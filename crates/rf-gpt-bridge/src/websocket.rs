// file: crates/rf-gpt-bridge/src/websocket.rs
//! WebSocket Server — the neural pathway between CORTEX and ChatGPT Browser.
//!
//! Runs a local WebSocket server on localhost:9742.
//! The Tampermonkey userscript in the browser connects here.
//!
//! Architecture:
//!   - One active browser connection at a time (last connection wins)
//!   - Outbound: BrowserCommand (queries for ChatGPT)
//!   - Inbound: BrowserEvent (responses from ChatGPT)
//!   - Heartbeat ping/pong for connection health monitoring

use crate::protocol::{BrowserCommand, BrowserEvent};
use crossbeam_channel::{Receiver, Sender};
use futures_util::{SinkExt, StreamExt};
use parking_lot::Mutex;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

/// Shared state for the WebSocket server.
pub struct WsServer {
    /// Channel to send commands TO the browser.
    cmd_tx: mpsc::UnboundedSender<BrowserCommand>,
    /// Channel to receive events FROM the browser (bridged to crossbeam for sync access).
    event_rx: Receiver<BrowserEvent>,
    /// Event sender (given to async tasks).
    event_tx: Sender<BrowserEvent>,
    /// Is a browser currently connected?
    browser_connected: Arc<AtomicBool>,
    /// Browser user agent (if connected).
    browser_info: Arc<Mutex<Option<BrowserInfo>>>,
    /// Total commands sent.
    pub total_commands_sent: Arc<AtomicU64>,
    /// Total events received.
    pub total_events_received: Arc<AtomicU64>,
    /// Last ping latency in ms.
    pub last_ping_latency_ms: Arc<AtomicI64>,
    /// Shutdown flag.
    shutdown: Arc<AtomicBool>,
}

/// Info about the connected browser.
#[derive(Debug, Clone)]
pub struct BrowserInfo {
    pub user_agent: String,
    pub model: Option<String>,
    pub connected_at: chrono::DateTime<chrono::Utc>,
}

impl WsServer {
    /// Create a new WebSocket server (does NOT start listening yet).
    pub fn new() -> Self {
        let (cmd_tx, _cmd_rx) = mpsc::unbounded_channel();
        let (event_tx, event_rx) = crossbeam_channel::bounded(256);

        // We'll create the real cmd channel when we start
        // For now, store the event channel
        Self {
            cmd_tx,
            event_rx,
            event_tx,
            browser_connected: Arc::new(AtomicBool::new(false)),
            browser_info: Arc::new(Mutex::new(None)),
            total_commands_sent: Arc::new(AtomicU64::new(0)),
            total_events_received: Arc::new(AtomicU64::new(0)),
            last_ping_latency_ms: Arc::new(AtomicI64::new(-1)),
            shutdown: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Start the WebSocket server on the given address.
    /// Returns a handle that can be used to spawn the server on a tokio runtime.
    pub fn start(&mut self, addr: SocketAddr, handle: &tokio::runtime::Handle) {
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        self.cmd_tx = cmd_tx;

        let event_tx = self.event_tx.clone();
        let connected = Arc::clone(&self.browser_connected);
        let info = Arc::clone(&self.browser_info);
        let total_events = Arc::clone(&self.total_events_received);
        let total_cmds = Arc::clone(&self.total_commands_sent);
        let ping_latency = Arc::clone(&self.last_ping_latency_ms);
        let shutdown = Arc::clone(&self.shutdown);

        handle.spawn(Self::run_server(
            addr,
            cmd_rx,
            event_tx,
            connected,
            info,
            total_events,
            total_cmds,
            ping_latency,
            shutdown,
        ));
    }

    /// Send a command to the browser.
    pub fn send_command(&self, cmd: BrowserCommand) -> Result<(), crate::protocol::GptError> {
        if !self.browser_connected.load(Ordering::Relaxed) {
            return Err(crate::protocol::GptError::BrowserNotConnected);
        }

        self.cmd_tx.send(cmd).map_err(|_| crate::protocol::GptError::WebSocketError {
            message: "Command channel closed".into(),
        })?;

        self.total_commands_sent.fetch_add(1, Ordering::Relaxed);
        Ok(())
    }

    /// Drain all pending events from the browser.
    pub fn drain_events(&self) -> Vec<BrowserEvent> {
        let mut events = Vec::new();
        while let Ok(event) = self.event_rx.try_recv() {
            events.push(event);
        }
        events
    }

    /// Is a browser currently connected?
    pub fn is_browser_connected(&self) -> bool {
        self.browser_connected.load(Ordering::Relaxed)
    }

    /// Get info about the connected browser.
    pub fn browser_info(&self) -> Option<BrowserInfo> {
        self.browser_info.lock().clone()
    }

    /// Signal shutdown.
    pub fn shutdown(&self) {
        self.shutdown.store(true, Ordering::Relaxed);
        self.browser_connected.store(false, Ordering::Relaxed);
    }

    // ─── Internal: async server loop ──────────────────────────────────────

    async fn run_server(
        addr: SocketAddr,
        cmd_rx: mpsc::UnboundedReceiver<BrowserCommand>,
        event_tx: Sender<BrowserEvent>,
        connected: Arc<AtomicBool>,
        info: Arc<Mutex<Option<BrowserInfo>>>,
        total_events: Arc<AtomicU64>,
        total_cmds: Arc<AtomicU64>,
        ping_latency: Arc<AtomicI64>,
        shutdown: Arc<AtomicBool>,
    ) {
        let listener = match TcpListener::bind(addr).await {
            Ok(l) => {
                log::info!("GPT Browser Bridge: WebSocket server listening on ws://{}", addr);
                l
            }
            Err(e) => {
                log::error!("GPT Browser Bridge: failed to bind to {}: {}", addr, e);
                return;
            }
        };

        // Wrap cmd_rx in Arc<Mutex> so we can replace it per connection
        let cmd_rx = Arc::new(tokio::sync::Mutex::new(cmd_rx));

        loop {
            if shutdown.load(Ordering::Relaxed) {
                log::info!("GPT Browser Bridge: shutting down WebSocket server");
                break;
            }

            tokio::select! {
                accept = listener.accept() => {
                    match accept {
                        Ok((stream, peer)) => {
                            log::info!("GPT Browser Bridge: browser connected from {}", peer);

                            // Handle connection (last connection wins — previous is dropped)
                            let event_tx = event_tx.clone();
                            let connected = Arc::clone(&connected);
                            let info = Arc::clone(&info);
                            let total_events = Arc::clone(&total_events);
                            let total_cmds = Arc::clone(&total_cmds);
                            let ping_latency = Arc::clone(&ping_latency);
                            let shutdown = Arc::clone(&shutdown);
                            let cmd_rx = Arc::clone(&cmd_rx);

                            tokio::spawn(async move {
                                Self::handle_connection(
                                    stream,
                                    peer,
                                    cmd_rx,
                                    event_tx,
                                    connected,
                                    info,
                                    total_events,
                                    total_cmds,
                                    ping_latency,
                                    shutdown,
                                ).await;
                            });
                        }
                        Err(e) => {
                            log::error!("GPT Browser Bridge: accept error: {}", e);
                        }
                    }
                }
                _ = tokio::time::sleep(std::time::Duration::from_secs(1)) => {
                    // Periodic check for shutdown
                }
            }
        }
    }

    async fn handle_connection(
        stream: TcpStream,
        peer: SocketAddr,
        cmd_rx: Arc<tokio::sync::Mutex<mpsc::UnboundedReceiver<BrowserCommand>>>,
        event_tx: Sender<BrowserEvent>,
        connected: Arc<AtomicBool>,
        info: Arc<Mutex<Option<BrowserInfo>>>,
        total_events: Arc<AtomicU64>,
        total_cmds: Arc<AtomicU64>,
        ping_latency: Arc<AtomicI64>,
        shutdown: Arc<AtomicBool>,
    ) {
        let ws_stream = match tokio_tungstenite::accept_async(stream).await {
            Ok(ws) => ws,
            Err(e) => {
                log::error!("GPT Browser Bridge: WebSocket handshake failed for {}: {}", peer, e);
                return;
            }
        };

        connected.store(true, Ordering::Relaxed);
        let (mut ws_sink, mut ws_stream_rx) = ws_stream.split();

        // Lock the command receiver for this connection
        let mut cmd_rx_guard = cmd_rx.lock().await;

        // Ping interval
        let mut ping_interval = tokio::time::interval(std::time::Duration::from_secs(15));
        ping_interval.tick().await; // Skip first immediate tick

        loop {
            if shutdown.load(Ordering::Relaxed) {
                break;
            }

            tokio::select! {
                // Receive from browser
                msg = ws_stream_rx.next() => {
                    match msg {
                        Some(Ok(Message::Text(text))) => {
                            match serde_json::from_str::<BrowserEvent>(&text) {
                                Ok(event) => {
                                    total_events.fetch_add(1, Ordering::Relaxed);

                                    // Handle special events
                                    match &event {
                                        BrowserEvent::Connected { user_agent, model } => {
                                            *info.lock() = Some(BrowserInfo {
                                                user_agent: user_agent.clone(),
                                                model: model.clone(),
                                                connected_at: chrono::Utc::now(),
                                            });
                                            log::info!(
                                                "GPT Browser Bridge: browser identified — {} (model: {:?})",
                                                user_agent,
                                                model
                                            );
                                        }
                                        BrowserEvent::Pong { ts } => {
                                            let now = chrono::Utc::now().timestamp_millis();
                                            let latency = now - ts;
                                            ping_latency.store(latency, Ordering::Relaxed);
                                        }
                                        _ => {}
                                    }

                                    // Forward to bridge
                                    if event_tx.try_send(event).is_err() {
                                        log::warn!("GPT Browser Bridge: event queue full, dropping event");
                                    }
                                }
                                Err(e) => {
                                    log::warn!("GPT Browser Bridge: invalid JSON from browser: {} — {}", e, text);
                                }
                            }
                        }
                        Some(Ok(Message::Close(_))) | None => {
                            log::info!("GPT Browser Bridge: browser disconnected ({})", peer);
                            break;
                        }
                        Some(Err(e)) => {
                            log::error!("GPT Browser Bridge: WebSocket error: {}", e);
                            break;
                        }
                        _ => {} // Binary, Ping, Pong frames handled by tungstenite
                    }
                }

                // Send commands to browser
                cmd = cmd_rx_guard.recv() => {
                    match cmd {
                        Some(command) => {
                            match serde_json::to_string(&command) {
                                Ok(json) => {
                                    if let Err(e) = ws_sink.send(Message::Text(json.into())).await {
                                        log::error!("GPT Browser Bridge: failed to send command: {}", e);
                                        break;
                                    }
                                    total_cmds.fetch_add(1, Ordering::Relaxed);
                                }
                                Err(e) => {
                                    log::error!("GPT Browser Bridge: failed to serialize command: {}", e);
                                }
                            }
                        }
                        None => {
                            // Command channel closed
                            break;
                        }
                    }
                }

                // Periodic ping
                _ = ping_interval.tick() => {
                    let ts = chrono::Utc::now().timestamp_millis();
                    let ping = BrowserCommand::Ping { ts };
                    if let Ok(json) = serde_json::to_string(&ping) {
                        if let Err(e) = ws_sink.send(Message::Text(json.into())).await {
                            log::warn!("GPT Browser Bridge: ping failed: {}", e);
                            break;
                        }
                    }
                }
            }
        }

        // Cleanup on disconnect
        connected.store(false, Ordering::Relaxed);
        *info.lock() = None;
        ping_latency.store(-1, Ordering::Relaxed);
        log::info!("GPT Browser Bridge: connection handler finished for {}", peer);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ws_server_creates() {
        let server = WsServer::new();
        assert!(!server.is_browser_connected());
        assert!(server.browser_info().is_none());
        assert!(server.drain_events().is_empty());
    }

    #[test]
    fn send_command_fails_without_browser() {
        let server = WsServer::new();
        let cmd = BrowserCommand::Ping { ts: 0 };
        let result = server.send_command(cmd);
        assert!(result.is_err());
    }

    #[test]
    fn shutdown_clears_state() {
        let server = WsServer::new();
        server.browser_connected.store(true, Ordering::Relaxed);
        assert!(server.is_browser_connected());

        server.shutdown();
        assert!(!server.is_browser_connected());
    }
}

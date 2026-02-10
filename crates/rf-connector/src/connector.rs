//! Engine Connector — WebSocket/TCP connection to game engines

use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;
use tokio::sync::{broadcast, mpsc, RwLock};
use tokio_tungstenite::{connect_async, tungstenite::Message};

use crate::commands::EngineCommand;
use crate::protocol::{ConnectionConfig, ConnectionState, EngineMessage, ProtocolFrame};
use rf_stage::event::StageEvent;

/// Engine connector for live stage streaming
pub struct EngineConnector {
    /// Connection configuration
    config: ConnectionConfig,

    /// Current connection state
    state: Arc<RwLock<ConnectionState>>,

    /// Channel for incoming stage events
    event_tx: broadcast::Sender<StageEvent>,

    /// Channel for outgoing commands
    command_tx: mpsc::Sender<EngineCommand>,
    command_rx: Arc<RwLock<Option<mpsc::Receiver<EngineCommand>>>>,

    /// Channel for raw engine messages
    message_tx: broadcast::Sender<EngineMessage>,

    /// Connection task handle
    connection_handle: Arc<RwLock<Option<tokio::task::JoinHandle<()>>>>,

    /// Shutdown signal
    shutdown_tx: broadcast::Sender<()>,
}

impl EngineConnector {
    /// Create a new connector with config
    pub fn new(config: ConnectionConfig) -> Self {
        let (event_tx, _) = broadcast::channel(256);
        let (message_tx, _) = broadcast::channel(256);
        let (command_tx, command_rx) = mpsc::channel(64);
        let (shutdown_tx, _) = broadcast::channel(1);

        Self {
            config,
            state: Arc::new(RwLock::new(ConnectionState::Disconnected)),
            event_tx,
            command_tx,
            command_rx: Arc::new(RwLock::new(Some(command_rx))),
            message_tx,
            connection_handle: Arc::new(RwLock::new(None)),
            shutdown_tx,
        }
    }

    /// Get the current connection state
    pub async fn state(&self) -> ConnectionState {
        *self.state.read().await
    }

    /// Connect to the engine
    pub async fn connect(&mut self) -> Result<(), ConnectorError> {
        // Update state
        *self.state.write().await = ConnectionState::Connecting;

        // Clone protocol info to avoid borrow issues
        let protocol = self.config.protocol.clone();

        // Try to connect based on protocol
        match protocol {
            crate::protocol::Protocol::WebSocket { url } => {
                self.connect_websocket(&url).await?;
            }
            crate::protocol::Protocol::Tcp { host, port } => {
                self.connect_tcp(&host, port).await?;
            }
        }

        *self.state.write().await = ConnectionState::Connected;
        Ok(())
    }

    /// Disconnect from the engine
    pub async fn disconnect(&mut self) -> Result<(), ConnectorError> {
        *self.state.write().await = ConnectionState::Disconnecting;
        // Close connections...
        *self.state.write().await = ConnectionState::Disconnected;
        Ok(())
    }

    /// Subscribe to stage events
    pub fn subscribe_events(&self) -> broadcast::Receiver<StageEvent> {
        self.event_tx.subscribe()
    }

    /// Subscribe to raw engine messages
    pub fn subscribe_messages(&self) -> broadcast::Receiver<EngineMessage> {
        self.message_tx.subscribe()
    }

    /// Send a command to the engine
    pub async fn send_command(&self, command: EngineCommand) -> Result<(), ConnectorError> {
        self.command_tx
            .send(command)
            .await
            .map_err(|_| ConnectorError::SendFailed)
    }

    /// Request the engine to play a specific spin
    pub async fn request_spin(&self, spin_id: &str) -> Result<(), ConnectorError> {
        self.send_command(EngineCommand::PlaySpin {
            spin_id: spin_id.to_string(),
        })
        .await
    }

    /// Request the engine to pause
    pub async fn request_pause(&self) -> Result<(), ConnectorError> {
        self.send_command(EngineCommand::Pause).await
    }

    /// Request the engine to resume
    pub async fn request_resume(&self) -> Result<(), ConnectorError> {
        self.send_command(EngineCommand::Resume).await
    }

    /// Request the engine to seek to a timestamp
    pub async fn request_seek(&self, timestamp_ms: f64) -> Result<(), ConnectorError> {
        self.send_command(EngineCommand::Seek { timestamp_ms })
            .await
    }

    /// Set timing profile
    pub async fn set_timing_profile(&self, profile: &str) -> Result<(), ConnectorError> {
        self.send_command(EngineCommand::SetTimingProfile {
            profile: profile.to_string(),
        })
        .await
    }

    // Internal connection methods

    async fn connect_websocket(&mut self, url: &str) -> Result<(), ConnectorError> {
        // Validate URL format
        let _ = url::Url::parse(url)
            .map_err(|e| ConnectorError::ConnectionFailed(format!("Invalid URL: {}", e)))?;

        let timeout = Duration::from_millis(self.config.timeout_ms as u64);

        // Connect with timeout - tokio-tungstenite accepts &str directly
        let ws_stream = tokio::time::timeout(timeout, connect_async(url))
            .await
            .map_err(|_| ConnectorError::Timeout)?
            .map_err(|e| ConnectorError::ConnectionFailed(format!("WebSocket error: {}", e)))?
            .0;

        let (mut write, mut read) = ws_stream.split();

        // Send auth if configured
        if let Some(token) = &self.config.auth_token {
            let auth_frame = ProtocolFrame::auth(token);
            let json = serde_json::to_string(&auth_frame)
                .map_err(|e| ConnectorError::Protocol(e.to_string()))?;
            write
                .send(Message::Text(json))
                .await
                .map_err(|e| ConnectorError::ConnectionFailed(e.to_string()))?;
        }

        // Take command receiver
        let command_rx = self.command_rx.write().await.take();
        let mut command_rx = command_rx
            .ok_or_else(|| ConnectorError::ConnectionFailed("Already connected".into()))?;

        let event_tx = self.event_tx.clone();
        let message_tx = self.message_tx.clone();
        let state = Arc::clone(&self.state);
        let mut shutdown_rx = self.shutdown_tx.subscribe();

        // Spawn connection task
        let handle = tokio::spawn(async move {
            loop {
                tokio::select! {
                    // Receive from WebSocket
                    msg = read.next() => {
                        match msg {
                            Some(Ok(Message::Text(text))) => {
                                Self::handle_message(&text, &event_tx, &message_tx);
                            }
                            Some(Ok(Message::Close(_))) | None => {
                                *state.write().await = ConnectionState::Disconnected;
                                break;
                            }
                            Some(Err(e)) => {
                                log::error!("[Connector] WebSocket error: {}", e);
                                *state.write().await = ConnectionState::Error;
                                break;
                            }
                            _ => {} // Ignore ping/pong/binary
                        }
                    }

                    // Send commands
                    cmd = command_rx.recv() => {
                        if let Some(cmd) = cmd {
                            let frame = ProtocolFrame::command(
                                &uuid::Uuid::new_v4().to_string(),
                                serde_json::to_value(&cmd).unwrap_or_default(),
                            );
                            if let Ok(json) = serde_json::to_string(&frame) {
                                if write.send(Message::Text(json)).await.is_err() {
                                    break;
                                }
                            }
                        }
                    }

                    // Shutdown signal
                    _ = shutdown_rx.recv() => {
                        let _ = write.send(Message::Close(None)).await;
                        break;
                    }
                }
            }
        });

        *self.connection_handle.write().await = Some(handle);
        Ok(())
    }

    async fn connect_tcp(&mut self, host: &str, port: u16) -> Result<(), ConnectorError> {
        let addr = format!("{}:{}", host, port);
        let timeout = Duration::from_millis(self.config.timeout_ms as u64);

        // Connect with timeout
        let stream = tokio::time::timeout(timeout, TcpStream::connect(&addr))
            .await
            .map_err(|_| ConnectorError::Timeout)?
            .map_err(|e| ConnectorError::ConnectionFailed(e.to_string()))?;

        let (read_half, mut write_half) = stream.into_split();
        let mut reader = BufReader::new(read_half);

        // Send auth if configured
        if let Some(token) = &self.config.auth_token {
            let auth_frame = ProtocolFrame::auth(token);
            let json = serde_json::to_string(&auth_frame)
                .map_err(|e| ConnectorError::Protocol(e.to_string()))?;
            write_half
                .write_all(format!("{}\n", json).as_bytes())
                .await
                .map_err(|e| ConnectorError::ConnectionFailed(e.to_string()))?;
        }

        // Take command receiver
        let command_rx = self.command_rx.write().await.take();
        let mut command_rx = command_rx
            .ok_or_else(|| ConnectorError::ConnectionFailed("Already connected".into()))?;

        let event_tx = self.event_tx.clone();
        let message_tx = self.message_tx.clone();
        let state = Arc::clone(&self.state);
        let mut shutdown_rx = self.shutdown_tx.subscribe();

        // Spawn connection task
        let handle = tokio::spawn(async move {
            let mut line = String::new();

            loop {
                tokio::select! {
                    // Read line from TCP
                    result = reader.read_line(&mut line) => {
                        match result {
                            Ok(0) => {
                                // EOF - connection closed
                                *state.write().await = ConnectionState::Disconnected;
                                break;
                            }
                            Ok(_) => {
                                Self::handle_message(line.trim(), &event_tx, &message_tx);
                                line.clear();
                            }
                            Err(e) => {
                                log::error!("[Connector] TCP read error: {}", e);
                                *state.write().await = ConnectionState::Error;
                                break;
                            }
                        }
                    }

                    // Send commands
                    cmd = command_rx.recv() => {
                        if let Some(cmd) = cmd {
                            let frame = ProtocolFrame::command(
                                &uuid::Uuid::new_v4().to_string(),
                                serde_json::to_value(&cmd).unwrap_or_default(),
                            );
                            if let Ok(json) = serde_json::to_string(&frame) {
                                if write_half.write_all(format!("{}\n", json).as_bytes()).await.is_err() {
                                    break;
                                }
                            }
                        }
                    }

                    // Shutdown signal
                    _ = shutdown_rx.recv() => {
                        break;
                    }
                }
            }
        });

        *self.connection_handle.write().await = Some(handle);
        Ok(())
    }

    /// Handle incoming message and dispatch to appropriate channels
    fn handle_message(
        text: &str,
        event_tx: &broadcast::Sender<StageEvent>,
        message_tx: &broadcast::Sender<EngineMessage>,
    ) {
        // Parse JSON
        let Ok(json): Result<serde_json::Value, _> = serde_json::from_str(text) else {
            log::warn!("[Connector] Invalid JSON: {}", text);
            return;
        };

        // Create raw message
        let msg_type = json
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        let message = EngineMessage::new(msg_type, json.clone());
        let _ = message_tx.send(message);

        // Try to parse as stage event
        if msg_type == "stage_event" || json.get("stage").is_some() {
            if let Some(stage_data) = json.get("stage").or(json.get("data")) {
                if let Ok(event) = serde_json::from_value::<StageEvent>(stage_data.clone()) {
                    let _ = event_tx.send(event);
                }
            }
        }
    }
}

/// Connector builder
pub struct ConnectorBuilder {
    config: ConnectionConfig,
    auto_reconnect: bool,
    reconnect_delay: Duration,
}

impl ConnectorBuilder {
    /// Create builder with WebSocket URL
    pub fn websocket(url: &str) -> Self {
        Self {
            config: ConnectionConfig {
                protocol: crate::protocol::Protocol::WebSocket {
                    url: url.to_string(),
                },
                adapter_id: "generic".to_string(),
                auth_token: None,
                timeout_ms: 5000,
            },
            auto_reconnect: true,
            reconnect_delay: Duration::from_secs(2),
        }
    }

    /// Create builder with TCP connection
    pub fn tcp(host: &str, port: u16) -> Self {
        Self {
            config: ConnectionConfig {
                protocol: crate::protocol::Protocol::Tcp {
                    host: host.to_string(),
                    port,
                },
                adapter_id: "generic".to_string(),
                auth_token: None,
                timeout_ms: 5000,
            },
            auto_reconnect: true,
            reconnect_delay: Duration::from_secs(2),
        }
    }

    /// Set adapter ID
    pub fn adapter(mut self, adapter_id: &str) -> Self {
        self.config.adapter_id = adapter_id.to_string();
        self
    }

    /// Set auth token
    pub fn auth(mut self, token: &str) -> Self {
        self.config.auth_token = Some(token.to_string());
        self
    }

    /// Set connection timeout
    pub fn timeout(mut self, timeout_ms: u32) -> Self {
        self.config.timeout_ms = timeout_ms;
        self
    }

    /// Enable/disable auto reconnect
    pub fn auto_reconnect(mut self, enabled: bool) -> Self {
        self.auto_reconnect = enabled;
        self
    }

    /// Set reconnect delay
    pub fn reconnect_delay(mut self, delay: Duration) -> Self {
        self.reconnect_delay = delay;
        self
    }

    /// Build the connector
    pub fn build(self) -> EngineConnector {
        EngineConnector::new(self.config)
    }
}

/// Connector errors
#[derive(Debug, thiserror::Error)]
pub enum ConnectorError {
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),

    #[error("Connection timeout")]
    Timeout,

    #[error("Authentication failed")]
    AuthFailed,

    #[error("Failed to send command")]
    SendFailed,

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_connector_builder() {
        let connector = ConnectorBuilder::websocket("ws://localhost:8080")
            .adapter("test-adapter")
            .timeout(3000)
            .auto_reconnect(true)
            .build();

        assert_eq!(connector.state().await, ConnectionState::Disconnected);
    }

    #[tokio::test]
    async fn test_builder_websocket() {
        let connector = ConnectorBuilder::websocket("ws://localhost:8080").build();
        match connector.config.protocol {
            crate::protocol::Protocol::WebSocket { ref url } => {
                assert_eq!(url, "ws://localhost:8080");
            }
            _ => panic!("Expected WebSocket protocol"),
        }
    }

    #[tokio::test]
    async fn test_builder_tcp() {
        let connector = ConnectorBuilder::tcp("localhost", 9090).build();
        match connector.config.protocol {
            crate::protocol::Protocol::Tcp { ref host, port } => {
                assert_eq!(host, "localhost");
                assert_eq!(port, 9090);
            }
            _ => panic!("Expected TCP protocol"),
        }
    }

    #[tokio::test]
    async fn test_builder_auth() {
        let connector = ConnectorBuilder::websocket("ws://localhost:8080")
            .auth("token123")
            .build();
        assert_eq!(connector.config.auth_token, Some("token123".to_string()));
    }

    #[tokio::test]
    async fn test_builder_timeout() {
        let connector = ConnectorBuilder::websocket("ws://localhost:8080")
            .timeout(5000)
            .build();
        assert_eq!(connector.config.timeout_ms, 5000);
    }

    #[tokio::test]
    async fn test_builder_auto_reconnect() {
        let builder = ConnectorBuilder::websocket("ws://localhost:8080")
            .auto_reconnect(true);
        assert!(builder.auto_reconnect);

        let builder2 = ConnectorBuilder::websocket("ws://localhost:8080")
            .auto_reconnect(false);
        assert!(!builder2.auto_reconnect);
    }

    #[tokio::test]
    async fn test_builder_adapter() {
        let connector = ConnectorBuilder::websocket("ws://localhost:8080")
            .adapter("my-adapter")
            .build();
        assert_eq!(connector.config.adapter_id, "my-adapter");
    }

    #[tokio::test]
    async fn test_builder_chaining() {
        let connector = ConnectorBuilder::websocket("ws://test:1234")
            .adapter("chain-adapter")
            .auth("secret")
            .timeout(10000)
            .auto_reconnect(false)
            .reconnect_delay(Duration::from_secs(5))
            .build();

        assert_eq!(connector.config.adapter_id, "chain-adapter");
        assert_eq!(connector.config.auth_token, Some("secret".to_string()));
        assert_eq!(connector.config.timeout_ms, 10000);
        match connector.config.protocol {
            crate::protocol::Protocol::WebSocket { ref url } => {
                assert_eq!(url, "ws://test:1234");
            }
            _ => panic!("Expected WebSocket protocol"),
        }
        assert_eq!(connector.state().await, ConnectionState::Disconnected);
    }

}

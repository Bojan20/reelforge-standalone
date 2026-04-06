//! CORTEX Bridge Daemon Server
//!
//! Two servers running concurrently:
//!   1. WebSocket (port 9742) — Chrome extension connects here
//!   2. HTTP API (port 9743) — CLI/scripts send queries, check status
//!
//! Architecture:
//!   HTTP POST /query → generates BrowserCommand::Query → WS → Chrome extension
//!   Chrome extension → BrowserEvent::Response → WS → stored → returned to HTTP caller

use crate::protocol::{BrowserCommand, BrowserEvent};
use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, Mutex, Notify, RwLock};
use tokio_tungstenite::tungstenite::Message;

/// Shared daemon state.
pub struct DaemonState {
    /// Channel to send commands to the browser.
    cmd_tx: mpsc::UnboundedSender<BrowserCommand>,
    /// Is browser connected?
    browser_connected: AtomicBool,
    /// Browser model name.
    browser_model: RwLock<Option<String>>,
    /// Browser user agent.
    browser_agent: RwLock<Option<String>>,
    /// Pending responses: request_id → (notify, content).
    pending: Mutex<HashMap<String, PendingQuery>>,
    /// Stats.
    total_queries: AtomicU64,
    total_responses: AtomicU64,
    total_errors: AtomicU64,
    reconnects: AtomicU64,
    ping_latency_ms: AtomicI64,
    /// Uptime start.
    started_at: chrono::DateTime<chrono::Utc>,
}

struct PendingQuery {
    notify: Arc<Notify>,
    content: Option<String>,
}

impl DaemonState {
    fn new(cmd_tx: mpsc::UnboundedSender<BrowserCommand>) -> Self {
        Self {
            cmd_tx,
            browser_connected: AtomicBool::new(false),
            browser_model: RwLock::new(None),
            browser_agent: RwLock::new(None),
            pending: Mutex::new(HashMap::new()),
            total_queries: AtomicU64::new(0),
            total_responses: AtomicU64::new(0),
            total_errors: AtomicU64::new(0),
            reconnects: AtomicU64::new(0),
            ping_latency_ms: AtomicI64::new(-1),
            started_at: chrono::Utc::now(),
        }
    }
}

/// Run the daemon — blocks forever.
pub async fn run_daemon(ws_port: u16, api_port: u16) {
    let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
    let state = Arc::new(DaemonState::new(cmd_tx));

    log::info!("╔══════════════════════════════════════════════════╗");
    log::info!("║      CORTEX Bridge Daemon — Corti ↔ ChatGPT     ║");
    log::info!("╠══════════════════════════════════════════════════╣");
    log::info!("║  WebSocket : ws://127.0.0.1:{:<5}              ║", ws_port);
    log::info!("║  HTTP API  : http://127.0.0.1:{:<5}             ║", api_port);
    log::info!("╚══════════════════════════════════════════════════╝");
    log::info!("");
    log::info!("Čekam browser konekciju (Chrome extension)...");

    // Run both servers + signal handler concurrently
    let ws_state = Arc::clone(&state);
    let api_state = Arc::clone(&state);

    tokio::select! {
        _ = run_ws_server(ws_port, cmd_rx, ws_state) => {
            log::info!("WebSocket server stopped");
        }
        _ = run_http_api(api_port, api_state) => {
            log::info!("HTTP API stopped");
        }
        _ = tokio::signal::ctrl_c() => {
            log::info!("CORTEX Bridge Daemon shutting down (Ctrl+C)");
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEBSOCKET SERVER — Chrome extension connects here
// ═══════════════════════════════════════════════════════════════════════════════

async fn run_ws_server(
    port: u16,
    cmd_rx: mpsc::UnboundedReceiver<BrowserCommand>,
    state: Arc<DaemonState>,
) {
    let addr: SocketAddr = format!("127.0.0.1:{}", port).parse().unwrap();
    let listener = match TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            log::error!("Failed to bind WebSocket server to {}: {}", addr, e);
            log::error!("Is another instance already running?");
            return;
        }
    };

    log::info!("WebSocket server listening on ws://{}", addr);

    let cmd_rx = Arc::new(tokio::sync::Mutex::new(cmd_rx));

    loop {
        match listener.accept().await {
            Ok((stream, peer)) => {
                log::info!("Browser connected from {}", peer);
                state.reconnects.fetch_add(1, Ordering::Relaxed);
                state.browser_connected.store(true, Ordering::Relaxed);

                let state = Arc::clone(&state);
                let cmd_rx = Arc::clone(&cmd_rx);

                tokio::spawn(async move {
                    handle_browser_connection(stream, peer, cmd_rx, state).await;
                });
            }
            Err(e) => {
                log::error!("Accept error: {}", e);
            }
        }
    }
}

async fn handle_browser_connection(
    stream: TcpStream,
    peer: SocketAddr,
    cmd_rx: Arc<tokio::sync::Mutex<mpsc::UnboundedReceiver<BrowserCommand>>>,
    state: Arc<DaemonState>,
) {
    let ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            log::error!("WebSocket handshake failed for {}: {}", peer, e);
            return;
        }
    };

    let (mut ws_sink, mut ws_source) = ws_stream.split();
    let mut cmd_rx_guard = cmd_rx.lock().await;
    let mut ping_interval = tokio::time::interval(std::time::Duration::from_secs(15));
    ping_interval.tick().await;

    loop {
        tokio::select! {
            // Receive from browser
            msg = ws_source.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        handle_browser_message(&text, &state).await;
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        log::info!("Browser disconnected ({})", peer);
                        break;
                    }
                    Some(Err(e)) => {
                        log::error!("WebSocket error: {}", e);
                        break;
                    }
                    _ => {}
                }
            }

            // Send commands to browser
            cmd = cmd_rx_guard.recv() => {
                match cmd {
                    Some(command) => {
                        match serde_json::to_string(&command) {
                            Ok(json) => {
                                if let Err(e) = ws_sink.send(Message::Text(json.into())).await {
                                    log::error!("Failed to send to browser: {}", e);
                                    break;
                                }
                            }
                            Err(e) => log::error!("Serialize error: {}", e),
                        }
                    }
                    None => break,
                }
            }

            // Ping
            _ = ping_interval.tick() => {
                let ts = chrono::Utc::now().timestamp_millis();
                let ping = BrowserCommand::Ping { ts };
                if let Ok(json) = serde_json::to_string(&ping) {
                    if ws_sink.send(Message::Text(json.into())).await.is_err() {
                        break;
                    }
                }
            }
        }
    }

    // Cleanup
    state.browser_connected.store(false, Ordering::Relaxed);
    *state.browser_model.write().await = None;
    *state.browser_agent.write().await = None;
    state.ping_latency_ms.store(-1, Ordering::Relaxed);
    log::info!("Connection closed for {}", peer);
}

async fn handle_browser_message(text: &str, state: &Arc<DaemonState>) {
    let event: BrowserEvent = match serde_json::from_str(text) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Invalid JSON from browser: {} — {}", e, text);
            return;
        }
    };

    match event {
        BrowserEvent::Response { id, content, streaming } => {
            if streaming {
                // Partial update — log but don't resolve yet
                log::debug!("Streaming partial for {}: {} chars", id, content.len());
                return;
            }

            log::info!("Response received for {} ({} chars)", id, content.len());
            state.total_responses.fetch_add(1, Ordering::Relaxed);

            // Resolve pending query
            let mut pending = state.pending.lock().await;
            if let Some(mut pq) = pending.remove(&id) {
                pq.content = Some(content);
                // Re-insert with content so the waiter can read it
                let notify = Arc::clone(&pq.notify);
                pending.insert(id, pq);
                notify.notify_one();
            }
        }

        BrowserEvent::Connected { user_agent, model } => {
            log::info!("Browser identified: {} (model: {:?})", user_agent, model);
            *state.browser_agent.write().await = Some(user_agent);
            *state.browser_model.write().await = model;
        }

        BrowserEvent::Pong { ts } => {
            let now = chrono::Utc::now().timestamp_millis();
            let latency = now - ts;
            state.ping_latency_ms.store(latency, Ordering::Relaxed);
            log::debug!("Ping latency: {}ms", latency);
        }

        BrowserEvent::Error { id, message, code } => {
            log::error!("Browser error: [{}] {} (id: {:?})", code, message, id);
            state.total_errors.fetch_add(1, Ordering::Relaxed);

            if let Some(request_id) = id {
                let mut pending = state.pending.lock().await;
                if let Some(mut pq) = pending.remove(&request_id) {
                    pq.content = Some(format!("[ERROR: {}] {}", code, message));
                    let notify = Arc::clone(&pq.notify);
                    pending.insert(request_id, pq);
                    notify.notify_one();
                }
            }
        }

        BrowserEvent::Busy { id } => {
            log::warn!("ChatGPT busy, request {} waiting...", id);
        }

        BrowserEvent::ChatCleared => {
            log::info!("ChatGPT conversation cleared");
        }

        BrowserEvent::Status { ready, model, message_count } => {
            log::debug!("Browser status: ready={}, model={:?}, msgs={}", ready, model, message_count);
            if let Some(m) = model {
                *state.browser_model.write().await = Some(m);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HTTP API — CLI/scripts send queries here
// ═══════════════════════════════════════════════════════════════════════════════

async fn run_http_api(port: u16, state: Arc<DaemonState>) {
    let addr: SocketAddr = format!("127.0.0.1:{}", port).parse().unwrap();
    let listener = match TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            log::error!("Failed to bind HTTP API to {}: {}", addr, e);
            return;
        }
    };

    log::info!("HTTP API listening on http://{}", addr);

    loop {
        let (stream, _) = match listener.accept().await {
            Ok(s) => s,
            Err(e) => {
                log::error!("HTTP accept error: {}", e);
                continue;
            }
        };

        let state = Arc::clone(&state);
        tokio::spawn(async move {
            handle_http_connection(stream, state).await;
        });
    }
}

async fn handle_http_connection(stream: TcpStream, state: Arc<DaemonState>) {
    use hyper::body::Incoming;
    use hyper::server::conn::http1;
    use hyper::service::service_fn;
    use hyper::Request;
    use hyper_util::rt::TokioIo;

    let io = TokioIo::new(stream);
    let state = Arc::clone(&state);

    let service = service_fn(move |req: Request<Incoming>| {
        let state = Arc::clone(&state);
        async move {
            handle_http_request(req, state).await
        }
    });

    if let Err(e) = http1::Builder::new().serve_connection(io, service).await {
        if !e.to_string().contains("connection closed") {
            log::error!("HTTP error: {}", e);
        }
    }
}

async fn handle_http_request(
    req: hyper::Request<hyper::body::Incoming>,
    state: Arc<DaemonState>,
) -> Result<hyper::Response<http_body_util::Full<hyper::body::Bytes>>, std::convert::Infallible> {
    use http_body_util::BodyExt;
    use hyper::{Method, StatusCode};

    let path = req.uri().path().to_string();
    let method = req.method().clone();

    match (method, path.as_str()) {
        (Method::GET, "/status") => {
            let model = state.browser_model.read().await.clone();
            let agent = state.browser_agent.read().await.clone();
            let uptime_secs = (chrono::Utc::now() - state.started_at).num_seconds();

            let json = serde_json::json!({
                "daemon": "running",
                "uptime_secs": uptime_secs,
                "browser_connected": state.browser_connected.load(Ordering::Relaxed),
                "browser_model": model,
                "browser_agent": agent,
                "ping_latency_ms": state.ping_latency_ms.load(Ordering::Relaxed),
                "total_queries": state.total_queries.load(Ordering::Relaxed),
                "total_responses": state.total_responses.load(Ordering::Relaxed),
                "total_errors": state.total_errors.load(Ordering::Relaxed),
                "reconnects": state.reconnects.load(Ordering::Relaxed),
            });

            Ok(json_response(StatusCode::OK, &json))
        }

        (Method::POST, "/query") => {
            // Read body
            let body_bytes = match req.into_body().collect().await {
                Ok(collected) => collected.to_bytes(),
                Err(e) => {
                    let err = serde_json::json!({"error": format!("Failed to read body: {}", e)});
                    return Ok(json_response(StatusCode::BAD_REQUEST, &err));
                }
            };

            #[derive(serde::Deserialize)]
            struct QueryRequest {
                content: String,
                intent: Option<String>,
                #[serde(default = "default_urgency")]
                urgency: f32,
                /// Timeout in seconds (default: 300 = 5 min)
                #[serde(default = "default_timeout")]
                timeout_secs: u64,
            }
            fn default_urgency() -> f32 { 0.8 }
            fn default_timeout() -> u64 { 300 }

            let query: QueryRequest = match serde_json::from_slice(&body_bytes) {
                Ok(q) => q,
                Err(e) => {
                    let err = serde_json::json!({"error": format!("Invalid JSON: {}", e)});
                    return Ok(json_response(StatusCode::BAD_REQUEST, &err));
                }
            };

            if !state.browser_connected.load(Ordering::Relaxed) {
                let err = serde_json::json!({
                    "error": "Browser not connected",
                    "hint": "Open ChatGPT in Chrome with CORTEX Bridge extension installed"
                });
                return Ok(json_response(StatusCode::SERVICE_UNAVAILABLE, &err));
            }

            let request_id = uuid::Uuid::new_v4().to_string();
            let intent = query.intent.unwrap_or_else(|| "user_query".into());

            // Register pending query
            let notify = Arc::new(Notify::new());
            {
                let mut pending = state.pending.lock().await;
                pending.insert(request_id.clone(), PendingQuery {
                    notify: Arc::clone(&notify),
                    content: None,
                });
            }

            // Send command to browser
            let cmd = BrowserCommand::Query {
                id: request_id.clone(),
                content: query.content.clone(),
                intent: intent.clone(),
                urgency: query.urgency,
            };

            if state.cmd_tx.send(cmd).is_err() {
                let err = serde_json::json!({"error": "Failed to send command to browser"});
                state.pending.lock().await.remove(&request_id);
                return Ok(json_response(StatusCode::INTERNAL_SERVER_ERROR, &err));
            }

            state.total_queries.fetch_add(1, Ordering::Relaxed);
            log::info!("Query sent: id={}, intent={}, {} chars",
                request_id, intent, query.content.len());

            // Wait for response with timeout
            let timeout = tokio::time::Duration::from_secs(query.timeout_secs);
            let result = tokio::time::timeout(timeout, notify.notified()).await;

            let response_content = {
                let mut pending = state.pending.lock().await;
                let pq = pending.remove(&request_id);
                pq.and_then(|p| p.content)
            };

            match (result.is_ok(), response_content) {
                (true, Some(content)) => {
                    let json = serde_json::json!({
                        "request_id": request_id,
                        "content": content,
                        "model": *state.browser_model.read().await,
                    });
                    Ok(json_response(StatusCode::OK, &json))
                }
                (false, _) => {
                    // Timeout
                    state.pending.lock().await.remove(&request_id);
                    let err = serde_json::json!({
                        "error": "Timeout waiting for ChatGPT response",
                        "request_id": request_id,
                        "timeout_secs": query.timeout_secs,
                    });
                    Ok(json_response(StatusCode::GATEWAY_TIMEOUT, &err))
                }
                (true, None) => {
                    let err = serde_json::json!({
                        "error": "Response was empty",
                        "request_id": request_id,
                    });
                    Ok(json_response(StatusCode::INTERNAL_SERVER_ERROR, &err))
                }
            }
        }

        (Method::POST, "/new_chat") => {
            if state.cmd_tx.send(BrowserCommand::NewChat).is_ok() {
                let json = serde_json::json!({"status": "new_chat_requested"});
                Ok(json_response(StatusCode::OK, &json))
            } else {
                let err = serde_json::json!({"error": "Failed to send new_chat command"});
                Ok(json_response(StatusCode::INTERNAL_SERVER_ERROR, &err))
            }
        }

        _ => {
            let err = serde_json::json!({
                "error": "Not found",
                "endpoints": {
                    "GET /status": "Check daemon and browser status",
                    "POST /query": "Send query to ChatGPT {content, intent?, urgency?, timeout_secs?}",
                    "POST /new_chat": "Start new ChatGPT conversation",
                }
            });
            Ok(json_response(StatusCode::NOT_FOUND, &err))
        }
    }
}

fn json_response(
    status: hyper::StatusCode,
    body: &serde_json::Value,
) -> hyper::Response<http_body_util::Full<hyper::body::Bytes>> {
    hyper::Response::builder()
        .status(status)
        .header("Content-Type", "application/json")
        .header("Access-Control-Allow-Origin", "*")
        .body(http_body_util::Full::new(hyper::body::Bytes::from(
            serde_json::to_string_pretty(body).unwrap_or_default(),
        )))
        .unwrap()
}

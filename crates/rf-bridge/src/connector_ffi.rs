//! Connector FFI — C bindings for rf-connector crate
//!
//! Exposes WebSocket/TCP live connections to Flutter/Dart.
//!
//! ## Architecture
//! - Async tokio runtime for non-blocking connections
//! - Event broadcast channel for real-time stage events
//! - Command queue for sending commands to engine
//! - Multiple connection support (one per connector_id)

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use rf_connector::commands::{EngineCapabilities, EngineCommand};
use rf_connector::connector::EngineConnector;
use rf_connector::protocol::{ConnectionConfig, ConnectionState, Protocol};
use rf_stage::event::StageEvent;
use tokio::runtime::Runtime;
use tokio::sync::broadcast;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Tokio runtime for async operations
static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("rf-connector")
        .enable_all()
        .build()
        .expect("Failed to create tokio runtime")
});

/// Active connectors (connector_id → ConnectorHandle)
static CONNECTORS: Lazy<RwLock<HashMap<u64, ConnectorHandle>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Next connector ID
static NEXT_CONNECTOR_ID: AtomicU64 = AtomicU64::new(1);

/// Global event callback (set by Flutter)
static EVENT_CALLBACK: Lazy<RwLock<Option<EventCallback>>> = Lazy::new(|| RwLock::new(None));

/// Event callback type: (connector_id, event_json)
type EventCallback = extern "C" fn(u64, *const c_char);

/// Connector handle with channels
struct ConnectorHandle {
    connector: Arc<RwLock<EngineConnector>>,
    config: ConnectionConfig,
    event_rx: broadcast::Receiver<StageEvent>,
    is_running: Arc<AtomicBool>,
    /// Cached capabilities from engine
    cached_capabilities: Arc<RwLock<Option<EngineCapabilities>>>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONNECTION API
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a WebSocket connector
/// url: WebSocket URL (e.g., "ws://localhost:8080")
/// Returns connector_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn connector_create_websocket(url: *const c_char) -> u64 {
    if url.is_null() {
        return 0;
    }

    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config = ConnectionConfig {
        protocol: Protocol::WebSocket {
            url: url_str.to_string(),
        },
        adapter_id: "generic".to_string(),
        auth_token: None,
        timeout_ms: 5000,
    };

    create_connector(config)
}

/// Create a TCP connector
/// host: TCP host (e.g., "127.0.0.1")
/// port: TCP port (e.g., 9000)
/// Returns connector_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn connector_create_tcp(host: *const c_char, port: u16) -> u64 {
    if host.is_null() {
        return 0;
    }

    let host_str = match unsafe { CStr::from_ptr(host) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config = ConnectionConfig {
        protocol: Protocol::Tcp {
            host: host_str.to_string(),
            port,
        },
        adapter_id: "generic".to_string(),
        auth_token: None,
        timeout_ms: 5000,
    };

    create_connector(config)
}

/// Create a connector with full config (JSON)
/// Returns connector_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn connector_create_config(config_json: *const c_char) -> u64 {
    if config_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(config_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config: ConnectionConfig = match serde_json::from_str(json_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("connector_create_config: parse error: {}", e);
            return 0;
        }
    };

    create_connector(config)
}

/// Internal: Create connector with config
fn create_connector(config: ConnectionConfig) -> u64 {
    let connector = EngineConnector::new(config.clone());
    let event_rx = connector.subscribe_events();

    let id = NEXT_CONNECTOR_ID.fetch_add(1, Ordering::Relaxed);
    let is_running = Arc::new(AtomicBool::new(false));

    let handle = ConnectorHandle {
        connector: Arc::new(RwLock::new(connector)),
        config,
        event_rx,
        is_running,
        cached_capabilities: Arc::new(RwLock::new(None)),
    };

    CONNECTORS.write().insert(id, handle);
    id
}

/// Destroy a connector
#[unsafe(no_mangle)]
pub extern "C" fn connector_destroy(connector_id: u64) {
    let mut connectors = CONNECTORS.write();
    if let Some(handle) = connectors.remove(&connector_id) {
        handle.is_running.store(false, Ordering::SeqCst);
        // Connector will be dropped, which closes connections
    }
}

/// Connect to the engine
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_connect(connector_id: u64) -> i32 {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    let connector = Arc::clone(&handle.connector);
    let is_running = Arc::clone(&handle.is_running);

    is_running.store(true, Ordering::SeqCst);

    RUNTIME.spawn(async move {
        let mut conn = connector.write();
        if let Err(e) = conn.connect().await {
            log::error!("connector_connect: error: {}", e);
            is_running.store(false, Ordering::SeqCst);
        }
    });

    1
}

/// Disconnect from the engine
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_disconnect(connector_id: u64) -> i32 {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    handle.is_running.store(false, Ordering::SeqCst);

    let connector = Arc::clone(&handle.connector);

    RUNTIME.spawn(async move {
        let mut conn = connector.write();
        if let Err(e) = conn.disconnect().await {
            log::error!("connector_disconnect: error: {}", e);
        }
    });

    1
}

/// Get connection state (blocking call to async state())
/// Returns JSON state object, caller must free with connector_free_string
#[unsafe(no_mangle)]
pub extern "C" fn connector_get_state(connector_id: u64) -> *mut c_char {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return ptr::null_mut(),
    };

    let connector = Arc::clone(&handle.connector);

    // Block on async call
    let state = RUNTIME.block_on(async {
        let conn = connector.read();
        conn.state().await
    });

    let state_json = serde_json::json!({
        "state": format!("{:?}", state),
        "is_connected": matches!(state, ConnectionState::Connected),
        "is_connecting": matches!(state, ConnectionState::Connecting),
        "is_disconnected": matches!(state, ConnectionState::Disconnected),
        "is_reconnecting": matches!(state, ConnectionState::Reconnecting),
        "is_error": matches!(state, ConnectionState::Error),
    });

    match serde_json::to_string(&state_json) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Check if connected (blocking)
#[unsafe(no_mangle)]
pub extern "C" fn connector_is_connected(connector_id: u64) -> i32 {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    let connector = Arc::clone(&handle.connector);

    let state = RUNTIME.block_on(async {
        let conn = connector.read();
        conn.state().await
    });

    if matches!(state, ConnectionState::Connected) {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMMAND API
// ═══════════════════════════════════════════════════════════════════════════════

/// Send a command to the engine (JSON)
/// command_json: JSON command object
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_send_command(connector_id: u64, command_json: *const c_char) -> i32 {
    if command_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(command_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let command: EngineCommand = match serde_json::from_str(json_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("connector_send_command: parse error: {}", e);
            return 0;
        }
    };

    send_command_internal(connector_id, command)
}

/// Send play spin command
/// spin_id: Spin identifier
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_play_spin(connector_id: u64, spin_id: *const c_char) -> i32 {
    if spin_id.is_null() {
        return 0;
    }

    let spin_id_str = match unsafe { CStr::from_ptr(spin_id) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let command = EngineCommand::PlaySpin { spin_id: spin_id_str };
    send_command_internal(connector_id, command)
}

/// Send pause command
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_pause(connector_id: u64) -> i32 {
    let command = EngineCommand::Pause;
    send_command_internal(connector_id, command)
}

/// Send resume command
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_resume(connector_id: u64) -> i32 {
    let command = EngineCommand::Resume;
    send_command_internal(connector_id, command)
}

/// Send stop command
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_stop(connector_id: u64) -> i32 {
    let command = EngineCommand::Stop;
    send_command_internal(connector_id, command)
}

/// Send seek command
/// timestamp_ms: Position in milliseconds
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_seek(connector_id: u64, timestamp_ms: f64) -> i32 {
    let command = EngineCommand::Seek { timestamp_ms };
    send_command_internal(connector_id, command)
}

/// Send set speed command
/// speed: Playback speed multiplier (1.0 = normal)
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_set_speed(connector_id: u64, speed: f64) -> i32 {
    let command = EngineCommand::SetSpeed { speed };
    send_command_internal(connector_id, command)
}

/// Set timing profile
/// profile: Profile name (normal, turbo, mobile, etc.)
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_set_timing_profile(connector_id: u64, profile: *const c_char) -> i32 {
    if profile.is_null() {
        return 0;
    }

    let profile_str = match unsafe { CStr::from_ptr(profile) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let command = EngineCommand::SetTimingProfile { profile: profile_str };
    send_command_internal(connector_id, command)
}

/// Request engine state
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_get_engine_state(connector_id: u64) -> i32 {
    let command = EngineCommand::GetState;
    send_command_internal(connector_id, command)
}

/// Request spin list
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_get_spin_list(connector_id: u64) -> i32 {
    let command = EngineCommand::GetSpinList;
    send_command_internal(connector_id, command)
}

/// Request engine capabilities
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_request_capabilities(connector_id: u64) -> i32 {
    let command = EngineCommand::GetCapabilities;
    send_command_internal(connector_id, command)
}

/// Trigger a specific event (for testing)
/// event_name: Event name
/// payload_json: Event payload JSON (can be null)
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_trigger_event(
    connector_id: u64,
    event_name: *const c_char,
    payload_json: *const c_char,
) -> i32 {
    if event_name.is_null() {
        return 0;
    }

    let name = match unsafe { CStr::from_ptr(event_name) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let payload = if payload_json.is_null() {
        None
    } else {
        match unsafe { CStr::from_ptr(payload_json) }.to_str() {
            Ok(s) => serde_json::from_str(s).ok(),
            Err(_) => None,
        }
    };

    let command = EngineCommand::TriggerEvent {
        event_name: name,
        payload,
    };
    send_command_internal(connector_id, command)
}

/// Set parameter value
/// name: Parameter name
/// value_json: Parameter value JSON
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_set_parameter(
    connector_id: u64,
    name: *const c_char,
    value_json: *const c_char,
) -> i32 {
    if name.is_null() || value_json.is_null() {
        return 0;
    }

    let param_name = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let value = match unsafe { CStr::from_ptr(value_json) }.to_str() {
        Ok(s) => serde_json::from_str(s).unwrap_or(serde_json::Value::Null),
        Err(_) => return 0,
    };

    let command = EngineCommand::SetParameter {
        name: param_name,
        value,
    };
    send_command_internal(connector_id, command)
}

/// Send custom command
/// name: Custom command name
/// data_json: JSON data
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_custom_command(
    connector_id: u64,
    name: *const c_char,
    data_json: *const c_char,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let cmd_name = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let data = if data_json.is_null() {
        serde_json::Value::Null
    } else {
        match unsafe { CStr::from_ptr(data_json) }.to_str() {
            Ok(s) => serde_json::from_str(s).unwrap_or(serde_json::Value::Null),
            Err(_) => serde_json::Value::Null,
        }
    };

    let command = EngineCommand::Custom { name: cmd_name, data };
    send_command_internal(connector_id, command)
}

/// Internal: Send command
fn send_command_internal(connector_id: u64, command: EngineCommand) -> i32 {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    let connector = Arc::clone(&handle.connector);

    RUNTIME.spawn(async move {
        let conn = connector.read();
        if let Err(e) = conn.send_command(command).await {
            log::error!("connector_send_command: send error: {}", e);
        }
    });

    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT API
// ═══════════════════════════════════════════════════════════════════════════════

/// Set global event callback
/// callback: Function pointer called for each event (connector_id, event_json)
#[unsafe(no_mangle)]
pub extern "C" fn connector_set_event_callback(callback: EventCallback) {
    *EVENT_CALLBACK.write() = Some(callback);
}

/// Clear global event callback
#[unsafe(no_mangle)]
pub extern "C" fn connector_clear_event_callback() {
    *EVENT_CALLBACK.write() = None;
}

/// Start event polling for a connector
/// This spawns a task that polls events and calls the callback
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn connector_start_event_polling(connector_id: u64) -> i32 {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    // Subscribe to events
    let connector = Arc::clone(&handle.connector);
    let is_running = Arc::clone(&handle.is_running);

    RUNTIME.spawn(async move {
        let mut event_rx = {
            let conn = connector.read();
            conn.subscribe_events()
        };

        while is_running.load(Ordering::SeqCst) {
            match event_rx.recv().await {
                Ok(event) => {
                    // Call the callback if set
                    let callback = EVENT_CALLBACK.read().clone();
                    if let Some(cb) = callback {
                        if let Ok(json) = serde_json::to_string(&event) {
                            if let Ok(cstr) = CString::new(json) {
                                cb(connector_id, cstr.as_ptr());
                            }
                        }
                    }
                }
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    log::warn!("Event receiver lagged {} messages", n);
                }
                Err(broadcast::error::RecvError::Closed) => {
                    break;
                }
            }
        }
    });

    1
}

/// Poll for next event (non-blocking)
/// Returns event JSON if available, null if none, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn connector_poll_event(connector_id: u64) -> *mut c_char {
    let mut connectors = CONNECTORS.write();
    let handle = match connectors.get_mut(&connector_id) {
        Some(h) => h,
        None => return ptr::null_mut(),
    };

    // Try to receive without blocking
    match handle.event_rx.try_recv() {
        Ok(event) => match serde_json::to_string(&event) {
            Ok(json) => match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get pending event count (approximate)
#[unsafe(no_mangle)]
pub extern "C" fn connector_event_count(connector_id: u64) -> i32 {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    handle.event_rx.len() as i32
}

// ═══════════════════════════════════════════════════════════════════════════════
// CAPABILITIES API
// ═══════════════════════════════════════════════════════════════════════════════

/// Get cached engine capabilities
/// Returns JSON capabilities, caller must free
/// Note: Call connector_request_capabilities first to populate cache
#[unsafe(no_mangle)]
pub extern "C" fn connector_get_capabilities(connector_id: u64) -> *mut c_char {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return ptr::null_mut(),
    };

    let caps = handle.cached_capabilities.read();
    match caps.as_ref() {
        Some(capabilities) => match serde_json::to_string(capabilities) {
            Ok(json) => match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        },
        None => {
            // Return default capabilities
            let default = EngineCapabilities::default();
            match serde_json::to_string(&default) {
                Ok(json) => match CString::new(json) {
                    Ok(cs) => cs.into_raw(),
                    Err(_) => ptr::null_mut(),
                },
                Err(_) => ptr::null_mut(),
            }
        }
    }
}

/// Set cached capabilities (called when engine responds)
#[unsafe(no_mangle)]
pub extern "C" fn connector_set_capabilities(
    connector_id: u64,
    capabilities_json: *const c_char,
) -> i32 {
    if capabilities_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(capabilities_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let caps: EngineCapabilities = match serde_json::from_str(json_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("connector_set_capabilities: parse error: {}", e);
            return 0;
        }
    };

    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    *handle.cached_capabilities.write() = Some(caps);
    1
}

/// Check if engine supports a specific command
/// command_name: Command name (e.g., "pause", "seek", "set_speed")
#[unsafe(no_mangle)]
pub extern "C" fn connector_supports_command(
    connector_id: u64,
    command_name: *const c_char,
) -> i32 {
    if command_name.is_null() {
        return 0;
    }

    let cmd_str = match unsafe { CStr::from_ptr(command_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return 0,
    };

    let caps = handle.cached_capabilities.read();
    match caps.as_ref() {
        Some(c) => {
            if c.supported_commands.contains(&cmd_str.to_string()) {
                1
            } else {
                0
            }
        }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string allocated by this module
#[unsafe(no_mangle)]
pub extern "C" fn connector_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Get all active connector IDs
/// Returns JSON array, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn connector_list_all() -> *mut c_char {
    let connectors = CONNECTORS.read();
    let ids: Vec<u64> = connectors.keys().copied().collect();

    match serde_json::to_string(&ids) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get connector config as JSON
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn connector_get_config(connector_id: u64) -> *mut c_char {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return ptr::null_mut(),
    };

    match serde_json::to_string(&handle.config) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Clear all connectors (for testing/reset)
#[unsafe(no_mangle)]
pub extern "C" fn connector_clear_all() {
    let mut connectors = CONNECTORS.write();
    for (_, handle) in connectors.drain() {
        handle.is_running.store(false, Ordering::SeqCst);
    }
}

/// Get connector statistics (connection uptime, events received, etc.)
/// Returns JSON with stats, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn connector_get_stats(connector_id: u64) -> *mut c_char {
    let connectors = CONNECTORS.read();
    let handle = match connectors.get(&connector_id) {
        Some(h) => h,
        None => return ptr::null_mut(),
    };

    // Return basic stats - connector doesn't track stats internally
    let stats = serde_json::json!({
        "connector_id": connector_id,
        "is_running": handle.is_running.load(Ordering::SeqCst),
        "pending_events": handle.event_rx.len(),
        "protocol": match &handle.config.protocol {
            Protocol::WebSocket { url } => format!("websocket:{}", url),
            Protocol::Tcp { host, port } => format!("tcp:{}:{}", host, port),
        },
        "adapter_id": handle.config.adapter_id,
    });

    match serde_json::to_string(&stats) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connector_lifecycle() {
        let url = CString::new("ws://localhost:9999").unwrap();
        let connector_id = connector_create_websocket(url.as_ptr());
        // May fail to connect, but ID should be valid
        assert!(connector_id > 0);

        connector_destroy(connector_id);
    }

    #[test]
    fn test_list_connectors() {
        let result = connector_list_all();
        assert!(!result.is_null());
        unsafe {
            connector_free_string(result);
        }
    }

    #[test]
    fn test_tcp_connector() {
        let host = CString::new("127.0.0.1").unwrap();
        let connector_id = connector_create_tcp(host.as_ptr(), 9000);
        assert!(connector_id > 0);

        connector_destroy(connector_id);
    }
}

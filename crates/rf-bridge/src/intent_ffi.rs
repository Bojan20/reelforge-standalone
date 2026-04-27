// file: crates/rf-bridge/src/intent_ffi.rs
//! IntentBridge FFI — exposes typed request/response bridge to Flutter.
//!
//! Two tiers:
//! 1. Flutter Rust Bridge (frb) — sync functions for Dart code generation
//! 2. C FFI (extern "C") — for dart:ffi direct access (lower overhead)
//!
//! All functions are safe to call from any thread.

use std::ffi::{CStr, CString, c_char};

use crate::intent_bridge::*;

// ═══════════════════════════════════════════════════════════════════════════
// FLUTTER RUST BRIDGE TIER (Dart codegen)
// ═══════════════════════════════════════════════════════════════════════════

/// Submit a typed request via JSON string.
/// Returns JSON response string.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_submit_json(request_json: String) -> String {
    let request: BridgeRequest = match serde_json::from_str(&request_json) {
        Ok(r) => r,
        Err(e) => {
            return serde_json::to_string(&BridgeResponse {
                correlation_id: 0,
                status: ResponseStatus::Error,
                error: format!("JSON parse error: {}", e),
                payload: ResponsePayload::Empty,
                processing_us: 0,
                commands_executed: 0,
            })
            .unwrap_or_else(|_| r#"{"status":"Error","error":"serialize failed"}"#.to_string());
        }
    };

    let bridge = IntentBridge::global();
    let cid = bridge.submit(request);

    // Drain the response we just created
    let responses = bridge.drain_responses(1);
    if let Some(resp) = responses.into_iter().find(|r| r.correlation_id == cid) {
        serde_json::to_string(&resp).unwrap_or_else(|_| "{}".to_string())
    } else {
        serde_json::to_string(&BridgeResponse {
            correlation_id: cid,
            status: ResponseStatus::Accepted,
            error: String::new(),
            payload: ResponsePayload::Empty,
            processing_us: 0,
            commands_executed: 0,
        })
        .unwrap_or_else(|_| "{}".to_string())
    }
}

/// Submit a batch of requests via JSON array string.
/// Returns JSON response string with batch result.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_submit_batch_json(requests_json: String) -> String {
    let requests: Vec<BridgeRequest> = match serde_json::from_str(&requests_json) {
        Ok(r) => r,
        Err(e) => {
            return serde_json::to_string(&BridgeResponse {
                correlation_id: 0,
                status: ResponseStatus::Error,
                error: format!("JSON parse error: {}", e),
                payload: ResponsePayload::Empty,
                processing_us: 0,
                commands_executed: 0,
            })
            .unwrap_or_else(|_| r#"{"status":"Error","error":"serialize failed"}"#.to_string());
        }
    };

    let bridge = IntentBridge::global();
    let cid = bridge.submit_batch(requests);

    let responses = bridge.drain_responses(1);
    if let Some(resp) = responses.into_iter().find(|r| r.correlation_id == cid) {
        serde_json::to_string(&resp).unwrap_or_else(|_| "{}".to_string())
    } else {
        "{}".to_string()
    }
}

/// Drain pending responses as JSON array.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_drain_responses(max: u32) -> String {
    let responses = IntentBridge::global().drain_responses(max as usize);
    serde_json::to_string(&responses).unwrap_or_else(|_| "[]".to_string())
}

/// Drain pending events (Rust→Flutter push) as JSON array.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_drain_events(max: u32) -> String {
    let events = IntentBridge::global().drain_events(max as usize);
    serde_json::to_string(&events).unwrap_or_else(|_| "[]".to_string())
}

/// Number of pending responses waiting for Flutter.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_pending_responses() -> u32 {
    IntentBridge::global().pending_responses() as u32
}

/// Number of pending events waiting for Flutter.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_pending_events() -> u32 {
    IntentBridge::global().pending_events() as u32
}

/// Bridge statistics as JSON.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_bridge_stats() -> String {
    let stats = IntentBridge::global().stats();
    serde_json::to_string(&stats).unwrap_or_else(|_| "{}".to_string())
}

/// Ping the bridge (latency measurement).
/// Returns JSON with client_timestamp_ms and server_timestamp_ms.
#[flutter_rust_bridge::frb(sync)]
pub fn intent_ping(client_timestamp_ms: u64) -> String {
    let bridge = IntentBridge::global();
    let cid = bridge.submit(BridgeRequest {
        correlation_id: next_correlation_id(),
        intent: CommandIntent::System,
        target: IntentTarget::Cortex,
        timeout_ms: 0,
        payload: RequestPayload::Ping { client_timestamp_ms },
    });

    let responses = bridge.drain_responses(1);
    if let Some(resp) = responses.into_iter().find(|r| r.correlation_id == cid) {
        serde_json::to_string(&resp).unwrap_or_else(|_| "{}".to_string())
    } else {
        "{}".to_string()
    }
}

/// Get the shared audio ring sequence number (UI checks for changes).
#[flutter_rust_bridge::frb(sync)]
pub fn intent_audio_ring_sequence() -> u64 {
    IntentBridge::global().audio_ring.sequence()
}

/// Read latest N frames from shared audio ring into a flat f32 array.
/// Returns interleaved stereo [L0, R0, L1, R1, ...].
#[flutter_rust_bridge::frb(sync)]
pub fn intent_audio_ring_read(max_frames: u32) -> Vec<f32> {
    let ring = &IntentBridge::global().audio_ring;
    let n = (max_frames as usize).min(ring.capacity());
    let mut out = vec![0.0f32; n * 2];
    let actual = ring.read_latest(&mut out, n);
    out.truncate(actual * 2);
    out
}

// ═══════════════════════════════════════════════════════════════════════════
// C FFI TIER (dart:ffi direct — lower overhead)
// ═══════════════════════════════════════════════════════════════════════════

/// Submit a request via C string JSON. Returns allocated C string JSON response.
/// Caller MUST free with `intent_free_string()`.
#[unsafe(no_mangle)]
pub extern "C" fn intent_submit(request_json: *const c_char) -> *mut c_char {
    let json_str = if request_json.is_null() {
        return std::ptr::null_mut();
    } else {
        unsafe { CStr::from_ptr(request_json) }
            .to_str()
            .unwrap_or("")
    };

    let result = intent_submit_json(json_str.to_string());

    CString::new(result)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Submit a batch via C string JSON. Returns allocated C string JSON response.
/// Caller MUST free with `intent_free_string()`.
#[unsafe(no_mangle)]
pub extern "C" fn intent_submit_batch(requests_json: *const c_char) -> *mut c_char {
    let json_str = if requests_json.is_null() {
        return std::ptr::null_mut();
    } else {
        unsafe { CStr::from_ptr(requests_json) }
            .to_str()
            .unwrap_or("")
    };

    let result = intent_submit_batch_json(json_str.to_string());

    CString::new(result)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Drain events as C string JSON array.
/// Caller MUST free with `intent_free_string()`.
#[unsafe(no_mangle)]
pub extern "C" fn intent_drain_events_c(max: u32) -> *mut c_char {
    let result = intent_drain_events(max);
    CString::new(result)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Drain responses as C string JSON array.
/// Caller MUST free with `intent_free_string()`.
#[unsafe(no_mangle)]
pub extern "C" fn intent_drain_responses_c(max: u32) -> *mut c_char {
    let result = intent_drain_responses(max);
    CString::new(result)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Get bridge stats as C string JSON.
/// Caller MUST free with `intent_free_string()`.
#[unsafe(no_mangle)]
pub extern "C" fn intent_stats_c() -> *mut c_char {
    let result = intent_bridge_stats();
    CString::new(result)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Pending response count (cheap atomic read).
#[unsafe(no_mangle)]
pub extern "C" fn intent_pending_responses_c() -> u32 {
    IntentBridge::global().pending_responses() as u32
}

/// Pending event count (cheap atomic read).
#[unsafe(no_mangle)]
pub extern "C" fn intent_pending_events_c() -> u32 {
    IntentBridge::global().pending_events() as u32
}

/// Audio ring sequence number (cheap atomic read).
#[unsafe(no_mangle)]
pub extern "C" fn intent_audio_ring_sequence_c() -> u64 {
    IntentBridge::global().audio_ring.sequence()
}

/// Free a string allocated by intent_* C FFI functions.
#[unsafe(no_mangle)]
pub extern "C" fn intent_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CALLBACK-BASED EVENT PUSH (Rust→Flutter without polling)
// ═══════════════════════════════════════════════════════════════════════════

/// Register a C callback for real-time Rust→Flutter event push.
/// A background thread will invoke this callback with JSON-encoded events.
/// Pass null to unregister.
#[unsafe(no_mangle)]
pub extern "C" fn intent_register_callback(callback: Option<CEventCallback>) {
    register_event_callback(callback);
}

/// Unregister the event callback.
#[unsafe(no_mangle)]
pub extern "C" fn intent_unregister_callback() {
    unregister_event_callback();
}

/// Get audio ring buffer raw pointer for zero-copy FFI access.
/// Returns JSON: `{"ptr": <address>, "frames": N, "channels": 2, "sequence": S}`
#[flutter_rust_bridge::frb(sync)]
pub fn intent_audio_ring_info() -> String {
    let ring = bridge_audio_ring();
    serde_json::to_string(&serde_json::json!({
        "ptr": ring.buffer.as_ptr() as usize,
        "frames": ring.capacity(),
        "channels": 2,
        "sequence": ring.sequence(),
    }))
    .unwrap_or_default()
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_submit_ping() {
        let req = serde_json::json!({
            "correlation_id": 1,
            "intent": "System",
            "target": "Cortex",
            "timeout_ms": 0,
            "payload": {
                "type": "Ping",
                "client_timestamp_ms": 12345
            }
        });

        let result = intent_submit_json(req.to_string());
        let resp: serde_json::Value = serde_json::from_str(&result).unwrap();
        assert_eq!(resp["correlation_id"], 1);
        assert_eq!(resp["status"], "Ok");
    }

    #[test]
    fn test_submit_batch() {
        let batch = serde_json::json!([
            {
                "correlation_id": 0,
                "intent": "UserInteraction",
                "target": "Mixer",
                "timeout_ms": 0,
                "payload": { "type": "SetVolume", "track_id": 0, "volume": 0.5 }
            },
            {
                "correlation_id": 0,
                "intent": "UserInteraction",
                "target": "Mixer",
                "timeout_ms": 0,
                "payload": { "type": "SetPan", "track_id": 0, "pan": -0.3 }
            }
        ]);

        let result = intent_submit_batch_json(batch.to_string());
        let resp: serde_json::Value = serde_json::from_str(&result).unwrap();
        // Should get some kind of response
        assert!(resp.get("correlation_id").is_some());
    }

    #[test]
    fn test_submit_invalid_json() {
        let result = intent_submit_json("not valid json".to_string());
        let resp: serde_json::Value = serde_json::from_str(&result).unwrap();
        assert_eq!(resp["status"], "Error");
        assert!(resp["error"].as_str().unwrap().contains("JSON parse error"));
    }

    #[test]
    fn test_drain_events_empty() {
        let result = intent_drain_events(100);
        let events: Vec<serde_json::Value> = serde_json::from_str(&result).unwrap();
        // Might be empty or have events from other tests — `from_str` already
        // proved the result is a valid JSON array; the previous
        // `assert!(events.len() >= 0)` was a tautology on `usize`.
        let _ = events;
    }

    #[test]
    fn test_audio_ring_read_empty() {
        let frames = intent_audio_ring_read(256);
        // May be empty if nothing written
        assert!(frames.len() <= 512);
    }
}

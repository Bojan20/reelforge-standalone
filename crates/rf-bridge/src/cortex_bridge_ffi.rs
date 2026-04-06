// file: crates/rf-bridge/src/cortex_bridge_ffi.rs
//! CortexBridge v2 FFI — exposes the ultimativni bridge to Flutter via C FFI.
//!
//! All functions are safe to call from any thread. Returns sensible defaults
//! if the bridge hasn't been initialized yet.
//!
//! ## Usage from Dart:
//! ```dart
//! // Send a typed request
//! final requestId = cortexBridgeSendRequest(
//!   3, // BridgeIntent.RealTime
//!   '{"TransportPlay":{}}',
//! );
//!
//! // Poll for responses
//! final json = cortexBridgePollResponses();
//! final responses = jsonDecode(json) as List;
//!
//! // Poll for autonomous events (CORTEX signals, file changes)
//! final eventsJson = cortexBridgePollEvents();
//! ```

use std::ffi::{CStr, CString, c_char};
use crate::cortex_bridge;

// ═══════════════════════════════════════════════════════════════════════════════
// BRIDGE LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the CortexBridge. Safe to call multiple times.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_init() {
    cortex_bridge::init_bridge();
}

// ═══════════════════════════════════════════════════════════════════════════════
// REQUEST / RESPONSE
// ═══════════════════════════════════════════════════════════════════════════════

/// Send a typed request through the bridge.
///
/// # Arguments
/// - `intent`: BridgeIntent as u8 (0=ParamChange, 1=Query, 2=Analysis,
///   3=RealTime, 4=Background, 5=Stream, 6=Batch, 7=Cortex, 8=Spatial)
/// - `payload_json`: JSON-encoded BridgePayload
///
/// # Returns
/// - Request ID (u64) for correlation, or 0 if failed.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_send_request(intent: u8, payload_json: *const c_char) -> u64 {
    if payload_json.is_null() {
        return 0;
    }
    let json = unsafe { CStr::from_ptr(payload_json) };
    let json_str = match json.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };
    cortex_bridge::bridge_send_request(intent, json_str)
}

/// Send a batch of requests atomically.
///
/// # Arguments
/// - `requests_json`: JSON array of CortexRequest objects
///
/// # Returns
/// - Batch ID (u64), or 0 if failed.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_send_batch(requests_json: *const c_char) -> u64 {
    if requests_json.is_null() {
        return 0;
    }
    let json = unsafe { CStr::from_ptr(requests_json) };
    let json_str = match json.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let requests: Vec<cortex_bridge::CortexRequest> = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(_) => return 0,
    };

    match cortex_bridge::flutter_handle().lock().send_batch(requests) {
        Some(batch_id) => batch_id,
        None => 0,
    }
}

/// Poll all available responses as a JSON array string.
///
/// # Returns
/// - Heap-allocated C string with JSON. Caller must free with `cortex_bridge_free_string`.
/// - Returns "[]" if no responses.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_poll_responses() -> *mut c_char {
    let json = cortex_bridge::bridge_poll_responses();
    CString::new(json).unwrap_or_else(|_| CString::new("[]").unwrap()).into_raw()
}

/// Poll all available events as a JSON array string.
///
/// # Returns
/// - Heap-allocated C string. Caller must free with `cortex_bridge_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_poll_events() -> *mut c_char {
    let json = cortex_bridge::bridge_poll_events();
    CString::new(json).unwrap_or_else(|_| CString::new("[]").unwrap()).into_raw()
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROCESSING (called from Rust-side tick loop)
// ═══════════════════════════════════════════════════════════════════════════════

/// Process all pending requests. Call from CORTEX tick loop.
///
/// # Returns
/// - Number of requests processed.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_process() -> u32 {
    cortex_bridge::bridge_process_requests()
}

/// Push an event from Rust to Flutter.
///
/// # Arguments
/// - `category`: EventCategory as u8
/// - `data_json`: JSON-encoded event data
///
/// # Returns
/// - true if event was queued, false if event ring is full.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_push_event(category: u8, data_json: *const c_char) -> bool {
    if data_json.is_null() {
        return false;
    }
    let json = unsafe { CStr::from_ptr(data_json) };
    let json_str = match json.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };
    cortex_bridge::bridge_push_event(category, json_str)
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATISTICS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get bridge statistics as JSON.
///
/// # Returns
/// - Heap-allocated C string. Caller must free with `cortex_bridge_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_stats() -> *mut c_char {
    let json = cortex_bridge::bridge_stats();
    CString::new(json).unwrap_or_else(|_| CString::new("{}").unwrap()).into_raw()
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED AUDIO BUFFER (Zero-Copy)
// ═══════════════════════════════════════════════════════════════════════════════

/// Register a shared audio buffer for zero-copy transfer.
///
/// # Arguments
/// - `name`: Buffer name (e.g., "master_out", "spatial_bed")
/// - `capacity`: Number of f32 samples (should be power of 2)
///
/// # Returns
/// - Raw pointer to the shared f32 buffer, or null on failure.
///   The pointer is valid for the lifetime of the bridge.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_register_buffer(
    name: *const c_char,
    capacity: u32,
) -> *const f32 {
    if name.is_null() || capacity == 0 {
        return std::ptr::null();
    }
    let name_str = unsafe { CStr::from_ptr(name) };
    let name_str = match name_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null(),
    };

    let (ptr, _cap) = cortex_bridge::bridge_register_shared_buffer(name_str, capacity as usize);
    ptr
}

/// Get the capacity of a registered shared buffer.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_buffer_capacity(name: *const c_char) -> u32 {
    if name.is_null() {
        return 0;
    }
    let name_str = unsafe { CStr::from_ptr(name) };
    let name_str = match name_str.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    cortex_bridge::rust_handle()
        .lock()
        .get_shared_buffer(name_str)
        .map(|buf| buf.capacity() as u32)
        .unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONVENIENCE: TYPED REQUEST SHORTCUTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Shortcut: Send a ParamChange request.
/// Returns request ID, or 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_param_change(payload_json: *const c_char) -> u64 {
    cortex_bridge_send_request(0, payload_json)
}

/// Shortcut: Send a Query request.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_query(payload_json: *const c_char) -> u64 {
    cortex_bridge_send_request(1, payload_json)
}

/// Shortcut: Send a RealTime request (transport, MIDI).
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_realtime(payload_json: *const c_char) -> u64 {
    cortex_bridge_send_request(3, payload_json)
}

/// Shortcut: Send a Spatial audio request.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_spatial(payload_json: *const c_char) -> u64 {
    cortex_bridge_send_request(8, payload_json)
}

/// Shortcut: Send a CORTEX signal/query.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_bridge_cortex(payload_json: *const c_char) -> u64 {
    cortex_bridge_send_request(7, payload_json)
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLUTTER RUST BRIDGE (frb) BINDINGS
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the bridge (Flutter Rust Bridge variant).
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_init() {
    cortex_bridge::init_bridge();
}

/// Send a typed request. Returns request ID (0 = failure).
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_send(intent: u8, payload_json: String) -> u64 {
    cortex_bridge::bridge_send_request(intent, &payload_json)
}

/// Send a batch of requests. Returns batch ID (0 = failure).
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_send_batch(requests_json: String) -> u64 {
    let requests: Vec<cortex_bridge::CortexRequest> = match serde_json::from_str(&requests_json) {
        Ok(r) => r,
        Err(_) => return 0,
    };
    cortex_bridge::flutter_handle()
        .lock()
        .send_batch(requests)
        .unwrap_or(0)
}

/// Poll responses as JSON string.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_poll_responses() -> String {
    cortex_bridge::bridge_poll_responses()
}

/// Poll events as JSON string.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_poll_events() -> String {
    cortex_bridge::bridge_poll_events()
}

/// Process pending requests (call from Rust tick loop integration).
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_process() -> u32 {
    cortex_bridge::bridge_process_requests()
}

/// Get bridge statistics as JSON.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_stats() -> String {
    cortex_bridge::bridge_stats()
}

/// Check if the bridge has pending responses.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_has_responses() -> bool {
    cortex_bridge::flutter_handle().lock().pending_responses() > 0
}

/// Check if the bridge has pending events.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_v2_has_events() -> bool {
    cortex_bridge::flutter_handle().lock().pending_events() > 0
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a C string allocated by the bridge (for C FFI callers).
///
/// # Safety
/// The pointer must have been returned by one of the bridge poll functions.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cortex_bridge_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)) };
    }
}

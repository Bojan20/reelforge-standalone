//! FFI Bindings for Unified Routing System
//!
//! Provides C-compatible interface for:
//! - Dynamic channel creation/deletion
//! - Flexible output routing
//! - Pre/post fader sends
//! - Channel properties (volume, pan, mute, solo)

use std::ffi::{CStr, c_char};

#[cfg(feature = "unified_routing")]
use crate::routing::{ChannelId, ChannelKind, OutputDestination, RoutingCommandSender};

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL ROUTING COMMAND SENDER
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(feature = "unified_routing")]
lazy_static::lazy_static! {
    /// Callback ID counter for async channel creation
    static ref CALLBACK_COUNTER: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(1);
    /// Routing sender pointer (NOT thread-safe, managed externally)
    static ref ROUTING_SENDER_PTR: std::sync::atomic::AtomicPtr<RoutingCommandSender> =
        std::sync::atomic::AtomicPtr::new(std::ptr::null_mut());
}

#[cfg(feature = "unified_routing")]
/// Helper to convert C string to Rust String
unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> { unsafe {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}}

// ═══════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(feature = "unified_routing")]
/// Initialize routing command sender (called once from PlaybackEngine)
/// This must be called before any routing commands can be sent
/// SAFETY: sender_ptr must remain valid for the entire program lifetime
#[unsafe(no_mangle)]
pub extern "C" fn routing_init(sender_ptr: *mut RoutingCommandSender) -> i32 {
    if sender_ptr.is_null() {
        return 0;
    }

    ROUTING_SENDER_PTR.store(sender_ptr, std::sync::atomic::Ordering::Release);

    log::info!("Routing FFI initialized");
    1
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(feature = "unified_routing")]
/// Create new routing channel
/// kind: 0=Audio, 1=Bus, 2=Aux, 3=VCA, 4=Master
/// Returns: callback_id for tracking response (0 on failure)
/// SAFETY: Caller must ensure name points to valid C string or is null
#[unsafe(no_mangle)]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn routing_create_channel(kind: u32, name: *const c_char) -> u32 {
    let name_str = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Unnamed".to_string());

    let channel_kind = match kind {
        0 => ChannelKind::Audio,
        1 => ChannelKind::Bus,
        2 => ChannelKind::Aux,
        3 => ChannelKind::Vca,
        4 => ChannelKind::Master,
        _ => return 0, // Invalid kind
    };

    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if sender_ptr.is_null() {
        return 0; // Not initialized
    }

    // SAFETY: Pointer guaranteed valid by routing_init contract
    let sender = unsafe { &mut *sender_ptr };
    let callback_id = CALLBACK_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    if sender.create_channel(channel_kind, name_str, callback_id) {
        callback_id
    } else {
        0 // Queue full
    }
}

#[cfg(feature = "unified_routing")]
/// Delete routing channel
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn routing_delete_channel(channel_id: u32) -> i32 {
    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        if sender.delete_channel(ChannelId(channel_id)) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[cfg(feature = "unified_routing")]
/// Try to receive channel creation response
/// Returns: channel_id if available, 0 if no response yet, -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn routing_poll_response(callback_id: u32) -> i32 {
    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        while let Some(response) = sender.try_recv() {
            match response {
                crate::routing::RoutingResponse::ChannelCreated {
                    callback_id: resp_id,
                    channel_id,
                } => {
                    if resp_id == callback_id {
                        return channel_id.0 as i32;
                    }
                }
                crate::routing::RoutingResponse::Error { message } => {
                    log::error!("Routing error: {}", message);
                    return -1;
                }
                _ => {}
            }
        }
        0 // No response yet
    } else {
        -1 // Not initialized
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTING
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(feature = "unified_routing")]
/// Set channel output destination
/// dest_type: 0=Master, 1=Channel, 2=None
/// dest_id: Target channel ID (only used if dest_type=1)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_output(channel_id: u32, dest_type: u32, dest_id: u32) -> i32 {
    let destination = match dest_type {
        0 => OutputDestination::Master,
        1 => OutputDestination::Channel(ChannelId(dest_id)),
        2 => OutputDestination::None,
        _ => return 0, // Invalid type
    };

    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        if sender.set_output(ChannelId(channel_id), destination) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[cfg(feature = "unified_routing")]
/// Add send from one channel to another
/// pre_fader: 1=pre-fader, 0=post-fader
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn routing_add_send(
    from_channel: u32,
    to_channel: u32,
    pre_fader: i32,
) -> i32 {
    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        if sender.add_send(
            ChannelId(from_channel),
            ChannelId(to_channel),
            pre_fader != 0,
        ) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL PROPERTIES
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(feature = "unified_routing")]
/// Set channel volume (fader)
/// volume_db: Volume in dB (-inf to +12)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_volume(channel_id: u32, volume_db: f64) -> i32 {
    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        if sender.set_volume(ChannelId(channel_id), volume_db) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[cfg(feature = "unified_routing")]
/// Set channel pan
/// pan: -1.0 (left) to +1.0 (right)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_pan(channel_id: u32, pan: f64) -> i32 {
    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        if sender.set_pan(ChannelId(channel_id), pan) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[cfg(feature = "unified_routing")]
/// Set channel mute
/// mute: 1=muted, 0=unmuted
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_mute(channel_id: u32, mute: i32) -> i32 {
    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        if sender.set_mute(ChannelId(channel_id), mute != 0) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[cfg(feature = "unified_routing")]
/// Set channel solo
/// solo: 1=soloed, 0=not soloed
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_solo(channel_id: u32, solo: i32) -> i32 {
    let sender_ptr = ROUTING_SENDER_PTR.load(std::sync::atomic::Ordering::Acquire);
    if !sender_ptr.is_null() {
        let sender = unsafe { &mut *sender_ptr };
        if sender.set_solo(ChannelId(channel_id), solo != 0) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// QUERY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(feature = "unified_routing")]
/// Get total number of routing channels (excluding master)
/// Returns: Channel count
#[unsafe(no_mangle)]
pub extern "C" fn routing_get_channel_count() -> u32 {
    // TODO: Need to add query capability to RoutingGraphRT
    // For now, return 0 as placeholder
    0
}

// ═══════════════════════════════════════════════════════════════════════════
// STUB FUNCTIONS (when unified_routing feature disabled)
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_init(_sender_ptr: *mut core::ffi::c_void) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_create_channel(_kind: u32, _name: *const c_char) -> u32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_delete_channel(_channel_id: u32) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_poll_response(_callback_id: u32) -> i32 { -1 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_output(_channel_id: u32, _dest_type: u32, _dest_id: u32) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_add_send(_from: u32, _to: u32, _pre_fader: i32) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_volume(_channel_id: u32, _volume_db: f64) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_pan(_channel_id: u32, _pan: f64) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_mute(_channel_id: u32, _mute: i32) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_solo(_channel_id: u32, _solo: i32) -> i32 { 0 }

#[cfg(not(feature = "unified_routing"))]
#[unsafe(no_mangle)]
pub extern "C" fn routing_get_channel_count() -> u32 { 0 }

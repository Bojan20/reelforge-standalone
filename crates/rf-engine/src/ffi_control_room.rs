//! FFI Bindings for Control Room System
//!
//! Provides C-compatible interface for:
//! - Monitor source selection (master, cue, external)
//! - Monitor controls (level, dim, mono)
//! - Speaker selection (up to 4 sets)
//! - Solo modes (SIP, AFL, PFL)
//! - Cue mixes (4 independent headphone mixes)
//! - Talkback system

use std::ffi::{CStr, c_char};
use std::sync::atomic::Ordering;

use crate::control_room::{ControlRoom, MonitorSource, SoloMode};
use crate::routing::ChannelId;

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL CONTROL ROOM POINTER
// ═══════════════════════════════════════════════════════════════════════════

/// Wrapper for raw pointer to make it Send+Sync
/// SAFETY: ControlRoom is managed by PlaybackEngine and lives for entire program
struct ControlRoomPtr(*mut ControlRoom);
unsafe impl Send for ControlRoomPtr {}
unsafe impl Sync for ControlRoomPtr {}

lazy_static::lazy_static! {
    /// Control room pointer - protected by RwLock for thread safety
    static ref CONTROL_ROOM_PTR: parking_lot::RwLock<Option<ControlRoomPtr>> =
        parking_lot::RwLock::new(None);
}

/// Helper macro to safely access control room
/// Prevents race condition between null check and dereference
macro_rules! with_control_room {
    ($cr:ident, $body:block, $default:expr) => {{
        let guard = CONTROL_ROOM_PTR.read();
        if let Some(ref wrapper) = *guard {
            let ptr = wrapper.0;
            if !ptr.is_null() {
                let $cr = unsafe { &*ptr };
                $body
            } else {
                $default
            }
        } else {
            $default
        }
    }};
}

/// Helper to convert C string to Rust String
#[allow(dead_code)]
unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> { unsafe {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}}

// ═══════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════

/// Initialize control room pointer (called once from PlaybackEngine)
/// SAFETY: control_room_ptr must remain valid for the entire program lifetime
#[unsafe(no_mangle)]
pub extern "C" fn control_room_init(control_room_ptr: *mut ControlRoom) -> i32 {
    if control_room_ptr.is_null() {
        return 0;
    }

    *CONTROL_ROOM_PTR.write() = Some(ControlRoomPtr(control_room_ptr));

    log::info!("Control Room FFI initialized");
    1
}

// ═══════════════════════════════════════════════════════════════════════════
// MONITOR SOURCE & LEVEL
// ═══════════════════════════════════════════════════════════════════════════

/// Set monitor source
/// source: 0=Master, 1-4=Cue 1-4, 5-6=External 1-2
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_monitor_source(source: u8) -> i32 {
    with_control_room!(control_room, {
        if let Some(monitor_source) = MonitorSource::from_u8(source) {
            control_room.set_monitor_source(monitor_source);
            1
        } else {
            0
        }
    }, 0)
}

/// Get monitor source
/// Returns: 0=Master, 1-4=Cue 1-4, 5-6=External 1-2, 255 on error
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_monitor_source() -> u8 {
    with_control_room!(control_room, {
        control_room.monitor_source().to_u8()
    }, 255)
}

/// Set monitor level (dB)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_monitor_level(level_db: f64) -> i32 {
    // SECURITY: Validate dB range
    if !level_db.is_finite() || !(-120.0..=24.0).contains(&level_db) {
        return 0;
    }

    with_control_room!(control_room, {
        control_room.set_monitor_level_db(level_db);
        1
    }, 0)
}

/// Get monitor level (dB)
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_monitor_level() -> f64 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.monitor_level_db()
    } else {
        0.0
    }
}

/// Set dim enabled
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_dim(enabled: i32) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.dim_enabled.store(enabled != 0, Ordering::Relaxed);
        1
    } else {
        0
    }
}

/// Get dim enabled
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_dim() -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        if control_room.dim_enabled.load(Ordering::Relaxed) { 1 } else { 0 }
    } else {
        0
    }
}

/// Set mono enabled
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_mono(enabled: i32) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.mono_enabled.store(enabled != 0, Ordering::Relaxed);
        1
    } else {
        0
    }
}

/// Get mono enabled
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_mono() -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        if control_room.mono_enabled.load(Ordering::Relaxed) { 1 } else { 0 }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPEAKER SELECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Set active speaker set (0-3)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_speaker_set(index: u8) -> i32 {
    if index > 3 {
        return 0;
    }

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.set_active_speaker_set(index);
        1
    } else {
        0
    }
}

/// Get active speaker set
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_speaker_set() -> u8 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.active_speakers.load(Ordering::Relaxed)
    } else {
        0
    }
}

/// Set speaker calibration level (dB)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_speaker_level(index: u8, level_db: f64) -> i32 {
    if index > 3 {
        return 0;
    }

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.speaker_sets[index as usize].set_calibration_db(level_db);
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SOLO SYSTEM
// ═══════════════════════════════════════════════════════════════════════════

/// Set solo mode
/// mode: 0=Off, 1=SIP, 2=AFL, 3=PFL
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_solo_mode(mode: u8) -> i32 {
    let solo_mode = match mode {
        0 => SoloMode::Off,
        1 => SoloMode::SIP,
        2 => SoloMode::AFL,
        3 => SoloMode::PFL,
        _ => return 0,
    };

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.set_solo_mode(solo_mode);
        1
    } else {
        0
    }
}

/// Get solo mode
/// Returns: 0=Off, 1=SIP, 2=AFL, 3=PFL
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_solo_mode() -> u8 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.solo_mode() as u8
    } else {
        0
    }
}

/// Solo channel
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_solo_channel(channel_id: u32) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.set_solo(ChannelId(channel_id), true);
        1
    } else {
        0
    }
}

/// Unsolo channel
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_unsolo_channel(channel_id: u32) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.set_solo(ChannelId(channel_id), false);
        1
    } else {
        0
    }
}

/// Clear all solos
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_clear_solo() -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.clear_all_solos();
        1
    } else {
        0
    }
}

/// Check if channel is soloed
#[unsafe(no_mangle)]
pub extern "C" fn control_room_is_soloed(channel_id: u32) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        if control_room.is_soloed(ChannelId(channel_id)) { 1 } else { 0 }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUE MIXES
// ═══════════════════════════════════════════════════════════════════════════

/// Set cue mix enabled
/// cue_index: 0-3
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_cue_enabled(cue_index: u8, enabled: i32) -> i32 {
    if cue_index > 3 {
        return 0;
    }

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.cue_mixes[cue_index as usize]
            .enabled
            .store(enabled != 0, Ordering::Relaxed);
        1
    } else {
        0
    }
}

/// Set cue mix level (dB)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_cue_level(cue_index: u8, level_db: f64) -> i32 {
    if cue_index > 3 {
        return 0;
    }

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.cue_mixes[cue_index as usize].set_level_db(level_db);
        1
    } else {
        0
    }
}

/// Set cue mix pan
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_cue_pan(cue_index: u8, pan: f64) -> i32 {
    if cue_index > 3 {
        return 0;
    }

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.cue_mixes[cue_index as usize].set_pan(pan);
        1
    } else {
        0
    }
}

/// Add channel to cue mix send
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_add_cue_send(
    cue_index: u8,
    channel_id: u32,
    level: f64,
    pan: f64,
) -> i32 {
    if cue_index > 3 {
        return 0;
    }

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        // Add send to cue mix channel_sends map
        let send = crate::control_room::CueSend {
            level,
            pan,
            enabled: true,
            pre_fader: true,  // Cue sends are typically pre-fader
        };
        control_room.cue_mixes[cue_index as usize]
            .channel_sends
            .write()
            .insert(ChannelId(channel_id), send);
        1
    } else {
        0
    }
}

/// Remove channel from cue mix send
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_remove_cue_send(cue_index: u8, channel_id: u32) -> i32 {
    if cue_index > 3 {
        return 0;
    }

    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.cue_mixes[cue_index as usize]
            .channel_sends
            .write()
            .remove(&ChannelId(channel_id));
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TALKBACK
// ═══════════════════════════════════════════════════════════════════════════

/// Set talkback enabled
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_talkback(enabled: i32) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.set_talkback_enabled(enabled != 0);
        1
    } else {
        0
    }
}

/// Set talkback level (dB)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_talkback_level(level_db: f64) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.set_talkback_level_db(level_db);
        1
    } else {
        0
    }
}

/// Set talkback destinations (bitmask: bit 0=Cue1, bit 1=Cue2, etc.)
/// Returns: 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn control_room_set_talkback_destinations(destinations: u8) -> i32 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        control_room.set_talkback_destinations(destinations);
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// METERING
// ═══════════════════════════════════════════════════════════════════════════

/// Get monitor peak level (left)
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_monitor_peak_l() -> f64 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        f64::from_bits(control_room.monitor_peak_l.load(Ordering::Relaxed))
    } else {
        0.0
    }
}

/// Get monitor peak level (right)
#[unsafe(no_mangle)]
pub extern "C" fn control_room_get_monitor_peak_r() -> f64 {
    let guard = CONTROL_ROOM_PTR.read();
    if let Some(ref wrapper) = *guard {
        let control_room = unsafe { &*wrapper.0 };
        f64::from_bits(control_room.monitor_peak_r.load(Ordering::Relaxed))
    } else {
        0.0
    }
}

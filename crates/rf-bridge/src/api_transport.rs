//! Transport API functions
//!
//! Extracted from api.rs as part of modular FFI decomposition.
//! Handles playback transport control: play, stop, pause, seek, loop, tempo.

use crate::{ENGINE, TransportState};

// ═══════════════════════════════════════════════════════════════════════════
// TRANSPORT
// ═══════════════════════════════════════════════════════════════════════════

/// Start playback
#[flutter_rust_bridge::frb(sync)]
pub fn transport_play() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_playing = true;
        true
    } else {
        false
    }
}

/// Stop playback
#[flutter_rust_bridge::frb(sync)]
pub fn transport_stop() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_playing = false;
        e.transport.position_samples = 0;
        e.transport.position_seconds = 0.0;
        true
    } else {
        false
    }
}

/// Pause playback (keeps position)
#[flutter_rust_bridge::frb(sync)]
pub fn transport_pause() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_playing = false;
        true
    } else {
        false
    }
}

/// Toggle record
#[flutter_rust_bridge::frb(sync)]
pub fn transport_record() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_recording = !e.transport.is_recording;
        true
    } else {
        false
    }
}

/// Set playback position (in seconds)
#[flutter_rust_bridge::frb(sync)]
pub fn transport_set_position(seconds: f64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.position_seconds = seconds;
        let sr = e.config.sample_rate.as_f64();
        e.transport.position_samples = (seconds * sr) as u64;
        true
    } else {
        false
    }
}

/// Set tempo
#[flutter_rust_bridge::frb(sync)]
pub fn transport_set_tempo(bpm: f64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.tempo = bpm.clamp(20.0, 999.0);
        true
    } else {
        false
    }
}

/// Toggle loop
#[flutter_rust_bridge::frb(sync)]
pub fn transport_toggle_loop() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.loop_enabled = !e.transport.loop_enabled;
        true
    } else {
        false
    }
}

/// Set loop range
#[flutter_rust_bridge::frb(sync)]
pub fn transport_set_loop_range(start: f64, end: f64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.loop_start = start;
        e.transport.loop_end = end;
        true
    } else {
        false
    }
}

/// Get current transport state
#[flutter_rust_bridge::frb(sync)]
pub fn transport_get_state() -> Option<TransportState> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.transport.clone())
}

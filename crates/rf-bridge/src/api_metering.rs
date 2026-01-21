//! Metering API functions
//!
//! Extracted from api.rs as part of modular FFI decomposition.
//! Handles real-time metering: peak levels, LUFS, CPU usage, correlation.

use crate::{MeteringState, ENGINE};

// ═══════════════════════════════════════════════════════════════════════════
// METERING
// ═══════════════════════════════════════════════════════════════════════════

/// Get current metering state (call at ~60fps for UI updates)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_state() -> Option<MeteringState> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.metering.clone())
}

/// Get master peak levels (L, R)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_peak() -> Option<(f32, f32)> {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| (e.metering.master_peak_l, e.metering.master_peak_r))
}

/// Get master LUFS (momentary, short-term, integrated)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_lufs() -> Option<(f32, f32, f32)> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| {
        (
            e.metering.master_lufs_m,
            e.metering.master_lufs_s,
            e.metering.master_lufs_i,
        )
    })
}

/// Get CPU usage percentage
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_cpu_usage() -> f32 {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.metering.cpu_usage).unwrap_or(0.0)
}

/// Get master stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_correlation() -> f32 {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.metering.correlation)
        .unwrap_or(1.0)
}

/// Get master stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_balance() -> f32 {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.metering.stereo_balance)
        .unwrap_or(0.0)
}

/// Get master dynamic range (peak - RMS in dB)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_dynamic_range() -> f32 {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.metering.dynamic_range)
        .unwrap_or(0.0)
}

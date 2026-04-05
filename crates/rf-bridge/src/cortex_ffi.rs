// file: crates/rf-bridge/src/cortex_ffi.rs
//! CORTEX Nervous System FFI — exposes cortex health, signals, and patterns to Flutter.
//!
//! All functions are safe to call from any thread. Returns sensible defaults
//! if the cortex hasn't been initialized yet.

use crate::{cortex_handle, cortex_shared};
use rf_cortex::prelude::*;

// ═══════════════════════════════════════════════════════════════════════════
// HEALTH & AWARENESS
// ═══════════════════════════════════════════════════════════════════════════

/// Get the cortex health score (0.0 = critical, 1.0 = perfect).
/// Returns 1.0 if cortex not yet initialized.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_health_score() -> f64 {
    cortex_shared()
        .map(|s| s.health_score())
        .unwrap_or(1.0)
}

/// Is the cortex in a degraded state (health < 0.6)?
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_is_degraded() -> bool {
    cortex_shared()
        .map(|s| s.is_degraded.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(false)
}

/// Total neural signals processed since boot.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_total_signals() -> u64 {
    cortex_shared()
        .map(|s| s.total_processed.load(portable_atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// Total reflex actions fired since boot.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_total_reflex_actions() -> u64 {
    cortex_shared()
        .map(|s| s.total_reflex_actions.load(portable_atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════
// AWARENESS SNAPSHOT (Full DTO)
// ═══════════════════════════════════════════════════════════════════════════

/// Full cortex awareness DTO for Flutter.
#[derive(Clone, Debug)]
pub struct CortexAwarenessDto {
    pub uptime_secs: f64,
    pub health_score: f64,
    pub signals_per_second: f64,
    pub drop_rate: f64,
    pub active_reflexes: u32,
    pub reflex_fires: u64,
    pub patterns_recognized: u64,
    pub subscriber_count: u32,
    // Dimensions
    pub dim_throughput: f64,
    pub dim_reliability: f64,
    pub dim_responsiveness: f64,
    pub dim_coverage: f64,
    pub dim_cognition: f64,
    pub dim_efficiency: f64,
    pub dim_coherence: f64,
}

/// Get full cortex awareness snapshot.
/// Returns None if cortex hasn't taken a snapshot yet.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_awareness() -> Option<CortexAwarenessDto> {
    let shared = cortex_shared()?;
    let snap = shared.latest_awareness.lock().clone()?;
    Some(CortexAwarenessDto {
        uptime_secs: snap.uptime_secs,
        health_score: snap.health_score,
        signals_per_second: snap.signals_per_second,
        drop_rate: snap.drop_rate,
        active_reflexes: snap.active_reflexes as u32,
        reflex_fires: snap.reflex_fires,
        patterns_recognized: snap.patterns_recognized,
        subscriber_count: snap.subscriber_count as u32,
        dim_throughput: snap.dimensions.throughput,
        dim_reliability: snap.dimensions.reliability,
        dim_responsiveness: snap.dimensions.responsiveness,
        dim_coverage: snap.dimensions.coverage,
        dim_cognition: snap.dimensions.cognition,
        dim_efficiency: snap.dimensions.efficiency,
        dim_coherence: snap.dimensions.coherence,
    })
}

// ═══════════════════════════════════════════════════════════════════════════
// PATTERN LOG
// ═══════════════════════════════════════════════════════════════════════════

/// A recognized pattern DTO for Flutter.
#[derive(Clone, Debug)]
pub struct CortexPatternDto {
    pub name: String,
    pub severity: f32,
    pub description: String,
}

/// Get recent recognized patterns (last 100).
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_recent_patterns() -> Vec<CortexPatternDto> {
    cortex_shared()
        .map(|s| {
            s.recent_patterns
                .lock()
                .iter()
                .map(|p| CortexPatternDto {
                    name: p.name.clone(),
                    severity: p.severity,
                    description: p.description.clone(),
                })
                .collect()
        })
        .unwrap_or_default()
}

// ═══════════════════════════════════════════════════════════════════════════
// SIGNAL EMISSION FROM FLUTTER (Vision/User signals)
// ═══════════════════════════════════════════════════════════════════════════

/// Emit a user interaction signal from Flutter.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_emit_user_interaction(action: String) {
    if let Some(handle) = cortex_handle() {
        handle.signal(
            SignalOrigin::User,
            SignalUrgency::Normal,
            SignalKind::UserInteraction { action },
        );
    }
}

/// Emit a visual anomaly signal from Flutter.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_emit_visual_anomaly(region: String, description: String) {
    if let Some(handle) = cortex_handle() {
        handle.signal(
            SignalOrigin::Vision,
            SignalUrgency::Elevated,
            SignalKind::VisualAnomaly { region, description },
        );
    }
}

/// Emit a custom signal from Flutter.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_emit_custom(tag: String, data: String) {
    if let Some(handle) = cortex_handle() {
        handle.signal(
            SignalOrigin::Bridge,
            SignalUrgency::Normal,
            SignalKind::Custom { tag, data },
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// C FFI (for dart:ffi direct calls)
// ═══════════════════════════════════════════════════════════════════════════

/// C FFI: Get cortex health score.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_health() -> f64 {
    cortex_shared()
        .map(|s| s.health_score())
        .unwrap_or(1.0)
}

/// C FFI: Is cortex degraded?
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_is_degraded() -> i32 {
    if cortex_shared()
        .map(|s| s.is_degraded.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(false)
    {
        1
    } else {
        0
    }
}

/// C FFI: Get total signals processed.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_total_signals() -> u64 {
    cortex_shared()
        .map(|s| s.total_processed.load(portable_atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

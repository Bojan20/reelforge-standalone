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
// REFLEX STATS
// ════════════════════════════════════════════════════════════════════════���══

/// Reflex stats DTO for Flutter.
#[derive(Clone, Debug)]
pub struct CortexReflexDto {
    pub name: String,
    pub fire_count: u64,
    pub enabled: bool,
}

/// Get stats for all registered reflexes.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_reflex_stats() -> Vec<CortexReflexDto> {
    cortex_shared()
        .map(|s| {
            s.reflex_stats
                .lock()
                .iter()
                .map(|r| CortexReflexDto {
                    name: r.name.clone(),
                    fire_count: r.fire_count,
                    enabled: r.enabled,
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
// SYSTEM HEALTH SIGNALS
// ═══════════════════════════════════════════════════════════════════════════

/// Report current system memory to CORTEX (call periodically from Flutter timer).
/// `available_mb` = free + reclaimable memory in MB.
/// Emits MemoryPressure signal when available < 512 MB.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_report_memory(available_mb: u64) {
    if available_mb < 512 {
        if let Some(handle) = cortex_handle() {
            handle.signal(
                SignalOrigin::Bridge,
                if available_mb < 128 {
                    SignalUrgency::Emergency
                } else if available_mb < 256 {
                    SignalUrgency::Critical
                } else {
                    SignalUrgency::Elevated
                },
                SignalKind::MemoryPressure { used_mb: 0, available_mb },
            );
        }
    }
}

/// Report sample rate change to CORTEX.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_report_sample_rate_change(old_rate: u32, new_rate: u32) {
    if let Some(handle) = cortex_handle() {
        handle.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::SampleRateChanged { old: old_rate, new: new_rate },
        );
    }
}

/// Report audio device change to CORTEX.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_report_device_change(device_name: String) {
    if let Some(handle) = cortex_handle() {
        handle.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::DeviceChanged { device_name },
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

/// C FFI: Get total reflex actions fired.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_total_reflex_actions() -> u64 {
    cortex_shared()
        .map(|s| s.total_reflex_actions.load(portable_atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// C FFI: Get total recognized patterns.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_total_patterns() -> u64 {
    cortex_shared()
        .map(|s| s.recent_patterns.lock().len() as u64)
        .unwrap_or(0)
}

/// C FFI: Get awareness dimension (0-6 → throughput, reliability, responsiveness, coverage, cognition, efficiency, coherence).
/// Returns -1.0 if unavailable.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_dimension(idx: u32) -> f64 {
    cortex_shared()
        .and_then(|s| {
            let snap = s.latest_awareness.lock().clone()?;
            Some(match idx {
                0 => snap.dimensions.throughput,
                1 => snap.dimensions.reliability,
                2 => snap.dimensions.responsiveness,
                3 => snap.dimensions.coverage,
                4 => snap.dimensions.cognition,
                5 => snap.dimensions.efficiency,
                6 => snap.dimensions.coherence,
                _ => return None,
            })
        })
        .unwrap_or(-1.0)
}

/// C FFI: Get signals per second rate.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_signals_per_second() -> f64 {
    cortex_shared()
        .and_then(|s| {
            let snap = s.latest_awareness.lock().clone()?;
            Some(snap.signals_per_second)
        })
        .unwrap_or(0.0)
}

/// C FFI: Get signal drop rate (0.0-1.0).
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_drop_rate() -> f64 {
    cortex_shared()
        .and_then(|s| {
            let snap = s.latest_awareness.lock().clone()?;
            Some(snap.drop_rate)
        })
        .unwrap_or(0.0)
}

/// C FFI: Get number of active reflex rules.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_active_reflex_count() -> u32 {
    cortex_shared()
        .map(|s| {
            s.reflex_stats
                .lock()
                .iter()
                .filter(|r| r.enabled)
                .count() as u32
        })
        .unwrap_or(0)
}

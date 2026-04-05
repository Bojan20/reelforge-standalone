// file: crates/rf-bridge/src/cortex_ffi.rs
//! CORTEX Nervous System FFI — exposes cortex health, signals, and patterns to Flutter.
//!
//! All functions are safe to call from any thread. Returns sensible defaults
//! if the cortex hasn't been initialized yet.

use crate::{cortex_handle, cortex_shared, cortex_executor_shared};
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
// IMMUNE SYSTEM STATUS
// ═══════════════════════════════════════════════════════════════════════════

/// Immune system status DTO for Flutter.
#[derive(Clone, Debug)]
pub struct CortexImmuneDto {
    pub total_anomalies: u64,
    pub total_escalations: u64,
    pub active_count: u32,
    pub chronic_count: u32,
    pub has_chronic: bool,
    pub categories: Vec<CortexAntibodyDto>,
}

/// Individual antibody DTO.
#[derive(Clone, Debug)]
pub struct CortexAntibodyDto {
    pub category: String,
    pub count: u32,
    pub escalation_level: u8,
    pub max_severity: f32,
    pub is_chronic: bool,
}

/// Get immune system status.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_immune_status() -> Option<CortexImmuneDto> {
    let shared = cortex_shared()?;
    let snap = shared.immune_snapshot.lock().clone()?;
    Some(CortexImmuneDto {
        total_anomalies: snap.total_anomalies,
        total_escalations: snap.total_escalations,
        active_count: snap.active_count as u32,
        chronic_count: snap.chronic_count as u32,
        has_chronic: snap.chronic_count > 0,
        categories: snap
            .categories
            .iter()
            .map(|ab| CortexAntibodyDto {
                category: ab.category.clone(),
                count: ab.count,
                escalation_level: ab.escalation_level,
                max_severity: ab.max_severity,
                is_chronic: ab.is_chronic,
            })
            .collect(),
    })
}

/// Is any anomaly chronic? (lock-free check)
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_has_chronic_anomaly() -> bool {
    cortex_shared()
        .map(|s| s.has_chronic.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(false)
}

// ═══════════════════════════════════════════════════════════════════════════
// COMMAND EXECUTOR STATS
// ═══════════════════════════════════════════════════════════════════════════

/// Command executor stats DTO for Flutter.
#[derive(Clone, Debug)]
pub struct CortexExecutorDto {
    pub total_commands_dispatched: u64,
    pub total_executed: u64,
    pub total_failed: u64,
    pub total_no_handler: u64,
    pub total_drained: u64,
    /// Commands that actually healed something (closed-loop verified).
    pub total_healed: u64,
    /// Commands that ran but didn't improve the situation.
    pub total_not_healed: u64,
    /// Healing success rate (0.0 to 1.0).
    pub healing_rate: f32,
    pub recent_actions: Vec<CortexExecutionDto>,
}

/// Individual execution record DTO.
#[derive(Clone, Debug)]
pub struct CortexExecutionDto {
    pub action_tag: String,
    pub reason: String,
    pub priority: String,
    pub result: String,
    /// Healing outcome detail (empty if legacy handler or no outcome).
    pub healing_detail: String,
    /// Whether this action healed the problem.
    pub healed: bool,
}

/// Get command executor stats (commands dispatched vs executed).
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_executor_stats() -> Option<CortexExecutorDto> {
    let shared = cortex_shared()?;
    let exec_shared = cortex_executor_shared()?;

    let dispatched = shared.total_commands_dispatched.load(portable_atomic::Ordering::Relaxed);
    let recent = exec_shared.recent_log.lock();

    Some(CortexExecutorDto {
        total_commands_dispatched: dispatched,
        total_executed: exec_shared.total_executed.load(std::sync::atomic::Ordering::Relaxed),
        total_failed: exec_shared.total_failed.load(std::sync::atomic::Ordering::Relaxed),
        total_no_handler: exec_shared.total_no_handler.load(std::sync::atomic::Ordering::Relaxed),
        total_drained: exec_shared.total_drained.load(std::sync::atomic::Ordering::Relaxed),
        total_healed: exec_shared.total_healed.load(std::sync::atomic::Ordering::Relaxed),
        total_not_healed: exec_shared.total_not_healed.load(std::sync::atomic::Ordering::Relaxed),
        healing_rate: exec_shared.healing_rate(),
        recent_actions: recent
            .iter()
            .rev()
            .take(20)
            .map(|r| CortexExecutionDto {
                action_tag: r.action_tag.clone(),
                reason: r.reason.clone(),
                priority: format!("{:?}", r.priority),
                result: format!("{:?}", r.result),
                healing_detail: r.outcome.as_ref().map(|o| o.detail.clone()).unwrap_or_default(),
                healed: r.outcome.as_ref().map(|o| o.healed).unwrap_or(false),
            })
            .collect(),
    })
}

/// Total commands dispatched by CORTEX (lock-free).
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_total_commands_dispatched() -> u64 {
    cortex_shared()
        .map(|s| s.total_commands_dispatched.load(portable_atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// Total commands executed by the executor (lock-free).
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_total_commands_executed() -> u64 {
    cortex_executor_shared()
        .map(|s| s.total_executed.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// Healing success rate (0.0 to 1.0). Returns 1.0 if no healing actions yet.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_healing_rate() -> f32 {
    cortex_executor_shared()
        .map(|s| s.healing_rate())
        .unwrap_or(1.0)
}

/// Total commands that successfully healed a problem.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_total_healed() -> u64 {
    cortex_executor_shared()
        .map(|s| s.total_healed.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// Total commands that ran but didn't improve the situation.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_total_not_healed() -> u64 {
    cortex_executor_shared()
        .map(|s| s.total_not_healed.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT STREAM — Reactive updates for Flutter CortexProvider
// ═══════════════════════════════════════════════════════════════════════════

/// Event DTO for Flutter — serialized form of CortexEvent.
#[derive(Clone, Debug)]
pub struct CortexEventDto {
    /// Event type tag: "health_changed", "degraded_changed", "pattern_recognized",
    /// "reflex_fired", "command_dispatched", "immune_escalation", "chronic_changed",
    /// "awareness_updated", "healing_complete", "signal_milestone"
    pub event_type: String,
    /// Primary value (context-dependent):
    /// - health_changed: new health score
    /// - degraded_changed: 1.0 if degraded, 0.0 if not
    /// - pattern_recognized: severity
    /// - reflex_fired: fire_count
    /// - immune_escalation: escalation_level
    /// - awareness_updated: health_score
    /// - signal_milestone: total signals
    pub value: f64,
    /// Secondary value (context-dependent):
    /// - health_changed: old health score
    /// - awareness_updated: signals_per_second
    pub value2: f64,
    /// Description/name field:
    /// - pattern_recognized: pattern name
    /// - reflex_fired: reflex name
    /// - command_dispatched: action_tag
    /// - immune_escalation: category
    pub name: String,
    /// Detail text:
    /// - pattern_recognized: description
    /// - command_dispatched: reason
    pub detail: String,
}

/// Drain all pending CORTEX events. Returns empty vec if no events.
/// Call this periodically from Flutter (e.g. every 200ms) for reactive updates.
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_drain_events() -> Vec<CortexEventDto> {
    let shared = match cortex_shared() {
        Some(s) => s,
        None => return Vec::new(),
    };

    let events = shared.drain_events();
    events
        .into_iter()
        .map(|e| match e {
            rf_cortex::runtime::CortexEvent::HealthChanged { old, new } => CortexEventDto {
                event_type: "health_changed".into(),
                value: new,
                value2: old,
                name: String::new(),
                detail: String::new(),
            },
            rf_cortex::runtime::CortexEvent::DegradedStateChanged { is_degraded } => CortexEventDto {
                event_type: "degraded_changed".into(),
                value: if is_degraded { 1.0 } else { 0.0 },
                value2: 0.0,
                name: String::new(),
                detail: String::new(),
            },
            rf_cortex::runtime::CortexEvent::PatternRecognized { name, severity, description } => CortexEventDto {
                event_type: "pattern_recognized".into(),
                value: severity as f64,
                value2: 0.0,
                name,
                detail: description,
            },
            rf_cortex::runtime::CortexEvent::ReflexFired { name, fire_count } => CortexEventDto {
                event_type: "reflex_fired".into(),
                value: fire_count as f64,
                value2: 0.0,
                name,
                detail: String::new(),
            },
            rf_cortex::runtime::CortexEvent::CommandDispatched { action_tag, reason } => CortexEventDto {
                event_type: "command_dispatched".into(),
                value: 0.0,
                value2: 0.0,
                name: action_tag,
                detail: reason,
            },
            rf_cortex::runtime::CortexEvent::ImmuneEscalation { category, escalation_level } => CortexEventDto {
                event_type: "immune_escalation".into(),
                value: escalation_level as f64,
                value2: 0.0,
                name: category,
                detail: String::new(),
            },
            rf_cortex::runtime::CortexEvent::ChronicChanged { has_chronic } => CortexEventDto {
                event_type: "chronic_changed".into(),
                value: if has_chronic { 1.0 } else { 0.0 },
                value2: 0.0,
                name: String::new(),
                detail: String::new(),
            },
            rf_cortex::runtime::CortexEvent::AwarenessUpdated { health_score, signals_per_second, drop_rate } => CortexEventDto {
                event_type: "awareness_updated".into(),
                value: health_score,
                value2: signals_per_second,
                name: String::new(),
                detail: format!("{:.4}", drop_rate),
            },
            rf_cortex::runtime::CortexEvent::HealingComplete { action_tag, healed } => CortexEventDto {
                event_type: "healing_complete".into(),
                value: if healed { 1.0 } else { 0.0 },
                value2: 0.0,
                name: action_tag,
                detail: String::new(),
            },
            rf_cortex::runtime::CortexEvent::SignalMilestone { total } => CortexEventDto {
                event_type: "signal_milestone".into(),
                value: total as f64,
                value2: 0.0,
                name: String::new(),
                detail: String::new(),
            },
        })
        .collect()
}

/// Number of pending events in the buffer (lock-free read).
#[flutter_rust_bridge::frb(sync)]
pub fn cortex_pending_event_count() -> u32 {
    cortex_shared()
        .map(|s| s.pending_event_count() as u32)
        .unwrap_or(0)
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

/// C FFI: Get total autonomic commands dispatched.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_commands_dispatched() -> u64 {
    cortex_shared()
        .map(|s| s.total_commands_dispatched.load(portable_atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// C FFI: Get total commands executed by executor.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_commands_executed() -> u64 {
    cortex_executor_shared()
        .map(|s| s.total_executed.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// C FFI: Healing success rate (0.0 to 1.0).
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_healing_rate() -> f64 {
    cortex_executor_shared()
        .map(|s| s.healing_rate() as f64)
        .unwrap_or(1.0)
}

/// C FFI: Total healed commands.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_total_healed() -> u64 {
    cortex_executor_shared()
        .map(|s| s.total_healed.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(0)
}

/// C FFI: Has any chronic anomaly?
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_has_chronic() -> i32 {
    if cortex_shared()
        .map(|s| s.has_chronic.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(false)
    {
        1
    } else {
        0
    }
}

/// C FFI: Get immune system active anomaly count.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_immune_active_count() -> u32 {
    cortex_shared()
        .and_then(|s| {
            let snap = s.immune_snapshot.lock().clone()?;
            Some(snap.active_count as u32)
        })
        .unwrap_or(0)
}

/// C FFI: Get immune system total escalations.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_immune_escalations() -> u64 {
    cortex_shared()
        .and_then(|s| {
            let snap = s.immune_snapshot.lock().clone()?;
            Some(snap.total_escalations)
        })
        .unwrap_or(0)
}

/// C FFI: Get number of pending events in the stream buffer.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_pending_event_count() -> u32 {
    cortex_shared()
        .map(|s| s.pending_event_count() as u32)
        .unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════
// C FFI: JSON endpoints for detailed data (Flutter consumes via dart:ffi)
//
// Pattern: Return a heap-allocated C string (NUL-terminated UTF-8).
// Flutter calls `cortex_free_string` to release memory.
// ═══════════════════════════════════════════════════════════════════════════

/// Free a string returned by any cortex_get_*_json function.
/// # Safety
/// `ptr` must be a pointer returned by one of the JSON FFI functions,
/// or null (in which case this is a no-op).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cortex_free_string(ptr: *mut std::os::raw::c_char) {
    if !ptr.is_null() {
        unsafe { drop(std::ffi::CString::from_raw(ptr)); }
    }
}

fn to_c_json(json: &str) -> *mut std::os::raw::c_char {
    std::ffi::CString::new(json)
        .unwrap_or_default()
        .into_raw()
}

/// C FFI: Get reflex stats as JSON array.
/// Returns `[{"name":"...","fire_count":N,"enabled":bool}, ...]`
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_reflex_stats_json() -> *mut std::os::raw::c_char {
    let stats = cortex_shared()
        .map(|s| {
            s.reflex_stats
                .lock()
                .iter()
                .map(|r| serde_json::json!({
                    "name": r.name,
                    "fire_count": r.fire_count,
                    "enabled": r.enabled,
                }))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    to_c_json(&serde_json::to_string(&stats).unwrap_or_else(|_| "[]".into()))
}

/// C FFI: Get recent patterns as JSON array.
/// Returns `[{"name":"...","severity":0.9,"description":"..."}, ...]`
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_recent_patterns_json() -> *mut std::os::raw::c_char {
    let patterns = cortex_shared()
        .map(|s| {
            s.recent_patterns
                .lock()
                .iter()
                .map(|p| serde_json::json!({
                    "name": p.name,
                    "severity": p.severity,
                    "description": p.description,
                }))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    to_c_json(&serde_json::to_string(&patterns).unwrap_or_else(|_| "[]".into()))
}

/// C FFI: Get immune system antibodies as JSON array.
/// Returns `[{"category":"...","count":N,"escalation_level":N,"max_severity":0.9,"is_chronic":bool}, ...]`
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_immune_antibodies_json() -> *mut std::os::raw::c_char {
    let antibodies = cortex_shared()
        .and_then(|s| {
            let snap = s.immune_snapshot.lock().clone()?;
            Some(
                snap.categories
                    .iter()
                    .map(|ab| serde_json::json!({
                        "category": ab.category,
                        "count": ab.count,
                        "escalation_level": ab.escalation_level,
                        "max_severity": ab.max_severity,
                        "is_chronic": ab.is_chronic,
                    }))
                    .collect::<Vec<_>>(),
            )
        })
        .unwrap_or_default();
    to_c_json(&serde_json::to_string(&antibodies).unwrap_or_else(|_| "[]".into()))
}

/// C FFI: Get executor recent actions as JSON array.
/// Returns `[{"action_tag":"...","reason":"...","priority":"...","result":"...","healed":bool}, ...]`
#[unsafe(no_mangle)]
pub extern "C" fn cortex_get_executor_actions_json() -> *mut std::os::raw::c_char {
    let actions = cortex_executor_shared()
        .map(|s| {
            s.recent_log
                .lock()
                .iter()
                .rev()
                .take(20)
                .map(|r| serde_json::json!({
                    "action_tag": r.action_tag,
                    "reason": r.reason,
                    "priority": format!("{:?}", r.priority),
                    "result": format!("{:?}", r.result),
                    "healing_detail": r.outcome.as_ref().map(|o| o.detail.as_str()).unwrap_or(""),
                    "healed": r.outcome.as_ref().map(|o| o.healed).unwrap_or(false),
                }))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    to_c_json(&serde_json::to_string(&actions).unwrap_or_else(|_| "[]".into()))
}

/// C FFI: Drain all pending events as JSON array.
/// Returns `[{"event_type":"...","value":N,"value2":N,"name":"...","detail":"..."}, ...]`
/// Clears the event buffer — each event is returned exactly once.
#[unsafe(no_mangle)]
pub extern "C" fn cortex_drain_events_json() -> *mut std::os::raw::c_char {
    let events = cortex_shared()
        .map(|s| {
            s.drain_events()
                .into_iter()
                .map(|e| {
                    let (etype, v1, v2, name, detail) = match e {
                        rf_cortex::runtime::CortexEvent::HealthChanged { old, new } =>
                            ("health_changed", new, old, "", String::new()),
                        rf_cortex::runtime::CortexEvent::DegradedStateChanged { is_degraded } =>
                            ("degraded_changed", if is_degraded { 1.0 } else { 0.0 }, 0.0, "", String::new()),
                        rf_cortex::runtime::CortexEvent::PatternRecognized { ref name, severity, ref description } =>
                            ("pattern_recognized", severity as f64, 0.0, name.as_str(), description.clone()),
                        rf_cortex::runtime::CortexEvent::ReflexFired { ref name, fire_count } =>
                            ("reflex_fired", fire_count as f64, 0.0, name.as_str(), String::new()),
                        rf_cortex::runtime::CortexEvent::CommandDispatched { ref action_tag, ref reason } =>
                            ("command_dispatched", 0.0, 0.0, action_tag.as_str(), reason.clone()),
                        rf_cortex::runtime::CortexEvent::ImmuneEscalation { ref category, escalation_level } =>
                            ("immune_escalation", escalation_level as f64, 0.0, category.as_str(), String::new()),
                        rf_cortex::runtime::CortexEvent::ChronicChanged { has_chronic } =>
                            ("chronic_changed", if has_chronic { 1.0 } else { 0.0 }, 0.0, "", String::new()),
                        rf_cortex::runtime::CortexEvent::AwarenessUpdated { health_score, signals_per_second, drop_rate } =>
                            ("awareness_updated", health_score, signals_per_second, "", format!("{:.4}", drop_rate)),
                        rf_cortex::runtime::CortexEvent::HealingComplete { ref action_tag, healed } =>
                            ("healing_complete", if healed { 1.0 } else { 0.0 }, 0.0, action_tag.as_str(), String::new()),
                        rf_cortex::runtime::CortexEvent::SignalMilestone { total } =>
                            ("signal_milestone", total as f64, 0.0, "", String::new()),
                    };
                    serde_json::json!({
                        "event_type": etype,
                        "value": v1,
                        "value2": v2,
                        "name": name,
                        "detail": detail,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    to_c_json(&serde_json::to_string(&events).unwrap_or_else(|_| "[]".into()))
}

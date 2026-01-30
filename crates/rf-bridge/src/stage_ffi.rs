//! Stage FFI — C bindings for rf-stage crate
//!
//! Exposes Stage, StageEvent, StageTrace, and TimingResolver to Flutter/Dart.

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};

use rf_stage::event::StageEvent;
use rf_stage::stage::Stage;
use rf_stage::taxonomy::BigWinTier;
use rf_stage::timing::{TimedStageTrace, TimingConfig, TimingProfile, TimingResolver};
use rf_stage::trace::StageTrace;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Stored traces (trace_id → StageTrace)
static TRACES: Lazy<RwLock<HashMap<u64, StageTrace>>> = Lazy::new(|| RwLock::new(HashMap::new()));

/// Stored timed traces
static TIMED_TRACES: Lazy<RwLock<HashMap<u64, TimedStageTrace>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Global timing resolver
static TIMING_RESOLVER: Lazy<RwLock<TimingResolver>> =
    Lazy::new(|| RwLock::new(TimingResolver::new()));

/// Next handle ID
static NEXT_HANDLE_ID: AtomicU64 = AtomicU64::new(1);

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE CREATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a StageEvent from JSON
/// Returns event JSON on success, null on error
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_event_json(
    stage_json: *const c_char,
    timestamp_ms: f64,
) -> *mut c_char {
    if stage_json.is_null() {
        return ptr::null_mut();
    }

    let json_str = match unsafe { CStr::from_ptr(stage_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let stage: Stage = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(_) => match parse_stage_string(json_str) {
            Some(s) => s,
            None => {
                log::error!("stage_create_event: parse error for '{}'", json_str);
                return ptr::null_mut();
            }
        },
    };

    let event = StageEvent::new(stage, timestamp_ms);

    match serde_json::to_string(&event) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Create SpinStart event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_spin_start(timestamp_ms: f64) -> *mut c_char {
    create_event_json(Stage::SpinStart, timestamp_ms)
}

/// Create SpinEnd event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_spin_end(timestamp_ms: f64) -> *mut c_char {
    create_event_json(Stage::SpinEnd, timestamp_ms)
}

/// Create ReelStop event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_reel_stop(
    reel_index: u8,
    symbols_json: *const c_char,
    timestamp_ms: f64,
) -> *mut c_char {
    let symbols = if symbols_json.is_null() {
        Vec::new()
    } else {
        match unsafe { CStr::from_ptr(symbols_json) }.to_str() {
            Ok(s) => serde_json::from_str(s).unwrap_or_default(),
            Err(_) => Vec::new(),
        }
    };

    create_event_json(Stage::ReelStop { reel_index, symbols }, timestamp_ms)
}

/// Create AnticipationOn event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_anticipation_on(
    reel_index: u8,
    reason: *const c_char,
    timestamp_ms: f64,
) -> *mut c_char {
    let reason_str = if reason.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(reason) }
            .to_str()
            .ok()
            .map(|s| s.to_string())
    };

    create_event_json(
        Stage::AnticipationOn {
            reel_index,
            reason: reason_str,
        },
        timestamp_ms,
    )
}

/// Create AnticipationOff event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_anticipation_off(reel_index: u8, timestamp_ms: f64) -> *mut c_char {
    create_event_json(Stage::AnticipationOff { reel_index }, timestamp_ms)
}

/// Create AnticipationTensionLayer event — per-reel tension with escalating intensity
/// reel_index: which reel (0-4)
/// tension_level: escalation level (1-4), higher = more intense
/// reason: optional reason string (e.g. "scatter", "bonus")
/// progress: 0.0 - 1.0 progress through anticipation
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_anticipation_tension_layer(
    reel_index: u8,
    tension_level: u8,
    reason: *const c_char,
    progress: f32,
    timestamp_ms: f64,
) -> *mut c_char {
    let reason_str = if reason.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(reason) }
            .to_str()
            .ok()
            .map(|s| s.to_string())
    };

    create_event_json(
        Stage::AnticipationTensionLayer {
            reel_index,
            tension_level,
            reason: reason_str,
            progress,
        },
        timestamp_ms,
    )
}

/// Create WinPresent event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_win_present(
    win_amount: f64,
    line_count: u32,
    timestamp_ms: f64,
) -> *mut c_char {
    create_event_json(
        Stage::WinPresent {
            win_amount,
            line_count: line_count as u8,
        },
        timestamp_ms,
    )
}

/// Create RollupStart event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_rollup_start(
    target_amount: f64,
    start_amount: f64,
    timestamp_ms: f64,
) -> *mut c_char {
    create_event_json(
        Stage::RollupStart {
            target_amount,
            start_amount,
        },
        timestamp_ms,
    )
}

/// Create RollupEnd event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_rollup_end(final_amount: f64, timestamp_ms: f64) -> *mut c_char {
    create_event_json(Stage::RollupEnd { final_amount }, timestamp_ms)
}

/// Create IdleStart event
#[unsafe(no_mangle)]
pub extern "C" fn stage_create_idle_start(timestamp_ms: f64) -> *mut c_char {
    create_event_json(Stage::IdleStart, timestamp_ms)
}

/// Helper: Create event JSON
fn create_event_json(stage: Stage, timestamp_ms: f64) -> *mut c_char {
    let event = StageEvent::new(stage, timestamp_ms);

    match serde_json::to_string(&event) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRACE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a new StageTrace
/// trace_id_str: Unique trace identifier string
/// game_id: Game identifier string
/// Returns trace handle (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_create(
    trace_id_str: *const c_char,
    game_id: *const c_char,
) -> u64 {
    if trace_id_str.is_null() || game_id.is_null() {
        return 0;
    }

    let trace_id = match unsafe { CStr::from_ptr(trace_id_str) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let game_id_str = match unsafe { CStr::from_ptr(game_id) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let trace = StageTrace::new(trace_id, game_id_str);
    let handle = NEXT_HANDLE_ID.fetch_add(1, Ordering::Relaxed);

    TRACES.write().insert(handle, trace);
    handle
}

/// Destroy a trace
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_destroy(handle: u64) {
    TRACES.write().remove(&handle);
}

/// Add event to trace (from JSON)
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_add_event(handle: u64, event_json: *const c_char) -> i32 {
    if event_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(event_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let event: StageEvent = match serde_json::from_str(json_str) {
        Ok(e) => e,
        Err(_) => return 0,
    };

    let mut traces = TRACES.write();
    if let Some(trace) = traces.get_mut(&handle) {
        trace.push(event);
        1
    } else {
        0
    }
}

/// Add event to trace (stage + timestamp)
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_add_stage(
    handle: u64,
    stage_json: *const c_char,
    timestamp_ms: f64,
) -> i32 {
    if stage_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(stage_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let stage: Stage = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(_) => match parse_stage_string(json_str) {
            Some(s) => s,
            None => return 0,
        },
    };

    let event = StageEvent::new(stage, timestamp_ms);

    let mut traces = TRACES.write();
    if let Some(trace) = traces.get_mut(&handle) {
        trace.push(event);
        1
    } else {
        0
    }
}

/// Get trace event count
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_event_count(handle: u64) -> i32 {
    let traces = TRACES.read();
    traces
        .get(&handle)
        .map(|t| t.events.len() as i32)
        .unwrap_or(0)
}

/// Get trace duration in ms
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_duration_ms(handle: u64) -> f64 {
    let traces = TRACES.read();
    traces.get(&handle).map(|t| t.duration_ms()).unwrap_or(0.0)
}

/// Get total win from trace
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_total_win(handle: u64) -> f64 {
    let traces = TRACES.read();
    traces.get(&handle).map(|t| t.total_win()).unwrap_or(0.0)
}

/// Check if trace has feature
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_has_feature(handle: u64) -> i32 {
    let traces = TRACES.read();
    traces
        .get(&handle)
        .map(|t| if t.has_feature() { 1 } else { 0 })
        .unwrap_or(0)
}

/// Check if trace has jackpot
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_has_jackpot(handle: u64) -> i32 {
    let traces = TRACES.read();
    traces
        .get(&handle)
        .map(|t| if t.has_jackpot() { 1 } else { 0 })
        .unwrap_or(0)
}

/// Get trace as JSON
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_to_json(handle: u64) -> *mut c_char {
    let traces = TRACES.read();
    let trace = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    match serde_json::to_string(trace) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Load trace from JSON
/// Returns trace handle (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_from_json(json: *const c_char) -> u64 {
    if json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let trace: StageTrace = match serde_json::from_str(json_str) {
        Ok(t) => t,
        Err(e) => {
            log::error!("stage_trace_from_json: parse error: {}", e);
            return 0;
        }
    };

    let handle = NEXT_HANDLE_ID.fetch_add(1, Ordering::Relaxed);
    TRACES.write().insert(handle, trace);
    handle
}

/// Validate trace
/// Returns validation JSON, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_validate(handle: u64) -> *mut c_char {
    let traces = TRACES.read();
    let trace = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    let validation = trace.validate();
    let validation_json = serde_json::json!({
        "is_valid": validation.is_valid(),
        "has_spin_start": validation.has_spin_start,
        "has_spin_end": validation.has_spin_end,
        "has_all_reels": validation.has_all_reels,
        "reel_stop_count": validation.reel_stop_count,
        "has_win_present": validation.has_win_present,
        "has_feature_enter": validation.has_feature_enter,
        "has_feature_exit": validation.has_feature_exit,
        "warnings": validation.warnings(),
    });

    match serde_json::to_string(&validation_json) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get trace summary JSON
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_summary(handle: u64) -> *mut c_char {
    let traces = TRACES.read();
    let trace = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    let summary = trace.summary();

    match serde_json::to_string(&summary) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get events by stage type
/// Returns JSON array, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_events_by_type(
    handle: u64,
    type_name: *const c_char,
) -> *mut c_char {
    if type_name.is_null() {
        return ptr::null_mut();
    }

    let type_str = match unsafe { CStr::from_ptr(type_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let traces = TRACES.read();
    let trace = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    let events: Vec<_> = trace.events_by_type(type_str);

    match serde_json::to_string(&events) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get all events in trace as JSON array
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_trace_get_events_json(handle: u64) -> *mut c_char {
    let traces = TRACES.read();
    let trace = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    match serde_json::to_string(&trace.events) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIMING RESOLVER
// ═══════════════════════════════════════════════════════════════════════════════

/// Get timing profile config as JSON
/// profile: "normal", "turbo", "mobile", "instant", "studio"
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_timing_get_config(profile: *const c_char) -> *mut c_char {
    if profile.is_null() {
        return ptr::null_mut();
    }

    let profile_str = match unsafe { CStr::from_ptr(profile) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let timing_profile = parse_timing_profile(profile_str);

    let resolver = TIMING_RESOLVER.read();
    let config = match resolver.get_config(timing_profile) {
        Some(c) => c,
        None => return ptr::null_mut(),
    };

    match serde_json::to_string(config) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Set custom timing config
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn stage_timing_set_config(config_json: *const c_char) -> i32 {
    if config_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(config_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config: TimingConfig = match serde_json::from_str(json_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("stage_timing_set_config: parse error: {}", e);
            return 0;
        }
    };

    TIMING_RESOLVER.write().set_profile(config);
    1
}

/// Resolve timing for a trace
/// Returns timed trace handle (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn stage_timing_resolve(trace_handle: u64, profile: *const c_char) -> u64 {
    if profile.is_null() {
        return 0;
    }

    let profile_str = match unsafe { CStr::from_ptr(profile) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let timing_profile = parse_timing_profile(profile_str);

    let traces = TRACES.read();
    let trace = match traces.get(&trace_handle) {
        Some(t) => t,
        None => return 0,
    };

    let resolver = TIMING_RESOLVER.read();
    let timed = resolver.resolve(trace, timing_profile);

    let handle = NEXT_HANDLE_ID.fetch_add(1, Ordering::Relaxed);
    TIMED_TRACES.write().insert(handle, timed);
    handle
}

/// Destroy timed trace
#[unsafe(no_mangle)]
pub extern "C" fn stage_timed_trace_destroy(handle: u64) {
    TIMED_TRACES.write().remove(&handle);
}

/// Get timed trace as JSON
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_timed_trace_to_json(handle: u64) -> *mut c_char {
    let traces = TIMED_TRACES.read();
    let timed = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    match serde_json::to_string(timed) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get timed trace total duration
#[unsafe(no_mangle)]
pub extern "C" fn stage_timed_trace_duration_ms(handle: u64) -> f64 {
    let traces = TIMED_TRACES.read();
    traces
        .get(&handle)
        .map(|t| t.total_duration_ms)
        .unwrap_or(0.0)
}

/// Get events at a specific time
/// Returns JSON array, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_timed_trace_events_at(handle: u64, time_ms: f64) -> *mut c_char {
    let traces = TIMED_TRACES.read();
    let timed = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    let events = timed.events_at(time_ms);

    match serde_json::to_string(&events) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get stage at a specific time
/// Returns event JSON or null
#[unsafe(no_mangle)]
pub extern "C" fn stage_timed_trace_stage_at(handle: u64, time_ms: f64) -> *mut c_char {
    let traces = TIMED_TRACES.read();
    let timed = match traces.get(&handle) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };

    let event = match timed.stage_at(time_ms) {
        Some(e) => e,
        None => return ptr::null_mut(),
    };

    match serde_json::to_string(event) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Parse timing profile string
fn parse_timing_profile(s: &str) -> TimingProfile {
    match s.to_lowercase().as_str() {
        "normal" => TimingProfile::Normal,
        "turbo" => TimingProfile::Turbo,
        "mobile" => TimingProfile::Mobile,
        "instant" => TimingProfile::Instant,
        "studio" => TimingProfile::Studio,
        _ => TimingProfile::Normal,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE PARSING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse a stage string to Stage enum
fn parse_stage_string(s: &str) -> Option<Stage> {
    let normalized = s.trim().to_uppercase();

    match normalized.as_str() {
        // Core lifecycle
        "SPIN_START" | "SPINSTART" => Some(Stage::SpinStart),
        "SPIN_END" | "SPINEND" | "SPIN_RESULT" => Some(Stage::SpinEnd),

        // Reels
        "REEL_SPINNING" | "REELSPINNING" | "REEL_SPIN" => {
            Some(Stage::ReelSpinning { reel_index: 0 })
        }

        // Anticipation
        "ANTICIPATION_ON" | "ANTICIPATION_START" => Some(Stage::AnticipationOn {
            reel_index: 0,
            reason: None,
        }),
        "ANTICIPATION_OFF" | "ANTICIPATION_END" => Some(Stage::AnticipationOff { reel_index: 0 }),

        // Wins
        "EVALUATE_WINS" | "WIN_EVAL" => Some(Stage::EvaluateWins),
        "WIN_PRESENT" | "WINPRESENT" => Some(Stage::WinPresent {
            win_amount: 0.0,
            line_count: 0,
        }),

        // Rollup
        "ROLLUP_START" | "ROLLUPSTART" => Some(Stage::RollupStart {
            start_amount: 0.0,
            target_amount: 0.0,
        }),
        "ROLLUP_TICK" | "ROLLUPTICK" => Some(Stage::RollupTick {
            current_amount: 0.0,
            progress: 0.0,
        }),
        "ROLLUP_END" | "ROLLUPEND" => Some(Stage::RollupEnd { final_amount: 0.0 }),

        // Features
        "FEATURE_EXIT" | "FEATUREEXIT" => Some(Stage::FeatureExit { total_win: 0.0 }),

        // Cascade
        "CASCADE_START" | "CASCADESTART" => Some(Stage::CascadeStart),
        "CASCADE_END" | "CASCADEEND" => Some(Stage::CascadeEnd {
            total_steps: 0,
            total_win: 0.0,
        }),

        // Gamble
        "GAMBLE_START" | "GAMBLESTART" => Some(Stage::GambleStart { stake_amount: 0.0 }),
        "GAMBLE_END" | "GAMBLEEND" => Some(Stage::GambleEnd {
            collected_amount: 0.0,
        }),

        // Idle
        "IDLE_START" | "IDLESTART" => Some(Stage::IdleStart),
        "IDLE_LOOP" | "IDLELOOP" => Some(Stage::IdleLoop),

        // Menu
        "MENU_OPEN" | "MENUOPEN" => Some(Stage::MenuOpen { menu_name: None }),
        "MENU_CLOSE" | "MENUCLOSE" => Some(Stage::MenuClose),

        // Jackpot
        "JACKPOT_END" | "JACKPOTEND" => Some(Stage::JackpotEnd),

        _ => {
            // Check for indexed patterns like REEL_STOP_3
            if let Some(idx) = parse_indexed_stage(&normalized, "REEL_STOP") {
                return Some(Stage::ReelStop {
                    reel_index: idx as u8,
                    symbols: vec![],
                });
            }
            if let Some(idx) = parse_indexed_stage(&normalized, "REEL_SPINNING") {
                return Some(Stage::ReelSpinning {
                    reel_index: idx as u8,
                });
            }
            if let Some(idx) = parse_indexed_stage(&normalized, "ANTICIPATION_ON") {
                return Some(Stage::AnticipationOn {
                    reel_index: idx as u8,
                    reason: None,
                });
            }
            if let Some(idx) = parse_indexed_stage(&normalized, "ANTICIPATION_OFF") {
                return Some(Stage::AnticipationOff {
                    reel_index: idx as u8,
                });
            }
            // Parse ANTICIPATION_TENSION_LAYER_R2_L3 → reel 2, level 3
            if normalized.starts_with("ANTICIPATION_TENSION_LAYER") {
                // Try to parse _R{reel}_L{level} pattern
                if let Some(rest) = normalized.strip_prefix("ANTICIPATION_TENSION_LAYER_R") {
                    let parts: Vec<&str> = rest.split("_L").collect();
                    if parts.len() == 2 {
                        if let (Ok(reel), Ok(level)) = (parts[0].parse::<u8>(), parts[1].parse::<u8>()) {
                            return Some(Stage::AnticipationTensionLayer {
                                reel_index: reel,
                                tension_level: level,
                                reason: None,
                                progress: 0.5,
                            });
                        }
                    }
                }
                // Generic tension layer
                return Some(Stage::AnticipationTensionLayer {
                    reel_index: 0,
                    tension_level: 1,
                    reason: None,
                    progress: 0.0,
                });
            }

            log::warn!("parse_stage_string: unknown stage '{}'", s);
            None
        }
    }
}

/// Parse indexed stage like "REEL_STOP_3" → Some(3)
fn parse_indexed_stage(s: &str, prefix: &str) -> Option<u32> {
    if let Some(rest) = s.strip_prefix(&format!("{}_", prefix)) {
        rest.parse().ok()
    } else {
        None
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAXONOMY HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get BigWinTier from win ratio (win/bet)
/// Returns tier name string, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_bigwin_tier_from_ratio(win_ratio: f64) -> *mut c_char {
    let tier = BigWinTier::from_ratio(win_ratio);
    let name = format!("{:?}", tier);
    match CString::new(name) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get all BigWinTier names as JSON array
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_bigwin_tier_all() -> *mut c_char {
    let tiers = vec!["Win", "BigWin", "MegaWin", "EpicWin", "UltraWin"];
    match serde_json::to_string(&tiers) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get all FeatureType names as JSON array
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_feature_types_all() -> *mut c_char {
    let types = vec![
        "FreeSpins",
        "PickBonus",
        "WheelBonus",
        "HoldAndSpin",
        "Cascade",
        "MegaWays",
        "Expanding",
        "Respin",
        "Gamble",
        "Jackpot",
        "Custom",
    ];
    match serde_json::to_string(&types) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string allocated by this module
#[unsafe(no_mangle)]
pub extern "C" fn stage_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Get stage type name from JSON
/// Returns type name string, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_get_type_name(stage_json: *const c_char) -> *mut c_char {
    if stage_json.is_null() {
        return ptr::null_mut();
    }

    let json_str = match unsafe { CStr::from_ptr(stage_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let stage: Stage = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(_) => match parse_stage_string(json_str) {
            Some(s) => s,
            None => return ptr::null_mut(),
        },
    };

    let type_name = stage.type_name();

    match CString::new(type_name) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Check if stage is a looping stage
#[unsafe(no_mangle)]
pub extern "C" fn stage_is_looping(stage_json: *const c_char) -> i32 {
    if stage_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(stage_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let stage: Stage = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(_) => match parse_stage_string(json_str) {
            Some(s) => s,
            None => return 0,
        },
    };

    if stage.is_looping() {
        1
    } else {
        0
    }
}

/// Get stage category
/// Returns category string, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_get_category(stage_json: *const c_char) -> *mut c_char {
    if stage_json.is_null() {
        return ptr::null_mut();
    }

    let json_str = match unsafe { CStr::from_ptr(stage_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let stage: Stage = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(_) => match parse_stage_string(json_str) {
            Some(s) => s,
            None => return ptr::null_mut(),
        },
    };

    let category = format!("{:?}", stage.category());

    match CString::new(category) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// List all trace handles
/// Returns JSON array of handles, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_list_traces() -> *mut c_char {
    let traces = TRACES.read();
    let ids: Vec<u64> = traces.keys().copied().collect();

    match serde_json::to_string(&ids) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Clear all traces
#[unsafe(no_mangle)]
pub extern "C" fn stage_clear_all() {
    TRACES.write().clear();
    TIMED_TRACES.write().clear();
}

/// Get available timing profiles
/// Returns JSON array of profile names, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn stage_list_timing_profiles() -> *mut c_char {
    let profiles = vec!["normal", "turbo", "mobile", "instant", "studio"];

    match serde_json::to_string(&profiles) {
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
    fn test_create_spin_start() {
        let result = stage_create_spin_start(0.0);
        assert!(!result.is_null());
        unsafe {
            let json = CStr::from_ptr(result).to_str().unwrap();
            assert!(json.contains("spin_start"));
            stage_free_string(result);
        }
    }

    #[test]
    fn test_trace_lifecycle() {
        let trace_id = CString::new("test-001").unwrap();
        let game_id = CString::new("test_game").unwrap();

        let handle = stage_trace_create(trace_id.as_ptr(), game_id.as_ptr());
        assert!(handle > 0);

        assert_eq!(stage_trace_event_count(handle), 0);

        let event = stage_create_spin_start(0.0);
        assert!(!event.is_null());

        let result = stage_trace_add_event(handle, event);
        assert_eq!(result, 1);
        unsafe {
            stage_free_string(event);
        }

        assert_eq!(stage_trace_event_count(handle), 1);

        stage_trace_destroy(handle);
    }

    #[test]
    fn test_timing_profiles() {
        let profiles = stage_list_timing_profiles();
        assert!(!profiles.is_null());
        unsafe {
            let json = CStr::from_ptr(profiles).to_str().unwrap();
            assert!(json.contains("normal"));
            assert!(json.contains("turbo"));
            stage_free_string(profiles);
        }
    }

    #[test]
    fn test_parse_stage_string() {
        assert!(parse_stage_string("SPIN_START").is_some());
        assert!(parse_stage_string("spin_end").is_some());
        assert!(parse_stage_string("REEL_STOP_3").is_some());
        assert!(parse_stage_string("unknown_xyz").is_none());
    }
}

//! FFI exports for Adaptive Layer Engine (ALE)
//!
//! Provides C-compatible functions for Flutter dart:ffi to control:
//! - ALE engine lifecycle
//! - Context switching
//! - Signal updates
//! - Profile management
//! - State queries
//!
//! Architecture:
//! - ALE engine and profile are held in global state
//! - FFI functions provide safe access
//! - For RT audio integration, engine would be ticked from audio callback
//!
//! # Thread Safety
//! Uses atomic CAS for initialization and RwLock for state access.

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::sync::atomic::{AtomicU8, Ordering};

use rf_ale::{
    AleProfile, Context, LayerId, MetricSignals, Rule, StabilityConfig, TransitionProfile,
};

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialization states
const STATE_UNINITIALIZED: u8 = 0;
const STATE_INITIALIZING: u8 = 1;
const STATE_INITIALIZED: u8 = 2;

/// Initialization state
static ALE_STATE: AtomicU8 = AtomicU8::new(STATE_UNINITIALIZED);

/// Current profile
static CURRENT_PROFILE: Lazy<RwLock<Option<AleProfile>>> = Lazy::new(|| RwLock::new(None));

/// Current engine state (simplified for FFI)
#[derive(Debug, Clone, Default)]
struct AleState {
    context_id: String,
    current_level: LayerId,
    target_level: Option<LayerId>,
    transition_progress: f32,
    playing: bool,
    manual_override: bool,
    active_rule: Option<String>,
    hold_remaining_ms: u32,
    signals: MetricSignals,
    timestamp_ms: u64,
}

/// Engine state
static ENGINE_STATE: Lazy<RwLock<AleState>> = Lazy::new(|| RwLock::new(AleState::default()));

/// Signal values (for updates)
static SIGNALS: Lazy<RwLock<MetricSignals>> = Lazy::new(|| RwLock::new(MetricSignals::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the ALE system
///
/// Returns 1 on success, 0 if already initialized
#[unsafe(no_mangle)]
pub extern "C" fn ale_init() -> i32 {
    match ALE_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            // Initialize with empty profile
            *CURRENT_PROFILE.write() = Some(AleProfile::new());
            *ENGINE_STATE.write() = AleState::default();
            *SIGNALS.write() = MetricSignals::new();

            ALE_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);
            log::info!("ale_init: Adaptive Layer Engine initialized");
            1
        }
        Err(STATE_INITIALIZING) => {
            while ALE_STATE.load(Ordering::SeqCst) == STATE_INITIALIZING {
                std::hint::spin_loop();
            }
            0
        }
        Err(_) => {
            log::warn!("ale_init: Already initialized");
            0
        }
    }
}

/// Shutdown the ALE system
#[unsafe(no_mangle)]
pub extern "C" fn ale_shutdown() {
    match ALE_STATE.compare_exchange(
        STATE_INITIALIZED,
        STATE_UNINITIALIZED,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            *CURRENT_PROFILE.write() = None;
            *ENGINE_STATE.write() = AleState::default();
            *SIGNALS.write() = MetricSignals::new();

            log::info!("ale_shutdown: Engine shutdown");
        }
        Err(_) => {
            log::warn!("ale_shutdown: Not initialized");
        }
    }
}

/// Check if ALE is initialized
#[unsafe(no_mangle)]
pub extern "C" fn ale_is_initialized() -> i32 {
    if ALE_STATE.load(Ordering::SeqCst) == STATE_INITIALIZED {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROFILE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Load a profile from JSON string
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn ale_load_profile_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match AleProfile::from_json(json_str) {
        Ok(profile) => {
            // Validate profile
            if let Err(errors) = profile.validate() {
                log::error!("ale_load_profile_json: Validation errors: {:?}", errors);
                return 0;
            }

            *CURRENT_PROFILE.write() = Some(profile);
            log::info!("ale_load_profile_json: Profile loaded successfully");
            1
        }
        Err(e) => {
            log::error!("ale_load_profile_json: Failed to parse: {:?}", e);
            0
        }
    }
}

/// Export current profile as JSON
///
/// Returns a heap-allocated string that must be freed with ale_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn ale_export_profile_json() -> *mut c_char {
    let guard = CURRENT_PROFILE.read();
    let json = match &*guard {
        Some(profile) => profile.to_json().unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Create a new empty profile
#[unsafe(no_mangle)]
pub extern "C" fn ale_create_empty_profile() {
    let profile = AleProfile::new();
    *CURRENT_PROFILE.write() = Some(profile);
    log::info!("ale_create_empty_profile: Created new profile");
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTEXT MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Switch to a context by ID
///
/// Returns 1 if successful, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn ale_switch_context(context_id: *const c_char) -> i32 {
    ale_switch_context_with_trigger(context_id, ptr::null())
}

/// Switch to a context with a trigger
///
/// Returns 1 if successful, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn ale_switch_context_with_trigger(
    context_id: *const c_char,
    trigger: *const c_char,
) -> i32 {
    if context_id.is_null() {
        return 0;
    }

    let ctx_str = unsafe {
        match CStr::from_ptr(context_id).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    let _trigger_opt = if trigger.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(trigger).to_str().ok().map(|s| s.to_string()) }
    };

    // Verify context exists
    let profile_guard = CURRENT_PROFILE.read();
    if let Some(ref profile) = *profile_guard {
        if !profile.contexts.contains_key(&ctx_str) {
            log::warn!("ale_switch_context: Unknown context '{}'", ctx_str);
            return 0;
        }
    } else {
        return 0;
    }
    drop(profile_guard);

    // Update state
    let mut state = ENGINE_STATE.write();
    state.context_id = ctx_str;
    // TODO: Implement proper transition logic
    log::info!("ale_switch_context: Switched to '{}'", state.context_id);
    1
}

/// Add a context to the current profile
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn ale_add_context_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match serde_json::from_str::<Context>(json_str) {
        Ok(context) => {
            let mut profile_guard = CURRENT_PROFILE.write();
            if let Some(ref mut profile) = *profile_guard {
                profile.add_context(context);
                1
            } else {
                0
            }
        }
        Err(e) => {
            log::error!("ale_add_context_json: Failed to parse: {:?}", e);
            0
        }
    }
}

/// Get list of context IDs as JSON array
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_context_ids_json() -> *mut c_char {
    let guard = CURRENT_PROFILE.read();
    let ids: Vec<&str> = match &*guard {
        Some(profile) => profile.contexts.keys().map(|s| s.as_str()).collect(),
        None => Vec::new(),
    };

    let json = serde_json::to_string(&ids).unwrap_or_else(|_| "[]".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIGNAL UPDATES
// ═══════════════════════════════════════════════════════════════════════════════

/// Update signals from JSON
///
/// JSON format: {"signalId": value, "signalId2": value2, ...}
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn ale_update_signals_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match serde_json::from_str::<std::collections::HashMap<String, f32>>(json_str) {
        Ok(updates) => {
            let mut signals = SIGNALS.write();
            for (id, value) in updates {
                signals.set(&id, value);
            }
            // Copy to engine state
            ENGINE_STATE.write().signals = signals.clone();
            1
        }
        Err(e) => {
            log::error!("ale_update_signals_json: Failed to parse: {:?}", e);
            0
        }
    }
}

/// Update a single signal
#[unsafe(no_mangle)]
pub extern "C" fn ale_update_signal(signal_id: *const c_char, value: f64) -> i32 {
    if signal_id.is_null() {
        return 0;
    }

    let id_str = unsafe {
        match CStr::from_ptr(signal_id).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let mut signals = SIGNALS.write();
    signals.set(id_str, value as f32);
    ENGINE_STATE.write().signals = signals.clone();
    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// LEVEL CONTROL
// ═══════════════════════════════════════════════════════════════════════════════

/// Force a specific layer level (manual override)
#[unsafe(no_mangle)]
pub extern "C" fn ale_force_level(level: i32) -> i32 {
    if !(0..=7).contains(&level) {
        return 0;
    }

    let mut state = ENGINE_STATE.write();
    state.current_level = level as LayerId;
    state.manual_override = true;
    log::info!("ale_force_level: Set level to L{}", level + 1);
    1
}

/// Release manual override
#[unsafe(no_mangle)]
pub extern "C" fn ale_release_manual_override() -> i32 {
    let mut state = ENGINE_STATE.write();
    state.manual_override = false;
    log::info!("ale_release_manual_override: Released override");
    1
}

/// Pause the engine
#[unsafe(no_mangle)]
pub extern "C" fn ale_pause() -> i32 {
    let mut state = ENGINE_STATE.write();
    state.playing = false;
    1
}

/// Resume the engine
#[unsafe(no_mangle)]
pub extern "C" fn ale_resume() -> i32 {
    let mut state = ENGINE_STATE.write();
    state.playing = true;
    1
}

/// Reset the engine to initial state
#[unsafe(no_mangle)]
pub extern "C" fn ale_reset() -> i32 {
    *ENGINE_STATE.write() = AleState::default();
    *SIGNALS.write() = MetricSignals::new();
    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE QUERIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current engine state as JSON
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_state_json() -> *mut c_char {
    let state = ENGINE_STATE.read();
    let json = serde_json::json!({
        "context_id": state.context_id,
        "current_level": state.current_level,
        "target_level": state.target_level,
        "transition_progress": state.transition_progress,
        "playing": state.playing,
        "manual_override": state.manual_override,
        "active_rule": state.active_rule,
        "hold_remaining_ms": state.hold_remaining_ms,
        "timestamp_ms": state.timestamp_ms
    });

    let json_str = serde_json::to_string(&json).unwrap_or_else(|_| "{}".to_string());

    match CString::new(json_str) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get current level (0-4 = L1-L5)
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_current_level() -> i32 {
    ENGINE_STATE.read().current_level as i32
}

/// Get current context ID
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_current_context() -> *mut c_char {
    let state = ENGINE_STATE.read();
    match CString::new(state.context_id.clone()) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Check if engine is playing
#[unsafe(no_mangle)]
pub extern "C" fn ale_is_playing() -> i32 {
    if ENGINE_STATE.read().playing { 1 } else { 0 }
}

/// Check if manual override is active
#[unsafe(no_mangle)]
pub extern "C" fn ale_is_manual_override() -> i32 {
    if ENGINE_STATE.read().manual_override {
        1
    } else {
        0
    }
}

/// Get hold remaining time (ms)
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_hold_remaining_ms() -> u32 {
    ENGINE_STATE.read().hold_remaining_ms
}

/// Get transition progress (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_transition_progress() -> f64 {
    ENGINE_STATE.read().transition_progress as f64
}

/// Get target level if transitioning (-1 if not transitioning)
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_target_level() -> i32 {
    match ENGINE_STATE.read().target_level {
        Some(level) => level as i32,
        None => -1,
    }
}

/// Get active rule ID (empty if none)
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_active_rule() -> *mut c_char {
    let rule = ENGINE_STATE.read().active_rule.clone().unwrap_or_default();

    match CString::new(rule) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RULE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Add a rule from JSON
#[unsafe(no_mangle)]
pub extern "C" fn ale_add_rule_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match serde_json::from_str::<Rule>(json_str) {
        Ok(rule) => {
            let mut profile_guard = CURRENT_PROFILE.write();
            if let Some(ref mut profile) = *profile_guard {
                profile.add_rule(rule);
                1
            } else {
                0
            }
        }
        Err(e) => {
            log::error!("ale_add_rule_json: Failed to parse: {:?}", e);
            0
        }
    }
}

/// Remove a rule by ID
#[unsafe(no_mangle)]
pub extern "C" fn ale_remove_rule(rule_id: *const c_char) -> i32 {
    if rule_id.is_null() {
        return 0;
    }

    let id_str = unsafe {
        match CStr::from_ptr(rule_id).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let mut profile_guard = CURRENT_PROFILE.write();
    if let Some(ref mut profile) = *profile_guard {
        profile.rules.retain(|r| r.id != id_str);
        1
    } else {
        0
    }
}

/// Get all rules as JSON array
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_rules_json() -> *mut c_char {
    let guard = CURRENT_PROFILE.read();
    let json = match &*guard {
        Some(profile) => serde_json::to_string(&profile.rules).unwrap_or_else(|_| "[]".to_string()),
        None => "[]".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STABILITY CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Update stability config from JSON
#[unsafe(no_mangle)]
pub extern "C" fn ale_set_stability_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match serde_json::from_str::<StabilityConfig>(json_str) {
        Ok(config) => {
            let mut profile_guard = CURRENT_PROFILE.write();
            if let Some(ref mut profile) = *profile_guard {
                profile.stability = config;
                1
            } else {
                0
            }
        }
        Err(e) => {
            log::error!("ale_set_stability_json: Failed to parse: {:?}", e);
            0
        }
    }
}

/// Get current stability config as JSON
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_stability_json() -> *mut c_char {
    let guard = CURRENT_PROFILE.read();
    let json = match &*guard {
        Some(profile) => {
            serde_json::to_string(&profile.stability).unwrap_or_else(|_| "{}".to_string())
        }
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSITION PROFILES
// ═══════════════════════════════════════════════════════════════════════════════

/// Add a transition profile from JSON
#[unsafe(no_mangle)]
pub extern "C" fn ale_add_transition_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match serde_json::from_str::<TransitionProfile>(json_str) {
        Ok(profile) => {
            let mut profile_guard = CURRENT_PROFILE.write();
            if let Some(ref mut p) = *profile_guard {
                p.add_transition(profile);
                1
            } else {
                0
            }
        }
        Err(e) => {
            log::error!("ale_add_transition_json: Failed to parse: {:?}", e);
            0
        }
    }
}

/// Get all transition profiles as JSON
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_transitions_json() -> *mut c_char {
    let guard = CURRENT_PROFILE.read();
    let json = match &*guard {
        Some(profile) => {
            serde_json::to_string(&profile.transitions).unwrap_or_else(|_| "{}".to_string())
        }
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER VOLUMES (for audio integration)
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current layer volumes as JSON
/// Returns {"volumes": [v0, v1, v2, v3, v4, v5, v6, v7], "active": n}
#[unsafe(no_mangle)]
pub extern "C" fn ale_get_layer_volumes_json() -> *mut c_char {
    let state = ENGINE_STATE.read();
    let current = state.current_level as usize;

    let mut volumes = [0.0f32; 8];
    if current < 8 {
        volumes[current] = 1.0;
    }

    let json = serde_json::json!({
        "volumes": volumes.to_vec(),
        "active": if current < 8 { 1 } else { 0 }
    });

    let json_str = serde_json::to_string(&json).unwrap_or_else(|_| "{}".to_string());

    match CString::new(json_str) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by ALE FFI functions
#[unsafe(no_mangle)]
pub extern "C" fn ale_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn test_ale_lifecycle() {
        let _guard = TEST_LOCK.lock().unwrap();

        ale_shutdown();

        assert_eq!(ale_init(), 1);
        assert_eq!(ale_is_initialized(), 1);
        assert_eq!(ale_init(), 0); // Double init fails

        ale_shutdown();
        assert_eq!(ale_is_initialized(), 0);
    }

    #[test]
    fn test_ale_level_control() {
        let _guard = TEST_LOCK.lock().unwrap();

        ale_shutdown();
        ale_init();

        assert_eq!(ale_force_level(3), 1);
        assert_eq!(ale_get_current_level(), 3);
        assert_eq!(ale_is_manual_override(), 1);

        assert_eq!(ale_release_manual_override(), 1);
        assert_eq!(ale_is_manual_override(), 0);

        assert_eq!(ale_force_level(-1), 0); // Invalid level
        assert_eq!(ale_force_level(10), 0); // Invalid level

        ale_shutdown();
    }
}

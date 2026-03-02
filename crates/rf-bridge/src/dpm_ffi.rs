//! DPM: Dynamic Priority Matrix FFI Bridge
//!
//! Exposes DPM functions via C FFI. Uses the shared AUREXIS ENGINE global
//! from aurexis_ffi.rs since DynamicPriorityMatrix lives inside AurexisEngine.

use std::ffi::{CString, c_char};
use std::ptr;

use crate::aurexis_ffi::ENGINE;
use rf_aurexis::priority::{EmotionalState, EventType, SurvivalAction};

// ═══════════════════════════════════════════════════════════════════════════════
// EMOTIONAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Set emotional state (0-6). Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_set_emotional_state(state_index: u8) -> i32 {
    let state = match EmotionalState::from_index(state_index) {
        Some(s) => s,
        None => return 0,
    };
    if let Some(ref mut engine) = *ENGINE.write() {
        engine.priority_matrix_mut().set_emotional_state(state);
        return 1;
    }
    0
}

/// Get current emotional state index (0-6). Returns 255 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_get_emotional_state() -> u8 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.priority_matrix().emotional_state() as u8;
    }
    255
}

/// Get emotional state name. Caller must free with dpm_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_emotional_state_name(state_index: u8) -> *mut c_char {
    let state = match EmotionalState::from_index(state_index) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(state.name()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get number of emotional states (always 7).
#[unsafe(no_mangle)]
pub extern "C" fn dpm_emotional_state_count() -> u32 {
    EmotionalState::COUNT as u32
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRIORITY COMPUTATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Compute priority score for a single event. Returns score or -1.0 on error.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_compute_priority(event_type: u8, context_modifier: f64) -> f64 {
    let et = match EventType::from_index(event_type) {
        Some(e) => e,
        None => return -1.0,
    };
    if let Some(ref engine) = *ENGINE.read() {
        return engine
            .priority_matrix()
            .compute_priority(et, context_modifier);
    }
    -1.0
}

/// Submit voices for DPM survival computation.
/// voice_data: flat array of (voice_id: u32, event_type: u8, context_modifier: f64) triples.
/// count: number of voices.
/// Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_compute_voices(
    voice_ids: *const u32,
    event_types: *const u8,
    context_modifiers: *const f64,
    count: u32,
) -> i32 {
    if voice_ids.is_null() || event_types.is_null() || context_modifiers.is_null() || count == 0 {
        return 0;
    }

    let mut voices = Vec::with_capacity(count as usize);
    unsafe {
        for i in 0..count as usize {
            let vid = *voice_ids.add(i);
            let et_idx = *event_types.add(i);
            let cm = *context_modifiers.add(i);
            if let Some(et) = EventType::from_index(et_idx) {
                voices.push((vid, et, cm));
            }
        }
    }

    if let Some(ref mut engine) = *ENGINE.write() {
        engine.priority_matrix_mut().compute(&voices);
        return 1;
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════════
// DPM OUTPUT QUERIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get retained count from last DPM computation.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_retained_count() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.priority_matrix().last_output().retained_count;
    }
    0
}

/// Get attenuated count from last DPM computation.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_attenuated_count() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.priority_matrix().last_output().attenuated_count;
    }
    0
}

/// Get suppressed count from last DPM computation.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_suppressed_count() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.priority_matrix().last_output().suppressed_count;
    }
    0
}

/// Get ducked count from last DPM computation.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_ducked_count() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.priority_matrix().last_output().ducked_count;
    }
    0
}

/// Check if JACKPOT_GRAND override is active.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_is_jackpot_override() -> i32 {
    if let Some(ref engine) = *ENGINE.read() {
        return if engine
            .priority_matrix()
            .last_output()
            .jackpot_override_active
        {
            1
        } else {
            0
        };
    }
    0
}

/// Get survival action for a specific voice (by voice_id).
/// Returns: 0=Retain, 1=Attenuate, 2=Suppress, 3=DuckCurve, 255=NotFound.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_voice_survival_action(voice_id: u32) -> u8 {
    if let Some(ref engine) = *ENGINE.read() {
        for result in &engine.priority_matrix().last_output().survival_results {
            if result.voice_id == voice_id {
                return match result.action {
                    SurvivalAction::Retain => 0,
                    SurvivalAction::Attenuate => 1,
                    SurvivalAction::Suppress => 2,
                    SurvivalAction::DuckCurve { .. } => 3,
                };
            }
        }
    }
    255
}

/// Get event type count (always 8).
#[unsafe(no_mangle)]
pub extern "C" fn dpm_event_type_count() -> u32 {
    EventType::COUNT as u32
}

/// Get event type name. Caller must free with dpm_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_event_type_name(event_type: u8) -> *mut c_char {
    let et = match EventType::from_index(event_type) {
        Some(e) => e,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(et.name()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get base weight for an event type. Returns -1.0 on error.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_event_base_weight(event_type: u8) -> f64 {
    match EventType::from_index(event_type) {
        Some(et) => et.base_weight(),
        None => -1.0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BAKE OUTPUT (DPM-10)
// ═══════════════════════════════════════════════════════════════════════════════

/// Get event weights JSON. Caller must free with dpm_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_event_weights_json() -> *mut c_char {
    use rf_aurexis::priority::DynamicPriorityMatrix;
    if let Ok(json) = DynamicPriorityMatrix::event_weights_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

/// Get profile modifiers JSON. Caller must free with dpm_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_profile_modifiers_json() -> *mut c_char {
    use rf_aurexis::priority::DynamicPriorityMatrix;
    if let Ok(json) = DynamicPriorityMatrix::profile_modifiers_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

/// Get context rules JSON. Caller must free with dpm_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_context_rules_json() -> *mut c_char {
    use rf_aurexis::priority::DynamicPriorityMatrix;
    if let Ok(json) = DynamicPriorityMatrix::context_rules_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

/// Get priority matrix output JSON. Caller must free with dpm_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_priority_matrix_json() -> *mut c_char {
    if let Some(ref engine) = *ENGINE.read() {
        if let Ok(json) = engine.priority_matrix().priority_matrix_json() {
            if let Ok(s) = CString::new(json) {
                return s.into_raw();
            }
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by dpm_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn dpm_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

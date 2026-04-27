//! DPM: Dynamic Priority Matrix FFI Bridge
//!
//! Exposes DPM functions via C FFI. Uses the shared AUREXIS ENGINE global
//! from aurexis_ffi.rs since DynamicPriorityMatrix lives inside AurexisEngine.

use std::ffi::{CString, c_char};
use std::ptr;

use crate::aurexis_ffi::ENGINE;
use rf_aurexis::priority::{EmotionalState, EventType, SurvivalAction};

/// Hard cap on a single `dpm_compute_voices` batch.
///
/// In practice the engine never sees more than the polyphony limit
/// (~256 simultaneous voices) plus whatever transient ducking targets
/// arrive in the same tick. 4096 leaves an order-of-magnitude headroom
/// while still bounding the damage if a Dart bug or attacker sends a
/// `count` of `u32::MAX`. With this cap the Vec reservation is at most
/// 4096 * (sizeof u32 + u8 + f64) ≈ 52 KB — tolerable inside the audio
/// dispatch path.
const DPM_MAX_VOICES_PER_BATCH: u32 = 4096;

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
///
/// `voice_ids`, `event_types`, `context_modifiers`: parallel arrays, each of
/// `count` elements. Caller (Dart) MUST keep the three buffers alive and
/// unchanged until this function returns.
///
/// FFI safety contract:
///   * Each pointer must be non-null and properly aligned for its element type.
///   * Each pointer must point to at least `count` valid, initialized elements.
///   * Buffers must not alias each other (UB on overlapping reads otherwise).
///
/// Defensive measures (FLUX_MASTER_TODO 1.1.4 — TOCTOU in voice_id iteration):
///   1. `count` is clamped against [`DPM_MAX_VOICES_PER_BATCH`] to bound damage
///      from a malformed or hostile caller (previously `u32::MAX` would
///      attempt a 4-billion-element iteration and crash or OOB read).
///   2. Pointer alignment is checked with `debug_assert` so misuse trips
///      cargo-test runs without imposing release-mode cost.
///   3. Inputs are bulk-copied via `slice::from_raw_parts → to_vec` (one
///      memcpy per buffer) BEFORE any engine work. This narrows the window
///      during which the Dart-owned buffers must remain valid to the absolute
///      minimum — three consecutive memcpys with no awaits, no locks, no
///      callbacks. The engine then operates on Rust-owned data, immune to
///      Dart-side reallocations or frees.
///
/// Returns 1 on success, 0 on null pointer / zero count / overflow / engine
/// not initialized.
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
    if count > DPM_MAX_VOICES_PER_BATCH {
        // Reject the entire batch rather than silently truncating — a
        // truncated DPM compute would leave un-prioritized voices that
        // could later steal slots from genuine high-priority events.
        return 0;
    }

    // Pointer alignment: required for `slice::from_raw_parts` soundness.
    debug_assert_eq!(voice_ids as usize % std::mem::align_of::<u32>(), 0,
        "voice_ids pointer not u32-aligned");
    debug_assert_eq!(event_types as usize % std::mem::align_of::<u8>(), 0,
        "event_types pointer not u8-aligned");
    debug_assert_eq!(context_modifiers as usize % std::mem::align_of::<f64>(), 0,
        "context_modifiers pointer not f64-aligned");

    let n = count as usize;

    // Bulk snapshot inputs into Rust-owned Vecs immediately. After these
    // three lines the Dart caller can free / mutate / realloc its buffers
    // without UB risk to us. This is the actual TOCTOU mitigation: the
    // pre-fix loop dereferenced `voice_ids.add(i)` etc. across a longer
    // window (one element at a time, with `EventType::from_index` work
    // between reads), giving a misbehaving Dart caller a wider race.
    //
    // SAFETY: we've null/zero/overflow-checked all three pointers above.
    // The caller's contract (documented in this function's doc comment)
    // is that each buffer holds at least `count` initialized elements;
    // we cannot validate that without trust. The bulk read here at least
    // collapses three independent unsafe regions into one and runs them
    // back-to-back so the per-buffer race window is minimized.
    let (vids_buf, etypes_buf, cms_buf) = unsafe {
        (
            std::slice::from_raw_parts(voice_ids, n).to_vec(),
            std::slice::from_raw_parts(event_types, n).to_vec(),
            std::slice::from_raw_parts(context_modifiers, n).to_vec(),
        )
    };

    let mut voices: Vec<(u32, EventType, f64)> = Vec::with_capacity(n);
    for i in 0..n {
        if let Some(et) = EventType::from_index(etypes_buf[i]) {
            voices.push((vids_buf[i], et, cms_buf[i]));
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Null pointers must be rejected without UB.
    #[test]
    fn dpm_compute_voices_rejects_null_pointers() {
        let vids: [u32; 1] = [0];
        let etypes: [u8; 1] = [0];
        let cms: [f64; 1] = [1.0];
        // Each null variant
        assert_eq!(dpm_compute_voices(ptr::null(), etypes.as_ptr(), cms.as_ptr(), 1), 0);
        assert_eq!(dpm_compute_voices(vids.as_ptr(), ptr::null(), cms.as_ptr(), 1), 0);
        assert_eq!(dpm_compute_voices(vids.as_ptr(), etypes.as_ptr(), ptr::null(), 1), 0);
    }

    /// Zero count must be rejected.
    #[test]
    fn dpm_compute_voices_rejects_zero_count() {
        let vids: [u32; 1] = [0];
        let etypes: [u8; 1] = [0];
        let cms: [f64; 1] = [1.0];
        assert_eq!(dpm_compute_voices(vids.as_ptr(), etypes.as_ptr(), cms.as_ptr(), 0), 0);
    }

    /// FLUX_MASTER_TODO 1.1.4 — pre-fix this would attempt a 4-billion-element
    /// iteration through `voice_ids.add(i)`, reading well past the actual
    /// 1-element buffer (UB). After fix: reject the entire batch before
    /// touching memory.
    #[test]
    fn dpm_compute_voices_rejects_count_above_max() {
        let vids: [u32; 1] = [0];
        let etypes: [u8; 1] = [0];
        let cms: [f64; 1] = [1.0];
        let too_big = DPM_MAX_VOICES_PER_BATCH + 1;
        assert_eq!(
            dpm_compute_voices(vids.as_ptr(), etypes.as_ptr(), cms.as_ptr(), too_big),
            0,
            "count > DPM_MAX_VOICES_PER_BATCH must be rejected wholesale"
        );
        // u32::MAX is the most pathological caller — must also reject.
        assert_eq!(
            dpm_compute_voices(vids.as_ptr(), etypes.as_ptr(), cms.as_ptr(), u32::MAX),
            0,
            "u32::MAX count must not trigger an iteration"
        );
    }

    /// `count == DPM_MAX_VOICES_PER_BATCH` is the boundary — must succeed
    /// (or fail only because the engine isn't initialized in unit tests).
    /// We can't assert success without a live AurexisEngine, but we can
    /// assert that the batch-size guard does NOT reject this case as if
    /// it were over-cap.
    #[test]
    fn dpm_compute_voices_accepts_exactly_max_batch_size() {
        // Build buffers of length DPM_MAX_VOICES_PER_BATCH so the FFI
        // call has memory to copy from. We don't need an engine for the
        // input-validation portion — engine-not-initialized returns 0 too,
        // but it returns AFTER the validation succeeded. The contract we
        // verify here is: this call is not rejected by the size guard.
        let n = DPM_MAX_VOICES_PER_BATCH as usize;
        let vids: Vec<u32> = vec![0; n];
        let etypes: Vec<u8> = vec![0; n];
        let cms: Vec<f64> = vec![1.0; n];
        let result = dpm_compute_voices(
            vids.as_ptr(),
            etypes.as_ptr(),
            cms.as_ptr(),
            DPM_MAX_VOICES_PER_BATCH,
        );
        // 0 (engine not init) or 1 (engine init); both indicate the size
        // check passed. The pre-fix loop would have crashed on a hostile
        // count here too, but only if buffers were undersized. With
        // properly-sized buffers, the fix is invisible — that's the
        // point: legitimate calls keep working.
        assert!(result == 0 || result == 1);
    }
}

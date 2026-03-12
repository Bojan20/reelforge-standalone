//! FFI exports for Tempo State Engine
//!
//! Provides C-compatible functions for Flutter dart:ffi to control:
//! - Tempo state registration and configuration
//! - Transition rule setup
//! - State triggering (UI thread → audio thread)
//! - Beat position and BPM queries
//!
//! # Thread Safety
//! Uses RwLock for state management. Trigger functions use atomic stores
//! for lock-free UI→Audio communication.

use std::sync::LazyLock;
use parking_lot::RwLock;
use std::ffi::{CStr, c_char};
use std::sync::atomic::{AtomicBool, Ordering};

use rf_dsp::beat_grid::{SyncMode, TempoRampType};
use rf_dsp::crossfade::FadeCurve;
use rf_engine::tempo_state::{TempoStateEngine, TempoTransitionRule};

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

static TEMPO_ENGINE: LazyLock<RwLock<Option<TempoStateEngine>>> = LazyLock::new(|| RwLock::new(None));
static TEMPO_INITIALIZED: AtomicBool = AtomicBool::new(false);

// ═══════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the Tempo State Engine
///
/// # Arguments
/// * `source_bpm` - Original BPM of the music material
/// * `beats_per_bar` - Time signature numerator (e.g., 4 for 4/4)
/// * `sample_rate` - Audio sample rate (e.g., 44100.0)
///
/// Returns 1 on success, 0 if already initialized
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_init(source_bpm: f64, beats_per_bar: u32, sample_rate: f64) -> i32 {
    let engine = TempoStateEngine::new(source_bpm, beats_per_bar, sample_rate);
    *TEMPO_ENGINE.write() = Some(engine);
    TEMPO_INITIALIZED.store(true, Ordering::Release);
    1
}

/// Destroy the Tempo State Engine and free resources
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_destroy() {
    *TEMPO_ENGINE.write() = None;
    TEMPO_INITIALIZED.store(false, Ordering::Release);
}

/// Check if engine is initialized
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_is_initialized() -> i32 {
    if TEMPO_INITIALIZED.load(Ordering::Acquire) { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE REGISTRATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Add a tempo state
///
/// # Arguments
/// * `name` - State name (null-terminated C string, e.g., "base_game")
/// * `target_bpm` - Target BPM for this state
///
/// Returns state ID on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_add(name: *const c_char, target_bpm: f64) -> u32 {
    if name.is_null() { return 0; }
    let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let mut guard = TEMPO_ENGINE.write();
    match guard.as_mut() {
        Some(engine) => engine.add_state(name_str, target_bpm),
        None => 0,
    }
}

/// Set the initial active state
///
/// Must be called after adding states and before processing.
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_set_initial(name: *const c_char) -> i32 {
    if name.is_null() { return 0; }
    let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let mut guard = TEMPO_ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_initial_state(name_str); 1 },
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSITION RULES
// ═══════════════════════════════════════════════════════════════════════════════

/// Set a transition rule between two states
///
/// # Arguments
/// * `from_state_id` - Source state ID (0 = wildcard/any)
/// * `to_state_id` - Target state ID
/// * `sync_mode` - 0=immediate, 1=beat, 2=bar, 3=phrase, 4=downbeat
/// * `duration_bars` - Crossfade duration in bars
/// * `ramp_type` - 0=instant, 1=linear, 2=sCurve
/// * `fade_curve` - 0=linear, 1=equalPower, 2=sCurve
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_set_transition(
    from_state_id: u32,
    to_state_id: u32,
    sync_mode: u32,
    duration_bars: u32,
    ramp_type: u32,
    fade_curve: u32,
) -> i32 {
    let rule = TempoTransitionRule {
        from_state: from_state_id,
        to_state: to_state_id,
        sync_mode: sync_mode_from_u32(sync_mode),
        duration_bars,
        ramp_type: ramp_type_from_u32(ramp_type),
        fade_curve: fade_curve_from_u32(fade_curve),
    };

    let mut guard = TEMPO_ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_transition_rule(rule); 1 },
        None => 0,
    }
}

/// Set the default transition rule (used when no specific rule matches)
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_set_default_transition(
    sync_mode: u32,
    duration_bars: u32,
    ramp_type: u32,
    fade_curve: u32,
) -> i32 {
    let rule = TempoTransitionRule {
        from_state: 0,
        to_state: 0,
        sync_mode: sync_mode_from_u32(sync_mode),
        duration_bars,
        ramp_type: ramp_type_from_u32(ramp_type),
        fade_curve: fade_curve_from_u32(fade_curve),
    };

    let mut guard = TEMPO_ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_default_rule(rule); 1 },
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE TRIGGERING
// ═══════════════════════════════════════════════════════════════════════════════

/// Trigger a transition to a new tempo state
///
/// This is safe to call from the UI thread. The transition will start
/// at the next sync point as defined by the transition rule.
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_trigger(name: *const c_char) -> i32 {
    if name.is_null() { return 0; }
    let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => { engine.trigger_state(name_str); 1 },
        None => 0,
    }
}

/// Trigger a transition by state ID
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_trigger_by_id(state_id: u32) -> i32 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => { engine.trigger_state_by_id(state_id); 1 },
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUERIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current BPM (atomic read, safe from any thread)
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_get_bpm() -> f64 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => engine.current_bpm(),
        None => 0.0,
    }
}

/// Get current beat position within the bar (0.0 to beats_per_bar)
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_get_beat() -> f64 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => engine.beat_position().beat,
        None => 0.0,
    }
}

/// Get current bar number
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_get_bar() -> u32 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => engine.beat_position().bar,
        None => 0,
    }
}

/// Check if a transition is in progress
/// Returns: 0=steady, 1=waiting_for_sync, 2=crossfading
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_get_phase() -> u32 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => match engine.phase() {
            rf_engine::tempo_state::EnginePhase::Steady => 0,
            rf_engine::tempo_state::EnginePhase::WaitingForSync => 1,
            rf_engine::tempo_state::EnginePhase::Crossfading => 2,
        },
        None => 0,
    }
}

/// Get crossfade progress (0.0 to 1.0)
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_get_crossfade_progress() -> f64 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => engine.crossfade_progress(),
        None => 0.0,
    }
}

/// Get voice A stretch factor
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_get_voice_a_stretch() -> f64 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => engine.voice_a_stretch(),
        None => 1.0,
    }
}

/// Get voice B stretch factor
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_get_voice_b_stretch() -> f64 {
    let guard = TEMPO_ENGINE.read();
    match guard.as_ref() {
        Some(engine) => engine.voice_b_stretch(),
        None => 1.0,
    }
}

/// Reset engine to initial state
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_reset() -> i32 {
    let mut guard = TEMPO_ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.reset(); 1 },
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO THREAD PROCESSING
// ═══════════════════════════════════════════════════════════════════════════════

/// Process one audio block — advance beat grid and manage transitions
///
/// # Arguments
/// * `num_samples` - Block size
/// * `out_voice_a_stretch` - Output: stretch factor for voice A
/// * `out_voice_a_gain` - Output: gain for voice A
/// * `out_voice_b_stretch` - Output: stretch factor for voice B
/// * `out_voice_b_gain` - Output: gain for voice B
/// * `out_bpm` - Output: current BPM
///
/// Returns 1 on success, 0 if not initialized
#[unsafe(no_mangle)]
pub extern "C" fn tempo_state_process(
    num_samples: u32,
    out_voice_a_stretch: *mut f64,
    out_voice_a_gain: *mut f64,
    out_voice_b_stretch: *mut f64,
    out_voice_b_gain: *mut f64,
    out_bpm: *mut f64,
) -> i32 {
    if out_voice_a_stretch.is_null() || out_voice_a_gain.is_null()
        || out_voice_b_stretch.is_null() || out_voice_b_gain.is_null()
        || out_bpm.is_null()
    {
        return 0;
    }

    let mut guard = TEMPO_ENGINE.write();
    match guard.as_mut() {
        Some(engine) => {
            let gains = engine.process(num_samples as usize);
            unsafe {
                *out_voice_a_stretch = gains.voice_a_stretch;
                *out_voice_a_gain = gains.voice_a_gain;
                *out_voice_b_stretch = gains.voice_b_stretch;
                *out_voice_b_gain = gains.voice_b_gain;
                *out_bpm = gains.bpm;
            }
            1
        },
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

fn sync_mode_from_u32(v: u32) -> SyncMode {
    match v {
        0 => SyncMode::Immediate,
        1 => SyncMode::Beat,
        2 => SyncMode::Bar,
        3 => SyncMode::Phrase,
        4 => SyncMode::Downbeat,
        _ => SyncMode::Bar,
    }
}

fn ramp_type_from_u32(v: u32) -> TempoRampType {
    match v {
        0 => TempoRampType::Instant,
        1 => TempoRampType::Linear,
        2 => TempoRampType::SCurve,
        _ => TempoRampType::Linear,
    }
}

fn fade_curve_from_u32(v: u32) -> FadeCurve {
    match v {
        0 => FadeCurve::Linear,
        1 => FadeCurve::EqualPower,
        2 => FadeCurve::SCurve,
        _ => FadeCurve::EqualPower,
    }
}

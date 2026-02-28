//! AUREXIS™ C FFI Bridge
//!
//! Exposes the AUREXIS intelligence engine to Flutter/Dart via C FFI.
//! Follows the same pattern as `ale_ffi.rs`:
//! - Atomic CAS initialization
//! - Lazy<RwLock<>> for global state
//! - CString for string return (caller must free via aurexis_free_string)
//! - JSON for complex data transport
//! - i32 return codes: 1 = success, 0 = failure

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicU8, Ordering};

use rf_aurexis::core::config::{AurexisConfig, PlatformType};
use rf_aurexis::core::engine::AurexisEngine;
use rf_aurexis::geometry::ScreenEvent;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

const STATE_UNINITIALIZED: u8 = 0;
const STATE_INITIALIZING: u8 = 1;
const STATE_INITIALIZED: u8 = 2;

static AUREXIS_STATE: AtomicU8 = AtomicU8::new(STATE_UNINITIALIZED);
static ENGINE: Lazy<RwLock<Option<AurexisEngine>>> = Lazy::new(|| RwLock::new(None));
static CONFIG: Lazy<RwLock<AurexisConfig>> = Lazy::new(|| RwLock::new(AurexisConfig::default()));

// ═══════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the AUREXIS engine. Must be called before any other function.
/// Returns 1 on success, 0 if already initialized or error.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_init() -> i32 {
    match AUREXIS_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            let config = CONFIG.read().clone();
            let mut engine = AurexisEngine::with_config(config);
            engine.initialize();
            *ENGINE.write() = Some(engine);
            AUREXIS_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);
            log::info!("AUREXIS FFI: Engine initialized");
            1
        }
        Err(STATE_INITIALIZING) => {
            // Spin-wait if another thread is initializing
            while AUREXIS_STATE.load(Ordering::SeqCst) == STATE_INITIALIZING {
                std::hint::spin_loop();
            }
            0
        }
        Err(_) => 0, // Already initialized
    }
}

/// Destroy the AUREXIS engine and free resources.
/// Returns 1 on success, 0 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_destroy() -> i32 {
    if AUREXIS_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return 0;
    }
    *ENGINE.write() = None;
    AUREXIS_STATE.store(STATE_UNINITIALIZED, Ordering::SeqCst);
    log::info!("AUREXIS FFI: Engine destroyed");
    1
}

/// Check if the engine is initialized.
/// Returns 1 if initialized, 0 otherwise.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_is_initialized() -> i32 {
    if AUREXIS_STATE.load(Ordering::SeqCst) == STATE_INITIALIZED { 1 } else { 0 }
}

/// Reset session state (fatigue, timing, voices) without clearing config.
/// Returns 1 on success, 0 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_reset_session() -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => {
            engine.reset_session();
            1
        }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE INPUT
// ═══════════════════════════════════════════════════════════════════════════════

/// Set the volatility index (0.0 = low, 1.0 = extreme).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_set_volatility(index: f64) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_volatility(index); 1 }
        None => 0,
    }
}

/// Set the RTP percentage (85.0 - 99.5).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_set_rtp(rtp: f64) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_rtp(rtp); 1 }
        None => 0,
    }
}

/// Set win data: amount, bet, jackpot proximity (0.0-1.0).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_set_win(amount: f64, bet: f64, jackpot_proximity: f64) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_win(amount, bet, jackpot_proximity); 1 }
        None => 0,
    }
}

/// Update audio metering data (RMS and HF energy in dB).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_set_metering(rms_db: f64, hf_db: f64) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_metering(rms_db, hf_db); 1 }
        None => 0,
    }
}

/// Set deterministic variation seed components.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_set_seed(
    sprite_id: u64,
    event_time: u64,
    game_state: u64,
    session_index: u64,
) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.set_seed(sprite_id, event_time, game_state, session_index); 1 }
        None => 0,
    }
}

/// Set active platform type.
/// 0 = Desktop, 1 = Mobile, 2 = Headphones, 3 = Cabinet.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_set_platform(platform_id: i32) -> i32 {
    let platform = match platform_id {
        0 => PlatformType::Desktop,
        1 => PlatformType::Mobile,
        2 => PlatformType::Headphones,
        3 => PlatformType::Cabinet,
        _ => return 0,
    };

    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => {
            engine.config_mut().platform.active_platform = platform;
            1
        }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE COLLISION
// ═══════════════════════════════════════════════════════════════════════════════

/// Register a voice for collision tracking.
/// Returns 1 on success, 0 on failure (capacity exceeded or not initialized).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_register_voice(
    voice_id: u32,
    pan: f32,
    z_depth: f32,
    priority: i32,
) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => {
            if engine.register_voice(voice_id, pan, z_depth, priority) { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Unregister a voice from collision tracking.
/// Returns 1 if removed, 0 if not found or not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_unregister_voice(voice_id: u32) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { if engine.unregister_voice(voice_id) { 1 } else { 0 } }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN EVENTS (ATTENTION VECTOR)
// ═══════════════════════════════════════════════════════════════════════════════

/// Register a screen event for attention vector calculation.
/// Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_register_screen_event(
    event_id: u32,
    x: f32,
    y: f32,
    weight: f32,
    priority: i32,
) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => {
            let event = ScreenEvent { event_id, x, y, weight, priority };
            if engine.register_screen_event(event) { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Clear all screen events.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_clear_screen_events() -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.clear_screen_events(); 1 }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPUTE
// ═══════════════════════════════════════════════════════════════════════════════

/// Main compute call. Called every tick (~50ms).
/// Computes the deterministic parameter map from current state.
/// Returns 1 on success, 0 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_compute(elapsed_ms: u64) -> i32 {
    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => { engine.compute(elapsed_ms); 1 }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUT — INDIVIDUAL PARAMETERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get a single parameter value by name.
/// Returns the value, or -999.0 if parameter not found or engine not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_parameter(name: *const c_char) -> f64 {
    if name.is_null() {
        return -999.0;
    }

    let name_str = unsafe {
        match CStr::from_ptr(name).to_str() {
            Ok(s) => s,
            Err(_) => return -999.0,
        }
    };

    let guard = ENGINE.read();
    match guard.as_ref() {
        Some(engine) => engine.output().get(name_str).unwrap_or(-999.0),
        None => -999.0,
    }
}

/// Get stereo width.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_stereo_width() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(1.0, |e| e.output().stereo_width)
}

/// Get stereo elasticity.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_stereo_elasticity() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(1.0, |e| e.output().stereo_elasticity)
}

/// Get HF attenuation (dB, 0 to negative).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_hf_attenuation_db() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().hf_attenuation_db)
}

/// Get harmonic excitation multiplier.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_harmonic_excitation() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(1.0, |e| e.output().harmonic_excitation)
}

/// Get escalation multiplier.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_escalation_multiplier() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(1.0, |e| e.output().escalation_multiplier)
}

/// Get fatigue index (0.0 = fresh, 1.0 = fatigued).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_fatigue_index() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().fatigue_index)
}

/// Get reverb tail extension (ms).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_reverb_tail_ms() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().reverb_tail_extension_ms)
}

/// Get sub reinforcement (dB).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_sub_reinforcement_db() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().sub_reinforcement_db)
}

/// Get transient sharpness multiplier.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_transient_sharpness() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(1.0, |e| e.output().transient_sharpness)
}

/// Get transient smoothing (0.0 = sharp, 1.0 = smooth).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_transient_smoothing() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().transient_smoothing)
}

/// Get attention vector X (-1.0 left, +1.0 right).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_attention_x() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().attention_x)
}

/// Get attention vector Y (-1.0 bottom, +1.0 top).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_attention_y() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().attention_y)
}

/// Get attention focus weight (0.0 dispersed, 1.0 focused).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_attention_weight() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().attention_weight)
}

/// Get center occupancy (number of voices in center zone).
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_center_occupancy() -> u32 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0, |e| e.output().center_occupancy)
}

/// Get number of redistributed voices.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_voices_redistributed() -> u32 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0, |e| e.output().voices_redistributed)
}

/// Get variation seed.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_variation_seed() -> u64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0, |e| e.output().variation_seed)
}

/// Get session duration in seconds.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_session_duration_s() -> f64 {
    let guard = ENGINE.read();
    guard.as_ref().map_or(0.0, |e| e.output().session_duration_s)
}

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUT — FULL JSON
// ═══════════════════════════════════════════════════════════════════════════════

/// Get the full parameter map as JSON string.
/// Caller MUST free the returned string with aurexis_free_string().
/// Returns null if not initialized or serialization error.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_output_json() -> *mut c_char {
    let guard = ENGINE.read();
    let json = match guard.as_ref() {
        Some(engine) => match engine.output().to_json() {
            Ok(j) => j,
            Err(_) => return ptr::null_mut(),
        },
        None => return ptr::null_mut(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get the engine state as JSON string.
/// Caller MUST free the returned string with aurexis_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_get_state_json() -> *mut c_char {
    let guard = ENGINE.read();
    let json = match guard.as_ref() {
        Some(engine) => {
            let state = engine.state();
            match serde_json::to_string(state) {
                Ok(j) => j,
                Err(_) => return ptr::null_mut(),
            }
        }
        None => return ptr::null_mut(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════════════════════

/// Load configuration from JSON string.
/// Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_load_config_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let config = match AurexisConfig::from_json(json_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("AUREXIS FFI: Failed to parse config JSON: {e}");
            return 0;
        }
    };

    // Update stored config
    *CONFIG.write() = config.clone();

    // If engine is running, update it too
    let mut guard = ENGINE.write();
    if let Some(engine) = guard.as_mut() {
        engine.set_config(config);
    }

    1
}

/// Export current configuration as JSON string.
/// Caller MUST free with aurexis_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_export_config_json() -> *mut c_char {
    let guard = ENGINE.read();
    let json = match guard.as_ref() {
        Some(engine) => match engine.config().to_json() {
            Ok(j) => j,
            Err(_) => return ptr::null_mut(),
        },
        None => {
            match CONFIG.read().to_json() {
                Ok(j) => j,
                Err(_) => return ptr::null_mut(),
            }
        }
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Set a single coefficient by section and key.
/// Returns 1 if coefficient was set, 0 if unknown section/key or not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_set_coefficient(
    section: *const c_char,
    key: *const c_char,
    value: f64,
) -> i32 {
    if section.is_null() || key.is_null() {
        return 0;
    }

    let section_str = unsafe {
        match CStr::from_ptr(section).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let key_str = unsafe {
        match CStr::from_ptr(key).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let mut guard = ENGINE.write();
    match guard.as_mut() {
        Some(engine) => {
            if engine.set_coefficient(section_str, key_str, value) { 1 } else { 0 }
        }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string previously returned by any aurexis_get_*_json() function.
/// Safe to call with null pointer.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BULK UPDATE (JSON-based batch input)
// ═══════════════════════════════════════════════════════════════════════════════

/// Update multiple state values at once via JSON.
///
/// JSON format:
/// ```json
/// {
///     "volatility": 0.7,
///     "rtp": 93.0,
///     "win_amount": 50.0,
///     "bet_amount": 1.0,
///     "jackpot_proximity": 0.3,
///     "rms_db": -18.0,
///     "hf_db": -24.0,
///     "sprite_id": 42,
///     "event_time": 1000,
///     "game_state": 7,
///     "session_index": 0
/// }
/// ```
///
/// All fields are optional. Only provided fields are updated.
/// Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_update_state_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let updates: serde_json::Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("AUREXIS FFI: Failed to parse state update JSON: {e}");
            return 0;
        }
    };

    let mut guard = ENGINE.write();
    let engine = match guard.as_mut() {
        Some(e) => e,
        None => return 0,
    };

    // Apply each field if present
    if let Some(v) = updates.get("volatility").and_then(|v| v.as_f64()) {
        engine.set_volatility(v);
    }
    if let Some(v) = updates.get("rtp").and_then(|v| v.as_f64()) {
        engine.set_rtp(v);
    }

    let win_amount = updates.get("win_amount").and_then(|v| v.as_f64());
    let bet_amount = updates.get("bet_amount").and_then(|v| v.as_f64());
    let jackpot = updates.get("jackpot_proximity").and_then(|v| v.as_f64());
    if win_amount.is_some() || bet_amount.is_some() || jackpot.is_some() {
        let state = engine.state();
        engine.set_win(
            win_amount.unwrap_or(state.win_amount),
            bet_amount.unwrap_or(state.bet_amount),
            jackpot.unwrap_or(state.jackpot_proximity),
        );
    }

    let rms = updates.get("rms_db").and_then(|v| v.as_f64());
    let hf = updates.get("hf_db").and_then(|v| v.as_f64());
    if rms.is_some() || hf.is_some() {
        let state = engine.state();
        engine.set_metering(
            rms.unwrap_or(state.current_rms_db),
            hf.unwrap_or(state.current_hf_db),
        );
    }

    let sprite = updates.get("sprite_id").and_then(|v| v.as_u64());
    let time = updates.get("event_time").and_then(|v| v.as_u64());
    let game = updates.get("game_state").and_then(|v| v.as_u64());
    let session = updates.get("session_index").and_then(|v| v.as_u64());
    if sprite.is_some() || time.is_some() || game.is_some() || session.is_some() {
        let state = engine.state();
        engine.set_seed(
            sprite.unwrap_or(state.seed_sprite_id),
            time.unwrap_or(state.seed_event_time),
            game.unwrap_or(state.seed_game_state),
            session.unwrap_or(state.seed_session_index),
        );
    }

    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPUTE + GET (atomic operation)
// ═══════════════════════════════════════════════════════════════════════════════

/// Compute and return the full parameter map as JSON.
/// This is an atomic compute+serialize operation — avoids race conditions
/// between compute() and get_output_json() calls.
/// Caller MUST free with aurexis_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn aurexis_compute_and_get_json(elapsed_ms: u64) -> *mut c_char {
    let mut guard = ENGINE.write();
    let json = match guard.as_mut() {
        Some(engine) => {
            let map = engine.compute_cloned(elapsed_ms);
            match map.to_json() {
                Ok(j) => j,
                Err(_) => return ptr::null_mut(),
            }
        }
        None => return ptr::null_mut(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Tests must be sequential because they share global state
    use std::sync::Mutex;
    static TEST_MUTEX: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    fn reset_for_test() {
        aurexis_destroy();
    }

    #[test]
    fn test_lifecycle() {
        let _lock = TEST_MUTEX.lock().unwrap();
        reset_for_test();

        assert_eq!(aurexis_is_initialized(), 0);
        assert_eq!(aurexis_init(), 1);
        assert_eq!(aurexis_is_initialized(), 1);
        assert_eq!(aurexis_init(), 0); // Already initialized
        assert_eq!(aurexis_destroy(), 1);
        assert_eq!(aurexis_is_initialized(), 0);
    }

    #[test]
    fn test_compute_returns_json() {
        let _lock = TEST_MUTEX.lock().unwrap();
        reset_for_test();
        aurexis_init();

        aurexis_set_volatility(0.7);
        aurexis_set_rtp(93.0);
        aurexis_set_win(25.0, 1.0, 0.2);

        let json_ptr = aurexis_compute_and_get_json(50);
        assert!(!json_ptr.is_null());

        let json_str = unsafe { CStr::from_ptr(json_ptr).to_str().unwrap() };
        assert!(json_str.contains("stereo_width"));
        assert!(json_str.contains("fatigue_index"));

        aurexis_free_string(json_ptr);
        aurexis_destroy();
    }

    #[test]
    fn test_individual_getters() {
        let _lock = TEST_MUTEX.lock().unwrap();
        reset_for_test();
        aurexis_init();

        aurexis_compute(50);

        let width = aurexis_get_stereo_width();
        assert!(width > 0.0 && width <= 2.0);

        let fatigue = aurexis_get_fatigue_index();
        assert!(fatigue >= 0.0 && fatigue <= 1.0);

        aurexis_destroy();
    }

    #[test]
    fn test_bulk_update() {
        let _lock = TEST_MUTEX.lock().unwrap();
        reset_for_test();
        aurexis_init();

        let json = CString::new(r#"{"volatility": 0.8, "rtp": 91.0, "win_amount": 50.0, "bet_amount": 1.0}"#).unwrap();
        assert_eq!(aurexis_update_state_json(json.as_ptr()), 1);

        aurexis_compute(50);

        // High volatility should give high elasticity
        let elasticity = aurexis_get_stereo_elasticity();
        assert!(elasticity > 1.0, "High volatility should give high elasticity: {elasticity}");

        aurexis_destroy();
    }

    #[test]
    fn test_null_safety() {
        let _lock = TEST_MUTEX.lock().unwrap();
        reset_for_test();

        // All functions should handle null/uninitialized gracefully
        assert_eq!(aurexis_compute(50), 0);
        assert_eq!(aurexis_set_volatility(0.5), 0);
        assert_eq!(aurexis_get_parameter(ptr::null()), -999.0);
        assert!(aurexis_get_output_json().is_null());
        aurexis_free_string(ptr::null_mut()); // Should not crash
    }
}

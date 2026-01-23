//! FFI exports for FluxForge Slot Lab Synthetic Engine
//!
//! Provides C-compatible functions for Flutter dart:ffi to control:
//! - Synthetic slot engine lifecycle
//! - Spin execution and forced outcomes
//! - Volatility and timing configuration
//! - Stage event generation for audio triggering
//!
//! Architecture:
//! - SyntheticSlotEngine lives in global state (single instance)
//! - FFI functions provide safe access to engine methods
//! - Stage events are returned as JSON for easy Dart parsing
//!
//! # Thread Safety
//! Uses OnceLock for race-free initialization. The SLOT_ENGINE is written
//! first, THEN initialized flag is set, ensuring other threads never see
//! a half-initialized state.

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicU64, AtomicU8, Ordering};

use rf_slot_lab::{
    ForcedOutcome, GameModel, SlotEngineV2, SpinResult, SyntheticSlotEngine,
    TimingProfile, VolatilityProfile,
    parser::GddParser,
    scenario::{ScenarioPlayback, ScenarioRegistry},
};
use rf_stage::StageEvent;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialization states (using AtomicU8 for CAS)
const STATE_UNINITIALIZED: u8 = 0;
const STATE_INITIALIZING: u8 = 1;
const STATE_INITIALIZED: u8 = 2;

/// Initialization state (race-free via CAS)
static SLOT_LAB_STATE: AtomicU8 = AtomicU8::new(STATE_UNINITIALIZED);

/// Spin counter
static SPIN_COUNT: AtomicU64 = AtomicU64::new(0);

/// Global slot engine instance
static SLOT_ENGINE: Lazy<RwLock<Option<SyntheticSlotEngine>>> =
    Lazy::new(|| RwLock::new(None));

/// Last spin result (for retrieval by Dart)
static LAST_SPIN_RESULT: Lazy<RwLock<Option<SpinResult>>> =
    Lazy::new(|| RwLock::new(None));

/// Last generated stages (for retrieval by Dart)
static LAST_STAGES: Lazy<RwLock<Vec<StageEvent>>> =
    Lazy::new(|| RwLock::new(Vec::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the Slot Lab engine with default config
///
/// Returns 1 on success, 0 if already initialized, -1 if initialization in progress
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_init() -> i32 {
    // Atomic CAS: UNINITIALIZED -> INITIALIZING (only one thread wins)
    match SLOT_LAB_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            // We won the CAS - do the initialization
            let engine = SyntheticSlotEngine::new();
            *SLOT_ENGINE.write() = Some(engine);

            // Mark as fully initialized (other threads can now proceed)
            SLOT_LAB_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);

            log::info!("slot_lab_init: Synthetic Slot Engine initialized");
            1
        }
        Err(STATE_INITIALIZING) => {
            // Another thread is initializing - spin wait (rare)
            while SLOT_LAB_STATE.load(Ordering::SeqCst) == STATE_INITIALIZING {
                std::hint::spin_loop();
            }
            0 // Already initialized by other thread
        }
        Err(_) => {
            // Already initialized
            log::warn!("slot_lab_init: Already initialized");
            0
        }
    }
}

/// Initialize for audio testing (high frequency events)
///
/// Returns 1 on success, 0 if already initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_init_audio_test() -> i32 {
    // Atomic CAS: UNINITIALIZED -> INITIALIZING
    match SLOT_LAB_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            let engine = SyntheticSlotEngine::audio_test();
            *SLOT_ENGINE.write() = Some(engine);

            // Mark as fully initialized
            SLOT_LAB_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);

            log::info!("slot_lab_init_audio_test: Audio test mode initialized");
            1
        }
        Err(STATE_INITIALIZING) => {
            // Another thread is initializing - spin wait
            while SLOT_LAB_STATE.load(Ordering::SeqCst) == STATE_INITIALIZING {
                std::hint::spin_loop();
            }
            0
        }
        Err(_) => {
            log::warn!("slot_lab_init_audio_test: Already initialized");
            0
        }
    }
}

/// Shutdown the Slot Lab engine
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_shutdown() {
    // Atomic CAS: INITIALIZED -> UNINITIALIZED
    match SLOT_LAB_STATE.compare_exchange(
        STATE_INITIALIZED,
        STATE_UNINITIALIZED,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            *SLOT_ENGINE.write() = None;
            *LAST_SPIN_RESULT.write() = None;
            LAST_STAGES.write().clear();
            SPIN_COUNT.store(0, Ordering::SeqCst);

            log::info!("slot_lab_shutdown: Engine shutdown");
        }
        Err(_) => {
            log::warn!("slot_lab_shutdown: Not initialized or already shutting down");
        }
    }
}

/// Check if engine is initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_is_initialized() -> i32 {
    if SLOT_LAB_STATE.load(Ordering::SeqCst) == STATE_INITIALIZED { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Set volatility by slider value (0.0 = low, 1.0 = high)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_set_volatility_slider(value: f64) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        engine.set_volatility_slider(value.clamp(0.0, 1.0));
    }
}

/// Set volatility preset (0=Low, 1=Medium, 2=High, 3=Studio)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_set_volatility_preset(preset: i32) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        let profile = match preset {
            0 => VolatilityProfile::low(),
            1 => VolatilityProfile::medium(),
            2 => VolatilityProfile::high(),
            3 => VolatilityProfile::studio(),
            _ => VolatilityProfile::medium(),
        };
        engine.set_volatility(profile);
    }
}

/// Set timing profile (0=Normal, 1=Turbo, 2=Mobile, 3=Studio)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_set_timing_profile(profile: i32) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        let timing = match profile {
            0 => TimingProfile::Normal,
            1 => TimingProfile::Turbo,
            2 => TimingProfile::Mobile,
            3 => TimingProfile::Studio,
            _ => TimingProfile::Normal,
        };
        engine.set_timing(timing);
    }
}

/// Set bet amount
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_set_bet(bet: f64) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        engine.set_bet(bet);
    }
}

/// Seed the RNG for reproducible results
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_seed_rng(seed: u64) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        engine.seed(seed);
    }
}

/// Reset session stats
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_reset_stats() {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        engine.reset_stats();
    }
}

/// Enable/disable cascades
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_set_cascades_enabled(enabled: i32) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        let mut features = engine.config().features.clone();
        features.cascades_enabled = enabled != 0;
        engine.set_features(features);
    }
}

/// Enable/disable free spins feature
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_set_free_spins_enabled(enabled: i32) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        let mut features = engine.config().features.clone();
        features.free_spins_enabled = enabled != 0;
        engine.set_features(features);
    }
}

/// Enable/disable jackpot feature
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_set_jackpot_enabled(enabled: i32) {
    let mut guard = SLOT_ENGINE.write();
    if let Some(ref mut engine) = *guard {
        let mut features = engine.config().features.clone();
        features.jackpot_enabled = enabled != 0;
        engine.set_features(features);
    }
}

/// Get current timing config as JSON
/// Returns null if engine not initialized
/// CALLER MUST FREE the returned string using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_timing_config_json() -> *mut c_char {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => {
            let config = engine.timing_config();
            match serde_json::to_string(config) {
                Ok(json) => {
                    match CString::new(json) {
                        Ok(c_str) => c_str.into_raw(),
                        Err(_) => std::ptr::null_mut(),
                    }
                }
                Err(_) => std::ptr::null_mut(),
            }
        }
        None => std::ptr::null_mut(),
    }
}

/// Get audio latency compensation in ms
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_audio_latency_compensation_ms() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.timing_config().audio_latency_compensation_ms,
        None => 5.0, // Default
    }
}

/// Get visual-audio sync offset in ms
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_visual_audio_sync_offset_ms() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.timing_config().visual_audio_sync_offset_ms,
        None => 0.0, // Default
    }
}

/// Get anticipation pre-trigger offset in ms
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_anticipation_pre_trigger_ms() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.timing_config().anticipation_audio_pre_trigger_ms,
        None => 50.0, // Default
    }
}

/// Get reel stop pre-trigger offset in ms
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_reel_stop_pre_trigger_ms() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.timing_config().reel_stop_audio_pre_trigger_ms,
        None => 20.0, // Default
    }
}

/// Get cascade step duration in ms
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_cascade_step_duration_ms() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.timing_config().cascade_step_duration_ms,
        None => 600.0, // Default
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPIN EXECUTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Execute a random spin, returns spin ID
///
/// After calling, use slot_lab_get_spin_result_json() to get the result
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_spin() -> u64 {
    let mut guard = SLOT_ENGINE.write();
    let Some(ref mut engine) = *guard else {
        return 0;
    };

    let (result, stages) = engine.spin_with_stages();

    let spin_id = SPIN_COUNT.fetch_add(1, Ordering::SeqCst) + 1;
    *LAST_SPIN_RESULT.write() = Some(result);
    *LAST_STAGES.write() = stages;

    spin_id
}

/// Minimum valid forced outcome value
pub const FORCED_OUTCOME_MIN: i32 = 0;
/// Maximum valid forced outcome value
pub const FORCED_OUTCOME_MAX: i32 = 13;

/// Check if a forced outcome value is valid
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_is_valid_forced_outcome(outcome: i32) -> i32 {
    if (FORCED_OUTCOME_MIN..=FORCED_OUTCOME_MAX).contains(&outcome) {
        1
    } else {
        0
    }
}

/// Get the name of a forced outcome for debugging
/// Returns a static string, do NOT free this pointer
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_forced_outcome_name(outcome: i32) -> *const c_char {
    static NAMES: [&str; 14] = [
        "Lose\0",
        "SmallWin\0",
        "MediumWin\0",
        "BigWin\0",
        "MegaWin\0",
        "EpicWin\0",
        "UltraWin\0",
        "FreeSpins\0",
        "JackpotMini\0",
        "JackpotMinor\0",
        "JackpotMajor\0",
        "JackpotGrand\0",
        "NearMiss\0",
        "Cascade\0",
    ];

    if (FORCED_OUTCOME_MIN..=FORCED_OUTCOME_MAX).contains(&outcome) {
        NAMES[outcome as usize].as_ptr() as *const c_char
    } else {
        "Invalid\0".as_ptr() as *const c_char
    }
}

/// Execute a forced spin with specific outcome
///
/// outcome values:
///   0 = Lose
///   1 = SmallWin
///   2 = MediumWin
///   3 = BigWin
///   4 = MegaWin
///   5 = EpicWin
///   6 = UltraWin
///   7 = FreeSpins
///   8 = JackpotMini
///   9 = JackpotMinor
///  10 = JackpotMajor
///  11 = JackpotGrand
///  12 = NearMiss
///  13 = Cascade
///
/// Returns:
///   - spin_id (> 0) on success
///   - 0 if engine not initialized or invalid outcome
///
/// VALIDATION: Invalid outcome values (< 0 or > 13) return 0 and log a warning.
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_spin_forced(outcome: i32) -> u64 {
    // Validate outcome range first
    if !(FORCED_OUTCOME_MIN..=FORCED_OUTCOME_MAX).contains(&outcome) {
        log::warn!(
            "slot_lab_spin_forced: Invalid outcome value {} (valid range: {}-{})",
            outcome,
            FORCED_OUTCOME_MIN,
            FORCED_OUTCOME_MAX
        );
        return 0;
    }

    let mut guard = SLOT_ENGINE.write();
    let Some(ref mut engine) = *guard else {
        log::warn!("slot_lab_spin_forced: Engine not initialized");
        return 0;
    };

    let forced = match outcome {
        0 => ForcedOutcome::Lose,
        1 => ForcedOutcome::SmallWin,
        2 => ForcedOutcome::MediumWin,
        3 => ForcedOutcome::BigWin,
        4 => ForcedOutcome::MegaWin,
        5 => ForcedOutcome::EpicWin,
        6 => ForcedOutcome::UltraWin,
        7 => ForcedOutcome::FreeSpins,
        8 => ForcedOutcome::JackpotMini,
        9 => ForcedOutcome::JackpotMinor,
        10 => ForcedOutcome::JackpotMajor,
        11 => ForcedOutcome::JackpotGrand,
        12 => ForcedOutcome::NearMiss,
        13 => ForcedOutcome::Cascade,
        // This should never be reached due to validation above
        _ => {
            log::error!("slot_lab_spin_forced: Unexpected outcome after validation: {}", outcome);
            return 0;
        }
    };

    let (result, stages) = engine.spin_forced_with_stages(forced);

    let spin_id = SPIN_COUNT.fetch_add(1, Ordering::SeqCst) + 1;
    *LAST_SPIN_RESULT.write() = Some(result);
    *LAST_STAGES.write() = stages;

    log::debug!("slot_lab_spin_forced: outcome={:?}, spin_id={}", forced, spin_id);
    spin_id
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESULT RETRIEVAL
// ═══════════════════════════════════════════════════════════════════════════════

/// Get last spin result as JSON string
///
/// Returns a heap-allocated string that must be freed with slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_spin_result_json() -> *mut c_char {
    let guard = LAST_SPIN_RESULT.read();
    let json = match &*guard {
        Some(result) => serde_json::to_string(result).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get last generated stages as JSON array
///
/// Returns a heap-allocated string that must be freed with slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_stages_json() -> *mut c_char {
    let guard = LAST_STAGES.read();
    let json = serde_json::to_string(&*guard).unwrap_or_else(|_| "[]".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get stage count from last spin
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_stage_count() -> i32 {
    LAST_STAGES.read().len() as i32
}

/// Free a string returned by the slot lab FFI
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATS AND STATE QUERIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get session stats as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_stats_json() -> *mut c_char {
    let guard = SLOT_ENGINE.read();
    let json = match &*guard {
        Some(engine) => {
            serde_json::to_string(engine.stats()).unwrap_or_else(|_| "{}".to_string())
        }
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get current RTP (return-to-player percentage)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_rtp() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.stats().rtp(),
        None => 0.0,
    }
}

/// Get current hit rate percentage
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_hit_rate() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.stats().hit_rate(),
        None => 0.0,
    }
}

/// Get total spins in session
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_total_spins() -> u64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.stats().total_spins,
        None => 0,
    }
}

/// Get total wins in session
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_total_wins() -> u64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.stats().wins,
        None => 0,
    }
}

/// Get total big wins
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_big_wins() -> u64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.stats().big_wins,
        None => 0,
    }
}

/// Get features triggered count
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_features_triggered() -> u64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.stats().features_triggered,
        None => 0,
    }
}

/// Get max win ratio achieved
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_max_win_ratio() -> f64 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.stats().max_win_ratio,
        None => 0.0,
    }
}

/// Check if currently in free spins
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_in_free_spins() -> i32 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => if engine.in_free_spins() { 1 } else { 0 },
        None => 0,
    }
}

/// Get remaining free spins
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_remaining() -> u32 {
    let guard = SLOT_ENGINE.read();
    match &*guard {
        Some(engine) => engine.free_spins_remaining(),
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG EXPORT/IMPORT
// ═══════════════════════════════════════════════════════════════════════════════

/// Export current config as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_export_config() -> *mut c_char {
    let guard = SLOT_ENGINE.read();
    let json = match &*guard {
        Some(engine) => engine.export_config(),
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Import config from JSON
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_import_config(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let mut guard = SLOT_ENGINE.write();
    match &mut *guard {
        Some(engine) => {
            if engine.import_config(json_str).is_ok() { 1 } else { 0 }
        }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAST SPIN QUICK ACCESS (without JSON parsing)
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if last spin was a win
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_is_win() -> i32 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => if result.is_win() { 1 } else { 0 },
        None => 0,
    }
}

/// Get last spin total win amount
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_win_amount() -> f64 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => result.total_win,
        None => 0.0,
    }
}

/// Get last spin win ratio
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_win_ratio() -> f64 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => result.win_ratio,
        None => 0.0,
    }
}

/// Get last spin bet amount
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_bet() -> f64 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => result.bet,
        None => 0.0,
    }
}

/// Get last spin line win count
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_line_count() -> i32 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => result.line_wins.len() as i32,
        None => 0,
    }
}

/// Check if last spin triggered a feature
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_triggered_feature() -> i32 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => if result.feature_triggered.is_some() { 1 } else { 0 },
        None => 0,
    }
}

/// Check if last spin was a near miss
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_near_miss() -> i32 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => if result.near_miss { 1 } else { 0 },
        None => 0,
    }
}

/// Get last spin big win tier (0=None, 1=Win, 2=BigWin, 3=MegaWin, 4=EpicWin, 5=UltraWin)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_big_win_tier() -> i32 {
    use rf_stage::BigWinTier;

    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => match &result.big_win_tier {
            None => 0,
            Some(BigWinTier::Win) => 1,
            Some(BigWinTier::BigWin) => 2,
            Some(BigWinTier::MegaWin) => 3,
            Some(BigWinTier::EpicWin) => 4,
            Some(BigWinTier::UltraWin) => 5,
            Some(BigWinTier::Custom(_)) => 1,
        },
        None => 0,
    }
}

/// Get cascade count from last spin
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_last_spin_cascade_count() -> i32 {
    let guard = LAST_SPIN_RESULT.read();
    match &*guard {
        Some(result) => result.cascades.len() as i32,
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENGINE V2 — GameModel-driven engine
// ═══════════════════════════════════════════════════════════════════════════════

/// Engine V2 initialization state
static ENGINE_V2_STATE: AtomicU8 = AtomicU8::new(STATE_UNINITIALIZED);

/// Global Engine V2 instance
static ENGINE_V2: Lazy<RwLock<Option<SlotEngineV2>>> = Lazy::new(|| RwLock::new(None));

/// Last Engine V2 spin result
static LAST_V2_RESULT: Lazy<RwLock<Option<SpinResult>>> = Lazy::new(|| RwLock::new(None));

/// Last Engine V2 stages
static LAST_V2_STAGES: Lazy<RwLock<Vec<StageEvent>>> = Lazy::new(|| RwLock::new(Vec::new()));

/// Initialize Engine V2 with default 5x3 game model
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_init() -> i32 {
    match ENGINE_V2_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            let engine = SlotEngineV2::new();
            *ENGINE_V2.write() = Some(engine);
            ENGINE_V2_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);
            log::info!("slot_lab_v2_init: Engine V2 initialized with default model");
            1
        }
        Err(STATE_INITIALIZING) => {
            while ENGINE_V2_STATE.load(Ordering::SeqCst) == STATE_INITIALIZING {
                std::hint::spin_loop();
            }
            0
        }
        Err(_) => {
            log::warn!("slot_lab_v2_init: Already initialized");
            0
        }
    }
}

/// Initialize Engine V2 with a GameModel from JSON
///
/// Returns 1 on success, 0 on failure or already initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_init_with_model_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match ENGINE_V2_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            // Parse the JSON as GameModel
            match serde_json::from_str::<GameModel>(json_str) {
                Ok(model) => {
                    let engine = SlotEngineV2::from_model(model);
                    *ENGINE_V2.write() = Some(engine);
                    ENGINE_V2_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);
                    log::info!("slot_lab_v2_init_with_model_json: Engine V2 initialized with custom model");
                    1
                }
                Err(e) => {
                    log::error!("slot_lab_v2_init_with_model_json: Failed to parse model: {}", e);
                    ENGINE_V2_STATE.store(STATE_UNINITIALIZED, Ordering::SeqCst);
                    0
                }
            }
        }
        Err(_) => 0,
    }
}

/// Initialize Engine V2 from a GDD (Game Design Document) JSON
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_init_from_gdd(gdd_json: *const c_char) -> i32 {
    if gdd_json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(gdd_json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match ENGINE_V2_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            // Parse GDD and convert to GameModel
            let parser = GddParser::new();
            match parser.parse_json(json_str) {
                Ok(model) => {
                    let engine = SlotEngineV2::from_model(model);
                    *ENGINE_V2.write() = Some(engine);
                    ENGINE_V2_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);
                    log::info!("slot_lab_v2_init_from_gdd: Engine V2 initialized from GDD");
                    1
                }
                Err(e) => {
                    log::error!("slot_lab_v2_init_from_gdd: Failed to parse GDD: {:?}", e);
                    ENGINE_V2_STATE.store(STATE_UNINITIALIZED, Ordering::SeqCst);
                    0
                }
            }
        }
        Err(_) => 0,
    }
}

/// Shutdown Engine V2
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_shutdown() {
    match ENGINE_V2_STATE.compare_exchange(
        STATE_INITIALIZED,
        STATE_UNINITIALIZED,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            *ENGINE_V2.write() = None;
            *LAST_V2_RESULT.write() = None;
            LAST_V2_STAGES.write().clear();
            log::info!("slot_lab_v2_shutdown: Engine V2 shutdown");
        }
        Err(_) => {
            log::warn!("slot_lab_v2_shutdown: Not initialized");
        }
    }
}

/// Check if Engine V2 is initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_is_initialized() -> i32 {
    if ENGINE_V2_STATE.load(Ordering::SeqCst) == STATE_INITIALIZED {
        1
    } else {
        0
    }
}

/// Execute a spin with Engine V2
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_spin() -> u64 {
    let mut guard = ENGINE_V2.write();
    let Some(ref mut engine) = *guard else {
        return 0;
    };

    let (result, stages) = engine.spin_with_stages();
    let spin_id = SPIN_COUNT.fetch_add(1, Ordering::SeqCst) + 1;
    *LAST_V2_RESULT.write() = Some(result);
    *LAST_V2_STAGES.write() = stages;

    spin_id
}

/// Execute a forced spin with Engine V2
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_spin_forced(outcome: i32) -> u64 {
    if !(FORCED_OUTCOME_MIN..=FORCED_OUTCOME_MAX).contains(&outcome) {
        return 0;
    }

    let mut guard = ENGINE_V2.write();
    let Some(ref mut engine) = *guard else {
        return 0;
    };

    let forced = match outcome {
        0 => ForcedOutcome::Lose,
        1 => ForcedOutcome::SmallWin,
        2 => ForcedOutcome::MediumWin,
        3 => ForcedOutcome::BigWin,
        4 => ForcedOutcome::MegaWin,
        5 => ForcedOutcome::EpicWin,
        6 => ForcedOutcome::UltraWin,
        7 => ForcedOutcome::FreeSpins,
        8 => ForcedOutcome::JackpotMini,
        9 => ForcedOutcome::JackpotMinor,
        10 => ForcedOutcome::JackpotMajor,
        11 => ForcedOutcome::JackpotGrand,
        12 => ForcedOutcome::NearMiss,
        13 => ForcedOutcome::Cascade,
        _ => return 0,
    };

    let (result, stages) = engine.spin_forced_with_stages(forced);
    let spin_id = SPIN_COUNT.fetch_add(1, Ordering::SeqCst) + 1;
    *LAST_V2_RESULT.write() = Some(result);
    *LAST_V2_STAGES.write() = stages;

    spin_id
}

/// Get Engine V2 spin result as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_get_spin_result_json() -> *mut c_char {
    let guard = LAST_V2_RESULT.read();
    let json = match &*guard {
        Some(result) => serde_json::to_string(result).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get Engine V2 stages as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_get_stages_json() -> *mut c_char {
    let guard = LAST_V2_STAGES.read();
    let json = serde_json::to_string(&*guard).unwrap_or_else(|_| "[]".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get Engine V2 game model as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_get_model_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    let json = match &*guard {
        Some(engine) => {
            serde_json::to_string(engine.model()).unwrap_or_else(|_| "{}".to_string())
        }
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get Engine V2 stats as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_get_stats_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    let json = match &*guard {
        Some(engine) => {
            serde_json::to_string(engine.stats()).unwrap_or_else(|_| "{}".to_string())
        }
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Set Engine V2 game mode (0 = GddOnly, 1 = MathDriven)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_set_mode(mode: i32) {
    let mut guard = ENGINE_V2.write();
    if let Some(ref mut engine) = *guard {
        let game_mode = match mode {
            0 => rf_slot_lab::model::GameMode::GddOnly,
            1 => rf_slot_lab::model::GameMode::MathDriven,
            _ => rf_slot_lab::model::GameMode::GddOnly,
        };
        engine.set_mode(game_mode);
    }
}

/// Set Engine V2 bet amount
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_set_bet(bet: f64) {
    let mut guard = ENGINE_V2.write();
    if let Some(ref mut engine) = *guard {
        engine.set_bet(bet);
    }
}

/// Seed Engine V2 RNG
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_seed(seed: u64) {
    let mut guard = ENGINE_V2.write();
    if let Some(ref mut engine) = *guard {
        engine.seed(seed);
    }
}

/// Reset Engine V2 stats
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_reset_stats() {
    let mut guard = ENGINE_V2.write();
    if let Some(ref mut engine) = *guard {
        engine.reset_stats();
    }
}

/// Get win tier name from last V2 spin
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_v2_last_win_tier() -> *mut c_char {
    let guard = LAST_V2_RESULT.read();
    let name = match &*guard {
        Some(result) => result.win_tier_name.clone().unwrap_or_default(),
        None => String::new(),
    };

    match CString::new(name) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCENARIO SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Global scenario registry
static SCENARIO_REGISTRY: Lazy<RwLock<ScenarioRegistry>> =
    Lazy::new(|| RwLock::new(ScenarioRegistry::new()));

/// Active playback state
static ACTIVE_PLAYBACK: Lazy<RwLock<Option<ScenarioPlayback>>> =
    Lazy::new(|| RwLock::new(None));

/// List all available scenarios as JSON array
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_list_json() -> *mut c_char {
    let registry = SCENARIO_REGISTRY.read();
    let info = registry.list_with_info();
    let json = serde_json::to_string(&info).unwrap_or_else(|_| "[]".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Load a scenario by ID for playback
///
/// Returns 1 on success, 0 if scenario not found
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_load(id: *const c_char) -> i32 {
    if id.is_null() {
        return 0;
    }

    let id_str = unsafe {
        match CStr::from_ptr(id).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let registry = SCENARIO_REGISTRY.read();
    match registry.create_playback(id_str) {
        Some(playback) => {
            *ACTIVE_PLAYBACK.write() = Some(playback);
            log::info!("slot_lab_scenario_load: Loaded scenario '{}'", id_str);
            1
        }
        None => {
            log::warn!("slot_lab_scenario_load: Scenario '{}' not found", id_str);
            0
        }
    }
}

/// Check if a scenario is currently loaded
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_is_loaded() -> i32 {
    if ACTIVE_PLAYBACK.read().is_some() { 1 } else { 0 }
}

/// Get the next spin from the loaded scenario
///
/// Returns the scripted spin as JSON, or empty object if no more spins
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_next_spin_json() -> *mut c_char {
    let mut playback = ACTIVE_PLAYBACK.write();
    let json = match &mut *playback {
        Some(pb) => match pb.next() {
            Some(spin) => serde_json::to_string(spin).unwrap_or_else(|_| "{}".to_string()),
            None => "{}".to_string(),
        },
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get current playback progress (current_index, total_spins)
///
/// Returns as "current,total" string
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_progress() -> *mut c_char {
    let playback = ACTIVE_PLAYBACK.read();
    let progress_str = match &*playback {
        Some(pb) => {
            let (current, total) = pb.progress();
            format!("{},{}", current, total)
        }
        None => "0,0".to_string(),
    };

    match CString::new(progress_str) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Check if scenario playback is complete
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_is_complete() -> i32 {
    let playback = ACTIVE_PLAYBACK.read();
    match &*playback {
        Some(pb) => if pb.is_complete() { 1 } else { 0 },
        None => 1, // No playback = complete
    }
}

/// Reset scenario playback to beginning
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_reset() {
    let mut playback = ACTIVE_PLAYBACK.write();
    if let Some(pb) = &mut *playback {
        pb.reset();
    }
}

/// Unload the current scenario
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_unload() {
    *ACTIVE_PLAYBACK.write() = None;
}

/// Register a custom scenario from JSON
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_register_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match serde_json::from_str::<rf_slot_lab::DemoScenario>(json_str) {
        Ok(scenario) => {
            let mut registry = SCENARIO_REGISTRY.write();
            log::info!("slot_lab_scenario_register_json: Registered scenario '{}'", scenario.id);
            registry.register(scenario);
            1
        }
        Err(e) => {
            log::error!("slot_lab_scenario_register_json: Failed to parse: {}", e);
            0
        }
    }
}

/// Get a scenario by ID as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_scenario_get_json(id: *const c_char) -> *mut c_char {
    if id.is_null() {
        return ptr::null_mut();
    }

    let id_str = unsafe {
        match CStr::from_ptr(id).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        }
    };

    let registry = SCENARIO_REGISTRY.read();
    let json = match registry.get(id_str) {
        Some(scenario) => serde_json::to_string(scenario).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GDD PARSER — Parse Game Design Documents
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse a GDD JSON and validate it
///
/// Returns validation result as JSON with errors array
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gdd_validate(gdd_json: *const c_char) -> *mut c_char {
    if gdd_json.is_null() {
        let error_json = r#"{"valid":false,"errors":["Null input"]}"#;
        return CString::new(error_json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut());
    }

    let json_str = unsafe {
        match CStr::from_ptr(gdd_json).to_str() {
            Ok(s) => s,
            Err(_) => {
                let error_json = r#"{"valid":false,"errors":["Invalid UTF-8"]}"#;
                return CString::new(error_json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut());
            }
        }
    };

    let parser = GddParser::new();
    match parser.parse_json(json_str) {
        Ok(_model) => {
            // Successfully parsed and validated
            let result = serde_json::json!({
                "valid": true,
                "errors": serde_json::Value::Array(vec![]),
            });
            let json = serde_json::to_string(&result).unwrap_or_else(|_| r#"{"valid":true}"#.to_string());
            CString::new(json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut())
        }
        Err(e) => {
            let result = serde_json::json!({
                "valid": false,
                "errors": [format!("Parse error: {:?}", e)],
            });
            let json = serde_json::to_string(&result).unwrap_or_else(|_| r#"{"valid":false}"#.to_string());
            CString::new(json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut())
        }
    }
}

/// Convert a GDD JSON to a GameModel JSON
///
/// Returns the GameModel as JSON, or error JSON on failure
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gdd_to_model(gdd_json: *const c_char) -> *mut c_char {
    if gdd_json.is_null() {
        let error_json = r#"{"error":"Null input"}"#;
        return CString::new(error_json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut());
    }

    let json_str = unsafe {
        match CStr::from_ptr(gdd_json).to_str() {
            Ok(s) => s,
            Err(_) => {
                let error_json = r#"{"error":"Invalid UTF-8"}"#;
                return CString::new(error_json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut());
            }
        }
    };

    let parser = GddParser::new();
    match parser.parse_json(json_str) {
        Ok(model) => {
            let json = serde_json::to_string(&model).unwrap_or_else(|_| "{}".to_string());
            CString::new(json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut())
        }
        Err(e) => {
            let error_json = format!(r#"{{"error":"Parse error: {:?}"}}"#, e);
            CString::new(error_json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut())
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HOLD & WIN — Feature State Access
// ═══════════════════════════════════════════════════════════════════════════════

/// Hold & Win state for FFI export
#[derive(serde::Serialize)]
struct HoldAndWinStateJson {
    is_active: bool,
    remaining_respins: u8,
    total_respins: u8,
    locked_count: usize,
    grid_size: u8,
    fill_percentage: f64,
    total_value: f64,
    locked_symbols: Vec<LockedSymbolJson>,
}

#[derive(serde::Serialize)]
struct LockedSymbolJson {
    position: u8,
    value: f64,
    symbol_type: String,
}

/// Check if Hold & Win feature is currently active
///
/// Returns 1 if active, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_is_active() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if engine.is_hold_and_win_active() { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Get remaining respins in Hold & Win feature
///
/// Returns remaining respins count, or 0 if not active
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_remaining_respins() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.hold_and_win_remaining_respins() as i32,
        None => 0,
    }
}

/// Get fill percentage of Hold & Win grid (0.0 - 1.0)
///
/// Returns fill percentage, or 0.0 if not active
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_fill_percentage() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.hold_and_win_fill_percentage(),
        None => 0.0,
    }
}

/// Get number of locked symbols in Hold & Win grid
///
/// Returns locked symbol count, or 0 if not active
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_locked_count() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.hold_and_win_locked_count() as i32,
        None => 0,
    }
}

/// Get complete Hold & Win state as JSON
///
/// Returns JSON with: is_active, remaining_respins, locked_count, fill_percentage,
/// total_value, locked_symbols array (position, value, symbol_type)
///
/// CALLER MUST FREE the returned string using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_get_state_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    let json = match &*guard {
        Some(engine) => {
            let state = engine.hold_and_win_state();
            match state {
                Some(snapshot) => {
                    let state_json = HoldAndWinStateJson {
                        is_active: snapshot.is_active,
                        remaining_respins: snapshot.data.get("remaining_respins")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0) as u8,
                        total_respins: snapshot.current_step as u8,
                        locked_count: snapshot.data.get("locked_count")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0) as usize,
                        grid_size: 15, // Default grid size
                        fill_percentage: engine.hold_and_win_fill_percentage(),
                        total_value: snapshot.accumulated_win,
                        locked_symbols: engine.hold_and_win_locked_symbols()
                            .iter()
                            .map(|sym| LockedSymbolJson {
                                position: sym.position,
                                value: sym.value,
                                symbol_type: format!("{:?}", sym.symbol_type),
                            })
                            .collect(),
                    };
                    serde_json::to_string(&state_json).unwrap_or_else(|_| "{}".to_string())
                }
                None => {
                    // Not active, return empty state
                    let empty = HoldAndWinStateJson {
                        is_active: false,
                        remaining_respins: 0,
                        total_respins: 0,
                        locked_count: 0,
                        grid_size: 15,
                        fill_percentage: 0.0,
                        total_value: 0.0,
                        locked_symbols: Vec::new(),
                    };
                    serde_json::to_string(&empty).unwrap_or_else(|_| "{}".to_string())
                }
            }
        }
        None => "{}".to_string(),
    };

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get total accumulated value in current Hold & Win session
///
/// Returns accumulated value, or 0.0 if not active
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_total_value() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.hold_and_win_total_value(),
        None => 0.0,
    }
}

/// Force trigger Hold & Win feature (for testing/demo)
///
/// Returns 1 on success, 0 if engine not initialized or feature already active
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_force_trigger() -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => {
            if engine.force_trigger_hold_and_win() { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Add a locked symbol to Hold & Win grid (for testing/demo)
///
/// position: 0-14 (for 5x3 grid)
/// value: coin value
/// symbol_type: 0=Normal, 1=Mini, 2=Minor, 3=Major, 4=Grand
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_add_locked_symbol(
    position: u8,
    value: f64,
    symbol_type: i32,
) -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => {
            let sym_type = match symbol_type {
                0 => rf_slot_lab::features::HoldSymbolType::Normal,
                1 => rf_slot_lab::features::HoldSymbolType::Mini,
                2 => rf_slot_lab::features::HoldSymbolType::Minor,
                3 => rf_slot_lab::features::HoldSymbolType::Major,
                4 => rf_slot_lab::features::HoldSymbolType::Grand,
                _ => rf_slot_lab::features::HoldSymbolType::Normal,
            };
            if engine.hold_and_win_add_locked_symbol(position, value, sym_type) {
                1
            } else {
                0
            }
        }
        None => 0,
    }
}

/// Complete Hold & Win feature and get final payout
///
/// Returns final payout value, or 0.0 if not active
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_hold_and_win_complete() -> f64 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => engine.hold_and_win_complete(),
        None => 0.0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PICK BONUS FEATURE FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if Pick Bonus is active
/// Returns 1 if active, 0 if not
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_is_active() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if engine.is_pick_bonus_active() { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Get picks made so far
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_picks_made() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.pick_bonus_picks_made() as i32,
        None => 0,
    }
}

/// Get total items in pick bonus
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_total_items() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.pick_bonus_total_items() as i32,
        None => 0,
    }
}

/// Get current multiplier
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_multiplier() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.pick_bonus_multiplier(),
        None => 1.0,
    }
}

/// Get total win accumulated
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_total_win() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.pick_bonus_total_win(),
        None => 0.0,
    }
}

/// Force trigger Pick Bonus (for testing)
/// Returns 1 if triggered, 0 if failed
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_force_trigger() -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => {
            if engine.force_trigger_pick_bonus() { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Make a pick in Pick Bonus
/// Returns JSON string with prize info or null if not active
/// JSON: {"prize_type": "coins", "prize_value": 100.0, "game_over": false}
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_make_pick() -> *mut c_char {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => {
            if let Some((prize_type, prize_value, game_over)) = engine.pick_bonus_make_pick() {
                let json = serde_json::json!({
                    "prize_type": prize_type,
                    "prize_value": prize_value,
                    "game_over": game_over,
                });
                let json_str = serde_json::to_string(&json).unwrap_or_default();
                CString::new(json_str).unwrap().into_raw()
            } else {
                std::ptr::null_mut()
            }
        }
        None => std::ptr::null_mut(),
    }
}

/// Get Pick Bonus state as JSON
/// Returns JSON string or null
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_get_state_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if let Some(json_str) = engine.pick_bonus_get_state_json() {
                CString::new(json_str).unwrap().into_raw()
            } else {
                std::ptr::null_mut()
            }
        }
        None => std::ptr::null_mut(),
    }
}

/// Complete Pick Bonus and return final payout
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_pick_bonus_complete() -> f64 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => engine.pick_bonus_complete(),
        None => 0.0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GAMBLE FEATURE FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if Gamble is active
/// Returns 1 if active, 0 if not
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gamble_is_active() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if engine.is_gamble_active() { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Get current stake in gamble
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gamble_current_stake() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.gamble_current_stake(),
        None => 0.0,
    }
}

/// Get attempts used in gamble
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gamble_attempts_used() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.gamble_attempts_used() as i32,
        None => 0,
    }
}

/// Force trigger Gamble with initial stake
/// Returns 1 if triggered, 0 if failed
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gamble_force_trigger(initial_stake: f64) -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => {
            if engine.force_trigger_gamble(initial_stake) { 1 } else { 0 }
        }
        None => 0,
    }
}

/// Make a gamble choice
/// choice_index: 0=first option, 1=second option, etc.
/// Returns JSON: {"won": true, "new_stake": 200.0, "game_over": false}
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gamble_make_choice(choice_index: i32) -> *mut c_char {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => {
            if let Some((won, new_stake, game_over)) = engine.gamble_make_choice(choice_index as u8) {
                let json = serde_json::json!({
                    "won": won,
                    "new_stake": new_stake,
                    "game_over": game_over,
                });
                let json_str = serde_json::to_string(&json).unwrap_or_default();
                CString::new(json_str).unwrap().into_raw()
            } else {
                std::ptr::null_mut()
            }
        }
        None => std::ptr::null_mut(),
    }
}

/// Collect gamble winnings and end
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gamble_collect() -> f64 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => engine.gamble_collect(),
        None => 0.0,
    }
}

/// Get Gamble state as JSON
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_gamble_get_state_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if let Some(json_str) = engine.gamble_get_state_json() {
                CString::new(json_str).unwrap().into_raw()
            } else {
                std::ptr::null_mut()
            }
        }
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // Ensure tests run serially since they share global state
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn test_slot_lab_lifecycle() {
        let _guard = TEST_LOCK.lock().unwrap();

        // Ensure clean state
        slot_lab_shutdown();

        // Init
        assert_eq!(slot_lab_init(), 1);
        assert_eq!(slot_lab_is_initialized(), 1);

        // Double init should fail
        assert_eq!(slot_lab_init(), 0);

        // Spin
        let spin_id = slot_lab_spin();
        assert!(spin_id > 0);

        // Shutdown
        slot_lab_shutdown();
        assert_eq!(slot_lab_is_initialized(), 0);
    }

    #[test]
    fn test_forced_outcomes() {
        let _guard = TEST_LOCK.lock().unwrap();

        // Ensure clean state
        slot_lab_shutdown();
        slot_lab_init();

        // Force a win
        slot_lab_spin_forced(3); // BigWin
        assert_eq!(slot_lab_last_spin_is_win(), 1);

        // Force a loss
        slot_lab_spin_forced(0); // Lose
        assert_eq!(slot_lab_last_spin_is_win(), 0);

        slot_lab_shutdown();
    }
}

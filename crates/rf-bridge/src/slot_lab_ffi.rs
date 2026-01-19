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

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use rf_slot_lab::{
    ForcedOutcome, SpinResult, SyntheticSlotEngine, TimingProfile, VolatilityProfile,
};
use rf_stage::StageEvent;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialization flag
static SLOT_LAB_INITIALIZED: AtomicBool = AtomicBool::new(false);

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
/// Returns 1 on success, 0 if already initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_init() -> i32 {
    if SLOT_LAB_INITIALIZED.swap(true, Ordering::SeqCst) {
        log::warn!("slot_lab_init: Already initialized");
        return 0;
    }

    let engine = SyntheticSlotEngine::new();
    *SLOT_ENGINE.write() = Some(engine);

    log::info!("slot_lab_init: Synthetic Slot Engine initialized");
    1
}

/// Initialize for audio testing (high frequency events)
///
/// Returns 1 on success, 0 if already initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_init_audio_test() -> i32 {
    if SLOT_LAB_INITIALIZED.swap(true, Ordering::SeqCst) {
        log::warn!("slot_lab_init_audio_test: Already initialized");
        return 0;
    }

    let engine = SyntheticSlotEngine::audio_test();
    *SLOT_ENGINE.write() = Some(engine);

    log::info!("slot_lab_init_audio_test: Audio test mode initialized");
    1
}

/// Shutdown the Slot Lab engine
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_shutdown() {
    if !SLOT_LAB_INITIALIZED.swap(false, Ordering::SeqCst) {
        log::warn!("slot_lab_shutdown: Not initialized");
        return;
    }

    *SLOT_ENGINE.write() = None;
    *LAST_SPIN_RESULT.write() = None;
    LAST_STAGES.write().clear();
    SPIN_COUNT.store(0, Ordering::SeqCst);

    log::info!("slot_lab_shutdown: Engine shutdown");
}

/// Check if engine is initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_is_initialized() -> i32 {
    if SLOT_LAB_INITIALIZED.load(Ordering::SeqCst) { 1 } else { 0 }
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

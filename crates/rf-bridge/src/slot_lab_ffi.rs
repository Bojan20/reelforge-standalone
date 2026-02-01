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
// P5 WIN TIER SPIN FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Execute a spin with P5 Win Tier evaluation
///
/// This uses the dynamic P5 SlotWinConfig to evaluate win tiers instead of
/// the legacy hardcoded thresholds. The spin result includes:
/// - win_tier_name: P5 stage name (e.g., "WIN_3", "BIG_WIN_INTRO")
/// - big_win_tier: Legacy enum for backwards compatibility
///
/// Returns spin ID (> 0) on success, 0 if engine not initialized
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_spin_p5() -> u64 {
    let mut guard = SLOT_ENGINE.write();
    let Some(ref mut engine) = *guard else {
        log::warn!("slot_lab_spin_p5: Engine not initialized");
        return 0;
    };

    // Execute spin (uses legacy win tier internally)
    let (mut result, mut stages) = engine.spin_with_stages();

    // Reevaluate with P5 Win Tier config
    let win_config = WIN_TIER_CONFIG.read();
    let p5_result = win_config.evaluate(result.total_win, result.bet);

    // Update SpinResult with P5 tier info
    result.win_tier_name = if p5_result.primary_stage.is_empty() || p5_result.primary_stage == "NO_WIN" {
        None
    } else {
        Some(p5_result.primary_stage.clone())
    };

    // Map P5 result to legacy BigWinTier for backwards compatibility
    if p5_result.is_big_win {
        result.big_win_tier = match p5_result.big_win_max_tier {
            Some(5) => Some(rf_stage::BigWinTier::UltraWin),
            Some(4) => Some(rf_stage::BigWinTier::EpicWin),
            Some(3) => Some(rf_stage::BigWinTier::MegaWin),
            Some(2) => Some(rf_stage::BigWinTier::BigWin),
            Some(1) => Some(rf_stage::BigWinTier::BigWin),
            _ => Some(rf_stage::BigWinTier::BigWin),
        };
    } else if result.total_win > 0.0 {
        result.big_win_tier = Some(rf_stage::BigWinTier::Win);
    }

    drop(win_config); // Release read lock before storing

    let spin_id = SPIN_COUNT.fetch_add(1, Ordering::SeqCst) + 1;
    *LAST_SPIN_RESULT.write() = Some(result);
    *LAST_STAGES.write() = stages;

    log::debug!("slot_lab_spin_p5: spin_id={}", spin_id);
    spin_id
}

/// Execute a forced spin with P5 Win Tier evaluation
///
/// Combines forced outcome with P5 dynamic win tier evaluation.
/// Returns spin ID (> 0) on success, 0 if engine not initialized or invalid outcome
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_spin_forced_p5(outcome: i32) -> u64 {
    // Validate outcome range first
    if !(FORCED_OUTCOME_MIN..=FORCED_OUTCOME_MAX).contains(&outcome) {
        log::warn!(
            "slot_lab_spin_forced_p5: Invalid outcome value {} (valid range: {}-{})",
            outcome,
            FORCED_OUTCOME_MIN,
            FORCED_OUTCOME_MAX
        );
        return 0;
    }

    let mut guard = SLOT_ENGINE.write();
    let Some(ref mut engine) = *guard else {
        log::warn!("slot_lab_spin_forced_p5: Engine not initialized");
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
        _ => {
            log::error!("slot_lab_spin_forced_p5: Unexpected outcome after validation: {}", outcome);
            return 0;
        }
    };

    // Execute spin (uses legacy win tier internally)
    let (mut result, mut stages) = engine.spin_forced_with_stages(forced);

    // Reevaluate with P5 Win Tier config
    let win_config = WIN_TIER_CONFIG.read();
    let p5_result = win_config.evaluate(result.total_win, result.bet);

    // Update SpinResult with P5 tier info
    result.win_tier_name = if p5_result.primary_stage.is_empty() || p5_result.primary_stage == "NO_WIN" {
        None
    } else {
        Some(p5_result.primary_stage.clone())
    };

    // Map P5 result to legacy BigWinTier for backwards compatibility
    if p5_result.is_big_win {
        result.big_win_tier = match p5_result.big_win_max_tier {
            Some(5) => Some(rf_stage::BigWinTier::UltraWin),
            Some(4) => Some(rf_stage::BigWinTier::EpicWin),
            Some(3) => Some(rf_stage::BigWinTier::MegaWin),
            Some(2) => Some(rf_stage::BigWinTier::BigWin),
            Some(1) => Some(rf_stage::BigWinTier::BigWin),
            _ => Some(rf_stage::BigWinTier::BigWin),
        };
    } else if result.total_win > 0.0 {
        result.big_win_tier = Some(rf_stage::BigWinTier::Win);
    }

    drop(win_config); // Release read lock before storing

    let spin_id = SPIN_COUNT.fetch_add(1, Ordering::SeqCst) + 1;
    *LAST_SPIN_RESULT.write() = Some(result);
    *LAST_STAGES.write() = stages;

    log::debug!("slot_lab_spin_forced_p5: outcome={:?}, spin_id={}", forced, spin_id);
    spin_id
}

/// Execute a forced spin with EXACT target win multiplier for precise tier testing
///
/// Parameters:
/// - outcome: ForcedOutcome enum value (0-13)
/// - target_multiplier: Exact win multiplier (e.g., 1.5 for WIN_1, 3.5 for WIN_2, etc.)
///
/// The engine will override paytable evaluation with: total_win = bet * target_multiplier
/// This ensures each tier button (W1, W2, W3, etc.) produces a DISTINCT win tier.
///
/// Returns spin ID (> 0) on success, 0 if invalid
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_spin_forced_with_multiplier(outcome: i32, target_multiplier: f64) -> u64 {
    // Validate outcome range first
    if !(FORCED_OUTCOME_MIN..=FORCED_OUTCOME_MAX).contains(&outcome) {
        log::warn!(
            "slot_lab_spin_forced_with_multiplier: Invalid outcome value {} (valid range: {}-{})",
            outcome,
            FORCED_OUTCOME_MIN,
            FORCED_OUTCOME_MAX
        );
        return 0;
    }

    let mut guard = SLOT_ENGINE.write();
    let Some(ref mut engine) = *guard else {
        log::warn!("slot_lab_spin_forced_with_multiplier: Engine not initialized");
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
        _ => {
            log::error!("slot_lab_spin_forced_with_multiplier: Unexpected outcome: {}", outcome);
            return 0;
        }
    };

    // Execute spin with EXACT target multiplier
    let (mut result, stages) = engine.spin_forced_with_multiplier_and_stages(forced, target_multiplier);

    // Reevaluate with P5 Win Tier config to get correct tier name
    let win_config = WIN_TIER_CONFIG.read();
    let p5_result = win_config.evaluate(result.total_win, result.bet);

    // Update SpinResult with P5 tier info
    result.win_tier_name = if p5_result.primary_stage.is_empty() || p5_result.primary_stage == "NO_WIN" {
        None
    } else {
        Some(p5_result.primary_stage.clone())
    };

    // Map P5 result to legacy BigWinTier for backwards compatibility
    if p5_result.is_big_win {
        result.big_win_tier = match p5_result.big_win_max_tier {
            Some(5) => Some(rf_stage::BigWinTier::UltraWin),
            Some(4) => Some(rf_stage::BigWinTier::EpicWin),
            Some(3) => Some(rf_stage::BigWinTier::MegaWin),
            Some(2) => Some(rf_stage::BigWinTier::BigWin),
            Some(1) => Some(rf_stage::BigWinTier::BigWin),
            _ => Some(rf_stage::BigWinTier::BigWin),
        };
    } else if result.total_win > 0.0 {
        result.big_win_tier = Some(rf_stage::BigWinTier::Win);
    }

    drop(win_config);

    let spin_id = SPIN_COUNT.fetch_add(1, Ordering::SeqCst) + 1;
    *LAST_SPIN_RESULT.write() = Some(result);
    *LAST_STAGES.write() = stages;

    log::debug!(
        "slot_lab_spin_forced_with_multiplier: outcome={:?}, multiplier={:.2}x, spin_id={}",
        forced,
        target_multiplier,
        spin_id
    );
    spin_id
}

/// Get P5 Win Tier result for last spin as JSON
///
/// Returns JSON with full P5 tier evaluation:
/// {
///   "is_big_win": false,
///   "multiplier": 5.5,
///   "regular_tier_id": 4,
///   "big_win_max_tier": null,
///   "primary_stage": "WIN_4",
///   "display_label": "NICE WIN",
///   "rollup_duration_ms": 1500
/// }
///
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_last_spin_p5_tier_json() -> *mut c_char {
    let spin_result = LAST_SPIN_RESULT.read();
    let Some(ref result) = *spin_result else {
        let empty = r#"{"error":"No spin result available"}"#;
        return CString::new(empty).map(|c| c.into_raw()).unwrap_or(ptr::null_mut());
    };

    let win_config = WIN_TIER_CONFIG.read();
    let p5_result = win_config.evaluate(result.total_win, result.bet);
    drop(win_config);

    let json = serde_json::to_string(&p5_result).unwrap_or_else(|_| "{}".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Check if P5 Win Tier config is being used (always true now)
/// This is a compatibility function - P5 is always available
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_is_p5_win_tier_enabled() -> i32 {
    1
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

/// Get remaining free spins (legacy wrapper - uses ENGINE_V2)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_remaining_legacy() -> u32 {
    let guard = ENGINE_V2.read();
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

// ═══════════════════════════════════════════════════════════════════════════════
// JACKPOT FEATURE FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if Jackpot feature is currently active (won jackpot pending)
/// Returns 1 if active, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_is_active() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => if engine.is_jackpot_active() { 1 } else { 0 },
        None => 0,
    }
}

/// Get jackpot value for a specific tier
/// tier: 0=Mini, 1=Minor, 2=Major, 3=Grand
/// Returns current progressive value for that tier
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_get_tier_value(tier: i32) -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.jackpot_get_tier_value(tier as usize),
        None => 0.0,
    }
}

/// Get all jackpot tier values as JSON
/// Returns JSON: {"mini": 50.0, "minor": 200.0, "major": 1000.0, "grand": 10000.0}
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_get_all_values_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            let values = engine.jackpot_get_all_values();
            let json = serde_json::json!({
                "mini": values[0],
                "minor": values[1],
                "major": values[2],
                "grand": values[3],
            });
            match CString::new(json.to_string()) {
                Ok(cstr) => cstr.into_raw(),
                Err(_) => ptr::null_mut(),
            }
        }
        None => ptr::null_mut(),
    }
}

/// Get total contributions made to jackpots in this session
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_total_contributions() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.jackpot_total_contributions(),
        None => 0.0,
    }
}

/// Get won jackpot tier (if any is pending)
/// Returns -1 if no jackpot won, otherwise 0=Mini, 1=Minor, 2=Major, 3=Grand
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_won_tier() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.jackpot_won_tier().map(|t| t as i32).unwrap_or(-1),
        None => -1,
    }
}

/// Get won jackpot amount (if any is pending)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_won_amount() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.jackpot_won_amount(),
        None => 0.0,
    }
}

/// Force trigger a specific jackpot tier (for testing)
/// tier: 0=Mini, 1=Minor, 2=Major, 3=Grand
/// Returns 1 if triggered, 0 if failed
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_force_trigger(tier: i32) -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => if engine.force_trigger_jackpot(tier as usize) { 1 } else { 0 },
        None => 0,
    }
}

/// Complete jackpot celebration and return won amount
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_complete() -> f64 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => engine.jackpot_complete(),
        None => 0.0,
    }
}

/// Get complete Jackpot state as JSON
/// Returns JSON with tier_values, won_tier, won_amount, total_contributions
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_jackpot_get_state_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if let Some(json_str) = engine.jackpot_get_state_json() {
                match CString::new(json_str) {
                    Ok(cstr) => cstr.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            } else {
                // Return basic state if no snapshot
                let values = engine.jackpot_get_all_values();
                let json = serde_json::json!({
                    "is_active": false,
                    "tier_values": {
                        "mini": values[0],
                        "minor": values[1],
                        "major": values[2],
                        "grand": values[3],
                    },
                    "won_tier": null,
                    "won_amount": 0.0,
                    "total_contributions": engine.jackpot_total_contributions(),
                });
                match CString::new(json.to_string()) {
                    Ok(cstr) => cstr.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            }
        }
        None => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FREE SPINS FEATURE FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if Free Spins feature is currently active
/// Returns 1 if active, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_is_active() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => if engine.is_free_spins_active() { 1 } else { 0 },
        None => 0,
    }
}

/// Get remaining free spins count (P4 complete API)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_remaining() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.free_spins_remaining() as i32,
        None => 0,
    }
}

/// Get total free spins awarded
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_total() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.free_spins_total() as i32,
        None => 0,
    }
}

/// Get current multiplier in free spins
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_multiplier() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.free_spins_multiplier(),
        None => 1.0,
    }
}

/// Get total win accumulated in free spins session
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_total_win() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.free_spins_total_win(),
        None => 0.0,
    }
}

/// Force trigger Free Spins feature (for testing)
/// num_spins: number of spins to award
/// Returns 1 if triggered, 0 if failed
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_force_trigger(num_spins: i32) -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => if engine.force_trigger_free_spins(num_spins as u32) { 1 } else { 0 },
        None => 0,
    }
}

/// Add extra free spins (retrigger)
/// Returns 1 if added, 0 if failed (not in free spins)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_add(extra_spins: i32) -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => if engine.free_spins_add(extra_spins as u32) { 1 } else { 0 },
        None => 0,
    }
}

/// Complete Free Spins and return total win
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_complete() -> f64 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => engine.free_spins_complete(),
        None => 0.0,
    }
}

/// Get complete Free Spins state as JSON
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_free_spins_get_state_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if let Some(json_str) = engine.free_spins_get_state_json() {
                match CString::new(json_str) {
                    Ok(cstr) => cstr.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            } else {
                // Return inactive state
                let json = serde_json::json!({
                    "is_active": false,
                    "remaining": 0,
                    "total": 0,
                    "multiplier": 1.0,
                    "total_win": 0.0,
                    "spins_played": 0,
                });
                match CString::new(json.to_string()) {
                    Ok(cstr) => cstr.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            }
        }
        None => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CASCADE FEATURE FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if Cascade feature is currently active
/// Returns 1 if active, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_is_active() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => if engine.is_cascade_active() { 1 } else { 0 },
        None => 0,
    }
}

/// Get current cascade step (depth)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_current_step() -> i32 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.cascade_current_step() as i32,
        None => 0,
    }
}

/// Get current cascade multiplier
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_multiplier() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.cascade_multiplier(),
        None => 1.0,
    }
}

/// Get peak multiplier reached in current cascade sequence
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_peak_multiplier() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.cascade_peak_multiplier(),
        None => 1.0,
    }
}

/// Get total win accumulated in cascade sequence
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_total_win() -> f64 {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => engine.cascade_total_win(),
        None => 0.0,
    }
}

/// Force trigger Cascade feature (for testing)
/// Returns 1 if triggered, 0 if failed
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_force_trigger() -> i32 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => if engine.force_trigger_cascade() { 1 } else { 0 },
        None => 0,
    }
}

/// Complete Cascade and return total win
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_complete() -> f64 {
    let mut guard = ENGINE_V2.write();
    match &mut *guard {
        Some(engine) => engine.cascade_complete(),
        None => 0.0,
    }
}

/// Get complete Cascade state as JSON
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_cascade_get_state_json() -> *mut c_char {
    let guard = ENGINE_V2.read();
    match &*guard {
        Some(engine) => {
            if let Some(json_str) = engine.cascade_get_state_json() {
                match CString::new(json_str) {
                    Ok(cstr) => cstr.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            } else {
                // Return inactive state
                let json = serde_json::json!({
                    "is_active": false,
                    "current_step": 0,
                    "multiplier": 1.0,
                    "peak_multiplier": 1.0,
                    "total_win": 0.0,
                });
                match CString::new(json.to_string()) {
                    Ok(cstr) => cstr.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            }
        }
        None => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIN TIER CONFIGURATION FFI (P5)
// ═══════════════════════════════════════════════════════════════════════════════

use rf_slot_lab::model::{
    SlotWinConfig, RegularWinConfig, RegularWinTier, BigWinConfig, BigWinTier, WinTierResult,
};

/// Global Win Tier Configuration
static WIN_TIER_CONFIG: Lazy<RwLock<SlotWinConfig>> =
    Lazy::new(|| RwLock::new(SlotWinConfig::default()));

/// Set complete win tier configuration from JSON
///
/// JSON structure:
/// {
///   "regular_wins": {
///     "tiers": [
///       {"tier_id": -1, "from_multiplier": 0.0, "to_multiplier": 1.0, "display_label": "Low Win", ...},
///       {"tier_id": 0, "from_multiplier": 1.0, "to_multiplier": 1.0, "display_label": "Equal Win", ...},
///       {"tier_id": 1, "from_multiplier": 1.0, "to_multiplier": 2.0, "display_label": "Win 1", ...},
///       ...
///     ]
///   },
///   "big_wins": {
///     "threshold": 20.0,
///     "intro_duration_ms": 500,
///     "end_duration_ms": 1000,
///     "fade_out_duration_ms": 500,
///     "tiers": [
///       {"tier_id": 1, "from_multiplier": 20.0, "to_multiplier": 50.0, "display_label": "Big Win!", ...},
///       ...
///     ]
///   }
/// }
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_set_config_json(json: *const c_char) -> i32 {
    if json.is_null() {
        log::warn!("slot_lab_win_tier_set_config_json: Null input");
        return 0;
    }

    let json_str = unsafe {
        match CStr::from_ptr(json).to_str() {
            Ok(s) => s,
            Err(_) => {
                log::warn!("slot_lab_win_tier_set_config_json: Invalid UTF-8");
                return 0;
            }
        }
    };

    match serde_json::from_str::<SlotWinConfig>(json_str) {
        Ok(config) => {
            *WIN_TIER_CONFIG.write() = config;
            log::info!("slot_lab_win_tier_set_config_json: Configuration set successfully");
            1
        }
        Err(e) => {
            log::error!("slot_lab_win_tier_set_config_json: Parse error: {}", e);
            0
        }
    }
}

/// Get current win tier configuration as JSON
///
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_get_config_json() -> *mut c_char {
    let config = WIN_TIER_CONFIG.read();
    let json = serde_json::to_string(&*config).unwrap_or_else(|_| "{}".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Evaluate win amount and get tier result as JSON
///
/// win_amount: Total win amount
/// bet_amount: Bet for this spin
///
/// Returns JSON with tier info:
/// {
///   "is_big_win": false,
///   "multiplier": 3.5,
///   "primary_stage": "WIN_2",
///   "display_label": "Win 2",
///   "rollup_duration_ms": 2000,
///   "regular_tier_id": 2,
///   "big_win_tier_id": null
/// }
///
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_evaluate(win_amount: f64, bet_amount: f64) -> *mut c_char {
    if bet_amount <= 0.0 {
        log::warn!("slot_lab_win_tier_evaluate: Invalid bet amount: {}", bet_amount);
        let error = r#"{"error":"Invalid bet amount"}"#;
        return CString::new(error).map(|c| c.into_raw()).unwrap_or(ptr::null_mut());
    }

    let config = WIN_TIER_CONFIG.read();
    let result = config.evaluate(win_amount, bet_amount);

    let json = serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get big win threshold multiplier
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_get_big_win_threshold() -> f64 {
    WIN_TIER_CONFIG.read().big_wins.threshold
}

/// Set big win threshold multiplier
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_set_big_win_threshold(threshold: f64) {
    if threshold > 0.0 {
        WIN_TIER_CONFIG.write().big_wins.threshold = threshold;
        log::debug!("slot_lab_win_tier_set_big_win_threshold: Set to {}x", threshold);
    }
}

/// Get number of regular win tiers
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_regular_count() -> i32 {
    WIN_TIER_CONFIG.read().regular_wins.tiers.len() as i32
}

/// Get number of big win tiers
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_big_count() -> i32 {
    WIN_TIER_CONFIG.read().big_wins.tiers.len() as i32
}

/// Add a regular win tier
///
/// Returns 1 on success, 0 on failure (invalid parameters or duplicate tier_id)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_add_regular(
    tier_id: i32,
    from_multiplier: f64,
    to_multiplier: f64,
    display_label: *const c_char,
    rollup_duration_ms: u32,
) -> i32 {
    let label = if display_label.is_null() {
        format!("Win {}", tier_id)
    } else {
        unsafe {
            CStr::from_ptr(display_label)
                .to_str()
                .unwrap_or(&format!("Win {}", tier_id))
                .to_string()
        }
    };

    let tier = RegularWinTier {
        tier_id,
        from_multiplier,
        to_multiplier,
        display_label: label,
        rollup_duration_ms,
        rollup_tick_rate: 15, // Default
        particle_burst_count: 10, // Default
    };

    let mut config = WIN_TIER_CONFIG.write();

    // Check for duplicate
    if config.regular_wins.tiers.iter().any(|t| t.tier_id == tier_id) {
        log::warn!("slot_lab_win_tier_add_regular: Tier {} already exists", tier_id);
        return 0;
    }

    config.regular_wins.tiers.push(tier);
    config.regular_wins.tiers.sort_by(|a, b| a.tier_id.cmp(&b.tier_id));

    log::debug!("slot_lab_win_tier_add_regular: Added tier {}", tier_id);
    1
}

/// Update a regular win tier
///
/// Returns 1 on success, 0 on failure (tier not found)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_update_regular(
    tier_id: i32,
    from_multiplier: f64,
    to_multiplier: f64,
    display_label: *const c_char,
    rollup_duration_ms: u32,
) -> i32 {
    let mut config = WIN_TIER_CONFIG.write();

    if let Some(tier) = config.regular_wins.tiers.iter_mut().find(|t| t.tier_id == tier_id) {
        tier.from_multiplier = from_multiplier;
        tier.to_multiplier = to_multiplier;
        tier.rollup_duration_ms = rollup_duration_ms;

        if !display_label.is_null() {
            if let Ok(label) = unsafe { CStr::from_ptr(display_label).to_str() } {
                tier.display_label = label.to_string();
            }
        }

        log::debug!("slot_lab_win_tier_update_regular: Updated tier {}", tier_id);
        1
    } else {
        log::warn!("slot_lab_win_tier_update_regular: Tier {} not found", tier_id);
        0
    }
}

/// Remove a regular win tier
///
/// Returns 1 on success, 0 on failure (tier not found)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_remove_regular(tier_id: i32) -> i32 {
    let mut config = WIN_TIER_CONFIG.write();
    let original_len = config.regular_wins.tiers.len();
    config.regular_wins.tiers.retain(|t| t.tier_id != tier_id);

    if config.regular_wins.tiers.len() < original_len {
        log::debug!("slot_lab_win_tier_remove_regular: Removed tier {}", tier_id);
        1
    } else {
        log::warn!("slot_lab_win_tier_remove_regular: Tier {} not found", tier_id);
        0
    }
}

/// Update a big win tier
///
/// tier_id: 1-5 (internal big win tier)
/// Returns 1 on success, 0 on failure (tier not found)
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_update_big(
    tier_id: u32,
    from_multiplier: f64,
    to_multiplier: f64,
    display_label: *const c_char,
    duration_ms: u32,
) -> i32 {
    let mut config = WIN_TIER_CONFIG.write();

    if let Some(tier) = config.big_wins.tiers.iter_mut().find(|t| t.tier_id == tier_id) {
        tier.from_multiplier = from_multiplier;
        tier.to_multiplier = to_multiplier;
        tier.duration_ms = duration_ms;

        if !display_label.is_null() {
            if let Ok(label) = unsafe { CStr::from_ptr(display_label).to_str() } {
                tier.display_label = label.to_string();
            }
        }

        log::debug!("slot_lab_win_tier_update_big: Updated big win tier {}", tier_id);
        1
    } else {
        log::warn!("slot_lab_win_tier_update_big: Big win tier {} not found", tier_id);
        0
    }
}

/// Get all stage names that need audio events
///
/// Returns JSON array of stage names:
/// ["WIN_LOW", "WIN_EQUAL", "WIN_1", "WIN_2", ..., "BIG_WIN_TIER_1", "BIG_WIN_TIER_2", ...]
///
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_get_all_stage_names() -> *mut c_char {
    let config = WIN_TIER_CONFIG.read();
    let stages = config.all_stage_names();
    let json = serde_json::to_string(&stages).unwrap_or_else(|_| "[]".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Reset win tier configuration to defaults
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_reset_to_defaults() {
    *WIN_TIER_CONFIG.write() = SlotWinConfig::default();
    log::info!("slot_lab_win_tier_reset_to_defaults: Configuration reset");
}

/// Validate current win tier configuration
///
/// Returns 1 if valid, 0 if invalid
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_validate() -> i32 {
    let config = WIN_TIER_CONFIG.read();
    if config.validate() { 1 } else { 0 }
}

/// Get validation errors as JSON array
///
/// Returns JSON array of error strings (empty if valid)
///
/// CALLER MUST FREE using slot_lab_free_string()
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_get_validation_errors() -> *mut c_char {
    let config = WIN_TIER_CONFIG.read();
    let errors = config.validation_errors();
    let json = serde_json::to_string(&errors).unwrap_or_else(|_| "[]".to_string());

    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Set big win intro/end/fadeout durations
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_win_tier_set_big_win_durations(
    intro_duration_ms: u32,
    end_duration_ms: u32,
    fade_out_duration_ms: u32,
) {
    let mut config = WIN_TIER_CONFIG.write();
    config.big_wins.intro_duration_ms = intro_duration_ms;
    config.big_wins.end_duration_ms = end_duration_ms;
    config.big_wins.fade_out_duration_ms = fade_out_duration_ms;
    log::debug!("slot_lab_win_tier_set_big_win_durations: intro={}ms, end={}ms, fadeout={}ms",
        intro_duration_ms, end_duration_ms, fade_out_duration_ms);
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

    #[test]
    fn test_win_tier_configuration() {
        let _guard = TEST_LOCK.lock().unwrap();

        // Reset to defaults
        slot_lab_win_tier_reset_to_defaults();

        // Check defaults
        assert!(slot_lab_win_tier_get_big_win_threshold() >= 20.0);
        assert!(slot_lab_win_tier_regular_count() >= 8); // -1, 0, 1-6
        assert_eq!(slot_lab_win_tier_big_count(), 5);

        // Add a custom tier
        let label = CString::new("Custom Win").unwrap();
        assert_eq!(slot_lab_win_tier_add_regular(7, 15.0, 20.0, label.as_ptr(), 3000), 1);
        assert!(slot_lab_win_tier_regular_count() >= 9);

        // Try adding duplicate
        assert_eq!(slot_lab_win_tier_add_regular(7, 15.0, 20.0, label.as_ptr(), 3000), 0);

        // Update tier
        let new_label = CString::new("Updated Custom Win").unwrap();
        assert_eq!(slot_lab_win_tier_update_regular(7, 16.0, 20.0, new_label.as_ptr(), 3500), 1);

        // Remove tier
        assert_eq!(slot_lab_win_tier_remove_regular(7), 1);
        assert_eq!(slot_lab_win_tier_remove_regular(7), 0); // Already removed

        // Validate
        assert_eq!(slot_lab_win_tier_validate(), 1);

        // Reset
        slot_lab_win_tier_reset_to_defaults();
    }

    #[test]
    fn test_win_tier_evaluation() {
        let _guard = TEST_LOCK.lock().unwrap();

        slot_lab_win_tier_reset_to_defaults();

        // Test regular win (3x bet)
        let result_ptr = slot_lab_win_tier_evaluate(30.0, 10.0);
        assert!(!result_ptr.is_null());
        let result_str = unsafe { CStr::from_ptr(result_ptr).to_str().unwrap() };
        assert!(result_str.contains("\"is_big_win\":false"));
        slot_lab_free_string(result_ptr);

        // Test big win (25x bet)
        let result_ptr = slot_lab_win_tier_evaluate(250.0, 10.0);
        assert!(!result_ptr.is_null());
        let result_str = unsafe { CStr::from_ptr(result_ptr).to_str().unwrap() };
        assert!(result_str.contains("\"is_big_win\":true"));
        slot_lab_free_string(result_ptr);
    }
}

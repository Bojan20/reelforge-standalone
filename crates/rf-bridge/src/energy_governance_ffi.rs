//! GEG-7: Energy Governance FFI Bridge
//!
//! Exposes GEG functions via C FFI. Uses the shared AUREXIS ENGINE global
//! from aurexis_ffi.rs since EnergyGovernor lives inside AurexisEngine.

use std::ffi::{CString, c_char};
use std::ptr;

use crate::aurexis_ffi::ENGINE;
use rf_aurexis::energy::{EnergyDomain, GegCurveType, SlotProfile};

// ═══════════════════════════════════════════════════════════════════════════════
// PROFILE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Set active slot profile (0-8). Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn geg_set_profile(profile_index: u8) -> i32 {
    let profile = match profile_index {
        0 => SlotProfile::HighVolatility,
        1 => SlotProfile::MediumVolatility,
        2 => SlotProfile::LowVolatility,
        3 => SlotProfile::CascadeHeavy,
        4 => SlotProfile::FeatureHeavy,
        5 => SlotProfile::JackpotFocused,
        6 => SlotProfile::Classic3Reel,
        7 => SlotProfile::ClusterPay,
        8 => SlotProfile::MegawaysStyle,
        _ => return 0,
    };
    if let Some(ref mut engine) = *ENGINE.write() {
        engine.energy_governor_mut().set_profile(profile);
        return 1;
    }
    0
}

/// Get current slot profile index (0-8). Returns 255 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn geg_get_profile() -> u8 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.energy_governor().profile() as u8;
    }
    255
}

/// Get slot profile name by index. Caller must free with geg_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn geg_profile_name(profile_index: u8) -> *mut c_char {
    let profile = match profile_index {
        0 => SlotProfile::HighVolatility,
        1 => SlotProfile::MediumVolatility,
        2 => SlotProfile::LowVolatility,
        3 => SlotProfile::CascadeHeavy,
        4 => SlotProfile::FeatureHeavy,
        5 => SlotProfile::JackpotFocused,
        6 => SlotProfile::Classic3Reel,
        7 => SlotProfile::ClusterPay,
        8 => SlotProfile::MegawaysStyle,
        _ => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(profile.name()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get number of slot profiles (always 9).
#[unsafe(no_mangle)]
pub extern "C" fn geg_profile_count() -> u32 {
    9
}

// ═══════════════════════════════════════════════════════════════════════════════
// ESCALATION CURVE
// ═══════════════════════════════════════════════════════════════════════════════

/// Set active escalation curve (0-5). Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn geg_set_curve(curve_index: u8) -> i32 {
    let curve = match curve_index {
        0 => GegCurveType::Linear,
        1 => GegCurveType::Logarithmic,
        2 => GegCurveType::Exponential,
        3 => GegCurveType::CappedExponential,
        4 => GegCurveType::Step,
        5 => GegCurveType::SCurve,
        _ => return 0,
    };
    if let Some(ref mut engine) = *ENGINE.write() {
        engine.energy_governor_mut().set_curve(curve);
        return 1;
    }
    0
}

/// Get active escalation curve index (0-5). Returns 255 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn geg_get_curve() -> u8 {
    if let Some(ref engine) = *ENGINE.read() {
        return match engine.energy_governor().curve() {
            GegCurveType::Linear => 0,
            GegCurveType::Logarithmic => 1,
            GegCurveType::Exponential => 2,
            GegCurveType::CappedExponential => 3,
            GegCurveType::Step => 4,
            GegCurveType::SCurve => 5,
        };
    }
    255
}

// ═══════════════════════════════════════════════════════════════════════════════
// SESSION MEMORY
// ═══════════════════════════════════════════════════════════════════════════════

/// Record a spin result for session memory.
#[unsafe(no_mangle)]
pub extern "C" fn geg_record_spin(win_multiplier: f64, is_feature: i32, is_jackpot: i32) -> i32 {
    if let Some(ref mut engine) = *ENGINE.write() {
        engine.record_spin(win_multiplier, is_feature != 0, is_jackpot != 0);
        return 1;
    }
    0
}

/// Get current Session Memory factor (SM). Returns value in [0.7, 1.0].
#[unsafe(no_mangle)]
pub extern "C" fn geg_get_session_memory() -> f64 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.energy_governor().session_memory().sm();
    }
    1.0
}

/// Get total spins recorded in session.
#[unsafe(no_mangle)]
pub extern "C" fn geg_get_total_spins() -> u64 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.energy_governor().session_memory().total_spins();
    }
    0
}

/// Get current loss streak length.
#[unsafe(no_mangle)]
pub extern "C" fn geg_get_loss_streak() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.energy_governor().session_memory().loss_streak();
    }
    0
}

/// Check if feature storm cooldown is active (1 = yes, 0 = no).
#[unsafe(no_mangle)]
pub extern "C" fn geg_is_feature_storm() -> i32 {
    if let Some(ref engine) = *ENGINE.read() {
        return if engine
            .energy_governor()
            .session_memory()
            .feature_storm_active()
        {
            1
        } else {
            0
        };
    }
    0
}

/// Check if jackpot compression is active (1 = yes, 0 = no).
#[unsafe(no_mangle)]
pub extern "C" fn geg_is_jackpot_compression() -> i32 {
    if let Some(ref engine) = *ENGINE.read() {
        return if engine
            .energy_governor()
            .session_memory()
            .jackpot_compression_active()
        {
            1
        } else {
            0
        };
    }
    0
}

/// Reset session memory.
#[unsafe(no_mangle)]
pub extern "C" fn geg_reset_session() -> i32 {
    if let Some(ref mut engine) = *ENGINE.write() {
        engine.energy_governor_mut().reset_session();
        return 1;
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENERGY BUDGET QUERIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get energy cap for a specific domain (0-4).
/// Returns domain cap [0.0, 1.0] or -1.0 if invalid.
#[unsafe(no_mangle)]
pub extern "C" fn geg_domain_cap(domain: u8) -> f64 {
    if domain > 4 {
        return -1.0;
    }
    if let Some(ref engine) = *ENGINE.read() {
        let d = match domain {
            0 => EnergyDomain::Dynamic,
            1 => EnergyDomain::Transient,
            2 => EnergyDomain::Spatial,
            3 => EnergyDomain::Harmonic,
            4 => EnergyDomain::Temporal,
            _ => return -1.0,
        };
        return engine.energy_governor().domain_cap(d);
    }
    -1.0
}

/// Get overall energy cap (average of 5 domains). Returns [0.0, 1.0].
#[unsafe(no_mangle)]
pub extern "C" fn geg_overall_cap() -> f64 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.energy_governor().budget().overall_cap;
    }
    0.5
}

/// Get all 5 domain caps as a flat f64 array. Caller provides buffer of 5 f64s.
#[unsafe(no_mangle)]
pub extern "C" fn geg_all_domain_caps(out_caps: *mut f64) -> i32 {
    if out_caps.is_null() {
        return 0;
    }
    if let Some(ref engine) = *ENGINE.read() {
        let caps = &engine.energy_governor().budget().caps;
        unsafe {
            for i in 0..5 {
                *out_caps.add(i) = caps[i];
            }
        }
        return 1;
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE BUDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current max voice count.
#[unsafe(no_mangle)]
pub extern "C" fn geg_voice_budget_max() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.energy_governor().voice_budget().max_voices;
    }
    40
}

/// Get current voice budget ratio (0.5, 0.7, or 0.9).
#[unsafe(no_mangle)]
pub extern "C" fn geg_voice_budget_ratio() -> f64 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.energy_governor().voice_budget().budget_ratio;
    }
    0.7
}

// ═══════════════════════════════════════════════════════════════════════════════
// BAKE OUTPUT (GEG-12)
// ═══════════════════════════════════════════════════════════════════════════════

/// Get energy config JSON for bake. Caller must free with geg_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn geg_energy_config_json() -> *mut c_char {
    if let Some(ref engine) = *ENGINE.read() {
        if let Ok(json) = engine.energy_governor().budget_to_json() {
            if let Ok(s) = CString::new(json) {
                return s.into_raw();
            }
        }
    }
    ptr::null_mut()
}

/// Get slot profile JSON for bake. Caller must free with geg_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn geg_slot_profile_json() -> *mut c_char {
    if let Some(ref engine) = *ENGINE.read() {
        if let Ok(json) = engine.energy_governor().profile_to_json() {
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

/// Free a string returned by geg_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn geg_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

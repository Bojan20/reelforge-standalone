//! PBSE: Pre-Bake Simulation Engine FFI Bridge
//!
//! Exposes PBSE functions via C FFI. PBSE has its own global state
//! (separate from AUREXIS ENGINE) because it creates internal engines
//! for each simulation run.

use std::ffi::{c_char, CString};
use std::ptr;

use once_cell::sync::Lazy;
use parking_lot::RwLock;

use rf_aurexis::qa::pbse::{PreBakeSimulator, SimulationDomain, ValidationThresholds};

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

pub(crate) static PBSE: Lazy<RwLock<PreBakeSimulator>> = Lazy::new(|| RwLock::new(PreBakeSimulator::new()));

/// Get PBSE result for cross-module access (used by AIL).
pub(crate) fn get_pbse_result() -> Option<rf_aurexis::qa::pbse::PbseResult> {
    PBSE.read().last_result().as_ref().cloned()
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Reset PBSE to default state.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_reset() -> i32 {
    *PBSE.write() = PreBakeSimulator::new();
    1
}

/// Set validation thresholds.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_set_thresholds(
    max_energy_cap: f64,
    max_voices: u32,
    max_sci: f64,
    max_fatigue: f64,
    max_escalation_slope: f64,
) -> i32 {
    PBSE.write().set_thresholds(ValidationThresholds {
        max_energy_cap,
        max_voices,
        max_sci,
        max_fatigue,
        max_escalation_slope,
    });
    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIMULATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Run full simulation across all 10 domains.
/// Returns 1 if all passed (bake unlocked), 0 if any failed.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_run_full_simulation() -> i32 {
    let mut sim = PBSE.write();
    sim.run_full_simulation();
    if sim.bake_unlocked() { 1 } else { 0 }
}

/// Run a single domain simulation. Returns 1 if domain passed.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_run_domain(domain_index: u8) -> i32 {
    let domain = match SimulationDomain::from_index(domain_index) {
        Some(d) => d,
        None => return 0,
    };
    let result = PBSE.read().run_domain(domain);
    if result.passed { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUERIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if bake is unlocked.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_bake_unlocked() -> i32 {
    if PBSE.read().bake_unlocked() { 1 } else { 0 }
}

/// Get domain count (always 10).
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_count() -> u32 {
    SimulationDomain::COUNT as u32
}

/// Get domain name. Caller must free with pbse_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_name(domain_index: u8) -> *mut c_char {
    let domain = match SimulationDomain::from_index(domain_index) {
        Some(d) => d,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(domain.name()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Check if a domain passed in last full simulation.
/// Returns: 1=passed, 0=failed, -1=not yet run.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_passed(domain_index: u8) -> i32 {
    let sim = PBSE.read();
    match sim.last_result() {
        Some(result) => {
            if let Some(domain_result) = result.domains.get(domain_index as usize) {
                if domain_result.passed { 1 } else { 0 }
            } else {
                -1
            }
        }
        None => -1,
    }
}

/// Get total spins from last full simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_total_spins() -> u32 {
    PBSE.read().last_result().as_ref().map_or(0, |r| r.total_spins)
}

/// Check if determinism was verified in last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_determinism_verified() -> i32 {
    match PBSE.read().last_result() {
        Some(r) => if r.determinism_verified { 1 } else { 0 },
        None => -1,
    }
}

/// Get domain peak energy cap from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_peak_energy(domain_index: u8) -> f64 {
    let sim = PBSE.read();
    sim.last_result().as_ref()
        .and_then(|r| r.domains.get(domain_index as usize))
        .map_or(0.0, |d| d.peak_energy_cap)
}

/// Get domain peak voice count from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_peak_voices(domain_index: u8) -> u32 {
    let sim = PBSE.read();
    sim.last_result().as_ref()
        .and_then(|r| r.domains.get(domain_index as usize))
        .map_or(0, |d| d.peak_voice_count)
}

/// Get domain peak SCI from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_peak_sci(domain_index: u8) -> f64 {
    let sim = PBSE.read();
    sim.last_result().as_ref()
        .and_then(|r| r.domains.get(domain_index as usize))
        .map_or(0.0, |d| d.peak_sci)
}

/// Get domain peak fatigue from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_peak_fatigue(domain_index: u8) -> f64 {
    let sim = PBSE.read();
    sim.last_result().as_ref()
        .and_then(|r| r.domains.get(domain_index as usize))
        .map_or(0.0, |d| d.peak_fatigue)
}

/// Get domain escalation slope from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_escalation_slope(domain_index: u8) -> f64 {
    let sim = PBSE.read();
    sim.last_result().as_ref()
        .and_then(|r| r.domains.get(domain_index as usize))
        .map_or(0.0, |d| d.escalation_slope)
}

/// Get domain spin count from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_spin_count(domain_index: u8) -> u32 {
    let sim = PBSE.read();
    sim.last_result().as_ref()
        .and_then(|r| r.domains.get(domain_index as usize))
        .map_or(0, |d| d.spin_count)
}

/// Get domain determinism status from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_deterministic(domain_index: u8) -> i32 {
    let sim = PBSE.read();
    match sim.last_result().as_ref()
        .and_then(|r| r.domains.get(domain_index as usize)) {
        Some(d) => if d.deterministic { 1 } else { 0 },
        None => -1,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FATIGUE MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Get fatigue model index from last simulation.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_fatigue_index() -> f64 {
    PBSE.read().last_result().as_ref().map_or(0.0, |r| r.fatigue_model.fatigue_index)
}

/// Get fatigue model passed status.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_fatigue_passed() -> i32 {
    match PBSE.read().last_result() {
        Some(r) => if r.fatigue_model.passed { 1 } else { 0 },
        None => -1,
    }
}

/// Get fatigue model peak frequency.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_fatigue_peak_frequency() -> f64 {
    PBSE.read().last_result().as_ref().map_or(0.0, |r| r.fatigue_model.peak_frequency)
}

/// Get fatigue model harmonic density.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_fatigue_harmonic_density() -> f64 {
    PBSE.read().last_result().as_ref().map_or(0.0, |r| r.fatigue_model.harmonic_density)
}

/// Get fatigue model temporal density.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_fatigue_temporal_density() -> f64 {
    PBSE.read().last_result().as_ref().map_or(0.0, |r| r.fatigue_model.temporal_density)
}

/// Get fatigue model recovery factor.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_fatigue_recovery_factor() -> f64 {
    PBSE.read().last_result().as_ref().map_or(0.0, |r| r.fatigue_model.recovery_factor)
}

// ═══════════════════════════════════════════════════════════════════════════════
// THRESHOLDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get max energy cap threshold.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_threshold_max_energy() -> f64 {
    PBSE.read().thresholds().max_energy_cap
}

/// Get max voices threshold.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_threshold_max_voices() -> u32 {
    PBSE.read().thresholds().max_voices
}

/// Get max SCI threshold.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_threshold_max_sci() -> f64 {
    PBSE.read().thresholds().max_sci
}

/// Get max fatigue threshold.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_threshold_max_fatigue() -> f64 {
    PBSE.read().thresholds().max_fatigue
}

/// Get max escalation slope threshold.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_threshold_max_slope() -> f64 {
    PBSE.read().thresholds().max_escalation_slope
}

// ═══════════════════════════════════════════════════════════════════════════════
// BAKE OUTPUT
// ═══════════════════════════════════════════════════════════════════════════════

/// Get simulation summary JSON. Caller must free with pbse_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_simulation_summary_json() -> *mut c_char {
    if let Ok(json) = PBSE.read().simulation_summary_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

/// Get domain names JSON. Caller must free with pbse_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_domain_names_json() -> *mut c_char {
    if let Ok(json) = PreBakeSimulator::domain_names_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by pbse_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn pbse_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

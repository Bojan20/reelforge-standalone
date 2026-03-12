//! DRC: Deterministic Replay Core FFI Bridge
//!
//! Exposes CertificationGate (which wraps DRC, SafetyEnvelope, Manifest)
//! via C FFI. Single global instance.

use std::ffi::{CString, c_char};
use std::ptr;

use std::sync::LazyLock;
use parking_lot::RwLock;

use rf_aurexis::core::engine::AurexisEngine;
use rf_aurexis::core::parameter_map::DeterministicParameterMap;
use rf_aurexis::drc::certification::CertificationGate;
use rf_aurexis::drc::manifest::CertificationStatus;
use rf_aurexis::qa::simulation::SimulationStep;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

static CERT_GATE: LazyLock<RwLock<CertificationGate>> =
    LazyLock::new(|| RwLock::new(CertificationGate::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Reset certification gate to default state.
#[unsafe(no_mangle)]
pub extern "C" fn drc_reset() -> i32 {
    CERT_GATE.write().reset();
    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// FULL CERTIFICATION PIPELINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Run full certification pipeline (PBSE + DRC + Envelope + Manifest).
/// Uses PBSE global result if available.
/// Returns 1 if certified, 0 if failed.
#[unsafe(no_mangle)]
pub extern "C" fn drc_run_certification() -> i32 {
    let pbse_result = super::pbse_ffi::get_pbse_result();

    // Generate test steps for DRC replay verification
    let steps = generate_test_steps(50);

    // Run engine to get outputs
    let outputs = run_engine_steps(&steps);

    // Config data (use version as config fingerprint)
    let config_data = format!("fluxforge:{}:drc_certification", env!("CARGO_PKG_VERSION"));

    let mut gate = CERT_GATE.write();
    let result = gate.certify(pbse_result.as_ref(), &steps, &outputs, &config_data);
    if result.certified { 1 } else { 0 }
}

/// Run certification with custom spin count.
#[unsafe(no_mangle)]
pub extern "C" fn drc_run_certification_with_spins(spin_count: u32) -> i32 {
    let pbse_result = super::pbse_ffi::get_pbse_result();
    let count = (spin_count as usize).clamp(10, 10000);
    let steps = generate_test_steps(count);
    let outputs = run_engine_steps(&steps);
    let config_data = format!("fluxforge:{}:drc_certification", env!("CARGO_PKG_VERSION"));

    let mut gate = CERT_GATE.write();
    let result = gate.certify(pbse_result.as_ref(), &steps, &outputs, &config_data);
    if result.certified { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CERTIFICATION STATUS
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if last certification passed.
#[unsafe(no_mangle)]
pub extern "C" fn drc_is_certified() -> i32 {
    if CERT_GATE.read().is_certified() {
        1
    } else {
        0
    }
}

/// Has certification been run?
#[unsafe(no_mangle)]
pub extern "C" fn drc_has_result() -> i32 {
    if CERT_GATE.read().last_result().is_some() {
        1
    } else {
        0
    }
}

/// Get certification status: 0=Pending, 1=Certified, 2=Failed. Returns -1 if no result.
#[unsafe(no_mangle)]
pub extern "C" fn drc_certification_status() -> i32 {
    CERT_GATE
        .read()
        .last_result()
        .map_or(-1, |r| match r.report.overall_status {
            CertificationStatus::Pending => 0,
            CertificationStatus::Certified => 1,
            CertificationStatus::Failed => 2,
        })
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get certification stage count. Returns 0 if no result.
#[unsafe(no_mangle)]
pub extern "C" fn drc_stage_count() -> u32 {
    CERT_GATE
        .read()
        .last_result()
        .map_or(0, |r| r.report.stages.len() as u32)
}

/// Get stage name. Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_stage_name(stage_index: u32) -> *mut c_char {
    let guard = CERT_GATE.read();
    let name = match guard
        .last_result()
        .and_then(|r| r.report.stages.get(stage_index as usize))
    {
        Some(s) => s.name,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(name) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get stage pass status. Returns -1 if invalid.
#[unsafe(no_mangle)]
pub extern "C" fn drc_stage_passed(stage_index: u32) -> i32 {
    CERT_GATE
        .read()
        .last_result()
        .and_then(|r| r.report.stages.get(stage_index as usize))
        .map_or(-1, |s| if s.passed { 1 } else { 0 })
}

/// Get stage details. Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_stage_details(stage_index: u32) -> *mut c_char {
    let guard = CERT_GATE.read();
    let details = match guard
        .last_result()
        .and_then(|r| r.report.stages.get(stage_index as usize))
    {
        Some(s) => &s.details,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(details.as_str()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLOCKING FAILURES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get blocking failure count.
#[unsafe(no_mangle)]
pub extern "C" fn drc_blocking_failure_count() -> u32 {
    CERT_GATE
        .read()
        .last_result()
        .map_or(0, |r| r.report.blocking_failures.len() as u32)
}

/// Get blocking failure message. Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_blocking_failure(failure_index: u32) -> *mut c_char {
    let guard = CERT_GATE.read();
    let msg = match guard
        .last_result()
        .and_then(|r| r.report.blocking_failures.get(failure_index as usize))
    {
        Some(m) => m,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(msg.as_str()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MANIFEST
// ═══════════════════════════════════════════════════════════════════════════════

/// Get manifest hash (64-bit).
#[unsafe(no_mangle)]
pub extern "C" fn drc_manifest_hash() -> u64 {
    CERT_GATE.read().manifest().manifest_hash
}

/// Get config bundle hash (64-bit).
#[unsafe(no_mangle)]
pub extern "C" fn drc_config_bundle_hash() -> u64 {
    CERT_GATE.read().manifest().config_bundle.config_bundle_hash
}

/// Get manifest version string. Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_manifest_version() -> *mut c_char {
    let guard = CERT_GATE.read();
    let version = &guard.manifest().manifest_version;
    if let Ok(s) = CString::new(version.as_str()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get manifest certification status: 0=Pending, 1=Certified, 2=Failed.
#[unsafe(no_mangle)]
pub extern "C" fn drc_manifest_certification_status() -> i32 {
    match CERT_GATE
        .read()
        .manifest()
        .certification_chain
        .overall_certification
    {
        CertificationStatus::Pending => 0,
        CertificationStatus::Certified => 1,
        CertificationStatus::Failed => 2,
    }
}

/// Get manifest as JSON. Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_manifest_json() -> *mut c_char {
    let guard = CERT_GATE.read();
    if let Ok(json) = guard.manifest().to_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAFETY ENVELOPE
// ═══════════════════════════════════════════════════════════════════════════════

/// Get safety envelope pass status.
#[unsafe(no_mangle)]
pub extern "C" fn drc_envelope_passed() -> i32 {
    if CERT_GATE.read().safety_envelope().passed() {
        1
    } else {
        0
    }
}

/// Get envelope peak energy.
#[unsafe(no_mangle)]
pub extern "C" fn drc_envelope_peak_energy() -> f64 {
    CERT_GATE
        .read()
        .safety_envelope()
        .last_result()
        .map_or(0.0, |r| r.peak_energy)
}

/// Get envelope peak voices.
#[unsafe(no_mangle)]
pub extern "C" fn drc_envelope_peak_voices() -> u32 {
    CERT_GATE
        .read()
        .safety_envelope()
        .last_result()
        .map_or(0, |r| r.peak_voices)
}

/// Get envelope max peak duration (consecutive frames > 0.9).
#[unsafe(no_mangle)]
pub extern "C" fn drc_envelope_max_peak_duration() -> u32 {
    CERT_GATE
        .read()
        .safety_envelope()
        .last_result()
        .map_or(0, |r| r.max_peak_duration)
}

/// Get envelope peak SCI.
#[unsafe(no_mangle)]
pub extern "C" fn drc_envelope_peak_sci() -> f64 {
    CERT_GATE
        .read()
        .safety_envelope()
        .last_result()
        .map_or(0.0, |r| r.peak_sci)
}

/// Get envelope peak session percentage.
#[unsafe(no_mangle)]
pub extern "C" fn drc_envelope_peak_session_pct() -> f64 {
    CERT_GATE
        .read()
        .safety_envelope()
        .last_result()
        .map_or(0.0, |r| r.peak_session_pct)
}

/// Get envelope violation count.
#[unsafe(no_mangle)]
pub extern "C" fn drc_envelope_violation_count() -> u32 {
    CERT_GATE
        .read()
        .safety_envelope()
        .last_result()
        .map_or(0, |r| r.violations.len() as u32)
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAFETY LIMITS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get max energy limit.
#[unsafe(no_mangle)]
pub extern "C" fn drc_limit_max_energy() -> f64 {
    CERT_GATE.read().safety_envelope().limits().max_energy
}

/// Get max peak duration frames limit.
#[unsafe(no_mangle)]
pub extern "C" fn drc_limit_max_peak_duration() -> u32 {
    CERT_GATE
        .read()
        .safety_envelope()
        .limits()
        .max_peak_duration_frames
}

/// Get max voices limit.
#[unsafe(no_mangle)]
pub extern "C" fn drc_limit_max_voices() -> u32 {
    CERT_GATE.read().safety_envelope().limits().max_voices
}

/// Get max harmonic density limit.
#[unsafe(no_mangle)]
pub extern "C" fn drc_limit_max_harmonic_density() -> u32 {
    CERT_GATE
        .read()
        .safety_envelope()
        .limits()
        .max_harmonic_density
}

/// Get max SCI limit.
#[unsafe(no_mangle)]
pub extern "C" fn drc_limit_max_sci() -> f64 {
    CERT_GATE.read().safety_envelope().limits().max_sci
}

/// Get max peak session percentage limit.
#[unsafe(no_mangle)]
pub extern "C" fn drc_limit_max_peak_session_pct() -> f64 {
    CERT_GATE
        .read()
        .safety_envelope()
        .limits()
        .max_peak_session_pct
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRC REPLAY CORE
// ═══════════════════════════════════════════════════════════════════════════════

/// Get DRC replay pass status.
#[unsafe(no_mangle)]
pub extern "C" fn drc_replay_passed() -> i32 {
    if CERT_GATE.read().replay_core().passed() {
        1
    } else {
        0
    }
}

/// Get DRC total frames from last replay.
#[unsafe(no_mangle)]
pub extern "C" fn drc_replay_total_frames() -> u32 {
    CERT_GATE
        .read()
        .replay_core()
        .last_result()
        .map_or(0, |r| r.total_frames)
}

/// Get DRC mismatch count from last replay.
#[unsafe(no_mangle)]
pub extern "C" fn drc_replay_mismatch_count() -> u32 {
    CERT_GATE
        .read()
        .replay_core()
        .last_result()
        .map_or(0, |r| r.mismatches.len() as u32)
}

/// Get DRC recorded final hash (hex). Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_replay_recorded_hash() -> *mut c_char {
    let guard = CERT_GATE.read();
    let hash_str = match guard.replay_core().last_result() {
        Some(r) => r.recorded_final_hash.as_hex(),
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(hash_str) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get DRC replay final hash (hex). Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_replay_replay_hash() -> *mut c_char {
    let guard = CERT_GATE.read();
    let hash_str = match guard.replay_core().last_result() {
        Some(r) => r.replay_final_hash.as_hex(),
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(hash_str) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get DRC trace as JSON. Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_trace_json() -> *mut c_char {
    let guard = CERT_GATE.read();
    if let Ok(json) = guard.replay_core().trace_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// CERTIFICATION REPORT JSON
// ═══════════════════════════════════════════════════════════════════════════════

/// Get full certification report as JSON. Caller must free with drc_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn drc_report_json() -> *mut c_char {
    let guard = CERT_GATE.read();
    if let Ok(json) = guard.report_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by drc_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn drc_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

fn generate_test_steps(count: usize) -> Vec<SimulationStep> {
    (0..count)
        .map(|i| SimulationStep {
            elapsed_ms: 50,
            volatility: 0.5 + (i as f64 * 0.005).sin() * 0.3,
            rtp: 96.0,
            win_multiplier: if i % 10 == 0 {
                5.0
            } else if i % 7 == 0 {
                2.0
            } else {
                0.0
            },
            jackpot_proximity: if i % 20 == 0 { 0.3 } else { 0.0 },
            rms_db: -20.0,
            hf_db: -26.0,
        })
        .collect()
}

fn run_engine_steps(steps: &[SimulationStep]) -> Vec<DeterministicParameterMap> {
    let mut engine = AurexisEngine::new();
    engine.initialize();
    engine.set_seed(0, 0, 0, 0);

    steps
        .iter()
        .map(|step| {
            engine.set_volatility(step.volatility);
            engine.set_rtp(step.rtp);
            engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
            engine.set_metering(step.rms_db, step.hf_db);

            let is_jackpot = step.jackpot_proximity > 0.9 && step.win_multiplier > 100.0;
            let is_feature = step.win_multiplier > 10.0;
            engine.record_spin(step.win_multiplier, is_feature, is_jackpot);

            engine.compute_cloned(step.elapsed_ms)
        })
        .collect()
}

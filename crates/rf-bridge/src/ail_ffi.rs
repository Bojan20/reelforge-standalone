//! AIL: Authoring Intelligence Layer FFI Bridge
//!
//! Exposes AIL advisory functions via C FFI. AIL has its own global state
//! (separate from AUREXIS ENGINE) because it creates internal engines
//! for each analysis run.

use std::ffi::{CString, c_char};
use std::ptr;

use std::sync::LazyLock;
use parking_lot::RwLock;

use rf_aurexis::advisory::ail::AuthoringIntelligence;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

static AIL: LazyLock<RwLock<AuthoringIntelligence>> =
    LazyLock::new(|| RwLock::new(AuthoringIntelligence::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Reset AIL to default state.
#[unsafe(no_mangle)]
pub extern "C" fn ail_reset() -> i32 {
    AIL.write().reset();
    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANALYSIS
// ═══════════════════════════════════════════════════════════════════════════════

/// Run full AIL analysis. Uses PBSE results if available.
/// Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn ail_run_analysis() -> i32 {
    // Get PBSE result if available
    let pbse = super::pbse_ffi::get_pbse_result();
    let mut ail = AIL.write();
    ail.analyze(pbse.as_ref());
    1
}

/// Check if AIL has results.
#[unsafe(no_mangle)]
pub extern "C" fn ail_has_results() -> i32 {
    if AIL.read().last_report().is_some() {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCORE & STATUS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get AIL score (0–100). Returns -1.0 if no report.
#[unsafe(no_mangle)]
pub extern "C" fn ail_score() -> f64 {
    AIL.read().last_report().map_or(-1.0, |r| r.score.value)
}

/// Get AIL status index: 0=Excellent, 1=Good, 2=Fair, 3=Poor, 4=Critical.
/// Returns -1 if no report.
#[unsafe(no_mangle)]
pub extern "C" fn ail_status() -> i32 {
    AIL.read()
        .last_report()
        .map_or(-1, |r| r.score.status as i32)
}

/// Get PBSE passed status from AIL report.
#[unsafe(no_mangle)]
pub extern "C" fn ail_pbse_passed() -> i32 {
    AIL.read()
        .last_report()
        .map_or(-1, |r| if r.pbse_passed { 1 } else { 0 })
}

/// Get simulation spin count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_simulation_spins() -> u32 {
    AIL.read().last_report().map_or(0, |r| r.simulation_spins)
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOMAIN RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get domain count (always 10).
#[unsafe(no_mangle)]
pub extern "C" fn ail_domain_count() -> u32 {
    10
}

/// Get domain score (0–100). Returns -1.0 if no report or invalid index.
#[unsafe(no_mangle)]
pub extern "C" fn ail_domain_score(domain_index: u8) -> f64 {
    AIL.read()
        .last_report()
        .and_then(|r| r.domain_analyses.get(domain_index as usize))
        .map_or(-1.0, |d| d.score)
}

/// Get domain risk (0.0–1.0). Returns -1.0 if no report.
#[unsafe(no_mangle)]
pub extern "C" fn ail_domain_risk(domain_index: u8) -> f64 {
    AIL.read()
        .last_report()
        .and_then(|r| r.domain_analyses.get(domain_index as usize))
        .map_or(-1.0, |d| d.risk)
}

/// Get domain name. Caller must free with ail_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn ail_domain_name(domain_index: u8) -> *mut c_char {
    use rf_aurexis::advisory::ail::AilDomain;
    let domain = match AilDomain::from_index(domain_index) {
        Some(d) => d,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(domain.name()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// FATIGUE
// ═══════════════════════════════════════════════════════════════════════════════

/// Get fatigue score (0–100). Returns -1.0 if no report.
#[unsafe(no_mangle)]
pub extern "C" fn ail_fatigue_score() -> f64 {
    AIL.read()
        .last_report()
        .map_or(-1.0, |r| r.fatigue.fatigue_score)
}

/// Get fatigue peak frequency.
#[unsafe(no_mangle)]
pub extern "C" fn ail_fatigue_peak_frequency() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.fatigue.peak_frequency)
}

/// Get fatigue harmonic density.
#[unsafe(no_mangle)]
pub extern "C" fn ail_fatigue_harmonic_density() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.fatigue.harmonic_density)
}

/// Get fatigue temporal density.
#[unsafe(no_mangle)]
pub extern "C" fn ail_fatigue_temporal_density() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.fatigue.temporal_density)
}

/// Get fatigue recovery factor.
#[unsafe(no_mangle)]
pub extern "C" fn ail_fatigue_recovery_factor() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.fatigue.recovery_factor)
}

/// Get fatigue risk level: 0=LOW, 1=MODERATE, 2=HIGH, 3=CRITICAL.
#[unsafe(no_mangle)]
pub extern "C" fn ail_fatigue_risk_level() -> i32 {
    AIL.read()
        .last_report()
        .map_or(-1, |r| match r.fatigue.risk_level {
            "LOW" => 0,
            "MODERATE" => 1,
            "HIGH" => 2,
            "CRITICAL" => 3,
            _ => -1,
        })
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE EFFICIENCY
// ═══════════════════════════════════════════════════════════════════════════════

/// Get average voice count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_voice_avg() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.voice_efficiency.avg_voices)
}

/// Get peak voice count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_voice_peak() -> u32 {
    AIL.read()
        .last_report()
        .map_or(0, |r| r.voice_efficiency.peak_voices)
}

/// Get voice budget cap.
#[unsafe(no_mangle)]
pub extern "C" fn ail_voice_budget() -> u32 {
    AIL.read()
        .last_report()
        .map_or(48, |r| r.voice_efficiency.budget_cap)
}

/// Get voice utilization percentage.
#[unsafe(no_mangle)]
pub extern "C" fn ail_voice_utilization_pct() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.voice_efficiency.utilization_pct)
}

/// Get voice efficiency score (0–100).
#[unsafe(no_mangle)]
pub extern "C" fn ail_voice_efficiency_score() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.voice_efficiency.efficiency_score)
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPECTRAL CLARITY
// ═══════════════════════════════════════════════════════════════════════════════

/// Get SCI advanced value.
#[unsafe(no_mangle)]
pub extern "C" fn ail_spectral_sci() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.spectral_clarity.sci_advanced)
}

/// Get spectral clarity score (0–100).
#[unsafe(no_mangle)]
pub extern "C" fn ail_spectral_clarity_score() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.spectral_clarity.clarity_score)
}

/// Get spectral overlap count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_spectral_overlap_count() -> u32 {
    AIL.read()
        .last_report()
        .map_or(0, |r| r.spectral_clarity.overlap_count)
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOLATILITY ALIGNMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Get volatility alignment score (0–100).
#[unsafe(no_mangle)]
pub extern "C" fn ail_volatility_alignment_score() -> f64 {
    AIL.read()
        .last_report()
        .map_or(0.0, |r| r.volatility_alignment.alignment_score)
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECOMMENDATIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get recommendation count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_recommendation_count() -> u32 {
    AIL.read()
        .last_report()
        .map_or(0, |r| r.recommendations.len() as u32)
}

/// Get critical recommendation count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_critical_count() -> u32 {
    AIL.read().last_report().map_or(0, |r| r.critical_count)
}

/// Get warning recommendation count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_warning_count() -> u32 {
    AIL.read().last_report().map_or(0, |r| r.warning_count)
}

/// Get info recommendation count.
#[unsafe(no_mangle)]
pub extern "C" fn ail_info_count() -> u32 {
    AIL.read().last_report().map_or(0, |r| r.info_count)
}

/// Get recommendation impact score. Returns -1.0 if invalid index.
#[unsafe(no_mangle)]
pub extern "C" fn ail_recommendation_impact(rec_index: u32) -> f64 {
    AIL.read()
        .last_report()
        .and_then(|r| r.recommendations.get(rec_index as usize))
        .map_or(-1.0, |rec| rec.impact_score)
}

/// Get recommendation level: 0=INFO, 1=WARNING, 2=CRITICAL. Returns -1 if invalid.
#[unsafe(no_mangle)]
pub extern "C" fn ail_recommendation_level(rec_index: u32) -> i32 {
    AIL.read()
        .last_report()
        .and_then(|r| r.recommendations.get(rec_index as usize))
        .map_or(-1, |rec| rec.level as i32)
}

/// Get recommendation title. Caller must free with ail_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn ail_recommendation_title(rec_index: u32) -> *mut c_char {
    let guard = AIL.read();
    let title = match guard
        .last_report()
        .and_then(|r| r.recommendations.get(rec_index as usize))
    {
        Some(rec) => &rec.title,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(title.as_str()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get recommendation description. Caller must free with ail_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn ail_recommendation_description(rec_index: u32) -> *mut c_char {
    let guard = AIL.read();
    let desc = match guard
        .last_report()
        .and_then(|r| r.recommendations.get(rec_index as usize))
    {
        Some(rec) => &rec.description,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(desc.as_str()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get recommendation domain index.
#[unsafe(no_mangle)]
pub extern "C" fn ail_recommendation_domain(rec_index: u32) -> i32 {
    AIL.read()
        .last_report()
        .and_then(|r| r.recommendations.get(rec_index as usize))
        .map_or(-1, |rec| rec.domain as i32)
}

// ═══════════════════════════════════════════════════════════════════════════════
// JSON OUTPUT
// ═══════════════════════════════════════════════════════════════════════════════

/// Get full AIL report as JSON. Caller must free with ail_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn ail_report_json() -> *mut c_char {
    if let Ok(json) = AIL.read().report_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by ail_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn ail_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

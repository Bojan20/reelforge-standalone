//! Advanced Metering FFI
//!
//! Exposes SIMD-optimized metering and psychoacoustic analysis to Flutter:
//! - 8x oversampling True Peak (superior to ITU 4x)
//! - PSR (Peak-to-Short-term Ratio)
//! - Crest Factor
//! - Zwicker Loudness (ISO 532-1)
//! - Sharpness, Roughness, Fluctuation

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use rf_dsp::metering_simd::{TruePeak8x, PsrMeter, CrestFactorMeter};
use rf_dsp::loudness_advanced::PsychoacousticMeter;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL ADVANCED METERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Global 8x True Peak meter
static TRUE_PEAK_8X: Lazy<RwLock<Option<TruePeak8x>>> = Lazy::new(|| RwLock::new(None));

/// Global PSR meter
static PSR_METER: Lazy<RwLock<Option<PsrMeter>>> = Lazy::new(|| RwLock::new(None));

/// Global Crest Factor meter
static CREST_METER: Lazy<RwLock<Option<CrestFactorMeter>>> = Lazy::new(|| RwLock::new(None));

/// Global Psychoacoustic meter (Zwicker + Sharpness + Roughness + Fluctuation)
static PSYCHOACOUSTIC: Lazy<RwLock<Option<PsychoacousticMeter>>> = Lazy::new(|| RwLock::new(None));

// ═══════════════════════════════════════════════════════════════════════════════
// DATA TRANSFER STRUCTS
// ═══════════════════════════════════════════════════════════════════════════════

/// 8x True Peak data for Flutter
#[derive(Debug, Clone, Default)]
pub struct TruePeak8xData {
    /// Current peak in dBTP
    pub peak_dbtp: f64,
    /// Maximum peak in dBTP
    pub max_dbtp: f64,
    /// Held peak in dBTP
    pub hold_dbtp: f64,
    /// Is clipping (> 0 dBTP)
    pub is_clipping: bool,
}

/// PSR data for Flutter
#[derive(Debug, Clone, Default)]
pub struct PsrData {
    /// Peak-to-Short-term Ratio in dB
    pub psr_db: f64,
    /// Short-term LUFS
    pub short_term_lufs: f64,
    /// True Peak in dBTP
    pub true_peak_dbtp: f64,
    /// Dynamic assessment string
    pub assessment: String,
}

/// Crest Factor data for Flutter
#[derive(Debug, Clone, Default)]
pub struct CrestFactorData {
    /// Crest factor in dB
    pub crest_db: f64,
    /// Crest factor as ratio (e.g., 1.414 for sine)
    pub crest_ratio: f64,
    /// Signal type assessment
    pub assessment: String,
}

/// Psychoacoustic data for Flutter
#[derive(Debug, Clone, Default)]
pub struct PsychoacousticData {
    /// Total loudness in sones (ISO 532-1)
    pub loudness_sones: f64,
    /// Loudness level in phons
    pub loudness_phons: f64,
    /// Sharpness in acum
    pub sharpness_acum: f64,
    /// Fluctuation strength in vacil
    pub fluctuation_vacil: f64,
    /// Roughness in asper
    pub roughness_asper: f64,
    /// Specific loudness per critical band (24 bands)
    pub specific_loudness: Vec<f64>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize all advanced meters
pub fn init_advanced_meters(sample_rate: f64) {
    *TRUE_PEAK_8X.write() = Some(TruePeak8x::new(sample_rate));
    *PSR_METER.write() = Some(PsrMeter::new(sample_rate));
    *CREST_METER.write() = Some(CrestFactorMeter::new(sample_rate, 300.0)); // 300ms window
    *PSYCHOACOUSTIC.write() = Some(PsychoacousticMeter::new(sample_rate));

    log::info!("Advanced meters initialized @ {} Hz", sample_rate);
}

/// Reset all advanced meters
pub fn reset_advanced_meters() {
    if let Some(meter) = TRUE_PEAK_8X.write().as_mut() {
        meter.reset();
    }
    if let Some(meter) = PSR_METER.write().as_mut() {
        meter.reset();
    }
    if let Some(meter) = PSYCHOACOUSTIC.write().as_mut() {
        meter.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROCESSING (called from audio thread)
// ═══════════════════════════════════════════════════════════════════════════════

/// Process stereo block through all advanced meters
/// Call this from the audio callback with the master bus output
pub fn process_advanced_meters(left: &[f64], right: &[f64]) {
    // 8x True Peak
    if let Some(meter) = TRUE_PEAK_8X.write().as_mut() {
        meter.process_block(left, right);
    }

    // Crest Factor (mono sum)
    if let Some(meter) = CREST_METER.write().as_mut() {
        for (&l, &r) in left.iter().zip(right.iter()) {
            meter.process((l + r) * 0.5);
        }
    }

    // Psychoacoustic (mono sum)
    if let Some(meter) = PSYCHOACOUSTIC.write().as_mut() {
        for (&l, &r) in left.iter().zip(right.iter()) {
            meter.process((l + r) * 0.5);
        }
    }
}

/// Process PSR meter (needs K-weighted AND raw signal)
pub fn process_psr_meter(
    k_left: &[f64],
    k_right: &[f64],
    raw_left: &[f64],
    raw_right: &[f64]
) {
    if let Some(meter) = PSR_METER.write().as_mut() {
        for i in 0..k_left.len().min(raw_left.len()) {
            meter.process(k_left[i], k_right[i], raw_left[i], raw_right[i]);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FFI GETTERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get 8x True Peak data
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_get_true_peak_8x() -> TruePeak8xData {
    if let Some(meter) = TRUE_PEAK_8X.read().as_ref() {
        TruePeak8xData {
            peak_dbtp: meter.peak_dbtp(),
            max_dbtp: meter.max_dbtp(),
            hold_dbtp: meter.hold_dbtp(),
            is_clipping: meter.is_clipping(),
        }
    } else {
        TruePeak8xData::default()
    }
}

/// Get PSR (Peak-to-Short-term Ratio) data
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_get_psr() -> PsrData {
    if let Some(meter) = PSR_METER.read().as_ref() {
        PsrData {
            psr_db: meter.psr(),
            short_term_lufs: meter.short_term_lufs(),
            true_peak_dbtp: meter.psr(), // Uses internal true peak
            assessment: meter.dynamic_assessment().to_string(),
        }
    } else {
        PsrData::default()
    }
}

/// Get Crest Factor data
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_get_crest_factor() -> CrestFactorData {
    if let Some(meter) = CREST_METER.read().as_ref() {
        let crest_db = meter.crest_factor_db();
        let assessment = if crest_db < 6.0 {
            "Over-limited"
        } else if crest_db < 10.0 {
            "Heavily Compressed"
        } else if crest_db < 14.0 {
            "Moderate Dynamics"
        } else if crest_db < 18.0 {
            "Natural Dynamics"
        } else {
            "High Dynamics"
        };

        CrestFactorData {
            crest_db,
            crest_ratio: meter.crest_factor_ratio(),
            assessment: assessment.to_string(),
        }
    } else {
        CrestFactorData::default()
    }
}

/// Get Psychoacoustic data (Zwicker loudness + sharpness + roughness)
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_get_psychoacoustic() -> PsychoacousticData {
    if let Some(meter) = PSYCHOACOUSTIC.read().as_ref() {
        PsychoacousticData {
            loudness_sones: meter.loudness.loudness_sones(),
            loudness_phons: meter.loudness.loudness_phons(),
            sharpness_acum: meter.sharpness.sharpness(),
            fluctuation_vacil: meter.fluctuation.fluctuation_strength(),
            roughness_asper: meter.roughness.roughness(),
            specific_loudness: meter.loudness.specific_loudness().to_vec(),
        }
    } else {
        PsychoacousticData::default()
    }
}

/// Get specific loudness per critical band (24 bands, Bark scale)
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_get_specific_loudness() -> Vec<f64> {
    if let Some(meter) = PSYCHOACOUSTIC.read().as_ref() {
        meter.loudness.specific_loudness().to_vec()
    } else {
        vec![0.0; 24]
    }
}

/// Reset 8x True Peak meter
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_reset_true_peak() {
    if let Some(meter) = TRUE_PEAK_8X.write().as_mut() {
        meter.reset();
    }
}

/// Reset PSR meter
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_reset_psr() {
    if let Some(meter) = PSR_METER.write().as_mut() {
        meter.reset();
    }
}

/// Reset all advanced meters
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_reset_all() {
    reset_advanced_meters();
}

/// Check if advanced meters are initialized
#[flutter_rust_bridge::frb(sync)]
pub fn advanced_is_initialized() -> bool {
    TRUE_PEAK_8X.read().is_some()
}

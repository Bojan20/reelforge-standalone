use serde::{Deserialize, Serialize};

/// Concrete fatigue thresholds with evidence-based defaults.
///
/// References:
/// - ISO 389-0: Reference equivalent threshold sound pressure levels
/// - ITU-R BS.1770-4: Loudness measurement
/// - AES/EBU R128: Loudness normalization
/// - WHO guidelines: Safe listening levels (85 dBA, 8h equivalent)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FatigueThresholds {
    /// RMS average threshold before HF regulation starts (dB).
    /// Based on -12 dBFS as sustained exposure reference.
    pub rms_avg_db: f64,

    /// Cumulative HF energy threshold (dB·s).
    /// 8kHz+ band RMS integrated over time.
    /// 120 dB·s ≈ -12dB sustained for 10 seconds at 8kHz+.
    pub hf_cumulative_db_s: f64,

    /// Transient density threshold (events per minute).
    /// >15 sharp transients/min is fatiguing per audiology research.
    pub transient_per_min: f64,

    /// Stereo width time-on threshold (minutes).
    /// Extended wide stereo causes listener fatigue after ~20 min.
    pub stereo_time_on_min: f64,
}

impl Default for FatigueThresholds {
    fn default() -> Self {
        Self {
            rms_avg_db: -12.0,
            hf_cumulative_db_s: 120.0,
            transient_per_min: 15.0,
            stereo_time_on_min: 20.0,
        }
    }
}

impl FatigueThresholds {
    /// Conservative thresholds for regulated markets (UK, Australia).
    pub fn conservative() -> Self {
        Self {
            rms_avg_db: -15.0,
            hf_cumulative_db_s: 80.0,
            transient_per_min: 10.0,
            stereo_time_on_min: 15.0,
        }
    }

    /// Relaxed thresholds for desktop/cabinet with lower fatigue risk.
    pub fn relaxed() -> Self {
        Self {
            rms_avg_db: -9.0,
            hf_cumulative_db_s: 180.0,
            transient_per_min: 25.0,
            stereo_time_on_min: 30.0,
        }
    }
}

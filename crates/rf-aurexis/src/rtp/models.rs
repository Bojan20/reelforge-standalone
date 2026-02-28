use serde::{Deserialize, Serialize};

/// Pacing curve describing the temporal envelope of audio intensity.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PacingCurve {
    /// Time to reach peak intensity (ms).
    pub build_time_ms: f64,
    /// Time peak holds before release (ms).
    pub hold_time_ms: f64,
    /// Time to decay from peak (ms).
    pub release_time_ms: f64,
    /// Micro-spike frequency (Hz). Higher = more frequent small intensity bumps.
    pub spike_rate_hz: f64,
    /// Peak elasticity: how much the peak can overshoot (1.0 = no overshoot).
    pub peak_elasticity: f64,
}

impl Default for PacingCurve {
    fn default() -> Self {
        Self {
            build_time_ms: 1500.0,
            hold_time_ms: 800.0,
            release_time_ms: 1200.0,
            spike_rate_hz: 2.0,
            peak_elasticity: 1.2,
        }
    }
}

/// Named RTP profile with its pacing characteristics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpProfile {
    pub name: String,
    pub rtp_range: (f64, f64),
    pub pacing: PacingCurve,
}

impl RtpProfile {
    /// High RTP (97-99.5%): slow build, fewer spikes, less aggressive.
    pub fn high_rtp() -> Self {
        Self {
            name: "High RTP".into(),
            rtp_range: (97.0, 99.5),
            pacing: PacingCurve {
                build_time_ms: 3000.0,
                hold_time_ms: 1200.0,
                release_time_ms: 2000.0,
                spike_rate_hz: 0.8,
                peak_elasticity: 1.1,
            },
        }
    }

    /// Medium RTP (93-97%): balanced pacing.
    pub fn medium_rtp() -> Self {
        Self {
            name: "Medium RTP".into(),
            rtp_range: (93.0, 97.0),
            pacing: PacingCurve::default(),
        }
    }

    /// Low RTP (85-93%): fast build, frequent spikes, aggressive.
    pub fn low_rtp() -> Self {
        Self {
            name: "Low RTP".into(),
            rtp_range: (85.0, 93.0),
            pacing: PacingCurve {
                build_time_ms: 500.0,
                hold_time_ms: 400.0,
                release_time_ms: 600.0,
                spike_rate_hz: 5.0,
                peak_elasticity: 1.8,
            },
        }
    }
}

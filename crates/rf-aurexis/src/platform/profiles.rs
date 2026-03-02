use crate::core::config::PlatformType;
use serde::{Deserialize, Serialize};

/// Platform-specific audio profile with concrete coefficients.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlatformProfile {
    pub platform: PlatformType,
    pub name: String,
    /// Stereo range factor. 1.0 = full, 0.6 = compressed for mobile.
    pub stereo_range_factor: f64,
    /// Mono safety boost. 1.0 = no boost, 1.2 = center boost +1.6dB.
    pub mono_safety_level: f64,
    /// Depth compression. 1.0 = full depth, 0.4 = collapsed to 2D.
    pub depth_compression: f64,
    /// Headroom reduction in dB. 0.0 = none, -2.0 = 2dB headroom.
    pub headroom_reduction_db: f64,
    /// HF roll-off frequency. 20000 = no roll-off, 8000 = mobile speaker sim.
    pub hf_rolloff_hz: f64,
    /// LF roll-off frequency. 20 = full range, 300 = phone speaker.
    pub lf_rolloff_hz: f64,
}

impl PlatformProfile {
    /// Desktop: full range, no restrictions.
    pub fn desktop() -> Self {
        Self {
            platform: PlatformType::Desktop,
            name: "Desktop".into(),
            stereo_range_factor: 1.0,
            mono_safety_level: 1.0,
            depth_compression: 1.0,
            headroom_reduction_db: 0.0,
            hf_rolloff_hz: 20000.0,
            lf_rolloff_hz: 20.0,
        }
    }

    /// Mobile: compressed stereo, mono safety, limited bandwidth.
    pub fn mobile() -> Self {
        Self {
            platform: PlatformType::Mobile,
            name: "Mobile".into(),
            stereo_range_factor: 0.6,
            mono_safety_level: 1.2,
            depth_compression: 0.4,
            headroom_reduction_db: -2.0,
            hf_rolloff_hz: 12000.0,
            lf_rolloff_hz: 200.0,
        }
    }

    /// Headphones: enhanced width, HRTF hints, full bandwidth.
    pub fn headphones() -> Self {
        Self {
            platform: PlatformType::Headphones,
            name: "Headphones".into(),
            stereo_range_factor: 1.3,
            mono_safety_level: 0.9,
            depth_compression: 1.2,
            headroom_reduction_db: -1.0,
            hf_rolloff_hz: 20000.0,
            lf_rolloff_hz: 20.0,
        }
    }

    /// Cabinet: mono-safe, bass-managed, limited bandwidth.
    pub fn cabinet() -> Self {
        Self {
            platform: PlatformType::Cabinet,
            name: "Cabinet".into(),
            stereo_range_factor: 0.4,
            mono_safety_level: 1.3,
            depth_compression: 0.3,
            headroom_reduction_db: -3.0,
            hf_rolloff_hz: 10000.0,
            lf_rolloff_hz: 250.0,
        }
    }

    /// Get profile for platform type.
    pub fn for_platform(platform: PlatformType) -> Self {
        match platform {
            PlatformType::Desktop => Self::desktop(),
            PlatformType::Mobile => Self::mobile(),
            PlatformType::Headphones => Self::headphones(),
            PlatformType::Cabinet => Self::cabinet(),
        }
    }
}

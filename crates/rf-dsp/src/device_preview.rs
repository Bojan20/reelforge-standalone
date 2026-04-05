//! Device Preview Engine — Post-master monitoring-only DSP chain
//!
//! 8-node pipeline: PreGain → HPF → TonalEQ → StereoProcessor → MultibandDRC → Limiter → Distortion → EnvironmentalOverlay
//!
//! NEVER in exports. ≤0.7ms latency, <3% CPU Apple Silicon.
//! Audio thread: process() with pre-computed coefficients. Zero locking.
//! UI thread: loads profiles + computes coefficients + atomic flag.

use crate::biquad::{BiquadCoeffs, BiquadTDF2};
use crate::{MonoProcessor, Processor};
use rf_core::Sample;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

// ═══════════════════════════════════════════════════════════════════════════
// DEVICE PROFILE DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Frequency response point for device modeling
#[derive(Debug, Clone, Copy)]
pub struct FrPoint {
    pub freq: f64,
    pub gain_db: f64,
}

/// Device profile category
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum DeviceCategory {
    Smartphone = 0,
    Headphone = 1,
    LaptopTablet = 2,
    TvSoundbar = 3,
    BtSpeaker = 4,
    ReferenceMonitor = 5,
    CasinoEnvironment = 6,
    Custom = 7,
}

/// Stereo processing mode for device simulation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeviceStereoMode {
    /// Full stereo (headphones, monitors)
    Stereo,
    /// Narrowed stereo field (phone speakers, small BT)
    Narrowed(u8), // width percentage 0-100
    /// Mono (single speaker devices)
    Mono,
}

/// Distortion model for speaker simulation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DistortionModel {
    /// No distortion (reference monitors, headphones)
    None,
    /// Soft clip (typical small speakers at high volume)
    SoftClip,
    /// Hard clip (phone speakers pushed to max)
    HardClip,
    /// Speaker breakup (BT speakers, TV speakers)
    SpeakerBreakup,
}

/// Complete device profile — all data needed to simulate a device
#[derive(Debug, Clone)]
pub struct DeviceProfile {
    pub id: u16,
    pub name: &'static str,
    pub category: DeviceCategory,
    /// Frequency response curve (10 points typical)
    pub fr_curve: &'static [FrPoint],
    /// High-pass filter cutoff (Hz) — speaker low-frequency rolloff
    pub hpf_freq: f64,
    /// HPF Q factor
    pub hpf_q: f64,
    /// Maximum SPL (dBFS) — headroom before distortion
    pub max_spl_dbfs: f64,
    /// DRC amount (0.0 = none, 1.0 = full)
    pub drc_amount: f64,
    /// DRC threshold (dBFS)
    pub drc_threshold: f64,
    /// Stereo processing mode
    pub stereo_mode: DeviceStereoMode,
    /// Bass management: redirect below this freq to enhance perceived bass
    pub bass_enhance_freq: f64,
    /// Limiter ceiling (dBFS)
    pub limiter_ceiling: f64,
    /// Distortion model
    pub distortion: DistortionModel,
    /// Distortion drive amount (0.0-1.0)
    pub distortion_drive: f64,
    /// Environmental noise floor (dBFS, negative)
    pub env_noise_floor: f64,
}

// ═══════════════════════════════════════════════════════════════════════════
// 50 DEVICE PROFILES
// ═══════════════════════════════════════════════════════════════════════════

/// All built-in device profiles (50 total)
pub static DEVICE_PROFILES: &[DeviceProfile] = &[
    // ── SMARTPHONES (15) ──────────────────────────────────────────────
    DeviceProfile {
        id: 100,
        name: "iPhone 15 Pro Max",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -30.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -18.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -6.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -8.0,
            },
        ],
        hpf_freq: 120.0,
        hpf_q: 0.707,
        max_spl_dbfs: -6.0,
        drc_amount: 0.4,
        drc_threshold: -18.0,
        stereo_mode: DeviceStereoMode::Narrowed(40),
        bass_enhance_freq: 150.0,
        limiter_ceiling: -3.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.15,
        env_noise_floor: -60.0,
    },
    DeviceProfile {
        id: 101,
        name: "iPhone 14",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -32.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -20.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -8.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -10.0,
            },
        ],
        hpf_freq: 140.0,
        hpf_q: 0.707,
        max_spl_dbfs: -8.0,
        drc_amount: 0.45,
        drc_threshold: -20.0,
        stereo_mode: DeviceStereoMode::Narrowed(35),
        bass_enhance_freq: 160.0,
        limiter_ceiling: -3.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.18,
        env_noise_floor: -58.0,
    },
    DeviceProfile {
        id: 102,
        name: "Samsung Galaxy S24 Ultra",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -28.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -16.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -7.0,
            },
        ],
        hpf_freq: 110.0,
        hpf_q: 0.707,
        max_spl_dbfs: -5.0,
        drc_amount: 0.35,
        drc_threshold: -16.0,
        stereo_mode: DeviceStereoMode::Narrowed(45),
        bass_enhance_freq: 140.0,
        limiter_ceiling: -2.5,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.12,
        env_noise_floor: -62.0,
    },
    DeviceProfile {
        id: 103,
        name: "Samsung Galaxy A54",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -35.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -24.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -6.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -14.0,
            },
        ],
        hpf_freq: 180.0,
        hpf_q: 0.707,
        max_spl_dbfs: -10.0,
        drc_amount: 0.5,
        drc_threshold: -22.0,
        stereo_mode: DeviceStereoMode::Narrowed(25),
        bass_enhance_freq: 200.0,
        limiter_ceiling: -4.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.25,
        env_noise_floor: -55.0,
    },
    DeviceProfile {
        id: 104,
        name: "Google Pixel 8 Pro",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -30.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -19.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -7.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -2.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -9.0,
            },
        ],
        hpf_freq: 130.0,
        hpf_q: 0.707,
        max_spl_dbfs: -7.0,
        drc_amount: 0.4,
        drc_threshold: -18.0,
        stereo_mode: DeviceStereoMode::Narrowed(38),
        bass_enhance_freq: 155.0,
        limiter_ceiling: -3.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.16,
        env_noise_floor: -59.0,
    },
    DeviceProfile {
        id: 105,
        name: "Xiaomi 14 Ultra",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -26.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -15.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 4.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -1.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -6.0,
            },
        ],
        hpf_freq: 100.0,
        hpf_q: 0.707,
        max_spl_dbfs: -4.0,
        drc_amount: 0.3,
        drc_threshold: -15.0,
        stereo_mode: DeviceStereoMode::Narrowed(50),
        bass_enhance_freq: 130.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.1,
        env_noise_floor: -64.0,
    },
    DeviceProfile {
        id: 106,
        name: "OnePlus 12",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -29.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -17.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -6.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -8.0,
            },
        ],
        hpf_freq: 125.0,
        hpf_q: 0.707,
        max_spl_dbfs: -6.0,
        drc_amount: 0.38,
        drc_threshold: -17.0,
        stereo_mode: DeviceStereoMode::Narrowed(42),
        bass_enhance_freq: 145.0,
        limiter_ceiling: -3.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.14,
        env_noise_floor: -61.0,
    },
    DeviceProfile {
        id: 107,
        name: "iPhone SE (budget)",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -36.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -26.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -12.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -7.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -15.0,
            },
        ],
        hpf_freq: 200.0,
        hpf_q: 0.707,
        max_spl_dbfs: -12.0,
        drc_amount: 0.55,
        drc_threshold: -24.0,
        stereo_mode: DeviceStereoMode::Mono,
        bass_enhance_freq: 220.0,
        limiter_ceiling: -5.0,
        distortion: DistortionModel::HardClip,
        distortion_drive: 0.3,
        env_noise_floor: -52.0,
    },
    DeviceProfile {
        id: 108,
        name: "Huawei Mate 60 Pro",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -27.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -16.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -5.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -7.0,
            },
        ],
        hpf_freq: 115.0,
        hpf_q: 0.707,
        max_spl_dbfs: -5.0,
        drc_amount: 0.35,
        drc_threshold: -16.0,
        stereo_mode: DeviceStereoMode::Narrowed(48),
        bass_enhance_freq: 135.0,
        limiter_ceiling: -2.5,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.12,
        env_noise_floor: -63.0,
    },
    DeviceProfile {
        id: 109,
        name: "Sony Xperia 1 VI",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -25.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -14.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 95.0,
        hpf_q: 0.707,
        max_spl_dbfs: -3.0,
        drc_amount: 0.25,
        drc_threshold: -14.0,
        stereo_mode: DeviceStereoMode::Narrowed(55),
        bass_enhance_freq: 120.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.08,
        env_noise_floor: -66.0,
    },
    DeviceProfile {
        id: 110,
        name: "Budget Android (generic)",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -40.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -30.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -15.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -6.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -20.0,
            },
        ],
        hpf_freq: 250.0,
        hpf_q: 0.707,
        max_spl_dbfs: -14.0,
        drc_amount: 0.6,
        drc_threshold: -26.0,
        stereo_mode: DeviceStereoMode::Mono,
        bass_enhance_freq: 280.0,
        limiter_ceiling: -6.0,
        distortion: DistortionModel::HardClip,
        distortion_drive: 0.35,
        env_noise_floor: -48.0,
    },
    DeviceProfile {
        id: 111,
        name: "iPad Pro 12.9\"",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -22.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 80.0,
        hpf_q: 0.707,
        max_spl_dbfs: -2.0,
        drc_amount: 0.2,
        drc_threshold: -12.0,
        stereo_mode: DeviceStereoMode::Narrowed(60),
        bass_enhance_freq: 100.0,
        limiter_ceiling: -1.5,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.06,
        env_noise_floor: -68.0,
    },
    DeviceProfile {
        id: 112,
        name: "Samsung Galaxy Tab S9",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -24.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -12.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -6.0,
            },
        ],
        hpf_freq: 90.0,
        hpf_q: 0.707,
        max_spl_dbfs: -3.0,
        drc_amount: 0.25,
        drc_threshold: -14.0,
        stereo_mode: DeviceStereoMode::Narrowed(55),
        bass_enhance_freq: 110.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.08,
        env_noise_floor: -65.0,
    },
    DeviceProfile {
        id: 113,
        name: "Nothing Phone 2",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -31.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -20.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -8.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -11.0,
            },
        ],
        hpf_freq: 150.0,
        hpf_q: 0.707,
        max_spl_dbfs: -9.0,
        drc_amount: 0.42,
        drc_threshold: -20.0,
        stereo_mode: DeviceStereoMode::Narrowed(32),
        bass_enhance_freq: 170.0,
        limiter_ceiling: -3.5,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.2,
        env_noise_floor: -56.0,
    },
    DeviceProfile {
        id: 114,
        name: "Motorola Edge 40",
        category: DeviceCategory::Smartphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -33.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -22.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -9.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -3.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -12.0,
            },
        ],
        hpf_freq: 160.0,
        hpf_q: 0.707,
        max_spl_dbfs: -10.0,
        drc_amount: 0.48,
        drc_threshold: -21.0,
        stereo_mode: DeviceStereoMode::Narrowed(30),
        bass_enhance_freq: 180.0,
        limiter_ceiling: -4.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.22,
        env_noise_floor: -54.0,
    },
    // ── HEADPHONES (9) ────────────────────────────────────────────────
    DeviceProfile {
        id: 200,
        name: "Sony WH-1000XM5",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -4.0,
            },
        ],
        hpf_freq: 15.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.3,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -90.0,
    },
    DeviceProfile {
        id: 201,
        name: "Apple AirPods Pro 2",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 18.0,
        hpf_q: 0.707,
        max_spl_dbfs: -1.0,
        drc_amount: 0.05,
        drc_threshold: -3.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.5,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -85.0,
    },
    DeviceProfile {
        id: 202,
        name: "AKG K712 Pro",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -2.0,
            },
        ],
        hpf_freq: 10.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -96.0,
    },
    DeviceProfile {
        id: 203,
        name: "Beyerdynamic DT 770 Pro",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -3.0,
            },
        ],
        hpf_freq: 10.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -94.0,
    },
    DeviceProfile {
        id: 204,
        name: "Audio-Technica ATH-M50x",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -4.0,
            },
        ],
        hpf_freq: 12.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -92.0,
    },
    DeviceProfile {
        id: 205,
        name: "Sennheiser HD 600",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -4.0,
            },
        ],
        hpf_freq: 12.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -95.0,
    },
    DeviceProfile {
        id: 206,
        name: "Samsung Galaxy Buds2 Pro",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -6.0,
            },
        ],
        hpf_freq: 20.0,
        hpf_q: 0.707,
        max_spl_dbfs: -1.0,
        drc_amount: 0.05,
        drc_threshold: -3.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.5,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -82.0,
    },
    DeviceProfile {
        id: 207,
        name: "Cheap Earbuds (generic)",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -8.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 4.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 5.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -8.0,
            },
        ],
        hpf_freq: 30.0,
        hpf_q: 0.707,
        max_spl_dbfs: -3.0,
        drc_amount: 0.1,
        drc_threshold: -6.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -1.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.05,
        env_noise_floor: -72.0,
    },
    DeviceProfile {
        id: 208,
        name: "Bose QuietComfort Ultra",
        category: DeviceCategory::Headphone,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 14.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.3,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -88.0,
    },
    // ── LAPTOP / TABLET (6) ──────────────────────────────────────────
    DeviceProfile {
        id: 300,
        name: "MacBook Pro 16\" (2024)",
        category: DeviceCategory::LaptopTablet,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -15.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 60.0,
        hpf_q: 0.707,
        max_spl_dbfs: -1.0,
        drc_amount: 0.15,
        drc_threshold: -10.0,
        stereo_mode: DeviceStereoMode::Narrowed(70),
        bass_enhance_freq: 80.0,
        limiter_ceiling: -1.0,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -72.0,
    },
    DeviceProfile {
        id: 301,
        name: "MacBook Air 13\"",
        category: DeviceCategory::LaptopTablet,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -22.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -7.0,
            },
        ],
        hpf_freq: 100.0,
        hpf_q: 0.707,
        max_spl_dbfs: -4.0,
        drc_amount: 0.25,
        drc_threshold: -14.0,
        stereo_mode: DeviceStereoMode::Narrowed(55),
        bass_enhance_freq: 120.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.05,
        env_noise_floor: -68.0,
    },
    DeviceProfile {
        id: 302,
        name: "Dell XPS 15",
        category: DeviceCategory::LaptopTablet,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -20.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -9.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -6.0,
            },
        ],
        hpf_freq: 85.0,
        hpf_q: 0.707,
        max_spl_dbfs: -3.0,
        drc_amount: 0.2,
        drc_threshold: -12.0,
        stereo_mode: DeviceStereoMode::Narrowed(60),
        bass_enhance_freq: 105.0,
        limiter_ceiling: -1.5,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -70.0,
    },
    DeviceProfile {
        id: 303,
        name: "ThinkPad X1 Carbon",
        category: DeviceCategory::LaptopTablet,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -25.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -14.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -9.0,
            },
        ],
        hpf_freq: 120.0,
        hpf_q: 0.707,
        max_spl_dbfs: -6.0,
        drc_amount: 0.3,
        drc_threshold: -16.0,
        stereo_mode: DeviceStereoMode::Narrowed(45),
        bass_enhance_freq: 140.0,
        limiter_ceiling: -3.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.08,
        env_noise_floor: -65.0,
    },
    DeviceProfile {
        id: 304,
        name: "Surface Pro 10",
        category: DeviceCategory::LaptopTablet,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -23.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -12.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -7.0,
            },
        ],
        hpf_freq: 95.0,
        hpf_q: 0.707,
        max_spl_dbfs: -4.0,
        drc_amount: 0.22,
        drc_threshold: -13.0,
        stereo_mode: DeviceStereoMode::Narrowed(52),
        bass_enhance_freq: 115.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.04,
        env_noise_floor: -67.0,
    },
    DeviceProfile {
        id: 305,
        name: "Chromebook (generic)",
        category: DeviceCategory::LaptopTablet,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -30.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -20.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -8.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -7.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -14.0,
            },
        ],
        hpf_freq: 160.0,
        hpf_q: 0.707,
        max_spl_dbfs: -10.0,
        drc_amount: 0.45,
        drc_threshold: -20.0,
        stereo_mode: DeviceStereoMode::Narrowed(30),
        bass_enhance_freq: 180.0,
        limiter_ceiling: -4.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.2,
        env_noise_floor: -55.0,
    },
    // ── TV / SOUNDBAR (6) ─────────────────────────────────────────────
    DeviceProfile {
        id: 400,
        name: "Samsung Soundbar Q990C",
        category: DeviceCategory::TvSoundbar,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -4.0,
            },
        ],
        hpf_freq: 35.0,
        hpf_q: 0.707,
        max_spl_dbfs: -1.0,
        drc_amount: 0.15,
        drc_threshold: -10.0,
        stereo_mode: DeviceStereoMode::Narrowed(75),
        bass_enhance_freq: 60.0,
        limiter_ceiling: -1.0,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -70.0,
    },
    DeviceProfile {
        id: 401,
        name: "Sonos Arc",
        category: DeviceCategory::TvSoundbar,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -8.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 45.0,
        hpf_q: 0.707,
        max_spl_dbfs: -1.5,
        drc_amount: 0.1,
        drc_threshold: -8.0,
        stereo_mode: DeviceStereoMode::Narrowed(80),
        bass_enhance_freq: 65.0,
        limiter_ceiling: -1.0,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -72.0,
    },
    DeviceProfile {
        id: 402,
        name: "LG OLED TV (built-in)",
        category: DeviceCategory::TvSoundbar,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -25.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -12.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -7.0,
            },
        ],
        hpf_freq: 100.0,
        hpf_q: 0.707,
        max_spl_dbfs: -6.0,
        drc_amount: 0.35,
        drc_threshold: -16.0,
        stereo_mode: DeviceStereoMode::Narrowed(50),
        bass_enhance_freq: 120.0,
        limiter_ceiling: -3.0,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.1,
        env_noise_floor: -62.0,
    },
    DeviceProfile {
        id: 403,
        name: "Samsung TV (built-in)",
        category: DeviceCategory::TvSoundbar,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -28.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -15.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.5,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -9.0,
            },
        ],
        hpf_freq: 120.0,
        hpf_q: 0.707,
        max_spl_dbfs: -7.0,
        drc_amount: 0.38,
        drc_threshold: -18.0,
        stereo_mode: DeviceStereoMode::Narrowed(45),
        bass_enhance_freq: 140.0,
        limiter_ceiling: -3.5,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.12,
        env_noise_floor: -60.0,
    },
    DeviceProfile {
        id: 404,
        name: "Bose Soundbar 600",
        category: DeviceCategory::TvSoundbar,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 50.0,
        hpf_q: 0.707,
        max_spl_dbfs: -2.0,
        drc_amount: 0.12,
        drc_threshold: -8.0,
        stereo_mode: DeviceStereoMode::Narrowed(70),
        bass_enhance_freq: 70.0,
        limiter_ceiling: -1.0,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -70.0,
    },
    DeviceProfile {
        id: 405,
        name: "Budget Soundbar (generic)",
        category: DeviceCategory::TvSoundbar,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -20.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -8.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -10.0,
            },
        ],
        hpf_freq: 80.0,
        hpf_q: 0.707,
        max_spl_dbfs: -5.0,
        drc_amount: 0.3,
        drc_threshold: -14.0,
        stereo_mode: DeviceStereoMode::Narrowed(55),
        bass_enhance_freq: 100.0,
        limiter_ceiling: -2.5,
        distortion: DistortionModel::SoftClip,
        distortion_drive: 0.08,
        env_noise_floor: -60.0,
    },
    // ── BT SPEAKERS (5) ──────────────────────────────────────────────
    DeviceProfile {
        id: 500,
        name: "JBL Charge 5",
        category: DeviceCategory::BtSpeaker,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -18.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -8.0,
            },
        ],
        hpf_freq: 65.0,
        hpf_q: 0.707,
        max_spl_dbfs: -3.0,
        drc_amount: 0.3,
        drc_threshold: -14.0,
        stereo_mode: DeviceStereoMode::Mono,
        bass_enhance_freq: 85.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SpeakerBreakup,
        distortion_drive: 0.1,
        env_noise_floor: -60.0,
    },
    DeviceProfile {
        id: 501,
        name: "Marshall Stanmore III",
        category: DeviceCategory::BtSpeaker,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -6.0,
            },
        ],
        hpf_freq: 45.0,
        hpf_q: 0.707,
        max_spl_dbfs: -1.0,
        drc_amount: 0.15,
        drc_threshold: -10.0,
        stereo_mode: DeviceStereoMode::Narrowed(65),
        bass_enhance_freq: 60.0,
        limiter_ceiling: -1.0,
        distortion: DistortionModel::SpeakerBreakup,
        distortion_drive: 0.06,
        env_noise_floor: -68.0,
    },
    DeviceProfile {
        id: 502,
        name: "UE Boom 3",
        category: DeviceCategory::BtSpeaker,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -20.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -7.0,
            },
        ],
        hpf_freq: 80.0,
        hpf_q: 0.707,
        max_spl_dbfs: -4.0,
        drc_amount: 0.3,
        drc_threshold: -15.0,
        stereo_mode: DeviceStereoMode::Mono,
        bass_enhance_freq: 100.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SpeakerBreakup,
        distortion_drive: 0.12,
        env_noise_floor: -58.0,
    },
    DeviceProfile {
        id: 503,
        name: "Sonos One",
        category: DeviceCategory::BtSpeaker,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -12.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -5.0,
            },
        ],
        hpf_freq: 55.0,
        hpf_q: 0.707,
        max_spl_dbfs: -2.0,
        drc_amount: 0.12,
        drc_threshold: -8.0,
        stereo_mode: DeviceStereoMode::Mono,
        bass_enhance_freq: 70.0,
        limiter_ceiling: -1.0,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -72.0,
    },
    DeviceProfile {
        id: 504,
        name: "Mini BT Speaker (generic)",
        category: DeviceCategory::BtSpeaker,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -35.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -18.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -12.0,
            },
        ],
        hpf_freq: 150.0,
        hpf_q: 0.707,
        max_spl_dbfs: -10.0,
        drc_amount: 0.5,
        drc_threshold: -22.0,
        stereo_mode: DeviceStereoMode::Mono,
        bass_enhance_freq: 180.0,
        limiter_ceiling: -4.0,
        distortion: DistortionModel::HardClip,
        distortion_drive: 0.3,
        env_noise_floor: -50.0,
    },
    // ── REFERENCE MONITORS (5) ───────────────────────────────────────
    DeviceProfile {
        id: 600,
        name: "Genelec 8341A",
        category: DeviceCategory::ReferenceMonitor,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -1.0,
            },
        ],
        hpf_freq: 10.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -96.0,
    },
    DeviceProfile {
        id: 601,
        name: "Focal Shape 65",
        category: DeviceCategory::ReferenceMonitor,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -2.0,
            },
        ],
        hpf_freq: 15.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -94.0,
    },
    DeviceProfile {
        id: 602,
        name: "Adam Audio A7V",
        category: DeviceCategory::ReferenceMonitor,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -1.5,
            },
        ],
        hpf_freq: 12.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -93.0,
    },
    DeviceProfile {
        id: 603,
        name: "KRK Rokit 5 G4",
        category: DeviceCategory::ReferenceMonitor,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -8.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -4.0,
            },
        ],
        hpf_freq: 30.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -88.0,
    },
    DeviceProfile {
        id: 604,
        name: "Yamaha HS5",
        category: DeviceCategory::ReferenceMonitor,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -1.5,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -3.0,
            },
        ],
        hpf_freq: 25.0,
        hpf_q: 0.707,
        max_spl_dbfs: 0.0,
        drc_amount: 0.0,
        drc_threshold: 0.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.1,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -90.0,
    },
    // ── CASINO / ENVIRONMENT (4) ─────────────────────────────────────
    DeviceProfile {
        id: 700,
        name: "IGT S3000 Cabinet",
        category: DeviceCategory::CasinoEnvironment,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -20.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -6.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -8.0,
            },
        ],
        hpf_freq: 80.0,
        hpf_q: 0.707,
        max_spl_dbfs: -4.0,
        drc_amount: 0.35,
        drc_threshold: -16.0,
        stereo_mode: DeviceStereoMode::Narrowed(40),
        bass_enhance_freq: 100.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SpeakerBreakup,
        distortion_drive: 0.08,
        env_noise_floor: -45.0, // Casino floor is LOUD
    },
    DeviceProfile {
        id: 701,
        name: "Aristocrat MarsX Cabinet",
        category: DeviceCategory::CasinoEnvironment,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -18.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -0.5,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 3.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -6.0,
            },
        ],
        hpf_freq: 75.0,
        hpf_q: 0.707,
        max_spl_dbfs: -3.0,
        drc_amount: 0.3,
        drc_threshold: -14.0,
        stereo_mode: DeviceStereoMode::Narrowed(45),
        bass_enhance_freq: 90.0,
        limiter_ceiling: -2.0,
        distortion: DistortionModel::SpeakerBreakup,
        distortion_drive: 0.06,
        env_noise_floor: -45.0,
    },
    DeviceProfile {
        id: 702,
        name: "Generic Slot Cabinet",
        category: DeviceCategory::CasinoEnvironment,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -25.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: -10.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: -3.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: 1.5,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 2.5,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -10.0,
            },
        ],
        hpf_freq: 100.0,
        hpf_q: 0.707,
        max_spl_dbfs: -6.0,
        drc_amount: 0.4,
        drc_threshold: -18.0,
        stereo_mode: DeviceStereoMode::Narrowed(35),
        bass_enhance_freq: 120.0,
        limiter_ceiling: -3.0,
        distortion: DistortionModel::SpeakerBreakup,
        distortion_drive: 0.15,
        env_noise_floor: -45.0,
    },
    DeviceProfile {
        id: 703,
        name: "Casino Headphone Station",
        category: DeviceCategory::CasinoEnvironment,
        fr_curve: &[
            FrPoint {
                freq: 20.0,
                gain_db: -5.0,
            },
            FrPoint {
                freq: 80.0,
                gain_db: 3.0,
            },
            FrPoint {
                freq: 200.0,
                gain_db: 1.0,
            },
            FrPoint {
                freq: 500.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 1000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 2000.0,
                gain_db: -1.0,
            },
            FrPoint {
                freq: 4000.0,
                gain_db: 0.0,
            },
            FrPoint {
                freq: 8000.0,
                gain_db: -2.0,
            },
            FrPoint {
                freq: 12000.0,
                gain_db: -4.0,
            },
            FrPoint {
                freq: 16000.0,
                gain_db: -6.0,
            },
        ],
        hpf_freq: 25.0,
        hpf_q: 0.707,
        max_spl_dbfs: -1.0,
        drc_amount: 0.1,
        drc_threshold: -6.0,
        stereo_mode: DeviceStereoMode::Stereo,
        bass_enhance_freq: 0.0,
        limiter_ceiling: -0.5,
        distortion: DistortionModel::None,
        distortion_drive: 0.0,
        env_noise_floor: -50.0, // Ambient casino noise bleeds through
    },
];

// ═══════════════════════════════════════════════════════════════════════════
// DEVICE PREVIEW DSP CHAIN — 8 NODES
// ═══════════════════════════════════════════════════════════════════════════

/// Runtime state for the DSP chain — lives on audio thread
pub struct DevicePreviewEngine {
    sample_rate: f64,
    /// Active flag (atomic — UI can toggle without locking)
    active: AtomicBool,
    /// Current profile ID
    current_profile_id: AtomicU32,

    // Node 2: HPF state (2nd order Butterworth)
    hpf_l: BiquadTDF2,
    hpf_r: BiquadTDF2,

    // Node 3: Tonal EQ states (coeffs baked in via set_coeffs)
    tonal_l: Vec<BiquadTDF2>,
    tonal_r: Vec<BiquadTDF2>,

    // Node 5: DRC envelope followers
    drc_env_l: f64,
    drc_env_r: f64,

    // Non-filter coefficients (stereo, DRC, limiter, distortion, env)
    stereo_width: f64,
    drc_threshold: f64,
    drc_ratio: f64,
    drc_attack_coeff: f64,
    drc_release_coeff: f64,
    limiter_ceiling: f64,
    distortion_model: DistortionModel,
    distortion_drive: f64,
    env_noise_level: f64,
    pre_gain: f64,
}

impl DevicePreviewEngine {
    /// Create new engine (call from UI thread, before audio starts)
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            active: AtomicBool::new(false),
            current_profile_id: AtomicU32::new(0),
            hpf_l: BiquadTDF2::new(sample_rate),
            hpf_r: BiquadTDF2::new(sample_rate),
            tonal_l: Vec::new(),
            tonal_r: Vec::new(),
            drc_env_l: 0.0,
            drc_env_r: 0.0,
            stereo_width: 1.0,
            drc_threshold: 1.0,
            drc_ratio: 1.0,
            drc_attack_coeff: 0.0,
            drc_release_coeff: 0.0,
            limiter_ceiling: 1.0,
            distortion_model: DistortionModel::None,
            distortion_drive: 0.0,
            env_noise_level: 0.0,
            pre_gain: 1.0,
        }
    }

    /// Check if active
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::Relaxed)
    }

    /// Set active state
    pub fn set_active(&self, active: bool) {
        self.active.store(active, Ordering::Relaxed);
    }

    /// Get current profile ID (0 = no profile)
    pub fn current_profile_id(&self) -> u32 {
        self.current_profile_id.load(Ordering::Relaxed)
    }

    /// Load a device profile — computes all coefficients on caller's thread (UI thread).
    /// Bakes coefficients directly into BiquadTDF2 filter states.
    pub fn load_profile(&mut self, profile: &DeviceProfile) {
        self.current_profile_id
            .store(profile.id as u32, Ordering::Relaxed);

        // Node 1: Pre-gain (compensate for FR curve average)
        let avg_gain: f64 = profile.fr_curve.iter().map(|p| p.gain_db).sum::<f64>()
            / profile.fr_curve.len().max(1) as f64;
        self.pre_gain = db_to_linear(-avg_gain);

        // Node 2: HPF — bake coefficients into filters
        let hpf_coeffs = BiquadCoeffs::highpass(profile.hpf_freq, profile.hpf_q, self.sample_rate);
        self.hpf_l.set_coeffs(hpf_coeffs);
        self.hpf_r.set_coeffs(hpf_coeffs);
        self.hpf_l.reset();
        self.hpf_r.reset();

        // Node 3: Tonal EQ from FR curve — create peaking filters
        let tonal_coeffs: Vec<BiquadCoeffs> = profile
            .fr_curve
            .iter()
            .filter(|p| p.gain_db.abs() > 0.1) // Skip flat points
            .map(|p| BiquadCoeffs::peaking(p.freq, 1.5, p.gain_db, self.sample_rate))
            .collect();

        let num_bands = tonal_coeffs.len();
        self.tonal_l
            .resize_with(num_bands, || BiquadTDF2::new(self.sample_rate));
        self.tonal_r
            .resize_with(num_bands, || BiquadTDF2::new(self.sample_rate));
        for (i, coeffs) in tonal_coeffs.into_iter().enumerate() {
            self.tonal_l[i].set_coeffs(coeffs);
            self.tonal_r[i].set_coeffs(coeffs);
            self.tonal_l[i].reset();
            self.tonal_r[i].reset();
        }
        // Truncate if new profile has fewer bands
        self.tonal_l.truncate(num_bands);
        self.tonal_r.truncate(num_bands);

        // Node 4: Stereo width
        self.stereo_width = match profile.stereo_mode {
            DeviceStereoMode::Stereo => 1.0,
            DeviceStereoMode::Narrowed(pct) => pct as f64 / 100.0,
            DeviceStereoMode::Mono => 0.0,
        };

        // Node 5: DRC
        self.drc_ratio = 1.0 + profile.drc_amount * 3.0;
        self.drc_threshold = db_to_linear(profile.drc_threshold);
        let drc_attack_ms = 10.0;
        let drc_release_ms = 100.0;
        self.drc_attack_coeff = 1.0 - (-1.0 / (drc_attack_ms * 0.001 * self.sample_rate)).exp();
        self.drc_release_coeff = 1.0 - (-1.0 / (drc_release_ms * 0.001 * self.sample_rate)).exp();
        self.drc_env_l = 0.0;
        self.drc_env_r = 0.0;

        // Node 6: Limiter
        self.limiter_ceiling = db_to_linear(profile.limiter_ceiling);

        // Node 7: Distortion
        self.distortion_model = profile.distortion;
        self.distortion_drive = profile.distortion_drive;

        // Node 8: Environmental noise
        self.env_noise_level = db_to_linear(profile.env_noise_floor);
    }

    /// Bypass — flat response
    pub fn bypass(&mut self) {
        self.current_profile_id.store(0, Ordering::Relaxed);
        self.pre_gain = 1.0;
        self.stereo_width = 1.0;
        self.drc_threshold = 1.0;
        self.drc_ratio = 1.0;
        self.limiter_ceiling = 1.0;
        self.distortion_model = DistortionModel::None;
        self.distortion_drive = 0.0;
        self.env_noise_level = 0.0;
        self.hpf_l
            .set_coeffs(BiquadCoeffs::highpass(10.0, 0.707, self.sample_rate));
        self.hpf_r
            .set_coeffs(BiquadCoeffs::highpass(10.0, 0.707, self.sample_rate));
        self.tonal_l.clear();
        self.tonal_r.clear();
    }

    /// Process stereo buffer IN-PLACE (monitoring only, never in exports)
    ///
    /// Audio thread safe: no allocations, no locks, no panics.
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if !self.active.load(Ordering::Relaxed) {
            return;
        }

        let len = left.len().min(right.len());

        for i in 0..len {
            let mut l = left[i] * self.pre_gain;
            let mut r = right[i] * self.pre_gain;

            // Node 2: HPF (Butterworth)
            l = self.hpf_l.process_sample(l);
            r = self.hpf_r.process_sample(r);

            // Node 3: Tonal Curve EQ
            for idx in 0..self.tonal_l.len() {
                l = self.tonal_l[idx].process_sample(l);
                r = self.tonal_r[idx].process_sample(r);
            }

            // Node 4: Stereo processor (M/S)
            if self.stereo_width < 1.0 {
                let mid = (l + r) * 0.5;
                let side = (l - r) * 0.5;
                l = mid + side * self.stereo_width;
                r = mid - side * self.stereo_width;
            }

            // Node 5: Simple DRC (envelope follower + gain reduction)
            if self.drc_ratio > 1.0 {
                let abs_l = l.abs();
                let abs_r = r.abs();

                self.drc_env_l = if abs_l > self.drc_env_l {
                    self.drc_env_l + self.drc_attack_coeff * (abs_l - self.drc_env_l)
                } else {
                    self.drc_env_l + self.drc_release_coeff * (abs_l - self.drc_env_l)
                };
                self.drc_env_r = if abs_r > self.drc_env_r {
                    self.drc_env_r + self.drc_attack_coeff * (abs_r - self.drc_env_r)
                } else {
                    self.drc_env_r + self.drc_release_coeff * (abs_r - self.drc_env_r)
                };

                if self.drc_env_l > self.drc_threshold {
                    let over = self.drc_env_l / self.drc_threshold;
                    let gr = over.powf(1.0 / self.drc_ratio - 1.0);
                    l *= gr;
                }
                if self.drc_env_r > self.drc_threshold {
                    let over = self.drc_env_r / self.drc_threshold;
                    let gr = over.powf(1.0 / self.drc_ratio - 1.0);
                    r *= gr;
                }
            }

            // Node 6: Limiter (brickwall)
            let ceiling = self.limiter_ceiling;
            l = l.clamp(-ceiling, ceiling);
            r = r.clamp(-ceiling, ceiling);

            // Node 7: Distortion model
            match self.distortion_model {
                DistortionModel::None => {}
                DistortionModel::SoftClip => {
                    l = soft_clip(l * (1.0 + self.distortion_drive * 4.0));
                    r = soft_clip(r * (1.0 + self.distortion_drive * 4.0));
                }
                DistortionModel::HardClip => {
                    let clip_level = 1.0 - self.distortion_drive * 0.4;
                    l = l.clamp(-clip_level, clip_level);
                    r = r.clamp(-clip_level, clip_level);
                }
                DistortionModel::SpeakerBreakup => {
                    l = speaker_breakup(l, self.distortion_drive);
                    r = speaker_breakup(r, self.distortion_drive);
                }
            }

            // Node 8: Environmental noise overlay
            if self.env_noise_level > 0.0 {
                let noise_seed = (i as f64 * 0.7919 + 0.3141).sin() * 43758.5453;
                let noise = (noise_seed - noise_seed.floor()) * 2.0 - 1.0;
                l += noise * self.env_noise_level;
                r += noise * self.env_noise_level * 0.97;
            }

            left[i] = l;
            right[i] = r;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// dB to linear conversion
#[inline]
fn db_to_linear(db: f64) -> f64 {
    10.0_f64.powf(db / 20.0)
}

/// Soft clip (tanh-based)
#[inline]
fn soft_clip(x: Sample) -> Sample {
    x.tanh()
}

/// Speaker breakup model — asymmetric distortion with dynamic bias
#[inline]
fn speaker_breakup(x: Sample, drive: f64) -> Sample {
    let driven = x * (1.0 + drive * 6.0);
    let positive = driven.tanh();
    let negative = (driven * 1.2).tanh() * 0.833; // Asymmetric
    if driven >= 0.0 { positive } else { negative }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE LOOKUP
// ═══════════════════════════════════════════════════════════════════════════

/// Find profile by ID
pub fn get_profile(id: u16) -> Option<&'static DeviceProfile> {
    DEVICE_PROFILES.iter().find(|p| p.id == id)
}

/// Get all profiles in a category
pub fn profiles_by_category(category: DeviceCategory) -> Vec<&'static DeviceProfile> {
    DEVICE_PROFILES
        .iter()
        .filter(|p| p.category == category)
        .collect()
}

/// Get profile count
pub fn profile_count() -> usize {
    DEVICE_PROFILES.len()
}

/// Get all category names
pub fn category_names() -> &'static [(&'static str, DeviceCategory)] {
    &[
        ("Smartphones", DeviceCategory::Smartphone),
        ("Headphones", DeviceCategory::Headphone),
        ("Laptop / Tablet", DeviceCategory::LaptopTablet),
        ("TV / Soundbar", DeviceCategory::TvSoundbar),
        ("BT Speakers", DeviceCategory::BtSpeaker),
        ("Reference Monitors", DeviceCategory::ReferenceMonitor),
        ("Casino / Environment", DeviceCategory::CasinoEnvironment),
        ("Custom", DeviceCategory::Custom),
    ]
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_profile_count() {
        assert_eq!(DEVICE_PROFILES.len(), 50);
    }

    #[test]
    fn test_category_distribution() {
        let smartphones = profiles_by_category(DeviceCategory::Smartphone);
        let headphones = profiles_by_category(DeviceCategory::Headphone);
        let laptops = profiles_by_category(DeviceCategory::LaptopTablet);
        let tv = profiles_by_category(DeviceCategory::TvSoundbar);
        let bt = profiles_by_category(DeviceCategory::BtSpeaker);
        let monitors = profiles_by_category(DeviceCategory::ReferenceMonitor);
        let casino = profiles_by_category(DeviceCategory::CasinoEnvironment);

        assert_eq!(smartphones.len(), 15);
        assert_eq!(headphones.len(), 9);
        assert_eq!(laptops.len(), 6);
        assert_eq!(tv.len(), 6);
        assert_eq!(bt.len(), 5);
        assert_eq!(monitors.len(), 5);
        assert_eq!(casino.len(), 4);
    }

    #[test]
    fn test_profile_lookup() {
        let profile = get_profile(100).expect("iPhone 15 Pro Max should exist");
        assert_eq!(profile.name, "iPhone 15 Pro Max");
        assert_eq!(profile.category, DeviceCategory::Smartphone);
    }

    #[test]
    fn test_engine_bypass() {
        let mut engine = DevicePreviewEngine::new(48000.0);
        engine.set_active(true);

        let mut left = vec![0.5_f64; 512];
        let mut right = vec![0.5_f64; 512];

        // Bypass coefficients — should pass through (nearly) unchanged
        engine.process(&mut left, &mut right);

        // With bypass coeffs, output should be very close to input
        for s in &left {
            assert!((s - 0.5).abs() < 0.01, "Bypass should be near-unity");
        }
    }

    #[test]
    fn test_engine_inactive() {
        let mut engine = DevicePreviewEngine::new(48000.0);
        // Not active by default
        assert!(!engine.is_active());

        let mut left = vec![0.5_f64; 512];
        let mut right = vec![0.5_f64; 512];

        engine.process(&mut left, &mut right);

        // Should be completely unchanged
        for s in &left {
            assert_eq!(*s, 0.5);
        }
    }

    #[test]
    fn test_load_profile() {
        let mut engine = DevicePreviewEngine::new(48000.0);
        let profile = get_profile(100).unwrap();
        engine.load_profile(profile);
        engine.set_active(true);

        assert_eq!(engine.current_profile_id(), 100);
        assert!(engine.is_active());
    }

    #[test]
    fn test_soft_clip() {
        assert!((soft_clip(0.0)).abs() < 1e-10);
        assert!(soft_clip(10.0) < 1.0); // Tanh saturates
        assert!(soft_clip(-10.0) > -1.0);
    }

    #[test]
    fn test_speaker_breakup_asymmetric() {
        let pos = speaker_breakup(0.5, 0.5);
        let neg = speaker_breakup(-0.5, 0.5);
        // Asymmetric — positive and negative should differ in magnitude
        assert!((pos.abs() - neg.abs()).abs() > 0.001);
    }

    #[test]
    fn test_db_to_linear() {
        assert!((db_to_linear(0.0) - 1.0).abs() < 1e-10);
        assert!((db_to_linear(-6.0) - 0.5012).abs() < 0.01);
        assert!((db_to_linear(-20.0) - 0.1).abs() < 0.001);
    }

    #[test]
    fn test_unique_profile_ids() {
        let mut ids: Vec<u16> = DEVICE_PROFILES.iter().map(|p| p.id).collect();
        ids.sort();
        ids.dedup();
        assert_eq!(
            ids.len(),
            DEVICE_PROFILES.len(),
            "All profile IDs must be unique"
        );
    }

    #[test]
    fn test_smartphone_profile_processing() {
        let mut engine = DevicePreviewEngine::new(48000.0);
        let profile = get_profile(110).unwrap(); // Budget Android
        engine.load_profile(profile);
        engine.set_active(true);

        // Generate a sine wave
        let mut left = Vec::with_capacity(1024);
        let mut right = Vec::with_capacity(1024);
        for i in 0..1024 {
            let t = i as f64 / 48000.0;
            let sample = (t * 1000.0 * std::f64::consts::TAU).sin() * 0.5;
            left.push(sample);
            right.push(sample);
        }

        engine.process(&mut left, &mut right);

        // Budget Android is mono — L and R should be identical
        for i in 0..1024 {
            assert!(
                (left[i] - right[i]).abs() < 0.05,
                "Mono device should have near-identical L/R at sample {}",
                i
            );
        }
    }
}

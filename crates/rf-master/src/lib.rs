//! FluxForge Studio Intelligent Mastering Engine
//!
//! AI-assisted mastering with genre-aware processing:
//!
//! ## Features
//! - **Genre Analysis**: Automatic genre detection for context-aware processing
//! - **Loudness Targeting**: LUFS-based loudness normalization with genre presets
//! - **Spectral Balance**: Intelligent EQ matching and tonal correction
//! - **Dynamic Control**: Adaptive multiband dynamics with genre profiles
//! - **Stereo Enhancement**: Width optimization and mono compatibility
//! - **True Peak Limiting**: ISP-safe limiting with 8x oversampling
//! - **Reference Matching**: Match spectral/dynamic profile of reference tracks
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_master::{MasteringEngine, MasteringPreset, LoudnessTarget};
//!
//! // Create engine with streaming preset
//! let mut engine = MasteringEngine::new(48000);
//! engine.set_preset(MasteringPreset::Streaming);
//! engine.set_loudness_target(LoudnessTarget::lufs(-14.0));
//!
//! // Process audio
//! let mastered = engine.process(&input_audio);
//! ```

#![warn(missing_docs)]
#![allow(dead_code)]
// Mastering algorithms use explicit indexing
#![allow(clippy::needless_range_loop)]

pub mod analysis;
pub mod chain;
pub mod dynamics;
pub mod eq;
pub mod limiter;
pub mod loudness;
pub mod reference;
pub mod stereo;

mod error;

pub use error::{MasterError, MasterResult};

use serde::{Deserialize, Serialize};

/// Mastering preset for different delivery targets
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MasteringPreset {
    /// CD/Lossless distribution (-9 to -12 LUFS)
    CdLossless,
    /// Streaming platforms (-14 LUFS)
    Streaming,
    /// Apple Music (-16 LUFS integrated)
    AppleMusic,
    /// Broadcast (-23 LUFS EBU R128)
    Broadcast,
    /// Club/DJ playback (loud, punchy)
    Club,
    /// Vinyl mastering (limited dynamics, bass mono)
    Vinyl,
    /// Podcast/Voice (-16 to -19 LUFS)
    Podcast,
    /// Film/Video (-24 LUFS dialogue norm)
    Film,
    /// Custom settings
    Custom,
}

impl MasteringPreset {
    /// Get target LUFS for preset
    pub fn target_lufs(&self) -> f32 {
        match self {
            MasteringPreset::CdLossless => -11.0,
            MasteringPreset::Streaming => -14.0,
            MasteringPreset::AppleMusic => -16.0,
            MasteringPreset::Broadcast => -23.0,
            MasteringPreset::Club => -8.0,
            MasteringPreset::Vinyl => -12.0,
            MasteringPreset::Podcast => -18.0,
            MasteringPreset::Film => -24.0,
            MasteringPreset::Custom => -14.0,
        }
    }

    /// Get true peak limit for preset
    pub fn true_peak_limit(&self) -> f32 {
        match self {
            MasteringPreset::CdLossless => -0.3,
            MasteringPreset::Streaming => -1.0,
            MasteringPreset::AppleMusic => -1.0,
            MasteringPreset::Broadcast => -1.0,
            MasteringPreset::Club => -0.1,
            MasteringPreset::Vinyl => -0.5,
            MasteringPreset::Podcast => -1.5,
            MasteringPreset::Film => -1.0,
            MasteringPreset::Custom => -1.0,
        }
    }

    /// Get dynamics range target (LRA)
    pub fn dynamics_target(&self) -> f32 {
        match self {
            MasteringPreset::CdLossless => 8.0,
            MasteringPreset::Streaming => 10.0,
            MasteringPreset::AppleMusic => 12.0,
            MasteringPreset::Broadcast => 15.0,
            MasteringPreset::Club => 5.0,
            MasteringPreset::Vinyl => 10.0,
            MasteringPreset::Podcast => 6.0,
            MasteringPreset::Film => 18.0,
            MasteringPreset::Custom => 10.0,
        }
    }
}

/// Detected audio genre for context-aware processing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Genre {
    /// Electronic/EDM
    Electronic,
    /// Hip-hop/Rap
    HipHop,
    /// Rock/Metal
    Rock,
    /// Pop
    Pop,
    /// Classical/Orchestral
    Classical,
    /// Jazz
    Jazz,
    /// Acoustic/Folk
    Acoustic,
    /// R&B/Soul
    RnB,
    /// Podcast/Speech
    Speech,
    /// Unknown/Mixed
    Unknown,
}

impl Genre {
    /// Get spectral tilt preference (bass emphasis)
    pub fn spectral_tilt(&self) -> f32 {
        match self {
            Genre::Electronic => 3.0, // Bass heavy
            Genre::HipHop => 4.0,     // Very bass heavy
            Genre::Rock => 1.0,       // Balanced
            Genre::Pop => 2.0,        // Slight bass boost
            Genre::Classical => -1.0, // Flat/natural
            Genre::Jazz => 0.0,       // Natural
            Genre::Acoustic => -0.5,  // Slight treble
            Genre::RnB => 3.5,        // Bass emphasis
            Genre::Speech => -2.0,    // Presence boost
            Genre::Unknown => 0.0,
        }
    }

    /// Get recommended compression ratio
    pub fn compression_ratio(&self) -> f32 {
        match self {
            Genre::Electronic => 4.0,
            Genre::HipHop => 3.5,
            Genre::Rock => 4.0,
            Genre::Pop => 3.0,
            Genre::Classical => 1.5,
            Genre::Jazz => 2.0,
            Genre::Acoustic => 2.0,
            Genre::RnB => 3.0,
            Genre::Speech => 3.0,
            Genre::Unknown => 2.5,
        }
    }

    /// Get stereo width preference
    pub fn stereo_width(&self) -> f32 {
        match self {
            Genre::Electronic => 1.3, // Wide
            Genre::HipHop => 1.1,
            Genre::Rock => 1.2,
            Genre::Pop => 1.15,
            Genre::Classical => 1.0, // Natural
            Genre::Jazz => 1.05,
            Genre::Acoustic => 1.0,
            Genre::RnB => 1.1,
            Genre::Speech => 0.9, // Narrow/center
            Genre::Unknown => 1.0,
        }
    }
}

/// Loudness target configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoudnessTarget {
    /// Target integrated LUFS
    pub integrated_lufs: f32,
    /// True peak limit (dBTP)
    pub true_peak: f32,
    /// Short-term LUFS limit (optional)
    pub short_term_max: Option<f32>,
    /// Loudness range target (LRA)
    pub lra_target: Option<f32>,
}

impl LoudnessTarget {
    /// Create from integrated LUFS
    pub fn lufs(integrated: f32) -> Self {
        Self {
            integrated_lufs: integrated,
            true_peak: -1.0,
            short_term_max: None,
            lra_target: None,
        }
    }

    /// Create from preset
    pub fn from_preset(preset: MasteringPreset) -> Self {
        Self {
            integrated_lufs: preset.target_lufs(),
            true_peak: preset.true_peak_limit(),
            short_term_max: None,
            lra_target: Some(preset.dynamics_target()),
        }
    }

    /// Set true peak limit
    pub fn with_true_peak(mut self, db: f32) -> Self {
        self.true_peak = db;
        self
    }

    /// Set short-term limit
    pub fn with_short_term_max(mut self, lufs: f32) -> Self {
        self.short_term_max = Some(lufs);
        self
    }

    /// Set LRA target
    pub fn with_lra(mut self, lra: f32) -> Self {
        self.lra_target = Some(lra);
        self
    }
}

impl Default for LoudnessTarget {
    fn default() -> Self {
        Self::lufs(-14.0)
    }
}

/// Mastering engine configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MasterConfig {
    /// Sample rate
    pub sample_rate: u32,
    /// Processing preset
    pub preset: MasteringPreset,
    /// Loudness target
    pub loudness: LoudnessTarget,
    /// Auto-detect genre
    pub auto_genre: bool,
    /// Override genre (if not auto)
    pub genre: Genre,
    /// Enable multiband processing
    pub multiband: bool,
    /// Multiband crossover frequencies
    pub crossovers: Vec<f32>,
    /// Enable stereo enhancement
    pub stereo_enhance: bool,
    /// Enable spectral shaping
    pub spectral_shape: bool,
    /// Reference track for matching (optional)
    pub reference: Option<ReferenceProfile>,
    /// Limiter lookahead (ms)
    pub limiter_lookahead_ms: f32,
    /// Enable dithering
    pub dither: bool,
    /// Target bit depth
    pub target_bits: u32,
}

impl Default for MasterConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            preset: MasteringPreset::Streaming,
            loudness: LoudnessTarget::default(),
            auto_genre: true,
            genre: Genre::Unknown,
            multiband: true,
            crossovers: vec![100.0, 500.0, 2000.0, 8000.0],
            stereo_enhance: true,
            spectral_shape: true,
            reference: None,
            limiter_lookahead_ms: 5.0,
            dither: true,
            target_bits: 24,
        }
    }
}

/// Reference track profile for matching
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReferenceProfile {
    /// Name of reference track
    pub name: String,
    /// Spectral envelope (magnitude per frequency bin)
    pub spectrum: Vec<f32>,
    /// Dynamics profile
    pub dynamics: DynamicsProfile,
    /// Stereo characteristics
    pub stereo: StereoProfile,
    /// Loudness measurements
    pub loudness: LoudnessMeasurement,
}

/// Dynamics profile from analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DynamicsProfile {
    /// Peak to RMS ratio
    pub crest_factor: f32,
    /// Dynamic range (dB)
    pub dynamic_range: f32,
    /// Loudness range (LRA)
    pub lra: f32,
    /// Multiband dynamics
    pub band_dynamics: Vec<f32>,
}

/// Stereo profile from analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StereoProfile {
    /// Average correlation
    pub correlation: f32,
    /// Average width
    pub width: f32,
    /// Low frequency mono percentage
    pub low_mono: f32,
    /// Balance (L-R)
    pub balance: f32,
}

/// Loudness measurement
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoudnessMeasurement {
    /// Integrated LUFS
    pub integrated: f32,
    /// Short-term max LUFS
    pub short_term_max: f32,
    /// Momentary max LUFS
    pub momentary_max: f32,
    /// True peak (dBTP)
    pub true_peak: f32,
    /// Loudness range
    pub lra: f32,
}

impl Default for LoudnessMeasurement {
    fn default() -> Self {
        Self {
            integrated: -14.0,
            short_term_max: -12.0,
            momentary_max: -10.0,
            true_peak: -1.0,
            lra: 8.0,
        }
    }
}

/// Mastering result with measurements
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MasteringResult {
    /// Output audio (if offline mode)
    pub audio: Option<Vec<f32>>,
    /// Pre-master loudness
    pub input_loudness: LoudnessMeasurement,
    /// Post-master loudness
    pub output_loudness: LoudnessMeasurement,
    /// Detected genre
    pub detected_genre: Genre,
    /// Applied gain (dB)
    pub applied_gain: f32,
    /// Limiting reduction (dB)
    pub peak_reduction: f32,
    /// Processing chain summary
    pub chain_summary: Vec<String>,
    /// Quality score (0-100)
    pub quality_score: f32,
    /// Warnings
    pub warnings: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preset_values() {
        assert_eq!(MasteringPreset::Streaming.target_lufs(), -14.0);
        assert_eq!(MasteringPreset::Broadcast.target_lufs(), -23.0);
        assert!(MasteringPreset::Club.target_lufs() > MasteringPreset::Streaming.target_lufs());
    }

    #[test]
    fn test_loudness_target() {
        let target = LoudnessTarget::lufs(-14.0)
            .with_true_peak(-1.0)
            .with_lra(10.0);

        assert_eq!(target.integrated_lufs, -14.0);
        assert_eq!(target.true_peak, -1.0);
        assert_eq!(target.lra_target, Some(10.0));
    }

    #[test]
    fn test_genre_properties() {
        assert!(Genre::HipHop.spectral_tilt() > Genre::Classical.spectral_tilt());
        assert!(Genre::Electronic.stereo_width() > Genre::Speech.stereo_width());
    }

    #[test]
    fn test_config_default() {
        let config = MasterConfig::default();
        assert_eq!(config.sample_rate, 48000);
        assert_eq!(config.preset, MasteringPreset::Streaming);
        assert!(config.multiband);
    }
}

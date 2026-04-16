//! T8.3: Post-processing pipeline — loudness, fade, format normalization.
//!
//! Defines configuration for post-processing generated audio assets.
//! Actual DSP is handled by rf-dsp and rf-offline; this module provides
//! the data model and spec generation.

use serde::{Deserialize, Serialize};
use crate::prompt::{AudioDescriptor, EventCategory, AudioTier};

/// EBU R128 loudness target presets
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum LoudnessTarget {
    /// EBU R128 standard (-23.0 LUFS) — broadcast/streaming
    EbuR128,
    /// iGaming standard (-18.0 LUFS) — slot games
    IGaming,
    /// AES streaming standard (-16.0 LUFS) — platform streaming
    AesStreaming,
    /// Custom LUFS value
    Custom(f32),
}

impl LoudnessTarget {
    pub fn lufs_value(&self) -> f32 {
        match self {
            Self::EbuR128     => -23.0,
            Self::IGaming     => -18.0,
            Self::AesStreaming => -16.0,
            Self::Custom(v)   => *v,
        }
    }

    pub fn true_peak_dbtp(&self) -> f32 {
        match self {
            Self::EbuR128     => -1.0,
            Self::IGaming     => -1.0,
            Self::AesStreaming => -1.0,
            Self::Custom(_)   => -1.0,
        }
    }
}

/// Fade configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FadeConfig {
    /// Fade-in duration in milliseconds (0 = no fade-in)
    pub fade_in_ms: u32,
    /// Fade-out duration in milliseconds (0 = no fade-out)
    pub fade_out_ms: u32,
    /// Fade curve shape
    pub curve: FadeCurve,
}

impl Default for FadeConfig {
    fn default() -> Self {
        Self {
            fade_in_ms: 5,
            fade_out_ms: 50,
            curve: FadeCurve::Logarithmic,
        }
    }
}

/// Fade curve shape
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum FadeCurve {
    Linear,
    Logarithmic,
    Sinusoidal,
    SCurve,
}

/// Output format specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormatSpec {
    /// Output format
    pub format: AudioFormat,
    /// Sample rate
    pub sample_rate: u32,
    /// Bit depth (for PCM formats)
    pub bit_depth: u8,
    /// Channel count (1 = mono, 2 = stereo)
    pub channels: u8,
}

impl Default for FormatSpec {
    fn default() -> Self {
        Self {
            format: AudioFormat::Wav,
            sample_rate: 44100,
            bit_depth: 24,
            channels: 2,
        }
    }
}

/// Supported audio formats
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioFormat {
    Wav,
    Ogg,
    Mp3,
    Flac,
    Aiff,
}

impl AudioFormat {
    pub fn extension(&self) -> &'static str {
        match self {
            Self::Wav  => "wav",
            Self::Ogg  => "ogg",
            Self::Mp3  => "mp3",
            Self::Flac => "flac",
            Self::Aiff => "aiff",
        }
    }
}

/// Dynamic range processing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DynamicsConfig {
    /// Apply limiter to prevent clipping
    pub apply_limiter: bool,
    /// Limiter ceiling in dBTP
    pub limiter_ceiling_dbtp: f32,
    /// Whether to apply gentle compression for consistent levels
    pub apply_compression: bool,
    /// Compression ratio (1:1 = bypass, 4:1 = moderate)
    pub compression_ratio: f32,
    /// Compression threshold in dBFS
    pub compression_threshold_db: f32,
}

impl Default for DynamicsConfig {
    fn default() -> Self {
        Self {
            apply_limiter: true,
            limiter_ceiling_dbtp: -0.1,
            apply_compression: false,
            compression_ratio: 1.0,
            compression_threshold_db: -18.0,
        }
    }
}

/// Complete post-processing configuration for a generated asset (T8.3)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostProcessingConfig {
    /// Loudness normalization target
    pub loudness: LoudnessTarget,
    /// Fade configuration
    pub fade: FadeConfig,
    /// Output format
    pub format: FormatSpec,
    /// Dynamic range processing
    pub dynamics: DynamicsConfig,
    /// Loop point detection (for looping assets)
    pub detect_loop_points: bool,
    /// Trim silence at start/end
    pub trim_silence: bool,
    /// Silence threshold in dBFS
    pub silence_threshold_db: f32,
}

impl Default for PostProcessingConfig {
    fn default() -> Self {
        Self {
            loudness: LoudnessTarget::IGaming,
            fade: FadeConfig::default(),
            format: FormatSpec::default(),
            dynamics: DynamicsConfig::default(),
            detect_loop_points: false,
            trim_silence: true,
            silence_threshold_db: -60.0,
        }
    }
}

impl PostProcessingConfig {
    /// Generate optimal post-processing config for an audio descriptor.
    pub fn for_descriptor(descriptor: &AudioDescriptor) -> Self {
        let mut config = Self::default();

        // Looping assets need loop point detection
        if descriptor.can_loop {
            config.detect_loop_points = true;
            config.fade.fade_in_ms = 10;
            config.fade.fade_out_ms = 10;
        }

        // UI sounds: very short, minimal processing
        if descriptor.category == EventCategory::UI {
            config.fade.fade_in_ms = 0;
            config.fade.fade_out_ms = 5;
            config.loudness = LoudnessTarget::IGaming;
        }

        // Flagship wins: slight compression for consistent energy
        if descriptor.tier == AudioTier::Flagship {
            config.dynamics.apply_compression = true;
            config.dynamics.compression_ratio = 2.0;
        }

        // Ambient beds: very gentle fade in/out
        if descriptor.category == EventCategory::Ambient {
            config.fade.fade_in_ms = 500;
            config.fade.fade_out_ms = 1000;
            config.fade.curve = FadeCurve::Sinusoidal;
        }

        config
    }

    /// Generate a processing pipeline description for display
    pub fn pipeline_steps(&self) -> Vec<String> {
        let mut steps = Vec::new();
        if self.trim_silence {
            steps.push(format!("Trim silence (threshold: {:.0} dBFS)", self.silence_threshold_db));
        }
        if self.fade.fade_in_ms > 0 {
            steps.push(format!("Fade-in: {} ms ({:?})", self.fade.fade_in_ms, self.fade.curve));
        }
        if self.fade.fade_out_ms > 0 {
            steps.push(format!("Fade-out: {} ms ({:?})", self.fade.fade_out_ms, self.fade.curve));
        }
        if self.dynamics.apply_compression {
            steps.push(format!(
                "Compress: {:.1}:1 at {:.0} dBFS",
                self.dynamics.compression_ratio, self.dynamics.compression_threshold_db
            ));
        }
        steps.push(format!(
            "Loudness: {:.1} LUFS ({})",
            self.loudness.lufs_value(),
            match &self.loudness {
                LoudnessTarget::EbuR128 => "EBU R128",
                LoudnessTarget::IGaming => "iGaming",
                LoudnessTarget::AesStreaming => "AES Streaming",
                LoudnessTarget::Custom(_) => "Custom",
            }
        ));
        if self.dynamics.apply_limiter {
            steps.push(format!("True peak limit: {:.1} dBTP", self.dynamics.limiter_ceiling_dbtp));
        }
        if self.detect_loop_points {
            steps.push("Detect loop points".to_string());
        }
        steps.push(format!(
            "Export: {} {}-bit {}Hz {}ch",
            self.format.format.extension().to_uppercase(),
            self.format.bit_depth, self.format.sample_rate, self.format.channels
        ));
        steps
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::prompt::PromptParser;

    #[test]
    fn test_default_loudness_is_igaming() {
        let config = PostProcessingConfig::default();
        assert!((config.loudness.lufs_value() - (-18.0)).abs() < 0.01);
    }

    #[test]
    fn test_loop_detection_for_ambient() {
        let desc = PromptParser::parse("casino ambient background loop");
        let config = PostProcessingConfig::for_descriptor(&desc);
        assert!(config.detect_loop_points);
    }

    #[test]
    fn test_ui_click_minimal_fade() {
        let desc = PromptParser::parse("short UI click button");
        let config = PostProcessingConfig::for_descriptor(&desc);
        assert_eq!(config.fade.fade_in_ms, 0);
        assert!(config.fade.fade_out_ms <= 20);
    }

    #[test]
    fn test_flagship_win_has_compression() {
        let desc = PromptParser::parse("mega ultimate jackpot win fanfare");
        let config = PostProcessingConfig::for_descriptor(&desc);
        assert!(config.dynamics.apply_compression);
    }

    #[test]
    fn test_pipeline_steps_not_empty() {
        let config = PostProcessingConfig::default();
        assert!(!config.pipeline_steps().is_empty());
    }

    #[test]
    fn test_pipeline_always_contains_loudness_step() {
        let config = PostProcessingConfig::default();
        let steps = config.pipeline_steps();
        assert!(steps.iter().any(|s| s.contains("LUFS")));
    }

    #[test]
    fn test_lufs_custom_value() {
        let t = LoudnessTarget::Custom(-20.5);
        assert!((t.lufs_value() - (-20.5)).abs() < 0.01);
    }
}

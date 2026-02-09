//! Enhancement configuration

use serde::{Deserialize, Serialize};

/// Enhancement mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum EnhanceMode {
    /// Real-time mode (minimum latency)
    Realtime,
    /// Balanced mode (good quality, low latency)
    #[default]
    Balanced,
    /// Quality mode (best quality, higher latency)
    Quality,
    /// Broadcast mode (optimized for streaming)
    Broadcast,
}

/// Enhancement configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhanceConfig {
    /// Enhancement mode
    pub mode: EnhanceMode,

    /// Enhancement strength (0.0 - 1.0)
    /// 0.0 = no enhancement, 1.0 = maximum enhancement
    pub strength: f32,

    /// Preserve voice naturalness (0.0 - 1.0)
    /// Higher values preserve more natural voice characteristics
    pub voice_preservation: f32,

    /// Background noise suppression level (0.0 - 1.0)
    pub noise_suppression: f32,

    /// Reduce reverb/echo (0.0 - 1.0)
    pub dereverb: f32,

    /// Frame size in samples (for real-time processing)
    pub frame_size: usize,

    /// Sample rate
    pub sample_rate: u32,

    /// Use GPU if available
    pub use_gpu: bool,

    /// State space model order (for aTENNuate)
    pub ssm_order: usize,

    /// Number of frequency bands
    pub num_bands: usize,
}

impl Default for EnhanceConfig {
    fn default() -> Self {
        Self {
            mode: EnhanceMode::default(),
            strength: 0.8,
            voice_preservation: 0.7,
            noise_suppression: 0.8,
            dereverb: 0.3,
            frame_size: 240, // 5ms @ 48kHz
            sample_rate: 48000,
            use_gpu: true,
            ssm_order: 64,
            num_bands: 257,
        }
    }
}

impl EnhanceConfig {
    /// Create real-time configuration (minimum latency)
    pub fn realtime() -> Self {
        Self {
            mode: EnhanceMode::Realtime,
            strength: 0.75,
            voice_preservation: 0.8,
            noise_suppression: 0.7,
            dereverb: 0.2,
            frame_size: 240, // 5ms @ 48kHz
            sample_rate: 48000,
            use_gpu: true,
            ssm_order: 32, // Smaller for speed
            num_bands: 257,
        }
    }

    /// Create quality configuration (best quality)
    pub fn quality() -> Self {
        Self {
            mode: EnhanceMode::Quality,
            strength: 0.9,
            voice_preservation: 0.6,
            noise_suppression: 0.9,
            dereverb: 0.5,
            frame_size: 480, // 10ms @ 48kHz
            sample_rate: 48000,
            use_gpu: true,
            ssm_order: 128,
            num_bands: 513,
        }
    }

    /// Create broadcast configuration
    pub fn broadcast() -> Self {
        Self {
            mode: EnhanceMode::Broadcast,
            strength: 0.85,
            voice_preservation: 0.75,
            noise_suppression: 0.85,
            dereverb: 0.4,
            frame_size: 480,
            sample_rate: 48000,
            use_gpu: true,
            ssm_order: 64,
            num_bands: 257,
        }
    }

    /// Calculate latency in milliseconds
    pub fn latency_ms(&self) -> f64 {
        self.frame_size as f64 / self.sample_rate as f64 * 1000.0
    }

    /// Calculate latency in samples
    pub fn latency_samples(&self) -> usize {
        self.frame_size
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_realtime_latency() {
        let config = EnhanceConfig::realtime();
        let latency = config.latency_ms();
        assert!(latency <= 5.0, "Realtime mode should have <= 5ms latency");
    }

    #[test]
    fn test_config_modes() {
        let realtime = EnhanceConfig::realtime();
        let quality = EnhanceConfig::quality();

        assert!(realtime.latency_ms() < quality.latency_ms());
        assert!(realtime.ssm_order < quality.ssm_order);
    }
}

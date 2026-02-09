//! Separation configuration

use serde::{Deserialize, Serialize};

/// Separation quality preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum SeparationQuality {
    /// Fast mode (lower quality, faster)
    Fast,
    /// Default quality (balanced)
    #[default]
    Default,
    /// High quality (slower, better)
    High,
    /// Ultra quality (slowest, best)
    Ultra,
}

/// Separation configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeparationConfig {
    /// Quality preset
    pub quality: SeparationQuality,

    /// Use 6-stem model (includes piano, guitar)
    pub use_6_stems: bool,

    /// Segment length in seconds (longer = more memory, potentially better)
    pub segment_length: f32,

    /// Overlap between segments (0.0 - 0.5)
    pub overlap: f32,

    /// Number of random shifts (more = better quality, slower)
    pub shifts: usize,

    /// Use GPU if available
    pub use_gpu: bool,

    /// Maximum batch size for GPU
    pub batch_size: usize,

    /// Post-process with Wiener filter
    pub wiener_filter: bool,

    /// Wiener filter iterations
    pub wiener_iterations: usize,

    /// Progress callback frequency (0 = disabled)
    pub progress_interval_ms: u64,
}

impl Default for SeparationConfig {
    fn default() -> Self {
        Self {
            quality: SeparationQuality::Default,
            use_6_stems: false,
            segment_length: 7.8,
            overlap: 0.25,
            shifts: 1,
            use_gpu: true,
            batch_size: 1,
            wiener_filter: false,
            wiener_iterations: 1,
            progress_interval_ms: 500,
        }
    }
}

impl SeparationConfig {
    /// Create fast configuration
    pub fn fast() -> Self {
        Self {
            quality: SeparationQuality::Fast,
            use_6_stems: false,
            segment_length: 7.8,
            overlap: 0.0,
            shifts: 0,
            use_gpu: true,
            batch_size: 4,
            wiener_filter: false,
            wiener_iterations: 0,
            progress_interval_ms: 200,
        }
    }

    /// Create high quality configuration
    pub fn high_quality() -> Self {
        Self {
            quality: SeparationQuality::High,
            use_6_stems: false,
            segment_length: 10.0,
            overlap: 0.25,
            shifts: 2,
            use_gpu: true,
            batch_size: 1,
            wiener_filter: true,
            wiener_iterations: 1,
            progress_interval_ms: 1000,
        }
    }

    /// Create ultra quality configuration
    pub fn ultra() -> Self {
        Self {
            quality: SeparationQuality::Ultra,
            use_6_stems: true,
            segment_length: 12.0,
            overlap: 0.5,
            shifts: 5,
            use_gpu: true,
            batch_size: 1,
            wiener_filter: true,
            wiener_iterations: 2,
            progress_interval_ms: 2000,
        }
    }

    /// Create config for 6-stem separation
    pub fn with_6_stems(mut self) -> Self {
        self.use_6_stems = true;
        self
    }

    /// Estimate processing time factor (relative to real-time)
    pub fn estimated_rtf(&self) -> f32 {
        let base_rtf = match self.quality {
            SeparationQuality::Fast => 0.1,
            SeparationQuality::Default => 0.5,
            SeparationQuality::High => 1.0,
            SeparationQuality::Ultra => 2.0,
        };

        let shift_factor = 1.0 + self.shifts as f32 * 0.3;
        let wiener_factor = if self.wiener_filter {
            1.0 + self.wiener_iterations as f32 * 0.2
        } else {
            1.0
        };
        let gpu_factor = if self.use_gpu { 0.3 } else { 1.0 };

        base_rtf * shift_factor * wiener_factor * gpu_factor
    }

    /// Estimate memory usage in MB
    pub fn estimated_memory_mb(&self, duration_secs: f32, sample_rate: u32) -> f32 {
        let samples = duration_secs * sample_rate as f32;
        let channels = 2.0; // Stereo

        // Base: input + output stems
        let num_stems = if self.use_6_stems { 6.0 } else { 4.0 };
        let base_mb = samples * channels * (1.0 + num_stems) * 4.0 / 1_000_000.0;

        // Processing overhead
        let segment_samples = self.segment_length * sample_rate as f32;
        let segment_mb = segment_samples * channels * 4.0 / 1_000_000.0;

        // Model weights (approximate)
        let model_mb = if self.use_6_stems { 400.0 } else { 300.0 };

        base_mb + segment_mb * 4.0 + model_mb
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_presets() {
        let fast = SeparationConfig::fast();
        let ultra = SeparationConfig::ultra();

        assert!(fast.estimated_rtf() < ultra.estimated_rtf());
        assert!(!fast.wiener_filter);
        assert!(ultra.wiener_filter);
    }

    #[test]
    fn test_memory_estimation() {
        let config = SeparationConfig::default();
        let mem = config.estimated_memory_mb(180.0, 44100); // 3 minute song

        // Should be reasonable (< 2GB)
        assert!(mem < 2000.0);
        assert!(mem > 100.0); // But not tiny
    }
}

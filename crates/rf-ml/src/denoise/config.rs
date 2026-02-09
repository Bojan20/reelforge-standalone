//! Denoiser configuration

use serde::{Deserialize, Serialize};

/// Denoising mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum DenoiseMode {
    /// Speech enhancement (optimized for voice)
    Speech,
    /// Music denoising (preserve harmonics)
    Music,
    /// Hybrid mode (auto-detect content)
    #[default]
    Hybrid,
    /// Aggressive (maximum noise reduction)
    Aggressive,
    /// Gentle (preserve detail)
    Gentle,
}

/// Denoiser configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DenoiseConfig {
    /// Denoising mode
    pub mode: DenoiseMode,

    /// Reduction amount (0.0 - 1.0)
    /// 0.0 = no reduction, 1.0 = maximum reduction
    pub reduction: f32,

    /// Sensitivity (0.0 - 1.0)
    /// Higher = more aggressive noise detection
    pub sensitivity: f32,

    /// Preserve transients
    pub preserve_transients: bool,

    /// Post-filter for residual noise
    pub post_filter: bool,

    /// Frame size (samples)
    pub frame_size: usize,

    /// Hop size (samples)
    pub hop_size: usize,

    /// Lookahead frames for non-causal processing
    pub lookahead_frames: usize,

    /// Use GPU acceleration if available
    pub use_gpu: bool,
}

impl Default for DenoiseConfig {
    fn default() -> Self {
        Self {
            mode: DenoiseMode::default(),
            reduction: 0.8,
            sensitivity: 0.5,
            preserve_transients: true,
            post_filter: true,
            frame_size: 480, // 10ms @ 48kHz
            hop_size: 480,   // No overlap for real-time
            lookahead_frames: 2,
            use_gpu: true,
        }
    }
}

impl DenoiseConfig {
    /// Create config for real-time speech enhancement
    pub fn realtime_speech() -> Self {
        Self {
            mode: DenoiseMode::Speech,
            reduction: 0.85,
            sensitivity: 0.6,
            preserve_transients: true,
            post_filter: true,
            frame_size: 480,
            hop_size: 480,
            lookahead_frames: 2,
            use_gpu: true,
        }
    }

    /// Create config for music denoising
    pub fn music() -> Self {
        Self {
            mode: DenoiseMode::Music,
            reduction: 0.7,
            sensitivity: 0.4,
            preserve_transients: true,
            post_filter: false,
            frame_size: 2048,
            hop_size: 512,
            lookahead_frames: 4,
            use_gpu: true,
        }
    }

    /// Create config for aggressive denoising
    pub fn aggressive() -> Self {
        Self {
            mode: DenoiseMode::Aggressive,
            reduction: 1.0,
            sensitivity: 0.8,
            preserve_transients: false,
            post_filter: true,
            frame_size: 480,
            hop_size: 480,
            lookahead_frames: 3,
            use_gpu: true,
        }
    }

    /// Create config for gentle denoising
    pub fn gentle() -> Self {
        Self {
            mode: DenoiseMode::Gentle,
            reduction: 0.5,
            sensitivity: 0.3,
            preserve_transients: true,
            post_filter: false,
            frame_size: 480,
            hop_size: 480,
            lookahead_frames: 2,
            use_gpu: true,
        }
    }

    /// Calculate latency in milliseconds
    pub fn latency_ms(&self, sample_rate: u32) -> f64 {
        let latency_samples = self.frame_size * (self.lookahead_frames + 1);
        latency_samples as f64 / sample_rate as f64 * 1000.0
    }
}

/// Learned noise profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoiseProfile {
    /// Average magnitude per frequency bin
    pub magnitude_floor: Vec<f32>,

    /// Variance per frequency bin
    pub variance: Vec<f32>,

    /// Number of frames analyzed
    pub frames_analyzed: usize,

    /// FFT size used
    pub fft_size: usize,

    /// Sample rate
    pub sample_rate: u32,

    /// Profile quality (0.0 - 1.0)
    pub quality: f32,
}

impl NoiseProfile {
    /// Create empty profile
    pub fn new(fft_size: usize, sample_rate: u32) -> Self {
        let num_bins = fft_size / 2 + 1;
        Self {
            magnitude_floor: vec![0.0; num_bins],
            variance: vec![0.0; num_bins],
            frames_analyzed: 0,
            fft_size,
            sample_rate,
            quality: 0.0,
        }
    }

    /// Update profile with new frame
    pub fn update(&mut self, spectrum_magnitude: &[f32]) {
        assert_eq!(spectrum_magnitude.len(), self.magnitude_floor.len());

        self.frames_analyzed += 1;
        let n = self.frames_analyzed as f32;

        for (i, &mag) in spectrum_magnitude.iter().enumerate() {
            // Running average
            let old_mean = self.magnitude_floor[i];
            self.magnitude_floor[i] += (mag - old_mean) / n;

            // Running variance (Welford's algorithm)
            let delta = mag - old_mean;
            let delta2 = mag - self.magnitude_floor[i];
            self.variance[i] += delta * delta2;
        }

        // Update quality estimate
        self.quality = (1.0 - 1.0 / (self.frames_analyzed as f32 + 1.0)).min(1.0);
    }

    /// Finalize variance calculation
    pub fn finalize(&mut self) {
        if self.frames_analyzed > 1 {
            let n = self.frames_analyzed as f32;
            for v in &mut self.variance {
                *v /= n - 1.0;
                *v = v.sqrt(); // Convert to standard deviation
            }
        }
    }

    /// Get noise floor at frequency
    pub fn noise_at_freq(&self, freq_hz: f32) -> f32 {
        let bin = (freq_hz * self.fft_size as f32 / self.sample_rate as f32) as usize;
        self.magnitude_floor.get(bin).copied().unwrap_or(0.0)
    }

    /// Get threshold for frequency (floor + k * stddev)
    pub fn threshold_at_bin(&self, bin: usize, sensitivity: f32) -> f32 {
        let floor = self.magnitude_floor.get(bin).copied().unwrap_or(0.0);
        let stddev = self.variance.get(bin).copied().unwrap_or(0.0);
        floor + (1.0 - sensitivity) * 3.0 * stddev
    }

    /// Check if profile is valid
    pub fn is_valid(&self) -> bool {
        self.frames_analyzed >= 10 && self.quality > 0.5
    }

    /// Required samples for good profile
    pub fn recommended_samples(&self) -> usize {
        // At least 0.5 seconds of noise
        (self.sample_rate as f64 * 0.5) as usize
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_latency() {
        let config = DenoiseConfig::default();
        let latency = config.latency_ms(48000);
        assert!(latency < 50.0); // Should be under 50ms for real-time
    }

    #[test]
    fn test_noise_profile() {
        let mut profile = NoiseProfile::new(2048, 48000);

        // Add some frames
        for _ in 0..20 {
            let spectrum: Vec<f32> = (0..1025).map(|i| (i as f32 * 0.001) + 0.01).collect();
            profile.update(&spectrum);
        }

        profile.finalize();

        assert!(profile.is_valid());
        assert!(profile.quality > 0.9);
    }
}

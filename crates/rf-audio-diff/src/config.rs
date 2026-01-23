//! Configuration for audio diff operations

use serde::{Deserialize, Serialize};

/// Configuration for audio comparison
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffConfig {
    /// FFT window size (power of 2)
    pub fft_size: usize,

    /// FFT hop size (overlap)
    pub hop_size: usize,

    /// Maximum allowed peak sample difference (0.0-1.0)
    pub peak_diff_tolerance: f64,

    /// Maximum allowed RMS difference (0.0-1.0)
    pub rms_diff_tolerance: f64,

    /// Maximum allowed spectral difference in dB
    pub spectral_diff_db_tolerance: f64,

    /// Maximum allowed phase difference in radians
    pub phase_diff_tolerance: f64,

    /// Duration tolerance in seconds
    pub duration_tolerance_sec: f64,

    /// Whether to allow sample rate conversion
    pub allow_sample_rate_conversion: bool,

    /// Whether to compare in mono (sum channels)
    pub compare_mono: bool,

    /// Frequency range for spectral comparison (Hz)
    pub freq_range: (f64, f64),

    /// A-weighting for perceptual comparison
    pub use_a_weighting: bool,

    /// Number of frequency bands for band-by-band comparison
    pub num_bands: usize,

    /// Ignore differences below this threshold (dB)
    pub noise_floor_db: f64,

    /// Maximum allowed correlation difference (1.0 = perfect correlation)
    pub correlation_tolerance: f64,

    /// Whether to generate detailed per-frame analysis
    pub detailed_analysis: bool,
}

impl Default for DiffConfig {
    fn default() -> Self {
        Self {
            fft_size: 4096,
            hop_size: 1024,
            peak_diff_tolerance: 0.001,        // -60 dB
            rms_diff_tolerance: 0.0001,        // -80 dB
            spectral_diff_db_tolerance: 0.5,   // 0.5 dB
            phase_diff_tolerance: 0.1,         // ~6 degrees
            duration_tolerance_sec: 0.001,     // 1ms
            allow_sample_rate_conversion: false,
            compare_mono: false,
            freq_range: (20.0, 20000.0),
            use_a_weighting: false,
            num_bands: 32,
            noise_floor_db: -96.0,
            correlation_tolerance: 0.9999,
            detailed_analysis: false,
        }
    }
}

impl DiffConfig {
    /// Strict configuration for bit-exact comparison
    pub fn strict() -> Self {
        Self {
            peak_diff_tolerance: 0.0,
            rms_diff_tolerance: 0.0,
            spectral_diff_db_tolerance: 0.0,
            phase_diff_tolerance: 0.0,
            duration_tolerance_sec: 0.0,
            correlation_tolerance: 1.0,
            ..Default::default()
        }
    }

    /// Relaxed configuration for perceptual comparison
    pub fn perceptual() -> Self {
        Self {
            peak_diff_tolerance: 0.01,         // -40 dB
            rms_diff_tolerance: 0.001,         // -60 dB
            spectral_diff_db_tolerance: 3.0,   // 3 dB (just noticeable)
            phase_diff_tolerance: 0.5,         // ~30 degrees
            duration_tolerance_sec: 0.01,      // 10ms
            use_a_weighting: true,
            correlation_tolerance: 0.999,
            ..Default::default()
        }
    }

    /// Configuration for DSP regression testing
    pub fn dsp_regression() -> Self {
        Self {
            fft_size: 8192,
            peak_diff_tolerance: 1e-6,         // -120 dB
            rms_diff_tolerance: 1e-7,          // -140 dB
            spectral_diff_db_tolerance: 0.01,  // 0.01 dB
            phase_diff_tolerance: 0.001,       // ~0.06 degrees
            detailed_analysis: true,
            ..Default::default()
        }
    }

    /// Configuration for lossy codec comparison
    pub fn lossy_codec() -> Self {
        Self {
            peak_diff_tolerance: 0.1,
            rms_diff_tolerance: 0.01,
            spectral_diff_db_tolerance: 6.0,   // 6 dB
            phase_diff_tolerance: 1.0,
            duration_tolerance_sec: 0.05,
            use_a_weighting: true,
            correlation_tolerance: 0.99,
            ..Default::default()
        }
    }

    /// Builder pattern: set FFT size
    pub fn with_fft_size(mut self, size: usize) -> Self {
        self.fft_size = size;
        self.hop_size = size / 4;
        self
    }

    /// Builder pattern: set peak tolerance
    pub fn with_peak_tolerance(mut self, tolerance: f64) -> Self {
        self.peak_diff_tolerance = tolerance;
        self
    }

    /// Builder pattern: set spectral tolerance
    pub fn with_spectral_tolerance_db(mut self, db: f64) -> Self {
        self.spectral_diff_db_tolerance = db;
        self
    }

    /// Builder pattern: set frequency range
    pub fn with_freq_range(mut self, min: f64, max: f64) -> Self {
        self.freq_range = (min, max);
        self
    }

    /// Builder pattern: enable A-weighting
    pub fn with_a_weighting(mut self) -> Self {
        self.use_a_weighting = true;
        self
    }

    /// Builder pattern: enable detailed analysis
    pub fn with_detailed_analysis(mut self) -> Self {
        self.detailed_analysis = true;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = DiffConfig::default();
        assert_eq!(config.fft_size, 4096);
        assert!(config.peak_diff_tolerance > 0.0);
    }

    #[test]
    fn test_strict_config() {
        let config = DiffConfig::strict();
        assert_eq!(config.peak_diff_tolerance, 0.0);
        assert_eq!(config.correlation_tolerance, 1.0);
    }

    #[test]
    fn test_builder_pattern() {
        let config = DiffConfig::default()
            .with_fft_size(8192)
            .with_peak_tolerance(0.01)
            .with_a_weighting();

        assert_eq!(config.fft_size, 8192);
        assert_eq!(config.hop_size, 2048);
        assert_eq!(config.peak_diff_tolerance, 0.01);
        assert!(config.use_a_weighting);
    }
}

//! EQ matching configuration

use serde::{Deserialize, Serialize};

/// Matching mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MatchMode {
    /// Full spectrum matching
    Full,
    /// Tonal balance only (smooth curve)
    TonalBalance,
    /// Brightness matching (high frequencies)
    Brightness,
    /// Warmth matching (low-mid frequencies)
    Warmth,
    /// Custom frequency range
    Custom,
}

impl Default for MatchMode {
    fn default() -> Self {
        Self::Full
    }
}

/// Perceptual weighting curve
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MatchWeighting {
    /// No weighting (linear)
    None,
    /// A-weighting (speech/general)
    AWeighting,
    /// C-weighting (music/high SPL)
    CWeighting,
    /// ITU-R 468 (broadcast)
    Itu468,
    /// Custom perceptual curve
    Perceptual,
}

impl Default for MatchWeighting {
    fn default() -> Self {
        Self::Perceptual
    }
}

/// EQ matching configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchConfig {
    /// Matching mode
    pub mode: MatchMode,

    /// Perceptual weighting
    pub weighting: MatchWeighting,

    /// Number of analysis bands
    pub num_bands: usize,

    /// Minimum frequency (Hz)
    pub min_freq: f32,

    /// Maximum frequency (Hz)
    pub max_freq: f32,

    /// Smoothing factor (0.0 - 1.0)
    /// Higher = smoother EQ curve
    pub smoothing: f32,

    /// Maximum gain change (dB)
    pub max_gain_db: f32,

    /// FFT size for analysis
    pub fft_size: usize,

    /// Use neural matching (if available)
    pub use_neural: bool,

    /// Match intensity (0.0 - 1.0)
    /// 0.0 = no change, 1.0 = full match
    pub intensity: f32,
}

impl Default for MatchConfig {
    fn default() -> Self {
        Self {
            mode: MatchMode::default(),
            weighting: MatchWeighting::default(),
            num_bands: 32,
            min_freq: 20.0,
            max_freq: 20000.0,
            smoothing: 0.5,
            max_gain_db: 12.0,
            fft_size: 4096,
            use_neural: true,
            intensity: 1.0,
        }
    }
}

impl MatchConfig {
    /// Create tonal balance matching config
    pub fn tonal_balance() -> Self {
        Self {
            mode: MatchMode::TonalBalance,
            num_bands: 8,
            smoothing: 0.8,
            max_gain_db: 6.0,
            ..Default::default()
        }
    }

    /// Create brightness matching config
    pub fn brightness() -> Self {
        Self {
            mode: MatchMode::Brightness,
            min_freq: 2000.0,
            max_freq: 20000.0,
            num_bands: 16,
            smoothing: 0.6,
            max_gain_db: 8.0,
            ..Default::default()
        }
    }

    /// Create warmth matching config
    pub fn warmth() -> Self {
        Self {
            mode: MatchMode::Warmth,
            min_freq: 80.0,
            max_freq: 500.0,
            num_bands: 12,
            smoothing: 0.6,
            max_gain_db: 6.0,
            ..Default::default()
        }
    }

    /// Create high-precision matching config
    pub fn high_precision() -> Self {
        Self {
            mode: MatchMode::Full,
            num_bands: 64,
            smoothing: 0.3,
            max_gain_db: 15.0,
            fft_size: 8192,
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = MatchConfig::default();
        assert_eq!(config.num_bands, 32);
        assert!(config.max_freq > config.min_freq);
    }

    #[test]
    fn test_presets() {
        let tonal = MatchConfig::tonal_balance();
        let precise = MatchConfig::high_precision();

        assert!(tonal.smoothing > precise.smoothing);
        assert!(precise.num_bands > tonal.num_bands);
    }
}

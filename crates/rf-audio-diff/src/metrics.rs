//! Audio comparison metrics

use serde::{Deserialize, Serialize};

/// Time-domain metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeDomainMetrics {
    /// Maximum absolute sample difference
    pub peak_diff: f64,

    /// RMS of sample differences
    pub rms_diff: f64,

    /// Mean absolute difference
    pub mean_abs_diff: f64,

    /// Sample index with maximum difference
    pub peak_diff_sample: usize,

    /// Peak difference in dB
    pub peak_diff_db: f64,

    /// RMS difference in dB
    pub rms_diff_db: f64,
}

/// Spectral domain metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpectralMetrics {
    /// Average spectral difference in dB
    pub avg_spectral_diff_db: f64,

    /// Maximum spectral difference in dB
    pub max_spectral_diff_db: f64,

    /// Frequency (Hz) with maximum spectral difference
    pub max_diff_freq: f64,

    /// Average phase difference in radians
    pub avg_phase_diff: f64,

    /// Maximum phase difference in radians
    pub max_phase_diff: f64,

    /// Spectral correlation (0.0-1.0)
    pub spectral_correlation: f64,

    /// Per-band spectral differences (dB)
    pub band_diffs_db: Vec<f64>,

    /// Band center frequencies (Hz)
    pub band_centers: Vec<f64>,
}

/// Perceptual metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerceptualMetrics {
    /// A-weighted RMS difference
    pub a_weighted_rms_diff: f64,

    /// A-weighted RMS difference in dB
    pub a_weighted_rms_diff_db: f64,

    /// Loudness difference in LUFS (simplified)
    pub loudness_diff_lufs: f64,

    /// Spectral centroid difference (Hz)
    pub centroid_diff_hz: f64,

    /// Spectral flatness difference
    pub flatness_diff: f64,
}

/// Correlation metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CorrelationMetrics {
    /// Pearson correlation coefficient
    pub pearson: f64,

    /// Correlation at optimal lag
    pub max_correlation: f64,

    /// Lag (samples) for maximum correlation
    pub optimal_lag: i64,

    /// Cross-correlation energy ratio
    pub energy_ratio: f64,
}

/// Overall comparison metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComparisonMetrics {
    /// Time-domain metrics
    pub time_domain: TimeDomainMetrics,

    /// Spectral metrics
    pub spectral: SpectralMetrics,

    /// Perceptual metrics
    pub perceptual: PerceptualMetrics,

    /// Correlation metrics
    pub correlation: CorrelationMetrics,

    /// Duration difference in seconds
    pub duration_diff: f64,

    /// Sample rate (must match)
    pub sample_rate: u32,

    /// Number of channels
    pub num_channels: usize,
}

impl TimeDomainMetrics {
    /// Calculate time-domain metrics from two sample arrays
    pub fn calculate(reference: &[f64], test: &[f64]) -> Self {
        let len = reference.len().min(test.len());
        if len == 0 {
            return Self::zero();
        }

        let mut peak_diff = 0.0;
        let mut peak_diff_sample = 0;
        let mut sum_sq_diff = 0.0;
        let mut sum_abs_diff = 0.0;

        for i in 0..len {
            let diff = (reference[i] - test[i]).abs();
            sum_abs_diff += diff;
            sum_sq_diff += diff * diff;

            if diff > peak_diff {
                peak_diff = diff;
                peak_diff_sample = i;
            }
        }

        let mean_abs_diff = sum_abs_diff / len as f64;
        let rms_diff = (sum_sq_diff / len as f64).sqrt();

        Self {
            peak_diff,
            rms_diff,
            mean_abs_diff,
            peak_diff_sample,
            peak_diff_db: amplitude_to_db(peak_diff),
            rms_diff_db: amplitude_to_db(rms_diff),
        }
    }

    fn zero() -> Self {
        Self {
            peak_diff: 0.0,
            rms_diff: 0.0,
            mean_abs_diff: 0.0,
            peak_diff_sample: 0,
            peak_diff_db: f64::NEG_INFINITY,
            rms_diff_db: f64::NEG_INFINITY,
        }
    }
}

impl SpectralMetrics {
    /// Create empty spectral metrics
    pub fn zero(num_bands: usize) -> Self {
        Self {
            avg_spectral_diff_db: 0.0,
            max_spectral_diff_db: 0.0,
            max_diff_freq: 0.0,
            avg_phase_diff: 0.0,
            max_phase_diff: 0.0,
            spectral_correlation: 1.0,
            band_diffs_db: vec![0.0; num_bands],
            band_centers: vec![0.0; num_bands],
        }
    }
}

impl PerceptualMetrics {
    /// Create zero perceptual metrics
    pub fn zero() -> Self {
        Self {
            a_weighted_rms_diff: 0.0,
            a_weighted_rms_diff_db: f64::NEG_INFINITY,
            loudness_diff_lufs: 0.0,
            centroid_diff_hz: 0.0,
            flatness_diff: 0.0,
        }
    }
}

impl CorrelationMetrics {
    /// Calculate correlation between two signals
    pub fn calculate(reference: &[f64], test: &[f64]) -> Self {
        let len = reference.len().min(test.len());
        if len == 0 {
            return Self::zero();
        }

        // Calculate means
        let ref_mean: f64 = reference[..len].iter().sum::<f64>() / len as f64;
        let test_mean: f64 = test[..len].iter().sum::<f64>() / len as f64;

        // Calculate Pearson correlation
        let mut cov = 0.0;
        let mut ref_var = 0.0;
        let mut test_var = 0.0;

        for i in 0..len {
            let ref_diff = reference[i] - ref_mean;
            let test_diff = test[i] - test_mean;
            cov += ref_diff * test_diff;
            ref_var += ref_diff * ref_diff;
            test_var += test_diff * test_diff;
        }

        let std_product = (ref_var * test_var).sqrt();
        let pearson = if std_product > 0.0 {
            cov / std_product
        } else {
            1.0
        };

        // Energy ratio
        let ref_energy: f64 = reference[..len].iter().map(|s| s * s).sum();
        let test_energy: f64 = test[..len].iter().map(|s| s * s).sum();
        let energy_ratio = if ref_energy > 0.0 {
            test_energy / ref_energy
        } else {
            1.0
        };

        Self {
            pearson,
            max_correlation: pearson.abs(),
            optimal_lag: 0, // Simple implementation without lag search
            energy_ratio,
        }
    }

    fn zero() -> Self {
        Self {
            pearson: 1.0,
            max_correlation: 1.0,
            optimal_lag: 0,
            energy_ratio: 1.0,
        }
    }
}

impl ComparisonMetrics {
    /// Check if metrics pass all tolerances
    pub fn passes(&self, config: &super::config::DiffConfig) -> bool {
        self.time_domain.peak_diff <= config.peak_diff_tolerance
            && self.time_domain.rms_diff <= config.rms_diff_tolerance
            && self.spectral.avg_spectral_diff_db.abs() <= config.spectral_diff_db_tolerance
            && self.spectral.avg_phase_diff.abs() <= config.phase_diff_tolerance
            && self.duration_diff.abs() <= config.duration_tolerance_sec
            && self.correlation.pearson >= config.correlation_tolerance
    }

    /// Get human-readable summary
    pub fn summary(&self) -> String {
        format!(
            "Peak diff: {:.6} ({:.1} dB), RMS diff: {:.6} ({:.1} dB), \
             Spectral diff: {:.2} dB, Correlation: {:.6}",
            self.time_domain.peak_diff,
            self.time_domain.peak_diff_db,
            self.time_domain.rms_diff,
            self.time_domain.rms_diff_db,
            self.spectral.avg_spectral_diff_db,
            self.correlation.pearson
        )
    }

    /// Get detailed breakdown per metric
    pub fn detailed_breakdown(&self) -> Vec<(String, String, bool)> {
        vec![
            (
                "Peak Difference".into(),
                format!(
                    "{:.6} ({:.1} dB)",
                    self.time_domain.peak_diff, self.time_domain.peak_diff_db
                ),
                true,
            ),
            (
                "RMS Difference".into(),
                format!(
                    "{:.6} ({:.1} dB)",
                    self.time_domain.rms_diff, self.time_domain.rms_diff_db
                ),
                true,
            ),
            (
                "Spectral Difference".into(),
                format!(
                    "{:.2} dB avg, {:.2} dB max",
                    self.spectral.avg_spectral_diff_db, self.spectral.max_spectral_diff_db
                ),
                true,
            ),
            (
                "Phase Difference".into(),
                format!(
                    "{:.4} rad avg ({:.1}°)",
                    self.spectral.avg_phase_diff,
                    self.spectral.avg_phase_diff.to_degrees()
                ),
                true,
            ),
            (
                "Correlation".into(),
                format!("{:.6} (Pearson)", self.correlation.pearson),
                true,
            ),
            (
                "Duration Difference".into(),
                format!("{:.3} ms", self.duration_diff * 1000.0),
                true,
            ),
        ]
    }
}

/// Convert linear amplitude to dB
fn amplitude_to_db(amplitude: f64) -> f64 {
    if amplitude <= 0.0 {
        f64::NEG_INFINITY
    } else {
        20.0 * amplitude.log10()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_time_domain_identical() {
        let samples = vec![0.5, -0.3, 0.8, -0.2];
        let metrics = TimeDomainMetrics::calculate(&samples, &samples);

        assert_eq!(metrics.peak_diff, 0.0);
        assert_eq!(metrics.rms_diff, 0.0);
    }

    #[test]
    fn test_time_domain_different() {
        let reference = vec![1.0, 0.0, -1.0, 0.0];
        let test = vec![0.9, 0.1, -0.9, 0.1];
        let metrics = TimeDomainMetrics::calculate(&reference, &test);

        assert!((metrics.peak_diff - 0.1).abs() < 0.001);
        assert!(metrics.rms_diff > 0.0);
    }

    #[test]
    fn test_correlation_identical() {
        let samples = vec![0.5, -0.3, 0.8, -0.2, 0.1];
        let metrics = CorrelationMetrics::calculate(&samples, &samples);

        assert!((metrics.pearson - 1.0).abs() < 0.001);
        assert!((metrics.energy_ratio - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_correlation_inverted() {
        let reference = vec![1.0, 0.5, 0.0, -0.5, -1.0];
        let test: Vec<f64> = reference.iter().map(|&s| -s).collect();
        let metrics = CorrelationMetrics::calculate(&reference, &test);

        assert!((metrics.pearson - (-1.0)).abs() < 0.001);
    }
}

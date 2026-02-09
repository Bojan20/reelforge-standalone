//! Main audio diff API

use crate::analysis::{compute_comparison_metrics, AudioAnalysis};
use crate::config::DiffConfig;
use crate::loader::AudioData;
use crate::metrics::ComparisonMetrics;
use crate::{AudioDiffError, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Result of comparing two audio files
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffResult {
    /// Reference file path
    pub reference_path: String,

    /// Test file path
    pub test_path: String,

    /// Whether the comparison passed all tolerances
    pub passed: bool,

    /// Detailed comparison metrics
    pub metrics: ComparisonMetrics,

    /// Individual check results
    pub checks: Vec<DiffCheck>,

    /// Configuration used for comparison
    pub config: DiffConfig,

    /// Reference audio info
    pub reference_info: AudioInfo,

    /// Test audio info
    pub test_info: AudioInfo,
}

/// Individual check result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffCheck {
    /// Check name
    pub name: String,

    /// Whether this check passed
    pub passed: bool,

    /// Actual value
    pub actual: f64,

    /// Tolerance (threshold)
    pub tolerance: f64,

    /// Human-readable description
    pub description: String,
}

/// Basic audio file information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioInfo {
    /// File path
    pub path: String,

    /// Sample rate (Hz)
    pub sample_rate: u32,

    /// Number of channels
    pub num_channels: usize,

    /// Duration in seconds
    pub duration: f64,

    /// Number of samples per channel
    pub num_samples: usize,

    /// Peak level (0.0-1.0)
    pub peak: f64,

    /// RMS level (0.0-1.0)
    pub rms: f64,

    /// Peak level in dB
    pub peak_db: f64,

    /// RMS level in dB
    pub rms_db: f64,
}

impl From<&AudioAnalysis> for AudioInfo {
    fn from(analysis: &AudioAnalysis) -> Self {
        Self {
            path: analysis.audio.source_path.clone(),
            sample_rate: analysis.audio.sample_rate,
            num_channels: analysis.audio.num_channels,
            duration: analysis.audio.duration,
            num_samples: analysis.audio.num_samples,
            peak: analysis.peak_levels.iter().copied().fold(0.0, f64::max),
            rms: analysis.rms_levels.iter().copied().fold(0.0, f64::max),
            peak_db: analysis.peak_db,
            rms_db: analysis.rms_db,
        }
    }
}

impl DiffResult {
    /// Check if the comparison passed all tolerances
    pub fn is_pass(&self) -> bool {
        self.passed
    }

    /// Get a summary string
    pub fn summary(&self) -> String {
        if self.passed {
            format!(
                "PASS: {} vs {} - All checks passed",
                self.reference_path, self.test_path
            )
        } else {
            let failed: Vec<&str> = self
                .checks
                .iter()
                .filter(|c| !c.passed)
                .map(|c| c.name.as_str())
                .collect();
            format!(
                "FAIL: {} vs {} - Failed checks: {}",
                self.reference_path,
                self.test_path,
                failed.join(", ")
            )
        }
    }

    /// Get detailed report
    pub fn detailed_report(&self) -> String {
        let mut report = String::new();

        report.push_str(&format!("Audio Diff Report\n"));
        report.push_str(&format!("================\n\n"));

        report.push_str(&format!(
            "Result: {}\n\n",
            if self.passed { "PASS ✓" } else { "FAIL ✗" }
        ));

        report.push_str("Reference:\n");
        report.push_str(&format!("  Path: {}\n", self.reference_info.path));
        report.push_str(&format!(
            "  Sample Rate: {} Hz\n",
            self.reference_info.sample_rate
        ));
        report.push_str(&format!(
            "  Channels: {}\n",
            self.reference_info.num_channels
        ));
        report.push_str(&format!(
            "  Duration: {:.3} s\n",
            self.reference_info.duration
        ));
        report.push_str(&format!("  Peak: {:.1} dB\n", self.reference_info.peak_db));
        report.push_str(&format!("  RMS: {:.1} dB\n\n", self.reference_info.rms_db));

        report.push_str("Test:\n");
        report.push_str(&format!("  Path: {}\n", self.test_info.path));
        report.push_str(&format!(
            "  Sample Rate: {} Hz\n",
            self.test_info.sample_rate
        ));
        report.push_str(&format!("  Channels: {}\n", self.test_info.num_channels));
        report.push_str(&format!("  Duration: {:.3} s\n", self.test_info.duration));
        report.push_str(&format!("  Peak: {:.1} dB\n", self.test_info.peak_db));
        report.push_str(&format!("  RMS: {:.1} dB\n\n", self.test_info.rms_db));

        report.push_str("Checks:\n");
        for check in &self.checks {
            let status = if check.passed { "✓" } else { "✗" };
            report.push_str(&format!(
                "  {} {} - {}\n",
                status, check.name, check.description
            ));
        }

        report.push_str("\nMetrics Summary:\n");
        report.push_str(&format!("  {}\n", self.metrics.summary()));

        report
    }
}

/// Main audio diff comparison
pub struct AudioDiff;

impl AudioDiff {
    /// Compare two audio files
    pub fn compare<P: AsRef<Path>>(
        reference_path: P,
        test_path: P,
        config: &DiffConfig,
    ) -> Result<DiffResult> {
        let reference_path = reference_path.as_ref();
        let test_path = test_path.as_ref();

        // Load audio files
        let reference_audio = AudioData::load(reference_path)?;
        let test_audio = AudioData::load(test_path)?;

        Self::compare_audio(reference_audio, test_audio, config)
    }

    /// Compare two AudioData instances
    pub fn compare_audio(
        reference_audio: AudioData,
        test_audio: AudioData,
        config: &DiffConfig,
    ) -> Result<DiffResult> {
        // Validate sample rates
        if !config.allow_sample_rate_conversion
            && reference_audio.sample_rate != test_audio.sample_rate
        {
            return Err(AudioDiffError::SampleRateMismatch(
                reference_audio.sample_rate,
                test_audio.sample_rate,
            ));
        }

        // Validate channel counts
        if reference_audio.num_channels != test_audio.num_channels && !config.compare_mono {
            return Err(AudioDiffError::ChannelMismatch(
                reference_audio.num_channels,
                test_audio.num_channels,
            ));
        }

        // Check duration
        let duration_diff = (reference_audio.duration - test_audio.duration).abs();
        if duration_diff > config.duration_tolerance_sec {
            return Err(AudioDiffError::DurationMismatch(
                reference_audio.duration,
                test_audio.duration,
                config.duration_tolerance_sec,
            ));
        }

        let ref_path = reference_audio.source_path.clone();
        let test_path = test_audio.source_path.clone();

        // Analyze both files
        let ref_analysis = AudioAnalysis::new(reference_audio, config)?;
        let test_analysis = AudioAnalysis::new(test_audio, config)?;

        // Compute comparison metrics
        let metrics = compute_comparison_metrics(&ref_analysis, &test_analysis, config)?;

        // Build individual checks
        let checks = Self::build_checks(&metrics, config);

        // Determine overall pass/fail
        let passed = checks.iter().all(|c| c.passed);

        Ok(DiffResult {
            reference_path: ref_path,
            test_path,
            passed,
            metrics,
            checks,
            config: config.clone(),
            reference_info: AudioInfo::from(&ref_analysis),
            test_info: AudioInfo::from(&test_analysis),
        })
    }

    fn build_checks(metrics: &ComparisonMetrics, config: &DiffConfig) -> Vec<DiffCheck> {
        let mut checks = Vec::new();

        // Peak difference
        checks.push(DiffCheck {
            name: "peak_diff".into(),
            passed: metrics.time_domain.peak_diff <= config.peak_diff_tolerance,
            actual: metrics.time_domain.peak_diff,
            tolerance: config.peak_diff_tolerance,
            description: format!(
                "Peak sample diff: {:.6} (tolerance: {:.6})",
                metrics.time_domain.peak_diff, config.peak_diff_tolerance
            ),
        });

        // RMS difference
        checks.push(DiffCheck {
            name: "rms_diff".into(),
            passed: metrics.time_domain.rms_diff <= config.rms_diff_tolerance,
            actual: metrics.time_domain.rms_diff,
            tolerance: config.rms_diff_tolerance,
            description: format!(
                "RMS diff: {:.6} (tolerance: {:.6})",
                metrics.time_domain.rms_diff, config.rms_diff_tolerance
            ),
        });

        // Spectral difference
        checks.push(DiffCheck {
            name: "spectral_diff".into(),
            passed: metrics.spectral.avg_spectral_diff_db.abs()
                <= config.spectral_diff_db_tolerance,
            actual: metrics.spectral.avg_spectral_diff_db,
            tolerance: config.spectral_diff_db_tolerance,
            description: format!(
                "Avg spectral diff: {:.2} dB (tolerance: {:.2} dB)",
                metrics.spectral.avg_spectral_diff_db, config.spectral_diff_db_tolerance
            ),
        });

        // Phase difference
        checks.push(DiffCheck {
            name: "phase_diff".into(),
            passed: metrics.spectral.avg_phase_diff.abs() <= config.phase_diff_tolerance,
            actual: metrics.spectral.avg_phase_diff,
            tolerance: config.phase_diff_tolerance,
            description: format!(
                "Avg phase diff: {:.4} rad (tolerance: {:.4} rad)",
                metrics.spectral.avg_phase_diff, config.phase_diff_tolerance
            ),
        });

        // Correlation
        checks.push(DiffCheck {
            name: "correlation".into(),
            passed: metrics.correlation.pearson >= config.correlation_tolerance,
            actual: metrics.correlation.pearson,
            tolerance: config.correlation_tolerance,
            description: format!(
                "Correlation: {:.6} (min: {:.6})",
                metrics.correlation.pearson, config.correlation_tolerance
            ),
        });

        // Duration difference
        checks.push(DiffCheck {
            name: "duration_diff".into(),
            passed: metrics.duration_diff.abs() <= config.duration_tolerance_sec,
            actual: metrics.duration_diff.abs(),
            tolerance: config.duration_tolerance_sec,
            description: format!(
                "Duration diff: {:.3} ms (tolerance: {:.3} ms)",
                metrics.duration_diff * 1000.0,
                config.duration_tolerance_sec * 1000.0
            ),
        });

        checks
    }

    /// Compare sample arrays directly (for in-memory testing)
    pub fn compare_samples(
        reference: &[f64],
        test: &[f64],
        sample_rate: u32,
        config: &DiffConfig,
    ) -> Result<DiffResult> {
        let ref_audio = AudioData {
            channels: vec![reference.to_vec()],
            sample_rate,
            num_channels: 1,
            num_samples: reference.len(),
            duration: reference.len() as f64 / sample_rate as f64,
            source_path: "reference".into(),
        };

        let test_audio = AudioData {
            channels: vec![test.to_vec()],
            sample_rate,
            num_channels: 1,
            num_samples: test.len(),
            duration: test.len() as f64 / sample_rate as f64,
            source_path: "test".into(),
        };

        Self::compare_audio(ref_audio, test_audio, config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identical_samples() {
        let samples: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        let result =
            AudioDiff::compare_samples(&samples, &samples, 44100, &DiffConfig::default()).unwrap();

        assert!(result.is_pass());
        assert!(result.metrics.time_domain.peak_diff < 1e-10);
    }

    #[test]
    fn test_different_samples() {
        let reference: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        let test: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * 880.0 * i as f64 / 44100.0).sin())
            .collect();

        let result =
            AudioDiff::compare_samples(&reference, &test, 44100, &DiffConfig::default()).unwrap();

        // Different frequencies should fail strict comparison
        assert!(!result.is_pass());
    }

    #[test]
    fn test_small_amplitude_difference() {
        let reference: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        // Very small amplitude difference
        let test: Vec<f64> = reference.iter().map(|&s| s * 0.9999).collect();

        let result = AudioDiff::compare_samples(
            &reference,
            &test,
            44100,
            &DiffConfig::perceptual(), // More relaxed
        )
        .unwrap();

        // Should pass with perceptual config
        assert!(result.is_pass());
    }

    #[test]
    fn test_diff_report() {
        let samples: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        let result =
            AudioDiff::compare_samples(&samples, &samples, 44100, &DiffConfig::default()).unwrap();

        let report = result.detailed_report();
        assert!(report.contains("PASS"));
        assert!(report.contains("Sample Rate: 44100"));
    }
}

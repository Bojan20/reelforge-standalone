//! Determinism validation for audio processing
//!
//! This module provides tools to verify that audio processing functions
//! produce bit-exact results when run multiple times with the same inputs.

use crate::config::DiffConfig;
use crate::diff::AudioDiff;
use crate::loader::AudioData;
use crate::Result;
use serde::{Deserialize, Serialize};
use std::time::Instant;

/// Configuration for determinism testing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeterminismConfig {
    /// Number of runs to compare
    pub num_runs: usize,

    /// Whether to check bit-exact equality (vs tolerance-based)
    pub bit_exact: bool,

    /// Tolerance for non-bit-exact comparison
    pub tolerance: f64,

    /// Whether to randomize run order
    pub randomize_order: bool,

    /// Include timing measurements
    pub measure_timing: bool,

    /// Verbose output
    pub verbose: bool,
}

impl Default for DeterminismConfig {
    fn default() -> Self {
        Self {
            num_runs: 3,
            bit_exact: true,
            tolerance: 0.0,
            randomize_order: false,
            measure_timing: true,
            verbose: false,
        }
    }
}

impl DeterminismConfig {
    /// Strict bit-exact configuration
    pub fn strict() -> Self {
        Self {
            num_runs: 5,
            bit_exact: true,
            tolerance: 0.0,
            ..Default::default()
        }
    }

    /// Relaxed configuration (allows small differences)
    pub fn relaxed() -> Self {
        Self {
            num_runs: 3,
            bit_exact: false,
            tolerance: 1e-10,
            ..Default::default()
        }
    }

    /// Builder: set number of runs
    pub fn with_num_runs(mut self, n: usize) -> Self {
        self.num_runs = n;
        self
    }

    /// Builder: enable/disable bit-exact mode
    pub fn with_bit_exact(mut self, exact: bool) -> Self {
        self.bit_exact = exact;
        self
    }

    /// Builder: set tolerance
    pub fn with_tolerance(mut self, tol: f64) -> Self {
        self.tolerance = tol;
        self
    }
}

/// Result of a determinism test
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeterminismResult {
    /// Whether the test passed (all runs produced same output)
    pub passed: bool,

    /// Number of runs performed
    pub num_runs: usize,

    /// Number of runs that matched the reference
    pub matching_runs: usize,

    /// Maximum difference found between runs
    pub max_diff: f64,

    /// Average difference across all comparisons
    pub avg_diff: f64,

    /// Sample index with maximum difference
    pub max_diff_sample: Option<usize>,

    /// Timing information per run (if measured)
    pub run_timings_ms: Vec<f64>,

    /// Average execution time
    pub avg_time_ms: f64,

    /// Timing variance (std dev / mean)
    pub timing_variance: f64,

    /// Detailed comparison results
    pub comparisons: Vec<DeterminismComparison>,
}

/// Comparison between two runs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeterminismComparison {
    /// Run A index
    pub run_a: usize,

    /// Run B index
    pub run_b: usize,

    /// Whether runs matched
    pub matched: bool,

    /// Peak sample difference
    pub peak_diff: f64,

    /// RMS difference
    pub rms_diff: f64,

    /// Sample index of peak difference
    pub peak_diff_sample: usize,
}

/// Determinism validator
pub struct DeterminismValidator {
    config: DeterminismConfig,
}

impl DeterminismValidator {
    /// Create a new validator
    pub fn new(config: DeterminismConfig) -> Self {
        Self { config }
    }

    /// Validate that a function produces deterministic results
    ///
    /// The function takes input samples and returns output samples.
    pub fn validate<F>(&self, input: &[f64], process_fn: F) -> DeterminismResult
    where
        F: Fn(&[f64]) -> Vec<f64>,
    {
        let mut outputs: Vec<Vec<f64>> = Vec::with_capacity(self.config.num_runs);
        let mut timings: Vec<f64> = Vec::with_capacity(self.config.num_runs);

        // Run the function multiple times
        for _ in 0..self.config.num_runs {
            let start = Instant::now();
            let output = process_fn(input);
            let duration = start.elapsed().as_secs_f64() * 1000.0;

            if self.config.measure_timing {
                timings.push(duration);
            }

            outputs.push(output);
        }

        // Compare all pairs
        let mut comparisons = Vec::new();
        let mut max_diff = 0.0;
        let mut max_diff_sample = None;
        let mut total_diff = 0.0;
        let mut comparison_count = 0;

        let reference = &outputs[0];

        for (i, output) in outputs.iter().enumerate().skip(1) {
            let (peak_diff, peak_sample, rms_diff) = compare_samples(reference, output);

            if peak_diff > max_diff {
                max_diff = peak_diff;
                max_diff_sample = Some(peak_sample);
            }

            total_diff += peak_diff;
            comparison_count += 1;

            let matched = if self.config.bit_exact {
                peak_diff == 0.0
            } else {
                peak_diff <= self.config.tolerance
            };

            comparisons.push(DeterminismComparison {
                run_a: 0,
                run_b: i,
                matched,
                peak_diff,
                rms_diff,
                peak_diff_sample: peak_sample,
            });
        }

        // Calculate timing statistics
        let avg_time_ms = if !timings.is_empty() {
            timings.iter().sum::<f64>() / timings.len() as f64
        } else {
            0.0
        };

        let timing_variance = if timings.len() > 1 && avg_time_ms > 0.0 {
            let variance: f64 = timings
                .iter()
                .map(|t| (t - avg_time_ms).powi(2))
                .sum::<f64>()
                / (timings.len() - 1) as f64;
            variance.sqrt() / avg_time_ms
        } else {
            0.0
        };

        let matching_runs = comparisons.iter().filter(|c| c.matched).count() + 1; // +1 for reference
        let avg_diff = if comparison_count > 0 {
            total_diff / comparison_count as f64
        } else {
            0.0
        };

        let passed = comparisons.iter().all(|c| c.matched);

        DeterminismResult {
            passed,
            num_runs: self.config.num_runs,
            matching_runs,
            max_diff,
            avg_diff,
            max_diff_sample,
            run_timings_ms: timings,
            avg_time_ms,
            timing_variance,
            comparisons,
        }
    }

    /// Validate determinism for audio files
    pub fn validate_audio_process<F>(
        &self,
        input: &AudioData,
        process_fn: F,
    ) -> Result<DeterminismResult>
    where
        F: Fn(&AudioData) -> AudioData,
    {
        let mut outputs: Vec<AudioData> = Vec::with_capacity(self.config.num_runs);
        let mut timings: Vec<f64> = Vec::with_capacity(self.config.num_runs);

        // Run the function multiple times
        for _ in 0..self.config.num_runs {
            let start = Instant::now();
            let output = process_fn(input);
            let duration = start.elapsed().as_secs_f64() * 1000.0;

            if self.config.measure_timing {
                timings.push(duration);
            }

            outputs.push(output);
        }

        // Compare using AudioDiff
        let diff_config = if self.config.bit_exact {
            DiffConfig::strict()
        } else {
            DiffConfig::dsp_regression().with_peak_tolerance(self.config.tolerance)
        };

        let mut comparisons = Vec::new();
        let mut max_diff = 0.0;
        let mut max_diff_sample = None;
        let mut total_diff = 0.0;

        let reference = &outputs[0];

        for (i, output) in outputs.iter().enumerate().skip(1) {
            let diff_result =
                AudioDiff::compare_audio(reference.clone(), output.clone(), &diff_config)?;

            let peak_diff = diff_result.metrics.time_domain.peak_diff;
            let rms_diff = diff_result.metrics.time_domain.rms_diff;
            let peak_sample = diff_result.metrics.time_domain.peak_diff_sample;

            if peak_diff > max_diff {
                max_diff = peak_diff;
                max_diff_sample = Some(peak_sample);
            }

            total_diff += peak_diff;

            comparisons.push(DeterminismComparison {
                run_a: 0,
                run_b: i,
                matched: diff_result.passed,
                peak_diff,
                rms_diff,
                peak_diff_sample: peak_sample,
            });
        }

        let avg_time_ms = if !timings.is_empty() {
            timings.iter().sum::<f64>() / timings.len() as f64
        } else {
            0.0
        };

        let timing_variance = if timings.len() > 1 && avg_time_ms > 0.0 {
            let variance: f64 = timings
                .iter()
                .map(|t| (t - avg_time_ms).powi(2))
                .sum::<f64>()
                / (timings.len() - 1) as f64;
            variance.sqrt() / avg_time_ms
        } else {
            0.0
        };

        let matching_runs = comparisons.iter().filter(|c| c.matched).count() + 1;
        let avg_diff = if !comparisons.is_empty() {
            total_diff / comparisons.len() as f64
        } else {
            0.0
        };

        let passed = comparisons.iter().all(|c| c.matched);

        Ok(DeterminismResult {
            passed,
            num_runs: self.config.num_runs,
            matching_runs,
            max_diff,
            avg_diff,
            max_diff_sample,
            run_timings_ms: timings,
            avg_time_ms,
            timing_variance,
            comparisons,
        })
    }
}

impl DeterminismResult {
    /// Get summary string
    pub fn summary(&self) -> String {
        let status = if self.passed { "PASS" } else { "FAIL" };
        format!(
            "{}: {}/{} runs matched (max diff: {:.2e}, avg time: {:.2}ms)",
            status, self.matching_runs, self.num_runs, self.max_diff, self.avg_time_ms
        )
    }

    /// Generate detailed report
    pub fn detailed_report(&self) -> String {
        let mut report = String::new();

        report.push_str(&format!("Determinism Test Report\n"));
        report.push_str(&format!("=======================\n\n"));

        report.push_str(&format!(
            "Status: {}\n",
            if self.passed { "PASS ✓" } else { "FAIL ✗" }
        ));
        report.push_str(&format!("Runs: {}\n", self.num_runs));
        report.push_str(&format!("Matching: {}\n", self.matching_runs));
        report.push_str(&format!("Max Diff: {:.2e}\n", self.max_diff));
        report.push_str(&format!("Avg Diff: {:.2e}\n", self.avg_diff));

        if let Some(sample) = self.max_diff_sample {
            report.push_str(&format!("Max Diff at Sample: {}\n", sample));
        }

        report.push_str(&format!("\nTiming:\n"));
        report.push_str(&format!("  Avg: {:.2} ms\n", self.avg_time_ms));
        report.push_str(&format!(
            "  Variance: {:.2}%\n",
            self.timing_variance * 100.0
        ));

        if !self.run_timings_ms.is_empty() {
            report.push_str(&format!("  Runs: {:?}\n", self.run_timings_ms));
        }

        if !self.passed {
            report.push_str(&format!("\nFailed Comparisons:\n"));
            for comp in &self.comparisons {
                if !comp.matched {
                    report.push_str(&format!(
                        "  Run {} vs Run {}: peak={:.2e}, rms={:.2e}, sample={}\n",
                        comp.run_a,
                        comp.run_b,
                        comp.peak_diff,
                        comp.rms_diff,
                        comp.peak_diff_sample
                    ));
                }
            }
        }

        report
    }
}

/// Compare two sample arrays and return (peak_diff, peak_sample, rms_diff)
fn compare_samples(a: &[f64], b: &[f64]) -> (f64, usize, f64) {
    let len = a.len().min(b.len());
    if len == 0 {
        return (0.0, 0, 0.0);
    }

    let mut peak_diff = 0.0;
    let mut peak_sample = 0;
    let mut sum_sq_diff = 0.0;

    for i in 0..len {
        let diff = (a[i] - b[i]).abs();
        sum_sq_diff += diff * diff;

        if diff > peak_diff {
            peak_diff = diff;
            peak_sample = i;
        }
    }

    let rms_diff = (sum_sq_diff / len as f64).sqrt();

    (peak_diff, peak_sample, rms_diff)
}

/// Quick determinism check with default settings
pub fn check_determinism<F>(input: &[f64], process_fn: F) -> bool
where
    F: Fn(&[f64]) -> Vec<f64>,
{
    let validator = DeterminismValidator::new(DeterminismConfig::default());
    validator.validate(input, process_fn).passed
}

/// Check determinism with strict settings
pub fn check_determinism_strict<F>(
    input: &[f64],
    process_fn: F,
    num_runs: usize,
) -> DeterminismResult
where
    F: Fn(&[f64]) -> Vec<f64>,
{
    let config = DeterminismConfig::strict().with_num_runs(num_runs);
    let validator = DeterminismValidator::new(config);
    validator.validate(input, process_fn)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deterministic_function() {
        // A deterministic function (simple gain)
        let input: Vec<f64> = (0..1000).map(|i| (i as f64 / 100.0).sin()).collect();

        let result = check_determinism_strict(
            &input,
            |samples| samples.iter().map(|s| s * 0.5).collect(),
            5,
        );

        assert!(result.passed);
        assert_eq!(result.matching_runs, 5);
        assert_eq!(result.max_diff, 0.0);
    }

    #[test]
    fn test_non_deterministic_function() {
        use std::time::{SystemTime, UNIX_EPOCH};

        // A non-deterministic function (uses system time as noise)
        let input: Vec<f64> = vec![0.0; 100];

        let result = check_determinism_strict(
            &input,
            |samples| {
                let noise = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .subsec_nanos() as f64
                    / 1e15; // Very small noise
                samples.iter().map(|s| s + noise).collect()
            },
            3,
        );

        // May or may not pass depending on timing
        // Just check it runs without panic
        assert!(result.num_runs == 3);
    }

    #[test]
    fn test_determinism_config() {
        let config = DeterminismConfig::default()
            .with_num_runs(10)
            .with_bit_exact(false)
            .with_tolerance(1e-6);

        assert_eq!(config.num_runs, 10);
        assert!(!config.bit_exact);
        assert_eq!(config.tolerance, 1e-6);
    }

    #[test]
    fn test_compare_samples() {
        let a = vec![1.0, 2.0, 3.0, 4.0];
        let b = vec![1.0, 2.1, 3.0, 4.0];

        let (peak, sample, rms) = compare_samples(&a, &b);

        assert!((peak - 0.1).abs() < 0.001);
        assert_eq!(sample, 1);
        assert!(rms > 0.0);
    }
}

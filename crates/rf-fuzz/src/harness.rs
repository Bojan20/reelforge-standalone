//! Fuzzing harness and runner

use crate::config::FuzzConfig;
use crate::generators::InputGenerator;
use serde::{Deserialize, Serialize};
use std::panic::{self, AssertUnwindSafe};
use std::time::{Duration, Instant};

/// Result of a fuzzing run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FuzzResult {
    /// Total iterations run
    pub iterations: usize,

    /// Number of successful iterations
    pub successes: usize,

    /// Number of failures
    pub failures: usize,

    /// Number of panics caught
    pub panics: usize,

    /// Number of timeouts
    pub timeouts: usize,

    /// Total duration
    pub duration_ms: u64,

    /// Seed used (for reproducibility)
    pub seed: Option<u64>,

    /// List of failures with details
    pub failure_details: Vec<FuzzFailure>,

    /// Whether all iterations passed
    pub passed: bool,
}

/// Details of a fuzzing failure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FuzzFailure {
    /// Iteration number when failure occurred
    pub iteration: usize,

    /// Type of failure
    pub failure_type: FailureType,

    /// Description of the failure
    pub description: String,

    /// Input that caused the failure (serialized)
    pub input: String,

    /// Stack trace if available
    pub backtrace: Option<String>,
}

/// Type of fuzzing failure
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum FailureType {
    Panic,
    InvalidOutput,
    Timeout,
    AssertionFailed,
}

/// Trait for fuzz targets
pub trait FuzzTarget<I, O> {
    /// Run the target with given input
    fn run(&self, input: I) -> O;

    /// Validate the output (default: always valid)
    fn validate(&self, _input: &I, _output: &O) -> Result<(), String> {
        Ok(())
    }
}

/// Main fuzzing runner
pub struct FuzzRunner {
    config: FuzzConfig,
}

impl FuzzRunner {
    /// Create a new fuzzing runner
    pub fn new(config: FuzzConfig) -> Self {
        Self { config }
    }

    /// Fuzz with byte inputs
    pub fn fuzz_bytes<F, R>(&self, target: F) -> FuzzResult
    where
        F: Fn(Vec<u8>) -> R + panic::RefUnwindSafe,
    {
        self.fuzz_internal(|gen| gen.bytes(self.config.max_input_size), target)
    }

    /// Fuzz with f64 inputs
    pub fn fuzz_f64<F, R>(&self, target: F) -> FuzzResult
    where
        F: Fn(f64) -> R + panic::RefUnwindSafe,
    {
        self.fuzz_internal(|gen| gen.f64(), target)
    }

    /// Fuzz with i32 inputs
    pub fn fuzz_i32<F, R>(&self, target: F) -> FuzzResult
    where
        F: Fn(i32) -> R + panic::RefUnwindSafe,
    {
        self.fuzz_internal(|gen| gen.i32(), target)
    }

    /// Fuzz with audio buffer inputs
    pub fn fuzz_audio<F, R>(&self, buffer_size: usize, target: F) -> FuzzResult
    where
        F: Fn(Vec<f64>) -> R + panic::RefUnwindSafe,
    {
        self.fuzz_internal(|gen| gen.audio_samples(buffer_size), target)
    }

    /// Fuzz with custom input generator
    pub fn fuzz_custom<I, F, G, R>(&self, input_gen: G, target: F) -> FuzzResult
    where
        I: std::fmt::Debug + Clone,
        G: Fn(&mut InputGenerator) -> I,
        F: Fn(I) -> R + panic::RefUnwindSafe,
    {
        self.fuzz_internal(input_gen, target)
    }

    /// Internal fuzzing loop
    fn fuzz_internal<I, F, G, R>(&self, input_gen: G, target: F) -> FuzzResult
    where
        I: std::fmt::Debug,
        G: Fn(&mut InputGenerator) -> I,
        F: Fn(I) -> R + panic::RefUnwindSafe,
    {
        let mut generator = InputGenerator::new(self.config.seed, self.config.max_input_size)
            .with_edge_cases(self.config.include_edge_cases)
            .with_boundaries(self.config.include_boundaries);

        let mut successes = 0;
        let mut failures = 0;
        let mut panics = 0;
        let timeouts = 0;
        let mut failure_details = Vec::new();

        let start = Instant::now();
        let _timeout = Duration::from_millis(self.config.timeout_ms);

        for iteration in 0..self.config.iterations {
            // Check if we've hit max failures
            if !self.config.continue_on_failure && failures > 0 {
                break;
            }
            if failure_details.len() >= self.config.max_failures {
                break;
            }

            // Generate input
            let input = input_gen(&mut generator);
            let input_str = format!("{:?}", input);

            // Run target with panic catching
            let result = panic::catch_unwind(AssertUnwindSafe(|| {
                let _start = Instant::now();
                target(input)
            }));

            match result {
                Ok(_) => {
                    successes += 1;
                }
                Err(panic_info) => {
                    panics += 1;
                    failures += 1;

                    let description = if let Some(s) = panic_info.downcast_ref::<&str>() {
                        s.to_string()
                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        "Unknown panic".to_string()
                    };

                    failure_details.push(FuzzFailure {
                        iteration,
                        failure_type: FailureType::Panic,
                        description,
                        input: input_str,
                        backtrace: None,
                    });

                    if self.config.verbosity >= 1 {
                        eprintln!(
                            "Panic at iteration {}: {}",
                            iteration,
                            failure_details.last().unwrap().description
                        );
                    }
                }
            }
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        FuzzResult {
            iterations: successes + failures,
            successes,
            failures,
            panics,
            timeouts,
            duration_ms,
            seed: self.config.seed,
            failure_details,
            passed: failures == 0,
        }
    }

    /// Fuzz with output validation
    pub fn fuzz_with_validation<I, O, F, G, V>(
        &self,
        input_gen: G,
        target: F,
        validator: V,
    ) -> FuzzResult
    where
        I: std::fmt::Debug + Clone,
        O: std::fmt::Debug,
        G: Fn(&mut InputGenerator) -> I,
        F: Fn(I) -> O + panic::RefUnwindSafe,
        V: Fn(&I, &O) -> Result<(), String>,
    {
        let mut generator = InputGenerator::new(self.config.seed, self.config.max_input_size)
            .with_edge_cases(self.config.include_edge_cases)
            .with_boundaries(self.config.include_boundaries);

        let mut successes = 0;
        let mut failures = 0;
        let mut panics = 0;
        let mut failure_details = Vec::new();

        let start = Instant::now();

        for iteration in 0..self.config.iterations {
            if !self.config.continue_on_failure && failures > 0 {
                break;
            }
            if failure_details.len() >= self.config.max_failures {
                break;
            }

            let input = input_gen(&mut generator);
            let input_str = format!("{:?}", input);
            let input_clone = input.clone();

            let result = panic::catch_unwind(AssertUnwindSafe(|| target(input)));

            match result {
                Ok(output) => {
                    // Validate output
                    match validator(&input_clone, &output) {
                        Ok(()) => {
                            successes += 1;
                        }
                        Err(validation_error) => {
                            failures += 1;
                            failure_details.push(FuzzFailure {
                                iteration,
                                failure_type: FailureType::InvalidOutput,
                                description: validation_error,
                                input: input_str,
                                backtrace: None,
                            });
                        }
                    }
                }
                Err(panic_info) => {
                    panics += 1;
                    failures += 1;

                    let description = if let Some(s) = panic_info.downcast_ref::<&str>() {
                        s.to_string()
                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        "Unknown panic".to_string()
                    };

                    failure_details.push(FuzzFailure {
                        iteration,
                        failure_type: FailureType::Panic,
                        description,
                        input: input_str,
                        backtrace: None,
                    });
                }
            }
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        FuzzResult {
            iterations: successes + failures,
            successes,
            failures,
            panics,
            timeouts: 0,
            duration_ms,
            seed: self.config.seed,
            failure_details,
            passed: failures == 0,
        }
    }
}

impl FuzzResult {
    /// Check if the fuzzing run passed
    pub fn is_pass(&self) -> bool {
        self.passed
    }

    /// Get pass rate
    pub fn pass_rate(&self) -> f64 {
        if self.iterations == 0 {
            1.0
        } else {
            self.successes as f64 / self.iterations as f64
        }
    }

    /// Get iterations per second
    pub fn iterations_per_sec(&self) -> f64 {
        if self.duration_ms == 0 {
            0.0
        } else {
            self.iterations as f64 * 1000.0 / self.duration_ms as f64
        }
    }

    /// Get summary string
    pub fn summary(&self) -> String {
        format!(
            "{} - {} iterations, {} failures ({:.2}% pass rate) in {}ms ({:.0} iter/s)",
            if self.passed { "PASS" } else { "FAIL" },
            self.iterations,
            self.failures,
            self.pass_rate() * 100.0,
            self.duration_ms,
            self.iterations_per_sec()
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fuzz_f64_no_panic() {
        let config = FuzzConfig::minimal().with_seed(42);
        let runner = FuzzRunner::new(config);

        // Function that doesn't panic
        let result = runner.fuzz_f64(|x| x * 2.0);

        assert!(result.passed);
        assert_eq!(result.failures, 0);
    }

    #[test]
    fn test_fuzz_catches_panic() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(100);
        let runner = FuzzRunner::new(config);

        // Function that panics on NaN
        let result = runner.fuzz_f64(|x| {
            if x.is_nan() {
                panic!("NaN not allowed!");
            }
            x
        });

        assert!(!result.passed);
        assert!(result.panics > 0);
    }

    #[test]
    fn test_fuzz_with_validation() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(100);
        let runner = FuzzRunner::new(config);

        // Clamp function (but handle NaN input - clamp(NaN) = NaN)
        let result = runner.fuzz_with_validation(
            |gen| gen.f64(),
            |x| if x.is_nan() { 0.0 } else { x.clamp(-1.0, 1.0) },
            |_input, output| {
                if *output >= -1.0 && *output <= 1.0 {
                    Ok(())
                } else {
                    Err(format!("Output {} out of range", output))
                }
            },
        );

        assert!(result.passed);
    }

    #[test]
    fn test_reproducibility() {
        use std::sync::atomic::{AtomicU64, Ordering};

        // Test that same seed produces same results
        let config1 = FuzzConfig::minimal().with_seed(12345).with_iterations(50);
        let config2 = FuzzConfig::minimal().with_seed(12345).with_iterations(50);

        let runner1 = FuzzRunner::new(config1);
        let runner2 = FuzzRunner::new(config2);

        // Use atomics to track sums (deterministic comparison)
        let sum1 = AtomicU64::new(0);
        let sum2 = AtomicU64::new(0);

        runner1.fuzz_f64(|x| {
            // Only count valid (non-NaN, non-Inf) numbers
            if x.is_finite() {
                sum1.fetch_add((x.abs() * 1000.0) as u64, Ordering::Relaxed);
            }
            x
        });

        runner2.fuzz_f64(|x| {
            if x.is_finite() {
                sum2.fetch_add((x.abs() * 1000.0) as u64, Ordering::Relaxed);
            }
            x
        });

        // Same seed should produce same sum
        assert_eq!(sum1.load(Ordering::Relaxed), sum2.load(Ordering::Relaxed));
    }
}

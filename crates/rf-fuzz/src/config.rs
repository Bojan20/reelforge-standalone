//! Fuzzing configuration

use serde::{Deserialize, Serialize};

/// Configuration for fuzzing runs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FuzzConfig {
    /// Number of fuzzing iterations
    pub iterations: usize,

    /// Random seed for reproducibility (None = random)
    pub seed: Option<u64>,

    /// Maximum input size in bytes
    pub max_input_size: usize,

    /// Timeout per iteration in milliseconds
    pub timeout_ms: u64,

    /// Whether to continue after first failure
    pub continue_on_failure: bool,

    /// Maximum failures before stopping
    pub max_failures: usize,

    /// Include edge cases (NaN, Inf, etc.)
    pub include_edge_cases: bool,

    /// Include boundary values
    pub include_boundaries: bool,

    /// Bias toward small inputs
    pub prefer_small_inputs: bool,

    /// Output directory for crash reports
    pub output_dir: Option<String>,

    /// Verbosity level (0-3)
    pub verbosity: u8,
}

impl Default for FuzzConfig {
    fn default() -> Self {
        Self {
            iterations: 10_000,
            seed: None,
            max_input_size: 4096,
            timeout_ms: 1000,
            continue_on_failure: true,
            max_failures: 100,
            include_edge_cases: true,
            include_boundaries: true,
            prefer_small_inputs: true,
            output_dir: None,
            verbosity: 1,
        }
    }
}

impl FuzzConfig {
    /// Create a quick fuzzing config for CI
    pub fn ci() -> Self {
        Self {
            iterations: 1000,
            timeout_ms: 100,
            verbosity: 0,
            ..Default::default()
        }
    }

    /// Create an exhaustive fuzzing config for local testing
    pub fn exhaustive() -> Self {
        Self {
            iterations: 1_000_000,
            timeout_ms: 5000,
            max_input_size: 65536,
            verbosity: 2,
            ..Default::default()
        }
    }

    /// Create a minimal config for quick sanity checks
    pub fn minimal() -> Self {
        Self {
            iterations: 100,
            include_edge_cases: true,
            include_boundaries: true,
            prefer_small_inputs: false,
            ..Default::default()
        }
    }

    /// Builder: set iterations
    pub fn with_iterations(mut self, n: usize) -> Self {
        self.iterations = n;
        self
    }

    /// Builder: set seed for reproducibility
    pub fn with_seed(mut self, seed: u64) -> Self {
        self.seed = Some(seed);
        self
    }

    /// Builder: set max input size
    pub fn with_max_input_size(mut self, size: usize) -> Self {
        self.max_input_size = size;
        self
    }

    /// Builder: set timeout
    pub fn with_timeout_ms(mut self, ms: u64) -> Self {
        self.timeout_ms = ms;
        self
    }

    /// Builder: set output directory
    pub fn with_output_dir(mut self, dir: impl Into<String>) -> Self {
        self.output_dir = Some(dir.into());
        self
    }

    /// Builder: set verbosity
    pub fn with_verbosity(mut self, level: u8) -> Self {
        self.verbosity = level;
        self
    }

    /// Builder: continue on failure
    pub fn continue_after_failures(mut self, cont: bool) -> Self {
        self.continue_on_failure = cont;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = FuzzConfig::default();
        assert_eq!(config.iterations, 10_000);
        assert!(config.include_edge_cases);
    }

    #[test]
    fn test_builder() {
        let config = FuzzConfig::default()
            .with_iterations(5000)
            .with_seed(42)
            .with_timeout_ms(500);

        assert_eq!(config.iterations, 5000);
        assert_eq!(config.seed, Some(42));
        assert_eq!(config.timeout_ms, 500);
    }
}

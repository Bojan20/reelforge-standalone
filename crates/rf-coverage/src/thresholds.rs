//! Coverage threshold checking

use crate::parser::CoverageData;
use serde::{Deserialize, Serialize};

/// Coverage threshold configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoverageThreshold {
    /// Minimum line coverage percentage
    pub min_line_coverage: f64,
    /// Minimum function coverage percentage
    pub min_function_coverage: f64,
    /// Minimum branch coverage percentage
    pub min_branch_coverage: f64,
    /// Per-file minimum (files below this are flagged)
    pub min_file_coverage: f64,
    /// Paths to exclude from threshold checks
    pub exclude_paths: Vec<String>,
    /// Crate-specific thresholds
    pub crate_thresholds: Vec<CrateThreshold>,
}

/// Crate-specific threshold
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrateThreshold {
    /// Crate path prefix
    pub path: String,
    /// Minimum line coverage for this crate
    pub min_line_coverage: f64,
    /// Minimum function coverage for this crate
    pub min_function_coverage: f64,
}

impl Default for CoverageThreshold {
    fn default() -> Self {
        Self {
            min_line_coverage: 70.0,
            min_function_coverage: 70.0,
            min_branch_coverage: 50.0,
            min_file_coverage: 50.0,
            exclude_paths: vec!["tests/".into(), "benches/".into(), "examples/".into()],
            crate_thresholds: vec![],
        }
    }
}

impl CoverageThreshold {
    /// Create strict threshold (CI/CD)
    pub fn strict() -> Self {
        Self {
            min_line_coverage: 80.0,
            min_function_coverage: 80.0,
            min_branch_coverage: 60.0,
            min_file_coverage: 60.0,
            ..Default::default()
        }
    }

    /// Create relaxed threshold (development)
    pub fn relaxed() -> Self {
        Self {
            min_line_coverage: 50.0,
            min_function_coverage: 50.0,
            min_branch_coverage: 30.0,
            min_file_coverage: 30.0,
            ..Default::default()
        }
    }

    /// Create audio-specific threshold (DSP code is harder to test)
    pub fn audio() -> Self {
        Self {
            min_line_coverage: 60.0,
            min_function_coverage: 70.0,
            min_branch_coverage: 40.0,
            min_file_coverage: 40.0,
            exclude_paths: vec![
                "tests/".into(),
                "benches/".into(),
                "examples/".into(),
                "ffi.rs".into(), // FFI code often has uncovered paths
            ],
            crate_thresholds: vec![
                CrateThreshold {
                    path: "rf-dsp".into(),
                    min_line_coverage: 50.0, // DSP code has many edge cases
                    min_function_coverage: 60.0,
                },
                CrateThreshold {
                    path: "rf-engine".into(),
                    min_line_coverage: 55.0, // Engine has async paths
                    min_function_coverage: 65.0,
                },
            ],
        }
    }

    /// Check coverage against thresholds
    pub fn check(&self, data: &CoverageData) -> ThresholdResult {
        let mut result = ThresholdResult {
            passed: true,
            line_coverage: data.total_line_coverage(),
            function_coverage: data.total_function_coverage(),
            branch_coverage: data.total_branch_coverage(),
            failures: vec![],
            warnings: vec![],
        };

        // Check overall thresholds
        if result.line_coverage < self.min_line_coverage {
            result.passed = false;
            result.failures.push(format!(
                "Line coverage {:.1}% below minimum {:.1}%",
                result.line_coverage, self.min_line_coverage
            ));
        }

        if result.function_coverage < self.min_function_coverage {
            result.passed = false;
            result.failures.push(format!(
                "Function coverage {:.1}% below minimum {:.1}%",
                result.function_coverage, self.min_function_coverage
            ));
        }

        if result.branch_coverage < self.min_branch_coverage {
            result.passed = false;
            result.failures.push(format!(
                "Branch coverage {:.1}% below minimum {:.1}%",
                result.branch_coverage, self.min_branch_coverage
            ));
        }

        // Check per-file thresholds
        for file in &data.files {
            // Skip excluded paths
            if self.exclude_paths.iter().any(|p| file.path.contains(p)) {
                continue;
            }

            let file_coverage = file.line_coverage_percent();
            if file_coverage < self.min_file_coverage {
                result.warnings.push(format!(
                    "{}: {:.1}% coverage (minimum {:.1}%)",
                    file.path, file_coverage, self.min_file_coverage
                ));
            }
        }

        // Check crate-specific thresholds
        for crate_threshold in &self.crate_thresholds {
            let crate_data = data.filter_path(&crate_threshold.path);
            let crate_line_cov = crate_data.total_line_coverage();
            let crate_func_cov = crate_data.total_function_coverage();

            if crate_line_cov < crate_threshold.min_line_coverage {
                result.warnings.push(format!(
                    "{}: line coverage {:.1}% below minimum {:.1}%",
                    crate_threshold.path, crate_line_cov, crate_threshold.min_line_coverage
                ));
            }

            if crate_func_cov < crate_threshold.min_function_coverage {
                result.warnings.push(format!(
                    "{}: function coverage {:.1}% below minimum {:.1}%",
                    crate_threshold.path, crate_func_cov, crate_threshold.min_function_coverage
                ));
            }
        }

        result
    }

    /// Add crate-specific threshold
    pub fn with_crate_threshold(mut self, path: &str, line: f64, function: f64) -> Self {
        self.crate_thresholds.push(CrateThreshold {
            path: path.into(),
            min_line_coverage: line,
            min_function_coverage: function,
        });
        self
    }

    /// Add path to exclude
    pub fn exclude(mut self, path: &str) -> Self {
        self.exclude_paths.push(path.into());
        self
    }
}

/// Result of threshold check
#[derive(Debug, Clone)]
pub struct ThresholdResult {
    /// Whether all thresholds were met
    pub passed: bool,
    /// Actual line coverage
    pub line_coverage: f64,
    /// Actual function coverage
    pub function_coverage: f64,
    /// Actual branch coverage
    pub branch_coverage: f64,
    /// Threshold failures (blocking)
    pub failures: Vec<String>,
    /// Warnings (non-blocking)
    pub warnings: Vec<String>,
}

impl ThresholdResult {
    /// Format as CI-friendly output
    pub fn ci_output(&self) -> String {
        let mut output = String::new();

        if self.passed {
            output.push_str("✅ Coverage thresholds PASSED\n");
        } else {
            output.push_str("❌ Coverage thresholds FAILED\n");
        }

        output.push_str(&format!(
            "\nCoverage: Lines {:.1}%, Functions {:.1}%, Branches {:.1}%\n",
            self.line_coverage, self.function_coverage, self.branch_coverage
        ));

        if !self.failures.is_empty() {
            output.push_str("\nFailures:\n");
            for failure in &self.failures {
                output.push_str(&format!("  - {}\n", failure));
            }
        }

        if !self.warnings.is_empty() {
            output.push_str("\nWarnings:\n");
            for warning in &self.warnings {
                output.push_str(&format!("  - {}\n", warning));
            }
        }

        output
    }

    /// Format as GitHub Actions annotation
    pub fn github_annotation(&self) -> String {
        if self.passed {
            format!(
                "::notice::Coverage: {:.1}% lines, {:.1}% functions",
                self.line_coverage, self.function_coverage
            )
        } else {
            let failures = self.failures.join("; ");
            format!("::error::Coverage threshold failed: {}", failures)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::CoverageData;

    fn sample_coverage() -> CoverageData {
        let json = r#"{
            "data": [{
                "files": [
                    {"filename": "src/lib.rs", "summary": {"lines": {"covered": 80, "count": 100}, "functions": {"covered": 10, "count": 12}}},
                    {"filename": "src/utils.rs", "summary": {"lines": {"covered": 45, "count": 50}, "functions": {"covered": 5, "count": 5}}}
                ],
                "functions": [],
                "totals": {"lines": {"covered": 125, "count": 150}, "functions": {"covered": 15, "count": 17}}
            }]
        }"#;
        CoverageData::from_json(json).unwrap()
    }

    #[test]
    fn test_default_threshold_pass() {
        let data = sample_coverage();
        let threshold = CoverageThreshold::default();
        let result = threshold.check(&data);

        assert!(result.passed);
    }

    #[test]
    fn test_strict_threshold_fail() {
        // Create low coverage data that will fail strict threshold
        let json = r#"{
            "data": [{
                "files": [
                    {"filename": "src/lib.rs", "summary": {"lines": {"covered": 60, "count": 100}, "functions": {"covered": 6, "count": 10}}}
                ],
                "functions": [],
                "totals": {"lines": {"covered": 60, "count": 100}, "functions": {"covered": 6, "count": 10}}
            }]
        }"#;
        let data = CoverageData::from_json(json).unwrap();
        let threshold = CoverageThreshold::strict();
        let result = threshold.check(&data);

        assert!(!result.passed);
        assert!(!result.failures.is_empty());
    }

    #[test]
    fn test_relaxed_threshold_pass() {
        let data = sample_coverage();
        let threshold = CoverageThreshold::relaxed();
        let result = threshold.check(&data);

        assert!(result.passed);
    }
}

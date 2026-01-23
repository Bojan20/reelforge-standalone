//! # rf-coverage
//!
//! Code coverage reporting and analysis for FluxForge.
//!
//! ## Features
//!
//! - Parse llvm-cov JSON output
//! - Generate coverage reports (HTML, Markdown, JSON)
//! - Track coverage trends over time
//! - Enforce coverage thresholds in CI
//! - Per-crate and per-file analysis
//!
//! ## Usage
//!
//! ```bash
//! # Generate coverage with cargo-llvm-cov
//! cargo llvm-cov --json --output-path coverage.json
//!
//! # Use rf-coverage to analyze
//! rf-coverage analyze coverage.json --threshold 80
//! ```

pub mod parser;
pub mod report;
pub mod thresholds;
pub mod trends;

pub use parser::{CoverageData, FileCoverage, FunctionCoverage};
pub use report::{CoverageReport, ReportFormat};
pub use thresholds::{CoverageThreshold, ThresholdResult};
pub use trends::{CoverageTrend, TrendAnalysis};

use thiserror::Error;

/// Errors that can occur during coverage operations
#[derive(Error, Debug)]
pub enum CoverageError {
    #[error("Failed to parse coverage data: {0}")]
    ParseError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Coverage threshold not met: {message}")]
    ThresholdNotMet { message: String },

    #[error("Invalid configuration: {0}")]
    ConfigError(String),
}

pub type Result<T> = std::result::Result<T, CoverageError>;

/// Quick coverage check with default thresholds
pub fn check_coverage(coverage_path: &str) -> Result<bool> {
    let data = CoverageData::from_file(coverage_path)?;
    let threshold = CoverageThreshold::default();
    Ok(threshold.check(&data).passed)
}

/// Get coverage summary from file
pub fn coverage_summary(coverage_path: &str) -> Result<CoverageSummary> {
    let data = CoverageData::from_file(coverage_path)?;
    Ok(CoverageSummary {
        line_coverage: data.total_line_coverage(),
        function_coverage: data.total_function_coverage(),
        branch_coverage: data.total_branch_coverage(),
        files_covered: data.files_with_coverage(),
        total_files: data.total_files(),
    })
}

/// Coverage summary statistics
#[derive(Debug, Clone)]
pub struct CoverageSummary {
    /// Line coverage percentage (0.0 - 100.0)
    pub line_coverage: f64,
    /// Function coverage percentage (0.0 - 100.0)
    pub function_coverage: f64,
    /// Branch coverage percentage (0.0 - 100.0)
    pub branch_coverage: f64,
    /// Number of files with some coverage
    pub files_covered: usize,
    /// Total number of source files
    pub total_files: usize,
}

impl CoverageSummary {
    /// Check if coverage meets minimum thresholds
    pub fn meets_threshold(&self, min_line: f64, min_function: f64) -> bool {
        self.line_coverage >= min_line && self.function_coverage >= min_function
    }

    /// Format as single-line summary
    pub fn one_line(&self) -> String {
        format!(
            "Lines: {:.1}%, Functions: {:.1}%, Branches: {:.1}% ({}/{} files)",
            self.line_coverage,
            self.function_coverage,
            self.branch_coverage,
            self.files_covered,
            self.total_files
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_coverage_summary() {
        let summary = CoverageSummary {
            line_coverage: 85.5,
            function_coverage: 90.0,
            branch_coverage: 75.0,
            files_covered: 45,
            total_files: 50,
        };

        assert!(summary.meets_threshold(80.0, 85.0));
        assert!(!summary.meets_threshold(90.0, 95.0));
    }
}

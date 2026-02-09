//! Coverage data parsing from llvm-cov JSON output

use crate::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// Parsed coverage data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoverageData {
    /// Coverage data per file
    pub files: Vec<FileCoverage>,
    /// Coverage data per function
    pub functions: Vec<FunctionCoverage>,
    /// Totals
    pub totals: CoverageTotals,
}

/// Coverage totals
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CoverageTotals {
    pub lines_covered: usize,
    pub lines_total: usize,
    pub functions_covered: usize,
    pub functions_total: usize,
    pub branches_covered: usize,
    pub branches_total: usize,
}

/// Coverage data for a single file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileCoverage {
    /// File path
    pub path: String,
    /// Lines covered
    pub lines_covered: usize,
    /// Total lines
    pub lines_total: usize,
    /// Functions covered
    pub functions_covered: usize,
    /// Total functions
    pub functions_total: usize,
    /// Branches covered
    pub branches_covered: usize,
    /// Total branches
    pub branches_total: usize,
    /// Per-line execution counts (line number -> count)
    pub line_counts: HashMap<usize, usize>,
}

impl FileCoverage {
    /// Calculate line coverage percentage
    pub fn line_coverage_percent(&self) -> f64 {
        if self.lines_total == 0 {
            100.0
        } else {
            self.lines_covered as f64 / self.lines_total as f64 * 100.0
        }
    }

    /// Calculate function coverage percentage
    pub fn function_coverage_percent(&self) -> f64 {
        if self.functions_total == 0 {
            100.0
        } else {
            self.functions_covered as f64 / self.functions_total as f64 * 100.0
        }
    }

    /// Get list of uncovered lines
    pub fn uncovered_lines(&self) -> Vec<usize> {
        self.line_counts
            .iter()
            .filter(|(_, &count)| count == 0)
            .map(|(&line, _)| line)
            .collect()
    }
}

/// Coverage data for a single function
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionCoverage {
    /// Function name
    pub name: String,
    /// File containing the function
    pub file: String,
    /// Start line
    pub start_line: usize,
    /// End line
    pub end_line: usize,
    /// Execution count
    pub execution_count: usize,
    /// Lines covered in this function
    pub lines_covered: usize,
    /// Total lines in this function
    pub lines_total: usize,
}

impl FunctionCoverage {
    /// Check if function was executed
    pub fn is_covered(&self) -> bool {
        self.execution_count > 0
    }

    /// Calculate line coverage percentage
    pub fn line_coverage_percent(&self) -> f64 {
        if self.lines_total == 0 {
            100.0
        } else {
            self.lines_covered as f64 / self.lines_total as f64 * 100.0
        }
    }
}

impl CoverageData {
    /// Load coverage data from file
    pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path)?;
        Self::from_json(&content)
    }

    /// Parse coverage data from JSON string
    pub fn from_json(json: &str) -> Result<Self> {
        // Try parsing as llvm-cov export format
        if let Ok(data) = Self::parse_llvm_cov_export(json) {
            return Ok(data);
        }

        // Try parsing as cargo-llvm-cov format
        if let Ok(data) = Self::parse_cargo_llvm_cov(json) {
            return Ok(data);
        }

        Err(crate::CoverageError::ParseError(
            "Unrecognized coverage format".into(),
        ))
    }

    /// Parse llvm-cov export JSON format
    fn parse_llvm_cov_export(json: &str) -> Result<Self> {
        #[derive(Deserialize)]
        struct LlvmCovExport {
            data: Vec<LlvmCovData>,
        }

        #[derive(Deserialize)]
        struct LlvmCovData {
            files: Vec<LlvmCovFile>,
            functions: Vec<LlvmCovFunction>,
            totals: LlvmCovTotals,
        }

        #[derive(Deserialize)]
        struct LlvmCovFile {
            filename: String,
            summary: LlvmCovSummary,
            segments: Option<Vec<Vec<serde_json::Value>>>,
        }

        #[derive(Deserialize)]
        struct LlvmCovFunction {
            name: String,
            count: usize,
            filenames: Vec<String>,
            regions: Option<Vec<Vec<usize>>>,
        }

        #[derive(Deserialize)]
        struct LlvmCovTotals {
            lines: LlvmCovMetric,
            functions: LlvmCovMetric,
            branches: Option<LlvmCovMetric>,
        }

        #[derive(Deserialize)]
        struct LlvmCovSummary {
            lines: LlvmCovMetric,
            functions: LlvmCovMetric,
            branches: Option<LlvmCovMetric>,
        }

        #[derive(Deserialize)]
        struct LlvmCovMetric {
            covered: usize,
            count: usize,
        }

        let export: LlvmCovExport = serde_json::from_str(json)?;
        let data = export
            .data
            .first()
            .ok_or_else(|| crate::CoverageError::ParseError("No coverage data found".into()))?;

        let files: Vec<FileCoverage> = data
            .files
            .iter()
            .map(|f| {
                let branches = f.summary.branches.as_ref();
                FileCoverage {
                    path: f.filename.clone(),
                    lines_covered: f.summary.lines.covered,
                    lines_total: f.summary.lines.count,
                    functions_covered: f.summary.functions.covered,
                    functions_total: f.summary.functions.count,
                    branches_covered: branches.map(|b| b.covered).unwrap_or(0),
                    branches_total: branches.map(|b| b.count).unwrap_or(0),
                    line_counts: HashMap::new(), // Would need segment parsing
                }
            })
            .collect();

        let functions: Vec<FunctionCoverage> = data
            .functions
            .iter()
            .map(|f| FunctionCoverage {
                name: f.name.clone(),
                file: f.filenames.first().cloned().unwrap_or_default(),
                start_line: 0,
                end_line: 0,
                execution_count: f.count,
                lines_covered: 0,
                lines_total: 0,
            })
            .collect();

        let branches = data.totals.branches.as_ref();
        let totals = CoverageTotals {
            lines_covered: data.totals.lines.covered,
            lines_total: data.totals.lines.count,
            functions_covered: data.totals.functions.covered,
            functions_total: data.totals.functions.count,
            branches_covered: branches.map(|b| b.covered).unwrap_or(0),
            branches_total: branches.map(|b| b.count).unwrap_or(0),
        };

        Ok(CoverageData {
            files,
            functions,
            totals,
        })
    }

    /// Parse cargo-llvm-cov JSON format
    fn parse_cargo_llvm_cov(json: &str) -> Result<Self> {
        // cargo-llvm-cov uses same format, just try direct parse
        Self::parse_llvm_cov_export(json)
    }

    /// Calculate total line coverage percentage
    pub fn total_line_coverage(&self) -> f64 {
        if self.totals.lines_total == 0 {
            100.0
        } else {
            self.totals.lines_covered as f64 / self.totals.lines_total as f64 * 100.0
        }
    }

    /// Calculate total function coverage percentage
    pub fn total_function_coverage(&self) -> f64 {
        if self.totals.functions_total == 0 {
            100.0
        } else {
            self.totals.functions_covered as f64 / self.totals.functions_total as f64 * 100.0
        }
    }

    /// Calculate total branch coverage percentage
    pub fn total_branch_coverage(&self) -> f64 {
        if self.totals.branches_total == 0 {
            100.0
        } else {
            self.totals.branches_covered as f64 / self.totals.branches_total as f64 * 100.0
        }
    }

    /// Get number of files with any coverage
    pub fn files_with_coverage(&self) -> usize {
        self.files.iter().filter(|f| f.lines_covered > 0).count()
    }

    /// Get total number of files
    pub fn total_files(&self) -> usize {
        self.files.len()
    }

    /// Get files below coverage threshold
    pub fn files_below_threshold(&self, threshold: f64) -> Vec<&FileCoverage> {
        self.files
            .iter()
            .filter(|f| f.line_coverage_percent() < threshold)
            .collect()
    }

    /// Get uncovered functions
    pub fn uncovered_functions(&self) -> Vec<&FunctionCoverage> {
        self.functions.iter().filter(|f| !f.is_covered()).collect()
    }

    /// Filter to specific crate/directory
    pub fn filter_path(&self, path_prefix: &str) -> Self {
        let files: Vec<FileCoverage> = self
            .files
            .iter()
            .filter(|f| f.path.contains(path_prefix))
            .cloned()
            .collect();

        let functions: Vec<FunctionCoverage> = self
            .functions
            .iter()
            .filter(|f| f.file.contains(path_prefix))
            .cloned()
            .collect();

        // Recalculate totals
        let totals = CoverageTotals {
            lines_covered: files.iter().map(|f| f.lines_covered).sum(),
            lines_total: files.iter().map(|f| f.lines_total).sum(),
            functions_covered: files.iter().map(|f| f.functions_covered).sum(),
            functions_total: files.iter().map(|f| f.functions_total).sum(),
            branches_covered: files.iter().map(|f| f.branches_covered).sum(),
            branches_total: files.iter().map(|f| f.branches_total).sum(),
        };

        CoverageData {
            files,
            functions,
            totals,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_coverage_json() -> &'static str {
        r#"{
            "data": [{
                "files": [
                    {
                        "filename": "src/lib.rs",
                        "summary": {
                            "lines": {"covered": 80, "count": 100},
                            "functions": {"covered": 10, "count": 12},
                            "branches": {"covered": 20, "count": 30}
                        }
                    },
                    {
                        "filename": "src/utils.rs",
                        "summary": {
                            "lines": {"covered": 45, "count": 50},
                            "functions": {"covered": 5, "count": 5}
                        }
                    }
                ],
                "functions": [
                    {"name": "main", "count": 1, "filenames": ["src/lib.rs"]},
                    {"name": "helper", "count": 0, "filenames": ["src/lib.rs"]}
                ],
                "totals": {
                    "lines": {"covered": 125, "count": 150},
                    "functions": {"covered": 15, "count": 17},
                    "branches": {"covered": 20, "count": 30}
                }
            }]
        }"#
    }

    #[test]
    fn test_parse_llvm_cov() {
        let data = CoverageData::from_json(sample_coverage_json()).unwrap();

        assert_eq!(data.files.len(), 2);
        assert_eq!(data.functions.len(), 2);
        assert_eq!(data.totals.lines_covered, 125);
        assert_eq!(data.totals.lines_total, 150);
    }

    #[test]
    fn test_coverage_percentages() {
        let data = CoverageData::from_json(sample_coverage_json()).unwrap();

        let line_cov = data.total_line_coverage();
        assert!((line_cov - 83.33).abs() < 0.1);

        let func_cov = data.total_function_coverage();
        assert!((func_cov - 88.24).abs() < 0.1);
    }

    #[test]
    fn test_file_coverage() {
        let data = CoverageData::from_json(sample_coverage_json()).unwrap();

        let lib_rs = data.files.iter().find(|f| f.path == "src/lib.rs").unwrap();
        assert_eq!(lib_rs.line_coverage_percent(), 80.0);
    }

    #[test]
    fn test_uncovered_functions() {
        let data = CoverageData::from_json(sample_coverage_json()).unwrap();
        let uncovered = data.uncovered_functions();

        assert_eq!(uncovered.len(), 1);
        assert_eq!(uncovered[0].name, "helper");
    }
}

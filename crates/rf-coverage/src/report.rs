//! Coverage report generation

use crate::parser::CoverageData;
use crate::thresholds::ThresholdResult;
use crate::Result;
use serde::Serialize;
use std::fs;
use std::path::Path;

/// Coverage report format
#[derive(Debug, Clone, Copy)]
pub enum ReportFormat {
    Text,
    Markdown,
    Html,
    Json,
    JUnit,
}

/// Coverage report generator
#[derive(Debug)]
pub struct CoverageReport {
    /// Coverage data
    data: CoverageData,
    /// Threshold result (optional)
    threshold_result: Option<ThresholdResult>,
    /// Report title
    title: String,
}

impl CoverageReport {
    /// Create new report from coverage data
    pub fn new(data: CoverageData) -> Self {
        Self {
            data,
            threshold_result: None,
            title: "Coverage Report".into(),
        }
    }

    /// Set report title
    pub fn with_title(mut self, title: impl Into<String>) -> Self {
        self.title = title.into();
        self
    }

    /// Add threshold result
    pub fn with_threshold(mut self, result: ThresholdResult) -> Self {
        self.threshold_result = Some(result);
        self
    }

    /// Generate report in specified format
    pub fn generate(&self, format: ReportFormat) -> String {
        match format {
            ReportFormat::Text => self.to_text(),
            ReportFormat::Markdown => self.to_markdown(),
            ReportFormat::Html => self.to_html(),
            ReportFormat::Json => self.to_json(),
            ReportFormat::JUnit => self.to_junit(),
        }
    }

    /// Save report to file
    pub fn save<P: AsRef<Path>>(&self, path: P, format: ReportFormat) -> Result<()> {
        let content = self.generate(format);
        fs::write(path, content)?;
        Ok(())
    }

    /// Generate text report
    fn to_text(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("{}\n", self.title));
        output.push_str(&format!("{}\n\n", "=".repeat(self.title.len())));

        // Summary
        output.push_str("Summary:\n");
        output.push_str(&format!(
            "  Lines:     {}/{} ({:.1}%)\n",
            self.data.totals.lines_covered,
            self.data.totals.lines_total,
            self.data.total_line_coverage()
        ));
        output.push_str(&format!(
            "  Functions: {}/{} ({:.1}%)\n",
            self.data.totals.functions_covered,
            self.data.totals.functions_total,
            self.data.total_function_coverage()
        ));
        output.push_str(&format!(
            "  Branches:  {}/{} ({:.1}%)\n\n",
            self.data.totals.branches_covered,
            self.data.totals.branches_total,
            self.data.total_branch_coverage()
        ));

        // Threshold result
        if let Some(ref result) = self.threshold_result {
            output.push_str(&result.ci_output());
            output.push('\n');
        }

        // File breakdown
        output.push_str("Files:\n");
        output.push_str(&"-".repeat(80));
        output.push('\n');

        let mut files: Vec<_> = self.data.files.iter().collect();
        files.sort_by(|a, b| {
            a.line_coverage_percent()
                .partial_cmp(&b.line_coverage_percent())
                .unwrap()
        });

        for file in files {
            let coverage = file.line_coverage_percent();
            let bar = coverage_bar(coverage, 20);
            output.push_str(&format!(
                "{:60} {:>5.1}% {}\n",
                truncate_path(&file.path, 60),
                coverage,
                bar
            ));
        }

        output
    }

    /// Generate markdown report
    fn to_markdown(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("# {}\n\n", self.title));

        // Status badge
        let status = if let Some(ref result) = self.threshold_result {
            if result.passed {
                "![Coverage](https://img.shields.io/badge/coverage-passing-green)"
            } else {
                "![Coverage](https://img.shields.io/badge/coverage-failing-red)"
            }
        } else {
            ""
        };
        if !status.is_empty() {
            output.push_str(&format!("{}\n\n", status));
        }

        // Summary table
        output.push_str("## Summary\n\n");
        output.push_str("| Metric | Covered | Total | Percentage |\n");
        output.push_str("|--------|---------|-------|------------|\n");
        output.push_str(&format!(
            "| Lines | {} | {} | {:.1}% |\n",
            self.data.totals.lines_covered,
            self.data.totals.lines_total,
            self.data.total_line_coverage()
        ));
        output.push_str(&format!(
            "| Functions | {} | {} | {:.1}% |\n",
            self.data.totals.functions_covered,
            self.data.totals.functions_total,
            self.data.total_function_coverage()
        ));
        output.push_str(&format!(
            "| Branches | {} | {} | {:.1}% |\n\n",
            self.data.totals.branches_covered,
            self.data.totals.branches_total,
            self.data.total_branch_coverage()
        ));

        // File breakdown
        output.push_str("## Files\n\n");
        output.push_str("| File | Lines | Functions | Coverage |\n");
        output.push_str("|------|-------|-----------|----------|\n");

        let mut files: Vec<_> = self.data.files.iter().collect();
        files.sort_by(|a, b| {
            a.line_coverage_percent()
                .partial_cmp(&b.line_coverage_percent())
                .unwrap()
        });

        for file in files {
            let coverage = file.line_coverage_percent();
            let status = if coverage >= 80.0 {
                "🟢"
            } else if coverage >= 60.0 {
                "🟡"
            } else {
                "🔴"
            };
            output.push_str(&format!(
                "| {} | {}/{} | {}/{} | {} {:.1}% |\n",
                file.path,
                file.lines_covered,
                file.lines_total,
                file.functions_covered,
                file.functions_total,
                status,
                coverage
            ));
        }

        output
    }

    /// Generate HTML report
    fn to_html(&self) -> String {
        let mut output = String::new();

        output.push_str("<!DOCTYPE html>\n<html>\n<head>\n");
        output.push_str(&format!("<title>{}</title>\n", self.title));
        output.push_str("<style>\n");
        output.push_str("body { font-family: -apple-system, sans-serif; margin: 20px; }\n");
        output.push_str("table { border-collapse: collapse; width: 100%; }\n");
        output.push_str("th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
        output.push_str("th { background-color: #4a9eff; color: white; }\n");
        output.push_str("tr:nth-child(even) { background-color: #f2f2f2; }\n");
        output.push_str(".pass { color: #40c840; } .fail { color: #ff4040; }\n");
        output.push_str(
            ".bar { background: #eee; width: 100px; height: 10px; display: inline-block; }\n",
        );
        output.push_str(".bar-fill { background: #4a9eff; height: 100%; }\n");
        output.push_str("</style>\n</head>\n<body>\n");

        output.push_str(&format!("<h1>{}</h1>\n", self.title));

        // Summary
        output.push_str("<h2>Summary</h2>\n");
        output.push_str(
            "<table>\n<tr><th>Metric</th><th>Covered</th><th>Total</th><th>Percentage</th></tr>\n",
        );
        output.push_str(&format!(
            "<tr><td>Lines</td><td>{}</td><td>{}</td><td>{:.1}%</td></tr>\n",
            self.data.totals.lines_covered,
            self.data.totals.lines_total,
            self.data.total_line_coverage()
        ));
        output.push_str(&format!(
            "<tr><td>Functions</td><td>{}</td><td>{}</td><td>{:.1}%</td></tr>\n",
            self.data.totals.functions_covered,
            self.data.totals.functions_total,
            self.data.total_function_coverage()
        ));
        output.push_str("</table>\n");

        // File list
        output.push_str("<h2>Files</h2>\n");
        output.push_str("<table>\n<tr><th>File</th><th>Lines</th><th>Coverage</th></tr>\n");

        for file in &self.data.files {
            let coverage = file.line_coverage_percent();
            output.push_str(&format!(
                "<tr><td>{}</td><td>{}/{}</td><td><div class=\"bar\"><div class=\"bar-fill\" style=\"width: {}%\"></div></div> {:.1}%</td></tr>\n",
                file.path,
                file.lines_covered,
                file.lines_total,
                coverage.min(100.0),
                coverage
            ));
        }

        output.push_str("</table>\n</body>\n</html>\n");
        output
    }

    /// Generate JSON report
    fn to_json(&self) -> String {
        #[derive(Serialize)]
        struct JsonReport<'a> {
            title: &'a str,
            summary: JsonSummary,
            files: Vec<JsonFile<'a>>,
            threshold_result: Option<JsonThreshold<'a>>,
        }

        #[derive(Serialize)]
        struct JsonSummary {
            line_coverage: f64,
            function_coverage: f64,
            branch_coverage: f64,
            lines_covered: usize,
            lines_total: usize,
        }

        #[derive(Serialize)]
        struct JsonFile<'a> {
            path: &'a str,
            line_coverage: f64,
            lines_covered: usize,
            lines_total: usize,
        }

        #[derive(Serialize)]
        struct JsonThreshold<'a> {
            passed: bool,
            failures: &'a [String],
            warnings: &'a [String],
        }

        let report = JsonReport {
            title: &self.title,
            summary: JsonSummary {
                line_coverage: self.data.total_line_coverage(),
                function_coverage: self.data.total_function_coverage(),
                branch_coverage: self.data.total_branch_coverage(),
                lines_covered: self.data.totals.lines_covered,
                lines_total: self.data.totals.lines_total,
            },
            files: self
                .data
                .files
                .iter()
                .map(|f| JsonFile {
                    path: &f.path,
                    line_coverage: f.line_coverage_percent(),
                    lines_covered: f.lines_covered,
                    lines_total: f.lines_total,
                })
                .collect(),
            threshold_result: self.threshold_result.as_ref().map(|r| JsonThreshold {
                passed: r.passed,
                failures: &r.failures,
                warnings: &r.warnings,
            }),
        };

        serde_json::to_string_pretty(&report).unwrap_or_else(|_| "{}".into())
    }

    /// Generate JUnit XML report
    fn to_junit(&self) -> String {
        let passed = self
            .threshold_result
            .as_ref()
            .map(|r| r.passed)
            .unwrap_or(true);
        let failures = if passed { 0 } else { 1 };

        let mut output = String::new();
        output.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        output.push_str(&format!(
            "<testsuite name=\"coverage\" tests=\"1\" failures=\"{}\">\n",
            failures
        ));

        output.push_str(&format!(
            "  <testcase name=\"line_coverage\" classname=\"coverage\">\n"
        ));

        if !passed {
            if let Some(ref result) = self.threshold_result {
                let msg = result.failures.join("; ");
                output.push_str(&format!(
                    "    <failure message=\"{}\">{:.1}% coverage</failure>\n",
                    xml_escape(&msg),
                    self.data.total_line_coverage()
                ));
            }
        }

        output.push_str("  </testcase>\n");
        output.push_str("</testsuite>\n");
        output
    }
}

/// Generate ASCII coverage bar
fn coverage_bar(percent: f64, width: usize) -> String {
    let filled = ((percent / 100.0) * width as f64).round() as usize;
    let empty = width.saturating_sub(filled);
    format!("[{}{}]", "█".repeat(filled), "░".repeat(empty))
}

/// Truncate file path for display
fn truncate_path(path: &str, max_len: usize) -> String {
    if path.len() <= max_len {
        format!("{:width$}", path, width = max_len)
    } else {
        let truncated = &path[path.len() - max_len + 3..];
        format!("...{}", truncated)
    }
}

/// Escape XML special characters
fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_data() -> CoverageData {
        let json = r#"{
            "data": [{
                "files": [
                    {"filename": "src/lib.rs", "summary": {"lines": {"covered": 80, "count": 100}, "functions": {"covered": 10, "count": 12}}}
                ],
                "functions": [],
                "totals": {"lines": {"covered": 80, "count": 100}, "functions": {"covered": 10, "count": 12}}
            }]
        }"#;
        CoverageData::from_json(json).unwrap()
    }

    #[test]
    fn test_text_report() {
        let report = CoverageReport::new(sample_data());
        let text = report.generate(ReportFormat::Text);

        assert!(text.contains("Coverage Report"));
        assert!(text.contains("80.0%"));
    }

    #[test]
    fn test_markdown_report() {
        let report = CoverageReport::new(sample_data());
        let md = report.generate(ReportFormat::Markdown);

        assert!(md.contains("# Coverage Report"));
        assert!(md.contains("| Lines |"));
    }

    #[test]
    fn test_json_report() {
        let report = CoverageReport::new(sample_data());
        let json = report.generate(ReportFormat::Json);

        assert!(json.contains("\"line_coverage\""));
        assert!(json.contains("80"));
    }
}

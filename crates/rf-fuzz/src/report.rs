//! Report generation for fuzzing results

use crate::harness::FuzzResult;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// Fuzzing report for multiple targets
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FuzzReport {
    /// Report title
    pub title: String,

    /// Timestamp
    pub timestamp: String,

    /// Individual target results
    pub results: Vec<TargetResult>,

    /// Total statistics
    pub summary: FuzzSummary,
}

/// Result for a single fuzz target
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TargetResult {
    /// Target name
    pub name: String,

    /// Fuzzing result
    pub result: FuzzResult,
}

/// Summary statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FuzzSummary {
    pub total_targets: usize,
    pub passed_targets: usize,
    pub failed_targets: usize,
    pub total_iterations: usize,
    pub total_failures: usize,
    pub total_panics: usize,
    pub total_duration_ms: u64,
}

impl FuzzReport {
    /// Create a new report
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            timestamp: timestamp_now(),
            results: Vec::new(),
            summary: FuzzSummary {
                total_targets: 0,
                passed_targets: 0,
                failed_targets: 0,
                total_iterations: 0,
                total_failures: 0,
                total_panics: 0,
                total_duration_ms: 0,
            },
        }
    }

    /// Add a target result
    pub fn add_result(&mut self, name: impl Into<String>, result: FuzzResult) {
        self.summary.total_targets += 1;
        if result.passed {
            self.summary.passed_targets += 1;
        } else {
            self.summary.failed_targets += 1;
        }
        self.summary.total_iterations += result.iterations;
        self.summary.total_failures += result.failures;
        self.summary.total_panics += result.panics;
        self.summary.total_duration_ms += result.duration_ms;

        self.results.push(TargetResult {
            name: name.into(),
            result,
        });
    }

    /// Check if all targets passed
    pub fn all_passed(&self) -> bool {
        self.summary.failed_targets == 0
    }

    /// Generate text report
    pub fn to_text(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("{}\n", self.title));
        output.push_str(&format!("{}\n\n", "=".repeat(self.title.len())));

        output.push_str(&format!("Timestamp: {}\n\n", self.timestamp));

        // Summary
        output.push_str("Summary:\n");
        output.push_str(&format!("  Targets: {} total, {} passed, {} failed\n",
            self.summary.total_targets,
            self.summary.passed_targets,
            self.summary.failed_targets));
        output.push_str(&format!("  Iterations: {} total, {} failures, {} panics\n",
            self.summary.total_iterations,
            self.summary.total_failures,
            self.summary.total_panics));
        output.push_str(&format!("  Duration: {} ms\n\n", self.summary.total_duration_ms));

        // Individual results
        output.push_str("Results:\n");
        output.push_str(&"-".repeat(80));
        output.push('\n');

        for target in &self.results {
            let status = if target.result.passed { "PASS" } else { "FAIL" };
            output.push_str(&format!("[{}] {}\n", status, target.name));
            output.push_str(&format!("    {}\n", target.result.summary()));

            if !target.result.failure_details.is_empty() {
                output.push_str("    Failures:\n");
                for (i, failure) in target.result.failure_details.iter().take(5).enumerate() {
                    output.push_str(&format!("      {}. {:?}: {}\n",
                        i + 1,
                        failure.failure_type,
                        failure.description));
                    if failure.input.len() < 200 {
                        output.push_str(&format!("         Input: {}\n", failure.input));
                    }
                }
                if target.result.failure_details.len() > 5 {
                    output.push_str(&format!("      ... and {} more failures\n",
                        target.result.failure_details.len() - 5));
                }
            }
            output.push('\n');
        }

        output
    }

    /// Generate JSON report
    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_else(|_| "{}".into())
    }

    /// Generate markdown report
    pub fn to_markdown(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("# {}\n\n", self.title));
        output.push_str(&format!("**Timestamp:** {}\n\n", self.timestamp));

        // Status badge
        let status = if self.all_passed() { "✅ PASS" } else { "❌ FAIL" };
        output.push_str(&format!("## Status: {}\n\n", status));

        // Summary table
        output.push_str("## Summary\n\n");
        output.push_str("| Metric | Value |\n");
        output.push_str("|--------|-------|\n");
        output.push_str(&format!("| Total Targets | {} |\n", self.summary.total_targets));
        output.push_str(&format!("| Passed | {} |\n", self.summary.passed_targets));
        output.push_str(&format!("| Failed | {} |\n", self.summary.failed_targets));
        output.push_str(&format!("| Total Iterations | {} |\n", self.summary.total_iterations));
        output.push_str(&format!("| Total Failures | {} |\n", self.summary.total_failures));
        output.push_str(&format!("| Total Panics | {} |\n", self.summary.total_panics));
        output.push_str(&format!("| Duration | {} ms |\n\n", self.summary.total_duration_ms));

        // Results table
        output.push_str("## Results\n\n");
        output.push_str("| Target | Status | Iterations | Failures | Pass Rate |\n");
        output.push_str("|--------|--------|------------|----------|----------|\n");
        for target in &self.results {
            let status = if target.result.passed { "✅" } else { "❌" };
            output.push_str(&format!("| {} | {} | {} | {} | {:.1}% |\n",
                target.name,
                status,
                target.result.iterations,
                target.result.failures,
                target.result.pass_rate() * 100.0));
        }
        output.push('\n');

        // Failed targets details
        let failed: Vec<_> = self.results.iter().filter(|t| !t.result.passed).collect();
        if !failed.is_empty() {
            output.push_str("## Failed Targets\n\n");
            for target in failed {
                output.push_str(&format!("### {}\n\n", target.name));

                output.push_str("**Failure Details:**\n\n");
                for failure in target.result.failure_details.iter().take(10) {
                    output.push_str(&format!("- **{:?}** at iteration {}: {}\n",
                        failure.failure_type,
                        failure.iteration,
                        failure.description));
                    if failure.input.len() < 100 {
                        output.push_str(&format!("  - Input: `{}`\n", failure.input));
                    }
                }
                output.push('\n');
            }
        }

        output
    }

    /// Generate JUnit XML report
    pub fn to_junit(&self) -> String {
        let mut output = String::new();

        output.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        output.push_str(&format!(
            "<testsuite name=\"{}\" tests=\"{}\" failures=\"{}\" time=\"{}\">\n",
            xml_escape(&self.title),
            self.summary.total_targets,
            self.summary.failed_targets,
            self.summary.total_duration_ms as f64 / 1000.0
        ));

        for target in &self.results {
            output.push_str(&format!(
                "  <testcase name=\"{}\" time=\"{}\">\n",
                xml_escape(&target.name),
                target.result.duration_ms as f64 / 1000.0
            ));

            if !target.result.passed {
                let failure_msg = if let Some(first) = target.result.failure_details.first() {
                    format!("{:?}: {}", first.failure_type, first.description)
                } else {
                    "Unknown failure".to_string()
                };

                output.push_str(&format!(
                    "    <failure message=\"{}\">{} failures in {} iterations</failure>\n",
                    xml_escape(&failure_msg),
                    target.result.failures,
                    target.result.iterations
                ));
            }

            output.push_str("  </testcase>\n");
        }

        output.push_str("</testsuite>\n");
        output
    }

    /// Save report to file
    pub fn save<P: AsRef<Path>>(&self, path: P, format: ReportFormat) -> std::io::Result<()> {
        let content = match format {
            ReportFormat::Text => self.to_text(),
            ReportFormat::Json => self.to_json(),
            ReportFormat::Markdown => self.to_markdown(),
            ReportFormat::JUnit => self.to_junit(),
        };
        fs::write(path, content)
    }
}

/// Report output format
#[derive(Debug, Clone, Copy)]
pub enum ReportFormat {
    Text,
    Json,
    Markdown,
    JUnit,
}

fn timestamp_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = duration.as_secs();

    let days = secs / 86400;
    let time_of_day = secs % 86400;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;

    let mut year = 1970u64;
    let mut remaining_days = days;
    loop {
        let days_in_year = if year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400)) {
            366
        } else {
            365
        };
        if remaining_days < days_in_year {
            break;
        }
        remaining_days -= days_in_year;
        year += 1;
    }

    let is_leap = year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
    let days_in_months: [u64; 12] = if is_leap {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };

    let mut month = 1;
    for (i, &d) in days_in_months.iter().enumerate() {
        if remaining_days < d {
            month = i + 1;
            break;
        }
        remaining_days -= d;
    }
    let day = remaining_days + 1;

    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hours, minutes, seconds)
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_result(passed: bool, failures: usize) -> FuzzResult {
        FuzzResult {
            iterations: 100,
            successes: if passed { 100 } else { 100 - failures },
            failures,
            panics: if passed { 0 } else { failures / 2 },
            timeouts: 0,
            duration_ms: 50,
            seed: Some(42),
            failure_details: vec![],
            passed,
        }
    }

    #[test]
    fn test_report_creation() {
        let mut report = FuzzReport::new("Test Report");
        report.add_result("target1", make_test_result(true, 0));
        report.add_result("target2", make_test_result(false, 5));

        assert_eq!(report.summary.total_targets, 2);
        assert_eq!(report.summary.passed_targets, 1);
        assert_eq!(report.summary.failed_targets, 1);
        assert!(!report.all_passed());
    }

    #[test]
    fn test_text_report() {
        let mut report = FuzzReport::new("Test Report");
        report.add_result("target1", make_test_result(true, 0));

        let text = report.to_text();
        assert!(text.contains("Test Report"));
        assert!(text.contains("PASS"));
    }

    #[test]
    fn test_markdown_report() {
        let mut report = FuzzReport::new("Test Report");
        report.add_result("target1", make_test_result(true, 0));

        let md = report.to_markdown();
        assert!(md.contains("# Test Report"));
        assert!(md.contains("| Target |"));
    }
}

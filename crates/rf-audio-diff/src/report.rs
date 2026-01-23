//! Report generation for audio diff results

use crate::diff::DiffResult;
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::Path;

/// Report format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReportFormat {
    /// Plain text report
    Text,
    /// JSON report
    Json,
    /// Markdown report
    Markdown,
    /// JUnit XML (for CI integration)
    JUnit,
}

/// Report generator
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffReport {
    /// Report title
    pub title: String,

    /// Timestamp
    pub timestamp: String,

    /// List of diff results
    pub results: Vec<DiffResult>,

    /// Total tests
    pub total: usize,

    /// Passed tests
    pub passed: usize,

    /// Failed tests
    pub failed: usize,
}

impl DiffReport {
    /// Create a new report
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            timestamp: chrono_lite_now(),
            results: Vec::new(),
            total: 0,
            passed: 0,
            failed: 0,
        }
    }

    /// Add a diff result to the report
    pub fn add_result(&mut self, result: DiffResult) {
        self.total += 1;
        if result.passed {
            self.passed += 1;
        } else {
            self.failed += 1;
        }
        self.results.push(result);
    }

    /// Check if all tests passed
    pub fn all_passed(&self) -> bool {
        self.failed == 0
    }

    /// Get pass rate (0.0 - 1.0)
    pub fn pass_rate(&self) -> f64 {
        if self.total == 0 {
            1.0
        } else {
            self.passed as f64 / self.total as f64
        }
    }

    /// Generate report in specified format
    pub fn generate(&self, format: ReportFormat) -> String {
        match format {
            ReportFormat::Text => self.to_text(),
            ReportFormat::Json => self.to_json(),
            ReportFormat::Markdown => self.to_markdown(),
            ReportFormat::JUnit => self.to_junit(),
        }
    }

    /// Save report to file
    pub fn save<P: AsRef<Path>>(&self, path: P, format: ReportFormat) -> std::io::Result<()> {
        let content = self.generate(format);
        let mut file = std::fs::File::create(path)?;
        file.write_all(content.as_bytes())
    }

    fn to_text(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("{}\n", self.title));
        output.push_str(&format!("{}\n\n", "=".repeat(self.title.len())));

        output.push_str(&format!("Timestamp: {}\n", self.timestamp));
        output.push_str(&format!("Total: {} | Passed: {} | Failed: {}\n",
            self.total, self.passed, self.failed));
        output.push_str(&format!("Pass Rate: {:.1}%\n\n", self.pass_rate() * 100.0));

        output.push_str("Results:\n");
        output.push_str(&"-".repeat(80));
        output.push_str("\n");

        for result in &self.results {
            let status = if result.passed { "PASS" } else { "FAIL" };
            output.push_str(&format!("[{}] {} vs {}\n",
                status, result.reference_path, result.test_path));

            if !result.passed {
                for check in &result.checks {
                    if !check.passed {
                        output.push_str(&format!("  ✗ {}: {}\n", check.name, check.description));
                    }
                }
            }
            output.push_str("\n");
        }

        output.push_str(&"-".repeat(80));
        output.push_str("\n");
        output.push_str(&format!("Summary: {} tests, {} passed, {} failed\n",
            self.total, self.passed, self.failed));

        output
    }

    fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_else(|_| "{}".into())
    }

    fn to_markdown(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("# {}\n\n", self.title));
        output.push_str(&format!("**Timestamp:** {}\n\n", self.timestamp));

        // Summary badge
        let status_emoji = if self.all_passed() { "✅" } else { "❌" };
        output.push_str(&format!("## Summary {}\n\n", status_emoji));
        output.push_str("| Metric | Value |\n");
        output.push_str("|--------|-------|\n");
        output.push_str(&format!("| Total | {} |\n", self.total));
        output.push_str(&format!("| Passed | {} |\n", self.passed));
        output.push_str(&format!("| Failed | {} |\n", self.failed));
        output.push_str(&format!("| Pass Rate | {:.1}% |\n\n", self.pass_rate() * 100.0));

        output.push_str("## Results\n\n");

        for result in &self.results {
            let status = if result.passed { "✅ PASS" } else { "❌ FAIL" };
            output.push_str(&format!("### {} - `{}` vs `{}`\n\n",
                status,
                Path::new(&result.reference_path).file_name()
                    .and_then(|n| n.to_str()).unwrap_or(&result.reference_path),
                Path::new(&result.test_path).file_name()
                    .and_then(|n| n.to_str()).unwrap_or(&result.test_path)
            ));

            output.push_str("| Check | Status | Value | Tolerance |\n");
            output.push_str("|-------|--------|-------|----------|\n");
            for check in &result.checks {
                let icon = if check.passed { "✓" } else { "✗" };
                output.push_str(&format!("| {} | {} | {:.6} | {:.6} |\n",
                    check.name, icon, check.actual, check.tolerance));
            }
            output.push_str("\n");

            if !result.passed {
                output.push_str("**Failed Checks:**\n");
                for check in &result.checks {
                    if !check.passed {
                        output.push_str(&format!("- {}: {}\n", check.name, check.description));
                    }
                }
                output.push_str("\n");
            }
        }

        output
    }

    fn to_junit(&self) -> String {
        let mut output = String::new();

        output.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        output.push_str(&format!(
            "<testsuite name=\"{}\" tests=\"{}\" failures=\"{}\" timestamp=\"{}\">\n",
            xml_escape(&self.title),
            self.total,
            self.failed,
            &self.timestamp
        ));

        for result in &self.results {
            let test_name = format!("{} vs {}",
                Path::new(&result.reference_path).file_name()
                    .and_then(|n| n.to_str()).unwrap_or(&result.reference_path),
                Path::new(&result.test_path).file_name()
                    .and_then(|n| n.to_str()).unwrap_or(&result.test_path)
            );

            output.push_str(&format!("  <testcase name=\"{}\">\n", xml_escape(&test_name)));

            if !result.passed {
                let mut failure_msg = String::new();
                for check in &result.checks {
                    if !check.passed {
                        failure_msg.push_str(&format!("{}: {}\n", check.name, check.description));
                    }
                }
                output.push_str(&format!(
                    "    <failure message=\"Audio diff failed\">{}</failure>\n",
                    xml_escape(&failure_msg)
                ));
            }

            output.push_str("  </testcase>\n");
        }

        output.push_str("</testsuite>\n");

        output
    }
}

/// Simple timestamp without full chrono dependency
fn chrono_lite_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = duration.as_secs();

    // Basic ISO 8601 format
    let days_since_1970 = secs / 86400;
    let time_of_day = secs % 86400;

    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;

    // Simplified date calculation (good enough for 2020-2100)
    let mut year = 1970;
    let mut remaining_days = days_since_1970;

    loop {
        let days_in_year = if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
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

    let is_leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days_in_months: [u64; 12] = if is_leap {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };

    let mut month = 0;
    for (i, &days) in days_in_months.iter().enumerate() {
        if remaining_days < days {
            month = i + 1;
            break;
        }
        remaining_days -= days;
    }
    let day = remaining_days + 1;

    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hours, minutes, seconds)
}

/// Escape XML special characters
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
    use crate::config::DiffConfig;
    use crate::diff::AudioDiff;

    fn make_test_result(passed: bool) -> DiffResult {
        let samples: Vec<f64> = (0..1024)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        let test = if passed {
            samples.clone()
        } else {
            samples.iter().map(|&s| s * 0.5).collect()
        };

        AudioDiff::compare_samples(&samples, &test, 44100, &DiffConfig::default()).unwrap()
    }

    #[test]
    fn test_report_creation() {
        let mut report = DiffReport::new("Test Report");
        report.add_result(make_test_result(true));
        report.add_result(make_test_result(false));

        assert_eq!(report.total, 2);
        assert_eq!(report.passed, 1);
        assert_eq!(report.failed, 1);
        assert!(!report.all_passed());
        assert!((report.pass_rate() - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_text_report() {
        let mut report = DiffReport::new("Test Report");
        report.add_result(make_test_result(true));

        let text = report.generate(ReportFormat::Text);
        assert!(text.contains("Test Report"));
        assert!(text.contains("PASS"));
    }

    #[test]
    fn test_json_report() {
        let mut report = DiffReport::new("Test Report");
        report.add_result(make_test_result(true));

        let json = report.generate(ReportFormat::Json);
        assert!(json.contains("\"title\""));
        assert!(json.contains("Test Report"));
    }

    #[test]
    fn test_markdown_report() {
        let mut report = DiffReport::new("Test Report");
        report.add_result(make_test_result(true));

        let md = report.generate(ReportFormat::Markdown);
        assert!(md.contains("# Test Report"));
        assert!(md.contains("| Metric |"));
    }

    #[test]
    fn test_junit_report() {
        let mut report = DiffReport::new("Test Report");
        report.add_result(make_test_result(true));
        report.add_result(make_test_result(false));

        let xml = report.generate(ReportFormat::JUnit);
        assert!(xml.contains("<testsuite"));
        assert!(xml.contains("tests=\"2\""));
        assert!(xml.contains("failures=\"1\""));
    }
}

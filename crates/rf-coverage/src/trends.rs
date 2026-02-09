//! Coverage trend tracking over time

use crate::parser::CoverageData;
use crate::Result;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// A single coverage snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoverageTrend {
    /// Timestamp (ISO 8601)
    pub timestamp: String,
    /// Git commit hash (optional)
    pub commit: Option<String>,
    /// Git branch (optional)
    pub branch: Option<String>,
    /// Line coverage percentage
    pub line_coverage: f64,
    /// Function coverage percentage
    pub function_coverage: f64,
    /// Branch coverage percentage
    pub branch_coverage: f64,
    /// Total lines
    pub total_lines: usize,
}

impl CoverageTrend {
    /// Create trend from coverage data
    pub fn from_data(data: &CoverageData) -> Self {
        Self {
            timestamp: timestamp_now(),
            commit: None,
            branch: None,
            line_coverage: data.total_line_coverage(),
            function_coverage: data.total_function_coverage(),
            branch_coverage: data.total_branch_coverage(),
            total_lines: data.totals.lines_total,
        }
    }

    /// Set commit info
    pub fn with_commit(mut self, commit: impl Into<String>) -> Self {
        self.commit = Some(commit.into());
        self
    }

    /// Set branch info
    pub fn with_branch(mut self, branch: impl Into<String>) -> Self {
        self.branch = Some(branch.into());
        self
    }
}

/// Coverage trend analysis
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TrendAnalysis {
    /// Historical data points
    pub history: Vec<CoverageTrend>,
    /// Maximum history size
    pub max_history: usize,
}

impl TrendAnalysis {
    /// Create new trend analysis
    pub fn new(max_history: usize) -> Self {
        Self {
            history: Vec::new(),
            max_history,
        }
    }

    /// Load from file
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path)?;
        let analysis: TrendAnalysis = serde_json::from_str(&content)?;
        Ok(analysis)
    }

    /// Save to file
    pub fn save<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let content = serde_json::to_string_pretty(self)?;
        fs::write(path, content)?;
        Ok(())
    }

    /// Add new data point
    pub fn add(&mut self, trend: CoverageTrend) {
        self.history.push(trend);

        // Trim to max history
        while self.history.len() > self.max_history {
            self.history.remove(0);
        }
    }

    /// Get latest data point
    pub fn latest(&self) -> Option<&CoverageTrend> {
        self.history.last()
    }

    /// Get previous data point
    pub fn previous(&self) -> Option<&CoverageTrend> {
        if self.history.len() >= 2 {
            Some(&self.history[self.history.len() - 2])
        } else {
            None
        }
    }

    /// Calculate change from previous
    pub fn line_coverage_change(&self) -> Option<f64> {
        match (self.latest(), self.previous()) {
            (Some(latest), Some(previous)) => Some(latest.line_coverage - previous.line_coverage),
            _ => None,
        }
    }

    /// Calculate average line coverage
    pub fn average_line_coverage(&self) -> f64 {
        if self.history.is_empty() {
            0.0
        } else {
            let sum: f64 = self.history.iter().map(|t| t.line_coverage).sum();
            sum / self.history.len() as f64
        }
    }

    /// Calculate minimum line coverage
    pub fn min_line_coverage(&self) -> f64 {
        self.history
            .iter()
            .map(|t| t.line_coverage)
            .fold(f64::INFINITY, f64::min)
    }

    /// Calculate maximum line coverage
    pub fn max_line_coverage(&self) -> f64 {
        self.history
            .iter()
            .map(|t| t.line_coverage)
            .fold(f64::NEG_INFINITY, f64::max)
    }

    /// Check if coverage is improving
    pub fn is_improving(&self) -> bool {
        if self.history.len() < 3 {
            return true;
        }

        // Check last 3 data points
        let recent: Vec<_> = self.history.iter().rev().take(3).collect();
        recent[0].line_coverage >= recent[2].line_coverage
    }

    /// Check if coverage is declining
    pub fn is_declining(&self) -> bool {
        if self.history.len() < 3 {
            return false;
        }

        let recent: Vec<_> = self.history.iter().rev().take(3).collect();
        recent[0].line_coverage < recent[2].line_coverage - 2.0 // 2% tolerance
    }

    /// Generate trend summary
    pub fn summary(&self) -> TrendSummary {
        TrendSummary {
            data_points: self.history.len(),
            current: self.latest().map(|t| t.line_coverage).unwrap_or(0.0),
            previous: self.previous().map(|t| t.line_coverage),
            change: self.line_coverage_change(),
            average: self.average_line_coverage(),
            min: self.min_line_coverage(),
            max: self.max_line_coverage(),
            is_improving: self.is_improving(),
            is_declining: self.is_declining(),
        }
    }

    /// Generate markdown trend report
    pub fn to_markdown(&self) -> String {
        let mut output = String::new();
        let summary = self.summary();

        output.push_str("## Coverage Trend\n\n");

        // Current status
        let trend_icon = if summary.is_improving {
            "📈"
        } else if summary.is_declining {
            "📉"
        } else {
            "➡️"
        };

        output.push_str(&format!(
            "Current: **{:.1}%** {}\n\n",
            summary.current, trend_icon
        ));

        if let Some(change) = summary.change {
            let change_str = if change >= 0.0 {
                format!("+{:.1}%", change)
            } else {
                format!("{:.1}%", change)
            };
            output.push_str(&format!("Change: {}\n", change_str));
        }

        // Statistics
        output.push_str("\n### Statistics\n\n");
        output.push_str(&format!("- Average: {:.1}%\n", summary.average));
        output.push_str(&format!("- Min: {:.1}%\n", summary.min));
        output.push_str(&format!("- Max: {:.1}%\n", summary.max));
        output.push_str(&format!("- Data points: {}\n", summary.data_points));

        // History table (last 10)
        if !self.history.is_empty() {
            output.push_str("\n### History\n\n");
            output.push_str("| Date | Commit | Lines | Functions |\n");
            output.push_str("|------|--------|-------|----------|\n");

            for trend in self.history.iter().rev().take(10) {
                let commit = trend
                    .commit
                    .as_ref()
                    .map(|c| &c[..7.min(c.len())])
                    .unwrap_or("-");
                output.push_str(&format!(
                    "| {} | {} | {:.1}% | {:.1}% |\n",
                    &trend.timestamp[..10],
                    commit,
                    trend.line_coverage,
                    trend.function_coverage
                ));
            }
        }

        output
    }
}

/// Trend summary statistics
#[derive(Debug, Clone)]
pub struct TrendSummary {
    pub data_points: usize,
    pub current: f64,
    pub previous: Option<f64>,
    pub change: Option<f64>,
    pub average: f64,
    pub min: f64,
    pub max: f64,
    pub is_improving: bool,
    pub is_declining: bool,
}

/// Generate ISO 8601 timestamp
fn timestamp_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = duration.as_secs();

    // Simple UTC timestamp
    let days = secs / 86400;
    let time_of_day = secs % 86400;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;

    let mut year = 1970u64;
    let mut remaining_days = days;
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

    let mut month = 1;
    for (i, &d) in days_in_months.iter().enumerate() {
        if remaining_days < d {
            month = i + 1;
            break;
        }
        remaining_days -= d;
    }
    let day = remaining_days + 1;

    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hours, minutes, seconds
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_trend_analysis() {
        let mut analysis = TrendAnalysis::new(100);

        // Add some data points
        analysis.add(CoverageTrend {
            timestamp: "2024-01-01T00:00:00Z".into(),
            commit: Some("abc1234".into()),
            branch: Some("main".into()),
            line_coverage: 70.0,
            function_coverage: 75.0,
            branch_coverage: 60.0,
            total_lines: 1000,
        });

        analysis.add(CoverageTrend {
            timestamp: "2024-01-02T00:00:00Z".into(),
            commit: Some("def5678".into()),
            branch: Some("main".into()),
            line_coverage: 72.0,
            function_coverage: 77.0,
            branch_coverage: 62.0,
            total_lines: 1050,
        });

        assert_eq!(analysis.history.len(), 2);
        assert_eq!(analysis.latest().unwrap().line_coverage, 72.0);
        assert_eq!(analysis.line_coverage_change(), Some(2.0));
    }

    #[test]
    fn test_trend_summary() {
        let mut analysis = TrendAnalysis::new(100);

        for i in 0..5 {
            analysis.add(CoverageTrend {
                timestamp: format!("2024-01-0{}T00:00:00Z", i + 1),
                commit: None,
                branch: None,
                line_coverage: 70.0 + i as f64,
                function_coverage: 75.0,
                branch_coverage: 60.0,
                total_lines: 1000,
            });
        }

        let summary = analysis.summary();
        assert_eq!(summary.data_points, 5);
        assert_eq!(summary.current, 74.0);
        assert!(summary.is_improving);
        assert!(!summary.is_declining);
    }

    #[test]
    fn test_max_history() {
        let mut analysis = TrendAnalysis::new(3);

        for i in 0..5 {
            analysis.add(CoverageTrend {
                timestamp: format!("2024-01-0{}T00:00:00Z", i + 1),
                commit: None,
                branch: None,
                line_coverage: 70.0 + i as f64,
                function_coverage: 75.0,
                branch_coverage: 60.0,
                total_lines: 1000,
            });
        }

        // Should only keep last 3
        assert_eq!(analysis.history.len(), 3);
        assert_eq!(analysis.history[0].line_coverage, 72.0);
    }
}

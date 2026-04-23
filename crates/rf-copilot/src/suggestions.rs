//! Suggestion data types.

use serde::{Deserialize, Serialize};

/// Domain category of a suggestion
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SuggestionCategory {
    VoiceBudget,
    EventCoverage,
    WinTierCalibration,
    FeatureAudio,
    ResponsibleGaming,
    LoopCoverage,
    TimingBenchmark,
    IndustryStandard,
    Compliance,
    Performance,
}

impl SuggestionCategory {
    pub fn display_name(self) -> &'static str {
        match self {
            SuggestionCategory::VoiceBudget        => "Voice Budget",
            SuggestionCategory::EventCoverage      => "Event Coverage",
            SuggestionCategory::WinTierCalibration => "Win Tier Calibration",
            SuggestionCategory::FeatureAudio       => "Feature Audio",
            SuggestionCategory::ResponsibleGaming  => "Responsible Gaming",
            SuggestionCategory::LoopCoverage       => "Loop Coverage",
            SuggestionCategory::TimingBenchmark    => "Timing Benchmark",
            SuggestionCategory::IndustryStandard   => "Industry Standard",
            SuggestionCategory::Compliance         => "Compliance",
            SuggestionCategory::Performance        => "Performance",
        }
    }
}

/// Severity / urgency of a suggestion
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SuggestionSeverity {
    Info,
    Suggestion,
    Warning,
    Critical,
}

impl SuggestionSeverity {
    pub fn display_name(self) -> &'static str {
        match self {
            SuggestionSeverity::Info       => "Info",
            SuggestionSeverity::Suggestion => "Suggestion",
            SuggestionSeverity::Warning    => "Warning",
            SuggestionSeverity::Critical   => "Critical",
        }
    }
}

/// One actionable suggestion from the AI Co-Pilot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CopilotSuggestion {
    /// Unique rule ID (stable across runs)
    pub rule_id: String,
    pub category: SuggestionCategory,
    pub severity: SuggestionSeverity,
    /// Short headline (< 60 chars)
    pub title: String,
    /// Full explanation with context
    pub description: String,
    /// Specific action to take
    pub action: String,
    /// Affected event name (if applicable)
    pub affected_event: Option<String>,
    /// Industry benchmark reference value (if applicable)
    pub benchmark_value: Option<String>,
    /// Can this be auto-applied with one click?
    pub auto_applicable: bool,
}

/// Complete Co-Pilot analysis report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CopilotReport {
    /// Total suggestions
    pub suggestions: Vec<CopilotSuggestion>,
    /// Overall quality score 0–100
    pub quality_score: u8,
    /// Industry match percentage (how close to reference slot)
    pub industry_match_pct: u8,
    /// Closest matching industry reference slot
    pub closest_reference: String,
    /// One-sentence executive summary
    pub summary: String,
}

impl CopilotReport {
    /// Critical suggestions only
    pub fn criticals(&self) -> Vec<&CopilotSuggestion> {
        self.suggestions.iter()
            .filter(|s| s.severity == SuggestionSeverity::Critical)
            .collect()
    }

    /// Warnings + criticals
    pub fn warnings_and_above(&self) -> Vec<&CopilotSuggestion> {
        self.suggestions.iter()
            .filter(|s| s.severity >= SuggestionSeverity::Warning)
            .collect()
    }

    pub fn auto_applicable(&self) -> Vec<&CopilotSuggestion> {
        self.suggestions.iter()
            .filter(|s| s.auto_applicable)
            .collect()
    }
}

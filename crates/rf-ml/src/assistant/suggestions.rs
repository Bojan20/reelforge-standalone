//! Audio processing suggestions

use serde::{Deserialize, Serialize};

/// Suggestion type/category
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SuggestionType {
    /// EQ adjustment
    Eq,
    /// Compression
    Compression,
    /// Limiting
    Limiting,
    /// Saturation/Warmth
    Saturation,
    /// Stereo width
    StereoWidth,
    /// Reverb
    Reverb,
    /// Noise reduction
    NoiseReduction,
    /// Level adjustment
    Level,
    /// Dynamic range
    DynamicRange,
    /// Frequency balance
    FrequencyBalance,
    /// Phase correction
    Phase,
    /// Transient shaping
    Transients,
    /// De-essing
    DeEss,
    /// Low-end treatment
    LowEnd,
    /// High-end treatment
    HighEnd,
    /// Mid/Side balance
    MidSide,
    /// General mix
    Mix,
}

impl SuggestionType {
    /// Get display name
    pub fn name(&self) -> &'static str {
        match self {
            SuggestionType::Eq => "EQ",
            SuggestionType::Compression => "Compression",
            SuggestionType::Limiting => "Limiting",
            SuggestionType::Saturation => "Saturation",
            SuggestionType::StereoWidth => "Stereo Width",
            SuggestionType::Reverb => "Reverb",
            SuggestionType::NoiseReduction => "Noise Reduction",
            SuggestionType::Level => "Level",
            SuggestionType::DynamicRange => "Dynamic Range",
            SuggestionType::FrequencyBalance => "Frequency Balance",
            SuggestionType::Phase => "Phase",
            SuggestionType::Transients => "Transients",
            SuggestionType::DeEss => "De-Essing",
            SuggestionType::LowEnd => "Low End",
            SuggestionType::HighEnd => "High End",
            SuggestionType::MidSide => "Mid/Side",
            SuggestionType::Mix => "Mix",
        }
    }

    /// Get icon name
    pub fn icon(&self) -> &'static str {
        match self {
            SuggestionType::Eq => "eq",
            SuggestionType::Compression => "compressor",
            SuggestionType::Limiting => "limiter",
            SuggestionType::Saturation => "saturation",
            SuggestionType::StereoWidth => "stereo",
            SuggestionType::Reverb => "reverb",
            SuggestionType::NoiseReduction => "noise",
            SuggestionType::Level => "volume",
            SuggestionType::DynamicRange => "dynamics",
            SuggestionType::FrequencyBalance => "frequency",
            SuggestionType::Phase => "phase",
            SuggestionType::Transients => "transient",
            SuggestionType::DeEss => "deess",
            SuggestionType::LowEnd => "bass",
            SuggestionType::HighEnd => "treble",
            SuggestionType::MidSide => "midside",
            SuggestionType::Mix => "mix",
        }
    }
}

/// Suggestion priority
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum SuggestionPriority {
    /// Low priority (optional improvement)
    Low = 1,
    /// Medium priority (recommended)
    Medium = 2,
    /// High priority (important)
    High = 3,
    /// Critical (should fix)
    Critical = 4,
}

impl SuggestionPriority {
    /// Get display name
    pub fn name(&self) -> &'static str {
        match self {
            SuggestionPriority::Low => "Low",
            SuggestionPriority::Medium => "Medium",
            SuggestionPriority::High => "High",
            SuggestionPriority::Critical => "Critical",
        }
    }

    /// Get color hex
    pub fn color(&self) -> &'static str {
        match self {
            SuggestionPriority::Low => "#40c8ff",      // Cyan
            SuggestionPriority::Medium => "#ffff40",   // Yellow
            SuggestionPriority::High => "#ff9040",     // Orange
            SuggestionPriority::Critical => "#ff4040", // Red
        }
    }
}

/// Processing parameter suggestion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParameterSuggestion {
    /// Parameter name
    pub name: String,
    /// Current value
    pub current: f32,
    /// Suggested value
    pub suggested: f32,
    /// Unit (dB, Hz, %, etc.)
    pub unit: String,
}

/// Complete suggestion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Suggestion {
    /// Suggestion type
    pub suggestion_type: SuggestionType,

    /// Priority
    pub priority: SuggestionPriority,

    /// Short description
    pub title: String,

    /// Detailed description
    pub description: String,

    /// Reasoning (why this is suggested)
    pub reasoning: String,

    /// Parameter suggestions
    pub parameters: Vec<ParameterSuggestion>,

    /// Confidence (0.0 - 1.0)
    pub confidence: f32,

    /// Impact estimate (how much difference it will make)
    pub impact: f32,
}

impl Suggestion {
    /// Create new suggestion
    pub fn new(
        suggestion_type: SuggestionType,
        priority: SuggestionPriority,
        title: impl Into<String>,
        description: impl Into<String>,
    ) -> Self {
        Self {
            suggestion_type,
            priority,
            title: title.into(),
            description: description.into(),
            reasoning: String::new(),
            parameters: Vec::new(),
            confidence: 1.0,
            impact: 0.5,
        }
    }

    /// Add reasoning
    pub fn with_reasoning(mut self, reasoning: impl Into<String>) -> Self {
        self.reasoning = reasoning.into();
        self
    }

    /// Add parameter suggestion
    pub fn with_parameter(
        mut self,
        name: impl Into<String>,
        current: f32,
        suggested: f32,
        unit: impl Into<String>,
    ) -> Self {
        self.parameters.push(ParameterSuggestion {
            name: name.into(),
            current,
            suggested,
            unit: unit.into(),
        });
        self
    }

    /// Set confidence
    pub fn with_confidence(mut self, confidence: f32) -> Self {
        self.confidence = confidence.clamp(0.0, 1.0);
        self
    }

    /// Set impact
    pub fn with_impact(mut self, impact: f32) -> Self {
        self.impact = impact.clamp(0.0, 1.0);
        self
    }
}

/// Generate suggestions based on analysis
pub struct SuggestionGenerator {
    /// Target loudness (LUFS)
    target_loudness: f32,

    /// Target true peak (dBTP)
    target_true_peak: f32,

    /// Genre-specific settings
    genre_presets: bool,
}

impl Default for SuggestionGenerator {
    fn default() -> Self {
        Self {
            target_loudness: -14.0, // Streaming standard
            target_true_peak: -1.0,
            genre_presets: true,
        }
    }
}

impl SuggestionGenerator {
    /// Create new generator
    pub fn new() -> Self {
        Self::default()
    }

    /// Set target loudness
    pub fn with_target_loudness(mut self, lufs: f32) -> Self {
        self.target_loudness = lufs;
        self
    }

    /// Generate suggestions from loudness analysis
    pub fn suggest_from_loudness(
        &self,
        integrated_lufs: f32,
        true_peak_db: f32,
        loudness_range: f32,
    ) -> Vec<Suggestion> {
        let mut suggestions = Vec::new();

        // Check loudness target
        let loudness_diff = integrated_lufs - self.target_loudness;
        if loudness_diff.abs() > 1.0 {
            let direction = if loudness_diff > 0.0 {
                "reduce"
            } else {
                "increase"
            };
            suggestions.push(
                Suggestion::new(
                    SuggestionType::Level,
                    if loudness_diff.abs() > 3.0 {
                        SuggestionPriority::High
                    } else {
                        SuggestionPriority::Medium
                    },
                    format!("Adjust loudness ({:.1} dB)", -loudness_diff),
                    format!(
                        "Current loudness is {:.1} LUFS. Target is {:.1} LUFS. {} by {:.1} dB.",
                        integrated_lufs,
                        self.target_loudness,
                        direction,
                        loudness_diff.abs()
                    ),
                )
                .with_reasoning("Loudness should match streaming platform standards.")
                .with_parameter("Gain", 0.0, -loudness_diff, "dB")
                .with_confidence(0.95)
                .with_impact(0.8),
            );
        }

        // Check true peak
        if true_peak_db > self.target_true_peak {
            let over = true_peak_db - self.target_true_peak;
            suggestions.push(
                Suggestion::new(
                    SuggestionType::Limiting,
                    SuggestionPriority::High,
                    format!("Reduce true peak ({:.1} dB over)", over),
                    format!(
                        "True peak is {:.1} dBTP, exceeds target of {:.1} dBTP. Use a limiter.",
                        true_peak_db, self.target_true_peak
                    ),
                )
                .with_reasoning(
                    "Peaks above -1 dBTP may cause distortion on some playback systems.",
                )
                .with_parameter("Ceiling", true_peak_db, self.target_true_peak, "dBTP")
                .with_confidence(0.98)
                .with_impact(0.7),
            );
        }

        // Check dynamic range
        if loudness_range < 4.0 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::DynamicRange,
                    SuggestionPriority::Low,
                    "Consider more dynamics",
                    format!(
                        "Loudness range is only {:.1} LU. Track may sound flat or over-compressed.",
                        loudness_range
                    ),
                )
                .with_reasoning("Low dynamic range can cause listener fatigue.")
                .with_confidence(0.7)
                .with_impact(0.4),
            );
        } else if loudness_range > 15.0 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::Compression,
                    SuggestionPriority::Medium,
                    "Consider gentle compression",
                    format!(
                        "Loudness range is {:.1} LU. Some compression may improve consistency.",
                        loudness_range
                    ),
                )
                .with_reasoning(
                    "High dynamic range may not translate well to all listening environments.",
                )
                .with_parameter("Ratio", 1.0, 2.0, ":1")
                .with_confidence(0.6)
                .with_impact(0.5),
            );
        }

        suggestions
    }

    /// Generate suggestions from spectral analysis
    pub fn suggest_from_spectral(
        &self,
        low_ratio: f32,
        _mid_ratio: f32,
        high_ratio: f32,
        _centroid_hz: f32,
    ) -> Vec<Suggestion> {
        let mut suggestions = Vec::new();

        // Check frequency balance
        if low_ratio > 0.4 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::LowEnd,
                    SuggestionPriority::Medium,
                    "Reduce low-end buildup",
                    format!(
                        "Low frequencies account for {:.0}% of energy. Consider high-pass filter or EQ cut.",
                        low_ratio * 100.0
                    ),
                )
                .with_reasoning("Excessive low-end can cause muddiness and masking.")
                .with_parameter("High-pass", 20.0, 40.0, "Hz")
                .with_confidence(0.75)
                .with_impact(0.6),
            );
        }

        if high_ratio < 0.1 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::HighEnd,
                    SuggestionPriority::Low,
                    "Consider adding brightness",
                    format!(
                        "High frequencies only account for {:.0}% of energy. Track may sound dull.",
                        high_ratio * 100.0
                    ),
                )
                .with_reasoning("Lack of high-end can make a mix sound dated or lifeless.")
                .with_parameter("Shelf boost at 8kHz", 0.0, 2.0, "dB")
                .with_confidence(0.6)
                .with_impact(0.4),
            );
        } else if high_ratio > 0.3 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::DeEss,
                    SuggestionPriority::Medium,
                    "Check for harshness",
                    format!(
                        "High frequency content is {:.0}%. May be harsh or sibilant.",
                        high_ratio * 100.0
                    ),
                )
                .with_reasoning("Excessive high-end can cause listener fatigue.")
                .with_confidence(0.65)
                .with_impact(0.5),
            );
        }

        suggestions
    }

    /// Generate suggestions from stereo analysis
    pub fn suggest_from_stereo(
        &self,
        width: f32,
        correlation: f32,
        balance: f32,
    ) -> Vec<Suggestion> {
        let mut suggestions = Vec::new();

        // Check correlation (phase issues)
        if correlation < 0.0 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::Phase,
                    SuggestionPriority::Critical,
                    "Phase issues detected",
                    format!(
                        "Stereo correlation is {:.2}. Track will have problems in mono playback.",
                        correlation
                    ),
                )
                .with_reasoning(
                    "Negative correlation indicates out-of-phase content that will cancel in mono.",
                )
                .with_confidence(0.95)
                .with_impact(0.9),
            );
        } else if correlation < 0.3 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::Phase,
                    SuggestionPriority::High,
                    "Low mono compatibility",
                    format!(
                        "Stereo correlation is {:.2}. May have issues on mono systems.",
                        correlation
                    ),
                )
                .with_reasoning("Low correlation may cause frequency cancellation in mono.")
                .with_confidence(0.85)
                .with_impact(0.7),
            );
        }

        // Check balance
        if balance.abs() > 0.1 {
            let direction = if balance > 0.0 { "right" } else { "left" };
            suggestions.push(
                Suggestion::new(
                    SuggestionType::StereoWidth,
                    SuggestionPriority::Medium,
                    format!("Mix leans {}", direction),
                    format!(
                        "Stereo balance is {:.0}% {}. Consider centering.",
                        balance.abs() * 100.0,
                        direction
                    ),
                )
                .with_reasoning("Unbalanced mixes can sound unprofessional.")
                .with_parameter("Balance", balance * 100.0, 0.0, "%")
                .with_confidence(0.8)
                .with_impact(0.5),
            );
        }

        // Check width
        if width < 0.2 {
            suggestions.push(
                Suggestion::new(
                    SuggestionType::StereoWidth,
                    SuggestionPriority::Low,
                    "Consider widening stereo image",
                    format!(
                        "Stereo width is only {:.0}%. May sound narrow.",
                        width * 100.0
                    ),
                )
                .with_reasoning("Wider stereo can create more immersive listening experience.")
                .with_confidence(0.5)
                .with_impact(0.3),
            );
        }

        suggestions
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_suggestion_priority_ordering() {
        assert!(SuggestionPriority::Critical > SuggestionPriority::High);
        assert!(SuggestionPriority::High > SuggestionPriority::Medium);
        assert!(SuggestionPriority::Medium > SuggestionPriority::Low);
    }

    #[test]
    fn test_loudness_suggestions() {
        let gen = SuggestionGenerator::new();

        // Too loud
        let suggestions = gen.suggest_from_loudness(-10.0, -0.5, 8.0);
        assert!(!suggestions.is_empty());
        assert!(suggestions
            .iter()
            .any(|s| s.suggestion_type == SuggestionType::Level));
        assert!(suggestions
            .iter()
            .any(|s| s.suggestion_type == SuggestionType::Limiting));

        // On target
        let suggestions = gen.suggest_from_loudness(-14.0, -1.5, 8.0);
        assert!(
            suggestions.is_empty()
                || suggestions
                    .iter()
                    .all(|s| s.priority < SuggestionPriority::High)
        );
    }

    #[test]
    fn test_phase_suggestions() {
        let gen = SuggestionGenerator::new();

        // Phase issues
        let suggestions = gen.suggest_from_stereo(0.5, -0.2, 0.0);
        assert!(suggestions
            .iter()
            .any(|s| s.priority == SuggestionPriority::Critical));
    }
}

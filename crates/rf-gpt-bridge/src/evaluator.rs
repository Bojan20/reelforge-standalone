// file: crates/rf-gpt-bridge/src/evaluator.rs
//! Response Evaluator — Corti grades GPT responses before accepting them.
//!
//! NOT every GPT response is gold. The evaluator applies heuristic quality
//! checks to filter out garbage, detect hallucinations, and score usefulness.
//!
//! This is Corti's quality gate: GPT proposes, Corti disposes.

use crate::protocol::GptIntent;
use crate::roles::{GptPersona, OutputFormat};
use serde::{Deserialize, Serialize};

/// Quality evaluation result for a GPT response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvaluationResult {
    /// Overall quality score (0.0 = garbage, 1.0 = excellent).
    pub quality: f64,
    /// Should Corti accept this response?
    pub accepted: bool,
    /// Breakdown of individual quality dimensions.
    pub dimensions: QualityDimensions,
    /// Human-readable verdict.
    pub verdict: String,
    /// Specific issues found.
    pub issues: Vec<QualityIssue>,
}

/// Individual quality dimensions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityDimensions {
    /// Does the response actually answer the question? (0.0 - 1.0)
    pub relevance: f64,
    /// Is the response actionable / concrete? (0.0 - 1.0)
    pub specificity: f64,
    /// Does the format match what was requested? (0.0 - 1.0)
    pub format_compliance: f64,
    /// Is the response appropriately sized? (0.0 - 1.0)
    pub length_appropriateness: f64,
    /// Does it smell like hallucination? (0.0 = likely hallucination, 1.0 = grounded)
    pub groundedness: f64,
}

/// A specific quality issue found in the response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityIssue {
    pub severity: IssueSeverity,
    pub description: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueSeverity {
    /// Informational — doesn't affect acceptance.
    Info,
    /// Warning — reduces quality score.
    Warning,
    /// Critical — auto-reject.
    Critical,
}

/// The evaluator — scores GPT responses.
pub struct ResponseEvaluator {
    /// Minimum quality threshold for acceptance.
    min_quality: f64,
    /// Minimum response length (chars) to not be "empty".
    min_response_length: usize,
    /// Maximum response length before penalty.
    max_response_length: usize,
}

impl Default for ResponseEvaluator {
    fn default() -> Self {
        Self::new()
    }
}

impl ResponseEvaluator {
    pub fn new() -> Self {
        Self {
            min_quality: 0.4,
            min_response_length: 20,
            max_response_length: 10000,
        }
    }

    pub fn with_threshold(mut self, threshold: f64) -> Self {
        self.min_quality = threshold.clamp(0.0, 1.0);
        self
    }

    /// Evaluate a GPT response.
    pub fn evaluate(
        &self,
        response: &str,
        query: &str,
        persona: GptPersona,
        intent: GptIntent,
    ) -> EvaluationResult {
        let def = persona.definition();
        let mut issues = Vec::new();

        // 1. Length check
        let length_score = self.score_length(response, def.max_response_hint, &mut issues);

        // 2. Format compliance
        let format_score = self.score_format(response, def.output_format, &mut issues);

        // 3. Relevance (does it reference concepts from the query?)
        let relevance_score = self.score_relevance(response, query, &mut issues);

        // 4. Specificity (concrete vs. generic)
        let specificity_score = self.score_specificity(response, intent, &mut issues);

        // 5. Groundedness (hallucination detection)
        let groundedness_score = self.score_groundedness(response, &mut issues);

        let dimensions = QualityDimensions {
            relevance: relevance_score,
            specificity: specificity_score,
            format_compliance: format_score,
            length_appropriateness: length_score,
            groundedness: groundedness_score,
        };

        // Weighted overall score
        let quality = relevance_score * 0.30
            + specificity_score * 0.25
            + format_score * 0.15
            + length_score * 0.15
            + groundedness_score * 0.15;

        // Critical issues force rejection
        let has_critical = issues.iter().any(|i| i.severity == IssueSeverity::Critical);
        let accepted = !has_critical && quality >= self.min_quality;

        let verdict = if has_critical {
            format!("ODBIJENO — kritičan problem: {}",
                issues.iter()
                    .filter(|i| i.severity == IssueSeverity::Critical)
                    .map(|i| i.description.as_str())
                    .collect::<Vec<_>>()
                    .join("; "))
        } else if accepted {
            format!("PRIHVAĆENO — kvalitet {:.0}%", quality * 100.0)
        } else {
            format!("ODBIJENO — kvalitet {:.0}% (minimum: {:.0}%)", quality * 100.0, self.min_quality * 100.0)
        };

        EvaluationResult {
            quality,
            accepted,
            dimensions,
            verdict,
            issues,
        }
    }

    fn score_length(
        &self,
        response: &str,
        max_hint: usize,
        issues: &mut Vec<QualityIssue>,
    ) -> f64 {
        let len = response.len();

        if len < self.min_response_length {
            issues.push(QualityIssue {
                severity: IssueSeverity::Critical,
                description: format!("Odgovor prekratak: {} karaktera", len),
            });
            return 0.0;
        }

        if len > self.max_response_length {
            issues.push(QualityIssue {
                severity: IssueSeverity::Warning,
                description: format!("Odgovor predugačak: {} karaktera", len),
            });
            return 0.5;
        }

        if max_hint > 0 && len > max_hint * 2 {
            issues.push(QualityIssue {
                severity: IssueSeverity::Warning,
                description: format!("Odgovor {} 2x duži od očekivanog ({})", len, max_hint),
            });
            return 0.6;
        }

        1.0
    }

    fn score_format(
        &self,
        response: &str,
        expected: OutputFormat,
        issues: &mut Vec<QualityIssue>,
    ) -> f64 {
        match expected {
            OutputFormat::Json => {
                // Check if response contains valid JSON
                let has_json = response.contains('{') && response.contains('}')
                    || response.contains('[') && response.contains(']');
                if !has_json {
                    issues.push(QualityIssue {
                        severity: IssueSeverity::Warning,
                        description: "Očekivan JSON format, ali nema JSON strukture".into(),
                    });
                    return 0.3;
                }
                // Try to extract and parse JSON
                if let Some(json_str) = extract_json_block(response) {
                    if serde_json::from_str::<serde_json::Value>(json_str).is_ok() {
                        return 1.0;
                    }
                }
                // Has JSON-like structure but not valid
                0.6
            }

            OutputFormat::NumberedList => {
                let lines: Vec<&str> = response.lines().collect();
                let numbered_lines = lines
                    .iter()
                    .filter(|l| {
                        let trimmed = l.trim();
                        trimmed.starts_with(|c: char| c.is_ascii_digit())
                            && (trimmed.contains('.') || trimmed.contains(')'))
                    })
                    .count();

                if numbered_lines == 0 {
                    issues.push(QualityIssue {
                        severity: IssueSeverity::Warning,
                        description: "Očekivana numerisana lista, ali nema numerisanih stavki".into(),
                    });
                    return 0.3;
                }

                let ratio = numbered_lines as f64 / lines.len().max(1) as f64;
                if ratio < 0.3 {
                    issues.push(QualityIssue {
                        severity: IssueSeverity::Info,
                        description: format!(
                            "Samo {}% linija je numerisano",
                            (ratio * 100.0) as u32
                        ),
                    });
                }
                ratio.clamp(0.3, 1.0)
            }

            OutputFormat::CodeOnly => {
                let has_code_block = response.contains("```");
                if !has_code_block {
                    issues.push(QualityIssue {
                        severity: IssueSeverity::Warning,
                        description: "Očekivan code-only format, ali nema code blokova".into(),
                    });
                    return 0.4;
                }
                1.0
            }

            OutputFormat::Markdown => {
                // Markdown is flexible — just check for basic structure
                let has_headers = response.contains('#');
                let has_formatting = response.contains('*') || response.contains('-') || has_headers;
                if has_formatting { 1.0 } else { 0.7 }
            }

            OutputFormat::FreeText => 1.0, // No format constraint
        }
    }

    fn score_relevance(
        &self,
        response: &str,
        query: &str,
        issues: &mut Vec<QualityIssue>,
    ) -> f64 {
        // Extract significant words from query (>3 chars, not stop words)
        let query_words: Vec<&str> = query
            .split_whitespace()
            .filter(|w| w.len() > 3)
            .filter(|w| !STOP_WORDS.contains(&w.to_lowercase().as_str()))
            .collect();

        if query_words.is_empty() {
            return 0.7; // Can't evaluate — neutral score
        }

        let response_lower = response.to_lowercase();
        let matched = query_words
            .iter()
            .filter(|w| response_lower.contains(&w.to_lowercase()))
            .count();

        let ratio = matched as f64 / query_words.len() as f64;

        if ratio < 0.1 {
            issues.push(QualityIssue {
                severity: IssueSeverity::Warning,
                description: "Odgovor ne referencira ključne reči iz pitanja".into(),
            });
        }

        // Scale: 0% match → 0.2, 50% match → 0.7, 100% match → 1.0
        0.2 + ratio * 0.8
    }

    fn score_specificity(
        &self,
        response: &str,
        intent: GptIntent,
        issues: &mut Vec<QualityIssue>,
    ) -> f64 {
        // Count specificity indicators
        let mut score = 0.5; // Baseline

        // Code references boost specificity
        if response.contains("```") || response.contains("fn ") || response.contains("struct ") {
            score += 0.15;
        }

        // File paths boost specificity
        if response.contains(".rs") || response.contains(".dart") || response.contains(".ts") {
            score += 0.1;
        }

        // Numbers and measurements boost specificity
        let has_numbers = response.chars().filter(|c| c.is_ascii_digit()).count() > 3;
        if has_numbers {
            score += 0.1;
        }

        // Generic phrases penalize
        let generic_phrases = [
            "generally speaking",
            "it depends",
            "there are many ways",
            "in general",
            "uopšteno",
            "zavisi od",
            "postoji mnogo načina",
        ];
        let generic_count = generic_phrases
            .iter()
            .filter(|p| response.to_lowercase().contains(*p))
            .count();
        score -= generic_count as f64 * 0.1;

        // Intent-specific checks
        match intent {
            GptIntent::Debugging
                // Debugging should mention specific error/cause
                if !response.contains("error") && !response.contains("greška") && !response.contains("bug") => {
                    score -= 0.1;
                }
            GptIntent::CodeReview
                // Code review should reference specific code
                if !response.contains("```") && !response.contains("linija") && !response.contains("line") => {
                    score -= 0.1;
                }
            _ => {}
        }

        if score < 0.3 {
            issues.push(QualityIssue {
                severity: IssueSeverity::Warning,
                description: "Odgovor je previše generičan — nedostaju konkretni detalji".into(),
            });
        }

        score.clamp(0.0, 1.0)
    }

    fn score_groundedness(
        &self,
        response: &str,
        issues: &mut Vec<QualityIssue>,
    ) -> f64 {
        let mut score: f64 = 1.0;

        // Hallucination red flags
        let hallucination_indicators = [
            // Fake confidence
            ("as of my last update", -0.2),
            ("I believe that", -0.1),
            ("as far as I know", -0.1),
            // Making up sources
            ("according to the documentation at", -0.15),
            ("the official guide states", -0.1),
            // Contradictions within response
            // (can't easily detect, but excessive hedging is a sign)
            ("however, it's also possible", -0.05),
            ("on the other hand", -0.05),
        ];

        for (indicator, penalty) in &hallucination_indicators {
            if response.to_lowercase().contains(indicator) {
                score += penalty; // penalty is negative
            }
        }

        // Excessive certainty about unknowable things
        let certainty_words = ["definitely", "certainly", "absolutely", "without doubt",
                               "sigurno", "definitivno", "apsolutno"];
        let certainty_count = certainty_words
            .iter()
            .filter(|w| response.to_lowercase().contains(*w))
            .count();
        if certainty_count > 2 {
            score -= 0.1;
            issues.push(QualityIssue {
                severity: IssueSeverity::Info,
                description: "Preterana sigurnost — moguća halucinacija".into(),
            });
        }

        score.clamp(0.0, 1.0)
    }
}

/// Extract the first JSON block from a response (between ``` markers or raw).
fn extract_json_block(text: &str) -> Option<&str> {
    // Try code fence first
    if let Some(start) = text.find("```json") {
        let content_start = start + 7;
        if let Some(end) = text[content_start..].find("```") {
            return Some(text[content_start..content_start + end].trim());
        }
    }
    if let Some(start) = text.find("```") {
        let content_start = start + 3;
        // Skip language identifier if present
        let line_end = text[content_start..].find('\n').unwrap_or(0);
        let actual_start = content_start + line_end;
        if let Some(end) = text[actual_start..].find("```") {
            return Some(text[actual_start..actual_start + end].trim());
        }
    }

    // Try raw JSON (first { to last })
    if let Some(start) = text.find('{') {
        if let Some(end) = text.rfind('}') {
            if end > start {
                return Some(&text[start..=end]);
            }
        }
    }

    // Try raw JSON array
    if let Some(start) = text.find('[') {
        if let Some(end) = text.rfind(']') {
            if end > start {
                return Some(&text[start..=end]);
            }
        }
    }

    None
}

// Serbian + English stop words (common words that don't indicate relevance)
const STOP_WORDS: &[&str] = &[
    "the", "and", "for", "are", "but", "not", "you", "all", "can",
    "her", "was", "one", "our", "out", "this", "that", "with", "have",
    "from", "they", "been", "said", "each", "which", "their", "will",
    "kako", "koji", "koja", "koje", "ovaj", "ova", "ovo", "biti",
    "jest", "može", "treba", "samo", "kada", "gde", "zašto",
];

#[cfg(test)]
mod tests {
    use super::*;

    fn evaluator() -> ResponseEvaluator {
        ResponseEvaluator::new()
    }

    #[test]
    fn accepts_good_response() {
        let result = evaluator().evaluate(
            "## Buffer Underrun Analiza\n\nProblem je u audio thread alokaciji na liniji 42 u `engine.rs`.\nPreporučujem pre-alocirani ring buffer od 4096 sampleova.\n\n```rust\nlet buffer = vec![0.0f32; 4096];\n```",
            "analiziraj buffer underrun problem u audio engine",
            GptPersona::DomainResearcher,
            GptIntent::Analysis,
        );
        assert!(result.accepted);
        assert!(result.quality > 0.5);
    }

    #[test]
    fn rejects_empty_response() {
        let result = evaluator().evaluate(
            "OK",
            "analiziraj kompleksan problem",
            GptPersona::DomainResearcher,
            GptIntent::Analysis,
        );
        assert!(!result.accepted);
        assert!(result.issues.iter().any(|i| i.severity == IssueSeverity::Critical));
    }

    #[test]
    fn penalizes_generic_response() {
        let result = evaluator().evaluate(
            "Generally speaking, there are many ways to solve this problem. It depends on your specific use case and requirements. In general, you should consider the trade-offs between different approaches.",
            "kako da optimizujem audio rendering pipeline",
            GptPersona::DomainResearcher,
            GptIntent::Analysis,
        );
        // Should have low specificity
        assert!(result.dimensions.specificity < 0.5);
    }

    #[test]
    fn validates_json_format() {
        let result = evaluator().evaluate(
            r#"Evo edge case-ova:
```json
[
  {"name": "zero buffer", "input": "0", "expected": "graceful error", "severity": "critical", "category": "boundary"},
  {"name": "huge buffer", "input": "999999999", "expected": "OOM handling", "severity": "high", "category": "resource"}
]
```"#,
            "generiši edge case za buffer",
            GptPersona::TestOracle,
            GptIntent::Debugging,
        );
        assert!(result.dimensions.format_compliance > 0.8);
    }

    #[test]
    fn validates_numbered_list() {
        let result = evaluator().evaluate(
            "1. AudioGraph Pro\n2. SoundForge Ultra\n3. WaveSmith\n4. ToneWeaver\n5. BeatAlchemy",
            "generiši 5 imena za audio plugin",
            GptPersona::BulkGenerator,
            GptIntent::Creative,
        );
        assert!(result.dimensions.format_compliance > 0.8);
    }

    #[test]
    fn detects_hallucination_signals() {
        let result = evaluator().evaluate(
            "As of my last update, the official guide states that you should definitely and absolutely use this approach. According to the documentation at docs.example.com, this is certainly the best way.",
            "kako da implementiram audio graph",
            GptPersona::DomainResearcher,
            GptIntent::Architecture,
        );
        assert!(result.dimensions.groundedness < 0.8);
    }

    #[test]
    fn extract_json_from_code_fence() {
        let text = r#"Evo rezultata:
```json
{"key": "value"}
```
Gotovo."#;
        let json = extract_json_block(text).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(json).is_ok());
    }

    #[test]
    fn extract_raw_json() {
        let text = "Rezultat: {\"key\": \"value\"} to je to.";
        let json = extract_json_block(text).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(json).is_ok());
    }

    #[test]
    fn custom_threshold() {
        let strict = ResponseEvaluator::new().with_threshold(0.9);
        let result = strict.evaluate(
            "Ovo je OK odgovor ali nije sjajan. Nema konkretnog koda ili specifičnih detalja o problemu.",
            "kako da fixujem bug",
            GptPersona::DomainResearcher,
            GptIntent::Debugging,
        );
        // With strict threshold, mediocre responses get rejected
        assert!(!result.accepted || result.quality >= 0.9);
    }
}

// file: crates/rf-brain-router/src/classifier.rs
//! TaskClassifier — analyzes a query and determines which AI model should handle it.
//!
//! This is the brain of the brain router. It examines:
//! - Keywords and patterns in the query
//! - Domain-specific signals (math notation, code patterns, creative language)
//! - Complexity indicators (multi-file, architectural scope)
//! - Language and intent markers
//!
//! The classifier outputs a `TaskDomain` which the `BrainRouter` maps to a `ModelId`.

use crate::provider::ModelId;
use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// TASK DOMAIN — what kind of task is this?
// ═══════════════════════════════════════════════════════════════════════════════

/// High-level domain classification for a task.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum TaskDomain {
    /// Architecture, multi-file refactoring, FFI design, lifecycle management.
    /// Deep reasoning over large codebases. Needs massive context window.
    /// → Claude Opus
    Architecture,

    /// Daily coding: bug fixes, tests, small features, quick edits.
    /// Speed matters more than depth.
    /// → Claude Sonnet
    DailyCoding,

    /// Mathematical computation: RTP, volatility, hit frequency, variance models,
    /// probability distributions, algorithm design, competitive programming.
    /// → DeepSeek-R1
    Mathematics,

    /// UI/UX design, copywriting, naming, branding, marketing text, translations.
    /// Creative tasks requiring cultural awareness and linguistic fluency.
    /// → GPT-4o
    Creative,

    /// Domain research: industry standards, best practices, competitive analysis.
    /// Broad knowledge retrieval.
    /// → GPT-4o (wide training data)
    Research,

    /// Code review, security audit, pattern detection.
    /// Needs deep understanding + breadth.
    /// → Claude Opus
    CodeReview,

    /// Documentation: API docs, changelogs, user guides.
    /// → Claude Sonnet (fast + accurate)
    Documentation,

    /// Slot game specific: reel math, paytable design, bonus mechanics,
    /// volatility tuning, RNG analysis.
    /// → DeepSeek-R1 (pure math)
    SlotMath,

    /// Audio/DSP: signal processing, filter design, spectral analysis,
    /// SIMD optimization, real-time constraints.
    /// → Claude Opus (deep system understanding)
    AudioDsp,

    /// General/unknown — use the default model.
    General,
}

impl TaskDomain {
    /// The primary (best) model for this domain.
    pub fn primary_model(&self) -> ModelId {
        match self {
            Self::Architecture => ModelId::ClaudeOpus,
            Self::DailyCoding => ModelId::ClaudeSonnet,
            Self::Mathematics => ModelId::DeepSeekR1,
            Self::Creative => ModelId::Gpt4o,
            Self::Research => ModelId::Gpt4o,
            Self::CodeReview => ModelId::ClaudeOpus,
            Self::Documentation => ModelId::ClaudeSonnet,
            Self::SlotMath => ModelId::DeepSeekR1,
            Self::AudioDsp => ModelId::ClaudeOpus,
            Self::General => ModelId::ClaudeSonnet,
        }
    }

    /// Fallback chain — if primary fails, try these in order.
    pub fn fallback_chain(&self) -> Vec<ModelId> {
        match self {
            Self::Architecture => vec![ModelId::ClaudeSonnet, ModelId::Gpt4o],
            Self::DailyCoding => vec![ModelId::Gpt4oMini, ModelId::DeepSeekV3],
            Self::Mathematics => vec![ModelId::DeepSeekV3, ModelId::ClaudeOpus],
            Self::Creative => vec![ModelId::ClaudeSonnet, ModelId::Gpt4oMini],
            Self::Research => vec![ModelId::ClaudeOpus, ModelId::DeepSeekV3],
            Self::CodeReview => vec![ModelId::ClaudeSonnet, ModelId::Gpt4o],
            Self::Documentation => vec![ModelId::Gpt4oMini, ModelId::DeepSeekV3],
            Self::SlotMath => vec![ModelId::DeepSeekV3, ModelId::ClaudeOpus],
            Self::AudioDsp => vec![ModelId::ClaudeSonnet, ModelId::DeepSeekR1],
            Self::General => vec![ModelId::Gpt4oMini, ModelId::DeepSeekV3],
        }
    }

    /// Recommended temperature for this domain.
    pub fn recommended_temperature(&self) -> f32 {
        match self {
            Self::Mathematics | Self::SlotMath => 0.0,     // Deterministic
            Self::Architecture | Self::AudioDsp => 0.2,    // Low creativity
            Self::DailyCoding | Self::CodeReview => 0.1,   // Precise
            Self::Documentation => 0.3,                     // Slight variation
            Self::Creative => 0.7,                          // Creative freedom
            Self::Research => 0.4,                          // Balanced
            Self::General => 0.3,                           // Default
        }
    }

    /// Recommended max tokens for this domain.
    pub fn recommended_max_tokens(&self) -> u32 {
        match self {
            Self::Architecture | Self::CodeReview => 8192,
            Self::Mathematics | Self::SlotMath => 4096,
            Self::DailyCoding => 4096,
            Self::Creative => 2048,
            Self::Research => 4096,
            Self::Documentation => 4096,
            Self::AudioDsp => 8192,
            Self::General => 4096,
        }
    }

    /// Display name (Serbian).
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Architecture => "Arhitektura",
            Self::DailyCoding => "Dnevni kod",
            Self::Mathematics => "Matematika",
            Self::Creative => "Kreativno",
            Self::Research => "Istraživanje",
            Self::CodeReview => "Code Review",
            Self::Documentation => "Dokumentacija",
            Self::SlotMath => "Slot Matematika",
            Self::AudioDsp => "Audio/DSP",
            Self::General => "Generalno",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLASSIFICATION RESULT
// ═══════════════════════════════════════════════════════════════════════════════

/// Result of classifying a task.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClassificationResult {
    /// Primary domain classification.
    pub domain: TaskDomain,
    /// Confidence of the classification (0.0 - 1.0).
    pub confidence: f64,
    /// Which signals triggered this classification.
    pub signals: Vec<String>,
    /// Secondary domain (if the task spans multiple domains).
    pub secondary_domain: Option<TaskDomain>,
    /// Recommended model based on domain.
    pub recommended_model: ModelId,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TASK CLASSIFIER
// ═══════════════════════════════════════════════════════════════════════════════

/// Classifies tasks by analyzing query content, keywords, and patterns.
pub struct TaskClassifier {
    /// Domain-specific keyword rules, ordered by priority.
    rules: Vec<ClassificationRule>,
}

struct ClassificationRule {
    domain: TaskDomain,
    /// Keywords that suggest this domain (case-insensitive).
    keywords: Vec<&'static str>,
    /// Regex-like patterns (simple substring matches).
    patterns: Vec<&'static str>,
    /// Base weight for this rule (higher = stronger signal).
    weight: f64,
}

impl TaskClassifier {
    pub fn new() -> Self {
        Self {
            rules: Self::build_rules(),
        }
    }

    /// Classify a query into a TaskDomain.
    pub fn classify(&self, query: &str) -> ClassificationResult {
        let lower = query.to_lowercase();
        let mut scores: Vec<(TaskDomain, f64, Vec<String>)> = Vec::new();

        for rule in &self.rules {
            let (score, signals) = self.evaluate_rule(rule, &lower);
            if score > 0.0 {
                scores.push((rule.domain, score, signals));
            }
        }

        // Sort by score descending
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        if scores.is_empty() {
            return ClassificationResult {
                domain: TaskDomain::General,
                confidence: 0.3,
                signals: vec!["Nema specifičnih signala".into()],
                secondary_domain: None,
                recommended_model: TaskDomain::General.primary_model(),
            };
        }

        let (domain, score, signals) = scores[0].clone();
        let secondary = scores.get(1).map(|(d, _, _)| *d);

        // Normalize confidence
        let total_score: f64 = scores.iter().map(|(_, s, _)| s).sum();
        let confidence = if total_score > 0.0 {
            (score / total_score).min(1.0)
        } else {
            0.3
        };

        ClassificationResult {
            domain,
            confidence,
            signals,
            secondary_domain: secondary,
            recommended_model: domain.primary_model(),
        }
    }

    fn evaluate_rule(&self, rule: &ClassificationRule, lower: &str) -> (f64, Vec<String>) {
        let mut score = 0.0;
        let mut signals = Vec::new();

        for keyword in &rule.keywords {
            if lower.contains(keyword) {
                score += rule.weight;
                signals.push(format!("keyword: '{}'", keyword));
            }
        }

        for pattern in &rule.patterns {
            if lower.contains(pattern) {
                score += rule.weight * 1.5; // Patterns weighted higher
                signals.push(format!("pattern: '{}'", pattern));
            }
        }

        (score, signals)
    }

    fn build_rules() -> Vec<ClassificationRule> {
        vec![
            // ─── SLOT MATH (highest priority — very specific domain) ─────
            ClassificationRule {
                domain: TaskDomain::SlotMath,
                keywords: vec![
                    "rtp", "return to player", "hit frequency", "hit freq",
                    "volatility index", "paytable", "pay table", "reel strip",
                    "scatter", "wild symbol", "free spin", "bonus round",
                    "jackpot", "progressive", "megaways", "payline",
                    "win distribution", "symbol frequency", "reel weight",
                    "near miss", "dead spin", "base game", "feature trigger",
                ],
                patterns: vec![
                    "slot math", "slot game", "slot machine", "casino math",
                    "rtp calculat", "variance model", "hit rate",
                    "win tier", "max win", "bet multiplier",
                    "symbol distribution", "reel configuration",
                ],
                weight: 3.0,
            },
            // ─── MATHEMATICS / ALGORITHMS ────────────────────────────────
            ClassificationRule {
                domain: TaskDomain::Mathematics,
                keywords: vec![
                    "algorithm", "algoritam", "mathematical", "matematick",
                    "probability", "verovatnoća", "distribution", "distribucija",
                    "variance", "varijansa", "standard deviation",
                    "dynamic programming", "graph theory", "number theory",
                    "complexity", "big-o", "polynomial", "exponential",
                    "fibonacci", "prime", "factorial", "combinatorics",
                    "matrix", "eigenvalue", "gradient", "optimization",
                    "monte carlo", "markov", "bayesian", "regression",
                    "neural network", "backpropagation",
                ],
                patterns: vec![
                    "o(n", "o(log", "np-hard", "np-complete",
                    "prove that", "dokaži da", "calculate the", "izračunaj",
                    "expected value", "confidence interval",
                    "time complexity", "space complexity",
                    "recurrence relation", "closed form",
                ],
                weight: 2.5,
            },
            // ─── AUDIO / DSP ─────────────────────────────────────────────
            ClassificationRule {
                domain: TaskDomain::AudioDsp,
                keywords: vec![
                    "audio thread", "sample rate", "buffer size",
                    "fft", "spectral", "frequency response",
                    "biquad", "filter", "convolution", "impulse response",
                    "simd", "avx", "sse", "neon",
                    "ring buffer", "lock-free", "real-time",
                    "latency", "jitter", "underrun",
                    "waveform", "oscillator", "envelope",
                    "reverb", "delay", "compressor", "limiter",
                    "mixer", "bus", "routing", "gain staging",
                ],
                patterns: vec![
                    "audio engine", "dsp pipeline", "audio graph",
                    "sample process", "zero crossing", "rms level",
                    "lufs", "true peak", "crest factor",
                    "cpal", "dasp", "symphonia",
                    "f32 buffer", "interleaved", "planar",
                ],
                weight: 2.0,
            },
            // ─── ARCHITECTURE ────────────────────────────────────────────
            ClassificationRule {
                domain: TaskDomain::Architecture,
                keywords: vec![
                    "architecture", "arhitektura", "refactor", "refaktorisanje",
                    "redesign", "redizajn", "restructure",
                    "ffi", "lifecycle", "životni ciklus",
                    "trait design", "type system", "generics",
                    "dependency injection", "inversion of control",
                    "event sourcing", "cqrs", "microservice",
                    "module boundary", "api design",
                ],
                patterns: vec![
                    "multi-file", "across crate", "cross-crate",
                    "how should we structure", "kako da organizujemo",
                    "system design", "dizajn sistema",
                    "component architecture", "layer",
                    "abstraction", "apstrakcija",
                    "trait hierarchy", "type-level",
                ],
                weight: 2.0,
            },
            // ─── CODE REVIEW ─────────────────────────────────────────────
            ClassificationRule {
                domain: TaskDomain::CodeReview,
                keywords: vec![
                    "review", "audit", "security", "vulnerability",
                    "code smell", "anti-pattern", "tech debt",
                    "unsafe", "race condition", "deadlock",
                    "memory leak", "use after free",
                ],
                patterns: vec![
                    "code review", "pregled koda", "security audit",
                    "find bugs", "nađi bagove", "potential issue",
                    "what's wrong", "šta ne valja",
                ],
                weight: 1.8,
            },
            // ─── CREATIVE ────────────────────────────────────────────────
            ClassificationRule {
                domain: TaskDomain::Creative,
                keywords: vec![
                    "name for", "ime za", "branding", "marketing",
                    "slogan", "tagline", "copy", "ux writing",
                    "tone of voice", "messaging", "pitch",
                    "logo", "visual identity", "color palette",
                    "user experience", "onboarding",
                ],
                patterns: vec![
                    "kako da nazovem", "how should i name",
                    "creative direction", "kreativni pravac",
                    "write me a", "napiši mi",
                    "come up with", "smisli",
                    "suggest names", "predloži imena",
                    "ui design", "ux design",
                ],
                weight: 1.5,
            },
            // ─── RESEARCH ────────────────────────────────────────────────
            ClassificationRule {
                domain: TaskDomain::Research,
                keywords: vec![
                    "best practice", "industry standard", "industrijski standard",
                    "comparison", "poređenje", "benchmark",
                    "how do they", "kako oni", "state of the art",
                    "alternative", "alternativa", "competitor",
                ],
                patterns: vec![
                    "how does ableton", "how does logic",
                    "kako rade", "what do others",
                    "industry approach", "best way to",
                    "research on", "istraži",
                ],
                weight: 1.3,
            },
            // ─── DOCUMENTATION ───────────────────────────────────────────
            ClassificationRule {
                domain: TaskDomain::Documentation,
                keywords: vec![
                    "document", "dokumentuj", "changelog",
                    "readme", "api doc", "migration guide",
                    "tutorial", "example", "primer",
                ],
                patterns: vec![
                    "write docs", "napiši dokumentaciju",
                    "add documentation", "dodaj dokumentaciju",
                    "update readme", "api reference",
                ],
                weight: 1.2,
            },
            // ─── DAILY CODING (lowest priority — catches remaining code tasks) ─
            ClassificationRule {
                domain: TaskDomain::DailyCoding,
                keywords: vec![
                    "fix", "fixuj", "popravi", "bug", "error", "greška",
                    "test", "testovi", "implement", "implementiraj",
                    "add feature", "dodaj", "update", "ažuriraj",
                    "compile", "build", "lint", "format",
                    "function", "method", "struct", "enum",
                ],
                patterns: vec![
                    "napiši kod", "write code", "fix this",
                    "add a", "dodaj", "make it",
                    "doesn't work", "ne radi", "broken",
                    "cargo test", "npm test", "flutter test",
                ],
                weight: 1.0,
            },
        ]
    }
}

impl Default for TaskClassifier {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn classifier() -> TaskClassifier {
        TaskClassifier::new()
    }

    #[test]
    fn classifies_slot_math() {
        let result = classifier().classify(
            "Izračunaj RTP za paytable sa 5 reels, 20 paylines, scatter trigger na 3+ simbola",
        );
        assert_eq!(result.domain, TaskDomain::SlotMath);
        assert!(result.confidence > 0.3);
    }

    #[test]
    fn classifies_architecture() {
        let result = classifier().classify(
            "Kako da redizajniramo FFI boundary između rf-bridge i Flutter-a? \
             Treba nova trait hierarchy za cross-crate komunikaciju.",
        );
        assert_eq!(result.domain, TaskDomain::Architecture);
    }

    #[test]
    fn classifies_daily_coding() {
        let result = classifier().classify(
            "Fixuj bug gde se audio callback ne poziva nakon resume. Error u engine.rs linija 42.",
        );
        // Could be DailyCoding or AudioDsp — both are valid
        assert!(
            result.domain == TaskDomain::DailyCoding || result.domain == TaskDomain::AudioDsp,
            "Got {:?}",
            result.domain
        );
    }

    #[test]
    fn classifies_pure_math() {
        let result = classifier().classify(
            "Prove that the time complexity of this algorithm is O(n log n). \
             Use dynamic programming to optimize the solution.",
        );
        assert_eq!(result.domain, TaskDomain::Mathematics);
    }

    #[test]
    fn classifies_creative() {
        let result = classifier().classify(
            "Smisli 10 imena za novi audio plugin. Treba da zvuči moderno i profesionalno.",
        );
        assert_eq!(result.domain, TaskDomain::Creative);
    }

    #[test]
    fn classifies_research() {
        let result = classifier().classify(
            "Kako rade Ableton i Logic Pro audio routing? Koji je industrijski standard?",
        );
        assert_eq!(result.domain, TaskDomain::Research);
    }

    #[test]
    fn classifies_audio_dsp() {
        let result = classifier().classify(
            "Implementiraj biquad filter sa TDF-II strukturom, SIMD dispatch za AVX2 i SSE4.",
        );
        assert_eq!(result.domain, TaskDomain::AudioDsp);
    }

    #[test]
    fn classifies_code_review() {
        let result = classifier().classify(
            "Security audit za unsafe blok u FFI modulu. Proveri race condition i memory leak.",
        );
        assert_eq!(result.domain, TaskDomain::CodeReview);
    }

    #[test]
    fn classifies_documentation() {
        let result = classifier().classify(
            "Napiši dokumentaciju za BrainRouter API. Dodaj changelog za v0.2.",
        );
        assert_eq!(result.domain, TaskDomain::Documentation);
    }

    #[test]
    fn unknown_query_is_general() {
        let result = classifier().classify("asdfghjkl");
        assert_eq!(result.domain, TaskDomain::General);
    }

    #[test]
    fn primary_model_mapping() {
        assert_eq!(TaskDomain::Architecture.primary_model(), ModelId::ClaudeOpus);
        assert_eq!(TaskDomain::DailyCoding.primary_model(), ModelId::ClaudeSonnet);
        assert_eq!(TaskDomain::Mathematics.primary_model(), ModelId::DeepSeekR1);
        assert_eq!(TaskDomain::Creative.primary_model(), ModelId::Gpt4o);
        assert_eq!(TaskDomain::SlotMath.primary_model(), ModelId::DeepSeekR1);
        assert_eq!(TaskDomain::AudioDsp.primary_model(), ModelId::ClaudeOpus);
    }

    #[test]
    fn fallback_chains_not_empty() {
        for domain in [
            TaskDomain::Architecture,
            TaskDomain::DailyCoding,
            TaskDomain::Mathematics,
            TaskDomain::Creative,
            TaskDomain::SlotMath,
            TaskDomain::AudioDsp,
            TaskDomain::General,
        ] {
            let chain = domain.fallback_chain();
            assert!(!chain.is_empty(), "Fallback chain empty for {:?}", domain);
            // Fallback should not contain the primary model
            assert!(
                !chain.contains(&domain.primary_model()),
                "Fallback chain for {:?} contains primary model",
                domain
            );
        }
    }

    #[test]
    fn math_temperature_is_zero() {
        assert!(TaskDomain::Mathematics.recommended_temperature().abs() < f32::EPSILON);
        assert!(TaskDomain::SlotMath.recommended_temperature().abs() < f32::EPSILON);
    }

    #[test]
    fn creative_temperature_is_high() {
        assert!(TaskDomain::Creative.recommended_temperature() > 0.5);
    }

    #[test]
    fn classification_has_signals() {
        let result = classifier().classify("Izračunaj RTP za slot sa scatter triggerom");
        assert!(!result.signals.is_empty());
    }

    #[test]
    fn secondary_domain_detected() {
        // This query touches both architecture and audio
        let result = classifier().classify(
            "Redizajniraj audio graph arhitekturu sa SIMD pipeline i FFI boundary",
        );
        assert!(result.secondary_domain.is_some());
    }

    #[test]
    fn slot_math_beats_general_math() {
        let result = classifier().classify(
            "Izračunaj variance model za slot machine sa 5 reels i progressive jackpot. \
             RTP mora biti 96.5% sa hit frequency 1/3.",
        );
        // SlotMath should win over Mathematics because it has more specific keywords
        assert_eq!(result.domain, TaskDomain::SlotMath);
    }
}

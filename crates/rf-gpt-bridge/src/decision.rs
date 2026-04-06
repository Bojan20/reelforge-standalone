// file: crates/rf-gpt-bridge/src/decision.rs
//! Decision Engine — determines WHEN and WHY to consult GPT.
//!
//! This is the intelligence layer. Not every signal warrants a GPT call.
//! The decision engine evaluates:
//! - Pattern complexity (can Corti handle this alone?)
//! - Novelty (has Corti seen this before?)
//! - User urgency (did Boki explicitly ask?)
//! - Rate limiting (don't spam the API)
//! - Cost awareness (respect token budget)

use crate::config::GptBridgeConfig;
use crate::protocol::GptIntent;
use crate::roles::GptPersona;
use rf_cortex::signal::{NeuralSignal, SignalKind};
use std::time::Instant;

/// A decision to consult GPT.
#[derive(Debug, Clone)]
pub struct GptDecision {
    /// Should we send this to GPT?
    pub should_query: bool,
    /// Why (or why not).
    pub reason: String,
    /// What intent should the query have?
    pub intent: GptIntent,
    /// How urgent is this query?
    pub urgency: f32,
    /// Context to include in the query.
    pub context: String,
    /// The actual query to send.
    pub query: String,
    /// Which persona should handle this (None = let RoleSelector decide).
    pub persona: Option<GptPersona>,
    /// Should this use a pipeline (consensus/chain) instead of single?
    pub use_pipeline: bool,
}

/// The decision engine — evaluates signals and patterns to decide when GPT is needed.
pub struct DecisionEngine {
    /// Last time we queried GPT.
    last_query_time: Option<Instant>,
    /// Minimum interval between autonomous queries.
    min_interval: std::time::Duration,
    /// Is autonomous mode enabled?
    autonomous_enabled: bool,
    /// Confidence threshold for autonomous queries.
    confidence_threshold: f32,
    /// Number of consecutive unknown patterns (escalation counter).
    unknown_pattern_streak: u32,
    /// Total autonomous queries sent this session.
    autonomous_queries_sent: u64,
    /// Total user queries sent this session.
    user_queries_sent: u64,
}

impl DecisionEngine {
    pub fn new(config: &GptBridgeConfig) -> Self {
        Self {
            last_query_time: None,
            min_interval: std::time::Duration::from_secs(config.min_query_interval_secs),
            autonomous_enabled: config.autonomous_enabled,
            confidence_threshold: config.confidence_threshold,
            unknown_pattern_streak: 0,
            autonomous_queries_sent: 0,
            user_queries_sent: 0,
        }
    }

    /// Evaluate whether a signal or pattern warrants a GPT consultation.
    pub fn evaluate_signal(&mut self, signal: &NeuralSignal) -> GptDecision {
        // User explicitly asked — always honor
        if let SignalKind::GptUserRequest { ref query } = signal.kind {
            return self.decide_user_request(query.clone());
        }

        // If autonomous mode is disabled, skip
        if !self.autonomous_enabled {
            return self.skip("Autonomni mod isključen");
        }

        // Rate limit check
        if let Some(last) = self.last_query_time {
            if last.elapsed() < self.min_interval {
                return self.skip("Prebrzo — čekam minimum interval");
            }
        }

        // Now evaluate the signal itself
        match &signal.kind {
            // Complex patterns Corti can't resolve alone
            SignalKind::PluginFault { reason, .. } if reason.contains("unknown") => {
                self.decide_autonomous(
                    GptIntent::Debugging,
                    format!("Plugin fault sa nepoznatim razlogom: {}", reason),
                    "Corti ne može da dijagnostikuje nepoznat plugin fault",
                    0.8,
                )
            }

            // Repeated crisis — escalate to GPT
            SignalKind::BufferUnderrun { count } if *count > 10 => {
                self.decide_autonomous(
                    GptIntent::Analysis,
                    format!("Kritičan broj buffer underrun-ova: {} consecutive", count),
                    "Persists uprkos reflex akcijama — treba dublja analiza",
                    0.9,
                )
            }

            // Memory pressure with no obvious cause
            SignalKind::MemoryPressure { used_mb, available_mb }
                if *available_mb < 512 =>
            {
                self.decide_autonomous(
                    GptIntent::Analysis,
                    format!("Kritičan memory: {}MB used, {}MB available", used_mb, available_mb),
                    "Corti pokušao FreeCaches ali pritisak ostaje",
                    0.7,
                )
            }

            // Code health degradation
            SignalKind::CodeHealthChanged { old_score, new_score }
                if new_score < old_score && *new_score < 0.5 =>
            {
                self.decide_autonomous(
                    GptIntent::CodeReview,
                    format!(
                        "Code health pao: {:.2} → {:.2}",
                        old_score, new_score
                    ),
                    "Značajan pad code health-a zahteva review",
                    0.6,
                )
            }

            // Evolution reverted — GPT might have insight
            SignalKind::EvolutionReverted { description, reason } => {
                self.decide_autonomous(
                    GptIntent::Architecture,
                    format!("Evolucija revertovana: {} — razlog: {}", description, reason),
                    "Automatska mutacija failovala, treba drugi pristup",
                    0.5,
                )
            }

            // Custom signal with explicit GPT tag
            SignalKind::Custom { tag, data } if tag.starts_with("gpt:") => {
                let subtag = &tag[4..];
                self.decide_autonomous(
                    GptIntent::Insight,
                    format!("[{}] {}", subtag, data),
                    "Eksplicitni GPT custom signal",
                    0.6,
                )
            }

            _ => self.skip("Signal ne zahteva GPT konsultaciju"),
        }
    }

    /// Evaluate a recognized pattern — patterns are higher-level than signals.
    pub fn evaluate_pattern(&mut self, name: &str, severity: f32, description: &str) -> GptDecision {
        if !self.autonomous_enabled {
            return self.skip("Autonomni mod isključen");
        }

        // High severity patterns that Corti can't handle alone
        if severity > 0.8 {
            self.unknown_pattern_streak += 1;

            return self.decide_autonomous(
                GptIntent::Analysis,
                format!(
                    "Kritičan pattern '{}' (severity: {:.2}): {}",
                    name, severity, description
                ),
                &format!(
                    "Streak nepoznatih patterna: {} — eskalacija",
                    self.unknown_pattern_streak
                ),
                severity,
            );
        }

        // Reset streak on normal patterns
        self.unknown_pattern_streak = 0;
        self.skip("Pattern u normalnom opsegu")
    }

    /// Record that a query was sent (updates rate limiting timer).
    pub fn record_query_sent(&mut self, _tokens: u32) {
        self.last_query_time = Some(Instant::now());
    }

    /// Stats for the decision engine.
    pub fn stats(&self) -> DecisionStats {
        DecisionStats {
            autonomous_queries_sent: self.autonomous_queries_sent,
            user_queries_sent: self.user_queries_sent,
            unknown_pattern_streak: self.unknown_pattern_streak,
        }
    }

    /// Update config at runtime.
    pub fn update_config(&mut self, config: &GptBridgeConfig) {
        self.min_interval = std::time::Duration::from_secs(config.min_query_interval_secs);
        self.autonomous_enabled = config.autonomous_enabled;
        self.confidence_threshold = config.confidence_threshold;
    }

    // --- Internal helpers ---

    fn decide_user_request(&mut self, query: String) -> GptDecision {
        self.user_queries_sent += 1;
        GptDecision {
            should_query: true,
            reason: "Korisnik eksplicitno tražio GPT konsultaciju".into(),
            intent: GptIntent::UserQuery,
            urgency: 0.9,
            context: String::new(), // Will be filled by bridge
            query,
            persona: None, // Let RoleSelector decide based on content
            use_pipeline: false,
        }
    }

    fn decide_autonomous(
        &mut self,
        intent: GptIntent,
        query: String,
        context: &str,
        urgency: f32,
    ) -> GptDecision {
        self.autonomous_queries_sent += 1;

        // High urgency architecture/debugging decisions → use pipeline for consensus
        let use_pipeline = urgency > 0.8
            && matches!(intent, GptIntent::Architecture | GptIntent::Debugging);

        // Select persona based on intent
        let persona = match intent {
            GptIntent::Debugging => Some(GptPersona::TestOracle),
            GptIntent::CodeReview => Some(GptPersona::DevilsAdvocate),
            GptIntent::Architecture => Some(GptPersona::DomainResearcher),
            GptIntent::Analysis => Some(GptPersona::PatternSpotter),
            GptIntent::Creative => Some(GptPersona::CreativeDirector),
            _ => None,
        };

        GptDecision {
            should_query: true,
            reason: context.to_string(),
            intent,
            urgency,
            context: context.to_string(),
            query,
            persona,
            use_pipeline,
        }
    }

    fn skip(&self, reason: &str) -> GptDecision {
        GptDecision {
            should_query: false,
            reason: reason.into(),
            intent: GptIntent::Insight,
            urgency: 0.0,
            context: String::new(),
            query: String::new(),
            persona: None,
            use_pipeline: false,
        }
    }
}

/// Decision engine statistics.
#[derive(Debug, Clone)]
pub struct DecisionStats {
    pub autonomous_queries_sent: u64,
    pub user_queries_sent: u64,
    pub unknown_pattern_streak: u32,
}

#[cfg(test)]
mod tests {
    use super::*;
    use rf_cortex::signal::{NeuralSignal, SignalKind, SignalOrigin, SignalUrgency};

    fn default_engine() -> DecisionEngine {
        DecisionEngine::new(&GptBridgeConfig::default())
    }

    #[test]
    fn user_request_always_honored() {
        let mut engine = default_engine();
        let signal = NeuralSignal::new(
            SignalOrigin::User,
            SignalUrgency::Normal,
            SignalKind::GptUserRequest {
                query: "Šta misliš o ovom kodu?".into(),
            },
        );

        let decision = engine.evaluate_signal(&signal);
        assert!(decision.should_query);
        assert_eq!(decision.intent, GptIntent::UserQuery);
    }

    #[test]
    fn normal_heartbeat_skipped() {
        let mut engine = default_engine();
        let signal = NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        );

        let decision = engine.evaluate_signal(&signal);
        assert!(!decision.should_query);
    }

    #[test]
    fn critical_underrun_triggers_query() {
        let mut engine = default_engine();
        let signal = NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 15 },
        );

        let decision = engine.evaluate_signal(&signal);
        assert!(decision.should_query);
        assert_eq!(decision.intent, GptIntent::Analysis);
    }

    #[test]
    fn rate_limiting_works() {
        let mut config = GptBridgeConfig::default();
        config.min_query_interval_secs = 60; // 60s minimum
        let mut engine = DecisionEngine::new(&config);

        // Simulate recent query
        engine.last_query_time = Some(Instant::now());

        let signal = NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 15 },
        );

        let decision = engine.evaluate_signal(&signal);
        assert!(!decision.should_query);
        assert!(decision.reason.contains("interval"));
    }

    #[test]
    fn high_severity_pattern_triggers() {
        let mut engine = default_engine();
        let decision = engine.evaluate_pattern("audio_crisis", 0.9, "Multiple subsystem failures");
        assert!(decision.should_query);
    }
}

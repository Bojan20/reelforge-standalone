// file: crates/rf-cortex/src/reflex.rs
//! Reflexes — automatic responses to known signal patterns.
//!
//! Like biological reflexes, these bypass conscious processing for speed.
//! A reflex fires instantly when its trigger condition is met, without
//! waiting for the cortex's full analysis cycle.

use crate::signal::{NeuralSignal, SignalKind, SignalOrigin, SignalUrgency};
use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant};

/// What action a reflex takes when triggered.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ReflexAction {
    /// Emit a new signal into the bus (chain reaction).
    EmitSignal {
        origin: SignalOrigin,
        urgency: SignalUrgency,
        kind: SignalKind,
    },
    /// Log a warning message.
    LogWarning { message: String },
    /// Increment an antibody counter (immune system integration).
    RecordAnomaly { category: String, severity: f32 },
    /// Request a specific subsystem to take action.
    CommandSubsystem { target: SignalOrigin, command: String },
    /// Suppress further signals of this type for a cooldown period.
    Suppress { duration_ms: u64 },
}

/// A reflex rule — condition + action + cooldown.
pub struct Reflex {
    /// Human-readable name.
    pub name: String,
    /// The condition that triggers this reflex.
    pub trigger: Box<dyn Fn(&NeuralSignal) -> bool + Send>,
    /// What to do when triggered.
    pub action: ReflexAction,
    /// Minimum time between firings (prevents reflex storms).
    pub cooldown: Duration,
    /// Last time this reflex fired.
    last_fired: Option<Instant>,
    /// How many times this reflex has fired total.
    pub fire_count: u64,
    /// Is this reflex enabled?
    pub enabled: bool,
}

impl Reflex {
    /// Create a new reflex.
    pub fn new(
        name: impl Into<String>,
        trigger: impl Fn(&NeuralSignal) -> bool + Send + 'static,
        action: ReflexAction,
        cooldown: Duration,
    ) -> Self {
        Self {
            name: name.into(),
            trigger: Box::new(trigger),
            action,
            cooldown,
            last_fired: None,
            fire_count: 0,
            enabled: true,
        }
    }

    /// Check if this reflex should fire for the given signal.
    pub fn should_fire(&self, signal: &NeuralSignal) -> bool {
        if !self.enabled {
            return false;
        }
        if let Some(last) = self.last_fired {
            if last.elapsed() < self.cooldown {
                return false;
            }
        }
        (self.trigger)(signal)
    }

    /// Mark this reflex as having fired.
    pub fn mark_fired(&mut self) {
        self.last_fired = Some(Instant::now());
        self.fire_count += 1;
    }
}

/// The reflex arc — a collection of reflexes that process signals before conscious processing.
pub struct ReflexArc {
    reflexes: Vec<Reflex>,
}

impl ReflexArc {
    pub fn new() -> Self {
        Self {
            reflexes: Vec::new(),
        }
    }

    /// Register a new reflex.
    pub fn register(&mut self, reflex: Reflex) {
        self.reflexes.push(reflex);
    }

    /// Process a signal through all reflexes. Returns actions to execute.
    pub fn process(&mut self, signal: &NeuralSignal) -> Vec<ReflexAction> {
        let mut actions = Vec::new();
        for reflex in &mut self.reflexes {
            if reflex.should_fire(signal) {
                actions.push(reflex.action.clone());
                reflex.mark_fired();
                log::debug!("Reflex '{}' fired (#{} total)", reflex.name, reflex.fire_count);
            }
        }
        actions
    }

    /// How many reflexes are registered.
    pub fn count(&self) -> usize {
        self.reflexes.len()
    }

    /// Get stats for all reflexes.
    pub fn stats(&self) -> Vec<ReflexStats> {
        self.reflexes
            .iter()
            .map(|r| ReflexStats {
                name: r.name.clone(),
                fire_count: r.fire_count,
                enabled: r.enabled,
            })
            .collect()
    }

    /// Create the default set of built-in reflexes for FluxForge.
    pub fn with_defaults() -> Self {
        let mut arc = Self::new();

        // Reflex: Buffer underrun → log warning + record anomaly
        arc.register(Reflex::new(
            "buffer-underrun-alert",
            |sig| matches!(sig.kind, SignalKind::BufferUnderrun { count } if count >= 3),
            ReflexAction::RecordAnomaly {
                category: "audio.underrun".into(),
                severity: 0.8,
            },
            Duration::from_secs(5),
        ));

        // Reflex: CPU overload → command engine to reduce quality
        arc.register(Reflex::new(
            "cpu-overload-reduce",
            |sig| matches!(sig.kind, SignalKind::CpuLoadAlert { load_percent } if load_percent > 90.0),
            ReflexAction::CommandSubsystem {
                target: SignalOrigin::AudioEngine,
                command: "reduce_quality".into(),
            },
            Duration::from_secs(10),
        ));

        // Reflex: Clipping detected → record anomaly
        arc.register(Reflex::new(
            "clip-detector",
            |sig| matches!(sig.kind, SignalKind::ClipDetected { peak_db, .. } if peak_db > 0.0),
            ReflexAction::RecordAnomaly {
                category: "audio.clipping".into(),
                severity: 0.6,
            },
            Duration::from_millis(500),
        ));

        // Reflex: Plugin crash → isolate and log
        arc.register(Reflex::new(
            "plugin-fault-isolate",
            |sig| matches!(sig.kind, SignalKind::PluginFault { .. }),
            ReflexAction::LogWarning {
                message: "Plugin fault detected — isolating".into(),
            },
            Duration::from_secs(1),
        ));

        // Reflex: Memory pressure → command engine to free caches
        arc.register(Reflex::new(
            "memory-pressure-response",
            |sig| {
                matches!(sig.kind, SignalKind::MemoryPressure { available_mb, .. } if available_mb < 512)
            },
            ReflexAction::CommandSubsystem {
                target: SignalOrigin::AudioEngine,
                command: "free_caches".into(),
            },
            Duration::from_secs(30),
        ));

        // Reflex: Feedback loop → emergency stop
        arc.register(Reflex::new(
            "feedback-loop-emergency",
            |sig| matches!(sig.kind, SignalKind::FeedbackDetected { .. }),
            ReflexAction::CommandSubsystem {
                target: SignalOrigin::MixerBus,
                command: "break_feedback".into(),
            },
            Duration::from_millis(100),
        ));

        // Reflex: Visual anomaly → record as anomaly for immune system
        arc.register(Reflex::new(
            "vision-anomaly-alert",
            |sig| matches!(sig.kind, SignalKind::VisualAnomaly { .. }),
            ReflexAction::RecordAnomaly {
                category: "vision.anomaly".into(),
                severity: 0.5,
            },
            Duration::from_secs(5),
        ));

        // Reflex: Vision frozen region → command UI subsystem to investigate
        arc.register(Reflex::new(
            "vision-frozen-diagnostic",
            |sig| {
                matches!(
                    &sig.kind,
                    SignalKind::Custom { tag, data }
                    if tag == "vision_telemetry" && data.contains("frozen=") && !data.ends_with("frozen=0")
                )
            },
            ReflexAction::RecordAnomaly {
                category: "vision.frozen_region".into(),
                severity: 0.6,
            },
            Duration::from_secs(30),
        ));

        arc
    }
}

impl Default for ReflexArc {
    fn default() -> Self {
        Self::new()
    }
}

/// Stats for a single reflex.
#[derive(Debug, Clone)]
pub struct ReflexStats {
    pub name: String,
    pub fire_count: u64,
    pub enabled: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reflex_fires_on_match() {
        let mut arc = ReflexArc::new();
        arc.register(Reflex::new(
            "test-reflex",
            |sig| matches!(sig.kind, SignalKind::Heartbeat),
            ReflexAction::LogWarning {
                message: "heartbeat!".into(),
            },
            Duration::from_millis(0),
        ));

        let sig = NeuralSignal::new(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);
        let actions = arc.process(&sig);
        assert_eq!(actions.len(), 1);
    }

    #[test]
    fn reflex_does_not_fire_on_mismatch() {
        let mut arc = ReflexArc::new();
        arc.register(Reflex::new(
            "heartbeat-only",
            |sig| matches!(sig.kind, SignalKind::Heartbeat),
            ReflexAction::LogWarning {
                message: "heartbeat!".into(),
            },
            Duration::from_millis(0),
        ));

        let sig = NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 1 },
        );
        let actions = arc.process(&sig);
        assert!(actions.is_empty());
    }

    #[test]
    fn cooldown_prevents_rapid_firing() {
        let mut arc = ReflexArc::new();
        arc.register(Reflex::new(
            "cooldown-test",
            |sig| matches!(sig.kind, SignalKind::Heartbeat),
            ReflexAction::LogWarning {
                message: "test".into(),
            },
            Duration::from_secs(60), // long cooldown
        ));

        let sig = NeuralSignal::new(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);

        let actions1 = arc.process(&sig);
        assert_eq!(actions1.len(), 1);

        // Should NOT fire again due to cooldown
        let actions2 = arc.process(&sig);
        assert!(actions2.is_empty());
    }

    #[test]
    fn disabled_reflex_does_not_fire() {
        let mut arc = ReflexArc::new();
        let mut reflex = Reflex::new(
            "disabled",
            |sig| matches!(sig.kind, SignalKind::Heartbeat),
            ReflexAction::LogWarning {
                message: "test".into(),
            },
            Duration::from_millis(0),
        );
        reflex.enabled = false;
        arc.register(reflex);

        let sig = NeuralSignal::new(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);
        let actions = arc.process(&sig);
        assert!(actions.is_empty());
    }

    #[test]
    fn default_reflexes_exist() {
        let arc = ReflexArc::with_defaults();
        assert!(arc.count() >= 8);
    }

    #[test]
    fn default_underrun_reflex_fires() {
        let mut arc = ReflexArc::with_defaults();
        let sig = NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 5 },
        );
        let actions = arc.process(&sig);
        assert!(!actions.is_empty());
    }

    #[test]
    fn stats_tracking() {
        let mut arc = ReflexArc::new();
        arc.register(Reflex::new(
            "stat-test",
            |sig| matches!(sig.kind, SignalKind::Heartbeat),
            ReflexAction::LogWarning {
                message: "test".into(),
            },
            Duration::from_millis(0),
        ));

        let sig = NeuralSignal::new(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);
        arc.process(&sig);
        arc.process(&sig);
        arc.process(&sig);

        let stats = arc.stats();
        assert_eq!(stats[0].fire_count, 3);
    }
}

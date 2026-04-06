// file: crates/rf-cortex/src/cortex.rs
//! The Cortex — central nervous system processor.
//!
//! This is the brain that ties everything together:
//! - Receives signals from all subsystems via the NeuralBus
//! - Runs reflexes for instant reactions
//! - Feeds patterns for sequence detection
//! - Maintains self-awareness
//! - Executes actions based on recognized patterns

use crate::autonomic::{AutonomicCommand, CommandAction, CommandChannel, CommandPriority, CommandReceiver};
use crate::awareness::{AwarenessEngine, AwarenessSnapshot};
use crate::bus::{NeuralBus, SignalFilter, Synapse};
use crate::immune::{ImmuneSnapshot, ImmuneSystem};
use crate::pattern::{PatternEngine, RecognizedPattern};
use crate::reflex::{ReflexAction, ReflexArc};
use crate::signal::{NeuralSignal, SignalKind, SignalOrigin, SignalUrgency};
use std::time::{Duration, Instant};

/// Configuration for the Cortex processor.
pub struct CortexConfig {
    /// How often to take awareness snapshots.
    pub awareness_interval: Duration,
    /// Expected number of subsystem origins.
    pub expected_origins: usize,
    /// Use default reflexes?
    pub default_reflexes: bool,
    /// Use default pattern detectors?
    pub default_patterns: bool,
}

impl Default for CortexConfig {
    fn default() -> Self {
        Self {
            awareness_interval: Duration::from_secs(5),
            expected_origins: 8,
            default_reflexes: true,
            default_patterns: true,
        }
    }
}

/// The central nervous system of FluxForge.
pub struct Cortex {
    /// The neural bus — signal backbone.
    bus: NeuralBus,
    /// The cortex's own synapse (subscribes to all signals).
    cortex_synapse: Synapse,
    /// Reflex arc — instant reactions.
    reflex_arc: ReflexArc,
    /// Pattern engine — sequence detection.
    pattern_engine: PatternEngine,
    /// Self-awareness engine.
    awareness: AwarenessEngine,
    /// Immune system — anomaly tracking + escalation.
    immune: ImmuneSystem,
    /// Autonomic command channel — efferent nerves.
    command_channel: CommandChannel,
    /// Last awareness snapshot time.
    last_awareness: Instant,
    /// Config.
    config: CortexConfig,
    /// Log of recognized patterns (recent).
    pattern_log: Vec<RecognizedPattern>,
    /// Max pattern log size.
    max_pattern_log: usize,
    /// Total signals processed.
    pub total_processed: u64,
    /// Total reflex actions executed.
    pub total_reflex_actions: u64,
    /// Total autonomic commands dispatched.
    pub total_commands_dispatched: u64,
}

impl Cortex {
    /// Create a new Cortex with the given configuration.
    /// Returns (Cortex, CommandReceiver) — the receiver is how subsystems get commands.
    pub fn with_command_channel(config: CortexConfig) -> (Self, CommandReceiver) {
        let (command_channel, command_receiver) = CommandChannel::new();
        let cortex = Self::new_inner(config, command_channel);
        (cortex, command_receiver)
    }

    /// Create a Cortex with a pre-created command channel (sender side).
    /// Use this when the CommandReceiver needs to live outside the Cortex.
    pub fn with_provided_channel(config: CortexConfig, command_channel: CommandChannel) -> Self {
        Self::new_inner(config, command_channel)
    }

    /// Create a new Cortex (commands are dispatched but no external receiver).
    /// Useful for testing or standalone operation.
    pub fn new(config: CortexConfig) -> Self {
        let (command_channel, _receiver) = CommandChannel::new();
        Self::new_inner(config, command_channel)
    }

    fn new_inner(config: CortexConfig, command_channel: CommandChannel) -> Self {
        let mut bus = NeuralBus::new();
        let cortex_synapse = bus.subscribe("cortex-brain", SignalFilter::all());

        let reflex_arc = if config.default_reflexes {
            ReflexArc::with_defaults()
        } else {
            ReflexArc::new()
        };

        let pattern_engine = if config.default_patterns {
            PatternEngine::with_defaults()
        } else {
            PatternEngine::default()
        };

        let awareness = AwarenessEngine::new(config.expected_origins);

        Self {
            bus,
            cortex_synapse,
            reflex_arc,
            pattern_engine,
            awareness,
            immune: ImmuneSystem::new(),
            command_channel,
            last_awareness: Instant::now(),
            config,
            pattern_log: Vec::new(),
            max_pattern_log: 500,
            total_processed: 0,
            total_reflex_actions: 0,
            total_commands_dispatched: 0,
        }
    }

    /// Emit a signal into the nervous system.
    pub fn emit(&mut self, signal: NeuralSignal) {
        self.bus.emit(signal);
    }

    /// Convenience: emit a signal with origin, urgency, and kind.
    pub fn signal(&mut self, origin: SignalOrigin, urgency: SignalUrgency, kind: SignalKind) {
        self.emit(NeuralSignal::new(origin, urgency, kind));
    }

    /// Subscribe to the neural bus with a custom filter.
    pub fn subscribe(&mut self, name: impl Into<String>, filter: SignalFilter) -> Synapse {
        self.bus.subscribe(name, filter)
    }

    /// Process one tick of the cortex — drain signals, run reflexes, detect patterns.
    /// Returns any recognized patterns from this tick.
    pub fn tick(&mut self) -> Vec<RecognizedPattern> {
        let signals = self.cortex_synapse.drain();
        let mut all_patterns = Vec::new();

        for signal in signals {
            self.total_processed += 1;

            // 1. Run reflexes (instant reaction)
            let reflex_actions = self.reflex_arc.process(&signal);
            for action in &reflex_actions {
                self.execute_reflex_action(action);
            }
            self.total_reflex_actions += reflex_actions.len() as u64;

            // 2. Feed pattern engine (sequence detection)
            let patterns = self.pattern_engine.feed(signal);
            for pattern in patterns {
                log::info!(
                    "Pattern recognized: '{}' (severity: {:.2}) — {}",
                    pattern.name,
                    pattern.severity,
                    pattern.description
                );
                self.pattern_log.push(pattern.clone());
                all_patterns.push(pattern);
            }
        }

        // Trim pattern log
        while self.pattern_log.len() > self.max_pattern_log {
            self.pattern_log.remove(0);
        }

        // 3. Immune system decay tick
        self.immune.decay_tick();

        // 4. Self-awareness snapshot (periodic)
        if self.last_awareness.elapsed() >= self.config.awareness_interval {
            self.take_awareness_snapshot();
        }

        all_patterns
    }

    /// Take a self-awareness snapshot.
    fn take_awareness_snapshot(&mut self) -> AwarenessSnapshot {
        let bus_stats = self.bus.stats();
        let reflex_stats = self.reflex_arc.stats();
        let pattern_stats = self.pattern_engine.stats();
        self.last_awareness = Instant::now();
        self.awareness.snapshot(&bus_stats, &reflex_stats, &pattern_stats)
    }

    /// Execute a reflex action — NOW with real autonomic dispatch.
    fn execute_reflex_action(&mut self, action: &ReflexAction) {
        match action {
            ReflexAction::EmitSignal {
                origin,
                urgency,
                kind,
            } => {
                self.bus
                    .emit(NeuralSignal::new(*origin, *urgency, kind.clone()));
            }
            ReflexAction::LogWarning { message } => {
                log::warn!("CORTEX Reflex: {}", message);
            }
            ReflexAction::RecordAnomaly { category, severity } => {
                log::info!(
                    "CORTEX Anomaly recorded: {} (severity: {:.2})",
                    category,
                    severity
                );
                // Feed the immune system — it tracks + escalates
                if let Some(escalation_cmd) = self.immune.record_anomaly(category, *severity) {
                    log::warn!(
                        "CORTEX Immune escalation: {} → {:?}",
                        category,
                        escalation_cmd.action
                    );
                    if self.command_channel.dispatch(escalation_cmd) {
                        self.total_commands_dispatched += 1;
                    }
                }
            }
            ReflexAction::CommandSubsystem { target, command } => {
                // Translate reflex command string → typed AutonomicCommand
                let action = match command.as_str() {
                    "reduce_quality" => CommandAction::ReduceQuality { level: 0.5 },
                    "free_caches" => CommandAction::FreeCaches,
                    "break_feedback" => CommandAction::BreakFeedback { bus_chain: vec![] },
                    "isolate_plugin" => CommandAction::SuspendBackground,
                    "throttle" => CommandAction::ThrottleProcessing { factor: 0.5 },
                    other => CommandAction::Custom {
                        tag: "reflex_command".into(),
                        data: other.into(),
                    },
                };

                let cmd = AutonomicCommand::new(
                    *target,
                    action,
                    format!("Reflex command: {}", command),
                    CommandPriority::High,
                );

                log::info!("CORTEX Autonomic dispatch: {:?} → {}", target, command);
                if self.command_channel.dispatch(cmd) {
                    self.total_commands_dispatched += 1;
                }
            }
            ReflexAction::Suppress { duration_ms } => {
                log::debug!("CORTEX Suppressing for {}ms", duration_ms);
                // Signal suppression: emit a meta-signal that the bus can use
                self.bus.emit(NeuralSignal::new(
                    SignalOrigin::Cortex,
                    SignalUrgency::Normal,
                    SignalKind::Custom {
                        tag: "suppress".into(),
                        data: format!("{}ms", duration_ms),
                    },
                ));
            }
        }
    }

    /// Get the latest awareness snapshot.
    pub fn awareness(&self) -> Option<&AwarenessSnapshot> {
        self.awareness.latest()
    }

    /// Force an awareness snapshot now.
    pub fn awareness_now(&mut self) -> AwarenessSnapshot {
        self.take_awareness_snapshot()
    }

    /// Update vision telemetry state (called from tick loop with shared state data).
    pub fn report_vision(&mut self, anomaly_count: u32, frozen_count: u32) {
        self.awareness.report_vision_capture(anomaly_count, frozen_count);
    }

    /// Get reflex stats (name, fire_count, enabled) for all reflexes.
    pub fn reflex_stats(&self) -> Vec<crate::reflex::ReflexStats> {
        self.reflex_arc.stats()
    }

    /// Is the cortex in a degraded state?
    pub fn is_degraded(&self) -> bool {
        self.awareness.is_degraded()
    }

    /// Get average health over last N snapshots.
    pub fn average_health(&self, n: usize) -> f64 {
        self.awareness.average_health(n)
    }

    /// Get uptime.
    pub fn uptime(&self) -> Duration {
        self.awareness.uptime()
    }

    /// Get the recent pattern log.
    pub fn pattern_log(&self) -> &[RecognizedPattern] {
        &self.pattern_log
    }

    /// Get bus statistics.
    pub fn bus_stats(&self) -> crate::bus::BusStats {
        self.bus.stats()
    }

    /// Access the reflex arc for registration.
    pub fn reflex_arc_mut(&mut self) -> &mut ReflexArc {
        &mut self.reflex_arc
    }

    /// Access the pattern engine for registration.
    pub fn pattern_engine_mut(&mut self) -> &mut PatternEngine {
        &mut self.pattern_engine
    }

    /// Get immune system snapshot.
    pub fn immune_snapshot(&self) -> ImmuneSnapshot {
        self.immune.snapshot()
    }

    /// Is any anomaly chronic?
    pub fn has_chronic_anomaly(&self) -> bool {
        self.immune.has_chronic()
    }

    /// Resolve an anomaly category (mark as handled by subsystem).
    pub fn resolve_anomaly(&mut self, category: &str) {
        self.immune.resolve(category);
    }

    /// Total autonomic commands dispatched.
    pub fn commands_dispatched(&self) -> u64 {
        self.total_commands_dispatched
    }
}

impl Default for Cortex {
    fn default() -> Self {
        Self::new(CortexConfig::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cortex_creation() {
        let cortex = Cortex::default();
        assert_eq!(cortex.total_processed, 0);
        assert_eq!(cortex.total_reflex_actions, 0);
        assert_eq!(cortex.total_commands_dispatched, 0);
    }

    #[test]
    fn cortex_with_command_channel() {
        let (mut cortex, receiver) = Cortex::with_command_channel(CortexConfig::default());

        // Trigger CPU overload reflex → should dispatch AutonomicCommand
        cortex.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::CpuLoadAlert { load_percent: 95.0 },
        );
        cortex.tick();

        // The "cpu-overload-reduce" reflex should have fired and dispatched a command
        assert!(cortex.total_reflex_actions > 0);
        assert!(cortex.total_commands_dispatched > 0);

        // Receiver should have the command
        let commands = receiver.drain();
        assert!(!commands.is_empty(), "Expected autonomic command to be dispatched");
        assert_eq!(commands[0].target, SignalOrigin::AudioEngine);
        assert!(matches!(commands[0].action, CommandAction::ReduceQuality { .. }));
    }

    #[test]
    fn immune_escalation_through_cortex() {
        let (mut cortex, _receiver) = Cortex::with_command_channel(CortexConfig::default());

        // The buffer-underrun-alert reflex has 5s cooldown, so it fires once per tick batch.
        // But that one fire records an anomaly in the immune system.
        // To escalate, we need multiple ticks to accumulate anomalies.
        for _ in 0..4 {
            cortex.signal(
                SignalOrigin::AudioEngine,
                SignalUrgency::Critical,
                SignalKind::BufferUnderrun { count: 5 },
            );
            cortex.tick();
        }

        let snap = cortex.immune_snapshot();
        // Reflex fires (at least once), recording anomalies in the immune system
        assert!(snap.total_anomalies > 0, "Expected immune anomalies to be recorded");
    }

    #[test]
    fn feedback_loop_dispatches_break_command() {
        let (mut cortex, receiver) = Cortex::with_command_channel(CortexConfig::default());

        cortex.signal(
            SignalOrigin::MixerBus,
            SignalUrgency::Emergency,
            SignalKind::FeedbackDetected { bus_chain: vec![1, 3, 5] },
        );
        cortex.tick();

        let commands = receiver.drain();
        assert!(!commands.is_empty());
        assert_eq!(commands[0].target, SignalOrigin::MixerBus);
        assert!(matches!(commands[0].action, CommandAction::BreakFeedback { .. }));
    }

    #[test]
    fn memory_pressure_dispatches_free_caches() {
        let (mut cortex, receiver) = Cortex::with_command_channel(CortexConfig::default());

        cortex.signal(
            SignalOrigin::Cortex,
            SignalUrgency::Elevated,
            SignalKind::MemoryPressure { used_mb: 7000, available_mb: 256 },
        );
        cortex.tick();

        let commands = receiver.drain();
        assert!(!commands.is_empty());
        assert!(matches!(commands[0].action, CommandAction::FreeCaches));
    }

    #[test]
    fn emit_and_tick() {
        let mut cortex = Cortex::default();
        cortex.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        );
        cortex.signal(
            SignalOrigin::SlotLab,
            SignalUrgency::Normal,
            SignalKind::SpinComplete { result_tier: 3 },
        );

        let patterns = cortex.tick();
        assert_eq!(cortex.total_processed, 2);
        // Heartbeat doesn't trigger any default reflexes/patterns
        assert!(patterns.is_empty());
    }

    #[test]
    fn reflex_fires_on_critical_signal() {
        let mut cortex = Cortex::default();

        // Emit a critical buffer underrun (should trigger default reflex)
        cortex.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 5 },
        );

        cortex.tick();
        assert!(cortex.total_reflex_actions > 0);
    }

    #[test]
    fn pattern_detection_through_cortex() {
        let mut cortex = Cortex::default();

        // Emit enough underruns to trigger the "repeated-underruns" pattern
        for i in 0..5 {
            cortex.signal(
                SignalOrigin::AudioEngine,
                SignalUrgency::Critical,
                SignalKind::BufferUnderrun { count: i },
            );
        }

        let patterns = cortex.tick();
        // Should detect repeated underruns pattern
        assert!(
            !patterns.is_empty(),
            "Expected repeated-underruns pattern detection"
        );
        assert!(!cortex.pattern_log().is_empty());
    }

    #[test]
    fn awareness_snapshot() {
        let mut cortex = Cortex::new(CortexConfig {
            awareness_interval: Duration::from_millis(0), // immediate
            ..Default::default()
        });

        cortex.signal(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);
        cortex.tick();

        let snap = cortex.awareness_now();
        assert!(snap.health_score > 0.0);
        assert!(snap.uptime_secs >= 0.0);
    }

    #[test]
    fn subscriber_receives_signals() {
        let mut cortex = Cortex::default();
        let sub = cortex.subscribe(
            "audio-listener",
            SignalFilter::from_origins(vec![SignalOrigin::AudioEngine]),
        );

        cortex.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        );
        cortex.signal(
            SignalOrigin::SlotLab,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        );

        // Subscriber should only get the AudioEngine signal
        assert_eq!(sub.pending(), 1);
    }

    #[test]
    fn bus_stats_accessible() {
        let mut cortex = Cortex::default();
        for _ in 0..10 {
            cortex.signal(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);
        }
        let stats = cortex.bus_stats();
        assert_eq!(stats.total_emitted, 10);
    }

    #[test]
    fn custom_reflex_registration() {
        let mut cortex = Cortex::new(CortexConfig {
            default_reflexes: false,
            default_patterns: false,
            ..Default::default()
        });

        cortex.reflex_arc_mut().register(crate::reflex::Reflex::new(
            "custom",
            |sig| matches!(sig.kind, SignalKind::Heartbeat),
            crate::reflex::ReflexAction::LogWarning {
                message: "custom reflex!".into(),
            },
            Duration::from_millis(0),
        ));

        cortex.signal(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);
        cortex.tick();
        assert_eq!(cortex.total_reflex_actions, 1);
    }

    #[test]
    fn uptime_tracks() {
        let cortex = Cortex::default();
        std::thread::sleep(Duration::from_millis(5));
        assert!(cortex.uptime().as_millis() >= 5);
    }
}

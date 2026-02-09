//! ALE Engine
//!
//! Main engine that orchestrates signals, contexts, rules, transitions,
//! and stability mechanisms into a cohesive real-time system.

use crate::context::{ContextId, ContextRegistry, LayerId};
use crate::rules::{HeldStates, Rule, RuleRegistry};
use crate::signals::MetricSignals;
use crate::stability::{StabilityConfig, StabilityState};
use crate::transitions::{ActiveTransition, TransitionRegistry};
use rtrb::{Consumer, Producer, RingBuffer};
use std::sync::atomic::{AtomicU8, AtomicU32, Ordering};

/// Commands from UI thread to RT engine
#[derive(Debug, Clone)]
pub enum EngineCommand {
    /// Update metric signals
    UpdateSignals(MetricSignals),
    /// Switch to a different context
    SwitchContext {
        context_id: String,
        trigger: Option<String>,
    },
    /// Force a specific level (manual override)
    ForceLevel { level: LayerId },
    /// Release manual override
    ReleaseManualOverride,
    /// Pause engine
    Pause,
    /// Resume engine
    Resume,
    /// Reset engine to initial state
    Reset,
    /// Add/update a rule
    UpdateRule(Rule),
    /// Remove a rule
    RemoveRule(String),
    /// Update stability config
    UpdateStability(StabilityConfig),
}

/// State updates from RT engine to UI
#[derive(Debug, Clone)]
pub struct EngineState {
    /// Current context ID
    pub context_id: String,
    /// Current level (0-4 = L1-L5)
    pub current_level: LayerId,
    /// Target level (if transitioning)
    pub target_level: Option<LayerId>,
    /// Transition progress (0.0-1.0)
    pub transition_progress: f32,
    /// Whether engine is playing
    pub playing: bool,
    /// Whether manual override is active
    pub manual_override: bool,
    /// Currently firing rule ID (if any)
    pub active_rule: Option<String>,
    /// Hold remaining time (ms)
    pub hold_remaining_ms: u32,
    /// Global cooldown remaining (ms)
    pub cooldown_remaining_ms: u32,
    /// Current signals snapshot
    pub signals: MetricSignals,
    /// Timestamp (ms)
    pub timestamp_ms: u64,
}

/// Layer volume state (for mixing)
#[derive(Debug, Clone, Copy, Default)]
pub struct LayerVolumes {
    /// Volume for each layer (0.0-1.0)
    pub volumes: [f32; 8],
    /// Active layer count
    pub active_count: u8,
}

/// Real-time safe engine core
pub struct AdaptiveLayerEngine {
    // Registries (read-only after setup)
    contexts: ContextRegistry,
    rules: RuleRegistry,
    transitions: TransitionRegistry,

    // Current state (atomic for RT safety)
    current_level: AtomicU8,
    current_context_hash: AtomicU32,
    is_playing: AtomicU8,
    manual_override: AtomicU8,

    // Non-atomic state (only touched by RT thread)
    current_context_id: String,
    target_level: Option<LayerId>,
    signals: MetricSignals,
    prev_signals: Option<MetricSignals>,
    stability: StabilityState,
    held_states: HeldStates,
    active_transition: Option<ActiveTransition>,
    last_fired_rule: Option<String>,

    // Lock-free communication
    command_rx: Consumer<EngineCommand>,
    state_tx: Producer<EngineState>,

    // Timing
    current_time_ms: u64,
    beat_position: f32,
    beat_duration_ms: f32,
    beats_per_bar: u8,
}

impl AdaptiveLayerEngine {
    /// Create a new engine with command/state channels
    pub fn new(command_rx: Consumer<EngineCommand>, state_tx: Producer<EngineState>) -> Self {
        Self {
            contexts: ContextRegistry::new(),
            rules: RuleRegistry::new(),
            transitions: TransitionRegistry::with_builtins(),
            current_level: AtomicU8::new(1),
            current_context_hash: AtomicU32::new(0),
            is_playing: AtomicU8::new(0),
            manual_override: AtomicU8::new(0),
            current_context_id: String::new(),
            target_level: None,
            signals: MetricSignals::new(),
            prev_signals: None,
            stability: StabilityState::new(StabilityConfig::default()),
            held_states: HeldStates::new(),
            active_transition: None,
            last_fired_rule: None,
            command_rx,
            state_tx,
            current_time_ms: 0,
            beat_position: 0.0,
            beat_duration_ms: 500.0, // Default 120 BPM
            beats_per_bar: 4,
        }
    }

    /// Create channels for engine communication
    pub fn create_channels() -> (
        Producer<EngineCommand>,
        Consumer<EngineState>,
        Consumer<EngineCommand>,
        Producer<EngineState>,
    ) {
        let (cmd_tx, cmd_rx) = RingBuffer::new(256);
        let (state_tx, state_rx) = RingBuffer::new(64);
        (cmd_tx, state_rx, cmd_rx, state_tx)
    }

    /// Set the context registry
    pub fn set_contexts(&mut self, contexts: ContextRegistry) {
        self.contexts = contexts;
    }

    /// Set the rule registry
    pub fn set_rules(&mut self, rules: RuleRegistry) {
        self.rules = rules;
    }

    /// Set the transition registry
    pub fn set_transitions(&mut self, transitions: TransitionRegistry) {
        self.transitions = transitions;
    }

    /// Set stability configuration
    pub fn set_stability_config(&mut self, config: StabilityConfig) {
        self.stability.set_config(config);
    }

    /// Switch to a context
    pub fn switch_context(&mut self, context_id: &str, trigger: Option<&str>) {
        if let Some(context) = self.contexts.get(context_id) {
            let current_level = self.current_level.load(Ordering::Relaxed);
            let start_level = context
                .entry_policy
                .resolve_start_level(trigger, current_level);

            self.current_context_id = context_id.to_string();
            self.current_context_hash
                .store(context.hash(), Ordering::Release);

            // Update timing from context
            self.beat_duration_ms = context.audio_character.beat_duration_ms();
            self.beats_per_bar = context.audio_character.time_sig_numerator;

            // Get transition profile
            let transition = trigger
                .and_then(|t| {
                    context
                        .entry_policy
                        .trigger_mappings
                        .iter()
                        .find(|m| m.trigger == t)
                        .and_then(|m| m.transition.as_ref())
                })
                .and_then(|t| self.transitions.get(t))
                .unwrap_or_else(|| self.transitions.default_profile())
                .clone();

            // Calculate sync delay
            let sync_delay = transition.calculate_sync_delay(
                self.beat_position,
                self.beats_per_bar,
                self.beat_duration_ms,
            );

            // Start transition
            self.target_level = Some(start_level);
            self.active_transition = Some(ActiveTransition::new(
                current_level,
                start_level,
                transition,
                self.current_time_ms,
                sync_delay,
            ));

            // Clear stability state for new context
            self.stability.reset();
            self.held_states.clear();
        }
    }

    /// Process engine tick (called from audio thread)
    #[inline]
    pub fn tick(&mut self, delta_ms: u32) -> LayerVolumes {
        // 1. Drain command queue (non-blocking)
        while let Ok(cmd) = self.command_rx.pop() {
            self.handle_command(cmd);
        }

        // Update time
        self.current_time_ms += delta_ms as u64;
        self.beat_position += delta_ms as f32 / self.beat_duration_ms;

        // 2. Update derived signals
        self.signals.update_derived("winTier");

        // 3. Tick stability mechanisms
        self.tick_stability(delta_ms);

        // 4. Evaluate rules (if not in manual override and playing)
        if self.is_playing.load(Ordering::Relaxed) != 0
            && self.manual_override.load(Ordering::Relaxed) == 0
        {
            self.evaluate_rules();
        }

        // 5. Process active transition
        self.tick_transition();

        // 6. Calculate layer volumes
        let volumes = self.calculate_layer_volumes();

        // 7. Publish state to UI (non-blocking)
        let _ = self.state_tx.push(self.capture_state());

        // Store current signals for next tick
        self.prev_signals = Some(self.signals.clone());

        volumes
    }

    /// Handle a command from the UI thread
    fn handle_command(&mut self, cmd: EngineCommand) {
        match cmd {
            EngineCommand::UpdateSignals(signals) => {
                self.signals = signals;
            }
            EngineCommand::SwitchContext {
                context_id,
                trigger,
            } => {
                self.switch_context(&context_id, trigger.as_deref());
            }
            EngineCommand::ForceLevel { level } => {
                self.manual_override.store(1, Ordering::Release);
                self.set_level(level);
            }
            EngineCommand::ReleaseManualOverride => {
                self.manual_override.store(0, Ordering::Release);
            }
            EngineCommand::Pause => {
                self.is_playing.store(0, Ordering::Release);
            }
            EngineCommand::Resume => {
                self.is_playing.store(1, Ordering::Release);
            }
            EngineCommand::Reset => {
                self.reset();
            }
            EngineCommand::UpdateRule(rule) => {
                // This is a simplified version - in production we'd need
                // proper synchronization for rule updates
                log::debug!("Rule update received: {}", rule.id);
            }
            EngineCommand::RemoveRule(id) => {
                log::debug!("Rule removal received: {}", id);
            }
            EngineCommand::UpdateStability(config) => {
                self.stability.set_config(config);
            }
        }
    }

    /// Tick stability mechanisms
    fn tick_stability(&mut self, delta_ms: u32) {
        // Update momentum buffer
        let momentum = self.signals.momentum();
        self.stability.update_momentum(momentum);

        // Check for decay
        let current_level = self.current_level.load(Ordering::Relaxed);
        if let Some(decayed_level) =
            self.stability
                .calculate_decay(current_level, self.current_time_ms, delta_ms)
        {
            // Only decay if we're not in manual override and not transitioning
            if self.manual_override.load(Ordering::Relaxed) == 0 && self.active_transition.is_none()
            {
                self.start_transition(current_level, decayed_level, "default");
            }
        }

        // Update prediction
        let _ = self
            .stability
            .calculate_prediction(current_level, self.current_time_ms);
    }

    /// Evaluate rules and trigger actions
    fn evaluate_rules(&mut self) {
        let context_id = &self.current_context_id;
        if context_id.is_empty() {
            return;
        }

        // Find first matching rule and extract needed data
        let rule_match = self
            .rules
            .find_match(
                context_id,
                &self.signals,
                self.prev_signals.as_ref(),
                &mut self.held_states,
                self.current_time_ms,
            )
            .map(|rule| {
                // Clone the data we need to avoid borrow issues
                (
                    rule.id.clone(),
                    rule.requires_hold_expired,
                    rule.action.clone(),
                    rule.transition.clone(),
                    rule.cooldown_ms,
                    rule.hold_ms,
                )
            });

        let Some((rule_id, requires_hold_expired, action, transition, cooldown_ms, hold_ms)) =
            rule_match
        else {
            return;
        };

        // Check stability constraints
        if !self
            .stability
            .can_change_level(&rule_id, requires_hold_expired, self.current_time_ms)
        {
            return;
        }

        // Get context constraints
        let context_id = &self.current_context_id;
        let (min_level, max_level) = self
            .contexts
            .get(context_id)
            .map(|c| (c.constraints.min_level, c.constraints.max_level))
            .unwrap_or((0, 4));

        // Apply action
        let current_level = self.current_level.load(Ordering::Relaxed);
        let new_level = action.apply(current_level, min_level, max_level);

        // Apply narrative arc if applicable
        let new_level = if let Some(context) = self.contexts.get(context_id) {
            let progress = self.signals.get("featureProgress");
            context
                .narrative_arc
                .apply(new_level, progress, &context.constraints)
        } else {
            new_level
        };

        // Start transition if level changed
        if new_level != current_level {
            let transition_id = transition.as_deref().unwrap_or("default");
            self.start_transition(current_level, new_level, transition_id);

            // Apply stability effects
            self.stability.start_global_cooldown(self.current_time_ms);
            self.stability
                .start_rule_cooldown(&rule_id, cooldown_ms, self.current_time_ms);

            if hold_ms > 0 {
                self.stability
                    .start_hold(new_level, hold_ms, self.current_time_ms);
            }

            self.stability
                .record_level_change(new_level, self.current_time_ms);
            self.last_fired_rule = Some(rule_id);
        }
    }

    /// Start a transition between levels
    fn start_transition(&mut self, from: LayerId, to: LayerId, transition_id: &str) {
        let profile = self
            .transitions
            .get(transition_id)
            .cloned()
            .unwrap_or_default();

        let sync_delay = profile.calculate_sync_delay(
            self.beat_position,
            self.beats_per_bar,
            self.beat_duration_ms,
        );

        self.target_level = Some(to);
        self.active_transition = Some(ActiveTransition::new(
            from,
            to,
            profile,
            self.current_time_ms,
            sync_delay,
        ));
    }

    /// Tick active transition
    fn tick_transition(&mut self) {
        if let Some(ref mut transition) = self.active_transition {
            transition.update(self.current_time_ms);

            if transition.is_complete() {
                self.current_level
                    .store(transition.to_level, Ordering::Release);
                self.target_level = None;
                self.active_transition = None;
            }
        }
    }

    /// Set level directly
    fn set_level(&mut self, level: LayerId) {
        let current = self.current_level.load(Ordering::Relaxed);
        if current != level {
            self.start_transition(current, level, "default");
        }
    }

    /// Calculate layer volumes based on current state
    fn calculate_layer_volumes(&self) -> LayerVolumes {
        let mut volumes = LayerVolumes::default();
        let current_level = self.current_level.load(Ordering::Relaxed) as usize;

        if let Some(ref transition) = self.active_transition {
            // During transition, blend layers
            let from = transition.from_level as usize;
            let to = transition.to_level as usize;

            if from < 8 {
                volumes.volumes[from] = transition.from_volume();
                if volumes.volumes[from] > 0.01 {
                    volumes.active_count += 1;
                }
            }
            if to < 8 && to != from {
                volumes.volumes[to] = transition.to_volume();
                if volumes.volumes[to] > 0.01 {
                    volumes.active_count += 1;
                }
            }
        } else {
            // No transition, single layer active
            if current_level < 8 {
                volumes.volumes[current_level] = 1.0;
                volumes.active_count = 1;
            }
        }

        volumes
    }

    /// Capture current state for UI
    fn capture_state(&self) -> EngineState {
        let current_level = self.current_level.load(Ordering::Relaxed);

        EngineState {
            context_id: self.current_context_id.clone(),
            current_level,
            target_level: self.target_level,
            transition_progress: self
                .active_transition
                .as_ref()
                .map(|t| t.progress)
                .unwrap_or(0.0),
            playing: self.is_playing.load(Ordering::Relaxed) != 0,
            manual_override: self.manual_override.load(Ordering::Relaxed) != 0,
            active_rule: self.last_fired_rule.clone(),
            hold_remaining_ms: self.stability.hold_remaining_ms(self.current_time_ms),
            cooldown_remaining_ms: 0, // Would need to track this
            signals: self.signals.clone(),
            timestamp_ms: self.current_time_ms,
        }
    }

    /// Reset engine to initial state
    fn reset(&mut self) {
        self.current_level.store(1, Ordering::Release);
        self.current_context_hash.store(0, Ordering::Release);
        self.is_playing.store(0, Ordering::Release);
        self.manual_override.store(0, Ordering::Release);
        self.current_context_id.clear();
        self.target_level = None;
        self.signals.clear();
        self.prev_signals = None;
        self.stability.reset();
        self.held_states.clear();
        self.active_transition = None;
        self.last_fired_rule = None;
        self.current_time_ms = 0;
        self.beat_position = 0.0;
    }

    // Getters for atomic state

    /// Get current level
    #[inline]
    pub fn current_level(&self) -> LayerId {
        self.current_level.load(Ordering::Relaxed)
    }

    /// Get current context hash
    #[inline]
    pub fn current_context_hash(&self) -> ContextId {
        self.current_context_hash.load(Ordering::Relaxed)
    }

    /// Check if engine is playing
    #[inline]
    pub fn is_playing(&self) -> bool {
        self.is_playing.load(Ordering::Relaxed) != 0
    }

    /// Check if manual override is active
    #[inline]
    pub fn is_manual_override(&self) -> bool {
        self.manual_override.load(Ordering::Relaxed) != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::{Context, Layer};
    use crate::rules::{Action, ComparisonOp, Condition, SimpleCondition};

    fn create_test_engine() -> AdaptiveLayerEngine {
        let (_, _, cmd_rx, state_tx) = AdaptiveLayerEngine::create_channels();
        let mut engine = AdaptiveLayerEngine::new(cmd_rx, state_tx);

        // Add test context
        let mut context = Context::new("BASE", "Base Game");
        context.add_layer(Layer::new(0, "Ethereal", 0.15));
        context.add_layer(Layer::new(1, "Foundation", 0.35));
        context.add_layer(Layer::new(2, "Tension", 0.55));
        context.add_layer(Layer::new(3, "Drive", 0.75));
        context.add_layer(Layer::new(4, "Climax", 0.95));

        let mut contexts = ContextRegistry::new();
        contexts.register(context);
        engine.set_contexts(contexts);

        engine
    }

    #[test]
    fn test_engine_creation() {
        let engine = create_test_engine();
        assert_eq!(engine.current_level(), 1);
        assert!(!engine.is_playing());
    }

    #[test]
    fn test_switch_context() {
        let mut engine = create_test_engine();
        engine.switch_context("BASE", None);

        assert_eq!(engine.current_context_id, "BASE");
        assert!(engine.active_transition.is_some());
    }

    #[test]
    fn test_layer_volumes_no_transition() {
        let mut engine = create_test_engine();
        engine.current_level.store(2, Ordering::Release);

        let volumes = engine.calculate_layer_volumes();
        assert_eq!(volumes.active_count, 1);
        assert!((volumes.volumes[2] - 1.0).abs() < 0.01);
        assert!((volumes.volumes[0]).abs() < 0.01);
    }
}

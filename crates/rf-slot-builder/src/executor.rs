//! FlowExecutor — deterministic state machine that runs a SlotBlueprint.
//!
//! The executor is the runtime heart of the Slot Construction Kit.
//! It drives the stage flow graph, fires HELIX audio events,
//! enforces compliance constraints, and produces a complete audit trail.
//!
//! ## Thread model
//! - The executor runs on the game thread (not audio thread)
//! - Audio events are dispatched to the HELIX Bus (lock-free queue)
//! - All state transitions are deterministic (given same seed → same outcome)
//!
//! ## Determinism guarantee
//! The executor accepts external events (spin results, user input) and
//! applies transitions deterministically. The same sequence of events
//! always produces the same sequence of stage transitions.
//! This enables:
//! - Replay for compliance verification
//! - RNG seed-based audit trails
//! - Regression testing

use serde::{Deserialize, Serialize};

use crate::blueprint::SlotBlueprint;
use crate::node::{NodeId, TransitionCondition};

// ─── External events that drive the state machine ────────────────────────────

/// Win data for a single winning combination
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinData {
    /// Which line won (None for scatter/ways wins)
    pub line_index: Option<u8>,
    /// Symbols involved
    pub symbols: Vec<u32>,
    /// Win multiplier (relative to bet)
    pub multiplier: f64,
    /// Win amount (in credits)
    pub amount: f64,
}

/// Outcome of a single spin evaluation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpinOutcome {
    /// Total win amount (sum of all wins)
    pub total_win: f64,
    /// Win-to-bet multiplier
    pub win_multiplier: f64,
    /// Individual win lines / ways
    pub wins: Vec<WinData>,
    /// Was a feature triggered?
    pub feature_triggered: bool,
    /// Which feature (if any)
    pub feature_id: Option<String>,
    /// Was a scatter trigger?
    pub scatter_count: u8,
    /// Was a jackpot triggered?
    pub jackpot_tier: Option<String>,
    /// Was this a near-miss?
    pub near_miss: bool,
    /// Cascade count (0 if no cascade)
    pub cascade_count: u32,
    /// Free spins awarded (0 if none)
    pub free_spins_awarded: u8,
    /// Was a retrigger?
    pub is_retrigger: bool,
    /// RNG seed used (for audit)
    pub rng_seed: u64,
}

impl SpinOutcome {
    pub fn no_win(seed: u64) -> Self {
        Self {
            total_win: 0.0,
            win_multiplier: 0.0,
            wins: vec![],
            feature_triggered: false,
            feature_id: None,
            scatter_count: 0,
            jackpot_tier: None,
            near_miss: false,
            cascade_count: 0,
            free_spins_awarded: 0,
            is_retrigger: false,
            rng_seed: seed,
        }
    }

    pub fn is_win(&self) -> bool {
        self.total_win > 0.0
    }

    pub fn is_big_win(&self, threshold: f64) -> bool {
        self.win_multiplier >= threshold
    }
}

/// Events fed to the executor to drive transitions
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum FlowEvent {
    /// User pressed the spin button
    SpinPressed,
    /// Math engine evaluated the spin outcome
    SpinResult(SpinOutcome),
    /// A reel stopped
    ReelStopped { reel_index: u8 },
    /// All reels stopped
    AllReelsStopped,
    /// Rollup counter reached target
    RollupComplete { amount: f64 },
    /// Win presentation animation done
    WinPresentComplete,
    /// User confirmed (skip / collect / OK)
    UserConfirm,
    /// User made a pick choice in bonus
    UserPick { index: u8 },
    /// User made a gamble choice
    UserGamble { choice: String },
    /// Gamble result arrived
    GambleResult { won: bool, amount: f64 },
    /// Feature ended (free spins exhausted)
    FeatureEnd,
    /// Cascade complete (this step)
    CascadeStepComplete { step: u32, multiplier: f64 },
    /// No more cascades
    CascadeSettled,
    /// Buy feature activated
    BuyFeatureActivated,
    /// Jackpot awarded
    JackpotAwarded { tier: String, amount: f64 },
    /// Autoplay toggle
    AutoplayToggle { active: bool },
    /// Responsible gambling limit reached
    RGLimitReached,
    /// Session timeout
    SessionTimeout,
    /// Node display timeout (fired by executor timer internally)
    NodeTimeout,
    /// Custom event (for plugin/script-driven transitions)
    Custom { id: String, payload: serde_json::Value },
}

// ─── Executor state ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExecutorState {
    /// Not started
    Idle,
    /// Actively in a node, waiting for events
    Running,
    /// In a terminal node — ready for next spin press
    Terminal,
    /// Paused (responsible gambling break, etc.)
    Paused,
    /// Error state — blueprint invariant violated
    Error(String),
}

// ─── Audit log entry ──────────────────────────────────────────────────────────

/// One entry in the executor audit trail
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    /// Monotonic sequence number
    pub seq: u64,
    /// Timestamp (milliseconds since executor start)
    pub timestamp_ms: u64,
    /// Node we were in
    pub from_node: String,
    /// Node we moved to (None if terminal/error)
    pub to_node: Option<String>,
    /// Event that triggered this transition
    pub event: String,
    /// Condition that matched
    pub matched_condition: String,
    /// Current spin outcome data (if available)
    pub spin_outcome: Option<SpinOutcome>,
}

// ─── Counter state ────────────────────────────────────────────────────────────

/// Internal counters for loop control (free spins count, retrigger count, etc.)
#[derive(Debug, Clone, Default)]
pub struct CounterState {
    values: std::collections::HashMap<String, u32>,
}

impl CounterState {
    pub fn get(&self, id: &str) -> u32 {
        *self.values.get(id).unwrap_or(&0)
    }

    pub fn set(&mut self, id: &str, val: u32) {
        self.values.insert(id.to_string(), val);
    }

    pub fn increment(&mut self, id: &str) -> u32 {
        let v = self.values.entry(id.to_string()).or_insert(0);
        *v += 1;
        *v
    }

    pub fn decrement(&mut self, id: &str) -> u32 {
        let v = self.values.entry(id.to_string()).or_insert(0);
        *v = v.saturating_sub(1);
        *v
    }

    pub fn reset(&mut self, id: &str) {
        self.values.remove(id);
    }
}

// ─── FlowExecutor ────────────────────────────────────────────────────────────

/// Deterministic state machine runner for a [`SlotBlueprint`].
///
/// Feed external events via [`dispatch`] and read the current node
/// via [`current_node_id`].
pub struct FlowExecutor {
    /// The blueprint being executed
    blueprint: SlotBlueprint,

    /// Current node
    current_node_id: NodeId,

    /// Executor lifecycle state
    state: ExecutorState,

    /// Last spin outcome (used for condition evaluation)
    last_outcome: Option<SpinOutcome>,

    /// Internal counters
    counters: CounterState,

    /// Autoplay active
    autoplay_active: bool,

    /// Free spins remaining
    free_spins_remaining: u8,

    /// Retrigger count in current feature
    retrigger_count: u8,

    /// Milliseconds since current node entry
    node_elapsed_ms: u64,

    /// Monotonic sequence counter
    seq: u64,

    /// Audit trail (append-only)
    audit_trail: Vec<AuditEntry>,

    /// Audio events pending dispatch (drained by the game/audio thread)
    pending_audio_events: Vec<AudioDispatch>,

    /// Stage events emitted (can be consumed by UI/visual layer)
    pending_stage_events: Vec<String>,

    /// Executor start time (ms, monotonic)
    start_ms: u64,
}

/// An audio event queued for dispatch to the HELIX Bus
#[derive(Debug, Clone)]
pub struct AudioDispatch {
    pub event_name: String,
    pub gain_db: Option<f32>,
    pub fade_in_ms: u32,
    pub fade_out_ms: u32,
    pub is_loop: bool,
    pub stop_on_exit: bool,
    pub rtpc_overrides: std::collections::HashMap<String, f32>,
}

impl FlowExecutor {
    /// Create a new executor for a blueprint, starting at the entry node.
    pub fn new(blueprint: SlotBlueprint) -> Self {
        let current_node_id = blueprint.flow.entry_id.clone();
        Self {
            blueprint,
            current_node_id,
            state: ExecutorState::Idle,
            last_outcome: None,
            counters: CounterState::default(),
            autoplay_active: false,
            free_spins_remaining: 0,
            retrigger_count: 0,
            node_elapsed_ms: 0,
            seq: 0,
            audit_trail: Vec::new(),
            pending_audio_events: Vec::new(),
            pending_stage_events: Vec::new(),
            start_ms: 0,
        }
    }

    /// Start the executor — fires entry events for the entry node
    pub fn start(&mut self) {
        self.state = ExecutorState::Running;
        self.start_ms = current_time_ms();
        self.enter_node(self.blueprint.flow.entry_id.clone(), None);
    }

    /// Current state
    pub fn state(&self) -> &ExecutorState {
        &self.state
    }

    /// Current node ID
    pub fn current_node_id(&self) -> &NodeId {
        &self.current_node_id
    }

    /// Current node reference
    pub fn current_node(&self) -> Option<&crate::node::StageNode> {
        self.blueprint.flow.get(&self.current_node_id)
    }

    /// Dispatch an external event — drives transitions.
    /// Returns the new node ID if a transition occurred, None otherwise.
    pub fn dispatch(&mut self, event: FlowEvent) -> Option<NodeId> {
        if self.state == ExecutorState::Idle {
            return None;
        }
        if let ExecutorState::Error(_) = self.state {
            return None;
        }

        // Update last outcome if this is a spin result
        if let FlowEvent::SpinResult(ref outcome) = event {
            self.last_outcome = Some(outcome.clone());
            // Update counters from outcome
            if outcome.feature_triggered {
                self.free_spins_remaining =
                    self.free_spins_remaining.saturating_add(outcome.free_spins_awarded);
            }
            if outcome.is_retrigger {
                self.retrigger_count += 1;
            }
        }

        if let FlowEvent::AutoplayToggle { active } = event {
            self.autoplay_active = active;
            return None;
        }

        // Tick timer
        let now = current_time_ms() - self.start_ms;
        self.node_elapsed_ms = now;

        // Evaluate transitions
        self.try_transition(&event)
    }

    /// Tick the executor (call periodically to handle timeouts)
    pub fn tick(&mut self, elapsed_ms: u64) -> Option<NodeId> {
        self.node_elapsed_ms += elapsed_ms;

        if let Some(node) = self.blueprint.flow.get(&self.current_node_id) {
            let max = node.max_display_ms as u64;
            if max > 0 && self.node_elapsed_ms >= max {
                return self.dispatch(FlowEvent::NodeTimeout);
            }
        }
        None
    }

    /// Drain pending audio events (call from audio/game thread)
    pub fn drain_audio(&mut self) -> Vec<AudioDispatch> {
        std::mem::take(&mut self.pending_audio_events)
    }

    /// Drain pending stage type strings (for UI / visual layer)
    pub fn drain_stage_events(&mut self) -> Vec<String> {
        std::mem::take(&mut self.pending_stage_events)
    }

    /// Audit trail (read-only)
    pub fn audit_trail(&self) -> &[AuditEntry] {
        &self.audit_trail
    }

    /// Free spins remaining
    pub fn free_spins_remaining(&self) -> u8 {
        self.free_spins_remaining
    }

    /// Current retrigger count
    pub fn retrigger_count(&self) -> u8 {
        self.retrigger_count
    }

    /// Reset the executor to entry node (for a new game round)
    pub fn reset(&mut self) {
        self.current_node_id = self.blueprint.flow.entry_id.clone();
        self.state = ExecutorState::Running;
        self.last_outcome = None;
        self.node_elapsed_ms = 0;
        self.retrigger_count = 0;
        self.enter_node(self.blueprint.flow.entry_id.clone(), None);
    }

    // ─── Private ─────────────────────────────────────────────────────────────

    fn try_transition(&mut self, event: &FlowEvent) -> Option<NodeId> {
        let node_id = self.current_node_id.clone();
        let node = self.blueprint.flow.get(&node_id)?;

        // Check minimum display time
        if node.min_display_ms as u64 > self.node_elapsed_ms {
            // Cannot transition yet — but some events bypass (RG, session timeout)
            match event {
                FlowEvent::RGLimitReached | FlowEvent::SessionTimeout => {}
                _ => return None,
            }
        }

        // Collect transition data first (avoid borrow conflict)
        struct TransitionMatch {
            next_id: NodeId,
            condition_str: String,
            delay_ms: u32,
        }

        let matched: Option<TransitionMatch> = {
            let transitions = node.sorted_transitions();
            let mut found = None;
            for t in transitions {
                if self.evaluate_condition(&t.condition, event) {
                    found = Some(TransitionMatch {
                        next_id: t.to.clone(),
                        condition_str: format!("{:?}", t.condition),
                        delay_ms: t.delay_ms,
                    });
                    break;
                }
            }
            found
        };

        if let Some(m) = matched {
            let event_str = format!("{:?}", event);
            let from_name = self.blueprint.flow.get(&node_id)
                .map(|n| n.name.clone())
                .unwrap_or_default();
            let to_name = self.blueprint.flow.get(&m.next_id)
                .map(|n| n.name.clone())
                .unwrap_or_else(|| m.next_id.to_string());

            self.fire_exit_audio(&node_id);
            self.log_audit(from_name, Some(to_name), event_str, m.condition_str);
            self.enter_node(m.next_id.clone(), Some(m.delay_ms));
            return Some(m.next_id);
        }

        None
    }

    fn evaluate_condition(&self, cond: &TransitionCondition, event: &FlowEvent) -> bool {
        let outcome = self.last_outcome.as_ref();

        match cond {
            TransitionCondition::Always => true,

            TransitionCondition::NoWin => {
                outcome.map(|o| !o.is_win()).unwrap_or(false)
                    || matches!(event, FlowEvent::SpinResult(o) if !o.is_win())
            }

            TransitionCondition::WinAmount { min, max } => {
                let amount = outcome.map(|o| o.total_win).unwrap_or(0.0);
                amount >= *min && max.map(|m| amount <= m).unwrap_or(true)
            }

            TransitionCondition::WinMultiplier { min, max } => {
                let mult = outcome.map(|o| o.win_multiplier).unwrap_or(0.0);
                mult >= *min && max.map(|m| mult <= m).unwrap_or(true)
            }

            TransitionCondition::FeatureTriggered { feature_id } => {
                let triggered = outcome.map(|o| o.feature_triggered).unwrap_or(false);
                if !triggered {
                    return false;
                }
                match feature_id {
                    None => true,
                    Some(id) => outcome
                        .and_then(|o| o.feature_id.as_ref())
                        .map(|fid| fid == id)
                        .unwrap_or(false),
                }
            }

            TransitionCondition::ScatterCount { min, max } => {
                let count = outcome.map(|o| o.scatter_count).unwrap_or(0);
                count >= *min && max.map(|m| count <= m).unwrap_or(true)
            }

            TransitionCondition::CascadeOccurred => {
                outcome.map(|o| o.cascade_count > 0).unwrap_or(false)
                    || matches!(event, FlowEvent::CascadeStepComplete { .. })
            }

            TransitionCondition::NoCascade => {
                matches!(event, FlowEvent::CascadeSettled)
            }

            TransitionCondition::CascadeMultiplier { min } => {
                if let FlowEvent::CascadeStepComplete { multiplier, .. } = event {
                    multiplier >= min
                } else {
                    false
                }
            }

            TransitionCondition::Retrigger => {
                outcome.map(|o| o.is_retrigger).unwrap_or(false)
            }

            TransitionCondition::RetriggerLimitReached { max_count } => {
                self.retrigger_count >= *max_count
            }

            TransitionCondition::CounterReached { counter_id, target } => {
                self.counters.get(counter_id) >= *target
            }

            TransitionCondition::CounterNotReached { counter_id, target } => {
                self.counters.get(counter_id) < *target
            }

            TransitionCondition::UserConfirm => {
                matches!(event, FlowEvent::UserConfirm)
            }

            TransitionCondition::UserPick { pick_index } => match event {
                FlowEvent::UserPick { index } => {
                    pick_index.map(|p| p == *index).unwrap_or(true)
                }
                _ => false,
            },

            TransitionCondition::AutoplayActive => self.autoplay_active,

            TransitionCondition::GambleChoice { .. } => {
                matches!(event, FlowEvent::UserGamble { .. })
            }

            TransitionCondition::GambleResult { outcome: expected } => {
                if let FlowEvent::GambleResult { won, .. } = event {
                    use crate::node::GambleOutcome;
                    match expected {
                        GambleOutcome::Win => *won,
                        GambleOutcome::Lose => !*won,
                        GambleOutcome::Draw => false,
                    }
                } else {
                    false
                }
            }

            TransitionCondition::TimeoutMs { ms } => {
                self.node_elapsed_ms >= *ms || matches!(event, FlowEvent::NodeTimeout)
            }

            TransitionCondition::RGLimitReached => {
                matches!(event, FlowEvent::RGLimitReached)
            }

            TransitionCondition::SessionDurationExceeded { .. } => {
                matches!(event, FlowEvent::SessionTimeout)
            }

            TransitionCondition::BuyFeature => {
                matches!(event, FlowEvent::BuyFeatureActivated)
            }

            TransitionCondition::BigWinTier { tier } => {
                use crate::node::BigWinTierCondition;
                let mult = outcome.map(|o| o.win_multiplier).unwrap_or(0.0);
                match tier {
                    BigWinTierCondition::Any => mult >= 10.0,
                    BigWinTierCondition::AtLeast { min_multiplier } => mult >= *min_multiplier,
                    BigWinTierCondition::Exact { .. } => mult >= 10.0, // simplified
                }
            }

            TransitionCondition::JackpotTier { .. } => {
                outcome.map(|o| o.jackpot_tier.is_some()).unwrap_or(false)
                    || matches!(event, FlowEvent::JackpotAwarded { .. })
            }

            TransitionCondition::And { conditions } => {
                conditions.iter().all(|c| self.evaluate_condition(c, event))
            }

            TransitionCondition::Or { conditions } => {
                conditions.iter().any(|c| self.evaluate_condition(c, event))
            }

            TransitionCondition::Not { condition } => {
                !self.evaluate_condition(condition, event)
            }

            TransitionCondition::Custom { .. } => {
                // Custom conditions require an external evaluator plugin
                // Default: false (safe — don't auto-take unknown conditions)
                false
            }
        }
    }

    fn enter_node(&mut self, node_id: NodeId, delay_ms: Option<u32>) {
        self.current_node_id = node_id.clone();
        self.node_elapsed_ms = 0;

        if let Some(node) = self.blueprint.flow.get(&node_id) {
            // Emit stage type for visual layer
            self.pending_stage_events.push(node.stage_type.clone());

            // Fire entry audio
            for event_ref in &node.audio.on_enter.clone() {
                self.pending_audio_events.push(AudioDispatch {
                    event_name: event_ref.event_name.clone(),
                    gain_db: event_ref.gain_db,
                    fade_in_ms: delay_ms.unwrap_or(0) + event_ref.fade_in_ms,
                    fade_out_ms: event_ref.fade_out_ms,
                    is_loop: false,
                    stop_on_exit: false,
                    rtpc_overrides: event_ref.rtpc_overrides.clone(),
                });
            }

            // Fire loop audio
            for event_ref in &node.audio.on_loop.clone() {
                self.pending_audio_events.push(AudioDispatch {
                    event_name: event_ref.event_name.clone(),
                    gain_db: event_ref.gain_db,
                    fade_in_ms: event_ref.fade_in_ms,
                    fade_out_ms: event_ref.fade_out_ms,
                    is_loop: true,
                    stop_on_exit: true,
                    rtpc_overrides: event_ref.rtpc_overrides.clone(),
                });
            }

            // Check terminal
            if node.is_terminal {
                self.state = ExecutorState::Terminal;
            }
        }
    }

    fn fire_exit_audio(&mut self, node_id: &NodeId) {
        if let Some(node) = self.blueprint.flow.get(node_id) {
            for event_ref in &node.audio.on_exit.clone() {
                self.pending_audio_events.push(AudioDispatch {
                    event_name: event_ref.event_name.clone(),
                    gain_db: event_ref.gain_db,
                    fade_in_ms: event_ref.fade_in_ms,
                    fade_out_ms: event_ref.fade_out_ms,
                    is_loop: false,
                    stop_on_exit: false,
                    rtpc_overrides: event_ref.rtpc_overrides.clone(),
                });
            }
        }
    }

    fn log_audit(
        &mut self,
        from: String,
        to: Option<String>,
        event: String,
        condition: String,
    ) {
        self.seq += 1;
        self.audit_trail.push(AuditEntry {
            seq: self.seq,
            timestamp_ms: current_time_ms() - self.start_ms,
            from_node: from,
            to_node: to,
            event,
            matched_condition: condition,
            spin_outcome: self.last_outcome.clone(),
        });
    }
}

fn current_time_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

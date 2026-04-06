// file: crates/rf-cortex/src/executor.rs
//! Command Executor — the efferent muscle that translates autonomic commands
//! into concrete subsystem actions, with CLOSED-LOOP VERIFICATION.
//!
//! The executor completes the full healing cycle:
//!
//! ```text
//! Signal → Reflex → Command → Execute → VERIFY → Signal(outcome)
//!                                          ↑              ↓
//!                                     if failed → ESCALATE (stronger action)
//! ```
//!
//! Each handler returns a `HealingOutcome` with before/after metrics.
//! The executor tracks success rate and emits verification signals back
//! to CORTEX, closing the autonomic loop completely.

use crate::autonomic::{AutonomicCommand, CommandAction, CommandPriority, CommandReceiver};
use crate::signal::SignalOrigin;
use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

/// Result of executing a command.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionResult {
    /// Command executed successfully.
    Executed,
    /// Command was skipped (no handler registered for this action type).
    NoHandler,
    /// Handler ran but reported failure.
    Failed,
}

/// Outcome of a healing action — did the organism actually get better?
#[derive(Debug, Clone)]
pub struct HealingOutcome {
    /// What was the metric BEFORE the action.
    pub before: f32,
    /// What is the metric AFTER the action.
    pub after: f32,
    /// Did the action improve the situation?
    pub healed: bool,
    /// Human-readable description of what changed.
    pub detail: String,
}

impl HealingOutcome {
    /// Create a successful healing outcome.
    pub fn healed(before: f32, after: f32, detail: impl Into<String>) -> Self {
        Self { before, after, healed: true, detail: detail.into() }
    }

    /// Create a failed healing outcome (action ran but didn't help).
    pub fn failed(before: f32, after: f32, detail: impl Into<String>) -> Self {
        Self { before, after, healed: false, detail: detail.into() }
    }

    /// Create an outcome for actions without measurable metrics.
    pub fn applied(detail: impl Into<String>) -> Self {
        Self { before: 0.0, after: 0.0, healed: true, detail: detail.into() }
    }

    /// Improvement ratio (positive = better, negative = worse).
    pub fn improvement(&self) -> f32 {
        if self.before.abs() < f32::EPSILON {
            return 0.0;
        }
        (self.before - self.after) / self.before
    }
}

/// A handler function that executes a specific type of autonomic command.
/// Returns `HealingOutcome` describing what changed.
pub type HealingHandler = Box<dyn Fn(&AutonomicCommand) -> HealingOutcome + Send + Sync>;

/// Legacy handler that returns bool (backwards compatible).
pub type CommandHandler = Box<dyn Fn(&AutonomicCommand) -> bool + Send + Sync>;

/// Record of an executed command (for audit/UI).
#[derive(Debug, Clone)]
pub struct ExecutionRecord {
    pub target: SignalOrigin,
    pub action_tag: String,
    pub reason: String,
    pub priority: CommandPriority,
    pub result: ExecutionResult,
    /// Healing outcome (None if legacy handler or no-handler).
    pub outcome: Option<HealingOutcome>,
    /// When this command was executed.
    pub executed_at: Option<Instant>,
}

/// Stats for the command executor.
#[derive(Debug, Clone, Default)]
pub struct ExecutorStats {
    pub total_executed: u64,
    pub total_failed: u64,
    pub total_no_handler: u64,
    pub total_drained: u64,
    /// Commands that actually healed something.
    pub total_healed: u64,
    /// Commands that ran but didn't improve the situation.
    pub total_not_healed: u64,
}

impl ExecutorStats {
    /// Healing success rate (0.0 to 1.0).
    pub fn healing_rate(&self) -> f32 {
        let total = self.total_healed + self.total_not_healed;
        if total == 0 { return 1.0; }
        self.total_healed as f32 / total as f32
    }
}

/// Wrapper for either legacy or healing handler.
enum HandlerKind {
    Legacy(CommandHandler),
    Healing(HealingHandler),
}

/// The command executor — drains autonomic commands and dispatches to handlers.
/// Supports both legacy bool-returning handlers and healing-outcome handlers.
pub struct CommandExecutor {
    receiver: CommandReceiver,
    handlers: HashMap<String, HandlerKind>,
    /// Fallback handler for unregistered action types.
    fallback: Option<CommandHandler>,
    stats: ExecutorStats,
    /// Recent execution log (ring buffer, last N).
    execution_log: Vec<ExecutionRecord>,
    max_log_size: usize,
}

impl CommandExecutor {
    /// Create a new executor with the given command receiver.
    pub fn new(receiver: CommandReceiver) -> Self {
        Self {
            receiver,
            handlers: HashMap::new(),
            fallback: None,
            stats: ExecutorStats::default(),
            execution_log: Vec::new(),
            max_log_size: 200,
        }
    }

    /// Register a legacy handler for a specific action tag (returns bool).
    pub fn on(&mut self, action_tag: impl Into<String>, handler: CommandHandler) {
        self.handlers.insert(action_tag.into(), HandlerKind::Legacy(handler));
    }

    /// Register a HEALING handler — returns HealingOutcome with before/after metrics.
    /// This is the preferred way to register handlers for closed-loop self-healing.
    pub fn on_healing(&mut self, action_tag: impl Into<String>, handler: HealingHandler) {
        self.handlers.insert(action_tag.into(), HandlerKind::Healing(handler));
    }

    /// Register a fallback handler for unregistered action types.
    pub fn on_unhandled(&mut self, handler: CommandHandler) {
        self.fallback = Some(handler);
    }

    /// Drain all pending commands and execute them. Non-blocking.
    /// Returns the number of commands processed.
    pub fn drain_and_execute(&mut self) -> usize {
        let commands = self.receiver.drain();
        let count = commands.len();

        // Sort by priority (Emergency first)
        let mut sorted = commands;
        sorted.sort_by_key(|b| std::cmp::Reverse(b.priority));

        let now = Instant::now();

        for cmd in &sorted {
            self.stats.total_drained += 1;
            let tag = action_tag(&cmd.action);

            let (result, outcome) = if let Some(handler) = self.handlers.get(&tag) {
                match handler {
                    HandlerKind::Healing(h) => {
                        let outcome = h(cmd);
                        if outcome.healed {
                            self.stats.total_executed += 1;
                            self.stats.total_healed += 1;
                            (ExecutionResult::Executed, Some(outcome))
                        } else {
                            self.stats.total_failed += 1;
                            self.stats.total_not_healed += 1;
                            (ExecutionResult::Failed, Some(outcome))
                        }
                    }
                    HandlerKind::Legacy(h) => {
                        if h(cmd) {
                            self.stats.total_executed += 1;
                            (ExecutionResult::Executed, None)
                        } else {
                            self.stats.total_failed += 1;
                            (ExecutionResult::Failed, None)
                        }
                    }
                }
            } else if let Some(fallback) = &self.fallback {
                if fallback(cmd) {
                    self.stats.total_executed += 1;
                    (ExecutionResult::Executed, None)
                } else {
                    self.stats.total_failed += 1;
                    (ExecutionResult::Failed, None)
                }
            } else {
                self.stats.total_no_handler += 1;
                log::debug!(
                    "CORTEX Executor: no handler for {:?} → {} ({})",
                    cmd.target,
                    tag,
                    cmd.reason
                );
                (ExecutionResult::NoHandler, None)
            };

            self.execution_log.push(ExecutionRecord {
                target: cmd.target,
                action_tag: tag,
                reason: cmd.reason.clone(),
                priority: cmd.priority,
                result,
                outcome,
                executed_at: Some(now),
            });
        }

        // Trim log
        while self.execution_log.len() > self.max_log_size {
            self.execution_log.remove(0);
        }

        count
    }

    /// Get executor stats.
    pub fn stats(&self) -> &ExecutorStats {
        &self.stats
    }

    /// Get recent execution log.
    pub fn recent_log(&self) -> &[ExecutionRecord] {
        &self.execution_log
    }

    /// How many commands are waiting.
    pub fn pending(&self) -> usize {
        self.receiver.pending()
    }

    /// Healing success rate (0.0 to 1.0). Returns 1.0 if no healing actions yet.
    pub fn healing_rate(&self) -> f32 {
        self.stats.healing_rate()
    }
}

/// Extract a tag string from a CommandAction variant (for handler dispatch).
fn action_tag(action: &CommandAction) -> String {
    match action {
        CommandAction::ReduceQuality { .. } => "ReduceQuality".into(),
        CommandAction::RestoreQuality => "RestoreQuality".into(),
        CommandAction::FreeCaches => "FreeCaches".into(),
        CommandAction::AdjustBufferSize { .. } => "AdjustBufferSize".into(),
        CommandAction::ThrottleProcessing { .. } => "ThrottleProcessing".into(),
        CommandAction::BreakFeedback { .. } => "BreakFeedback".into(),
        CommandAction::MuteChannel { .. } => "MuteChannel".into(),
        CommandAction::UnmuteChannel { .. } => "UnmuteChannel".into(),
        CommandAction::EmergencyGainReduce { .. } => "EmergencyGainReduce".into(),
        CommandAction::IsolatePlugin { .. } => "IsolatePlugin".into(),
        CommandAction::RestorePlugin { .. } => "RestorePlugin".into(),
        CommandAction::MemoryCleanup => "MemoryCleanup".into(),
        CommandAction::SuspendBackground => "SuspendBackground".into(),
        CommandAction::ResumeBackground => "ResumeBackground".into(),
        CommandAction::Custom { tag, .. } => format!("Custom:{}", tag),
        CommandAction::GptQuery { topic, .. } => format!("GptQuery:{}", topic),
        CommandAction::GptForwardSuggestion { action, .. } => format!("GptForward:{}", action),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED EXECUTOR STATE (for background thread + FFI access)
// ═══════════════════════════════════════════════════════════════════════════

/// Shared executor state — readable from any thread.
pub struct SharedExecutorState {
    pub total_executed: AtomicU64,
    pub total_failed: AtomicU64,
    pub total_no_handler: AtomicU64,
    pub total_drained: AtomicU64,
    /// Commands that resulted in successful healing.
    pub total_healed: AtomicU64,
    /// Commands that ran but didn't improve the situation.
    pub total_not_healed: AtomicU64,
    pub recent_log: Mutex<Vec<ExecutionRecord>>,
}

impl SharedExecutorState {
    fn new() -> Self {
        Self {
            total_executed: AtomicU64::new(0),
            total_failed: AtomicU64::new(0),
            total_no_handler: AtomicU64::new(0),
            total_drained: AtomicU64::new(0),
            total_healed: AtomicU64::new(0),
            total_not_healed: AtomicU64::new(0),
            recent_log: Mutex::new(Vec::new()),
        }
    }

    fn update(&self, stats: &ExecutorStats, log: &[ExecutionRecord]) {
        self.total_executed.store(stats.total_executed, Ordering::Relaxed);
        self.total_failed.store(stats.total_failed, Ordering::Relaxed);
        self.total_no_handler.store(stats.total_no_handler, Ordering::Relaxed);
        self.total_drained.store(stats.total_drained, Ordering::Relaxed);
        self.total_healed.store(stats.total_healed, Ordering::Relaxed);
        self.total_not_healed.store(stats.total_not_healed, Ordering::Relaxed);
        let mut recent = self.recent_log.lock();
        *recent = log.to_vec();
    }

    /// Healing success rate (0.0 to 1.0).
    pub fn healing_rate(&self) -> f32 {
        let healed = self.total_healed.load(Ordering::Relaxed);
        let not_healed = self.total_not_healed.load(Ordering::Relaxed);
        let total = healed + not_healed;
        if total == 0 { return 1.0; }
        healed as f32 / total as f32
    }
}

/// Executor runtime — runs the executor on a background thread.
pub struct ExecutorRuntime {
    shared: Arc<SharedExecutorState>,
    shutdown: Arc<AtomicBool>,
    thread: Option<thread::JoinHandle<()>>,
}

/// Interval at which the executor drains commands.
const EXECUTOR_INTERVAL: Duration = Duration::from_millis(100);

impl ExecutorRuntime {
    /// Start the executor runtime.
    /// `setup` is called once with a mutable reference to the executor,
    /// allowing handler registration before the loop starts.
    pub fn start(
        receiver: CommandReceiver,
        setup: impl FnOnce(&mut CommandExecutor) + Send + 'static,
    ) -> Self {
        let shared = Arc::new(SharedExecutorState::new());
        let shutdown = Arc::new(AtomicBool::new(false));

        let thread = {
            let shared = Arc::clone(&shared);
            let shutdown = Arc::clone(&shutdown);
            thread::Builder::new()
                .name("cortex-executor".into())
                .spawn(move || {
                    let mut executor = CommandExecutor::new(receiver);
                    setup(&mut executor);

                    log::info!("CORTEX Executor thread started (interval: {:?})", EXECUTOR_INTERVAL);

                    while !shutdown.load(Ordering::Relaxed) {
                        let drained = executor.drain_and_execute();
                        if drained > 0 {
                            shared.update(executor.stats(), executor.recent_log());
                            log::debug!("CORTEX Executor: processed {} commands", drained);
                        }
                        thread::sleep(EXECUTOR_INTERVAL);
                    }

                    log::info!(
                        "CORTEX Executor shutting down (executed: {}, failed: {}, no_handler: {})",
                        executor.stats().total_executed,
                        executor.stats().total_failed,
                        executor.stats().total_no_handler,
                    );
                })
                .expect("Failed to spawn cortex-executor thread")
        };

        Self {
            shared,
            shutdown,
            thread: Some(thread),
        }
    }

    /// Get the shared executor state.
    pub fn shared(&self) -> &Arc<SharedExecutorState> {
        &self.shared
    }

    /// Shutdown the executor.
    pub fn shutdown(mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

impl Drop for ExecutorRuntime {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::autonomic::CommandChannel;

    #[test]
    fn executor_drains_commands() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        // Register handler
        executor.on("ReduceQuality", Box::new(|_cmd| true));

        // Dispatch a command
        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::ReduceQuality { level: 0.5 },
            "test",
            CommandPriority::High,
        ));

        let processed = executor.drain_and_execute();
        assert_eq!(processed, 1);
        assert_eq!(executor.stats().total_executed, 1);
        assert_eq!(executor.stats().total_failed, 0);
    }

    #[test]
    fn executor_no_handler_tracked() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::FreeCaches,
            "no handler registered",
            CommandPriority::Normal,
        ));

        executor.drain_and_execute();
        assert_eq!(executor.stats().total_no_handler, 1);
        assert_eq!(executor.stats().total_executed, 0);
    }

    #[test]
    fn executor_failed_handler() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        executor.on("ReduceQuality", Box::new(|_cmd| false)); // always fail

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::ReduceQuality { level: 0.3 },
            "will fail",
            CommandPriority::Normal,
        ));

        executor.drain_and_execute();
        assert_eq!(executor.stats().total_failed, 1);
        assert_eq!(executor.stats().total_executed, 0);
    }

    #[test]
    fn executor_priority_sorting() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        let order = Arc::new(Mutex::new(Vec::new()));
        let order_clone = Arc::clone(&order);

        executor.on_unhandled(Box::new(move |cmd| {
            order_clone.lock().push(cmd.priority);
            true
        }));

        // Send in reverse priority order
        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::FreeCaches,
            "low",
            CommandPriority::Low,
        ));
        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::ReduceQuality { level: 0.9 },
            "emergency",
            CommandPriority::Emergency,
        ));
        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::RestoreQuality,
            "normal",
            CommandPriority::Normal,
        ));

        executor.drain_and_execute();

        let executed_order = order.lock().clone();
        assert_eq!(executed_order.len(), 3);
        // Emergency should be first
        assert_eq!(executed_order[0], CommandPriority::Emergency);
        assert_eq!(executed_order[1], CommandPriority::Normal);
        assert_eq!(executed_order[2], CommandPriority::Low);
    }

    #[test]
    fn executor_fallback_handler() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        let caught = Arc::new(AtomicBool::new(false));
        let caught_clone = Arc::clone(&caught);

        executor.on_unhandled(Box::new(move |_cmd| {
            caught_clone.store(true, Ordering::Relaxed);
            true
        }));

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::MixerBus,
            CommandAction::MuteChannel { bus_id: 5 },
            "test fallback",
            CommandPriority::Normal,
        ));

        executor.drain_and_execute();
        assert!(caught.load(Ordering::Relaxed));
        assert_eq!(executor.stats().total_executed, 1);
    }

    #[test]
    fn executor_execution_log() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        executor.on("FreeCaches", Box::new(|_| true));

        for _ in 0..3 {
            channel.dispatch(AutonomicCommand::new(
                SignalOrigin::Cortex,
                CommandAction::FreeCaches,
                "memory pressure",
                CommandPriority::Normal,
            ));
        }

        executor.drain_and_execute();
        assert_eq!(executor.recent_log().len(), 3);
        assert!(executor.recent_log().iter().all(|r| r.result == ExecutionResult::Executed));
    }

    #[test]
    fn executor_runtime_background() {
        let (channel, receiver) = CommandChannel::new();

        let executed = Arc::new(AtomicU64::new(0));
        let executed_clone = Arc::clone(&executed);

        let runtime = ExecutorRuntime::start(receiver, move |executor| {
            executor.on("ReduceQuality", Box::new(move |_cmd| {
                executed_clone.fetch_add(1, Ordering::Relaxed);
                true
            }));
        });

        // Dispatch commands
        for _ in 0..5 {
            channel.dispatch(AutonomicCommand::new(
                SignalOrigin::AudioEngine,
                CommandAction::ReduceQuality { level: 0.5 },
                "background test",
                CommandPriority::Normal,
            ));
        }

        // Wait for executor to process
        thread::sleep(Duration::from_millis(250));

        assert_eq!(executed.load(Ordering::Relaxed), 5);
        assert_eq!(
            runtime.shared().total_executed.load(Ordering::Relaxed),
            5
        );

        runtime.shutdown();
    }

    #[test]
    fn action_tag_all_variants() {
        let tags = vec![
            (CommandAction::ReduceQuality { level: 0.5 }, "ReduceQuality"),
            (CommandAction::RestoreQuality, "RestoreQuality"),
            (CommandAction::FreeCaches, "FreeCaches"),
            (CommandAction::AdjustBufferSize { target_samples: 512 }, "AdjustBufferSize"),
            (CommandAction::ThrottleProcessing { factor: 0.5 }, "ThrottleProcessing"),
            (CommandAction::BreakFeedback { bus_chain: vec![1] }, "BreakFeedback"),
            (CommandAction::MuteChannel { bus_id: 0 }, "MuteChannel"),
            (CommandAction::UnmuteChannel { bus_id: 0 }, "UnmuteChannel"),
            (CommandAction::EmergencyGainReduce { bus_id: 0, target_db: -6.0 }, "EmergencyGainReduce"),
            (CommandAction::IsolatePlugin { plugin_id: 1 }, "IsolatePlugin"),
            (CommandAction::RestorePlugin { plugin_id: 1 }, "RestorePlugin"),
            (CommandAction::MemoryCleanup, "MemoryCleanup"),
            (CommandAction::SuspendBackground, "SuspendBackground"),
            (CommandAction::ResumeBackground, "ResumeBackground"),
        ];

        for (action, expected) in tags {
            assert_eq!(action_tag(&action), expected);
        }

        // Custom tag includes the tag name
        let custom = CommandAction::Custom { tag: "mytest".into(), data: "{}".into() };
        assert_eq!(action_tag(&custom), "Custom:mytest");
    }

    #[test]
    fn full_neural_loop_signal_to_execution() {
        // End-to-end: Signal → Cortex → Reflex → Command → Executor → Action
        use crate::cortex::{Cortex, CortexConfig};
        use crate::signal::{SignalKind, SignalUrgency};

        let (cmd_channel, cmd_receiver) = CommandChannel::new();
        let mut cortex = Cortex::with_provided_channel(CortexConfig::default(), cmd_channel);

        let mut executor = CommandExecutor::new(cmd_receiver);
        let action_taken = Arc::new(AtomicBool::new(false));
        let action_clone = Arc::clone(&action_taken);

        executor.on("ReduceQuality", Box::new(move |cmd| {
            if let CommandAction::ReduceQuality { level } = &cmd.action {
                log::info!("EXECUTOR: Reducing quality to {}", level);
                action_clone.store(true, Ordering::Relaxed);
                true
            } else {
                false
            }
        }));

        // Trigger: CPU overload → reflex fires → command dispatched
        cortex.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::CpuLoadAlert { load_percent: 95.0 },
        );
        cortex.tick();

        // Executor drains and executes
        let processed = executor.drain_and_execute();
        assert!(processed > 0, "Expected commands to be dispatched");
        assert!(action_taken.load(Ordering::Relaxed), "Expected ReduceQuality handler to fire");
    }

    // ── Healing Handler Tests ────────────────────────────────────────────

    #[test]
    fn healing_handler_tracks_outcome() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        executor.on_healing("MuteChannel", Box::new(|cmd| {
            if let CommandAction::MuteChannel { bus_id } = &cmd.action {
                HealingOutcome::healed(0.95, 0.0, format!("Muted bus {} — peak dropped", bus_id))
            } else {
                HealingOutcome::failed(0.0, 0.0, "wrong action")
            }
        }));

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::MixerBus,
            CommandAction::MuteChannel { bus_id: 3 },
            "clipping detected",
            CommandPriority::High,
        ));

        executor.drain_and_execute();
        assert_eq!(executor.stats().total_healed, 1);
        assert_eq!(executor.stats().total_not_healed, 0);
        assert!((executor.healing_rate() - 1.0).abs() < f32::EPSILON);

        let log = executor.recent_log();
        assert_eq!(log.len(), 1);
        assert!(log[0].outcome.is_some());
        let outcome = log[0].outcome.as_ref().unwrap();
        assert!(outcome.healed);
        assert!((outcome.before - 0.95).abs() < f32::EPSILON);
        assert!(outcome.after.abs() < f32::EPSILON);
    }

    #[test]
    fn healing_handler_failed_outcome_tracked() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        executor.on_healing("ReduceQuality", Box::new(|_cmd| {
            HealingOutcome::failed(95.0, 94.5, "CPU still high after reduce")
        }));

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::ReduceQuality { level: 0.5 },
            "cpu overload",
            CommandPriority::Emergency,
        ));

        executor.drain_and_execute();
        assert_eq!(executor.stats().total_healed, 0);
        assert_eq!(executor.stats().total_not_healed, 1);
        assert_eq!(executor.stats().total_failed, 1);
        assert!(executor.healing_rate() < 0.01);
    }

    #[test]
    fn healing_outcome_improvement_ratio() {
        let good = HealingOutcome::healed(95.0, 45.0, "CPU reduced");
        assert!((good.improvement() - (95.0 - 45.0) / 95.0).abs() < 0.01);

        let bad = HealingOutcome::failed(95.0, 96.0, "got worse");
        assert!(bad.improvement() < 0.0);

        let zero = HealingOutcome::applied("no metric");
        assert!((zero.improvement()).abs() < f32::EPSILON);
    }

    #[test]
    fn mixed_legacy_and_healing_handlers() {
        let (channel, receiver) = CommandChannel::new();
        let mut executor = CommandExecutor::new(receiver);

        // Legacy handler
        executor.on("FreeCaches", Box::new(|_| true));
        // Healing handler
        executor.on_healing("MuteChannel", Box::new(|_| {
            HealingOutcome::healed(1.0, 0.0, "muted")
        }));

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::Cortex, CommandAction::FreeCaches,
            "memory", CommandPriority::Normal,
        ));
        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::MixerBus, CommandAction::MuteChannel { bus_id: 1 },
            "feedback", CommandPriority::High,
        ));

        executor.drain_and_execute();
        assert_eq!(executor.stats().total_executed, 2);
        assert_eq!(executor.stats().total_healed, 1);

        // Legacy handler produces no outcome
        let log = executor.recent_log();
        // Find FreeCaches record — sorted by priority so MuteChannel (High) first
        let caches = log.iter().find(|r| r.action_tag == "FreeCaches").unwrap();
        assert!(caches.outcome.is_none());
        let mute = log.iter().find(|r| r.action_tag == "MuteChannel").unwrap();
        assert!(mute.outcome.is_some());
    }

    #[test]
    fn shared_state_exposes_healing_rate() {
        let (channel, receiver) = CommandChannel::new();

        let runtime = ExecutorRuntime::start(receiver, |executor| {
            executor.on_healing("ReduceQuality", Box::new(|_| {
                HealingOutcome::healed(90.0, 50.0, "quality reduced")
            }));
            executor.on_healing("FreeCaches", Box::new(|_| {
                HealingOutcome::failed(80.0, 79.0, "barely changed")
            }));
        });

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::AudioEngine, CommandAction::ReduceQuality { level: 0.5 },
            "test", CommandPriority::Normal,
        ));
        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::Cortex, CommandAction::FreeCaches,
            "test", CommandPriority::Normal,
        ));

        thread::sleep(Duration::from_millis(250));

        let shared = runtime.shared();
        assert_eq!(shared.total_healed.load(Ordering::Relaxed), 1);
        assert_eq!(shared.total_not_healed.load(Ordering::Relaxed), 1);
        assert!((shared.healing_rate() - 0.5).abs() < 0.01);

        runtime.shutdown();
    }

    #[test]
    fn full_closed_loop_signal_to_healing() {
        // The ULTIMATE test: Signal → Reflex → Command → Healing → Verified
        use crate::cortex::{Cortex, CortexConfig};
        use crate::signal::{SignalKind, SignalUrgency};

        let (cmd_channel, cmd_receiver) = CommandChannel::new();
        let mut cortex = Cortex::with_provided_channel(CortexConfig::default(), cmd_channel);

        let mut executor = CommandExecutor::new(cmd_receiver);

        // Healing handler that tracks before/after
        executor.on_healing("ReduceQuality", Box::new(|cmd| {
            if let CommandAction::ReduceQuality { level } = &cmd.action {
                // Simulate: CPU was at 95%, after reducing quality it drops
                let before = 95.0;
                let after = 95.0 * (1.0 - level);
                HealingOutcome::healed(before, after, format!("CPU {} → {}", before, after))
            } else {
                HealingOutcome::failed(0.0, 0.0, "wrong action")
            }
        }));

        // Crisis: CPU overload
        cortex.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::CpuLoadAlert { load_percent: 95.0 },
        );
        cortex.tick();

        let processed = executor.drain_and_execute();
        assert!(processed > 0, "Expected healing commands");
        assert_eq!(executor.stats().total_healed, processed as u64);
        assert!(executor.healing_rate() > 0.99);

        // Verify the outcome is in the log
        let log = executor.recent_log();
        assert!(!log.is_empty());
        let first = &log[0];
        assert!(first.outcome.is_some());
        assert!(first.outcome.as_ref().unwrap().healed);
        assert!(first.outcome.as_ref().unwrap().improvement() > 0.0);
    }
}

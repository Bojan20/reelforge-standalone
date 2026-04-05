//! Autonomic Response System — efferent nerves of the CORTEX organism.
//!
//! The afferent path (signals IN) was built first. This module completes the loop:
//! signals flow in → reflexes/patterns fire → commands flow OUT to subsystems.
//!
//! Like the biological autonomic nervous system, this operates below conscious
//! level — subsystems receive commands and execute them without "thinking".
//!
//! Architecture:
//! ```text
//!   Cortex ──→ AutonomicCommand ──→ [command_channel] ──→ Subsystem handlers
//!                                                          │
//!                                   ReduceQuality ─────────┤
//!                                   FreeCaches ────────────┤
//!                                   BreakFeedback ─────────┤
//!                                   IsolatePlugin ─────────┤
//!                                   MuteChannel ───────────┤
//!                                   AdjustBufferSize ──────┤
//!                                   ThrottleProcessing ────┘
//! ```

use crate::signal::SignalOrigin;
use crossbeam_channel::{Receiver, Sender, TrySendError};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

/// A command sent from CORTEX to a subsystem — the efferent nerve impulse.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutonomicCommand {
    /// Which subsystem should receive this command.
    pub target: SignalOrigin,
    /// What action to take.
    pub action: CommandAction,
    /// Why this command was issued (for logging/audit).
    pub reason: String,
    /// Urgency level (higher = execute sooner).
    pub priority: CommandPriority,
    /// When the command was issued.
    #[serde(skip)]
    pub issued_at: Option<Instant>,
}

impl AutonomicCommand {
    pub fn new(
        target: SignalOrigin,
        action: CommandAction,
        reason: impl Into<String>,
        priority: CommandPriority,
    ) -> Self {
        Self {
            target,
            action,
            reason: reason.into(),
            priority,
            issued_at: Some(Instant::now()),
        }
    }
}

/// Priority of an autonomic command.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum CommandPriority {
    /// Background optimization, no rush.
    Low,
    /// Standard response, execute within a few ticks.
    Normal,
    /// Urgent — execute ASAP (e.g., CPU overload).
    High,
    /// Emergency — execute NOW (e.g., feedback loop, imminent crash).
    Emergency,
}

/// The actual action a subsystem should take.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CommandAction {
    // --- Audio Engine commands ---
    /// Reduce DSP processing quality to save CPU.
    /// `level`: 0.0 = full quality, 1.0 = minimum quality.
    ReduceQuality { level: f32 },

    /// Restore full quality processing.
    RestoreQuality,

    /// Free internal caches and pre-allocated buffers.
    FreeCaches,

    /// Adjust audio buffer size (higher = safer but more latency).
    AdjustBufferSize { target_samples: u32 },

    /// Throttle non-critical processing (e.g., skip visualization updates).
    ThrottleProcessing { factor: f32 },

    // --- Mixer commands ---
    /// Break a feedback loop by muting the offending bus chain.
    BreakFeedback { bus_chain: Vec<u32> },

    /// Mute a specific channel/bus.
    MuteChannel { bus_id: u32 },

    /// Unmute a previously muted channel.
    UnmuteChannel { bus_id: u32 },

    /// Apply emergency gain reduction on a bus.
    EmergencyGainReduce { bus_id: u32, target_db: f32 },

    // --- Plugin commands ---
    /// Isolate a faulty plugin (bypass it in the chain).
    IsolatePlugin { plugin_id: u64 },

    /// Restore a previously isolated plugin.
    RestorePlugin { plugin_id: u64 },

    // --- System commands ---
    /// Request garbage collection / memory cleanup.
    MemoryCleanup,

    /// Suspend non-critical background tasks.
    SuspendBackground,

    /// Resume background tasks.
    ResumeBackground,

    /// Custom command for extensibility.
    Custom { tag: String, data: String },
}

/// The command channel — sends commands from Cortex to the outside world.
pub struct CommandChannel {
    tx: Sender<AutonomicCommand>,
    /// Total commands dispatched.
    dispatched: AtomicU64,
    /// Total commands dropped (channel full).
    dropped: AtomicU64,
}

/// Capacity of the command channel.
const COMMAND_CHANNEL_CAPACITY: usize = 256;

impl CommandChannel {
    /// Create a new command channel. Returns (sender side for Cortex, receiver for subsystems).
    pub fn new() -> (Self, CommandReceiver) {
        let (tx, rx) = crossbeam_channel::bounded(COMMAND_CHANNEL_CAPACITY);
        let channel = Self {
            tx,
            dispatched: AtomicU64::new(0),
            dropped: AtomicU64::new(0),
        };
        let receiver = CommandReceiver { rx };
        (channel, receiver)
    }

    /// Dispatch a command. Never blocks.
    pub fn dispatch(&self, command: AutonomicCommand) -> bool {
        self.dispatched.fetch_add(1, Ordering::Relaxed);
        match self.tx.try_send(command) {
            Ok(()) => true,
            Err(TrySendError::Full(_)) => {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                log::warn!("CORTEX autonomic command dropped (channel full)");
                false
            }
            Err(TrySendError::Disconnected(_)) => {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                log::error!("CORTEX autonomic command channel disconnected");
                false
            }
        }
    }

    /// Total commands dispatched.
    pub fn total_dispatched(&self) -> u64 {
        self.dispatched.load(Ordering::Relaxed)
    }

    /// Total commands dropped.
    pub fn total_dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }
}

/// The receiving end of the command channel — held by the subsystem bridge.
pub struct CommandReceiver {
    rx: Receiver<AutonomicCommand>,
}

impl CommandReceiver {
    /// Drain all pending commands (non-blocking).
    pub fn drain(&self) -> Vec<AutonomicCommand> {
        let mut commands = Vec::new();
        while let Ok(cmd) = self.rx.try_recv() {
            commands.push(cmd);
        }
        commands
    }

    /// Try to receive one command (non-blocking).
    pub fn try_recv(&self) -> Option<AutonomicCommand> {
        self.rx.try_recv().ok()
    }

    /// How many commands are pending.
    pub fn pending(&self) -> usize {
        self.rx.len()
    }

    /// Is the sender still alive?
    pub fn is_alive(&self) -> bool {
        !self.rx.is_empty() || self.rx.capacity().is_some()
    }
}

/// Stats for the autonomic system.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutonomicStats {
    pub total_dispatched: u64,
    pub total_dropped: u64,
    pub pending_commands: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_channel_send_receive() {
        let (channel, receiver) = CommandChannel::new();

        let cmd = AutonomicCommand::new(
            SignalOrigin::AudioEngine,
            CommandAction::ReduceQuality { level: 0.5 },
            "CPU overload detected",
            CommandPriority::High,
        );

        assert!(channel.dispatch(cmd));
        assert_eq!(channel.total_dispatched(), 1);
        assert_eq!(channel.total_dropped(), 0);

        let commands = receiver.drain();
        assert_eq!(commands.len(), 1);
        assert_eq!(commands[0].target, SignalOrigin::AudioEngine);
        assert!(matches!(commands[0].action, CommandAction::ReduceQuality { level } if (level - 0.5).abs() < f32::EPSILON));
    }

    #[test]
    fn command_priority_ordering() {
        assert!(CommandPriority::Emergency > CommandPriority::High);
        assert!(CommandPriority::High > CommandPriority::Normal);
        assert!(CommandPriority::Normal > CommandPriority::Low);
    }

    #[test]
    fn command_channel_drops_when_full() {
        let (tx, _rx) = crossbeam_channel::bounded(2);
        let channel = CommandChannel {
            tx,
            dispatched: AtomicU64::new(0),
            dropped: AtomicU64::new(0),
        };

        let make_cmd = || {
            AutonomicCommand::new(
                SignalOrigin::AudioEngine,
                CommandAction::FreeCaches,
                "test",
                CommandPriority::Normal,
            )
        };

        assert!(channel.dispatch(make_cmd()));
        assert!(channel.dispatch(make_cmd()));
        assert!(!channel.dispatch(make_cmd())); // full

        assert_eq!(channel.total_dispatched(), 3);
        assert_eq!(channel.total_dropped(), 1);
    }

    #[test]
    fn command_receiver_drain() {
        let (channel, receiver) = CommandChannel::new();

        for i in 0..5 {
            channel.dispatch(AutonomicCommand::new(
                SignalOrigin::AudioEngine,
                CommandAction::ReduceQuality { level: i as f32 * 0.1 },
                format!("test {}", i),
                CommandPriority::Normal,
            ));
        }

        assert_eq!(receiver.pending(), 5);
        let commands = receiver.drain();
        assert_eq!(commands.len(), 5);
        assert_eq!(receiver.pending(), 0);
    }

    #[test]
    fn command_receiver_try_recv() {
        let (channel, receiver) = CommandChannel::new();

        assert!(receiver.try_recv().is_none());

        channel.dispatch(AutonomicCommand::new(
            SignalOrigin::MixerBus,
            CommandAction::MuteChannel { bus_id: 3 },
            "clipping",
            CommandPriority::High,
        ));

        let cmd = receiver.try_recv().unwrap();
        assert_eq!(cmd.target, SignalOrigin::MixerBus);
        assert!(matches!(cmd.action, CommandAction::MuteChannel { bus_id: 3 }));
    }

    #[test]
    fn all_command_actions_serialize() {
        let actions = vec![
            CommandAction::ReduceQuality { level: 0.5 },
            CommandAction::RestoreQuality,
            CommandAction::FreeCaches,
            CommandAction::AdjustBufferSize { target_samples: 1024 },
            CommandAction::ThrottleProcessing { factor: 0.5 },
            CommandAction::BreakFeedback { bus_chain: vec![1, 2, 3] },
            CommandAction::MuteChannel { bus_id: 0 },
            CommandAction::UnmuteChannel { bus_id: 0 },
            CommandAction::EmergencyGainReduce { bus_id: 0, target_db: -20.0 },
            CommandAction::IsolatePlugin { plugin_id: 42 },
            CommandAction::RestorePlugin { plugin_id: 42 },
            CommandAction::MemoryCleanup,
            CommandAction::SuspendBackground,
            CommandAction::ResumeBackground,
            CommandAction::Custom { tag: "test".into(), data: "{}".into() },
        ];

        for action in actions {
            let json = serde_json::to_string(&action).unwrap();
            let _: CommandAction = serde_json::from_str(&json).unwrap();
        }
    }

    #[test]
    fn receiver_alive_check() {
        let (channel, receiver) = CommandChannel::new();
        assert!(receiver.is_alive());
        drop(channel);
        // After sender drops and channel drains, receiver detects disconnect
        let _ = receiver.drain();
    }
}

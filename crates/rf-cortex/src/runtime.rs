// file: crates/rf-cortex/src/runtime.rs
//! CortexRuntime — manages the cortex lifecycle: background tick thread + handle distribution.
//!
//! Usage:
//! ```ignore
//! let runtime = CortexRuntime::start(CortexConfig::default());
//! let handle = runtime.handle(); // clone and give to any subsystem
//! // ... later ...
//! runtime.shutdown(); // or drop
//! ```

use crate::autonomic::{CommandChannel, CommandReceiver};
use crate::awareness::AwarenessSnapshot;
use crate::cortex::{Cortex, CortexConfig};
use crate::handle::CortexHandle;
use crate::immune::ImmuneSnapshot;
use crate::pattern::RecognizedPattern;
use crate::reflex::ReflexStats;
use crate::signal::NeuralSignal;
use crossbeam_channel::{self, Receiver};
use parking_lot::Mutex;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX EVENT STREAM — Real-time events for Flutter reactive binding
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum events in the ring buffer before oldest are dropped.
const EVENT_BUFFER_CAPACITY: usize = 512;

/// Events emitted by CORTEX for Flutter to consume reactively.
/// Each event represents a meaningful state change — not raw signals,
/// but semantic events the UI cares about.
#[derive(Debug, Clone)]
pub enum CortexEvent {
    /// Health score changed significantly (delta > 0.05).
    HealthChanged {
        old: f64,
        new: f64,
    },
    /// Entered or exited degraded state.
    DegradedStateChanged {
        is_degraded: bool,
    },
    /// A pattern was recognized by the pattern engine.
    PatternRecognized {
        name: String,
        severity: f32,
        description: String,
    },
    /// A reflex fired (instant autonomic reaction).
    ReflexFired {
        name: String,
        fire_count: u64,
    },
    /// An autonomic command was dispatched.
    CommandDispatched {
        action_tag: String,
        reason: String,
    },
    /// Immune system escalated an anomaly.
    ImmuneEscalation {
        category: String,
        escalation_level: u8,
    },
    /// A chronic anomaly was detected or resolved.
    ChronicChanged {
        has_chronic: bool,
    },
    /// Awareness dimensions changed significantly.
    AwarenessUpdated {
        health_score: f64,
        signals_per_second: f64,
        drop_rate: f64,
    },
    /// A healing action completed (closed-loop verification).
    HealingComplete {
        action_tag: String,
        healed: bool,
    },
    /// Signal throughput milestone (every 1000 signals).
    SignalMilestone {
        total: u64,
    },
}

/// Inbox capacity — how many signals can queue before being dropped.
const INBOX_CAPACITY: usize = 8192;

/// Tick interval — how often the cortex processes signals.
const TICK_INTERVAL: Duration = Duration::from_millis(50);

/// The CORTEX runtime — owns the brain and its tick thread.
pub struct CortexRuntime {
    /// Thread-safe handle for emitting signals.
    handle: CortexHandle,
    /// Shared state readable from any thread.
    shared: Arc<SharedCortexState>,
    /// Shutdown flag.
    shutdown: Arc<AtomicBool>,
    /// The tick thread handle.
    tick_thread: Option<thread::JoinHandle<()>>,
    /// Command receiver — subsystems drain this for autonomic commands.
    /// Protected by Mutex so it can be taken once (interior mutability for OnceLock).
    command_receiver: Mutex<Option<CommandReceiver>>,
}

/// Shared cortex state — readable from any thread (behind Mutex for snapshots).
pub struct SharedCortexState {
    /// Latest awareness snapshot.
    pub latest_awareness: Mutex<Option<AwarenessSnapshot>>,
    /// Recent recognized patterns.
    pub recent_patterns: Mutex<Vec<RecognizedPattern>>,
    /// Total signals processed.
    pub total_processed: portable_atomic::AtomicU64,
    /// Total reflex actions fired.
    pub total_reflex_actions: portable_atomic::AtomicU64,
    /// Is degraded?
    pub is_degraded: AtomicBool,
    /// Health score (stored as bits for atomic access).
    pub health_score_bits: portable_atomic::AtomicU64,
    /// Recent reflex stats (name, fire_count, enabled).
    pub reflex_stats: Mutex<Vec<ReflexStats>>,
    /// Total autonomic commands dispatched.
    pub total_commands_dispatched: portable_atomic::AtomicU64,
    /// Latest immune system snapshot.
    pub immune_snapshot: Mutex<Option<ImmuneSnapshot>>,
    /// Has chronic anomaly?
    pub has_chronic: AtomicBool,
    /// Event stream ring buffer — Flutter drains this for reactive updates.
    pub event_buffer: Mutex<VecDeque<CortexEvent>>,
    /// Total events ever pushed (for milestone tracking).
    pub total_events_pushed: portable_atomic::AtomicU64,
}

impl SharedCortexState {
    fn new() -> Self {
        Self {
            latest_awareness: Mutex::new(None),
            recent_patterns: Mutex::new(Vec::new()),
            total_processed: portable_atomic::AtomicU64::new(0),
            total_reflex_actions: portable_atomic::AtomicU64::new(0),
            is_degraded: AtomicBool::new(false),
            health_score_bits: portable_atomic::AtomicU64::new(f64::to_bits(1.0)),
            reflex_stats: Mutex::new(Vec::new()),
            total_commands_dispatched: portable_atomic::AtomicU64::new(0),
            immune_snapshot: Mutex::new(None),
            has_chronic: AtomicBool::new(false),
            event_buffer: Mutex::new(VecDeque::with_capacity(EVENT_BUFFER_CAPACITY)),
            total_events_pushed: portable_atomic::AtomicU64::new(0),
        }
    }

    /// Get current health score.
    pub fn health_score(&self) -> f64 {
        f64::from_bits(self.health_score_bits.load(portable_atomic::Ordering::Relaxed))
    }

    /// Push an event into the ring buffer. Drops oldest if full.
    pub fn push_event(&self, event: CortexEvent) {
        let mut buf = self.event_buffer.lock();
        if buf.len() >= EVENT_BUFFER_CAPACITY {
            buf.pop_front();
        }
        buf.push_back(event);
        self.total_events_pushed.fetch_add(1, portable_atomic::Ordering::Relaxed);
    }

    /// Drain all pending events. Returns them in order (oldest first).
    pub fn drain_events(&self) -> Vec<CortexEvent> {
        let mut buf = self.event_buffer.lock();
        buf.drain(..).collect()
    }

    /// Number of pending events.
    pub fn pending_event_count(&self) -> usize {
        self.event_buffer.lock().len()
    }
}

impl CortexRuntime {
    /// Start the cortex runtime with the given configuration.
    /// Spawns a background tick thread that processes signals every 50ms.
    /// The CommandReceiver is accessible via `take_command_receiver()`.
    pub fn start(config: CortexConfig) -> Self {
        let (tx, rx) = crossbeam_channel::bounded(INBOX_CAPACITY);
        let handle = CortexHandle::new(tx);
        let shared = Arc::new(SharedCortexState::new());
        let shutdown = Arc::new(AtomicBool::new(false));

        // Create command channel BEFORE spawning thread — receiver stays accessible
        let (cmd_channel, cmd_receiver) = CommandChannel::new();

        let tick_thread = {
            let shared = Arc::clone(&shared);
            let shutdown = Arc::clone(&shutdown);
            thread::Builder::new()
                .name("cortex-tick".into())
                .spawn(move || {
                    Self::tick_loop(config, rx, shared, shutdown, cmd_channel);
                })
                .expect("Failed to spawn cortex-tick thread")
        };

        Self {
            handle,
            shared,
            shutdown,
            tick_thread: Some(tick_thread),
            command_receiver: Mutex::new(Some(cmd_receiver)),
        }
    }

    /// The tick loop — runs on the background thread.
    fn tick_loop(
        config: CortexConfig,
        inbox: Receiver<NeuralSignal>,
        shared: Arc<SharedCortexState>,
        shutdown: Arc<AtomicBool>,
        cmd_channel: crate::autonomic::CommandChannel,
    ) {
        // Create cortex with the provided command channel — commands dispatch
        // into the channel, receiver is held externally by CortexRuntime
        let mut cortex = Cortex::with_provided_channel(config, cmd_channel);

        log::info!("CORTEX tick thread started (interval: {:?})", TICK_INTERVAL);

        // Track previous state for change detection → event emission
        let mut prev_health: f64 = 1.0;
        let mut prev_degraded: bool = false;
        let mut prev_chronic: bool = false;
        let mut prev_reflex_actions: u64 = 0;
        let mut prev_commands: u64 = 0;
        let mut prev_milestone: u64 = 0; // signals / 1000

        while !shutdown.load(Ordering::Relaxed) {
            // Drain inbox → feed into cortex
            let mut fed = 0u64;
            while let Ok(signal) = inbox.try_recv() {
                cortex.emit(signal);
                fed += 1;
                // Batch limit to avoid starving the tick
                if fed >= 1000 {
                    break;
                }
            }

            // Process tick
            let patterns = cortex.tick();

            // ═══════════════════════════════════════════════════════════════
            // STATE DIFF → EVENT EMISSION (the reactive nerve impulses)
            // ═══════════════════════════════════════════════════════════════

            let current_health = cortex.awareness()
                .map(|s| s.health_score)
                .unwrap_or(prev_health);

            // Health change (significant delta > 0.05)
            if (current_health - prev_health).abs() > 0.05 {
                shared.push_event(CortexEvent::HealthChanged {
                    old: prev_health,
                    new: current_health,
                });
                prev_health = current_health;
            }

            // Degraded state transition
            let current_degraded = cortex.is_degraded();
            if current_degraded != prev_degraded {
                shared.push_event(CortexEvent::DegradedStateChanged {
                    is_degraded: current_degraded,
                });
                prev_degraded = current_degraded;
            }

            // Chronic anomaly transition
            let current_chronic = cortex.has_chronic_anomaly();
            if current_chronic != prev_chronic {
                shared.push_event(CortexEvent::ChronicChanged {
                    has_chronic: current_chronic,
                });
                prev_chronic = current_chronic;
            }

            // Pattern recognized events
            if !patterns.is_empty() {
                for pattern in &patterns {
                    shared.push_event(CortexEvent::PatternRecognized {
                        name: pattern.name.clone(),
                        severity: pattern.severity,
                        description: pattern.description.clone(),
                    });
                }
            }

            // Reflex fired events (detect new fires)
            let current_reflex_actions = cortex.total_reflex_actions;
            if current_reflex_actions > prev_reflex_actions {
                // Get the reflex that fired most recently
                let stats = cortex.reflex_stats();
                for stat in &stats {
                    if stat.fire_count > 0 {
                        shared.push_event(CortexEvent::ReflexFired {
                            name: stat.name.clone(),
                            fire_count: stat.fire_count,
                        });
                    }
                }
                prev_reflex_actions = current_reflex_actions;
            }

            // Command dispatched events
            let current_commands = cortex.total_commands_dispatched;
            if current_commands > prev_commands {
                shared.push_event(CortexEvent::CommandDispatched {
                    action_tag: "autonomic".into(),
                    reason: format!("{} commands total", current_commands),
                });
                prev_commands = current_commands;
            }

            // Signal milestone (every 1000)
            let current_milestone = cortex.total_processed / 1000;
            if current_milestone > prev_milestone {
                shared.push_event(CortexEvent::SignalMilestone {
                    total: cortex.total_processed,
                });
                prev_milestone = current_milestone;
            }

            // Awareness update event (when snapshot is taken)
            if let Some(snap) = cortex.awareness() {
                shared.push_event(CortexEvent::AwarenessUpdated {
                    health_score: snap.health_score,
                    signals_per_second: snap.signals_per_second,
                    drop_rate: snap.drop_rate,
                });
            }

            // Immune escalation events
            {
                let immune_snap = cortex.immune_snapshot();
                for cat in &immune_snap.categories {
                    if cat.escalation_level > 1 {
                        shared.push_event(CortexEvent::ImmuneEscalation {
                            category: cat.category.clone(),
                            escalation_level: cat.escalation_level,
                        });
                    }
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // SHARED STATE UPDATE (existing logic — unchanged)
            // ═══════════════════════════════════════════════════════════════

            shared.total_processed.store(cortex.total_processed, portable_atomic::Ordering::Relaxed);
            shared.total_reflex_actions.store(cortex.total_reflex_actions, portable_atomic::Ordering::Relaxed);
            shared.total_commands_dispatched.store(cortex.total_commands_dispatched, portable_atomic::Ordering::Relaxed);
            shared.is_degraded.store(current_degraded, Ordering::Relaxed);
            shared.has_chronic.store(current_chronic, Ordering::Relaxed);

            if let Some(snap) = cortex.awareness() {
                shared.health_score_bits.store(
                    f64::to_bits(snap.health_score),
                    portable_atomic::Ordering::Relaxed,
                );
                *shared.latest_awareness.lock() = Some(snap.clone());
            }

            // Update immune snapshot
            *shared.immune_snapshot.lock() = Some(cortex.immune_snapshot());

            if !patterns.is_empty() {
                let mut recent = shared.recent_patterns.lock();
                recent.extend(patterns);
                // Keep only last 100
                if recent.len() > 100 {
                    let drain_count = recent.len() - 100;
                    recent.drain(..drain_count);
                }
            }

            // Update reflex stats (every tick is fine — small data)
            *shared.reflex_stats.lock() = cortex.reflex_stats();

            thread::sleep(TICK_INTERVAL);
        }

        log::info!(
            "CORTEX tick thread shutting down (processed {} signals, dispatched {} commands)",
            cortex.total_processed,
            cortex.total_commands_dispatched
        );
    }

    /// Get a clone of the handle for signal emission.
    pub fn handle(&self) -> CortexHandle {
        self.handle.clone()
    }

    /// Get a reference to the shared state.
    pub fn shared(&self) -> &Arc<SharedCortexState> {
        &self.shared
    }

    /// Get the latest awareness snapshot.
    pub fn awareness(&self) -> Option<AwarenessSnapshot> {
        self.shared.latest_awareness.lock().clone()
    }

    /// Get current health score (lock-free).
    pub fn health_score(&self) -> f64 {
        self.shared.health_score()
    }

    /// Is the cortex degraded? (lock-free)
    pub fn is_degraded(&self) -> bool {
        self.shared.is_degraded.load(Ordering::Relaxed)
    }

    /// Get recent recognized patterns.
    pub fn recent_patterns(&self) -> Vec<RecognizedPattern> {
        self.shared.recent_patterns.lock().clone()
    }

    /// Get immune system snapshot.
    pub fn immune_snapshot(&self) -> Option<ImmuneSnapshot> {
        self.shared.immune_snapshot.lock().clone()
    }

    /// Has any chronic anomaly? (lock-free)
    pub fn has_chronic(&self) -> bool {
        self.shared.has_chronic.load(Ordering::Relaxed)
    }

    /// Total autonomic commands dispatched (lock-free).
    pub fn total_commands_dispatched(&self) -> u64 {
        self.shared.total_commands_dispatched.load(portable_atomic::Ordering::Relaxed)
    }

    /// Take the command receiver (can only be called once).
    /// The receiver is how subsystems get autonomic commands from CORTEX.
    /// Returns None if already taken.
    pub fn take_command_receiver(&self) -> Option<CommandReceiver> {
        self.command_receiver.lock().take()
    }

    /// Gracefully shut down the cortex.
    pub fn shutdown(mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Some(thread) = self.tick_thread.take() {
            let _ = thread.join();
        }
    }
}

impl Drop for CortexRuntime {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        // Thread will notice on next tick and exit
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signal::{SignalKind, SignalOrigin, SignalUrgency};

    #[test]
    fn runtime_start_and_shutdown() {
        let runtime = CortexRuntime::start(CortexConfig::default());
        let handle = runtime.handle();

        // Emit some signals
        handle.signal(SignalOrigin::AudioEngine, SignalUrgency::Normal, SignalKind::Heartbeat);
        handle.signal(SignalOrigin::SlotLab, SignalUrgency::Normal, SignalKind::SpinComplete { result_tier: 3 });

        // Give tick thread time to process
        thread::sleep(Duration::from_millis(100));

        assert!(runtime.shared().total_processed.load(portable_atomic::Ordering::Relaxed) >= 2);
        assert!(!runtime.is_degraded());

        runtime.shutdown();
    }

    #[test]
    fn runtime_handle_is_send_sync() {
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<CortexHandle>();
    }

    #[test]
    fn runtime_awareness_available() {
        let runtime = CortexRuntime::start(CortexConfig {
            awareness_interval: Duration::from_millis(0),
            ..Default::default()
        });

        runtime.handle().signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        );

        thread::sleep(Duration::from_millis(150));

        let snap = runtime.awareness();
        assert!(snap.is_some());
        assert!(runtime.health_score() > 0.0);

        runtime.shutdown();
    }

    #[test]
    fn runtime_multi_thread_emission() {
        let runtime = CortexRuntime::start(CortexConfig::default());

        let threads: Vec<_> = (0..4)
            .map(|_| {
                let h = runtime.handle();
                thread::spawn(move || {
                    for _ in 0..50 {
                        h.signal(
                            SignalOrigin::AudioEngine,
                            SignalUrgency::Normal,
                            SignalKind::Heartbeat,
                        );
                    }
                })
            })
            .collect();

        for t in threads {
            t.join().unwrap();
        }

        thread::sleep(Duration::from_millis(200));

        let processed = runtime.shared().total_processed.load(portable_atomic::Ordering::Relaxed);
        assert!(processed >= 100, "Expected 200 processed, got {}", processed);

        runtime.shutdown();
    }

    #[test]
    fn event_stream_emits_on_state_change() {
        let runtime = CortexRuntime::start(CortexConfig {
            awareness_interval: Duration::from_millis(0),
            ..Default::default()
        });

        // Emit signals that should trigger awareness events
        let handle = runtime.handle();
        for _ in 0..5 {
            handle.signal(SignalOrigin::AudioEngine, SignalUrgency::Normal, SignalKind::Heartbeat);
        }

        // Wait for tick thread to process
        thread::sleep(Duration::from_millis(200));

        // Drain events — should have at least awareness_updated events
        let events = runtime.shared().drain_events();
        assert!(!events.is_empty(), "Expected events to be emitted, got none");

        // Check that awareness events exist
        let awareness_events: Vec<_> = events
            .iter()
            .filter(|e| matches!(e, CortexEvent::AwarenessUpdated { .. }))
            .collect();
        assert!(!awareness_events.is_empty(), "Expected AwarenessUpdated events");

        // After drain, buffer should be empty
        assert_eq!(runtime.shared().pending_event_count(), 0);

        runtime.shutdown();
    }

    #[test]
    fn event_stream_push_and_drain() {
        let shared = Arc::new(SharedCortexState::new());

        // Push some events
        shared.push_event(CortexEvent::HealthChanged { old: 1.0, new: 0.5 });
        shared.push_event(CortexEvent::DegradedStateChanged { is_degraded: true });
        shared.push_event(CortexEvent::PatternRecognized {
            name: "test_pattern".into(),
            severity: 0.8,
            description: "test".into(),
        });

        assert_eq!(shared.pending_event_count(), 3);

        // Drain
        let events = shared.drain_events();
        assert_eq!(events.len(), 3);
        assert_eq!(shared.pending_event_count(), 0);

        // Verify types
        assert!(matches!(&events[0], CortexEvent::HealthChanged { new, .. } if *new == 0.5));
        assert!(matches!(&events[1], CortexEvent::DegradedStateChanged { is_degraded: true }));
        assert!(matches!(&events[2], CortexEvent::PatternRecognized { name, .. } if name == "test_pattern"));
    }

    #[test]
    fn event_buffer_capacity_limit() {
        let shared = Arc::new(SharedCortexState::new());

        // Push more than capacity
        for i in 0..600 {
            shared.push_event(CortexEvent::SignalMilestone { total: i });
        }

        // Should be capped at EVENT_BUFFER_CAPACITY (512)
        assert!(shared.pending_event_count() <= 512);

        // Oldest events should be dropped — first event should be > 0
        let events = shared.drain_events();
        if let CortexEvent::SignalMilestone { total } = &events[0] {
            assert!(*total > 0, "Oldest events should have been dropped");
        }
    }

    #[test]
    fn event_stream_crisis_emits_events() {
        let runtime = CortexRuntime::start(CortexConfig {
            awareness_interval: Duration::from_millis(0),
            ..Default::default()
        });

        let handle = runtime.handle();

        // Trigger crisis: repeated buffer underruns
        for i in 1..=5 {
            handle.signal(
                SignalOrigin::AudioEngine,
                SignalUrgency::Critical,
                SignalKind::BufferUnderrun { count: i },
            );
        }

        thread::sleep(Duration::from_millis(200));

        let events = runtime.shared().drain_events();
        // Should have reflex and/or pattern events from crisis
        let has_reflex = events.iter().any(|e| matches!(e, CortexEvent::ReflexFired { .. }));
        let has_pattern = events.iter().any(|e| matches!(e, CortexEvent::PatternRecognized { .. }));
        assert!(
            has_reflex || has_pattern,
            "Crisis should trigger reflex and/or pattern events. Got {} events: {:?}",
            events.len(),
            events.iter().map(|e| format!("{:?}", std::mem::discriminant(e))).collect::<Vec<_>>()
        );

        runtime.shutdown();
    }
}

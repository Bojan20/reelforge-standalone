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

use crate::awareness::AwarenessSnapshot;
use crate::cortex::{Cortex, CortexConfig};
use crate::handle::CortexHandle;
use crate::pattern::RecognizedPattern;
use crate::reflex::ReflexStats;
use crate::signal::NeuralSignal;
use crossbeam_channel::{self, Receiver};
use parking_lot::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

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
        }
    }

    /// Get current health score.
    pub fn health_score(&self) -> f64 {
        f64::from_bits(self.health_score_bits.load(portable_atomic::Ordering::Relaxed))
    }
}

impl CortexRuntime {
    /// Start the cortex runtime with the given configuration.
    /// Spawns a background tick thread that processes signals every 50ms.
    pub fn start(config: CortexConfig) -> Self {
        let (tx, rx) = crossbeam_channel::bounded(INBOX_CAPACITY);
        let handle = CortexHandle::new(tx);
        let shared = Arc::new(SharedCortexState::new());
        let shutdown = Arc::new(AtomicBool::new(false));

        let tick_thread = {
            let shared = Arc::clone(&shared);
            let shutdown = Arc::clone(&shutdown);
            thread::Builder::new()
                .name("cortex-tick".into())
                .spawn(move || {
                    Self::tick_loop(config, rx, shared, shutdown);
                })
                .expect("Failed to spawn cortex-tick thread")
        };

        Self {
            handle,
            shared,
            shutdown,
            tick_thread: Some(tick_thread),
        }
    }

    /// The tick loop — runs on the background thread.
    fn tick_loop(
        config: CortexConfig,
        inbox: Receiver<NeuralSignal>,
        shared: Arc<SharedCortexState>,
        shutdown: Arc<AtomicBool>,
    ) {
        let mut cortex = Cortex::new(config);

        log::info!("CORTEX tick thread started (interval: {:?})", TICK_INTERVAL);

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

            // Update shared state
            shared.total_processed.store(cortex.total_processed, portable_atomic::Ordering::Relaxed);
            shared.total_reflex_actions.store(cortex.total_reflex_actions, portable_atomic::Ordering::Relaxed);
            shared.is_degraded.store(cortex.is_degraded(), Ordering::Relaxed);

            if let Some(snap) = cortex.awareness() {
                shared.health_score_bits.store(
                    f64::to_bits(snap.health_score),
                    portable_atomic::Ordering::Relaxed,
                );
                *shared.latest_awareness.lock() = Some(snap.clone());
            }

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

        log::info!("CORTEX tick thread shutting down (processed {} signals)", cortex.total_processed);
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
}

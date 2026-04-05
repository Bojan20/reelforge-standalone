// file: crates/rf-cortex/src/handle.rs
//! CortexHandle — thread-safe, Send+Sync handle for emitting signals from any thread.
//!
//! The Cortex itself is single-threaded (owns the bus, reflexes, patterns, awareness).
//! CortexHandle uses a crossbeam channel to send signals INTO the cortex from any thread,
//! including the audio thread (non-blocking try_send).
//!
//! Architecture:
//! ```text
//!   Audio Thread ──┐
//!   UI Thread ─────┤── CortexHandle::signal() ──→ [channel] ──→ Cortex::tick()
//!   Plugin Host ───┘
//! ```

use crate::signal::{NeuralSignal, SignalKind, SignalOrigin, SignalUrgency};
use crossbeam_channel::{Sender, TrySendError};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// Thread-safe handle for emitting signals into the cortex.
///
/// Clone this and hand it to any subsystem. Signal emission is lock-free
/// and will never block the caller (signals are dropped if the inbox is full).
#[derive(Clone)]
pub struct CortexHandle {
    tx: Sender<NeuralSignal>,
    /// Dropped signal counter (shared across all clones).
    dropped: Arc<AtomicU64>,
    /// Total emitted counter (shared across all clones).
    emitted: Arc<AtomicU64>,
}

impl CortexHandle {
    /// Create a new handle from a sender. Called internally by `CortexRuntime::new()`.
    pub(crate) fn new(tx: Sender<NeuralSignal>) -> Self {
        Self {
            tx,
            dropped: Arc::new(AtomicU64::new(0)),
            emitted: Arc::new(AtomicU64::new(0)),
        }
    }

    /// Emit a signal into the cortex. Never blocks.
    /// Returns true if delivered, false if dropped (inbox full).
    pub fn signal(&self, origin: SignalOrigin, urgency: SignalUrgency, kind: SignalKind) -> bool {
        let signal = NeuralSignal::new(origin, urgency, kind);
        self.emit(signal)
    }

    /// Emit a pre-built signal into the cortex. Never blocks.
    pub fn emit(&self, signal: NeuralSignal) -> bool {
        self.emitted.fetch_add(1, Ordering::Relaxed);
        match self.tx.try_send(signal) {
            Ok(()) => true,
            Err(TrySendError::Full(_)) => {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                false
            }
            Err(TrySendError::Disconnected(_)) => {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                false
            }
        }
    }

    /// How many signals have been emitted through this handle (across all clones).
    pub fn total_emitted(&self) -> u64 {
        self.emitted.load(Ordering::Relaxed)
    }

    /// How many signals were dropped (inbox full or disconnected).
    pub fn total_dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    /// Is the cortex still listening? (channel not disconnected)
    pub fn is_alive(&self) -> bool {
        !self.tx.is_empty() || self.tx.capacity().is_some()
    }
}

// CortexHandle is Send + Sync because crossbeam Sender is Send + Sync
// and AtomicU64 is Send + Sync.

#[cfg(test)]
mod tests {
    use super::*;
    use crossbeam_channel;

    #[test]
    fn handle_send_and_receive() {
        let (tx, rx) = crossbeam_channel::bounded(64);
        let handle = CortexHandle::new(tx);

        assert!(handle.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        ));

        let sig = rx.try_recv().unwrap();
        assert_eq!(sig.origin, SignalOrigin::AudioEngine);
        assert_eq!(handle.total_emitted(), 1);
        assert_eq!(handle.total_dropped(), 0);
    }

    #[test]
    fn handle_clone_shares_counters() {
        let (tx, _rx) = crossbeam_channel::bounded(64);
        let h1 = CortexHandle::new(tx);
        let h2 = h1.clone();

        h1.signal(SignalOrigin::AudioEngine, SignalUrgency::Normal, SignalKind::Heartbeat);
        h2.signal(SignalOrigin::SlotLab, SignalUrgency::Normal, SignalKind::Heartbeat);

        assert_eq!(h1.total_emitted(), 2);
        assert_eq!(h2.total_emitted(), 2);
    }

    #[test]
    fn handle_drops_when_full() {
        let (tx, _rx) = crossbeam_channel::bounded(2);
        let handle = CortexHandle::new(tx);

        assert!(handle.signal(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat));
        assert!(handle.signal(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat));
        // Third should fail — channel full
        assert!(!handle.signal(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat));

        assert_eq!(handle.total_emitted(), 3);
        assert_eq!(handle.total_dropped(), 1);
    }

    #[test]
    fn handle_is_send_sync() {
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<CortexHandle>();
    }

    #[test]
    fn handle_across_threads() {
        let (tx, rx) = crossbeam_channel::bounded(128);
        let handle = CortexHandle::new(tx);

        let handles: Vec<_> = (0..4)
            .map(|_| {
                let h = handle.clone();
                std::thread::spawn(move || {
                    for _ in 0..10 {
                        h.signal(SignalOrigin::AudioEngine, SignalUrgency::Normal, SignalKind::Heartbeat);
                    }
                })
            })
            .collect();

        for h in handles {
            h.join().unwrap();
        }

        assert_eq!(handle.total_emitted(), 40);

        let mut count = 0;
        while rx.try_recv().is_ok() {
            count += 1;
        }
        assert_eq!(count, 40);
    }
}

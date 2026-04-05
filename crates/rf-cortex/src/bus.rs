// file: crates/rf-cortex/src/bus.rs
//! NeuralBus — lock-free signal routing backbone of the CORTEX nervous system.
//!
//! Signals flow from any subsystem into the bus, and subscribers receive them
//! filtered by origin and/or urgency. The bus never blocks — signals that can't
//! be delivered are dropped with a warning (better to lose telemetry than stall audio).

use crate::signal::{NeuralSignal, SignalOrigin, SignalUrgency};
use crossbeam_channel::{self, Receiver, Sender, TrySendError};
use portable_atomic::{AtomicU64, Ordering};
use std::collections::HashMap;
use std::sync::Arc;

/// Subscription filter — which signals a subscriber wants to receive.
#[derive(Debug, Clone)]
pub struct SignalFilter {
    /// If set, only receive signals from these origins.
    pub origins: Option<Vec<SignalOrigin>>,
    /// Minimum urgency level to receive.
    pub min_urgency: SignalUrgency,
}

impl SignalFilter {
    /// Accept all signals.
    pub fn all() -> Self {
        Self {
            origins: None,
            min_urgency: SignalUrgency::Ambient,
        }
    }

    /// Accept only signals at or above the given urgency.
    pub fn min_urgency(urgency: SignalUrgency) -> Self {
        Self {
            origins: None,
            min_urgency: urgency,
        }
    }

    /// Accept signals from specific origins.
    pub fn from_origins(origins: Vec<SignalOrigin>) -> Self {
        Self {
            origins: Some(origins),
            min_urgency: SignalUrgency::Ambient,
        }
    }

    /// Does this signal pass the filter?
    pub fn matches(&self, signal: &NeuralSignal) -> bool {
        if signal.urgency < self.min_urgency {
            return false;
        }
        if let Some(ref origins) = self.origins {
            if !origins.contains(&signal.origin) {
                return false;
            }
        }
        true
    }
}

/// A subscriber handle — receives filtered signals from the bus.
pub struct Synapse {
    /// Human-readable name for debugging.
    pub name: String,
    /// The receiving end of the channel.
    pub rx: Receiver<NeuralSignal>,
    /// What this synapse filters for.
    pub filter: SignalFilter,
}

impl Synapse {
    /// Try to receive a signal without blocking. Returns None if no signal available.
    pub fn try_recv(&self) -> Option<NeuralSignal> {
        self.rx.try_recv().ok()
    }

    /// Receive all available signals into a vec (non-blocking drain).
    pub fn drain(&self) -> Vec<NeuralSignal> {
        let mut signals = Vec::new();
        while let Ok(sig) = self.rx.try_recv() {
            signals.push(sig);
        }
        signals
    }

    /// How many signals are currently queued.
    pub fn pending(&self) -> usize {
        self.rx.len()
    }
}

/// Internal subscriber entry.
struct Subscriber {
    name: String,
    tx: Sender<NeuralSignal>,
    filter: SignalFilter,
}

/// The central neural bus — all signals flow through here.
pub struct NeuralBus {
    /// Monotonically increasing signal ID counter.
    next_id: Arc<AtomicU64>,
    /// All subscribers.
    subscribers: Vec<Subscriber>,
    /// Statistics: total signals emitted.
    pub total_emitted: u64,
    /// Statistics: total signals dropped (subscriber channel full).
    pub total_dropped: u64,
    /// Statistics: signals emitted per origin.
    pub origin_counts: HashMap<SignalOrigin, u64>,
}

impl NeuralBus {
    /// Channel capacity per subscriber. Large enough for bursts, bounded to prevent OOM.
    const CHANNEL_CAPACITY: usize = 4096;

    /// Create a new neural bus.
    pub fn new() -> Self {
        Self {
            next_id: Arc::new(AtomicU64::new(1)),
            subscribers: Vec::new(),
            total_emitted: 0,
            total_dropped: 0,
            origin_counts: HashMap::new(),
        }
    }

    /// Subscribe to the bus with a filter. Returns a Synapse for receiving signals.
    pub fn subscribe(&mut self, name: impl Into<String>, filter: SignalFilter) -> Synapse {
        let (tx, rx) = crossbeam_channel::bounded(Self::CHANNEL_CAPACITY);
        let name = name.into();
        self.subscribers.push(Subscriber {
            name: name.clone(),
            tx,
            filter: filter.clone(),
        });
        Synapse { name, rx, filter }
    }

    /// Emit a signal into the bus. It will be routed to all matching subscribers.
    /// This never blocks — if a subscriber's channel is full, the signal is dropped
    /// for that subscriber (with a counter increment).
    pub fn emit(&mut self, mut signal: NeuralSignal) {
        signal.id = self.next_id.fetch_add(1, Ordering::Relaxed);
        self.total_emitted += 1;
        *self.origin_counts.entry(signal.origin).or_insert(0) += 1;

        // Remove disconnected subscribers
        self.subscribers.retain(|sub| !sub.tx.is_empty() || sub.tx.capacity().is_some());

        for sub in &self.subscribers {
            if sub.filter.matches(&signal) {
                if let Err(TrySendError::Full(_)) = sub.tx.try_send(signal.clone()) {
                    self.total_dropped += 1;
                    log::warn!(
                        "NeuralBus: dropped signal #{} for subscriber '{}' (channel full)",
                        signal.id,
                        sub.name
                    );
                }
                // TrySendError::Disconnected is fine — subscriber was dropped
            }
        }
    }

    /// How many subscribers are currently connected.
    pub fn subscriber_count(&self) -> usize {
        self.subscribers.len()
    }

    /// Get bus statistics as a snapshot.
    pub fn stats(&self) -> BusStats {
        BusStats {
            total_emitted: self.total_emitted,
            total_dropped: self.total_dropped,
            subscriber_count: self.subscribers.len(),
            origin_counts: self.origin_counts.clone(),
        }
    }
}

impl Default for NeuralBus {
    fn default() -> Self {
        Self::new()
    }
}

/// Snapshot of bus statistics.
#[derive(Debug, Clone)]
pub struct BusStats {
    pub total_emitted: u64,
    pub total_dropped: u64,
    pub subscriber_count: usize,
    pub origin_counts: HashMap<SignalOrigin, u64>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signal::SignalKind;

    #[test]
    fn subscribe_and_receive() {
        let mut bus = NeuralBus::new();
        let synapse = bus.subscribe("test", SignalFilter::all());

        bus.emit(NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        ));

        let sig = synapse.try_recv().unwrap();
        assert_eq!(sig.id, 1);
        assert_eq!(sig.origin, SignalOrigin::AudioEngine);
    }

    #[test]
    fn filter_by_origin() {
        let mut bus = NeuralBus::new();
        let synapse = bus.subscribe(
            "audio-only",
            SignalFilter::from_origins(vec![SignalOrigin::AudioEngine]),
        );

        // This should NOT be received
        bus.emit(NeuralSignal::new(
            SignalOrigin::SlotLab,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        ));

        // This SHOULD be received
        bus.emit(NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::BufferUnderrun { count: 1 },
        ));

        assert_eq!(synapse.pending(), 1);
        let sig = synapse.try_recv().unwrap();
        assert_eq!(sig.origin, SignalOrigin::AudioEngine);
    }

    #[test]
    fn filter_by_urgency() {
        let mut bus = NeuralBus::new();
        let synapse = bus.subscribe("critical-only", SignalFilter::min_urgency(SignalUrgency::Critical));

        bus.emit(NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        ));
        bus.emit(NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 5 },
        ));

        assert_eq!(synapse.pending(), 1);
    }

    #[test]
    fn multiple_subscribers() {
        let mut bus = NeuralBus::new();
        let s1 = bus.subscribe("all", SignalFilter::all());
        let s2 = bus.subscribe("critical", SignalFilter::min_urgency(SignalUrgency::Critical));

        bus.emit(NeuralSignal::new(
            SignalOrigin::Cortex,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        ));

        assert_eq!(s1.pending(), 1);
        assert_eq!(s2.pending(), 0);
    }

    #[test]
    fn drain_all() {
        let mut bus = NeuralBus::new();
        let synapse = bus.subscribe("test", SignalFilter::all());

        for _ in 0..10 {
            bus.emit(NeuralSignal::new(
                SignalOrigin::Cortex,
                SignalUrgency::Normal,
                SignalKind::Heartbeat,
            ));
        }

        let signals = synapse.drain();
        assert_eq!(signals.len(), 10);
        assert_eq!(synapse.pending(), 0);
    }

    #[test]
    fn stats_tracking() {
        let mut bus = NeuralBus::new();
        let _s = bus.subscribe("test", SignalFilter::all());

        bus.emit(NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        ));
        bus.emit(NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 1 },
        ));
        bus.emit(NeuralSignal::new(
            SignalOrigin::SlotLab,
            SignalUrgency::Normal,
            SignalKind::SpinComplete { result_tier: 3 },
        ));

        let stats = bus.stats();
        assert_eq!(stats.total_emitted, 3);
        assert_eq!(stats.origin_counts[&SignalOrigin::AudioEngine], 2);
        assert_eq!(stats.origin_counts[&SignalOrigin::SlotLab], 1);
    }

    #[test]
    fn signal_ids_are_monotonic() {
        let mut bus = NeuralBus::new();
        let synapse = bus.subscribe("test", SignalFilter::all());

        for _ in 0..5 {
            bus.emit(NeuralSignal::new(
                SignalOrigin::Cortex,
                SignalUrgency::Normal,
                SignalKind::Heartbeat,
            ));
        }

        let signals = synapse.drain();
        for i in 1..signals.len() {
            assert!(signals[i].id > signals[i - 1].id);
        }
    }
}

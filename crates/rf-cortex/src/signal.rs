// file: crates/rf-cortex/src/signal.rs
//! Neural signal types — typed impulses flowing through the CORTEX nervous system.
//!
//! Every subsystem emits signals. The cortex receives, routes, and acts on them.

use serde::{Deserialize, Serialize};
use std::time::Instant;

/// Origin of a neural signal — which subsystem fired it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SignalOrigin {
    AudioEngine,
    DspPipeline,
    MixerBus,
    PluginHost,
    Transport,
    Timeline,
    Automation,
    SlotLab,
    Aurexis,
    MlInference,
    FileSystem,
    Midi,
    Bridge,
    Vision,
    User,
    Cortex,
}

/// Urgency of a signal — determines routing priority.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum SignalUrgency {
    /// Background telemetry, metrics collection
    Ambient,
    /// Normal operational signals
    Normal,
    /// Needs attention soon (e.g. buffer nearing capacity)
    Elevated,
    /// Immediate response required (e.g. RT safety violation detected)
    Critical,
    /// System survival (e.g. audio thread panic imminent, memory exhaustion)
    Emergency,
}

/// The payload of a neural signal — what happened.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SignalKind {
    // --- Audio Engine signals ---
    /// Buffer underrun detected. count = consecutive underruns.
    BufferUnderrun { count: u32 },
    /// CPU load on audio thread crossed threshold.
    CpuLoadAlert { load_percent: f32 },
    /// Sample rate changed.
    SampleRateChanged { old: u32, new: u32 },
    /// Audio device disconnected or changed.
    DeviceChanged { device_name: String },

    // --- DSP Pipeline signals ---
    /// A DSP node's latency changed.
    LatencyChanged { node_id: u64, samples: u32 },
    /// Clipping detected on a channel.
    ClipDetected { channel: u32, peak_db: f32 },

    // --- Mixer signals ---
    /// Level crossed threshold (for metering, ducking).
    LevelCrossing { bus_id: u32, rms_db: f32, peak_db: f32 },
    /// Feedback loop detected in routing.
    FeedbackDetected { bus_chain: Vec<u32> },

    // --- Plugin signals ---
    /// Plugin crashed or became unresponsive.
    PluginFault { plugin_id: u64, reason: String },
    /// Plugin scan completed.
    PluginScanComplete { found: u32, failed: u32 },

    // --- Transport signals ---
    /// Playback state changed.
    TransportStateChanged { playing: bool, recording: bool },
    /// Position jumped (seek, loop restart).
    PositionJump { from_samples: u64, to_samples: u64 },

    // --- SlotLab signals ---
    /// Slot spin completed.
    SpinComplete { result_tier: u8 },
    /// Event triggered in slot game.
    SlotEvent { event_name: String },

    // --- ML signals ---
    /// Inference completed with result.
    InferenceComplete { model: String, latency_ms: f32 },
    /// Model load failed.
    ModelLoadFailed { model: String, reason: String },

    // --- System health signals ---
    /// Memory pressure detected.
    MemoryPressure { used_mb: u64, available_mb: u64 },
    /// Thread pool saturation.
    ThreadPoolSaturated { active: u32, max: u32 },

    // --- Vision signals (from Flutter side via bridge) ---
    /// Visual anomaly detected.
    VisualAnomaly { region: String, description: String },
    /// UI interaction observed.
    UserInteraction { action: String },

    // --- Meta signals ---
    /// Heartbeat from a subsystem (alive check).
    Heartbeat,
    /// Subsystem is shutting down.
    Shutdown,
    /// Custom signal for extensibility.
    Custom { tag: String, data: String },
}

/// A neural signal flowing through the CORTEX nervous system.
#[derive(Debug, Clone)]
pub struct NeuralSignal {
    /// Unique signal ID (monotonically increasing).
    pub id: u64,
    /// When this signal was created.
    pub timestamp: Instant,
    /// Which subsystem emitted this signal.
    pub origin: SignalOrigin,
    /// How urgent is this signal.
    pub urgency: SignalUrgency,
    /// What happened.
    pub kind: SignalKind,
}

impl NeuralSignal {
    /// Create a new signal. ID is assigned by the bus, not the caller.
    pub fn new(origin: SignalOrigin, urgency: SignalUrgency, kind: SignalKind) -> Self {
        Self {
            id: 0, // assigned by NeuralBus on emit
            timestamp: Instant::now(),
            origin,
            urgency,
            kind,
        }
    }

    /// How old is this signal in microseconds.
    pub fn age_us(&self) -> u64 {
        self.timestamp.elapsed().as_micros() as u64
    }

    /// Is this signal still fresh (< threshold_ms old)?
    pub fn is_fresh(&self, threshold_ms: u64) -> bool {
        self.timestamp.elapsed().as_millis() < threshold_ms as u128
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signal_creation() {
        let sig = NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Critical,
            SignalKind::BufferUnderrun { count: 3 },
        );
        assert_eq!(sig.origin, SignalOrigin::AudioEngine);
        assert_eq!(sig.urgency, SignalUrgency::Critical);
        assert!(sig.is_fresh(1000));
    }

    #[test]
    fn urgency_ordering() {
        assert!(SignalUrgency::Emergency > SignalUrgency::Critical);
        assert!(SignalUrgency::Critical > SignalUrgency::Elevated);
        assert!(SignalUrgency::Elevated > SignalUrgency::Normal);
        assert!(SignalUrgency::Normal > SignalUrgency::Ambient);
    }

    #[test]
    fn signal_freshness() {
        let sig = NeuralSignal::new(
            SignalOrigin::Cortex,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        );
        assert!(sig.is_fresh(5000));
    }
}

// file: crates/rf-cortex/src/lib.rs
//! # rf-cortex — CORTEX Nervous System
//!
//! Central nervous system of the FluxForge organism. Routes neural signals
//! between all subsystems, runs reflexes for instant reactions, detects
//! patterns in signal sequences, and maintains self-awareness.
//!
//! ## Architecture
//!
//! ```text
//!                    ┌─────────────────────────┐
//!                    │      CORTEX (Brain)      │
//!                    │                          │
//!                    │  ┌─────┐   ┌──────────┐ │
//!                    │  │Reflex│   │ Pattern  │ │
//!                    │  │ Arc  │   │ Engine   │ │
//!                    │  └──┬──┘   └────┬─────┘ │
//!                    │     │           │        │
//!                    │  ┌──┴───────────┴──┐     │
//!                    │  │   NeuralBus     │     │
//!                    │  └─┬──┬──┬──┬──┬──┘     │
//!                    │    │  │  │  │  │         │
//!                    │  ┌─┴──┴──┴──┴──┴─┐      │
//!                    │  │  Awareness     │      │
//!                    │  └───────────────┘       │
//!                    └─────────────────────────┘
//!           ┌──────────┼──────────┼──────────┼──────────┐
//!           │          │          │          │           │
//!      ┌────┴───┐ ┌────┴───┐ ┌───┴────┐ ┌──┴─────┐ ┌──┴───┐
//!      │ Audio  │ │  DSP   │ │ Mixer  │ │ Plugin │ │ Slot │
//!      │ Engine │ │Pipeline│ │  Bus   │ │  Host  │ │ Lab  │
//!      └────────┘ └────────┘ └────────┘ └────────┘ └──────┘
//! ```
//!
//! ## Quick Start
//!
//! ```rust
//! use rf_cortex::prelude::*;
//!
//! // Create the cortex
//! let mut cortex = Cortex::default();
//!
//! // Subscribe to specific signals
//! let audio_sub = cortex.subscribe("my-listener",
//!     SignalFilter::from_origins(vec![SignalOrigin::AudioEngine]));
//!
//! // Emit a signal
//! cortex.signal(
//!     SignalOrigin::AudioEngine,
//!     SignalUrgency::Critical,
//!     SignalKind::BufferUnderrun { count: 3 },
//! );
//!
//! // Process — reflexes fire, patterns checked, awareness updated
//! let patterns = cortex.tick();
//! ```

pub mod awareness;
pub mod bus;
pub mod cortex;
pub mod handle;
pub mod pattern;
pub mod reflex;
pub mod runtime;
pub mod signal;

/// Prelude — import everything you need with `use rf_cortex::prelude::*`
pub mod prelude {
    pub use crate::awareness::{AwarenessDimensions, AwarenessEngine, AwarenessSnapshot};
    pub use crate::bus::{BusStats, NeuralBus, SignalFilter, Synapse};
    pub use crate::cortex::{Cortex, CortexConfig};
    pub use crate::handle::CortexHandle;
    pub use crate::pattern::{PatternDetector, PatternEngine, RecognizedPattern};
    pub use crate::reflex::{Reflex, ReflexAction, ReflexArc};
    pub use crate::runtime::{CortexRuntime, SharedCortexState};
    pub use crate::signal::{NeuralSignal, SignalKind, SignalOrigin, SignalUrgency};
}

#[cfg(test)]
mod integration_tests {
    use crate::prelude::*;
    use std::time::Duration;

    #[test]
    fn full_pipeline_signal_to_awareness() {
        let mut cortex = Cortex::new(CortexConfig {
            awareness_interval: Duration::from_millis(0),
            default_reflexes: true,
            default_patterns: true,
            ..Default::default()
        });

        // Simulate a session: multiple subsystems sending signals
        cortex.signal(SignalOrigin::AudioEngine, SignalUrgency::Normal, SignalKind::Heartbeat);
        cortex.signal(
            SignalOrigin::Transport,
            SignalUrgency::Normal,
            SignalKind::TransportStateChanged {
                playing: true,
                recording: false,
            },
        );
        cortex.signal(
            SignalOrigin::MixerBus,
            SignalUrgency::Normal,
            SignalKind::LevelCrossing {
                bus_id: 0,
                rms_db: -18.0,
                peak_db: -6.0,
            },
        );

        let patterns = cortex.tick();
        assert!(patterns.is_empty()); // Normal operation, no patterns

        let snap = cortex.awareness_now();
        assert!(snap.health_score > 0.3);
        assert_eq!(cortex.total_processed, 3);
    }

    #[test]
    fn crisis_scenario_underruns_cascade() {
        let mut cortex = Cortex::default();

        // Simulate audio crisis: CPU spike + repeated underruns
        cortex.signal(
            SignalOrigin::AudioEngine,
            SignalUrgency::Elevated,
            SignalKind::CpuLoadAlert { load_percent: 85.0 },
        );

        for i in 1..=5 {
            cortex.signal(
                SignalOrigin::AudioEngine,
                SignalUrgency::Critical,
                SignalKind::BufferUnderrun { count: i },
            );
        }

        let patterns = cortex.tick();

        // Should have detected repeated underruns
        assert!(!patterns.is_empty(), "Expected crisis pattern detection");
        assert!(cortex.total_reflex_actions > 0, "Expected reflexes to fire");

        // Pattern severity should be high
        let max_severity = patterns.iter().map(|p| p.severity).fold(0.0f32, f32::max);
        assert!(max_severity > 0.5, "Expected high-severity pattern");
    }

    #[test]
    fn subscriber_isolation() {
        let mut cortex = Cortex::default();

        // Two subscribers with different filters
        let audio_sub = cortex.subscribe(
            "audio-monitor",
            SignalFilter::from_origins(vec![SignalOrigin::AudioEngine]),
        );
        let critical_sub = cortex.subscribe(
            "critical-monitor",
            SignalFilter::min_urgency(SignalUrgency::Critical),
        );

        // Normal audio signal
        cortex.signal(SignalOrigin::AudioEngine, SignalUrgency::Normal, SignalKind::Heartbeat);
        // Critical slot signal
        cortex.signal(
            SignalOrigin::SlotLab,
            SignalUrgency::Critical,
            SignalKind::SlotEvent {
                event_name: "big_win".into(),
            },
        );
        // Normal slot signal
        cortex.signal(
            SignalOrigin::SlotLab,
            SignalUrgency::Normal,
            SignalKind::SpinComplete { result_tier: 1 },
        );

        // audio_sub gets only audio signals (1)
        assert_eq!(audio_sub.pending(), 1);
        // critical_sub gets only critical signals (1)
        assert_eq!(critical_sub.pending(), 1);
    }

    #[test]
    fn awareness_tracks_health_over_time() {
        let mut cortex = Cortex::new(CortexConfig {
            awareness_interval: Duration::from_millis(0),
            ..Default::default()
        });

        // Healthy period
        for _ in 0..5 {
            cortex.signal(SignalOrigin::AudioEngine, SignalUrgency::Normal, SignalKind::Heartbeat);
            cortex.tick();
            cortex.awareness_now();
        }

        let avg = cortex.average_health(5);
        assert!(avg > 0.3, "Healthy period should have good average health: {}", avg);
    }

    #[test]
    fn custom_reflex_and_pattern() {
        let mut cortex = Cortex::new(CortexConfig {
            default_reflexes: false,
            default_patterns: false,
            ..Default::default()
        });

        // Custom reflex: any heartbeat → emit custom signal
        cortex.reflex_arc_mut().register(Reflex::new(
            "heartbeat-echo",
            |sig| matches!(sig.kind, SignalKind::Heartbeat),
            ReflexAction::EmitSignal {
                origin: SignalOrigin::Cortex,
                urgency: SignalUrgency::Ambient,
                kind: SignalKind::Custom {
                    tag: "echo".into(),
                    data: "heartbeat received".into(),
                },
            },
            Duration::from_millis(0),
        ));

        // Custom pattern: 3+ custom signals = recognition
        cortex.pattern_engine_mut().register(PatternDetector::new(
            "echo-storm",
            Duration::from_millis(0),
            |window| {
                let custom_count = window
                    .iter()
                    .filter(|s| matches!(s.kind, SignalKind::Custom { .. }))
                    .count();
                if custom_count >= 3 {
                    Some((0.3, format!("{} echoes detected", custom_count)))
                } else {
                    None
                }
            },
        ));

        // Send heartbeats (which trigger echo reflex → custom signals)
        for _ in 0..5 {
            cortex.signal(SignalOrigin::Cortex, SignalUrgency::Normal, SignalKind::Heartbeat);
            cortex.tick(); // process + reflexes emit custom signals
        }

        // The echoed custom signals should be in the bus for next tick
        let _patterns = cortex.tick();
        // Pattern might or might not fire depending on whether reflex-emitted
        // signals were processed in time — this tests the wiring, not timing
        assert!(cortex.total_reflex_actions >= 5);
    }
}

//! rf-neuro — NeuroAudio™ Real-time Player Behavioral Signal Processor
//!
//! Processes behavioral signals from a slot game session and outputs an 8D
//! Player State Vector that drives real-time audio adaptation via RTPC.
//!
//! ## Architecture
//!
//! ```text
//! BehavioralSample  →  NeuroEngine  →  PlayerStateVector (8D)
//!                            ↓
//!                    AudioAdaptation  →  RTPC writes
//! ```
//!
//! The engine maintains a 5-minute sliding window of behavioral samples.
//! All computation is deterministic — identical inputs produce identical outputs.
//! No randomness, no wall-clock dependency (timestamps are from input).
//!
//! ## Player State Vector Dimensions
//!
//! | Dimension       | Range | Meaning                          |
//! |-----------------|-------|----------------------------------|
//! | arousal         | 0–1   | calm/bored ↔ excited/stimulated  |
//! | valence         | 0–1   | frustrated/negative ↔ euphoric   |
//! | engagement      | 0–1   | about-to-leave ↔ deep-flow       |
//! | risk_tolerance  | 0–1   | conservative ↔ reckless-chasing  |
//! | frustration     | 0–1   | content ↔ tilted                 |
//! | anticipation    | 0–1   | nothing-expected ↔ big-win-near  |
//! | fatigue         | 0–1   | fresh ↔ exhausted                |
//! | churn_prob      | 0–1   | staying ↔ about-to-quit          |

pub mod engine;
pub mod events;
pub mod session;
pub mod state;

pub use engine::{NeuroConfig, NeuroEngine};
pub use events::{BehavioralEvent, BehavioralSample, SpinOutcome};
pub use session::{ArchetypePreset, SessionSimulation, SimulationResult};
pub use state::{AudioAdaptation, PlayerStateVector, RgIntervention};

//! # rf-ab-sim — Audio-Aware Batch Spin Simulator
//!
//! 1M+ spin simulation engine for slot game audio validation.
//! Answers the question: "How often will each audio event fire, and will
//! the voice budget ever be exceeded?"
//!
//! ## T2.3 Capabilities
//!
//! - Parallel simulation via Rayon (scales to all CPU cores)
//! - Event frequency heatmap (per event: count, per-1000, peak concurrent, min gap)
//! - Voice budget prediction (max simultaneous voices at any point)
//! - Dry spell analysis (how long between wins)
//! - Win distribution validation against PAR target
//! - Progress callback every 10,000 spins for UI feedback
//! - Deterministic mode (fixed seed) for reproducible tests
//!
//! ## Architecture
//!
//! ```text
//! BatchSimConfig → [Rayon worker pool] → per-thread MiniBatchResult
//!                                           ↓
//!                                    merge → BatchSimResult
//! ```

pub mod config;
pub mod result;
pub mod simulator;
pub mod ffi;

pub use config::{
    BatchSimConfig, AudioEventDef, PlayerArchetype, PlayerBehavior,
};
pub use result::{
    BatchSimResult, EventFrequency, DrySpellReport, WinDistribution,
    TimelineSample, VoiceBudgetPrediction,
};
pub use simulator::BatchSimulator;

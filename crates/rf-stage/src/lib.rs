//! # rf-stage — FluxForge Universal Stage System
//!
//! Defines canonical game stages that all slot engines map to.
//! FluxForge never understands engine-specific events — only STAGES.
//!
//! ## Philosophy
//!
//! All slot games, regardless of engine, pass through the same semantic phases:
//! - Spin starts → Reels stop → Wins evaluated → Features triggered
//!
//! This crate defines these universal stages and provides timing resolution.

pub mod audio_naming;
pub mod event;
pub mod sonic_dna;
pub mod stage;
pub mod stage_library;
pub mod taxonomy;
pub mod timing;
pub mod trace;

pub use audio_naming::*;
pub use event::*;
pub use sonic_dna::{
    all_profiles, classify_and_place, hungarian_assignment, build_score_matrix,
    EnvelopeShape, FeatureVector, FeatureWeights, PlacementResult, SlotSoundProfile,
    SlotSoundType, SoundClassification,
};
pub use stage::*;
pub use stage_library::*;
pub use taxonomy::*;
pub use timing::*;
pub use trace::*;

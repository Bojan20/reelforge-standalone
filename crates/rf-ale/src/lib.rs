//! # Adaptive Layer Engine (ALE)
//!
//! Data-driven, context-aware, metric-reactive music system for slot games.
//!
//! ## Architecture
//!
//! - **Signals**: Normalized metrics (winTier, momentum, velocity, etc.)
//! - **Contexts**: Game chapters (BASE, FREESPINS, HOLDWIN, etc.)
//! - **Layers**: Intensity levels L1-L5 (energy degrees, not audio files)
//! - **Rules**: Conditions + actions that drive layer transitions
//! - **Transitions**: Beat-synced fades with multiple curves
//! - **Stability**: 7 mechanisms to prevent erratic behavior
//!
//! ## Real-Time Safety
//!
//! The engine uses lock-free communication (rtrb) and pre-allocated buffers.
//! No allocations occur during audio processing.

pub mod context;
pub mod engine;
pub mod profile;
pub mod rules;
pub mod signals;
pub mod stability;
pub mod transitions;

pub use context::*;
pub use engine::*;
pub use profile::*;
pub use rules::*;
pub use signals::*;
pub use stability::*;
pub use transitions::*;

use thiserror::Error;

/// ALE error types
#[derive(Debug, Error)]
pub enum AleError {
    #[error("Invalid signal: {0}")]
    InvalidSignal(String),

    #[error("Unknown context: {0}")]
    UnknownContext(String),

    #[error("Invalid rule: {0}")]
    InvalidRule(String),

    #[error("Transition error: {0}")]
    TransitionError(String),

    #[error("Profile error: {0}")]
    ProfileError(String),

    #[error("JSON parse error: {0}")]
    JsonError(#[from] serde_json::Error),
}

pub type AleResult<T> = Result<T, AleError>;

/// Maximum number of layers (L1-L5 + room for expansion)
pub const MAX_LAYERS: usize = 8;

/// Maximum number of tracks per layer
pub const MAX_TRACKS_PER_LAYER: usize = 8;

/// Maximum total loaded tracks
pub const MAX_TOTAL_TRACKS: usize = 64;

/// Maximum number of rules
pub const MAX_RULES: usize = 256;

/// Maximum loaded contexts
pub const MAX_CONTEXTS: usize = 16;

/// Signal history depth for momentum/velocity calculations
pub const SIGNAL_HISTORY_DEPTH: usize = 100;

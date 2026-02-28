//! # AUREXIS™ — Deterministic Slot Audio Intelligence Engine
//!
//! Pure intelligence layer that translates slot mathematics into audio behavior.
//! Outputs `DeterministicParameterMap` — never processes audio.
//!
//! **No dependency** on rf-ale, rf-engine, rf-dsp, rf-spatial.
//! Consumers read the parameter map and apply values themselves.

pub mod core;
pub mod volatility;
pub mod rtp;
pub mod psycho;
pub mod collision;
pub mod escalation;
pub mod variation;
pub mod geometry;
pub mod platform;
pub mod energy;
pub mod priority;
pub mod spectral;
pub mod advisory;
pub mod drc;
pub mod qa;
pub mod sam;

pub use crate::core::engine::AurexisEngine;
pub use crate::core::config::AurexisConfig;
pub use crate::core::state::AurexisState;
pub use crate::core::parameter_map::DeterministicParameterMap;
pub use crate::energy::{EnergyGovernor, EnergyDomain, EnergyBudget, VoiceBudget, SlotProfile, SessionMemory, GegCurveType};
pub use crate::priority::{DynamicPriorityMatrix, EventType, EmotionalState, VoicePriority, VoiceSurvivalResult, SurvivalAction, DpmOutput};
pub use crate::spectral::{SpectralAllocator, SpectralRole, SpectralBand, SpectralAssignment, SpectralAllocationOutput, MaskingResolver, MaskingStrategy, MaskingAction, SciAdvanced};
pub use crate::qa::{PreBakeSimulator, SimulationDomain, ValidationThresholds, PbseResult, DomainResult, FatigueModelResult, MetricValidation};
pub use crate::advisory::{AuthoringIntelligence, AilDomain, AilScore, AilStatus, AilReport, AilRecommendation, RecommendationLevel, DomainAnalysis, FatigueAnalysis, VoiceEfficiency, SpectralClarityAnalysis, VolatilityAlignment};
pub use crate::drc::{DeterministicReplayCore, TraceEntry, FrameHash, TraceMetadata, TraceFormat, ReplayResult, FluxManifest, VersionLocks, ConfigBundle, CertificationChain, CertificationStatus, SafetyEnvelope, SafetyLimits, EnvelopeViolation, EnvelopeViolationType, EnvelopeResult, CertificationGate, CertificationResult, CertificationReport};
pub use crate::sam::{SmartAuthoringEngine, AuthoringMode, WizardStep, SmartAuthoringState, ParameterMapping, SlotArchetype, ArchetypeProfile, ArchetypeDefaults, VolatilityRange, MarketTarget, SmartControlGroup, SmartControl, SmartControlValue, EnergyControls, ClarityControls, StabilityControls, SmartControlSet};

/// Result type for AUREXIS operations.
pub type AurexisResult<T> = Result<T, AurexisError>;

/// Maximum concurrent voices tracked for collision.
pub const MAX_VOICES: usize = 64;

/// Maximum screen events tracked for attention vector.
pub const MAX_SCREEN_EVENTS: usize = 32;

/// Default tick interval in milliseconds.
pub const DEFAULT_TICK_MS: u64 = 50;

/// Minimum supported RTP percentage.
pub const MIN_RTP: f64 = 85.0;

/// Maximum supported RTP percentage.
pub const MAX_RTP: f64 = 99.5;

/// AUREXIS error types.
#[derive(Debug, thiserror::Error)]
pub enum AurexisError {
    #[error("AUREXIS not initialized")]
    NotInitialized,

    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("Invalid parameter: {field} = {value} (expected {expected})")]
    InvalidParameter {
        field: String,
        value: String,
        expected: String,
    },

    #[error("Voice not found: {0}")]
    VoiceNotFound(u32),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("Capacity exceeded: {what} ({count}/{max})")]
    CapacityExceeded {
        what: String,
        count: usize,
        max: usize,
    },
}

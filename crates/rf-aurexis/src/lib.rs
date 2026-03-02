//! # AUREXIS™ — Deterministic Slot Audio Intelligence Engine
//!
//! Pure intelligence layer that translates slot mathematics into audio behavior.
//! Outputs `DeterministicParameterMap` — never processes audio.
//!
//! **No dependency** on rf-ale, rf-engine, rf-dsp, rf-spatial.
//! Consumers read the parameter map and apply values themselves.

pub mod advisory;
pub mod collision;
pub mod core;
pub mod drc;
pub mod energy;
pub mod escalation;
pub mod gad;
pub mod geometry;
pub mod platform;
pub mod priority;
pub mod psycho;
pub mod qa;
pub mod rtp;
pub mod sam;
pub mod spectral;
pub mod sss;
pub mod variation;
pub mod volatility;

pub use crate::advisory::{
    AilDomain, AilRecommendation, AilReport, AilScore, AilStatus, AuthoringIntelligence,
    DomainAnalysis, FatigueAnalysis, RecommendationLevel, SpectralClarityAnalysis, VoiceEfficiency,
    VolatilityAlignment,
};
pub use crate::core::config::AurexisConfig;
pub use crate::core::engine::AurexisEngine;
pub use crate::core::parameter_map::DeterministicParameterMap;
pub use crate::core::state::AurexisState;
pub use crate::drc::{
    CertificationChain, CertificationGate, CertificationReport, CertificationResult,
    CertificationStatus, ConfigBundle, DeterministicReplayCore, EnvelopeResult, EnvelopeViolation,
    EnvelopeViolationType, FluxManifest, FrameHash, ReplayResult, SafetyEnvelope, SafetyLimits,
    TraceEntry, TraceFormat, TraceMetadata, VersionLocks,
};
pub use crate::energy::{
    EnergyBudget, EnergyDomain, EnergyGovernor, GegCurveType, SessionMemory, SlotProfile,
    VoiceBudget,
};
pub use crate::gad::{
    BakeConfig, BakeError, BakeResult, BakeStep, BakeStepStatus, BakeToSlot, CanonicalEventBinding,
    DualTimeline, GadProject, GadProjectConfig, GadTrack, GadTrackLayout, GadTrackType,
    GameplayPosition, GameplayTimeline, MarkerType, MusicalPosition, MusicalTimeline, StemOutput,
    TempoChange, TimeSignature, TimelineMarker, TrackMetadata, TrackState, VoicePriorityClass,
};
pub use crate::priority::{
    DpmOutput, DynamicPriorityMatrix, EmotionalState, EventType, SurvivalAction, VoicePriority,
    VoiceSurvivalResult,
};
pub use crate::qa::{
    DomainResult, FatigueModelResult, MetricValidation, PbseResult, PreBakeSimulator,
    SimulationDomain, ValidationThresholds,
};
pub use crate::sam::{
    ArchetypeDefaults, ArchetypeProfile, AuthoringMode, ClarityControls, EnergyControls,
    MarketTarget, ParameterMapping, SlotArchetype, SmartAuthoringEngine, SmartAuthoringState,
    SmartControl, SmartControlGroup, SmartControlSet, SmartControlValue, StabilityControls,
    VolatilityRange, WizardStep,
};
pub use crate::spectral::{
    MaskingAction, MaskingResolver, MaskingStrategy, SciAdvanced, SpectralAllocationOutput,
    SpectralAllocator, SpectralAssignment, SpectralBand, SpectralRole,
};
pub use crate::sss::{
    AutoRegression, BurnTest, BurnTestConfig, BurnTestMetrics, BurnTestResult, ConfigDiff,
    ConfigDiffEngine, DiffEntry, DiffType, DriftMetric, IsolatedProject, ProjectConfig,
    ProjectIsolation, ProjectManifest, RegressionConfig, RegressionResult, RegressionRun,
    RegressionStatus, RiskLevel, StressScenario, TrendDirection,
};

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

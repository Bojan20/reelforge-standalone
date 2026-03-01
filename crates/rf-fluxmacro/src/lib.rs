// ============================================================================
// rf-fluxmacro — Deterministic Orchestration Engine
// ============================================================================
// Casino-grade Audio Automation System for slot audio pipelines.
// Unifies authoring, validation, QA simulation, manifest building,
// and release packaging into a single deterministic pipeline.
// ============================================================================

pub mod context;
pub mod error;
pub mod hash;
pub mod interpreter;
pub mod parser;
pub mod reporter;
pub mod rules;
pub mod security;
pub mod steps;
pub mod version;

// Re-export core types for convenience
pub use context::{
    GameMechanic, LogLevel, MacroContext, Platform, QaTestResult, ReportFormat, VolatilityLevel,
};
pub use error::FluxMacroError;
pub use interpreter::MacroInterpreter;
pub use parser::{parse_macro_file, parse_macro_string, MacroFile};
pub use steps::{MacroStep, StepRegistry, StepResult, StepStatus};

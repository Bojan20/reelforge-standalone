// ============================================================================
// rf-fluxmacro — Error Types
// ============================================================================
// FM-5: FluxMacroError enum — all error variants for the orchestration engine.
// ============================================================================

use std::path::PathBuf;

/// All errors that can occur during FluxMacro execution.
#[derive(Debug, thiserror::Error)]
pub enum FluxMacroError {
    // === Parse Errors ===
    #[error("failed to parse macro file: {0}")]
    ParseError(String),

    #[error("invalid macro version '{version}': expected semver")]
    InvalidVersion { version: String },

    #[error("unknown volatility level '{0}' — expected low/medium/high/extreme")]
    UnknownVolatility(String),

    #[error("unknown platform '{0}' — expected mobile/desktop/cabinet/webgl")]
    UnknownPlatform(String),

    #[error("unknown mechanic '{0}'")]
    UnknownMechanic(String),

    #[error("unknown report format '{0}' — expected html/json/markdown/all")]
    UnknownReportFormat(String),

    // === Step Errors ===
    #[error("step not found: '{0}'")]
    StepNotFound(String),

    #[error("step '{step}' failed: {reason}")]
    StepFailed { step: String, reason: String },

    #[error("step '{step}' validation failed: {reason}")]
    StepValidationFailed { step: String, reason: String },

    #[error("step '{step}' precondition not met: {precondition}")]
    PreconditionNotMet { step: String, precondition: String },

    // === File I/O Errors ===
    #[error("failed to read file {0}: {1}")]
    FileRead(PathBuf, #[source] std::io::Error),

    #[error("failed to write file {0}: {1}")]
    FileWrite(PathBuf, #[source] std::io::Error),

    #[error("failed to create directory {0}: {1}")]
    DirectoryCreate(PathBuf, #[source] std::io::Error),

    // === Security Errors ===
    #[error("path traversal detected: '{path}' escapes sandbox '{sandbox}'")]
    PathTraversal { path: PathBuf, sandbox: PathBuf },

    #[error("invalid game ID '{0}': must match [a-zA-Z0-9_-]{{1,64}}")]
    InvalidGameId(String),

    #[error("invalid input: {0}")]
    InvalidInput(String),

    // === Rule Errors ===
    #[error("failed to load rules from {path}: {reason}")]
    RuleLoadError { path: PathBuf, reason: String },

    #[error("naming rule violation: {0}")]
    NamingViolation(String),

    // === QA Errors ===
    #[error("QA gate failed: {passed}/{total} tests passed")]
    QaGateFailed { passed: usize, total: usize },

    #[error("determinism check failed: hash mismatch on run {run_index}")]
    DeterminismFailed { run_index: usize },

    // === Execution Errors ===
    #[error("macro execution cancelled by user")]
    Cancelled,

    #[error("macro execution timed out after {0}ms")]
    Timeout(u64),

    // === Serialization ===
    #[error("serialization error: {0}")]
    Serialization(String),

    // === Catch-all ===
    #[error("{0}")]
    Other(String),
}

impl From<std::io::Error> for FluxMacroError {
    fn from(e: std::io::Error) -> Self {
        Self::Other(format!("I/O error: {e}"))
    }
}

impl From<serde_json::Error> for FluxMacroError {
    fn from(e: serde_json::Error) -> Self {
        Self::Serialization(format!("JSON: {e}"))
    }
}

impl From<serde_yml::Error> for FluxMacroError {
    fn from(e: serde_yml::Error) -> Self {
        Self::ParseError(format!("YAML: {e}"))
    }
}

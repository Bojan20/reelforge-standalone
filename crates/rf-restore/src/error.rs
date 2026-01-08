//! Error types for audio restoration

use thiserror::Error;

/// Restoration error types
#[derive(Error, Debug)]
pub enum RestoreError {
    /// Invalid configuration
    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    /// Processing error
    #[error("Processing error: {0}")]
    ProcessingError(String),

    /// Buffer size mismatch
    #[error("Buffer size mismatch: expected {expected}, got {got}")]
    BufferMismatch { expected: usize, got: usize },

    /// Analysis failed
    #[error("Analysis failed: {0}")]
    AnalysisFailed(String),

    /// Invalid sample rate
    #[error("Invalid sample rate: {0}")]
    InvalidSampleRate(u32),

    /// Internal error
    #[error("Internal error: {0}")]
    Internal(String),
}

/// Result type for restoration operations
pub type RestoreResult<T> = Result<T, RestoreError>;

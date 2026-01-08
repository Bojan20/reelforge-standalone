//! Error types for mastering engine

use thiserror::Error;

/// Mastering error type
#[derive(Error, Debug)]
pub enum MasterError {
    /// Invalid audio format
    #[error("Invalid audio format: {0}")]
    InvalidFormat(String),

    /// Buffer size mismatch
    #[error("Buffer size mismatch: expected {expected}, got {got}")]
    BufferMismatch {
        /// Expected size
        expected: usize,
        /// Actual size
        got: usize,
    },

    /// Invalid parameter value
    #[error("Invalid parameter: {0}")]
    InvalidParameter(String),

    /// Reference track error
    #[error("Reference track error: {0}")]
    ReferenceError(String),

    /// Processing error
    #[error("Processing error: {0}")]
    ProcessingError(String),

    /// Analysis error
    #[error("Analysis error: {0}")]
    AnalysisError(String),
}

/// Result type for mastering operations
pub type MasterResult<T> = Result<T, MasterError>;

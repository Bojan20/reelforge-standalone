//! Error types for offline processing

use thiserror::Error;

/// Offline processing errors
#[derive(Error, Debug)]
pub enum OfflineError {
    #[error("Input file not found: {0}")]
    InputNotFound(String),

    #[error("Failed to read audio file: {0}")]
    ReadError(String),

    #[error("Failed to write output file: {0}")]
    WriteError(String),

    #[error("Unsupported format: {0}")]
    UnsupportedFormat(String),

    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("Processing failed: {0}")]
    ProcessingFailed(String),

    #[error("Job cancelled")]
    Cancelled,

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("DSP error: {0}")]
    Dsp(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("Encoding error: {0}")]
    EncodingError(String),

    #[error("Sample rate conversion failed: {0}")]
    SampleRateConversion(String),

    #[error("Channel mismatch: expected {expected}, got {actual}")]
    ChannelMismatch { expected: usize, actual: usize },
}

/// Result type for offline operations
pub type OfflineResult<T> = Result<T, OfflineError>;

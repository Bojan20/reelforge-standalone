//! Error types for ML processing

use thiserror::Error;

/// ML processing error types
#[derive(Error, Debug)]
pub enum MlError {
    /// Model file not found
    #[error("Model not found: {path}")]
    ModelNotFound { path: String },

    /// Model loading failed
    #[error("Failed to load model: {reason}")]
    ModelLoadFailed { reason: String },

    /// Inference failed
    #[error("Inference failed: {reason}")]
    InferenceFailed { reason: String },

    /// Invalid input shape
    #[error("Invalid input shape: expected {expected}, got {got}")]
    InvalidInputShape { expected: String, got: String },

    /// Invalid output shape
    #[error("Invalid output shape: expected {expected}, got {got}")]
    InvalidOutputShape { expected: String, got: String },

    /// Processing failed
    #[error("Processing failed: {0}")]
    ProcessingFailed(String),

    /// Invalid sample rate
    #[error("Invalid sample rate: expected {expected}, got {got}")]
    InvalidSampleRate { expected: u32, got: u32 },

    /// Buffer too small
    #[error("Buffer too small: need {needed} samples, got {got}")]
    BufferTooSmall { needed: usize, got: usize },

    /// GPU not available
    #[error("GPU acceleration not available: {reason}")]
    GpuNotAvailable { reason: String },

    /// ONNX Runtime error
    #[error("ONNX Runtime error: {0}")]
    OrtError(String),

    /// Tract error
    #[error("Tract error: {0}")]
    TractError(String),

    /// IO error
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    /// Channel count mismatch
    #[error("Channel count mismatch: expected {expected}, got {got}")]
    ChannelMismatch { expected: usize, got: usize },

    /// Processing timeout
    #[error("Processing timeout after {timeout_ms}ms")]
    Timeout { timeout_ms: u64 },

    /// Internal error
    #[error("Internal error: {0}")]
    Internal(String),
}

/// Result type for ML operations
pub type MlResult<T> = Result<T, MlError>;

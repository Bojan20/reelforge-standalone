//! Error types for spatial audio processing

use thiserror::Error;

/// Spatial audio error types
#[derive(Error, Debug)]
pub enum SpatialError {
    /// Invalid channel count
    #[error("Invalid channel count: expected {expected}, got {got}")]
    InvalidChannelCount { expected: usize, got: usize },

    /// Invalid Ambisonic order
    #[error("Invalid Ambisonic order: {0} (max supported: 7)")]
    InvalidAmbisonicOrder(usize),

    /// Invalid speaker layout
    #[error("Invalid speaker layout: {0}")]
    InvalidLayout(String),

    /// HRTF not loaded
    #[error("HRTF not loaded: {0}")]
    HrtfNotLoaded(String),

    /// SOFA file error
    #[error("SOFA file error: {0}")]
    SofaError(String),

    /// Processing error
    #[error("Processing error: {0}")]
    ProcessingError(String),

    /// Buffer size mismatch
    #[error("Buffer size mismatch: expected {expected}, got {got}")]
    BufferSizeMismatch { expected: usize, got: usize },

    /// Invalid position
    #[error("Invalid position: {0}")]
    InvalidPosition(String),

    /// IO error
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    /// Object not found
    #[error("Object not found: {0}")]
    ObjectNotFound(u32),

    /// Maximum objects exceeded
    #[error("Maximum objects exceeded: {max}")]
    MaxObjectsExceeded { max: usize },
}

/// Result type for spatial operations
pub type SpatialResult<T> = Result<T, SpatialError>;

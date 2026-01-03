//! Error types for ReelForge

use thiserror::Error;

/// Core error type
#[derive(Error, Debug)]
pub enum RfError {
    #[error("Audio error: {0}")]
    Audio(String),

    #[error("DSP error: {0}")]
    Dsp(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Invalid parameter: {0}")]
    InvalidParam(String),

    #[error("Invalid sample rate: {0}")]
    InvalidSampleRate(u32),

    #[error("Buffer underrun")]
    BufferUnderrun,

    #[error("Buffer overrun")]
    BufferOverrun,

    #[error("Plugin error: {0}")]
    Plugin(String),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("State error: {0}")]
    State(String),
}

/// Result type alias
pub type RfResult<T> = Result<T, RfError>;

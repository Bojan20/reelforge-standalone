//! Audio error types

use thiserror::Error;

#[derive(Error, Debug)]
pub enum AudioError {
    #[error("No audio device found")]
    NoDevice,

    #[error("Device not found: {0}")]
    DeviceNotFound(String),

    #[error("Failed to get device config: {0}")]
    ConfigError(String),

    #[error("Failed to build stream: {0}")]
    StreamBuildError(String),

    #[error("Stream error: {0}")]
    StreamError(String),

    #[error("Unsupported sample rate: {0}")]
    UnsupportedSampleRate(u32),

    #[error("Unsupported buffer size: {0}")]
    UnsupportedBufferSize(u32),

    #[error("Backend error: {0}")]
    BackendError(String),
}

pub type AudioResult<T> = Result<T, AudioError>;

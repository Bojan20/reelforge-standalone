//! Plugin hosting error types

use thiserror::Error;

#[derive(Error, Debug)]
pub enum PluginError {
    #[error("Plugin not found: {0}")]
    NotFound(String),

    #[error("Invalid plugin format: {0}")]
    InvalidFormat(String),

    #[error("Failed to load plugin: {0}")]
    LoadError(String),

    #[error("Plugin crashed: {0}")]
    Crashed(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Cache error: {0}")]
    CacheError(String),

    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Plugin timeout")]
    Timeout,

    #[error("Plugin validation failed: {0}")]
    ValidationFailed(String),

    #[error("Unsupported plugin format: {0}")]
    UnsupportedFormat(String),

    #[error("Plugin instance not found: {0}")]
    InstanceNotFound(u64),

    #[error("Preset not found: {0}")]
    PresetNotFound(usize),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Plugin initialization failed: {0}")]
    InitError(String),

    #[error("Plugin processing error: {0}")]
    ProcessError(String),
}

pub type PluginResult<T> = Result<T, PluginError>;

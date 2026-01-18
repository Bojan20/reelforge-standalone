//! File I/O error types

use thiserror::Error;

#[derive(Error, Debug)]
pub enum FileError {
    #[error("File not found: {0}")]
    NotFound(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Unsupported format: {0}")]
    UnsupportedFormat(String),

    #[error("Invalid file: {0}")]
    InvalidFile(String),

    #[error("Decode error: {0}")]
    DecodeError(String),

    #[error("Encode error: {0}")]
    EncodeError(String),

    #[error("Write error: {0}")]
    WriteError(String),

    #[error("WAV error: {0}")]
    WavError(String),

    #[error("Project error: {0}")]
    ProjectError(String),

    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Recording error: {0}")]
    RecordingError(String),
}

pub type FileResult<T> = Result<T, FileError>;

impl From<hound::Error> for FileError {
    fn from(err: hound::Error) -> Self {
        FileError::WavError(err.to_string())
    }
}

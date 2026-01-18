//! Error types for pitch engine

use thiserror::Error;

/// Pitch engine errors
#[derive(Debug, Error)]
pub enum PitchError {
    /// Input too short for analysis
    #[error("Input too short: {0} samples, need at least {1}")]
    InputTooShort(usize, usize),

    /// Invalid sample rate
    #[error("Invalid sample rate: {0}")]
    InvalidSampleRate(u32),

    /// Invalid frequency range
    #[error("Invalid frequency range: {min} - {max} Hz")]
    InvalidFrequencyRange { min: f32, max: f32 },

    /// No pitch detected
    #[error("No pitch detected in signal")]
    NoPitchDetected,

    /// Voice limit exceeded
    #[error("Maximum voices exceeded: {0}")]
    VoiceLimitExceeded(usize),

    /// Invalid scale
    #[error("Invalid scale: {0}")]
    InvalidScale(String),

    /// Synthesis error
    #[error("Synthesis error: {0}")]
    SynthesisError(String),

    /// FFT error
    #[error("FFT error: {0}")]
    FftError(String),
}

/// Result type for pitch operations
pub type PitchResult<T> = Result<T, PitchError>;

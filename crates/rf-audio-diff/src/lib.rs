//! # rf-audio-diff
//!
//! FFT-based spectral audio comparison tool for regression testing.
//!
//! ## Features
//!
//! - **Spectral Analysis**: FFT-based frequency domain comparison
//! - **Time Domain**: Sample-by-sample difference analysis
//! - **Perceptual Metrics**: A-weighted, loudness-based comparison
//! - **Golden File Support**: Compare against reference audio files
//! - **Report Generation**: JSON and human-readable diff reports
//!
//! ## Example
//!
//! ```rust,ignore
//! use rf_audio_diff::{AudioDiff, DiffConfig, DiffResult};
//!
//! let config = DiffConfig::default();
//! let result = AudioDiff::compare("reference.wav", "test.wav", &config)?;
//!
//! if result.is_pass() {
//!     println!("Audio matches within tolerance");
//! } else {
//!     println!("Differences found: {:?}", result.summary());
//! }
//! ```

pub mod analysis;
pub mod config;
pub mod determinism;
pub mod diff;
pub mod golden;
pub mod loader;
pub mod metrics;
pub mod quality_gates;
pub mod report;
pub mod spectral;

pub use analysis::AudioAnalysis;
pub use config::DiffConfig;
pub use determinism::{
    check_determinism, DeterminismConfig, DeterminismResult, DeterminismValidator,
};
pub use diff::{AudioDiff, DiffResult};
pub use golden::{GoldenBatchResult, GoldenCompareResult, GoldenMetadata, GoldenStore};
pub use metrics::*;
pub use quality_gates::{QualityGateConfig, QualityGateResult, QualityGateRunner};
pub use report::DiffReport;

use thiserror::Error;

/// Errors that can occur during audio diff operations
#[derive(Error, Debug)]
pub enum AudioDiffError {
    #[error("Failed to load audio file: {0}")]
    LoadError(String),

    #[error("Sample rate mismatch: reference={0}Hz, test={1}Hz")]
    SampleRateMismatch(u32, u32),

    #[error("Channel count mismatch: reference={0}, test={1}")]
    ChannelMismatch(usize, usize),

    #[error("Duration mismatch: reference={0:.3}s, test={1:.3}s (tolerance={2:.3}s)")]
    DurationMismatch(f64, f64, f64),

    #[error("FFT error: {0}")]
    FftError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Invalid configuration: {0}")]
    ConfigError(String),
}

pub type Result<T> = std::result::Result<T, AudioDiffError>;

/// Quick comparison with default settings
pub fn quick_compare(reference_path: &str, test_path: &str) -> Result<DiffResult> {
    AudioDiff::compare(reference_path, test_path, &DiffConfig::default())
}

/// Check if two audio files match within default tolerances
pub fn files_match(reference_path: &str, test_path: &str) -> Result<bool> {
    Ok(quick_compare(reference_path, test_path)?.is_pass())
}

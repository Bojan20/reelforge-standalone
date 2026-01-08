//! Audio source separation (stem separation)
//!
//! State-of-the-art music source separation using HTDemucs v4:
//! - 4 stems: drums, bass, vocals, other
//! - 6 stems: + piano, guitar (htdemucs_6s)
//! - Hybrid Transformer architecture for SOTA quality
//! - SDR > 9.0 dB on MUSDB18 benchmark
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_ml::separation::{HTDemucs, StemType, SeparationConfig};
//!
//! let config = SeparationConfig::high_quality();
//! let mut separator = HTDemucs::new("models/htdemucs.onnx", config)?;
//! let stems = separator.separate(&audio, 2, 44100)?;
//!
//! let vocals = stems.get(StemType::Vocals).unwrap();
//! let instrumental = stems.instrumental(); // Everything except vocals
//! let karaoke = stems.karaoke(); // Drums + Bass + Other
//! ```

mod htdemucs;
mod config;
mod stems;

pub use htdemucs::{HTDemucs, HTDemucsConfig, create_htdemucs_4stem, create_htdemucs_6stem, create_htdemucs_ultra};
pub use config::{SeparationConfig, SeparationQuality};
pub use stems::{StemType, StemOutput, StemCollection};

use crate::error::MlResult;

/// Common trait for source separators
pub trait SourceSeparator: Send + Sync {
    /// Separate audio into stems
    ///
    /// # Arguments
    /// * `audio` - Interleaved audio samples
    /// * `channels` - Number of audio channels (1 or 2)
    /// * `sample_rate` - Sample rate in Hz
    ///
    /// # Returns
    /// Collection of separated stems
    fn separate(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<StemCollection>;

    /// Get available stem types for this separator
    fn available_stems(&self) -> &[StemType];

    /// Get model name/version
    fn model_name(&self) -> &str;

    /// Check if real-time processing is supported
    fn supports_realtime(&self) -> bool;

    /// Estimate memory usage for given audio duration
    fn estimated_memory_mb(&self, duration_secs: f32) -> f32;
}

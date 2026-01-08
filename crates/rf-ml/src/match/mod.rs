//! EQ Matching module
//!
//! Transfer spectral characteristics from reference audio to target:
//! - Neural spectral matching
//! - Multi-band gain optimization
//! - Perceptual weighting (A-weighting, ITU-R 468)
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_ml::r#match::{EqMatcher, MatchConfig};
//!
//! let config = MatchConfig::default();
//! let mut matcher = EqMatcher::new(config)?;
//!
//! // Analyze reference
//! matcher.set_reference(&reference_audio)?;
//!
//! // Get EQ curve to match target to reference
//! let eq_curve = matcher.compute_match(&target_audio)?;
//! ```

mod spectral;
mod config;
mod curve;

pub use spectral::SpectralMatcher;
pub use config::{MatchConfig, MatchMode, MatchWeighting};
pub use curve::{EqCurve, FrequencyBand};

use crate::error::MlResult;

/// EQ matching result
#[derive(Debug, Clone)]
pub struct MatchResult {
    /// EQ curve to apply
    pub eq_curve: EqCurve,

    /// Match quality score (0.0 - 1.0)
    pub quality: f32,

    /// Frequency response error in dB
    pub error_db: f32,

    /// Perceptual difference score
    pub perceptual_diff: f32,
}

/// Common trait for EQ matchers
pub trait EqMatcher: Send + Sync {
    /// Set reference audio for matching
    fn set_reference(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<()>;

    /// Compute EQ curve to match target to reference
    fn compute_match(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<MatchResult>;

    /// Get current reference spectrum
    fn reference_spectrum(&self) -> Option<&[f32]>;

    /// Reset matcher state
    fn reset(&mut self);

    /// Get number of EQ bands
    fn num_bands(&self) -> usize;
}

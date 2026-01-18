//! Speech enhancement module
//!
//! Ultra-low latency speech enhancement using:
//! - aTENNuate: State-Space Models (SSM) for 5ms latency
//! - FRCRN: Full-band and sub-band fusion
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_ml::enhance::{ATENNuate, EnhanceConfig};
//!
//! let config = EnhanceConfig::realtime();
//! let mut enhancer = ATENNuate::new("models/attenuate.onnx", config)?;
//!
//! // Process frame-by-frame (5ms latency)
//! let enhanced = enhancer.process_frame(&noisy_frame)?;
//! ```

mod attenuate;
mod config;
mod frcrn;

pub use attenuate::ATENNuate;
pub use config::{EnhanceConfig, EnhanceMode};
pub use frcrn::FRCRN;

use crate::buffer::AudioFrame;
use crate::error::MlResult;

/// Common trait for speech enhancers
pub trait SpeechEnhancer: Send + Sync {
    /// Process single frame (real-time capable)
    fn process_frame(&mut self, input: &AudioFrame) -> MlResult<AudioFrame>;

    /// Process entire audio buffer (batch mode)
    fn process_batch(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<Vec<f32>>;

    /// Reset internal state
    fn reset(&mut self);

    /// Get latency in samples
    fn latency_samples(&self) -> usize;

    /// Get latency in milliseconds
    fn latency_ms(&self) -> f64;

    /// Get supported sample rate
    fn sample_rate(&self) -> u32;

    /// Set enhancement strength (0.0 - 1.0)
    fn set_strength(&mut self, strength: f32);

    /// Get current strength
    fn strength(&self) -> f32;

    /// Check if GPU accelerated
    fn is_gpu_accelerated(&self) -> bool;
}

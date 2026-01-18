//! Neural audio denoising
//!
//! State-of-the-art neural network based noise reduction:
//! - DeepFilterNet3: Real-time speech enhancement with ERB processing
//! - FRCRN: Full-band and sub-band fusion for robust denoising
//! - Spectral gating: Classical noise gate with learned threshold
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_ml::denoise::{DeepFilterNet, DenoiseConfig};
//!
//! let config = DenoiseConfig::default();
//! let mut denoiser = DeepFilterNet::new("models/deepfilternet3.onnx", config)?;
//!
//! // Process frame-by-frame for real-time
//! let clean = denoiser.process_frame(&noisy_frame)?;
//! ```

mod config;
mod deep_filter;
mod spectral_gate;

pub use config::{DenoiseConfig, DenoiseMode, NoiseProfile};
pub use deep_filter::DeepFilterNet;
pub use spectral_gate::SpectralGate;

use crate::buffer::AudioFrame;
use crate::error::MlResult;

/// Common trait for all denoisers
pub trait Denoiser: Send + Sync {
    /// Process single frame
    fn process_frame(&mut self, input: &AudioFrame) -> MlResult<AudioFrame>;

    /// Reset internal state
    fn reset(&mut self);

    /// Get latency in samples
    fn latency_samples(&self) -> usize;

    /// Get supported sample rate
    fn sample_rate(&self) -> u32;

    /// Learn noise profile from sample
    fn learn_noise(&mut self, noise_sample: &[f32]) -> MlResult<()>;

    /// Set reduction amount (0.0 - 1.0)
    fn set_reduction(&mut self, amount: f32);

    /// Get current reduction amount
    fn reduction(&self) -> f32;
}

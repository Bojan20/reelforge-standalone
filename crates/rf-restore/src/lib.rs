//! ReelForge Audio Restoration Suite
//!
//! Professional-grade audio repair and restoration:
//!
//! ## Declipping
//! - Soft clipping detection
//! - Hard clipping reconstruction using spline interpolation
//! - Psychoacoustic masking-aware processing
//!
//! ## Dehumming
//! - Multi-harmonic hum removal (50/60 Hz + harmonics)
//! - Adaptive notch filters
//! - Phase-locked detection
//!
//! ## Declick/Decrackle
//! - Impulsive noise detection (clicks, pops)
//! - Interpolation-based repair
//! - Vinyl crackle removal
//!
//! ## Spectral Denoise
//! - Noise profile learning
//! - Spectral subtraction with psychoacoustic weighting
//! - Artifact-free processing
//!
//! ## De-reverb
//! - Reverb suppression
//! - Early reflections removal
//! - Tail reduction

#![warn(missing_docs)]

pub mod declip;
pub mod declick;
pub mod dehum;
pub mod denoise;
pub mod dereverb;

mod error;
mod analysis;

pub use error::{RestoreError, RestoreResult};

use serde::{Deserialize, Serialize};

/// Restoration module configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestoreConfig {
    /// Sample rate
    pub sample_rate: u32,
    /// Processing block size
    pub block_size: usize,
    /// Overlap ratio (0.5 = 50%)
    pub overlap: f32,
    /// Quality level (0.0 = fast, 1.0 = best)
    pub quality: f32,
}

impl Default for RestoreConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            block_size: 2048,
            overlap: 0.75,
            quality: 0.8,
        }
    }
}

/// Common restoration processor trait
pub trait Restorer: Send + Sync {
    /// Process audio block
    fn process(&mut self, input: &[f32], output: &mut [f32]) -> RestoreResult<()>;

    /// Reset internal state
    fn reset(&mut self);

    /// Get latency in samples
    fn latency_samples(&self) -> usize;

    /// Get processing name
    fn name(&self) -> &str;
}

/// Restoration analysis result
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AnalysisResult {
    /// Detected clipping percentage
    pub clipping_percent: f32,
    /// Detected click count (per second)
    pub clicks_per_second: f32,
    /// Hum fundamental frequency (Hz)
    pub hum_frequency: Option<f32>,
    /// Hum level (dB)
    pub hum_level_db: f32,
    /// Estimated noise floor (dB)
    pub noise_floor_db: f32,
    /// Reverb tail estimation (seconds)
    pub reverb_tail_seconds: f32,
    /// Overall quality score (0-100)
    pub quality_score: f32,
    /// Suggested restoration modules
    pub suggestions: Vec<String>,
}

/// Combined restoration pipeline
pub struct RestorationPipeline {
    /// Modules in processing order
    modules: Vec<Box<dyn Restorer>>,
    /// Pipeline configuration
    config: RestoreConfig,
    /// Is active
    active: bool,
}

impl RestorationPipeline {
    /// Create new pipeline
    pub fn new(config: RestoreConfig) -> Self {
        Self {
            modules: Vec::new(),
            config,
            active: true,
        }
    }

    /// Add restoration module
    pub fn add_module(&mut self, module: Box<dyn Restorer>) {
        self.modules.push(module);
    }

    /// Set active state
    pub fn set_active(&mut self, active: bool) {
        self.active = active;
    }

    /// Process audio through pipeline
    pub fn process(&mut self, input: &[f32], output: &mut [f32]) -> RestoreResult<()> {
        if !self.active || self.modules.is_empty() {
            output.copy_from_slice(input);
            return Ok(());
        }

        let mut buffer_a = input.to_vec();
        let mut buffer_b = vec![0.0f32; input.len()];

        for (i, module) in self.modules.iter_mut().enumerate() {
            if i % 2 == 0 {
                module.process(&buffer_a, &mut buffer_b)?;
            } else {
                module.process(&buffer_b, &mut buffer_a)?;
            }
        }

        // Copy final result
        if self.modules.len() % 2 == 1 {
            output.copy_from_slice(&buffer_b);
        } else {
            output.copy_from_slice(&buffer_a);
        }

        Ok(())
    }

    /// Get total latency
    pub fn total_latency(&self) -> usize {
        self.modules.iter().map(|m| m.latency_samples()).sum()
    }

    /// Reset all modules
    pub fn reset(&mut self) {
        for module in &mut self.modules {
            module.reset();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = RestoreConfig::default();
        assert_eq!(config.sample_rate, 48000);
        assert_eq!(config.block_size, 2048);
    }

    #[test]
    fn test_pipeline_passthrough() {
        let config = RestoreConfig::default();
        let mut pipeline = RestorationPipeline::new(config);

        let input = vec![0.5f32; 1000];
        let mut output = vec![0.0f32; 1000];

        pipeline.process(&input, &mut output).unwrap();

        // Should be passthrough with no modules
        assert_eq!(input, output);
    }
}

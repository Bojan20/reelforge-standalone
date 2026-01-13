//! aTENNuate - State-Space Model Speech Enhancement
//!
//! Ultra-low latency speech enhancement using State-Space Models (SSM).
//! Based on the Mamba/S4 architecture for efficient sequence modeling.
//!
//! ## Features
//! - 5ms latency at 48kHz
//! - Efficient SSM for long-range dependencies
//! - Frequency-domain processing with learned masks
//! - GPU accelerated with TensorRT/CoreML

use std::path::Path;
use std::sync::Arc;

use ndarray::{s, Array2, Array3, Axis};
use num_complex::Complex32;
use realfft::{ComplexToReal, RealFftPlanner, RealToComplex};

use super::config::EnhanceConfig;
use super::SpeechEnhancer;
use crate::buffer::AudioFrame;
use crate::error::{MlError, MlResult};
use crate::inference::{InferenceConfig, InferenceEngine};

/// State-Space Model state
#[derive(Clone)]
struct SSMState {
    /// Hidden state [batch, state_dim]
    hidden: Array2<f32>,
    /// Previous input for residual
    prev_input: Vec<f32>,
}

impl SSMState {
    fn new(state_dim: usize) -> Self {
        Self {
            hidden: Array2::zeros((1, state_dim)),
            prev_input: Vec::new(),
        }
    }

    fn reset(&mut self) {
        self.hidden.fill(0.0);
        self.prev_input.clear();
    }
}

/// aTENNuate speech enhancer
pub struct ATENNuate {
    /// SSM model
    model: InferenceEngine,

    /// Configuration
    config: EnhanceConfig,

    /// FFT forward transform
    fft_forward: Arc<dyn RealToComplex<f32>>,

    /// FFT inverse transform
    fft_inverse: Arc<dyn ComplexToReal<f32>>,

    /// Window function (Hann)
    window: Vec<f32>,

    /// Synthesis window
    synthesis_window: Vec<f32>,

    /// SSM state
    state: SSMState,

    /// Input buffer for overlap-add
    input_buffer: Vec<f32>,

    /// Output buffer for overlap-add
    output_buffer: Vec<f32>,

    /// Frame index
    frame_index: u64,

    /// Current strength setting
    strength: f32,

    /// Sample rate
    sample_rate: u32,
}

impl ATENNuate {
    /// Create new aTENNuate enhancer
    pub fn new<P: AsRef<Path>>(model_path: P, config: EnhanceConfig) -> MlResult<Self> {
        let path = model_path.as_ref();

        // Create inference engine
        let inference_config = InferenceConfig {
            use_gpu: config.use_gpu,
            ..Default::default()
        };

        let model = InferenceEngine::new(path, inference_config)?;

        // Create FFT planners
        let fft_size = config.frame_size * 2; // 2x frame for 50% overlap
        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Create analysis window (Hann)
        let window: Vec<f32> = (0..fft_size)
            .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / fft_size as f32).cos()))
            .collect();

        // Create synthesis window (complementary for perfect reconstruction)
        let synthesis_window = Self::create_synthesis_window(&window, config.frame_size);

        // Initialize SSM state
        let state = SSMState::new(config.ssm_order);

        Ok(Self {
            model,
            config: config.clone(),
            fft_forward,
            fft_inverse,
            window,
            synthesis_window,
            state,
            input_buffer: vec![0.0; config.frame_size * 2],
            output_buffer: vec![0.0; config.frame_size * 2],
            frame_index: 0,
            strength: config.strength,
            sample_rate: config.sample_rate,
        })
    }

    /// Create synthesis window for perfect reconstruction with OLA
    fn create_synthesis_window(analysis_window: &[f32], hop_size: usize) -> Vec<f32> {
        let size = analysis_window.len();
        let mut synthesis = vec![0.0f32; size];

        // Compute normalization factor for OLA
        let mut norm = vec![0.0f32; hop_size];
        let num_overlaps = size / hop_size;

        for shift in 0..num_overlaps {
            for i in 0..hop_size {
                let idx = shift * hop_size + i;
                if idx < size {
                    norm[i] += analysis_window[idx] * analysis_window[idx];
                }
            }
        }

        // Apply normalization
        for shift in 0..num_overlaps {
            for i in 0..hop_size {
                let idx = shift * hop_size + i;
                if idx < size && norm[i] > 1e-8 {
                    synthesis[idx] = analysis_window[idx] / norm[i];
                }
            }
        }

        synthesis
    }

    /// Compute STFT magnitude and phase
    fn stft_frame(&self, frame: &[f32]) -> MlResult<(Vec<f32>, Vec<f32>)> {
        let fft_size = self.window.len();
        let n_bins = fft_size / 2 + 1;

        // Apply window
        let mut windowed: Vec<f32> = frame
            .iter()
            .zip(self.window.iter())
            .map(|(&s, &w)| s * w)
            .collect();

        // Pad or truncate
        windowed.resize(fft_size, 0.0);

        // FFT
        let mut spectrum = vec![Complex32::new(0.0, 0.0); n_bins];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft_forward.get_scratch_len()];

        self.fft_forward
            .process_with_scratch(&mut windowed, &mut spectrum, &mut scratch)
            .map_err(|e| MlError::ProcessingFailed(format!("FFT failed: {}", e)))?;

        // Extract magnitude and phase
        let magnitude: Vec<f32> = spectrum.iter().map(|c| c.norm()).collect();
        let phase: Vec<f32> = spectrum.iter().map(|c| c.arg()).collect();

        Ok((magnitude, phase))
    }

    /// Reconstruct audio from magnitude and phase
    fn istft_frame(&self, magnitude: &[f32], phase: &[f32]) -> MlResult<Vec<f32>> {
        let n_bins = magnitude.len();
        let fft_size = (n_bins - 1) * 2;

        // Reconstruct complex spectrum
        let mut spectrum: Vec<Complex32> = magnitude
            .iter()
            .zip(phase.iter())
            .map(|(&m, &p)| Complex32::from_polar(m, p))
            .collect();

        // IFFT
        let mut output = vec![0.0f32; fft_size];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft_inverse.get_scratch_len()];

        self.fft_inverse
            .process_with_scratch(&mut spectrum, &mut output, &mut scratch)
            .map_err(|e| MlError::ProcessingFailed(format!("IFFT failed: {}", e)))?;

        // Normalize and apply synthesis window
        let norm = 1.0 / fft_size as f32;
        for (i, sample) in output.iter_mut().enumerate() {
            *sample *= norm * self.synthesis_window[i];
        }

        Ok(output)
    }

    /// Process magnitude through SSM model
    fn process_magnitude(&mut self, magnitude: &[f32]) -> MlResult<Vec<f32>> {
        let num_bands = magnitude.len();

        // Prepare input: [batch, bands, 1]
        let mut input = Array3::<f32>::zeros((1, num_bands, 1));
        for (i, &m) in magnitude.iter().enumerate() {
            input[[0, i, 0]] = m.ln().max(-10.0); // Log magnitude
        }

        // Concatenate with hidden state
        let _hidden_expanded = self.state.hidden.clone().insert_axis(Axis(2));

        // Run model (simplified - actual model would take both input and state)
        let input_2d = input.slice(s![0, .., 0]).to_owned();
        let output = self.model.run_array2(&input_2d.insert_axis(Axis(0)))?;

        // Extract mask and new hidden state
        // Output assumed to be [batch, bands] mask
        let mask: Vec<f32> = output.slice(s![0, ..]).iter().copied().collect();

        // Apply mask with strength control
        let enhanced: Vec<f32> = magnitude
            .iter()
            .zip(mask.iter())
            .map(|(&m, &mask_val)| {
                // Sigmoid activation for mask
                let mask_sigmoid = 1.0 / (1.0 + (-mask_val).exp());
                // Blend based on strength
                let blended_mask = 1.0 - self.strength + self.strength * mask_sigmoid;
                m * blended_mask
            })
            .collect();

        Ok(enhanced)
    }

    /// Apply voice preservation
    fn preserve_voice(&self, original: &[f32], enhanced: &[f32]) -> Vec<f32> {
        let preservation = self.config.voice_preservation;

        // Simple blend for voice preservation
        // In production, this would use a voice activity detector
        original
            .iter()
            .zip(enhanced.iter())
            .map(|(&o, &e)| {
                // Preserve more of original in voice frequencies (100Hz - 4kHz)
                // This is simplified - real implementation would be frequency-dependent
                o * preservation + e * (1.0 - preservation)
            })
            .collect()
    }
}

impl SpeechEnhancer for ATENNuate {
    fn process_frame(&mut self, input: &AudioFrame) -> MlResult<AudioFrame> {
        let frame_size = self.config.frame_size;
        let fft_size = self.window.len();

        // Handle mono/stereo
        let mono_input = input.to_mono();

        // Shift input buffer and add new samples
        let shift = frame_size.min(mono_input.len());
        self.input_buffer.copy_within(shift.., 0);
        let copy_start = fft_size - shift;
        for (i, &s) in mono_input.iter().take(shift).enumerate() {
            self.input_buffer[copy_start + i] = s;
        }

        // Process frame
        let (magnitude, phase) = self.stft_frame(&self.input_buffer)?;

        // Enhance magnitude through SSM
        let enhanced_magnitude = self.process_magnitude(&magnitude)?;

        // Apply voice preservation
        let preserved_magnitude = if self.config.voice_preservation > 0.0 {
            self.preserve_voice(&magnitude, &enhanced_magnitude)
        } else {
            enhanced_magnitude
        };

        // Reconstruct
        let reconstructed = self.istft_frame(&preserved_magnitude, &phase)?;

        // Overlap-add with output buffer
        for (i, &s) in reconstructed.iter().enumerate() {
            self.output_buffer[i] += s;
        }

        // Extract output frame
        let output_data: Vec<f32> = self.output_buffer[..frame_size].to_vec();

        // Shift output buffer
        self.output_buffer.copy_within(frame_size.., 0);
        for sample in self.output_buffer[fft_size - frame_size..].iter_mut() {
            *sample = 0.0;
        }

        self.frame_index += 1;

        // Return as mono or stereo based on input
        let output = if input.channels == 1 {
            AudioFrame::mono(output_data, input.sample_rate, self.frame_index)
        } else {
            // Duplicate to stereo
            let stereo_data: Vec<f32> = output_data.iter().flat_map(|&s| [s, s]).collect();
            AudioFrame::stereo(stereo_data, input.sample_rate, self.frame_index)
        };

        Ok(output)
    }

    fn process_batch(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<Vec<f32>> {
        // Convert to mono if needed
        let mono = if channels == 2 {
            audio
                .chunks(2)
                .map(|chunk| (chunk[0] + chunk.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect::<Vec<_>>()
        } else {
            audio.to_vec()
        };

        let frame_size = self.config.frame_size;
        let num_frames = mono.len().div_ceil(frame_size);

        let mut output = Vec::with_capacity(mono.len());
        self.reset();

        for i in 0..num_frames {
            let start = i * frame_size;
            let end = (start + frame_size).min(mono.len());

            // Create frame
            let mut frame_data = vec![0.0f32; frame_size];
            frame_data[..end - start].copy_from_slice(&mono[start..end]);

            let frame = AudioFrame::mono(frame_data, sample_rate, i as u64);

            // Process
            let processed = self.process_frame(&frame)?;

            // Collect output
            let valid_samples = end - start;
            output.extend_from_slice(&processed.data[..valid_samples]);
        }

        // Convert back to stereo if input was stereo
        if channels == 2 {
            Ok(output.iter().flat_map(|&s| [s, s]).collect())
        } else {
            Ok(output)
        }
    }

    fn reset(&mut self) {
        self.state.reset();
        self.input_buffer.fill(0.0);
        self.output_buffer.fill(0.0);
        self.frame_index = 0;
    }

    fn latency_samples(&self) -> usize {
        self.config.frame_size
    }

    fn latency_ms(&self) -> f64 {
        self.config.latency_ms()
    }

    fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    fn set_strength(&mut self, strength: f32) {
        self.strength = strength.clamp(0.0, 1.0);
    }

    fn strength(&self) -> f32 {
        self.strength
    }

    fn is_gpu_accelerated(&self) -> bool {
        self.model.is_gpu_accelerated()
    }
}

/// Create aTENNuate with realtime configuration
pub fn create_realtime<P: AsRef<Path>>(model_path: P) -> MlResult<ATENNuate> {
    ATENNuate::new(model_path, EnhanceConfig::realtime())
}

/// Create aTENNuate with quality configuration
pub fn create_quality<P: AsRef<Path>>(model_path: P) -> MlResult<ATENNuate> {
    ATENNuate::new(model_path, EnhanceConfig::quality())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_synthesis_window() {
        let window: Vec<f32> = (0..512)
            .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / 512.0).cos()))
            .collect();

        let synthesis = ATENNuate::create_synthesis_window(&window, 256);
        assert_eq!(synthesis.len(), 512);

        // Check that synthesis window is non-negative
        assert!(synthesis.iter().all(|&w| w >= 0.0));
    }

    #[test]
    fn test_config_latency() {
        let config = EnhanceConfig::realtime();
        assert!(config.latency_ms() <= 5.0);
    }
}

//! FRCRN - Full-band and Sub-band Fusion Complex Spectral Mapping
//!
//! High-quality speech enhancement using full-band and sub-band fusion.
//! Better quality than aTENNuate but higher latency.
//!
//! ## Architecture
//! - Full-band CRN for global spectral patterns
//! - Sub-band CRN for local frequency details
//! - Complex spectral mapping (magnitude + phase)
//! - Attention-based fusion

use std::path::Path;
use std::sync::Arc;

use ndarray::{Array2, Array3, s};
use num_complex::Complex32;
use realfft::{RealFftPlanner, RealToComplex, ComplexToReal};

use crate::error::{MlError, MlResult};
use crate::inference::{InferenceEngine, InferenceConfig};
use crate::buffer::AudioFrame;
use super::config::EnhanceConfig;
use super::SpeechEnhancer;

/// FRCRN configuration
#[derive(Debug, Clone)]
pub struct FRCRNConfig {
    /// FFT size for full-band processing
    pub fullband_fft: usize,

    /// FFT size for sub-band processing
    pub subband_fft: usize,

    /// Number of sub-bands
    pub num_subbands: usize,

    /// Frame shift (hop size)
    pub hop_size: usize,

    /// Sample rate
    pub sample_rate: u32,

    /// Use GPU
    pub use_gpu: bool,
}

impl Default for FRCRNConfig {
    fn default() -> Self {
        Self {
            fullband_fft: 512,
            subband_fft: 256,
            num_subbands: 4,
            hop_size: 256,
            sample_rate: 16000, // FRCRN typically operates at 16kHz
            use_gpu: true,
        }
    }
}

/// FRCRN state
struct FRCRNState {
    /// Encoder hidden state
    encoder_hidden: Array2<f32>,
    /// Decoder hidden state
    decoder_hidden: Array2<f32>,
    /// Previous frames for context
    context_frames: Vec<Array2<f32>>,
}

impl FRCRNState {
    fn new(hidden_size: usize) -> Self {
        Self {
            encoder_hidden: Array2::zeros((1, hidden_size)),
            decoder_hidden: Array2::zeros((1, hidden_size)),
            context_frames: Vec::new(),
        }
    }

    fn reset(&mut self) {
        self.encoder_hidden.fill(0.0);
        self.decoder_hidden.fill(0.0);
        self.context_frames.clear();
    }
}

/// FRCRN speech enhancer
pub struct FRCRN {
    /// Full-band model
    fullband_model: InferenceEngine,

    /// Sub-band model
    subband_model: InferenceEngine,

    /// Configuration
    config: FRCRNConfig,

    /// Enhance config
    enhance_config: EnhanceConfig,

    /// FFT for full-band
    fullband_fft_forward: Arc<dyn RealToComplex<f32>>,
    fullband_fft_inverse: Arc<dyn ComplexToReal<f32>>,

    /// FFT for sub-bands
    subband_fft_forward: Arc<dyn RealToComplex<f32>>,
    subband_fft_inverse: Arc<dyn ComplexToReal<f32>>,

    /// Analysis window
    window: Vec<f32>,

    /// Synthesis window
    synthesis_window: Vec<f32>,

    /// Model state
    state: FRCRNState,

    /// Input buffer
    input_buffer: Vec<f32>,

    /// Output buffer
    output_buffer: Vec<f32>,

    /// Current strength
    strength: f32,

    /// Frame counter
    frame_index: u64,
}

impl FRCRN {
    /// Create new FRCRN enhancer
    pub fn new<P: AsRef<Path>>(
        fullband_model_path: P,
        subband_model_path: P,
        config: EnhanceConfig,
    ) -> MlResult<Self> {
        let frcrn_config = FRCRNConfig::default();

        // Load models
        let inference_config = InferenceConfig {
            use_gpu: config.use_gpu,
            ..Default::default()
        };

        let fullband_model = InferenceEngine::new(&fullband_model_path, inference_config.clone())?;
        let subband_model = InferenceEngine::new(&subband_model_path, inference_config)?;

        // Create FFT planners
        let mut planner = RealFftPlanner::new();
        let fullband_fft_forward = planner.plan_fft_forward(frcrn_config.fullband_fft);
        let fullband_fft_inverse = planner.plan_fft_inverse(frcrn_config.fullband_fft);
        let subband_fft_forward = planner.plan_fft_forward(frcrn_config.subband_fft);
        let subband_fft_inverse = planner.plan_fft_inverse(frcrn_config.subband_fft);

        // Create windows
        let window: Vec<f32> = (0..frcrn_config.fullband_fft)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / frcrn_config.fullband_fft as f32).cos())
            })
            .collect();

        let synthesis_window = Self::create_synthesis_window(&window, frcrn_config.hop_size);

        // Initialize state
        let state = FRCRNState::new(256);

        Ok(Self {
            fullband_model,
            subband_model,
            config: frcrn_config.clone(),
            enhance_config: config.clone(),
            fullband_fft_forward,
            fullband_fft_inverse,
            subband_fft_forward,
            subband_fft_inverse,
            window,
            synthesis_window,
            state,
            input_buffer: vec![0.0; frcrn_config.fullband_fft],
            output_buffer: vec![0.0; frcrn_config.fullband_fft],
            strength: config.strength,
            frame_index: 0,
        })
    }

    /// Create synthesis window
    fn create_synthesis_window(analysis_window: &[f32], hop_size: usize) -> Vec<f32> {
        let size = analysis_window.len();
        let mut synthesis = analysis_window.to_vec();

        // Cola normalization
        let mut norm = vec![0.0f32; hop_size];
        let num_frames = size / hop_size;

        for frame in 0..num_frames {
            for i in 0..hop_size {
                let idx = frame * hop_size + i;
                if idx < size {
                    norm[i] += analysis_window[idx].powi(2);
                }
            }
        }

        for frame in 0..num_frames {
            for i in 0..hop_size {
                let idx = frame * hop_size + i;
                if idx < size && norm[i] > 1e-8 {
                    synthesis[idx] /= norm[i];
                }
            }
        }

        synthesis
    }

    /// Compute full-band STFT
    fn fullband_stft(&self, frame: &[f32]) -> MlResult<Vec<Complex32>> {
        let fft_size = self.config.fullband_fft;
        let n_bins = fft_size / 2 + 1;

        let mut windowed: Vec<f32> = frame
            .iter()
            .zip(self.window.iter())
            .map(|(&s, &w)| s * w)
            .collect();
        windowed.resize(fft_size, 0.0);

        let mut spectrum = vec![Complex32::new(0.0, 0.0); n_bins];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fullband_fft_forward.get_scratch_len()];

        self.fullband_fft_forward
            .process_with_scratch(&mut windowed, &mut spectrum, &mut scratch)
            .map_err(|e| MlError::ProcessingFailed(format!("Full-band FFT failed: {}", e)))?;

        Ok(spectrum)
    }

    /// Compute full-band ISTFT
    fn fullband_istft(&self, spectrum: &[Complex32]) -> MlResult<Vec<f32>> {
        let n_bins = spectrum.len();
        let fft_size = (n_bins - 1) * 2;

        let mut spectrum_copy = spectrum.to_vec();
        let mut output = vec![0.0f32; fft_size];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fullband_fft_inverse.get_scratch_len()];

        self.fullband_fft_inverse
            .process_with_scratch(&mut spectrum_copy, &mut output, &mut scratch)
            .map_err(|e| MlError::ProcessingFailed(format!("Full-band IFFT failed: {}", e)))?;

        // Normalize and window
        let norm = 1.0 / fft_size as f32;
        for (i, sample) in output.iter_mut().enumerate() {
            *sample *= norm * self.synthesis_window[i];
        }

        Ok(output)
    }

    /// Split into sub-bands
    fn split_subbands(&self, spectrum: &[Complex32]) -> Vec<Vec<Complex32>> {
        let n_bins = spectrum.len();
        let band_size = n_bins / self.config.num_subbands;

        (0..self.config.num_subbands)
            .map(|i| {
                let start = i * band_size;
                let end = if i == self.config.num_subbands - 1 {
                    n_bins
                } else {
                    (i + 1) * band_size
                };
                spectrum[start..end].to_vec()
            })
            .collect()
    }

    /// Merge sub-bands
    fn merge_subbands(&self, subbands: &[Vec<Complex32>]) -> Vec<Complex32> {
        subbands.iter().flat_map(|band| band.iter().copied()).collect()
    }

    /// Process through full-band model
    fn process_fullband(&mut self, spectrum: &[Complex32]) -> MlResult<Vec<Complex32>> {
        let n_bins = spectrum.len();

        // Prepare input: real and imaginary parts as separate channels
        let mut input = Array2::<f32>::zeros((2, n_bins));
        for (i, &c) in spectrum.iter().enumerate() {
            input[[0, i]] = c.re;
            input[[1, i]] = c.im;
        }

        // Run model
        let output = self.fullband_model.run_array2(&input)?;

        // Reconstruct complex spectrum
        let enhanced: Vec<Complex32> = (0..n_bins)
            .map(|i| Complex32::new(output[[0, i]], output[[1, i]]))
            .collect();

        Ok(enhanced)
    }

    /// Process through sub-band model
    fn process_subbands(&mut self, subbands: &[Vec<Complex32>]) -> MlResult<Vec<Vec<Complex32>>> {
        let mut enhanced_subbands = Vec::with_capacity(subbands.len());

        for band in subbands {
            let n_bins = band.len();

            // Prepare input
            let mut input = Array2::<f32>::zeros((2, n_bins));
            for (i, &c) in band.iter().enumerate() {
                input[[0, i]] = c.re;
                input[[1, i]] = c.im;
            }

            // Run model
            let output = self.subband_model.run_array2(&input)?;

            // Reconstruct
            let enhanced: Vec<Complex32> = (0..n_bins)
                .map(|i| Complex32::new(output[[0, i]], output[[1, i]]))
                .collect();

            enhanced_subbands.push(enhanced);
        }

        Ok(enhanced_subbands)
    }

    /// Fuse full-band and sub-band estimates
    fn fuse_estimates(
        &self,
        fullband: &[Complex32],
        subband: &[Complex32],
    ) -> Vec<Complex32> {
        // Attention-based fusion (simplified)
        // Weight based on magnitude confidence
        fullband
            .iter()
            .zip(subband.iter())
            .map(|(&f, &s)| {
                let f_mag = f.norm();
                let s_mag = s.norm();
                let total = f_mag + s_mag + 1e-8;

                // Weighted average based on magnitude (simplified attention)
                let f_weight = f_mag / total;
                let s_weight = s_mag / total;

                Complex32::new(
                    f.re * f_weight + s.re * s_weight,
                    f.im * f_weight + s.im * s_weight,
                )
            })
            .collect()
    }
}

impl SpeechEnhancer for FRCRN {
    fn process_frame(&mut self, input: &AudioFrame) -> MlResult<AudioFrame> {
        let hop_size = self.config.hop_size;
        let fft_size = self.config.fullband_fft;

        // Get mono input
        let mono = input.to_mono();

        // Shift buffer and add new samples
        let shift = hop_size.min(mono.len());
        self.input_buffer.copy_within(shift.., 0);
        let start = fft_size - shift;
        for (i, &s) in mono.iter().take(shift).enumerate() {
            self.input_buffer[start + i] = s;
        }

        // Full-band STFT
        let fullband_spectrum = self.fullband_stft(&self.input_buffer)?;

        // Process full-band
        let enhanced_fullband = self.process_fullband(&fullband_spectrum)?;

        // Split into sub-bands and process
        let subbands = self.split_subbands(&fullband_spectrum);
        let enhanced_subbands = self.process_subbands(&subbands)?;
        let merged_subband = self.merge_subbands(&enhanced_subbands);

        // Fuse estimates
        let fused = self.fuse_estimates(&enhanced_fullband, &merged_subband);

        // Apply strength
        let final_spectrum: Vec<Complex32> = fullband_spectrum
            .iter()
            .zip(fused.iter())
            .map(|(&orig, &enh)| {
                Complex32::new(
                    orig.re * (1.0 - self.strength) + enh.re * self.strength,
                    orig.im * (1.0 - self.strength) + enh.im * self.strength,
                )
            })
            .collect();

        // ISTFT
        let reconstructed = self.fullband_istft(&final_spectrum)?;

        // Overlap-add
        for (i, &s) in reconstructed.iter().enumerate() {
            self.output_buffer[i] += s;
        }

        // Extract output
        let output_data: Vec<f32> = self.output_buffer[..hop_size].to_vec();

        // Shift output buffer
        self.output_buffer.copy_within(hop_size.., 0);
        for sample in self.output_buffer[fft_size - hop_size..].iter_mut() {
            *sample = 0.0;
        }

        self.frame_index += 1;

        // Return frame
        if input.channels == 1 {
            Ok(AudioFrame::mono(output_data, input.sample_rate, self.frame_index))
        } else {
            let stereo: Vec<f32> = output_data.iter().flat_map(|&s| [s, s]).collect();
            Ok(AudioFrame::stereo(stereo, input.sample_rate, self.frame_index))
        }
    }

    fn process_batch(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<Vec<f32>> {
        // Convert to mono
        let mono = if channels == 2 {
            audio
                .chunks(2)
                .map(|c| (c[0] + c.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect::<Vec<_>>()
        } else {
            audio.to_vec()
        };

        let hop_size = self.config.hop_size;
        let num_frames = (mono.len() + hop_size - 1) / hop_size;

        let mut output = Vec::with_capacity(mono.len());
        self.reset();

        for i in 0..num_frames {
            let start = i * hop_size;
            let end = (start + hop_size).min(mono.len());

            let mut frame_data = vec![0.0f32; hop_size];
            frame_data[..end - start].copy_from_slice(&mono[start..end]);

            let frame = AudioFrame::mono(frame_data, sample_rate, i as u64);
            let processed = self.process_frame(&frame)?;

            let valid = end - start;
            output.extend_from_slice(&processed.data[..valid]);
        }

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
        self.config.fullband_fft
    }

    fn latency_ms(&self) -> f64 {
        self.config.fullband_fft as f64 / self.config.sample_rate as f64 * 1000.0
    }

    fn sample_rate(&self) -> u32 {
        self.config.sample_rate
    }

    fn set_strength(&mut self, strength: f32) {
        self.strength = strength.clamp(0.0, 1.0);
    }

    fn strength(&self) -> f32 {
        self.strength
    }

    fn is_gpu_accelerated(&self) -> bool {
        self.fullband_model.is_gpu_accelerated()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_defaults() {
        let config = FRCRNConfig::default();
        assert_eq!(config.sample_rate, 16000);
        assert_eq!(config.num_subbands, 4);
    }
}

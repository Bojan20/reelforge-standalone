//! DeepFilterNet3 neural denoiser
//!
//! State-of-the-art real-time speech enhancement using:
//! - ERB (Equivalent Rectangular Bandwidth) feature extraction
//! - Deep filtering in frequency domain
//! - Dual-path processing for efficient inference
//!
//! Reference: https://github.com/Rikorose/DeepFilterNet

use crate::buffer::{AudioFrame, FrameBuffer, OverlapAddBuffer};
use crate::denoise::{DenoiseConfig, Denoiser, NoiseProfile};
use crate::error::{MlError, MlResult};
use crate::inference::{InferenceConfig, InferenceEngine};

use ndarray::{Array1, Array2, Axis};
use num_complex::Complex32;
use realfft::{ComplexToReal, RealFftPlanner, RealToComplex};
use std::sync::Arc;

/// Number of ERB bands
const ERB_BANDS: usize = 32;

/// FFT size for DeepFilterNet
const FFT_SIZE: usize = 960;

/// Frame size (hop size for STFT)
const FRAME_SIZE: usize = 480;

/// Number of frequency bins
const NUM_BINS: usize = FFT_SIZE / 2 + 1;

/// DeepFilterNet3 neural denoiser
pub struct DeepFilterNet {
    /// ERB model (encoder + GRU + decoder)
    erb_model: InferenceEngine,

    /// Deep filter model
    df_model: InferenceEngine,

    /// Configuration
    config: DenoiseConfig,

    /// Sample rate
    sample_rate: u32,

    /// Input frame buffer
    input_buffer: FrameBuffer,

    /// Output overlap-add buffer
    output_buffer: OverlapAddBuffer,

    /// FFT planner (forward)
    fft_forward: Arc<dyn RealToComplex<f32>>,

    /// FFT planner (inverse)
    fft_inverse: Arc<dyn ComplexToReal<f32>>,

    /// Analysis window
    analysis_window: Vec<f32>,

    /// Synthesis window
    synthesis_window: Vec<f32>,

    /// ERB filterbank weights
    erb_fb: Array2<f32>,

    /// Inverse ERB filterbank weights
    erb_fb_inv: Array2<f32>,

    /// ERB GRU hidden state
    erb_hidden: Array2<f32>,

    /// DF GRU hidden state
    df_hidden: Array2<f32>,

    /// Previous enhanced spectrum (for DF)
    prev_spectrum: Vec<Complex32>,

    /// Noise profile (optional)
    noise_profile: Option<NoiseProfile>,

    /// Reduction amount
    reduction: f32,

    /// Frame counter
    frame_count: u64,
}

impl DeepFilterNet {
    /// Create new DeepFilterNet denoiser
    pub fn new(erb_model_path: &str, df_model_path: &str, config: DenoiseConfig) -> MlResult<Self> {
        let inference_config = InferenceConfig {
            providers: if config.use_gpu {
                vec![
                    crate::inference::ExecutionProvider::TensorRT,
                    crate::inference::ExecutionProvider::Cuda,
                    crate::inference::ExecutionProvider::CoreML,
                    crate::inference::ExecutionProvider::Cpu,
                ]
            } else {
                vec![crate::inference::ExecutionProvider::Cpu]
            },
            ..Default::default()
        };

        let erb_model = InferenceEngine::new(erb_model_path, inference_config.clone())?;
        let df_model = InferenceEngine::new(df_model_path, inference_config)?;

        let sample_rate = 48000;

        // Create FFT planners
        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(FFT_SIZE);
        let fft_inverse = planner.plan_fft_inverse(FFT_SIZE);

        // Create analysis window (sqrt-Hann for WOLA)
        let analysis_window: Vec<f32> = (0..FFT_SIZE)
            .map(|i| {
                let phase = std::f32::consts::PI * i as f32 / FFT_SIZE as f32;
                phase.sin()
            })
            .collect();

        // Synthesis window (same as analysis for sqrt-Hann WOLA)
        let synthesis_window = analysis_window.clone();

        // Create ERB filterbank
        let erb_fb = Self::create_erb_filterbank(NUM_BINS, ERB_BANDS, sample_rate);
        let erb_fb_inv = Self::create_inverse_erb_filterbank(&erb_fb);

        // Initialize hidden states (dimensions depend on model architecture)
        let erb_hidden = Array2::zeros((1, 256)); // Typical GRU hidden size
        let df_hidden = Array2::zeros((1, 256));

        let reduction = config.reduction;

        Ok(Self {
            erb_model,
            df_model,
            config,
            sample_rate,
            input_buffer: FrameBuffer::new(FFT_SIZE, FRAME_SIZE, 1, sample_rate),
            output_buffer: OverlapAddBuffer::new(FFT_SIZE, FRAME_SIZE),
            fft_forward,
            fft_inverse,
            analysis_window,
            synthesis_window,
            erb_fb,
            erb_fb_inv,
            erb_hidden,
            df_hidden,
            prev_spectrum: vec![Complex32::new(0.0, 0.0); NUM_BINS],
            noise_profile: None,
            reduction,
            frame_count: 0,
        })
    }

    /// Create ERB filterbank matrix
    fn create_erb_filterbank(num_bins: usize, num_bands: usize, sample_rate: u32) -> Array2<f32> {
        let mut fb = Array2::zeros((num_bands, num_bins));

        // ERB scale parameters
        let min_freq = 50.0;
        let max_freq = sample_rate as f32 / 2.0;

        // Convert to ERB scale
        let min_erb = Self::hz_to_erb(min_freq);
        let max_erb = Self::hz_to_erb(max_freq);

        // Create equally spaced center frequencies on ERB scale
        let erb_step = (max_erb - min_erb) / (num_bands + 1) as f32;

        for band in 0..num_bands {
            let center_erb = min_erb + (band + 1) as f32 * erb_step;
            let center_hz = Self::erb_to_hz(center_erb);

            // ERB bandwidth
            let bandwidth = 24.7 * (4.37 * center_hz / 1000.0 + 1.0);

            // Triangular filter
            for bin in 0..num_bins {
                let freq = bin as f32 * sample_rate as f32 / (2.0 * (num_bins - 1) as f32);
                let distance = (freq - center_hz).abs();

                if distance < bandwidth {
                    fb[[band, bin]] = 1.0 - distance / bandwidth;
                }
            }
        }

        // Normalize rows to sum to 1
        for mut row in fb.axis_iter_mut(Axis(0)) {
            let sum: f32 = row.sum();
            if sum > 0.0 {
                row /= sum;
            }
        }

        fb
    }

    /// Create inverse ERB filterbank
    fn create_inverse_erb_filterbank(fb: &Array2<f32>) -> Array2<f32> {
        // Pseudo-inverse: (A^T * A)^-1 * A^T
        // Simplified: just transpose and normalize
        let mut fb_inv = fb.t().to_owned();

        // Normalize columns
        for mut col in fb_inv.axis_iter_mut(Axis(1)) {
            let sum: f32 = col.sum();
            if sum > 0.0 {
                col /= sum;
            }
        }

        fb_inv
    }

    /// Convert Hz to ERB scale
    fn hz_to_erb(hz: f32) -> f32 {
        21.4 * (1.0 + 4.37 * hz / 1000.0).ln()
    }

    /// Convert ERB scale to Hz
    fn erb_to_hz(erb: f32) -> f32 {
        1000.0 * ((erb / 21.4).exp() - 1.0) / 4.37
    }

    /// Process single STFT frame
    fn process_stft_frame(&mut self, spectrum: &[Complex32]) -> MlResult<Vec<Complex32>> {
        // 1. Compute magnitude and phase
        let magnitude: Vec<f32> = spectrum.iter().map(|c| c.norm()).collect();
        let phase: Vec<f32> = spectrum.iter().map(|c| c.arg()).collect();

        // 2. Compute ERB features
        let erb_features = self.compute_erb_features(&magnitude);

        // 3. Run ERB model
        let (erb_gains, new_erb_hidden) = self.run_erb_model(&erb_features)?;
        self.erb_hidden = new_erb_hidden;

        // 4. Expand ERB gains to full spectrum
        let expanded_gains = self.expand_erb_gains(&erb_gains);

        // 5. Apply gains with reduction control
        let mut enhanced_mag: Vec<f32> = magnitude
            .iter()
            .zip(expanded_gains.iter())
            .map(|(&m, &g)| {
                let gain = 1.0 - self.reduction * (1.0 - g);
                m * gain.clamp(0.0, 1.0)
            })
            .collect();

        // 6. Run deep filtering if enabled
        if self.config.post_filter {
            let (df_coeffs, new_df_hidden) = self.run_df_model(&erb_features, &enhanced_mag)?;
            self.df_hidden = new_df_hidden;

            // Apply deep filter
            enhanced_mag = self.apply_deep_filter(&enhanced_mag, &df_coeffs);
        }

        // 7. Reconstruct complex spectrum
        let enhanced: Vec<Complex32> = enhanced_mag
            .iter()
            .zip(phase.iter())
            .map(|(&m, &p)| Complex32::from_polar(m, p))
            .collect();

        // Save for next frame
        self.prev_spectrum = enhanced.clone();
        self.frame_count += 1;

        Ok(enhanced)
    }

    /// Compute ERB features from magnitude spectrum
    fn compute_erb_features(&self, magnitude: &[f32]) -> Array1<f32> {
        let mag_array = Array1::from_vec(magnitude.to_vec());

        // Apply ERB filterbank: erb_features = erb_fb @ magnitude
        let erb_features = self.erb_fb.dot(&mag_array);

        // Log compression
        erb_features.mapv(|x| (x + 1e-10).ln())
    }

    /// Expand ERB gains to full spectrum
    fn expand_erb_gains(&self, erb_gains: &Array1<f32>) -> Vec<f32> {
        // Apply inverse filterbank: gains = erb_fb_inv @ erb_gains
        let expanded = self.erb_fb_inv.dot(erb_gains);
        expanded.to_vec()
    }

    /// Run ERB model
    fn run_erb_model(&self, erb_features: &Array1<f32>) -> MlResult<(Array1<f32>, Array2<f32>)> {
        // Prepare input: [batch=1, features=ERB_BANDS]
        let input = erb_features
            .clone()
            .insert_axis(ndarray::Axis(0))
            .into_dyn();

        let hidden_input = self.erb_hidden.clone().into_dyn();

        // Run inference
        let outputs = self.erb_model.run_f32(&[input, hidden_input])?;

        // Parse outputs
        let gains_raw = outputs.first()
            .ok_or_else(|| MlError::Internal("Missing ERB gains output".into()))?
            .clone();

        let gains = if gains_raw.shape().len() == 2 {
            gains_raw
                .into_dimensionality::<ndarray::Ix2>()
                .map_err(|e| MlError::Internal(e.to_string()))?
                .index_axis(ndarray::Axis(0), 0)
                .to_owned()
        } else {
            gains_raw
                .into_dimensionality::<ndarray::Ix1>()
                .map_err(|e| MlError::Internal(e.to_string()))?
        };

        // Apply sigmoid to get gains in [0, 1]
        let gains = gains.mapv(|x| 1.0 / (1.0 + (-x).exp()));

        let new_hidden = outputs
            .get(1)
            .ok_or_else(|| MlError::Internal("Missing ERB hidden output".into()))?
            .clone()
            .into_dimensionality::<ndarray::Ix2>()
            .map_err(|e| MlError::Internal(e.to_string()))?;

        Ok((gains, new_hidden))
    }

    /// Run deep filter model
    fn run_df_model(
        &self,
        erb_features: &Array1<f32>,
        magnitude: &[f32],
    ) -> MlResult<(Array2<f32>, Array2<f32>)> {
        // Prepare inputs
        let erb_input = erb_features
            .clone()
            .insert_axis(ndarray::Axis(0))
            .into_dyn();

        let mag_input = Array1::from_vec(magnitude.to_vec())
            .insert_axis(ndarray::Axis(0))
            .into_dyn();

        let hidden_input = self.df_hidden.clone().into_dyn();

        // Run inference
        let outputs = self
            .df_model
            .run_f32(&[erb_input, mag_input, hidden_input])?;

        // Deep filter coefficients
        let _df_order = 5;
        let coeffs_raw = outputs.first()
            .ok_or_else(|| MlError::Internal("Missing DF coefficients".into()))?
            .clone();

        let coeffs = coeffs_raw
            .into_dimensionality::<ndarray::Ix2>()
            .map_err(|e| MlError::Internal(e.to_string()))?;

        let new_hidden = outputs
            .get(1)
            .ok_or_else(|| MlError::Internal("Missing DF hidden output".into()))?
            .clone()
            .into_dimensionality::<ndarray::Ix2>()
            .map_err(|e| MlError::Internal(e.to_string()))?;

        Ok((coeffs, new_hidden))
    }

    /// Apply deep filter to magnitude
    fn apply_deep_filter(&self, magnitude: &[f32], coeffs: &Array2<f32>) -> Vec<f32> {
        let _df_order = 5;
        let mut filtered = magnitude.to_vec();

        // Deep filtering: convolution with learned complex coefficients
        // Simplified version: just apply real part of first coefficient
        for (bin, mag) in filtered.iter_mut().enumerate() {
            let coeff = coeffs[[bin, 0]]; // First real coefficient
            *mag *= coeff.abs().clamp(0.0, 1.0);
        }

        filtered
    }

    /// Process audio buffer (offline)
    pub fn process_buffer(&mut self, input: &[f32]) -> MlResult<Vec<f32>> {
        let mut output = Vec::with_capacity(input.len());
        let mut frame_buf = vec![0.0f32; FFT_SIZE];
        let mut spectrum = vec![Complex32::new(0.0, 0.0); NUM_BINS];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft_forward.get_scratch_len()];
        let mut inv_scratch = vec![Complex32::new(0.0, 0.0); self.fft_inverse.get_scratch_len()];

        // Process frame by frame
        self.input_buffer.reset();
        self.output_buffer.reset();

        self.input_buffer.push(input);

        while self.input_buffer.has_frame() {
            let frame = self.input_buffer.pop_frame().unwrap();

            // Apply analysis window
            for (i, &s) in frame.data.iter().enumerate() {
                frame_buf[i] = s * self.analysis_window[i];
            }

            // Forward FFT
            self.fft_forward
                .process_with_scratch(&mut frame_buf, &mut spectrum, &mut scratch)
                .map_err(|e| MlError::Internal(e.to_string()))?;

            // Process spectrum
            let enhanced = self.process_stft_frame(&spectrum)?;

            // Inverse FFT
            self.fft_inverse
                .process_with_scratch(&mut enhanced.clone(), &mut frame_buf, &mut inv_scratch)
                .map_err(|e| MlError::Internal(e.to_string()))?;

            // Normalize and apply synthesis window
            let norm = 1.0 / FFT_SIZE as f32;
            for (i, s) in frame_buf.iter_mut().enumerate() {
                *s *= norm * self.synthesis_window[i];
            }

            // Overlap-add
            self.output_buffer.add_frame(&frame_buf);

            // Read output
            let mut out_frame = vec![0.0f32; FRAME_SIZE];
            let read = self.output_buffer.read(&mut out_frame);
            output.extend(&out_frame[..read]);
        }

        // Flush remaining
        if let Some(frame) = self.input_buffer.flush() {
            // Process last frame similarly...
            // (simplified: just output zeros for remaining)
            let remaining = frame.data.len().min(FRAME_SIZE);
            output.extend(vec![0.0f32; remaining]);
        }

        Ok(output)
    }
}

impl Denoiser for DeepFilterNet {
    fn process_frame(&mut self, input: &AudioFrame) -> MlResult<AudioFrame> {
        // Convert to mono if stereo
        let mono = if input.channels > 1 {
            input.to_mono()
        } else {
            input.data.clone()
        };

        // Process mono
        let enhanced = self.process_buffer(&mono)?;

        // Return as mono frame
        Ok(AudioFrame::mono(enhanced, self.sample_rate, input.index))
    }

    fn reset(&mut self) {
        self.input_buffer.reset();
        self.output_buffer.reset();
        self.erb_hidden.fill(0.0);
        self.df_hidden.fill(0.0);
        self.prev_spectrum.fill(Complex32::new(0.0, 0.0));
        self.frame_count = 0;
    }

    fn latency_samples(&self) -> usize {
        FFT_SIZE + FRAME_SIZE * self.config.lookahead_frames
    }

    fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    fn learn_noise(&mut self, noise_sample: &[f32]) -> MlResult<()> {
        let mut profile = NoiseProfile::new(FFT_SIZE, self.sample_rate);

        // Create STFT buffer
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(FFT_SIZE);

        let mut frame_buf = vec![0.0f32; FFT_SIZE];
        let mut spectrum = vec![Complex32::new(0.0, 0.0); NUM_BINS];
        let mut scratch = vec![Complex32::new(0.0, 0.0); fft.get_scratch_len()];

        // Process frames
        for chunk in noise_sample.chunks(FRAME_SIZE) {
            if chunk.len() < FRAME_SIZE {
                break;
            }

            // Copy and window
            for (i, &s) in chunk.iter().enumerate() {
                frame_buf[i] = s * self.analysis_window.get(i).copied().unwrap_or(0.0);
            }
            for i in chunk.len()..FFT_SIZE {
                frame_buf[i] = 0.0;
            }

            // FFT
            fft.process_with_scratch(&mut frame_buf, &mut spectrum, &mut scratch)
                .map_err(|e| MlError::Internal(e.to_string()))?;

            // Update profile with magnitude
            let magnitude: Vec<f32> = spectrum.iter().map(|c| c.norm()).collect();
            profile.update(&magnitude);
        }

        profile.finalize();

        if !profile.is_valid() {
            return Err(MlError::BufferTooSmall {
                needed: profile.recommended_samples(),
                got: noise_sample.len(),
            });
        }

        self.noise_profile = Some(profile);
        Ok(())
    }

    fn set_reduction(&mut self, amount: f32) {
        self.reduction = amount.clamp(0.0, 1.0);
    }

    fn reduction(&self) -> f32 {
        self.reduction
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_erb_filterbank() {
        let fb = DeepFilterNet::create_erb_filterbank(481, 32, 48000);
        assert_eq!(fb.shape(), &[32, 481]);

        // Each row should sum to approximately 1
        for row in fb.axis_iter(Axis(0)) {
            let sum: f32 = row.sum();
            assert!(sum > 0.5 && sum < 1.5, "Row sum: {}", sum);
        }
    }

    #[test]
    fn test_hz_to_erb() {
        // 1000 Hz: 21.4 * ln(1 + 4.37 * 1) = 21.4 * ln(5.37) ≈ 35.95 ERB
        let erb = DeepFilterNet::hz_to_erb(1000.0);
        assert!((erb - 35.95).abs() < 1.0, "ERB for 1000 Hz: {}", erb);

        // Round-trip
        let hz = DeepFilterNet::erb_to_hz(erb);
        assert!((hz - 1000.0).abs() < 1.0, "Hz round-trip: {}", hz);
    }
}

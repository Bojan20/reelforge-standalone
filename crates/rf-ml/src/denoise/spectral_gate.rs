//! Spectral noise gate with optional neural enhancement
//!
//! Classical spectral subtraction with modern improvements:
//! - Adaptive noise floor estimation
//! - Psychoacoustic masking
//! - Optional neural post-filter

use crate::buffer::AudioFrame;
use crate::denoise::{DenoiseConfig, Denoiser, NoiseProfile};
use crate::error::{MlError, MlResult};

use num_complex::Complex32;
use realfft::{ComplexToReal, RealFftPlanner, RealToComplex};
use std::sync::Arc;

/// Spectral noise gate
pub struct SpectralGate {
    /// Configuration
    config: DenoiseConfig,

    /// Sample rate
    sample_rate: u32,

    /// FFT size
    fft_size: usize,

    /// Hop size
    hop_size: usize,

    /// Forward FFT
    fft_forward: Arc<dyn RealToComplex<f32>>,

    /// Inverse FFT
    fft_inverse: Arc<dyn ComplexToReal<f32>>,

    /// Analysis window
    analysis_window: Vec<f32>,

    /// Synthesis window
    synthesis_window: Vec<f32>,

    /// Input buffer
    input_buffer: Vec<f32>,

    /// Input position
    input_pos: usize,

    /// Output buffer (overlap-add)
    output_buffer: Vec<f32>,

    /// Output read position
    output_read_pos: usize,

    /// Output write position
    output_write_pos: usize,

    /// Noise profile
    noise_profile: Option<NoiseProfile>,

    /// Running noise estimate (adaptive)
    running_noise: Vec<f32>,

    /// Noise adaptation rate
    noise_adapt_rate: f32,

    /// Previous gains (for smoothing)
    prev_gains: Vec<f32>,

    /// Gain smoothing factor
    gain_smooth: f32,

    /// Reduction amount
    reduction: f32,

    /// Frame scratch buffer
    frame_scratch: Vec<f32>,

    /// Spectrum scratch buffer
    spectrum_scratch: Vec<Complex32>,

    /// FFT scratch buffer
    fft_scratch: Vec<Complex32>,

    /// IFFT scratch buffer
    ifft_scratch: Vec<Complex32>,
}

impl SpectralGate {
    /// Create new spectral gate
    pub fn new(config: DenoiseConfig, sample_rate: u32) -> MlResult<Self> {
        let fft_size = config.frame_size * 2; // 2x frame size for STFT
        let hop_size = config.hop_size;
        let num_bins = fft_size / 2 + 1;

        // Create FFT planners
        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Hann window
        let analysis_window: Vec<f32> = (0..fft_size)
            .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / fft_size as f32).cos()))
            .collect();

        // Synthesis window (same as analysis for 50% overlap)
        let synthesis_window = analysis_window.clone();

        let fft_scratch_len = fft_forward.get_scratch_len();
        let ifft_scratch_len = fft_inverse.get_scratch_len();

        Ok(Self {
            config: config.clone(),
            sample_rate,
            fft_size,
            hop_size,
            fft_forward,
            fft_inverse,
            analysis_window,
            synthesis_window,
            input_buffer: vec![0.0; fft_size],
            input_pos: 0,
            output_buffer: vec![0.0; fft_size * 2],
            output_read_pos: 0,
            output_write_pos: 0,
            noise_profile: None,
            running_noise: vec![0.0; num_bins],
            noise_adapt_rate: 0.02,
            prev_gains: vec![1.0; num_bins],
            gain_smooth: 0.7,
            reduction: config.reduction,
            frame_scratch: vec![0.0; fft_size],
            spectrum_scratch: vec![Complex32::new(0.0, 0.0); num_bins],
            fft_scratch: vec![Complex32::new(0.0, 0.0); fft_scratch_len],
            ifft_scratch: vec![Complex32::new(0.0, 0.0); ifft_scratch_len],
        })
    }

    /// Process single STFT frame
    fn process_spectrum(&mut self, spectrum: &mut [Complex32]) {
        let num_bins = spectrum.len();

        // Get noise floor
        let noise_floor = if let Some(profile) = &self.noise_profile {
            &profile.magnitude_floor
        } else {
            &self.running_noise
        };

        // Compute magnitude
        let magnitude: Vec<f32> = spectrum.iter().map(|c| c.norm()).collect();

        // Compute gains per bin
        let mut gains = Vec::with_capacity(num_bins);

        for (i, &mag) in magnitude.iter().enumerate() {
            let noise = noise_floor.get(i).copied().unwrap_or(0.0);

            // Spectral subtraction gain
            let snr = if noise > 1e-10 {
                (mag / noise).max(0.0)
            } else {
                100.0 // Very high SNR if no noise
            };

            // Wiener-like gain
            let gain = if snr > 1.0 {
                1.0 - (1.0 / snr).powf(self.reduction)
            } else {
                0.0
            };

            // Apply sensitivity
            let threshold = 1.0 + (1.0 - self.config.sensitivity) * 2.0;
            let adjusted_gain = if snr > threshold {
                gain
            } else {
                gain * (snr / threshold).max(0.0)
            };

            gains.push(adjusted_gain.clamp(0.0, 1.0));
        }

        // Smooth gains temporally
        for (i, gain) in gains.iter_mut().enumerate() {
            *gain = self.gain_smooth * self.prev_gains[i] + (1.0 - self.gain_smooth) * *gain;
            self.prev_gains[i] = *gain;
        }

        // Smooth gains spectrally (3-bin moving average)
        let smoothed: Vec<f32> = gains
            .iter()
            .enumerate()
            .map(|(i, &g)| {
                let prev = if i > 0 { gains[i - 1] } else { g };
                let next = if i < gains.len() - 1 { gains[i + 1] } else { g };
                (prev + g + next) / 3.0
            })
            .collect();

        // Apply gains
        for (i, c) in spectrum.iter_mut().enumerate() {
            *c *= smoothed[i];
        }

        // Update running noise estimate if no profile
        if self.noise_profile.is_none() {
            for (i, &mag) in magnitude.iter().enumerate() {
                // Adapt only when signal is likely noise (low magnitude)
                let threshold = self.running_noise[i] * 2.0;
                if mag < threshold || self.running_noise[i] == 0.0 {
                    self.running_noise[i] = (1.0 - self.noise_adapt_rate) * self.running_noise[i]
                        + self.noise_adapt_rate * mag;
                }
            }
        }
    }

    /// Process audio buffer
    pub fn process(&mut self, input: &[f32], output: &mut [f32]) -> usize {
        let mut processed = 0;

        for &sample in input {
            // Add to input buffer
            self.input_buffer[self.input_pos] = sample;
            self.input_pos += 1;

            // Process when we have a full frame
            if self.input_pos >= self.fft_size {
                // Apply analysis window
                for (i, &w) in self.analysis_window.iter().enumerate() {
                    self.frame_scratch[i] = self.input_buffer[i] * w;
                }

                // Forward FFT
                self.fft_forward
                    .process_with_scratch(
                        &mut self.frame_scratch,
                        &mut self.spectrum_scratch,
                        &mut self.fft_scratch,
                    )
                    .ok();

                // Process spectrum (copy to avoid borrow issues)
                let mut spectrum_copy = self.spectrum_scratch.clone();
                self.process_spectrum(&mut spectrum_copy);
                self.spectrum_scratch = spectrum_copy;

                // Inverse FFT
                self.fft_inverse
                    .process_with_scratch(
                        &mut self.spectrum_scratch,
                        &mut self.frame_scratch,
                        &mut self.ifft_scratch,
                    )
                    .ok();

                // Normalize and apply synthesis window
                let norm = 1.0 / self.fft_size as f32;
                for (i, &w) in self.synthesis_window.iter().enumerate() {
                    self.frame_scratch[i] *= norm * w;
                }

                // Overlap-add to output buffer
                for (i, &s) in self.frame_scratch.iter().enumerate() {
                    let pos = (self.output_write_pos + i) % self.output_buffer.len();
                    self.output_buffer[pos] += s;
                }

                // Advance output write position
                self.output_write_pos =
                    (self.output_write_pos + self.hop_size) % self.output_buffer.len();

                // Shift input buffer
                let shift = self.hop_size;
                self.input_buffer.copy_within(shift.., 0);
                self.input_pos = self.fft_size - shift;
            }
        }

        // Read available output
        while processed < output.len() {
            // Check if we have output available
            let available = if self.output_write_pos > self.output_read_pos {
                self.output_write_pos - self.output_read_pos
            } else if self.output_write_pos < self.output_read_pos {
                self.output_buffer.len() - self.output_read_pos + self.output_write_pos
            } else {
                0
            };

            if available == 0 {
                break;
            }

            output[processed] = self.output_buffer[self.output_read_pos];
            self.output_buffer[self.output_read_pos] = 0.0; // Clear after reading
            self.output_read_pos = (self.output_read_pos + 1) % self.output_buffer.len();
            processed += 1;
        }

        processed
    }
}

impl Denoiser for SpectralGate {
    fn process_frame(&mut self, input: &AudioFrame) -> MlResult<AudioFrame> {
        let mono = if input.channels > 1 {
            input.to_mono()
        } else {
            input.data.clone()
        };

        let mut output = vec![0.0f32; mono.len()];
        let processed = self.process(&mono, &mut output);
        output.truncate(processed);

        Ok(AudioFrame::mono(output, self.sample_rate, input.index))
    }

    fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.input_pos = 0;
        self.output_buffer.fill(0.0);
        self.output_read_pos = 0;
        self.output_write_pos = 0;
        self.prev_gains.fill(1.0);
        // Don't reset running_noise to preserve adaptation
    }

    fn latency_samples(&self) -> usize {
        self.fft_size
    }

    fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    fn learn_noise(&mut self, noise_sample: &[f32]) -> MlResult<()> {
        let mut profile = NoiseProfile::new(self.fft_size, self.sample_rate);

        // Process noise sample through STFT
        let num_bins = self.fft_size / 2 + 1;
        let mut frame = vec![0.0f32; self.fft_size];
        let mut spectrum = vec![Complex32::new(0.0, 0.0); num_bins];

        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(self.fft_size);
        let mut scratch = vec![Complex32::new(0.0, 0.0); fft.get_scratch_len()];

        for chunk in noise_sample.chunks(self.hop_size) {
            if chunk.len() < self.hop_size {
                break;
            }

            // Window
            for (i, &s) in chunk.iter().enumerate() {
                frame[i] = s * self.analysis_window.get(i).copied().unwrap_or(0.0);
            }
            for i in chunk.len()..self.fft_size {
                frame[i] = 0.0;
            }

            // FFT
            fft.process_with_scratch(&mut frame, &mut spectrum, &mut scratch)
                .map_err(|e| MlError::Internal(e.to_string()))?;

            // Update profile
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

        // Also set running noise to profile
        self.running_noise = profile.magnitude_floor.clone();
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
    fn test_spectral_gate_creation() {
        let config = DenoiseConfig::default();
        let gate = SpectralGate::new(config, 48000);
        assert!(gate.is_ok());
    }

    #[test]
    fn test_spectral_gate_process() {
        let config = DenoiseConfig {
            frame_size: 256,
            hop_size: 128,
            ..Default::default()
        };
        let mut gate = SpectralGate::new(config, 48000).unwrap();

        // Generate test signal with noise
        let signal: Vec<f32> = (0..2048)
            .map(|i| {
                let sine = (i as f32 * 0.1).sin() * 0.5;
                let noise = (i as f32 * 12345.678).sin() * 0.1;
                sine + noise
            })
            .collect();

        let mut output = vec![0.0f32; signal.len()];
        let processed = gate.process(&signal, &mut output);

        // Should have processed something
        assert!(processed > 0);
    }
}

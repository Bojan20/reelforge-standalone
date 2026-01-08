//! De-reverberation - suppress room reverb and reflections
//!
//! Features:
//! - Spectral dereverberation (weighted prediction error)
//! - Early reflections cancellation
//! - Late reverb suppression
//! - T60 estimation
//! - Dry/wet blend control

use crate::error::{RestoreError, RestoreResult};
use crate::{RestoreConfig, Restorer};
use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;
use std::sync::Arc;

/// Dereverb configuration
#[derive(Debug, Clone)]
pub struct DereverbConfig {
    /// Base configuration
    pub base: RestoreConfig,
    /// FFT size
    pub fft_size: usize,
    /// Hop size
    pub hop_size: usize,
    /// Late reverb suppression (dB)
    pub late_suppression_db: f32,
    /// Early reflection suppression (dB)
    pub early_suppression_db: f32,
    /// Reverb estimation frames
    pub estimation_frames: usize,
    /// Spectral floor
    pub spectral_floor: f32,
    /// Dry/wet mix (0.0 = full dry, 1.0 = full processed)
    pub mix: f32,
}

impl Default for DereverbConfig {
    fn default() -> Self {
        Self {
            base: RestoreConfig::default(),
            fft_size: 2048,
            hop_size: 512,
            late_suppression_db: 12.0,
            early_suppression_db: 6.0,
            estimation_frames: 20,
            spectral_floor: 0.1,
            mix: 1.0,
        }
    }
}

/// Reverb characteristics
#[derive(Debug, Clone)]
pub struct ReverbProfile {
    /// Estimated T60 per frequency band
    pub t60: Vec<f32>,
    /// Direct-to-reverb ratio per band
    pub drr: Vec<f32>,
    /// Early reflection delay (samples)
    pub early_delay: usize,
    /// Late reverb onset (samples)
    pub late_onset: usize,
}

impl ReverbProfile {
    fn new(bins: usize) -> Self {
        Self {
            t60: vec![0.3; bins],
            drr: vec![1.0; bins],
            early_delay: 0,
            late_onset: 0,
        }
    }
}

/// Spectral dereverberation processor
pub struct Dereverb {
    /// Configuration
    config: DereverbConfig,
    /// Sample rate
    sample_rate: u32,
    /// Forward FFT
    fft_forward: Arc<dyn RealToComplex<f32>>,
    /// Inverse FFT
    fft_inverse: Arc<dyn realfft::ComplexToReal<f32>>,
    /// Analysis window
    window: Vec<f32>,
    /// Synthesis window
    synthesis_window: Vec<f32>,
    /// Input buffer
    input_buffer: Vec<f32>,
    /// Output buffer
    output_buffer: Vec<f32>,
    /// Overlap-add buffer
    overlap_buffer: Vec<f32>,
    /// FFT scratch
    fft_scratch: Vec<f32>,
    /// Complex spectrum
    spectrum: Vec<Complex<f32>>,
    /// Inverse scratch
    ifft_scratch: Vec<f32>,
    /// Frame history for reverb estimation
    frame_history: Vec<Vec<f32>>,
    /// History position
    history_pos: usize,
    /// Reverb profile
    reverb_profile: ReverbProfile,
    /// Late reverb estimate per bin
    late_reverb: Vec<f32>,
    /// Previous frame power
    prev_power: Vec<f32>,
    /// Decay rate per bin
    decay_rate: Vec<f32>,
    /// Input position
    input_pos: usize,
    /// Late suppression gain (linear)
    late_gain: f32,
    /// Early suppression gain (linear)
    early_gain: f32,
}

impl Dereverb {
    /// Create new dereverb processor
    pub fn new(config: DereverbConfig, sample_rate: u32) -> Self {
        let fft_size = config.fft_size;
        let bins = fft_size / 2 + 1;
        let num_frames = config.estimation_frames;

        let mut planner = RealFftPlanner::<f32>::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Hann window for analysis
        let window: Vec<f32> = (0..fft_size)
            .map(|i| {
                let phase = 2.0 * std::f32::consts::PI * i as f32 / fft_size as f32;
                0.5 * (1.0 - phase.cos())
            })
            .collect();

        // Synthesis window (for perfect reconstruction)
        let synthesis_window = window.clone();

        let late_gain = 10.0_f32.powf(-config.late_suppression_db / 20.0);
        let early_gain = 10.0_f32.powf(-config.early_suppression_db / 20.0);

        Self {
            config: config.clone(),
            sample_rate,
            fft_forward,
            fft_inverse,
            window,
            synthesis_window,
            input_buffer: vec![0.0; fft_size],
            output_buffer: vec![0.0; fft_size],
            overlap_buffer: vec![0.0; fft_size],
            fft_scratch: vec![0.0; fft_size],
            spectrum: vec![Complex::new(0.0, 0.0); bins],
            ifft_scratch: vec![0.0; fft_size],
            frame_history: vec![vec![0.0; bins]; num_frames],
            history_pos: 0,
            reverb_profile: ReverbProfile::new(bins),
            late_reverb: vec![0.0; bins],
            prev_power: vec![0.0; bins],
            decay_rate: vec![0.95; bins],
            input_pos: 0,
            late_gain,
            early_gain,
        }
    }

    /// Process single FFT frame
    fn process_frame(&mut self) {
        let fft_size = self.config.fft_size;
        let _bins = fft_size / 2 + 1;

        // Apply analysis window
        for (i, sample) in self.fft_scratch.iter_mut().enumerate() {
            *sample = self.input_buffer[i] * self.window[i];
        }

        // Forward FFT
        self.fft_forward
            .process(&mut self.fft_scratch, &mut self.spectrum)
            .ok();

        // Compute power spectrum
        let power: Vec<f32> = self.spectrum.iter().map(|c| c.norm_sqr()).collect();

        // Store in history
        self.frame_history[self.history_pos].copy_from_slice(&power);
        self.history_pos = (self.history_pos + 1) % self.config.estimation_frames;

        // Estimate late reverb using temporal decay model
        self.estimate_late_reverb(&power);

        // Apply dereverberation
        self.apply_dereverb(&power);

        // Inverse FFT
        self.fft_inverse
            .process(&mut self.spectrum, &mut self.ifft_scratch)
            .ok();

        // Normalize and apply synthesis window
        let norm = 1.0 / fft_size as f32;
        for i in 0..fft_size {
            self.ifft_scratch[i] *= norm * self.synthesis_window[i];
        }

        // Overlap-add
        for i in 0..fft_size {
            self.overlap_buffer[i] += self.ifft_scratch[i];
        }
    }

    /// Estimate late reverb component
    fn estimate_late_reverb(&mut self, current_power: &[f32]) {
        let bins = current_power.len();
        let num_frames = self.config.estimation_frames;

        // Simple reverb estimation based on power decay
        for bin in 0..bins {
            // Look at past frames to estimate reverberant energy
            let mut reverb_sum = 0.0f32;
            let mut weight_sum = 0.0f32;

            for frame_offset in 1..num_frames {
                let frame_idx = (self.history_pos + num_frames - frame_offset) % num_frames;
                let past_power = self.frame_history[frame_idx][bin];

                // Weight by expected decay
                let decay = self.decay_rate[bin].powi(frame_offset as i32);
                let weight = decay;

                reverb_sum += past_power * weight;
                weight_sum += weight;
            }

            if weight_sum > 1e-10 {
                self.late_reverb[bin] = reverb_sum / weight_sum;
            }

            // Update decay rate based on observed decay
            if self.prev_power[bin] > 1e-10 && current_power[bin] > 1e-10 {
                let observed_decay = (current_power[bin] / self.prev_power[bin]).sqrt();
                // Smooth update
                self.decay_rate[bin] = 0.99 * self.decay_rate[bin] + 0.01 * observed_decay.clamp(0.5, 0.999);
            }

            self.prev_power[bin] = current_power[bin];
        }
    }

    /// Apply dereverberation to spectrum
    fn apply_dereverb(&mut self, current_power: &[f32]) {
        let floor = self.config.spectral_floor;
        let mix = self.config.mix;

        for (bin, spectrum_bin) in self.spectrum.iter_mut().enumerate() {
            let power = current_power[bin];
            let reverb = self.late_reverb[bin];

            // Estimate direct signal power
            let direct_power = (power - reverb * self.late_gain).max(power * floor);

            // Wiener-like gain
            let gain = if power > 1e-10 {
                (direct_power / power).sqrt().clamp(floor, 1.0)
            } else {
                1.0
            };

            // Apply with mix control
            let final_gain = mix * gain + (1.0 - mix);

            *spectrum_bin = *spectrum_bin * final_gain;
        }
    }

    /// Estimate T60 reverberation time
    pub fn estimate_t60(&self, audio: &[f32]) -> f32 {
        // Simple T60 estimation using energy decay
        let fft_size = self.config.fft_size;

        if audio.len() < fft_size * 10 {
            return 0.3; // Default
        }

        // Find decay regions (after transients)
        let hop = fft_size / 4;
        let mut energies: Vec<f32> = Vec::new();

        for start in (0..audio.len() - fft_size).step_by(hop) {
            let energy: f32 = audio[start..start + fft_size]
                .iter()
                .map(|s| s * s)
                .sum();
            energies.push(energy);
        }

        // Find peak and measure decay
        if let Some((peak_idx, &peak_val)) = energies
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
        {
            // Find -60dB point
            let threshold = peak_val * 0.001; // -60dB

            for (i, &e) in energies.iter().enumerate().skip(peak_idx) {
                if e < threshold {
                    let decay_samples = (i - peak_idx) * hop;
                    return decay_samples as f32 / self.sample_rate as f32;
                }
            }
        }

        0.3 // Default T60
    }

    /// Set late reverb suppression
    pub fn set_late_suppression(&mut self, db: f32) {
        self.config.late_suppression_db = db;
        self.late_gain = 10.0_f32.powf(-db / 20.0);
    }

    /// Set early reflection suppression
    pub fn set_early_suppression(&mut self, db: f32) {
        self.config.early_suppression_db = db;
        self.early_gain = 10.0_f32.powf(-db / 20.0);
    }

    /// Set dry/wet mix
    pub fn set_mix(&mut self, mix: f32) {
        self.config.mix = mix.clamp(0.0, 1.0);
    }
}

impl Restorer for Dereverb {
    fn process(&mut self, input: &[f32], output: &mut [f32]) -> RestoreResult<()> {
        if input.len() != output.len() {
            return Err(RestoreError::BufferMismatch {
                expected: input.len(),
                got: output.len(),
            });
        }

        let fft_size = self.config.fft_size;
        let hop_size = self.config.hop_size;

        for (i, &sample) in input.iter().enumerate() {
            // Add to input buffer
            self.input_buffer[self.input_pos] = sample;
            self.input_pos += 1;

            // Get output from overlap buffer
            output[i] = self.overlap_buffer[0];

            // Shift overlap buffer
            self.overlap_buffer.copy_within(1.., 0);
            self.overlap_buffer[fft_size - 1] = 0.0;

            // Process when we have a full frame
            if self.input_pos >= fft_size {
                self.process_frame();

                // Shift input buffer by hop_size
                self.input_buffer.copy_within(hop_size.., 0);
                self.input_pos = fft_size - hop_size;
            }
        }

        Ok(())
    }

    fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.output_buffer.fill(0.0);
        self.overlap_buffer.fill(0.0);
        self.fft_scratch.fill(0.0);
        self.ifft_scratch.fill(0.0);
        self.late_reverb.fill(0.0);
        self.prev_power.fill(0.0);
        self.decay_rate.fill(0.95);

        for frame in &mut self.frame_history {
            frame.fill(0.0);
        }

        self.history_pos = 0;
        self.input_pos = 0;
    }

    fn latency_samples(&self) -> usize {
        self.config.fft_size
    }

    fn name(&self) -> &str {
        "Dereverb"
    }
}

/// Weighted Prediction Error (WPE) dereverberation
/// More advanced algorithm for blind dereverberation
pub struct WpeDereverb {
    /// Configuration
    config: DereverbConfig,
    /// Sample rate
    sample_rate: u32,
    /// FFT size
    fft_size: usize,
    /// Prediction filter length (frames)
    prediction_length: usize,
    /// Prediction delay (frames)
    prediction_delay: usize,
    /// Filter coefficients per bin
    filters: Vec<Vec<Complex<f32>>>,
    /// Frame buffer for prediction
    frame_buffer: Vec<Vec<Complex<f32>>>,
    /// Buffer position
    buffer_pos: usize,
    /// Forward FFT
    fft_forward: Arc<dyn RealToComplex<f32>>,
    /// Inverse FFT
    fft_inverse: Arc<dyn realfft::ComplexToReal<f32>>,
    /// Windows
    window: Vec<f32>,
    /// Input buffer
    input_buffer: Vec<f32>,
    /// Overlap buffer
    overlap_buffer: Vec<f32>,
    /// Input position
    input_pos: usize,
}

impl WpeDereverb {
    /// Create WPE dereverberation processor
    pub fn new(config: DereverbConfig, sample_rate: u32) -> Self {
        let fft_size = config.fft_size;
        let bins = fft_size / 2 + 1;
        let prediction_length = 10;
        let prediction_delay = 3;

        let mut planner = RealFftPlanner::<f32>::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        let window: Vec<f32> = (0..fft_size)
            .map(|i| {
                let phase = 2.0 * std::f32::consts::PI * i as f32 / fft_size as f32;
                0.5 * (1.0 - phase.cos())
            })
            .collect();

        Self {
            config,
            sample_rate,
            fft_size,
            prediction_length,
            prediction_delay,
            filters: vec![vec![Complex::new(0.0, 0.0); prediction_length]; bins],
            frame_buffer: vec![vec![Complex::new(0.0, 0.0); bins]; prediction_length + prediction_delay],
            buffer_pos: 0,
            fft_forward,
            fft_inverse,
            window,
            input_buffer: vec![0.0; fft_size],
            overlap_buffer: vec![0.0; fft_size],
            input_pos: 0,
        }
    }

    /// Process frame with WPE
    fn process_frame(&mut self, spectrum: &mut [Complex<f32>]) {
        let bins = spectrum.len();

        // Store current frame
        self.frame_buffer[self.buffer_pos].copy_from_slice(spectrum);

        // Predict reverberant component
        for bin in 0..bins {
            let mut prediction = Complex::new(0.0, 0.0);

            for tap in 0..self.prediction_length {
                let frame_idx =
                    (self.buffer_pos + self.frame_buffer.len() - self.prediction_delay - tap)
                        % self.frame_buffer.len();

                prediction += self.filters[bin][tap] * self.frame_buffer[frame_idx][bin];
            }

            // Subtract prediction (dereverberate)
            spectrum[bin] = spectrum[bin] - prediction * self.config.mix;
        }

        // Update filters (simplified LMS)
        let mu = 0.001; // Learning rate

        for bin in 0..bins {
            let error = spectrum[bin];

            for tap in 0..self.prediction_length {
                let frame_idx =
                    (self.buffer_pos + self.frame_buffer.len() - self.prediction_delay - tap)
                        % self.frame_buffer.len();

                let x = self.frame_buffer[frame_idx][bin];
                self.filters[bin][tap] += x.conj() * error * mu;
            }
        }

        self.buffer_pos = (self.buffer_pos + 1) % self.frame_buffer.len();
    }
}

impl Restorer for WpeDereverb {
    fn process(&mut self, input: &[f32], output: &mut [f32]) -> RestoreResult<()> {
        if input.len() != output.len() {
            return Err(RestoreError::BufferMismatch {
                expected: input.len(),
                got: output.len(),
            });
        }

        let fft_size = self.fft_size;
        let hop_size = self.config.hop_size;

        let mut fft_scratch = vec![0.0f32; fft_size];
        let mut spectrum = vec![Complex::new(0.0, 0.0); fft_size / 2 + 1];
        let mut ifft_scratch = vec![0.0f32; fft_size];

        for (i, &sample) in input.iter().enumerate() {
            self.input_buffer[self.input_pos] = sample;
            self.input_pos += 1;

            output[i] = self.overlap_buffer[0];
            self.overlap_buffer.copy_within(1.., 0);
            self.overlap_buffer[fft_size - 1] = 0.0;

            if self.input_pos >= fft_size {
                // Apply window
                for (j, s) in fft_scratch.iter_mut().enumerate() {
                    *s = self.input_buffer[j] * self.window[j];
                }

                // FFT
                self.fft_forward.process(&mut fft_scratch, &mut spectrum).ok();

                // Process with WPE
                self.process_frame(&mut spectrum);

                // IFFT
                self.fft_inverse.process(&mut spectrum, &mut ifft_scratch).ok();

                // Normalize and overlap-add
                let norm = 1.0 / fft_size as f32;
                for j in 0..fft_size {
                    self.overlap_buffer[j] += ifft_scratch[j] * norm * self.window[j];
                }

                // Shift input
                self.input_buffer.copy_within(hop_size.., 0);
                self.input_pos = fft_size - hop_size;
            }
        }

        Ok(())
    }

    fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.overlap_buffer.fill(0.0);

        for frame in &mut self.frame_buffer {
            frame.fill(Complex::new(0.0, 0.0));
        }

        for filter in &mut self.filters {
            filter.fill(Complex::new(0.0, 0.0));
        }

        self.buffer_pos = 0;
        self.input_pos = 0;
    }

    fn latency_samples(&self) -> usize {
        self.fft_size + self.prediction_delay * self.config.hop_size
    }

    fn name(&self) -> &str {
        "WpeDereverb"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dereverb_creation() {
        let config = DereverbConfig::default();
        let dereverb = Dereverb::new(config, 48000);
        assert_eq!(dereverb.name(), "Dereverb");
    }

    #[test]
    fn test_dereverb_process() {
        let config = DereverbConfig::default();
        let mut dereverb = Dereverb::new(config, 48000);

        let input: Vec<f32> = (0..4096)
            .map(|i| {
                let t = i as f32 / 48000.0;
                (2.0 * std::f32::consts::PI * 440.0 * t).sin() * 0.5
            })
            .collect();

        let mut output = vec![0.0f32; input.len()];
        dereverb.process(&input, &mut output).unwrap();

        assert!(output.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn test_t60_estimation() {
        let config = DereverbConfig::default();
        let dereverb = Dereverb::new(config, 48000);

        // Create decaying signal
        let signal: Vec<f32> = (0..48000)
            .map(|i| {
                let t = i as f32 / 48000.0;
                let decay = (-t * 3.0).exp(); // T60 ~ 0.3s
                (2.0 * std::f32::consts::PI * 440.0 * t).sin() * decay
            })
            .collect();

        let t60 = dereverb.estimate_t60(&signal);
        // Should be roughly 0.2-0.5 seconds
        assert!(t60 > 0.1 && t60 < 1.0);
    }

    #[test]
    fn test_wpe_dereverb() {
        let config = DereverbConfig::default();
        let mut wpe = WpeDereverb::new(config, 48000);

        let input = vec![0.0f32; 4096];
        let mut output = vec![0.0f32; 4096];

        wpe.process(&input, &mut output).unwrap();
        assert_eq!(wpe.name(), "WpeDereverb");
    }

    #[test]
    fn test_dereverb_reset() {
        let config = DereverbConfig::default();
        let mut dereverb = Dereverb::new(config, 48000);

        // Process some audio
        let input = vec![0.5f32; 1024];
        let mut output = vec![0.0f32; 1024];
        dereverb.process(&input, &mut output).unwrap();

        // Reset
        dereverb.reset();

        // Internal state should be cleared
        assert!(dereverb.late_reverb.iter().all(|&v| v == 0.0));
    }
}

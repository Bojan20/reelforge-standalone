//! P12.1.4 — Simple Time-Stretch FFI
//!
//! Phase vocoder-based time stretching for matching audio duration to animation timing.
//! Designed for SlotLab use case: win rollup audio matching rollup animation duration.
//!
//! ## Algorithm
//!
//! Uses a standard phase vocoder with:
//! - STFT (Short-Time Fourier Transform) analysis
//! - Phase adjustment for time scaling
//! - ISTFT (Inverse STFT) reconstruction
//! - Hann window with 75% overlap for minimal artifacts
//!
//! ## Quality Targets
//!
//! - Pitch preservation (phase vocoder maintains frequency content)
//! - Minimal artifacts (Hann window, 75% overlap)
//! - Support 0.5x to 2.0x time stretch range

use rustfft::FftPlanner;
use rustfft::num_complex::Complex;
use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Default FFT size for good quality/latency tradeoff
const DEFAULT_FFT_SIZE: usize = 2048;

/// Overlap factor (75% overlap = hop_size = fft_size / 4)
const OVERLAP_FACTOR: usize = 4;

// ═══════════════════════════════════════════════════════════════════════════════
// SIMPLE PHASE VOCODER
// ═══════════════════════════════════════════════════════════════════════════════

/// Simple phase vocoder for time stretching
///
/// # Example
///
/// ```ignore
/// let mut vocoder = SimplePhaseVocoder::new(2048, 44100.0);
///
/// // Stretch audio to 1.5x duration (slower playback, same pitch)
/// let stretched = vocoder.process(&input_samples, 1.5);
///
/// // Compress audio to 0.8x duration (faster playback, same pitch)
/// let compressed = vocoder.process(&input_samples, 0.8);
/// ```
pub struct SimplePhaseVocoder {
    /// FFT size
    fft_size: usize,
    /// Analysis hop size
    hop_a: usize,
    /// Synthesis hop size (calculated from stretch factor)
    hop_s: usize,
    /// Sample rate
    sample_rate: f64,
    /// Analysis window (Hann)
    window: Vec<f64>,
    /// Previous frame phase (for phase accumulation)
    prev_phase: Vec<f64>,
    /// Accumulated phase (for synthesis)
    phase_acc: Vec<f64>,
    /// Expected phase increment per bin
    omega: Vec<f64>,
    /// FFT planner
    fft_planner: FftPlanner<f64>,
}

impl SimplePhaseVocoder {
    /// Create a new phase vocoder
    ///
    /// # Arguments
    ///
    /// * `fft_size` - FFT size (power of 2, typically 1024-4096)
    /// * `sample_rate` - Audio sample rate in Hz
    pub fn new(fft_size: usize, sample_rate: f64) -> Self {
        let hop = fft_size / OVERLAP_FACTOR;

        // Expected phase increment per bin: ω[k] = 2π × k × hop_size / fft_size
        let omega: Vec<f64> = (0..fft_size)
            .map(|k| 2.0 * PI * k as f64 * hop as f64 / fft_size as f64)
            .collect();

        Self {
            fft_size,
            hop_a: hop,
            hop_s: hop,
            sample_rate,
            window: Self::create_hann_window(fft_size),
            prev_phase: vec![0.0; fft_size],
            phase_acc: vec![0.0; fft_size],
            omega,
            fft_planner: FftPlanner::new(),
        }
    }

    /// Create a new phase vocoder with default FFT size (2048)
    pub fn new_default(sample_rate: f64) -> Self {
        Self::new(DEFAULT_FFT_SIZE, sample_rate)
    }

    /// Create Hann window for STFT analysis
    fn create_hann_window(size: usize) -> Vec<f64> {
        (0..size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / (size - 1) as f64).cos()))
            .collect()
    }

    /// Process audio with time stretching
    ///
    /// # Arguments
    ///
    /// * `input` - Input audio samples (mono f64)
    /// * `factor` - Time stretch factor:
    ///   - factor < 1.0 = speed up (shorter duration)
    ///   - factor > 1.0 = slow down (longer duration)
    ///   - factor = 1.0 = no change
    ///
    /// # Returns
    ///
    /// Time-stretched audio samples
    ///
    /// # Panics
    ///
    /// Panics if factor is <= 0.0
    pub fn process(&mut self, input: &[f64], factor: f64) -> Vec<f64> {
        assert!(factor > 0.0, "Stretch factor must be positive");

        // Clamp factor to reasonable range
        let factor = factor.clamp(0.25, 4.0);

        // Short input: just resample
        if input.len() < self.fft_size {
            return self.simple_resample(input, factor);
        }

        // Calculate synthesis hop size based on stretch factor
        self.hop_s = ((self.hop_a as f64 * factor) as usize).max(1);

        // Calculate output length
        let output_len = (input.len() as f64 * factor) as usize;
        let mut output = vec![0.0; output_len];
        let mut window_acc = vec![0.0; output_len];

        // Create FFT plans
        let fft = self.fft_planner.plan_fft_forward(self.fft_size);
        let ifft = self.fft_planner.plan_fft_inverse(self.fft_size);

        // Reset phase accumulators
        self.prev_phase.fill(0.0);
        self.phase_acc.fill(0.0);

        // Calculate number of frames
        let num_frames = (input.len() - self.fft_size) / self.hop_a + 1;

        for frame_idx in 0..num_frames {
            let in_pos = frame_idx * self.hop_a;
            let out_pos = frame_idx * self.hop_s;

            // Check if we can write to output
            if out_pos + self.fft_size > output_len {
                break;
            }

            // === ANALYSIS (STFT) ===

            // Apply window and prepare for FFT
            let mut frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size];
            for i in 0..self.fft_size {
                frame[i] = Complex::new(input[in_pos + i] * self.window[i], 0.0);
            }

            // Forward FFT
            fft.process(&mut frame);

            // Extract magnitude and phase
            let magnitudes: Vec<f64> = frame.iter().map(|c| c.norm()).collect();
            let phases: Vec<f64> = frame.iter().map(|c| c.arg()).collect();

            // === PHASE PROPAGATION ===

            let mut new_phases = vec![0.0; self.fft_size];
            let num_bins = self.fft_size / 2 + 1;

            for bin in 0..num_bins {
                // Calculate phase deviation from expected
                let phase_diff = phases[bin] - self.prev_phase[bin] - self.omega[bin];

                // Wrap to [-π, π]
                let phase_diff_wrapped = Self::wrap_phase(phase_diff);

                // True frequency deviation (as fraction of bin)
                let freq_dev = phase_diff_wrapped / (2.0 * PI);

                // Calculate phase increment for synthesis hop
                // Phase increment = expected + deviation, scaled by stretch factor
                let phase_inc = (self.omega[bin] + 2.0 * PI * freq_dev) * factor;

                // Accumulate phase
                self.phase_acc[bin] += phase_inc;
                new_phases[bin] = self.phase_acc[bin];
            }

            // === SYNTHESIS (ISTFT) ===

            // Reconstruct complex spectrum with new phases
            let mut synth_frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size];

            for bin in 0..num_bins {
                synth_frame[bin] = Complex::from_polar(magnitudes[bin], new_phases[bin]);

                // Mirror negative frequencies (conjugate symmetry)
                if bin > 0 && bin < self.fft_size / 2 {
                    synth_frame[self.fft_size - bin] = synth_frame[bin].conj();
                }
            }

            // Inverse FFT
            ifft.process(&mut synth_frame);

            // Overlap-add with synthesis window
            for i in 0..self.fft_size {
                if out_pos + i < output_len {
                    let w = self.window[i];
                    // Normalize by FFT size and apply window
                    output[out_pos + i] += synth_frame[i].re * w / self.fft_size as f64;
                    window_acc[out_pos + i] += w * w;
                }
            }

            // Store current phase for next frame
            self.prev_phase.copy_from_slice(&phases);
        }

        // Normalize by accumulated window
        for i in 0..output_len {
            if window_acc[i] > 1e-10 {
                output[i] /= window_acc[i];
            }
        }

        output
    }

    /// Process stereo audio
    ///
    /// Processes left and right channels independently.
    pub fn process_stereo(
        &mut self,
        left: &[f64],
        right: &[f64],
        factor: f64,
    ) -> (Vec<f64>, Vec<f64>) {
        let left_out = self.process(left, factor);
        self.reset();
        let right_out = self.process(right, factor);
        (left_out, right_out)
    }

    /// Match audio duration to target duration
    ///
    /// # Arguments
    ///
    /// * `input` - Input audio samples
    /// * `target_duration_ms` - Target duration in milliseconds
    ///
    /// # Returns
    ///
    /// Time-stretched audio that matches the target duration
    pub fn match_duration(&mut self, input: &[f64], target_duration_ms: f64) -> Vec<f64> {
        if input.is_empty() {
            return vec![];
        }

        // Calculate current duration
        let current_duration_ms = input.len() as f64 / self.sample_rate * 1000.0;

        // Calculate stretch factor
        let factor = target_duration_ms / current_duration_ms;

        self.process(input, factor)
    }

    /// Reset internal state
    pub fn reset(&mut self) {
        self.prev_phase.fill(0.0);
        self.phase_acc.fill(0.0);
    }

    /// Wrap phase to [-π, π]
    #[inline]
    fn wrap_phase(phase: f64) -> f64 {
        let mut p = phase;
        while p > PI {
            p -= 2.0 * PI;
        }
        while p < -PI {
            p += 2.0 * PI;
        }
        p
    }

    /// Simple resampling for short inputs
    fn simple_resample(&self, input: &[f64], factor: f64) -> Vec<f64> {
        let output_len = (input.len() as f64 * factor) as usize;
        if output_len == 0 {
            return vec![];
        }

        let mut output = vec![0.0; output_len];

        for i in 0..output_len {
            // Linear interpolation
            let src_pos = i as f64 / factor;
            let src_idx = src_pos as usize;
            let frac = src_pos - src_idx as f64;

            if src_idx + 1 < input.len() {
                output[i] = input[src_idx] * (1.0 - frac) + input[src_idx + 1] * frac;
            } else if src_idx < input.len() {
                output[i] = input[src_idx];
            }
        }

        output
    }

    /// Get FFT size
    pub fn fft_size(&self) -> usize {
        self.fft_size
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> f64 {
        self.sample_rate
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Calculate stretch factor to match audio to target duration
///
/// # Arguments
///
/// * `audio_samples` - Number of samples in input audio
/// * `sample_rate` - Audio sample rate
/// * `target_duration_ms` - Target duration in milliseconds
///
/// # Returns
///
/// Stretch factor (> 1.0 = slow down, < 1.0 = speed up)
pub fn calculate_stretch_factor(
    audio_samples: usize,
    sample_rate: f64,
    target_duration_ms: f64,
) -> f64 {
    let current_duration_ms = audio_samples as f64 / sample_rate * 1000.0;
    if current_duration_ms <= 0.0 {
        return 1.0;
    }
    target_duration_ms / current_duration_ms
}

/// Get audio duration in milliseconds
pub fn audio_duration_ms(samples: usize, sample_rate: f64) -> f64 {
    samples as f64 / sample_rate * 1000.0
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_RATE: f64 = 44100.0;

    /// Generate a simple sine wave for testing
    fn generate_sine(freq: f64, duration_ms: f64, sample_rate: f64) -> Vec<f64> {
        let num_samples = (duration_ms / 1000.0 * sample_rate) as usize;
        (0..num_samples)
            .map(|i| (2.0 * PI * freq * i as f64 / sample_rate).sin())
            .collect()
    }

    #[test]
    fn test_no_stretch() {
        let mut vocoder = SimplePhaseVocoder::new_default(SAMPLE_RATE);
        let input = generate_sine(440.0, 500.0, SAMPLE_RATE);

        let output = vocoder.process(&input, 1.0);

        // Output should be approximately same length
        let ratio = output.len() as f64 / input.len() as f64;
        assert!(
            (ratio - 1.0).abs() < 0.05,
            "No stretch should preserve length. Ratio: {}",
            ratio
        );
    }

    #[test]
    fn test_stretch_2x() {
        let mut vocoder = SimplePhaseVocoder::new_default(SAMPLE_RATE);
        let input = generate_sine(440.0, 500.0, SAMPLE_RATE);

        let output = vocoder.process(&input, 2.0);

        // Output should be approximately 2x input length
        let ratio = output.len() as f64 / input.len() as f64;
        assert!(
            (ratio - 2.0).abs() < 0.1,
            "2x stretch should double length. Ratio: {}",
            ratio
        );
    }

    #[test]
    fn test_compress_0_5x() {
        let mut vocoder = SimplePhaseVocoder::new_default(SAMPLE_RATE);
        let input = generate_sine(440.0, 500.0, SAMPLE_RATE);

        let output = vocoder.process(&input, 0.5);

        // Output should be approximately 0.5x input length
        let ratio = output.len() as f64 / input.len() as f64;
        assert!(
            (ratio - 0.5).abs() < 0.1,
            "0.5x stretch should halve length. Ratio: {}",
            ratio
        );
    }

    #[test]
    fn test_match_duration() {
        let mut vocoder = SimplePhaseVocoder::new_default(SAMPLE_RATE);
        let input = generate_sine(440.0, 2000.0, SAMPLE_RATE); // 2000ms input

        let output = vocoder.match_duration(&input, 3000.0); // Target 3000ms

        // Check output duration
        let output_duration_ms = output.len() as f64 / SAMPLE_RATE * 1000.0;
        assert!(
            (output_duration_ms - 3000.0).abs() < 100.0,
            "Duration should be ~3000ms. Got: {}ms",
            output_duration_ms
        );
    }

    #[test]
    fn test_stereo_processing() {
        let mut vocoder = SimplePhaseVocoder::new_default(SAMPLE_RATE);
        let left = generate_sine(440.0, 500.0, SAMPLE_RATE);
        let right = generate_sine(880.0, 500.0, SAMPLE_RATE);

        let (left_out, right_out) = vocoder.process_stereo(&left, &right, 1.5);

        assert!(!left_out.is_empty());
        assert!(!right_out.is_empty());
        assert_eq!(left_out.len(), right_out.len());
    }

    #[test]
    fn test_empty_input() {
        let mut vocoder = SimplePhaseVocoder::new_default(SAMPLE_RATE);
        let output = vocoder.process(&[], 1.5);
        assert!(output.is_empty());
    }

    #[test]
    fn test_short_input() {
        let mut vocoder = SimplePhaseVocoder::new(1024, SAMPLE_RATE);
        let input = vec![0.5; 100]; // Shorter than FFT size

        let output = vocoder.process(&input, 2.0);

        // Should still produce output (via simple resampling)
        assert!(!output.is_empty());
    }

    #[test]
    fn test_calculate_stretch_factor() {
        let factor = calculate_stretch_factor(44100, 44100.0, 2000.0);
        assert!((factor - 2.0).abs() < 0.01); // 1s input, 2s target = 2x stretch
    }

    #[test]
    fn test_audio_duration_ms() {
        let duration = audio_duration_ms(44100, 44100.0);
        assert!((duration - 1000.0).abs() < 0.1); // 44100 samples @ 44.1kHz = 1000ms
    }

    #[test]
    fn test_pitch_preservation() {
        // This test verifies that pitch is preserved after stretching
        // by checking that the dominant frequency remains the same
        let mut vocoder = SimplePhaseVocoder::new_default(SAMPLE_RATE);
        let input = generate_sine(440.0, 1000.0, SAMPLE_RATE);

        let output = vocoder.process(&input, 1.5);

        // Calculate zero-crossing rate as a proxy for pitch
        let zcr_input = zero_crossing_rate(&input);
        let zcr_output = zero_crossing_rate(&output);

        // ZCR should be similar (pitch preserved)
        let ratio = zcr_output / zcr_input;
        assert!(
            (ratio - 1.0).abs() < 0.15,
            "Pitch should be preserved. ZCR ratio: {}",
            ratio
        );
    }

    /// Helper: Calculate zero-crossing rate
    fn zero_crossing_rate(signal: &[f64]) -> f64 {
        if signal.len() < 2 {
            return 0.0;
        }
        let crossings = signal
            .windows(2)
            .filter(|w| w[0].signum() != w[1].signum())
            .count();
        crossings as f64 / signal.len() as f64
    }
}

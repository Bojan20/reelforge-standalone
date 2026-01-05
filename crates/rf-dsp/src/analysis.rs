//! Audio analysis: FFT, metering, loudness measurement
//!
//! All analyzers include input validation for sample rates and FFT sizes.

use rf_core::Sample;
use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;
use std::sync::Arc;

// ============================================================================
// VALIDATION CONSTANTS
// ============================================================================

/// Default sample rate for fallback
const DEFAULT_SAMPLE_RATE: f64 = 48000.0;
/// Minimum FFT size
const MIN_FFT_SIZE: usize = 64;
/// Maximum FFT size
const MAX_FFT_SIZE: usize = 65536;
/// Default FFT size
const DEFAULT_FFT_SIZE: usize = 2048;

/// FFT analyzer for spectrum display
pub struct FftAnalyzer {
    fft: Arc<dyn RealToComplex<f64>>,
    fft_size: usize,
    input_buffer: Vec<f64>,
    output_buffer: Vec<Complex<f64>>,
    window: Vec<f64>,
    magnitudes: Vec<f64>,
    write_pos: usize,
}

impl FftAnalyzer {
    pub fn new(fft_size: usize) -> Self {
        // Validate FFT size (must be power of 2 and within range)
        let fft_size = if fft_size >= MIN_FFT_SIZE && fft_size <= MAX_FFT_SIZE && fft_size.is_power_of_two() {
            fft_size
        } else {
            DEFAULT_FFT_SIZE
        };

        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        let output_len = fft_size / 2 + 1;

        // Hann window
        let window: Vec<f64> = (0..fft_size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f64::consts::PI * i as f64 / (fft_size - 1) as f64).cos())
            })
            .collect();

        Self {
            fft,
            fft_size,
            input_buffer: vec![0.0; fft_size],
            output_buffer: vec![Complex::new(0.0, 0.0); output_len],
            window,
            magnitudes: vec![0.0; output_len],
            write_pos: 0,
        }
    }

    /// Add samples to the analyzer
    pub fn push_samples(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.input_buffer[self.write_pos] = sample;
            self.write_pos = (self.write_pos + 1) % self.fft_size;
        }
    }

    /// Perform FFT and update magnitudes
    pub fn analyze(&mut self) {
        // Apply window
        let mut windowed: Vec<f64> = self
            .input_buffer
            .iter()
            .zip(&self.window)
            .map(|(&s, &w)| s * w)
            .collect();

        // Rotate buffer to start from write position for correct phase
        windowed.rotate_left(self.write_pos);

        // Perform FFT (safe: buffer sizes are validated in new())
        if let Err(_) = self.fft.process(&mut windowed, &mut self.output_buffer) {
            // FFT failed - fill with silence
            for c in &mut self.output_buffer {
                *c = Complex::new(0.0, 0.0);
            }
            return;
        }

        // Calculate magnitudes in dB
        let scale = 2.0 / self.fft_size as f64;
        for (i, c) in self.output_buffer.iter().enumerate() {
            let magnitude = (c.re * c.re + c.im * c.im).sqrt() * scale;
            // Convert to dB with smoothing
            let db = 20.0 * magnitude.max(1e-10).log10();
            // Smooth with previous value
            self.magnitudes[i] = self.magnitudes[i] * 0.8 + db * 0.2;
        }
    }

    /// Get magnitude at a specific bin
    pub fn magnitude(&self, bin: usize) -> f64 {
        self.magnitudes.get(bin).copied().unwrap_or(f64::NEG_INFINITY)
    }

    /// Get all magnitudes
    pub fn magnitudes(&self) -> &[f64] {
        &self.magnitudes
    }

    /// Get frequency for a bin index
    pub fn bin_to_freq(&self, bin: usize, sample_rate: f64) -> f64 {
        bin as f64 * sample_rate / self.fft_size as f64
    }

    /// Get bin index for a frequency
    pub fn freq_to_bin(&self, freq: f64, sample_rate: f64) -> usize {
        ((freq * self.fft_size as f64) / sample_rate).round() as usize
    }

    pub fn fft_size(&self) -> usize {
        self.fft_size
    }

    pub fn bin_count(&self) -> usize {
        self.magnitudes.len()
    }

    pub fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.magnitudes.fill(f64::NEG_INFINITY);
        self.write_pos = 0;
    }
}

/// Peak meter with hold
#[derive(Debug, Clone)]
pub struct PeakMeter {
    current_peak: f64,
    held_peak: f64,
    hold_samples: usize,
    hold_counter: usize,
    release_coeff: f64,
}

impl PeakMeter {
    pub fn new(sample_rate: f64) -> Self {
        // Validate sample rate
        let sr = if sample_rate > 0.0 && sample_rate.is_finite() {
            sample_rate
        } else {
            DEFAULT_SAMPLE_RATE
        };
        Self {
            current_peak: 0.0,
            held_peak: 0.0,
            hold_samples: (sr * 2.0) as usize, // 2 second hold
            hold_counter: 0,
            release_coeff: (-1.0 / (0.3 * sr)).exp(), // 300ms release
        }
    }

    pub fn process(&mut self, sample: Sample) {
        let abs = sample.abs();

        // Update current peak
        if abs > self.current_peak {
            self.current_peak = abs;
        } else {
            self.current_peak *= self.release_coeff;
        }

        // Update held peak
        if abs > self.held_peak {
            self.held_peak = abs;
            self.hold_counter = 0;
        } else {
            self.hold_counter += 1;
            if self.hold_counter >= self.hold_samples {
                self.held_peak *= self.release_coeff;
            }
        }
    }

    pub fn process_block(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.process(sample);
        }
    }

    pub fn current_db(&self) -> f64 {
        20.0 * self.current_peak.max(1e-10).log10()
    }

    pub fn held_db(&self) -> f64 {
        20.0 * self.held_peak.max(1e-10).log10()
    }

    pub fn reset(&mut self) {
        self.current_peak = 0.0;
        self.held_peak = 0.0;
        self.hold_counter = 0;
    }

    pub fn reset_held(&mut self) {
        self.held_peak = self.current_peak;
        self.hold_counter = 0;
    }
}

/// RMS meter
#[derive(Debug, Clone)]
pub struct RmsMeter {
    sum_squares: f64,
    window_samples: usize,
    buffer: Vec<f64>,
    write_pos: usize,
}

impl RmsMeter {
    pub fn new(sample_rate: f64, window_ms: f64) -> Self {
        // Validate sample rate
        let sr = if sample_rate > 0.0 && sample_rate.is_finite() {
            sample_rate
        } else {
            DEFAULT_SAMPLE_RATE
        };
        // Validate window (1ms to 1000ms)
        let window = if window_ms.is_finite() {
            window_ms.clamp(1.0, 1000.0)
        } else {
            300.0
        };
        let window_samples = ((window * 0.001 * sr) as usize).max(1);
        Self {
            sum_squares: 0.0,
            window_samples,
            buffer: vec![0.0; window_samples],
            write_pos: 0,
        }
    }

    pub fn process(&mut self, sample: Sample) {
        let squared = sample * sample;

        // Remove old value, add new
        self.sum_squares -= self.buffer[self.write_pos];
        self.sum_squares += squared;
        self.buffer[self.write_pos] = squared;

        self.write_pos = (self.write_pos + 1) % self.window_samples;
    }

    pub fn process_block(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.process(sample);
        }
    }

    pub fn rms(&self) -> f64 {
        (self.sum_squares / self.window_samples as f64).sqrt()
    }

    pub fn rms_db(&self) -> f64 {
        20.0 * self.rms().max(1e-10).log10()
    }

    pub fn reset(&mut self) {
        self.sum_squares = 0.0;
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }
}

/// True peak detector with oversampling
#[derive(Debug, Clone)]
pub struct TruePeakMeter {
    /// 4x oversampling filter coefficients (FIR)
    filter_coeffs: Vec<f64>,
    /// Filter state for each phase
    filter_state: Vec<f64>,
    current_true_peak: f64,
    held_true_peak: f64,
    hold_samples: usize,
    hold_counter: usize,
    release_coeff: f64,
}

impl TruePeakMeter {
    pub fn new(sample_rate: f64) -> Self {
        // Validate sample rate
        let sr = if sample_rate > 0.0 && sample_rate.is_finite() {
            sample_rate
        } else {
            DEFAULT_SAMPLE_RATE
        };

        // Simple 4-tap polyphase filter for 4x oversampling
        // In production, use a proper sinc-windowed filter
        let filter_coeffs = vec![
            0.0, 0.25, 0.5, 0.75, 1.0, 0.75, 0.5, 0.25,
        ];

        Self {
            filter_coeffs,
            filter_state: vec![0.0; 4],
            current_true_peak: 0.0,
            held_true_peak: 0.0,
            hold_samples: (sr * 2.0) as usize,
            hold_counter: 0,
            release_coeff: (-1.0 / (0.3 * sr)).exp(),
        }
    }

    pub fn process(&mut self, sample: Sample) {
        // Shift state
        self.filter_state.rotate_right(1);
        self.filter_state[0] = sample;

        // Calculate 4 interpolated samples
        for phase in 0..4 {
            let mut interpolated = 0.0;
            for (i, &state) in self.filter_state.iter().enumerate() {
                let coeff_idx = phase + i * 2;
                if coeff_idx < self.filter_coeffs.len() {
                    interpolated += state * self.filter_coeffs[coeff_idx];
                }
            }

            let abs = interpolated.abs();
            if abs > self.current_true_peak {
                self.current_true_peak = abs;
            }
            if abs > self.held_true_peak {
                self.held_true_peak = abs;
                self.hold_counter = 0;
            }
        }

        // Release
        self.current_true_peak *= self.release_coeff;
        self.hold_counter += 1;
        if self.hold_counter >= self.hold_samples {
            self.held_true_peak *= self.release_coeff;
        }
    }

    pub fn current_dbtp(&self) -> f64 {
        20.0 * self.current_true_peak.max(1e-10).log10()
    }

    pub fn held_dbtp(&self) -> f64 {
        20.0 * self.held_true_peak.max(1e-10).log10()
    }

    pub fn reset(&mut self) {
        self.filter_state.fill(0.0);
        self.current_true_peak = 0.0;
        self.held_true_peak = 0.0;
        self.hold_counter = 0;
    }
}

/// LUFS meter (EBU R128)
#[derive(Debug, Clone)]
pub struct LufsMeter {
    /// Pre-filter (high shelf)
    pre_filter_state: [f64; 2],
    /// High-pass filter state
    hp_filter_state: [f64; 2],
    /// Momentary loudness window (400ms)
    momentary_buffer: Vec<f64>,
    momentary_pos: usize,
    momentary_sum: f64,
    /// Short-term loudness window (3s)
    short_term_buffer: Vec<f64>,
    short_term_pos: usize,
    short_term_sum: f64,
    /// Integrated loudness
    integrated_sum: f64,
    integrated_count: u64,
    sample_rate: f64,
}

impl LufsMeter {
    pub fn new(sample_rate: f64) -> Self {
        // Validate sample rate
        let sr = if sample_rate > 0.0 && sample_rate.is_finite() {
            sample_rate
        } else {
            DEFAULT_SAMPLE_RATE
        };

        let momentary_samples = ((0.4 * sr) as usize).max(1);
        let short_term_samples = ((3.0 * sr) as usize).max(1);

        Self {
            pre_filter_state: [0.0; 2],
            hp_filter_state: [0.0; 2],
            momentary_buffer: vec![0.0; momentary_samples],
            momentary_pos: 0,
            momentary_sum: 0.0,
            short_term_buffer: vec![0.0; short_term_samples],
            short_term_pos: 0,
            short_term_sum: 0.0,
            integrated_sum: 0.0,
            integrated_count: 0,
            sample_rate: sr,
        }
    }

    /// Apply K-weighting filter
    fn k_weight(&mut self, sample: Sample) -> f64 {
        // Simplified K-weighting (proper implementation needs exact ITU coefficients)
        // Stage 1: Pre-filter (high shelf +4dB @ 1681Hz)
        let pre_a1 = -1.69065929318241;
        let pre_a2 = 0.73248077421585;
        let pre_b0 = 1.53512485958697;
        let pre_b1 = -2.69169618940638;
        let pre_b2 = 1.19839281085285;

        let pre_out = pre_b0 * sample + self.pre_filter_state[0];
        self.pre_filter_state[0] = pre_b1 * sample - pre_a1 * pre_out + self.pre_filter_state[1];
        self.pre_filter_state[1] = pre_b2 * sample - pre_a2 * pre_out;

        // Stage 2: High-pass filter (38.13Hz)
        let hp_a1 = -1.99004745483398;
        let hp_a2 = 0.99007225036621;
        let hp_b0 = 1.0;
        let hp_b1 = -2.0;
        let hp_b2 = 1.0;

        let hp_out = hp_b0 * pre_out + self.hp_filter_state[0];
        self.hp_filter_state[0] = hp_b1 * pre_out - hp_a1 * hp_out + self.hp_filter_state[1];
        self.hp_filter_state[1] = hp_b2 * pre_out - hp_a2 * hp_out;

        hp_out
    }

    pub fn process(&mut self, sample: Sample) {
        let weighted = self.k_weight(sample);
        let squared = weighted * weighted;

        // Momentary (400ms)
        self.momentary_sum -= self.momentary_buffer[self.momentary_pos];
        self.momentary_sum += squared;
        self.momentary_buffer[self.momentary_pos] = squared;
        self.momentary_pos = (self.momentary_pos + 1) % self.momentary_buffer.len();

        // Short-term (3s)
        self.short_term_sum -= self.short_term_buffer[self.short_term_pos];
        self.short_term_sum += squared;
        self.short_term_buffer[self.short_term_pos] = squared;
        self.short_term_pos = (self.short_term_pos + 1) % self.short_term_buffer.len();

        // Integrated (gated)
        // For proper implementation, apply -70 LUFS absolute gate
        // and -10 LU relative gate
        self.integrated_sum += squared;
        self.integrated_count += 1;
    }

    pub fn process_block(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.process(sample);
        }
    }

    /// Momentary loudness (400ms window)
    pub fn momentary(&self) -> f64 {
        let mean = self.momentary_sum / self.momentary_buffer.len() as f64;
        -0.691 + 10.0 * mean.max(1e-10).log10()
    }

    /// Short-term loudness (3s window)
    pub fn short_term(&self) -> f64 {
        let mean = self.short_term_sum / self.short_term_buffer.len() as f64;
        -0.691 + 10.0 * mean.max(1e-10).log10()
    }

    /// Integrated loudness (entire program)
    pub fn integrated(&self) -> f64 {
        if self.integrated_count == 0 {
            return f64::NEG_INFINITY;
        }
        let mean = self.integrated_sum / self.integrated_count as f64;
        -0.691 + 10.0 * mean.max(1e-10).log10()
    }

    pub fn reset(&mut self) {
        self.pre_filter_state = [0.0; 2];
        self.hp_filter_state = [0.0; 2];
        self.momentary_buffer.fill(0.0);
        self.momentary_pos = 0;
        self.momentary_sum = 0.0;
        self.short_term_buffer.fill(0.0);
        self.short_term_pos = 0;
        self.short_term_sum = 0.0;
        self.integrated_sum = 0.0;
        self.integrated_count = 0;
    }

    pub fn reset_integrated(&mut self) {
        self.integrated_sum = 0.0;
        self.integrated_count = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_peak_meter() {
        let mut meter = PeakMeter::new(48000.0);

        meter.process(0.5);
        assert!(meter.current_db() > -7.0); // ~-6dB

        meter.process(1.0);
        assert!(meter.current_db() > -0.1); // ~0dB
    }

    #[test]
    fn test_rms_meter() {
        let mut meter = RmsMeter::new(48000.0, 300.0);

        // DC signal of 1.0 should give RMS of 1.0
        for _ in 0..48000 {
            meter.process(1.0);
        }
        assert!((meter.rms() - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_fft_analyzer() {
        let mut analyzer = FftAnalyzer::new(1024);

        // Push a sine wave
        let freq = 1000.0;
        let sample_rate = 48000.0;
        for i in 0..1024 {
            let sample = (2.0 * std::f64::consts::PI * freq * i as f64 / sample_rate).sin();
            analyzer.push_samples(&[sample]);
        }

        analyzer.analyze();

        // Should have a peak near 1kHz
        let peak_bin = analyzer.freq_to_bin(freq, sample_rate);
        assert!(analyzer.magnitude(peak_bin) > analyzer.magnitude(peak_bin + 10));
    }
}

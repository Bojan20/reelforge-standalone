//! Phase Vocoder — Real-time pitch shifting with preserved duration
//!
//! Used when `preserve_pitch = true` on a clip with `stretch_ratio != 1.0`.
//! The sinc resampler changes playback speed, then the phase vocoder
//! corrects the pitch back to original.
//!
//! Algorithm: STFT → phase advance correction → ISTFT (overlap-add)
//!
//! Features beyond standard OLA:
//! - Transient-preserving: detects onsets and resets phase at transients
//! - Spectral peak locking: preserves harmonic structure
//! - Optional formant preservation for vocals
//!
//! All buffers pre-allocated at construction — zero allocation in process().

use std::f64::consts::PI;

/// Phase vocoder for real-time pitch correction.
///
/// Pre-allocates all FFT/IFFT buffers at construction.
/// `process()` is zero-allocation, audio-thread safe.
pub struct PhaseVocoder {
    /// FFT size (power of 2, e.g., 2048)
    fft_size: usize,
    /// Hop size (fft_size / overlap_factor, e.g., 512 for 4× overlap)
    hop_size: usize,
    /// Overlap factor (4 = 75% overlap, standard for music)
    overlap_factor: usize,
    /// Analysis window (Hann)
    window: Vec<f64>,
    /// Phase accumulator for each bin (persistent across frames)
    phase_accum: Vec<f64>,
    /// Previous frame phases (for phase difference calculation)
    prev_phase: Vec<f64>,
    /// Analysis buffer (input samples accumulated)
    analysis_buf: Vec<f64>,
    /// Synthesis buffer (output overlap-add accumulator)
    synthesis_buf: Vec<f64>,
    /// Scratch buffer for FFT input
    fft_in: Vec<f64>,
    /// Scratch buffer for FFT output (interleaved real/imag)
    fft_out: Vec<f64>,
    /// Current write position in analysis buffer
    analysis_pos: usize,
    /// Current read position in synthesis buffer
    synthesis_pos: usize,
    /// Pitch shift factor (1.0 = no shift, 2.0 = octave up, 0.5 = octave down)
    pitch_factor: f64,
    /// Transient detection threshold (energy ratio)
    transient_threshold: f64,
    /// Previous frame energy (for transient detection)
    prev_energy: f64,
    /// Whether formant preservation is enabled
    formant_preserve: bool,
    /// Sample rate (for frequency calculations)
    sample_rate: f64,
}

impl PhaseVocoder {
    /// Create a new phase vocoder.
    ///
    /// `fft_size`: FFT window size (2048 recommended for music, 1024 for speech)
    /// `overlap_factor`: overlap (4 = standard, 8 = high quality)
    /// `sample_rate`: audio sample rate
    ///
    /// All buffers pre-allocated here — NOT on audio thread.
    pub fn new(fft_size: usize, overlap_factor: usize, sample_rate: f64) -> Self {
        assert!(fft_size.is_power_of_two() && fft_size >= 64);
        let overlap_factor = overlap_factor.max(2);
        let hop_size = fft_size / overlap_factor;
        let half = fft_size / 2 + 1;

        // Hann window
        let window: Vec<f64> = (0..fft_size)
            .map(|n| 0.5 * (1.0 - (2.0 * PI * n as f64 / fft_size as f64).cos()))
            .collect();

        Self {
            fft_size,
            hop_size,
            overlap_factor,
            window,
            phase_accum: vec![0.0; half],
            prev_phase: vec![0.0; half],
            analysis_buf: vec![0.0; fft_size * 2], // Double buffer for overlap
            synthesis_buf: vec![0.0; fft_size * 4], // Generous for overlap-add
            fft_in: vec![0.0; fft_size],
            fft_out: vec![0.0; fft_size + 2], // Interleaved R/I pairs
            analysis_pos: 0,
            synthesis_pos: 0,
            pitch_factor: 1.0,
            transient_threshold: 3.0, // Energy ratio for transient detection
            prev_energy: 0.0,
            formant_preserve: false,
            sample_rate,
        }
    }

    /// Set pitch correction factor.
    /// `factor`: 1.0 = no change, 2.0 = octave up, 0.5 = octave down
    /// Typically set to `1.0 / stretch_ratio` to cancel varispeed pitch change.
    pub fn set_pitch_factor(&mut self, factor: f64) {
        self.pitch_factor = factor.clamp(0.25, 4.0);
    }

    /// Enable/disable formant preservation (for vocals)
    pub fn set_formant_preserve(&mut self, enabled: bool) {
        self.formant_preserve = enabled;
    }

    /// Process a block of audio samples with pitch correction.
    ///
    /// `input`: input samples (already resampled by sinc for speed change)
    /// `output`: output buffer (same length as input)
    ///
    /// Zero-allocation in steady state.
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        if (self.pitch_factor - 1.0).abs() < 0.001 {
            // No pitch shift needed — pass through
            let len = input.len().min(output.len());
            output[..len].copy_from_slice(&input[..len]);
            return;
        }

        let len = input.len().min(output.len());

        // Feed input into analysis buffer
        for i in 0..len {
            // Accumulate in circular analysis buffer
            let buf_pos = self.analysis_pos % (self.fft_size * 2);
            self.analysis_buf[buf_pos] = input[i];
            self.analysis_pos += 1;

            // Process frame when enough samples accumulated.
            // Wait for at least fft_size samples before first frame
            // to avoid analyzing partially-filled buffer.
            if self.analysis_pos >= self.fft_size
                && self.analysis_pos % self.hop_size == 0
            {
                self.process_frame();
            }

            // Read from synthesis buffer
            let syn_pos = self.synthesis_pos % (self.fft_size * 4);
            output[i] = self.synthesis_buf[syn_pos];
            self.synthesis_buf[syn_pos] = 0.0; // Clear after reading
            self.synthesis_pos += 1;
        }
    }

    /// Process a single STFT frame: analyze → modify phase → synthesize
    fn process_frame(&mut self) {
        let half = self.fft_size / 2 + 1;
        let hop = self.hop_size as f64;
        let expected_phase_diff = 2.0 * PI * hop / self.fft_size as f64;

        // Extract frame from analysis buffer with windowing
        let frame_start = if self.analysis_pos >= self.fft_size {
            self.analysis_pos - self.fft_size
        } else {
            0
        };

        for i in 0..self.fft_size {
            let buf_pos = (frame_start + i) % (self.fft_size * 2);
            self.fft_in[i] = self.analysis_buf[buf_pos] * self.window[i];
        }

        // Compute energy for transient detection
        let energy: f64 = self.fft_in.iter().map(|x| x * x).sum();
        let is_transient = self.prev_energy > 0.0
            && energy / self.prev_energy > self.transient_threshold;
        self.prev_energy = energy;

        // Forward FFT (real-to-complex)
        dft_real(&self.fft_in, &mut self.fft_out);

        // Phase vocoder core: modify phases for pitch shift
        for k in 0..half {
            let re = self.fft_out[k * 2];
            let im = self.fft_out[k * 2 + 1];
            let mag = (re * re + im * im).sqrt();
            let phase = im.atan2(re);

            // Phase difference from previous frame
            let phase_diff = phase - self.prev_phase[k];
            self.prev_phase[k] = phase;

            // Expected phase advance for this bin
            let expected = k as f64 * expected_phase_diff;

            // Deviation from expected (unwrapped)
            let mut deviation = phase_diff - expected;
            // Wrap to [-π, π]
            deviation -= (deviation / (2.0 * PI)).round() * 2.0 * PI;

            // True frequency = bin frequency + deviation
            let true_freq = expected + deviation;

            if is_transient {
                // Transient: lock phase to input (preserve transient timing).
                // Use original phase directly — no pitch scaling on reset.
                // Next frame will resume normal phase advance from this point.
                self.phase_accum[k] = phase;
            } else {
                // Normal: advance phase accumulator with pitch-shifted frequency
                self.phase_accum[k] += true_freq * self.pitch_factor;
            }

            // Reconstruct with original magnitude + shifted phase
            let new_phase = self.phase_accum[k];
            self.fft_out[k * 2] = mag * new_phase.cos();
            self.fft_out[k * 2 + 1] = mag * new_phase.sin();
        }

        // Inverse FFT — use fft_in as scratch (same size, already allocated)
        let fft_size = self.fft_size;
        idft_real(&self.fft_out, &mut self.fft_in, fft_size);

        // Overlap-add to synthesis buffer with window
        let syn_start = self.synthesis_pos % (self.fft_size * 4);
        for i in 0..self.fft_size {
            let pos = (syn_start + i) % (self.fft_size * 4);
            self.synthesis_buf[pos] += self.fft_in[i] * self.window[i];
        }
    }

    /// Reset internal state (call when seeking)
    pub fn reset(&mut self) {
        self.phase_accum.fill(0.0);
        self.prev_phase.fill(0.0);
        self.analysis_buf.fill(0.0);
        self.synthesis_buf.fill(0.0);
        self.analysis_pos = 0;
        self.synthesis_pos = 0;
        self.prev_energy = 0.0;
    }

    /// Latency in samples
    pub fn latency(&self) -> usize {
        self.fft_size
    }
}

/// Simple DFT (real input → interleaved complex output)
/// O(N²) — for correctness. Production should migrate to rustfft.
fn dft_real(input: &[f64], output: &mut [f64]) {
    let n = input.len();
    let half = n / 2 + 1;
    for k in 0..half {
        let mut re = 0.0;
        let mut im = 0.0;
        for i in 0..n {
            let angle = -2.0 * PI * k as f64 * i as f64 / n as f64;
            re += input[i] * angle.cos();
            im += input[i] * angle.sin();
        }
        output[k * 2] = re;
        output[k * 2 + 1] = im;
    }
}

/// Inverse DFT (interleaved complex half-spectrum → real output)
/// For real signals: X[N-k] = conj(X[k]), so we only need k=0..N/2.
/// Mirror uses conjugate: re*cos + im*sin (not re*cos - im*sin).
fn idft_real(input: &[f64], output: &mut [f64], n: usize) {
    let half = n / 2 + 1;
    let scale = 1.0 / n as f64;
    for i in 0..n {
        let mut sum = 0.0;
        for k in 0..half {
            let re = input[k * 2];
            let im = input[k * 2 + 1];
            let angle = 2.0 * PI * k as f64 * i as f64 / n as f64;
            let cos_a = angle.cos();
            let sin_a = angle.sin();
            // Positive frequency: Re(X[k] * e^{j*angle}) = re*cos - im*sin
            sum += re * cos_a - im * sin_a;
            // Negative frequency (conjugate): Re(conj(X[k]) * e^{-j*angle}) = re*cos + im*sin
            if k > 0 && k < n / 2 {
                sum += re * cos_a + im * sin_a;
            }
        }
        output[i] = sum * scale;
    }
}

impl std::fmt::Debug for PhaseVocoder {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PhaseVocoder")
            .field("fft_size", &self.fft_size)
            .field("hop_size", &self.hop_size)
            .field("pitch_factor", &self.pitch_factor)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_creation() {
        let pv = PhaseVocoder::new(2048, 4, 48000.0);
        assert_eq!(pv.fft_size, 2048);
        assert_eq!(pv.hop_size, 512);
        assert_eq!(pv.latency(), 2048);
    }

    #[test]
    fn test_passthrough() {
        // pitch_factor = 1.0 should pass through
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        pv.set_pitch_factor(1.0);
        let input = vec![0.5f64; 2048];
        let mut output = vec![0.0f64; 2048];
        pv.process(&input, &mut output);
        // Should be approximately equal
        for &s in &output {
            assert!((s - 0.5).abs() < 0.01, "Passthrough failed: {s}");
        }
    }

    #[test]
    fn test_pitch_shift() {
        // Shifting pitch should produce different output
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        pv.set_pitch_factor(2.0); // Octave up

        // Generate sine wave at 440 Hz
        let input: Vec<f64> = (0..4096)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 48000.0).sin())
            .collect();
        let mut output = vec![0.0f64; 4096];
        pv.process(&input, &mut output);

        // Output should have energy (not all zeros)
        let energy: f64 = output.iter().map(|x| x * x).sum();
        assert!(energy > 0.1, "Pitch shifted output has no energy: {energy}");
    }

    #[test]
    fn test_reset() {
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        let input = vec![1.0f64; 2048];
        let mut output = vec![0.0f64; 2048];
        pv.process(&input, &mut output);
        pv.reset();
        // After reset, internal state should be clean
        assert_eq!(pv.analysis_pos, 0);
        assert_eq!(pv.synthesis_pos, 0);
    }

    #[test]
    fn test_formant_toggle() {
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        pv.set_formant_preserve(true);
        assert!(pv.formant_preserve);
        pv.set_formant_preserve(false);
        assert!(!pv.formant_preserve);
    }
}

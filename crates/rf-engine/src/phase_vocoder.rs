//! Phase Vocoder — Real-time pitch shifting with preserved duration
//!
//! Used when `preserve_pitch = true` on a clip with `stretch_ratio != 1.0`.
//! The sinc resampler changes playback speed, then the phase vocoder
//! corrects the pitch back to original.
//!
//! Algorithm: STFT → phase advance correction → ISTFT (overlap-add)
//!
//! Features:
//! - Transient-preserving: detects onsets and resets phase at transients
//! - Pre-allocated FFT plans via rustfft — O(N log N)
//! - All buffers pre-allocated at construction — zero allocation in process()

use std::f64::consts::PI;
use rustfft::{FftPlanner, num_complex::Complex64};

/// Phase vocoder for real-time pitch correction.
///
/// Pre-allocates all FFT/IFFT plans and buffers at construction.
/// `process()` is zero-allocation, audio-thread safe.
pub struct PhaseVocoder {
    /// FFT size (power of 2, e.g., 2048)
    fft_size: usize,
    /// Hop size (fft_size / overlap_factor)
    hop_size: usize,
    /// Analysis window (Hann)
    window: Vec<f64>,
    /// Phase accumulator for each bin (persistent across frames)
    phase_accum: Vec<f64>,
    /// Previous frame phases (for phase difference calculation)
    prev_phase: Vec<f64>,
    /// Analysis buffer (circular, input samples accumulated)
    analysis_buf: Vec<f64>,
    /// Synthesis buffer (circular, output overlap-add accumulator)
    synthesis_buf: Vec<f64>,
    /// Complex FFT buffer (pre-allocated for rustfft in-place)
    fft_buf: Vec<Complex64>,
    /// Forward FFT plan (pre-computed, reusable)
    fft_forward: std::sync::Arc<dyn rustfft::Fft<f64>>,
    /// Inverse FFT plan (pre-computed, reusable)
    fft_inverse: std::sync::Arc<dyn rustfft::Fft<f64>>,
    /// FFT normalization scale (1/N for IFFT)
    fft_scale: f64,
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
    /// Pre-allocated magnitude buffer for frequency bin resampling
    mag_buf: Vec<f64>,
    /// Pre-allocated frequency buffer for frequency bin resampling
    freq_buf: Vec<f64>,
    /// Pre-allocated buffer for spectral envelope extraction (cepstral method)
    /// Stores log-magnitude spectrum for cepstral analysis
    envelope_buf: Vec<Complex64>,
    /// Original spectral envelope (magnitudes before pitch shift)
    orig_envelope: Vec<f64>,
    /// Shifted spectral envelope (magnitudes after pitch shift, for correction)
    shifted_envelope: Vec<f64>,
    /// Cepstral lifter order (number of cepstral coefficients to keep)
    /// Higher = more detail, lower = smoother envelope. 30-60 typical for music.
    cepstral_order: usize,
}

impl PhaseVocoder {
    /// Create a new phase vocoder.
    ///
    /// `fft_size`: FFT window size (2048 recommended for music, 1024 for speech)
    /// `overlap_factor`: overlap (4 = standard, 8 = high quality)
    /// `sample_rate`: audio sample rate (unused currently, reserved for formants)
    ///
    /// All buffers AND FFT plans pre-allocated here — NOT on audio thread.
    pub fn new(fft_size: usize, overlap_factor: usize, _sample_rate: f64) -> Self {
        assert!(fft_size.is_power_of_two() && fft_size >= 64);
        let overlap_factor = overlap_factor.max(2);
        let hop_size = fft_size / overlap_factor;
        let half = fft_size / 2 + 1;

        // Hann window
        let window: Vec<f64> = (0..fft_size)
            .map(|n| 0.5 * (1.0 - (2.0 * PI * n as f64 / fft_size as f64).cos()))
            .collect();

        // Pre-compute FFT plans (heavy allocation — done once, not on audio thread)
        let mut planner = FftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        Self {
            fft_size,
            hop_size,
            window,
            phase_accum: vec![0.0; half],
            prev_phase: vec![0.0; half],
            analysis_buf: vec![0.0; fft_size * 2],
            synthesis_buf: vec![0.0; fft_size * 4],
            fft_buf: vec![Complex64::new(0.0, 0.0); fft_size],
            fft_forward,
            fft_inverse,
            // fft_scale includes COLA normalization for Hann^2 window:
            // For overlap_factor=4, sum of overlapping Hann^2 windows = 1.5
            // For overlap_factor=2, sum = 1.0 (no correction needed)
            // General formula: sum = overlap_factor / 4 * 1.5 for Hann, but compute exactly:
            fft_scale: {
                // Compute COLA sum for Hann^2 at this overlap
                let mut cola_sum = 0.0_f64;
                for n in 0..hop_size {
                    let mut s = 0.0;
                    for k in 0..overlap_factor {
                        let idx = n + k * hop_size;
                        if idx < fft_size {
                            let w = 0.5 * (1.0 - (2.0 * PI * idx as f64 / fft_size as f64).cos());
                            s += w * w; // analysis window * synthesis window
                        }
                    }
                    cola_sum += s;
                }
                cola_sum /= hop_size as f64;
                // Scale = (1/N) / COLA to compensate both IFFT and overlap-add gain
                if cola_sum > 0.0 { 1.0 / (fft_size as f64 * cola_sum) } else { 1.0 / fft_size as f64 }
            },
            analysis_pos: 0,
            synthesis_pos: 0,
            pitch_factor: 1.0,
            transient_threshold: 3.0,
            prev_energy: 0.0,
            formant_preserve: false,
            mag_buf: vec![0.0; half],
            freq_buf: vec![0.0; half],
            envelope_buf: vec![Complex64::new(0.0, 0.0); fft_size],
            orig_envelope: vec![0.0; half],
            shifted_envelope: vec![0.0; half],
            cepstral_order: 40, // good default for music at 2048 FFT / 48kHz
        }
    }

    /// Set pitch correction factor.
    /// `factor`: 1.0 = no change, 2.0 = octave up, 0.5 = octave down
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
    /// Zero-allocation — all FFT work uses pre-allocated buffers.
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        if (self.pitch_factor - 1.0).abs() < 0.001 {
            let len = input.len().min(output.len());
            output[..len].copy_from_slice(&input[..len]);
            return;
        }

        let len = input.len().min(output.len());

        for i in 0..len {
            let buf_pos = self.analysis_pos % (self.fft_size * 2);
            self.analysis_buf[buf_pos] = input[i];
            self.analysis_pos += 1;

            if self.analysis_pos >= self.fft_size
                && self.analysis_pos % self.hop_size == 0
            {
                self.process_frame();
            }

            let syn_pos = self.synthesis_pos % (self.fft_size * 4);
            output[i] = self.synthesis_buf[syn_pos];
            self.synthesis_buf[syn_pos] = 0.0;
            self.synthesis_pos += 1;
        }
    }

    /// Process a single STFT frame using rustfft
    fn process_frame(&mut self) {
        let half = self.fft_size / 2 + 1;
        let hop = self.hop_size as f64;
        let expected_phase_diff = 2.0 * PI * hop / self.fft_size as f64;

        // Extract frame from analysis buffer with windowing → complex FFT buffer
        let frame_start = self.analysis_pos - self.fft_size;
        for i in 0..self.fft_size {
            let buf_pos = (frame_start + i) % (self.fft_size * 2);
            self.fft_buf[i] = Complex64::new(
                self.analysis_buf[buf_pos] * self.window[i],
                0.0,
            );
        }

        // Transient detection (energy of windowed frame)
        let energy: f64 = self.fft_buf.iter().map(|c| c.re * c.re).sum();
        let is_transient = self.prev_energy > 0.0
            && energy / self.prev_energy > self.transient_threshold;
        self.prev_energy = energy;

        // Forward FFT — O(N log N) via rustfft, in-place, zero-allocation
        self.fft_forward.process(&mut self.fft_buf);

        // Extract original spectral envelope BEFORE pitch shift (for formant preservation)
        // Uses cepstral smoothing: log-mag → IFFT → lifter → FFT → exp
        if self.formant_preserve {
            // Store raw magnitudes in orig_envelope, then smooth in-place
            for k in 0..half {
                let re = self.fft_buf[k].re;
                let im = self.fft_buf[k].im;
                self.orig_envelope[k] = (re * re + im * im).sqrt().max(1e-20);
            }
            Self::cepstral_envelope_inplace(
                &mut self.orig_envelope[..half],
                &mut self.envelope_buf,
                &self.fft_forward,
                &self.fft_inverse,
                self.fft_size,
                self.cepstral_order,
            );
        }

        // Phase vocoder core: phase advance with pitch_factor as synthesis hop multiplier
        // This performs TIME STRETCHING — changes duration without changing pitch.
        // pitch_factor > 1.0 = longer output (slower), < 1.0 = shorter (faster)
        //
        // For pitch shift: caller plays source at different rate (varispeed),
        // then PV time-corrects back to original duration.
        // Example: pitch up 1 octave = play source 2x faster, PV stretches 2x → same duration, higher pitch
        for k in 0..half {
            let re = self.fft_buf[k].re;
            let im = self.fft_buf[k].im;
            let mag = (re * re + im * im).sqrt();
            let phase = im.atan2(re);

            let phase_diff = phase - self.prev_phase[k];
            self.prev_phase[k] = phase;

            let expected = k as f64 * expected_phase_diff;
            let mut deviation = phase_diff - expected;
            deviation -= (deviation / (2.0 * PI)).round() * 2.0 * PI;
            let true_freq = expected + deviation;

            if is_transient {
                self.phase_accum[k] = phase;
            } else {
                // Scale phase advance by pitch_factor — this is the synthesis hop stretch
                self.phase_accum[k] += true_freq * self.pitch_factor;
            }

            let new_phase = self.phase_accum[k];
            self.fft_buf[k] = Complex64::new(mag * new_phase.cos(), mag * new_phase.sin());
        }

        // Formant preservation: correct magnitudes to restore original spectral envelope
        if self.formant_preserve {
            // Extract shifted envelope
            for k in 0..half {
                let re = self.fft_buf[k].re;
                let im = self.fft_buf[k].im;
                self.shifted_envelope[k] = (re * re + im * im).sqrt().max(1e-20);
            }
            Self::cepstral_envelope_inplace(
                &mut self.shifted_envelope[..half],
                &mut self.envelope_buf,
                &self.fft_forward,
                &self.fft_inverse,
                self.fft_size,
                self.cepstral_order,
            );

            // Apply correction: scale magnitudes so envelope matches original
            for k in 0..half {
                if self.shifted_envelope[k] > 1e-20 {
                    let correction = self.orig_envelope[k] / self.shifted_envelope[k];
                    // Clamp to prevent extreme gains (max 20dB boost)
                    let correction = correction.clamp(0.1, 10.0);
                    let re = self.fft_buf[k].re;
                    let im = self.fft_buf[k].im;
                    self.fft_buf[k] = Complex64::new(re * correction, im * correction);
                }
            }
        }

        // Mirror negative frequencies (conjugate symmetry for real output)
        for k in 1..self.fft_size / 2 {
            let mirror = self.fft_size - k;
            self.fft_buf[mirror] = Complex64::new(self.fft_buf[k].re, -self.fft_buf[k].im);
        }

        // Inverse FFT — O(N log N), in-place
        self.fft_inverse.process(&mut self.fft_buf);

        // Overlap-add to synthesis buffer (with window and IFFT normalization)
        let syn_start = self.synthesis_pos % (self.fft_size * 4);
        for i in 0..self.fft_size {
            let pos = (syn_start + i) % (self.fft_size * 4);
            self.synthesis_buf[pos] += self.fft_buf[i].re * self.fft_scale * self.window[i];
        }
    }

    /// Reset internal state (call when seeking)
    /// Compute smoothed spectral envelope in-place via cepstral method.
    ///
    /// `magnitudes`: input magnitudes (overwritten with smoothed envelope)
    /// `work_buf`: pre-allocated complex buffer (>= fft_size)
    ///
    /// Algorithm: log-mag → IFFT → lifter → FFT → exp
    /// Zero-allocation: uses pre-allocated `work_buf`.
    fn cepstral_envelope_inplace(
        magnitudes: &mut [f64],
        work_buf: &mut [Complex64],
        fft_fwd: &std::sync::Arc<dyn rustfft::Fft<f64>>,
        fft_inv: &std::sync::Arc<dyn rustfft::Fft<f64>>,
        fft_size: usize,
        cepstral_order: usize,
    ) {
        let half = magnitudes.len();

        // Step 1: log-magnitude → real part of complex buffer
        for i in 0..half {
            work_buf[i] = Complex64::new(magnitudes[i].max(1e-20).ln(), 0.0);
        }
        // Mirror for full FFT (conjugate symmetry)
        for i in half..fft_size {
            let mirror = fft_size - i;
            if mirror < half {
                work_buf[i] = work_buf[mirror];
            } else {
                work_buf[i] = Complex64::new(0.0, 0.0);
            }
        }

        // Step 2: IFFT → cepstrum
        fft_inv.process(&mut work_buf[..fft_size]);
        let scale = 1.0 / fft_size as f64;
        for c in work_buf[..fft_size].iter_mut() {
            c.re *= scale;
            c.im *= scale;
        }

        // Step 3: Lifter — keep only first `cepstral_order` coefficients + DC
        // Zero out everything else (high-quefrency = fine spectral detail)
        let order = cepstral_order.min(fft_size / 2);
        for i in order..fft_size.saturating_sub(order) {
            work_buf[i] = Complex64::new(0.0, 0.0);
        }

        // Step 4: FFT → smooth log-envelope
        fft_fwd.process(&mut work_buf[..fft_size]);

        // Step 5: Exponentiate → linear smooth envelope (in-place)
        for i in 0..half {
            magnitudes[i] = work_buf[i].re.clamp(-50.0, 50.0).exp().max(1e-20);
        }
    }

    pub fn reset(&mut self) {
        self.phase_accum.fill(0.0);
        self.prev_phase.fill(0.0);
        self.mag_buf.fill(0.0);
        self.freq_buf.fill(0.0);
        self.analysis_buf.fill(0.0);
        self.synthesis_buf.fill(0.0);
        for c in &mut self.fft_buf {
            *c = Complex64::new(0.0, 0.0);
        }
        self.analysis_pos = 0;
        self.synthesis_pos = 0;
        self.prev_energy = 0.0;
        for c in &mut self.envelope_buf {
            *c = Complex64::new(0.0, 0.0);
        }
        self.orig_envelope.fill(0.0);
        self.shifted_envelope.fill(0.0);
    }

    /// Current pitch factor
    pub fn pitch_factor(&self) -> f64 {
        self.pitch_factor
    }

    /// Latency in samples
    pub fn latency(&self) -> usize {
        self.fft_size
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
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        pv.set_pitch_factor(1.0);
        let input = vec![0.5f64; 2048];
        let mut output = vec![0.0f64; 2048];
        pv.process(&input, &mut output);
        for &s in &output {
            assert!((s - 0.5).abs() < 0.01, "Passthrough failed: {s}");
        }
    }

    #[test]
    fn test_pitch_shift_produces_output() {
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        pv.set_pitch_factor(2.0);

        let input: Vec<f64> = (0..4096)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 48000.0).sin())
            .collect();
        let mut output = vec![0.0f64; 4096];
        pv.process(&input, &mut output);

        // After latency (1024 samples), output should have energy
        let energy: f64 = output[1024..].iter().map(|x| x * x).sum();
        assert!(energy > 0.1, "Pitch shifted output has no energy: {energy}");
    }

    #[test]
    fn test_reset() {
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        let input = vec![1.0f64; 2048];
        let mut output = vec![0.0f64; 2048];
        pv.process(&input, &mut output);
        pv.reset();
        assert_eq!(pv.analysis_pos, 0);
        assert_eq!(pv.synthesis_pos, 0);
    }

    #[test]
    fn test_formant_preserve_produces_output() {
        let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
        pv.set_pitch_factor(2.0);
        pv.set_formant_preserve(true);

        // 440Hz sine wave (A4)
        let input: Vec<f64> = (0..4096)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 48000.0).sin())
            .collect();
        let mut output = vec![0.0f64; 4096];
        pv.process(&input, &mut output);

        // After latency, output should have energy
        let energy: f64 = output[1024..].iter().map(|x| x * x).sum();
        assert!(energy > 0.01, "Formant-preserved output has no energy: {energy}");

        // Should not produce NaN or Inf
        assert!(output.iter().all(|x| x.is_finite()), "Output contains NaN/Inf");
    }

    #[test]
    fn test_formant_preserve_no_nan() {
        // Formant preservation should produce finite output for various pitch factors
        for &pf in &[0.5, 0.75, 1.5, 2.0] {
            let mut pv = PhaseVocoder::new(1024, 4, 48000.0);
            pv.set_pitch_factor(pf);
            pv.set_formant_preserve(true);

            let input: Vec<f64> = (0..8192)
                .map(|i| {
                    let t = i as f64 / 48000.0;
                    0.5 * (2.0 * PI * 200.0 * t).sin()
                        + 0.3 * (2.0 * PI * 400.0 * t).sin()
                        + 0.2 * (2.0 * PI * 800.0 * t).sin()
                })
                .collect();

            let mut output = vec![0.0f64; 8192];
            pv.process(&input, &mut output);

            assert!(
                output.iter().all(|x| x.is_finite()),
                "Output contains NaN/Inf for pitch_factor={pf}"
            );
            let energy: f64 = output[2048..].iter().map(|x| x * x).sum();
            assert!(energy > 0.01, "No energy for pitch_factor={pf}: {energy}");
        }
    }

    #[test]
    fn test_fft_roundtrip() {
        // Verify FFT → IFFT roundtrip produces original signal
        let n = 1024;
        let mut planner = FftPlanner::new();
        let fwd = planner.plan_fft_forward(n);
        let inv = planner.plan_fft_inverse(n);

        let mut buf: Vec<Complex64> = (0..n)
            .map(|i| Complex64::new((2.0 * PI * 10.0 * i as f64 / n as f64).sin(), 0.0))
            .collect();
        let original: Vec<f64> = buf.iter().map(|c| c.re).collect();

        fwd.process(&mut buf);
        inv.process(&mut buf);

        let scale = 1.0 / n as f64;
        for i in 0..n {
            let recovered = buf[i].re * scale;
            assert!(
                (recovered - original[i]).abs() < 1e-10,
                "FFT roundtrip failed at {i}: {recovered} vs {}",
                original[i]
            );
        }
    }
}

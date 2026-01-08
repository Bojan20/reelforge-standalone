//! # Formant Preservation Engine
//!
//! LPC-based spectral envelope extraction for pitch-independent time stretching.
//!
//! ## Algorithms
//!
//! - **LPC (Linear Predictive Coding)**: All-pole model of vocal tract
//! - **True Envelope**: Iterative refinement for accurate envelope
//! - **Cepstral smoothing**: Alternative envelope extraction

use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// LPC SOLVER
// ═══════════════════════════════════════════════════════════════════════════════

/// Levinson-Durbin recursion for LPC coefficient computation
pub struct LevinsonDurbin {
    /// Maximum LPC order
    max_order: usize,
    /// Work buffer for forward prediction errors
    forward: Vec<f64>,
    /// Work buffer for backward prediction errors
    backward: Vec<f64>,
}

impl LevinsonDurbin {
    /// Create new solver with given maximum order
    pub fn new(max_order: usize) -> Self {
        Self {
            max_order,
            forward: vec![0.0; max_order + 1],
            backward: vec![0.0; max_order + 1],
        }
    }

    /// Solve for LPC coefficients using Levinson-Durbin recursion
    ///
    /// Input: autocorrelation coefficients r[0..=order]
    /// Output: LPC coefficients a[1..=order] (a[0] is always 1.0)
    pub fn solve(&mut self, autocorr: &[f64], order: usize) -> Vec<f64> {
        let order = order.min(self.max_order).min(autocorr.len() - 1);

        if order == 0 || autocorr[0] <= 0.0 {
            return vec![1.0];
        }

        let mut a = vec![0.0; order + 1];
        a[0] = 1.0;

        let mut e = autocorr[0]; // Prediction error

        for i in 1..=order {
            // Compute reflection coefficient
            let mut lambda = autocorr[i];
            for j in 1..i {
                lambda += a[j] * autocorr[i - j];
            }

            if e.abs() < 1e-10 {
                break;
            }

            let k = -lambda / e;

            // Update coefficients (Levinson-Durbin recursion)
            self.forward[..=i].copy_from_slice(&a[..=i]);

            for j in 1..i {
                a[j] = self.forward[j] + k * self.forward[i - j];
            }
            a[i] = k;

            // Update prediction error
            e *= 1.0 - k * k;

            if e <= 0.0 {
                break; // Numerical instability
            }
        }

        a
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FORMANT PRESERVER
// ═══════════════════════════════════════════════════════════════════════════════

/// Formant preservation processor using LPC envelope extraction
pub struct FormantPreserver {
    /// Sample rate
    sample_rate: f64,
    /// LPC order (typically 24-32 for 44.1kHz)
    lpc_order: usize,
    /// Levinson-Durbin solver
    solver: LevinsonDurbin,
    /// FFT size for envelope computation
    fft_size: usize,
    /// Pre-emphasis coefficient
    pre_emphasis: f64,
    /// True envelope iteration count
    true_envelope_iterations: usize,
}

impl FormantPreserver {
    /// Create new formant preserver
    pub fn new(sample_rate: f64) -> Self {
        // LPC order based on sample rate
        // Rule: ~2 + sample_rate / 1000
        let lpc_order = (2.0 + sample_rate / 1000.0) as usize;
        let lpc_order = lpc_order.clamp(12, 48);

        Self {
            sample_rate,
            lpc_order,
            solver: LevinsonDurbin::new(lpc_order),
            fft_size: 2048,
            pre_emphasis: 0.97,
            true_envelope_iterations: 5,
        }
    }

    /// Create with custom LPC order
    pub fn with_order(sample_rate: f64, lpc_order: usize) -> Self {
        Self {
            sample_rate,
            lpc_order,
            solver: LevinsonDurbin::new(lpc_order),
            fft_size: 2048,
            pre_emphasis: 0.97,
            true_envelope_iterations: 5,
        }
    }

    /// Extract spectral envelope from audio frame
    pub fn extract_envelope(&mut self, frame: &[f64]) -> Vec<f64> {
        // 1. Pre-emphasis (boost high frequencies)
        let emphasized = self.apply_pre_emphasis(frame);

        // 2. Windowing
        let windowed = self.apply_window(&emphasized);

        // 3. Autocorrelation
        let autocorr = self.autocorrelation(&windowed, self.lpc_order + 1);

        // 4. LPC coefficients via Levinson-Durbin
        let lpc_coeffs = self.solver.solve(&autocorr, self.lpc_order);

        // 5. LPC to frequency response (envelope)
        let envelope = self.lpc_to_envelope(&lpc_coeffs);

        // 6. True envelope refinement (optional)
        if self.true_envelope_iterations > 0 {
            self.refine_true_envelope(&envelope, frame)
        } else {
            envelope
        }
    }

    /// Apply pre-emphasis filter
    fn apply_pre_emphasis(&self, input: &[f64]) -> Vec<f64> {
        let mut output = vec![0.0; input.len()];
        if !input.is_empty() {
            output[0] = input[0];
            for i in 1..input.len() {
                output[i] = input[i] - self.pre_emphasis * input[i - 1];
            }
        }
        output
    }

    /// Apply Hann window
    fn apply_window(&self, input: &[f64]) -> Vec<f64> {
        let n = input.len() as f64;
        input.iter().enumerate()
            .map(|(i, &x)| {
                let window = 0.5 * (1.0 - (2.0 * PI * i as f64 / n).cos());
                x * window
            })
            .collect()
    }

    /// Compute autocorrelation using direct method
    fn autocorrelation(&self, input: &[f64], max_lag: usize) -> Vec<f64> {
        let n = input.len();
        let mut r = vec![0.0; max_lag];

        for lag in 0..max_lag {
            let mut sum = 0.0;
            for i in lag..n {
                sum += input[i] * input[i - lag];
            }
            r[lag] = sum;
        }

        r
    }

    /// Convert LPC coefficients to frequency response (envelope)
    fn lpc_to_envelope(&self, lpc_coeffs: &[f64]) -> Vec<f64> {
        let n = self.fft_size;
        let mut envelope = vec![0.0; n / 2 + 1];

        // H(z) = gain / A(z) where A(z) = 1 + a1*z^-1 + a2*z^-2 + ...
        for (k, env) in envelope.iter_mut().enumerate() {
            let omega = 2.0 * PI * k as f64 / n as f64;

            // Evaluate A(e^jω)
            let mut a_real = 1.0;
            let mut a_imag = 0.0;

            for (i, &coeff) in lpc_coeffs.iter().enumerate().skip(1) {
                a_real += coeff * (omega * i as f64).cos();
                a_imag -= coeff * (omega * i as f64).sin();
            }

            // |H(e^jω)| = 1 / |A(e^jω)|
            let mag_a = (a_real * a_real + a_imag * a_imag).sqrt();
            *env = if mag_a > 1e-10 { 1.0 / mag_a } else { 0.0 };
        }

        envelope
    }

    /// Refine envelope using true envelope algorithm
    fn refine_true_envelope(&self, initial: &[f64], frame: &[f64]) -> Vec<f64> {
        // Compute actual spectrum magnitude
        let spectrum_mag = self.compute_spectrum_magnitude(frame);

        let mut envelope = initial.to_vec();
        let n = envelope.len().min(spectrum_mag.len());

        for _ in 0..self.true_envelope_iterations {
            // Where spectrum exceeds envelope, raise envelope
            for i in 0..n {
                if spectrum_mag[i] > envelope[i] {
                    envelope[i] = spectrum_mag[i];
                }
            }

            // Smooth envelope (cepstral smoothing)
            envelope = self.smooth_envelope(&envelope);
        }

        envelope
    }

    /// Compute spectrum magnitude via FFT
    fn compute_spectrum_magnitude(&self, frame: &[f64]) -> Vec<f64> {
        use rustfft::{FftPlanner, num_complex::Complex64};

        let n = self.fft_size;
        let mut buffer: Vec<Complex64> = vec![Complex64::new(0.0, 0.0); n];

        // Copy and window input
        let win_len = frame.len().min(n);
        for i in 0..win_len {
            let window = 0.5 * (1.0 - (2.0 * PI * i as f64 / win_len as f64).cos());
            buffer[i] = Complex64::new(frame[i] * window, 0.0);
        }

        // FFT
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(n);
        fft.process(&mut buffer);

        // Return magnitude of positive frequencies
        buffer[..n / 2 + 1]
            .iter()
            .map(|c| c.norm())
            .collect()
    }

    /// Smooth envelope using low-pass filtering in cepstral domain
    fn smooth_envelope(&self, envelope: &[f64]) -> Vec<f64> {
        use rustfft::{FftPlanner, num_complex::Complex64};

        let n = envelope.len();
        if n < 4 {
            return envelope.to_vec();
        }

        // Log magnitude to cepstrum
        let log_env: Vec<Complex64> = envelope.iter()
            .map(|&e| Complex64::new((e + 1e-10).ln(), 0.0))
            .collect();

        let mut cepstrum = log_env;

        // IFFT to get cepstrum
        let mut planner = FftPlanner::new();
        let ifft = planner.plan_fft_inverse(n);
        ifft.process(&mut cepstrum);

        // Lifter: keep low quefrencies (smooth envelope)
        let cutoff = n.min(32); // Keep first ~32 cepstral coefficients
        for i in cutoff..n - cutoff {
            cepstrum[i] = Complex64::new(0.0, 0.0);
        }

        // FFT back to frequency domain
        let fft = planner.plan_fft_forward(n);
        fft.process(&mut cepstrum);

        // Exp to get envelope back
        cepstrum.iter()
            .map(|c| (c.re / n as f64).exp())
            .collect()
    }

    /// Apply formant correction to spectrum
    ///
    /// When pitch-shifting, the formant envelope shifts with pitch.
    /// This corrects by:
    /// 1. Extracting original envelope
    /// 2. Extracting shifted envelope
    /// 3. Dividing shifted spectrum by shifted envelope
    /// 4. Multiplying by original envelope
    pub fn correct_formants(
        &mut self,
        spectrum: &mut [f64],
        original_envelope: &[f64],
        pitch_ratio: f64,
    ) {
        if (pitch_ratio - 1.0).abs() < 1e-6 {
            return; // No correction needed
        }

        let n = spectrum.len();

        // Create shifted envelope (how formants would naturally shift)
        let shifted_envelope = self.shift_envelope(original_envelope, pitch_ratio);

        // Apply correction: spectrum * (original / shifted)
        for i in 0..n {
            let orig = original_envelope.get(i).copied().unwrap_or(1.0);
            let shifted = shifted_envelope.get(i).copied().unwrap_or(1.0);

            if shifted > 1e-10 {
                spectrum[i] *= orig / shifted;
            }
        }
    }

    /// Shift envelope by pitch ratio (for computing expected shifted envelope)
    fn shift_envelope(&self, envelope: &[f64], ratio: f64) -> Vec<f64> {
        let n = envelope.len();
        let mut shifted = vec![0.0; n];

        for (i, s) in shifted.iter_mut().enumerate() {
            let src_idx = i as f64 / ratio;
            let src_low = src_idx.floor() as usize;
            let src_high = (src_low + 1).min(n - 1);
            let frac = src_idx - src_idx.floor();

            if src_low < n {
                *s = envelope[src_low] * (1.0 - frac)
                    + envelope.get(src_high).copied().unwrap_or(0.0) * frac;
            }
        }

        shifted
    }

    /// Get current LPC order
    pub fn lpc_order(&self) -> usize {
        self.lpc_order
    }

    /// Set LPC order
    pub fn set_lpc_order(&mut self, order: usize) {
        self.lpc_order = order.clamp(8, 64);
        self.solver = LevinsonDurbin::new(self.lpc_order);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIMD OPTIMIZED AUTOCORRELATION
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(target_arch = "x86_64")]
pub mod simd {
    use std::simd::{f64x4, Simd, SimdFloat};

    /// SIMD-optimized autocorrelation (AVX2)
    pub fn autocorrelation_simd(input: &[f64], max_lag: usize) -> Vec<f64> {
        let n = input.len();
        let mut r = vec![0.0; max_lag];

        for lag in 0..max_lag {
            let valid = n - lag;
            let chunks = valid / 4;

            let mut sum = f64x4::splat(0.0);

            for i in 0..chunks {
                let idx = i * 4;
                let a = f64x4::from_slice(&input[idx..idx + 4]);
                let b = f64x4::from_slice(&input[idx + lag..idx + lag + 4]);
                sum += a * b;
            }

            r[lag] = sum.reduce_sum();

            // Scalar remainder
            for i in (chunks * 4)..valid {
                r[lag] += input[i] * input[i + lag];
            }
        }

        r
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_levinson_durbin() {
        let mut solver = LevinsonDurbin::new(10);

        // Simple autocorrelation (exponentially decaying)
        let autocorr: Vec<f64> = (0..11)
            .map(|i| 0.9_f64.powi(i as i32))
            .collect();

        let coeffs = solver.solve(&autocorr, 4);
        assert_eq!(coeffs.len(), 5);
        assert!((coeffs[0] - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_formant_preserver_creation() {
        let preserver = FormantPreserver::new(44100.0);
        assert!(preserver.lpc_order() >= 12);
        assert!(preserver.lpc_order() <= 48);
    }

    #[test]
    fn test_envelope_extraction() {
        let mut preserver = FormantPreserver::new(44100.0);

        // Generate test signal (formant-like)
        let signal: Vec<f64> = (0..1024)
            .map(|i| {
                let t = i as f64 / 44100.0;
                (2.0 * PI * 440.0 * t).sin()
                    + 0.5 * (2.0 * PI * 880.0 * t).sin()
                    + 0.25 * (2.0 * PI * 1320.0 * t).sin()
            })
            .collect();

        let envelope = preserver.extract_envelope(&signal);
        assert!(!envelope.is_empty());
        assert!(envelope.iter().all(|&e| e >= 0.0));
    }

    #[test]
    fn test_pre_emphasis() {
        let preserver = FormantPreserver::new(44100.0);
        let input = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let emphasized = preserver.apply_pre_emphasis(&input);

        assert_eq!(emphasized.len(), input.len());
        // Pre-emphasis should boost high frequencies (differences)
        assert!((emphasized[0] - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_envelope_shift() {
        let preserver = FormantPreserver::new(44100.0);
        let envelope = vec![1.0, 0.8, 0.6, 0.4, 0.2];

        // Shift up (pitch up = envelope shifts down in frequency)
        let shifted = preserver.shift_envelope(&envelope, 2.0);
        assert_eq!(shifted.len(), envelope.len());
    }
}

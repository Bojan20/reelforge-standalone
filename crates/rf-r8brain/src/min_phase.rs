//! Minimum-Phase Transform via Hilbert Transform in Cepstrum Domain
//!
//! Converts a linear-phase FIR kernel to minimum-phase, reducing latency
//! while preserving magnitude response. The resulting phase is "minimum"
//! meaning all energy arrives as early as possible.
//!
//! Algorithm (from r8brain):
//! 1. Zero-pad kernel to N = 2^k (with oversampling factor)
//! 2. Forward FFT → complex spectrum
//! 3. Compute log-magnitude: ln(|H(k)|)
//! 4. Inverse FFT → cepstrum domain
//! 5. Apply Hilbert transform to cepstrum
//! 6. Forward FFT → minimum-phase spectrum
//! 7. Restore original magnitude, apply minimum phase
//! 8. Inverse FFT → minimum-phase kernel

use rustfft::{FftPlanner, num_complex::Complex64};

/// Convert a linear-phase FIR kernel to minimum-phase.
///
/// `kernel`: input linear-phase filter coefficients
/// `len_mult`: frequency-domain oversampling (2 = minimum, higher = better precision)
///
/// Returns: minimum-phase kernel (same length as input, but energy front-loaded)
pub fn to_minimum_phase(kernel: &[f64], len_mult: usize) -> Vec<f64> {
    let kernel_len = kernel.len();
    if kernel_len <= 1 {
        return kernel.to_vec();
    }

    let len_mult = len_mult.max(2);

    // FFT length: next power of 2 >= kernel_len * len_mult
    let fft_len = (kernel_len * len_mult).next_power_of_two();
    let fft_len_f = fft_len as f64;

    let mut planner = FftPlanner::new();
    let fft_fwd = planner.plan_fft_forward(fft_len);
    let fft_inv = planner.plan_fft_inverse(fft_len);

    // Step 1: Zero-pad kernel and compute FFT
    let mut spec: Vec<Complex64> = kernel
        .iter()
        .map(|&v| Complex64::new(v, 0.0))
        .collect();
    spec.resize(fft_len, Complex64::new(0.0, 0.0));
    fft_fwd.process(&mut spec);

    // Step 2: Save magnitude spectrum
    let magnitudes: Vec<f64> = spec.iter().map(|c| c.norm()).collect();

    // Step 3: Compute log-magnitude cepstrum
    // log(|H(k)|) with floor to avoid log(0)
    let mut log_spec: Vec<Complex64> = magnitudes
        .iter()
        .map(|&m| Complex64::new((m + 1e-300).ln(), 0.0))
        .collect();

    // Step 4: Inverse FFT → cepstrum domain
    fft_inv.process(&mut log_spec);

    // Normalize IFFT output (rustfft doesn't normalize)
    let inv_scale = 1.0 / fft_len_f;
    for c in &mut log_spec {
        *c *= inv_scale;
    }

    // Step 5: Apply Hilbert transform to cepstrum
    // cepstrum[0] = cepstrum[0] (DC — keep as-is)
    // cepstrum[1..N/2] *= 2 (positive quefrencies — double)
    // cepstrum[N/2] = cepstrum[N/2] (Nyquist — keep as-is)
    // cepstrum[N/2+1..N] = 0 (negative quefrencies — zero out)
    let half = fft_len / 2;

    // DC stays
    // log_spec[0] unchanged

    // Positive quefrencies: double
    for i in 1..half {
        log_spec[i] *= 2.0;
    }

    // Nyquist stays
    // log_spec[half] unchanged

    // Negative quefrencies: zero
    for i in (half + 1)..fft_len {
        log_spec[i] = Complex64::new(0.0, 0.0);
    }

    // Step 6: Forward FFT → analytic signal spectrum
    fft_fwd.process(&mut log_spec);

    // Step 7: Reconstruct minimum-phase spectrum
    // H_min(k) = |H(k)| * exp(j * min_phase(k))
    // Where min_phase comes from: exp(log_spec) gives complex envelope
    // with magnitude = original magnitude and phase = minimum phase
    let scale = 1.0 / fft_len_f; // Normalize forward FFT
    for (i, c) in log_spec.iter_mut().enumerate() {
        // exp(complex value) gives minimum-phase complex factor
        let log_val = Complex64::new(c.re * scale, c.im * scale);
        let exp_val = complex_exp(log_val);
        // Restore original magnitude
        *c = Complex64::new(
            magnitudes[i] * exp_val.re / exp_val.norm(),
            magnitudes[i] * exp_val.im / exp_val.norm(),
        );
    }

    // Step 8: Inverse FFT → minimum-phase kernel
    fft_inv.process(&mut log_spec);

    // Normalize and extract real part (truncated to original length)
    let inv_scale2 = 1.0 / fft_len_f;
    let mut result = Vec::with_capacity(kernel_len);
    for i in 0..kernel_len {
        result.push(log_spec[i].re * inv_scale2);
    }

    result
}

/// Complex exponential: exp(a + bi) = e^a * (cos(b) + i*sin(b))
#[inline]
fn complex_exp(c: Complex64) -> Complex64 {
    let exp_re = c.re.exp();
    Complex64::new(exp_re * c.im.cos(), exp_re * c.im.sin())
}

/// Compute group delay at DC for a minimum-phase kernel.
/// Returns delay in samples (fractional).
pub fn group_delay_at_dc(kernel: &[f64]) -> f64 {
    if kernel.len() <= 1 {
        return 0.0;
    }

    // Group delay at DC = -d(phase)/d(omega) at omega=0
    // For FIR: tau = sum(n * h[n]) / sum(h[n])
    let mut num = 0.0;
    let mut den = 0.0;
    for (n, &h) in kernel.iter().enumerate() {
        num += n as f64 * h;
        den += h;
    }

    if den.abs() < 1e-15 {
        0.0
    } else {
        num / den
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identity_kernel() {
        // Single-tap kernel should be unchanged
        let result = to_minimum_phase(&[1.0], 2);
        assert_eq!(result.len(), 1);
        assert!((result[0] - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_symmetric_kernel() {
        // Symmetric linear-phase kernel → minimum-phase should front-load energy
        let kernel = vec![0.1, 0.2, 0.4, 0.2, 0.1];
        let min_phase = to_minimum_phase(&kernel, 4);

        assert_eq!(min_phase.len(), 5);

        // Minimum-phase: first sample should have more energy than linear-phase
        assert!(min_phase[0].abs() > kernel[0].abs(),
            "Min-phase should front-load: {} vs {}", min_phase[0], kernel[0]);

        // Energy preservation: sum of squares should be approximately equal
        let energy_orig: f64 = kernel.iter().map(|x| x * x).sum();
        let energy_min: f64 = min_phase.iter().map(|x| x * x).sum();
        assert!((energy_orig - energy_min).abs() / energy_orig < 0.01,
            "Energy not preserved: orig={energy_orig}, min={energy_min}");
    }

    #[test]
    fn test_group_delay() {
        // Symmetric 5-tap kernel: group delay should be at center (index 2)
        let kernel = vec![0.1, 0.2, 0.4, 0.2, 0.1];
        let delay = group_delay_at_dc(&kernel);
        assert!((delay - 2.0).abs() < 0.01, "Delay should be ~2.0: {delay}");

        // Minimum-phase should have lower delay
        let min_kernel = to_minimum_phase(&kernel, 4);
        let min_delay = group_delay_at_dc(&min_kernel);
        assert!(min_delay < delay, "Min-phase delay {min_delay} should be < linear {delay}");
    }

    #[test]
    fn test_complex_exp() {
        use std::f64::consts::PI;
        // exp(0) = 1
        let r = complex_exp(Complex64::new(0.0, 0.0));
        assert!((r.re - 1.0).abs() < 1e-10);
        assert!(r.im.abs() < 1e-10);

        // exp(i*π) = -1
        let r = complex_exp(Complex64::new(0.0, PI));
        assert!((r.re + 1.0).abs() < 1e-10);
        assert!(r.im.abs() < 1e-10);
    }

    #[test]
    fn test_longer_kernel() {
        // Generate a proper lowpass and convert
        let kernel = crate::kaiser::generate_sinc_filter(0.9, 33, 100.0);
        let min_phase = to_minimum_phase(&kernel, 4);

        assert_eq!(min_phase.len(), 33);

        // Energy preservation
        let energy_orig: f64 = kernel.iter().map(|x| x * x).sum();
        let energy_min: f64 = min_phase.iter().map(|x| x * x).sum();
        assert!((energy_orig - energy_min).abs() / energy_orig < 0.05,
            "Energy diverged: orig={energy_orig}, min={energy_min}");
    }
}

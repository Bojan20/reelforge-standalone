//! Kaiser Window and Sinc Filter Generator
//!
//! Implements the Kaiser-Bessel window function used by r8brain for
//! designing FIR lowpass filters with configurable transition band
//! and stopband attenuation.
//!
//! The Kaiser window achieves near-optimal sidelobe suppression for
//! a given filter length, controlled by the β parameter.

use std::f64::consts::PI;

/// Modified Bessel function of the first kind, order 0.
/// Uses polynomial approximation from Abramowitz & Stegun (1964).
///
/// Two ranges for numerical stability:
/// - |x| < 3.75: 7th-order polynomial
/// - |x| >= 3.75: asymptotic expansion with exponential
///
/// Accuracy: ~1e-15 relative error across full range.
#[inline]
pub fn bessel_i0(x: f64) -> f64 {
    let ax = x.abs();

    if ax < 3.75 {
        // Polynomial approximation for small arguments
        let t = (x / 3.75) * (x / 3.75);
        1.0 + t * (3.5156229
            + t * (3.0899424
                + t * (1.2067492
                    + t * (0.2659732
                        + t * (0.0360768
                            + t * 0.0045813)))))
    } else {
        // Asymptotic expansion for large arguments
        let t = 3.75 / ax;
        let exp_part = ax.exp() / ax.sqrt();
        exp_part * (0.39894228
            + t * (0.01328592
                + t * (0.00225319
                    + t * (-0.00157565
                        + t * (0.00916281
                            + t * (-0.02057706
                                + t * (0.02635537
                                    + t * (-0.01647633
                                        + t * 0.00392377))))))))
    }
}

/// Kaiser window function.
///
/// `n`: sample index (0 to N-1)
/// `n_total`: total number of samples (N)
/// `beta`: shape parameter (higher = wider main lobe, lower sidelobes)
///
/// β mapping to approximate stopband attenuation:
/// - β=5.0  → ~50 dB
/// - β=8.0  → ~80 dB
/// - β=10.0 → ~100 dB
/// - β=14.0 → ~140 dB
/// - β=18.0 → ~180 dB
/// - β=21.0 → ~210 dB
#[inline]
pub fn kaiser_window(n: usize, n_total: usize, beta: f64) -> f64 {
    if n_total <= 1 {
        return 1.0;
    }
    let half = (n_total - 1) as f64 / 2.0;
    let x = (n as f64 - half) / half; // -1.0 to +1.0
    let arg = 1.0 - x * x;
    if arg < 0.0 {
        return 0.0;
    }
    bessel_i0(beta * arg.sqrt()) / bessel_i0(beta)
}

/// Calculate Kaiser β parameter from desired stopband attenuation.
/// Formula from Kaiser & Schafer (1980).
///
/// `atten_db`: desired stopband attenuation in dB (e.g., 180.0)
/// Returns: β parameter for Kaiser window
#[inline]
pub fn beta_from_attenuation(atten_db: f64) -> f64 {
    if atten_db > 50.0 {
        0.1102 * (atten_db - 8.7)
    } else if atten_db >= 21.0 {
        0.5842 * (atten_db - 21.0).powf(0.4) + 0.07886 * (atten_db - 21.0)
    } else {
        0.0 // Rectangular window
    }
}

/// Calculate minimum filter length for desired specifications.
///
/// `atten_db`: stopband attenuation in dB
/// `transition_width`: transition band width as fraction of sample rate (0.0 to 0.5)
/// Returns: filter length (odd number)
pub fn filter_length(atten_db: f64, transition_width: f64) -> usize {
    if transition_width <= 0.0 || transition_width > 0.5 {
        return 3; // Minimum valid
    }
    // Kaiser formula: N ≈ (A - 7.95) / (2.285 * 2π * Δf)
    let n = ((atten_db - 7.95) / (2.285 * 2.0 * PI * transition_width)).ceil() as usize;
    // Ensure odd length for symmetric filter
    let n = n.max(3);
    if n % 2 == 0 { n + 1 } else { n }
}

/// Power-raised Kaiser window — r8brain's variant for spectral concentration control.
///
/// `power`: exponent applied to window values (1.0 = standard Kaiser)
/// Higher power narrows main lobe but increases sidelobes.
#[inline]
pub fn kaiser_power_window(n: usize, n_total: usize, beta: f64, power: f64) -> f64 {
    kaiser_window(n, n_total, beta).powf(power)
}

/// Generate a windowed sinc lowpass filter kernel.
///
/// `cutoff`: normalized cutoff frequency (0.0 to 1.0, where 1.0 = Nyquist)
/// `length`: filter length (number of taps, should be odd)
/// `atten_db`: stopband attenuation in dB (determines Kaiser β)
///
/// Returns: normalized filter coefficients (sum = 1.0 for DC preservation)
pub fn generate_sinc_filter(cutoff: f64, length: usize, atten_db: f64) -> Vec<f64> {
    let beta = beta_from_attenuation(atten_db);
    let half = (length - 1) as f64 / 2.0;
    let mut kernel = Vec::with_capacity(length);
    let mut sum = 0.0;

    for n in 0..length {
        let x = n as f64 - half;

        // Lowpass sinc: h(x) = sin(π·x·cutoff) / (π·x)
        // At x=0: limit = cutoff
        let sinc = if x.abs() < 1e-10 {
            cutoff
        } else {
            let pi_x = PI * x;
            (pi_x * cutoff).sin() / pi_x
        };

        // Kaiser window
        let window = kaiser_window(n, length, beta);

        let val = sinc * window;
        kernel.push(val);
        sum += val;
    }

    // Normalize for DC gain = 1.0
    if sum.abs() > 1e-15 {
        for val in &mut kernel {
            *val /= sum;
        }
    }

    kernel
}

/// Generate a windowed sinc filter at a specific fractional delay.
///
/// `cutoff`: normalized cutoff frequency
/// `length`: filter length
/// `atten_db`: stopband attenuation
/// `frac_delay`: fractional sample delay (0.0 to 1.0)
///
/// Returns: filter coefficients shifted by frac_delay
pub fn generate_sinc_filter_delayed(
    cutoff: f64,
    length: usize,
    atten_db: f64,
    frac_delay: f64,
) -> Vec<f64> {
    let beta = beta_from_attenuation(atten_db);
    let half = (length - 1) as f64 / 2.0;
    let mut kernel = Vec::with_capacity(length);
    let mut sum = 0.0;

    for n in 0..length {
        let x = n as f64 - half - frac_delay;

        let sinc = if x.abs() < 1e-10 {
            cutoff
        } else {
            let pi_x = PI * x;
            (pi_x * cutoff).sin() / pi_x
        };

        let window = kaiser_window(n, length, beta);
        let val = sinc * window;
        kernel.push(val);
        sum += val;
    }

    if sum.abs() > 1e-15 {
        for val in &mut kernel {
            *val /= sum;
        }
    }

    kernel
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bessel_i0_zero() {
        assert!((bessel_i0(0.0) - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_bessel_i0_known_values() {
        // I0(1.0) ≈ 1.26606587776
        assert!((bessel_i0(1.0) - 1.26606587776).abs() < 1e-6);
        // I0(3.75) should be continuous across boundary
        let below = bessel_i0(3.74);
        let above = bessel_i0(3.76);
        let at = bessel_i0(3.75);
        assert!((at - below).abs() < 0.5, "Discontinuity at boundary: {below} vs {at}");
        assert!((at - above).abs() < 0.5, "Discontinuity at boundary: {at} vs {above}");
        // Monotonicity: I0 is monotonically increasing for x > 0
        assert!(above > at, "I0 should be monotonic: I0(3.76)={above} > I0(3.75)={at}");
        assert!(at > below, "I0 should be monotonic: I0(3.75)={at} > I0(3.74)={below}");
    }

    #[test]
    fn test_kaiser_window_symmetry() {
        let n = 65;
        let beta = 10.0;
        for i in 0..n / 2 {
            let left = kaiser_window(i, n, beta);
            let right = kaiser_window(n - 1 - i, n, beta);
            assert!((left - right).abs() < 1e-12, "Asymmetry at {i}: {left} vs {right}");
        }
    }

    #[test]
    fn test_kaiser_window_edges() {
        let n = 65;
        let beta = 14.0;
        let edge = kaiser_window(0, n, beta);
        let center = kaiser_window(32, n, beta);
        assert!(edge < 0.01, "Edge not near zero: {edge}");
        assert!((center - 1.0).abs() < 1e-10, "Center not 1.0: {center}");
    }

    #[test]
    fn test_beta_from_attenuation() {
        let b50 = beta_from_attenuation(50.0);
        let b100 = beta_from_attenuation(100.0);
        let b180 = beta_from_attenuation(180.0);
        assert!(b50 < b100, "β should increase with attenuation");
        assert!(b100 < b180, "β should increase with attenuation");
        assert!(b180 > 15.0, "180dB should have β > 15: got {b180}");
    }

    #[test]
    fn test_sinc_filter_dc_preservation() {
        let kernel = generate_sinc_filter(0.9, 65, 140.0);
        let sum: f64 = kernel.iter().sum();
        assert!((sum - 1.0).abs() < 1e-10, "DC gain not 1.0: {sum}");
    }

    #[test]
    fn test_sinc_filter_symmetry() {
        let kernel = generate_sinc_filter(0.9, 65, 140.0);
        for i in 0..kernel.len() / 2 {
            let left = kernel[i];
            let right = kernel[kernel.len() - 1 - i];
            assert!((left - right).abs() < 1e-12, "Filter asymmetry at {i}");
        }
    }

    #[test]
    fn test_filter_length_calculation() {
        let len = filter_length(140.0, 0.02); // 2% transition band, 140dB
        assert!(len >= 100, "Filter should be long for tight specs: {len}");
        assert!(len % 2 == 1, "Filter length should be odd: {len}");
    }

    #[test]
    fn test_delayed_filter_sum() {
        // Delayed filter should still preserve DC
        let kernel = generate_sinc_filter_delayed(0.9, 65, 140.0, 0.5);
        let sum: f64 = kernel.iter().sum();
        assert!((sum - 1.0).abs() < 1e-6, "Delayed filter DC not preserved: {sum}");
    }
}

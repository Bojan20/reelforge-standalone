//! Polynomial Fractional Delay Interpolator
//!
//! Core innovation of r8brain: instead of storing sinc filters for every
//! fractional position, stores polynomial coefficients that interpolate
//! between filter bank entries.
//!
//! For each tap position, cubic (or quadratic) polynomial coefficients
//! are computed via 8-point cubic spline fitting. At runtime, the exact
//! filter coefficient for any fractional delay is:
//!   coeff = a0 + a1*x + a2*x² + a3*x³
//! where x is the fractional offset within the filter bank step.

use crate::kaiser;

/// Number of polynomial coefficients per tap per interpolation order
const POLY_ORDER_3: usize = 4; // cubic: a0, a1, a2, a3

/// Fractional delay interpolator with polynomial filter bank.
///
/// Pre-computes a bank of sinc filters at discrete fractional positions,
/// then fits polynomial curves through adjacent filters to allow
/// continuous fractional delay at any position.
pub struct FracInterpolator {
    /// Filter length (number of taps)
    filter_len: usize,
    /// Number of discrete fractional positions in the bank
    filter_fracs: usize,
    /// Polynomial coefficients: [filter_fracs][filter_len][POLY_ORDER_3]
    /// Stored flat: index = frac_idx * filter_len * POLY_ORDER_3 + tap * POLY_ORDER_3 + coeff
    poly_coeffs: Vec<f64>,
    /// Normalized cutoff frequency used to generate filters
    #[allow(dead_code)]
    cutoff: f64,
    /// Stopband attenuation in dB
    #[allow(dead_code)]
    atten_db: f64,
}

impl FracInterpolator {
    /// Create a new fractional interpolator.
    ///
    /// `filter_len`: number of filter taps (typically 8-30 for r8brain)
    /// `cutoff`: normalized cutoff frequency (0.0 to 1.0)
    /// `atten_db`: stopband attenuation (e.g., 180.0 for 24-bit quality)
    ///
    /// FilterFracs is automatically calculated: ceil(6.4^(atten_db/50))
    pub fn new(filter_len: usize, cutoff: f64, atten_db: f64) -> Self {
        assert!(filter_len >= 4, "filter_len must be >= 4");

        // r8brain formula for number of fractional positions
        let filter_fracs = (6.4_f64.powf(atten_db / 50.0)).ceil() as usize;
        let filter_fracs = filter_fracs.max(8); // Minimum 8 positions

        // Generate sinc filters at each discrete fractional position
        // Plus 3 extra on each side for cubic spline fitting
        let total_positions = filter_fracs + 6; // 3 extra on each side
        let mut filter_bank = Vec::with_capacity(total_positions);

        for i in 0..total_positions {
            // Fractional delay: maps [0, total_positions) to [-3/fracs, 1+3/fracs)
            let frac = (i as f64 - 3.0) / filter_fracs as f64;
            let kernel = kaiser::generate_sinc_filter_delayed(cutoff, filter_len, atten_db, frac);
            filter_bank.push(kernel);
        }

        // Fit cubic polynomials through 8 adjacent filter bank entries (r8brain method)
        let stride = filter_len * POLY_ORDER_3;
        let mut poly_coeffs = vec![0.0f64; filter_fracs * stride];

        for frac_idx in 0..filter_fracs {
            for tap in 0..filter_len {
                // 8-point cubic spline: uses points at frac_idx + {-3, -2, -1, 0, 1, 2, 3, 4}
                // which maps to filter_bank indices frac_idx + {0, 1, 2, 3, 4, 5, 6, 7}
                // (since we added 3 extra on each side)
                let x_m3 = filter_bank[frac_idx][tap];
                let x_m2 = filter_bank[frac_idx + 1][tap];
                let x_m1 = filter_bank[frac_idx + 2][tap];
                let x_0 = filter_bank[frac_idx + 3][tap];
                let x_1 = filter_bank[frac_idx + 4][tap];
                let x_2 = filter_bank[frac_idx + 5][tap];
                let x_3 = if frac_idx + 6 < filter_bank.len() {
                    filter_bank[frac_idx + 6][tap]
                } else {
                    0.0
                };
                let x_4 = if frac_idx + 7 < filter_bank.len() {
                    filter_bank[frac_idx + 7][tap]
                } else {
                    0.0
                };

                // 8-point cubic spline coefficients (r8brain calcSpline3p8Coeffs)
                let (a0, a1, a2, a3) = calc_spline_3p8(x_m3, x_m2, x_m1, x_0, x_1, x_2, x_3, x_4);

                let base = frac_idx * stride + tap * POLY_ORDER_3;
                poly_coeffs[base] = a0;
                poly_coeffs[base + 1] = a1;
                poly_coeffs[base + 2] = a2;
                poly_coeffs[base + 3] = a3;
            }
        }

        Self {
            filter_len,
            filter_fracs,
            poly_coeffs,
            cutoff,
            atten_db,
        }
    }

    /// Interpolate a single output sample.
    ///
    /// `input`: input audio buffer (mono, contiguous)
    /// `position`: fractional input position (e.g., 1234.567)
    /// `input_len`: total length of input buffer
    ///
    /// Returns: interpolated output sample
    ///
    /// Zero-allocation, audio-thread safe.
    #[inline]
    pub fn interpolate(&self, input: &[f64], position: f64, input_len: usize) -> f64 {
        if input_len == 0 || !position.is_finite() {
            return 0.0;
        }

        let idx_floor = position.floor() as i64;
        let frac = position - idx_floor as f64;

        // Map fractional position to filter bank index + sub-position
        let frac_scaled = frac * self.filter_fracs as f64;
        let frac_idx = frac_scaled.floor() as usize;
        let sub_frac = frac_scaled - frac_idx as f64; // 0.0 to 1.0 within bank step

        let frac_idx = frac_idx.min(self.filter_fracs - 1);
        let half = self.filter_len as i64 / 2;
        let stride = self.filter_len * POLY_ORDER_3;
        let base = frac_idx * stride;

        let mut sum = 0.0f64;

        // Convolution with polynomial-evaluated coefficients
        for tap in 0..self.filter_len {
            let sample_idx = idx_floor - half + 1 + tap as i64;
            if sample_idx >= 0 && sample_idx < input_len as i64 {
                let coeff_base = base + tap * POLY_ORDER_3;
                let a0 = self.poly_coeffs[coeff_base];
                let a1 = self.poly_coeffs[coeff_base + 1];
                let a2 = self.poly_coeffs[coeff_base + 2];
                let a3 = self.poly_coeffs[coeff_base + 3];

                // Horner's method: a0 + x*(a1 + x*(a2 + x*a3))
                let coeff = a0 + sub_frac * (a1 + sub_frac * (a2 + sub_frac * a3));
                sum += input[sample_idx as usize] * coeff;
            }
        }

        sum
    }

    /// Get filter length
    pub fn filter_len(&self) -> usize {
        self.filter_len
    }

    /// Get number of fractional positions in the bank
    pub fn filter_fracs(&self) -> usize {
        self.filter_fracs
    }

    /// Latency in samples
    pub fn latency(&self) -> usize {
        self.filter_len / 2
    }
}

/// 8-point cubic spline coefficient calculation.
/// r8brain's `calcSpline3p8Coeffs` formula.
///
/// Given 8 sample points (x_{-3} through x_4), computes
/// cubic polynomial coefficients (a0, a1, a2, a3) such that:
///   f(t) = a0 + a1*t + a2*t² + a3*t³  for t in [0, 1)
///
/// Coefficients from r8brain source (empirically optimized):
#[inline]
fn calc_spline_3p8(
    x_m3: f64, x_m2: f64, x_m1: f64, x_0: f64,
    x_1: f64, x_2: f64, x_3: f64, x_4: f64,
) -> (f64, f64, f64, f64) {
    let scale = 1.0 / 76.0; // 0.0131578947...

    let a0 = x_0;
    let a1 = (61.0 * (x_1 - x_m1) + 16.0 * (x_m2 - x_2) + 3.0 * (x_3 - x_m3)) * scale;
    let a2 = (106.0 * (x_m1 + x_1) + 10.0 * x_3 + 6.0 * x_m3
        - 3.0 * x_4 - 29.0 * (x_m2 + x_2) - 167.0 * x_0) * scale;
    let a3 = (91.0 * (x_0 - x_1) + 45.0 * (x_2 - x_m1)
        + 13.0 * (x_m2 - x_3) + 3.0 * (x_4 - x_m3)) * scale;

    (a0, a1, a2, a3)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_interpolator_creation() {
        let interp = FracInterpolator::new(16, 0.9, 140.0);
        assert_eq!(interp.filter_len(), 16);
        assert!(interp.filter_fracs() >= 8);
    }

    #[test]
    fn test_interpolator_dc() {
        // All-ones input should produce ~1.0 output
        let interp = FracInterpolator::new(16, 0.95, 140.0);
        let input: Vec<f64> = vec![1.0; 1000];
        for frac in [0.0, 0.25, 0.5, 0.75, 0.99] {
            let result = interp.interpolate(&input, 500.0 + frac, 1000);
            assert!(
                (result - 1.0).abs() < 0.01,
                "DC preservation failed at frac={frac}: got {result}"
            );
        }
    }

    #[test]
    fn test_interpolator_zero_input() {
        let interp = FracInterpolator::new(16, 0.9, 140.0);
        let input: Vec<f64> = vec![0.0; 100];
        let result = interp.interpolate(&input, 50.0, 100);
        assert!(result.abs() < 1e-15, "Zero input should produce zero output");
    }

    #[test]
    fn test_spline_coefficients() {
        // All same values → a0 = value, a1=a2=a3 ≈ 0
        let (a0, a1, a2, a3) = calc_spline_3p8(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0);
        assert!((a0 - 1.0).abs() < 1e-10, "a0 should be 1.0: {a0}");
        assert!(a1.abs() < 1e-10, "a1 should be ~0: {a1}");
        assert!(a2.abs() < 1e-10, "a2 should be ~0: {a2}");
        assert!(a3.abs() < 1e-10, "a3 should be ~0: {a3}");
    }

    #[test]
    fn test_interpolator_latency() {
        let interp = FracInterpolator::new(16, 0.9, 140.0);
        assert_eq!(interp.latency(), 8);
    }

    #[test]
    fn test_interpolator_empty_input() {
        let interp = FracInterpolator::new(16, 0.9, 140.0);
        let input: Vec<f64> = vec![];
        let result = interp.interpolate(&input, 0.0, 0);
        assert_eq!(result, 0.0);
    }

    #[test]
    fn test_interpolator_nan_position() {
        let interp = FracInterpolator::new(16, 0.9, 140.0);
        let input: Vec<f64> = vec![1.0; 100];
        let result = interp.interpolate(&input, f64::NAN, 100);
        assert_eq!(result, 0.0);
    }
}

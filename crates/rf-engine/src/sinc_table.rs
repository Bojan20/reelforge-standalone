//! Blackman-Harris Windowed Sinc Interpolation — WDL-grade quality
//!
//! Pre-computed sinc table for real-time sample rate conversion.
//! All table generation happens ONCE at init — zero allocation on audio thread.
//!
//! Quality modes match Reaper's nomenclature:
//! - Sinc(16): Fast preview (~-60dB noise floor)
//! - Sinc(64): Default playback (~-120dB) — Reaper "Medium"
//! - Sinc(192): Good render (~-140dB) — Reaper "Good"
//! - Sinc(384): High render (~-150dB) — Reaper "Better"
//! - Sinc(512): HQ render — Reaper "HQ"
//! - Sinc(768): Extreme HQ — Reaper "Extreme HQ"

use std::f64::consts::PI;

/// Resample quality mode — maps to sinc kernel size
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResampleMode {
    /// Nearest-neighbor (zero-order hold) — for lo-fi effect
    Point,
    /// Linear interpolation (2-tap) — for scrub/shuttle, lowest CPU
    Linear,
    /// Windowed sinc interpolation — configurable tap count
    Sinc(u16),
    /// R8brain multi-stage pipeline — OFFLINE RENDER ONLY (heap allocs, not audio-thread safe)
    /// Used by rf-offline for final bounce, NOT by real-time playback engine.
    R8brain,
}

impl ResampleMode {
    /// Default playback quality (64pt sinc = Reaper "Medium")
    pub const PLAYBACK: Self = Self::Sinc(64);
    /// Default render quality — Sinc(384) (real-time safe, ~-150dB)
    /// R8brain is available for offline render via rf-offline crate.
    pub const RENDER: Self = Self::Sinc(384);
    /// Scrub/shuttle quality
    pub const SCRUB: Self = Self::Linear;

    /// Returns the kernel half-size (number of taps on each side)
    pub fn half_size(self) -> usize {
        match self {
            Self::Point => 0,
            Self::Linear => 1,
            Self::Sinc(n) => (n as usize) / 2,
            Self::R8brain => 0, // R8brain handles latency internally
        }
    }

    /// Latency in samples introduced by this mode
    pub fn latency_samples(self) -> usize {
        self.half_size()
    }

    /// Whether this mode requires a per-voice R8brainResampler instance
    pub fn is_r8brain(self) -> bool {
        matches!(self, Self::R8brain)
    }
}

impl Default for ResampleMode {
    fn default() -> Self {
        Self::PLAYBACK
    }
}

/// Pre-computed windowed sinc interpolation table.
///
/// Table layout: `sinc_size * interp_resolution` coefficients.
/// For each fractional offset (0..interp_resolution), stores `sinc_size` tap weights.
///
/// Generated ONCE at init or mode change — NEVER on audio thread.
pub struct SincTable {
    /// Sinc kernel size (total taps: 16, 64, 192, 384, 512, 768)
    sinc_size: usize,
    /// Sub-sample interpolation resolution (positions between integer samples)
    interp_resolution: usize,
    /// Pre-computed coefficients: [interp_resolution][sinc_size]
    /// Stored flat: index = frac_idx * sinc_size + tap_idx
    coefficients: Vec<f64>,
}

impl SincTable {
    /// Create a new sinc table for the given kernel size.
    ///
    /// `sinc_size`: total number of taps (must be even, e.g., 64)
    /// `interp_resolution`: number of sub-sample positions (default: 256)
    ///
    /// Uses Blackman-Harris 4-term window for optimal sidelobe suppression.
    pub fn new(sinc_size: usize, interp_resolution: usize) -> Self {
        assert!(sinc_size >= 4 && sinc_size % 2 == 0, "sinc_size must be even and >= 4");
        assert!(interp_resolution >= 1, "interp_resolution must be >= 1");

        let half = sinc_size / 2;
        let total = sinc_size * interp_resolution;
        let mut coefficients = vec![0.0f64; total];

        for frac_idx in 0..interp_resolution {
            // Fractional offset: 0.0 to 1.0 (exclusive)
            let frac = frac_idx as f64 / interp_resolution as f64;

            let row_start = frac_idx * sinc_size;
            let mut weight_sum = 0.0;

            for tap in 0..sinc_size {
                // Distance from center: tap position relative to fractional offset
                let x = (tap as f64 - half as f64) + (1.0 - frac);

                let sinc_val = if x.abs() < 1e-10 {
                    1.0
                } else {
                    let pi_x = PI * x;
                    pi_x.sin() / pi_x
                };

                // Blackman-Harris 4-term window — fixed function of tap position only.
                // Window is symmetric around center (tap/sinc_size = 0.5 → peak).
                // Edges (tap=0, tap=sinc_size-1) → near zero.
                let window_pos = (tap as f64 + 0.5) / sinc_size as f64;
                let window = blackman_harris_4(window_pos);

                let coeff = sinc_val * window;
                coefficients[row_start + tap] = coeff;
                weight_sum += coeff;
            }

            // Normalize so coefficients sum to 1.0 (preserves DC gain)
            if weight_sum.abs() > 1e-15 {
                for tap in 0..sinc_size {
                    coefficients[row_start + tap] /= weight_sum;
                }
            }
        }

        Self {
            sinc_size,
            interp_resolution,
            coefficients,
        }
    }

    /// Get the coefficient slice for a fractional position.
    ///
    /// `frac`: fractional part of source position (0.0 to 1.0)
    /// Returns: slice of `sinc_size` pre-normalized coefficients
    #[inline(always)]
    pub fn get_coefficients(&self, frac: f64) -> &[f64] {
        let frac_idx = ((frac * self.interp_resolution as f64) as usize)
            .min(self.interp_resolution - 1);
        let start = frac_idx * self.sinc_size;
        &self.coefficients[start..start + self.sinc_size]
    }

    #[inline(always)]
    pub fn sinc_size(&self) -> usize {
        self.sinc_size
    }

    #[inline(always)]
    pub fn half_size(&self) -> usize {
        self.sinc_size / 2
    }
}

/// Blackman-Harris 4-term window function.
/// `t`: normalized position (0.0 to 1.0)
/// Returns: window value (0.0 to 1.0)
///
/// Coefficients: a0=0.35875, a1=0.48829, a2=0.14128, a3=0.01168
/// Sidelobe suppression: ~-92dB (far superior to Hann ~-31dB or Blackman ~-58dB)
#[inline(always)]
fn blackman_harris_4(t: f64) -> f64 {
    let w = 2.0 * PI * t;
    0.35875 - 0.48829 * (w).cos() + 0.14128 * (2.0 * w).cos() - 0.01168 * (3.0 * w).cos()
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERPOLATION FUNCTIONS — Audio-thread safe, zero-allocation
// ═══════════════════════════════════════════════════════════════════════════════

/// Point sample (nearest-neighbor) — zero-order hold.
/// Lowest quality, lowest CPU. For lo-fi effects only.
#[inline(always)]
pub fn point_sample(
    src_pos: f64,
    samples: &[f32],
    channels: usize,
    total_frames: usize,
    ch: usize,
) -> f32 {
    if channels == 0 || total_frames == 0 || !src_pos.is_finite() {
        return 0.0;
    }
    let idx = src_pos.round() as i64;
    if idx >= 0 && (idx as usize) < total_frames {
        samples[idx as usize * channels + ch]
    } else {
        0.0
    }
}

/// Linear interpolation (2-tap) — for scrub/shuttle.
/// Low quality but fast. No pre-computed table needed.
#[inline(always)]
pub fn linear_sample(
    src_pos: f64,
    samples: &[f32],
    channels: usize,
    total_frames: usize,
    ch: usize,
) -> f32 {
    if channels == 0 || total_frames == 0 || !src_pos.is_finite() {
        return 0.0;
    }
    let idx_i = src_pos.floor() as i64;
    if idx_i < 0 { return 0.0; }
    let idx = idx_i as usize;
    let frac = (src_pos - idx as f64) as f32;

    if idx + 1 < total_frames {
        let a = samples[idx * channels + ch];
        let b = samples[(idx + 1) * channels + ch];
        a + frac * (b - a)
    } else if idx < total_frames {
        samples[idx * channels + ch]
    } else {
        0.0
    }
}

/// Windowed sinc interpolation using pre-computed table.
/// Quality determined by `SincTable` kernel size (16 to 768 taps).
///
/// Audio-thread safe: zero allocation, stack-only computation.
/// Uses pre-normalized coefficients — no division in hot path.
///
/// For sinc_size <= 768, uses stack-allocated gather buffer for
/// contiguous SIMD-friendly dot product (no strided memory access).
#[inline]
pub fn sinc_sample(
    src_pos: f64,
    samples: &[f32],
    channels: usize,
    total_frames: usize,
    ch: usize,
    table: &SincTable,
) -> f32 {
    // Guard: invalid inputs → silence
    if channels == 0 || total_frames == 0 || !src_pos.is_finite() {
        return 0.0;
    }

    let idx_floor = src_pos.floor() as i64;
    let frac = src_pos - idx_floor as f64;

    // Fast path: exact integer position
    if frac < 1e-10 {
        let i = idx_floor as usize;
        if i < total_frames {
            return samples[i * channels + ch];
        }
        return 0.0;
    }

    let coeffs = table.get_coefficients(frac);
    let half = table.half_size() as i64;
    let sinc_size = table.sinc_size();
    let first_tap = idx_floor - half + 1;

    // Gather samples into contiguous stack buffer for SIMD-friendly dot product.
    // Max 768 taps × 8 bytes = 6KB on stack — well within audio thread limits.
    let mut gathered = [0.0f64; 768];
    for tap in 0..sinc_size {
        let sample_idx = first_tap + tap as i64;
        if sample_idx >= 0 && sample_idx < total_frames as i64 {
            gathered[tap] = samples[sample_idx as usize * channels + ch] as f64;
        }
    }

    // Dot product: coeffs · gathered — SIMD-friendly (both contiguous)
    sinc_dot_product(&coeffs[..sinc_size], &gathered[..sinc_size])
}

/// SIMD-optimized dot product for sinc convolution.
/// Both slices are contiguous f64 — uses platform-specific intrinsics.
///
/// aarch64: NEON vfmaq_f64 (2× f64 FMA per cycle)
/// x86_64: AVX2 _mm256_fmadd_pd (4× f64 FMA per cycle) or SSE2 fallback
#[inline]
fn sinc_dot_product(coeffs: &[f64], samples: &[f64]) -> f32 {
    debug_assert_eq!(coeffs.len(), samples.len());

    #[cfg(target_arch = "aarch64")]
    {
        // NEON is always available on aarch64
        unsafe { sinc_dot_neon(coeffs, samples) }
    }

    #[cfg(target_arch = "x86_64")]
    {
        if is_x86_feature_detected!("avx2") && is_x86_feature_detected!("fma") {
            unsafe { sinc_dot_avx2(coeffs, samples) }
        } else {
            sinc_dot_scalar(coeffs, samples)
        }
    }

    #[cfg(not(any(target_arch = "aarch64", target_arch = "x86_64")))]
    {
        sinc_dot_scalar(coeffs, samples)
    }
}

/// Scalar fallback — used on platforms without NEON/AVX2
#[inline]
#[allow(dead_code)]
fn sinc_dot_scalar(coeffs: &[f64], samples: &[f64]) -> f32 {
    let mut sum = 0.0f64;
    for i in 0..coeffs.len() {
        sum += coeffs[i] * samples[i];
    }
    sum as f32
}

/// NEON f64 dot product — 2× f64 per cycle with FMA
#[cfg(target_arch = "aarch64")]
#[inline]
unsafe fn sinc_dot_neon(coeffs: &[f64], samples: &[f64]) -> f32 {
    use std::arch::aarch64::*;
    debug_assert_eq!(coeffs.len(), samples.len(), "NEON sinc_dot: length mismatch");
    let len = coeffs.len();
    if len == 0 { return 0.0; }
    let simd_len = len - (len % 2);
    let c_ptr = coeffs.as_ptr();
    let s_ptr = samples.as_ptr();

    let mut acc = unsafe { vdupq_n_f64(0.0) };

    for i in (0..simd_len).step_by(2) {
        unsafe {
            let c = vld1q_f64(c_ptr.add(i));
            let s = vld1q_f64(s_ptr.add(i));
            acc = vfmaq_f64(acc, c, s); // acc += c * s
        }
    }

    // Horizontal sum of 2-lane accumulator
    let mut sum = unsafe { vgetq_lane_f64(acc, 0) + vgetq_lane_f64(acc, 1) };

    // Scalar remainder
    for i in simd_len..len {
        sum += coeffs[i] * samples[i];
    }

    sum as f32
}

/// AVX2 f64 dot product — 4× f64 per cycle with FMA
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2", enable = "fma")]
#[inline]
unsafe fn sinc_dot_avx2(coeffs: &[f64], samples: &[f64]) -> f32 {
    use std::arch::x86_64::*;
    debug_assert_eq!(coeffs.len(), samples.len(), "AVX2 sinc_dot: length mismatch");
    let len = coeffs.len();
    if len == 0 { return 0.0; }
    let simd_len = len - (len % 4);
    let c_ptr = coeffs.as_ptr();
    let s_ptr = samples.as_ptr();

    let mut acc = _mm256_setzero_pd();

    for i in (0..simd_len).step_by(4) {
        let c = _mm256_loadu_pd(c_ptr.add(i));
        let s = _mm256_loadu_pd(s_ptr.add(i));
        acc = _mm256_fmadd_pd(c, s, acc); // acc += c * s
    }

    // Horizontal sum of 4-lane accumulator
    // [a, b, c, d] → [a+c, b+d] → a+c+b+d
    let hi = _mm256_extractf128_pd(acc, 1);
    let lo = _mm256_castpd256_pd128(acc);
    let sum128 = _mm_add_pd(lo, hi);
    let mut sum = _mm_cvtsd_f64(sum128) + _mm_cvtsd_f64(_mm_unpackhi_pd(sum128, sum128));

    // Scalar remainder
    for i in simd_len..len {
        sum += coeffs[i] * samples[i];
    }

    sum as f32
}

/// Interpolate a sample using the specified quality mode.
/// Dispatches to point_sample, linear_sample, or sinc_sample.
///
/// `table`: required for Sinc mode, ignored for Point/Linear.
#[inline]
pub fn interpolate_sample(
    mode: ResampleMode,
    src_pos: f64,
    samples: &[f32],
    channels: usize,
    total_frames: usize,
    ch: usize,
    table: Option<&SincTable>,
) -> f32 {
    match mode {
        ResampleMode::Point => point_sample(src_pos, samples, channels, total_frames, ch),
        ResampleMode::Linear => linear_sample(src_pos, samples, channels, total_frames, ch),
        ResampleMode::Sinc(_) | ResampleMode::R8brain => {
            // R8brain uses block-based processing in fill_buffer() directly.
            // If we reach here with R8brain mode, fallback to sinc table.
            if let Some(t) = table {
                sinc_sample(src_pos, samples, channels, total_frames, ch, t)
            } else {
                linear_sample(src_pos, samples, channels, total_frames, ch)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sinc_table_creation() {
        let table = SincTable::new(64, 256);
        assert_eq!(table.sinc_size(), 64);
        assert_eq!(table.half_size(), 32);
    }

    #[test]
    fn test_dc_preservation() {
        // All-ones input should produce 1.0 output at any fractional position
        let table = SincTable::new(64, 256);
        let samples: Vec<f32> = vec![1.0; 1000];
        for frac in [0.0, 0.25, 0.5, 0.75, 0.999] {
            let result = sinc_sample(500.0 + frac, &samples, 1, 1000, 0, &table);
            assert!((result - 1.0).abs() < 0.001, "DC preservation failed at frac={frac}: got {result}");
        }
    }

    #[test]
    fn test_point_sample() {
        let samples = vec![0.0f32, 0.5, 1.0, 0.5, 0.0];
        assert_eq!(point_sample(2.0, &samples, 1, 5, 0), 1.0);
        assert_eq!(point_sample(2.4, &samples, 1, 5, 0), 1.0); // rounds to 2
        assert_eq!(point_sample(2.6, &samples, 1, 5, 0), 0.5); // rounds to 3
    }

    #[test]
    fn test_linear_sample() {
        let samples = vec![0.0f32, 1.0, 0.0];
        let result = linear_sample(0.5, &samples, 1, 3, 0);
        assert!((result - 0.5).abs() < 0.001, "Linear interp failed: got {result}");
    }

    #[test]
    fn test_blackman_harris_window() {
        // Window should be 0 at edges, positive in center
        let edge_start = blackman_harris_4(0.0);
        let center = blackman_harris_4(0.5);
        assert!(edge_start < 0.01, "Window not zero at start: {edge_start}");
        assert!(center > 0.9, "Window not near 1.0 at center: {center}");
    }

    #[test]
    fn test_stereo_interpolation() {
        // Stereo interleaved: [L0, R0, L1, R1, L2, R2]
        let samples = vec![0.0f32, 1.0, 0.5, 0.5, 1.0, 0.0];
        let table = SincTable::new(4, 32); // Small kernel for test

        let l = sinc_sample(1.0, &samples, 2, 3, 0, &table);
        let r = sinc_sample(1.0, &samples, 2, 3, 1, &table);
        assert!((l - 0.5).abs() < 0.01, "Stereo L failed: got {l}");
        assert!((r - 0.5).abs() < 0.01, "Stereo R failed: got {r}");
    }
}

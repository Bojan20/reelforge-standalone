//! ReelForge DSP Kernel - High-Performance Audio Processing
//!
//! Production-grade DSP for professional audio applications.
//! Designed to match or exceed Cubase/Pro Tools quality.
//!
//! Features:
//! - Zero GC (no allocations in hot paths)
//! - SIMD-optimized processing
//! - Denormal prevention (FTZ)
//! - True Peak metering (ITU-R BS.1770)
//! - 4x oversampling for dynamics
//! - Lock-free metering

use wasm_bindgen::prelude::*;

mod biquad;
mod compressor;
mod limiter;
mod metering;
mod oversampling;
mod utils;

pub use biquad::*;
pub use compressor::*;
pub use limiter::*;
pub use metering::*;
pub use oversampling::*;

// ============ Constants ============

/// Denormal threshold - values below this are flushed to zero
const DENORMAL_THRESHOLD: f32 = 1e-15;

/// Two PI for frequency calculations
const TWO_PI: f32 = std::f32::consts::PI * 2.0;

/// ln(10) / 20 for dB conversion
const LN10_OVER_20: f32 = 0.11512925464970228;

/// 20 / ln(10) for dB conversion
const TWENTY_OVER_LN10: f32 = 8.685889638065035;

// ============ Initialization ============

/// Initialize the WASM module.
/// Call once after loading.
#[wasm_bindgen(start)]
pub fn init() {
    // Set up panic hook for better error messages
    #[cfg(feature = "console_error_panic_hook")]
    console_error_panic_hook::set_once();
}

// ============ Basic Math (inline for hot paths) ============

/// Convert dB to linear gain.
#[inline(always)]
pub fn db_to_linear(db: f32) -> f32 {
    (db * LN10_OVER_20).exp()
}

/// Convert linear gain to dB.
#[inline(always)]
pub fn linear_to_db(linear: f32) -> f32 {
    if linear <= 0.0 {
        -f32::INFINITY
    } else {
        linear.ln() * TWENTY_OVER_LN10
    }
}

/// Flush denormals to zero.
/// Critical for preventing CPU spikes.
#[inline(always)]
pub fn flush_denormal(x: f32) -> f32 {
    if x.abs() < DENORMAL_THRESHOLD {
        0.0
    } else {
        x
    }
}

/// Clamp value to range.
#[inline(always)]
pub fn clamp(value: f32, min: f32, max: f32) -> f32 {
    value.max(min).min(max)
}

/// Linear interpolation.
#[inline(always)]
pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Soft clip (tanh-like, but faster).
#[inline(always)]
pub fn soft_clip(x: f32) -> f32 {
    let x2 = x * x;
    x * (27.0 + x2) / (27.0 + 9.0 * x2)
}

// ============ JS-Exposed Functions ============

/// Apply gain to stereo buffer (interleaved L/R).
#[wasm_bindgen]
pub fn apply_gain_stereo(buffer: &mut [f32], gain: f32) {
    for sample in buffer.iter_mut() {
        *sample = flush_denormal(*sample * gain);
    }
}

/// Apply gain ramp to stereo buffer (interleaved L/R).
#[wasm_bindgen]
pub fn apply_gain_ramp_stereo(buffer: &mut [f32], start_gain: f32, end_gain: f32) {
    let len = buffer.len() / 2; // stereo pairs
    if len == 0 {
        return;
    }

    let step = (end_gain - start_gain) / len as f32;
    let mut gain = start_gain;

    for i in 0..len {
        let idx = i * 2;
        buffer[idx] = flush_denormal(buffer[idx] * gain);
        buffer[idx + 1] = flush_denormal(buffer[idx + 1] * gain);
        gain += step;
    }
}

/// Mix source into destination with gain (stereo interleaved).
#[wasm_bindgen]
pub fn mix_stereo(dest: &mut [f32], source: &[f32], gain: f32) {
    let len = dest.len().min(source.len());
    for i in 0..len {
        dest[i] = flush_denormal(dest[i] + source[i] * gain);
    }
}

/// Calculate peak levels (stereo interleaved).
/// Returns [peakL, peakR].
#[wasm_bindgen]
pub fn calc_peak_stereo(buffer: &[f32]) -> Box<[f32]> {
    let mut peak_l: f32 = 0.0;
    let mut peak_r: f32 = 0.0;

    let len = buffer.len() / 2;
    for i in 0..len {
        let idx = i * 2;
        let abs_l = buffer[idx].abs();
        let abs_r = buffer[idx + 1].abs();

        if abs_l > peak_l {
            peak_l = abs_l;
        }
        if abs_r > peak_r {
            peak_r = abs_r;
        }
    }

    Box::new([peak_l, peak_r])
}

/// Calculate RMS levels (stereo interleaved).
/// Returns [rmsL, rmsR].
#[wasm_bindgen]
pub fn calc_rms_stereo(buffer: &[f32]) -> Box<[f32]> {
    let mut sum_l: f32 = 0.0;
    let mut sum_r: f32 = 0.0;

    let len = buffer.len() / 2;
    if len == 0 {
        return Box::new([0.0, 0.0]);
    }

    for i in 0..len {
        let idx = i * 2;
        sum_l += buffer[idx] * buffer[idx];
        sum_r += buffer[idx + 1] * buffer[idx + 1];
    }

    let rms_l = (sum_l / len as f32).sqrt();
    let rms_r = (sum_r / len as f32).sqrt();

    Box::new([rms_l, rms_r])
}

/// Calculate peak and RMS in one pass (stereo interleaved).
/// Returns [peakL, peakR, rmsL, rmsR].
#[wasm_bindgen]
pub fn calc_levels_stereo(buffer: &[f32]) -> Box<[f32]> {
    let mut peak_l: f32 = 0.0;
    let mut peak_r: f32 = 0.0;
    let mut sum_l: f32 = 0.0;
    let mut sum_r: f32 = 0.0;

    let len = buffer.len() / 2;
    if len == 0 {
        return Box::new([0.0, 0.0, 0.0, 0.0]);
    }

    for i in 0..len {
        let idx = i * 2;
        let l = buffer[idx];
        let r = buffer[idx + 1];

        let abs_l = l.abs();
        let abs_r = r.abs();

        if abs_l > peak_l {
            peak_l = abs_l;
        }
        if abs_r > peak_r {
            peak_r = abs_r;
        }

        sum_l += l * l;
        sum_r += r * r;
    }

    let rms_l = (sum_l / len as f32).sqrt();
    let rms_r = (sum_r / len as f32).sqrt();

    Box::new([peak_l, peak_r, rms_l, rms_r])
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_db_conversion() {
        assert!((db_to_linear(0.0) - 1.0).abs() < 1e-6);
        assert!((db_to_linear(-6.0) - 0.5011872).abs() < 1e-5);
        assert!((linear_to_db(1.0) - 0.0).abs() < 1e-6);
    }

    #[test]
    fn test_denormal_flush() {
        assert_eq!(flush_denormal(1e-20), 0.0);
        assert_eq!(flush_denormal(0.5), 0.5);
        assert_eq!(flush_denormal(-1e-20), 0.0);
    }

    #[test]
    fn test_soft_clip() {
        assert!((soft_clip(0.0) - 0.0).abs() < 1e-6);
        assert!(soft_clip(1.0) < 1.0); // Should reduce
        assert!(soft_clip(10.0) < 2.0); // Heavy limiting
    }
}

//! SIMD Dispatch System for ReelForge DSP
//!
//! Runtime SIMD feature detection with lazy-static dispatch tables.
//! Supports AVX-512, AVX2, SSE4.2, and NEON (ARM).
//!
//! # Design
//! - Detection happens once at startup
//! - Dispatch tables are static function pointers
//! - Zero overhead after initial detection
//! - Graceful fallback to scalar code

use rf_core::Sample;
use std::sync::OnceLock;

// ============ SIMD Level Detection ============

/// Detected SIMD capability level
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum SimdLevel {
    /// No SIMD, scalar fallback
    Scalar = 0,
    /// SSE4.2 (128-bit, 2 f64s)
    Sse42 = 1,
    /// AVX2 (256-bit, 4 f64s)
    Avx2 = 2,
    /// AVX-512 (512-bit, 8 f64s)
    Avx512 = 3,
    /// ARM NEON (128-bit, 2 f64s)
    Neon = 4,
}

impl SimdLevel {
    /// Get the SIMD width in f64 elements
    pub const fn width(self) -> usize {
        match self {
            SimdLevel::Scalar => 1,
            SimdLevel::Sse42 | SimdLevel::Neon => 2,
            SimdLevel::Avx2 => 4,
            SimdLevel::Avx512 => 8,
        }
    }

    /// Get human-readable name
    pub const fn name(self) -> &'static str {
        match self {
            SimdLevel::Scalar => "Scalar",
            SimdLevel::Sse42 => "SSE4.2",
            SimdLevel::Avx2 => "AVX2",
            SimdLevel::Avx512 => "AVX-512",
            SimdLevel::Neon => "NEON",
        }
    }
}

/// Global SIMD level detection (computed once)
static DETECTED_SIMD_LEVEL: OnceLock<SimdLevel> = OnceLock::new();

/// Detect the best available SIMD level
pub fn detect_simd_level() -> SimdLevel {
    *DETECTED_SIMD_LEVEL.get_or_init(|| {
        #[cfg(target_arch = "x86_64")]
        {
            if is_x86_feature_detected!("avx512f") && is_x86_feature_detected!("avx512dq") {
                return SimdLevel::Avx512;
            }
            if is_x86_feature_detected!("avx2") && is_x86_feature_detected!("fma") {
                return SimdLevel::Avx2;
            }
            if is_x86_feature_detected!("sse4.2") {
                return SimdLevel::Sse42;
            }
            SimdLevel::Scalar
        }

        #[cfg(target_arch = "aarch64")]
        {
            // NEON is always available on aarch64
            SimdLevel::Neon
        }

        #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
        {
            SimdLevel::Scalar
        }
    })
}

/// Get the current SIMD level (cached)
#[inline]
pub fn simd_level() -> SimdLevel {
    detect_simd_level()
}

// ============ Denormal Protection ============

/// Set CPU flags to flush denormals to zero (DAZ + FTZ)
/// This prevents massive CPU slowdown when processing very quiet audio
/// MUST be called once at audio thread startup
///
/// # Safety
/// This modifies the MXCSR register on x86_64.
/// The change affects the current thread only.
#[inline]
pub fn set_denormals_zero() {
    #[cfg(target_arch = "x86_64")]
    {
        // Safety: These intrinsics only affect floating-point behavior
        // and are safe to call at any time
        unsafe {
            use std::arch::x86_64::{_mm_getcsr, _mm_setcsr};
            // DAZ (Denormals Are Zero) = bit 6 (0x0040)
            // FTZ (Flush To Zero) = bit 15 (0x8000)
            let mxcsr = _mm_getcsr();
            _mm_setcsr(mxcsr | 0x8040);
        }
    }

    #[cfg(target_arch = "aarch64")]
    {
        // ARM: FPCR.FZ bit enables flush-to-zero
        // This is typically the default on ARM, but set it explicitly
        // Note: Rust doesn't have stable intrinsics for this yet,
        // so we rely on default ARM behavior
    }
}

/// Restore normal denormal handling (for compatibility tests)
#[inline]
pub fn restore_denormals() {
    #[cfg(target_arch = "x86_64")]
    {
        unsafe {
            use std::arch::x86_64::{_mm_getcsr, _mm_setcsr};
            let mxcsr = _mm_getcsr();
            _mm_setcsr(mxcsr & !0x8040);
        }
    }
}

/// Check if denormals are being flushed to zero
#[inline]
pub fn denormals_are_zero() -> bool {
    #[cfg(target_arch = "x86_64")]
    {
        unsafe {
            use std::arch::x86_64::_mm_getcsr;
            let mxcsr = _mm_getcsr();
            (mxcsr & 0x8040) == 0x8040
        }
    }

    #[cfg(not(target_arch = "x86_64"))]
    {
        true // Assume ARM handles this correctly
    }
}

// ============ Dispatch Function Types ============

/// Function pointer type for gain processing
pub type GainProcessFn = fn(&mut [Sample], Sample);

/// Function pointer type for block processing with coefficients
pub type BiquadProcessFn = fn(&mut [Sample], &BiquadCoeffsSimd, &mut BiquadStateSimd);

/// Function pointer type for mix (add with gain)
pub type MixProcessFn = fn(&mut [Sample], &[Sample], Sample);

/// Function pointer type for stereo gain
pub type StereoGainProcessFn = fn(&mut [Sample], &mut [Sample], Sample);

// ============ SIMD-Compatible Structures ============

/// Biquad coefficients in SIMD-friendly layout
#[derive(Debug, Clone, Copy)]
#[repr(C, align(64))]
pub struct BiquadCoeffsSimd {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
    // Padding for alignment
    _pad: [f64; 3],
}

impl Default for BiquadCoeffsSimd {
    fn default() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            _pad: [0.0; 3],
        }
    }
}

/// Biquad state in SIMD-friendly layout
#[derive(Debug, Clone, Copy, Default)]
#[repr(C, align(64))]
pub struct BiquadStateSimd {
    pub z1: f64,
    pub z2: f64,
    // Padding for alignment
    _pad: [f64; 6],
}

impl BiquadStateSimd {
    pub fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}

// ============ Dispatch Tables ============

/// Dispatch table for common DSP operations
pub struct DspDispatch {
    /// Apply gain to buffer
    pub apply_gain: GainProcessFn,
    /// Process biquad filter
    pub process_biquad: BiquadProcessFn,
    /// Mix source into destination with gain
    pub mix_add: MixProcessFn,
    /// Apply stereo gain
    pub stereo_gain: StereoGainProcessFn,
    /// SIMD level used
    pub level: SimdLevel,
}

impl DspDispatch {
    /// Get the global dispatch table
    pub fn get() -> &'static Self {
        static DISPATCH: OnceLock<DspDispatch> = OnceLock::new();
        DISPATCH.get_or_init(|| Self::new(detect_simd_level()))
    }

    /// Create dispatch table for specific SIMD level
    fn new(level: SimdLevel) -> Self {
        match level {
            SimdLevel::Avx512 => Self {
                apply_gain: gain_avx512,
                process_biquad: biquad_avx512,
                mix_add: mix_add_avx512,
                stereo_gain: stereo_gain_avx512,
                level,
            },
            SimdLevel::Avx2 => Self {
                apply_gain: gain_avx2,
                process_biquad: biquad_avx2,
                mix_add: mix_add_avx2,
                stereo_gain: stereo_gain_avx2,
                level,
            },
            SimdLevel::Sse42 => Self {
                apply_gain: gain_sse42,
                process_biquad: biquad_sse42,
                mix_add: mix_add_sse42,
                stereo_gain: stereo_gain_sse42,
                level,
            },
            SimdLevel::Neon => Self {
                apply_gain: gain_neon,
                process_biquad: biquad_neon,
                mix_add: mix_add_neon,
                stereo_gain: stereo_gain_neon,
                level,
            },
            SimdLevel::Scalar => Self {
                apply_gain: gain_scalar,
                process_biquad: biquad_scalar,
                mix_add: mix_add_scalar,
                stereo_gain: stereo_gain_scalar,
                level,
            },
        }
    }
}

// ============ Scalar Implementations (Fallback) ============

fn gain_scalar(buffer: &mut [Sample], gain: Sample) {
    for sample in buffer.iter_mut() {
        *sample *= gain;
    }
}

fn biquad_scalar(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    for sample in buffer.iter_mut() {
        let input = *sample;
        let output = coeffs.b0 * input + state.z1;
        state.z1 = coeffs.b1 * input - coeffs.a1 * output + state.z2;
        state.z2 = coeffs.b2 * input - coeffs.a2 * output;
        *sample = output;
    }
}

fn mix_add_scalar(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    for (d, s) in dest.iter_mut().zip(src.iter()) {
        *d += *s * gain;
    }
}

fn stereo_gain_scalar(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    for (l, r) in left.iter_mut().zip(right.iter_mut()) {
        *l *= gain;
        *r *= gain;
    }
}

// ============ x86_64 SIMD Implementations ============

#[cfg(target_arch = "x86_64")]
mod x86_impl {
    use super::*;
    use std::arch::x86_64::*;

    // --- SSE4.2 (128-bit, 2 f64s) ---

    #[target_feature(enable = "sse4.2")]
    pub unsafe fn gain_sse42_impl(buffer: &mut [Sample], gain: Sample) {
        let gain_vec = _mm_set1_pd(gain);
        let len = buffer.len();
        let simd_len = len - (len % 2);
        let ptr = buffer.as_mut_ptr();

        for i in (0..simd_len).step_by(2) {
            let input = _mm_loadu_pd(ptr.add(i));
            let output = _mm_mul_pd(input, gain_vec);
            _mm_storeu_pd(ptr.add(i), output);
        }

        // Remainder - safe because simd_len..len is always within bounds
        // simd_len = len - (len % 2), so simd_len <= len always
        debug_assert!(simd_len <= len, "SIMD remainder loop bounds check failed");
        for sample in &mut buffer[simd_len..len] {
            *sample *= gain;
        }
    }

    #[target_feature(enable = "sse4.2")]
    pub unsafe fn biquad_sse42_impl(
        buffer: &mut [Sample],
        coeffs: &BiquadCoeffsSimd,
        state: &mut BiquadStateSimd,
    ) {
        // Biquad is inherently serial due to state dependency
        // SIMD benefit comes from processing multiple filters in parallel
        // For single filter, use scalar with potential auto-vectorization
        for sample in buffer.iter_mut() {
            let input = *sample;
            let output = coeffs.b0 * input + state.z1;
            state.z1 = coeffs.b1 * input - coeffs.a1 * output + state.z2;
            state.z2 = coeffs.b2 * input - coeffs.a2 * output;
            *sample = output;
        }
    }

    #[target_feature(enable = "sse4.2")]
    pub unsafe fn mix_add_sse42_impl(dest: &mut [Sample], src: &[Sample], gain: Sample) {
        let gain_vec = _mm_set1_pd(gain);
        let len = dest.len().min(src.len());
        let simd_len = len - (len % 2);
        let dest_ptr = dest.as_mut_ptr();
        let src_ptr = src.as_ptr();

        for i in (0..simd_len).step_by(2) {
            let d = _mm_loadu_pd(dest_ptr.add(i));
            let s = _mm_loadu_pd(src_ptr.add(i));
            let result = _mm_add_pd(d, _mm_mul_pd(s, gain_vec));
            _mm_storeu_pd(dest_ptr.add(i), result);
        }

        // Remainder - safe because simd_len..len is within bounds of both slices
        debug_assert!(simd_len <= len, "SIMD mix_add remainder loop bounds check failed");
        for i in simd_len..len {
            dest[i] += src[i] * gain;
        }
    }

    #[target_feature(enable = "sse4.2")]
    pub unsafe fn stereo_gain_sse42_impl(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
        gain_sse42_impl(left, gain);
        gain_sse42_impl(right, gain);
    }

    // --- AVX2 (256-bit, 4 f64s) ---

    #[target_feature(enable = "avx2", enable = "fma")]
    pub unsafe fn gain_avx2_impl(buffer: &mut [Sample], gain: Sample) {
        let gain_vec = _mm256_set1_pd(gain);
        let len = buffer.len();
        let simd_len = len - (len % 4);
        let ptr = buffer.as_mut_ptr();

        for i in (0..simd_len).step_by(4) {
            let input = _mm256_loadu_pd(ptr.add(i));
            let output = _mm256_mul_pd(input, gain_vec);
            _mm256_storeu_pd(ptr.add(i), output);
        }

        // Remainder - safe because simd_len..len is always within bounds
        debug_assert!(simd_len <= len, "AVX2 remainder loop bounds check failed");
        for sample in &mut buffer[simd_len..len] {
            *sample *= gain;
        }
    }

    #[target_feature(enable = "avx2", enable = "fma")]
    pub unsafe fn biquad_avx2_impl(
        buffer: &mut [Sample],
        coeffs: &BiquadCoeffsSimd,
        state: &mut BiquadStateSimd,
    ) {
        // Same as SSE - biquad is serial
        biquad_sse42_impl(buffer, coeffs, state);
    }

    #[target_feature(enable = "avx2", enable = "fma")]
    pub unsafe fn mix_add_avx2_impl(dest: &mut [Sample], src: &[Sample], gain: Sample) {
        let gain_vec = _mm256_set1_pd(gain);
        let len = dest.len().min(src.len());
        let simd_len = len - (len % 4);
        let dest_ptr = dest.as_mut_ptr();
        let src_ptr = src.as_ptr();

        for i in (0..simd_len).step_by(4) {
            let d = _mm256_loadu_pd(dest_ptr.add(i));
            let s = _mm256_loadu_pd(src_ptr.add(i));
            // FMA: d + s * gain
            let result = _mm256_fmadd_pd(s, gain_vec, d);
            _mm256_storeu_pd(dest_ptr.add(i), result);
        }

        // Remainder - safe because simd_len..len is within bounds
        debug_assert!(simd_len <= len, "AVX2 mix_add remainder loop bounds check failed");
        for i in simd_len..len {
            dest[i] += src[i] * gain;
        }
    }

    #[target_feature(enable = "avx2", enable = "fma")]
    pub unsafe fn stereo_gain_avx2_impl(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
        gain_avx2_impl(left, gain);
        gain_avx2_impl(right, gain);
    }

    // --- AVX-512 (512-bit, 8 f64s) ---

    #[cfg(feature = "avx512")]
    #[target_feature(enable = "avx512f", enable = "avx512dq")]
    pub unsafe fn gain_avx512_impl(buffer: &mut [Sample], gain: Sample) {
        let gain_vec = _mm512_set1_pd(gain);
        let len = buffer.len();
        let simd_len = len - (len % 8);
        let ptr = buffer.as_mut_ptr();

        for i in (0..simd_len).step_by(8) {
            let input = _mm512_loadu_pd(ptr.add(i));
            let output = _mm512_mul_pd(input, gain_vec);
            _mm512_storeu_pd(ptr.add(i), output);
        }

        // Remainder with AVX2
        if simd_len < len {
            gain_avx2_impl(&mut buffer[simd_len..], gain);
        }
    }

    #[cfg(not(feature = "avx512"))]
    pub unsafe fn gain_avx512_impl(buffer: &mut [Sample], gain: Sample) {
        gain_avx2_impl(buffer, gain);
    }

    #[cfg(feature = "avx512")]
    #[target_feature(enable = "avx512f", enable = "avx512dq")]
    pub unsafe fn biquad_avx512_impl(
        buffer: &mut [Sample],
        coeffs: &BiquadCoeffsSimd,
        state: &mut BiquadStateSimd,
    ) {
        // Biquad still serial
        biquad_sse42_impl(buffer, coeffs, state);
    }

    #[cfg(not(feature = "avx512"))]
    pub unsafe fn biquad_avx512_impl(
        buffer: &mut [Sample],
        coeffs: &BiquadCoeffsSimd,
        state: &mut BiquadStateSimd,
    ) {
        biquad_avx2_impl(buffer, coeffs, state);
    }

    #[cfg(feature = "avx512")]
    #[target_feature(enable = "avx512f", enable = "avx512dq")]
    pub unsafe fn mix_add_avx512_impl(dest: &mut [Sample], src: &[Sample], gain: Sample) {
        let gain_vec = _mm512_set1_pd(gain);
        let len = dest.len().min(src.len());
        let simd_len = len - (len % 8);
        let dest_ptr = dest.as_mut_ptr();
        let src_ptr = src.as_ptr();

        for i in (0..simd_len).step_by(8) {
            let d = _mm512_loadu_pd(dest_ptr.add(i));
            let s = _mm512_loadu_pd(src_ptr.add(i));
            let result = _mm512_fmadd_pd(s, gain_vec, d);
            _mm512_storeu_pd(dest_ptr.add(i), result);
        }

        if simd_len < len {
            mix_add_avx2_impl(&mut dest[simd_len..], &src[simd_len..], gain);
        }
    }

    #[cfg(not(feature = "avx512"))]
    pub unsafe fn mix_add_avx512_impl(dest: &mut [Sample], src: &[Sample], gain: Sample) {
        mix_add_avx2_impl(dest, src, gain);
    }

    #[cfg(feature = "avx512")]
    #[target_feature(enable = "avx512f", enable = "avx512dq")]
    pub unsafe fn stereo_gain_avx512_impl(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
        gain_avx512_impl(left, gain);
        gain_avx512_impl(right, gain);
    }

    #[cfg(not(feature = "avx512"))]
    pub unsafe fn stereo_gain_avx512_impl(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
        stereo_gain_avx2_impl(left, right, gain);
    }
}

// ============ ARM NEON Implementations ============

#[cfg(target_arch = "aarch64")]
mod arm_impl {
    use super::*;
    use std::arch::aarch64::*;

    pub unsafe fn gain_neon_impl(buffer: &mut [Sample], gain: Sample) {
        unsafe {
            let gain_vec = vdupq_n_f64(gain);
            let len = buffer.len();
            let simd_len = len - (len % 2);
            let ptr = buffer.as_mut_ptr();

            for i in (0..simd_len).step_by(2) {
                let input = vld1q_f64(ptr.add(i));
                let output = vmulq_f64(input, gain_vec);
                vst1q_f64(ptr.add(i), output);
            }

            // Remainder - safe because simd_len..len is always within bounds
            debug_assert!(simd_len <= len, "NEON remainder loop bounds check failed");
            for sample in &mut buffer[simd_len..len] {
                *sample *= gain;
            }
        }
    }

    pub unsafe fn biquad_neon_impl(
        buffer: &mut [Sample],
        coeffs: &BiquadCoeffsSimd,
        state: &mut BiquadStateSimd,
    ) {
        // Biquad is serial - no SIMD intrinsics needed
        for sample in buffer.iter_mut() {
            let input = *sample;
            let output = coeffs.b0 * input + state.z1;
            state.z1 = coeffs.b1 * input - coeffs.a1 * output + state.z2;
            state.z2 = coeffs.b2 * input - coeffs.a2 * output;
            *sample = output;
        }
    }

    pub unsafe fn mix_add_neon_impl(dest: &mut [Sample], src: &[Sample], gain: Sample) {
        unsafe {
            let gain_vec = vdupq_n_f64(gain);
            let len = dest.len().min(src.len());
            let simd_len = len - (len % 2);
            let dest_ptr = dest.as_mut_ptr();
            let src_ptr = src.as_ptr();

            for i in (0..simd_len).step_by(2) {
                let d = vld1q_f64(dest_ptr.add(i));
                let s = vld1q_f64(src_ptr.add(i));
                let result = vfmaq_f64(d, s, gain_vec);
                vst1q_f64(dest_ptr.add(i), result);
            }

            // Remainder - safe because simd_len..len is within bounds
            debug_assert!(simd_len <= len, "NEON mix_add remainder loop bounds check failed");
            for i in simd_len..len {
                dest[i] += src[i] * gain;
            }
        }
    }

    pub unsafe fn stereo_gain_neon_impl(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
        unsafe {
            gain_neon_impl(left, gain);
            gain_neon_impl(right, gain);
        }
    }
}

// ============ Safe Wrapper Functions ============

// SSE4.2 wrappers
#[cfg(target_arch = "x86_64")]
fn gain_sse42(buffer: &mut [Sample], gain: Sample) {
    unsafe { x86_impl::gain_sse42_impl(buffer, gain) }
}

#[cfg(target_arch = "x86_64")]
fn biquad_sse42(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    unsafe { x86_impl::biquad_sse42_impl(buffer, coeffs, state) }
}

#[cfg(target_arch = "x86_64")]
fn mix_add_sse42(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    unsafe { x86_impl::mix_add_sse42_impl(dest, src, gain) }
}

#[cfg(target_arch = "x86_64")]
fn stereo_gain_sse42(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    unsafe { x86_impl::stereo_gain_sse42_impl(left, right, gain) }
}

// AVX2 wrappers
#[cfg(target_arch = "x86_64")]
fn gain_avx2(buffer: &mut [Sample], gain: Sample) {
    unsafe { x86_impl::gain_avx2_impl(buffer, gain) }
}

#[cfg(target_arch = "x86_64")]
fn biquad_avx2(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    unsafe { x86_impl::biquad_avx2_impl(buffer, coeffs, state) }
}

#[cfg(target_arch = "x86_64")]
fn mix_add_avx2(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    unsafe { x86_impl::mix_add_avx2_impl(dest, src, gain) }
}

#[cfg(target_arch = "x86_64")]
fn stereo_gain_avx2(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    unsafe { x86_impl::stereo_gain_avx2_impl(left, right, gain) }
}

// AVX-512 wrappers
#[cfg(target_arch = "x86_64")]
fn gain_avx512(buffer: &mut [Sample], gain: Sample) {
    unsafe { x86_impl::gain_avx512_impl(buffer, gain) }
}

#[cfg(target_arch = "x86_64")]
fn biquad_avx512(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    unsafe { x86_impl::biquad_avx512_impl(buffer, coeffs, state) }
}

#[cfg(target_arch = "x86_64")]
fn mix_add_avx512(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    unsafe { x86_impl::mix_add_avx512_impl(dest, src, gain) }
}

#[cfg(target_arch = "x86_64")]
fn stereo_gain_avx512(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    unsafe { x86_impl::stereo_gain_avx512_impl(left, right, gain) }
}

// NEON wrappers
#[cfg(target_arch = "aarch64")]
fn gain_neon(buffer: &mut [Sample], gain: Sample) {
    unsafe { arm_impl::gain_neon_impl(buffer, gain) }
}

#[cfg(target_arch = "aarch64")]
fn biquad_neon(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    unsafe { arm_impl::biquad_neon_impl(buffer, coeffs, state) }
}

#[cfg(target_arch = "aarch64")]
fn mix_add_neon(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    unsafe { arm_impl::mix_add_neon_impl(dest, src, gain) }
}

#[cfg(target_arch = "aarch64")]
fn stereo_gain_neon(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    unsafe { arm_impl::stereo_gain_neon_impl(left, right, gain) }
}

// Fallback stubs for non-matching architectures
#[cfg(not(target_arch = "x86_64"))]
fn gain_sse42(buffer: &mut [Sample], gain: Sample) {
    gain_scalar(buffer, gain)
}
#[cfg(not(target_arch = "x86_64"))]
fn biquad_sse42(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    biquad_scalar(buffer, coeffs, state)
}
#[cfg(not(target_arch = "x86_64"))]
fn mix_add_sse42(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    mix_add_scalar(dest, src, gain)
}
#[cfg(not(target_arch = "x86_64"))]
fn stereo_gain_sse42(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    stereo_gain_scalar(left, right, gain)
}

#[cfg(not(target_arch = "x86_64"))]
fn gain_avx2(buffer: &mut [Sample], gain: Sample) {
    gain_scalar(buffer, gain)
}
#[cfg(not(target_arch = "x86_64"))]
fn biquad_avx2(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    biquad_scalar(buffer, coeffs, state)
}
#[cfg(not(target_arch = "x86_64"))]
fn mix_add_avx2(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    mix_add_scalar(dest, src, gain)
}
#[cfg(not(target_arch = "x86_64"))]
fn stereo_gain_avx2(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    stereo_gain_scalar(left, right, gain)
}

#[cfg(not(target_arch = "x86_64"))]
fn gain_avx512(buffer: &mut [Sample], gain: Sample) {
    gain_scalar(buffer, gain)
}
#[cfg(not(target_arch = "x86_64"))]
fn biquad_avx512(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    biquad_scalar(buffer, coeffs, state)
}
#[cfg(not(target_arch = "x86_64"))]
fn mix_add_avx512(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    mix_add_scalar(dest, src, gain)
}
#[cfg(not(target_arch = "x86_64"))]
fn stereo_gain_avx512(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    stereo_gain_scalar(left, right, gain)
}

#[cfg(not(target_arch = "aarch64"))]
fn gain_neon(buffer: &mut [Sample], gain: Sample) {
    gain_scalar(buffer, gain)
}
#[cfg(not(target_arch = "aarch64"))]
fn biquad_neon(buffer: &mut [Sample], coeffs: &BiquadCoeffsSimd, state: &mut BiquadStateSimd) {
    biquad_scalar(buffer, coeffs, state)
}
#[cfg(not(target_arch = "aarch64"))]
fn mix_add_neon(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    mix_add_scalar(dest, src, gain)
}
#[cfg(not(target_arch = "aarch64"))]
fn stereo_gain_neon(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    stereo_gain_scalar(left, right, gain)
}

// ============ Convenience Functions ============

/// Apply gain using best available SIMD
#[inline]
pub fn apply_gain(buffer: &mut [Sample], gain: Sample) {
    (DspDispatch::get().apply_gain)(buffer, gain)
}

/// Process biquad using best available SIMD
#[inline]
pub fn process_biquad(
    buffer: &mut [Sample],
    coeffs: &BiquadCoeffsSimd,
    state: &mut BiquadStateSimd,
) {
    (DspDispatch::get().process_biquad)(buffer, coeffs, state)
}

/// Mix source into destination with gain using best available SIMD
#[inline]
pub fn mix_add(dest: &mut [Sample], src: &[Sample], gain: Sample) {
    (DspDispatch::get().mix_add)(dest, src, gain)
}

/// Apply stereo gain using best available SIMD
#[inline]
pub fn apply_stereo_gain(left: &mut [Sample], right: &mut [Sample], gain: Sample) {
    (DspDispatch::get().stereo_gain)(left, right, gain)
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simd_detection() {
        let level = detect_simd_level();
        println!("Detected SIMD level: {:?} ({})", level, level.name());
        assert!(level.width() >= 1);
    }

    #[test]
    fn test_gain_scalar() {
        let mut buffer = vec![1.0, 2.0, 3.0, 4.0];
        gain_scalar(&mut buffer, 2.0);
        assert_eq!(buffer, vec![2.0, 4.0, 6.0, 8.0]);
    }

    #[test]
    fn test_apply_gain() {
        let mut buffer = vec![1.0; 100];
        apply_gain(&mut buffer, 0.5);
        for sample in &buffer {
            assert!((*sample - 0.5).abs() < 1e-10);
        }
    }

    #[test]
    fn test_mix_add() {
        let mut dest = vec![1.0; 100];
        let src = vec![2.0; 100];
        mix_add(&mut dest, &src, 0.5);
        for sample in &dest {
            assert!((*sample - 2.0).abs() < 1e-10); // 1.0 + 2.0 * 0.5 = 2.0
        }
    }

    #[test]
    fn test_biquad_bypass() {
        let coeffs = BiquadCoeffsSimd::default(); // bypass
        let mut state = BiquadStateSimd::default();
        let mut buffer = vec![1.0, 2.0, 3.0, 4.0];
        process_biquad(&mut buffer, &coeffs, &mut state);
        // Bypass should pass through
        assert!((buffer[0] - 1.0).abs() < 1e-10);
    }
}

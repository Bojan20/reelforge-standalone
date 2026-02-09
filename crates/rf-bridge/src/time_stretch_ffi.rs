//! P12.1.4 — Time-Stretch FFI
//!
//! C FFI exports for simple phase vocoder time stretching.
//! Used by SlotLab to match audio duration to animation timing.
//!
//! ## Use Case
//!
//! Win rollup audio matching rollup animation duration:
//! - Rollup animation: 2500ms
//! - Audio file: 2000ms
//! - Time-stretch factor: 2500/2000 = 1.25x

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use rf_dsp::time_stretch::SimplePhaseVocoder;
use std::collections::HashMap;
use std::ptr;
use std::slice;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Global time stretch processor pool
static TIME_STRETCH_PROCESSORS: Lazy<RwLock<HashMap<i32, SimplePhaseVocoder>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Next processor handle
static NEXT_HANDLE: Lazy<RwLock<i32>> = Lazy::new(|| RwLock::new(1));

/// Allocate and return the next handle
fn allocate_handle() -> i32 {
    let mut next = NEXT_HANDLE.write();
    let handle = *next;
    *next += 1;
    handle
}

// ═══════════════════════════════════════════════════════════════════════════════
// C FFI EXPORTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a time-stretch processor
///
/// # Arguments
///
/// * `sample_rate` - Audio sample rate in Hz
///
/// # Returns
///
/// Handle to the processor (> 0) or 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_create(sample_rate: f64) -> i32 {
    if sample_rate <= 0.0 || sample_rate > 384000.0 {
        return 0;
    }

    let handle = allocate_handle();
    let processor = SimplePhaseVocoder::new_default(sample_rate);

    let mut processors = TIME_STRETCH_PROCESSORS.write();
    processors.insert(handle, processor);

    handle
}

/// Create a time-stretch processor with custom FFT size
///
/// # Arguments
///
/// * `fft_size` - FFT size (power of 2, typically 1024-4096)
/// * `sample_rate` - Audio sample rate in Hz
///
/// # Returns
///
/// Handle to the processor (> 0) or 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_create_with_fft_size(fft_size: usize, sample_rate: f64) -> i32 {
    if sample_rate <= 0.0 || sample_rate > 384000.0 {
        return 0;
    }

    // Validate FFT size (must be power of 2)
    if fft_size < 256 || fft_size > 8192 || !fft_size.is_power_of_two() {
        return 0;
    }

    let handle = allocate_handle();
    let processor = SimplePhaseVocoder::new(fft_size, sample_rate);

    let mut processors = TIME_STRETCH_PROCESSORS.write();
    processors.insert(handle, processor);

    handle
}

/// Process audio with time stretching
///
/// # Arguments
///
/// * `handle` - Processor handle from time_stretch_create
/// * `input` - Pointer to input audio samples (f64)
/// * `input_len` - Number of input samples
/// * `factor` - Time stretch factor (0.5-2.0):
///   - < 1.0 = speed up (shorter duration)
///   - > 1.0 = slow down (longer duration)
/// * `out_len` - Pointer to write output length
///
/// # Returns
///
/// Pointer to output samples (must be freed with time_stretch_free) or null on error
///
/// # Safety
///
/// - `input` must be a valid pointer to `input_len` f64 samples
/// - `out_len` must be a valid pointer
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_process(
    handle: i32,
    input: *const f64,
    input_len: usize,
    factor: f64,
    out_len: *mut usize,
) -> *mut f64 {
    // Validate pointers
    if input.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }

    // Validate factor
    if factor <= 0.0 || factor.is_nan() || factor.is_infinite() {
        return ptr::null_mut();
    }

    // Get processor
    let mut processors = TIME_STRETCH_PROCESSORS.write();
    let processor = match processors.get_mut(&handle) {
        Some(p) => p,
        None => return ptr::null_mut(),
    };

    // Read input
    let input_slice = unsafe { slice::from_raw_parts(input, input_len) };

    // Process
    let output = processor.process(input_slice, factor);

    // Write output length
    unsafe {
        *out_len = output.len();
    }

    // Allocate output buffer and copy data
    if output.is_empty() {
        return ptr::null_mut();
    }

    let output_boxed = output.into_boxed_slice();
    Box::into_raw(output_boxed) as *mut f64
}

/// Match audio duration to target duration
///
/// # Arguments
///
/// * `handle` - Processor handle from time_stretch_create
/// * `input` - Pointer to input audio samples (f64)
/// * `input_len` - Number of input samples
/// * `target_duration_ms` - Target duration in milliseconds
/// * `out_len` - Pointer to write output length
///
/// # Returns
///
/// Pointer to output samples (must be freed with time_stretch_free) or null on error
///
/// # Safety
///
/// - `input` must be a valid pointer to `input_len` f64 samples
/// - `out_len` must be a valid pointer
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_match_duration(
    handle: i32,
    input: *const f64,
    input_len: usize,
    target_duration_ms: f64,
    out_len: *mut usize,
) -> *mut f64 {
    // Validate pointers
    if input.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }

    // Validate target duration
    if target_duration_ms <= 0.0 || target_duration_ms.is_nan() || target_duration_ms.is_infinite()
    {
        return ptr::null_mut();
    }

    // Get processor
    let mut processors = TIME_STRETCH_PROCESSORS.write();
    let processor = match processors.get_mut(&handle) {
        Some(p) => p,
        None => return ptr::null_mut(),
    };

    // Read input
    let input_slice = unsafe { slice::from_raw_parts(input, input_len) };

    // Process
    let output = processor.match_duration(input_slice, target_duration_ms);

    // Write output length
    unsafe {
        *out_len = output.len();
    }

    // Allocate output buffer and copy data
    if output.is_empty() {
        return ptr::null_mut();
    }

    let output_boxed = output.into_boxed_slice();
    Box::into_raw(output_boxed) as *mut f64
}

/// Free stretched audio buffer
///
/// # Arguments
///
/// * `ptr` - Pointer to buffer allocated by time_stretch_process
/// * `len` - Length of the buffer
///
/// # Safety
///
/// - `ptr` must be a valid pointer returned by time_stretch_process or time_stretch_match_duration
/// - `len` must be the length returned via out_len
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_free(ptr: *mut f64, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }

    // Reconstruct the boxed slice and drop it
    unsafe {
        let slice = slice::from_raw_parts_mut(ptr, len);
        let _ = Box::from_raw(slice as *mut [f64]);
    }
}

/// Reset processor state
///
/// # Arguments
///
/// * `handle` - Processor handle
///
/// # Returns
///
/// 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_reset(handle: i32) -> i32 {
    let mut processors = TIME_STRETCH_PROCESSORS.write();
    match processors.get_mut(&handle) {
        Some(p) => {
            p.reset();
            1
        }
        None => 0,
    }
}

/// Destroy processor
///
/// # Arguments
///
/// * `handle` - Processor handle
///
/// # Returns
///
/// 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_destroy(handle: i32) -> i32 {
    let mut processors = TIME_STRETCH_PROCESSORS.write();
    match processors.remove(&handle) {
        Some(_) => 1,
        None => 0,
    }
}

/// Calculate stretch factor to match target duration
///
/// # Arguments
///
/// * `audio_samples` - Number of samples in input audio
/// * `sample_rate` - Audio sample rate
/// * `target_duration_ms` - Target duration in milliseconds
///
/// # Returns
///
/// Stretch factor (> 1.0 = slow down, < 1.0 = speed up)
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_calculate_factor(
    audio_samples: usize,
    sample_rate: f64,
    target_duration_ms: f64,
) -> f64 {
    rf_dsp::time_stretch::calculate_stretch_factor(audio_samples, sample_rate, target_duration_ms)
}

/// Get audio duration in milliseconds
///
/// # Arguments
///
/// * `samples` - Number of samples
/// * `sample_rate` - Sample rate
///
/// # Returns
///
/// Duration in milliseconds
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_audio_duration_ms(samples: usize, sample_rate: f64) -> f64 {
    rf_dsp::time_stretch::audio_duration_ms(samples, sample_rate)
}

/// Get processor count (for debugging)
#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_processor_count() -> i32 {
    TIME_STRETCH_PROCESSORS.read().len() as i32
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_destroy() {
        let handle = time_stretch_create(44100.0);
        assert!(handle > 0);

        let result = time_stretch_destroy(handle);
        assert_eq!(result, 1);

        // Double destroy should fail
        let result = time_stretch_destroy(handle);
        assert_eq!(result, 0);
    }

    #[test]
    fn test_invalid_sample_rate() {
        let handle = time_stretch_create(-1.0);
        assert_eq!(handle, 0);

        let handle = time_stretch_create(0.0);
        assert_eq!(handle, 0);
    }

    #[test]
    fn test_process() {
        let handle = time_stretch_create(44100.0);
        assert!(handle > 0);

        // Create test input
        let input: Vec<f64> = (0..4410).map(|i| (i as f64 * 0.01).sin()).collect();

        let mut out_len: usize = 0;
        let output_ptr = time_stretch_process(
            handle,
            input.as_ptr(),
            input.len(),
            1.5,
            &mut out_len as *mut usize,
        );

        assert!(!output_ptr.is_null());
        assert!(out_len > 0);

        // Free output
        time_stretch_free(output_ptr, out_len);

        // Cleanup
        time_stretch_destroy(handle);
    }

    #[test]
    fn test_match_duration() {
        let handle = time_stretch_create(44100.0);
        assert!(handle > 0);

        // Create 1 second of audio at 44.1kHz
        let input: Vec<f64> = (0..44100).map(|i| (i as f64 * 0.01).sin()).collect();

        let mut out_len: usize = 0;
        let output_ptr = time_stretch_match_duration(
            handle,
            input.as_ptr(),
            input.len(),
            1500.0, // Target 1.5 seconds
            &mut out_len as *mut usize,
        );

        assert!(!output_ptr.is_null());

        // Output should be ~1.5x input length
        let ratio = out_len as f64 / input.len() as f64;
        assert!((ratio - 1.5).abs() < 0.1);

        // Free output
        time_stretch_free(output_ptr, out_len);

        // Cleanup
        time_stretch_destroy(handle);
    }

    #[test]
    fn test_calculate_factor() {
        let factor = time_stretch_calculate_factor(44100, 44100.0, 2000.0);
        assert!((factor - 2.0).abs() < 0.01);
    }

    #[test]
    fn test_audio_duration_ms() {
        let duration = time_stretch_audio_duration_ms(44100, 44100.0);
        assert!((duration - 1000.0).abs() < 0.1);
    }
}

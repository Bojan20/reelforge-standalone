//! P12.1.4 — Time-Stretch FFI
//!
//! C FFI exports for time stretching using Signalsmith Stretch (MIT).
//! Used by SlotLab to match audio duration to animation timing.
//!
//! ## Use Case
//!
//! Win rollup audio matching rollup animation duration:
//! - Rollup animation: 2500ms
//! - Audio file: 2000ms
//! - Time-stretch factor: 2500/2000 = 1.25x

use std::sync::LazyLock;
use parking_lot::RwLock;
use signalsmith_stretch::Stretch;
use std::collections::HashMap;
use std::ptr;
use std::slice;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

struct SignalsmithProcessor {
    inner: Stretch,
    sample_rate: f64,
}

static TIME_STRETCH_PROCESSORS: LazyLock<RwLock<HashMap<i32, SignalsmithProcessor>>> =
    LazyLock::new(|| RwLock::new(HashMap::new()));

static NEXT_HANDLE: LazyLock<RwLock<i32>> = LazyLock::new(|| RwLock::new(1));

fn allocate_handle() -> i32 {
    let mut next = NEXT_HANDLE.write();
    let handle = *next;
    *next += 1;
    handle
}

// ═══════════════════════════════════════════════════════════════════════════════
// C FFI EXPORTS
// ═══════════════════════════════════════════════════════════════════════════════

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_create(sample_rate: f64) -> i32 {
    if sample_rate <= 0.0 || sample_rate > 384000.0 {
        return 0;
    }

    let handle = allocate_handle();
    let inner = Stretch::preset_default(1, sample_rate as u32);

    let mut processors = TIME_STRETCH_PROCESSORS.write();
    processors.insert(handle, SignalsmithProcessor { inner, sample_rate });

    handle
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_create_with_fft_size(_fft_size: usize, sample_rate: f64) -> i32 {
    // Signalsmith doesn't expose FFT size — use default preset.
    // FFI signature preserved for backwards compatibility.
    time_stretch_create(sample_rate)
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_process(
    handle: i32,
    input: *const f64,
    input_len: usize,
    factor: f64,
    out_len: *mut usize,
) -> *mut f64 {
    if input.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }

    if factor <= 0.0 || factor.is_nan() || factor.is_infinite() {
        return ptr::null_mut();
    }

    let mut processors = TIME_STRETCH_PROCESSORS.write();
    let processor = match processors.get_mut(&handle) {
        Some(p) => p,
        None => return ptr::null_mut(),
    };

    let input_slice = unsafe { slice::from_raw_parts(input, input_len) };

    let output = stretch_mono(processor, input_slice, factor);

    unsafe {
        *out_len = output.len();
    }

    if output.is_empty() {
        return ptr::null_mut();
    }

    let output_boxed = output.into_boxed_slice();
    Box::into_raw(output_boxed) as *mut f64
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_match_duration(
    handle: i32,
    input: *const f64,
    input_len: usize,
    target_duration_ms: f64,
    out_len: *mut usize,
) -> *mut f64 {
    if input.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }

    if target_duration_ms <= 0.0 || target_duration_ms.is_nan() || target_duration_ms.is_infinite()
    {
        return ptr::null_mut();
    }

    let mut processors = TIME_STRETCH_PROCESSORS.write();
    let processor = match processors.get_mut(&handle) {
        Some(p) => p,
        None => return ptr::null_mut(),
    };

    let input_slice = unsafe { slice::from_raw_parts(input, input_len) };

    let current_duration_ms = input_len as f64 / processor.sample_rate * 1000.0;
    if current_duration_ms <= 0.0 {
        return ptr::null_mut();
    }
    let factor = target_duration_ms / current_duration_ms;

    let output = stretch_mono(processor, input_slice, factor);

    unsafe {
        *out_len = output.len();
    }

    if output.is_empty() {
        return ptr::null_mut();
    }

    let output_boxed = output.into_boxed_slice();
    Box::into_raw(output_boxed) as *mut f64
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_free(ptr: *mut f64, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }

    unsafe {
        let slice = slice::from_raw_parts_mut(ptr, len);
        let _ = Box::from_raw(slice as *mut [f64]);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_reset(handle: i32) -> i32 {
    let mut processors = TIME_STRETCH_PROCESSORS.write();
    match processors.get_mut(&handle) {
        Some(p) => {
            p.inner.reset();
            1
        }
        None => 0,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_destroy(handle: i32) -> i32 {
    let mut processors = TIME_STRETCH_PROCESSORS.write();
    match processors.remove(&handle) {
        Some(_) => 1,
        None => 0,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_calculate_factor(
    audio_samples: usize,
    sample_rate: f64,
    target_duration_ms: f64,
) -> f64 {
    if audio_samples == 0 || sample_rate <= 0.0 || target_duration_ms <= 0.0 {
        return 1.0;
    }
    let current_ms = audio_samples as f64 / sample_rate * 1000.0;
    target_duration_ms / current_ms
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_audio_duration_ms(samples: usize, sample_rate: f64) -> f64 {
    if sample_rate <= 0.0 {
        return 0.0;
    }
    samples as f64 / sample_rate * 1000.0
}

#[unsafe(no_mangle)]
pub extern "C" fn time_stretch_processor_count() -> i32 {
    TIME_STRETCH_PROCESSORS.read().len() as i32
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL
// ═══════════════════════════════════════════════════════════════════════════════

fn stretch_mono(proc: &mut SignalsmithProcessor, input: &[f64], factor: f64) -> Vec<f64> {
    let factor = factor.clamp(0.1, 10.0);
    let total_in = input.len();
    let total_out = (total_in as f64 * factor).ceil() as usize;

    if total_out == 0 {
        return vec![];
    }

    proc.inner.reset();
    // No pitch shift for SlotLab time-stretch
    proc.inner.set_transpose_factor_semitones(0.0, None);

    let mut output = vec![0.0f64; total_out];

    // Pre-feed silence to flush latency
    let latency = proc.inner.input_latency() + proc.inner.output_latency();
    if latency > 0 {
        let silence_in = vec![0.0f32; latency];
        let mut silence_out = vec![0.0f32; latency];
        proc.inner.process(&silence_in, &mut silence_out);
    }

    let block_in = 4096usize;
    let mut in_pos = 0usize;
    let mut out_pos = 0usize;

    while in_pos < total_in && out_pos < total_out {
        let this_in = block_in.min(total_in - in_pos);
        let this_out = ((this_in as f64 * factor).ceil() as usize)
            .min(total_out - out_pos)
            .max(1);

        // Mono: channel_count=1, so interleaved = plain f32 mono
        let input_f32: Vec<f32> = input[in_pos..in_pos + this_in]
            .iter()
            .map(|&s| s as f32)
            .collect();

        let mut output_f32 = vec![0.0f32; this_out];
        proc.inner.process(&input_f32, &mut output_f32);

        for i in 0..this_out {
            if out_pos + i < total_out {
                output[out_pos + i] = output_f32[i] as f64;
            }
        }

        in_pos += this_in;
        out_pos += this_out;
    }

    // Flush tail
    let flush_frames = 4096;
    let silence_in = vec![0.0f32; flush_frames];
    let mut flush_out = vec![0.0f32; flush_frames];
    for _ in 0..4 {
        proc.inner.process(&silence_in, &mut flush_out);
        for i in 0..flush_frames {
            if out_pos + i < total_out {
                output[out_pos + i] = flush_out[i] as f64;
            }
        }
        out_pos += flush_frames;
        if out_pos >= total_out {
            break;
        }
    }

    output
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

        time_stretch_free(output_ptr, out_len);
        time_stretch_destroy(handle);
    }

    #[test]
    fn test_match_duration() {
        let handle = time_stretch_create(44100.0);
        assert!(handle > 0);

        let input: Vec<f64> = (0..44100).map(|i| (i as f64 * 0.01).sin()).collect();

        let mut out_len: usize = 0;
        let output_ptr = time_stretch_match_duration(
            handle,
            input.as_ptr(),
            input.len(),
            1500.0,
            &mut out_len as *mut usize,
        );

        assert!(!output_ptr.is_null());

        let ratio = out_len as f64 / input.len() as f64;
        assert!((ratio - 1.5).abs() < 0.15, "Ratio was {ratio}, expected ~1.5");

        time_stretch_free(output_ptr, out_len);
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

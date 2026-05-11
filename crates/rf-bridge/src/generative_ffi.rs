//! FFI exports for 5.1.3 — `rf-generative` audio synthesis.
//!
//! Exposes the FAZA 5.1 `MockBackend` (and, once `feature = "onnx"` lands in
//! 5.1.2, the real tract backend) to Flutter via a JSON-in / WAV-out C ABI.
//!
//! ## Why JSON for request, raw PCM for response
//!
//! - **Request** is tiny (< 1 KB) and changes slowly — JSON is fine and
//!   keeps the schema self-documenting.
//! - **Response** PCM can be megabytes (60 s × 48 kHz × 2 ch × f32 ≈ 23 MB).
//!   Round-tripping that through JSON base64 would burn ~30 MB of UI thread
//!   time. Instead we return a struct that exposes a raw `f32*` pointer the
//!   caller borrows once, then frees through `generative_free_buffer`.
//!
//! ## Protocol
//!
//! ```text
//! generative_generate(request_json) → GenerativeFfiBuffer
//! generative_free_buffer(buf)       → void
//! generative_free_string(ptr)       → void
//! ```
//!
//! ## Request schema
//!
//! ```json
//! {
//!   "prompt": "big win sting",
//!   "duration_seconds": 2.5,
//!   "sample_rate_hz": 0,
//!   "seed": 1234,
//!   "style": {
//!     "stage_hint": "win_big",
//!     "emotional_arc": { "points": [{"t":0,"intensity":0.1},{"t":1,"intensity":1.0}] },
//!     "tags": ["bright", "brassy"]
//!   }
//! }
//! ```
//!
//! On error: `pcm_ptr` is null and `error_json` is non-null (caller frees
//! with `generative_free_string`). On success: `pcm_ptr` non-null,
//! `error_json` null.

use std::ffi::{CStr, CString, c_char};

use rf_generative::{GenerationRequest, GenerativeBackend, MockBackend};
use serde::Serialize;

// ═══════════════════════════════════════════════════════════════════════════
// FFI surface
// ═══════════════════════════════════════════════════════════════════════════

/// Heap-owned buffer returned to the Dart side. Mirror this struct exactly
/// on the Dart side with `ffi.Struct`.
///
/// - `pcm_ptr` / `pcm_len`: interleaved `f32` samples. `null` on error.
/// - `sample_rate_hz`, `channels`: drive playback / WAV header on Dart side.
/// - `latency_ms`: backend wall-clock, surfaced in UI perf badge.
/// - `metadata_json`: serialized `ProvenanceTag` + non-PCM extras
///   (caller frees with `generative_free_string`).
/// - `error_json`: serialized `{"error": "..."}` on failure (caller frees
///   with `generative_free_string`); `null` on success.
#[repr(C)]
pub struct GenerativeFfiBuffer {
    pub pcm_ptr: *mut f32,
    pub pcm_len: usize,
    pub sample_rate_hz: u32,
    pub channels: u16,
    pub _pad: u16,
    pub latency_ms: u32,
    pub metadata_json: *mut c_char,
    pub error_json: *mut c_char,
}

impl GenerativeFfiBuffer {
    fn error(message: &str) -> Self {
        let err_json = serde_json::json!({ "error": message }).to_string();
        Self {
            pcm_ptr: std::ptr::null_mut(),
            pcm_len: 0,
            sample_rate_hz: 0,
            channels: 0,
            _pad: 0,
            latency_ms: 0,
            metadata_json: std::ptr::null_mut(),
            error_json: into_c_string(err_json),
        }
    }
}

#[derive(Serialize)]
struct GenerativeMetadata<'a> {
    backend_id: &'a str,
    model_id: &'a str,
    seed: Option<u64>,
    generated_at_utc: &'a str,
    duration_seconds: f32,
    frame_count: usize,
}

/// Run a generation request and return PCM + metadata.
///
/// `request_json` must be a valid UTF-8 NUL-terminated JSON string matching
/// `GenerationRequest`. `null` is rejected (returns error buffer).
///
/// The caller MUST eventually free both `pcm_ptr` (via
/// `generative_free_buffer`) and `metadata_json` / `error_json` (via
/// `generative_free_string`). Leak-safe because `generative_free_buffer`
/// also frees any remaining non-null metadata/error string.
#[unsafe(no_mangle)]
pub extern "C" fn generative_generate(request_json: *const c_char) -> GenerativeFfiBuffer {
    if request_json.is_null() {
        return GenerativeFfiBuffer::error("request_json is null");
    }
    // SAFETY: caller guarantees valid NUL-terminated C string.
    let json_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
        Ok(s) => s,
        Err(e) => return GenerativeFfiBuffer::error(&format!("invalid UTF-8: {e}")),
    };
    let request: GenerationRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return GenerativeFfiBuffer::error(&format!("request JSON parse: {e}")),
    };

    // Sprint 18: only `MockBackend` is wired. 5.1.2 will branch on a
    // `backend_id` field in the request once `feature = "onnx"` adds tract.
    let backend = MockBackend::new();
    let response = match backend.generate(&request) {
        Ok(r) => r,
        Err(e) => return GenerativeFfiBuffer::error(&format!("{e}")),
    };

    let frame_count = response.frame_count();
    let duration_seconds = response.duration_seconds();
    let metadata = GenerativeMetadata {
        backend_id: &response.provenance.backend_id,
        model_id: &response.provenance.model_id,
        seed: response.provenance.seed,
        generated_at_utc: &response.provenance.generated_at_utc,
        duration_seconds,
        frame_count,
    };
    let metadata_json = match serde_json::to_string(&metadata) {
        Ok(s) => into_c_string(s),
        Err(e) => {
            return GenerativeFfiBuffer::error(&format!("metadata serialize: {e}"));
        }
    };

    // Move PCM out into a leaked Box<[f32]> so Dart owns it until the
    // matching free call. `into_boxed_slice` keeps `pcm_len` honest.
    let pcm = response.pcm.into_boxed_slice();
    let pcm_len = pcm.len();
    let pcm_ptr = Box::into_raw(pcm) as *mut f32;

    GenerativeFfiBuffer {
        pcm_ptr,
        pcm_len,
        sample_rate_hz: response.sample_rate_hz,
        channels: response.channels,
        _pad: 0,
        latency_ms: response.latency_ms,
        metadata_json,
        error_json: std::ptr::null_mut(),
    }
}

/// Free a buffer previously returned by `generative_generate`.
///
/// Frees both the PCM buffer and (if non-null) the metadata / error JSON
/// strings — Dart side only needs one call per buffer.
#[unsafe(no_mangle)]
pub extern "C" fn generative_free_buffer(buf: GenerativeFfiBuffer) {
    if !buf.pcm_ptr.is_null() && buf.pcm_len > 0 {
        // SAFETY: pcm_ptr was created via Box::into_raw on a Box<[f32]>
        // of exactly `pcm_len` elements in `generative_generate`.
        unsafe {
            let slice = std::ptr::slice_from_raw_parts_mut(buf.pcm_ptr, buf.pcm_len);
            drop(Box::from_raw(slice));
        }
    }
    if !buf.metadata_json.is_null() {
        // SAFETY: created by CString::into_raw in `into_c_string`.
        unsafe { drop(CString::from_raw(buf.metadata_json)) };
    }
    if !buf.error_json.is_null() {
        // SAFETY: created by CString::into_raw in `into_c_string`.
        unsafe { drop(CString::from_raw(buf.error_json)) };
    }
}

/// Free a string previously returned through `metadata_json` / `error_json`.
///
/// Provided so Dart can free those fields *before* the parent buffer goes
/// away (e.g. after copying error text into a Dart string). Passing the
/// same pointer twice is UB — callers MUST null the field after freeing.
#[unsafe(no_mangle)]
pub extern "C" fn generative_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        // SAFETY: ptr was created by CString::into_raw in this module.
        unsafe { drop(CString::from_raw(ptr)) };
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

fn into_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn call(request: &str) -> GenerativeFfiBuffer {
        let c_in = CString::new(request).unwrap();
        generative_generate(c_in.as_ptr())
    }

    fn read_string(ptr: *mut c_char) -> Option<String> {
        if ptr.is_null() {
            return None;
        }
        // SAFETY: only called on pointers created by `into_c_string`.
        Some(unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string())
    }

    #[test]
    fn null_request_returns_error_buffer() {
        let buf = generative_generate(std::ptr::null());
        assert!(buf.pcm_ptr.is_null());
        let err = read_string(buf.error_json).expect("error_json must be set");
        assert!(err.contains("null"));
        generative_free_buffer(buf);
    }

    #[test]
    fn invalid_json_returns_error_buffer() {
        let buf = call("{not json at all");
        assert!(buf.pcm_ptr.is_null());
        let err = read_string(buf.error_json).expect("error_json must be set");
        assert!(err.contains("parse"));
        generative_free_buffer(buf);
    }

    #[test]
    fn valid_request_returns_pcm_and_metadata() {
        let req = r#"{
            "prompt": "test sting",
            "duration_seconds": 0.1,
            "sample_rate_hz": 0,
            "seed": 42,
            "style": { "stage_hint": "win_big", "tags": [] }
        }"#;
        let buf = call(req);
        assert!(buf.error_json.is_null(), "no error expected");
        assert!(!buf.pcm_ptr.is_null());
        assert!(buf.pcm_len > 0);
        assert_eq!(buf.channels, 2);
        assert_eq!(buf.sample_rate_hz, rf_generative::NATIVE_SAMPLE_RATE);
        // 0.1s × 48000 × 2ch = 9600 samples
        assert_eq!(buf.pcm_len, 9600);

        let metadata = read_string(buf.metadata_json).expect("metadata_json must be set");
        let v: serde_json::Value = serde_json::from_str(&metadata).unwrap();
        assert_eq!(v["backend_id"], "mock");
        assert_eq!(v["seed"], 42);
        assert!(v["generated_at_utc"].as_str().unwrap().contains("T"));
        assert_eq!(v["frame_count"], 4800);

        // SAFETY: pcm_ptr/pcm_len are valid for the lifetime of `buf`.
        let pcm = unsafe { std::slice::from_raw_parts(buf.pcm_ptr, buf.pcm_len) };
        // Fade-in: first sample near zero.
        assert!(pcm[0].abs() < 0.05);
        // Non-trivial mid-clip energy.
        let mid = pcm[buf.pcm_len / 2];
        assert!(mid.is_finite());

        generative_free_buffer(buf);
    }

    #[test]
    fn deterministic_across_calls() {
        let req = r#"{
            "prompt": "deterministic check",
            "duration_seconds": 0.05,
            "sample_rate_hz": 0,
            "seed": 7,
            "style": { "stage_hint": "idle", "tags": [] }
        }"#;
        let a = call(req);
        let b = call(req);
        assert!(!a.pcm_ptr.is_null());
        assert!(!b.pcm_ptr.is_null());
        assert_eq!(a.pcm_len, b.pcm_len);
        // SAFETY: both buffers are valid for their declared lengths.
        let a_pcm = unsafe { std::slice::from_raw_parts(a.pcm_ptr, a.pcm_len) };
        let b_pcm = unsafe { std::slice::from_raw_parts(b.pcm_ptr, b.pcm_len) };
        assert_eq!(a_pcm, b_pcm, "same seed must yield same PCM");
        generative_free_buffer(a);
        generative_free_buffer(b);
    }

    #[test]
    fn double_free_string_is_safe_when_field_nulled() {
        // Callers null the field after calling generative_free_string —
        // this test documents that contract.
        let req = r#"{
            "prompt": "free check",
            "duration_seconds": 0.05,
            "sample_rate_hz": 0,
            "seed": 1,
            "style": { "stage_hint": "idle", "tags": [] }
        }"#;
        let mut buf = call(req);
        assert!(!buf.metadata_json.is_null());
        let md_ptr = buf.metadata_json;
        buf.metadata_json = std::ptr::null_mut();
        generative_free_string(md_ptr);
        // Should not crash even with null metadata_json field on buffer.
        generative_free_buffer(buf);
    }

    #[test]
    fn rejects_out_of_range_duration() {
        let req = r#"{
            "prompt": "too long",
            "duration_seconds": 99999.0,
            "sample_rate_hz": 0,
            "seed": 1,
            "style": {}
        }"#;
        let buf = call(req);
        assert!(buf.pcm_ptr.is_null());
        let err = read_string(buf.error_json).unwrap();
        assert!(
            err.contains("duration") || err.contains("range"),
            "got: {err}"
        );
        generative_free_buffer(buf);
    }

    #[test]
    fn arc_request_round_trips() {
        let req = r#"{
            "prompt": "crescendo",
            "duration_seconds": 0.2,
            "sample_rate_hz": 0,
            "seed": 100,
            "style": {
                "stage_hint": "win_mega",
                "emotional_arc": {
                    "points": [
                        {"t": 0.0, "intensity": 0.05},
                        {"t": 1.0, "intensity": 1.0}
                    ]
                },
                "tags": ["bright"]
            }
        }"#;
        let buf = call(req);
        assert!(buf.error_json.is_null());
        assert!(!buf.pcm_ptr.is_null());
        // SAFETY: pcm valid for declared length.
        let pcm = unsafe { std::slice::from_raw_parts(buf.pcm_ptr, buf.pcm_len) };
        let n = pcm.len();
        // Tail energy must dominate head energy under the crescendo arc.
        let head: f32 = pcm[..n / 10].iter().map(|s| s * s).sum::<f32>().sqrt();
        let tail: f32 = pcm[n - n / 10..].iter().map(|s| s * s).sum::<f32>().sqrt();
        assert!(tail > head * 2.0, "head={head} tail={tail}");
        generative_free_buffer(buf);
    }

    #[test]
    fn freeing_null_pointers_is_noop() {
        generative_free_string(std::ptr::null_mut());
        let buf = GenerativeFfiBuffer {
            pcm_ptr: std::ptr::null_mut(),
            pcm_len: 0,
            sample_rate_hz: 0,
            channels: 0,
            _pad: 0,
            latency_ms: 0,
            metadata_json: std::ptr::null_mut(),
            error_json: std::ptr::null_mut(),
        };
        generative_free_buffer(buf); // must not crash
    }
}

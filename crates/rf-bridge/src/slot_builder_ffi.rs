//! FFI exports for 3.7.K — RTP Solver.
//!
//! Exposes `rf_slot_builder::solve_paytable` + `solution_to_math_config`
//! to Flutter via a JSON-in / JSON-out C ABI.
//!
//! # Protocol
//! ```text
//! slot_builder_solve_paytable(config_json) → result_json | null
//! slot_builder_free_string(ptr)            → void
//! ```
//!
//! ## config_json schema (RtpSolverConfig)
//! ```json
//! {
//!   "target_rtp":         0.965,
//!   "volatility_index":   5,
//!   "paying_symbol_count": 6,
//!   "reel_count":         5,
//!   "row_count":          3,
//!   "payline_count":      20,
//!   "include_wild":       true,
//!   "include_scatter":    true
//! }
//! ```
//!
//! ## result_json schema
//! ```json
//! {
//!   "ok": true,
//!   "solution": { <RtpSolution fields> },
//!   "math_config": { <MathConfig fields> }
//! }
//! ```
//! On error: `{"ok": false, "error": "reason string"}`

use std::ffi::{CStr, CString, c_char};

use rf_slot_builder::{
    RtpSolverConfig,
    solve_paytable,
    solution_to_math_config,
};

// ═══════════════════════════════════════════════════════════════════════════
// FFI FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Solve a paytable distribution for the given JSON config.
///
/// `config_json` must be a valid UTF-8 NUL-terminated JSON string matching
/// `RtpSolverConfig`.  Pass `null` to use the default config.
///
/// Returns a heap-allocated NUL-terminated JSON string that the caller
/// **must** free with [`slot_builder_free_string`].  Returns `null` only on
/// catastrophic internal error (OOM, etc.).
#[unsafe(no_mangle)]
pub extern "C" fn slot_builder_solve_paytable(
    config_json: *const c_char,
) -> *mut c_char {
    // Parse config — fall back to Default if null or invalid JSON.
    let config: RtpSolverConfig = if config_json.is_null() {
        RtpSolverConfig::default()
    } else {
        // SAFETY: caller guarantees valid NUL-terminated C string.
        let json_str = match unsafe { CStr::from_ptr(config_json) }.to_str() {
            Ok(s) => s,
            Err(e) => {
                return error_json(&format!("invalid UTF-8 in config: {e}"));
            }
        };
        match serde_json::from_str(json_str) {
            Ok(c) => c,
            Err(e) => {
                return error_json(&format!("config JSON parse error: {e}"));
            }
        }
    };

    // Run solver.
    let solution = match solve_paytable(&config) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };

    // Build MathConfig from solution.
    let math_config = solution_to_math_config(&solution, &config);

    // Serialise result.
    let result = serde_json::json!({
        "ok": true,
        "solution": solution,
        "math_config": math_config,
    });

    match serde_json::to_string(&result) {
        Ok(s) => match CString::new(s) {
            Ok(cs) => cs.into_raw(),
            Err(_) => null_ptr(),
        },
        Err(e) => error_json(&format!("result serialization error: {e}")),
    }
}

/// Free a string returned by [`slot_builder_solve_paytable`].
///
/// Passing `null` is a no-op.
#[unsafe(no_mangle)]
pub extern "C" fn slot_builder_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        // SAFETY: ptr was created by CString::into_raw() in this module.
        unsafe { drop(CString::from_raw(ptr)) };
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

fn error_json(msg: &str) -> *mut c_char {
    let json = format!("{{\"ok\":false,\"error\":{}}}", serde_json::json!(msg));
    match CString::new(json) {
        Ok(cs) => cs.into_raw(),
        Err(_) => null_ptr(),
    }
}

#[inline]
fn null_ptr() -> *mut c_char {
    std::ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn call_solver(json: &str) -> String {
        let c_in = CString::new(json).unwrap();
        let ptr = slot_builder_solve_paytable(c_in.as_ptr());
        assert!(!ptr.is_null(), "FFI returned null");
        let out = unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .unwrap()
            .to_owned();
        slot_builder_free_string(ptr);
        out
    }

    #[test]
    fn ffi_default_config_null_ptr() {
        let ptr = slot_builder_solve_paytable(std::ptr::null());
        assert!(!ptr.is_null());
        let json_str = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_owned();
        slot_builder_free_string(ptr);
        let v: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        assert_eq!(v["ok"], true);
        assert!(v["solution"]["achieved_rtp"].as_f64().unwrap() > 0.8);
    }

    #[test]
    fn ffi_default_config_json() {
        let json_str = call_solver(r#"{
            "target_rtp": 0.965,
            "volatility_index": 5,
            "paying_symbol_count": 6,
            "reel_count": 5,
            "row_count": 3,
            "payline_count": 20,
            "include_wild": true,
            "include_scatter": true
        }"#);
        let v: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        assert_eq!(v["ok"], true);
        let achieved = v["solution"]["achieved_rtp"].as_f64().unwrap();
        assert!((achieved - 0.965).abs() < 0.02, "RTP {achieved} not close to 0.965");
        assert!(v["math_config"]["symbols"].as_array().unwrap().len() >= 6);
    }

    #[test]
    fn ffi_invalid_json_returns_error() {
        let json_str = call_solver("NOT VALID JSON {{}}");
        let v: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        assert_eq!(v["ok"], false);
        assert!(v["error"].as_str().unwrap().contains("JSON"));
    }

    #[test]
    fn ffi_high_volatility() {
        let json_str = call_solver(r#"{
            "target_rtp": 0.960,
            "volatility_index": 9,
            "paying_symbol_count": 8,
            "reel_count": 5,
            "row_count": 3,
            "payline_count": 20,
            "include_wild": true,
            "include_scatter": true
        }"#);
        let v: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        assert_eq!(v["ok"], true);
        let achieved = v["solution"]["achieved_rtp"].as_f64().unwrap();
        assert!((achieved - 0.960).abs() < 0.02, "RTP {achieved}");
    }

    #[test]
    fn ffi_free_null_is_safe() {
        // Must not crash.
        slot_builder_free_string(std::ptr::null_mut());
    }

    #[test]
    fn ffi_math_config_reel_strips_present() {
        let json_str = call_solver(r#"{
            "target_rtp": 0.965,
            "volatility_index": 5,
            "paying_symbol_count": 6,
            "reel_count": 5,
            "row_count": 3,
            "payline_count": 20,
            "include_wild": true,
            "include_scatter": true
        }"#);
        let v: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        let strips = &v["math_config"]["reel_strips"]["base"];
        assert_eq!(strips.as_array().unwrap().len(), 5); // 5 reels
        assert_eq!(strips[0]["symbols"].as_array().unwrap().len(), 50); // 50 stops each
    }
}

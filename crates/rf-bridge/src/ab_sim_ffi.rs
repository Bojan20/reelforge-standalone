//! A/B Testing Analytics™ FFI — Bridges rf-ab-sim to Flutter.
//! Uses rf-ab-sim's built-in FFI helpers.

use std::ffi::{c_char, CStr, CString};

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Start a batch simulation in background. Input: BatchSimConfig JSON. Returns task ID.
#[unsafe(no_mangle)]
pub extern "C" fn ab_sim_start(config_json: *const c_char) -> u64 {
    if config_json.is_null() { return 0; }
    let s = match unsafe { CStr::from_ptr(config_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };
    rf_ab_sim::ffi::batch_sim_start_impl(s)
}

/// Get simulation progress (0.0 - 1.0).
#[unsafe(no_mangle)]
pub extern "C" fn ab_sim_progress(task_id: u64) -> f64 {
    rf_ab_sim::ffi::batch_sim_progress_impl(task_id)
}

/// Get simulation result as JSON (None if still running).
#[unsafe(no_mangle)]
pub extern "C" fn ab_sim_result_json(task_id: u64) -> *mut c_char {
    match rf_ab_sim::ffi::batch_sim_result_impl(task_id) {
        Some(json) => json_to_c(json),
        None => json_to_c(r#"{"status":"running"}"#.to_string()),
    }
}

/// Cancel a running simulation.
#[unsafe(no_mangle)]
pub extern "C" fn ab_sim_cancel(task_id: u64) {
    rf_ab_sim::ffi::batch_sim_cancel_impl(task_id);
}

#[unsafe(no_mangle)]
pub extern "C" fn ab_sim_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}

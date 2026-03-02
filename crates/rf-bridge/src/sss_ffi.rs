//! SSS: Scale & Stability Suite FFI Bridge
//!
//! Exposes multi-project isolation, config diff, auto regression,
//! and burn test via C FFI.

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};
use std::ptr;

use rf_aurexis::core::config::AurexisConfig;
use rf_aurexis::sss::{
    AutoRegression, BurnTest, BurnTestConfig, ConfigDiffEngine, ProjectConfig, ProjectIsolation,
    RegressionConfig, StressScenario,
};

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

static PROJECT_ISOLATION: Lazy<RwLock<ProjectIsolation>> =
    Lazy::new(|| RwLock::new(ProjectIsolation::new("/tmp/fluxforge_sss")));
static REGRESSION: Lazy<RwLock<Option<AutoRegression>>> = Lazy::new(|| RwLock::new(None));
static BURN_TEST: Lazy<RwLock<Option<BurnTest>>> = Lazy::new(|| RwLock::new(None));

// ═══════════════════════════════════════════════════════════════════════════════
// PROJECT ISOLATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a new isolated project. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn sss_create_project(name: *const c_char) -> i32 {
    let name_str = match unsafe { c_str_to_string(name) } {
        Some(s) => s,
        None => return 0,
    };
    let mut guard = PROJECT_ISOLATION.write();
    guard.create_project(name_str, ProjectConfig::default());
    1
}

/// Get project count.
#[unsafe(no_mangle)]
pub extern "C" fn sss_project_count() -> i32 {
    PROJECT_ISOLATION.read().project_count() as i32
}

/// Switch active project by ID. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn sss_switch_project(id: *const c_char) -> i32 {
    let id_str = match unsafe { c_str_to_string(id) } {
        Some(s) => s,
        None => return 0,
    };
    if PROJECT_ISOLATION.write().switch_project(&id_str) {
        1
    } else {
        0
    }
}

/// Remove a project. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn sss_remove_project(id: *const c_char) -> i32 {
    let id_str = match unsafe { c_str_to_string(id) } {
        Some(s) => s,
        None => return 0,
    };
    if PROJECT_ISOLATION.write().remove_project(&id_str) {
        1
    } else {
        0
    }
}

/// Get active project manifest JSON. Caller must free with sss_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sss_active_project_json() -> *mut c_char {
    let guard = PROJECT_ISOLATION.read();
    match guard.active_project() {
        Some(p) => match p.manifest.to_json() {
            Ok(json) => string_to_c(&json),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

/// List all projects as JSON array. Caller must free with sss_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sss_list_projects_json() -> *mut c_char {
    let guard = PROJECT_ISOLATION.read();
    let projects: Vec<_> = guard
        .list_projects()
        .iter()
        .map(|p| {
            serde_json::json!({
                "id": p.manifest.project_id,
                "name": p.manifest.project_name,
                "certified": p.manifest.is_certified(),
                "config_hash": p.manifest.config_hash,
            })
        })
        .collect();
    match serde_json::to_string(&projects) {
        Ok(json) => string_to_c(&json),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG DIFF
// ═══════════════════════════════════════════════════════════════════════════════

/// Compute diff between two config JSON objects. Returns diff JSON.
/// Both old_json and new_json should be flat {"key":"value"} objects.
/// Caller must free result with sss_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sss_config_diff(old_json: *const c_char, new_json: *const c_char) -> *mut c_char {
    let old_str = match unsafe { c_str_to_string(old_json) } {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let new_str = match unsafe { c_str_to_string(new_json) } {
        Some(s) => s,
        None => return ptr::null_mut(),
    };

    let old: HashMap<String, String> = match serde_json::from_str(&old_str) {
        Ok(m) => m,
        Err(_) => return ptr::null_mut(),
    };
    let new: HashMap<String, String> = match serde_json::from_str(&new_str) {
        Ok(m) => m,
        Err(_) => return ptr::null_mut(),
    };

    let diff = ConfigDiffEngine::diff(&old, &new);
    match diff.to_json() {
        Ok(json) => string_to_c(&json),
        Err(_) => ptr::null_mut(),
    }
}

/// Quick check: does a config change require regression? Returns 1 if yes.
#[unsafe(no_mangle)]
pub extern "C" fn sss_requires_regression(old_json: *const c_char, new_json: *const c_char) -> i32 {
    let old_str = match unsafe { c_str_to_string(old_json) } {
        Some(s) => s,
        None => return -1,
    };
    let new_str = match unsafe { c_str_to_string(new_json) } {
        Some(s) => s,
        None => return -1,
    };

    let old: HashMap<String, String> = match serde_json::from_str(&old_str) {
        Ok(m) => m,
        Err(_) => return -1,
    };
    let new: HashMap<String, String> = match serde_json::from_str(&new_str) {
        Ok(m) => m,
        Err(_) => return -1,
    };

    if ConfigDiffEngine::requires_regression(&old, &new) {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTO REGRESSION
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize regression engine with default config. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn sss_regression_init() -> i32 {
    *REGRESSION.write() = Some(AutoRegression::new(RegressionConfig::default()));
    1
}

/// Initialize regression with custom config. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn sss_regression_init_custom(session_count: u32, spins_per_session: u32) -> i32 {
    let config = RegressionConfig {
        session_count: session_count as usize,
        spins_per_session,
        ..Default::default()
    };
    *REGRESSION.write() = Some(AutoRegression::new(config));
    1
}

/// Run regression suite. Returns 1 if all pass, 0 if failures, -1 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn sss_regression_run() -> i32 {
    let aurexis_config = AurexisConfig::default();
    let mut guard = REGRESSION.write();
    match &mut *guard {
        Some(reg) => {
            let result = reg.run(&aurexis_config);
            if result.all_passed { 1 } else { 0 }
        }
        None => -1,
    }
}

/// Get regression result JSON. Caller must free with sss_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sss_regression_result_json() -> *mut c_char {
    let guard = REGRESSION.read();
    match &*guard {
        Some(reg) => match reg.last_result() {
            Some(r) => match r.to_json() {
                Ok(json) => string_to_c(&json),
                Err(_) => ptr::null_mut(),
            },
            None => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

/// Get regression pass rate (0.0–1.0).
#[unsafe(no_mangle)]
pub extern "C" fn sss_regression_pass_rate() -> f64 {
    let guard = REGRESSION.read();
    match &*guard {
        Some(reg) => reg.last_result().map(|r| r.pass_rate()).unwrap_or(0.0),
        None => 0.0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BURN TEST
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize burn test with default config (10,000 spins). Returns 1.
#[unsafe(no_mangle)]
pub extern "C" fn sss_burn_test_init() -> i32 {
    *BURN_TEST.write() = Some(BurnTest::new(BurnTestConfig::default()));
    1
}

/// Initialize burn test with custom spin count. Returns 1.
#[unsafe(no_mangle)]
pub extern "C" fn sss_burn_test_init_custom(total_spins: u32, sample_interval: u32) -> i32 {
    let config = BurnTestConfig {
        total_spins,
        sample_interval,
        ..Default::default()
    };
    *BURN_TEST.write() = Some(BurnTest::new(config));
    1
}

/// Run burn test. Returns 1 if passed, 0 if failures, -1 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn sss_burn_test_run() -> i32 {
    let aurexis_config = AurexisConfig::default();
    let mut guard = BURN_TEST.write();
    match &mut *guard {
        Some(bt) => {
            let result = bt.run(&aurexis_config);
            if result.passed { 1 } else { 0 }
        }
        None => -1,
    }
}

/// Get burn test result JSON. Caller must free with sss_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sss_burn_test_result_json() -> *mut c_char {
    let guard = BURN_TEST.read();
    match &*guard {
        Some(bt) => match bt.last_result() {
            Some(r) => match r.to_json() {
                Ok(json) => string_to_c(&json),
                Err(_) => ptr::null_mut(),
            },
            None => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

/// Check if burn test was deterministic. Returns 1 if yes, 0 if no, -1 if not run.
#[unsafe(no_mangle)]
pub extern "C" fn sss_burn_test_deterministic() -> i32 {
    let guard = BURN_TEST.read();
    match &*guard {
        Some(bt) => match bt.last_result() {
            Some(r) => {
                if r.deterministic {
                    1
                } else {
                    0
                }
            }
            None => -1,
        },
        None => -1,
    }
}

/// Free a string returned by sss_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn sss_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

fn string_to_c(s: &str) -> *mut c_char {
    CString::new(s)
        .map(|c| c.into_raw())
        .unwrap_or(ptr::null_mut())
}

unsafe fn c_str_to_string(s: *const c_char) -> Option<String> {
    if s.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(s) }.to_str().ok().map(String::from)
}

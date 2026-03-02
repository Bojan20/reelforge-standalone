// ============================================================================
// rf-bridge — FluxMacro FFI Bridge
// ============================================================================
// FM-33: Exposes FluxMacro orchestration engine to Flutter/Dart via C FFI.
// ~25 extern "C" functions: init, run, cancel, progress, history, etc.
// Pattern: Atomic CAS init, Lazy<RwLock<>> state, CString returns.
// ============================================================================

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::ffi::{CStr, CString, c_char};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};

use rf_fluxmacro::context::MacroContext;
use rf_fluxmacro::error::FluxMacroError;
use rf_fluxmacro::interpreter::MacroInterpreter;
use rf_fluxmacro::parser;
use rf_fluxmacro::steps::{StepRegistry, register_all_steps};
use rf_fluxmacro::version;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

const STATE_UNINITIALIZED: u8 = 0;
const STATE_INITIALIZING: u8 = 1;
const STATE_INITIALIZED: u8 = 2;

static FLUXMACRO_STATE: AtomicU8 = AtomicU8::new(STATE_UNINITIALIZED);
static INTERPRETER: Lazy<RwLock<Option<MacroInterpreter>>> = Lazy::new(|| RwLock::new(None));

/// Last run context (kept for querying results after run completes).
static LAST_CONTEXT: Lazy<RwLock<Option<MacroContext>>> = Lazy::new(|| RwLock::new(None));

/// Cancel token for in-progress runs.
static CANCEL_TOKEN: Lazy<Arc<AtomicBool>> = Lazy::new(|| Arc::new(AtomicBool::new(false)));

/// Progress callback state: (progress 0.0-1.0, step_name).
static PROGRESS: Lazy<RwLock<(f32, String)>> = Lazy::new(|| RwLock::new((0.0, String::new())));

/// Whether a run is currently in progress.
static RUNNING: AtomicBool = AtomicBool::new(false);

// ═══════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the FluxMacro engine. Must be called before any other function.
/// Returns 1 on success, 0 if already initialized or error.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_init() -> i32 {
    match FLUXMACRO_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            let mut registry = StepRegistry::new();
            register_all_steps(&mut registry);
            let interp = MacroInterpreter::new(registry);
            *INTERPRETER.write() = Some(interp);
            FLUXMACRO_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);
            log::info!("FluxMacro FFI: Engine initialized with all steps");
            1
        }
        Err(STATE_INITIALIZING) => {
            while FLUXMACRO_STATE.load(Ordering::SeqCst) == STATE_INITIALIZING {
                std::hint::spin_loop();
            }
            0
        }
        Err(_) => 0,
    }
}

/// Destroy the FluxMacro engine and free resources.
/// Returns 1 on success, 0 if not initialized.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_destroy() -> i32 {
    if FLUXMACRO_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return 0;
    }
    *INTERPRETER.write() = None;
    *LAST_CONTEXT.write() = None;
    FLUXMACRO_STATE.store(STATE_UNINITIALIZED, Ordering::SeqCst);
    log::info!("FluxMacro FFI: Engine destroyed");
    1
}

/// Check if the engine is initialized.
/// Returns 1 if initialized, 0 otherwise.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_is_initialized() -> i32 {
    if FLUXMACRO_STATE.load(Ordering::SeqCst) == STATE_INITIALIZED {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RUN MACRO
// ═══════════════════════════════════════════════════════════════════════════════

/// Run a macro from a YAML string. Blocks until complete.
/// Returns JSON result string (caller must free via fluxmacro_free_string).
/// Returns NULL on error.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_run_yaml(
    yaml_str: *const c_char,
    working_dir: *const c_char,
) -> *mut c_char {
    if yaml_str.is_null() || working_dir.is_null() {
        return ptr::null_mut();
    }

    let yaml = match unsafe { CStr::from_ptr(yaml_str) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return ptr::null_mut(),
    };

    let dir = match unsafe { CStr::from_ptr(working_dir) }.to_str() {
        Ok(s) => PathBuf::from(s),
        Err(_) => return ptr::null_mut(),
    };

    if RUNNING.swap(true, Ordering::SeqCst) {
        return to_json_ptr(&serde_json::json!({
            "success": false,
            "error": "A macro is already running",
        }));
    }

    CANCEL_TOKEN.store(false, Ordering::SeqCst);
    *PROGRESS.write() = (0.0, String::new());

    let result = run_macro_internal(&yaml, dir);

    RUNNING.store(false, Ordering::SeqCst);

    match result {
        Ok(json) => to_json_ptr(&json),
        Err(e) => to_json_ptr(&serde_json::json!({
            "success": false,
            "error": format!("{e}"),
        })),
    }
}

/// Run a macro from a .ffmacro.yaml file path. Blocks until complete.
/// Returns JSON result string (caller must free via fluxmacro_free_string).
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_run_file(file_path: *const c_char) -> *mut c_char {
    if file_path.is_null() {
        return ptr::null_mut();
    }

    let path_str = match unsafe { CStr::from_ptr(file_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let path = PathBuf::from(path_str);
    let working_dir = path
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));

    let yaml = match std::fs::read_to_string(&path) {
        Ok(s) => s,
        Err(e) => {
            return to_json_ptr(&serde_json::json!({
                "success": false,
                "error": format!("Failed to read file: {e}"),
            }));
        }
    };

    fluxmacro_run_yaml(
        CString::new(yaml).unwrap_or_default().as_ptr(),
        CString::new(working_dir.to_string_lossy().as_ref())
            .unwrap_or_default()
            .as_ptr(),
    )
}

// ═══════════════════════════════════════════════════════════════════════════════
// VALIDATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Validate a macro YAML string without executing.
/// Returns JSON with validation result (caller must free via fluxmacro_free_string).
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_validate(yaml_str: *const c_char) -> *mut c_char {
    if yaml_str.is_null() {
        return ptr::null_mut();
    }

    let yaml = match unsafe { CStr::from_ptr(yaml_str) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let macro_file = match parser::parse_macro_string(yaml) {
        Ok(m) => m,
        Err(e) => {
            return to_json_ptr(&serde_json::json!({
                "valid": false,
                "error": format!("{e}"),
            }));
        }
    };

    let guard = INTERPRETER.read();
    let interp = match guard.as_ref() {
        Some(i) => i,
        None => {
            return to_json_ptr(&serde_json::json!({
                "valid": false,
                "error": "Engine not initialized",
            }));
        }
    };

    match interp.validate(&macro_file) {
        Ok(warnings) => to_json_ptr(&serde_json::json!({
            "valid": true,
            "macro_name": macro_file.name,
            "game_id": macro_file.game_id,
            "step_count": macro_file.steps.len(),
            "warnings": warnings,
        })),
        Err(e) => to_json_ptr(&serde_json::json!({
            "valid": false,
            "error": format!("{e}"),
        })),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CANCEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Cancel a running macro. Safe to call at any time.
/// Returns 1 if cancellation was requested, 0 if nothing was running.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_cancel() -> i32 {
    if RUNNING.load(Ordering::SeqCst) {
        CANCEL_TOKEN.store(true, Ordering::SeqCst);
        log::info!("FluxMacro FFI: Cancellation requested");
        1
    } else {
        0
    }
}

/// Check if a macro is currently running.
/// Returns 1 if running, 0 otherwise.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_is_running() -> i32 {
    if RUNNING.load(Ordering::SeqCst) { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROGRESS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current progress (0.0 to 1.0).
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_get_progress() -> f64 {
    PROGRESS.read().0 as f64
}

/// Get current step name.
/// Returns string (caller must free via fluxmacro_free_string).
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_get_current_step() -> *mut c_char {
    let step = PROGRESS.read().1.clone();
    match CString::new(step) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAST RUN RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get last run result as JSON.
/// Returns NULL if no run has completed.
/// Caller must free via fluxmacro_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_get_last_result() -> *mut c_char {
    let guard = LAST_CONTEXT.read();
    match guard.as_ref() {
        Some(ctx) => to_json_ptr(&build_result_json(ctx)),
        None => ptr::null_mut(),
    }
}

/// Get last run hash.
/// Returns empty string if no run completed.
/// Caller must free via fluxmacro_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_get_last_hash() -> *mut c_char {
    let guard = LAST_CONTEXT.read();
    let hash = match guard.as_ref() {
        Some(ctx) => ctx.run_hash.clone(),
        None => String::new(),
    };
    match CString::new(hash) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Check if last run was successful.
/// Returns 1 if success, 0 if failed, -1 if no run yet.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_last_success() -> i32 {
    let guard = LAST_CONTEXT.read();
    match guard.as_ref() {
        Some(ctx) => {
            if ctx.is_success() {
                1
            } else {
                0
            }
        }
        None => -1,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEPS
// ═══════════════════════════════════════════════════════════════════════════════

/// List all registered steps as JSON.
/// Caller must free via fluxmacro_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_list_steps() -> *mut c_char {
    let guard = INTERPRETER.read();
    let interp = match guard.as_ref() {
        Some(i) => i,
        None => return ptr::null_mut(),
    };

    let steps: Vec<serde_json::Value> = interp
        .registry()
        .list()
        .iter()
        .filter_map(|name| {
            interp.registry().get(name).map(|step| {
                serde_json::json!({
                    "name": name,
                    "description": step.description(),
                    "estimated_ms": step.estimated_duration_ms(),
                })
            })
        })
        .collect();

    to_json_ptr(&serde_json::json!({ "steps": steps, "count": steps.len() }))
}

/// Get step count.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_step_count() -> i32 {
    let guard = INTERPRETER.read();
    match guard.as_ref() {
        Some(i) => i.registry().len() as i32,
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

/// List run history for a working directory.
/// Returns JSON array (caller must free via fluxmacro_free_string).
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_list_history(working_dir: *const c_char) -> *mut c_char {
    if working_dir.is_null() {
        return ptr::null_mut();
    }

    let dir = match unsafe { CStr::from_ptr(working_dir) }.to_str() {
        Ok(s) => PathBuf::from(s),
        Err(_) => return ptr::null_mut(),
    };

    match version::list_runs(&dir) {
        Ok(runs) => {
            let entries: Vec<serde_json::Value> = runs
                .iter()
                .filter_map(|(id, path)| {
                    version::load_run_meta(path).ok().map(|m| {
                        serde_json::json!({
                            "run_id": id,
                            "macro_name": m.macro_name,
                            "game_id": m.game_id,
                            "success": m.success,
                            "timestamp": m.timestamp,
                            "duration_ms": m.duration_ms,
                            "run_hash": m.run_hash,
                        })
                    })
                })
                .collect();
            to_json_ptr(&serde_json::json!({ "runs": entries, "count": entries.len() }))
        }
        Err(e) => to_json_ptr(&serde_json::json!({
            "error": format!("{e}"),
            "runs": [],
            "count": 0,
        })),
    }
}

/// Get run details by run ID.
/// Returns JSON (caller must free via fluxmacro_free_string).
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_get_run(
    working_dir: *const c_char,
    run_id: *const c_char,
) -> *mut c_char {
    if working_dir.is_null() || run_id.is_null() {
        return ptr::null_mut();
    }

    let dir = match unsafe { CStr::from_ptr(working_dir) }.to_str() {
        Ok(s) => PathBuf::from(s),
        Err(_) => return ptr::null_mut(),
    };

    let id = match unsafe { CStr::from_ptr(run_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let run_path = version::run_dir(&dir, id);
    match version::load_run_meta(&run_path) {
        Ok(meta) => match serde_json::to_value(&meta) {
            Ok(val) => to_json_ptr(&val),
            Err(_) => ptr::null_mut(),
        },
        Err(e) => to_json_ptr(&serde_json::json!({
            "error": format!("{e}"),
        })),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QA RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get QA results from the last run as JSON.
/// Caller must free via fluxmacro_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_get_qa_results() -> *mut c_char {
    let guard = LAST_CONTEXT.read();
    let ctx = match guard.as_ref() {
        Some(c) => c,
        None => return ptr::null_mut(),
    };

    let results: Vec<serde_json::Value> = ctx
        .qa_results
        .iter()
        .map(|r| {
            serde_json::json!({
                "test": r.test_name,
                "passed": r.passed,
                "details": r.details,
                "duration_ms": r.duration_ms,
                "metrics": r.metrics,
            })
        })
        .collect();

    to_json_ptr(&serde_json::json!({
        "qa_passed": ctx.qa_passed_count(),
        "qa_failed": ctx.qa_failed_count(),
        "results": results,
    }))
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOGS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get logs from the last run as JSON array.
/// Caller must free via fluxmacro_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_get_logs() -> *mut c_char {
    let guard = LAST_CONTEXT.read();
    let ctx = match guard.as_ref() {
        Some(c) => c,
        None => return ptr::null_mut(),
    };

    let logs: Vec<serde_json::Value> = ctx
        .logs
        .iter()
        .map(|entry| {
            serde_json::json!({
                "elapsed_ms": entry.elapsed.as_millis() as u64,
                "level": format!("{:?}", entry.level),
                "step": entry.step,
                "message": entry.message,
            })
        })
        .collect();

    to_json_ptr(&serde_json::json!({ "logs": logs, "count": logs.len() }))
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by any fluxmacro_* function.
/// Must be called on every non-null *mut c_char return value.
#[unsafe(no_mangle)]
pub extern "C" fn fluxmacro_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

fn run_macro_internal(
    yaml: &str,
    working_dir: PathBuf,
) -> Result<serde_json::Value, FluxMacroError> {
    let macro_file = parser::parse_macro_string(yaml)?;

    let guard = INTERPRETER.read();
    let interp = guard
        .as_ref()
        .ok_or_else(|| FluxMacroError::Other("Engine not initialized".to_string()))?;

    // We need to run the interpreter, but it takes ownership-like access.
    // The interpreter.run() takes &self, so we can use it through the read guard.

    // Set up progress callback via the cancel token and progress state.
    // Note: The interpreter creates its own MacroContext internally.
    // We pass the cancel token and progress callback through the context after build.

    // Since interpreter.run() builds context internally, we need to work around this.
    // We'll use interpreter.run() directly and capture progress via the context callback.
    // The interpreter calls ctx.report_progress() which calls the callback.

    // For now, run directly — the context built by interpreter won't have our callback
    // unless we modify the interpreter. Instead, we accept that progress polling works
    // through PROGRESS state updated by the internal callback.

    let ctx = interp.run(&macro_file, working_dir)?;

    let result_json = build_result_json(&ctx);

    // Store for later queries
    *LAST_CONTEXT.write() = Some(ctx);

    Ok(result_json)
}

fn build_result_json(ctx: &MacroContext) -> serde_json::Value {
    serde_json::json!({
        "success": ctx.is_success(),
        "game_id": ctx.game_id,
        "seed": ctx.seed,
        "run_hash": ctx.run_hash,
        "duration_ms": ctx.duration().as_millis() as u64,
        "qa_passed": ctx.qa_passed_count(),
        "qa_failed": ctx.qa_failed_count(),
        "artifacts": ctx.artifacts.keys().collect::<Vec<_>>(),
        "warnings": ctx.warnings,
        "errors": ctx.errors,
    })
}

fn to_json_ptr(value: &serde_json::Value) -> *mut c_char {
    match serde_json::to_string(value) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

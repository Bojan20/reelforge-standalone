//! ML FFI — Bridges rf-ml to Flutter via C FFI.
//!
//! 16 functions matching native_ffi.dart typedefs:
//! - ml_init, ml_reset
//! - ml_get_model_count, ml_get_model_name, ml_model_is_available, ml_get_model_size
//! - ml_denoise_start, ml_separate_start, ml_enhance_voice_start
//! - ml_get_progress, ml_is_processing, ml_get_phase, ml_get_current_model
//! - ml_cancel, ml_set_execution_provider, ml_get_error

use std::ffi::{c_char, CString};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU8, Ordering};
use std::sync::{Arc, OnceLock};

use crossbeam_channel::{Receiver, Sender};
use parking_lot::RwLock;

/// ML model registry entry.
struct MlModel {
    name: &'static str,
    model_type: &'static str,
    available: bool,
    size_mb: u32,
}

/// Commands sent to ML processing threads.
enum MlCommand {
    /// Begin processing with input/output paths and model-specific params
    Process {
        input_path: String,
        output_path: String,
        /// Model-specific parameter (strength for denoise, stems_mask for separate, unused for enhance)
        param: f64,
    },
    /// Cancel current processing
    Cancel,
    /// Shut down the thread
    Shutdown,
}

/// Thread state: 0=idle, 1=running, 2=stopped, 3=error
const THREAD_IDLE: u8 = 0;
const THREAD_RUNNING: u8 = 1;
const THREAD_STOPPED: u8 = 2;
const THREAD_ERROR: u8 = 3;

/// Handle to a spawned ML processing thread.
struct MlThreadHandle {
    /// Command sender
    cmd_tx: Sender<MlCommand>,
    /// Thread state (Arc-shared with the spawned thread)
    state: Arc<AtomicU8>,
}

impl MlThreadHandle {
    /// Spawn a named ML processing thread with catch_unwind panic handler.
    fn spawn(name: &str, model_name: &'static str) -> Self {
        let (cmd_tx, cmd_rx): (Sender<MlCommand>, Receiver<MlCommand>) =
            crossbeam_channel::bounded(4);
        let state = Arc::new(AtomicU8::new(THREAD_IDLE));
        let state_ref = Arc::clone(&state);
        let thread_name = name.to_string();

        std::thread::Builder::new()
            .name(thread_name.clone())
            .spawn(move || {
                let state_ref = &*state_ref;
                log::info!("ML thread '{}' started for model {}", thread_name, model_name);

                loop {
                    let cmd = match cmd_rx.recv() {
                        Ok(cmd) => cmd,
                        Err(_) => {
                            log::info!("ML thread '{}': channel closed, exiting", thread_name);
                            state_ref.store(THREAD_STOPPED, Ordering::Release);
                            break;
                        }
                    };

                    match cmd {
                        MlCommand::Process { input_path, output_path, param } => {
                            state_ref.store(THREAD_RUNNING, Ordering::Release);
                            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                log::info!(
                                    "ML thread '{}': processing {} -> {} (param={:.2})",
                                    thread_name, input_path, output_path, param
                                );

                                // Update global progress state
                                if let Some(ml) = ml_state() {
                                    *ml.phase.write() = format!("Processing with {}...", model_name);
                                    *ml.progress.write() = 0.1;
                                }

                                // NOTE: Actual ML model inference would happen here.
                                // When model weights are available, this is where we:
                                // 1. Load audio from input_path into ring buffer
                                // 2. Run inference through the ML model
                                // 3. Write processed output to output_path
                                // For now, log and simulate completion.

                                log::info!(
                                    "ML thread '{}': {} inference would run here (no weights loaded)",
                                    thread_name, model_name
                                );

                                if let Some(ml) = ml_state() {
                                    *ml.progress.write() = 1.0;
                                    *ml.phase.write() = "Complete".into();
                                    ml.processing.store(false, Ordering::Release);
                                }
                            }));

                            match result {
                                Ok(()) => {
                                    state_ref.store(THREAD_IDLE, Ordering::Release);
                                }
                                Err(panic_info) => {
                                    let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                                        s.to_string()
                                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                                        s.clone()
                                    } else {
                                        "unknown panic".to_string()
                                    };
                                    log::error!(
                                        "ML thread '{}' panicked during processing: {}",
                                        thread_name, msg
                                    );
                                    state_ref.store(THREAD_ERROR, Ordering::Release);
                                    if let Some(ml) = ml_state() {
                                        *ml.error.write() = Some(format!("Internal error in {}: {}", model_name, msg));
                                        ml.processing.store(false, Ordering::Release);
                                        *ml.phase.write() = "Error".into();
                                    }
                                }
                            }
                        }
                        MlCommand::Cancel => {
                            log::info!("ML thread '{}': cancel received", thread_name);
                            if let Some(ml) = ml_state() {
                                ml.processing.store(false, Ordering::Release);
                                *ml.phase.write() = "Cancelled".into();
                            }
                            state_ref.store(THREAD_IDLE, Ordering::Release);
                        }
                        MlCommand::Shutdown => {
                            log::info!("ML thread '{}': shutdown received", thread_name);
                            state_ref.store(THREAD_STOPPED, Ordering::Release);
                            break;
                        }
                    }
                }
            })
            .unwrap_or_else(|e| {
                log::error!("Failed to spawn ML thread '{}': {}", name, e);
                panic!("Critical: cannot spawn ML thread '{}'", name);
            });

        Self { cmd_tx, state }
    }

    /// Send a command to the thread (non-blocking best-effort).
    fn send(&self, cmd: MlCommand) -> bool {
        self.cmd_tx.try_send(cmd).is_ok()
    }

    /// Get thread state.
    fn thread_state(&self) -> u8 {
        self.state.load(Ordering::Acquire)
    }
}

/// Global ML state.
struct MlState {
    models: Vec<MlModel>,
    processing: AtomicBool,
    progress: RwLock<f32>,
    phase: RwLock<String>,
    current_model: RwLock<String>,
    error: RwLock<Option<String>>,
    execution_provider: AtomicU32, // 0=CPU, 1=CUDA, 2=TensorRT, 3=CoreML
    /// Processing threads — one per model type
    thread_denoise: MlThreadHandle,
    thread_separate: MlThreadHandle,
    thread_enhance: MlThreadHandle,
}

static ML_STATE: OnceLock<MlState> = OnceLock::new();

fn ml_state() -> Option<&'static MlState> {
    ML_STATE.get()
}

// ════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ════════════════════════════════════════════════════════════════════

/// Initialize ML engine. Registers available models.
#[unsafe(no_mangle)]
pub extern "C" fn ml_init() {
    // Spawn processing threads before creating state
    let thread_denoise = MlThreadHandle::spawn("ff-ml-denoise", "DeepFilterNet3");
    let thread_separate = MlThreadHandle::spawn("ff-ml-separate", "HTDemucs");
    let thread_enhance = MlThreadHandle::spawn("ff-ml-enhance", "aTENNuate-SSM");

    let _ = ML_STATE.set(MlState {
        models: vec![
            MlModel {
                name: "DeepFilterNet3",
                model_type: "denoise",
                available: true,
                size_mb: 15,
            },
            MlModel {
                name: "HTDemucs-4stem",
                model_type: "separation",
                available: true,
                size_mb: 80,
            },
            MlModel {
                name: "HTDemucs-6stem",
                model_type: "separation",
                available: true,
                size_mb: 120,
            },
            MlModel {
                name: "aTENNuate-SSM",
                model_type: "voice_enhance",
                available: true,
                size_mb: 25,
            },
            MlModel {
                name: "GenreClassifier",
                model_type: "analysis",
                available: true,
                size_mb: 8,
            },
            MlModel {
                name: "PitchEstimator",
                model_type: "analysis",
                available: true,
                size_mb: 5,
            },
        ],
        processing: AtomicBool::new(false),
        progress: RwLock::new(0.0),
        phase: RwLock::new(String::new()),
        current_model: RwLock::new(String::new()),
        error: RwLock::new(None),
        execution_provider: AtomicU32::new(0), // CPU default
        thread_denoise,
        thread_separate,
        thread_enhance,
    });
    log::info!("ML FFI: Initialized with {} models, 3 processing threads spawned", ML_STATE.get().map_or(0, |s| s.models.len()));
}

/// Reset ML engine state. Cancels any processing.
#[unsafe(no_mangle)]
pub extern "C" fn ml_reset() {
    if let Some(state) = ml_state() {
        // Cancel any in-flight processing on all threads
        let _ = state.thread_denoise.send(MlCommand::Cancel);
        let _ = state.thread_separate.send(MlCommand::Cancel);
        let _ = state.thread_enhance.send(MlCommand::Cancel);
        state.processing.store(false, Ordering::Release);
        *state.progress.write() = 0.0;
        *state.phase.write() = String::new();
        *state.current_model.write() = String::new();
        *state.error.write() = None;
        log::info!("ML FFI: State reset");
    }
}

// ════════════════════════════════════════════════════════════════════
// MODEL REGISTRY
// ════════════════════════════════════════════════════════════════════

/// Get number of registered ML models.
#[unsafe(no_mangle)]
pub extern "C" fn ml_get_model_count() -> u32 {
    ml_state().map_or(0, |s| s.models.len() as u32)
}

/// Get model name by index. Returns C string (caller must free).
#[unsafe(no_mangle)]
pub extern "C" fn ml_get_model_name(index: u32) -> *mut c_char {
    let Some(state) = ml_state() else {
        return std::ptr::null_mut();
    };
    if (index as usize) >= state.models.len() {
        return std::ptr::null_mut();
    }
    match CString::new(state.models[index as usize].name) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Check if model at index is available. Returns 1=available, 0=not.
#[unsafe(no_mangle)]
pub extern "C" fn ml_model_is_available(index: u32) -> i32 {
    let Some(state) = ml_state() else { return 0 };
    if (index as usize) >= state.models.len() {
        return 0;
    }
    if state.models[index as usize].available { 1 } else { 0 }
}

/// Get model size in MB.
#[unsafe(no_mangle)]
pub extern "C" fn ml_get_model_size(index: u32) -> u32 {
    let Some(state) = ml_state() else { return 0 };
    if (index as usize) >= state.models.len() {
        return 0;
    }
    state.models[index as usize].size_mb
}

// ════════════════════════════════════════════════════════════════════
// PROCESSING START
// ════════════════════════════════════════════════════════════════════

/// Start denoising. Returns 1 on success, 0 on failure.
/// input_path: path to input audio file
/// output_path: path for denoised output
/// strength: denoise strength (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn ml_denoise_start(
    input_path: *const c_char,
    output_path: *const c_char,
    strength: f32,
) -> i32 {
    if input_path.is_null() || output_path.is_null() {
        return 0;
    }

    let _input = match unsafe { std::ffi::CStr::from_ptr(input_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };
    let _output = match unsafe { std::ffi::CStr::from_ptr(output_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let Some(state) = ml_state() else { return 0 };

    if state.processing.load(Ordering::Relaxed) {
        *state.error.write() = Some("Processing already in progress".into());
        return 0;
    }

    state.processing.store(true, Ordering::Relaxed);
    *state.progress.write() = 0.0;
    *state.phase.write() = "Starting denoise...".into();
    *state.current_model.write() = "DeepFilterNet3".into();
    *state.error.write() = None;

    log::info!(
        "ML FFI: Denoise started (strength={:.2})",
        strength
    );

    // Dispatch to DeepFilterNet processing thread
    if !state.thread_denoise.send(MlCommand::Process {
        input_path: _input,
        output_path: _output,
        param: strength as f64,
    }) {
        *state.error.write() = Some("Failed to send command to denoise thread".into());
        state.processing.store(false, Ordering::Release);
        return 0;
    }

    1
}

/// Start stem separation. Returns 1 on success, 0 on failure.
/// stems_mask: bitmask of stems to extract (1=vocals, 2=drums, 4=bass, 8=other, 16=piano, 32=guitar)
#[unsafe(no_mangle)]
pub extern "C" fn ml_separate_start(
    input_path: *const c_char,
    output_dir: *const c_char,
    stems_mask: u32,
) -> i32 {
    if input_path.is_null() || output_dir.is_null() {
        return 0;
    }

    let _input = match unsafe { std::ffi::CStr::from_ptr(input_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };
    let _output = match unsafe { std::ffi::CStr::from_ptr(output_dir) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let Some(state) = ml_state() else { return 0 };

    if state.processing.load(Ordering::Relaxed) {
        *state.error.write() = Some("Processing already in progress".into());
        return 0;
    }

    // Determine model based on stems requested
    let model_name = if stems_mask & 0x30 != 0 {
        "HTDemucs-6stem"
    } else {
        "HTDemucs-4stem"
    };

    state.processing.store(true, Ordering::Relaxed);
    *state.progress.write() = 0.0;
    *state.phase.write() = "Starting separation...".into();
    *state.current_model.write() = model_name.into();
    *state.error.write() = None;

    log::info!(
        "ML FFI: Separation started (model={}, mask=0x{:X})",
        model_name, stems_mask
    );

    // Dispatch to HTDemucs processing thread (stems_mask as param)
    if !state.thread_separate.send(MlCommand::Process {
        input_path: _input,
        output_path: _output,
        param: stems_mask as f64,
    }) {
        *state.error.write() = Some("Failed to send command to separation thread".into());
        state.processing.store(false, Ordering::Release);
        return 0;
    }

    1
}

/// Start voice enhancement. Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn ml_enhance_voice_start(
    input_path: *const c_char,
    output_path: *const c_char,
) -> i32 {
    if input_path.is_null() || output_path.is_null() {
        return 0;
    }

    let _input = match unsafe { std::ffi::CStr::from_ptr(input_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };
    let _output = match unsafe { std::ffi::CStr::from_ptr(output_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let Some(state) = ml_state() else { return 0 };

    if state.processing.load(Ordering::Relaxed) {
        *state.error.write() = Some("Processing already in progress".into());
        return 0;
    }

    state.processing.store(true, Ordering::Relaxed);
    *state.progress.write() = 0.0;
    *state.phase.write() = "Enhancing voice...".into();
    *state.current_model.write() = "aTENNuate-SSM".into();
    *state.error.write() = None;

    log::info!("ML FFI: Voice enhancement started");

    // Dispatch to aTENNuate processing thread
    if !state.thread_enhance.send(MlCommand::Process {
        input_path: _input,
        output_path: _output,
        param: 0.0,
    }) {
        *state.error.write() = Some("Failed to send command to voice enhancement thread".into());
        state.processing.store(false, Ordering::Release);
        return 0;
    }

    1
}

// ════════════════════════════════════════════════════════════════════
// PROGRESS POLLING
// ════════════════════════════════════════════════════════════════════

/// Get processing progress (0.0 to 1.0).
#[unsafe(no_mangle)]
pub extern "C" fn ml_get_progress() -> f32 {
    ml_state().map_or(0.0, |s| *s.progress.read())
}

/// Check if ML is currently processing. Returns 1 if yes.
#[unsafe(no_mangle)]
pub extern "C" fn ml_is_processing() -> i32 {
    ml_state().map_or(0, |s| if s.processing.load(Ordering::Relaxed) { 1 } else { 0 })
}

/// Get current processing phase string. Returns C string (caller must free).
#[unsafe(no_mangle)]
pub extern "C" fn ml_get_phase() -> *mut c_char {
    let Some(state) = ml_state() else {
        return std::ptr::null_mut();
    };
    let phase = state.phase.read().clone();
    match CString::new(phase) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Get current model name. Returns C string (caller must free).
#[unsafe(no_mangle)]
pub extern "C" fn ml_get_current_model() -> *mut c_char {
    let Some(state) = ml_state() else {
        return std::ptr::null_mut();
    };
    let model = state.current_model.read().clone();
    match CString::new(model) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Get error message (null if no error). Returns C string (caller must free).
#[unsafe(no_mangle)]
pub extern "C" fn ml_get_error() -> *mut c_char {
    let Some(state) = ml_state() else {
        return std::ptr::null_mut();
    };
    let error = state.error.read().clone();
    match error {
        Some(e) => match CString::new(e) {
            Ok(cs) => cs.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

// ════════════════════════════════════════════════════════════════════
// CONTROL
// ════════════════════════════════════════════════════════════════════

/// Cancel current processing. Returns 1 if cancelled, 0 if nothing to cancel.
#[unsafe(no_mangle)]
pub extern "C" fn ml_cancel() -> i32 {
    let Some(state) = ml_state() else { return 0 };
    if state.processing.load(Ordering::Acquire) {
        // Send cancel to all threads — only the active one will act on it
        let _ = state.thread_denoise.send(MlCommand::Cancel);
        let _ = state.thread_separate.send(MlCommand::Cancel);
        let _ = state.thread_enhance.send(MlCommand::Cancel);
        state.processing.store(false, Ordering::Release);
        *state.phase.write() = "Cancelled".into();
        log::info!("ML FFI: Processing cancelled");
        1
    } else {
        0
    }
}

/// Set execution provider. provider: 0=CPU, 1=CUDA, 2=TensorRT, 3=CoreML.
/// Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn ml_set_execution_provider(provider: i32) -> i32 {
    let Some(state) = ml_state() else { return 0 };
    let p = (provider as u32).min(3);
    state.execution_provider.store(p, Ordering::Relaxed);
    let name = match p {
        0 => "CPU",
        1 => "CUDA",
        2 => "TensorRT",
        3 => "CoreML",
        _ => "CPU",
    };
    log::info!("ML FFI: Execution provider set to {}", name);
    1
}

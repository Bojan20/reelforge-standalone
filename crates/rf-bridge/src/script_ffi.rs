//! Script FFI — Bridges rf-script (Lua ScriptEngine) to Flutter via C FFI.
//!
//! 22 functions matching native_ffi.dart typedefs:
//! - script_init, script_shutdown, script_is_initialized
//! - script_execute, script_execute_file, script_load_file, script_run
//! - script_get_output, script_get_error, script_get_duration
//! - script_poll_actions, script_get_next_action
//! - script_set_context, script_set_selected_tracks, script_set_selected_clips
//! - script_add_search_path, script_get_loaded_count, script_get_name, script_get_description

use std::ffi::{c_char, CStr, CString};
use std::sync::OnceLock;
use std::time::Instant;

use parking_lot::RwLock;
use rf_script::{ScriptContext, ScriptManager};

/// Global script manager singleton.
static SCRIPT_MANAGER: OnceLock<RwLock<ScriptManagerState>> = OnceLock::new();

struct ScriptManagerState {
    manager: ScriptManager,
    last_output: String,
    last_error: String,
    last_duration_ms: u32,
    /// Pending actions as JSON strings (drained by script_get_next_action)
    pending_actions: Vec<String>,
}

fn script_state() -> Option<&'static RwLock<ScriptManagerState>> {
    SCRIPT_MANAGER.get()
}

// ════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ════════════════════════════════════════════════════════════════════

/// Initialize the script engine. Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn script_init() -> i32 {
    if SCRIPT_MANAGER.get().is_some() {
        return 1; // Already initialized
    }

    match ScriptManager::new() {
        Ok(manager) => {
            let state = ScriptManagerState {
                manager,
                last_output: String::new(),
                last_error: String::new(),
                last_duration_ms: 0,
                pending_actions: Vec::new(),
            };
            let _ = SCRIPT_MANAGER.set(RwLock::new(state));
            log::info!("SCRIPT FFI: Engine initialized");
            1
        }
        Err(e) => {
            log::error!("SCRIPT FFI: Init failed — {}", e);
            0
        }
    }
}

/// Shutdown the script engine.
#[unsafe(no_mangle)]
pub extern "C" fn script_shutdown() {
    // OnceLock can't be cleared, but we can reset internal state
    if let Some(state) = script_state() {
        let mut s = state.write();
        s.last_output.clear();
        s.last_error.clear();
        s.pending_actions.clear();
        log::info!("SCRIPT FFI: Engine shutdown (state cleared)");
    }
}

/// Check if script engine is initialized. Returns 1 if yes, 0 if no.
#[unsafe(no_mangle)]
pub extern "C" fn script_is_initialized() -> i32 {
    if SCRIPT_MANAGER.get().is_some() { 1 } else { 0 }
}

// ════════════════════════════════════════════════════════════════════
// EXECUTION
// ════════════════════════════════════════════════════════════════════

/// Execute inline Lua code. Returns 1 on success, 0 on error.
#[unsafe(no_mangle)]
pub extern "C" fn script_execute(code: *const c_char) -> i32 {
    if code.is_null() {
        return 0;
    }
    let code_str = match unsafe { CStr::from_ptr(code) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let Some(state) = script_state() else { return 0 };
    let mut s = state.write();

    let start = Instant::now();
    match s.manager.execute_code(code_str) {
        Ok(()) => {
            s.last_duration_ms = start.elapsed().as_millis() as u32;
            s.last_error.clear();
            // Drain actions
            drain_actions(&mut s);
            1
        }
        Err(e) => {
            s.last_duration_ms = start.elapsed().as_millis() as u32;
            s.last_error = format!("{}", e);
            log::error!("SCRIPT FFI: execute failed — {}", e);
            0
        }
    }
}

/// Execute a script file by path. Returns 1 on success, 0 on error.
#[unsafe(no_mangle)]
pub extern "C" fn script_execute_file(path: *const c_char) -> i32 {
    if path.is_null() {
        return 0;
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let Some(state) = script_state() else { return 0 };
    let mut s = state.write();

    let start = Instant::now();
    // Load then execute
    match s.manager.engine_mut().load_script(path_str) {
        Ok(name) => {
            match s.manager.execute(&name) {
                Ok(()) => {
                    s.last_duration_ms = start.elapsed().as_millis() as u32;
                    s.last_error.clear();
                    drain_actions(&mut s);
                    1
                }
                Err(e) => {
                    s.last_duration_ms = start.elapsed().as_millis() as u32;
                    s.last_error = format!("{}", e);
                    0
                }
            }
        }
        Err(e) => {
            s.last_duration_ms = start.elapsed().as_millis() as u32;
            s.last_error = format!("{}", e);
            0
        }
    }
}

/// Load a script file (without executing). Returns script name as C string, or null.
#[unsafe(no_mangle)]
pub extern "C" fn script_load_file(path: *const c_char) -> *mut c_char {
    if path.is_null() {
        return std::ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let Some(state) = script_state() else {
        return std::ptr::null_mut();
    };
    let mut s = state.write();

    match s.manager.engine_mut().load_script(path_str) {
        Ok(name) => {
            log::info!("SCRIPT FFI: Loaded script '{}' from {}", name, path_str);
            match CString::new(name) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(e) => {
            s.last_error = format!("{}", e);
            std::ptr::null_mut()
        }
    }
}

/// Run a loaded script by name. Returns 1 on success, 0 on error.
#[unsafe(no_mangle)]
pub extern "C" fn script_run(name: *const c_char) -> i32 {
    if name.is_null() {
        return 0;
    }
    let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let Some(state) = script_state() else { return 0 };
    let mut s = state.write();

    let start = Instant::now();
    match s.manager.execute(name_str) {
        Ok(()) => {
            s.last_duration_ms = start.elapsed().as_millis() as u32;
            s.last_error.clear();
            drain_actions(&mut s);
            1
        }
        Err(e) => {
            s.last_duration_ms = start.elapsed().as_millis() as u32;
            s.last_error = format!("{}", e);
            0
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// OUTPUT
// ════════════════════════════════════════════════════════════════════

/// Get captured output from last execution. Returns C string (caller must free).
#[unsafe(no_mangle)]
pub extern "C" fn script_get_output() -> *mut c_char {
    let Some(state) = script_state() else {
        return std::ptr::null_mut();
    };
    let s = state.read();
    match CString::new(s.last_output.as_str()) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Get error message from last execution. Returns C string (caller must free).
#[unsafe(no_mangle)]
pub extern "C" fn script_get_error() -> *mut c_char {
    let Some(state) = script_state() else {
        return std::ptr::null_mut();
    };
    let s = state.read();
    match CString::new(s.last_error.as_str()) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Get execution duration of last script (milliseconds).
#[unsafe(no_mangle)]
pub extern "C" fn script_get_duration() -> u32 {
    let Some(state) = script_state() else { return 0 };
    state.read().last_duration_ms
}

// ════════════════════════════════════════════════════════════════════
// ACTION POLLING
// ════════════════════════════════════════════════════════════════════

/// Poll pending actions from the script engine. Returns count.
#[unsafe(no_mangle)]
pub extern "C" fn script_poll_actions() -> u32 {
    let Some(state) = script_state() else { return 0 };
    let s = state.read();
    s.pending_actions.len() as u32
}

/// Get the next pending action as JSON string. Returns null if none.
/// Caller must free the returned string.
#[unsafe(no_mangle)]
pub extern "C" fn script_get_next_action() -> *mut c_char {
    let Some(state) = script_state() else {
        return std::ptr::null_mut();
    };
    let mut s = state.write();

    if s.pending_actions.is_empty() {
        return std::ptr::null_mut();
    }

    let action_json = s.pending_actions.remove(0);
    match CString::new(action_json) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

// ════════════════════════════════════════════════════════════════════
// CONTEXT
// ════════════════════════════════════════════════════════════════════

/// Update script execution context.
#[unsafe(no_mangle)]
pub extern "C" fn script_set_context(
    playhead: u64,
    is_playing: i32,
    is_recording: i32,
    sample_rate: u32,
) {
    let Some(state) = script_state() else { return };
    let s = state.read();

    let ctx = ScriptContext {
        project_path: None,
        selected_tracks: vec![],
        selected_clips: vec![],
        playhead,
        is_playing: is_playing != 0,
        is_recording: is_recording != 0,
        sample_rate,
        block_size: 512,
    };

    s.manager.engine().update_context(ctx);
}

/// Set selected track IDs in script context.
#[unsafe(no_mangle)]
pub extern "C" fn script_set_selected_tracks(
    track_ids: *const u64,
    count: u32,
) {
    if track_ids.is_null() || count == 0 {
        return;
    }

    let ids = unsafe {
        std::slice::from_raw_parts(track_ids, count as usize)
    };

    let Some(state) = script_state() else { return };
    let s = state.read();

    // Build context with current state + new track selection
    let ctx = ScriptContext {
        project_path: None,
        selected_tracks: ids.to_vec(),
        selected_clips: vec![],
        playhead: 0,
        is_playing: false,
        is_recording: false,
        sample_rate: 48000,
        block_size: 512,
    };

    s.manager.engine().update_context(ctx);
}

/// Set selected clip IDs in script context.
#[unsafe(no_mangle)]
pub extern "C" fn script_set_selected_clips(
    clip_ids: *const u64,
    count: u32,
) {
    if clip_ids.is_null() || count == 0 {
        return;
    }

    let ids = unsafe {
        std::slice::from_raw_parts(clip_ids, count as usize)
    };

    let Some(state) = script_state() else { return };
    let s = state.read();

    let ctx = ScriptContext {
        project_path: None,
        selected_tracks: vec![],
        selected_clips: ids.to_vec(),
        playhead: 0,
        is_playing: false,
        is_recording: false,
        sample_rate: 48000,
        block_size: 512,
    };

    s.manager.engine().update_context(ctx);
}

// ════════════════════════════════════════════════════════════════════
// SCRIPT MANAGEMENT
// ════════════════════════════════════════════════════════════════════

/// Add a search path for user scripts.
#[unsafe(no_mangle)]
pub extern "C" fn script_add_search_path(path: *const c_char) {
    if path.is_null() {
        return;
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return,
    };

    let Some(state) = script_state() else { return };
    let mut s = state.write();
    s.manager.engine_mut().add_search_path(path_str);
    log::info!("SCRIPT FFI: Added search path '{}'", path_str);
}

/// Get count of loaded scripts.
#[unsafe(no_mangle)]
pub extern "C" fn script_get_loaded_count() -> u32 {
    let Some(state) = script_state() else { return 0 };
    let s = state.read();
    s.manager.list_all_scripts().len() as u32
}

/// Get script name by index. Returns C string (caller must free).
#[unsafe(no_mangle)]
pub extern "C" fn script_get_name(index: u32) -> *mut c_char {
    let Some(state) = script_state() else {
        return std::ptr::null_mut();
    };
    let s = state.read();
    let scripts = s.manager.list_all_scripts();

    if (index as usize) >= scripts.len() {
        return std::ptr::null_mut();
    }

    match CString::new(scripts[index as usize].as_str()) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Get script description by index. Returns C string (caller must free).
/// For now returns the script name as description (rf-script doesn't have separate descriptions).
#[unsafe(no_mangle)]
pub extern "C" fn script_get_description(index: u32) -> *mut c_char {
    // rf-script doesn't store separate descriptions — return name
    script_get_name(index)
}

// ════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════

/// Drain actions from the script engine into the pending_actions buffer as JSON.
fn drain_actions(state: &mut ScriptManagerState) {
    let actions = state.manager.engine().poll_actions();
    for action in actions {
        let json = action_to_json(&action);
        state.pending_actions.push(json);
    }
}

/// Convert a ScriptAction to JSON string for Flutter consumption.
fn action_to_json(action: &rf_script::ScriptAction) -> String {
    use rf_script::ScriptAction::*;
    match action {
        Play => r#"{"type":"play"}"#.into(),
        Stop => r#"{"type":"stop"}"#.into(),
        Record => r#"{"type":"record"}"#.into(),
        SetPlayhead(pos) => format!(r#"{{"type":"setPlayhead","position":{}}}"#, pos),
        SetLoop(s, e) => format!(r#"{{"type":"setLoop","start":{},"end":{}}}"#, s, e),
        CreateTrack { name, track_type } => {
            format!(r#"{{"type":"createTrack","name":"{}","trackType":"{}"}}"#, name, track_type)
        }
        DeleteTrack(id) => format!(r#"{{"type":"deleteTrack","id":{}}}"#, id),
        RenameTrack(id, name) => format!(r#"{{"type":"renameTrack","id":{},"name":"{}"}}"#, id, name),
        MuteTrack(id, muted) => format!(r#"{{"type":"muteTrack","id":{},"muted":{}}}"#, id, muted),
        SoloTrack(id, solo) => format!(r#"{{"type":"soloTrack","id":{},"solo":{}}}"#, id, solo),
        SetTrackVolume(id, vol) => format!(r#"{{"type":"setTrackVolume","id":{},"volume":{}}}"#, id, vol),
        SetTrackPan(id, pan) => format!(r#"{{"type":"setTrackPan","id":{},"pan":{}}}"#, id, pan),
        CreateClip { track_id, start, length } => {
            format!(r#"{{"type":"createClip","trackId":{},"start":{},"length":{}}}"#, track_id, start, length)
        }
        DeleteClip(id) => format!(r#"{{"type":"deleteClip","id":{}}}"#, id),
        MoveClip { clip_id, new_start } => {
            format!(r#"{{"type":"moveClip","clipId":{},"newStart":{}}}"#, clip_id, new_start)
        }
        TrimClip { clip_id, new_start, new_end } => {
            format!(r#"{{"type":"trimClip","clipId":{},"newStart":{},"newEnd":{}}}"#, clip_id, new_start, new_end)
        }
        SplitClip { clip_id, position } => {
            format!(r#"{{"type":"splitClip","clipId":{},"position":{}}}"#, clip_id, position)
        }
        DuplicateClip(id) => format!(r#"{{"type":"duplicateClip","id":{}}}"#, id),
        SelectTrack(id) => format!(r#"{{"type":"selectTrack","id":{}}}"#, id),
        SelectClip(id) => format!(r#"{{"type":"selectClip","id":{}}}"#, id),
        SelectAll => r#"{"type":"selectAll"}"#.into(),
        DeselectAll => r#"{"type":"deselectAll"}"#.into(),
        Cut => r#"{"type":"cut"}"#.into(),
        Copy => r#"{"type":"copy"}"#.into(),
        Paste => r#"{"type":"paste"}"#.into(),
        Delete => r#"{"type":"delete"}"#.into(),
        Undo => r#"{"type":"undo"}"#.into(),
        Redo => r#"{"type":"redo"}"#.into(),
        InsertPlugin { track_id, slot, plugin_id } => {
            format!(r#"{{"type":"insertPlugin","trackId":{},"slot":{},"pluginId":"{}"}}"#, track_id, slot, plugin_id)
        }
        RemovePlugin { track_id, slot } => {
            format!(r#"{{"type":"removePlugin","trackId":{},"slot":{}}}"#, track_id, slot)
        }
        SetPluginParam { track_id, slot, param_id, value } => {
            format!(r#"{{"type":"setPluginParam","trackId":{},"slot":{},"paramId":{},"value":{}}}"#, track_id, slot, param_id, value)
        }
        WriteAutomation { track_id, param, time, value } => {
            format!(r#"{{"type":"writeAutomation","trackId":{},"param":"{}","time":{},"value":{}}}"#, track_id, param, time, value)
        }
        ClearAutomation { track_id, param } => {
            format!(r#"{{"type":"clearAutomation","trackId":{},"param":"{}"}}"#, track_id, param)
        }
        AddMarker { position, name, color } => {
            format!(r#"{{"type":"addMarker","position":{},"name":"{}","color":{}}}"#, position, name, color)
        }
        DeleteMarker(id) => format!(r#"{{"type":"deleteMarker","id":{}}}"#, id),
        Save => r#"{"type":"save"}"#.into(),
        SaveAs(path) => format!(r#"{{"type":"saveAs","path":"{}"}}"#, path.display()),
        Export { path, format } => {
            format!(r#"{{"type":"export","path":"{}","format":"{}"}}"#, path.display(), format)
        }
        Custom { name, data } => {
            format!(r#"{{"type":"custom","name":"{}","data":"{}"}}"#, name, data)
        }
    }
}

//! Container System FFI — Rust-side container evaluation for Flutter
//!
//! Provides C-compatible functions for high-performance container operations:
//! - Blend containers: RTPC-based crossfade evaluation
//! - Random containers: Weighted selection with shuffle/round-robin
//! - Sequence containers: Precise timing and step scheduling
//!
//! ## Performance
//!
//! Container evaluation in Rust is < 1ms vs 5-10ms in Dart:
//! - Lock-free storage via DashMap
//! - SIMD-friendly crossfade curves
//! - XorShift RNG for random selection
//! - Microsecond-accurate sequence timing

use once_cell::sync::Lazy;
use parking_lot::Mutex;
use std::ffi::{CStr, c_char};
use std::sync::atomic::{AtomicBool, Ordering};

use rf_engine::containers::{
    BlendChild, BlendContainer, BlendCurve, ContainerGroup, ContainerStorage, ContainerType,
    GroupChild, GroupEvaluationMode, RandomChild, RandomContainer, RandomMode, RandomVariation,
    SequenceContainer, SequenceEndBehavior, SequenceStep,
};

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialization flag
static INITIALIZED: AtomicBool = AtomicBool::new(false);

/// Global container storage (thread-safe via DashMap)
static STORAGE: Lazy<ContainerStorage> = Lazy::new(ContainerStorage::new);

/// JSON parse error buffer
static LAST_ERROR: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the container system
/// Returns 1 on success, 0 if already initialized
#[unsafe(no_mangle)]
pub extern "C" fn container_init() -> i32 {
    if INITIALIZED.swap(true, Ordering::SeqCst) {
        log::warn!("[container_ffi] Already initialized");
        return 0;
    }

    log::info!("[container_ffi] Container system initialized");
    1
}

/// Shutdown the container system
#[unsafe(no_mangle)]
pub extern "C" fn container_shutdown() {
    if !INITIALIZED.swap(false, Ordering::SeqCst) {
        log::warn!("[container_ffi] Not initialized");
        return;
    }

    STORAGE.clear();
    log::info!("[container_ffi] Container system shutdown");
}

/// Get last error message
/// Returns pointer to null-terminated UTF-8 string
#[unsafe(no_mangle)]
pub extern "C" fn container_get_last_error() -> *const c_char {
    static ERROR_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    let error = LAST_ERROR.lock();
    let mut buf = ERROR_BUF.lock();
    buf.clear();
    buf.extend_from_slice(error.as_bytes());
    buf.push(0); // Null terminator
    buf.as_ptr() as *const c_char
}

fn set_error(msg: &str) {
    *LAST_ERROR.lock() = msg.to_string();
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLEND CONTAINER FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a blend container from JSON
/// JSON format: { "id": 1, "name": "...", "curve": 0, "children": [...] }
/// Returns container ID on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn container_create_blend(json_ptr: *const c_char) -> u32 {
    let json_str = match unsafe { CStr::from_ptr(json_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid UTF-8 in JSON");
            return 0;
        }
    };

    match parse_blend_container(json_str) {
        Ok(container) => {
            let id = container.id;
            STORAGE.insert_blend(container);
            log::debug!("[container_ffi] Created blend container {}", id);
            id
        }
        Err(e) => {
            set_error(&e);
            log::error!("[container_ffi] Failed to create blend: {}", e);
            0
        }
    }
}

/// Update a blend container from JSON
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn container_update_blend(json_ptr: *const c_char) -> i32 {
    let json_str = match unsafe { CStr::from_ptr(json_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid UTF-8 in JSON");
            return 0;
        }
    };

    match parse_blend_container(json_str) {
        Ok(container) => {
            STORAGE.insert_blend(container);
            1
        }
        Err(e) => {
            set_error(&e);
            0
        }
    }
}

/// Remove a blend container
/// Returns 1 if removed, 0 if not found
#[unsafe(no_mangle)]
pub extern "C" fn container_remove_blend(container_id: u32) -> i32 {
    if STORAGE.remove_blend(container_id).is_some() {
        log::debug!("[container_ffi] Removed blend container {}", container_id);
        1
    } else {
        0
    }
}

/// Set RTPC value for a blend container (instant, bypasses smoothing)
#[unsafe(no_mangle)]
pub extern "C" fn container_set_blend_rtpc(container_id: u32, rtpc: f64) {
    STORAGE.set_blend_rtpc(container_id, rtpc);
}

/// Set RTPC target value for smoothed interpolation (P3D)
#[unsafe(no_mangle)]
pub extern "C" fn container_set_blend_rtpc_target(container_id: u32, rtpc: f64) {
    STORAGE.set_blend_rtpc_target(container_id, rtpc);
}

/// Set smoothing time in milliseconds for blend container (P3D)
/// 0 = instant, typical values: 50-500ms
#[unsafe(no_mangle)]
pub extern "C" fn container_set_blend_smoothing(container_id: u32, smoothing_ms: f64) {
    STORAGE.set_blend_smoothing(container_id, smoothing_ms);
}

/// Tick smoothing for a blend container by delta milliseconds (P3D)
/// Returns 1 if value changed, 0 if unchanged, -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn container_tick_blend_smoothing(container_id: u32, delta_ms: f64) -> i32 {
    match STORAGE.tick_blend_smoothing(container_id, delta_ms) {
        Some(changed) => {
            if changed {
                1
            } else {
                0
            }
        }
        None => -1,
    }
}

/// Evaluate blend container at given RTPC value
/// Writes results to output arrays (child_ids, volumes)
/// Returns number of active children, or -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn container_evaluate_blend(
    container_id: u32,
    rtpc: f64,
    out_child_ids: *mut u32,
    out_volumes: *mut f64,
    max_results: usize,
) -> i32 {
    if out_child_ids.is_null() || out_volumes.is_null() {
        set_error("Null output pointers");
        return -1;
    }

    match STORAGE.evaluate_blend(container_id, rtpc) {
        Some(result) => {
            let count = result.children.len().min(max_results);
            for (i, (child_id, volume)) in result.children.iter().take(count).enumerate() {
                unsafe {
                    *out_child_ids.add(i) = *child_id;
                    *out_volumes.add(i) = *volume;
                }
            }
            count as i32
        }
        None => {
            set_error("Container not found or disabled");
            -1
        }
    }
}

/// Get blend child audio path
/// Returns pointer to null-terminated path, or null if not found
/// IMPORTANT: Caller must NOT free the returned pointer
#[unsafe(no_mangle)]
pub extern "C" fn container_get_blend_child_audio_path(
    container_id: u32,
    child_id: u32,
) -> *const c_char {
    static PATH_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    match STORAGE.get_blend_child_audio_path(container_id, child_id) {
        Some(path) => {
            let mut buf = PATH_BUF.lock();
            buf.clear();
            buf.extend_from_slice(path.as_bytes());
            buf.push(0);
            buf.as_ptr() as *const c_char
        }
        None => std::ptr::null(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RANDOM CONTAINER FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a random container from JSON
/// Returns container ID on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn container_create_random(json_ptr: *const c_char) -> u32 {
    let json_str = match unsafe { CStr::from_ptr(json_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid UTF-8 in JSON");
            return 0;
        }
    };

    match parse_random_container(json_str) {
        Ok(container) => {
            let id = container.id;
            STORAGE.insert_random(container);
            log::debug!("[container_ffi] Created random container {}", id);
            id
        }
        Err(e) => {
            set_error(&e);
            log::error!("[container_ffi] Failed to create random: {}", e);
            0
        }
    }
}

/// Update a random container from JSON
#[unsafe(no_mangle)]
pub extern "C" fn container_update_random(json_ptr: *const c_char) -> i32 {
    let json_str = match unsafe { CStr::from_ptr(json_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid UTF-8 in JSON");
            return 0;
        }
    };

    match parse_random_container(json_str) {
        Ok(container) => {
            STORAGE.insert_random(container);
            1
        }
        Err(e) => {
            set_error(&e);
            0
        }
    }
}

/// Remove a random container
#[unsafe(no_mangle)]
pub extern "C" fn container_remove_random(container_id: u32) -> i32 {
    if STORAGE.remove_random(container_id).is_some() {
        log::debug!("[container_ffi] Removed random container {}", container_id);
        1
    } else {
        0
    }
}

/// Seed the random container's RNG
#[unsafe(no_mangle)]
pub extern "C" fn container_seed_random(container_id: u32, seed: u64) {
    STORAGE.seed_random(container_id, seed);
}

/// Reset random container state (shuffle deck, round-robin index)
#[unsafe(no_mangle)]
pub extern "C" fn container_reset_random(container_id: u32) {
    STORAGE.reset_random(container_id);
}

/// Select from random container
/// Writes result to output parameters
/// Returns 1 on success, 0 if no selection (disabled/empty), -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn container_select_random(
    container_id: u32,
    out_child_id: *mut u32,
    out_pitch_offset: *mut f64,
    out_volume_offset: *mut f64,
) -> i32 {
    if out_child_id.is_null() || out_pitch_offset.is_null() || out_volume_offset.is_null() {
        set_error("Null output pointers");
        return -1;
    }

    match STORAGE.select_random(container_id) {
        Some(result) => {
            unsafe {
                *out_child_id = result.child_id;
                *out_pitch_offset = result.pitch_offset;
                *out_volume_offset = result.volume_offset;
            }
            1
        }
        None => 0,
    }
}

/// Get random child audio path
#[unsafe(no_mangle)]
pub extern "C" fn container_get_random_child_audio_path(
    container_id: u32,
    child_id: u32,
) -> *const c_char {
    static PATH_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    match STORAGE.get_random_child_audio_path(container_id, child_id) {
        Some(path) => {
            let mut buf = PATH_BUF.lock();
            buf.clear();
            buf.extend_from_slice(path.as_bytes());
            buf.push(0);
            buf.as_ptr() as *const c_char
        }
        None => std::ptr::null(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEQUENCE CONTAINER FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a sequence container from JSON
/// Returns container ID on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn container_create_sequence(json_ptr: *const c_char) -> u32 {
    let json_str = match unsafe { CStr::from_ptr(json_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid UTF-8 in JSON");
            return 0;
        }
    };

    match parse_sequence_container(json_str) {
        Ok(container) => {
            let id = container.id;
            STORAGE.insert_sequence(container);
            log::debug!("[container_ffi] Created sequence container {}", id);
            id
        }
        Err(e) => {
            set_error(&e);
            log::error!("[container_ffi] Failed to create sequence: {}", e);
            0
        }
    }
}

/// Update a sequence container from JSON
#[unsafe(no_mangle)]
pub extern "C" fn container_update_sequence(json_ptr: *const c_char) -> i32 {
    let json_str = match unsafe { CStr::from_ptr(json_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid UTF-8 in JSON");
            return 0;
        }
    };

    match parse_sequence_container(json_str) {
        Ok(container) => {
            STORAGE.insert_sequence(container);
            1
        }
        Err(e) => {
            set_error(&e);
            0
        }
    }
}

/// Remove a sequence container
#[unsafe(no_mangle)]
pub extern "C" fn container_remove_sequence(container_id: u32) -> i32 {
    if STORAGE.remove_sequence(container_id).is_some() {
        log::debug!(
            "[container_ffi] Removed sequence container {}",
            container_id
        );
        1
    } else {
        0
    }
}

/// Start sequence playback
#[unsafe(no_mangle)]
pub extern "C" fn container_play_sequence(container_id: u32) {
    STORAGE.play_sequence(container_id);
}

/// Stop sequence playback
#[unsafe(no_mangle)]
pub extern "C" fn container_stop_sequence(container_id: u32) {
    STORAGE.stop_sequence(container_id);
}

/// Pause sequence playback
#[unsafe(no_mangle)]
pub extern "C" fn container_pause_sequence(container_id: u32) {
    STORAGE.pause_sequence(container_id);
}

/// Resume sequence playback
#[unsafe(no_mangle)]
pub extern "C" fn container_resume_sequence(container_id: u32) {
    STORAGE.resume_sequence(container_id);
}

/// Check if sequence is playing
/// Returns 1 if playing, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn container_is_sequence_playing(container_id: u32) -> i32 {
    if STORAGE.is_sequence_playing(container_id) {
        1
    } else {
        0
    }
}

/// Tick sequence by delta milliseconds
/// Writes triggered step indices to output array
/// Returns number of triggered steps, or -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn container_tick_sequence(
    container_id: u32,
    delta_ms: f64,
    out_step_indices: *mut usize,
    max_steps: usize,
    out_ended: *mut i32,
    out_looped: *mut i32,
) -> i32 {
    if out_step_indices.is_null() || out_ended.is_null() || out_looped.is_null() {
        set_error("Null output pointers");
        return -1;
    }

    match STORAGE.tick_sequence(container_id, delta_ms) {
        Some(result) => {
            let count = result.trigger_steps.len().min(max_steps);
            for (i, &step_idx) in result.trigger_steps.iter().take(count).enumerate() {
                unsafe {
                    *out_step_indices.add(i) = step_idx;
                }
            }
            unsafe {
                *out_ended = if result.ended { 1 } else { 0 };
                *out_looped = if result.looped { 1 } else { 0 };
            }
            count as i32
        }
        None => -1,
    }
}

/// Get sequence step audio path
#[unsafe(no_mangle)]
pub extern "C" fn container_get_sequence_step_audio_path(
    container_id: u32,
    step_index: usize,
) -> *const c_char {
    static PATH_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    match STORAGE.get_sequence_step_audio_path(container_id, step_index) {
        Some(path) => {
            let mut buf = PATH_BUF.lock();
            buf.clear();
            buf.extend_from_slice(path.as_bytes());
            buf.push(0);
            buf.as_ptr() as *const c_char
        }
        None => std::ptr::null(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTAINER GROUPS (P3C)
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a container group from JSON
/// JSON format: {"id": u32, "name": str, "mode": u8, "children": [...]}
/// Returns container ID on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn container_create_group(json: *const c_char) -> u32 {
    let json_str = match unsafe { CStr::from_ptr(json) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            *LAST_ERROR.lock() = "Invalid UTF-8 in JSON".to_string();
            return 0;
        }
    };

    match parse_group_container(json_str) {
        Ok(group) => {
            let id = group.id;
            STORAGE.insert_group(group);
            log::info!("[container_ffi] Created group {}", id);
            id
        }
        Err(e) => {
            *LAST_ERROR.lock() = e;
            0
        }
    }
}

/// Remove a container group
/// Returns 1 on success, 0 if not found
#[unsafe(no_mangle)]
pub extern "C" fn container_remove_group(id: u32) -> i32 {
    match STORAGE.remove_group(id) {
        Some(_) => {
            log::info!("[container_ffi] Removed group {}", id);
            1
        }
        None => 0,
    }
}

/// Get group child count
#[unsafe(no_mangle)]
pub extern "C" fn container_get_group_child_count(id: u32) -> i32 {
    match STORAGE.get_group(id) {
        Some(group) => group.children.len() as i32,
        None => -1,
    }
}

/// Evaluate a container group
/// Returns child container references via output arrays
/// out_types, out_ids: arrays for container type/id pairs
/// max_children: max output capacity
/// Returns number of active children, -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn container_evaluate_group(
    id: u32,
    out_types: *mut u8,
    out_ids: *mut u32,
    max_children: usize,
) -> i32 {
    match STORAGE.get_group(id) {
        Some(group) => {
            if !group.enabled {
                return 0;
            }

            let result = group.evaluate();
            let count = result.children.len().min(max_children);

            for (i, child) in result.children.iter().take(count).enumerate() {
                unsafe {
                    *out_types.add(i) = child.container_type as u8;
                    *out_ids.add(i) = child.container_id;
                }
            }

            count as i32
        }
        None => -1,
    }
}

/// Add a child to a container group
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn container_group_add_child(
    group_id: u32,
    child_type: u8,
    child_id: u32,
    name: *const c_char,
    order: u32,
) -> i32 {
    let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => "Unnamed".to_string(),
    };

    match STORAGE.get_group(group_id) {
        Some(mut group) => {
            let child = GroupChild {
                container_type: ContainerType::from_u8(child_type),
                container_id: child_id,
                name: name_str,
                enabled: true,
                order,
            };
            group.add_child(child);
            STORAGE.insert_group(group);
            1
        }
        None => 0,
    }
}

/// Remove a child from a container group
/// Returns 1 on success, 0 if not found
#[unsafe(no_mangle)]
pub extern "C" fn container_group_remove_child(group_id: u32, child_id: u32) -> i32 {
    match STORAGE.get_group(group_id) {
        Some(mut group) => {
            if group.remove_child_by_id(child_id) {
                STORAGE.insert_group(group);
                1
            } else {
                0
            }
        }
        None => 0,
    }
}

/// Set group evaluation mode
/// mode: 0=All, 1=FirstMatch, 2=Priority, 3=Random
#[unsafe(no_mangle)]
pub extern "C" fn container_set_group_mode(group_id: u32, mode: u8) -> i32 {
    match STORAGE.get_group(group_id) {
        Some(mut group) => {
            group.mode = GroupEvaluationMode::from_u8(mode);
            STORAGE.insert_group(group);
            1
        }
        None => 0,
    }
}

/// Set group enabled state
#[unsafe(no_mangle)]
pub extern "C" fn container_set_group_enabled(group_id: u32, enabled: i32) -> i32 {
    match STORAGE.get_group(group_id) {
        Some(mut group) => {
            group.enabled = enabled != 0;
            STORAGE.insert_group(group);
            1
        }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Get total container count
#[unsafe(no_mangle)]
pub extern "C" fn container_get_total_count() -> usize {
    STORAGE.total_count()
}

/// Get container count by type
/// type: 1=Blend, 2=Random, 3=Sequence, 4=Group
#[unsafe(no_mangle)]
pub extern "C" fn container_get_count_by_type(container_type: u8) -> usize {
    match ContainerType::from_u8(container_type) {
        ContainerType::Blend => STORAGE.blend_count(),
        ContainerType::Random => STORAGE.random_count(),
        ContainerType::Sequence => STORAGE.sequence_count(),
        ContainerType::Group => STORAGE.group_count(),
        ContainerType::None => 0,
    }
}

/// Check if container exists
/// Returns 1 if exists, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn container_exists(container_type: u8, container_id: u32) -> i32 {
    if STORAGE.exists(ContainerType::from_u8(container_type), container_id) {
        1
    } else {
        0
    }
}

/// Clear all containers
#[unsafe(no_mangle)]
pub extern "C" fn container_clear_all() {
    STORAGE.clear();
    log::info!("[container_ffi] All containers cleared");
}

// ═══════════════════════════════════════════════════════════════════════════════
// JSON PARSING
// ═══════════════════════════════════════════════════════════════════════════════

fn parse_blend_container(json: &str) -> Result<BlendContainer, String> {
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("JSON parse error: {}", e))?;

    let id = v["id"].as_u64().ok_or("Missing 'id'")? as u32;
    let name = v["name"].as_str().unwrap_or("Unnamed").to_string();
    let enabled = v["enabled"].as_bool().unwrap_or(true);
    let rtpc_value = v["rtpcValue"].as_f64().unwrap_or(0.5);
    let rtpc_name = v["rtpcName"].as_str().unwrap_or("").to_string();
    let curve = BlendCurve::from_u8(v["curve"].as_u64().unwrap_or(0) as u8);

    let mut container = BlendContainer::new(id, name);
    container.enabled = enabled;
    container.rtpc_value = rtpc_value;
    container.rtpc_name = rtpc_name;
    container.curve = curve;

    if let Some(children) = v["children"].as_array() {
        for child_v in children {
            let child_id = child_v["id"].as_u64().ok_or("Child missing 'id'")? as u32;
            let child_name = child_v["name"].as_str().unwrap_or("Unnamed");
            let rtpc_start = child_v["rtpcStart"].as_f64().unwrap_or(0.0);
            let rtpc_end = child_v["rtpcEnd"].as_f64().unwrap_or(1.0);

            let mut child = BlendChild::new(child_id, child_name, rtpc_start, rtpc_end);
            child.audio_path = child_v["audioPath"].as_str().map(String::from);
            child.crossfade_width = child_v["crossfadeWidth"].as_f64().unwrap_or(0.1);
            child.volume = child_v["volume"].as_f64().unwrap_or(1.0);

            container.add_child(child);
        }
    }

    Ok(container)
}

fn parse_random_container(json: &str) -> Result<RandomContainer, String> {
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("JSON parse error: {}", e))?;

    let id = v["id"].as_u64().ok_or("Missing 'id'")? as u32;
    let name = v["name"].as_str().unwrap_or("Unnamed").to_string();
    let enabled = v["enabled"].as_bool().unwrap_or(true);
    let mode = RandomMode::from_u8(v["mode"].as_u64().unwrap_or(0) as u8);
    let avoid_repeat = v["avoidRepeat"].as_bool().unwrap_or(true);
    let avoid_repeat_count = v["avoidRepeatCount"].as_u64().unwrap_or(1) as usize;

    let mut container = RandomContainer::new(id, name);
    container.enabled = enabled;
    container.mode = mode;
    container.avoid_repeat = avoid_repeat;
    container.avoid_repeat_count = avoid_repeat_count;
    container.global_pitch_min = v["globalPitchMin"].as_f64().unwrap_or(0.0);
    container.global_pitch_max = v["globalPitchMax"].as_f64().unwrap_or(0.0);
    container.global_volume_min = v["globalVolumeMin"].as_f64().unwrap_or(0.0);
    container.global_volume_max = v["globalVolumeMax"].as_f64().unwrap_or(0.0);

    if let Some(children) = v["children"].as_array() {
        for child_v in children {
            let child_id = child_v["id"].as_u64().ok_or("Child missing 'id'")? as u32;
            let child_name = child_v["name"].as_str().unwrap_or("Unnamed");
            let weight = child_v["weight"].as_f64().unwrap_or(1.0);

            let mut child = RandomChild::with_weight(child_id, child_name, weight);
            child.audio_path = child_v["audioPath"].as_str().map(String::from);
            child.variation = RandomVariation::new(
                child_v["pitchMin"].as_f64().unwrap_or(0.0),
                child_v["pitchMax"].as_f64().unwrap_or(0.0),
                child_v["volumeMin"].as_f64().unwrap_or(0.0),
                child_v["volumeMax"].as_f64().unwrap_or(0.0),
            );

            container.add_child(child);
        }
    }

    Ok(container)
}

fn parse_sequence_container(json: &str) -> Result<SequenceContainer, String> {
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("JSON parse error: {}", e))?;

    let id = v["id"].as_u64().ok_or("Missing 'id'")? as u32;
    let name = v["name"].as_str().unwrap_or("Unnamed").to_string();
    let enabled = v["enabled"].as_bool().unwrap_or(true);
    let end_behavior = SequenceEndBehavior::from_u8(v["endBehavior"].as_u64().unwrap_or(0) as u8);
    let speed = v["speed"].as_f64().unwrap_or(1.0);

    let mut container = SequenceContainer::new(id, name);
    container.enabled = enabled;
    container.end_behavior = end_behavior;
    container.speed = speed;

    if let Some(steps) = v["steps"].as_array() {
        for (i, step_v) in steps.iter().enumerate() {
            let child_id = step_v["childId"].as_u64().unwrap_or(i as u64 + 1) as u32;
            let child_name = step_v["childName"].as_str().unwrap_or("Step");
            let delay_ms = step_v["delayMs"].as_f64().unwrap_or(0.0);
            let duration_ms = step_v["durationMs"].as_f64().unwrap_or(1000.0);

            let mut step = SequenceStep::new(i, child_id, child_name, delay_ms, duration_ms);
            step.audio_path = step_v["audioPath"].as_str().map(String::from);
            step.fade_in_ms = step_v["fadeInMs"].as_f64().unwrap_or(0.0);
            step.fade_out_ms = step_v["fadeOutMs"].as_f64().unwrap_or(0.0);
            step.loop_count = step_v["loopCount"].as_u64().unwrap_or(1) as u32;
            step.volume = step_v["volume"].as_f64().unwrap_or(1.0);

            container.add_step(step);
        }
    }

    Ok(container)
}

fn parse_group_container(json: &str) -> Result<ContainerGroup, String> {
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("JSON parse error: {}", e))?;

    let id = v["id"].as_u64().ok_or("Missing 'id'")? as u32;
    let name = v["name"].as_str().unwrap_or("Unnamed").to_string();
    let enabled = v["enabled"].as_bool().unwrap_or(true);
    let mode = GroupEvaluationMode::from_u8(v["mode"].as_u64().unwrap_or(0) as u8);

    let mut group = ContainerGroup::new(id, name);
    group.enabled = enabled;
    group.mode = mode;

    if let Some(children) = v["children"].as_array() {
        for child_v in children {
            let child_type =
                ContainerType::from_u8(child_v["containerType"].as_u64().unwrap_or(0) as u8);
            let child_id = child_v["containerId"]
                .as_u64()
                .ok_or("Child missing 'containerId'")? as u32;
            let child_name = child_v["name"].as_str().unwrap_or("Unnamed").to_string();
            let child_enabled = child_v["enabled"].as_bool().unwrap_or(true);
            let order = child_v["order"].as_u64().unwrap_or(0) as u32;

            let child = GroupChild {
                container_type: child_type,
                container_id: child_id,
                name: child_name,
                enabled: child_enabled,
                order,
            };
            group.add_child(child);
        }
    }

    Ok(group)
}

// ═══════════════════════════════════════════════════════════════════════════════
// VALIDATION FFI
// ═══════════════════════════════════════════════════════════════════════════════

/// Validate a container group for depth/cycle issues
/// Returns JSON: {"valid": bool, "maxDepth": int, "total": int, "errors": [...]}
/// Returns null pointer on error
#[unsafe(no_mangle)]
pub extern "C" fn container_validate_group(group_id: u32) -> *const c_char {
    static RESULT_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    match STORAGE.validate_group(group_id) {
        Some(result) => {
            let json = serde_json::json!({
                "valid": result.valid,
                "maxDepth": result.max_depth_found,
                "total": result.total_containers,
                "errors": result.errors.iter().map(|e| e.to_string()).collect::<Vec<_>>(),
                "warnings": result.warnings,
            });

            let json_str = serde_json::to_string(&json).unwrap_or_else(|_| "{}".into());
            let mut buf = RESULT_BUF.lock();
            buf.clear();
            buf.extend_from_slice(json_str.as_bytes());
            buf.push(0);
            buf.as_ptr() as *const c_char
        }
        None => std::ptr::null(),
    }
}

/// Validate proposed child addition without modifying storage
/// Returns 0 on success, error code on failure:
/// - 1: Self-reference
/// - 2: Missing container
/// - 3: Cycle detected
/// - 4: Max depth exceeded
/// - 5: Too many children
/// - 99: Unknown error
#[unsafe(no_mangle)]
pub extern "C" fn container_validate_add_child(
    group_id: u32,
    child_type: u8,
    child_id: u32,
) -> i32 {
    use rf_engine::containers::group::ValidationError;

    match STORAGE.validate_group_child_addition(
        group_id,
        ContainerType::from_u8(child_type),
        child_id,
    ) {
        Ok(()) => 0,
        Err(e) => match e {
            ValidationError::SelfReference { .. } => 1,
            ValidationError::MissingContainer { .. } => 2,
            ValidationError::CycleDetected { .. } => 3,
            ValidationError::MaxDepthExceeded { .. } => 4,
            ValidationError::TooManyChildren { .. } => 5,
        },
    }
}

/// Get maximum allowed nesting depth
#[unsafe(no_mangle)]
pub extern "C" fn container_get_max_nesting_depth() -> usize {
    rf_engine::containers::group::MAX_NESTING_DEPTH
}

/// Validate all groups in storage
/// Returns JSON array: [{"id": int, "valid": bool, "errors": [...]}]
#[unsafe(no_mangle)]
pub extern "C" fn container_validate_all_groups() -> *const c_char {
    static RESULT_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    let results: Vec<serde_json::Value> = STORAGE
        .validate_all_groups()
        .iter()
        .map(|(id, result)| {
            serde_json::json!({
                "id": id,
                "valid": result.valid,
                "maxDepth": result.max_depth_found,
                "errors": result.errors.iter().map(|e| e.to_string()).collect::<Vec<_>>(),
            })
        })
        .collect();

    let json_str = serde_json::to_string(&results).unwrap_or_else(|_| "[]".into());
    let mut buf = RESULT_BUF.lock();
    buf.clear();
    buf.extend_from_slice(json_str.as_bytes());
    buf.push(0);
    buf.as_ptr() as *const c_char
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEED LOG (DETERMINISM)
// ═══════════════════════════════════════════════════════════════════════════════

/// Enable or disable seed logging for determinism capture
/// enabled: 1 = enable, 0 = disable
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_enable(enabled: i32) {
    use rf_engine::containers::random::SEED_LOG;

    let log = SEED_LOG.lock();
    if enabled != 0 {
        log.enable();
    } else {
        log.disable();
    }
}

/// Check if seed logging is enabled
/// Returns 1 if enabled, 0 if disabled
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_is_enabled() -> i32 {
    use rf_engine::containers::random::SEED_LOG;

    let log = SEED_LOG.lock();
    if log.is_enabled() { 1 } else { 0 }
}

/// Clear all seed log entries
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_clear() {
    use rf_engine::containers::random::SEED_LOG;

    let mut log = SEED_LOG.lock();
    log.clear();
}

/// Get count of seed log entries
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_get_count() -> usize {
    use rf_engine::containers::random::SEED_LOG;

    let log = SEED_LOG.lock();
    log.len()
}

/// Get seed log as JSON array
/// Returns pointer to null-terminated JSON string, or null on empty
/// Format: [{"tick": u64, "containerId": u32, "seedBefore": "hex", "seedAfter": "hex",
///           "selectedId": u32, "pitchOffset": f64, "volumeOffset": f64}, ...]
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_get_json() -> *const c_char {
    use rf_engine::containers::random::SEED_LOG;

    static SEED_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    let log = SEED_LOG.lock();
    let entries: Vec<serde_json::Value> = log
        .entries()
        .iter()
        .map(|e| {
            serde_json::json!({
                "tick": e.tick,
                "containerId": e.container_id,
                "seedBefore": format!("{:016x}", e.seed_before),
                "seedAfter": format!("{:016x}", e.seed_after),
                "selectedId": e.selected_id,
                "pitchOffset": e.pitch_offset,
                "volumeOffset": e.volume_offset,
            })
        })
        .collect();

    if entries.is_empty() {
        return std::ptr::null();
    }

    let json_str = serde_json::to_string(&entries).unwrap_or_else(|_| "[]".into());
    let mut buf = SEED_BUF.lock();
    buf.clear();
    buf.extend_from_slice(json_str.as_bytes());
    buf.push(0);
    buf.as_ptr() as *const c_char
}

/// Get the last N seed log entries as JSON
/// Returns pointer to null-terminated JSON string, or null on empty
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_get_last_n_json(n: usize) -> *const c_char {
    use rf_engine::containers::random::SEED_LOG;

    static LAST_N_BUF: Lazy<Mutex<Vec<u8>>> = Lazy::new(|| Mutex::new(Vec::new()));

    let log = SEED_LOG.lock();
    let all_entries = log.entries();
    let start = if all_entries.len() > n {
        all_entries.len() - n
    } else {
        0
    };

    let entries: Vec<serde_json::Value> = all_entries[start..]
        .iter()
        .map(|e| {
            serde_json::json!({
                "tick": e.tick,
                "containerId": e.container_id,
                "seedBefore": format!("{:016x}", e.seed_before),
                "seedAfter": format!("{:016x}", e.seed_after),
                "selectedId": e.selected_id,
                "pitchOffset": e.pitch_offset,
                "volumeOffset": e.volume_offset,
            })
        })
        .collect();

    if entries.is_empty() {
        return std::ptr::null();
    }

    let json_str = serde_json::to_string(&entries).unwrap_or_else(|_| "[]".into());
    let mut buf = LAST_N_BUF.lock();
    buf.clear();
    buf.extend_from_slice(json_str.as_bytes());
    buf.push(0);
    buf.as_ptr() as *const c_char
}

/// Replay a seed into a random container (for determinism testing)
/// This allows setting exact RNG state for reproducibility
/// seed: The seed value to set (hex string was converted to u64)
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_replay_seed(container_id: u32, seed: u64) -> i32 {
    if STORAGE.set_random_rng_state(container_id, seed) {
        1
    } else {
        0
    }
}

/// Get current RNG state from a random container
/// Returns the seed value, or 0 if container not found
#[unsafe(no_mangle)]
pub extern "C" fn seed_log_get_rng_state(container_id: u32) -> u64 {
    STORAGE.get_random_rng_state(container_id).unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn test_blend_container_ffi() {
        let json = r#"{
            "id": 1,
            "name": "TestBlend",
            "curve": 0,
            "children": [
                {"id": 1, "name": "Low", "rtpcStart": 0.0, "rtpcEnd": 0.5},
                {"id": 2, "name": "High", "rtpcStart": 0.4, "rtpcEnd": 1.0}
            ]
        }"#;
        let c_json = CString::new(json).unwrap();

        let id = unsafe { container_create_blend(c_json.as_ptr()) };
        assert_eq!(id, 1);

        // Evaluate
        let mut child_ids = [0u32; 8];
        let mut volumes = [0.0f64; 8];
        let count = unsafe {
            container_evaluate_blend(1, 0.45, child_ids.as_mut_ptr(), volumes.as_mut_ptr(), 8)
        };
        assert!(count >= 1);

        // Cleanup
        assert_eq!(unsafe { container_remove_blend(1) }, 1);
    }

    #[test]
    fn test_random_container_ffi() {
        let json = r#"{
            "id": 2,
            "name": "TestRandom",
            "mode": 0,
            "children": [
                {"id": 1, "name": "Sound1", "weight": 1.0},
                {"id": 2, "name": "Sound2", "weight": 2.0}
            ]
        }"#;
        let c_json = CString::new(json).unwrap();

        let id = unsafe { container_create_random(c_json.as_ptr()) };
        assert_eq!(id, 2);

        // Seed and select
        unsafe { container_seed_random(2, 12345) };

        let mut child_id = 0u32;
        let mut pitch = 0.0f64;
        let mut volume = 0.0f64;
        let result = unsafe { container_select_random(2, &mut child_id, &mut pitch, &mut volume) };
        assert_eq!(result, 1);
        assert!(child_id == 1 || child_id == 2);

        // Cleanup
        assert_eq!(unsafe { container_remove_random(2) }, 1);
    }

    #[test]
    fn test_sequence_container_ffi() {
        let json = r#"{
            "id": 3,
            "name": "TestSequence",
            "speed": 1.0,
            "endBehavior": 0,
            "steps": [
                {"childId": 1, "childName": "Step1", "delayMs": 0, "durationMs": 100},
                {"childId": 2, "childName": "Step2", "delayMs": 150, "durationMs": 100}
            ]
        }"#;
        let c_json = CString::new(json).unwrap();

        let id = unsafe { container_create_sequence(c_json.as_ptr()) };
        assert_eq!(id, 3);

        // Play and tick
        unsafe { container_play_sequence(3) };
        assert_eq!(unsafe { container_is_sequence_playing(3) }, 1);

        let mut steps = [0usize; 4];
        let mut ended = 0i32;
        let mut looped = 0i32;
        let count = unsafe {
            container_tick_sequence(3, 10.0, steps.as_mut_ptr(), 4, &mut ended, &mut looped)
        };
        assert!(count >= 0);

        // Cleanup
        unsafe { container_stop_sequence(3) };
        assert_eq!(unsafe { container_remove_sequence(3) }, 1);
    }
}

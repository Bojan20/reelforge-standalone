//! Plugin State FFI
//!
//! FFI bindings for plugin state management.
//! Allows Flutter to save/load third-party plugin states.
//!
//! Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

use once_cell::sync::Lazy;
use std::ffi::{CStr, CString, c_char};
use std::sync::Mutex;

use rf_state::{PluginFormat, PluginStateChunk, PluginStateStorage, PluginUid};

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL STATE STORAGE
// ═══════════════════════════════════════════════════════════════════════════

static STATE_STORAGE: Lazy<Mutex<PluginStateStorage>> =
    Lazy::new(|| Mutex::new(PluginStateStorage::new()));

// Thread-local buffer for returning strings
thread_local! {
    static STRING_BUFFER: std::cell::RefCell<CString> = std::cell::RefCell::new(CString::default());
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: Caller guarantees ptr is valid and null-terminated
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

fn return_string(s: &str) -> *const c_char {
    STRING_BUFFER.with(|buffer| {
        let cstring = CString::new(s).unwrap_or_default();
        *buffer.borrow_mut() = cstring;
        buffer.borrow().as_ptr()
    })
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN STATE FFI FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Store plugin state in memory cache
///
/// # Arguments
/// * `track_id` - Track ID
/// * `slot_index` - Insert slot index (0-7)
/// * `format` - Plugin format (0=VST3, 1=AU, 2=CLAP, 3=AAX, 4=LV2)
/// * `uid` - Plugin UID string (format-specific)
/// * `state_data` - Raw binary state data from plugin
/// * `state_len` - Length of state data
/// * `preset_name` - Optional preset name (can be null)
///
/// # Returns
/// 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_store(
    track_id: u32,
    slot_index: u32,
    format: u8,
    uid: *const c_char,
    state_data: *const u8,
    state_len: usize,
    preset_name: *const c_char,
) -> i32 {
    let uid_str = match unsafe { cstr_to_string(uid) } {
        Some(s) => s,
        None => return 0,
    };

    let plugin_format = match PluginFormat::from_u8(format) {
        Some(f) => f,
        None => return 0,
    };

    if state_data.is_null() || state_len == 0 {
        return 0;
    }

    let data = unsafe { std::slice::from_raw_parts(state_data, state_len) }.to_vec();
    let plugin_uid = PluginUid::new(plugin_format, uid_str);

    let mut chunk = PluginStateChunk::new(plugin_uid, data);

    if let Some(preset) = unsafe { cstr_to_string(preset_name) } {
        chunk = chunk.with_preset(preset);
    }

    match STATE_STORAGE.lock() {
        Ok(mut storage) => {
            storage.store(track_id, slot_index, chunk);
            1
        }
        Err(_) => 0,
    }
}

/// Get plugin state from memory cache
///
/// # Arguments
/// * `track_id` - Track ID
/// * `slot_index` - Insert slot index
/// * `out_data` - Output buffer for state data
/// * `out_capacity` - Capacity of output buffer
/// * `out_len` - Output: actual length of state data
///
/// # Returns
/// 1 on success (data copied), 0 on not found, -1 on buffer too small
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_get(
    track_id: u32,
    slot_index: u32,
    out_data: *mut u8,
    out_capacity: usize,
    out_len: *mut usize,
) -> i32 {
    let storage = match STATE_STORAGE.lock() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let chunk = match storage.get(track_id, slot_index) {
        Some(c) => c,
        None => return 0,
    };

    let data_len = chunk.state_data.len();

    if !out_len.is_null() {
        unsafe { *out_len = data_len };
    }

    if data_len > out_capacity {
        return -1; // Buffer too small
    }

    if !out_data.is_null() && out_capacity >= data_len {
        unsafe {
            std::ptr::copy_nonoverlapping(chunk.state_data.as_ptr(), out_data, data_len);
        }
    }

    1
}

/// Get plugin state size (for pre-allocating buffer)
///
/// # Returns
/// State size in bytes, or 0 if not found
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_get_size(track_id: u32, slot_index: u32) -> usize {
    match STATE_STORAGE.lock() {
        Ok(storage) => storage
            .get(track_id, slot_index)
            .map(|c| c.state_data.len())
            .unwrap_or(0),
        Err(_) => 0,
    }
}

/// Remove plugin state from cache
///
/// # Returns
/// 1 if removed, 0 if not found
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_remove(track_id: u32, slot_index: u32) -> i32 {
    match STATE_STORAGE.lock() {
        Ok(mut storage) => {
            if storage.remove(track_id, slot_index).is_some() {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

/// Clear all plugin states
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_clear_all() {
    if let Ok(mut storage) = STATE_STORAGE.lock() {
        storage.clear();
    }
}

/// Get number of stored plugin states
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_count() -> usize {
    match STATE_STORAGE.lock() {
        Ok(storage) => storage.len(),
        Err(_) => 0,
    }
}

/// Save plugin state to .ffstate file
///
/// # Arguments
/// * `track_id` - Track ID
/// * `slot_index` - Insert slot index
/// * `file_path` - Path to save file
///
/// # Returns
/// 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_save_to_file(
    track_id: u32,
    slot_index: u32,
    file_path: *const c_char,
) -> i32 {
    let path = match unsafe { cstr_to_string(file_path) } {
        Some(p) => p,
        None => return 0,
    };

    let storage = match STATE_STORAGE.lock() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let chunk = match storage.get(track_id, slot_index) {
        Some(c) => c,
        None => return 0,
    };

    let bytes = chunk.to_bytes();

    match std::fs::write(&path, bytes) {
        Ok(_) => {
            log::debug!("Saved plugin state to: {}", path);
            1
        }
        Err(e) => {
            log::error!("Failed to save plugin state: {}", e);
            0
        }
    }
}

/// Load plugin state from .ffstate file
///
/// # Arguments
/// * `track_id` - Track ID to load into
/// * `slot_index` - Insert slot index
/// * `file_path` - Path to load from
///
/// # Returns
/// 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_load_from_file(
    track_id: u32,
    slot_index: u32,
    file_path: *const c_char,
) -> i32 {
    let path = match unsafe { cstr_to_string(file_path) } {
        Some(p) => p,
        None => return 0,
    };

    let bytes = match std::fs::read(&path) {
        Ok(b) => b,
        Err(e) => {
            log::error!("Failed to read plugin state file: {}", e);
            return 0;
        }
    };

    let chunk = match PluginStateChunk::from_bytes(&bytes) {
        Ok(c) => c,
        Err(e) => {
            log::error!("Failed to parse plugin state: {}", e);
            return 0;
        }
    };

    match STATE_STORAGE.lock() {
        Ok(mut storage) => {
            storage.store(track_id, slot_index, chunk);
            log::debug!("Loaded plugin state from: {}", path);
            1
        }
        Err(_) => 0,
    }
}

/// Get plugin UID for a stored state
///
/// # Returns
/// Pointer to UID string (format:uid), or null if not found
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_get_uid(track_id: u32, slot_index: u32) -> *const c_char {
    match STATE_STORAGE.lock() {
        Ok(storage) => {
            if let Some(chunk) = storage.get(track_id, slot_index) {
                return_string(&chunk.plugin_uid.to_string())
            } else {
                std::ptr::null()
            }
        }
        Err(_) => std::ptr::null(),
    }
}

/// Get preset name for a stored state
///
/// # Returns
/// Pointer to preset name string, or null if not set
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_get_preset_name(track_id: u32, slot_index: u32) -> *const c_char {
    match STATE_STORAGE.lock() {
        Ok(storage) => {
            if let Some(chunk) = storage.get(track_id, slot_index) {
                if let Some(ref name) = chunk.preset_name {
                    return_string(name)
                } else {
                    std::ptr::null()
                }
            } else {
                std::ptr::null()
            }
        }
        Err(_) => std::ptr::null(),
    }
}

/// Get all stored states as JSON
///
/// # Returns
/// JSON array: [{"trackId":1,"slotIndex":0,"uid":"VST3:...","size":1234},...]
#[unsafe(no_mangle)]
pub extern "C" fn plugin_state_get_all_json() -> *const c_char {
    match STATE_STORAGE.lock() {
        Ok(storage) => {
            let entries: Vec<String> = storage
                .iter()
                .map(|((track_id, slot_index), chunk)| {
                    format!(
                        r#"{{"trackId":{},"slotIndex":{},"uid":"{}","size":{},"preset":{}}}"#,
                        track_id,
                        slot_index,
                        chunk.plugin_uid.to_string().replace('"', r#"\""#),
                        chunk.state_data.len(),
                        chunk
                            .preset_name
                            .as_ref()
                            .map(|n| format!(r#""{}""#, n.replace('"', r#"\""#)))
                            .unwrap_or_else(|| "null".to_string())
                    )
                })
                .collect();

            return_string(&format!("[{}]", entries.join(",")))
        }
        Err(_) => return_string("[]"),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn test_store_and_get() {
        // Clear first
        plugin_state_clear_all();

        let uid = CString::new("58E595CC2C1242FB8E32F4C9D39C5F42").unwrap();
        let preset = CString::new("My Preset").unwrap();
        let state_data = vec![1u8, 2, 3, 4, 5];

        // Store
        let result = plugin_state_store(
            1,
            0,
            0, // track 1, slot 0, VST3
            uid.as_ptr(),
            state_data.as_ptr(),
            state_data.len(),
            preset.as_ptr(),
        );
        assert_eq!(result, 1);

        // Check count
        assert_eq!(plugin_state_count(), 1);

        // Get size
        let size = plugin_state_get_size(1, 0);
        assert_eq!(size, 5);

        // Get data
        let mut buffer = vec![0u8; 10];
        let mut out_len = 0usize;
        let result = plugin_state_get(1, 0, buffer.as_mut_ptr(), buffer.len(), &mut out_len);
        assert_eq!(result, 1);
        assert_eq!(out_len, 5);
        assert_eq!(&buffer[..5], &[1, 2, 3, 4, 5]);

        // Remove
        let result = plugin_state_remove(1, 0);
        assert_eq!(result, 1);
        assert_eq!(plugin_state_count(), 0);
    }
}

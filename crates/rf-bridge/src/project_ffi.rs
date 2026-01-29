// Project FFI — C ABI Functions for Flutter
//
// Project management: new, save, load, metadata, recent projects
// Uses the api_project module internally

#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::ffi::{c_char, CStr, CString};

use crate::api_project;

// ============================================================================
// PROJECT LIFECYCLE
// ============================================================================

/// Create a new project with the given name
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_new(name: *const c_char) -> i32 {
    let name_str = if name.is_null() {
        "Untitled".to_string()
    } else {
        unsafe {
            match CStr::from_ptr(name).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => "Untitled".to_string(),
            }
        }
    };

    if api_project::project_new(name_str) {
        1
    } else {
        0
    }
}

/// Save project to file
/// path: File path to save to
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_save(path: *const c_char) -> i32 {
    if path.is_null() {
        return 0;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    match api_project::project_save_sync(path_str) {
        Ok(()) => 1,
        Err(e) => {
            log::error!("Project save failed: {}", e);
            0
        }
    }
}

/// Load project from file
/// path: File path to load from
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_load(path: *const c_char) -> i32 {
    if path.is_null() {
        return 0;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    match api_project::project_load_sync(path_str) {
        Ok(()) => 1,
        Err(e) => {
            log::error!("Project load failed: {}", e);
            0
        }
    }
}

// ============================================================================
// PROJECT METADATA
// ============================================================================

/// Set project name
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_set_name(name: *const c_char) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe {
        match CStr::from_ptr(name).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    if api_project::project_set_name(name_str) {
        1
    } else {
        0
    }
}

/// Get project name
/// out_name: Buffer to write name to
/// max_len: Maximum buffer length
/// Returns: Length of name, or -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn project_get_name(out_name: *mut c_char, max_len: u32) -> i32 {
    if out_name.is_null() || max_len == 0 {
        return -1;
    }

    let name = match api_project::project_get_name() {
        Some(n) => n,
        None => return -1,
    };

    let bytes = name.as_bytes();
    let copy_len = bytes.len().min(max_len as usize - 1);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_name as *mut u8, copy_len);
        *out_name.add(copy_len) = 0;
    }

    copy_len as i32
}

/// Set project author
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_set_author(author: *const c_char) -> i32 {
    let author_str = if author.is_null() {
        String::new()
    } else {
        unsafe {
            match CStr::from_ptr(author).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => String::new(),
            }
        }
    };

    if api_project::project_set_author(author_str) {
        1
    } else {
        0
    }
}

/// Set project description
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_set_description(description: *const c_char) -> i32 {
    let desc_str = if description.is_null() {
        String::new()
    } else {
        unsafe {
            match CStr::from_ptr(description).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => String::new(),
            }
        }
    };

    if api_project::project_set_description(desc_str) {
        1
    } else {
        0
    }
}

// ============================================================================
// PROJECT SETTINGS
// ============================================================================

/// Set project tempo (BPM)
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_set_tempo(tempo: f64) -> i32 {
    if api_project::project_set_tempo(tempo) {
        1
    } else {
        0
    }
}

/// Get project tempo
/// Returns: Tempo in BPM, or -1.0 if engine not initialized
#[unsafe(no_mangle)]
pub extern "C" fn project_get_tempo() -> f64 {
    api_project::project_get_tempo().unwrap_or(-1.0)
}

/// Set project sample rate
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_set_sample_rate(sample_rate: u32) -> i32 {
    if api_project::project_set_sample_rate(sample_rate) {
        1
    } else {
        0
    }
}

/// Set project time signature
/// Returns: 1 = success, 0 = failure
#[unsafe(no_mangle)]
pub extern "C" fn project_set_time_signature(numerator: u8, denominator: u8) -> i32 {
    if api_project::project_set_time_signature(numerator, denominator) {
        1
    } else {
        0
    }
}

// ============================================================================
// PROJECT STATE
// ============================================================================

/// Check if project has unsaved changes
/// Returns: 1 = dirty, 0 = clean
#[unsafe(no_mangle)]
pub extern "C" fn project_is_modified() -> i32 {
    if api_project::project_is_modified() {
        1
    } else {
        0
    }
}

/// Mark project as dirty (has unsaved changes)
#[unsafe(no_mangle)]
pub extern "C" fn project_mark_dirty() {
    api_project::project_mark_dirty();
}

/// Mark project as clean (just saved)
#[unsafe(no_mangle)]
pub extern "C" fn project_mark_clean() {
    api_project::project_mark_clean();
}

/// Set project file path
#[unsafe(no_mangle)]
pub extern "C" fn project_set_file_path(path: *const c_char) {
    let path_opt = if path.is_null() {
        None
    } else {
        unsafe {
            CStr::from_ptr(path)
                .to_str()
                .ok()
                .map(|s| s.to_string())
        }
    };

    api_project::project_set_file_path(path_opt);
}

/// Get project file path
/// out_path: Buffer to write path to
/// max_len: Maximum buffer length
/// Returns: Length of path, or -1 if no path set
#[unsafe(no_mangle)]
pub extern "C" fn project_get_file_path(out_path: *mut c_char, max_len: u32) -> i32 {
    if out_path.is_null() || max_len == 0 {
        return -1;
    }

    let path = match api_project::project_get_file_path() {
        Some(p) => p,
        None => return -1,
    };

    let bytes = path.as_bytes();
    let copy_len = bytes.len().min(max_len as usize - 1);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_path as *mut u8, copy_len);
        *out_path.add(copy_len) = 0;
    }

    copy_len as i32
}

// ============================================================================
// PROJECT INFO (JSON)
// ============================================================================

/// Get full project info as JSON
/// Returns: JSON string (caller must free with project_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn project_get_info_json() -> *mut c_char {
    let info = match api_project::project_get_info() {
        Some(i) => i,
        None => return std::ptr::null_mut(),
    };

    let json = serde_json::json!({
        "name": info.name,
        "author": info.author,
        "description": info.description,
        "created_at": info.created_at,
        "modified_at": info.modified_at,
        "duration_sec": info.duration_sec,
        "sample_rate": info.sample_rate,
        "tempo": info.tempo,
        "time_sig_num": info.time_sig_num,
        "time_sig_denom": info.time_sig_denom,
        "track_count": info.track_count,
        "bus_count": info.bus_count,
        "is_modified": info.is_modified,
        "file_path": info.file_path
    });

    match CString::new(json.to_string()) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a string returned by project_get_info_json
#[unsafe(no_mangle)]
pub extern "C" fn project_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

// ============================================================================
// RECENT PROJECTS
// ============================================================================

/// Get count of recent projects
#[unsafe(no_mangle)]
pub extern "C" fn project_recent_count() -> u32 {
    api_project::project_get_recent().len() as u32
}

/// Get recent project path by index
/// out_path: Buffer to write path to
/// max_len: Maximum buffer length
/// Returns: Length of path, or -1 if index out of bounds
#[unsafe(no_mangle)]
pub extern "C" fn project_recent_get(index: u32, out_path: *mut c_char, max_len: u32) -> i32 {
    if out_path.is_null() || max_len == 0 {
        return -1;
    }

    let recent = api_project::project_get_recent();
    if (index as usize) >= recent.len() {
        return -1;
    }

    let path = &recent[index as usize];
    let bytes = path.as_bytes();
    let copy_len = bytes.len().min(max_len as usize - 1);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_path as *mut u8, copy_len);
        *out_path.add(copy_len) = 0;
    }

    copy_len as i32
}

/// Add project to recent list
#[unsafe(no_mangle)]
pub extern "C" fn project_recent_add(path: *const c_char) -> i32 {
    if path.is_null() {
        return 0;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    api_project::project_add_recent(path_str);
    1
}

/// Remove project from recent list
#[unsafe(no_mangle)]
pub extern "C" fn project_recent_remove(path: *const c_char) -> i32 {
    if path.is_null() {
        return 0;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    api_project::project_remove_recent(path_str);
    1
}

/// Clear recent projects list
#[unsafe(no_mangle)]
pub extern "C" fn project_recent_clear() {
    api_project::project_clear_recent();
}

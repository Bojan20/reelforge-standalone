// Autosave FFI — C ABI Functions for Flutter
//
// Simplified autosave system for Flutter integration

// Allow raw pointer args in extern "C" FFI functions
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::ffi::c_char;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::RwLock;

// ============================================================================
// GLOBAL STATE
// ============================================================================

lazy_static::lazy_static! {
    /// Autosave directory
    static ref AUTOSAVE_DIR: RwLock<PathBuf> = RwLock::new(default_autosave_dir());

    /// Current project name
    static ref PROJECT_NAME: RwLock<String> = RwLock::new(String::from("Untitled"));

    /// Recent projects list
    static ref RECENT_PROJECTS: RwLock<Vec<PathBuf>> = RwLock::new(Vec::new());
}

/// Autosave enabled flag
static AUTOSAVE_ENABLED: AtomicBool = AtomicBool::new(true);
/// Autosave interval in seconds
static AUTOSAVE_INTERVAL: AtomicU64 = AtomicU64::new(60);
/// Backup count
static BACKUP_COUNT: AtomicU64 = AtomicU64::new(5);
/// Change counter for dirty state
static CHANGE_COUNT: AtomicU64 = AtomicU64::new(0);
/// Last saved change count
static LAST_SAVED_CHANGE: AtomicU64 = AtomicU64::new(0);
/// Last save timestamp
static LAST_SAVE_TIME: AtomicU64 = AtomicU64::new(0);

fn default_autosave_dir() -> PathBuf {
    dirs::data_local_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("FluxForge Studio")
        .join("Autosave")
}

fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

// ============================================================================
// INITIALIZATION
// ============================================================================

/// Initialize autosave system with project name
#[unsafe(no_mangle)]
pub extern "C" fn autosave_init(project_name: *const c_char) -> i32 {
    let name = if project_name.is_null() {
        "Untitled".to_string()
    } else {
        unsafe {
            match std::ffi::CStr::from_ptr(project_name).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => "Untitled".to_string(),
            }
        }
    };

    *PROJECT_NAME.write() = name.clone();

    // Create autosave directory if needed
    let dir = AUTOSAVE_DIR.read().clone();
    if !dir.exists() {
        let _ = fs::create_dir_all(&dir);
    }

    log::info!("Autosave initialized for project: {}", name);
    1
}

/// Shutdown autosave system
#[unsafe(no_mangle)]
pub extern "C" fn autosave_shutdown() {
    log::info!("Autosave shutdown");
}

// ============================================================================
// CONFIGURATION
// ============================================================================

/// Set autosave enabled state
#[unsafe(no_mangle)]
pub extern "C" fn autosave_set_enabled(enabled: i32) {
    AUTOSAVE_ENABLED.store(enabled != 0, Ordering::Relaxed);
}

/// Check if autosave is enabled
#[unsafe(no_mangle)]
pub extern "C" fn autosave_is_enabled() -> i32 {
    if AUTOSAVE_ENABLED.load(Ordering::Relaxed) {
        1
    } else {
        0
    }
}

/// Set autosave interval in seconds
#[unsafe(no_mangle)]
pub extern "C" fn autosave_set_interval(interval_secs: u32) {
    AUTOSAVE_INTERVAL.store(interval_secs as u64, Ordering::Relaxed);
}

/// Get autosave interval in seconds
#[unsafe(no_mangle)]
pub extern "C" fn autosave_get_interval() -> u32 {
    AUTOSAVE_INTERVAL.load(Ordering::Relaxed) as u32
}

/// Set backup count (how many autosaves to keep)
#[unsafe(no_mangle)]
pub extern "C" fn autosave_set_backup_count(count: u32) {
    BACKUP_COUNT.store(count as u64, Ordering::Relaxed);
}

/// Get backup count
#[unsafe(no_mangle)]
pub extern "C" fn autosave_get_backup_count() -> u32 {
    BACKUP_COUNT.load(Ordering::Relaxed) as u32
}

// ============================================================================
// DIRTY STATE
// ============================================================================

/// Mark project as having unsaved changes
#[unsafe(no_mangle)]
pub extern "C" fn autosave_mark_dirty() {
    CHANGE_COUNT.fetch_add(1, Ordering::Relaxed);
}

/// Mark project as saved (clean)
#[unsafe(no_mangle)]
pub extern "C" fn autosave_mark_clean() {
    LAST_SAVED_CHANGE.store(CHANGE_COUNT.load(Ordering::Relaxed), Ordering::Relaxed);
}

/// Check if project has unsaved changes
#[unsafe(no_mangle)]
pub extern "C" fn autosave_is_dirty() -> i32 {
    let current = CHANGE_COUNT.load(Ordering::Relaxed);
    let saved = LAST_SAVED_CHANGE.load(Ordering::Relaxed);
    if current != saved { 1 } else { 0 }
}

// ============================================================================
// AUTOSAVE OPERATIONS
// ============================================================================

/// Check if autosave should run now
#[unsafe(no_mangle)]
pub extern "C" fn autosave_should_save() -> i32 {
    if !AUTOSAVE_ENABLED.load(Ordering::Relaxed) {
        return 0;
    }

    // Check if dirty
    if autosave_is_dirty() == 0 {
        return 0;
    }

    // Check interval
    let now = current_timestamp();
    let last = LAST_SAVE_TIME.load(Ordering::Relaxed);
    let interval = AUTOSAVE_INTERVAL.load(Ordering::Relaxed);

    if now.saturating_sub(last) >= interval {
        1
    } else {
        0
    }
}

/// Perform autosave with project data
/// project_data: JSON string of project state
/// Returns: 1 = success, 0 = skipped (no changes), -1 = error
#[unsafe(no_mangle)]
pub extern "C" fn autosave_now(project_data: *const c_char) -> i32 {
    if project_data.is_null() {
        return -1;
    }

    let data = unsafe {
        match std::ffi::CStr::from_ptr(project_data).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    let dir = AUTOSAVE_DIR.read().clone();
    if !dir.exists() && fs::create_dir_all(&dir).is_err() {
        return -1;
    }

    // Generate filename with timestamp
    let project_name = PROJECT_NAME.read().clone();
    let timestamp = current_timestamp();
    let filename = format!(
        "{}_autosave_{}.json",
        sanitize_filename(&project_name),
        timestamp
    );
    let path = dir.join(&filename);

    // Write autosave
    match fs::File::create(&path) {
        Ok(mut file) => {
            if file.write_all(data.as_bytes()).is_err() {
                return -1;
            }
        }
        Err(_) => return -1,
    }

    // Update state
    LAST_SAVE_TIME.store(timestamp, Ordering::Relaxed);
    autosave_mark_clean();

    // Rotate old backups
    rotate_backups(&dir, &project_name);

    log::info!("Autosave completed: {:?}", path);
    1
}

fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect::<String>()
        .chars()
        .take(200)
        .collect()
}

fn rotate_backups(dir: &PathBuf, project_name: &str) {
    let prefix = format!("{}_autosave_", sanitize_filename(project_name));
    let max_backups = BACKUP_COUNT.load(Ordering::Relaxed) as usize;

    // Collect autosave files for this project
    let mut autosaves: Vec<_> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with(&prefix) && name.ends_with(".json") {
                Some(entry.path())
            } else {
                None
            }
        })
        .collect();

    // Sort by modification time (newest first)
    autosaves.sort_by(|a, b| {
        let a_time = fs::metadata(a).and_then(|m| m.modified()).ok();
        let b_time = fs::metadata(b).and_then(|m| m.modified()).ok();
        b_time.cmp(&a_time)
    });

    // Delete old backups
    for path in autosaves.into_iter().skip(max_backups) {
        let _ = fs::remove_file(path);
    }
}

// ============================================================================
// RECOVERY
// ============================================================================

/// Get count of available autosave backups
#[unsafe(no_mangle)]
pub extern "C" fn autosave_backup_count() -> u32 {
    let dir = AUTOSAVE_DIR.read().clone();
    let project_name = PROJECT_NAME.read().clone();
    let prefix = format!("{}_autosave_", sanitize_filename(&project_name));

    fs::read_dir(&dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            name.starts_with(&prefix) && name.ends_with(".json")
        })
        .count() as u32
}

/// Get path to latest autosave backup
#[unsafe(no_mangle)]
pub extern "C" fn autosave_latest_path(out_path: *mut c_char, max_len: u32) -> i32 {
    if out_path.is_null() || max_len == 0 {
        return -1;
    }

    let dir = AUTOSAVE_DIR.read().clone();
    let project_name = PROJECT_NAME.read().clone();
    let prefix = format!("{}_autosave_", sanitize_filename(&project_name));

    // Find newest autosave
    let mut autosaves: Vec<_> = fs::read_dir(&dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with(&prefix) && name.ends_with(".json") {
                Some(entry.path())
            } else {
                None
            }
        })
        .collect();

    autosaves.sort_by(|a, b| {
        let a_time = fs::metadata(a).and_then(|m| m.modified()).ok();
        let b_time = fs::metadata(b).and_then(|m| m.modified()).ok();
        b_time.cmp(&a_time)
    });

    if let Some(latest) = autosaves.first() {
        let path_str = latest.to_string_lossy();
        let bytes = path_str.as_bytes();
        let copy_len = bytes.len().min(max_len as usize - 1);

        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_path as *mut u8, copy_len);
            *out_path.add(copy_len) = 0;
        }

        return copy_len as i32;
    }

    -1
}

/// Clear all autosave backups for current project
#[unsafe(no_mangle)]
pub extern "C" fn autosave_clear_backups() {
    let dir = AUTOSAVE_DIR.read().clone();
    let project_name = PROJECT_NAME.read().clone();
    let prefix = format!("{}_autosave_", sanitize_filename(&project_name));

    let count = fs::read_dir(&dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            name.starts_with(&prefix) && name.ends_with(".json")
        })
        .filter_map(|entry| fs::remove_file(entry.path()).ok())
        .count();

    log::info!("Cleared {} autosave backups", count);
}

// ============================================================================
// RECENT PROJECTS
// ============================================================================

/// Add project to recent list
#[unsafe(no_mangle)]
pub extern "C" fn recent_projects_add(path: *const c_char) -> i32 {
    if path.is_null() {
        return -1;
    }

    let path_str = unsafe {
        match std::ffi::CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    let path_buf = PathBuf::from(path_str);
    let mut recent = RECENT_PROJECTS.write();

    // Remove if already exists (to move to front)
    recent.retain(|p| p != &path_buf);

    // Add to front
    recent.insert(0, path_buf);

    // Keep max 20
    if recent.len() > 20 {
        recent.truncate(20);
    }

    1
}

/// Get recent project count
#[unsafe(no_mangle)]
pub extern "C" fn recent_projects_count() -> u32 {
    RECENT_PROJECTS.read().len() as u32
}

/// Get recent project path by index
#[unsafe(no_mangle)]
pub extern "C" fn recent_projects_get(index: u32, out_path: *mut c_char, max_len: u32) -> i32 {
    if out_path.is_null() || max_len == 0 {
        return -1;
    }

    let recent = RECENT_PROJECTS.read();
    if (index as usize) >= recent.len() {
        return -1;
    }

    let path = &recent[index as usize];
    let path_str = path.to_string_lossy();
    let bytes = path_str.as_bytes();
    let copy_len = bytes.len().min(max_len as usize - 1);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_path as *mut u8, copy_len);
        *out_path.add(copy_len) = 0;
    }

    copy_len as i32
}

/// Remove project from recent list
#[unsafe(no_mangle)]
pub extern "C" fn recent_projects_remove(path: *const c_char) -> i32 {
    if path.is_null() {
        return -1;
    }

    let path_str = unsafe {
        match std::ffi::CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    let path_buf = PathBuf::from(path_str);
    let mut recent = RECENT_PROJECTS.write();
    recent.retain(|p| p != &path_buf);

    1
}

/// Clear all recent projects
#[unsafe(no_mangle)]
pub extern "C" fn recent_projects_clear() {
    RECENT_PROJECTS.write().clear();
}

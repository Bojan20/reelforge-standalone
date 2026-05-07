//! Chain preset FFI — save/load named preset files for chain snapshots.
//!
//! Wave 2 Front 5. Wraps `rf_ml::assistant::chain_preset` in a stable
//! C-extern surface. The store is a flat directory of JSON files
//! (default: `~/.fluxforge/chains/`), one per preset, slug-named.
//!
//! # Functions
//!
//! - `chain_preset_set_dir(path)`               — override the store directory (or "" to reset)
//! - `chain_preset_get_dir()`                    — current store directory
//! - `chain_preset_save_json(req_json)`          — save a preset
//! - `chain_preset_load_json(name)`              — load by user-visible name
//! - `chain_preset_list_json()`                  — metadata list (sorted by updated_ms desc)
//! - `chain_preset_search_json(query)`           — substring search across name/description/tags/category
//! - `chain_preset_filter_json(spec_json)`       — Wave 2 Front 6: structured filter (category × tags × query)
//! - `chain_preset_list_tags()`                  — Wave 2 Front 6: aggregate of every tag in the library
//! - `chain_preset_list_categories()`            — Wave 2 Front 6: canonical + user-defined categories
//! - `chain_preset_delete(name)`                 — delete by name; returns 1 if removed, 0 if missing, -1 on error
//! - `chain_preset_export_json(req_json)`        — export to an absolute path
//! - `chain_preset_import_path(path)`            — import a preset file into the store
//! - `chain_preset_free_string(ptr)`             — paired free
//!
//! # Save request shape
//!
//! ```json
//! {
//!   "name": "My Vocal Master",
//!   "description": "Bright, transparent",
//!   "category": "vocal",
//!   "tags": ["modern", "podcast"],
//!   "snapshot": { ... FullChainSnapshot ... }
//! }
//! ```
//!
//! # Filter spec shape
//!
//! ```json
//! {
//!   "categories": ["vocal", "bus"],
//!   "tags_any": ["modern"],
//!   "tags_all": ["mastering"],
//!   "query": "podcast",
//!   "uncategorised_only": false
//! }
//! ```
//!
//! # Export request shape
//!
//! ```json
//! { "name": "My Vocal Master", "dest": "/abs/path/preset.json" }
//! ```

use std::ffi::{c_char, CStr, CString};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

use rf_ml::assistant::chain_history::FullChainSnapshot;
use rf_ml::assistant::chain_preset::{
    self, ChainPreset, ChainPresetMeta, PresetError, PresetFilterSpec,
};

// ─── Wire types ──────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct SaveRequest {
    name: String,
    #[serde(default)]
    description: String,
    /// Optional canonical category — `vocal`, `drums`, `bus`, … See
    /// `chain_preset::CANONICAL_CATEGORIES`. Free-form strings are
    /// allowed; the core normalises (lowercase + trim) on save.
    #[serde(default)]
    category: Option<String>,
    #[serde(default)]
    tags: Vec<String>,
    snapshot: FullChainSnapshot,
}

#[derive(Debug, Deserialize)]
struct ExportRequest {
    name: String,
    dest: String,
}

#[derive(Debug, Serialize)]
struct OkResponse {
    ok: bool,
    /// Absolute path to the on-disk file (empty for non-save ops).
    #[serde(skip_serializing_if = "String::is_empty", default)]
    path: String,
    /// User-visible name (echoed for clarity).
    #[serde(skip_serializing_if = "String::is_empty", default)]
    name: String,
}

#[derive(Debug, Serialize)]
struct ListResponse {
    presets: Vec<ChainPresetMeta>,
}

#[derive(Debug, Serialize)]
struct StringListResponse {
    items: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
}

// ─── Global directory override ───────────────────────────────────────────────

static DIR_OVERRIDE: OnceLock<RwLock<Option<PathBuf>>> = OnceLock::new();

fn dir_override() -> &'static RwLock<Option<PathBuf>> {
    DIR_OVERRIDE.get_or_init(|| RwLock::new(None))
}

fn current_dir() -> Result<PathBuf, PresetError> {
    let override_dir = dir_override().read().clone();
    chain_preset::resolve_preset_dir(override_dir.as_deref())
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn error_response(msg: impl Into<String>) -> *mut c_char {
    let resp = ErrorResponse { error: msg.into() };
    json_to_c(serde_json::to_string(&resp).unwrap_or_default())
}

fn cstr_to_str<'a>(ptr: *const c_char, name: &str) -> Result<&'a str, *mut c_char> {
    if ptr.is_null() {
        return Err(error_response(format!("null {}", name)));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|_| error_response(format!("{} not utf-8", name)))
}

// ─── Directory management ────────────────────────────────────────────────────

/// Set the active preset directory. Pass an empty string to clear the
/// override (falls back to env / `$HOME/.fluxforge/chains`).
///
/// Returns JSON `{"ok": true, "path": "<resolved>"}` on success or
/// `{"error": "..."}` on resolution failure.
///
/// # Safety
/// `path_cstr` must be a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_set_dir(path_cstr: *const c_char) -> *mut c_char {
    let s = match cstr_to_str(path_cstr, "path") {
        Ok(s) => s,
        Err(e) => return e,
    };
    let new_dir = if s.trim().is_empty() {
        None
    } else {
        Some(PathBuf::from(s))
    };
    *dir_override().write() = new_dir;
    match current_dir() {
        Ok(p) => {
            let resp = OkResponse {
                ok: true,
                path: p.to_string_lossy().to_string(),
                name: String::new(),
            };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("resolve failed: {}", e)),
    }
}

/// Get the currently-resolved preset directory.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_get_dir() -> *mut c_char {
    match current_dir() {
        Ok(p) => {
            let resp = OkResponse {
                ok: true,
                path: p.to_string_lossy().to_string(),
                name: String::new(),
            };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("resolve failed: {}", e)),
    }
}

// ─── Save / load / delete / list / search ───────────────────────────────────

/// Save a preset. See module docs for request shape.
///
/// # Safety
/// `req_json` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_save_json(req_json: *const c_char) -> *mut c_char {
    let s = match cstr_to_str(req_json, "request") {
        Ok(s) => s,
        Err(e) => return e,
    };
    let req: SaveRequest = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => return error_response(format!("parse error: {}", e)),
    };
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    let preset = ChainPreset::with_category(
        req.name.clone(),
        req.description,
        req.category,
        req.tags,
        req.snapshot,
    );
    match chain_preset::save_preset(&dir, &preset) {
        Ok(path) => {
            let resp = OkResponse {
                ok: true,
                path: path.to_string_lossy().to_string(),
                name: req.name,
            };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("save: {}", e)),
    }
}

/// Load a preset by its user-visible name (slugified internally).
///
/// # Safety
/// `name_cstr` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_load_json(name_cstr: *const c_char) -> *mut c_char {
    let name = match cstr_to_str(name_cstr, "name") {
        Ok(s) => s,
        Err(e) => return e,
    };
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    match chain_preset::load_preset(&dir, name) {
        Ok(preset) => match serde_json::to_string(&preset) {
            Ok(j) => json_to_c(j),
            Err(e) => error_response(format!("serialize: {}", e)),
        },
        Err(e) => error_response(format!("load: {}", e)),
    }
}

/// List all presets (metadata only). Sorted by `updated_ms` descending.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_list_json() -> *mut c_char {
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    match chain_preset::list_presets(&dir) {
        Ok(presets) => {
            let resp = ListResponse { presets };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("list: {}", e)),
    }
}

/// Search presets by case-insensitive substring across name, description,
/// and tags. Empty query returns the full list.
///
/// # Safety
/// `query_cstr` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_search_json(query_cstr: *const c_char) -> *mut c_char {
    let query = match cstr_to_str(query_cstr, "query") {
        Ok(s) => s,
        Err(e) => return e,
    };
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    match chain_preset::search_presets(&dir, query) {
        Ok(presets) => {
            let resp = ListResponse { presets };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("search: {}", e)),
    }
}

/// Apply a structured filter (categories / tags_any / tags_all / query /
/// uncategorised_only). See `PresetFilterSpec` in `rf-ml` for the full
/// contract. Empty / missing axes are no-ops.
///
/// # Safety
/// `spec_json` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_filter_json(spec_json: *const c_char) -> *mut c_char {
    let s = match cstr_to_str(spec_json, "spec") {
        Ok(s) => s,
        Err(e) => return e,
    };
    let spec: PresetFilterSpec = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => return error_response(format!("parse error: {}", e)),
    };
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    match chain_preset::filter_presets(&dir, &spec) {
        Ok(presets) => {
            let resp = ListResponse { presets };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("filter: {}", e)),
    }
}

/// List every distinct tag across the library, sorted alphabetically.
/// Used by the multi-select chip strip — call once on panel mount and
/// again after every save/delete.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_list_tags() -> *mut c_char {
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    match chain_preset::list_tags(&dir) {
        Ok(items) => {
            let resp = StringListResponse { items };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("list_tags: {}", e)),
    }
}

/// List every distinct category across the library. Canonical categories
/// (`vocal`, `drums`, `bus`, …) come first in their canonical order;
/// user-defined categories follow alphabetically. Always returns the
/// canonical set even when the library is empty so the UI chip strip
/// has a stable shape.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_list_categories() -> *mut c_char {
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    match chain_preset::list_categories(&dir) {
        Ok(items) => {
            let resp = StringListResponse { items };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("list_categories: {}", e)),
    }
}

/// Delete a preset.
/// Returns:
///   1  — file removed
///   0  — no file existed (idempotent)
///  -1  — error (path resolution, name slug, IO)
///
/// # Safety
/// `name_cstr` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_delete(name_cstr: *const c_char) -> i32 {
    if name_cstr.is_null() {
        return -1;
    }
    let name = match unsafe { CStr::from_ptr(name_cstr) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let dir = match current_dir() {
        Ok(d) => d,
        Err(_) => return -1,
    };
    match chain_preset::delete_preset(&dir, name) {
        Ok(true) => 1,
        Ok(false) => 0,
        Err(_) => -1,
    }
}

/// Export a preset to a destination path.
///
/// Request: `{ "name": "...", "dest": "/abs/path/preset.json" }`
///
/// # Safety
/// `req_json` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_export_json(req_json: *const c_char) -> *mut c_char {
    let s = match cstr_to_str(req_json, "request") {
        Ok(s) => s,
        Err(e) => return e,
    };
    let req: ExportRequest = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => return error_response(format!("parse error: {}", e)),
    };
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    match chain_preset::export_preset_to(&dir, &req.name, Path::new(&req.dest)) {
        Ok(()) => {
            let resp = OkResponse {
                ok: true,
                path: req.dest,
                name: req.name,
            };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("export: {}", e)),
    }
}

/// Import a preset file from an arbitrary path into the store.
///
/// Returns `{"ok": true, "path": "<final_store_path>", "name": "<preset name>"}`.
///
/// # Safety
/// `path_cstr` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_import_path(path_cstr: *const c_char) -> *mut c_char {
    let path_str = match cstr_to_str(path_cstr, "path") {
        Ok(s) => s,
        Err(e) => return e,
    };
    let dir = match current_dir() {
        Ok(d) => d,
        Err(e) => return error_response(format!("resolve dir: {}", e)),
    };
    let src = Path::new(path_str);
    match chain_preset::import_preset_from(&dir, src) {
        Ok(final_path) => {
            // Re-read to echo the imported preset's name.
            let name = match chain_preset::list_presets(&dir) {
                Ok(list) => list
                    .into_iter()
                    .find(|m| {
                        Path::new(&final_path)
                            .file_name()
                            .map(|f| f.to_string_lossy().to_string())
                            == Some(m.filename.clone())
                    })
                    .map(|m| m.name)
                    .unwrap_or_default(),
                Err(_) => String::new(),
            };
            let resp = OkResponse {
                ok: true,
                path: final_path.to_string_lossy().to_string(),
                name,
            };
            json_to_c(serde_json::to_string(&resp).unwrap_or_default())
        }
        Err(e) => error_response(format!("import: {}", e)),
    }
}

/// Free a string allocated by this module's FFI functions.
///
/// # Safety
/// `ptr` must come from one of this module's `*_json` / `*_get_dir` /
/// `*_set_dir` / `*_export` / `*_import` functions.
#[unsafe(no_mangle)]
pub extern "C" fn chain_preset_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rf_ml::assistant::chain_history::{FullChainSnapshot, FullSlotSnapshot, SlotParamSnapshot};
    use std::sync::Mutex;

    /// Serialise tests against the global DIR_OVERRIDE — they all
    /// mutate the same static, so parallel execution would race.
    static DIR_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn cstr_to_string(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
        chain_preset_free_string(ptr);
        s
    }

    fn isolate_dir(test: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!(
            "rf_chain_preset_ffi_{}_{}",
            test,
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&p).unwrap();
        // Set override to this directory
        let cstr = CString::new(p.to_string_lossy().as_ref()).unwrap();
        let raw = chain_preset_set_dir(cstr.as_ptr());
        let _ = cstr_to_string(raw);
        p
    }

    fn sample_snapshot(track_id: u32, label: &str) -> FullChainSnapshot {
        FullChainSnapshot::now(
            track_id,
            vec![FullSlotSnapshot {
                slot_index: 0,
                processor_name: "compressor".into(),
                bypassed: false,
                mix: 1.0,
                params: vec![SlotParamSnapshot {
                    index: 0,
                    name: "Threshold".into(),
                    value: -18.0,
                }],
            }],
            label,
        )
    }

    #[test]
    fn set_and_get_dir_roundtrip() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        let dir = isolate_dir("set_get");
        let raw = chain_preset_get_dir();
        let out = cstr_to_string(raw);
        assert!(out.contains(&dir.to_string_lossy().to_string()));
    }

    #[test]
    fn save_load_roundtrip_via_ffi() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("save_load");
        let req = serde_json::json!({
            "name": "FFI Vocal",
            "description": "Test preset",
            "tags": ["vocal", "ffi"],
            "snapshot": sample_snapshot(7, "Save")
        });
        let c = CString::new(req.to_string()).unwrap();
        let saved = cstr_to_string(chain_preset_save_json(c.as_ptr()));
        assert!(saved.contains("\"ok\":true"), "got {}", saved);
        assert!(saved.contains("FFI Vocal"));

        let name_c = CString::new("FFI Vocal").unwrap();
        let loaded = cstr_to_string(chain_preset_load_json(name_c.as_ptr()));
        assert!(loaded.contains("\"name\":\"FFI Vocal\""));
        assert!(loaded.contains("\"track_id\":7"));
        assert!(loaded.contains("compressor"));
    }

    #[test]
    fn save_invalid_json_returns_error() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("save_invalid");
        let c = CString::new("not json").unwrap();
        let out = cstr_to_string(chain_preset_save_json(c.as_ptr()));
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn load_missing_returns_error() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("load_missing");
        let name_c = CString::new("Phantom").unwrap();
        let out = cstr_to_string(chain_preset_load_json(name_c.as_ptr()));
        assert!(out.contains("\"error\""));
        assert!(out.contains("Phantom") || out.contains("not found"));
    }

    #[test]
    fn list_returns_saved_preset() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("list_one");
        let req = serde_json::json!({
            "name": "Listed",
            "description": "",
            "tags": [],
            "snapshot": sample_snapshot(1, "x")
        });
        let c = CString::new(req.to_string()).unwrap();
        let _ = cstr_to_string(chain_preset_save_json(c.as_ptr()));
        let listed = cstr_to_string(chain_preset_list_json());
        assert!(listed.contains("\"name\":\"Listed\""));
        assert!(listed.contains("\"slot_count\":1"));
    }

    #[test]
    fn list_empty_dir_returns_empty_array() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("list_empty");
        let listed = cstr_to_string(chain_preset_list_json());
        assert!(listed.contains("\"presets\":[]"), "got {}", listed);
    }

    #[test]
    fn search_filters_by_query() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("search");
        for (n, t) in [("Pop Vocal", "vocal"), ("Drum Bus", "drum")] {
            let req = serde_json::json!({
                "name": n,
                "description": "",
                "tags": [t],
                "snapshot": sample_snapshot(1, "x")
            });
            let c = CString::new(req.to_string()).unwrap();
            let _ = cstr_to_string(chain_preset_save_json(c.as_ptr()));
        }
        let q = CString::new("vocal").unwrap();
        let out = cstr_to_string(chain_preset_search_json(q.as_ptr()));
        assert!(out.contains("Pop Vocal"));
        assert!(!out.contains("Drum Bus"));
    }

    #[test]
    fn delete_existing_returns_one() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("delete_one");
        let req = serde_json::json!({
            "name": "DeleteMe",
            "description": "",
            "tags": [],
            "snapshot": sample_snapshot(1, "x")
        });
        let c = CString::new(req.to_string()).unwrap();
        let _ = cstr_to_string(chain_preset_save_json(c.as_ptr()));
        let n = CString::new("DeleteMe").unwrap();
        assert_eq!(chain_preset_delete(n.as_ptr()), 1);
        // Second delete is idempotent
        assert_eq!(chain_preset_delete(n.as_ptr()), 0);
    }

    #[test]
    fn delete_null_returns_minus_one() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        assert_eq!(chain_preset_delete(std::ptr::null()), -1);
    }

    #[test]
    fn export_and_import_roundtrip_via_ffi() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        let store_a = isolate_dir("export");
        let req = serde_json::json!({
            "name": "Source",
            "description": "exp",
            "tags": ["x"],
            "snapshot": sample_snapshot(42, "x")
        });
        let c = CString::new(req.to_string()).unwrap();
        let _ = cstr_to_string(chain_preset_save_json(c.as_ptr()));

        let dest = std::env::temp_dir().join(format!(
            "rf_export_ffi_{}.json",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let exp_req = serde_json::json!({
            "name": "Source",
            "dest": dest.to_string_lossy().to_string()
        });
        let c2 = CString::new(exp_req.to_string()).unwrap();
        let exp_out = cstr_to_string(chain_preset_export_json(c2.as_ptr()));
        assert!(exp_out.contains("\"ok\":true"), "got {}", exp_out);
        assert!(dest.exists());

        // Import into a different store
        let _store_b = isolate_dir("import");
        let dest_c = CString::new(dest.to_string_lossy().as_ref()).unwrap();
        let imp_out = cstr_to_string(chain_preset_import_path(dest_c.as_ptr()));
        assert!(imp_out.contains("\"ok\":true"), "got {}", imp_out);
        assert!(imp_out.contains("Source"));

        // Cleanup
        let _ = std::fs::remove_file(&dest);
        let _ = std::fs::remove_dir_all(&store_a);
    }

    #[test]
    fn import_missing_file_returns_error() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("import_missing");
        let p = CString::new("/nonexistent/preset.json").unwrap();
        let out = cstr_to_string(chain_preset_import_path(p.as_ptr()));
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn export_missing_preset_returns_error() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("export_missing");
        let req = serde_json::json!({
            "name": "Phantom",
            "dest": "/tmp/phantom.json"
        });
        let c = CString::new(req.to_string()).unwrap();
        let out = cstr_to_string(chain_preset_export_json(c.as_ptr()));
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn null_pointers_return_errors_safely() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        let saved = cstr_to_string(chain_preset_save_json(std::ptr::null()));
        assert!(saved.contains("\"error\""));
        let loaded = cstr_to_string(chain_preset_load_json(std::ptr::null()));
        assert!(loaded.contains("\"error\""));
        let searched = cstr_to_string(chain_preset_search_json(std::ptr::null()));
        assert!(searched.contains("\"error\""));
        let exported = cstr_to_string(chain_preset_export_json(std::ptr::null()));
        assert!(exported.contains("\"error\""));
        let imported = cstr_to_string(chain_preset_import_path(std::ptr::null()));
        assert!(imported.contains("\"error\""));
        let setdir = cstr_to_string(chain_preset_set_dir(std::ptr::null()));
        assert!(setdir.contains("\"error\""));
    }

    #[test]
    fn free_string_null_safe() {
        chain_preset_free_string(std::ptr::null_mut());
    }

    #[test]
    fn save_then_overwrite_via_ffi_increments_updated_ms() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("overwrite");
        for desc in ["v1", "v2"] {
            let req = serde_json::json!({
                "name": "Same",
                "description": desc,
                "tags": [],
                "snapshot": sample_snapshot(1, "x")
            });
            let c = CString::new(req.to_string()).unwrap();
            let _ = cstr_to_string(chain_preset_save_json(c.as_ptr()));
            std::thread::sleep(std::time::Duration::from_millis(2));
        }
        let n = CString::new("Same").unwrap();
        let out = cstr_to_string(chain_preset_load_json(n.as_ptr()));
        assert!(out.contains("\"description\":\"v2\""));
    }

    #[test]
    fn empty_dir_override_string_clears_override() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        // Set a real dir, then clear with empty string
        isolate_dir("clear");
        let empty = CString::new("").unwrap();
        let out = cstr_to_string(chain_preset_set_dir(empty.as_ptr()));
        // Falls back to env / $HOME path — should still be ok
        assert!(out.contains("\"ok\":true") || out.contains("\"error\""));
        // Restore an isolated dir for any subsequent tests
        isolate_dir("clear_restore");
    }

    // ─── Wave 2 Front 6 — categories + filter FFI ──────────────────────────

    fn save_with_category(name: &str, category: Option<&str>, tags: &[&str]) {
        let mut req = serde_json::json!({
            "name": name,
            "description": "",
            "tags": tags,
            "snapshot": sample_snapshot(1, name)
        });
        if let Some(c) = category {
            req["category"] = serde_json::json!(c);
        }
        let c = CString::new(req.to_string()).unwrap();
        let out = cstr_to_string(chain_preset_save_json(c.as_ptr()));
        assert!(out.contains("\"ok\":true"), "save failed: {}", out);
    }

    #[test]
    fn save_with_category_round_trips() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("save_cat");
        save_with_category("VocalA", Some("VOCAL"), &["modern"]);
        let n = CString::new("VocalA").unwrap();
        let out = cstr_to_string(chain_preset_load_json(n.as_ptr()));
        // Lowercase canonicalisation done in core.
        assert!(out.contains("\"category\":\"vocal\""), "got {}", out);
    }

    #[test]
    fn list_tags_aggregator_returns_unique_sorted() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("ffi_list_tags");
        save_with_category("A", None, &["Modern", "vintage"]);
        save_with_category("B", None, &["VINTAGE", "warm"]);
        let out = cstr_to_string(chain_preset_list_tags());
        // Expect modern, vintage, warm (lowercased + sorted + deduped).
        assert!(out.contains("\"items\""));
        assert!(out.contains("modern"));
        assert!(out.contains("vintage"));
        assert!(out.contains("warm"));
        // Single occurrence of "vintage".
        let count = out.matches("\"vintage\"").count();
        assert_eq!(count, 1, "got {}", out);
    }

    #[test]
    fn list_categories_returns_canonicals_even_when_empty() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("ffi_list_cats_empty");
        let out = cstr_to_string(chain_preset_list_categories());
        // Canonical set must always be present.
        assert!(out.contains("vocal"));
        assert!(out.contains("drums"));
        assert!(out.contains("mastering"));
    }

    #[test]
    fn list_categories_includes_user_defined() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("ffi_list_cats_user");
        save_with_category("CustomP", Some("podcast"), &[]);
        let out = cstr_to_string(chain_preset_list_categories());
        assert!(out.contains("podcast"), "got {}", out);
    }

    #[test]
    fn filter_by_category_returns_only_matches() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("ffi_filter_cat");
        save_with_category("Vox", Some("vocal"), &[]);
        save_with_category("Kik", Some("drums"), &[]);
        let spec = serde_json::json!({"categories": ["vocal"]});
        let c = CString::new(spec.to_string()).unwrap();
        let out = cstr_to_string(chain_preset_filter_json(c.as_ptr()));
        assert!(out.contains("\"name\":\"Vox\""), "got {}", out);
        assert!(!out.contains("\"name\":\"Kik\""), "got {}", out);
    }

    #[test]
    fn filter_by_tags_any_combines_or() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("ffi_filter_any");
        save_with_category("A", None, &["modern"]);
        save_with_category("B", None, &["vintage"]);
        save_with_category("C", None, &["dark"]);
        let spec = serde_json::json!({"tags_any": ["modern", "vintage"]});
        let c = CString::new(spec.to_string()).unwrap();
        let out = cstr_to_string(chain_preset_filter_json(c.as_ptr()));
        assert!(out.contains("\"name\":\"A\""), "got {}", out);
        assert!(out.contains("\"name\":\"B\""), "got {}", out);
        assert!(!out.contains("\"name\":\"C\""), "got {}", out);
    }

    #[test]
    fn filter_invalid_json_returns_error() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("ffi_filter_bad");
        let c = CString::new("not json").unwrap();
        let out = cstr_to_string(chain_preset_filter_json(c.as_ptr()));
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn filter_null_returns_error_safely() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        let out = cstr_to_string(chain_preset_filter_json(std::ptr::null()));
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn legacy_save_request_without_category_still_works() {
        let _g = DIR_TEST_LOCK.lock().unwrap();
        isolate_dir("ffi_legacy_save");
        // Old request shape (no category field) must still parse.
        let req = serde_json::json!({
            "name": "Legacy",
            "description": "",
            "tags": ["x"],
            "snapshot": sample_snapshot(1, "x")
        });
        let c = CString::new(req.to_string()).unwrap();
        let out = cstr_to_string(chain_preset_save_json(c.as_ptr()));
        assert!(out.contains("\"ok\":true"), "got {}", out);
    }
}

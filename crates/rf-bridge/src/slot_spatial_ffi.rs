//! Slot Spatial Audio™ FFI — Bridges rf-slot-spatial to Flutter.

use std::ffi::{c_char, CStr, CString};
use std::sync::OnceLock;

use parking_lot::RwLock;
use rf_slot_spatial::{SpatialSlotScene, SpatialAudioSource};

static SPATIAL_SCENE: OnceLock<RwLock<SpatialSlotScene>> = OnceLock::new();

fn scene() -> &'static RwLock<SpatialSlotScene> {
    SPATIAL_SCENE.get_or_init(|| RwLock::new(SpatialSlotScene::new("default")))
}

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Initialize spatial scene. Input: JSON {"game_id": "..."}.
#[unsafe(no_mangle)]
pub extern "C" fn slot_spatial_init(config_json: *const c_char) -> i32 {
    let game_id = if config_json.is_null() {
        "default".to_string()
    } else {
        let s = unsafe { CStr::from_ptr(config_json) };
        let v: serde_json::Value = s.to_str().ok()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!({}));
        v["game_id"].as_str().unwrap_or("default").to_string()
    };
    *scene().write() = SpatialSlotScene::new(game_id);
    0
}

/// Add or update a spatial audio source. Input: SpatialAudioSource JSON.
#[unsafe(no_mangle)]
pub extern "C" fn slot_spatial_add_source_json(source_json: *const c_char) -> i32 {
    if source_json.is_null() { return -1; }
    let s = match unsafe { CStr::from_ptr(source_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let source: SpatialAudioSource = match serde_json::from_str(s) {
        Ok(src) => src,
        Err(_) => return -1,
    };
    scene().write().add_source(source);
    0
}

/// Remove a spatial source by event_id.
#[unsafe(no_mangle)]
pub extern "C" fn slot_spatial_remove_source(event_id: *const c_char) -> i32 {
    if event_id.is_null() { return -1; }
    let id = match unsafe { CStr::from_ptr(event_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    scene().write().remove_source(id);
    0
}

/// Get current spatial scene as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn slot_spatial_get_scene_json() -> *mut c_char {
    let s = scene().read();
    json_to_c(serde_json::to_string(&*s).unwrap_or_else(|_| "{}".to_string()))
}

/// Get source count.
#[unsafe(no_mangle)]
pub extern "C" fn slot_spatial_source_count() -> u32 {
    scene().read().source_count() as u32
}

#[unsafe(no_mangle)]
pub extern "C" fn slot_spatial_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}

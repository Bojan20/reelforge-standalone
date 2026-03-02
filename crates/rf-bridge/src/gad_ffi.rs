//! GAD: Gameplay-Aware DAW FFI Bridge
//!
//! Exposes GAD project management, dual timeline, track metadata, and
//! Bake To Slot pipeline via C FFI.

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::ffi::{CStr, CString, c_char};
use std::ptr;

use rf_aurexis::gad::{
    BakeConfig, BakeStep, BakeToSlot, CanonicalEventBinding, GadProject, GadProjectConfig,
    GadTrackType, MarkerType, MusicalPosition, TimelineMarker,
};

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

static GAD_PROJECT: Lazy<RwLock<Option<GadProject>>> = Lazy::new(|| RwLock::new(None));
static BAKE_ENGINE: Lazy<RwLock<Option<BakeToSlot>>> = Lazy::new(|| RwLock::new(None));

// ═══════════════════════════════════════════════════════════════════════════════
// PROJECT MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a new GAD project with default config. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_create_project() -> i32 {
    let project = GadProject::default_project();
    *GAD_PROJECT.write() = Some(project);
    *BAKE_ENGINE.write() = Some(BakeToSlot::new(BakeConfig::default()));
    1
}

/// Create a GAD project with custom BPM and bar count. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_create_project_custom(bpm: f64, length_bars: u32, sample_rate: u32) -> i32 {
    let config = GadProjectConfig {
        bpm,
        length_bars,
        sample_rate,
        ..Default::default()
    };
    *GAD_PROJECT.write() = Some(GadProject::new(config));
    *BAKE_ENGINE.write() = Some(BakeToSlot::new(BakeConfig::default()));
    1
}

/// Get project name as JSON string. Caller must free with gad_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn gad_project_name() -> *mut c_char {
    let guard = GAD_PROJECT.read();
    match &*guard {
        Some(p) => string_to_c(&p.config.name),
        None => ptr::null_mut(),
    }
}

/// Get track count.
#[unsafe(no_mangle)]
pub extern "C" fn gad_track_count() -> i32 {
    let guard = GAD_PROJECT.read();
    match &*guard {
        Some(p) => p.tracks.len() as i32,
        None => -1,
    }
}

/// Get full project as JSON. Caller must free with gad_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn gad_project_json() -> *mut c_char {
    let guard = GAD_PROJECT.read();
    match &*guard {
        Some(p) => match p.to_json() {
            Ok(json) => string_to_c(&json),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

/// Load project from JSON. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_load_project_json(json: *const c_char) -> i32 {
    let json_str = match unsafe { c_str_to_string(json) } {
        Some(s) => s,
        None => return 0,
    };
    match GadProject::from_json(&json_str) {
        Ok(project) => {
            *GAD_PROJECT.write() = Some(project);
            1
        }
        Err(_) => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRACK MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Add a track. track_type: 0-7 maps to GadTrackType. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_add_track(name: *const c_char, track_type: u8) -> i32 {
    let name_str = match unsafe { c_str_to_string(name) } {
        Some(s) => s,
        None => return 0,
    };
    let tt = match track_type_from_index(track_type) {
        Some(t) => t,
        None => return 0,
    };
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => {
            p.add_track(name_str, tt);
            1
        }
        None => 0,
    }
}

/// Remove a track by ID. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_remove_track(track_id: *const c_char) -> i32 {
    let id = match unsafe { c_str_to_string(track_id) } {
        Some(s) => s,
        None => return 0,
    };
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => {
            if p.remove_track(&id) {
                1
            } else {
                0
            }
        }
        None => 0,
    }
}

/// Set track audio path. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_set_track_audio(track_id: *const c_char, audio_path: *const c_char) -> i32 {
    let id = match unsafe { c_str_to_string(track_id) } {
        Some(s) => s,
        None => return 0,
    };
    let path = match unsafe { c_str_to_string(audio_path) } {
        Some(s) => s,
        None => return 0,
    };
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => match p.track_mut(&id) {
            Some(track) => {
                track.audio_path = Some(path);
                1
            }
            None => 0,
        },
        None => 0,
    }
}

/// Set track event binding. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_set_track_binding(
    track_id: *const c_char,
    hook: *const c_char,
    substate: *const c_char,
) -> i32 {
    let id = match unsafe { c_str_to_string(track_id) } {
        Some(s) => s,
        None => return 0,
    };
    let hook_str = match unsafe { c_str_to_string(hook) } {
        Some(s) => s,
        None => return 0,
    };
    let sub = match unsafe { c_str_to_string(substate) } {
        Some(s) => s,
        None => return 0,
    };
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => match p.track_mut(&id) {
            Some(track) => {
                track.metadata.event_binding = Some(CanonicalEventBinding {
                    hook: hook_str,
                    substate: sub,
                    required: true,
                });
                1
            }
            None => 0,
        },
        None => 0,
    }
}

/// Set track metadata values. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_set_track_metadata(
    track_id: *const c_char,
    emotional_bias: f64,
    energy_weight: f64,
    harmonic_density: u32,
    turbo_reduction: f64,
) -> i32 {
    let id = match unsafe { c_str_to_string(track_id) } {
        Some(s) => s,
        None => return 0,
    };
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => match p.track_mut(&id) {
            Some(track) => {
                track.metadata.emotional_bias = emotional_bias;
                track.metadata.energy_weight = energy_weight;
                track.metadata.harmonic_density = harmonic_density;
                track.metadata.turbo_reduction_factor = turbo_reduction;
                1
            }
            None => 0,
        },
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIMELINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Set BPM. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_set_bpm(bpm: f64) -> i32 {
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => {
            p.timeline.musical.base_bpm = bpm;
            1
        }
        None => 0,
    }
}

/// Add a timeline anchor. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_add_anchor(
    id: *const c_char,
    bar: u32,
    beat: u32,
    tick: u32,
    gameplay_frame: u64,
    hook: *const c_char,
) -> i32 {
    let id_str = match unsafe { c_str_to_string(id) } {
        Some(s) => s,
        None => return 0,
    };
    let hook_str = match unsafe { c_str_to_string(hook) } {
        Some(s) => s,
        None => return 0,
    };
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => {
            p.timeline.add_anchor(
                id_str,
                MusicalPosition::new(bar, beat, tick),
                gameplay_frame,
                hook_str,
            );
            1
        }
        None => 0,
    }
}

/// Add a timeline marker. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn gad_add_marker(
    id: *const c_char,
    name: *const c_char,
    marker_type: u8,
    bar: u32,
    beat: u32,
    tick: u32,
    color: u32,
) -> i32 {
    let id_str = match unsafe { c_str_to_string(id) } {
        Some(s) => s,
        None => return 0,
    };
    let name_str = match unsafe { c_str_to_string(name) } {
        Some(s) => s,
        None => return 0,
    };
    let mt = match marker_type {
        0 => MarkerType::Cue,
        1 => MarkerType::HookAnchor,
        2 => MarkerType::RegionStart,
        3 => MarkerType::RegionEnd,
        4 => MarkerType::LoopPoint,
        5 => MarkerType::BakeBoundary,
        _ => return 0,
    };
    let mut guard = GAD_PROJECT.write();
    match &mut *guard {
        Some(p) => {
            p.timeline.add_marker(TimelineMarker {
                id: id_str,
                name: name_str,
                marker_type: mt,
                musical_pos: MusicalPosition::new(bar, beat, tick),
                gameplay_pos: None,
                color,
            });
            1
        }
        None => 0,
    }
}

/// Get timeline JSON. Caller must free with gad_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn gad_timeline_json() -> *mut c_char {
    let guard = GAD_PROJECT.read();
    match &*guard {
        Some(p) => match p.timeline.to_json() {
            Ok(json) => string_to_c(&json),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BAKE TO SLOT
// ═══════════════════════════════════════════════════════════════════════════════

/// Run the 11-step bake pipeline. Returns 1 on success (all steps pass).
#[unsafe(no_mangle)]
pub extern "C" fn gad_bake() -> i32 {
    let project_guard = GAD_PROJECT.read();
    let project = match &*project_guard {
        Some(p) => p,
        None => return 0,
    };
    let mut bake_guard = BAKE_ENGINE.write();
    let bake = match &mut *bake_guard {
        Some(b) => b,
        None => return 0,
    };
    let result = bake.bake(project);
    if result.success { 1 } else { 0 }
}

/// Get bake result JSON. Caller must free with gad_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn gad_bake_result_json() -> *mut c_char {
    let guard = BAKE_ENGINE.read();
    match &*guard {
        Some(b) => match b.result_json() {
            Ok(json) => string_to_c(&json),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

/// Get bake step count (always 11).
#[unsafe(no_mangle)]
pub extern "C" fn gad_bake_step_count() -> i32 {
    BakeStep::count() as i32
}

/// Get bake progress (0.0-1.0).
#[unsafe(no_mangle)]
pub extern "C" fn gad_bake_progress() -> f64 {
    let guard = BAKE_ENGINE.read();
    match &*guard {
        Some(b) => match b.last_result() {
            Some(r) => r.progress(),
            None => 0.0,
        },
        None => 0.0,
    }
}

/// Validate project. Returns error count (0 = valid).
#[unsafe(no_mangle)]
pub extern "C" fn gad_validate() -> i32 {
    let guard = GAD_PROJECT.read();
    match &*guard {
        Some(p) => p.validate().len() as i32,
        None => -1,
    }
}

/// Get validation errors as JSON array. Caller must free with gad_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn gad_validation_errors_json() -> *mut c_char {
    let guard = GAD_PROJECT.read();
    match &*guard {
        Some(p) => {
            let errors = p.validate();
            match serde_json::to_string(&errors) {
                Ok(json) => string_to_c(&json),
                Err(_) => ptr::null_mut(),
            }
        }
        None => ptr::null_mut(),
    }
}

/// Free a string returned by gad_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn gad_free_string(s: *mut c_char) {
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

fn track_type_from_index(index: u8) -> Option<GadTrackType> {
    match index {
        0 => Some(GadTrackType::MusicLayer),
        1 => Some(GadTrackType::Transient),
        2 => Some(GadTrackType::ReelBound),
        3 => Some(GadTrackType::CascadeLayer),
        4 => Some(GadTrackType::JackpotLadder),
        5 => Some(GadTrackType::Ui),
        6 => Some(GadTrackType::System),
        7 => Some(GadTrackType::AmbientPad),
        _ => None,
    }
}

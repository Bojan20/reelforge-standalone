//! Device Preview Engine FFI — monitoring-only device simulation
//!
//! Thread-safe: load_profile/set_active from UI, process() from audio thread.

use lazy_static::lazy_static;
use parking_lot::RwLock;
use rf_dsp::device_preview::{
    self, DeviceCategory, DevicePreviewEngine, DeviceStereoMode, DistortionModel,
};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

lazy_static! {
    pub static ref DEVICE_PREVIEW: RwLock<Option<DevicePreviewEngine>> = RwLock::new(None);
}

// ═══════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════

/// Initialize device preview engine
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_init(sample_rate: f64) -> i32 {
    let engine = DevicePreviewEngine::new(sample_rate);
    *DEVICE_PREVIEW.write() = Some(engine);
    1
}

/// Destroy device preview engine
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_destroy() -> i32 {
    *DEVICE_PREVIEW.write() = None;
    1
}

/// Set active state (1 = on, 0 = off)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_set_active(active: i32) -> i32 {
    if let Some(ref engine) = *DEVICE_PREVIEW.read() {
        engine.set_active(active != 0);
        return 1;
    }
    0
}

/// Check if active
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_is_active() -> i32 {
    if let Some(ref engine) = *DEVICE_PREVIEW.read() {
        return if engine.is_active() { 1 } else { 0 };
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

/// Load a profile by ID. Returns 1 on success, 0 if profile not found.
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_load_profile(profile_id: u16) -> i32 {
    if let Some(profile) = device_preview::get_profile(profile_id) {
        if let Some(ref mut engine) = *DEVICE_PREVIEW.write() {
            engine.load_profile(profile);
            return 1;
        }
    }
    0
}

/// Bypass (flat response)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_bypass() -> i32 {
    if let Some(ref mut engine) = *DEVICE_PREVIEW.write() {
        engine.bypass();
        return 1;
    }
    0
}

/// Get current profile ID (0 = no profile / bypass)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_current_profile_id() -> u32 {
    if let Some(ref engine) = *DEVICE_PREVIEW.read() {
        return engine.current_profile_id();
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE QUERIES
// ═══════════════════════════════════════════════════════════════════════════

/// Get total number of profiles
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_profile_count() -> u32 {
    device_preview::profile_count() as u32
}

/// Get profile name by ID. Returns null if not found. Caller must free with device_preview_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_profile_name(profile_id: u16) -> *mut c_char {
    if let Some(profile) = device_preview::get_profile(profile_id) {
        if let Ok(s) = CString::new(profile.name) {
            return s.into_raw();
        }
    }
    std::ptr::null_mut()
}

/// Get profile category by ID (returns category enum as u8)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_profile_category(profile_id: u16) -> u8 {
    if let Some(profile) = device_preview::get_profile(profile_id) {
        return profile.category as u8;
    }
    255
}

/// Get all profile IDs as a flat array. Returns count. Caller provides buffer.
/// Buffer must hold at least 50 u16 values.
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_all_profile_ids(out_ids: *mut u16, max_count: u32) -> u32 {
    if out_ids.is_null() {
        return 0;
    }
    let profiles = &device_preview::DEVICE_PROFILES;
    let count = profiles.len().min(max_count as usize);
    unsafe {
        for i in 0..count {
            *out_ids.add(i) = profiles[i].id;
        }
    }
    count as u32
}

/// Get profiles by category. Returns count. Buffer must hold profile IDs.
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_profiles_by_category(
    category: u8,
    out_ids: *mut u16,
    max_count: u32,
) -> u32 {
    if out_ids.is_null() {
        return 0;
    }
    let cat = match category {
        0 => DeviceCategory::Smartphone,
        1 => DeviceCategory::Headphone,
        2 => DeviceCategory::LaptopTablet,
        3 => DeviceCategory::TvSoundbar,
        4 => DeviceCategory::BtSpeaker,
        5 => DeviceCategory::ReferenceMonitor,
        6 => DeviceCategory::CasinoEnvironment,
        7 => DeviceCategory::Custom,
        _ => return 0,
    };
    let profiles = device_preview::profiles_by_category(cat);
    let count = profiles.len().min(max_count as usize);
    unsafe {
        for i in 0..count {
            *out_ids.add(i) = profiles[i].id;
        }
    }
    count as u32
}

/// Get profile FR curve data. Returns point count.
/// out_data format: [freq0, gain0, freq1, gain1, ...] (interleaved)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_profile_fr_curve(
    profile_id: u16,
    out_data: *mut f32,
    max_points: u32,
) -> u32 {
    if out_data.is_null() {
        return 0;
    }
    if let Some(profile) = device_preview::get_profile(profile_id) {
        let count = profile.fr_curve.len().min(max_points as usize);
        unsafe {
            for i in 0..count {
                *out_data.add(i * 2) = profile.fr_curve[i].freq as f32;
                *out_data.add(i * 2 + 1) = profile.fr_curve[i].gain_db as f32;
            }
        }
        return count as u32;
    }
    0
}

/// Get category count (8 categories)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_category_count() -> u32 {
    8
}

/// Get category name by index. Caller must free with device_preview_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_category_name(category: u8) -> *mut c_char {
    let names = device_preview::category_names();
    if (category as usize) < names.len() {
        if let Ok(s) = CString::new(names[category as usize].0) {
            return s.into_raw();
        }
    }
    std::ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════
// PROCESS (audio thread)
// ═══════════════════════════════════════════════════════════════════════════

/// Process stereo buffer in-place (called from audio thread)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_process(
    left: *mut f64,
    right: *mut f64,
    frames: u32,
) -> i32 {
    if left.is_null() || right.is_null() || frames == 0 {
        return 0;
    }
    if let Some(ref mut engine) = *DEVICE_PREVIEW.write() {
        unsafe {
            let left_slice = std::slice::from_raw_parts_mut(left, frames as usize);
            let right_slice = std::slice::from_raw_parts_mut(right, frames as usize);
            engine.process(left_slice, right_slice);
        }
        return 1;
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

/// Free a string returned by device_preview functions
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

/// Get JSON with all profile info (for bulk loading into Dart)
#[unsafe(no_mangle)]
pub extern "C" fn device_preview_all_profiles_json() -> *mut c_char {
    let profiles = &device_preview::DEVICE_PROFILES;
    let mut json = String::from("[");
    for (i, p) in profiles.iter().enumerate() {
        if i > 0 { json.push(','); }
        let cat = match p.category {
            DeviceCategory::Smartphone => "smartphone",
            DeviceCategory::Headphone => "headphone",
            DeviceCategory::LaptopTablet => "laptop_tablet",
            DeviceCategory::TvSoundbar => "tv_soundbar",
            DeviceCategory::BtSpeaker => "bt_speaker",
            DeviceCategory::ReferenceMonitor => "reference_monitor",
            DeviceCategory::CasinoEnvironment => "casino_environment",
            DeviceCategory::Custom => "custom",
        };
        let stereo = match p.stereo_mode {
            DeviceStereoMode::Stereo => "stereo".to_string(),
            DeviceStereoMode::Narrowed(w) => format!("narrowed_{}", w),
            DeviceStereoMode::Mono => "mono".to_string(),
        };
        let dist = match p.distortion {
            DistortionModel::None => "none",
            DistortionModel::SoftClip => "soft_clip",
            DistortionModel::HardClip => "hard_clip",
            DistortionModel::SpeakerBreakup => "speaker_breakup",
        };
        json.push_str(&format!(
            r#"{{"id":{},"name":"{}","category":"{}","hpf_freq":{:.1},"max_spl":{:.1},"drc_amount":{:.2},"stereo":"{}","distortion":"{}","env_noise_floor":{:.1},"fr_points":{}}}"#,
            p.id, p.name, cat, p.hpf_freq, p.max_spl_dbfs, p.drc_amount, stereo, dist, p.env_noise_floor, p.fr_curve.len()
        ));
    }
    json.push(']');

    if let Ok(s) = CString::new(json) {
        return s.into_raw();
    }
    std::ptr::null_mut()
}

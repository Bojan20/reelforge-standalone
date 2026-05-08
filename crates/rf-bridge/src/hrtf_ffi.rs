//! Personalized HRTF FFI — bridges rf-spatial binaural to Flutter.

use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::sync::{Arc, RwLock};

use rf_spatial::binaural::{
    personalize, AnthropometricProfile, HrtfDatabase,
};

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════

static HRTF_DB: RwLock<Option<Arc<HrtfDatabase>>> = RwLock::new(None);

fn set_db(db: HrtfDatabase) {
    *HRTF_DB.write().unwrap() = Some(Arc::new(db));
}

fn with_db<F, R>(f: F) -> R
where
    F: FnOnce(Option<&HrtfDatabase>) -> R,
{
    let lock = HRTF_DB.read().unwrap();
    f(lock.as_deref())
}

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/// Get the default anthropometric profile as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_default_profile_json() -> *mut c_char {
    let profile = AnthropometricProfile::default();
    json_to_c(serde_json::to_string_pretty(&profile).unwrap_or_else(|_| "{}".into()))
}

/// Clamp an anthropometric profile JSON in-place and return the clamped JSON.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_clamp_profile_json(profile_json: *const c_char) -> *mut c_char {
    if profile_json.is_null() {
        return hrtf_default_profile_json();
    }
    let s = match unsafe { CStr::from_ptr(profile_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let profile: AnthropometricProfile = match serde_json::from_str(s) {
        Ok(p) => p,
        Err(_) => return std::ptr::null_mut(),
    };
    let clamped = profile.clamp();
    json_to_c(serde_json::to_string_pretty(&clamped).unwrap_or_else(|_| "{}".into()))
}

// ═══════════════════════════════════════════════════════════════════════════
// GENERATION
// ═══════════════════════════════════════════════════════════════════════════

/// Generate a personalized HRTF database from an anthropometric profile.
///
/// * `profile_json` — JSON `AnthropometricProfile`
/// * `sample_rate` — e.g. 48000 or 44100
///
/// Returns 0 on success, -1 on parse error.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_generate(profile_json: *const c_char, sample_rate: u32) -> i32 {
    if profile_json.is_null() {
        return -1;
    }
    let s = match unsafe { CStr::from_ptr(profile_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let profile: AnthropometricProfile = match serde_json::from_str(s) {
        Ok(p) => p,
        Err(_) => return -1,
    };
    let db = personalize(profile, sample_rate);
    set_db(db);
    0
}

/// Generate using the default (average) profile.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_generate_default(sample_rate: u32) -> i32 {
    let db = personalize(AnthropometricProfile::default(), sample_rate);
    set_db(db);
    0
}

// ═══════════════════════════════════════════════════════════════════════════
// PERSISTENCE (FFHRTF)
// ═══════════════════════════════════════════════════════════════════════════

/// Save the current HRTF database to a `.ffhrtf` directory.
///
/// Returns 0 on success, -1 if no DB is loaded, -2 on I/O error.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_save_ffhrtf(path: *const c_char, subject_id: *const c_char) -> i32 {
    with_db(|db_opt| {
        let db = match db_opt {
            Some(db) => db,
            None => return -1,
        };
        let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let subject = if subject_id.is_null() {
            "custom"
        } else {
            match unsafe { CStr::from_ptr(subject_id) }.to_str() {
                Ok(s) => s,
                Err(_) => return -1,
            }
        };

        let (manifest, dataset) =
            rf_spatial::binaural::export_database(db, subject, None);
        match rf_spatial::binaural::save_ffhrtf_dir(Path::new(path_str), &manifest, &dataset) {
            Ok(()) => 0,
            Err(_) => -2,
        }
    })
}

/// Load a `.ffhrtf` directory and replace the current HRTF database.
///
/// Returns 0 on success, -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_load_ffhrtf(path: *const c_char) -> i32 {
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    match rf_spatial::binaural::load_ffhrtf_dir(Path::new(path_str)) {
        Ok(dataset) => {
            set_db(dataset.into_database());
            0
        }
        Err(_) => -1,
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// METADATA
// ═══════════════════════════════════════════════════════════════════════════

/// Get the current HRTF metadata as JSON.
/// Returns `null` if no database is loaded.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_metadata_json() -> *mut c_char {
    with_db(|db_opt| {
        let db = match db_opt {
            Some(db) => db,
            None => return std::ptr::null_mut(),
        };
        let meta = serde_json::json!({
            "sample_rate": db.sample_rate(),
            "filter_length": db.filter_length(),
            "measurement_count": db.measurement_count(),
        });
        json_to_c(meta.to_string())
    })
}

// ═══════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════

/// Free a string returned by any `hrtf_*` function.
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Serialize tests that mutate the global `HRTF_DB`.  `cargo test`
    /// runs tests in parallel by default, so without this lock
    /// `save_without_db_returns_error` can race with `generate_default_*`
    /// and observe a populated DB.
    static TEST_MUTEX: Mutex<()> = Mutex::new(());

    /// Helper to consume a `*mut c_char` from FFI into an owned `String`.
    /// Frees the C string via `hrtf_free_string` to mirror the Flutter contract.
    fn ffi_string(ptr: *mut c_char) -> Option<String> {
        if ptr.is_null() {
            return None;
        }
        let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
        hrtf_free_string(ptr);
        Some(s)
    }

    fn cstr(s: &str) -> CString {
        CString::new(s).expect("test string contains NUL")
    }

    #[test]
    fn default_profile_json_parses_back_into_struct() {
        let raw = hrtf_default_profile_json();
        let json = ffi_string(raw).expect("default profile must produce JSON");
        let parsed: AnthropometricProfile =
            serde_json::from_str(&json).expect("default JSON must deserialize");
        assert_eq!(parsed, AnthropometricProfile::default());
    }

    #[test]
    fn clamp_profile_handles_null_and_garbage() {
        // Null → falls back to default
        let from_null = ffi_string(hrtf_clamp_profile_json(std::ptr::null()))
            .expect("null should fall back to default JSON");
        let parsed: AnthropometricProfile = serde_json::from_str(&from_null).unwrap();
        assert_eq!(parsed, AnthropometricProfile::default());

        // Garbage JSON → null pointer
        let garbage = cstr("{\"not_a_profile\":true}");
        let bad = hrtf_clamp_profile_json(garbage.as_ptr());
        assert!(bad.is_null(), "invalid JSON should yield null");
    }

    #[test]
    fn clamp_profile_pulls_extreme_values_into_range() {
        let extreme = AnthropometricProfile {
            head_width_mm: 999.0,
            head_depth_mm: 1.0,
            pinna_height_mm: 200.0,
            pinna_width_mm: 0.0,
            cavum_concha_depth_mm: 0.0,
            head_circumference_mm: 0.0,
            inter_tragal_distance_mm: 0.0,
            nose_bridge_prominence_mm: 999.0,
        };
        let json = serde_json::to_string(&extreme).unwrap();
        let c = cstr(&json);
        let raw = hrtf_clamp_profile_json(c.as_ptr());
        let clamped_json = ffi_string(raw).expect("clamp must succeed");
        let clamped: AnthropometricProfile = serde_json::from_str(&clamped_json).unwrap();
        assert!(clamped.head_width_mm <= 190.0);
        assert!(clamped.head_width_mm >= 120.0);
        assert!(clamped.pinna_width_mm >= 15.0);
        assert!(clamped.nose_bridge_prominence_mm <= 28.0);
    }

    #[test]
    fn generate_default_then_metadata_reports_population() {
        let _g = TEST_MUTEX.lock().unwrap();
        let rc = hrtf_generate_default(48_000);
        assert_eq!(rc, 0);

        let meta_raw = hrtf_metadata_json();
        let meta = ffi_string(meta_raw).expect("metadata must be present after generate");
        let v: serde_json::Value = serde_json::from_str(&meta).unwrap();
        assert_eq!(v["sample_rate"].as_u64(), Some(48_000));
        let count = v["measurement_count"].as_u64().unwrap();
        assert!(count > 100, "expected populated DB, got {count} measurements");
        let fl = v["filter_length"].as_u64().unwrap();
        assert!(fl > 0);
    }

    #[test]
    fn generate_with_custom_profile_round_trips_through_persistence() {
        let _g = TEST_MUTEX.lock().unwrap();
        // Step 1 — generate from a custom profile
        let profile = AnthropometricProfile {
            head_width_mm: 162.0,
            ..AnthropometricProfile::default()
        };
        let pj = serde_json::to_string(&profile).unwrap();
        let pj_c = cstr(&pj);
        assert_eq!(hrtf_generate(pj_c.as_ptr(), 48_000), 0);

        // Step 2 — save to a temp ffhrtf dir
        let tmp = std::env::temp_dir().join("fluxforge_test_ffi_hrtf_roundtrip");
        let _ = std::fs::remove_dir_all(&tmp);
        let path_c = cstr(tmp.to_str().unwrap());
        let subj_c = cstr("ffi_test");
        assert_eq!(hrtf_save_ffhrtf(path_c.as_ptr(), subj_c.as_ptr()), 0);

        // Step 3 — load back; metadata should match what we just saved
        assert_eq!(hrtf_load_ffhrtf(path_c.as_ptr()), 0);
        let meta = ffi_string(hrtf_metadata_json()).unwrap();
        let v: serde_json::Value = serde_json::from_str(&meta).unwrap();
        assert_eq!(v["sample_rate"].as_u64(), Some(48_000));
        assert!(v["measurement_count"].as_u64().unwrap() > 100);

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn generate_rejects_null_and_garbage_profile() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate(std::ptr::null(), 48_000), -1);

        let bad = cstr("not json");
        assert_eq!(hrtf_generate(bad.as_ptr(), 48_000), -1);
    }

    #[test]
    fn save_without_db_returns_error() {
        let _g = TEST_MUTEX.lock().unwrap();
        // Force a clean global state before this test by writing None.
        *HRTF_DB.write().unwrap() = None;
        let p = cstr("/tmp/fluxforge_should_not_be_created");
        let s = cstr("ffi_test");
        let rc = hrtf_save_ffhrtf(p.as_ptr(), s.as_ptr());
        assert_eq!(rc, -1, "save with no DB should return -1");
    }

    #[test]
    fn free_string_handles_null_safely() {
        // Must not panic / segfault.
        hrtf_free_string(std::ptr::null_mut());
    }
}

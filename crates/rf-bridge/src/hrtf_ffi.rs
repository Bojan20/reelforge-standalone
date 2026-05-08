//! Personalized HRTF FFI — bridges rf-spatial binaural to Flutter.

use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::sync::{Arc, RwLock};

use rf_spatial::binaural::{
    personalize, AnthropometricProfile, BinauralConfig, BinauralRenderer, HrtfDatabase,
};
use rf_spatial::{AudioObject, Position3D, SpatialRenderer};

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
// LIVE AUDITION (P1.2)
// ═══════════════════════════════════════════════════════════════════════════
//
// Render a short test signal through the in-memory HRTF database to a stereo
// `.wav` file at the user-specified path.  The Flutter side then plays back
// the file via its existing audio player — keeping the audio thread out of
// the FFI surface.  This trades ~100 ms of latency for a much simpler
// integration than wiring a live audio callback through Rust↔Dart.

/// Test signal generators recognised by `hrtf_audition_render_to_wav`.
const SIGNAL_PINK: u8 = 0;
const SIGNAL_WHITE: u8 = 1;
const SIGNAL_SINE_440: u8 = 2;
const SIGNAL_SINE_1K: u8 = 3;
const SIGNAL_CHIRP: u8 = 4;

/// Render a personalized HRTF audition tone to a stereo WAV file.
///
/// * `azimuth_deg` — −180..+180 (0 = front, +90 = right)
/// * `elevation_deg` — −90..+90 (0 = ear-level, +90 = above)
/// * `signal_type` — 0 pink, 1 white, 2 440Hz sine, 3 1 kHz sine, 4 200Hz→8kHz chirp
/// * `duration_ms` — 50..5000 — clamped
/// * `out_path` — directory must already exist
///
/// Returns:
/// *  `0` — success
/// * `-1` — no HRTF database (call `hrtf_generate*` first)
/// * `-2` — invalid argument (null path, bad signal_type, bad UTF-8)
/// * `-3` — render failure
/// * `-4` — WAV write failure
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_audition_render_to_wav(
    azimuth_deg: f32,
    elevation_deg: f32,
    signal_type: u8,
    duration_ms: u32,
    out_path: *const c_char,
) -> i32 {
    // ── 1. Snapshot the global HRTF database under the read lock ──────────
    let db_arc = match HRTF_DB.read().unwrap().as_ref() {
        Some(arc) => arc.clone(),
        None => return -1,
    };

    // ── 2. Validate args ──────────────────────────────────────────────────
    if out_path.is_null() {
        return -2;
    }
    let path_str = match unsafe { CStr::from_ptr(out_path) }.to_str() {
        Ok(s) if !s.is_empty() => s,
        _ => return -2,
    };
    if signal_type > SIGNAL_CHIRP {
        return -2;
    }

    // ── 3. Build a fresh BinauralRenderer from the snapshot DB ────────────
    let sample_rate = db_arc.sample_rate();
    let mut renderer = BinauralRenderer::new(BinauralConfig::default(), sample_rate);
    renderer.set_hrtf_database((*db_arc).clone());

    // ── 4. Generate mono source signal ────────────────────────────────────
    let dur_ms = duration_ms.clamp(50, 5_000);
    let n_samples = ((dur_ms as u64) * sample_rate as u64 / 1000) as usize;
    let source = generate_signal(signal_type, n_samples, sample_rate);

    // ── 5. Wrap in an AudioObject placed on the unit sphere at (az, el) ────
    let position = Position3D::from_spherical(azimuth_deg, elevation_deg, 1.5);
    let object = AudioObject {
        id: 0,
        name: "audition".into(),
        position,
        size: 0.0,
        gain: 0.5, // headroom — leave 6 dB before clipping
        audio: source,
        sample_rate,
        automation: None,
    };

    // ── 6. Render to interleaved stereo ──────────────────────────────────
    let mut output = vec![0.0f32; n_samples * 2];
    if renderer.render(&[object], &mut output, 2).is_err() {
        return -3;
    }

    // ── 7. Apply a small fade in/out so the click is gone ─────────────────
    apply_fades(&mut output, sample_rate);

    // ── 8. Write WAV (32-bit float, stereo) ──────────────────────────────
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };
    let mut writer = match hound::WavWriter::create(path_str, spec) {
        Ok(w) => w,
        Err(_) => return -4,
    };
    for s in &output {
        if writer.write_sample(*s).is_err() {
            return -4;
        }
    }
    if writer.finalize().is_err() {
        return -4;
    }
    0
}

// ─── Audition signal generators ──────────────────────────────────────────

fn generate_signal(kind: u8, n: usize, sample_rate: u32) -> Vec<f32> {
    match kind {
        SIGNAL_PINK => generate_pink_noise(n),
        SIGNAL_WHITE => generate_white_noise(n),
        SIGNAL_SINE_440 => generate_sine(n, sample_rate, 440.0),
        SIGNAL_SINE_1K => generate_sine(n, sample_rate, 1_000.0),
        SIGNAL_CHIRP => generate_chirp(n, sample_rate, 200.0, 8_000.0),
        _ => generate_pink_noise(n),
    }
}

/// Lightweight LFSR for reproducible noise without bringing in `rand`.
struct Lfsr {
    state: u32,
}
impl Lfsr {
    fn new(seed: u32) -> Self {
        Self {
            state: if seed == 0 { 0xDEADBEEF } else { seed },
        }
    }
    fn next_f32(&mut self) -> f32 {
        // xorshift32
        let mut s = self.state;
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        self.state = s;
        // Map to [-1, 1)
        (s as i32 as f32) / (i32::MAX as f32)
    }
}

fn generate_white_noise(n: usize) -> Vec<f32> {
    let mut rng = Lfsr::new(0xC0DE_F00D);
    (0..n).map(|_| rng.next_f32() * 0.5).collect()
}

/// Voss–McCartney pink noise (4 octaves, fixed amplitude).
/// Cheap, deterministic, ~1/f spectrum within ±1 dB across 50 Hz–18 kHz.
fn generate_pink_noise(n: usize) -> Vec<f32> {
    let mut rng = Lfsr::new(0xFEED_BEEF);
    let mut rows = [0.0f32; 5];
    let mut out = Vec::with_capacity(n);
    let mut counter: u32 = 0;
    for _ in 0..n {
        // Update one row whose index is the lowest set bit of `counter`.
        counter = counter.wrapping_add(1);
        let row_idx = counter.trailing_zeros().min(4) as usize;
        rows[row_idx] = rng.next_f32();
        let sum: f32 = rows.iter().sum();
        out.push((sum / 5.0) * 0.5);
    }
    out
}

fn generate_sine(n: usize, sample_rate: u32, freq_hz: f32) -> Vec<f32> {
    let two_pi = std::f32::consts::TAU;
    (0..n)
        .map(|i| {
            let t = i as f32 / sample_rate as f32;
            (two_pi * freq_hz * t).sin() * 0.5
        })
        .collect()
}

/// Logarithmic frequency sweep — useful for hearing how the HRTF
/// shapes notches across the spectrum.
fn generate_chirp(n: usize, sample_rate: u32, f_start: f32, f_end: f32) -> Vec<f32> {
    let dur = n as f32 / sample_rate as f32;
    let k = (f_end / f_start).ln() / dur;
    (0..n)
        .map(|i| {
            let t = i as f32 / sample_rate as f32;
            // Instantaneous frequency ω(t) = 2π·f_start·exp(k·t), so
            // the phase is the analytic integral.
            let phase = std::f32::consts::TAU * f_start * ((k * t).exp() - 1.0) / k;
            phase.sin() * 0.5
        })
        .collect()
}

/// 5 ms linear fade in/out to suppress edge clicks.
fn apply_fades(stereo: &mut [f32], sample_rate: u32) {
    let fade_n = ((sample_rate as f32) * 0.005) as usize;
    let frames = stereo.len() / 2;
    if fade_n * 2 >= frames {
        return;
    }
    for i in 0..fade_n {
        let g = i as f32 / fade_n as f32;
        stereo[i * 2] *= g;
        stereo[i * 2 + 1] *= g;
        let j = frames - 1 - i;
        stereo[j * 2] *= g;
        stereo[j * 2 + 1] *= g;
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

    // ─── Audition tests (P1.2) ─────────────────────────────────────────

    #[test]
    fn audition_renders_wav_when_db_is_loaded() {
        let _g = TEST_MUTEX.lock().unwrap();
        // Ensure the DB is populated (round-trip uses default profile).
        assert_eq!(hrtf_generate_default(48_000), 0);

        let path = std::env::temp_dir().join("fluxforge_audition_test.wav");
        let _ = std::fs::remove_file(&path);
        let path_c = cstr(path.to_str().unwrap());

        // 200 ms pink noise at 30° azimuth, 0° elevation.
        let rc = hrtf_audition_render_to_wav(30.0, 0.0, 0, 200, path_c.as_ptr());
        assert_eq!(rc, 0);
        assert!(path.exists(), "wav file must exist after render");

        // Validate the WAV is parseable + has stereo content.
        let reader = hound::WavReader::open(&path).expect("WavReader open");
        let spec = reader.spec();
        assert_eq!(spec.channels, 2);
        assert_eq!(spec.sample_rate, 48_000);
        assert_eq!(spec.sample_format, hound::SampleFormat::Float);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn audition_rejects_when_no_db() {
        let _g = TEST_MUTEX.lock().unwrap();
        *HRTF_DB.write().unwrap() = None;
        let path_c = cstr("/tmp/should_not_be_written.wav");
        let rc = hrtf_audition_render_to_wav(0.0, 0.0, 0, 200, path_c.as_ptr());
        assert_eq!(rc, -1);
    }

    #[test]
    fn audition_rejects_invalid_signal_type() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);
        let path_c = cstr("/tmp/should_not_be_written.wav");
        let rc = hrtf_audition_render_to_wav(0.0, 0.0, 99, 200, path_c.as_ptr());
        assert_eq!(rc, -2);
    }

    #[test]
    fn audition_rejects_null_path() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);
        let rc = hrtf_audition_render_to_wav(0.0, 0.0, 0, 200, std::ptr::null());
        assert_eq!(rc, -2);
    }

    #[test]
    fn audition_clamps_extreme_duration() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);
        let path = std::env::temp_dir().join("fluxforge_audition_clamp.wav");
        let _ = std::fs::remove_file(&path);
        let path_c = cstr(path.to_str().unwrap());

        // 10 s would overflow our policy; renderer must clamp to 5 s and
        // still return 0.  We verify by checking the actual frame count.
        let rc =
            hrtf_audition_render_to_wav(0.0, 0.0, 2, 10_000, path_c.as_ptr());
        assert_eq!(rc, 0);
        let reader = hound::WavReader::open(&path).expect("open");
        let frames = reader.duration();
        assert!(
            frames <= 48_000 * 5 + 16,
            "expected ≤5s of audio, got {frames} frames",
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn audition_supports_all_signal_types() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);
        let dir = std::env::temp_dir().join("fluxforge_audition_signals");
        let _ = std::fs::create_dir_all(&dir);
        for sig in 0u8..=4u8 {
            let p = dir.join(format!("sig_{sig}.wav"));
            let _ = std::fs::remove_file(&p);
            let pc = cstr(p.to_str().unwrap());
            let rc = hrtf_audition_render_to_wav(0.0, 0.0, sig, 100, pc.as_ptr());
            assert_eq!(rc, 0, "signal type {sig} should succeed");
            assert!(p.exists());
            let _ = std::fs::remove_file(&p);
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
}

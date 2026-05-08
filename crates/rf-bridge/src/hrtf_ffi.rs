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

// ═══════════════════════════════════════════════════════════════════════════
// DEFAULT PRESETS BUNDLE (P1.3)
// ═══════════════════════════════════════════════════════════════════════════
//
// Generates the three canonical anthropometric profiles (small / average /
// large) and writes each as a `.ffhrtf` directory under `out_dir`.  Flutter
// calls this once on first launch and then loads any of them via the
// existing `hrtf_load_ffhrtf` path.

/// Anthropometric matching the Dart `AnthropometricProfile.small` constant.
fn preset_small() -> AnthropometricProfile {
    AnthropometricProfile {
        head_width_mm: 142.0,
        head_depth_mm: 180.0,
        pinna_height_mm: 58.0,
        pinna_width_mm: 25.0,
        cavum_concha_depth_mm: 10.5,
        head_circumference_mm: 540.0,
        inter_tragal_distance_mm: 128.0,
        nose_bridge_prominence_mm: 11.0,
    }
}

fn preset_large() -> AnthropometricProfile {
    AnthropometricProfile {
        head_width_mm: 168.0,
        head_depth_mm: 212.0,
        pinna_height_mm: 74.0,
        pinna_width_mm: 32.0,
        cavum_concha_depth_mm: 14.5,
        head_circumference_mm: 600.0,
        inter_tragal_distance_mm: 152.0,
        nose_bridge_prominence_mm: 17.0,
    }
}

/// Generate and persist the three default `.ffhrtf` presets under
/// `out_dir`/{small,average,large}.  Each subdirectory becomes a complete
/// `.ffhrtf` bundle that can be loaded via `hrtf_load_ffhrtf`.
///
/// Returns:
/// *  `0` — all three presets written
/// * `-1` — invalid args (null path, bad UTF-8)
/// * `-2` — I/O error during write (partial state may exist on disk)
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_save_default_presets(
    out_dir: *const c_char,
    sample_rate: u32,
) -> i32 {
    if out_dir.is_null() {
        return -1;
    }
    let base_str = match unsafe { CStr::from_ptr(out_dir) }.to_str() {
        Ok(s) if !s.is_empty() => s,
        _ => return -1,
    };
    let base = std::path::PathBuf::from(base_str);
    let presets: [(&str, AnthropometricProfile); 3] = [
        ("small", preset_small()),
        ("average", AnthropometricProfile::default()),
        ("large", preset_large()),
    ];
    for (name, profile) in &presets {
        let db = personalize(*profile, sample_rate);
        let (mut manifest, dataset) =
            rf_spatial::binaural::export_database(&db, name, Some(*profile));
        manifest.subject_id = (*name).to_string();
        let dir = base.join(name);
        if rf_spatial::binaural::save_ffhrtf_dir(&dir, &manifest, &dataset)
            .is_err()
        {
            return -2;
        }
    }
    0
}

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
// OFFLINE BUFFER RENDER (HRTF P2 phase 1)
// ═══════════════════════════════════════════════════════════════════════════
//
// Render an arbitrary mono WAV file through the in-memory HRTF database to
// a stereo WAV at the user-picked (azimuth, elevation).  This is the offline
// counterpart of `hrtf_audition_render_to_wav` — same DSP path, but the
// source audio comes from disk instead of a synthesised test signal.
//
// This is the foundation for the upcoming P2 audio-thread integration:
// the offline path proves the BinauralRenderer × HrtfDatabase wiring is
// sample-accurate before we hook it into the realtime mixer.

/// Render `in_path` (mono or stereo source — stereo is summed to mono)
/// through the loaded HRTF DB at the supplied direction.
///
/// Returns the number of frames written to `out_path`, or:
/// *  `0` — empty input or write failure
/// * `-1` — no HRTF DB loaded
/// * `-2` — invalid argument (null path, bad UTF-8)
/// * `-3` — input file could not be read / decoded
/// * `-4` — output WAV write failed
///
/// `azimuth_deg` and `elevation_deg` follow the same convention as the
/// audition render: azimuth −180..+180 (0 front, +90 right), elevation
/// −90..+90 (0 ear-level, +90 above).
#[unsafe(no_mangle)]
pub extern "C" fn hrtf_render_buffer_to_wav(
    in_path: *const c_char,
    out_path: *const c_char,
    azimuth_deg: f32,
    elevation_deg: f32,
    gain: f32,
) -> i32 {
    let db_arc = match HRTF_DB.read().unwrap().as_ref() {
        Some(arc) => arc.clone(),
        None => return -1,
    };
    if in_path.is_null() || out_path.is_null() {
        return -2;
    }
    let in_str = match unsafe { CStr::from_ptr(in_path) }.to_str() {
        Ok(s) if !s.is_empty() => s,
        _ => return -2,
    };
    let out_str = match unsafe { CStr::from_ptr(out_path) }.to_str() {
        Ok(s) if !s.is_empty() => s,
        _ => return -2,
    };

    // ── Decode input ────────────────────────────────────────────────────
    let (mut mono, sample_rate) = match decode_wav_to_mono(in_str) {
        Ok(v) => v,
        Err(_) => return -3,
    };
    if mono.is_empty() {
        return 0;
    }

    // ── Apply user gain (clamped to ±1.0 range after) ───────────────────
    let g = gain.clamp(0.0, 4.0);
    if (g - 1.0).abs() > 1e-6 {
        for s in mono.iter_mut() {
            *s *= g;
        }
    }

    // ── Build BinauralRenderer matching the input sample rate ─────────────
    // The DB might be at a different SR; if so we still feed input frames
    // 1:1.  A future commit can resample first; for now we expose the
    // mismatch as a no-op (best-effort offline render).
    let mut renderer = BinauralRenderer::new(BinauralConfig::default(), sample_rate);
    renderer.set_hrtf_database((*db_arc).clone());

    let position = Position3D::from_spherical(azimuth_deg, elevation_deg, 1.5);
    let object = AudioObject {
        id: 0,
        name: "offline".into(),
        position,
        size: 0.0,
        gain: 1.0, // gain already baked into source
        audio: mono,
        sample_rate,
        automation: None,
    };

    let n_frames = object.audio.len();
    let mut output = vec![0.0f32; n_frames * 2];
    if renderer.render(&[object], &mut output, 2).is_err() {
        return -4;
    }

    // 5 ms fade-in/out to suppress edge clicks (same policy as audition).
    apply_fades(&mut output, sample_rate);

    // De-interleave for the rf_core writer (16-bit PCM stereo).
    let mut left = Vec::with_capacity(n_frames);
    let mut right = Vec::with_capacity(n_frames);
    for i in 0..n_frames {
        left.push(output[i * 2]);
        right.push(output[i * 2 + 1]);
    }
    if rf_core::wav_writer::write_wav(out_str, &left, &right, sample_rate).is_err() {
        return -4;
    }
    n_frames as i32
}

/// Decode a WAV file into mono f32 frames + the file's sample rate.
/// Stereo / multi-channel sources are summed to mono.  Uses `hound` so
/// PCM 16/24/32, IEEE float and ADPCM-free files all work without us
/// shipping a heavyweight decoder.
fn decode_wav_to_mono(path: &str) -> Result<(Vec<f32>, u32), Box<dyn std::error::Error>> {
    let mut reader = hound::WavReader::open(path)?;
    let spec = reader.spec();
    let channels = spec.channels.max(1) as usize;
    let sample_rate = spec.sample_rate;

    let frames: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => {
            let raw: Vec<f32> = reader
                .samples::<f32>()
                .map(|s| s.unwrap_or(0.0))
                .collect();
            sum_to_mono(&raw, channels)
        }
        hound::SampleFormat::Int => {
            // Normalise integer PCM to ±1 by dividing by 2^(bits-1).
            let bits = spec.bits_per_sample.max(1) as i32;
            let scale = 1.0f32 / ((1i64 << (bits - 1)) as f32);
            let raw: Vec<f32> = reader
                .samples::<i32>()
                .map(|s| s.map(|v| v as f32 * scale).unwrap_or(0.0))
                .collect();
            sum_to_mono(&raw, channels)
        }
    };

    Ok((frames, sample_rate))
}

fn sum_to_mono(interleaved: &[f32], channels: usize) -> Vec<f32> {
    if channels <= 1 {
        return interleaved.to_vec();
    }
    let frames = interleaved.len() / channels;
    let mut out = Vec::with_capacity(frames);
    let inv = 1.0 / channels as f32;
    for f in 0..frames {
        let mut sum = 0.0f32;
        for c in 0..channels {
            sum += interleaved[f * channels + c];
        }
        out.push(sum * inv);
    }
    out
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
    fn default_presets_writes_three_loadable_bundles() {
        let _g = TEST_MUTEX.lock().unwrap();
        let tmp = std::env::temp_dir().join("fluxforge_default_presets_test");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();
        let path_c = cstr(tmp.to_str().unwrap());

        let rc = hrtf_save_default_presets(path_c.as_ptr(), 48_000);
        assert_eq!(rc, 0);

        // Verify all three subdirectories exist and are loadable.
        for name in ["small", "average", "large"] {
            let sub = tmp.join(name);
            assert!(sub.is_dir(), "{name} preset dir missing");
            assert!(sub.join("manifest.json").exists());
            assert!(sub.join("hrir_left.raw").exists());

            // Load each one back into the global slot — proves the bundle
            // is byte-identical to a freshly generated one.
            let pc = cstr(sub.to_str().unwrap());
            let lc = hrtf_load_ffhrtf(pc.as_ptr());
            assert_eq!(lc, 0, "{name} load failed (rc={lc})");
            let meta = ffi_string(hrtf_metadata_json()).unwrap();
            let v: serde_json::Value = serde_json::from_str(&meta).unwrap();
            assert_eq!(v["sample_rate"].as_u64(), Some(48_000));
            assert!(v["measurement_count"].as_u64().unwrap() > 100);
        }

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn default_presets_rejects_null_path() {
        let _g = TEST_MUTEX.lock().unwrap();
        let rc = hrtf_save_default_presets(std::ptr::null(), 48_000);
        assert_eq!(rc, -1);
    }

    // ─── Offline buffer render tests (HRTF P2 phase 1) ─────────────────

    /// Helper — write a synthetic mono WAV that the renderer can decode.
    fn write_test_mono_wav(path: &std::path::Path, freq: f32, secs: f32) {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: 48_000,
            bits_per_sample: 32,
            sample_format: hound::SampleFormat::Float,
        };
        let mut w = hound::WavWriter::create(path, spec).unwrap();
        let n = (48_000.0 * secs) as usize;
        let two_pi = std::f32::consts::TAU;
        for i in 0..n {
            let t = i as f32 / 48_000.0;
            w.write_sample((two_pi * freq * t).sin() * 0.5).unwrap();
        }
        w.finalize().unwrap();
    }

    #[test]
    fn buffer_render_round_trip_produces_stereo_wav() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);

        let dir = std::env::temp_dir();
        let in_path = dir.join("fluxforge_buffer_in.wav");
        let out_path = dir.join("fluxforge_buffer_out.wav");
        let _ = std::fs::remove_file(&in_path);
        let _ = std::fs::remove_file(&out_path);
        write_test_mono_wav(&in_path, 440.0, 0.2);

        let in_c = cstr(in_path.to_str().unwrap());
        let out_c = cstr(out_path.to_str().unwrap());
        let frames = hrtf_render_buffer_to_wav(in_c.as_ptr(), out_c.as_ptr(), 45.0, 10.0, 1.0);
        assert!(frames > 0, "expected positive frame count, got {frames}");

        let reader = hound::WavReader::open(&out_path).expect("read out");
        let s = reader.spec();
        assert_eq!(s.channels, 2);
        assert_eq!(s.sample_rate, 48_000);
        assert!(reader.duration() > 0);

        let _ = std::fs::remove_file(&in_path);
        let _ = std::fs::remove_file(&out_path);
    }

    #[test]
    fn buffer_render_rejects_when_no_db() {
        let _g = TEST_MUTEX.lock().unwrap();
        *HRTF_DB.write().unwrap() = None;
        let in_c = cstr("/tmp/no_db_in.wav");
        let out_c = cstr("/tmp/no_db_out.wav");
        let rc = hrtf_render_buffer_to_wav(in_c.as_ptr(), out_c.as_ptr(), 0.0, 0.0, 1.0);
        assert_eq!(rc, -1);
    }

    #[test]
    fn buffer_render_rejects_null_paths() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);
        let dummy = cstr("/tmp/dummy.wav");
        assert_eq!(
            hrtf_render_buffer_to_wav(std::ptr::null(), dummy.as_ptr(), 0.0, 0.0, 1.0),
            -2
        );
        assert_eq!(
            hrtf_render_buffer_to_wav(dummy.as_ptr(), std::ptr::null(), 0.0, 0.0, 1.0),
            -2
        );
    }

    #[test]
    fn buffer_render_rejects_missing_input_file() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);
        let in_c = cstr("/tmp/this_file_does_not_exist_xyz.wav");
        let out_c = cstr("/tmp/should_not_be_written.wav");
        let rc = hrtf_render_buffer_to_wav(in_c.as_ptr(), out_c.as_ptr(), 0.0, 0.0, 1.0);
        assert_eq!(rc, -3);
    }

    #[test]
    fn buffer_render_clamps_extreme_gain() {
        let _g = TEST_MUTEX.lock().unwrap();
        assert_eq!(hrtf_generate_default(48_000), 0);

        let dir = std::env::temp_dir();
        let in_path = dir.join("fluxforge_gain_in.wav");
        let out_path = dir.join("fluxforge_gain_out.wav");
        let _ = std::fs::remove_file(&in_path);
        let _ = std::fs::remove_file(&out_path);
        write_test_mono_wav(&in_path, 440.0, 0.05);

        let in_c = cstr(in_path.to_str().unwrap());
        let out_c = cstr(out_path.to_str().unwrap());
        // 999.0 → clamped to 4.0 internally, render should still succeed
        let frames = hrtf_render_buffer_to_wav(in_c.as_ptr(), out_c.as_ptr(), 0.0, 0.0, 999.0);
        assert!(frames > 0);

        let _ = std::fs::remove_file(&in_path);
        let _ = std::fs::remove_file(&out_path);
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

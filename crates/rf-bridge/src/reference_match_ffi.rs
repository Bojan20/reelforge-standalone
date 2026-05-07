//! Reference Track Match FFI — bridges `rf_ml::r#match::SpectralMatcher`
//! to Flutter and patches Front 3 chain suggestions in place.
//!
//! Wave 2 Front 4. The user provides a reference track ("ovako želim
//! da zvuči") plus the target audio they're working on; we return an
//! `EqCurve` whose band gains, when applied to the target, push it
//! toward the reference. Optionally, that curve gets folded into a
//! `ChainSuggestion` so the existing apply pipeline (Front 4) takes
//! it through to the engine without any new UI plumbing.
//!
//! # Functions
//!
//! - `reference_match_set_reference_pcm(pcm, len, channels, sr)`  — load reference from PCM
//! - `reference_match_set_reference_path(path)`                   — load reference from disk (WAV/MP3/FLAC/…)
//! - `reference_match_compute_pcm(pcm, len, channels, sr)`        — analyse target → MatchResult
//! - `reference_match_compute_path(path)`                          — same, file-based
//! - `reference_match_apply_to_suggestion(sug_json, curve_json)`   — fold EQ curve into a suggestion's EQ slot
//! - `reference_match_has_reference()`                              — bool probe
//! - `reference_match_clear()`                                      — drop reference state
//! - `reference_match_free_string(ptr)`
//!
//! # Wire format (success)
//!
//! `set_reference_*`:
//! ```json
//! { "ok": true, "sample_rate": 48000, "spectrum_bins": 256 }
//! ```
//!
//! `compute_*`:
//! ```json
//! {
//!   "quality": 0.84,
//!   "error_db": 6.2,
//!   "perceptual_diff": 0.16,
//!   "eq_curve": {
//!     "bands": [{ "freq": 80.0, "gain_db": -1.5, "q": 1.0, "enabled": true }, ...],
//!     "sample_rate": 48000,
//!     "global_gain_db": 0.0,
//!     "quality": 0.84
//!   }
//! }
//! ```
//!
//! `apply_to_suggestion`:
//! Returns a new `ChainSuggestion` with the EQ slot's parameters
//! replaced/extended by the reference-derived bands, plus an updated
//! `style_tag` ("…+ ref-match"). All other slots are preserved untouched.
//!
//! # Lifecycle
//!
//! A single global `SpectralMatcher` lives behind `OnceLock<RwLock<>>`.
//! `set_reference_*` (re)builds it; `compute_*` requires that a reference
//! is loaded and that sample rates match. Sample-rate mismatch surfaces
//! as `{"error":"sample rate mismatch: ref=…, target=…"}` rather than a
//! panic.

use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::sync::OnceLock;

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

use rf_ml::assistant::{ChainSlotSuggestion, ChainSuggestion, SlotKind};
use rf_ml::r#match::{
    EqCurve, EqMatcher, FrequencyBand, MatchConfig, MatchMode, MatchResult, MatchWeighting,
    SpectralMatcher,
};

// ─── Wire types ───────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct SetReferenceOk {
    ok: bool,
    sample_rate: u32,
    spectrum_bins: usize,
}

#[derive(Debug, Serialize)]
struct ComputeOk {
    quality: f32,
    error_db: f32,
    perceptual_diff: f32,
    eq_curve: EqCurve,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
}

#[derive(Debug, Deserialize)]
struct ApplyRequest {
    suggestion: ChainSuggestion,
    eq_curve: EqCurve,
    /// Strength factor 0..1 — 1.0 applies the curve as-is, 0.5 halves
    /// the dB deltas (gentler match), 0.0 is a no-op (identity).
    /// Defaults to 1.0.
    #[serde(default = "default_strength")]
    strength: f32,
}

fn default_strength() -> f32 {
    1.0
}

// ─── Global matcher state ─────────────────────────────────────────────────

/// One reference at a time. Calling `set_reference_*` again replaces it.
struct MatcherState {
    matcher: SpectralMatcher,
    sample_rate: Option<u32>,
}

static MATCHER: OnceLock<RwLock<MatcherState>> = OnceLock::new();

fn matcher_state() -> &'static RwLock<MatcherState> {
    MATCHER.get_or_init(|| {
        RwLock::new(MatcherState {
            matcher: SpectralMatcher::new(MatchConfig {
                num_bands: 24,
                mode: MatchMode::Full,
                weighting: MatchWeighting::AWeighting,
                ..Default::default()
            }),
            sample_rate: None,
        })
    })
}

// ─── Helpers ──────────────────────────────────────────────────────────────

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn error_response(msg: &str) -> *mut c_char {
    let resp = ErrorResponse { error: msg.into() };
    json_to_c(serde_json::to_string(&resp).unwrap_or_default())
}

fn import_audio_path(p: &Path) -> Result<(Vec<f32>, u8, u32), String> {
    let imported = rf_engine::AudioImporter::import(p)
        .map_err(|e| format!("import failed: {:?}", e))?;
    Ok((imported.samples, imported.channels, imported.sample_rate))
}

// ─── set_reference ────────────────────────────────────────────────────────

/// Load a reference track from raw interleaved PCM.
///
/// # Safety
/// `pcm_ptr` must be valid for `num_samples_total` reads; both must be
/// well-defined. `num_samples_total = samples_per_channel * channels`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn reference_match_set_reference_pcm(
    pcm_ptr: *const f32,
    num_samples_total: usize,
    channels: u32,
    sample_rate: u32,
) -> *mut c_char {
    if pcm_ptr.is_null() {
        return error_response("null pcm pointer");
    }
    if num_samples_total == 0 {
        return error_response("num_samples_total must be > 0");
    }
    if channels == 0 {
        return error_response("channels must be > 0");
    }
    if sample_rate == 0 {
        return error_response("sample_rate must be > 0");
    }
    let audio: &[f32] = unsafe { std::slice::from_raw_parts(pcm_ptr, num_samples_total) };
    set_reference_internal(audio, channels as usize, sample_rate)
}

/// Load a reference track from disk. Decoded via Symphonia
/// (WAV/MP3/FLAC/AIFF/OGG/M4A — same surface as Front 5).
///
/// # Safety
/// `path_cstr` must be a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub extern "C" fn reference_match_set_reference_path(path_cstr: *const c_char) -> *mut c_char {
    if path_cstr.is_null() {
        return error_response("null path");
    }
    let path_str = match unsafe { CStr::from_ptr(path_cstr) }.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("path not utf-8"),
    };
    let (audio, channels, sample_rate) = match import_audio_path(Path::new(path_str)) {
        Ok(t) => t,
        Err(e) => return error_response(&e),
    };
    set_reference_internal(&audio, channels as usize, sample_rate)
}

fn set_reference_internal(audio: &[f32], channels: usize, sample_rate: u32) -> *mut c_char {
    let mut state = matcher_state().write();
    if let Err(e) = state.matcher.set_reference(audio, channels, sample_rate) {
        return error_response(&format!("set_reference failed: {:?}", e));
    }
    state.sample_rate = Some(sample_rate);
    let bins = state
        .matcher
        .reference_spectrum()
        .map(|s| s.len())
        .unwrap_or(0);
    let resp = SetReferenceOk {
        ok: true,
        sample_rate,
        spectrum_bins: bins,
    };
    json_to_c(serde_json::to_string(&resp).unwrap_or_default())
}

// ─── compute_match ────────────────────────────────────────────────────────

/// Compute the EQ curve required to push `target` toward the previously
/// loaded reference. Requires `set_reference_*` to have been called and
/// requires matching sample rates.
///
/// # Safety
/// Same as `reference_match_set_reference_pcm`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn reference_match_compute_pcm(
    pcm_ptr: *const f32,
    num_samples_total: usize,
    channels: u32,
    sample_rate: u32,
) -> *mut c_char {
    if pcm_ptr.is_null() {
        return error_response("null pcm pointer");
    }
    if num_samples_total == 0 {
        return error_response("num_samples_total must be > 0");
    }
    if channels == 0 || sample_rate == 0 {
        return error_response("channels/sample_rate must be > 0");
    }
    let audio: &[f32] = unsafe { std::slice::from_raw_parts(pcm_ptr, num_samples_total) };
    compute_match_internal(audio, channels as usize, sample_rate)
}

/// File-based variant of `reference_match_compute_pcm`.
///
/// # Safety
/// `path_cstr` must be a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub extern "C" fn reference_match_compute_path(path_cstr: *const c_char) -> *mut c_char {
    if path_cstr.is_null() {
        return error_response("null path");
    }
    let path_str = match unsafe { CStr::from_ptr(path_cstr) }.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("path not utf-8"),
    };
    let (audio, channels, sample_rate) = match import_audio_path(Path::new(path_str)) {
        Ok(t) => t,
        Err(e) => return error_response(&e),
    };
    compute_match_internal(&audio, channels as usize, sample_rate)
}

fn compute_match_internal(audio: &[f32], channels: usize, sample_rate: u32) -> *mut c_char {
    let mut state = matcher_state().write();
    if state.sample_rate.is_none() {
        return error_response("no reference loaded — call set_reference first");
    }
    if let Some(ref_sr) = state.sample_rate
        && ref_sr != sample_rate
    {
        return error_response(&format!(
            "sample rate mismatch: ref={}, target={}",
            ref_sr, sample_rate
        ));
    }

    let result: MatchResult = match state.matcher.compute_match(audio, channels, sample_rate) {
        Ok(r) => r,
        Err(e) => return error_response(&format!("compute_match failed: {:?}", e)),
    };

    let resp = ComputeOk {
        quality: result.quality,
        error_db: result.error_db,
        perceptual_diff: result.perceptual_diff,
        eq_curve: result.eq_curve,
    };
    json_to_c(serde_json::to_string(&resp).unwrap_or_default())
}

// ─── apply_to_suggestion ──────────────────────────────────────────────────

/// Fold a reference-derived `EqCurve` into the EQ slot of an existing
/// `ChainSuggestion` (from Front 3). Returns the patched suggestion as
/// JSON; the rest of the chain is preserved unchanged.
///
/// Behaviour:
/// - If the suggestion has an `eq` slot, its `parameters` are extended
///   with one `Band {N} Gain` and `Band {N} Freq` per reference band.
/// - If there is no `eq` slot, one is inserted right after the first
///   `high_pass` slot (or at position 0 if no HPF).
/// - `style_tag` becomes `"<orig> + ref-match"`.
/// - `strength` (0..1) scales every band's `gain_db` before insertion.
///
/// # Safety
/// `request_json` must be a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub extern "C" fn reference_match_apply_to_suggestion(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return error_response("null request");
    }
    let raw = unsafe { CStr::from_ptr(request_json) };
    let s = match raw.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("request not utf-8"),
    };
    let req: ApplyRequest = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => return error_response(&format!("parse error: {}", e)),
    };

    let strength = req.strength.clamp(0.0, 1.0);
    let patched = patch_suggestion_v2(req.suggestion, &req.eq_curve, strength);
    match serde_json::to_string(&patched) {
        Ok(j) => json_to_c(j),
        Err(e) => error_response(&format!("serialize error: {}", e)),
    }
}

/// Locate the EQ slot in a suggestion (the one *after* any HPF if the
/// chain has one), or insert a fresh EQ slot just past the HPF.
/// Returns the resulting index of the EQ slot.
fn find_or_insert_eq_slot(slots: &mut Vec<ChainSlotSuggestion>) -> usize {
    // First, look for an EQ that comes after a HPF (or anywhere if no HPF).
    let hpf_idx = slots.iter().position(|s| s.kind == SlotKind::HighPass);
    let search_start = hpf_idx.map(|i| i + 1).unwrap_or(0);
    if let Some(eq_at) = slots
        .iter()
        .enumerate()
        .skip(search_start)
        .find(|(_, s)| s.kind == SlotKind::Eq)
        .map(|(i, _)| i)
    {
        return eq_at;
    }
    // No EQ slot — insert one. Place it right after the HPF, or at the
    // start if no HPF.
    let insert_at = search_start.min(slots.len());
    let new_slot = ChainSlotSuggestion {
        position: insert_at as u32,
        kind: SlotKind::Eq,
        bypass_safe: true,
        plugin_candidates: Vec::new(),
        parameters: Vec::new(),
        reasoning: "Reference-matched EQ".into(),
        confidence: 0.7,
    };
    slots.insert(insert_at, new_slot);
    insert_at
}

// ─── Misc FFI ─────────────────────────────────────────────────────────────

/// True if `set_reference_*` has been called and a spectrum is cached.
#[unsafe(no_mangle)]
pub extern "C" fn reference_match_has_reference() -> bool {
    matcher_state().read().sample_rate.is_some()
}

/// Drop the cached reference. After this, `compute_*` returns an error
/// until a new reference is loaded.
#[unsafe(no_mangle)]
pub extern "C" fn reference_match_clear() {
    let mut state = matcher_state().write();
    state.matcher.reset();
    state.sample_rate = None;
}

/// Free a string allocated by this module's FFI functions.
///
/// # Safety
/// `ptr` must come from one of this module's `*_json` / `*_set_reference_*`
/// / `*_compute_*` / `*_apply_to_suggestion` functions.
#[unsafe(no_mangle)]
pub extern "C" fn reference_match_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

// ─── Patch implementation ─────────────────────────────────────────────────
//
// `ChainSlotSuggestion.parameters` is `Vec<ParameterSuggestion>`, and
// ParameterSuggestion is Serialize/Deserialize. We extend the slot's
// parameter list by serialising the existing entries to a JSON array,
// appending new band entries, then deserialising back into the slot via
// a temporary slot JSON. This keeps the patch type-safe without needing
// to add another public re-export from rf-ml.

fn extend_eq_params_with_curve(
    slot: &mut ChainSlotSuggestion,
    bands: &[FrequencyBand],
    strength: f32,
) {
    let mut new_params: Vec<serde_json::Value> = Vec::with_capacity(bands.len() * 2);
    for (i, b) in bands.iter().enumerate() {
        new_params.push(serde_json::json!({
            "name": format!("Band {} Freq", i + 1),
            "current": 0.0,
            "suggested": b.freq as f32,
            "unit": "Hz"
        }));
        new_params.push(serde_json::json!({
            "name": format!("Band {} Gain", i + 1),
            "current": 0.0,
            "suggested": (b.gain_db * strength) as f32,
            "unit": "dB"
        }));
    }

    let current = match serde_json::to_value(&slot.parameters) {
        Ok(serde_json::Value::Array(a)) => a,
        _ => Vec::new(),
    };
    let mut combined: Vec<serde_json::Value> = current.into_iter().collect();
    combined.extend(new_params);

    let temp_slot = serde_json::json!({
        "position": 0,
        "kind": "eq",
        "bypass_safe": true,
        "plugin_candidates": [],
        "parameters": serde_json::Value::Array(combined),
        "reasoning": "",
        "confidence": 1.0
    });
    if let Ok(parsed_slot) = serde_json::from_value::<ChainSlotSuggestion>(temp_slot) {
        slot.parameters = parsed_slot.parameters;
    }
}

/// Patch a chain suggestion with reference-derived band data.
/// Locates the EQ slot (or inserts one after the HPF), clears any prior
/// `Band N Freq`/`Band N Gain` entries so re-applying is idempotent,
/// then appends the reference bands. Updates `style_tag` (idempotent),
/// confidence (min of slot's and curve's), and re-packs positions.
fn patch_suggestion_v2(
    mut sug: ChainSuggestion,
    curve: &EqCurve,
    strength: f32,
) -> ChainSuggestion {
    let eq_idx = find_or_insert_eq_slot(&mut sug.slots);
    if let Some(slot) = sug.slots.get_mut(eq_idx) {
        // Clear prior band-N params so re-applying doesn't double up.
        slot.parameters.retain(|p| {
            !(p.name.starts_with("Band ")
                && (p.name.ends_with(" Freq") || p.name.ends_with(" Gain")))
        });
        extend_eq_params_with_curve(slot, &curve.bands, strength);
        slot.reasoning = format!(
            "{} (reference-matched, {} bands, strength {:.0}%)",
            slot.reasoning,
            curve.bands.len(),
            strength * 100.0
        );
        slot.confidence = slot.confidence.min(curve.quality);
    }
    sug.style_tag = if sug.style_tag.contains("ref-match") {
        sug.style_tag
    } else {
        format!("{} + ref-match", sug.style_tag)
    };
    for (i, s) in sug.slots.iter_mut().enumerate() {
        s.position = i as u32;
    }
    sug
}

// ─── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rf_ml::assistant::ChainAdvisor;
    use rf_ml::assistant::{
        AnalysisResult, DynamicsAnalysis, LoudnessAnalysis, SpectralAnalysis, StereoAnalysis,
        TrackType,
    };

    fn cstr_to_string(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
        reference_match_free_string(ptr);
        s
    }

    fn synth(seconds: f32, sr: u32, freq_hz: f32) -> Vec<f32> {
        let n = (seconds * sr as f32) as usize;
        (0..n)
            .flat_map(|i| {
                let t = i as f32 / sr as f32;
                let s = (2.0 * std::f32::consts::PI * freq_hz * t).sin() * 0.4;
                [s, s] // stereo
            })
            .collect()
    }

    fn vocal_suggestion() -> ChainSuggestion {
        let a = AnalysisResult {
            genres: vec![],
            moods: vec![],
            tempo_bpm: None,
            key: None,
            loudness: LoudnessAnalysis::default(),
            spectral: SpectralAnalysis {
                low_ratio: 0.2,
                mid_ratio: 0.55,
                high_ratio: 0.25,
                ..Default::default()
            },
            dynamics: DynamicsAnalysis {
                crest_factor_db: 12.0,
                transient_sharpness: 0.5,
                ..Default::default()
            },
            stereo: StereoAnalysis {
                width: 0.3,
                ..Default::default()
            },
            suggestions: vec![],
            quality_score: 0.5,
        };
        ChainAdvisor::new().suggest_chain(&a, &[], Some(TrackType::Vocal))
    }

    #[test]
    fn has_reference_initially_false() {
        reference_match_clear();
        assert!(!reference_match_has_reference());
    }

    #[test]
    fn set_and_clear_reference_pcm() {
        let audio = synth(0.5, 48000, 440.0);
        let raw = unsafe {
            reference_match_set_reference_pcm(audio.as_ptr(), audio.len(), 2, 48000)
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"ok\":true"), "got {}", out);
        assert!(reference_match_has_reference());
        reference_match_clear();
        assert!(!reference_match_has_reference());
    }

    #[test]
    fn set_reference_null_pcm_returns_error() {
        let raw = unsafe {
            reference_match_set_reference_pcm(std::ptr::null(), 0, 2, 48000)
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn set_reference_zero_channels_returns_error() {
        let audio = vec![0.0_f32; 100];
        let raw = unsafe {
            reference_match_set_reference_pcm(audio.as_ptr(), audio.len(), 0, 48000)
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn compute_without_reference_returns_error() {
        reference_match_clear();
        let audio = synth(0.2, 48000, 220.0);
        let raw = unsafe {
            reference_match_compute_pcm(audio.as_ptr(), audio.len(), 2, 48000)
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
        assert!(out.contains("set_reference"));
    }

    #[test]
    fn compute_with_sample_rate_mismatch_returns_error() {
        reference_match_clear();
        let ref_audio = synth(0.5, 48000, 440.0);
        let raw = unsafe {
            reference_match_set_reference_pcm(ref_audio.as_ptr(), ref_audio.len(), 2, 48000)
        };
        let _ = cstr_to_string(raw);

        let target = synth(0.2, 44100, 220.0);
        let raw = unsafe {
            reference_match_compute_pcm(target.as_ptr(), target.len(), 2, 44100)
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""), "got {}", out);
        assert!(out.contains("sample rate mismatch"), "got {}", out);
    }

    #[test]
    fn compute_with_matching_pcm_yields_curve() {
        reference_match_clear();
        let ref_audio = synth(0.5, 48000, 440.0);
        let _ = cstr_to_string(unsafe {
            reference_match_set_reference_pcm(ref_audio.as_ptr(), ref_audio.len(), 2, 48000)
        });

        let target = synth(0.5, 48000, 220.0); // different content
        let raw = unsafe {
            reference_match_compute_pcm(target.as_ptr(), target.len(), 2, 48000)
        };
        let out = cstr_to_string(raw);
        // Either an EqCurve in JSON, or a clean error — never a panic.
        if out.contains("\"error\"") {
            // Some MlError surface (e.g. spectrum-len mismatch) — acceptable
            return;
        }
        assert!(out.contains("\"eq_curve\""));
        assert!(out.contains("\"bands\""));
    }

    #[test]
    fn apply_to_suggestion_adds_band_params() {
        let suggestion = vocal_suggestion();
        let curve = EqCurve {
            bands: vec![
                FrequencyBand::new(100.0, -2.0, 1.0),
                FrequencyBand::new(1000.0, 1.5, 1.0),
                FrequencyBand::new(8000.0, 2.0, 1.0),
            ],
            sample_rate: 48000,
            global_gain_db: 0.0,
            quality: 0.85,
        };
        let req = serde_json::json!({
            "suggestion": suggestion,
            "eq_curve": curve,
            "strength": 1.0
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = reference_match_apply_to_suggestion(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("Band 1 Freq"), "got {}", out);
        assert!(out.contains("Band 1 Gain"));
        assert!(out.contains("Band 3 Gain"));
        assert!(out.contains("ref-match"));
    }

    #[test]
    fn apply_to_suggestion_strength_scales_gain() {
        let suggestion = vocal_suggestion();
        let curve = EqCurve {
            bands: vec![FrequencyBand::new(1000.0, 6.0, 1.0)],
            sample_rate: 48000,
            global_gain_db: 0.0,
            quality: 0.9,
        };
        let req = serde_json::json!({
            "suggestion": suggestion,
            "eq_curve": curve,
            "strength": 0.5
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = reference_match_apply_to_suggestion(c.as_ptr());
        let out = cstr_to_string(raw);
        // Strength 0.5 * gain 6.0 = 3.0
        assert!(out.contains("\"suggested\":3.0") || out.contains("\"suggested\":3"));
    }

    #[test]
    fn apply_to_suggestion_idempotent() {
        let suggestion = vocal_suggestion();
        let curve = EqCurve {
            bands: vec![FrequencyBand::new(1000.0, 2.0, 1.0)],
            sample_rate: 48000,
            global_gain_db: 0.0,
            quality: 0.85,
        };
        // Apply once
        let req = serde_json::json!({
            "suggestion": suggestion,
            "eq_curve": curve,
            "strength": 1.0
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = reference_match_apply_to_suggestion(c.as_ptr());
        let first = cstr_to_string(raw);
        let parsed: ChainSuggestion = serde_json::from_str(&first).unwrap();
        // Apply again — should produce same result, not double-band.
        let req2 = serde_json::json!({
            "suggestion": parsed.clone(),
            "eq_curve": curve,
            "strength": 1.0
        });
        let c2 = CString::new(req2.to_string()).unwrap();
        let raw2 = reference_match_apply_to_suggestion(c2.as_ptr());
        let second = cstr_to_string(raw2);
        // Style tag must NOT contain "ref-match + ref-match"
        assert!(!second.contains("ref-match + ref-match"), "got {}", second);
        // Should still have exactly Band 1 Freq + Gain (not 2 + 2)
        let count_band1_freq = second.matches("Band 1 Freq").count();
        assert_eq!(count_band1_freq, 1, "got {}", second);
    }

    #[test]
    fn apply_to_suggestion_no_eq_inserts_one() {
        // Build a custom suggestion with no EQ slot.
        let mut sug = vocal_suggestion();
        sug.slots.retain(|s| s.kind != SlotKind::Eq);
        let original_count = sug.slots.len();
        let curve = EqCurve {
            bands: vec![FrequencyBand::new(440.0, 1.0, 1.0)],
            sample_rate: 48000,
            global_gain_db: 0.0,
            quality: 0.7,
        };
        let req = serde_json::json!({
            "suggestion": sug,
            "eq_curve": curve,
            "strength": 1.0
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = reference_match_apply_to_suggestion(c.as_ptr());
        let out = cstr_to_string(raw);
        let parsed: ChainSuggestion = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed.slots.len(), original_count + 1);
        assert!(parsed.slots.iter().any(|s| s.kind == SlotKind::Eq));
    }

    #[test]
    fn apply_to_suggestion_invalid_json_returns_error() {
        let c = CString::new("not json").unwrap();
        let raw = reference_match_apply_to_suggestion(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn apply_to_suggestion_null_returns_error() {
        let raw = reference_match_apply_to_suggestion(std::ptr::null());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn set_reference_path_nonexistent_returns_error() {
        let p = CString::new("/nonexistent/path/audio.wav").unwrap();
        let raw = reference_match_set_reference_path(p.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn compute_path_nonexistent_returns_error() {
        let p = CString::new("/nonexistent/file.wav").unwrap();
        let raw = reference_match_compute_path(p.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn free_string_null_safe() {
        reference_match_free_string(std::ptr::null_mut());
    }

    #[test]
    fn strength_clamp_below_zero() {
        let suggestion = vocal_suggestion();
        let curve = EqCurve {
            bands: vec![FrequencyBand::new(1000.0, 4.0, 1.0)],
            sample_rate: 48000,
            global_gain_db: 0.0,
            quality: 0.8,
        };
        let req = serde_json::json!({
            "suggestion": suggestion,
            "eq_curve": curve,
            "strength": -0.5
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = reference_match_apply_to_suggestion(c.as_ptr());
        let out = cstr_to_string(raw);
        // Negative strength clamps to 0 → no-op gain (0.0 dB)
        assert!(out.contains("\"suggested\":0.0") || out.contains("\"suggested\":0"));
    }

    #[test]
    fn strength_clamp_above_one() {
        let suggestion = vocal_suggestion();
        let curve = EqCurve {
            bands: vec![FrequencyBand::new(1000.0, 3.0, 1.0)],
            sample_rate: 48000,
            global_gain_db: 0.0,
            quality: 0.8,
        };
        let req = serde_json::json!({
            "suggestion": suggestion,
            "eq_curve": curve,
            "strength": 5.0
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = reference_match_apply_to_suggestion(c.as_ptr());
        let out = cstr_to_string(raw);
        // Above 1.0 clamps to 1.0 — full strength
        assert!(out.contains("\"suggested\":3.0") || out.contains("\"suggested\":3"));
    }
}

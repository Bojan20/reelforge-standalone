//! Chain Auto-Pipeline FFI — one call: audio → analyzer → advisor → applier.
//!
//! This is the production "magic button". The client passes raw PCM (or
//! a path to a WAV/MP3/FLAC file), the user's plugin library, and
//! whatever knobs they want to override; the pipeline returns:
//!
//!   * The analysis features the advisor saw
//!   * The full chain suggestion (slot order, plugin candidates, params)
//!   * The apply plan ready to execute
//!   * Optionally, the execute result (dry-run or live)
//!
//! Front 1–4 built infrastructure; Front 5 wires it together so the UI
//! has a single FFI entry point.
//!
//! # Functions
//!
//! - `chain_auto_pipeline_pcm_json(pcm_ptr, len, channels, sample_rate, request_json) -> *mut c_char`
//! - `chain_auto_pipeline_path_json(audio_path, request_json) -> *mut c_char`
//! - `chain_auto_free_string(ptr)`
//!
//! # Request shape
//!
//! ```json
//! {
//!   "plugins": [{"id":"...", "name":"...", "vendor":"..."}],
//!   "track_id": 42,                                    // for plan + execute
//!   "current_chain": [...],                            // CurrentSlotState array
//!   "track_hint": "vocal",                             // optional
//!   "advisor": {"target_lufs": -14.0, "vintage_bias": false},
//!   "policy": {"plugin_strategy": "internal_only"},
//!   "execute_mode": "dry_run" | "real" | "skip"        // default: skip
//! }
//! ```
//!
//! # Response shape
//!
//! ```json
//! {
//!   "analysis":   { ... lossless echo of features the advisor used ... },
//!   "suggestion": { ... ChainSuggestion ... },
//!   "plan":       { ... ApplyPlan ... },
//!   "execute":    { ... ExecuteResult or null ... }
//! }
//! ```

use std::ffi::{c_char, CStr, CString};
use std::path::Path;

use rf_ml::assistant::{
    AdvisorConfig, AnalysisResult, AudioAnalyzer, AudioAssistantTrait, AvailablePlugin,
    ChainAdvisor, ChainApplier, ChainSuggestion, CurrentChainState, CurrentSlotState,
    PluginPickStrategy, ApplyPlan, ApplyPolicy, AssistantConfig, TrackType,
};
use serde::{Deserialize, Serialize};

// ─── Request types ────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct PipelineRequest {
    #[serde(default)]
    plugins: Vec<PluginIn>,
    #[serde(default)]
    track_id: u32,
    #[serde(default)]
    current_chain: Vec<CurrentSlotState>,
    #[serde(default)]
    track_hint: Option<String>,
    #[serde(default)]
    advisor: Option<AdvisorIn>,
    #[serde(default)]
    policy: Option<PolicyIn>,
    #[serde(default)]
    execute_mode: Option<String>, // "dry_run" | "real" | "skip"
}

#[derive(Debug, Deserialize)]
struct PluginIn {
    id: String,
    name: String,
    #[serde(default)]
    vendor: String,
}

#[derive(Debug, Deserialize, Default)]
struct AdvisorIn {
    #[serde(default)]
    target_lufs: Option<f32>,
    #[serde(default)]
    vintage_bias: Option<bool>,
    #[serde(default)]
    corrective_aggressiveness: Option<f32>,
}

#[derive(Debug, Deserialize, Default)]
struct PolicyIn {
    #[serde(default)]
    plugin_strategy: Option<String>,
    #[serde(default)]
    preserve_matching_slots: Option<bool>,
    #[serde(default)]
    overwrite_preserved_params: Option<bool>,
}

// ─── Response types ───────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct PipelineResponse {
    analysis: AnalysisDigest,
    suggestion: ChainSuggestion,
    plan: ApplyPlan,
    execute: Option<serde_json::Value>,
}

/// Compact, JSON-friendly digest of `AnalysisResult`. (The full
/// AnalysisResult uses non-serde types like Genre — this digest exposes
/// what the UI actually wants to display.)
#[derive(Debug, Serialize)]
struct AnalysisDigest {
    integrated_lufs: f32,
    true_peak_db: f32,
    loudness_range: f32,
    spectral_low_ratio: f32,
    spectral_mid_ratio: f32,
    spectral_high_ratio: f32,
    spectral_brightness: f32,
    crest_factor_db: f32,
    transient_sharpness: f32,
    stereo_width: f32,
    stereo_correlation: f32,
    quality_score: f32,
}

impl From<&AnalysisResult> for AnalysisDigest {
    fn from(a: &AnalysisResult) -> Self {
        Self {
            integrated_lufs: a.loudness.integrated_lufs,
            true_peak_db: a.loudness.true_peak_db,
            loudness_range: a.loudness.loudness_range,
            spectral_low_ratio: a.spectral.low_ratio,
            spectral_mid_ratio: a.spectral.mid_ratio,
            spectral_high_ratio: a.spectral.high_ratio,
            spectral_brightness: a.spectral.brightness,
            crest_factor_db: a.dynamics.crest_factor_db,
            transient_sharpness: a.dynamics.transient_sharpness,
            stereo_width: a.stereo.width,
            stereo_correlation: a.stereo.correlation,
            quality_score: a.quality_score,
        }
    }
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
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

fn parse_track_hint(s: &str) -> Option<TrackType> {
    match s.to_lowercase().as_str() {
        "vocal" => Some(TrackType::Vocal),
        "drums" | "drum" => Some(TrackType::Drums),
        "bass" => Some(TrackType::Bass),
        "guitar" => Some(TrackType::Guitar),
        "synth" => Some(TrackType::Synth),
        "keys" | "piano" | "keyboard" => Some(TrackType::Keys),
        "fullmix" | "full_mix" | "mix" => Some(TrackType::FullMix),
        "master" | "mastering" => Some(TrackType::Master),
        "unknown" => Some(TrackType::Unknown),
        _ => None,
    }
}

fn parse_strategy(s: &str) -> PluginPickStrategy {
    match s.to_lowercase().as_str() {
        "internal_only" | "internal" => PluginPickStrategy::InternalOnly,
        "external_only" | "external" => PluginPickStrategy::ExternalOnly,
        _ => PluginPickStrategy::PreferExternal,
    }
}

fn build_advisor_config(a: Option<AdvisorIn>) -> AdvisorConfig {
    let mut out = AdvisorConfig::default();
    if let Some(a) = a {
        if let Some(v) = a.target_lufs {
            out.target_lufs = v;
        }
        if let Some(v) = a.vintage_bias {
            out.vintage_bias = v;
        }
        if let Some(v) = a.corrective_aggressiveness {
            out.corrective_aggressiveness = v.clamp(0.0, 1.0);
        }
    }
    out
}

fn build_policy(p: Option<PolicyIn>) -> ApplyPolicy {
    let mut out = ApplyPolicy::default();
    if let Some(p) = p {
        if let Some(s) = p.plugin_strategy {
            out.plugin_strategy = parse_strategy(&s);
        }
        if let Some(v) = p.preserve_matching_slots {
            out.preserve_matching_slots = v;
        }
        if let Some(v) = p.overwrite_preserved_params {
            out.overwrite_preserved_params = v;
        }
    }
    out
}

// ─── Core pipeline ────────────────────────────────────────────────────────

/// Run analyzer → advisor → planner → (optional) executor.
fn run_pipeline(
    audio: &[f32],
    channels: usize,
    sample_rate: u32,
    req: PipelineRequest,
) -> Result<PipelineResponse, String> {
    if audio.is_empty() {
        return Err("audio buffer is empty".into());
    }
    if channels == 0 {
        return Err("channels must be > 0".into());
    }
    if sample_rate == 0 {
        return Err("sample_rate must be > 0".into());
    }

    // 1. Analyze
    let mut analyzer = AudioAnalyzer::new(AssistantConfig::default());
    let analysis = analyzer
        .analyze(audio, channels, sample_rate)
        .map_err(|e| format!("analyze failed: {:?}", e))?;

    // 2. Advise
    let advisor = ChainAdvisor::with_config(build_advisor_config(req.advisor));
    let plugins: Vec<AvailablePlugin> = req
        .plugins
        .into_iter()
        .map(|p| AvailablePlugin {
            id: p.id,
            name: p.name,
            vendor: p.vendor,
        })
        .collect();
    let hint = req.track_hint.as_deref().and_then(parse_track_hint);
    let suggestion: ChainSuggestion = advisor.suggest_chain(&analysis, &plugins, hint);

    // 3. Plan
    let policy = build_policy(req.policy);
    let applier = ChainApplier::with_policy(policy);
    let current = CurrentChainState {
        track_id: req.track_id,
        slots: req.current_chain,
    };
    let plan: ApplyPlan = applier.plan(&suggestion, &current);

    // 4. Execute (optional)
    let execute = match req.execute_mode.as_deref().unwrap_or("skip") {
        "skip" => None,
        "dry_run" => Some(serde_json::to_value(execute_via_chain_apply(&plan, true))
            .unwrap_or(serde_json::Value::Null)),
        "real" => Some(serde_json::to_value(execute_via_chain_apply(&plan, false))
            .unwrap_or(serde_json::Value::Null)),
        other => return Err(format!("unknown execute_mode '{}'", other)),
    };

    Ok(PipelineResponse {
        analysis: AnalysisDigest::from(&analysis),
        suggestion,
        plan,
        execute,
    })
}

/// Bridge to chain_apply_ffi's executor without going through the FFI
/// boundary twice. We replicate the small executor logic here so the
/// auto-pipeline doesn't have to round-trip through CStrings.
fn execute_via_chain_apply(plan: &ApplyPlan, dry_run: bool) -> serde_json::Value {
    // Build the same JSON contract chain_apply_execute_json uses.
    let req = serde_json::json!({
        "plan": plan,
        "dry_run": dry_run,
    });
    let cstr = match CString::new(req.to_string()) {
        Ok(c) => c,
        Err(_) => return serde_json::json!({"error": "failed to build execute request"}),
    };
    let raw = crate::chain_apply_ffi::chain_apply_execute_json(cstr.as_ptr());
    if raw.is_null() {
        return serde_json::Value::Null;
    }
    let s = unsafe { CStr::from_ptr(raw) }.to_string_lossy().to_string();
    crate::chain_apply_ffi::chain_apply_free_string(raw);
    serde_json::from_str(&s).unwrap_or(serde_json::Value::Null)
}

fn parse_request(req_json: *const c_char) -> Result<PipelineRequest, String> {
    if req_json.is_null() {
        return Err("null request".into());
    }
    let raw = unsafe { CStr::from_ptr(req_json) };
    let s = raw.to_str().map_err(|_| "request not utf-8".to_string())?;
    serde_json::from_str(s).map_err(|e| format!("parse error: {}", e))
}

// ─── FFI surface ──────────────────────────────────────────────────────────

/// Run the full pipeline against an in-memory PCM buffer.
///
/// `pcm_ptr` is interleaved f32 audio (`-1.0..=1.0`) of length
/// `num_samples_total = num_samples_per_channel * channels`.
///
/// # Safety
/// `pcm_ptr` must be valid for `num_samples_total` reads, properly
/// aligned for f32. `request_json` must be a NUL-terminated UTF-8
/// string. The returned pointer must be freed via
/// `chain_auto_free_string`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn chain_auto_pipeline_pcm_json(
    pcm_ptr: *const f32,
    num_samples_total: usize,
    channels: u32,
    sample_rate: u32,
    request_json: *const c_char,
) -> *mut c_char {
    if pcm_ptr.is_null() {
        return error_response("null pcm pointer");
    }
    if num_samples_total == 0 {
        return error_response("num_samples_total must be > 0");
    }
    let req = match parse_request(request_json) {
        Ok(r) => r,
        Err(e) => return error_response(&e),
    };
    let audio: &[f32] = unsafe { std::slice::from_raw_parts(pcm_ptr, num_samples_total) };
    match run_pipeline(audio, channels as usize, sample_rate, req) {
        Ok(resp) => match serde_json::to_string(&resp) {
            Ok(j) => json_to_c(j),
            Err(e) => error_response(&format!("serialize error: {}", e)),
        },
        Err(e) => error_response(&e),
    }
}

/// Run the full pipeline against an audio file on disk.
///
/// The file is decoded via Symphonia (WAV/MP3/FLAC/etc., the same
/// codecs `ImportedAudio::import` supports). For very long files,
/// the analyzer reads all samples — caller may pre-truncate via
/// PCM API for cheaper analysis windows.
///
/// # Safety
/// `audio_path` and `request_json` must be NUL-terminated UTF-8
/// strings. Returned pointer must be freed via
/// `chain_auto_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_auto_pipeline_path_json(
    audio_path: *const c_char,
    request_json: *const c_char,
) -> *mut c_char {
    if audio_path.is_null() {
        return error_response("null audio_path");
    }
    let path_str = match unsafe { CStr::from_ptr(audio_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("audio_path not utf-8"),
    };
    let req = match parse_request(request_json) {
        Ok(r) => r,
        Err(e) => return error_response(&e),
    };
    // Use the engine's importer (handles WAV/MP3/FLAC/AIFF/OGG/M4A).
    let imported = match rf_engine::AudioImporter::import(Path::new(path_str)) {
        Ok(a) => a,
        Err(e) => return error_response(&format!("import failed: {:?}", e)),
    };
    match run_pipeline(
        &imported.samples,
        imported.channels as usize,
        imported.sample_rate,
        req,
    ) {
        Ok(resp) => match serde_json::to_string(&resp) {
            Ok(j) => json_to_c(j),
            Err(e) => error_response(&format!("serialize error: {}", e)),
        },
        Err(e) => error_response(&e),
    }
}

/// Free a string allocated by this module's FFI functions.
///
/// # Safety
/// `ptr` must come from one of this module's `*_json` functions.
#[unsafe(no_mangle)]
pub extern "C" fn chain_auto_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn cstr_to_string(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null(), "got null pointer");
        let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
        chain_auto_free_string(ptr);
        s
    }

    /// Synthesize a vocal-ish sine sweep buffer: mid-frequency content
    /// with moderate dynamics + narrow stereo. Enough to exercise the
    /// analyzer end-to-end.
    fn synth_vocal_pcm(seconds: f32, sample_rate: u32) -> Vec<f32> {
        let n = (seconds * sample_rate as f32) as usize;
        let mut out = Vec::with_capacity(n * 2);
        for i in 0..n {
            let t = i as f32 / sample_rate as f32;
            // 220 Hz fundamental + harmonics → mid-range bias
            let s = 0.4 * (2.0 * std::f32::consts::PI * 220.0 * t).sin()
                + 0.2 * (2.0 * std::f32::consts::PI * 440.0 * t).sin()
                + 0.1 * (2.0 * std::f32::consts::PI * 880.0 * t).sin();
            // Tiny stereo offset (narrow image)
            out.push(s);
            out.push(s * 0.95);
        }
        out
    }

    #[test]
    fn pipeline_pcm_with_skip_execute_returns_plan_only() {
        let audio = synth_vocal_pcm(2.0, 48000);
        let req = serde_json::json!({
            "plugins": [],
            "track_id": 1,
            "current_chain": [],
            "track_hint": "vocal",
            "policy": {"plugin_strategy": "internal_only"},
            "execute_mode": "skip"
        });
        let req_c = CString::new(req.to_string()).unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                req_c.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        // analysis + suggestion + plan must all be present
        assert!(out.contains("\"analysis\""));
        assert!(out.contains("\"suggestion\""));
        assert!(out.contains("\"plan\""));
        // execute is null (skip)
        assert!(out.contains("\"execute\":null"));
        // Track type forced to vocal
        assert!(out.contains("\"track_type\":\"vocal\""));
    }

    #[test]
    fn pipeline_pcm_with_dry_run_includes_execute_log() {
        let audio = synth_vocal_pcm(1.0, 48000);
        let req = serde_json::json!({
            "track_id": 7,
            "track_hint": "vocal",
            "policy": {"plugin_strategy": "internal_only"},
            "execute_mode": "dry_run"
        });
        let req_c = CString::new(req.to_string()).unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                req_c.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["execute"]["dry_run"].as_bool().unwrap_or(false));
        assert!(v["execute"]["failed"].as_u64().unwrap_or(99) == 0);
    }

    #[test]
    fn pipeline_pcm_with_invalid_execute_mode_errors() {
        let audio = synth_vocal_pcm(1.0, 48000);
        let req = serde_json::json!({
            "track_hint": "vocal",
            "execute_mode": "bogus"
        });
        let req_c = CString::new(req.to_string()).unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                req_c.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
        assert!(out.contains("bogus") || out.contains("unknown"));
    }

    #[test]
    fn pipeline_pcm_null_pcm_returns_error() {
        let req = CString::new("{}").unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                std::ptr::null(),
                0,
                2,
                48000,
                req.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn pipeline_pcm_zero_channels_returns_error() {
        let audio = vec![0.0_f32; 100];
        let req = CString::new("{}").unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                0,
                48000,
                req.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn pipeline_pcm_zero_sample_rate_returns_error() {
        let audio = vec![0.0_f32; 100];
        let req = CString::new("{}").unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                0,
                req.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn pipeline_pcm_invalid_request_json_returns_error() {
        let audio = synth_vocal_pcm(0.1, 48000);
        let bad = CString::new("{this is not json").unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                bad.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn pipeline_pcm_advisor_config_threads_through() {
        // vintage_bias=true should add saturation slot to vocal chain
        let audio = synth_vocal_pcm(1.0, 48000);
        let req = serde_json::json!({
            "track_hint": "vocal",
            "advisor": {"vintage_bias": true},
            "execute_mode": "skip"
        });
        let req_c = CString::new(req.to_string()).unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                req_c.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("Vintage Vocal"));
        assert!(out.contains("saturation"));
    }

    #[test]
    fn pipeline_path_with_nonexistent_file_returns_error() {
        let path = CString::new("/nonexistent/path/audio.wav").unwrap();
        let req = CString::new("{}").unwrap();
        let raw = chain_auto_pipeline_path_json(path.as_ptr(), req.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn pipeline_path_null_returns_error() {
        let req = CString::new("{}").unwrap();
        let raw = chain_auto_pipeline_path_json(std::ptr::null(), req.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn analysis_digest_contains_expected_fields() {
        let audio = synth_vocal_pcm(1.0, 48000);
        let req = serde_json::json!({"track_hint": "vocal", "execute_mode": "skip"});
        let req_c = CString::new(req.to_string()).unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                req_c.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        let analysis = &v["analysis"];
        // Spot-check the digest carries each required field
        for key in &[
            "integrated_lufs",
            "true_peak_db",
            "spectral_low_ratio",
            "spectral_mid_ratio",
            "spectral_high_ratio",
            "crest_factor_db",
            "stereo_width",
            "quality_score",
        ] {
            assert!(
                analysis[*key].is_number(),
                "missing analysis field: {} (got: {:?})",
                key,
                analysis[*key]
            );
        }
    }

    #[test]
    fn pipeline_with_existing_chain_preserves_matching_slots() {
        let audio = synth_vocal_pcm(0.5, 48000);
        let req = serde_json::json!({
            "track_id": 1,
            "current_chain": [
                {"slot_index": 0, "processor_name": "compressor", "kind": "compressor", "bypassed": false}
            ],
            "track_hint": "vocal",
            "policy": {"plugin_strategy": "internal_only", "preserve_matching_slots": true},
            "execute_mode": "skip"
        });
        let req_c = CString::new(req.to_string()).unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                req_c.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        // preserved_slots must be at least 1 (the compressor)
        assert!(v["plan"]["preserved_slots"].as_u64().unwrap_or(0) >= 1);
    }

    #[test]
    fn pipeline_track_hint_overrides_classifier() {
        let audio = synth_vocal_pcm(0.5, 48000);
        // Force "drums" hint on what's clearly tonal — must respect hint
        let req = serde_json::json!({
            "track_hint": "drums",
            "execute_mode": "skip"
        });
        let req_c = CString::new(req.to_string()).unwrap();
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                audio.as_ptr(),
                audio.len(),
                2,
                48000,
                req_c.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"track_type\":\"drums\""));
    }

    #[test]
    fn free_string_is_null_safe() {
        chain_auto_free_string(std::ptr::null_mut());
    }

    #[test]
    fn parse_track_hint_round_trips() {
        assert_eq!(parse_track_hint("vocal"), Some(TrackType::Vocal));
        assert_eq!(parse_track_hint("DRUMS"), Some(TrackType::Drums));
        assert_eq!(parse_track_hint("Master"), Some(TrackType::Master));
        assert_eq!(parse_track_hint("nonsense"), None);
    }

    #[test]
    fn empty_audio_returns_error() {
        let req = CString::new("{}").unwrap();
        let empty: Vec<f32> = vec![];
        let raw = unsafe {
            chain_auto_pipeline_pcm_json(
                empty.as_ptr(),
                0,
                2,
                48000,
                req.as_ptr(),
            )
        };
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }
}

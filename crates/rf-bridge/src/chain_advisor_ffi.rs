//! Chain Advisor FFI — bridge `rf_ml::assistant::ChainAdvisor` to Flutter.
//!
//! The advisor is stateless, so this layer is thin: take a JSON request
//! describing the analysis features + scanned plugins, return a JSON
//! `ChainSuggestion`.
//!
//! # Functions
//!
//! - `chain_advisor_suggest_json(request_json) -> *mut c_char`
//! - `chain_advisor_classify_json(features_json) -> *mut c_char`
//! - `chain_advisor_free_string(ptr)`
//!
//! # Request shape (JSON)
//!
//! ```json
//! {
//!   "features": {
//!     "low_ratio": 0.2,  "mid_ratio": 0.55,  "high_ratio": 0.25,
//!     "crest_factor_db": 12.0,  "transient_sharpness": 0.5,
//!     "stereo_width": 0.3,
//!     "genres": [{"genre": "pop", "confidence": 0.7}]
//!   },
//!   "plugins": [
//!     {"id": "fab.proq4", "name": "FabFilter Pro-Q 4", "vendor": "FabFilter"}
//!   ],
//!   "track_hint": "vocal",          // optional, omit for auto-detect
//!   "config": {                       // optional
//!     "target_lufs": -14.0,
//!     "vintage_bias": false,
//!     "corrective_aggressiveness": 0.6
//!   }
//! }
//! ```

use std::ffi::{c_char, CStr, CString};

use serde::{Deserialize, Serialize};

use rf_ml::assistant::{
    AdvisorConfig, AvailablePlugin, ChainAdvisor, ChainSuggestion, DynamicsAnalysis, Genre,
    LoudnessAnalysis, SpectralAnalysis, StereoAnalysis, TrackType,
};
use rf_ml::assistant::AnalysisResult;

// ─── Request / response wire types ───────────────────────────────────────

#[derive(Debug, Deserialize)]
struct GenreEntry {
    genre: String,
    #[serde(default)]
    confidence: f32,
}

#[derive(Debug, Deserialize, Default)]
struct FeaturesIn {
    #[serde(default)]
    low_ratio: f32,
    #[serde(default)]
    mid_ratio: f32,
    #[serde(default)]
    high_ratio: f32,
    #[serde(default)]
    crest_factor_db: f32,
    #[serde(default)]
    transient_sharpness: f32,
    #[serde(default)]
    stereo_width: f32,
    #[serde(default)]
    genres: Vec<GenreEntry>,
}

#[derive(Debug, Deserialize)]
struct PluginIn {
    id: String,
    name: String,
    #[serde(default)]
    vendor: String,
}

#[derive(Debug, Deserialize, Default)]
struct ConfigIn {
    #[serde(default)]
    target_lufs: Option<f32>,
    #[serde(default)]
    vintage_bias: Option<bool>,
    #[serde(default)]
    corrective_aggressiveness: Option<f32>,
}

#[derive(Debug, Deserialize)]
struct SuggestRequest {
    features: FeaturesIn,
    #[serde(default)]
    plugins: Vec<PluginIn>,
    #[serde(default)]
    track_hint: Option<String>,
    #[serde(default)]
    config: Option<ConfigIn>,
}

#[derive(Debug, Serialize)]
struct ClassifyResponse {
    track_type: String,
    confidence: f32,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
}

// ─── Helpers ──────────────────────────────────────────────────────────────

fn parse_genre(name: &str) -> Genre {
    match name.to_lowercase().as_str() {
        "rock" => Genre::Rock,
        "pop" => Genre::Pop,
        "hiphop" | "hip-hop" | "hip hop" => Genre::HipHop,
        "electronic" | "edm" => Genre::Electronic,
        "jazz" => Genre::Jazz,
        "classical" => Genre::Classical,
        "country" => Genre::Country,
        "blues" => Genre::Blues,
        "metal" => Genre::Metal,
        "rnb" | "r&b" => Genre::RnB,
        "reggae" => Genre::Reggae,
        "folk" => Genre::Folk,
        _ => Genre::Other,
    }
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

fn track_type_to_str(t: TrackType) -> &'static str {
    match t {
        TrackType::Vocal => "vocal",
        TrackType::Drums => "drums",
        TrackType::Bass => "bass",
        TrackType::Guitar => "guitar",
        TrackType::Synth => "synth",
        TrackType::Keys => "keys",
        TrackType::FullMix => "fullmix",
        TrackType::Master => "master",
        TrackType::Unknown => "unknown",
    }
}

fn build_analysis(f: &FeaturesIn) -> AnalysisResult {
    AnalysisResult {
        genres: f
            .genres
            .iter()
            .map(|g| (parse_genre(&g.genre), g.confidence))
            .collect(),
        moods: vec![],
        tempo_bpm: None,
        key: None,
        loudness: LoudnessAnalysis::default(),
        spectral: SpectralAnalysis {
            low_ratio: f.low_ratio,
            mid_ratio: f.mid_ratio,
            high_ratio: f.high_ratio,
            ..Default::default()
        },
        dynamics: DynamicsAnalysis {
            crest_factor_db: f.crest_factor_db,
            transient_sharpness: f.transient_sharpness,
            ..Default::default()
        },
        stereo: StereoAnalysis {
            width: f.stereo_width,
            ..Default::default()
        },
        suggestions: vec![],
        quality_score: 0.5,
    }
}

fn build_advisor(cfg: Option<ConfigIn>) -> ChainAdvisor {
    match cfg {
        Some(c) => {
            let mut ac = AdvisorConfig::default();
            if let Some(v) = c.target_lufs {
                ac.target_lufs = v;
            }
            if let Some(v) = c.vintage_bias {
                ac.vintage_bias = v;
            }
            if let Some(v) = c.corrective_aggressiveness {
                ac.corrective_aggressiveness = v.clamp(0.0, 1.0);
            }
            ChainAdvisor::with_config(ac)
        }
        None => ChainAdvisor::new(),
    }
}

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn error_response(msg: &str) -> *mut c_char {
    let resp = ErrorResponse { error: msg.into() };
    json_to_c(serde_json::to_string(&resp).unwrap_or_default())
}

// ─── FFI surface ──────────────────────────────────────────────────────────

/// Suggest a complete chain. Input: JSON request (see module docs).
/// Output: JSON `ChainSuggestion` or `{"error": "..."}`.
///
/// # Safety
/// `request_json` must be a NUL-terminated C string. Returned pointer
/// must be freed via `chain_advisor_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_advisor_suggest_json(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return error_response("null request");
    }
    let raw = unsafe { CStr::from_ptr(request_json) };
    let s = match raw.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("request not utf-8"),
    };
    let req: SuggestRequest = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => return error_response(&format!("parse error: {}", e)),
    };

    let advisor = build_advisor(req.config);
    let analysis = build_analysis(&req.features);
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

    match serde_json::to_string(&suggestion) {
        Ok(j) => json_to_c(j),
        Err(e) => error_response(&format!("serialize error: {}", e)),
    }
}

/// Classify the track type from features only — no plugin matching, no
/// chain assembly. Cheap, can be called for live previews.
///
/// Input: JSON `FeaturesIn`. Output: JSON `{"track_type": "vocal", "confidence": 0.72}`.
///
/// # Safety
/// Same as `chain_advisor_suggest_json`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_advisor_classify_json(features_json: *const c_char) -> *mut c_char {
    if features_json.is_null() {
        return error_response("null features");
    }
    let raw = unsafe { CStr::from_ptr(features_json) };
    let s = match raw.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("features not utf-8"),
    };
    let features: FeaturesIn = match serde_json::from_str(s) {
        Ok(f) => f,
        Err(e) => return error_response(&format!("parse error: {}", e)),
    };

    let analysis = build_analysis(&features);
    let advisor = ChainAdvisor::new();
    let (track_type, confidence) = advisor.classify_track_type(&analysis);

    let resp = ClassifyResponse {
        track_type: track_type_to_str(track_type).into(),
        confidence,
    };
    match serde_json::to_string(&resp) {
        Ok(j) => json_to_c(j),
        Err(e) => error_response(&format!("serialize error: {}", e)),
    }
}

/// Free a string allocated by this module's FFI functions.
///
/// # Safety
/// `ptr` must have come from one of this module's `*_json` functions.
#[unsafe(no_mangle)]
pub extern "C" fn chain_advisor_free_string(ptr: *mut c_char) {
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
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
        chain_advisor_free_string(ptr);
        s
    }

    #[test]
    fn classify_vocal() {
        let req = r#"{"low_ratio":0.2,"mid_ratio":0.55,"high_ratio":0.25,"crest_factor_db":12.0,"transient_sharpness":0.5,"stereo_width":0.3}"#;
        let c = CString::new(req).unwrap();
        let raw = chain_advisor_classify_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"track_type\":\"vocal\""));
    }

    #[test]
    fn classify_drums() {
        let req = r#"{"low_ratio":0.3,"mid_ratio":0.4,"high_ratio":0.3,"crest_factor_db":18.0,"transient_sharpness":0.85,"stereo_width":0.5}"#;
        let c = CString::new(req).unwrap();
        let raw = chain_advisor_classify_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"track_type\":\"drums\""));
    }

    #[test]
    fn suggest_full_chain_for_vocal_with_plugins() {
        let req = r#"{
          "features": {
            "low_ratio": 0.2, "mid_ratio": 0.55, "high_ratio": 0.25,
            "crest_factor_db": 12.0, "transient_sharpness": 0.5,
            "stereo_width": 0.3
          },
          "plugins": [
            {"id":"f1","name":"FabFilter Pro-Q 4","vendor":"FabFilter"},
            {"id":"f2","name":"FabFilter Pro-C 2","vendor":"FabFilter"},
            {"id":"f3","name":"FabFilter Pro-DS","vendor":"FabFilter"},
            {"id":"v1","name":"Valhalla VintageVerb","vendor":"Valhalla"}
          ],
          "track_hint": "vocal"
        }"#;
        let c = CString::new(req).unwrap();
        let raw = chain_advisor_suggest_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"track_type\":\"vocal\""));
        assert!(out.contains("Pro-C"));
        assert!(out.contains("Valhalla"));
        assert!(out.contains("\"slots\""));
    }

    #[test]
    fn invalid_json_returns_error() {
        let c = CString::new("not json").unwrap();
        let raw = chain_advisor_suggest_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn null_pointer_returns_error() {
        let raw = chain_advisor_suggest_json(std::ptr::null());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn track_hint_overrides_classification_via_ffi() {
        let req = r#"{
          "features": {"low_ratio":0.7,"mid_ratio":0.2,"high_ratio":0.1,"crest_factor_db":9.0,"transient_sharpness":0.3,"stereo_width":0.3},
          "track_hint": "master"
        }"#;
        let c = CString::new(req).unwrap();
        let raw = chain_advisor_suggest_json(c.as_ptr());
        let out = cstr_to_string(raw);
        // Despite features looking bass-like, hint forces master
        assert!(out.contains("\"track_type\":\"master\""));
    }

    #[test]
    fn config_target_lufs_threaded_through() {
        let req = r#"{
          "features": {"low_ratio":0.3,"mid_ratio":0.4,"high_ratio":0.3,"crest_factor_db":12.0,"transient_sharpness":0.5,"stereo_width":0.6},
          "track_hint": "master",
          "config": {"target_lufs": -10.0}
        }"#;
        let c = CString::new(req).unwrap();
        let raw = chain_advisor_suggest_json(c.as_ptr());
        let out = cstr_to_string(raw);
        // Maximizer must echo -10 LUFS
        assert!(out.contains("Target LUFS"));
        assert!(out.contains("-10"));
    }

    #[test]
    fn vintage_bias_propagates() {
        let req = r#"{
          "features": {"low_ratio":0.2,"mid_ratio":0.55,"high_ratio":0.25,"crest_factor_db":12.0,"transient_sharpness":0.5,"stereo_width":0.3},
          "track_hint": "vocal",
          "config": {"vintage_bias": true}
        }"#;
        let c = CString::new(req).unwrap();
        let raw = chain_advisor_suggest_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("Vintage Vocal"));
        assert!(out.contains("saturation"));
    }

    #[test]
    fn parse_genre_known_and_unknown() {
        assert!(matches!(parse_genre("Pop"), Genre::Pop));
        assert!(matches!(parse_genre("HIP-HOP"), Genre::HipHop));
        assert!(matches!(parse_genre("xyz"), Genre::Other));
    }

    #[test]
    fn parse_track_hint_variants() {
        assert_eq!(parse_track_hint("Vocal"), Some(TrackType::Vocal));
        assert_eq!(parse_track_hint("DRUM"), Some(TrackType::Drums));
        assert_eq!(parse_track_hint("piano"), Some(TrackType::Keys));
        assert_eq!(parse_track_hint("nonsense"), None);
    }

    #[test]
    fn free_string_handles_null_safely() {
        chain_advisor_free_string(std::ptr::null_mut());
        // Must not crash.
    }
}

//! RGAI™ FFI — Bridges rf-rgai to Flutter.
//!
//! Functions:
//! - rgai_init (set target jurisdictions)
//! - rgai_analyze_asset_json (single asset analysis)
//! - rgai_analyze_session_json (full game session)
//! - rgai_export_gate_json (can we export?)
//! - rgai_get_report_json (RGAR report)
//! - rgai_get_remediation_json (fix suggestions)
//! - rgai_jurisdictions_json (list all supported)

use std::ffi::{c_char, CStr, CString};
use std::sync::OnceLock;

use parking_lot::RwLock;
use rf_rgai::{
    ExportGate, Jurisdiction, RgaiAnalyzer, RemediationPlan,
    report::RgarReport,
    session::{AudioAssetProfile, GameAudioSession},
};

struct RgaiState {
    analyzer: RgaiAnalyzer,
    gate: ExportGate,
    jurisdictions: Vec<Jurisdiction>,
}

static RGAI_STATE: OnceLock<RwLock<RgaiState>> = OnceLock::new();

fn state() -> &'static RwLock<RgaiState> {
    RGAI_STATE.get_or_init(|| {
        let jurisdictions = vec![Jurisdiction::Ukgc, Jurisdiction::Mga];
        RwLock::new(RgaiState {
            analyzer: RgaiAnalyzer::new(jurisdictions.clone()),
            gate: ExportGate::new(jurisdictions.clone()),
            jurisdictions,
        })
    })
}

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Initialize RGAI with target jurisdictions (JSON array of codes: ["UKGC","MGA","SE",...]).
#[unsafe(no_mangle)]
pub extern "C" fn rgai_init(jurisdictions_json: *const c_char) -> i32 {
    let jurisdictions = if jurisdictions_json.is_null() {
        vec![Jurisdiction::Ukgc, Jurisdiction::Mga]
    } else {
        let s = match unsafe { CStr::from_ptr(jurisdictions_json) }.to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let codes: Vec<String> = match serde_json::from_str(s) {
            Ok(c) => c,
            Err(_) => return -1,
        };
        codes
            .iter()
            .filter_map(|code| match code.as_str() {
                "UKGC" => Some(Jurisdiction::Ukgc),
                "MGA" => Some(Jurisdiction::Mga),
                "AGCO" | "Ontario" => Some(Jurisdiction::Ontario),
                "SE" | "Sweden" => Some(Jurisdiction::Sweden),
                "DK" | "Denmark" => Some(Jurisdiction::Denmark),
                "NL" | "Netherlands" => Some(Jurisdiction::Netherlands),
                "AU" | "Australia" => Some(Jurisdiction::Australia),
                _ => None,
            })
            .collect()
    };
    let mut st = state().write();
    st.analyzer = RgaiAnalyzer::new(jurisdictions.clone());
    st.gate = ExportGate::new(jurisdictions.clone());
    st.jurisdictions = jurisdictions;
    0
}

/// Analyze a single audio asset. Returns JSON with metrics + per-jurisdiction pass/fail.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_analyze_asset_json(asset_json: *const c_char) -> *mut c_char {
    if asset_json.is_null() {
        return json_to_c(r#"{"error":"null input"}"#.to_string());
    }
    let s = match unsafe { CStr::from_ptr(asset_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return json_to_c(r#"{"error":"invalid utf8"}"#.to_string()),
    };
    let asset: AudioAssetProfile = match serde_json::from_str(s) {
        Ok(a) => a,
        Err(e) => return json_to_c(format!(r#"{{"error":"{}"}}"#, e)),
    };
    let st = state().read();
    let result = st.analyzer.analyze_asset(&asset);
    json_to_c(serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string()))
}

/// Analyze an entire game audio session. Returns full analysis JSON.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_analyze_session_json(session_json: *const c_char) -> *mut c_char {
    if session_json.is_null() {
        return json_to_c(r#"{"error":"null input"}"#.to_string());
    }
    let s = match unsafe { CStr::from_ptr(session_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return json_to_c(r#"{"error":"invalid utf8"}"#.to_string()),
    };
    let session: GameAudioSession = match serde_json::from_str(s) {
        Ok(s) => s,
        Err(e) => return json_to_c(format!(r#"{{"error":"{}"}}"#, e)),
    };
    let st = state().read();
    let result = st.analyzer.analyze_session(&session);
    json_to_c(serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string()))
}

/// Export gate check — returns JSON with decision (Approved/Blocked) + details.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_export_gate_json(session_json: *const c_char) -> *mut c_char {
    if session_json.is_null() {
        return json_to_c(r#"{"error":"null input"}"#.to_string());
    }
    let s = match unsafe { CStr::from_ptr(session_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return json_to_c(r#"{"error":"invalid utf8"}"#.to_string()),
    };
    let session: GameAudioSession = match serde_json::from_str(s) {
        Ok(s) => s,
        Err(e) => return json_to_c(format!(r#"{{"error":"{}"}}"#, e)),
    };
    let st = state().read();
    let result = st.gate.evaluate(&session);
    json_to_c(serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string()))
}

/// Generate RGAR compliance report. Returns full report JSON.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_get_report_json(session_json: *const c_char) -> *mut c_char {
    if session_json.is_null() {
        return json_to_c(r#"{"error":"null input"}"#.to_string());
    }
    let s = match unsafe { CStr::from_ptr(session_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return json_to_c(r#"{"error":"invalid utf8"}"#.to_string()),
    };
    let session: GameAudioSession = match serde_json::from_str(s) {
        Ok(s) => s,
        Err(e) => return json_to_c(format!(r#"{{"error":"{}"}}"#, e)),
    };
    let st = state().read();
    let analysis = st.analyzer.analyze_session(&session);
    let report = RgarReport::generate(&analysis, "0.1.0");
    json_to_c(report.to_json())
}

/// Get remediation suggestions for a failing asset. Returns JSON plan.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_get_remediation_json(asset_json: *const c_char) -> *mut c_char {
    if asset_json.is_null() {
        return json_to_c(r#"{"error":"null input"}"#.to_string());
    }
    let s = match unsafe { CStr::from_ptr(asset_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return json_to_c(r#"{"error":"invalid utf8"}"#.to_string()),
    };
    let asset: AudioAssetProfile = match serde_json::from_str(s) {
        Ok(a) => a,
        Err(e) => return json_to_c(format!(r#"{{"error":"{}"}}"#, e)),
    };
    let st = state().read();
    let analysis = st.analyzer.analyze_asset(&asset);
    let profile = st.analyzer.merged_profile();
    match RemediationPlan::generate(&analysis, profile) {
        Some(plan) => json_to_c(serde_json::to_string(&plan).unwrap_or_else(|_| "{}".to_string())),
        None => json_to_c(r#"{"status":"compliant","message":"No remediation needed"}"#.to_string()),
    }
}

/// List all supported jurisdictions with their profiles as JSON array.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_jurisdictions_json() -> *mut c_char {
    let jurisdictions: Vec<serde_json::Value> = Jurisdiction::all_builtin()
        .iter()
        .map(|j| {
            let p = j.profile();
            serde_json::json!({
                "code": j.code(),
                "label": j.label(),
                "max_arousal": p.max_arousal,
                "max_near_miss_deception": p.max_near_miss_deception,
                "max_loss_disguise": p.max_loss_disguise,
                "max_temporal_distortion": p.max_temporal_distortion,
                "ldw_suppression_required": p.ldw_suppression_required,
                "near_miss_enhancement_prohibited": p.near_miss_enhancement_prohibited,
            })
        })
        .collect();
    json_to_c(serde_json::to_string(&jurisdictions).unwrap_or_else(|_| "[]".to_string()))
}

#[unsafe(no_mangle)]
pub extern "C" fn rgai_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}

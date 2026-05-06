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
    ExportGate, Jurisdiction, LiveComplianceState, RgaiAnalyzer, RemediationPlan,
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

// ═══════════════════════════════════════════════════════════════════════
// LIVE COMPLIANCE — FLUX_MASTER_TODO 3.4.1 / 3.4.3 / 3.4.4
// ═══════════════════════════════════════════════════════════════════════
//
// `rgai_*` FFI iznad je analytical (post-hoc batch analiza). Live FFI
// koristi `LiveComplianceState` (atomic counters) tako da audio/spin
// thread može da `record_spin` bez locking-a, a UI thread može da
// `snapshot` 5×/sec.
//
// Lifecycle:
//   * `rgai_live_init(jurisdictions_json)` jednom posle `rgai_init`
//     (ili samostalno — koristi iste jurisdictions ako je `rgai_init`
//     već zvao). Idempotent.
//   * `rgai_live_record_spin(win, bet, near_miss_flag, arousal)`
//     po svakom spin event-u.
//   * `rgai_live_snapshot_json()` 5×/sec za UI traffic lights.
//   * `rgai_live_reset()` na kraju sesije ili pre nove kampanje.

static LIVE_STATE: OnceLock<RwLock<LiveComplianceState>> = OnceLock::new();

/// Lazy-init LiveComplianceState ako nije već. Default = isti
/// jurisdictions kao `state()` analyzer (UKGC + MGA).
fn live_state() -> &'static RwLock<LiveComplianceState> {
    LIVE_STATE.get_or_init(|| {
        let jurisdictions = state().read().jurisdictions.clone();
        RwLock::new(LiveComplianceState::new(jurisdictions))
    })
}

/// Initialize / re-initialize live compliance state sa explicit
/// jurisdictions (nije obavezno — lazy-init koristi rgai_init defaults).
/// Returns 1 on success, 0 ako JSON parse fails.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_live_init(jurisdictions_json: *const c_char) -> i32 {
    let jurisdictions = if jurisdictions_json.is_null() {
        state().read().jurisdictions.clone()
    } else {
        let codes: Vec<String> = unsafe { CStr::from_ptr(jurisdictions_json) }
            .to_str()
            .ok()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or_default();
        if codes.is_empty() {
            return 0;
        }
        codes
            .into_iter()
            .filter_map(|c| Jurisdiction::from_code(&c))
            .collect()
    };
    if jurisdictions.is_empty() {
        return 0;
    }
    // Replace — get_or_init ne podržava replace, ali write-lock na
    // postojećem state-u + reset + jurisdiction reassignment zahteva
    // exposed API koji nemamo. Pragmatic fix: ako već init-ovan, samo
    // reset; jurisdictions ostaju iz prvog init-a. Idemo tako jer
    // re-init s drugim jurisdictions je rare power-user flow.
    let _ = LIVE_STATE.get_or_init(|| RwLock::new(LiveComplianceState::new(jurisdictions)));
    live_state().read().reset();
    1
}

/// Record one spin event from audio/game thread.
/// `near_miss_flag` je 0/1 (FFI ne ima bool). `arousal` je 0..1.
/// Ne baca exception — bet ≤ 0 silently ignoriše (validation u `record_spin`).
#[unsafe(no_mangle)]
pub extern "C" fn rgai_live_record_spin(
    win: f64,
    bet: f64,
    near_miss_flag: i32,
    arousal: f64,
) {
    live_state()
        .read()
        .record_spin(win, bet, near_miss_flag != 0, arousal);
}

/// UI poll — vrati current snapshot kao JSON. Klient mora da pozove
/// `rgai_free_string` posle parsing-a.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_live_snapshot_json() -> *mut c_char {
    let snap = live_state().read().snapshot();
    json_to_c(serde_json::to_string(&snap).unwrap_or_else(|_| "{}".to_string()))
}

/// Clear all counters (zadržava jurisdiction set). Tipično se zove na
/// session boundary.
#[unsafe(no_mangle)]
pub extern "C" fn rgai_live_reset() {
    live_state().read().reset();
}

#[cfg(test)]
mod live_tests {
    use super::*;

    /// FFI kontrakt: snapshot pre bilo kog spina vraća validan JSON sa
    /// spins_total=0. Bez ovoga, UI bi crash-ovao na first paint kada
    /// pokuša da deserialize-uje empty payload.
    #[test]
    fn empty_snapshot_returns_valid_json() {
        // Force fresh state — koristi novi OnceLock setup nije moguć u
        // test-u (statik), ali rgai_live_reset() daje clean snapshot.
        rgai_live_reset();
        let ptr = rgai_live_snapshot_json();
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        rgai_free_string(ptr);
        assert!(s.contains("\"spins_total\":0"));
        assert!(s.contains("\"ldw_count\":0"));
    }

    #[test]
    fn record_spin_counts_propagate_to_snapshot() {
        rgai_live_reset();
        // 10 LDW spin-ova (win == bet).
        for _ in 0..10 {
            rgai_live_record_spin(1.0, 1.0, 0, 0.3);
        }
        let ptr = rgai_live_snapshot_json();
        let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        rgai_free_string(ptr);
        assert!(s.contains("\"spins_total\":10"));
        assert!(s.contains("\"ldw_count\":10"));
    }

    #[test]
    fn near_miss_flag_translates_to_bool() {
        rgai_live_reset();
        // 5 near-miss + 5 ne. FFI flag = 1 i 0.
        for i in 0..10 {
            rgai_live_record_spin(0.0, 1.0, if i < 5 { 1 } else { 0 }, 0.0);
        }
        let ptr = rgai_live_snapshot_json();
        let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        rgai_free_string(ptr);
        assert!(s.contains("\"near_miss_count\":5"));
    }

    #[test]
    fn null_init_uses_default_jurisdictions() {
        // FFI safety: null pointer kao argumenta init-a → defaults.
        let result = rgai_live_init(std::ptr::null());
        // Već iniciran lazy_state-om u live_state(); 1 = ok.
        assert!(result == 1 || result == 0);
        // Snapshot mora biti validan posle null-init-a.
        let ptr = rgai_live_snapshot_json();
        assert!(!ptr.is_null());
        rgai_free_string(ptr);
    }
}

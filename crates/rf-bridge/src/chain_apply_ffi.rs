//! Chain Apply FFI — bridge `rf_ml::assistant::ChainApplier` to Flutter.
//!
//! Two functions, two modes:
//!
//! - `chain_apply_plan_json` — pure planner. Takes a `ChainSuggestion`
//!   (from the advisor) plus the track's current chain state plus an
//!   optional policy, returns an `ApplyPlan` JSON. **Touches no audio.**
//! - `chain_apply_execute_json` — runs an `ApplyPlan` against the live
//!   `ENGINE`. Honours a `dry_run` flag so the caller can verify
//!   exactly what would happen before committing.
//!
//! # Why split planning and execution
//!
//! - Planning is deterministic and reversible — the UI can preview, the
//!   user can disagree slot-by-slot, the daemon can A/B different
//!   suggestions without touching the engine.
//! - Execution is the only place that reaches into the audio thread.
//!   Keeping it isolated makes the surface easy to audit.
//!
//! # Execute coverage today
//!
//! - `LoadInternal` → engine `insert_load(track_id, slot, name)` ✓
//! - `UnloadSlot` → engine `unload_track_insert` ✓
//! - `SetBypass` → engine `set_track_insert_bypass` ✓
//! - `SetParameter` → engine `set_track_insert_param_by_name` (fuzzy match) ✓
//! - `LoadExternal` → currently logged-and-skipped: scanned VST3/AU
//!   instantiation through the apply path is the next phase. The plan
//!   still contains these steps for UI preview.

use std::ffi::{c_char, CStr, CString};

use rf_ml::assistant::{
    ApplyPlan, ApplyPolicy, ApplyStep, ChainApplier, ChainSuggestion, CurrentChainState,
    PluginPickStrategy,
};
use serde::{Deserialize, Serialize};

use crate::ENGINE;

// ─── Wire types ───────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct PlanRequest {
    suggestion: ChainSuggestion,
    current: CurrentChainState,
    #[serde(default)]
    policy: Option<PolicyIn>,
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

fn parse_strategy(s: &str) -> PluginPickStrategy {
    match s.to_lowercase().as_str() {
        "internal_only" | "internal" => PluginPickStrategy::InternalOnly,
        "external_only" | "external" => PluginPickStrategy::ExternalOnly,
        _ => PluginPickStrategy::PreferExternal,
    }
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

#[derive(Debug, Deserialize)]
struct ExecuteRequest {
    plan: ApplyPlan,
    /// If true, walk the plan but only collect what would happen — no
    /// engine calls. Defaults to false.
    #[serde(default)]
    dry_run: bool,
}

#[derive(Debug, Serialize)]
struct ExecuteResult {
    /// Steps actually executed (or simulated in dry_run).
    executed: u32,
    /// Steps skipped (e.g. `LoadExternal` not yet supported, or engine missing).
    skipped: u32,
    /// Steps that failed (engine returned false).
    failed: u32,
    /// Per-step outcomes.
    log: Vec<StepResult>,
    /// Was this a dry run?
    dry_run: bool,
}

#[derive(Debug, Serialize)]
struct StepResult {
    index: u32,
    description: String,
    outcome: String, // "ok" | "skipped" | "failed"
    detail: String,
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

// ─── Public FFI: planner ──────────────────────────────────────────────────

/// Build an `ApplyPlan` from a suggestion + current chain state.
/// Pure planning, no engine impact.
///
/// # Safety
/// `request_json` must be a NUL-terminated C string.
/// Returned pointer must be freed via `chain_apply_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_apply_plan_json(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return error_response("null request");
    }
    let raw = unsafe { CStr::from_ptr(request_json) };
    let s = match raw.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("request not utf-8"),
    };
    let req: PlanRequest = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => return error_response(&format!("parse error: {}", e)),
    };
    let policy = build_policy(req.policy);
    let planner = ChainApplier::with_policy(policy);
    let plan = planner.plan(&req.suggestion, &req.current);
    match serde_json::to_string(&plan) {
        Ok(j) => json_to_c(j),
        Err(e) => error_response(&format!("serialize error: {}", e)),
    }
}

// ─── Public FFI: executor ─────────────────────────────────────────────────

/// Execute an `ApplyPlan` against the live engine. With `dry_run=true`
/// the steps are walked but no engine calls are made — useful for UI
/// previews and tests.
///
/// # Safety
/// Same as `chain_apply_plan_json`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_apply_execute_json(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return error_response("null request");
    }
    let raw = unsafe { CStr::from_ptr(request_json) };
    let s = match raw.to_str() {
        Ok(s) => s,
        Err(_) => return error_response("request not utf-8"),
    };
    let req: ExecuteRequest = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => return error_response(&format!("parse error: {}", e)),
    };

    let result = execute_plan(&req.plan, req.dry_run);
    match serde_json::to_string(&result) {
        Ok(j) => json_to_c(j),
        Err(e) => error_response(&format!("serialize error: {}", e)),
    }
}

/// Free a string allocated by this module's FFI functions.
///
/// # Safety
/// `ptr` must come from `chain_apply_plan_json` or `chain_apply_execute_json`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_apply_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

// ─── Internal: execute the plan ───────────────────────────────────────────

fn execute_plan(plan: &ApplyPlan, dry_run: bool) -> ExecuteResult {
    let mut log = Vec::with_capacity(plan.steps.len());
    let mut executed = 0u32;
    let mut skipped = 0u32;
    let mut failed = 0u32;

    let track_id = plan.track_id as u64;

    for (i, step) in plan.steps.iter().enumerate() {
        let desc = step.describe();
        let (outcome, detail) = if dry_run {
            ("ok".to_string(), "(dry_run)".to_string())
        } else {
            apply_step_to_engine(track_id, step)
        };
        match outcome.as_str() {
            "ok" => executed += 1,
            "skipped" => skipped += 1,
            _ => failed += 1,
        }
        log.push(StepResult {
            index: i as u32,
            description: desc,
            outcome,
            detail,
        });
    }

    ExecuteResult {
        executed,
        skipped,
        failed,
        log,
        dry_run,
    }
}

/// Apply a single step to the live engine. Returns `(outcome, detail)`.
fn apply_step_to_engine(track_id: u64, step: &ApplyStep) -> (String, String) {
    let engine_guard = ENGINE.read();
    let engine = match engine_guard.as_ref() {
        Some(e) => e,
        None => return ("failed".into(), "ENGINE not initialised".into()),
    };
    let pb = engine.playback_engine();

    match step {
        ApplyStep::UnloadSlot { slot_index } => {
            let result = pb.unload_track_insert(track_id, *slot_index as usize);
            if result.is_some() {
                ("ok".into(), "unloaded".into())
            } else {
                // Not strictly an error — slot was already empty.
                ("ok".into(), "slot was empty".into())
            }
        }
        ApplyStep::LoadInternal {
            slot_index,
            processor_name,
        } => {
            // Sample rate is held privately by EngineBridge; the
            // playback engine's master sample rate is the source of truth
            // for newly created processors.
            let sample_rate = pb.sample_rate() as f64;
            match rf_engine::create_processor_extended(processor_name, sample_rate) {
                Some(processor) => {
                    let ok =
                        pb.load_track_insert(track_id, *slot_index as usize, processor);
                    if ok {
                        ("ok".into(), format!("loaded {}", processor_name))
                    } else {
                        ("failed".into(), "load_track_insert returned false".into())
                    }
                }
                None => (
                    "skipped".into(),
                    format!("unknown processor '{}'", processor_name),
                ),
            }
        }
        ApplyStep::LoadExternal {
            plugin_id,
            plugin_name,
            ..
        } => (
            "skipped".into(),
            format!(
                "external plugin '{}' (id {}) — instantiation through apply path \
                 is a follow-up phase",
                plugin_name, plugin_id
            ),
        ),
        ApplyStep::SetBypass {
            slot_index,
            bypassed,
        } => {
            pb.set_track_insert_bypass(track_id, *slot_index as usize, *bypassed);
            ("ok".into(), format!("bypass={}", bypassed))
        }
        ApplyStep::SetParameter {
            slot_index,
            name,
            value,
            ..
        } => {
            // Engine exposes a fuzzy-matching name lookup; we then route
            // the value through the lock-free ring buffer.
            match pb.track_insert_param_index_by_name(track_id, *slot_index as usize, name) {
                Some(idx) => {
                    pb.set_track_insert_param(
                        track_id,
                        *slot_index as usize,
                        idx,
                        *value as f64,
                    );
                    (
                        "ok".into(),
                        format!("set param[{}] '{}' = {}", idx, name, value),
                    )
                }
                None => {
                    // Slot empty or no matching parameter; either way,
                    // we don't fail the whole plan.
                    let n = pb.track_insert_param_count(track_id, *slot_index as usize);
                    if n == 0 {
                        ("failed".into(), "slot has no loaded processor".into())
                    } else {
                        (
                            "skipped".into(),
                            format!("no parameter matching '{}' (slot has {} params)", name, n),
                        )
                    }
                }
            }
        }
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rf_ml::assistant::{
        AnalysisResult, ChainAdvisor, DynamicsAnalysis, LoudnessAnalysis, SpectralAnalysis,
        StereoAnalysis, TrackType,
    };

    fn cstr_to_string(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
        chain_apply_free_string(ptr);
        s
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
    fn plan_via_ffi_returns_apply_plan() {
        let req = PlanRequest {
            suggestion: vocal_suggestion(),
            current: CurrentChainState {
                track_id: 5,
                slots: vec![],
            },
            policy: None,
        };
        let req_json = serde_json::to_string(&serde_json::json!({
            "suggestion": req.suggestion,
            "current": req.current,
            "policy": null
        }))
        .unwrap();
        let c = CString::new(req_json).unwrap();
        let raw = chain_apply_plan_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"track_id\":5"));
        assert!(out.contains("\"steps\""));
        assert!(out.contains("load_internal") || out.contains("\"op\":\"set_bypass\""));
    }

    #[test]
    fn dry_run_executes_no_failures_for_pure_internal_plan() {
        // Build a plan, dry_run it — should produce one outcome per step,
        // all ok.
        let plan = ChainApplier::new().plan(
            &vocal_suggestion(),
            &CurrentChainState {
                track_id: 7,
                slots: vec![],
            },
        );
        let req = serde_json::json!({
            "plan": plan,
            "dry_run": true,
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = chain_apply_execute_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"dry_run\":true"));
        assert!(out.contains("\"failed\":0"));
        // log array must contain entries for every step
        let result: serde_json::Value = serde_json::from_str(&out).unwrap();
        let log_len = result["log"].as_array().unwrap().len();
        assert_eq!(log_len, plan.steps.len());
    }

    #[test]
    fn execute_with_uninitialised_engine_fails_gracefully() {
        // ENGINE is None in test runtime → real-mode execute should not
        // panic, just return failed steps.
        let plan = ChainApplier::new().plan(
            &vocal_suggestion(),
            &CurrentChainState {
                track_id: 0,
                slots: vec![],
            },
        );
        let req = serde_json::json!({
            "plan": plan,
            "dry_run": false,
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = chain_apply_execute_json(c.as_ptr());
        let out = cstr_to_string(raw);
        // Expect at least some failures (ENGINE not initialised) — but no crash
        let result: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(result["failed"].as_u64().unwrap() > 0);
    }

    #[test]
    fn invalid_plan_json_returns_error() {
        let c = CString::new("{not json}").unwrap();
        let raw = chain_apply_plan_json(c.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn null_pointer_handled_in_plan() {
        let raw = chain_apply_plan_json(std::ptr::null());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn null_pointer_handled_in_execute() {
        let raw = chain_apply_execute_json(std::ptr::null());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn parse_strategy_variants() {
        assert_eq!(parse_strategy("internal_only"), PluginPickStrategy::InternalOnly);
        assert_eq!(parse_strategy("INTERNAL"), PluginPickStrategy::InternalOnly);
        assert_eq!(parse_strategy("external"), PluginPickStrategy::ExternalOnly);
        assert_eq!(parse_strategy("anything else"), PluginPickStrategy::PreferExternal);
    }

    #[test]
    fn free_string_handles_null() {
        chain_apply_free_string(std::ptr::null_mut());
    }

    #[test]
    fn policy_threading_through_ffi() {
        let req = serde_json::json!({
            "suggestion": vocal_suggestion(),
            "current": {"track_id": 1, "slots": []},
            "policy": {"plugin_strategy": "internal_only"}
        });
        let c = CString::new(req.to_string()).unwrap();
        let raw = chain_apply_plan_json(c.as_ptr());
        let out = cstr_to_string(raw);
        // InternalOnly with empty plugin list = all loads should be load_internal
        assert!(out.contains("\"op\":\"load_internal\""));
        assert!(!out.contains("\"op\":\"load_external\""));
    }
}

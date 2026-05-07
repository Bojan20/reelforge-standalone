//! Chain History FFI — Undo / Redo + A/B snapshot
//!
//! # Overview
//!
//! Every time `chain_apply_execute_json` succeeds (non-dry-run), it calls
//! `push_current_snapshot` automatically — no extra work needed from Flutter.
//!
//! From Flutter the undo surface is (Dart pseudocode):
//!
//! ```text
//! // Is undo available?
//! int depth = chain_undo_depth(trackId);
//!
//! // Undo (returns JSON result or error string)
//! Pointer<Utf8> ptr = chain_undo_json(trackId);
//! String json = ptr.toDartString();
//! chain_history_free_string(ptr);
//!
//! // A/B
//! chain_ab_save_a(trackId);            // capture current → slot A
//! chain_ab_restore_a_json(trackId);    // restore slot A, returns result JSON
//! chain_ab_swap(trackId);              // flip A↔B labels (no engine change)
//!
//! // Status (undo depth + A/B state in one call)
//! Pointer<Utf8> s = chain_history_status_json(trackId);
//! ```
//!
//! # Restore algorithm
//!
//! `restore_snapshot_to_engine`:
//!   1. Query current info → unload all loaded slots
//!   2. For each slot in snapshot: `create_processor_extended` → `load_track_insert`
//!   3. Set each parameter by index via the ring-buffer path
//!   4. Set bypass + wet/dry mix
//!
//! Parameters are set by index via `PlaybackEngine::set_track_insert_param`,
//! which routes through the existing lock-free ring buffer — audio-thread safe.

use std::ffi::{c_char, CStr, CString};
use std::ptr;

use rf_ml::assistant::chain_history::{
    FullChainSnapshot, FullSlotSnapshot, SlotParamSnapshot, CHAIN_HISTORY,
};
use serde::Serialize;

use crate::ENGINE;

// ─── Internal helpers ────────────────────────────────────────────────────────

/// Build a `FullChainSnapshot` from live engine state for `track_id`.
fn capture_snapshot(track_id: u32, label: &str) -> FullChainSnapshot {
    let guard = ENGINE.read();
    let Some(engine) = guard.as_ref() else {
        return FullChainSnapshot::now(track_id, vec![], label);
    };
    let pb = engine.playback_engine();
    let info = pb.get_track_insert_info(track_id as u64);

    let mut slots: Vec<FullSlotSnapshot> = Vec::with_capacity(info.len());
    for (slot_index, name, is_loaded, is_bypassed, _pre_fader, mix, _latency) in &info {
        if !is_loaded || name == "Empty" {
            continue;
        }
        let tid = track_id as u64;
        let si = *slot_index;
        let param_count = pb.track_insert_param_count(tid, si);
        let mut params: Vec<SlotParamSnapshot> = Vec::with_capacity(param_count);
        for pi in 0..param_count {
            let pname = pb.track_insert_param_name(tid, si, pi);
            let value = pb.get_track_insert_param(tid, si, pi);
            params.push(SlotParamSnapshot { index: pi, name: pname, value });
        }
        slots.push(FullSlotSnapshot {
            slot_index: *slot_index as u32,
            processor_name: name.clone(),
            bypassed: *is_bypassed,
            mix: *mix,
            params,
        });
    }
    FullChainSnapshot::now(track_id, slots, label)
}

// ─── Restore result ──────────────────────────────────────────────────────────

#[derive(Serialize)]
struct RestoreResult {
    ok: bool,
    track_id: u32,
    slots_restored: u32,
    params_set: u32,
    label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn make_ok_json(snap: &FullChainSnapshot, params_set: u32) -> String {
    let r = RestoreResult {
        ok: true,
        track_id: snap.track_id,
        slots_restored: snap.slots.len() as u32,
        params_set,
        label: snap.label.clone(),
        error: None,
    };
    serde_json::to_string(&r).unwrap_or_else(|_| r#"{"ok":true}"#.to_string())
}

fn make_err_json(track_id: u32, msg: &str) -> String {
    let r = RestoreResult {
        ok: false,
        track_id,
        slots_restored: 0,
        params_set: 0,
        label: String::new(),
        error: Some(msg.to_string()),
    };
    serde_json::to_string(&r).unwrap_or_else(|_| r#"{"ok":false}"#.to_string())
}

/// Restore an engine insert chain from a `FullChainSnapshot`.
fn restore_snapshot_to_engine(snap: &FullChainSnapshot) -> String {
    let guard = ENGINE.read();
    let Some(engine) = guard.as_ref() else {
        return make_err_json(snap.track_id, "ENGINE not initialised");
    };
    let pb = engine.playback_engine();
    let track_id = snap.track_id as u64;

    // 1. Unload all currently-loaded slots (0–7)
    let info = pb.get_track_insert_info(track_id);
    for (idx, _name, is_loaded, _, _, _, _) in &info {
        if *is_loaded {
            pb.unload_track_insert(track_id, *idx);
        }
    }

    // 2. Load + configure each slot from snapshot
    let sample_rate = pb.sample_rate() as f64;
    let mut params_set: u32 = 0;

    for slot in &snap.slots {
        let si = slot.slot_index as usize;

        // Try the snapshot's stored name as a factory key first, then
        // fall back to the display-name → factory-key map. The
        // double-lookup is intentional: legacy snapshots and snapshots
        // captured via `get_track_insert_info` carry the *display name*
        // ("FluxForge Studio Compressor"), while preset/UI flows that
        // already canonicalised the key send the factory string
        // ("compressor"). Both must restore correctly. Without the
        // fallback, processors whose display ≠ factory (compressor,
        // limiter, room-correction) silently drop on undo / preset
        // apply — see the chain_preset_integration_tests fix log.
        let processor_opt = rf_engine::create_processor_extended(
            &slot.processor_name,
            sample_rate,
        )
        .or_else(|| {
            rf_engine::display_name_to_factory_key(&slot.processor_name)
                .and_then(|key| {
                    rf_engine::create_processor_extended(key, sample_rate)
                })
        });
        match processor_opt {
            Some(processor) => {
                let ok = pb.load_track_insert(track_id, si, processor);
                if !ok {
                    log::warn!(
                        "[chain_history] load_track_insert returned false: track={} slot={} proc='{}'",
                        track_id, si, slot.processor_name
                    );
                    continue;
                }
            }
            None => {
                log::warn!(
                    "[chain_history] unknown processor '{}' — slot {} skipped on restore",
                    slot.processor_name, si
                );
                continue;
            }
        }

        // 3. Restore parameters by index
        for p in &slot.params {
            pb.set_track_insert_param(track_id, si, p.index, p.value);
            params_set += 1;
        }

        // 4. Set bypass and mix
        pb.set_track_insert_bypass(track_id, si, slot.bypassed);
        pb.set_track_insert_mix(track_id, si, slot.mix);
    }

    make_ok_json(snap, params_set)
}

// ─── Auto-push hook (called by chain_apply_ffi before each execute) ──────────

/// Called by `chain_apply_execute_json` before applying a non-dry-run plan.
/// Captures current engine state and pushes it as the before-state for undo.
/// `label` should describe the operation being applied (e.g. "Apply Vocal Bright").
pub(crate) fn push_current_snapshot(track_id: u32, label: &str) {
    let snap = capture_snapshot(track_id, label);
    CHAIN_HISTORY.write().push(snap);
}

// ─── FFI: capture / push ─────────────────────────────────────────────────────

/// Capture the current insert chain state for `track_id` as a JSON string.
/// Useful for external persistence (project files, user presets).
/// Returns null on ENGINE not-initialized or serialization error.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_history_capture_json(track_id: u32) -> *mut c_char {
    let snap = capture_snapshot(track_id, "capture");
    match serde_json::to_string(&snap) {
        Ok(s) => CString::new(s).map(CString::into_raw).unwrap_or(ptr::null_mut()),
        Err(e) => {
            log::warn!("[chain_history] capture_json serialize: {e}");
            ptr::null_mut()
        }
    }
}

/// Push a previously-captured `FullChainSnapshot` JSON onto the undo stack.
/// Returns 1 on success, 0 on parse error or null pointer.
#[unsafe(no_mangle)]
pub extern "C" fn chain_history_push_json(snapshot_json: *const c_char) -> i32 {
    if snapshot_json.is_null() {
        return 0;
    }
    let s = match unsafe { CStr::from_ptr(snapshot_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };
    match serde_json::from_str::<FullChainSnapshot>(s) {
        Ok(snap) => {
            CHAIN_HISTORY.write().push(snap);
            1
        }
        Err(e) => {
            log::warn!("[chain_history] push_json parse: {e}");
            0
        }
    }
}

/// Apply a `FullChainSnapshot` JSON directly to the engine, with an
/// automatic undo-push of the *current* state first.
///
/// Used by the chain preset library (Wave 2 Front 5): a preset stores a
/// `FullChainSnapshot`; loading it should look identical to any other
/// `chain_apply_execute` from the user's POV (single-step undo restores
/// what was loaded before).
///
/// Behaviour mirrors `chain_apply_execute_json`:
///   1. Capture current engine chain → push onto undo stack with the
///      snapshot's label (or "preset apply" fallback).
///   2. Unload all currently-loaded slots.
///   3. Load each snapshot slot, set parameters, set bypass + mix.
///
/// Returns the same `RestoreResult` JSON shape as `chain_undo_json`
/// (`{"ok":true,"track_id":...,"slots_restored":...,"params_set":...,"label":...}`)
/// or an error envelope.
///
/// **Caller must free with `chain_history_free_string`.**
///
/// # Safety
/// `snapshot_json` must be a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub extern "C" fn chain_history_apply_snapshot_json(
    snapshot_json: *const c_char,
) -> *mut c_char {
    if snapshot_json.is_null() {
        let err = make_err_json(0, "null snapshot");
        return CString::new(err).map(CString::into_raw).unwrap_or(ptr::null_mut());
    }
    let s = match unsafe { CStr::from_ptr(snapshot_json) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            let err = make_err_json(0, "snapshot not utf-8");
            return CString::new(err).map(CString::into_raw).unwrap_or(ptr::null_mut());
        }
    };
    let snap: FullChainSnapshot = match serde_json::from_str(s) {
        Ok(v) => v,
        Err(e) => {
            let err = make_err_json(0, &format!("parse error: {}", e));
            return CString::new(err).map(CString::into_raw).unwrap_or(ptr::null_mut());
        }
    };

    // Auto-push undo so the user can revert the preset apply with a
    // single Cmd-Z. Use the snapshot label if present, else a generic.
    let label = if snap.label.is_empty() {
        "preset apply".to_string()
    } else {
        snap.label.clone()
    };
    push_current_snapshot(snap.track_id, &label);

    let result = restore_snapshot_to_engine(&snap);
    CString::new(result).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

// ─── FFI: depths + labels ────────────────────────────────────────────────────

/// How many undo steps are available for `track_id`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_undo_depth(track_id: u32) -> i32 {
    CHAIN_HISTORY.read().undo_depth(track_id) as i32
}

/// How many redo steps are available for `track_id`.
#[unsafe(no_mangle)]
pub extern "C" fn chain_redo_depth(track_id: u32) -> i32 {
    CHAIN_HISTORY.read().redo_depth(track_id) as i32
}

/// Label of the step that would be undone next, or null if stack empty.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_undo_label_json(track_id: u32) -> *mut c_char {
    let guard = CHAIN_HISTORY.read();
    match guard.undo_label(track_id) {
        Some(label) => CString::new(label).map(CString::into_raw).unwrap_or(ptr::null_mut()),
        None => ptr::null_mut(),
    }
}

/// Label of the step that would be redone next, or null if stack empty.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_redo_label_json(track_id: u32) -> *mut c_char {
    let guard = CHAIN_HISTORY.read();
    match guard.redo_label(track_id) {
        Some(label) => CString::new(label).map(CString::into_raw).unwrap_or(ptr::null_mut()),
        None => ptr::null_mut(),
    }
}

// ─── FFI: Undo ───────────────────────────────────────────────────────────────

/// Undo the most recent chain apply for `track_id`.
///
/// - Captures current engine state → pushed onto redo stack
/// - Pops undo stack → restores engine
/// - Returns a JSON result object (same shape as `ExecuteResult`)
///
/// Returns a JSON error object if nothing to undo.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_undo_json(track_id: u32) -> *mut c_char {
    let current = capture_snapshot(track_id, "pre-undo");
    let target = CHAIN_HISTORY.write().undo(track_id, current);

    let result = match target {
        None => make_err_json(track_id, "nothing to undo"),
        Some(snap) => restore_snapshot_to_engine(&snap),
    };
    CString::new(result).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

// ─── FFI: Redo ───────────────────────────────────────────────────────────────

/// Redo the most recently undone chain apply for `track_id`.
///
/// - Captures current engine state → pushed onto undo stack
/// - Pops redo stack → restores engine
/// - Returns a JSON result object
///
/// Returns a JSON error object if nothing to redo.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_redo_json(track_id: u32) -> *mut c_char {
    let current = capture_snapshot(track_id, "pre-redo");
    let target = CHAIN_HISTORY.write().redo(track_id, current);

    let result = match target {
        None => make_err_json(track_id, "nothing to redo"),
        Some(snap) => restore_snapshot_to_engine(&snap),
    };
    CString::new(result).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

// ─── FFI: history management ─────────────────────────────────────────────────

/// Clear undo + redo stacks for `track_id` (e.g. after a destructive reload).
#[unsafe(no_mangle)]
pub extern "C" fn chain_history_clear(track_id: u32) -> i32 {
    CHAIN_HISTORY.write().clear(track_id);
    1
}

/// Clear history for ALL tracks (call on project close / new).
#[unsafe(no_mangle)]
pub extern "C" fn chain_history_clear_all() -> i32 {
    CHAIN_HISTORY.write().clear_all();
    1
}

// ─── FFI: A/B Slots ──────────────────────────────────────────────────────────

/// Capture current engine chain state for `track_id` → store in A slot.
#[unsafe(no_mangle)]
pub extern "C" fn chain_ab_save_a(track_id: u32) -> i32 {
    let snap = capture_snapshot(track_id, "slot-A");
    CHAIN_HISTORY.write().save_a(snap);
    1
}

/// Capture current engine chain state for `track_id` → store in B slot.
#[unsafe(no_mangle)]
pub extern "C" fn chain_ab_save_b(track_id: u32) -> i32 {
    let snap = capture_snapshot(track_id, "slot-B");
    CHAIN_HISTORY.write().save_b(snap);
    1
}

/// Restore slot A chain for `track_id`.
///
/// Pushes current engine state to undo, restores A, returns JSON result.
/// Returns JSON error if slot A is empty.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_ab_restore_a_json(track_id: u32) -> *mut c_char {
    let snap_opt = CHAIN_HISTORY.read().get_a(track_id).cloned();
    let result = match snap_opt {
        None => make_err_json(track_id, "slot A is empty"),
        Some(snap) => {
            let current = capture_snapshot(track_id, "before-restore-A");
            CHAIN_HISTORY.write().push(current);
            restore_snapshot_to_engine(&snap)
        }
    };
    CString::new(result).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

/// Restore slot B chain for `track_id`.
///
/// Pushes current engine state to undo, restores B, returns JSON result.
/// Returns JSON error if slot B is empty.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_ab_restore_b_json(track_id: u32) -> *mut c_char {
    let snap_opt = CHAIN_HISTORY.read().get_b(track_id).cloned();
    let result = match snap_opt {
        None => make_err_json(track_id, "slot B is empty"),
        Some(snap) => {
            let current = capture_snapshot(track_id, "before-restore-B");
            CHAIN_HISTORY.write().push(current);
            restore_snapshot_to_engine(&snap)
        }
    };
    CString::new(result).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

/// Swap A↔B slot contents in memory (no engine change).
/// Common use: "B sounds better — make it the new A, archive A as B".
#[unsafe(no_mangle)]
pub extern "C" fn chain_ab_swap(track_id: u32) -> i32 {
    CHAIN_HISTORY.write().swap_ab(track_id);
    1
}

/// Get the A-slot snapshot as JSON, or null if slot A is empty.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_ab_get_a_json(track_id: u32) -> *mut c_char {
    let guard = CHAIN_HISTORY.read();
    guard
        .get_a(track_id)
        .and_then(|s| serde_json::to_string(s).ok())
        .and_then(|s| CString::new(s).ok())
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

/// Get the B-slot snapshot as JSON, or null if slot B is empty.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_ab_get_b_json(track_id: u32) -> *mut c_char {
    let guard = CHAIN_HISTORY.read();
    guard
        .get_b(track_id)
        .and_then(|s| serde_json::to_string(s).ok())
        .and_then(|s| CString::new(s).ok())
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

// ─── FFI: status (one-call UI polling) ───────────────────────────────────────

#[derive(Serialize)]
struct HistoryStatusJson {
    track_id: u32,
    undo_depth: usize,
    redo_depth: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    undo_label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    redo_label: Option<String>,
    a_set: bool,
    b_set: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    a_label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    b_label: Option<String>,
}

/// Return a JSON status object for `track_id` — undo/redo depths, labels,
/// and whether A/B slots are populated.  Designed for lightweight UI polling.
/// **Caller must free with `chain_history_free_string`.**
#[unsafe(no_mangle)]
pub extern "C" fn chain_history_status_json(track_id: u32) -> *mut c_char {
    let guard = CHAIN_HISTORY.read();
    let status = HistoryStatusJson {
        track_id,
        undo_depth: guard.undo_depth(track_id),
        redo_depth: guard.redo_depth(track_id),
        undo_label: guard.undo_label(track_id).map(str::to_string),
        redo_label: guard.redo_label(track_id).map(str::to_string),
        a_set: guard.get_a(track_id).is_some(),
        b_set: guard.get_b(track_id).is_some(),
        a_label: guard.get_a(track_id).map(|s| s.label.clone()),
        b_label: guard.get_b(track_id).map(|s| s.label.clone()),
    };
    match serde_json::to_string(&status) {
        Ok(s) => CString::new(s).map(CString::into_raw).unwrap_or(ptr::null_mut()),
        Err(_) => ptr::null_mut(),
    }
}

// ─── Memory ──────────────────────────────────────────────────────────────────

/// Free a string pointer returned by any `chain_history_*` or `chain_ab_*` function.
/// Safe to call with null.
#[unsafe(no_mangle)]
pub extern "C" fn chain_history_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(unsafe { CString::from_raw(ptr) });
    }
}

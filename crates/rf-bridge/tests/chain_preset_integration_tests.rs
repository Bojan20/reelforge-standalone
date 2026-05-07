//! End-to-end integration test for the Wave 2 Front 5 chain preset
//! library, covering the full user journey:
//!
//!   load processors → capture → save preset → list → search → clear
//!     → load preset from disk → apply to live engine → verify engine
//!     state matches → undo → verify revert → export → delete → import
//!
//! Why this lives here (not in `chain_preset_ffi.rs` unit tests):
//!
//! - Unit tests in `chain_preset_ffi.rs` operate on the JSON surface
//!   in isolation — they never touch the audio engine. They prove the
//!   wire format is stable and the disk store works.
//! - This file proves the *whole pipeline*: that a preset captured
//!   from a live engine and re-applied through `chain_history_apply_
//!   snapshot_json` produces the same engine state, and that the
//!   auto-pushed undo entry actually reverts to the prior state.
//!
//! All FFI here goes through `extern "C"` calls (`*const c_char` etc.)
//! to exercise exactly the same surface the Flutter side hits — if a
//! signature drifts in a way Dart wouldn't catch, this test fails.
//!
//! Test isolation:
//! - The whole rf-bridge ENGINE + DIR_OVERRIDE + CHAIN_HISTORY are
//!   global statics. Every test acquires a single shared `Mutex`
//!   guard so they run serially within this binary regardless of
//!   `cargo test --test-threads=N`.
//! - Each test resets the preset dir to a unique temp dir and clears
//!   chain history at start.

use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::sync::Mutex;

use rf_bridge::{
    chain_history_ffi::{
        chain_history_apply_snapshot_json, chain_history_capture_json, chain_history_clear_all,
        chain_history_free_string, chain_undo_depth, chain_undo_json,
    },
    chain_preset_ffi::{
        chain_preset_delete, chain_preset_export_json, chain_preset_free_string,
        chain_preset_import_path, chain_preset_list_json, chain_preset_load_json,
        chain_preset_save_json, chain_preset_search_json, chain_preset_set_dir,
    },
};

// ─── Test serialisation lock ────────────────────────────────────────────────

static SHARED_LOCK: Mutex<()> = Mutex::new(());

fn isolate_state(test_name: &str) -> PathBuf {
    // Unique temp dir for the preset store
    let dir = std::env::temp_dir().join(format!(
        "rf_chain_preset_e2e_{}_{}",
        test_name,
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).unwrap();

    // Set preset dir override
    let cstr = CString::new(dir.to_string_lossy().as_ref()).unwrap();
    let raw = chain_preset_set_dir(cstr.as_ptr());
    free_preset_string(raw);

    // Wipe undo/redo + A/B for every track
    chain_history_clear_all();

    dir
}

// ─── String helpers ─────────────────────────────────────────────────────────

fn read_and_free_preset(ptr: *mut c_char) -> String {
    assert!(!ptr.is_null(), "preset FFI returned null");
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
    chain_preset_free_string(ptr);
    s
}

fn read_and_free_history(ptr: *mut c_char) -> String {
    assert!(!ptr.is_null(), "history FFI returned null");
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
    chain_history_free_string(ptr);
    s
}

fn free_preset_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        chain_preset_free_string(ptr);
    }
}

// ─── Engine helpers ─────────────────────────────────────────────────────────

/// Initialise the engine if not already initialised. Returns true if
/// the engine is now usable. Tests that rely on engine state should
/// `assert!(ensure_engine())` to fail loudly when init breaks.
fn ensure_engine() -> bool {
    if rf_bridge::engine_is_running() {
        return true;
    }
    rf_bridge::engine_init()
}

/// Manually load a processor into a track's insert slot via the same
/// `insert_load` path the UI uses. Returns true on success.
fn load_processor(track_id: u32, slot: usize, name: &str) -> bool {
    rf_bridge::insert_load(track_id, slot, name.to_string())
}

/// Set bypass on a slot — used to introduce non-default state we can
/// verify round-trips through the snapshot pipeline. There's no public
/// `insert_set_param` wrapper on the FFI surface (only the internal
/// engine bridge has it), so bypass is the cleanest non-default we can
/// dial from a black-box test.
fn set_bypass(track_id: u32, slot: usize, bypassed: bool) -> bool {
    rf_bridge::insert_set_bypass(track_id, slot, bypassed)
}

/// Set wet/dry mix on a slot.
fn set_mix(track_id: u32, slot: usize, mix: f64) -> bool {
    rf_bridge::insert_set_mix(track_id, slot, mix)
}

/// Capture the current engine chain as JSON.
fn capture(track_id: u32) -> String {
    let raw = chain_history_capture_json(track_id);
    read_and_free_history(raw)
}

// ─── Tests ──────────────────────────────────────────────────────────────────

#[test]
fn end_to_end_preset_roundtrip_with_engine_apply_and_undo() {
    // Recover from poison — when one test panics we still want the
    // others to run (the lock is just a serialiser, not state).
    let _g = SHARED_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    if !ensure_engine() {
        // CI without audio device → engine init can fail. Skip rather
        // than fail; pure FFI tests in chain_preset_ffi.rs already
        // cover the no-engine path.
        eprintln!("[skip] engine init failed — likely no audio device");
        return;
    }
    let _store = isolate_state("e2e_roundtrip");

    let track_id = 11_u32;

    // Wipe any prior chain on this track.
    for slot in 0..8 {
        rf_bridge::insert_unload(track_id, slot);
    }

    // ── 1. Build a real chain on the live engine ────────────────────
    assert!(load_processor(track_id, 0, "compressor"),
        "compressor failed to load — engine processor registry broken?");
    assert!(load_processor(track_id, 1, "pro-eq"),
        "pro-eq failed to load");

    // Dial in non-default state so the snapshot round-trip is verifiable:
    //   - compressor bypassed
    //   - pro-eq mixed at 0.65 wet
    set_bypass(track_id, 0, true);
    set_mix(track_id, 1, 0.65);

    // ── 2. Capture → save preset ───────────────────────────────────
    let captured_json = capture(track_id);
    // capture stores the processor's *display name*
    // ("FluxForge Studio Compressor"), not the factory key
    // ("compressor"). The restore path handles both via the
    // display→factory fallback, but the on-disk format is whatever
    // capture writes. Match the display strings here so the assertion
    // doesn't drift if a wrapper is renamed.
    assert!(captured_json.contains("FluxForge Studio Compressor"),
        "captured snapshot missing compressor: {}", captured_json);
    assert!(captured_json.contains("FluxForge Studio Pro-EQ 64"),
        "captured snapshot missing pro-eq: {}", captured_json);

    let save_req = serde_json::json!({
        "name": "E2E Bright",
        "description": "Roundtrip test",
        "tags": ["test", "e2e"],
        // The Rust capture's snapshot field is the FullChainSnapshot
        // itself; SaveRequest expects `snapshot` to BE the snapshot.
        "snapshot": serde_json::from_str::<serde_json::Value>(&captured_json).unwrap(),
    });
    let save_c = CString::new(save_req.to_string()).unwrap();
    let save_resp = read_and_free_preset(chain_preset_save_json(save_c.as_ptr()));
    assert!(save_resp.contains("\"ok\":true"), "save failed: {}", save_resp);
    assert!(save_resp.contains("E2E Bright"));

    // ── 3. List + search ────────────────────────────────────────────
    let list_resp = read_and_free_preset(chain_preset_list_json());
    assert!(list_resp.contains("E2E Bright"));
    assert!(list_resp.contains("\"slot_count\":2"),
        "expected 2 slots in list, got: {}", list_resp);

    let q = CString::new("e2e").unwrap();
    let search_resp = read_and_free_preset(chain_preset_search_json(q.as_ptr()));
    assert!(search_resp.contains("E2E Bright"));

    // ── 4. Clear engine chain so apply has work to do ──────────────
    for slot in 0..8 {
        rf_bridge::insert_unload(track_id, slot);
    }
    let cleared = capture(track_id);
    let cleared_v: serde_json::Value = serde_json::from_str(&cleared).unwrap();
    let cleared_slots = cleared_v["slots"].as_array().unwrap();
    assert!(cleared_slots.is_empty(),
        "expected empty chain after unload, got: {:?}", cleared_slots);

    // ── 5. Load preset from disk + apply to engine ─────────────────
    let load_c = CString::new("E2E Bright").unwrap();
    let load_resp = read_and_free_preset(chain_preset_load_json(load_c.as_ptr()));
    assert!(load_resp.contains("\"name\":\"E2E Bright\""));

    // Extract the snapshot field and feed it to apply.
    let preset_v: serde_json::Value = serde_json::from_str(&load_resp).unwrap();
    let snapshot_v = preset_v["snapshot"].clone();
    let snapshot_json = snapshot_v.to_string();
    let snap_c = CString::new(snapshot_json.clone()).unwrap();

    let undo_depth_before = chain_undo_depth(track_id);

    let apply_resp = read_and_free_history(
        chain_history_apply_snapshot_json(snap_c.as_ptr()),
    );
    assert!(apply_resp.contains("\"ok\":true"),
        "apply failed: {}", apply_resp);
    assert!(apply_resp.contains("\"slots_restored\":2"));

    // Undo depth must have grown by 1 (auto-pushed pre-state).
    assert_eq!(chain_undo_depth(track_id), undo_depth_before + 1,
        "apply did not push undo entry");

    // ── 6. Verify engine state matches captured ─────────────────────
    let restored = capture(track_id);
    let restored_v: serde_json::Value = serde_json::from_str(&restored).unwrap();
    let restored_slots = restored_v["slots"].as_array().unwrap();
    assert_eq!(restored_slots.len(), 2,
        "expected 2 restored slots, got: {:?}", restored_slots);

    // After restore the engine re-loads each processor and we
    // re-capture; processor_name in the new snapshot is again the
    // display string. The order must match the original chain.
    let proc_names: Vec<&str> = restored_slots.iter()
        .map(|s| s["processor_name"].as_str().unwrap()).collect();
    assert_eq!(proc_names,
        vec!["FluxForge Studio Compressor", "FluxForge Studio Pro-EQ 64"]);

    // Bypass + mix must round-trip — these were the non-default state
    // we dialled in step 1.
    let comp_bypassed = restored_slots[0]["bypassed"].as_bool().unwrap();
    assert!(comp_bypassed,
        "compressor bypass did not round-trip — got {:?}", restored_slots[0]);

    let eq_mix = restored_slots[1]["mix"].as_f64().unwrap();
    assert!((eq_mix - 0.65).abs() < 0.01,
        "pro-eq mix did not round-trip — expected 0.65, got {}", eq_mix);

    // ── 7. Undo → verify engine reverts to empty ────────────────────
    let undo_resp = read_and_free_history(chain_undo_json(track_id));
    assert!(undo_resp.contains("\"ok\":true"),
        "undo failed: {}", undo_resp);
    let after_undo = capture(track_id);
    let after_v: serde_json::Value = serde_json::from_str(&after_undo).unwrap();
    let after_slots = after_v["slots"].as_array().unwrap();
    assert!(after_slots.is_empty(),
        "expected empty chain after undo, got: {:?}", after_slots);
}

#[test]
fn export_import_roundtrip_via_engine_path() {
    // Recover from poison — when one test panics we still want the
    // others to run (the lock is just a serialiser, not state).
    let _g = SHARED_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    if !ensure_engine() {
        eprintln!("[skip] engine init failed");
        return;
    }
    let store_a = isolate_state("export_import_a");

    let track_id = 12_u32;
    for slot in 0..8 {
        rf_bridge::insert_unload(track_id, slot);
    }
    assert!(load_processor(track_id, 0, "limiter"));

    let captured_json = capture(track_id);

    let save_req = serde_json::json!({
        "name": "Portable",
        "description": "ex/im",
        "tags": ["share"],
        "snapshot": serde_json::from_str::<serde_json::Value>(&captured_json).unwrap(),
    });
    let save_c = CString::new(save_req.to_string()).unwrap();
    let _ = read_and_free_preset(chain_preset_save_json(save_c.as_ptr()));

    // Export to an external file
    let dest = std::env::temp_dir().join(format!(
        "rf_export_e2e_{}.json",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let exp_req = serde_json::json!({
        "name": "Portable",
        "dest": dest.to_string_lossy().to_string(),
    });
    let exp_c = CString::new(exp_req.to_string()).unwrap();
    let exp_resp = read_and_free_preset(chain_preset_export_json(exp_c.as_ptr()));
    assert!(exp_resp.contains("\"ok\":true"), "export: {}", exp_resp);
    assert!(dest.exists());

    // Switch to a fresh store and import the file there
    let _store_b = isolate_state("export_import_b");
    let imp_c = CString::new(dest.to_string_lossy().as_ref()).unwrap();
    let imp_resp = read_and_free_preset(chain_preset_import_path(imp_c.as_ptr()));
    assert!(imp_resp.contains("\"ok\":true"), "import: {}", imp_resp);
    assert!(imp_resp.contains("Portable"),
        "imported preset name not echoed: {}", imp_resp);

    // The imported preset should be loadable from the new store.
    // capture stores the limiter's display name, not the factory key —
    // either substring proves the round-trip carried the slot intact.
    let load_c = CString::new("Portable").unwrap();
    let load_resp = read_and_free_preset(chain_preset_load_json(load_c.as_ptr()));
    assert!(
        load_resp.contains("FluxForge Studio True Peak Limiter")
            || load_resp.contains("\"limiter\""),
        "imported preset missing original processor: {}", load_resp);

    // Cleanup
    let _ = std::fs::remove_file(&dest);
    let _ = std::fs::remove_dir_all(&store_a);
}

#[test]
fn delete_removes_preset_and_returns_idempotent_zero() {
    // Recover from poison — when one test panics we still want the
    // others to run (the lock is just a serialiser, not state).
    let _g = SHARED_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    if !ensure_engine() {
        eprintln!("[skip] engine init failed");
        return;
    }
    let _store = isolate_state("delete");

    let track_id = 13_u32;
    for slot in 0..8 {
        rf_bridge::insert_unload(track_id, slot);
    }
    assert!(load_processor(track_id, 0, "gate"));

    let captured_json = capture(track_id);
    let save_req = serde_json::json!({
        "name": "Disposable",
        "description": "",
        "tags": [],
        "snapshot": serde_json::from_str::<serde_json::Value>(&captured_json).unwrap(),
    });
    let save_c = CString::new(save_req.to_string()).unwrap();
    let _ = read_and_free_preset(chain_preset_save_json(save_c.as_ptr()));

    let n = CString::new("Disposable").unwrap();
    assert_eq!(chain_preset_delete(n.as_ptr()), 1,
        "first delete should remove and return 1");
    assert_eq!(chain_preset_delete(n.as_ptr()), 0,
        "second delete should be idempotent (return 0)");

    // List must no longer contain it
    let list_resp = read_and_free_preset(chain_preset_list_json());
    assert!(!list_resp.contains("Disposable"),
        "list still contains deleted preset: {}", list_resp);
}

#[test]
fn apply_snapshot_with_invalid_json_returns_error_envelope() {
    // Recover from poison — when one test panics we still want the
    // others to run (the lock is just a serialiser, not state).
    let _g = SHARED_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    // Engine not required for parse-error path
    let _store = isolate_state("apply_invalid");

    let bad = CString::new("{ not a snapshot }").unwrap();
    let resp = read_and_free_history(
        chain_history_apply_snapshot_json(bad.as_ptr()),
    );
    assert!(resp.contains("\"ok\":false"),
        "expected error envelope, got: {}", resp);
    assert!(resp.contains("error"));
}

#[test]
fn apply_snapshot_with_null_pointer_returns_error_envelope() {
    // Recover from poison — when one test panics we still want the
    // others to run (the lock is just a serialiser, not state).
    let _g = SHARED_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let resp = read_and_free_history(
        chain_history_apply_snapshot_json(std::ptr::null()),
    );
    assert!(resp.contains("\"ok\":false"));
    assert!(resp.contains("null snapshot"));
}

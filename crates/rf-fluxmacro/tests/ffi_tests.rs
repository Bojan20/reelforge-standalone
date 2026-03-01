// ============================================================================
// rf-fluxmacro — FFI Integration Tests
// ============================================================================
// FM-37: Tests for the FluxMacro FFI bridge functions.
// Tests lifecycle, run, validate, steps, progress, history.
// These test the Rust API directly (not via C FFI boundary).
// ============================================================================

use rf_fluxmacro::interpreter::MacroInterpreter;
use rf_fluxmacro::parser;
use rf_fluxmacro::steps::{register_all_steps, StepRegistry};
use rf_fluxmacro::version;

/// Build a fully-equipped interpreter.
fn build_interpreter() -> MacroInterpreter {
    let mut registry = StepRegistry::new();
    register_all_steps(&mut registry);
    MacroInterpreter::new(registry)
}

const MINIMAL_YAML: &str = r#"
macro: ffi_test
input:
  game_id: "FFITestGame"
  volatility: "medium"
options:
  seed: 12345
steps:
  - naming.validate
"#;

const FULL_YAML: &str = r#"
macro: ffi_full
input:
  game_id: "FFIFullGame"
  volatility: "high"
  mechanics:
    - "free_spins"
    - "hold_and_win"
  platforms:
    - "desktop"
    - "mobile"
options:
  seed: 42
  fail_fast: true
steps:
  - adb.generate
  - naming.validate
  - volatility.profile.generate
"#;

// ─── Interpreter API Tests (simulating FFI flow) ────────────────────────────

#[test]
fn ffi_init_and_step_count() {
    let interp = build_interpreter();
    assert_eq!(interp.registry().len(), 11, "Should have 11 registered steps");
}

#[test]
fn ffi_list_steps() {
    let interp = build_interpreter();
    let names = interp.registry().list();

    assert!(names.contains(&"adb.generate".to_string()));
    assert!(names.contains(&"naming.validate".to_string()));
    assert!(names.contains(&"qa.run_suite".to_string()));
    assert!(names.contains(&"qa.loudness".to_string()));
    assert!(names.contains(&"pack.release".to_string()));
}

#[test]
fn ffi_validate_valid_yaml() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(MINIMAL_YAML).unwrap();
    let warnings = interp.validate(&macro_file).unwrap();

    // Should have warnings about no mechanics
    assert!(!warnings.is_empty());
}

#[test]
fn ffi_validate_full_yaml() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(FULL_YAML).unwrap();
    let warnings = interp.validate(&macro_file).unwrap();

    // Full YAML has mechanics, so fewer warnings expected
    assert!(
        !warnings.iter().any(|w| w.contains("mechanics")),
        "Should not warn about mechanics"
    );
}

#[test]
fn ffi_validate_invalid_yaml() {
    let result = parser::parse_macro_string("not valid yaml [[[");
    assert!(result.is_err());
}

#[test]
fn ffi_validate_missing_game_id() {
    let yaml = r#"
macro: test
input: {}
steps:
  - naming.validate
"#;
    let result = parser::parse_macro_string(yaml);
    assert!(result.is_err());
}

#[test]
fn ffi_run_minimal() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(MINIMAL_YAML).unwrap();
    let dir = tempfile::tempdir().unwrap();

    let ctx = interp.run(&macro_file, dir.path().to_path_buf()).unwrap();

    assert_eq!(ctx.game_id, "FFITestGame");
    assert_eq!(ctx.seed, 12345);
    assert!(!ctx.run_hash.is_empty());
}

#[test]
fn ffi_run_deterministic() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(MINIMAL_YAML).unwrap();

    let dir1 = tempfile::tempdir().unwrap();
    let dir2 = tempfile::tempdir().unwrap();

    let ctx1 = interp.run(&macro_file, dir1.path().to_path_buf()).unwrap();
    let ctx2 = interp.run(&macro_file, dir2.path().to_path_buf()).unwrap();

    assert_eq!(
        ctx1.run_hash, ctx2.run_hash,
        "Same seed should produce same hash"
    );
}

#[test]
fn ffi_run_full_pipeline() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(FULL_YAML).unwrap();
    let dir = tempfile::tempdir().unwrap();

    let ctx = interp.run(&macro_file, dir.path().to_path_buf()).unwrap();

    assert_eq!(ctx.game_id, "FFIFullGame");
    assert!(!ctx.run_hash.is_empty());
    // Should have generated artifacts
    assert!(!ctx.artifacts.is_empty(), "Full pipeline should produce artifacts");
}

#[test]
fn ffi_run_saves_history() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(MINIMAL_YAML).unwrap();
    let dir = tempfile::tempdir().unwrap();

    let _ctx = interp.run(&macro_file, dir.path().to_path_buf()).unwrap();

    // History should be saved
    let runs = version::list_runs(dir.path()).unwrap();
    assert!(!runs.is_empty(), "Should have saved run history");

    // Load run metadata
    let (run_id, run_path) = &runs[0];
    assert!(!run_id.is_empty());
    let meta = version::load_run_meta(run_path).unwrap();
    assert_eq!(meta.game_id, "FFITestGame");
    assert_eq!(meta.seed, 12345);
    assert!(meta.success);
}

#[test]
fn ffi_run_result_json() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(MINIMAL_YAML).unwrap();
    let dir = tempfile::tempdir().unwrap();

    let ctx = interp.run(&macro_file, dir.path().to_path_buf()).unwrap();

    // Build result JSON (same as FFI bridge does)
    let result = serde_json::json!({
        "success": ctx.is_success(),
        "game_id": ctx.game_id,
        "seed": ctx.seed,
        "run_hash": ctx.run_hash,
        "duration_ms": ctx.duration().as_millis() as u64,
        "qa_passed": ctx.qa_passed_count(),
        "qa_failed": ctx.qa_failed_count(),
        "artifacts": ctx.artifacts.keys().collect::<Vec<_>>(),
        "warnings": ctx.warnings,
        "errors": ctx.errors,
    });

    // Serialize to JSON string (what FFI would return)
    let json_str = serde_json::to_string(&result).unwrap();
    assert!(!json_str.is_empty());

    // Deserialize back (what Dart would do)
    let parsed: serde_json::Value = serde_json::from_str(&json_str).unwrap();
    assert_eq!(parsed["game_id"], "FFITestGame");
    assert_eq!(parsed["seed"], 12345);
}

#[test]
fn ffi_cancellation() {
    let _interp = build_interpreter();
    let _macro_file = parser::parse_macro_string(MINIMAL_YAML).unwrap();
    let dir = tempfile::tempdir().unwrap();

    // Build context manually and cancel before running
    let ctx = rf_fluxmacro::MacroContext::new("Test".to_string(), dir.path().to_path_buf());
    ctx.cancel();
    assert!(ctx.is_cancelled());
}

#[test]
fn ffi_history_list_and_detail() {
    let interp = build_interpreter();
    let macro_file = parser::parse_macro_string(MINIMAL_YAML).unwrap();
    let dir = tempfile::tempdir().unwrap();

    // Run twice with a 1-second gap so run IDs differ
    let _ctx1 = interp.run(&macro_file, dir.path().to_path_buf()).unwrap();
    std::thread::sleep(std::time::Duration::from_secs(1));
    let _ctx2 = interp.run(&macro_file, dir.path().to_path_buf()).unwrap();

    let runs = version::list_runs(dir.path()).unwrap();
    assert!(runs.len() >= 2, "Should have at least 2 runs, got {}", runs.len());

    // Newest first
    assert!(runs[0].0 >= runs[1].0, "Should be sorted newest first");

    // Detail for first run
    let meta = version::load_run_meta(&runs[0].1).unwrap();
    assert_eq!(meta.macro_name, "ffi_test");
    assert_eq!(meta.game_id, "FFITestGame");
}

#[test]
fn ffi_step_not_found() {
    let interp = build_interpreter();
    let yaml = r#"
macro: bad_step
input:
  game_id: "Test"
steps:
  - nonexistent.step
"#;
    let macro_file = parser::parse_macro_string(yaml).unwrap();
    let dir = tempfile::tempdir().unwrap();

    let result = interp.run(&macro_file, dir.path().to_path_buf());
    assert!(result.is_err());
}

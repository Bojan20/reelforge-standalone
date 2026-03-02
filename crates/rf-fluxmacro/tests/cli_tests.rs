// ============================================================================
// rf-fluxmacro — CLI Integration Tests
// ============================================================================
// FM-36: Tests for the fluxmacro CLI binary.
// Tests: run, dry-run, validate, steps, qa, adb, history, --ci mode.
// ============================================================================

use std::fs;
use std::path::PathBuf;
use std::process::Command;

/// Get the path to the fluxmacro binary (built in the workspace target dir).
fn fluxmacro_bin() -> PathBuf {
    // The binary is built to the workspace target directory
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop(); // up from crates/rf-fluxmacro
    path.pop(); // up from crates/
    path.push("target");

    // Check fast profile first, then debug, then release
    for profile in &["fast", "debug", "release"] {
        let bin = path.join(profile).join("fluxmacro");
        if bin.exists() {
            return bin;
        }
    }

    // Fallback: cargo will build it via `cargo test`
    path.join("debug").join("fluxmacro")
}

/// Create a temporary macro file for testing.
fn create_test_macro(dir: &std::path::Path, name: &str, steps: &[&str]) -> PathBuf {
    let steps_yaml: String = steps.iter().map(|s| format!("  - {s}\n")).collect();
    let content = format!(
        r#"macro: {name}
input:
  game_id: "TestCLI"
  volatility: "medium"
  mechanics:
    - "free_spins"
  platforms:
    - "desktop"
options:
  seed: 42
  fail_fast: true
steps:
{steps_yaml}"#
    );

    let path = dir.join(format!("{name}.ffmacro.yaml"));
    fs::write(&path, content).unwrap();
    path
}

// ─── Tests ──────────────────────────────────────────────────────────────────

#[test]
fn cli_steps_command() {
    let output = Command::new(fluxmacro_bin())
        .args(["steps"])
        .output()
        .expect("failed to run fluxmacro steps");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        stdout.contains("adb.generate"),
        "Should list adb.generate step"
    );
    assert!(
        stdout.contains("qa.loudness"),
        "Should list qa.loudness step"
    );
    assert!(stdout.contains("11"), "Should show 11 steps");
}

#[test]
fn cli_steps_ci_json() {
    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "steps"])
        .output()
        .expect("failed to run fluxmacro --ci steps");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .unwrap_or_else(|e| panic!("Invalid JSON output: {e}\nGot: {stdout}"));

    assert_eq!(json["count"], 11);
    assert!(json["steps"].is_array());
}

#[test]
fn cli_validate_valid_macro() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_test_macro(dir.path(), "valid_test", &["naming.validate"]);

    let output = Command::new(fluxmacro_bin())
        .args(["validate", macro_path.to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro validate");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("valid"), "Should indicate valid macro");
    assert!(output.status.success(), "Should exit 0 for valid macro");
}

#[test]
fn cli_validate_ci_json() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_test_macro(dir.path(), "valid_ci", &["naming.validate"]);

    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "validate", macro_path.to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro --ci validate");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .unwrap_or_else(|e| panic!("Invalid JSON: {e}\nGot: {stdout}"));

    assert_eq!(json["valid"], true);
    assert_eq!(json["game_id"], "TestCLI");
}

#[test]
fn cli_validate_invalid_macro() {
    let dir = tempfile::tempdir().unwrap();
    let bad_path = dir.path().join("bad.ffmacro.yaml");
    fs::write(&bad_path, "not valid yaml at all [[[").unwrap();

    let output = Command::new(fluxmacro_bin())
        .args(["validate", bad_path.to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro validate");

    assert!(!output.status.success(), "Should exit 1 for invalid macro");
}

#[test]
fn cli_dry_run() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_test_macro(
        dir.path(),
        "dryrun_test",
        &["adb.generate", "naming.validate"],
    );

    let output = Command::new(fluxmacro_bin())
        .args(["dry-run", macro_path.to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro dry-run");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Dry-Run"), "Should show dry-run header");
    assert!(stdout.contains("adb.generate"), "Should list adb.generate");
    assert!(
        stdout.contains("naming.validate"),
        "Should list naming.validate"
    );
    assert!(output.status.success(), "Should exit 0");
}

#[test]
fn cli_dry_run_ci_json() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_test_macro(
        dir.path(),
        "dryrun_ci",
        &["adb.generate", "naming.validate"],
    );

    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "dry-run", macro_path.to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro --ci dry-run");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .unwrap_or_else(|e| panic!("Invalid JSON: {e}\nGot: {stdout}"));

    assert_eq!(json["success"], true);
    assert_eq!(json["mode"], "dry-run");
    assert_eq!(json["step_count"], 2);
}

#[test]
fn cli_history_empty() {
    let dir = tempfile::tempdir().unwrap();

    let output = Command::new(fluxmacro_bin())
        .args(["history", "-w", dir.path().to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro history");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        stdout.contains("No run history") || stdout.contains("0 runs"),
        "Should indicate no history found. Got: {stdout}"
    );
    assert!(output.status.success(), "Should exit 0");
}

#[test]
fn cli_history_ci_json_empty() {
    let dir = tempfile::tempdir().unwrap();

    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "history", "-w", dir.path().to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro --ci history");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .unwrap_or_else(|e| panic!("Invalid JSON: {e}\nGot: {stdout}"));

    assert_eq!(json["count"], 0);
    assert!(json["runs"].is_array());
}

#[test]
fn cli_nonexistent_file() {
    let output = Command::new(fluxmacro_bin())
        .args(["validate", "/tmp/nonexistent_macro_file.yaml"])
        .output()
        .expect("failed to run fluxmacro");

    assert!(!output.status.success(), "Should exit 1 for missing file");
}

#[test]
fn cli_ci_error_json() {
    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "validate", "/tmp/nonexistent_macro_file.yaml"])
        .output()
        .expect("failed to run fluxmacro");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .unwrap_or_else(|e| panic!("Invalid JSON: {e}\nGot: {stdout}"));

    assert_eq!(json["success"], false);
    assert!(json["error"].is_string(), "Should have error message");
}

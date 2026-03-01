// ============================================================================
// FluxMacro CI Integration Tests — FM-53
// ============================================================================
// Headless mode tests: no TTY, JSON-only output.
// Validates that --ci flag produces valid JSON for all commands,
// determinism holds across runs, and error handling works correctly.
// ============================================================================

use std::fs;
use std::path::PathBuf;
use std::process::Command;

/// Get the fluxmacro binary path.
fn fluxmacro_bin() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop(); // up from crates/rf-fluxmacro
    path.pop(); // up from crates/

    // Check fast profile first, then debug, then release
    for profile in &["fast", "debug", "release"] {
        let bin = path.join("target").join(profile).join("fluxmacro");
        if bin.exists() {
            return bin;
        }
    }

    path.join("target").join("debug").join("fluxmacro")
}

/// Create a test macro file.
fn create_macro(dir: &std::path::Path, name: &str, steps: &[&str]) -> PathBuf {
    let steps_yaml: String = steps.iter().map(|s| format!("  - {s}\n")).collect();
    let content = format!(
        r#"macro: {name}
input:
  game_id: "CITest"
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

/// Run fluxmacro with --ci flag and parse JSON output.
fn run_ci(args: &[&str]) -> (serde_json::Value, bool) {
    let output = Command::new(fluxmacro_bin())
        .arg("--ci")
        .args(args)
        .output()
        .expect("failed to run fluxmacro");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .unwrap_or_else(|e| panic!("Invalid JSON from --ci mode: {e}\nGot: {stdout}"));

    (json, output.status.success())
}

// ─── JSON Output Structure ──────────────────────────────────────────────────

#[test]
fn ci_steps_returns_valid_json() {
    let (json, success) = run_ci(&["steps"]);

    assert!(success, "steps command should succeed");
    assert!(json["count"].is_number(), "Should have numeric count");
    assert!(json["steps"].is_array(), "Should have steps array");

    let steps = json["steps"].as_array().unwrap();
    assert!(!steps.is_empty(), "Should have at least one step");

    // Each step should have name, description, estimated_ms
    for step in steps {
        assert!(step["name"].is_string(), "Step should have name");
        assert!(step["description"].is_string(), "Step should have description");
        assert!(step["estimated_ms"].is_number(), "Step should have estimated_ms");
    }
}

#[test]
fn ci_validate_returns_valid_json() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_macro(dir.path(), "ci_validate", &["naming.validate"]);

    let (json, success) = run_ci(&["validate", macro_path.to_str().unwrap()]);

    assert!(success, "validate should succeed for valid macro");
    assert_eq!(json["valid"], true, "Should report valid=true");
    assert!(json["macro_name"].is_string(), "Should have macro_name");
    assert!(json["game_id"].is_string(), "Should have game_id");
    assert!(json["step_count"].is_number(), "Should have step_count");
    assert!(json["warnings"].is_array(), "Should have warnings array");
}

#[test]
fn ci_dry_run_returns_valid_json() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_macro(dir.path(), "ci_dryrun", &["adb.generate", "naming.validate"]);

    let (json, success) = run_ci(&["dry-run", macro_path.to_str().unwrap()]);

    assert!(success, "dry-run should succeed");
    assert_eq!(json["success"], true);
    assert_eq!(json["mode"], "dry-run");
    assert_eq!(json["step_count"], 2);
    assert!(json["steps"].is_array(), "Should have steps array");
    assert!(json["volatility"].is_string(), "Should have volatility");
}

#[test]
fn ci_run_returns_valid_json() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_macro(dir.path(), "ci_run", &["naming.validate"]);

    let (json, _) = run_ci(&[
        "run",
        macro_path.to_str().unwrap(),
        "--seed",
        "42",
        "-w",
        dir.path().to_str().unwrap(),
    ]);

    // Run output should have all expected fields
    assert!(json["game_id"].is_string(), "Should have game_id");
    assert!(json["seed"].is_number(), "Should have seed");
    assert!(json["run_hash"].is_string(), "Should have run_hash");
    assert!(json["duration_ms"].is_number(), "Should have duration_ms");
    assert!(json["qa_passed"].is_number(), "Should have qa_passed");
    assert!(json["qa_failed"].is_number(), "Should have qa_failed");
    assert!(json["artifacts"].is_array(), "Should have artifacts");
    assert!(json["warnings"].is_array(), "Should have warnings");
    assert!(json["errors"].is_array(), "Should have errors");
}

#[test]
fn ci_history_empty_returns_valid_json() {
    let dir = tempfile::tempdir().unwrap();

    let (json, success) = run_ci(&["history", "-w", dir.path().to_str().unwrap()]);

    assert!(success, "history should succeed even if empty");
    assert_eq!(json["count"], 0);
    assert!(json["runs"].is_array(), "Should have runs array");
    assert!(json["runs"].as_array().unwrap().is_empty());
}

// ─── No TTY / Headless ──────────────────────────────────────────────────────

#[test]
fn ci_no_logging_to_stderr() {
    // --ci mode should suppress env_logger so no log output goes to stderr
    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "steps"])
        .output()
        .expect("failed to run fluxmacro");

    let stderr = String::from_utf8_lossy(&output.stderr);
    // In CI mode, env_logger should not be initialized, so stderr should be empty
    assert!(
        stderr.is_empty() || !stderr.contains("INFO") && !stderr.contains("DEBUG"),
        "CI mode should not log to stderr. Got: {stderr}"
    );
}

#[test]
fn ci_stdout_is_pure_json() {
    // Ensure stdout contains ONLY valid JSON, no extra lines
    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "steps"])
        .output()
        .expect("failed to run fluxmacro");

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();

    // Must parse as valid JSON
    let parsed: Result<serde_json::Value, _> = serde_json::from_str(&stdout);
    assert!(parsed.is_ok(), "stdout must be valid JSON: {stdout}");

    // Must start with { or [ (valid JSON root)
    assert!(
        stdout.starts_with('{') || stdout.starts_with('['),
        "JSON output must start with {{ or [. Got: {}",
        &stdout[..20.min(stdout.len())]
    );
}

// ─── Error Handling ─────────────────────────────────────────────────────────

#[test]
fn ci_missing_file_returns_error_json() {
    let (json, success) = run_ci(&["validate", "/tmp/does_not_exist_fluxmacro.yaml"]);

    assert!(!success, "Should fail for missing file");
    assert_eq!(json["success"], false);
    assert!(json["error"].is_string(), "Should have error message");
}

#[test]
fn ci_invalid_yaml_returns_error_json() {
    let dir = tempfile::tempdir().unwrap();
    let bad_path = dir.path().join("bad.ffmacro.yaml");
    fs::write(&bad_path, "not valid yaml at all [[[").unwrap();

    let (json, success) = run_ci(&["validate", bad_path.to_str().unwrap()]);

    assert!(!success, "Should fail for invalid YAML");
    assert_eq!(json["success"], false);
    assert!(json["error"].is_string(), "Should have error message");
}

#[test]
fn ci_error_json_always_has_success_field() {
    // Even on errors, the JSON should have a "success" field
    let (json, _) = run_ci(&["validate", "/nonexistent/path/macro.yaml"]);
    assert!(
        json.get("success").is_some(),
        "Error JSON must have 'success' field"
    );
}

// ─── Determinism ────────────────────────────────────────────────────────────

#[test]
fn ci_deterministic_same_seed() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_macro(dir.path(), "det_test", &["naming.validate"]);

    // Run same macro twice with same seed in same workdir
    let (json1, _) = run_ci(&[
        "run",
        macro_path.to_str().unwrap(),
        "--seed",
        "77777",
        "-w",
        dir.path().to_str().unwrap(),
    ]);
    let (json2, _) = run_ci(&[
        "run",
        macro_path.to_str().unwrap(),
        "--seed",
        "77777",
        "-w",
        dir.path().to_str().unwrap(),
    ]);

    let hash1 = json1["run_hash"].as_str().unwrap_or("");
    let hash2 = json2["run_hash"].as_str().unwrap_or("");

    assert!(
        !hash1.is_empty() && !hash2.is_empty(),
        "Both runs should produce hashes"
    );
    assert_eq!(
        hash1, hash2,
        "Same seed + same steps must produce same hash"
    );
}

#[test]
fn ci_different_seeds_different_hashes() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_macro(dir.path(), "seed_test", &["naming.validate", "adb.generate"]);

    let (json1, _) = run_ci(&[
        "run",
        macro_path.to_str().unwrap(),
        "--seed",
        "11111",
        "-w",
        dir.path().to_str().unwrap(),
    ]);
    let (json2, _) = run_ci(&[
        "run",
        macro_path.to_str().unwrap(),
        "--seed",
        "22222",
        "-w",
        dir.path().to_str().unwrap(),
    ]);

    let hash1 = json1["run_hash"].as_str().unwrap_or("");
    let hash2 = json2["run_hash"].as_str().unwrap_or("");

    assert!(
        !hash1.is_empty() && !hash2.is_empty(),
        "Both runs should produce hashes"
    );
    assert_ne!(
        hash1, hash2,
        "Different seeds should produce different hashes"
    );
}

// ─── Exit Codes ─────────────────────────────────────────────────────────────

#[test]
fn ci_exit_code_zero_on_success() {
    let dir = tempfile::tempdir().unwrap();
    let macro_path = create_macro(dir.path(), "exit0", &["naming.validate"]);

    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "validate", macro_path.to_str().unwrap()])
        .output()
        .expect("failed to run fluxmacro");

    assert!(output.status.success(), "Valid macro should exit 0");
}

#[test]
fn ci_exit_code_nonzero_on_failure() {
    let output = Command::new(fluxmacro_bin())
        .args(["--ci", "validate", "/tmp/nonexistent_file.yaml"])
        .output()
        .expect("failed to run fluxmacro");

    assert!(
        !output.status.success(),
        "Missing file should exit with non-zero"
    );
}

// ─── Report Formatter Script ────────────────────────────────────────────────

#[test]
fn ci_report_formatter_produces_markdown() {
    let dir = tempfile::tempdir().unwrap();

    // Create sample JSON input
    let json_input = serde_json::json!({
        "success": true,
        "game_id": "TestGame",
        "seed": 42,
        "run_hash": "abc123def456789012345678",
        "duration_ms": 1234,
        "qa_passed": 5,
        "qa_failed": 0,
        "artifacts": ["adb.json", "report.html"],
        "warnings": [],
        "errors": [],
    });

    let json_path = dir.path().join("input.json");
    let output_path = dir.path().join("report.md");
    fs::write(&json_path, serde_json::to_string(&json_input).unwrap()).unwrap();

    let script_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("scripts")
        .join("ci_report_formatter.py");

    let output = Command::new("python3")
        .args([
            script_path.to_str().unwrap(),
            "--json-input",
            json_path.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--commit",
            "abc123",
            "--pr-number",
            "42",
        ])
        .output()
        .expect("failed to run ci_report_formatter.py");

    assert!(
        output.status.success(),
        "Formatter should succeed. stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let md = fs::read_to_string(&output_path).unwrap();
    assert!(md.contains("FluxMacro"), "Report should contain FluxMacro header");
    assert!(md.contains("TestGame"), "Report should contain game_id");
    assert!(md.contains("PASS"), "Report should show PASS status");
    assert!(md.contains("abc123"), "Report should contain commit SHA");
    assert!(md.contains("#42"), "Report should contain PR number");
}

#[test]
fn ci_report_formatter_handles_failure() {
    let dir = tempfile::tempdir().unwrap();

    let json_input = serde_json::json!({
        "success": false,
        "error": "Something went wrong",
    });

    let json_path = dir.path().join("fail.json");
    let output_path = dir.path().join("fail_report.md");
    fs::write(&json_path, serde_json::to_string(&json_input).unwrap()).unwrap();

    let script_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("scripts")
        .join("ci_report_formatter.py");

    let output = Command::new("python3")
        .args([
            script_path.to_str().unwrap(),
            "--json-input",
            json_path.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
        ])
        .output()
        .expect("failed to run ci_report_formatter.py");

    // Formatter exits 1 for failure data
    assert!(!output.status.success(), "Should exit 1 for failure data");

    let md = fs::read_to_string(&output_path).unwrap();
    assert!(md.contains("FAIL"), "Report should show FAIL");
    assert!(md.contains("Something went wrong"), "Report should contain error");
}

// ============================================================================
// rf-fluxmacro — Integration Tests (FM-31)
// ============================================================================
// Tests for Phase 2 step implementations.
// ============================================================================

use rf_fluxmacro::context::{
    GameMechanic, MacroContext, Platform, VolatilityLevel,
};
use rf_fluxmacro::steps::{MacroStep, StepRegistry, register_all_steps};

/// Create a test context with a temporary working directory.
fn test_context(dir: &std::path::Path) -> MacroContext {
    MacroContext::new("test_game_01".to_string(), dir.to_path_buf())
}

/// Create a test context with mechanics and platforms set.
fn test_context_full(dir: &std::path::Path) -> MacroContext {
    let mut ctx = test_context(dir);
    ctx.platforms = vec![Platform::Desktop, Platform::Mobile];
    ctx.mechanics = vec![
        GameMechanic::FreeSpins,
        GameMechanic::Cascades,
        GameMechanic::Progressive,
    ];
    ctx.theme = Some("ancient_egypt".to_string());
    ctx
}

// ─── Registry Tests ─────────────────────────────────────────────────────────

#[test]
fn register_all_steps_populates_registry() {
    let mut registry = StepRegistry::new();
    register_all_steps(&mut registry);

    assert_eq!(registry.len(), 11);
    assert!(registry.contains("adb.generate"));
    assert!(registry.contains("naming.validate"));
    assert!(registry.contains("volatility.profile.generate"));
    assert!(registry.contains("manifest.build"));
    assert!(registry.contains("qa.run_suite"));
    assert!(registry.contains("qa.event_storm"));
    assert!(registry.contains("qa.determinism"));
    assert!(registry.contains("qa.loudness"));
    assert!(registry.contains("qa.fatigue"));
    assert!(registry.contains("qa.spectral_health"));
    assert!(registry.contains("pack.release"));
}

#[test]
fn step_names_and_descriptions_are_non_empty() {
    let mut registry = StepRegistry::new();
    register_all_steps(&mut registry);

    for name in registry.list() {
        let step = registry.get(name).unwrap();
        assert!(!step.name().is_empty(), "Step name is empty");
        assert!(!step.description().is_empty(), "Step '{}' has empty description", name);
        assert!(step.estimated_duration_ms() > 0, "Step '{}' has zero estimated duration", name);
    }
}

// ─── ADB Generate Tests ────────────────────────────────────────────────────

#[test]
fn adb_generate_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context_full(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::adb_generate::AdbGenerateStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn adb_generate_creates_files() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context_full(tmp.path());

    let step = rf_fluxmacro::steps::adb_generate::AdbGenerateStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.status.is_success());
    assert_eq!(result.artifacts.len(), 2);

    // Check files exist
    for (_, path) in &result.artifacts {
        assert!(path.exists(), "Artifact not found: {}", path.display());
    }

    // Check metrics
    assert!(result.metrics.get("mechanic_count").is_some());
    assert!(result.metrics.get("event_count").is_some());
}

#[test]
fn adb_generate_validates_game_id() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.game_id = String::new();

    let step = rf_fluxmacro::steps::adb_generate::AdbGenerateStep;
    let result = step.validate(&ctx);
    assert!(result.is_err());
}

// ─── Naming Validate Tests ──────────────────────────────────────────────────

#[test]
fn naming_validate_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    // Create assets dir with a file
    let assets = tmp.path().join("AudioRaw");
    std::fs::create_dir_all(&assets).unwrap();
    std::fs::write(assets.join("ui_click_01.wav"), b"RIFF").unwrap();

    let step = rf_fluxmacro::steps::naming_validate::NamingValidateStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn naming_validate_no_assets_dir() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::naming_validate::NamingValidateStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    // Should have a warning about missing dir
}

#[test]
fn naming_validate_scans_files() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    // Create valid audio files
    let assets = tmp.path().join("AudioRaw");
    std::fs::create_dir_all(&assets).unwrap();
    std::fs::write(assets.join("ui_click_01.wav"), b"RIFF").unwrap();
    std::fs::write(assets.join("sfx_spin_start_01.wav"), b"RIFF").unwrap();
    std::fs::write(assets.join("mus_base_loop.ogg"), b"OGG").unwrap();

    let step = rf_fluxmacro::steps::naming_validate::NamingValidateStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.metrics.get("total_files").is_some());
    assert_eq!(*result.metrics.get("total_files").unwrap() as usize, 3);
}

// ─── Volatility Profile Tests ───────────────────────────────────────────────

#[test]
fn volatility_profile_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::volatility_profile::VolatilityProfileStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn volatility_profile_generates_file() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::volatility_profile::VolatilityProfileStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.status.is_success());
    assert_eq!(result.artifacts.len(), 1);
    assert!(result.artifacts[0].1.exists());

    // Verify metric
    let vi = result.metrics.get("volatility_index").unwrap();
    assert!(*vi > 0.0 && *vi < 1.0);
}

#[test]
fn volatility_profile_varies_by_level() {
    let tmp = tempfile::tempdir().unwrap();

    let mut ctx_low = test_context(tmp.path());
    ctx_low.volatility = VolatilityLevel::Low;
    let step = rf_fluxmacro::steps::volatility_profile::VolatilityProfileStep;
    let r_low = step.execute(&mut ctx_low).unwrap();

    let mut ctx_extreme = test_context(tmp.path());
    ctx_extreme.volatility = VolatilityLevel::Extreme;
    let r_extreme = step.execute(&mut ctx_extreme).unwrap();

    let vi_low = r_low.metrics.get("volatility_index").unwrap();
    let vi_extreme = r_extreme.metrics.get("volatility_index").unwrap();
    assert!(vi_extreme > vi_low);
}

#[test]
fn volatility_profile_mechanic_modifiers() {
    let tmp = tempfile::tempdir().unwrap();

    // Without mechanics
    let mut ctx1 = test_context(tmp.path());
    ctx1.volatility = VolatilityLevel::Medium;
    let step = rf_fluxmacro::steps::volatility_profile::VolatilityProfileStep;
    let r1 = step.execute(&mut ctx1).unwrap();

    // With Megaways (adds transient aggression)
    let mut ctx2 = test_context(tmp.path());
    ctx2.volatility = VolatilityLevel::Medium;
    ctx2.mechanics = vec![GameMechanic::Megaways];
    let r2 = step.execute(&mut ctx2).unwrap();

    // volatility_index should be the same (mechanics don't change it)
    let vi1 = r1.metrics.get("volatility_index").unwrap();
    let vi2 = r2.metrics.get("volatility_index").unwrap();
    assert_eq!(*vi1, *vi2);
}

// ─── Manifest Build Tests ───────────────────────────────────────────────────

#[test]
fn manifest_build_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::manifest_build::ManifestBuildStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn manifest_build_creates_file() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::manifest_build::ManifestBuildStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.status.is_success());
    assert_eq!(result.artifacts.len(), 1);
    assert!(result.artifacts[0].1.exists());

    // Without QA results, it should be PENDING/not certified
    let certified = result.metrics.get("certified").unwrap();
    assert_eq!(*certified, 0.0);
}

#[test]
fn manifest_build_certified_with_qa() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    // Set QA pass results
    ctx.set_intermediate("qa_determinism_passed", serde_json::json!(true));
    ctx.set_intermediate("qa_event_storm_passed", serde_json::json!(true));
    ctx.set_intermediate("qa_loudness_passed", serde_json::json!(true));

    let step = rf_fluxmacro::steps::manifest_build::ManifestBuildStep;
    let result = step.execute(&mut ctx).unwrap();

    let certified = result.metrics.get("certified").unwrap();
    assert_eq!(*certified, 1.0);
}

// ─── QA Run Suite Tests ─────────────────────────────────────────────────────

#[test]
fn qa_run_suite_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::qa_run_suite::QaRunSuiteStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn qa_run_suite_configures_steps() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::qa_run_suite::QaRunSuiteStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.status.is_success());
    let count = result.metrics.get("qa_step_count").unwrap();
    assert_eq!(*count, 5.0); // 5 QA sub-steps
}

// ─── QA Event Storm Tests ───────────────────────────────────────────────────

#[test]
fn qa_event_storm_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::qa_event_storm::QaEventStormStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn qa_event_storm_runs_simulation() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::qa_event_storm::QaEventStormStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.status.is_success() || !result.status.is_failed());
    assert!(result.metrics.get("total_spins").is_some());
    assert!(result.metrics.get("fatigue_index").is_some());
    assert!(!ctx.qa_results.is_empty());
}

// ─── QA Determinism Tests ───────────────────────────────────────────────────

#[test]
fn qa_determinism_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::qa_determinism::QaDeterminismStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn qa_determinism_runs_replays() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    // Use fewer replays for speed
    ctx.set_intermediate("determinism_replay_count", serde_json::json!(3));

    let step = rf_fluxmacro::steps::qa_determinism::QaDeterminismStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.metrics.get("replay_count").is_some());
    assert_eq!(*result.metrics.get("replay_count").unwrap(), 3.0);
    assert!(!ctx.qa_results.is_empty());
}

#[test]
fn qa_determinism_same_seed_matches() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.seed = 42;
    ctx.set_intermediate("determinism_replay_count", serde_json::json!(3));

    let step = rf_fluxmacro::steps::qa_determinism::QaDeterminismStep;
    let result = step.execute(&mut ctx).unwrap();

    let all_passed = result.metrics.get("all_passed").unwrap();
    assert_eq!(*all_passed, 1.0);
    let mismatches = result.metrics.get("mismatches").unwrap();
    assert_eq!(*mismatches, 0.0);
}

// ─── QA Fatigue Tests ───────────────────────────────────────────────────────

#[test]
fn qa_fatigue_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::qa_fatigue::QaFatigueStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn qa_fatigue_runs_burn_test() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::qa_fatigue::QaFatigueStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.metrics.get("fatigue_index").is_some());
    assert!(result.metrics.get("energy_drift").is_some());
    assert!(!ctx.qa_results.is_empty());
}

// ─── QA Loudness Tests ──────────────────────────────────────────────────────

#[test]
fn qa_loudness_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::qa_loudness::QaLoudnessStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn qa_loudness_no_assets() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::qa_loudness::QaLoudnessStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    // No files → warning about missing dir
}

// ─── QA Spectral Health Tests ───────────────────────────────────────────────

#[test]
fn qa_spectral_health_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::qa_spectral_health::QaSpectralHealthStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn qa_spectral_health_no_assets() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::qa_spectral_health::QaSpectralHealthStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
}

// ─── Pack Release Tests ─────────────────────────────────────────────────────

#[test]
fn pack_release_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.dry_run = true;

    let step = rf_fluxmacro::steps::pack_release::PackReleaseStep;
    let result = step.execute(&mut ctx).unwrap();
    assert!(result.status.is_success());
    assert!(result.summary.contains("Dry-run"));
}

#[test]
fn pack_release_validates_empty_artifacts() {
    let tmp = tempfile::tempdir().unwrap();
    let ctx = test_context(tmp.path());

    let step = rf_fluxmacro::steps::pack_release::PackReleaseStep;
    let result = step.validate(&ctx);
    assert!(result.is_err()); // No artifacts = precondition failure
}

#[test]
fn pack_release_packages_artifacts() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());

    // Create a fake artifact
    let artifact_path = tmp.path().join("test_artifact.json");
    std::fs::write(&artifact_path, r#"{"test": true}"#).unwrap();
    ctx.artifacts.insert("test_artifact".to_string(), artifact_path);

    let step = rf_fluxmacro::steps::pack_release::PackReleaseStep;
    let result = step.execute(&mut ctx).unwrap();

    assert!(result.status.is_success());
    assert!(result.metrics.get("artifact_count").is_some());
    assert_eq!(*result.metrics.get("artifact_count").unwrap(), 1.0);

    // Release dir should exist
    let release_dir = tmp.path().join("Release");
    assert!(release_dir.exists());
}

// ─── End-to-End Pipeline Tests ──────────────────────────────────────────────

#[test]
fn end_to_end_adb_then_volatility() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context_full(tmp.path());

    // Step 1: Generate ADB
    let adb_step = rf_fluxmacro::steps::adb_generate::AdbGenerateStep;
    let r1 = adb_step.execute(&mut ctx).unwrap();
    assert!(r1.status.is_success());

    // Store artifacts
    for (name, path) in r1.artifacts {
        ctx.artifacts.insert(name, path);
    }

    // Step 2: Generate volatility profile
    let vol_step = rf_fluxmacro::steps::volatility_profile::VolatilityProfileStep;
    let r2 = vol_step.execute(&mut ctx).unwrap();
    assert!(r2.status.is_success());

    for (name, path) in r2.artifacts {
        ctx.artifacts.insert(name, path);
    }

    // Verify both sets of artifacts exist
    assert!(ctx.artifacts.len() >= 3);
}

#[test]
fn end_to_end_full_pipeline_dry_run() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context_full(tmp.path());
    ctx.dry_run = true;

    let mut registry = StepRegistry::new();
    register_all_steps(&mut registry);

    // Run all steps in dry-run mode
    let step_names: Vec<String> = registry.list().to_vec();
    for name in &step_names {
        if name == "pack.release" {
            continue; // Skip — needs artifacts
        }
        let step = registry.get(name).unwrap();
        let result = step.execute(&mut ctx).unwrap();
        assert!(
            result.status.is_success(),
            "Step '{}' failed in dry-run: {}",
            name,
            result.summary,
        );
    }
}

#[test]
fn cancellation_support() {
    let tmp = tempfile::tempdir().unwrap();
    let mut ctx = test_context(tmp.path());
    ctx.cancel(); // Pre-cancel

    // Naming validate should check cancellation
    let assets = tmp.path().join("AudioRaw");
    std::fs::create_dir_all(&assets).unwrap();
    for i in 0..10 {
        std::fs::write(assets.join(format!("ui_click_{i:02}.wav")), b"RIFF").unwrap();
    }

    let step = rf_fluxmacro::steps::naming_validate::NamingValidateStep;
    let result = step.execute(&mut ctx);
    assert!(result.is_err());
}

// ============================================================================
// rf-fluxmacro — QA Determinism Test Step
// ============================================================================
// FM-26: Runs N deterministic replays via rf-aurexis DRC.
// Verifies per-frame hashes match across all runs.
// ============================================================================

use crate::context::{LogLevel, MacroContext, QaTestResult};
use crate::error::FluxMacroError;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct QaDeterminismStep;

/// Default number of replay runs for determinism verification.
const DEFAULT_REPLAY_COUNT: usize = 10;

impl MacroStep for QaDeterminismStep {
    fn name(&self) -> &'static str {
        "qa.determinism"
    }

    fn description(&self) -> &'static str {
        "Verify deterministic output across N replay runs"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        let replay_count = ctx
            .get_intermediate("determinism_replay_count")
            .and_then(|v| v.as_u64())
            .unwrap_or(DEFAULT_REPLAY_COUNT as u64) as usize;

        if ctx.dry_run {
            return Ok(StepResult::success(format!(
                "Dry-run: would run {replay_count} determinism replays"
            )));
        }

        let start = std::time::Instant::now();

        ctx.log(
            LogLevel::Info,
            "qa.determinism",
            &format!(
                "Running {replay_count} deterministic replays (seed={})",
                ctx.seed
            ),
        );

        // Build simulation steps from seed
        let aurexis_config = rf_aurexis::AurexisConfig::default();
        let sim_steps = build_simulation_steps(ctx.seed, 100); // 100 frames per run

        // Record reference trace
        let mut drc =
            rf_aurexis::drc::replay::DeterministicReplayCore::with_config(aurexis_config);
        let reference_trace = drc.record(&sim_steps);

        // Replay N times and collect hashes
        let mut run_hashes = Vec::with_capacity(replay_count);
        let mut all_passed = true;
        let mut total_mismatches = 0u32;

        // First hash from the reference
        let reference_hash = reference_trace.final_state_hash.clone();
        run_hashes.push(reference_hash.as_hex());

        for run_idx in 1..replay_count {
            if ctx.is_cancelled() {
                return Err(FluxMacroError::Cancelled);
            }

            let result = drc.replay_and_verify(&sim_steps);
            let passed = result.passed;
            let mismatches = result.mismatches.len() as u32;

            run_hashes.push(result.replay_final_hash.as_hex());

            if !passed {
                all_passed = false;
                total_mismatches += mismatches;
                ctx.log(
                    LogLevel::Warning,
                    "qa.determinism",
                    &format!("Run {run_idx}: {mismatches} frame mismatches"),
                );
            }
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        // Record QA result
        ctx.qa_results.push(QaTestResult {
            test_name: "determinism.replay".to_string(),
            passed: all_passed,
            details: format!(
                "{replay_count} runs, {} mismatches, ref_hash={}",
                total_mismatches, &run_hashes[0]
            ),
            duration_ms,
            metrics: {
                let mut m = std::collections::HashMap::new();
                m.insert("replay_count".to_string(), replay_count as f64);
                m.insert("mismatches".to_string(), total_mismatches as f64);
                m
            },
        });

        // Store pass/fail for manifest
        ctx.set_intermediate("qa_determinism_passed", serde_json::json!(all_passed));
        ctx.set_intermediate("qa_determinism_hashes", serde_json::json!(run_hashes));

        // Write report
        let reports_dir = ctx.working_dir.join("Reports");
        std::fs::create_dir_all(&reports_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(reports_dir.clone(), e))?;

        let report_path = reports_dir.join(format!(
            "determinism_report_{}.json",
            security::sanitize_filename(&ctx.game_id)
        ));

        let report = serde_json::json!({
            "replay_count": replay_count,
            "all_passed": all_passed,
            "total_mismatches": total_mismatches,
            "reference_hash": &run_hashes[0],
            "run_hashes": run_hashes,
            "seed": ctx.seed,
            "duration_ms": duration_ms,
        });

        let json_str = serde_json::to_string_pretty(&report)?;
        std::fs::write(&report_path, &json_str)
            .map_err(|e| FluxMacroError::FileWrite(report_path.clone(), e))?;

        ctx.log(
            LogLevel::Info,
            "qa.determinism",
            &format!(
                "Determinism test: {replay_count} runs, {}, ref={}",
                if all_passed {
                    "ALL MATCH"
                } else {
                    "MISMATCH DETECTED"
                },
                &run_hashes[0],
            ),
        );

        let summary = format!(
            "Determinism: {replay_count} runs, {}",
            if all_passed {
                "ALL MATCH"
            } else {
                "MISMATCHES FOUND"
            }
        );

        let result = if all_passed {
            StepResult::success(&summary)
        } else {
            StepResult::success_with_warnings(
                &summary,
                vec![format!(
                    "{total_mismatches} frame mismatches across {replay_count} runs"
                )],
            )
        };

        Ok(result
            .with_artifact("determinism_report".to_string(), report_path)
            .with_metric("replay_count".to_string(), replay_count as f64)
            .with_metric("mismatches".to_string(), total_mismatches as f64)
            .with_metric("all_passed".to_string(), if all_passed { 1.0 } else { 0.0 }))
    }

    fn estimated_duration_ms(&self) -> u64 {
        8000
    }
}

/// Build deterministic simulation steps from a seed.
fn build_simulation_steps(
    seed: u64,
    frame_count: usize,
) -> Vec<rf_aurexis::qa::simulation::SimulationStep> {
    use rand::Rng;
    use rand::SeedableRng;

    let mut rng = rand_chacha::ChaCha20Rng::seed_from_u64(seed);
    let mut steps = Vec::with_capacity(frame_count);

    for i in 0..frame_count {
        steps.push(rf_aurexis::qa::simulation::SimulationStep {
            elapsed_ms: (i as u64) * 50,
            volatility: rng.random_range(0.0..1.0f64),
            rtp: 90.0 + rng.random_range(0.0..1.0f64) * 7.0, // 90-97%
            win_multiplier: if rng.random_range(0.0..1.0f64) < 0.25 {
                rng.random_range(0.0..1.0f64) * 100.0
            } else {
                0.0
            },
            jackpot_proximity: rng.random_range(0.0..1.0f64),
            rms_db: -30.0 + rng.random_range(0.0..1.0f64) * 18.0, // -30 to -12
            hf_db: -40.0 + rng.random_range(0.0..1.0f64) * 20.0,  // -40 to -20
        });
    }

    steps
}

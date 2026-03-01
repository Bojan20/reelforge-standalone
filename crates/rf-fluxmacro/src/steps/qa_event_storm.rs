// ============================================================================
// rf-fluxmacro — QA Event Storm Step
// ============================================================================
// FM-25: Runs 500-spin Pre-Bake Simulation via rf-aurexis PBSE.
// Validates energy, voice count, SCI, fatigue across 10 domains.
// ============================================================================

use crate::context::{LogLevel, MacroContext, QaTestResult};
use crate::error::FluxMacroError;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct QaEventStormStep;

impl MacroStep for QaEventStormStep {
    fn name(&self) -> &'static str {
        "qa.event_storm"
    }

    fn description(&self) -> &'static str {
        "Run 500-spin event storm simulation (PBSE) across 10 domains"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        if ctx.dry_run {
            return Ok(StepResult::success(
                "Dry-run: would run 500-spin PBSE event storm",
            ));
        }

        let start = std::time::Instant::now();

        ctx.log(
            LogLevel::Info,
            "qa.event_storm",
            "Starting Pre-Bake Simulation Engine (500 spins × 10 domains)",
        );

        // Build AUREXIS config from context
        let aurexis_config = rf_aurexis::AurexisConfig::default();
        let mut pbse = rf_aurexis::qa::pbse::PreBakeSimulator::with_config(aurexis_config);

        // Run full simulation
        let result = pbse.run_full_simulation();

        let duration_ms = start.elapsed().as_millis() as u64;

        // Record QA results per domain
        for domain in &result.domains {
            let passed = domain.passed;
            let details = format!(
                "energy={:.2}, voices_max={}, sci={:.3}, fatigue={:.3}",
                domain.metrics.iter().find(|m| m.name == "MaxEnergyCap").map(|m| m.value).unwrap_or(0.0),
                domain.metrics.iter().find(|m| m.name == "MaxVoices").map(|m| m.value as u32).unwrap_or(0),
                domain.metrics.iter().find(|m| m.name == "SCI").map(|m| m.value).unwrap_or(0.0),
                domain.metrics.iter().find(|m| m.name == "FatigueIndex").map(|m| m.value).unwrap_or(0.0),
            );

            ctx.qa_results.push(QaTestResult {
                test_name: format!("pbse.{}", domain.domain.name()),
                passed,
                details,
                duration_ms: duration_ms / result.domains.len() as u64,
                metrics: domain
                    .metrics
                    .iter()
                    .map(|m| (m.name.to_string(), m.value))
                    .collect(),
            });
        }

        // Record fatigue model result
        ctx.qa_results.push(QaTestResult {
            test_name: "pbse.fatigue_model".to_string(),
            passed: result.fatigue_model.passed,
            details: format!(
                "fatigue_index={:.3}, peak_freq={:.1}Hz, threshold={:.2}",
                result.fatigue_model.fatigue_index,
                result.fatigue_model.peak_frequency,
                result.fatigue_model.threshold,
            ),
            duration_ms: 0,
            metrics: {
                let mut m = std::collections::HashMap::new();
                m.insert("fatigue_index".to_string(), result.fatigue_model.fatigue_index);
                m.insert("peak_frequency".to_string(), result.fatigue_model.peak_frequency);
                m
            },
        });

        // Store pass/fail for manifest
        ctx.set_intermediate(
            "qa_event_storm_passed",
            serde_json::json!(result.all_passed),
        );
        ctx.set_intermediate(
            "qa_event_storm_bake_unlocked",
            serde_json::json!(result.bake_unlocked),
        );
        ctx.set_intermediate(
            "qa_event_storm_total_spins",
            serde_json::json!(result.total_spins),
        );

        // Write detailed report
        let reports_dir = ctx.working_dir.join("Reports");
        std::fs::create_dir_all(&reports_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(reports_dir.clone(), e))?;

        let report_path = reports_dir.join(format!(
            "pbse_report_{}.json",
            security::sanitize_filename(&ctx.game_id)
        ));

        let report_json = serde_json::json!({
            "total_spins": result.total_spins,
            "all_passed": result.all_passed,
            "bake_unlocked": result.bake_unlocked,
            "determinism_verified": result.determinism_verified,
            "domain_count": result.domains.len(),
            "fatigue_model": {
                "fatigue_index": result.fatigue_model.fatigue_index,
                "peak_frequency": result.fatigue_model.peak_frequency,
                "harmonic_density": result.fatigue_model.harmonic_density,
                "temporal_density": result.fatigue_model.temporal_density,
                "recovery_factor": result.fatigue_model.recovery_factor,
                "passed": result.fatigue_model.passed,
            },
        });

        let json_str = serde_json::to_string_pretty(&report_json)?;
        std::fs::write(&report_path, &json_str)
            .map_err(|e| FluxMacroError::FileWrite(report_path.clone(), e))?;

        ctx.log(
            LogLevel::Info,
            "qa.event_storm",
            &format!(
                "PBSE complete: {} spins, {} domains, all_passed={}, bake_unlocked={}",
                result.total_spins,
                result.domains.len(),
                result.all_passed,
                result.bake_unlocked,
            ),
        );

        let mut warnings = Vec::new();
        if !result.all_passed {
            let failed_count = result.domains.iter().filter(|d| !d.passed).count();
            warnings.push(format!("{failed_count} domains failed validation"));
        }
        if !result.fatigue_model.passed {
            warnings.push(format!(
                "Fatigue model failed: index={:.3} (threshold={:.2})",
                result.fatigue_model.fatigue_index,
                result.fatigue_model.threshold,
            ));
        }

        let summary = format!(
            "PBSE: {} spins, {} domains, {}",
            result.total_spins,
            result.domains.len(),
            if result.all_passed { "ALL PASS" } else { "FAILURES DETECTED" }
        );

        let step_result = if warnings.is_empty() {
            StepResult::success(&summary)
        } else {
            StepResult::success_with_warnings(&summary, warnings)
        };

        Ok(step_result
            .with_artifact("pbse_report".to_string(), report_path)
            .with_metric("total_spins".to_string(), result.total_spins as f64)
            .with_metric("all_passed".to_string(), if result.all_passed { 1.0 } else { 0.0 })
            .with_metric("fatigue_index".to_string(), result.fatigue_model.fatigue_index))
    }

    fn estimated_duration_ms(&self) -> u64 {
        5000
    }
}

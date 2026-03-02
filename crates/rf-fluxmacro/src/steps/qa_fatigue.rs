// ============================================================================
// rf-fluxmacro — QA Fatigue Analyzer Step
// ============================================================================
// FM-28: 45-minute session simulation for listener fatigue analysis.
// Wraps rf-aurexis PBSE fatigue model + SSS burn test.
// ============================================================================

use crate::context::{LogLevel, MacroContext, QaTestResult};
use crate::error::FluxMacroError;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct QaFatigueStep;

/// Fatigue simulation parameters.
const SIMULATION_DURATION_MIN: f64 = 45.0;
const FATIGUE_WARNING_THRESHOLD: f64 = 0.65;
const FATIGUE_FAIL_THRESHOLD: f64 = 0.85;
const BURN_SPINS: u32 = 10_000;

impl MacroStep for QaFatigueStep {
    fn name(&self) -> &'static str {
        "qa.fatigue"
    }

    fn description(&self) -> &'static str {
        "Analyze listener fatigue over 45-minute simulated session"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        if ctx.dry_run {
            return Ok(StepResult::success(format!(
                "Dry-run: would run {SIMULATION_DURATION_MIN}-minute fatigue analysis"
            )));
        }

        let start = std::time::Instant::now();

        ctx.log(
            LogLevel::Info,
            "qa.fatigue",
            &format!(
                "Starting {SIMULATION_DURATION_MIN}-min fatigue analysis ({BURN_SPINS} spins)"
            ),
        );

        // Run SSS burn test for drift/fatigue analysis
        let burn_config = rf_aurexis::sss::burn_test::BurnTestConfig {
            total_spins: BURN_SPINS,
            sample_interval: 100,
            max_final_fatigue: FATIGUE_FAIL_THRESHOLD,
            ..Default::default()
        };

        let aurexis_config = rf_aurexis::AurexisConfig::default();
        let mut burn = rf_aurexis::sss::burn_test::BurnTest::new(burn_config);
        let burn_result = burn.run(&aurexis_config);

        let duration_ms = start.elapsed().as_millis() as u64;

        // Extract fatigue metrics
        let fatigue_acc = burn_result.metrics.fatigue_accumulation.final_value;
        let energy_drift = burn_result.metrics.energy_drift.final_value;
        let harmonic_creep = burn_result.metrics.harmonic_creep.final_value;
        let spectral_bias = burn_result.metrics.spectral_bias.final_value;
        let voice_trend = burn_result.metrics.voice_trend.final_value;

        // Determine status
        let fatigue_passed = fatigue_acc < FATIGUE_FAIL_THRESHOLD;
        let fatigue_warning = fatigue_acc >= FATIGUE_WARNING_THRESHOLD;

        // Record QA result
        ctx.qa_results.push(QaTestResult {
            test_name: "fatigue.burn_test".to_string(),
            passed: burn_result.passed,
            details: format!(
                "fatigue={:.3}, energy_drift={:.3}, harmonic_creep={:.3}, spins={}",
                fatigue_acc, energy_drift, harmonic_creep, burn_result.total_spins,
            ),
            duration_ms,
            metrics: {
                let mut m = std::collections::HashMap::new();
                m.insert("fatigue_accumulation".to_string(), fatigue_acc);
                m.insert("energy_drift".to_string(), energy_drift);
                m.insert("harmonic_creep".to_string(), harmonic_creep);
                m.insert("spectral_bias".to_string(), spectral_bias);
                m.insert("voice_trend".to_string(), voice_trend);
                m
            },
        });

        ctx.qa_results.push(QaTestResult {
            test_name: "fatigue.determinism".to_string(),
            passed: burn_result.deterministic,
            details: format!("hash={}", burn_result.hash),
            duration_ms: 0,
            metrics: std::collections::HashMap::new(),
        });

        // Store in intermediate
        ctx.set_intermediate("qa_fatigue_passed", serde_json::json!(fatigue_passed));
        ctx.set_intermediate("qa_fatigue_index", serde_json::json!(fatigue_acc));

        // Generate fatigue curve data for SVG reporter
        // Simulate data points (time_min, fatigue_index)
        let fatigue_curve: Vec<(f64, f64)> = (0..=90)
            .map(|i| {
                let t = i as f64 * (SIMULATION_DURATION_MIN / 90.0);
                let progress = t / SIMULATION_DURATION_MIN;
                let fatigue_at_t = fatigue_acc * progress.powf(0.7); // Rough curve
                (t, fatigue_at_t)
            })
            .collect();

        ctx.set_intermediate("fatigue_curve_data", serde_json::json!(fatigue_curve));

        // Write report
        let reports_dir = ctx.working_dir.join("Reports");
        std::fs::create_dir_all(&reports_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(reports_dir.clone(), e))?;

        let report_path = reports_dir.join(format!(
            "fatigue_report_{}.json",
            security::sanitize_filename(&ctx.game_id)
        ));

        let report_json = serde_json::json!({
            "simulation_duration_min": SIMULATION_DURATION_MIN,
            "total_spins": burn_result.total_spins,
            "passed": fatigue_passed,
            "burn_passed": burn_result.passed,
            "deterministic": burn_result.deterministic,
            "metrics": {
                "fatigue_accumulation": fatigue_acc,
                "energy_drift": energy_drift,
                "harmonic_creep": harmonic_creep,
                "spectral_bias": spectral_bias,
                "voice_trend": voice_trend,
            },
            "thresholds": {
                "warning": FATIGUE_WARNING_THRESHOLD,
                "fail": FATIGUE_FAIL_THRESHOLD,
            },
            "failures": burn_result.failures,
            "fatigue_curve": fatigue_curve,
        });

        let json_str = serde_json::to_string_pretty(&report_json)?;
        std::fs::write(&report_path, &json_str)
            .map_err(|e| FluxMacroError::FileWrite(report_path.clone(), e))?;

        ctx.log(
            LogLevel::Info,
            "qa.fatigue",
            &format!(
                "Fatigue analysis: index={:.3}, {}, {} spins in {}ms",
                fatigue_acc,
                if fatigue_passed { "PASS" } else { "FAIL" },
                burn_result.total_spins,
                duration_ms,
            ),
        );

        let summary = format!(
            "Fatigue: index={:.3}, {}",
            fatigue_acc,
            if fatigue_passed { "PASS" } else { "FAIL" }
        );

        let mut warnings = Vec::new();
        if fatigue_warning && fatigue_passed {
            warnings.push(format!(
                "Fatigue index {fatigue_acc:.3} approaching threshold ({FATIGUE_FAIL_THRESHOLD:.2})"
            ));
        }
        if !fatigue_passed {
            warnings.push(format!(
                "Fatigue index {fatigue_acc:.3} exceeds threshold ({FATIGUE_FAIL_THRESHOLD:.2})"
            ));
        }
        for failure in &burn_result.failures {
            warnings.push(failure.clone());
        }

        let result = if warnings.is_empty() {
            StepResult::success(&summary)
        } else {
            StepResult::success_with_warnings(&summary, warnings)
        };

        Ok(result
            .with_artifact("fatigue_report".to_string(), report_path)
            .with_metric("fatigue_index".to_string(), fatigue_acc)
            .with_metric("energy_drift".to_string(), energy_drift)
            .with_metric("burn_spins".to_string(), burn_result.total_spins as f64)
            .with_metric("duration_ms".to_string(), duration_ms as f64))
    }

    fn estimated_duration_ms(&self) -> u64 {
        15000
    }
}

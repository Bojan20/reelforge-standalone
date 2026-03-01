// ============================================================================
// rf-fluxmacro — JSON Reporter
// ============================================================================
// FM-15: JSON report generator — versioned stable API for CI/CD.
// ============================================================================

use serde::Serialize;

use crate::context::{MacroContext, ReportFormat};
use crate::error::FluxMacroError;
use crate::reporter::Reporter;

/// JSON report generator for CI/CD integration.
pub struct JsonReporter;

/// Stable JSON report format (version 1).
#[derive(Serialize)]
struct JsonReport {
    version: u32,
    game_id: String,
    timestamp: String,
    duration_ms: u64,
    overall_status: String,
    seed: u64,
    run_hash: String,
    steps: Vec<StepSummary>,
    qa_results: Vec<QaResult>,
    artifacts: Vec<ArtifactEntry>,
    warnings: Vec<String>,
    errors: Vec<String>,
    metrics: ReportMetrics,
}

#[derive(Serialize)]
struct StepSummary {
    name: String,
    status: String,
}

#[derive(Serialize)]
struct QaResult {
    test_name: String,
    passed: bool,
    details: String,
    duration_ms: u64,
    metrics: std::collections::HashMap<String, f64>,
}

#[derive(Serialize)]
struct ArtifactEntry {
    name: String,
    path: String,
}

#[derive(Serialize)]
struct ReportMetrics {
    total_logs: usize,
    total_warnings: usize,
    total_errors: usize,
    qa_passed: usize,
    qa_failed: usize,
    artifact_count: usize,
}

impl Reporter for JsonReporter {
    fn format(&self) -> ReportFormat {
        ReportFormat::Json
    }

    fn generate(&self, ctx: &MacroContext) -> Result<Vec<u8>, FluxMacroError> {
        let report = JsonReport {
            version: 1,
            game_id: ctx.game_id.clone(),
            timestamp: chrono::Local::now().to_rfc3339(),
            duration_ms: ctx.duration().as_millis() as u64,
            overall_status: if ctx.is_success() {
                "PASS".to_string()
            } else {
                "FAIL".to_string()
            },
            seed: ctx.seed,
            run_hash: ctx.run_hash.clone(),
            steps: ctx
                .logs
                .iter()
                .filter(|l| {
                    l.message.starts_with('[') && l.message.contains(']')
                })
                .map(|l| StepSummary {
                    name: l.step.clone(),
                    status: "executed".to_string(),
                })
                .collect(),
            qa_results: ctx
                .qa_results
                .iter()
                .map(|r| QaResult {
                    test_name: r.test_name.clone(),
                    passed: r.passed,
                    details: r.details.clone(),
                    duration_ms: r.duration_ms,
                    metrics: r.metrics.clone(),
                })
                .collect(),
            artifacts: ctx
                .artifacts
                .iter()
                .map(|(name, path)| ArtifactEntry {
                    name: name.clone(),
                    path: path.display().to_string(),
                })
                .collect(),
            warnings: ctx.warnings.clone(),
            errors: ctx.errors.clone(),
            metrics: ReportMetrics {
                total_logs: ctx.logs.len(),
                total_warnings: ctx.warnings.len(),
                total_errors: ctx.errors.len(),
                qa_passed: ctx.qa_passed_count(),
                qa_failed: ctx.qa_failed_count(),
                artifact_count: ctx.artifacts.len(),
            },
        };

        let json = serde_json::to_string_pretty(&report)?;
        Ok(json.into_bytes())
    }

    fn file_extension(&self) -> &'static str {
        "json"
    }
}

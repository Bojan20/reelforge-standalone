// ============================================================================
// rf-fluxmacro — Pack Release Step
// ============================================================================
// FM-30: Release candidate packager.
// Collects all artifacts, manifests, reports into a release ZIP.
// ============================================================================

use std::path::PathBuf;

use crate::context::{LogLevel, MacroContext};
use crate::error::FluxMacroError;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct PackReleaseStep;

impl MacroStep for PackReleaseStep {
    fn name(&self) -> &'static str {
        "pack.release"
    }

    fn description(&self) -> &'static str {
        "Package release candidate with all artifacts and reports"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        if ctx.dry_run {
            return Ok(StepResult::success(format!(
                "Dry-run: would package {} artifacts into release",
                ctx.artifacts.len()
            )));
        }

        let start = std::time::Instant::now();

        ctx.log(
            LogLevel::Info,
            "pack.release",
            &format!(
                "Packaging release candidate: {} artifacts",
                ctx.artifacts.len()
            ),
        );

        // Create release directory
        let release_dir = ctx.working_dir.join("Release");
        std::fs::create_dir_all(&release_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(release_dir.clone(), e))?;

        let safe_game_id = security::sanitize_filename(&ctx.game_id);

        // Copy artifacts into release directory
        let mut copied_artifacts = Vec::new();
        let mut copy_errors = Vec::new();

        for (name, src_path) in &ctx.artifacts {
            if !src_path.exists() {
                copy_errors.push(format!(
                    "Artifact '{}' not found: {}",
                    name,
                    src_path.display()
                ));
                continue;
            }

            let dest_filename = if let Some(ext) = src_path.extension().and_then(|e| e.to_str()) {
                format!(
                    "{}_{}.{}",
                    safe_game_id,
                    security::sanitize_filename(name),
                    ext
                )
            } else {
                format!("{}_{}", safe_game_id, security::sanitize_filename(name))
            };

            let dest_path = release_dir.join(&dest_filename);

            match std::fs::copy(src_path, &dest_path) {
                Ok(_) => {
                    copied_artifacts.push((name.clone(), dest_path));
                }
                Err(e) => {
                    copy_errors.push(format!("Failed to copy '{}': {}", name, e));
                }
            }
        }

        // Generate release manifest
        let release_manifest = generate_release_manifest(ctx, &copied_artifacts);
        let manifest_path = release_dir.join(format!("{safe_game_id}_release_manifest.json"));
        std::fs::write(&manifest_path, &release_manifest)
            .map_err(|e| FluxMacroError::FileWrite(manifest_path.clone(), e))?;

        // Generate release summary
        let summary_path = release_dir.join(format!("{safe_game_id}_release_summary.md"));
        let summary_md = generate_release_summary(ctx, &copied_artifacts, &copy_errors);
        std::fs::write(&summary_path, &summary_md)
            .map_err(|e| FluxMacroError::FileWrite(summary_path.clone(), e))?;

        let duration_ms = start.elapsed().as_millis() as u64;

        ctx.log(
            LogLevel::Info,
            "pack.release",
            &format!(
                "Release packaged: {} artifacts, {} errors, {}ms",
                copied_artifacts.len(),
                copy_errors.len(),
                duration_ms,
            ),
        );

        let summary = format!(
            "Release packaged: {} artifacts in {}",
            copied_artifacts.len(),
            release_dir.display(),
        );

        let mut result = if copy_errors.is_empty() {
            StepResult::success(&summary)
        } else {
            StepResult::success_with_warnings(&summary, copy_errors)
        };

        result = result
            .with_artifact("release_dir".to_string(), release_dir)
            .with_artifact("release_manifest".to_string(), manifest_path)
            .with_artifact("release_summary".to_string(), summary_path)
            .with_metric("artifact_count".to_string(), copied_artifacts.len() as f64)
            .with_metric("duration_ms".to_string(), duration_ms as f64);

        Ok(result)
    }

    fn validate(&self, ctx: &MacroContext) -> Result<(), FluxMacroError> {
        if ctx.artifacts.is_empty() {
            return Err(FluxMacroError::PreconditionNotMet {
                step: "pack.release".to_string(),
                precondition: "No artifacts to package — run generation steps first".to_string(),
            });
        }
        Ok(())
    }

    fn estimated_duration_ms(&self) -> u64 {
        3000
    }
}

fn generate_release_manifest(ctx: &MacroContext, artifacts: &[(String, PathBuf)]) -> String {
    let manifest = serde_json::json!({
        "release_version": "1.0",
        "game_id": ctx.game_id,
        "volatility": format!("{:?}", ctx.volatility),
        "seed": ctx.seed,
        "run_hash": ctx.run_hash,
        "timestamp": chrono::Local::now().to_rfc3339(),
        "duration_ms": ctx.duration().as_millis() as u64,
        "qa_status": if ctx.is_success() { "PASS" } else { "FAIL" },
        "qa_summary": {
            "total_tests": ctx.qa_results.len(),
            "passed": ctx.qa_passed_count(),
            "failed": ctx.qa_failed_count(),
        },
        "artifacts": artifacts.iter().map(|(name, path)| {
            serde_json::json!({
                "name": name,
                "path": path.file_name().and_then(|n| n.to_str()).unwrap_or(""),
                "size_bytes": std::fs::metadata(path).map(|m| m.len()).unwrap_or(0),
            })
        }).collect::<Vec<_>>(),
        "warnings": ctx.warnings,
        "errors": ctx.errors,
    });

    serde_json::to_string_pretty(&manifest).unwrap_or_default()
}

fn generate_release_summary(
    ctx: &MacroContext,
    artifacts: &[(String, PathBuf)],
    errors: &[String],
) -> String {
    let mut md = String::with_capacity(4096);

    md.push_str(&format!("# Release Summary — {}\n\n", ctx.game_id));
    md.push_str(&format!(
        "**Status:** {}\n",
        if ctx.is_success() { "PASS" } else { "FAIL" }
    ));
    md.push_str(&format!("**Volatility:** {:?}\n", ctx.volatility));
    md.push_str(&format!("**Seed:** {}\n", ctx.seed));
    md.push_str(&format!("**Run Hash:** {}\n", &ctx.run_hash));
    md.push_str(&format!(
        "**Duration:** {:.1}s\n\n",
        ctx.duration().as_secs_f64()
    ));

    md.push_str("## QA Results\n\n");
    md.push_str(&format!(
        "- **Passed:** {}\n- **Failed:** {}\n- **Total:** {}\n\n",
        ctx.qa_passed_count(),
        ctx.qa_failed_count(),
        ctx.qa_results.len(),
    ));

    if !ctx.qa_results.is_empty() {
        md.push_str("| Test | Status | Details |\n");
        md.push_str("|------|--------|---------|\n");
        for qa in &ctx.qa_results {
            let status = if qa.passed { "PASS" } else { "FAIL" };
            md.push_str(&format!(
                "| {} | {} | {} |\n",
                qa.test_name, status, qa.details
            ));
        }
        md.push('\n');
    }

    md.push_str("## Artifacts\n\n");
    for (name, path) in artifacts {
        let size = std::fs::metadata(path).map(|m| m.len()).unwrap_or(0);
        let filename = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        md.push_str(&format!("- **{name}**: `{filename}` ({} bytes)\n", size));
    }

    if !errors.is_empty() {
        md.push_str("\n## Packaging Errors\n\n");
        for e in errors {
            md.push_str(&format!("- {e}\n"));
        }
    }

    if !ctx.warnings.is_empty() {
        md.push_str("\n## Warnings\n\n");
        for w in &ctx.warnings {
            md.push_str(&format!("- {w}\n"));
        }
    }

    md.push_str("\n---\n*Generated by FluxMacro Pack Release*\n");
    md
}

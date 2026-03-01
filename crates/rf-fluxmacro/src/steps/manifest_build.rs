// ============================================================================
// rf-fluxmacro — Manifest Builder Step
// ============================================================================
// FM-23: Builds flux_manifest.json wrapping rf-aurexis FluxManifest + DRC.
// Version locks, config bundle hash, certification chain.
// ============================================================================

use crate::context::{LogLevel, MacroContext};
use crate::error::FluxMacroError;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct ManifestBuildStep;

impl MacroStep for ManifestBuildStep {
    fn name(&self) -> &'static str {
        "manifest.build"
    }

    fn description(&self) -> &'static str {
        "Build flux_manifest.json with version locks and certification chain"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        if ctx.dry_run {
            return Ok(StepResult::success(
                "Dry-run: would build flux_manifest.json",
            ));
        }

        // Build config data string for hashing
        let config_data = build_config_string(ctx);

        // Create manifest via rf-aurexis
        let mut manifest = rf_aurexis::drc::manifest::FluxManifest::new();
        manifest.set_config_hash(&config_data);

        // Check QA results from intermediate data (populated by qa steps)
        let drc_pass = ctx
            .get_intermediate("qa_determinism_passed")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let pbse_pass = ctx
            .get_intermediate("qa_event_storm_passed")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let envelope_pass = ctx
            .get_intermediate("qa_loudness_passed")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        manifest.update_certification(drc_pass, pbse_pass, envelope_pass);

        // Write manifest
        let manifest_dir = ctx.working_dir.join("Manifest");
        std::fs::create_dir_all(&manifest_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(manifest_dir.clone(), e))?;

        let filename = format!(
            "flux_manifest_{}.json",
            security::sanitize_filename(&ctx.game_id)
        );
        let path = manifest_dir.join(&filename);

        let json = manifest
            .to_json()
            .map_err(|e| FluxMacroError::Other(format!("Manifest serialization failed: {e}")))?;
        std::fs::write(&path, &json)
            .map_err(|e| FluxMacroError::FileWrite(path.clone(), e))?;

        // Store in intermediate
        ctx.set_intermediate(
            "flux_manifest",
            serde_json::from_str(&json).unwrap_or(serde_json::Value::Null),
        );

        let certified = manifest.is_certified();
        let status_str = if certified { "CERTIFIED" } else { "PENDING" };

        ctx.log(
            LogLevel::Info,
            "manifest.build",
            &format!("Manifest built: status={status_str}, hash={}", manifest.manifest_hash),
        );

        let mut warnings = Vec::new();
        if !certified {
            if !drc_pass {
                warnings.push("DRC not passed".to_string());
            }
            if !pbse_pass {
                warnings.push("PBSE not passed".to_string());
            }
            if !envelope_pass {
                warnings.push("Loudness not passed".to_string());
            }
        }

        let summary = format!("Manifest built: {status_str} (hash={})", manifest.manifest_hash);
        let result = if warnings.is_empty() {
            StepResult::success(&summary)
        } else {
            StepResult::success_with_warnings(&summary, warnings)
        };

        Ok(result
            .with_artifact("flux_manifest".to_string(), path)
            .with_metric("manifest_hash".to_string(), manifest.manifest_hash as f64)
            .with_metric("certified".to_string(), if certified { 1.0 } else { 0.0 }))
    }

    fn estimated_duration_ms(&self) -> u64 {
        500
    }
}

/// Build a deterministic config string for hashing.
fn build_config_string(ctx: &MacroContext) -> String {
    let mut parts = Vec::new();
    parts.push(format!("game_id={}", ctx.game_id));
    parts.push(format!("volatility={:?}", ctx.volatility));
    parts.push(format!("seed={}", ctx.seed));

    let mut platforms: Vec<String> = ctx.platforms.iter().map(|p| format!("{p:?}")).collect();
    platforms.sort();
    parts.push(format!("platforms={}", platforms.join(",")));

    let mut mechanics: Vec<String> = ctx.mechanics.iter().map(|m| m.id().to_string()).collect();
    mechanics.sort();
    parts.push(format!("mechanics={}", mechanics.join(",")));

    if let Some(ref theme) = ctx.theme {
        parts.push(format!("theme={theme}"));
    }

    parts.join("|")
}

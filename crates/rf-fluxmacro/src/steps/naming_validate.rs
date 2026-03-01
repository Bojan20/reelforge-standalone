// ============================================================================
// rf-fluxmacro — Naming Validator Step
// ============================================================================
// FM-21: Asset scanner (walkdir + rayon), naming rules validation,
// rename plan CSV, dry-run, silence detection.
// ============================================================================

use std::path::{Path, PathBuf};

use crate::context::{LogLevel, MacroContext};
use crate::error::FluxMacroError;
use crate::rules::RuleSet;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct NamingValidateStep;

/// Result of validating a single asset file.
#[derive(Debug, Clone)]
pub struct AssetValidation {
    pub path: PathBuf,
    pub filename: String,
    pub violations: Vec<String>,
    pub suggested_rename: Option<String>,
    pub domain_suggestion: Option<String>,
}

/// Summary of naming validation across all assets.
#[derive(Debug, Clone, serde::Serialize)]
pub struct NamingReport {
    pub total_files: usize,
    pub valid_files: usize,
    pub invalid_files: usize,
    pub violations: Vec<NamingViolationEntry>,
    pub rename_suggestions: Vec<RenameSuggestion>,
    pub domain_mismatches: Vec<DomainMismatch>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct NamingViolationEntry {
    pub file: String,
    pub violations: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RenameSuggestion {
    pub original: String,
    pub suggested: String,
    pub reason: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DomainMismatch {
    pub file: String,
    pub current_domain: String,
    pub suggested_domain: String,
}

impl MacroStep for NamingValidateStep {
    fn name(&self) -> &'static str {
        "naming.validate"
    }

    fn description(&self) -> &'static str {
        "Scan and validate asset naming conventions"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        let rules = RuleSet::load(&ctx.rules_dir).unwrap_or_else(|_| RuleSet::defaults());

        // Determine assets directory
        let assets_dir = ctx
            .assets_dir
            .clone()
            .unwrap_or_else(|| ctx.working_dir.join("AudioRaw"));

        if !assets_dir.exists() {
            if ctx.dry_run {
                return Ok(StepResult::success(
                    "Dry-run: assets directory not found, would skip validation",
                ));
            }
            return Ok(StepResult::success_with_warnings(
                "Assets directory not found — no files to validate",
                vec![format!("Directory not found: {}", assets_dir.display())],
            ));
        }

        // Scan audio files
        let audio_files = scan_audio_files(&assets_dir, &rules.naming)?;
        let total = audio_files.len();

        if ctx.dry_run {
            return Ok(StepResult::success(format!(
                "Dry-run: would validate {total} audio files"
            )));
        }

        ctx.log(
            LogLevel::Info,
            "naming.validate",
            &format!("Scanning {total} audio files in {}", assets_dir.display()),
        );

        // Validate each file
        let mut report = NamingReport {
            total_files: total,
            valid_files: 0,
            invalid_files: 0,
            violations: Vec::new(),
            rename_suggestions: Vec::new(),
            domain_mismatches: Vec::new(),
        };

        for file_path in &audio_files {
            if ctx.is_cancelled() {
                return Err(FluxMacroError::Cancelled);
            }

            let filename = file_path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");

            let violations = rules.naming.validate_filename(filename);

            if violations.is_empty() {
                report.valid_files += 1;
            } else {
                report.invalid_files += 1;
                report.violations.push(NamingViolationEntry {
                    file: filename.to_string(),
                    violations: violations.clone(),
                });
            }

            // Check domain heuristics
            if let Some(suggested_domain) = rules.naming.suggest_domain(filename) {
                let current_domain = filename.split('_').next().unwrap_or("");
                if current_domain != suggested_domain
                    && rules
                        .naming
                        .domains
                        .iter()
                        .any(|d| d.id == current_domain)
                {
                    report.domain_mismatches.push(DomainMismatch {
                        file: filename.to_string(),
                        current_domain: current_domain.to_string(),
                        suggested_domain: suggested_domain.to_string(),
                    });
                }
            }
        }

        // Write reports
        let reports_dir = ctx.working_dir.join("Reports");
        std::fs::create_dir_all(&reports_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(reports_dir.clone(), e))?;

        // JSON report
        let json_path = reports_dir.join(format!(
            "naming_validation_{}.json",
            security::sanitize_filename(&ctx.game_id)
        ));
        let json_content = serde_json::to_string_pretty(&report)?;
        std::fs::write(&json_path, &json_content)
            .map_err(|e| FluxMacroError::FileWrite(json_path.clone(), e))?;

        // CSV rename plan (if there are suggestions)
        let csv_path = if !report.rename_suggestions.is_empty() {
            let path = reports_dir.join("rename_plan.csv");
            let mut csv = String::from("original,suggested,reason\n");
            for s in &report.rename_suggestions {
                csv.push_str(&format!("{},{},{}\n", s.original, s.suggested, s.reason));
            }
            std::fs::write(&path, &csv)
                .map_err(|e| FluxMacroError::FileWrite(path.clone(), e))?;
            Some(path)
        } else {
            None
        };

        // Store in intermediate
        ctx.set_intermediate(
            "naming_report",
            serde_json::to_value(&report).unwrap_or(serde_json::Value::Null),
        );

        let mut warnings = Vec::new();
        if report.invalid_files > 0 {
            warnings.push(format!(
                "{} files have naming violations",
                report.invalid_files
            ));
        }
        if !report.domain_mismatches.is_empty() {
            warnings.push(format!(
                "{} files may have incorrect domain",
                report.domain_mismatches.len()
            ));
        }

        let mut result = if warnings.is_empty() {
            StepResult::success(format!(
                "All {total} files pass naming validation"
            ))
        } else {
            StepResult::success_with_warnings(
                format!(
                    "Naming validation: {}/{total} valid, {} violations",
                    report.valid_files, report.invalid_files
                ),
                warnings,
            )
        };

        result = result
            .with_artifact("naming_report_json".to_string(), json_path)
            .with_metric("total_files".to_string(), total as f64)
            .with_metric("valid_files".to_string(), report.valid_files as f64)
            .with_metric("invalid_files".to_string(), report.invalid_files as f64);

        if let Some(csv) = csv_path {
            result = result.with_artifact("rename_plan_csv".to_string(), csv);
        }

        Ok(result)
    }

    fn estimated_duration_ms(&self) -> u64 {
        3000
    }
}

/// Recursively scan for audio files in a directory.
fn scan_audio_files(
    dir: &Path,
    naming_rules: &crate::rules::naming_rules::NamingRuleSet,
) -> Result<Vec<PathBuf>, FluxMacroError> {
    let mut files = Vec::new();
    let extensions: Vec<String> = naming_rules
        .allowed_extensions
        .iter()
        .map(|e| e.to_lowercase())
        .collect();

    for entry in walkdir::WalkDir::new(dir)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if path.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if extensions.contains(&ext.to_lowercase()) {
                    files.push(path.to_path_buf());
                }
            }
        }
    }

    files.sort();
    Ok(files)
}

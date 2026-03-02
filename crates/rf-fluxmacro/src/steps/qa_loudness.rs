// ============================================================================
// rf-fluxmacro — QA Loudness Compliance Step
// ============================================================================
// FM-27: Measures loudness of rendered audio assets via rf-offline LoudnessMeter.
// Validates per-domain LUFS/TP targets from rules.
// ============================================================================

use std::path::{Path, PathBuf};

use crate::context::{LogLevel, MacroContext, QaTestResult};
use crate::error::FluxMacroError;
use crate::rules::RuleSet;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct QaLoudnessStep;

/// Per-file loudness measurement result.
#[derive(Debug, Clone, serde::Serialize)]
pub struct LoudnessMeasurement {
    pub file: String,
    pub domain: String,
    pub integrated_lufs: f64,
    pub true_peak_dbtp: f64,
    pub short_term_lufs: f64,
    pub target_lufs: f64,
    pub target_tp: f64,
    pub lufs_passed: bool,
    pub tp_passed: bool,
    pub passed: bool,
}

impl MacroStep for QaLoudnessStep {
    fn name(&self) -> &'static str {
        "qa.loudness"
    }

    fn description(&self) -> &'static str {
        "Measure and validate loudness compliance per audio domain"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        let rules = RuleSet::load(&ctx.rules_dir).unwrap_or_else(|_| RuleSet::defaults());

        let assets_dir = ctx
            .assets_dir
            .clone()
            .unwrap_or_else(|| ctx.working_dir.join("AudioRaw"));

        if ctx.dry_run {
            return Ok(StepResult::success(
                "Dry-run: would measure loudness compliance for audio assets",
            ));
        }

        if !assets_dir.exists() {
            return Ok(StepResult::success_with_warnings(
                "Assets directory not found — skipping loudness check",
                vec![format!("Directory not found: {}", assets_dir.display())],
            ));
        }

        let start = std::time::Instant::now();

        ctx.log(
            LogLevel::Info,
            "qa.loudness",
            &format!("Measuring loudness for assets in {}", assets_dir.display()),
        );

        // Scan audio files
        let audio_files = scan_audio_files(&assets_dir)?;

        if audio_files.is_empty() {
            return Ok(StepResult::success_with_warnings(
                "No audio files found for loudness measurement",
                vec!["No .wav/.ogg/.mp3 files found".to_string()],
            ));
        }

        let mut measurements = Vec::new();
        let mut total_passed = 0usize;
        let mut total_failed = 0usize;

        for file_path in &audio_files {
            if ctx.is_cancelled() {
                return Err(FluxMacroError::Cancelled);
            }

            let filename = file_path.file_name().and_then(|n| n.to_str()).unwrap_or("");

            // Determine domain from filename prefix
            let domain = detect_domain(filename);

            // Get target for this domain
            let (target_lufs, target_tp, tolerance) =
                if let Some(target) = rules.loudness.domains.get(&domain) {
                    (
                        target.lufs_target as f64,
                        target.true_peak_max as f64,
                        target.lufs_tolerance as f64,
                    )
                } else {
                    (-18.0_f64, -1.0_f64, 2.0_f64)
                };

            // Decode and measure
            match measure_file(file_path) {
                Ok(info) => {
                    let lufs_passed = (info.integrated - target_lufs).abs() <= tolerance;
                    let tp_passed = info.true_peak <= target_tp;
                    let passed = lufs_passed && tp_passed;

                    if passed {
                        total_passed += 1;
                    } else {
                        total_failed += 1;
                    }

                    measurements.push(LoudnessMeasurement {
                        file: filename.to_string(),
                        domain: domain.clone(),
                        integrated_lufs: info.integrated,
                        true_peak_dbtp: info.true_peak,
                        short_term_lufs: info.short_term,
                        target_lufs,
                        target_tp,
                        lufs_passed,
                        tp_passed,
                        passed,
                    });
                }
                Err(e) => {
                    total_failed += 1;
                    ctx.log(
                        LogLevel::Warning,
                        "qa.loudness",
                        &format!("Failed to measure {filename}: {e}"),
                    );
                }
            }
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        // Record per-domain QA results
        let domains: Vec<String> = measurements
            .iter()
            .map(|m| m.domain.clone())
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .collect();

        for domain in &domains {
            let domain_measurements: Vec<&LoudnessMeasurement> = measurements
                .iter()
                .filter(|m| &m.domain == domain)
                .collect();
            let domain_passed = domain_measurements.iter().all(|m| m.passed);
            let avg_lufs = if domain_measurements.is_empty() {
                0.0
            } else {
                domain_measurements
                    .iter()
                    .map(|m| m.integrated_lufs)
                    .sum::<f64>()
                    / domain_measurements.len() as f64
            };

            ctx.qa_results.push(QaTestResult {
                test_name: format!("loudness.{domain}"),
                passed: domain_passed,
                details: format!(
                    "{} files, avg={:.1} LUFS, {} passed",
                    domain_measurements.len(),
                    avg_lufs,
                    domain_measurements.iter().filter(|m| m.passed).count(),
                ),
                duration_ms: duration_ms / domains.len().max(1) as u64,
                metrics: {
                    let mut m = std::collections::HashMap::new();
                    m.insert("avg_lufs".to_string(), avg_lufs);
                    m.insert("file_count".to_string(), domain_measurements.len() as f64);
                    m
                },
            });
        }

        let all_passed = total_failed == 0;

        // Store pass/fail for manifest
        ctx.set_intermediate("qa_loudness_passed", serde_json::json!(all_passed));

        // Write report
        let reports_dir = ctx.working_dir.join("Reports");
        std::fs::create_dir_all(&reports_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(reports_dir.clone(), e))?;

        let report_path = reports_dir.join(format!(
            "loudness_report_{}.json",
            security::sanitize_filename(&ctx.game_id)
        ));

        let report = serde_json::json!({
            "total_files": measurements.len(),
            "passed": total_passed,
            "failed": total_failed,
            "all_passed": all_passed,
            "measurements": measurements,
        });

        let json_str = serde_json::to_string_pretty(&report)?;
        std::fs::write(&report_path, &json_str)
            .map_err(|e| FluxMacroError::FileWrite(report_path.clone(), e))?;

        ctx.log(
            LogLevel::Info,
            "qa.loudness",
            &format!(
                "Loudness check: {}/{} passed, {} files measured",
                total_passed,
                total_passed + total_failed,
                measurements.len(),
            ),
        );

        let summary = format!(
            "Loudness: {}/{} passed",
            total_passed,
            total_passed + total_failed,
        );

        let mut warnings = Vec::new();
        if total_failed > 0 {
            warnings.push(format!("{total_failed} files failed loudness compliance"));
        }

        let result = if warnings.is_empty() {
            StepResult::success(&summary)
        } else {
            StepResult::success_with_warnings(&summary, warnings)
        };

        Ok(result
            .with_artifact("loudness_report".to_string(), report_path)
            .with_metric("total_files".to_string(), measurements.len() as f64)
            .with_metric("passed".to_string(), total_passed as f64)
            .with_metric("failed".to_string(), total_failed as f64))
    }

    fn estimated_duration_ms(&self) -> u64 {
        10000
    }
}

/// Detect audio domain from filename prefix.
fn detect_domain(filename: &str) -> String {
    let lower = filename.to_lowercase();
    if lower.starts_with("ui_") || lower.starts_with("ui-") {
        "ui".to_string()
    } else if lower.starts_with("sfx_") || lower.starts_with("sfx-") {
        "sfx".to_string()
    } else if lower.starts_with("mus_") || lower.starts_with("mus-") || lower.starts_with("music_")
    {
        "mus".to_string()
    } else if lower.starts_with("vo_") || lower.starts_with("vo-") || lower.starts_with("voice_") {
        "vo".to_string()
    } else if lower.starts_with("amb_")
        || lower.starts_with("amb-")
        || lower.starts_with("ambience_")
    {
        "amb".to_string()
    } else {
        "sfx".to_string() // Default domain
    }
}

/// Scan for audio files recursively.
fn scan_audio_files(dir: &Path) -> Result<Vec<PathBuf>, FluxMacroError> {
    let extensions = ["wav", "ogg", "mp3", "flac", "aiff", "aif"];
    let mut files = Vec::new();

    for entry in walkdir::WalkDir::new(dir)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if path.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if extensions.contains(&ext.to_lowercase().as_str()) {
                    files.push(path.to_path_buf());
                }
            }
        }
    }

    files.sort();
    Ok(files)
}

/// Measure loudness of a single file.
fn measure_file(path: &Path) -> Result<rf_offline::LoudnessInfo, FluxMacroError> {
    let buffer = rf_offline::AudioDecoder::decode(path)
        .map_err(|e| FluxMacroError::Other(format!("Decode error: {e}")))?;

    let mut meter = rf_offline::LoudnessMeter::new(buffer.sample_rate, buffer.channels);

    // Process all samples (already f64)
    meter.process(&buffer.samples);

    Ok(meter.get_info())
}

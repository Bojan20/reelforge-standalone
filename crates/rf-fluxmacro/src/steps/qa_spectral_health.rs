// ============================================================================
// rf-fluxmacro — QA Spectral Health Step
// ============================================================================
// FM-29: Spectral analysis for audio health checks.
// Detects DC offset, clipping, excessive high-frequency content,
// silence gaps, and spectral imbalance.
// ============================================================================

use std::path::{Path, PathBuf};

use crate::context::{LogLevel, MacroContext, QaTestResult};
use crate::error::FluxMacroError;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct QaSpectralHealthStep;

/// Per-file spectral health result.
#[derive(Debug, Clone, serde::Serialize)]
pub struct SpectralHealthResult {
    pub file: String,
    pub dc_offset: f64,
    pub dc_offset_pass: bool,
    pub clipping_samples: usize,
    pub clipping_pass: bool,
    pub crest_factor_db: f64,
    pub silence_ratio: f64,
    pub silence_pass: bool,
    pub spectral_centroid_hz: f64,
    pub high_freq_energy_ratio: f64,
    pub high_freq_pass: bool,
    pub overall_pass: bool,
}

/// Thresholds for spectral health checks.
const DC_OFFSET_MAX: f64 = 0.01; // Max absolute DC offset
const CLIPPING_THRESHOLD: f64 = 0.9999; // Sample value threshold for clipping
const MAX_CLIPPING_RATIO: f64 = 0.001; // Max 0.1% clipping samples
const SILENCE_MAX_RATIO: f64 = 0.5; // Max 50% silence (< -60dB)
const HIGH_FREQ_MAX_RATIO: f64 = 0.6; // Max 60% energy above 10kHz
const SILENCE_THRESHOLD_DB: f64 = -60.0;

impl MacroStep for QaSpectralHealthStep {
    fn name(&self) -> &'static str {
        "qa.spectral_health"
    }

    fn description(&self) -> &'static str {
        "Check spectral health: DC offset, clipping, silence, frequency balance"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        let assets_dir = ctx
            .assets_dir
            .clone()
            .unwrap_or_else(|| ctx.working_dir.join("AudioRaw"));

        if ctx.dry_run {
            return Ok(StepResult::success(
                "Dry-run: would check spectral health of audio assets",
            ));
        }

        if !assets_dir.exists() {
            return Ok(StepResult::success_with_warnings(
                "Assets directory not found — skipping spectral health",
                vec![format!("Directory not found: {}", assets_dir.display())],
            ));
        }

        let start = std::time::Instant::now();

        ctx.log(
            LogLevel::Info,
            "qa.spectral_health",
            &format!("Analyzing spectral health in {}", assets_dir.display()),
        );

        let audio_files = scan_audio_files(&assets_dir)?;

        if audio_files.is_empty() {
            return Ok(StepResult::success_with_warnings(
                "No audio files found for spectral analysis",
                vec!["No audio files found".to_string()],
            ));
        }

        let mut results = Vec::new();
        let mut total_passed = 0usize;
        let mut total_failed = 0usize;

        for file_path in &audio_files {
            if ctx.is_cancelled() {
                return Err(FluxMacroError::Cancelled);
            }

            let filename = file_path.file_name().and_then(|n| n.to_str()).unwrap_or("");

            match analyze_spectral_health(file_path) {
                Ok(health) => {
                    if health.overall_pass {
                        total_passed += 1;
                    } else {
                        total_failed += 1;
                    }
                    results.push(health);
                }
                Err(e) => {
                    total_failed += 1;
                    ctx.log(
                        LogLevel::Warning,
                        "qa.spectral_health",
                        &format!("Failed to analyze {filename}: {e}"),
                    );
                }
            }
        }

        let duration_ms = start.elapsed().as_millis() as u64;

        // Record QA results
        let dc_failures = results.iter().filter(|r| !r.dc_offset_pass).count();
        let clip_failures = results.iter().filter(|r| !r.clipping_pass).count();
        let silence_failures = results.iter().filter(|r| !r.silence_pass).count();
        let hf_failures = results.iter().filter(|r| !r.high_freq_pass).count();

        ctx.qa_results.push(QaTestResult {
            test_name: "spectral.dc_offset".to_string(),
            passed: dc_failures == 0,
            details: format!(
                "{}/{} files pass DC offset check",
                results.len() - dc_failures,
                results.len()
            ),
            duration_ms: duration_ms / 4,
            metrics: {
                let mut m = std::collections::HashMap::new();
                m.insert("failures".to_string(), dc_failures as f64);
                m
            },
        });

        ctx.qa_results.push(QaTestResult {
            test_name: "spectral.clipping".to_string(),
            passed: clip_failures == 0,
            details: format!(
                "{}/{} files pass clipping check",
                results.len() - clip_failures,
                results.len()
            ),
            duration_ms: duration_ms / 4,
            metrics: {
                let mut m = std::collections::HashMap::new();
                m.insert("failures".to_string(), clip_failures as f64);
                m
            },
        });

        ctx.qa_results.push(QaTestResult {
            test_name: "spectral.silence".to_string(),
            passed: silence_failures == 0,
            details: format!(
                "{}/{} files pass silence check",
                results.len() - silence_failures,
                results.len()
            ),
            duration_ms: duration_ms / 4,
            metrics: {
                let mut m = std::collections::HashMap::new();
                m.insert("failures".to_string(), silence_failures as f64);
                m
            },
        });

        ctx.qa_results.push(QaTestResult {
            test_name: "spectral.frequency_balance".to_string(),
            passed: hf_failures == 0,
            details: format!(
                "{}/{} files pass HF balance check",
                results.len() - hf_failures,
                results.len()
            ),
            duration_ms: duration_ms / 4,
            metrics: {
                let mut m = std::collections::HashMap::new();
                m.insert("failures".to_string(), hf_failures as f64);
                m
            },
        });

        let all_passed = total_failed == 0;
        ctx.set_intermediate("qa_spectral_passed", serde_json::json!(all_passed));

        // Write report
        let reports_dir = ctx.working_dir.join("Reports");
        std::fs::create_dir_all(&reports_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(reports_dir.clone(), e))?;

        let report_path = reports_dir.join(format!(
            "spectral_health_{}.json",
            security::sanitize_filename(&ctx.game_id)
        ));

        let report = serde_json::json!({
            "total_files": results.len(),
            "passed": total_passed,
            "failed": total_failed,
            "all_passed": all_passed,
            "issue_summary": {
                "dc_offset_failures": dc_failures,
                "clipping_failures": clip_failures,
                "silence_failures": silence_failures,
                "high_freq_failures": hf_failures,
            },
            "results": results,
        });

        let json_str = serde_json::to_string_pretty(&report)?;
        std::fs::write(&report_path, &json_str)
            .map_err(|e| FluxMacroError::FileWrite(report_path.clone(), e))?;

        ctx.log(
            LogLevel::Info,
            "qa.spectral_health",
            &format!(
                "Spectral health: {}/{} passed ({} DC, {} clip, {} silence, {} HF issues)",
                total_passed,
                total_passed + total_failed,
                dc_failures,
                clip_failures,
                silence_failures,
                hf_failures,
            ),
        );

        let summary = format!(
            "Spectral health: {}/{} passed",
            total_passed,
            total_passed + total_failed,
        );

        let mut warnings = Vec::new();
        if dc_failures > 0 {
            warnings.push(format!("{dc_failures} files have DC offset"));
        }
        if clip_failures > 0 {
            warnings.push(format!("{clip_failures} files have clipping"));
        }
        if silence_failures > 0 {
            warnings.push(format!("{silence_failures} files have excessive silence"));
        }
        if hf_failures > 0 {
            warnings.push(format!("{hf_failures} files have high-frequency imbalance"));
        }

        let result = if warnings.is_empty() {
            StepResult::success(&summary)
        } else {
            StepResult::success_with_warnings(&summary, warnings)
        };

        Ok(result
            .with_artifact("spectral_report".to_string(), report_path)
            .with_metric("total_files".to_string(), results.len() as f64)
            .with_metric("passed".to_string(), total_passed as f64)
            .with_metric("failed".to_string(), total_failed as f64))
    }

    fn estimated_duration_ms(&self) -> u64 {
        8000
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

/// Analyze spectral health of a single file.
fn analyze_spectral_health(path: &Path) -> Result<SpectralHealthResult, FluxMacroError> {
    let buffer = rf_offline::AudioDecoder::decode(path)
        .map_err(|e| FluxMacroError::Other(format!("Decode error: {e}")))?;

    let filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_string();

    let samples = &buffer.samples;
    let total_samples = samples.len();

    if total_samples == 0 {
        return Ok(SpectralHealthResult {
            file: filename,
            dc_offset: 0.0,
            dc_offset_pass: true,
            clipping_samples: 0,
            clipping_pass: true,
            crest_factor_db: 0.0,
            silence_ratio: 1.0,
            silence_pass: false,
            spectral_centroid_hz: 0.0,
            high_freq_energy_ratio: 0.0,
            high_freq_pass: true,
            overall_pass: false,
        });
    }

    // DC offset: mean of all samples (samples are f64)
    let sum: f64 = samples.iter().sum();
    let dc_offset = (sum / total_samples as f64).abs();
    let dc_offset_pass = dc_offset < DC_OFFSET_MAX;

    // Clipping: count samples at or near ±1.0
    let clipping_samples = samples
        .iter()
        .filter(|&&s| s.abs() >= CLIPPING_THRESHOLD)
        .count();
    let clipping_ratio = clipping_samples as f64 / total_samples as f64;
    let clipping_pass = clipping_ratio < MAX_CLIPPING_RATIO;

    // Crest factor: peak / RMS
    let peak = samples.iter().map(|s| s.abs()).fold(0.0f64, f64::max);
    let rms = (samples.iter().map(|s| s * s).sum::<f64>() / total_samples as f64).sqrt();
    let crest_factor_db = if rms > 0.0 {
        20.0 * (peak / rms).log10()
    } else {
        0.0
    };

    // Silence ratio: percentage below threshold
    let silence_threshold_linear = 10.0f64.powf(SILENCE_THRESHOLD_DB / 20.0);
    let silence_samples = samples
        .iter()
        .filter(|&&s| s.abs() < silence_threshold_linear)
        .count();
    let silence_ratio = silence_samples as f64 / total_samples as f64;
    let silence_pass = silence_ratio < SILENCE_MAX_RATIO;

    // Spectral centroid (simplified: energy-weighted frequency via zero-crossing rate)
    let sample_rate = buffer.sample_rate as f64;
    let mut zero_crossings = 0usize;
    for i in 1..total_samples {
        if (samples[i] >= 0.0) != (samples[i - 1] >= 0.0) {
            zero_crossings += 1;
        }
    }
    let spectral_centroid_hz = (zero_crossings as f64 * sample_rate) / (2.0 * total_samples as f64);

    // High-frequency energy ratio (simplified: energy of zero-crossing-heavy segments)
    // Use spectral centroid as proxy
    let high_freq_energy_ratio = (spectral_centroid_hz / (sample_rate / 2.0)).min(1.0);
    let high_freq_pass = high_freq_energy_ratio < HIGH_FREQ_MAX_RATIO;

    let overall_pass = dc_offset_pass && clipping_pass && silence_pass && high_freq_pass;

    Ok(SpectralHealthResult {
        file: filename,
        dc_offset,
        dc_offset_pass,
        clipping_samples,
        clipping_pass,
        crest_factor_db,
        silence_ratio,
        silence_pass,
        spectral_centroid_hz,
        high_freq_energy_ratio,
        high_freq_pass,
        overall_pass,
    })
}

// ============================================================================
// rf-fluxmacro — Run Versioning
// ============================================================================
// FM-7: Run versioning — save/load run history with timestamps.
// Each run is stored in a timestamped folder under /Runs/.
// ============================================================================

use std::path::{Path, PathBuf};

use chrono::Local;
use serde::{Deserialize, Serialize};

use crate::context::MacroContext;
use crate::error::FluxMacroError;

/// Metadata for a completed macro run, persisted as run_meta.json.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunMeta {
    pub run_id: String,
    pub macro_name: String,
    pub game_id: String,
    pub timestamp: String,
    pub seed: u64,
    pub run_hash: String,
    pub duration_ms: u64,
    pub success: bool,
    pub steps: Vec<String>,
    pub qa_passed: usize,
    pub qa_failed: usize,
    pub artifact_count: usize,
    pub warning_count: usize,
    pub error_count: usize,
}

/// Generate a unique run ID from current timestamp.
pub fn generate_run_id() -> String {
    Local::now().format("%Y-%m-%dT%H-%M-%S").to_string()
}

/// Get the runs directory for a working directory.
pub fn runs_dir(working_dir: &Path) -> PathBuf {
    working_dir.join("Runs")
}

/// Get the directory for a specific run.
pub fn run_dir(working_dir: &Path, run_id: &str) -> PathBuf {
    runs_dir(working_dir).join(run_id)
}

/// Save run history to disk.
/// Creates /Runs/{run_id}/ folder with:
///   - run_meta.json — run metadata
///   - macro_input.yaml — original macro file content (if provided)
///   - logs.txt — formatted log entries
///   - result_hash.txt — run hash
pub fn save_run_history(
    ctx: &MacroContext,
    macro_name: &str,
    steps: &[String],
    macro_content: Option<&str>,
) -> Result<PathBuf, FluxMacroError> {
    let run_id = generate_run_id();
    let dir = run_dir(&ctx.working_dir, &run_id);

    std::fs::create_dir_all(&dir).map_err(|e| FluxMacroError::DirectoryCreate(dir.clone(), e))?;

    // 1. Run metadata
    let meta = RunMeta {
        run_id,
        macro_name: macro_name.to_string(),
        game_id: ctx.game_id.clone(),
        timestamp: Local::now().to_rfc3339(),
        seed: ctx.seed,
        run_hash: ctx.run_hash.clone(),
        duration_ms: ctx.duration().as_millis() as u64,
        success: ctx.is_success(),
        steps: steps.to_vec(),
        qa_passed: ctx.qa_passed_count(),
        qa_failed: ctx.qa_failed_count(),
        artifact_count: ctx.artifacts.len(),
        warning_count: ctx.warnings.len(),
        error_count: ctx.errors.len(),
    };

    let meta_path = dir.join("run_meta.json");
    let meta_json = serde_json::to_string_pretty(&meta)?;
    std::fs::write(&meta_path, &meta_json).map_err(|e| FluxMacroError::FileWrite(meta_path, e))?;

    // 2. Original macro file (if provided)
    if let Some(content) = macro_content {
        let input_path = dir.join("macro_input.yaml");
        std::fs::write(&input_path, content)
            .map_err(|e| FluxMacroError::FileWrite(input_path, e))?;
    }

    // 3. Logs
    let logs_path = dir.join("logs.txt");
    let mut logs_text = String::new();
    for entry in &ctx.logs {
        let level = match entry.level {
            crate::context::LogLevel::Debug => "DEBUG",
            crate::context::LogLevel::Info => "INFO ",
            crate::context::LogLevel::Warning => "WARN ",
            crate::context::LogLevel::Error => "ERROR",
        };
        let elapsed_ms = entry.elapsed.as_millis();
        logs_text.push_str(&format!(
            "[{elapsed_ms:>8}ms] [{level}] [{}] {}\n",
            entry.step, entry.message
        ));
    }
    std::fs::write(&logs_path, &logs_text).map_err(|e| FluxMacroError::FileWrite(logs_path, e))?;

    // 4. Result hash
    let hash_path = dir.join("result_hash.txt");
    std::fs::write(&hash_path, &ctx.run_hash)
        .map_err(|e| FluxMacroError::FileWrite(hash_path, e))?;

    Ok(dir)
}

/// Load run metadata from a run directory.
pub fn load_run_meta(run_path: &Path) -> Result<RunMeta, FluxMacroError> {
    let meta_path = run_path.join("run_meta.json");
    let content =
        std::fs::read_to_string(&meta_path).map_err(|e| FluxMacroError::FileRead(meta_path, e))?;
    let meta: RunMeta = serde_json::from_str(&content)?;
    Ok(meta)
}

/// List all run directories (sorted newest first).
pub fn list_runs(working_dir: &Path) -> Result<Vec<(String, PathBuf)>, FluxMacroError> {
    let dir = runs_dir(working_dir);
    if !dir.exists() {
        return Ok(Vec::new());
    }

    let mut runs = Vec::new();
    for entry in std::fs::read_dir(&dir).map_err(|e| FluxMacroError::FileRead(dir.clone(), e))? {
        let entry = entry.map_err(|e| FluxMacroError::Other(format!("read_dir: {e}")))?;
        let path = entry.path();
        if path.is_dir() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                runs.push((name.to_string(), path));
            }
        }
    }

    // Sort newest first (timestamp-based names sort lexicographically)
    runs.sort_by(|a, b| b.0.cmp(&a.0));
    Ok(runs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn run_id_format() {
        let id = generate_run_id();
        // Should look like 2026-03-01T14-30-00
        assert!(id.contains('T'));
        assert!(id.len() >= 19);
    }

    #[test]
    fn runs_dir_path() {
        let dir = runs_dir(Path::new("/project"));
        assert_eq!(dir, PathBuf::from("/project/Runs"));
    }

    #[test]
    fn run_dir_path() {
        let dir = run_dir(Path::new("/project"), "2026-03-01T14-30-00");
        assert_eq!(dir, PathBuf::from("/project/Runs/2026-03-01T14-30-00"));
    }

    #[test]
    fn list_runs_empty() {
        let tmp = tempfile::tempdir().unwrap();
        let runs = list_runs(tmp.path()).unwrap();
        assert!(runs.is_empty());
    }
}

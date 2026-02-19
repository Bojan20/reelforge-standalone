use crate::config::AccConfig;
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, process::Command};
use tempfile::NamedTempFile;
use std::io::Write;

#[derive(Debug, Clone, Deserialize)]
pub struct PatchApplyRequest {
    pub provider: String,      // "claude"
    pub task_id: String,       // "TASK_001"
    pub reason: Option<String>,
    pub patch: String          // unified diff
}

#[derive(Debug, Clone, Serialize)]
pub struct PatchApplyResponse {
    pub ok: bool,
    pub branch: Option<String>,
    pub changed_files: Vec<String>,
    pub blocked_files: Vec<String>,
    pub error: Option<String>,
}

fn run(repo_root: &PathBuf, args: &[&str]) -> Result<String, String> {
    let out = Command::new("git")
        .args(args)
        .current_dir(repo_root)
        .output()
        .map_err(|e| format!("git {:?} failed to start: {e}", args))?;

    if !out.status.success() {
        return Err(format!(
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

pub fn apply_patch_on_branch(cfg: &AccConfig, req: PatchApplyRequest) -> Result<PatchApplyResponse, String> {
    // Determine current branch
    let current_branch = run(&cfg.repo_root, &["rev-parse", "--abbrev-ref", "HEAD"])?;
    let current_branch = current_branch.trim().to_string();

    // Create branch name
    let ts = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .map_err(|e| e.to_string())?
        .replace(':', "-");
    let branch = format!("acc/{}/{}", req.task_id, ts);

    // Checkout new branch
    run(&cfg.repo_root, &["checkout", "-b", &branch])?;

    // Write patch to temp file
    let mut tmp = NamedTempFile::new().map_err(|e| e.to_string())?;
    tmp.write_all(req.patch.as_bytes()).map_err(|e| e.to_string())?;
    let tmp_path = tmp.path().to_string_lossy().to_string();

    // Apply patch
    let apply_res = Command::new("git")
        .args(["apply", "--whitespace=nowarn", &tmp_path])
        .current_dir(&cfg.repo_root)
        .output()
        .map_err(|e| format!("git apply failed to start: {e}"))?;

    if !apply_res.status.success() {
        // rollback: checkout original branch and delete ours
        let _ = run(&cfg.repo_root, &["checkout", &current_branch]);
        let _ = run(&cfg.repo_root, &["branch", "-D", &branch]);
        return Ok(PatchApplyResponse {
            ok: false,
            branch: None,
            changed_files: vec![],
            blocked_files: vec![],
            error: Some(String::from_utf8_lossy(&apply_res.stderr).to_string()),
        });
    }

    // List changed files
    let changed = run(&cfg.repo_root, &["diff", "--name-only"])?;
    let changed_files: Vec<String> = changed
        .lines()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    // Locked path gate
    let mut blocked = vec![];
    for f in &changed_files {
        if cfg.is_locked(std::path::Path::new(f)) {
            blocked.push(f.clone());
        }
    }

    if !blocked.is_empty() {
        // rollback changes and branch
        let _ = run(&cfg.repo_root, &["reset", "--hard"]);
        let _ = run(&cfg.repo_root, &["checkout", &current_branch]);
        let _ = run(&cfg.repo_root, &["branch", "-D", &branch]);

        return Ok(PatchApplyResponse {
            ok: false,
            branch: None,
            changed_files,
            blocked_files: blocked,
            error: Some("Locked paths modified. Patch rejected.".to_string()),
        });
    }

    // Commit on branch
    run(&cfg.repo_root, &["add", "-A"])?;
    let msg = format!(
        "ACC: {} ({})",
        req.task_id,
        req.reason.unwrap_or_else(|| "auto".to_string())
    );
    run(&cfg.repo_root, &["commit", "-m", &msg])?;

    // Switch back to original branch (keep feature branch)
    run(&cfg.repo_root, &["checkout", &current_branch])?;

    Ok(PatchApplyResponse {
        ok: true,
        branch: Some(branch),
        changed_files,
        blocked_files: vec![],
        error: None,
    })
}

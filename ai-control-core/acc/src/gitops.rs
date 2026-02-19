use crate::config::AccConfig;
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, process::Command};
use tempfile::NamedTempFile;
use std::io::Write;

#[derive(Debug, Clone, Deserialize)]
pub struct PatchApplyRequest {
    pub provider: String,      // "claude" | "openai"
    pub task_id: String,       // "TASK_001"
    pub reason: Option<String>,
    pub patch: String,         // unified diff
}

#[derive(Debug, Clone, Serialize)]
pub struct PatchApplyResponse {
    pub ok: bool,
    pub branch: Option<String>,
    pub merged: bool,
    pub changed_files: Vec<String>,
    pub blocked_files: Vec<String>,
    pub gate_results: GateResults,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct GateResults {
    pub locked_paths: GateResult,
    pub flutter_analyze: GateResult,
}

#[derive(Debug, Clone, Serialize)]
pub struct GateResult {
    pub ran: bool,
    pub passed: bool,
    pub detail: Option<String>,
}

impl Default for GateResult {
    fn default() -> Self {
        Self { ran: false, passed: false, detail: None }
    }
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

fn run_cmd(repo_root: &PathBuf, cmd: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(cmd)
        .args(args)
        .current_dir(repo_root)
        .output()
        .map_err(|e| format!("{cmd} {:?} failed to start: {e}", args))?;

    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();

    if !out.status.success() {
        return Err(format!("{stdout}\n{stderr}"));
    }
    Ok(stdout)
}

/// Run flutter analyze gate. Returns (passed, detail).
fn run_flutter_analyze_gate(cfg: &AccConfig) -> GateResult {
    if !cfg.gates.run_typecheck {
        return GateResult { ran: false, passed: true, detail: Some("skipped (disabled in config)".into()) };
    }

    let flutter_ui = cfg.repo_root.join("flutter_ui");
    if !flutter_ui.exists() {
        return GateResult { ran: false, passed: true, detail: Some("skipped (flutter_ui not found)".into()) };
    }

    tracing::info!("Running flutter analyze gate...");
    match run_cmd(&flutter_ui, "flutter", &["analyze", "--no-fatal-infos"]) {
        Ok(output) => {
            let passed = output.contains("No issues found") || !output.to_lowercase().contains("error");
            GateResult {
                ran: true,
                passed,
                detail: Some(output.lines().take(10).collect::<Vec<_>>().join("\n")),
            }
        }
        Err(e) => {
            let has_errors = e.to_lowercase().contains("error") && !e.to_lowercase().contains("0 error");
            GateResult {
                ran: true,
                passed: !has_errors,
                detail: Some(e.lines().take(15).collect::<Vec<_>>().join("\n")),
            }
        }
    }
}

/// Update SYSTEM_STATUS.json after a patch apply attempt.
fn update_system_status(cfg: &AccConfig, req: &PatchApplyRequest, response: &PatchApplyResponse) {
    let status_path = cfg.state_dir().join("SYSTEM_STATUS.json");

    let ts = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| "unknown".to_string());

    let body = serde_json::json!({
        "acc_version": "0.2.0",
        "environment": "LOCAL",
        "last_start_time": ts,
        "last_apply": {
            "timestamp": ts,
            "task_id": req.task_id,
            "provider": req.provider,
            "reason": req.reason,
            "ok": response.ok,
            "merged": response.merged,
            "changed_files_count": response.changed_files.len(),
            "branch": response.branch,
            "gate_results": response.gate_results,
            "error": response.error,
        },
        "git_clean": null,
        "current_provider": req.provider,
        "emergency_mode": false,
        "notes": "Automatically maintained by ACC runtime."
    });

    if let Ok(json) = serde_json::to_string_pretty(&body) {
        let _ = std::fs::write(&status_path, json);
    }
}

fn rollback_branch(cfg: &AccConfig, current_branch: &str, branch: &str) {
    let _ = run(&cfg.repo_root, &["reset", "--hard"]);
    let _ = run(&cfg.repo_root, &["checkout", current_branch]);
    let _ = run(&cfg.repo_root, &["branch", "-D", branch]);
}

pub fn apply_patch_on_branch(cfg: &AccConfig, req: PatchApplyRequest) -> Result<PatchApplyResponse, String> {
    // Determine current branch
    let current_branch = run(&cfg.repo_root, &["rev-parse", "--abbrev-ref", "HEAD"])?;
    let current_branch = current_branch.trim().to_string();

    // Create branch name
    let safe_reason = req.reason.clone().unwrap_or_else(|| "auto".to_string());
    let branch = format!("acc/{}/{}", req.task_id, safe_reason);

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
        rollback_branch(cfg, &current_branch, &branch);
        let resp = PatchApplyResponse {
            ok: false,
            branch: None,
            merged: false,
            changed_files: vec![],
            blocked_files: vec![],
            gate_results: GateResults::default(),
            error: Some(format!("git apply failed: {}", String::from_utf8_lossy(&apply_res.stderr))),
        };
        update_system_status(cfg, &req, &resp);
        return Ok(resp);
    }

    // List changed files
    let changed = run(&cfg.repo_root, &["diff", "--name-only"])?;
    let changed_files: Vec<String> = changed
        .lines()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    // ═══════════════════════════════════════════════════════════════
    // GATE 1: Locked paths
    // ═══════════════════════════════════════════════════════════════
    let mut blocked = vec![];
    for f in &changed_files {
        if cfg.is_locked(std::path::Path::new(f)) {
            blocked.push(f.clone());
        }
    }

    let locked_gate = if blocked.is_empty() {
        GateResult { ran: true, passed: true, detail: None }
    } else {
        GateResult { ran: true, passed: false, detail: Some(format!("Blocked: {}", blocked.join(", "))) }
    };

    if !locked_gate.passed {
        rollback_branch(cfg, &current_branch, &branch);
        let resp = PatchApplyResponse {
            ok: false,
            branch: None,
            merged: false,
            changed_files,
            blocked_files: blocked,
            gate_results: GateResults { locked_paths: locked_gate, ..Default::default() },
            error: Some("Locked paths modified. Patch rejected.".to_string()),
        };
        update_system_status(cfg, &req, &resp);
        return Ok(resp);
    }

    // Commit on branch (needed for merge later)
    run(&cfg.repo_root, &["add", "-A"])?;
    let msg = format!(
        "ACC: {} ({})\n\nProvider: {}\nFiles: {}",
        req.task_id,
        safe_reason,
        req.provider,
        changed_files.join(", ")
    );
    run(&cfg.repo_root, &["commit", "-m", &msg])?;

    // ═══════════════════════════════════════════════════════════════
    // GATE 2: Flutter analyze (runs on the branch with changes committed)
    // ═══════════════════════════════════════════════════════════════
    let flutter_gate = run_flutter_analyze_gate(cfg);

    if flutter_gate.ran && !flutter_gate.passed {
        tracing::warn!("Flutter analyze gate FAILED — rolling back");
        rollback_branch(cfg, &current_branch, &branch);
        let resp = PatchApplyResponse {
            ok: false,
            branch: None,
            merged: false,
            changed_files,
            blocked_files: vec![],
            gate_results: GateResults { locked_paths: locked_gate, flutter_analyze: flutter_gate },
            error: Some("Flutter analyze gate FAILED. Patch rejected.".to_string()),
        };
        update_system_status(cfg, &req, &resp);
        return Ok(resp);
    }

    // ═══════════════════════════════════════════════════════════════
    // ALL GATES PASSED → Merge into main branch
    // ═══════════════════════════════════════════════════════════════
    tracing::info!(branch=%branch, target=%current_branch, "All gates passed — merging");

    // Switch to main
    run(&cfg.repo_root, &["checkout", &current_branch])?;

    // Merge the branch
    let merge_result = run(&cfg.repo_root, &["merge", "--no-ff", &branch, "-m", &format!("ACC: {} ({})", req.task_id, safe_reason)]);

    let merged = match merge_result {
        Ok(_) => {
            // Delete the feature branch after successful merge
            let _ = run(&cfg.repo_root, &["branch", "-d", &branch]);
            tracing::info!(task_id=%req.task_id, "Patch merged into {current_branch} successfully");
            true
        }
        Err(e) => {
            // Merge failed — abort and keep branch for manual inspection
            let _ = run(&cfg.repo_root, &["merge", "--abort"]);
            tracing::error!(error=%e, "Merge failed — branch {branch} preserved for manual resolution");
            false
        }
    };

    let resp = PatchApplyResponse {
        ok: true,
        branch: if merged { None } else { Some(branch) },
        merged,
        changed_files,
        blocked_files: vec![],
        gate_results: GateResults { locked_paths: locked_gate, flutter_analyze: flutter_gate },
        error: if merged { None } else { Some("Merge failed — branch preserved".into()) },
    };

    update_system_status(cfg, &req, &resp);

    Ok(resp)
}

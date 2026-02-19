use crate::config::AccConfig;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    collections::BTreeSet,
    fs,
    path::Path,
};

#[derive(Debug, Clone, Deserialize)]
pub struct DiffpackPokeRequest {
    pub reason: Option<String>,
    pub changed_files: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct DiffpackPokeResponse {
    pub ok: bool,
    pub written_to: String,
    pub archived: bool,
    pub count: usize,
}

fn ensure_parent_dir(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("create_dir_all({parent:?}) failed: {e}"))?;
    }
    Ok(())
}

fn ensure_dir(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path).map_err(|e| format!("create_dir_all({path:?}) failed: {e}"))?;
    Ok(())
}

pub fn write_diffpack(cfg: &AccConfig, changed_files: &BTreeSet<String>, reason: &str) -> Result<(String, bool), String> {
    ensure_parent_dir(&cfg.diffpack_path)?;
    ensure_dir(&cfg.history_dir)?;

    let ts = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .map_err(|e| e.to_string())?;

    let body = json!({
        "task_id": null,
        "snapshot_id": null,
        "timestamp": ts,
        "provider": null,
        "reason": reason,
        "changed_files": changed_files.iter().collect::<Vec<_>>(),
        "patch": "",
        "hash_before": null,
        "hash_after": null,
        "gate_results": null,
        "review_result": null
    });

    let out = serde_json::to_string_pretty(&body).map_err(|e| e.to_string())?;
    fs::write(&cfg.diffpack_path, out).map_err(|e| format!("write({:?}) failed: {e}", cfg.diffpack_path))?;

    let safe_ts = ts.replace(':', "-");
    let hist = cfg.history_dir.join(format!("diffpack_{safe_ts}.json"));
    let mut archived = false;
    if fs::write(hist, serde_json::to_string_pretty(&body).unwrap()).is_ok() {
        archived = true;
    }

    Ok((ts, archived))
}

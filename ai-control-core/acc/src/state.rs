use serde_json::Value;
use std::{fs, path::Path};

pub fn read_json(path: &Path) -> Result<Value, String> {
    let raw = fs::read_to_string(path).map_err(|e| format!("Failed reading {path:?}: {e}"))?;
    serde_json::from_str(&raw).map_err(|e| format!("Invalid JSON in {path:?}: {e}"))
}

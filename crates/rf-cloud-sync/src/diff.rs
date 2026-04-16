//! T7.1: Structural diff between two project snapshots.
//!
//! Computes JSON path-based diffs. Each diff entry describes
//! one changed leaf value with its JSON path (dot notation).

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Operation performed on a value
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum DiffOp {
    /// New value was added at this path
    Add { value: Value },
    /// Value was removed from this path
    Remove { old_value: Value },
    /// Value was modified at this path
    Modify { from: Value, to: Value },
}

/// Single diff entry: path + operation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiffEntry {
    /// JSON path to the changed value (dot notation, arrays use index)
    /// e.g. "events.0.duration_ms", "config.rtp"
    pub path: String,
    /// What changed
    pub op: DiffOp,
}

/// Complete diff between two project snapshots
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectDiff {
    /// Source snapshot ID
    pub from_id: String,
    /// Target snapshot ID
    pub to_id: String,
    /// All changes from `from` to `to`
    pub changes: Vec<DiffEntry>,
    /// True if the projects are identical
    pub is_identical: bool,
    /// Number of additions
    pub additions: usize,
    /// Number of removals
    pub removals: usize,
    /// Number of modifications
    pub modifications: usize,
}

impl ProjectDiff {
    /// Compute the diff between two JSON project strings.
    ///
    /// Returns a `ProjectDiff` describing all leaf-level changes.
    pub fn compute(from_id: &str, from_json: &str, to_id: &str, to_json: &str) -> Self {
        let from_val: Value = serde_json::from_str(from_json).unwrap_or(Value::Null);
        let to_val: Value = serde_json::from_str(to_json).unwrap_or(Value::Null);

        let mut changes = Vec::new();
        diff_values("", &from_val, &to_val, &mut changes);

        let additions = changes.iter().filter(|e| matches!(e.op, DiffOp::Add { .. })).count();
        let removals = changes.iter().filter(|e| matches!(e.op, DiffOp::Remove { .. })).count();
        let modifications = changes.iter().filter(|e| matches!(e.op, DiffOp::Modify { .. })).count();
        let is_identical = changes.is_empty();

        Self {
            from_id: from_id.to_string(),
            to_id: to_id.to_string(),
            changes,
            is_identical,
            additions,
            removals,
            modifications,
        }
    }

    /// Summary line for display
    pub fn summary(&self) -> String {
        if self.is_identical {
            "No changes.".to_string()
        } else {
            format!(
                "+{} additions, -{} removals, ~{} modifications ({} total)",
                self.additions, self.removals, self.modifications,
                self.changes.len()
            )
        }
    }
}

/// Recursively diff two JSON values, collecting DiffEntry records.
fn diff_values(path: &str, from: &Value, to: &Value, out: &mut Vec<DiffEntry>) {
    match (from, to) {
        // Both objects: recurse on keys
        (Value::Object(f_map), Value::Object(t_map)) => {
            for key in f_map.keys() {
                let child_path = child_path(path, key);
                match t_map.get(key) {
                    Some(to_child) => diff_values(&child_path, f_map.get(key).unwrap(), to_child, out),
                    None => out.push(DiffEntry {
                        path: child_path,
                        op: DiffOp::Remove { old_value: f_map[key].clone() },
                    }),
                }
            }
            for key in t_map.keys() {
                if !f_map.contains_key(key) {
                    out.push(DiffEntry {
                        path: child_path(path, key),
                        op: DiffOp::Add { value: t_map[key].clone() },
                    });
                }
            }
        }
        // Both arrays: diff by index
        (Value::Array(f_arr), Value::Array(t_arr)) => {
            let max_len = f_arr.len().max(t_arr.len());
            for i in 0..max_len {
                let child = child_path(path, &i.to_string());
                match (f_arr.get(i), t_arr.get(i)) {
                    (Some(fv), Some(tv)) => diff_values(&child, fv, tv, out),
                    (Some(fv), None) => out.push(DiffEntry {
                        path: child,
                        op: DiffOp::Remove { old_value: fv.clone() },
                    }),
                    (None, Some(tv)) => out.push(DiffEntry {
                        path: child,
                        op: DiffOp::Add { value: tv.clone() },
                    }),
                    (None, None) => {}
                }
            }
        }
        // Leaves: compare directly
        (fv, tv) => {
            if fv != tv {
                out.push(DiffEntry {
                    path: path.to_string(),
                    op: DiffOp::Modify { from: fv.clone(), to: tv.clone() },
                });
            }
        }
    }
}

fn child_path(parent: &str, key: &str) -> String {
    if parent.is_empty() {
        key.to_string()
    } else {
        format!("{parent}.{key}")
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identical_json_no_changes() {
        let json = r#"{"rtp":0.96,"events":[]}"#;
        let diff = ProjectDiff::compute("a", json, "b", json);
        assert!(diff.is_identical);
        assert_eq!(diff.changes.len(), 0);
    }

    #[test]
    fn test_modified_leaf_value() {
        let from = r#"{"rtp":0.96}"#;
        let to = r#"{"rtp":0.97}"#;
        let diff = ProjectDiff::compute("a", from, "b", to);
        assert!(!diff.is_identical);
        assert_eq!(diff.modifications, 1);
        assert_eq!(diff.changes[0].path, "rtp");
    }

    #[test]
    fn test_added_key() {
        let from = r#"{"rtp":0.96}"#;
        let to = r#"{"rtp":0.96,"volatility":"high"}"#;
        let diff = ProjectDiff::compute("a", from, "b", to);
        assert_eq!(diff.additions, 1);
        let added = &diff.changes[0];
        assert_eq!(added.path, "volatility");
        assert!(matches!(&added.op, DiffOp::Add { value } if value == "high"));
    }

    #[test]
    fn test_removed_key() {
        let from = r#"{"rtp":0.96,"volatility":"high"}"#;
        let to = r#"{"rtp":0.96}"#;
        let diff = ProjectDiff::compute("a", from, "b", to);
        assert_eq!(diff.removals, 1);
    }

    #[test]
    fn test_nested_modification() {
        let from = r#"{"config":{"rtp":0.96}}"#;
        let to = r#"{"config":{"rtp":0.97}}"#;
        let diff = ProjectDiff::compute("a", from, "b", to);
        assert_eq!(diff.changes[0].path, "config.rtp");
    }

    #[test]
    fn test_array_element_modified() {
        let from = r#"{"events":[{"name":"SPIN_START","dur":150}]}"#;
        let to = r#"{"events":[{"name":"SPIN_START","dur":200}]}"#;
        let diff = ProjectDiff::compute("a", from, "b", to);
        assert_eq!(diff.modifications, 1);
        assert_eq!(diff.changes[0].path, "events.0.dur");
    }

    #[test]
    fn test_array_element_added() {
        let from = r#"{"events":[]}"#;
        let to = r#"{"events":[{"name":"WIN_5"}]}"#;
        let diff = ProjectDiff::compute("a", from, "b", to);
        assert_eq!(diff.additions, 1);
    }

    #[test]
    fn test_summary_non_identical() {
        let from = r#"{"a":1}"#;
        let to = r#"{"a":2,"b":3}"#;
        let diff = ProjectDiff::compute("x", from, "y", to);
        let summary = diff.summary();
        assert!(summary.contains('+'));
    }
}

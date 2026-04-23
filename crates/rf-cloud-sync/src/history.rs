//! T7.1: Project history — ordered chain of snapshots.

use serde::{Deserialize, Serialize};
use crate::snapshot::ProjectSnapshot;

/// Lightweight summary of a snapshot (no project_data payload)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotSummary {
    pub id: String,
    pub short_id: String,
    pub author: String,
    pub message: String,
    pub timestamp: String,
    pub parent_id: Option<String>,
    pub data_size_bytes: usize,
}

impl From<&ProjectSnapshot> for SnapshotSummary {
    fn from(s: &ProjectSnapshot) -> Self {
        Self {
            id: s.id.clone(),
            short_id: s.short_id.clone(),
            author: s.author.clone(),
            message: s.message.clone(),
            timestamp: s.timestamp.clone(),
            parent_id: s.parent_id.clone(),
            data_size_bytes: s.data_size_bytes,
        }
    }
}

/// Ordered history of project snapshots.
///
/// Snapshots are stored in insertion order. The `HEAD` is the most recent.
/// The chain is maintained as a linked list via parent_id references.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectHistory {
    /// Game/project identifier
    pub project_id: String,
    /// Snapshots in insertion order (oldest first)
    snapshots: Vec<ProjectSnapshot>,
    /// Currently checked-out snapshot ID
    pub head_id: Option<String>,
}

impl ProjectHistory {
    /// Create a new empty history for a project.
    pub fn new(project_id: impl Into<String>) -> Self {
        Self {
            project_id: project_id.into(),
            snapshots: Vec::new(),
            head_id: None,
        }
    }

    /// Append a snapshot to the history.
    /// Updates HEAD to this snapshot.
    pub fn push(&mut self, snapshot: ProjectSnapshot) {
        self.head_id = Some(snapshot.id.clone());
        self.snapshots.push(snapshot);
    }

    /// Number of snapshots in history.
    pub fn len(&self) -> usize {
        self.snapshots.len()
    }

    pub fn is_empty(&self) -> bool {
        self.snapshots.is_empty()
    }

    /// Get the current HEAD snapshot.
    pub fn head(&self) -> Option<&ProjectSnapshot> {
        self.head_id.as_ref().and_then(|id| self.get(id))
    }

    /// Look up a snapshot by ID (full or short prefix).
    pub fn get(&self, id: &str) -> Option<&ProjectSnapshot> {
        self.snapshots.iter().find(|s| s.id == id || s.short_id == id)
    }

    /// Get all snapshot summaries, most recent first.
    pub fn log(&self) -> Vec<SnapshotSummary> {
        self.snapshots.iter().rev().map(SnapshotSummary::from).collect()
    }

    /// Get the linear ancestry chain from HEAD back to root.
    ///
    /// Returns snapshots from HEAD → root (newest first).
    pub fn ancestry(&self) -> Vec<&ProjectSnapshot> {
        let mut chain = Vec::new();
        let mut current_id = self.head_id.clone();
        while let Some(id) = current_id {
            match self.get(&id) {
                Some(s) => {
                    current_id = s.parent_id.clone();
                    chain.push(s);
                }
                None => break,
            }
        }
        chain
    }

    /// Check out a specific snapshot (sets HEAD without discarding others).
    /// Returns error message if ID not found.
    pub fn checkout(&mut self, id: &str) -> Result<(), String> {
        if self.get(id).is_some() {
            self.head_id = Some(
                self.get(id).unwrap().id.clone()
            );
            Ok(())
        } else {
            Err(format!("Snapshot '{id}' not found in history."))
        }
    }

    /// Verify integrity of the entire history chain.
    /// Returns list of corrupt snapshot IDs.
    pub fn verify_all(&self) -> Vec<String> {
        self.snapshots.iter()
            .filter(|s| !s.verify_integrity())
            .map(|s| s.id.clone())
            .collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::snapshot::ProjectSnapshot;

    fn snap(msg: &str, parent: Option<&str>) -> ProjectSnapshot {
        ProjectSnapshot::create(
            format!(r#"{{"msg":"{}"}}"#, msg),
            "dev",
            msg,
            "2026-01-01T00:00:00Z",
            parent.map(|s| s.to_string()),
        )
    }

    #[test]
    fn test_push_and_head() {
        let mut hist = ProjectHistory::new("game_x");
        let s = snap("init", None);
        let id = s.id.clone();
        hist.push(s);
        assert_eq!(hist.head_id.as_deref(), Some(id.as_str()));
        assert_eq!(hist.len(), 1);
    }

    #[test]
    fn test_get_by_short_id() {
        let mut hist = ProjectHistory::new("game_x");
        let s = snap("init", None);
        let short = s.short_id.clone();
        hist.push(s);
        assert!(hist.get(&short).is_some());
    }

    #[test]
    fn test_log_newest_first() {
        let mut hist = ProjectHistory::new("game_x");
        let s1 = snap("first", None);
        let s2 = snap("second", Some(&s1.id.clone()));
        hist.push(s1);
        hist.push(s2.clone());
        let log = hist.log();
        assert_eq!(log[0].message, "second");
        assert_eq!(log[1].message, "first");
    }

    #[test]
    fn test_ancestry_chain() {
        let mut hist = ProjectHistory::new("game_x");
        let s1 = snap("root", None);
        let s2 = snap("child", Some(&s1.id.clone()));
        let s3 = snap("grandchild", Some(&s2.id.clone()));
        hist.push(s1);
        hist.push(s2);
        hist.push(s3);
        let chain = hist.ancestry();
        assert_eq!(chain.len(), 3);
        assert_eq!(chain[0].message, "grandchild");
        assert_eq!(chain[2].message, "root");
    }

    #[test]
    fn test_checkout_valid_id() {
        let mut hist = ProjectHistory::new("game_x");
        let s1 = snap("root", None);
        let id1 = s1.id.clone();
        let s2 = snap("child", Some(&s1.id.clone()));
        hist.push(s1);
        hist.push(s2);
        assert!(hist.checkout(&id1).is_ok());
        assert_eq!(hist.head_id.as_deref(), Some(id1.as_str()));
    }

    #[test]
    fn test_checkout_invalid_id_returns_err() {
        let mut hist = ProjectHistory::new("game_x");
        assert!(hist.checkout("nonexistent").is_err());
    }

    #[test]
    fn test_verify_all_clean() {
        let mut hist = ProjectHistory::new("game_x");
        hist.push(snap("a", None));
        hist.push(snap("b", None));
        assert!(hist.verify_all().is_empty());
    }
}

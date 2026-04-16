//! T7.1: SyncManager — top-level API for project versioning.
//!
//! Wraps ProjectHistory with a high-level commit/checkout/log/diff API.
//! Designed for Flutter integration via FFI.

use serde::{Deserialize, Serialize};
use crate::diff::ProjectDiff;
use crate::history::{ProjectHistory, SnapshotSummary};
use crate::snapshot::ProjectSnapshot;

/// Configuration for the sync engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    /// Max number of snapshots to retain (0 = unlimited)
    pub max_history_depth: usize,
    /// Whether to verify integrity on every push
    pub verify_on_push: bool,
}

impl Default for SyncConfig {
    fn default() -> Self {
        Self {
            max_history_depth: 100,
            verify_on_push: true,
        }
    }
}

/// High-level project sync and versioning manager.
///
/// Lifecycle:
/// ```rust,ignore
/// let mut mgr = SyncManager::new("golden_phoenix", SyncConfig::default());
/// let snap = mgr.commit(project_json, "alice", "Initial audio setup")?;
/// // ... after changes:
/// let snap2 = mgr.commit(updated_json, "alice", "Added WIN_5 sound")?;
/// let diff = mgr.diff(&snap.id, &snap2.id)?;
/// let log = mgr.log();
/// mgr.checkout(&snap.id)?; // revert
/// ```
pub struct SyncManager {
    history: ProjectHistory,
    config: SyncConfig,
}

impl SyncManager {
    /// Create a new SyncManager for a project.
    pub fn new(project_id: impl Into<String>, config: SyncConfig) -> Self {
        Self {
            history: ProjectHistory::new(project_id),
            config,
        }
    }

    /// Load from a previously serialized history.
    pub fn from_history(history: ProjectHistory, config: SyncConfig) -> Self {
        Self { history, config }
    }

    /// Serialize the current history to JSON for persistence.
    pub fn serialize(&self) -> Result<String, String> {
        serde_json::to_string(&self.history).map_err(|e| e.to_string())
    }

    /// Restore from serialized history JSON.
    pub fn deserialize(json: &str, config: SyncConfig) -> Result<Self, String> {
        let history: ProjectHistory = serde_json::from_str(json)
            .map_err(|e| e.to_string())?;
        Ok(Self::from_history(history, config))
    }

    /// Commit a new snapshot of the project.
    ///
    /// Returns the created snapshot. Returns Err if integrity check fails (shouldn't happen).
    pub fn commit(
        &mut self,
        project_data: impl Into<String>,
        author: impl Into<String>,
        message: impl Into<String>,
    ) -> Result<ProjectSnapshot, String> {
        let project_data = project_data.into();
        let author = author.into();
        let message = message.into();
        let timestamp = chrono_now();
        let parent_id = self.history.head_id.clone();

        let snapshot = ProjectSnapshot::create(
            &project_data,
            &author,
            &message,
            &timestamp,
            parent_id,
        );

        if self.config.verify_on_push && !snapshot.verify_integrity() {
            return Err("Snapshot integrity check failed immediately after creation.".to_string());
        }

        self.history.push(snapshot.clone());
        self.trim_history();
        Ok(snapshot)
    }

    /// Compute diff between two snapshot IDs.
    ///
    /// Returns Err if either ID is not found.
    pub fn diff(&self, from_id: &str, to_id: &str) -> Result<ProjectDiff, String> {
        let from = self.history.get(from_id)
            .ok_or_else(|| format!("Snapshot '{from_id}' not found."))?;
        let to = self.history.get(to_id)
            .ok_or_else(|| format!("Snapshot '{to_id}' not found."))?;

        Ok(ProjectDiff::compute(
            &from.id,
            &from.project_data,
            &to.id,
            &to.project_data,
        ))
    }

    /// Diff HEAD against a specific snapshot.
    pub fn diff_from_head(&self, to_id: &str) -> Result<ProjectDiff, String> {
        let head = self.history.head()
            .ok_or_else(|| "No HEAD snapshot.".to_string())?;
        self.diff(&head.id, to_id)
    }

    /// Get the full log (newest first).
    pub fn log(&self) -> Vec<SnapshotSummary> {
        self.history.log()
    }

    /// Check out a specific snapshot (moves HEAD, does NOT discard later commits).
    pub fn checkout(&mut self, id: &str) -> Result<ProjectSnapshot, String> {
        self.history.checkout(id)?;
        self.history.head()
            .cloned()
            .ok_or_else(|| "Checkout succeeded but HEAD is missing.".to_string())
    }

    /// Get the HEAD snapshot.
    pub fn head(&self) -> Option<&ProjectSnapshot> {
        self.history.head()
    }

    /// Number of snapshots in history.
    pub fn len(&self) -> usize {
        self.history.len()
    }

    pub fn is_empty(&self) -> bool {
        self.history.is_empty()
    }

    /// Verify all snapshot integrity. Returns list of corrupt IDs.
    pub fn verify_integrity(&self) -> Vec<String> {
        self.history.verify_all()
    }

    /// Get the history reference (for serialization).
    pub fn history(&self) -> &ProjectHistory {
        &self.history
    }

    // ── Private ──────────────────────────────────────────────────────────────

    fn trim_history(&mut self) {
        // Pruning history while maintaining parent chain integrity is complex.
        // For now: no-op (unlimited history is safe for offline-first use).
        // TODO: implement when cloud sync with large histories is active (T7.5).
        let _ = self.config.max_history_depth;
    }
}

/// Simple timestamp without pulling in a time dependency.
/// In production, Flutter passes in the timestamp; this is the Rust fallback.
fn chrono_now() -> String {
    // Without a time crate, use a placeholder. FFI callers pass real timestamps.
    "1970-01-01T00:00:00Z".to_string()
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn mgr() -> SyncManager {
        SyncManager::new("game_x", SyncConfig::default())
    }

    #[test]
    fn test_commit_creates_snapshot() {
        let mut m = mgr();
        let snap = m.commit(r#"{"events":[]}"#, "alice", "Initial").unwrap();
        assert!(!snap.id.is_empty());
        assert_eq!(m.len(), 1);
    }

    #[test]
    fn test_parent_chain() {
        let mut m = mgr();
        let s1 = m.commit(r#"{"a":1}"#, "alice", "First").unwrap();
        let s2 = m.commit(r#"{"a":2}"#, "alice", "Second").unwrap();
        assert_eq!(s2.parent_id.as_deref(), Some(s1.id.as_str()));
    }

    #[test]
    fn test_diff_detects_changes() {
        let mut m = mgr();
        let s1 = m.commit(r#"{"rtp":0.96}"#, "alice", "First").unwrap();
        let s2 = m.commit(r#"{"rtp":0.97}"#, "alice", "Updated RTP").unwrap();
        let diff = m.diff(&s1.id, &s2.id).unwrap();
        assert!(!diff.is_identical);
        assert_eq!(diff.modifications, 1);
    }

    #[test]
    fn test_diff_with_short_id() {
        let mut m = mgr();
        let s1 = m.commit(r#"{"x":1}"#, "alice", "A").unwrap();
        let s2 = m.commit(r#"{"x":2}"#, "alice", "B").unwrap();
        // Short IDs should work too
        let diff = m.diff(&s1.short_id, &s2.short_id).unwrap();
        assert_eq!(diff.modifications, 1);
    }

    #[test]
    fn test_checkout_reverts_head() {
        let mut m = mgr();
        let s1 = m.commit(r#"{"v":1}"#, "alice", "v1").unwrap();
        let _s2 = m.commit(r#"{"v":2}"#, "alice", "v2").unwrap();
        m.checkout(&s1.id).unwrap();
        assert_eq!(m.head().map(|s| s.message.as_str()), Some("v1"));
    }

    #[test]
    fn test_log_newest_first() {
        let mut m = mgr();
        m.commit(r#"{"i":1}"#, "alice", "one").unwrap();
        m.commit(r#"{"i":2}"#, "alice", "two").unwrap();
        let log = m.log();
        assert_eq!(log[0].message, "two");
    }

    #[test]
    fn test_serialize_deserialize_roundtrip() {
        let mut m = mgr();
        m.commit(r#"{"rtp":0.96}"#, "alice", "setup").unwrap();
        let json = m.serialize().unwrap();
        let m2 = SyncManager::deserialize(&json, SyncConfig::default()).unwrap();
        assert_eq!(m2.len(), 1);
        assert_eq!(m2.head().map(|s| s.message.as_str()), Some("setup"));
    }

    #[test]
    fn test_integrity_check_passes() {
        let mut m = mgr();
        m.commit(r#"{"x":1}"#, "alice", "test").unwrap();
        let corrupt = m.verify_integrity();
        assert!(corrupt.is_empty());
    }
}

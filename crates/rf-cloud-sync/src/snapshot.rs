//! T7.1: Project snapshot — immutable, content-addressed project state.

use sha2::{Digest, Sha256};
use serde::{Deserialize, Serialize};

/// An immutable, content-addressed snapshot of a FluxForge project.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectSnapshot {
    /// SHA-256 of (parent_id + author + timestamp + project_data)
    pub id: String,
    /// Full project JSON payload (serialized AudioProject)
    pub project_data: String,
    /// Author/user who created this snapshot
    pub author: String,
    /// Human-readable commit message
    pub message: String,
    /// ISO 8601 UTC timestamp
    pub timestamp: String,
    /// Parent snapshot ID (None = root commit)
    pub parent_id: Option<String>,
    /// Short display ID (first 8 chars of id)
    pub short_id: String,
    /// Size of project_data in bytes
    pub data_size_bytes: usize,
}

impl ProjectSnapshot {
    /// Create a new snapshot from project data.
    ///
    /// The `id` is deterministic: SHA-256 of concatenated inputs.
    /// If `parent_id` is None, this is treated as "0000000000000000" for hashing.
    pub fn create(
        project_data: impl Into<String>,
        author: impl Into<String>,
        message: impl Into<String>,
        timestamp: impl Into<String>,
        parent_id: Option<String>,
    ) -> Self {
        let project_data = project_data.into();
        let author = author.into();
        let message = message.into();
        let timestamp = timestamp.into();
        let parent_str = parent_id.as_deref().unwrap_or("0000000000000000");

        let mut hasher = Sha256::new();
        hasher.update(parent_str.as_bytes());
        hasher.update(b"|");
        hasher.update(author.as_bytes());
        hasher.update(b"|");
        hasher.update(timestamp.as_bytes());
        hasher.update(b"|");
        hasher.update(message.as_bytes());
        hasher.update(b"|");
        hasher.update(project_data.as_bytes());
        let id_bytes = hasher.finalize();
        let id = hex::encode(id_bytes);
        let short_id = id[..8].to_string();
        let data_size_bytes = project_data.len();

        Self {
            id,
            project_data,
            author,
            message,
            timestamp,
            parent_id,
            short_id,
            data_size_bytes,
        }
    }

    /// Verify that this snapshot's ID matches its content.
    pub fn verify_integrity(&self) -> bool {
        let parent_str = self.parent_id.as_deref().unwrap_or("0000000000000000");
        let mut hasher = Sha256::new();
        hasher.update(parent_str.as_bytes());
        hasher.update(b"|");
        hasher.update(self.author.as_bytes());
        hasher.update(b"|");
        hasher.update(self.timestamp.as_bytes());
        hasher.update(b"|");
        hasher.update(self.message.as_bytes());
        hasher.update(b"|");
        hasher.update(self.project_data.as_bytes());
        let expected_id = hex::encode(hasher.finalize());
        self.id == expected_id
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn snap(msg: &str, parent: Option<&str>) -> ProjectSnapshot {
        ProjectSnapshot::create(
            r#"{"events":[]}"#,
            "test_user",
            msg,
            "2026-04-16T12:00:00Z",
            parent.map(|s| s.to_string()),
        )
    }

    #[test]
    fn test_snapshot_id_is_deterministic() {
        let s1 = snap("initial", None);
        let s2 = snap("initial", None);
        assert_eq!(s1.id, s2.id);
    }

    #[test]
    fn test_snapshot_different_messages_produce_different_ids() {
        let s1 = snap("initial", None);
        let s2 = snap("update", None);
        assert_ne!(s1.id, s2.id);
    }

    #[test]
    fn test_parent_chain_produces_different_ids() {
        let root = snap("root", None);
        let child = snap("root", Some(&root.id));
        assert_ne!(root.id, child.id);
    }

    #[test]
    fn test_short_id_is_8_chars() {
        let s = snap("x", None);
        assert_eq!(s.short_id.len(), 8);
        assert_eq!(&s.id[..8], s.short_id);
    }

    #[test]
    fn test_integrity_verification() {
        let s = snap("test", None);
        assert!(s.verify_integrity());
    }

    #[test]
    fn test_tampered_data_fails_integrity() {
        let mut s = snap("test", None);
        s.project_data = r#"{"events":[{"name":"TAMPERED"}]}"#.to_string();
        assert!(!s.verify_integrity());
    }
}

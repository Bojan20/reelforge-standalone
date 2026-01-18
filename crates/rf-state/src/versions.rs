//! Project Versioning System
//!
//! Provides manual snapshot versioning:
//! - Named project versions (like "Before mixing", "Final v1")
//! - Version comparison
//! - Restore from version
//! - Version history with descriptions
//!
//! Different from autosave: these are intentional, named snapshots

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

// ============ Version Metadata ============

/// Project version metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectVersion {
    /// Unique version ID
    pub id: String,
    /// Version number (auto-incremented)
    pub number: u32,
    /// User-provided name
    pub name: String,
    /// Description of changes
    pub description: String,
    /// Creation timestamp (Unix ms)
    pub created_at: u64,
    /// File size in bytes
    pub size: u64,
    /// Parent project name
    pub project_name: String,
    /// Checksum for integrity
    pub checksum: u32,
    /// Tags for organization
    pub tags: Vec<String>,
    /// Is marked as milestone (important version)
    pub is_milestone: bool,
}

impl ProjectVersion {
    pub fn new(number: u32, name: &str, project_name: &str) -> Self {
        Self {
            id: format!("v{}-{}", number, current_timestamp()),
            number,
            name: name.to_string(),
            description: String::new(),
            created_at: current_timestamp(),
            size: 0,
            project_name: project_name.to_string(),
            checksum: 0,
            tags: Vec::new(),
            is_milestone: false,
        }
    }

    /// Age in seconds
    pub fn age_secs(&self) -> u64 {
        let now = current_timestamp();
        (now.saturating_sub(self.created_at)) / 1000
    }

    /// Format creation time
    pub fn created_at_formatted(&self) -> String {
        let secs = self.created_at / 1000;
        // Simple formatting - production code would use chrono
        format!("{}s ago", (current_timestamp() / 1000).saturating_sub(secs))
    }
}

// ============ Version Manager ============

/// Manages project versions
pub struct VersionManager {
    /// Project name
    project_name: RwLock<String>,
    /// Version storage directory
    versions_dir: RwLock<PathBuf>,
    /// Cached version list
    versions: RwLock<Vec<ProjectVersion>>,
    /// Next version number
    next_number: RwLock<u32>,
    /// Maximum versions to keep (0 = unlimited)
    max_versions: RwLock<u32>,
}

impl VersionManager {
    pub fn new(project_name: &str, base_dir: &Path) -> Self {
        let versions_dir = base_dir.join("versions");

        let manager = Self {
            project_name: RwLock::new(project_name.to_string()),
            versions_dir: RwLock::new(versions_dir),
            versions: RwLock::new(Vec::new()),
            next_number: RwLock::new(1),
            max_versions: RwLock::new(50), // Default limit
        };

        // Load existing versions
        manager.refresh_versions();
        manager
    }

    /// Set project name
    pub fn set_project_name(&self, name: &str) {
        *self.project_name.write() = name.to_string();
    }

    /// Set versions directory
    pub fn set_versions_dir(&self, dir: &Path) {
        *self.versions_dir.write() = dir.to_path_buf();
        self.refresh_versions();
    }

    /// Set maximum versions to keep
    pub fn set_max_versions(&self, max: u32) {
        *self.max_versions.write() = max;
    }

    /// Create a new version
    pub fn create_version<T: Serialize>(
        &self,
        name: &str,
        description: &str,
        data: &T,
    ) -> Result<ProjectVersion, VersionError> {
        let dir = self.versions_dir.read().clone();
        std::fs::create_dir_all(&dir)?;

        let number = {
            let mut next = self.next_number.write();
            let n = *next;
            *next += 1;
            n
        };

        let project_name = self.project_name.read().clone();
        let mut version = ProjectVersion::new(number, name, &project_name);
        version.description = description.to_string();

        // Serialize data
        let json = serde_json::to_string_pretty(data)?;
        version.checksum = crc32_hash(json.as_bytes());
        version.size = json.len() as u64;

        // Save version file
        let filename = format!("{}.json", version.id);
        let path = dir.join(&filename);
        std::fs::write(&path, &json)?;

        // Save metadata
        let meta_path = dir.join(format!("{}.meta.json", version.id));
        let meta_json = serde_json::to_string_pretty(&version)?;
        std::fs::write(&meta_path, meta_json)?;

        // Update cache
        self.versions.write().push(version.clone());

        // Cleanup old versions if needed
        self.cleanup_old_versions()?;

        log::info!("Created version {}: {}", number, name);
        Ok(version)
    }

    /// Mark version as milestone
    pub fn set_milestone(&self, version_id: &str, is_milestone: bool) -> Result<(), VersionError> {
        let dir = self.versions_dir.read().clone();
        let meta_path = dir.join(format!("{}.meta.json", version_id));

        if !meta_path.exists() {
            return Err(VersionError::NotFound(version_id.to_string()));
        }

        // Load and update metadata
        let json = std::fs::read_to_string(&meta_path)?;
        let mut version: ProjectVersion = serde_json::from_str(&json)?;
        version.is_milestone = is_milestone;

        // Save updated metadata
        let updated = serde_json::to_string_pretty(&version)?;
        std::fs::write(&meta_path, updated)?;

        // Update cache
        if let Some(v) = self
            .versions
            .write()
            .iter_mut()
            .find(|v| v.id == version_id)
        {
            v.is_milestone = is_milestone;
        }

        Ok(())
    }

    /// Add tag to version
    pub fn add_tag(&self, version_id: &str, tag: &str) -> Result<(), VersionError> {
        let dir = self.versions_dir.read().clone();
        let meta_path = dir.join(format!("{}.meta.json", version_id));

        if !meta_path.exists() {
            return Err(VersionError::NotFound(version_id.to_string()));
        }

        let json = std::fs::read_to_string(&meta_path)?;
        let mut version: ProjectVersion = serde_json::from_str(&json)?;

        if !version.tags.contains(&tag.to_string()) {
            version.tags.push(tag.to_string());
        }

        let updated = serde_json::to_string_pretty(&version)?;
        std::fs::write(&meta_path, updated)?;

        // Update cache
        if let Some(v) = self
            .versions
            .write()
            .iter_mut()
            .find(|v| v.id == version_id)
            && !v.tags.contains(&tag.to_string()) {
                v.tags.push(tag.to_string());
            }

        Ok(())
    }

    /// Load version data
    pub fn load_version<T: for<'de> Deserialize<'de>>(
        &self,
        version_id: &str,
    ) -> Result<T, VersionError> {
        let dir = self.versions_dir.read().clone();
        let path = dir.join(format!("{}.json", version_id));

        if !path.exists() {
            return Err(VersionError::NotFound(version_id.to_string()));
        }

        let json = std::fs::read_to_string(&path)?;
        let data: T = serde_json::from_str(&json)?;
        Ok(data)
    }

    /// Delete a version
    pub fn delete_version(&self, version_id: &str) -> Result<(), VersionError> {
        let dir = self.versions_dir.read().clone();
        let data_path = dir.join(format!("{}.json", version_id));
        let meta_path = dir.join(format!("{}.meta.json", version_id));

        // Check if milestone - don't delete milestones without force
        if let Some(v) = self.versions.read().iter().find(|v| v.id == version_id)
            && v.is_milestone {
                return Err(VersionError::MilestoneProtected(version_id.to_string()));
            }

        if data_path.exists() {
            std::fs::remove_file(&data_path)?;
        }
        if meta_path.exists() {
            std::fs::remove_file(&meta_path)?;
        }

        // Update cache
        self.versions.write().retain(|v| v.id != version_id);

        log::info!("Deleted version: {}", version_id);
        Ok(())
    }

    /// Force delete version (even milestones)
    pub fn force_delete_version(&self, version_id: &str) -> Result<(), VersionError> {
        let dir = self.versions_dir.read().clone();
        let data_path = dir.join(format!("{}.json", version_id));
        let meta_path = dir.join(format!("{}.meta.json", version_id));

        if data_path.exists() {
            std::fs::remove_file(&data_path)?;
        }
        if meta_path.exists() {
            std::fs::remove_file(&meta_path)?;
        }

        self.versions.write().retain(|v| v.id != version_id);
        Ok(())
    }

    /// Get all versions (sorted by number descending)
    pub fn list_versions(&self) -> Vec<ProjectVersion> {
        let mut versions = self.versions.read().clone();
        versions.sort_by(|a, b| b.number.cmp(&a.number));
        versions
    }

    /// Get milestones only
    pub fn list_milestones(&self) -> Vec<ProjectVersion> {
        self.versions
            .read()
            .iter()
            .filter(|v| v.is_milestone)
            .cloned()
            .collect()
    }

    /// Search versions by tag
    pub fn search_by_tag(&self, tag: &str) -> Vec<ProjectVersion> {
        self.versions
            .read()
            .iter()
            .filter(|v| v.tags.iter().any(|t| t.contains(tag)))
            .cloned()
            .collect()
    }

    /// Get version by ID
    pub fn get_version(&self, version_id: &str) -> Option<ProjectVersion> {
        self.versions
            .read()
            .iter()
            .find(|v| v.id == version_id)
            .cloned()
    }

    /// Get latest version
    pub fn latest_version(&self) -> Option<ProjectVersion> {
        self.versions
            .read()
            .iter()
            .max_by_key(|v| v.number)
            .cloned()
    }

    /// Get version count
    pub fn version_count(&self) -> usize {
        self.versions.read().len()
    }

    /// Refresh versions from disk
    pub fn refresh_versions(&self) {
        let dir = self.versions_dir.read().clone();

        if !dir.exists() {
            return;
        }

        let mut versions = Vec::new();
        let mut max_number: u32 = 0;

        if let Ok(entries) = std::fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().map(|e| e == "meta") == Some(false)
                    && path
                        .file_name()
                        .map(|n| n.to_string_lossy().ends_with(".meta.json"))
                        .unwrap_or(false)
                    && let Ok(json) = std::fs::read_to_string(&path)
                        && let Ok(version) = serde_json::from_str::<ProjectVersion>(&json) {
                            max_number = max_number.max(version.number);
                            versions.push(version);
                        }
            }
        }

        *self.versions.write() = versions;
        *self.next_number.write() = max_number + 1;
    }

    /// Cleanup old versions (keep max_versions, always keep milestones)
    fn cleanup_old_versions(&self) -> Result<(), VersionError> {
        let max = *self.max_versions.read();
        if max == 0 {
            return Ok(()); // Unlimited
        }

        let mut versions = self.versions.read().clone();
        versions.sort_by(|a, b| b.number.cmp(&a.number)); // Newest first

        // Count non-milestone versions
        let non_milestones: Vec<_> = versions.iter().filter(|v| !v.is_milestone).collect();

        if non_milestones.len() > max as usize {
            // Delete oldest non-milestone versions
            let to_delete = non_milestones
                .iter()
                .skip(max as usize)
                .map(|v| v.id.clone())
                .collect::<Vec<_>>();

            for id in to_delete {
                self.force_delete_version(&id)?;
            }
        }

        Ok(())
    }

    /// Compare two versions (returns diff info)
    pub fn compare_versions(
        &self,
        version_a: &str,
        version_b: &str,
    ) -> Result<VersionDiff, VersionError> {
        let a = self
            .get_version(version_a)
            .ok_or_else(|| VersionError::NotFound(version_a.to_string()))?;
        let b = self
            .get_version(version_b)
            .ok_or_else(|| VersionError::NotFound(version_b.to_string()))?;

        Ok(VersionDiff {
            version_a: a.clone(),
            version_b: b.clone(),
            size_diff: b.size as i64 - a.size as i64,
            time_diff: b.created_at as i64 - a.created_at as i64,
            checksums_match: a.checksum == b.checksum,
        })
    }

    /// Export version to standalone file
    pub fn export_version(&self, version_id: &str, export_path: &Path) -> Result<(), VersionError> {
        let dir = self.versions_dir.read().clone();
        let source = dir.join(format!("{}.json", version_id));

        if !source.exists() {
            return Err(VersionError::NotFound(version_id.to_string()));
        }

        std::fs::copy(&source, export_path)?;
        Ok(())
    }

    /// Import version from external file
    pub fn import_version<T: Serialize + for<'de> Deserialize<'de>>(
        &self,
        import_path: &Path,
        name: &str,
    ) -> Result<ProjectVersion, VersionError> {
        let json = std::fs::read_to_string(import_path)?;
        let data: T = serde_json::from_str(&json)?;

        self.create_version(name, &format!("Imported from {:?}", import_path), &data)
    }
}

impl Default for VersionManager {
    fn default() -> Self {
        let default_dir = dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("FluxForge Studio")
            .join("Versions");

        Self::new("Untitled", &default_dir)
    }
}

// ============ Version Diff ============

/// Difference between two versions
#[derive(Debug, Clone)]
pub struct VersionDiff {
    pub version_a: ProjectVersion,
    pub version_b: ProjectVersion,
    pub size_diff: i64,
    pub time_diff: i64,
    pub checksums_match: bool,
}

// ============ Errors ============

#[derive(Debug, thiserror::Error)]
pub enum VersionError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialize(#[from] serde_json::Error),

    #[error("Version not found: {0}")]
    NotFound(String),

    #[error("Cannot delete milestone version: {0}. Use force_delete instead.")]
    MilestoneProtected(String),
}

// ============ Helpers ============

fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Simple CRC32 hash
fn crc32_hash(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFFFFFF;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xEDB88320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn test_version_creation() {
        let version = ProjectVersion::new(1, "Test Version", "TestProject");
        assert_eq!(version.number, 1);
        assert_eq!(version.name, "Test Version");
        assert!(version.id.starts_with("v1-"));
    }

    #[test]
    fn test_version_manager() {
        let temp_dir = std::env::temp_dir().join("rf_version_test");
        let _ = std::fs::create_dir_all(&temp_dir);

        let manager = VersionManager::new("TestProject", &temp_dir);

        // Create version
        let data = HashMap::from([("key".to_string(), "value".to_string())]);
        let version = manager.create_version("v1", "First version", &data);

        assert!(version.is_ok());
        let v = version.unwrap();
        assert_eq!(v.number, 1);
        assert_eq!(v.name, "v1");

        // List versions
        let versions = manager.list_versions();
        assert_eq!(versions.len(), 1);

        // Load version
        let loaded: HashMap<String, String> = manager.load_version(&v.id).unwrap();
        assert_eq!(loaded.get("key"), Some(&"value".to_string()));

        // Cleanup
        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_milestone_protection() {
        let temp_dir = std::env::temp_dir().join("rf_milestone_test");
        let _ = std::fs::create_dir_all(&temp_dir);

        let manager = VersionManager::new("TestProject", &temp_dir);

        let data = HashMap::<String, String>::new();
        let version = manager.create_version("v1", "Milestone", &data).unwrap();

        // Set as milestone
        manager.set_milestone(&version.id, true).unwrap();

        // Try to delete - should fail
        let result = manager.delete_version(&version.id);
        assert!(result.is_err());

        // Force delete should work
        let result = manager.force_delete_version(&version.id);
        assert!(result.is_ok());

        // Cleanup
        let _ = std::fs::remove_dir_all(&temp_dir);
    }
}

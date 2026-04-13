//! Multi-Project Isolation — per-project manifest, configs, profiles.
//! No shared mutable config between projects.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Per-project configuration snapshot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Energy governance config hash.
    pub geg_config_hash: String,
    /// DPM config hash.
    pub dpm_config_hash: String,
    /// SAMCL config hash.
    pub samcl_config_hash: String,
    /// SAM archetype.
    pub sam_archetype: String,
    /// Slot profile name.
    pub slot_profile: String,
    /// Sample rate.
    pub sample_rate: u32,
    /// Custom parameters (key-value).
    pub custom_params: HashMap<String, String>,
}

impl Default for ProjectConfig {
    fn default() -> Self {
        Self {
            geg_config_hash: String::new(),
            dpm_config_hash: String::new(),
            samcl_config_hash: String::new(),
            sam_archetype: "balanced".into(),
            slot_profile: "standard_5reel".into(),
            sample_rate: 48000,
            custom_params: HashMap::new(),
        }
    }
}

impl ProjectConfig {
    /// Compute a config bundle hash for this config.
    pub fn compute_hash(&self) -> String {
        let mut hasher = 0xcbf29ce484222325u64; // FNV-1a offset basis
        let parts = [
            &self.geg_config_hash,
            &self.dpm_config_hash,
            &self.samcl_config_hash,
            &self.sam_archetype,
            &self.slot_profile,
        ];
        for part in &parts {
            for byte in part.as_bytes() {
                hasher ^= *byte as u64;
                hasher = hasher.wrapping_mul(0x100000001b3);
            }
        }
        format!("{:016x}", hasher)
    }
}

/// Per-project manifest with version locking.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectManifest {
    pub project_id: String,
    pub project_name: String,
    pub config: ProjectConfig,
    pub config_hash: String,
    pub engine_version: String,
    pub regression_suite_version: u32,
    pub certification_hash: Option<String>,
    pub last_bake_timestamp: Option<u64>,
    pub created_timestamp: u64,
    pub modified_timestamp: u64,
}

impl ProjectManifest {
    /// Create a new manifest.
    pub fn new(id: impl Into<String>, name: impl Into<String>, config: ProjectConfig) -> Self {
        let hash = config.compute_hash();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        Self {
            project_id: id.into(),
            project_name: name.into(),
            config,
            config_hash: hash,
            engine_version: env!("CARGO_PKG_VERSION").into(),
            regression_suite_version: 1,
            certification_hash: None,
            last_bake_timestamp: None,
            created_timestamp: now,
            modified_timestamp: now,
        }
    }

    /// Update config and recompute hash. Returns true if hash changed.
    pub fn update_config(&mut self, new_config: ProjectConfig) -> bool {
        let new_hash = new_config.compute_hash();
        let changed = new_hash != self.config_hash;
        self.config = new_config;
        self.config_hash = new_hash;
        self.modified_timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        if changed {
            // Config changed → certification invalidated
            self.certification_hash = None;
        }
        changed
    }

    /// Check if certification is valid.
    pub fn is_certified(&self) -> bool {
        self.certification_hash.is_some()
    }

    /// Export manifest to JSON.
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }
}

/// An isolated project with its own manifest and data paths.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IsolatedProject {
    pub manifest: ProjectManifest,
    /// Path to project data directory.
    pub data_dir: String,
    /// Path to replay traces.
    pub traces_dir: String,
    /// Path to regression results.
    pub regression_dir: String,
    /// Path to burn test results.
    pub burn_test_dir: String,
    /// Path to export output.
    pub export_dir: String,
}

impl IsolatedProject {
    pub fn new(manifest: ProjectManifest, base_dir: &str) -> Self {
        let id = manifest.project_id.clone();
        Self {
            data_dir: format!("{}/{}/data", base_dir, id),
            traces_dir: format!("{}/{}/traces", base_dir, id),
            regression_dir: format!("{}/{}/regression", base_dir, id),
            burn_test_dir: format!("{}/{}/burn_tests", base_dir, id),
            export_dir: format!("{}/{}/exports", base_dir, id),
            manifest,
        }
    }
}

/// Multi-project isolation manager.
#[derive(Debug)]
pub struct ProjectIsolation {
    projects: HashMap<String, IsolatedProject>,
    base_dir: String,
    active_project_id: Option<String>,
}

impl ProjectIsolation {
    pub fn new(base_dir: impl Into<String>) -> Self {
        Self {
            projects: HashMap::new(),
            base_dir: base_dir.into(),
            active_project_id: None,
        }
    }

    /// Create a new isolated project.
    pub fn create_project(
        &mut self,
        name: impl Into<String>,
        config: ProjectConfig,
    ) -> &IsolatedProject {
        let name = name.into();
        let id = format!("proj_{:08x}", {
            let mut h = 0u32;
            for b in name.as_bytes() {
                h = h.wrapping_mul(31).wrapping_add(*b as u32);
            }
            h ^ (self.projects.len() as u32)
        });
        let manifest = ProjectManifest::new(&id, &name, config);
        let project = IsolatedProject::new(manifest, &self.base_dir);
        self.projects.insert(id.clone(), project);
        if self.active_project_id.is_none() {
            self.active_project_id = Some(id.clone());
        }
        // SAFETY: Just inserted above
        self.projects.get(&id).expect("project was just inserted")
    }

    /// Get active project.
    pub fn active_project(&self) -> Option<&IsolatedProject> {
        self.active_project_id
            .as_ref()
            .and_then(|id| self.projects.get(id))
    }

    /// Switch active project.
    pub fn switch_project(&mut self, id: &str) -> bool {
        if self.projects.contains_key(id) {
            self.active_project_id = Some(id.into());
            true
        } else {
            false
        }
    }

    /// List all projects.
    pub fn list_projects(&self) -> Vec<&IsolatedProject> {
        self.projects.values().collect()
    }

    /// Remove a project.
    pub fn remove_project(&mut self, id: &str) -> bool {
        let removed = self.projects.remove(id).is_some();
        if removed && self.active_project_id.as_deref() == Some(id) {
            self.active_project_id = self.projects.keys().next().cloned();
        }
        removed
    }

    /// Get project count.
    pub fn project_count(&self) -> usize {
        self.projects.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_project_config_hash() {
        let config = ProjectConfig::default();
        let hash = config.compute_hash();
        assert!(!hash.is_empty());
        assert_eq!(hash.len(), 16); // 16 hex chars = 64 bits

        // Same config → same hash
        let hash2 = config.compute_hash();
        assert_eq!(hash, hash2);

        // Different config → different hash
        let mut config2 = config.clone();
        config2.sam_archetype = "volatile".into();
        assert_ne!(config.compute_hash(), config2.compute_hash());
    }

    #[test]
    fn test_project_manifest_update() {
        let config = ProjectConfig::default();
        let mut manifest = ProjectManifest::new("p1", "Test", config);
        assert!(!manifest.is_certified());

        manifest.certification_hash = Some("abc123".into());
        assert!(manifest.is_certified());

        // Update config → certification invalidated
        let mut new_config = ProjectConfig::default();
        new_config.sam_archetype = "volatile".into();
        let changed = manifest.update_config(new_config);
        assert!(changed);
        assert!(!manifest.is_certified());
    }

    #[test]
    fn test_project_isolation_create_switch() {
        let mut isolation = ProjectIsolation::new("/tmp/sss");
        let p1 = isolation.create_project("Game A", ProjectConfig::default());
        let p1_id = p1.manifest.project_id.clone();

        let p2 = isolation.create_project("Game B", ProjectConfig::default());
        let p2_id = p2.manifest.project_id.clone();

        assert_eq!(isolation.project_count(), 2);
        assert_eq!(
            isolation.active_project().unwrap().manifest.project_id,
            p1_id
        );

        assert!(isolation.switch_project(&p2_id));
        assert_eq!(
            isolation.active_project().unwrap().manifest.project_id,
            p2_id
        );
    }

    #[test]
    fn test_project_isolation_remove() {
        let mut isolation = ProjectIsolation::new("/tmp/sss");
        let p1 = isolation.create_project("Game A", ProjectConfig::default());
        let p1_id = p1.manifest.project_id.clone();
        isolation.create_project("Game B", ProjectConfig::default());

        assert_eq!(isolation.project_count(), 2);
        assert!(isolation.remove_project(&p1_id));
        assert_eq!(isolation.project_count(), 1);
    }

    #[test]
    fn test_isolated_project_paths() {
        let config = ProjectConfig::default();
        let manifest = ProjectManifest::new("proj_test", "Test", config);
        let project = IsolatedProject::new(manifest, "/data/sss");
        assert!(project.data_dir.contains("proj_test"));
        assert!(project.traces_dir.contains("traces"));
        assert!(project.burn_test_dir.contains("burn_tests"));
    }
}

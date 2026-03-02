//! DRC: Manifest Manager (flux_manifest.json)
//!
//! Version locks for all subsystems + config_bundle_hash.
//! Any config change invalidates entire build.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §10

use serde::{Deserialize, Serialize};

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// Certification status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CertificationStatus {
    Pending,
    Certified,
    Failed,
}

impl CertificationStatus {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Pending => "PENDING",
            Self::Certified => "CERTIFIED",
            Self::Failed => "FAILED",
        }
    }
}

/// Version locks for all subsystems.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionLocks {
    pub engine_version: String,
    pub aurexis_version: String,
    pub hook_translation_version: String,
    pub emotional_engine_version: String,
    pub dpm_version: String,
    pub samcl_version: String,
    pub pbse_version: String,
    pub ail_version: String,
    pub drc_version: String,
}

impl Default for VersionLocks {
    fn default() -> Self {
        let version = env!("CARGO_PKG_VERSION").to_string();
        Self {
            engine_version: version.clone(),
            aurexis_version: version.clone(),
            hook_translation_version: version.clone(),
            emotional_engine_version: version.clone(),
            dpm_version: version.clone(),
            samcl_version: version.clone(),
            pbse_version: version.clone(),
            ail_version: version.clone(),
            drc_version: version,
        }
    }
}

/// Config bundle info.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigBundle {
    pub config_bundle_hash: u64,
    pub included_configs: Vec<String>,
}

impl Default for ConfigBundle {
    fn default() -> Self {
        Self {
            config_bundle_hash: 0,
            included_configs: vec![
                "emotional_transition_table.json".into(),
                "orchestration_matrix.json".into(),
                "decay_config.json".into(),
                "voice_allocation_table.json".into(),
                "dpm_event_weights.json".into(),
                "dpm_profile_modifiers.json".into(),
                "dpm_context_rules.json".into(),
                "dpm_priority_matrix.json".into(),
                "samcl_band_config.json".into(),
                "samcl_role_assignment.json".into(),
                "samcl_collision_rules.json".into(),
                "samcl_shift_curves.json".into(),
            ],
        }
    }
}

/// Certification chain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificationChain {
    pub drc_pass: bool,
    pub pbse_pass: bool,
    pub envelope_pass: bool,
    pub manifest_check_pass: bool,
    pub hash_validation_pass: bool,
    pub overall_certification: CertificationStatus,
}

impl Default for CertificationChain {
    fn default() -> Self {
        Self {
            drc_pass: false,
            pbse_pass: false,
            envelope_pass: false,
            manifest_check_pass: false,
            hash_validation_pass: false,
            overall_certification: CertificationStatus::Pending,
        }
    }
}

/// Complete flux_manifest.json.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FluxManifest {
    pub manifest_version: String,
    pub manifest_hash: u64,
    pub version_locks: VersionLocks,
    pub config_bundle: ConfigBundle,
    pub certification_chain: CertificationChain,
}

impl FluxManifest {
    /// Create a new manifest with default versions.
    pub fn new() -> Self {
        Self {
            manifest_version: "1.0".into(),
            manifest_hash: 0,
            version_locks: VersionLocks::default(),
            config_bundle: ConfigBundle::default(),
            certification_chain: CertificationChain::default(),
        }
    }

    /// Set config bundle hash from config data.
    pub fn set_config_hash(&mut self, config_data: &str) {
        self.config_bundle.config_bundle_hash = Self::fnv_hash(config_data.as_bytes());
        self.recompute_manifest_hash();
    }

    /// Update certification chain.
    pub fn update_certification(&mut self, drc_pass: bool, pbse_pass: bool, envelope_pass: bool) {
        self.certification_chain.drc_pass = drc_pass;
        self.certification_chain.pbse_pass = pbse_pass;
        self.certification_chain.envelope_pass = envelope_pass;
        self.certification_chain.manifest_check_pass = self.config_bundle.config_bundle_hash != 0;
        self.certification_chain.hash_validation_pass = true; // Will be verified

        let all_pass =
            drc_pass && pbse_pass && envelope_pass && self.certification_chain.manifest_check_pass;

        self.certification_chain.overall_certification = if all_pass {
            CertificationStatus::Certified
        } else {
            CertificationStatus::Failed
        };

        self.recompute_manifest_hash();
    }

    /// Check if manifest is certified.
    pub fn is_certified(&self) -> bool {
        self.certification_chain.overall_certification == CertificationStatus::Certified
    }

    /// Check if config has changed (invalidation).
    pub fn validate_config_hash(&self, config_data: &str) -> bool {
        let new_hash = Self::fnv_hash(config_data.as_bytes());
        new_hash == self.config_bundle.config_bundle_hash
    }

    /// Invalidate manifest (config changed).
    pub fn invalidate(&mut self) {
        self.certification_chain.overall_certification = CertificationStatus::Pending;
        self.certification_chain.hash_validation_pass = false;
        self.recompute_manifest_hash();
    }

    /// Serialize to JSON.
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }

    fn recompute_manifest_hash(&mut self) {
        // Hash version locks + config bundle hash + certification status
        let data = format!(
            "{}:{}:{}:{}",
            self.manifest_version,
            self.config_bundle.config_bundle_hash,
            self.certification_chain.overall_certification.name(),
            serde_json::to_string(&self.version_locks).unwrap_or_default(),
        );
        self.manifest_hash = Self::fnv_hash(data.as_bytes());
    }

    fn fnv_hash(data: &[u8]) -> u64 {
        let mut hash: u64 = 0xcbf29ce484222325;
        for byte in data {
            hash ^= *byte as u64;
            hash = hash.wrapping_mul(0x100000001b3);
        }
        hash
    }
}

impl Default for FluxManifest {
    fn default() -> Self {
        Self::new()
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manifest_creation() {
        let m = FluxManifest::new();
        assert_eq!(m.manifest_version, "1.0");
        assert_eq!(
            m.certification_chain.overall_certification,
            CertificationStatus::Pending
        );
        assert!(!m.is_certified());
    }

    #[test]
    fn test_config_hash() {
        let mut m = FluxManifest::new();
        m.set_config_hash("test config data");
        assert_ne!(m.config_bundle.config_bundle_hash, 0);

        assert!(m.validate_config_hash("test config data"));
        assert!(!m.validate_config_hash("different config"));
    }

    #[test]
    fn test_certification_all_pass() {
        let mut m = FluxManifest::new();
        m.set_config_hash("config");
        m.update_certification(true, true, true);
        assert!(m.is_certified());
        assert_eq!(
            m.certification_chain.overall_certification,
            CertificationStatus::Certified
        );
    }

    #[test]
    fn test_certification_fails_if_drc_fails() {
        let mut m = FluxManifest::new();
        m.set_config_hash("config");
        m.update_certification(false, true, true);
        assert!(!m.is_certified());
    }

    #[test]
    fn test_certification_fails_if_pbse_fails() {
        let mut m = FluxManifest::new();
        m.set_config_hash("config");
        m.update_certification(true, false, true);
        assert!(!m.is_certified());
    }

    #[test]
    fn test_certification_fails_if_envelope_fails() {
        let mut m = FluxManifest::new();
        m.set_config_hash("config");
        m.update_certification(true, true, false);
        assert!(!m.is_certified());
    }

    #[test]
    fn test_invalidation() {
        let mut m = FluxManifest::new();
        m.set_config_hash("config");
        m.update_certification(true, true, true);
        assert!(m.is_certified());

        m.invalidate();
        assert!(!m.is_certified());
        assert_eq!(
            m.certification_chain.overall_certification,
            CertificationStatus::Pending
        );
    }

    #[test]
    fn test_manifest_json() {
        let m = FluxManifest::new();
        let json = m.to_json().expect("JSON should work");
        assert!(json.contains("manifest_version"));
        assert!(json.contains("version_locks"));
        assert!(json.contains("config_bundle"));
        assert!(json.contains("certification_chain"));
    }

    #[test]
    fn test_manifest_hash_changes() {
        let mut m = FluxManifest::new();
        let h1 = m.manifest_hash;
        m.set_config_hash("data");
        assert_ne!(m.manifest_hash, h1);
    }

    #[test]
    fn test_version_locks_default() {
        let v = VersionLocks::default();
        assert!(!v.engine_version.is_empty());
        assert_eq!(v.engine_version, v.aurexis_version);
    }
}

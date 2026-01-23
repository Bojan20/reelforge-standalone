//! # rf-release
//!
//! Release automation for FluxForge Studio.
//!
//! ## Features
//!
//! - Semantic versioning management
//! - Changelog generation from git commits
//! - Version bumping across all crates
//! - Release artifact packaging
//! - CI/CD integration helpers
//!
//! ## Version Format
//!
//! `MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]`
//!
//! Examples:
//! - `1.0.0` - Stable release
//! - `1.0.0-alpha.1` - Alpha prerelease
//! - `1.0.0-beta.2+build.456` - Beta with build metadata

pub mod changelog;
pub mod packaging;
pub mod version;

pub use changelog::{ChangelogEntry, ChangelogGenerator, ChangeType};
pub use packaging::{PackageConfig, ReleasePackage};
pub use version::{BumpType, Version};

use thiserror::Error;

/// Errors that can occur during release operations
#[derive(Error, Debug)]
pub enum ReleaseError {
    #[error("Invalid version: {0}")]
    InvalidVersion(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("TOML parse error: {0}")]
    TomlError(#[from] toml::de::Error),

    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Git error: {0}")]
    GitError(String),

    #[error("Package error: {0}")]
    PackageError(String),
}

pub type Result<T> = std::result::Result<T, ReleaseError>;

/// Release configuration
#[derive(Debug, Clone)]
pub struct ReleaseConfig {
    /// Current version
    pub version: Version,
    /// Crates to include in release
    pub crates: Vec<String>,
    /// Flutter package path
    pub flutter_path: Option<String>,
    /// Release branch
    pub release_branch: String,
    /// Changelog path
    pub changelog_path: String,
}

impl Default for ReleaseConfig {
    fn default() -> Self {
        Self {
            version: Version::new(0, 1, 0),
            crates: vec![
                "rf-core".into(),
                "rf-dsp".into(),
                "rf-engine".into(),
                "rf-bridge".into(),
            ],
            flutter_path: Some("flutter_ui".into()),
            release_branch: "main".into(),
            changelog_path: "CHANGELOG.md".into(),
        }
    }
}

/// Main release manager
pub struct ReleaseManager {
    config: ReleaseConfig,
}

impl ReleaseManager {
    /// Create new release manager
    pub fn new(config: ReleaseConfig) -> Self {
        Self { config }
    }

    /// Get current version
    pub fn version(&self) -> &Version {
        &self.config.version
    }

    /// Bump version
    pub fn bump(&mut self, bump_type: BumpType) -> &Version {
        self.config.version = self.config.version.bump(bump_type);
        &self.config.version
    }

    /// Set prerelease tag
    pub fn set_prerelease(&mut self, tag: &str) {
        self.config.version = self.config.version.clone().with_prerelease(tag);
    }

    /// Clear prerelease (promote to stable)
    pub fn promote(&mut self) {
        self.config.version = self.config.version.clone().promote();
    }

    /// Prepare release (validate, generate changelog)
    pub fn prepare(&self) -> Result<ReleasePlan> {
        let changelog = ChangelogGenerator::new()
            .since_tag(&format!("v{}", self.config.version.previous_stable()))
            .generate()?;

        Ok(ReleasePlan {
            version: self.config.version.clone(),
            changelog,
            crates: self.config.crates.clone(),
            flutter_path: self.config.flutter_path.clone(),
        })
    }
}

/// Release plan to be executed
#[derive(Debug)]
pub struct ReleasePlan {
    /// Target version
    pub version: Version,
    /// Generated changelog
    pub changelog: Vec<ChangelogEntry>,
    /// Crates to update
    pub crates: Vec<String>,
    /// Flutter path
    pub flutter_path: Option<String>,
}

impl ReleasePlan {
    /// Format as markdown
    pub fn to_markdown(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("# Release v{}\n\n", self.version));

        if !self.changelog.is_empty() {
            output.push_str("## Changes\n\n");
            for entry in &self.changelog {
                output.push_str(&format!("- {} {}\n", entry.change_type.emoji(), entry.message));
            }
        }

        output.push_str("\n## Packages\n\n");
        for crate_name in &self.crates {
            output.push_str(&format!("- {}\n", crate_name));
        }

        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_release_config_default() {
        let config = ReleaseConfig::default();
        assert_eq!(config.version.major, 0);
        assert_eq!(config.version.minor, 1);
        assert_eq!(config.version.patch, 0);
    }

    #[test]
    fn test_release_manager_bump() {
        let config = ReleaseConfig::default();
        let mut manager = ReleaseManager::new(config);

        manager.bump(BumpType::Minor);
        assert_eq!(manager.version().to_string(), "0.2.0");

        manager.bump(BumpType::Patch);
        assert_eq!(manager.version().to_string(), "0.2.1");

        manager.bump(BumpType::Major);
        assert_eq!(manager.version().to_string(), "1.0.0");
    }

    #[test]
    fn test_prerelease() {
        let config = ReleaseConfig::default();
        let mut manager = ReleaseManager::new(config);

        manager.set_prerelease("alpha.1");
        assert_eq!(manager.version().to_string(), "0.1.0-alpha.1");

        manager.promote();
        assert_eq!(manager.version().to_string(), "0.1.0");
    }
}

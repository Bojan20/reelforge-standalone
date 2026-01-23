//! Release packaging and artifact generation

use crate::{Result, Version};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Platform target
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Platform {
    MacOsArm64,
    MacOsX64,
    WindowsX64,
    LinuxX64,
}

impl Platform {
    /// Get Rust target triple
    pub fn target(&self) -> &'static str {
        match self {
            Self::MacOsArm64 => "aarch64-apple-darwin",
            Self::MacOsX64 => "x86_64-apple-darwin",
            Self::WindowsX64 => "x86_64-pc-windows-msvc",
            Self::LinuxX64 => "x86_64-unknown-linux-gnu",
        }
    }

    /// Get artifact extension
    pub fn extension(&self) -> &'static str {
        match self {
            Self::MacOsArm64 | Self::MacOsX64 => "tar.gz",
            Self::WindowsX64 => "zip",
            Self::LinuxX64 => "tar.gz",
        }
    }

    /// Get dylib extension
    pub fn dylib_extension(&self) -> &'static str {
        match self {
            Self::MacOsArm64 | Self::MacOsX64 => "dylib",
            Self::WindowsX64 => "dll",
            Self::LinuxX64 => "so",
        }
    }

    /// Get all supported platforms
    pub fn all() -> &'static [Platform] {
        &[
            Self::MacOsArm64,
            Self::MacOsX64,
            Self::WindowsX64,
            Self::LinuxX64,
        ]
    }
}

/// Package configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageConfig {
    /// Package name
    pub name: String,
    /// Version
    pub version: Version,
    /// Target platforms
    pub platforms: Vec<Platform>,
    /// Files to include
    pub files: Vec<PackageFile>,
    /// Output directory
    pub output_dir: PathBuf,
}

/// A file to include in package
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageFile {
    /// Source path (relative to project root)
    pub source: String,
    /// Destination path in archive
    pub dest: String,
    /// Only include for specific platforms
    pub platforms: Option<Vec<Platform>>,
}

impl Default for PackageConfig {
    fn default() -> Self {
        Self {
            name: "fluxforge-studio".into(),
            version: Version::new(0, 1, 0),
            platforms: Platform::all().to_vec(),
            files: vec![
                PackageFile {
                    source: "target/release/librf_bridge.dylib".into(),
                    dest: "lib/librf_bridge.dylib".into(),
                    platforms: Some(vec![Platform::MacOsArm64, Platform::MacOsX64]),
                },
                PackageFile {
                    source: "target/release/librf_engine.dylib".into(),
                    dest: "lib/librf_engine.dylib".into(),
                    platforms: Some(vec![Platform::MacOsArm64, Platform::MacOsX64]),
                },
                PackageFile {
                    source: "target/release/rf_bridge.dll".into(),
                    dest: "lib/rf_bridge.dll".into(),
                    platforms: Some(vec![Platform::WindowsX64]),
                },
                PackageFile {
                    source: "README.md".into(),
                    dest: "README.md".into(),
                    platforms: None,
                },
                PackageFile {
                    source: "LICENSE".into(),
                    dest: "LICENSE".into(),
                    platforms: None,
                },
            ],
            output_dir: PathBuf::from("dist"),
        }
    }
}

/// Release package builder
#[derive(Debug)]
pub struct ReleasePackage {
    config: PackageConfig,
    artifacts: HashMap<Platform, PathBuf>,
}

impl ReleasePackage {
    /// Create new package builder
    pub fn new(config: PackageConfig) -> Self {
        Self {
            config,
            artifacts: HashMap::new(),
        }
    }

    /// Get artifact filename for platform
    pub fn artifact_name(&self, platform: Platform) -> String {
        format!(
            "{}-{}-{}.{}",
            self.config.name,
            self.config.version,
            platform.target(),
            platform.extension()
        )
    }

    /// Get files for platform
    pub fn files_for_platform(&self, platform: Platform) -> Vec<&PackageFile> {
        self.config
            .files
            .iter()
            .filter(|f| {
                f.platforms
                    .as_ref()
                    .map(|p| p.contains(&platform))
                    .unwrap_or(true)
            })
            .collect()
    }

    /// Build package for platform (mock implementation)
    pub fn build(&mut self, platform: Platform) -> Result<PathBuf> {
        let artifact_name = self.artifact_name(platform);
        let artifact_path = self.config.output_dir.join(&artifact_name);

        // In real implementation, this would:
        // 1. Create temp directory
        // 2. Copy files
        // 3. Create archive
        // 4. Compute checksums

        self.artifacts.insert(platform, artifact_path.clone());
        Ok(artifact_path)
    }

    /// Build all platforms
    pub fn build_all(&mut self) -> Result<Vec<PathBuf>> {
        let platforms = self.config.platforms.clone();
        let mut paths = Vec::new();

        for platform in platforms {
            paths.push(self.build(platform)?);
        }

        Ok(paths)
    }

    /// Generate release manifest
    pub fn manifest(&self) -> ReleaseManifest {
        ReleaseManifest {
            version: self.config.version.clone(),
            artifacts: self
                .artifacts
                .iter()
                .map(|(platform, path)| ArtifactInfo {
                    platform: *platform,
                    filename: path.file_name().unwrap().to_string_lossy().to_string(),
                    sha256: String::new(), // Would compute in real implementation
                    size: 0,               // Would compute in real implementation
                })
                .collect(),
        }
    }
}

/// Release manifest for download page/API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleaseManifest {
    /// Version
    pub version: Version,
    /// Artifacts
    pub artifacts: Vec<ArtifactInfo>,
}

/// Artifact info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArtifactInfo {
    /// Target platform
    pub platform: Platform,
    /// Filename
    pub filename: String,
    /// SHA256 checksum
    pub sha256: String,
    /// File size in bytes
    pub size: u64,
}

impl ReleaseManifest {
    /// Generate JSON
    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_else(|_| "{}".into())
    }

    /// Generate markdown download table
    pub fn to_markdown(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!("## Downloads v{}\n\n", self.version));
        output.push_str("| Platform | Download | SHA256 |\n");
        output.push_str("|----------|----------|--------|\n");

        for artifact in &self.artifacts {
            let platform_name = match artifact.platform {
                Platform::MacOsArm64 => "macOS (Apple Silicon)",
                Platform::MacOsX64 => "macOS (Intel)",
                Platform::WindowsX64 => "Windows (x64)",
                Platform::LinuxX64 => "Linux (x64)",
            };

            output.push_str(&format!(
                "| {} | [{}]({}) | `{}`... |\n",
                platform_name,
                artifact.filename,
                artifact.filename,
                if artifact.sha256.len() > 8 {
                    &artifact.sha256[..8]
                } else {
                    &artifact.sha256
                }
            ));
        }

        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_platform_target() {
        assert_eq!(Platform::MacOsArm64.target(), "aarch64-apple-darwin");
        assert_eq!(Platform::WindowsX64.target(), "x86_64-pc-windows-msvc");
    }

    #[test]
    fn test_artifact_name() {
        let config = PackageConfig {
            name: "myapp".into(),
            version: Version::new(1, 2, 3),
            ..Default::default()
        };
        let package = ReleasePackage::new(config);

        assert_eq!(
            package.artifact_name(Platform::MacOsArm64),
            "myapp-1.2.3-aarch64-apple-darwin.tar.gz"
        );
    }

    #[test]
    fn test_files_for_platform() {
        let config = PackageConfig::default();
        let package = ReleasePackage::new(config);

        let macos_files = package.files_for_platform(Platform::MacOsArm64);
        let windows_files = package.files_for_platform(Platform::WindowsX64);

        // macOS should have dylib files
        assert!(macos_files.iter().any(|f| f.source.ends_with(".dylib")));

        // Windows should have dll files
        assert!(windows_files.iter().any(|f| f.source.ends_with(".dll")));
    }

    #[test]
    fn test_manifest_json() {
        let manifest = ReleaseManifest {
            version: Version::new(1, 0, 0),
            artifacts: vec![ArtifactInfo {
                platform: Platform::MacOsArm64,
                filename: "test.tar.gz".into(),
                sha256: "abc123".into(),
                size: 1000,
            }],
        };

        let json = manifest.to_json();
        assert!(json.contains("\"major\": 1"));
        assert!(json.contains("test.tar.gz"));
    }
}

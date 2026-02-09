//! Semantic versioning support

use crate::{ReleaseError, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::fmt;
use std::str::FromStr;

/// Semantic version
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct Version {
    /// Major version (breaking changes)
    pub major: u32,
    /// Minor version (new features)
    pub minor: u32,
    /// Patch version (bug fixes)
    pub patch: u32,
    /// Prerelease tag (e.g., "alpha.1", "beta.2")
    pub prerelease: Option<String>,
    /// Build metadata (e.g., "build.456")
    pub build: Option<String>,
}

/// Version bump type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BumpType {
    /// Bump major version (1.0.0 -> 2.0.0)
    Major,
    /// Bump minor version (1.0.0 -> 1.1.0)
    Minor,
    /// Bump patch version (1.0.0 -> 1.0.1)
    Patch,
}

impl Version {
    /// Create new version
    pub fn new(major: u32, minor: u32, patch: u32) -> Self {
        Self {
            major,
            minor,
            patch,
            prerelease: None,
            build: None,
        }
    }

    /// Parse version from string
    pub fn parse(s: &str) -> Result<Self> {
        s.parse()
    }

    /// Check if this is a prerelease version
    pub fn is_prerelease(&self) -> bool {
        self.prerelease.is_some()
    }

    /// Check if this is a stable release (no prerelease tag)
    pub fn is_stable(&self) -> bool {
        self.prerelease.is_none()
    }

    /// Bump version
    pub fn bump(&self, bump_type: BumpType) -> Self {
        match bump_type {
            BumpType::Major => Self::new(self.major + 1, 0, 0),
            BumpType::Minor => Self::new(self.major, self.minor + 1, 0),
            BumpType::Patch => Self::new(self.major, self.minor, self.patch + 1),
        }
    }

    /// Add prerelease tag
    pub fn with_prerelease(mut self, tag: &str) -> Self {
        self.prerelease = Some(tag.into());
        self
    }

    /// Add build metadata
    pub fn with_build(mut self, build: &str) -> Self {
        self.build = Some(build.into());
        self
    }

    /// Promote to stable (remove prerelease tag)
    pub fn promote(mut self) -> Self {
        self.prerelease = None;
        self
    }

    /// Get previous stable version
    pub fn previous_stable(&self) -> Self {
        if self.patch > 0 {
            Self::new(self.major, self.minor, self.patch - 1)
        } else if self.minor > 0 {
            Self::new(self.major, self.minor - 1, 0)
        } else if self.major > 0 {
            Self::new(self.major - 1, 0, 0)
        } else {
            Self::new(0, 0, 0)
        }
    }

    /// Check if compatible with another version (same major)
    pub fn is_compatible(&self, other: &Version) -> bool {
        self.major == other.major
    }

    /// Format as Cargo.toml compatible string
    pub fn cargo_string(&self) -> String {
        // Cargo doesn't support build metadata
        if let Some(ref pre) = self.prerelease {
            format!("{}.{}.{}-{}", self.major, self.minor, self.patch, pre)
        } else {
            format!("{}.{}.{}", self.major, self.minor, self.patch)
        }
    }

    /// Format as git tag
    pub fn git_tag(&self) -> String {
        format!("v{}", self)
    }
}

impl fmt::Display for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)?;

        if let Some(ref pre) = self.prerelease {
            write!(f, "-{}", pre)?;
        }

        if let Some(ref build) = self.build {
            write!(f, "+{}", build)?;
        }

        Ok(())
    }
}

impl FromStr for Version {
    type Err = ReleaseError;

    fn from_str(s: &str) -> Result<Self> {
        let re = Regex::new(r"^v?(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9.]+))?(?:\+([a-zA-Z0-9.]+))?$")
            .unwrap();

        let caps = re
            .captures(s)
            .ok_or_else(|| ReleaseError::InvalidVersion(s.to_string()))?;

        let major = caps[1].parse().map_err(|_| {
            ReleaseError::InvalidVersion(format!("Invalid major version: {}", &caps[1]))
        })?;

        let minor = caps[2].parse().map_err(|_| {
            ReleaseError::InvalidVersion(format!("Invalid minor version: {}", &caps[2]))
        })?;

        let patch = caps[3].parse().map_err(|_| {
            ReleaseError::InvalidVersion(format!("Invalid patch version: {}", &caps[3]))
        })?;

        let prerelease = caps.get(4).map(|m| m.as_str().to_string());
        let build = caps.get(5).map(|m| m.as_str().to_string());

        Ok(Self {
            major,
            minor,
            patch,
            prerelease,
            build,
        })
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> Ordering {
        // Compare major.minor.patch
        match self.major.cmp(&other.major) {
            Ordering::Equal => {}
            ord => return ord,
        }
        match self.minor.cmp(&other.minor) {
            Ordering::Equal => {}
            ord => return ord,
        }
        match self.patch.cmp(&other.patch) {
            Ordering::Equal => {}
            ord => return ord,
        }

        // Prerelease comparison (no prerelease > prerelease)
        match (&self.prerelease, &other.prerelease) {
            (None, None) => Ordering::Equal,
            (None, Some(_)) => Ordering::Greater,
            (Some(_), None) => Ordering::Less,
            (Some(a), Some(b)) => a.cmp(b),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_new() {
        let v = Version::new(1, 2, 3);
        assert_eq!(v.major, 1);
        assert_eq!(v.minor, 2);
        assert_eq!(v.patch, 3);
        assert!(v.is_stable());
    }

    #[test]
    fn test_version_parse() {
        let v: Version = "1.2.3".parse().unwrap();
        assert_eq!(v.to_string(), "1.2.3");

        let v: Version = "v1.2.3".parse().unwrap();
        assert_eq!(v.to_string(), "1.2.3");

        let v: Version = "1.0.0-alpha.1".parse().unwrap();
        assert_eq!(v.prerelease, Some("alpha.1".into()));

        let v: Version = "1.0.0-beta.2+build.456".parse().unwrap();
        assert_eq!(v.prerelease, Some("beta.2".into()));
        assert_eq!(v.build, Some("build.456".into()));
    }

    #[test]
    fn test_version_bump() {
        let v = Version::new(1, 2, 3);

        assert_eq!(v.bump(BumpType::Patch).to_string(), "1.2.4");
        assert_eq!(v.bump(BumpType::Minor).to_string(), "1.3.0");
        assert_eq!(v.bump(BumpType::Major).to_string(), "2.0.0");
    }

    #[test]
    fn test_version_ordering() {
        let v1: Version = "1.0.0".parse().unwrap();
        let v2: Version = "1.0.1".parse().unwrap();
        let v3: Version = "1.1.0".parse().unwrap();
        let v4: Version = "2.0.0".parse().unwrap();
        let v5: Version = "1.0.0-alpha.1".parse().unwrap();

        assert!(v1 < v2);
        assert!(v2 < v3);
        assert!(v3 < v4);
        assert!(v5 < v1); // Prerelease is lower
    }

    #[test]
    fn test_version_prerelease() {
        let v = Version::new(1, 0, 0).with_prerelease("alpha.1");
        assert!(v.is_prerelease());
        assert_eq!(v.to_string(), "1.0.0-alpha.1");

        let stable = v.promote();
        assert!(stable.is_stable());
        assert_eq!(stable.to_string(), "1.0.0");
    }

    #[test]
    fn test_git_tag() {
        let v = Version::new(1, 2, 3);
        assert_eq!(v.git_tag(), "v1.2.3");
    }
}

//! Changelog generation from git commits

use crate::{Result, Version};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// Type of change for changelog categorization
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ChangeType {
    /// New feature
    Feature,
    /// Bug fix
    Fix,
    /// Documentation change
    Docs,
    /// Code style/formatting
    Style,
    /// Code refactoring
    Refactor,
    /// Performance improvement
    Perf,
    /// Test changes
    Test,
    /// Build/CI changes
    Build,
    /// Chores and maintenance
    Chore,
    /// Breaking change
    Breaking,
    /// Other/unknown
    Other,
}

impl ChangeType {
    /// Parse from conventional commit prefix
    pub fn from_prefix(prefix: &str) -> Self {
        match prefix.to_lowercase().as_str() {
            "feat" | "feature" => Self::Feature,
            "fix" | "bugfix" => Self::Fix,
            "docs" | "doc" => Self::Docs,
            "style" => Self::Style,
            "refactor" => Self::Refactor,
            "perf" | "performance" => Self::Perf,
            "test" | "tests" => Self::Test,
            "build" | "ci" => Self::Build,
            "chore" | "maintenance" => Self::Chore,
            _ => Self::Other,
        }
    }

    /// Get emoji for change type
    pub fn emoji(&self) -> &'static str {
        match self {
            Self::Feature => "✨",
            Self::Fix => "🐛",
            Self::Docs => "📝",
            Self::Style => "💄",
            Self::Refactor => "♻️",
            Self::Perf => "⚡",
            Self::Test => "✅",
            Self::Build => "👷",
            Self::Chore => "🔧",
            Self::Breaking => "💥",
            Self::Other => "📦",
        }
    }

    /// Get section title for changelog
    pub fn title(&self) -> &'static str {
        match self {
            Self::Feature => "Features",
            Self::Fix => "Bug Fixes",
            Self::Docs => "Documentation",
            Self::Style => "Style",
            Self::Refactor => "Refactoring",
            Self::Perf => "Performance",
            Self::Test => "Tests",
            Self::Build => "Build",
            Self::Chore => "Maintenance",
            Self::Breaking => "Breaking Changes",
            Self::Other => "Other",
        }
    }
}

/// A single changelog entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChangelogEntry {
    /// Type of change
    pub change_type: ChangeType,
    /// Scope (optional, e.g., "dsp", "engine")
    pub scope: Option<String>,
    /// Change message
    pub message: String,
    /// Git commit hash
    pub commit: Option<String>,
    /// Author
    pub author: Option<String>,
    /// Is breaking change
    pub breaking: bool,
}

impl ChangelogEntry {
    /// Parse from conventional commit message
    pub fn from_commit(message: &str, commit: Option<String>, author: Option<String>) -> Self {
        // Pattern: type(scope)!: message
        let re = Regex::new(r"^(\w+)(?:\(([^)]+)\))?(!)?:\s*(.+)").unwrap();

        if let Some(caps) = re.captures(message) {
            let type_str = &caps[1];
            let scope = caps.get(2).map(|m| m.as_str().to_string());
            let breaking = caps.get(3).is_some();
            let msg = caps[4].to_string();

            let change_type = if breaking {
                ChangeType::Breaking
            } else {
                ChangeType::from_prefix(type_str)
            };

            Self {
                change_type,
                scope,
                message: msg,
                commit,
                author,
                breaking,
            }
        } else {
            // Non-conventional commit
            Self {
                change_type: ChangeType::Other,
                scope: None,
                message: message.lines().next().unwrap_or(message).to_string(),
                commit,
                author,
                breaking: false,
            }
        }
    }

    /// Format as markdown list item
    pub fn to_markdown(&self) -> String {
        let scope = self
            .scope
            .as_ref()
            .map(|s| format!("**{}:** ", s))
            .unwrap_or_default();
        let commit = self
            .commit
            .as_ref()
            .map(|c| format!(" ({})", &c[..7.min(c.len())]))
            .unwrap_or_default();

        format!("- {}{}{}", scope, self.message, commit)
    }
}

/// Changelog generator
pub struct ChangelogGenerator {
    /// Since tag/commit
    since: Option<String>,
    /// Include merge commits
    include_merges: bool,
    /// Include authors
    include_authors: bool,
}

impl ChangelogGenerator {
    /// Create new generator
    pub fn new() -> Self {
        Self {
            since: None,
            include_merges: false,
            include_authors: true,
        }
    }

    /// Set starting point (tag or commit)
    pub fn since_tag(mut self, tag: &str) -> Self {
        self.since = Some(tag.into());
        self
    }

    /// Include merge commits
    pub fn with_merges(mut self, include: bool) -> Self {
        self.include_merges = include;
        self
    }

    /// Include authors
    pub fn with_authors(mut self, include: bool) -> Self {
        self.include_authors = include;
        self
    }

    /// Generate changelog entries (mock implementation)
    pub fn generate(&self) -> Result<Vec<ChangelogEntry>> {
        // In real implementation, this would run git log
        // For now, return empty vec
        Ok(Vec::new())
    }

    /// Generate changelog from commit messages
    pub fn from_commits(&self, commits: &[(String, String, String)]) -> Vec<ChangelogEntry> {
        commits
            .iter()
            .map(|(hash, author, message)| {
                ChangelogEntry::from_commit(message, Some(hash.clone()), Some(author.clone()))
            })
            .collect()
    }
}

impl Default for ChangelogGenerator {
    fn default() -> Self {
        Self::new()
    }
}

/// Full changelog file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Changelog {
    /// All releases
    pub releases: Vec<ChangelogRelease>,
}

/// A single release in the changelog
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChangelogRelease {
    /// Version
    pub version: Version,
    /// Release date (YYYY-MM-DD)
    pub date: String,
    /// Entries grouped by type
    pub entries: Vec<ChangelogEntry>,
}

impl Changelog {
    /// Load from file
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path)?;
        Self::parse(&content)
    }

    /// Parse from markdown
    pub fn parse(markdown: &str) -> Result<Self> {
        // Simple parser - looks for ## [version] - date
        let version_re = Regex::new(r"##\s*\[([^\]]+)\]\s*-\s*(\d{4}-\d{2}-\d{2})").unwrap();
        let mut releases = Vec::new();

        for caps in version_re.captures_iter(markdown) {
            let version: Version = caps[1].parse()?;
            let date = caps[2].to_string();

            releases.push(ChangelogRelease {
                version,
                date,
                entries: Vec::new(), // Would need more parsing
            });
        }

        Ok(Self { releases })
    }

    /// Generate markdown
    pub fn to_markdown(&self) -> String {
        let mut output = String::new();

        output.push_str("# Changelog\n\n");
        output.push_str("All notable changes to this project will be documented in this file.\n\n");
        output.push_str(
            "The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),\n",
        );
        output.push_str("and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).\n\n");

        for release in &self.releases {
            output.push_str(&format!("## [{}] - {}\n\n", release.version, release.date));

            // Group entries by type
            let mut by_type: std::collections::HashMap<ChangeType, Vec<&ChangelogEntry>> =
                std::collections::HashMap::new();

            for entry in &release.entries {
                by_type.entry(entry.change_type).or_default().push(entry);
            }

            // Output in order
            for change_type in &[
                ChangeType::Breaking,
                ChangeType::Feature,
                ChangeType::Fix,
                ChangeType::Perf,
                ChangeType::Docs,
                ChangeType::Refactor,
                ChangeType::Other,
            ] {
                if let Some(entries) = by_type.get(change_type) {
                    output.push_str(&format!("### {}\n\n", change_type.title()));
                    for entry in entries.iter() {
                        output.push_str(&format!("{}\n", (*entry).to_markdown()));
                    }
                    output.push('\n');
                }
            }
        }

        output
    }

    /// Save to file
    pub fn save<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        fs::write(path, self.to_markdown())?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_change_type_from_prefix() {
        assert_eq!(ChangeType::from_prefix("feat"), ChangeType::Feature);
        assert_eq!(ChangeType::from_prefix("fix"), ChangeType::Fix);
        assert_eq!(ChangeType::from_prefix("docs"), ChangeType::Docs);
        assert_eq!(ChangeType::from_prefix("unknown"), ChangeType::Other);
    }

    #[test]
    fn test_entry_from_commit() {
        let entry = ChangelogEntry::from_commit(
            "feat(dsp): add new compressor",
            Some("abc1234".into()),
            Some("Author".into()),
        );

        assert_eq!(entry.change_type, ChangeType::Feature);
        assert_eq!(entry.scope, Some("dsp".into()));
        assert_eq!(entry.message, "add new compressor");
        assert!(!entry.breaking);
    }

    #[test]
    fn test_breaking_change() {
        let entry = ChangelogEntry::from_commit("feat(api)!: change parameter order", None, None);

        assert_eq!(entry.change_type, ChangeType::Breaking);
        assert!(entry.breaking);
    }

    #[test]
    fn test_entry_markdown() {
        let entry = ChangelogEntry::from_commit(
            "fix(engine): resolve memory leak",
            Some("abc1234".into()),
            None,
        );

        let md = entry.to_markdown();
        assert!(md.contains("**engine:**"));
        assert!(md.contains("resolve memory leak"));
        assert!(md.contains("abc1234"));
    }
}

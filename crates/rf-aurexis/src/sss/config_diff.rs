//! Config Diff Engine — detect structural/behavioral changes between configs.
//! Computes risk level and regression_required flag.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Type of change detected.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DiffType {
    /// Value changed.
    Modified,
    /// New key added.
    Added,
    /// Key removed.
    Removed,
    /// Type changed (structural).
    TypeChanged,
}

/// Risk level of a change.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum RiskLevel {
    /// No risk — cosmetic change.
    None = 0,
    /// Low risk — safe parameter tweak.
    Low = 1,
    /// Medium risk — behavioral change, regression recommended.
    Medium = 2,
    /// High risk — structural change, regression required.
    High = 3,
    /// Critical — breaking change, full re-certification needed.
    Critical = 4,
}

impl RiskLevel {
    pub fn label(&self) -> &'static str {
        match self {
            Self::None => "None",
            Self::Low => "Low",
            Self::Medium => "Medium",
            Self::High => "High",
            Self::Critical => "Critical",
        }
    }

    pub fn regression_required(&self) -> bool {
        *self >= Self::Medium
    }
}

/// A single diff entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffEntry {
    pub path: String,
    pub diff_type: DiffType,
    pub old_value: Option<String>,
    pub new_value: Option<String>,
    pub risk_level: RiskLevel,
    pub description: String,
}

/// Complete diff result between two configs.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigDiff {
    pub entries: Vec<DiffEntry>,
    pub overall_risk: RiskLevel,
    pub regression_required: bool,
    pub total_changes: usize,
    pub structural_changes: usize,
    pub behavioral_changes: usize,
}

impl ConfigDiff {
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Get entries filtered by risk level.
    pub fn entries_at_risk(&self, level: RiskLevel) -> Vec<&DiffEntry> {
        self.entries
            .iter()
            .filter(|e| e.risk_level == level)
            .collect()
    }

    /// Export diff to JSON.
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }
}

/// Risk classification rules for known config keys.
const RISK_RULES: &[(&str, RiskLevel)] = &[
    ("sample_rate", RiskLevel::Critical),
    ("slot_profile", RiskLevel::High),
    ("sam_archetype", RiskLevel::High),
    ("geg_config", RiskLevel::High),
    ("dpm_config", RiskLevel::Medium),
    ("samcl_config", RiskLevel::Medium),
    ("voice_budget", RiskLevel::Medium),
    ("energy_cap", RiskLevel::Medium),
    ("custom_", RiskLevel::Low),
];

/// Config Diff Engine.
#[derive(Debug)]
pub struct ConfigDiffEngine;

impl ConfigDiffEngine {
    /// Compute diff between two flat config maps.
    pub fn diff(old: &HashMap<String, String>, new: &HashMap<String, String>) -> ConfigDiff {
        let mut entries = Vec::new();

        // Check modified and removed keys
        for (key, old_val) in old {
            match new.get(key) {
                Some(new_val) if new_val != old_val => {
                    let risk = Self::classify_risk(key);
                    entries.push(DiffEntry {
                        path: key.clone(),
                        diff_type: DiffType::Modified,
                        old_value: Some(old_val.clone()),
                        new_value: Some(new_val.clone()),
                        risk_level: risk,
                        description: format!("Changed '{}': '{}' → '{}'", key, old_val, new_val),
                    });
                }
                None => {
                    let risk = Self::classify_risk(key);
                    entries.push(DiffEntry {
                        path: key.clone(),
                        diff_type: DiffType::Removed,
                        old_value: Some(old_val.clone()),
                        new_value: None,
                        risk_level: risk.max(RiskLevel::Medium), // Removals are at least medium
                        description: format!("Removed '{}'", key),
                    });
                }
                _ => {} // Unchanged
            }
        }

        // Check added keys
        for (key, new_val) in new {
            if !old.contains_key(key) {
                let risk = Self::classify_risk(key);
                entries.push(DiffEntry {
                    path: key.clone(),
                    diff_type: DiffType::Added,
                    old_value: None,
                    new_value: Some(new_val.clone()),
                    risk_level: risk,
                    description: format!("Added '{}': '{}'", key, new_val),
                });
            }
        }

        // Sort by risk level (highest first)
        entries.sort_by_key(|b| std::cmp::Reverse(b.risk_level));

        let overall_risk = entries
            .iter()
            .map(|e| e.risk_level)
            .max()
            .unwrap_or(RiskLevel::None);

        let structural_changes = entries
            .iter()
            .filter(|e| {
                matches!(
                    e.diff_type,
                    DiffType::Added | DiffType::Removed | DiffType::TypeChanged
                )
            })
            .count();

        let behavioral_changes = entries
            .iter()
            .filter(|e| e.risk_level >= RiskLevel::Medium)
            .count();

        ConfigDiff {
            total_changes: entries.len(),
            structural_changes,
            behavioral_changes,
            regression_required: overall_risk.regression_required(),
            overall_risk,
            entries,
        }
    }

    /// Classify risk for a config key.
    fn classify_risk(key: &str) -> RiskLevel {
        for (pattern, risk) in RISK_RULES {
            if key.contains(pattern) {
                return *risk;
            }
        }
        RiskLevel::Low // Default: low risk for unknown keys
    }

    /// Quick check: does this change require regression?
    pub fn requires_regression(
        old: &HashMap<String, String>,
        new: &HashMap<String, String>,
    ) -> bool {
        Self::diff(old, new).regression_required
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_config(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn test_no_diff() {
        let config = make_config(&[("key", "value")]);
        let diff = ConfigDiffEngine::diff(&config, &config);
        assert!(diff.is_empty());
        assert_eq!(diff.overall_risk, RiskLevel::None);
        assert!(!diff.regression_required);
    }

    #[test]
    fn test_modified_value() {
        let old = make_config(&[("energy_cap", "0.8")]);
        let new = make_config(&[("energy_cap", "0.9")]);
        let diff = ConfigDiffEngine::diff(&old, &new);
        assert_eq!(diff.total_changes, 1);
        assert_eq!(diff.entries[0].diff_type, DiffType::Modified);
        assert_eq!(diff.entries[0].risk_level, RiskLevel::Medium);
        assert!(diff.regression_required);
    }

    #[test]
    fn test_added_removed() {
        let old = make_config(&[("key_a", "1")]);
        let new = make_config(&[("key_b", "2")]);
        let diff = ConfigDiffEngine::diff(&old, &new);
        assert_eq!(diff.total_changes, 2); // 1 removed + 1 added
        assert_eq!(diff.structural_changes, 2);
    }

    #[test]
    fn test_critical_change() {
        let old = make_config(&[("sample_rate", "48000")]);
        let new = make_config(&[("sample_rate", "44100")]);
        let diff = ConfigDiffEngine::diff(&old, &new);
        assert_eq!(diff.overall_risk, RiskLevel::Critical);
        assert!(diff.regression_required);
    }

    #[test]
    fn test_risk_level_ordering() {
        assert!(RiskLevel::Critical > RiskLevel::High);
        assert!(RiskLevel::High > RiskLevel::Medium);
        assert!(RiskLevel::Medium > RiskLevel::Low);
        assert!(RiskLevel::Low > RiskLevel::None);
    }

    #[test]
    fn test_requires_regression_quick_check() {
        let old = make_config(&[("sam_archetype", "balanced")]);
        let new = make_config(&[("sam_archetype", "volatile")]);
        assert!(ConfigDiffEngine::requires_regression(&old, &new));
    }
}

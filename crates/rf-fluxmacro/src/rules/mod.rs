// ============================================================================
// rf-fluxmacro — Rules Module
// ============================================================================
// FM-9: Rule loader — loads JSON rule files into typed structs.
// ============================================================================

pub mod naming_rules;
pub mod mechanics_map;
pub mod loudness_targets;
pub mod adb_templates;

use std::path::Path;

use crate::error::FluxMacroError;

use naming_rules::NamingRuleSet;
use mechanics_map::MechanicsMap;
use loudness_targets::LoudnessTargets;
use adb_templates::AdbTemplates;

/// All loaded rules for a macro execution.
#[derive(Debug, Clone)]
pub struct RuleSet {
    pub naming: NamingRuleSet,
    pub mechanics: MechanicsMap,
    pub loudness: LoudnessTargets,
    pub adb_templates: AdbTemplates,
}

impl RuleSet {
    /// Load all rules from the rules directory.
    /// Falls back to defaults if files are missing.
    pub fn load(rules_dir: &Path) -> Result<Self, FluxMacroError> {
        let naming = load_or_default(rules_dir, "naming_rules.json", NamingRuleSet::default)?;
        let mechanics = load_or_default(rules_dir, "mechanics_map.json", MechanicsMap::default)?;
        let loudness =
            load_or_default(rules_dir, "loudness_targets.json", LoudnessTargets::default)?;
        let adb_templates =
            load_or_default(rules_dir, "adb_templates.json", AdbTemplates::default)?;

        Ok(Self {
            naming,
            mechanics,
            loudness,
            adb_templates,
        })
    }

    /// Load all rules using built-in defaults (no files needed).
    pub fn defaults() -> Self {
        Self {
            naming: NamingRuleSet::default(),
            mechanics: MechanicsMap::default(),
            loudness: LoudnessTargets::default(),
            adb_templates: AdbTemplates::default(),
        }
    }
}

/// Load a rule from JSON file, or fall back to default if file doesn't exist.
fn load_or_default<T: serde::de::DeserializeOwned>(
    dir: &Path,
    filename: &str,
    default_fn: fn() -> T,
) -> Result<T, FluxMacroError> {
    let path = dir.join(filename);
    if path.exists() {
        let content = std::fs::read_to_string(&path)
            .map_err(|e| FluxMacroError::FileRead(path.clone(), e))?;
        serde_json::from_str(&content).map_err(|e| FluxMacroError::RuleLoadError {
            path,
            reason: format!("{e}"),
        })
    } else {
        Ok(default_fn())
    }
}

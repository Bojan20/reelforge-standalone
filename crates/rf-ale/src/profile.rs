//! Profile System
//!
//! Load and save ALE profiles (complete configurations) from/to JSON.
//! Supports versioning and migration.

use crate::context::{Context, ContextRegistry};
use crate::rules::{Rule, RuleRegistry};
use crate::stability::StabilityConfig;
use crate::transitions::{TransitionProfile, TransitionRegistry};
use crate::{AleError, AleResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Profile format version
pub const PROFILE_VERSION: &str = "2.0";

/// Asset manifest entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssetEntry {
    /// Asset identifier
    pub id: String,
    /// File path (relative to project)
    pub path: String,
    /// File size in bytes
    #[serde(default)]
    pub size_bytes: u64,
}

/// Asset manifest
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AssetManifest {
    /// Audio tracks
    #[serde(default)]
    pub tracks: Vec<AssetEntry>,
    /// Stinger audio files
    #[serde(default)]
    pub stingers: Vec<AssetEntry>,
}

/// Profile metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileMetadata {
    /// Game name
    #[serde(default)]
    pub game_name: String,
    /// Game identifier
    #[serde(default)]
    pub game_id: String,
    /// Target platforms
    #[serde(default)]
    pub target_platforms: Vec<String>,
    /// Audio budget in MB
    #[serde(default)]
    pub audio_budget_mb: u32,
}

impl Default for ProfileMetadata {
    fn default() -> Self {
        Self {
            game_name: String::new(),
            game_id: String::new(),
            target_platforms: vec!["desktop".to_string(), "mobile".to_string()],
            audio_budget_mb: 150,
        }
    }
}

/// Complete ALE profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AleProfile {
    /// Profile format version
    pub version: String,
    /// Format identifier
    #[serde(default = "default_format")]
    pub format: String,
    /// Creation timestamp
    #[serde(default)]
    pub created: String,
    /// Last modified timestamp
    #[serde(default)]
    pub modified: String,
    /// Author name
    #[serde(default)]
    pub author: String,
    /// Profile metadata
    #[serde(default)]
    pub metadata: ProfileMetadata,
    /// Contexts
    pub contexts: HashMap<String, Context>,
    /// Rules
    #[serde(default)]
    pub rules: Vec<Rule>,
    /// Transition profiles
    #[serde(default)]
    pub transitions: HashMap<String, TransitionProfile>,
    /// Stability configuration
    #[serde(default)]
    pub stability: StabilityConfig,
    /// Asset manifest
    #[serde(default)]
    pub asset_manifest: AssetManifest,
}

fn default_format() -> String {
    "ale_profile".to_string()
}

impl Default for AleProfile {
    fn default() -> Self {
        Self {
            version: PROFILE_VERSION.to_string(),
            format: "ale_profile".to_string(),
            created: String::new(),
            modified: String::new(),
            author: String::new(),
            metadata: ProfileMetadata::default(),
            contexts: HashMap::new(),
            rules: Vec::new(),
            transitions: HashMap::new(),
            stability: StabilityConfig::default(),
            asset_manifest: AssetManifest::default(),
        }
    }
}

impl AleProfile {
    /// Create a new empty profile
    pub fn new() -> Self {
        Self::default()
    }

    /// Create profile from registries
    pub fn from_registries(
        contexts: &ContextRegistry,
        rules: &RuleRegistry,
        transitions: &TransitionRegistry,
        stability: &StabilityConfig,
    ) -> Self {
        let mut profile = Self::new();

        // Copy contexts
        for id in contexts.context_ids() {
            if let Some(ctx) = contexts.get(id) {
                profile.contexts.insert(id.to_string(), ctx.clone());
            }
        }

        // Copy rules
        profile.rules = rules.all().to_vec();

        // Copy transitions
        for id in transitions.profile_ids() {
            if let Some(t) = transitions.get(id) {
                profile.transitions.insert(id.to_string(), t.clone());
            }
        }

        // Copy stability
        profile.stability = stability.clone();

        profile
    }

    /// Load profile from JSON string
    pub fn from_json(json: &str) -> AleResult<Self> {
        let raw: serde_json::Value = serde_json::from_str(json)?;

        // Check version and migrate if needed
        let version = raw["version"].as_str().unwrap_or("1.0");
        let profile = match version {
            "1.0" => Self::migrate_v1_to_v2(raw)?,
            "2.0" => serde_json::from_value(raw)?,
            _ => {
                return Err(AleError::ProfileError(format!(
                    "Unknown profile version: {}",
                    version
                )))
            }
        };

        Ok(profile)
    }

    /// Save profile to JSON string
    pub fn to_json(&self) -> AleResult<String> {
        Ok(serde_json::to_string_pretty(self)?)
    }

    /// Save profile to compact JSON
    pub fn to_json_compact(&self) -> AleResult<String> {
        Ok(serde_json::to_string(self)?)
    }

    /// Migrate v1 profile to v2
    fn migrate_v1_to_v2(mut v1: serde_json::Value) -> AleResult<Self> {
        // Add prediction to stability if missing
        if v1["stability"]["prediction"].is_null() {
            v1["stability"]["prediction"] = serde_json::json!({
                "enabled": false,
                "horizon_ms": 2000,
                "confidence_threshold": 0.7
            });
        }

        // Migrate old fade_time_ms to new structure
        if let Some(contexts) = v1["contexts"].as_object_mut() {
            for (_id, context) in contexts.iter_mut() {
                if let Some(fade_time) = context["fade_time_ms"].take().as_u64()
                    && context["entry_policy"]["transition"].is_null() {
                        context["entry_policy"]["transition"] = serde_json::json!({
                            "fade_in": {
                                "duration_ms": fade_time,
                                "curve": "ease_out_quad"
                            }
                        });
                    }
            }
        }

        v1["version"] = serde_json::json!("2.0");

        Ok(serde_json::from_value(v1)?)
    }

    /// Validate profile
    pub fn validate(&self) -> Result<(), Vec<String>> {
        let mut errors = Vec::new();

        // Validate contexts
        for (id, context) in &self.contexts {
            if let Err(e) = context.validate() {
                errors.push(format!("Context '{}': {}", id, e));
            }
        }

        // Validate rules reference valid contexts
        for rule in &self.rules {
            for ctx_id in &rule.contexts {
                if !self.contexts.contains_key(ctx_id) {
                    errors.push(format!(
                        "Rule '{}' references unknown context '{}'",
                        rule.id, ctx_id
                    ));
                }
            }
        }

        // Validate transition references
        for rule in &self.rules {
            if let Some(ref t_id) = rule.transition
                && !self.transitions.contains_key(t_id) && t_id != "default" {
                    errors.push(format!(
                        "Rule '{}' references unknown transition '{}'",
                        rule.id, t_id
                    ));
                }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }

    /// Extract registries from profile
    pub fn to_registries(
        &self,
    ) -> (
        ContextRegistry,
        RuleRegistry,
        TransitionRegistry,
        StabilityConfig,
    ) {
        let mut contexts = ContextRegistry::new();
        for context in self.contexts.values() {
            contexts.register(context.clone());
        }

        let mut rules = RuleRegistry::new();
        for rule in &self.rules {
            rules.add(rule.clone());
        }

        let mut transitions = TransitionRegistry::with_builtins();
        for profile in self.transitions.values() {
            transitions.register(profile.clone());
        }

        (contexts, rules, transitions, self.stability.clone())
    }

    /// Add a context
    pub fn add_context(&mut self, context: Context) {
        self.contexts.insert(context.id.clone(), context);
    }

    /// Add a rule
    pub fn add_rule(&mut self, rule: Rule) {
        self.rules.push(rule);
    }

    /// Add a transition profile
    pub fn add_transition(&mut self, profile: TransitionProfile) {
        self.transitions.insert(profile.id.clone(), profile);
    }

    /// Get context count
    pub fn context_count(&self) -> usize {
        self.contexts.len()
    }

    /// Get rule count
    pub fn rule_count(&self) -> usize {
        self.rules.len()
    }

    /// Get transition count
    pub fn transition_count(&self) -> usize {
        self.transitions.len()
    }
}

/// Profile builder for fluent API
pub struct ProfileBuilder {
    profile: AleProfile,
}

impl ProfileBuilder {
    pub fn new() -> Self {
        Self {
            profile: AleProfile::new(),
        }
    }

    pub fn author(mut self, author: &str) -> Self {
        self.profile.author = author.to_string();
        self
    }

    pub fn game_name(mut self, name: &str) -> Self {
        self.profile.metadata.game_name = name.to_string();
        self
    }

    pub fn game_id(mut self, id: &str) -> Self {
        self.profile.metadata.game_id = id.to_string();
        self
    }

    pub fn context(mut self, context: Context) -> Self {
        self.profile.add_context(context);
        self
    }

    pub fn rule(mut self, rule: Rule) -> Self {
        self.profile.add_rule(rule);
        self
    }

    pub fn transition(mut self, profile: TransitionProfile) -> Self {
        self.profile.add_transition(profile);
        self
    }

    pub fn stability(mut self, config: StabilityConfig) -> Self {
        self.profile.stability = config;
        self
    }

    pub fn build(self) -> AleProfile {
        self.profile
    }
}

impl Default for ProfileBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::Layer;
    use crate::rules::{Action, Condition, SimpleCondition, ComparisonOp};

    #[test]
    fn test_profile_serialization() {
        let mut profile = AleProfile::new();
        profile.author = "Test Author".to_string();
        profile.metadata.game_name = "Test Game".to_string();

        let mut context = Context::new("BASE", "Base Game");
        context.add_layer(Layer::new(0, "L1", 0.15));
        profile.add_context(context);

        let json = profile.to_json().unwrap();
        assert!(json.contains("Test Author"));
        assert!(json.contains("Test Game"));
        assert!(json.contains("BASE"));

        let loaded = AleProfile::from_json(&json).unwrap();
        assert_eq!(loaded.author, "Test Author");
        assert!(loaded.contexts.contains_key("BASE"));
    }

    #[test]
    fn test_profile_validation() {
        let mut profile = AleProfile::new();

        // Add valid context with at least one layer
        let mut context = Context::new("BASE", "Base Game");
        context.add_layer(Layer::new(0, "base_layer", 1.0));
        profile.add_context(context);

        // Add rule referencing valid context
        let rule = Rule::new(
            "test_rule",
            "Test Rule",
            Condition::Simple(SimpleCondition::new("winTier", ComparisonOp::Gte, 3.0)),
            Action::step_up(1),
        )
        .for_context("BASE");
        profile.add_rule(rule);

        assert!(profile.validate().is_ok());

        // Add rule referencing invalid context
        let bad_rule = Rule::new(
            "bad_rule",
            "Bad Rule",
            Condition::Simple(SimpleCondition::new("winTier", ComparisonOp::Gte, 3.0)),
            Action::step_up(1),
        )
        .for_context("NONEXISTENT");
        profile.add_rule(bad_rule);

        let validation = profile.validate();
        assert!(validation.is_err());
        let errors = validation.unwrap_err();
        assert!(errors
            .iter()
            .any(|e| e.contains("unknown context 'NONEXISTENT'")));
    }

    #[test]
    fn test_profile_builder() {
        let profile = ProfileBuilder::new()
            .author("Builder Test")
            .game_name("Builder Game")
            .context(Context::new("BASE", "Base"))
            .stability(StabilityConfig::default())
            .build();

        assert_eq!(profile.author, "Builder Test");
        assert_eq!(profile.metadata.game_name, "Builder Game");
        assert!(profile.contexts.contains_key("BASE"));
    }

    #[test]
    fn test_to_registries() {
        let mut profile = AleProfile::new();

        let context = Context::new("BASE", "Base Game");
        profile.add_context(context);

        let rule = Rule::new(
            "test_rule",
            "Test Rule",
            Condition::Simple(SimpleCondition::new("winTier", ComparisonOp::Gte, 3.0)),
            Action::step_up(1),
        );
        profile.add_rule(rule);

        let (contexts, rules, transitions, _stability) = profile.to_registries();

        assert!(contexts.get("BASE").is_some());
        assert_eq!(rules.len(), 1);
        assert!(transitions.get("default").is_some());
    }
}

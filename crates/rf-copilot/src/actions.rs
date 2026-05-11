//! Action trait — reversible auto-applicable Co-Pilot suggestions (4.1.1)
//!
//! Each auto-applicable `CopilotSuggestion` has a corresponding `Action`
//! that deterministically mutates an `AudioProjectSpec`. Undo is handled
//! by the caller saving the pre-apply project snapshot (Command pattern).
//!
//! ## Architecture
//!
//! ```text
//! CopilotSuggestion { rule_id, auto_applicable: true }
//!          │
//!          ▼
//! ActionRegistry::find(rule_id) → Box<dyn Action>
//!          │
//!          ▼
//! action.apply(&mut project) → mutates project in-place
//! ```
//!
//! ## Auto-applicable rules
//!
//! | Rule ID  | Action                        | Effect                                   |
//! |----------|-------------------------------|------------------------------------------|
//! | R-VB-1   | `BumpVoiceBudget`             | Sets budget = ceil(peak * 1.3)           |
//! | R-VB-2   | `BumpVoiceBudget`             | Sets budget = benchmark recommended      |
//! | R-VB-3   | `SetMinVoiceBudget`           | Sets budget = max(16, current)           |
//! | R-LC-1   | `SetReelSpinLoop`             | Sets can_loop = true on spin events      |
//! | R-LC-2   | `SetAmbientLoop`              | Sets can_loop = true on ambient events   |
//! | R-FA-1   | `PromoteFeatureTriggerTier`   | Sets feature trigger tier to "prominent" |
//! | R-PO-1   | `SetRequiredEventWeight`      | Sets audio_weight = 0.8 on low-priority  |

use crate::project::{AudioEventSpec, AudioProjectSpec};

// ─────────────────────────────────────────────────────────────────────────────
// Action trait
// ─────────────────────────────────────────────────────────────────────────────

/// A reversible, deterministic action that mutates an `AudioProjectSpec`.
///
/// Undo is achieved by the caller:
/// 1. Clone the project before calling `apply`
/// 2. If user wants to undo: replace current project with the saved clone
///
/// This matches how Dart's undo stack works — the project state is the undo token.
pub trait Action: Send + Sync {
    /// Stable rule ID matching `CopilotSuggestion::rule_id`
    fn rule_id(&self) -> &str;

    /// Short human-readable description of what this action will do.
    /// Written in past tense (after apply): "Set voice budget to 32".
    fn description(&self, project: &AudioProjectSpec) -> String;

    /// Apply the action in-place. Returns `Err` if preconditions are not met.
    fn apply(&self, project: &mut AudioProjectSpec) -> Result<String, String>;
}

// ─────────────────────────────────────────────────────────────────────────────
// ActionRegistry — dispatch table
// ─────────────────────────────────────────────────────────────────────────────

/// Dispatch table: maps rule_id → concrete `Action` implementation.
pub struct ActionRegistry;

impl ActionRegistry {
    /// Find the `Action` for a given rule_id.
    ///
    /// Returns `None` if:
    /// - rule_id is unknown
    /// - The rule has no auto-applicable action
    pub fn find(rule_id: &str) -> Option<Box<dyn Action>> {
        match rule_id {
            "R-VB-1" => Some(Box::new(BumpVoiceBudget { mode: BudgetMode::PeakBased })),
            "R-VB-2" => Some(Box::new(BumpVoiceBudget { mode: BudgetMode::BenchmarkMin })),
            "R-VB-3" => Some(Box::new(BumpVoiceBudget { mode: BudgetMode::AbsoluteMin })),
            "R-LC-1" => Some(Box::new(SetReelSpinLoop)),
            "R-LC-2" => Some(Box::new(SetAmbientLoop)),
            "R-FA-1" => Some(Box::new(PromoteFeatureTriggerTier)),
            "R-PO-1" => Some(Box::new(SetRequiredEventWeight)),
            _        => None,
        }
    }

    /// All rule IDs that have a registered auto-applicable action.
    pub fn auto_applicable_ids() -> &'static [&'static str] {
        &["R-VB-1", "R-VB-2", "R-VB-3", "R-LC-1", "R-LC-2", "R-FA-1", "R-PO-1"]
    }

    /// Returns true if this rule_id has an auto-applicable action.
    pub fn is_auto_applicable(rule_id: &str) -> bool {
        Self::auto_applicable_ids().contains(&rule_id)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Concrete Action implementations
// ─────────────────────────────────────────────────────────────────────────────

/// Voice budget strategy for `BumpVoiceBudget`
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BudgetMode {
    /// R-VB-1: Set budget = ceil(estimated_peak_voices * 1.3)
    PeakBased,
    /// R-VB-2: Set budget = 32 (standard industry minimum for mid-tier slots)
    BenchmarkMin,
    /// R-VB-3: Set budget = max(16, current_budget)
    AbsoluteMin,
}

/// Actions for R-VB-1 / R-VB-2 / R-VB-3: bump voice budget
#[derive(Debug, Clone)]
pub struct BumpVoiceBudget {
    pub mode: BudgetMode,
}

impl Action for BumpVoiceBudget {
    fn rule_id(&self) -> &str {
        match self.mode {
            BudgetMode::PeakBased    => "R-VB-1",
            BudgetMode::BenchmarkMin => "R-VB-2",
            BudgetMode::AbsoluteMin  => "R-VB-3",
        }
    }

    fn description(&self, project: &AudioProjectSpec) -> String {
        let new_budget = self.compute_new_budget(project);
        match self.mode {
            BudgetMode::PeakBased    => format!("Set voice budget to {new_budget} (1.3× estimated peak)"),
            BudgetMode::BenchmarkMin => format!("Set voice budget to {new_budget} (industry benchmark minimum)"),
            BudgetMode::AbsoluteMin  => format!("Set voice budget to {new_budget} (absolute minimum 16)"),
        }
    }

    fn apply(&self, project: &mut AudioProjectSpec) -> Result<String, String> {
        let new_budget = self.compute_new_budget(project);
        if new_budget <= project.voice_budget {
            return Err(format!(
                "New budget ({new_budget}) is not greater than current ({})",
                project.voice_budget
            ));
        }
        let old = project.voice_budget;
        project.voice_budget = new_budget;
        Ok(format!("Voice budget: {} → {}", old, new_budget))
    }
}

impl BumpVoiceBudget {
    fn compute_new_budget(&self, project: &AudioProjectSpec) -> u8 {
        match self.mode {
            BudgetMode::PeakBased => {
                if let Some(peak) = project.estimated_peak_voices {
                    (peak * 1.3).ceil() as u8
                } else {
                    32
                }
            }
            BudgetMode::BenchmarkMin => 32u8.max(project.voice_budget),
            BudgetMode::AbsoluteMin  => 16u8.max(project.voice_budget),
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Action for R-LC-1: set can_loop = true on reel spin events
#[derive(Debug, Clone, Default)]
pub struct SetReelSpinLoop;

impl Action for SetReelSpinLoop {
    fn rule_id(&self) -> &str { "R-LC-1" }

    fn description(&self, project: &AudioProjectSpec) -> String {
        let affected: Vec<&str> = project.audio_events.iter()
            .filter(|e| is_spin_sound(e) && !e.can_loop)
            .map(|e| e.name.as_str())
            .collect();
        if affected.is_empty() {
            "No non-looping reel spin events found".to_string()
        } else {
            format!("Set can_loop = true on: {}", affected.join(", "))
        }
    }

    fn apply(&self, project: &mut AudioProjectSpec) -> Result<String, String> {
        let mut changed = Vec::new();
        for event in &mut project.audio_events {
            if is_spin_sound(event) && !event.can_loop {
                event.can_loop = true;
                changed.push(event.name.clone());
            }
        }
        if changed.is_empty() {
            Err("No non-looping reel spin events found".into())
        } else {
            Ok(format!("Set can_loop = true on: {}", changed.join(", ")))
        }
    }
}

fn is_spin_sound(e: &AudioEventSpec) -> bool {
    let n = e.name.to_lowercase();
    n.contains("reel_spin") || n.contains("spin_loop") || n.contains("reels_spinning")
}

// ─────────────────────────────────────────────────────────────────────────────

/// Action for R-LC-2: set can_loop = true on ambient/bg events
#[derive(Debug, Clone, Default)]
pub struct SetAmbientLoop;

impl Action for SetAmbientLoop {
    fn rule_id(&self) -> &str { "R-LC-2" }

    fn description(&self, project: &AudioProjectSpec) -> String {
        let affected: Vec<&str> = project.audio_events.iter()
            .filter(|e| is_ambient_sound(e) && !e.can_loop)
            .map(|e| e.name.as_str())
            .collect();
        if affected.is_empty() {
            "No non-looping ambient events found".to_string()
        } else {
            format!("Set can_loop = true on: {}", affected.join(", "))
        }
    }

    fn apply(&self, project: &mut AudioProjectSpec) -> Result<String, String> {
        let mut changed = Vec::new();
        for event in &mut project.audio_events {
            if is_ambient_sound(event) && !event.can_loop {
                event.can_loop = true;
                changed.push(event.name.clone());
            }
        }
        if changed.is_empty() {
            Err("No non-looping ambient events found".into())
        } else {
            Ok(format!("Set can_loop = true on: {}", changed.join(", ")))
        }
    }
}

fn is_ambient_sound(e: &AudioEventSpec) -> bool {
    let n = e.name.to_lowercase();
    n.contains("ambient") || n.contains("bg_music") || n.contains("backing")
}

// ─────────────────────────────────────────────────────────────────────────────

/// Action for R-FA-1: promote feature trigger tier to "prominent"
#[derive(Debug, Clone, Default)]
pub struct PromoteFeatureTriggerTier;

impl Action for PromoteFeatureTriggerTier {
    fn rule_id(&self) -> &str { "R-FA-1" }

    fn description(&self, project: &AudioProjectSpec) -> String {
        let affected: Vec<&str> = project.audio_events.iter()
            .filter(|e| e.category == "Feature"
                && e.name.contains("TRIGGER")
                && (e.tier == "subtle" || e.tier == "standard"))
            .map(|e| e.name.as_str())
            .collect();
        if affected.is_empty() {
            "No under-tiered feature trigger events found".to_string()
        } else {
            format!("Promote to 'prominent': {}", affected.join(", "))
        }
    }

    fn apply(&self, project: &mut AudioProjectSpec) -> Result<String, String> {
        let mut changed = Vec::new();
        for event in &mut project.audio_events {
            if event.category == "Feature"
                && event.name.contains("TRIGGER")
                && (event.tier == "subtle" || event.tier == "standard")
            {
                event.tier = "prominent".to_string();
                changed.push(event.name.clone());
            }
        }
        if changed.is_empty() {
            Err("No under-tiered feature trigger events found".into())
        } else {
            Ok(format!("Promoted to 'prominent': {}", changed.join(", ")))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Action for R-PO-1: set audio_weight = 0.8 on required events with low weight
#[derive(Debug, Clone, Default)]
pub struct SetRequiredEventWeight;

const MIN_REQUIRED_WEIGHT: f64 = 0.8;

impl Action for SetRequiredEventWeight {
    fn rule_id(&self) -> &str { "R-PO-1" }

    fn description(&self, project: &AudioProjectSpec) -> String {
        let affected: Vec<&str> = project.audio_events.iter()
            .filter(|e| e.is_required && e.audio_weight < 0.5)
            .map(|e| e.name.as_str())
            .collect();
        if affected.is_empty() {
            "No required events with low audio_weight found".to_string()
        } else {
            format!("Set audio_weight = {} on: {}", MIN_REQUIRED_WEIGHT, affected.join(", "))
        }
    }

    fn apply(&self, project: &mut AudioProjectSpec) -> Result<String, String> {
        let mut changed = Vec::new();
        for event in &mut project.audio_events {
            if event.is_required && event.audio_weight < 0.5 {
                event.audio_weight = MIN_REQUIRED_WEIGHT;
                changed.push(event.name.clone());
            }
        }
        if changed.is_empty() {
            Err("No required events with low audio_weight found".into())
        } else {
            Ok(format!(
                "Set audio_weight = {} on: {}",
                MIN_REQUIRED_WEIGHT,
                changed.join(", ")
            ))
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::project::{AudioEventSpec, AudioProjectSpec};

    fn make_event(
        name: &str, cat: &str, tier: &str,
        required: bool, loops: bool, weight: f64,
    ) -> AudioEventSpec {
        AudioEventSpec {
            name:               name.to_string(),
            category:           cat.to_string(),
            tier:               tier.to_string(),
            duration_ms:        500,
            voice_count:        2,
            is_required:        required,
            can_loop:           loops,
            trigger_probability: 0.5,
            audio_weight:       weight,
            rtp_contribution:   0.0,
        }
    }

    fn base_project() -> AudioProjectSpec {
        AudioProjectSpec {
            game_name:             "Test".to_string(),
            game_id:               "test".to_string(),
            rtp_target:            96.5,
            volatility:            "MEDIUM".to_string(),
            voice_budget:          24,
            reels:                 5,
            rows:                  3,
            win_mechanism:         "20 paylines".to_string(),
            audio_events:          vec![],
            estimated_peak_voices: None,
        }
    }

    // ─── ActionRegistry ─────────────────────────────────────────────────────

    #[test]
    fn test_registry_finds_known_rules() {
        for id in ActionRegistry::auto_applicable_ids() {
            assert!(
                ActionRegistry::find(id).is_some(),
                "Expected action for rule_id = {id}"
            );
        }
    }

    #[test]
    fn test_registry_returns_none_for_unknown() {
        assert!(ActionRegistry::find("R-MA-1").is_none());
        assert!(ActionRegistry::find("R-WT-2").is_none());
        assert!(ActionRegistry::find("UNKNOWN").is_none());
    }

    #[test]
    fn test_is_auto_applicable() {
        assert!(ActionRegistry::is_auto_applicable("R-VB-1"));
        assert!(ActionRegistry::is_auto_applicable("R-LC-1"));
        assert!(!ActionRegistry::is_auto_applicable("R-MA-1"));
        assert!(!ActionRegistry::is_auto_applicable("R-WT-2"));
    }

    // ─── BumpVoiceBudget ────────────────────────────────────────────────────

    #[test]
    fn test_bump_voice_budget_peak_based() {
        let mut project = base_project();
        project.voice_budget = 10;
        project.estimated_peak_voices = Some(9.8);

        let action = BumpVoiceBudget { mode: BudgetMode::PeakBased };
        let result = action.apply(&mut project);
        assert!(result.is_ok(), "apply should succeed: {:?}", result);
        // ceil(9.8 * 1.3) = ceil(12.74) = 13
        assert_eq!(project.voice_budget, 13);
    }

    #[test]
    fn test_bump_voice_budget_absolute_min() {
        let mut project = base_project();
        project.voice_budget = 8;

        let action = BumpVoiceBudget { mode: BudgetMode::AbsoluteMin };
        let result = action.apply(&mut project);
        assert!(result.is_ok());
        assert_eq!(project.voice_budget, 16);
    }

    #[test]
    fn test_bump_voice_budget_benchmark_min() {
        let mut project = base_project();
        project.voice_budget = 24;

        let action = BumpVoiceBudget { mode: BudgetMode::BenchmarkMin };
        let result = action.apply(&mut project);
        assert!(result.is_ok());
        assert_eq!(project.voice_budget, 32);
    }

    #[test]
    fn test_bump_voice_budget_no_op_when_already_above() {
        let mut project = base_project();
        project.voice_budget = 40;

        let action = BumpVoiceBudget { mode: BudgetMode::AbsoluteMin };
        let result = action.apply(&mut project);
        assert!(result.is_err(), "Should return Err when budget already >= 16");
        assert_eq!(project.voice_budget, 40, "Budget unchanged");
    }

    // ─── SetReelSpinLoop ────────────────────────────────────────────────────

    #[test]
    fn test_set_reel_spin_loop_applies() {
        let mut project = base_project();
        project.audio_events.push(make_event("REEL_SPIN", "BaseGame", "subtle", false, false, 1.0));
        project.audio_events.push(make_event("REEL_STOP", "BaseGame", "subtle", false, false, 0.9));

        let action = SetReelSpinLoop;
        let result = action.apply(&mut project);
        assert!(result.is_ok());

        let spin = project.audio_events.iter().find(|e| e.name == "REEL_SPIN").unwrap();
        let stop = project.audio_events.iter().find(|e| e.name == "REEL_STOP").unwrap();
        assert!(spin.can_loop,  "REEL_SPIN must be loop");
        assert!(!stop.can_loop, "REEL_STOP must NOT be changed");
    }

    #[test]
    fn test_set_reel_spin_loop_no_op_when_already_loop() {
        let mut project = base_project();
        project.audio_events.push(make_event("REEL_SPIN", "BaseGame", "subtle", false, true, 1.0));

        let action = SetReelSpinLoop;
        let result = action.apply(&mut project);
        assert!(result.is_err(), "No change expected when already loop");
    }

    // ─── SetAmbientLoop ─────────────────────────────────────────────────────

    #[test]
    fn test_set_ambient_loop_applies() {
        let mut project = base_project();
        project.audio_events.push(make_event("AMBIENT_BED", "BaseGame", "subtle", false, false, 0.5));
        project.audio_events.push(make_event("WIN_1", "Win", "subtle", false, false, 0.8));

        let action = SetAmbientLoop;
        let result = action.apply(&mut project);
        assert!(result.is_ok());

        let ambient = project.audio_events.iter().find(|e| e.name == "AMBIENT_BED").unwrap();
        let win    = project.audio_events.iter().find(|e| e.name == "WIN_1").unwrap();
        assert!(ambient.can_loop, "AMBIENT_BED must be loop");
        assert!(!win.can_loop,    "WIN_1 must NOT be changed");
    }

    // ─── PromoteFeatureTriggerTier ──────────────────────────────────────────

    #[test]
    fn test_promote_feature_trigger_tier() {
        let mut project = base_project();
        // "TRIGGER" in name + Feature cat + low tier → promoted
        project.audio_events.push(make_event("FEATURE_TRIGGER", "Feature", "subtle", false, false, 1.0));
        // Also contains "TRIGGER" → promoted (retrigger is also a trigger)
        project.audio_events.push(make_event("FEATURE_RETRIGGER", "Feature", "standard", false, false, 0.9));
        // Win category → unchanged
        project.audio_events.push(make_event("WIN_1", "Win", "subtle", false, false, 0.8));
        // Already flagship → unchanged (doesn't match subtle/standard filter)
        project.audio_events.push(make_event("BONUS_TRIGGER", "Feature", "flagship", false, false, 1.0));

        let action = PromoteFeatureTriggerTier;
        let result = action.apply(&mut project);
        assert!(result.is_ok());

        let trig   = project.audio_events.iter().find(|e| e.name == "FEATURE_TRIGGER").unwrap();
        let retrig = project.audio_events.iter().find(|e| e.name == "FEATURE_RETRIGGER").unwrap();
        let win    = project.audio_events.iter().find(|e| e.name == "WIN_1").unwrap();
        let bonus  = project.audio_events.iter().find(|e| e.name == "BONUS_TRIGGER").unwrap();

        assert_eq!(trig.tier,   "prominent", "FEATURE_TRIGGER: subtle → prominent");
        assert_eq!(retrig.tier, "prominent", "FEATURE_RETRIGGER: standard → prominent");
        assert_eq!(win.tier,    "subtle",    "WIN_1: wrong category, unchanged");
        assert_eq!(bonus.tier,  "flagship",  "BONUS_TRIGGER: already flagship, unchanged");
    }

    // ─── SetRequiredEventWeight ─────────────────────────────────────────────

    #[test]
    fn test_set_required_event_weight() {
        let mut project = base_project();
        // Required + low weight → should be bumped
        project.audio_events.push(make_event("SPIN_START", "BaseGame", "subtle", true, false, 0.3));
        // Required + adequate weight → unchanged
        project.audio_events.push(make_event("REEL_STOP", "BaseGame", "subtle", true, false, 0.9));
        // Not required + low weight → unchanged
        project.audio_events.push(make_event("WIN_1", "Win", "subtle", false, false, 0.2));

        let action = SetRequiredEventWeight;
        let result = action.apply(&mut project);
        assert!(result.is_ok());

        let spin_start = project.audio_events.iter().find(|e| e.name == "SPIN_START").unwrap();
        let reel_stop  = project.audio_events.iter().find(|e| e.name == "REEL_STOP").unwrap();
        let win1       = project.audio_events.iter().find(|e| e.name == "WIN_1").unwrap();

        assert!((spin_start.audio_weight - 0.8).abs() < f64::EPSILON, "SPIN_START bumped to 0.8");
        assert!((reel_stop.audio_weight  - 0.9).abs() < f64::EPSILON, "REEL_STOP unchanged");
        assert!((win1.audio_weight       - 0.2).abs() < f64::EPSILON, "WIN_1 unchanged (not required)");
    }

    // ─── Rule ID consistency ─────────────────────────────────────────────────

    #[test]
    fn test_action_rule_id_matches_registry_key() {
        let rules = ActionRegistry::auto_applicable_ids();
        for rule_id in rules {
            let action = ActionRegistry::find(rule_id).unwrap();
            assert_eq!(
                action.rule_id(), *rule_id,
                "Action rule_id() must match registry key for {rule_id}"
            );
        }
    }
}

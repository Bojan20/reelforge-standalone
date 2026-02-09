//! Middleware Event Definition
//!
//! Events are containers for actions that get executed together
//! when the event is posted.

use crate::action::MiddlewareAction;
use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT ID GENERATION
// ═══════════════════════════════════════════════════════════════════════════════

use std::sync::atomic::{AtomicU32, Ordering};

/// Global event ID counter
static NEXT_EVENT_ID: AtomicU32 = AtomicU32::new(1);

/// Generate unique event ID
pub fn generate_event_id() -> u32 {
    NEXT_EVENT_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDDLEWARE EVENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Middleware event definition
///
/// An event is a named container of actions that execute when the event
/// is posted. This is the core authoring unit in Wwise/FMOD style systems.
///
/// ## Example
///
/// ```rust
/// use rf_event::{MiddlewareEvent, MiddlewareAction, ActionType, FadeCurve};
///
/// // Create a "BigWin" event with multiple actions
/// let mut event = MiddlewareEvent::new(1, "BigWin_Start")
///     .with_category("Wins");
///
/// // Add actions
/// event.add_action(
///     MiddlewareAction::set_volume(1, 0.3, 0.2)  // Duck music
/// );
/// event.add_action(
///     MiddlewareAction::play(100, 2)  // Play jackpot sound
///         .with_priority(rf_event::ActionPriority::High)
/// );
/// event.add_action(
///     MiddlewareAction::play(101, 3)  // Play VO
///         .with_delay(0.5)  // 500ms delay
/// );
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MiddlewareEvent {
    /// Unique event ID
    pub id: u32,
    /// Event name (for lookup by name)
    pub name: String,
    /// Category for organization (e.g., "Music", "SFX", "VO")
    pub category: String,
    /// Description/notes
    pub description: Option<String>,
    /// Actions to execute when event is posted
    pub actions: Vec<MiddlewareAction>,
    /// Maximum instances of this event (0 = unlimited)
    pub max_instances: u32,
    /// What to do when max instances reached
    pub max_instance_behavior: MaxInstanceBehavior,
    /// Cooldown between posts (seconds, 0 = no cooldown)
    pub cooldown_secs: f32,
    /// Tags for filtering
    pub tags: Vec<String>,
}

/// Behavior when max instances is reached
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum MaxInstanceBehavior {
    /// Don't play new instance
    #[default]
    DiscardNewest = 0,
    /// Stop oldest instance, play new
    DiscardOldest = 1,
    /// Stop instance with lowest priority
    DiscardLowestPriority = 2,
    /// Always play (ignore limit)
    IgnoreLimit = 3,
}

impl Default for MiddlewareEvent {
    fn default() -> Self {
        Self {
            id: generate_event_id(),
            name: String::new(),
            category: "General".to_string(),
            description: None,
            actions: Vec::new(),
            max_instances: 0,
            max_instance_behavior: MaxInstanceBehavior::DiscardNewest,
            cooldown_secs: 0.0,
            tags: Vec::new(),
        }
    }
}

impl MiddlewareEvent {
    /// Create a new event with ID and name
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            ..Default::default()
        }
    }

    /// Create a new event with auto-generated ID
    pub fn new_auto(name: impl Into<String>) -> Self {
        Self {
            id: generate_event_id(),
            name: name.into(),
            ..Default::default()
        }
    }

    // === Builder methods ===

    /// Set category
    pub fn with_category(mut self, category: impl Into<String>) -> Self {
        self.category = category.into();
        self
    }

    /// Set description
    pub fn with_description(mut self, desc: impl Into<String>) -> Self {
        self.description = Some(desc.into());
        self
    }

    /// Set max instances
    pub fn with_max_instances(mut self, max: u32, behavior: MaxInstanceBehavior) -> Self {
        self.max_instances = max;
        self.max_instance_behavior = behavior;
        self
    }

    /// Set cooldown
    pub fn with_cooldown(mut self, cooldown_secs: f32) -> Self {
        self.cooldown_secs = cooldown_secs;
        self
    }

    /// Add a tag
    pub fn with_tag(mut self, tag: impl Into<String>) -> Self {
        self.tags.push(tag.into());
        self
    }

    /// Add multiple tags
    pub fn with_tags(mut self, tags: impl IntoIterator<Item = impl Into<String>>) -> Self {
        self.tags.extend(tags.into_iter().map(|t| t.into()));
        self
    }

    // === Action management ===

    /// Add an action to the event
    pub fn add_action(&mut self, action: MiddlewareAction) {
        self.actions.push(action);
    }

    /// Add action with auto-generated ID
    pub fn add_action_auto(&mut self, mut action: MiddlewareAction) {
        action.id = self.actions.len() as u32;
        self.actions.push(action);
    }

    /// Remove action by ID
    pub fn remove_action(&mut self, action_id: u32) -> Option<MiddlewareAction> {
        if let Some(pos) = self.actions.iter().position(|a| a.id == action_id) {
            Some(self.actions.remove(pos))
        } else {
            None
        }
    }

    /// Get action by ID
    pub fn get_action(&self, action_id: u32) -> Option<&MiddlewareAction> {
        self.actions.iter().find(|a| a.id == action_id)
    }

    /// Get mutable action by ID
    pub fn get_action_mut(&mut self, action_id: u32) -> Option<&mut MiddlewareAction> {
        self.actions.iter_mut().find(|a| a.id == action_id)
    }

    /// Sort actions by delay (for execution order)
    pub fn sort_actions_by_delay(&mut self) {
        self.actions.sort_by(|a, b| {
            a.delay_secs
                .partial_cmp(&b.delay_secs)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
    }

    /// Get actions sorted by delay (non-mutating)
    pub fn actions_by_delay(&self) -> Vec<&MiddlewareAction> {
        let mut sorted: Vec<_> = self.actions.iter().collect();
        sorted.sort_by(|a, b| {
            a.delay_secs
                .partial_cmp(&b.delay_secs)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        sorted
    }

    // === Query methods ===

    /// Check if event has any Play actions
    pub fn has_play_actions(&self) -> bool {
        self.actions.iter().any(|a| a.action_type.is_play_action())
    }

    /// Check if event has any Stop actions
    pub fn has_stop_actions(&self) -> bool {
        self.actions.iter().any(|a| a.action_type.is_stop_action())
    }

    /// Get total duration (max delay + max fade)
    pub fn total_duration_secs(&self) -> f32 {
        self.actions
            .iter()
            .map(|a| a.delay_secs + a.fade_time_secs)
            .fold(0.0, f32::max)
    }

    /// Get number of actions
    pub fn action_count(&self) -> usize {
        self.actions.len()
    }

    /// Check if event is empty
    pub fn is_empty(&self) -> bool {
        self.actions.is_empty()
    }

    /// Check if event has tag
    pub fn has_tag(&self, tag: &str) -> bool {
        self.tags.iter().any(|t| t == tag)
    }

    /// Get actions that execute immediately (no delay)
    pub fn immediate_actions(&self) -> impl Iterator<Item = &MiddlewareAction> {
        self.actions.iter().filter(|a| a.delay_secs == 0.0)
    }

    /// Get actions that have delay
    pub fn delayed_actions(&self) -> impl Iterator<Item = &MiddlewareAction> {
        self.actions.iter().filter(|a| a.delay_secs > 0.0)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT CATEGORY CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Common event categories (matching Dart kAllBuses)
pub mod categories {
    pub const GENERAL: &str = "General";
    pub const MUSIC: &str = "Music";
    pub const SFX: &str = "SFX";
    pub const VOICE: &str = "Voice";
    pub const UI: &str = "UI";
    pub const AMBIENCE: &str = "Ambience";
    pub const WINS: &str = "Wins";
    pub const VO: &str = "VO";
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::action::{ActionPriority, ActionType};
    use crate::curve::FadeCurve;

    #[test]
    fn test_event_creation() {
        let event = MiddlewareEvent::new(1, "Test_Event")
            .with_category("SFX")
            .with_description("Test event description");

        assert_eq!(event.id, 1);
        assert_eq!(event.name, "Test_Event");
        assert_eq!(event.category, "SFX");
        assert_eq!(
            event.description,
            Some("Test event description".to_string())
        );
    }

    #[test]
    fn test_add_actions() {
        let mut event = MiddlewareEvent::new(1, "Test");

        event.add_action(MiddlewareAction::play(100, 0).with_id(1));
        event.add_action(MiddlewareAction::play(101, 0).with_id(2).with_delay(0.5));
        event.add_action(MiddlewareAction::stop(None).with_id(3).with_delay(1.0));

        assert_eq!(event.action_count(), 3);
        assert!(event.has_play_actions());
        assert!(event.has_stop_actions());
    }

    #[test]
    fn test_sort_by_delay() {
        let mut event = MiddlewareEvent::new(1, "Test");

        event.add_action(MiddlewareAction::play(100, 0).with_delay(1.0));
        event.add_action(MiddlewareAction::play(101, 0).with_delay(0.0));
        event.add_action(MiddlewareAction::play(102, 0).with_delay(0.5));

        event.sort_actions_by_delay();

        assert_eq!(event.actions[0].delay_secs, 0.0);
        assert_eq!(event.actions[1].delay_secs, 0.5);
        assert_eq!(event.actions[2].delay_secs, 1.0);
    }

    #[test]
    fn test_total_duration() {
        let mut event = MiddlewareEvent::new(1, "Test");

        event.add_action(
            MiddlewareAction::play(100, 0)
                .with_delay(0.5)
                .with_fade(FadeCurve::Linear, 0.2),
        );
        event.add_action(MiddlewareAction::play(101, 0).with_delay(1.0));

        // Max duration = 0.5 + 0.2 = 0.7 or 1.0 + 0.0 = 1.0
        assert_eq!(event.total_duration_secs(), 1.0);
    }

    #[test]
    fn test_tags() {
        let event = MiddlewareEvent::new(1, "Test")
            .with_tag("important")
            .with_tags(["music", "loop"]);

        assert!(event.has_tag("important"));
        assert!(event.has_tag("music"));
        assert!(event.has_tag("loop"));
        assert!(!event.has_tag("sfx"));
    }

    #[test]
    fn test_max_instances() {
        let event = MiddlewareEvent::new(1, "Test")
            .with_max_instances(1, MaxInstanceBehavior::DiscardOldest);

        assert_eq!(event.max_instances, 1);
        assert_eq!(
            event.max_instance_behavior,
            MaxInstanceBehavior::DiscardOldest
        );
    }

    #[test]
    fn test_auto_id() {
        let event1 = MiddlewareEvent::new_auto("Event1");
        let event2 = MiddlewareEvent::new_auto("Event2");

        // Auto IDs should be different
        assert_ne!(event1.id, event2.id);
    }

    #[test]
    fn test_remove_action() {
        let mut event = MiddlewareEvent::new(1, "Test");
        event.add_action(MiddlewareAction::play(100, 0).with_id(1));
        event.add_action(MiddlewareAction::play(101, 0).with_id(2));

        let removed = event.remove_action(1);
        assert!(removed.is_some());
        assert_eq!(event.action_count(), 1);
        assert!(event.get_action(1).is_none());
        assert!(event.get_action(2).is_some());
    }
}

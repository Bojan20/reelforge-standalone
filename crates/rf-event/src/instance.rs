//! Event Instance Management
//!
//! Tracks active event executions and their pending actions.

use crate::action::MiddlewareAction;
use crate::event::MiddlewareEvent;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPE ALIASES
// ═══════════════════════════════════════════════════════════════════════════════

/// Unique identifier for a playing event instance
pub type PlayingId = u64;

/// Game object identifier (emitter)
pub type GameObjectId = u64;

/// Voice identifier
pub type VoiceId = u32;

/// Invalid game object (global scope)
pub const INVALID_GAME_OBJECT: GameObjectId = 0;

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYING ID GENERATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Global playing ID counter
static NEXT_PLAYING_ID: AtomicU64 = AtomicU64::new(1);

/// Generate unique playing ID
#[inline]
pub fn generate_playing_id() -> PlayingId {
    NEXT_PLAYING_ID.fetch_add(1, Ordering::Relaxed)
}

/// Invalid playing ID (for error cases)
pub const INVALID_PLAYING_ID: PlayingId = 0;

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT INSTANCE STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// State of an event instance
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum EventInstanceState {
    /// Instance is executing actions and voices are playing
    #[default]
    Playing = 0,
    /// Instance is paused
    Paused = 1,
    /// Instance is stopping (fading out)
    Stopping = 2,
    /// Instance has completed (ready for cleanup)
    Stopped = 3,
}

impl EventInstanceState {
    /// Check if instance is active (playing or paused)
    #[inline]
    pub fn is_active(&self) -> bool {
        matches!(
            self,
            EventInstanceState::Playing | EventInstanceState::Paused
        )
    }

    /// Check if instance can be cleaned up
    #[inline]
    pub fn is_finished(&self) -> bool {
        *self == EventInstanceState::Stopped
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PENDING ACTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Action scheduled for future execution
#[derive(Debug, Clone)]
pub struct PendingAction {
    /// The action to execute
    pub action: MiddlewareAction,
    /// Frame at which to execute (absolute)
    pub execute_at_frame: u64,
    /// Whether the action has been executed
    pub executed: bool,
}

impl PendingAction {
    /// Create a pending action
    pub fn new(action: MiddlewareAction, execute_at_frame: u64) -> Self {
        Self {
            action,
            execute_at_frame,
            executed: false,
        }
    }

    /// Check if action should execute at given frame
    #[inline]
    pub fn should_execute(&self, current_frame: u64) -> bool {
        !self.executed && current_frame >= self.execute_at_frame
    }

    /// Mark as executed
    #[inline]
    pub fn mark_executed(&mut self) {
        self.executed = true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT INSTANCE
// ═══════════════════════════════════════════════════════════════════════════════

/// Instance of an event being executed
///
/// Created when `post_event` is called, tracks all pending actions
/// and active voices until completion.
#[derive(Debug)]
pub struct EventInstance {
    /// Unique playing ID for this instance
    pub playing_id: PlayingId,
    /// Source event ID
    pub event_id: u32,
    /// Source event name (for debugging)
    pub event_name: String,
    /// Game object that triggered this instance
    pub game_object: GameObjectId,
    /// Frame when instance was created
    pub start_frame: u64,
    /// Current state
    pub state: EventInstanceState,
    /// Actions pending execution
    pub pending_actions: Vec<PendingAction>,
    /// Active voice IDs created by this instance
    pub voice_ids: Vec<VoiceId>,
    /// Callback ID (for completion notification)
    pub callback_id: Option<u32>,
    /// User data (for game integration)
    pub user_data: u64,
    /// Stop fade remaining frames (when stopping)
    pub stop_fade_frames: u64,
    /// Stop fade total frames
    pub stop_fade_total: u64,
}

impl EventInstance {
    /// Create a new event instance
    pub fn new(
        event_id: u32,
        event_name: impl Into<String>,
        game_object: GameObjectId,
        current_frame: u64,
    ) -> Self {
        Self::new_with_id(
            generate_playing_id(),
            event_id,
            event_name,
            game_object,
            current_frame,
        )
    }

    /// Create new instance with specific playing_id
    pub fn new_with_id(
        playing_id: PlayingId,
        event_id: u32,
        event_name: impl Into<String>,
        game_object: GameObjectId,
        current_frame: u64,
    ) -> Self {
        Self {
            playing_id,
            event_id,
            event_name: event_name.into(),
            game_object,
            start_frame: current_frame,
            state: EventInstanceState::Playing,
            pending_actions: Vec::new(),
            voice_ids: Vec::new(),
            callback_id: None,
            user_data: 0,
            stop_fade_frames: 0,
            stop_fade_total: 0,
        }
    }

    /// Schedule actions from event definition
    pub fn schedule_actions(&mut self, event: &MiddlewareEvent, sample_rate: u32) {
        self.pending_actions.clear();

        for action in &event.actions {
            let delay_frames = action.delay_frames(sample_rate);
            let execute_at = self.start_frame + delay_frames;

            self.pending_actions
                .push(PendingAction::new(action.clone(), execute_at));
        }

        // Sort by execution time for efficient processing
        self.pending_actions.sort_by_key(|a| a.execute_at_frame);
    }

    /// Get actions ready to execute at current frame
    ///
    /// Returns actions and marks them as executed.
    pub fn get_ready_actions(&mut self, current_frame: u64) -> Vec<&MiddlewareAction> {
        let mut ready = Vec::new();

        for pending in &mut self.pending_actions {
            if pending.should_execute(current_frame) {
                pending.mark_executed();
                ready.push(&pending.action);
            }
        }

        ready
    }

    /// Check if all actions have been executed
    #[inline]
    pub fn all_actions_executed(&self) -> bool {
        self.pending_actions.iter().all(|a| a.executed)
    }

    /// Check if instance has any active voices
    #[inline]
    pub fn has_active_voices(&self) -> bool {
        !self.voice_ids.is_empty()
    }

    /// Add a voice to this instance
    pub fn add_voice(&mut self, voice_id: VoiceId) {
        self.voice_ids.push(voice_id);
    }

    /// Remove a voice (when it finishes)
    pub fn remove_voice(&mut self, voice_id: VoiceId) {
        self.voice_ids.retain(|&v| v != voice_id);
    }

    /// Check if instance is complete (all actions done, no voices)
    #[inline]
    pub fn is_complete(&self) -> bool {
        self.all_actions_executed() && !self.has_active_voices()
    }

    /// Start stopping with fade
    pub fn start_stopping(&mut self, fade_frames: u64) {
        self.state = EventInstanceState::Stopping;
        self.stop_fade_frames = fade_frames;
        self.stop_fade_total = fade_frames;
    }

    /// Update stop fade (returns true if still fading)
    pub fn update_stop_fade(&mut self, frames_elapsed: u64) -> bool {
        if self.state != EventInstanceState::Stopping {
            return false;
        }

        if self.stop_fade_frames <= frames_elapsed {
            self.stop_fade_frames = 0;
            self.state = EventInstanceState::Stopped;
            false
        } else {
            self.stop_fade_frames -= frames_elapsed;
            true
        }
    }

    /// Get stop fade gain (0.0 - 1.0)
    #[inline]
    pub fn stop_fade_gain(&self) -> f32 {
        if self.stop_fade_total == 0 {
            return 0.0;
        }
        self.stop_fade_frames as f32 / self.stop_fade_total as f32
    }

    /// Pause the instance
    pub fn pause(&mut self) {
        if self.state == EventInstanceState::Playing {
            self.state = EventInstanceState::Paused;
        }
    }

    /// Resume the instance
    pub fn resume(&mut self) {
        if self.state == EventInstanceState::Paused {
            self.state = EventInstanceState::Playing;
        }
    }

    /// Set callback ID
    pub fn with_callback(mut self, callback_id: u32) -> Self {
        self.callback_id = Some(callback_id);
        self
    }

    /// Set user data
    pub fn with_user_data(mut self, user_data: u64) -> Self {
        self.user_data = user_data;
        self
    }

    /// Get elapsed frames since start
    #[inline]
    pub fn elapsed_frames(&self, current_frame: u64) -> u64 {
        current_frame.saturating_sub(self.start_frame)
    }

    /// Get count of pending (not yet executed) actions
    pub fn pending_action_count(&self) -> usize {
        self.pending_actions.iter().filter(|a| !a.executed).count()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CALLBACK INFO
// ═══════════════════════════════════════════════════════════════════════════════

/// Callback event type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum CallbackType {
    /// Event started
    EventStarted = 0,
    /// Event ended (all actions and voices complete)
    EventEnded = 1,
    /// Voice started
    VoiceStarted = 2,
    /// Voice ended
    VoiceEnded = 3,
    /// Marker reached
    MarkerReached = 4,
    /// Loop iteration
    LoopIteration = 5,
}

/// Callback information
#[derive(Debug, Clone)]
pub struct CallbackInfo {
    /// Callback type
    pub callback_type: CallbackType,
    /// Playing ID
    pub playing_id: PlayingId,
    /// Event ID
    pub event_id: u32,
    /// Game object
    pub game_object: GameObjectId,
    /// Callback ID (user provided)
    pub callback_id: u32,
    /// Voice ID (for voice callbacks)
    pub voice_id: Option<VoiceId>,
    /// Additional data (marker name, loop count, etc.)
    pub data: u64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::action::ActionType;

    #[test]
    fn test_playing_id_generation() {
        let id1 = generate_playing_id();
        let id2 = generate_playing_id();
        let id3 = generate_playing_id();

        assert_ne!(id1, id2);
        assert_ne!(id2, id3);
        assert!(id1 > 0);
    }

    #[test]
    fn test_instance_creation() {
        let instance = EventInstance::new(1, "Test_Event", 100, 0);

        assert_eq!(instance.event_id, 1);
        assert_eq!(instance.event_name, "Test_Event");
        assert_eq!(instance.game_object, 100);
        assert_eq!(instance.start_frame, 0);
        assert_eq!(instance.state, EventInstanceState::Playing);
        assert!(instance.pending_actions.is_empty());
        assert!(instance.voice_ids.is_empty());
    }

    #[test]
    fn test_schedule_actions() {
        let mut instance = EventInstance::new(1, "Test", 0, 1000);

        // Create event with actions
        let mut event = crate::event::MiddlewareEvent::new(1, "Test");
        event.add_action(crate::action::MiddlewareAction::play(100, 0).with_delay(0.0));
        event.add_action(crate::action::MiddlewareAction::play(101, 0).with_delay(0.5));
        event.add_action(crate::action::MiddlewareAction::stop(None).with_delay(1.0));

        instance.schedule_actions(&event, 48000);

        assert_eq!(instance.pending_actions.len(), 3);
        // Should be sorted by execution frame
        assert_eq!(instance.pending_actions[0].execute_at_frame, 1000); // 0ms delay
        assert_eq!(instance.pending_actions[1].execute_at_frame, 1000 + 24000); // 500ms
        assert_eq!(instance.pending_actions[2].execute_at_frame, 1000 + 48000); // 1000ms
    }

    #[test]
    fn test_get_ready_actions() {
        let mut instance = EventInstance::new(1, "Test", 0, 0);

        // Add actions at different times
        instance.pending_actions.push(PendingAction::new(
            crate::action::MiddlewareAction::play(100, 0),
            100,
        ));
        instance.pending_actions.push(PendingAction::new(
            crate::action::MiddlewareAction::play(101, 0),
            200,
        ));
        instance.pending_actions.push(PendingAction::new(
            crate::action::MiddlewareAction::play(102, 0),
            300,
        ));

        // At frame 150, only first action should be ready
        let ready = instance.get_ready_actions(150);
        assert_eq!(ready.len(), 1);
        assert_eq!(ready[0].asset_id, Some(100));

        // First action should now be marked executed
        assert!(instance.pending_actions[0].executed);

        // At frame 250, second action should be ready
        let ready = instance.get_ready_actions(250);
        assert_eq!(ready.len(), 1);
        assert_eq!(ready[0].asset_id, Some(101));
    }

    #[test]
    fn test_voice_management() {
        let mut instance = EventInstance::new(1, "Test", 0, 0);

        assert!(!instance.has_active_voices());

        instance.add_voice(1);
        instance.add_voice(2);
        instance.add_voice(3);

        assert!(instance.has_active_voices());
        assert_eq!(instance.voice_ids.len(), 3);

        instance.remove_voice(2);
        assert_eq!(instance.voice_ids.len(), 2);
        assert!(instance.voice_ids.contains(&1));
        assert!(instance.voice_ids.contains(&3));
        assert!(!instance.voice_ids.contains(&2));
    }

    #[test]
    fn test_stop_fade() {
        let mut instance = EventInstance::new(1, "Test", 0, 0);

        instance.start_stopping(1000);
        assert_eq!(instance.state, EventInstanceState::Stopping);
        assert_eq!(instance.stop_fade_frames, 1000);

        // Halfway through fade
        assert!(instance.update_stop_fade(500));
        assert_eq!(instance.stop_fade_frames, 500);
        assert!((instance.stop_fade_gain() - 0.5).abs() < 0.001);

        // Complete fade
        assert!(!instance.update_stop_fade(500));
        assert_eq!(instance.state, EventInstanceState::Stopped);
        assert_eq!(instance.stop_fade_gain(), 0.0);
    }

    #[test]
    fn test_pause_resume() {
        let mut instance = EventInstance::new(1, "Test", 0, 0);

        assert_eq!(instance.state, EventInstanceState::Playing);

        instance.pause();
        assert_eq!(instance.state, EventInstanceState::Paused);

        instance.resume();
        assert_eq!(instance.state, EventInstanceState::Playing);

        // Pausing while stopping should not change state
        instance.start_stopping(100);
        instance.pause();
        assert_eq!(instance.state, EventInstanceState::Stopping);
    }

    #[test]
    fn test_is_complete() {
        let mut instance = EventInstance::new(1, "Test", 0, 0);

        // Empty instance is complete
        assert!(instance.is_complete());

        // Add pending action
        instance.pending_actions.push(PendingAction::new(
            crate::action::MiddlewareAction::play(100, 0),
            0,
        ));
        assert!(!instance.is_complete());

        // Execute action but add voice
        instance.pending_actions[0].executed = true;
        instance.add_voice(1);
        assert!(!instance.is_complete());

        // Remove voice
        instance.remove_voice(1);
        assert!(instance.is_complete());
    }

    #[test]
    fn test_instance_state() {
        assert!(EventInstanceState::Playing.is_active());
        assert!(EventInstanceState::Paused.is_active());
        assert!(!EventInstanceState::Stopping.is_active());
        assert!(!EventInstanceState::Stopped.is_active());

        assert!(!EventInstanceState::Playing.is_finished());
        assert!(EventInstanceState::Stopped.is_finished());
    }
}

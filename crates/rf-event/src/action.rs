//! Middleware Action Types
//!
//! Complete action system matching Wwise/FMOD functionality.
//! All enums match Dart UI exactly for seamless FFI.

use serde::{Deserialize, Serialize};
use crate::curve::FadeCurve;

// ═══════════════════════════════════════════════════════════════════════════════
// ACTION TYPE
// ═══════════════════════════════════════════════════════════════════════════════

/// Action type enum — matches Dart `ActionType` exactly
///
/// These are the core operations that can be triggered by events.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum ActionType {
    /// Play a sound
    #[default]
    Play = 0,
    /// Play without stopping existing instances
    PlayAndContinue = 1,
    /// Stop a sound
    Stop = 2,
    /// Stop all sounds (in scope)
    StopAll = 3,
    /// Pause a sound
    Pause = 4,
    /// Pause all sounds (in scope)
    PauseAll = 5,
    /// Resume a paused sound
    Resume = 6,
    /// Resume all paused sounds (in scope)
    ResumeAll = 7,
    /// Break out of loop
    Break = 8,
    /// Mute a sound/bus
    Mute = 9,
    /// Unmute a sound/bus
    Unmute = 10,
    /// Set volume with fade
    SetVolume = 11,
    /// Set pitch
    SetPitch = 12,
    /// Set low-pass filter cutoff
    SetLPF = 13,
    /// Set high-pass filter cutoff
    SetHPF = 14,
    /// Set bus volume
    SetBusVolume = 15,
    /// Set state group value
    SetState = 16,
    /// Set switch group value
    SetSwitch = 17,
    /// Set RTPC value
    SetRTPC = 18,
    /// Reset RTPC to default
    ResetRTPC = 19,
    /// Seek to position
    Seek = 20,
    /// Trigger a stinger
    Trigger = 21,
    /// Post another event (nested)
    PostEvent = 22,
}

impl ActionType {
    /// Convert from u8 index
    #[inline]
    pub fn from_index(index: u8) -> Self {
        match index {
            0 => ActionType::Play,
            1 => ActionType::PlayAndContinue,
            2 => ActionType::Stop,
            3 => ActionType::StopAll,
            4 => ActionType::Pause,
            5 => ActionType::PauseAll,
            6 => ActionType::Resume,
            7 => ActionType::ResumeAll,
            8 => ActionType::Break,
            9 => ActionType::Mute,
            10 => ActionType::Unmute,
            11 => ActionType::SetVolume,
            12 => ActionType::SetPitch,
            13 => ActionType::SetLPF,
            14 => ActionType::SetHPF,
            15 => ActionType::SetBusVolume,
            16 => ActionType::SetState,
            17 => ActionType::SetSwitch,
            18 => ActionType::SetRTPC,
            19 => ActionType::ResetRTPC,
            20 => ActionType::Seek,
            21 => ActionType::Trigger,
            22 => ActionType::PostEvent,
            _ => ActionType::Play,
        }
    }

    /// Get display name (matches Dart)
    pub fn display_name(&self) -> &'static str {
        match self {
            ActionType::Play => "Play",
            ActionType::PlayAndContinue => "PlayAndContinue",
            ActionType::Stop => "Stop",
            ActionType::StopAll => "StopAll",
            ActionType::Pause => "Pause",
            ActionType::PauseAll => "PauseAll",
            ActionType::Resume => "Resume",
            ActionType::ResumeAll => "ResumeAll",
            ActionType::Break => "Break",
            ActionType::Mute => "Mute",
            ActionType::Unmute => "Unmute",
            ActionType::SetVolume => "SetVolume",
            ActionType::SetPitch => "SetPitch",
            ActionType::SetLPF => "SetLPF",
            ActionType::SetHPF => "SetHPF",
            ActionType::SetBusVolume => "SetBusVolume",
            ActionType::SetState => "SetState",
            ActionType::SetSwitch => "SetSwitch",
            ActionType::SetRTPC => "SetRTPC",
            ActionType::ResetRTPC => "ResetRTPC",
            ActionType::Seek => "Seek",
            ActionType::Trigger => "Trigger",
            ActionType::PostEvent => "PostEvent",
        }
    }

    /// Check if this action plays audio
    #[inline]
    pub fn is_play_action(&self) -> bool {
        matches!(self, ActionType::Play | ActionType::PlayAndContinue)
    }

    /// Check if this action stops audio
    #[inline]
    pub fn is_stop_action(&self) -> bool {
        matches!(self, ActionType::Stop | ActionType::StopAll)
    }

    /// Check if this action affects state/switch
    #[inline]
    pub fn is_state_action(&self) -> bool {
        matches!(self, ActionType::SetState | ActionType::SetSwitch)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACTION SCOPE
// ═══════════════════════════════════════════════════════════════════════════════

/// Action scope — which objects are affected
///
/// Matches Dart `ActionScope` exactly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum ActionScope {
    /// Affects all instances globally
    #[default]
    Global = 0,
    /// Affects only the triggering game object
    GameObject = 1,
    /// Affects the emitter (synonym for GameObject in most cases)
    Emitter = 2,
    /// Affects all matching instances
    All = 3,
    /// Affects only the first matching instance
    FirstOnly = 4,
    /// Affects a random matching instance
    Random = 5,
}

impl ActionScope {
    /// Convert from u8 index
    #[inline]
    pub fn from_index(index: u8) -> Self {
        match index {
            0 => ActionScope::Global,
            1 => ActionScope::GameObject,
            2 => ActionScope::Emitter,
            3 => ActionScope::All,
            4 => ActionScope::FirstOnly,
            5 => ActionScope::Random,
            _ => ActionScope::Global,
        }
    }

    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            ActionScope::Global => "Global",
            ActionScope::GameObject => "Game Object",
            ActionScope::Emitter => "Emitter",
            ActionScope::All => "All",
            ActionScope::FirstOnly => "First Only",
            ActionScope::Random => "Random",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACTION PRIORITY
// ═══════════════════════════════════════════════════════════════════════════════

/// Action priority for voice stealing decisions
///
/// Matches Dart `ActionPriority` exactly.
/// Higher priority = less likely to be stolen.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum ActionPriority {
    /// Lowest priority — first to be stolen
    Lowest = 0,
    /// Low priority
    Low = 1,
    /// Below normal priority
    BelowNormal = 2,
    /// Normal priority (default)
    #[default]
    Normal = 3,
    /// Above normal priority
    AboveNormal = 4,
    /// High priority
    High = 5,
    /// Highest priority — last to be stolen
    Highest = 6,
}

impl ActionPriority {
    /// Convert from u8 index
    #[inline]
    pub fn from_index(index: u8) -> Self {
        match index {
            0 => ActionPriority::Lowest,
            1 => ActionPriority::Low,
            2 => ActionPriority::BelowNormal,
            3 => ActionPriority::Normal,
            4 => ActionPriority::AboveNormal,
            5 => ActionPriority::High,
            6 => ActionPriority::Highest,
            _ => ActionPriority::Normal,
        }
    }

    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            ActionPriority::Lowest => "Lowest",
            ActionPriority::Low => "Low",
            ActionPriority::BelowNormal => "Below Normal",
            ActionPriority::Normal => "Normal",
            ActionPriority::AboveNormal => "Above Normal",
            ActionPriority::High => "High",
            ActionPriority::Highest => "Highest",
        }
    }

    /// Get numeric value (0-100 scale for compatibility)
    #[inline]
    pub fn numeric_value(&self) -> u8 {
        match self {
            ActionPriority::Lowest => 0,
            ActionPriority::Low => 17,
            ActionPriority::BelowNormal => 33,
            ActionPriority::Normal => 50,
            ActionPriority::AboveNormal => 67,
            ActionPriority::High => 83,
            ActionPriority::Highest => 100,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDDLEWARE ACTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete action definition
///
/// Represents a single action within an event. Multiple actions
/// can be combined in one event for complex behaviors.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MiddlewareAction {
    /// Unique action ID within event
    pub id: u32,
    /// Action type
    pub action_type: ActionType,
    /// Target asset ID (for Play/Stop actions)
    pub asset_id: Option<u32>,
    /// Target bus ID (0 = Master)
    pub bus_id: u32,
    /// Action scope
    pub scope: ActionScope,
    /// Priority for voice stealing
    pub priority: ActionPriority,
    /// Fade curve type
    pub fade_curve: FadeCurve,
    /// Fade time in seconds
    pub fade_time_secs: f32,
    /// Gain multiplier (0.0 - 2.0, where 1.0 = unity)
    pub gain: f32,
    /// Delay before execution (seconds)
    pub delay_secs: f32,
    /// Loop playback (for Play actions)
    pub loop_playback: bool,

    // === State/Switch specific ===
    /// State/Switch group ID
    pub group_id: Option<u32>,
    /// State/Switch value ID
    pub value_id: Option<u32>,

    // === RTPC specific ===
    /// RTPC ID
    pub rtpc_id: Option<u32>,
    /// RTPC target value
    pub rtpc_value: Option<f32>,
    /// RTPC interpolation time (seconds)
    pub rtpc_interpolation_secs: Option<f32>,

    // === Seek specific ===
    /// Seek position (seconds)
    pub seek_position_secs: Option<f32>,
    /// Seek to percentage (0.0 - 1.0) instead of absolute
    pub seek_to_percent: bool,

    // === PostEvent specific ===
    /// Target event ID for PostEvent action
    pub target_event_id: Option<u32>,

    // === Pitch specific ===
    /// Pitch adjustment in semitones (-24 to +24)
    pub pitch_semitones: Option<f32>,

    // === Filter specific ===
    /// LPF/HPF cutoff frequency (Hz)
    pub filter_freq_hz: Option<f32>,

    // === Extended playback parameters (2026-01-26) ===
    /// Stereo pan position (-1.0 = left, 0.0 = center, +1.0 = right)
    pub pan: f32,
    /// Fade-in duration in seconds (for Play actions)
    pub fade_in_secs: f32,
    /// Fade-out duration in seconds (for Stop actions, separate from fade_time_secs)
    pub fade_out_secs: f32,
    /// Non-destructive trim start position in seconds
    pub trim_start_secs: f32,
    /// Non-destructive trim end position in seconds (0.0 = full duration)
    pub trim_end_secs: f32,

    // === State condition (for state-aware playback) ===
    /// Optional state group ID that must be active for action to execute
    pub require_state_group: Option<u32>,
    /// Required state ID within the group
    pub require_state_id: Option<u32>,
    /// If true, action executes when state is NOT the specified one
    pub require_state_inverted: bool,

    // === Switch condition ===
    /// Optional switch group ID that must match for action to execute
    pub require_switch_group: Option<u32>,
    /// Required switch ID within the group
    pub require_switch_id: Option<u32>,

    // === RTPC condition ===
    /// Optional RTPC ID for conditional execution
    pub require_rtpc_id: Option<u32>,
    /// Minimum RTPC value for action to execute
    pub require_rtpc_min: Option<f32>,
    /// Maximum RTPC value for action to execute
    pub require_rtpc_max: Option<f32>,
}

impl Default for MiddlewareAction {
    fn default() -> Self {
        Self {
            id: 0,
            action_type: ActionType::Play,
            asset_id: None,
            bus_id: 0,
            scope: ActionScope::Global,
            priority: ActionPriority::Normal,
            fade_curve: FadeCurve::Linear,
            fade_time_secs: 0.0,
            gain: 1.0,
            delay_secs: 0.0,
            loop_playback: false,
            group_id: None,
            value_id: None,
            rtpc_id: None,
            rtpc_value: None,
            rtpc_interpolation_secs: None,
            seek_position_secs: None,
            seek_to_percent: false,
            target_event_id: None,
            pitch_semitones: None,
            filter_freq_hz: None,
            // Extended playback parameters (2026-01-26)
            pan: 0.0,
            fade_in_secs: 0.0,
            fade_out_secs: 0.0,
            trim_start_secs: 0.0,
            trim_end_secs: 0.0,
            require_state_group: None,
            require_state_id: None,
            require_state_inverted: false,
            require_switch_group: None,
            require_switch_id: None,
            require_rtpc_id: None,
            require_rtpc_min: None,
            require_rtpc_max: None,
        }
    }
}

impl MiddlewareAction {
    /// Create a Play action
    pub fn play(asset_id: u32, bus_id: u32) -> Self {
        Self {
            action_type: ActionType::Play,
            asset_id: Some(asset_id),
            bus_id,
            ..Default::default()
        }
    }

    /// Create a Stop action
    pub fn stop(asset_id: Option<u32>) -> Self {
        Self {
            action_type: ActionType::Stop,
            asset_id,
            ..Default::default()
        }
    }

    /// Create a StopAll action
    pub fn stop_all() -> Self {
        Self {
            action_type: ActionType::StopAll,
            ..Default::default()
        }
    }

    /// Create a SetVolume action
    pub fn set_volume(bus_id: u32, gain: f32, fade_secs: f32) -> Self {
        Self {
            action_type: ActionType::SetVolume,
            bus_id,
            gain,
            fade_time_secs: fade_secs,
            ..Default::default()
        }
    }

    /// Create a SetState action
    pub fn set_state(group_id: u32, state_id: u32) -> Self {
        Self {
            action_type: ActionType::SetState,
            group_id: Some(group_id),
            value_id: Some(state_id),
            ..Default::default()
        }
    }

    /// Create a SetSwitch action
    pub fn set_switch(group_id: u32, switch_id: u32) -> Self {
        Self {
            action_type: ActionType::SetSwitch,
            group_id: Some(group_id),
            value_id: Some(switch_id),
            ..Default::default()
        }
    }

    /// Create a SetRTPC action
    pub fn set_rtpc(rtpc_id: u32, value: f32, interpolation_secs: f32) -> Self {
        Self {
            action_type: ActionType::SetRTPC,
            rtpc_id: Some(rtpc_id),
            rtpc_value: Some(value),
            rtpc_interpolation_secs: Some(interpolation_secs),
            ..Default::default()
        }
    }

    /// Create a PostEvent action
    pub fn post_event(event_id: u32) -> Self {
        Self {
            action_type: ActionType::PostEvent,
            target_event_id: Some(event_id),
            ..Default::default()
        }
    }

    /// Create a Seek action
    pub fn seek(position_secs: f32) -> Self {
        Self {
            action_type: ActionType::Seek,
            seek_position_secs: Some(position_secs),
            ..Default::default()
        }
    }

    // === Builder methods ===

    /// Set action ID
    pub fn with_id(mut self, id: u32) -> Self {
        self.id = id;
        self
    }

    /// Set delay before execution
    pub fn with_delay(mut self, delay_secs: f32) -> Self {
        self.delay_secs = delay_secs;
        self
    }

    /// Set fade curve and time
    pub fn with_fade(mut self, curve: FadeCurve, time_secs: f32) -> Self {
        self.fade_curve = curve;
        self.fade_time_secs = time_secs;
        self
    }

    /// Set priority
    pub fn with_priority(mut self, priority: ActionPriority) -> Self {
        self.priority = priority;
        self
    }

    /// Set scope
    pub fn with_scope(mut self, scope: ActionScope) -> Self {
        self.scope = scope;
        self
    }

    /// Set loop playback
    pub fn with_loop(mut self, loop_playback: bool) -> Self {
        self.loop_playback = loop_playback;
        self
    }

    /// Set gain
    pub fn with_gain(mut self, gain: f32) -> Self {
        self.gain = gain;
        self
    }

    /// Set bus
    pub fn with_bus(mut self, bus_id: u32) -> Self {
        self.bus_id = bus_id;
        self
    }

    // === Query methods ===

    /// Get delay in frames at given sample rate
    #[inline]
    pub fn delay_frames(&self, sample_rate: u32) -> u64 {
        (self.delay_secs * sample_rate as f32) as u64
    }

    /// Get fade time in frames at given sample rate
    #[inline]
    pub fn fade_frames(&self, sample_rate: u32) -> u64 {
        (self.fade_time_secs * sample_rate as f32) as u64
    }

    /// Check if action has delay
    #[inline]
    pub fn has_delay(&self) -> bool {
        self.delay_secs > 0.0
    }

    /// Check if action has fade
    #[inline]
    pub fn has_fade(&self) -> bool {
        self.fade_time_secs > 0.0
    }

    // === State/Switch/RTPC condition builders ===

    /// Require specific state for action to execute
    pub fn with_state_condition(mut self, group_id: u32, state_id: u32) -> Self {
        self.require_state_group = Some(group_id);
        self.require_state_id = Some(state_id);
        self.require_state_inverted = false;
        self
    }

    /// Require state to NOT be specific value for action to execute
    pub fn with_state_condition_inverted(mut self, group_id: u32, state_id: u32) -> Self {
        self.require_state_group = Some(group_id);
        self.require_state_id = Some(state_id);
        self.require_state_inverted = true;
        self
    }

    /// Require specific switch for action to execute (on game object)
    pub fn with_switch_condition(mut self, group_id: u32, switch_id: u32) -> Self {
        self.require_switch_group = Some(group_id);
        self.require_switch_id = Some(switch_id);
        self
    }

    /// Require RTPC value in range for action to execute
    pub fn with_rtpc_condition(mut self, rtpc_id: u32, min: f32, max: f32) -> Self {
        self.require_rtpc_id = Some(rtpc_id);
        self.require_rtpc_min = Some(min);
        self.require_rtpc_max = Some(max);
        self
    }

    /// Check if action has any state/switch/rtpc condition
    #[inline]
    pub fn has_condition(&self) -> bool {
        self.require_state_group.is_some() ||
        self.require_switch_group.is_some() ||
        self.require_rtpc_id.is_some()
    }

    /// Check state condition against current states
    pub fn check_state_condition(&self, current_states: &std::collections::HashMap<u32, u32>) -> bool {
        if let (Some(group_id), Some(required_state)) = (self.require_state_group, self.require_state_id) {
            let current = current_states.get(&group_id).copied().unwrap_or(0);
            let matches = current == required_state;
            if self.require_state_inverted { !matches } else { matches }
        } else {
            true // No condition = always passes
        }
    }

    /// Check switch condition against current switches (for specific game object)
    pub fn check_switch_condition(
        &self,
        game_object: u64,
        current_switches: &std::collections::HashMap<(u64, u32), u32>,
    ) -> bool {
        if let (Some(group_id), Some(required_switch)) = (self.require_switch_group, self.require_switch_id) {
            let current = current_switches.get(&(game_object, group_id)).copied().unwrap_or(0);
            current == required_switch
        } else {
            true
        }
    }

    /// Check RTPC condition against current values
    pub fn check_rtpc_condition(&self, current_rtpcs: &std::collections::HashMap<u32, f32>) -> bool {
        if let Some(rtpc_id) = self.require_rtpc_id {
            let current = current_rtpcs.get(&rtpc_id).copied().unwrap_or(0.0);
            let min = self.require_rtpc_min.unwrap_or(f32::MIN);
            let max = self.require_rtpc_max.unwrap_or(f32::MAX);
            current >= min && current <= max
        } else {
            true
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_action_type_roundtrip() {
        for i in 0..=22 {
            let action = ActionType::from_index(i);
            assert_eq!(action as u8, i);
        }
    }

    #[test]
    fn test_action_scope_roundtrip() {
        for i in 0..=5 {
            let scope = ActionScope::from_index(i);
            assert_eq!(scope as u8, i);
        }
    }

    #[test]
    fn test_priority_ordering() {
        assert!(ActionPriority::Lowest < ActionPriority::Low);
        assert!(ActionPriority::Low < ActionPriority::Normal);
        assert!(ActionPriority::Normal < ActionPriority::High);
        assert!(ActionPriority::High < ActionPriority::Highest);
    }

    #[test]
    fn test_play_action_builder() {
        let action = MiddlewareAction::play(100, 1)
            .with_id(1)
            .with_delay(0.5)
            .with_fade(FadeCurve::SCurve, 0.2)
            .with_priority(ActionPriority::High)
            .with_loop(true);

        assert_eq!(action.id, 1);
        assert_eq!(action.action_type, ActionType::Play);
        assert_eq!(action.asset_id, Some(100));
        assert_eq!(action.bus_id, 1);
        assert_eq!(action.delay_secs, 0.5);
        assert_eq!(action.fade_curve, FadeCurve::SCurve);
        assert_eq!(action.fade_time_secs, 0.2);
        assert_eq!(action.priority, ActionPriority::High);
        assert!(action.loop_playback);
    }

    #[test]
    fn test_delay_frames() {
        let action = MiddlewareAction::play(100, 0).with_delay(1.0);

        assert_eq!(action.delay_frames(48000), 48000);
        assert_eq!(action.delay_frames(44100), 44100);
    }

    #[test]
    fn test_set_state_action() {
        let action = MiddlewareAction::set_state(1, 2);

        assert_eq!(action.action_type, ActionType::SetState);
        assert_eq!(action.group_id, Some(1));
        assert_eq!(action.value_id, Some(2));
    }

    #[test]
    fn test_set_rtpc_action() {
        let action = MiddlewareAction::set_rtpc(5, 0.75, 0.5);

        assert_eq!(action.action_type, ActionType::SetRTPC);
        assert_eq!(action.rtpc_id, Some(5));
        assert_eq!(action.rtpc_value, Some(0.75));
        assert_eq!(action.rtpc_interpolation_secs, Some(0.5));
    }
}

//! Sequence Container - Timed Sound Sequences
//!
//! Provides step-based audio playback with precise timing:
//! - Each step has delay, duration, and optional loop count
//! - Supports fade in/out per step
//! - End behaviors: Stop, Loop, HoldLast, PingPong
//! - Speed multiplier for tempo adjustment
//!
//! ## Example Timeline
//!
//! ```text
//! Time:  0ms    100ms   200ms   300ms   400ms   500ms
//!        │       │       │       │       │       │
//! Step 0: ███████                              (delay=0, duration=100)
//! Step 1:         ─────███████                 (delay=150, duration=100)
//! Step 2:                         ███████████  (delay=300, duration=200)
//! ```

use super::{ChildId, Container, ContainerId, ContainerType};
use smallvec::SmallVec;

/// Maximum steps per sequence container (stack-allocated)
const MAX_SEQUENCE_STEPS: usize = 32;

/// Sequence end behavior
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum SequenceEndBehavior {
    /// Stop after last step
    #[default]
    Stop = 0,
    /// Loop back to first step
    Loop = 1,
    /// Keep last step playing
    HoldLast = 2,
    /// Reverse direction (ping-pong)
    PingPong = 3,
}

impl SequenceEndBehavior {
    /// Create from integer value
    pub fn from_u8(value: u8) -> Self {
        match value {
            1 => SequenceEndBehavior::Loop,
            2 => SequenceEndBehavior::HoldLast,
            3 => SequenceEndBehavior::PingPong,
            _ => SequenceEndBehavior::Stop,
        }
    }
}

/// Sequence step
#[derive(Debug, Clone)]
pub struct SequenceStep {
    /// Step index (0-based)
    pub index: usize,
    /// Child/sound ID to play
    pub child_id: ChildId,
    /// Display name
    pub child_name: String,
    /// Audio file path
    pub audio_path: Option<String>,
    /// Delay from sequence start (milliseconds)
    pub delay_ms: f64,
    /// Step duration (milliseconds)
    pub duration_ms: f64,
    /// Fade in time (milliseconds)
    pub fade_in_ms: f64,
    /// Fade out time (milliseconds)
    pub fade_out_ms: f64,
    /// Loop count for this step (1 = play once, 0 = infinite)
    pub loop_count: u32,
    /// Volume for this step (0.0 - 1.0)
    pub volume: f64,
}

impl SequenceStep {
    /// Create a new sequence step
    pub fn new(
        index: usize,
        child_id: ChildId,
        name: impl Into<String>,
        delay_ms: f64,
        duration_ms: f64,
    ) -> Self {
        Self {
            index,
            child_id,
            child_name: name.into(),
            audio_path: None,
            delay_ms: delay_ms.max(0.0),
            duration_ms: duration_ms.max(0.0),
            fade_in_ms: 0.0,
            fade_out_ms: 0.0,
            loop_count: 1,
            volume: 1.0,
        }
    }

    /// Get end time (delay + duration)
    #[inline]
    pub fn end_ms(&self) -> f64 {
        self.delay_ms + self.duration_ms
    }
}

/// Sequence playback state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum SequenceState {
    /// Not playing
    #[default]
    Stopped = 0,
    /// Currently playing
    Playing = 1,
    /// Paused
    Paused = 2,
}

/// Sequence container
#[derive(Debug, Clone)]
pub struct SequenceContainer {
    /// Unique container ID
    pub id: ContainerId,
    /// Display name
    pub name: String,
    /// Whether container is enabled
    pub enabled: bool,
    /// End behavior
    pub end_behavior: SequenceEndBehavior,
    /// Speed multiplier (1.0 = normal)
    pub speed: f64,
    /// Steps in the sequence
    pub steps: SmallVec<[SequenceStep; MAX_SEQUENCE_STEPS]>,

    // Playback state
    /// Current playback state
    state: SequenceState,
    /// Current playback position (milliseconds)
    position_ms: f64,
    /// Current step index
    current_step: usize,
    /// Playback direction (1 = forward, -1 = backward for ping-pong)
    direction: i32,
    /// Steps that have been triggered this playback
    triggered_steps: SmallVec<[bool; MAX_SEQUENCE_STEPS]>,
}

impl SequenceContainer {
    /// Create a new sequence container
    pub fn new(id: ContainerId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            enabled: true,
            end_behavior: SequenceEndBehavior::Stop,
            speed: 1.0,
            steps: SmallVec::new(),
            state: SequenceState::Stopped,
            position_ms: 0.0,
            current_step: 0,
            direction: 1,
            triggered_steps: SmallVec::new(),
        }
    }

    /// Add a step to the sequence
    pub fn add_step(&mut self, step: SequenceStep) {
        self.steps.push(step);
        self.triggered_steps.push(false);
        // Sort by delay time
        self.steps.sort_by(|a, b| {
            a.delay_ms
                .partial_cmp(&b.delay_ms)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        // Re-index
        for (i, step) in self.steps.iter_mut().enumerate() {
            step.index = i;
        }
    }

    /// Remove a step by index
    pub fn remove_step(&mut self, index: usize) -> bool {
        if index < self.steps.len() {
            self.steps.remove(index);
            if index < self.triggered_steps.len() {
                self.triggered_steps.remove(index);
            }
            // Re-index
            for (i, step) in self.steps.iter_mut().enumerate() {
                step.index = i;
            }
            true
        } else {
            false
        }
    }

    /// Get total sequence duration (in milliseconds)
    pub fn duration_ms(&self) -> f64 {
        self.steps.iter().map(|s| s.end_ms()).fold(0.0, f64::max)
    }

    /// Start playback
    pub fn play(&mut self) {
        if !self.enabled || self.steps.is_empty() {
            return;
        }

        self.state = SequenceState::Playing;
        self.position_ms = 0.0;
        self.current_step = 0;
        self.direction = 1;
        self.triggered_steps.clear();
        self.triggered_steps.resize(self.steps.len(), false);
    }

    /// Stop playback
    pub fn stop(&mut self) {
        self.state = SequenceState::Stopped;
        self.position_ms = 0.0;
        self.current_step = 0;
        self.direction = 1;
    }

    /// Pause playback
    pub fn pause(&mut self) {
        if self.state == SequenceState::Playing {
            self.state = SequenceState::Paused;
        }
    }

    /// Resume playback
    pub fn resume(&mut self) {
        if self.state == SequenceState::Paused {
            self.state = SequenceState::Playing;
        }
    }

    /// Jump to specific step
    pub fn jump_to_step(&mut self, step_index: usize) {
        if step_index < self.steps.len() {
            self.current_step = step_index;
            self.position_ms = self.steps[step_index].delay_ms;
            // Reset triggered flags for steps we're jumping over
            for i in 0..self.triggered_steps.len() {
                self.triggered_steps[i] = i < step_index;
            }
        }
    }

    /// Tick the sequence by delta milliseconds
    /// Returns steps that should be triggered this tick
    pub fn tick(&mut self, delta_ms: f64) -> SequenceResult {
        if self.state != SequenceState::Playing || self.steps.is_empty() {
            return SequenceResult::default();
        }

        // Apply speed multiplier
        let adjusted_delta = delta_ms * self.speed;
        self.position_ms += adjusted_delta * self.direction as f64;

        let mut result = SequenceResult::default();
        let duration = self.duration_ms();

        // Check for steps to trigger (forward)
        if self.direction > 0 {
            for (i, step) in self.steps.iter().enumerate() {
                if i < self.triggered_steps.len()
                    && !self.triggered_steps[i]
                    && self.position_ms >= step.delay_ms
                {
                    self.triggered_steps[i] = true;
                    result.trigger_steps.push(i);
                }
            }
        } else {
            // Backward (ping-pong)
            for (i, step) in self.steps.iter().enumerate().rev() {
                if i < self.triggered_steps.len()
                    && !self.triggered_steps[i]
                    && self.position_ms <= step.end_ms()
                {
                    self.triggered_steps[i] = true;
                    result.trigger_steps.push(i);
                }
            }
        }

        // Check for end of sequence
        if self.direction > 0 && self.position_ms >= duration {
            self.handle_end(&mut result);
        } else if self.direction < 0 && self.position_ms <= 0.0 {
            self.handle_end(&mut result);
        }

        result.state = self.state;
        result.position_ms = self.position_ms;
        result.current_step = self.current_step;

        result
    }

    /// Handle sequence end based on behavior
    fn handle_end(&mut self, result: &mut SequenceResult) {
        match self.end_behavior {
            SequenceEndBehavior::Stop => {
                self.state = SequenceState::Stopped;
                result.ended = true;
            }
            SequenceEndBehavior::Loop => {
                self.position_ms = 0.0;
                self.current_step = 0;
                self.triggered_steps.fill(false);
                result.looped = true;
            }
            SequenceEndBehavior::HoldLast => {
                self.state = SequenceState::Paused;
                result.holding = true;
            }
            SequenceEndBehavior::PingPong => {
                self.direction = -self.direction;
                self.triggered_steps.fill(false);
                result.reversed = true;
            }
        }
    }

    /// Get step by index
    pub fn get_step(&self, index: usize) -> Option<&SequenceStep> {
        self.steps.get(index)
    }

    /// Get mutable step by index
    pub fn get_step_mut(&mut self, index: usize) -> Option<&mut SequenceStep> {
        self.steps.get_mut(index)
    }

    /// Get current playback state
    pub fn playback_state(&self) -> SequenceState {
        self.state
    }

    /// Check if currently playing
    pub fn is_playing(&self) -> bool {
        self.state == SequenceState::Playing
    }

    /// Get current position
    pub fn position(&self) -> f64 {
        self.position_ms
    }
}

impl Container for SequenceContainer {
    fn id(&self) -> ContainerId {
        self.id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn is_enabled(&self) -> bool {
        self.enabled
    }

    fn container_type(&self) -> ContainerType {
        ContainerType::Sequence
    }

    fn child_count(&self) -> usize {
        self.steps.len()
    }
}

/// Result of sequence tick
#[derive(Debug, Clone, Default)]
pub struct SequenceResult {
    /// Steps to trigger this tick (indices)
    pub trigger_steps: SmallVec<[usize; 4]>,
    /// Current playback state
    pub state: SequenceState,
    /// Current position (milliseconds)
    pub position_ms: f64,
    /// Current step index
    pub current_step: usize,
    /// Sequence ended (Stop behavior)
    pub ended: bool,
    /// Sequence looped (Loop behavior)
    pub looped: bool,
    /// Sequence holding last (HoldLast behavior)
    pub holding: bool,
    /// Direction reversed (PingPong behavior)
    pub reversed: bool,
}

impl SequenceResult {
    /// Check if any steps should be triggered
    pub fn has_triggers(&self) -> bool {
        !self.trigger_steps.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sequence_end_behavior_from_u8() {
        assert_eq!(SequenceEndBehavior::from_u8(0), SequenceEndBehavior::Stop);
        assert_eq!(SequenceEndBehavior::from_u8(1), SequenceEndBehavior::Loop);
        assert_eq!(
            SequenceEndBehavior::from_u8(2),
            SequenceEndBehavior::HoldLast
        );
        assert_eq!(
            SequenceEndBehavior::from_u8(3),
            SequenceEndBehavior::PingPong
        );
    }

    #[test]
    fn test_sequence_step() {
        let step = SequenceStep::new(0, 1, "test_sound", 100.0, 200.0);
        assert_eq!(step.delay_ms, 100.0);
        assert_eq!(step.duration_ms, 200.0);
        assert_eq!(step.end_ms(), 300.0);
    }

    #[test]
    fn test_sequence_container_play() {
        let mut container = SequenceContainer::new(1, "test_sequence");

        container.add_step(SequenceStep::new(0, 1, "sound_a", 0.0, 100.0));
        container.add_step(SequenceStep::new(1, 2, "sound_b", 150.0, 100.0));
        container.add_step(SequenceStep::new(2, 3, "sound_c", 300.0, 100.0));

        assert_eq!(container.duration_ms(), 400.0);

        // Start playback
        container.play();
        assert!(container.is_playing());

        // Tick: should trigger first step immediately
        let result = container.tick(10.0);
        assert!(result.trigger_steps.contains(&0));

        // Tick to 160ms: should trigger second step
        let result = container.tick(150.0);
        assert!(result.trigger_steps.contains(&1));

        // Tick to 310ms: should trigger third step
        let result = container.tick(150.0);
        assert!(result.trigger_steps.contains(&2));

        // Tick past end: should stop
        let result = container.tick(100.0);
        assert!(result.ended);
        assert_eq!(container.playback_state(), SequenceState::Stopped);
    }

    #[test]
    fn test_sequence_loop() {
        let mut container = SequenceContainer::new(1, "test_loop");
        container.end_behavior = SequenceEndBehavior::Loop;

        container.add_step(SequenceStep::new(0, 1, "sound", 0.0, 100.0));

        container.play();

        // First cycle
        container.tick(50.0);
        let result = container.tick(60.0); // Past 100ms
        assert!(result.looped);
        assert!(container.is_playing());

        // Position should reset
        assert!(container.position() < 20.0); // Wrapped around
    }

    #[test]
    fn test_sequence_speed() {
        let mut container = SequenceContainer::new(1, "test_speed");
        container.speed = 2.0; // 2x speed

        container.add_step(SequenceStep::new(0, 1, "sound", 100.0, 100.0));

        container.play();

        // At 2x speed, 50ms real time = 100ms sequence time
        let result = container.tick(50.0);
        assert!(result.trigger_steps.contains(&0));
    }
}

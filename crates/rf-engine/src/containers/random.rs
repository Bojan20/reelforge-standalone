//! Random Container - Weighted Random Selection
//!
//! Provides weighted random sound selection with multiple modes:
//! - **Random**: Pure random selection based on weights
//! - **Shuffle**: Play each child once before repeating
//! - **RoundRobin**: Sequential playback (predictable)
//!
//! Supports per-child pitch and volume variation for natural sound design.

use super::{ChildId, Container, ContainerId, ContainerType};
use smallvec::SmallVec;

/// Maximum children per random container (stack-allocated)
const MAX_RANDOM_CHILDREN: usize = 16;

/// Random selection mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum RandomMode {
    /// Pure weighted random
    #[default]
    Random = 0,
    /// Play all before repeating (no consecutive repeats)
    Shuffle = 1,
    /// Sequential round-robin
    RoundRobin = 2,
}

impl RandomMode {
    /// Create from integer value
    pub fn from_u8(value: u8) -> Self {
        match value {
            1 => RandomMode::Shuffle,
            2 => RandomMode::RoundRobin,
            _ => RandomMode::Random,
        }
    }
}

/// Pitch/volume variation for a child
#[derive(Debug, Clone, Copy, Default)]
pub struct RandomVariation {
    /// Minimum pitch offset (semitones, can be negative)
    pub pitch_min: f64,
    /// Maximum pitch offset (semitones)
    pub pitch_max: f64,
    /// Minimum volume offset (dB, can be negative)
    pub volume_min: f64,
    /// Maximum volume offset (dB)
    pub volume_max: f64,
}

impl RandomVariation {
    /// Create variation with specified ranges
    pub fn new(pitch_min: f64, pitch_max: f64, volume_min: f64, volume_max: f64) -> Self {
        Self {
            pitch_min,
            pitch_max,
            volume_min,
            volume_max,
        }
    }

    /// Apply variation using random value (0.0 - 1.0)
    #[inline]
    pub fn apply(&self, pitch_rand: f64, volume_rand: f64) -> (f64, f64) {
        let pitch = self.pitch_min + pitch_rand * (self.pitch_max - self.pitch_min);
        let volume = self.volume_min + volume_rand * (self.volume_max - self.volume_min);
        (pitch, volume)
    }
}

/// Random container child
#[derive(Debug, Clone)]
pub struct RandomChild {
    /// Unique child ID
    pub id: ChildId,
    /// Display name
    pub name: String,
    /// Audio file path
    pub audio_path: Option<String>,
    /// Selection weight (higher = more likely)
    pub weight: f64,
    /// Per-play variation
    pub variation: RandomVariation,
}

impl RandomChild {
    /// Create a new random child
    pub fn new(id: ChildId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            audio_path: None,
            weight: 1.0,
            variation: RandomVariation::default(),
        }
    }

    /// Create with specified weight
    pub fn with_weight(id: ChildId, name: impl Into<String>, weight: f64) -> Self {
        Self {
            id,
            name: name.into(),
            audio_path: None,
            weight: weight.max(0.0),
            variation: RandomVariation::default(),
        }
    }
}

/// Random container
#[derive(Debug, Clone)]
pub struct RandomContainer {
    /// Unique container ID
    pub id: ContainerId,
    /// Display name
    pub name: String,
    /// Whether container is enabled
    pub enabled: bool,
    /// Selection mode
    pub mode: RandomMode,
    /// Child sounds
    pub children: SmallVec<[RandomChild; MAX_RANDOM_CHILDREN]>,
    /// Avoid consecutive repeats (for Random mode)
    pub avoid_repeat: bool,
    /// Number of recent plays to avoid (for avoid_repeat)
    pub avoid_repeat_count: usize,
    /// Global pitch variation (applied on top of per-child)
    pub global_pitch_min: f64,
    pub global_pitch_max: f64,
    /// Global volume variation
    pub global_volume_min: f64,
    pub global_volume_max: f64,

    // Internal state (mutable during selection)
    /// Last selected child ID (for avoid_repeat)
    last_selected: Option<ChildId>,
    /// Recent history (for avoid_repeat_count)
    recent_history: SmallVec<[ChildId; 8]>,
    /// Shuffle deck (remaining unplayed children)
    shuffle_deck: SmallVec<[ChildId; MAX_RANDOM_CHILDREN]>,
    /// Round-robin index
    round_robin_index: usize,
    /// XorShift RNG state
    rng_state: u64,
}

impl RandomContainer {
    /// Create a new random container
    pub fn new(id: ContainerId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            enabled: true,
            mode: RandomMode::Random,
            children: SmallVec::new(),
            avoid_repeat: true,
            avoid_repeat_count: 1,
            global_pitch_min: 0.0,
            global_pitch_max: 0.0,
            global_volume_min: 0.0,
            global_volume_max: 0.0,
            last_selected: None,
            recent_history: SmallVec::new(),
            shuffle_deck: SmallVec::new(),
            round_robin_index: 0,
            rng_state: 0x853c49e6748fea9b, // Default seed
        }
    }

    /// Seed the RNG
    pub fn seed(&mut self, seed: u64) {
        self.rng_state = seed.max(1); // Ensure non-zero
    }

    /// Add a child to the container
    pub fn add_child(&mut self, child: RandomChild) {
        self.children.push(child);
        self.reset_state();
    }

    /// Remove a child by ID
    pub fn remove_child(&mut self, child_id: ChildId) -> bool {
        if let Some(pos) = self.children.iter().position(|c| c.id == child_id) {
            self.children.remove(pos);
            self.reset_state();
            true
        } else {
            false
        }
    }

    /// Reset internal state (shuffle deck, round-robin, history)
    pub fn reset_state(&mut self) {
        self.shuffle_deck.clear();
        self.round_robin_index = 0;
        self.recent_history.clear();
        self.last_selected = None;
    }

    /// Generate next random number (XorShift64)
    #[inline]
    fn next_random(&mut self) -> f64 {
        let mut x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;
        // Convert to 0.0-1.0
        (x as f64) / (u64::MAX as f64)
    }

    /// Select a child based on current mode
    pub fn select(&mut self) -> Option<RandomResult> {
        if !self.enabled || self.children.is_empty() {
            return None;
        }

        let selected_id = match self.mode {
            RandomMode::Random => self.select_random()?,
            RandomMode::Shuffle => self.select_shuffle()?,
            RandomMode::RoundRobin => self.select_round_robin()?,
        };

        // Find the child and copy its variation (to avoid borrow conflict)
        let child_variation = self
            .children
            .iter()
            .find(|c| c.id == selected_id)?
            .variation;

        // Calculate variation (now safe to mutate self)
        let pitch_rand = self.next_random();
        let volume_rand = self.next_random();
        let (child_pitch, child_volume) = child_variation.apply(pitch_rand, volume_rand);

        // Add global variation
        let global_pitch_rand = self.next_random();
        let global_volume_rand = self.next_random();
        let global_pitch = self.global_pitch_min
            + global_pitch_rand * (self.global_pitch_max - self.global_pitch_min);
        let global_volume = self.global_volume_min
            + global_volume_rand * (self.global_volume_max - self.global_volume_min);

        // Update history
        self.last_selected = Some(selected_id);
        if self.avoid_repeat_count > 0 {
            self.recent_history.push(selected_id);
            if self.recent_history.len() > self.avoid_repeat_count {
                self.recent_history.remove(0);
            }
        }

        Some(RandomResult {
            child_id: selected_id,
            pitch_offset: child_pitch + global_pitch,
            volume_offset: child_volume + global_volume,
        })
    }

    /// Weighted random selection
    fn select_random(&mut self) -> Option<ChildId> {
        let total_weight: f64 = self.children.iter().map(|c| c.weight).sum();
        if total_weight <= 0.0 {
            return None;
        }

        let mut attempts = 0;
        const MAX_ATTEMPTS: usize = 10;

        loop {
            let r = self.next_random() * total_weight;
            let mut cumulative = 0.0;

            for child in &self.children {
                cumulative += child.weight;
                if r < cumulative {
                    // Check avoid_repeat
                    if self.avoid_repeat && Some(child.id) == self.last_selected {
                        attempts += 1;
                        if attempts >= MAX_ATTEMPTS || self.children.len() == 1 {
                            return Some(child.id);
                        }
                        break; // Try again
                    }

                    // Check recent history
                    if self.avoid_repeat_count > 0
                        && self.recent_history.contains(&child.id)
                        && self.children.len() > self.avoid_repeat_count
                    {
                        attempts += 1;
                        if attempts >= MAX_ATTEMPTS {
                            return Some(child.id);
                        }
                        break;
                    }

                    return Some(child.id);
                }
            }

            attempts += 1;
            if attempts >= MAX_ATTEMPTS {
                // Fallback: return first valid child
                return self.children.first().map(|c| c.id);
            }
        }
    }

    /// Shuffle selection (play all before repeating)
    fn select_shuffle(&mut self) -> Option<ChildId> {
        // Refill deck if empty
        if self.shuffle_deck.is_empty() {
            self.shuffle_deck = self.children.iter().map(|c| c.id).collect();

            // Fisher-Yates shuffle
            let n = self.shuffle_deck.len();
            for i in (1..n).rev() {
                let j = (self.next_random() * (i + 1) as f64) as usize;
                self.shuffle_deck.swap(i, j.min(i));
            }

            // Move last played to end (avoid consecutive repeat)
            if let Some(last) = self.last_selected {
                if let Some(pos) = self.shuffle_deck.iter().position(|&id| id == last) {
                    if pos == 0 && self.shuffle_deck.len() > 1 {
                        self.shuffle_deck.swap(0, 1);
                    }
                }
            }
        }

        self.shuffle_deck.pop()
    }

    /// Round-robin selection
    fn select_round_robin(&mut self) -> Option<ChildId> {
        if self.children.is_empty() {
            return None;
        }

        let child_id = self.children[self.round_robin_index].id;
        self.round_robin_index = (self.round_robin_index + 1) % self.children.len();
        Some(child_id)
    }

    /// Get child by ID
    pub fn get_child(&self, child_id: ChildId) -> Option<&RandomChild> {
        self.children.iter().find(|c| c.id == child_id)
    }

    /// Get mutable child by ID
    pub fn get_child_mut(&mut self, child_id: ChildId) -> Option<&mut RandomChild> {
        self.children.iter_mut().find(|c| c.id == child_id)
    }
}

impl Container for RandomContainer {
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
        ContainerType::Random
    }

    fn child_count(&self) -> usize {
        self.children.len()
    }
}

/// Result of random selection
#[derive(Debug, Clone)]
pub struct RandomResult {
    /// Selected child ID
    pub child_id: ChildId,
    /// Pitch offset in semitones
    pub pitch_offset: f64,
    /// Volume offset in dB
    pub volume_offset: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_random_mode_from_u8() {
        assert_eq!(RandomMode::from_u8(0), RandomMode::Random);
        assert_eq!(RandomMode::from_u8(1), RandomMode::Shuffle);
        assert_eq!(RandomMode::from_u8(2), RandomMode::RoundRobin);
    }

    #[test]
    fn test_random_variation() {
        let var = RandomVariation::new(-2.0, 2.0, -3.0, 3.0);

        let (pitch, volume) = var.apply(0.0, 0.0);
        assert!((pitch - (-2.0)).abs() < 0.001);
        assert!((volume - (-3.0)).abs() < 0.001);

        let (pitch, volume) = var.apply(1.0, 1.0);
        assert!((pitch - 2.0).abs() < 0.001);
        assert!((volume - 3.0).abs() < 0.001);
    }

    #[test]
    fn test_random_container_select() {
        let mut container = RandomContainer::new(1, "test_random");
        container.seed(12345);

        container.add_child(RandomChild::with_weight(1, "sound_a", 1.0));
        container.add_child(RandomChild::with_weight(2, "sound_b", 1.0));
        container.add_child(RandomChild::with_weight(3, "sound_c", 1.0));

        // Select multiple times
        let mut selections = vec![];
        for _ in 0..10 {
            if let Some(result) = container.select() {
                selections.push(result.child_id);
            }
        }

        // Should have variety (not all same)
        let unique: std::collections::HashSet<_> = selections.iter().collect();
        assert!(unique.len() > 1);
    }

    #[test]
    fn test_round_robin() {
        let mut container = RandomContainer::new(1, "test_rr");
        container.mode = RandomMode::RoundRobin;

        container.add_child(RandomChild::new(1, "a"));
        container.add_child(RandomChild::new(2, "b"));
        container.add_child(RandomChild::new(3, "c"));

        // Should cycle 1, 2, 3, 1, 2, 3...
        assert_eq!(container.select().unwrap().child_id, 1);
        assert_eq!(container.select().unwrap().child_id, 2);
        assert_eq!(container.select().unwrap().child_id, 3);
        assert_eq!(container.select().unwrap().child_id, 1);
    }

    #[test]
    fn test_shuffle_no_repeat() {
        let mut container = RandomContainer::new(1, "test_shuffle");
        container.mode = RandomMode::Shuffle;
        container.seed(12345);

        container.add_child(RandomChild::new(1, "a"));
        container.add_child(RandomChild::new(2, "b"));
        container.add_child(RandomChild::new(3, "c"));

        // First cycle: all three should appear exactly once
        let mut first_cycle = vec![];
        for _ in 0..3 {
            first_cycle.push(container.select().unwrap().child_id);
        }
        let unique: std::collections::HashSet<_> = first_cycle.iter().collect();
        assert_eq!(unique.len(), 3);
    }
}

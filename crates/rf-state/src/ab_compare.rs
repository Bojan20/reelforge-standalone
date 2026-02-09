//! A/B Comparison System
//!
//! Provides instant A/B comparison like FabFilter/iZotope plugins:
//! - Store up to 8 states (A, B, C, D, E, F, G, H)
//! - Instant switching without audio glitches
//! - Copy between slots
//! - Delta view (difference between states)

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU8, Ordering};

use serde::{Deserialize, Serialize};

// ============ Slot Identifier ============

/// A/B comparison slot
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
#[derive(Default)]
pub enum CompareSlot {
    #[default]
    A = 0,
    B = 1,
    C = 2,
    D = 3,
    E = 4,
    F = 5,
    G = 6,
    H = 7,
}

impl CompareSlot {
    pub fn from_index(index: u8) -> Option<Self> {
        match index {
            0 => Some(Self::A),
            1 => Some(Self::B),
            2 => Some(Self::C),
            3 => Some(Self::D),
            4 => Some(Self::E),
            5 => Some(Self::F),
            6 => Some(Self::G),
            7 => Some(Self::H),
            _ => None,
        }
    }

    pub fn index(self) -> usize {
        self as usize
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::A => "A",
            Self::B => "B",
            Self::C => "C",
            Self::D => "D",
            Self::E => "E",
            Self::F => "F",
            Self::G => "G",
            Self::H => "H",
        }
    }

    pub fn all() -> &'static [CompareSlot] {
        &[
            Self::A,
            Self::B,
            Self::C,
            Self::D,
            Self::E,
            Self::F,
            Self::G,
            Self::H,
        ]
    }
}

// ============ Parameter State ============

/// Single parameter value
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParameterValue {
    pub id: u32,
    pub value: f64,
    pub name: String,
}

/// Complete parameter state for one slot
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ParameterState {
    /// All parameter values
    pub values: HashMap<u32, f64>,
    /// Slot name (user-definable)
    pub name: String,
    /// Whether this slot has been initialized
    pub initialized: bool,
    /// Timestamp of last update
    pub updated_at: u64,
}

impl ParameterState {
    pub fn new() -> Self {
        Self {
            values: HashMap::new(),
            name: String::new(),
            initialized: false,
            updated_at: 0,
        }
    }

    /// Get parameter value
    pub fn get(&self, id: u32) -> Option<f64> {
        self.values.get(&id).copied()
    }

    /// Set parameter value
    pub fn set(&mut self, id: u32, value: f64) {
        self.values.insert(id, value);
        self.initialized = true;
    }

    /// Copy all values from another state
    pub fn copy_from(&mut self, other: &ParameterState) {
        self.values = other.values.clone();
        self.initialized = other.initialized;
    }

    /// Get difference from another state
    pub fn diff(&self, other: &ParameterState) -> Vec<(u32, f64, f64)> {
        let mut diffs = Vec::new();

        for (&id, &value) in &self.values {
            if let Some(&other_value) = other.values.get(&id) {
                if (value - other_value).abs() > 1e-10 {
                    diffs.push((id, value, other_value));
                }
            } else {
                diffs.push((id, value, 0.0));
            }
        }

        diffs
    }

    /// Check if identical to another state
    pub fn is_equal(&self, other: &ParameterState) -> bool {
        if self.values.len() != other.values.len() {
            return false;
        }

        for (&id, &value) in &self.values {
            if let Some(&other_value) = other.values.get(&id) {
                if (value - other_value).abs() > 1e-10 {
                    return false;
                }
            } else {
                return false;
            }
        }

        true
    }

    /// Interpolate between this state and another
    pub fn lerp(&self, other: &ParameterState, t: f64) -> ParameterState {
        let mut result = self.clone();
        let t = t.clamp(0.0, 1.0);

        for (&id, &value) in &self.values {
            if let Some(&other_value) = other.values.get(&id) {
                result.values.insert(id, value + (other_value - value) * t);
            }
        }

        result
    }
}

// ============ A/B Compare Manager ============

/// Maximum number of comparison slots
pub const MAX_SLOTS: usize = 8;

/// A/B Comparison manager
pub struct ABCompare {
    /// All slots
    slots: [ParameterState; MAX_SLOTS],
    /// Currently active slot
    active_slot: AtomicU8,
    /// Slot being compared to (for delta view)
    compare_slot: Option<CompareSlot>,
    /// Whether delta mode is active
    delta_mode: bool,
    /// Crossfade time in ms (for smooth transitions)
    crossfade_ms: f64,
    /// Currently crossfading
    crossfading: bool,
    /// Crossfade progress (0.0 to 1.0)
    crossfade_progress: f64,
    /// Crossfade source slot
    crossfade_from: CompareSlot,
    /// Crossfade target slot
    crossfade_to: CompareSlot,
    /// Timestamp counter
    timestamp: u64,
}

impl ABCompare {
    pub fn new() -> Self {
        Self {
            slots: std::array::from_fn(|i| {
                let mut state = ParameterState::new();
                state.name = CompareSlot::from_index(i as u8)
                    .map(|s| s.name().to_string())
                    .unwrap_or_default();
                state
            }),
            active_slot: AtomicU8::new(0),
            compare_slot: None,
            delta_mode: false,
            crossfade_ms: 50.0,
            crossfading: false,
            crossfade_progress: 0.0,
            crossfade_from: CompareSlot::A,
            crossfade_to: CompareSlot::A,
            timestamp: 0,
        }
    }

    /// Get active slot
    pub fn active_slot(&self) -> CompareSlot {
        CompareSlot::from_index(self.active_slot.load(Ordering::Relaxed)).unwrap_or(CompareSlot::A)
    }

    /// Set active slot (instant switch)
    pub fn set_active_slot(&mut self, slot: CompareSlot) {
        self.active_slot.store(slot as u8, Ordering::Relaxed);
    }

    /// Set active slot with crossfade
    pub fn crossfade_to_slot(&mut self, slot: CompareSlot) {
        if slot != self.active_slot() {
            self.crossfade_from = self.active_slot();
            self.crossfade_to = slot;
            self.crossfading = true;
            self.crossfade_progress = 0.0;
        }
    }

    /// Update crossfade (call from audio thread)
    pub fn update_crossfade(&mut self, sample_rate: f64, block_size: usize) {
        if !self.crossfading {
            return;
        }

        let crossfade_samples = (self.crossfade_ms / 1000.0) * sample_rate;
        let progress_per_block = block_size as f64 / crossfade_samples;

        self.crossfade_progress += progress_per_block;

        if self.crossfade_progress >= 1.0 {
            self.crossfade_progress = 1.0;
            self.crossfading = false;
            self.set_active_slot(self.crossfade_to);
        }
    }

    /// Get current parameter state (with crossfade interpolation)
    pub fn current_state(&self) -> ParameterState {
        if self.crossfading {
            let from = &self.slots[self.crossfade_from.index()];
            let to = &self.slots[self.crossfade_to.index()];
            from.lerp(to, self.crossfade_progress)
        } else {
            self.slots[self.active_slot().index()].clone()
        }
    }

    /// Get slot state
    pub fn get_slot(&self, slot: CompareSlot) -> &ParameterState {
        &self.slots[slot.index()]
    }

    /// Get mutable slot state
    pub fn get_slot_mut(&mut self, slot: CompareSlot) -> &mut ParameterState {
        &mut self.slots[slot.index()]
    }

    /// Store current parameters to a slot
    pub fn store_to_slot(&mut self, slot: CompareSlot, values: &[(u32, f64)]) {
        self.timestamp += 1;
        let state = &mut self.slots[slot.index()];

        for &(id, value) in values {
            state.set(id, value);
        }
        state.updated_at = self.timestamp;
    }

    /// Copy one slot to another
    pub fn copy_slot(&mut self, from: CompareSlot, to: CompareSlot) {
        if from != to {
            let source = self.slots[from.index()].clone();
            self.slots[to.index()].copy_from(&source);
            self.slots[to.index()].updated_at = self.timestamp;
        }
    }

    /// Swap two slots
    pub fn swap_slots(&mut self, a: CompareSlot, b: CompareSlot) {
        if a != b {
            self.slots.swap(a.index(), b.index());
        }
    }

    /// Clear a slot
    pub fn clear_slot(&mut self, slot: CompareSlot) {
        self.slots[slot.index()] = ParameterState::new();
        self.slots[slot.index()].name = slot.name().to_string();
    }

    /// Enable delta mode (show difference from compare slot)
    pub fn set_delta_mode(&mut self, enabled: bool, compare_to: Option<CompareSlot>) {
        self.delta_mode = enabled;
        self.compare_slot = compare_to;
    }

    /// Get delta from compare slot
    pub fn get_delta(&self) -> Option<Vec<(u32, f64, f64)>> {
        if !self.delta_mode {
            return None;
        }

        let compare_slot = self.compare_slot?;
        let active = &self.slots[self.active_slot().index()];
        let compare = &self.slots[compare_slot.index()];

        Some(active.diff(compare))
    }

    /// Check if slot is initialized
    pub fn is_slot_initialized(&self, slot: CompareSlot) -> bool {
        self.slots[slot.index()].initialized
    }

    /// Get slot name
    pub fn slot_name(&self, slot: CompareSlot) -> &str {
        &self.slots[slot.index()].name
    }

    /// Set slot name
    pub fn set_slot_name(&mut self, slot: CompareSlot, name: impl Into<String>) {
        self.slots[slot.index()].name = name.into();
    }

    /// Set crossfade time
    pub fn set_crossfade_time(&mut self, ms: f64) {
        self.crossfade_ms = ms.max(0.0);
    }

    /// Check if currently crossfading
    pub fn is_crossfading(&self) -> bool {
        self.crossfading
    }

    /// Get all slot summaries
    pub fn slot_summaries(&self) -> Vec<(CompareSlot, &str, bool)> {
        CompareSlot::all()
            .iter()
            .map(|&slot| {
                let state = &self.slots[slot.index()];
                (slot, state.name.as_str(), state.initialized)
            })
            .collect()
    }
}

impl Default for ABCompare {
    fn default() -> Self {
        Self::new()
    }
}

// ============ Shared A/B Compare ============

/// Thread-safe A/B compare wrapper
pub struct SharedABCompare {
    inner: Arc<parking_lot::RwLock<ABCompare>>,
}

impl SharedABCompare {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(parking_lot::RwLock::new(ABCompare::new())),
        }
    }

    pub fn read(&self) -> parking_lot::RwLockReadGuard<'_, ABCompare> {
        self.inner.read()
    }

    pub fn write(&self) -> parking_lot::RwLockWriteGuard<'_, ABCompare> {
        self.inner.write()
    }

    pub fn active_slot(&self) -> CompareSlot {
        self.inner.read().active_slot()
    }

    pub fn set_active_slot(&self, slot: CompareSlot) {
        self.inner.write().set_active_slot(slot);
    }
}

impl Clone for SharedABCompare {
    fn clone(&self) -> Self {
        Self {
            inner: Arc::clone(&self.inner),
        }
    }
}

impl Default for SharedABCompare {
    fn default() -> Self {
        Self::new()
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ab_compare_basic() {
        let mut ab = ABCompare::new();

        // Store values to slot A
        ab.store_to_slot(CompareSlot::A, &[(0, 0.5), (1, 0.7)]);
        assert!(ab.is_slot_initialized(CompareSlot::A));

        // Store different values to slot B
        ab.store_to_slot(CompareSlot::B, &[(0, 1.0), (1, 0.3)]);

        // Check values
        assert!((ab.get_slot(CompareSlot::A).get(0).unwrap() - 0.5).abs() < 1e-10);
        assert!((ab.get_slot(CompareSlot::B).get(0).unwrap() - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_slot_switching() {
        let mut ab = ABCompare::new();

        ab.store_to_slot(CompareSlot::A, &[(0, 0.5)]);
        ab.store_to_slot(CompareSlot::B, &[(0, 1.0)]);

        assert_eq!(ab.active_slot(), CompareSlot::A);

        ab.set_active_slot(CompareSlot::B);
        assert_eq!(ab.active_slot(), CompareSlot::B);
    }

    #[test]
    fn test_copy_slot() {
        let mut ab = ABCompare::new();

        ab.store_to_slot(CompareSlot::A, &[(0, 0.5), (1, 0.7)]);
        ab.copy_slot(CompareSlot::A, CompareSlot::B);

        assert!(
            ab.get_slot(CompareSlot::A)
                .is_equal(ab.get_slot(CompareSlot::B))
        );
    }

    #[test]
    fn test_delta_mode() {
        let mut ab = ABCompare::new();

        ab.store_to_slot(CompareSlot::A, &[(0, 0.5), (1, 0.7)]);
        ab.store_to_slot(CompareSlot::B, &[(0, 1.0), (1, 0.7)]);

        ab.set_delta_mode(true, Some(CompareSlot::B));

        let delta = ab.get_delta().unwrap();
        // Only param 0 differs
        assert_eq!(delta.len(), 1);
        assert_eq!(delta[0].0, 0);
    }

    #[test]
    fn test_interpolation() {
        let mut ab = ABCompare::new();

        ab.store_to_slot(CompareSlot::A, &[(0, 0.0)]);
        ab.store_to_slot(CompareSlot::B, &[(0, 1.0)]);

        let a = ab.get_slot(CompareSlot::A);
        let b = ab.get_slot(CompareSlot::B);

        let mid = a.lerp(b, 0.5);
        assert!((mid.get(0).unwrap() - 0.5).abs() < 1e-10);
    }
}

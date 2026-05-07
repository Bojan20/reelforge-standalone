//! Chain Undo/Redo + A/B Snapshot Manager
//!
//! Per-track history stacks (UNDO_DEPTH=32) + two A/B preset slots.
//! State is kept in-process; the FFI layer serialises to JSON for
//! cross-language boundaries.
//!
//! # Data model
//!
//! `FullChainSnapshot` captures everything needed to restore a chain:
//!   - which processor is in each slot (name)
//!   - bypass state and wet/dry mix
//!   - all numerical parameters by index + display name
//!
//! This is richer than the `CurrentChainState` used by `chain_applier`;
//! those only track structural identity (name + bypass), not parameter
//! values.  History requires the full picture.
//!
//! # A/B slots
//!
//! Two named preset slots per track.  Common DAW workflow:
//!   1. Dial in chain A → `chain_ab_save_a`
//!   2. Try different approach → `chain_ab_save_b`
//!   3. `chain_ab_restore_a` / `chain_ab_restore_b` to toggle
//!   4. `chain_ab_swap` to flip without restoring

use std::collections::HashMap;
use std::sync::LazyLock;
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

// ─── Config ──────────────────────────────────────────────────────────────────

/// Maximum undo/redo entries per track. Oldest entry is evicted when full.
const UNDO_DEPTH: usize = 32;

// ─── Snapshot types ──────────────────────────────────────────────────────────

/// One captured parameter value.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotParamSnapshot {
    /// Raw parameter index (stable within a loaded processor).
    pub index: usize,
    /// Display name at capture time ("Threshold", "Frequency", …).
    pub name: String,
    /// Normalised or raw value — whatever `get_track_insert_param` returns.
    pub value: f64,
}

/// One slot's full state at capture time.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FullSlotSnapshot {
    pub slot_index: u32,
    /// Processor factory name ("compressor", "pro-eq", "fab-q-pro", …).
    pub processor_name: String,
    pub bypassed: bool,
    /// Wet/dry mix (0.0–1.0).
    pub mix: f64,
    /// All parameters captured in index order.
    pub params: Vec<SlotParamSnapshot>,
}

/// Complete chain state for one track at one point in time.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FullChainSnapshot {
    pub track_id: u32,
    /// Loaded slots only (empty slots are not stored).
    pub slots: Vec<FullSlotSnapshot>,
    /// Human-readable label, e.g. "Apply Vocal Bright".
    pub label: String,
    /// Unix epoch milliseconds.
    pub timestamp_ms: u64,
}

impl FullChainSnapshot {
    /// Construct with current wall-clock timestamp.
    pub fn now(track_id: u32, slots: Vec<FullSlotSnapshot>, label: impl Into<String>) -> Self {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        Self {
            track_id,
            slots,
            label: label.into(),
            timestamp_ms: ts,
        }
    }
}

// ─── Per-track record ────────────────────────────────────────────────────────

#[derive(Debug, Default)]
struct TrackRecord {
    undo: Vec<FullChainSnapshot>, // back() = most recent
    redo: Vec<FullChainSnapshot>,
    slot_a: Option<FullChainSnapshot>,
    slot_b: Option<FullChainSnapshot>,
}

impl TrackRecord {
    /// Push `snap` as a new undo point. Clears redo (branching history).
    fn push_undo(&mut self, snap: FullChainSnapshot) {
        if self.undo.len() >= UNDO_DEPTH {
            self.undo.remove(0);
        }
        self.undo.push(snap);
        self.redo.clear();
    }

    /// Pop one undo entry.  Pushes `current` onto redo so it can be re-applied.
    /// Returns the snapshot to restore, or `None` if the undo stack is empty.
    fn undo(&mut self, current: FullChainSnapshot) -> Option<FullChainSnapshot> {
        let target = self.undo.pop()?;
        if self.redo.len() >= UNDO_DEPTH {
            self.redo.remove(0);
        }
        self.redo.push(current);
        Some(target)
    }

    /// Pop one redo entry.  Pushes `current` back onto undo.
    fn redo(&mut self, current: FullChainSnapshot) -> Option<FullChainSnapshot> {
        let target = self.redo.pop()?;
        if self.undo.len() >= UNDO_DEPTH {
            self.undo.remove(0);
        }
        self.undo.push(current);
        Some(target)
    }
}

// ─── Manager ─────────────────────────────────────────────────────────────────

/// Central undo/redo + A/B manager.  Lazily allocates per-track records.
#[derive(Default)]
pub struct ChainHistoryManager {
    tracks: HashMap<u32, TrackRecord>,
}

impl ChainHistoryManager {
    pub fn new() -> Self {
        Self::default()
    }

    fn track_mut(&mut self, id: u32) -> &mut TrackRecord {
        self.tracks.entry(id).or_default()
    }

    // ─── Undo / Redo ────────────────────────────────────────────────────────

    /// Push `snap` as a before-state onto the undo stack for its track.
    /// Called by the apply-execute path *before* modifying the engine.
    pub fn push(&mut self, snap: FullChainSnapshot) {
        let id = snap.track_id;
        self.track_mut(id).push_undo(snap);
    }

    /// Undo the most recent apply.  `current` is the *current* chain state
    /// (will be pushed to redo so the user can redo back to it).
    /// Returns the snapshot to restore, or `None` if nothing to undo.
    pub fn undo(&mut self, track_id: u32, current: FullChainSnapshot) -> Option<FullChainSnapshot> {
        self.track_mut(track_id).undo(current)
    }

    /// Redo the most recently undone apply.
    pub fn redo(&mut self, track_id: u32, current: FullChainSnapshot) -> Option<FullChainSnapshot> {
        self.track_mut(track_id).redo(current)
    }

    /// How many undo steps are available for this track.
    pub fn undo_depth(&self, track_id: u32) -> usize {
        self.tracks.get(&track_id).map(|t| t.undo.len()).unwrap_or(0)
    }

    /// How many redo steps are available for this track.
    pub fn redo_depth(&self, track_id: u32) -> usize {
        self.tracks.get(&track_id).map(|t| t.redo.len()).unwrap_or(0)
    }

    /// Label of the step that would be undone next, for tooltip display.
    pub fn undo_label(&self, track_id: u32) -> Option<&str> {
        self.tracks
            .get(&track_id)?
            .undo
            .last()
            .map(|s| s.label.as_str())
    }

    /// Label of the step that would be redone next.
    pub fn redo_label(&self, track_id: u32) -> Option<&str> {
        self.tracks
            .get(&track_id)?
            .redo
            .last()
            .map(|s| s.label.as_str())
    }

    /// Clear both stacks for a track (e.g. after a destructive project reload).
    pub fn clear(&mut self, track_id: u32) {
        if let Some(t) = self.tracks.get_mut(&track_id) {
            t.undo.clear();
            t.redo.clear();
        }
    }

    /// Clear all tracks (full project reset).
    pub fn clear_all(&mut self) {
        self.tracks.clear();
    }

    // ─── A/B Slots ──────────────────────────────────────────────────────────

    /// Store `snap` in A slot for its track.
    pub fn save_a(&mut self, snap: FullChainSnapshot) {
        let id = snap.track_id;
        self.track_mut(id).slot_a = Some(snap);
    }

    /// Store `snap` in B slot for its track.
    pub fn save_b(&mut self, snap: FullChainSnapshot) {
        let id = snap.track_id;
        self.track_mut(id).slot_b = Some(snap);
    }

    pub fn get_a(&self, track_id: u32) -> Option<&FullChainSnapshot> {
        self.tracks.get(&track_id)?.slot_a.as_ref()
    }

    pub fn get_b(&self, track_id: u32) -> Option<&FullChainSnapshot> {
        self.tracks.get(&track_id)?.slot_b.as_ref()
    }

    /// Swap A↔B labels and contents in-memory (no engine state change).
    pub fn swap_ab(&mut self, track_id: u32) {
        let t = self.track_mut(track_id);
        std::mem::swap(&mut t.slot_a, &mut t.slot_b);
    }
}

// ─── Global singleton ────────────────────────────────────────────────────────

pub static CHAIN_HISTORY: LazyLock<RwLock<ChainHistoryManager>> =
    LazyLock::new(|| RwLock::new(ChainHistoryManager::new()));

// ─── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn snap(track_id: u32, label: &str) -> FullChainSnapshot {
        FullChainSnapshot {
            track_id,
            slots: vec![],
            label: label.to_string(),
            timestamp_ms: 1000,
        }
    }

    #[test]
    fn push_and_undo_basic() {
        let mut mgr = ChainHistoryManager::new();
        mgr.push(snap(1, "before-A"));
        let current = snap(1, "current");
        let restored = mgr.undo(1, current.clone()).unwrap();
        assert_eq!(restored.label, "before-A");
        assert_eq!(mgr.undo_depth(1), 0);
        assert_eq!(mgr.redo_depth(1), 1);
    }

    #[test]
    fn redo_after_undo() {
        let mut mgr = ChainHistoryManager::new();
        mgr.push(snap(1, "step-1"));
        let current = snap(1, "after");
        let undone = mgr.undo(1, current.clone()).unwrap();
        assert_eq!(undone.label, "step-1");
        let redone = mgr.redo(1, undone).unwrap();
        assert_eq!(redone.label, "after");
        assert_eq!(mgr.undo_depth(1), 1);
        assert_eq!(mgr.redo_depth(1), 0);
    }

    #[test]
    fn push_clears_redo() {
        let mut mgr = ChainHistoryManager::new();
        mgr.push(snap(1, "step-1"));
        let _ = mgr.undo(1, snap(1, "after-1"));
        assert_eq!(mgr.redo_depth(1), 1);
        // New push should clear redo
        mgr.push(snap(1, "step-2"));
        assert_eq!(mgr.redo_depth(1), 0);
    }

    #[test]
    fn undo_empty_returns_none() {
        let mut mgr = ChainHistoryManager::new();
        assert!(mgr.undo(99, snap(99, "x")).is_none());
    }

    #[test]
    fn evicts_oldest_when_full() {
        let mut mgr = ChainHistoryManager::new();
        for i in 0..(UNDO_DEPTH + 5) {
            mgr.push(snap(1, &format!("step-{i}")));
        }
        assert_eq!(mgr.undo_depth(1), UNDO_DEPTH);
    }

    #[test]
    fn ab_save_get() {
        let mut mgr = ChainHistoryManager::new();
        mgr.save_a(snap(2, "a-state"));
        mgr.save_b(snap(2, "b-state"));
        assert_eq!(mgr.get_a(2).unwrap().label, "a-state");
        assert_eq!(mgr.get_b(2).unwrap().label, "b-state");
    }

    #[test]
    fn ab_swap() {
        let mut mgr = ChainHistoryManager::new();
        mgr.save_a(snap(3, "a"));
        mgr.save_b(snap(3, "b"));
        mgr.swap_ab(3);
        assert_eq!(mgr.get_a(3).unwrap().label, "b");
        assert_eq!(mgr.get_b(3).unwrap().label, "a");
    }

    #[test]
    fn clear_resets_stacks() {
        let mut mgr = ChainHistoryManager::new();
        mgr.push(snap(4, "x"));
        mgr.clear(4);
        assert_eq!(mgr.undo_depth(4), 0);
    }

    #[test]
    fn undo_redo_labels() {
        let mut mgr = ChainHistoryManager::new();
        mgr.push(snap(5, "my-label"));
        assert_eq!(mgr.undo_label(5), Some("my-label"));
        assert!(mgr.redo_label(5).is_none());
        let _ = mgr.undo(5, snap(5, "cur"));
        assert!(mgr.undo_label(5).is_none());
        assert_eq!(mgr.redo_label(5), Some("cur"));
    }

    #[test]
    fn serialization_roundtrip() {
        let snap_in = FullChainSnapshot::now(
            10,
            vec![FullSlotSnapshot {
                slot_index: 0,
                processor_name: "compressor".to_string(),
                bypassed: false,
                mix: 1.0,
                params: vec![
                    SlotParamSnapshot { index: 0, name: "Threshold".to_string(), value: -20.0 },
                    SlotParamSnapshot { index: 1, name: "Ratio".to_string(), value: 4.0 },
                ],
            }],
            "Vocal Compress",
        );
        let json = serde_json::to_string(&snap_in).unwrap();
        let snap_out: FullChainSnapshot = serde_json::from_str(&json).unwrap();
        assert_eq!(snap_out.track_id, 10);
        assert_eq!(snap_out.slots[0].params[0].name, "Threshold");
        assert_eq!(snap_out.slots[0].params[0].value, -20.0);
    }

    #[test]
    fn multi_track_isolation() {
        let mut mgr = ChainHistoryManager::new();
        mgr.push(snap(1, "track-1"));
        mgr.push(snap(2, "track-2"));
        assert_eq!(mgr.undo_depth(1), 1);
        assert_eq!(mgr.undo_depth(2), 1);
        mgr.clear(1);
        assert_eq!(mgr.undo_depth(1), 0);
        assert_eq!(mgr.undo_depth(2), 1); // untouched
    }
}

//! Marker and Locator System
//!
//! Professional marker management like Cubase/Pro Tools:
//! - Position markers (named locations)
//! - Cycle markers (regions)
//! - Arranger events
//! - Cue points (for video)
//! - Tempo/time signature markers
//! - Memory locations (Cubase-style)
//!
//! ## Marker Types
//! - Position: Single point in time
//! - Cycle: Range with start/end
//! - Arranger: Sections for song arrangement

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Marker ID
pub type MarkerId = u64;

static NEXT_MARKER_ID: AtomicU64 = AtomicU64::new(1);

fn new_marker_id() -> MarkerId {
    NEXT_MARKER_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKER TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Marker type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[derive(Default)]
pub enum MarkerType {
    /// Simple position marker
    #[default]
    Position,
    /// Cycle/loop region
    Cycle,
    /// Arranger section
    Arranger,
    /// Punch in point
    PunchIn,
    /// Punch out point
    PunchOut,
    /// Cue point (for video sync)
    Cue,
}


// ═══════════════════════════════════════════════════════════════════════════════
// MARKER
// ═══════════════════════════════════════════════════════════════════════════════

/// A marker on the timeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Marker {
    /// Unique ID
    pub id: MarkerId,
    /// Display name
    pub name: String,
    /// Marker type
    pub marker_type: MarkerType,
    /// Position in samples
    pub position: u64,
    /// End position (for cycle/arranger markers)
    pub end_position: Option<u64>,
    /// Color (RGBA)
    pub color: u32,
    /// Description/notes
    pub description: String,
    /// Keyboard shortcut number (1-9, 0)
    pub shortcut: Option<u8>,
    /// Is locked (prevent movement)
    pub locked: bool,
}

impl Marker {
    /// Create position marker
    pub fn position(name: &str, position: u64) -> Self {
        Self {
            id: new_marker_id(),
            name: name.to_string(),
            marker_type: MarkerType::Position,
            position,
            end_position: None,
            color: 0x4a9eff, // Blue
            description: String::new(),
            shortcut: None,
            locked: false,
        }
    }

    /// Create cycle marker
    pub fn cycle(name: &str, start: u64, end: u64) -> Self {
        Self {
            id: new_marker_id(),
            name: name.to_string(),
            marker_type: MarkerType::Cycle,
            position: start,
            end_position: Some(end),
            color: 0x40ff90, // Green
            description: String::new(),
            shortcut: None,
            locked: false,
        }
    }

    /// Create arranger section
    pub fn arranger(name: &str, start: u64, end: u64) -> Self {
        Self {
            id: new_marker_id(),
            name: name.to_string(),
            marker_type: MarkerType::Arranger,
            position: start,
            end_position: Some(end),
            color: 0xff9040, // Orange
            description: String::new(),
            shortcut: None,
            locked: false,
        }
    }

    /// Create punch in marker
    pub fn punch_in(position: u64) -> Self {
        Self {
            id: new_marker_id(),
            name: "Punch In".to_string(),
            marker_type: MarkerType::PunchIn,
            position,
            end_position: None,
            color: 0xff4060, // Red
            description: String::new(),
            shortcut: None,
            locked: false,
        }
    }

    /// Create punch out marker
    pub fn punch_out(position: u64) -> Self {
        Self {
            id: new_marker_id(),
            name: "Punch Out".to_string(),
            marker_type: MarkerType::PunchOut,
            position,
            end_position: None,
            color: 0xff4060, // Red
            description: String::new(),
            shortcut: None,
            locked: false,
        }
    }

    /// Get length (for cycle/arranger)
    pub fn length(&self) -> Option<u64> {
        self.end_position
            .map(|end| end.saturating_sub(self.position))
    }

    /// Check if position is within marker (for cycle/arranger)
    pub fn contains(&self, pos: u64) -> bool {
        match self.end_position {
            Some(end) => pos >= self.position && pos < end,
            None => pos == self.position,
        }
    }

    /// Move marker
    pub fn move_to(&mut self, new_position: u64) {
        if self.locked {
            return;
        }

        if let Some(end) = self.end_position {
            let length = end - self.position;
            self.end_position = Some(new_position + length);
        }
        self.position = new_position;
    }

    /// Resize (for cycle/arranger)
    pub fn resize(&mut self, new_end: u64) {
        if self.locked {
            return;
        }

        if self.end_position.is_some() && new_end > self.position {
            self.end_position = Some(new_end);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOCATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Left/Right locators for cycle playback
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct Locators {
    /// Left locator position
    pub left: u64,
    /// Right locator position
    pub right: u64,
    /// Cycle enabled
    pub cycle_enabled: bool,
    /// Auto punch enabled
    pub punch_enabled: bool,
}

impl Locators {
    pub fn new(left: u64, right: u64) -> Self {
        Self {
            left,
            right,
            cycle_enabled: false,
            punch_enabled: false,
        }
    }

    /// Set from marker
    pub fn set_from_cycle(&mut self, marker: &Marker) {
        if let Some(end) = marker.end_position {
            self.left = marker.position;
            self.right = end;
        }
    }

    /// Length between locators
    pub fn length(&self) -> u64 {
        self.right.saturating_sub(self.left)
    }

    /// Check if position is in cycle range
    pub fn in_range(&self, pos: u64) -> bool {
        pos >= self.left && pos < self.right
    }

    /// Get loop position (wraps around if cycling)
    pub fn loop_position(&self, pos: u64) -> u64 {
        if !self.cycle_enabled || pos < self.left {
            return pos;
        }

        let length = self.length();
        if length == 0 {
            return self.left;
        }

        let offset = (pos - self.left) % length;
        self.left + offset
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ARRANGER TRACK
// ═══════════════════════════════════════════════════════════════════════════════

/// Arranger chain entry (for non-linear playback)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArrangerEntry {
    /// Reference to arranger marker ID
    pub marker_id: MarkerId,
    /// Number of repeats
    pub repeats: u32,
    /// Is muted
    pub muted: bool,
}

/// Arranger chain for song arrangement
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ArrangerChain {
    /// Entries in order
    pub entries: Vec<ArrangerEntry>,
    /// Is active (use arranger instead of linear)
    pub active: bool,
    /// Current playback index
    pub current_index: usize,
    /// Current repeat count
    pub current_repeat: u32,
}

impl ArrangerChain {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add section to chain
    pub fn add(&mut self, marker_id: MarkerId, repeats: u32) {
        self.entries.push(ArrangerEntry {
            marker_id,
            repeats,
            muted: false,
        });
    }

    /// Remove section
    pub fn remove(&mut self, index: usize) {
        if index < self.entries.len() {
            self.entries.remove(index);
        }
    }

    /// Move section
    pub fn move_entry(&mut self, from: usize, to: usize) {
        if from < self.entries.len() && to < self.entries.len() {
            let entry = self.entries.remove(from);
            self.entries.insert(to, entry);
        }
    }

    /// Clear chain
    pub fn clear(&mut self) {
        self.entries.clear();
        self.current_index = 0;
        self.current_repeat = 0;
    }

    /// Reset playback
    pub fn reset(&mut self) {
        self.current_index = 0;
        self.current_repeat = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKER TRACK
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages all markers
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MarkerTrack {
    /// All markers
    pub markers: HashMap<MarkerId, Marker>,
    /// Locators
    pub locators: Locators,
    /// Arranger chain
    pub arranger: ArrangerChain,
    /// Default color for new markers
    pub default_color: u32,
}

impl MarkerTrack {
    pub fn new() -> Self {
        Self {
            default_color: 0x4a9eff,
            ..Default::default()
        }
    }

    /// Add marker
    pub fn add(&mut self, marker: Marker) -> MarkerId {
        let id = marker.id;
        self.markers.insert(id, marker);
        id
    }

    /// Remove marker
    pub fn remove(&mut self, id: MarkerId) -> Option<Marker> {
        self.markers.remove(&id)
    }

    /// Get marker by ID
    pub fn get(&self, id: MarkerId) -> Option<&Marker> {
        self.markers.get(&id)
    }

    /// Get mutable marker
    pub fn get_mut(&mut self, id: MarkerId) -> Option<&mut Marker> {
        self.markers.get_mut(&id)
    }

    /// Get markers by type
    pub fn by_type(&self, marker_type: MarkerType) -> Vec<&Marker> {
        self.markers
            .values()
            .filter(|m| m.marker_type == marker_type)
            .collect()
    }

    /// Get markers in range
    pub fn in_range(&self, start: u64, end: u64) -> Vec<&Marker> {
        self.markers
            .values()
            .filter(|m| {
                let marker_end = m.end_position.unwrap_or(m.position);
                m.position < end && marker_end > start
            })
            .collect()
    }

    /// Get all position markers sorted by position
    pub fn position_markers_sorted(&self) -> Vec<&Marker> {
        let mut markers: Vec<_> = self
            .markers
            .values()
            .filter(|m| m.marker_type == MarkerType::Position)
            .collect();
        markers.sort_by_key(|m| m.position);
        markers
    }

    /// Get all cycle markers sorted
    pub fn cycle_markers_sorted(&self) -> Vec<&Marker> {
        let mut markers: Vec<_> = self
            .markers
            .values()
            .filter(|m| m.marker_type == MarkerType::Cycle)
            .collect();
        markers.sort_by_key(|m| m.position);
        markers
    }

    /// Get all arranger sections sorted
    pub fn arranger_sections_sorted(&self) -> Vec<&Marker> {
        let mut markers: Vec<_> = self
            .markers
            .values()
            .filter(|m| m.marker_type == MarkerType::Arranger)
            .collect();
        markers.sort_by_key(|m| m.position);
        markers
    }

    /// Find marker by shortcut
    pub fn by_shortcut(&self, shortcut: u8) -> Option<&Marker> {
        self.markers.values().find(|m| m.shortcut == Some(shortcut))
    }

    /// Get next marker after position
    pub fn next_marker(&self, pos: u64) -> Option<&Marker> {
        self.markers
            .values()
            .filter(|m| m.position > pos)
            .min_by_key(|m| m.position)
    }

    /// Get previous marker before position
    pub fn prev_marker(&self, pos: u64) -> Option<&Marker> {
        self.markers
            .values()
            .filter(|m| m.position < pos)
            .max_by_key(|m| m.position)
    }

    /// Set cycle from marker
    pub fn set_cycle_from_marker(&mut self, id: MarkerId) {
        if let Some(marker) = self.markers.get(&id)
            && marker.end_position.is_some() {
                self.locators.set_from_cycle(marker);
            }
    }

    /// Create quick marker at position
    pub fn add_quick_marker(&mut self, position: u64) -> MarkerId {
        let count = self.by_type(MarkerType::Position).len() + 1;
        let marker = Marker::position(&format!("Marker {}", count), position);
        self.add(marker)
    }

    /// Delete all markers of type
    pub fn delete_by_type(&mut self, marker_type: MarkerType) {
        self.markers.retain(|_, m| m.marker_type != marker_type);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_marker_creation() {
        let marker = Marker::position("Intro", 0);
        assert_eq!(marker.name, "Intro");
        assert_eq!(marker.position, 0);
        assert_eq!(marker.marker_type, MarkerType::Position);
    }

    #[test]
    fn test_cycle_marker() {
        let marker = Marker::cycle("Chorus", 48000, 96000);
        assert_eq!(marker.length(), Some(48000));
        assert!(marker.contains(50000));
        assert!(!marker.contains(100000));
    }

    #[test]
    fn test_locators() {
        let mut loc = Locators::new(0, 48000);
        loc.cycle_enabled = true;

        // Position 60000 should loop to 12000
        let looped = loc.loop_position(60000);
        assert_eq!(looped, 12000);
    }

    #[test]
    fn test_marker_track() {
        let mut track = MarkerTrack::new();

        let m1 = track.add(Marker::position("Start", 0));
        let m2 = track.add(Marker::position("Verse", 48000));
        let _m3 = track.add(Marker::position("Chorus", 96000));

        let in_range = track.in_range(24000, 72000);
        assert_eq!(in_range.len(), 1);

        let next = track.next_marker(24000);
        assert_eq!(next.map(|m| m.id), Some(m2));

        let prev = track.prev_marker(72000);
        assert_eq!(prev.map(|m| m.id), Some(m2));
    }

    #[test]
    fn test_arranger_chain() {
        let mut chain = ArrangerChain::new();
        chain.add(1, 2); // Intro x2
        chain.add(2, 1); // Verse
        chain.add(3, 4); // Chorus x4

        assert_eq!(chain.entries.len(), 3);

        chain.move_entry(2, 0);
        assert_eq!(chain.entries[0].marker_id, 3);
    }
}

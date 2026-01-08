//! History Browser and Snapshots
//!
//! Provides visual history browsing like Photoshop:
//! - Timeline of all changes
//! - Named snapshots
//! - Branching history support
//! - History export/import

use std::collections::VecDeque;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

// ============ History Entry ============

/// Unique identifier for history entries
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct HistoryId(pub u64);

impl HistoryId {
    pub fn new() -> Self {
        Self(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(0),
        )
    }
}

impl Default for HistoryId {
    fn default() -> Self {
        Self::new()
    }
}

/// Type of history entry
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HistoryEntryType {
    /// Regular action
    Action,
    /// User-created snapshot
    Snapshot,
    /// Auto-snapshot (created automatically at intervals)
    AutoSnapshot,
    /// Branch point
    Branch,
}

/// Single history entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryEntry {
    /// Unique ID
    pub id: HistoryId,
    /// Entry type
    pub entry_type: HistoryEntryType,
    /// Display name
    pub name: String,
    /// Description
    pub description: Option<String>,
    /// Timestamp (Unix ms)
    pub timestamp: u64,
    /// Parent entry ID (for branching)
    pub parent_id: Option<HistoryId>,
    /// Whether this is the current state
    pub is_current: bool,
    /// Associated state data (serialized)
    pub state_data: Option<Vec<u8>>,
}

impl HistoryEntry {
    pub fn action(name: impl Into<String>) -> Self {
        Self {
            id: HistoryId::new(),
            entry_type: HistoryEntryType::Action,
            name: name.into(),
            description: None,
            timestamp: current_timestamp(),
            parent_id: None,
            is_current: false,
            state_data: None,
        }
    }

    pub fn snapshot(name: impl Into<String>) -> Self {
        Self {
            id: HistoryId::new(),
            entry_type: HistoryEntryType::Snapshot,
            name: name.into(),
            description: None,
            timestamp: current_timestamp(),
            parent_id: None,
            is_current: false,
            state_data: None,
        }
    }

    pub fn with_description(mut self, desc: impl Into<String>) -> Self {
        self.description = Some(desc.into());
        self
    }

    pub fn with_state<T: Serialize>(mut self, state: &T) -> Self {
        if let Ok(data) = serde_json::to_vec(state) {
            self.state_data = Some(data);
        }
        self
    }

    pub fn get_state<T: for<'de> Deserialize<'de>>(&self) -> Option<T> {
        self.state_data
            .as_ref()
            .and_then(|data| serde_json::from_slice(data).ok())
    }

    pub fn age_seconds(&self) -> u64 {
        current_timestamp().saturating_sub(self.timestamp) / 1000
    }

    pub fn formatted_time(&self) -> String {
        // Simple time formatting without external deps
        let secs = (self.timestamp / 1000) % 86400;
        let hours = secs / 3600;
        let mins = (secs % 3600) / 60;
        let secs = secs % 60;
        format!("{:02}:{:02}:{:02}", hours, mins, secs)
    }
}

fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

// ============ History Browser ============

/// Maximum history entries
pub const MAX_HISTORY_ENTRIES: usize = 1000;

/// Maximum snapshots
pub const MAX_SNAPSHOTS: usize = 50;

/// History browser with timeline view support
pub struct HistoryBrowser {
    /// All history entries (linear timeline)
    entries: VecDeque<HistoryEntry>,
    /// Named snapshots (quick access)
    snapshots: Vec<HistoryEntry>,
    /// Current position in history
    current_index: usize,
    /// Maximum entries to keep
    max_entries: usize,
    /// Auto-snapshot interval (seconds, 0 = disabled)
    auto_snapshot_interval: u64,
    /// Last auto-snapshot time
    last_auto_snapshot: u64,
    /// History modified callback
    on_change: Option<Box<dyn Fn(&HistoryEntry) + Send + Sync>>,
}

impl HistoryBrowser {
    pub fn new() -> Self {
        Self {
            entries: VecDeque::with_capacity(MAX_HISTORY_ENTRIES),
            snapshots: Vec::with_capacity(MAX_SNAPSHOTS),
            current_index: 0,
            max_entries: MAX_HISTORY_ENTRIES,
            auto_snapshot_interval: 0,
            last_auto_snapshot: current_timestamp(),
            on_change: None,
        }
    }

    /// Set max history entries
    pub fn set_max_entries(&mut self, max: usize) {
        self.max_entries = max.min(MAX_HISTORY_ENTRIES);
        self.trim_history();
    }

    /// Enable auto-snapshots at interval (seconds)
    pub fn set_auto_snapshot_interval(&mut self, seconds: u64) {
        self.auto_snapshot_interval = seconds;
    }

    /// Add a new history entry
    pub fn push(&mut self, mut entry: HistoryEntry) {
        // Check for auto-snapshot
        self.maybe_auto_snapshot();

        // Clear forward history if not at end
        if self.current_index < self.entries.len() {
            self.entries.truncate(self.current_index);
        }

        // Set parent
        if let Some(current) = self.entries.back() {
            entry.parent_id = Some(current.id);
        }

        entry.is_current = true;

        // Mark previous as not current
        if let Some(prev) = self.entries.back_mut() {
            prev.is_current = false;
        }

        self.entries.push_back(entry.clone());
        self.current_index = self.entries.len();

        self.trim_history();

        if let Some(ref callback) = self.on_change {
            callback(&entry);
        }
    }

    /// Create a named snapshot
    pub fn create_snapshot(&mut self, name: impl Into<String>) -> HistoryId {
        let mut snapshot = HistoryEntry::snapshot(name);

        // Copy state from current entry
        if let Some(current) = self.current_entry() {
            snapshot.state_data = current.state_data.clone();
        }

        let id = snapshot.id;
        self.snapshots.push(snapshot);

        // Trim snapshots
        while self.snapshots.len() > MAX_SNAPSHOTS {
            self.snapshots.remove(0);
        }

        id
    }

    /// Create snapshot with state data
    pub fn create_snapshot_with_state<T: Serialize>(
        &mut self,
        name: impl Into<String>,
        state: &T,
    ) -> HistoryId {
        let snapshot = HistoryEntry::snapshot(name).with_state(state);
        let id = snapshot.id;
        self.snapshots.push(snapshot);

        while self.snapshots.len() > MAX_SNAPSHOTS {
            self.snapshots.remove(0);
        }

        id
    }

    /// Restore to a snapshot
    pub fn restore_snapshot<T: for<'de> Deserialize<'de>>(&self, id: HistoryId) -> Option<T> {
        self.snapshots
            .iter()
            .find(|s| s.id == id)
            .and_then(|s| s.get_state())
    }

    /// Delete a snapshot
    pub fn delete_snapshot(&mut self, id: HistoryId) -> bool {
        if let Some(pos) = self.snapshots.iter().position(|s| s.id == id) {
            self.snapshots.remove(pos);
            true
        } else {
            false
        }
    }

    /// Rename a snapshot
    pub fn rename_snapshot(&mut self, id: HistoryId, new_name: impl Into<String>) -> bool {
        if let Some(snapshot) = self.snapshots.iter_mut().find(|s| s.id == id) {
            snapshot.name = new_name.into();
            true
        } else {
            false
        }
    }

    /// Go back in history
    pub fn go_back(&mut self) -> Option<&HistoryEntry> {
        if self.current_index > 1 {
            // Update current flags
            if let Some(current) = self.entries.get_mut(self.current_index - 1) {
                current.is_current = false;
            }

            self.current_index -= 1;

            if let Some(new_current) = self.entries.get_mut(self.current_index - 1) {
                new_current.is_current = true;
            }

            self.entries.get(self.current_index - 1)
        } else {
            None
        }
    }

    /// Go forward in history
    pub fn go_forward(&mut self) -> Option<&HistoryEntry> {
        if self.current_index < self.entries.len() {
            // Update current flags
            if self.current_index > 0 {
                if let Some(current) = self.entries.get_mut(self.current_index - 1) {
                    current.is_current = false;
                }
            }

            self.current_index += 1;

            if let Some(new_current) = self.entries.get_mut(self.current_index - 1) {
                new_current.is_current = true;
            }

            self.entries.get(self.current_index - 1)
        } else {
            None
        }
    }

    /// Jump to specific entry
    pub fn go_to(&mut self, id: HistoryId) -> Option<&HistoryEntry> {
        if let Some(pos) = self.entries.iter().position(|e| e.id == id) {
            // Update current flags
            for (i, entry) in self.entries.iter_mut().enumerate() {
                entry.is_current = i == pos;
            }

            self.current_index = pos + 1;
            self.entries.get(pos)
        } else {
            None
        }
    }

    /// Get current entry
    pub fn current_entry(&self) -> Option<&HistoryEntry> {
        if self.current_index > 0 {
            self.entries.get(self.current_index - 1)
        } else {
            None
        }
    }

    /// Get all entries
    pub fn entries(&self) -> impl Iterator<Item = &HistoryEntry> {
        self.entries.iter()
    }

    /// Get all snapshots
    pub fn snapshots(&self) -> impl Iterator<Item = &HistoryEntry> {
        self.snapshots.iter()
    }

    /// Get entry count
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Get snapshot count
    pub fn snapshot_count(&self) -> usize {
        self.snapshots.len()
    }

    /// Check if can go back
    pub fn can_go_back(&self) -> bool {
        self.current_index > 1
    }

    /// Check if can go forward
    pub fn can_go_forward(&self) -> bool {
        self.current_index < self.entries.len()
    }

    /// Get current position
    pub fn current_position(&self) -> usize {
        self.current_index
    }

    /// Clear all history
    pub fn clear(&mut self) {
        self.entries.clear();
        self.current_index = 0;
    }

    /// Clear all snapshots
    pub fn clear_snapshots(&mut self) {
        self.snapshots.clear();
    }

    /// Set change callback
    pub fn set_on_change(&mut self, callback: impl Fn(&HistoryEntry) + Send + Sync + 'static) {
        self.on_change = Some(Box::new(callback));
    }

    /// Check and create auto-snapshot if needed
    fn maybe_auto_snapshot(&mut self) {
        if self.auto_snapshot_interval == 0 {
            return;
        }

        let now = current_timestamp();
        let elapsed_secs = (now - self.last_auto_snapshot) / 1000;

        if elapsed_secs >= self.auto_snapshot_interval {
            self.last_auto_snapshot = now;

            let mut snapshot =
                HistoryEntry::snapshot(format!("Auto-snapshot {}", self.snapshots.len() + 1));
            snapshot.entry_type = HistoryEntryType::AutoSnapshot;

            if let Some(current) = self.entries.back() {
                snapshot.state_data = current.state_data.clone();
            }

            self.snapshots.push(snapshot);

            // Trim auto-snapshots
            let auto_count = self
                .snapshots
                .iter()
                .filter(|s| s.entry_type == HistoryEntryType::AutoSnapshot)
                .count();

            if auto_count > 10 {
                // Remove oldest auto-snapshot
                if let Some(pos) = self
                    .snapshots
                    .iter()
                    .position(|s| s.entry_type == HistoryEntryType::AutoSnapshot)
                {
                    self.snapshots.remove(pos);
                }
            }
        }
    }

    /// Trim history to max size
    fn trim_history(&mut self) {
        while self.entries.len() > self.max_entries {
            self.entries.pop_front();
            if self.current_index > 0 {
                self.current_index -= 1;
            }
        }
    }

    /// Get summary for UI display
    pub fn summary(&self) -> HistorySummary {
        HistorySummary {
            total_entries: self.entries.len(),
            current_position: self.current_index,
            snapshot_count: self.snapshots.len(),
            can_undo: self.can_go_back(),
            can_redo: self.can_go_forward(),
            current_action: self.current_entry().map(|e| e.name.clone()),
        }
    }
}

impl Default for HistoryBrowser {
    fn default() -> Self {
        Self::new()
    }
}

/// History summary for UI
#[derive(Debug, Clone)]
pub struct HistorySummary {
    pub total_entries: usize,
    pub current_position: usize,
    pub snapshot_count: usize,
    pub can_undo: bool,
    pub can_redo: bool,
    pub current_action: Option<String>,
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_history_push() {
        let mut history = HistoryBrowser::new();

        history.push(HistoryEntry::action("Action 1"));
        history.push(HistoryEntry::action("Action 2"));
        history.push(HistoryEntry::action("Action 3"));

        assert_eq!(history.len(), 3);
        assert_eq!(history.current_position(), 3);
    }

    #[test]
    fn test_history_navigation() {
        let mut history = HistoryBrowser::new();

        history.push(HistoryEntry::action("Action 1"));
        history.push(HistoryEntry::action("Action 2"));
        history.push(HistoryEntry::action("Action 3"));

        // Go back twice
        assert!(history.go_back().is_some());
        assert!(history.go_back().is_some());
        assert_eq!(history.current_position(), 1);

        // Go forward once
        assert!(history.go_forward().is_some());
        assert_eq!(history.current_position(), 2);
    }

    #[test]
    fn test_snapshots() {
        let mut history = HistoryBrowser::new();

        history.push(HistoryEntry::action("Action 1"));
        let id = history.create_snapshot("My Snapshot");

        assert_eq!(history.snapshot_count(), 1);
        assert!(history.delete_snapshot(id));
        assert_eq!(history.snapshot_count(), 0);
    }

    #[test]
    fn test_history_branch() {
        let mut history = HistoryBrowser::new();

        history.push(HistoryEntry::action("Action 1"));
        history.push(HistoryEntry::action("Action 2"));
        history.push(HistoryEntry::action("Action 3"));

        // Go back and create new branch
        history.go_back();
        history.push(HistoryEntry::action("Branch Action"));

        // Should have truncated forward history
        assert_eq!(history.len(), 3);
    }
}

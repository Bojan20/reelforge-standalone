//! Group and VCA Track System
//!
//! Professional group/VCA control like Cubase/Pro Tools:
//! - Group channels (link faders, mutes, solos, pans)
//! - VCA faders (non-destructive level control)
//! - Folder tracks (visual organization)
//! - Automation spill (edit group automation)
//!
//! ## VCA vs Group
//! - Group: Actually sums audio through group bus
//! - VCA: Controls linked faders without audio routing
//!
//! ## Link Modes
//! - Absolute: All linked channels move to same value
//! - Relative: Channels maintain offset, move together

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Group ID
pub type GroupId = u64;

/// VCA ID
pub type VcaId = u64;

/// Track ID - using u64 directly for compatibility with track_manager
/// Note: rf-core::TrackId is a newtype struct, this is a type alias for internal use
pub type TrackId = u64;

static NEXT_GROUP_ID: AtomicU64 = AtomicU64::new(1);
static NEXT_VCA_ID: AtomicU64 = AtomicU64::new(1);

fn new_group_id() -> GroupId {
    NEXT_GROUP_ID.fetch_add(1, Ordering::Relaxed)
}

fn new_vca_id() -> VcaId {
    NEXT_VCA_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════════
// LINK PARAMETERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Parameters that can be linked in a group
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum LinkParameter {
    /// Volume fader
    Volume,
    /// Pan control
    Pan,
    /// Mute button
    Mute,
    /// Solo button
    Solo,
    /// Record arm
    RecordArm,
    /// Monitor
    Monitor,
    /// All insert bypass states
    InsertBypass,
    /// Send levels
    SendLevel,
    /// Automation mode
    AutomationMode,
}

/// Link mode for parameter changes
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum LinkMode {
    /// Absolute: all move to same value
    Absolute,
    /// Relative: maintain offsets
    #[default]
    Relative,
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP CHANNEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Group for linking track parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Group {
    /// Unique ID
    pub id: GroupId,
    /// Display name
    pub name: String,
    /// Member track IDs
    pub members: HashSet<TrackId>,
    /// Linked parameters
    pub linked_params: HashSet<LinkParameter>,
    /// Link mode
    pub link_mode: LinkMode,
    /// Color
    pub color: u32,
    /// Is active
    pub active: bool,
}

impl Group {
    pub fn new(name: &str) -> Self {
        Self {
            id: new_group_id(),
            name: name.to_string(),
            members: HashSet::new(),
            linked_params: HashSet::from([
                LinkParameter::Volume,
                LinkParameter::Mute,
                LinkParameter::Solo,
            ]),
            link_mode: LinkMode::Relative,
            color: 0x4a9eff, // Default blue
            active: true,
        }
    }

    /// Add track to group
    pub fn add_member(&mut self, track_id: TrackId) {
        self.members.insert(track_id);
    }

    /// Remove track from group
    pub fn remove_member(&mut self, track_id: TrackId) {
        self.members.remove(&track_id);
    }

    /// Check if track is member
    pub fn has_member(&self, track_id: TrackId) -> bool {
        self.members.contains(&track_id)
    }

    /// Toggle parameter linking
    pub fn toggle_link(&mut self, param: LinkParameter) {
        if self.linked_params.contains(&param) {
            self.linked_params.remove(&param);
        } else {
            self.linked_params.insert(param);
        }
    }

    /// Check if parameter is linked
    pub fn is_linked(&self, param: LinkParameter) -> bool {
        self.linked_params.contains(&param)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VCA FADER
// ═══════════════════════════════════════════════════════════════════════════════

/// VCA (Voltage Controlled Amplifier) fader
///
/// Controls level of multiple tracks without audio routing.
/// The VCA level is multiplied with each track's level.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcaFader {
    /// Unique ID
    pub id: VcaId,
    /// Display name
    pub name: String,
    /// Controlled track IDs
    pub members: HashSet<TrackId>,
    /// VCA level in dB
    pub level_db: f64,
    /// Is muted
    pub muted: bool,
    /// Is soloed
    pub soloed: bool,
    /// Color
    pub color: u32,
    /// Trim offset per track (for relative control)
    pub trim_offsets: HashMap<TrackId, f64>,
}

impl VcaFader {
    pub fn new(name: &str) -> Self {
        Self {
            id: new_vca_id(),
            name: name.to_string(),
            members: HashSet::new(),
            level_db: 0.0,
            muted: false,
            soloed: false,
            color: 0xff9040, // Orange
            trim_offsets: HashMap::new(),
        }
    }

    /// Add track to VCA
    pub fn add_member(&mut self, track_id: TrackId) {
        self.members.insert(track_id);
        self.trim_offsets.insert(track_id, 0.0);
    }

    /// Remove track from VCA
    pub fn remove_member(&mut self, track_id: TrackId) {
        self.members.remove(&track_id);
        self.trim_offsets.remove(&track_id);
    }

    /// Get effective level for a track
    pub fn effective_level(&self, track_id: TrackId, track_level_db: f64) -> f64 {
        if !self.members.contains(&track_id) {
            return track_level_db;
        }

        let trim = self.trim_offsets.get(&track_id).copied().unwrap_or(0.0);
        track_level_db + self.level_db + trim
    }

    /// Is track effectively muted by VCA
    pub fn is_track_muted(&self, track_id: TrackId) -> bool {
        self.members.contains(&track_id) && self.muted
    }

    /// Set VCA level
    pub fn set_level(&mut self, db: f64) {
        self.level_db = db.clamp(-144.0, 12.0);
    }

    /// Adjust trim for specific track
    pub fn set_trim(&mut self, track_id: TrackId, db: f64) {
        if self.members.contains(&track_id) {
            self.trim_offsets.insert(track_id, db);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FOLDER TRACK
// ═══════════════════════════════════════════════════════════════════════════════

/// Folder track for visual organization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderTrack {
    /// Unique ID
    pub id: TrackId,
    /// Display name
    pub name: String,
    /// Child track IDs
    pub children: Vec<TrackId>,
    /// Is expanded in UI
    pub expanded: bool,
    /// Color
    pub color: u32,
    /// Solo defeats folder (folder solo affects children)
    pub solo_defeat: bool,
}

impl FolderTrack {
    pub fn new(id: TrackId, name: &str) -> Self {
        Self {
            id,
            name: name.to_string(),
            children: Vec::new(),
            expanded: true,
            color: 0x808080, // Gray
            solo_defeat: false,
        }
    }

    /// Add child track
    pub fn add_child(&mut self, track_id: TrackId) {
        if !self.children.contains(&track_id) {
            self.children.push(track_id);
        }
    }

    /// Remove child track
    pub fn remove_child(&mut self, track_id: TrackId) {
        self.children.retain(|&id| id != track_id);
    }

    /// Move child to position
    pub fn move_child(&mut self, track_id: TrackId, new_index: usize) {
        if let Some(old_index) = self.children.iter().position(|&id| id == track_id) {
            self.children.remove(old_index);
            let insert_at = new_index.min(self.children.len());
            self.children.insert(insert_at, track_id);
        }
    }

    /// Toggle expanded
    pub fn toggle(&mut self) {
        self.expanded = !self.expanded;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages all groups, VCAs, and folders
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupManager {
    /// All groups
    pub groups: HashMap<GroupId, Group>,
    /// All VCA faders
    pub vcas: HashMap<VcaId, VcaFader>,
    /// All folder tracks
    pub folders: HashMap<TrackId, FolderTrack>,
    /// Track to group mapping (for quick lookup)
    track_groups: HashMap<TrackId, HashSet<GroupId>>,
    /// Track to VCA mapping
    track_vcas: HashMap<TrackId, HashSet<VcaId>>,
}

impl GroupManager {
    pub fn new() -> Self {
        Self::default()
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Group Management
    // ─────────────────────────────────────────────────────────────────────────────

    /// Create new group
    pub fn create_group(&mut self, name: &str) -> GroupId {
        let group = Group::new(name);
        let id = group.id;
        self.groups.insert(id, group);
        id
    }

    /// Delete group
    pub fn delete_group(&mut self, id: GroupId) {
        if let Some(group) = self.groups.remove(&id) {
            // Remove from track mappings
            for track_id in group.members {
                if let Some(groups) = self.track_groups.get_mut(&track_id) {
                    groups.remove(&id);
                }
            }
        }
    }

    /// Add track to group
    pub fn add_to_group(&mut self, group_id: GroupId, track_id: TrackId) {
        if let Some(group) = self.groups.get_mut(&group_id) {
            group.add_member(track_id);
            self.track_groups
                .entry(track_id)
                .or_default()
                .insert(group_id);
        }
    }

    /// Remove track from group
    pub fn remove_from_group(&mut self, group_id: GroupId, track_id: TrackId) {
        if let Some(group) = self.groups.get_mut(&group_id) {
            group.remove_member(track_id);
            if let Some(groups) = self.track_groups.get_mut(&track_id) {
                groups.remove(&group_id);
            }
        }
    }

    /// Get groups for track
    pub fn groups_for_track(&self, track_id: TrackId) -> Vec<&Group> {
        self.track_groups
            .get(&track_id)
            .map(|ids| ids.iter().filter_map(|id| self.groups.get(id)).collect())
            .unwrap_or_default()
    }

    /// Get linked tracks for a parameter change
    pub fn get_linked_tracks(&self, source_track: TrackId, param: LinkParameter) -> Vec<TrackId> {
        let mut linked = Vec::new();

        if let Some(group_ids) = self.track_groups.get(&source_track) {
            for group_id in group_ids {
                if let Some(group) = self.groups.get(group_id)
                    && group.active
                    && group.is_linked(param)
                {
                    for &member in &group.members {
                        if member != source_track && !linked.contains(&member) {
                            linked.push(member);
                        }
                    }
                }
            }
        }

        linked
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // VCA Management
    // ─────────────────────────────────────────────────────────────────────────────

    /// Create new VCA
    pub fn create_vca(&mut self, name: &str) -> VcaId {
        let vca = VcaFader::new(name);
        let id = vca.id;
        self.vcas.insert(id, vca);
        id
    }

    /// Delete VCA
    pub fn delete_vca(&mut self, id: VcaId) {
        if let Some(vca) = self.vcas.remove(&id) {
            for track_id in vca.members {
                if let Some(vcas) = self.track_vcas.get_mut(&track_id) {
                    vcas.remove(&id);
                }
            }
        }
    }

    /// Add track to VCA
    pub fn add_to_vca(&mut self, vca_id: VcaId, track_id: TrackId) {
        if let Some(vca) = self.vcas.get_mut(&vca_id) {
            vca.add_member(track_id);
            self.track_vcas.entry(track_id).or_default().insert(vca_id);
        }
    }

    /// Remove track from VCA
    pub fn remove_from_vca(&mut self, vca_id: VcaId, track_id: TrackId) {
        if let Some(vca) = self.vcas.get_mut(&vca_id) {
            vca.remove_member(track_id);
            if let Some(vcas) = self.track_vcas.get_mut(&track_id) {
                vcas.remove(&vca_id);
            }
        }
    }

    /// Get effective VCA level for track (sum of all VCAs)
    pub fn get_vca_contribution(&self, track_id: TrackId) -> f64 {
        self.track_vcas
            .get(&track_id)
            .map(|vca_ids| {
                vca_ids
                    .iter()
                    .filter_map(|id| self.vcas.get(id))
                    .map(|vca| vca.level_db)
                    .sum()
            })
            .unwrap_or(0.0)
    }

    /// Check if track is muted by any VCA
    pub fn is_vca_muted(&self, track_id: TrackId) -> bool {
        self.track_vcas
            .get(&track_id)
            .map(|vca_ids| {
                vca_ids
                    .iter()
                    .filter_map(|id| self.vcas.get(id))
                    .any(|vca| vca.muted)
            })
            .unwrap_or(false)
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Folder Management
    // ─────────────────────────────────────────────────────────────────────────────

    /// Create folder track
    pub fn create_folder(&mut self, id: TrackId, name: &str) {
        let folder = FolderTrack::new(id, name);
        self.folders.insert(id, folder);
    }

    /// Delete folder
    pub fn delete_folder(&mut self, id: TrackId) {
        self.folders.remove(&id);
    }

    /// Get folder for track (if any)
    pub fn parent_folder(&self, track_id: TrackId) -> Option<&FolderTrack> {
        self.folders
            .values()
            .find(|f| f.children.contains(&track_id))
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // FFI Helper Methods (for Flutter bridge)
    // ─────────────────────────────────────────────────────────────────────────────

    /// List all VCAs with their info
    pub fn list_vcas(&self) -> Vec<(VcaId, VcaInfo)> {
        self.vcas
            .iter()
            .map(|(&id, vca)| {
                (
                    id,
                    VcaInfo {
                        name: vca.name.clone(),
                        level: db_to_linear(vca.level_db),
                        is_muted: vca.muted,
                        color: vca.color,
                        assigned_tracks: vca.members.iter().copied().collect(),
                    },
                )
            })
            .collect()
    }

    /// List all groups with their info
    pub fn list_groups(&self) -> Vec<(GroupId, GroupInfo)> {
        self.groups
            .iter()
            .map(|(&id, group)| {
                (
                    id,
                    GroupInfo {
                        name: group.name.clone(),
                        color: group.color,
                        tracks: group.members.iter().copied().collect(),
                        linked_params: group.linked_params.clone(),
                    },
                )
            })
            .collect()
    }

    /// Get VCA level (linear)
    pub fn get_vca_level(&self, vca_id: VcaId) -> Option<f64> {
        self.vcas.get(&vca_id).map(|vca| db_to_linear(vca.level_db))
    }

    /// Get effective volume for track including VCA contribution
    pub fn get_track_effective_volume(&self, track_id: TrackId, base_volume: f64) -> f64 {
        let vca_db = self.get_vca_contribution(track_id);
        // Convert: base is linear, VCA contribution is in dB
        let base_db = linear_to_db(base_volume);
        db_to_linear(base_db + vca_db)
    }
}

/// VCA info for FFI
#[derive(Debug, Clone)]
pub struct VcaInfo {
    pub name: String,
    pub level: f64,
    pub is_muted: bool,
    pub color: u32,
    pub assigned_tracks: Vec<TrackId>,
}

/// Group info for FFI
#[derive(Debug, Clone)]
pub struct GroupInfo {
    pub name: String,
    pub color: u32,
    pub tracks: Vec<TrackId>,
    pub linked_params: HashSet<LinkParameter>,
}

// Helper functions for dB conversion
fn db_to_linear(db: f64) -> f64 {
    if db <= -144.0 {
        0.0
    } else {
        10.0_f64.powf(db / 20.0)
    }
}

fn linear_to_db(linear: f64) -> f64 {
    if linear <= 0.0 {
        -144.0
    } else {
        20.0 * linear.log10()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_group_creation() {
        let mut manager = GroupManager::new();
        let group_id = manager.create_group("Drums");

        manager.add_to_group(group_id, 1);
        manager.add_to_group(group_id, 2);
        manager.add_to_group(group_id, 3);

        let groups = manager.groups_for_track(1);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].members.len(), 3);
    }

    #[test]
    fn test_linked_tracks() {
        let mut manager = GroupManager::new();
        let group_id = manager.create_group("Backing Vocals");

        manager.add_to_group(group_id, 10);
        manager.add_to_group(group_id, 11);
        manager.add_to_group(group_id, 12);

        let linked = manager.get_linked_tracks(10, LinkParameter::Volume);
        assert_eq!(linked.len(), 2);
        assert!(linked.contains(&11));
        assert!(linked.contains(&12));
    }

    #[test]
    fn test_vca() {
        let mut manager = GroupManager::new();
        let vca_id = manager.create_vca("Drums VCA");

        manager.add_to_vca(vca_id, 1);
        manager.add_to_vca(vca_id, 2);

        if let Some(vca) = manager.vcas.get_mut(&vca_id) {
            vca.set_level(-6.0);
        }

        let contribution = manager.get_vca_contribution(1);
        assert!((contribution - (-6.0)).abs() < 0.001);
    }

    #[test]
    fn test_folder() {
        let mut manager = GroupManager::new();
        manager.create_folder(100, "Drums Folder");

        if let Some(folder) = manager.folders.get_mut(&100) {
            folder.add_child(1);
            folder.add_child(2);
            folder.add_child(3);
        }

        let parent = manager.parent_folder(2);
        assert!(parent.is_some());
        assert_eq!(parent.unwrap().name, "Drums Folder");
    }
}

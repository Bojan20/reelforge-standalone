//! Direct Routing Matrix
//!
//! Cubase-style direct routing allowing tracks to output to multiple
//! destinations simultaneously with individual gain control.
//!
//! Key features:
//! - Up to 8 summing destinations per track
//! - Individual gain per destination
//! - Quick A/B switching between routing presets
//! - Pre/post fader routing options

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::{Decibels, TrackId};

/// Maximum number of direct routing destinations per track
pub const MAX_DIRECT_ROUTES: usize = 8;

/// Direct route destination
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub enum RouteDestination {
    /// Route to a track (including buses)
    Track(TrackId),
    /// Route to hardware output pair
    HardwareOutput(usize),
    /// Route to master bus
    #[default]
    Master,
}

/// Single direct route configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectRoute {
    /// Destination
    pub destination: RouteDestination,
    /// Gain offset (relative to fader)
    pub gain: Decibels,
    /// Route is active
    pub active: bool,
    /// Pre-fader routing
    pub pre_fader: bool,
    /// Route summing mode
    pub summing_mode: SummingMode,
}

impl Default for DirectRoute {
    fn default() -> Self {
        Self {
            destination: RouteDestination::Master,
            gain: Decibels::ZERO,
            active: true,
            pre_fader: false,
            summing_mode: SummingMode::Normal,
        }
    }
}

/// Summing mode for direct routing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum SummingMode {
    /// Normal summing (add to destination)
    #[default]
    Normal,
    /// Exclusive (mute other routes when active)
    Exclusive,
    /// Replace (overwrite destination)
    Replace,
}

/// Direct routing slot (8 slots per track like Cubase)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DirectRoutingSlot {
    /// Routes in this slot (A/B/C/D banks)
    pub routes: [Option<DirectRoute>; 4],
    /// Currently active bank (0-3)
    pub active_bank: usize,
}

impl DirectRoutingSlot {
    /// Get active route
    pub fn active_route(&self) -> Option<&DirectRoute> {
        self.routes[self.active_bank].as_ref()
    }

    /// Set route for a bank
    pub fn set_route(&mut self, bank: usize, route: Option<DirectRoute>) {
        if bank < 4 {
            self.routes[bank] = route;
        }
    }

    /// Switch to bank
    pub fn switch_bank(&mut self, bank: usize) {
        if bank < 4 {
            self.active_bank = bank;
        }
    }
}

/// Direct routing matrix for a track
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DirectRoutingMatrix {
    /// 8 routing slots
    pub slots: [DirectRoutingSlot; MAX_DIRECT_ROUTES],
    /// Global enable/disable
    pub enabled: bool,
    /// Current preset name
    pub preset_name: Option<String>,
}

impl DirectRoutingMatrix {
    /// Create new empty matrix
    pub fn new() -> Self {
        Self {
            slots: Default::default(),
            enabled: true,
            preset_name: None,
        }
    }

    /// Create with default master routing on slot 0
    pub fn with_master() -> Self {
        let mut matrix = Self::new();
        matrix.slots[0].routes[0] = Some(DirectRoute::default());
        matrix
    }

    /// Get all active routes
    pub fn active_routes(&self) -> Vec<(usize, &DirectRoute)> {
        if !self.enabled {
            return Vec::new();
        }

        self.slots
            .iter()
            .enumerate()
            .filter_map(|(i, slot)| slot.active_route().filter(|r| r.active).map(|r| (i, r)))
            .collect()
    }

    /// Set route at slot and bank
    pub fn set_route(&mut self, slot: usize, bank: usize, route: Option<DirectRoute>) {
        if slot < MAX_DIRECT_ROUTES {
            self.slots[slot].set_route(bank, route);
        }
    }

    /// Quick route to track
    pub fn route_to(&mut self, slot: usize, dest: RouteDestination) {
        if slot < MAX_DIRECT_ROUTES {
            self.slots[slot].routes[0] = Some(DirectRoute {
                destination: dest,
                ..Default::default()
            });
        }
    }

    /// Switch all slots to bank
    pub fn switch_all_to_bank(&mut self, bank: usize) {
        for slot in &mut self.slots {
            slot.switch_bank(bank);
        }
    }

    /// Clear all routes
    pub fn clear(&mut self) {
        for slot in &mut self.slots {
            slot.routes = Default::default();
        }
    }

    /// Count active routes
    pub fn active_count(&self) -> usize {
        self.active_routes().len()
    }
}

/// Routing preset
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingPreset {
    /// Preset name
    pub name: String,
    /// Matrix configuration
    pub matrix: DirectRoutingMatrix,
    /// Created timestamp
    pub created: u64,
}

/// Global routing matrix manager
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RoutingManager {
    /// Per-track routing matrices
    pub track_routing: HashMap<TrackId, DirectRoutingMatrix>,
    /// Saved presets
    pub presets: Vec<RoutingPreset>,
}

impl RoutingManager {
    pub fn new() -> Self {
        Self {
            track_routing: HashMap::new(),
            presets: Vec::new(),
        }
    }

    /// Get routing matrix for track
    pub fn get(&self, track_id: TrackId) -> Option<&DirectRoutingMatrix> {
        self.track_routing.get(&track_id)
    }

    /// Get or create routing matrix for track
    pub fn get_or_create(&mut self, track_id: TrackId) -> &mut DirectRoutingMatrix {
        self.track_routing
            .entry(track_id)
            .or_insert_with(DirectRoutingMatrix::with_master)
    }

    /// Set routing matrix for track
    pub fn set(&mut self, track_id: TrackId, matrix: DirectRoutingMatrix) {
        self.track_routing.insert(track_id, matrix);
    }

    /// Get all destinations a track routes to
    pub fn get_destinations(&self, track_id: TrackId) -> Vec<RouteDestination> {
        self.get(track_id)
            .map(|matrix| {
                matrix
                    .active_routes()
                    .into_iter()
                    .map(|(_, route)| route.destination.clone())
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Get all tracks that route to a destination
    pub fn get_sources(&self, dest: &RouteDestination) -> Vec<TrackId> {
        self.track_routing
            .iter()
            .filter(|(_, matrix)| {
                matrix
                    .active_routes()
                    .iter()
                    .any(|(_, route)| match (&route.destination, dest) {
                        (RouteDestination::Track(a), RouteDestination::Track(b)) => a == b,
                        (
                            RouteDestination::HardwareOutput(a),
                            RouteDestination::HardwareOutput(b),
                        ) => a == b,
                        (RouteDestination::Master, RouteDestination::Master) => true,
                        _ => false,
                    })
            })
            .map(|(id, _)| *id)
            .collect()
    }

    /// Save preset
    pub fn save_preset(&mut self, name: &str, track_id: TrackId) {
        if let Some(matrix) = self.get(track_id) {
            self.presets.push(RoutingPreset {
                name: name.to_string(),
                matrix: matrix.clone(),
                created: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(0),
            });
        }
    }

    /// Load preset
    pub fn load_preset(&mut self, preset_name: &str, track_id: TrackId) -> bool {
        if let Some(preset) = self.presets.iter().find(|p| p.name == preset_name) {
            let mut matrix = preset.matrix.clone();
            matrix.preset_name = Some(preset.name.clone());
            self.set(track_id, matrix);
            true
        } else {
            false
        }
    }

    /// Delete preset
    pub fn delete_preset(&mut self, name: &str) {
        self.presets.retain(|p| p.name != name);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_direct_routing_matrix() {
        let mut matrix = DirectRoutingMatrix::with_master();

        // Should have one active route to master
        let routes = matrix.active_routes();
        assert_eq!(routes.len(), 1);

        // Add route to slot 1
        matrix.route_to(1, RouteDestination::Track(TrackId::new(5)));

        let routes = matrix.active_routes();
        assert_eq!(routes.len(), 2);
    }

    #[test]
    fn test_bank_switching() {
        let mut matrix = DirectRoutingMatrix::new();

        // Set up bank A with master
        matrix.set_route(0, 0, Some(DirectRoute::default()));

        // Set up bank B with track
        matrix.set_route(
            0,
            1,
            Some(DirectRoute {
                destination: RouteDestination::Track(TrackId::new(5)),
                ..Default::default()
            }),
        );

        // Default is bank A
        assert!(matches!(
            matrix.slots[0].active_route().unwrap().destination,
            RouteDestination::Master
        ));

        // Switch to bank B
        matrix.slots[0].switch_bank(1);
        assert!(matches!(
            matrix.slots[0].active_route().unwrap().destination,
            RouteDestination::Track(_)
        ));
    }

    #[test]
    fn test_routing_manager() {
        let mut manager = RoutingManager::new();

        let track1 = TrackId::new(1);
        let track2 = TrackId::new(2);

        // Create routing for track1
        let matrix = manager.get_or_create(track1);
        matrix.route_to(1, RouteDestination::Track(track2));

        // Check sources for track2
        let sources = manager.get_sources(&RouteDestination::Track(track2));
        assert!(sources.contains(&track1));
    }
}

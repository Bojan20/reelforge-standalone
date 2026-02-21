//! DAW Mixer Orchestration Layer
//! Pro Tools 2026–class mixer coordination (no audio processing).

use crate::track_manager::TrackManager;
use crate::routing::RoutingGraph;
use std::collections::HashSet;
use std::collections::HashMap;

pub type DawChannelId = u64;

// ==========================
// SessionGraph
// ==========================

pub struct SessionGraph {
    pub track_manager: TrackManager,
    pub routing_graph: RoutingGraph,
}

impl SessionGraph {
    pub fn new(track_manager: TrackManager, routing_graph: RoutingGraph) -> Self {
        Self { track_manager, routing_graph }
    }
}

// ==========================
// Solo Engine
// ==========================

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SoloMode {
    Sip,
    Afl,
    Pfl,
}

#[derive(Debug, Clone)]
pub enum SoloCommand {
    SetSolo { channel: DawChannelId, enabled: bool },
    SetSoloSafe { channel: DawChannelId, safe: bool },
    SetSoloMode { mode: SoloMode },
}

pub struct SoloEngine {
    mode: SoloMode,
}

impl SoloEngine {
    pub fn new() -> Self {
        Self { mode: SoloMode::Sip }
    }

    pub fn handle_command(&mut self, command: SoloCommand) {
        match command {
            SoloCommand::SetSolo { .. } => {}
            SoloCommand::SetSoloSafe { .. } => {}
            SoloCommand::SetSoloMode { mode } => {
                self.mode = mode;
            }
        }
    }
}

// ==========================
// Folder Engine
// ==========================

pub struct FolderEngine;

impl FolderEngine {
    pub fn new() -> Self { Self }
}

// ==========================
// VCA Engine
// ==========================

pub struct VcaEngine;

impl VcaEngine {
    pub fn new() -> Self { Self }
}

// ==========================
// Spill Engine
// ==========================

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpillMode {
    Vca,
    Folder,
}

pub struct SpillEngine {
    mode: SpillMode,
    spill_targets: HashSet<DawChannelId>,
}

impl SpillEngine {
    pub fn new() -> Self {
        Self {
            mode: SpillMode::Vca,
            spill_targets: HashSet::new(),
        }
    }
}

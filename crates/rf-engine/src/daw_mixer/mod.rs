//! DAW Mixer Orchestration Layer
//! Pro Tools 2026–class mixer coordination (no audio processing).

pub mod session_graph;
pub mod solo_engine;
pub mod folder_engine;
pub mod vca_engine;
pub mod spill_engine;
pub mod layout_snapshot;

pub use session_graph::SessionGraph;
pub use solo_engine::{SoloEngine, SoloMode};
pub use folder_engine::FolderEngine;
pub use vca_engine::VcaEngine;
pub use spill_engine::{SpillEngine, SpillMode};
pub use layout_snapshot::LayoutSnapshot;

pub type DawChannelId = u64;

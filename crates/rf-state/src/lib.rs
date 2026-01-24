//! rf-state: State management, undo/redo, presets, automation
//!
//! Provides comprehensive state management:
//! - Full undo/redo with command pattern
//! - Concrete DAW commands (track, clip, mixer, automation)
//! - A/B comparison system (8 slots)
//! - History browser with snapshots
//! - Autosave with crash recovery
//! - Preset management
//! - Project serialization
//! - App preferences
//! - Plugin state persistence (third-party plugins)

mod ab_compare;
mod automation;
mod autosave;
mod clip;
mod commands;
mod history;
mod markers;
mod plugin_state;
mod preferences;
mod preset;
mod project;
mod undo;
mod versions;

pub use ab_compare::*;
pub use automation::*;
pub use autosave::*;
pub use clip::*;
pub use commands::*;
pub use history::*;
pub use markers::*;
pub use plugin_state::*;
pub use preferences::*;
pub use preset::*;
pub use project::*;
pub use undo::*;
pub use versions::*;

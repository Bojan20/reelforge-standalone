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

mod undo;
mod commands;
mod preset;
mod project;
mod automation;
mod ab_compare;
mod history;
mod autosave;
mod clip;
mod markers;

pub use undo::*;
pub use commands::*;
pub use preset::*;
pub use project::*;
pub use automation::*;
pub use ab_compare::*;
pub use history::*;
pub use autosave::*;
pub use clip::*;
pub use markers::*;

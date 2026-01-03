//! rf-state: State management, undo/redo, presets, automation
//!
//! Provides state management with full undo/redo support.

mod undo;
mod preset;
mod project;
mod automation;

pub use undo::*;
pub use preset::*;
pub use project::*;
pub use automation::*;

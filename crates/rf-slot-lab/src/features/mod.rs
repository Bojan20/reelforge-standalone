//! Feature System — Modular feature chapters
//!
//! This module provides a pluggable feature system where each game feature
//! (Free Spins, Cascades, Hold & Win, etc.) is implemented as a separate "chapter"
//! that can be composed to create different games.
//!
//! ## Architecture
//!
//! ```text
//! FeatureRegistry
//!     │
//!     ├── FreeSpinsChapter
//!     ├── CascadesChapter
//!     ├── HoldAndWinChapter
//!     ├── JackpotChapter
//!     └── GambleChapter
//! ```
//!
//! ## Usage
//!
//! ```rust,ignore
//! let mut registry = FeatureRegistry::new();
//!
//! // Get a feature
//! if let Some(fs) = registry.get_mut(&FeatureId::new("free_spins")) {
//!     fs.activate(&context);
//! }
//! ```

mod chapter;
mod context;
mod registry;
mod types;

pub use chapter::*;
pub use context::*;
pub use registry::*;
pub use types::*;

// Feature implementations (to be added)
// mod free_spins;
// mod cascades;
// mod hold_and_win;
// mod jackpot;
// mod gamble;

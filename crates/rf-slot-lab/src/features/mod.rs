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

// Feature implementations
mod cascades;
mod free_spins;
mod gamble;
mod hold_and_win;
mod jackpot;
mod pick_bonus;

pub use chapter::*;
pub use context::*;
pub use registry::*;
pub use types::*;

// Export feature chapters
pub use cascades::{CascadeConfig, CascadeRemoveMode, CascadesChapter};
pub use free_spins::{FreeSpinsChapter, FreeSpinsConfig};
pub use gamble::{GambleChapter, GambleChoice, GambleConfig, GambleOutcome, GambleType};
pub use hold_and_win::{HoldAndWinChapter, HoldAndWinConfig, HoldSymbolType, LockedSymbol};
pub use jackpot::{JackpotChapter, JackpotConfig, JackpotTierConfig};
pub use pick_bonus::{PickBonusChapter, PickBonusConfig, PickBonusStyle, PickItem, PrizeType};

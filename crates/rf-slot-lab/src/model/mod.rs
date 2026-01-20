//! Game Model — Central game definition structures
//!
//! This module defines the core data structures for representing a slot game:
//! - `GameModel` — Complete game configuration
//! - `GameInfo` — Basic game metadata
//! - `GameMode` — GDD-only vs Math-driven mode
//! - `WinMechanism` — Paylines, Ways, Cluster pays
//! - `WinTierConfig` — Win tier thresholds

mod game_info;
mod game_model;
mod math_model;
mod win_mechanism;
mod win_tiers;

pub use game_info::*;
pub use game_model::*;
pub use math_model::*;
pub use win_mechanism::*;
pub use win_tiers::*;

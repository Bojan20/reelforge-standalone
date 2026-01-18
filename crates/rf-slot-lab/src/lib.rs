//! # rf-slot-lab — Synthetic Slot Engine for FluxForge Studio
//!
//! Provides a fully deterministic slot machine simulator for audio-first development.
//! Generates realistic game outcomes with configurable volatility, features, and timing.
//!
//! ## Features
//!
//! - **Synthetic Engine**: Generates dramaturgically realistic slot outcomes
//! - **Volatility Control**: Adjustable win frequency and big win distribution
//! - **Feature Simulation**: Free spins, cascades, jackpots, bonus games
//! - **Stage Generation**: Automatic STAGE event generation for audio triggering
//! - **Timing Profiles**: Normal, Turbo, Studio (instant) timing modes
//!
//! ## Architecture
//!
//! ```text
//! SyntheticSlotEngine
//!     │
//!     ├── GridSpec (reels × rows configuration)
//!     ├── PayTable (symbol values, line patterns)
//!     ├── VolatilityProfile (win distribution)
//!     └── FeatureConfig (bonus frequencies)
//!           │
//!           v
//!     SpinResult → Vec<StageEvent>
//! ```

pub mod config;
pub mod engine;
pub mod paytable;
pub mod spin;
pub mod symbols;
pub mod timing;

pub use config::*;
pub use engine::*;
pub use paytable::*;
pub use spin::*;
pub use symbols::*;
pub use timing::*;

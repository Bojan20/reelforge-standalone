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
//! - **Game Model**: Central game definition from GDD documents
//! - **Feature Registry**: Modular feature chapter system
//! - **Scenario System**: Demo sequences for presentations
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────┐
//! │                      GameModel                          │
//! │  (from GDD or programmatic)                             │
//! └────────────────────────┬────────────────────────────────┘
//!                          │
//!                          ▼
//! ┌─────────────────────────────────────────────────────────┐
//! │              SyntheticSlotEngine                        │
//! │                                                         │
//! │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
//! │  │ GridSpec    │  │ PayTable    │  │ Volatility  │    │
//! │  └─────────────┘  └─────────────┘  └─────────────┘    │
//! │                                                         │
//! │  ┌─────────────────────────────────────────────────┐   │
//! │  │           Feature Registry                       │   │
//! │  │  ├── FreeSpinsChapter                           │   │
//! │  │  ├── CascadesChapter                            │   │
//! │  │  ├── HoldAndWinChapter                          │   │
//! │  │  └── JackpotChapter                             │   │
//! │  └─────────────────────────────────────────────────┘   │
//! └────────────────────────┬────────────────────────────────┘
//!                          │
//!                          ▼
//!                   SpinResult → Vec<StageEvent>
//! ```
//!
//! ## Modes
//!
//! - **GDD-Only**: Scripted outcomes for demos (no RNG)
//! - **Math-Driven**: Real probability distribution with RTP targeting

// ═══════════════════════════════════════════════════════════════════════════════
// CORE MODULES (existing)
// ═══════════════════════════════════════════════════════════════════════════════

pub mod config;
pub mod engine;
pub mod engine_v2;
pub mod paytable;
pub mod spin;
pub mod symbols;
pub mod timing;

// ═══════════════════════════════════════════════════════════════════════════════
// NEW MODULES (Slot Lab Ultimate)
// ═══════════════════════════════════════════════════════════════════════════════

/// Game Model — Central game definition
pub mod model;

/// Feature System — Modular feature chapters
pub mod features;

/// Scenario System — Demo sequences
pub mod scenario;

/// GDD Parser — Parse Game Design Documents
pub mod parser;

// ═══════════════════════════════════════════════════════════════════════════════
// RE-EXPORTS
// ═══════════════════════════════════════════════════════════════════════════════

pub use config::*;
pub use engine::*;
pub use engine_v2::SlotEngineV2;
pub use paytable::*;
pub use spin::*;
pub use symbols::*;
pub use timing::*;

// New module re-exports
pub use features::{FeatureCategory, FeatureChapter, FeatureId, FeatureRegistry};
pub use model::{GameInfo, GameMode, GameModel, Volatility, WinMechanism, WinTierConfig};
pub use parser::{GddParseError, GddParser};
pub use scenario::{DemoScenario, LoopMode, ScenarioPlayback, ScriptedOutcome};

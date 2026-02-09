//! # rf-stage — FluxForge Universal Stage System
//!
//! Defines canonical game stages that all slot engines map to.
//! FluxForge never understands engine-specific events — only STAGES.
//!
//! ## Philosophy
//!
//! All slot games, regardless of engine, pass through the same semantic phases:
//! - Spin starts → Reels stop → Wins evaluated → Features triggered
//!
//! This crate defines these universal stages and provides timing resolution.

pub mod event;
pub mod stage;
pub mod taxonomy;
pub mod timing;
pub mod trace;

pub use event::*;
pub use stage::*;
pub use taxonomy::*;
pub use timing::*;
pub use trace::*;

//! # rf-ingest — FluxForge Universal Ingest System
//!
//! Adapters for converting any slot engine events into canonical STAGES.
//!
//! ## Three Ingest Layers
//!
//! 1. **Direct Event** - Engine has event log with names
//! 2. **Snapshot Diff** - Engine has only before/after state
//! 3. **Rule-Based** - Generic events, heuristic reconstruction

pub mod adapter;
pub mod config;
pub mod registry;
pub mod wizard;

// Ingest layers
pub mod layer_event;
pub mod layer_rules;
pub mod layer_snapshot;

pub use adapter::*;
pub use config::*;
pub use registry::*;

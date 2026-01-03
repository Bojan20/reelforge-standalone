//! rf-host: Plugin Hosting for ReelForge
//!
//! Provides VST3/CLAP/AU plugin scanning and hosting:
//! - Plugin discovery and scanning
//! - Plugin metadata caching
//! - Plugin instantiation and management
//! - Parameter mapping
//! - Audio/MIDI processing
//!
//! NOTE: This module provides the infrastructure for plugin hosting.
//! Actual plugin loading requires platform-specific bindings (vst3-sys, clap-sys).

mod scanner;
mod cache;
mod error;
mod instance;

pub use scanner::*;
pub use cache::*;
pub use error::*;
pub use instance::*;

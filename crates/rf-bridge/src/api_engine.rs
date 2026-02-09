//! Engine Lifecycle API functions
//!
//! Extracted from api.rs as part of modular FFI decomposition.
//! Handles engine initialization, shutdown, and status.

use crate::{ENGINE, EngineBridge};
use rf_core::SampleRate;
use rf_engine::EngineConfig;

// ═══════════════════════════════════════════════════════════════════════════
// ENGINE LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════

/// Initialize the audio engine with default config
#[flutter_rust_bridge::frb(sync)]
pub fn engine_init() -> bool {
    let mut engine = ENGINE.write();
    if engine.is_some() {
        return false; // Already initialized
    }
    *engine = Some(EngineBridge::new(EngineConfig::default()));
    true
}

/// Initialize with custom config
#[flutter_rust_bridge::frb(sync)]
pub fn engine_init_with_config(sample_rate: u32, block_size: usize, num_buses: usize) -> bool {
    let mut engine = ENGINE.write();
    if engine.is_some() {
        return false;
    }

    let sr = match sample_rate {
        44100 => SampleRate::Hz44100,
        48000 => SampleRate::Hz48000,
        88200 => SampleRate::Hz88200,
        96000 => SampleRate::Hz96000,
        176400 => SampleRate::Hz176400,
        192000 => SampleRate::Hz192000,
        _ => SampleRate::Hz48000,
    };

    let config = EngineConfig {
        sample_rate: sr,
        block_size,
        num_buses,
        ..Default::default()
    };

    *engine = Some(EngineBridge::new(config));
    true
}

/// Shutdown the engine
#[flutter_rust_bridge::frb(sync)]
pub fn engine_shutdown() {
    let mut engine = ENGINE.write();
    *engine = None;
}

/// Check if engine is running
#[flutter_rust_bridge::frb(sync)]
pub fn engine_is_running() -> bool {
    ENGINE.read().is_some()
}

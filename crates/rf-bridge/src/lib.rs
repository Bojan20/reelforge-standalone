//! rf-bridge: Flutter-Rust Bridge for ReelForge DAW
//!
//! Provides FFI bindings for Flutter frontend to communicate with:
//! - Audio engine (transport, metering, routing)
//! - DSP processors (EQ, dynamics, effects)
//! - State management (undo/redo, presets, projects)
//! - Audio I/O (device selection, buffer config)
//!
//! Uses flutter_rust_bridge for automatic Dart code generation.

mod api;
mod engine_bridge;
mod metering;
mod transport;
mod project;
mod audio_io;
mod viz;

pub use api::*;
pub use viz::*;

use std::sync::Arc;
use parking_lot::RwLock;
use once_cell::sync::Lazy;

use rf_engine::{DualPathEngine, EngineConfig, ProcessingMode};
use rf_state::{Project, UndoManager};

/// Global engine instance (singleton for Flutter access)
static ENGINE: Lazy<Arc<RwLock<Option<EngineBridge>>>> = Lazy::new(|| {
    Arc::new(RwLock::new(None))
});

/// Bridge wrapper for the audio engine
pub struct EngineBridge {
    engine: DualPathEngine,
    project: Project,
    undo_manager: UndoManager,
    config: EngineConfig,
    metering: MeteringState,
    transport: TransportState,
}

/// Real-time metering data (lock-free updates)
#[derive(Debug, Clone, Default)]
pub struct MeteringState {
    pub master_peak_l: f32,
    pub master_peak_r: f32,
    pub master_rms_l: f32,
    pub master_rms_r: f32,
    pub master_lufs_m: f32,
    pub master_lufs_s: f32,
    pub master_lufs_i: f32,
    pub master_true_peak: f32,
    pub track_peaks: Vec<(f32, f32)>,
    pub cpu_usage: f32,
    pub buffer_underruns: u32,
}

/// Transport state
#[derive(Debug, Clone, Default)]
pub struct TransportState {
    pub is_playing: bool,
    pub is_recording: bool,
    pub position_samples: u64,
    pub position_seconds: f64,
    pub tempo: f64,
    pub time_sig_num: u32,
    pub time_sig_denom: u32,
    pub loop_enabled: bool,
    pub loop_start: f64,
    pub loop_end: f64,
}

impl EngineBridge {
    pub fn new(config: EngineConfig) -> Self {
        Self {
            engine: DualPathEngine::new(
                config.processing_mode,
                config.block_size,
                config.sample_rate.as_f64(),
                config.lookahead_blocks,
            ),
            project: Project::new("Untitled"),
            undo_manager: UndoManager::new(500), // 500 undo steps
            config,
            metering: MeteringState::default(),
            transport: TransportState {
                tempo: 120.0,
                time_sig_num: 4,
                time_sig_denom: 4,
                ..Default::default()
            },
        }
    }
}

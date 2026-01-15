//! rf-bridge: Flutter-Rust Bridge for FluxForge Studio DAW
//!
//! Provides FFI bindings for Flutter frontend to communicate with:
//! - Audio engine (transport, metering, routing)
//! - DSP processors (EQ, dynamics, effects)
//! - State management (undo/redo, presets, projects)
//! - Audio I/O (device selection, buffer config)
//!
//! Uses flutter_rust_bridge for automatic Dart code generation.
//!
//! ## Lock-Free Architecture
//! Uses rtrb ring buffers for real-time safe UI↔Audio communication:
//! - `dsp_commands` - All DSP parameter command types
//! - `command_queue` - Lock-free producer/consumer queues

// Many structs/methods are only used via FFI from Flutter
#![allow(dead_code)]
// Flutter Rust Bridge uses custom cfg attributes
#![allow(unexpected_cfgs)]
// Both api::* and rf_engine::ffi::* export some functions with same names
// This is intentional - api provides Flutter Rust Bridge bindings, ffi provides C FFI
#![allow(ambiguous_glob_reexports)]
// Audio processing functions need many arguments for zero-copy
#![allow(clippy::too_many_arguments)]
// Field reassign pattern is common in FFI bridge init
#![allow(clippy::field_reassign_with_default)]
// Flutter Rust Bridge macro generates div_ceil manually
#![allow(clippy::manual_div_ceil)]

pub mod advanced_metering;
mod api;
mod audio_io;
pub mod autosave_ffi;
pub mod command_queue;
pub mod dsp_commands;
mod engine_bridge;
mod metering;
pub mod midi_bridge;
mod midi_ffi;
mod playback;
mod project;
pub mod timestretch;
mod transport;
mod viz;

pub use advanced_metering::*;
pub use api::*;
pub use command_queue::*;
pub use dsp_commands::*;
pub use playback::{PlaybackClip, PlaybackEngine, PlaybackMeters, PlaybackState};
pub use timestretch::*;
pub use viz::*;

// Re-export recording types from rf-file
pub use rf_file::{RecordingConfig, RecordingState, RecordingStats};

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::sync::Arc;

use rf_engine::automation::AutomationEngine;
use rf_engine::groups::GroupManager;
use rf_engine::playback::PlaybackEngine as EnginePlayback;
use rf_engine::track_manager::TrackManager;
use rf_engine::{DualPathEngine, EngineConfig};
use rf_state::{Project, UndoManager};

/// Global engine instance (singleton for Flutter access)
static ENGINE: Lazy<Arc<RwLock<Option<EngineBridge>>>> = Lazy::new(|| Arc::new(RwLock::new(None)));

/// Global playback engine (real-time audio output)
pub static PLAYBACK: Lazy<Arc<PlaybackEngine>> = Lazy::new(|| Arc::new(PlaybackEngine::new()));

/// Bridge wrapper for the audio engine
pub struct EngineBridge {
    engine: DualPathEngine,
    project: Project,
    undo_manager: UndoManager,
    config: EngineConfig,
    metering: MeteringState,
    transport: TransportState,
    /// Track manager for timeline clips
    track_manager: Arc<TrackManager>,
    /// Playback engine for real-time audio processing
    playback_engine: Arc<EnginePlayback>,
    /// Automation engine for parameter automation
    automation_engine: Arc<AutomationEngine>,
    /// VCA/Group manager for track grouping
    group_manager: Arc<RwLock<GroupManager>>,
    /// Dirty state - project has unsaved changes
    is_dirty: std::sync::atomic::AtomicBool,
    /// Last saved undo position
    last_saved_undo_pos: std::sync::atomic::AtomicUsize,
    /// Current project file path
    project_file_path: RwLock<Option<String>>,
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
    /// Stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
    pub correlation: f32,
    /// Stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
    pub stereo_balance: f32,
    /// Dynamic range (peak - RMS in dB)
    pub dynamic_range: f32,
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
        // Create track manager for timeline clips
        let track_manager = Arc::new(TrackManager::new());

        // Create automation engine
        let automation_engine = Arc::new(AutomationEngine::new(config.sample_rate.as_f64()));

        // Create VCA/group manager
        let group_manager = Arc::new(RwLock::new(GroupManager::new()));

        // Create playback engine connected to track manager
        let sample_rate = config.sample_rate.as_u32();
        let mut playback_engine = EnginePlayback::new(Arc::clone(&track_manager), sample_rate);

        // Connect automation to playback engine
        playback_engine.set_automation(Arc::clone(&automation_engine));
        // Connect group/VCA manager to playback engine for audio-thread VCA gain
        playback_engine.set_group_manager(Arc::clone(&group_manager));

        let playback_engine = Arc::new(playback_engine);

        // Connect playback engine to audio output
        PLAYBACK.connect_engine(Arc::clone(&playback_engine));
        log::info!("EngineBridge: Connected rf-engine PlaybackEngine to audio output");
        log::info!("EngineBridge: Automation and VCA systems connected");

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
            track_manager,
            playback_engine,
            automation_engine,
            group_manager,
            is_dirty: std::sync::atomic::AtomicBool::new(false),
            last_saved_undo_pos: std::sync::atomic::AtomicUsize::new(0),
            project_file_path: RwLock::new(None),
        }
    }

    /// Mark project as dirty (has unsaved changes)
    pub fn mark_dirty(&self) {
        self.is_dirty
            .store(true, std::sync::atomic::Ordering::Relaxed);
    }

    /// Mark project as clean (just saved)
    pub fn mark_clean(&self) {
        self.is_dirty
            .store(false, std::sync::atomic::Ordering::Relaxed);
        self.last_saved_undo_pos.store(
            self.undo_manager.undo_count(),
            std::sync::atomic::Ordering::Relaxed,
        );
    }

    /// Check if project has unsaved changes
    pub fn is_dirty(&self) -> bool {
        // Dirty if explicitly marked OR if undo count differs from saved position
        self.is_dirty.load(std::sync::atomic::Ordering::Relaxed)
            || self.undo_manager.undo_count()
                != self
                    .last_saved_undo_pos
                    .load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Set project file path
    pub fn set_file_path(&self, path: Option<String>) {
        *self.project_file_path.write() = path;
    }

    /// Get project file path
    pub fn file_path(&self) -> Option<String> {
        self.project_file_path.read().clone()
    }

    /// Get track manager for adding clips/tracks
    pub fn track_manager(&self) -> &Arc<TrackManager> {
        &self.track_manager
    }

    /// Get playback engine for transport control
    pub fn playback_engine(&self) -> &Arc<EnginePlayback> {
        &self.playback_engine
    }

    /// Get automation engine for parameter automation
    pub fn automation_engine(&self) -> &Arc<AutomationEngine> {
        &self.automation_engine
    }

    /// Get VCA/group manager for track grouping
    pub fn group_manager(&self) -> &Arc<RwLock<GroupManager>> {
        &self.group_manager
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// C FFI RE-EXPORTS FROM RF-ENGINE
// These functions are defined in rf-engine/src/ffi.rs and need to be accessible
// through librf_bridge.dylib for Flutter dart:ffi direct calls.
// ═══════════════════════════════════════════════════════════════════════════════

// Re-export all C FFI symbols from rf-engine
pub use rf_engine::ffi::*;

// Re-export autosave and recent projects FFI
pub use autosave_ffi::*;

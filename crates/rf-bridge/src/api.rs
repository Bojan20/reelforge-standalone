//! Flutter API functions
//!
//! These functions are exposed to Flutter via flutter_rust_bridge.
//! All functions are async-safe and use message passing for thread safety.

use crate::{ENGINE, EngineBridge, MeteringState, TransportState};
use rf_engine::EngineConfig;
use rf_core::SampleRate;
use std::path::Path;

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
pub fn engine_init_with_config(
    sample_rate: u32,
    block_size: usize,
    num_buses: usize,
) -> bool {
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

// ═══════════════════════════════════════════════════════════════════════════
// TRANSPORT
// ═══════════════════════════════════════════════════════════════════════════

/// Start playback
#[flutter_rust_bridge::frb(sync)]
pub fn transport_play() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_playing = true;
        true
    } else {
        false
    }
}

/// Stop playback
#[flutter_rust_bridge::frb(sync)]
pub fn transport_stop() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_playing = false;
        e.transport.position_samples = 0;
        e.transport.position_seconds = 0.0;
        true
    } else {
        false
    }
}

/// Pause playback (keeps position)
#[flutter_rust_bridge::frb(sync)]
pub fn transport_pause() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_playing = false;
        true
    } else {
        false
    }
}

/// Toggle record
#[flutter_rust_bridge::frb(sync)]
pub fn transport_record() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.is_recording = !e.transport.is_recording;
        true
    } else {
        false
    }
}

/// Set playback position (in seconds)
#[flutter_rust_bridge::frb(sync)]
pub fn transport_set_position(seconds: f64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.position_seconds = seconds;
        let sr = e.config.sample_rate.as_f64();
        e.transport.position_samples = (seconds * sr) as u64;
        true
    } else {
        false
    }
}

/// Set tempo
#[flutter_rust_bridge::frb(sync)]
pub fn transport_set_tempo(bpm: f64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.tempo = bpm.clamp(20.0, 999.0);
        true
    } else {
        false
    }
}

/// Toggle loop
#[flutter_rust_bridge::frb(sync)]
pub fn transport_toggle_loop() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.loop_enabled = !e.transport.loop_enabled;
        true
    } else {
        false
    }
}

/// Set loop range
#[flutter_rust_bridge::frb(sync)]
pub fn transport_set_loop_range(start: f64, end: f64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.transport.loop_start = start;
        e.transport.loop_end = end;
        true
    } else {
        false
    }
}

/// Get current transport state
#[flutter_rust_bridge::frb(sync)]
pub fn transport_get_state() -> Option<TransportState> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.transport.clone())
}

// ═══════════════════════════════════════════════════════════════════════════
// METERING
// ═══════════════════════════════════════════════════════════════════════════

/// Get current metering state (call at ~60fps for UI updates)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_state() -> Option<MeteringState> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.metering.clone())
}

/// Get master peak levels (L, R)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_peak() -> Option<(f32, f32)> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| (e.metering.master_peak_l, e.metering.master_peak_r))
}

/// Get master LUFS (momentary, short-term, integrated)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_lufs() -> Option<(f32, f32, f32)> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| (
        e.metering.master_lufs_m,
        e.metering.master_lufs_s,
        e.metering.master_lufs_i,
    ))
}

/// Get CPU usage percentage
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_cpu_usage() -> f32 {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.metering.cpu_usage).unwrap_or(0.0)
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER
// ═══════════════════════════════════════════════════════════════════════════

/// Set track volume (in dB)
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_volume(track_id: u32, volume_db: f64) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        // TODO: Forward to engine
        log::debug!("Set track {} volume to {} dB", track_id, volume_db);
        true
    } else {
        false
    }
}

/// Set track pan (-1.0 to 1.0)
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_pan(track_id: u32, pan: f64) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!("Set track {} pan to {}", track_id, pan);
        true
    } else {
        false
    }
}

/// Set track mute
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_mute(track_id: u32, muted: bool) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!("Set track {} mute to {}", track_id, muted);
        true
    } else {
        false
    }
}

/// Set track solo
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_solo(track_id: u32, solo: bool) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!("Set track {} solo to {}", track_id, solo);
        true
    } else {
        false
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROJECT
// ═══════════════════════════════════════════════════════════════════════════

/// Create new project
#[flutter_rust_bridge::frb(sync)]
pub fn project_new(name: String) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project = rf_state::Project::new(&name);
        e.undo_manager.clear();
        true
    } else {
        false
    }
}

/// Save project to file (sync version)
#[flutter_rust_bridge::frb(sync)]
pub fn project_save_sync(path: String) -> Result<(), String> {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let p = Path::new(&path);
        let format = rf_state::ProjectFormat::from_extension(p);
        e.project.save(p, format)
            .map_err(|err| err.to_string())
    } else {
        Err("Engine not initialized".to_string())
    }
}

/// Load project from file (sync version)
#[flutter_rust_bridge::frb(sync)]
pub fn project_load_sync(path: String) -> Result<(), String> {
    let project = rf_state::Project::load(Path::new(&path))
        .map_err(|err| err.to_string())?;

    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project = project;
        e.undo_manager.clear();

        // Sync transport from project
        e.transport.tempo = e.project.tempo;
        e.transport.time_sig_num = e.project.time_sig_num as u32;
        e.transport.time_sig_denom = e.project.time_sig_denom as u32;
        e.transport.loop_enabled = e.project.loop_enabled;

        Ok(())
    } else {
        Err("Engine not initialized".to_string())
    }
}

/// Get project name
#[flutter_rust_bridge::frb(sync)]
pub fn project_get_name() -> Option<String> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.project.meta.name.clone())
}

/// Set project name
#[flutter_rust_bridge::frb(sync)]
pub fn project_set_name(name: String) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project.meta.name = name;
        e.project.touch();
        true
    } else {
        false
    }
}

/// Get project tempo
#[flutter_rust_bridge::frb(sync)]
pub fn project_get_tempo() -> Option<f64> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.project.tempo)
}

/// Set project tempo
#[flutter_rust_bridge::frb(sync)]
pub fn project_set_tempo(tempo: f64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project.tempo = tempo.clamp(20.0, 999.0);
        e.transport.tempo = e.project.tempo;
        e.project.touch();
        true
    } else {
        false
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNDO/REDO
// ═══════════════════════════════════════════════════════════════════════════

/// Undo last action
#[flutter_rust_bridge::frb(sync)]
pub fn history_undo() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.undo_manager.undo()
    } else {
        false
    }
}

/// Redo last undone action
#[flutter_rust_bridge::frb(sync)]
pub fn history_redo() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.undo_manager.redo()
    } else {
        false
    }
}

/// Check if undo is available
#[flutter_rust_bridge::frb(sync)]
pub fn history_can_undo() -> bool {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.undo_manager.can_undo()).unwrap_or(false)
}

/// Check if redo is available
#[flutter_rust_bridge::frb(sync)]
pub fn history_can_redo() -> bool {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.undo_manager.can_redo()).unwrap_or(false)
}

/// Get undo step count
#[flutter_rust_bridge::frb(sync)]
pub fn history_undo_count() -> usize {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.undo_manager.undo_count()).unwrap_or(0)
}

/// Get redo step count
#[flutter_rust_bridge::frb(sync)]
pub fn history_redo_count() -> usize {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.undo_manager.redo_count()).unwrap_or(0)
}

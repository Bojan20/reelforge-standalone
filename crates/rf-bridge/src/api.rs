//! Flutter API functions
//!
//! These functions are exposed to Flutter via flutter_rust_bridge.
//! All functions are async-safe and use message passing for thread safety.

use crate::{ENGINE, EngineBridge, MeteringState, PLAYBACK, TransportState};
use rf_core::SampleRate;
use rf_engine::EngineConfig;
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
    engine
        .as_ref()
        .map(|e| (e.metering.master_peak_l, e.metering.master_peak_r))
}

/// Get master LUFS (momentary, short-term, integrated)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_lufs() -> Option<(f32, f32, f32)> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| {
        (
            e.metering.master_lufs_m,
            e.metering.master_lufs_s,
            e.metering.master_lufs_i,
        )
    })
}

/// Get CPU usage percentage
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_cpu_usage() -> f32 {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.metering.cpu_usage).unwrap_or(0.0)
}

/// Get master stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_correlation() -> f32 {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.metering.correlation)
        .unwrap_or(1.0)
}

/// Get master stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_balance() -> f32 {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.metering.stereo_balance)
        .unwrap_or(0.0)
}

/// Get master dynamic range (peak - RMS in dB)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_master_dynamic_range() -> f32 {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.metering.dynamic_range)
        .unwrap_or(0.0)
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER
// ═══════════════════════════════════════════════════════════════════════════

/// Set track volume (linear, 0.0 to 2.0, 1.0 = unity)
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_volume(track_id: u32, volume: f64) -> bool {
    use rf_engine::track_manager::TrackId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        // Update track in TrackManager
        e.track_manager()
            .update_track(TrackId(track_id as u64), |track| {
                track.volume = volume.clamp(0.0, 2.0);
            });
        log::debug!("Set track {} volume to {}", track_id, volume);
        true
    } else {
        false
    }
}

/// Set track pan (-1.0 to 1.0)
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_pan(track_id: u32, pan: f64) -> bool {
    use rf_engine::track_manager::TrackId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_track(TrackId(track_id as u64), |track| {
                track.pan = pan.clamp(-1.0, 1.0);
            });
        log::debug!("Set track {} pan to {}", track_id, pan);
        true
    } else {
        false
    }
}

/// Set track mute
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_mute(track_id: u32, muted: bool) -> bool {
    use rf_engine::track_manager::TrackId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_track(TrackId(track_id as u64), |track| {
                track.muted = muted;
            });
        log::debug!("Set track {} mute to {}", track_id, muted);
        true
    } else {
        false
    }
}

/// Set track solo
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_solo(track_id: u32, solo: bool) -> bool {
    use rf_engine::track_manager::TrackId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_track(TrackId(track_id as u64), |track| {
                track.soloed = solo;
            });
        log::debug!("Set track {} solo to {}", track_id, solo);
        true
    } else {
        false
    }
}

/// Set track output bus (0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=Aux)
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_bus(track_id: u32, bus_id: u8) -> bool {
    use rf_engine::track_manager::{OutputBus, TrackId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_track(TrackId(track_id as u64), |track| {
                track.output_bus = OutputBus::from(bus_id as u32);
            });
        log::debug!("Set track {} output bus to {}", track_id, bus_id);
        true
    } else {
        false
    }
}

/// Set track record arm
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_track_armed(track_id: u32, armed: bool) -> bool {
    use rf_engine::track_manager::TrackId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_track(TrackId(track_id as u64), |track| {
                track.armed = armed;
            });
        log::debug!("Set track {} armed to {}", track_id, armed);
        true
    } else {
        false
    }
}

/// Get track state (volume, pan, mute, solo, armed, bus)
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_get_track_state(track_id: u32) -> Option<TrackMixerState> {
    use rf_engine::track_manager::TrackId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .get_track(TrackId(track_id as u64))
            .map(|track| TrackMixerState {
                volume: track.volume,
                pan: track.pan,
                muted: track.muted,
                soloed: track.soloed,
                armed: track.armed,
                bus_id: track.output_bus as u8,
            })
    } else {
        None
    }
}

/// Track mixer state for UI sync
#[derive(Debug, Clone)]
pub struct TrackMixerState {
    pub volume: f64,
    pub pan: f64,
    pub muted: bool,
    pub soloed: bool,
    pub armed: bool,
    pub bus_id: u8,
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
        e.set_file_path(None);
        e.mark_clean();
        true
    } else {
        false
    }
}

/// Save project to file (sync version)
#[flutter_rust_bridge::frb(sync)]
pub fn project_save_sync(path: String) -> Result<(), String> {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        // Sync tracks from TrackManager to Project before saving
        sync_tracks_to_project(e);

        let p = Path::new(&path);
        let format = rf_state::ProjectFormat::from_extension(p);
        let result = e.project.save(p, format).map_err(|err| err.to_string());

        if result.is_ok() {
            e.set_file_path(Some(path));
            e.mark_clean();
        }
        result
    } else {
        Err("Engine not initialized".to_string())
    }
}

/// Sync tracks from TrackManager to Project state
fn sync_tracks_to_project(e: &mut EngineBridge) {
    use rf_engine::track_manager::OutputBus;
    use rf_state::{
        AssetRef, AutomationLaneState, AutomationPointState, RegionState, TrackState, TrackType,
    };

    let track_manager = e.track_manager();
    let tracks = track_manager.get_all_tracks();
    let all_clips = track_manager.get_all_clips();

    e.project.tracks = tracks
        .iter()
        .map(|track| {
            // Convert clips for this track
            let regions: Vec<RegionState> = all_clips
                .iter()
                .filter(|c| c.track_id == track.id)
                .map(|clip| {
                    // Convert seconds to samples (48kHz default)
                    let sample_rate = 48000u64;
                    RegionState {
                        id: clip.id.0.to_string(),
                        name: clip.name.clone(),
                        asset_ref: AssetRef::External(std::path::PathBuf::from(&clip.source_file)),
                        position: (clip.start_time * sample_rate as f64) as u64,
                        length: (clip.duration * sample_rate as f64) as u64,
                        source_offset: (clip.source_offset * sample_rate as f64) as u64,
                        gain_db: linear_to_db(clip.gain),
                        fade_in: (clip.fade_in * sample_rate as f64) as u64,
                        fade_out: (clip.fade_out * sample_rate as f64) as u64,
                        locked: false,
                    }
                })
                .collect();

            // Get automation lanes for this track
            let automation_lanes: Vec<AutomationLaneState> = {
                let automation = e.automation_engine.as_ref();
                let lane_ids = automation.lane_ids();

                lane_ids
                    .iter()
                    .filter_map(|param_id| {
                        // Only include lanes that belong to this track
                        if param_id.target_id == track.id.0 {
                            automation
                                .export_lane(param_id)
                                .map(|lane| AutomationLaneState {
                                    id: format!(
                                        "{}_{}",
                                        lane.param_id.target_id, lane.param_id.param_name
                                    ),
                                    parameter_id: lane.param_id.target_id as u32,
                                    parameter_name: lane.name.clone(),
                                    points: lane
                                        .points
                                        .iter()
                                        .map(|pt| AutomationPointState {
                                            position: pt.time_samples,
                                            value: pt.value,
                                            curve_type: match pt.curve {
                                                rf_engine::automation::CurveType::Linear => 0,
                                                rf_engine::automation::CurveType::Step => 2,
                                                rf_engine::automation::CurveType::Exponential => 3,
                                                _ => 0,
                                            },
                                            tension: 0.0,
                                        })
                                        .collect(),
                                    visible: lane.visible,
                                })
                        } else {
                            None
                        }
                    })
                    .collect()
            };

            // Convert output bus to string
            let output_bus_str = match track.output_bus {
                OutputBus::Master => "Master",
                OutputBus::Music => "Music",
                OutputBus::Sfx => "SFX",
                OutputBus::Voice => "Voice",
                OutputBus::Ambience => "Ambience",
                OutputBus::Aux => "Aux",
            };

            TrackState {
                id: track.id.0.to_string(),
                name: track.name.clone(),
                track_type: TrackType::Audio,
                output_bus: output_bus_str.to_string(),
                volume_db: linear_to_db(track.volume),
                pan: track.pan,
                mute: track.muted,
                solo: track.soloed,
                armed: track.armed,
                color: Some(track.color),
                regions,
                automation: automation_lanes,
            }
        })
        .collect();

    // Sync transport state
    e.project.tempo = e.transport.tempo;
    e.project.time_sig_num = e.transport.time_sig_num as u8;
    e.project.time_sig_denom = e.transport.time_sig_denom as u8;
    e.project.playhead = e.transport.position_samples;
    e.project.loop_enabled = e.transport.loop_enabled;
}

/// Convert dB to linear
fn db_to_linear(db: f64) -> f64 {
    10.0_f64.powf(db / 20.0)
}

/// Convert linear to dB
fn linear_to_db(linear: f64) -> f64 {
    if linear <= 0.0 {
        -120.0
    } else {
        20.0 * linear.log10()
    }
}

/// Load project from file (sync version)
#[flutter_rust_bridge::frb(sync)]
pub fn project_load_sync(path: String) -> Result<(), String> {
    let project = rf_state::Project::load(Path::new(&path)).map_err(|err| err.to_string())?;

    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project = project;
        e.undo_manager.clear();

        // Sync transport from project
        e.transport.tempo = e.project.tempo;
        e.transport.time_sig_num = e.project.time_sig_num as u32;
        e.transport.time_sig_denom = e.project.time_sig_denom as u32;
        e.transport.loop_enabled = e.project.loop_enabled;

        // Restore tracks from project to TrackManager
        sync_tracks_from_project(e);

        // Mark project as clean and store file path
        e.set_file_path(Some(path));
        e.mark_clean();

        Ok(())
    } else {
        Err("Engine not initialized".to_string())
    }
}

/// Sync tracks from Project state to TrackManager
fn sync_tracks_from_project(e: &mut EngineBridge) {
    use rf_engine::track_manager::{Clip, OutputBus};
    use rf_state::AssetRef;

    let track_manager = e.track_manager();

    // Clear existing tracks
    track_manager.clear();

    let sample_rate = 48000.0_f64; // Default sample rate for conversion

    for track_state in &e.project.tracks {
        // Parse output bus
        let output_bus = match track_state.output_bus.as_str() {
            "Master" => OutputBus::Master,
            "Music" => OutputBus::Music,
            "SFX" | "Sfx" => OutputBus::Sfx,
            "Voice" | "VO" => OutputBus::Voice,
            "Ambience" | "Ambient" => OutputBus::Ambience,
            "Aux" => OutputBus::Aux,
            _ => OutputBus::Master,
        };

        // Create track
        let color = track_state.color.unwrap_or(0xFF4488CC);
        let track_id = track_manager.create_track(&track_state.name, color, output_bus);

        // Update track properties
        track_manager.update_track(track_id, |t| {
            t.volume = db_to_linear(track_state.volume_db);
            t.pan = track_state.pan;
            t.muted = track_state.mute;
            t.soloed = track_state.solo;
            t.armed = track_state.armed;
        });

        // Add clips/regions for this track
        for region in &track_state.regions {
            // Get audio path from asset ref
            let source_file = match &region.asset_ref {
                AssetRef::External(path) => path.to_string_lossy().to_string(),
                AssetRef::Embedded(id) => id.clone(),
                AssetRef::Missing(name) => {
                    log::warn!("Missing asset: {}", name);
                    continue;
                }
            };

            // Convert samples to seconds
            let start_time = region.position as f64 / sample_rate;
            let duration = region.length as f64 / sample_rate;
            let source_offset = region.source_offset as f64 / sample_rate;
            let fade_in = region.fade_in as f64 / sample_rate;
            let fade_out = region.fade_out as f64 / sample_rate;

            let clip = Clip {
                id: rf_engine::track_manager::ClipId(region.id.parse().unwrap_or(0)),
                track_id,
                name: region.name.clone(),
                color: track_state.color,
                start_time,
                duration,
                source_file,
                source_offset,
                source_duration: duration, // Assume source duration equals clip duration
                fade_in,
                fade_out,
                gain: db_to_linear(region.gain_db),
                muted: false,
                selected: false,
                reversed: false,
                fx_chain: rf_engine::track_manager::ClipFxChain::new(),
            };

            track_manager.add_clip(clip);
        }

        // Restore automation lanes
        for lane_state in &track_state.automation {
            use rf_engine::automation::{AutomationPoint, CurveType, ParamId};

            // Create ParamId from stored data
            let param_id = ParamId::track_volume(track_id.0); // Use track_volume as default

            // Get or create lane
            let auto_engine = e.automation_engine.as_ref();
            let lane_param_id =
                auto_engine.get_or_create_lane(param_id, &lane_state.parameter_name);

            for pt in &lane_state.points {
                let curve = match pt.curve_type {
                    0 => CurveType::Linear,
                    2 => CurveType::Step,
                    3 => CurveType::Exponential,
                    _ => CurveType::Linear,
                };

                auto_engine.add_point(
                    &lane_param_id,
                    AutomationPoint::new(pt.position, pt.value).with_curve(curve),
                );
            }
        }
    }

    // Set playhead position
    e.transport.position_samples = e.project.playhead;

    log::info!(
        "Loaded {} tracks with {} clips from project",
        e.project.tracks.len(),
        e.project
            .tracks
            .iter()
            .map(|t| t.regions.len())
            .sum::<usize>()
    );
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

/// Project info for Flutter
#[derive(Debug, Clone)]
pub struct ProjectInfo {
    pub name: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub created_at: u64,
    pub modified_at: u64,
    pub duration_sec: f64,
    pub sample_rate: u32,
    pub tempo: f64,
    pub time_sig_num: u8,
    pub time_sig_denom: u8,
    pub track_count: usize,
    pub bus_count: usize,
    pub is_modified: bool,
    pub file_path: Option<String>,
}

/// Get full project info
#[flutter_rust_bridge::frb(sync)]
pub fn project_get_info() -> Option<ProjectInfo> {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| {
        ProjectInfo {
            name: e.project.meta.name.clone(),
            author: e.project.meta.author.clone(),
            description: e.project.meta.description.clone(),
            created_at: e.project.meta.created_at,
            modified_at: e.project.meta.modified_at,
            duration_sec: e.project.meta.duration_secs(),
            sample_rate: e.project.meta.sample_rate,
            tempo: e.project.tempo,
            time_sig_num: e.project.time_sig_num,
            time_sig_denom: e.project.time_sig_denom,
            track_count: e.project.tracks.len(),
            bus_count: e.project.buses.len(),
            is_modified: false, // TODO: Track dirty state
            file_path: None,    // TODO: Track file path
        }
    })
}

/// Set project author
#[flutter_rust_bridge::frb(sync)]
pub fn project_set_author(author: String) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project.meta.author = if author.is_empty() {
            None
        } else {
            Some(author)
        };
        e.project.touch();
        true
    } else {
        false
    }
}

/// Set project description
#[flutter_rust_bridge::frb(sync)]
pub fn project_set_description(description: String) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project.meta.description = if description.is_empty() {
            None
        } else {
            Some(description)
        };
        e.project.touch();
        true
    } else {
        false
    }
}

/// Set time signature
#[flutter_rust_bridge::frb(sync)]
pub fn project_set_time_signature(numerator: u8, denominator: u8) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project.time_sig_num = numerator;
        e.project.time_sig_denom = denominator;
        e.transport.time_sig_num = numerator as u32;
        e.transport.time_sig_denom = denominator as u32;
        e.project.touch();
        true
    } else {
        false
    }
}

/// Set sample rate
#[flutter_rust_bridge::frb(sync)]
pub fn project_set_sample_rate(sample_rate: u32) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project.meta.sample_rate = sample_rate;
        e.project.touch();
        true
    } else {
        false
    }
}

/// Check if project has unsaved changes
#[flutter_rust_bridge::frb(sync)]
pub fn project_is_modified() -> bool {
    let engine = ENGINE.read();
    engine.as_ref().map(|e| e.is_dirty()).unwrap_or(false)
}

/// Mark project as dirty (has unsaved changes)
#[flutter_rust_bridge::frb(sync)]
pub fn project_mark_dirty() {
    let engine = ENGINE.read();
    if let Some(e) = engine.as_ref() {
        e.mark_dirty();
    }
}

/// Mark project as clean (just saved)
#[flutter_rust_bridge::frb(sync)]
pub fn project_mark_clean() {
    let engine = ENGINE.read();
    if let Some(e) = engine.as_ref() {
        e.mark_clean();
    }
}

/// Set project file path
#[flutter_rust_bridge::frb(sync)]
pub fn project_set_file_path(path: Option<String>) {
    let engine = ENGINE.read();
    if let Some(e) = engine.as_ref() {
        e.set_file_path(path);
    }
}

/// Get project file path
#[flutter_rust_bridge::frb(sync)]
pub fn project_get_file_path() -> Option<String> {
    let engine = ENGINE.read();
    engine.as_ref().and_then(|e| e.file_path())
}

/// Get recent projects list (from app preferences)
#[flutter_rust_bridge::frb(sync)]
pub fn project_get_recent() -> Vec<String> {
    rf_state::AppPreferences::load().recent_projects
}

/// Add a project to recent projects list
#[flutter_rust_bridge::frb(sync)]
pub fn project_add_recent(path: String) {
    let mut prefs = rf_state::AppPreferences::load();
    prefs.add_recent_project(&path);
    let _ = prefs.save();
}

/// Remove a project from recent projects list
#[flutter_rust_bridge::frb(sync)]
pub fn project_remove_recent(path: String) {
    let mut prefs = rf_state::AppPreferences::load();
    prefs.remove_recent_project(&path);
    let _ = prefs.save();
}

/// Clear recent projects list
#[flutter_rust_bridge::frb(sync)]
pub fn project_clear_recent() {
    let mut prefs = rf_state::AppPreferences::load();
    prefs.clear_recent_projects();
    let _ = prefs.save();
}

// ═══════════════════════════════════════════════════════════════════════════
// PREFERENCES
// ═══════════════════════════════════════════════════════════════════════════

/// Audio preferences DTO for Flutter
#[derive(Clone, Debug)]
pub struct AudioPreferencesDto {
    pub default_sample_rate: u32,
    pub default_buffer_size: u32,
    pub preferred_device: Option<String>,
    pub low_latency: bool,
    pub auto_connect: bool,
}

/// UI preferences DTO for Flutter
#[derive(Clone, Debug)]
pub struct UiPreferencesDto {
    pub theme: String,
    pub timeline_zoom: f64,
    pub track_height: u32,
    pub show_meters: bool,
    pub show_waveforms: bool,
    pub show_automation: bool,
    pub mixer_view: String,
    pub snap_enabled: bool,
    pub grid_beats: f64,
}

/// Editor preferences DTO for Flutter
#[derive(Clone, Debug)]
pub struct EditorPreferencesDto {
    pub autosave_interval: u32,
    pub backup_on_save: bool,
    pub max_undo_history: u32,
    pub confirm_delete: bool,
    pub auto_scroll: bool,
    pub follow_playhead: bool,
}

/// Recording preferences DTO for Flutter
#[derive(Clone, Debug)]
pub struct RecordingPreferencesDto {
    pub format: String,
    pub bit_depth: u32,
    pub pre_roll: f64,
    pub post_roll: f64,
    pub count_in: bool,
    pub count_in_bars: u32,
    pub metronome_record: bool,
    pub metronome_playback: bool,
}

/// Get audio preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_get_audio() -> AudioPreferencesDto {
    let prefs = rf_state::AppPreferences::load();
    AudioPreferencesDto {
        default_sample_rate: prefs.audio.default_sample_rate,
        default_buffer_size: prefs.audio.default_buffer_size,
        preferred_device: prefs.audio.preferred_device,
        low_latency: prefs.audio.low_latency,
        auto_connect: prefs.audio.auto_connect,
    }
}

/// Set audio preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_set_audio(prefs: AudioPreferencesDto) {
    let mut app_prefs = rf_state::AppPreferences::load();
    app_prefs.audio.default_sample_rate = prefs.default_sample_rate;
    app_prefs.audio.default_buffer_size = prefs.default_buffer_size;
    app_prefs.audio.preferred_device = prefs.preferred_device;
    app_prefs.audio.low_latency = prefs.low_latency;
    app_prefs.audio.auto_connect = prefs.auto_connect;
    let _ = app_prefs.save();
}

/// Get UI preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_get_ui() -> UiPreferencesDto {
    let prefs = rf_state::AppPreferences::load();
    UiPreferencesDto {
        theme: prefs.ui.theme,
        timeline_zoom: prefs.ui.timeline_zoom,
        track_height: prefs.ui.track_height,
        show_meters: prefs.ui.show_meters,
        show_waveforms: prefs.ui.show_waveforms,
        show_automation: prefs.ui.show_automation,
        mixer_view: prefs.ui.mixer_view,
        snap_enabled: prefs.ui.snap_enabled,
        grid_beats: prefs.ui.grid_beats,
    }
}

/// Set UI preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_set_ui(prefs: UiPreferencesDto) {
    let mut app_prefs = rf_state::AppPreferences::load();
    app_prefs.ui.theme = prefs.theme;
    app_prefs.ui.timeline_zoom = prefs.timeline_zoom;
    app_prefs.ui.track_height = prefs.track_height;
    app_prefs.ui.show_meters = prefs.show_meters;
    app_prefs.ui.show_waveforms = prefs.show_waveforms;
    app_prefs.ui.show_automation = prefs.show_automation;
    app_prefs.ui.mixer_view = prefs.mixer_view;
    app_prefs.ui.snap_enabled = prefs.snap_enabled;
    app_prefs.ui.grid_beats = prefs.grid_beats;
    let _ = app_prefs.save();
}

/// Get editor preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_get_editor() -> EditorPreferencesDto {
    let prefs = rf_state::AppPreferences::load();
    EditorPreferencesDto {
        autosave_interval: prefs.editor.autosave_interval,
        backup_on_save: prefs.editor.backup_on_save,
        max_undo_history: prefs.editor.max_undo_history as u32,
        confirm_delete: prefs.editor.confirm_delete,
        auto_scroll: prefs.editor.auto_scroll,
        follow_playhead: prefs.editor.follow_playhead,
    }
}

/// Set editor preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_set_editor(prefs: EditorPreferencesDto) {
    let mut app_prefs = rf_state::AppPreferences::load();
    app_prefs.editor.autosave_interval = prefs.autosave_interval;
    app_prefs.editor.backup_on_save = prefs.backup_on_save;
    app_prefs.editor.max_undo_history = prefs.max_undo_history as usize;
    app_prefs.editor.confirm_delete = prefs.confirm_delete;
    app_prefs.editor.auto_scroll = prefs.auto_scroll;
    app_prefs.editor.follow_playhead = prefs.follow_playhead;
    let _ = app_prefs.save();
}

/// Get recording preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_get_recording() -> RecordingPreferencesDto {
    let prefs = rf_state::AppPreferences::load();
    RecordingPreferencesDto {
        format: prefs.recording.format,
        bit_depth: prefs.recording.bit_depth,
        pre_roll: prefs.recording.pre_roll,
        post_roll: prefs.recording.post_roll,
        count_in: prefs.recording.count_in,
        count_in_bars: prefs.recording.count_in_bars,
        metronome_record: prefs.recording.metronome_record,
        metronome_playback: prefs.recording.metronome_playback,
    }
}

/// Set recording preferences
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_set_recording(prefs: RecordingPreferencesDto) {
    let mut app_prefs = rf_state::AppPreferences::load();
    app_prefs.recording.format = prefs.format;
    app_prefs.recording.bit_depth = prefs.bit_depth;
    app_prefs.recording.pre_roll = prefs.pre_roll;
    app_prefs.recording.post_roll = prefs.post_roll;
    app_prefs.recording.count_in = prefs.count_in;
    app_prefs.recording.count_in_bars = prefs.count_in_bars;
    app_prefs.recording.metronome_record = prefs.metronome_record;
    app_prefs.recording.metronome_playback = prefs.metronome_playback;
    let _ = app_prefs.save();
}

/// Reset all preferences to defaults
#[flutter_rust_bridge::frb(sync)]
pub fn preferences_reset() {
    let prefs = rf_state::AppPreferences::default();
    let _ = prefs.save();
}

/// Export project as JSON string (for debugging/backup)
#[flutter_rust_bridge::frb(sync)]
pub fn project_export_json() -> Option<String> {
    let engine = ENGINE.read();
    engine.as_ref().and_then(|e| e.project.to_json().ok())
}

/// Import project from JSON string
#[flutter_rust_bridge::frb(sync)]
pub fn project_import_json(json: String) -> Result<(), String> {
    let project = rf_state::Project::from_json(&json).map_err(|e| e.to_string())?;

    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.project = project;
        e.undo_manager.clear();
        e.transport.tempo = e.project.tempo;
        e.transport.time_sig_num = e.project.time_sig_num as u32;
        e.transport.time_sig_denom = e.project.time_sig_denom as u32;
        Ok(())
    } else {
        Err("Engine not initialized".to_string())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNDO/REDO (Flutter Rust Bridge - high-level API)
// ═══════════════════════════════════════════════════════════════════════════

/// Undo last action (FRB high-level)
#[flutter_rust_bridge::frb(sync)]
pub fn frb_history_undo() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.undo_manager.undo()
    } else {
        false
    }
}

/// Redo last undone action (FRB high-level)
#[flutter_rust_bridge::frb(sync)]
pub fn frb_history_redo() -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        e.undo_manager.redo()
    } else {
        false
    }
}

/// Check if undo is available (FRB high-level)
#[flutter_rust_bridge::frb(sync)]
pub fn frb_history_can_undo() -> bool {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.undo_manager.can_undo())
        .unwrap_or(false)
}

/// Check if redo is available (FRB high-level)
#[flutter_rust_bridge::frb(sync)]
pub fn frb_history_can_redo() -> bool {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.undo_manager.can_redo())
        .unwrap_or(false)
}

/// Get undo step count
#[flutter_rust_bridge::frb(sync)]
pub fn frb_history_undo_count() -> usize {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.undo_manager.undo_count())
        .unwrap_or(0)
}

/// Get redo step count
#[flutter_rust_bridge::frb(sync)]
pub fn frb_history_redo_count() -> usize {
    let engine = ENGINE.read();
    engine
        .as_ref()
        .map(|e| e.undo_manager.redo_count())
        .unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════
// C FFI WRAPPERS FOR UNDO/REDO (for dart:ffi direct calls)
// ═══════════════════════════════════════════════════════════════════════════

/// C FFI: Undo last action
#[unsafe(no_mangle)]
pub extern "C" fn history_undo() -> i32 {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        if e.undo_manager.undo() { 1 } else { 0 }
    } else {
        0
    }
}

/// C FFI: Redo last undone action
#[unsafe(no_mangle)]
pub extern "C" fn history_redo() -> i32 {
    let mut engine = ENGINE.write();
    if let Some(ref mut e) = *engine {
        if e.undo_manager.redo() { 1 } else { 0 }
    } else {
        0
    }
}

/// C FFI: Check if undo is available
#[unsafe(no_mangle)]
pub extern "C" fn history_can_undo() -> i32 {
    let engine = ENGINE.read();
    if engine
        .as_ref()
        .map(|e| e.undo_manager.can_undo())
        .unwrap_or(false)
    {
        1
    } else {
        0
    }
}

/// C FFI: Check if redo is available
#[unsafe(no_mangle)]
pub extern "C" fn history_can_redo() -> i32 {
    let engine = ENGINE.read();
    if engine
        .as_ref()
        .map(|e| e.undo_manager.can_redo())
        .unwrap_or(false)
    {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO PLAYBACK (Real-time audio output)
// ═══════════════════════════════════════════════════════════════════════════

/// Start audio playback engine
#[flutter_rust_bridge::frb(sync)]
pub fn playback_start() -> Result<(), String> {
    crate::PLAYBACK.start()
}

/// Stop audio playback engine
#[flutter_rust_bridge::frb(sync)]
pub fn playback_stop() -> Result<(), String> {
    crate::PLAYBACK.stop()
}

/// Start playback (transport play)
#[flutter_rust_bridge::frb(sync)]
pub fn playback_play() {
    crate::PLAYBACK.play();
}

/// Pause playback
#[flutter_rust_bridge::frb(sync)]
pub fn playback_pause() {
    crate::PLAYBACK.pause();
}

/// Stop playback and reset position
#[flutter_rust_bridge::frb(sync)]
pub fn playback_transport_stop() {
    crate::PLAYBACK.transport_stop();
}

/// Seek to position (in seconds)
#[flutter_rust_bridge::frb(sync)]
pub fn playback_seek(seconds: f64) {
    crate::PLAYBACK.seek(seconds);
}

// ═══════════════════════════════════════════════════════════════════════════
// SCRUBBING (audio preview on drag)
// ═══════════════════════════════════════════════════════════════════════════

/// Start scrubbing at given position (enables audio preview while dragging)
#[flutter_rust_bridge::frb(sync)]
pub fn playback_start_scrub(seconds: f64) {
    crate::PLAYBACK.start_scrub(seconds);
}

/// Update scrub position with velocity
/// velocity: -4.0 to 4.0, positive = forward, negative = backward
#[flutter_rust_bridge::frb(sync)]
pub fn playback_update_scrub(seconds: f64, velocity: f64) {
    crate::PLAYBACK.update_scrub(seconds, velocity);
}

/// Stop scrubbing
#[flutter_rust_bridge::frb(sync)]
pub fn playback_stop_scrub() {
    crate::PLAYBACK.stop_scrub();
}

/// Check if currently scrubbing
#[flutter_rust_bridge::frb(sync)]
pub fn playback_is_scrubbing() -> bool {
    crate::PLAYBACK.is_scrubbing()
}

/// Set scrub window size in milliseconds (10-200ms, default 50ms)
/// Smaller = more responsive but choppier, Larger = smoother but less precise
#[flutter_rust_bridge::frb(sync)]
pub fn playback_set_scrub_window_ms(ms: u32) {
    crate::PLAYBACK.set_scrub_window_ms(ms as u64);
}

/// Set loop range
#[flutter_rust_bridge::frb(sync)]
pub fn playback_set_loop(enabled: bool, start_sec: f64, end_sec: f64) {
    crate::PLAYBACK.set_loop(enabled, start_sec, end_sec);
}

/// Check if playback engine is running
#[flutter_rust_bridge::frb(sync)]
pub fn playback_is_running() -> bool {
    crate::PLAYBACK.is_running()
}

/// Check if playing
#[flutter_rust_bridge::frb(sync)]
pub fn playback_is_playing() -> bool {
    crate::PLAYBACK.is_playing()
}

/// Get current position in seconds
#[flutter_rust_bridge::frb(sync)]
pub fn playback_position() -> f64 {
    crate::PLAYBACK.position_seconds()
}

/// Get peak meters (L, R)
#[flutter_rust_bridge::frb(sync)]
pub fn playback_get_peaks() -> (f32, f32) {
    (
        crate::PLAYBACK.meters.get_peak_l(),
        crate::PLAYBACK.meters.get_peak_r(),
    )
}

/// Get RMS meters (L, R)
#[flutter_rust_bridge::frb(sync)]
pub fn playback_get_rms() -> (f32, f32) {
    (
        crate::PLAYBACK.meters.get_rms_l(),
        crate::PLAYBACK.meters.get_rms_r(),
    )
}

/// Load test tone clip
#[flutter_rust_bridge::frb(sync)]
pub fn playback_load_test_tone() -> Result<(), String> {
    crate::PLAYBACK.load_audio_file("test_tone", "", 0)
}

/// Clear all clips
#[flutter_rust_bridge::frb(sync)]
pub fn playback_clear_clips() {
    crate::PLAYBACK.clear_clips();
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO PREVIEW (for Slot Lab and general preview playback)
// Uses dedicated PreviewEngine from rf-engine (separate from main timeline playback)
// ═══════════════════════════════════════════════════════════════════════════

/// Preview audio file - loads and plays immediately via dedicated PreviewEngine
/// Returns voice ID on success
#[flutter_rust_bridge::frb(sync)]
pub fn preview_audio_file(path: String, volume: f64) -> Result<u64, String> {
    use rf_engine::preview::PREVIEW_ENGINE;
    PREVIEW_ENGINE.play(&path, volume as f32)
}

/// Stop all preview playback
#[flutter_rust_bridge::frb(sync)]
pub fn preview_stop() {
    use rf_engine::preview::PREVIEW_ENGINE;
    PREVIEW_ENGINE.stop_all();
}

/// Check if preview is playing
#[flutter_rust_bridge::frb(sync)]
pub fn preview_is_playing() -> bool {
    use rf_engine::preview::PREVIEW_ENGINE;
    PREVIEW_ENGINE.is_playing()
}

/// Set preview master volume (0.0 to 1.0)
#[flutter_rust_bridge::frb(sync)]
pub fn preview_set_volume(volume: f64) {
    use rf_engine::preview::PREVIEW_ENGINE;
    PREVIEW_ENGINE.set_volume(volume as f32);
}

// ═══════════════════════════════════════════════════════════════════════════
// ONE-SHOT BUS PLAYBACK (for Middleware/SlotLab event preview through buses)
// Uses PlaybackEngine with bus routing - audio goes through DAW buses for mixing
// ═══════════════════════════════════════════════════════════════════════════

/// Play one-shot audio through a specific bus (Middleware/SlotLab events)
/// bus_id: 0=Sfx, 1=Music, 2=Voice, 3=Ambience, 4=Aux, 5=Master
/// Returns voice ID (0 = failed to queue)
#[flutter_rust_bridge::frb(sync)]
pub fn playback_play_to_bus(path: String, volume: f64, bus_id: u32) -> u64 {
    crate::PLAYBACK.play_one_shot_to_bus(&path, volume as f32, bus_id)
}

/// Stop specific one-shot voice
#[flutter_rust_bridge::frb(sync)]
pub fn playback_stop_one_shot(voice_id: u64) {
    crate::PLAYBACK.stop_one_shot(voice_id);
}

/// Stop all one-shot voices
#[flutter_rust_bridge::frb(sync)]
pub fn playback_stop_all_one_shots() {
    crate::PLAYBACK.stop_all_one_shots();
}

// ═══════════════════════════════════════════════════════════════════════════
// EQ
// ═══════════════════════════════════════════════════════════════════════════

/// EQ band parameters
#[flutter_rust_bridge::frb]
pub struct EqBandParams {
    pub enabled: bool,
    pub filter_type: u8, // 0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut, 5=Notch, 6=Bandpass, 7=Tilt, 8=Allpass
    pub frequency: f64,  // 20-20000 Hz
    pub gain: f64,       // -24 to +24 dB
    pub q: f64,          // 0.1 to 30
    pub slope: u8, // For cut filters: 0=6dB, 1=12dB, 2=18dB, 3=24dB, 4=36dB, 5=48dB, 6=72dB, 7=96dB
    pub stereo_mode: u8, // 0=Stereo, 1=Left, 2=Right, 3=Mid, 4=Side
}

/// Set EQ band parameters for a track
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band(track_id: u32, band_index: u8, params: EqBandParams) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, FilterSlope, FilterType, StereoPlacement};

    send_command(DspCommand::EqSetBand {
        track_id,
        band_index,
        freq: params.frequency,
        gain_db: params.gain,
        q: params.q,
        filter_type: FilterType::from(params.filter_type),
        slope: FilterSlope::from(params.slope),
        stereo: StereoPlacement::from(params.stereo_mode),
    })
}

/// Enable/disable EQ band
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band_enabled(track_id: u32, band_index: u8, enabled: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqEnableBand {
        track_id,
        band_index,
        enabled,
    })
}

/// Set EQ band frequency
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band_frequency(track_id: u32, band_index: u8, frequency: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSetFrequency {
        track_id,
        band_index,
        freq: frequency,
    })
}

/// Set EQ band gain
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band_gain(track_id: u32, band_index: u8, gain: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSetGain {
        track_id,
        band_index,
        gain_db: gain,
    })
}

/// Set EQ band Q
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band_q(track_id: u32, band_index: u8, q: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSetQ {
        track_id,
        band_index,
        q,
    })
}

/// Solo EQ band (preview)
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band_solo(track_id: u32, band_index: u8, solo: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSoloBand {
        track_id,
        band_index,
        solo,
    })
}

/// Set EQ band filter type
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band_filter_type(track_id: u32, band_index: u8, filter_type: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, FilterType};

    send_command(DspCommand::EqSetFilterType {
        track_id,
        band_index,
        filter_type: FilterType::from(filter_type),
    })
}

/// Set EQ global bypass
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_bypass(track_id: u32, bypass: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqBypass { track_id, bypass })
}

/// Set EQ phase mode (0=ZeroLatency, 1=Natural, 2=Linear, 3=Hybrid)
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_phase_mode(track_id: u32, mode: u8, hybrid_blend: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, PhaseMode};

    send_command(DspCommand::EqSetPhaseMode {
        track_id,
        mode: PhaseMode::from(mode),
        hybrid_blend,
    })
}

/// Set EQ output gain
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_output_gain(track_id: u32, gain_db: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSetOutputGain { track_id, gain_db })
}

/// Enable/disable auto-gain
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_auto_gain(track_id: u32, enabled: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSetAutoGain { track_id, enabled })
}

/// Set analyzer mode
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_analyzer_mode(track_id: u32, mode: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{AnalyzerMode, DspCommand};

    send_command(DspCommand::EqSetAnalyzerMode {
        track_id,
        mode: AnalyzerMode::from(mode),
    })
}

// ═══════════════════════════════════════════════════════════════════════════
// DYNAMIC EQ
// ═══════════════════════════════════════════════════════════════════════════

/// Enable dynamic mode for EQ band
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_dynamic_enabled(track_id: u32, band_index: u8, enabled: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSetDynamicEnabled {
        track_id,
        band_index,
        enabled,
    })
}

/// Set dynamic EQ parameters
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_dynamic_params(
    track_id: u32,
    band_index: u8,
    threshold_db: f64,
    ratio: f64,
    attack_ms: f64,
    release_ms: f64,
    range_db: f64,
) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqSetDynamicParams {
        track_id,
        band_index,
        threshold_db,
        ratio,
        attack_ms,
        release_ms,
        range_db,
    })
}

// ═══════════════════════════════════════════════════════════════════════════
// ANALOG EQ - PULTEC
// ═══════════════════════════════════════════════════════════════════════════

/// Set Pultec low boost
#[flutter_rust_bridge::frb(sync)]
pub fn pultec_set_low_boost(track_id: u32, boost_db: f64, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, PultecLowFreq};

    let freq = match freq_index {
        0 => PultecLowFreq::Hz20,
        1 => PultecLowFreq::Hz30,
        2 => PultecLowFreq::Hz60,
        _ => PultecLowFreq::Hz100,
    };

    send_command(DspCommand::PultecSetLowBoost {
        track_id,
        boost_db,
        freq,
    })
}

/// Set Pultec low attenuation
#[flutter_rust_bridge::frb(sync)]
pub fn pultec_set_low_atten(track_id: u32, atten_db: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::PultecSetLowAtten { track_id, atten_db })
}

/// Set Pultec high boost
#[flutter_rust_bridge::frb(sync)]
pub fn pultec_set_high_boost(track_id: u32, boost_db: f64, bandwidth: f64, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, PultecHighBoostFreq};

    let freq = match freq_index {
        0 => PultecHighBoostFreq::Khz3,
        1 => PultecHighBoostFreq::Khz4,
        2 => PultecHighBoostFreq::Khz5,
        3 => PultecHighBoostFreq::Khz8,
        4 => PultecHighBoostFreq::Khz10,
        5 => PultecHighBoostFreq::Khz12,
        _ => PultecHighBoostFreq::Khz16,
    };

    send_command(DspCommand::PultecSetHighBoost {
        track_id,
        boost_db,
        bandwidth,
        freq,
    })
}

/// Set Pultec high attenuation
#[flutter_rust_bridge::frb(sync)]
pub fn pultec_set_high_atten(track_id: u32, atten_db: f64, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, PultecHighAttenFreq};

    let freq = match freq_index {
        0 => PultecHighAttenFreq::Khz5,
        1 => PultecHighAttenFreq::Khz10,
        _ => PultecHighAttenFreq::Khz20,
    };

    send_command(DspCommand::PultecSetHighAtten {
        track_id,
        atten_db,
        freq,
    })
}

/// Bypass Pultec
#[flutter_rust_bridge::frb(sync)]
pub fn pultec_set_bypass(track_id: u32, bypass: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::PultecBypass { track_id, bypass })
}

// ═══════════════════════════════════════════════════════════════════════════
// ANALOG EQ - API 550
// ═══════════════════════════════════════════════════════════════════════════

/// Set API 550 low band
#[flutter_rust_bridge::frb(sync)]
pub fn api550_set_low(track_id: u32, gain_db: f64, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Api550SetLow {
        track_id,
        gain_db,
        freq_index,
    })
}

/// Set API 550 mid band
#[flutter_rust_bridge::frb(sync)]
pub fn api550_set_mid(track_id: u32, gain_db: f64, freq_hz: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Api550SetMid {
        track_id,
        gain_db,
        freq_hz,
    })
}

/// Set API 550 high band
#[flutter_rust_bridge::frb(sync)]
pub fn api550_set_high(track_id: u32, gain_db: f64, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Api550SetHigh {
        track_id,
        gain_db,
        freq_index,
    })
}

/// Bypass API 550
#[flutter_rust_bridge::frb(sync)]
pub fn api550_set_bypass(track_id: u32, bypass: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Api550Bypass { track_id, bypass })
}

// ═══════════════════════════════════════════════════════════════════════════
// ANALOG EQ - NEVE 1073
// ═══════════════════════════════════════════════════════════════════════════

/// Set Neve 1073 highpass
#[flutter_rust_bridge::frb(sync)]
pub fn neve1073_set_highpass(track_id: u32, enabled: bool, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Neve1073SetHighpass {
        track_id,
        enabled,
        freq_index,
    })
}

/// Set Neve 1073 low band
#[flutter_rust_bridge::frb(sync)]
pub fn neve1073_set_low(track_id: u32, gain_db: f64, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Neve1073SetLow {
        track_id,
        gain_db,
        freq_index,
    })
}

/// Set Neve 1073 mid band
#[flutter_rust_bridge::frb(sync)]
pub fn neve1073_set_mid(track_id: u32, gain_db: f64, freq_hz: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Neve1073SetMid {
        track_id,
        gain_db,
        freq_hz,
    })
}

/// Set Neve 1073 high band
#[flutter_rust_bridge::frb(sync)]
pub fn neve1073_set_high(track_id: u32, gain_db: f64, freq_index: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Neve1073SetHigh {
        track_id,
        gain_db,
        freq_index,
    })
}

/// Bypass Neve 1073
#[flutter_rust_bridge::frb(sync)]
pub fn neve1073_set_bypass(track_id: u32, bypass: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::Neve1073Bypass { track_id, bypass })
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO EQ
// ═══════════════════════════════════════════════════════════════════════════

/// Set bass mono crossover frequency
#[flutter_rust_bridge::frb(sync)]
pub fn stereo_eq_set_bass_mono_freq(track_id: u32, freq: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::StereoEqSetBassMonoFreq { track_id, freq })
}

/// Set bass mono blend amount
#[flutter_rust_bridge::frb(sync)]
pub fn stereo_eq_set_bass_mono_blend(track_id: u32, blend: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::StereoEqSetBassMonoBlend { track_id, blend })
}

/// Set per-band stereo width
#[flutter_rust_bridge::frb(sync)]
pub fn stereo_eq_set_band_width(track_id: u32, band_index: u8, width: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::StereoEqSetBandWidth {
        track_id,
        band_index,
        width,
    })
}

// ═══════════════════════════════════════════════════════════════════════════
// ROOM CORRECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Set room correction target curve
#[flutter_rust_bridge::frb(sync)]
pub fn room_eq_set_target_curve(track_id: u32, curve: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, TargetCurve};

    send_command(DspCommand::RoomEqSetTargetCurve {
        track_id,
        curve: TargetCurve::from(curve),
    })
}

/// Set room correction amount (0-100%)
#[flutter_rust_bridge::frb(sync)]
pub fn room_eq_set_amount(track_id: u32, amount: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::RoomEqSetAmount { track_id, amount })
}

/// Bypass room correction
#[flutter_rust_bridge::frb(sync)]
pub fn room_eq_set_bypass(track_id: u32, bypass: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::RoomEqBypass { track_id, bypass })
}

// ═══════════════════════════════════════════════════════════════════════════
// MORPHING EQ
// ═══════════════════════════════════════════════════════════════════════════

/// Set morph position (XY pad)
#[flutter_rust_bridge::frb(sync)]
pub fn morph_eq_set_position(track_id: u32, x: f64, y: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::MorphEqSetPosition { track_id, x, y })
}

/// Store current EQ to morph preset slot
#[flutter_rust_bridge::frb(sync)]
pub fn morph_eq_store_preset(track_id: u32, slot: u8) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::MorphEqStorePreset { track_id, slot })
}

/// Set morph transition time
#[flutter_rust_bridge::frb(sync)]
pub fn morph_eq_set_time(track_id: u32, time_ms: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::MorphEqSetTime { track_id, time_ms })
}

// ═══════════════════════════════════════════════════════════════════════════
// SPECTRUM ANALYZER
// ═══════════════════════════════════════════════════════════════════════════

/// Set spectrum FFT size
#[flutter_rust_bridge::frb(sync)]
pub fn spectrum_set_fft_size(track_id: u32, size: u16) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::SpectrumSetFftSize { track_id, size })
}

/// Set spectrum smoothing
#[flutter_rust_bridge::frb(sync)]
pub fn spectrum_set_smoothing(track_id: u32, smoothing: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::SpectrumSetSmoothing {
        track_id,
        smoothing,
    })
}

/// Set spectrum peak hold
#[flutter_rust_bridge::frb(sync)]
pub fn spectrum_set_peak_hold(track_id: u32, hold_ms: f64, decay_rate: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::SpectrumSetPeakHold {
        track_id,
        hold_ms,
        decay_rate,
    })
}

/// Freeze spectrum display
#[flutter_rust_bridge::frb(sync)]
pub fn spectrum_freeze(track_id: u32, freeze: bool) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::SpectrumFreeze { track_id, freeze })
}

/// Get spectrum data for visualization (256 bins)
#[flutter_rust_bridge::frb(sync)]
pub fn spectrum_get_data(track_id: u32) -> Vec<f32> {
    use crate::command_queue::get_spectrum;

    let spectrum = get_spectrum(track_id);
    spectrum.magnitudes.to_vec()
}

/// Get spectrum peak hold data
#[flutter_rust_bridge::frb(sync)]
pub fn spectrum_get_peaks(track_id: u32) -> Vec<f32> {
    use crate::command_queue::get_spectrum;

    let spectrum = get_spectrum(track_id);
    spectrum.peaks.to_vec()
}

/// Get EQ curve magnitude response (256 points)
#[flutter_rust_bridge::frb(sync)]
pub fn eq_get_curve(track_id: u32) -> Vec<f32> {
    use crate::command_queue::get_eq_curve;

    get_eq_curve(track_id).to_vec()
}

/// Get dynamic EQ gain reduction per band (64 bands)
#[flutter_rust_bridge::frb(sync)]
pub fn eq_get_dynamic_gr(track_id: u32) -> Vec<f32> {
    use crate::command_queue::get_dynamic_gr;

    get_dynamic_gr(track_id).to_vec()
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO METERING
// ═══════════════════════════════════════════════════════════════════════════

/// Get stereo correlation (-1 to +1)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_correlation(track_id: u32) -> f32 {
    use crate::command_queue::get_correlation;

    get_correlation(track_id)
}

/// Get stereo balance (-1 = left, +1 = right)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_balance(track_id: u32) -> f32 {
    use crate::command_queue::get_stereo_meter;

    get_stereo_meter(track_id).balance
}

/// Get stereo width (0-1)
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_width(track_id: u32) -> f32 {
    use crate::command_queue::get_stereo_meter;

    get_stereo_meter(track_id).width
}

/// Get LUFS momentary
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_lufs_momentary(track_id: u32) -> f32 {
    use crate::command_queue::get_loudness;

    get_loudness(track_id).momentary
}

/// Get LUFS short-term
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_lufs_short(track_id: u32) -> f32 {
    use crate::command_queue::get_loudness;

    get_loudness(track_id).short_term
}

/// Get LUFS integrated
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_lufs_integrated(track_id: u32) -> f32 {
    use crate::command_queue::get_loudness;

    get_loudness(track_id).integrated
}

/// Get true peak L/R
#[flutter_rust_bridge::frb(sync)]
pub fn metering_get_true_peak(track_id: u32) -> (f32, f32) {
    use crate::command_queue::get_loudness;

    let data = get_loudness(track_id);
    (data.true_peak_l, data.true_peak_r)
}

/// Poll analysis data updates (call from UI timer at ~60fps)
#[flutter_rust_bridge::frb(sync)]
pub fn poll_analysis_updates() {
    use crate::command_queue::poll_analysis;

    poll_analysis();
}

// ═══════════════════════════════════════════════════════════════════════════
// EQ MATCH
// ═══════════════════════════════════════════════════════════════════════════

/// Start learning source spectrum for EQ match
#[flutter_rust_bridge::frb(sync)]
pub fn eq_match_start_learn_source(track_id: u32) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqMatchStartLearnSource { track_id })
}

/// Start learning reference spectrum for EQ match
#[flutter_rust_bridge::frb(sync)]
pub fn eq_match_start_learn_reference(track_id: u32) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqMatchStartLearnReference { track_id })
}

/// Stop learning
#[flutter_rust_bridge::frb(sync)]
pub fn eq_match_stop_learn(track_id: u32) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqMatchStopLearn { track_id })
}

/// Apply learned EQ match
#[flutter_rust_bridge::frb(sync)]
pub fn eq_match_apply(track_id: u32, amount: f64, smoothing: f64) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::DspCommand;

    send_command(DspCommand::EqMatchApply {
        track_id,
        amount,
        smoothing,
    })
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER BUSES
// ═══════════════════════════════════════════════════════════════════════════

/// Set bus volume (dB to linear conversion)
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_bus_volume(bus_id: u32, volume_db: f64) -> bool {
    // Convert dB to linear: linear = 10^(dB/20)
    let linear = if volume_db <= -60.0 {
        0.0
    } else {
        10.0_f64.powf(volume_db / 20.0)
    };

    crate::PLAYBACK.set_bus_volume(bus_id as usize, linear);
    log::debug!(
        "Bus {} volume: {} dB (linear: {:.4})",
        bus_id,
        volume_db,
        linear
    );
    true
}

/// Set bus mute
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_bus_mute(bus_id: u32, muted: bool) -> bool {
    crate::PLAYBACK.set_bus_mute(bus_id as usize, muted);
    log::debug!("Bus {} mute: {}", bus_id, muted);
    true
}

/// Set bus solo
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_bus_solo(bus_id: u32, solo: bool) -> bool {
    crate::PLAYBACK.set_bus_solo(bus_id as usize, solo);
    log::debug!("Bus {} solo: {}", bus_id, solo);
    true
}

/// Set bus pan
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_bus_pan(bus_id: u32, pan: f64) -> bool {
    crate::PLAYBACK.set_bus_pan(bus_id as usize, pan);
    log::debug!("Bus {} pan: {}", bus_id, pan);
    true
}

/// Set master volume
#[flutter_rust_bridge::frb(sync)]
pub fn mixer_set_master_volume(volume_db: f64) -> bool {
    // Convert dB to linear
    let linear = if volume_db <= -60.0 {
        0.0
    } else {
        10.0_f64.powf(volume_db / 20.0)
    };

    crate::PLAYBACK.set_master_volume(linear);
    log::debug!("Master volume: {} dB (linear: {:.4})", volume_db, linear);
    true
}

/// Get memory usage in MB
#[flutter_rust_bridge::frb(sync)]
pub fn system_get_memory_usage() -> f32 {
    // Return approximate memory usage
    // TODO: Implement proper tracking
    0.0
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO PROCESSING
// ═══════════════════════════════════════════════════════════════════════════

/// Normalize clip audio to target level
#[flutter_rust_bridge::frb(sync)]
pub fn clip_normalize(clip_id: u64, target_db: f64) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!("Normalize clip {} to {} dB", clip_id, target_db);
        // TODO: Implement in engine
        true
    } else {
        false
    }
}

/// Reverse clip audio
#[flutter_rust_bridge::frb(sync)]
pub fn clip_reverse(clip_id: u64) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!("Reverse clip {}", clip_id);
        // TODO: Implement in engine
        true
    } else {
        false
    }
}

/// Fade in clip
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fade_in(clip_id: u64, duration_sec: f64, curve_type: u8) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!(
            "Fade in clip {} for {} sec, curve {}",
            clip_id,
            duration_sec,
            curve_type
        );
        true
    } else {
        false
    }
}

/// Fade out clip
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fade_out(clip_id: u64, duration_sec: f64, curve_type: u8) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!(
            "Fade out clip {} for {} sec, curve {}",
            clip_id,
            duration_sec,
            curve_type
        );
        true
    } else {
        false
    }
}

/// Apply gain to clip
#[flutter_rust_bridge::frb(sync)]
pub fn clip_apply_gain(clip_id: u64, gain_db: f64) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!("Apply {} dB gain to clip {}", gain_db, clip_id);
        true
    } else {
        false
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

/// Create a new track
#[flutter_rust_bridge::frb(sync)]
pub fn track_create(name: String, color: u32, bus_id: u32) -> u64 {
    let mut engine = ENGINE.write();
    if let Some(ref mut _e) = *engine {
        log::debug!("Create track '{}' color={} bus={}", name, color, bus_id);
        // TODO: Implement in engine
        1 // Return mock track ID
    } else {
        0
    }
}

/// Delete a track
#[flutter_rust_bridge::frb(sync)]
pub fn track_delete(track_id: u64) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut _e) = *engine {
        log::debug!("Delete track {}", track_id);
        true
    } else {
        false
    }
}

/// Rename a track
#[flutter_rust_bridge::frb(sync)]
pub fn track_rename(track_id: u64, name: String) -> bool {
    let mut engine = ENGINE.write();
    if let Some(ref mut _e) = *engine {
        log::debug!("Rename track {} to '{}'", track_id, name);
        true
    } else {
        false
    }
}

/// Duplicate a track
#[flutter_rust_bridge::frb(sync)]
pub fn track_duplicate(track_id: u64) -> u64 {
    let mut engine = ENGINE.write();
    if let Some(ref mut _e) = *engine {
        log::debug!("Duplicate track {}", track_id);
        2 // Return mock new track ID
    } else {
        0
    }
}

/// Set track color
#[flutter_rust_bridge::frb(sync)]
pub fn track_set_color(track_id: u64, color: u32) -> bool {
    let engine = ENGINE.read();
    if engine.is_some() {
        log::debug!("Set track {} color to {}", track_id, color);
        true
    } else {
        false
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// IMPORT/EXPORT
// ═══════════════════════════════════════════════════════════════════════════

/// Scan folder for audio files
#[flutter_rust_bridge::frb]
pub struct AudioFileInfo {
    pub path: String,
    pub name: String,
    pub duration_sec: f64,
    pub sample_rate: u32,
    pub channels: u8,
    pub format: String,
}

/// Scan folder for audio files (returns list of file info)
#[flutter_rust_bridge::frb(sync)]
pub fn import_scan_folder(folder_path: String) -> Vec<AudioFileInfo> {
    log::debug!("Scanning folder for audio: {}", folder_path);

    let path = std::path::Path::new(&folder_path);
    if !path.exists() || !path.is_dir() {
        return vec![];
    }

    let mut files = Vec::new();

    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let entry_path = entry.path();
            if entry_path.is_file() {
                if let Some(ext) = entry_path.extension() {
                    let ext_lower = ext.to_string_lossy().to_lowercase();
                    if matches!(
                        ext_lower.as_str(),
                        "wav" | "mp3" | "flac" | "aiff" | "ogg" | "m4a"
                    ) {
                        files.push(AudioFileInfo {
                            path: entry_path.to_string_lossy().to_string(),
                            name: entry_path
                                .file_name()
                                .map(|n| n.to_string_lossy().to_string())
                                .unwrap_or_default(),
                            duration_sec: 0.0, // TODO: Read actual duration
                            sample_rate: 48000,
                            channels: 2,
                            format: ext_lower,
                        });
                    }
                }
            }
        }
    }

    files
}

/// Export/Build project to audio file
#[flutter_rust_bridge::frb(sync)]
pub fn export_build(
    output_path: String,
    format: String, // "wav", "mp3", "flac"
    sample_rate: u32,
    bit_depth: u8, // 16, 24, 32
    normalize: bool,
    normalize_target_db: f64,
) -> Result<(), String> {
    use rf_file::{
        AudioData, AudioFormat, BitDepth, BounceConfig, BounceRegion, DitherType, ExportFormat,
        NoiseShapeType, OfflineRenderer, PassthroughProcessor,
    };
    use std::path::PathBuf;

    log::info!(
        "Export to {} ({}, {}Hz, {}bit, normalize={})",
        output_path,
        format,
        sample_rate,
        bit_depth,
        normalize
    );

    let engine = ENGINE.read();
    let e = engine.as_ref().ok_or("Engine not initialized")?;

    // Get track manager and render all audio
    let track_manager = e.track_manager();
    let playback = e.playback_engine();

    // Calculate project duration from clips
    let all_clips = track_manager.get_all_clips();
    let duration_secs = all_clips
        .iter()
        .map(|c| c.end_time())
        .fold(0.0_f64, f64::max);

    if duration_secs <= 0.0 {
        return Err("No audio to export".to_string());
    }

    let source_sample_rate = 48000u32; // Default sample rate
    let total_samples = (duration_secs * source_sample_rate as f64) as u64;

    // Parse format
    let audio_format = match format.to_lowercase().as_str() {
        "wav" => AudioFormat::Wav,
        "flac" => AudioFormat::Flac,
        "mp3" => AudioFormat::Mp3,
        "aac" => AudioFormat::Aac,
        "ogg" => AudioFormat::Ogg,
        _ => AudioFormat::Wav,
    };

    // Parse bit depth
    let bit_depth_enum = match bit_depth {
        16 => BitDepth::Int16,
        24 => BitDepth::Int24,
        32 => BitDepth::Float32,
        _ => BitDepth::Int24,
    };

    // Create export configuration
    let export_format = ExportFormat {
        format: audio_format,
        bit_depth: bit_depth_enum,
        sample_rate: if sample_rate > 0 {
            sample_rate
        } else {
            source_sample_rate
        },
        bitrate: 320,
        dither: DitherType::Triangular,
        noise_shape: NoiseShapeType::None,
        normalize,
        normalize_target: normalize_target_db,
        allow_clip: false,
    };

    let config = BounceConfig {
        output_path: PathBuf::from(&output_path),
        export_format,
        region: BounceRegion {
            start_samples: 0,
            end_samples: total_samples,
            include_tail: true,
            tail_secs: 2.0,
        },
        source_sample_rate,
        num_channels: 2,
        offline: true,
        block_size: 4096,
    };

    // Render audio offline
    let block_size = 4096;
    let num_blocks = (total_samples as usize).div_ceil(block_size);
    let mut left_samples = Vec::with_capacity(total_samples as usize);
    let mut right_samples = Vec::with_capacity(total_samples as usize);

    for block_idx in 0..num_blocks {
        let start_sample = block_idx * block_size;
        let mut left_block = vec![0.0f64; block_size];
        let mut right_block = vec![0.0f64; block_size];

        // Process through playback engine (offline mode)
        playback.process_offline(start_sample, &mut left_block, &mut right_block);

        left_samples.extend_from_slice(&left_block);
        right_samples.extend_from_slice(&right_block);

        // Log progress
        if block_idx % 100 == 0 {
            let progress = (block_idx as f32 / num_blocks as f32) * 100.0;
            log::debug!("Export progress: {:.1}%", progress);
        }
    }

    // Truncate to exact length
    left_samples.truncate(total_samples as usize);
    right_samples.truncate(total_samples as usize);

    // Create audio data
    let audio_data = AudioData {
        channels: vec![left_samples, right_samples],
        sample_rate: source_sample_rate,
        bit_depth: bit_depth_enum,
        format: audio_format,
    };

    // Create offline renderer and render
    let mut renderer = OfflineRenderer::new(config);
    let mut processor = PassthroughProcessor;

    match renderer.render(&audio_data, &mut processor) {
        Ok(path) => {
            log::info!("Export complete: {}", path.display());
            Ok(())
        }
        Err(err) => {
            log::error!("Export failed: {}", err);
            Err(err.to_string())
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO DEVICES
// ═══════════════════════════════════════════════════════════════════════════

/// Audio device info for Flutter
#[derive(Debug, Clone)]
pub struct AudioDeviceInfo {
    pub name: String,
    pub is_default: bool,
    pub channels: u16,
    pub sample_rates: Vec<u32>,
}

/// Audio host info for Flutter
#[derive(Debug, Clone)]
pub struct AudioHostInfo {
    pub name: String,
    pub is_asio: bool,
    pub is_jack: bool,
    pub is_core_audio: bool,
}

/// List available output devices
#[flutter_rust_bridge::frb(sync)]
pub fn audio_list_output_devices() -> Vec<AudioDeviceInfo> {
    match rf_audio::list_output_devices() {
        Ok(devices) => devices
            .into_iter()
            .map(|d| AudioDeviceInfo {
                name: d.name,
                is_default: d.is_default,
                channels: d.output_channels,
                sample_rates: d.sample_rates,
            })
            .collect(),
        Err(e) => {
            log::error!("Failed to list output devices: {}", e);
            Vec::new()
        }
    }
}

/// List available input devices
#[flutter_rust_bridge::frb(sync)]
pub fn audio_list_input_devices() -> Vec<AudioDeviceInfo> {
    match rf_audio::list_input_devices() {
        Ok(devices) => devices
            .into_iter()
            .map(|d| AudioDeviceInfo {
                name: d.name,
                is_default: d.is_default,
                channels: d.input_channels,
                sample_rates: d.sample_rates,
            })
            .collect(),
        Err(e) => {
            log::error!("Failed to list input devices: {}", e);
            Vec::new()
        }
    }
}

/// Get audio host information
#[flutter_rust_bridge::frb(sync)]
pub fn audio_get_host_info() -> AudioHostInfo {
    let info = rf_audio::get_host_info();
    AudioHostInfo {
        name: info.name,
        is_asio: info.is_asio,
        is_jack: info.is_jack,
        is_core_audio: info.is_core_audio,
    }
}

/// List available audio backends
#[flutter_rust_bridge::frb(sync)]
pub fn audio_list_hosts() -> Vec<String> {
    rf_audio::list_available_hosts()
}

/// Set output device by name
#[allow(unused_must_use)]
#[flutter_rust_bridge::frb(sync)]
pub fn audio_set_output_device(device_name: String) -> bool {
    // Stop current stream
    crate::PLAYBACK.stop();

    // Get the device
    match rf_audio::get_output_device_by_name(&device_name) {
        Ok(_device) => {
            log::info!("Output device set to: {}", device_name);
            // Restart stream with new device
            if let Err(e) = crate::PLAYBACK.start_with_device(&device_name) {
                log::error!("Failed to start stream: {}", e);
                return false;
            }
            true
        }
        Err(e) => {
            log::error!("Device not found: {} - {}", device_name, e);
            false
        }
    }
}

/// Set input device by name
#[flutter_rust_bridge::frb(sync)]
pub fn audio_set_input_device(device_name: String) -> bool {
    log::info!("Input device set to: {}", device_name);
    // TODO: Store selection and use for recording
    true
}

/// Set sample rate
#[flutter_rust_bridge::frb(sync)]
pub fn audio_set_sample_rate(sample_rate: u32) -> bool {
    log::info!("Sample rate set to: {}", sample_rate);
    match crate::PLAYBACK.restart_with_settings(Some(sample_rate), None) {
        Ok(()) => true,
        Err(e) => {
            log::error!("Failed to set sample rate: {}", e);
            false
        }
    }
}

/// Set buffer size
#[flutter_rust_bridge::frb(sync)]
pub fn audio_set_buffer_size(buffer_size: u32) -> bool {
    log::info!("Buffer size set to: {}", buffer_size);
    match crate::PLAYBACK.restart_with_settings(None, Some(buffer_size)) {
        Ok(()) => true,
        Err(e) => {
            log::error!("Failed to set buffer size: {}", e);
            false
        }
    }
}

/// Get current audio settings
#[flutter_rust_bridge::frb(sync)]
pub fn audio_get_current_settings() -> AudioSettings {
    AudioSettings {
        output_device: crate::PLAYBACK.current_output_device(),
        input_device: None, // TODO
        sample_rate: crate::PLAYBACK.sample_rate() as u32,
        buffer_size: crate::PLAYBACK.get_current_buffer_size(),
        latency_ms: crate::PLAYBACK.latency_ms(),
    }
}

/// Current audio settings
#[derive(Debug, Clone)]
pub struct AudioSettings {
    pub output_device: Option<String>,
    pub input_device: Option<String>,
    pub sample_rate: u32,
    pub buffer_size: u32,
    pub latency_ms: f64,
}

/// Refresh device list (for hot-plug detection)
#[flutter_rust_bridge::frb(sync)]
pub fn audio_refresh_devices() {
    log::debug!("Refreshing audio device list");
    // The list functions already refresh
}

/// Test audio output (plays a short beep)
#[flutter_rust_bridge::frb(sync)]
pub fn audio_test_output() -> bool {
    crate::PLAYBACK.play_test_tone(440.0, 0.5);
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING API
// ═══════════════════════════════════════════════════════════════════════════

/// Recording status info
#[derive(Debug, Clone)]
pub struct RecordingStatus {
    pub is_recording: bool,
    pub is_armed: bool,
    pub duration_secs: f64,
    pub samples_recorded: u64,
    pub peak_level: f32,
    pub clips_detected: u32,
    pub output_path: Option<String>,
}

/// Recording configuration
#[derive(Debug, Clone)]
pub struct RecordingSettings {
    pub output_dir: String,
    pub file_prefix: String,
    pub bit_depth: u8, // 16, 24, or 32
    pub pre_roll_secs: f32,
    pub input_monitoring: bool,
}

impl Default for RecordingSettings {
    fn default() -> Self {
        Self {
            output_dir: String::from("."),
            file_prefix: String::from("Recording"),
            bit_depth: 24,
            pre_roll_secs: 2.0,
            input_monitoring: true,
        }
    }
}

/// Get recording status
#[flutter_rust_bridge::frb(sync)]
pub fn recording_get_status() -> RecordingStatus {
    use rf_file::RecordingState;

    let state = PLAYBACK.recording_state();
    let stats = PLAYBACK.recorder().stats();
    let (peak_l, peak_r) = PLAYBACK.get_input_peaks();

    RecordingStatus {
        is_recording: state == RecordingState::Recording,
        is_armed: state == RecordingState::Armed,
        duration_secs: stats.duration_secs,
        samples_recorded: stats.samples_recorded,
        peak_level: peak_l.max(peak_r),
        clips_detected: stats.clips_detected,
        output_path: None, // File path returned on stop
    }
}

/// Arm recording (prepare without starting)
#[flutter_rust_bridge::frb(sync)]
pub fn recording_arm() -> bool {
    PLAYBACK.recording_arm()
}

/// Disarm recording
#[flutter_rust_bridge::frb(sync)]
pub fn recording_disarm() {
    PLAYBACK.recording_disarm();
}

/// Start recording
#[flutter_rust_bridge::frb(sync)]
pub fn recording_start() -> bool {
    match PLAYBACK.recording_start() {
        Ok(path) => {
            log::info!("Recording started: {}", path);
            true
        }
        Err(e) => {
            log::error!("Failed to start recording: {}", e);
            false
        }
    }
}

/// Stop recording
#[flutter_rust_bridge::frb(sync)]
pub fn recording_stop() -> Option<String> {
    let path = PLAYBACK.recording_stop();
    if let Some(ref p) = path {
        log::info!("Recording stopped: {}", p);
    }
    path
}

/// Pause recording
#[flutter_rust_bridge::frb(sync)]
pub fn recording_pause() -> bool {
    PLAYBACK.recording_pause()
}

/// Resume recording
#[flutter_rust_bridge::frb(sync)]
pub fn recording_resume() -> bool {
    PLAYBACK.recording_resume()
}

/// Set recording output directory
#[flutter_rust_bridge::frb(sync)]
pub fn recording_set_output_dir(path: String) -> bool {
    use std::path::PathBuf;

    let config = rf_file::RecordingConfig {
        output_dir: PathBuf::from(&path),
        file_prefix: "Recording".to_string(),
        sample_rate: PLAYBACK.sample_rate() as u32,
        bit_depth: rf_file::BitDepth::Int24,
        num_channels: 2,
        pre_roll_secs: 2.0,
        capture_pre_roll: true,
        min_disk_space: 100 * 1024 * 1024,
        disk_buffer_size: 256 * 1024,
        auto_increment: true,
    };

    PLAYBACK.set_recording_config(config);
    log::info!("Recording output dir: {}", path);
    true
}

/// Set recording bit depth
#[flutter_rust_bridge::frb(sync)]
pub fn recording_set_bit_depth(bits: u8) -> bool {
    if bits == 16 || bits == 24 || bits == 32 {
        log::info!("Recording bit depth: {}", bits);
        // Note: Would need to update config, but bit_depth is not easily changed
        // without full config reconstruction
        true
    } else {
        false
    }
}

/// Enable/disable input monitoring
#[flutter_rust_bridge::frb(sync)]
pub fn recording_set_monitoring(enabled: bool) -> bool {
    log::info!("Input monitoring: {}", enabled);
    // Input monitoring is handled in audio callback when input stream is connected
    true
}

/// Get input level meters (for recording UI)
#[flutter_rust_bridge::frb(sync)]
pub fn recording_get_input_levels() -> (f32, f32) {
    PLAYBACK.get_input_peaks()
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO EXPORT API
// ═══════════════════════════════════════════════════════════════════════════

/// Export file format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportFileFormat {
    Wav,
    Flac,
    Mp3,
    Aac,
    Ogg,
}

impl From<u8> for ExportFileFormat {
    fn from(v: u8) -> Self {
        match v {
            0 => ExportFileFormat::Wav,
            1 => ExportFileFormat::Flac,
            2 => ExportFileFormat::Mp3,
            3 => ExportFileFormat::Aac,
            4 => ExportFileFormat::Ogg,
            _ => ExportFileFormat::Wav,
        }
    }
}

/// Dither type for export
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportDither {
    None,
    Rectangular,
    Triangular,
    NoiseShape,
}

impl From<u8> for ExportDither {
    fn from(v: u8) -> Self {
        match v {
            0 => ExportDither::None,
            1 => ExportDither::Rectangular,
            2 => ExportDither::Triangular,
            3 => ExportDither::NoiseShape,
            _ => ExportDither::None,
        }
    }
}

/// Export configuration
#[derive(Debug, Clone)]
pub struct ExportConfig {
    pub output_path: String,
    pub format: u8, // 0=Wav, 1=Flac, 2=Mp3, 3=Aac, 4=Ogg
    pub sample_rate: u32,
    pub bit_depth: u8, // 16, 24, 32
    pub channels: u8,  // 1=Mono, 2=Stereo
    pub normalize: bool,
    pub normalize_target_db: f64,
    pub dither: u8,     // 0=None, 1=Rectangular, 2=Triangular, 3=NoiseShape
    pub start_sec: f64, // Export range start (0 = project start)
    pub end_sec: f64,   // Export range end (0 = project end)
    pub include_master_fx: bool,
    pub real_time: bool, // Real-time export (for external hardware)
}

impl Default for ExportConfig {
    fn default() -> Self {
        Self {
            output_path: String::new(),
            format: 0, // WAV
            sample_rate: 48000,
            bit_depth: 24,
            channels: 2,
            normalize: false,
            normalize_target_db: -1.0,
            dither: 0, // None
            start_sec: 0.0,
            end_sec: 0.0,
            include_master_fx: true,
            real_time: false,
        }
    }
}

/// Export progress information
#[derive(Debug, Clone)]
pub struct ExportProgress {
    pub is_exporting: bool,
    pub progress: f32, // 0.0 - 1.0
    pub current_time_sec: f64,
    pub total_time_sec: f64,
    pub eta_secs: f64,
    pub phase: String, // "Rendering", "Normalizing", "Encoding", "Complete"
    pub error: Option<String>,
}

impl Default for ExportProgress {
    fn default() -> Self {
        Self {
            is_exporting: false,
            progress: 0.0,
            current_time_sec: 0.0,
            total_time_sec: 0.0,
            eta_secs: 0.0,
            phase: String::from("Idle"),
            error: None,
        }
    }
}

/// Export result
#[derive(Debug, Clone)]
pub struct ExportResult {
    pub success: bool,
    pub output_path: String,
    pub duration_sec: f64,
    pub file_size_bytes: u64,
    pub peak_level_db: f64,
    pub lufs_integrated: f64,
    pub true_peak_db: f64,
    pub error: Option<String>,
}

/// Export preset
#[derive(Debug, Clone)]
pub struct ExportPreset {
    pub name: String,
    pub format: u8,
    pub sample_rate: u32,
    pub bit_depth: u8,
    pub normalize: bool,
    pub normalize_target_db: f64,
    pub dither: u8,
}

/// Path validation result
#[derive(Debug, Clone)]
pub struct ExportPathValidation {
    pub valid: bool,
    pub error: Option<String>,
    pub suggested_path: Option<String>,
    pub will_overwrite: bool,
}

// Global export state
use parking_lot::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

static EXPORT_IN_PROGRESS: AtomicBool = AtomicBool::new(false);
static EXPORT_CANCELLED: AtomicBool = AtomicBool::new(false);
static EXPORT_PROGRESS: Mutex<ExportProgress> = Mutex::new(ExportProgress {
    is_exporting: false,
    progress: 0.0,
    current_time_sec: 0.0,
    total_time_sec: 0.0,
    eta_secs: 0.0,
    phase: String::new(),
    error: None,
});

/// Start audio export with configuration
#[flutter_rust_bridge::frb(sync)]
pub fn export_start(config: ExportConfig) -> bool {
    use rf_file::{
        AudioFormat, BounceConfig, BounceRegion, DitherType, ExportFormat, OfflineRenderer,
        PassthroughProcessor,
    };
    use std::path::PathBuf;

    if EXPORT_IN_PROGRESS.load(Ordering::SeqCst) {
        log::warn!("Export already in progress");
        return false;
    }

    let engine = ENGINE.read();
    if engine.is_none() {
        log::error!("Engine not initialized for export");
        return false;
    }

    // Validate path
    if config.output_path.is_empty() {
        log::error!("Export path is empty");
        return false;
    }

    // Set export state
    EXPORT_IN_PROGRESS.store(true, Ordering::SeqCst);
    EXPORT_CANCELLED.store(false, Ordering::SeqCst);

    // Initialize progress
    {
        let mut progress = EXPORT_PROGRESS.lock();
        progress.is_exporting = true;
        progress.progress = 0.0;
        progress.phase = String::from("Rendering");
        progress.error = None;
    }

    log::info!(
        "Starting export to {} (format={}, {}Hz, {}bit)",
        config.output_path,
        config.format,
        config.sample_rate,
        config.bit_depth
    );

    // Convert API config to rf_file config
    let audio_format = match config.format {
        0 => AudioFormat::Wav,
        1 => AudioFormat::Flac,
        2 => AudioFormat::Mp3,
        3 => AudioFormat::Aac,
        4 => AudioFormat::Ogg,
        _ => AudioFormat::Wav,
    };

    let bit_depth = match config.bit_depth {
        16 => rf_file::BitDepth::Int16,
        24 => rf_file::BitDepth::Int24,
        32 => rf_file::BitDepth::Float32,
        _ => rf_file::BitDepth::Int24,
    };

    let dither = match config.dither {
        0 => DitherType::None,
        1 => DitherType::Rectangular,
        2 => DitherType::Triangular,
        3 => DitherType::NoiseShape,
        _ => DitherType::None,
    };

    let source_sample_rate = PLAYBACK.sample_rate() as u32;
    let start_samples = (config.start_sec * source_sample_rate as f64) as u64;
    let end_samples = if config.end_sec > 0.0 {
        (config.end_sec * source_sample_rate as f64) as u64
    } else {
        u64::MAX // Entire project
    };

    let bounce_config = BounceConfig {
        output_path: PathBuf::from(&config.output_path),
        export_format: ExportFormat {
            format: audio_format,
            bit_depth,
            sample_rate: config.sample_rate,
            bitrate: 320, // Default for lossy
            dither,
            noise_shape: rf_file::NoiseShapeType::None,
            normalize: config.normalize,
            normalize_target: config.normalize_target_db,
            allow_clip: false,
        },
        region: BounceRegion {
            start_samples,
            end_samples,
            include_tail: true,
            tail_secs: 2.0,
        },
        source_sample_rate,
        num_channels: config.channels as u16,
        offline: !config.real_time,
        block_size: 1024,
    };

    let _output_path = config.output_path.clone();

    // Spawn export thread
    std::thread::spawn(move || {
        let mut renderer = OfflineRenderer::new(bounce_config);

        // Set up progress callback
        let _progress_clone = EXPORT_PROGRESS.lock().clone();
        let total_secs = if end_samples < u64::MAX {
            (end_samples - start_samples) as f64 / source_sample_rate as f64
        } else {
            60.0 // Default estimate
        };

        // Update progress periodically
        renderer.set_progress_callback(move |bounce_progress| {
            if EXPORT_CANCELLED.load(Ordering::SeqCst) {
                return;
            }

            let mut progress = EXPORT_PROGRESS.lock();
            progress.progress = bounce_progress.percent / 100.0;
            progress.current_time_sec =
                bounce_progress.processed_samples as f64 / source_sample_rate as f64;
            progress.total_time_sec = total_secs;
            progress.eta_secs = bounce_progress.eta_secs as f64;
        });

        // Calculate duration
        let duration_samples = if end_samples < u64::MAX {
            (end_samples - start_samples) as usize
        } else {
            // Default to 60 seconds if no end specified
            (60.0 * source_sample_rate as f64) as usize
        };

        // Allocate output buffers
        let mut output_l = vec![0.0f64; duration_samples];
        let mut output_r = vec![0.0f64; duration_samples];

        // Render audio from playback engine offline
        // Process in blocks to avoid memory issues and allow progress updates
        let block_size = 1024;
        let total_blocks = (duration_samples + block_size - 1) / block_size;

        {
            let mut progress = EXPORT_PROGRESS.lock();
            progress.total_time_sec = duration_samples as f64 / source_sample_rate as f64;
        }

        for block_idx in 0..total_blocks {
            // Check for cancellation
            if EXPORT_CANCELLED.load(Ordering::SeqCst) {
                let mut progress = EXPORT_PROGRESS.lock();
                progress.is_exporting = false;
                progress.phase = String::from("Cancelled");
                EXPORT_IN_PROGRESS.store(false, Ordering::SeqCst);
                return;
            }

            let block_start = block_idx * block_size;
            let block_end = (block_start + block_size).min(duration_samples);

            // Get samples from start position
            let sample_position = start_samples + block_start as u64;

            // Render this block from playback engine
            PLAYBACK.process_offline(
                sample_position,
                &mut output_l[block_start..block_end],
                &mut output_r[block_start..block_end],
            );

            // Update progress
            {
                let mut progress = EXPORT_PROGRESS.lock();
                progress.progress = (block_end as f32) / (duration_samples as f32);
                progress.current_time_sec = block_end as f64 / source_sample_rate as f64;
                let elapsed = progress.current_time_sec;
                let remaining = progress.total_time_sec - elapsed;
                let speed = if progress.progress > 0.0 {
                    elapsed / progress.progress as f64
                } else {
                    1.0
                };
                progress.eta_secs = remaining / speed.max(0.01);
            }
        }

        // Create AudioData from rendered buffers
        // AudioData stores channels as Vec<Vec<f64>>
        let audio_data = rf_file::AudioData {
            channels: vec![output_l, output_r],
            sample_rate: source_sample_rate,
            bit_depth: rf_file::BitDepth::Float64,
            format: rf_file::AudioFormat::Unknown,
        };

        // Update phase
        {
            let mut progress = EXPORT_PROGRESS.lock();
            progress.phase = String::from("Writing file");
        }

        let mut processor = PassthroughProcessor;

        match renderer.render(&audio_data, &mut processor) {
            Ok(path) => {
                let mut progress = EXPORT_PROGRESS.lock();
                progress.is_exporting = false;
                progress.progress = 1.0;
                progress.phase = String::from("Complete");
                log::info!("Export complete: {:?}", path);
            }
            Err(e) => {
                let mut progress = EXPORT_PROGRESS.lock();
                progress.is_exporting = false;
                progress.phase = String::from("Error");
                progress.error = Some(e.to_string());
                log::error!("Export failed: {}", e);
            }
        }

        EXPORT_IN_PROGRESS.store(false, Ordering::SeqCst);
    });

    true
}

/// Cancel ongoing export
#[flutter_rust_bridge::frb(sync)]
pub fn export_cancel() -> bool {
    if !EXPORT_IN_PROGRESS.load(Ordering::SeqCst) {
        return false;
    }

    EXPORT_CANCELLED.store(true, Ordering::SeqCst);
    log::info!("Export cancelled by user");
    true
}

/// Get export progress
#[flutter_rust_bridge::frb(sync)]
pub fn export_get_progress() -> ExportProgress {
    EXPORT_PROGRESS.lock().clone()
}

/// Quick export with preset name
#[flutter_rust_bridge::frb(sync)]
pub fn export_with_preset(preset_name: String, output_path: String) -> bool {
    let config = match preset_name.as_str() {
        "CD Quality" => ExportConfig {
            output_path,
            format: 0, // WAV
            sample_rate: 44100,
            bit_depth: 16,
            normalize: false,
            dither: 2, // Triangular
            ..Default::default()
        },
        "High Quality" => ExportConfig {
            output_path,
            format: 0, // WAV
            sample_rate: 48000,
            bit_depth: 24,
            normalize: false,
            ..Default::default()
        },
        "Master" => ExportConfig {
            output_path,
            format: 0, // WAV
            sample_rate: 96000,
            bit_depth: 32,
            normalize: false,
            ..Default::default()
        },
        "MP3 320k" => ExportConfig {
            output_path,
            format: 2, // MP3
            sample_rate: 44100,
            bit_depth: 16,
            ..Default::default()
        },
        "FLAC Lossless" => ExportConfig {
            output_path,
            format: 1, // FLAC
            sample_rate: 48000,
            bit_depth: 24,
            ..Default::default()
        },
        _ => {
            log::error!("Unknown preset: {}", preset_name);
            return false;
        }
    };

    export_start(config)
}

/// Get available export presets
#[flutter_rust_bridge::frb(sync)]
pub fn export_get_presets() -> Vec<ExportPreset> {
    vec![
        ExportPreset {
            name: String::from("CD Quality"),
            format: 0,
            sample_rate: 44100,
            bit_depth: 16,
            normalize: false,
            normalize_target_db: -1.0,
            dither: 2,
        },
        ExportPreset {
            name: String::from("High Quality"),
            format: 0,
            sample_rate: 48000,
            bit_depth: 24,
            normalize: false,
            normalize_target_db: -1.0,
            dither: 0,
        },
        ExportPreset {
            name: String::from("Master"),
            format: 0,
            sample_rate: 96000,
            bit_depth: 32,
            normalize: false,
            normalize_target_db: -1.0,
            dither: 0,
        },
        ExportPreset {
            name: String::from("MP3 320k"),
            format: 2,
            sample_rate: 44100,
            bit_depth: 16,
            normalize: true,
            normalize_target_db: -1.0,
            dither: 0,
        },
        ExportPreset {
            name: String::from("FLAC Lossless"),
            format: 1,
            sample_rate: 48000,
            bit_depth: 24,
            normalize: false,
            normalize_target_db: -1.0,
            dither: 0,
        },
        ExportPreset {
            name: String::from("Broadcast"),
            format: 0,
            sample_rate: 48000,
            bit_depth: 24,
            normalize: true,
            normalize_target_db: -23.0, // EBU R128
            dither: 0,
        },
    ]
}

/// Export individual stems (per track)
#[flutter_rust_bridge::frb(sync)]
pub fn export_stems(output_dir: String, format: u8, bit_depth: u8) -> bool {
    use rf_engine::{AudioImporter, ImportedAudio, InsertChain, OfflineRenderer};
    use rf_file::{AudioData, AudioFormat, write_flac, write_wav};
    use std::collections::HashMap;
    use std::path::PathBuf;
    use std::sync::Arc;

    if EXPORT_IN_PROGRESS.load(Ordering::SeqCst) {
        log::warn!("Export already in progress");
        return false;
    }

    let engine = ENGINE.read();
    let engine_ref = match engine.as_ref() {
        Some(e) => e,
        None => {
            log::error!("Engine not initialized for stems export");
            return false;
        }
    };

    // Get track manager and tracks
    let track_manager = engine_ref.track_manager();
    let tracks = track_manager.get_all_tracks();

    if tracks.is_empty() {
        log::warn!("No tracks to export");
        return true; // Not an error, just nothing to do
    }

    let audio_format = match format {
        0 => AudioFormat::Wav,
        1 => AudioFormat::Flac,
        _ => AudioFormat::Wav,
    };

    let bit_depth_enum = match bit_depth {
        16 => rf_file::BitDepth::Int16,
        24 => rf_file::BitDepth::Int24,
        32 => rf_file::BitDepth::Float32,
        _ => rf_file::BitDepth::Int24,
    };

    let sample_rate = PLAYBACK.sample_rate();
    let sample_rate_u32 = sample_rate as u32;

    log::info!(
        "Starting stems export to {} (format={:?}, {}bit, {} tracks)",
        output_dir,
        audio_format,
        bit_depth,
        tracks.len()
    );

    // Set export state
    EXPORT_IN_PROGRESS.store(true, Ordering::SeqCst);
    EXPORT_CANCELLED.store(false, Ordering::SeqCst);

    {
        let mut progress = EXPORT_PROGRESS.lock();
        progress.is_exporting = true;
        progress.progress = 0.0;
        progress.phase = String::from("Exporting stems");
        progress.error = None;
    }

    // Get all clips
    let all_clips = track_manager.get_all_clips();

    // Build audio cache by loading all unique source files
    let mut audio_cache: HashMap<String, Arc<ImportedAudio>> = HashMap::new();
    for clip in &all_clips {
        if !audio_cache.contains_key(&clip.source_file) {
            match AudioImporter::import(std::path::Path::new(&clip.source_file)) {
                Ok(audio) => {
                    audio_cache.insert(clip.source_file.clone(), Arc::new(audio));
                }
                Err(e) => {
                    log::warn!("Failed to load audio '{}': {}", clip.source_file, e);
                }
            }
        }
    }

    // Calculate time range from all clips
    let (start_time, end_time) = {
        let mut min_start = f64::MAX;
        let mut max_end = 0.0_f64;
        for clip in &all_clips {
            min_start = min_start.min(clip.start_time);
            max_end = max_end.max(clip.start_time + clip.duration);
        }
        if min_start == f64::MAX {
            (0.0, 10.0) // Default if no clips
        } else {
            (min_start, max_end)
        }
    };

    let output_dir_path = PathBuf::from(&output_dir);

    // Create output directory if needed
    if let Err(e) = std::fs::create_dir_all(&output_dir_path) {
        log::error!("Failed to create output directory: {}", e);
        EXPORT_IN_PROGRESS.store(false, Ordering::SeqCst);
        return false;
    }

    // Create offline renderer for track rendering
    let offline_renderer = OfflineRenderer::new(sample_rate, 1024);

    // Export each track
    let total_tracks = tracks.len();
    for (idx, track) in tracks.iter().enumerate() {
        if EXPORT_CANCELLED.load(Ordering::SeqCst) {
            log::info!("Stems export cancelled");
            break;
        }

        // Update progress
        {
            let mut progress = EXPORT_PROGRESS.lock();
            progress.progress = idx as f32 / total_tracks as f32;
            progress.phase = format!("Exporting: {}", track.name);
        }

        // Get clips for this track
        let track_clips: Vec<_> = all_clips
            .iter()
            .filter(|c| c.track_id == track.id)
            .cloned()
            .collect();

        if track_clips.is_empty() {
            log::info!("Track '{}' has no clips, skipping", track.name);
            continue;
        }

        // Create empty insert chain for this track (or get real one if available)
        let mut insert_chain = InsertChain::new(sample_rate);

        // Render track audio
        let (output_l, output_r) = offline_renderer.render_track(
            &track_clips,
            &mut insert_chain,
            &audio_cache,
            start_time,
            end_time,
            2.0, // tail seconds
            Some(&|progress| {
                // Inner progress callback
                let mut p = EXPORT_PROGRESS.lock();
                let track_progress = idx as f32 / total_tracks as f32;
                let inner_progress = progress / total_tracks as f32;
                p.progress = track_progress + inner_progress;
            }),
        );

        // Create AudioData
        let num_frames = output_l.len();
        let audio_data = AudioData {
            channels: vec![output_l, output_r],
            sample_rate: sample_rate_u32,
            bit_depth: bit_depth_enum,
            format: audio_format,
        };

        // Sanitize track name for filename
        let safe_name: String = track
            .name
            .chars()
            .map(|c| {
                if c.is_alphanumeric() || c == '-' || c == '_' {
                    c
                } else {
                    '_'
                }
            })
            .collect();

        let ext = match audio_format {
            AudioFormat::Wav => "wav",
            AudioFormat::Flac => "flac",
            _ => "wav",
        };

        let output_path = output_dir_path.join(format!("{}_{}.{}", idx + 1, safe_name, ext));

        // Write file
        let result = match audio_format {
            AudioFormat::Wav => write_wav(&output_path, &audio_data, bit_depth_enum),
            AudioFormat::Flac => write_flac(&output_path, &audio_data, bit_depth_enum),
            _ => write_wav(&output_path, &audio_data, bit_depth_enum),
        };

        match result {
            Ok(()) => {
                log::info!(
                    "Exported stem: {} ({} samples)",
                    output_path.display(),
                    num_frames
                );
            }
            Err(e) => {
                log::error!("Failed to export stem '{}': {:?}", track.name, e);
                let mut progress = EXPORT_PROGRESS.lock();
                progress.error = Some(format!("Failed to export {}: {:?}", track.name, e));
            }
        }
    }

    // Complete
    {
        let mut progress = EXPORT_PROGRESS.lock();
        progress.is_exporting = false;
        progress.progress = 1.0;
        progress.phase = String::from("Complete");
    }
    EXPORT_IN_PROGRESS.store(false, Ordering::SeqCst);

    log::info!("Stems export complete: {} tracks", total_tracks);
    true
}

/// Validate export path
#[flutter_rust_bridge::frb(sync)]
pub fn export_validate_path(path: String) -> ExportPathValidation {
    let path_obj = Path::new(&path);

    // Check if parent directory exists
    if let Some(parent) = path_obj.parent() {
        if !parent.exists() {
            return ExportPathValidation {
                valid: false,
                error: Some(String::from("Parent directory does not exist")),
                suggested_path: None,
                will_overwrite: false,
            };
        }

        // Check write permissions
        if parent
            .metadata()
            .map(|m| m.permissions().readonly())
            .unwrap_or(true)
        {
            return ExportPathValidation {
                valid: false,
                error: Some(String::from("Directory is not writable")),
                suggested_path: None,
                will_overwrite: false,
            };
        }
    }

    // Check if file already exists
    let will_overwrite = path_obj.exists();

    // Suggest alternative if file exists
    let suggested = if will_overwrite {
        let stem = path_obj
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        let ext = path_obj
            .extension()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        let parent = path_obj
            .parent()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();

        // Find unique name
        let mut counter = 1;
        loop {
            let new_name = format!("{}/{}_{}.{}", parent, stem, counter, ext);
            if !Path::new(&new_name).exists() {
                break Some(new_name);
            }
            counter += 1;
            if counter > 100 {
                break None;
            }
        }
    } else {
        None
    };

    ExportPathValidation {
        valid: true,
        error: None,
        suggested_path: suggested,
        will_overwrite,
    }
}

/// Check if export is currently in progress
#[flutter_rust_bridge::frb(sync)]
pub fn export_is_in_progress() -> bool {
    EXPORT_IN_PROGRESS.load(Ordering::SeqCst)
}

/// Get supported export formats
#[flutter_rust_bridge::frb(sync)]
pub fn export_get_formats() -> Vec<String> {
    vec![
        String::from("WAV"),
        String::from("FLAC"),
        String::from("MP3"),
        String::from("AAC"),
        String::from("OGG"),
    ]
}

/// Get supported sample rates for export
#[flutter_rust_bridge::frb(sync)]
pub fn export_get_sample_rates() -> Vec<u32> {
    vec![44100, 48000, 88200, 96000, 176400, 192000]
}

/// Get supported bit depths for export
#[flutter_rust_bridge::frb(sync)]
pub fn export_get_bit_depths() -> Vec<u8> {
    vec![16, 24, 32]
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN SYSTEM API
// ═══════════════════════════════════════════════════════════════════════════

use once_cell::sync::Lazy;
use rf_plugin::{PluginHost, PluginInfo as RfPluginInfo, PluginType as RfPluginType};

/// Global plugin host (singleton)
static PLUGIN_HOST: Lazy<parking_lot::RwLock<PluginHost>> =
    Lazy::new(|| parking_lot::RwLock::new(PluginHost::new()));

/// Plugin info for Flutter
#[derive(Debug, Clone)]
pub struct PluginInfo {
    pub id: String,
    pub name: String,
    pub vendor: String,
    pub version: String,
    pub category: String,
    pub plugin_type: String, // "VST3", "CLAP", "AU", "Internal"
    pub path: String,
    pub is_instrument: bool,
    pub has_editor: bool,
    pub input_channels: u32,
    pub output_channels: u32,
}

impl From<&RfPluginInfo> for PluginInfo {
    fn from(info: &RfPluginInfo) -> Self {
        use rf_plugin::scanner::PluginCategory;

        let is_instrument = matches!(info.category, PluginCategory::Instrument);
        let category_str = match info.category {
            PluginCategory::Effect => "Effect",
            PluginCategory::Instrument => "Instrument",
            PluginCategory::Analyzer => "Analyzer",
            PluginCategory::Utility => "Utility",
            PluginCategory::Unknown => "Other",
        };

        Self {
            id: info.id.clone(),
            name: info.name.clone(),
            vendor: info.vendor.clone(),
            version: info.version.clone(),
            category: category_str.to_string(),
            plugin_type: format!("{:?}", info.plugin_type),
            path: info.path.to_string_lossy().to_string(),
            is_instrument,
            has_editor: info.has_editor,
            input_channels: info.audio_inputs,
            output_channels: info.audio_outputs,
        }
    }
}

/// Scan for available plugins
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_scan() -> Vec<PluginInfo> {
    let mut host = PLUGIN_HOST.write();
    match host.scan_plugins() {
        Ok(plugins) => {
            log::info!("Scanned {} plugins", plugins.len());
            plugins.iter().map(PluginInfo::from).collect()
        }
        Err(e) => {
            log::error!("Plugin scan failed: {}", e);
            Vec::new()
        }
    }
}

/// Get list of available plugins (from cache)
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_list() -> Vec<PluginInfo> {
    let host = PLUGIN_HOST.read();
    host.available_plugins()
        .iter()
        .map(PluginInfo::from)
        .collect()
}

/// Get internal (built-in) plugins
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_list_internal() -> Vec<PluginInfo> {
    let host = PLUGIN_HOST.read();
    host.available_plugins()
        .iter()
        .filter(|p| matches!(p.plugin_type, RfPluginType::Internal))
        .map(PluginInfo::from)
        .collect()
}

/// Get VST3 plugins only
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_list_vst3() -> Vec<PluginInfo> {
    let host = PLUGIN_HOST.read();
    host.available_plugins()
        .iter()
        .filter(|p| matches!(p.plugin_type, RfPluginType::Vst3))
        .map(PluginInfo::from)
        .collect()
}

/// Load a plugin instance
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_load(plugin_id: String) -> Option<String> {
    let host = PLUGIN_HOST.read();
    match host.load_plugin(&plugin_id) {
        Ok(instance_id) => {
            log::info!("Loaded plugin {}: {}", plugin_id, instance_id);
            Some(instance_id)
        }
        Err(e) => {
            log::error!("Failed to load plugin {}: {}", plugin_id, e);
            None
        }
    }
}

/// Unload a plugin instance
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_unload(instance_id: String) -> bool {
    let host = PLUGIN_HOST.read();
    match host.unload_plugin(&instance_id) {
        Ok(_) => {
            log::info!("Unloaded plugin instance: {}", instance_id);
            true
        }
        Err(e) => {
            log::error!("Failed to unload plugin {}: {}", instance_id, e);
            false
        }
    }
}

/// Get plugin parameter count
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_get_parameter_count(instance_id: String) -> u32 {
    let host = PLUGIN_HOST.read();
    if let Some(instance) = host.get_instance(&instance_id) {
        if let Some(inst) = instance.try_read() {
            return inst.parameter_count() as u32;
        }
    }
    0
}

/// Plugin parameter info for Flutter
#[derive(Debug, Clone)]
pub struct PluginParamInfo {
    pub id: u32,
    pub name: String,
    pub unit: String,
    pub min: f64,
    pub max: f64,
    pub default_value: f64,
    pub current_value: f64,
    pub is_automatable: bool,
}

/// Get plugin parameter info
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_get_parameter_info(instance_id: String, param_index: u32) -> Option<PluginParamInfo> {
    let host = PLUGIN_HOST.read();
    if let Some(instance) = host.get_instance(&instance_id) {
        if let Some(inst) = instance.try_read() {
            if let Some(info) = inst.parameter_info(param_index as usize) {
                return Some(PluginParamInfo {
                    id: info.id,
                    name: info.name,
                    unit: info.unit,
                    min: info.min,
                    max: info.max,
                    default_value: info.default,
                    current_value: info.normalized,
                    is_automatable: info.automatable,
                });
            }
        }
    }
    None
}

/// Set plugin parameter value
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_set_parameter(instance_id: String, param_id: u32, value: f64) -> bool {
    let host = PLUGIN_HOST.read();
    if let Some(instance) = host.get_instance(&instance_id) {
        if let Some(mut inst) = instance.try_write() {
            return inst.set_parameter(param_id, value).is_ok();
        }
    }
    false
}

/// Get plugin parameter value
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_get_parameter(instance_id: String, param_id: u32) -> Option<f64> {
    let host = PLUGIN_HOST.read();
    if let Some(instance) = host.get_instance(&instance_id) {
        if let Some(inst) = instance.try_read() {
            return inst.get_parameter(param_id);
        }
    }
    None
}

/// Get plugin latency in samples
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_get_latency(instance_id: String) -> u32 {
    let host = PLUGIN_HOST.read();
    if let Some(instance) = host.get_instance(&instance_id) {
        if let Some(inst) = instance.try_read() {
            return inst.latency() as u32;
        }
    }
    0
}

/// Check if plugin has editor GUI
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_has_editor(instance_id: String) -> bool {
    let host = PLUGIN_HOST.read();
    if let Some(instance) = host.get_instance(&instance_id) {
        if let Some(inst) = instance.try_read() {
            return inst.has_editor();
        }
    }
    false
}

/// Get plugin categories
#[flutter_rust_bridge::frb(sync)]
pub fn plugin_get_categories() -> Vec<String> {
    vec![
        String::from("EQ"),
        String::from("Dynamics"),
        String::from("Delay"),
        String::from("Reverb"),
        String::from("Modulation"),
        String::from("Distortion"),
        String::from("Filter"),
        String::from("Utility"),
        String::from("Instrument"),
        String::from("Other"),
    ]
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION ENGINE FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Automation target type for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutomationTarget {
    Track = 0,
    Bus = 1,
    Master = 2,
    Plugin = 3,
    Send = 4,
    Clip = 5,
}

impl From<u8> for AutomationTarget {
    fn from(v: u8) -> Self {
        match v {
            0 => AutomationTarget::Track,
            1 => AutomationTarget::Bus,
            2 => AutomationTarget::Master,
            3 => AutomationTarget::Plugin,
            4 => AutomationTarget::Send,
            5 => AutomationTarget::Clip,
            _ => AutomationTarget::Track,
        }
    }
}

/// Automation curve type for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutomationCurve {
    Linear = 0,
    Bezier = 1,
    Exponential = 2,
    Logarithmic = 3,
    Step = 4,
    SCurve = 5,
}

impl From<u8> for AutomationCurve {
    fn from(v: u8) -> Self {
        match v {
            0 => AutomationCurve::Linear,
            1 => AutomationCurve::Bezier,
            2 => AutomationCurve::Exponential,
            3 => AutomationCurve::Logarithmic,
            4 => AutomationCurve::Step,
            5 => AutomationCurve::SCurve,
            _ => AutomationCurve::Linear,
        }
    }
}

/// Automation mode for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutomationModeFFI {
    Read = 0,
    Touch = 1,
    Latch = 2,
    Write = 3,
    Trim = 4,
    Off = 5,
}

impl From<u8> for AutomationModeFFI {
    fn from(v: u8) -> Self {
        match v {
            0 => AutomationModeFFI::Read,
            1 => AutomationModeFFI::Touch,
            2 => AutomationModeFFI::Latch,
            3 => AutomationModeFFI::Write,
            4 => AutomationModeFFI::Trim,
            5 => AutomationModeFFI::Off,
            _ => AutomationModeFFI::Read,
        }
    }
}

/// Automation point for Flutter
#[derive(Debug, Clone)]
pub struct AutomationPointFFI {
    pub time_samples: u64,
    pub value: f64,
    pub curve: u8,
}

/// Automation lane info for Flutter
#[derive(Debug, Clone)]
pub struct AutomationLaneInfo {
    pub param_name: String,
    pub target_id: u64,
    pub target_type: u8,
    pub slot: Option<u32>,
    pub display_name: String,
    pub enabled: bool,
    pub visible: bool,
    pub point_count: usize,
    pub min_value: f64,
    pub max_value: f64,
    pub default_value: f64,
    pub unit: String,
}

/// Create automation lane for track volume
#[flutter_rust_bridge::frb(sync)]
pub fn automation_create_track_volume_lane(track_id: u64) -> bool {
    use rf_engine::automation::ParamId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let param_id = ParamId::track_volume(track_id);
        e.automation_engine.get_or_create_lane(param_id, "Volume");
        log::debug!("Created automation lane: Track {} Volume", track_id);
        true
    } else {
        false
    }
}

/// Create automation lane for track pan
#[flutter_rust_bridge::frb(sync)]
pub fn automation_create_track_pan_lane(track_id: u64) -> bool {
    use rf_engine::automation::ParamId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let param_id = ParamId::track_pan(track_id);
        e.automation_engine.get_or_create_lane(param_id, "Pan");
        log::debug!("Created automation lane: Track {} Pan", track_id);
        true
    } else {
        false
    }
}

/// Create automation lane for plugin parameter
#[flutter_rust_bridge::frb(sync)]
pub fn automation_create_plugin_lane(
    track_id: u64,
    slot: u32,
    param_name: String,
    display_name: String,
) -> bool {
    use rf_engine::automation::ParamId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let param_id = ParamId::plugin_param(track_id, slot, &param_name);
        e.automation_engine
            .get_or_create_lane(param_id, &display_name);
        log::debug!(
            "Created automation lane: Track {} Plugin {} {}",
            track_id,
            slot,
            param_name
        );
        true
    } else {
        false
    }
}

/// Create automation lane for send level
#[flutter_rust_bridge::frb(sync)]
pub fn automation_create_send_lane(track_id: u64, send_slot: u32) -> bool {
    use rf_engine::automation::ParamId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let param_id = ParamId::send_level(track_id, send_slot);
        let name = format!("Send {} Level", send_slot + 1);
        e.automation_engine.get_or_create_lane(param_id, &name);
        log::debug!(
            "Created automation lane: Track {} Send {}",
            track_id,
            send_slot
        );
        true
    } else {
        false
    }
}

/// Add automation point to lane
#[flutter_rust_bridge::frb(sync)]
pub fn automation_add_point(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
    time_samples: u64,
    value: f64,
    curve: u8,
) -> bool {
    use rf_engine::automation::{AutomationPoint, CurveType, ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        let curve_type = match curve {
            0 => CurveType::Linear,
            1 => CurveType::Bezier,
            2 => CurveType::Exponential,
            3 => CurveType::Logarithmic,
            4 => CurveType::Step,
            5 => CurveType::SCurve,
            _ => CurveType::Linear,
        };

        let point = AutomationPoint::new(time_samples, value).with_curve(curve_type);
        e.automation_engine.add_point(&param_id, point);
        true
    } else {
        false
    }
}

/// Remove automation point at time
#[flutter_rust_bridge::frb(sync)]
pub fn automation_remove_point(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
    time_samples: u64,
    tolerance_samples: u64,
) -> bool {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine
            .with_lane(&param_id, |lane| {
                lane.remove_point_at(time_samples, tolerance_samples)
            })
            .unwrap_or(false)
    } else {
        false
    }
}

/// Get automation value at time
#[flutter_rust_bridge::frb(sync)]
pub fn automation_get_value_at(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
    time_samples: u64,
) -> Option<f64> {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine.get_value_at(&param_id, time_samples)
    } else {
        None
    }
}

/// Get all automation points for a lane
#[flutter_rust_bridge::frb(sync)]
pub fn automation_get_points(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
) -> Vec<AutomationPointFFI> {
    use rf_engine::automation::{CurveType, ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        if let Some(lane) = e.automation_engine.lane(&param_id) {
            lane.points
                .iter()
                .map(|p| AutomationPointFFI {
                    time_samples: p.time_samples,
                    value: p.value,
                    curve: match p.curve {
                        CurveType::Linear => 0,
                        CurveType::Bezier => 1,
                        CurveType::Exponential => 2,
                        CurveType::Logarithmic => 3,
                        CurveType::Step => 4,
                        CurveType::SCurve => 5,
                    },
                })
                .collect()
        } else {
            Vec::new()
        }
    } else {
        Vec::new()
    }
}

/// Set global automation mode
#[flutter_rust_bridge::frb(sync)]
pub fn automation_set_mode(mode: u8) -> bool {
    use rf_engine::automation::AutomationMode;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let auto_mode = match mode {
            0 => AutomationMode::Read,
            1 => AutomationMode::Touch,
            2 => AutomationMode::Latch,
            3 => AutomationMode::Write,
            4 => AutomationMode::Trim,
            5 => AutomationMode::Off,
            _ => AutomationMode::Read,
        };
        e.automation_engine.set_mode(auto_mode);
        log::debug!("Automation mode set to: {:?}", auto_mode);
        true
    } else {
        false
    }
}

/// Get global automation mode
#[flutter_rust_bridge::frb(sync)]
pub fn automation_get_mode() -> u8 {
    use rf_engine::automation::AutomationMode;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        match e.automation_engine.mode() {
            AutomationMode::Read => 0,
            AutomationMode::Touch => 1,
            AutomationMode::Latch => 2,
            AutomationMode::Write => 3,
            AutomationMode::Trim => 4,
            AutomationMode::Off => 5,
        }
    } else {
        0
    }
}

/// Enable/disable automation lane
#[flutter_rust_bridge::frb(sync)]
pub fn automation_set_lane_enabled(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
    enabled: bool,
) -> bool {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine
            .with_lane(&param_id, |lane| {
                lane.enabled = enabled;
            })
            .is_some()
    } else {
        false
    }
}

/// Clear all points from automation lane
#[flutter_rust_bridge::frb(sync)]
pub fn automation_clear_lane(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
) -> bool {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine
            .with_lane(&param_id, |lane| {
                lane.clear();
            })
            .is_some()
    } else {
        false
    }
}

/// Delete automation lane
#[flutter_rust_bridge::frb(sync)]
pub fn automation_delete_lane(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
) -> bool {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine.remove_lane(&param_id);
        true
    } else {
        false
    }
}

/// Touch parameter (for Touch/Latch mode recording)
#[flutter_rust_bridge::frb(sync)]
pub fn automation_touch_param(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
    current_value: f64,
) -> bool {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine.touch_param(param_id, current_value);
        true
    } else {
        false
    }
}

/// Release parameter (for Touch mode)
#[flutter_rust_bridge::frb(sync)]
pub fn automation_release_param(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
) -> bool {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine.release_param(&param_id);
        true
    } else {
        false
    }
}

/// Record parameter change (call during playback with recording enabled)
#[flutter_rust_bridge::frb(sync)]
pub fn automation_record_change(
    track_id: u64,
    param_name: String,
    target_type: u8,
    slot: Option<u32>,
    value: f64,
) -> bool {
    use rf_engine::automation::{ParamId, TargetType};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let target = match target_type {
            0 => TargetType::Track,
            1 => TargetType::Bus,
            2 => TargetType::Master,
            3 => TargetType::Plugin,
            4 => TargetType::Send,
            5 => TargetType::Clip,
            _ => TargetType::Track,
        };

        let param_id = ParamId {
            target_id: track_id,
            target_type: target,
            param_name,
            slot,
        };

        e.automation_engine.record_change(param_id, value);
        true
    } else {
        false
    }
}

/// Enable automation recording
#[flutter_rust_bridge::frb(sync)]
pub fn automation_set_recording(enabled: bool) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.automation_engine.set_recording(enabled);
        log::debug!("Automation recording: {}", enabled);
        true
    } else {
        false
    }
}

/// List all automation lanes for a track
#[flutter_rust_bridge::frb(sync)]
pub fn automation_list_lanes(track_id: u64) -> Vec<AutomationLaneInfo> {
    use rf_engine::automation::TargetType;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.automation_engine
            .lane_ids()
            .into_iter()
            .filter(|p| p.target_id == track_id)
            .filter_map(|param_id| {
                e.automation_engine
                    .lane(&param_id)
                    .map(|lane| AutomationLaneInfo {
                        param_name: param_id.param_name.clone(),
                        target_id: param_id.target_id,
                        target_type: match param_id.target_type {
                            TargetType::Track => 0,
                            TargetType::Bus => 1,
                            TargetType::Master => 2,
                            TargetType::Plugin => 3,
                            TargetType::Send => 4,
                            TargetType::Clip => 5,
                        },
                        slot: param_id.slot,
                        display_name: lane.name.clone(),
                        enabled: lane.enabled,
                        visible: lane.visible,
                        point_count: lane.points.len(),
                        min_value: lane.min_value,
                        max_value: lane.max_value,
                        default_value: lane.default_value,
                        unit: lane.unit.clone(),
                    })
            })
            .collect()
    } else {
        Vec::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// VCA / GROUP MANAGER FFI
// ═══════════════════════════════════════════════════════════════════════════

/// VCA fader info for Flutter
#[derive(Debug, Clone)]
pub struct VcaFaderInfo {
    pub id: u64,
    pub name: String,
    pub level: f64,
    pub is_muted: bool,
    pub color: u32,
    pub track_count: usize,
}

/// Group info for Flutter
#[derive(Debug, Clone)]
pub struct GroupInfo {
    pub id: u64,
    pub name: String,
    pub color: u32,
    pub track_ids: Vec<u64>,
    pub linked_volume: bool,
    pub linked_pan: bool,
    pub linked_mute: bool,
    pub linked_solo: bool,
}

/// Create a new VCA fader
#[flutter_rust_bridge::frb(sync)]
pub fn vca_create(name: String) -> u64 {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let id = e.group_manager.write().create_vca(&name);
        log::debug!("Created VCA '{}' with id {}", name, id);
        id
    } else {
        0
    }
}

/// Delete a VCA fader
#[flutter_rust_bridge::frb(sync)]
pub fn vca_delete(vca_id: u64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager.write().delete_vca(vca_id);
        log::debug!("Deleted VCA {}", vca_id);
        true
    } else {
        false
    }
}

/// Set VCA fader level (0.0 - 1.0, or dB)
#[flutter_rust_bridge::frb(sync)]
pub fn vca_set_level(vca_id: u64, level: f64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        if let Some(vca) = e.group_manager.write().vcas.get_mut(&vca_id) {
            // Convert linear to dB if needed
            let db = if level <= 0.0 {
                -144.0
            } else {
                20.0 * level.log10()
            };
            vca.set_level(db);
        }
        true
    } else {
        false
    }
}

/// Get VCA fader level
#[flutter_rust_bridge::frb(sync)]
pub fn vca_get_level(vca_id: u64) -> f64 {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager.read().get_vca_level(vca_id).unwrap_or(1.0)
    } else {
        1.0
    }
}

/// Set VCA mute state
#[flutter_rust_bridge::frb(sync)]
pub fn vca_set_mute(vca_id: u64, muted: bool) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        if let Some(vca) = e.group_manager.write().vcas.get_mut(&vca_id) {
            vca.muted = muted;
        }
        true
    } else {
        false
    }
}

/// Assign track to VCA
#[flutter_rust_bridge::frb(sync)]
pub fn vca_assign_track(vca_id: u64, track_id: u64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager.write().add_to_vca(vca_id, track_id);
        log::debug!("Assigned track {} to VCA {}", track_id, vca_id);
        true
    } else {
        false
    }
}

/// Remove track from VCA
#[flutter_rust_bridge::frb(sync)]
pub fn vca_remove_track(vca_id: u64, track_id: u64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager.write().remove_from_vca(vca_id, track_id);
        log::debug!("Removed track {} from VCA {}", track_id, vca_id);
        true
    } else {
        false
    }
}

/// List all VCA faders
#[flutter_rust_bridge::frb(sync)]
pub fn vca_list() -> Vec<VcaFaderInfo> {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager
            .read()
            .list_vcas()
            .into_iter()
            .map(|(id, vca)| VcaFaderInfo {
                id,
                name: vca.name.clone(),
                level: vca.level,
                is_muted: vca.is_muted,
                color: vca.color,
                track_count: vca.assigned_tracks.len(),
            })
            .collect()
    } else {
        Vec::new()
    }
}

/// Get effective volume for track (includes VCA)
#[flutter_rust_bridge::frb(sync)]
pub fn vca_get_track_effective_volume(track_id: u64, base_volume: f64) -> f64 {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager
            .read()
            .get_track_effective_volume(track_id, base_volume)
    } else {
        base_volume
    }
}

/// Create a new group
#[flutter_rust_bridge::frb(sync)]
pub fn group_create(name: String) -> u64 {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let id = e.group_manager.write().create_group(&name);
        log::debug!("Created group '{}' with id {}", name, id);
        id
    } else {
        0
    }
}

/// Delete a group
#[flutter_rust_bridge::frb(sync)]
pub fn group_delete(group_id: u64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager.write().delete_group(group_id);
        log::debug!("Deleted group {}", group_id);
        true
    } else {
        false
    }
}

/// Add track to group
#[flutter_rust_bridge::frb(sync)]
pub fn group_add_track(group_id: u64, track_id: u64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager.write().add_to_group(group_id, track_id);
        log::debug!("Added track {} to group {}", track_id, group_id);
        true
    } else {
        false
    }
}

/// Remove track from group
#[flutter_rust_bridge::frb(sync)]
pub fn group_remove_track(group_id: u64, track_id: u64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager
            .write()
            .remove_from_group(group_id, track_id);
        log::debug!("Removed track {} from group {}", track_id, group_id);
        true
    } else {
        false
    }
}

/// Set group link parameters
#[flutter_rust_bridge::frb(sync)]
pub fn group_set_link(
    group_id: u64,
    link_volume: bool,
    link_pan: bool,
    link_mute: bool,
    link_solo: bool,
) -> bool {
    use rf_engine::groups::LinkParameter;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let mut gm = e.group_manager.write();
        if let Some(group) = gm.groups.get_mut(&group_id) {
            if link_volume {
                group.linked_params.insert(LinkParameter::Volume);
            }
            if link_pan {
                group.linked_params.insert(LinkParameter::Pan);
            }
            if link_mute {
                group.linked_params.insert(LinkParameter::Mute);
            }
            if link_solo {
                group.linked_params.insert(LinkParameter::Solo);
            }
        }
        true
    } else {
        false
    }
}

/// List all groups
#[flutter_rust_bridge::frb(sync)]
pub fn group_list() -> Vec<GroupInfo> {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.group_manager
            .read()
            .list_groups()
            .into_iter()
            .map(|(id, group)| GroupInfo {
                id,
                name: group.name.clone(),
                color: group.color,
                track_ids: group.tracks.clone(),
                linked_volume: group
                    .linked_params
                    .contains(&rf_engine::groups::LinkParameter::Volume),
                linked_pan: group
                    .linked_params
                    .contains(&rf_engine::groups::LinkParameter::Pan),
                linked_mute: group
                    .linked_params
                    .contains(&rf_engine::groups::LinkParameter::Mute),
                linked_solo: group
                    .linked_params
                    .contains(&rf_engine::groups::LinkParameter::Solo),
            })
            .collect()
    } else {
        Vec::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT CHAIN FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Insert slot info for Flutter
#[derive(Debug, Clone)]
pub struct InsertSlotInfo {
    pub index: usize,
    pub name: String,
    pub is_loaded: bool,
    pub is_bypassed: bool,
    pub position: u8, // 0=PreFader, 1=PostFader
    pub mix: f64,
    pub latency_samples: usize,
}

/// Load processor into insert slot
#[flutter_rust_bridge::frb(sync)]
pub fn insert_load(track_id: u32, slot_index: usize, processor_name: String) -> bool {
    use rf_engine::create_processor;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        // Create processor by name
        let sample_rate = e.config.sample_rate.as_f64();
        if let Some(processor) = create_processor(&processor_name, sample_rate) {
            // Load into track's insert chain via PlaybackEngine
            let success =
                e.playback_engine()
                    .load_track_insert(track_id as u64, slot_index, processor);
            if success {
                log::debug!(
                    "Loaded {} into track {} slot {}",
                    processor_name,
                    track_id,
                    slot_index
                );
            } else {
                log::error!(
                    "Failed to load {} into track {} slot {}",
                    processor_name,
                    track_id,
                    slot_index
                );
            }
            success
        } else {
            log::error!("Unknown processor: {}", processor_name);
            false
        }
    } else {
        false
    }
}

/// Unload processor from insert slot
#[flutter_rust_bridge::frb(sync)]
pub fn insert_unload(track_id: u32, slot_index: usize) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let result = e
            .playback_engine()
            .unload_track_insert(track_id as u64, slot_index);
        if result.is_some() {
            log::debug!(
                "Unloaded insert from track {} slot {}",
                track_id,
                slot_index
            );
            true
        } else {
            log::debug!(
                "No insert to unload from track {} slot {}",
                track_id,
                slot_index
            );
            false
        }
    } else {
        false
    }
}

/// Bypass insert slot
#[flutter_rust_bridge::frb(sync)]
pub fn insert_set_bypass(track_id: u32, slot_index: usize, bypassed: bool) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .set_track_insert_bypass(track_id as u64, slot_index, bypassed);
        log::debug!(
            "Insert bypass track {} slot {}: {}",
            track_id,
            slot_index,
            bypassed
        );
        true
    } else {
        false
    }
}

/// Set insert wet/dry mix
#[flutter_rust_bridge::frb(sync)]
pub fn insert_set_mix(track_id: u32, slot_index: usize, mix: f64) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .set_track_insert_mix(track_id as u64, slot_index, mix);
        log::debug!("Insert mix track {} slot {}: {}", track_id, slot_index, mix);
        true
    } else {
        false
    }
}

/// Set insert position (pre/post fader)
#[flutter_rust_bridge::frb(sync)]
pub fn insert_set_position(track_id: u32, slot_index: usize, position: u8) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let pre_fader = position == 0;
        e.playback_engine()
            .set_track_insert_position(track_id as u64, slot_index, pre_fader);
        let pos_str = if pre_fader { "PreFader" } else { "PostFader" };
        log::debug!(
            "Insert position track {} slot {}: {}",
            track_id,
            slot_index,
            pos_str
        );
        true
    } else {
        false
    }
}

/// List inserts for track
#[flutter_rust_bridge::frb(sync)]
pub fn insert_list(track_id: u32) -> Vec<InsertSlotInfo> {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        // Get actual insert chain state from PlaybackEngine
        e.playback_engine()
            .get_track_insert_info(track_id as u64)
            .into_iter()
            .map(
                |(index, name, is_loaded, is_bypassed, is_pre_fader, mix, latency)| {
                    InsertSlotInfo {
                        index,
                        name,
                        is_loaded,
                        is_bypassed,
                        position: if is_pre_fader { 0 } else { 1 },
                        mix,
                        latency_samples: latency,
                    }
                },
            )
            .collect()
    } else {
        Vec::new()
    }
}

/// Get total latency for track's insert chain
#[flutter_rust_bridge::frb(sync)]
pub fn insert_get_total_latency(track_id: u32) -> usize {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .get_track_insert_latency(track_id as u64)
    } else {
        0
    }
}

/// Bypass all inserts on track
#[flutter_rust_bridge::frb(sync)]
pub fn insert_bypass_all(track_id: u32, bypass: bool) -> bool {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .bypass_all_track_inserts(track_id as u64, bypass);
        log::debug!("Bypass all inserts on track {}: {}", track_id, bypass);
        true
    } else {
        false
    }
}

/// Get available processors for inserts
#[flutter_rust_bridge::frb(sync)]
pub fn insert_available_processors() -> Vec<String> {
    rf_engine::available_processors()
        .iter()
        .map(|s| s.to_string())
        .collect()
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP FX CHAIN API
// ═══════════════════════════════════════════════════════════════════════════

/// ClipFxType enum values for FFI
/// 0 = Gain, 1 = Compressor, 2 = Limiter, 3 = Gate, 4 = Saturation,
/// 5 = PitchShift, 6 = TimeStretch, 7 = ProEq, 8 = UltraEq,
/// 9 = Pultec, 10 = Api550, 11 = Neve1073, 12 = MorphEq, 13 = RoomCorrection, 14 = External
fn fx_type_from_int(value: u8) -> rf_engine::track_manager::ClipFxType {
    use rf_engine::track_manager::ClipFxType;
    match value {
        0 => ClipFxType::Gain { db: 0.0, pan: 0.0 },
        1 => ClipFxType::Compressor {
            ratio: 4.0,
            threshold_db: -18.0,
            attack_ms: 10.0,
            release_ms: 100.0,
        },
        2 => ClipFxType::Limiter { ceiling_db: -0.3 },
        3 => ClipFxType::Gate {
            threshold_db: -40.0,
            attack_ms: 1.0,
            release_ms: 50.0,
        },
        4 => ClipFxType::Saturation {
            drive: 0.5,
            mix: 1.0,
        },
        5 => ClipFxType::PitchShift {
            semitones: 0.0,
            cents: 0.0,
        },
        6 => ClipFxType::TimeStretch { ratio: 1.0 },
        7 => ClipFxType::ProEq { bands: 8 },
        8 => ClipFxType::UltraEq,
        9 => ClipFxType::Pultec,
        10 => ClipFxType::Api550,
        11 => ClipFxType::Neve1073,
        12 => ClipFxType::MorphEq,
        13 => ClipFxType::RoomCorrection,
        14 => ClipFxType::External {
            plugin_id: String::new(),
            state: None,
        },
        _ => ClipFxType::Gain { db: 0.0, pan: 0.0 },
    }
}

/// Add FX slot to clip FX chain
/// Returns slot ID or 0 on failure
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_add(clip_id: u64, fx_type: u8) -> u64 {
    use rf_engine::track_manager::ClipId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let fx = fx_type_from_int(fx_type);
        if let Some(slot_id) = e.track_manager().add_clip_fx(ClipId(clip_id), fx) {
            log::debug!("Added clip FX to clip {}: slot {}", clip_id, slot_id.0);
            return slot_id.0;
        }
    }
    0
}

/// Remove FX slot from clip
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_remove(clip_id: u64, slot_id: u64) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let result = e
            .track_manager()
            .remove_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id));
        log::debug!(
            "Removed clip FX slot {} from clip {}: {}",
            slot_id,
            clip_id,
            result
        );
        result
    } else {
        false
    }
}

/// Move FX slot to new position in chain
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_move(clip_id: u64, slot_id: u64, new_index: usize) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        let result =
            e.track_manager()
                .move_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), new_index);
        log::debug!(
            "Moved clip FX slot {} to index {}: {}",
            slot_id,
            new_index,
            result
        );
        result
    } else {
        false
    }
}

/// Set FX slot bypass state
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_bypass(clip_id: u64, slot_id: u64, bypass: bool) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .set_clip_fx_bypass(ClipId(clip_id), ClipFxSlotId(slot_id), bypass)
    } else {
        false
    }
}

/// Set entire FX chain bypass state
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_chain_bypass(clip_id: u64, bypass: bool) -> bool {
    use rf_engine::track_manager::ClipId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .set_clip_fx_chain_bypass(ClipId(clip_id), bypass)
    } else {
        false
    }
}

/// Set FX slot wet/dry mix (0.0 = dry, 1.0 = wet)
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_wet_dry(clip_id: u64, slot_id: u64, wet_dry: f64) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
                slot.wet_dry = wet_dry.clamp(0.0, 1.0);
            })
    } else {
        false
    }
}

/// Set clip FX chain input gain (dB)
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_input_gain(clip_id: u64, gain_db: f64) -> bool {
    use rf_engine::track_manager::ClipId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .set_clip_fx_input_gain(ClipId(clip_id), gain_db)
    } else {
        false
    }
}

/// Set clip FX chain output gain (dB)
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_output_gain(clip_id: u64, gain_db: f64) -> bool {
    use rf_engine::track_manager::ClipId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .set_clip_fx_output_gain(ClipId(clip_id), gain_db)
    } else {
        false
    }
}

/// Set Gain FX parameters
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_gain_params(clip_id: u64, slot_id: u64, db: f64, pan: f64) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipFxType, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
                slot.fx_type = ClipFxType::Gain {
                    db,
                    pan: pan.clamp(-1.0, 1.0),
                };
            })
    } else {
        false
    }
}

/// Set Compressor FX parameters
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_compressor_params(
    clip_id: u64,
    slot_id: u64,
    ratio: f64,
    threshold_db: f64,
    attack_ms: f64,
    release_ms: f64,
) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipFxType, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
                slot.fx_type = ClipFxType::Compressor {
                    ratio: ratio.clamp(1.0, 100.0),
                    threshold_db: threshold_db.clamp(-60.0, 0.0),
                    attack_ms: attack_ms.clamp(0.01, 500.0),
                    release_ms: release_ms.clamp(1.0, 5000.0),
                };
            })
    } else {
        false
    }
}

/// Set Limiter FX parameters
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_limiter_params(clip_id: u64, slot_id: u64, ceiling_db: f64) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipFxType, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
                slot.fx_type = ClipFxType::Limiter {
                    ceiling_db: ceiling_db.clamp(-30.0, 0.0),
                };
            })
    } else {
        false
    }
}

/// Set Gate FX parameters
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_gate_params(
    clip_id: u64,
    slot_id: u64,
    threshold_db: f64,
    attack_ms: f64,
    release_ms: f64,
) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipFxType, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
                slot.fx_type = ClipFxType::Gate {
                    threshold_db: threshold_db.clamp(-80.0, 0.0),
                    attack_ms: attack_ms.clamp(0.01, 100.0),
                    release_ms: release_ms.clamp(1.0, 2000.0),
                };
            })
    } else {
        false
    }
}

/// Set Saturation FX parameters
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_set_saturation_params(clip_id: u64, slot_id: u64, drive: f64, mix: f64) -> bool {
    use rf_engine::track_manager::{ClipFxSlotId, ClipFxType, ClipId};

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
                slot.fx_type = ClipFxType::Saturation {
                    drive: drive.clamp(0.0, 1.0),
                    mix: mix.clamp(0.0, 1.0),
                };
            })
    } else {
        false
    }
}

/// Copy FX chain from one clip to another
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_copy(source_clip_id: u64, target_clip_id: u64) -> bool {
    use rf_engine::track_manager::ClipId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager()
            .copy_clip_fx(ClipId(source_clip_id), ClipId(target_clip_id))
    } else {
        false
    }
}

/// Clear all FX from clip
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_clear(clip_id: u64) -> bool {
    use rf_engine::track_manager::ClipId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.track_manager().clear_clip_fx(ClipId(clip_id))
    } else {
        false
    }
}

/// Get clip FX chain info
/// Returns: (bypass, input_gain_db, output_gain_db, slot_count)
#[flutter_rust_bridge::frb(sync)]
pub fn clip_fx_get_chain_info(clip_id: u64) -> Option<(bool, f64, f64, usize)> {
    use rf_engine::track_manager::ClipId;

    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        if let Some(chain) = e.track_manager().get_clip_fx_chain(ClipId(clip_id)) {
            return Some((
                chain.bypass,
                chain.input_gain_db,
                chain.output_gain_db,
                chain.slots.len(),
            ));
        }
    }
    None
}

// Note: Saturation FFI functions are defined in rf-engine/src/ffi.rs
// and exposed via C FFI for NativeFFI Dart bindings

// ═══════════════════════════════════════════════════════════════════════════
// ML PROCESSOR (rf-ml)
// ═══════════════════════════════════════════════════════════════════════════

/// ML Processor state for Flutter
#[derive(Debug, Clone)]
pub struct MlProcessorState {
    pub is_active: bool,
    pub processor_type: String,
    pub progress: f32,
    pub status: String,
}

/// Stem separation result
#[derive(Debug, Clone)]
pub struct StemSeparationResult {
    pub vocals_path: String,
    pub drums_path: String,
    pub bass_path: String,
    pub other_path: String,
    pub success: bool,
    pub error_message: String,
}

/// Denoise settings
#[derive(Debug, Clone)]
pub struct DenoiseSettings {
    pub strength: f32,
    pub preserve_voice: bool,
    pub adaptive: bool,
}

impl Default for DenoiseSettings {
    fn default() -> Self {
        Self {
            strength: 0.5,
            preserve_voice: true,
            adaptive: true,
        }
    }
}

/// Start stem separation process
#[flutter_rust_bridge::frb(sync)]
pub fn ml_stem_separation_start(
    input_path: String,
    output_dir: String,
    _model_type: String,
) -> bool {
    // Validate input exists
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    // Create output directory if needed
    let _ = std::fs::create_dir_all(&output_dir);

    // In production, this would spawn an async task using rf-ml
    // For now, return true to indicate the request was accepted
    true
}

/// Get stem separation progress (0.0 - 1.0)
#[flutter_rust_bridge::frb(sync)]
pub fn ml_stem_separation_progress() -> f32 {
    // Would query the actual separation task
    0.0
}

/// Cancel stem separation
#[flutter_rust_bridge::frb(sync)]
pub fn ml_stem_separation_cancel() -> bool {
    true
}

/// Apply ML denoising to audio file
#[flutter_rust_bridge::frb(sync)]
pub fn ml_denoise_file(
    input_path: String,
    _output_path: String,
    _strength: f32,
    _preserve_voice: bool,
) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    // Would use rf-ml denoise module
    true
}

/// Get available ML models (basic list)
#[flutter_rust_bridge::frb(sync)]
pub fn ml_get_available_models_basic() -> Vec<String> {
    vec![
        "htdemucs".to_string(),
        "htdemucs_ft".to_string(),
        "demucs".to_string(),
        "mdx".to_string(),
        "deep_filter".to_string(),
        "frcrn".to_string(),
    ]
}

/// Check if ML model is downloaded/available
#[flutter_rust_bridge::frb(sync)]
pub fn ml_model_is_available(model_name: String) -> bool {
    // Would check local model cache
    match model_name.as_str() {
        "htdemucs" | "deep_filter" => true,
        _ => false,
    }
}

/// Download ML model
#[flutter_rust_bridge::frb(sync)]
pub fn ml_model_download(_model_name: String) -> bool {
    // Would trigger async download
    true
}

/// Get ML processor state
#[flutter_rust_bridge::frb(sync)]
pub fn ml_get_processor_state() -> MlProcessorState {
    MlProcessorState {
        is_active: false,
        processor_type: "none".to_string(),
        progress: 0.0,
        status: "idle".to_string(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MASTERING ENGINE (rf-master)
// ═══════════════════════════════════════════════════════════════════════════

/// Mastering preset info
#[derive(Debug, Clone)]
pub struct MasteringPresetInfo {
    pub id: String,
    pub name: String,
    pub genre: String,
    pub target_lufs: f32,
    pub description: String,
}

/// Mastering analysis result
#[derive(Debug, Clone)]
pub struct MasteringAnalysis {
    pub lufs_integrated: f32,
    pub lufs_range: f32,
    pub true_peak: f32,
    pub dynamic_range: f32,
    pub stereo_width: f32,
    pub spectral_balance: String,
    pub suggested_genre: String,
    pub issues: Vec<String>,
}

/// Mastering settings
#[derive(Debug, Clone)]
pub struct MasteringSettings {
    pub target_lufs: f32,
    pub true_peak_limit: f32,
    pub stereo_width: f32,
    pub low_cut_freq: f32,
    pub multiband_enabled: bool,
    pub limiter_enabled: bool,
    pub eq_enabled: bool,
    pub auto_gain: bool,
}

impl Default for MasteringSettings {
    fn default() -> Self {
        Self {
            target_lufs: -14.0,
            true_peak_limit: -1.0,
            stereo_width: 1.0,
            low_cut_freq: 30.0,
            multiband_enabled: true,
            limiter_enabled: true,
            eq_enabled: true,
            auto_gain: true,
        }
    }
}

/// Get available mastering presets
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_get_presets() -> Vec<MasteringPresetInfo> {
    vec![
        MasteringPresetInfo {
            id: "streaming".to_string(),
            name: "Streaming".to_string(),
            genre: "General".to_string(),
            target_lufs: -14.0,
            description: "Optimized for Spotify, Apple Music, YouTube".to_string(),
        },
        MasteringPresetInfo {
            id: "cd".to_string(),
            name: "CD Master".to_string(),
            genre: "General".to_string(),
            target_lufs: -9.0,
            description: "Traditional CD mastering levels".to_string(),
        },
        MasteringPresetInfo {
            id: "broadcast".to_string(),
            name: "Broadcast".to_string(),
            genre: "General".to_string(),
            target_lufs: -24.0,
            description: "EBU R128 broadcast compliant".to_string(),
        },
        MasteringPresetInfo {
            id: "podcast".to_string(),
            name: "Podcast".to_string(),
            genre: "Voice".to_string(),
            target_lufs: -16.0,
            description: "Optimized for spoken word content".to_string(),
        },
        MasteringPresetInfo {
            id: "edm".to_string(),
            name: "EDM".to_string(),
            genre: "Electronic".to_string(),
            target_lufs: -8.0,
            description: "Loud and punchy for electronic music".to_string(),
        },
        MasteringPresetInfo {
            id: "classical".to_string(),
            name: "Classical".to_string(),
            genre: "Classical".to_string(),
            target_lufs: -18.0,
            description: "Preserve dynamics for orchestral music".to_string(),
        },
        MasteringPresetInfo {
            id: "hiphop".to_string(),
            name: "Hip-Hop".to_string(),
            genre: "Hip-Hop".to_string(),
            target_lufs: -10.0,
            description: "Heavy low-end, punchy drums".to_string(),
        },
        MasteringPresetInfo {
            id: "rock".to_string(),
            name: "Rock".to_string(),
            genre: "Rock".to_string(),
            target_lufs: -11.0,
            description: "Balanced with emphasis on guitars".to_string(),
        },
    ]
}

/// Analyze audio for mastering
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_analyze(input_path: String) -> Option<MasteringAnalysis> {
    if !std::path::Path::new(&input_path).exists() {
        return None;
    }

    // Would use rf-master analysis module
    Some(MasteringAnalysis {
        lufs_integrated: -18.5,
        lufs_range: 8.2,
        true_peak: -0.3,
        dynamic_range: 12.5,
        stereo_width: 0.85,
        spectral_balance: "balanced".to_string(),
        suggested_genre: "Rock".to_string(),
        issues: vec![
            "True peak exceeds -1.0 dBTP".to_string(),
            "Consider reducing high frequency harshness".to_string(),
        ],
    })
}

/// Apply mastering preset
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_apply_preset(_preset_id: String) -> bool {
    // Would configure rf-master with preset
    true
}

/// Set mastering settings
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_set_settings(
    _target_lufs: f32,
    _true_peak_limit: f32,
    _stereo_width: f32,
    _multiband_enabled: bool,
    _limiter_enabled: bool,
) -> bool {
    // Would configure rf-master
    true
}

/// Get current mastering settings
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_get_settings() -> MasteringSettings {
    MasteringSettings::default()
}

/// Process file through mastering chain
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_process_file(
    input_path: String,
    _output_path: String,
    _preset_id: String,
) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    // Would use rf-master chain
    true
}

/// Enable/disable mastering on master bus
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_set_enabled(_enabled: bool) -> bool {
    // Would toggle rf-master on master bus
    true
}

/// Get mastering enabled state
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_is_enabled() -> bool {
    false
}

/// Match reference track
#[flutter_rust_bridge::frb(sync)]
pub fn mastering_match_reference(reference_path: String) -> bool {
    if !std::path::Path::new(&reference_path).exists() {
        return false;
    }

    // Would use rf-master reference matching
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO RESTORATION (rf-restore)
// ═══════════════════════════════════════════════════════════════════════════

/// Restoration module type
#[derive(Debug, Clone, PartialEq)]
pub enum RestorationType {
    Denoise,
    Declick,
    Declip,
    Dehum,
    Dereverb,
}

/// Restoration settings
#[derive(Debug, Clone)]
pub struct RestorationSettings {
    pub denoise_enabled: bool,
    pub denoise_strength: f32,
    pub declick_enabled: bool,
    pub declick_sensitivity: f32,
    pub declip_enabled: bool,
    pub declip_threshold: f32,
    pub dehum_enabled: bool,
    pub dehum_frequency: f32,
    pub dereverb_enabled: bool,
    pub dereverb_amount: f32,
}

impl Default for RestorationSettings {
    fn default() -> Self {
        Self {
            denoise_enabled: false,
            denoise_strength: 0.5,
            declick_enabled: false,
            declick_sensitivity: 0.5,
            declip_enabled: false,
            declip_threshold: 0.9,
            dehum_enabled: false,
            dehum_frequency: 50.0,
            dereverb_enabled: false,
            dereverb_amount: 0.5,
        }
    }
}

/// Restoration analysis result
#[derive(Debug, Clone)]
pub struct RestorationAnalysis {
    pub noise_floor_db: f32,
    pub click_count: u32,
    pub clip_percentage: f32,
    pub hum_detected: bool,
    pub hum_frequency: f32,
    pub reverb_amount: f32,
    pub overall_quality: f32,
    pub recommendations: Vec<String>,
}

/// Analyze audio for restoration needs
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_analyze(input_path: String) -> Option<RestorationAnalysis> {
    if !std::path::Path::new(&input_path).exists() {
        return None;
    }

    // Would use rf-restore analysis
    Some(RestorationAnalysis {
        noise_floor_db: -55.0,
        click_count: 12,
        clip_percentage: 0.02,
        hum_detected: true,
        hum_frequency: 50.0,
        reverb_amount: 0.3,
        overall_quality: 0.75,
        recommendations: vec![
            "Apply denoise to reduce background noise".to_string(),
            "Use declick to remove 12 detected clicks".to_string(),
            "Enable dehum at 50Hz".to_string(),
        ],
    })
}

/// Set restoration settings
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_set_settings(
    _denoise_enabled: bool,
    _denoise_strength: f32,
    _declick_enabled: bool,
    _declick_sensitivity: f32,
    _declip_enabled: bool,
    _dehum_enabled: bool,
    _dehum_frequency: f32,
    _dereverb_enabled: bool,
    _dereverb_amount: f32,
) -> bool {
    // Would configure rf-restore
    true
}

/// Get current restoration settings
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_get_settings() -> RestorationSettings {
    RestorationSettings::default()
}

/// Process file through restoration chain
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_process_file(input_path: String, _output_path: String) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    // Would use rf-restore pipeline
    true
}

/// Learn noise profile from selection
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_learn_noise_profile(
    input_path: String,
    _start_sample: u64,
    _end_sample: u64,
) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    // Would use rf-restore denoise module
    true
}

/// Clear learned noise profile
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_clear_noise_profile() -> bool {
    true
}

/// Enable/disable restoration on track
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_set_enabled_for_track(_track_id: u32, _enabled: bool) -> bool {
    // Would toggle rf-restore on track
    true
}

/// Get restoration processing state
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_get_processing_state() -> (bool, f32, String) {
    (false, 0.0, "idle".to_string())
}

/// Auto-detect and fix issues
#[flutter_rust_bridge::frb(sync)]
pub fn restoration_auto_fix(input_path: String, _output_path: String) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    // Would analyze and apply appropriate restoration
    true
}

// =============================================================================
// ML/AI PROCESSING (rf-ml)
// =============================================================================

/// ML execution providers
#[derive(Debug, Clone)]
pub enum MlExecutionProvider {
    /// Pure CPU execution
    Cpu,
    /// CUDA GPU acceleration
    Cuda,
    /// Apple CoreML
    CoreMl,
    /// TensorRT optimization
    TensorRt,
}

/// AI-powered denoising types
#[derive(Debug, Clone)]
pub enum DenoiseModel {
    /// DeepFilterNet3 - balanced quality/speed
    DeepFilterNet,
    /// FRCRN - maximum quality
    Frcrn,
    /// aTENNuate - ultra-low latency speech
    Atennuate,
}

/// Stem separation output types
#[derive(Debug, Clone)]
pub enum StemType {
    Vocals,
    Drums,
    Bass,
    Other,
    Piano,
    Guitar,
}

/// Start AI denoising on audio
#[flutter_rust_bridge::frb(sync)]
pub fn ml_denoise_start(
    input_path: String,
    _output_path: String,
    model: DenoiseModel,
    strength: f32,
) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    // Would initialize rf-ml denoising processor
    log::info!("Starting ML denoise: {:?}, strength: {}", model, strength);
    true
}

/// Get denoising progress (0.0 - 1.0)
#[flutter_rust_bridge::frb(sync)]
pub fn ml_denoise_progress() -> f32 {
    // Would return actual progress from rf-ml
    0.0
}

/// Cancel denoising
#[flutter_rust_bridge::frb(sync)]
pub fn ml_denoise_cancel() -> bool {
    true
}

/// Start stem separation
#[flutter_rust_bridge::frb(sync)]
pub fn ml_separate_stems(input_path: String, _output_dir: String, stems: Vec<StemType>) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    log::info!("Starting stem separation: {} stems", stems.len());
    true
}

/// Get stem separation progress
#[flutter_rust_bridge::frb(sync)]
pub fn ml_separation_progress() -> (f32, String) {
    // Returns (progress 0-1, current_stem_name)
    (0.0, "".to_string())
}

/// AI mastering preset
#[derive(Debug, Clone)]
pub struct MasteringPreset {
    pub name: String,
    pub target_lufs: f32,
    pub genre: String,
    pub reference_path: Option<String>,
}

/// Start AI mastering
#[flutter_rust_bridge::frb(sync)]
pub fn ml_master_start(input_path: String, _output_path: String, preset: MasteringPreset) -> bool {
    if !std::path::Path::new(&input_path).exists() {
        return false;
    }

    log::info!("Starting AI mastering with preset: {}", preset.name);
    true
}

/// Get mastering suggestions based on analysis
#[flutter_rust_bridge::frb(sync)]
pub fn ml_get_mastering_suggestions(input_path: String) -> Vec<String> {
    if !std::path::Path::new(&input_path).exists() {
        return vec![];
    }

    // Would analyze audio and return suggestions
    vec![
        "Add +2dB high shelf at 12kHz for air".to_string(),
        "Consider multiband compression on low end".to_string(),
        "Target LUFS: -14 for streaming".to_string(),
    ]
}

/// EQ match between reference and target
#[flutter_rust_bridge::frb(sync)]
pub fn ml_eq_match(
    target_path: String,
    reference_path: String,
    _output_path: String,
    match_amount: f32,
) -> bool {
    if !std::path::Path::new(&target_path).exists()
        || !std::path::Path::new(&reference_path).exists()
    {
        return false;
    }

    log::info!("EQ matching with amount: {}", match_amount);
    true
}

/// Get available ML models and their status
#[flutter_rust_bridge::frb(sync)]
pub fn ml_get_available_models() -> Vec<(String, bool, String)> {
    // Returns: (model_name, is_available, required_memory_mb)
    vec![
        ("DeepFilterNet3".to_string(), true, "200MB".to_string()),
        ("HTDemucs v4".to_string(), true, "1.5GB".to_string()),
        ("aTENNuate SSM".to_string(), true, "150MB".to_string()),
        ("Genre Classifier".to_string(), true, "50MB".to_string()),
    ]
}

/// Set ML execution provider
#[flutter_rust_bridge::frb(sync)]
pub fn ml_set_execution_provider(provider: MlExecutionProvider) -> bool {
    log::info!("Setting ML execution provider: {:?}", provider);
    true
}

// =============================================================================
// SPATIAL AUDIO (rf-spatial)
// =============================================================================

/// Speaker layout types
#[derive(Debug, Clone)]
pub enum SpeakerLayoutType {
    Stereo,
    Surround5_1,
    Surround7_1,
    Atmos7_1_4,
    Atmos9_1_6,
    Binaural,
    Custom,
}

/// 3D position for spatial audio
#[derive(Debug, Clone, Default)]
pub struct SpatialPosition3D {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// Audio object for Atmos/spatial
#[derive(Debug, Clone)]
pub struct SpatialObject {
    pub id: u32,
    pub name: String,
    pub position: SpatialPosition3D,
    pub size: f32,
    pub gain: f32,
}

/// Set output speaker layout
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_set_output_layout(layout: SpeakerLayoutType) -> bool {
    log::info!("Setting spatial output layout: {:?}", layout);
    true
}

/// Get current speaker layout channel count
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_get_channel_count() -> u32 {
    // Would return from rf-spatial
    2 // Default stereo
}

/// Create Atmos audio object
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_create_object(name: String, position: SpatialPosition3D) -> u32 {
    // Would create object in rf-spatial Atmos renderer
    log::info!(
        "Creating spatial object: {} at ({}, {}, {})",
        name,
        position.x,
        position.y,
        position.z
    );
    0 // Return object ID
}

/// Update object position
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_update_object_position(_object_id: u32, _position: SpatialPosition3D) -> bool {
    true
}

/// Update object size/spread
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_update_object_size(_object_id: u32, _size: f32) -> bool {
    true
}

/// Remove object
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_remove_object(_object_id: u32) -> bool {
    true
}

/// Get all objects
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_get_objects() -> Vec<SpatialObject> {
    vec![]
}

/// Enable binaural rendering
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_enable_binaural(enabled: bool) -> bool {
    log::info!(
        "Binaural rendering: {}",
        if enabled { "enabled" } else { "disabled" }
    );
    true
}

/// Load HRTF (SOFA format)
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_load_hrtf(path: String) -> bool {
    if !std::path::Path::new(&path).exists() {
        return false;
    }
    log::info!("Loading HRTF: {}", path);
    true
}

/// Set listener head position (for binaural)
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_set_listener_position(
    _position: SpatialPosition3D,
    _yaw: f32,
    _pitch: f32,
    _roll: f32,
) -> bool {
    true
}

/// Enable head tracking
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_enable_head_tracking(enabled: bool) -> bool {
    log::info!(
        "Head tracking: {}",
        if enabled { "enabled" } else { "disabled" }
    );
    true
}

/// HOA (Higher-Order Ambisonics) order setting
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_set_hoa_order(order: u32) -> bool {
    if order > 7 {
        return false;
    }
    log::info!("Setting HOA order: {}", order);
    true
}

/// Export to Atmos ADM BWF
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_export_atmos(
    output_path: String,
    _include_beds: bool,
    _include_objects: bool,
) -> bool {
    log::info!("Exporting Atmos ADM to: {}", output_path);
    true
}

/// Get renderer latency in samples
#[flutter_rust_bridge::frb(sync)]
pub fn spatial_get_latency_samples() -> u32 {
    256 // Default
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT CHAIN FFI (C-compatible exports for native_ffi.dart)
// ═══════════════════════════════════════════════════════════════════════════

/// C FFI: Create insert chain for track (currently no-op as chains auto-create)
#[unsafe(no_mangle)]
pub extern "C" fn insert_create_chain(_track_id: u64) {
    // Insert chains are created automatically when first processor is loaded
    // This is a no-op for compatibility
}

/// C FFI: Remove insert chain from track
#[unsafe(no_mangle)]
pub extern "C" fn insert_remove_chain(track_id: u64) {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        // Unload all slots for this track
        for slot in 0..8 {
            let _ = e.playback_engine().unload_track_insert(track_id, slot);
        }
    }
}

/// C FFI: Set insert slot bypass (wraps flutter_rust_bridge version)
#[unsafe(no_mangle)]
pub extern "C" fn ffi_insert_set_bypass(track_id: u64, slot: u32, bypass: i32) {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .set_track_insert_bypass(track_id, slot as usize, bypass != 0);
    }
}

/// C FFI: Set insert slot wet/dry mix (wraps flutter_rust_bridge version)
#[unsafe(no_mangle)]
pub extern "C" fn ffi_insert_set_mix(track_id: u64, slot: u32, mix: f64) {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .set_track_insert_mix(track_id, slot as usize, mix);
    }
}

/// C FFI: Get insert slot wet/dry mix (0.0 = dry, 1.0 = wet)
#[unsafe(no_mangle)]
pub extern "C" fn ffi_insert_get_mix(track_id: u64, slot: u32) -> f64 {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .get_track_insert_mix(track_id, slot as usize)
    } else {
        1.0 // Default full wet
    }
}

/// C FFI: Bypass all inserts on track (wraps flutter_rust_bridge version)
#[unsafe(no_mangle)]
pub extern "C" fn ffi_insert_bypass_all(track_id: u64, bypass: i32) {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine()
            .bypass_all_track_inserts(track_id, bypass != 0);
    }
}

/// C FFI: Get total latency of insert chain (samples)
#[unsafe(no_mangle)]
pub extern "C" fn ffi_insert_get_total_latency(track_id: u64) -> u32 {
    let engine = ENGINE.read();
    if let Some(ref e) = *engine {
        e.playback_engine().get_track_insert_latency(track_id) as u32
    } else {
        0
    }
}

// NOTE: insert_load_processor, insert_unload_slot, insert_set_param,
// insert_get_param, and insert_is_loaded are defined in rf-engine/src/ffi.rs
// They support both master bus (track_id=0) and audio tracks, so we use those.

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO FILE INFO & WAVEFORM EXTRACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Audio file information DTO
#[derive(Debug, Clone)]
pub struct AudioFileInfoDto {
    /// File format (wav, mp3, flac, ogg, aac)
    pub format: String,
    /// Number of channels
    pub channels: u16,
    /// Sample rate in Hz
    pub sample_rate: u32,
    /// Bit depth (8, 16, 24, 32)
    pub bit_depth: u32,
    /// Total number of sample frames
    pub num_frames: u64,
    /// Duration in seconds
    pub duration_seconds: f64,
    /// File size in bytes
    pub file_size: u64,
}

/// Waveform extraction result DTO
#[derive(Debug, Clone)]
pub struct WaveformDataDto {
    /// Waveform peak values (0.0 to 1.0)
    pub peaks: Vec<f32>,
    /// Duration in seconds
    pub duration_seconds: f64,
    /// Sample rate of original file
    pub sample_rate: u32,
    /// Number of channels
    pub channels: u16,
}

/// Get audio file information without fully decoding
/// Supports: WAV, MP3, FLAC, OGG, AAC/M4A
#[flutter_rust_bridge::frb(sync)]
pub fn audio_file_get_info(file_path: String) -> Option<AudioFileInfoDto> {
    use rf_file::{get_audio_info, AudioFormat};

    let path = Path::new(&file_path);
    match get_audio_info(path) {
        Ok(info) => Some(AudioFileInfoDto {
            format: match info.format {
                AudioFormat::Wav => "wav".to_string(),
                AudioFormat::Mp3 => "mp3".to_string(),
                AudioFormat::Flac => "flac".to_string(),
                AudioFormat::Ogg => "ogg".to_string(),
                AudioFormat::Aac => "aac".to_string(),
                AudioFormat::Unknown => "unknown".to_string(),
            },
            channels: info.channels,
            sample_rate: info.sample_rate,
            bit_depth: info.bit_depth.bits(),
            num_frames: info.num_frames,
            duration_seconds: info.duration,
            file_size: info.file_size,
        }),
        Err(e) => {
            log::warn!("Failed to get audio file info for {}: {}", file_path, e);
            None
        }
    }
}

/// Extract waveform peaks from audio file
/// Supports: WAV, MP3, FLAC, OGG, AAC/M4A
/// Returns normalized peak values (0.0 to 1.0) for visualization
#[flutter_rust_bridge::frb(sync)]
pub fn audio_file_extract_waveform(file_path: String, num_peaks: u32) -> Option<WaveformDataDto> {
    use rf_file::read_audio;

    let path = Path::new(&file_path);
    match read_audio(path) {
        Ok(audio_data) => {
            let num_frames = audio_data.num_frames();
            let num_channels = audio_data.num_channels();
            let sample_rate = audio_data.sample_rate;
            let duration_seconds = audio_data.duration();

            if num_frames == 0 {
                return None;
            }

            // Calculate samples per peak
            let target_peaks = num_peaks.max(10).min(2000) as usize;
            let samples_per_peak = (num_frames / target_peaks).max(1);

            let mut peaks = Vec::with_capacity(target_peaks);
            let mut max_peak = 0.0f64;

            // Extract peak values (max absolute sample in each window)
            for peak_idx in 0..target_peaks {
                let start = peak_idx * samples_per_peak;
                let end = ((peak_idx + 1) * samples_per_peak).min(num_frames);

                if start >= num_frames {
                    break;
                }

                let mut peak_value = 0.0f64;

                // Get max across all channels for this window
                for frame in start..end {
                    for ch in 0..num_channels {
                        let sample = audio_data.channels[ch][frame].abs();
                        if sample > peak_value {
                            peak_value = sample;
                        }
                    }
                }

                peaks.push(peak_value);
                if peak_value > max_peak {
                    max_peak = peak_value;
                }
            }

            // Normalize to 0.0-1.0
            let normalized_peaks: Vec<f32> = if max_peak > 0.0 {
                peaks.iter().map(|&p| (p / max_peak) as f32).collect()
            } else {
                peaks.iter().map(|_| 0.0f32).collect()
            };

            log::debug!(
                "Extracted {} waveform peaks from {} ({:.2}s, {} ch, {} Hz)",
                normalized_peaks.len(),
                file_path,
                duration_seconds,
                num_channels,
                sample_rate
            );

            Some(WaveformDataDto {
                peaks: normalized_peaks,
                duration_seconds,
                sample_rate,
                channels: num_channels as u16,
            })
        }
        Err(e) => {
            log::warn!("Failed to extract waveform from {}: {}", file_path, e);
            None
        }
    }
}

/// Get audio file duration only (faster than full waveform extraction)
/// Supports: WAV, MP3, FLAC, OGG, AAC/M4A
#[flutter_rust_bridge::frb(sync)]
pub fn audio_file_get_duration(file_path: String) -> Option<f64> {
    use rf_file::get_audio_info;

    let path = Path::new(&file_path);
    match get_audio_info(path) {
        Ok(info) => Some(info.duration),
        Err(e) => {
            log::warn!("Failed to get audio duration for {}: {}", file_path, e);
            None
        }
    }
}

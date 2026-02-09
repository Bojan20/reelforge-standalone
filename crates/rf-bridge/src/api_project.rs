//! Project API functions
//!
//! Extracted from api.rs as part of modular FFI decomposition.
//! Handles project management: new, save, load, metadata, recent projects.

use crate::{ENGINE, EngineBridge};
use std::path::Path;

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

    // Use actual session sample rate from engine config
    let sample_rate = e.config.sample_rate.as_u32() as u64;

    e.project.tracks = tracks
        .iter()
        .map(|track| {
            // Convert clips for this track
            let regions: Vec<RegionState> = all_clips
                .iter()
                .filter(|c| c.track_id == track.id)
                .map(|clip| RegionState {
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

    // Use actual session sample rate from engine config
    let sample_rate = e.config.sample_rate.as_f64();

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

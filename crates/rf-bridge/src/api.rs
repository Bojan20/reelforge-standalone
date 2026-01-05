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
    (crate::PLAYBACK.meters.get_peak_l(), crate::PLAYBACK.meters.get_peak_r())
}

/// Get RMS meters (L, R)
#[flutter_rust_bridge::frb(sync)]
pub fn playback_get_rms() -> (f32, f32) {
    (crate::PLAYBACK.meters.get_rms_l(), crate::PLAYBACK.meters.get_rms_r())
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
    pub slope: u8,       // For cut filters: 0=6dB, 1=12dB, 2=18dB, 3=24dB, 4=36dB, 5=48dB, 6=72dB, 7=96dB
    pub stereo_mode: u8, // 0=Stereo, 1=Left, 2=Right, 3=Mid, 4=Side
}

/// Set EQ band parameters for a track
#[flutter_rust_bridge::frb(sync)]
pub fn eq_set_band(track_id: u32, band_index: u8, params: EqBandParams) -> bool {
    use crate::command_queue::send_command;
    use crate::dsp_commands::{DspCommand, FilterType, FilterSlope, StereoPlacement};

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
    use crate::dsp_commands::{DspCommand, AnalyzerMode};

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

    send_command(DspCommand::SpectrumSetSmoothing { track_id, smoothing })
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
    log::debug!("Bus {} volume: {} dB (linear: {:.4})", bus_id, volume_db, linear);
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
        log::debug!("Fade in clip {} for {} sec, curve {}", clip_id, duration_sec, curve_type);
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
        log::debug!("Fade out clip {} for {} sec, curve {}", clip_id, duration_sec, curve_type);
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
                    if matches!(ext_lower.as_str(), "wav" | "mp3" | "flac" | "aiff" | "ogg" | "m4a") {
                        files.push(AudioFileInfo {
                            path: entry_path.to_string_lossy().to_string(),
                            name: entry_path.file_name()
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
    format: String,         // "wav", "mp3", "flac"
    sample_rate: u32,
    bit_depth: u8,          // 16, 24, 32
    normalize: bool,
    normalize_target_db: f64,
) -> Result<(), String> {
    log::debug!(
        "Export to {} ({}, {}Hz, {}bit, normalize={})",
        output_path, format, sample_rate, bit_depth, normalize
    );

    let engine = ENGINE.read();
    if engine.is_none() {
        return Err("Engine not initialized".to_string());
    }

    // TODO: Implement actual export
    Ok(())
}

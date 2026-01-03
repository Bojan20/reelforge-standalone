//! Tauri commands for React ↔ Rust communication
//!
//! All IPC commands exposed to the frontend.

use serde::{Deserialize, Serialize};
use tauri::State;

use rf_core::{BufferSize, SampleRate};
use rf_engine::{ChannelId, MixerCommand};

use crate::state::AppState;

// ============ Types ============

#[derive(Debug, Serialize, Deserialize)]
pub struct AudioStatus {
    pub running: bool,
    pub sample_rate: u32,
    pub buffer_size: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ChannelMeters {
    pub peak_l: f64,
    pub peak_r: f64,
    pub rms_l: f64,
    pub rms_r: f64,
    pub gain_reduction: f64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MasterMeters {
    pub peak_l: f64,
    pub peak_r: f64,
    pub gain_reduction: f64,
    pub lufs_short: f64,
    pub lufs_integrated: f64,
    pub true_peak: f64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AllMeters {
    pub channels: Vec<ChannelMeters>,
    pub master: MasterMeters,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TransportStatus {
    pub is_playing: bool,
    pub is_recording: bool,
    pub is_looping: bool,
    pub position_samples: u64,
    pub position_seconds: f64,
    pub tempo: f64,
}

// ============ Audio Engine Commands ============

#[tauri::command]
pub fn init_audio_engine(
    state: State<'_, AppState>,
    sample_rate: Option<u32>,
    buffer_size: Option<usize>,
) -> Result<AudioStatus, String> {
    let sr = match sample_rate.unwrap_or(48000) {
        44100 => SampleRate::Hz44100,
        48000 => SampleRate::Hz48000,
        88200 => SampleRate::Hz88200,
        96000 => SampleRate::Hz96000,
        _ => SampleRate::Hz48000,
    };

    let bs = match buffer_size.unwrap_or(256) {
        64 => BufferSize::Samples64,
        128 => BufferSize::Samples128,
        256 => BufferSize::Samples256,
        512 => BufferSize::Samples512,
        1024 => BufferSize::Samples1024,
        _ => BufferSize::Samples256,
    };

    state.init_audio(sr, bs)?;

    Ok(AudioStatus {
        running: state.is_audio_running(),
        sample_rate: sr.as_u32(),
        buffer_size: bs.as_usize(),
    })
}

#[tauri::command]
pub fn start_audio(state: State<'_, AppState>) -> Result<(), String> {
    state.start_audio()
}

#[tauri::command]
pub fn stop_audio(state: State<'_, AppState>) -> Result<(), String> {
    state.stop_audio()
}

#[tauri::command]
pub fn get_audio_status(state: State<'_, AppState>) -> AudioStatus {
    let audio = state.audio.lock();
    AudioStatus {
        running: audio.running,
        sample_rate: audio.sample_rate.as_u32(),
        buffer_size: audio.buffer_size.as_usize(),
    }
}

// ============ Mixer Commands ============

fn channel_id_from_index(index: usize) -> Option<ChannelId> {
    match index {
        0 => Some(ChannelId::Ui),
        1 => Some(ChannelId::Reels),
        2 => Some(ChannelId::Fx),
        3 => Some(ChannelId::Vo),
        4 => Some(ChannelId::Music),
        5 => Some(ChannelId::Ambient),
        _ => None,
    }
}

#[tauri::command]
pub fn set_channel_volume(state: State<'_, AppState>, channel: usize, db: f64) -> Result<(), String> {
    let channel_id = channel_id_from_index(channel).ok_or("Invalid channel index")?;
    state.send_mixer_command(MixerCommand::SetChannelVolume(channel_id, db));
    Ok(())
}

#[tauri::command]
pub fn set_channel_pan(state: State<'_, AppState>, channel: usize, pan: f64) -> Result<(), String> {
    let channel_id = channel_id_from_index(channel).ok_or("Invalid channel index")?;
    state.send_mixer_command(MixerCommand::SetChannelPan(channel_id, pan));
    Ok(())
}

#[tauri::command]
pub fn set_channel_mute(state: State<'_, AppState>, channel: usize, mute: bool) -> Result<(), String> {
    let channel_id = channel_id_from_index(channel).ok_or("Invalid channel index")?;
    state.send_mixer_command(MixerCommand::SetChannelMute(channel_id, mute));
    Ok(())
}

#[tauri::command]
pub fn set_channel_solo(state: State<'_, AppState>, channel: usize, solo: bool) -> Result<(), String> {
    let channel_id = channel_id_from_index(channel).ok_or("Invalid channel index")?;
    state.send_mixer_command(MixerCommand::SetChannelSolo(channel_id, solo));
    Ok(())
}

#[tauri::command]
pub fn set_master_volume(state: State<'_, AppState>, db: f64) -> Result<(), String> {
    state.send_mixer_command(MixerCommand::SetMasterVolume(db));
    Ok(())
}

#[tauri::command]
pub fn set_master_limiter(
    state: State<'_, AppState>,
    enabled: bool,
    ceiling: f64,
) -> Result<(), String> {
    state.send_mixer_command(MixerCommand::SetMasterLimiterEnabled(enabled));
    state.send_mixer_command(MixerCommand::SetMasterLimiterCeiling(ceiling));
    Ok(())
}

// ============ Metering ============

/// Get current meter values (polling fallback)
/// Primary metering is via "meters" event at 30fps
#[tauri::command]
pub fn get_meters(state: State<'_, AppState>) -> Option<AllMeters> {
    let meter_bridge = state.meter_bridge()?;

    let channels: Vec<ChannelMeters> = meter_bridge.channels
        .iter()
        .map(|ch| ChannelMeters {
            peak_l: ch.peak_l.load(),
            peak_r: ch.peak_r.load(),
            rms_l: ch.rms_l.load(),
            rms_r: ch.rms_r.load(),
            gain_reduction: ch.gain_reduction.load(),
        })
        .collect();

    let master = MasterMeters {
        peak_l: meter_bridge.master.peak_l.load(),
        peak_r: meter_bridge.master.peak_r.load(),
        gain_reduction: meter_bridge.master.gain_reduction.load(),
        lufs_short: meter_bridge.lufs_short.load(),
        lufs_integrated: meter_bridge.lufs_integrated.load(),
        true_peak: meter_bridge.true_peak.load(),
    };

    Some(AllMeters { channels, master })
}

// ============ Transport ============

#[tauri::command]
pub fn play(state: State<'_, AppState>) -> Result<(), String> {
    let mut transport = state.transport.write();
    transport.is_playing = true;
    log::info!("Transport: Play");
    Ok(())
}

#[tauri::command]
pub fn stop(state: State<'_, AppState>) -> Result<(), String> {
    let mut transport = state.transport.write();
    transport.is_playing = false;
    transport.position_samples = 0;
    log::info!("Transport: Stop");
    Ok(())
}

#[tauri::command]
pub fn set_position(state: State<'_, AppState>, samples: u64) -> Result<(), String> {
    let mut transport = state.transport.write();
    transport.position_samples = samples;
    Ok(())
}

#[tauri::command]
pub fn get_position(state: State<'_, AppState>) -> TransportStatus {
    let transport = state.transport.read();
    let audio = state.audio.lock();
    let sr = audio.sample_rate.as_f64();

    TransportStatus {
        is_playing: transport.is_playing,
        is_recording: transport.is_recording,
        is_looping: transport.is_looping,
        position_samples: transport.position_samples,
        position_seconds: transport.position_samples as f64 / sr,
        tempo: transport.tempo,
    }
}

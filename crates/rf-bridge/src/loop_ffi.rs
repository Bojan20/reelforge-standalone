//! FFI exports for FluxForge Advanced Looping System
//!
//! Wwise-grade loop control: LoopAsset registration, instance lifecycle,
//! region switching, per-iteration gain, marker ingest.
//! All commands route through PlaybackEngine ring buffers for real audio-thread processing.

use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::sync::Arc;

use rf_engine::ffi::PLAYBACK_ENGINE;
use rf_engine::loop_asset::*;
use rf_engine::loop_manager::*;
use rf_engine::marker_ingest;

// ═══════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════

/// Initialize the advanced looping system.
#[unsafe(no_mangle)]
pub extern "C" fn loop_system_init(_sample_rate: u32) -> i32 {
    PLAYBACK_ENGINE.loop_system_init();
    1
}

/// Check if loop system is initialized.
#[unsafe(no_mangle)]
pub extern "C" fn loop_system_is_initialized() -> i32 {
    if PLAYBACK_ENGINE.loop_system_is_initialized() { 1 } else { 0 }
}

/// Destroy the loop system and free resources.
#[unsafe(no_mangle)]
pub extern "C" fn loop_system_destroy() -> i32 {
    PLAYBACK_ENGINE.loop_system_destroy();
    1
}

// ═══════════════════════════════════════════════════════════
// ASSET REGISTRATION
// ═══════════════════════════════════════════════════════════

/// Register a LoopAsset from JSON string via command queue (sent to audio thread).
#[unsafe(no_mangle)]
pub extern "C" fn loop_register_asset_json(json_ptr: *const c_char) -> i32 {
    if json_ptr.is_null() { return 0; }
    let json = c_str_to_string(json_ptr);
    if json.is_empty() { return 0; }

    let asset: LoopAsset = match serde_json::from_str(&json) {
        Ok(a) => a,
        Err(_) => return 0,
    };

    if validate_loop_asset(&asset).is_err() { return 0; }

    let mut tx = PLAYBACK_ENGINE.loop_cmd_producer().lock();
    if tx.push(LoopCommand::RegisterAsset { asset: Box::new(asset) }).is_ok() { 1 } else { 0 }
}

/// Register asset directly (stored in PlaybackEngine's asset map).
#[unsafe(no_mangle)]
pub extern "C" fn loop_register_asset_direct(json_ptr: *const c_char) -> i32 {
    if json_ptr.is_null() { return 0; }
    let json = c_str_to_string(json_ptr);
    if json.is_empty() { return 0; }

    let asset: LoopAsset = match serde_json::from_str(&json) {
        Ok(a) => a,
        Err(_) => return 0,
    };

    if validate_loop_asset(&asset).is_err() { return 0; }

    let id = asset.id.clone();
    PLAYBACK_ENGINE.loop_assets_map().write().insert(id, Arc::new(asset));
    1
}

// ═══════════════════════════════════════════════════════════
// PLAYBACK CONTROL
// ═══════════════════════════════════════════════════════════

/// Start a loop instance.
#[unsafe(no_mangle)]
pub extern "C" fn loop_play(
    asset_id: *const c_char,
    region: *const c_char,
    volume: f32,
    bus: u32,
    use_dual_voice: i32,
    fade_in_ms: f32,
) -> i32 {
    let asset_id = c_str_to_string(asset_id);
    let region = c_str_to_string(region);
    if asset_id.is_empty() || region.is_empty() { return 0; }

    send_command(LoopCommand::Play {
        asset_id,
        region,
        volume,
        bus,
        use_dual_voice: use_dual_voice != 0,
        play_pre_entry: None,
        fade_in_ms: if fade_in_ms > 0.0 { Some(fade_in_ms) } else { None },
    })
}

/// Set loop region (with sync mode).
#[unsafe(no_mangle)]
pub extern "C" fn loop_set_region(
    instance_id: u64,
    region: *const c_char,
    sync_mode: u32,
    crossfade_ms: f32,
    crossfade_curve: u32,
) -> i32 {
    let region = c_str_to_string(region);
    if region.is_empty() { return 0; }

    send_command(LoopCommand::SetRegion {
        instance_id,
        region,
        sync: sync_mode_from_u32(sync_mode),
        crossfade_ms,
        crossfade_curve: crossfade_curve_from_u32(crossfade_curve),
    })
}

/// Exit a loop instance.
#[unsafe(no_mangle)]
pub extern "C" fn loop_exit(
    instance_id: u64,
    sync_mode: u32,
    fade_out_ms: f32,
    play_post_exit: i32,
) -> i32 {
    send_command(LoopCommand::Exit {
        instance_id,
        sync: sync_mode_from_u32(sync_mode),
        fade_out_ms,
        play_post_exit: Some(play_post_exit != 0),
    })
}

/// Stop a loop instance (optional fade).
#[unsafe(no_mangle)]
pub extern "C" fn loop_stop(instance_id: u64, fade_out_ms: f32) -> i32 {
    send_command(LoopCommand::Stop { instance_id, fade_out_ms })
}

/// Set volume on a loop instance.
#[unsafe(no_mangle)]
pub extern "C" fn loop_set_volume(instance_id: u64, volume: f32, fade_ms: f32) -> i32 {
    send_command(LoopCommand::SetVolume { instance_id, volume, fade_ms })
}

/// Set bus routing.
#[unsafe(no_mangle)]
pub extern "C" fn loop_set_bus(instance_id: u64, bus: u32) -> i32 {
    send_command(LoopCommand::SetBus { instance_id, bus })
}

/// Seek to position (debug/QA).
#[unsafe(no_mangle)]
pub extern "C" fn loop_seek(instance_id: u64, position_samples: u64) -> i32 {
    send_command(LoopCommand::Seek { instance_id, position_samples })
}

/// Set per-iteration gain factor.
#[unsafe(no_mangle)]
pub extern "C" fn loop_set_iteration_gain(instance_id: u64, factor: f32) -> i32 {
    send_command(LoopCommand::SetIterationGain { instance_id, factor })
}

// ═══════════════════════════════════════════════════════════
// CALLBACK POLLING
// ═══════════════════════════════════════════════════════════

/// Poll next callback. Returns JSON string or null.
/// Caller must free with loop_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn loop_poll_callback() -> *mut c_char {
    let mut rx = PLAYBACK_ENGINE.loop_cb_consumer().lock();
    if let Ok(cb) = rx.pop() {
        let json = callback_to_json(&cb);
        CString::new(json).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut())
    } else {
        ptr::null_mut()
    }
}

/// Free a string returned by FFI.
#[unsafe(no_mangle)]
pub extern "C" fn loop_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { let _ = CString::from_raw(ptr); }
    }
}

// ═══════════════════════════════════════════════════════════
// MARKER INGEST
// ═══════════════════════════════════════════════════════════

/// Parse sidecar markers → LoopAsset JSON.
/// Caller must free with loop_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn loop_parse_sidecar_markers(
    sidecar_json: *const c_char,
    asset_id: *const c_char,
    sound_id: *const c_char,
    sample_rate: u32,
    channels: u16,
    length_samples: u64,
) -> *mut c_char {
    let json = c_str_to_string(sidecar_json);
    let aid = c_str_to_string(asset_id);
    let sid = c_str_to_string(sound_id);
    if json.is_empty() || aid.is_empty() { return ptr::null_mut(); }

    let markers = match marker_ingest::parse_sidecar_json(&json) {
        Ok(m) => m,
        Err(_) => return ptr::null_mut(),
    };

    let asset = match marker_ingest::markers_to_loop_asset(
        &markers, &aid, &sid, sample_rate, channels, length_samples,
        &marker_ingest::IngestConfig::default(),
    ) {
        Ok(a) => a,
        Err(_) => return ptr::null_mut(),
    };

    serde_json::to_string(&asset)
        .ok()
        .and_then(|s| CString::new(s).ok())
        .map(|cs| cs.into_raw())
        .unwrap_or(ptr::null_mut())
}

/// Validate a LoopAsset JSON. Returns error JSON or null (valid).
/// Caller must free with loop_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn loop_validate_asset(json_ptr: *const c_char) -> *mut c_char {
    let json = c_str_to_string(json_ptr);
    if json.is_empty() { return ptr::null_mut(); }

    let asset: LoopAsset = match serde_json::from_str(&json) {
        Ok(a) => a,
        Err(e) => {
            let msg = format!("{{\"error\":\"Invalid JSON: {}\"}}", e);
            return CString::new(msg).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut());
        }
    };

    match validate_loop_asset(&asset) {
        Ok(()) => ptr::null_mut(),
        Err(errors) => {
            let msgs: Vec<String> = errors.iter().map(|e| e.to_string()).collect();
            let json = format!("{{\"errors\":{}}}", serde_json::to_string(&msgs).unwrap_or_default());
            CString::new(json).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut())
        }
    }
}

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════

fn c_str_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() { return String::new(); }
    unsafe { CStr::from_ptr(ptr) }.to_str().unwrap_or("").to_string()
}

fn send_command(cmd: LoopCommand) -> i32 {
    let mut tx = PLAYBACK_ENGINE.loop_cmd_producer().lock();
    if tx.push(cmd).is_ok() { 1 } else { 0 }
}

fn sync_mode_from_u32(v: u32) -> SyncMode {
    match v {
        0 => SyncMode::NextBar,
        1 => SyncMode::NextBeat,
        2 => SyncMode::NextCue,
        3 => SyncMode::Immediate,
        4 => SyncMode::ExitCue,
        5 => SyncMode::OnWrap,
        6 => SyncMode::EntryCue,
        7 => SyncMode::SameTime,
        _ => SyncMode::Immediate,
    }
}

fn crossfade_curve_from_u32(v: u32) -> LoopCrossfadeCurve {
    match v {
        0 => LoopCrossfadeCurve::EqualPower,
        1 => LoopCrossfadeCurve::Linear,
        2 => LoopCrossfadeCurve::SCurve,
        3 => LoopCrossfadeCurve::Logarithmic,
        4 => LoopCrossfadeCurve::Exponential,
        5 => LoopCrossfadeCurve::CosineHalf,
        6 => LoopCrossfadeCurve::SquareRoot,
        7 => LoopCrossfadeCurve::Sine,
        8 => LoopCrossfadeCurve::FastAttack,
        9 => LoopCrossfadeCurve::SlowAttack,
        _ => LoopCrossfadeCurve::EqualPower,
    }
}

fn callback_to_json(cb: &LoopCallback) -> String {
    match cb {
        LoopCallback::Started { instance_id, asset_id } =>
            format!("{{\"type\":\"started\",\"instanceId\":{instance_id},\"assetId\":\"{asset_id}\"}}"),
        LoopCallback::StateChanged { instance_id, new_state } => {
            let s = match new_state { 0 => "intro", 1 => "looping", 2 => "exiting", _ => "stopped" };
            format!("{{\"type\":\"stateChanged\",\"instanceId\":{instance_id},\"state\":\"{s}\"}}")
        }
        LoopCallback::Wrap { instance_id, loop_count, at_samples } =>
            format!("{{\"type\":\"wrap\",\"instanceId\":{instance_id},\"loopCount\":{loop_count},\"atSamples\":{at_samples}}}"),
        LoopCallback::RegionSwitched { instance_id, from_region, to_region } =>
            format!("{{\"type\":\"regionSwitched\",\"instanceId\":{instance_id},\"from\":\"{from_region}\",\"to\":\"{to_region}\"}}"),
        LoopCallback::CueHit { instance_id, cue_name, at_samples } =>
            format!("{{\"type\":\"cueHit\",\"instanceId\":{instance_id},\"cueName\":\"{cue_name}\",\"atSamples\":{at_samples}}}"),
        LoopCallback::Stopped { instance_id } =>
            format!("{{\"type\":\"stopped\",\"instanceId\":{instance_id}}}"),
        LoopCallback::VoiceStealWarning { instance_id } =>
            format!("{{\"type\":\"voiceStealWarning\",\"instanceId\":{instance_id}}}"),
        LoopCallback::Error { message } =>
            format!("{{\"type\":\"error\",\"message\":\"{}\"}}", message.replace('"', "\\\"")),
    }
}

//! Mixer API functions
//!
//! Extracted from api.rs as part of modular FFI decomposition.
//! Handles track mixing: volume, pan, mute, solo, bus routing.

use crate::ENGINE;

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

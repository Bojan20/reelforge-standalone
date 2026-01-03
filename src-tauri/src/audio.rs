//! Audio utilities and meter broadcasting
//!
//! Handles real-time meter updates via Tauri events.

use std::time::Duration;
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use crate::state::AppState;

/// Channel meter data sent to frontend
#[derive(Debug, Clone, Serialize)]
pub struct ChannelMeterData {
    pub peak_l: f64,
    pub peak_r: f64,
    pub rms_l: f64,
    pub rms_r: f64,
    pub gain_reduction: f64,
}

/// Master meter data sent to frontend
#[derive(Debug, Clone, Serialize)]
pub struct MasterMeterData {
    pub peak_l: f64,
    pub peak_r: f64,
    pub rms_l: f64,
    pub rms_r: f64,
    pub gain_reduction: f64,
    pub lufs_short: f64,
    pub lufs_integrated: f64,
    pub true_peak: f64,
}

/// All meters payload
#[derive(Debug, Clone, Serialize)]
pub struct AllMeters {
    pub channels: Vec<ChannelMeterData>,
    pub master: MasterMeterData,
}

/// Meter broadcast loop - emits meter events at ~30fps
pub fn meter_broadcast_loop(app: AppHandle) {
    log::info!("Meter broadcast thread started");

    let update_interval = Duration::from_millis(33); // ~30fps

    loop {
        std::thread::sleep(update_interval);

        // Get AppState
        let state = match app.try_state::<AppState>() {
            Some(s) => s,
            None => continue,
        };

        // Get MeterBridge
        let meter_bridge = match state.meter_bridge() {
            Some(m) => m,
            None => continue, // Not initialized yet
        };

        // Read atomic meter values
        let mut channels = Vec::with_capacity(6);
        for ch in &meter_bridge.channels {
            channels.push(ChannelMeterData {
                peak_l: ch.peak_l.load(),
                peak_r: ch.peak_r.load(),
                rms_l: ch.rms_l.load(),
                rms_r: ch.rms_r.load(),
                gain_reduction: ch.gain_reduction.load(),
            });
        }

        let master = MasterMeterData {
            peak_l: meter_bridge.master.peak_l.load(),
            peak_r: meter_bridge.master.peak_r.load(),
            rms_l: meter_bridge.master.rms_l.load(),
            rms_r: meter_bridge.master.rms_r.load(),
            gain_reduction: meter_bridge.master.gain_reduction.load(),
            lufs_short: meter_bridge.lufs_short.load(),
            lufs_integrated: meter_bridge.lufs_integrated.load(),
            true_peak: meter_bridge.true_peak.load(),
        };

        let payload = AllMeters { channels, master };

        // Emit to all windows
        if let Err(e) = app.emit("meters", &payload) {
            log::warn!("Failed to emit meters: {}", e);
        }
    }
}

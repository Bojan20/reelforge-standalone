//! FFI exports for AutoSpatial Engine
//!
//! Provides C-compatible functions for Flutter dart:ffi to control:
//! - Real-time spatial audio processing
//! - Kalman filter for predictive smoothing
//! - Per-voice spatial output (pan, width, distance, reverb)
//! - Intent-based spatial positioning
//!
//! Architecture:
//! - Dart side handles: intent rules, anchors, UI tracking
//! - Rust side handles: real-time spatial processing, Kalman smoothing
//!
//! # Thread Safety
//! Uses atomic CAS for initialization and RwLock for state access.

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::ffi::{CStr, c_char};
use std::sync::atomic::{AtomicU8, Ordering};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Spatial output for a single voice/event
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct SpatialOutput {
    /// Pan position (-1.0 = left, 0.0 = center, 1.0 = right)
    pub pan: f64,
    /// Stereo width (0.0 = mono, 1.0 = full stereo)
    pub width: f64,
    /// Distance (0.0 = near, 1.0 = far)
    pub distance: f64,
    /// Doppler pitch shift multiplier (1.0 = no shift)
    pub doppler: f64,
    /// Reverb send level (0.0 - 1.0)
    pub reverb_send: f64,
    /// Low-pass filter cutoff Hz (20 - 20000)
    pub lpf_cutoff: f64,
    /// HRTF azimuth degrees (-180 to 180)
    pub hrtf_azimuth: f64,
    /// HRTF elevation degrees (-90 to 90)
    pub hrtf_elevation: f64,
}

/// 3D position
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct Position3D {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

/// Kalman filter state for a single tracker
#[derive(Debug, Clone)]
struct KalmanState {
    // State: [x, y, z, vx, vy, vz]
    state: [f64; 6],
    // Covariance matrix (6x6 flattened)
    covariance: [f64; 36],
    // Process noise
    q: f64,
    // Measurement noise
    r: f64,
    // Last update timestamp
    last_update_ms: u64,
}

impl Default for KalmanState {
    fn default() -> Self {
        let mut cov = [0.0; 36];
        // Initialize diagonal to 1.0
        for i in 0..6 {
            cov[i * 6 + i] = 1.0;
        }
        Self {
            state: [0.0; 6],
            covariance: cov,
            q: 0.01, // Process noise
            r: 0.1,  // Measurement noise
            last_update_ms: 0,
        }
    }
}

impl KalmanState {
    /// Predict step
    fn predict(&mut self, dt: f64) {
        // State transition: x += vx * dt, etc.
        self.state[0] += self.state[3] * dt;
        self.state[1] += self.state[4] * dt;
        self.state[2] += self.state[5] * dt;

        // Update covariance (simplified)
        for i in 0..6 {
            self.covariance[i * 6 + i] += self.q;
        }
    }

    /// Update step with measurement
    fn update(&mut self, measured: Position3D) {
        // Kalman gain (simplified scalar version)
        let k = self.covariance[0] / (self.covariance[0] + self.r);

        // Update state
        self.state[0] += k * (measured.x - self.state[0]);
        self.state[1] += k * (measured.y - self.state[1]);
        self.state[2] += k * (measured.z - self.state[2]);

        // Update covariance
        for i in 0..6 {
            self.covariance[i * 6 + i] *= 1.0 - k;
        }
    }

    /// Get current position estimate
    fn position(&self) -> Position3D {
        Position3D {
            x: self.state[0],
            y: self.state[1],
            z: self.state[2],
        }
    }

    /// Get current velocity estimate
    fn velocity(&self) -> Position3D {
        Position3D {
            x: self.state[3],
            y: self.state[4],
            z: self.state[5],
        }
    }
}

/// Event tracker with Kalman filter
#[derive(Debug, Clone, Default)]
struct EventTracker {
    id: u64,
    intent: String,
    kalman: KalmanState,
    output: SpatialOutput,
    active: bool,
    bus_id: u8,
}

/// Global engine state
#[derive(Debug)]
struct AutoSpatialState {
    /// Event trackers pool
    trackers: Vec<EventTracker>,
    /// Active tracker count
    active_count: usize,
    /// ID to tracker index mapping
    id_map: HashMap<u64, usize>,
    /// Next event ID
    next_id: u64,
    /// Listener position
    listener_pos: Position3D,
    /// Listener rotation (radians)
    listener_rotation: f64,
    /// Global pan scale
    pan_scale: f64,
    /// Global width scale
    width_scale: f64,
    /// Doppler enabled
    doppler_enabled: bool,
    /// HRTF enabled
    hrtf_enabled: bool,
    /// Distance attenuation enabled
    distance_atten_enabled: bool,
    /// Reverb enabled
    reverb_enabled: bool,
    /// Stats
    events_per_second: f64,
    processing_time_us: u64,
    dropped_events: u64,
}

impl Default for AutoSpatialState {
    fn default() -> Self {
        // Pre-allocate 128 trackers
        let mut trackers = Vec::with_capacity(128);
        for _ in 0..128 {
            trackers.push(EventTracker::default());
        }

        Self {
            trackers,
            active_count: 0,
            id_map: HashMap::with_capacity(128),
            next_id: 1,
            listener_pos: Position3D::default(),
            listener_rotation: 0.0,
            pan_scale: 1.0,
            width_scale: 1.0,
            doppler_enabled: true,
            hrtf_enabled: false,
            distance_atten_enabled: true,
            reverb_enabled: true,
            events_per_second: 0.0,
            processing_time_us: 0,
            dropped_events: 0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialization states
const STATE_UNINITIALIZED: u8 = 0;
const STATE_INITIALIZING: u8 = 1;
const STATE_INITIALIZED: u8 = 2;

/// Initialization state
static AUTO_SPATIAL_STATE: AtomicU8 = AtomicU8::new(STATE_UNINITIALIZED);

/// Engine state
static ENGINE: Lazy<RwLock<AutoSpatialState>> =
    Lazy::new(|| RwLock::new(AutoSpatialState::default()));

/// Current timestamp (for Kalman dt calculation)
static CURRENT_TIME_MS: Lazy<RwLock<u64>> = Lazy::new(|| RwLock::new(0));

// ═══════════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the AutoSpatial engine
///
/// Returns 1 on success, 0 if already initialized
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_init() -> i32 {
    match AUTO_SPATIAL_STATE.compare_exchange(
        STATE_UNINITIALIZED,
        STATE_INITIALIZING,
        Ordering::SeqCst,
        Ordering::SeqCst,
    ) {
        Ok(_) => {
            *ENGINE.write() = AutoSpatialState::default();
            *CURRENT_TIME_MS.write() = 0;

            AUTO_SPATIAL_STATE.store(STATE_INITIALIZED, Ordering::SeqCst);
            log::info!("auto_spatial_init: AutoSpatial Engine initialized (128 tracker pool)");
            1
        }
        Err(STATE_INITIALIZING) => {
            while AUTO_SPATIAL_STATE.load(Ordering::SeqCst) == STATE_INITIALIZING {
                std::hint::spin_loop();
            }
            0
        }
        Err(_) => {
            log::warn!("auto_spatial_init: Already initialized");
            0
        }
    }
}

/// Shutdown the AutoSpatial engine
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_shutdown() {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }

    let mut engine = ENGINE.write();
    engine.id_map.clear();
    engine.active_count = 0;
    for tracker in &mut engine.trackers {
        tracker.active = false;
    }

    AUTO_SPATIAL_STATE.store(STATE_UNINITIALIZED, Ordering::SeqCst);
    log::info!("auto_spatial_shutdown: AutoSpatial Engine shut down");
}

/// Check if engine is initialized
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_is_initialized() -> i32 {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) == STATE_INITIALIZED {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT TRACKING
// ═══════════════════════════════════════════════════════════════════════════════

/// Start tracking a new spatial event
///
/// Returns event ID (>0) on success, 0 on failure (pool exhausted)
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_start_event(
    intent: *const c_char,
    x: f64,
    y: f64,
    z: f64,
    bus_id: u8,
) -> u64 {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return 0;
    }

    let intent_str = if intent.is_null() {
        String::from("default")
    } else {
        unsafe { CStr::from_ptr(intent) }
            .to_string_lossy()
            .into_owned()
    };

    let mut engine = ENGINE.write();

    // Find free tracker slot
    let slot = engine.trackers.iter().position(|t| !t.active);
    let slot = match slot {
        Some(s) => s,
        None => {
            engine.dropped_events += 1;
            log::warn!("auto_spatial_start_event: Pool exhausted, dropped event");
            return 0;
        }
    };

    let id = engine.next_id;
    engine.next_id += 1;

    let current_time = *CURRENT_TIME_MS.read();

    // Copy values before mutable borrow
    let listener_pos = engine.listener_pos;
    let listener_rot = engine.listener_rotation;
    let pan_scale = engine.pan_scale;
    let width_scale = engine.width_scale;

    // Initialize tracker
    let tracker = &mut engine.trackers[slot];
    tracker.id = id;
    tracker.intent = intent_str;
    tracker.bus_id = bus_id;
    tracker.active = true;
    tracker.kalman = KalmanState::default();
    tracker.kalman.state[0] = x;
    tracker.kalman.state[1] = y;
    tracker.kalman.state[2] = z;
    tracker.kalman.last_update_ms = current_time;

    // Calculate initial spatial output
    update_tracker_output(tracker, &listener_pos, listener_rot, pan_scale, width_scale);

    // Release tracker borrow before final updates
    let _ = tracker;
    engine.id_map.insert(id, slot);
    engine.active_count += 1;

    id
}

/// Update event position
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_update_event(event_id: u64, x: f64, y: f64, z: f64) -> i32 {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return 0;
    }

    let mut engine = ENGINE.write();
    let current_time = *CURRENT_TIME_MS.read();

    // Copy values before mutable borrow
    let listener_pos = engine.listener_pos;
    let listener_rot = engine.listener_rotation;
    let pan_scale = engine.pan_scale;
    let width_scale = engine.width_scale;

    if let Some(&slot) = engine.id_map.get(&event_id) {
        let tracker = &mut engine.trackers[slot];
        if tracker.active {
            // Calculate dt
            let dt = if tracker.kalman.last_update_ms > 0 {
                (current_time - tracker.kalman.last_update_ms) as f64 / 1000.0
            } else {
                0.016 // Default 16ms
            };

            // Predict then update Kalman
            if dt > 0.0 {
                tracker.kalman.predict(dt);
            }
            tracker.kalman.update(Position3D { x, y, z });
            tracker.kalman.last_update_ms = current_time;

            // Update spatial output
            update_tracker_output(tracker, &listener_pos, listener_rot, pan_scale, width_scale);

            return 1;
        }
    }

    0
}

/// Stop tracking an event
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_stop_event(event_id: u64) -> i32 {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return 0;
    }

    let mut engine = ENGINE.write();

    if let Some(slot) = engine.id_map.remove(&event_id) {
        engine.trackers[slot].active = false;
        engine.active_count = engine.active_count.saturating_sub(1);
        return 1;
    }

    0
}

/// Get spatial output for an event
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_get_output(event_id: u64, out: *mut SpatialOutput) -> i32 {
    if out.is_null() || AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return 0;
    }

    let engine = ENGINE.read();

    if let Some(&slot) = engine.id_map.get(&event_id) {
        let tracker = &engine.trackers[slot];
        if tracker.active {
            unsafe {
                *out = tracker.output;
            }
            return 1;
        }
    }

    0
}

/// Get all active event outputs (batch query)
/// Returns number of events written
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_get_all_outputs(
    out_ids: *mut u64,
    out_outputs: *mut SpatialOutput,
    max_count: u32,
) -> u32 {
    if out_ids.is_null()
        || out_outputs.is_null()
        || AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED
    {
        return 0;
    }

    let engine = ENGINE.read();
    let mut written = 0u32;

    for tracker in &engine.trackers {
        if tracker.active && written < max_count {
            unsafe {
                *out_ids.add(written as usize) = tracker.id;
                *out_outputs.add(written as usize) = tracker.output;
            }
            written += 1;
        }
    }

    written
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Set listener position
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_listener(x: f64, y: f64, z: f64, rotation: f64) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }

    let mut engine = ENGINE.write();
    engine.listener_pos = Position3D { x, y, z };
    engine.listener_rotation = rotation;

    // Update all active trackers
    let listener_pos = engine.listener_pos;
    let listener_rot = engine.listener_rotation;
    let pan_scale = engine.pan_scale;
    let width_scale = engine.width_scale;

    for tracker in &mut engine.trackers {
        if tracker.active {
            update_tracker_output(tracker, &listener_pos, listener_rot, pan_scale, width_scale);
        }
    }
}

/// Set global pan scale
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_pan_scale(scale: f64) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }
    ENGINE.write().pan_scale = scale.clamp(0.0, 2.0);
}

/// Set global width scale
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_width_scale(scale: f64) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }
    ENGINE.write().width_scale = scale.clamp(0.0, 2.0);
}

/// Enable/disable Doppler effect
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_doppler_enabled(enabled: i32) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }
    ENGINE.write().doppler_enabled = enabled != 0;
}

/// Enable/disable HRTF
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_hrtf_enabled(enabled: i32) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }
    ENGINE.write().hrtf_enabled = enabled != 0;
}

/// Enable/disable distance attenuation
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_distance_atten_enabled(enabled: i32) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }
    ENGINE.write().distance_atten_enabled = enabled != 0;
}

/// Enable/disable reverb
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_reverb_enabled(enabled: i32) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }
    ENGINE.write().reverb_enabled = enabled != 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIMING & STATS
// ═══════════════════════════════════════════════════════════════════════════════

/// Update current time (call this each frame/tick)
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_set_time(time_ms: u64) {
    *CURRENT_TIME_MS.write() = time_ms;
}

/// Tick the engine (predict all active trackers forward)
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_tick(dt_ms: u32) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }

    let start = std::time::Instant::now();
    let dt = dt_ms as f64 / 1000.0;

    let mut engine = ENGINE.write();
    let listener_pos = engine.listener_pos;
    let listener_rot = engine.listener_rotation;
    let pan_scale = engine.pan_scale;
    let width_scale = engine.width_scale;

    for tracker in &mut engine.trackers {
        if tracker.active {
            tracker.kalman.predict(dt);
            update_tracker_output(tracker, &listener_pos, listener_rot, pan_scale, width_scale);
        }
    }

    engine.processing_time_us = start.elapsed().as_micros() as u64;
}

/// Get statistics
#[unsafe(no_mangle)]
pub extern "C" fn auto_spatial_get_stats(
    out_active_events: *mut u32,
    out_pool_utilization: *mut f32,
    out_processing_time_us: *mut u64,
    out_dropped_events: *mut u64,
) {
    if AUTO_SPATIAL_STATE.load(Ordering::SeqCst) != STATE_INITIALIZED {
        return;
    }

    let engine = ENGINE.read();

    if !out_active_events.is_null() {
        unsafe {
            *out_active_events = engine.active_count as u32;
        }
    }
    if !out_pool_utilization.is_null() {
        unsafe {
            *out_pool_utilization = (engine.active_count as f32 / 128.0) * 100.0;
        }
    }
    if !out_processing_time_us.is_null() {
        unsafe {
            *out_processing_time_us = engine.processing_time_us;
        }
    }
    if !out_dropped_events.is_null() {
        unsafe {
            *out_dropped_events = engine.dropped_events;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Update tracker's spatial output based on Kalman position
fn update_tracker_output(
    tracker: &mut EventTracker,
    listener_pos: &Position3D,
    listener_rotation: f64,
    pan_scale: f64,
    width_scale: f64,
) {
    let pos = tracker.kalman.position();
    let vel = tracker.kalman.velocity();

    // Relative position to listener
    let rel_x = pos.x - listener_pos.x;
    let rel_y = pos.y - listener_pos.y;
    let rel_z = pos.z - listener_pos.z;

    // Rotate by listener rotation
    let cos_r = listener_rotation.cos();
    let sin_r = listener_rotation.sin();
    let rotated_x = rel_x * cos_r - rel_y * sin_r;
    let rotated_y = rel_x * sin_r + rel_y * cos_r;

    // Distance
    let distance = (rotated_x * rotated_x + rotated_y * rotated_y + rel_z * rel_z).sqrt();
    let distance_norm = (distance / 2.0).min(1.0); // Normalize to 0-1 over 2 units

    // Pan from x position (-1 to +1)
    let raw_pan = rotated_x.clamp(-1.0, 1.0);
    tracker.output.pan = (raw_pan * pan_scale).clamp(-1.0, 1.0);

    // Width decreases with distance
    tracker.output.width = ((1.0 - distance_norm * 0.5) * width_scale).clamp(0.0, 1.0);

    // Distance
    tracker.output.distance = distance_norm;

    // Doppler from velocity towards listener
    let speed_of_sound = 343.0; // m/s
    let velocity_towards = -(vel.x * rotated_x + vel.y * rotated_y) / distance.max(0.01);
    tracker.output.doppler = 1.0 + (velocity_towards / speed_of_sound).clamp(-0.5, 0.5);

    // Reverb increases with distance
    tracker.output.reverb_send = (distance_norm * 0.8).clamp(0.0, 1.0);

    // LPF decreases with distance (air absorption)
    tracker.output.lpf_cutoff = 20000.0 - (distance_norm * 15000.0).clamp(0.0, 15000.0);

    // HRTF angles
    tracker.output.hrtf_azimuth = rotated_x.atan2(rotated_y).to_degrees();
    tracker.output.hrtf_elevation = (rel_z / distance.max(0.01)).asin().to_degrees();
}

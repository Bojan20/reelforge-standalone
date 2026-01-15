// MIDI Bridge — Device enumeration and input handling
//
// Provides cross-platform MIDI support:
// - Input/output device enumeration
// - Real-time MIDI input capture
// - Lock-free event queue for recording
// - MIDI routing to tracks

use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Mutex,
};

use midir::{MidiInput, MidiInputConnection, MidiOutput, MidiOutputConnection};
use parking_lot::RwLock;

// ============================================================================
// TYPES
// ============================================================================

/// MIDI device info for UI
#[derive(Debug, Clone)]
pub struct MidiDeviceInfo {
    pub id: String,
    pub name: String,
    pub is_input: bool,
    pub is_output: bool,
}

/// MIDI input event with timestamp
#[derive(Debug, Clone)]
pub struct MidiInputEvent {
    /// Timestamp in microseconds from input start
    pub timestamp_us: u64,
    /// Sample position (computed from timestamp)
    pub sample_position: u64,
    /// Raw MIDI bytes
    pub data: [u8; 3],
    /// Number of valid bytes (1-3)
    pub len: u8,
}

/// Recording state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MidiRecordingState {
    Stopped,
    Armed,
    Recording,
    Paused,
}

// ============================================================================
// GLOBAL STATE (atomics for lock-free access)
// ============================================================================

/// Recording state (atomic for lock-free read)
static RECORDING_STATE: AtomicU64 = AtomicU64::new(0);
/// Target track for recording
static TARGET_TRACK_ID: AtomicU64 = AtomicU64::new(0);
/// Sample rate for timestamp conversion
static SAMPLE_RATE: AtomicU64 = AtomicU64::new(48000);
/// Recording start timestamp (microseconds)
static RECORDING_START_US: AtomicU64 = AtomicU64::new(0);
/// MIDI thru enabled
static MIDI_THRU_ENABLED: AtomicBool = AtomicBool::new(true);

lazy_static::lazy_static! {
    /// Event buffer (Mutex for thread-safe append)
    static ref EVENT_BUFFER: Mutex<Vec<MidiInputEvent>> = Mutex::new(Vec::with_capacity(4096));

    /// Cached list of input devices
    static ref INPUT_DEVICES: RwLock<Vec<MidiDeviceInfo>> = RwLock::new(Vec::new());

    /// Cached list of output devices
    static ref OUTPUT_DEVICES: RwLock<Vec<MidiDeviceInfo>> = RwLock::new(Vec::new());

    /// Active input connections (needs Mutex because MidiInputConnection is not Sync)
    static ref INPUT_CONNECTIONS: Mutex<Vec<(String, MidiInputConnection<()>)>> = Mutex::new(Vec::new());

    /// Active output connection
    static ref OUTPUT_CONNECTION: Mutex<Option<MidiOutputConnection>> = Mutex::new(None);
}

// ============================================================================
// RECORDING STATE
// ============================================================================

/// Get current recording state
pub fn get_recording_state() -> MidiRecordingState {
    match RECORDING_STATE.load(Ordering::Relaxed) {
        1 => MidiRecordingState::Armed,
        2 => MidiRecordingState::Recording,
        3 => MidiRecordingState::Paused,
        _ => MidiRecordingState::Stopped,
    }
}

/// Set recording state
pub fn set_recording_state(state: MidiRecordingState) {
    let value = match state {
        MidiRecordingState::Stopped => 0,
        MidiRecordingState::Armed => 1,
        MidiRecordingState::Recording => 2,
        MidiRecordingState::Paused => 3,
    };
    RECORDING_STATE.store(value, Ordering::Relaxed);

    if state == MidiRecordingState::Recording {
        // Record start timestamp
        RECORDING_START_US.store(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as u64,
            Ordering::Relaxed,
        );
        // Clear event buffer
        if let Ok(mut buffer) = EVENT_BUFFER.lock() {
            buffer.clear();
        }
    }
}

/// Set target track for recording
pub fn set_target_track(track_id: u64) {
    TARGET_TRACK_ID.store(track_id, Ordering::Relaxed);
}

/// Get target track
pub fn get_target_track() -> u64 {
    TARGET_TRACK_ID.load(Ordering::Relaxed)
}

/// Set sample rate for timestamp conversion
pub fn set_sample_rate(sample_rate: u32) {
    SAMPLE_RATE.store(sample_rate as u64, Ordering::Relaxed);
}

/// Enable/disable MIDI thru
pub fn set_midi_thru(enabled: bool) {
    MIDI_THRU_ENABLED.store(enabled, Ordering::Relaxed);
}

/// Check if MIDI thru is enabled
pub fn is_midi_thru_enabled() -> bool {
    MIDI_THRU_ENABLED.load(Ordering::Relaxed)
}

// ============================================================================
// MIDI INPUT CALLBACK
// ============================================================================

/// Process incoming MIDI data (called from midir callback)
fn process_midi_input(timestamp_us: u64, data: &[u8]) {
    if data.is_empty() || data.len() > 3 {
        return;
    }

    // Skip if not recording
    if get_recording_state() != MidiRecordingState::Recording {
        return;
    }

    // Compute sample position from timestamp
    let start_us = RECORDING_START_US.load(Ordering::Relaxed);
    let relative_us = timestamp_us.saturating_sub(start_us);
    let sample_rate = SAMPLE_RATE.load(Ordering::Relaxed);
    let sample_position = (relative_us * sample_rate) / 1_000_000;

    // Create event
    let mut event_data = [0u8; 3];
    let len = data.len().min(3);
    event_data[..len].copy_from_slice(&data[..len]);

    let event = MidiInputEvent {
        timestamp_us,
        sample_position,
        data: event_data,
        len: len as u8,
    };

    // Push to event buffer
    if let Ok(mut buffer) = EVENT_BUFFER.lock() {
        if buffer.len() < 65536 {
            // Hard limit
            buffer.push(event);
        }
    }
}

// ============================================================================
// DEVICE ENUMERATION
// ============================================================================

/// Scan for available MIDI input devices
pub fn scan_input_devices() -> Vec<MidiDeviceInfo> {
    let midi_in = match MidiInput::new("FluxForge Studio") {
        Ok(m) => m,
        Err(e) => {
            log::error!("Failed to create MIDI input: {}", e);
            return Vec::new();
        }
    };

    let ports = midi_in.ports();
    let mut devices = Vec::with_capacity(ports.len());

    for (idx, port) in ports.iter().enumerate() {
        let name = midi_in
            .port_name(port)
            .unwrap_or_else(|_| format!("MIDI Input {}", idx));

        devices.push(MidiDeviceInfo {
            id: format!("midi_in_{}", idx),
            name,
            is_input: true,
            is_output: false,
        });
    }

    // Cache for later use
    *INPUT_DEVICES.write() = devices.clone();
    log::info!("Scanned {} MIDI input devices", devices.len());
    devices
}

/// Scan for available MIDI output devices
pub fn scan_output_devices() -> Vec<MidiDeviceInfo> {
    let midi_out = match MidiOutput::new("FluxForge Studio") {
        Ok(m) => m,
        Err(e) => {
            log::error!("Failed to create MIDI output: {}", e);
            return Vec::new();
        }
    };

    let ports = midi_out.ports();
    let mut devices = Vec::with_capacity(ports.len());

    for (idx, port) in ports.iter().enumerate() {
        let name = midi_out
            .port_name(port)
            .unwrap_or_else(|_| format!("MIDI Output {}", idx));

        devices.push(MidiDeviceInfo {
            id: format!("midi_out_{}", idx),
            name,
            is_input: false,
            is_output: true,
        });
    }

    // Cache for later use
    *OUTPUT_DEVICES.write() = devices.clone();
    log::info!("Scanned {} MIDI output devices", devices.len());
    devices
}

/// Get cached input devices
pub fn get_input_devices() -> Vec<MidiDeviceInfo> {
    INPUT_DEVICES.read().clone()
}

/// Get cached output devices
pub fn get_output_devices() -> Vec<MidiDeviceInfo> {
    OUTPUT_DEVICES.read().clone()
}

/// Get device count
pub fn input_device_count() -> usize {
    INPUT_DEVICES.read().len()
}

pub fn output_device_count() -> usize {
    OUTPUT_DEVICES.read().len()
}

// ============================================================================
// INPUT CONNECTION
// ============================================================================

/// Connect to a MIDI input device by index
pub fn connect_input_device(device_index: usize) -> Result<(), String> {
    let midi_in = MidiInput::new("FluxForge Studio Recording")
        .map_err(|e| format!("Failed to create MIDI input: {}", e))?;

    let ports = midi_in.ports();
    if device_index >= ports.len() {
        return Err(format!(
            "Invalid device index {} (have {})",
            device_index,
            ports.len()
        ));
    }

    let port = &ports[device_index];
    let port_name = midi_in
        .port_name(port)
        .unwrap_or_else(|_| format!("MIDI In {}", device_index));

    log::info!("Connecting to MIDI input: {}", port_name);

    // Create connection with callback
    let connection = midi_in
        .connect(
            port,
            "fluxforge-input",
            move |timestamp_us, data, _| {
                process_midi_input(timestamp_us, data);
            },
            (),
        )
        .map_err(|e| format!("Failed to connect: {}", e))?;

    // Store connection
    if let Ok(mut connections) = INPUT_CONNECTIONS.lock() {
        connections.push((port_name.clone(), connection));
    }

    log::info!("Connected to MIDI input: {}", port_name);
    Ok(())
}

/// Disconnect from a MIDI input device by connection index
pub fn disconnect_input_device(connection_index: usize) -> Result<(), String> {
    if let Ok(mut connections) = INPUT_CONNECTIONS.lock() {
        if connection_index >= connections.len() {
            return Err("Invalid connection index".to_string());
        }

        let (name, connection) = connections.remove(connection_index);
        drop(connection); // Close connection
        log::info!("Disconnected from MIDI input: {}", name);
        Ok(())
    } else {
        Err("Failed to acquire lock".to_string())
    }
}

/// Disconnect all MIDI inputs
pub fn disconnect_all_inputs() {
    if let Ok(mut connections) = INPUT_CONNECTIONS.lock() {
        let count = connections.len();
        connections.clear();
        log::info!("Disconnected {} MIDI inputs", count);
    }
}

/// Get number of active input connections
pub fn active_input_count() -> usize {
    INPUT_CONNECTIONS
        .lock()
        .map(|c| c.len())
        .unwrap_or(0)
}

/// Get list of active input connection names
pub fn get_active_inputs() -> Vec<String> {
    INPUT_CONNECTIONS
        .lock()
        .map(|c| c.iter().map(|(name, _)| name.clone()).collect())
        .unwrap_or_default()
}

// ============================================================================
// RECORDING CONTROL
// ============================================================================

/// Start MIDI recording to a track
pub fn start_recording(track_id: u64) {
    set_target_track(track_id);
    set_recording_state(MidiRecordingState::Recording);
    log::info!("MIDI recording started for track {}", track_id);
}

/// Stop MIDI recording
pub fn stop_recording() {
    set_recording_state(MidiRecordingState::Stopped);
    log::info!("MIDI recording stopped");
}

/// Arm track for MIDI recording
pub fn arm_track(track_id: u64) {
    set_target_track(track_id);
    set_recording_state(MidiRecordingState::Armed);
    log::info!("Track {} armed for MIDI recording", track_id);
}

/// Check if currently recording
pub fn is_recording() -> bool {
    get_recording_state() == MidiRecordingState::Recording
}

/// Get recorded events and clear buffer
pub fn take_recorded_events() -> Vec<MidiInputEvent> {
    EVENT_BUFFER
        .lock()
        .map(|mut buffer| {
            let events = buffer.clone();
            buffer.clear();
            events
        })
        .unwrap_or_default()
}

/// Get recorded events without clearing
pub fn peek_recorded_events() -> Vec<MidiInputEvent> {
    EVENT_BUFFER
        .lock()
        .map(|buffer| buffer.clone())
        .unwrap_or_default()
}

/// Get recorded event count
pub fn recorded_event_count() -> usize {
    EVENT_BUFFER.lock().map(|b| b.len()).unwrap_or(0)
}

// ============================================================================
// MIDI OUTPUT
// ============================================================================

/// Connect to a MIDI output device
pub fn connect_output_device(device_index: usize) -> Result<(), String> {
    let midi_out = MidiOutput::new("FluxForge Studio Output")
        .map_err(|e| format!("Failed to create MIDI output: {}", e))?;

    let ports = midi_out.ports();
    if device_index >= ports.len() {
        return Err(format!(
            "Invalid device index {} (have {})",
            device_index,
            ports.len()
        ));
    }

    let port = &ports[device_index];
    let port_name = midi_out
        .port_name(port)
        .unwrap_or_else(|_| format!("MIDI Out {}", device_index));

    log::info!("Connecting to MIDI output: {}", port_name);

    let connection = midi_out
        .connect(port, "fluxforge-output")
        .map_err(|e| format!("Failed to connect: {}", e))?;

    if let Ok(mut conn) = OUTPUT_CONNECTION.lock() {
        *conn = Some(connection);
    }

    log::info!("Connected to MIDI output: {}", port_name);
    Ok(())
}

/// Disconnect MIDI output
pub fn disconnect_output() {
    if let Ok(mut conn) = OUTPUT_CONNECTION.lock() {
        if conn.is_some() {
            *conn = None;
            log::info!("Disconnected MIDI output");
        }
    }
}

/// Check if output is connected
pub fn is_output_connected() -> bool {
    OUTPUT_CONNECTION
        .lock()
        .map(|c| c.is_some())
        .unwrap_or(false)
}

/// Send MIDI message to output
pub fn send_midi(data: &[u8]) -> Result<(), String> {
    if let Ok(mut conn) = OUTPUT_CONNECTION.lock() {
        if let Some(ref mut connection) = *conn {
            connection
                .send(data)
                .map_err(|e| format!("Failed to send MIDI: {}", e))
        } else {
            Err("No output connected".to_string())
        }
    } else {
        Err("Failed to acquire lock".to_string())
    }
}

/// Send note on
pub fn send_note_on(channel: u8, note: u8, velocity: u8) -> Result<(), String> {
    send_midi(&[0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F])
}

/// Send note off
pub fn send_note_off(channel: u8, note: u8, velocity: u8) -> Result<(), String> {
    send_midi(&[0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F])
}

/// Send CC
pub fn send_cc(channel: u8, cc: u8, value: u8) -> Result<(), String> {
    send_midi(&[0xB0 | (channel & 0x0F), cc & 0x7F, value & 0x7F])
}

/// Send pitch bend (14-bit value, center = 8192)
pub fn send_pitch_bend(channel: u8, value: u16) -> Result<(), String> {
    let clamped = value.min(16383);
    send_midi(&[
        0xE0 | (channel & 0x0F),
        (clamped & 0x7F) as u8,
        ((clamped >> 7) & 0x7F) as u8,
    ])
}

/// Send program change
pub fn send_program_change(channel: u8, program: u8) -> Result<(), String> {
    send_midi(&[0xC0 | (channel & 0x0F), program & 0x7F])
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_scan() {
        // Just verify it doesn't crash
        let inputs = scan_input_devices();
        let outputs = scan_output_devices();
        println!("Found {} inputs, {} outputs", inputs.len(), outputs.len());
    }

    #[test]
    fn test_recording_state() {
        set_recording_state(MidiRecordingState::Stopped);
        assert_eq!(get_recording_state(), MidiRecordingState::Stopped);

        set_recording_state(MidiRecordingState::Armed);
        assert_eq!(get_recording_state(), MidiRecordingState::Armed);

        set_recording_state(MidiRecordingState::Recording);
        assert_eq!(get_recording_state(), MidiRecordingState::Recording);

        // Reset
        set_recording_state(MidiRecordingState::Stopped);
    }

    #[test]
    fn test_event_buffer() {
        set_recording_state(MidiRecordingState::Recording);

        // Simulate some events
        process_midi_input(1000, &[0x90, 60, 100]);
        process_midi_input(2000, &[0x80, 60, 0]);

        let events = take_recorded_events();
        assert_eq!(events.len(), 2);

        // Buffer should be cleared
        assert_eq!(recorded_event_count(), 0);

        set_recording_state(MidiRecordingState::Stopped);
    }
}

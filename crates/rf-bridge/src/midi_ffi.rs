// MIDI FFI — C ABI Functions for Flutter
//
// Exposed to Flutter via dart:ffi

use crate::midi_bridge;
use std::ffi::c_char;

// ═══════════════════════════════════════════════════════════════════════════
// DEVICE ENUMERATION
// ═══════════════════════════════════════════════════════════════════════════

/// Scan for MIDI input devices
/// Returns number of devices found
#[unsafe(no_mangle)]
pub extern "C" fn midi_scan_input_devices() -> u32 {
    midi_bridge::scan_input_devices().len() as u32
}

/// Scan for MIDI output devices
/// Returns number of devices found
#[unsafe(no_mangle)]
pub extern "C" fn midi_scan_output_devices() -> u32 {
    midi_bridge::scan_output_devices().len() as u32
}

/// Get MIDI input device name
/// Returns: length of name written, -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn midi_get_input_device_name(
    index: u32,
    out_name: *mut c_char,
    max_len: u32,
) -> i32 {
    if out_name.is_null() || max_len == 0 {
        return -1;
    }

    let devices = midi_bridge::get_input_devices();
    if (index as usize) >= devices.len() {
        return -1;
    }

    let name = &devices[index as usize].name;
    let bytes = name.as_bytes();
    let copy_len = bytes.len().min(max_len as usize - 1);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_name as *mut u8, copy_len);
        *out_name.add(copy_len) = 0; // Null terminate
    }

    copy_len as i32
}

/// Get MIDI output device name
#[unsafe(no_mangle)]
pub extern "C" fn midi_get_output_device_name(
    index: u32,
    out_name: *mut c_char,
    max_len: u32,
) -> i32 {
    if out_name.is_null() || max_len == 0 {
        return -1;
    }

    let devices = midi_bridge::get_output_devices();
    if (index as usize) >= devices.len() {
        return -1;
    }

    let name = &devices[index as usize].name;
    let bytes = name.as_bytes();
    let copy_len = bytes.len().min(max_len as usize - 1);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_name as *mut u8, copy_len);
        *out_name.add(copy_len) = 0;
    }

    copy_len as i32
}

/// Get number of cached input devices
#[unsafe(no_mangle)]
pub extern "C" fn midi_input_device_count() -> u32 {
    midi_bridge::input_device_count() as u32
}

/// Get number of cached output devices
#[unsafe(no_mangle)]
pub extern "C" fn midi_output_device_count() -> u32 {
    midi_bridge::output_device_count() as u32
}

// ═══════════════════════════════════════════════════════════════════════════
// INPUT CONNECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Connect to MIDI input device
/// Returns: 1 = success, -1 = error
#[unsafe(no_mangle)]
pub extern "C" fn midi_connect_input(device_index: u32) -> i32 {
    match midi_bridge::connect_input_device(device_index as usize) {
        Ok(()) => 1,
        Err(e) => {
            log::error!("MIDI connect error: {}", e);
            -1
        }
    }
}

/// Disconnect from MIDI input device by connection index
#[unsafe(no_mangle)]
pub extern "C" fn midi_disconnect_input(connection_index: u32) -> i32 {
    match midi_bridge::disconnect_input_device(connection_index as usize) {
        Ok(()) => 1,
        Err(_) => -1,
    }
}

/// Disconnect all MIDI inputs
#[unsafe(no_mangle)]
pub extern "C" fn midi_disconnect_all_inputs() {
    midi_bridge::disconnect_all_inputs();
}

/// Get number of active MIDI input connections
#[unsafe(no_mangle)]
pub extern "C" fn midi_active_input_count() -> u32 {
    midi_bridge::active_input_count() as u32
}

// ═══════════════════════════════════════════════════════════════════════════
// OUTPUT CONNECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Connect to MIDI output device
#[unsafe(no_mangle)]
pub extern "C" fn midi_connect_output(device_index: u32) -> i32 {
    match midi_bridge::connect_output_device(device_index as usize) {
        Ok(()) => 1,
        Err(e) => {
            log::error!("MIDI output connect error: {}", e);
            -1
        }
    }
}

/// Disconnect MIDI output
#[unsafe(no_mangle)]
pub extern "C" fn midi_disconnect_output() {
    midi_bridge::disconnect_output();
}

/// Check if MIDI output is connected
#[unsafe(no_mangle)]
pub extern "C" fn midi_is_output_connected() -> i32 {
    if midi_bridge::is_output_connected() {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING
// ═══════════════════════════════════════════════════════════════════════════

/// Start MIDI recording for a track
#[unsafe(no_mangle)]
pub extern "C" fn midi_start_recording(track_id: u64) {
    midi_bridge::start_recording(track_id);
}

/// Stop MIDI recording
#[unsafe(no_mangle)]
pub extern "C" fn midi_stop_recording() {
    midi_bridge::stop_recording();
}

/// Arm track for MIDI recording
#[unsafe(no_mangle)]
pub extern "C" fn midi_arm_track(track_id: u64) {
    midi_bridge::arm_track(track_id);
}

/// Check if MIDI recording is active
#[unsafe(no_mangle)]
pub extern "C" fn midi_is_recording() -> i32 {
    if midi_bridge::is_recording() { 1 } else { 0 }
}

/// Get MIDI recording state
/// Returns: 0=Stopped, 1=Armed, 2=Recording, 3=Paused
#[unsafe(no_mangle)]
pub extern "C" fn midi_get_recording_state() -> u32 {
    use midi_bridge::MidiRecordingState;
    match midi_bridge::get_recording_state() {
        MidiRecordingState::Stopped => 0,
        MidiRecordingState::Armed => 1,
        MidiRecordingState::Recording => 2,
        MidiRecordingState::Paused => 3,
    }
}

/// Get number of recorded MIDI events
#[unsafe(no_mangle)]
pub extern "C" fn midi_recorded_event_count() -> u32 {
    midi_bridge::recorded_event_count() as u32
}

/// Get target track for recording
#[unsafe(no_mangle)]
pub extern "C" fn midi_get_target_track() -> u64 {
    midi_bridge::get_target_track()
}

// ═══════════════════════════════════════════════════════════════════════════
// SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// Set sample rate for MIDI timestamp conversion
#[unsafe(no_mangle)]
pub extern "C" fn midi_set_sample_rate(sample_rate: u32) {
    midi_bridge::set_sample_rate(sample_rate);
}

/// Enable/disable MIDI thru
#[unsafe(no_mangle)]
pub extern "C" fn midi_set_thru(enabled: i32) {
    midi_bridge::set_midi_thru(enabled != 0);
}

/// Check if MIDI thru is enabled
#[unsafe(no_mangle)]
pub extern "C" fn midi_is_thru_enabled() -> i32 {
    if midi_bridge::is_midi_thru_enabled() {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIDI OUTPUT (Send Messages)
// ═══════════════════════════════════════════════════════════════════════════

/// Send MIDI note on
#[unsafe(no_mangle)]
pub extern "C" fn midi_send_note_on(channel: u8, note: u8, velocity: u8) -> i32 {
    match midi_bridge::send_note_on(channel, note, velocity) {
        Ok(()) => 1,
        Err(_) => -1,
    }
}

/// Send MIDI note off
#[unsafe(no_mangle)]
pub extern "C" fn midi_send_note_off(channel: u8, note: u8, velocity: u8) -> i32 {
    match midi_bridge::send_note_off(channel, note, velocity) {
        Ok(()) => 1,
        Err(_) => -1,
    }
}

/// Send MIDI CC
#[unsafe(no_mangle)]
pub extern "C" fn midi_send_cc(channel: u8, cc: u8, value: u8) -> i32 {
    match midi_bridge::send_cc(channel, cc, value) {
        Ok(()) => 1,
        Err(_) => -1,
    }
}

/// Send MIDI pitch bend (14-bit value, center = 8192)
#[unsafe(no_mangle)]
pub extern "C" fn midi_send_pitch_bend(channel: u8, value: u16) -> i32 {
    match midi_bridge::send_pitch_bend(channel, value) {
        Ok(()) => 1,
        Err(_) => -1,
    }
}

/// Send MIDI program change
#[unsafe(no_mangle)]
pub extern "C" fn midi_send_program_change(channel: u8, program: u8) -> i32 {
    match midi_bridge::send_program_change(channel, program) {
        Ok(()) => 1,
        Err(_) => -1,
    }
}

/// Send raw MIDI bytes (1-3 bytes)
#[unsafe(no_mangle)]
pub extern "C" fn midi_send_raw(data: *const u8, len: u8) -> i32 {
    if data.is_null() || len == 0 || len > 3 {
        return -1;
    }

    let bytes = unsafe { std::slice::from_raw_parts(data, len as usize) };
    match midi_bridge::send_midi(bytes) {
        Ok(()) => 1,
        Err(_) => -1,
    }
}

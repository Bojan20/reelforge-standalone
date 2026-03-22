//! OSC FFI — C-compatible interface for OSC server

use crate::osc_server;
use std::ffi::CString;
use std::os::raw::c_char;

/// Start OSC server on given port. Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn osc_start(port: u32) -> i32 {
    if osc_server::start(port as u16) { 1 } else { 0 }
}

/// Stop OSC server.
#[unsafe(no_mangle)]
pub extern "C" fn osc_stop() {
    osc_server::stop();
}

/// Check if OSC server is running.
#[unsafe(no_mangle)]
pub extern "C" fn osc_is_running() -> i32 {
    if osc_server::is_running() { 1 } else { 0 }
}

/// Get current OSC port.
#[unsafe(no_mangle)]
pub extern "C" fn osc_get_port() -> u32 {
    osc_server::get_port() as u32
}

/// Poll pending OSC messages. Returns count.
/// For each message, writes: address (null-terminated C string) + float_arg + int_arg
/// into the provided buffers. Buffers must have room for `max_events` entries.
///
/// out_addresses: array of *mut c_char pointers (caller must free each with free_rust_string)
/// out_floats: array of f32 (NaN if no float arg)
/// out_ints: array of i32 (i32::MIN if no int arg)
#[unsafe(no_mangle)]
pub extern "C" fn osc_poll_messages(
    out_addresses: *mut *mut c_char,
    out_floats: *mut f32,
    out_ints: *mut i32,
    max_events: u32,
) -> u32 {
    if out_addresses.is_null() || out_floats.is_null() || out_ints.is_null() || max_events == 0 {
        return 0;
    }

    let Ok(mut buffer) = osc_server::OSC_BUFFER.lock() else { return 0; };
    let count = buffer.len().min(max_events as usize);

    for i in 0..count {
        let event = &buffer[i];

        // Address → CString
        let addr = CString::new(event.address.as_str()).unwrap_or_default();
        unsafe {
            *out_addresses.add(i) = addr.into_raw();
            *out_floats.add(i) = event.float_arg.unwrap_or(f32::NAN);
            *out_ints.add(i) = event.int_arg.unwrap_or(i32::MIN);
        }
    }

    buffer.drain(..count);
    count as u32
}

/// Get count of pending OSC messages (without draining).
#[unsafe(no_mangle)]
pub extern "C" fn osc_pending_count() -> u32 {
    osc_server::OSC_BUFFER.lock().map(|b| b.len() as u32).unwrap_or(0)
}

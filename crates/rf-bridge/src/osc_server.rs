//! OSC Server — UDP listener for Open Sound Control messages
//!
//! Receives OSC messages from game engines, Unreal, Unity, or other software.
//! Stores parsed messages in a lock-free buffer polled by Dart via FFI.
//!
//! Architecture:
//! - Background thread listens on UDP socket
//! - Parsed messages pushed to bounded buffer (`Mutex<Vec>`)
//! - Dart polls via osc_poll_messages() FFI every 5-10ms
//! - Buffer bounded to 256 entries (drains oldest on overflow)

use std::net::UdpSocket;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, Mutex};
use std::thread;

/// Parsed OSC message for Dart consumption
#[derive(Debug, Clone)]
pub struct OscEvent {
    /// OSC address (e.g., "/slot/reel_stop", "/rtpc/anticipation")
    pub address: String,
    /// First float argument (if any)
    pub float_arg: Option<f32>,
    /// First int argument (if any)
    pub int_arg: Option<i32>,
    /// First string argument (if any)
    pub string_arg: Option<String>,
}

/// Message buffer — polled by Dart
pub(crate) static OSC_BUFFER: LazyLock<Mutex<Vec<OscEvent>>> =
    LazyLock::new(|| Mutex::new(Vec::with_capacity(256)));

/// Server running flag
static RUNNING: AtomicBool = AtomicBool::new(false);

/// Current port
static PORT: LazyLock<Mutex<u16>> = LazyLock::new(|| Mutex::new(8000));

/// Start OSC server on given port. Returns true if started.
pub fn start(port: u16) -> bool {
    if RUNNING.load(Ordering::Relaxed) {
        return false; // Already running
    }

    if let Ok(mut p) = PORT.lock() {
        *p = port;
    }

    let socket = match UdpSocket::bind(format!("0.0.0.0:{}", port)) {
        Ok(s) => s,
        Err(_) => return false,
    };

    // Set non-blocking with 100ms timeout for clean shutdown
    socket.set_read_timeout(Some(std::time::Duration::from_millis(100))).ok();

    RUNNING.store(true, Ordering::Relaxed);

    thread::Builder::new()
        .name("osc-server".into())
        .spawn(move || {
            let mut buf = [0u8; 4096]; // OSC max packet size

            while RUNNING.load(Ordering::Relaxed) {
                match socket.recv_from(&mut buf) {
                    Ok((size, _addr)) => {
                        if let Ok(packet) = rosc::decoder::decode_udp(&buf[..size]) {
                            process_packet(packet.1);
                        }
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        // Timeout — check RUNNING flag and loop
                        continue;
                    }
                    Err(_) => {
                        // Other error — continue listening
                        continue;
                    }
                }
            }
        })
        .is_ok()
}

/// Stop OSC server
pub fn stop() {
    RUNNING.store(false, Ordering::Relaxed);
}

/// Check if OSC server is running
pub fn is_running() -> bool {
    RUNNING.load(Ordering::Relaxed)
}

/// Get current port
pub fn get_port() -> u16 {
    PORT.lock().map(|p| *p).unwrap_or(8000)
}

/// Process an OSC packet (may contain bundle or single message)
fn process_packet(packet: rosc::OscPacket) {
    process_packet_depth(packet, 0);
}

fn process_packet_depth(packet: rosc::OscPacket, depth: u8) {
    if depth > 8 { return; } // Prevent stack overflow from malicious nested bundles
    match packet {
        rosc::OscPacket::Message(msg) => process_message(msg),
        rosc::OscPacket::Bundle(bundle) => {
            for content in bundle.content {
                process_packet_depth(content, depth + 1);
            }
        }
    }
}

/// Process a single OSC message → push to buffer
fn process_message(msg: rosc::OscMessage) {
    let mut float_arg = None;
    let mut int_arg = None;
    let mut string_arg = None;

    // Extract first argument of each type
    for arg in &msg.args {
        match arg {
            rosc::OscType::Float(f) if float_arg.is_none() => { float_arg = Some(*f); }
            rosc::OscType::Int(i) if int_arg.is_none() => { int_arg = Some(*i); }
            rosc::OscType::String(s) if string_arg.is_none() => { string_arg = Some(s.clone()); }
            rosc::OscType::Double(d) if float_arg.is_none() => { float_arg = Some(*d as f32); }
            rosc::OscType::Long(l) if int_arg.is_none() => { int_arg = Some(*l as i32); }
            _ => {} // Skip blobs, booleans, etc.
        }
    }

    let event = OscEvent {
        address: msg.addr,
        float_arg,
        int_arg,
        string_arg,
    };

    if let Ok(mut buf) = OSC_BUFFER.lock() {
        if buf.len() >= 256 {
            buf.drain(..128); // Keep latest 128
        }
        buf.push(event);
    }
}

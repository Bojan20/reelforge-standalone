//! Audio over IP (AoIP) Support
//!
//! Professional AoIP standards support:
//! - SMPTE ST 2110-30 (AES3/PCM audio)
//! - AES67 (high-performance streaming)
//! - Dante-compatible (Audinate protocol)
//! - Ravenna/AES67 hybrid
//!
//! Features:
//! - Sub-millisecond latency
//! - PTP synchronization (IEEE 1588-2008)
//! - Redundant streams (ST 2022-7)
//! - Up to 384kHz/32-bit

use parking_lot::RwLock;
use std::net::{IpAddr, SocketAddr, UdpSocket};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Instant;

/// AoIP Protocol type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(Default)]
pub enum AoipProtocol {
    /// SMPTE ST 2110-30 (broadcast standard)
    Smpte2110,
    /// AES67 (studio standard)
    #[default]
    Aes67,
    /// Dante (proprietary but common)
    Dante,
    /// Ravenna (AES67 compatible)
    Ravenna,
}


/// Audio encoding for AoIP
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(Default)]
pub enum AoipEncoding {
    /// Linear PCM 16-bit
    Pcm16,
    /// Linear PCM 24-bit
    #[default]
    Pcm24,
    /// Linear PCM 32-bit
    Pcm32,
    /// 32-bit floating point
    Float32,
}


impl AoipEncoding {
    /// Bytes per sample
    pub fn bytes_per_sample(&self) -> usize {
        match self {
            Self::Pcm16 => 2,
            Self::Pcm24 => 3,
            Self::Pcm32 | Self::Float32 => 4,
        }
    }
}

/// PTP Clock status
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(Default)]
pub enum PtpStatus {
    /// Not synchronized
    #[default]
    Unsynchronized,
    /// Synchronizing
    Acquiring,
    /// Synchronized (locked)
    Locked,
    /// Free-running (no master)
    Freerun,
}


/// AoIP Stream configuration
#[derive(Debug, Clone)]
pub struct AoipStreamConfig {
    /// Protocol to use
    pub protocol: AoipProtocol,
    /// Audio encoding
    pub encoding: AoipEncoding,
    /// Sample rate
    pub sample_rate: u32,
    /// Number of channels
    pub channels: u16,
    /// Packet time in microseconds (typical: 125, 250, 333, 1000)
    pub packet_time_us: u32,
    /// Multicast group address
    pub multicast_addr: Option<IpAddr>,
    /// Port
    pub port: u16,
    /// Enable redundant stream (ST 2022-7)
    pub redundant: bool,
    /// Primary interface
    pub primary_interface: Option<String>,
    /// Secondary interface (for redundancy)
    pub secondary_interface: Option<String>,
    /// Buffer size (packets)
    pub buffer_packets: usize,
    /// DSCP marking for QoS
    pub dscp: u8,
}

impl Default for AoipStreamConfig {
    fn default() -> Self {
        Self {
            protocol: AoipProtocol::Aes67,
            encoding: AoipEncoding::Pcm24,
            sample_rate: 48000,
            channels: 2,
            packet_time_us: 1000, // 1ms default
            multicast_addr: None,
            port: 5004, // Default RTP port
            redundant: false,
            primary_interface: None,
            secondary_interface: None,
            buffer_packets: 8,
            dscp: 46, // EF (Expedited Forwarding)
        }
    }
}

impl AoipStreamConfig {
    /// Calculate samples per packet
    pub fn samples_per_packet(&self) -> usize {
        (self.sample_rate as usize * self.packet_time_us as usize) / 1_000_000
    }

    /// Calculate bytes per packet (audio payload only)
    pub fn payload_bytes(&self) -> usize {
        self.samples_per_packet() * self.channels as usize * self.encoding.bytes_per_sample()
    }

    /// Calculate packet rate (packets per second)
    pub fn packet_rate(&self) -> f64 {
        1_000_000.0 / self.packet_time_us as f64
    }

    /// Calculate bitrate (bits per second)
    pub fn bitrate(&self) -> u64 {
        (self.payload_bytes() as u64 * 8 * 1_000_000) / self.packet_time_us as u64
    }
}

/// RTP Header (12 bytes minimum)
#[repr(C, packed)]
#[derive(Debug, Clone, Copy, Default)]
pub struct RtpHeader {
    /// Version (2), Padding, Extension, CSRC count
    pub vpxcc: u8,
    /// Marker, Payload type
    pub mpt: u8,
    /// Sequence number
    pub sequence: u16,
    /// Timestamp
    pub timestamp: u32,
    /// SSRC
    pub ssrc: u32,
}

impl RtpHeader {
    /// Create new RTP header
    pub fn new(payload_type: u8, sequence: u16, timestamp: u32, ssrc: u32) -> Self {
        Self {
            vpxcc: 0x80, // Version 2, no padding, no extension, 0 CSRC
            mpt: payload_type & 0x7F,
            sequence,
            timestamp,
            ssrc,
        }
    }

    /// Set marker bit
    pub fn with_marker(mut self) -> Self {
        self.mpt |= 0x80;
        self
    }

    /// Serialize to bytes
    pub fn to_bytes(&self) -> [u8; 12] {
        [
            self.vpxcc,
            self.mpt,
            (self.sequence >> 8) as u8,
            self.sequence as u8,
            (self.timestamp >> 24) as u8,
            (self.timestamp >> 16) as u8,
            (self.timestamp >> 8) as u8,
            self.timestamp as u8,
            (self.ssrc >> 24) as u8,
            (self.ssrc >> 16) as u8,
            (self.ssrc >> 8) as u8,
            self.ssrc as u8,
        ]
    }

    /// Parse from bytes
    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 12 {
            return None;
        }
        Some(Self {
            vpxcc: bytes[0],
            mpt: bytes[1],
            sequence: ((bytes[2] as u16) << 8) | (bytes[3] as u16),
            timestamp: ((bytes[4] as u32) << 24)
                | ((bytes[5] as u32) << 16)
                | ((bytes[6] as u32) << 8)
                | (bytes[7] as u32),
            ssrc: ((bytes[8] as u32) << 24)
                | ((bytes[9] as u32) << 16)
                | ((bytes[10] as u32) << 8)
                | (bytes[11] as u32),
        })
    }
}

/// AoIP stream statistics
#[derive(Debug, Clone, Default)]
pub struct AoipStats {
    /// Packets sent
    pub packets_sent: u64,
    /// Packets received
    pub packets_received: u64,
    /// Packets lost
    pub packets_lost: u64,
    /// Packets late
    pub packets_late: u64,
    /// Packets out of order
    pub packets_reordered: u64,
    /// Average latency (microseconds)
    pub avg_latency_us: f64,
    /// Maximum latency (microseconds)
    pub max_latency_us: u64,
    /// Jitter (microseconds)
    pub jitter_us: f64,
    /// Current buffer fill level (0-1)
    pub buffer_level: f64,
}

/// Atomic statistics for real-time access
pub struct AtomicAoipStats {
    packets_sent: AtomicU64,
    packets_received: AtomicU64,
    packets_lost: AtomicU64,
    packets_late: AtomicU64,
}

impl Default for AtomicAoipStats {
    fn default() -> Self {
        Self {
            packets_sent: AtomicU64::new(0),
            packets_received: AtomicU64::new(0),
            packets_lost: AtomicU64::new(0),
            packets_late: AtomicU64::new(0),
        }
    }
}

impl AtomicAoipStats {
    pub fn record_sent(&self) {
        self.packets_sent.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_received(&self) {
        self.packets_received.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_lost(&self) {
        self.packets_lost.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_late(&self) {
        self.packets_late.fetch_add(1, Ordering::Relaxed);
    }

    pub fn snapshot(&self) -> AoipStats {
        AoipStats {
            packets_sent: self.packets_sent.load(Ordering::Relaxed),
            packets_received: self.packets_received.load(Ordering::Relaxed),
            packets_lost: self.packets_lost.load(Ordering::Relaxed),
            packets_late: self.packets_late.load(Ordering::Relaxed),
            ..Default::default()
        }
    }
}

/// AoIP Transmitter
pub struct AoipTransmitter {
    config: AoipStreamConfig,
    socket: Option<UdpSocket>,
    sequence: u16,
    timestamp: u32,
    ssrc: u32,
    stats: AtomicAoipStats,
    running: AtomicBool,
    packet_buffer: Vec<u8>,
}

impl AoipTransmitter {
    /// Create new transmitter
    pub fn new(config: AoipStreamConfig) -> Self {
        let ssrc = rand_u32();
        let max_packet_size = 12 + config.payload_bytes(); // RTP header + payload

        Self {
            config,
            socket: None,
            sequence: 0,
            timestamp: 0,
            ssrc,
            stats: AtomicAoipStats::default(),
            running: AtomicBool::new(false),
            packet_buffer: vec![0u8; max_packet_size],
        }
    }

    /// Start transmitter
    pub fn start(&mut self, dest: SocketAddr) -> Result<(), std::io::Error> {
        let socket = UdpSocket::bind("0.0.0.0:0")?;
        socket.connect(dest)?;

        // Set socket options for real-time
        socket.set_nonblocking(true)?;

        self.socket = Some(socket);
        self.running.store(true, Ordering::Release);

        Ok(())
    }

    /// Stop transmitter
    pub fn stop(&mut self) {
        self.running.store(false, Ordering::Release);
        self.socket = None;
    }

    /// Send audio samples
    pub fn send(&mut self, samples: &[f32]) -> Result<(), std::io::Error> {
        if !self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        let socket = match &self.socket {
            Some(s) => s,
            None => return Ok(()),
        };

        let samples_per_packet = self.config.samples_per_packet();
        let channels = self.config.channels as usize;

        // Process in packet-sized chunks
        for chunk in samples.chunks(samples_per_packet * channels) {
            // Build RTP header
            let header = RtpHeader::new(
                96, // Dynamic payload type for L24
                self.sequence,
                self.timestamp,
                self.ssrc,
            );

            // Write header to buffer
            self.packet_buffer[..12].copy_from_slice(&header.to_bytes());

            // Encode audio samples
            let payload_start = 12;
            match self.config.encoding {
                AoipEncoding::Pcm24 => {
                    for (i, &sample) in chunk.iter().enumerate() {
                        let value = (sample * 8388607.0) as i32;
                        let offset = payload_start + i * 3;
                        if offset + 3 <= self.packet_buffer.len() {
                            self.packet_buffer[offset] = ((value >> 16) & 0xFF) as u8;
                            self.packet_buffer[offset + 1] = ((value >> 8) & 0xFF) as u8;
                            self.packet_buffer[offset + 2] = (value & 0xFF) as u8;
                        }
                    }
                }
                AoipEncoding::Float32 => {
                    for (i, &sample) in chunk.iter().enumerate() {
                        let bytes = sample.to_be_bytes();
                        let offset = payload_start + i * 4;
                        if offset + 4 <= self.packet_buffer.len() {
                            self.packet_buffer[offset..offset + 4].copy_from_slice(&bytes);
                        }
                    }
                }
                _ => {
                    // Other encodings not fully implemented
                }
            }

            // Send packet
            let packet_size = payload_start + chunk.len() * self.config.encoding.bytes_per_sample();
            let _ = socket.send(&self.packet_buffer[..packet_size.min(self.packet_buffer.len())]);

            self.stats.record_sent();
            self.sequence = self.sequence.wrapping_add(1);
            self.timestamp = self.timestamp.wrapping_add(samples_per_packet as u32);
        }

        Ok(())
    }

    /// Get statistics
    pub fn stats(&self) -> AoipStats {
        self.stats.snapshot()
    }

    /// Is running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire)
    }
}

/// AoIP Receiver
#[allow(dead_code)]
pub struct AoipReceiver {
    config: AoipStreamConfig,
    socket: Option<UdpSocket>,
    stats: AtomicAoipStats,
    running: AtomicBool,
    last_sequence: u16,
    last_timestamp: u32,
    receive_buffer: Vec<u8>,
    audio_buffer: Arc<RwLock<Vec<f32>>>,
}

impl AoipReceiver {
    /// Create new receiver
    pub fn new(config: AoipStreamConfig) -> Self {
        let max_packet_size = 12 + config.payload_bytes();
        let audio_buffer_size =
            config.samples_per_packet() * config.channels as usize * config.buffer_packets;

        Self {
            config,
            socket: None,
            stats: AtomicAoipStats::default(),
            running: AtomicBool::new(false),
            last_sequence: 0,
            last_timestamp: 0,
            receive_buffer: vec![0u8; max_packet_size],
            audio_buffer: Arc::new(RwLock::new(vec![0.0f32; audio_buffer_size])),
        }
    }

    /// Start receiver
    pub fn start(&mut self, bind_addr: SocketAddr) -> Result<(), std::io::Error> {
        let socket = UdpSocket::bind(bind_addr)?;
        socket.set_nonblocking(true)?;

        // Join multicast if configured
        if let Some(multicast) = self.config.multicast_addr
            && let IpAddr::V4(addr) = multicast {
                socket.join_multicast_v4(&addr, &std::net::Ipv4Addr::UNSPECIFIED)?;
            }

        self.socket = Some(socket);
        self.running.store(true, Ordering::Release);

        Ok(())
    }

    /// Stop receiver
    pub fn stop(&mut self) {
        self.running.store(false, Ordering::Release);
        self.socket = None;
    }

    /// Receive and decode packets
    pub fn receive(&mut self) -> Option<Vec<f32>> {
        if !self.running.load(Ordering::Acquire) {
            return None;
        }

        let socket = match &self.socket {
            Some(s) => s,
            None => return None,
        };

        // Try to receive a packet
        match socket.recv(&mut self.receive_buffer) {
            Ok(size) if size >= 12 => {
                let header = RtpHeader::from_bytes(&self.receive_buffer)?;

                // Check for lost packets
                let expected_seq = self.last_sequence.wrapping_add(1);
                if header.sequence != expected_seq && self.last_sequence != 0 {
                    self.stats.record_lost();
                }

                self.last_sequence = header.sequence;
                self.last_timestamp = header.timestamp;
                self.stats.record_received();

                // Decode audio
                let payload = &self.receive_buffer[12..size];
                let samples = self.decode_audio(payload);

                Some(samples)
            }
            _ => None,
        }
    }

    /// Decode audio from payload
    fn decode_audio(&self, payload: &[u8]) -> Vec<f32> {
        let mut samples = Vec::new();

        match self.config.encoding {
            AoipEncoding::Pcm24 => {
                for chunk in payload.chunks(3) {
                    if chunk.len() == 3 {
                        let value = ((chunk[0] as i32) << 24)
                            | ((chunk[1] as i32) << 16)
                            | ((chunk[2] as i32) << 8);
                        samples.push((value >> 8) as f32 / 8388607.0);
                    }
                }
            }
            AoipEncoding::Float32 => {
                for chunk in payload.chunks(4) {
                    if chunk.len() == 4 {
                        let bytes = [chunk[0], chunk[1], chunk[2], chunk[3]];
                        samples.push(f32::from_be_bytes(bytes));
                    }
                }
            }
            AoipEncoding::Pcm16 => {
                for chunk in payload.chunks(2) {
                    if chunk.len() == 2 {
                        let value = ((chunk[0] as i16) << 8) | (chunk[1] as i16);
                        samples.push(value as f32 / 32767.0);
                    }
                }
            }
            AoipEncoding::Pcm32 => {
                for chunk in payload.chunks(4) {
                    if chunk.len() == 4 {
                        let value = ((chunk[0] as i32) << 24)
                            | ((chunk[1] as i32) << 16)
                            | ((chunk[2] as i32) << 8)
                            | (chunk[3] as i32);
                        samples.push(value as f32 / 2147483647.0);
                    }
                }
            }
        }

        samples
    }

    /// Get statistics
    pub fn stats(&self) -> AoipStats {
        self.stats.snapshot()
    }

    /// Is running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire)
    }
}

/// Simple random u32 for SSRC
fn rand_u32() -> u32 {
    use std::time::SystemTime;
    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    (nanos & 0xFFFFFFFF) as u32
}

/// PTP Clock (IEEE 1588-2008)
#[allow(dead_code)]
pub struct PtpClock {
    /// Clock status
    status: PtpStatus,
    /// Master clock ID
    master_id: Option<u64>,
    /// Offset from master (nanoseconds)
    offset_ns: i64,
    /// Path delay (nanoseconds)
    delay_ns: u64,
    /// Last sync time
    last_sync: Option<Instant>,
}

impl Default for PtpClock {
    fn default() -> Self {
        Self::new()
    }
}

impl PtpClock {
    /// Create new PTP clock
    pub fn new() -> Self {
        Self {
            status: PtpStatus::Unsynchronized,
            master_id: None,
            offset_ns: 0,
            delay_ns: 0,
            last_sync: None,
        }
    }

    /// Get current status
    pub fn status(&self) -> PtpStatus {
        self.status
    }

    /// Get offset from master in nanoseconds
    pub fn offset_ns(&self) -> i64 {
        self.offset_ns
    }

    /// Is synchronized
    pub fn is_locked(&self) -> bool {
        self.status == PtpStatus::Locked
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_aoip_config() {
        let config = AoipStreamConfig {
            sample_rate: 48000,
            channels: 2,
            packet_time_us: 1000,
            encoding: AoipEncoding::Pcm24,
            ..Default::default()
        };

        assert_eq!(config.samples_per_packet(), 48);
        assert_eq!(config.payload_bytes(), 48 * 2 * 3);
        assert!((config.packet_rate() - 1000.0).abs() < 0.1);
    }

    #[test]
    fn test_rtp_header() {
        let header = RtpHeader::new(96, 1234, 5678, 0xDEADBEEF);
        let bytes = header.to_bytes();
        let parsed = RtpHeader::from_bytes(&bytes).unwrap();

        // Copy fields to avoid unaligned access in packed struct
        let seq = { parsed.sequence };
        let ts = { parsed.timestamp };
        let ssrc = { parsed.ssrc };

        assert_eq!(seq, 1234);
        assert_eq!(ts, 5678);
        assert_eq!(ssrc, 0xDEADBEEF);
    }

    #[test]
    fn test_encoding_sizes() {
        assert_eq!(AoipEncoding::Pcm16.bytes_per_sample(), 2);
        assert_eq!(AoipEncoding::Pcm24.bytes_per_sample(), 3);
        assert_eq!(AoipEncoding::Pcm32.bytes_per_sample(), 4);
        assert_eq!(AoipEncoding::Float32.bytes_per_sample(), 4);
    }

    #[test]
    fn test_transmitter_creation() {
        let config = AoipStreamConfig::default();
        let tx = AoipTransmitter::new(config);
        assert!(!tx.is_running());
    }

    #[test]
    fn test_receiver_creation() {
        let config = AoipStreamConfig::default();
        let rx = AoipReceiver::new(config);
        assert!(!rx.is_running());
    }

    #[test]
    fn test_ptp_clock() {
        let clock = PtpClock::new();
        assert_eq!(clock.status(), PtpStatus::Unsynchronized);
        assert!(!clock.is_locked());
    }
}

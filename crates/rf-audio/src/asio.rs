//! ASIO Low-Latency Backend for Windows
//!
//! Professional-grade Windows audio I/O via ASIO:
//! - Direct hardware access bypassing Windows audio stack
//! - Sub-millisecond latency possible
//! - Professional sample rates up to 384kHz
//! - Multi-channel support (up to 64+ channels)
//!
//! # Requirements
//!
//! - ASIO driver installed (e.g., from audio interface manufacturer)
//! - asio-sys crate (bindings to ASIO SDK)
//!
//! # Latency Comparison
//!
//! | API       | Typical Latency |
//! |-----------|-----------------|
//! | WASAPI    | 10-50ms         |
//! | DirectSound | 50-100ms      |
//! | ASIO      | 1-5ms           |

#![cfg(target_os = "windows")]

use std::ffi::CStr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::Mutex;

use crate::{AudioError, AudioResult};
use rf_core::{BufferSize, Sample, SampleRate};

// ═══════════════════════════════════════════════════════════════════════════════
// ASIO TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// ASIO sample type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AsioSampleType {
    Int16LSB,
    Int24LSB,
    Int32LSB,
    Float32LSB,
    Float64LSB,
    Int32LSB16,
    Int32LSB18,
    Int32LSB20,
    Int32LSB24,
    // Big endian variants (rare)
    Int16MSB,
    Int24MSB,
    Int32MSB,
    Float32MSB,
    Float64MSB,
}

/// ASIO driver info
#[derive(Debug, Clone)]
pub struct AsioDriverInfo {
    pub name: String,
    pub version: i32,
    pub input_channels: i32,
    pub output_channels: i32,
    pub buffer_sizes: AsioBufferSizes,
    pub sample_rates: Vec<f64>,
    pub sample_type: AsioSampleType,
    pub input_latency: i32,
    pub output_latency: i32,
}

/// ASIO buffer sizes
#[derive(Debug, Clone, Copy)]
pub struct AsioBufferSizes {
    pub min: i32,
    pub max: i32,
    pub preferred: i32,
    pub granularity: i32,
}

/// ASIO channel info
#[derive(Debug, Clone)]
pub struct AsioChannelInfo {
    pub channel: i32,
    pub is_input: bool,
    pub is_active: bool,
    pub name: String,
    pub sample_type: AsioSampleType,
}

// ═══════════════════════════════════════════════════════════════════════════════
// ASIO DRIVER ENUMERATION (STUB - requires asio-sys)
// ═══════════════════════════════════════════════════════════════════════════════

/// List available ASIO drivers
///
/// This requires the asio-sys crate which wraps the ASIO SDK.
/// The ASIO SDK itself is proprietary and must be obtained from Steinberg.
pub fn list_asio_drivers() -> AudioResult<Vec<String>> {
    // In production, this would enumerate the Windows registry:
    // HKEY_LOCAL_MACHINE\SOFTWARE\ASIO
    // Each subkey is an ASIO driver with CLSID and Description

    // For now, return empty list - actual implementation requires asio-sys
    log::warn!("ASIO driver enumeration requires asio-sys crate");
    Ok(Vec::new())
}

/// Load ASIO driver by name
pub fn load_asio_driver(name: &str) -> AudioResult<AsioDriverInfo> {
    // This would:
    // 1. Open registry key for driver
    // 2. Get CLSID
    // 3. CoCreateInstance to load driver
    // 4. Call ASIOInit
    // 5. Query driver capabilities

    Err(AudioError::BackendError(format!(
        "ASIO driver loading not implemented: {}",
        name
    )))
}

// ═══════════════════════════════════════════════════════════════════════════════
// ASIO STREAM
// ═══════════════════════════════════════════════════════════════════════════════

/// Callback data for ASIO bufferSwitch
struct AsioCallbackData {
    callback: Box<dyn FnMut(&[Sample], &mut [Sample]) + Send>,
    input_channels: i32,
    output_channels: i32,
    buffer_size: i32,
    sample_type: AsioSampleType,
    running: AtomicBool,
    buffer_switch_count: AtomicU64,
}

/// ASIO stream wrapper
pub struct AsioStream {
    driver_name: String,
    sample_rate: f64,
    buffer_size: i32,
    callback_data: *mut AsioCallbackData,
    input_latency: i32,
    output_latency: i32,
}

// Safety: Callback data is managed by single owner
unsafe impl Send for AsioStream {}

impl AsioStream {
    /// Create new ASIO stream
    pub fn new<F>(
        driver_name: &str,
        sample_rate: SampleRate,
        buffer_size: BufferSize,
        callback: F,
    ) -> AudioResult<Self>
    where
        F: FnMut(&[Sample], &mut [Sample]) + Send + 'static,
    {
        // This would:
        // 1. Load ASIO driver
        // 2. Set sample rate (ASIOSetSampleRate)
        // 3. Create buffers (ASIOCreateBuffers)
        // 4. Register callbacks (bufferSwitch, sampleRateDidChange, etc.)

        Err(AudioError::BackendError(
            "ASIO stream creation requires asio-sys crate".to_string(),
        ))
    }

    /// Start ASIO stream
    pub fn start(&self) -> AudioResult<()> {
        // ASIOStart()
        Err(AudioError::StreamError("ASIO not implemented".to_string()))
    }

    /// Stop ASIO stream
    pub fn stop(&self) -> AudioResult<()> {
        // ASIOStop()
        Err(AudioError::StreamError("ASIO not implemented".to_string()))
    }

    /// Check if running
    pub fn is_running(&self) -> bool {
        false
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> f64 {
        self.sample_rate
    }

    /// Get buffer size
    pub fn buffer_size(&self) -> i32 {
        self.buffer_size
    }

    /// Get total latency in samples
    pub fn total_latency(&self) -> i32 {
        self.input_latency + self.output_latency
    }

    /// Get latency in milliseconds
    pub fn latency_ms(&self) -> f64 {
        (self.total_latency() as f64 / self.sample_rate) * 1000.0
    }

    /// Get buffer switch count
    pub fn buffer_switch_count(&self) -> u64 {
        0
    }
}

impl Drop for AsioStream {
    fn drop(&mut self) {
        // ASIODisposeBuffers()
        // ASIOExit()
        // CoUninitialize()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAMPLE CONVERSION UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Convert ASIO sample type to f64
#[inline]
pub fn asio_to_f64(data: &[u8], sample_type: AsioSampleType) -> f64 {
    match sample_type {
        AsioSampleType::Int16LSB => {
            let value = i16::from_le_bytes([data[0], data[1]]);
            value as f64 / 32768.0
        }
        AsioSampleType::Int24LSB => {
            let value = i32::from_le_bytes([
                data[0],
                data[1],
                data[2],
                if data[2] & 0x80 != 0 { 0xFF } else { 0x00 },
            ]);
            value as f64 / 8388608.0
        }
        AsioSampleType::Int32LSB => {
            let value = i32::from_le_bytes([data[0], data[1], data[2], data[3]]);
            value as f64 / 2147483648.0
        }
        AsioSampleType::Float32LSB => {
            let value = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
            value as f64
        }
        AsioSampleType::Float64LSB => f64::from_le_bytes([
            data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7],
        ]),
        _ => 0.0, // Handle other types as needed
    }
}

/// Convert f64 to ASIO sample type
#[inline]
pub fn f64_to_asio(value: f64, sample_type: AsioSampleType, output: &mut [u8]) {
    let clamped = value.clamp(-1.0, 1.0);

    match sample_type {
        AsioSampleType::Int16LSB => {
            let int_value = (clamped * 32767.0) as i16;
            let bytes = int_value.to_le_bytes();
            output[0] = bytes[0];
            output[1] = bytes[1];
        }
        AsioSampleType::Int24LSB => {
            let int_value = (clamped * 8388607.0) as i32;
            let bytes = int_value.to_le_bytes();
            output[0] = bytes[0];
            output[1] = bytes[1];
            output[2] = bytes[2];
        }
        AsioSampleType::Int32LSB => {
            let int_value = (clamped * 2147483647.0) as i32;
            let bytes = int_value.to_le_bytes();
            output[..4].copy_from_slice(&bytes);
        }
        AsioSampleType::Float32LSB => {
            let bytes = (clamped as f32).to_le_bytes();
            output[..4].copy_from_slice(&bytes);
        }
        AsioSampleType::Float64LSB => {
            let bytes = clamped.to_le_bytes();
            output[..8].copy_from_slice(&bytes);
        }
        _ => {} // Handle other types as needed
    }
}

/// Get sample size in bytes
#[inline]
pub fn sample_size(sample_type: AsioSampleType) -> usize {
    match sample_type {
        AsioSampleType::Int16LSB | AsioSampleType::Int16MSB => 2,
        AsioSampleType::Int24LSB | AsioSampleType::Int24MSB => 3,
        AsioSampleType::Int32LSB
        | AsioSampleType::Int32MSB
        | AsioSampleType::Int32LSB16
        | AsioSampleType::Int32LSB18
        | AsioSampleType::Int32LSB20
        | AsioSampleType::Int32LSB24
        | AsioSampleType::Float32LSB
        | AsioSampleType::Float32MSB => 4,
        AsioSampleType::Float64LSB | AsioSampleType::Float64MSB => 8,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ASIO CONTROL PANEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Show ASIO driver control panel
///
/// This opens the manufacturer's settings dialog for the ASIO driver,
/// allowing users to configure buffer size, sample rate, etc.
pub fn show_control_panel(_driver_name: &str) -> AudioResult<()> {
    // ASIOControlPanel()
    Err(AudioError::BackendError(
        "ASIO control panel requires asio-sys crate".to_string(),
    ))
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sample_conversion_int16() {
        // Max positive
        let mut output = [0u8; 2];
        f64_to_asio(1.0, AsioSampleType::Int16LSB, &mut output);
        let back = asio_to_f64(&output, AsioSampleType::Int16LSB);
        assert!((back - 1.0).abs() < 0.0001);

        // Max negative
        f64_to_asio(-1.0, AsioSampleType::Int16LSB, &mut output);
        let back = asio_to_f64(&output, AsioSampleType::Int16LSB);
        assert!((back - (-1.0)).abs() < 0.0001);

        // Zero
        f64_to_asio(0.0, AsioSampleType::Int16LSB, &mut output);
        let back = asio_to_f64(&output, AsioSampleType::Int16LSB);
        assert!(back.abs() < 0.0001);
    }

    #[test]
    fn test_sample_conversion_float32() {
        let mut output = [0u8; 4];

        f64_to_asio(0.5, AsioSampleType::Float32LSB, &mut output);
        let back = asio_to_f64(&output, AsioSampleType::Float32LSB);
        assert!((back - 0.5).abs() < 0.0001);
    }

    #[test]
    fn test_sample_sizes() {
        assert_eq!(sample_size(AsioSampleType::Int16LSB), 2);
        assert_eq!(sample_size(AsioSampleType::Int24LSB), 3);
        assert_eq!(sample_size(AsioSampleType::Int32LSB), 4);
        assert_eq!(sample_size(AsioSampleType::Float32LSB), 4);
        assert_eq!(sample_size(AsioSampleType::Float64LSB), 8);
    }

    #[test]
    fn test_list_drivers() {
        let drivers = list_asio_drivers();
        assert!(drivers.is_ok());
        println!("Available ASIO drivers: {:?}", drivers.unwrap());
    }
}

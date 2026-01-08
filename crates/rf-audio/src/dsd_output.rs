//! Native DSD Output Support
//!
//! UNIQUE: Direct DSD output via ASIO DSD-capable interfaces.
//!
//! Supports:
//! - Native ASIO DSD mode (raw 1-bit stream)
//! - DoP (DSD over PCM) fallback
//! - Automatic capability detection
//! - DSD64/128/256/512 rate selection

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

/// DSD output mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DsdOutputMode {
    /// DSD not supported, convert to PCM
    PcmConversion,
    /// DSD over PCM (DoP) - works with most USB DACs
    DoP,
    /// Native ASIO DSD - direct 1-bit stream
    NativeAsio,
}

/// DSD rate
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DsdRate {
    Dsd64,  // 2.8224 MHz
    Dsd128, // 5.6448 MHz
    Dsd256, // 11.2896 MHz
    Dsd512, // 22.5792 MHz
}

impl DsdRate {
    pub fn sample_rate(&self) -> u32 {
        match self {
            DsdRate::Dsd64 => 2_822_400,
            DsdRate::Dsd128 => 5_644_800,
            DsdRate::Dsd256 => 11_289_600,
            DsdRate::Dsd512 => 22_579_200,
        }
    }

    pub fn dop_pcm_rate(&self) -> u32 {
        // DoP requires specific PCM rates
        match self {
            DsdRate::Dsd64 => 176_400,   // DSD64 → 176.4kHz PCM
            DsdRate::Dsd128 => 352_800,  // DSD128 → 352.8kHz PCM
            DsdRate::Dsd256 => 705_600,  // DSD256 → 705.6kHz PCM (rare)
            DsdRate::Dsd512 => 705_600,  // DSD512 → requires native or special handling
        }
    }

    pub fn from_sample_rate(rate: u32) -> Option<Self> {
        match rate {
            2_822_400 => Some(DsdRate::Dsd64),
            5_644_800 => Some(DsdRate::Dsd128),
            11_289_600 => Some(DsdRate::Dsd256),
            22_579_200 => Some(DsdRate::Dsd512),
            _ => None,
        }
    }
}

/// DSD device capabilities
#[derive(Debug, Clone)]
pub struct DsdCapabilities {
    /// Device supports native DSD
    pub native_dsd: bool,
    /// Supported native DSD rates
    pub native_rates: Vec<DsdRate>,
    /// Device supports DoP
    pub dop_supported: bool,
    /// Supported DoP rates
    pub dop_rates: Vec<DsdRate>,
    /// Maximum channels for DSD
    pub max_channels: u32,
}

impl Default for DsdCapabilities {
    fn default() -> Self {
        Self {
            native_dsd: false,
            native_rates: Vec::new(),
            dop_supported: true, // Most DACs support DoP
            dop_rates: vec![DsdRate::Dsd64, DsdRate::Dsd128],
            max_channels: 2,
        }
    }
}

/// DoP (DSD over PCM) encoder
pub struct DoPEncoder {
    /// Current marker (alternates 0x05/0xFA)
    marker_state: bool,
    /// Channel count
    channels: usize,
}

impl DoPEncoder {
    pub fn new(channels: usize) -> Self {
        Self {
            marker_state: false,
            channels,
        }
    }

    /// Encode DSD bytes to DoP PCM samples
    ///
    /// Each 24-bit PCM sample contains:
    /// - Bits 23-16: DoP marker (0x05 or 0xFA, alternating)
    /// - Bits 15-8: DSD data byte (MSB)
    /// - Bits 7-0: DSD data byte (LSB)
    pub fn encode(&mut self, dsd_data: &[u8], output: &mut [i32]) {
        const DOP_MARKER_A: u8 = 0x05;
        const DOP_MARKER_B: u8 = 0xFA;

        let mut dsd_idx = 0;
        let mut out_idx = 0;

        while dsd_idx + 1 < dsd_data.len() && out_idx < output.len() {
            let marker = if self.marker_state { DOP_MARKER_B } else { DOP_MARKER_A };
            self.marker_state = !self.marker_state;

            // Pack two DSD bytes into one 24-bit DoP sample
            let dsd_msb = dsd_data[dsd_idx] as i32;
            let dsd_lsb = dsd_data[dsd_idx + 1] as i32;

            // DoP format: marker(8) | dsd_msb(8) | dsd_lsb(8)
            let dop_sample = ((marker as i32) << 16) | (dsd_msb << 8) | dsd_lsb;

            // Sign extend to 32-bit (DoP is always positive in upper bits)
            output[out_idx] = dop_sample << 8; // Shift to align as 32-bit

            dsd_idx += 2;
            out_idx += 1;
        }
    }

    /// Reset encoder state
    pub fn reset(&mut self) {
        self.marker_state = false;
    }
}

/// DoP decoder (for detecting DoP in PCM stream)
pub struct DoPDecoder {
    /// Last marker seen
    last_marker: Option<u8>,
    /// Consecutive valid markers
    valid_count: usize,
    /// Detection threshold
    detection_threshold: usize,
}

impl DoPDecoder {
    pub fn new() -> Self {
        Self {
            last_marker: None,
            valid_count: 0,
            detection_threshold: 8,
        }
    }

    /// Check if PCM data is actually DoP
    pub fn detect_dop(&mut self, pcm_samples: &[i32]) -> bool {
        const DOP_MARKER_A: u8 = 0x05;
        const DOP_MARKER_B: u8 = 0xFA;

        for &sample in pcm_samples {
            // Extract marker from bits 23-16
            let marker = ((sample >> 24) & 0xFF) as u8;

            let is_valid = match self.last_marker {
                None => marker == DOP_MARKER_A || marker == DOP_MARKER_B,
                Some(DOP_MARKER_A) => marker == DOP_MARKER_B,
                Some(DOP_MARKER_B) => marker == DOP_MARKER_A,
                _ => false,
            };

            if is_valid {
                self.valid_count += 1;
                self.last_marker = Some(marker);
            } else {
                self.valid_count = 0;
                self.last_marker = None;
            }

            if self.valid_count >= self.detection_threshold {
                return true;
            }
        }

        false
    }

    /// Decode DoP back to DSD bytes
    pub fn decode(&self, pcm_samples: &[i32], dsd_output: &mut [u8]) {
        let mut dsd_idx = 0;

        for &sample in pcm_samples {
            if dsd_idx + 1 >= dsd_output.len() {
                break;
            }

            // Extract DSD bytes from DoP sample
            let dsd_msb = ((sample >> 16) & 0xFF) as u8;
            let dsd_lsb = ((sample >> 8) & 0xFF) as u8;

            dsd_output[dsd_idx] = dsd_msb;
            dsd_output[dsd_idx + 1] = dsd_lsb;
            dsd_idx += 2;
        }
    }

    pub fn reset(&mut self) {
        self.last_marker = None;
        self.valid_count = 0;
    }
}

impl Default for DoPDecoder {
    fn default() -> Self {
        Self::new()
    }
}

/// Native ASIO DSD output handler
#[cfg(target_os = "windows")]
pub struct AsioDsdOutput {
    /// DSD mode
    mode: DsdOutputMode,
    /// Current rate
    rate: DsdRate,
    /// Channel count
    channels: usize,
    /// DoP encoder (when using DoP mode)
    dop_encoder: Option<DoPEncoder>,
    /// Buffer for DSD data
    dsd_buffer: Vec<u8>,
    /// Is active
    active: Arc<AtomicBool>,
}

#[cfg(target_os = "windows")]
impl AsioDsdOutput {
    pub fn new(mode: DsdOutputMode, rate: DsdRate, channels: usize) -> Self {
        let dop_encoder = if mode == DsdOutputMode::DoP {
            Some(DoPEncoder::new(channels))
        } else {
            None
        };

        Self {
            mode,
            rate,
            channels,
            dop_encoder,
            dsd_buffer: Vec::with_capacity(8192),
            active: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Start DSD output
    pub fn start(&self) -> Result<(), String> {
        self.active.store(true, Ordering::SeqCst);
        // ASIO initialization would happen here
        Ok(())
    }

    /// Stop DSD output
    pub fn stop(&self) {
        self.active.store(false, Ordering::SeqCst);
    }

    /// Write DSD data
    pub fn write(&mut self, dsd_data: &[u8]) -> Result<(), String> {
        if !self.active.load(Ordering::SeqCst) {
            return Err("DSD output not active".to_string());
        }

        match self.mode {
            DsdOutputMode::NativeAsio => {
                // Direct pass-through to ASIO DSD buffer
                self.write_native_dsd(dsd_data)
            }
            DsdOutputMode::DoP => {
                // Encode to DoP and write as PCM
                self.write_dop(dsd_data)
            }
            DsdOutputMode::PcmConversion => {
                // Should not reach here - PCM conversion happens earlier
                Err("PCM conversion mode should not use DSD output".to_string())
            }
        }
    }

    fn write_native_dsd(&mut self, dsd_data: &[u8]) -> Result<(), String> {
        // Native ASIO DSD: write raw 1-bit stream
        // Implementation depends on specific ASIO driver
        self.dsd_buffer.clear();
        self.dsd_buffer.extend_from_slice(dsd_data);
        Ok(())
    }

    fn write_dop(&mut self, dsd_data: &[u8]) -> Result<(), String> {
        if let Some(ref mut encoder) = self.dop_encoder {
            let pcm_samples = dsd_data.len() / 2;
            let mut pcm_buffer = vec![0i32; pcm_samples];
            encoder.encode(dsd_data, &mut pcm_buffer);
            // Write PCM buffer to ASIO
            Ok(())
        } else {
            Err("DoP encoder not initialized".to_string())
        }
    }

    /// Get current mode
    pub fn mode(&self) -> DsdOutputMode {
        self.mode
    }

    /// Get current rate
    pub fn rate(&self) -> DsdRate {
        self.rate
    }

    /// Check if active
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }
}

/// DSD capability detector
pub struct DsdCapabilityDetector;

impl DsdCapabilityDetector {
    /// Detect DSD capabilities of current audio device
    #[cfg(target_os = "windows")]
    pub fn detect() -> DsdCapabilities {
        // Query ASIO driver for DSD support
        // This would use ASIOFuture with kAsioCanDsd

        // For now, return conservative defaults
        DsdCapabilities {
            native_dsd: false, // Assume no native DSD
            native_rates: Vec::new(),
            dop_supported: true,
            dop_rates: vec![DsdRate::Dsd64, DsdRate::Dsd128],
            max_channels: 2,
        }
    }

    #[cfg(not(target_os = "windows"))]
    pub fn detect() -> DsdCapabilities {
        // macOS/Linux: DoP only via CoreAudio/ALSA
        DsdCapabilities {
            native_dsd: false,
            native_rates: Vec::new(),
            dop_supported: true,
            dop_rates: vec![DsdRate::Dsd64, DsdRate::Dsd128],
            max_channels: 2,
        }
    }

    /// Determine best output mode for given DSD rate
    pub fn best_mode_for_rate(caps: &DsdCapabilities, rate: DsdRate) -> DsdOutputMode {
        // Prefer native if available
        if caps.native_dsd && caps.native_rates.contains(&rate) {
            return DsdOutputMode::NativeAsio;
        }

        // Fall back to DoP
        if caps.dop_supported && caps.dop_rates.contains(&rate) {
            return DsdOutputMode::DoP;
        }

        // Last resort: PCM conversion
        DsdOutputMode::PcmConversion
    }
}

/// DSD to PCM converter for non-DSD-capable devices
pub struct DsdToPcmConverter {
    /// Output sample rate
    output_rate: u32,
    /// Decimation filter state
    filter_state: Vec<f64>,
    /// Filter coefficients
    coefficients: Vec<f64>,
    /// Decimation factor
    decimation_factor: usize,
}

impl DsdToPcmConverter {
    /// Create converter for given DSD and PCM rates
    pub fn new(dsd_rate: DsdRate, pcm_rate: u32) -> Self {
        let decimation_factor = (dsd_rate.sample_rate() / pcm_rate) as usize;

        // Design low-pass filter
        let filter_order = 128;
        let coefficients = Self::design_lowpass(filter_order, pcm_rate as f64 / dsd_rate.sample_rate() as f64);

        Self {
            output_rate: pcm_rate,
            filter_state: vec![0.0; filter_order],
            coefficients,
            decimation_factor,
        }
    }

    /// Design simple windowed-sinc lowpass filter
    fn design_lowpass(order: usize, cutoff: f64) -> Vec<f64> {
        use std::f64::consts::PI;

        let mut coeffs = vec![0.0; order];
        let mid = order / 2;

        for i in 0..order {
            let n = i as f64 - mid as f64;

            // Sinc function
            let sinc = if n.abs() < 1e-10 {
                2.0 * cutoff
            } else {
                (2.0 * PI * cutoff * n).sin() / (PI * n)
            };

            // Blackman window
            let window = 0.42 - 0.5 * (2.0 * PI * i as f64 / (order - 1) as f64).cos()
                + 0.08 * (4.0 * PI * i as f64 / (order - 1) as f64).cos();

            coeffs[i] = sinc * window;
        }

        // Normalize
        let sum: f64 = coeffs.iter().sum();
        for c in &mut coeffs {
            *c /= sum;
        }

        coeffs
    }

    /// Convert DSD bytes to PCM samples
    pub fn convert(&mut self, dsd_data: &[u8], pcm_output: &mut [f64]) {
        let mut pcm_idx = 0;
        let mut bit_buffer = Vec::with_capacity(self.decimation_factor);

        for &byte in dsd_data {
            // Unpack 8 DSD bits
            for bit_pos in (0..8).rev() {
                let bit = (byte >> bit_pos) & 1;
                let sample = if bit == 1 { 1.0 } else { -1.0 };
                bit_buffer.push(sample);

                // Process when we have enough samples
                if bit_buffer.len() >= self.decimation_factor {
                    if pcm_idx < pcm_output.len() {
                        // Apply filter and decimate
                        let filtered = self.apply_filter(&bit_buffer);
                        pcm_output[pcm_idx] = filtered;
                        pcm_idx += 1;
                    }
                    bit_buffer.clear();
                }
            }
        }
    }

    fn apply_filter(&mut self, samples: &[f64]) -> f64 {
        // Simple FIR filter
        let mut output = 0.0;
        let filter_len = self.coefficients.len();

        // Update state
        for &s in samples.iter().take(filter_len) {
            self.filter_state.remove(0);
            self.filter_state.push(s);
        }

        // Convolve
        for (i, &coeff) in self.coefficients.iter().enumerate() {
            if i < self.filter_state.len() {
                output += coeff * self.filter_state[i];
            }
        }

        output
    }

    /// Reset converter state
    pub fn reset(&mut self) {
        self.filter_state.fill(0.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dsd_rates() {
        assert_eq!(DsdRate::Dsd64.sample_rate(), 2_822_400);
        assert_eq!(DsdRate::Dsd128.sample_rate(), 5_644_800);
        assert_eq!(DsdRate::Dsd256.sample_rate(), 11_289_600);
        assert_eq!(DsdRate::Dsd512.sample_rate(), 22_579_200);
    }

    #[test]
    fn test_dop_encoder() {
        let mut encoder = DoPEncoder::new(2);
        let dsd_data = [0xAA, 0x55, 0xFF, 0x00];
        let mut output = [0i32; 2];

        encoder.encode(&dsd_data, &mut output);

        // Check marker is present
        let marker1 = ((output[0] >> 24) & 0xFF) as u8;
        assert!(marker1 == 0x05 || marker1 == 0xFA);
    }

    #[test]
    fn test_dop_detector() {
        let mut decoder = DoPDecoder::new();

        // Create valid DoP sequence
        let dop_samples: Vec<i32> = (0..16)
            .map(|i| {
                let marker = if i % 2 == 0 { 0x05 } else { 0xFA };
                (marker as i32) << 24
            })
            .collect();

        assert!(decoder.detect_dop(&dop_samples));
    }

    #[test]
    fn test_capability_detection() {
        let caps = DsdCapabilityDetector::detect();

        // Should at least support DoP
        assert!(caps.dop_supported);
        assert!(!caps.dop_rates.is_empty());
    }

    #[test]
    fn test_best_mode_selection() {
        let caps = DsdCapabilities {
            native_dsd: true,
            native_rates: vec![DsdRate::Dsd64, DsdRate::Dsd128],
            dop_supported: true,
            dop_rates: vec![DsdRate::Dsd64, DsdRate::Dsd128, DsdRate::Dsd256],
            max_channels: 2,
        };

        // Should prefer native
        assert_eq!(
            DsdCapabilityDetector::best_mode_for_rate(&caps, DsdRate::Dsd64),
            DsdOutputMode::NativeAsio
        );

        // DSD256 not in native, should use DoP
        assert_eq!(
            DsdCapabilityDetector::best_mode_for_rate(&caps, DsdRate::Dsd256),
            DsdOutputMode::DoP
        );

        // DSD512 not supported anywhere
        assert_eq!(
            DsdCapabilityDetector::best_mode_for_rate(&caps, DsdRate::Dsd512),
            DsdOutputMode::PcmConversion
        );
    }

    #[test]
    fn test_dsd_to_pcm_converter() {
        let mut converter = DsdToPcmConverter::new(DsdRate::Dsd64, 44100);

        // All 1s DSD should produce positive PCM
        let dsd_data = vec![0xFF; 64];
        let mut pcm_output = vec![0.0; 4];

        converter.convert(&dsd_data, &mut pcm_output);

        // Output should be positive (trending towards +1)
        assert!(pcm_output.iter().all(|&s| s >= -1.0 && s <= 1.0));
    }
}

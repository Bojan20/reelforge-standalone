//! DoP (DSD over PCM) Encoder/Decoder
//!
//! Standard for transmitting DSD audio over PCM interfaces.
//! Uses 24-bit PCM samples with 8-bit marker + 16 DSD bits.
//!
//! DoP Standard v1.1:
//! - Marker bytes: 0x05 (pattern A) and 0xFA (pattern B), alternating
//! - 16 DSD bits packed into lower 16 bits of 24-bit PCM
//! - MSB first bit ordering

use super::{DsdRate, DsdStream};
use rf_core::Sample;

/// DoP marker bytes per standard
pub const DOP_MARKER_A: u8 = 0x05;
pub const DOP_MARKER_B: u8 = 0xFA;

/// DoP alternate marker (some DACs)
pub const DOP_MARKER_ALT_A: u8 = 0x06;
pub const DOP_MARKER_ALT_B: u8 = 0xF9;

/// DoP encoding mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DopMode {
    /// Standard DoP v1.1 markers (0x05/0xFA)
    Standard,
    /// Alternative markers (0x06/0xF9)
    Alternative,
}

/// DoP encoder - converts DSD bits to PCM samples
pub struct DopEncoder {
    /// Marker toggle state
    marker_toggle: bool,
    /// Encoding mode
    mode: DopMode,
    /// DSD rate being encoded
    dsd_rate: DsdRate,
}

impl DopEncoder {
    /// Create new DoP encoder
    pub fn new(dsd_rate: DsdRate) -> Self {
        Self {
            marker_toggle: false,
            mode: DopMode::Standard,
            dsd_rate,
        }
    }

    /// Create with specific mode
    pub fn with_mode(dsd_rate: DsdRate, mode: DopMode) -> Self {
        Self {
            marker_toggle: false,
            mode,
            dsd_rate,
        }
    }

    /// Get current marker byte
    fn current_marker(&self) -> u8 {
        match (self.mode, self.marker_toggle) {
            (DopMode::Standard, false) => DOP_MARKER_A,
            (DopMode::Standard, true) => DOP_MARKER_B,
            (DopMode::Alternative, false) => DOP_MARKER_ALT_A,
            (DopMode::Alternative, true) => DOP_MARKER_ALT_B,
        }
    }

    /// Encode DSD bits to DoP PCM samples
    /// Takes 16 DSD bits, returns one 24-bit PCM sample (as i32)
    pub fn encode_sample(&mut self, dsd_bits: &[u8; 16]) -> i32 {
        let marker = self.current_marker();
        self.marker_toggle = !self.marker_toggle;

        // Pack 16 DSD bits into lower 16 bits
        let mut dsd_word: u16 = 0;
        for (i, &bit) in dsd_bits.iter().enumerate() {
            dsd_word |= ((bit & 1) as u16) << (15 - i);
        }

        // Combine marker and DSD data
        // Bits 23-16: marker, Bits 15-0: DSD data
        ((marker as i32) << 16) | (dsd_word as i32)
    }

    /// Encode DSD stream to DoP PCM
    pub fn encode(&mut self, dsd: &DsdStream) -> Vec<i32> {
        let bits_per_channel = dsd.samples_per_channel as usize;
        let num_samples = bits_per_channel / 16; // 16 DSD bits per PCM sample

        let mut output = Vec::with_capacity(num_samples * dsd.channels as usize);

        for ch in 0..dsd.channels {
            self.marker_toggle = false; // Reset per channel

            for sample_idx in 0..num_samples {
                let mut bits = [0u8; 16];

                for (i, bit) in bits.iter_mut().enumerate() {
                    let bit_idx = sample_idx * 16 + i;
                    *bit = dsd.get_bit(ch, bit_idx as u64).unwrap_or(0);
                }

                output.push(self.encode_sample(&bits));
            }
        }

        output
    }

    /// Encode DSD bytes directly (packed format)
    pub fn encode_packed(&mut self, dsd_bytes: &[u8]) -> Vec<i32> {
        // 2 bytes (16 bits) per DoP sample
        let num_samples = dsd_bytes.len() / 2;
        let mut output = Vec::with_capacity(num_samples);

        for chunk in dsd_bytes.chunks(2) {
            if chunk.len() < 2 {
                break;
            }

            let marker = self.current_marker();
            self.marker_toggle = !self.marker_toggle;

            // Two bytes become one DoP sample
            let dsd_word = ((chunk[0] as u16) << 8) | (chunk[1] as u16);
            output.push(((marker as i32) << 16) | (dsd_word as i32));
        }

        output
    }

    /// Get DoP output sample rate
    pub fn output_sample_rate(&self) -> u32 {
        // DoP runs at DSD_rate / 16
        self.dsd_rate.sample_rate() / 16
    }

    /// Reset encoder state
    pub fn reset(&mut self) {
        self.marker_toggle = false;
    }
}

/// DoP decoder - extracts DSD bits from PCM samples
pub struct DopDecoder {
    /// Expected marker for validation
    expected_marker_toggle: bool,
    /// Detected mode
    detected_mode: Option<DopMode>,
    /// Detected DSD rate
    detected_rate: Option<DsdRate>,
    /// Consecutive valid marker count
    valid_marker_count: usize,
    /// Minimum consecutive markers for detection
    detection_threshold: usize,
}

impl DopDecoder {
    /// Create new DoP decoder
    pub fn new() -> Self {
        Self {
            expected_marker_toggle: false,
            detected_mode: None,
            detected_rate: None,
            valid_marker_count: 0,
            detection_threshold: 8,
        }
    }

    /// Check if marker byte is valid DoP marker
    fn is_valid_marker(byte: u8, toggle: bool) -> Option<DopMode> {
        match (byte, toggle) {
            (DOP_MARKER_A, false) | (DOP_MARKER_B, true) => Some(DopMode::Standard),
            (DOP_MARKER_ALT_A, false) | (DOP_MARKER_ALT_B, true) => Some(DopMode::Alternative),
            _ => None,
        }
    }

    /// Detect DoP stream in PCM samples
    pub fn detect(&mut self, pcm: &[i32]) -> bool {
        self.valid_marker_count = 0;
        self.expected_marker_toggle = false;

        for &sample in pcm.iter().take(64) {
            let marker = ((sample >> 16) & 0xFF) as u8;

            if let Some(mode) = Self::is_valid_marker(marker, self.expected_marker_toggle) {
                self.valid_marker_count += 1;
                self.expected_marker_toggle = !self.expected_marker_toggle;

                if self.valid_marker_count >= self.detection_threshold {
                    self.detected_mode = Some(mode);
                    return true;
                }
            } else {
                // Reset on invalid marker
                self.valid_marker_count = 0;
                self.expected_marker_toggle = false;
            }
        }

        false
    }

    /// Detect DoP with rate estimation from PCM sample rate
    pub fn detect_with_rate(&mut self, pcm: &[i32], pcm_rate: u32) -> Option<DsdRate> {
        if !self.detect(pcm) {
            return None;
        }

        // DoP sample rate = DSD rate / 16
        let dsd_rate = pcm_rate * 16;
        self.detected_rate = DsdRate::from_sample_rate(dsd_rate);
        self.detected_rate
    }

    /// Decode DoP PCM sample to DSD bits
    pub fn decode_sample(&mut self, pcm: i32) -> Option<[u8; 16]> {
        let marker = ((pcm >> 16) & 0xFF) as u8;

        // Validate marker
        Self::is_valid_marker(marker, self.expected_marker_toggle)?;

        self.expected_marker_toggle = !self.expected_marker_toggle;

        // Extract 16 DSD bits
        let dsd_word = (pcm & 0xFFFF) as u16;
        let mut bits = [0u8; 16];

        for (i, bit) in bits.iter_mut().enumerate() {
            *bit = ((dsd_word >> (15 - i)) & 1) as u8;
        }

        Some(bits)
    }

    /// Decode DoP stream to DSD
    pub fn decode(&mut self, pcm: &[i32]) -> Option<Vec<u8>> {
        if self.detected_mode.is_none() && !self.detect(pcm) {
            return None;
        }

        self.expected_marker_toggle = false;
        let mut dsd_bits = Vec::with_capacity(pcm.len() * 16);

        for &sample in pcm {
            if let Some(bits) = self.decode_sample(sample) {
                dsd_bits.extend_from_slice(&bits);
            } else {
                // Invalid marker - might be end of DoP stream
                break;
            }
        }

        if dsd_bits.is_empty() {
            None
        } else {
            Some(dsd_bits)
        }
    }

    /// Decode to packed bytes (8 DSD bits per byte)
    pub fn decode_packed(&mut self, pcm: &[i32]) -> Option<Vec<u8>> {
        let bits = self.decode(pcm)?;

        // Pack bits into bytes
        let packed: Vec<u8> = bits
            .chunks(8)
            .map(|chunk| {
                let mut byte = 0u8;
                for (i, &bit) in chunk.iter().enumerate() {
                    byte |= (bit & 1) << (7 - i);
                }
                byte
            })
            .collect();

        Some(packed)
    }

    /// Get detected mode
    pub fn detected_mode(&self) -> Option<DopMode> {
        self.detected_mode
    }

    /// Get detected DSD rate
    pub fn detected_rate(&self) -> Option<DsdRate> {
        self.detected_rate
    }

    /// Reset decoder state
    pub fn reset(&mut self) {
        self.expected_marker_toggle = false;
        self.detected_mode = None;
        self.detected_rate = None;
        self.valid_marker_count = 0;
    }
}

impl Default for DopDecoder {
    fn default() -> Self {
        Self::new()
    }
}

/// Convert DoP PCM samples to normalized float for visualization
/// (Shows the DSD content, not the markers)
pub fn dop_to_float(pcm: &[i32]) -> Vec<Sample> {
    pcm.iter()
        .map(|&s| {
            // Extract DSD word, treat as 16-bit signed for visualization
            let dsd_word = (s & 0xFFFF) as i16;
            dsd_word as Sample / 32768.0
        })
        .collect()
}

/// Check if PCM buffer likely contains DoP
pub fn is_likely_dop(pcm: &[i32]) -> bool {
    let mut decoder = DopDecoder::new();
    decoder.detect(pcm)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dop_markers() {
        assert_eq!(DOP_MARKER_A, 0x05);
        assert_eq!(DOP_MARKER_B, 0xFA);
    }

    #[test]
    fn test_encoder_creation() {
        let encoder = DopEncoder::new(DsdRate::Dsd64);
        assert_eq!(encoder.output_sample_rate(), 176_400); // DSD64/16 = 176.4kHz
    }

    #[test]
    fn test_encode_decode_roundtrip() {
        let mut encoder = DopEncoder::new(DsdRate::Dsd64);
        let mut decoder = DopDecoder::new();

        // Create test DSD bits
        let dsd_bits: [u8; 16] = [1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 0, 1];

        // Encode
        let pcm = encoder.encode_sample(&dsd_bits);

        // Verify marker is present
        let marker = ((pcm >> 16) & 0xFF) as u8;
        assert_eq!(marker, DOP_MARKER_A);

        // Decode
        let decoded = decoder.decode_sample(pcm).unwrap();
        assert_eq!(decoded, dsd_bits);
    }

    #[test]
    fn test_marker_alternation() {
        let mut encoder = DopEncoder::new(DsdRate::Dsd64);
        let bits = [0u8; 16];

        let pcm1 = encoder.encode_sample(&bits);
        let pcm2 = encoder.encode_sample(&bits);
        let pcm3 = encoder.encode_sample(&bits);

        let marker1 = ((pcm1 >> 16) & 0xFF) as u8;
        let marker2 = ((pcm2 >> 16) & 0xFF) as u8;
        let marker3 = ((pcm3 >> 16) & 0xFF) as u8;

        assert_eq!(marker1, DOP_MARKER_A);
        assert_eq!(marker2, DOP_MARKER_B);
        assert_eq!(marker3, DOP_MARKER_A);
    }

    #[test]
    fn test_detection() {
        let mut encoder = DopEncoder::new(DsdRate::Dsd64);
        let mut decoder = DopDecoder::new();

        // Generate valid DoP stream
        let bits = [0u8; 16];
        let pcm: Vec<i32> = (0..64).map(|_| encoder.encode_sample(&bits)).collect();

        // Should detect as DoP
        assert!(decoder.detect(&pcm));
        assert_eq!(decoder.detected_mode(), Some(DopMode::Standard));
    }

    #[test]
    fn test_non_dop_detection() {
        let decoder = DopDecoder::new();

        // Random PCM data (not DoP)
        let pcm: Vec<i32> = (0..64).map(|i| i * 12345).collect();

        assert!(!is_likely_dop(&pcm));
    }

    #[test]
    fn test_packed_encode() {
        let mut encoder = DopEncoder::new(DsdRate::Dsd64);

        // 4 bytes = 32 bits = 2 DoP samples
        let dsd_bytes = [0xAA, 0x55, 0x0F, 0xF0];
        let pcm = encoder.encode_packed(&dsd_bytes);

        assert_eq!(pcm.len(), 2);

        // Verify markers
        let marker1 = ((pcm[0] >> 16) & 0xFF) as u8;
        let marker2 = ((pcm[1] >> 16) & 0xFF) as u8;
        assert_eq!(marker1, DOP_MARKER_A);
        assert_eq!(marker2, DOP_MARKER_B);

        // Verify DSD data
        let data1 = (pcm[0] & 0xFFFF) as u16;
        let data2 = (pcm[1] & 0xFFFF) as u16;
        assert_eq!(data1, 0xAA55);
        assert_eq!(data2, 0x0FF0);
    }

    #[test]
    fn test_rate_detection() {
        let mut encoder = DopEncoder::new(DsdRate::Dsd64);
        let mut decoder = DopDecoder::new();

        let bits = [0u8; 16];
        let pcm: Vec<i32> = (0..64).map(|_| encoder.encode_sample(&bits)).collect();

        // DoP at 176.4kHz = DSD64
        let rate = decoder.detect_with_rate(&pcm, 176_400);
        assert_eq!(rate, Some(DsdRate::Dsd64));
    }
}

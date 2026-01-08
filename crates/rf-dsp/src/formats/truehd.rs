//! Dolby TrueHD Passthrough
//!
//! UNIQUE: Bitstream passthrough for Dolby TrueHD/Atmos content.
//!
//! Note: TrueHD decoding requires licensed Dolby decoder.
//! This implementation provides detection and passthrough only.

use std::collections::VecDeque;

/// TrueHD stream info
#[derive(Debug, Clone)]
pub struct TrueHdInfo {
    /// Valid TrueHD stream detected
    pub valid: bool,
    /// Sample rate
    pub sample_rate: u32,
    /// Channel count
    pub channels: u8,
    /// Bit depth
    pub bit_depth: u8,
    /// Has Atmos metadata
    pub has_atmos: bool,
    /// Peak data rate (kbps)
    pub peak_rate_kbps: u32,
}

impl Default for TrueHdInfo {
    fn default() -> Self {
        Self {
            valid: false,
            sample_rate: 48000,
            channels: 2,
            bit_depth: 24,
            has_atmos: false,
            peak_rate_kbps: 0,
        }
    }
}

/// TrueHD sync word
const TRUEHD_SYNC_WORD: u32 = 0xF8726FBA;

/// TrueHD major sync info
#[derive(Debug, Clone, Default)]
pub struct TrueHdMajorSync {
    pub format_sync: u32,
    pub format_info: u8,
    pub sample_rate_code: u8,
    pub channel_assignment: u16,
    pub peak_bitrate: u16,
    pub substream_info: u8,
}

/// TrueHD detector and passthrough handler
pub struct TrueHdHandler {
    /// Detection buffer
    buffer: VecDeque<u8>,
    /// Detected stream info
    info: TrueHdInfo,
    /// Is passthrough active
    passthrough_active: bool,
    /// Frame buffer for passthrough
    frame_buffer: Vec<u8>,
    /// Current frame size
    current_frame_size: usize,
    /// Bytes collected for current frame
    frame_bytes_collected: usize,
}

impl TrueHdHandler {
    /// Create new handler
    pub fn new() -> Self {
        Self {
            buffer: VecDeque::with_capacity(8192),
            info: TrueHdInfo::default(),
            passthrough_active: false,
            frame_buffer: vec![0; 61440], // Max TrueHD frame size
            current_frame_size: 0,
            frame_bytes_collected: 0,
        }
    }

    /// Feed data for detection
    pub fn feed(&mut self, data: &[u8]) {
        for &byte in data {
            self.buffer.push_back(byte);
            if self.buffer.len() > 8192 {
                self.buffer.pop_front();
            }
        }
    }

    /// Detect TrueHD stream
    pub fn detect(&mut self) -> bool {
        if self.buffer.len() < 32 {
            return false;
        }

        // Look for sync word
        let sync_pos = self.find_sync_word();

        if let Some(pos) = sync_pos {
            // Parse major sync
            if let Some(major_sync) = self.parse_major_sync(pos) {
                self.info = self.decode_info(&major_sync);
                self.info.valid = true;
                return true;
            }
        }

        false
    }

    /// Find TrueHD sync word in buffer
    fn find_sync_word(&self) -> Option<usize> {
        if self.buffer.len() < 4 {
            return None;
        }

        for i in 0..self.buffer.len() - 3 {
            let word = ((self.buffer[i] as u32) << 24)
                | ((self.buffer[i + 1] as u32) << 16)
                | ((self.buffer[i + 2] as u32) << 8)
                | (self.buffer[i + 3] as u32);

            if word == TRUEHD_SYNC_WORD {
                return Some(i);
            }
        }

        None
    }

    /// Parse major sync header
    fn parse_major_sync(&self, pos: usize) -> Option<TrueHdMajorSync> {
        if pos + 28 > self.buffer.len() {
            return None;
        }

        // TrueHD major sync format (simplified)
        let mut sync = TrueHdMajorSync::default();

        // Read sync word (already verified)
        sync.format_sync = TRUEHD_SYNC_WORD;

        // Format info at offset +4
        sync.format_info = self.buffer[pos + 4];

        // Sample rate code at offset +8
        sync.sample_rate_code = (self.buffer[pos + 8] >> 4) & 0x0F;

        // Channel assignment at offset +11-12
        sync.channel_assignment =
            ((self.buffer[pos + 11] as u16) << 8) | (self.buffer[pos + 12] as u16);

        // Peak bitrate at offset +14-15
        sync.peak_bitrate = ((self.buffer[pos + 14] as u16) << 8) | (self.buffer[pos + 15] as u16);

        // Substream info at offset +18
        sync.substream_info = self.buffer[pos + 18];

        Some(sync)
    }

    /// Decode stream info from major sync
    fn decode_info(&self, sync: &TrueHdMajorSync) -> TrueHdInfo {
        // Sample rate decoding
        let sample_rate = match sync.sample_rate_code {
            0 => 48000,
            1 => 96000,
            2 => 192000,
            8 => 44100,
            9 => 88200,
            10 => 176400,
            _ => 48000,
        };

        // Channel count from assignment (simplified)
        let channels = self.count_channels(sync.channel_assignment);

        // Check for Atmos (object audio metadata)
        let has_atmos = (sync.substream_info & 0x80) != 0;

        // Peak bitrate in kbps
        let peak_rate_kbps = sync.peak_bitrate as u32 * 8;

        TrueHdInfo {
            valid: true,
            sample_rate,
            channels,
            bit_depth: 24, // TrueHD is always 24-bit
            has_atmos,
            peak_rate_kbps,
        }
    }

    /// Count channels from channel assignment
    fn count_channels(&self, assignment: u16) -> u8 {
        // TrueHD channel assignment is a bitmask
        let mut count = 0;

        // Standard channel positions
        if assignment & 0x0001 != 0 {
            count += 2; // L/R
        }
        if assignment & 0x0002 != 0 {
            count += 1; // C
        }
        if assignment & 0x0004 != 0 {
            count += 1; // LFE
        }
        if assignment & 0x0008 != 0 {
            count += 2; // Ls/Rs
        }
        if assignment & 0x0010 != 0 {
            count += 2; // Lrs/Rrs (rear surround)
        }
        if assignment & 0x0020 != 0 {
            count += 2; // Lw/Rw (wide)
        }
        if assignment & 0x0040 != 0 {
            count += 2; // Ltf/Rtf (top front)
        }
        if assignment & 0x0080 != 0 {
            count += 2; // Ltr/Rtr (top rear)
        }

        count.max(2) // At least stereo
    }

    /// Get stream info
    pub fn info(&self) -> &TrueHdInfo {
        &self.info
    }

    /// Enable passthrough mode
    pub fn enable_passthrough(&mut self) {
        self.passthrough_active = true;
    }

    /// Disable passthrough mode
    pub fn disable_passthrough(&mut self) {
        self.passthrough_active = false;
    }

    /// Is passthrough active
    pub fn is_passthrough_active(&self) -> bool {
        self.passthrough_active
    }

    /// Process frame for passthrough
    ///
    /// Returns data to send to HDMI/S/PDIF output
    pub fn process_passthrough(&mut self, input: &[u8]) -> Option<Vec<u8>> {
        if !self.passthrough_active || !self.info.valid {
            return None;
        }

        // Accumulate frame data
        for &byte in input {
            if self.frame_bytes_collected < self.frame_buffer.len() {
                self.frame_buffer[self.frame_bytes_collected] = byte;
                self.frame_bytes_collected += 1;
            }
        }

        // Check for complete frame
        if self.frame_bytes_collected >= self.current_frame_size && self.current_frame_size > 0 {
            let frame = self.frame_buffer[..self.current_frame_size].to_vec();
            self.frame_bytes_collected = 0;

            // Wrap in IEC 61937 for S/PDIF/HDMI
            Some(self.wrap_iec61937(&frame))
        } else {
            None
        }
    }

    /// Wrap TrueHD frame in IEC 61937 burst
    fn wrap_iec61937(&self, frame: &[u8]) -> Vec<u8> {
        // IEC 61937 header
        const SYNC_WORD_1: u16 = 0xF872;
        const SYNC_WORD_2: u16 = 0x4E1F;
        const DATA_TYPE_TRUEHD: u16 = 0x0016; // TrueHD with MAT

        let frame_len = frame.len();
        let burst_len = frame_len + 8; // Header + data
        let padded_len = ((burst_len + 3) / 4) * 4; // Align to 4 bytes

        let mut output = vec![0u8; padded_len];

        // Sync words
        output[0] = (SYNC_WORD_1 >> 8) as u8;
        output[1] = (SYNC_WORD_1 & 0xFF) as u8;
        output[2] = (SYNC_WORD_2 >> 8) as u8;
        output[3] = (SYNC_WORD_2 & 0xFF) as u8;

        // Data type
        output[4] = (DATA_TYPE_TRUEHD >> 8) as u8;
        output[5] = (DATA_TYPE_TRUEHD & 0xFF) as u8;

        // Length in bits
        let length_bits = (frame_len * 8) as u16;
        output[6] = (length_bits >> 8) as u8;
        output[7] = (length_bits & 0xFF) as u8;

        // Copy frame data
        output[8..8 + frame_len].copy_from_slice(frame);

        output
    }

    /// Reset handler
    pub fn reset(&mut self) {
        self.buffer.clear();
        self.info = TrueHdInfo::default();
        self.frame_bytes_collected = 0;
        self.current_frame_size = 0;
    }
}

impl Default for TrueHdHandler {
    fn default() -> Self {
        Self::new()
    }
}

/// MAT (Metadata-enhanced Audio Transmission) wrapper for TrueHD
///
/// Required for HDMI transmission of TrueHD
pub struct MatWrapper {
    /// MAT frame buffer
    mat_frame: Vec<u8>,
    /// Current position in MAT frame
    position: usize,
    /// MAT frame size (61440 bytes for TrueHD)
    frame_size: usize,
}

impl MatWrapper {
    /// MAT frame size constant
    const MAT_FRAME_SIZE: usize = 61440;

    /// Create new MAT wrapper
    pub fn new() -> Self {
        Self {
            mat_frame: vec![0; Self::MAT_FRAME_SIZE],
            position: 0,
            frame_size: Self::MAT_FRAME_SIZE,
        }
    }

    /// Add TrueHD access unit to MAT frame
    pub fn add_access_unit(&mut self, au: &[u8]) -> Option<Vec<u8>> {
        if self.position + au.len() > self.frame_size {
            // Frame complete, return it and start new one
            let complete_frame = self.mat_frame[..self.position].to_vec();
            self.position = 0;
            self.mat_frame.fill(0);

            // Add this AU to new frame
            self.mat_frame[..au.len()].copy_from_slice(au);
            self.position = au.len();

            Some(complete_frame)
        } else {
            // Add to current frame
            self.mat_frame[self.position..self.position + au.len()].copy_from_slice(au);
            self.position += au.len();
            None
        }
    }

    /// Flush remaining data
    pub fn flush(&mut self) -> Option<Vec<u8>> {
        if self.position > 0 {
            let frame = self.mat_frame[..self.position].to_vec();
            self.position = 0;
            self.mat_frame.fill(0);
            Some(frame)
        } else {
            None
        }
    }

    /// Reset wrapper
    pub fn reset(&mut self) {
        self.position = 0;
        self.mat_frame.fill(0);
    }
}

impl Default for MatWrapper {
    fn default() -> Self {
        Self::new()
    }
}

/// TrueHD/Atmos passthrough controller
pub struct AtmosPassthrough {
    /// Handler
    handler: TrueHdHandler,
    /// MAT wrapper
    mat_wrapper: MatWrapper,
    /// Output sample rate (for HDMI timing)
    output_rate: u32,
}

impl AtmosPassthrough {
    /// Create new passthrough controller
    pub fn new() -> Self {
        Self {
            handler: TrueHdHandler::new(),
            mat_wrapper: MatWrapper::new(),
            output_rate: 192000, // TrueHD requires 192kHz carrier
        }
    }

    /// Process input data
    pub fn process(&mut self, input: &[u8]) -> Vec<Vec<u8>> {
        let mut output_frames = Vec::new();

        // Feed to handler
        self.handler.feed(input);

        // Detect if not already valid
        if !self.handler.info().valid {
            self.handler.detect();
        }

        // Process passthrough
        if let Some(frame) = self.handler.process_passthrough(input) {
            // Wrap in MAT
            if let Some(mat_frame) = self.mat_wrapper.add_access_unit(&frame) {
                output_frames.push(mat_frame);
            }
        }

        output_frames
    }

    /// Get stream info
    pub fn info(&self) -> &TrueHdInfo {
        self.handler.info()
    }

    /// Enable passthrough
    pub fn enable(&mut self) {
        self.handler.enable_passthrough();
    }

    /// Disable passthrough
    pub fn disable(&mut self) {
        self.handler.disable_passthrough();
    }

    /// Is Atmos content detected
    pub fn is_atmos(&self) -> bool {
        self.handler.info().has_atmos
    }

    /// Reset
    pub fn reset(&mut self) {
        self.handler.reset();
        self.mat_wrapper.reset();
    }
}

impl Default for AtmosPassthrough {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_handler_creation() {
        let handler = TrueHdHandler::new();
        assert!(!handler.info().valid);
        assert!(!handler.is_passthrough_active());
    }

    #[test]
    fn test_sync_word_detection() {
        let mut handler = TrueHdHandler::new();

        // Create data with sync word
        let mut data = vec![0u8; 100];
        data[20] = 0xF8;
        data[21] = 0x72;
        data[22] = 0x6F;
        data[23] = 0xBA;

        handler.feed(&data);

        // Should find sync word
        let pos = handler.find_sync_word();
        assert_eq!(pos, Some(20));
    }

    #[test]
    fn test_channel_counting() {
        let handler = TrueHdHandler::new();

        // Stereo only
        assert_eq!(handler.count_channels(0x0001), 2);

        // 5.1 (L/R + C + LFE + Ls/Rs)
        assert_eq!(handler.count_channels(0x000F), 6);

        // 7.1 (5.1 + Lrs/Rrs)
        assert_eq!(handler.count_channels(0x001F), 8);
    }

    #[test]
    fn test_iec61937_wrapping() {
        let handler = TrueHdHandler::new();

        let frame = vec![0xAA; 100];
        let wrapped = handler.wrap_iec61937(&frame);

        // Check sync words
        assert_eq!(wrapped[0], 0xF8);
        assert_eq!(wrapped[1], 0x72);
        assert_eq!(wrapped[2], 0x4E);
        assert_eq!(wrapped[3], 0x1F);

        // Check data type (TrueHD)
        assert_eq!(wrapped[4], 0x00);
        assert_eq!(wrapped[5], 0x16);
    }

    #[test]
    fn test_mat_wrapper() {
        let mut wrapper = MatWrapper::new();

        // Add small AU
        let au = vec![0xBB; 1000];
        let result = wrapper.add_access_unit(&au);
        assert!(result.is_none()); // Frame not complete

        // Flush should return partial frame
        let flushed = wrapper.flush();
        assert!(flushed.is_some());
        assert_eq!(flushed.unwrap().len(), 1000);
    }

    #[test]
    fn test_atmos_passthrough() {
        let mut passthrough = AtmosPassthrough::new();

        // Should start disabled
        assert!(!passthrough.info().valid);

        passthrough.enable();

        // Process some data (won't produce output without valid TrueHD stream)
        let data = vec![0; 1000];
        let output = passthrough.process(&data);
        assert!(output.is_empty());
    }

    #[test]
    fn test_sample_rate_decode() {
        let handler = TrueHdHandler::new();

        let sync = TrueHdMajorSync {
            sample_rate_code: 0,
            ..Default::default()
        };
        let info = handler.decode_info(&sync);
        assert_eq!(info.sample_rate, 48000);

        let sync_96 = TrueHdMajorSync {
            sample_rate_code: 1,
            ..Default::default()
        };
        let info_96 = handler.decode_info(&sync_96);
        assert_eq!(info_96.sample_rate, 96000);
    }
}

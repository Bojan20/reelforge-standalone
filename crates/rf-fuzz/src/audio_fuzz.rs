//! Audio parser fuzz targets
//!
//! Generates malformed audio file data (WAV, FLAC) to test parser robustness.
//! Tests boundary conditions, corrupted headers, truncated files, and extreme values.

use crate::config::FuzzConfig;
use crate::generators::InputGenerator;
use crate::harness::{FuzzResult, FuzzRunner};
use crate::report::FuzzReport;

// ============================================================================
// WAV format constants
// ============================================================================

/// Standard RIFF/WAVE magic bytes
const RIFF_MAGIC: &[u8; 4] = b"RIFF";
const WAVE_MAGIC: &[u8; 4] = b"WAVE";
const FMT_CHUNK_ID: &[u8; 4] = b"fmt ";
const DATA_CHUNK_ID: &[u8; 4] = b"data";

/// WAV audio format codes
const WAV_FORMAT_PCM: u16 = 1;
const WAV_FORMAT_IEEE_FLOAT: u16 = 3;
const WAV_FORMAT_ALAW: u16 = 6;
const WAV_FORMAT_MULAW: u16 = 7;
const WAV_FORMAT_EXTENSIBLE: u16 = 0xFFFE;

// ============================================================================
// FLAC format constants
// ============================================================================

/// FLAC stream marker
const FLAC_MARKER: &[u8; 4] = b"fLaC";

/// FLAC metadata block types
const FLAC_STREAMINFO: u8 = 0;
const FLAC_PADDING: u8 = 1;
#[allow(dead_code)]
const FLAC_APPLICATION: u8 = 2;
#[allow(dead_code)]
const FLAC_SEEKTABLE: u8 = 3;
#[allow(dead_code)]
const FLAC_VORBIS_COMMENT: u8 = 4;
#[allow(dead_code)]
const FLAC_CUESHEET: u8 = 5;
#[allow(dead_code)]
const FLAC_PICTURE: u8 = 6;

// ============================================================================
// WAV header generator
// ============================================================================

/// Generates a WAV file header (potentially malformed) from fuzz inputs.
///
/// The generated header follows the RIFF/WAVE structure but with values
/// sourced from the `InputGenerator`, which can produce edge cases and
/// boundary values to stress-test parsers.
pub struct WavHeaderGenerator;

impl WavHeaderGenerator {
    /// Generate a well-formed WAV header with the given parameters.
    pub fn valid_header(
        sample_rate: u32,
        channels: u16,
        bits_per_sample: u16,
        data_size: u32,
    ) -> Vec<u8> {
        let block_align = channels * (bits_per_sample / 8);
        let byte_rate = sample_rate * block_align as u32;
        let file_size = 36 + data_size;

        let mut buf = Vec::with_capacity(44);
        // RIFF header
        buf.extend_from_slice(RIFF_MAGIC);
        buf.extend_from_slice(&file_size.to_le_bytes());
        buf.extend_from_slice(WAVE_MAGIC);
        // fmt chunk
        buf.extend_from_slice(FMT_CHUNK_ID);
        buf.extend_from_slice(&16u32.to_le_bytes()); // chunk size
        buf.extend_from_slice(&WAV_FORMAT_PCM.to_le_bytes());
        buf.extend_from_slice(&channels.to_le_bytes());
        buf.extend_from_slice(&sample_rate.to_le_bytes());
        buf.extend_from_slice(&byte_rate.to_le_bytes());
        buf.extend_from_slice(&block_align.to_le_bytes());
        buf.extend_from_slice(&bits_per_sample.to_le_bytes());
        // data chunk
        buf.extend_from_slice(DATA_CHUNK_ID);
        buf.extend_from_slice(&data_size.to_le_bytes());

        buf
    }

    /// Generate a WAV header with fuzzed field values.
    ///
    /// Randomly corrupts individual fields while keeping the overall
    /// RIFF structure recognizable so parsers attempt to process it.
    pub fn fuzzed_header(gen: &mut InputGenerator) -> Vec<u8> {
        let corruption = gen.u32() % 16;

        match corruption {
            0 => Self::corrupted_magic(gen),
            1 => Self::corrupted_file_size(gen),
            2 => Self::corrupted_format_code(gen),
            3 => Self::corrupted_sample_rate(gen),
            4 => Self::corrupted_channels(gen),
            5 => Self::corrupted_bits_per_sample(gen),
            6 => Self::corrupted_chunk_size(gen),
            7 => Self::truncated_header(gen),
            8 => Self::zero_length_data(gen),
            9 => Self::max_length_data(gen),
            10 => Self::mismatched_block_align(gen),
            11 => Self::missing_wave_marker(gen),
            12 => Self::missing_fmt_chunk(gen),
            13 => Self::extra_bytes_in_fmt(gen),
            14 => Self::ieee_float_format(gen),
            15 => Self::extensible_format(gen),
            _ => Self::valid_header(44100, 2, 16, 1024),
        }
    }

    /// Corrupt the RIFF or WAVE magic bytes.
    fn corrupted_magic(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        if gen.bool() {
            // Corrupt RIFF magic (bytes 0-3)
            let pos = gen.u32() as usize % 4;
            header[pos] = gen.u32() as u8;
        } else {
            // Corrupt WAVE magic (bytes 8-11)
            let pos = 8 + (gen.u32() as usize % 4);
            header[pos] = gen.u32() as u8;
        }
        header
    }

    /// Set the file size field to an extreme or invalid value.
    fn corrupted_file_size(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        let bad_size = match gen.u32() % 5 {
            0 => 0u32,
            1 => 1u32,
            2 => u32::MAX,
            3 => u32::MAX - 1,
            _ => gen.u32(),
        };
        header[4..8].copy_from_slice(&bad_size.to_le_bytes());
        header
    }

    /// Use an invalid or unusual audio format code.
    fn corrupted_format_code(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        let bad_format: u16 = match gen.u32() % 6 {
            0 => 0,                // invalid
            1 => 2,                // ADPCM
            2 => 0xFF,             // unknown
            3 => u16::MAX,         // max
            4 => WAV_FORMAT_ALAW,  // A-law
            _ => WAV_FORMAT_MULAW, // mu-law
        };
        header[20..22].copy_from_slice(&bad_format.to_le_bytes());
        header
    }

    /// Set sample rate to an extreme or zero value.
    fn corrupted_sample_rate(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        let bad_rate: u32 = match gen.u32() % 6 {
            0 => 0,
            1 => 1,
            2 => u32::MAX,
            3 => 384001, // above max supported
            4 => 7,      // absurdly low
            _ => gen.u32(),
        };
        header[24..28].copy_from_slice(&bad_rate.to_le_bytes());
        header
    }

    /// Set channel count to an extreme value.
    fn corrupted_channels(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        let bad_channels: u16 = match gen.u32() % 5 {
            0 => 0,
            1 => 1,
            2 => 255,
            3 => u16::MAX,
            _ => gen.u32() as u16,
        };
        header[22..24].copy_from_slice(&bad_channels.to_le_bytes());
        header
    }

    /// Set bits per sample to an unusual value.
    fn corrupted_bits_per_sample(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        let bad_bps: u16 = match gen.u32() % 6 {
            0 => 0,
            1 => 1,
            2 => 3,  // odd, not byte-aligned
            3 => 7,  // not byte-aligned
            4 => 48, // unusually high
            _ => u16::MAX,
        };
        header[34..36].copy_from_slice(&bad_bps.to_le_bytes());
        header
    }

    /// Set the fmt chunk size to a wrong value.
    fn corrupted_chunk_size(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        let bad_chunk_size: u32 = match gen.u32() % 4 {
            0 => 0,
            1 => u32::MAX,
            2 => 15,   // one byte short
            _ => 1000, // way too large
        };
        header[16..20].copy_from_slice(&bad_chunk_size.to_le_bytes());
        header
    }

    /// Truncate the header at various points.
    fn truncated_header(gen: &mut InputGenerator) -> Vec<u8> {
        let full = Self::valid_header(44100, 2, 16, 1024);
        let truncate_at = match gen.u32() % 7 {
            0 => 0,  // empty
            1 => 1,  // single byte
            2 => 4,  // just RIFF
            3 => 12, // RIFF + WAVE, no fmt
            4 => 20, // partial fmt
            5 => 36, // no data chunk
            _ => gen.u32() as usize % full.len(),
        };
        full[..truncate_at.min(full.len())].to_vec()
    }

    /// Data chunk claims zero length.
    fn zero_length_data(_gen: &mut InputGenerator) -> Vec<u8> {
        Self::valid_header(44100, 2, 16, 0)
    }

    /// Data chunk claims maximum possible length.
    fn max_length_data(_gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 0);
        // Overwrite data size with u32::MAX
        let data_size_offset = 40;
        header[data_size_offset..data_size_offset + 4].copy_from_slice(&u32::MAX.to_le_bytes());
        header
    }

    /// Block align doesn't match channels * (bits / 8).
    fn mismatched_block_align(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        let bad_align: u16 = match gen.u32() % 4 {
            0 => 0,
            1 => 1, // should be 4 for stereo 16-bit
            2 => 255,
            _ => gen.u32() as u16,
        };
        header[32..34].copy_from_slice(&bad_align.to_le_bytes());
        header
    }

    /// Valid RIFF header but missing WAVE marker.
    fn missing_wave_marker(_gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 16, 1024);
        // Replace WAVE with garbage
        header[8..12].copy_from_slice(b"JUNK");
        header
    }

    /// Skip the fmt chunk entirely, go straight to data.
    fn missing_fmt_chunk(_gen: &mut InputGenerator) -> Vec<u8> {
        let data_size: u32 = 1024;
        let file_size = 4 + 8 + data_size; // WAVE + data chunk header + data
        let mut buf = Vec::with_capacity(20 + data_size as usize);
        buf.extend_from_slice(RIFF_MAGIC);
        buf.extend_from_slice(&file_size.to_le_bytes());
        buf.extend_from_slice(WAVE_MAGIC);
        buf.extend_from_slice(DATA_CHUNK_ID);
        buf.extend_from_slice(&data_size.to_le_bytes());
        // No actual data bytes appended — just the header
        buf
    }

    /// fmt chunk has extra trailing bytes beyond the standard 16.
    fn extra_bytes_in_fmt(gen: &mut InputGenerator) -> Vec<u8> {
        let block_align: u16 = 4;
        let byte_rate: u32 = 44100 * 4;
        let extra_len = (gen.u32() % 64) as usize;
        let fmt_size = 16u32 + extra_len as u32;
        let data_size: u32 = 1024;
        let file_size = 4 + (8 + fmt_size) + (8 + data_size);

        let mut buf = Vec::new();
        buf.extend_from_slice(RIFF_MAGIC);
        buf.extend_from_slice(&file_size.to_le_bytes());
        buf.extend_from_slice(WAVE_MAGIC);
        buf.extend_from_slice(FMT_CHUNK_ID);
        buf.extend_from_slice(&fmt_size.to_le_bytes());
        buf.extend_from_slice(&WAV_FORMAT_PCM.to_le_bytes());
        buf.extend_from_slice(&2u16.to_le_bytes()); // channels
        buf.extend_from_slice(&44100u32.to_le_bytes());
        buf.extend_from_slice(&byte_rate.to_le_bytes());
        buf.extend_from_slice(&block_align.to_le_bytes());
        buf.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
                                                     // Extra random bytes
        let extra: Vec<u8> = (0..extra_len).map(|_| gen.u32() as u8).collect();
        buf.extend_from_slice(&extra);
        buf.extend_from_slice(DATA_CHUNK_ID);
        buf.extend_from_slice(&data_size.to_le_bytes());
        buf
    }

    /// WAV with IEEE float format code.
    fn ieee_float_format(gen: &mut InputGenerator) -> Vec<u8> {
        let mut header = Self::valid_header(44100, 2, 32, 2048);
        // Set format to IEEE float
        header[20..22].copy_from_slice(&WAV_FORMAT_IEEE_FLOAT.to_le_bytes());
        // Optionally corrupt the bits_per_sample
        if gen.bool() {
            let bad_bps: u16 = match gen.u32() % 3 {
                0 => 16, // wrong for float
                1 => 24, // wrong for float
                _ => 64, // double precision
            };
            header[34..36].copy_from_slice(&bad_bps.to_le_bytes());
        }
        header
    }

    /// WAV with EXTENSIBLE format header.
    fn extensible_format(gen: &mut InputGenerator) -> Vec<u8> {
        let fmt_size = 40u32; // 16 base + 22 extensible + 2 cbSize
        let data_size: u32 = 512;
        let file_size = 4 + (8 + fmt_size) + (8 + data_size);

        let mut buf = Vec::new();
        buf.extend_from_slice(RIFF_MAGIC);
        buf.extend_from_slice(&file_size.to_le_bytes());
        buf.extend_from_slice(WAVE_MAGIC);
        buf.extend_from_slice(FMT_CHUNK_ID);
        buf.extend_from_slice(&fmt_size.to_le_bytes());
        buf.extend_from_slice(&WAV_FORMAT_EXTENSIBLE.to_le_bytes());
        buf.extend_from_slice(&2u16.to_le_bytes()); // channels
        buf.extend_from_slice(&48000u32.to_le_bytes()); // sample rate
        buf.extend_from_slice(&(48000u32 * 4).to_le_bytes()); // byte rate
        buf.extend_from_slice(&4u16.to_le_bytes()); // block align
        buf.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
        buf.extend_from_slice(&22u16.to_le_bytes()); // cbSize
                                                     // Valid bits per sample (may be corrupted)
        let valid_bps: u16 = if gen.bool() { 16 } else { gen.u32() as u16 };
        buf.extend_from_slice(&valid_bps.to_le_bytes());
        // Channel mask
        buf.extend_from_slice(&gen.u32().to_le_bytes());
        // SubFormat GUID (16 bytes) — random
        for _ in 0..16 {
            buf.push(gen.u32() as u8);
        }
        buf.extend_from_slice(DATA_CHUNK_ID);
        buf.extend_from_slice(&data_size.to_le_bytes());
        buf
    }
}

// ============================================================================
// FLAC header generator
// ============================================================================

/// Generates FLAC stream data (potentially malformed) for parser fuzzing.
pub struct FlacHeaderGenerator;

impl FlacHeaderGenerator {
    /// Generate a valid FLAC STREAMINFO metadata block.
    pub fn valid_streaminfo(
        sample_rate: u32,
        channels: u8,
        bits_per_sample: u8,
        total_samples: u64,
    ) -> Vec<u8> {
        let mut buf = Vec::with_capacity(42);
        // fLaC marker
        buf.extend_from_slice(FLAC_MARKER);
        // Metadata block header: last=1, type=STREAMINFO, length=34
        let header_byte = 0x80 | FLAC_STREAMINFO; // last block flag set
        buf.push(header_byte);
        buf.extend_from_slice(&[0x00, 0x00, 0x22]); // length = 34

        // STREAMINFO block (34 bytes)
        buf.extend_from_slice(&4096u16.to_be_bytes()); // min block size
        buf.extend_from_slice(&4096u16.to_be_bytes()); // max block size
        buf.extend_from_slice(&[0x00, 0x00, 0x00]); // min frame size (24-bit)
        buf.extend_from_slice(&[0x00, 0x00, 0x00]); // max frame size (24-bit)

        // Sample rate (20 bits), channels-1 (3 bits), bps-1 (5 bits), total samples (36 bits)
        // Pack into 8 bytes
        let sr = sample_rate & 0xFFFFF;
        let ch = ((channels.saturating_sub(1)) & 0x07) as u32;
        let bps = ((bits_per_sample.saturating_sub(1)) & 0x1F) as u32;
        let ts = total_samples & 0xFFFFFFFFF;

        let packed: u64 = ((sr as u64) << 44) | ((ch as u64) << 41) | ((bps as u64) << 36) | ts;
        buf.extend_from_slice(&packed.to_be_bytes());

        // MD5 signature (16 bytes of zeros)
        buf.extend_from_slice(&[0u8; 16]);

        buf
    }

    /// Generate a FLAC stream with fuzzed metadata.
    pub fn fuzzed_stream(gen: &mut InputGenerator) -> Vec<u8> {
        let corruption = gen.u32() % 10;

        match corruption {
            0 => Self::corrupted_marker(gen),
            1 => Self::corrupted_streaminfo(gen),
            2 => Self::invalid_block_type(gen),
            3 => Self::oversized_block_length(gen),
            4 => Self::zero_sample_rate(gen),
            5 => Self::extreme_channels(gen),
            6 => Self::truncated_stream(gen),
            7 => Self::missing_streaminfo(gen),
            8 => Self::multiple_streaminfo(gen),
            9 => Self::corrupted_md5(gen),
            _ => Self::valid_streaminfo(44100, 2, 16, 44100 * 60),
        }
    }

    /// Corrupt the fLaC magic marker.
    fn corrupted_marker(gen: &mut InputGenerator) -> Vec<u8> {
        let mut stream = Self::valid_streaminfo(44100, 2, 16, 44100);
        let pos = gen.u32() as usize % 4;
        stream[pos] = gen.u32() as u8;
        stream
    }

    /// Corrupt individual fields within the STREAMINFO block.
    fn corrupted_streaminfo(gen: &mut InputGenerator) -> Vec<u8> {
        let mut stream = Self::valid_streaminfo(44100, 2, 16, 44100);
        // Corrupt random bytes in the STREAMINFO data (bytes 8..42)
        let num_corruptions = (gen.u32() % 8) + 1;
        for _ in 0..num_corruptions {
            let pos = 8 + (gen.u32() as usize % 34);
            if pos < stream.len() {
                stream[pos] = gen.u32() as u8;
            }
        }
        stream
    }

    /// Use an invalid metadata block type (>= 127).
    fn invalid_block_type(gen: &mut InputGenerator) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(FLAC_MARKER);
        // Invalid block type (7-126 are reserved, 127 is invalid)
        let bad_type = match gen.u32() % 4 {
            0 => 7u8,                    // first reserved
            1 => 127u8,                  // explicitly invalid
            2 => 100u8,                  // reserved range
            _ => gen.u32() as u8 & 0x7F, // random type
        };
        let header_byte = 0x80 | bad_type; // last block
        buf.push(header_byte);
        buf.extend_from_slice(&[0x00, 0x00, 0x22]); // length 34
                                                    // Fill with random data
        for _ in 0..34 {
            buf.push(gen.u32() as u8);
        }
        buf
    }

    /// Block length exceeds available data.
    fn oversized_block_length(gen: &mut InputGenerator) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(FLAC_MARKER);
        let header_byte = 0x80 | FLAC_STREAMINFO;
        buf.push(header_byte);
        // Claim a huge block length
        let big_len = match gen.u32() % 3 {
            0 => [0xFF, 0xFF, 0xFF], // 16 MB
            1 => [0x00, 0xFF, 0xFF], // 65535
            _ => [gen.u32() as u8, gen.u32() as u8, gen.u32() as u8],
        };
        buf.extend_from_slice(&big_len);
        // Only provide 34 bytes of actual data
        for _ in 0..34 {
            buf.push(gen.u32() as u8);
        }
        buf
    }

    /// Sample rate packed as zero.
    fn zero_sample_rate(_gen: &mut InputGenerator) -> Vec<u8> {
        Self::valid_streaminfo(0, 2, 16, 44100)
    }

    /// Extreme channel count (0 or very high).
    fn extreme_channels(gen: &mut InputGenerator) -> Vec<u8> {
        let channels = match gen.u32() % 3 {
            0 => 0u8,   // zero channels (invalid)
            1 => 8u8,   // maximum FLAC channels
            _ => 255u8, // well above max (will be masked to 3 bits = 7)
        };
        Self::valid_streaminfo(44100, channels, 16, 44100)
    }

    /// Truncate the stream at various points.
    fn truncated_stream(gen: &mut InputGenerator) -> Vec<u8> {
        let full = Self::valid_streaminfo(44100, 2, 16, 44100);
        let truncate_at = match gen.u32() % 6 {
            0 => 0,
            1 => 1,
            2 => 4, // just the marker
            3 => 5, // marker + 1 byte of block header
            4 => 8, // marker + block header, no data
            _ => gen.u32() as usize % full.len(),
        };
        full[..truncate_at.min(full.len())].to_vec()
    }

    /// FLAC stream that starts with a non-STREAMINFO block.
    fn missing_streaminfo(gen: &mut InputGenerator) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(FLAC_MARKER);
        // Start with PADDING block instead of STREAMINFO
        let header_byte = 0x80 | FLAC_PADDING;
        buf.push(header_byte);
        let padding_len = (gen.u32() % 256) as usize;
        let len_bytes = (padding_len as u32).to_be_bytes();
        buf.extend_from_slice(&len_bytes[1..4]); // 24-bit length
        for _ in 0..padding_len {
            buf.push(0);
        }
        buf
    }

    /// Two STREAMINFO blocks (first must be STREAMINFO per spec).
    fn multiple_streaminfo(gen: &mut InputGenerator) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(FLAC_MARKER);

        // First STREAMINFO (not last)
        let header_byte = FLAC_STREAMINFO; // no last flag
        buf.push(header_byte);
        buf.extend_from_slice(&[0x00, 0x00, 0x22]); // length 34
                                                    // Random STREAMINFO content
        for _ in 0..34 {
            buf.push(gen.u32() as u8);
        }

        // Second STREAMINFO (last) — violates spec
        let header_byte2 = 0x80 | FLAC_STREAMINFO;
        buf.push(header_byte2);
        buf.extend_from_slice(&[0x00, 0x00, 0x22]); // length 34
        for _ in 0..34 {
            buf.push(gen.u32() as u8);
        }

        buf
    }

    /// Valid structure but corrupted MD5 hash.
    fn corrupted_md5(gen: &mut InputGenerator) -> Vec<u8> {
        let mut stream = Self::valid_streaminfo(44100, 2, 16, 44100);
        // MD5 is the last 16 bytes of the STREAMINFO block (bytes 26..42)
        for i in 26..42 {
            if i < stream.len() {
                stream[i] = gen.u32() as u8;
            }
        }
        stream
    }
}

// ============================================================================
// Completely random / garbage audio data generators
// ============================================================================

/// Generates completely random byte sequences that may or may not
/// resemble audio files, for testing that parsers reject garbage gracefully.
pub struct GarbageAudioGenerator;

impl GarbageAudioGenerator {
    /// Generate a random blob that starts with a valid magic but has garbage after.
    pub fn magic_then_garbage(gen: &mut InputGenerator) -> Vec<u8> {
        let magic = match gen.u32() % 4 {
            0 => RIFF_MAGIC.to_vec(),
            1 => FLAC_MARKER.to_vec(),
            2 => b"OggS".to_vec(), // Ogg container
            _ => b"FORM".to_vec(), // AIFF
        };
        let garbage_len = gen.u32() as usize % 256;
        let mut buf = magic;
        for _ in 0..garbage_len {
            buf.push(gen.u32() as u8);
        }
        buf
    }

    /// Generate pure random bytes of various lengths.
    pub fn random_bytes(gen: &mut InputGenerator) -> Vec<u8> {
        let len = match gen.u32() % 8 {
            0 => 0,
            1 => 1,
            2 => 4,
            3 => 44, // exactly WAV header size
            4 => 100,
            5 => 1024,
            6 => 4096,
            _ => gen.u32() as usize % 8192,
        };
        gen.bytes(len)
    }

    /// Generate data with repeated byte patterns that might confuse parsers.
    pub fn repeated_pattern(gen: &mut InputGenerator) -> Vec<u8> {
        let pattern_byte = gen.u32() as u8;
        let len = match gen.u32() % 5 {
            0 => 0,
            1 => 1,
            2 => 44,
            3 => 256,
            _ => gen.u32() as usize % 4096,
        };
        vec![pattern_byte; len]
    }

    /// Generate a file that is just null bytes.
    pub fn null_bytes(gen: &mut InputGenerator) -> Vec<u8> {
        let len = gen.u32() as usize % 8192;
        vec![0u8; len]
    }
}

// ============================================================================
// Fuzz target runners
// ============================================================================

/// Runs all audio fuzz targets and collects results into a `FuzzReport`.
///
/// This is the main entry point for exercising the audio fuzzing suite.
pub fn run_audio_fuzz_suite(config: &FuzzConfig) -> FuzzReport {
    let mut report = FuzzReport::new("Audio Parser Fuzz Suite");

    // WAV header parsing targets
    report.add_result("wav_fuzzed_header_parse", fuzz_wav_header_parse(config));
    report.add_result(
        "wav_header_field_validation",
        fuzz_wav_header_field_validation(config),
    );
    report.add_result("wav_truncated_files", fuzz_wav_truncated(config));

    // FLAC metadata parsing targets
    report.add_result("flac_fuzzed_stream_parse", fuzz_flac_stream_parse(config));
    report.add_result(
        "flac_block_type_validation",
        fuzz_flac_block_type_validation(config),
    );

    // Garbage data targets
    report.add_result("garbage_audio_resilience", fuzz_garbage_audio(config));
    report.add_result("null_bytes_resilience", fuzz_null_bytes(config));

    // Boundary condition targets
    report.add_result("audio_boundary_conditions", fuzz_audio_boundaries(config));

    report
}

/// Fuzz target: parse randomly corrupted WAV headers.
///
/// The parser function validates WAV structure and must not panic
/// on any input, no matter how malformed.
pub fn fuzz_wav_header_parse(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| WavHeaderGenerator::fuzzed_header(gen),
        |data| parse_wav_header_safe(&data),
    )
}

/// Fuzz target: validate WAV header fields for consistency.
///
/// Generates headers with valid structure but inconsistent field
/// values (e.g., block_align != channels * bytes_per_sample).
pub fn fuzz_wav_header_field_validation(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| WavHeaderGenerator::fuzzed_header(gen),
        |data| parse_wav_header_safe(&data),
        |_input, result| {
            match result {
                WavParseResult::Valid {
                    sample_rate,
                    channels,
                    bits_per_sample,
                    ..
                } => {
                    // If parsed as valid, fields must be sane
                    if *sample_rate == 0 {
                        return Err("Valid parse with zero sample rate".to_string());
                    }
                    if *channels == 0 {
                        return Err("Valid parse with zero channels".to_string());
                    }
                    if *bits_per_sample == 0 {
                        return Err("Valid parse with zero bits_per_sample".to_string());
                    }
                    Ok(())
                }
                WavParseResult::Invalid(_) => Ok(()), // rejecting bad data is correct
            }
        },
    )
}

/// Fuzz target: parse truncated WAV files.
pub fn fuzz_wav_truncated(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| {
            let full = WavHeaderGenerator::valid_header(44100, 2, 16, 1024);
            let cut = gen.usize(full.len());
            full[..cut].to_vec()
        },
        |data| parse_wav_header_safe(&data),
    )
}

/// Fuzz target: parse randomly corrupted FLAC streams.
pub fn fuzz_flac_stream_parse(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| FlacHeaderGenerator::fuzzed_stream(gen),
        |data| parse_flac_header_safe(&data),
    )
}

/// Fuzz target: validate FLAC metadata block type handling.
pub fn fuzz_flac_block_type_validation(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| FlacHeaderGenerator::fuzzed_stream(gen),
        |data| parse_flac_header_safe(&data),
        |_input, result| match result {
            FlacParseResult::Valid {
                sample_rate,
                channels,
                bits_per_sample,
                ..
            } => {
                if *sample_rate == 0 {
                    return Err("Valid parse with zero sample rate".to_string());
                }
                if *channels == 0 {
                    return Err("Valid parse with zero channels".to_string());
                }
                if *bits_per_sample == 0 {
                    return Err("Valid parse with zero bits per sample".to_string());
                }
                Ok(())
            }
            FlacParseResult::Invalid(_) => Ok(()),
        },
    )
}

/// Fuzz target: feed pure garbage data to audio parsers.
pub fn fuzz_garbage_audio(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| {
            if gen.bool() {
                GarbageAudioGenerator::magic_then_garbage(gen)
            } else {
                GarbageAudioGenerator::random_bytes(gen)
            }
        },
        |data| {
            // Try both parsers — neither should panic
            let _ = parse_wav_header_safe(&data);
            let _ = parse_flac_header_safe(&data);
        },
    )
}

/// Fuzz target: feed null bytes to audio parsers.
pub fn fuzz_null_bytes(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| GarbageAudioGenerator::null_bytes(gen),
        |data| {
            let _ = parse_wav_header_safe(&data);
            let _ = parse_flac_header_safe(&data);
        },
    )
}

/// Fuzz target: exercise boundary conditions.
pub fn fuzz_audio_boundaries(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| {
            let boundary = gen.u32() % 8;
            match boundary {
                // Empty file
                0 => vec![],
                // Single byte
                1 => vec![gen.u32() as u8],
                // Exactly 4 bytes (magic size)
                2 => gen.bytes(4),
                // Exactly 44 bytes (WAV header size)
                3 => gen.bytes(44),
                // Exactly 42 bytes (FLAC STREAMINFO size)
                4 => gen.bytes(42),
                // 0xFF filled (common in corrupted flash storage)
                5 => vec![0xFF; 44],
                // Alternating 0x00/0xFF
                6 => (0..44)
                    .map(|i| if i % 2 == 0 { 0x00 } else { 0xFF })
                    .collect(),
                // Maximum generation size
                _ => gen.bytes(config.max_input_size),
            }
        },
        |data| {
            let _ = parse_wav_header_safe(&data);
            let _ = parse_flac_header_safe(&data);
        },
    )
}

// ============================================================================
// Safe parsing functions (the targets under test)
// ============================================================================

/// Result of attempting to parse a WAV header.
#[derive(Debug, Clone)]
pub enum WavParseResult {
    Valid {
        sample_rate: u32,
        channels: u16,
        bits_per_sample: u16,
        data_size: u32,
        format_code: u16,
    },
    Invalid(String),
}

/// Result of attempting to parse a FLAC header.
#[derive(Debug, Clone)]
pub enum FlacParseResult {
    Valid {
        sample_rate: u32,
        channels: u8,
        bits_per_sample: u8,
        total_samples: u64,
    },
    Invalid(String),
}

/// Safely parse a WAV header from arbitrary bytes.
///
/// This function must never panic regardless of input. It returns
/// `WavParseResult::Invalid` for any malformed data.
pub fn parse_wav_header_safe(data: &[u8]) -> WavParseResult {
    if data.len() < 44 {
        return WavParseResult::Invalid("Too short for WAV header".to_string());
    }

    // Check RIFF magic
    if &data[0..4] != RIFF_MAGIC {
        return WavParseResult::Invalid("Missing RIFF magic".to_string());
    }

    // Check WAVE magic
    if &data[8..12] != WAVE_MAGIC {
        return WavParseResult::Invalid("Missing WAVE magic".to_string());
    }

    // Check fmt chunk
    if &data[12..16] != FMT_CHUNK_ID {
        return WavParseResult::Invalid("Missing fmt chunk".to_string());
    }

    let fmt_size = u32::from_le_bytes([data[16], data[17], data[18], data[19]]);
    if fmt_size < 16 {
        return WavParseResult::Invalid(format!("fmt chunk too small: {}", fmt_size));
    }

    let format_code = u16::from_le_bytes([data[20], data[21]]);
    let channels = u16::from_le_bytes([data[22], data[23]]);
    let sample_rate = u32::from_le_bytes([data[24], data[25], data[26], data[27]]);
    let bits_per_sample = u16::from_le_bytes([data[34], data[35]]);

    // Validate fields
    if channels == 0 {
        return WavParseResult::Invalid("Zero channels".to_string());
    }
    if sample_rate == 0 {
        return WavParseResult::Invalid("Zero sample rate".to_string());
    }
    if bits_per_sample == 0 {
        return WavParseResult::Invalid("Zero bits per sample".to_string());
    }
    if format_code != WAV_FORMAT_PCM
        && format_code != WAV_FORMAT_IEEE_FLOAT
        && format_code != WAV_FORMAT_EXTENSIBLE
    {
        return WavParseResult::Invalid(format!("Unsupported format code: {}", format_code));
    }

    // Find data chunk
    let data_chunk_offset = 12 + 8 + fmt_size as usize;
    if data_chunk_offset + 8 > data.len() {
        return WavParseResult::Invalid("Data chunk offset out of bounds".to_string());
    }

    let data_size = u32::from_le_bytes([
        data[data_chunk_offset + 4],
        data[data_chunk_offset + 5],
        data[data_chunk_offset + 6],
        data[data_chunk_offset + 7],
    ]);

    WavParseResult::Valid {
        sample_rate,
        channels,
        bits_per_sample,
        data_size,
        format_code,
    }
}

/// Safely parse a FLAC header from arbitrary bytes.
///
/// This function must never panic regardless of input. It returns
/// `FlacParseResult::Invalid` for any malformed data.
pub fn parse_flac_header_safe(data: &[u8]) -> FlacParseResult {
    if data.len() < 8 {
        return FlacParseResult::Invalid("Too short for FLAC stream".to_string());
    }

    // Check fLaC marker
    if &data[0..4] != FLAC_MARKER {
        return FlacParseResult::Invalid("Missing fLaC marker".to_string());
    }

    // Read metadata block header
    let block_header = data[4];
    let block_type = block_header & 0x7F;

    if block_type != FLAC_STREAMINFO {
        return FlacParseResult::Invalid(format!(
            "First block is not STREAMINFO (type={})",
            block_type
        ));
    }

    // Block length (24 bits big-endian)
    if data.len() < 8 {
        return FlacParseResult::Invalid("Truncated block header".to_string());
    }
    let block_length = ((data[5] as u32) << 16) | ((data[6] as u32) << 8) | (data[7] as u32);

    if block_length < 34 {
        return FlacParseResult::Invalid(format!("STREAMINFO block too small: {}", block_length));
    }

    if data.len() < 8 + 34 {
        return FlacParseResult::Invalid("Truncated STREAMINFO block".to_string());
    }

    // Parse sample rate, channels, bps from packed 8 bytes at offset 18
    // (offset 8 = block data start, +10 = after min/max block/frame sizes)
    let packed_offset = 18;
    if data.len() < packed_offset + 8 {
        return FlacParseResult::Invalid("Truncated packed fields".to_string());
    }

    let packed = u64::from_be_bytes([
        data[packed_offset],
        data[packed_offset + 1],
        data[packed_offset + 2],
        data[packed_offset + 3],
        data[packed_offset + 4],
        data[packed_offset + 5],
        data[packed_offset + 6],
        data[packed_offset + 7],
    ]);

    let sample_rate = ((packed >> 44) & 0xFFFFF) as u32;
    let channels = (((packed >> 41) & 0x07) as u8) + 1;
    let bits_per_sample = (((packed >> 36) & 0x1F) as u8) + 1;
    let total_samples = packed & 0xFFFFFFFFF;

    // Validate
    if sample_rate == 0 {
        return FlacParseResult::Invalid("Zero sample rate".to_string());
    }

    FlacParseResult::Valid {
        sample_rate,
        channels,
        bits_per_sample,
        total_samples,
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_wav_header_roundtrip() {
        let header = WavHeaderGenerator::valid_header(44100, 2, 16, 1024);
        assert_eq!(header.len(), 44);
        match parse_wav_header_safe(&header) {
            WavParseResult::Valid {
                sample_rate,
                channels,
                bits_per_sample,
                data_size,
                format_code,
            } => {
                assert_eq!(sample_rate, 44100);
                assert_eq!(channels, 2);
                assert_eq!(bits_per_sample, 16);
                assert_eq!(data_size, 1024);
                assert_eq!(format_code, WAV_FORMAT_PCM);
            }
            WavParseResult::Invalid(e) => panic!("Valid header rejected: {}", e),
        }
    }

    #[test]
    fn test_valid_flac_streaminfo_roundtrip() {
        let stream = FlacHeaderGenerator::valid_streaminfo(48000, 2, 24, 48000 * 120);
        match parse_flac_header_safe(&stream) {
            FlacParseResult::Valid {
                sample_rate,
                channels,
                bits_per_sample,
                ..
            } => {
                assert_eq!(sample_rate, 48000);
                assert_eq!(channels, 2);
                assert_eq!(bits_per_sample, 24);
            }
            FlacParseResult::Invalid(e) => panic!("Valid FLAC rejected: {}", e),
        }
    }

    #[test]
    fn test_wav_empty_data_rejected() {
        let result = parse_wav_header_safe(&[]);
        assert!(matches!(result, WavParseResult::Invalid(_)));
    }

    #[test]
    fn test_wav_short_data_rejected() {
        let result = parse_wav_header_safe(&[0u8; 10]);
        assert!(matches!(result, WavParseResult::Invalid(_)));
    }

    #[test]
    fn test_wav_bad_magic_rejected() {
        let mut header = WavHeaderGenerator::valid_header(44100, 2, 16, 1024);
        header[0] = b'X';
        let result = parse_wav_header_safe(&header);
        assert!(matches!(result, WavParseResult::Invalid(_)));
    }

    #[test]
    fn test_wav_zero_channels_rejected() {
        let header = WavHeaderGenerator::valid_header(44100, 0, 16, 1024);
        let result = parse_wav_header_safe(&header);
        assert!(matches!(result, WavParseResult::Invalid(_)));
    }

    #[test]
    fn test_wav_zero_sample_rate_rejected() {
        let header = WavHeaderGenerator::valid_header(0, 2, 16, 1024);
        let result = parse_wav_header_safe(&header);
        assert!(matches!(result, WavParseResult::Invalid(_)));
    }

    #[test]
    fn test_wav_zero_bps_rejected() {
        let header = WavHeaderGenerator::valid_header(44100, 2, 0, 1024);
        let result = parse_wav_header_safe(&header);
        assert!(matches!(result, WavParseResult::Invalid(_)));
    }

    #[test]
    fn test_flac_empty_data_rejected() {
        let result = parse_flac_header_safe(&[]);
        assert!(matches!(result, FlacParseResult::Invalid(_)));
    }

    #[test]
    fn test_flac_bad_marker_rejected() {
        let mut stream = FlacHeaderGenerator::valid_streaminfo(44100, 2, 16, 44100);
        stream[0] = b'X';
        let result = parse_flac_header_safe(&stream);
        assert!(matches!(result, FlacParseResult::Invalid(_)));
    }

    #[test]
    fn test_flac_zero_sample_rate_rejected() {
        let stream = FlacHeaderGenerator::valid_streaminfo(0, 2, 16, 44100);
        let result = parse_flac_header_safe(&stream);
        assert!(matches!(result, FlacParseResult::Invalid(_)));
    }

    #[test]
    fn test_fuzz_wav_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_wav_header_parse(&config);
        assert!(
            result.passed,
            "WAV fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_wav_field_validation() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_wav_header_field_validation(&config);
        assert!(
            result.passed,
            "WAV field validation failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_wav_truncated_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_wav_truncated(&config);
        assert!(
            result.passed,
            "Truncated WAV panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_flac_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_flac_stream_parse(&config);
        assert!(
            result.passed,
            "FLAC fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_flac_block_type_validation() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_flac_block_type_validation(&config);
        assert!(
            result.passed,
            "FLAC block validation failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_garbage_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_garbage_audio(&config);
        assert!(
            result.passed,
            "Garbage audio panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_null_bytes_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(200);
        let result = fuzz_null_bytes(&config);
        assert!(
            result.passed,
            "Null bytes panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_boundaries_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_audio_boundaries(&config);
        assert!(
            result.passed,
            "Boundary fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_full_audio_fuzz_suite() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(100);
        let report = run_audio_fuzz_suite(&config);
        assert!(
            report.all_passed(),
            "Audio fuzz suite failed:\n{}",
            report.to_text()
        );
    }

    #[test]
    fn test_wav_various_sample_rates() {
        let rates = [
            8000u32, 11025, 22050, 44100, 48000, 88200, 96000, 192000, 384000,
        ];
        for &rate in &rates {
            let header = WavHeaderGenerator::valid_header(rate, 2, 16, 1024);
            match parse_wav_header_safe(&header) {
                WavParseResult::Valid { sample_rate, .. } => {
                    assert_eq!(sample_rate, rate);
                }
                WavParseResult::Invalid(e) => panic!("Rate {} rejected: {}", rate, e),
            }
        }
    }

    #[test]
    fn test_wav_various_channel_counts() {
        for channels in [1u16, 2, 4, 6, 8] {
            let header = WavHeaderGenerator::valid_header(44100, channels, 16, 1024);
            match parse_wav_header_safe(&header) {
                WavParseResult::Valid {
                    channels: parsed_ch,
                    ..
                } => {
                    assert_eq!(parsed_ch, channels);
                }
                WavParseResult::Invalid(e) => {
                    panic!("{} channels rejected: {}", channels, e);
                }
            }
        }
    }

    #[test]
    fn test_wav_various_bit_depths() {
        for bps in [8u16, 16, 24, 32] {
            let header = WavHeaderGenerator::valid_header(44100, 2, bps, 1024);
            match parse_wav_header_safe(&header) {
                WavParseResult::Valid {
                    bits_per_sample, ..
                } => {
                    assert_eq!(bits_per_sample, bps);
                }
                WavParseResult::Invalid(e) => {
                    panic!("{}-bit rejected: {}", bps, e);
                }
            }
        }
    }

    #[test]
    fn test_flac_various_configs() {
        let configs = [
            (44100u32, 1u8, 16u8),
            (48000, 2, 24),
            (96000, 2, 16),
            (192000, 6, 24),
        ];
        for &(rate, ch, bps) in &configs {
            let stream = FlacHeaderGenerator::valid_streaminfo(rate, ch, bps, rate as u64 * 60);
            match parse_flac_header_safe(&stream) {
                FlacParseResult::Valid {
                    sample_rate,
                    channels,
                    bits_per_sample,
                    ..
                } => {
                    assert_eq!(sample_rate, rate);
                    assert_eq!(channels, ch);
                    assert_eq!(bits_per_sample, bps);
                }
                FlacParseResult::Invalid(e) => {
                    panic!("Config ({}, {}, {}) rejected: {}", rate, ch, bps, e);
                }
            }
        }
    }

    #[test]
    fn test_repeated_pattern_resilience() {
        // 0xFF filled data should not crash parsers
        let data = vec![0xFF; 1024];
        let wav_result = parse_wav_header_safe(&data);
        assert!(matches!(wav_result, WavParseResult::Invalid(_)));

        let flac_result = parse_flac_header_safe(&data);
        assert!(matches!(flac_result, FlacParseResult::Invalid(_)));
    }

    #[test]
    fn test_generator_determinism() {
        let mut gen1 = InputGenerator::new(Some(999), 4096);
        let mut gen2 = InputGenerator::new(Some(999), 4096);

        for _ in 0..20 {
            let wav1 = WavHeaderGenerator::fuzzed_header(&mut gen1);
            let wav2 = WavHeaderGenerator::fuzzed_header(&mut gen2);
            assert_eq!(wav1, wav2, "WAV generators diverged with same seed");
        }
    }
}

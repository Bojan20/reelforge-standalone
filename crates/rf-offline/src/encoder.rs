//! Audio encoding module
//!
//! Supports:
//! - WAV (via hound) — native, no external dependencies
//! - AIFF (custom Rust) — native, no external dependencies
//! - FLAC (via flac-bound) — native, no external dependencies
//! - MP3 (via mp3lame-encoder) — native LAME, no external dependencies!
//! - OGG (via vorbis-encoder) — native libvorbis, no external dependencies!
//! - Opus (via audiopus + ogg) — native libopus, no external dependencies!
//! - AAC (via FFmpeg fallback when available)

use crate::config::DitheringMode;
use crate::error::{OfflineError, OfflineResult};
use crate::formats::{
    AacConfig, AiffConfig, FlacConfig, Mp3Bitrate, Mp3Config, OggConfig, OpusConfig, OutputFormat,
    WavConfig,
};
use crate::pipeline::AudioBuffer;

use std::io::Cursor;
use std::process::Command;

// ═══════════════════════════════════════════════════════════════════════════════
// ENCODER TRAIT
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio encoder trait
pub trait AudioEncoder {
    /// Encode audio buffer to bytes
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>>;

    /// Get file extension
    fn extension(&self) -> &'static str;
}

// ═══════════════════════════════════════════════════════════════════════════════
// WAV ENCODER
// ═══════════════════════════════════════════════════════════════════════════════

/// WAV encoder using hound
pub struct WavEncoder {
    config: WavConfig,
}

impl WavEncoder {
    pub fn new(config: WavConfig) -> Self {
        Self { config }
    }
}

impl AudioEncoder for WavEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        let mut output = Vec::new();
        let cursor = Cursor::new(&mut output);

        let spec = hound::WavSpec {
            channels: buffer.channels as u16,
            sample_rate: buffer.sample_rate,
            bits_per_sample: self.config.bit_depth as u16,
            sample_format: if self.config.float && self.config.bit_depth == 32 {
                hound::SampleFormat::Float
            } else {
                hound::SampleFormat::Int
            },
        };

        let mut writer = hound::WavWriter::new(cursor, spec)
            .map_err(|e| OfflineError::EncodingError(e.to_string()))?;

        // Apply dithering for bit depth reduction
        let dithered = apply_dithering(
            &buffer.samples,
            self.config.bit_depth,
            self.config.dithering,
        );

        match self.config.bit_depth {
            8 => {
                for &sample in &dithered {
                    let s = ((sample.clamp(-1.0, 1.0) * 127.0) + 128.0) as i8;
                    writer
                        .write_sample(s)
                        .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                }
            }
            16 => {
                for &sample in &dithered {
                    let s = (sample.clamp(-1.0, 1.0) * 32767.0) as i16;
                    writer
                        .write_sample(s)
                        .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                }
            }
            24 => {
                for &sample in &dithered {
                    let s = (sample.clamp(-1.0, 1.0) * 8388607.0) as i32;
                    writer
                        .write_sample(s)
                        .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                }
            }
            32 => {
                if self.config.float {
                    for &sample in &buffer.samples {
                        writer
                            .write_sample(sample as f32)
                            .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                    }
                } else {
                    for &sample in &dithered {
                        let s = (sample.clamp(-1.0, 1.0) * 2147483647.0) as i32;
                        writer
                            .write_sample(s)
                            .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                    }
                }
            }
            _ => {
                return Err(OfflineError::ConfigError(format!(
                    "Unsupported bit depth: {}",
                    self.config.bit_depth
                )));
            }
        }

        writer
            .finalize()
            .map_err(|e| OfflineError::EncodingError(e.to_string()))?;

        Ok(output)
    }

    fn extension(&self) -> &'static str {
        "wav"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLAC ENCODER
// ═══════════════════════════════════════════════════════════════════════════════

/// FLAC encoder using flac-bound
pub struct FlacEncoder {
    config: FlacConfig,
}

impl FlacEncoder {
    pub fn new(config: FlacConfig) -> Self {
        Self { config }
    }
}

impl AudioEncoder for FlacEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        use flac_bound::{FlacEncoder as FlacEnc, WriteWrapper};

        let mut output = Vec::new();

        // Create FLAC encoder with settings
        let encoder_config = FlacEnc::new()
            .ok_or_else(|| OfflineError::EncodingError("FLAC encoder init failed".to_string()))?
            .channels(buffer.channels as u32)
            .sample_rate(buffer.sample_rate)
            .bits_per_sample(self.config.bit_depth as u32)
            .compression_level(self.config.compression_level as u32);

        // Initialize with output writer
        let mut wrapper = WriteWrapper(&mut output);
        let mut encoder = encoder_config
            .init_write(&mut wrapper)
            .map_err(|e| OfflineError::EncodingError(format!("FLAC init write failed: {:?}", e)))?;

        // Apply dithering
        let dithered = apply_dithering(
            &buffer.samples,
            self.config.bit_depth,
            self.config.dithering,
        );

        // Convert to i32 samples
        let max_val = (1i64 << (self.config.bit_depth - 1)) as f64;
        let samples: Vec<i32> = dithered
            .iter()
            .map(|&s| (s.clamp(-1.0, 1.0) * max_val) as i32)
            .collect();

        // Process in blocks
        let frames = samples.len() / buffer.channels;
        let block_size = 4096;

        for block_start in (0..frames).step_by(block_size) {
            let block_end = (block_start + block_size).min(frames);
            let block_frames = block_end - block_start;

            // Deinterleave
            let mut block_samples = Vec::with_capacity(block_frames * buffer.channels);
            for frame in block_start..block_end {
                for ch in 0..buffer.channels {
                    block_samples.push(samples[frame * buffer.channels + ch]);
                }
            }

            encoder
                .process_interleaved(&block_samples, block_frames as u32)
                .map_err(|e| {
                    OfflineError::EncodingError(format!("FLAC process failed: {:?}", e))
                })?;
        }

        // Finish encoding
        encoder
            .finish()
            .map_err(|e| OfflineError::EncodingError(format!("FLAC finish failed: {:?}", e)))?;

        Ok(output)
    }

    fn extension(&self) -> &'static str {
        "flac"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AIFF ENCODER (native Rust implementation)
// ═══════════════════════════════════════════════════════════════════════════════

/// AIFF encoder - native Rust implementation (no external dependencies)
/// AIFF uses big-endian byte order (unlike WAV which is little-endian)
pub struct AiffEncoder {
    config: AiffConfig,
}

impl AiffEncoder {
    pub fn new(config: AiffConfig) -> Self {
        Self { config }
    }

    /// Convert f64 to 80-bit extended precision (IEEE 754)
    /// Used for sample rate in AIFF COMM chunk
    fn f64_to_extended(value: f64) -> [u8; 10] {
        let mut result = [0u8; 10];

        if value == 0.0 {
            return result;
        }

        let bits = value.to_bits();
        let sign = ((bits >> 63) & 1) as u16;
        let exp = ((bits >> 52) & 0x7FF) as i32;
        let mantissa = bits & 0xFFFFFFFFFFFFF;

        // Convert from IEEE 754 double to extended precision
        let extended_exp = if exp == 0 {
            0
        } else {
            (exp - 1023 + 16383) as u16
        };

        let extended_exp_with_sign = (sign << 15) | extended_exp;

        // Mantissa: add implicit 1 and shift
        let extended_mantissa = if exp != 0 {
            0x8000000000000000u64 | (mantissa << 11)
        } else {
            mantissa << 12
        };

        // Write big-endian
        result[0] = (extended_exp_with_sign >> 8) as u8;
        result[1] = extended_exp_with_sign as u8;
        result[2..10].copy_from_slice(&extended_mantissa.to_be_bytes());

        result
    }
}

impl AudioEncoder for AiffEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        let mut output = Vec::new();

        let channels = buffer.channels as u16;
        let sample_rate = buffer.sample_rate;
        let bit_depth = self.config.bit_depth;
        let bytes_per_sample = (bit_depth / 8) as u32;

        // Apply dithering if needed
        let dithered = apply_dithering(&buffer.samples, bit_depth, self.config.dithering.clone());

        let num_frames = dithered.len() / buffer.channels;
        let sound_data_size = num_frames as u32 * channels as u32 * bytes_per_sample;

        // COMM chunk size: 18 bytes (fixed for AIFF)
        let comm_chunk_size: u32 = 18;
        // SSND chunk size: 8 (offset + block_size) + sound_data_size
        let ssnd_chunk_size: u32 = 8 + sound_data_size;
        // Total FORM size: 4 (AIFF) + 8 (COMM header) + comm_chunk_size + 8 (SSND header) + ssnd_chunk_size
        let form_size: u32 = 4 + 8 + comm_chunk_size + 8 + ssnd_chunk_size;

        // ═══════════════════════════════════════════════════════════════════════
        // FORM chunk (container)
        // ═══════════════════════════════════════════════════════════════════════
        output.extend_from_slice(b"FORM");
        output.extend_from_slice(&form_size.to_be_bytes());
        output.extend_from_slice(b"AIFF");

        // ═══════════════════════════════════════════════════════════════════════
        // COMM chunk (common data)
        // ═══════════════════════════════════════════════════════════════════════
        output.extend_from_slice(b"COMM");
        output.extend_from_slice(&comm_chunk_size.to_be_bytes());
        output.extend_from_slice(&channels.to_be_bytes()); // numChannels (2 bytes)
        output.extend_from_slice(&(num_frames as u32).to_be_bytes()); // numSampleFrames (4 bytes)
        output.extend_from_slice(&(bit_depth as u16).to_be_bytes()); // sampleSize (2 bytes)
        output.extend_from_slice(&Self::f64_to_extended(sample_rate as f64)); // sampleRate (10 bytes, 80-bit extended)

        // ═══════════════════════════════════════════════════════════════════════
        // SSND chunk (sound data)
        // ═══════════════════════════════════════════════════════════════════════
        output.extend_from_slice(b"SSND");
        output.extend_from_slice(&ssnd_chunk_size.to_be_bytes());
        output.extend_from_slice(&0u32.to_be_bytes()); // offset (always 0)
        output.extend_from_slice(&0u32.to_be_bytes()); // blockSize (always 0)

        // Write audio samples in big-endian format
        match bit_depth {
            8 => {
                // 8-bit: unsigned, offset binary (128 = silence)
                for &sample in &dithered {
                    let s = ((sample.clamp(-1.0, 1.0) * 127.0) + 128.0) as u8;
                    output.push(s);
                }
            }
            16 => {
                for &sample in &dithered {
                    let s = (sample.clamp(-1.0, 1.0) * 32767.0) as i16;
                    output.extend_from_slice(&s.to_be_bytes());
                }
            }
            24 => {
                for &sample in &dithered {
                    let s = (sample.clamp(-1.0, 1.0) * 8388607.0) as i32;
                    // Write only 3 bytes (big-endian, MSB first)
                    let bytes = s.to_be_bytes();
                    output.extend_from_slice(&bytes[1..4]);
                }
            }
            32 => {
                for &sample in &dithered {
                    let s = (sample.clamp(-1.0, 1.0) * 2147483647.0) as i32;
                    output.extend_from_slice(&s.to_be_bytes());
                }
            }
            _ => {
                return Err(OfflineError::ConfigError(format!(
                    "Unsupported AIFF bit depth: {}",
                    bit_depth
                )));
            }
        }

        // Pad to even length if necessary (AIFF requirement)
        if output.len() % 2 != 0 {
            output.push(0);
        }

        Ok(output)
    }

    fn extension(&self) -> &'static str {
        "aiff"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MP3 ENCODER (Native LAME - no FFmpeg dependency!)
// ═══════════════════════════════════════════════════════════════════════════════

/// Native MP3 encoder using LAME via mp3lame-encoder crate
/// Supports CBR (128/192/256/320 kbps) and VBR (quality 0-9)
pub struct LameMp3Encoder {
    config: Mp3Config,
}

impl LameMp3Encoder {
    pub fn new(config: Mp3Config) -> Self {
        Self { config }
    }

    /// Convert Mp3Bitrate to LAME bitrate enum
    fn get_lame_bitrate(&self) -> mp3lame_encoder::Bitrate {
        match &self.config.bitrate {
            Mp3Bitrate::Cbr(kbps) | Mp3Bitrate::Abr(kbps) => match kbps {
                0..=95 => mp3lame_encoder::Bitrate::Kbps96,
                96..=111 => mp3lame_encoder::Bitrate::Kbps96,
                112..=127 => mp3lame_encoder::Bitrate::Kbps112,
                128..=159 => mp3lame_encoder::Bitrate::Kbps128,
                160..=191 => mp3lame_encoder::Bitrate::Kbps160,
                192..=223 => mp3lame_encoder::Bitrate::Kbps192,
                224..=255 => mp3lame_encoder::Bitrate::Kbps224,
                256..=319 => mp3lame_encoder::Bitrate::Kbps256,
                _ => mp3lame_encoder::Bitrate::Kbps320,
            },
            // VBR doesn't use bitrate directly, use 320 as fallback
            Mp3Bitrate::Vbr(_) => mp3lame_encoder::Bitrate::Kbps320,
        }
    }

    /// Convert VBR quality (0-9) to LAME quality enum
    /// LAME VBR quality: 0 = best, 9 = worst
    fn get_lame_quality(&self) -> mp3lame_encoder::Quality {
        match &self.config.bitrate {
            Mp3Bitrate::Vbr(q) => match q {
                0 => mp3lame_encoder::Quality::Best,
                1 => mp3lame_encoder::Quality::SecondBest,
                2 => mp3lame_encoder::Quality::NearBest,
                3 => mp3lame_encoder::Quality::VeryNice,
                4 => mp3lame_encoder::Quality::Nice,
                5 => mp3lame_encoder::Quality::Good,
                6 => mp3lame_encoder::Quality::Decent,
                7 => mp3lame_encoder::Quality::Ok,
                8 => mp3lame_encoder::Quality::SecondWorst,
                _ => mp3lame_encoder::Quality::Worst,
            },
            // CBR/ABR use best quality for encoding
            _ => mp3lame_encoder::Quality::Best,
        }
    }
}

impl AudioEncoder for LameMp3Encoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        use mp3lame_encoder::{Builder, DualPcm, FlushNoGap};

        // Build LAME encoder
        let mut builder = Builder::new()
            .ok_or_else(|| OfflineError::EncodingError("LAME encoder init failed".to_string()))?;

        // Set channels
        builder
            .set_num_channels(buffer.channels as u8)
            .map_err(|e| {
                OfflineError::EncodingError(format!("LAME set channels failed: {:?}", e))
            })?;

        // Set sample rate
        builder.set_sample_rate(buffer.sample_rate).map_err(|e| {
            OfflineError::EncodingError(format!("LAME set sample rate failed: {:?}", e))
        })?;

        // Set bitrate
        builder.set_brate(self.get_lame_bitrate()).map_err(|e| {
            OfflineError::EncodingError(format!("LAME set bitrate failed: {:?}", e))
        })?;

        // Set quality
        builder.set_quality(self.get_lame_quality()).map_err(|e| {
            OfflineError::EncodingError(format!("LAME set quality failed: {:?}", e))
        })?;

        // Build encoder
        let mut encoder = builder
            .build()
            .map_err(|e| OfflineError::EncodingError(format!("LAME build failed: {:?}", e)))?;

        // Convert f64 samples to i16 (LAME expects 16-bit PCM)
        // Deinterleave into left/right channels
        let num_frames = buffer.samples.len() / buffer.channels;
        let mut left: Vec<i16> = Vec::with_capacity(num_frames);
        let mut right: Vec<i16> = Vec::with_capacity(num_frames);

        if buffer.channels == 2 {
            for i in 0..num_frames {
                left.push((buffer.samples[i * 2].clamp(-1.0, 1.0) * 32767.0) as i16);
                right.push((buffer.samples[i * 2 + 1].clamp(-1.0, 1.0) * 32767.0) as i16);
            }
        } else {
            // Mono: duplicate to both channels
            for i in 0..num_frames {
                let sample = (buffer.samples[i].clamp(-1.0, 1.0) * 32767.0) as i16;
                left.push(sample);
                right.push(sample);
            }
        }

        // Create output buffer with spare capacity for MaybeUninit
        let mp3_buffer_size = mp3lame_encoder::max_required_buffer_size(num_frames);
        let mut mp3_output: Vec<u8> = Vec::with_capacity(mp3_buffer_size);

        // Encode using DualPcm (separate L/R channels)
        let input = DualPcm {
            left: &left,
            right: &right,
        };

        let encoded_size = encoder
            .encode(input, mp3_output.spare_capacity_mut())
            .map_err(|e| OfflineError::EncodingError(format!("LAME encode failed: {:?}", e)))?;

        // SAFETY: encoder wrote encoded_size bytes into spare capacity
        unsafe {
            mp3_output.set_len(encoded_size);
        }

        // Flush remaining data
        // Reserve more space for flush
        mp3_output.reserve(7200);
        let flush_size = encoder
            .flush::<FlushNoGap>(mp3_output.spare_capacity_mut())
            .map_err(|e| OfflineError::EncodingError(format!("LAME flush failed: {:?}", e)))?;

        // SAFETY: encoder wrote flush_size bytes into spare capacity
        unsafe {
            mp3_output.set_len(mp3_output.len() + flush_size);
        }

        Ok(mp3_output)
    }

    fn extension(&self) -> &'static str {
        "mp3"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MP3 ENCODER (FFmpeg fallback - kept for backwards compatibility)
// ═══════════════════════════════════════════════════════════════════════════════

/// MP3 encoder using FFmpeg (fallback, prefer LameMp3Encoder)
pub struct FfmpegMp3Encoder {
    config: Mp3Config,
}

impl FfmpegMp3Encoder {
    pub fn new(config: Mp3Config) -> Self {
        Self { config }
    }

    /// Check if FFmpeg is available
    pub fn is_available() -> bool {
        Command::new("ffmpeg").arg("-version").output().is_ok()
    }
}

impl AudioEncoder for FfmpegMp3Encoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        // Write temp WAV file, convert with FFmpeg
        let temp_dir = std::env::temp_dir();
        let temp_wav = temp_dir.join(format!("rf_offline_{}.wav", std::process::id()));
        let temp_mp3 = temp_dir.join(format!("rf_offline_{}.mp3", std::process::id()));

        // Write WAV
        let wav_encoder = WavEncoder::new(WavConfig::default());
        let wav_data = wav_encoder.encode(buffer)?;
        std::fs::write(&temp_wav, &wav_data)?;

        // Build FFmpeg command
        let mut cmd = Command::new("ffmpeg");
        cmd.arg("-y")
            .arg("-i")
            .arg(&temp_wav)
            .arg("-acodec")
            .arg("libmp3lame");

        match &self.config.bitrate {
            Mp3Bitrate::Cbr(kbps) => {
                cmd.arg("-b:a").arg(format!("{}k", kbps));
            }
            Mp3Bitrate::Vbr(quality) => {
                cmd.arg("-q:a").arg(quality.to_string());
            }
            Mp3Bitrate::Abr(kbps) => {
                cmd.arg("--abr").arg(kbps.to_string());
            }
        }

        if self.config.joint_stereo {
            cmd.arg("-joint_stereo").arg("1");
        }

        cmd.arg(&temp_mp3);

        let output = cmd.output()?;

        if !output.status.success() {
            // Cleanup
            let _ = std::fs::remove_file(&temp_wav);
            return Err(OfflineError::EncodingError(format!(
                "FFmpeg MP3 encoding failed: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        // Read result
        let mp3_data = std::fs::read(&temp_mp3)?;

        // Cleanup
        let _ = std::fs::remove_file(&temp_wav);
        let _ = std::fs::remove_file(&temp_mp3);

        Ok(mp3_data)
    }

    fn extension(&self) -> &'static str {
        "mp3"
    }
}

/// Backwards-compatible alias (uses native LAME)
pub type Mp3Encoder = LameMp3Encoder;

// ═══════════════════════════════════════════════════════════════════════════════
// OGG ENCODER (Native libvorbis - no FFmpeg dependency!)
// ═══════════════════════════════════════════════════════════════════════════════

/// Native OGG Vorbis encoder using vorbis-encoder crate
/// Supports quality levels 0-10 (mapped to libvorbis -0.1 to 1.0)
pub struct NativeOggEncoder {
    config: OggConfig,
}

impl NativeOggEncoder {
    pub fn new(config: OggConfig) -> Self {
        Self { config }
    }

    /// Convert quality (-1 to 10) to libvorbis quality (-0.1 to 1.0)
    /// -1 = lowest quality (~45kbps), 10 = highest quality (~500kbps)
    fn get_vorbis_quality(&self) -> f32 {
        // OggConfig quality: -1 to 10
        // libvorbis quality: -0.1 to 1.0
        // Map: -1 → -0.1, 10 → 1.0
        let clamped = self.config.quality.clamp(-1.0, 10.0);
        (clamped + 1.0) / 11.0 * 1.1 - 0.1
    }
}

impl AudioEncoder for NativeOggEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        use vorbis_encoder::Encoder;

        // Create Vorbis encoder
        let mut encoder = Encoder::new(
            buffer.channels as u32,
            buffer.sample_rate as u64,
            self.get_vorbis_quality(),
        )
        .map_err(|e| OfflineError::EncodingError(format!("Vorbis encoder init failed: {}", e)))?;

        // Convert f64 samples to i16 (Vorbis expects 16-bit PCM)
        let samples_i16: Vec<i16> = buffer
            .samples
            .iter()
            .map(|&s| (s.clamp(-1.0, 1.0) * 32767.0) as i16)
            .collect();

        // Encode samples
        let mut ogg_data = encoder
            .encode(&samples_i16)
            .map_err(|e| OfflineError::EncodingError(format!("Vorbis encode failed: {}", e)))?;

        // Flush remaining data
        let flush_data = encoder
            .flush()
            .map_err(|e| OfflineError::EncodingError(format!("Vorbis flush failed: {}", e)))?;

        ogg_data.extend(flush_data);

        Ok(ogg_data)
    }

    fn extension(&self) -> &'static str {
        "ogg"
    }
}

/// Backwards-compatible alias (uses native libvorbis)
pub type OggEncoder = NativeOggEncoder;

// ═══════════════════════════════════════════════════════════════════════════════
// OPUS ENCODER (Native libopus - no FFmpeg dependency!)
// ═══════════════════════════════════════════════════════════════════════════════

/// Native Opus encoder using audiopus + ogg crates
/// Supports bitrates 6-510 kbps and complexity 0-10
/// Opus requires 48kHz sample rate - audio will be resampled if needed
pub struct NativeOpusEncoder {
    config: OpusConfig,
}

impl NativeOpusEncoder {
    pub fn new(config: OpusConfig) -> Self {
        Self { config }
    }

    /// Get Opus bitrate enum from config
    fn get_opus_bitrate(&self) -> audiopus::Bitrate {
        audiopus::Bitrate::BitsPerSecond(self.config.bitrate as i32 * 1000)
    }

    /// Resample audio to 48kHz if needed (Opus requires specific sample rates)
    fn resample_to_48k(samples: &[f64], src_rate: u32, channels: usize) -> Vec<f64> {
        if src_rate == 48000 {
            return samples.to_vec();
        }

        // Linear interpolation resampling (simple but effective)
        let ratio = 48000.0 / src_rate as f64;
        let num_src_frames = samples.len() / channels;
        let num_dst_frames = (num_src_frames as f64 * ratio).ceil() as usize;
        let mut resampled = Vec::with_capacity(num_dst_frames * channels);

        for dst_frame in 0..num_dst_frames {
            let src_pos = dst_frame as f64 / ratio;
            let src_frame = src_pos.floor() as usize;
            let frac = src_pos - src_frame as f64;

            for ch in 0..channels {
                let idx0 = src_frame * channels + ch;
                let idx1 = ((src_frame + 1).min(num_src_frames - 1)) * channels + ch;

                let s0 = samples.get(idx0).copied().unwrap_or(0.0);
                let s1 = samples.get(idx1).copied().unwrap_or(0.0);

                // Linear interpolation
                let sample = s0 + (s1 - s0) * frac;
                resampled.push(sample);
            }
        }

        resampled
    }
}

impl AudioEncoder for NativeOpusEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        use audiopus::coder::Encoder as OpusEnc;
        use audiopus::{Application, Channels, SampleRate};
        use ogg::writing::PacketWriter;

        // Opus requires specific sample rates, 48kHz is the standard
        let resampled = Self::resample_to_48k(&buffer.samples, buffer.sample_rate, buffer.channels);
        let sample_rate = SampleRate::Hz48000;

        // Determine channels
        let channels = match buffer.channels {
            1 => Channels::Mono,
            2 => Channels::Stereo,
            _ => {
                return Err(OfflineError::ConfigError(format!(
                    "Opus only supports 1 or 2 channels, got {}",
                    buffer.channels
                )));
            }
        };

        // Create Opus encoder
        let mut encoder = OpusEnc::new(sample_rate, channels, Application::Audio).map_err(|e| {
            OfflineError::EncodingError(format!("Opus encoder init failed: {:?}", e))
        })?;

        // Configure encoder
        encoder.set_bitrate(self.get_opus_bitrate()).map_err(|e| {
            OfflineError::EncodingError(format!("Opus set bitrate failed: {:?}", e))
        })?;

        encoder
            .set_complexity(self.config.complexity.min(10))
            .map_err(|e| {
                OfflineError::EncodingError(format!("Opus set complexity failed: {:?}", e))
            })?;

        // Frame size: 20ms at 48kHz = 960 samples per channel
        let frame_size = 960;
        let frame_samples = frame_size * buffer.channels;

        // Convert to i16 for encoding
        let samples_i16: Vec<i16> = resampled
            .iter()
            .map(|&s| (s.clamp(-1.0, 1.0) * 32767.0) as i16)
            .collect();

        // OGG container setup
        let mut ogg_data = Vec::new();
        let mut packet_writer = PacketWriter::new(&mut ogg_data);
        let serial = 1u32;

        // Write Opus identification header (OpusHead)
        let opus_head = Self::create_opus_head(buffer.channels as u8, 48000);
        packet_writer
            .write_packet(
                opus_head,
                serial,
                ogg::writing::PacketWriteEndInfo::EndPage,
                0,
            )
            .map_err(|e| {
                OfflineError::EncodingError(format!("OGG write header failed: {:?}", e))
            })?;

        // Write Opus comment header (OpusTags)
        let opus_tags = Self::create_opus_tags();
        packet_writer
            .write_packet(
                opus_tags,
                serial,
                ogg::writing::PacketWriteEndInfo::EndPage,
                0,
            )
            .map_err(|e| OfflineError::EncodingError(format!("OGG write tags failed: {:?}", e)))?;

        // Encode audio frames
        let mut opus_packet = vec![0u8; 4000]; // Max packet size
        let num_frames = samples_i16.len() / frame_samples;
        let mut granule_pos: u64 = 0;

        for frame_idx in 0..num_frames {
            let start = frame_idx * frame_samples;
            let end = start + frame_samples;
            let frame_data = &samples_i16[start..end];

            let encoded_len = encoder
                .encode(frame_data, &mut opus_packet)
                .map_err(|e| OfflineError::EncodingError(format!("Opus encode failed: {:?}", e)))?;

            granule_pos += frame_size as u64;

            let is_last = frame_idx == num_frames - 1;
            let end_info = if is_last {
                ogg::writing::PacketWriteEndInfo::EndStream
            } else {
                ogg::writing::PacketWriteEndInfo::NormalPacket
            };

            packet_writer
                .write_packet(
                    opus_packet[..encoded_len].to_vec(),
                    serial,
                    end_info,
                    granule_pos,
                )
                .map_err(|e| {
                    OfflineError::EncodingError(format!("OGG write packet failed: {:?}", e))
                })?;
        }

        // Handle remaining samples (pad to frame size if needed)
        let remaining = samples_i16.len() % frame_samples;
        if remaining > 0 {
            let mut last_frame = vec![0i16; frame_samples];
            let start = num_frames * frame_samples;
            last_frame[..remaining].copy_from_slice(&samples_i16[start..]);

            let encoded_len = encoder.encode(&last_frame, &mut opus_packet).map_err(|e| {
                OfflineError::EncodingError(format!("Opus encode final failed: {:?}", e))
            })?;

            granule_pos += frame_size as u64;

            packet_writer
                .write_packet(
                    opus_packet[..encoded_len].to_vec(),
                    serial,
                    ogg::writing::PacketWriteEndInfo::EndStream,
                    granule_pos,
                )
                .map_err(|e| {
                    OfflineError::EncodingError(format!("OGG write final failed: {:?}", e))
                })?;
        }

        Ok(ogg_data)
    }

    fn extension(&self) -> &'static str {
        "opus"
    }
}

impl NativeOpusEncoder {
    /// Create OpusHead identification header
    /// RFC 7845 Section 5.1
    fn create_opus_head(channels: u8, sample_rate: u32) -> Vec<u8> {
        let mut head = Vec::with_capacity(19);

        // Magic signature "OpusHead"
        head.extend_from_slice(b"OpusHead");

        // Version (1)
        head.push(1);

        // Channel count
        head.push(channels);

        // Pre-skip (3840 samples = 80ms at 48kHz, standard value)
        head.extend_from_slice(&3840u16.to_le_bytes());

        // Input sample rate (informational, for seeking)
        head.extend_from_slice(&sample_rate.to_le_bytes());

        // Output gain (0 dB)
        head.extend_from_slice(&0i16.to_le_bytes());

        // Channel mapping family (0 = mono/stereo, no mapping table)
        head.push(0);

        head
    }

    /// Create OpusTags comment header
    /// RFC 7845 Section 5.2
    fn create_opus_tags() -> Vec<u8> {
        let mut tags = Vec::with_capacity(60);

        // Magic signature "OpusTags"
        tags.extend_from_slice(b"OpusTags");

        // Vendor string
        let vendor = b"FluxForge rf-offline";
        tags.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
        tags.extend_from_slice(vendor);

        // User comment list count (0)
        tags.extend_from_slice(&0u32.to_le_bytes());

        tags
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OGG ENCODER (FFmpeg fallback - kept for backwards compatibility)
// ═══════════════════════════════════════════════════════════════════════════════

/// OGG Vorbis encoder using FFmpeg (fallback, prefer NativeOggEncoder)
pub struct FfmpegOggEncoder {
    config: OggConfig,
}

impl FfmpegOggEncoder {
    pub fn new(config: OggConfig) -> Self {
        Self { config }
    }

    /// Check if FFmpeg is available
    pub fn is_available() -> bool {
        Command::new("ffmpeg").arg("-version").output().is_ok()
    }
}

impl AudioEncoder for FfmpegOggEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        let temp_dir = std::env::temp_dir();
        let temp_wav = temp_dir.join(format!("rf_offline_{}.wav", std::process::id()));
        let temp_ogg = temp_dir.join(format!("rf_offline_{}.ogg", std::process::id()));

        // Write WAV
        let wav_encoder = WavEncoder::new(WavConfig::default());
        let wav_data = wav_encoder.encode(buffer)?;
        std::fs::write(&temp_wav, &wav_data)?;

        // FFmpeg encode
        let output = Command::new("ffmpeg")
            .arg("-y")
            .arg("-i")
            .arg(&temp_wav)
            .arg("-acodec")
            .arg("libvorbis")
            .arg("-q:a")
            .arg(self.config.quality.to_string())
            .arg(&temp_ogg)
            .output()?;

        if !output.status.success() {
            let _ = std::fs::remove_file(&temp_wav);
            return Err(OfflineError::EncodingError(format!(
                "FFmpeg OGG encoding failed: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        let ogg_data = std::fs::read(&temp_ogg)?;

        let _ = std::fs::remove_file(&temp_wav);
        let _ = std::fs::remove_file(&temp_ogg);

        Ok(ogg_data)
    }

    fn extension(&self) -> &'static str {
        "ogg"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OPUS ENCODER (FFmpeg fallback - kept for backwards compatibility)
// ═══════════════════════════════════════════════════════════════════════════════

/// Opus encoder using FFmpeg (fallback, prefer NativeOpusEncoder)
pub struct FfmpegOpusEncoder {
    config: OpusConfig,
}

impl FfmpegOpusEncoder {
    pub fn new(config: OpusConfig) -> Self {
        Self { config }
    }

    /// Check if FFmpeg is available
    pub fn is_available() -> bool {
        Command::new("ffmpeg").arg("-version").output().is_ok()
    }
}

impl AudioEncoder for FfmpegOpusEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        let temp_dir = std::env::temp_dir();
        let temp_wav = temp_dir.join(format!("rf_offline_{}.wav", std::process::id()));
        let temp_opus = temp_dir.join(format!("rf_offline_{}.opus", std::process::id()));

        let wav_encoder = WavEncoder::new(WavConfig::default());
        let wav_data = wav_encoder.encode(buffer)?;
        std::fs::write(&temp_wav, &wav_data)?;

        let output = Command::new("ffmpeg")
            .arg("-y")
            .arg("-i")
            .arg(&temp_wav)
            .arg("-acodec")
            .arg("libopus")
            .arg("-b:a")
            .arg(format!("{}k", self.config.bitrate))
            .arg("-compression_level")
            .arg(self.config.complexity.to_string())
            .arg(&temp_opus)
            .output()?;

        if !output.status.success() {
            let _ = std::fs::remove_file(&temp_wav);
            return Err(OfflineError::EncodingError(format!(
                "FFmpeg Opus encoding failed: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        let opus_data = std::fs::read(&temp_opus)?;

        let _ = std::fs::remove_file(&temp_wav);
        let _ = std::fs::remove_file(&temp_opus);

        Ok(opus_data)
    }

    fn extension(&self) -> &'static str {
        "opus"
    }
}

/// Backwards-compatible alias (uses native libopus)
pub type OpusEncoder = NativeOpusEncoder;

// ═══════════════════════════════════════════════════════════════════════════════
// AAC ENCODER (FFmpeg fallback)
// ═══════════════════════════════════════════════════════════════════════════════

/// AAC encoder using FFmpeg
pub struct AacEncoder {
    config: AacConfig,
}

impl AacEncoder {
    pub fn new(config: AacConfig) -> Self {
        Self { config }
    }
}

impl AudioEncoder for AacEncoder {
    fn encode(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        let temp_dir = std::env::temp_dir();
        let temp_wav = temp_dir.join(format!("rf_offline_{}.wav", std::process::id()));
        let temp_aac = temp_dir.join(format!("rf_offline_{}.m4a", std::process::id()));

        let wav_encoder = WavEncoder::new(WavConfig::default());
        let wav_data = wav_encoder.encode(buffer)?;
        std::fs::write(&temp_wav, &wav_data)?;

        let output = Command::new("ffmpeg")
            .arg("-y")
            .arg("-i")
            .arg(&temp_wav)
            .arg("-acodec")
            .arg("aac")
            .arg("-b:a")
            .arg(format!("{}k", self.config.bitrate))
            .arg(&temp_aac)
            .output()?;

        if !output.status.success() {
            let _ = std::fs::remove_file(&temp_wav);
            return Err(OfflineError::EncodingError(format!(
                "FFmpeg AAC encoding failed: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        let aac_data = std::fs::read(&temp_aac)?;

        let _ = std::fs::remove_file(&temp_wav);
        let _ = std::fs::remove_file(&temp_aac);

        Ok(aac_data)
    }

    fn extension(&self) -> &'static str {
        "m4a"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENCODER FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/// Create encoder for output format
pub fn create_encoder(format: &OutputFormat) -> Box<dyn AudioEncoder> {
    match format {
        OutputFormat::Wav(config) => Box::new(WavEncoder::new(config.clone())),
        OutputFormat::Aiff(config) => Box::new(AiffEncoder::new(config.clone())),
        OutputFormat::Flac(config) => Box::new(FlacEncoder::new(config.clone())),
        // Native LAME encoder (no FFmpeg needed!)
        OutputFormat::Mp3(config) => Box::new(LameMp3Encoder::new(config.clone())),
        // Native libvorbis encoder (no FFmpeg needed!)
        OutputFormat::Ogg(config) => Box::new(NativeOggEncoder::new(config.clone())),
        // Native libopus encoder (no FFmpeg needed!)
        OutputFormat::Opus(config) => Box::new(NativeOpusEncoder::new(config.clone())),
        OutputFormat::Aac(config) => Box::new(AacEncoder::new(config.clone())),
    }
}

/// Check what encoders are available
/// Native: wav, aiff, flac, mp3, ogg, opus (no external dependencies)
/// FFmpeg: aac (requires ffmpeg installed)
pub fn available_encoders() -> Vec<&'static str> {
    // Native encoders (always available - no external dependencies!)
    let mut available = vec!["wav", "aiff", "flac", "mp3", "ogg", "opus"];

    // FFmpeg-based encoders (require ffmpeg)
    if FfmpegMp3Encoder::is_available() {
        available.push("aac");
    }

    available
}

// ═══════════════════════════════════════════════════════════════════════════════
// DITHERING
// ═══════════════════════════════════════════════════════════════════════════════

/// Apply dithering for bit depth reduction
fn apply_dithering(samples: &[f64], target_bits: u8, mode: DitheringMode) -> Vec<f64> {
    match mode {
        DitheringMode::None => samples.to_vec(),
        DitheringMode::Rectangular => {
            use rand::Rng;
            let mut rng = rand::thread_rng();
            let step = 1.0 / ((1i64 << (target_bits - 1)) as f64);

            samples
                .iter()
                .map(|&s| {
                    let dither = (rng.gen_range(0.0..1.0) - 0.5) * step;
                    s + dither
                })
                .collect()
        }
        DitheringMode::Triangular => {
            use rand::Rng;
            let mut rng = rand::thread_rng();
            let step = 1.0 / ((1i64 << (target_bits - 1)) as f64);

            samples
                .iter()
                .map(|&s| {
                    // TPDF: sum of two uniform random values
                    let r1: f64 = rng.gen_range(0.0..1.0);
                    let r2: f64 = rng.gen_range(0.0..1.0);
                    let dither = (r1 + r2 - 1.0) * step;
                    s + dither
                })
                .collect()
        }
        DitheringMode::NoiseShaped => {
            // Simplified noise shaping (first-order)
            use rand::Rng;
            let mut rng = rand::thread_rng();
            let step = 1.0 / ((1i64 << (target_bits - 1)) as f64);
            let mut error = 0.0;

            samples
                .iter()
                .map(|&s| {
                    let input = s - error * 0.5; // Feedback
                    let r1: f64 = rng.gen_range(0.0..1.0);
                    let r2: f64 = rng.gen_range(0.0..1.0);
                    let dither = (r1 + r2 - 1.0) * step;
                    let output = input + dither;

                    // Quantize
                    let quantized = (output / step).round() * step;
                    error = quantized - input;

                    quantized
                })
                .collect()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wav_encoder() {
        let buffer = AudioBuffer {
            samples: vec![0.5, -0.5, 0.25, -0.25],
            channels: 2,
            sample_rate: 44100,
        };

        let encoder = WavEncoder::new(WavConfig::default());
        let result = encoder.encode(&buffer);

        assert!(result.is_ok());
        let data = result.unwrap();
        assert!(!data.is_empty());
        // Check RIFF header
        assert_eq!(&data[0..4], b"RIFF");
    }

    #[test]
    fn test_available_encoders() {
        let encoders = available_encoders();
        assert!(encoders.contains(&"wav"));
        assert!(encoders.contains(&"flac"));
        // MP3 is now always available (native LAME)
        assert!(encoders.contains(&"mp3"));
        // OGG is now always available (native libvorbis)
        assert!(encoders.contains(&"ogg"));
    }

    #[test]
    fn test_native_ogg_encoder() {
        let buffer = AudioBuffer {
            samples: vec![0.5, -0.5, 0.25, -0.25, 0.1, -0.1, 0.0, 0.0],
            channels: 2,
            sample_rate: 44100,
        };

        // Test quality 8.0 (high quality)
        let encoder = NativeOggEncoder::new(OggConfig { quality: 8.0 });
        let result = encoder.encode(&buffer);
        assert!(result.is_ok(), "OGG encoding failed: {:?}", result.err());
        let data = result.unwrap();
        assert!(!data.is_empty());
        // Check OGG header magic bytes "OggS"
        assert!(data.len() > 4);
        assert_eq!(
            &data[0..4],
            b"OggS",
            "OGG file should start with OggS magic"
        );
    }

    #[test]
    fn test_native_ogg_encoder_various_qualities() {
        let buffer = AudioBuffer {
            samples: vec![0.5; 8820], // 0.1 seconds of stereo audio at 44.1kHz
            channels: 2,
            sample_rate: 44100,
        };

        // Test various quality levels
        for quality in [0.0_f32, 3.0, 5.0, 8.0, 10.0] {
            let encoder = NativeOggEncoder::new(OggConfig { quality });
            let result = encoder.encode(&buffer);
            assert!(
                result.is_ok(),
                "OGG Q{} encoding failed: {:?}",
                quality,
                result.err()
            );
            let data = result.unwrap();
            assert!(!data.is_empty());
            assert_eq!(&data[0..4], b"OggS");
        }
    }

    #[test]
    fn test_native_ogg_encoder_mono() {
        let buffer = AudioBuffer {
            samples: vec![0.5, -0.5, 0.25, -0.25],
            channels: 1,
            sample_rate: 44100,
        };

        let encoder = NativeOggEncoder::new(OggConfig { quality: 6.0 });
        let result = encoder.encode(&buffer);
        assert!(
            result.is_ok(),
            "OGG mono encoding failed: {:?}",
            result.err()
        );
    }

    #[test]
    fn test_ogg_quality_mapping() {
        // Test quality mapping from -1 to 10 to -0.1 to 1.0
        let encoder_low = NativeOggEncoder::new(OggConfig { quality: -1.0 });
        let encoder_mid = NativeOggEncoder::new(OggConfig { quality: 5.0 });
        let encoder_high = NativeOggEncoder::new(OggConfig { quality: 10.0 });

        let q_low = encoder_low.get_vorbis_quality();
        let q_mid = encoder_mid.get_vorbis_quality();
        let q_high = encoder_high.get_vorbis_quality();

        assert!(q_low < q_mid, "Low quality should be less than mid");
        assert!(q_mid < q_high, "Mid quality should be less than high");
        assert!(
            q_low >= -0.15 && q_low <= 0.0,
            "Quality -1 should map to ~-0.1, got {}",
            q_low
        );
        assert!(
            q_high >= 0.9 && q_high <= 1.05,
            "Quality 10 should map to ~1.0, got {}",
            q_high
        );
    }

    #[test]
    fn test_native_mp3_encoder() {
        let buffer = AudioBuffer {
            samples: vec![0.5, -0.5, 0.25, -0.25, 0.1, -0.1, 0.0, 0.0],
            channels: 2,
            sample_rate: 44100,
        };

        // Test CBR 320kbps
        let encoder = LameMp3Encoder::new(Mp3Config {
            bitrate: Mp3Bitrate::Cbr(320),
            joint_stereo: true,
        });
        let result = encoder.encode(&buffer);
        assert!(result.is_ok(), "CBR encoding failed: {:?}", result.err());
        let data = result.unwrap();
        assert!(!data.is_empty());
        // Check for MP3 frame sync (0xFF 0xFB for MPEG Layer 3)
        assert!(data.len() > 2);
    }

    #[test]
    fn test_native_mp3_encoder_vbr() {
        let buffer = AudioBuffer {
            samples: vec![0.5, -0.5, 0.25, -0.25, 0.1, -0.1, 0.0, 0.0],
            channels: 2,
            sample_rate: 44100,
        };

        // Test VBR quality 2 (high quality)
        let encoder = LameMp3Encoder::new(Mp3Config {
            bitrate: Mp3Bitrate::Vbr(2),
            joint_stereo: true,
        });
        let result = encoder.encode(&buffer);
        assert!(result.is_ok(), "VBR encoding failed: {:?}", result.err());
    }

    #[test]
    fn test_native_mp3_encoder_various_bitrates() {
        let buffer = AudioBuffer {
            samples: vec![0.5; 8820], // 0.1 seconds of stereo audio at 44.1kHz
            channels: 2,
            sample_rate: 44100,
        };

        // Test various bitrates
        for bitrate in [128, 192, 256, 320] {
            let encoder = LameMp3Encoder::new(Mp3Config {
                bitrate: Mp3Bitrate::Cbr(bitrate),
                joint_stereo: true,
            });
            let result = encoder.encode(&buffer);
            assert!(
                result.is_ok(),
                "CBR {} encoding failed: {:?}",
                bitrate,
                result.err()
            );
        }
    }

    #[test]
    fn test_dithering_rectangular() {
        let samples = vec![0.5; 1000];
        let dithered = apply_dithering(&samples, 16, DitheringMode::Rectangular);

        // Should have same length
        assert_eq!(dithered.len(), samples.len());

        // Should be slightly different (with dither)
        let different_count = samples
            .iter()
            .zip(dithered.iter())
            .filter(|(a, b)| (*a - *b).abs() > 1e-10)
            .count();
        assert!(different_count > 900); // Most should be different
    }

    #[test]
    fn test_dithering_triangular() {
        let samples = vec![0.25; 1000];
        let dithered = apply_dithering(&samples, 16, DitheringMode::Triangular);

        assert_eq!(dithered.len(), samples.len());

        // TPDF should have characteristic distribution
        let sum: f64 = dithered.iter().sum();
        let mean = sum / dithered.len() as f64;

        // Mean should be close to original
        assert!((mean - 0.25).abs() < 0.01);
    }

    #[test]
    fn test_native_opus_encoder() {
        let buffer = AudioBuffer {
            // 20ms of stereo audio at 48kHz = 960 * 2 = 1920 samples
            samples: (0..960).flat_map(|_| [0.5, -0.5]).collect(),
            channels: 2,
            sample_rate: 48000,
        };

        let encoder = NativeOpusEncoder::new(OpusConfig {
            bitrate: 128,
            complexity: 10,
        });
        let result = encoder.encode(&buffer);
        assert!(result.is_ok(), "Opus encoding failed: {:?}", result.err());
        let data = result.unwrap();
        assert!(!data.is_empty());
        // Check OGG header magic bytes "OggS"
        assert!(data.len() > 4);
        assert_eq!(
            &data[0..4],
            b"OggS",
            "Opus file should start with OggS magic"
        );
    }

    #[test]
    fn test_native_opus_encoder_various_bitrates() {
        let buffer = AudioBuffer {
            // 100ms of stereo audio at 48kHz = 4800 * 2 = 9600 samples
            samples: vec![0.3; 9600],
            channels: 2,
            sample_rate: 48000,
        };

        // Test various bitrates
        for bitrate in [64, 96, 128, 192, 256] {
            let encoder = NativeOpusEncoder::new(OpusConfig {
                bitrate,
                complexity: 10,
            });
            let result = encoder.encode(&buffer);
            assert!(
                result.is_ok(),
                "Opus {}kbps encoding failed: {:?}",
                bitrate,
                result.err()
            );
            let data = result.unwrap();
            assert!(!data.is_empty());
            assert_eq!(&data[0..4], b"OggS");
        }
    }

    #[test]
    fn test_native_opus_encoder_mono() {
        let buffer = AudioBuffer {
            // 20ms of mono audio at 48kHz = 960 samples
            samples: (0..240).flat_map(|_| [0.5, -0.5, 0.25, -0.25]).collect(),
            channels: 1,
            sample_rate: 48000,
        };

        let encoder = NativeOpusEncoder::new(OpusConfig {
            bitrate: 64,
            complexity: 5,
        });
        let result = encoder.encode(&buffer);
        assert!(
            result.is_ok(),
            "Opus mono encoding failed: {:?}",
            result.err()
        );
    }

    #[test]
    fn test_native_opus_encoder_resampling() {
        // Test with 44.1kHz input (requires resampling to 48kHz)
        let buffer = AudioBuffer {
            samples: vec![0.5; 8820], // 0.1 seconds of stereo audio at 44.1kHz
            channels: 2,
            sample_rate: 44100,
        };

        let encoder = NativeOpusEncoder::new(OpusConfig {
            bitrate: 128,
            complexity: 10,
        });
        let result = encoder.encode(&buffer);
        assert!(
            result.is_ok(),
            "Opus resampling encoding failed: {:?}",
            result.err()
        );
        let data = result.unwrap();
        assert!(!data.is_empty());
        assert_eq!(&data[0..4], b"OggS");
    }

    #[test]
    fn test_native_opus_encoder_complexity() {
        let buffer = AudioBuffer {
            samples: vec![0.3; 9600],
            channels: 2,
            sample_rate: 48000,
        };

        // Test various complexity levels
        for complexity in [0, 3, 5, 8, 10] {
            let encoder = NativeOpusEncoder::new(OpusConfig {
                bitrate: 128,
                complexity,
            });
            let result = encoder.encode(&buffer);
            assert!(
                result.is_ok(),
                "Opus complexity {} encoding failed: {:?}",
                complexity,
                result.err()
            );
        }
    }

    #[test]
    fn test_opus_head_creation() {
        let head = NativeOpusEncoder::create_opus_head(2, 48000);

        // Verify OpusHead structure
        assert_eq!(&head[0..8], b"OpusHead");
        assert_eq!(head[8], 1); // Version
        assert_eq!(head[9], 2); // Channels
        // Pre-skip: bytes 10-11 (little endian)
        let pre_skip = u16::from_le_bytes([head[10], head[11]]);
        assert_eq!(pre_skip, 3840);
        // Sample rate: bytes 12-15 (little endian)
        let sample_rate = u32::from_le_bytes([head[12], head[13], head[14], head[15]]);
        assert_eq!(sample_rate, 48000);
    }

    #[test]
    fn test_opus_tags_creation() {
        let tags = NativeOpusEncoder::create_opus_tags();

        // Verify OpusTags structure
        assert_eq!(&tags[0..8], b"OpusTags");
        // Vendor string length: bytes 8-11 (little endian)
        let vendor_len = u32::from_le_bytes([tags[8], tags[9], tags[10], tags[11]]);
        assert!(vendor_len > 0);
    }
}

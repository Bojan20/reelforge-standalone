//! Audio encoding module
//!
//! Supports:
//! - WAV (via hound)
//! - FLAC (via flac-bound)
//! - MP3/OGG/AAC (via FFmpeg fallback when available)

use crate::config::DitheringMode;
use crate::error::{OfflineError, OfflineResult};
use crate::formats::{
    AacConfig, FlacConfig, Mp3Bitrate, Mp3Config, OggConfig, OpusConfig, OutputFormat, WavConfig,
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
        let dithered = apply_dithering(&buffer.samples, self.config.bit_depth, self.config.dithering);

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
        let dithered =
            apply_dithering(&buffer.samples, self.config.bit_depth, self.config.dithering);

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
                .map_err(|e| OfflineError::EncodingError(format!("FLAC process failed: {:?}", e)))?;
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
// MP3 ENCODER (FFmpeg fallback)
// ═══════════════════════════════════════════════════════════════════════════════

/// MP3 encoder using FFmpeg
pub struct Mp3Encoder {
    config: Mp3Config,
}

impl Mp3Encoder {
    pub fn new(config: Mp3Config) -> Self {
        Self { config }
    }

    /// Check if FFmpeg is available
    pub fn is_available() -> bool {
        Command::new("ffmpeg").arg("-version").output().is_ok()
    }
}

impl AudioEncoder for Mp3Encoder {
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

// ═══════════════════════════════════════════════════════════════════════════════
// OGG ENCODER (FFmpeg fallback)
// ═══════════════════════════════════════════════════════════════════════════════

/// OGG Vorbis encoder using FFmpeg
pub struct OggEncoder {
    config: OggConfig,
}

impl OggEncoder {
    pub fn new(config: OggConfig) -> Self {
        Self { config }
    }

    /// Check if FFmpeg is available
    pub fn is_available() -> bool {
        Command::new("ffmpeg").arg("-version").output().is_ok()
    }
}

impl AudioEncoder for OggEncoder {
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
// OPUS ENCODER (FFmpeg fallback)
// ═══════════════════════════════════════════════════════════════════════════════

/// Opus encoder using FFmpeg
pub struct OpusEncoder {
    config: OpusConfig,
}

impl OpusEncoder {
    pub fn new(config: OpusConfig) -> Self {
        Self { config }
    }
}

impl AudioEncoder for OpusEncoder {
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
        OutputFormat::Aiff(config) => {
            // AIFF uses same encoding as WAV but with AIFF header
            // For simplicity, encode as WAV (would need aiff crate for proper support)
            Box::new(WavEncoder::new(WavConfig {
                bit_depth: config.bit_depth,
                float: false,
                dithering: config.dithering.clone(),
            }))
        }
        OutputFormat::Flac(config) => Box::new(FlacEncoder::new(config.clone())),
        OutputFormat::Mp3(config) => Box::new(Mp3Encoder::new(config.clone())),
        OutputFormat::Ogg(config) => Box::new(OggEncoder::new(config.clone())),
        OutputFormat::Opus(config) => Box::new(OpusEncoder::new(config.clone())),
        OutputFormat::Aac(config) => Box::new(AacEncoder::new(config.clone())),
    }
}

/// Check what encoders are available
pub fn available_encoders() -> Vec<&'static str> {
    let mut available = vec!["wav", "flac"];

    if Mp3Encoder::is_available() {
        available.push("mp3");
        available.push("ogg");
        available.push("opus");
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
}

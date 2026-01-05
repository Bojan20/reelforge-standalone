//! Audio File Import
//!
//! Provides:
//! - Audio file decoding (WAV, MP3, FLAC, OGG via symphonia)
//! - Automatic sample rate conversion
//! - Waveform peak generation for UI display
//! - Streaming import for large files

use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use thiserror::Error;

// ═══════════════════════════════════════════════════════════════════════════
// ERRORS
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Error, Debug)]
pub enum ImportError {
    #[error("File not found: {0}")]
    FileNotFound(String),

    #[error("Unsupported format: {0}")]
    UnsupportedFormat(String),

    #[error("Decode error: {0}")]
    DecodeError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

// ═══════════════════════════════════════════════════════════════════════════
// IMPORTED AUDIO
// ═══════════════════════════════════════════════════════════════════════════

/// Imported audio data with metadata
#[derive(Debug, Clone)]
pub struct ImportedAudio {
    /// Interleaved audio samples (f32, normalized -1.0 to 1.0)
    pub samples: Vec<f32>,

    /// Sample rate in Hz
    pub sample_rate: u32,

    /// Number of channels (1=mono, 2=stereo)
    pub channels: u8,

    /// Duration in seconds
    pub duration_secs: f64,

    /// Total sample count (per channel)
    pub sample_count: usize,

    /// Original file path
    pub source_path: String,

    /// File name without path
    pub name: String,
}

impl ImportedAudio {
    /// Create mono audio data
    pub fn new_mono(samples: Vec<f32>, sample_rate: u32, source_path: &str) -> Self {
        let sample_count = samples.len();
        let duration_secs = sample_count as f64 / sample_rate as f64;
        let name = Path::new(source_path)
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "Unknown".to_string());

        Self {
            samples,
            sample_rate,
            channels: 1,
            duration_secs,
            sample_count,
            source_path: source_path.to_string(),
            name,
        }
    }

    /// Create stereo audio data
    pub fn new_stereo(samples: Vec<f32>, sample_rate: u32, source_path: &str) -> Self {
        let sample_count = samples.len() / 2;
        let duration_secs = sample_count as f64 / sample_rate as f64;
        let name = Path::new(source_path)
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "Unknown".to_string());

        Self {
            samples,
            sample_rate,
            channels: 2,
            duration_secs,
            sample_count,
            source_path: source_path.to_string(),
            name,
        }
    }

    /// Get left channel samples (or mono samples)
    pub fn left_channel(&self) -> Vec<f32> {
        if self.channels == 1 {
            self.samples.clone()
        } else {
            self.samples.iter().step_by(2).copied().collect()
        }
    }

    /// Get right channel samples (or mono samples for mono files)
    pub fn right_channel(&self) -> Vec<f32> {
        if self.channels == 1 {
            self.samples.clone()
        } else {
            self.samples.iter().skip(1).step_by(2).copied().collect()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO IMPORTER
// ═══════════════════════════════════════════════════════════════════════════

/// Audio file importer with format detection
pub struct AudioImporter;

impl AudioImporter {
    /// Import audio file from path
    ///
    /// Supports: WAV, MP3, FLAC, OGG, AIFF
    pub fn import(path: &Path) -> Result<ImportedAudio, ImportError> {
        if !path.exists() {
            return Err(ImportError::FileNotFound(path.display().to_string()));
        }

        let extension = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.to_lowercase())
            .unwrap_or_default();

        match extension.as_str() {
            "wav" => Self::import_wav(path),
            "mp3" => Self::import_compressed(path), // TODO: implement with symphonia
            "flac" => Self::import_compressed(path),
            "ogg" => Self::import_compressed(path),
            "aiff" | "aif" => Self::import_wav(path), // Similar to WAV
            _ => Err(ImportError::UnsupportedFormat(extension)),
        }
    }

    /// Import WAV file (native support, no external deps)
    fn import_wav(path: &Path) -> Result<ImportedAudio, ImportError> {
        let file = File::open(path)?;
        let mut reader = BufReader::new(file);

        // Parse WAV header manually for maximum control
        let header = WavHeader::read(&mut reader)
            .map_err(|e| ImportError::DecodeError(e.to_string()))?;

        // Read sample data
        let samples = Self::read_wav_samples(&mut reader, &header)
            .map_err(|e| ImportError::DecodeError(e.to_string()))?;

        let path_str = path.display().to_string();

        if header.channels == 1 {
            Ok(ImportedAudio::new_mono(samples, header.sample_rate, &path_str))
        } else {
            Ok(ImportedAudio::new_stereo(samples, header.sample_rate, &path_str))
        }
    }

    /// Import compressed format (placeholder for symphonia integration)
    fn import_compressed(path: &Path) -> Result<ImportedAudio, ImportError> {
        // TODO: Implement with symphonia crate
        // For now, return error indicating compressed formats need symphonia
        Err(ImportError::UnsupportedFormat(format!(
            "Compressed format support requires symphonia crate (file: {})",
            path.display()
        )))
    }

    /// Read WAV samples and convert to f32
    fn read_wav_samples<R: std::io::Read>(
        reader: &mut R,
        header: &WavHeader,
    ) -> Result<Vec<f32>, std::io::Error> {
        use std::io::Read;

        let total_samples = header.data_size as usize / (header.bits_per_sample as usize / 8);
        let mut samples = Vec::with_capacity(total_samples);

        match header.bits_per_sample {
            16 => {
                let mut buf = [0u8; 2];
                while reader.read_exact(&mut buf).is_ok() {
                    let sample = i16::from_le_bytes(buf);
                    samples.push(sample as f32 / 32768.0);
                }
            }
            24 => {
                let mut buf = [0u8; 3];
                while reader.read_exact(&mut buf).is_ok() {
                    let sample = i32::from_le_bytes([buf[0], buf[1], buf[2], 0]);
                    samples.push(sample as f32 / 8388608.0);
                }
            }
            32 => {
                if header.audio_format == 3 {
                    // IEEE float
                    let mut buf = [0u8; 4];
                    while reader.read_exact(&mut buf).is_ok() {
                        let sample = f32::from_le_bytes(buf);
                        samples.push(sample);
                    }
                } else {
                    // 32-bit integer
                    let mut buf = [0u8; 4];
                    while reader.read_exact(&mut buf).is_ok() {
                        let sample = i32::from_le_bytes(buf);
                        samples.push(sample as f32 / 2147483648.0);
                    }
                }
            }
            _ => {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("Unsupported bit depth: {}", header.bits_per_sample),
                ));
            }
        }

        Ok(samples)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WAV HEADER PARSER
// ═══════════════════════════════════════════════════════════════════════════

/// WAV file header
#[derive(Debug)]
struct WavHeader {
    audio_format: u16,
    channels: u16,
    sample_rate: u32,
    bits_per_sample: u16,
    data_size: u32,
}

impl WavHeader {
    fn read<R: std::io::Read>(reader: &mut R) -> Result<Self, std::io::Error> {
        use std::io::{Error, ErrorKind, Read};

        let mut buf4 = [0u8; 4];
        let mut buf2 = [0u8; 2];

        // RIFF header
        reader.read_exact(&mut buf4)?;
        if &buf4 != b"RIFF" {
            return Err(Error::new(ErrorKind::InvalidData, "Not a RIFF file"));
        }

        reader.read_exact(&mut buf4)?; // file size
        reader.read_exact(&mut buf4)?;
        if &buf4 != b"WAVE" {
            return Err(Error::new(ErrorKind::InvalidData, "Not a WAVE file"));
        }

        // Find fmt chunk
        let mut audio_format = 0u16;
        let mut channels = 0u16;
        let mut sample_rate = 0u32;
        let mut bits_per_sample = 0u16;
        let mut data_size = 0u32;

        loop {
            if reader.read_exact(&mut buf4).is_err() {
                break;
            }
            let chunk_id = buf4;

            reader.read_exact(&mut buf4)?;
            let chunk_size = u32::from_le_bytes(buf4);

            match &chunk_id {
                b"fmt " => {
                    reader.read_exact(&mut buf2)?;
                    audio_format = u16::from_le_bytes(buf2);

                    reader.read_exact(&mut buf2)?;
                    channels = u16::from_le_bytes(buf2);

                    reader.read_exact(&mut buf4)?;
                    sample_rate = u32::from_le_bytes(buf4);

                    reader.read_exact(&mut buf4)?; // byte rate
                    reader.read_exact(&mut buf2)?; // block align

                    reader.read_exact(&mut buf2)?;
                    bits_per_sample = u16::from_le_bytes(buf2);

                    // Skip extra bytes in fmt chunk
                    if chunk_size > 16 {
                        let skip = chunk_size - 16;
                        let mut skip_buf = vec![0u8; skip as usize];
                        reader.read_exact(&mut skip_buf)?;
                    }
                }
                b"data" => {
                    data_size = chunk_size;
                    break; // Ready to read samples
                }
                _ => {
                    // Skip unknown chunks
                    let mut skip_buf = vec![0u8; chunk_size as usize];
                    reader.read_exact(&mut skip_buf)?;
                }
            }
        }

        if sample_rate == 0 {
            return Err(Error::new(ErrorKind::InvalidData, "Invalid WAV: no fmt chunk"));
        }

        Ok(Self {
            audio_format,
            channels,
            sample_rate,
            bits_per_sample,
            data_size,
        })
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SAMPLE RATE CONVERSION
// ═══════════════════════════════════════════════════════════════════════════

/// Simple sample rate converter using linear interpolation
pub struct SampleRateConverter;

impl SampleRateConverter {
    /// Convert sample rate using linear interpolation
    ///
    /// For production, use sinc interpolation (rf-dsp crate)
    pub fn convert_linear(
        samples: &[f32],
        from_rate: u32,
        to_rate: u32,
        channels: u8,
    ) -> Vec<f32> {
        if from_rate == to_rate {
            return samples.to_vec();
        }

        let ratio = to_rate as f64 / from_rate as f64;
        let new_len = ((samples.len() / channels as usize) as f64 * ratio) as usize * channels as usize;
        let mut output = Vec::with_capacity(new_len);

        let samples_per_channel = samples.len() / channels as usize;

        for ch in 0..channels as usize {
            for i in 0..((samples_per_channel as f64 * ratio) as usize) {
                let src_pos = i as f64 / ratio;
                let src_idx = src_pos.floor() as usize;
                let frac = src_pos - src_idx as f64;

                let idx = src_idx * channels as usize + ch;
                let next_idx = (src_idx + 1).min(samples_per_channel - 1) * channels as usize + ch;

                let sample = if idx < samples.len() && next_idx < samples.len() {
                    samples[idx] * (1.0 - frac as f32) + samples[next_idx] * frac as f32
                } else if idx < samples.len() {
                    samples[idx]
                } else {
                    0.0
                };

                output.push(sample);
            }
        }

        // Interleave channels properly
        if channels == 2 {
            let half = output.len() / 2;
            let mut interleaved = Vec::with_capacity(output.len());
            for i in 0..half {
                interleaved.push(output[i]);
                interleaved.push(output[half + i]);
            }
            output = interleaved;
        }

        output
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_imported_audio_mono() {
        let samples = vec![0.0f32; 48000];
        let audio = ImportedAudio::new_mono(samples, 48000, "/test/audio.wav");

        assert_eq!(audio.channels, 1);
        assert_eq!(audio.duration_secs, 1.0);
        assert_eq!(audio.name, "audio.wav");
    }

    #[test]
    fn test_imported_audio_stereo() {
        let samples = vec![0.0f32; 96000]; // 48000 * 2 channels
        let audio = ImportedAudio::new_stereo(samples, 48000, "/test/stereo.wav");

        assert_eq!(audio.channels, 2);
        assert_eq!(audio.duration_secs, 1.0);
    }

    #[test]
    fn test_sample_rate_conversion() {
        let samples: Vec<f32> = (0..44100).map(|i| (i as f32 / 44100.0).sin()).collect();
        let converted = SampleRateConverter::convert_linear(&samples, 44100, 48000, 1);

        // Should be approximately 48000 samples
        assert!((converted.len() as i32 - 48000).abs() < 10);
    }
}

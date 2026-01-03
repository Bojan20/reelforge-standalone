//! Audio file reading and writing
//!
//! Supports:
//! - WAV (8/16/24/32-bit int, 32/64-bit float)
//! - FLAC (lossless)
//! - MP3 (lossy)
//! - OGG Vorbis (lossy)
//! - AAC/M4A (lossy)

use std::fs::File;
use std::io::BufReader;
use std::path::Path;

use rf_core::Sample;
use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

use crate::{FileError, FileResult};

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO FILE METADATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio file format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioFormat {
    Wav,
    Flac,
    Mp3,
    Ogg,
    Aac,
    Unknown,
}

impl AudioFormat {
    pub fn from_extension(ext: &str) -> Self {
        match ext.to_lowercase().as_str() {
            "wav" | "wave" => Self::Wav,
            "flac" => Self::Flac,
            "mp3" => Self::Mp3,
            "ogg" | "oga" => Self::Ogg,
            "aac" | "m4a" | "mp4" => Self::Aac,
            _ => Self::Unknown,
        }
    }

    pub fn from_path(path: &Path) -> Self {
        path.extension()
            .and_then(|e| e.to_str())
            .map(Self::from_extension)
            .unwrap_or(Self::Unknown)
    }
}

/// Bit depth of audio samples
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BitDepth {
    Int8,
    Int16,
    Int24,
    Int32,
    Float32,
    Float64,
}

impl BitDepth {
    pub fn bits(&self) -> u32 {
        match self {
            Self::Int8 => 8,
            Self::Int16 => 16,
            Self::Int24 => 24,
            Self::Int32 => 32,
            Self::Float32 => 32,
            Self::Float64 => 64,
        }
    }
}

/// Audio file metadata
#[derive(Debug, Clone)]
pub struct AudioFileInfo {
    /// File format
    pub format: AudioFormat,
    /// Number of channels
    pub channels: u16,
    /// Sample rate in Hz
    pub sample_rate: u32,
    /// Bit depth
    pub bit_depth: BitDepth,
    /// Total number of sample frames
    pub num_frames: u64,
    /// Duration in seconds
    pub duration: f64,
    /// File size in bytes
    pub file_size: u64,
}

impl AudioFileInfo {
    pub fn duration_from_frames(&self) -> f64 {
        self.num_frames as f64 / self.sample_rate as f64
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO DATA CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Loaded audio data
#[derive(Debug, Clone)]
pub struct AudioData {
    /// Audio samples (deinterleaved, one Vec per channel)
    pub channels: Vec<Vec<Sample>>,
    /// Sample rate in Hz
    pub sample_rate: u32,
    /// Original bit depth
    pub bit_depth: BitDepth,
    /// Original format
    pub format: AudioFormat,
}

impl AudioData {
    /// Create new audio data container
    pub fn new(num_channels: usize, num_frames: usize, sample_rate: u32) -> Self {
        Self {
            channels: vec![vec![0.0; num_frames]; num_channels],
            sample_rate,
            bit_depth: BitDepth::Float64,
            format: AudioFormat::Unknown,
        }
    }

    /// Number of channels
    pub fn num_channels(&self) -> usize {
        self.channels.len()
    }

    /// Number of sample frames
    pub fn num_frames(&self) -> usize {
        self.channels.first().map(|c| c.len()).unwrap_or(0)
    }

    /// Duration in seconds
    pub fn duration(&self) -> f64 {
        self.num_frames() as f64 / self.sample_rate as f64
    }

    /// Get mono mix
    pub fn to_mono(&self) -> Vec<Sample> {
        let frames = self.num_frames();
        let num_channels = self.num_channels() as f64;

        (0..frames)
            .map(|i| {
                self.channels.iter().map(|c| c[i]).sum::<f64>() / num_channels
            })
            .collect()
    }

    /// Get as interleaved samples
    pub fn to_interleaved(&self) -> Vec<Sample> {
        let frames = self.num_frames();
        let channels = self.num_channels();
        let mut interleaved = Vec::with_capacity(frames * channels);

        for i in 0..frames {
            for ch in &self.channels {
                interleaved.push(ch[i]);
            }
        }

        interleaved
    }

    /// Create from interleaved samples
    pub fn from_interleaved(
        samples: &[Sample],
        num_channels: usize,
        sample_rate: u32,
    ) -> Self {
        let num_frames = samples.len() / num_channels;
        let mut channels = vec![vec![0.0; num_frames]; num_channels];

        for (i, chunk) in samples.chunks(num_channels).enumerate() {
            for (ch, &sample) in chunk.iter().enumerate() {
                channels[ch][i] = sample;
            }
        }

        Self {
            channels,
            sample_rate,
            bit_depth: BitDepth::Float64,
            format: AudioFormat::Unknown,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WAV READING (hound)
// ═══════════════════════════════════════════════════════════════════════════════

/// Read WAV file using hound
pub fn read_wav<P: AsRef<Path>>(path: P) -> FileResult<AudioData> {
    let reader = hound::WavReader::open(path.as_ref())?;
    let spec = reader.spec();

    let num_channels = spec.channels as usize;
    let sample_rate = spec.sample_rate;
    let bit_depth = match (spec.bits_per_sample, spec.sample_format) {
        (8, _) => BitDepth::Int8,
        (16, _) => BitDepth::Int16,
        (24, _) => BitDepth::Int24,
        (32, hound::SampleFormat::Int) => BitDepth::Int32,
        (32, hound::SampleFormat::Float) => BitDepth::Float32,
        _ => BitDepth::Int16,
    };

    // Read all samples
    let samples: Vec<Sample> = match spec.sample_format {
        hound::SampleFormat::Float => {
            reader.into_samples::<f32>()
                .map(|s| s.unwrap_or(0.0) as f64)
                .collect()
        }
        hound::SampleFormat::Int => {
            let max_value = (1 << (spec.bits_per_sample - 1)) as f64;
            reader.into_samples::<i32>()
                .map(|s| s.unwrap_or(0) as f64 / max_value)
                .collect()
        }
    };

    // Deinterleave
    let num_frames = samples.len() / num_channels;
    let mut channels = vec![vec![0.0; num_frames]; num_channels];

    for (i, chunk) in samples.chunks(num_channels).enumerate() {
        for (ch, &sample) in chunk.iter().enumerate() {
            channels[ch][i] = sample;
        }
    }

    Ok(AudioData {
        channels,
        sample_rate,
        bit_depth,
        format: AudioFormat::Wav,
    })
}

/// Write WAV file using hound
pub fn write_wav<P: AsRef<Path>>(
    path: P,
    data: &AudioData,
    bit_depth: BitDepth,
) -> FileResult<()> {
    let spec = hound::WavSpec {
        channels: data.num_channels() as u16,
        sample_rate: data.sample_rate,
        bits_per_sample: bit_depth.bits() as u16,
        sample_format: match bit_depth {
            BitDepth::Float32 | BitDepth::Float64 => hound::SampleFormat::Float,
            _ => hound::SampleFormat::Int,
        },
    };

    let mut writer = hound::WavWriter::create(path.as_ref(), spec)?;

    // Interleave and write
    let num_frames = data.num_frames();
    let num_channels = data.num_channels();

    match bit_depth {
        BitDepth::Float32 | BitDepth::Float64 => {
            for i in 0..num_frames {
                for ch in 0..num_channels {
                    writer.write_sample(data.channels[ch][i] as f32)?;
                }
            }
        }
        BitDepth::Int16 => {
            for i in 0..num_frames {
                for ch in 0..num_channels {
                    let sample = (data.channels[ch][i].clamp(-1.0, 1.0) * 32767.0) as i16;
                    writer.write_sample(sample)?;
                }
            }
        }
        BitDepth::Int24 => {
            for i in 0..num_frames {
                for ch in 0..num_channels {
                    let sample = (data.channels[ch][i].clamp(-1.0, 1.0) * 8388607.0) as i32;
                    writer.write_sample(sample)?;
                }
            }
        }
        BitDepth::Int32 => {
            for i in 0..num_frames {
                for ch in 0..num_channels {
                    let sample = (data.channels[ch][i].clamp(-1.0, 1.0) * 2147483647.0) as i32;
                    writer.write_sample(sample)?;
                }
            }
        }
        BitDepth::Int8 => {
            for i in 0..num_frames {
                for ch in 0..num_channels {
                    let sample = ((data.channels[ch][i].clamp(-1.0, 1.0) + 1.0) * 127.5) as i8;
                    writer.write_sample(sample as i16)?;
                }
            }
        }
    }

    writer.finalize()?;
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════════
// SYMPHONIA READING (FLAC, MP3, OGG, AAC)
// ═══════════════════════════════════════════════════════════════════════════════

/// Read audio file using symphonia (supports FLAC, MP3, OGG, AAC)
pub fn read_audio<P: AsRef<Path>>(path: P) -> FileResult<AudioData> {
    let path = path.as_ref();
    let format = AudioFormat::from_path(path);

    // For WAV, use hound (faster)
    if format == AudioFormat::Wav {
        return read_wav(path);
    }

    // Open file
    let file = File::open(path)
        .map_err(|_| FileError::NotFound(path.display().to_string()))?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    // Probe file
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| FileError::DecodeError(e.to_string()))?;

    let mut format_reader = probed.format;

    // Get default track
    let track = format_reader
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| FileError::InvalidFile("No audio track found".to_string()))?;

    let track_id = track.id;
    let num_channels = track.codec_params.channels
        .map(|c| c.count())
        .unwrap_or(2);
    let sample_rate = track.codec_params.sample_rate.unwrap_or(44100);

    // Create decoder
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| FileError::DecodeError(e.to_string()))?;

    // Collect all samples
    let mut all_samples: Vec<Vec<Sample>> = vec![Vec::new(); num_channels];

    loop {
        match format_reader.next_packet() {
            Ok(packet) => {
                if packet.track_id() != track_id {
                    continue;
                }

                match decoder.decode(&packet) {
                    Ok(decoded) => {
                        copy_audio_buffer(&decoded, &mut all_samples);
                    }
                    Err(symphonia::core::errors::Error::DecodeError(_)) => {
                        // Skip decode errors
                        continue;
                    }
                    Err(e) => {
                        return Err(FileError::DecodeError(e.to_string()));
                    }
                }
            }
            Err(symphonia::core::errors::Error::IoError(e))
                if e.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }
            Err(e) => {
                return Err(FileError::DecodeError(e.to_string()));
            }
        }
    }

    Ok(AudioData {
        channels: all_samples,
        sample_rate,
        bit_depth: BitDepth::Float64,
        format,
    })
}

/// Copy samples from symphonia buffer to our format
fn copy_audio_buffer(buffer: &AudioBufferRef, output: &mut [Vec<Sample>]) {
    match buffer {
        AudioBufferRef::F32(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|&s| s as f64));
                }
            }
        }
        AudioBufferRef::F64(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().copied());
                }
            }
        }
        AudioBufferRef::S16(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|&s| s as f64 / 32768.0));
                }
            }
        }
        AudioBufferRef::S24(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|s| s.0 as f64 / 8388608.0));
                }
            }
        }
        AudioBufferRef::S32(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|&s| s as f64 / 2147483648.0));
                }
            }
        }
        AudioBufferRef::U8(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|&s| (s as f64 - 128.0) / 128.0));
                }
            }
        }
        AudioBufferRef::U16(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|&s| (s as f64 - 32768.0) / 32768.0));
                }
            }
        }
        AudioBufferRef::U24(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|s| (s.0 as f64 - 8388608.0) / 8388608.0));
                }
            }
        }
        AudioBufferRef::U32(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|&s| (s as f64 - 2147483648.0) / 2147483648.0));
                }
            }
        }
        AudioBufferRef::S8(buf) => {
            for (ch, out_ch) in output.iter_mut().enumerate() {
                if ch < buf.spec().channels.count() {
                    out_ch.extend(buf.chan(ch).iter().map(|&s| s as f64 / 128.0));
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILE INFO
// ═══════════════════════════════════════════════════════════════════════════════

/// Get audio file info without fully loading
pub fn get_audio_info<P: AsRef<Path>>(path: P) -> FileResult<AudioFileInfo> {
    let path = path.as_ref();
    let format = AudioFormat::from_path(path);

    let file_size = std::fs::metadata(path)
        .map(|m| m.len())
        .unwrap_or(0);

    // For WAV, use hound
    if format == AudioFormat::Wav {
        let reader = hound::WavReader::open(path)?;
        let spec = reader.spec();
        let num_frames = reader.duration() as u64;

        return Ok(AudioFileInfo {
            format,
            channels: spec.channels,
            sample_rate: spec.sample_rate,
            bit_depth: match (spec.bits_per_sample, spec.sample_format) {
                (8, _) => BitDepth::Int8,
                (16, _) => BitDepth::Int16,
                (24, _) => BitDepth::Int24,
                (32, hound::SampleFormat::Int) => BitDepth::Int32,
                (32, hound::SampleFormat::Float) => BitDepth::Float32,
                _ => BitDepth::Int16,
            },
            num_frames,
            duration: num_frames as f64 / spec.sample_rate as f64,
            file_size,
        });
    }

    // Use symphonia for other formats
    let file = File::open(path)
        .map_err(|_| FileError::NotFound(path.display().to_string()))?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| FileError::DecodeError(e.to_string()))?;

    let track = probed.format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| FileError::InvalidFile("No audio track found".to_string()))?;

    let channels = track.codec_params.channels
        .map(|c| c.count() as u16)
        .unwrap_or(2);
    let sample_rate = track.codec_params.sample_rate.unwrap_or(44100);
    let num_frames = track.codec_params.n_frames.unwrap_or(0);
    let duration = num_frames as f64 / sample_rate as f64;

    Ok(AudioFileInfo {
        format,
        channels,
        sample_rate,
        bit_depth: BitDepth::Float32, // Compressed formats are decoded to float
        num_frames,
        duration,
        file_size,
    })
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audio_format_from_extension() {
        assert_eq!(AudioFormat::from_extension("wav"), AudioFormat::Wav);
        assert_eq!(AudioFormat::from_extension("FLAC"), AudioFormat::Flac);
        assert_eq!(AudioFormat::from_extension("mp3"), AudioFormat::Mp3);
        assert_eq!(AudioFormat::from_extension("ogg"), AudioFormat::Ogg);
        assert_eq!(AudioFormat::from_extension("m4a"), AudioFormat::Aac);
        assert_eq!(AudioFormat::from_extension("xyz"), AudioFormat::Unknown);
    }

    #[test]
    fn test_audio_data_creation() {
        let data = AudioData::new(2, 1000, 48000);

        assert_eq!(data.num_channels(), 2);
        assert_eq!(data.num_frames(), 1000);
        assert!((data.duration() - 1000.0 / 48000.0).abs() < 0.0001);
    }

    #[test]
    fn test_interleave_deinterleave() {
        let interleaved = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
        let data = AudioData::from_interleaved(&interleaved, 2, 48000);

        assert_eq!(data.num_channels(), 2);
        assert_eq!(data.num_frames(), 3);
        assert_eq!(data.channels[0], vec![1.0, 3.0, 5.0]);
        assert_eq!(data.channels[1], vec![2.0, 4.0, 6.0]);

        let back = data.to_interleaved();
        assert_eq!(back, interleaved);
    }

    #[test]
    fn test_to_mono() {
        let data = AudioData {
            channels: vec![
                vec![1.0, 0.0],
                vec![0.0, 1.0],
            ],
            sample_rate: 48000,
            bit_depth: BitDepth::Float64,
            format: AudioFormat::Unknown,
        };

        let mono = data.to_mono();
        assert_eq!(mono, vec![0.5, 0.5]);
    }
}

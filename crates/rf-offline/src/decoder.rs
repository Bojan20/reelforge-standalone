//! Audio decoding module
//!
//! Uses symphonia for decoding multiple formats:
//! - WAV, AIFF (PCM)
//! - FLAC (lossless)
//! - MP3, OGG Vorbis, AAC (lossy)

use crate::error::{OfflineError, OfflineResult};
use crate::pipeline::AudioBuffer;

use std::fs::File;
use std::path::Path;

use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

// ═══════════════════════════════════════════════════════════════════════════════
// DECODER
// ═══════════════════════════════════════════════════════════════════════════════

/// Universal audio decoder using symphonia
pub struct AudioDecoder;

impl AudioDecoder {
    /// Decode audio file to AudioBuffer
    pub fn decode(path: &Path) -> OfflineResult<AudioBuffer> {
        // Create media source stream
        let file = File::open(path)
            .map_err(|e| OfflineError::ReadError(format!("Failed to open file: {}", e)))?;

        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        // Create hint from file extension
        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        // Probe format
        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .map_err(|e| OfflineError::ReadError(format!("Failed to probe format: {}", e)))?;

        let mut format = probed.format;

        // Find first audio track
        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
            .ok_or_else(|| OfflineError::ReadError("No audio track found".to_string()))?;

        let track_id = track.id;

        // Get codec parameters
        let codec_params = track.codec_params.clone();
        let sample_rate = codec_params.sample_rate.unwrap_or(44100);
        let channels = codec_params.channels.map(|c| c.count()).unwrap_or(2);

        // Create decoder
        let mut decoder = symphonia::default::get_codecs()
            .make(&codec_params, &DecoderOptions::default())
            .map_err(|e| OfflineError::ReadError(format!("Failed to create decoder: {}", e)))?;

        // Decode all packets
        let mut samples: Vec<f64> = Vec::new();

        loop {
            match format.next_packet() {
                Ok(packet) => {
                    if packet.track_id() != track_id {
                        continue;
                    }

                    match decoder.decode(&packet) {
                        Ok(decoded) => {
                            Self::append_samples(&decoded, channels, &mut samples);
                        }
                        Err(symphonia::core::errors::Error::DecodeError(_)) => {
                            // Skip decode errors
                            continue;
                        }
                        Err(e) => {
                            return Err(OfflineError::ReadError(format!("Decode error: {}", e)));
                        }
                    }
                }
                Err(symphonia::core::errors::Error::IoError(ref e))
                    if e.kind() == std::io::ErrorKind::UnexpectedEof =>
                {
                    // End of file
                    break;
                }
                Err(e) => {
                    return Err(OfflineError::ReadError(format!("Packet read error: {}", e)));
                }
            }
        }

        Ok(AudioBuffer {
            samples,
            channels,
            sample_rate,
        })
    }

    /// Append decoded samples to output buffer
    fn append_samples(decoded: &AudioBufferRef, channels: usize, output: &mut Vec<f64>) {
        match decoded {
            AudioBufferRef::F32(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = planes.planes()[ch][frame] as f64;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::F64(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        output.push(planes.planes()[ch][frame]);
                    }
                }
            }
            AudioBufferRef::S16(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = planes.planes()[ch][frame] as f64 / 32768.0;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::S24(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = planes.planes()[ch][frame].inner() as f64 / 8388608.0;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::S32(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = planes.planes()[ch][frame] as f64 / 2147483648.0;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::U8(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = (planes.planes()[ch][frame] as f64 - 128.0) / 128.0;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::U16(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = (planes.planes()[ch][frame] as f64 - 32768.0) / 32768.0;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::U24(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = (planes.planes()[ch][frame].inner() as f64 - 8388608.0) / 8388608.0;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::U32(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = (planes.planes()[ch][frame] as f64 - 2147483648.0) / 2147483648.0;
                        output.push(sample);
                    }
                }
            }
            AudioBufferRef::S8(buf) => {
                let planes = buf.planes();
                let frames = buf.frames();

                for frame in 0..frames {
                    for ch in 0..channels.min(planes.planes().len()) {
                        let sample = planes.planes()[ch][frame] as f64 / 128.0;
                        output.push(sample);
                    }
                }
            }
        }
    }

    /// Get audio file info without decoding
    pub fn probe(path: &Path) -> OfflineResult<AudioFileInfo> {
        let file = File::open(path)
            .map_err(|e| OfflineError::ReadError(format!("Failed to open file: {}", e)))?;

        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .map_err(|e| OfflineError::ReadError(format!("Failed to probe format: {}", e)))?;

        let format = probed.format;

        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
            .ok_or_else(|| OfflineError::ReadError("No audio track found".to_string()))?;

        let codec_params = &track.codec_params;

        let sample_rate = codec_params.sample_rate.unwrap_or(44100);
        let channels = codec_params.channels.map(|c| c.count()).unwrap_or(2);
        let bit_depth = codec_params.bits_per_sample.unwrap_or(16);

        let duration = codec_params.n_frames
            .map(|f| f as f64 / sample_rate as f64)
            .unwrap_or(0.0);

        let format_name = path.extension()
            .and_then(|e| e.to_str())
            .unwrap_or("unknown")
            .to_uppercase();

        Ok(AudioFileInfo {
            path: path.to_path_buf(),
            format: format_name,
            sample_rate,
            channels,
            bit_depth: bit_depth as u8,
            duration,
            samples: codec_params.n_frames.unwrap_or(0) as usize,
        })
    }

    /// Get list of supported formats
    pub fn supported_formats() -> &'static [&'static str] {
        &["wav", "flac", "mp3", "ogg", "aac", "m4a", "aiff"]
    }
}

/// Audio file information
#[derive(Debug, Clone)]
pub struct AudioFileInfo {
    pub path: std::path::PathBuf,
    pub format: String,
    pub sample_rate: u32,
    pub channels: usize,
    pub bit_depth: u8,
    pub duration: f64,
    pub samples: usize,
}

impl AudioFileInfo {
    /// Get duration as formatted string
    pub fn duration_str(&self) -> String {
        let total_secs = self.duration as u64;
        let hours = total_secs / 3600;
        let mins = (total_secs % 3600) / 60;
        let secs = total_secs % 60;
        let ms = ((self.duration - total_secs as f64) * 1000.0) as u64;

        if hours > 0 {
            format!("{}:{:02}:{:02}.{:03}", hours, mins, secs, ms)
        } else {
            format!("{}:{:02}.{:03}", mins, secs, ms)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_supported_formats() {
        let formats = AudioDecoder::supported_formats();
        assert!(formats.contains(&"wav"));
        assert!(formats.contains(&"flac"));
        assert!(formats.contains(&"mp3"));
    }

    #[test]
    fn test_duration_str() {
        let info = AudioFileInfo {
            path: std::path::PathBuf::from("test.wav"),
            format: "WAV".to_string(),
            sample_rate: 44100,
            channels: 2,
            bit_depth: 16,
            duration: 65.5,  // 1:05.500
            samples: 44100 * 65,
        };

        assert_eq!(info.duration_str(), "1:05.500");
    }
}

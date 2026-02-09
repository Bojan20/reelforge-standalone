//! Audio file loading utilities

use crate::{AudioDiffError, Result};
use std::path::Path;
use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Loaded audio data
#[derive(Debug, Clone)]
pub struct AudioData {
    /// Sample data per channel
    pub channels: Vec<Vec<f64>>,

    /// Sample rate in Hz
    pub sample_rate: u32,

    /// Number of channels
    pub num_channels: usize,

    /// Total number of samples per channel
    pub num_samples: usize,

    /// Duration in seconds
    pub duration: f64,

    /// Source file path
    pub source_path: String,
}

impl AudioData {
    /// Load audio from file
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self> {
        let path = path.as_ref();
        let path_str = path.display().to_string();

        // Check file extension for WAV (use hound for better precision)
        if let Some(ext) = path.extension() {
            if ext.eq_ignore_ascii_case("wav") {
                return Self::load_wav(path, &path_str);
            }
        }

        // Use symphonia for other formats
        Self::load_symphonia(path, &path_str)
    }

    /// Load WAV file using hound (more precise for 32-bit float)
    fn load_wav(path: &Path, path_str: &str) -> Result<Self> {
        let reader = hound::WavReader::open(path)
            .map_err(|e| AudioDiffError::LoadError(format!("{}: {}", path_str, e)))?;

        let spec = reader.spec();
        let sample_rate = spec.sample_rate;
        let num_channels = spec.channels as usize;

        let samples: Vec<f64> = match spec.sample_format {
            hound::SampleFormat::Float => reader
                .into_samples::<f32>()
                .map(|s| s.map(|v| v as f64))
                .collect::<std::result::Result<Vec<_>, _>>()
                .map_err(|e| AudioDiffError::LoadError(format!("{}: {}", path_str, e)))?,
            hound::SampleFormat::Int => {
                let bits = spec.bits_per_sample;
                let max_val = (1i64 << (bits - 1)) as f64;
                reader
                    .into_samples::<i32>()
                    .map(|s| s.map(|v| v as f64 / max_val))
                    .collect::<std::result::Result<Vec<_>, _>>()
                    .map_err(|e| AudioDiffError::LoadError(format!("{}: {}", path_str, e)))?
            }
        };

        // Deinterleave channels
        let num_samples = samples.len() / num_channels;
        let mut channels = vec![Vec::with_capacity(num_samples); num_channels];

        for (i, sample) in samples.into_iter().enumerate() {
            channels[i % num_channels].push(sample);
        }

        let duration = num_samples as f64 / sample_rate as f64;

        Ok(Self {
            channels,
            sample_rate,
            num_channels,
            num_samples,
            duration,
            source_path: path_str.to_string(),
        })
    }

    /// Load audio using symphonia (supports multiple formats)
    fn load_symphonia(path: &Path, path_str: &str) -> Result<Self> {
        let file = std::fs::File::open(path)?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(
                &hint,
                mss,
                &FormatOptions::default(),
                &MetadataOptions::default(),
            )
            .map_err(|e| AudioDiffError::LoadError(format!("{}: {}", path_str, e)))?;

        let mut format = probed.format;

        let track = format
            .default_track()
            .ok_or_else(|| AudioDiffError::LoadError(format!("{}: no audio track", path_str)))?;

        let sample_rate = track.codec_params.sample_rate.ok_or_else(|| {
            AudioDiffError::LoadError(format!("{}: unknown sample rate", path_str))
        })?;

        let num_channels = track
            .codec_params
            .channels
            .map(|c| c.count())
            .ok_or_else(|| AudioDiffError::LoadError(format!("{}: unknown channels", path_str)))?;

        let mut decoder = symphonia::default::get_codecs()
            .make(&track.codec_params, &DecoderOptions::default())
            .map_err(|e| AudioDiffError::LoadError(format!("{}: {}", path_str, e)))?;

        let track_id = track.id;
        let mut channels = vec![Vec::new(); num_channels];

        loop {
            let packet = match format.next_packet() {
                Ok(p) => p,
                Err(symphonia::core::errors::Error::IoError(ref e))
                    if e.kind() == std::io::ErrorKind::UnexpectedEof =>
                {
                    break
                }
                Err(e) => return Err(AudioDiffError::LoadError(format!("{}: {}", path_str, e))),
            };

            if packet.track_id() != track_id {
                continue;
            }

            let decoded = decoder
                .decode(&packet)
                .map_err(|e| AudioDiffError::LoadError(format!("{}: {}", path_str, e)))?;

            Self::copy_samples(&decoded, &mut channels);
        }

        let num_samples = channels.first().map(|c| c.len()).unwrap_or(0);
        let duration = num_samples as f64 / sample_rate as f64;

        Ok(Self {
            channels,
            sample_rate,
            num_channels,
            num_samples,
            duration,
            source_path: path_str.to_string(),
        })
    }

    /// Copy decoded samples to channel vectors
    fn copy_samples(buffer: &AudioBufferRef, channels: &mut [Vec<f64>]) {
        match buffer {
            AudioBufferRef::F32(buf) => {
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|&s| s as f64));
                    }
                }
            }
            AudioBufferRef::F64(buf) => {
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().copied());
                    }
                }
            }
            AudioBufferRef::S16(buf) => {
                const SCALE: f64 = 1.0 / 32768.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|&s| s as f64 * SCALE));
                    }
                }
            }
            AudioBufferRef::S32(buf) => {
                const SCALE: f64 = 1.0 / 2147483648.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|&s| s as f64 * SCALE));
                    }
                }
            }
            AudioBufferRef::U8(buf) => {
                const SCALE: f64 = 1.0 / 128.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|&s| (s as f64 - 128.0) * SCALE));
                    }
                }
            }
            AudioBufferRef::S24(buf) => {
                const SCALE: f64 = 1.0 / 8388608.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|s| s.inner() as f64 * SCALE));
                    }
                }
            }
            AudioBufferRef::U16(buf) => {
                const SCALE: f64 = 1.0 / 32768.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|&s| (s as f64 - 32768.0) * SCALE));
                    }
                }
            }
            AudioBufferRef::U24(buf) => {
                const SCALE: f64 = 1.0 / 8388608.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel
                            .extend(plane.iter().map(|s| (s.inner() as f64 - 8388608.0) * SCALE));
                    }
                }
            }
            AudioBufferRef::U32(buf) => {
                const SCALE: f64 = 1.0 / 2147483648.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|&s| (s as f64 - 2147483648.0) * SCALE));
                    }
                }
            }
            AudioBufferRef::S8(buf) => {
                const SCALE: f64 = 1.0 / 128.0;
                for (ch_idx, channel) in channels.iter_mut().enumerate() {
                    if ch_idx < buf.spec().channels.count() {
                        let plane = buf.chan(ch_idx);
                        channel.extend(plane.iter().map(|&s| s as f64 * SCALE));
                    }
                }
            }
        }
    }

    /// Convert to mono by summing channels
    pub fn to_mono(&self) -> Vec<f64> {
        if self.num_channels == 1 {
            return self.channels[0].clone();
        }

        let scale = 1.0 / self.num_channels as f64;
        (0..self.num_samples)
            .map(|i| {
                self.channels
                    .iter()
                    .map(|ch| ch.get(i).copied().unwrap_or(0.0))
                    .sum::<f64>()
                    * scale
            })
            .collect()
    }

    /// Get interleaved samples
    pub fn interleaved(&self) -> Vec<f64> {
        let mut result = Vec::with_capacity(self.num_samples * self.num_channels);
        for i in 0..self.num_samples {
            for ch in &self.channels {
                result.push(ch.get(i).copied().unwrap_or(0.0));
            }
        }
        result
    }

    /// Get peak amplitude
    pub fn peak(&self) -> f64 {
        self.channels
            .iter()
            .flat_map(|ch| ch.iter())
            .map(|s| s.abs())
            .fold(0.0, f64::max)
    }

    /// Get RMS level
    pub fn rms(&self) -> f64 {
        let sum: f64 = self
            .channels
            .iter()
            .flat_map(|ch| ch.iter())
            .map(|s| s * s)
            .sum();
        let count = self.num_samples * self.num_channels;
        (sum / count as f64).sqrt()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audio_data_mono() {
        let data = AudioData {
            channels: vec![vec![1.0, 0.5, -0.5, -1.0]],
            sample_rate: 44100,
            num_channels: 1,
            num_samples: 4,
            duration: 4.0 / 44100.0,
            source_path: "test.wav".into(),
        };

        assert_eq!(data.peak(), 1.0);
        // RMS = sqrt((1 + 0.25 + 0.25 + 1) / 4) = sqrt(0.625) ≈ 0.7906
        assert!((data.rms() - 0.7906).abs() < 0.01);
    }

    #[test]
    fn test_to_mono() {
        let data = AudioData {
            channels: vec![vec![1.0, 0.0], vec![0.0, 1.0]],
            sample_rate: 44100,
            num_channels: 2,
            num_samples: 2,
            duration: 2.0 / 44100.0,
            source_path: "test.wav".into(),
        };

        let mono = data.to_mono();
        assert_eq!(mono, vec![0.5, 0.5]);
    }
}

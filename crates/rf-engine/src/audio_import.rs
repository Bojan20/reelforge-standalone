//! Audio File Import
//!
//! Provides:
//! - Audio file decoding (WAV, MP3, FLAC, OGG, AAC, ALAC via symphonia)
//! - Automatic sample rate conversion
//! - Waveform peak generation for UI display
//! - Streaming import for large files

use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use thiserror::Error;

use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::codecs::{Decoder, DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::formats::{FormatOptions, FormatReader};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

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

    #[error("No audio tracks found")]
    NoAudioTracks,

    #[error("Unsupported codec: {0}")]
    UnsupportedCodec(String),
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

    /// Original bit depth (if known)
    pub bit_depth: Option<u8>,

    /// Original format (wav, mp3, flac, etc.)
    pub format: String,
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
        let format = Path::new(source_path)
            .extension()
            .map(|s| s.to_string_lossy().to_lowercase())
            .unwrap_or_else(|| "unknown".to_string());

        Self {
            samples,
            sample_rate,
            channels: 1,
            duration_secs,
            sample_count,
            source_path: source_path.to_string(),
            name,
            bit_depth: None,
            format,
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
        let format = Path::new(source_path)
            .extension()
            .map(|s| s.to_string_lossy().to_lowercase())
            .unwrap_or_else(|| "unknown".to_string());

        Self {
            samples,
            sample_rate,
            channels: 2,
            duration_secs,
            sample_count,
            source_path: source_path.to_string(),
            name,
            bit_depth: None,
            format,
        }
    }

    /// Create with specified channel count
    pub fn new(samples: Vec<f32>, sample_rate: u32, channels: u8, source_path: &str) -> Self {
        let sample_count = samples.len() / channels as usize;
        let duration_secs = sample_count as f64 / sample_rate as f64;
        let name = Path::new(source_path)
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "Unknown".to_string());
        let format = Path::new(source_path)
            .extension()
            .map(|s| s.to_string_lossy().to_lowercase())
            .unwrap_or_else(|| "unknown".to_string());

        Self {
            samples,
            sample_rate,
            channels,
            duration_secs,
            sample_count,
            source_path: source_path.to_string(),
            name,
            bit_depth: None,
            format,
        }
    }

    /// Get left channel samples (or mono samples)
    pub fn left_channel(&self) -> Vec<f32> {
        if self.channels == 1 {
            self.samples.clone()
        } else {
            self.samples.iter().step_by(self.channels as usize).copied().collect()
        }
    }

    /// Get right channel samples (or mono samples for mono files)
    pub fn right_channel(&self) -> Vec<f32> {
        if self.channels == 1 {
            self.samples.clone()
        } else if self.channels >= 2 {
            self.samples.iter().skip(1).step_by(self.channels as usize).copied().collect()
        } else {
            self.samples.clone()
        }
    }

    /// Get specific channel samples
    pub fn channel(&self, channel_idx: usize) -> Vec<f32> {
        if channel_idx >= self.channels as usize {
            return vec![];
        }
        self.samples
            .iter()
            .skip(channel_idx)
            .step_by(self.channels as usize)
            .copied()
            .collect()
    }

    /// Convert to mono by averaging channels
    pub fn to_mono(&self) -> Vec<f32> {
        if self.channels == 1 {
            return self.samples.clone();
        }

        let mut mono = Vec::with_capacity(self.sample_count);
        let ch = self.channels as usize;

        for i in 0..self.sample_count {
            let mut sum = 0.0f32;
            for c in 0..ch {
                sum += self.samples[i * ch + c];
            }
            mono.push(sum / ch as f32);
        }

        mono
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
    /// Supports: WAV, MP3, FLAC, OGG, AAC, ALAC, AIFF
    pub fn import(path: &Path) -> Result<ImportedAudio, ImportError> {
        if !path.exists() {
            return Err(ImportError::FileNotFound(path.display().to_string()));
        }

        let extension = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.to_lowercase())
            .unwrap_or_default();

        // Use symphonia for all supported formats
        match extension.as_str() {
            "wav" | "wave" => Self::import_symphonia(path),
            "mp3" => Self::import_symphonia(path),
            "flac" => Self::import_symphonia(path),
            "ogg" | "oga" => Self::import_symphonia(path),
            "m4a" | "aac" => Self::import_symphonia(path),
            "aiff" | "aif" => Self::import_symphonia(path),
            _ => Err(ImportError::UnsupportedFormat(extension)),
        }
    }

    /// Import using symphonia (supports all formats)
    fn import_symphonia(path: &Path) -> Result<ImportedAudio, ImportError> {
        let file = File::open(path)?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        // Create hint with extension
        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        // Probe the format
        let format_opts = FormatOptions::default();
        let metadata_opts = MetadataOptions::default();

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &format_opts, &metadata_opts)
            .map_err(|e| ImportError::DecodeError(format!("Probe failed: {}", e)))?;

        let mut format = probed.format;

        // Find the first audio track
        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
            .ok_or(ImportError::NoAudioTracks)?;

        let track_id = track.id;

        // Get codec parameters
        let codec_params = &track.codec_params;
        let sample_rate = codec_params.sample_rate.unwrap_or(48000);
        let channels = codec_params.channels.map(|c| c.count()).unwrap_or(2) as u8;
        let bit_depth = codec_params.bits_per_sample;

        // Create decoder
        let decoder_opts = DecoderOptions::default();
        let mut decoder = symphonia::default::get_codecs()
            .make(codec_params, &decoder_opts)
            .map_err(|e| ImportError::UnsupportedCodec(format!("{}", e)))?;

        // Decode all packets
        let mut samples: Vec<f32> = Vec::new();

        loop {
            let packet = match format.next_packet() {
                Ok(packet) => packet,
                Err(symphonia::core::errors::Error::IoError(ref e))
                    if e.kind() == std::io::ErrorKind::UnexpectedEof =>
                {
                    break; // End of stream
                }
                Err(symphonia::core::errors::Error::ResetRequired) => {
                    // Reset decoder and continue
                    decoder.reset();
                    continue;
                }
                Err(e) => {
                    log::warn!("Packet decode error: {}", e);
                    break;
                }
            };

            // Skip packets from other tracks
            if packet.track_id() != track_id {
                continue;
            }

            // Decode the packet
            match decoder.decode(&packet) {
                Ok(decoded) => {
                    Self::append_samples(&decoded, channels, &mut samples);
                }
                Err(symphonia::core::errors::Error::DecodeError(e)) => {
                    log::warn!("Decode error: {}", e);
                    continue;
                }
                Err(e) => {
                    log::warn!("Decode error: {}", e);
                    break;
                }
            }
        }

        if samples.is_empty() {
            return Err(ImportError::DecodeError("No audio samples decoded".to_string()));
        }

        let path_str = path.display().to_string();
        let mut audio = ImportedAudio::new(samples, sample_rate, channels, &path_str);
        audio.bit_depth = bit_depth.map(|b| b as u8);

        log::info!(
            "Imported {}: {}ch, {}Hz, {:.2}s, {} samples",
            audio.name, audio.channels, audio.sample_rate,
            audio.duration_secs, audio.sample_count
        );

        Ok(audio)
    }

    /// Append decoded samples to output buffer
    fn append_samples(decoded: &AudioBufferRef, channels: u8, samples: &mut Vec<f32>) {
        match decoded {
            AudioBufferRef::F32(buf) => {
                // Already f32 - just interleave
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        samples.push(buf.chan(c)[frame]);
                    }
                    // Pad with zeros if source has fewer channels
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::F64(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        samples.push(buf.chan(c)[frame] as f32);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::S16(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        samples.push(buf.chan(c)[frame] as f32 / 32768.0);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::S24(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        let sample = buf.chan(c)[frame].inner();
                        samples.push(sample as f32 / 8388608.0);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::S32(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        samples.push(buf.chan(c)[frame] as f32 / 2147483648.0);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::U8(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        let sample = buf.chan(c)[frame] as f32;
                        samples.push((sample - 128.0) / 128.0);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::U16(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        let sample = buf.chan(c)[frame] as f32;
                        samples.push((sample - 32768.0) / 32768.0);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::U24(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        let sample = buf.chan(c)[frame].inner() as f32;
                        samples.push((sample - 8388608.0) / 8388608.0);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::U32(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        let sample = buf.chan(c)[frame] as f64;
                        samples.push(((sample - 2147483648.0) / 2147483648.0) as f32);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
            AudioBufferRef::S8(buf) => {
                let frames = buf.frames();
                let ch = buf.spec().channels.count();

                for frame in 0..frames {
                    for c in 0..ch.min(channels as usize) {
                        let sample = buf.chan(c)[frame] as f32;
                        samples.push(sample / 128.0);
                    }
                    for _ in ch..channels as usize {
                        samples.push(0.0);
                    }
                }
            }
        }
    }

    /// Get audio file info without fully decoding
    pub fn get_info(path: &Path) -> Result<AudioFileInfo, ImportError> {
        if !path.exists() {
            return Err(ImportError::FileNotFound(path.display().to_string()));
        }

        let file = File::open(path)?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .map_err(|e| ImportError::DecodeError(format!("Probe failed: {}", e)))?;

        let format = probed.format;

        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
            .ok_or(ImportError::NoAudioTracks)?;

        let codec_params = &track.codec_params;
        let sample_rate = codec_params.sample_rate.unwrap_or(48000);
        let channels = codec_params.channels.map(|c| c.count()).unwrap_or(2) as u8;
        let bit_depth = codec_params.bits_per_sample;

        // Calculate duration if available
        let duration_secs = codec_params.n_frames
            .map(|frames| frames as f64 / sample_rate as f64);

        let format_name = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.to_lowercase())
            .unwrap_or_else(|| "unknown".to_string());

        Ok(AudioFileInfo {
            sample_rate,
            channels,
            bit_depth: bit_depth.map(|b| b as u8),
            duration_secs,
            format: format_name,
            path: path.display().to_string(),
        })
    }
}

/// Audio file information (without full decode)
#[derive(Debug, Clone)]
pub struct AudioFileInfo {
    pub sample_rate: u32,
    pub channels: u8,
    pub bit_depth: Option<u8>,
    pub duration_secs: Option<f64>,
    pub format: String,
    pub path: String,
}

// ═══════════════════════════════════════════════════════════════════════════
// SAMPLE RATE CONVERSION
// ═══════════════════════════════════════════════════════════════════════════

/// Sample rate converter using sinc interpolation
pub struct SampleRateConverter;

impl SampleRateConverter {
    /// Convert sample rate using linear interpolation (fast, lower quality)
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
        let samples_per_channel = samples.len() / channels as usize;
        let new_samples_per_channel = (samples_per_channel as f64 * ratio) as usize;
        let mut output = Vec::with_capacity(new_samples_per_channel * channels as usize);

        for ch in 0..channels as usize {
            for i in 0..new_samples_per_channel {
                let src_pos = i as f64 / ratio;
                let src_idx = src_pos.floor() as usize;
                let frac = src_pos - src_idx as f64;

                let idx = src_idx * channels as usize + ch;
                let next_idx = ((src_idx + 1).min(samples_per_channel - 1)) * channels as usize + ch;

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

        // Re-interleave channels
        if channels > 1 {
            let mut interleaved = Vec::with_capacity(output.len());
            for i in 0..new_samples_per_channel {
                for ch in 0..channels as usize {
                    interleaved.push(output[ch * new_samples_per_channel + i]);
                }
            }
            output = interleaved;
        }

        output
    }

    /// Convert sample rate using sinc interpolation (slower, higher quality)
    /// Uses Lanczos-3 kernel for high quality resampling
    pub fn convert_sinc(
        samples: &[f32],
        from_rate: u32,
        to_rate: u32,
        channels: u8,
    ) -> Vec<f32> {
        if from_rate == to_rate {
            return samples.to_vec();
        }

        const LANCZOS_A: i32 = 3; // Lanczos-3 kernel

        let ratio = to_rate as f64 / from_rate as f64;
        let samples_per_channel = samples.len() / channels as usize;
        let new_samples_per_channel = (samples_per_channel as f64 * ratio) as usize;
        let mut output = vec![0.0f32; new_samples_per_channel * channels as usize];

        // Process each channel
        for ch in 0..channels as usize {
            for i in 0..new_samples_per_channel {
                let src_pos = i as f64 / ratio;
                let src_idx = src_pos.floor() as i64;
                let frac = src_pos - src_idx as f64;

                let mut sum = 0.0f64;
                let mut weight_sum = 0.0f64;

                // Apply Lanczos kernel
                for k in (-LANCZOS_A + 1)..=LANCZOS_A {
                    let sample_idx = src_idx + k as i64;
                    if sample_idx < 0 || sample_idx >= samples_per_channel as i64 {
                        continue;
                    }

                    let x = frac - k as f64;
                    let weight = Self::lanczos(x, LANCZOS_A as f64);

                    let idx = (sample_idx as usize) * channels as usize + ch;
                    if idx < samples.len() {
                        sum += samples[idx] as f64 * weight;
                        weight_sum += weight;
                    }
                }

                let out_idx = i * channels as usize + ch;
                output[out_idx] = if weight_sum > 0.0 {
                    (sum / weight_sum) as f32
                } else {
                    0.0
                };
            }
        }

        output
    }

    /// Lanczos kernel function
    #[inline]
    fn lanczos(x: f64, a: f64) -> f64 {
        if x.abs() < 1e-10 {
            return 1.0;
        }
        if x.abs() >= a {
            return 0.0;
        }

        let pi_x = std::f64::consts::PI * x;
        let pi_x_a = pi_x / a;

        (pi_x.sin() * pi_x_a.sin()) / (pi_x * pi_x_a)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM GENERATION
// ═══════════════════════════════════════════════════════════════════════════

/// Waveform peak data for UI display
#[derive(Debug, Clone)]
pub struct WaveformPeaks {
    /// Min/max pairs for each segment
    pub peaks: Vec<(f32, f32)>,
    /// Samples per peak
    pub samples_per_peak: usize,
    /// Total source samples
    pub total_samples: usize,
    /// Channel (0=left, 1=right, etc.)
    pub channel: usize,
}

impl WaveformPeaks {
    /// Generate waveform peaks from audio samples
    pub fn generate(samples: &[f32], channels: u8, channel: usize, target_peaks: usize) -> Self {
        let samples_per_channel = samples.len() / channels as usize;
        let samples_per_peak = (samples_per_channel / target_peaks).max(1);

        let mut peaks = Vec::with_capacity(target_peaks);

        for peak_idx in 0..target_peaks {
            let start = peak_idx * samples_per_peak;
            let end = (start + samples_per_peak).min(samples_per_channel);

            let mut min_val = f32::MAX;
            let mut max_val = f32::MIN;

            for i in start..end {
                let idx = i * channels as usize + channel;
                if idx < samples.len() {
                    let sample = samples[idx];
                    min_val = min_val.min(sample);
                    max_val = max_val.max(sample);
                }
            }

            if min_val == f32::MAX {
                min_val = 0.0;
                max_val = 0.0;
            }

            peaks.push((min_val, max_val));
        }

        Self {
            peaks,
            samples_per_peak,
            total_samples: samples_per_channel,
            channel,
        }
    }

    /// Generate multi-resolution LOD (Level of Detail) waveforms
    pub fn generate_lod(
        samples: &[f32],
        channels: u8,
        channel: usize,
        levels: &[usize],
    ) -> Vec<WaveformPeaks> {
        levels
            .iter()
            .map(|&target_peaks| Self::generate(samples, channels, channel, target_peaks))
            .collect()
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
        assert_eq!(audio.format, "wav");
    }

    #[test]
    fn test_imported_audio_stereo() {
        let samples = vec![0.0f32; 96000]; // 48000 * 2 channels
        let audio = ImportedAudio::new_stereo(samples, 48000, "/test/stereo.wav");

        assert_eq!(audio.channels, 2);
        assert_eq!(audio.duration_secs, 1.0);
    }

    #[test]
    fn test_imported_audio_new() {
        let samples = vec![0.0f32; 48000 * 6]; // 6 channels
        let audio = ImportedAudio::new(samples, 48000, 6, "/test/surround.wav");

        assert_eq!(audio.channels, 6);
        assert_eq!(audio.sample_count, 48000);
    }

    #[test]
    fn test_sample_rate_conversion_linear() {
        let samples: Vec<f32> = (0..44100).map(|i| (i as f32 / 44100.0).sin()).collect();
        let converted = SampleRateConverter::convert_linear(&samples, 44100, 48000, 1);

        // Should be approximately 48000 samples
        assert!((converted.len() as i32 - 48000).abs() < 10);
    }

    #[test]
    fn test_sample_rate_conversion_sinc() {
        let samples: Vec<f32> = (0..4410).map(|i| (i as f32 / 4410.0).sin()).collect();
        let converted = SampleRateConverter::convert_sinc(&samples, 44100, 48000, 1);

        // Should be approximately 4800 samples (10x smaller test)
        assert!((converted.len() as i32 - 4800).abs() < 10);
    }

    #[test]
    fn test_waveform_peaks() {
        let samples: Vec<f32> = (0..48000)
            .map(|i| ((i as f32 / 48000.0) * std::f32::consts::PI * 2.0 * 440.0).sin())
            .collect();

        let peaks = WaveformPeaks::generate(&samples, 1, 0, 1000);

        assert_eq!(peaks.peaks.len(), 1000);
        assert!(peaks.peaks.iter().all(|(min, max)| *min <= *max));
    }

    #[test]
    fn test_to_mono() {
        let samples = vec![0.5f32, -0.5, 0.3, -0.3, 0.0, 0.0];
        let audio = ImportedAudio::new_stereo(samples, 48000, "/test/stereo.wav");

        let mono = audio.to_mono();

        assert_eq!(mono.len(), 3);
        assert!((mono[0] - 0.0).abs() < 1e-6); // (0.5 + -0.5) / 2
        assert!((mono[1] - 0.0).abs() < 1e-6); // (0.3 + -0.3) / 2
    }

    #[test]
    fn test_lanczos_kernel() {
        // Lanczos kernel at 0 should be 1
        assert!((SampleRateConverter::lanczos(0.0, 3.0) - 1.0).abs() < 1e-10);

        // Lanczos kernel at >=a should be 0
        assert!(SampleRateConverter::lanczos(3.0, 3.0).abs() < 1e-10);
        assert!(SampleRateConverter::lanczos(4.0, 3.0).abs() < 1e-10);
    }
}

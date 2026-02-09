//! Audio Export System
//!
//! Professional audio export with:
//! - WAV export (16/24/32-bit)
//! - Full mix bounce (all tracks + master)
//! - Region export (loop regions)
//! - Real-time or faster-than-real-time rendering
//! - Progress callback support

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use crate::freeze::OfflineRenderer;
use crate::playback::PlaybackEngine;
use crate::track_manager::TrackManager;

#[allow(unused_imports)]
use rf_file::{AudioData, AudioFormat, BitDepth, write_flac, write_mp3};

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Export format
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ExportFormat {
    /// 16-bit PCM WAV
    Wav16,
    /// 24-bit PCM WAV
    #[default]
    Wav24,
    /// 32-bit float WAV
    Wav32Float,
    /// FLAC lossless (16-bit)
    Flac16,
    /// FLAC lossless (24-bit)
    Flac24,
    /// MP3 320kbps
    Mp3_320,
    /// MP3 256kbps
    Mp3_256,
    /// MP3 192kbps
    Mp3_192,
    /// MP3 128kbps
    Mp3_128,
}

impl ExportFormat {
    /// Get file extension for this format
    pub fn file_extension(&self) -> &'static str {
        match self {
            ExportFormat::Wav16 | ExportFormat::Wav24 | ExportFormat::Wav32Float => "wav",
            ExportFormat::Flac16 | ExportFormat::Flac24 => "flac",
            ExportFormat::Mp3_320
            | ExportFormat::Mp3_256
            | ExportFormat::Mp3_192
            | ExportFormat::Mp3_128 => "mp3",
        }
    }

    /// Get format code for FFI
    pub fn to_code(&self) -> u32 {
        match self {
            ExportFormat::Wav16 => 0,
            ExportFormat::Wav24 => 1,
            ExportFormat::Wav32Float => 2,
            ExportFormat::Flac16 => 3,
            ExportFormat::Flac24 => 4,
            ExportFormat::Mp3_320 => 5,
            ExportFormat::Mp3_256 => 6,
            ExportFormat::Mp3_192 => 7,
            ExportFormat::Mp3_128 => 8,
        }
    }

    /// Create from FFI code
    pub fn from_code(code: u32) -> Self {
        match code {
            0 => ExportFormat::Wav16,
            1 => ExportFormat::Wav24,
            2 => ExportFormat::Wav32Float,
            3 => ExportFormat::Flac16,
            4 => ExportFormat::Flac24,
            5 => ExportFormat::Mp3_320,
            6 => ExportFormat::Mp3_256,
            7 => ExportFormat::Mp3_192,
            8 => ExportFormat::Mp3_128,
            _ => ExportFormat::Wav24, // Default
        }
    }
}

/// Export configuration
#[derive(Debug, Clone)]
pub struct ExportConfig {
    /// Output file path
    pub output_path: PathBuf,
    /// Export format
    pub format: ExportFormat,
    /// Sample rate (0 = use project rate)
    pub sample_rate: u32,
    /// Start time in seconds
    pub start_time: f64,
    /// End time in seconds
    pub end_time: f64,
    /// Include tail (reverb/delay decay)
    pub include_tail: bool,
    /// Tail length in seconds
    pub tail_seconds: f64,
    /// Normalize to -0.1 dBFS
    pub normalize: bool,
    /// Render block size
    pub block_size: usize,
}

impl Default for ExportConfig {
    fn default() -> Self {
        Self {
            output_path: PathBuf::from("export.wav"),
            format: ExportFormat::Wav24,
            sample_rate: 48000,
            start_time: 0.0,
            end_time: 60.0,
            include_tail: true,
            tail_seconds: 3.0,
            normalize: false,
            block_size: 512,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Audio export engine
pub struct ExportEngine {
    /// Playback engine for rendering
    playback_engine: Arc<PlaybackEngine>,
    /// Track manager (reserved for future per-track export)
    #[allow(dead_code)]
    track_manager: Arc<TrackManager>,
    /// Export progress (0-100)
    progress: AtomicU64,
    /// Is exporting
    is_exporting: AtomicBool,
}

impl ExportEngine {
    /// Create new export engine
    pub fn new(playback_engine: Arc<PlaybackEngine>, track_manager: Arc<TrackManager>) -> Self {
        Self {
            playback_engine,
            track_manager,
            progress: AtomicU64::new(0),
            is_exporting: AtomicBool::new(false),
        }
    }

    /// Get current export progress (0.0 - 100.0)
    pub fn progress(&self) -> f32 {
        f64::from_bits(self.progress.load(Ordering::Relaxed)) as f32
    }

    /// Is currently exporting
    pub fn is_exporting(&self) -> bool {
        self.is_exporting.load(Ordering::Relaxed)
    }

    /// Export audio to file
    pub fn export(&self, config: ExportConfig) -> Result<(), ExportError> {
        // Check if already exporting
        if self.is_exporting.swap(true, Ordering::Relaxed) {
            return Err(ExportError::AlreadyExporting);
        }

        // Ensure output directory exists
        if let Some(parent) = config.output_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| ExportError::IoError(e.to_string()))?;
        }

        // Calculate duration
        let render_duration = config.end_time - config.start_time;
        if render_duration <= 0.0 {
            self.is_exporting.store(false, Ordering::Relaxed);
            return Err(ExportError::InvalidTimeRange);
        }

        let total_duration = if config.include_tail {
            render_duration + config.tail_seconds
        } else {
            render_duration
        };

        // Use project sample rate if not specified
        let sample_rate = if config.sample_rate == 0 {
            48000 // Default project rate
        } else {
            config.sample_rate
        };

        let total_samples = (total_duration * sample_rate as f64) as usize;

        // Allocate output buffers
        let mut output_l = vec![0.0f64; total_samples];
        let mut output_r = vec![0.0f64; total_samples];

        // Reset progress
        self.progress.store(0.0_f64.to_bits(), Ordering::Relaxed);

        // Render in blocks
        let num_blocks = total_samples.div_ceil(config.block_size);

        for block_idx in 0..num_blocks {
            let block_start = block_idx * config.block_size;
            let block_end = (block_start + config.block_size).min(total_samples);

            // Calculate block time
            let block_start_sample =
                (config.start_time * sample_rate as f64) as usize + block_start;

            // Get block buffers
            let block_l = &mut output_l[block_start..block_end];
            let block_r = &mut output_r[block_start..block_end];

            // Render block through playback engine
            self.playback_engine
                .process_offline(block_start_sample, block_l, block_r);

            // Update progress
            let progress = (block_idx as f64 / num_blocks as f64) * 100.0;
            self.progress.store(progress.to_bits(), Ordering::Relaxed);
        }

        // Normalize if requested
        if config.normalize {
            self.normalize_audio(&mut output_l, &mut output_r);
        }

        // Write to file based on format
        self.write_output(
            &config.output_path,
            &output_l,
            &output_r,
            sample_rate,
            config.format,
        )?;

        // Mark complete
        self.progress.store(100.0_f64.to_bits(), Ordering::Relaxed);
        self.is_exporting.store(false, Ordering::Relaxed);

        Ok(())
    }

    /// Create AudioData from left/right buffers
    fn create_audio_data(&self, left: &[f64], right: &[f64], sample_rate: u32) -> AudioData {
        let mut audio_data = AudioData::new(2, left.len(), sample_rate);
        audio_data.channels[0].copy_from_slice(left);
        audio_data.channels[1].copy_from_slice(right);
        audio_data
    }

    /// Write output in specified format
    fn write_output(
        &self,
        path: &Path,
        left: &[f64],
        right: &[f64],
        sample_rate: u32,
        format: ExportFormat,
    ) -> Result<(), ExportError> {
        let path_buf = path.to_path_buf();
        match format {
            ExportFormat::Wav16 => {
                OfflineRenderer::write_wav_16bit(&path_buf, left, right, sample_rate)
                    .map_err(|e| ExportError::IoError(e.to_string()))?;
            }
            ExportFormat::Wav24 => {
                OfflineRenderer::write_wav_24bit(&path_buf, left, right, sample_rate)
                    .map_err(|e| ExportError::IoError(e.to_string()))?;
            }
            ExportFormat::Wav32Float => {
                OfflineRenderer::write_wav_f32(&path_buf, left, right, sample_rate)
                    .map_err(|e| ExportError::IoError(e.to_string()))?;
            }
            ExportFormat::Flac16 | ExportFormat::Flac24 => {
                let bit_depth = if format == ExportFormat::Flac16 {
                    BitDepth::Int16
                } else {
                    BitDepth::Int24
                };
                let audio_data = self.create_audio_data(left, right, sample_rate);
                write_flac(path, &audio_data, bit_depth)
                    .map_err(|e: rf_file::FileError| ExportError::IoError(e.to_string()))?;
            }
            ExportFormat::Mp3_320
            | ExportFormat::Mp3_256
            | ExportFormat::Mp3_192
            | ExportFormat::Mp3_128 => {
                let bitrate = match format {
                    ExportFormat::Mp3_320 => 320,
                    ExportFormat::Mp3_256 => 256,
                    ExportFormat::Mp3_192 => 192,
                    ExportFormat::Mp3_128 => 128,
                    _ => 320,
                };
                let audio_data = self.create_audio_data(left, right, sample_rate);
                write_mp3(path, &audio_data, bitrate)
                    .map_err(|e: rf_file::FileError| ExportError::IoError(e.to_string()))?;
            }
        }
        Ok(())
    }

    /// Normalize audio to -0.1 dBFS
    fn normalize_audio(&self, left: &mut [f64], right: &mut [f64]) {
        // Find peak
        let mut peak = 0.0f64;
        for &sample in left.iter().chain(right.iter()) {
            peak = peak.max(sample.abs());
        }

        if peak > 0.0 {
            // Target: -0.1 dBFS = 0.989 linear
            let target = 0.989;
            let gain = target / peak;

            // Apply gain
            for sample in left.iter_mut().chain(right.iter_mut()) {
                *sample *= gain;
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEMS EXPORT
// ═══════════════════════════════════════════════════════════════════════════

/// Stems export configuration
#[derive(Debug, Clone)]
pub struct StemsConfig {
    /// Output directory for stems
    pub output_dir: PathBuf,
    /// Export format
    pub format: ExportFormat,
    /// Sample rate (0 = use project rate)
    pub sample_rate: u32,
    /// Start time in seconds
    pub start_time: f64,
    /// End time in seconds
    pub end_time: f64,
    /// Include tail (reverb/delay decay)
    pub include_tail: bool,
    /// Tail length in seconds
    pub tail_seconds: f64,
    /// Normalize each stem to -0.1 dBFS
    pub normalize: bool,
    /// Render block size
    pub block_size: usize,
    /// Export buses as stems
    pub include_buses: bool,
    /// Prefix for stem filenames
    pub prefix: String,
}

impl Default for StemsConfig {
    fn default() -> Self {
        Self {
            output_dir: PathBuf::from("stems"),
            format: ExportFormat::Wav24,
            sample_rate: 48000,
            start_time: 0.0,
            end_time: 60.0,
            include_tail: true,
            tail_seconds: 3.0,
            normalize: false,
            block_size: 512,
            include_buses: true,
            prefix: String::new(),
        }
    }
}

/// Stem info for tracking export progress
#[derive(Debug, Clone)]
pub struct StemInfo {
    /// Track ID
    pub track_id: u64,
    /// Track name
    pub track_name: String,
    /// Output file path
    pub output_path: PathBuf,
    /// Export status (0=pending, 1=rendering, 2=complete, 3=error)
    pub status: u8,
}

impl ExportEngine {
    /// Export stems (individual tracks)
    pub fn export_stems(&self, config: StemsConfig) -> Result<Vec<StemInfo>, ExportError> {
        // Check if already exporting
        if self.is_exporting.swap(true, Ordering::Relaxed) {
            return Err(ExportError::AlreadyExporting);
        }

        // Create output directory
        std::fs::create_dir_all(&config.output_dir)
            .map_err(|e| ExportError::IoError(e.to_string()))?;

        // Get all tracks from track manager
        let tracks = self.track_manager.get_all_tracks();
        let track_count = tracks.len();

        if track_count == 0 {
            self.is_exporting.store(false, Ordering::Relaxed);
            return Err(ExportError::RenderError("No tracks to export".to_string()));
        }

        let mut stems: Vec<StemInfo> = Vec::with_capacity(track_count);

        // Calculate duration
        let render_duration = config.end_time - config.start_time;
        if render_duration <= 0.0 {
            self.is_exporting.store(false, Ordering::Relaxed);
            return Err(ExportError::InvalidTimeRange);
        }

        let total_duration = if config.include_tail {
            render_duration + config.tail_seconds
        } else {
            render_duration
        };

        let sample_rate = if config.sample_rate == 0 {
            48000
        } else {
            config.sample_rate
        };
        let total_samples = (total_duration * sample_rate as f64) as usize;

        // Export each track
        let extension = config.format.file_extension();
        for (idx, track) in tracks.iter().enumerate() {
            // Generate output filename
            let filename = if config.prefix.is_empty() {
                format!(
                    "{}_{}.{}",
                    track.id.0,
                    sanitize_filename(&track.name),
                    extension
                )
            } else {
                format!(
                    "{}_{}_{}.{}",
                    config.prefix,
                    track.id.0,
                    sanitize_filename(&track.name),
                    extension
                )
            };
            let output_path = config.output_dir.join(&filename);

            stems.push(StemInfo {
                track_id: track.id.0,
                track_name: track.name.clone(),
                output_path: output_path.clone(),
                status: 1, // Rendering
            });

            // Allocate output buffers
            let mut output_l = vec![0.0f64; total_samples];
            let mut output_r = vec![0.0f64; total_samples];

            // Render track in blocks
            let num_blocks = total_samples.div_ceil(config.block_size);

            for block_idx in 0..num_blocks {
                let block_start = block_idx * config.block_size;
                let block_end = (block_start + config.block_size).min(total_samples);

                let block_start_sample =
                    (config.start_time * sample_rate as f64) as usize + block_start;

                let block_l = &mut output_l[block_start..block_end];
                let block_r = &mut output_r[block_start..block_end];

                // Render single track
                self.playback_engine.process_track_offline(
                    track.id.0,
                    block_start_sample,
                    block_l,
                    block_r,
                );
            }

            // Normalize if requested
            if config.normalize {
                self.normalize_audio(&mut output_l, &mut output_r);
            }

            // Write to file
            let write_result = self.write_output(
                &output_path,
                &output_l,
                &output_r,
                sample_rate,
                config.format,
            );

            // SAFETY: stems.push() was called above, so last_mut() is always Some
            let current_stem = stems.last_mut().expect("stem was just pushed above");

            if let Err(e) = write_result {
                current_stem.status = 3; // Error
                log::error!("Failed to export stem {}: {}", track.name, e);
            } else {
                current_stem.status = 2; // Complete
            }

            // Update progress
            let progress = ((idx + 1) as f64 / track_count as f64) * 100.0;
            self.progress.store(progress.to_bits(), Ordering::Relaxed);
        }

        self.is_exporting.store(false, Ordering::Relaxed);
        Ok(stems)
    }
}

/// Sanitize filename by removing invalid characters
fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect()
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT ERROR
// ═══════════════════════════════════════════════════════════════════════════

/// Export errors
#[derive(Debug, thiserror::Error)]
pub enum ExportError {
    #[error("Export already in progress")]
    AlreadyExporting,

    #[error("Invalid time range")]
    InvalidTimeRange,

    #[error("IO error: {0}")]
    IoError(String),

    #[error("Render error: {0}")]
    RenderError(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_export_config_default() {
        let config = ExportConfig::default();
        assert_eq!(config.format, ExportFormat::Wav24);
        assert_eq!(config.sample_rate, 48000);
        assert!(config.include_tail);
    }

    #[test]
    fn test_normalize_audio() {
        let track_manager = Arc::new(TrackManager::new());
        let playback_engine = Arc::new(PlaybackEngine::new(track_manager.clone(), 48000));
        let export_engine = ExportEngine::new(playback_engine, track_manager);

        let mut left = vec![0.5, -0.8, 0.3];
        let mut right = vec![0.6, -0.7, 0.4];

        export_engine.normalize_audio(&mut left, &mut right);

        // Peak should be at -0.1 dBFS (0.989)
        let peak = left
            .iter()
            .chain(right.iter())
            .map(|s| s.abs())
            .fold(0.0f64, f64::max);
        assert!((peak - 0.989).abs() < 0.01);
    }
}

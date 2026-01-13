//! Audio Export System
//!
//! Professional audio export with:
//! - WAV export (16/24/32-bit)
//! - Full mix bounce (all tracks + master)
//! - Region export (loop regions)
//! - Real-time or faster-than-real-time rendering
//! - Progress callback support

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use crate::freeze::OfflineRenderer;
use crate::playback::PlaybackEngine;
use crate::track_manager::TrackManager;

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Export format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(Default)]
pub enum ExportFormat {
    /// 16-bit PCM WAV
    Wav16,
    /// 24-bit PCM WAV
    #[default]
    Wav24,
    /// 32-bit float WAV
    Wav32Float,
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
    pub fn new(
        playback_engine: Arc<PlaybackEngine>,
        track_manager: Arc<TrackManager>,
    ) -> Self {
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
            std::fs::create_dir_all(parent)
                .map_err(|e| ExportError::IoError(e.to_string()))?;
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
            let block_start_sample = (config.start_time * sample_rate as f64) as usize + block_start;

            // Get block buffers
            let block_l = &mut output_l[block_start..block_end];
            let block_r = &mut output_r[block_start..block_end];

            // Render block through playback engine
            self.playback_engine.process_offline(block_start_sample, block_l, block_r);

            // Update progress
            let progress = (block_idx as f64 / num_blocks as f64) * 100.0;
            self.progress.store(progress.to_bits(), Ordering::Relaxed);
        }

        // Normalize if requested
        if config.normalize {
            self.normalize_audio(&mut output_l, &mut output_r);
        }

        // Write to file based on format
        match config.format {
            ExportFormat::Wav16 => {
                OfflineRenderer::write_wav_16bit(
                    &config.output_path,
                    &output_l,
                    &output_r,
                    sample_rate,
                )
                .map_err(|e| ExportError::IoError(e.to_string()))?;
            }
            ExportFormat::Wav24 => {
                OfflineRenderer::write_wav_24bit(
                    &config.output_path,
                    &output_l,
                    &output_r,
                    sample_rate,
                )
                .map_err(|e| ExportError::IoError(e.to_string()))?;
            }
            ExportFormat::Wav32Float => {
                OfflineRenderer::write_wav_f32(
                    &config.output_path,
                    &output_l,
                    &output_r,
                    sample_rate,
                )
                .map_err(|e| ExportError::IoError(e.to_string()))?;
            }
        }

        // Mark complete
        self.progress.store(100.0_f64.to_bits(), Ordering::Relaxed);
        self.is_exporting.store(false, Ordering::Relaxed);

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
        let peak = left.iter().chain(right.iter()).map(|s| s.abs()).fold(0.0f64, f64::max);
        assert!((peak - 0.989).abs() < 0.01);
    }
}

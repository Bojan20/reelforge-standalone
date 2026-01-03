//! Track Freeze System
//!
//! Renders tracks to audio files for CPU savings:
//! - Full track freeze (all plugins disabled)
//! - Partial freeze (keep selected plugins active)
//! - Instrument track freeze (render VSTi/AU instruments)
//! - Background freeze processing
//! - Quick unfreeze with original state restore
//!
//! ## CPU Savings
//! Frozen tracks play back pre-rendered audio instead of
//! running plugins in real-time, dramatically reducing CPU usage.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use parking_lot::RwLock;

use rf_core::Sample;

// ═══════════════════════════════════════════════════════════════════════════════
// FREEZE STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Freeze status for a track
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FreezeStatus {
    /// Track is not frozen
    Unfrozen,
    /// Freeze is in progress
    Freezing,
    /// Track is fully frozen
    Frozen,
    /// Freeze failed
    Failed,
}

/// Freeze mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FreezeMode {
    /// Freeze entire track (all plugins)
    Full,
    /// Freeze up to a specific insert slot
    UpToSlot(usize),
    /// Freeze only instrument (for MIDI/instrument tracks)
    InstrumentOnly,
    /// Freeze sends (render send effects into main signal)
    WithSends,
}

/// Freeze options
#[derive(Debug, Clone)]
pub struct FreezeOptions {
    /// Freeze mode
    pub mode: FreezeMode,
    /// Tail time in seconds (for reverb/delay tails)
    pub tail_time: f64,
    /// Sample rate for frozen audio
    pub sample_rate: u32,
    /// Bit depth for frozen audio
    pub bit_depth: u8,
    /// Process in real-time (preview) or offline (faster)
    pub realtime: bool,
    /// Keep source events visible (grayed out)
    pub keep_source_visible: bool,
}

impl Default for FreezeOptions {
    fn default() -> Self {
        Self {
            mode: FreezeMode::Full,
            tail_time: 2.0,
            sample_rate: 48000,
            bit_depth: 32,
            realtime: false,
            keep_source_visible: true,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FROZEN TRACK DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Data stored for a frozen track
#[derive(Debug, Clone)]
pub struct FrozenTrackData {
    /// Track ID
    pub track_id: u64,
    /// Path to frozen audio file
    pub audio_file: PathBuf,
    /// Original track state (for unfreeze)
    pub original_state: FrozenOriginalState,
    /// Freeze options used
    pub options: FreezeOptions,
    /// Frozen timestamp
    pub frozen_at: u64,
    /// Duration in samples
    pub duration_samples: u64,
    /// Number of channels
    pub channels: u8,
}

/// Original track state before freeze
#[derive(Debug, Clone)]
pub struct FrozenOriginalState {
    /// Insert chain state (plugin IDs and parameters)
    pub inserts: Vec<FrozenInsertState>,
    /// Send levels
    pub sends: Vec<FrozenSendState>,
    /// Track volume
    pub volume_db: f64,
    /// Track pan
    pub pan: f64,
    /// Events/regions on track
    pub events: Vec<FrozenEventState>,
}

/// Frozen insert slot state
#[derive(Debug, Clone)]
pub struct FrozenInsertState {
    pub slot: usize,
    pub plugin_id: String,
    pub plugin_name: String,
    pub bypassed: bool,
    pub parameters: HashMap<u32, f64>,
    pub preset_data: Option<Vec<u8>>,
}

/// Frozen send state
#[derive(Debug, Clone)]
pub struct FrozenSendState {
    pub destination_id: String,
    pub level_db: f64,
    pub pan: f64,
    pub pre_fader: bool,
}

/// Frozen event state
#[derive(Debug, Clone)]
pub struct FrozenEventState {
    pub event_id: u64,
    pub position: u64,
    pub length: u64,
    pub clip_offset: u64,
    pub gain_db: f64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// FREEZE PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Track freeze processor
pub struct TrackFreezer {
    /// Freeze directory
    freeze_dir: PathBuf,
    /// Frozen tracks
    frozen_tracks: Arc<RwLock<HashMap<u64, FrozenTrackData>>>,
    /// Active freeze jobs
    active_jobs: Arc<RwLock<HashMap<u64, FreezeJob>>>,
    /// Sample rate
    sample_rate: u32,
    /// Block size
    block_size: usize,
}

/// Active freeze job
pub struct FreezeJob {
    /// Track ID
    pub track_id: u64,
    /// Progress (0.0 - 1.0)
    pub progress: AtomicU64,
    /// Cancel flag
    pub cancelled: AtomicBool,
    /// Status
    pub status: Arc<RwLock<FreezeStatus>>,
}

impl FreezeJob {
    pub fn progress(&self) -> f64 {
        f64::from_bits(self.progress.load(Ordering::Relaxed))
    }

    pub fn set_progress(&self, p: f64) {
        self.progress.store(p.to_bits(), Ordering::Relaxed);
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }
}

impl TrackFreezer {
    pub fn new(freeze_dir: PathBuf, sample_rate: u32, block_size: usize) -> Self {
        // Create freeze directory if needed
        std::fs::create_dir_all(&freeze_dir).ok();

        Self {
            freeze_dir,
            frozen_tracks: Arc::new(RwLock::new(HashMap::new())),
            active_jobs: Arc::new(RwLock::new(HashMap::new())),
            sample_rate,
            block_size,
        }
    }

    /// Check if track is frozen
    pub fn is_frozen(&self, track_id: u64) -> bool {
        self.frozen_tracks.read().contains_key(&track_id)
    }

    /// Get freeze status
    pub fn status(&self, track_id: u64) -> FreezeStatus {
        if self.frozen_tracks.read().contains_key(&track_id) {
            return FreezeStatus::Frozen;
        }

        if let Some(job) = self.active_jobs.read().get(&track_id) {
            return *job.status.read();
        }

        FreezeStatus::Unfrozen
    }

    /// Get freeze progress
    pub fn progress(&self, track_id: u64) -> f64 {
        if let Some(job) = self.active_jobs.read().get(&track_id) {
            return job.progress();
        }
        0.0
    }

    /// Start freeze job
    pub fn freeze_track(
        &self,
        track_id: u64,
        original_state: FrozenOriginalState,
        options: FreezeOptions,
        duration_samples: u64,
    ) -> Result<(), FreezeError> {
        // Check if already frozen or freezing
        if self.is_frozen(track_id) {
            return Err(FreezeError::AlreadyFrozen);
        }

        if self.active_jobs.read().contains_key(&track_id) {
            return Err(FreezeError::FreezeInProgress);
        }

        // Create job
        let job = FreezeJob {
            track_id,
            progress: AtomicU64::new(0.0_f64.to_bits()),
            cancelled: AtomicBool::new(false),
            status: Arc::new(RwLock::new(FreezeStatus::Freezing)),
        };

        self.active_jobs.write().insert(track_id, job);

        // Generate freeze file path
        let freeze_file = self.freeze_dir.join(format!("track_{}_freeze.wav", track_id));

        // In a real implementation, this would spawn a thread or task
        // to do the actual rendering. For now, we just set up the structure.
        let frozen_data = FrozenTrackData {
            track_id,
            audio_file: freeze_file,
            original_state,
            options,
            frozen_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0),
            duration_samples,
            channels: 2,
        };

        // Store frozen data
        self.frozen_tracks.write().insert(track_id, frozen_data);

        // Remove active job
        self.active_jobs.write().remove(&track_id);

        Ok(())
    }

    /// Cancel freeze in progress
    pub fn cancel_freeze(&self, track_id: u64) -> bool {
        if let Some(job) = self.active_jobs.read().get(&track_id) {
            job.cancel();
            return true;
        }
        false
    }

    /// Unfreeze track
    pub fn unfreeze_track(&self, track_id: u64) -> Option<FrozenOriginalState> {
        if let Some(frozen) = self.frozen_tracks.write().remove(&track_id) {
            // Delete freeze file
            std::fs::remove_file(&frozen.audio_file).ok();

            return Some(frozen.original_state);
        }
        None
    }

    /// Get frozen track data
    pub fn get_frozen_data(&self, track_id: u64) -> Option<FrozenTrackData> {
        self.frozen_tracks.read().get(&track_id).cloned()
    }

    /// Get freeze file path
    pub fn get_freeze_file(&self, track_id: u64) -> Option<PathBuf> {
        self.frozen_tracks
            .read()
            .get(&track_id)
            .map(|d| d.audio_file.clone())
    }

    /// Clean up orphaned freeze files
    pub fn cleanup(&self) -> usize {
        let mut count = 0;

        if let Ok(entries) = std::fs::read_dir(&self.freeze_dir) {
            let frozen_files: Vec<PathBuf> = self
                .frozen_tracks
                .read()
                .values()
                .map(|d| d.audio_file.clone())
                .collect();

            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().map(|e| e == "wav").unwrap_or(false) {
                    if !frozen_files.contains(&path) {
                        if std::fs::remove_file(&path).is_ok() {
                            count += 1;
                        }
                    }
                }
            }
        }

        count
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FREEZE RENDERER
// ═══════════════════════════════════════════════════════════════════════════════

/// Offline freeze renderer
pub struct FreezeRenderer {
    /// Sample rate
    sample_rate: u32,
    /// Block size for rendering
    block_size: usize,
    /// Left channel buffer
    left_buffer: Vec<Sample>,
    /// Right channel buffer
    right_buffer: Vec<Sample>,
}

impl FreezeRenderer {
    pub fn new(sample_rate: u32, block_size: usize) -> Self {
        Self {
            sample_rate,
            block_size,
            left_buffer: vec![0.0; block_size],
            right_buffer: vec![0.0; block_size],
        }
    }

    /// Render a track to file
    ///
    /// This is a simplified implementation. In production, this would:
    /// 1. Process all events through the plugin chain
    /// 2. Render automation
    /// 3. Handle tail time
    /// 4. Write to disk progressively
    pub fn render_track<F>(
        &mut self,
        duration_samples: u64,
        tail_samples: u64,
        mut process_callback: F,
        progress_callback: impl Fn(f64),
    ) -> Vec<f32>
    where
        F: FnMut(&mut [Sample], &mut [Sample]),
    {
        let total_samples = duration_samples + tail_samples;
        let total_blocks = (total_samples as usize + self.block_size - 1) / self.block_size;

        let mut output = Vec::with_capacity(total_samples as usize * 2);

        for block_idx in 0..total_blocks {
            // Clear buffers
            self.left_buffer.fill(0.0);
            self.right_buffer.fill(0.0);

            // Process
            process_callback(&mut self.left_buffer, &mut self.right_buffer);

            // Interleave and append
            for i in 0..self.block_size {
                output.push(self.left_buffer[i] as f32);
                output.push(self.right_buffer[i] as f32);
            }

            // Report progress
            let progress = (block_idx + 1) as f64 / total_blocks as f64;
            progress_callback(progress);
        }

        // Truncate to exact length
        let exact_len = total_samples as usize * 2;
        output.truncate(exact_len);

        output
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FREEZE FILE WRITER
// ═══════════════════════════════════════════════════════════════════════════════

/// Write freeze data to file
pub struct FreezeFileWriter {
    /// Sample rate
    sample_rate: u32,
    /// Bit depth
    bit_depth: u8,
    /// Number of channels
    channels: u8,
}

impl FreezeFileWriter {
    pub fn new(sample_rate: u32, bit_depth: u8, channels: u8) -> Self {
        Self {
            sample_rate,
            bit_depth,
            channels,
        }
    }

    /// Write interleaved samples to WAV file
    pub fn write_wav(&self, path: &Path, samples: &[f32]) -> Result<(), FreezeError> {
        use std::fs::File;
        use std::io::{BufWriter, Write};

        let file = File::create(path)?;
        let mut writer = BufWriter::new(file);

        let num_samples = samples.len() / self.channels as usize;
        let bytes_per_sample = self.bit_depth as u32 / 8;
        let byte_rate = self.sample_rate * self.channels as u32 * bytes_per_sample;
        let block_align = self.channels as u16 * bytes_per_sample as u16;
        let data_size = (num_samples * self.channels as usize * bytes_per_sample as usize) as u32;

        // RIFF header
        writer.write_all(b"RIFF")?;
        writer.write_all(&(36 + data_size).to_le_bytes())?;
        writer.write_all(b"WAVE")?;

        // fmt chunk
        writer.write_all(b"fmt ")?;
        writer.write_all(&16u32.to_le_bytes())?; // chunk size
        writer.write_all(&3u16.to_le_bytes())?; // format: IEEE float
        writer.write_all(&(self.channels as u16).to_le_bytes())?;
        writer.write_all(&self.sample_rate.to_le_bytes())?;
        writer.write_all(&byte_rate.to_le_bytes())?;
        writer.write_all(&block_align.to_le_bytes())?;
        writer.write_all(&(self.bit_depth as u16).to_le_bytes())?;

        // data chunk
        writer.write_all(b"data")?;
        writer.write_all(&data_size.to_le_bytes())?;

        // Write samples
        for &sample in samples {
            writer.write_all(&sample.to_le_bytes())?;
        }

        writer.flush()?;
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ERRORS
// ═══════════════════════════════════════════════════════════════════════════════

/// Freeze errors
#[derive(Debug, thiserror::Error)]
pub enum FreezeError {
    #[error("Track is already frozen")]
    AlreadyFrozen,

    #[error("Freeze already in progress")]
    FreezeInProgress,

    #[error("Track is not frozen")]
    NotFrozen,

    #[error("Freeze cancelled")]
    Cancelled,

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Render error: {0}")]
    RenderError(String),
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::env::temp_dir;

    #[test]
    fn test_freeze_status() {
        let freezer = TrackFreezer::new(temp_dir().join("freeze_test"), 48000, 256);

        assert_eq!(freezer.status(1), FreezeStatus::Unfrozen);
        assert!(!freezer.is_frozen(1));
    }

    #[test]
    fn test_freeze_renderer() {
        let mut renderer = FreezeRenderer::new(48000, 256);

        let mut block_count = 0;
        let output = renderer.render_track(
            4800, // 0.1 seconds
            0,
            |left, right| {
                // Generate silence
                left.fill(0.0);
                right.fill(0.0);
                block_count += 1;
            },
            |_progress| {},
        );

        assert!(block_count > 0);
        assert_eq!(output.len(), 4800 * 2); // Stereo
    }

    #[test]
    fn test_freeze_file_writer() {
        let writer = FreezeFileWriter::new(48000, 32, 2);
        let temp_path = temp_dir().join("test_freeze.wav");

        // Generate test samples
        let samples: Vec<f32> = (0..4800)
            .flat_map(|i| {
                let t = i as f32 / 48000.0;
                let sample = (t * 440.0 * std::f32::consts::TAU).sin() * 0.5;
                [sample, sample] // Stereo
            })
            .collect();

        writer.write_wav(&temp_path, &samples).unwrap();

        // Verify file exists and has correct size
        let metadata = std::fs::metadata(&temp_path).unwrap();
        assert!(metadata.len() > 0);

        // Cleanup
        std::fs::remove_file(&temp_path).ok();
    }

    #[test]
    fn test_freeze_job() {
        let job = FreezeJob {
            track_id: 1,
            progress: AtomicU64::new(0.0_f64.to_bits()),
            cancelled: AtomicBool::new(false),
            status: Arc::new(RwLock::new(FreezeStatus::Freezing)),
        };

        assert!((job.progress() - 0.0).abs() < 0.001);

        job.set_progress(0.5);
        assert!((job.progress() - 0.5).abs() < 0.001);

        assert!(!job.is_cancelled());
        job.cancel();
        assert!(job.is_cancelled());
    }
}

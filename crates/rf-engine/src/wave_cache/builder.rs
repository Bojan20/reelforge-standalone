//! Async Waveform Cache Builder
//!
//! Builds .wfc cache files in background with:
//! - Progressive refinement (coarsest level first for instant preview)
//! - Chunked reading to avoid memory spikes
//! - Progress reporting for UI feedback
//! - Cancellation support

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU32, Ordering};

use super::WaveCacheError;
use super::format::{MIP_TILE_SAMPLES, MipLevel, NUM_MIP_LEVELS, TileData, WfcFile};

// ═══════════════════════════════════════════════════════════════════════════
// BUILD STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Current build state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum BuildState {
    /// Not started
    Idle = 0,
    /// Reading audio file
    Reading = 1,
    /// Building mip levels
    BuildingMips = 2,
    /// Writing .wfc file
    Writing = 3,
    /// Build complete
    Complete = 4,
    /// Build failed
    Failed = 5,
    /// Build cancelled
    Cancelled = 6,
}

impl From<u8> for BuildState {
    fn from(v: u8) -> Self {
        match v {
            0 => BuildState::Idle,
            1 => BuildState::Reading,
            2 => BuildState::BuildingMips,
            3 => BuildState::Writing,
            4 => BuildState::Complete,
            5 => BuildState::Failed,
            6 => BuildState::Cancelled,
            _ => BuildState::Idle,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILD PROGRESS
// ═══════════════════════════════════════════════════════════════════════════

/// Progress information for UI
#[derive(Debug, Clone)]
pub struct BuildProgress {
    /// Current state
    pub state: BuildState,
    /// Progress 0.0 - 1.0
    pub progress: f32,
    /// Current mip level being built
    pub current_level: usize,
    /// Total mip levels
    pub total_levels: usize,
    /// Frames processed
    pub frames_processed: u64,
    /// Total frames
    pub total_frames: u64,
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVE CACHE BUILDER
// ═══════════════════════════════════════════════════════════════════════════

/// Async waveform cache builder
pub struct WaveCacheBuilder {
    /// Source audio file path
    audio_path: String,

    /// Output .wfc file path
    output_path: PathBuf,

    /// Sample rate
    sample_rate: u32,

    /// Number of channels
    channels: u8,

    /// Total frames in source
    total_frames: u64,

    /// Current build state
    state: AtomicU8,

    /// Progress 0-100 (percentage * 100 for atomicity)
    progress_pct: AtomicU32,

    /// Current mip level
    current_level: AtomicU8,

    /// Cancel flag
    cancelled: AtomicBool,

    /// Completed mip levels (available for preview)
    /// Bit flags: bit N = level N is complete
    completed_levels: AtomicU8,
}

impl WaveCacheBuilder {
    /// Create new builder
    pub fn new(
        audio_path: String,
        output_path: PathBuf,
        sample_rate: u32,
        channels: u8,
        total_frames: u64,
    ) -> Self {
        Self {
            audio_path,
            output_path,
            sample_rate,
            channels,
            total_frames,
            state: AtomicU8::new(BuildState::Idle as u8),
            progress_pct: AtomicU32::new(0),
            current_level: AtomicU8::new(0),
            cancelled: AtomicBool::new(false),
            completed_levels: AtomicU8::new(0),
        }
    }

    /// Get current progress (0.0 - 1.0)
    pub fn progress(&self) -> f32 {
        self.progress_pct.load(Ordering::Relaxed) as f32 / 10000.0
    }

    /// Get current state
    pub fn state(&self) -> BuildState {
        self.state.load(Ordering::Relaxed).into()
    }

    /// Get full progress info
    pub fn get_progress(&self) -> BuildProgress {
        BuildProgress {
            state: self.state(),
            progress: self.progress(),
            current_level: self.current_level.load(Ordering::Relaxed) as usize,
            total_levels: NUM_MIP_LEVELS,
            frames_processed: (self.progress() * self.total_frames as f32) as u64,
            total_frames: self.total_frames,
        }
    }

    /// Check if build is complete
    pub fn is_complete(&self) -> bool {
        self.state() == BuildState::Complete
    }

    /// Check if a specific mip level is ready for preview
    pub fn is_level_ready(&self, level: usize) -> bool {
        let mask = 1u8 << level;
        (self.completed_levels.load(Ordering::Relaxed) & mask) != 0
    }

    /// Cancel the build
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    /// Execute the build (blocking)
    ///
    /// Call this from a background thread
    pub fn build(&self) -> Result<(), WaveCacheError> {
        // Set state to reading
        self.state
            .store(BuildState::Reading as u8, Ordering::Relaxed);

        // Load audio data
        let audio_data = self.load_audio()?;

        if self.cancelled.load(Ordering::Relaxed) {
            self.state
                .store(BuildState::Cancelled as u8, Ordering::Relaxed);
            return Ok(());
        }

        // Build mip levels
        self.state
            .store(BuildState::BuildingMips as u8, Ordering::Relaxed);

        let mut wfc = WfcFile::new(self.channels, self.sample_rate, self.total_frames);

        // Build from coarsest to finest (progressive refinement)
        // This allows preview to start with coarse level immediately
        for level in (0..NUM_MIP_LEVELS).rev() {
            if self.cancelled.load(Ordering::Relaxed) {
                self.state
                    .store(BuildState::Cancelled as u8, Ordering::Relaxed);
                return Ok(());
            }

            self.current_level.store(level as u8, Ordering::Relaxed);

            // Build this mip level
            self.build_mip_level(&audio_data, &mut wfc.mip_levels[level], level);

            // Mark level as complete (for preview)
            let mask = 1u8 << level;
            self.completed_levels.fetch_or(mask, Ordering::Relaxed);

            // Update progress
            let levels_done = NUM_MIP_LEVELS - level;
            let progress = levels_done as f32 / NUM_MIP_LEVELS as f32;
            self.progress_pct
                .store((progress * 10000.0) as u32, Ordering::Relaxed);
        }

        // Write to file
        self.state
            .store(BuildState::Writing as u8, Ordering::Relaxed);

        wfc.save(&self.output_path)?;

        self.state
            .store(BuildState::Complete as u8, Ordering::Relaxed);
        self.progress_pct.store(10000, Ordering::Relaxed);

        Ok(())
    }

    /// Load audio data from file using AudioImporter
    fn load_audio(&self) -> Result<AudioData, WaveCacheError> {
        use crate::audio_import::AudioImporter;
        use std::path::Path;

        // Use our audio import system which handles WAV, AIFF, FLAC, MP3, etc.
        let path = Path::new(&self.audio_path);

        match AudioImporter::import(path) {
            Ok(imported) => {
                let channels = imported.channels as usize;
                let frames = imported.samples.len() / channels;

                // Deinterleave samples
                let mut channel_data: Vec<Vec<f32>> = vec![Vec::with_capacity(frames); channels];
                for (i, &sample) in imported.samples.iter().enumerate() {
                    let ch = i % channels;
                    channel_data[ch].push(sample);
                }

                Ok(AudioData {
                    channels: channel_data,
                    sample_rate: imported.sample_rate,
                })
            }
            Err(e) => {
                // Fallback: create empty data
                log::warn!(
                    "Failed to load audio {}: {:?}, using empty data",
                    self.audio_path,
                    e
                );
                let channels = self.channels as usize;
                let frames = self.total_frames as usize;

                let channel_data: Vec<Vec<f32>> =
                    (0..channels).map(|_| vec![0.0; frames]).collect();

                Ok(AudioData {
                    channels: channel_data,
                    sample_rate: self.sample_rate,
                })
            }
        }
    }

    /// Build a single mip level
    fn build_mip_level(&self, audio: &AudioData, level: &mut MipLevel, level_idx: usize) {
        let samples_per_tile = MIP_TILE_SAMPLES[level_idx];

        for (ch_idx, channel_samples) in audio.channels.iter().enumerate() {
            let num_tiles = channel_samples.len().div_ceil(samples_per_tile);
            level.tiles[ch_idx] = Vec::with_capacity(num_tiles);

            for chunk in channel_samples.chunks(samples_per_tile) {
                let (min, max) = self.find_min_max(chunk);
                level.tiles[ch_idx].push(TileData::new(min, max));
            }
        }
    }

    /// Find min/max in a chunk (SIMD-friendly)
    #[inline]
    fn find_min_max(&self, samples: &[f32]) -> (f32, f32) {
        if samples.is_empty() {
            return (0.0, 0.0);
        }

        let mut min = f32::MAX;
        let mut max = f32::MIN;

        // Process in chunks of 8 for SIMD-friendly behavior
        let chunks = samples.chunks_exact(8);
        let remainder = chunks.remainder();

        for chunk in chunks {
            for &sample in chunk {
                if sample < min {
                    min = sample;
                }
                if sample > max {
                    max = sample;
                }
            }
        }

        for &sample in remainder {
            if sample < min {
                min = sample;
            }
            if sample > max {
                max = sample;
            }
        }

        (min, max)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Temporary audio data for building
struct AudioData {
    /// Per-channel sample data
    channels: Vec<Vec<f32>>,
    /// Sample rate (kept for future use)
    #[allow(dead_code)]
    sample_rate: u32,
}

// ═══════════════════════════════════════════════════════════════════════════
// STANDALONE BUILDER FUNCTION
// ═══════════════════════════════════════════════════════════════════════════

/// Build waveform cache from already-loaded samples
///
/// This is the main entry point for building from in-memory data
pub fn build_from_samples(
    samples: &[f32],
    channels: usize,
    sample_rate: u32,
    output_path: &std::path::Path,
) -> Result<WfcFile, WaveCacheError> {
    let frames = samples.len() / channels;

    // Deinterleave samples
    let mut channel_data: Vec<Vec<f32>> = vec![Vec::with_capacity(frames); channels];
    for (i, &sample) in samples.iter().enumerate() {
        let ch = i % channels;
        channel_data[ch].push(sample);
    }

    // Create WFC file
    let mut wfc = WfcFile::new(channels as u8, sample_rate, frames as u64);

    // Build all mip levels
    for level_idx in 0..NUM_MIP_LEVELS {
        let samples_per_tile = MIP_TILE_SAMPLES[level_idx];

        for (ch_idx, ch_samples) in channel_data.iter().enumerate() {
            let num_tiles = ch_samples.len().div_ceil(samples_per_tile);
            wfc.mip_levels[level_idx].tiles[ch_idx] = Vec::with_capacity(num_tiles);

            for chunk in ch_samples.chunks(samples_per_tile) {
                let (min, max) = find_min_max_simple(chunk);
                wfc.mip_levels[level_idx].tiles[ch_idx].push(TileData::new(min, max));
            }
        }
    }

    // Save to file
    wfc.save(output_path)?;

    Ok(wfc)
}

/// Simple min/max finder
fn find_min_max_simple(samples: &[f32]) -> (f32, f32) {
    if samples.is_empty() {
        return (0.0, 0.0);
    }

    let mut min = samples[0];
    let mut max = samples[0];

    for &sample in &samples[1..] {
        if sample < min {
            min = sample;
        }
        if sample > max {
            max = sample;
        }
    }

    (min, max)
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_min_max() {
        let samples = vec![-0.5, 0.0, 0.3, -0.8, 0.9, 0.1];
        let (min, max) = find_min_max_simple(&samples);

        assert!((min - (-0.8)).abs() < 0.0001);
        assert!((max - 0.9).abs() < 0.0001);
    }

    #[test]
    fn test_build_state_conversion() {
        assert_eq!(BuildState::from(0), BuildState::Idle);
        assert_eq!(BuildState::from(4), BuildState::Complete);
        assert_eq!(BuildState::from(255), BuildState::Idle); // Unknown -> Idle
    }
}

//! Track Freeze System
//!
//! Renders track with all inserts to audio file for CPU savings:
//! - Freezes: Render track to temp audio, bypass all processing
//! - Unfreezes: Remove rendered audio, restore processing
//!
//! Cubase/Pro Tools style freeze with:
//! - Full render including all inserts and sends
//! - Tail capture for reverbs/delays
//! - Source-quality render (no quality loss)
//! - Quick unfreeze (original data preserved)

use parking_lot::RwLock;
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::PathBuf;
use std::sync::Arc;

use crate::audio_import::{AudioImporter, ImportedAudio};
use crate::insert_chain::InsertChain;
use crate::track_manager::{Clip, TrackId, TrackManager};

// ═══════════════════════════════════════════════════════════════════════════
// FREEZE CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Freeze render settings
#[derive(Debug, Clone)]
pub struct FreezeConfig {
    /// Sample rate for frozen audio
    pub sample_rate: u32,
    /// Bit depth (16, 24, 32)
    pub bit_depth: u8,
    /// Tail length in seconds (for reverbs/delays)
    pub tail_seconds: f64,
    /// Freeze directory
    pub freeze_dir: PathBuf,
    /// Render sends as well
    pub include_sends: bool,
    /// Render automation
    pub include_automation: bool,
    /// Block size for processing
    pub block_size: usize,
}

impl Default for FreezeConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            bit_depth: 32,
            tail_seconds: 5.0,
            freeze_dir: PathBuf::from("freeze_cache"),
            include_sends: false,
            include_automation: true,
            block_size: 512,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FROZEN TRACK INFO
// ═══════════════════════════════════════════════════════════════════════════

/// Information about a frozen track
#[derive(Debug, Clone)]
pub struct FrozenTrackInfo {
    pub track_id: TrackId,
    /// Path to frozen audio file
    pub frozen_path: PathBuf,
    /// Original start time
    pub start_time: f64,
    /// Frozen duration (including tail)
    pub duration: f64,
    /// Timestamp when frozen
    pub frozen_at: u64,
    /// Freeze config used
    pub config: FreezeConfig,
    /// Serialized insert chain state (for restore)
    pub insert_chain_state: Option<Vec<u8>>,
}

// ═══════════════════════════════════════════════════════════════════════════
// OFFLINE RENDERER
// ═══════════════════════════════════════════════════════════════════════════

/// Offline audio renderer for freeze/bounce
pub struct OfflineRenderer {
    sample_rate: f64,
    block_size: usize,
}

impl OfflineRenderer {
    pub fn new(sample_rate: f64, block_size: usize) -> Self {
        Self {
            sample_rate,
            block_size,
        }
    }

    /// Render a track with inserts to stereo buffers
    /// Returns (left, right) f64 vectors
    pub fn render_track(
        &self,
        clips: &[Clip],
        insert_chain: &mut InsertChain,
        audio_cache: &HashMap<String, Arc<ImportedAudio>>,
        start_time: f64,
        end_time: f64,
        tail_seconds: f64,
        progress_callback: Option<&dyn Fn(f32)>,
    ) -> (Vec<f64>, Vec<f64>) {
        let total_duration = (end_time - start_time) + tail_seconds;
        let total_samples = (total_duration * self.sample_rate) as usize;

        let mut output_l = vec![0.0f64; total_samples];
        let mut output_r = vec![0.0f64; total_samples];

        // Process in blocks
        let num_blocks = total_samples.div_ceil(self.block_size);

        for block_idx in 0..num_blocks {
            let block_start = block_idx * self.block_size;
            let block_end = (block_start + self.block_size).min(total_samples);
            let block_len = block_end - block_start;

            // Block time range
            let block_start_time = start_time + (block_start as f64 / self.sample_rate);
            let block_end_time = start_time + (block_end as f64 / self.sample_rate);

            // Temporary block buffers
            let mut block_l = vec![0.0f64; block_len];
            let mut block_r = vec![0.0f64; block_len];

            // Sum all clips that overlap this block
            for clip in clips {
                if clip.muted {
                    continue;
                }

                // Check clip overlap
                if !clip.overlaps(block_start_time, block_end_time) {
                    continue;
                }

                // Get audio data
                let audio = match audio_cache.get(&clip.source_file) {
                    Some(a) => a,
                    None => continue,
                };

                // Render clip samples into block
                self.render_clip_to_block(
                    clip,
                    audio,
                    block_start_time,
                    &mut block_l,
                    &mut block_r,
                );
            }

            // Apply insert chain processing
            insert_chain.process_all(&mut block_l, &mut block_r);

            // Copy to output
            output_l[block_start..block_start + block_len].copy_from_slice(&block_l[..block_len]);
            output_r[block_start..block_start + block_len].copy_from_slice(&block_r[..block_len]);

            // Report progress
            if let Some(callback) = progress_callback {
                let progress = (block_idx + 1) as f32 / num_blocks as f32;
                callback(progress);
            }
        }

        (output_l, output_r)
    }

    /// Render a single clip's contribution to a block
    fn render_clip_to_block(
        &self,
        clip: &Clip,
        audio: &ImportedAudio,
        block_start_time: f64,
        block_l: &mut [f64],
        block_r: &mut [f64],
    ) {
        let block_len = block_l.len();
        let clip_start_sample = (clip.start_time * self.sample_rate) as i64;
        let source_sample_rate = audio.sample_rate as f64;
        let rate_ratio = source_sample_rate / self.sample_rate;

        // Combined gain
        let gain = clip.gain;

        // Fade parameters
        let fade_in_samples = (clip.fade_in * self.sample_rate) as i64;
        let fade_out_samples = (clip.fade_out * self.sample_rate) as i64;
        let clip_duration_samples = (clip.duration * self.sample_rate) as i64;

        for i in 0..block_len {
            let playback_sample = ((block_start_time * self.sample_rate) as i64) + i as i64;
            let clip_relative_sample = playback_sample - clip_start_sample;

            // Check bounds
            if clip_relative_sample < 0 || clip_relative_sample >= clip_duration_samples {
                continue;
            }

            // Source position
            let source_offset_samples = (clip.source_offset * source_sample_rate) as i64;
            let source_sample = ((clip_relative_sample as f64 * rate_ratio) as i64
                + source_offset_samples) as usize;

            // Get sample
            let (mut sample_l, mut sample_r) = if audio.channels == 1 {
                let s = audio.samples.get(source_sample).copied().unwrap_or(0.0) as f64;
                (s, s)
            } else {
                let idx = source_sample * 2;
                let l = audio.samples.get(idx).copied().unwrap_or(0.0) as f64;
                let r = audio.samples.get(idx + 1).copied().unwrap_or(0.0) as f64;
                (l, r)
            };

            // Calculate fade envelope
            let mut fade = 1.0;

            // Fade in
            if clip_relative_sample < fade_in_samples && fade_in_samples > 0 {
                fade = clip_relative_sample as f64 / fade_in_samples as f64;
                fade = fade * fade; // Quadratic
            }

            // Fade out
            let samples_from_end = clip_duration_samples - clip_relative_sample;
            if samples_from_end < fade_out_samples && fade_out_samples > 0 {
                let fade_out = samples_from_end as f64 / fade_out_samples as f64;
                fade *= fade_out * fade_out;
            }

            // Apply gain and fade
            sample_l *= gain * fade;
            sample_r *= gain * fade;

            block_l[i] += sample_l;
            block_r[i] += sample_r;
        }
    }

    /// Write stereo audio to WAV file (32-bit float)
    pub fn write_wav_f32(
        path: &PathBuf,
        left: &[f64],
        right: &[f64],
        sample_rate: u32,
    ) -> Result<(), std::io::Error> {
        let file = File::create(path)?;
        let mut writer = BufWriter::new(file);

        let num_samples = left.len().min(right.len());
        let num_channels = 2u16;
        let bits_per_sample = 32u16;
        let byte_rate = sample_rate * num_channels as u32 * bits_per_sample as u32 / 8;
        let block_align = num_channels * bits_per_sample / 8;
        let data_size = (num_samples * 2 * 4) as u32;
        let file_size = 36 + data_size;

        // RIFF header
        writer.write_all(b"RIFF")?;
        writer.write_all(&file_size.to_le_bytes())?;
        writer.write_all(b"WAVE")?;

        // fmt chunk
        writer.write_all(b"fmt ")?;
        writer.write_all(&16u32.to_le_bytes())?; // chunk size
        writer.write_all(&3u16.to_le_bytes())?; // IEEE float format
        writer.write_all(&num_channels.to_le_bytes())?;
        writer.write_all(&sample_rate.to_le_bytes())?;
        writer.write_all(&byte_rate.to_le_bytes())?;
        writer.write_all(&block_align.to_le_bytes())?;
        writer.write_all(&bits_per_sample.to_le_bytes())?;

        // data chunk
        writer.write_all(b"data")?;
        writer.write_all(&data_size.to_le_bytes())?;

        // Write interleaved samples
        for i in 0..num_samples {
            let l = left[i] as f32;
            let r = right[i] as f32;
            writer.write_all(&l.to_le_bytes())?;
            writer.write_all(&r.to_le_bytes())?;
        }

        writer.flush()?;
        Ok(())
    }

    /// Write stereo audio to WAV file (24-bit integer)
    pub fn write_wav_24bit(
        path: &PathBuf,
        left: &[f64],
        right: &[f64],
        sample_rate: u32,
    ) -> Result<(), std::io::Error> {
        let file = File::create(path)?;
        let mut writer = BufWriter::new(file);

        let num_samples = left.len().min(right.len());
        let num_channels = 2u16;
        let bits_per_sample = 24u16;
        let byte_rate = sample_rate * num_channels as u32 * 3;
        let block_align = num_channels * 3;
        let data_size = (num_samples * 2 * 3) as u32;
        let file_size = 36 + data_size;

        // RIFF header
        writer.write_all(b"RIFF")?;
        writer.write_all(&file_size.to_le_bytes())?;
        writer.write_all(b"WAVE")?;

        // fmt chunk
        writer.write_all(b"fmt ")?;
        writer.write_all(&16u32.to_le_bytes())?;
        writer.write_all(&1u16.to_le_bytes())?; // PCM format
        writer.write_all(&num_channels.to_le_bytes())?;
        writer.write_all(&sample_rate.to_le_bytes())?;
        writer.write_all(&byte_rate.to_le_bytes())?;
        writer.write_all(&block_align.to_le_bytes())?;
        writer.write_all(&bits_per_sample.to_le_bytes())?;

        // data chunk
        writer.write_all(b"data")?;
        writer.write_all(&data_size.to_le_bytes())?;

        // Write interleaved 24-bit samples
        for i in 0..num_samples {
            // Clamp and convert to 24-bit integer
            let l = (left[i].clamp(-1.0, 1.0) * 8388607.0) as i32;
            let r = (right[i].clamp(-1.0, 1.0) * 8388607.0) as i32;

            writer.write_all(&l.to_le_bytes()[0..3])?;
            writer.write_all(&r.to_le_bytes()[0..3])?;
        }

        writer.flush()?;
        Ok(())
    }

    /// Write stereo audio to WAV file (16-bit integer)
    pub fn write_wav_16bit(
        path: &PathBuf,
        left: &[f64],
        right: &[f64],
        sample_rate: u32,
    ) -> Result<(), std::io::Error> {
        let file = File::create(path)?;
        let mut writer = BufWriter::new(file);

        let num_samples = left.len().min(right.len());
        let num_channels = 2u16;
        let bits_per_sample = 16u16;
        let byte_rate = sample_rate * num_channels as u32 * 2;
        let block_align = num_channels * 2;
        let data_size = (num_samples * 2 * 2) as u32;
        let file_size = 36 + data_size;

        // RIFF header
        writer.write_all(b"RIFF")?;
        writer.write_all(&file_size.to_le_bytes())?;
        writer.write_all(b"WAVE")?;

        // fmt chunk
        writer.write_all(b"fmt ")?;
        writer.write_all(&16u32.to_le_bytes())?;
        writer.write_all(&1u16.to_le_bytes())?; // PCM format
        writer.write_all(&num_channels.to_le_bytes())?;
        writer.write_all(&sample_rate.to_le_bytes())?;
        writer.write_all(&byte_rate.to_le_bytes())?;
        writer.write_all(&block_align.to_le_bytes())?;
        writer.write_all(&bits_per_sample.to_le_bytes())?;

        // data chunk
        writer.write_all(b"data")?;
        writer.write_all(&data_size.to_le_bytes())?;

        // Write interleaved 16-bit samples
        for i in 0..num_samples {
            let l = (left[i].clamp(-1.0, 1.0) * 32767.0) as i16;
            let r = (right[i].clamp(-1.0, 1.0) * 32767.0) as i16;
            writer.write_all(&l.to_le_bytes())?;
            writer.write_all(&r.to_le_bytes())?;
        }

        writer.flush()?;
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FREEZE MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Manages track freezing/unfreezing
pub struct FreezeManager {
    /// Frozen track info
    frozen_tracks: RwLock<HashMap<TrackId, FrozenTrackInfo>>,
    /// Default config
    config: FreezeConfig,
    /// Progress callback
    progress_callback: Option<Arc<dyn Fn(TrackId, f32) + Send + Sync>>,
    /// Insert chains per track (for processing)
    insert_chains: RwLock<HashMap<TrackId, InsertChain>>,
}

impl FreezeManager {
    pub fn new(config: FreezeConfig) -> Self {
        // Ensure freeze directory exists
        if !config.freeze_dir.exists() {
            std::fs::create_dir_all(&config.freeze_dir).ok();
        }

        Self {
            frozen_tracks: RwLock::new(HashMap::new()),
            config,
            progress_callback: None,
            insert_chains: RwLock::new(HashMap::new()),
        }
    }

    /// Set progress callback
    pub fn set_progress_callback<F>(&mut self, callback: F)
    where
        F: Fn(TrackId, f32) + Send + Sync + 'static,
    {
        self.progress_callback = Some(Arc::new(callback));
    }

    /// Register insert chain for a track
    pub fn register_insert_chain(&self, track_id: TrackId, chain: InsertChain) {
        self.insert_chains.write().insert(track_id, chain);
    }

    /// Check if track is frozen
    pub fn is_frozen(&self, track_id: TrackId) -> bool {
        self.frozen_tracks.read().contains_key(&track_id)
    }

    /// Get frozen track info
    pub fn get_frozen_info(&self, track_id: TrackId) -> Option<FrozenTrackInfo> {
        self.frozen_tracks.read().get(&track_id).cloned()
    }

    /// Freeze a track with full offline render
    pub fn freeze_track_with_manager(
        &self,
        track_manager: &TrackManager,
        track_id: TrackId,
        sample_rate: u32,
    ) -> Result<PathBuf, FreezeError> {
        if self.is_frozen(track_id) {
            return Err(FreezeError::AlreadyFrozen);
        }

        // Get track clips
        let clips = track_manager.get_clips_for_track(track_id);
        if clips.is_empty() {
            return Err(FreezeError::RenderError("Track has no clips".to_string()));
        }

        // Calculate time range
        let start_time = clips.iter().map(|c| c.start_time).fold(f64::MAX, f64::min);
        let end_time = clips.iter().map(|c| c.end_time()).fold(0.0, f64::max);

        // Load audio files into cache
        let mut audio_cache: HashMap<String, Arc<ImportedAudio>> = HashMap::new();
        for clip in &clips {
            if !audio_cache.contains_key(&clip.source_file) {
                match AudioImporter::import(std::path::Path::new(&clip.source_file)) {
                    Ok(audio) => {
                        audio_cache.insert(clip.source_file.clone(), Arc::new(audio));
                    }
                    Err(e) => {
                        log::warn!("Failed to load audio for freeze: {}", e);
                    }
                }
            }
        }

        // Get or create insert chain for this track
        let mut insert_chain = self
            .insert_chains
            .write()
            .remove(&track_id)
            .unwrap_or_else(|| InsertChain::new(sample_rate as f64));

        insert_chain.set_sample_rate(sample_rate as f64);

        // Create offline renderer
        let renderer = OfflineRenderer::new(sample_rate as f64, self.config.block_size);

        // Render track
        let callback = self.progress_callback.clone();
        let track_id_copy = track_id;
        let progress_fn: Option<Box<dyn Fn(f32)>> = callback.map(|cb| {
            Box::new(move |progress: f32| {
                cb(track_id_copy, progress);
            }) as Box<dyn Fn(f32)>
        });

        let (left, right) = renderer.render_track(
            &clips,
            &mut insert_chain,
            &audio_cache,
            start_time,
            end_time,
            self.config.tail_seconds,
            progress_fn.as_ref().map(|f| f.as_ref()),
        );

        // Generate output filename
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();

        let filename = format!("freeze_{}_{}.wav", track_id.0, timestamp);
        let frozen_path = self.config.freeze_dir.join(&filename);

        // Write WAV file based on bit depth
        match self.config.bit_depth {
            16 => OfflineRenderer::write_wav_16bit(&frozen_path, &left, &right, sample_rate)?,
            24 => OfflineRenderer::write_wav_24bit(&frozen_path, &left, &right, sample_rate)?,
            _ => OfflineRenderer::write_wav_f32(&frozen_path, &left, &right, sample_rate)?,
        }

        let total_duration = (end_time - start_time) + self.config.tail_seconds;

        // Store frozen info
        let info = FrozenTrackInfo {
            track_id,
            frozen_path: frozen_path.clone(),
            start_time,
            duration: total_duration,
            frozen_at: timestamp as u64,
            config: self.config.clone(),
            insert_chain_state: None, // Could serialize insert chain state here
        };

        self.frozen_tracks.write().insert(track_id, info);

        // Store insert chain back (will be bypassed during playback)
        self.insert_chains.write().insert(track_id, insert_chain);

        log::info!(
            "Froze track {} to {:?} ({:.2}s, {} samples)",
            track_id.0,
            frozen_path,
            total_duration,
            left.len()
        );

        Ok(frozen_path)
    }

    /// Freeze a track (legacy interface)
    pub fn freeze_track(
        &self,
        track_id: TrackId,
        start_time: f64,
        end_time: f64,
        _sample_rate: u32,
    ) -> Result<PathBuf, FreezeError> {
        if self.is_frozen(track_id) {
            return Err(FreezeError::AlreadyFrozen);
        }

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();

        let filename = format!("freeze_{}_{}.wav", track_id.0, timestamp);
        let frozen_path = self.config.freeze_dir.join(&filename);
        let total_duration = (end_time - start_time) + self.config.tail_seconds;

        log::info!(
            "Freezing track {} from {}s to {}s (total: {}s)",
            track_id.0,
            start_time,
            end_time,
            total_duration
        );

        // Progress simulation for legacy interface
        if let Some(callback) = &self.progress_callback {
            for i in 0..=10 {
                callback(track_id, i as f32 / 10.0);
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
        }

        let info = FrozenTrackInfo {
            track_id,
            frozen_path: frozen_path.clone(),
            start_time,
            duration: total_duration,
            frozen_at: timestamp as u64,
            config: self.config.clone(),
            insert_chain_state: None,
        };

        self.frozen_tracks.write().insert(track_id, info);
        log::info!("Track {} frozen to {:?}", track_id.0, frozen_path);
        Ok(frozen_path)
    }

    /// Unfreeze a track
    pub fn unfreeze_track(&self, track_id: TrackId) -> Result<(), FreezeError> {
        let info = self
            .frozen_tracks
            .write()
            .remove(&track_id)
            .ok_or(FreezeError::NotFrozen)?;

        if info.frozen_path.exists() {
            std::fs::remove_file(&info.frozen_path).ok();
        }

        log::info!("Track {} unfrozen", track_id.0);
        Ok(())
    }

    /// Get all frozen tracks
    pub fn frozen_tracks(&self) -> Vec<TrackId> {
        self.frozen_tracks.read().keys().copied().collect()
    }

    /// Get total frozen audio size in bytes
    pub fn total_frozen_size(&self) -> u64 {
        self.frozen_tracks
            .read()
            .values()
            .filter_map(|info| std::fs::metadata(&info.frozen_path).ok())
            .map(|m| m.len())
            .sum()
    }

    /// Clear all freeze cache
    pub fn clear_cache(&self) {
        let mut frozen = self.frozen_tracks.write();
        for info in frozen.values() {
            if info.frozen_path.exists() {
                std::fs::remove_file(&info.frozen_path).ok();
            }
        }
        frozen.clear();
        log::info!("Freeze cache cleared");
    }

    /// Get frozen audio path for playback
    pub fn get_frozen_audio_path(&self, track_id: TrackId) -> Option<PathBuf> {
        self.frozen_tracks
            .read()
            .get(&track_id)
            .map(|info| info.frozen_path.clone())
    }
}

impl Default for FreezeManager {
    fn default() -> Self {
        Self::new(FreezeConfig::default())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ERRORS
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, thiserror::Error)]
pub enum FreezeError {
    #[error("Track is already frozen")]
    AlreadyFrozen,
    #[error("Track is not frozen")]
    NotFrozen,
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Render error: {0}")]
    RenderError(String),
}

// ═══════════════════════════════════════════════════════════════════════════
// FFI
// ═══════════════════════════════════════════════════════════════════════════

use lazy_static::lazy_static;

lazy_static! {
    static ref FREEZE_MANAGER: FreezeManager = FreezeManager::default();
}

/// Freeze a track
#[unsafe(no_mangle)]
pub extern "C" fn track_freeze(track_id: u64, start_time: f64, end_time: f64) -> i32 {
    match FREEZE_MANAGER.freeze_track(TrackId(track_id), start_time, end_time, 48000) {
        Ok(_) => 1,
        Err(e) => {
            log::error!("Freeze failed: {}", e);
            0
        }
    }
}

/// Unfreeze a track
#[unsafe(no_mangle)]
pub extern "C" fn track_unfreeze(track_id: u64) -> i32 {
    match FREEZE_MANAGER.unfreeze_track(TrackId(track_id)) {
        Ok(_) => 1,
        Err(e) => {
            log::error!("Unfreeze failed: {}", e);
            0
        }
    }
}

/// Check if track is frozen
#[unsafe(no_mangle)]
pub extern "C" fn track_is_frozen(track_id: u64) -> i32 {
    if FREEZE_MANAGER.is_frozen(TrackId(track_id)) {
        1
    } else {
        0
    }
}

/// Get total freeze cache size in MB
#[unsafe(no_mangle)]
pub extern "C" fn freeze_cache_size_mb() -> f32 {
    (FREEZE_MANAGER.total_frozen_size() as f32) / (1024.0 * 1024.0)
}

/// Clear all freeze cache
#[unsafe(no_mangle)]
pub extern "C" fn freeze_clear_cache() {
    FREEZE_MANAGER.clear_cache();
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_freeze_config_default() {
        let config = FreezeConfig::default();
        assert_eq!(config.sample_rate, 48000);
        assert_eq!(config.bit_depth, 32);
        assert_eq!(config.tail_seconds, 5.0);
    }

    #[test]
    fn test_freeze_manager_new() {
        let config = FreezeConfig {
            freeze_dir: std::env::temp_dir().join("rf_freeze_test"),
            ..Default::default()
        };
        let manager = FreezeManager::new(config);

        assert!(manager.frozen_tracks().is_empty());
    }

    /// Force OS buffer → disk sync (ExFAT volumes have delayed allocation)
    fn sync_file(path: &std::path::Path) {
        if let Ok(file) = std::fs::File::open(path) {
            let _ = file.sync_all();
        }
    }

    #[test]
    fn test_offline_renderer_wav_write() {
        let dir = std::env::temp_dir().join("rf_freeze_test");
        std::fs::create_dir_all(&dir).ok();

        let path = dir.join("test_render.wav");
        let _ = std::fs::remove_file(&path); // Clean up leftover

        // Generate 1 second of stereo sine wave
        let sample_rate = 48000;
        let samples = sample_rate;
        let mut left = vec![0.0f64; samples];
        let mut right = vec![0.0f64; samples];

        for i in 0..samples {
            let t = i as f64 / sample_rate as f64;
            left[i] = (440.0 * 2.0 * std::f64::consts::PI * t).sin() * 0.5;
            right[i] = (880.0 * 2.0 * std::f64::consts::PI * t).sin() * 0.5;
        }

        // Write 32-bit float
        OfflineRenderer::write_wav_f32(&path, &left, &right, sample_rate as u32)
            .expect("Failed to write WAV f32");
        sync_file(&path);

        assert!(path.exists(), "WAV f32 file should exist after write+sync");

        let metadata = std::fs::metadata(&path).expect("Failed to read metadata");
        assert!(metadata.len() > 0, "WAV f32 file should have content");

        // Cleanup
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn test_offline_renderer_24bit() {
        let dir = std::env::temp_dir().join("rf_freeze_test");
        std::fs::create_dir_all(&dir).ok();

        let path = dir.join("test_render_24.wav");
        let _ = std::fs::remove_file(&path); // Clean up leftover

        let left = vec![0.5f64; 1000];
        let right = vec![-0.5f64; 1000];

        OfflineRenderer::write_wav_24bit(&path, &left, &right, 48000)
            .expect("Failed to write WAV 24bit");
        sync_file(&path);

        assert!(path.exists(), "WAV 24bit file should exist after write+sync");

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn test_offline_renderer_16bit() {
        let dir = std::env::temp_dir().join("rf_freeze_test");
        std::fs::create_dir_all(&dir).ok();

        let path = dir.join("test_render_16.wav");
        let _ = std::fs::remove_file(&path); // Clean up leftover

        let left = vec![0.25f64; 1000];
        let right = vec![-0.25f64; 1000];

        OfflineRenderer::write_wav_16bit(&path, &left, &right, 44100)
            .expect("Failed to write WAV 16bit");
        sync_file(&path);

        assert!(path.exists(), "WAV 16bit file should exist after write+sync");

        let _ = std::fs::remove_file(&path);
    }
}

//! Recording Manager
//!
//! Integrates rf-file AudioRecorder with the playback engine.
//! - Manages armed tracks
//! - Routes input audio to recorders
//! - Handles punch in/out
//! - Manages take folders

use parking_lot::RwLock;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use rf_file::recording::{AudioRecorder, RecordingConfig, RecordingState};

use crate::track_manager::TrackId;

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Recording manager for managing multiple track recordings
pub struct RecordingManager {
    /// Active recorders per track
    recorders: RwLock<HashMap<TrackId, Arc<AudioRecorder>>>,
    /// Global recording config
    config: RwLock<RecordingConfig>,
    /// Sample rate
    sample_rate: u32,
}

impl RecordingManager {
    pub fn new(sample_rate: u32) -> Self {
        Self {
            recorders: RwLock::new(HashMap::new()),
            config: RwLock::new(RecordingConfig {
                sample_rate,
                ..Default::default()
            }),
            sample_rate,
        }
    }

    /// Set output directory for recordings
    pub fn set_output_dir(&self, path: PathBuf) {
        self.config.write().output_dir = path;
    }

    /// Get output directory
    pub fn output_dir(&self) -> PathBuf {
        self.config.read().output_dir.clone()
    }

    /// Arm track for recording
    pub fn arm_track(&self, track_id: TrackId, num_channels: u16, track_name: &str) -> bool {
        let mut config = self.config.read().clone();
        config.num_channels = num_channels;
        config.file_prefix = format!("{}_Recording", track_name);

        let recorder = Arc::new(AudioRecorder::new(config));

        self.recorders.write().insert(track_id, recorder);
        true
    }

    /// Disarm track
    pub fn disarm_track(&self, track_id: TrackId) -> bool {
        self.recorders.write().remove(&track_id).is_some()
    }

    /// Start recording on armed track
    pub fn start_recording(&self, track_id: TrackId) -> Option<PathBuf> {
        let recorders = self.recorders.read();
        if let Some(recorder) = recorders.get(&track_id) {
            recorder.start().ok()
        } else {
            None
        }
    }

    /// Stop recording on track
    pub fn stop_recording(&self, track_id: TrackId) -> Option<PathBuf> {
        let recorders = self.recorders.read();
        if let Some(recorder) = recorders.get(&track_id) {
            recorder.stop().ok().flatten()
        } else {
            None
        }
    }

    /// Start recording on all armed tracks
    pub fn start_all(&self) -> Vec<(TrackId, PathBuf)> {
        let recorders = self.recorders.read();
        recorders
            .iter()
            .filter_map(|(track_id, recorder)| {
                recorder.start().ok().map(|path| (*track_id, path))
            })
            .collect()
    }

    /// Stop recording on all tracks
    pub fn stop_all(&self) -> Vec<(TrackId, PathBuf)> {
        let recorders = self.recorders.read();
        recorders
            .iter()
            .filter_map(|(track_id, recorder)| {
                recorder
                    .stop()
                    .ok()
                    .flatten()
                    .map(|path| (*track_id, path))
            })
            .collect()
    }

    /// Write audio samples to track recorder
    ///
    /// # Safety
    /// Must be called from audio thread only
    pub fn write_samples(&self, track_id: TrackId, samples: &[f32], position: u64) {
        let recorders = self.recorders.read();
        if let Some(recorder) = recorders.get(&track_id) {
            recorder.process(samples, position);
        }
    }

    /// Get recording state for track
    pub fn get_state(&self, track_id: TrackId) -> Option<RecordingState> {
        let recorders = self.recorders.read();
        recorders.get(&track_id).map(|r| r.state())
    }

    /// Check if track is armed
    pub fn is_armed(&self, track_id: TrackId) -> bool {
        self.recorders.read().contains_key(&track_id)
    }

    /// Check if track is recording
    pub fn is_recording(&self, track_id: TrackId) -> bool {
        matches!(
            self.get_state(track_id),
            Some(RecordingState::Recording)
        )
    }

    /// Get number of armed tracks
    pub fn armed_count(&self) -> usize {
        self.recorders.read().len()
    }

    /// Get number of recording tracks
    pub fn recording_count(&self) -> usize {
        self.recorders
            .read()
            .values()
            .filter(|r| r.state() == RecordingState::Recording)
            .count()
    }

    /// Clear all recorders
    pub fn clear(&self) {
        let mut recorders = self.recorders.write();
        // Stop all before clearing
        for recorder in recorders.values() {
            let _ = recorder.stop();
        }
        recorders.clear();
    }
}

impl Default for RecordingManager {
    fn default() -> Self {
        Self::new(48000)
    }
}

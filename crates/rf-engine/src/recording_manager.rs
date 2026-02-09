//! Recording Manager
//!
//! Integrates rf-file AudioRecorder with the playback engine.
//! - Manages armed tracks
//! - Routes input audio to recorders
//! - Handles punch in/out
//! - Pre-roll support
//! - Auto-arm on input detect
//! - Manages take folders

use parking_lot::RwLock;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use rf_file::recording::{AudioRecorder, RecordingConfig, RecordingState};

use crate::track_manager::TrackId;

// ═══════════════════════════════════════════════════════════════════════════
// PUNCH MODE
// ═══════════════════════════════════════════════════════════════════════════

/// Punch recording mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PunchMode {
    /// Normal recording (no punch)
    #[default]
    Off,
    /// Punch in at punch_in point
    PunchIn,
    /// Punch out at punch_out point
    PunchOut,
    /// Punch in AND out (replace region)
    PunchInOut,
}

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

    // Punch in/out
    /// Punch mode
    punch_mode: RwLock<PunchMode>,
    /// Punch in point (in samples)
    punch_in: AtomicU64,
    /// Punch out point (in samples)
    punch_out: AtomicU64,
    /// Is currently punched in (recording within punch region)
    punched_in: AtomicBool,

    // Pre-roll
    /// Pre-roll enabled
    pre_roll_enabled: AtomicBool,
    /// Pre-roll duration in samples
    pre_roll_samples: AtomicU64,
    /// Pre-roll bars (alternative to samples)
    pre_roll_bars: AtomicU64,

    // Auto-arm
    /// Auto-arm enabled (arm tracks when input signal detected)
    auto_arm_enabled: AtomicBool,
    /// Auto-arm threshold (linear amplitude, typically -40dB = 0.01)
    auto_arm_threshold: AtomicU64,
    /// Tracks pending auto-arm
    pending_auto_arm: RwLock<Vec<TrackId>>,
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

            // Punch
            punch_mode: RwLock::new(PunchMode::Off),
            punch_in: AtomicU64::new(0),
            punch_out: AtomicU64::new(0),
            punched_in: AtomicBool::new(false),

            // Pre-roll
            pre_roll_enabled: AtomicBool::new(false),
            pre_roll_samples: AtomicU64::new(48000), // 1 second default
            pre_roll_bars: AtomicU64::new(1),

            // Auto-arm
            auto_arm_enabled: AtomicBool::new(false),
            auto_arm_threshold: AtomicU64::new(0.01_f64.to_bits()), // -40dB
            pending_auto_arm: RwLock::new(Vec::new()),
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Punch In/Out
    // ─────────────────────────────────────────────────────────────────────────

    /// Set punch mode
    pub fn set_punch_mode(&self, mode: PunchMode) {
        *self.punch_mode.write() = mode;
    }

    /// Get punch mode
    pub fn punch_mode(&self) -> PunchMode {
        *self.punch_mode.read()
    }

    /// Set punch in point (in samples)
    pub fn set_punch_in(&self, sample: u64) {
        self.punch_in.store(sample, Ordering::Relaxed);
    }

    /// Get punch in point
    pub fn punch_in(&self) -> u64 {
        self.punch_in.load(Ordering::Relaxed)
    }

    /// Set punch out point (in samples)
    pub fn set_punch_out(&self, sample: u64) {
        self.punch_out.store(sample, Ordering::Relaxed);
    }

    /// Get punch out point
    pub fn punch_out(&self) -> u64 {
        self.punch_out.load(Ordering::Relaxed)
    }

    /// Set punch points from time in seconds
    pub fn set_punch_times(&self, punch_in_secs: f64, punch_out_secs: f64) {
        let punch_in = (punch_in_secs * self.sample_rate as f64) as u64;
        let punch_out = (punch_out_secs * self.sample_rate as f64) as u64;
        self.punch_in.store(punch_in, Ordering::Relaxed);
        self.punch_out.store(punch_out, Ordering::Relaxed);
    }

    /// Check if position is within punch region and handle state
    /// Returns true if recording should be active at this position
    pub fn check_punch(&self, position: u64) -> bool {
        let mode = *self.punch_mode.read();
        let punch_in = self.punch_in.load(Ordering::Relaxed);
        let punch_out = self.punch_out.load(Ordering::Relaxed);

        match mode {
            PunchMode::Off => true, // Always record when no punch
            PunchMode::PunchIn => {
                // Start recording when we reach punch_in
                if position >= punch_in {
                    self.punched_in.store(true, Ordering::Relaxed);
                    true
                } else {
                    false
                }
            }
            PunchMode::PunchOut => {
                // Stop recording when we reach punch_out
                if position < punch_out {
                    true
                } else {
                    self.punched_in.store(false, Ordering::Relaxed);
                    false
                }
            }
            PunchMode::PunchInOut => {
                // Record only between punch_in and punch_out
                let in_region = position >= punch_in && position < punch_out;
                self.punched_in.store(in_region, Ordering::Relaxed);
                in_region
            }
        }
    }

    /// Check if currently punched in
    pub fn is_punched_in(&self) -> bool {
        self.punched_in.load(Ordering::Relaxed)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pre-Roll
    // ─────────────────────────────────────────────────────────────────────────

    /// Enable/disable pre-roll
    pub fn set_pre_roll_enabled(&self, enabled: bool) {
        self.pre_roll_enabled.store(enabled, Ordering::Relaxed);
    }

    /// Check if pre-roll is enabled
    pub fn pre_roll_enabled(&self) -> bool {
        self.pre_roll_enabled.load(Ordering::Relaxed)
    }

    /// Set pre-roll duration in samples
    pub fn set_pre_roll_samples(&self, samples: u64) {
        self.pre_roll_samples.store(samples, Ordering::Relaxed);
    }

    /// Get pre-roll duration in samples
    pub fn pre_roll_samples(&self) -> u64 {
        self.pre_roll_samples.load(Ordering::Relaxed)
    }

    /// Set pre-roll in seconds
    pub fn set_pre_roll_seconds(&self, seconds: f64) {
        let samples = (seconds * self.sample_rate as f64) as u64;
        self.pre_roll_samples.store(samples, Ordering::Relaxed);
    }

    /// Set pre-roll in bars (requires tempo to calculate)
    pub fn set_pre_roll_bars(&self, bars: u64) {
        self.pre_roll_bars.store(bars, Ordering::Relaxed);
    }

    /// Get pre-roll in bars
    pub fn pre_roll_bars(&self) -> u64 {
        self.pre_roll_bars.load(Ordering::Relaxed)
    }

    /// Calculate pre-roll start position given record start and tempo
    pub fn pre_roll_start(&self, record_start: u64, tempo: f64) -> u64 {
        if !self.pre_roll_enabled.load(Ordering::Relaxed) {
            return record_start;
        }

        // If pre-roll bars is set, calculate from tempo
        let bars = self.pre_roll_bars.load(Ordering::Relaxed);
        let pre_roll = if bars > 0 {
            // 4 beats per bar, calculate samples per bar
            let beats_per_bar = 4.0;
            let samples_per_beat = (60.0 / tempo) * self.sample_rate as f64;
            let samples_per_bar = samples_per_beat * beats_per_bar;
            (bars as f64 * samples_per_bar) as u64
        } else {
            self.pre_roll_samples.load(Ordering::Relaxed)
        };

        record_start.saturating_sub(pre_roll)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Auto-Arm
    // ─────────────────────────────────────────────────────────────────────────

    /// Enable/disable auto-arm
    pub fn set_auto_arm_enabled(&self, enabled: bool) {
        self.auto_arm_enabled.store(enabled, Ordering::Relaxed);
    }

    /// Check if auto-arm is enabled
    pub fn auto_arm_enabled(&self) -> bool {
        self.auto_arm_enabled.load(Ordering::Relaxed)
    }

    /// Set auto-arm threshold in dB
    pub fn set_auto_arm_threshold_db(&self, db: f64) {
        let linear = 10.0_f64.powf(db / 20.0);
        self.auto_arm_threshold
            .store(linear.to_bits(), Ordering::Relaxed);
    }

    /// Get auto-arm threshold (linear)
    pub fn auto_arm_threshold(&self) -> f64 {
        f64::from_bits(self.auto_arm_threshold.load(Ordering::Relaxed))
    }

    /// Add track to pending auto-arm list
    pub fn add_pending_auto_arm(&self, track_id: TrackId) {
        let mut pending = self.pending_auto_arm.write();
        if !pending.contains(&track_id) {
            pending.push(track_id);
        }
    }

    /// Remove track from pending auto-arm list
    pub fn remove_pending_auto_arm(&self, track_id: TrackId) {
        self.pending_auto_arm.write().retain(|&id| id != track_id);
    }

    /// Check input signal against threshold for auto-arm
    /// Returns tracks that should be armed based on signal level
    pub fn check_auto_arm(&self, track_id: TrackId, peak_level: f64) -> bool {
        if !self.auto_arm_enabled.load(Ordering::Relaxed) {
            return false;
        }

        let threshold = self.auto_arm_threshold();
        let pending = self.pending_auto_arm.read();

        if pending.contains(&track_id) && peak_level > threshold {
            return true; // Signal exceeds threshold, arm this track
        }

        false
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
            .filter_map(|(track_id, recorder)| recorder.start().ok().map(|path| (*track_id, path)))
            .collect()
    }

    /// Stop recording on all tracks
    pub fn stop_all(&self) -> Vec<(TrackId, PathBuf)> {
        let recorders = self.recorders.read();
        recorders
            .iter()
            .filter_map(|(track_id, recorder)| {
                recorder.stop().ok().flatten().map(|path| (*track_id, path))
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
        matches!(self.get_state(track_id), Some(RecordingState::Recording))
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

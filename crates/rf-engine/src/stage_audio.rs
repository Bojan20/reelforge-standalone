//! Stage Audio Integration - Connect Stage Events to Audio Playback
//!
//! Provides:
//! - Stage event → Audio cue triggering
//! - Timed audio preview based on stage timing
//! - Audio markers synced to stages
//! - Preview playback with stage-driven transport

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::RwLock;

use crate::playback::PlaybackEngine;
use crate::track_manager::TrackManager;
use rf_stage::event::StageEvent;
use rf_stage::timing::{TimedStageEvent, TimedStageTrace};

// ═══════════════════════════════════════════════════════════════════════════
// STAGE AUDIO CUE
// ═══════════════════════════════════════════════════════════════════════════

/// Audio cue triggered by a stage event
#[derive(Debug, Clone)]
pub struct StageCue {
    /// Unique cue ID
    pub id: u64,
    /// Stage type that triggers this cue (e.g., "spin_start", "reel_stop")
    pub stage_trigger: String,
    /// Optional specific stage index (for reels, symbols, etc.)
    pub stage_index: Option<u32>,
    /// Audio file path to play
    pub audio_path: String,
    /// Volume (0.0 to 1.0)
    pub volume: f64,
    /// Pan (-1.0 left to 1.0 right)
    pub pan: f64,
    /// Delay offset in milliseconds from stage start
    pub delay_ms: f64,
    /// Whether cue is enabled
    pub enabled: bool,
}

impl Default for StageCue {
    fn default() -> Self {
        Self {
            id: 0,
            stage_trigger: String::new(),
            stage_index: None,
            audio_path: String::new(),
            volume: 1.0,
            pan: 0.0,
            delay_ms: 0.0,
            enabled: true,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE AUDIO ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Stage-driven audio playback engine
pub struct StageAudioEngine {
    /// Reference to main playback engine
    playback: Arc<PlaybackEngine>,
    /// Track manager for creating audio clips (reserved for cue-to-clip conversion)
    #[allow(dead_code)]
    track_manager: Arc<TrackManager>,
    /// Registered stage cues (stage_type -> cues)
    cues: RwLock<HashMap<String, Vec<StageCue>>>,
    /// Current timed trace for preview
    current_trace: RwLock<Option<TimedStageTrace>>,
    /// Preview playback position (milliseconds)
    preview_position_ms: AtomicU64,
    /// Preview playing state
    preview_playing: AtomicBool,
    /// Next cue ID
    next_cue_id: AtomicU64,
    /// Sample rate
    sample_rate: u32,
}

impl StageAudioEngine {
    /// Create new stage audio engine
    pub fn new(
        playback: Arc<PlaybackEngine>,
        track_manager: Arc<TrackManager>,
        sample_rate: u32,
    ) -> Self {
        Self {
            playback,
            track_manager,
            cues: RwLock::new(HashMap::new()),
            current_trace: RwLock::new(None),
            preview_position_ms: AtomicU64::new(0),
            preview_playing: AtomicBool::new(false),
            next_cue_id: AtomicU64::new(1),
            sample_rate,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CUE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// Register a new audio cue for a stage type
    pub fn add_cue(&self, mut cue: StageCue) -> u64 {
        let id = self.next_cue_id.fetch_add(1, Ordering::Relaxed);
        cue.id = id;

        let trigger = cue.stage_trigger.clone();
        let mut cues = self.cues.write();
        cues.entry(trigger).or_default().push(cue);

        id
    }

    /// Remove a cue by ID
    pub fn remove_cue(&self, cue_id: u64) -> bool {
        let mut cues = self.cues.write();
        for cue_list in cues.values_mut() {
            if let Some(pos) = cue_list.iter().position(|c| c.id == cue_id) {
                cue_list.remove(pos);
                return true;
            }
        }
        false
    }

    /// Update an existing cue
    pub fn update_cue(&self, cue: StageCue) -> bool {
        let mut cues = self.cues.write();
        for cue_list in cues.values_mut() {
            if let Some(existing) = cue_list.iter_mut().find(|c| c.id == cue.id) {
                *existing = cue;
                return true;
            }
        }
        false
    }

    /// Get all cues for a stage type
    pub fn get_cues(&self, stage_type: &str) -> Vec<StageCue> {
        let cues = self.cues.read();
        cues.get(stage_type).cloned().unwrap_or_default()
    }

    /// Get all registered cues
    pub fn all_cues(&self) -> Vec<StageCue> {
        let cues = self.cues.read();
        cues.values().flatten().cloned().collect()
    }

    /// Clear all cues
    pub fn clear_cues(&self) {
        self.cues.write().clear();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENT TRIGGERING
    // ═══════════════════════════════════════════════════════════════════════

    /// Handle incoming stage event and trigger matching cues
    pub fn on_stage_event(&self, event: &StageEvent) {
        let stage_type = event.stage.type_name();
        let cues = self.cues.read();

        if let Some(matching_cues) = cues.get(stage_type) {
            for cue in matching_cues.iter().filter(|c| c.enabled) {
                // Check index match if specified - skip if mismatch
                if cue.stage_index.is_some_and(|required_idx| {
                    self.get_stage_index(event)
                        .is_some_and(|idx| idx != required_idx)
                }) {
                    continue;
                }

                // Trigger the audio cue
                self.trigger_cue(cue, event.timestamp_ms);
            }
        }
    }

    /// Get stage index from event (for reel index, symbol index, etc.)
    fn get_stage_index(&self, event: &StageEvent) -> Option<u32> {
        // Extract index from stage-specific data
        match &event.stage {
            rf_stage::Stage::ReelStop { reel_index, .. } => Some(*reel_index as u32),
            rf_stage::Stage::ReelSpinning { reel_index } => Some(*reel_index as u32),
            rf_stage::Stage::AnticipationOn { reel_index, .. } => Some(*reel_index as u32),
            _ => None,
        }
    }

    /// Trigger an audio cue at specified time
    fn trigger_cue(&self, cue: &StageCue, trigger_time_ms: f64) {
        let actual_time_ms = trigger_time_ms + cue.delay_ms;
        let position_samples = self.ms_to_samples(actual_time_ms);

        log::debug!(
            "[StageAudio] Triggering cue {} at {}ms (audio: {})",
            cue.id,
            actual_time_ms,
            cue.audio_path
        );

        // Load and schedule audio through playback engine
        // For now, seek to position and rely on track clips
        // Full implementation would create one-shot clips or use event-based triggering
        self.playback.seek_samples(position_samples);
    }

    /// Convert milliseconds to samples
    fn ms_to_samples(&self, ms: f64) -> u64 {
        ((ms / 1000.0) * self.sample_rate as f64) as u64
    }

    /// Convert samples to milliseconds
    fn samples_to_ms(&self, samples: u64) -> f64 {
        (samples as f64 / self.sample_rate as f64) * 1000.0
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PREVIEW PLAYBACK
    // ═══════════════════════════════════════════════════════════════════════

    /// Load a timed trace for preview
    pub fn load_trace(&self, trace: TimedStageTrace) {
        *self.current_trace.write() = Some(trace);
        self.preview_position_ms.store(0, Ordering::Relaxed);
    }

    /// Clear current trace
    pub fn clear_trace(&self) {
        *self.current_trace.write() = None;
        self.preview_playing.store(false, Ordering::Relaxed);
    }

    /// Start preview playback
    pub fn preview_play(&self) {
        if self.current_trace.read().is_some() {
            self.preview_playing.store(true, Ordering::Relaxed);
            self.playback.play();
        }
    }

    /// Pause preview playback
    pub fn preview_pause(&self) {
        self.preview_playing.store(false, Ordering::Relaxed);
        self.playback.pause();
    }

    /// Stop preview playback
    pub fn preview_stop(&self) {
        self.preview_playing.store(false, Ordering::Relaxed);
        self.preview_position_ms.store(0, Ordering::Relaxed);
        self.playback.stop();
    }

    /// Seek preview to position
    pub fn preview_seek(&self, position_ms: f64) {
        self.preview_position_ms
            .store(position_ms.to_bits(), Ordering::Relaxed);
        self.playback.seek_samples(self.ms_to_samples(position_ms));
    }

    /// Get current preview position in milliseconds
    pub fn preview_position(&self) -> f64 {
        f64::from_bits(self.preview_position_ms.load(Ordering::Relaxed))
    }

    /// Is preview currently playing?
    pub fn is_preview_playing(&self) -> bool {
        self.preview_playing.load(Ordering::Relaxed)
    }

    /// Get duration of loaded trace in milliseconds
    pub fn trace_duration_ms(&self) -> f64 {
        self.current_trace
            .read()
            .as_ref()
            .map(|t| t.total_duration_ms)
            .unwrap_or(0.0)
    }

    /// Get events at current preview position
    pub fn current_events(&self) -> Vec<TimedStageEvent> {
        let pos = self.preview_position();
        self.current_trace
            .read()
            .as_ref()
            .map(|t| t.events_at(pos).into_iter().cloned().collect())
            .unwrap_or_default()
    }

    /// Get current stage at preview position
    pub fn current_stage(&self) -> Option<TimedStageEvent> {
        let pos = self.preview_position();
        self.current_trace
            .read()
            .as_ref()
            .and_then(|t| t.stage_at(pos))
            .cloned()
    }

    /// Update preview position from playback engine
    /// Called periodically during preview playback
    pub fn update_preview(&self) {
        if !self.is_preview_playing() {
            return;
        }

        // Sync position from playback engine
        let samples = self.playback.position.samples();
        let ms = self.samples_to_ms(samples);
        self.preview_position_ms
            .store(ms.to_bits(), Ordering::Relaxed);

        // Check for stage transitions and trigger cues
        let events = self.current_events();
        for timed_event in events {
            self.on_stage_event(&timed_event.event);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEFAULT CUE TEMPLATES
// ═══════════════════════════════════════════════════════════════════════════

impl StageAudioEngine {
    /// Create default cue templates for common slot game events
    pub fn create_default_slot_cues(&self) {
        // Spin start
        self.add_cue(StageCue {
            stage_trigger: "spin_start".to_string(),
            audio_path: "sounds/spin_start.wav".to_string(),
            volume: 0.8,
            ..Default::default()
        });

        // Reel stops (5 reels)
        for i in 0..5 {
            self.add_cue(StageCue {
                stage_trigger: "reel_stop".to_string(),
                stage_index: Some(i),
                audio_path: format!("sounds/reel_stop_{}.wav", i),
                volume: 0.7,
                delay_ms: i as f64 * 50.0, // Staggered by 50ms
                ..Default::default()
            });
        }

        // Win stages
        self.add_cue(StageCue {
            stage_trigger: "small_win".to_string(),
            audio_path: "sounds/win_small.wav".to_string(),
            volume: 0.6,
            ..Default::default()
        });

        self.add_cue(StageCue {
            stage_trigger: "medium_win".to_string(),
            audio_path: "sounds/win_medium.wav".to_string(),
            volume: 0.8,
            ..Default::default()
        });

        self.add_cue(StageCue {
            stage_trigger: "big_win".to_string(),
            audio_path: "sounds/win_big.wav".to_string(),
            volume: 1.0,
            ..Default::default()
        });

        // Feature stages
        self.add_cue(StageCue {
            stage_trigger: "free_spins_trigger".to_string(),
            audio_path: "sounds/feature_trigger.wav".to_string(),
            volume: 1.0,
            ..Default::default()
        });

        self.add_cue(StageCue {
            stage_trigger: "bonus_trigger".to_string(),
            audio_path: "sounds/bonus_trigger.wav".to_string(),
            volume: 1.0,
            ..Default::default()
        });

        log::info!("[StageAudio] Created default slot cue templates");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cue_management() {
        // Create mock playback and track manager
        let track_manager = Arc::new(TrackManager::new());
        let playback = Arc::new(PlaybackEngine::new(Arc::clone(&track_manager), 48000));
        let engine = StageAudioEngine::new(playback, track_manager, 48000);

        // Add cue
        let cue = StageCue {
            stage_trigger: "spin_start".to_string(),
            audio_path: "test.wav".to_string(),
            ..Default::default()
        };
        let id = engine.add_cue(cue);
        assert!(id > 0);

        // Get cues
        let cues = engine.get_cues("spin_start");
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].audio_path, "test.wav");

        // Remove cue
        assert!(engine.remove_cue(id));
        assert!(engine.get_cues("spin_start").is_empty());
    }

    #[test]
    fn test_ms_to_samples_conversion() {
        let track_manager = Arc::new(TrackManager::new());
        let playback = Arc::new(PlaybackEngine::new(Arc::clone(&track_manager), 48000));
        let engine = StageAudioEngine::new(playback, track_manager, 48000);

        // 1000ms = 48000 samples at 48kHz
        assert_eq!(engine.ms_to_samples(1000.0), 48000);
        assert_eq!(engine.ms_to_samples(500.0), 24000);

        // Reverse conversion
        assert!((engine.samples_to_ms(48000) - 1000.0).abs() < 0.001);
    }
}

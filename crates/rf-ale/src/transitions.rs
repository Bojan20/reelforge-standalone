//! Transition System
//!
//! Smooth, musical transitions between layers with:
//! - Sync modes (immediate, beat, bar, phrase, next_downbeat, custom)
//! - Fade curves (10 types)
//! - Crossfade overlap
//! - Ducking integration

use crate::context::LayerId;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Sync mode for transitions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum SyncMode {
    /// Start immediately
    #[default]
    Immediate,
    /// Start on next beat
    Beat,
    /// Start on next bar
    Bar,
    /// Start on next phrase (4 bars)
    Phrase,
    /// Start on next downbeat (beat 1)
    NextDownbeat,
    /// Custom grid position
    Custom,
}


/// Fade curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum FadeCurve {
    /// Linear fade
    Linear,
    /// Quadratic ease-in (slow start)
    EaseInQuad,
    /// Quadratic ease-out (slow end)
    #[default]
    EaseOutQuad,
    /// Quadratic ease-in-out
    EaseInOutQuad,
    /// Cubic ease-in
    EaseInCubic,
    /// Cubic ease-out
    EaseOutCubic,
    /// Cubic ease-in-out
    EaseInOutCubic,
    /// Exponential ease-in
    EaseInExpo,
    /// Exponential ease-out
    EaseOutExpo,
    /// S-curve (sine-based)
    SCurve,
}


impl FadeCurve {
    /// Apply the curve to a linear progress value (0.0-1.0)
    #[inline]
    pub fn apply(&self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);

        match self {
            FadeCurve::Linear => t,
            FadeCurve::EaseInQuad => t * t,
            FadeCurve::EaseOutQuad => 1.0 - (1.0 - t) * (1.0 - t),
            FadeCurve::EaseInOutQuad => {
                if t < 0.5 {
                    2.0 * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(2) / 2.0
                }
            }
            FadeCurve::EaseInCubic => t * t * t,
            FadeCurve::EaseOutCubic => 1.0 - (1.0 - t).powi(3),
            FadeCurve::EaseInOutCubic => {
                if t < 0.5 {
                    4.0 * t * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
                }
            }
            FadeCurve::EaseInExpo => {
                if t == 0.0 {
                    0.0
                } else {
                    (2.0_f32).powf(10.0 * t - 10.0)
                }
            }
            FadeCurve::EaseOutExpo => {
                if t == 1.0 {
                    1.0
                } else {
                    1.0 - (2.0_f32).powf(-10.0 * t)
                }
            }
            FadeCurve::SCurve => {
                // Sine-based S-curve
                (1.0 - (t * std::f32::consts::PI).cos()) / 2.0
            }
        }
    }
}

/// Fade configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FadeConfig {
    /// Fade duration in milliseconds
    #[serde(default = "default_fade_duration")]
    pub duration_ms: u32,
    /// Fade curve
    #[serde(default)]
    pub curve: FadeCurve,
}

fn default_fade_duration() -> u32 {
    300
}

impl Default for FadeConfig {
    fn default() -> Self {
        Self {
            duration_ms: 300,
            curve: FadeCurve::EaseOutQuad,
        }
    }
}

impl FadeConfig {
    /// Create a new fade config
    pub fn new(duration_ms: u32, curve: FadeCurve) -> Self {
        Self { duration_ms, curve }
    }
}

/// Ducking configuration for transitions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuckingConfig {
    /// Whether ducking is enabled
    #[serde(default)]
    pub enabled: bool,
    /// Bus to duck (e.g., "SFX", "VO")
    #[serde(default)]
    pub target_bus: String,
    /// Duck amount in dB
    #[serde(default = "default_duck_db")]
    pub duck_db: f32,
    /// Duck attack time (ms)
    #[serde(default = "default_duck_attack")]
    pub attack_ms: u32,
    /// Duck release time (ms)
    #[serde(default = "default_duck_release")]
    pub release_ms: u32,
}

fn default_duck_db() -> f32 {
    -6.0
}
fn default_duck_attack() -> u32 {
    50
}
fn default_duck_release() -> u32 {
    200
}

impl Default for DuckingConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            target_bus: String::new(),
            duck_db: -6.0,
            attack_ms: 50,
            release_ms: 200,
        }
    }
}

/// Complete transition profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransitionProfile {
    /// Profile identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Sync mode
    #[serde(default)]
    pub sync_mode: SyncMode,
    /// Maximum wait time for sync (ms)
    #[serde(default = "default_max_wait")]
    pub max_wait_ms: u32,
    /// Custom grid beats (for Custom sync mode)
    #[serde(default)]
    pub custom_grid_beats: Option<f32>,
    /// Fade-in configuration
    #[serde(default)]
    pub fade_in: FadeConfig,
    /// Fade-out configuration
    #[serde(default)]
    pub fade_out: FadeConfig,
    /// Overlap duration (ms) - how long both layers play together
    #[serde(default = "default_overlap")]
    pub overlap_ms: u32,
    /// Ducking configuration
    #[serde(default)]
    pub ducking: DuckingConfig,
}

fn default_max_wait() -> u32 {
    500
}
fn default_overlap() -> u32 {
    100
}

impl Default for TransitionProfile {
    fn default() -> Self {
        Self {
            id: "default".to_string(),
            name: "Default Transition".to_string(),
            sync_mode: SyncMode::Immediate,
            max_wait_ms: 500,
            custom_grid_beats: None,
            fade_in: FadeConfig::default(),
            fade_out: FadeConfig::default(),
            overlap_ms: 100,
            ducking: DuckingConfig::default(),
        }
    }
}

impl TransitionProfile {
    /// Create a new transition profile
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            ..Default::default()
        }
    }

    /// Create an upshift (energetic) transition
    pub fn upshift_energetic() -> Self {
        Self {
            id: "upshift_energetic".to_string(),
            name: "Upshift Energetic".to_string(),
            sync_mode: SyncMode::Beat,
            max_wait_ms: 500,
            custom_grid_beats: None,
            fade_in: FadeConfig::new(250, FadeCurve::EaseOutQuad),
            fade_out: FadeConfig::new(200, FadeCurve::EaseInQuad),
            overlap_ms: 100,
            ducking: DuckingConfig {
                enabled: true,
                target_bus: "SFX".to_string(),
                duck_db: -4.0,
                ..Default::default()
            },
        }
    }

    /// Create a downshift (smooth) transition
    pub fn downshift_smooth() -> Self {
        Self {
            id: "downshift_smooth".to_string(),
            name: "Downshift Smooth".to_string(),
            sync_mode: SyncMode::Bar,
            max_wait_ms: 1000,
            custom_grid_beats: None,
            fade_in: FadeConfig::new(500, FadeCurve::EaseInOutQuad),
            fade_out: FadeConfig::new(600, FadeCurve::EaseInOutQuad),
            overlap_ms: 300,
            ducking: DuckingConfig::default(),
        }
    }

    /// Create a feature entry transition
    pub fn feature_enter() -> Self {
        Self {
            id: "feature_enter".to_string(),
            name: "Feature Enter".to_string(),
            sync_mode: SyncMode::NextDownbeat,
            max_wait_ms: 2000,
            custom_grid_beats: None,
            fade_in: FadeConfig::new(400, FadeCurve::EaseOutExpo),
            fade_out: FadeConfig::new(300, FadeCurve::EaseInQuad),
            overlap_ms: 200,
            ducking: DuckingConfig {
                enabled: true,
                target_bus: "SFX".to_string(),
                duck_db: -8.0,
                ..Default::default()
            },
        }
    }

    /// Create a feature exit transition
    pub fn feature_exit() -> Self {
        Self {
            id: "feature_exit".to_string(),
            name: "Feature Exit".to_string(),
            sync_mode: SyncMode::Phrase,
            max_wait_ms: 4000,
            custom_grid_beats: None,
            fade_in: FadeConfig::new(1000, FadeCurve::SCurve),
            fade_out: FadeConfig::new(1500, FadeCurve::SCurve),
            overlap_ms: 500,
            ducking: DuckingConfig::default(),
        }
    }

    /// Calculate sync delay based on musical position
    pub fn calculate_sync_delay(
        &self,
        current_beat_position: f32,
        beats_per_bar: u8,
        beat_duration_ms: f32,
    ) -> u32 {
        match self.sync_mode {
            SyncMode::Immediate => 0,
            SyncMode::Beat => {
                let beats_to_next = 1.0 - (current_beat_position % 1.0);
                let delay = (beats_to_next * beat_duration_ms) as u32;
                delay.min(self.max_wait_ms)
            }
            SyncMode::Bar => {
                let beat_in_bar = current_beat_position % beats_per_bar as f32;
                let beats_to_next_bar = beats_per_bar as f32 - beat_in_bar;
                let delay = (beats_to_next_bar * beat_duration_ms) as u32;
                delay.min(self.max_wait_ms)
            }
            SyncMode::Phrase => {
                // Phrase = 4 bars
                let phrase_beats = beats_per_bar as f32 * 4.0;
                let beat_in_phrase = current_beat_position % phrase_beats;
                let beats_to_next_phrase = phrase_beats - beat_in_phrase;
                let delay = (beats_to_next_phrase * beat_duration_ms) as u32;
                delay.min(self.max_wait_ms)
            }
            SyncMode::NextDownbeat => {
                let beat_in_bar = current_beat_position % beats_per_bar as f32;
                let beats_to_downbeat = if beat_in_bar < 0.01 {
                    0.0
                } else {
                    beats_per_bar as f32 - beat_in_bar
                };
                let delay = (beats_to_downbeat * beat_duration_ms) as u32;
                delay.min(self.max_wait_ms)
            }
            SyncMode::Custom => {
                if let Some(grid) = self.custom_grid_beats {
                    let beat_in_grid = current_beat_position % grid;
                    let beats_to_next = grid - beat_in_grid;
                    let delay = (beats_to_next * beat_duration_ms) as u32;
                    delay.min(self.max_wait_ms)
                } else {
                    0
                }
            }
        }
    }
}

/// Active transition state
#[derive(Debug, Clone)]
pub struct ActiveTransition {
    /// Source layer
    pub from_level: LayerId,
    /// Target layer
    pub to_level: LayerId,
    /// Transition profile
    pub profile: TransitionProfile,
    /// Start time (ms since engine start)
    pub start_time_ms: u64,
    /// Whether transition has started (after sync delay)
    pub started: bool,
    /// Sync delay (ms)
    pub sync_delay_ms: u32,
    /// Current progress (0.0-1.0)
    pub progress: f32,
    /// Phase (0 = waiting for sync, 1 = fade out old, 2 = crossfade, 3 = fade in new)
    pub phase: TransitionPhase,
}

/// Transition phase
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransitionPhase {
    /// Waiting for musical sync point
    WaitingForSync,
    /// Fading out old layer
    FadeOut,
    /// Crossfade (both playing)
    Crossfade,
    /// Fading in new layer
    FadeIn,
    /// Transition complete
    Complete,
}

impl ActiveTransition {
    /// Create a new active transition
    pub fn new(
        from_level: LayerId,
        to_level: LayerId,
        profile: TransitionProfile,
        current_time_ms: u64,
        sync_delay_ms: u32,
    ) -> Self {
        let phase = if sync_delay_ms > 0 {
            TransitionPhase::WaitingForSync
        } else {
            TransitionPhase::FadeOut
        };

        Self {
            from_level,
            to_level,
            profile,
            start_time_ms: current_time_ms,
            started: sync_delay_ms == 0,
            sync_delay_ms,
            progress: 0.0,
            phase,
        }
    }

    /// Update transition state
    pub fn update(&mut self, current_time_ms: u64) {
        let elapsed = current_time_ms.saturating_sub(self.start_time_ms) as u32;

        // Check if sync delay has passed
        if !self.started {
            if elapsed >= self.sync_delay_ms {
                self.started = true;
                self.start_time_ms = current_time_ms;
                self.phase = TransitionPhase::FadeOut;
            }
            return;
        }

        let elapsed_after_start = current_time_ms.saturating_sub(self.start_time_ms) as u32;
        let fade_out_end = self.profile.fade_out.duration_ms;
        let crossfade_end = fade_out_end + self.profile.overlap_ms;
        let fade_in_end = crossfade_end + self.profile.fade_in.duration_ms;

        if elapsed_after_start < fade_out_end {
            self.phase = TransitionPhase::FadeOut;
            self.progress = elapsed_after_start as f32 / fade_out_end as f32;
        } else if elapsed_after_start < crossfade_end {
            self.phase = TransitionPhase::Crossfade;
            let crossfade_elapsed = elapsed_after_start - fade_out_end;
            self.progress = crossfade_elapsed as f32 / self.profile.overlap_ms as f32;
        } else if elapsed_after_start < fade_in_end {
            self.phase = TransitionPhase::FadeIn;
            let fade_in_elapsed = elapsed_after_start - crossfade_end;
            self.progress = fade_in_elapsed as f32 / self.profile.fade_in.duration_ms as f32;
        } else {
            self.phase = TransitionPhase::Complete;
            self.progress = 1.0;
        }
    }

    /// Get volume for the source (from) layer
    pub fn from_volume(&self) -> f32 {
        match self.phase {
            TransitionPhase::WaitingForSync => 1.0,
            TransitionPhase::FadeOut => {
                let curve_value = self.profile.fade_out.curve.apply(self.progress);
                1.0 - curve_value
            }
            TransitionPhase::Crossfade => {
                // During crossfade, old layer is at reduced volume
                let overlap_progress = self.progress;
                0.3 * (1.0 - overlap_progress) // Fade from 0.3 to 0
            }
            TransitionPhase::FadeIn | TransitionPhase::Complete => 0.0,
        }
    }

    /// Get volume for the target (to) layer
    pub fn to_volume(&self) -> f32 {
        match self.phase {
            TransitionPhase::WaitingForSync | TransitionPhase::FadeOut => 0.0,
            TransitionPhase::Crossfade => {
                // During crossfade, new layer fades in
                let overlap_progress = self.progress;
                0.3 + 0.7 * overlap_progress // Fade from 0.3 to 1.0
            }
            TransitionPhase::FadeIn => {
                
                self.profile.fade_in.curve.apply(self.progress)
            }
            TransitionPhase::Complete => 1.0,
        }
    }

    /// Check if transition is complete
    pub fn is_complete(&self) -> bool {
        self.phase == TransitionPhase::Complete
    }

    /// Get total transition duration (ms)
    pub fn total_duration_ms(&self) -> u32 {
        self.sync_delay_ms
            + self.profile.fade_out.duration_ms
            + self.profile.overlap_ms
            + self.profile.fade_in.duration_ms
    }
}

/// Transition profile registry
#[derive(Debug, Clone, Default)]
pub struct TransitionRegistry {
    profiles: HashMap<String, TransitionProfile>,
}

impl TransitionRegistry {
    pub fn new() -> Self {
        Self {
            profiles: HashMap::new(),
        }
    }

    /// Create registry with built-in profiles
    pub fn with_builtins() -> Self {
        let mut registry = Self::new();

        registry.register(TransitionProfile::default());
        registry.register(TransitionProfile::upshift_energetic());
        registry.register(TransitionProfile::downshift_smooth());
        registry.register(TransitionProfile::feature_enter());
        registry.register(TransitionProfile::feature_exit());

        registry
    }

    /// Register a transition profile
    pub fn register(&mut self, profile: TransitionProfile) {
        self.profiles.insert(profile.id.clone(), profile);
    }

    /// Get a profile by ID
    pub fn get(&self, id: &str) -> Option<&TransitionProfile> {
        self.profiles.get(id)
    }

    /// Get default profile
    pub fn default_profile(&self) -> &TransitionProfile {
        self.profiles
            .get("default")
            .unwrap_or_else(|| self.profiles.values().next().unwrap())
    }

    /// List all profile IDs
    pub fn profile_ids(&self) -> impl Iterator<Item = &str> {
        self.profiles.keys().map(|s| s.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fade_curves() {
        // All curves should map 0 -> 0 and 1 -> 1
        let curves = [
            FadeCurve::Linear,
            FadeCurve::EaseInQuad,
            FadeCurve::EaseOutQuad,
            FadeCurve::EaseInOutQuad,
            FadeCurve::EaseInCubic,
            FadeCurve::EaseOutCubic,
            FadeCurve::EaseInOutCubic,
            FadeCurve::EaseInExpo,
            FadeCurve::EaseOutExpo,
            FadeCurve::SCurve,
        ];

        for curve in curves {
            assert!(curve.apply(0.0).abs() < 0.01, "Curve {:?} at 0.0", curve);
            assert!(
                (curve.apply(1.0) - 1.0).abs() < 0.01,
                "Curve {:?} at 1.0",
                curve
            );
        }
    }

    #[test]
    fn test_sync_delay_beat() {
        let profile = TransitionProfile {
            sync_mode: SyncMode::Beat,
            max_wait_ms: 1000,
            ..Default::default()
        };

        // Beat duration 500ms, currently at beat 0.5
        let delay = profile.calculate_sync_delay(0.5, 4, 500.0);
        assert_eq!(delay, 250); // 0.5 beats * 500ms

        // Currently at beat 0.9
        let delay = profile.calculate_sync_delay(0.9, 4, 500.0);
        assert_eq!(delay, 50); // 0.1 beats * 500ms
    }

    #[test]
    fn test_sync_delay_bar() {
        let profile = TransitionProfile {
            sync_mode: SyncMode::Bar,
            max_wait_ms: 3000,
            ..Default::default()
        };

        // 4/4 time, beat duration 500ms, currently at beat 1.0 (second beat)
        let delay = profile.calculate_sync_delay(1.0, 4, 500.0);
        assert_eq!(delay, 1500); // 3 beats * 500ms
    }

    #[test]
    fn test_active_transition_phases() {
        let profile = TransitionProfile {
            fade_out: FadeConfig::new(100, FadeCurve::Linear),
            fade_in: FadeConfig::new(100, FadeCurve::Linear),
            overlap_ms: 50,
            ..Default::default()
        };

        let mut transition = ActiveTransition::new(0, 1, profile, 0, 0);

        // Initially in FadeOut
        assert_eq!(transition.phase, TransitionPhase::FadeOut);

        // At 50ms (half fade out)
        transition.update(50);
        assert_eq!(transition.phase, TransitionPhase::FadeOut);
        assert!((transition.progress - 0.5).abs() < 0.01);

        // At 100ms (end fade out, start crossfade)
        transition.update(100);
        assert_eq!(transition.phase, TransitionPhase::Crossfade);

        // At 150ms (end crossfade, start fade in)
        transition.update(150);
        assert_eq!(transition.phase, TransitionPhase::FadeIn);

        // At 250ms (complete)
        transition.update(250);
        assert_eq!(transition.phase, TransitionPhase::Complete);
        assert!(transition.is_complete());
    }

    #[test]
    fn test_transition_volumes() {
        let profile = TransitionProfile {
            fade_out: FadeConfig::new(100, FadeCurve::Linear),
            fade_in: FadeConfig::new(100, FadeCurve::Linear),
            overlap_ms: 0,
            ..Default::default()
        };

        let mut transition = ActiveTransition::new(0, 1, profile, 0, 0);

        // At start
        transition.update(0);
        assert!((transition.from_volume() - 1.0).abs() < 0.01);
        assert!((transition.to_volume() - 0.0).abs() < 0.01);

        // Half fade out
        transition.update(50);
        assert!((transition.from_volume() - 0.5).abs() < 0.01);

        // Complete
        transition.update(200);
        assert!((transition.from_volume() - 0.0).abs() < 0.01);
        assert!((transition.to_volume() - 1.0).abs() < 0.01);
    }
}

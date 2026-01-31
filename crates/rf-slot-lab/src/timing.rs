//! Timing profiles for stage event generation

use serde::{Deserialize, Serialize};

/// Timing profile for stage events
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum TimingProfile {
    /// Normal gameplay timing
    Normal,
    /// Fast/Turbo mode
    Turbo,
    /// Mobile optimized (slightly faster)
    Mobile,
    /// Studio mode (instant for testing)
    Studio,
    /// Custom timing multiplier
    Custom,
}

impl Default for TimingProfile {
    fn default() -> Self {
        Self::Normal
    }
}

/// Anticipation TIMING configuration for industry-standard anticipation system
/// NOTE: This handles timing/effects parameters. For trigger rules (which symbols,
/// which reels), see `AnticipationConfig` in config.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnticipationTimingConfig {
    /// Minimum scatter symbols needed to trigger anticipation (default: 2)
    pub min_scatters_to_trigger: u8,

    /// Duration per reel in anticipation (ms) — each reel gets this much time
    pub duration_per_reel_ms: f64,

    /// Base intensity multiplier for visual/audio effects (0.0-1.0)
    pub base_intensity: f64,

    /// Escalation factor per tension level (multiplied for each level)
    pub escalation_factor: f64,

    /// Number of tension layers (typically 4: L1-L4)
    pub tension_layer_count: u8,

    /// Speed multiplier when in anticipation (0.3 = 30% of normal speed)
    pub speed_multiplier: f64,

    /// Audio pre-trigger offset (ms) — audio starts this much before visual
    pub audio_pre_trigger_ms: f64,

    /// Whether to enable per-reel color progression
    pub enable_color_progression: bool,

    /// Whether to enable particle effects
    pub enable_particles: bool,

    /// Whether to enable screen vignette darkening
    pub enable_vignette: bool,
}

impl Default for AnticipationTimingConfig {
    fn default() -> Self {
        Self {
            min_scatters_to_trigger: 2,
            duration_per_reel_ms: 1500.0,
            base_intensity: 0.7,
            escalation_factor: 1.15,
            tension_layer_count: 4,
            speed_multiplier: 0.3,
            audio_pre_trigger_ms: 50.0,
            enable_color_progression: true,
            enable_particles: true,
            enable_vignette: true,
        }
    }
}

impl AnticipationTimingConfig {
    /// Normal gameplay anticipation config
    pub fn normal() -> Self {
        Self::default()
    }

    /// Turbo mode — faster anticipation
    pub fn turbo() -> Self {
        Self {
            duration_per_reel_ms: 800.0,
            audio_pre_trigger_ms: 30.0,
            ..Self::default()
        }
    }

    /// Mobile optimized — slightly faster, fewer effects
    pub fn mobile() -> Self {
        Self {
            duration_per_reel_ms: 1000.0,
            audio_pre_trigger_ms: 40.0,
            enable_particles: false, // Save GPU on mobile
            ..Self::default()
        }
    }

    /// Studio mode — longer for testing/debugging
    pub fn studio() -> Self {
        Self {
            duration_per_reel_ms: 2000.0,
            audio_pre_trigger_ms: 30.0,
            ..Self::default()
        }
    }

    /// High tension mode — more dramatic escalation
    pub fn high_tension() -> Self {
        Self {
            base_intensity: 0.8,
            escalation_factor: 1.25,
            duration_per_reel_ms: 2000.0,
            ..Self::default()
        }
    }

    /// Calculate tension level for a given reel position in anticipation sequence
    pub fn tension_level_for_position(&self, position: usize) -> u8 {
        ((position + 1) as u8).min(self.tension_layer_count)
    }

    /// Calculate intensity for a given tension level
    pub fn intensity_for_tension(&self, tension_level: u8) -> f64 {
        let level = tension_level.min(self.tension_layer_count) as f64;
        self.base_intensity * self.escalation_factor.powf(level - 1.0)
    }

    /// Calculate total anticipation duration for N reels
    pub fn total_duration_for_reels(&self, reel_count: u8) -> f64 {
        self.duration_per_reel_ms * reel_count as f64
    }

    /// Get color for tension level (Gold → Orange → Red-Orange → Red)
    pub fn color_for_tension(&self, tension_level: u8) -> (u8, u8, u8) {
        if !self.enable_color_progression {
            return (255, 215, 0); // Gold always
        }
        match tension_level {
            1 => (255, 215, 0),   // Gold #FFD700
            2 => (255, 165, 0),   // Orange #FFA500
            3 => (255, 99, 71),   // Red-Orange #FF6347
            _ => (255, 69, 0),    // Red #FF4500
        }
    }

    /// Get volume multiplier for tension level
    pub fn volume_for_tension(&self, tension_level: u8) -> f64 {
        0.5 + (tension_level.min(self.tension_layer_count) as f64 * 0.1)
    }

    /// Get pitch semitones for tension level
    pub fn pitch_semitones_for_tension(&self, tension_level: u8) -> f64 {
        tension_level.min(self.tension_layer_count) as f64
    }
}

/// Detailed timing configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimingConfig {
    /// Profile type
    pub profile: TimingProfile,

    /// Time for each reel to spin before stopping (ms)
    pub reel_spin_duration_ms: f64,

    /// Delay between reel stops (ms)
    pub reel_stop_interval_ms: f64,

    /// Anticipation duration per reel (ms)
    pub anticipation_duration_ms: f64,

    /// Delay before win presentation (ms)
    pub win_reveal_delay_ms: f64,

    /// Duration per win line highlight (ms)
    pub win_line_duration_ms: f64,

    /// Rollup speed (credits per second)
    pub rollup_speed: f64,

    /// Big win celebration base duration (ms)
    pub big_win_base_duration_ms: f64,

    /// Feature enter transition (ms)
    pub feature_enter_duration_ms: f64,

    /// Cascade step duration (ms)
    pub cascade_step_duration_ms: f64,

    /// Minimum time between stage events (ms)
    pub min_event_interval_ms: f64,

    // ═══════════════════════════════════════════════════════════════════════════
    // AUDIO LATENCY COMPENSATION
    // ═══════════════════════════════════════════════════════════════════════════
    /// Audio buffer latency compensation (ms)
    /// Accounts for audio engine buffer size delay
    /// Typical values: 128 samples @ 44.1kHz ≈ 3ms, 256 samples ≈ 6ms
    #[serde(default)]
    pub audio_latency_compensation_ms: f64,

    /// Visual-to-audio sync offset (ms)
    /// Positive = audio plays later, Negative = audio plays earlier
    /// Used for fine-tuning when audio should hit relative to visual
    #[serde(default)]
    pub visual_audio_sync_offset_ms: f64,

    /// Pre-trigger offset for anticipation audio (ms)
    /// Audio starts this much before the visual anticipation begins
    #[serde(default)]
    pub anticipation_audio_pre_trigger_ms: f64,

    /// Pre-trigger offset for reel stop audio (ms)
    /// Audio starts this much before the reel visually stops
    #[serde(default)]
    pub reel_stop_audio_pre_trigger_ms: f64,

    // ═══════════════════════════════════════════════════════════════════════════
    // ANTICIPATION CONFIGURATION (P2.4)
    // ═══════════════════════════════════════════════════════════════════════════
    /// Full anticipation configuration for industry-standard anticipation system
    #[serde(default)]
    pub anticipation_timing: AnticipationTimingConfig,
}

impl TimingConfig {
    /// Normal gameplay timing
    pub fn normal() -> Self {
        Self {
            profile: TimingProfile::Normal,
            reel_spin_duration_ms: 800.0,
            reel_stop_interval_ms: 300.0,
            anticipation_duration_ms: 1500.0,
            win_reveal_delay_ms: 200.0,
            win_line_duration_ms: 500.0,
            rollup_speed: 50.0,
            big_win_base_duration_ms: 3000.0,
            feature_enter_duration_ms: 2000.0,
            cascade_step_duration_ms: 600.0,
            min_event_interval_ms: 50.0,
            // Audio latency compensation - normal has conservative defaults
            audio_latency_compensation_ms: 5.0,
            visual_audio_sync_offset_ms: 0.0,
            anticipation_audio_pre_trigger_ms: 50.0,
            reel_stop_audio_pre_trigger_ms: 20.0,
            // Anticipation config
            anticipation_timing: AnticipationTimingConfig::normal(),
        }
    }

    /// Turbo mode
    pub fn turbo() -> Self {
        Self {
            profile: TimingProfile::Turbo,
            reel_spin_duration_ms: 400.0,
            reel_stop_interval_ms: 100.0,
            anticipation_duration_ms: 800.0,
            win_reveal_delay_ms: 100.0,
            win_line_duration_ms: 200.0,
            rollup_speed: 200.0,
            big_win_base_duration_ms: 1500.0,
            feature_enter_duration_ms: 1000.0,
            cascade_step_duration_ms: 300.0,
            min_event_interval_ms: 25.0,
            // Turbo mode - tighter timing, less compensation needed
            audio_latency_compensation_ms: 3.0,
            visual_audio_sync_offset_ms: 0.0,
            anticipation_audio_pre_trigger_ms: 30.0,
            reel_stop_audio_pre_trigger_ms: 10.0,
            // Anticipation config
            anticipation_timing: AnticipationTimingConfig::turbo(),
        }
    }

    /// Mobile optimized
    pub fn mobile() -> Self {
        Self {
            profile: TimingProfile::Mobile,
            reel_spin_duration_ms: 600.0,
            reel_stop_interval_ms: 200.0,
            anticipation_duration_ms: 1000.0,
            win_reveal_delay_ms: 150.0,
            win_line_duration_ms: 350.0,
            rollup_speed: 100.0,
            big_win_base_duration_ms: 2000.0,
            feature_enter_duration_ms: 1500.0,
            cascade_step_duration_ms: 450.0,
            min_event_interval_ms: 30.0,
            // Mobile - account for potentially higher latency
            audio_latency_compensation_ms: 8.0,
            visual_audio_sync_offset_ms: 0.0,
            anticipation_audio_pre_trigger_ms: 40.0,
            reel_stop_audio_pre_trigger_ms: 15.0,
            // Anticipation config
            anticipation_timing: AnticipationTimingConfig::mobile(),
        }
    }

    /// Studio mode (optimized for audio testing - visible reel stops with good sync)
    /// CRITICAL: These values MUST match premium_slot_preview.dart visual animation!
    /// Visual formula: stopTime = 1000 + i * 370 (baseAnimDuration + i * (staggerDelay + baseDelay))
    pub fn studio() -> Self {
        Self {
            profile: TimingProfile::Studio,
            reel_spin_duration_ms: 1000.0, // Matches visual: first reel stops at 1000ms
            reel_stop_interval_ms: 370.0,  // Matches visual: 120ms stagger + 250ms base delay
            anticipation_duration_ms: 500.0,
            win_reveal_delay_ms: 100.0,
            win_line_duration_ms: 200.0,
            rollup_speed: 500.0,
            big_win_base_duration_ms: 1000.0,
            feature_enter_duration_ms: 500.0,
            cascade_step_duration_ms: 300.0,
            min_event_interval_ms: 50.0,  // Minimum gap za audio playback latency
            // Studio - precise timing for audio production
            audio_latency_compensation_ms: 3.0,  // Low latency for pro audio setup
            visual_audio_sync_offset_ms: 0.0,
            anticipation_audio_pre_trigger_ms: 30.0,
            reel_stop_audio_pre_trigger_ms: 15.0,
            // Anticipation config
            anticipation_timing: AnticipationTimingConfig::studio(),
        }
    }

    /// Get config for profile
    pub fn from_profile(profile: TimingProfile) -> Self {
        match profile {
            TimingProfile::Normal => Self::normal(),
            TimingProfile::Turbo => Self::turbo(),
            TimingProfile::Mobile => Self::mobile(),
            TimingProfile::Studio => Self::studio(),
            TimingProfile::Custom => Self::normal(),
        }
    }

    /// Scale timing by factor (< 1.0 = faster)
    pub fn scaled(&self, factor: f64) -> Self {
        Self {
            profile: TimingProfile::Custom,
            reel_spin_duration_ms: self.reel_spin_duration_ms * factor,
            reel_stop_interval_ms: self.reel_stop_interval_ms * factor,
            anticipation_duration_ms: self.anticipation_duration_ms * factor,
            win_reveal_delay_ms: self.win_reveal_delay_ms * factor,
            win_line_duration_ms: self.win_line_duration_ms * factor,
            rollup_speed: self.rollup_speed / factor,
            big_win_base_duration_ms: self.big_win_base_duration_ms * factor,
            feature_enter_duration_ms: self.feature_enter_duration_ms * factor,
            cascade_step_duration_ms: self.cascade_step_duration_ms * factor,
            min_event_interval_ms: self.min_event_interval_ms * factor,
            // Audio latency compensation is NOT scaled - it's hardware dependent
            audio_latency_compensation_ms: self.audio_latency_compensation_ms,
            visual_audio_sync_offset_ms: self.visual_audio_sync_offset_ms,
            anticipation_audio_pre_trigger_ms: self.anticipation_audio_pre_trigger_ms,
            reel_stop_audio_pre_trigger_ms: self.reel_stop_audio_pre_trigger_ms,
            // Scale anticipation duration but keep other config intact
            anticipation_timing: AnticipationTimingConfig {
                duration_per_reel_ms: self.anticipation_timing.duration_per_reel_ms * factor,
                ..self.anticipation_timing.clone()
            },
        }
    }

    /// Get total audio latency offset (compensation + sync)
    pub fn total_audio_offset(&self) -> f64 {
        self.audio_latency_compensation_ms + self.visual_audio_sync_offset_ms
    }

    /// Get adjusted timestamp for audio trigger
    /// Returns the timestamp at which audio should be triggered to hit the visual event
    pub fn audio_trigger_time(&self, visual_timestamp_ms: f64, pre_trigger_ms: f64) -> f64 {
        (visual_timestamp_ms - self.total_audio_offset() - pre_trigger_ms).max(0.0)
    }

    /// Get audio trigger time for reel stop event
    pub fn reel_stop_audio_time(&self, visual_timestamp_ms: f64) -> f64 {
        self.audio_trigger_time(visual_timestamp_ms, self.reel_stop_audio_pre_trigger_ms)
    }

    /// Get audio trigger time for anticipation event
    pub fn anticipation_audio_time(&self, visual_timestamp_ms: f64) -> f64 {
        self.audio_trigger_time(visual_timestamp_ms, self.anticipation_audio_pre_trigger_ms)
    }

    /// Calculate total spin duration (all reels stopping)
    pub fn total_spin_duration(&self, reel_count: u8) -> f64 {
        self.reel_spin_duration_ms + (reel_count as f64 - 1.0) * self.reel_stop_interval_ms
    }

    /// Calculate rollup duration for an amount
    pub fn rollup_duration(&self, amount: f64) -> f64 {
        if self.rollup_speed <= 0.0 {
            return 0.0;
        }
        (amount / self.rollup_speed * 1000.0).max(500.0).min(10000.0)
    }

    /// Calculate big win celebration duration
    pub fn big_win_duration(&self, win_ratio: f64) -> f64 {
        // Longer celebration for bigger wins
        let tier_multiplier = match win_ratio {
            r if r >= 100.0 => 3.0,
            r if r >= 50.0 => 2.5,
            r if r >= 25.0 => 2.0,
            r if r >= 15.0 => 1.5,
            _ => 1.0,
        };
        self.big_win_base_duration_ms * tier_multiplier
    }
}

impl Default for TimingConfig {
    fn default() -> Self {
        Self::normal()
    }
}

/// Timestamp generator for sequential events
#[derive(Debug, Clone)]
pub struct TimestampGenerator {
    current_ms: f64,
    config: TimingConfig,
}

impl TimestampGenerator {
    /// Create new generator
    pub fn new(config: TimingConfig) -> Self {
        Self {
            current_ms: 0.0,
            config,
        }
    }

    /// Reset to zero
    pub fn reset(&mut self) {
        self.current_ms = 0.0;
    }

    /// Get current timestamp
    pub fn current(&self) -> f64 {
        self.current_ms
    }

    /// Advance by duration and return new timestamp
    pub fn advance(&mut self, duration_ms: f64) -> f64 {
        self.current_ms += duration_ms.max(self.config.min_event_interval_ms);
        self.current_ms
    }

    /// Advance for reel spin start
    pub fn reel_spin(&mut self, reel_index: u8) -> f64 {
        // All reels start together, so only advance on first reel
        if reel_index == 0 {
            self.advance(0.0)
        } else {
            self.current_ms
        }
    }

    /// Advance for reel stop
    pub fn reel_stop(&mut self, reel_index: u8) -> f64 {
        let advance_ms = if reel_index == 0 {
            self.config.reel_spin_duration_ms
        } else {
            self.config.reel_stop_interval_ms
        };
        let result = self.advance(advance_ms);
        log::debug!("[TimestampGenerator::reel_stop] reel={}, advance={}ms, result={}ms",
            reel_index, advance_ms, result);
        result
    }

    /// Advance for anticipation start
    pub fn anticipation_start(&mut self) -> f64 {
        self.current_ms // Same timestamp as reel would stop
    }

    /// Advance for anticipation end
    pub fn anticipation_end(&mut self) -> f64 {
        self.advance(self.config.anticipation_duration_ms)
    }

    /// Advance for win reveal
    pub fn win_reveal(&mut self) -> f64 {
        self.advance(self.config.win_reveal_delay_ms)
    }

    /// Advance for win line
    pub fn win_line(&mut self) -> f64 {
        self.advance(self.config.win_line_duration_ms)
    }

    /// Advance for rollup tick (returns multiple timestamps)
    pub fn rollup_ticks(&mut self, amount: f64, tick_count: u32) -> Vec<f64> {
        let total_duration = self.config.rollup_duration(amount);
        let tick_interval = total_duration / tick_count.max(1) as f64;

        (0..tick_count)
            .map(|_| self.advance(tick_interval))
            .collect()
    }

    /// Advance for feature enter
    pub fn feature_enter(&mut self) -> f64 {
        self.advance(self.config.feature_enter_duration_ms)
    }

    /// Advance for cascade step
    pub fn cascade_step(&mut self) -> f64 {
        self.advance(self.config.cascade_step_duration_ms)
    }

    /// Advance for big win celebration
    pub fn big_win(&mut self, win_ratio: f64) -> f64 {
        self.advance(self.config.big_win_duration(win_ratio))
    }

    /// Get timing config reference
    pub fn config(&self) -> &TimingConfig {
        &self.config
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_timing_profiles() {
        let normal = TimingConfig::normal();
        let turbo = TimingConfig::turbo();
        let mobile = TimingConfig::mobile();
        let studio = TimingConfig::studio();

        // Turbo is fastest gameplay mode
        assert!(turbo.reel_spin_duration_ms < normal.reel_spin_duration_ms);
        assert!(turbo.reel_spin_duration_ms < mobile.reel_spin_duration_ms);

        // Mobile is between turbo and normal
        assert!(mobile.reel_spin_duration_ms < normal.reel_spin_duration_ms);

        // Studio has longer spin for audio testing (intentionally slower)
        // This allows REEL_SPIN loop to be audible before stops
        assert!(studio.reel_spin_duration_ms > turbo.reel_spin_duration_ms);

        // Studio has wider reel stop intervals for audio sync testing
        assert!(studio.reel_stop_interval_ms > turbo.reel_stop_interval_ms);
    }

    #[test]
    fn test_timestamp_generator() {
        let config = TimingConfig::studio();
        let mut ts_gen = TimestampGenerator::new(config);

        assert_eq!(ts_gen.current(), 0.0);

        let t1 = ts_gen.reel_stop(0);
        assert!(t1 > 0.0);

        let t2 = ts_gen.reel_stop(1);
        assert!(t2 > t1);
    }

    #[test]
    fn test_rollup_duration() {
        let config = TimingConfig::normal();

        let small = config.rollup_duration(10.0);
        let large = config.rollup_duration(1000.0);

        assert!(large > small);
    }
}

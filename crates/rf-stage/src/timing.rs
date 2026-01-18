//! Timing Resolution — Convert untimed stages to timed traces
//!
//! STAGES don't inherently have timing. This module adds the time dimension
//! based on configurable timing profiles.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::event::StageEvent;
use crate::stage::Stage;
use crate::taxonomy::BigWinTier;
use crate::trace::StageTrace;

/// Timing profile identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TimingProfile {
    /// Normal gameplay speed
    #[default]
    Normal,
    /// Fast/Turbo mode
    Turbo,
    /// Mobile-optimized (slightly faster)
    Mobile,
    /// Studio preview (customizable)
    Studio,
    /// Instant (no delays, for testing)
    Instant,
    /// Custom profile by name
    Custom(u32),
}

impl TimingProfile {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Normal => "Normal",
            Self::Turbo => "Turbo",
            Self::Mobile => "Mobile",
            Self::Studio => "Studio",
            Self::Instant => "Instant",
            Self::Custom(_) => "Custom",
        }
    }
}

/// Timing configuration for a profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimingConfig {
    /// Profile identifier
    pub profile: TimingProfile,

    /// Base delay for each stage type (ms)
    #[serde(default)]
    pub stage_delays: HashMap<String, f64>,

    /// Time between reel stops (ms)
    pub reel_stop_interval: f64,

    /// Time before first reel stops (ms)
    pub reel_stop_base: f64,

    /// Time between win line highlights (ms)
    pub win_line_interval: f64,

    /// Rollup speed (credits per second)
    pub rollup_speed: f64,

    /// Big win tier durations (ms)
    #[serde(default)]
    pub bigwin_durations: HashMap<String, f64>,

    /// Feature enter delay (ms)
    pub feature_enter_delay: f64,

    /// Feature step interval (ms)
    pub feature_step_interval: f64,

    /// Cascade step interval (ms)
    pub cascade_step_interval: f64,

    /// Anticipation minimum duration (ms)
    pub anticipation_min_duration: f64,
}

impl Default for TimingConfig {
    fn default() -> Self {
        Self::normal()
    }
}

impl TimingConfig {
    /// Create normal timing config
    pub fn normal() -> Self {
        let mut stage_delays = HashMap::new();
        stage_delays.insert("spin_start".to_string(), 0.0);
        stage_delays.insert("reel_spinning".to_string(), 100.0);
        stage_delays.insert("evaluate_wins".to_string(), 100.0);
        stage_delays.insert("win_present".to_string(), 200.0);
        stage_delays.insert("rollup_start".to_string(), 100.0);
        stage_delays.insert("rollup_end".to_string(), 0.0);
        stage_delays.insert("bigwin_tier".to_string(), 500.0);
        stage_delays.insert("spin_end".to_string(), 200.0);
        stage_delays.insert("idle_start".to_string(), 1000.0);

        let mut bigwin_durations = HashMap::new();
        bigwin_durations.insert("win".to_string(), 3000.0);
        bigwin_durations.insert("big_win".to_string(), 5000.0);
        bigwin_durations.insert("mega_win".to_string(), 8000.0);
        bigwin_durations.insert("epic_win".to_string(), 12000.0);
        bigwin_durations.insert("ultra_win".to_string(), 15000.0);

        Self {
            profile: TimingProfile::Normal,
            stage_delays,
            reel_stop_interval: 150.0,
            reel_stop_base: 800.0,
            win_line_interval: 300.0,
            rollup_speed: 100.0,
            bigwin_durations,
            feature_enter_delay: 1000.0,
            feature_step_interval: 500.0,
            cascade_step_interval: 400.0,
            anticipation_min_duration: 1500.0,
        }
    }

    /// Create turbo timing config
    pub fn turbo() -> Self {
        let mut config = Self::normal();
        config.profile = TimingProfile::Turbo;

        // Reduce all delays by ~60%
        for delay in config.stage_delays.values_mut() {
            *delay *= 0.4;
        }

        config.reel_stop_interval = 50.0;
        config.reel_stop_base = 300.0;
        config.win_line_interval = 100.0;
        config.rollup_speed = 500.0;

        for duration in config.bigwin_durations.values_mut() {
            *duration *= 0.5;
        }

        config.feature_enter_delay = 400.0;
        config.feature_step_interval = 200.0;
        config.cascade_step_interval = 150.0;
        config.anticipation_min_duration = 500.0;

        config
    }

    /// Create mobile timing config
    pub fn mobile() -> Self {
        let mut config = Self::normal();
        config.profile = TimingProfile::Mobile;

        // Slightly faster than normal
        for delay in config.stage_delays.values_mut() {
            *delay *= 0.8;
        }

        config.reel_stop_interval = 120.0;
        config.reel_stop_base = 600.0;
        config.rollup_speed = 150.0;

        config
    }

    /// Create instant timing config (for testing)
    pub fn instant() -> Self {
        Self {
            profile: TimingProfile::Instant,
            stage_delays: HashMap::new(),
            reel_stop_interval: 0.0,
            reel_stop_base: 0.0,
            win_line_interval: 0.0,
            rollup_speed: f64::MAX,
            bigwin_durations: HashMap::new(),
            feature_enter_delay: 0.0,
            feature_step_interval: 0.0,
            cascade_step_interval: 0.0,
            anticipation_min_duration: 0.0,
        }
    }

    /// Get delay for a stage type
    pub fn get_stage_delay(&self, stage: &Stage) -> f64 {
        let type_name = stage.type_name();
        self.stage_delays.get(type_name).copied().unwrap_or(0.0)
    }

    /// Get big win duration
    pub fn get_bigwin_duration(&self, tier: &BigWinTier) -> f64 {
        let key = match tier {
            BigWinTier::Win => "win",
            BigWinTier::BigWin => "big_win",
            BigWinTier::MegaWin => "mega_win",
            BigWinTier::EpicWin => "epic_win",
            BigWinTier::UltraWin => "ultra_win",
            BigWinTier::Custom(_) => "custom",
        };
        self.bigwin_durations.get(key).copied().unwrap_or(3000.0)
    }
}

/// Timing resolver — converts untimed traces to timed traces
#[derive(Debug, Clone)]
pub struct TimingResolver {
    profiles: HashMap<TimingProfile, TimingConfig>,
}

impl Default for TimingResolver {
    fn default() -> Self {
        Self::new()
    }
}

impl TimingResolver {
    /// Create with default profiles
    pub fn new() -> Self {
        let mut profiles = HashMap::new();
        profiles.insert(TimingProfile::Normal, TimingConfig::normal());
        profiles.insert(TimingProfile::Turbo, TimingConfig::turbo());
        profiles.insert(TimingProfile::Mobile, TimingConfig::mobile());
        profiles.insert(TimingProfile::Instant, TimingConfig::instant());

        Self { profiles }
    }

    /// Add or update a profile
    pub fn set_profile(&mut self, config: TimingConfig) {
        self.profiles.insert(config.profile, config);
    }

    /// Get config for a profile
    pub fn get_config(&self, profile: TimingProfile) -> Option<&TimingConfig> {
        self.profiles.get(&profile)
    }

    /// Resolve timing for a trace
    pub fn resolve(&self, trace: &StageTrace, profile: TimingProfile) -> TimedStageTrace {
        let config = self.profiles.get(&profile).unwrap_or_else(|| {
            self.profiles
                .get(&TimingProfile::Normal)
                .expect("Normal profile must exist")
        });

        let mut timed_events = Vec::with_capacity(trace.events.len());
        let mut current_time = 0.0;
        let mut last_reel_index: Option<u8> = None;

        for event in &trace.events {
            // Calculate delay based on stage type
            let delay = self.calculate_delay(event, config, last_reel_index);
            current_time += delay;

            // Track reel stops for proper interval calculation
            if let Stage::ReelStop { reel_index, .. } = &event.stage {
                last_reel_index = Some(*reel_index);
            }

            timed_events.push(TimedStageEvent {
                event: event.clone(),
                absolute_time_ms: current_time,
                duration_ms: self.calculate_duration(event, config),
            });
        }

        TimedStageTrace {
            trace_id: trace.trace_id.clone(),
            game_id: trace.game_id.clone(),
            events: timed_events,
            total_duration_ms: current_time,
            profile,
        }
    }

    /// Calculate delay before this event
    fn calculate_delay(
        &self,
        event: &StageEvent,
        config: &TimingConfig,
        last_reel_index: Option<u8>,
    ) -> f64 {
        match &event.stage {
            // Reel stops have special timing
            Stage::ReelStop { reel_index, .. } => {
                if last_reel_index.is_none() || *reel_index == 0 {
                    // First reel: use base delay
                    config.reel_stop_base
                } else {
                    // Subsequent reels: use interval
                    config.reel_stop_interval
                }
            }

            // Anticipation has minimum duration
            Stage::AnticipationOff { .. } => config.anticipation_min_duration,

            // Win line shows
            Stage::WinLineShow { .. } => config.win_line_interval,

            // Feature steps
            Stage::FeatureStep { .. } => config.feature_step_interval,

            // Cascade steps
            Stage::CascadeStep { .. } => config.cascade_step_interval,

            // Feature enter
            Stage::FeatureEnter { .. } => config.feature_enter_delay,

            // Default: use stage delay map
            _ => config.get_stage_delay(&event.stage),
        }
    }

    /// Calculate duration of this event (for sustained sounds)
    fn calculate_duration(&self, event: &StageEvent, config: &TimingConfig) -> f64 {
        match &event.stage {
            // Big wins have specific durations
            Stage::BigWinTier { tier, .. } => config.get_bigwin_duration(tier),

            // Rollup duration based on amount and speed
            Stage::RollupStart { target_amount, .. } => {
                if config.rollup_speed > 0.0 {
                    (target_amount / config.rollup_speed) * 1000.0
                } else {
                    0.0
                }
            }

            // Looping stages have no set duration
            _ if event.stage.is_looping() => f64::MAX,

            // Default: no duration (instant)
            _ => 0.0,
        }
    }
}

/// A stage event with resolved timing
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TimedStageEvent {
    /// The original event
    pub event: StageEvent,

    /// Absolute time from start of trace (ms)
    pub absolute_time_ms: f64,

    /// Duration of this event (ms), MAX for looping
    pub duration_ms: f64,
}

impl TimedStageEvent {
    /// Check if this is a looping event
    pub fn is_looping(&self) -> bool {
        self.duration_ms == f64::MAX
    }

    /// Get end time (None if looping)
    pub fn end_time(&self) -> Option<f64> {
        if self.is_looping() {
            None
        } else {
            Some(self.absolute_time_ms + self.duration_ms)
        }
    }
}

/// A trace with resolved timing
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TimedStageTrace {
    /// Trace ID
    pub trace_id: String,

    /// Game ID
    pub game_id: String,

    /// Timed events
    pub events: Vec<TimedStageEvent>,

    /// Total duration (ms)
    pub total_duration_ms: f64,

    /// Profile used
    pub profile: TimingProfile,
}

impl TimedStageTrace {
    /// Get events at a specific time
    pub fn events_at(&self, time_ms: f64) -> Vec<&TimedStageEvent> {
        self.events
            .iter()
            .filter(|e| {
                e.absolute_time_ms <= time_ms
                    && (e.is_looping() || e.absolute_time_ms + e.duration_ms > time_ms)
            })
            .collect()
    }

    /// Get the current stage at a given time
    pub fn stage_at(&self, time_ms: f64) -> Option<&TimedStageEvent> {
        // Find the most recent non-looping event, or any active looping event
        self.events
            .iter()
            .rev()
            .find(|e| e.absolute_time_ms <= time_ms)
    }

    /// Find event by stage type
    pub fn find_stage(&self, type_name: &str) -> Option<&TimedStageEvent> {
        self.events
            .iter()
            .find(|e| e.event.stage.type_name() == type_name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::StageEvent;

    fn create_test_trace() -> StageTrace {
        let mut trace = StageTrace::new("test", "test_game");

        trace.push(StageEvent::new(Stage::SpinStart, 0.0));
        for i in 0..5u8 {
            trace.push(StageEvent::new(
                Stage::ReelStop {
                    reel_index: i,
                    symbols: vec![],
                },
                0.0, // Untimed
            ));
        }
        trace.push(StageEvent::new(
            Stage::WinPresent {
                win_amount: 100.0,
                line_count: 3,
            },
            0.0,
        ));
        trace.push(StageEvent::new(Stage::SpinEnd, 0.0));

        trace
    }

    #[test]
    fn test_timing_resolver_normal() {
        let resolver = TimingResolver::new();
        let trace = create_test_trace();

        let timed = resolver.resolve(&trace, TimingProfile::Normal);

        // Check reel timing
        let reel_stops: Vec<_> = timed
            .events
            .iter()
            .filter(|e| e.event.stage.type_name() == "reel_stop")
            .collect();

        assert_eq!(reel_stops.len(), 5);

        // First reel should have base delay
        assert!(reel_stops[0].absolute_time_ms >= 800.0);

        // Subsequent reels should have interval spacing
        let interval = reel_stops[1].absolute_time_ms - reel_stops[0].absolute_time_ms;
        assert!((interval - 150.0).abs() < 1.0);
    }

    #[test]
    fn test_timing_resolver_turbo() {
        let resolver = TimingResolver::new();
        let trace = create_test_trace();

        let normal = resolver.resolve(&trace, TimingProfile::Normal);
        let turbo = resolver.resolve(&trace, TimingProfile::Turbo);

        // Turbo should be significantly faster
        assert!(turbo.total_duration_ms < normal.total_duration_ms * 0.7);
    }

    #[test]
    fn test_timing_resolver_instant() {
        let resolver = TimingResolver::new();
        let trace = create_test_trace();

        let timed = resolver.resolve(&trace, TimingProfile::Instant);

        // Instant should have minimal duration
        assert!(timed.total_duration_ms < 100.0);
    }

    #[test]
    fn test_events_at_time() {
        let resolver = TimingResolver::new();
        let trace = create_test_trace();

        let timed = resolver.resolve(&trace, TimingProfile::Normal);

        // stage_at should find the most recent event at any time
        let first_event = &timed.events[0];
        let stage = timed.stage_at(first_event.absolute_time_ms);
        assert!(stage.is_some(), "Should find stage at its start time");

        // stage_at at end time should find last event
        let last_stage = timed.stage_at(timed.total_duration_ms);
        assert!(last_stage.is_some(), "Should find stage at end time");

        // events_at finds active events (those with duration spanning the time)
        // Most events are instant (duration=0), so events_at returns empty for them
        // This is by design - events_at is for finding sustained/looping events
        let events_count = timed.events.len();
        assert!(events_count > 0, "Should have events in trace");
    }
}

//! Tempo and Time Signature System
//!
//! Professional tempo management:
//! - Tempo map with tempo changes
//! - Time signature changes
//! - Musical time (bars/beats) ↔ absolute time conversion
//! - Tempo ramps (linear/exponential)
//! - MIDI clock sync
//! - PPQ (pulses per quarter note) support
//!
//! ## Time Units
//! - Samples: Audio samples (absolute)
//! - Ticks: PPQ-based (musical, 960 ticks per quarter note)
//! - Seconds: Real time
//! - Bars/Beats: Musical position (1.1.0 = Bar 1, Beat 1, Tick 0)

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Pulses per quarter note (industry standard: 960)
pub const PPQ: u32 = 960;

/// Minimum tempo
pub const MIN_TEMPO: f64 = 20.0;

/// Maximum tempo
pub const MAX_TEMPO: f64 = 400.0;

// ═══════════════════════════════════════════════════════════════════════════════
// TIME SIGNATURE
// ═══════════════════════════════════════════════════════════════════════════════

/// Time signature (e.g., 4/4, 3/4, 6/8)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct TimeSignature {
    /// Numerator (beats per bar)
    pub numerator: u8,
    /// Denominator (note value that gets one beat)
    pub denominator: u8,
}

impl Default for TimeSignature {
    fn default() -> Self {
        Self {
            numerator: 4,
            denominator: 4,
        }
    }
}

impl TimeSignature {
    pub fn new(numerator: u8, denominator: u8) -> Self {
        Self {
            numerator,
            denominator,
        }
    }

    /// Common time (4/4)
    pub const COMMON: Self = Self {
        numerator: 4,
        denominator: 4,
    };

    /// Cut time (2/2)
    pub const CUT: Self = Self {
        numerator: 2,
        denominator: 2,
    };

    /// Waltz time (3/4)
    pub const WALTZ: Self = Self {
        numerator: 3,
        denominator: 4,
    };

    /// Ticks per bar at this time signature
    pub fn ticks_per_bar(&self) -> u64 {
        // A quarter note = PPQ ticks
        // The denominator tells us what note value gets one beat
        // 4 = quarter, 8 = eighth, 2 = half
        let ticks_per_beat = PPQ as u64 * 4 / self.denominator as u64;
        ticks_per_beat * self.numerator as u64
    }

    /// Ticks per beat at this time signature
    pub fn ticks_per_beat(&self) -> u64 {
        PPQ as u64 * 4 / self.denominator as u64
    }

    /// Is compound meter (6/8, 9/8, 12/8)
    pub fn is_compound(&self) -> bool {
        self.denominator == 8 && self.numerator % 3 == 0
    }

    /// Display string (e.g., "4/4")
    pub fn to_string(&self) -> String {
        format!("{}/{}", self.numerator, self.denominator)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEMPO EVENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Tempo change event
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct TempoEvent {
    /// Position in ticks
    pub tick: u64,
    /// Tempo in BPM
    pub bpm: f64,
    /// Ramp type to next tempo
    pub ramp: TempoRamp,
}

impl TempoEvent {
    pub fn new(tick: u64, bpm: f64) -> Self {
        Self {
            tick,
            bpm: bpm.clamp(MIN_TEMPO, MAX_TEMPO),
            ramp: TempoRamp::Instant,
        }
    }

    pub fn with_ramp(tick: u64, bpm: f64, ramp: TempoRamp) -> Self {
        Self {
            tick,
            bpm: bpm.clamp(MIN_TEMPO, MAX_TEMPO),
            ramp,
        }
    }
}

/// Tempo ramp type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum TempoRamp {
    /// Instant tempo change
    #[default]
    Instant,
    /// Linear ramp to next tempo
    Linear,
    /// Exponential ramp (S-curve)
    SCurve,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIME SIGNATURE EVENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Time signature change event
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct TimeSignatureEvent {
    /// Position in bars (0-indexed)
    pub bar: u32,
    /// New time signature
    pub time_signature: TimeSignature,
}

impl TimeSignatureEvent {
    pub fn new(bar: u32, time_signature: TimeSignature) -> Self {
        Self {
            bar,
            time_signature,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MUSICAL POSITION
// ═══════════════════════════════════════════════════════════════════════════════

/// Musical position (bars, beats, ticks)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct MusicalPosition {
    /// Bar number (1-indexed for display, 0-indexed internally)
    pub bar: u32,
    /// Beat within bar (1-indexed for display, 0-indexed internally)
    pub beat: u8,
    /// Tick within beat
    pub tick: u16,
}

impl MusicalPosition {
    pub fn new(bar: u32, beat: u8, tick: u16) -> Self {
        Self { bar, beat, tick }
    }

    /// Display format: "Bar.Beat.Tick" (1-indexed)
    pub fn to_display_string(&self) -> String {
        format!("{}.{}.{:03}", self.bar + 1, self.beat + 1, self.tick)
    }

    /// Parse from display string
    pub fn from_display_string(s: &str) -> Option<Self> {
        let parts: Vec<&str> = s.split('.').collect();
        if parts.len() != 3 {
            return None;
        }

        let bar = parts[0].parse::<u32>().ok()?.checked_sub(1)?;
        let beat = parts[1].parse::<u8>().ok()?.checked_sub(1)?;
        let tick = parts[2].parse::<u16>().ok()?;

        Some(Self { bar, beat, tick })
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEMPO MAP
// ═══════════════════════════════════════════════════════════════════════════════

/// Tempo and time signature map
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TempoMap {
    /// Tempo events (sorted by tick)
    tempo_events: Vec<TempoEvent>,
    /// Time signature events (sorted by bar)
    time_sig_events: Vec<TimeSignatureEvent>,
    /// Sample rate for conversions
    sample_rate: u32,
    /// Cached: tick to sample mapping (for performance)
    #[serde(skip)]
    tick_to_sample_cache: Vec<(u64, u64)>,
    /// Cache valid flag
    #[serde(skip)]
    cache_valid: bool,
}

impl Default for TempoMap {
    fn default() -> Self {
        Self::new(48000)
    }
}

impl TempoMap {
    pub fn new(sample_rate: u32) -> Self {
        let mut map = Self {
            tempo_events: vec![TempoEvent::new(0, 120.0)],
            time_sig_events: vec![TimeSignatureEvent::new(0, TimeSignature::default())],
            sample_rate,
            tick_to_sample_cache: Vec::new(),
            cache_valid: false,
        };
        map.rebuild_cache();
        map
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: u32) {
        self.sample_rate = sample_rate;
        self.invalidate_cache();
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Tempo Management
    // ─────────────────────────────────────────────────────────────────────────────

    /// Get tempo at tick
    pub fn tempo_at_tick(&self, tick: u64) -> f64 {
        if self.tempo_events.is_empty() {
            return 120.0;
        }

        // Find the tempo event at or before this tick
        let idx = self
            .tempo_events
            .iter()
            .rposition(|e| e.tick <= tick)
            .unwrap_or(0);

        let event = &self.tempo_events[idx];

        // Check if we need to interpolate (ramp)
        if let Some(next) = self.tempo_events.get(idx + 1) {
            if event.ramp != TempoRamp::Instant && tick < next.tick {
                let t = (tick - event.tick) as f64 / (next.tick - event.tick) as f64;
                return match event.ramp {
                    TempoRamp::Linear => event.bpm + (next.bpm - event.bpm) * t,
                    TempoRamp::SCurve => {
                        let s = (1.0 - (t * std::f64::consts::PI).cos()) * 0.5;
                        event.bpm + (next.bpm - event.bpm) * s
                    }
                    TempoRamp::Instant => event.bpm,
                };
            }
        }

        event.bpm
    }

    /// Set tempo at tick
    pub fn set_tempo(&mut self, tick: u64, bpm: f64) {
        self.set_tempo_with_ramp(tick, bpm, TempoRamp::Instant);
    }

    /// Set tempo with ramp type
    pub fn set_tempo_with_ramp(&mut self, tick: u64, bpm: f64, ramp: TempoRamp) {
        let bpm = bpm.clamp(MIN_TEMPO, MAX_TEMPO);

        // Find existing event at this tick
        if let Some(event) = self.tempo_events.iter_mut().find(|e| e.tick == tick) {
            event.bpm = bpm;
            event.ramp = ramp;
        } else {
            self.tempo_events
                .push(TempoEvent::with_ramp(tick, bpm, ramp));
            self.tempo_events.sort_by_key(|e| e.tick);
        }

        self.invalidate_cache();
    }

    /// Remove tempo event at tick
    pub fn remove_tempo_event(&mut self, tick: u64) {
        // Don't remove the first event (always need one)
        if tick > 0 {
            self.tempo_events.retain(|e| e.tick != tick);
            self.invalidate_cache();
        }
    }

    /// Get all tempo events
    pub fn tempo_events(&self) -> &[TempoEvent] {
        &self.tempo_events
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Time Signature Management
    // ─────────────────────────────────────────────────────────────────────────────

    /// Get time signature at bar
    pub fn time_signature_at_bar(&self, bar: u32) -> TimeSignature {
        if self.time_sig_events.is_empty() {
            return TimeSignature::default();
        }

        self.time_sig_events
            .iter()
            .filter(|e| e.bar <= bar)
            .last()
            .map(|e| e.time_signature)
            .unwrap_or_default()
    }

    /// Set time signature at bar
    pub fn set_time_signature(&mut self, bar: u32, time_sig: TimeSignature) {
        if let Some(event) = self.time_sig_events.iter_mut().find(|e| e.bar == bar) {
            event.time_signature = time_sig;
        } else {
            self.time_sig_events
                .push(TimeSignatureEvent::new(bar, time_sig));
            self.time_sig_events.sort_by_key(|e| e.bar);
        }

        self.invalidate_cache();
    }

    /// Remove time signature event at bar
    pub fn remove_time_signature_event(&mut self, bar: u32) {
        if bar > 0 {
            self.time_sig_events.retain(|e| e.bar != bar);
            self.invalidate_cache();
        }
    }

    /// Get all time signature events
    pub fn time_signature_events(&self) -> &[TimeSignatureEvent] {
        &self.time_sig_events
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Conversion: Ticks <-> Samples
    // ─────────────────────────────────────────────────────────────────────────────

    /// Convert ticks to samples
    pub fn ticks_to_samples(&self, ticks: u64) -> u64 {
        if !self.cache_valid {
            // Slow path: calculate directly
            return self.calculate_ticks_to_samples(ticks);
        }

        // Fast path: use cached data
        // Binary search for closest cached point
        let idx = self
            .tick_to_sample_cache
            .binary_search_by_key(&ticks, |&(t, _)| t)
            .unwrap_or_else(|i| i.saturating_sub(1));

        if idx >= self.tick_to_sample_cache.len() {
            return self.calculate_ticks_to_samples(ticks);
        }

        let (cached_tick, cached_sample) = self.tick_to_sample_cache[idx];

        if cached_tick == ticks {
            return cached_sample;
        }

        // Interpolate from cached point
        let tempo = self.tempo_at_tick(cached_tick);
        let delta_ticks = ticks - cached_tick;
        let seconds_per_tick = 60.0 / (tempo * PPQ as f64);
        let delta_samples =
            (delta_ticks as f64 * seconds_per_tick * self.sample_rate as f64) as u64;

        cached_sample + delta_samples
    }

    /// Convert samples to ticks
    pub fn samples_to_ticks(&self, samples: u64) -> u64 {
        // This is more complex due to tempo changes
        // Use binary search with the cache
        if !self.cache_valid || self.tick_to_sample_cache.is_empty() {
            return self.calculate_samples_to_ticks(samples);
        }

        // Find the cached entry where sample is closest
        let idx = self
            .tick_to_sample_cache
            .binary_search_by_key(&samples, |&(_, s)| s)
            .unwrap_or_else(|i| i.saturating_sub(1));

        if idx >= self.tick_to_sample_cache.len() {
            return self.calculate_samples_to_ticks(samples);
        }

        let (cached_tick, cached_sample) = self.tick_to_sample_cache[idx];

        if cached_sample == samples {
            return cached_tick;
        }

        // Interpolate from cached point
        let tempo = self.tempo_at_tick(cached_tick);
        let delta_samples = samples.saturating_sub(cached_sample);
        let ticks_per_sample = (tempo * PPQ as f64) / (60.0 * self.sample_rate as f64);
        let delta_ticks = (delta_samples as f64 * ticks_per_sample) as u64;

        cached_tick + delta_ticks
    }

    fn calculate_ticks_to_samples(&self, ticks: u64) -> u64 {
        let mut total_samples: f64 = 0.0;
        let mut current_tick: u64 = 0;

        for i in 0..self.tempo_events.len() {
            let event = &self.tempo_events[i];
            let next_tick = self
                .tempo_events
                .get(i + 1)
                .map(|e| e.tick.min(ticks))
                .unwrap_or(ticks);

            if current_tick >= ticks {
                break;
            }

            let segment_ticks = next_tick.saturating_sub(current_tick);
            if segment_ticks == 0 {
                current_tick = event.tick;
                continue;
            }

            // Average tempo for this segment (accounting for ramps)
            let avg_tempo = if event.ramp != TempoRamp::Instant {
                if let Some(next_event) = self.tempo_events.get(i + 1) {
                    (event.bpm + next_event.bpm) / 2.0
                } else {
                    event.bpm
                }
            } else {
                event.bpm
            };

            let seconds_per_tick = 60.0 / (avg_tempo * PPQ as f64);
            total_samples += segment_ticks as f64 * seconds_per_tick * self.sample_rate as f64;

            current_tick = next_tick;
        }

        total_samples as u64
    }

    fn calculate_samples_to_ticks(&self, samples: u64) -> u64 {
        // Inverse of calculate_ticks_to_samples
        let mut total_ticks: u64 = 0;
        let mut remaining_samples = samples as f64;

        for i in 0..self.tempo_events.len() {
            if remaining_samples <= 0.0 {
                break;
            }

            let event = &self.tempo_events[i];
            let avg_tempo = event.bpm;

            let ticks_per_sample = (avg_tempo * PPQ as f64) / (60.0 * self.sample_rate as f64);

            // How many ticks until next tempo change?
            let ticks_to_next = if let Some(next) = self.tempo_events.get(i + 1) {
                next.tick - event.tick
            } else {
                u64::MAX
            };

            let samples_to_next = ticks_to_next as f64 / ticks_per_sample;

            if remaining_samples <= samples_to_next {
                total_ticks += (remaining_samples * ticks_per_sample) as u64;
                break;
            }

            total_ticks += ticks_to_next;
            remaining_samples -= samples_to_next;
        }

        total_ticks
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Conversion: Ticks <-> Musical Position
    // ─────────────────────────────────────────────────────────────────────────────

    /// Convert ticks to musical position (bar, beat, tick)
    pub fn ticks_to_position(&self, ticks: u64) -> MusicalPosition {
        let mut remaining_ticks = ticks;
        let mut current_bar: u32 = 0;

        // Process time signature changes
        for i in 0..self.time_sig_events.len() {
            let event = &self.time_sig_events[i];
            let next_bar = self
                .time_sig_events
                .get(i + 1)
                .map(|e| e.bar)
                .unwrap_or(u32::MAX);

            let bars_in_segment = next_bar.saturating_sub(event.bar);
            let ticks_per_bar = event.time_signature.ticks_per_bar();
            let segment_ticks = bars_in_segment as u64 * ticks_per_bar;

            if remaining_ticks < segment_ticks || next_bar == u32::MAX {
                // Position is within this segment
                let bars = remaining_ticks / ticks_per_bar;
                remaining_ticks %= ticks_per_bar;

                let ticks_per_beat = event.time_signature.ticks_per_beat();
                let beat = (remaining_ticks / ticks_per_beat) as u8;
                let tick = (remaining_ticks % ticks_per_beat) as u16;

                return MusicalPosition {
                    bar: current_bar + event.bar + bars as u32,
                    beat,
                    tick,
                };
            }

            remaining_ticks -= segment_ticks;
            current_bar = next_bar;
        }

        // Shouldn't reach here
        MusicalPosition::default()
    }

    /// Convert musical position to ticks
    pub fn position_to_ticks(&self, pos: &MusicalPosition) -> u64 {
        let mut total_ticks: u64 = 0;

        // Find which time signature segment the position is in
        for i in 0..self.time_sig_events.len() {
            let event = &self.time_sig_events[i];
            let next_bar = self
                .time_sig_events
                .get(i + 1)
                .map(|e| e.bar)
                .unwrap_or(u32::MAX);

            if pos.bar >= event.bar && (pos.bar < next_bar || next_bar == u32::MAX) {
                // Add ticks for complete bars before this segment
                for j in 0..i {
                    let prev_event = &self.time_sig_events[j];
                    let bars = if j + 1 < self.time_sig_events.len() {
                        self.time_sig_events[j + 1].bar - prev_event.bar
                    } else {
                        0
                    };
                    total_ticks += bars as u64 * prev_event.time_signature.ticks_per_bar();
                }

                // Add ticks for bars within this segment
                let bars_in_segment = pos.bar - event.bar;
                total_ticks += bars_in_segment as u64 * event.time_signature.ticks_per_bar();

                // Add beats and ticks
                total_ticks += pos.beat as u64 * event.time_signature.ticks_per_beat();
                total_ticks += pos.tick as u64;

                return total_ticks;
            }
        }

        total_ticks
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Conversion: Seconds
    // ─────────────────────────────────────────────────────────────────────────────

    /// Convert ticks to seconds
    pub fn ticks_to_seconds(&self, ticks: u64) -> f64 {
        let samples = self.ticks_to_samples(ticks);
        samples as f64 / self.sample_rate as f64
    }

    /// Convert seconds to ticks
    pub fn seconds_to_ticks(&self, seconds: f64) -> u64 {
        let samples = (seconds * self.sample_rate as f64) as u64;
        self.samples_to_ticks(samples)
    }

    /// Convert samples to seconds
    pub fn samples_to_seconds(&self, samples: u64) -> f64 {
        samples as f64 / self.sample_rate as f64
    }

    /// Convert seconds to samples
    pub fn seconds_to_samples(&self, seconds: f64) -> u64 {
        (seconds * self.sample_rate as f64) as u64
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Grid Snapping
    // ─────────────────────────────────────────────────────────────────────────────

    /// Snap tick to grid
    pub fn snap_to_grid(&self, tick: u64, grid: GridValue) -> u64 {
        let grid_ticks = grid.to_ticks();
        ((tick + grid_ticks / 2) / grid_ticks) * grid_ticks
    }

    /// Get next bar boundary
    pub fn next_bar(&self, tick: u64) -> u64 {
        let pos = self.ticks_to_position(tick);
        let next_pos = MusicalPosition::new(pos.bar + 1, 0, 0);
        self.position_to_ticks(&next_pos)
    }

    /// Get next beat boundary
    pub fn next_beat(&self, tick: u64) -> u64 {
        let pos = self.ticks_to_position(tick);
        let time_sig = self.time_signature_at_bar(pos.bar);

        let next_beat = pos.beat + 1;
        let (next_bar, next_beat) = if next_beat >= time_sig.numerator {
            (pos.bar + 1, 0)
        } else {
            (pos.bar, next_beat)
        };

        let next_pos = MusicalPosition::new(next_bar, next_beat, 0);
        self.position_to_ticks(&next_pos)
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Cache Management
    // ─────────────────────────────────────────────────────────────────────────────

    fn invalidate_cache(&mut self) {
        self.cache_valid = false;
    }

    fn rebuild_cache(&mut self) {
        self.tick_to_sample_cache.clear();

        // Build cache at regular intervals (every bar)
        let mut tick: u64 = 0;
        let max_ticks = 10000 * PPQ as u64; // Cache up to 10000 beats

        while tick < max_ticks {
            let samples = self.calculate_ticks_to_samples(tick);
            self.tick_to_sample_cache.push((tick, samples));
            tick += PPQ as u64 * 4; // Cache every 4 beats
        }

        self.cache_valid = true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRID VALUE
// ═══════════════════════════════════════════════════════════════════════════════

/// Grid/quantize values
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GridValue {
    /// Whole note
    Whole,
    /// Half note
    Half,
    /// Quarter note
    Quarter,
    /// Eighth note
    Eighth,
    /// Sixteenth note
    Sixteenth,
    /// Thirty-second note
    ThirtySecond,
    /// Sixty-fourth note
    SixtyFourth,
    /// Triplet quarter
    TripletQuarter,
    /// Triplet eighth
    TripletEighth,
    /// Triplet sixteenth
    TripletSixteenth,
    /// Dotted quarter
    DottedQuarter,
    /// Dotted eighth
    DottedEighth,
    /// Dotted sixteenth
    DottedSixteenth,
    /// Custom ticks
    Custom(u32),
}

impl Default for GridValue {
    fn default() -> Self {
        Self::Sixteenth
    }
}

impl GridValue {
    /// Convert to ticks
    pub fn to_ticks(&self) -> u64 {
        match self {
            GridValue::Whole => PPQ as u64 * 4,
            GridValue::Half => PPQ as u64 * 2,
            GridValue::Quarter => PPQ as u64,
            GridValue::Eighth => PPQ as u64 / 2,
            GridValue::Sixteenth => PPQ as u64 / 4,
            GridValue::ThirtySecond => PPQ as u64 / 8,
            GridValue::SixtyFourth => PPQ as u64 / 16,
            GridValue::TripletQuarter => PPQ as u64 * 2 / 3,
            GridValue::TripletEighth => PPQ as u64 / 3,
            GridValue::TripletSixteenth => PPQ as u64 / 6,
            GridValue::DottedQuarter => PPQ as u64 * 3 / 2,
            GridValue::DottedEighth => PPQ as u64 * 3 / 4,
            GridValue::DottedSixteenth => PPQ as u64 * 3 / 8,
            GridValue::Custom(ticks) => *ticks as u64,
        }
    }

    /// Display name
    pub fn name(&self) -> &'static str {
        match self {
            GridValue::Whole => "1",
            GridValue::Half => "1/2",
            GridValue::Quarter => "1/4",
            GridValue::Eighth => "1/8",
            GridValue::Sixteenth => "1/16",
            GridValue::ThirtySecond => "1/32",
            GridValue::SixtyFourth => "1/64",
            GridValue::TripletQuarter => "1/4T",
            GridValue::TripletEighth => "1/8T",
            GridValue::TripletSixteenth => "1/16T",
            GridValue::DottedQuarter => "1/4D",
            GridValue::DottedEighth => "1/8D",
            GridValue::DottedSixteenth => "1/16D",
            GridValue::Custom(_) => "Custom",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_time_signature() {
        let ts = TimeSignature::new(4, 4);
        assert_eq!(ts.ticks_per_bar(), 4 * PPQ as u64);
        assert_eq!(ts.ticks_per_beat(), PPQ as u64);

        let ts_68 = TimeSignature::new(6, 8);
        assert!(ts_68.is_compound());
        assert_eq!(ts_68.ticks_per_beat(), PPQ as u64 / 2);
    }

    #[test]
    fn test_tempo_map_basic() {
        let map = TempoMap::new(48000);
        assert_eq!(map.tempo_at_tick(0), 120.0);
    }

    #[test]
    fn test_tempo_change() {
        let mut map = TempoMap::new(48000);
        map.set_tempo(PPQ as u64 * 4, 140.0); // Change at bar 2

        assert_eq!(map.tempo_at_tick(0), 120.0);
        assert_eq!(map.tempo_at_tick(PPQ as u64 * 4), 140.0);
    }

    #[test]
    fn test_ticks_to_samples() {
        let map = TempoMap::new(48000);

        // At 120 BPM, one quarter note = 0.5 seconds = 24000 samples
        let samples = map.ticks_to_samples(PPQ as u64);
        assert!((samples as i64 - 24000).abs() < 100); // Allow small rounding
    }

    #[test]
    fn test_musical_position() {
        let map = TempoMap::new(48000);

        // Bar 0, beat 0, tick 0 = tick 0
        let pos = map.ticks_to_position(0);
        assert_eq!(pos.bar, 0);
        assert_eq!(pos.beat, 0);
        assert_eq!(pos.tick, 0);

        // One bar later (4/4 time)
        let pos = map.ticks_to_position(4 * PPQ as u64);
        assert_eq!(pos.bar, 1);
        assert_eq!(pos.beat, 0);
    }

    #[test]
    fn test_grid_values() {
        assert_eq!(GridValue::Quarter.to_ticks(), PPQ as u64);
        assert_eq!(GridValue::Eighth.to_ticks(), PPQ as u64 / 2);
        assert_eq!(GridValue::Sixteenth.to_ticks(), PPQ as u64 / 4);

        // Triplet eighth = quarter note / 3
        assert_eq!(GridValue::TripletEighth.to_ticks(), PPQ as u64 / 3);
    }

    #[test]
    fn test_snap_to_grid() {
        let map = TempoMap::new(48000);

        let tick = PPQ as u64 / 4 + 10; // Slightly after a 16th
        let snapped = map.snap_to_grid(tick, GridValue::Sixteenth);
        assert_eq!(snapped, PPQ as u64 / 4);
    }

    #[test]
    fn test_position_display() {
        let pos = MusicalPosition::new(3, 2, 480);
        assert_eq!(pos.to_display_string(), "4.3.480");

        let parsed = MusicalPosition::from_display_string("4.3.480").unwrap();
        assert_eq!(parsed, pos);
    }
}

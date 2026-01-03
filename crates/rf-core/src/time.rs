//! Time-related types for audio processing

use serde::{Deserialize, Serialize};

/// Sample position in the timeline
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct SamplePosition(pub u64);

impl SamplePosition {
    pub const ZERO: Self = Self(0);

    #[inline]
    pub fn from_seconds(seconds: f64, sample_rate: f64) -> Self {
        Self((seconds * sample_rate) as u64)
    }

    #[inline]
    pub fn to_seconds(self, sample_rate: f64) -> f64 {
        self.0 as f64 / sample_rate
    }

    #[inline]
    pub fn advance(&mut self, samples: u64) {
        self.0 += samples;
    }
}

impl std::ops::Add<u64> for SamplePosition {
    type Output = Self;

    fn add(self, rhs: u64) -> Self::Output {
        Self(self.0 + rhs)
    }
}

impl std::ops::Sub for SamplePosition {
    type Output = u64;

    fn sub(self, rhs: Self) -> Self::Output {
        self.0.saturating_sub(rhs.0)
    }
}

/// Time duration in samples
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct SampleDuration(pub u64);

impl SampleDuration {
    pub const ZERO: Self = Self(0);

    #[inline]
    pub fn from_seconds(seconds: f64, sample_rate: f64) -> Self {
        Self((seconds * sample_rate) as u64)
    }

    #[inline]
    pub fn from_ms(ms: f64, sample_rate: f64) -> Self {
        Self::from_seconds(ms / 1000.0, sample_rate)
    }

    #[inline]
    pub fn to_seconds(self, sample_rate: f64) -> f64 {
        self.0 as f64 / sample_rate
    }

    #[inline]
    pub fn to_ms(self, sample_rate: f64) -> f64 {
        self.to_seconds(sample_rate) * 1000.0
    }
}

/// Musical time (bars, beats)
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct MusicalTime {
    pub bar: u32,
    pub beat: u32,
    pub tick: u32,
}

impl MusicalTime {
    pub const TICKS_PER_BEAT: u32 = 960; // Standard MIDI resolution

    pub fn from_samples(
        samples: u64,
        sample_rate: f64,
        tempo: f64,
        time_sig_num: u32,
    ) -> Self {
        let seconds = samples as f64 / sample_rate;
        let beats_total = seconds * (tempo / 60.0);
        let total_ticks = (beats_total * Self::TICKS_PER_BEAT as f64) as u64;

        let ticks_per_bar = Self::TICKS_PER_BEAT as u64 * time_sig_num as u64;

        let bar = (total_ticks / ticks_per_bar) as u32;
        let remaining = total_ticks % ticks_per_bar;
        let beat = (remaining / Self::TICKS_PER_BEAT as u64) as u32;
        let tick = (remaining % Self::TICKS_PER_BEAT as u64) as u32;

        Self { bar, beat, tick }
    }
}

/// Tempo in BPM
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Tempo(pub f64);

impl Tempo {
    pub const DEFAULT: Self = Self(120.0);

    #[inline]
    pub fn beat_duration_samples(self, sample_rate: f64) -> f64 {
        (60.0 / self.0) * sample_rate
    }

    #[inline]
    pub fn bar_duration_samples(self, sample_rate: f64, beats_per_bar: u32) -> f64 {
        self.beat_duration_samples(sample_rate) * beats_per_bar as f64
    }
}

impl Default for Tempo {
    fn default() -> Self {
        Self::DEFAULT
    }
}

// TimeSignature is now in tempo.rs with enhanced functionality

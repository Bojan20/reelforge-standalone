//! rf-core: Shared types, traits, and utilities for ReelForge
//!
//! This crate provides the foundational types used across all ReelForge crates.

#![feature(portable_simd)]

mod sample;
mod time;
mod params;
mod error;
mod midi;
mod tempo;
mod edit_mode;
mod track;
mod smart_tempo;
mod routing;
mod channel_strip;
mod comping;
mod piano_roll;

pub use sample::*;
pub use time::*;
pub use params::*;
pub use error::*;
pub use midi::*;
pub use tempo::*;
pub use edit_mode::*;
pub use track::*;
pub use smart_tempo::*;
pub use routing::*;
pub use channel_strip::*;
pub use comping::*;
pub use piano_roll::*;

/// Standard sample rate options
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[repr(u32)]
pub enum SampleRate {
    Hz44100 = 44100,
    Hz48000 = 48000,
    Hz88200 = 88200,
    Hz96000 = 96000,
    Hz176400 = 176400,
    Hz192000 = 192000,
    Hz352800 = 352800,
    Hz384000 = 384000,
}

impl SampleRate {
    #[inline]
    pub fn as_f64(self) -> f64 {
        self as u32 as f64
    }

    #[inline]
    pub fn as_u32(self) -> u32 {
        self as u32
    }
}

impl Default for SampleRate {
    fn default() -> Self {
        Self::Hz48000
    }
}

/// Buffer size options
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[repr(u32)]
pub enum BufferSize {
    Samples32 = 32,
    Samples64 = 64,
    Samples128 = 128,
    Samples256 = 256,
    Samples512 = 512,
    Samples1024 = 1024,
    Samples2048 = 2048,
    Samples4096 = 4096,
}

impl BufferSize {
    #[inline]
    pub fn as_usize(self) -> usize {
        self as u32 as usize
    }

    /// Calculate latency in milliseconds
    #[inline]
    pub fn latency_ms(self, sample_rate: SampleRate) -> f64 {
        (self.as_usize() as f64 / sample_rate.as_f64()) * 1000.0
    }
}

impl Default for BufferSize {
    fn default() -> Self {
        Self::Samples256
    }
}

/// Channel configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ChannelConfig {
    Mono,
    Stereo,
    MidSide,
}

impl Default for ChannelConfig {
    fn default() -> Self {
        Self::Stereo
    }
}

/// Decibel value wrapper
#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Decibels(pub f64);

impl Decibels {
    pub const ZERO: Self = Self(0.0);
    pub const NEG_INF: Self = Self(f64::NEG_INFINITY);

    #[inline]
    pub fn from_gain(gain: f64) -> Self {
        if gain <= 0.0 {
            Self::NEG_INF
        } else {
            Self(20.0 * gain.log10())
        }
    }

    #[inline]
    pub fn to_gain(self) -> f64 {
        if self.0 <= -144.0 {
            0.0
        } else {
            10.0_f64.powf(self.0 / 20.0)
        }
    }
}

impl Default for Decibels {
    fn default() -> Self {
        Self::ZERO
    }
}

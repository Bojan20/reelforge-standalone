//! Parameter types for audio processors

use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};

/// Parameter ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ParamId(pub u32);

/// Parameter value (normalized 0.0-1.0)
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct NormalizedValue(f64);

impl NormalizedValue {
    pub const ZERO: Self = Self(0.0);
    pub const ONE: Self = Self(1.0);
    pub const HALF: Self = Self(0.5);

    #[inline]
    pub fn new(value: f64) -> Self {
        Self(value.clamp(0.0, 1.0))
    }

    #[inline]
    pub fn get(self) -> f64 {
        self.0
    }

    /// Map to a range
    #[inline]
    pub fn map(self, min: f64, max: f64) -> f64 {
        min + self.0 * (max - min)
    }

    /// Map logarithmically (for frequency, etc.)
    #[inline]
    pub fn map_log(self, min: f64, max: f64) -> f64 {
        let log_min = min.ln();
        let log_max = max.ln();
        (log_min + self.0 * (log_max - log_min)).exp()
    }

    /// Map exponentially (for volume, etc.)
    #[inline]
    pub fn map_exp(self, min: f64, max: f64, exponent: f64) -> f64 {
        min + self.0.powf(exponent) * (max - min)
    }
}

impl Default for NormalizedValue {
    fn default() -> Self {
        Self::HALF
    }
}

/// Atomic parameter for lock-free access
pub struct AtomicParam {
    bits: AtomicU64,
}

impl AtomicParam {
    pub fn new(value: f64) -> Self {
        Self {
            bits: AtomicU64::new(value.to_bits()),
        }
    }

    #[inline]
    pub fn get(&self) -> f64 {
        f64::from_bits(self.bits.load(Ordering::Relaxed))
    }

    #[inline]
    pub fn set(&self, value: f64) {
        self.bits.store(value.to_bits(), Ordering::Relaxed);
    }

    /// Smoothly transition to new value
    #[inline]
    pub fn smooth_set(&self, target: f64, smoothing: f64) {
        let current = self.get();
        let new_value = current + (target - current) * smoothing;
        self.set(new_value);
    }
}

impl Default for AtomicParam {
    fn default() -> Self {
        Self::new(0.0)
    }
}

/// Parameter change event for lock-free communication
#[derive(Debug, Clone, Copy)]
pub struct ParamChange {
    pub id: ParamId,
    pub value: f64,
    pub sample_offset: u32,
}

/// Parameter range specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParamRange {
    pub min: f64,
    pub max: f64,
    pub default: f64,
    pub skew: ParamSkew,
}

impl ParamRange {
    pub fn linear(min: f64, max: f64, default: f64) -> Self {
        Self {
            min,
            max,
            default,
            skew: ParamSkew::Linear,
        }
    }

    pub fn logarithmic(min: f64, max: f64, default: f64) -> Self {
        Self {
            min,
            max,
            default,
            skew: ParamSkew::Logarithmic,
        }
    }

    /// Denormalize a 0-1 value to actual value
    pub fn denormalize(&self, normalized: f64) -> f64 {
        match self.skew {
            ParamSkew::Linear => self.min + normalized * (self.max - self.min),
            ParamSkew::Logarithmic => {
                let log_min = self.min.ln();
                let log_max = self.max.ln();
                (log_min + normalized * (log_max - log_min)).exp()
            }
            ParamSkew::Exponential(exp) => self.min + normalized.powf(exp) * (self.max - self.min),
        }
    }

    /// Normalize an actual value to 0-1
    pub fn normalize(&self, value: f64) -> f64 {
        let clamped = value.clamp(self.min, self.max);
        match self.skew {
            ParamSkew::Linear => (clamped - self.min) / (self.max - self.min),
            ParamSkew::Logarithmic => {
                let log_min = self.min.ln();
                let log_max = self.max.ln();
                (clamped.ln() - log_min) / (log_max - log_min)
            }
            ParamSkew::Exponential(exp) => {
                ((clamped - self.min) / (self.max - self.min)).powf(1.0 / exp)
            }
        }
    }
}

/// Parameter skew type
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ParamSkew {
    Linear,
    Logarithmic,
    Exponential(f64),
}

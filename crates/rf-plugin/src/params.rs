//! Common parameter utilities for plugins

use nih_plug::prelude::*;
use std::sync::Arc;

/// dB to linear gain conversion
pub fn db_to_gain(db: f32) -> f32 {
    10.0_f32.powf(db / 20.0)
}

/// Linear gain to dB conversion
pub fn gain_to_db(gain: f32) -> f32 {
    20.0 * gain.max(1e-10).log10()
}

/// Create a frequency parameter (20Hz - 20kHz, logarithmic)
pub fn freq_param(name: &str, default: f32) -> FloatParam {
    FloatParam::new(
        name,
        default,
        FloatRange::Skewed {
            min: 20.0,
            max: 20000.0,
            factor: FloatRange::skew_factor(-2.0), // Logarithmic
        },
    )
    .with_unit(" Hz")
    .with_value_to_string(formatters::v2s_f32_hz_then_khz(2))
    .with_string_to_value(formatters::s2v_f32_hz_then_khz())
}

/// Create a gain parameter in dB
pub fn gain_param(name: &str, default: f32, min: f32, max: f32) -> FloatParam {
    FloatParam::new(
        name,
        default,
        FloatRange::Linear { min, max },
    )
    .with_unit(" dB")
    .with_value_to_string(formatters::v2s_f32_rounded(2))
}

/// Create a Q parameter (0.1 - 18.0)
pub fn q_param(name: &str, default: f32) -> FloatParam {
    FloatParam::new(
        name,
        default,
        FloatRange::Skewed {
            min: 0.1,
            max: 18.0,
            factor: FloatRange::skew_factor(-1.0),
        },
    )
    .with_value_to_string(formatters::v2s_f32_rounded(2))
}

/// Create a time parameter in ms
pub fn time_ms_param(name: &str, default: f32, min: f32, max: f32) -> FloatParam {
    FloatParam::new(
        name,
        default,
        FloatRange::Skewed {
            min,
            max,
            factor: FloatRange::skew_factor(-2.0),
        },
    )
    .with_unit(" ms")
    .with_value_to_string(formatters::v2s_f32_rounded(1))
}

/// Create a ratio parameter (1:1 to 20:1)
pub fn ratio_param(name: &str, default: f32) -> FloatParam {
    FloatParam::new(
        name,
        default,
        FloatRange::Skewed {
            min: 1.0,
            max: 20.0,
            factor: FloatRange::skew_factor(-1.5),
        },
    )
    .with_value_to_string(Arc::new(|v| format!("{:.1}:1", v)))
    .with_string_to_value(Arc::new(|s| {
        s.trim()
            .trim_end_matches(":1")
            .parse()
            .ok()
    }))
}

/// Create a percentage parameter (0-100%)
pub fn percent_param(name: &str, default: f32) -> FloatParam {
    FloatParam::new(
        name,
        default,
        FloatRange::Linear { min: 0.0, max: 100.0 },
    )
    .with_unit(" %")
    .with_value_to_string(formatters::v2s_f32_rounded(1))
}

/// Create a pan parameter (-100 to +100)
pub fn pan_param(name: &str) -> FloatParam {
    FloatParam::new(
        name,
        0.0,
        FloatRange::Linear { min: -100.0, max: 100.0 },
    )
    .with_value_to_string(Arc::new(|v| {
        if v.abs() < 0.5 {
            "C".to_string()
        } else if v < 0.0 {
            format!("L{:.0}", -v)
        } else {
            format!("R{:.0}", v)
        }
    }))
}

/// Smoother for parameter values (for audio thread)
#[derive(Debug, Clone)]
pub struct ParamSmoother {
    current: f32,
    target: f32,
    coef: f32,
}

impl ParamSmoother {
    pub fn new(initial: f32, smoothing_ms: f32, sample_rate: f32) -> Self {
        let coef = (-1.0 / (smoothing_ms * 0.001 * sample_rate)).exp();
        Self {
            current: initial,
            target: initial,
            coef,
        }
    }

    pub fn set_target(&mut self, target: f32) {
        self.target = target;
    }

    pub fn set_sample_rate(&mut self, sample_rate: f32, smoothing_ms: f32) {
        self.coef = (-1.0 / (smoothing_ms * 0.001 * sample_rate)).exp();
    }

    #[inline]
    pub fn next(&mut self) -> f32 {
        self.current = self.target + self.coef * (self.current - self.target);
        self.current
    }

    pub fn current(&self) -> f32 {
        self.current
    }

    pub fn is_smoothing(&self) -> bool {
        (self.current - self.target).abs() > 1e-6
    }

    pub fn reset(&mut self, value: f32) {
        self.current = value;
        self.target = value;
    }
}

impl Default for ParamSmoother {
    fn default() -> Self {
        Self {
            current: 0.0,
            target: 0.0,
            coef: 0.999,
        }
    }
}

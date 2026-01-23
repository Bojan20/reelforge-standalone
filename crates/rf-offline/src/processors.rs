//! Offline DSP processors

use serde::{Deserialize, Serialize};

/// Trait for offline processors
pub trait OfflineProcessor: Send + Sync {
    /// Process a block of samples
    fn process(&mut self, samples: &mut [f64], sample_rate: u32);

    /// Reset processor state
    fn reset(&mut self);

    /// Get processor latency in samples
    fn latency(&self) -> usize {
        0
    }

    /// Get processor name
    fn name(&self) -> &'static str;
}

/// Chain of processors
#[derive(Default)]
pub struct ProcessorChain {
    processors: Vec<Box<dyn OfflineProcessor>>,
}

impl std::fmt::Debug for ProcessorChain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ProcessorChain")
            .field("processors_count", &self.processors.len())
            .finish()
    }
}

impl ProcessorChain {
    /// Create new empty chain
    pub fn new() -> Self {
        Self::default()
    }

    /// Add processor to chain
    pub fn add<P: OfflineProcessor + 'static>(mut self, processor: P) -> Self {
        self.processors.push(Box::new(processor));
        self
    }

    /// Process samples through all processors
    pub fn process(&mut self, samples: &mut [f64], sample_rate: u32) {
        for processor in &mut self.processors {
            processor.process(samples, sample_rate);
        }
    }

    /// Reset all processors
    pub fn reset(&mut self) {
        for processor in &mut self.processors {
            processor.reset();
        }
    }

    /// Get total latency
    pub fn total_latency(&self) -> usize {
        self.processors.iter().map(|p| p.latency()).sum()
    }

    /// Check if chain is empty
    pub fn is_empty(&self) -> bool {
        self.processors.is_empty()
    }
}

/// Processor configuration (serializable)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ProcessorConfig {
    /// Gain adjustment
    Gain { db: f64 },

    /// DC offset removal
    DcOffset,

    /// Phase inversion
    Invert,

    /// Reverse audio
    Reverse,

    /// Fade in
    FadeIn { samples: u64, curve: FadeCurve },

    /// Fade out
    FadeOut { samples: u64, curve: FadeCurve },

    /// Normalize
    Normalize { target_db: f64 },

    /// High-pass filter
    HighPass { frequency: f64 },

    /// Low-pass filter
    LowPass { frequency: f64 },

    /// Time stretch
    TimeStretch { ratio: f64 },

    /// Pitch shift
    PitchShift { semitones: f64 },
}

/// Fade curve types
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum FadeCurve {
    Linear,
    Logarithmic,
    Exponential,
    SCurve,
    EqualPower,
}

impl Default for FadeCurve {
    fn default() -> Self {
        Self::EqualPower
    }
}

impl FadeCurve {
    /// Calculate fade amount at position (0.0 - 1.0)
    pub fn apply(&self, position: f64) -> f64 {
        let p = position.clamp(0.0, 1.0);
        match self {
            Self::Linear => p,
            Self::Logarithmic => {
                if p <= 0.0 {
                    0.0
                } else {
                    (p * 9.0 + 1.0).log10()
                }
            }
            Self::Exponential => p * p,
            Self::SCurve => {
                let t = p * std::f64::consts::PI;
                (1.0 - t.cos()) * 0.5
            }
            Self::EqualPower => (p * std::f64::consts::FRAC_PI_2).sin(),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROCESSOR IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Gain processor
pub struct GainProcessor {
    linear_gain: f64,
}

impl GainProcessor {
    pub fn new(db: f64) -> Self {
        Self {
            linear_gain: 10.0_f64.powf(db / 20.0),
        }
    }
}

impl OfflineProcessor for GainProcessor {
    fn process(&mut self, samples: &mut [f64], _sample_rate: u32) {
        for sample in samples {
            *sample *= self.linear_gain;
        }
    }

    fn reset(&mut self) {}

    fn name(&self) -> &'static str {
        "Gain"
    }
}

/// DC offset removal using high-pass filter
pub struct DcOffsetProcessor {
    prev_input: f64,
    prev_output: f64,
    coeff: f64,
}

impl DcOffsetProcessor {
    pub fn new() -> Self {
        Self {
            prev_input: 0.0,
            prev_output: 0.0,
            coeff: 0.995, // ~10Hz cutoff at 44.1kHz
        }
    }
}

impl Default for DcOffsetProcessor {
    fn default() -> Self {
        Self::new()
    }
}

impl OfflineProcessor for DcOffsetProcessor {
    fn process(&mut self, samples: &mut [f64], _sample_rate: u32) {
        for sample in samples {
            let input = *sample;
            let output = input - self.prev_input + self.coeff * self.prev_output;
            self.prev_input = input;
            self.prev_output = output;
            *sample = output;
        }
    }

    fn reset(&mut self) {
        self.prev_input = 0.0;
        self.prev_output = 0.0;
    }

    fn name(&self) -> &'static str {
        "DC Offset"
    }
}

/// Phase inversion
pub struct InvertProcessor;

impl OfflineProcessor for InvertProcessor {
    fn process(&mut self, samples: &mut [f64], _sample_rate: u32) {
        for sample in samples {
            *sample = -*sample;
        }
    }

    fn reset(&mut self) {}

    fn name(&self) -> &'static str {
        "Invert"
    }
}

/// Fade processor (works on entire buffer at once)
pub struct FadeProcessor {
    fade_in_samples: u64,
    fade_out_samples: u64,
    fade_in_curve: FadeCurve,
    fade_out_curve: FadeCurve,
    position: u64,
    total_samples: u64,
}

impl FadeProcessor {
    pub fn new(
        fade_in_samples: u64,
        fade_out_samples: u64,
        fade_in_curve: FadeCurve,
        fade_out_curve: FadeCurve,
        total_samples: u64,
    ) -> Self {
        Self {
            fade_in_samples,
            fade_out_samples,
            fade_in_curve,
            fade_out_curve,
            position: 0,
            total_samples,
        }
    }
}

impl OfflineProcessor for FadeProcessor {
    fn process(&mut self, samples: &mut [f64], _sample_rate: u32) {
        for sample in samples.iter_mut() {
            let mut gain = 1.0;

            // Fade in
            if self.position < self.fade_in_samples {
                let pos = self.position as f64 / self.fade_in_samples as f64;
                gain *= self.fade_in_curve.apply(pos);
            }

            // Fade out
            let fade_out_start = self.total_samples.saturating_sub(self.fade_out_samples);
            if self.position >= fade_out_start {
                let pos = (self.position - fade_out_start) as f64 / self.fade_out_samples as f64;
                gain *= self.fade_out_curve.apply(1.0 - pos);
            }

            *sample *= gain;
            self.position += 1;
        }
    }

    fn reset(&mut self) {
        self.position = 0;
    }

    fn name(&self) -> &'static str {
        "Fade"
    }
}

/// Simple biquad filter for high-pass/low-pass
pub struct BiquadFilter {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    z1: f64,
    z2: f64,
}

impl BiquadFilter {
    /// Create high-pass filter
    pub fn highpass(frequency: f64, sample_rate: u32, q: f64) -> Self {
        let omega = 2.0 * std::f64::consts::PI * frequency / sample_rate as f64;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = (1.0 + cos_omega) / 2.0;
        let b1 = -(1.0 + cos_omega);
        let b2 = (1.0 + cos_omega) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            z1: 0.0,
            z2: 0.0,
        }
    }

    /// Create low-pass filter
    pub fn lowpass(frequency: f64, sample_rate: u32, q: f64) -> Self {
        let omega = 2.0 * std::f64::consts::PI * frequency / sample_rate as f64;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = (1.0 - cos_omega) / 2.0;
        let b1 = 1.0 - cos_omega;
        let b2 = (1.0 - cos_omega) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            z1: 0.0,
            z2: 0.0,
        }
    }
}

impl OfflineProcessor for BiquadFilter {
    fn process(&mut self, samples: &mut [f64], _sample_rate: u32) {
        for sample in samples {
            let input = *sample;
            let output = self.b0 * input + self.z1;
            self.z1 = self.b1 * input - self.a1 * output + self.z2;
            self.z2 = self.b2 * input - self.a2 * output;
            *sample = output;
        }
    }

    fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }

    fn name(&self) -> &'static str {
        "Biquad Filter"
    }
}

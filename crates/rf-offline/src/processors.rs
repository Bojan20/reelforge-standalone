//! Offline DSP processors

use serde::{Deserialize, Serialize};

/// Trait for offline processors
pub trait OfflineProcessor: Send + Sync {
    /// Process a block of interleaved samples
    fn process(&mut self, samples: &mut [f64], sample_rate: u32);

    /// Set number of interleaved channels (for multichannel-aware processors)
    fn set_channels(&mut self, _channels: usize) {}

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

    /// Process samples through all processors (mono-compatible)
    pub fn process(&mut self, samples: &mut [f64], sample_rate: u32) {
        for processor in &mut self.processors {
            processor.process(samples, sample_rate);
        }
    }

    /// Process interleaved multichannel samples — sets channel count on BiquadFilters
    pub fn process_interleaved(&mut self, samples: &mut [f64], sample_rate: u32, channels: usize) {
        for processor in &mut self.processors {
            processor.set_channels(channels);
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

/// Biquad filter type
#[derive(Debug, Clone, Copy)]
pub enum BiquadType {
    HighPass,
    LowPass,
}

/// Simple biquad filter for high-pass/low-pass (TDF-II)
/// Supports multichannel interleaved audio with per-channel state.
pub struct BiquadFilter {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    /// Per-channel state (z1, z2). Grows on first process() call.
    channel_state: Vec<(f64, f64)>,
    /// Number of interleaved channels (set via set_channels or auto-detected)
    channels: usize,
    // Lazy-init: recalculate coefficients on first process() call
    // with actual sample rate from the audio buffer.
    filter_type: BiquadType,
    frequency: f64,
    q: f64,
    initialized_sr: Option<u32>,
}

impl BiquadFilter {
    /// Create high-pass filter.
    /// Coefficients are lazily recalculated with actual sample rate on first process() call.
    pub fn highpass(frequency: f64, sample_rate: u32, q: f64) -> Self {
        let mut f = Self::new_uninit(BiquadType::HighPass, frequency, q);
        f.calc_coefficients(sample_rate);
        f.initialized_sr = Some(sample_rate);
        f
    }

    /// Create low-pass filter.
    /// Coefficients are lazily recalculated with actual sample rate on first process() call.
    pub fn lowpass(frequency: f64, sample_rate: u32, q: f64) -> Self {
        let mut f = Self::new_uninit(BiquadType::LowPass, frequency, q);
        f.calc_coefficients(sample_rate);
        f.initialized_sr = Some(sample_rate);
        f
    }

    /// Create with deferred coefficient calculation (for FFI where sample rate is unknown).
    pub fn highpass_deferred(frequency: f64, q: f64) -> Self {
        Self::new_uninit(BiquadType::HighPass, frequency, q)
    }

    /// Create with deferred coefficient calculation (for FFI where sample rate is unknown).
    pub fn lowpass_deferred(frequency: f64, q: f64) -> Self {
        Self::new_uninit(BiquadType::LowPass, frequency, q)
    }

    /// Set number of interleaved channels (call before processing)
    pub fn set_channels(mut self, channels: usize) -> Self {
        self.channels = channels;
        self.channel_state = vec![(0.0, 0.0); channels];
        self
    }

    fn new_uninit(filter_type: BiquadType, frequency: f64, q: f64) -> Self {
        Self {
            b0: 1.0, b1: 0.0, b2: 0.0,
            a1: 0.0, a2: 0.0,
            channel_state: vec![(0.0, 0.0)], // default mono
            channels: 1,
            filter_type,
            frequency,
            q,
            initialized_sr: None,
        }
    }

    fn calc_coefficients(&mut self, sample_rate: u32) {
        let omega = 2.0 * std::f64::consts::PI * self.frequency / sample_rate as f64;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * self.q);

        let (b0, b1, b2) = match self.filter_type {
            BiquadType::HighPass => (
                (1.0 + cos_omega) / 2.0,
                -(1.0 + cos_omega),
                (1.0 + cos_omega) / 2.0,
            ),
            BiquadType::LowPass => (
                (1.0 - cos_omega) / 2.0,
                1.0 - cos_omega,
                (1.0 - cos_omega) / 2.0,
            ),
        };

        let a0 = 1.0 + alpha;
        self.b0 = b0 / a0;
        self.b1 = b1 / a0;
        self.b2 = b2 / a0;
        self.a1 = (-2.0 * cos_omega) / a0;
        self.a2 = (1.0 - alpha) / a0;
    }
}

impl OfflineProcessor for BiquadFilter {
    fn set_channels(&mut self, channels: usize) {
        if channels != self.channels {
            self.channels = channels.max(1);
            self.channel_state.resize(self.channels, (0.0, 0.0));
        }
    }

    fn process(&mut self, samples: &mut [f64], sample_rate: u32) {
        // Lazy-init: recalculate coefficients if sample rate differs
        if self.initialized_sr != Some(sample_rate) {
            self.calc_coefficients(sample_rate);
            self.initialized_sr = Some(sample_rate);
            for state in &mut self.channel_state {
                *state = (0.0, 0.0);
            }
        }

        let ch = self.channels;
        if ch <= 1 {
            // Mono: single state, process linearly
            let (ref mut z1, ref mut z2) = self.channel_state[0];
            for sample in samples {
                let input = *sample;
                let output = self.b0 * input + *z1;
                *z1 = self.b1 * input - self.a1 * output + *z2;
                *z2 = self.b2 * input - self.a2 * output;
                *sample = output;
            }
        } else {
            // Multichannel interleaved: per-channel state
            // Ensure we have enough state slots
            while self.channel_state.len() < ch {
                self.channel_state.push((0.0, 0.0));
            }
            let b0 = self.b0;
            let b1 = self.b1;
            let b2 = self.b2;
            let a1 = self.a1;
            let a2 = self.a2;
            for (i, sample) in samples.iter_mut().enumerate() {
                let c = i % ch;
                let (ref mut z1, ref mut z2) = self.channel_state[c];
                let input = *sample;
                let output = b0 * input + *z1;
                *z1 = b1 * input - a1 * output + *z2;
                *z2 = b2 * input - a2 * output;
                *sample = output;
            }
        }
    }

    fn reset(&mut self) {
        for state in &mut self.channel_state {
            *state = (0.0, 0.0);
        }
        self.initialized_sr = None;
    }

    fn name(&self) -> &'static str {
        "Biquad Filter"
    }
}

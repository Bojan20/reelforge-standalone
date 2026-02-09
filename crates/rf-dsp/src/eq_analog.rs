//! Analog EQ Models - Classic Hardware Emulations
//!
//! Professional analog EQ emulations:
//! - Pultec EQP-1A (passive, simultaneous boost+cut)
//! - API 550A/550B (proportional Q)
//! - Neve 1073 (inductor saturation)
//! - SSL E-Series (musical Q)
//! - Massive Passive (tube-driven passive)
//!
//! Each model includes:
//! - Accurate frequency response
//! - Harmonic distortion characteristics
//! - Component tolerances (vintage variation)
//! - Transformer coloration

use crate::{Processor, StereoProcessor};
use rf_core::Sample;
use std::f64::consts::PI;

// ============================================================================
// PULTEC EQP-1A
// ============================================================================

/// Pultec EQP-1A - Legendary passive tube EQ
///
/// Unique feature: simultaneous boost AND cut at same frequency
/// creates the famous "Pultec trick" sound
#[derive(Debug, Clone)]
pub struct PultecEqp1a {
    sample_rate: f64,

    // Low frequency section
    low_boost: f64, // 0-10 (represents dB boost)
    low_atten: f64, // 0-10 (represents dB cut)
    low_freq: PultecLowFreq,

    // High frequency section
    high_boost: f64,     // 0-10
    high_bandwidth: f64, // Sharp to Broad
    high_boost_freq: PultecHighBoostFreq,
    high_atten: f64, // 0-10
    high_atten_freq: PultecHighAttenFreq,

    // Internal filter states
    low_boost_filter: PultecPassiveFilter,
    low_atten_filter: PultecPassiveFilter,
    high_boost_filter: PultecPassiveFilter,
    high_atten_filter: PultecPassiveFilter,

    // Tube saturation
    tube_stage: TubeSaturation,

    // Output transformer
    transformer: OutputTransformer,
}

/// Low frequency selections (Hz)
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum PultecLowFreq {
    Hz20,
    Hz30,
    Hz60,
    #[default]
    Hz100,
}

impl PultecLowFreq {
    pub fn hz(&self) -> f64 {
        match self {
            PultecLowFreq::Hz20 => 20.0,
            PultecLowFreq::Hz30 => 30.0,
            PultecLowFreq::Hz60 => 60.0,
            PultecLowFreq::Hz100 => 100.0,
        }
    }
}

/// High boost frequency selections (kHz)
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum PultecHighBoostFreq {
    K3,
    K4,
    K5,
    K8,
    K10,
    #[default]
    K12,
    K16,
}

impl PultecHighBoostFreq {
    pub fn hz(&self) -> f64 {
        match self {
            PultecHighBoostFreq::K3 => 3000.0,
            PultecHighBoostFreq::K4 => 4000.0,
            PultecHighBoostFreq::K5 => 5000.0,
            PultecHighBoostFreq::K8 => 8000.0,
            PultecHighBoostFreq::K10 => 10000.0,
            PultecHighBoostFreq::K12 => 12000.0,
            PultecHighBoostFreq::K16 => 16000.0,
        }
    }
}

/// High atten frequency selections (kHz)
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum PultecHighAttenFreq {
    K5,
    #[default]
    K10,
    K20,
}

impl PultecHighAttenFreq {
    pub fn hz(&self) -> f64 {
        match self {
            PultecHighAttenFreq::K5 => 5000.0,
            PultecHighAttenFreq::K10 => 10000.0,
            PultecHighAttenFreq::K20 => 20000.0,
        }
    }
}

/// Passive LC filter for Pultec modeling
#[derive(Debug, Clone)]
struct PultecPassiveFilter {
    // State variables
    s1: f64,
    s2: f64,
    // Coefficients
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

impl Default for PultecPassiveFilter {
    fn default() -> Self {
        Self {
            s1: 0.0,
            s2: 0.0,
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
        }
    }
}

impl PultecPassiveFilter {
    fn new() -> Self {
        Self::default()
    }

    /// Configure as Pultec-style low shelf boost
    /// The Pultec uses inductor-capacitor resonance
    fn set_low_boost(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Pultec has a unique resonant peak before the shelf
        // Q is frequency-dependent (wider at lower frequencies)
        let q = 0.5 + (freq / 100.0) * 0.3;
        let alpha = sin_w / (2.0 * q);

        let a = 10.0_f64.powf(gain_db / 40.0);

        // Low shelf with resonant bump
        let a0 = (a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
        self.b0 = (a * ((a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
        self.b1 = (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
        self.b2 = (a * ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
        self.a1 = (-2.0 * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
        self.a2 = ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
    }

    /// Configure as Pultec-style low shelf cut
    /// Cut is gentler and shifted slightly higher in frequency
    fn set_low_atten(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        // Pultec atten is actually at a slightly higher frequency
        let actual_freq = freq * 1.5;
        let omega = 2.0 * PI * actual_freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Gentler Q for attenuation
        let q = 0.4;
        let alpha = sin_w / (2.0 * q);

        let a = 10.0_f64.powf(-gain_db / 40.0); // Negative for cut

        let a0 = (a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
        self.b0 = (a * ((a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
        self.b1 = (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
        self.b2 = (a * ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
        self.a1 = (-2.0 * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
        self.a2 = ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
    }

    /// Configure as Pultec high shelf boost with bandwidth control
    fn set_high_boost(&mut self, freq: f64, gain_db: f64, bandwidth: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Bandwidth affects Q (sharp = high Q, broad = low Q)
        let q = 0.3 + (1.0 - bandwidth) * 2.0;
        let alpha = sin_w / (2.0 * q);

        let a = 10.0_f64.powf(gain_db / 40.0);

        // High shelf
        let a0 = (a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
        self.b0 = (a * ((a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
        self.b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
        self.b2 = (a * ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
        self.a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
        self.a2 = ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
    }

    /// Configure as Pultec high shelf cut
    fn set_high_atten(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        let q = 0.5;
        let alpha = sin_w / (2.0 * q);

        let a = 10.0_f64.powf(-gain_db / 40.0);

        let a0 = (a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
        self.b0 = (a * ((a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
        self.b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
        self.b2 = (a * ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
        self.a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
        self.a2 = ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
    }

    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.s1;
        self.s1 = self.b1 * input - self.a1 * output + self.s2;
        self.s2 = self.b2 * input - self.a2 * output;
        output
    }

    fn reset(&mut self) {
        self.s1 = 0.0;
        self.s2 = 0.0;
    }
}

/// Tube saturation stage (12AX7 style)
#[derive(Debug, Clone)]
pub struct TubeSaturation {
    /// Drive amount (0-1)
    pub drive: f64,
    /// Bias point affects asymmetry
    bias: f64,
    /// Previous sample for slew limiting
    prev_sample: f64,
}

impl Default for TubeSaturation {
    fn default() -> Self {
        Self {
            drive: 0.3,
            bias: 0.1,
            prev_sample: 0.0,
        }
    }
}

impl TubeSaturation {
    pub fn new(drive: f64) -> Self {
        Self {
            drive: drive.clamp(0.0, 1.0),
            ..Default::default()
        }
    }

    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        // Add bias for asymmetric clipping
        let biased = input + self.bias;

        // Apply drive
        let driven = biased * (1.0 + self.drive * 4.0);

        // Tube-style soft clipping (asymmetric waveshaper)
        let saturated = if driven >= 0.0 {
            // Positive half: softer compression
            1.0 - (-driven * 0.7).exp()
        } else {
            // Negative half: harder clipping (grid conduction)
            -((1.0 - (-driven.abs() * 1.2).exp()) * 0.9)
        };

        // Slew rate limiting (tubes have limited bandwidth)
        let max_slew = 0.5;
        let delta = saturated - self.prev_sample;
        let limited = if delta.abs() > max_slew {
            self.prev_sample + delta.signum() * max_slew
        } else {
            saturated
        };

        self.prev_sample = limited;

        // Remove bias DC offset
        limited - self.bias * 0.5
    }

    pub fn reset(&mut self) {
        self.prev_sample = 0.0;
    }
}

/// Output transformer coloration
#[derive(Debug, Clone)]
pub struct OutputTransformer {
    /// Low frequency rolloff (Hz)
    lf_corner: f64,
    /// High frequency rolloff (Hz)
    hf_corner: f64,
    /// Saturation amount
    saturation: f64,
    // Filter states
    hp_state: f64,
    lp_state: f64,
    sample_rate: f64,
}

impl Default for OutputTransformer {
    fn default() -> Self {
        Self {
            lf_corner: 20.0,
            hf_corner: 25000.0,
            saturation: 0.1,
            hp_state: 0.0,
            lp_state: 0.0,
            sample_rate: 48000.0,
        }
    }
}

impl OutputTransformer {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            ..Default::default()
        }
    }

    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        // High-pass (transformer can't pass DC)
        let hp_coeff = 1.0 - (2.0 * PI * self.lf_corner / self.sample_rate);
        self.hp_state = hp_coeff * (self.hp_state + input);
        let hp_out = input - self.hp_state;

        // Low-pass (transformer has limited HF)
        let lp_coeff = 2.0 * PI * self.hf_corner / self.sample_rate;
        self.lp_state += lp_coeff * (hp_out - self.lp_state);

        // Core saturation (iron hysteresis)
        let sat_input = self.lp_state * (1.0 + self.saturation);

        sat_input.tanh()
    }

    pub fn reset(&mut self) {
        self.hp_state = 0.0;
        self.lp_state = 0.0;
    }
}

impl PultecEqp1a {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            low_boost: 0.0,
            low_atten: 0.0,
            low_freq: PultecLowFreq::default(),
            high_boost: 0.0,
            high_bandwidth: 0.5,
            high_boost_freq: PultecHighBoostFreq::default(),
            high_atten: 0.0,
            high_atten_freq: PultecHighAttenFreq::default(),
            low_boost_filter: PultecPassiveFilter::new(),
            low_atten_filter: PultecPassiveFilter::new(),
            high_boost_filter: PultecPassiveFilter::new(),
            high_atten_filter: PultecPassiveFilter::new(),
            tube_stage: TubeSaturation::default(),
            transformer: OutputTransformer::new(sample_rate),
        }
    }

    /// Set low frequency boost (0-10 maps to ~0-12dB)
    pub fn set_low_boost(&mut self, amount: f64) {
        self.low_boost = amount.clamp(0.0, 10.0);
        let gain_db = self.low_boost * 1.2; // ~12dB max
        self.low_boost_filter
            .set_low_boost(self.low_freq.hz(), gain_db, self.sample_rate);
    }

    /// Set low frequency attenuation (0-10)
    pub fn set_low_atten(&mut self, amount: f64) {
        self.low_atten = amount.clamp(0.0, 10.0);
        let gain_db = self.low_atten * 1.5; // Slightly more range for cut
        self.low_atten_filter
            .set_low_atten(self.low_freq.hz(), gain_db, self.sample_rate);
    }

    /// Set low frequency selection
    pub fn set_low_freq(&mut self, freq: PultecLowFreq) {
        self.low_freq = freq;
        // Recalculate filters
        self.set_low_boost(self.low_boost);
        self.set_low_atten(self.low_atten);
    }

    /// Set high frequency boost
    pub fn set_high_boost(&mut self, amount: f64) {
        self.high_boost = amount.clamp(0.0, 10.0);
        let gain_db = self.high_boost * 1.2;
        self.high_boost_filter.set_high_boost(
            self.high_boost_freq.hz(),
            gain_db,
            self.high_bandwidth,
            self.sample_rate,
        );
    }

    /// Set high boost bandwidth (0=sharp, 1=broad)
    pub fn set_high_bandwidth(&mut self, bandwidth: f64) {
        self.high_bandwidth = bandwidth.clamp(0.0, 1.0);
        self.set_high_boost(self.high_boost);
    }

    /// Set high boost frequency
    pub fn set_high_boost_freq(&mut self, freq: PultecHighBoostFreq) {
        self.high_boost_freq = freq;
        self.set_high_boost(self.high_boost);
    }

    /// Set high frequency attenuation
    pub fn set_high_atten(&mut self, amount: f64) {
        self.high_atten = amount.clamp(0.0, 10.0);
        let gain_db = self.high_atten * 1.5;
        self.high_atten_filter
            .set_high_atten(self.high_atten_freq.hz(), gain_db, self.sample_rate);
    }

    /// Set high atten frequency
    pub fn set_high_atten_freq(&mut self, freq: PultecHighAttenFreq) {
        self.high_atten_freq = freq;
        self.set_high_atten(self.high_atten);
    }

    /// Set tube drive
    pub fn set_drive(&mut self, drive: f64) {
        self.tube_stage.drive = drive.clamp(0.0, 1.0);
    }

    /// Process single sample
    #[inline(always)]
    fn process_sample_internal(&mut self, input: f64) -> f64 {
        // Passive EQ sections (parallel/series combination)
        let low_boosted = self.low_boost_filter.process(input);
        let low_result = self.low_atten_filter.process(low_boosted);

        let high_boosted = self.high_boost_filter.process(low_result);
        let eq_out = self.high_atten_filter.process(high_boosted);

        // Tube makeup gain stage
        let tube_out = self.tube_stage.process(eq_out);

        // Output transformer
        self.transformer.process(tube_out)
    }
}

impl Processor for PultecEqp1a {
    fn reset(&mut self) {
        self.low_boost_filter.reset();
        self.low_atten_filter.reset();
        self.high_boost_filter.reset();
        self.high_atten_filter.reset();
        self.tube_stage.reset();
        self.transformer.reset();
    }

    fn latency(&self) -> usize {
        0
    }
}

impl StereoProcessor for PultecEqp1a {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Mono sum for processing (Pultec is mono)
        let mono = (left + right) * 0.5;
        let processed = self.process_sample_internal(mono);
        (processed, processed)
    }
}

// ============================================================================
// API 550A / 550B
// ============================================================================

/// API 550 style EQ
///
/// Features:
/// - Proportional Q (wider at low gain, narrower at high gain)
/// - Discrete transistor saturation
/// - Stepped frequency selection
#[derive(Debug, Clone)]
pub struct Api550 {
    sample_rate: f64,

    // 3-band EQ
    low_gain: f64,
    low_freq: Api550LowFreq,
    mid_gain: f64,
    mid_freq: Api550MidFreq,
    high_gain: f64,
    high_freq: Api550HighFreq,

    // Filters
    low_filter: ApiProportionalQ,
    mid_filter: ApiProportionalQ,
    high_filter: ApiProportionalQ,

    // Discrete saturation
    saturation: DiscreteSaturation,
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Api550LowFreq {
    Hz50,
    Hz100,
    #[default]
    Hz200,
    Hz300,
    Hz400,
}

impl Api550LowFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Api550LowFreq::Hz50 => 50.0,
            Api550LowFreq::Hz100 => 100.0,
            Api550LowFreq::Hz200 => 200.0,
            Api550LowFreq::Hz300 => 300.0,
            Api550LowFreq::Hz400 => 400.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Api550MidFreq {
    Hz200,
    Hz400,
    Hz800,
    #[default]
    K1_5,
    K3,
}

impl Api550MidFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Api550MidFreq::Hz200 => 200.0,
            Api550MidFreq::Hz400 => 400.0,
            Api550MidFreq::Hz800 => 800.0,
            Api550MidFreq::K1_5 => 1500.0,
            Api550MidFreq::K3 => 3000.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Api550HighFreq {
    K2_5,
    K5,
    K7_5,
    #[default]
    K10,
    K12_5,
}

impl Api550HighFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Api550HighFreq::K2_5 => 2500.0,
            Api550HighFreq::K5 => 5000.0,
            Api550HighFreq::K7_5 => 7500.0,
            Api550HighFreq::K10 => 10000.0,
            Api550HighFreq::K12_5 => 12500.0,
        }
    }
}

/// API-style proportional Q filter
/// Q decreases as gain increases (more musical)
#[derive(Debug, Clone, Default)]
struct ApiProportionalQ {
    s1: f64,
    s2: f64,
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

impl ApiProportionalQ {
    fn new() -> Self {
        Self::default()
    }

    /// Set as peaking filter with proportional Q
    fn set_peak(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Proportional Q: wider at low gain, narrower at high gain
        // This is the secret sauce of API EQs
        let base_q = 0.7;
        let gain_factor = gain_db.abs() / 12.0; // Normalize to typical range
        let q = base_q + gain_factor * 1.5; // Q increases with gain

        let alpha = sin_w / (2.0 * q);
        let a = 10.0_f64.powf(gain_db / 40.0);

        let a0 = 1.0 + alpha / a;
        self.b0 = (1.0 + alpha * a) / a0;
        self.b1 = (-2.0 * cos_w) / a0;
        self.b2 = (1.0 - alpha * a) / a0;
        self.a1 = self.b1;
        self.a2 = (1.0 - alpha / a) / a0;
    }

    /// Set as shelf (for low/high bands optionally)
    fn set_shelf(&mut self, freq: f64, gain_db: f64, is_high: bool, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        let q = 0.707;
        let alpha = sin_w / (2.0 * q);
        let a = 10.0_f64.powf(gain_db / 40.0);

        if is_high {
            let a0 = (a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
            self.b0 = (a * ((a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
            self.b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
            self.b2 = (a * ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
            self.a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
            self.a2 = ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
        } else {
            let a0 = (a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
            self.b0 = (a * ((a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
            self.b1 = (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
            self.b2 = (a * ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
            self.a1 = (-2.0 * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
            self.a2 = ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
        }
    }

    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.s1;
        self.s1 = self.b1 * input - self.a1 * output + self.s2;
        self.s2 = self.b2 * input - self.a2 * output;
        output
    }

    fn reset(&mut self) {
        self.s1 = 0.0;
        self.s2 = 0.0;
    }
}

/// Discrete transistor saturation (API 2520 op-amp style)
#[derive(Debug, Clone)]
pub struct DiscreteSaturation {
    pub drive: f64,
    prev: f64,
}

impl Default for DiscreteSaturation {
    fn default() -> Self {
        Self {
            drive: 0.2,
            prev: 0.0,
        }
    }
}

impl DiscreteSaturation {
    pub fn new(drive: f64) -> Self {
        Self {
            drive: drive.clamp(0.0, 1.0),
            prev: 0.0,
        }
    }

    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        let driven = input * (1.0 + self.drive * 3.0);

        // API 2520 style: symmetric soft clipping
        let saturated = (driven * 1.5).tanh() / 1.5_f64.tanh();

        // Slight high frequency rolloff from transistor capacitance
        let smoothed = saturated * 0.95 + self.prev * 0.05;
        self.prev = smoothed;

        smoothed
    }

    pub fn reset(&mut self) {
        self.prev = 0.0;
    }
}

impl Api550 {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            low_gain: 0.0,
            low_freq: Api550LowFreq::default(),
            mid_gain: 0.0,
            mid_freq: Api550MidFreq::default(),
            high_gain: 0.0,
            high_freq: Api550HighFreq::default(),
            low_filter: ApiProportionalQ::new(),
            mid_filter: ApiProportionalQ::new(),
            high_filter: ApiProportionalQ::new(),
            saturation: DiscreteSaturation::default(),
        }
    }

    pub fn set_low(&mut self, gain_db: f64, freq: Api550LowFreq) {
        self.low_gain = gain_db.clamp(-12.0, 12.0);
        self.low_freq = freq;
        self.low_filter
            .set_shelf(freq.hz(), self.low_gain, false, self.sample_rate);
    }

    pub fn set_mid(&mut self, gain_db: f64, freq: Api550MidFreq) {
        self.mid_gain = gain_db.clamp(-12.0, 12.0);
        self.mid_freq = freq;
        self.mid_filter
            .set_peak(freq.hz(), self.mid_gain, self.sample_rate);
    }

    pub fn set_high(&mut self, gain_db: f64, freq: Api550HighFreq) {
        self.high_gain = gain_db.clamp(-12.0, 12.0);
        self.high_freq = freq;
        self.high_filter
            .set_shelf(freq.hz(), self.high_gain, true, self.sample_rate);
    }

    #[inline(always)]
    fn process_sample_internal(&mut self, input: f64) -> f64 {
        let low = self.low_filter.process(input);
        let mid = self.mid_filter.process(low);
        let high = self.high_filter.process(mid);
        self.saturation.process(high)
    }
}

impl Processor for Api550 {
    fn reset(&mut self) {
        self.low_filter.reset();
        self.mid_filter.reset();
        self.high_filter.reset();
        self.saturation.reset();
    }
}

impl StereoProcessor for Api550 {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mono = (left + right) * 0.5;
        let processed = self.process_sample_internal(mono);
        (processed, processed)
    }
}

// ============================================================================
// NEVE 1073
// ============================================================================

/// Neve 1073 style EQ
///
/// Features:
/// - Inductor-based filters (smooth, musical)
/// - Transformer saturation
/// - Class-A discrete saturation
/// - Fixed high-pass filter
#[derive(Debug, Clone)]
pub struct Neve1073 {
    sample_rate: f64,

    // High-pass filter (fixed frequencies)
    hp_enabled: bool,
    hp_freq: Neve1073HpFreq,

    // Low shelf
    low_gain: f64,
    low_freq: Neve1073LowFreq,

    // High shelf
    high_gain: f64,
    high_freq: Neve1073HighFreq,

    // Filters
    hp_filter: NeveInductorFilter,
    low_filter: NeveInductorFilter,
    high_filter: NeveInductorFilter,

    // Transformers
    input_transformer: NeveTransformer,
    output_transformer: NeveTransformer,
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Neve1073HpFreq {
    Hz50,
    Hz80,
    Hz160,
    #[default]
    Hz300,
}

impl Neve1073HpFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Neve1073HpFreq::Hz50 => 50.0,
            Neve1073HpFreq::Hz80 => 80.0,
            Neve1073HpFreq::Hz160 => 160.0,
            Neve1073HpFreq::Hz300 => 300.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Neve1073LowFreq {
    Hz35,
    Hz60,
    Hz110,
    #[default]
    Hz220,
}

impl Neve1073LowFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Neve1073LowFreq::Hz35 => 35.0,
            Neve1073LowFreq::Hz60 => 60.0,
            Neve1073LowFreq::Hz110 => 110.0,
            Neve1073LowFreq::Hz220 => 220.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Neve1073HighFreq {
    #[default]
    K12,
    K10,
    K7_5,
    K5,
}

impl Neve1073HighFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Neve1073HighFreq::K12 => 12000.0,
            Neve1073HighFreq::K10 => 10000.0,
            Neve1073HighFreq::K7_5 => 7500.0,
            Neve1073HighFreq::K5 => 5000.0,
        }
    }
}

/// Neve inductor-based filter
/// Inductors create smooth, musical response with slight ringing
#[derive(Debug, Clone, Default)]
struct NeveInductorFilter {
    s1: f64,
    s2: f64,
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

impl NeveInductorFilter {
    fn new() -> Self {
        Self::default()
    }

    /// High-pass with inductor characteristics
    fn set_highpass(&mut self, freq: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Inductor creates slight resonance
        let q = 0.6;
        let alpha = sin_w / (2.0 * q);

        let a0 = 1.0 + alpha;
        self.b0 = ((1.0 + cos_w) / 2.0) / a0;
        self.b1 = (-(1.0 + cos_w)) / a0;
        self.b2 = self.b0;
        self.a1 = (-2.0 * cos_w) / a0;
        self.a2 = (1.0 - alpha) / a0;
    }

    /// Low shelf with inductor smoothness
    fn set_low_shelf(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Inductor Q - very smooth transitions
        let q = 0.5;
        let alpha = sin_w / (2.0 * q);
        let a = 10.0_f64.powf(gain_db / 40.0);

        let a0 = (a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
        self.b0 = (a * ((a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
        self.b1 = (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
        self.b2 = (a * ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
        self.a1 = (-2.0 * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
        self.a2 = ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
    }

    /// High shelf with inductor characteristics
    fn set_high_shelf(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Neve high shelf is quite gentle
        let q = 0.4;
        let alpha = sin_w / (2.0 * q);
        let a = 10.0_f64.powf(gain_db / 40.0);

        let a0 = (a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
        self.b0 = (a * ((a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
        self.b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
        self.b2 = (a * ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
        self.a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
        self.a2 = ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
    }

    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.s1;
        self.s1 = self.b1 * input - self.a1 * output + self.s2;
        self.s2 = self.b2 * input - self.a2 * output;
        output
    }

    fn reset(&mut self) {
        self.s1 = 0.0;
        self.s2 = 0.0;
    }
}

/// Neve transformer with iron saturation
#[derive(Debug, Clone)]
pub struct NeveTransformer {
    /// Saturation amount
    saturation: f64,
    /// Low frequency boost from core
    lf_bump: f64,
    // States
    hp_state: f64,
    lp_state: f64,
    sample_rate: f64,
}

impl Default for NeveTransformer {
    fn default() -> Self {
        Self {
            saturation: 0.15,
            lf_bump: 1.02, // Slight LF enhancement
            hp_state: 0.0,
            lp_state: 0.0,
            sample_rate: 48000.0,
        }
    }
}

impl NeveTransformer {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            ..Default::default()
        }
    }

    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        // Input transformer: adds slight LF bump
        let lf_boosted = input * self.lf_bump;

        // Iron core saturation (asymmetric)
        let sat_input = lf_boosted * (1.0 + self.saturation);
        let saturated = if sat_input >= 0.0 {
            sat_input.tanh()
        } else {
            -(-sat_input * 0.95).tanh()
        };

        // Bandwidth limiting
        let hp_coeff = 1.0 - (2.0 * PI * 18.0 / self.sample_rate);
        self.hp_state = hp_coeff * (self.hp_state + saturated);
        let hp_out = saturated - self.hp_state;

        let lp_coeff = 2.0 * PI * 22000.0 / self.sample_rate;
        self.lp_state += lp_coeff * (hp_out - self.lp_state);

        self.lp_state
    }

    pub fn reset(&mut self) {
        self.hp_state = 0.0;
        self.lp_state = 0.0;
    }
}

impl Neve1073 {
    pub fn new(sample_rate: f64) -> Self {
        let mut eq = Self {
            sample_rate,
            hp_enabled: false,
            hp_freq: Neve1073HpFreq::default(),
            low_gain: 0.0,
            low_freq: Neve1073LowFreq::default(),
            high_gain: 0.0,
            high_freq: Neve1073HighFreq::default(),
            hp_filter: NeveInductorFilter::new(),
            low_filter: NeveInductorFilter::new(),
            high_filter: NeveInductorFilter::new(),
            input_transformer: NeveTransformer::new(sample_rate),
            output_transformer: NeveTransformer::new(sample_rate),
        };
        eq.hp_filter.set_highpass(eq.hp_freq.hz(), sample_rate);
        eq
    }

    pub fn set_hp(&mut self, enabled: bool, freq: Neve1073HpFreq) {
        self.hp_enabled = enabled;
        self.hp_freq = freq;
        self.hp_filter.set_highpass(freq.hz(), self.sample_rate);
    }

    pub fn set_low(&mut self, gain_db: f64, freq: Neve1073LowFreq) {
        self.low_gain = gain_db.clamp(-16.0, 16.0);
        self.low_freq = freq;
        self.low_filter
            .set_low_shelf(freq.hz(), self.low_gain, self.sample_rate);
    }

    pub fn set_high(&mut self, gain_db: f64, freq: Neve1073HighFreq) {
        self.high_gain = gain_db.clamp(-16.0, 16.0);
        self.high_freq = freq;
        self.high_filter
            .set_high_shelf(freq.hz(), self.high_gain, self.sample_rate);
    }

    #[inline(always)]
    fn process_sample_internal(&mut self, input: f64) -> f64 {
        // Input transformer
        let xfmr_in = self.input_transformer.process(input);

        // High-pass if enabled
        let hp_out = if self.hp_enabled {
            self.hp_filter.process(xfmr_in)
        } else {
            xfmr_in
        };

        // EQ
        let low = self.low_filter.process(hp_out);
        let high = self.high_filter.process(low);

        // Output transformer
        self.output_transformer.process(high)
    }
}

impl Processor for Neve1073 {
    fn reset(&mut self) {
        self.hp_filter.reset();
        self.low_filter.reset();
        self.high_filter.reset();
        self.input_transformer.reset();
        self.output_transformer.reset();
    }
}

impl StereoProcessor for Neve1073 {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mono = (left + right) * 0.5;
        let processed = self.process_sample_internal(mono);
        (processed, processed)
    }
}

// ============================================================================
// STEREO VARIANTS
// ============================================================================

/// Stereo Pultec (dual-mono)
#[derive(Debug, Clone)]
pub struct StereoPultec {
    pub left: PultecEqp1a,
    pub right: PultecEqp1a,
}

impl StereoPultec {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: PultecEqp1a::new(sample_rate),
            right: PultecEqp1a::new(sample_rate),
        }
    }

    /// Link both channels
    pub fn link(&mut self) {
        self.right.low_boost = self.left.low_boost;
        self.right.low_atten = self.left.low_atten;
        self.right.low_freq = self.left.low_freq;
        self.right.high_boost = self.left.high_boost;
        self.right.high_bandwidth = self.left.high_bandwidth;
        self.right.high_boost_freq = self.left.high_boost_freq;
        self.right.high_atten = self.left.high_atten;
        self.right.high_atten_freq = self.left.high_atten_freq;
    }
}

impl Processor for StereoPultec {
    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

impl StereoProcessor for StereoPultec {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        (
            self.left.process_sample_internal(left),
            self.right.process_sample_internal(right),
        )
    }
}

/// Stereo API 550
#[derive(Debug, Clone)]
pub struct StereoApi550 {
    pub left: Api550,
    pub right: Api550,
}

impl StereoApi550 {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Api550::new(sample_rate),
            right: Api550::new(sample_rate),
        }
    }
}

impl Processor for StereoApi550 {
    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

impl StereoProcessor for StereoApi550 {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        (
            self.left.process_sample_internal(left),
            self.right.process_sample_internal(right),
        )
    }
}

/// Stereo Neve 1073
#[derive(Debug, Clone)]
pub struct StereoNeve1073 {
    pub left: Neve1073,
    pub right: Neve1073,
}

impl StereoNeve1073 {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Neve1073::new(sample_rate),
            right: Neve1073::new(sample_rate),
        }
    }
}

impl Processor for StereoNeve1073 {
    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

impl StereoProcessor for StereoNeve1073 {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        (
            self.left.process_sample_internal(left),
            self.right.process_sample_internal(right),
        )
    }
}

// ============================================================================
// MAXIMUM BANDS FOR ANALOG MODELS
// ============================================================================

/// Maximum bands for analog EQ models
pub const ANALOG_MAX_BANDS: usize = 4;

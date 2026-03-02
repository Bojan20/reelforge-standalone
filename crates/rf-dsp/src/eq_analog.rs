//! Analog EQ Models — UAD-Faithful Hardware Emulations
//!
//! Professional analog EQ emulations based on UAD reference designs:
//! - Pultec EQP-1A (passive LC network, parallel boost+cut, tube saturation)
//! - API 550A (proportional Q, discrete gain steps, peak/shelf switching)
//! - Neve 1073 (inductor-based, 18dB/oct HPF, frequency-dependent MF Q, Class-A saturation)
//!
//! Each model includes:
//! - UAD-accurate frequency selections
//! - Correct signal flow topology
//! - Authentic harmonic distortion characteristics
//! - Transformer coloration

use crate::{Processor, StereoProcessor};
use rf_core::Sample;
use std::f64::consts::PI;

// ============================================================================
// PULTEC EQP-1A — UAD Reference
// ============================================================================
//
// Signal flow (PARALLEL LF topology — the "Pultec trick"):
//   Input → [LF Boost Filter] ─┐
//           [LF Atten Filter] ─┤ Sum (parallel)
//                               ↓
//           [HF Boost Filter] → [HF Atten Filter] → Tube Stage → Transformer → Output
//
// UAD Reference specs:
//   LF Boost: 0-10 knob → 0-13.5 dB, wide Q (~0.7)
//   LF Atten: 0-10 knob → 0-17.5 dB, narrow Q (~1.8), corner freq offset ×1.2
//   HF Boost: 0-10 knob → 0-18 dB, bandwidth-controlled Q (0.5-2.5)
//   HF Atten: 0-10 knob → 0-16 dB, gentle shelf
//   Tube: ≤0.15% THD (subtle 2nd harmonic)
//   LF freqs: 20, 30, 60, 100 Hz
//   HF boost freqs: 3k, 4k, 5k, 8k, 10k, 12k, 16k Hz
//   HF atten freqs: 5k, 10k, 20k Hz

/// Pultec EQP-1A — UAD-faithful passive tube EQ
///
/// Unique feature: LF boost and cut operate in PARALLEL at the same frequency,
/// creating the famous "Pultec trick" — a slight dip below the boost frequency.
#[derive(Debug, Clone)]
pub struct PultecEqp1a {
    sample_rate: f64,

    // Low frequency section
    low_boost: f64, // 0-10 knob position
    low_atten: f64, // 0-10 knob position
    low_freq: PultecLowFreq,

    // High frequency section
    high_boost: f64,     // 0-10 knob position
    high_bandwidth: f64, // 0.0=Sharp to 1.0=Broad
    high_boost_freq: PultecHighBoostFreq,
    high_atten: f64, // 0-10 knob position
    high_atten_freq: PultecHighAttenFreq,

    // Internal filter states
    low_boost_filter: PultecPassiveFilter,
    low_atten_filter: PultecPassiveFilter,
    high_boost_filter: PultecPassiveFilter,
    high_atten_filter: PultecPassiveFilter,

    // Tube saturation (subtle, ≤0.15% THD)
    tube_stage: TubeSaturation,

    // Output transformer
    transformer: OutputTransformer,
}

/// Low frequency selections (Hz) — matches UAD Pultec EQP-1A
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

/// High boost frequency selections (kHz) — matches UAD Pultec EQP-1A
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

/// High atten frequency selections (kHz) — matches UAD Pultec EQP-1A
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

/// Passive LC filter for Pultec modeling — TDF-II biquad
#[derive(Debug, Clone)]
struct PultecPassiveFilter {
    // State variables (TDF-II)
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
    /// UAD: Wide Q (~0.7), inductor-capacitor resonance creates slight peak before shelf
    fn set_low_boost(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            *self = Self::default();
            return;
        }
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // UAD Pultec: Wide, constant Q for boost (~0.7)
        // The inductor creates a broad, musical shelf with slight resonant peak
        let q = 0.7;
        let alpha = sin_w / (2.0 * q);
        let a = 10.0_f64.powf(gain_db / 40.0);

        // Low shelf with LC resonant character
        let a0 = (a + 1.0) + (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha;
        self.b0 = (a * ((a + 1.0) - (a - 1.0) * cos_w + 2.0 * a.sqrt() * alpha)) / a0;
        self.b1 = (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
        self.b2 = (a * ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha)) / a0;
        self.a1 = (-2.0 * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
        self.a2 = ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * a.sqrt() * alpha) / a0;
    }

    /// Configure as Pultec-style low shelf cut
    /// UAD: Narrower Q (~1.8), corner frequency offset ×1.2 above boost freq
    /// This offset is key to the "Pultec trick" — cut is slightly higher than boost
    fn set_low_atten(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            *self = Self::default();
            return;
        }
        // UAD: Atten corner is offset slightly above boost frequency
        let actual_freq = freq * 1.2;
        let omega = 2.0 * PI * actual_freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // UAD: Narrower Q for attenuation (tighter bandwidth than boost)
        let q = 1.8;
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
    /// UAD: Bandwidth knob sweeps Q from 0.5 (broad) to 2.5 (sharp)
    fn set_high_boost(&mut self, freq: f64, gain_db: f64, bandwidth: f64, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            *self = Self::default();
            return;
        }
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // UAD: Bandwidth 0=Broad (Q=0.5), 1=Sharp (Q=2.5)
        let q = 0.5 + bandwidth * 2.0;
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
    /// UAD: Gentle shelf with Q=0.6
    fn set_high_atten(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            *self = Self::default();
            return;
        }
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        let q = 0.6;
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

/// Tube saturation stage — UAD-faithful subtle 12AX7 style
/// Real Pultec: ≤0.15% THD, predominantly 2nd harmonic
#[derive(Debug, Clone)]
pub struct TubeSaturation {
    /// Drive amount (0-1)
    pub drive: f64,
    /// Bias point (subtle asymmetry)
    bias: f64,
    /// DC blocker state
    dc_state: f64,
    dc_prev_in: f64,
}

impl Default for TubeSaturation {
    fn default() -> Self {
        Self {
            drive: 0.3,
            bias: 0.04, // Subtle bias — real Pultec is barely asymmetric
            dc_state: 0.0,
            dc_prev_in: 0.0,
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
        // Subtle bias for mild asymmetry (2nd harmonic character)
        let biased = input + self.bias;

        // UAD-faithful: gentle drive, NOT aggressive
        // Real Pultec tube stage is very clean — ≤0.15% THD
        let driven = biased * (1.0 + self.drive * 1.5);

        // Soft saturation waveshaper — mostly transparent
        // Positive half: gentle compression
        // Negative half: slightly different curve (tube asymmetry)
        let saturated = if driven >= 0.0 {
            driven / (1.0 + driven.abs() * 0.15)
        } else {
            driven / (1.0 + driven.abs() * 0.18)
        };

        // DC blocker (removes bias offset)
        let dc_coeff = 0.9995;
        self.dc_state = saturated - self.dc_prev_in + dc_coeff * self.dc_state;
        self.dc_prev_in = saturated;

        self.dc_state
    }

    pub fn reset(&mut self) {
        self.dc_state = 0.0;
        self.dc_prev_in = 0.0;
    }
}

/// Output transformer coloration — UAD Pultec style
/// Adds subtle LF warmth, HF rolloff, and very gentle iron saturation
#[derive(Debug, Clone)]
pub struct OutputTransformer {
    /// Low frequency rolloff (Hz)
    lf_corner: f64,
    /// High frequency rolloff (Hz)
    hf_corner: f64,
    /// Saturation amount (subtle)
    saturation: f64,
    /// Makeup gain (compensate for passive losses)
    makeup_gain: f64,
    // Filter states
    hp_state: f64,
    lp_state: f64,
    sample_rate: f64,
}

impl Default for OutputTransformer {
    fn default() -> Self {
        Self {
            lf_corner: 18.0,
            hf_corner: 28000.0,
            saturation: 0.08,  // Very subtle
            makeup_gain: 1.05, // Slight makeup for passive losses
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
        let hp_coeff = (-2.0 * PI * self.lf_corner / self.sample_rate).exp();
        self.hp_state = hp_coeff * self.hp_state + (1.0 - hp_coeff) * input;
        let hp_out = input - self.hp_state;

        // Low-pass (transformer has limited HF bandwidth)
        let lp_coeff = 1.0 - (-2.0 * PI * self.hf_corner / self.sample_rate).exp();
        self.lp_state += lp_coeff * (hp_out - self.lp_state);

        // Sanitize filter states
        if !self.lp_state.is_finite() {
            self.lp_state = 0.0;
        }
        if !self.hp_state.is_finite() {
            self.hp_state = 0.0;
        }

        // Subtle iron saturation (very gentle tanh)
        let sat_input = self.lp_state * (1.0 + self.saturation);
        let saturated = sat_input.tanh();

        // Makeup gain to compensate for passive losses
        saturated * self.makeup_gain
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

    /// Set low frequency boost (0-10 knob → 0-13.5 dB) — UAD spec
    pub fn set_low_boost(&mut self, amount: f64) {
        self.low_boost = amount.clamp(0.0, 10.0);
        let gain_db = self.low_boost * 1.35; // UAD: max ~13.5 dB
        self.low_boost_filter
            .set_low_boost(self.low_freq.hz(), gain_db, self.sample_rate);
    }

    /// Set low frequency attenuation (0-10 knob → 0-17.5 dB) — UAD spec
    pub fn set_low_atten(&mut self, amount: f64) {
        self.low_atten = amount.clamp(0.0, 10.0);
        let gain_db = self.low_atten * 1.75; // UAD: max ~17.5 dB
        self.low_atten_filter
            .set_low_atten(self.low_freq.hz(), gain_db, self.sample_rate);
    }

    /// Set low frequency selection
    pub fn set_low_freq(&mut self, freq: PultecLowFreq) {
        self.low_freq = freq;
        // Recalculate both LF filters (boost and atten share frequency)
        self.set_low_boost(self.low_boost);
        self.set_low_atten(self.low_atten);
    }

    /// Set high frequency boost (0-10 knob → 0-18 dB) — UAD spec
    pub fn set_high_boost(&mut self, amount: f64) {
        self.high_boost = amount.clamp(0.0, 10.0);
        let gain_db = self.high_boost * 1.8; // UAD: max ~18 dB
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

    /// Set high frequency attenuation (0-10 knob → 0-16 dB) — UAD spec
    pub fn set_high_atten(&mut self, amount: f64) {
        self.high_atten = amount.clamp(0.0, 10.0);
        let gain_db = self.high_atten * 1.6; // UAD: max ~16 dB
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

    /// Process single sample — UAD-faithful PARALLEL LF topology
    #[inline(always)]
    fn process_sample_internal(&mut self, input: f64) -> f64 {
        // ========================================
        // PARALLEL LF section (the "Pultec trick")
        // ========================================
        // Both boost and cut filters receive the SAME input signal,
        // then their outputs are summed. This creates the characteristic
        // dip-then-boost curve when both knobs are turned up.
        let low_boost_out = self.low_boost_filter.process(input);
        let low_atten_out = self.low_atten_filter.process(input);
        let lf_out = (low_boost_out + low_atten_out) * 0.5;

        // ========================================
        // SERIAL HF section
        // ========================================
        let high_boosted = self.high_boost_filter.process(lf_out);
        let eq_out = self.high_atten_filter.process(high_boosted);

        // ========================================
        // Tube makeup gain stage (subtle)
        // ========================================
        let tube_out = self.tube_stage.process(eq_out);

        // ========================================
        // Output transformer
        // ========================================
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
// API 550A — UAD Reference
// ============================================================================
//
// UAD Reference specs:
//   3-band EQ with proportional Q (constant apparent bandwidth)
//   Q DECREASES with gain: wide at low gain (~4.5 at ±2dB), narrow at high gain (~0.9 at ±12dB)
//   Discrete gain steps: ±2, ±4, ±6, ±9, ±12 dB
//   Band 1 (LF): peak or shelf, 7 freqs: 30, 40, 50, 100, 200, 300, 400 Hz
//   Band 2 (MF): peak only, 7 freqs: 200, 400, 600, 800, 1.5k, 3k, 5k Hz
//   Band 3 (HF): peak or shelf, 7 freqs: 2.5k, 5k, 7k, 10k, 12.5k, 15k, 20k Hz
//   Bandpass filter: 50Hz-15kHz, 12dB/oct
//   API 2520 discrete op-amp saturation: symmetric, subtle

/// API 550A style EQ — UAD-faithful implementation
#[derive(Debug, Clone)]
pub struct Api550 {
    sample_rate: f64,

    // 3-band EQ
    low_gain: f64,
    low_freq: Api550LowFreq,
    low_is_shelf: bool, // true=shelf, false=peak
    mid_gain: f64,
    mid_freq: Api550MidFreq,
    high_gain: f64,
    high_freq: Api550HighFreq,
    high_is_shelf: bool, // true=shelf, false=peak

    // Bandpass filter
    bandpass_enabled: bool,
    bp_hp_filter: ApiProportionalQ, // 50Hz HPF section of bandpass
    bp_lp_filter: ApiProportionalQ, // 15kHz LPF section of bandpass

    // Filters
    low_filter: ApiProportionalQ,
    mid_filter: ApiProportionalQ,
    high_filter: ApiProportionalQ,

    // Discrete op-amp saturation
    saturation: DiscreteSaturation,
}

/// API 550A LF frequency selections — UAD 7-position switch
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Api550LowFreq {
    Hz30,
    Hz40,
    Hz50,
    #[default]
    Hz100,
    Hz200,
    Hz300,
    Hz400,
}

impl Api550LowFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Api550LowFreq::Hz30 => 30.0,
            Api550LowFreq::Hz40 => 40.0,
            Api550LowFreq::Hz50 => 50.0,
            Api550LowFreq::Hz100 => 100.0,
            Api550LowFreq::Hz200 => 200.0,
            Api550LowFreq::Hz300 => 300.0,
            Api550LowFreq::Hz400 => 400.0,
        }
    }
}

/// API 550A MF frequency selections — UAD 7-position switch
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Api550MidFreq {
    Hz200,
    Hz400,
    Hz600,
    Hz800,
    #[default]
    K1_5,
    K3,
    K5,
}

impl Api550MidFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Api550MidFreq::Hz200 => 200.0,
            Api550MidFreq::Hz400 => 400.0,
            Api550MidFreq::Hz600 => 600.0,
            Api550MidFreq::Hz800 => 800.0,
            Api550MidFreq::K1_5 => 1500.0,
            Api550MidFreq::K3 => 3000.0,
            Api550MidFreq::K5 => 5000.0,
        }
    }
}

/// API 550A HF frequency selections — UAD 7-position switch
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Api550HighFreq {
    K2_5,
    K5,
    K7,
    #[default]
    K10,
    K12_5,
    K15,
    K20,
}

impl Api550HighFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Api550HighFreq::K2_5 => 2500.0,
            Api550HighFreq::K5 => 5000.0,
            Api550HighFreq::K7 => 7000.0,
            Api550HighFreq::K10 => 10000.0,
            Api550HighFreq::K12_5 => 12500.0,
            Api550HighFreq::K15 => 15000.0,
            Api550HighFreq::K20 => 20000.0,
        }
    }
}

/// Discrete gain steps for API 550A — UAD-faithful stepped attenuator
const API_GAIN_STEPS: [f64; 11] = [-12.0, -9.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 9.0, 12.0];

/// Snap continuous gain to nearest discrete API step
fn snap_to_api_gain(gain_db: f64) -> f64 {
    let mut closest = 0.0;
    let mut min_dist = f64::MAX;
    for &step in &API_GAIN_STEPS {
        let dist = (gain_db - step).abs();
        if dist < min_dist {
            min_dist = dist;
            closest = step;
        }
    }
    closest
}

/// API-style proportional Q filter — TDF-II biquad
/// UAD: Q DECREASES as gain increases (constant apparent bandwidth / "constant-skirt")
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
        Self {
            b0: 1.0,
            ..Self::default()
        }
    }

    /// Set as peaking filter with UAD proportional Q
    /// Q = wide at low gain, narrow at high gain
    fn set_peak(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            self.b0 = 1.0;
            self.b1 = 0.0;
            self.b2 = 0.0;
            self.a1 = 0.0;
            self.a2 = 0.0;
            return;
        }
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // UAD Proportional Q: DECREASES (gets narrower) as gain increases
        // ~4.5 at ±2dB → ~0.9 at ±12dB
        let gain_factor = (gain_db.abs() / 12.0).clamp(0.0, 1.0);
        let q = 4.5 - gain_factor * 3.6; // 4.5 → 0.9

        let alpha = sin_w / (2.0 * q);
        let a = 10.0_f64.powf(gain_db / 40.0);

        let a0 = 1.0 + alpha / a;
        self.b0 = (1.0 + alpha * a) / a0;
        self.b1 = (-2.0 * cos_w) / a0;
        self.b2 = (1.0 - alpha * a) / a0;
        self.a1 = self.b1;
        self.a2 = (1.0 - alpha / a) / a0;
    }

    /// Set as shelf filter (for low/high bands)
    fn set_shelf(&mut self, freq: f64, gain_db: f64, is_high: bool, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            self.b0 = 1.0;
            self.b1 = 0.0;
            self.b2 = 0.0;
            self.a1 = 0.0;
            self.a2 = 0.0;
            return;
        }
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

    /// Set as 2nd-order high-pass (for bandpass filter)
    fn set_highpass(&mut self, freq: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let q = 0.707;
        let alpha = sin_w / (2.0 * q);

        let a0 = 1.0 + alpha;
        self.b0 = ((1.0 + cos_w) / 2.0) / a0;
        self.b1 = (-(1.0 + cos_w)) / a0;
        self.b2 = self.b0;
        self.a1 = (-2.0 * cos_w) / a0;
        self.a2 = (1.0 - alpha) / a0;
    }

    /// Set as 2nd-order low-pass (for bandpass filter)
    fn set_lowpass(&mut self, freq: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let q = 0.707;
        let alpha = sin_w / (2.0 * q);

        let a0 = 1.0 + alpha;
        self.b0 = ((1.0 - cos_w) / 2.0) / a0;
        self.b1 = (1.0 - cos_w) / a0;
        self.b2 = self.b0;
        self.a1 = (-2.0 * cos_w) / a0;
        self.a2 = (1.0 - alpha) / a0;
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

/// Discrete transistor saturation — API 2520 op-amp style
/// Symmetric, subtle, with slight HF rolloff from transistor capacitance
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
        let mut eq = Self {
            sample_rate,
            low_gain: 0.0,
            low_freq: Api550LowFreq::default(),
            low_is_shelf: true, // Default: shelf for LF
            mid_gain: 0.0,
            mid_freq: Api550MidFreq::default(),
            high_gain: 0.0,
            high_freq: Api550HighFreq::default(),
            high_is_shelf: true, // Default: shelf for HF
            bandpass_enabled: false,
            bp_hp_filter: ApiProportionalQ::new(),
            bp_lp_filter: ApiProportionalQ::new(),
            low_filter: ApiProportionalQ::new(),
            mid_filter: ApiProportionalQ::new(),
            high_filter: ApiProportionalQ::new(),
            saturation: DiscreteSaturation::default(),
        };
        // Initialize bandpass filters
        eq.bp_hp_filter.set_highpass(50.0, sample_rate);
        eq.bp_lp_filter.set_lowpass(15000.0, sample_rate);
        eq
    }

    pub fn set_low(&mut self, gain_db: f64, freq: Api550LowFreq) {
        self.low_gain = snap_to_api_gain(gain_db.clamp(-12.0, 12.0));
        self.low_freq = freq;
        self.update_low_filter();
    }

    /// Set LF shape: true=shelf, false=peak
    pub fn set_low_shape(&mut self, is_shelf: bool) {
        self.low_is_shelf = is_shelf;
        self.update_low_filter();
    }

    fn update_low_filter(&mut self) {
        if self.low_is_shelf {
            self.low_filter
                .set_shelf(self.low_freq.hz(), self.low_gain, false, self.sample_rate);
        } else {
            self.low_filter
                .set_peak(self.low_freq.hz(), self.low_gain, self.sample_rate);
        }
    }

    pub fn set_mid(&mut self, gain_db: f64, freq: Api550MidFreq) {
        self.mid_gain = snap_to_api_gain(gain_db.clamp(-12.0, 12.0));
        self.mid_freq = freq;
        self.mid_filter
            .set_peak(freq.hz(), self.mid_gain, self.sample_rate);
    }

    pub fn set_high(&mut self, gain_db: f64, freq: Api550HighFreq) {
        self.high_gain = snap_to_api_gain(gain_db.clamp(-12.0, 12.0));
        self.high_freq = freq;
        self.update_high_filter();
    }

    /// Set HF shape: true=shelf, false=peak
    pub fn set_high_shape(&mut self, is_shelf: bool) {
        self.high_is_shelf = is_shelf;
        self.update_high_filter();
    }

    fn update_high_filter(&mut self) {
        if self.high_is_shelf {
            self.high_filter
                .set_shelf(self.high_freq.hz(), self.high_gain, true, self.sample_rate);
        } else {
            self.high_filter
                .set_peak(self.high_freq.hz(), self.high_gain, self.sample_rate);
        }
    }

    /// Set bandpass filter on/off (50Hz-15kHz, 12dB/oct)
    pub fn set_bandpass(&mut self, enabled: bool) {
        self.bandpass_enabled = enabled;
    }

    #[inline(always)]
    fn process_sample_internal(&mut self, input: f64) -> f64 {
        // Bandpass filter (if enabled)
        let bp_out = if self.bandpass_enabled {
            let hp = self.bp_hp_filter.process(input);
            self.bp_lp_filter.process(hp)
        } else {
            input
        };

        // Serial EQ: Low → Mid → High
        let low = self.low_filter.process(bp_out);
        let mid = self.mid_filter.process(low);
        let high = self.high_filter.process(mid);

        // API 2520 saturation
        self.saturation.process(high)
    }
}

impl Processor for Api550 {
    fn reset(&mut self) {
        self.low_filter.reset();
        self.mid_filter.reset();
        self.high_filter.reset();
        self.bp_hp_filter.reset();
        self.bp_lp_filter.reset();
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
// NEVE 1073 — UAD Reference
// ============================================================================
//
// UAD Reference specs:
//   HPF: 4 freqs (50, 80, 160, 300 Hz), 18dB/oct (3rd order Butterworth)
//   LF: shelf, 4 freqs (35, 60, 110, 220 Hz), ±16 dB
//   MF: peak, 6 freqs (360, 700, 1600, 3200, 4800, 7200 Hz), ±18 dB
//       Frequency-dependent Q: 1.5@360Hz → 3.0@7200Hz
//   HF: shelf, FIXED 12kHz, ±16 dB (NOT selectable)
//   Transformers: Marinair, iron core, subtle LF bump
//   Class-A saturation: subtle 2nd/3rd harmonic, ~0.5-1% THD

/// Neve 1073 style EQ — UAD-faithful implementation
///
/// Full 4-band topology: HPF + LF shelf + MF peak + HF shelf
/// MF band is integral part of the DSP (not a wrapper add-on)
#[derive(Debug, Clone)]
pub struct Neve1073 {
    sample_rate: f64,

    // High-pass filter (18dB/oct = 3 cascaded 1st-order sections)
    hp_enabled: bool,
    hp_freq: Neve1073HpFreq,

    // Low shelf
    low_gain: f64,
    low_freq: Neve1073LowFreq,

    // Mid peak — integral part of Neve 1073 (not wrapper addon)
    mid_gain: f64,
    mid_freq: Neve1073MidFreq,

    // High shelf — FIXED at 12kHz per UAD spec
    high_gain: f64,

    // Filters
    hp_filter_1: NeveInductorFilter, // 18dB/oct = 3 cascaded 2nd-order sections
    hp_filter_2: NeveInductorFilter, // (actually 3x 6dB/oct 1-pole, but we use
    hp_filter_3: NeveInductorFilter, // 3x biquad for better numerical stability)
    low_filter: NeveInductorFilter,
    mid_filter: NeveInductorFilter,
    high_filter: NeveInductorFilter,

    // Class-A saturation stage
    class_a_sat: ClassASaturation,

    // Marinair transformers
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

/// Neve 1073 MF frequency selections — UAD 6-position switch
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Neve1073MidFreq {
    Hz360,
    Hz700,
    #[default]
    K1_6,
    K3_2,
    K4_8,
    K7_2,
}

impl Neve1073MidFreq {
    pub fn hz(&self) -> f64 {
        match self {
            Neve1073MidFreq::Hz360 => 360.0,
            Neve1073MidFreq::Hz700 => 700.0,
            Neve1073MidFreq::K1_6 => 1600.0,
            Neve1073MidFreq::K3_2 => 3200.0,
            Neve1073MidFreq::K4_8 => 4800.0,
            Neve1073MidFreq::K7_2 => 7200.0,
        }
    }

    /// UAD-faithful frequency-dependent Q
    /// Lower frequencies → wider Q (inductor topology)
    /// 360Hz: Q=1.5, 7200Hz: Q=3.0
    pub fn q(&self) -> f64 {
        match self {
            Neve1073MidFreq::Hz360 => 1.5,
            Neve1073MidFreq::Hz700 => 1.8,
            Neve1073MidFreq::K1_6 => 2.0,
            Neve1073MidFreq::K3_2 => 2.3,
            Neve1073MidFreq::K4_8 => 2.6,
            Neve1073MidFreq::K7_2 => 3.0,
        }
    }
}

/// NOTE: Neve1073HighFreq enum is REMOVED.
/// The real Neve 1073 HF shelf is FIXED at 12kHz — not selectable.
/// We keep a constant for clarity.
const NEVE_1073_HF_FREQ: f64 = 12000.0;

/// Neve inductor-based filter — TDF-II biquad
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
        Self {
            b0: 1.0,
            ..Self::default()
        }
    }

    /// High-pass — one section of the 18dB/oct cascade
    /// Uses Butterworth alignment (Q=0.707 per section)
    fn set_highpass(&mut self, freq: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Butterworth Q for each cascaded section
        let q = 0.707;
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
        if gain_db.abs() < 0.01 {
            self.b0 = 1.0;
            self.b1 = 0.0;
            self.b2 = 0.0;
            self.a1 = 0.0;
            self.a2 = 0.0;
            return;
        }
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Inductor Q — smooth transitions
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

    /// High shelf with inductor characteristics — used for fixed 12kHz Neve HF
    fn set_high_shelf(&mut self, freq: f64, gain_db: f64, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            self.b0 = 1.0;
            self.b1 = 0.0;
            self.b2 = 0.0;
            self.a1 = 0.0;
            self.a2 = 0.0;
            return;
        }
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();

        // Neve high shelf is gentle
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

    /// Peak filter with configurable Q — for MF band
    fn set_peak(&mut self, freq: f64, gain_db: f64, q: f64, sample_rate: f64) {
        if gain_db.abs() < 0.01 {
            self.b0 = 1.0;
            self.b1 = 0.0;
            self.b2 = 0.0;
            self.a1 = 0.0;
            self.a2 = 0.0;
            return;
        }
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let alpha = sin_w / (2.0 * q);
        let a = 10.0_f64.powf(gain_db / 40.0);

        let a0 = 1.0 + alpha / a;
        self.b0 = (1.0 + alpha * a) / a0;
        self.b1 = (-2.0 * cos_w) / a0;
        self.b2 = (1.0 - alpha * a) / a0;
        self.a1 = self.b1;
        self.a2 = (1.0 - alpha / a) / a0;
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

/// Class-A discrete saturation — Neve 1073 style
/// Subtle 2nd/3rd harmonic content, ~0.5-1% THD
#[derive(Debug, Clone)]
pub struct ClassASaturation {
    /// Amount (0-1)
    pub amount: f64,
    dc_state: f64,
    dc_prev_in: f64,
}

impl Default for ClassASaturation {
    fn default() -> Self {
        Self {
            amount: 0.3,
            dc_state: 0.0,
            dc_prev_in: 0.0,
        }
    }
}

impl ClassASaturation {
    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        // Class-A: asymmetric waveshaping (2nd + 3rd harmonic)
        let x = input * (1.0 + self.amount * 0.5);

        // Asymmetric: positive half slightly compressed, negative half slightly expanded
        let saturated = if x >= 0.0 {
            x - self.amount * 0.05 * x * x // 2nd harmonic (even)
        } else {
            x + self.amount * 0.03 * x * x * x.signum() // 3rd harmonic character
        };

        // DC blocker
        let dc_coeff = 0.9995;
        self.dc_state = saturated - self.dc_prev_in + dc_coeff * self.dc_state;
        self.dc_prev_in = saturated;

        self.dc_state
    }

    pub fn reset(&mut self) {
        self.dc_state = 0.0;
        self.dc_prev_in = 0.0;
    }
}

/// Neve Marinair transformer with iron saturation
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

        // Iron core saturation (asymmetric — Marinair character)
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

        // Sanitize
        if !self.lp_state.is_finite() {
            self.lp_state = 0.0;
        }
        if !self.hp_state.is_finite() {
            self.hp_state = 0.0;
        }

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
            mid_gain: 0.0,
            mid_freq: Neve1073MidFreq::default(),
            high_gain: 0.0,
            hp_filter_1: NeveInductorFilter::new(),
            hp_filter_2: NeveInductorFilter::new(),
            hp_filter_3: NeveInductorFilter::new(),
            low_filter: NeveInductorFilter::new(),
            mid_filter: NeveInductorFilter::new(),
            high_filter: NeveInductorFilter::new(),
            class_a_sat: ClassASaturation::default(),
            input_transformer: NeveTransformer::new(sample_rate),
            output_transformer: NeveTransformer::new(sample_rate),
        };
        eq.hp_filter_1.set_highpass(eq.hp_freq.hz(), sample_rate);
        eq.hp_filter_2.set_highpass(eq.hp_freq.hz(), sample_rate);
        eq.hp_filter_3.set_highpass(eq.hp_freq.hz(), sample_rate);
        eq
    }

    pub fn set_hp(&mut self, enabled: bool, freq: Neve1073HpFreq) {
        self.hp_enabled = enabled;
        self.hp_freq = freq;
        // 18dB/oct = 3 cascaded 2nd-order HP sections
        self.hp_filter_1.set_highpass(freq.hz(), self.sample_rate);
        self.hp_filter_2.set_highpass(freq.hz(), self.sample_rate);
        self.hp_filter_3.set_highpass(freq.hz(), self.sample_rate);
    }

    pub fn set_low(&mut self, gain_db: f64, freq: Neve1073LowFreq) {
        self.low_gain = gain_db.clamp(-16.0, 16.0);
        self.low_freq = freq;
        self.low_filter
            .set_low_shelf(freq.hz(), self.low_gain, self.sample_rate);
    }

    /// Set MF peak band — integral Neve 1073 band with frequency-dependent Q
    pub fn set_mid(&mut self, gain_db: f64, freq: Neve1073MidFreq) {
        self.mid_gain = gain_db.clamp(-18.0, 18.0);
        self.mid_freq = freq;
        self.mid_filter
            .set_peak(freq.hz(), self.mid_gain, freq.q(), self.sample_rate);
    }

    /// Set HF shelf — FIXED at 12kHz per UAD Neve 1073 spec
    pub fn set_high(&mut self, gain_db: f64) {
        self.high_gain = gain_db.clamp(-16.0, 16.0);
        self.high_filter
            .set_high_shelf(NEVE_1073_HF_FREQ, self.high_gain, self.sample_rate);
    }

    /// Legacy compatibility — accepts freq enum but ignores it (HF is always 12kHz)
    pub fn set_high_with_freq(&mut self, gain_db: f64, _freq: Neve1073HpFreq) {
        self.set_high(gain_db);
    }

    #[inline(always)]
    fn process_sample_internal(&mut self, input: f64) -> f64 {
        // Input transformer (Marinair)
        let xfmr_in = self.input_transformer.process(input);

        // 18dB/oct HPF (3 cascaded sections) — if enabled
        let hp_out = if self.hp_enabled {
            let s1 = self.hp_filter_1.process(xfmr_in);
            let s2 = self.hp_filter_2.process(s1);
            self.hp_filter_3.process(s2)
        } else {
            xfmr_in
        };

        // LF shelf
        let low = self.low_filter.process(hp_out);

        // MF peak (with frequency-dependent Q)
        let mid = self.mid_filter.process(low);

        // HF shelf (fixed 12kHz)
        let high = self.high_filter.process(mid);

        // Class-A saturation
        let sat = self.class_a_sat.process(high);

        // Output transformer
        self.output_transformer.process(sat)
    }
}

impl Processor for Neve1073 {
    fn reset(&mut self) {
        self.hp_filter_1.reset();
        self.hp_filter_2.reset();
        self.hp_filter_3.reset();
        self.low_filter.reset();
        self.mid_filter.reset();
        self.high_filter.reset();
        self.class_a_sat.reset();
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
// STEREO VARIANTS — Dual-mono wrappers
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

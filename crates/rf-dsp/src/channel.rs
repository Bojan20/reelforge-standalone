//! Channel strip processor
//!
//! Complete channel strip combining:
//! - Input gain/trim
//! - High-pass filter
//! - Gate/Expander
//! - Compressor
//! - 4-band EQ (like analog console)
//! - Parametric EQ (optional)
//! - Limiter
//! - Spatial (pan, width)
//! - Output gain
//! - Metering

use rf_core::Sample;

use crate::analysis::PeakMeter;
use crate::biquad::{BiquadCoeffs, BiquadTDF2};
use crate::dynamics::{Compressor, CompressorType, Gate, Limiter};
use crate::spatial::{PanLaw, StereoPanner, StereoWidth};
use crate::{MonoProcessor, Processor, ProcessorConfig, StereoProcessor};

/// Simple 4-band console-style EQ
#[derive(Debug, Clone)]
pub struct ConsoleEq {
    // Low shelf
    low: BiquadTDF2,
    low_freq: f64,
    low_gain: f64,

    // Low-mid parametric
    low_mid: BiquadTDF2,
    low_mid_freq: f64,
    low_mid_gain: f64,
    low_mid_q: f64,

    // High-mid parametric
    high_mid: BiquadTDF2,
    high_mid_freq: f64,
    high_mid_gain: f64,
    high_mid_q: f64,

    // High shelf
    high: BiquadTDF2,
    high_freq: f64,
    high_gain: f64,

    sample_rate: f64,
}

impl ConsoleEq {
    pub fn new(sample_rate: f64) -> Self {
        let mut eq = Self {
            low: BiquadTDF2::new(sample_rate),
            low_freq: 80.0,
            low_gain: 0.0,
            low_mid: BiquadTDF2::new(sample_rate),
            low_mid_freq: 400.0,
            low_mid_gain: 0.0,
            low_mid_q: 1.0,
            high_mid: BiquadTDF2::new(sample_rate),
            high_mid_freq: 3000.0,
            high_mid_gain: 0.0,
            high_mid_q: 1.0,
            high: BiquadTDF2::new(sample_rate),
            high_freq: 12000.0,
            high_gain: 0.0,
            sample_rate,
        };
        eq.update_coeffs();
        eq
    }

    pub fn set_low(&mut self, freq: f64, gain_db: f64) {
        self.low_freq = freq.clamp(20.0, 500.0);
        self.low_gain = gain_db.clamp(-15.0, 15.0);
        self.low.set_coeffs(BiquadCoeffs::low_shelf(
            self.low_freq,
            0.707,
            self.low_gain,
            self.sample_rate,
        ));
    }

    pub fn set_low_mid(&mut self, freq: f64, gain_db: f64, q: f64) {
        self.low_mid_freq = freq.clamp(100.0, 2000.0);
        self.low_mid_gain = gain_db.clamp(-15.0, 15.0);
        self.low_mid_q = q.clamp(0.3, 10.0);
        self.low_mid.set_coeffs(BiquadCoeffs::peaking(
            self.low_mid_freq,
            self.low_mid_q,
            self.low_mid_gain,
            self.sample_rate,
        ));
    }

    pub fn set_high_mid(&mut self, freq: f64, gain_db: f64, q: f64) {
        self.high_mid_freq = freq.clamp(500.0, 10000.0);
        self.high_mid_gain = gain_db.clamp(-15.0, 15.0);
        self.high_mid_q = q.clamp(0.3, 10.0);
        self.high_mid.set_coeffs(BiquadCoeffs::peaking(
            self.high_mid_freq,
            self.high_mid_q,
            self.high_mid_gain,
            self.sample_rate,
        ));
    }

    pub fn set_high(&mut self, freq: f64, gain_db: f64) {
        self.high_freq = freq.clamp(2000.0, 20000.0);
        self.high_gain = gain_db.clamp(-15.0, 15.0);
        self.high.set_coeffs(BiquadCoeffs::high_shelf(
            self.high_freq,
            0.707,
            self.high_gain,
            self.sample_rate,
        ));
    }

    fn update_coeffs(&mut self) {
        self.low.set_coeffs(BiquadCoeffs::low_shelf(
            self.low_freq,
            0.707,
            self.low_gain,
            self.sample_rate,
        ));
        self.low_mid.set_coeffs(BiquadCoeffs::peaking(
            self.low_mid_freq,
            self.low_mid_q,
            self.low_mid_gain,
            self.sample_rate,
        ));
        self.high_mid.set_coeffs(BiquadCoeffs::peaking(
            self.high_mid_freq,
            self.high_mid_q,
            self.high_mid_gain,
            self.sample_rate,
        ));
        self.high.set_coeffs(BiquadCoeffs::high_shelf(
            self.high_freq,
            0.707,
            self.high_gain,
            self.sample_rate,
        ));
    }

    #[inline]
    pub fn process(&mut self, sample: Sample) -> Sample {
        let mut out = self.low.process_sample(sample);
        out = self.low_mid.process_sample(out);
        out = self.high_mid.process_sample(out);
        out = self.high.process_sample(out);
        out
    }

    pub fn reset(&mut self) {
        self.low.reset();
        self.low_mid.reset();
        self.high_mid.reset();
        self.high.reset();
    }
}

/// Channel strip processing order
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum ProcessingOrder {
    /// Gate → Compressor → EQ (typical live sound)
    #[default]
    GateCompEq,
    /// Gate → EQ → Compressor (studio mixing)
    GateEqComp,
    /// EQ → Gate → Compressor
    EqGateComp,
    /// EQ → Compressor → Gate
    EqCompGate,
}

/// Complete stereo channel strip
#[derive(Debug)]
pub struct ChannelStrip {
    // Gain staging
    input_gain: f64,
    output_gain: f64,

    // High-pass filter
    hpf_enabled: bool,
    hpf_l: BiquadTDF2,
    hpf_r: BiquadTDF2,
    hpf_freq: f64,

    // Gate
    gate_enabled: bool,
    gate_l: Gate,
    gate_r: Gate,

    // Compressor
    comp_enabled: bool,
    comp_l: Compressor,
    comp_r: Compressor,
    comp_link: f64, // 0.0 = independent, 1.0 = linked

    // EQ
    eq_enabled: bool,
    eq_l: ConsoleEq,
    eq_r: ConsoleEq,

    // Limiter
    limiter_enabled: bool,
    limiter_l: Limiter,
    limiter_r: Limiter,

    // Spatial
    panner: StereoPanner,
    width: StereoWidth,

    // Processing order
    order: ProcessingOrder,

    // Metering
    input_peak_l: PeakMeter,
    input_peak_r: PeakMeter,
    output_peak_l: PeakMeter,
    output_peak_r: PeakMeter,

    // State
    solo: bool,
    mute: bool,
    sample_rate: f64,
}

impl ChannelStrip {
    pub fn new(sample_rate: f64) -> Self {
        let mut hpf_l = BiquadTDF2::new(sample_rate);
        let mut hpf_r = BiquadTDF2::new(sample_rate);
        hpf_l.set_highpass(80.0, 0.707);
        hpf_r.set_highpass(80.0, 0.707);

        Self {
            input_gain: 1.0,
            output_gain: 1.0,
            hpf_enabled: false,
            hpf_l,
            hpf_r,
            hpf_freq: 80.0,
            gate_enabled: false,
            gate_l: Gate::new(sample_rate),
            gate_r: Gate::new(sample_rate),
            comp_enabled: false,
            comp_l: Compressor::new(sample_rate),
            comp_r: Compressor::new(sample_rate),
            comp_link: 1.0,
            eq_enabled: true,
            eq_l: ConsoleEq::new(sample_rate),
            eq_r: ConsoleEq::new(sample_rate),
            limiter_enabled: false,
            limiter_l: Limiter::new(sample_rate),
            limiter_r: Limiter::new(sample_rate),
            panner: StereoPanner::new(),
            width: StereoWidth::new(),
            order: ProcessingOrder::GateCompEq,
            input_peak_l: PeakMeter::new(sample_rate),
            input_peak_r: PeakMeter::new(sample_rate),
            output_peak_l: PeakMeter::new(sample_rate),
            output_peak_r: PeakMeter::new(sample_rate),
            solo: false,
            mute: false,
            sample_rate,
        }
    }

    // Gain controls
    pub fn set_input_gain_db(&mut self, db: f64) {
        self.input_gain = 10.0_f64.powf(db.clamp(-24.0, 24.0) / 20.0);
    }

    pub fn set_output_gain_db(&mut self, db: f64) {
        self.output_gain = 10.0_f64.powf(db.clamp(-96.0, 12.0) / 20.0);
    }

    // HPF
    pub fn set_hpf_enabled(&mut self, enabled: bool) {
        self.hpf_enabled = enabled;
    }

    pub fn set_hpf_freq(&mut self, freq: f64) {
        self.hpf_freq = freq.clamp(20.0, 500.0);
        self.hpf_l.set_highpass(self.hpf_freq, 0.707);
        self.hpf_r.set_highpass(self.hpf_freq, 0.707);
    }

    // Gate controls
    pub fn set_gate_enabled(&mut self, enabled: bool) {
        self.gate_enabled = enabled;
    }

    pub fn set_gate_threshold(&mut self, db: f64) {
        self.gate_l.set_threshold(db);
        self.gate_r.set_threshold(db);
    }

    // Compressor controls
    pub fn set_comp_enabled(&mut self, enabled: bool) {
        self.comp_enabled = enabled;
    }

    pub fn set_comp_type(&mut self, comp_type: CompressorType) {
        self.comp_l.set_type(comp_type);
        self.comp_r.set_type(comp_type);
    }

    pub fn set_comp_threshold(&mut self, db: f64) {
        self.comp_l.set_threshold(db);
        self.comp_r.set_threshold(db);
    }

    pub fn set_comp_ratio(&mut self, ratio: f64) {
        self.comp_l.set_ratio(ratio);
        self.comp_r.set_ratio(ratio);
    }

    pub fn set_comp_attack(&mut self, ms: f64) {
        self.comp_l.set_attack(ms);
        self.comp_r.set_attack(ms);
    }

    pub fn set_comp_release(&mut self, ms: f64) {
        self.comp_l.set_release(ms);
        self.comp_r.set_release(ms);
    }

    pub fn set_comp_makeup(&mut self, db: f64) {
        self.comp_l.set_makeup(db);
        self.comp_r.set_makeup(db);
    }

    pub fn set_comp_link(&mut self, link: f64) {
        self.comp_link = link.clamp(0.0, 1.0);
    }

    // EQ controls
    pub fn set_eq_enabled(&mut self, enabled: bool) {
        self.eq_enabled = enabled;
    }

    pub fn set_eq_low(&mut self, freq: f64, gain_db: f64) {
        self.eq_l.set_low(freq, gain_db);
        self.eq_r.set_low(freq, gain_db);
    }

    pub fn set_eq_low_mid(&mut self, freq: f64, gain_db: f64, q: f64) {
        self.eq_l.set_low_mid(freq, gain_db, q);
        self.eq_r.set_low_mid(freq, gain_db, q);
    }

    pub fn set_eq_high_mid(&mut self, freq: f64, gain_db: f64, q: f64) {
        self.eq_l.set_high_mid(freq, gain_db, q);
        self.eq_r.set_high_mid(freq, gain_db, q);
    }

    pub fn set_eq_high(&mut self, freq: f64, gain_db: f64) {
        self.eq_l.set_high(freq, gain_db);
        self.eq_r.set_high(freq, gain_db);
    }

    // Limiter controls
    pub fn set_limiter_enabled(&mut self, enabled: bool) {
        self.limiter_enabled = enabled;
    }

    pub fn set_limiter_threshold(&mut self, db: f64) {
        self.limiter_l.set_threshold(db);
        self.limiter_r.set_threshold(db);
    }

    // Spatial controls
    pub fn set_pan(&mut self, pan: f64) {
        self.panner.set_pan(pan);
    }

    pub fn set_pan_law(&mut self, law: PanLaw) {
        self.panner.set_pan_law(law);
    }

    pub fn set_width(&mut self, width: f64) {
        self.width.set_width(width);
    }

    // Solo/Mute
    pub fn set_solo(&mut self, solo: bool) {
        self.solo = solo;
    }

    pub fn set_mute(&mut self, mute: bool) {
        self.mute = mute;
    }

    pub fn is_solo(&self) -> bool {
        self.solo
    }

    pub fn is_mute(&self) -> bool {
        self.mute
    }

    // Processing order
    pub fn set_processing_order(&mut self, order: ProcessingOrder) {
        self.order = order;
    }

    // Metering
    pub fn input_peak_db(&self) -> (f64, f64) {
        (
            self.input_peak_l.current_db(),
            self.input_peak_r.current_db(),
        )
    }

    pub fn output_peak_db(&self) -> (f64, f64) {
        (
            self.output_peak_l.current_db(),
            self.output_peak_r.current_db(),
        )
    }

    pub fn gain_reduction_db(&self) -> f64 {
        (self.comp_l.gain_reduction_db() + self.comp_r.gain_reduction_db()) * 0.5
    }

    /// Process gate for both channels
    #[inline]
    fn process_gate(&mut self, l: Sample, r: Sample) -> (Sample, Sample) {
        if self.gate_enabled {
            (self.gate_l.process_sample(l), self.gate_r.process_sample(r))
        } else {
            (l, r)
        }
    }

    /// Process compressor for both channels
    #[inline]
    fn process_comp(&mut self, l: Sample, r: Sample) -> (Sample, Sample) {
        if !self.comp_enabled {
            return (l, r);
        }

        if self.comp_link >= 0.99 {
            // Fully linked
            let max_input = l.abs().max(r.abs());
            let _ = self.comp_l.process_sample(max_input);
            let gain = 10.0_f64.powf(-self.comp_l.gain_reduction_db() / 20.0);
            (l * gain, r * gain)
        } else if self.comp_link <= 0.01 {
            // Independent
            (self.comp_l.process_sample(l), self.comp_r.process_sample(r))
        } else {
            // Partial link
            let out_l = self.comp_l.process_sample(l);
            let out_r = self.comp_r.process_sample(r);

            let max_gr = self
                .comp_l
                .gain_reduction_db()
                .max(self.comp_r.gain_reduction_db());
            let linked_gain = 10.0_f64.powf(-max_gr / 20.0);

            (
                out_l * (1.0 - self.comp_link) + l * linked_gain * self.comp_link,
                out_r * (1.0 - self.comp_link) + r * linked_gain * self.comp_link,
            )
        }
    }

    /// Process EQ for both channels
    #[inline]
    fn process_eq(&mut self, l: Sample, r: Sample) -> (Sample, Sample) {
        if self.eq_enabled {
            (self.eq_l.process(l), self.eq_r.process(r))
        } else {
            (l, r)
        }
    }
}

impl Processor for ChannelStrip {
    fn reset(&mut self) {
        self.hpf_l.reset();
        self.hpf_r.reset();
        self.gate_l.reset();
        self.gate_r.reset();
        self.comp_l.reset();
        self.comp_r.reset();
        self.eq_l.reset();
        self.eq_r.reset();
        self.limiter_l.reset();
        self.limiter_r.reset();
        self.panner.reset();
        self.width.reset();
        self.input_peak_l.reset();
        self.input_peak_r.reset();
        self.output_peak_l.reset();
        self.output_peak_r.reset();
    }

    fn latency(&self) -> usize {
        let mut lat = 0;
        if self.limiter_enabled {
            lat += self.limiter_l.latency();
        }
        lat
    }
}

impl StereoProcessor for ChannelStrip {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Mute check
        if self.mute {
            return (0.0, 0.0);
        }

        // Input gain
        let mut l = left * self.input_gain;
        let mut r = right * self.input_gain;

        // Input metering
        self.input_peak_l.process(l);
        self.input_peak_r.process(r);

        // High-pass filter
        if self.hpf_enabled {
            l = self.hpf_l.process_sample(l);
            r = self.hpf_r.process_sample(r);
        }

        // Processing chain based on order
        match self.order {
            ProcessingOrder::GateCompEq => {
                (l, r) = self.process_gate(l, r);
                (l, r) = self.process_comp(l, r);
                (l, r) = self.process_eq(l, r);
            }
            ProcessingOrder::GateEqComp => {
                (l, r) = self.process_gate(l, r);
                (l, r) = self.process_eq(l, r);
                (l, r) = self.process_comp(l, r);
            }
            ProcessingOrder::EqGateComp => {
                (l, r) = self.process_eq(l, r);
                (l, r) = self.process_gate(l, r);
                (l, r) = self.process_comp(l, r);
            }
            ProcessingOrder::EqCompGate => {
                (l, r) = self.process_eq(l, r);
                (l, r) = self.process_comp(l, r);
                (l, r) = self.process_gate(l, r);
            }
        }

        // Limiter
        if self.limiter_enabled {
            l = self.limiter_l.process_sample(l);
            r = self.limiter_r.process_sample(r);
        }

        // Stereo width
        (l, r) = self.width.process_sample(l, r);

        // Panning
        (l, r) = self.panner.process_sample(l, r);

        // Output gain
        l *= self.output_gain;
        r *= self.output_gain;

        // Output metering
        self.output_peak_l.process(l);
        self.output_peak_r.process(r);

        (l, r)
    }
}

impl ProcessorConfig for ChannelStrip {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;

        self.hpf_l.set_sample_rate(sample_rate);
        self.hpf_r.set_sample_rate(sample_rate);
        self.hpf_l.set_highpass(self.hpf_freq, 0.707);
        self.hpf_r.set_highpass(self.hpf_freq, 0.707);

        self.gate_l.set_sample_rate(sample_rate);
        self.gate_r.set_sample_rate(sample_rate);

        self.comp_l.set_sample_rate(sample_rate);
        self.comp_r.set_sample_rate(sample_rate);

        self.eq_l = ConsoleEq::new(sample_rate);
        self.eq_r = ConsoleEq::new(sample_rate);

        self.limiter_l.set_sample_rate(sample_rate);
        self.limiter_r.set_sample_rate(sample_rate);

        self.input_peak_l = PeakMeter::new(sample_rate);
        self.input_peak_r = PeakMeter::new(sample_rate);
        self.output_peak_l = PeakMeter::new(sample_rate);
        self.output_peak_r = PeakMeter::new(sample_rate);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_channel_strip_passthrough() {
        let mut strip = ChannelStrip::new(48000.0);

        // Disable all processing
        strip.set_hpf_enabled(false);
        strip.set_gate_enabled(false);
        strip.set_comp_enabled(false);
        strip.set_eq_enabled(false);
        strip.set_limiter_enabled(false);

        // Should pass through unchanged (panner/width at defaults)
        let (l, r) = strip.process_sample(0.5, 0.5);

        // Panner at center mono-sums, so both should be equal
        assert!((l - r).abs() < 0.01);
    }

    #[test]
    fn test_channel_strip_mute() {
        let mut strip = ChannelStrip::new(48000.0);
        strip.set_mute(true);

        let (l, r) = strip.process_sample(1.0, 1.0);
        assert_eq!(l, 0.0);
        assert_eq!(r, 0.0);
    }

    #[test]
    fn test_channel_strip_gain() {
        let mut strip = ChannelStrip::new(48000.0);
        strip.set_eq_enabled(false);
        strip.set_input_gain_db(6.0); // ~2x

        // Process to warm up meters
        for _ in 0..100 {
            strip.process_sample(0.25, 0.25);
        }

        // Input peak should show boosted level
        let (peak_l, _) = strip.input_peak_db();
        assert!(peak_l > -15.0); // 0.25 * 2 = 0.5 ≈ -6dB
    }

    #[test]
    fn test_console_eq() {
        let mut eq = ConsoleEq::new(48000.0);
        eq.set_low(100.0, 6.0);
        eq.set_high(10000.0, -3.0);

        // Process some samples
        for _ in 0..1000 {
            let _ = eq.process(0.5);
        }
    }
}

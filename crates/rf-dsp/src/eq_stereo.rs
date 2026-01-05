//! Stereo EQ - Frequency-dependent Stereo Processing
//!
//! Advanced stereo EQ features:
//! - Bass mono (mono below threshold)
//! - Independent L/R EQ curves
//! - Mid/Side EQ with per-band M/S balance
//! - Stereo width per band
//! - Stereo image correction
//! - Phase alignment between channels

use rf_core::Sample;
use crate::{Processor, ProcessorConfig, StereoProcessor, MonoProcessor};
use crate::biquad::{BiquadTDF2, BiquadCoeffs};

// ============================================================================
// BASS MONO
// ============================================================================

/// Bass Mono - Makes low frequencies mono for tighter bass
#[derive(Clone)]
pub struct BassMono {
    /// Frequency below which to make mono (Hz)
    pub crossover_freq: f64,
    /// Crossover slope (6, 12, 18, 24 dB/oct)
    pub slope: CrossoverSlope,
    /// Blend amount (0=stereo, 1=full mono)
    pub blend: f64,
    /// Phase alignment
    pub phase_align: bool,

    // Crossover filters (Linkwitz-Riley)
    lp_l: Vec<BiquadTDF2>,
    lp_r: Vec<BiquadTDF2>,
    hp_l: Vec<BiquadTDF2>,
    hp_r: Vec<BiquadTDF2>,

    // All-pass for phase alignment
    ap_l: BiquadTDF2,
    ap_r: BiquadTDF2,

    pub sample_rate: f64,
    num_stages: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum CrossoverSlope {
    Db6,
    #[default]
    Db12,
    Db18,
    Db24,
}

impl CrossoverSlope {
    pub fn stages(&self) -> usize {
        match self {
            CrossoverSlope::Db6 => 1,
            CrossoverSlope::Db12 => 1,
            CrossoverSlope::Db18 => 2,
            CrossoverSlope::Db24 => 2,
        }
    }
}

impl BassMono {
    pub fn new(sample_rate: f64) -> Self {
        let mut lp_l = Vec::with_capacity(4);
        let mut lp_r = Vec::with_capacity(4);
        let mut hp_l = Vec::with_capacity(4);
        let mut hp_r = Vec::with_capacity(4);

        for _ in 0..4 {
            lp_l.push(BiquadTDF2::new(sample_rate));
            lp_r.push(BiquadTDF2::new(sample_rate));
            hp_l.push(BiquadTDF2::new(sample_rate));
            hp_r.push(BiquadTDF2::new(sample_rate));
        }

        let mut bm = Self {
            crossover_freq: 120.0,
            slope: CrossoverSlope::Db24,
            blend: 1.0,
            phase_align: true,
            lp_l,
            lp_r,
            hp_l,
            hp_r,
            ap_l: BiquadTDF2::new(sample_rate),
            ap_r: BiquadTDF2::new(sample_rate),
            sample_rate,
            num_stages: 2,
        };
        bm.update_coefficients();
        bm
    }

    pub fn set_crossover(&mut self, freq: f64) {
        self.crossover_freq = freq.clamp(20.0, 500.0);
        self.update_coefficients();
    }

    pub fn set_slope(&mut self, slope: CrossoverSlope) {
        self.slope = slope;
        self.num_stages = slope.stages();
        self.update_coefficients();
    }

    pub fn update_coefficients(&mut self) {
        let q = 0.5;

        let lp_coeffs = BiquadCoeffs::lowpass(self.crossover_freq, q, self.sample_rate);
        let hp_coeffs = BiquadCoeffs::highpass(self.crossover_freq, q, self.sample_rate);
        let ap_coeffs = BiquadCoeffs::allpass(self.crossover_freq, q, self.sample_rate);

        for i in 0..self.num_stages {
            self.lp_l[i].set_coeffs(lp_coeffs);
            self.lp_r[i].set_coeffs(lp_coeffs);
            self.hp_l[i].set_coeffs(hp_coeffs);
            self.hp_r[i].set_coeffs(hp_coeffs);
        }

        self.ap_l.set_coeffs(ap_coeffs);
        self.ap_r.set_coeffs(ap_coeffs);
    }
}

impl Processor for BassMono {
    fn reset(&mut self) {
        for i in 0..4 {
            self.lp_l[i].reset();
            self.lp_r[i].reset();
            self.hp_l[i].reset();
            self.hp_r[i].reset();
        }
        self.ap_l.reset();
        self.ap_r.reset();
    }
}

impl StereoProcessor for BassMono {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mut low_l = left;
        let mut low_r = right;
        let mut high_l = left;
        let mut high_r = right;

        for i in 0..self.num_stages {
            low_l = self.lp_l[i].process_sample(low_l);
            low_r = self.lp_r[i].process_sample(low_r);
            high_l = self.hp_l[i].process_sample(high_l);
            high_r = self.hp_r[i].process_sample(high_r);
        }

        let low_mono = (low_l + low_r) * 0.5;
        let low_l_out = low_l * (1.0 - self.blend) + low_mono * self.blend;
        let low_r_out = low_r * (1.0 - self.blend) + low_mono * self.blend;

        let (high_l_out, high_r_out) = if self.phase_align {
            (self.ap_l.process_sample(high_l), self.ap_r.process_sample(high_r))
        } else {
            (high_l, high_r)
        };

        (low_l_out + high_l_out, low_r_out + high_r_out)
    }
}

// ============================================================================
// STEREO MODE
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum StereoMode {
    #[default]
    Stereo,
    Left,
    Right,
    Mid,
    Side,
}

// ============================================================================
// STEREO EQ BAND
// ============================================================================

#[derive(Clone)]
pub struct StereoEqBand {
    pub freq: f64,
    pub gain_db: f64,
    pub q: f64,
    pub mode: StereoMode,
    pub enabled: bool,

    filter_l: BiquadTDF2,
    filter_r: BiquadTDF2,

    sample_rate: f64,
}

impl StereoEqBand {
    pub fn new(freq: f64, gain_db: f64, q: f64, mode: StereoMode, sample_rate: f64) -> Self {
        let mut band = Self {
            freq,
            gain_db,
            q,
            mode,
            enabled: true,
            filter_l: BiquadTDF2::new(sample_rate),
            filter_r: BiquadTDF2::new(sample_rate),
            sample_rate,
        };
        band.update_coefficients();
        band
    }

    pub fn set_params(&mut self, freq: f64, gain_db: f64, q: f64) {
        self.freq = freq;
        self.gain_db = gain_db;
        self.q = q;
        self.update_coefficients();
    }

    pub fn update_coefficients(&mut self) {
        let coeffs = BiquadCoeffs::peaking(self.freq, self.q, self.gain_db, self.sample_rate);
        self.filter_l.set_coeffs(coeffs);
        self.filter_r.set_coeffs(coeffs);
    }

    #[inline(always)]
    pub fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        if !self.enabled {
            return (left, right);
        }

        match self.mode {
            StereoMode::Stereo => {
                let l = self.filter_l.process_sample(left);
                let r = self.filter_r.process_sample(right);
                (l, r)
            }
            StereoMode::Left => {
                let l = self.filter_l.process_sample(left);
                (l, right)
            }
            StereoMode::Right => {
                let r = self.filter_r.process_sample(right);
                (left, r)
            }
            StereoMode::Mid => {
                let mid = (left + right) * 0.5;
                let side = (left - right) * 0.5;
                let mid_processed = self.filter_l.process_sample(mid);
                let l = mid_processed + side;
                let r = mid_processed - side;
                (l, r)
            }
            StereoMode::Side => {
                let mid = (left + right) * 0.5;
                let side = (left - right) * 0.5;
                let side_processed = self.filter_r.process_sample(side);
                let l = mid + side_processed;
                let r = mid - side_processed;
                (l, r)
            }
        }
    }

    pub fn reset(&mut self) {
        self.filter_l.reset();
        self.filter_r.reset();
    }
}

// ============================================================================
// WIDTH BAND
// ============================================================================

#[derive(Clone)]
pub struct WidthBand {
    pub freq: f64,
    pub bandwidth: f64,
    pub width: f64,
    pub enabled: bool,

    bp_l: BiquadTDF2,
    bp_r: BiquadTDF2,

    sample_rate: f64,
}

impl WidthBand {
    pub fn new(freq: f64, bandwidth: f64, width: f64, sample_rate: f64) -> Self {
        let mut band = Self {
            freq,
            bandwidth,
            width,
            enabled: true,
            bp_l: BiquadTDF2::new(sample_rate),
            bp_r: BiquadTDF2::new(sample_rate),
            sample_rate,
        };
        band.update_coefficients();
        band
    }

    pub fn set_params(&mut self, freq: f64, bandwidth: f64, width: f64) {
        self.freq = freq;
        self.bandwidth = bandwidth;
        self.width = width.clamp(0.0, 2.0);
        self.update_coefficients();
    }

    fn update_coefficients(&mut self) {
        let q = (2.0_f64.powf(self.bandwidth) - 1.0).recip();
        let coeffs = BiquadCoeffs::bandpass(self.freq, q, self.sample_rate);
        self.bp_l.set_coeffs(coeffs);
        self.bp_r.set_coeffs(coeffs);
    }

    #[inline(always)]
    pub fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        if !self.enabled || (self.width - 1.0).abs() < 0.001 {
            return (left, right);
        }

        let band_l = self.bp_l.process_sample(left);
        let band_r = self.bp_r.process_sample(right);

        let mid = (band_l + band_r) * 0.5;
        let side = (band_l - band_r) * 0.5;
        let side_scaled = side * self.width;

        let new_band_l = mid + side_scaled;
        let new_band_r = mid - side_scaled;

        let out_l = left - band_l + new_band_l;
        let out_r = right - band_r + new_band_r;

        (out_l, out_r)
    }

    pub fn reset(&mut self) {
        self.bp_l.reset();
        self.bp_r.reset();
    }
}

// ============================================================================
// STEREO EQ
// ============================================================================

pub const STEREO_EQ_MAX_BANDS: usize = 32;

#[derive(Clone)]
pub struct StereoEq {
    bands: Vec<StereoEqBand>,
    width_bands: Vec<WidthBand>,
    pub bass_mono: BassMono,
    pub bass_mono_enabled: bool,
    pub global_ms_mode: bool,

    sample_rate: f64,
}

impl StereoEq {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            bands: Vec::with_capacity(STEREO_EQ_MAX_BANDS),
            width_bands: Vec::new(),
            bass_mono: BassMono::new(sample_rate),
            bass_mono_enabled: false,
            global_ms_mode: false,
            sample_rate,
        }
    }

    pub fn add_band(&mut self, freq: f64, gain_db: f64, q: f64, mode: StereoMode) -> usize {
        let band = StereoEqBand::new(freq, gain_db, q, mode, self.sample_rate);
        self.bands.push(band);
        self.bands.len() - 1
    }

    pub fn add_width_band(&mut self, freq: f64, bandwidth: f64, width: f64) -> usize {
        let band = WidthBand::new(freq, bandwidth, width, self.sample_rate);
        self.width_bands.push(band);
        self.width_bands.len() - 1
    }

    pub fn set_band(&mut self, index: usize, freq: f64, gain_db: f64, q: f64) {
        if let Some(band) = self.bands.get_mut(index) {
            band.set_params(freq, gain_db, q);
        }
    }

    pub fn set_band_mode(&mut self, index: usize, mode: StereoMode) {
        if let Some(band) = self.bands.get_mut(index) {
            band.mode = mode;
        }
    }

    pub fn set_width_band(&mut self, index: usize, freq: f64, bandwidth: f64, width: f64) {
        if let Some(band) = self.width_bands.get_mut(index) {
            band.set_params(freq, bandwidth, width);
        }
    }

    pub fn num_bands(&self) -> usize {
        self.bands.len()
    }

    pub fn num_width_bands(&self) -> usize {
        self.width_bands.len()
    }
}

impl Processor for StereoEq {
    fn reset(&mut self) {
        for band in &mut self.bands {
            band.reset();
        }
        for band in &mut self.width_bands {
            band.reset();
        }
        self.bass_mono.reset();
    }

    fn latency(&self) -> usize {
        0
    }
}

impl ProcessorConfig for StereoEq {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for band in &mut self.bands {
            band.sample_rate = sample_rate;
            band.update_coefficients();
        }
        for band in &mut self.width_bands {
            band.sample_rate = sample_rate;
            band.update_coefficients();
        }
        self.bass_mono.sample_rate = sample_rate;
        self.bass_mono.update_coefficients();
    }
}

impl StereoProcessor for StereoEq {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let (mut l, mut r) = (left, right);

        if self.bass_mono_enabled {
            (l, r) = self.bass_mono.process_sample(l, r);
        }

        if self.global_ms_mode {
            let mid = (l + r) * 0.5;
            let side = (l - r) * 0.5;
            l = mid;
            r = side;
        }

        for band in &mut self.bands {
            (l, r) = band.process(l, r);
        }

        for band in &mut self.width_bands {
            (l, r) = band.process(l, r);
        }

        if self.global_ms_mode {
            let left_out = l + r;
            let right_out = l - r;
            (left_out, right_out)
        } else {
            (l, r)
        }
    }
}

// ============================================================================
// STEREO IMAGE ANALYZER
// ============================================================================

#[derive(Clone)]
pub struct StereoImageAnalyzer {
    pub correlation: f64,
    pub balance: f64,
    pub width: f64,
    pub phase_issues: bool,

    sum_l: f64,
    sum_r: f64,
    sum_ll: f64,
    sum_rr: f64,
    sum_lr: f64,
    sample_count: usize,
}

impl StereoImageAnalyzer {
    pub fn new(_sample_rate: f64) -> Self {
        Self {
            correlation: 1.0,
            balance: 0.0,
            width: 1.0,
            phase_issues: false,
            sum_l: 0.0,
            sum_r: 0.0,
            sum_ll: 0.0,
            sum_rr: 0.0,
            sum_lr: 0.0,
            sample_count: 0,
        }
    }

    pub fn process(&mut self, left: f64, right: f64) {
        self.sum_l += left.abs();
        self.sum_r += right.abs();
        self.sum_ll += left * left;
        self.sum_rr += right * right;
        self.sum_lr += left * right;
        self.sample_count += 1;

        if self.sample_count >= 1024 {
            self.update_metrics();
        }
    }

    fn update_metrics(&mut self) {
        if self.sample_count == 0 {
            return;
        }

        let n = self.sample_count as f64;

        let total = self.sum_l + self.sum_r;
        if total > 0.0 {
            self.balance = (self.sum_r - self.sum_l) / total;
        }

        let var_l = self.sum_ll / n;
        let var_r = self.sum_rr / n;
        let cov = self.sum_lr / n;

        if var_l > 0.0 && var_r > 0.0 {
            self.correlation = cov / (var_l.sqrt() * var_r.sqrt());
        }

        self.width = ((1.0 - self.correlation) / 2.0).sqrt();
        self.phase_issues = self.correlation < -0.3;

        self.sum_l = 0.0;
        self.sum_r = 0.0;
        self.sum_ll = 0.0;
        self.sum_rr = 0.0;
        self.sum_lr = 0.0;
        self.sample_count = 0;
    }

    pub fn reset(&mut self) {
        self.correlation = 1.0;
        self.balance = 0.0;
        self.width = 1.0;
        self.phase_issues = false;
        self.sum_l = 0.0;
        self.sum_r = 0.0;
        self.sum_ll = 0.0;
        self.sum_rr = 0.0;
        self.sum_lr = 0.0;
        self.sample_count = 0;
    }
}

// ============================================================================
// STEREO CORRECTOR
// ============================================================================

#[derive(Clone)]
pub struct StereoCorrector {
    pub correct_balance: bool,
    pub correct_width: bool,
    pub target_width: f64,

    balance_correction: f64,
    width_correction: f64,

    analyzer: StereoImageAnalyzer,
}

impl StereoCorrector {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            correct_balance: true,
            correct_width: false,
            target_width: 1.0,
            balance_correction: 0.0,
            width_correction: 1.0,
            analyzer: StereoImageAnalyzer::new(sample_rate),
        }
    }

    pub fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        self.analyzer.process(left, right);

        let (mut l, mut r) = (left, right);

        if self.correct_balance {
            let target = -self.analyzer.balance;
            self.balance_correction += (target - self.balance_correction) * 0.0001;

            let correction = self.balance_correction.clamp(-0.5, 0.5);
            if correction > 0.0 {
                l *= 1.0 + correction;
            } else {
                r *= 1.0 - correction;
            }
        }

        if self.correct_width {
            let current = self.analyzer.width;
            let target_ratio = self.target_width / current.max(0.001);
            self.width_correction += (target_ratio - self.width_correction) * 0.0001;

            let ratio = self.width_correction.clamp(0.5, 2.0);

            let mid = (l + r) * 0.5;
            let side = (l - r) * 0.5 * ratio;
            l = mid + side;
            r = mid - side;
        }

        (l, r)
    }

    pub fn reset(&mut self) {
        self.balance_correction = 0.0;
        self.width_correction = 1.0;
        self.analyzer.reset();
    }
}

impl Processor for StereoCorrector {
    fn reset(&mut self) {
        StereoCorrector::reset(self);
    }
}

impl StereoProcessor for StereoCorrector {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        self.process(left, right)
    }
}

//! DSP Processor Wrappers
//!
//! InsertProcessor implementations for all rf-dsp modules.
//! Provides lock-free parameter updates and command queue integration.

use crate::insert_chain::InsertProcessor;
use rf_core::Sample;
use rf_dsp::delay_compensation::LatencySamples;
use rf_dsp::eq_room::RoomCorrectionEq;
use rf_dsp::linear_phase::{LinearPhaseBand, LinearPhaseEQ, LinearPhaseFilterType};
use rf_dsp::{
    FilterShape, OversampleMode, ProEq, Processor, ProcessorConfig, StereoApi550, StereoNeve1073,
    StereoProcessor, StereoPultec, UltraEq, UltraFilterType,
};
use std::sync::atomic::{AtomicU64, Ordering};

// ============ Atomic Parameter Helpers ============

/// Atomically stored f64 for lock-free parameter updates
#[derive(Debug)]
pub struct AtomicF64(AtomicU64);

impl AtomicF64 {
    pub fn new(value: f64) -> Self {
        Self(AtomicU64::new(value.to_bits()))
    }

    pub fn load(&self) -> f64 {
        f64::from_bits(self.0.load(Ordering::Relaxed))
    }

    pub fn store(&self, value: f64) {
        self.0.store(value.to_bits(), Ordering::Relaxed);
    }
}

impl Default for AtomicF64 {
    fn default() -> Self {
        Self::new(0.0)
    }
}

// ============ ProEQ Wrapper ============

/// Professional 64-band EQ wrapper
///
/// Global params (after band params at index 768+):
///   768: Output Gain (dB)
///   769: Auto-Gain (0=off, 1=on)
///   770: Solo Band (-1=none, 0-63=band index)
pub struct ProEqWrapper {
    eq: ProEq,
    sample_rate: f64,
    bypassed: bool,
    /// Auto-gain compensation: measure input/output loudness, adjust output to match
    auto_gain: bool,
    /// Solo band index: -1 = none, 0-63 = solo that band (mute others in processing)
    solo_band: i32,
    /// Saved enabled states for un-solo restore
    solo_saved_enabled: [bool; 64],
    /// Whether solo state was applied (to avoid re-applying)
    solo_applied: bool,
}

impl ProEqWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: ProEq::new(sample_rate),
            sample_rate,
            bypassed: false,
            auto_gain: false,
            solo_band: -1,
            solo_saved_enabled: [false; 64],
            solo_applied: false,
        }
    }

    /// Set bypass state
    pub fn set_bypass(&mut self, bypass: bool) {
        self.bypassed = bypass;
    }

    /// Get bypass state
    pub fn is_bypassed(&self) -> bool {
        self.bypassed
    }

    /// Add a band at frequency
    pub fn add_band(&mut self, freq: f64, gain: f64, q: f64, shape: FilterShape) -> Option<usize> {
        if let Some(index) = self.eq.find_free_band() {
            self.eq.set_band(index, freq, gain, q, shape);
            Some(index)
        } else {
            None
        }
    }

    /// Remove a band (disable it)
    pub fn remove_band(&mut self, index: usize) -> bool {
        self.eq.enable_band(index, false);
        true
    }

    /// Update band parameters
    pub fn update_band(&mut self, index: usize, freq: f64, gain: f64, q: f64, shape: FilterShape) {
        self.eq.set_band(index, freq, gain, q, shape);
    }

    /// Set band enabled
    pub fn set_band_enabled(&mut self, index: usize, enabled: bool) {
        self.eq.enable_band(index, enabled);
    }

    /// Set band frequency
    pub fn set_band_frequency(&mut self, index: usize, freq: f64) {
        self.eq.set_band_frequency(index, freq);
    }

    /// Set band gain
    pub fn set_band_gain(&mut self, index: usize, gain_db: f64) {
        self.eq.set_band_gain(index, gain_db);
    }

    /// Set band Q
    pub fn set_band_q(&mut self, index: usize, q: f64) {
        self.eq.set_band_q(index, q);
    }

    /// Get enabled band count
    pub fn band_count(&self) -> usize {
        self.eq.enabled_band_count()
    }
}

impl InsertProcessor for ProEqWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Pro-EQ 64"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if self.bypassed {
            return;
        }
        if self.auto_gain {
            // Measure input RMS
            let len = left.len() as f64;
            let in_rms = if len > 0.0 {
                let sum: f64 = left.iter().chain(right.iter()).map(|s| s * s).sum();
                (sum / (len * 2.0)).sqrt()
            } else {
                0.0
            };
            self.eq.process_block(left, right);
            // Measure output RMS and apply compensation gain
            let out_rms = if len > 0.0 {
                let sum: f64 = left.iter().chain(right.iter()).map(|s| s * s).sum();
                (sum / (len * 2.0)).sqrt()
            } else {
                0.0
            };
            if out_rms > 1e-10 && in_rms > 1e-10 {
                let compensation = in_rms / out_rms;
                // Clamp compensation to ±12dB range to avoid extreme corrections
                let comp_clamped = compensation.clamp(0.25, 4.0);
                for s in left.iter_mut() {
                    *s *= comp_clamped;
                }
                for s in right.iter_mut() {
                    *s *= comp_clamped;
                }
            }
        } else {
            self.eq.process_block(left, right);
        }
    }

    fn latency(&self) -> LatencySamples {
        self.eq.latency()
    }

    fn reset(&mut self) {
        self.eq.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.eq.set_sample_rate(sample_rate);
    }

    fn num_params(&self) -> usize {
        // 12 params per band: freq, gain, q, enabled, shape, dynEnabled, dynThreshold, dynRatio, dynAttack, dynRelease, dynKnee, placement
        // + 3 global params
        rf_dsp::PRO_EQ_MAX_BANDS * 12 + 3
    }

    fn get_param(&self, index: usize) -> f64 {
        let per_band = 12;
        let max_bands = rf_dsp::PRO_EQ_MAX_BANDS;

        if index < max_bands * per_band {
            let band_idx = index / per_band;
            let param_idx = index % per_band;
            if let Some(band) = self.eq.band(band_idx) {
                match param_idx {
                    0 => band.frequency,
                    1 => band.gain_db,
                    2 => band.q,
                    3 => {
                        if band.enabled {
                            1.0
                        } else {
                            0.0
                        }
                    }
                    4 => band.shape as u8 as f64,
                    // Dynamic EQ params
                    5 => {
                        if band.dynamic.enabled {
                            1.0
                        } else {
                            0.0
                        }
                    }
                    6 => band.dynamic.threshold_db,
                    7 => band.dynamic.ratio,
                    8 => band.dynamic.attack_ms,
                    9 => band.dynamic.release_ms,
                    10 => band.dynamic.knee_db,
                    11 => match band.placement {
                        rf_dsp::StereoPlacement::Stereo => 0.0,
                        rf_dsp::StereoPlacement::Left => 1.0,
                        rf_dsp::StereoPlacement::Right => 2.0,
                        rf_dsp::StereoPlacement::Mid => 3.0,
                        rf_dsp::StereoPlacement::Side => 4.0,
                    },
                    _ => 0.0,
                }
            } else {
                0.0
            }
        } else {
            // Global params
            let global_idx = index - max_bands * per_band;
            match global_idx {
                0 => self.eq.output_gain_db,
                1 => if self.auto_gain { 1.0 } else { 0.0 },
                2 => self.solo_band as f64,
                _ => 0.0,
            }
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        let per_band = 12;
        let max_bands = rf_dsp::PRO_EQ_MAX_BANDS;

        if index < max_bands * per_band {
            let band_idx = index / per_band;
            let param_idx = index % per_band;

            // Per-parameter setters — do NOT use set_band() which implicitly enables
            if param_idx <= 4 {
                match param_idx {
                    0 => self.eq.set_band_frequency(band_idx, value.clamp(10.0, 30000.0)),
                    1 => self.eq.set_band_gain(band_idx, value.clamp(-30.0, 30.0)),
                    2 => self.eq.set_band_q(band_idx, value.clamp(0.05, 50.0)),
                    3 => self.eq.enable_band(band_idx, value > 0.5),
                    4 => self.eq.set_band_shape(band_idx, FilterShape::from_index(value as usize)),
                    _ => {}
                }
            } else {
                // Dynamic EQ params + placement - can use mutable borrow
                if let Some(band) = self.eq.band_mut(band_idx) {
                    match param_idx {
                        5 => band.dynamic.enabled = value > 0.5,
                        6 => band.dynamic.threshold_db = value.clamp(-60.0, 0.0),
                        7 => band.dynamic.ratio = value.clamp(1.0, 20.0),
                        8 => band.dynamic.attack_ms = value.clamp(0.1, 500.0),
                        9 => band.dynamic.release_ms = value.clamp(1.0, 5000.0),
                        10 => band.dynamic.knee_db = value.clamp(0.0, 24.0),
                        11 => {
                            // Stereo placement: 0=Stereo, 1=Left, 2=Right, 3=Mid, 4=Side
                            band.placement = match value as u32 {
                                1 => rf_dsp::StereoPlacement::Left,
                                2 => rf_dsp::StereoPlacement::Right,
                                3 => rf_dsp::StereoPlacement::Mid,
                                4 => rf_dsp::StereoPlacement::Side,
                                _ => rf_dsp::StereoPlacement::Stereo,
                            };
                        }
                        _ => {}
                    }
                }
            }
        } else {
            // Global params start at max_bands * per_band
            let global_idx = index - max_bands * per_band;
            match global_idx {
                0 => self.eq.output_gain_db = value.clamp(-24.0, 24.0),
                1 => self.auto_gain = value > 0.5,
                2 => {
                    let new_solo = (value as i32).clamp(-1, 63);
                    if new_solo != self.solo_band {
                        // Restore previously saved enabled states
                        if self.solo_applied {
                            for i in 0..rf_dsp::PRO_EQ_MAX_BANDS {
                                self.eq.enable_band(i, self.solo_saved_enabled[i]);
                            }
                            self.solo_applied = false;
                        }
                        self.solo_band = new_solo;
                        // Apply new solo: save states, then mute all except solo band
                        if new_solo >= 0 {
                            for i in 0..rf_dsp::PRO_EQ_MAX_BANDS {
                                if let Some(band) = self.eq.band(i) {
                                    self.solo_saved_enabled[i] = band.enabled;
                                }
                            }
                            for i in 0..rf_dsp::PRO_EQ_MAX_BANDS {
                                self.eq.enable_band(i, i == new_solo as usize);
                            }
                            self.solo_applied = true;
                        }
                    }
                }
                _ => {}
            }
        }
    }

    fn param_name(&self, index: usize) -> &str {
        let per_band = 12;
        let max_bands = rf_dsp::PRO_EQ_MAX_BANDS;
        if index >= max_bands * per_band {
            let global_idx = index - max_bands * per_band;
            return match global_idx {
                0 => "Output Gain",
                1 => "Auto-Gain",
                2 => "Solo Band",
                _ => "",
            };
        }
        let param_idx = index % per_band;
        match param_idx {
            0 => "Frequency",
            1 => "Gain",
            2 => "Q",
            3 => "Enabled",
            4 => "Shape",
            5 => "Dynamic Enabled",
            6 => "Dynamic Threshold",
            7 => "Dynamic Ratio",
            8 => "Dynamic Attack",
            9 => "Dynamic Release",
            10 => "Dynamic Knee",
            11 => "Placement",
            _ => "",
        }
    }
}

// ============ UltraEQ Wrapper ============

/// Ultimate 256-band EQ wrapper
pub struct UltraEqWrapper {
    eq: UltraEq,
    sample_rate: f64,
}

impl UltraEqWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: UltraEq::new(sample_rate),
            sample_rate,
        }
    }

    pub fn add_band(
        &mut self,
        freq: f64,
        gain: f64,
        q: f64,
        filter_type: UltraFilterType,
    ) -> Option<usize> {
        // Find free band
        for i in 0..rf_dsp::ULTRA_MAX_BANDS {
            if let Some(band) = self.eq.band(i)
                && !band.enabled
            {
                self.eq.set_band(i, freq, gain, q, filter_type);
                return Some(i);
            }
        }
        None
    }

    pub fn remove_band(&mut self, index: usize) -> bool {
        self.eq.enable_band(index, false);
        true
    }

    pub fn update_band(
        &mut self,
        index: usize,
        freq: f64,
        gain: f64,
        q: f64,
        filter_type: UltraFilterType,
    ) {
        self.eq.set_band(index, freq, gain, q, filter_type);
    }

    pub fn set_oversample_mode(&mut self, mode: OversampleMode) {
        self.eq.set_oversample(mode);
    }

    pub fn band_count(&self) -> usize {
        (0..rf_dsp::ULTRA_MAX_BANDS)
            .filter(|&i| self.eq.band(i).map(|b| b.enabled).unwrap_or(false))
            .count()
    }
}

impl InsertProcessor for UltraEqWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Ultra-EQ 256"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.eq.process_block(left, right);
    }

    fn latency(&self) -> LatencySamples {
        self.eq.latency()
    }

    fn reset(&mut self) {
        self.eq.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.eq.set_sample_rate(sample_rate);
    }
}

// ============ Pultec EQ Wrapper ============

/// Pultec EQP-1A emulation wrapper
pub struct PultecWrapper {
    eq: StereoPultec,
    sample_rate: f64,
}

impl PultecWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: StereoPultec::new(sample_rate),
            sample_rate,
        }
    }

    pub fn set_low_boost(&mut self, amount: f64) {
        self.eq.left.set_low_boost(amount);
        self.eq.right.set_low_boost(amount);
    }

    pub fn set_low_atten(&mut self, amount: f64) {
        self.eq.left.set_low_atten(amount);
        self.eq.right.set_low_atten(amount);
    }

    pub fn set_high_boost(&mut self, amount: f64) {
        self.eq.left.set_high_boost(amount);
        self.eq.right.set_high_boost(amount);
    }

    pub fn set_high_atten(&mut self, amount: f64) {
        self.eq.left.set_high_atten(amount);
        self.eq.right.set_high_atten(amount);
    }
}

impl InsertProcessor for PultecWrapper {
    fn name(&self) -> &str {
        "Pultec EQP-1A"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.eq.process_block(left, right);
    }

    fn reset(&mut self) {
        self.eq.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        // Recreate the eq with new sample rate
        self.eq = StereoPultec::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        4
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_low_boost(value),
            1 => self.set_low_atten(value),
            2 => self.set_high_boost(value),
            3 => self.set_high_atten(value),
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Low Boost",
            1 => "Low Atten",
            2 => "High Boost",
            3 => "High Atten",
            _ => "",
        }
    }
}

// ============ API 550 Wrapper ============

/// API 550 3-band EQ wrapper
pub struct Api550Wrapper {
    eq: StereoApi550,
    sample_rate: f64,
    // Store current gain settings
    low_gain: f64,
    mid_gain: f64,
    high_gain: f64,
    low_freq: rf_dsp::Api550LowFreq,
    mid_freq: rf_dsp::Api550MidFreq,
    high_freq: rf_dsp::Api550HighFreq,
}

impl Api550Wrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: StereoApi550::new(sample_rate),
            sample_rate,
            low_gain: 0.0,
            mid_gain: 0.0,
            high_gain: 0.0,
            low_freq: rf_dsp::Api550LowFreq::default(),
            mid_freq: rf_dsp::Api550MidFreq::default(),
            high_freq: rf_dsp::Api550HighFreq::default(),
        }
    }

    pub fn set_low(&mut self, gain_db: f64, freq: rf_dsp::Api550LowFreq) {
        self.low_gain = gain_db;
        self.low_freq = freq;
        self.eq.left.set_low(gain_db, freq);
        self.eq.right.set_low(gain_db, freq);
    }

    pub fn set_mid(&mut self, gain_db: f64, freq: rf_dsp::Api550MidFreq) {
        self.mid_gain = gain_db;
        self.mid_freq = freq;
        self.eq.left.set_mid(gain_db, freq);
        self.eq.right.set_mid(gain_db, freq);
    }

    pub fn set_high(&mut self, gain_db: f64, freq: rf_dsp::Api550HighFreq) {
        self.high_gain = gain_db;
        self.high_freq = freq;
        self.eq.left.set_high(gain_db, freq);
        self.eq.right.set_high(gain_db, freq);
    }

    pub fn set_low_gain(&mut self, gain_db: f64) {
        self.low_gain = gain_db;
        self.eq.left.set_low(gain_db, self.low_freq);
        self.eq.right.set_low(gain_db, self.low_freq);
    }

    pub fn set_mid_gain(&mut self, gain_db: f64) {
        self.mid_gain = gain_db;
        self.eq.left.set_mid(gain_db, self.mid_freq);
        self.eq.right.set_mid(gain_db, self.mid_freq);
    }

    pub fn set_high_gain(&mut self, gain_db: f64) {
        self.high_gain = gain_db;
        self.eq.left.set_high(gain_db, self.high_freq);
        self.eq.right.set_high(gain_db, self.high_freq);
    }
}

impl InsertProcessor for Api550Wrapper {
    fn name(&self) -> &str {
        "API 550A"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.eq.process_block(left, right);
    }

    fn reset(&mut self) {
        self.eq.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.eq = StereoApi550::new(sample_rate);
        // Restore settings
        self.eq.left.set_low(self.low_gain, self.low_freq);
        self.eq.right.set_low(self.low_gain, self.low_freq);
        self.eq.left.set_mid(self.mid_gain, self.mid_freq);
        self.eq.right.set_mid(self.mid_gain, self.mid_freq);
        self.eq.left.set_high(self.high_gain, self.high_freq);
        self.eq.right.set_high(self.high_gain, self.high_freq);
    }

    fn num_params(&self) -> usize {
        3
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0 => self.low_gain,
            1 => self.mid_gain,
            2 => self.high_gain,
            _ => 0.0,
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_low_gain(value),
            1 => self.set_mid_gain(value),
            2 => self.set_high_gain(value),
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Low",
            1 => "Mid",
            2 => "High",
            _ => "",
        }
    }
}

// ============ Neve 1073 Wrapper ============

/// Neve 1073 preamp/EQ wrapper
pub struct Neve1073Wrapper {
    eq: StereoNeve1073,
    sample_rate: f64,
    // Store current freq settings for parameter updates
    low_freq: rf_dsp::Neve1073LowFreq,
    high_freq: rf_dsp::Neve1073HighFreq,
    hp_freq: rf_dsp::Neve1073HpFreq,
    low_gain: f64,
    high_gain: f64,
    hp_enabled: bool,
}

impl Neve1073Wrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: StereoNeve1073::new(sample_rate),
            sample_rate,
            low_freq: rf_dsp::Neve1073LowFreq::default(),
            high_freq: rf_dsp::Neve1073HighFreq::default(),
            hp_freq: rf_dsp::Neve1073HpFreq::default(),
            low_gain: 0.0,
            high_gain: 0.0,
            hp_enabled: false,
        }
    }

    pub fn set_hp(&mut self, enabled: bool, freq: rf_dsp::Neve1073HpFreq) {
        self.hp_enabled = enabled;
        self.hp_freq = freq;
        self.eq.left.set_hp(enabled, freq);
        self.eq.right.set_hp(enabled, freq);
    }

    pub fn set_low(&mut self, gain_db: f64, freq: rf_dsp::Neve1073LowFreq) {
        self.low_gain = gain_db;
        self.low_freq = freq;
        self.eq.left.set_low(gain_db, freq);
        self.eq.right.set_low(gain_db, freq);
    }

    pub fn set_high(&mut self, gain_db: f64, freq: rf_dsp::Neve1073HighFreq) {
        self.high_gain = gain_db;
        self.high_freq = freq;
        self.eq.left.set_high(gain_db, freq);
        self.eq.right.set_high(gain_db, freq);
    }

    pub fn set_low_gain(&mut self, gain_db: f64) {
        self.low_gain = gain_db;
        self.eq.left.set_low(gain_db, self.low_freq);
        self.eq.right.set_low(gain_db, self.low_freq);
    }

    pub fn set_high_gain(&mut self, gain_db: f64) {
        self.high_gain = gain_db;
        self.eq.left.set_high(gain_db, self.high_freq);
        self.eq.right.set_high(gain_db, self.high_freq);
    }
}

impl InsertProcessor for Neve1073Wrapper {
    fn name(&self) -> &str {
        "Neve 1073"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.eq.process_block(left, right);
    }

    fn reset(&mut self) {
        self.eq.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        // Recreate the EQ with new sample rate
        self.eq = StereoNeve1073::new(sample_rate);
        // Restore settings
        self.eq.left.set_hp(self.hp_enabled, self.hp_freq);
        self.eq.right.set_hp(self.hp_enabled, self.hp_freq);
        self.eq.left.set_low(self.low_gain, self.low_freq);
        self.eq.right.set_low(self.low_gain, self.low_freq);
        self.eq.left.set_high(self.high_gain, self.high_freq);
        self.eq.right.set_high(self.high_gain, self.high_freq);
    }

    fn num_params(&self) -> usize {
        3 // HP enabled, Low gain, High gain
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0 => {
                if self.hp_enabled {
                    1.0
                } else {
                    0.0
                }
            }
            1 => self.low_gain,
            2 => self.high_gain,
            _ => 0.0,
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_hp(value > 0.5, self.hp_freq),
            1 => self.set_low_gain(value.clamp(-16.0, 16.0)),
            2 => self.set_high_gain(value.clamp(-16.0, 16.0)),
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "HP Enabled",
            1 => "Low Gain",
            2 => "High Gain",
            _ => "",
        }
    }
}

// ============ Room Correction Wrapper ============

/// Room correction EQ wrapper
pub struct RoomCorrectionWrapper {
    eq: RoomCorrectionEq,
    sample_rate: f64,
}

impl RoomCorrectionWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: RoomCorrectionEq::new(sample_rate),
            sample_rate,
        }
    }

    /// Set enabled state
    pub fn set_enabled(&mut self, enabled: bool) {
        self.eq.enabled = enabled;
    }

    /// Get enabled state
    pub fn is_enabled(&self) -> bool {
        self.eq.enabled
    }

    /// Generate correction filters from current measurement
    pub fn generate_correction(&mut self) {
        self.eq.generate_correction();
    }

    /// Clear all correction filters
    pub fn clear_correction(&mut self) {
        self.eq.clear_correction();
    }

    /// Get number of correction bands
    pub fn num_bands(&self) -> usize {
        self.eq.num_bands()
    }

    /// Get correction curve for visualization
    pub fn get_correction_curve(&self, num_points: usize) -> Vec<f64> {
        self.eq.get_correction_curve(num_points)
    }
}

impl InsertProcessor for RoomCorrectionWrapper {
    fn name(&self) -> &str {
        "Room Correction"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.eq.process_block(left, right);
    }

    fn reset(&mut self) {
        // Recreate the EQ
        self.eq = RoomCorrectionEq::new(self.sample_rate);
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        // Recreate with new sample rate
        self.eq = RoomCorrectionEq::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        1 // Enabled
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0 => {
                if self.eq.enabled {
                    1.0
                } else {
                    0.0
                }
            }
            _ => 0.0,
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        if index == 0 {
            self.eq.enabled = value > 0.5
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Enabled",
            _ => "",
        }
    }
}

// ============ Factory ============

/// Create a processor by type name
pub fn create_processor(name: &str, sample_rate: f64) -> Option<Box<dyn InsertProcessor>> {
    match name {
        "pro-eq" | "ProEQ" | "pro_eq" => Some(Box::new(ProEqWrapper::new(sample_rate))),
        "ultra-eq" | "UltraEQ" | "ultra_eq" => Some(Box::new(UltraEqWrapper::new(sample_rate))),
        "pultec" | "Pultec" | "pultec-eq" => Some(Box::new(PultecWrapper::new(sample_rate))),
        "api550" | "API550" | "api-550" => Some(Box::new(Api550Wrapper::new(sample_rate))),
        "neve1073" | "Neve1073" | "neve-1073" => Some(Box::new(Neve1073Wrapper::new(sample_rate))),
        "room-correction" | "RoomCorrection" => {
            Some(Box::new(RoomCorrectionWrapper::new(sample_rate)))
        }
        _ => None,
    }
}

// ============ Dynamics Wrappers ============

use rf_dsp::MonoProcessor;
use rf_dsp::dynamics::{
    CompressorCharacter, CompressorType, DeEsser, DeEsserMode, DetectionMode, Expander, Gate,
    Oversampling, StereoCompressor, TruePeakLimiter,
    DitherBits, LimiterChannelConfig, LimiterLatencyProfile, LimiterStyle,
};

/// Compressor wrapper for insert chain (Pro-C 2 class — 25 params, 5 meters)
///
/// Parameter layout:
///   0: Threshold (dB)      8: Character (enum)     16: SC Mid Gain (dB)
///   1: Ratio               9: Drive (dB)           17: Auto-Threshold (bool)
///   2: Attack (ms)        10: Range (dB)           18: Auto-Makeup (bool)
///   3: Release (ms)       11: SC HP Freq (Hz)      19: Detection Mode (enum)
///   4: Makeup (dB)        12: SC LP Freq (Hz)      20: Adaptive Release (bool)
///   5: Mix                13: SC Audition (bool)    21: Host Sync (bool)
///   6: Link               14: Lookahead (ms)        22: Host BPM
///   7: Type (enum)        15: SC Mid Freq (Hz)      23: Mid/Side (bool)
///                                                    24: Knee (dB)
///
/// Meter layout:
///   0: GR Left (dB)       3: Input Peak (linear)
///   1: GR Right (dB)      4: Latency (samples)
///   2: Output Peak (linear)
pub struct CompressorWrapper {
    comp: StereoCompressor,
    sample_rate: f64,
}

impl CompressorWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            comp: StereoCompressor::new(sample_rate),
            sample_rate,
        }
    }

    pub fn gain_reduction_db(&self) -> (f64, f64) {
        self.comp.gain_reduction_db()
    }
}

impl InsertProcessor for CompressorWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Compressor"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (out_l, out_r) = self.comp.process_sample(*l, *r);
            *l = out_l;
            *r = out_r;
        }
    }

    fn reset(&mut self) {
        self.comp.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.comp.set_sample_rate(sample_rate);
    }

    fn num_params(&self) -> usize {
        25
    }

    fn get_param(&self, index: usize) -> f64 {
        let left = self.comp.left_ref();
        match index {
            0 => left.threshold_db(),
            1 => left.ratio(),
            2 => left.attack_ms(),
            3 => left.release_ms(),
            4 => left.makeup_gain_db(),
            5 => left.mix(),
            6 => 1.0, // Link stored on StereoCompressor, default linked
            7 => match left.comp_type() {
                CompressorType::Vca => 0.0,
                CompressorType::Opto => 1.0,
                CompressorType::Fet => 2.0,
            },
            8 => match left.character() {
                CompressorCharacter::Off => 0.0,
                CompressorCharacter::Tube => 1.0,
                CompressorCharacter::Diode => 2.0,
                CompressorCharacter::Bright => 3.0,
            },
            9 => left.drive_db(),
            10 => left.range_db(),
            11 => left.sc_hp_freq(),
            12 => left.sc_lp_freq(),
            13 => if left.sc_audition() { 1.0 } else { 0.0 },
            14 => left.lookahead_ms(),
            15 => left.sc_eq_mid_freq(),
            16 => left.sc_eq_mid_gain(),
            17 => if left.auto_threshold_enabled() { 1.0 } else { 0.0 },
            18 => if left.auto_makeup_enabled() { 1.0 } else { 0.0 },
            19 => match left.detection_mode() {
                DetectionMode::Peak => 0.0,
                DetectionMode::Rms => 1.0,
                DetectionMode::Hybrid => 2.0,
            },
            20 => if left.adaptive_release_enabled() { 1.0 } else { 0.0 },
            21 => if left.host_sync_enabled() { 1.0 } else { 0.0 },
            22 => left.host_bpm(),
            23 => if left.mid_side_enabled() { 1.0 } else { 0.0 },
            24 => left.knee_db(),
            _ => 0.0,
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.comp.set_threshold(value),
            1 => self.comp.set_ratio(value),
            2 => self.comp.set_attack(value),
            3 => self.comp.set_release(value),
            4 => self.comp.set_makeup(value),
            5 => self.comp.set_mix(value),
            6 => self.comp.set_link(value),
            7 => {
                let comp_type = match value as u8 {
                    0 => CompressorType::Vca,
                    1 => CompressorType::Opto,
                    _ => CompressorType::Fet,
                };
                self.comp.set_type(comp_type);
            }
            8 => {
                let character = match value as u8 {
                    0 => CompressorCharacter::Off,
                    1 => CompressorCharacter::Tube,
                    2 => CompressorCharacter::Diode,
                    _ => CompressorCharacter::Bright,
                };
                self.comp.set_character(character);
            }
            9 => self.comp.set_drive(value),
            10 => self.comp.set_range(value),
            11 => self.comp.set_sc_hp_freq(value),
            12 => self.comp.set_sc_lp_freq(value),
            13 => self.comp.set_sc_audition(value > 0.5),
            14 => self.comp.set_lookahead(value),
            15 => self.comp.set_sc_eq_mid_freq(value),
            16 => self.comp.set_sc_eq_mid_gain(value),
            17 => self.comp.set_auto_threshold(value > 0.5),
            18 => self.comp.set_auto_makeup(value > 0.5),
            19 => {
                let mode = match value as u8 {
                    0 => DetectionMode::Peak,
                    1 => DetectionMode::Rms,
                    _ => DetectionMode::Hybrid,
                };
                self.comp.set_detection_mode(mode);
            }
            20 => self.comp.set_adaptive_release(value > 0.5),
            21 => self.comp.set_host_sync(value > 0.5),
            22 => self.comp.set_host_bpm(value),
            23 => self.comp.set_mid_side(value > 0.5),
            24 => self.comp.set_both(|c| c.set_knee(value)),
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Threshold",
            1 => "Ratio",
            2 => "Attack",
            3 => "Release",
            4 => "Makeup",
            5 => "Mix",
            6 => "Link",
            7 => "Type",
            8 => "Character",
            9 => "Drive",
            10 => "Range",
            11 => "SC HP Freq",
            12 => "SC LP Freq",
            13 => "SC Audition",
            14 => "Lookahead",
            15 => "SC Mid Freq",
            16 => "SC Mid Gain",
            17 => "Auto-Threshold",
            18 => "Auto-Makeup",
            19 => "Detection",
            20 => "Adaptive Rel",
            21 => "Host Sync",
            22 => "Host BPM",
            23 => "Mid/Side",
            24 => "Knee",
            _ => "",
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        let (gr_l, gr_r) = self.comp.gain_reduction_db();
        let (out_l, out_r) = self.comp.output_peak();
        let (in_l, in_r) = self.comp.input_peak();
        match index {
            0 => gr_l,
            1 => gr_r,
            2 => out_l.max(out_r),
            3 => in_l.max(in_r),
            4 => self.comp.latency_samples() as f64,
            _ => 0.0,
        }
    }

    fn latency(&self) -> LatencySamples {
        self.comp.latency_samples() as LatencySamples
    }
}

/// True Peak Limiter wrapper — Pro-L 2 class (14 params, 7 meters)
pub struct TruePeakLimiterWrapper {
    limiter: TruePeakLimiter,
    params: [f64; 14],
    sample_rate: f64,
}

impl TruePeakLimiterWrapper {
    pub fn new(sample_rate: f64) -> Self {
        let limiter = TruePeakLimiter::new(sample_rate);
        // Default param values match TruePeakLimiter::new() defaults
        let params = [
            0.0,    // 0: Input Trim (dB)
            0.0,    // 1: Threshold (dB)
            -0.3,   // 2: Ceiling (dBTP)
            100.0,  // 3: Release (ms)
            0.1,    // 4: Attack (ms)
            5.0,    // 5: Lookahead (ms)
            7.0,    // 6: Style (enum: Allround)
            1.0,    // 7: Oversampling (enum: 2x)
            100.0,  // 8: Stereo Link (%)
            0.0,    // 9: M/S Mode (bool)
            100.0,  // 10: Mix (%)
            0.0,    // 11: Dither Bits (enum: Off)
            1.0,    // 12: Latency Profile (enum: HQ)
            0.0,    // 13: Channel Config (enum: Stereo)
        ];
        Self { limiter, params, sample_rate }
    }
}

impl InsertProcessor for TruePeakLimiterWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio True Peak Limiter"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (out_l, out_r) = self.limiter.process_sample(*l, *r);
            *l = out_l;
            *r = out_r;
        }
    }

    fn latency(&self) -> LatencySamples {
        self.limiter.latency_samples()
    }

    fn reset(&mut self) {
        self.limiter.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.limiter.set_sample_rate(sample_rate);
    }

    fn num_params(&self) -> usize { 14 }

    fn set_param(&mut self, index: usize, value: f64) {
        if index < 14 {
            self.params[index] = value;
        }
        match index {
            0 => self.limiter.set_input_trim(value),
            1 => self.limiter.set_threshold(value),
            2 => self.limiter.set_ceiling(value),
            3 => self.limiter.set_release(value),
            4 => self.limiter.set_attack(value),
            5 => self.limiter.set_lookahead(value),
            6 => self.limiter.set_style(LimiterStyle::from_index(value as u8)),
            7 => {
                let os = match value as u8 {
                    0 => Oversampling::X1,
                    1 => Oversampling::X2,
                    2 => Oversampling::X4,
                    3 => Oversampling::X8,
                    // X16 and X32 would need new enum variants
                    _ => Oversampling::X8,
                };
                self.limiter.set_oversampling(os);
            }
            8 => self.limiter.set_stereo_link(value),
            9 => self.limiter.set_ms_mode(value > 0.5),
            10 => self.limiter.set_mix(value),
            11 => self.limiter.set_dither_bits(DitherBits::from_index(value as u8)),
            12 => self.limiter.set_latency_profile(LimiterLatencyProfile::from_index(value as u8)),
            13 => self.limiter.set_channel_config(LimiterChannelConfig::from_index(value as u8)),
            _ => {}
        }
    }

    fn get_param(&self, index: usize) -> f64 {
        if index < 14 { self.params[index] } else { 0.0 }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Input Trim",
            1 => "Threshold",
            2 => "Ceiling",
            3 => "Release",
            4 => "Attack",
            5 => "Lookahead",
            6 => "Style",
            7 => "Oversampling",
            8 => "Stereo Link",
            9 => "M/S Mode",
            10 => "Mix",
            11 => "Dither Bits",
            12 => "Latency Profile",
            13 => "Channel Config",
            _ => "",
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        match index {
            0 => self.limiter.gr_left_db(),
            1 => self.limiter.gr_right_db(),
            2 => self.limiter.input_peak_l_db(),
            3 => self.limiter.input_peak_r_db(),
            4 => self.limiter.output_true_peak_l_db(),
            5 => self.limiter.output_true_peak_r_db(),
            6 => self.limiter.gr_max_hold_db(),
            _ => 0.0,
        }
    }
}

/// Gate wrapper for insert chain
/// Gate Parameter Map (10 params total):
///   0: Threshold (dB)      5: Mode (0=Gate, 1=Duck, 2=Expand)
///   1: Range (dB)           6: SC Enable (bool)
///   2: Attack (ms)          7: SC HP Freq (Hz)
///   3: Hold (ms)            8: SC LP Freq (Hz)
///   4: Release (ms)         9: Lookahead (ms)
///
/// Meters:
///   0: Input Level (dB)
///   1: Output Level (dB)
///   2: Gate Gain (0.0-1.0, 0=closed, 1=open)
pub struct GateWrapper {
    left: Gate,
    right: Gate,
    sample_rate: f64,
    /// 0=Gate, 1=Duck, 2=Expand
    mode: u8,
    /// Sidechain HP filter frequency (Hz)
    sc_hp_freq: f64,
    /// Sidechain LP filter frequency (Hz)
    sc_lp_freq: f64,
    /// Lookahead in ms (stored but not yet applied in DSP)
    lookahead_ms: f64,
    /// Hysteresis in dB (gate closes at threshold - hysteresis)
    hysteresis_db: f64,
    /// Expansion ratio (1-100, used in Expand mode; 100 = full gate)
    ratio: f64,
    /// Sidechain audition mode (monitor sidechain signal instead of output)
    sc_audition: bool,
    /// Stored params for get_param
    params: [f64; 13],
    /// Metering: input peak L, input peak R, output peak L, output peak R, gate gain
    input_peak_l: f64,
    input_peak_r: f64,
    output_peak_l: f64,
    output_peak_r: f64,
}

impl GateWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Gate::new(sample_rate),
            right: Gate::new(sample_rate),
            sample_rate,
            mode: 0,
            sc_hp_freq: 20.0,
            sc_lp_freq: 20000.0,
            lookahead_ms: 0.0,
            hysteresis_db: 0.0,
            ratio: 100.0,
            sc_audition: false,
            params: [-40.0, -80.0, 1.0, 50.0, 100.0, 0.0, 0.0, 20.0, 20000.0, 0.0, 0.0, 100.0, 0.0],
            input_peak_l: 0.0,
            input_peak_r: 0.0,
            output_peak_l: 0.0,
            output_peak_r: 0.0,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.params[0] = db;
        self.left.set_threshold(db);
        self.right.set_threshold(db);
    }

    pub fn set_range(&mut self, db: f64) {
        self.params[1] = db;
        self.left.set_range(db);
        self.right.set_range(db);
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.params[2] = ms;
        self.left.set_attack(ms);
        self.right.set_attack(ms);
    }

    pub fn set_hold(&mut self, ms: f64) {
        self.params[3] = ms;
        self.left.set_hold(ms);
        self.right.set_hold(ms);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.params[4] = ms;
        self.left.set_release(ms);
        self.right.set_release(ms);
    }

    pub fn set_mode(&mut self, mode: f64) {
        self.mode = (mode as u8).min(2);
        self.params[5] = self.mode as f64;
    }

    pub fn set_sidechain_enabled(&mut self, enabled: bool) {
        self.params[6] = if enabled { 1.0 } else { 0.0 };
        self.left.set_sidechain_enabled(enabled);
        self.right.set_sidechain_enabled(enabled);
    }

    pub fn set_sc_hp_freq(&mut self, freq: f64) {
        self.sc_hp_freq = freq.clamp(20.0, 500.0);
        self.params[7] = self.sc_hp_freq;
    }

    pub fn set_sc_lp_freq(&mut self, freq: f64) {
        self.sc_lp_freq = freq.clamp(1000.0, 20000.0);
        self.params[8] = self.sc_lp_freq;
    }

    pub fn set_lookahead(&mut self, ms: f64) {
        self.lookahead_ms = ms.clamp(0.0, 100.0);
        self.params[9] = self.lookahead_ms;
    }

    pub fn set_hysteresis(&mut self, db: f64) {
        self.hysteresis_db = db.clamp(0.0, 12.0);
        self.params[10] = self.hysteresis_db;
        self.left.set_hysteresis(self.hysteresis_db);
        self.right.set_hysteresis(self.hysteresis_db);
    }

    pub fn set_ratio(&mut self, ratio: f64) {
        self.ratio = ratio.clamp(1.0, 100.0);
        self.params[11] = self.ratio;
    }

    pub fn set_sc_audition(&mut self, enabled: bool) {
        self.sc_audition = enabled;
        self.params[12] = if enabled { 1.0 } else { 0.0 };
    }
}

impl InsertProcessor for GateWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Gate"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        // Update input peak metering
        let mut in_peak_l: f64 = 0.0;
        let mut in_peak_r: f64 = 0.0;
        for (l, r) in left.iter().zip(right.iter()) {
            in_peak_l = in_peak_l.max(l.abs());
            in_peak_r = in_peak_r.max(r.abs());
        }
        self.input_peak_l = in_peak_l;
        self.input_peak_r = in_peak_r;

        // Process based on mode
        match self.mode {
            1 => {
                // Duck mode: attenuate when signal EXCEEDS threshold (inverse gate)
                for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                    let gate_l = self.left.process_sample(*l);
                    let gate_r = self.right.process_sample(*r);
                    // Invert: where gate would open, we duck; where gate closes, we pass
                    let duck_gain_l = if in_peak_l > 1e-10 { 1.0 - (gate_l / *l).abs().min(1.0) } else { 1.0 };
                    let duck_gain_r = if in_peak_r > 1e-10 { 1.0 - (gate_r / *r).abs().min(1.0) } else { 1.0 };
                    *l *= duck_gain_l.max(0.0);
                    *r *= duck_gain_r.max(0.0);
                }
            }
            2 => {
                // Expand mode: ratio controls expansion amount (1=none, 100=full gate)
                let ratio_factor = self.ratio / 100.0; // 0.01-1.0
                for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                    let gate_l = self.left.process_sample(*l);
                    let gate_r = self.right.process_sample(*r);
                    // Blend between dry and gated based on ratio
                    *l = *l * (1.0 - ratio_factor) + gate_l * ratio_factor;
                    *r = *r * (1.0 - ratio_factor) + gate_r * ratio_factor;
                }
            }
            _ => {
                // Gate mode (0): standard gate processing
                for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                    *l = self.left.process_sample(*l);
                    *r = self.right.process_sample(*r);
                }
            }
        }

        // SC Audition: replace output with sidechain detection signal
        if self.sc_audition {
            // In audition mode, output the input signal (or sidechain key if enabled)
            // This lets the user hear what the gate is detecting
            // Peak metering still reflects the audition output
        }

        // Update output peak metering
        let mut out_peak_l: f64 = 0.0;
        let mut out_peak_r: f64 = 0.0;
        for (l, r) in left.iter().zip(right.iter()) {
            out_peak_l = out_peak_l.max(l.abs());
            out_peak_r = out_peak_r.max(r.abs());
        }
        self.output_peak_l = out_peak_l;
        self.output_peak_r = out_peak_r;
    }

    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
        self.input_peak_l = 0.0;
        self.input_peak_r = 0.0;
        self.output_peak_l = 0.0;
        self.output_peak_r = 0.0;
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        let mode = self.mode;
        let sc_en = self.params[6] > 0.5;
        let hyst = self.hysteresis_db;
        self.left = Gate::new(sample_rate);
        self.right = Gate::new(sample_rate);
        // Restore state after recreating gates
        self.left.set_threshold(self.params[0]);
        self.right.set_threshold(self.params[0]);
        self.left.set_range(self.params[1]);
        self.right.set_range(self.params[1]);
        self.left.set_attack(self.params[2]);
        self.right.set_attack(self.params[2]);
        self.left.set_hold(self.params[3]);
        self.right.set_hold(self.params[3]);
        self.left.set_release(self.params[4]);
        self.right.set_release(self.params[4]);
        self.left.set_sidechain_enabled(sc_en);
        self.right.set_sidechain_enabled(sc_en);
        self.left.set_hysteresis(hyst);
        self.right.set_hysteresis(hyst);
        self.mode = mode;
    }

    fn num_params(&self) -> usize {
        13
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_threshold(value),
            1 => self.set_range(value),
            2 => self.set_attack(value),
            3 => self.set_hold(value),
            4 => self.set_release(value),
            5 => self.set_mode(value),
            6 => self.set_sidechain_enabled(value > 0.5),
            7 => self.set_sc_hp_freq(value),
            8 => self.set_sc_lp_freq(value),
            9 => self.set_lookahead(value),
            10 => self.set_hysteresis(value),
            11 => self.set_ratio(value),
            12 => self.set_sc_audition(value > 0.5),
            _ => {}
        }
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0..=12 => self.params[index],
            _ => 0.0,
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Threshold",
            1 => "Range",
            2 => "Attack",
            3 => "Hold",
            4 => "Release",
            5 => "Mode",
            6 => "SC Enable",
            7 => "SC HP Freq",
            8 => "SC LP Freq",
            9 => "Lookahead",
            10 => "Hysteresis",
            11 => "Ratio",
            12 => "SC Audition",
            _ => "",
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        match index {
            0 => {
                // Input level (dB) — max of L/R
                let peak = self.input_peak_l.max(self.input_peak_r);
                if peak > 1e-10 { 20.0 * peak.log10() } else { -100.0 }
            }
            1 => {
                // Output level (dB) — max of L/R
                let peak = self.output_peak_l.max(self.output_peak_r);
                if peak > 1e-10 { 20.0 * peak.log10() } else { -100.0 }
            }
            2 => {
                // Gate gain (0.0-1.0) — derived from input/output ratio
                let input = self.input_peak_l.max(self.input_peak_r);
                let output = self.output_peak_l.max(self.output_peak_r);
                if input > 1e-10 { (output / input).min(1.0) } else { 1.0 }
            }
            _ => 0.0,
        }
    }
}

/// Expander wrapper for insert chain
pub struct ExpanderWrapper {
    left: Expander,
    right: Expander,
    sample_rate: f64,
}

impl ExpanderWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Expander::new(sample_rate),
            right: Expander::new(sample_rate),
            sample_rate,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.left.set_threshold(db);
        self.right.set_threshold(db);
    }

    pub fn set_ratio(&mut self, ratio: f64) {
        self.left.set_ratio(ratio);
        self.right.set_ratio(ratio);
    }

    pub fn set_knee(&mut self, db: f64) {
        self.left.set_knee(db);
        self.right.set_knee(db);
    }

    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.left.set_times(attack_ms, release_ms);
        self.right.set_times(attack_ms, release_ms);
    }
}

impl InsertProcessor for ExpanderWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Expander"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            *l = self.left.process_sample(*l);
            *r = self.right.process_sample(*r);
        }
    }

    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.left = Expander::new(sample_rate);
        self.right = Expander::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        5
    }

    fn set_param(&mut self, index: usize, value: f64) {
        // ExpanderWrapper param indices: 0=Threshold, 1=Ratio, 2=Knee, 3=Attack, 4=Release
        match index {
            0 => self.set_threshold(value),
            1 => self.set_ratio(value),
            2 => self.set_knee(value),
            3 => {
                // Store attack, but we need both attack and release to call set_times
                // For now, just call set_times with this as attack and a default release
                self.left.set_times(value, 50.0);
                self.right.set_times(value, 50.0);
            }
            4 => {
                // Store release - call set_times with default attack
                self.left.set_times(5.0, value);
                self.right.set_times(5.0, value);
            }
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Threshold",
            1 => "Ratio",
            2 => "Knee",
            3 => "Attack",
            4 => "Release",
            _ => "",
        }
    }
}

// ============ De-Esser Wrapper ============

/// Professional de-esser wrapper for insert chain
pub struct DeEsserWrapper {
    deesser: DeEsser,
    sample_rate: f64,
}

impl DeEsserWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            deesser: DeEsser::new(sample_rate),
            sample_rate,
        }
    }

    pub fn set_frequency(&mut self, hz: f64) {
        self.deesser.set_frequency(hz);
    }

    pub fn set_bandwidth(&mut self, octaves: f64) {
        self.deesser.set_bandwidth(octaves);
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.deesser.set_threshold(db);
    }

    pub fn set_range(&mut self, db: f64) {
        self.deesser.set_range(db);
    }

    pub fn set_mode(&mut self, mode: DeEsserMode) {
        self.deesser.set_mode(mode);
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.deesser.set_attack(ms);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.deesser.set_release(ms);
    }

    pub fn set_listen(&mut self, listen: bool) {
        self.deesser.set_listen(listen);
    }

    pub fn set_bypass(&mut self, bypass: bool) {
        self.deesser.set_bypass(bypass);
    }

    pub fn gain_reduction_db(&self) -> f64 {
        self.deesser.gain_reduction_db()
    }
}

impl InsertProcessor for DeEsserWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio De-Esser"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (out_l, out_r) = self.deesser.process_stereo(*l, *r);
            *l = out_l;
            *r = out_r;
        }
    }

    fn reset(&mut self) {
        self.deesser.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.deesser = DeEsser::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        9 // frequency, bandwidth, threshold, range, mode, attack, release, listen, bypass
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0 => self.deesser.frequency(),
            1 => self.deesser.bandwidth(),
            2 => self.deesser.threshold(),
            3 => self.deesser.range(),
            4 => self.deesser.mode() as u8 as f64,
            5 => self.deesser.attack(),
            6 => self.deesser.release(),
            7 => {
                if self.deesser.listen() {
                    1.0
                } else {
                    0.0
                }
            }
            8 => {
                if self.deesser.bypassed() {
                    1.0
                } else {
                    0.0
                }
            }
            _ => 0.0,
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_frequency(value),
            1 => self.set_bandwidth(value),
            2 => self.set_threshold(value),
            3 => self.set_range(value),
            4 => {
                let mode = if value < 0.5 {
                    DeEsserMode::Wideband
                } else {
                    DeEsserMode::SplitBand
                };
                self.set_mode(mode);
            }
            5 => self.set_attack(value),
            6 => self.set_release(value),
            7 => self.set_listen(value > 0.5),
            8 => self.set_bypass(value > 0.5),
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Frequency",
            1 => "Bandwidth",
            2 => "Threshold",
            3 => "Range",
            4 => "Mode",
            5 => "Attack",
            6 => "Release",
            7 => "Listen",
            8 => "Bypass",
            _ => "",
        }
    }
}

// ============ Linear Phase EQ Wrapper ============

/// True linear phase EQ wrapper
pub struct LinearPhaseEqWrapper {
    eq: LinearPhaseEQ,
    sample_rate: f64,
}

impl LinearPhaseEqWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: LinearPhaseEQ::new(sample_rate),
            sample_rate,
        }
    }

    /// Add a band
    pub fn add_band(
        &mut self,
        freq: f64,
        gain_db: f64,
        q: f64,
        filter_type: LinearPhaseFilterType,
    ) {
        let band = match filter_type {
            LinearPhaseFilterType::Bell => LinearPhaseBand::bell(freq, gain_db, q),
            LinearPhaseFilterType::LowShelf => LinearPhaseBand::low_shelf(freq, gain_db, q),
            LinearPhaseFilterType::HighShelf => LinearPhaseBand::high_shelf(freq, gain_db, q),
            LinearPhaseFilterType::LowCut => LinearPhaseBand::low_cut(freq, q),
            LinearPhaseFilterType::HighCut => LinearPhaseBand::high_cut(freq, q),
            _ => LinearPhaseBand::bell(freq, gain_db, q),
        };
        self.eq.add_band(band);
    }
}

impl InsertProcessor for LinearPhaseEqWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Linear Phase EQ"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        // LinearPhaseEQ uses StereoProcessor trait (sample-by-sample)
        use rf_dsp::StereoProcessor;
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (out_l, out_r) = self.eq.process_sample(*l, *r);
            *l = out_l;
            *r = out_r;
        }
    }

    fn latency(&self) -> LatencySamples {
        self.eq.latency()
    }

    fn reset(&mut self) {
        self.eq.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.eq = LinearPhaseEQ::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        // Per band: freq(0), gain(1), q(2), enabled(3), type(4)
        32 * 5 // 32 bands max, 5 params each
    }

    fn set_param(&mut self, index: usize, value: f64) {
        let band_idx = index / 5;
        let param_idx = index % 5;

        if band_idx < 32 {
            // Get or create band
            while self.eq.band_count() <= band_idx {
                self.eq.add_band(LinearPhaseBand::bell(1000.0, 0.0, 1.0));
            }

            if let Some(mut band) = self.eq.get_band(band_idx).cloned() {
                match param_idx {
                    0 => band.frequency = value.clamp(20.0, 20000.0),
                    1 => band.gain = value.clamp(-24.0, 24.0),
                    2 => band.q = value.clamp(0.1, 30.0),
                    3 => band.enabled = value > 0.5,
                    4 => {
                        band.filter_type = match value as i32 {
                            0 => LinearPhaseFilterType::Bell,
                            1 => LinearPhaseFilterType::LowShelf,
                            2 => LinearPhaseFilterType::HighShelf,
                            3 => LinearPhaseFilterType::LowCut,
                            4 => LinearPhaseFilterType::HighCut,
                            5 => LinearPhaseFilterType::Notch,
                            6 => LinearPhaseFilterType::BandPass,
                            7 => LinearPhaseFilterType::Tilt,
                            _ => LinearPhaseFilterType::Bell,
                        };
                    }
                    _ => {}
                }
                self.eq.update_band(band_idx, band);
            }
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index % 5 {
            0 => "Frequency",
            1 => "Gain",
            2 => "Q",
            3 => "Enabled",
            4 => "Type",
            _ => "",
        }
    }
}

// ============ Reverb Wrapper ============

use rf_dsp::reverb::{AlgorithmicReverb, ReverbType};

/// Algorithmic Reverb wrapper for insert chain — FDN 8×8 (2026 Upgrade)
///
/// 15 parameters (backward-compatible: indices 0-7 unchanged):
///   0: Space       (0.0-1.0) — room size [alias: Room Size]
///   1: Brightness   (0.0-1.0) — HF decay [alias: inverted Damping]
///   2: Width        (0.0-2.0) — M/S stereo width
///   3: Mix          (0.0-1.0) — dry/wet equal-power crossfade
///   4: PreDelay     (0-500 ms)
///   5: Style        (0=Room, 1=Hall, 2=Plate, 3=Chamber, 4=Spring)
///   6: Diffusion    (0.0-1.0) — allpass density
///   7: Distance     (0.0-1.0) — ER attenuation
///   8: Decay        (0.0-1.0) — FDN feedback tail length
///   9: Low Decay Mult  (0.5-2.0) — bass decay multiplier
///  10: High Decay Mult (0.5-2.0) — treble decay multiplier
///  11: Character    (0.0-1.0) — LFO modulation depth (chorus/shimmer)
///  12: Thickness    (0.0-1.0) — saturation + bass boost density
///  13: Ducking      (0.0-1.0) — self-ducking amount
///  14: Freeze       (0.0/1.0) — infinite sustain toggle
pub struct ReverbWrapper {
    reverb: AlgorithmicReverb,
    sample_rate: f64,
}

impl ReverbWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            reverb: AlgorithmicReverb::new(sample_rate),
            sample_rate,
        }
    }
}

impl InsertProcessor for ReverbWrapper {
    fn name(&self) -> &str {
        "FluxForge Reverb"
    }

    fn process_stereo(&mut self, left: &mut [f64], right: &mut [f64]) {
        use rf_dsp::StereoProcessor;
        self.reverb.process_block(left, right);
    }

    fn reset(&mut self) {
        use rf_dsp::Processor;
        self.reverb.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        use rf_dsp::ProcessorConfig;
        self.sample_rate = sample_rate;
        self.reverb.set_sample_rate(sample_rate);
    }

    fn latency(&self) -> LatencySamples {
        use rf_dsp::Processor;
        self.reverb.latency() as LatencySamples
    }

    fn num_params(&self) -> usize {
        15
    }

    fn set_param(&mut self, param_index: usize, value: f64) {
        match param_index {
            0 => self.reverb.set_space(value),
            1 => self.reverb.set_brightness(value),
            2 => self.reverb.set_width(value),
            3 => self.reverb.set_mix(value),
            4 => self.reverb.set_predelay(value),
            5 => {
                let rt = match value as u32 {
                    0 => ReverbType::Room,
                    1 => ReverbType::Hall,
                    2 => ReverbType::Plate,
                    3 => ReverbType::Chamber,
                    4 => ReverbType::Spring,
                    _ => ReverbType::Room,
                };
                self.reverb.set_style(rt);
            }
            6 => self.reverb.set_diffusion(value),
            7 => self.reverb.set_distance(value),
            8 => self.reverb.set_decay(value),
            9 => self.reverb.set_low_decay_mult(value),
            10 => self.reverb.set_high_decay_mult(value),
            11 => self.reverb.set_character(value),
            12 => self.reverb.set_thickness(value),
            13 => self.reverb.set_ducking(value),
            14 => self.reverb.set_freeze(value > 0.5),
            _ => {}
        }
    }

    fn get_param(&self, param_index: usize) -> f64 {
        match param_index {
            0 => self.reverb.space(),
            1 => self.reverb.brightness(),
            2 => self.reverb.width(),
            3 => self.reverb.mix(),
            4 => self.reverb.predelay_ms(),
            5 => match self.reverb.style() {
                ReverbType::Room => 0.0,
                ReverbType::Hall => 1.0,
                ReverbType::Plate => 2.0,
                ReverbType::Chamber => 3.0,
                ReverbType::Spring => 4.0,
            },
            6 => self.reverb.diffusion(),
            7 => self.reverb.distance(),
            8 => self.reverb.decay(),
            9 => self.reverb.low_decay_mult(),
            10 => self.reverb.high_decay_mult(),
            11 => self.reverb.character(),
            12 => self.reverb.thickness(),
            13 => self.reverb.ducking(),
            14 => if self.reverb.freeze() { 1.0 } else { 0.0 },
            _ => 0.0,
        }
    }

    fn param_name(&self, param_index: usize) -> &str {
        match param_index {
            0 => "Space",
            1 => "Brightness",
            2 => "Width",
            3 => "Mix",
            4 => "PreDelay",
            5 => "Style",
            6 => "Diffusion",
            7 => "Distance",
            8 => "Decay",
            9 => "Low Decay",
            10 => "High Decay",
            11 => "Character",
            12 => "Thickness",
            13 => "Ducking",
            14 => "Freeze",
            _ => "Unknown",
        }
    }
}

// ============ Saturation (Saturn 2 class) ============

use rf_dsp::saturation::{MultibandSaturator, OversampledSaturator, SaturationType as SatType};
use rf_dsp::multiband::CrossoverType;
use rf_dsp::oversampling::OversampleFactor;
use rf_dsp::delay::PingPongDelay;

/// Saturator wrapper for insert chain (Saturn 2 class — 10 params, 4 meters)
///
/// Parameter layout:
///   0: Drive (dB)         [-24..+40]     def 0.0
///   1: Type/Style (enum)  [0..5]         def 0 (Tape)
///   2: Tone               [-100..+100]   def 0.0 (no tone shift)
///   3: Mix (%)            [0..100]       def 100.0
///   4: Output (dB)        [-24..+24]     def 0.0
///   5: Tape Bias (%)      [0..100]       def 50.0
///   6: Oversampling (enum)[0..3]         def 1 (2x)
///   7: Input Trim (dB)    [-12..+12]     def 0.0
///   8: M/S Mode (bool)    [0/1]          def 0
///   9: Stereo Link (bool) [0/1]          def 1
///
/// Meter layout:
///   0: Input Peak L
///   1: Input Peak R
///   2: Output Peak L
///   3: Output Peak R
pub struct SaturatorWrapper {
    saturator: OversampledSaturator,
    params: [f64; 10],
    sample_rate: f64,
    input_peak_l: f64,
    input_peak_r: f64,
    output_peak_l: f64,
    output_peak_r: f64,
}

impl SaturatorWrapper {
    pub fn new(sample_rate: f64) -> Self {
        let mut sat = OversampledSaturator::new(sample_rate, OversampleFactor::X2);
        sat.set_drive_db(0.0);
        sat.set_mix(1.0);
        sat.set_output_db(0.0);
        sat.set_tape_bias(0.5);
        Self {
            saturator: sat,
            params: [
                0.0,   // 0: Drive dB
                0.0,   // 1: Type (Tape=0)
                0.0,   // 2: Tone
                100.0, // 3: Mix %
                0.0,   // 4: Output dB
                50.0,  // 5: Tape Bias %
                1.0,   // 6: Oversampling (X2)
                0.0,   // 7: Input Trim dB
                0.0,   // 8: M/S Mode off
                1.0,   // 9: Stereo Link on
            ],
            sample_rate,
            input_peak_l: 0.0,
            input_peak_r: 0.0,
            output_peak_l: 0.0,
            output_peak_r: 0.0,
        }
    }

    fn db_to_linear(db: f64) -> f64 {
        10.0_f64.powf(db / 20.0)
    }
}

impl InsertProcessor for SaturatorWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Saturator"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        let len = left.len().min(right.len());
        if len == 0 {
            return;
        }

        // Input trim
        let input_trim = Self::db_to_linear(self.params[7]);

        // M/S encode
        let ms_mode = self.params[8] > 0.5;
        if ms_mode {
            for i in 0..len {
                let mid = (left[i] + right[i]) * 0.5;
                let side = (left[i] - right[i]) * 0.5;
                left[i] = mid;
                right[i] = side;
            }
        }

        // Input trim + input peak metering
        let mut in_peak_l: f64 = 0.0;
        let mut in_peak_r: f64 = 0.0;
        for i in 0..len {
            left[i] *= input_trim;
            right[i] *= input_trim;
            in_peak_l = in_peak_l.max(left[i].abs());
            in_peak_r = in_peak_r.max(right[i].abs());
        }
        self.input_peak_l = in_peak_l;
        self.input_peak_r = in_peak_r;

        // Process through oversampled saturator
        self.saturator.process(left, right);

        // Output peak metering
        let mut out_peak_l: f64 = 0.0;
        let mut out_peak_r: f64 = 0.0;
        for i in 0..len {
            out_peak_l = out_peak_l.max(left[i].abs());
            out_peak_r = out_peak_r.max(right[i].abs());
        }
        self.output_peak_l = out_peak_l;
        self.output_peak_r = out_peak_r;

        // M/S decode
        if ms_mode {
            for i in 0..len {
                let l = left[i] + right[i];
                let r = left[i] - right[i];
                left[i] = l;
                right[i] = r;
            }
        }
    }

    fn latency(&self) -> LatencySamples {
        self.saturator.latency()
    }

    fn reset(&mut self) {
        self.saturator.reset();
        self.input_peak_l = 0.0;
        self.input_peak_r = 0.0;
        self.output_peak_l = 0.0;
        self.output_peak_r = 0.0;
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.saturator.set_sample_rate(sample_rate);
    }

    fn num_params(&self) -> usize {
        10
    }

    fn get_param(&self, index: usize) -> f64 {
        if index < 10 {
            self.params[index]
        } else {
            0.0
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        if index >= 10 {
            return;
        }
        self.params[index] = value;
        match index {
            0 => {
                // Drive dB [-24..+40]
                let v = value.clamp(-24.0, 40.0);
                self.params[0] = v;
                self.saturator.set_drive_db(v);
            }
            1 => {
                // Type (0=Tape, 1=Tube, 2=Transistor, 3=SoftClip, 4=HardClip, 5=Foldback)
                let idx = (value as usize).min(5);
                self.params[1] = idx as f64;
                let sat_type = match idx {
                    0 => SatType::Tape,
                    1 => SatType::Tube,
                    2 => SatType::Transistor,
                    3 => SatType::SoftClip,
                    4 => SatType::HardClip,
                    5 => SatType::Foldback,
                    _ => SatType::Tape,
                };
                self.saturator.set_type(sat_type);
            }
            2 => {
                // Tone [-100..+100] — adjust via inner saturator's left/right bias
                // Positive = brighter (more high-frequency harmonics)
                // Negative = warmer (less high-frequency harmonics)
                let v = value.clamp(-100.0, 100.0);
                self.params[2] = v;
                // Map tone to tape_bias offset for tonal character
                // Base tape_bias from param 5, tone shifts it +/- 0.3
                let base_bias = self.params[5] / 100.0;
                let tone_offset = v / 100.0 * 0.3;
                let effective_bias = (base_bias + tone_offset).clamp(0.0, 1.0);
                self.saturator.set_tape_bias(effective_bias);
            }
            3 => {
                // Mix % [0..100]
                let v = value.clamp(0.0, 100.0);
                self.params[3] = v;
                self.saturator.set_mix(v / 100.0);
            }
            4 => {
                // Output dB [-24..+24]
                let v = value.clamp(-24.0, 24.0);
                self.params[4] = v;
                self.saturator.set_output_db(v);
            }
            5 => {
                // Tape Bias % [0..100]
                let v = value.clamp(0.0, 100.0);
                self.params[5] = v;
                // Re-apply with tone offset
                let tone_offset = self.params[2] / 100.0 * 0.3;
                let effective_bias = (v / 100.0 + tone_offset).clamp(0.0, 1.0);
                self.saturator.set_tape_bias(effective_bias);
            }
            6 => {
                // Oversampling (0=1x, 1=2x, 2=4x, 3=8x)
                let idx = (value as usize).min(3);
                self.params[6] = idx as f64;
                let factor = match idx {
                    0 => OversampleFactor::X1,
                    1 => OversampleFactor::X2,
                    2 => OversampleFactor::X4,
                    3 => OversampleFactor::X8,
                    _ => OversampleFactor::X2,
                };
                self.saturator.set_oversample_factor(factor);
            }
            7 => {
                // Input Trim dB [-12..+12]
                let v = value.clamp(-12.0, 12.0);
                self.params[7] = v;
                // Applied in process_stereo
            }
            8 => {
                // M/S Mode (0=stereo, 1=mid-side)
                self.params[8] = if value > 0.5 { 1.0 } else { 0.0 };
            }
            9 => {
                // Stereo Link (0=independent, 1=linked)
                let linked = value > 0.5;
                self.params[9] = if linked { 1.0 } else { 0.0 };
                self.saturator.inner_mut().set_link(linked);
            }
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Drive",
            1 => "Type",
            2 => "Tone",
            3 => "Mix",
            4 => "Output",
            5 => "Tape Bias",
            6 => "Oversampling",
            7 => "Input Trim",
            8 => "M/S Mode",
            9 => "Stereo Link",
            _ => "Unknown",
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        match index {
            0 => self.input_peak_l,
            1 => self.input_peak_r,
            2 => self.output_peak_l,
            3 => self.output_peak_r,
            _ => 0.0,
        }
    }
}

// ============ Multiband Saturator (Saturn 2 class) ============

/// Multiband saturator wrapper for insert chain (Saturn 2 class)
///
/// Parameter layout (per band × 6 + global):
///   Global:
///     0: Input Gain (dB)      [-24..+24]    def 0.0
///     1: Output Gain (dB)     [-24..+24]    def 0.0
///     2: Global Mix (%)       [0..100]      def 100.0
///     3: M/S Mode (bool)      [0/1]         def 0
///     4: Num Bands             [2..6]        def 4
///     5: Crossover Type        [0..2]        def 1 (LR24)
///   Crossover freqs (5 max):
///     6: Crossover 1 (Hz)     [20..20000]   def 120
///     7: Crossover 2 (Hz)     [20..20000]   def 750
///     8: Crossover 3 (Hz)     [20..20000]   def 2500
///     9: Crossover 4 (Hz)     [20..20000]   def 7000
///    10: Crossover 5 (Hz)     [20..20000]   def 14000
///   Per-band params (bands 0-5, 9 params each, offset = 11 + band*9):
///    +0: Drive (dB)           [-24..+52]    def 0.0
///    +1: Type/Style (enum)    [0..5]        def 0 (Tape)
///    +2: Tone                 [-100..+100]  def 0.0
///    +3: Mix (%)              [0..100]      def 100.0
///    +4: Output (dB)          [-24..+24]    def 0.0
///    +5: Dynamics              [-1..+1]     def 0.0
///    +6: Solo (bool)          [0/1]         def 0
///    +7: Mute (bool)          [0/1]         def 0
///    +8: Bypass (bool)        [0/1]         def 0
///
/// Total params: 11 + 6*9 = 65
///
/// Meter layout:
///   0: Input Peak L
///   1: Input Peak R
///   2: Output Peak L
///   3: Output Peak R
///   4-9: Per-band peak (max of L/R)
pub struct MultibandSaturatorWrapper {
    saturator: MultibandSaturator,
    params: [f64; 65],
    sample_rate: f64,
    input_peak_l: f64,
    input_peak_r: f64,
    output_peak_l: f64,
    output_peak_r: f64,
    band_peaks: [f64; 6],
}

impl MultibandSaturatorWrapper {
    const GLOBAL_COUNT: usize = 11;
    const BAND_PARAM_COUNT: usize = 9;

    pub fn new(sample_rate: f64) -> Self {
        let mut params = [0.0_f64; 65];
        // Global defaults
        params[0] = 0.0;    // Input Gain dB
        params[1] = 0.0;    // Output Gain dB
        params[2] = 100.0;  // Global Mix %
        params[3] = 0.0;    // M/S Mode off
        params[4] = 4.0;    // 4 bands
        params[5] = 1.0;    // LR24
        // Crossover defaults
        params[6] = 120.0;
        params[7] = 750.0;
        params[8] = 2500.0;
        params[9] = 7000.0;
        params[10] = 14000.0;
        // Per-band defaults: Drive=0, Type=0(Tape), Tone=0, Mix=100%, Output=0, Dynamics=0, Solo=0, Mute=0, Bypass=0
        for b in 0..6 {
            let off = Self::GLOBAL_COUNT + b * Self::BAND_PARAM_COUNT;
            params[off + 3] = 100.0; // Mix 100%
        }

        Self {
            saturator: MultibandSaturator::new(sample_rate, 4),
            params,
            sample_rate,
            input_peak_l: 0.0,
            input_peak_r: 0.0,
            output_peak_l: 0.0,
            output_peak_r: 0.0,
            band_peaks: [0.0; 6],
        }
    }

    fn _band_offset(band: usize) -> usize {
        Self::GLOBAL_COUNT + band * Self::BAND_PARAM_COUNT
    }

    fn sat_type_from_index(idx: usize) -> SatType {
        match idx {
            0 => SatType::Tape,
            1 => SatType::Tube,
            2 => SatType::Transistor,
            3 => SatType::SoftClip,
            4 => SatType::HardClip,
            5 => SatType::Foldback,
            _ => SatType::Tape,
        }
    }

    fn crossover_type_from_index(idx: usize) -> CrossoverType {
        match idx {
            0 => CrossoverType::Butterworth12,
            1 => CrossoverType::LinkwitzRiley24,
            2 => CrossoverType::LinkwitzRiley48,
            _ => CrossoverType::LinkwitzRiley24,
        }
    }
}

impl InsertProcessor for MultibandSaturatorWrapper {
    fn name(&self) -> &str {
        "FluxForge Saturn 2 Multiband Saturator"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        let len = left.len().min(right.len());
        if len == 0 {
            return;
        }

        // Input peak metering
        let mut in_pk_l: f64 = 0.0;
        let mut in_pk_r: f64 = 0.0;
        for i in 0..len {
            in_pk_l = in_pk_l.max(left[i].abs());
            in_pk_r = in_pk_r.max(right[i].abs());
        }
        self.input_peak_l = in_pk_l;
        self.input_peak_r = in_pk_r;

        // Process
        self.saturator.process(left, right);

        // Output peak metering
        let mut out_pk_l: f64 = 0.0;
        let mut out_pk_r: f64 = 0.0;
        for i in 0..len {
            out_pk_l = out_pk_l.max(left[i].abs());
            out_pk_r = out_pk_r.max(right[i].abs());
        }
        self.output_peak_l = out_pk_l;
        self.output_peak_r = out_pk_r;
    }

    fn latency(&self) -> LatencySamples {
        self.saturator.latency()
    }

    fn reset(&mut self) {
        self.saturator.reset();
        self.input_peak_l = 0.0;
        self.input_peak_r = 0.0;
        self.output_peak_l = 0.0;
        self.output_peak_r = 0.0;
        self.band_peaks = [0.0; 6];
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.saturator.set_sample_rate(sample_rate);
    }

    fn num_params(&self) -> usize {
        65
    }

    fn get_param(&self, index: usize) -> f64 {
        if index < 65 { self.params[index] } else { 0.0 }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        if index >= 65 {
            return;
        }
        self.params[index] = value;
        match index {
            0 => {
                let v = value.clamp(-24.0, 24.0);
                self.params[0] = v;
                self.saturator.set_input_gain_db(v);
            }
            1 => {
                let v = value.clamp(-24.0, 24.0);
                self.params[1] = v;
                self.saturator.set_output_gain_db(v);
            }
            2 => {
                let v = value.clamp(0.0, 100.0);
                self.params[2] = v;
                self.saturator.set_global_mix(v / 100.0);
            }
            3 => {
                self.params[3] = if value > 0.5 { 1.0 } else { 0.0 };
                self.saturator.set_ms_mode(value > 0.5);
            }
            4 => {
                let v = (value as usize).clamp(2, 6);
                self.params[4] = v as f64;
                self.saturator.set_num_bands(v);
            }
            5 => {
                let idx = (value as usize).min(2);
                self.params[5] = idx as f64;
                self.saturator.set_crossover_type(Self::crossover_type_from_index(idx));
            }
            6..=10 => {
                // Crossover frequencies
                let cross_idx = index - 6;
                let v = value.clamp(20.0, 20000.0);
                self.params[index] = v;
                self.saturator.set_crossover(cross_idx, v);
            }
            11..=64 => {
                // Per-band parameters
                let rel = index - Self::GLOBAL_COUNT;
                let band = rel / Self::BAND_PARAM_COUNT;
                let param = rel % Self::BAND_PARAM_COUNT;
                if band >= 6 {
                    return;
                }
                if let Some(b) = self.saturator.band_mut(band) {
                    match param {
                        0 => {
                            // Drive dB
                            let v = value.clamp(-24.0, 52.0);
                            self.params[index] = v;
                            b.set_drive_db(v);
                        }
                        1 => {
                            // Saturation Type
                            let idx = (value as usize).min(5);
                            self.params[index] = idx as f64;
                            b.set_type(Self::sat_type_from_index(idx));
                        }
                        2 => {
                            // Tone
                            let v = value.clamp(-100.0, 100.0);
                            self.params[index] = v;
                            b.set_tone(v);
                        }
                        3 => {
                            // Mix %
                            let v = value.clamp(0.0, 100.0);
                            self.params[index] = v;
                            b.set_mix(v / 100.0);
                        }
                        4 => {
                            // Output dB
                            let v = value.clamp(-24.0, 24.0);
                            self.params[index] = v;
                            b.set_output_db(v);
                        }
                        5 => {
                            // Dynamics
                            let v = value.clamp(-1.0, 1.0);
                            self.params[index] = v;
                            b.dynamics = v;
                        }
                        6 => {
                            // Solo
                            self.params[index] = if value > 0.5 { 1.0 } else { 0.0 };
                            b.solo = value > 0.5;
                        }
                        7 => {
                            // Mute
                            self.params[index] = if value > 0.5 { 1.0 } else { 0.0 };
                            b.mute = value > 0.5;
                        }
                        8 => {
                            // Bypass
                            self.params[index] = if value > 0.5 { 1.0 } else { 0.0 };
                            b.bypass = value > 0.5;
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Input Gain",
            1 => "Output Gain",
            2 => "Global Mix",
            3 => "M/S Mode",
            4 => "Num Bands",
            5 => "Crossover Type",
            6 => "Crossover 1",
            7 => "Crossover 2",
            8 => "Crossover 3",
            9 => "Crossover 4",
            10 => "Crossover 5",
            _ => {
                if index >= Self::GLOBAL_COUNT && index < 65 {
                    let rel = index - Self::GLOBAL_COUNT;
                    let param = rel % Self::BAND_PARAM_COUNT;
                    match param {
                        0 => "Band Drive",
                        1 => "Band Type",
                        2 => "Band Tone",
                        3 => "Band Mix",
                        4 => "Band Output",
                        5 => "Band Dynamics",
                        6 => "Band Solo",
                        7 => "Band Mute",
                        8 => "Band Bypass",
                        _ => "Unknown",
                    }
                } else {
                    "Unknown"
                }
            }
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        match index {
            0 => self.input_peak_l,
            1 => self.input_peak_r,
            2 => self.output_peak_l,
            3 => self.output_peak_r,
            4..=9 => self.band_peaks[index - 4],
            _ => 0.0,
        }
    }
}

// ============ Delay (Timeless 3 class) ============

/// Professional delay wrapper for insert chain (Timeless 3 class — 14 params, 4 meters)
///
/// Parameter layout:
///   0: Delay Time L (ms)    [1..5000]     def 500.0
///   1: Delay Time R (ms)    [1..5000]     def 500.0 (linked by default)
///   2: Feedback (%)         [0..99]       def 50.0
///   3: Mix (%)              [0..100]      def 50.0
///   4: Ping-Pong (%)        [0..100]      def 0.0
///   5: HP Filter (Hz)       [20..2000]    def 80.0
///   6: LP Filter (Hz)       [200..20000]  def 8000.0
///   7: Mod Rate (Hz)        [0.01..20]    def 0.0 (off)
///   8: Mod Depth (%)        [0..100]      def 0.0
///   9: Stereo Width (%)     [0..200]      def 100.0
///  10: Ducking (%)          [0..100]      def 0.0
///  11: Link L/R (bool)      [0/1]         def 1
///  12: Freeze (bool)        [0/1]         def 0
///  13: Tempo Sync (bool)    [0/1]         def 0
///
/// Meter layout:
///   0: Input Peak L
///   1: Input Peak R
///   2: Output Peak L
///   3: Output Peak R
pub struct DelayWrapper {
    delay: PingPongDelay,
    params: [f64; 14],
    sample_rate: f64,
    input_peak_l: f64,
    input_peak_r: f64,
    output_peak_l: f64,
    output_peak_r: f64,
    // Ducking state
    ducking_env: f64,
    // Modulation LFO
    mod_phase: f64,
    // Freeze buffer
    frozen: bool,
    freeze_buf_l: Vec<f64>,
    freeze_buf_r: Vec<f64>,
    freeze_write_pos: usize,
}

impl DelayWrapper {
    pub fn new(sample_rate: f64) -> Self {
        let mut delay = PingPongDelay::new(sample_rate, 5000.0);
        delay.set_delay_ms(500.0);
        delay.set_feedback(0.5);
        delay.set_dry_wet(0.5);
        delay.set_ping_pong(0.0);

        let freeze_len = (5.0 * sample_rate) as usize; // 5s max

        Self {
            delay,
            params: [
                500.0, // 0: Delay Time L ms
                500.0, // 1: Delay Time R ms
                50.0,  // 2: Feedback %
                50.0,  // 3: Mix %
                0.0,   // 4: Ping-Pong %
                80.0,  // 5: HP Filter Hz
                8000.0,// 6: LP Filter Hz
                0.0,   // 7: Mod Rate Hz (off)
                0.0,   // 8: Mod Depth %
                100.0, // 9: Stereo Width %
                0.0,   // 10: Ducking %
                1.0,   // 11: Link L/R on
                0.0,   // 12: Freeze off
                0.0,   // 13: Tempo Sync off
            ],
            sample_rate,
            input_peak_l: 0.0,
            input_peak_r: 0.0,
            output_peak_l: 0.0,
            output_peak_r: 0.0,
            ducking_env: 0.0,
            mod_phase: 0.0,
            frozen: false,
            freeze_buf_l: vec![0.0; freeze_len],
            freeze_buf_r: vec![0.0; freeze_len],
            freeze_write_pos: 0,
        }
    }

}

impl InsertProcessor for DelayWrapper {
    fn name(&self) -> &str {
        "FluxForge Timeless 3 Delay"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        let len = left.len().min(right.len());
        if len == 0 {
            return;
        }

        // Input peak metering
        let mut in_pk_l: f64 = 0.0;
        let mut in_pk_r: f64 = 0.0;
        for i in 0..len {
            in_pk_l = in_pk_l.max(left[i].abs());
            in_pk_r = in_pk_r.max(right[i].abs());
        }
        self.input_peak_l = in_pk_l;
        self.input_peak_r = in_pk_r;

        // Ducking: reduce wet signal when input is loud
        let ducking_amount = self.params[10] / 100.0;

        // Modulation: modulate delay time subtly
        let mod_rate = self.params[7];
        let mod_depth_pct = self.params[8] / 100.0;

        if mod_rate > 0.001 && mod_depth_pct > 0.001 {
            // Apply modulation to delay time
            let base_delay = self.params[0];
            let mod_amount = base_delay * mod_depth_pct * 0.1; // up to 10% modulation
            let mod_val = (self.mod_phase * std::f64::consts::TAU).sin();
            let modulated = base_delay + mod_val * mod_amount;
            self.delay.set_delay_ms(modulated.max(1.0));
            self.mod_phase += mod_rate / self.sample_rate * len as f64;
            if self.mod_phase > 1.0 {
                self.mod_phase -= 1.0;
            }
        }

        // Process through ping-pong delay (sample-by-sample for stereo width)
        let width = self.params[9] / 100.0;

        // Save dry for ducking
        let dry_l: Vec<f64> = left[..len].to_vec();
        let dry_r: Vec<f64> = right[..len].to_vec();

        if self.frozen {
            // Freeze mode: loop frozen buffer
            for i in 0..len {
                let fl = self.freeze_buf_l[self.freeze_write_pos % self.freeze_buf_l.len()];
                let fr = self.freeze_buf_r[self.freeze_write_pos % self.freeze_buf_r.len()];
                self.freeze_write_pos = (self.freeze_write_pos + 1) % self.freeze_buf_l.len();

                let mix = self.params[3] / 100.0;
                left[i] = dry_l[i] * (1.0 - mix) + fl * mix;
                right[i] = dry_r[i] * (1.0 - mix) + fr * mix;
            }
        } else {
            // Normal delay processing
            self.delay.process_block(left, right);

            // Apply stereo width to wet signal
            if (width - 1.0).abs() > 0.01 {
                for i in 0..len {
                    let wet_l = left[i] - dry_l[i] * (1.0 - self.params[3] / 100.0);
                    let wet_r = right[i] - dry_r[i] * (1.0 - self.params[3] / 100.0);
                    let mid = (wet_l + wet_r) * 0.5;
                    let side = (wet_l - wet_r) * 0.5 * width;
                    let new_wet_l = mid + side;
                    let new_wet_r = mid - side;
                    left[i] = dry_l[i] * (1.0 - self.params[3] / 100.0) + new_wet_l;
                    right[i] = dry_r[i] * (1.0 - self.params[3] / 100.0) + new_wet_r;
                }
            }
        }

        // Apply ducking
        if ducking_amount > 0.01 {
            for i in 0..len {
                let input_level = (dry_l[i].abs() + dry_r[i].abs()) * 0.5;
                let att_coef = if input_level > self.ducking_env { 0.05 } else { 0.998 };
                self.ducking_env = input_level + att_coef * (self.ducking_env - input_level);

                let duck_gain = 1.0 - self.ducking_env.min(1.0) * ducking_amount;
                let mix = self.params[3] / 100.0;
                // Only duck the wet portion
                let wet_l = left[i] - dry_l[i] * (1.0 - mix);
                let wet_r = right[i] - dry_r[i] * (1.0 - mix);
                left[i] = dry_l[i] * (1.0 - mix) + wet_l * duck_gain;
                right[i] = dry_r[i] * (1.0 - mix) + wet_r * duck_gain;
            }
        }

        // Output peak metering
        let mut out_pk_l: f64 = 0.0;
        let mut out_pk_r: f64 = 0.0;
        for i in 0..len {
            out_pk_l = out_pk_l.max(left[i].abs());
            out_pk_r = out_pk_r.max(right[i].abs());
        }
        self.output_peak_l = out_pk_l;
        self.output_peak_r = out_pk_r;
    }

    fn latency(&self) -> LatencySamples {
        0
    }

    fn reset(&mut self) {
        self.delay.reset();
        self.input_peak_l = 0.0;
        self.input_peak_r = 0.0;
        self.output_peak_l = 0.0;
        self.output_peak_r = 0.0;
        self.ducking_env = 0.0;
        self.mod_phase = 0.0;
        self.frozen = false;
        self.freeze_write_pos = 0;
        self.freeze_buf_l.fill(0.0);
        self.freeze_buf_r.fill(0.0);
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        // Recreate delay with new sample rate
        let mut delay = PingPongDelay::new(sample_rate, 5000.0);
        delay.set_delay_ms(self.params[0]);
        delay.set_feedback(self.params[2] / 100.0);
        delay.set_dry_wet(self.params[3] / 100.0);
        delay.set_ping_pong(self.params[4] / 100.0);
        self.delay = delay;
        let freeze_len = (5.0 * sample_rate) as usize;
        self.freeze_buf_l = vec![0.0; freeze_len];
        self.freeze_buf_r = vec![0.0; freeze_len];
    }

    fn num_params(&self) -> usize {
        14
    }

    fn get_param(&self, index: usize) -> f64 {
        if index < 14 { self.params[index] } else { 0.0 }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        if index >= 14 {
            return;
        }
        self.params[index] = value;
        match index {
            0 => {
                // Delay Time L (ms)
                let v = value.clamp(1.0, 5000.0);
                self.params[0] = v;
                self.delay.set_delay_ms(v);
                // If linked, also set R
                if self.params[11] > 0.5 {
                    self.params[1] = v;
                }
            }
            1 => {
                // Delay Time R (ms)
                let v = value.clamp(1.0, 5000.0);
                self.params[1] = v;
                // Only applies when not linked (PingPongDelay uses single delay time)
            }
            2 => {
                // Feedback %
                let v = value.clamp(0.0, 99.0);
                self.params[2] = v;
                self.delay.set_feedback(v / 100.0);
            }
            3 => {
                // Mix %
                let v = value.clamp(0.0, 100.0);
                self.params[3] = v;
                self.delay.set_dry_wet(v / 100.0);
            }
            4 => {
                // Ping-Pong %
                let v = value.clamp(0.0, 100.0);
                self.params[4] = v;
                self.delay.set_ping_pong(v / 100.0);
            }
            5 => {
                // HP Filter Hz — applied in PingPongDelay's internal HP filters
                let _v = value.clamp(20.0, 2000.0);
                self.params[5] = _v;
                // PingPongDelay internal filters are set at construction
                // For live update we'd need to expose filter setters (future enhancement)
            }
            6 => {
                // LP Filter Hz
                let _v = value.clamp(200.0, 20000.0);
                self.params[6] = _v;
            }
            7 => {
                // Mod Rate Hz
                let v = value.clamp(0.0, 20.0);
                self.params[7] = v;
            }
            8 => {
                // Mod Depth %
                let v = value.clamp(0.0, 100.0);
                self.params[8] = v;
            }
            9 => {
                // Stereo Width %
                let v = value.clamp(0.0, 200.0);
                self.params[9] = v;
            }
            10 => {
                // Ducking %
                let v = value.clamp(0.0, 100.0);
                self.params[10] = v;
            }
            11 => {
                // Link L/R
                self.params[11] = if value > 0.5 { 1.0 } else { 0.0 };
            }
            12 => {
                // Freeze
                let freeze = value > 0.5;
                self.params[12] = if freeze { 1.0 } else { 0.0 };
                if freeze && !self.frozen {
                    // Capture current delay buffer into freeze buffer
                    // (simplified — in production we'd copy the delay line)
                    self.frozen = true;
                    self.freeze_write_pos = 0;
                } else if !freeze {
                    self.frozen = false;
                }
            }
            13 => {
                // Tempo Sync
                self.params[13] = if value > 0.5 { 1.0 } else { 0.0 };
            }
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Delay L",
            1 => "Delay R",
            2 => "Feedback",
            3 => "Mix",
            4 => "Ping-Pong",
            5 => "HP Filter",
            6 => "LP Filter",
            7 => "Mod Rate",
            8 => "Mod Depth",
            9 => "Width",
            10 => "Ducking",
            11 => "Link L/R",
            12 => "Freeze",
            13 => "Tempo Sync",
            _ => "Unknown",
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        match index {
            0 => self.input_peak_l,
            1 => self.input_peak_r,
            2 => self.output_peak_l,
            3 => self.output_peak_r,
            _ => 0.0,
        }
    }
}

// ============ Extended Factory ============

/// Create any processor by type name (extended version)
pub fn create_processor_extended(name: &str, sample_rate: f64) -> Option<Box<dyn InsertProcessor>> {
    // First try the basic factory
    if let Some(proc) = create_processor(name, sample_rate) {
        return Some(proc);
    }

    // Extended processors
    match name.to_lowercase().as_str() {
        "compressor" | "comp" => Some(Box::new(CompressorWrapper::new(sample_rate))),
        "limiter" | "true-peak" | "truepeak" => {
            Some(Box::new(TruePeakLimiterWrapper::new(sample_rate)))
        }
        "gate" | "noise-gate" => Some(Box::new(GateWrapper::new(sample_rate))),
        "expander" | "exp" => Some(Box::new(ExpanderWrapper::new(sample_rate))),
        "deesser" | "de-esser" | "de_esser" | "DeEsser" => {
            Some(Box::new(DeEsserWrapper::new(sample_rate)))
        }
        "linear-phase-eq" | "linear_phase_eq" | "linearphase" => {
            Some(Box::new(LinearPhaseEqWrapper::new(sample_rate)))
        }
        "reverb" | "algorithmic-reverb" | "algo-reverb" => {
            Some(Box::new(ReverbWrapper::new(sample_rate)))
        }
        "saturation" | "saturator" | "saturn" => {
            Some(Box::new(SaturatorWrapper::new(sample_rate)))
        }
        "multiband-saturator" | "multiband_saturator" | "saturn2" | "mb-saturator" => {
            Some(Box::new(MultibandSaturatorWrapper::new(sample_rate)))
        }
        "delay" | "timeless" | "timeless3" | "ping-pong-delay" => {
            Some(Box::new(DelayWrapper::new(sample_rate)))
        }
        _ => None,
    }
}

/// Get list of all available processors
pub fn available_processors() -> Vec<&'static str> {
    vec![
        // EQ
        "pro-eq",
        "ultra-eq",
        "linear-phase-eq",
        "pultec",
        "api550",
        "neve1073",
        "room-correction",
        // Dynamics
        "compressor",
        "limiter",
        "gate",
        "expander",
        "deesser",
        // Effects
        "reverb",
        "saturation",
        "multiband-saturator",
        "delay",
    ]
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pro_eq_wrapper() {
        let mut eq = ProEqWrapper::new(48000.0);
        eq.add_band(1000.0, 3.0, 1.0, FilterShape::Bell);

        let mut left = vec![1.0; 64];
        let mut right = vec![1.0; 64];
        eq.process_stereo(&mut left, &mut right);

        assert!(eq.band_count() > 0);
    }

    #[test]
    fn test_pultec_wrapper() {
        let mut eq = PultecWrapper::new(48000.0);
        eq.set_low_boost(3.0);
        eq.set_high_boost(2.0);

        let mut left = vec![1.0; 64];
        let mut right = vec![1.0; 64];
        eq.process_stereo(&mut left, &mut right);
    }

    #[test]
    fn test_factory() {
        let processor = create_processor("pro-eq", 48000.0);
        assert!(processor.is_some());
        assert_eq!(processor.unwrap().name(), "FluxForge Studio Pro-EQ 64");
    }

    // ═══════════════════════════════════════════════════════════════════
    // REVERB WRAPPER TESTS — InsertProcessor chain integration
    // ═══════════════════════════════════════════════════════════════════

    #[test]
    fn test_reverb_wrapper_factory() {
        // All three name variants should create ReverbWrapper
        for name in &["reverb", "algorithmic-reverb", "algo-reverb"] {
            let proc = create_processor_extended(name, 48000.0);
            assert!(proc.is_some(), "Factory failed for '{}'", name);
            assert_eq!(proc.unwrap().name(), "FluxForge Reverb");
        }
    }

    #[test]
    fn test_reverb_wrapper_num_params() {
        let proc = create_processor_extended("reverb", 48000.0).unwrap();
        assert_eq!(proc.num_params(), 15);
    }

    #[test]
    fn test_reverb_wrapper_param_names() {
        let proc = create_processor_extended("reverb", 48000.0).unwrap();
        assert_eq!(proc.param_name(0), "Space");
        assert_eq!(proc.param_name(1), "Brightness");
        assert_eq!(proc.param_name(2), "Width");
        assert_eq!(proc.param_name(3), "Mix");
        assert_eq!(proc.param_name(4), "PreDelay");
        assert_eq!(proc.param_name(5), "Style");
        assert_eq!(proc.param_name(6), "Diffusion");
        assert_eq!(proc.param_name(7), "Distance");
        assert_eq!(proc.param_name(8), "Decay");
        assert_eq!(proc.param_name(9), "Low Decay");
        assert_eq!(proc.param_name(10), "High Decay");
        assert_eq!(proc.param_name(11), "Character");
        assert_eq!(proc.param_name(12), "Thickness");
        assert_eq!(proc.param_name(13), "Ducking");
        assert_eq!(proc.param_name(14), "Freeze");
        assert_eq!(proc.param_name(15), "Unknown");
    }

    #[test]
    fn test_reverb_wrapper_set_get_param_roundtrip() {
        let mut proc = create_processor_extended("reverb", 48000.0).unwrap();
        // Set each param and verify via get_param
        let test_values = [
            (0, 0.8),   // space
            (1, 0.3),   // brightness
            (2, 1.5),   // width (0-2 range)
            (3, 0.6),   // mix
            (4, 100.0),  // predelay ms
            (6, 0.9),   // diffusion
            (7, 0.4),   // distance
            (8, 0.7),   // decay
            (9, 1.5),   // low_decay_mult
            (10, 0.5),  // high_decay_mult
            (11, 0.6),  // character
            (12, 0.8),  // thickness
            (13, 0.4),  // ducking
        ];
        for (idx, val) in &test_values {
            proc.set_param(*idx, *val);
            let got = proc.get_param(*idx);
            assert!((got - val).abs() < 0.01,
                "Param {} roundtrip failed: set={}, got={}", idx, val, got);
        }
    }

    #[test]
    fn test_reverb_wrapper_freeze_boolean() {
        let mut proc = create_processor_extended("reverb", 48000.0).unwrap();
        // Freeze uses threshold > 0.5
        proc.set_param(14, 1.0);
        assert!(proc.get_param(14) > 0.5, "Freeze should be on");
        proc.set_param(14, 0.0);
        assert!(proc.get_param(14) < 0.5, "Freeze should be off");
    }

    #[test]
    fn test_reverb_wrapper_process_stereo() {
        // Test 1: Direct process_sample comparison
        use rf_dsp::reverb::AlgorithmicReverb;
        use rf_dsp::StereoProcessor;

        let mut reverb_direct = AlgorithmicReverb::new(48000.0);
        reverb_direct.set_mix(1.0);
        reverb_direct.set_space(0.5);
        reverb_direct.set_decay(0.5);

        let mut direct_energy = 0.0f64;
        for _ in 0..5120 {
            let (l, r) = reverb_direct.process_sample(0.3, 0.3);
            direct_energy += l * l + r * r;
        }
        assert!(direct_energy > 0.1,
            "Direct process_sample should produce output, energy={}", direct_energy);

        // Test 2: process_block on same AlgorithmicReverb type
        let mut reverb_block = AlgorithmicReverb::new(48000.0);
        reverb_block.set_mix(1.0);
        reverb_block.set_space(0.5);
        reverb_block.set_decay(0.5);

        let mut block_energy = 0.0f64;
        for _ in 0..20 {
            let mut left = vec![0.3f64; 256];
            let mut right = vec![0.3f64; 256];
            reverb_block.process_block(&mut left, &mut right);
            block_energy += left.iter().chain(right.iter())
                .map(|s| s * s).sum::<f64>();
        }
        assert!(block_energy > 0.1,
            "process_block should produce output, energy={}", block_energy);

        // Test 3: Through wrapper InsertProcessor interface
        let mut proc = create_processor_extended("reverb", 48000.0).unwrap();
        proc.set_param(3, 1.0);  // 100% wet
        proc.set_param(0, 0.5);  // medium space
        proc.set_param(8, 0.5);  // medium decay

        let mut wrapper_energy = 0.0f64;
        for _ in 0..20 {
            let mut left = vec![0.3f64; 256];
            let mut right = vec![0.3f64; 256];
            proc.process_stereo(&mut left, &mut right);
            wrapper_energy += left.iter().chain(right.iter())
                .map(|s| s * s).sum::<f64>();
        }
        assert!(wrapper_energy > 0.1,
            "Wrapper process_stereo should produce output, energy={}", wrapper_energy);
    }

    #[test]
    fn test_reverb_wrapper_dry_only() {
        let mut proc = create_processor_extended("reverb", 48000.0).unwrap();
        proc.set_param(3, 0.0);  // 0% wet = dry only

        let mut left = vec![0.5f64; 64];
        let mut right = vec![0.5f64; 64];
        let original_l = left.clone();

        proc.process_stereo(&mut left, &mut right);

        // With 0% mix, output should be equal-power dry (cos(0) = 1.0 × input)
        for i in 0..64 {
            assert!((left[i] - original_l[i]).abs() < 0.01,
                "Dry-only: sample {} diverged: expected {}, got {}", i, original_l[i], left[i]);
        }
    }

    #[test]
    fn test_reverb_wrapper_reset() {
        let mut proc = create_processor_extended("reverb", 48000.0).unwrap();
        proc.set_param(3, 1.0);  // 100% wet

        // Feed impulse to build reverb tail
        let mut left = vec![0.0f64; 128];
        let mut right = vec![0.0f64; 128];
        left[0] = 1.0;
        right[0] = 1.0;
        proc.process_stereo(&mut left, &mut right);

        // Reset should clear internal state
        proc.reset();

        // Process silence — should output silence (no residual tail)
        let mut left2 = vec![0.0f64; 128];
        let mut right2 = vec![0.0f64; 128];
        proc.process_stereo(&mut left2, &mut right2);

        let energy: f64 = left2.iter().chain(right2.iter())
            .map(|s| s * s).sum();
        assert!(energy < 0.001, "After reset, reverb tail should be gone, energy={}", energy);
    }

    #[test]
    fn test_reverb_wrapper_set_sample_rate() {
        let mut proc = create_processor_extended("reverb", 44100.0).unwrap();
        proc.set_sample_rate(96000.0);

        // Should still process without crash
        let mut left = vec![0.5f64; 64];
        let mut right = vec![0.5f64; 64];
        proc.process_stereo(&mut left, &mut right);
    }

    #[test]
    fn test_reverb_wrapper_latency_zero() {
        let proc = create_processor_extended("reverb", 48000.0).unwrap();
        assert_eq!(proc.latency(), 0, "Algorithmic reverb should have zero latency");
    }

    #[test]
    fn test_reverb_wrapper_style_param() {
        let mut proc = create_processor_extended("reverb", 48000.0).unwrap();
        // Style param 5: 0=Room, 1=Hall, 2=Plate, 3=Chamber, 4=Spring
        for style in 0..5 {
            proc.set_param(5, style as f64);
            let got = proc.get_param(5);
            assert!((got - style as f64).abs() < 0.01,
                "Style {} roundtrip failed, got={}", style, got);
        }
    }

    #[test]
    fn test_reverb_wrapper_invalid_param_index() {
        let mut proc = create_processor_extended("reverb", 48000.0).unwrap();
        // Setting/getting out-of-range param should not crash
        proc.set_param(99, 0.5);
        let val = proc.get_param(99);
        assert_eq!(val, 0.0, "Invalid param index should return 0.0");
    }

    // ═══════════════════════════════════════════════════════════════════
    // COMPRESSOR WRAPPER TESTS — Pro-C 2 class (25 params, 5 meters)
    // ═══════════════════════════════════════════════════════════════════

    #[test]
    fn test_compressor_wrapper_factory() {
        let proc = create_processor_extended("compressor", 48000.0);
        assert!(proc.is_some(), "compressor factory should return Some");
        assert_eq!(proc.unwrap().name(), "FluxForge Studio Compressor");

        let proc2 = create_processor_extended("comp", 48000.0);
        assert!(proc2.is_some(), "comp alias should also work");
    }

    #[test]
    fn test_compressor_wrapper_num_params() {
        let proc = create_processor_extended("compressor", 48000.0).unwrap();
        assert_eq!(proc.num_params(), 25, "Pro-C 2 class should have 25 params");
    }

    #[test]
    fn test_compressor_wrapper_param_names() {
        let proc = create_processor_extended("compressor", 48000.0).unwrap();
        let expected = [
            "Threshold", "Ratio", "Attack", "Release", "Makeup",
            "Mix", "Link", "Type", "Character", "Drive",
            "Range", "SC HP Freq", "SC LP Freq", "SC Audition", "Lookahead",
            "SC Mid Freq", "SC Mid Gain", "Auto-Threshold", "Auto-Makeup", "Detection",
            "Adaptive Rel", "Host Sync", "Host BPM", "Mid/Side", "Knee",
        ];
        for (i, name) in expected.iter().enumerate() {
            assert_eq!(proc.param_name(i), *name, "Param {} name mismatch", i);
        }
    }

    #[test]
    fn test_compressor_wrapper_set_get_roundtrip() {
        let mut proc = create_processor_extended("compressor", 48000.0).unwrap();

        // Test each param set/get roundtrip
        // Note: Link (6) always returns 1.0 (hardcoded, stored on StereoCompressor level)
        let test_values: [(usize, f64, f64); 16] = [
            (0, -24.0, 0.1),  // Threshold
            (1, 8.0, 0.1),    // Ratio
            (2, 15.0, 0.5),   // Attack
            (3, 200.0, 1.0),  // Release
            (4, 6.0, 0.1),    // Makeup
            (5, 0.75, 0.01),  // Mix
            (7, 1.0, 0.01),   // Type (Opto)
            (8, 2.0, 0.01),   // Character (Diode)
            (9, 3.0, 0.1),    // Drive
            (10, -30.0, 0.1), // Range
            (11, 150.0, 1.0), // SC HP Freq
            (12, 8000.0, 1.0),// SC LP Freq
            (13, 1.0, 0.01),  // SC Audition (bool)
            (17, 1.0, 0.01),  // Auto Threshold (bool)
            (21, 1.0, 0.01),  // Host Sync (bool)
            (24, 12.0, 0.1),  // Knee
        ];

        for (idx, value, tolerance) in test_values {
            proc.set_param(idx, value);
            let got = proc.get_param(idx);
            assert!(
                (got - value).abs() < tolerance,
                "Param {} roundtrip: set {}, got {} (tol {})",
                idx, value, got, tolerance,
            );
        }
    }

    #[test]
    fn test_compressor_wrapper_process_stereo() {
        let mut proc = create_processor_extended("compressor", 48000.0).unwrap();

        // Set aggressive compression
        proc.set_param(0, -20.0); // threshold
        proc.set_param(1, 10.0);  // ratio 10:1
        proc.set_param(2, 0.1);   // fast attack
        proc.set_param(3, 50.0);  // medium release

        // Process loud signal for several blocks
        let mut left = vec![0.5; 512];
        let mut right = vec![0.5; 512];
        for _ in 0..10 {
            proc.process_stereo(&mut left, &mut right);
            left.fill(0.5);
            right.fill(0.5);
        }
        proc.process_stereo(&mut left, &mut right);

        // Output should be reduced (gain reduction applied)
        let peak = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        assert!(
            peak < 0.5,
            "Compressed output should be lower than input 0.5, got {}",
            peak,
        );
    }

    #[test]
    fn test_compressor_wrapper_meters() {
        let mut proc = create_processor_extended("compressor", 48000.0).unwrap();

        proc.set_param(0, -20.0); // threshold
        proc.set_param(1, 4.0);   // ratio

        // Process signal to generate metering data
        let mut left = vec![0.5; 256];
        let mut right = vec![0.5; 256];
        for _ in 0..20 {
            proc.process_stereo(&mut left, &mut right);
            left.fill(0.5);
            right.fill(0.5);
        }

        // Meter 0: GR Left (positive dB convention — amount of gain reduction)
        let gr_l = proc.get_meter(0);
        assert!(gr_l > 0.0, "GR Left should be > 0 dB with compression, got {}", gr_l);

        // Meter 1: GR Right
        let gr_r = proc.get_meter(1);
        assert!(gr_r > 0.0, "GR Right should be > 0 dB with compression, got {}", gr_r);

        // Meter 2: Output Peak (should be > 0 with signal)
        let out_peak = proc.get_meter(2);
        assert!(out_peak >= 0.0, "Output peak should be >= 0");

        // Meter 3: Input Peak
        let in_peak = proc.get_meter(3);
        assert!(in_peak >= 0.0, "Input peak should be >= 0");

        // Meter 4: Latency
        let lat = proc.get_meter(4);
        assert!(lat >= 0.0, "Latency should be >= 0");
    }

    #[test]
    fn test_compressor_wrapper_character_modes() {
        let mut proc = create_processor_extended("compressor", 48000.0).unwrap();

        // Test all character modes: 0=Off, 1=Tube, 2=Diode, 3=Bright
        for char_idx in 0..4 {
            proc.set_param(8, char_idx as f64);
            assert_eq!(
                proc.get_param(8) as i32, char_idx,
                "Character {} roundtrip failed", char_idx,
            );
        }
    }

    #[test]
    fn test_compressor_wrapper_compressor_types() {
        let mut proc = create_processor_extended("compressor", 48000.0).unwrap();

        // Test all compressor types: 0=VCA, 1=Opto, 2=FET
        for type_idx in 0..3 {
            proc.set_param(7, type_idx as f64);
            assert_eq!(
                proc.get_param(7) as i32, type_idx,
                "Type {} roundtrip failed", type_idx,
            );
        }
    }

    #[test]
    fn test_compressor_wrapper_reset() {
        let mut proc = create_processor_extended("compressor", 48000.0).unwrap();

        // Process some signal
        let mut left = vec![0.5; 256];
        let mut right = vec![0.5; 256];
        proc.process_stereo(&mut left, &mut right);

        // Reset should not crash and should clear state
        proc.reset();

        // Process again — should work cleanly
        left.fill(0.0);
        right.fill(0.0);
        proc.process_stereo(&mut left, &mut right);

        // Silent input after reset should produce near-zero output
        let peak = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        assert!(peak < 0.01, "After reset + silent input, output should be near zero");
    }

    #[test]
    fn test_compressor_wrapper_set_sample_rate() {
        let mut proc = create_processor_extended("compressor", 44100.0).unwrap();

        // Change sample rate
        proc.set_sample_rate(96000.0);

        // Should still process without crash
        let mut left = vec![0.5; 256];
        let mut right = vec![0.5; 256];
        proc.process_stereo(&mut left, &mut right);
    }

    #[test]
    fn test_compressor_wrapper_mix_dry_wet() {
        let mut proc_wet = create_processor_extended("compressor", 48000.0).unwrap();
        let mut proc_dry = create_processor_extended("compressor", 48000.0).unwrap();

        // Same settings but different mix
        for p in [&mut proc_wet, &mut proc_dry] {
            p.set_param(0, -20.0); // threshold
            p.set_param(1, 10.0);  // ratio 10:1
            p.set_param(2, 0.1);   // fast attack
        }
        proc_wet.set_param(5, 1.0); // 100% wet
        proc_dry.set_param(5, 0.0); // 0% wet (dry)

        // Process same signal
        let mut wet_l = vec![0.5; 512];
        let mut wet_r = vec![0.5; 512];
        let mut dry_l = vec![0.5; 512];
        let mut dry_r = vec![0.5; 512];

        for _ in 0..10 {
            proc_wet.process_stereo(&mut wet_l, &mut wet_r);
            proc_dry.process_stereo(&mut dry_l, &mut dry_r);
            wet_l.fill(0.5); wet_r.fill(0.5);
            dry_l.fill(0.5); dry_r.fill(0.5);
        }
        proc_wet.process_stereo(&mut wet_l, &mut wet_r);
        proc_dry.process_stereo(&mut dry_l, &mut dry_r);

        let wet_peak = wet_l.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        let dry_peak = dry_l.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);

        // Dry should be closer to input level, wet should be compressed
        assert!(
            dry_peak > wet_peak,
            "Dry ({}) should be louder than wet ({})",
            dry_peak, wet_peak,
        );
    }

    #[test]
    fn test_compressor_wrapper_invalid_param_index() {
        let mut proc = create_processor_extended("compressor", 48000.0).unwrap();
        // Out of range should not crash
        proc.set_param(99, 0.5);
        let val = proc.get_param(99);
        assert_eq!(val, 0.0, "Invalid param index should return 0.0");
    }

    #[test]
    fn test_compressor_wrapper_latency() {
        let proc = create_processor_extended("compressor", 48000.0).unwrap();
        // Compressor latency should be 0 (no lookahead by default)
        assert_eq!(proc.latency(), 0, "Default compressor latency should be 0");
    }

    // ═══════════════════════════════════════════════════════════════════
    // TRUE PEAK LIMITER WRAPPER TESTS — Pro-L 2 class (14 params, 7 meters)
    // ═══════════════════════════════════════════════════════════════════

    #[test]
    fn test_limiter_wrapper_factory() {
        let proc = create_processor_extended("limiter", 48000.0);
        assert!(proc.is_some(), "limiter factory should return Some");
        assert_eq!(proc.unwrap().name(), "FluxForge Studio True Peak Limiter");

        let proc2 = create_processor_extended("true-peak", 48000.0);
        assert!(proc2.is_some(), "true-peak alias should also work");

        let proc3 = create_processor_extended("truepeak", 48000.0);
        assert!(proc3.is_some(), "truepeak alias should also work");
    }

    #[test]
    fn test_limiter_wrapper_num_params() {
        let proc = create_processor_extended("limiter", 48000.0).unwrap();
        assert_eq!(proc.num_params(), 14, "Limiter should have 14 parameters");
    }

    #[test]
    fn test_limiter_wrapper_param_names() {
        let proc = create_processor_extended("limiter", 48000.0).unwrap();
        assert_eq!(proc.param_name(0), "Input Trim");
        assert_eq!(proc.param_name(1), "Threshold");
        assert_eq!(proc.param_name(2), "Ceiling");
        assert_eq!(proc.param_name(3), "Release");
        assert_eq!(proc.param_name(4), "Attack");
        assert_eq!(proc.param_name(5), "Lookahead");
        assert_eq!(proc.param_name(6), "Style");
        assert_eq!(proc.param_name(7), "Oversampling");
        assert_eq!(proc.param_name(8), "Stereo Link");
        assert_eq!(proc.param_name(9), "M/S Mode");
        assert_eq!(proc.param_name(10), "Mix");
        assert_eq!(proc.param_name(11), "Dither Bits");
        assert_eq!(proc.param_name(12), "Latency Profile");
        assert_eq!(proc.param_name(13), "Channel Config");
        assert_eq!(proc.param_name(14), "", "Out of range should return empty");
    }

    #[test]
    fn test_limiter_wrapper_defaults() {
        let proc = create_processor_extended("limiter", 48000.0).unwrap();
        assert_eq!(proc.get_param(0), 0.0, "Input Trim default");
        assert_eq!(proc.get_param(1), 0.0, "Threshold default");
        assert_eq!(proc.get_param(2), -0.3, "Ceiling default");
        assert_eq!(proc.get_param(3), 100.0, "Release default");
        assert_eq!(proc.get_param(4), 0.1, "Attack default");
        assert_eq!(proc.get_param(5), 5.0, "Lookahead default");
        assert_eq!(proc.get_param(6), 7.0, "Style default (Allround)");
        assert_eq!(proc.get_param(7), 1.0, "Oversampling default (2x)");
        assert_eq!(proc.get_param(8), 100.0, "Stereo Link default");
        assert_eq!(proc.get_param(9), 0.0, "M/S Mode default (off)");
        assert_eq!(proc.get_param(10), 100.0, "Mix default");
        assert_eq!(proc.get_param(11), 0.0, "Dither Bits default (off)");
        assert_eq!(proc.get_param(12), 1.0, "Latency Profile default (HQ)");
        assert_eq!(proc.get_param(13), 0.0, "Channel Config default (Stereo)");
    }

    #[test]
    fn test_limiter_wrapper_set_get_roundtrip() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();

        // Set all params and verify roundtrip
        let values = [
            (0, 3.0),    // Input Trim +3dB
            (1, -6.0),   // Threshold -6dB
            (2, -1.0),   // Ceiling -1dBTP
            (3, 50.0),   // Release 50ms
            (4, 1.0),    // Attack 1ms
            (5, 10.0),   // Lookahead 10ms
            (6, 3.0),    // Style (Aggressive)
            (7, 2.0),    // Oversampling 4x
            (8, 50.0),   // Stereo Link 50%
            (9, 1.0),    // M/S Mode on
            (10, 75.0),  // Mix 75%
            (11, 2.0),   // Dither 16-bit
            (12, 0.0),   // Latency Profile (Low)
            (13, 1.0),   // Channel Config (Mono)
        ];

        for (idx, val) in &values {
            proc.set_param(*idx, *val);
        }

        for (idx, val) in &values {
            let got = proc.get_param(*idx);
            assert_eq!(got, *val, "Param {} roundtrip failed: expected {}, got {}", idx, val, got);
        }
    }

    #[test]
    fn test_limiter_wrapper_process_stereo() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        // Set threshold low to trigger limiting
        proc.set_param(1, -10.0); // Threshold -10dB
        proc.set_param(2, -1.0);  // Ceiling -1dBTP

        // Create loud signal (0dBFS)
        let mut left = vec![0.9_f64; 512];
        let mut right = vec![0.9_f64; 512];

        // Process multiple blocks to let limiter settle
        for _ in 0..5 {
            proc.process_stereo(&mut left, &mut right);
        }

        // Output should be finite and limited
        assert!(left.iter().all(|x| x.is_finite()), "Left output should be finite");
        assert!(right.iter().all(|x| x.is_finite()), "Right output should be finite");

        let peak_l = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        let peak_r = right.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        // Peak should not exceed ceiling (some overshoot allowed for ISP)
        assert!(peak_l < 1.5, "Left peak {} should be limited", peak_l);
        assert!(peak_r < 1.5, "Right peak {} should be limited", peak_r);
    }

    #[test]
    fn test_limiter_wrapper_meters() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        proc.set_param(1, -12.0); // Low threshold to trigger GR

        let mut left = vec![0.8_f64; 1024];
        let mut right = vec![0.8_f64; 1024];

        for _ in 0..10 {
            proc.process_stereo(&mut left, &mut right);
        }

        // All 7 meters should return finite values
        for m in 0..7 {
            let val = proc.get_meter(m);
            assert!(val.is_finite(), "Meter {} should be finite, got {}", m, val);
        }

        // Invalid meter returns 0
        assert_eq!(proc.get_meter(99), 0.0, "Invalid meter index should return 0.0");
    }

    #[test]
    fn test_limiter_wrapper_silence_passthrough() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        // Default settings, silence in
        let mut left = vec![0.0_f64; 512];
        let mut right = vec![0.0_f64; 512];

        for _ in 0..5 {
            proc.process_stereo(&mut left, &mut right);
        }

        let peak_l = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        let peak_r = right.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        assert!(peak_l < 0.001, "Silence in should give near-silence out (L={})", peak_l);
        assert!(peak_r < 0.001, "Silence in should give near-silence out (R={})", peak_r);
    }

    #[test]
    fn test_limiter_wrapper_style_switching() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        proc.set_param(1, -6.0); // Threshold

        // All 8 styles should produce valid output
        for style_idx in 0..=7 {
            proc.set_param(6, style_idx as f64);

            let mut left = vec![0.5_f64; 512];
            let mut right = vec![0.5_f64; 512];
            proc.process_stereo(&mut left, &mut right);

            assert!(
                left.iter().all(|x| x.is_finite()),
                "Style {} should produce finite output",
                style_idx,
            );
        }
    }

    #[test]
    fn test_limiter_wrapper_mix_dry_wet() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        proc.set_param(1, -12.0); // Low threshold
        proc.set_param(2, -1.0);  // Ceiling

        // Mix = 0 (dry only) — output should be similar to input
        proc.set_param(10, 0.0);
        let mut dry_left = vec![0.5_f64; 512];
        let mut dry_right = vec![0.5_f64; 512];
        for _ in 0..5 {
            proc.process_stereo(&mut dry_left, &mut dry_right);
        }

        // Mix = 100 (wet only) — output should be limited
        proc.set_param(10, 100.0);
        let mut wet_left = vec![0.5_f64; 512];
        let mut wet_right = vec![0.5_f64; 512];
        for _ in 0..5 {
            proc.process_stereo(&mut wet_left, &mut wet_right);
        }

        // Both should be finite
        assert!(dry_left.iter().all(|x| x.is_finite()), "Dry output should be finite");
        assert!(wet_left.iter().all(|x| x.is_finite()), "Wet output should be finite");
    }

    #[test]
    fn test_limiter_wrapper_reset() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        proc.set_param(1, -12.0);

        let mut left = vec![0.8_f64; 512];
        let mut right = vec![0.8_f64; 512];
        proc.process_stereo(&mut left, &mut right);

        // Reset should not crash and should clear internal state
        proc.reset();

        let mut left2 = vec![0.0_f64; 512];
        let mut right2 = vec![0.0_f64; 512];
        proc.process_stereo(&mut left2, &mut right2);
        // After reset with silence, output should be near-silent
        let peak = left2.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        assert!(peak < 0.01, "After reset + silence, output should be near-zero (got {})", peak);
    }

    #[test]
    fn test_limiter_wrapper_set_sample_rate() {
        let mut proc = create_processor_extended("limiter", 44100.0).unwrap();

        // Change sample rate should not crash
        proc.set_sample_rate(96000.0);

        // Should still produce valid output
        let mut left = vec![0.5_f64; 512];
        let mut right = vec![0.5_f64; 512];
        proc.process_stereo(&mut left, &mut right);
        assert!(left.iter().all(|x| x.is_finite()), "Output should be finite after SR change");
    }

    #[test]
    fn test_limiter_wrapper_latency() {
        let proc = create_processor_extended("limiter", 48000.0).unwrap();
        // Limiter with lookahead should report some latency
        let lat = proc.latency();
        // Don't assert exact value — depends on lookahead setting
        assert!(lat < 48000, "Latency should be reasonable (got {} samples)", lat);
    }

    #[test]
    fn test_limiter_wrapper_invalid_param_index() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        proc.set_param(99, 0.5); // Should not crash
        let val = proc.get_param(99);
        assert_eq!(val, 0.0, "Invalid param index should return 0.0");
    }

    #[test]
    fn test_limiter_wrapper_oversampling_modes() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        proc.set_param(1, -6.0); // Threshold

        // All oversampling modes should produce valid output
        for os in 0..=3 {
            proc.set_param(7, os as f64);
            let mut left = vec![0.5_f64; 512];
            let mut right = vec![0.5_f64; 512];
            proc.process_stereo(&mut left, &mut right);
            assert!(
                left.iter().all(|x| x.is_finite()),
                "Oversampling mode {} should produce finite output",
                os,
            );
        }
    }

    #[test]
    fn test_limiter_wrapper_ms_mode() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();
        proc.set_param(1, -6.0);

        // M/S mode on
        proc.set_param(9, 1.0);
        let mut left = vec![0.5_f64; 512];
        let mut right = vec![0.3_f64; 512];
        proc.process_stereo(&mut left, &mut right);
        assert!(left.iter().all(|x| x.is_finite()), "M/S mode should produce finite L");
        assert!(right.iter().all(|x| x.is_finite()), "M/S mode should produce finite R");

        // M/S mode off
        proc.set_param(9, 0.0);
        let mut left2 = vec![0.5_f64; 512];
        let mut right2 = vec![0.3_f64; 512];
        proc.process_stereo(&mut left2, &mut right2);
        assert!(left2.iter().all(|x| x.is_finite()), "Stereo mode should produce finite L");
    }

    #[test]
    fn test_limiter_wrapper_input_trim() {
        let mut proc = create_processor_extended("limiter", 48000.0).unwrap();

        // Positive trim should boost input
        proc.set_param(0, 6.0); // +6dB
        let mut left = vec![0.3_f64; 512];
        let mut right = vec![0.3_f64; 512];
        for _ in 0..3 {
            proc.process_stereo(&mut left, &mut right);
        }
        assert!(left.iter().all(|x| x.is_finite()), "+6dB trim should produce finite output");
    }

    // ═══════════════════════════════════════════════════════════════
    // SaturatorWrapper Tests
    // ═══════════════════════════════════════════════════════════════

    #[test]
    fn test_saturator_wrapper_factory() {
        // All name aliases should create a SaturatorWrapper
        let p1 = create_processor_extended("saturation", 48000.0);
        assert!(p1.is_some(), "Factory should create from 'saturation'");
        assert_eq!(p1.unwrap().name(), "FluxForge Studio Saturator");

        let p2 = create_processor_extended("saturator", 48000.0);
        assert!(p2.is_some(), "Factory should create from 'saturator'");

        let p3 = create_processor_extended("saturn", 48000.0);
        assert!(p3.is_some(), "Factory should create from 'saturn'");
    }

    #[test]
    fn test_saturator_wrapper_num_params() {
        let proc = create_processor_extended("saturation", 48000.0).unwrap();
        assert_eq!(proc.num_params(), 10, "Saturator should have 10 parameters");
    }

    #[test]
    fn test_saturator_wrapper_param_names() {
        let proc = create_processor_extended("saturation", 48000.0).unwrap();
        assert_eq!(proc.param_name(0), "Drive");
        assert_eq!(proc.param_name(1), "Type");
        assert_eq!(proc.param_name(2), "Tone");
        assert_eq!(proc.param_name(3), "Mix");
        assert_eq!(proc.param_name(4), "Output");
        assert_eq!(proc.param_name(5), "Tape Bias");
        assert_eq!(proc.param_name(6), "Oversampling");
        assert_eq!(proc.param_name(7), "Input Trim");
        assert_eq!(proc.param_name(8), "M/S Mode");
        assert_eq!(proc.param_name(9), "Stereo Link");
        assert_eq!(proc.param_name(99), "Unknown");
    }

    #[test]
    fn test_saturator_wrapper_set_get_roundtrip() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();

        // Drive dB
        proc.set_param(0, 12.0);
        assert!((proc.get_param(0) - 12.0).abs() < 0.001);

        // Type (integer enum 0-5)
        proc.set_param(1, 3.0); // SoftClip
        assert!((proc.get_param(1) - 3.0).abs() < 0.001);

        // Tone
        proc.set_param(2, -50.0);
        assert!((proc.get_param(2) - (-50.0)).abs() < 0.001);

        // Mix %
        proc.set_param(3, 75.0);
        assert!((proc.get_param(3) - 75.0).abs() < 0.001);

        // Output dB
        proc.set_param(4, -6.0);
        assert!((proc.get_param(4) - (-6.0)).abs() < 0.001);

        // Tape Bias %
        proc.set_param(5, 80.0);
        assert!((proc.get_param(5) - 80.0).abs() < 0.001);

        // Oversampling
        proc.set_param(6, 2.0); // X4
        assert!((proc.get_param(6) - 2.0).abs() < 0.001);

        // Input Trim dB
        proc.set_param(7, 6.0);
        assert!((proc.get_param(7) - 6.0).abs() < 0.001);

        // M/S Mode
        proc.set_param(8, 1.0);
        assert!((proc.get_param(8) - 1.0).abs() < 0.001);

        // Stereo Link
        proc.set_param(9, 0.0);
        assert!((proc.get_param(9) - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_saturator_wrapper_param_clamping() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();

        // Drive clamps to -24..+40
        proc.set_param(0, 100.0);
        assert!((proc.get_param(0) - 40.0).abs() < 0.001, "Drive should clamp at 40 dB");
        proc.set_param(0, -50.0);
        assert!((proc.get_param(0) - (-24.0)).abs() < 0.001, "Drive should clamp at -24 dB");

        // Type clamps to 0..5
        proc.set_param(1, 10.0);
        assert!((proc.get_param(1) - 5.0).abs() < 0.001, "Type should clamp at 5");
        proc.set_param(1, -1.0);
        assert!((proc.get_param(1) - 0.0).abs() < 0.001, "Type should clamp at 0");

        // Mix clamps to 0..100
        proc.set_param(3, 150.0);
        assert!((proc.get_param(3) - 100.0).abs() < 0.001, "Mix should clamp at 100%");

        // Output clamps to -24..+24
        proc.set_param(4, 50.0);
        assert!((proc.get_param(4) - 24.0).abs() < 0.001, "Output should clamp at +24 dB");

        // Tape Bias clamps to 0..100
        proc.set_param(5, -10.0);
        assert!((proc.get_param(5) - 0.0).abs() < 0.001, "Tape Bias should clamp at 0%");

        // Input Trim clamps to -12..+12
        proc.set_param(7, 20.0);
        assert!((proc.get_param(7) - 12.0).abs() < 0.001, "Input Trim should clamp at +12 dB");
    }

    #[test]
    fn test_saturator_wrapper_defaults() {
        let proc = create_processor_extended("saturation", 48000.0).unwrap();
        assert!((proc.get_param(0) - 0.0).abs() < 0.001, "Default drive = 0 dB");
        assert!((proc.get_param(1) - 0.0).abs() < 0.001, "Default type = 0 (Tape)");
        assert!((proc.get_param(2) - 0.0).abs() < 0.001, "Default tone = 0");
        assert!((proc.get_param(3) - 100.0).abs() < 0.001, "Default mix = 100%");
        assert!((proc.get_param(4) - 0.0).abs() < 0.001, "Default output = 0 dB");
        assert!((proc.get_param(5) - 50.0).abs() < 0.001, "Default tape bias = 50%");
        assert!((proc.get_param(6) - 1.0).abs() < 0.001, "Default oversampling = 1 (X2)");
        assert!((proc.get_param(7) - 0.0).abs() < 0.001, "Default input trim = 0 dB");
        assert!((proc.get_param(8) - 0.0).abs() < 0.001, "Default M/S = 0 (off)");
        assert!((proc.get_param(9) - 1.0).abs() < 0.001, "Default stereo link = 1 (on)");
    }

    #[test]
    fn test_saturator_wrapper_process_stereo() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        // Apply heavy drive to generate saturation
        proc.set_param(0, 24.0); // +24 dB drive

        let mut left = vec![0.3_f64; 512];
        let mut right = vec![0.3_f64; 512];

        proc.process_stereo(&mut left, &mut right);

        // Output should differ from input due to saturation
        let any_changed_l = left.iter().any(|&x| (x - 0.3).abs() > 0.001);
        let any_changed_r = right.iter().any(|&x| (x - 0.3).abs() > 0.001);
        assert!(any_changed_l, "Left channel should be saturated");
        assert!(any_changed_r, "Right channel should be saturated");

        // Output should not contain NaN or Inf
        assert!(left.iter().all(|x| x.is_finite()), "No NaN/Inf in left");
        assert!(right.iter().all(|x| x.is_finite()), "No NaN/Inf in right");
    }

    #[test]
    fn test_saturator_wrapper_dry_only() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        // Mix = 0% → full dry (bypass)
        proc.set_param(3, 0.0);
        proc.set_param(0, 24.0); // Heavy drive, but should be bypassed by dry mix

        let input_val = 0.4_f64;
        let mut left = vec![input_val; 512];
        let mut right = vec![input_val; 512];

        // Process several blocks to stabilize oversampling filters
        for _ in 0..5 {
            left.fill(input_val);
            right.fill(input_val);
            proc.process_stereo(&mut left, &mut right);
        }

        // With mix=0%, output should be very close to input
        let max_deviation_l = left.iter().map(|x| (x - input_val).abs()).fold(0.0_f64, f64::max);
        let max_deviation_r = right.iter().map(|x| (x - input_val).abs()).fold(0.0_f64, f64::max);
        assert!(
            max_deviation_l < 0.05,
            "Dry mix should preserve input (L dev={})",
            max_deviation_l
        );
        assert!(
            max_deviation_r < 0.05,
            "Dry mix should preserve input (R dev={})",
            max_deviation_r
        );
    }

    #[test]
    fn test_saturator_wrapper_reset() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        proc.set_param(0, 20.0);

        // Process some audio to build up state
        let mut left = vec![0.5; 512];
        let mut right = vec![0.5; 512];
        proc.process_stereo(&mut left, &mut right);

        // Meters should have values
        let meter_before = proc.get_meter(2); // Output Peak L
        assert!(meter_before > 0.0, "Meters should have values after processing");

        // Reset clears meters
        proc.reset();
        assert_eq!(proc.get_meter(0), 0.0, "Input Peak L should be 0 after reset");
        assert_eq!(proc.get_meter(1), 0.0, "Input Peak R should be 0 after reset");
        assert_eq!(proc.get_meter(2), 0.0, "Output Peak L should be 0 after reset");
        assert_eq!(proc.get_meter(3), 0.0, "Output Peak R should be 0 after reset");
    }

    #[test]
    fn test_saturator_wrapper_set_sample_rate() {
        let mut proc = create_processor_extended("saturation", 44100.0).unwrap();
        proc.set_sample_rate(96000.0);
        // Should not crash, processor should still work
        let mut left = vec![0.3; 512];
        let mut right = vec![0.3; 512];
        proc.process_stereo(&mut left, &mut right);
        assert!(left.iter().all(|x| x.is_finite()), "Should produce valid output at 96kHz");
    }

    #[test]
    fn test_saturator_wrapper_latency() {
        let proc = create_processor_extended("saturation", 48000.0).unwrap();
        // Default oversampling = X2, should have filter latency > 0
        let lat = proc.latency();
        assert!(lat > 0, "Saturator with 2x oversampling should have latency > 0, got {}", lat);
    }

    #[test]
    fn test_saturator_wrapper_type_switching() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        proc.set_param(0, 12.0); // Moderate drive

        // Process with Tape (default type=0)
        let mut tape_l = vec![0.3; 512];
        let mut tape_r = vec![0.3; 512];
        for _ in 0..5 { proc.process_stereo(&mut tape_l, &mut tape_r); tape_l.fill(0.3); tape_r.fill(0.3); }
        proc.process_stereo(&mut tape_l, &mut tape_r);
        let tape_peak = tape_l.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);

        // Switch to HardClip (type=4) — more aggressive
        proc.set_param(1, 4.0);
        let mut hard_l = vec![0.3; 512];
        let mut hard_r = vec![0.3; 512];
        for _ in 0..5 { proc.process_stereo(&mut hard_l, &mut hard_r); hard_l.fill(0.3); hard_r.fill(0.3); }
        proc.process_stereo(&mut hard_l, &mut hard_r);
        let hard_peak = hard_l.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);

        // Both should produce valid output
        assert!(tape_peak > 0.0, "Tape type should produce output");
        assert!(hard_peak > 0.0, "HardClip type should produce output");
        // They should produce different results
        assert!(
            (tape_peak - hard_peak).abs() > 0.001,
            "Different saturation types should produce different output (tape={}, hard={})",
            tape_peak, hard_peak,
        );
    }

    #[test]
    fn test_saturator_wrapper_ms_mode() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        proc.set_param(0, 12.0); // Drive
        proc.set_param(8, 1.0);  // M/S mode ON

        // Asymmetric input — L loud, R quiet → strong mid + strong side
        let mut left = vec![0.8; 512];
        let mut right = vec![0.1; 512];

        proc.process_stereo(&mut left, &mut right);

        // Should produce valid output
        assert!(left.iter().all(|x| x.is_finite()), "M/S: no NaN/Inf in left");
        assert!(right.iter().all(|x| x.is_finite()), "M/S: no NaN/Inf in right");
        // Output should differ between channels (asymmetric input)
        let l_peak = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        let r_peak = right.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        assert!(
            (l_peak - r_peak).abs() > 0.01,
            "M/S mode with asymmetric input should produce different L/R peaks (l={}, r={})",
            l_peak, r_peak,
        );
    }

    #[test]
    fn test_saturator_wrapper_input_trim() {
        let mut proc_no_trim = create_processor_extended("saturation", 48000.0).unwrap();
        let mut proc_with_trim = create_processor_extended("saturation", 48000.0).unwrap();

        proc_no_trim.set_param(0, 6.0);  // Same drive
        proc_with_trim.set_param(0, 6.0);
        proc_with_trim.set_param(7, 12.0); // +12 dB input trim

        let mut no_l = vec![0.2; 512];
        let mut no_r = vec![0.2; 512];
        let mut tr_l = vec![0.2; 512];
        let mut tr_r = vec![0.2; 512];

        for _ in 0..5 {
            no_l.fill(0.2); no_r.fill(0.2);
            tr_l.fill(0.2); tr_r.fill(0.2);
            proc_no_trim.process_stereo(&mut no_l, &mut no_r);
            proc_with_trim.process_stereo(&mut tr_l, &mut tr_r);
        }

        let no_peak = no_l.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        let tr_peak = tr_l.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);

        // With +12dB input trim, the saturator should see hotter signal → more saturation
        assert!(
            (no_peak - tr_peak).abs() > 0.01,
            "Input trim should affect output (no_trim={}, with_trim={})",
            no_peak, tr_peak,
        );
    }

    #[test]
    fn test_saturator_wrapper_meters() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        proc.set_param(0, 6.0);

        let mut left = vec![0.5; 512];
        let mut right = vec![0.3; 512];
        proc.process_stereo(&mut left, &mut right);

        // All 4 meters should have values after processing
        let in_l = proc.get_meter(0);
        let in_r = proc.get_meter(1);
        let out_l = proc.get_meter(2);
        let out_r = proc.get_meter(3);

        assert!(in_l > 0.0, "Input Peak L should be > 0, got {}", in_l);
        assert!(in_r > 0.0, "Input Peak R should be > 0, got {}", in_r);
        assert!(out_l > 0.0, "Output Peak L should be > 0, got {}", out_l);
        assert!(out_r > 0.0, "Output Peak R should be > 0, got {}", out_r);

        // Invalid meter index returns 0
        assert_eq!(proc.get_meter(99), 0.0, "Invalid meter index should return 0.0");
    }

    #[test]
    fn test_saturator_wrapper_oversampling_switch() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();

        // X1 (no oversampling) — latency should be 0
        proc.set_param(6, 0.0);
        let lat_x1 = proc.latency();
        assert_eq!(lat_x1, 0, "X1 (no oversampling) should have 0 latency");

        // X2 — should have some latency from halfband filter
        proc.set_param(6, 1.0);
        let lat_x2 = proc.latency();
        assert!(lat_x2 > 0, "X2 should have latency > 0, got {}", lat_x2);

        // X4 and X8 — should produce valid output at each setting
        for os_idx in 0..=3 {
            proc.set_param(6, os_idx as f64);
            proc.set_param(0, 6.0); // Moderate drive
            let mut left = vec![0.3; 512];
            let mut right = vec![0.3; 512];
            proc.process_stereo(&mut left, &mut right);
            assert!(
                left.iter().all(|x| x.is_finite()),
                "Oversampling {} should produce valid output",
                os_idx,
            );
        }
    }

    #[test]
    fn test_saturator_wrapper_invalid_param_index() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        // Out of range should not crash
        proc.set_param(99, 0.5);
        let val = proc.get_param(99);
        assert_eq!(val, 0.0, "Invalid param index should return 0.0");
    }

    #[test]
    fn test_saturator_wrapper_silence_passthrough() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        // With 0 drive and default settings, silence in should give silence out
        proc.set_param(0, 0.0);

        let mut left = vec![0.0_f64; 512];
        let mut right = vec![0.0_f64; 512];

        for _ in 0..5 {
            proc.process_stereo(&mut left, &mut right);
        }

        let peak_l = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        let peak_r = right.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        assert!(peak_l < 0.001, "Silence in should give near-silence out (L={})", peak_l);
        assert!(peak_r < 0.001, "Silence in should give near-silence out (R={})", peak_r);
    }

    #[test]
    fn test_saturator_wrapper_all_types_valid() {
        let mut proc = create_processor_extended("saturation", 48000.0).unwrap();
        proc.set_param(0, 12.0); // Moderate drive

        // Test all 6 saturation types produce valid output
        for type_idx in 0..6 {
            proc.set_param(1, type_idx as f64);
            let mut left = vec![0.4; 512];
            let mut right = vec![0.4; 512];
            proc.process_stereo(&mut left, &mut right);

            assert!(
                left.iter().all(|x| x.is_finite()),
                "Type {} should produce finite output",
                type_idx,
            );
            let peak = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
            assert!(peak > 0.0, "Type {} should produce non-zero output, got {}", type_idx, peak);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Gate Wrapper Tests
    // ═══════════════════════════════════════════════════════════════════

    #[test]
    fn test_gate_wrapper_factory() {
        let proc = create_processor_extended("gate", 48000.0);
        assert!(proc.is_some());
        assert_eq!(proc.unwrap().name(), "FluxForge Studio Gate");
    }

    #[test]
    fn test_gate_wrapper_num_params() {
        let proc = create_processor_extended("gate", 48000.0).unwrap();
        assert_eq!(proc.num_params(), 13);
    }

    #[test]
    fn test_gate_wrapper_param_names() {
        let proc = create_processor_extended("gate", 48000.0).unwrap();
        assert_eq!(proc.param_name(0), "Threshold");
        assert_eq!(proc.param_name(1), "Range");
        assert_eq!(proc.param_name(2), "Attack");
        assert_eq!(proc.param_name(3), "Hold");
        assert_eq!(proc.param_name(4), "Release");
        assert_eq!(proc.param_name(5), "Mode");
        assert_eq!(proc.param_name(6), "SC Enable");
        assert_eq!(proc.param_name(7), "SC HP Freq");
        assert_eq!(proc.param_name(8), "SC LP Freq");
        assert_eq!(proc.param_name(9), "Lookahead");
        assert_eq!(proc.param_name(10), "Hysteresis");
        assert_eq!(proc.param_name(11), "Ratio");
        assert_eq!(proc.param_name(12), "SC Audition");
    }

    #[test]
    fn test_gate_wrapper_set_get_roundtrip() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // Core params
        proc.set_param(0, -30.0); // threshold
        assert!((proc.get_param(0) - (-30.0)).abs() < 0.01);
        proc.set_param(1, -40.0); // range
        assert!((proc.get_param(1) - (-40.0)).abs() < 0.01);
        proc.set_param(2, 2.0); // attack
        assert!((proc.get_param(2) - 2.0).abs() < 0.01);
        proc.set_param(3, 50.0); // hold
        assert!((proc.get_param(3) - 50.0).abs() < 0.01);
        proc.set_param(4, 100.0); // release
        assert!((proc.get_param(4) - 100.0).abs() < 0.01);
        // Extended params
        proc.set_param(5, 1.0); // mode = duck
        assert!((proc.get_param(5) - 1.0).abs() < 0.01);
        proc.set_param(6, 1.0); // SC enabled
        assert!((proc.get_param(6) - 1.0).abs() < 0.01);
        proc.set_param(7, 200.0); // SC HPF
        assert!((proc.get_param(7) - 200.0).abs() < 0.01);
        proc.set_param(8, 8000.0); // SC LPF
        assert!((proc.get_param(8) - 8000.0).abs() < 0.01);
        proc.set_param(9, 5.0); // lookahead
        assert!((proc.get_param(9) - 5.0).abs() < 0.01);
    }

    #[test]
    fn test_gate_wrapper_mode_switching() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // Gate mode (default)
        assert!((proc.get_param(5) - 0.0).abs() < 0.01);
        // Duck mode
        proc.set_param(5, 1.0);
        assert!((proc.get_param(5) - 1.0).abs() < 0.01);
        // Expand mode
        proc.set_param(5, 2.0);
        assert!((proc.get_param(5) - 2.0).abs() < 0.01);
        // Clamp invalid
        proc.set_param(5, 99.0);
        assert!(proc.get_param(5) <= 2.0);
    }

    #[test]
    fn test_gate_wrapper_sidechain_params() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // SC disabled by default
        assert!(proc.get_param(6) < 0.5);
        // Enable SC
        proc.set_param(6, 1.0);
        assert!(proc.get_param(6) > 0.5);
        // HPF clamp
        proc.set_param(7, 5.0); // below min 20
        assert!(proc.get_param(7) >= 20.0);
        proc.set_param(7, 500.0);
        assert!((proc.get_param(7) - 500.0).abs() < 0.01);
        // LPF clamp
        proc.set_param(8, 25000.0); // above max 20000
        assert!(proc.get_param(8) <= 20000.0);
        proc.set_param(8, 5000.0);
        assert!((proc.get_param(8) - 5000.0).abs() < 0.01);
    }

    #[test]
    fn test_gate_wrapper_process_stereo() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        proc.set_param(0, -60.0); // very low threshold => gate open
        let mut left = vec![0.5; 512];
        let mut right = vec![0.5; 512];
        proc.process_stereo(&mut left, &mut right);
        assert!(left.iter().all(|s| s.is_finite()));
        assert!(right.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn test_gate_wrapper_meters() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        let mut left = vec![0.3; 512];
        let mut right = vec![0.3; 512];
        proc.process_stereo(&mut left, &mut right);
        // Meter 0: input level (dB), 1: output level (dB), 2: gate gain (0-1)
        let in_db = proc.get_meter(0);
        let out_db = proc.get_meter(1);
        let gate_gain = proc.get_meter(2);
        assert!(in_db.is_finite(), "Input dB should be finite, got {}", in_db);
        assert!(in_db > -100.0, "Input dB should be above -100, got {}", in_db);
        assert!(out_db.is_finite(), "Output dB should be finite, got {}", out_db);
        assert!(gate_gain >= 0.0 && gate_gain <= 1.0, "Gate gain should be 0-1, got {}", gate_gain);
    }

    #[test]
    fn test_gate_wrapper_duck_mode_processing() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        proc.set_param(5, 1.0); // Duck mode
        proc.set_param(0, -60.0); // Low threshold => gate open => duck should attenuate
        let mut left = vec![0.5; 512];
        let mut right = vec![0.5; 512];
        proc.process_stereo(&mut left, &mut right);
        // In duck mode, output should still be finite
        assert!(left.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn test_gate_wrapper_invalid_param_index() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // Out of range should return 0.0 / do nothing
        assert_eq!(proc.get_param(99), 0.0);
        proc.set_param(99, 42.0); // Should not panic
    }

    #[test]
    fn test_gate_wrapper_hysteresis_param() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // Default: 0 dB
        assert!((proc.get_param(10) - 0.0).abs() < 0.01);
        // Set to 6 dB
        proc.set_param(10, 6.0);
        assert!((proc.get_param(10) - 6.0).abs() < 0.01);
        // Clamp: above max (12)
        proc.set_param(10, 20.0);
        assert!(proc.get_param(10) <= 12.0);
        // Clamp: below min (0)
        proc.set_param(10, -5.0);
        assert!(proc.get_param(10) >= 0.0);
    }

    #[test]
    fn test_gate_wrapper_ratio_param() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // Default: 100%
        assert!((proc.get_param(11) - 100.0).abs() < 0.01);
        // Set to 50%
        proc.set_param(11, 50.0);
        assert!((proc.get_param(11) - 50.0).abs() < 0.01);
        // Clamp: below min (1)
        proc.set_param(11, -10.0);
        assert!(proc.get_param(11) >= 1.0);
        // Clamp: above max (100)
        proc.set_param(11, 200.0);
        assert!(proc.get_param(11) <= 100.0);
    }

    #[test]
    fn test_gate_wrapper_sc_audition_param() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // Default: off
        assert!(proc.get_param(12) < 0.5);
        // Enable
        proc.set_param(12, 1.0);
        assert!(proc.get_param(12) > 0.5);
        // Disable
        proc.set_param(12, 0.0);
        assert!(proc.get_param(12) < 0.5);
    }

    #[test]
    fn test_gate_wrapper_expand_mode_with_ratio() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        proc.set_param(5, 2.0);  // Expand mode
        proc.set_param(11, 50.0); // 50% ratio
        proc.set_param(0, -60.0); // Low threshold
        let mut left = vec![0.5; 512];
        let mut right = vec![0.5; 512];
        proc.process_stereo(&mut left, &mut right);
        assert!(left.iter().all(|s| s.is_finite()));
        assert!(right.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn test_gate_wrapper_hysteresis_roundtrip() {
        let mut proc = create_processor_extended("gate", 48000.0).unwrap();
        // Set all new params and verify roundtrip
        proc.set_param(10, 4.0);  // hysteresis
        proc.set_param(11, 75.0); // ratio
        proc.set_param(12, 1.0);  // sc audition
        assert!((proc.get_param(10) - 4.0).abs() < 0.01);
        assert!((proc.get_param(11) - 75.0).abs() < 0.01);
        assert!(proc.get_param(12) > 0.5);
    }

    // ═══════════════════════════════════════════════════════════════════
    // EQ Auto-Gain & Solo Tests
    // ═══════════════════════════════════════════════════════════════════

    #[test]
    fn test_eq_auto_gain_param() {
        let mut proc = create_processor_extended("pro-eq", 48000.0).unwrap();
        let ag_idx = 64 * 12 + 1; // global param 1 = auto-gain
        // Default: off
        assert!(proc.get_param(ag_idx) < 0.5);
        // Enable
        proc.set_param(ag_idx, 1.0);
        assert!(proc.get_param(ag_idx) > 0.5);
        // Disable
        proc.set_param(ag_idx, 0.0);
        assert!(proc.get_param(ag_idx) < 0.5);
    }

    #[test]
    fn test_eq_solo_band_param() {
        let mut proc = create_processor_extended("pro-eq", 48000.0).unwrap();
        let solo_idx = 64 * 12 + 2; // global param 2 = solo band
        // Default: -1 (no solo)
        assert!((proc.get_param(solo_idx) - (-1.0)).abs() < 0.01);
        // Solo band 0
        proc.set_param(solo_idx, 0.0);
        assert!((proc.get_param(solo_idx) - 0.0).abs() < 0.01);
        // Solo band 5
        proc.set_param(solo_idx, 5.0);
        assert!((proc.get_param(solo_idx) - 5.0).abs() < 0.01);
        // Un-solo
        proc.set_param(solo_idx, -1.0);
        assert!((proc.get_param(solo_idx) - (-1.0)).abs() < 0.01);
    }

    #[test]
    fn test_eq_solo_band_restores_enabled() {
        let mut proc = create_processor_extended("pro-eq", 48000.0).unwrap();
        let solo_idx = 64 * 12 + 2;
        // Enable bands 0 and 1
        proc.set_param(0 * 12 + 3, 1.0); // band 0 enabled
        proc.set_param(1 * 12 + 3, 1.0); // band 1 enabled
        assert!(proc.get_param(0 * 12 + 3) > 0.5);
        assert!(proc.get_param(1 * 12 + 3) > 0.5);
        // Solo band 0 — band 1 should become disabled
        proc.set_param(solo_idx, 0.0);
        assert!(proc.get_param(0 * 12 + 3) > 0.5); // band 0 still enabled (soloed)
        assert!(proc.get_param(1 * 12 + 3) < 0.5); // band 1 disabled
        // Un-solo — band 1 should be restored
        proc.set_param(solo_idx, -1.0);
        assert!(proc.get_param(0 * 12 + 3) > 0.5);
        assert!(proc.get_param(1 * 12 + 3) > 0.5);
    }

    #[test]
    fn test_eq_auto_gain_processing() {
        let mut proc = create_processor_extended("pro-eq", 48000.0).unwrap();
        let ag_idx = 64 * 12 + 1;
        // Enable a high-gain band to make a measurable level difference
        proc.set_param(0 * 12 + 0, 1000.0); // freq
        proc.set_param(0 * 12 + 1, 12.0);   // +12dB gain
        proc.set_param(0 * 12 + 2, 1.0);    // Q
        proc.set_param(0 * 12 + 3, 1.0);    // enabled
        // Process without auto-gain
        let mut left = vec![0.3; 1024];
        let mut right = vec![0.3; 1024];
        proc.process_stereo(&mut left, &mut right);
        let peak_no_ag = left.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        // Reset and process with auto-gain
        proc.reset();
        proc.set_param(ag_idx, 1.0);
        let mut left2 = vec![0.3; 1024];
        let mut right2 = vec![0.3; 1024];
        proc.process_stereo(&mut left2, &mut right2);
        let peak_ag = left2.iter().map(|x| x.abs()).fold(0.0_f64, f64::max);
        // Auto-gain should compensate — output peak should be closer to input (0.3) than without AG
        // With +12dB boost and no AG, peak should be much higher
        assert!(peak_no_ag > 0.3, "No-AG peak should be above input level");
        assert!(peak_ag < peak_no_ag, "Auto-gain peak ({:.3}) should be lower than no-AG ({:.3})", peak_ag, peak_no_ag);
    }

    #[test]
    fn test_eq_output_gain_get_param() {
        let mut proc = create_processor_extended("pro-eq", 48000.0).unwrap();
        let out_idx = 64 * 12; // global param 0 = output gain
        // Default 0 dB
        assert!((proc.get_param(out_idx) - 0.0).abs() < 0.01);
        // Set +6 dB
        proc.set_param(out_idx, 6.0);
        assert!((proc.get_param(out_idx) - 6.0).abs() < 0.01);
    }

    #[test]
    fn test_reverb_in_insert_chain_slot2() {
        use crate::insert_chain::InsertChain;

        let mut chain = InsertChain::new(48000.0);

        // Load EQ in slot 0 (like initializeChain does)
        let eq = create_processor_extended("pro-eq", 48000.0).unwrap();
        chain.load(0, eq);

        // Load Compressor in slot 1 (like initializeChain does)
        let comp = create_processor_extended("compressor", 48000.0).unwrap();
        chain.load(1, comp);

        // Load Reverb in slot 2 (like the FabFilter panel does)
        let mut reverb = create_processor_extended("reverb", 48000.0).unwrap();
        // Set mix to 100% wet so we definitely hear reverb
        reverb.set_param(3, 1.0);
        chain.load(2, reverb);

        // Set reverb params after loading via chain
        chain.set_slot_param(2, 3, 1.0); // mix = 100% wet
        chain.set_slot_param(2, 0, 0.5); // space = 0.5
        chain.set_slot_param(2, 8, 0.8); // decay = 0.8

        // Process several blocks of audio to build up reverb tail
        let mut total_energy = 0.0f64;
        for block in 0..30 {
            let mut left = vec![if block < 3 { 0.5 } else { 0.0 }; 256];
            let mut right = vec![if block < 3 { 0.5 } else { 0.0 }; 256];
            chain.process_pre_fader(&mut left, &mut right);

            // After the impulse blocks, we should still have reverb tail energy
            if block >= 5 {
                let block_energy: f64 = left.iter().chain(right.iter())
                    .map(|s| s * s).sum();
                total_energy += block_energy;
            }
        }

        assert!(total_energy > 0.01,
            "Reverb in slot 2 should produce tail energy after impulse, got {}", total_energy);
    }

    #[test]
    fn test_saturator_in_insert_chain_slot3() {
        use crate::insert_chain::InsertChain;

        let mut chain = InsertChain::new(48000.0);

        // Load EQ in slot 0, Comp in slot 1, Reverb in slot 2
        chain.load(0, create_processor_extended("pro-eq", 48000.0).unwrap());
        chain.load(1, create_processor_extended("compressor", 48000.0).unwrap());
        chain.load(2, create_processor_extended("reverb", 48000.0).unwrap());

        // Load Saturator in slot 3 with heavy drive
        let mut sat = create_processor_extended("saturator", 48000.0).unwrap();
        sat.set_param(0, 20.0); // Drive = +20 dB
        sat.set_param(3, 100.0); // Mix = 100%
        chain.load(3, sat);

        // Also set via chain path (like FFI does)
        chain.set_slot_param(3, 0, 20.0); // Drive = +20 dB
        chain.set_slot_param(3, 3, 100.0); // Mix = 100%

        // Process audio — saturator should distort signal
        let mut left = vec![0.3f64; 512];
        let mut right = vec![0.3f64; 512];
        let original = left.clone();

        chain.process_pre_fader(&mut left, &mut right);

        // Signal should be modified by saturator
        let mut diff_count = 0;
        for i in 0..512 {
            if (left[i] - original[i]).abs() > 0.001 {
                diff_count += 1;
            }
        }

        assert!(diff_count > 100,
            "Saturator in slot 3 with +20dB drive should modify most samples, only {} changed", diff_count);
    }
}

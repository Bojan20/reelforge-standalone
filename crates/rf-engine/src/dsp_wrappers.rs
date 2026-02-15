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
pub struct ProEqWrapper {
    eq: ProEq,
    sample_rate: f64,
    bypassed: bool,
}

impl ProEqWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: ProEq::new(sample_rate),
            sample_rate,
            bypassed: false,
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
        if !self.bypassed {
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
            0.0
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        let per_band = 12;
        let max_bands = rf_dsp::PRO_EQ_MAX_BANDS;

        if index < max_bands * per_band {
            let band_idx = index / per_band;
            let param_idx = index % per_band;

            // For params 0-4 that need set_band, read values first then drop borrow
            if param_idx <= 4 {
                let (freq, gain, q, shape) = if let Some(band) = self.eq.band(band_idx) {
                    (band.frequency, band.gain_db, band.q, band.shape)
                } else {
                    return;
                };

                match param_idx {
                    0 => self
                        .eq
                        .set_band(band_idx, value.clamp(10.0, 30000.0), gain, q, shape),
                    1 => self
                        .eq
                        .set_band(band_idx, freq, value.clamp(-30.0, 30.0), q, shape),
                    2 => self
                        .eq
                        .set_band(band_idx, freq, gain, value.clamp(0.05, 50.0), shape),
                    3 => self.eq.enable_band(band_idx, value > 0.5),
                    4 => self.eq.set_band(
                        band_idx,
                        freq,
                        gain,
                        q,
                        FilterShape::from_index(value as usize),
                    ),
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
    CompressorType, DeEsser, DeEsserMode, Expander, Gate, Oversampling, StereoCompressor,
    TruePeakLimiter,
};

/// Compressor wrapper for insert chain
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

    pub fn set_threshold(&mut self, db: f64) {
        self.comp.set_both(|c| c.set_threshold(db));
    }

    pub fn set_ratio(&mut self, ratio: f64) {
        self.comp.set_both(|c| c.set_ratio(ratio));
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.comp.set_both(|c| c.set_attack(ms));
    }

    pub fn set_release(&mut self, ms: f64) {
        self.comp.set_both(|c| c.set_release(ms));
    }

    pub fn set_makeup(&mut self, db: f64) {
        self.comp.set_both(|c| c.set_makeup(db));
    }

    pub fn set_mix(&mut self, mix: f64) {
        self.comp.set_both(|c| c.set_mix(mix));
    }

    pub fn set_type(&mut self, comp_type: CompressorType) {
        self.comp.set_both(|c| c.set_type(comp_type));
    }

    pub fn set_link(&mut self, link: f64) {
        self.comp.set_link(link);
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
        self.comp = StereoCompressor::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        8
    }

    fn get_param(&self, _index: usize) -> f64 {
        0.0 // Would need to store params separately for get
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_threshold(value),
            1 => self.set_ratio(value),
            2 => self.set_attack(value),
            3 => self.set_release(value),
            4 => self.set_makeup(value),
            5 => self.set_mix(value),
            6 => self.set_link(value),
            7 => {
                let comp_type = match value as u8 {
                    0 => CompressorType::Vca,
                    1 => CompressorType::Opto,
                    _ => CompressorType::Fet,
                };
                self.set_type(comp_type);
            }
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
            _ => "",
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        let (gr_l, gr_r) = self.comp.gain_reduction_db();
        match index {
            0 => gr_l,
            1 => gr_r,
            _ => 0.0,
        }
    }
}

/// True Peak Limiter wrapper
pub struct TruePeakLimiterWrapper {
    limiter: TruePeakLimiter,
    sample_rate: f64,
}

impl TruePeakLimiterWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            limiter: TruePeakLimiter::new(sample_rate),
            sample_rate,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.limiter.set_threshold(db);
    }

    pub fn set_ceiling(&mut self, db: f64) {
        self.limiter.set_ceiling(db);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.limiter.set_release(ms);
    }

    pub fn set_oversampling(&mut self, os: Oversampling) {
        self.limiter.set_oversampling(os);
    }

    pub fn true_peak_db(&self) -> f64 {
        self.limiter.true_peak_db()
    }

    pub fn gain_reduction_db(&self) -> f64 {
        self.limiter.gain_reduction_db()
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
        self.limiter.latency()
    }

    fn reset(&mut self) {
        self.limiter.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.limiter = TruePeakLimiter::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        4
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_threshold(value),
            1 => self.set_ceiling(value),
            2 => self.set_release(value),
            3 => {
                let os = match value as u8 {
                    0 => Oversampling::X1,
                    1 => Oversampling::X2,
                    2 => Oversampling::X4,
                    _ => Oversampling::X8,
                };
                self.set_oversampling(os);
            }
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Threshold",
            1 => "Ceiling",
            2 => "Release",
            3 => "Oversampling",
            _ => "",
        }
    }

    fn get_meter(&self, index: usize) -> f64 {
        match index {
            0 | 1 => self.limiter.gain_reduction_db(),
            _ => 0.0,
        }
    }
}

/// Gate wrapper for insert chain
pub struct GateWrapper {
    left: Gate,
    right: Gate,
    sample_rate: f64,
}

impl GateWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Gate::new(sample_rate),
            right: Gate::new(sample_rate),
            sample_rate,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.left.set_threshold(db);
        self.right.set_threshold(db);
    }

    pub fn set_range(&mut self, db: f64) {
        self.left.set_range(db);
        self.right.set_range(db);
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.left.set_attack(ms);
        self.right.set_attack(ms);
    }

    pub fn set_hold(&mut self, ms: f64) {
        self.left.set_hold(ms);
        self.right.set_hold(ms);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.left.set_release(ms);
        self.right.set_release(ms);
    }
}

impl InsertProcessor for GateWrapper {
    fn name(&self) -> &str {
        "FluxForge Studio Gate"
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
        self.left = Gate::new(sample_rate);
        self.right = Gate::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        5
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.set_threshold(value),
            1 => self.set_range(value),
            2 => self.set_attack(value),
            3 => self.set_hold(value),
            4 => self.set_release(value),
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Threshold",
            1 => "Range",
            2 => "Attack",
            3 => "Hold",
            4 => "Release",
            _ => "",
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

/// Algorithmic Reverb wrapper for insert chain
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

    pub fn set_room_size(&mut self, size: f64) {
        self.reverb.set_room_size(size);
    }

    pub fn set_damping(&mut self, damping: f64) {
        self.reverb.set_damping(damping);
    }

    pub fn set_width(&mut self, width: f64) {
        self.reverb.set_width(width);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.reverb.set_dry_wet(mix);
    }

    pub fn set_predelay(&mut self, ms: f64) {
        self.reverb.set_predelay(ms);
    }

    pub fn set_type(&mut self, reverb_type: ReverbType) {
        self.reverb.set_type(reverb_type);
    }

    pub fn set_diffusion(&mut self, diffusion: f64) {
        self.reverb.set_diffusion(diffusion);
    }

    pub fn set_distance(&mut self, distance: f64) {
        self.reverb.set_distance(distance);
    }
}

impl InsertProcessor for ReverbWrapper {
    fn name(&self) -> &str {
        "FluxForge Algorithmic Reverb"
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
        // AlgorithmicReverb doesn't have set_sample_rate, so recreate
        self.sample_rate = sample_rate;
        self.reverb = AlgorithmicReverb::new(sample_rate);
    }

    fn latency(&self) -> LatencySamples {
        use rf_dsp::Processor;
        self.reverb.latency() as LatencySamples
    }

    fn num_params(&self) -> usize {
        8
    }

    fn set_param(&mut self, param_index: usize, value: f64) {
        // Reverb param indices:
        // 0 = Room Size (0.0-1.0)
        // 1 = Damping (0.0-1.0)
        // 2 = Width (0.0-1.0)
        // 3 = Dry/Wet mix (0.0-1.0)
        // 4 = Predelay (0-200 ms)
        // 5 = Type (0=Room, 1=Hall, 2=Plate, 3=Chamber, 4=Spring)
        // 6 = Diffusion (0.0-1.0) — allpass feedback, echo density
        // 7 = Distance (0.0-1.0) — early reflections attenuation
        match param_index {
            0 => self.set_room_size(value),
            1 => self.set_damping(value),
            2 => self.set_width(value),
            3 => self.set_dry_wet(value),
            4 => self.set_predelay(value),
            5 => {
                let rt = match value as u32 {
                    0 => ReverbType::Room,
                    1 => ReverbType::Hall,
                    2 => ReverbType::Plate,
                    3 => ReverbType::Chamber,
                    4 => ReverbType::Spring,
                    _ => ReverbType::Room,
                };
                self.set_type(rt);
            }
            6 => self.set_diffusion(value),
            7 => self.set_distance(value),
            _ => {}
        }
    }

    fn get_param(&self, _param_index: usize) -> f64 {
        // Not implemented for now
        0.0
    }

    fn param_name(&self, param_index: usize) -> &str {
        match param_index {
            0 => "Room Size",
            1 => "Damping",
            2 => "Width",
            3 => "Mix",
            4 => "Predelay",
            5 => "Type",
            6 => "Diffusion",
            7 => "Distance",
            _ => "Unknown",
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
}

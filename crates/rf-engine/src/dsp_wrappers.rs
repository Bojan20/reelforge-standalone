//! DSP Processor Wrappers
//!
//! InsertProcessor implementations for all rf-dsp modules.
//! Provides lock-free parameter updates and command queue integration.

use std::sync::atomic::{AtomicU64, Ordering};
use rf_core::Sample;
use rf_dsp::{
    ProEq, FilterShape,
    UltraEq, UltraFilterType, OversampleMode,
    StereoPultec, StereoApi550, StereoNeve1073,
    MorphingEq, EqPreset,
    StereoProcessor, Processor, ProcessorConfig,
};
use rf_dsp::eq_room::RoomCorrectionEq;
use rf_dsp::delay_compensation::LatencySamples;
use crate::insert_chain::InsertProcessor;

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
}

impl ProEqWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: ProEq::new(sample_rate),
            sample_rate,
        }
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

    /// Get enabled band count
    pub fn band_count(&self) -> usize {
        self.eq.enabled_band_count()
    }
}

impl InsertProcessor for ProEqWrapper {
    fn name(&self) -> &str {
        "ReelForge Pro-EQ 64"
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

    fn num_params(&self) -> usize {
        // freq, gain, q, enabled, shape per band + global params
        rf_dsp::PRO_EQ_MAX_BANDS * 5 + 3
    }

    fn get_param(&self, index: usize) -> f64 {
        let per_band = 5;
        let max_bands = rf_dsp::PRO_EQ_MAX_BANDS;

        if index < max_bands * per_band {
            let band_idx = index / per_band;
            let param_idx = index % per_band;
            if let Some(band) = self.eq.band(band_idx) {
                match param_idx {
                    0 => band.frequency,
                    1 => band.gain_db,
                    2 => band.q,
                    3 => if band.enabled { 1.0 } else { 0.0 },
                    4 => band.shape as u8 as f64,
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
        let per_band = 5;
        let max_bands = rf_dsp::PRO_EQ_MAX_BANDS;

        if index < max_bands * per_band {
            let band_idx = index / per_band;
            let param_idx = index % per_band;

            // Get current values and update
            if let Some(band) = self.eq.band(band_idx) {
                let mut freq = band.frequency;
                let mut gain = band.gain_db;
                let mut q = band.q;
                let shape = band.shape;

                match param_idx {
                    0 => freq = value.clamp(10.0, 30000.0),
                    1 => gain = value.clamp(-30.0, 30.0),
                    2 => q = value.clamp(0.05, 50.0),
                    3 => {
                        self.eq.enable_band(band_idx, value > 0.5);
                        return;
                    }
                    _ => return,
                }
                self.eq.set_band(band_idx, freq, gain, q, shape);
            }
        }
    }

    fn param_name(&self, index: usize) -> &str {
        let per_band = 5;
        let param_idx = index % per_band;
        match param_idx {
            0 => "Frequency",
            1 => "Gain",
            2 => "Q",
            3 => "Enabled",
            4 => "Shape",
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

    pub fn add_band(&mut self, freq: f64, gain: f64, q: f64, filter_type: UltraFilterType) -> Option<usize> {
        // Find free band
        for i in 0..rf_dsp::ULTRA_MAX_BANDS {
            if let Some(band) = self.eq.band(i) {
                if !band.enabled {
                    self.eq.set_band(i, freq, gain, q, filter_type);
                    return Some(i);
                }
            }
        }
        None
    }

    pub fn remove_band(&mut self, index: usize) -> bool {
        self.eq.enable_band(index, false);
        true
    }

    pub fn update_band(&mut self, index: usize, freq: f64, gain: f64, q: f64, filter_type: UltraFilterType) {
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
        "ReelForge Ultra-EQ 256"
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
}

impl Api550Wrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: StereoApi550::new(sample_rate),
            sample_rate,
        }
    }

    pub fn set_low(&mut self, gain_db: f64, freq: rf_dsp::Api550LowFreq) {
        self.eq.left.set_low(gain_db, freq);
        self.eq.right.set_low(gain_db, freq);
    }

    pub fn set_mid(&mut self, gain_db: f64, freq: rf_dsp::Api550MidFreq) {
        self.eq.left.set_mid(gain_db, freq);
        self.eq.right.set_mid(gain_db, freq);
    }

    pub fn set_high(&mut self, gain_db: f64, freq: rf_dsp::Api550HighFreq) {
        self.eq.left.set_high(gain_db, freq);
        self.eq.right.set_high(gain_db, freq);
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
    }

    fn num_params(&self) -> usize {
        3
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
        3  // HP enabled, Low gain, High gain
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0 => if self.hp_enabled { 1.0 } else { 0.0 },
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

// ============ Morphing EQ Wrapper ============

/// Morphing EQ with A/B preset morphing
pub struct MorphEqWrapper {
    eq: MorphingEq,
    sample_rate: f64,
}

impl MorphEqWrapper {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            eq: MorphingEq::new(sample_rate),
            sample_rate,
        }
    }

    /// Load preset into slot A
    pub fn load_preset_a(&mut self, preset: EqPreset) {
        self.eq.load_preset_a(preset);
    }

    /// Load preset into slot B
    pub fn load_preset_b(&mut self, preset: EqPreset) {
        self.eq.load_preset_b(preset);
    }

    /// Set morph position (0=A, 1=B)
    pub fn set_morph(&mut self, position: f64) {
        self.eq.set_morph(position);
    }

    /// Get current morph position
    pub fn get_morph_position(&self) -> f64 {
        self.eq.get_morph_position()
    }

    /// Morph to A
    pub fn morph_to_a(&mut self) {
        self.eq.morph_to_a();
    }

    /// Morph to B
    pub fn morph_to_b(&mut self) {
        self.eq.morph_to_b();
    }

    /// Toggle A/B instantly
    pub fn toggle_ab(&mut self) {
        self.eq.toggle_ab();
    }
}

impl InsertProcessor for MorphEqWrapper {
    fn name(&self) -> &str {
        "Morph EQ"
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.eq.process_block(left, right);
    }

    fn reset(&mut self) {
        // Reset by recreating with current sample rate
        self.eq = MorphingEq::new(self.sample_rate);
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        // Recreate with new sample rate
        self.eq = MorphingEq::new(sample_rate);
    }

    fn num_params(&self) -> usize {
        1  // Morph position
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0 => self.eq.get_morph_position(),
            _ => 0.0,
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.eq.set_morph(value.clamp(0.0, 1.0)),
            _ => {}
        }
    }

    fn param_name(&self, index: usize) -> &str {
        match index {
            0 => "Morph",
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
        1  // Enabled
    }

    fn get_param(&self, index: usize) -> f64 {
        match index {
            0 => if self.eq.enabled { 1.0 } else { 0.0 },
            _ => 0.0,
        }
    }

    fn set_param(&mut self, index: usize, value: f64) {
        match index {
            0 => self.eq.enabled = value > 0.5,
            _ => {}
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
        "morph-eq" | "MorphEQ" | "morph_eq" => Some(Box::new(MorphEqWrapper::new(sample_rate))),
        "room-correction" | "RoomCorrection" => Some(Box::new(RoomCorrectionWrapper::new(sample_rate))),
        _ => None,
    }
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
        assert_eq!(processor.unwrap().name(), "ReelForge Pro-EQ 64");
    }
}

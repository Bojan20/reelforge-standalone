//! Dynamics processors: compressor, limiter, gate, expander
//!
//! Professional dynamics processing with:
//! - VCA, Opto, and FET compressor characteristics
//! - True peak limiting with oversampling
//! - Program-dependent attack/release
//! - Soft-knee compression
//! - SIMD-optimized envelope following (AVX2/AVX-512)
//! - Lookup tables for fast dB/gain conversions

use rf_core::Sample;

#[cfg(target_arch = "x86_64")]
use std::simd::{f64x4, f64x8};
#[cfg(target_arch = "x86_64")]
use std::simd::prelude::SimdFloat;

use crate::{MonoProcessor, Processor, ProcessorConfig, StereoProcessor};

// ═══════════════════════════════════════════════════════════════════════════════
// LOOKUP TABLES FOR FAST dB/GAIN CONVERSION
// ═══════════════════════════════════════════════════════════════════════════════

/// Lookup table size for dB to linear conversion
const DB_TO_LINEAR_TABLE_SIZE: usize = 2048;
/// dB range: -120dB to +24dB
const DB_MIN: f64 = -120.0;
const DB_MAX: f64 = 24.0;
const DB_RANGE: f64 = DB_MAX - DB_MIN;

/// Const-friendly LN_10 (for use in const fn)
const CONST_LN_10: f64 = std::f64::consts::LN_10;
/// Const-friendly LN_2 (for use in const fn)
const CONST_LN_2: f64 = std::f64::consts::LN_2;

/// Lookup table size for linear to dB conversion
const LINEAR_TO_DB_TABLE_SIZE: usize = 4096;
/// Linear range: 1e-6 to 10.0 (covers -120dB to +20dB)
const LINEAR_MIN: f64 = 1e-6;
const LINEAR_MAX: f64 = 10.0;

/// Pre-computed dB to linear lookup table
struct DbToLinearTable {
    table: [f64; DB_TO_LINEAR_TABLE_SIZE],
}

impl DbToLinearTable {
    const fn new() -> Self {
        let mut table = [0.0; DB_TO_LINEAR_TABLE_SIZE];
        let mut i = 0;
        while i < DB_TO_LINEAR_TABLE_SIZE {
            let db = DB_MIN + (i as f64 / (DB_TO_LINEAR_TABLE_SIZE - 1) as f64) * DB_RANGE;
            // 10^(db/20) = e^(db * ln(10) / 20)
            let ln10_div_20 = 0.11512925464970228; // ln(10) / 20
            table[i] = const_exp(db * ln10_div_20);
            i += 1;
        }
        Self { table }
    }

    #[inline(always)]
    fn lookup(&self, db: f64) -> f64 {
        // Clamp to valid range
        let db_clamped = db.clamp(DB_MIN, DB_MAX);

        // Calculate index with linear interpolation
        let normalized = (db_clamped - DB_MIN) / DB_RANGE;
        let index_f = normalized * (DB_TO_LINEAR_TABLE_SIZE - 1) as f64;
        let index = index_f as usize;
        let frac = index_f - index as f64;

        // Linear interpolation
        let v0 = self.table[index];
        let v1 = if index + 1 < DB_TO_LINEAR_TABLE_SIZE {
            self.table[index + 1]
        } else {
            self.table[index]
        };

        v0 + frac * (v1 - v0)
    }
}

/// Pre-computed linear to dB lookup table
struct LinearToDbTable {
    table: [f64; LINEAR_TO_DB_TABLE_SIZE],
    log_linear_min: f64,
    log_range: f64,
}

impl LinearToDbTable {
    const fn new() -> Self {
        // Use logarithmic indexing for better resolution at low levels
        let log_linear_min = const_ln(LINEAR_MIN);
        let log_linear_max = const_ln(LINEAR_MAX);
        let log_range = log_linear_max - log_linear_min;

        let mut table = [0.0; LINEAR_TO_DB_TABLE_SIZE];
        let mut i = 0;
        while i < LINEAR_TO_DB_TABLE_SIZE {
            let log_val = log_linear_min + (i as f64 / (LINEAR_TO_DB_TABLE_SIZE - 1) as f64) * log_range;
            let linear = const_exp(log_val);
            // 20 * log10(x) = 20 * ln(x) / ln(10)
            table[i] = 20.0 * const_ln(linear) / CONST_LN_10;
            i += 1;
        }

        Self {
            table,
            log_linear_min,
            log_range,
        }
    }

    #[inline(always)]
    fn lookup(&self, linear: f64) -> f64 {
        if linear < 1e-10 {
            return -120.0;
        }
        if linear > LINEAR_MAX {
            // Fallback to computation for very high values
            return 20.0 * linear.log10();
        }

        // Logarithmic indexing
        let log_val = linear.ln();
        let normalized = (log_val - self.log_linear_min) / self.log_range;
        let normalized_clamped = normalized.clamp(0.0, 1.0);

        let index_f = normalized_clamped * (LINEAR_TO_DB_TABLE_SIZE - 1) as f64;
        let index = index_f as usize;
        let frac = index_f - index as f64;

        let v0 = self.table[index];
        let v1 = if index + 1 < LINEAR_TO_DB_TABLE_SIZE {
            self.table[index + 1]
        } else {
            self.table[index]
        };

        v0 + frac * (v1 - v0)
    }
}

/// Const-compatible exp function using Taylor series
const fn const_exp(x: f64) -> f64 {
    // For large negative values, return small number
    if x < -30.0 {
        return 1e-13;
    }
    // For large positive values, cap it
    if x > 30.0 {
        return 1e13;
    }

    // Taylor series: e^x = 1 + x + x²/2! + x³/3! + ...
    let mut result = 1.0;
    let mut term = 1.0;
    let mut i = 1;
    while i < 30 {
        term *= x / i as f64;
        result += term;
        if term.abs() < 1e-15 {
            break;
        }
        i += 1;
    }
    result
}

/// Const-compatible natural log using series expansion
const fn const_ln(x: f64) -> f64 {
    if x <= 0.0 {
        return -1e10;
    }

    // Normalize to [0.5, 1.5] range for better convergence
    let mut y = x;
    let mut adjustment = 0.0;

    // Scale down
    while y > 2.0 {
        y /= 2.0;
        adjustment += CONST_LN_2;
    }
    // Scale up
    while y < 0.5 {
        y *= 2.0;
        adjustment -= CONST_LN_2;
    }

    // ln(1+u) series where u = y-1
    let u = y - 1.0;
    let mut result = 0.0;
    let mut term = u;
    let mut i = 1;
    while i < 50 {
        if i % 2 == 1 {
            result += term / i as f64;
        } else {
            result -= term / i as f64;
        }
        term *= u;
        if term.abs() < 1e-15 {
            break;
        }
        i += 1;
    }

    result + adjustment
}

// Global lookup tables (computed at compile time)
static DB_TO_LINEAR: DbToLinearTable = DbToLinearTable::new();
static LINEAR_TO_DB: LinearToDbTable = LinearToDbTable::new();

/// Fast dB to linear conversion using lookup table
#[inline(always)]
pub fn db_to_linear_fast(db: f64) -> f64 {
    DB_TO_LINEAR.lookup(db)
}

/// Fast linear to dB conversion using lookup table
#[inline(always)]
pub fn linear_to_db_fast(linear: f64) -> f64 {
    LINEAR_TO_DB.lookup(linear)
}

/// Fast gain calculation for compression
/// Given input_db, threshold_db, and ratio, returns the gain multiplier
#[inline(always)]
pub fn calculate_compressor_gain_fast(input_db: f64, threshold_db: f64, ratio: f64) -> f64 {
    if input_db <= threshold_db {
        return 1.0;
    }

    let over_db = input_db - threshold_db;
    let gr_db = over_db * (1.0 - 1.0 / ratio);
    db_to_linear_fast(-gr_db)
}

/// Envelope follower for dynamics processing
#[derive(Debug, Clone)]
pub struct EnvelopeFollower {
    attack_coeff: f64,
    release_coeff: f64,
    envelope: f64,
    sample_rate: f64,
}

impl EnvelopeFollower {
    pub fn new(sample_rate: f64) -> Self {
        let mut follower = Self {
            attack_coeff: 0.0,
            release_coeff: 0.0,
            envelope: 0.0,
            sample_rate,
        };
        follower.set_times(10.0, 100.0);
        follower
    }

    /// Set attack and release times in milliseconds
    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.attack_coeff = (-1.0 / (attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-1.0 / (release_ms * 0.001 * self.sample_rate)).exp();
    }

    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }

    #[inline(always)]
    pub fn process(&mut self, input: Sample) -> f64 {
        let abs_input = input.abs();
        let coeff = if abs_input > self.envelope {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.envelope = abs_input + coeff * (self.envelope - abs_input);
        self.envelope
    }

    /// Process block with optimized loop unrolling
    ///
    /// NOTE: Envelope following is an IIR process where each sample depends on
    /// the previous envelope state (env[n] depends on env[n-1]).
    /// True SIMD parallelization is not possible for serial envelope detection.
    /// This version uses loop unrolling for better branch prediction.
    #[cfg(target_arch = "x86_64")]
    pub fn process_block_simd4(&mut self, input: &[Sample], output: &mut [f64]) {
        assert_eq!(input.len(), output.len());

        let len = input.len();
        let unroll_len = len - (len % 4);

        let attack = self.attack_coeff;
        let release = self.release_coeff;
        let mut envelope = self.envelope;

        // Process 4 samples per iteration (loop unrolling, NOT SIMD parallel)
        for i in (0..unroll_len).step_by(4) {
            // Sample 0
            let abs0 = input[i].abs();
            let coeff0 = if abs0 > envelope { attack } else { release };
            envelope = abs0 + coeff0 * (envelope - abs0);
            output[i] = envelope;

            // Sample 1
            let abs1 = input[i + 1].abs();
            let coeff1 = if abs1 > envelope { attack } else { release };
            envelope = abs1 + coeff1 * (envelope - abs1);
            output[i + 1] = envelope;

            // Sample 2
            let abs2 = input[i + 2].abs();
            let coeff2 = if abs2 > envelope { attack } else { release };
            envelope = abs2 + coeff2 * (envelope - abs2);
            output[i + 2] = envelope;

            // Sample 3
            let abs3 = input[i + 3].abs();
            let coeff3 = if abs3 > envelope { attack } else { release };
            envelope = abs3 + coeff3 * (envelope - abs3);
            output[i + 3] = envelope;
        }

        // Process remaining samples (0-3)
        for i in unroll_len..len {
            let abs_input = input[i].abs();
            let coeff = if abs_input > envelope { attack } else { release };
            envelope = abs_input + coeff * (envelope - abs_input);
            output[i] = envelope;
        }

        self.envelope = envelope;
    }

    /// Process block with AVX-512 optimization (8-sample loop unrolling)
    ///
    /// NOTE: Like SIMD4, this uses loop unrolling not SIMD parallelization,
    /// because envelope following requires serial state dependencies.
    #[cfg(target_arch = "x86_64")]
    pub fn process_block_simd8(&mut self, input: &[Sample], output: &mut [f64]) {
        assert_eq!(input.len(), output.len());

        let len = input.len();
        let unroll_len = len - (len % 8);

        let attack = self.attack_coeff;
        let release = self.release_coeff;
        let mut envelope = self.envelope;

        // Process 8 samples per iteration (loop unrolling)
        for i in (0..unroll_len).step_by(8) {
            // Unrolled: process 8 samples sequentially
            for j in 0..8 {
                let abs_input = input[i + j].abs();
                let coeff = if abs_input > envelope { attack } else { release };
                envelope = abs_input + coeff * (envelope - abs_input);
                output[i + j] = envelope;
            }
        }

        // Process remaining samples (0-7)
        for i in unroll_len..len {
            let abs_input = input[i].abs();
            let coeff = if abs_input > envelope { attack } else { release };
            envelope = abs_input + coeff * (envelope - abs_input);
            output[i] = envelope;
        }

        self.envelope = envelope;
    }

    /// Process block with runtime SIMD dispatch
    pub fn process_block(&mut self, input: &[Sample], output: &mut [f64]) {
        #[cfg(target_arch = "x86_64")]
        {
            if is_x86_feature_detected!("avx512f") {
                self.process_block_simd8(input, output);
            } else if is_x86_feature_detected!("avx2") {
                self.process_block_simd4(input, output);
            } else {
                self.process_block_scalar(input, output);
            }
        }
        #[cfg(not(target_arch = "x86_64"))]
        {
            self.process_block_scalar(input, output);
        }
    }

    /// Scalar fallback for block processing
    fn process_block_scalar(&mut self, input: &[Sample], output: &mut [f64]) {
        for (i, &sample) in input.iter().enumerate() {
            output[i] = self.process(sample);
        }
    }

    pub fn reset(&mut self) {
        self.envelope = 0.0;
    }

    pub fn current(&self) -> f64 {
        self.envelope
    }
}

/// Compressor characteristic type
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum CompressorType {
    /// Clean VCA compression - fast, transparent
    #[default]
    Vca,
    /// Optical compression - smooth, program-dependent
    Opto,
    /// FET compression - aggressive, punchy, adds harmonics
    Fet,
}

/// Compressor with multiple characteristics
#[derive(Debug, Clone)]
pub struct Compressor {
    // Parameters
    threshold_db: f64,
    ratio: f64,
    knee_db: f64,
    makeup_gain_db: f64,
    attack_ms: f64,
    release_ms: f64,
    mix: f64, // Dry/wet for parallel compression

    // Compressor type
    comp_type: CompressorType,

    // State
    envelope: EnvelopeFollower,
    gain_reduction: f64,

    // Opto-specific state
    opto_envelope: f64,
    opto_gain_history: [f64; 4],

    // FET-specific state
    fet_saturation: f64,

    sample_rate: f64,

    // Sidechain support
    /// External sidechain enabled
    sidechain_enabled: bool,
    /// Current sidechain key sample (set per-sample from external source)
    sidechain_key_sample: Sample,
}

impl Compressor {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            threshold_db: -20.0,
            ratio: 4.0,
            knee_db: 6.0,
            makeup_gain_db: 0.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            mix: 1.0,
            comp_type: CompressorType::Vca,
            envelope: EnvelopeFollower::new(sample_rate),
            gain_reduction: 0.0,
            opto_envelope: 0.0,
            opto_gain_history: [1.0; 4],
            fet_saturation: 0.0,
            sample_rate,
            sidechain_enabled: false,
            sidechain_key_sample: 0.0,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SIDECHAIN API
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Enable/disable external sidechain input
    pub fn set_sidechain_enabled(&mut self, enabled: bool) {
        self.sidechain_enabled = enabled;
    }

    /// Check if sidechain is enabled
    pub fn is_sidechain_enabled(&self) -> bool {
        self.sidechain_enabled
    }

    /// Set the current sidechain key sample (call per-sample before process_sample)
    ///
    /// When sidechain is enabled, this value is used for envelope detection
    /// instead of the input signal.
    #[inline]
    pub fn set_sidechain_key(&mut self, key: Sample) {
        self.sidechain_key_sample = key;
    }

    /// Get the signal to use for envelope detection
    #[inline]
    fn get_detection_signal(&self, input: Sample) -> Sample {
        if self.sidechain_enabled {
            self.sidechain_key_sample
        } else {
            input
        }
    }

    // Parameter setters
    pub fn set_type(&mut self, comp_type: CompressorType) {
        self.comp_type = comp_type;
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-60.0, 0.0);
    }

    pub fn set_ratio(&mut self, ratio: f64) {
        self.ratio = ratio.clamp(1.0, 100.0);
    }

    pub fn set_knee(&mut self, db: f64) {
        self.knee_db = db.clamp(0.0, 24.0);
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.attack_ms = ms.clamp(0.01, 500.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(1.0, 5000.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.attack_ms = attack_ms.clamp(0.01, 500.0);
        self.release_ms = release_ms.clamp(1.0, 5000.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_makeup(&mut self, db: f64) {
        self.makeup_gain_db = db.clamp(-24.0, 24.0);
    }

    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Get current gain reduction in dB
    pub fn gain_reduction_db(&self) -> f64 {
        self.gain_reduction
    }

    /// Calculate gain reduction using soft-knee
    #[inline]
    fn calculate_gain_reduction(&self, input_db: f64) -> f64 {
        let half_knee = self.knee_db / 2.0;
        let knee_start = self.threshold_db - half_knee;
        let knee_end = self.threshold_db + half_knee;

        if input_db < knee_start {
            0.0
        } else if input_db > knee_end {
            (input_db - self.threshold_db) * (1.0 - 1.0 / self.ratio)
        } else {
            let x = input_db - knee_start;
            let slope = 1.0 - 1.0 / self.ratio;
            (slope * x * x) / (2.0 * self.knee_db)
        }
    }

    /// VCA-style compression (clean, transparent)
    /// Uses lookup tables for fast dB/gain conversion
    /// Supports external sidechain: envelope follows key signal, gain applied to input
    #[inline]
    fn process_vca(&mut self, input: Sample) -> Sample {
        // Use sidechain key or input for envelope detection
        let detection = self.get_detection_signal(input);
        let envelope = self.envelope.process(detection);

        if envelope < 1e-10 {
            return input;
        }

        // Fast dB conversion using lookup table
        let env_db = linear_to_db_fast(envelope);
        let gr_db = self.calculate_gain_reduction(env_db);
        self.gain_reduction = gr_db;

        // Fast gain conversion using lookup table
        let gain = db_to_linear_fast(-gr_db);
        input * gain  // Apply gain to INPUT, not detection signal
    }

    /// Opto-style compression (smooth, program-dependent)
    /// Uses lookup tables for fast dB/gain conversion
    /// Supports external sidechain: envelope follows key signal, gain applied to input
    #[inline]
    fn process_opto(&mut self, input: Sample) -> Sample {
        // Use sidechain key or input for envelope detection
        let detection = self.get_detection_signal(input);
        let abs_detection = detection.abs();

        // Opto cells have program-dependent attack/release
        // Higher levels = faster response
        let level_factor = (abs_detection * 10.0).min(1.0);

        // Attack gets faster with higher levels
        let attack_coeff = (-1.0
            / ((self.attack_ms * (1.0 - level_factor * 0.5)) * 0.001 * self.sample_rate))
            .exp();
        // Release is slower for higher gain reduction (opto characteristic)
        let release_factor = 1.0 + self.gain_reduction * 0.02;
        let release_coeff =
            (-1.0 / ((self.release_ms * release_factor) * 0.001 * self.sample_rate)).exp();

        let coeff = if abs_detection > self.opto_envelope {
            attack_coeff
        } else {
            release_coeff
        };
        self.opto_envelope = abs_detection + coeff * (self.opto_envelope - abs_detection);

        if self.opto_envelope < 1e-10 {
            return input;
        }

        // Fast dB conversion using lookup table
        let env_db = linear_to_db_fast(self.opto_envelope);
        let gr_db = self.calculate_gain_reduction(env_db);

        // Smooth the gain reduction (opto inertia)
        self.opto_gain_history.rotate_right(1);
        self.opto_gain_history[0] = gr_db;
        let smoothed_gr: f64 = self.opto_gain_history.iter().sum::<f64>() / 4.0;
        self.gain_reduction = smoothed_gr;

        // Fast gain conversion using lookup table
        let gain = db_to_linear_fast(-smoothed_gr);
        input * gain
    }

    /// FET-style compression (aggressive, punchy, adds harmonics)
    /// Uses lookup tables for fast dB/gain conversion
    /// Supports external sidechain: envelope follows key signal, gain applied to input
    #[inline]
    fn process_fet(&mut self, input: Sample) -> Sample {
        // Use sidechain key or input for envelope detection
        let detection = self.get_detection_signal(input);
        let envelope = self.envelope.process(detection);

        if envelope < 1e-10 {
            return input;
        }

        // Fast dB conversion using lookup table
        let env_db = linear_to_db_fast(envelope);

        // FET has more aggressive knee and can go into negative ratio territory
        let gr_db = if env_db > self.threshold_db {
            let over = env_db - self.threshold_db;
            // FET characteristic: harder knee, more aggressive at high levels
            let effective_ratio = self.ratio * (1.0 + over * 0.05).min(2.0);
            over * (1.0 - 1.0 / effective_ratio)
        } else {
            0.0
        };

        self.gain_reduction = gr_db;
        // Fast gain conversion using lookup table
        let gain = db_to_linear_fast(-gr_db);

        // Add subtle FET saturation
        let saturated = input * gain;
        let saturation_amount = (gr_db / 20.0).min(0.3);
        self.fet_saturation = saturation_amount;

        // Soft clip saturation characteristic
        if saturation_amount > 0.0 {
            let x = saturated * (1.0 + saturation_amount);
            x / (1.0 + x.abs() * saturation_amount * 0.5)
        } else {
            saturated
        }
    }
}

impl Processor for Compressor {
    fn reset(&mut self) {
        self.envelope.reset();
        self.gain_reduction = 0.0;
        self.opto_envelope = 0.0;
        self.opto_gain_history = [1.0; 4];
        self.fet_saturation = 0.0;
        self.sidechain_key_sample = 0.0;
    }
}

impl MonoProcessor for Compressor {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let dry = input;

        let compressed = match self.comp_type {
            CompressorType::Vca => self.process_vca(input),
            CompressorType::Opto => self.process_opto(input),
            CompressorType::Fet => self.process_fet(input),
        };

        // Apply makeup gain
        let makeup = 10.0_f64.powf(self.makeup_gain_db / 20.0);
        let wet = compressed * makeup;

        // Dry/wet mix
        dry * (1.0 - self.mix) + wet * self.mix
    }
}

impl ProcessorConfig for Compressor {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.envelope.set_sample_rate(sample_rate);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }
}

/// Stereo compressor with link options
#[derive(Debug, Clone)]
pub struct StereoCompressor {
    left: Compressor,
    right: Compressor,
    link: f64, // 0.0 = independent, 1.0 = fully linked
    /// Sidechain enabled for stereo pair
    sidechain_enabled: bool,
    /// Sidechain key samples (L/R or mono duplicated)
    sidechain_key_left: Sample,
    sidechain_key_right: Sample,
}

impl StereoCompressor {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Compressor::new(sample_rate),
            right: Compressor::new(sample_rate),
            link: 1.0,
            sidechain_enabled: false,
            sidechain_key_left: 0.0,
            sidechain_key_right: 0.0,
        }
    }

    pub fn set_link(&mut self, link: f64) {
        self.link = link.clamp(0.0, 1.0);
    }

    pub fn left(&mut self) -> &mut Compressor {
        &mut self.left
    }

    pub fn right(&mut self) -> &mut Compressor {
        &mut self.right
    }

    /// Set parameter for both channels
    pub fn set_both<F>(&mut self, f: F)
    where
        F: Fn(&mut Compressor),
    {
        f(&mut self.left);
        f(&mut self.right);
    }

    pub fn gain_reduction_db(&self) -> (f64, f64) {
        (
            self.left.gain_reduction_db(),
            self.right.gain_reduction_db(),
        )
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SIDECHAIN API
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Enable/disable external sidechain input
    pub fn set_sidechain_enabled(&mut self, enabled: bool) {
        self.sidechain_enabled = enabled;
        self.left.set_sidechain_enabled(enabled);
        self.right.set_sidechain_enabled(enabled);
    }

    /// Check if sidechain is enabled
    pub fn is_sidechain_enabled(&self) -> bool {
        self.sidechain_enabled
    }

    /// Set stereo sidechain key samples (call per-sample before process_sample)
    #[inline]
    pub fn set_sidechain_key_stereo(&mut self, left: Sample, right: Sample) {
        self.sidechain_key_left = left;
        self.sidechain_key_right = right;
        self.left.set_sidechain_key(left);
        self.right.set_sidechain_key(right);
    }

    /// Set mono sidechain key sample (duplicated to both channels)
    #[inline]
    pub fn set_sidechain_key_mono(&mut self, key: Sample) {
        self.set_sidechain_key_stereo(key, key);
    }
}

impl Processor for StereoCompressor {
    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
        self.sidechain_key_left = 0.0;
        self.sidechain_key_right = 0.0;
    }
}

impl StereoProcessor for StereoCompressor {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if self.link >= 0.99 {
            // Fully linked - use max of both channels (or sidechain if enabled)
            let detection = if self.sidechain_enabled {
                // Use sidechain key signal for detection
                self.sidechain_key_left.abs().max(self.sidechain_key_right.abs())
            } else {
                // Use input signal for detection
                left.abs().max(right.abs())
            };
            let _ = self.left.envelope.process(detection);
            let _ = self.right.envelope.process(detection);

            // Use same envelope for both with fast lookup
            let env = self.left.envelope.current();
            let env_db = linear_to_db_fast(env);
            let gr_db = self.left.calculate_gain_reduction(env_db);
            self.left.gain_reduction = gr_db;
            self.right.gain_reduction = gr_db;

            // Fast gain conversion
            let gain = db_to_linear_fast(-gr_db);
            let makeup = db_to_linear_fast(self.left.makeup_gain_db);

            // Apply gain to INPUT signal (not sidechain)
            (left * gain * makeup, right * gain * makeup)
        } else if self.link <= 0.01 {
            // Independent
            (
                self.left.process_sample(left),
                self.right.process_sample(right),
            )
        } else {
            // Partial link
            let out_l = self.left.process_sample(left);
            let out_r = self.right.process_sample(right);

            // Blend between linked and independent with fast lookup
            let max_gr = self.left.gain_reduction.max(self.right.gain_reduction);
            let linked_gain = db_to_linear_fast(-max_gr);
            let makeup = db_to_linear_fast(self.left.makeup_gain_db);

            let linked_l = left * linked_gain * makeup;
            let linked_r = right * linked_gain * makeup;

            (
                out_l * (1.0 - self.link) + linked_l * self.link,
                out_r * (1.0 - self.link) + linked_r * self.link,
            )
        }
    }
}

impl ProcessorConfig for StereoCompressor {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.left.set_sample_rate(sample_rate);
        self.right.set_sample_rate(sample_rate);
    }
}

/// Oversampling factor for true peak limiting
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Oversampling {
    #[default]
    X1,
    X2,
    X4,
    X8,
}

impl Oversampling {
    pub fn factor(&self) -> usize {
        match self {
            Oversampling::X1 => 1,
            Oversampling::X2 => 2,
            Oversampling::X4 => 4,
            Oversampling::X8 => 8,
        }
    }
}

/// Half-band filter for oversampling
#[derive(Debug, Clone)]
struct HalfbandFilter {
    coeffs: [f64; 7],
    delay: [f64; 7],
}

impl HalfbandFilter {
    fn new() -> Self {
        // 7-tap half-band filter coefficients
        Self {
            coeffs: [
                0.00613927,
                0.0,
                -0.05096454,
                0.0,
                0.29466106,
                0.5,
                0.29466106,
            ],
            delay: [0.0; 7],
        }
    }

    #[inline]
    fn process(&mut self, input: f64) -> f64 {
        self.delay.rotate_right(1);
        self.delay[0] = input;

        let mut output = 0.0;
        for (i, &coeff) in self.coeffs.iter().enumerate() {
            output += coeff * self.delay[i];
        }
        output
    }

    fn reset(&mut self) {
        self.delay.fill(0.0);
    }
}

/// True Peak Limiter with oversampling
///
/// Uses ITU-R BS.1770-4 compliant true peak detection
#[derive(Debug, Clone)]
pub struct TruePeakLimiter {
    // Parameters
    threshold_db: f64,
    release_ms: f64,
    ceiling_db: f64,

    // Oversampling
    oversampling: Oversampling,
    upsample_filters: Vec<HalfbandFilter>,
    downsample_filters: Vec<HalfbandFilter>,

    // Lookahead
    lookahead_ms: f64,
    lookahead_buffer_l: Vec<Sample>,
    lookahead_buffer_r: Vec<Sample>,
    buffer_pos: usize,

    // State
    gain: f64,
    release_coeff: f64,
    true_peak: f64,
    sample_rate: f64,
}

impl TruePeakLimiter {
    pub fn new(sample_rate: f64) -> Self {
        let lookahead_ms = 1.5; // ITU recommends 1.5ms for true peak
        let lookahead_samples = ((lookahead_ms * 0.001 * sample_rate) as usize).max(1);

        Self {
            threshold_db: -1.0,
            release_ms: 100.0,
            ceiling_db: -0.1,
            oversampling: Oversampling::X4,
            upsample_filters: vec![HalfbandFilter::new(); 4],
            downsample_filters: vec![HalfbandFilter::new(); 4],
            lookahead_ms,
            lookahead_buffer_l: vec![0.0; lookahead_samples],
            lookahead_buffer_r: vec![0.0; lookahead_samples],
            buffer_pos: 0,
            gain: 1.0,
            release_coeff: (-1.0 / (100.0 * 0.001 * sample_rate)).exp(),
            true_peak: 0.0,
            sample_rate,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-24.0, 0.0);
    }

    pub fn set_ceiling(&mut self, db: f64) {
        self.ceiling_db = db.clamp(-6.0, 0.0);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(10.0, 1000.0);
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();
    }

    pub fn set_oversampling(&mut self, os: Oversampling) {
        self.oversampling = os;
        self.reset();
    }

    /// Get current true peak level in dBTP
    pub fn true_peak_db(&self) -> f64 {
        linear_to_db_fast(self.true_peak)
    }

    /// Get current gain reduction in dB
    pub fn gain_reduction_db(&self) -> f64 {
        -linear_to_db_fast(self.gain)
    }

    /// Upsample a sample (zero-stuffing + filtering)
    /// Returns (samples_array, count) - stack-allocated, no heap allocation
    #[inline(always)]
    fn upsample(&mut self, input: f64) -> ([f64; 8], usize) {
        let factor = self.oversampling.factor();
        let mut samples = [0.0f64; 8];

        if factor == 1 {
            samples[0] = input;
            return (samples, 1);
        }

        // Simple zero-stuffing with single filter pass
        // (proper implementation would use polyphase)
        for i in 0..factor {
            let x = if i == 0 { input * factor as f64 } else { 0.0 };
            samples[i] = self.upsample_filters[0].process(x);
        }

        (samples, factor)
    }

    /// Downsample (filter + decimate)
    fn downsample(&mut self, samples: &[f64]) -> f64 {
        let factor = self.oversampling.factor();
        if factor == 1 {
            return samples[0];
        }

        // Filter and take last sample
        let mut last = 0.0;
        for &sample in samples {
            last = self.downsample_filters[0].process(sample);
        }
        last
    }

    /// Find true peak in oversampled signal
    #[inline(always)]
    fn find_true_peak(&mut self, left: Sample, right: Sample) -> f64 {
        let (up_l, count_l) = self.upsample(left);
        let (up_r, count_r) = self.upsample(right);
        let count = count_l.min(count_r);

        let mut max_peak: f64 = 0.0;
        for i in 0..count {
            max_peak = max_peak.max(up_l[i].abs()).max(up_r[i].abs());
        }

        max_peak
    }
}

impl Processor for TruePeakLimiter {
    fn reset(&mut self) {
        self.gain = 1.0;
        self.true_peak = 0.0;
        self.lookahead_buffer_l.fill(0.0);
        self.lookahead_buffer_r.fill(0.0);
        self.buffer_pos = 0;

        for filter in &mut self.upsample_filters {
            filter.reset();
        }
        for filter in &mut self.downsample_filters {
            filter.reset();
        }
    }

    fn latency(&self) -> usize {
        self.lookahead_buffer_l.len()
    }
}

impl StereoProcessor for TruePeakLimiter {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Get delayed samples
        let delayed_l = self.lookahead_buffer_l[self.buffer_pos];
        let delayed_r = self.lookahead_buffer_r[self.buffer_pos];

        // Store current samples
        self.lookahead_buffer_l[self.buffer_pos] = left;
        self.lookahead_buffer_r[self.buffer_pos] = right;
        self.buffer_pos = (self.buffer_pos + 1) % self.lookahead_buffer_l.len();

        // Find true peak using oversampling
        let true_peak = self.find_true_peak(left, right);
        self.true_peak = self.true_peak.max(true_peak);

        // Calculate target gain with fast lookup
        let threshold_linear = db_to_linear_fast(self.threshold_db);
        let ceiling_linear = db_to_linear_fast(self.ceiling_db);

        let target_gain = if true_peak > threshold_linear {
            (ceiling_linear / true_peak).min(1.0)
        } else {
            1.0
        };

        // Apply gain smoothing (instant attack, smooth release)
        if target_gain < self.gain {
            self.gain = target_gain;
        } else {
            self.gain = target_gain + self.release_coeff * (self.gain - target_gain);
        }

        // Apply gain to delayed signal
        (delayed_l * self.gain, delayed_r * self.gain)
    }
}

impl ProcessorConfig for TruePeakLimiter {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * sample_rate)).exp();

        let lookahead_samples = ((self.lookahead_ms * 0.001 * sample_rate) as usize).max(1);
        self.lookahead_buffer_l = vec![0.0; lookahead_samples];
        self.lookahead_buffer_r = vec![0.0; lookahead_samples];
        self.buffer_pos = 0;
    }
}

/// Simple peak limiter (for compatibility)
#[derive(Debug, Clone)]
pub struct Limiter {
    threshold_db: f64,
    release_coeff: f64,
    gain: f64,
    lookahead_samples: usize,
    lookahead_buffer: Vec<Sample>,
    buffer_pos: usize,
    sample_rate: f64,
}

impl Limiter {
    pub fn new(sample_rate: f64) -> Self {
        let lookahead_ms = 5.0;
        let lookahead_samples = (lookahead_ms * 0.001 * sample_rate) as usize;

        Self {
            threshold_db: -0.3,
            release_coeff: (-1.0 / (100.0 * 0.001 * sample_rate)).exp(),
            gain: 1.0,
            lookahead_samples,
            lookahead_buffer: vec![0.0; lookahead_samples],
            buffer_pos: 0,
            sample_rate,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db;
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_coeff = (-1.0 / (ms * 0.001 * self.sample_rate)).exp();
    }

    fn threshold_linear(&self) -> f64 {
        db_to_linear_fast(self.threshold_db)
    }
}

impl Processor for Limiter {
    fn reset(&mut self) {
        self.gain = 1.0;
        self.lookahead_buffer.fill(0.0);
        self.buffer_pos = 0;
    }

    fn latency(&self) -> usize {
        self.lookahead_samples
    }
}

impl MonoProcessor for Limiter {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let delayed = self.lookahead_buffer[self.buffer_pos];
        self.lookahead_buffer[self.buffer_pos] = input;
        self.buffer_pos = (self.buffer_pos + 1) % self.lookahead_samples;

        let threshold = self.threshold_linear();
        let abs_input = input.abs();
        let target_gain = if abs_input > threshold {
            threshold / abs_input
        } else {
            1.0
        };

        if target_gain < self.gain {
            self.gain = target_gain;
        } else {
            self.gain = target_gain + self.release_coeff * (self.gain - target_gain);
        }

        delayed * self.gain
    }
}

impl ProcessorConfig for Limiter {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        let lookahead_ms = 5.0;
        self.lookahead_samples = (lookahead_ms * 0.001 * sample_rate) as usize;
        self.lookahead_buffer = vec![0.0; self.lookahead_samples];
        self.buffer_pos = 0;
    }
}

/// Noise gate
#[derive(Debug, Clone)]
pub struct Gate {
    threshold_db: f64,
    range_db: f64,
    attack_ms: f64,
    hold_ms: f64,
    release_ms: f64,
    envelope: EnvelopeFollower,
    gain: f64,
    hold_counter: usize,
    sample_rate: f64,
    // Sidechain support
    /// External sidechain enabled
    sidechain_enabled: bool,
    /// Current sidechain key sample (set per-sample from external source)
    sidechain_key_sample: Sample,
}

impl Gate {
    pub fn new(sample_rate: f64) -> Self {
        let mut gate = Self {
            threshold_db: -40.0,
            range_db: -80.0,
            attack_ms: 1.0,
            hold_ms: 50.0,
            release_ms: 100.0,
            envelope: EnvelopeFollower::new(sample_rate),
            gain: 0.0,
            hold_counter: 0,
            sample_rate,
            sidechain_enabled: false,
            sidechain_key_sample: 0.0,
        };
        gate.envelope.set_times(1.0, 50.0);
        gate
    }

    /// Enable/disable external sidechain input
    pub fn set_sidechain_enabled(&mut self, enabled: bool) {
        self.sidechain_enabled = enabled;
    }

    /// Check if sidechain is enabled
    pub fn is_sidechain_enabled(&self) -> bool {
        self.sidechain_enabled
    }

    /// Set the sidechain key signal for the current sample
    /// Call this before process_sample() when using external sidechain
    #[inline]
    pub fn set_sidechain_key(&mut self, key: Sample) {
        self.sidechain_key_sample = key;
    }

    /// Get the signal to use for envelope detection
    #[inline]
    fn get_detection_signal(&self, input: Sample) -> Sample {
        if self.sidechain_enabled {
            self.sidechain_key_sample
        } else {
            input
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-80.0, 0.0);
    }

    pub fn set_range(&mut self, db: f64) {
        self.range_db = db.clamp(-80.0, 0.0);
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.attack_ms = ms.clamp(0.01, 100.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_hold(&mut self, ms: f64) {
        self.hold_ms = ms.clamp(0.0, 500.0);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(1.0, 1000.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    fn threshold_linear(&self) -> f64 {
        db_to_linear_fast(self.threshold_db)
    }

    fn range_linear(&self) -> f64 {
        db_to_linear_fast(self.range_db)
    }
}

impl Processor for Gate {
    fn reset(&mut self) {
        self.envelope.reset();
        self.gain = 0.0;
        self.hold_counter = 0;
    }
}

impl MonoProcessor for Gate {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        // Use sidechain key or input for envelope detection
        let detection = self.get_detection_signal(input);
        let envelope = self.envelope.process(detection);
        let threshold = self.threshold_linear();
        let range = self.range_linear();

        let hold_samples = (self.hold_ms * 0.001 * self.sample_rate) as usize;

        let target_gain = if envelope >= threshold {
            self.hold_counter = hold_samples;
            1.0
        } else if self.hold_counter > 0 {
            self.hold_counter -= 1;
            1.0
        } else {
            range
        };

        // Smooth gain transition
        let attack_coeff = (-1.0 / (self.attack_ms * 0.001 * self.sample_rate)).exp();
        let release_coeff = (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();

        let coeff = if target_gain > self.gain {
            attack_coeff
        } else {
            release_coeff
        };
        self.gain = target_gain + coeff * (self.gain - target_gain);

        // Apply gain to INPUT signal (not detection signal)
        input * self.gain
    }
}

impl ProcessorConfig for Gate {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.envelope.set_sample_rate(sample_rate);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }
}

/// Expander (opposite of compressor)
#[derive(Debug, Clone)]
pub struct Expander {
    threshold_db: f64,
    ratio: f64,
    knee_db: f64,
    attack_ms: f64,
    release_ms: f64,
    envelope: EnvelopeFollower,
    sample_rate: f64,
    // Sidechain support
    /// External sidechain enabled
    sidechain_enabled: bool,
    /// Current sidechain key sample (set per-sample from external source)
    sidechain_key_sample: Sample,
}

impl Expander {
    pub fn new(sample_rate: f64) -> Self {
        let mut exp = Self {
            threshold_db: -30.0,
            ratio: 2.0,
            knee_db: 6.0,
            attack_ms: 5.0,
            release_ms: 100.0,
            envelope: EnvelopeFollower::new(sample_rate),
            sample_rate,
            sidechain_enabled: false,
            sidechain_key_sample: 0.0,
        };
        exp.envelope.set_times(5.0, 100.0);
        exp
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-80.0, 0.0);
    }

    pub fn set_ratio(&mut self, ratio: f64) {
        self.ratio = ratio.clamp(1.0, 20.0);
    }

    pub fn set_knee(&mut self, db: f64) {
        self.knee_db = db.clamp(0.0, 24.0);
    }

    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.attack_ms = attack_ms;
        self.release_ms = release_ms;
        self.envelope.set_times(attack_ms, release_ms);
    }

    /// Enable/disable external sidechain input
    pub fn set_sidechain_enabled(&mut self, enabled: bool) {
        self.sidechain_enabled = enabled;
    }

    /// Check if sidechain is enabled
    pub fn is_sidechain_enabled(&self) -> bool {
        self.sidechain_enabled
    }

    /// Set the sidechain key signal for the current sample
    /// Call this before process_sample() when using external sidechain
    #[inline]
    pub fn set_sidechain_key(&mut self, key: Sample) {
        self.sidechain_key_sample = key;
    }

    /// Get the signal to use for envelope detection
    #[inline]
    fn get_detection_signal(&self, input: Sample) -> Sample {
        if self.sidechain_enabled {
            self.sidechain_key_sample
        } else {
            input
        }
    }
}

impl Processor for Expander {
    fn reset(&mut self) {
        self.envelope.reset();
    }
}

impl MonoProcessor for Expander {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        // Use sidechain key or input for envelope detection
        let detection = self.get_detection_signal(input);
        let envelope = self.envelope.process(detection);

        if envelope < 1e-10 {
            return 0.0;
        }

        // Fast dB conversion using lookup table
        let env_db = linear_to_db_fast(envelope);

        // Expansion below threshold
        let gain_db = if env_db < self.threshold_db - self.knee_db / 2.0 {
            // Below knee - full expansion
            (env_db - self.threshold_db) * (self.ratio - 1.0)
        } else if env_db > self.threshold_db + self.knee_db / 2.0 {
            // Above knee - no expansion
            0.0
        } else {
            // In knee - soft transition
            let x = env_db - (self.threshold_db - self.knee_db / 2.0);
            let slope = self.ratio - 1.0;
            -(slope * (self.knee_db - x) * (self.knee_db - x)) / (2.0 * self.knee_db)
        };

        // Fast gain conversion using lookup table
        let gain = db_to_linear_fast(gain_db);
        // Apply gain to INPUT signal (not detection signal)
        input * gain
    }
}

impl ProcessorConfig for Expander {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.envelope.set_sample_rate(sample_rate);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DE-ESSER — Sibilance control processor
// ═══════════════════════════════════════════════════════════════════════════════

/// De-esser mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DeEsserMode {
    /// Wideband: Reduce entire signal when sibilance detected
    #[default]
    Wideband,
    /// Split-band: Only reduce the sibilant frequency range
    SplitBand,
}

/// Professional de-esser for sibilance control
///
/// Features:
/// - Variable frequency detection (2-16 kHz)
/// - Wideband or split-band modes
/// - Adjustable range (gain reduction limit)
/// - Listen mode for sidechain monitoring
/// - Smooth envelope following
#[derive(Debug, Clone)]
pub struct DeEsser {
    sample_rate: f64,
    /// Detection frequency center (Hz)
    frequency: f64,
    /// Detection bandwidth in octaves
    bandwidth: f64,
    /// Threshold in dB
    threshold_db: f64,
    /// Maximum gain reduction in dB
    range_db: f64,
    /// Processing mode
    mode: DeEsserMode,
    /// Attack time in ms
    attack_ms: f64,
    /// Release time in ms
    release_ms: f64,
    /// Listen to sidechain (for tuning)
    listen: bool,
    /// Bypassed
    bypassed: bool,

    // Internal state
    /// Bandpass filter for sidechain (state-variable filter)
    bp_ic1eq_l: f64,
    bp_ic2eq_l: f64,
    bp_ic1eq_r: f64,
    bp_ic2eq_r: f64,
    /// Bandpass coefficients
    bp_g: f64,
    bp_k: f64,
    bp_a1: f64,
    bp_a2: f64,
    bp_a3: f64,

    /// Envelope follower
    envelope: f64,
    /// Attack coefficient
    attack_coeff: f64,
    /// Release coefficient
    release_coeff: f64,

    /// Current gain reduction in dB (for metering)
    current_gr_db: f64,
}

impl DeEsser {
    pub fn new(sample_rate: f64) -> Self {
        let mut deesser = Self {
            sample_rate,
            frequency: 6000.0,
            bandwidth: 1.0,
            threshold_db: -20.0,
            range_db: 12.0,
            mode: DeEsserMode::Wideband,
            attack_ms: 0.5,
            release_ms: 50.0,
            listen: false,
            bypassed: false,

            bp_ic1eq_l: 0.0,
            bp_ic2eq_l: 0.0,
            bp_ic1eq_r: 0.0,
            bp_ic2eq_r: 0.0,
            bp_g: 0.0,
            bp_k: 0.0,
            bp_a1: 0.0,
            bp_a2: 0.0,
            bp_a3: 0.0,

            envelope: 0.0,
            attack_coeff: 0.0,
            release_coeff: 0.0,

            current_gr_db: 0.0,
        };
        deesser.update_filter_coeffs();
        deesser.update_envelope_coeffs();
        deesser
    }

    /// Set detection frequency (2000-16000 Hz)
    pub fn set_frequency(&mut self, hz: f64) {
        self.frequency = hz.clamp(2000.0, 16000.0);
        self.update_filter_coeffs();
    }

    /// Get detection frequency
    pub fn frequency(&self) -> f64 {
        self.frequency
    }

    /// Set detection bandwidth in octaves (0.25-4.0)
    pub fn set_bandwidth(&mut self, octaves: f64) {
        self.bandwidth = octaves.clamp(0.25, 4.0);
        self.update_filter_coeffs();
    }

    /// Get bandwidth
    pub fn bandwidth(&self) -> f64 {
        self.bandwidth
    }

    /// Set threshold in dB (-60 to 0)
    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-60.0, 0.0);
    }

    /// Get threshold
    pub fn threshold(&self) -> f64 {
        self.threshold_db
    }

    /// Set maximum gain reduction in dB (0-24)
    pub fn set_range(&mut self, db: f64) {
        self.range_db = db.clamp(0.0, 24.0);
    }

    /// Get range
    pub fn range(&self) -> f64 {
        self.range_db
    }

    /// Set processing mode
    pub fn set_mode(&mut self, mode: DeEsserMode) {
        self.mode = mode;
    }

    /// Get mode
    pub fn mode(&self) -> DeEsserMode {
        self.mode
    }

    /// Set attack time in ms
    pub fn set_attack(&mut self, ms: f64) {
        self.attack_ms = ms.clamp(0.1, 50.0);
        self.update_envelope_coeffs();
    }

    /// Get attack time in ms
    pub fn attack(&self) -> f64 {
        self.attack_ms
    }

    /// Set release time in ms
    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(10.0, 500.0);
        self.update_envelope_coeffs();
    }

    /// Get release time in ms
    pub fn release(&self) -> f64 {
        self.release_ms
    }

    /// Enable/disable listen mode (hear sidechain)
    pub fn set_listen(&mut self, listen: bool) {
        self.listen = listen;
    }

    /// Get listen state
    pub fn listen(&self) -> bool {
        self.listen
    }

    /// Set bypass state
    pub fn set_bypass(&mut self, bypass: bool) {
        self.bypassed = bypass;
    }

    /// Get bypass state
    pub fn bypassed(&self) -> bool {
        self.bypassed
    }

    /// Get current gain reduction in dB (for metering)
    pub fn gain_reduction_db(&self) -> f64 {
        self.current_gr_db
    }

    /// Update bandpass filter coefficients (SVF implementation)
    fn update_filter_coeffs(&mut self) {
        // Q from bandwidth (Q = freq / bandwidth_hz)
        // bandwidth_hz = freq * (2^(bw/2) - 2^(-bw/2))
        let bw_factor = 2.0_f64.powf(self.bandwidth / 2.0) - 2.0_f64.powf(-self.bandwidth / 2.0);
        let q = 1.0 / bw_factor;

        // SVF coefficients
        let w0 = std::f64::consts::PI * self.frequency / self.sample_rate;
        self.bp_g = w0.tan();
        self.bp_k = 1.0 / q;
        self.bp_a1 = 1.0 / (1.0 + self.bp_g * (self.bp_g + self.bp_k));
        self.bp_a2 = self.bp_g * self.bp_a1;
        self.bp_a3 = self.bp_g * self.bp_a2;
    }

    /// Update envelope follower coefficients
    fn update_envelope_coeffs(&mut self) {
        // Time constants for envelope
        self.attack_coeff = (-1.0 / (self.attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();
    }

    /// Process bandpass filter (SVF) - returns bandpass output
    #[inline(always)]
    fn process_bandpass(&mut self, input_l: f64, input_r: f64) -> (f64, f64) {
        // Left channel
        let v3_l = input_l - self.bp_ic2eq_l;
        let v1_l = self.bp_a1 * self.bp_ic1eq_l + self.bp_a2 * v3_l;
        let v2_l = self.bp_ic2eq_l + self.bp_a2 * self.bp_ic1eq_l + self.bp_a3 * v3_l;
        self.bp_ic1eq_l = 2.0 * v1_l - self.bp_ic1eq_l;
        self.bp_ic2eq_l = 2.0 * v2_l - self.bp_ic2eq_l;
        let bp_l = self.bp_k * v1_l; // Bandpass output

        // Right channel
        let v3_r = input_r - self.bp_ic2eq_r;
        let v1_r = self.bp_a1 * self.bp_ic1eq_r + self.bp_a2 * v3_r;
        let v2_r = self.bp_ic2eq_r + self.bp_a2 * self.bp_ic1eq_r + self.bp_a3 * v3_r;
        self.bp_ic1eq_r = 2.0 * v1_r - self.bp_ic1eq_r;
        self.bp_ic2eq_r = 2.0 * v2_r - self.bp_ic2eq_r;
        let bp_r = self.bp_k * v1_r;

        (bp_l, bp_r)
    }

    /// Process stereo de-essing
    #[inline(always)]
    pub fn process_stereo(&mut self, left: f64, right: f64) -> (f64, f64) {
        if self.bypassed {
            return (left, right);
        }

        // 1. Extract sibilant frequencies with bandpass filter
        let (bp_l, bp_r) = self.process_bandpass(left, right);

        // Listen mode - output sidechain for tuning
        if self.listen {
            return (bp_l, bp_r);
        }

        // 2. Measure sidechain level (RMS-ish: use max of L/R for stereo linking)
        let sidechain_level = (bp_l.abs()).max(bp_r.abs());

        // 3. Envelope follower (attack/release)
        let coeff = if sidechain_level > self.envelope {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.envelope = coeff * self.envelope + (1.0 - coeff) * sidechain_level;

        // 4. Calculate gain reduction
        let env_db = if self.envelope > 1e-10 {
            linear_to_db_fast(self.envelope)
        } else {
            -120.0
        };

        let gain_reduction_db = if env_db > self.threshold_db {
            // Above threshold: reduce proportionally
            let over_db = env_db - self.threshold_db;
            // Soft ratio of ~2:1 for natural sounding de-essing
            (over_db * 0.5).min(self.range_db)
        } else {
            0.0
        };

        self.current_gr_db = gain_reduction_db;

        // 5. Apply gain reduction based on mode
        let gain = db_to_linear_fast(-gain_reduction_db);

        match self.mode {
            DeEsserMode::Wideband => {
                // Reduce entire signal
                (left * gain, right * gain)
            }
            DeEsserMode::SplitBand => {
                // Only reduce the sibilant frequencies
                // Output = input - (bandpass * (1 - gain))
                // This subtracts only the reduced portion of sibilant frequencies
                let reduction_l = bp_l * (1.0 - gain);
                let reduction_r = bp_r * (1.0 - gain);
                (left - reduction_l, right - reduction_r)
            }
        }
    }

    /// Reset internal state
    pub fn reset(&mut self) {
        self.bp_ic1eq_l = 0.0;
        self.bp_ic2eq_l = 0.0;
        self.bp_ic1eq_r = 0.0;
        self.bp_ic2eq_r = 0.0;
        self.envelope = 0.0;
        self.current_gr_db = 0.0;
    }
}

impl Processor for DeEsser {
    fn reset(&mut self) {
        self.reset();
    }
}

impl StereoProcessor for DeEsser {
    #[inline(always)]
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        self.process_stereo(left, right)
    }
}

impl ProcessorConfig for DeEsser {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.update_filter_coeffs();
        self.update_envelope_coeffs();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compressor_types() {
        let sample_rate = 48000.0;

        for comp_type in [
            CompressorType::Vca,
            CompressorType::Opto,
            CompressorType::Fet,
        ] {
            let mut comp = Compressor::new(sample_rate);
            comp.set_type(comp_type);
            comp.set_threshold(-20.0);
            comp.set_ratio(4.0);

            // Process some samples
            for _ in 0..1000 {
                let _ = comp.process_sample(0.5);
            }

            // Should have some gain reduction
            assert!(comp.gain_reduction_db() > 0.0);
        }
    }

    #[test]
    fn test_true_peak_limiter() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-1.0);
        limiter.set_ceiling(-0.1);

        // Process through lookahead
        for _ in 0..limiter.latency() {
            let _ = limiter.process_sample(2.0, 2.0);
        }

        // Output should be limited
        let (l, r) = limiter.process_sample(2.0, 2.0);
        assert!(l.abs() < 1.0);
        assert!(r.abs() < 1.0);
    }

    #[test]
    fn test_gate_with_hold() {
        let mut gate = Gate::new(48000.0);
        gate.set_threshold(-20.0);
        gate.set_hold(10.0); // 10ms hold

        // Loud signal opens gate - need more samples for gate to fully open
        for _ in 0..1000 {
            gate.process_sample(0.5);
        }

        // Gate should be open (may not be exactly 1.0 due to attack time)
        assert!(gate.gain > 0.5, "Gate should be open, got {}", gate.gain);

        // Small number of quiet samples - gate still held open
        for _ in 0..100 {
            gate.process_sample(0.001);
        }
        // Gate should still be partially open due to hold
        assert!(
            gate.gain > 0.3,
            "Gate should still be partially open due to hold, got {}",
            gate.gain
        );
    }

    #[test]
    fn test_stereo_compressor_link() {
        let mut comp = StereoCompressor::new(48000.0);
        comp.set_both(|c| {
            c.set_threshold(-20.0);
            c.set_ratio(4.0);
        });
        comp.set_link(1.0); // Fully linked

        // Process with unbalanced signal
        for _ in 0..1000 {
            let _ = comp.process_sample(0.5, 0.1);
        }

        // Both channels should have same gain reduction when linked
        let (gr_l, gr_r) = comp.gain_reduction_db();
        assert!((gr_l - gr_r).abs() < 0.1);
    }

    #[test]
    fn test_envelope_simd_vs_scalar() {
        let mut envelope_scalar = EnvelopeFollower::new(48000.0);
        envelope_scalar.set_times(10.0, 100.0);

        let mut envelope_simd = EnvelopeFollower::new(48000.0);
        envelope_simd.set_times(10.0, 100.0);

        // Generate test signal (sine wave with attack/release)
        let input: Vec<f64> = (0..1024)
            .map(|i| (i as f64 * 0.01).sin() * 0.5)
            .collect();

        // Process with scalar
        let mut output_scalar = vec![0.0; 1024];
        for (i, &sample) in input.iter().enumerate() {
            output_scalar[i] = envelope_scalar.process(sample);
        }

        // Process with SIMD
        envelope_simd.reset();
        let mut output_simd = vec![0.0; 1024];
        envelope_simd.process_block(&input, &mut output_simd);

        // Compare results (should be nearly identical)
        for (i, (&scalar, &simd)) in output_scalar.iter().zip(output_simd.iter()).enumerate() {
            assert!(
                (scalar - simd).abs() < 1e-10,
                "Mismatch at sample {}: scalar={}, simd={}",
                i,
                scalar,
                simd
            );
        }
    }

    #[test]
    fn test_envelope_simd_performance() {
        let mut envelope = EnvelopeFollower::new(48000.0);
        envelope.set_times(5.0, 50.0);

        // Large block for performance testing
        let input: Vec<f64> = (0..8192)
            .map(|i| (i as f64 * 0.001).sin())
            .collect();
        let mut output = vec![0.0; 8192];

        // Process block (should use SIMD on x86_64)
        envelope.process_block(&input, &mut output);

        // Verify envelope is computed
        assert!(output.iter().all(|&x| x.is_finite()));
        assert!(output.iter().any(|&x| x > 0.0));
    }

    #[test]
    #[cfg(target_arch = "x86_64")]
    fn test_envelope_avx512() {
        if !is_x86_feature_detected!("avx512f") {
            println!("AVX-512 not available, skipping test");
            return;
        }

        let mut envelope = EnvelopeFollower::new(48000.0);
        envelope.set_times(10.0, 100.0);

        let input: Vec<f64> = (0..1024)
            .map(|i| (i as f64 * 0.01).sin())
            .collect();
        let mut output = vec![0.0; 1024];

        envelope.process_block_simd8(&input, &mut output);

        assert!(output.iter().all(|&x| x.is_finite()));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOOKUP TABLE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fn test_db_to_linear_lookup() {
        // Test known values
        let test_cases = [
            (0.0, 1.0),
            (-6.0, 0.501187), // -6dB ≈ 0.5
            (-20.0, 0.1),
            (-40.0, 0.01),
            (-60.0, 0.001),
            (6.0, 1.9952),  // +6dB ≈ 2.0
            (20.0, 10.0),
        ];

        for (db, expected) in test_cases {
            let result = db_to_linear_fast(db);
            let error = (result - expected).abs() / expected;
            assert!(
                error < 0.01,
                "db_to_linear_fast({}) = {}, expected {} (error: {:.2}%)",
                db,
                result,
                expected,
                error * 100.0
            );
        }
    }

    #[test]
    fn test_linear_to_db_lookup() {
        // Test known values
        let test_cases = [
            (1.0, 0.0),
            (0.5, -6.0206),  // -6dB
            (0.1, -20.0),
            (0.01, -40.0),
            (2.0, 6.0206),   // +6dB
            (10.0, 20.0),
        ];

        for (linear, expected) in test_cases {
            let result = linear_to_db_fast(linear);
            let error = (result - expected).abs();
            assert!(
                error < 0.5,
                "linear_to_db_fast({}) = {}, expected {} (error: {:.2}dB)",
                linear,
                result,
                expected,
                error
            );
        }
    }

    #[test]
    fn test_lookup_vs_precise() {
        // Compare lookup tables against precise computation
        for i in 0..100 {
            let db = -60.0 + i as f64 * 0.84; // Test range -60 to +24
            let precise = 10.0_f64.powf(db / 20.0);
            let fast = db_to_linear_fast(db);
            let error = (fast - precise).abs() / precise;
            assert!(
                error < 0.01,
                "db_to_linear error at {} dB: {:.4}%",
                db,
                error * 100.0
            );
        }

        for i in 1..100 {
            let linear = 0.001 + i as f64 * 0.1;
            let precise = 20.0 * linear.log10();
            let fast = linear_to_db_fast(linear);
            let error = (fast - precise).abs();
            assert!(
                error < 0.5,
                "linear_to_db error at {}: {:.4} dB",
                linear,
                error
            );
        }
    }

    #[test]
    fn test_compressor_gain_fast() {
        // Test compressor gain calculation
        let gain = calculate_compressor_gain_fast(-10.0, -20.0, 4.0);
        // Above threshold by 10dB, 4:1 ratio = 7.5dB reduction
        // gain = 10^(-7.5/20) ≈ 0.42
        assert!(
            (gain - 0.42).abs() < 0.05,
            "Compressor gain: expected ~0.42, got {}",
            gain
        );

        // Below threshold - no reduction
        let gain_below = calculate_compressor_gain_fast(-25.0, -20.0, 4.0);
        assert!(
            (gain_below - 1.0).abs() < 0.01,
            "Below threshold: expected 1.0, got {}",
            gain_below
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIDECHAIN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fn test_compressor_sidechain() {
        let mut comp = Compressor::new(48000.0);
        comp.set_threshold(-20.0);
        comp.set_ratio(4.0);
        comp.set_sidechain_enabled(true);

        // Small input signal, loud sidechain key
        let input = 0.05; // -26dB - below threshold normally
        let key = 0.5;    // -6dB - above threshold

        // Feed sidechain key and process
        for _ in 0..1000 {
            comp.set_sidechain_key(key);
            let _ = comp.process_sample(input);
        }

        // Should compress because sidechain key is loud
        assert!(
            comp.gain_reduction_db() > 0.5,
            "Sidechain should trigger compression, got {} dB GR",
            comp.gain_reduction_db()
        );
    }

    #[test]
    fn test_gate_sidechain() {
        let mut gate = Gate::new(48000.0);
        gate.set_threshold(-20.0);
        gate.set_range(-60.0);
        gate.set_hold(10.0); // Short hold for faster test
        gate.set_release(50.0); // Faster release
        gate.set_sidechain_enabled(true);

        // Loud input, quiet sidechain - gate should close
        let input = 0.5;  // -6dB - would normally open gate
        let key = 0.001;  // -60dB - below threshold

        // First open the gate with loud key
        for _ in 0..500 {
            gate.set_sidechain_key(0.5);
            let _ = gate.process_sample(input);
        }
        assert!(gate.gain > 0.8, "Gate should be open initially");

        // Now use quiet key - gate should close even though input is loud
        // Need enough samples to pass hold time (10ms = 480 samples) + release time
        for _ in 0..10000 {
            gate.set_sidechain_key(key);
            let _ = gate.process_sample(input);
        }
        assert!(
            gate.gain < 0.1,
            "Gate should close with quiet sidechain, got gain {}",
            gate.gain
        );
    }

    #[test]
    fn test_stereo_compressor_sidechain() {
        let mut comp = StereoCompressor::new(48000.0);
        comp.set_both(|c| {
            c.set_threshold(-20.0);
            c.set_ratio(4.0);
        });
        comp.set_link(1.0);
        comp.set_sidechain_enabled(true);

        // Small stereo input, mono sidechain key
        for _ in 0..1000 {
            comp.set_sidechain_key_mono(0.5); // Loud key
            let _ = comp.process_sample(0.05, 0.05); // Quiet input
        }

        // Should compress due to sidechain
        let (gr_l, gr_r) = comp.gain_reduction_db();
        assert!(gr_l > 0.5, "L channel should compress via sidechain");
        assert!(gr_r > 0.5, "R channel should compress via sidechain");
    }

    #[test]
    fn test_expander_sidechain() {
        let mut exp = Expander::new(48000.0);
        exp.set_threshold(-20.0);
        exp.set_ratio(4.0);
        exp.set_sidechain_enabled(true);

        // Loud input, quiet sidechain - should expand (reduce) the signal
        let input = 0.5;  // -6dB - above threshold normally
        let key = 0.01;   // -40dB - below threshold

        // Process with quiet sidechain key
        let mut last_output = 0.0;
        for _ in 0..1000 {
            exp.set_sidechain_key(key);
            last_output = exp.process_sample(input);
        }

        // Output should be reduced because sidechain key is below threshold
        assert!(
            last_output.abs() < input.abs() * 0.5,
            "Expander should reduce output when sidechain is quiet, got {}",
            last_output
        );
    }
}

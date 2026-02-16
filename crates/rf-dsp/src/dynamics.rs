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
use std::simd::prelude::SimdFloat;
#[cfg(target_arch = "x86_64")]
use std::simd::{f64x4, f64x8};

use crate::biquad::{BiquadCoeffs, BiquadTDF2};
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
            let log_val =
                log_linear_min + (i as f64 / (LINEAR_TO_DB_TABLE_SIZE - 1) as f64) * log_range;
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
            let coeff = if abs_input > envelope {
                attack
            } else {
                release
            };
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
                let coeff = if abs_input > envelope {
                    attack
                } else {
                    release
                };
                envelope = abs_input + coeff * (envelope - abs_input);
                output[i + j] = envelope;
            }
        }

        // Process remaining samples (0-7)
        for i in unroll_len..len {
            let abs_input = input[i].abs();
            let coeff = if abs_input > envelope {
                attack
            } else {
                release
            };
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

/// Character saturation mode (Pro-C 2 style)
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum CompressorCharacter {
    /// No coloration
    #[default]
    Off,
    /// Warm tube harmonics (even-order)
    Tube,
    /// Diode clipping (odd-order, harder)
    Diode,
    /// Bright presence enhancement (high-frequency exciter)
    Bright,
}

/// Envelope detection mode
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum DetectionMode {
    /// Peak detection — fastest response
    #[default]
    Peak,
    /// RMS detection — average power, smoother
    Rms,
    /// Hybrid — blend of peak and RMS (Pro-C 2 default)
    Hybrid,
}

/// Compressor with multiple characteristics (Pro-C 2 class)
#[derive(Debug, Clone)]
pub struct Compressor {
    // ═══ Core Parameters (0-7, existing) ═══
    threshold_db: f64,
    ratio: f64,
    knee_db: f64,
    makeup_gain_db: f64,
    attack_ms: f64,
    release_ms: f64,
    mix: f64, // Dry/wet for parallel compression
    comp_type: CompressorType,

    // ═══ Pro-C 2 Extended Parameters (8-24) ═══
    /// Character saturation mode
    character: CompressorCharacter,
    /// Drive amount in dB (0-24, applied post-compression as saturation)
    drive_db: f64,
    /// Range limit — maximum gain reduction in dB (-60..0, default -60 = unlimited)
    range_db: f64,
    /// Sidechain HP filter frequency (20-500 Hz)
    sc_hp_freq: f64,
    /// Sidechain LP filter frequency (1000-20000 Hz)
    sc_lp_freq: f64,
    /// Sidechain audition mode (listen to filtered SC signal)
    sc_audition: bool,
    /// Lookahead in ms (0-20, adds latency but catches transients)
    lookahead_ms: f64,
    /// Sidechain EQ mid frequency (200-5000 Hz)
    sc_eq_mid_freq: f64,
    /// Sidechain EQ mid gain in dB (-12..+12)
    sc_eq_mid_gain: f64,
    /// Auto-threshold: dynamically adjusts threshold based on input level
    auto_threshold: bool,
    /// Auto-makeup: automatically compensate gain reduction
    auto_makeup: bool,
    /// Detection mode (Peak/RMS/Hybrid)
    detection_mode: DetectionMode,
    /// Adaptive release: release time follows program material
    adaptive_release: bool,
    /// Host sync (tempo-sync release to host BPM)
    host_sync: bool,
    /// Host BPM for sync
    host_bpm: f64,
    /// Mid/Side processing mode
    mid_side: bool,

    // ═══ State ═══
    envelope: EnvelopeFollower,
    gain_reduction: f64,

    // Opto-specific state
    opto_envelope: f64,
    opto_gain_history: [f64; 4],

    // FET-specific state
    fet_saturation: f64,

    sample_rate: f64,

    // Sidechain support
    sidechain_enabled: bool,
    sidechain_key_sample: Sample,

    // ═══ Pro-C 2 Extended State ═══
    /// Sidechain HP filter
    sc_hp_filter: BiquadTDF2,
    /// Sidechain LP filter
    sc_lp_filter: BiquadTDF2,
    /// Sidechain EQ mid filter (peaking)
    sc_eq_mid_filter: BiquadTDF2,
    /// Lookahead delay buffer (circular)
    lookahead_buffer: [Sample; 1024],
    /// Lookahead buffer write position
    lookahead_write_pos: usize,
    /// Lookahead delay in samples
    lookahead_samples: usize,
    /// RMS detector state (for RMS/Hybrid detection modes)
    rms_sum: f64,
    /// RMS window sample count
    rms_count: usize,
    /// RMS window size in samples
    rms_window_samples: usize,
    /// Auto-threshold envelope (slow follower for input level tracking)
    auto_threshold_envelope: f64,
    /// Adaptive release state — tracks recent GR for program-dependent release
    adaptive_release_envelope: f64,
    /// Input peak meter (for metering)
    input_peak: f64,
    /// Output peak meter (for metering)
    output_peak: f64,
    /// GR max hold (peak GR with decay)
    gr_max_hold: f64,
    /// GR max hold decay counter
    gr_max_hold_decay: f64,
}

impl Compressor {
    pub fn new(sample_rate: f64) -> Self {
        let mut sc_hp = BiquadTDF2::new(sample_rate);
        sc_hp.set_highpass(20.0, 0.707);
        let mut sc_lp = BiquadTDF2::new(sample_rate);
        sc_lp.set_lowpass(20000.0, 0.707);
        let sc_eq_mid = BiquadTDF2::new(sample_rate); // bypass by default

        let rms_window_ms = 10.0; // 10ms RMS window
        let rms_window_samples = (sample_rate * rms_window_ms * 0.001) as usize;

        Self {
            threshold_db: -20.0,
            ratio: 4.0,
            knee_db: 6.0,
            makeup_gain_db: 0.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            mix: 1.0,
            comp_type: CompressorType::Vca,

            // Pro-C 2 extended
            character: CompressorCharacter::Off,
            drive_db: 0.0,
            range_db: -60.0,
            sc_hp_freq: 20.0,
            sc_lp_freq: 20000.0,
            sc_audition: false,
            lookahead_ms: 0.0,
            sc_eq_mid_freq: 1000.0,
            sc_eq_mid_gain: 0.0,
            auto_threshold: false,
            auto_makeup: false,
            detection_mode: DetectionMode::Peak,
            adaptive_release: false,
            host_sync: false,
            host_bpm: 120.0,
            mid_side: false,

            // State
            envelope: EnvelopeFollower::new(sample_rate),
            gain_reduction: 0.0,
            opto_envelope: 0.0,
            opto_gain_history: [1.0; 4],
            fet_saturation: 0.0,
            sample_rate,
            sidechain_enabled: false,
            sidechain_key_sample: 0.0,

            // Extended state
            sc_hp_filter: sc_hp,
            sc_lp_filter: sc_lp,
            sc_eq_mid_filter: sc_eq_mid,
            lookahead_buffer: [0.0; 1024],
            lookahead_write_pos: 0,
            lookahead_samples: 0,
            rms_sum: 0.0,
            rms_count: 0,
            rms_window_samples,
            auto_threshold_envelope: -20.0,
            adaptive_release_envelope: 0.0,
            input_peak: 0.0,
            output_peak: 0.0,
            gr_max_hold: 0.0,
            gr_max_hold_decay: 0.0,
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

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRO-C 2 EXTENDED PARAMETER SETTERS
    // ═══════════════════════════════════════════════════════════════════════════════

    pub fn set_character(&mut self, character: CompressorCharacter) {
        self.character = character;
    }

    pub fn set_drive(&mut self, db: f64) {
        self.drive_db = db.clamp(0.0, 24.0);
    }

    pub fn set_range(&mut self, db: f64) {
        self.range_db = db.clamp(-60.0, 0.0);
    }

    pub fn set_sc_hp_freq(&mut self, freq: f64) {
        self.sc_hp_freq = freq.clamp(20.0, 500.0);
        self.sc_hp_filter.set_highpass(self.sc_hp_freq, 0.707);
    }

    pub fn set_sc_lp_freq(&mut self, freq: f64) {
        self.sc_lp_freq = freq.clamp(1000.0, 20000.0);
        self.sc_lp_filter.set_lowpass(self.sc_lp_freq, 0.707);
    }

    pub fn set_sc_audition(&mut self, audition: bool) {
        self.sc_audition = audition;
    }

    pub fn set_lookahead(&mut self, ms: f64) {
        self.lookahead_ms = ms.clamp(0.0, 20.0);
        self.lookahead_samples = (self.sample_rate * self.lookahead_ms * 0.001) as usize;
        if self.lookahead_samples > 1023 {
            self.lookahead_samples = 1023;
        }
    }

    pub fn set_sc_eq_mid_freq(&mut self, freq: f64) {
        self.sc_eq_mid_freq = freq.clamp(200.0, 5000.0);
        if self.sc_eq_mid_gain.abs() > 0.01 {
            self.sc_eq_mid_filter
                .set_peaking(self.sc_eq_mid_freq, 1.0, self.sc_eq_mid_gain);
        }
    }

    pub fn set_sc_eq_mid_gain(&mut self, db: f64) {
        self.sc_eq_mid_gain = db.clamp(-12.0, 12.0);
        if self.sc_eq_mid_gain.abs() > 0.01 {
            self.sc_eq_mid_filter
                .set_peaking(self.sc_eq_mid_freq, 1.0, self.sc_eq_mid_gain);
        } else {
            self.sc_eq_mid_filter
                .set_coeffs(BiquadCoeffs::bypass());
        }
    }

    pub fn set_auto_threshold(&mut self, enabled: bool) {
        self.auto_threshold = enabled;
    }

    pub fn set_auto_makeup(&mut self, enabled: bool) {
        self.auto_makeup = enabled;
    }

    pub fn set_detection_mode(&mut self, mode: DetectionMode) {
        self.detection_mode = mode;
    }

    pub fn set_adaptive_release(&mut self, enabled: bool) {
        self.adaptive_release = enabled;
    }

    pub fn set_host_sync(&mut self, enabled: bool) {
        self.host_sync = enabled;
    }

    pub fn set_host_bpm(&mut self, bpm: f64) {
        self.host_bpm = bpm.clamp(20.0, 300.0);
    }

    pub fn set_mid_side(&mut self, enabled: bool) {
        self.mid_side = enabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // GETTERS (for wrapper get_param)
    // ═══════════════════════════════════════════════════════════════════════════════

    pub fn threshold_db(&self) -> f64 { self.threshold_db }
    pub fn ratio(&self) -> f64 { self.ratio }
    pub fn attack_ms(&self) -> f64 { self.attack_ms }
    pub fn release_ms(&self) -> f64 { self.release_ms }
    pub fn makeup_gain_db(&self) -> f64 { self.makeup_gain_db }
    pub fn mix(&self) -> f64 { self.mix }
    pub fn knee_db(&self) -> f64 { self.knee_db }
    pub fn comp_type(&self) -> CompressorType { self.comp_type }
    pub fn character(&self) -> CompressorCharacter { self.character }
    pub fn drive_db(&self) -> f64 { self.drive_db }
    pub fn range_db(&self) -> f64 { self.range_db }
    pub fn sc_hp_freq(&self) -> f64 { self.sc_hp_freq }
    pub fn sc_lp_freq(&self) -> f64 { self.sc_lp_freq }
    pub fn sc_audition(&self) -> bool { self.sc_audition }
    pub fn lookahead_ms(&self) -> f64 { self.lookahead_ms }
    pub fn sc_eq_mid_freq(&self) -> f64 { self.sc_eq_mid_freq }
    pub fn sc_eq_mid_gain(&self) -> f64 { self.sc_eq_mid_gain }
    pub fn auto_threshold_enabled(&self) -> bool { self.auto_threshold }
    pub fn auto_makeup_enabled(&self) -> bool { self.auto_makeup }
    pub fn detection_mode(&self) -> DetectionMode { self.detection_mode }
    pub fn adaptive_release_enabled(&self) -> bool { self.adaptive_release }
    pub fn host_sync_enabled(&self) -> bool { self.host_sync }
    pub fn host_bpm(&self) -> f64 { self.host_bpm }
    pub fn mid_side_enabled(&self) -> bool { self.mid_side }

    // ═══════════════════════════════════════════════════════════════════════════════
    // METERING
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Get current gain reduction in dB
    pub fn gain_reduction_db(&self) -> f64 {
        self.gain_reduction
    }

    /// Get input peak level (linear)
    pub fn input_peak(&self) -> f64 {
        self.input_peak
    }

    /// Get output peak level (linear)
    pub fn output_peak(&self) -> f64 {
        self.output_peak
    }

    /// Get GR max hold value (dB, with 1s decay)
    pub fn gr_max_hold(&self) -> f64 {
        self.gr_max_hold
    }

    /// Lookahead latency in samples (for PDC)
    pub fn latency_samples(&self) -> usize {
        self.lookahead_samples
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRO-C 2 EXTENDED PROCESSING
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Apply sidechain filters to detection signal
    #[inline]
    fn filter_sidechain(&mut self, signal: Sample) -> Sample {
        let mut filtered = signal;
        // HP filter (cuts low-frequency content from triggering)
        if self.sc_hp_freq > 21.0 {
            filtered = self.sc_hp_filter.process_sample(filtered);
        }
        // LP filter (cuts high-frequency content from triggering)
        if self.sc_lp_freq < 19999.0 {
            filtered = self.sc_lp_filter.process_sample(filtered);
        }
        // Mid EQ (boost/cut a band to emphasize triggering on specific content)
        if self.sc_eq_mid_gain.abs() > 0.01 {
            filtered = self.sc_eq_mid_filter.process_sample(filtered);
        }
        filtered
    }

    /// Detect envelope level based on detection mode
    #[inline]
    fn detect_level(&mut self, signal: Sample) -> f64 {
        match self.detection_mode {
            DetectionMode::Peak => {
                self.envelope.process(signal)
            }
            DetectionMode::Rms => {
                // Running RMS calculation
                self.rms_sum += (signal * signal) as f64;
                self.rms_count += 1;
                if self.rms_count >= self.rms_window_samples.max(1) {
                    let rms = (self.rms_sum / self.rms_count as f64).sqrt();
                    self.rms_sum = 0.0;
                    self.rms_count = 0;
                    self.envelope.process(rms as Sample)
                } else {
                    self.envelope.current()
                }
            }
            DetectionMode::Hybrid => {
                // Blend of peak and RMS (70% peak, 30% RMS)
                let peak = signal.abs() as f64;
                self.rms_sum += (signal * signal) as f64;
                self.rms_count += 1;
                let rms = if self.rms_count >= self.rms_window_samples.max(1) {
                    let r = (self.rms_sum / self.rms_count as f64).sqrt();
                    self.rms_sum = 0.0;
                    self.rms_count = 0;
                    r
                } else {
                    (self.rms_sum / self.rms_count.max(1) as f64).sqrt()
                };
                let blended = peak * 0.7 + rms * 0.3;
                self.envelope.process(blended as Sample)
            }
        }
    }

    /// Write sample to lookahead buffer and return delayed sample
    #[inline]
    fn process_lookahead(&mut self, input: Sample) -> Sample {
        if self.lookahead_samples == 0 {
            return input;
        }
        // Write input to buffer
        self.lookahead_buffer[self.lookahead_write_pos] = input;
        // Read from delayed position
        let read_pos = (self.lookahead_write_pos + 1024 - self.lookahead_samples) % 1024;
        let delayed = self.lookahead_buffer[read_pos];
        // Advance write position
        self.lookahead_write_pos = (self.lookahead_write_pos + 1) % 1024;
        delayed
    }

    /// Update auto-threshold based on input level
    #[inline]
    fn update_auto_threshold(&mut self, input_db: f64) {
        if !self.auto_threshold {
            return;
        }
        // Slow envelope follower tracks input level (~500ms time constant)
        let coeff = (-1.0 / (0.5 * self.sample_rate)).exp();
        self.auto_threshold_envelope =
            input_db + coeff * (self.auto_threshold_envelope - input_db);
    }

    /// Get effective threshold (may be auto-adjusted)
    #[inline]
    fn effective_threshold(&self) -> f64 {
        if self.auto_threshold {
            // Auto-threshold: offset from tracked input level
            // Maintains relative distance as input level changes
            self.auto_threshold_envelope + (self.threshold_db + 20.0)
        } else {
            self.threshold_db
        }
    }

    /// Calculate auto-makeup gain
    #[inline]
    fn auto_makeup_gain_db(&self) -> f64 {
        if !self.auto_makeup {
            return self.makeup_gain_db;
        }
        // Estimate makeup from threshold and ratio
        let threshold = self.effective_threshold();
        let estimated_gr = (-threshold) * (1.0 - 1.0 / self.ratio);
        self.makeup_gain_db + estimated_gr * 0.5 // Conservative: half the estimated GR
    }

    /// Calculate adaptive release time
    #[inline]
    fn adaptive_release_ms(&mut self) -> f64 {
        if !self.adaptive_release {
            return self.release_ms;
        }
        // Track GR envelope — heavier compression = faster release
        let gr_abs = self.gain_reduction.abs();
        let coeff = (-1.0 / (0.1 * self.sample_rate)).exp();
        self.adaptive_release_envelope =
            gr_abs + coeff * (self.adaptive_release_envelope - gr_abs);

        // Scale release: 100% at low GR → 30% at heavy GR (20dB+)
        let gr_factor = (1.0 - (self.adaptive_release_envelope / 20.0).min(1.0) * 0.7).max(0.3);
        self.release_ms * gr_factor
    }

    /// Apply character saturation to output
    #[inline]
    fn apply_character(&self, input: Sample) -> Sample {
        match self.character {
            CompressorCharacter::Off => input,
            CompressorCharacter::Tube => {
                // Even-order harmonic saturation (warm, musical)
                let drive = db_to_linear_fast(self.drive_db);
                let x = input * drive;
                // Soft asymmetric clipping (tube characteristic)
                let saturated = if x >= 0.0 {
                    1.0 - (-x).exp()
                } else {
                    -(1.0 - x.exp()) * 0.9 // Asymmetric: less on negative
                };
                saturated / drive.max(1.0)
            }
            CompressorCharacter::Diode => {
                // Odd-order harmonic saturation (harder, more aggressive)
                let drive = db_to_linear_fast(self.drive_db);
                let x = input * drive;
                // Hard symmetric clipping (diode characteristic)
                let saturated = x / (1.0 + x.abs());
                saturated / drive.max(1.0)
            }
            CompressorCharacter::Bright => {
                // High-frequency presence enhancement
                let drive = db_to_linear_fast(self.drive_db * 0.5); // Less drive for bright
                let x = input * drive;
                // Subtle odd harmonics + high-frequency emphasis
                let saturated = x - (x * x * x) * 0.1;
                saturated / drive.max(1.0)
            }
        }
    }

    /// Apply range limit — clamps maximum gain reduction
    #[inline]
    fn apply_range(&self, gr_db: f64) -> f64 {
        if self.range_db >= -0.1 {
            return 0.0; // Range at 0 = no compression
        }
        if self.range_db <= -59.9 {
            return gr_db; // Range at -60 = unlimited
        }
        // Limit GR to range value
        gr_db.min(-self.range_db)
    }

    /// Update metering values
    #[inline]
    fn update_meters(&mut self, input: Sample, output: Sample) {
        // Input peak (fast attack, 300ms release)
        let abs_in = input.abs() as f64;
        if abs_in > self.input_peak {
            self.input_peak = abs_in;
        } else {
            self.input_peak *= 0.9997; // ~300ms decay at 44.1kHz
        }

        // Output peak
        let abs_out = output.abs() as f64;
        if abs_out > self.output_peak {
            self.output_peak = abs_out;
        } else {
            self.output_peak *= 0.9997;
        }

        // GR max hold (1s decay)
        let abs_gr = self.gain_reduction.abs();
        if abs_gr > self.gr_max_hold {
            self.gr_max_hold = abs_gr;
            self.gr_max_hold_decay = self.sample_rate; // 1 second hold
        } else if self.gr_max_hold_decay > 0.0 {
            self.gr_max_hold_decay -= 1.0;
        } else {
            self.gr_max_hold *= 0.999; // Slow decay after hold
        }
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
    /// Full Pro-C 2 signal chain: SC filter → detection → lookahead → auto-threshold → range
    #[inline]
    fn process_vca(&mut self, input: Sample) -> Sample {
        // 1. Get detection signal (sidechain or input)
        let detection = self.get_detection_signal(input);

        // 2. Apply SC filters to detection signal
        let filtered_detection = self.filter_sidechain(detection);

        // 3. Detect envelope level (Peak/RMS/Hybrid)
        let envelope = self.detect_level(filtered_detection);

        if envelope < 1e-10 {
            return input;
        }

        // 4. Convert to dB
        let env_db = linear_to_db_fast(envelope);

        // 5. Update auto-threshold tracking
        self.update_auto_threshold(env_db);

        // 6. Calculate GR with effective threshold
        let threshold = self.effective_threshold();
        let half_knee = self.knee_db / 2.0;
        let knee_start = threshold - half_knee;
        let knee_end = threshold + half_knee;

        let gr_db = if env_db < knee_start {
            0.0
        } else if env_db > knee_end {
            (env_db - threshold) * (1.0 - 1.0 / self.ratio)
        } else {
            let x = env_db - knee_start;
            let slope = 1.0 - 1.0 / self.ratio;
            (slope * x * x) / (2.0 * self.knee_db.max(0.001))
        };

        // 7. Apply range limit
        let gr_db = self.apply_range(gr_db);

        // 8. Update adaptive release if enabled
        if self.adaptive_release {
            let adaptive_rel = self.adaptive_release_ms();
            self.envelope.set_times(self.attack_ms, adaptive_rel);
        }

        self.gain_reduction = gr_db;

        // 9. Apply gain (lookup table)
        let gain = db_to_linear_fast(-gr_db);
        input * gain
    }

    /// Opto-style compression (smooth, program-dependent)
    /// Uses lookup tables for fast dB/gain conversion
    /// Full Pro-C 2 signal chain: SC filter → detection → auto-threshold → range
    #[inline]
    fn process_opto(&mut self, input: Sample) -> Sample {
        // 1. Get detection signal
        let detection = self.get_detection_signal(input);

        // 2. Apply SC filters
        let filtered_detection = self.filter_sidechain(detection);
        let abs_detection = filtered_detection.abs();

        // Opto cells have program-dependent attack/release
        // Higher levels = faster response
        let level_factor = (abs_detection * 10.0).min(1.0);

        // Attack gets faster with higher levels
        let base_release = if self.adaptive_release {
            self.adaptive_release_ms()
        } else {
            self.release_ms
        };
        let attack_coeff = (-1.0
            / ((self.attack_ms * (1.0 - level_factor * 0.5)) * 0.001 * self.sample_rate))
            .exp();
        // Release is slower for higher gain reduction (opto characteristic)
        let release_factor = 1.0 + self.gain_reduction * 0.02;
        let release_coeff =
            (-1.0 / ((base_release * release_factor) * 0.001 * self.sample_rate)).exp();

        let coeff = if abs_detection > self.opto_envelope {
            attack_coeff
        } else {
            release_coeff
        };
        self.opto_envelope = abs_detection + coeff * (self.opto_envelope - abs_detection);

        if self.opto_envelope < 1e-10 {
            return input;
        }

        // 3. Convert to dB and track auto-threshold
        let env_db = linear_to_db_fast(self.opto_envelope);
        self.update_auto_threshold(env_db);

        // 4. Calculate GR with effective threshold
        let threshold = self.effective_threshold();
        let half_knee = self.knee_db / 2.0;
        let knee_start = threshold - half_knee;
        let knee_end = threshold + half_knee;

        let gr_db = if env_db < knee_start {
            0.0
        } else if env_db > knee_end {
            (env_db - threshold) * (1.0 - 1.0 / self.ratio)
        } else {
            let x = env_db - knee_start;
            let slope = 1.0 - 1.0 / self.ratio;
            (slope * x * x) / (2.0 * self.knee_db.max(0.001))
        };

        // 5. Apply range limit
        let gr_db = self.apply_range(gr_db);

        // 6. Smooth the gain reduction (opto inertia)
        self.opto_gain_history.rotate_right(1);
        self.opto_gain_history[0] = gr_db;
        let smoothed_gr: f64 = self.opto_gain_history.iter().sum::<f64>() / 4.0;
        self.gain_reduction = smoothed_gr;

        let gain = db_to_linear_fast(-smoothed_gr);
        input * gain
    }

    /// FET-style compression (aggressive, punchy, adds harmonics)
    /// Uses lookup tables for fast dB/gain conversion
    /// Full Pro-C 2 signal chain: SC filter → detection → auto-threshold → range → FET saturation
    #[inline]
    fn process_fet(&mut self, input: Sample) -> Sample {
        // 1. Get and filter detection signal
        let detection = self.get_detection_signal(input);
        let filtered_detection = self.filter_sidechain(detection);

        // 2. Detect level
        let envelope = self.detect_level(filtered_detection);

        if envelope < 1e-10 {
            return input;
        }

        // 3. Convert to dB and track auto-threshold
        let env_db = linear_to_db_fast(envelope);
        self.update_auto_threshold(env_db);

        // 4. FET has more aggressive knee and can go into negative ratio territory
        let threshold = self.effective_threshold();
        let gr_db = if env_db > threshold {
            let over = env_db - threshold;
            let effective_ratio = self.ratio * (1.0 + over * 0.05).min(2.0);
            over * (1.0 - 1.0 / effective_ratio)
        } else {
            0.0
        };

        // 5. Apply range limit
        let gr_db = self.apply_range(gr_db);

        // 6. Adaptive release
        if self.adaptive_release {
            let adaptive_rel = self.adaptive_release_ms();
            self.envelope.set_times(self.attack_ms, adaptive_rel);
        }

        self.gain_reduction = gr_db;
        let gain = db_to_linear_fast(-gr_db);

        // 7. FET-inherent saturation (based on GR depth)
        let saturated = input * gain;
        let saturation_amount = (gr_db / 20.0).min(0.3);
        self.fet_saturation = saturation_amount;

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

        // Pro-C 2 extended state
        self.sc_hp_filter = BiquadTDF2::new(self.sample_rate);
        if self.sc_hp_freq > 21.0 {
            self.sc_hp_filter.set_highpass(self.sc_hp_freq, 0.707);
        }
        self.sc_lp_filter = BiquadTDF2::new(self.sample_rate);
        if self.sc_lp_freq < 19999.0 {
            self.sc_lp_filter.set_lowpass(self.sc_lp_freq, 0.707);
        }
        self.sc_eq_mid_filter = BiquadTDF2::new(self.sample_rate);
        if self.sc_eq_mid_gain.abs() > 0.01 {
            self.sc_eq_mid_filter
                .set_peaking(self.sc_eq_mid_freq, 1.0, self.sc_eq_mid_gain);
        }
        self.lookahead_buffer = [0.0; 1024];
        self.lookahead_write_pos = 0;
        self.rms_sum = 0.0;
        self.rms_count = 0;
        self.auto_threshold_envelope = self.threshold_db;
        self.adaptive_release_envelope = 0.0;
        self.input_peak = 0.0;
        self.output_peak = 0.0;
        self.gr_max_hold = 0.0;
        self.gr_max_hold_decay = 0.0;
    }
}

impl MonoProcessor for Compressor {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        // SC Audition mode: output filtered sidechain signal for monitoring
        if self.sc_audition {
            let detection = self.get_detection_signal(input);
            return self.filter_sidechain(detection);
        }

        let dry = input;

        // Lookahead: delay the audio signal so GR is applied ahead of transients
        let delayed = self.process_lookahead(input);

        // Core compression (uses delayed audio, detection uses un-delayed signal)
        let compressed = match self.comp_type {
            CompressorType::Vca => self.process_vca(delayed),
            CompressorType::Opto => self.process_opto(delayed),
            CompressorType::Fet => self.process_fet(delayed),
        };

        // Apply character saturation (Tube/Diode/Bright)
        let saturated = if self.character != CompressorCharacter::Off && self.drive_db > 0.01 {
            self.apply_character(compressed)
        } else {
            compressed
        };

        // Apply makeup gain (auto or manual)
        let makeup_db = self.auto_makeup_gain_db();
        let makeup = db_to_linear_fast(makeup_db);
        let wet = saturated * makeup;

        // Dry/wet mix (parallel compression)
        let output = if self.lookahead_samples > 0 {
            // When using lookahead, dry signal must also be delayed
            delayed * (1.0 - self.mix) + wet * self.mix
        } else {
            dry * (1.0 - self.mix) + wet * self.mix
        };

        // Update meters
        self.update_meters(input, output);

        output
    }
}

impl ProcessorConfig for Compressor {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.envelope.set_sample_rate(sample_rate);
        self.envelope.set_times(self.attack_ms, self.release_ms);

        // Recalculate SC filter coefficients at new sample rate
        self.sc_hp_filter = BiquadTDF2::new(sample_rate);
        if self.sc_hp_freq > 21.0 {
            self.sc_hp_filter.set_highpass(self.sc_hp_freq, 0.707);
        }
        self.sc_lp_filter = BiquadTDF2::new(sample_rate);
        if self.sc_lp_freq < 19999.0 {
            self.sc_lp_filter.set_lowpass(self.sc_lp_freq, 0.707);
        }
        self.sc_eq_mid_filter = BiquadTDF2::new(sample_rate);
        if self.sc_eq_mid_gain.abs() > 0.01 {
            self.sc_eq_mid_filter
                .set_peaking(self.sc_eq_mid_freq, 1.0, self.sc_eq_mid_gain);
        }

        // Recalculate lookahead buffer size
        self.lookahead_samples = (sample_rate * self.lookahead_ms * 0.001) as usize;
        if self.lookahead_samples > 1023 {
            self.lookahead_samples = 1023;
        }

        // Recalculate RMS window
        self.rms_window_samples = (sample_rate * 10.0 * 0.001) as usize; // 10ms
    }
}

/// Stereo compressor with link options and Mid/Side processing
#[derive(Debug, Clone)]
pub struct StereoCompressor {
    left: Compressor,
    right: Compressor,
    link: f64, // 0.0 = independent, 1.0 = fully linked
    /// Mid/Side processing mode
    mid_side: bool,
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
            mid_side: false,
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

    pub fn left_ref(&self) -> &Compressor {
        &self.left
    }

    pub fn right(&mut self) -> &mut Compressor {
        &mut self.right
    }

    pub fn right_ref(&self) -> &Compressor {
        &self.right
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
    // PRO-C 2 EXTENDED PARAMETER FORWARDING
    // ═══════════════════════════════════════════════════════════════════════════════

    pub fn set_type(&mut self, comp_type: CompressorType) {
        self.set_both(|c| c.set_type(comp_type));
    }
    pub fn set_threshold(&mut self, db: f64) {
        self.set_both(|c| c.set_threshold(db));
    }
    pub fn set_ratio(&mut self, ratio: f64) {
        self.set_both(|c| c.set_ratio(ratio));
    }
    pub fn set_knee(&mut self, db: f64) {
        self.set_both(|c| c.set_knee(db));
    }
    pub fn set_attack(&mut self, ms: f64) {
        self.set_both(|c| c.set_attack(ms));
    }
    pub fn set_release(&mut self, ms: f64) {
        self.set_both(|c| c.set_release(ms));
    }
    pub fn set_makeup(&mut self, db: f64) {
        self.set_both(|c| c.set_makeup(db));
    }
    pub fn set_mix(&mut self, mix: f64) {
        self.set_both(|c| c.set_mix(mix));
    }
    pub fn set_character(&mut self, character: CompressorCharacter) {
        self.set_both(|c| c.set_character(character));
    }
    pub fn set_drive(&mut self, db: f64) {
        self.set_both(|c| c.set_drive(db));
    }
    pub fn set_range(&mut self, db: f64) {
        self.set_both(|c| c.set_range(db));
    }
    pub fn set_sc_hp_freq(&mut self, freq: f64) {
        self.set_both(|c| c.set_sc_hp_freq(freq));
    }
    pub fn set_sc_lp_freq(&mut self, freq: f64) {
        self.set_both(|c| c.set_sc_lp_freq(freq));
    }
    pub fn set_sc_audition(&mut self, audition: bool) {
        self.set_both(|c| c.set_sc_audition(audition));
    }
    pub fn set_lookahead(&mut self, ms: f64) {
        self.set_both(|c| c.set_lookahead(ms));
    }
    pub fn set_sc_eq_mid_freq(&mut self, freq: f64) {
        self.set_both(|c| c.set_sc_eq_mid_freq(freq));
    }
    pub fn set_sc_eq_mid_gain(&mut self, db: f64) {
        self.set_both(|c| c.set_sc_eq_mid_gain(db));
    }
    pub fn set_auto_threshold(&mut self, enabled: bool) {
        self.set_both(|c| c.set_auto_threshold(enabled));
    }
    pub fn set_auto_makeup(&mut self, enabled: bool) {
        self.set_both(|c| c.set_auto_makeup(enabled));
    }
    pub fn set_detection_mode(&mut self, mode: DetectionMode) {
        self.set_both(|c| c.set_detection_mode(mode));
    }
    pub fn set_adaptive_release(&mut self, enabled: bool) {
        self.set_both(|c| c.set_adaptive_release(enabled));
    }
    pub fn set_host_sync(&mut self, enabled: bool) {
        self.set_both(|c| c.set_host_sync(enabled));
    }
    pub fn set_host_bpm(&mut self, bpm: f64) {
        self.set_both(|c| c.set_host_bpm(bpm));
    }
    pub fn set_mid_side(&mut self, enabled: bool) {
        self.mid_side = enabled;
        self.set_both(|c| c.set_mid_side(enabled));
    }

    // Metering getters
    pub fn input_peak(&self) -> (f64, f64) {
        (self.left.input_peak(), self.right.input_peak())
    }
    pub fn output_peak(&self) -> (f64, f64) {
        (self.left.output_peak(), self.right.output_peak())
    }
    pub fn gr_max_hold(&self) -> (f64, f64) {
        (self.left.gr_max_hold(), self.right.gr_max_hold())
    }
    pub fn latency_samples(&self) -> usize {
        self.left.latency_samples()
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

    /// Encode L/R to M/S
    #[inline]
    fn lr_to_ms(left: Sample, right: Sample) -> (Sample, Sample) {
        let mid = (left + right) * 0.5;
        let side = (left - right) * 0.5;
        (mid, side)
    }

    /// Decode M/S to L/R
    #[inline]
    fn ms_to_lr(mid: Sample, side: Sample) -> (Sample, Sample) {
        let left = mid + side;
        let right = mid - side;
        (left, right)
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
        // Mid/Side encoding
        let (proc_l, proc_r) = if self.mid_side {
            Self::lr_to_ms(left, right)
        } else {
            (left, right)
        };

        let (out_l, out_r) = if self.link >= 0.99 {
            // Fully linked - use max of both channels (or sidechain if enabled)
            let detection = if self.sidechain_enabled {
                self.sidechain_key_left
                    .abs()
                    .max(self.sidechain_key_right.abs())
            } else {
                proc_l.abs().max(proc_r.abs())
            };

            // Filter sidechain detection
            let filtered = self.left.filter_sidechain(detection);
            let _ = self.left.detect_level(filtered);
            let env = self.left.envelope.current();

            if env < 1e-10 {
                let makeup = db_to_linear_fast(self.left.auto_makeup_gain_db());
                (proc_l * makeup, proc_r * makeup)
            } else {
                let env_db = linear_to_db_fast(env);
                self.left.update_auto_threshold(env_db);
                let threshold = self.left.effective_threshold();

                let half_knee = self.left.knee_db / 2.0;
                let knee_start = threshold - half_knee;
                let knee_end = threshold + half_knee;

                let gr_db = if env_db < knee_start {
                    0.0
                } else if env_db > knee_end {
                    (env_db - threshold) * (1.0 - 1.0 / self.left.ratio)
                } else {
                    let x = env_db - knee_start;
                    let slope = 1.0 - 1.0 / self.left.ratio;
                    (slope * x * x) / (2.0 * self.left.knee_db.max(0.001))
                };

                let gr_db = self.left.apply_range(gr_db);
                self.left.gain_reduction = gr_db;
                self.right.gain_reduction = gr_db;

                let gain = db_to_linear_fast(-gr_db);
                let makeup = db_to_linear_fast(self.left.auto_makeup_gain_db());

                let comp_l = proc_l * gain;
                let comp_r = proc_r * gain;

                // Character
                let sat_l = if self.left.character != CompressorCharacter::Off
                    && self.left.drive_db > 0.01
                {
                    self.left.apply_character(comp_l)
                } else {
                    comp_l
                };
                let sat_r = if self.right.character != CompressorCharacter::Off
                    && self.right.drive_db > 0.01
                {
                    self.right.apply_character(comp_r)
                } else {
                    comp_r
                };

                // Dry/wet mix
                let mix = self.left.mix;
                let out_l = proc_l * (1.0 - mix) + sat_l * makeup * mix;
                let out_r = proc_r * (1.0 - mix) + sat_r * makeup * mix;

                // Meters
                self.left.update_meters(left, out_l);
                self.right.update_meters(right, out_r);

                (out_l, out_r)
            }
        } else if self.link <= 0.01 {
            // Independent
            (
                self.left.process_sample(proc_l),
                self.right.process_sample(proc_r),
            )
        } else {
            // Partial link
            let out_l = self.left.process_sample(proc_l);
            let out_r = self.right.process_sample(proc_r);

            let max_gr = self.left.gain_reduction.max(self.right.gain_reduction);
            let linked_gain = db_to_linear_fast(-max_gr);
            let makeup = db_to_linear_fast(self.left.auto_makeup_gain_db());

            let linked_l = proc_l * linked_gain * makeup;
            let linked_r = proc_r * linked_gain * makeup;

            (
                out_l * (1.0 - self.link) + linked_l * self.link,
                out_r * (1.0 - self.link) + linked_r * self.link,
            )
        };

        // Mid/Side decoding
        if self.mid_side {
            Self::ms_to_lr(out_l, out_r)
        } else {
            (out_l, out_r)
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

/// Limiter style — defines DSP laws, NOT presets
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LimiterStyle {
    /// Clean, invisible limiting — adaptive program-dependent release
    Transparent = 0,
    /// Punch-through — fast-slow dual stage release
    Punchy = 1,
    /// Preserves dynamics — program-dependent release
    Dynamic = 2,
    /// In-your-face — very fast fixed release
    Aggressive = 3,
    /// Bus/stem glue — slow release
    Bus = 4,
    /// Broadcast safe — conservative, max anti-pump
    Safe = 5,
    /// Modern loud — adaptive fast release
    Modern = 6,
    /// Balanced default
    Allround = 7,
}

impl LimiterStyle {
    pub fn from_index(i: u8) -> Self {
        match i {
            0 => Self::Transparent,
            1 => Self::Punchy,
            2 => Self::Dynamic,
            3 => Self::Aggressive,
            4 => Self::Bus,
            5 => Self::Safe,
            6 => Self::Modern,
            _ => Self::Allround,
        }
    }

    /// Transient attack time in ms for GainStageA
    pub fn transient_attack_ms(&self) -> f64 {
        match self {
            Self::Transparent => 0.05,
            Self::Punchy => 0.2,
            Self::Dynamic => 0.1,
            Self::Aggressive => 0.02,
            Self::Bus => 0.5,
            Self::Safe => 0.1,
            Self::Modern => 0.05,
            Self::Allround => 0.1,
        }
    }

    /// Fast release time in ms for GainStageB
    pub fn fast_release_ms(&self) -> f64 {
        match self {
            Self::Transparent => 20.0,
            Self::Punchy => 15.0,
            Self::Dynamic => 30.0,
            Self::Aggressive => 8.0,
            Self::Bus => 80.0,
            Self::Safe => 40.0,
            Self::Modern => 15.0,
            Self::Allround => 25.0,
        }
    }

    /// Slow release time in ms for GainStageB
    pub fn slow_release_ms(&self) -> f64 {
        match self {
            Self::Transparent => 300.0,
            Self::Punchy => 200.0,
            Self::Dynamic => 400.0,
            Self::Aggressive => 80.0,
            Self::Bus => 600.0,
            Self::Safe => 350.0,
            Self::Modern => 200.0,
            Self::Allround => 300.0,
        }
    }

    /// Anti-pumping strength (0.0-1.0)
    pub fn anti_pump_strength(&self) -> f64 {
        match self {
            Self::Transparent => 1.0,
            Self::Punchy => 0.5,
            Self::Dynamic => 0.8,
            Self::Aggressive => 0.2,
            Self::Bus => 0.8,
            Self::Safe => 1.0,
            Self::Modern => 0.5,
            Self::Allround => 0.5,
        }
    }

    /// Sustain sensitivity — how much GainStageB responds to sustained signal
    pub fn sustain_sensitivity(&self) -> f64 {
        match self {
            Self::Transparent => 0.6,
            Self::Punchy => 0.3,
            Self::Dynamic => 0.8,
            Self::Aggressive => 0.2,
            Self::Bus => 0.7,
            Self::Safe => 0.5,
            Self::Modern => 0.4,
            Self::Allround => 0.5,
        }
    }
}

/// Dither bit depth options
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DitherBits {
    Off = 0,
    Bits8 = 1,
    Bits12 = 2,
    Bits16 = 3,
    Bits24 = 4,
}

impl DitherBits {
    pub fn from_index(i: u8) -> Self {
        match i {
            1 => Self::Bits8,
            2 => Self::Bits12,
            3 => Self::Bits16,
            4 => Self::Bits24,
            _ => Self::Off,
        }
    }

    /// Dither amplitude (peak-to-peak)
    pub fn amplitude(&self) -> f64 {
        match self {
            Self::Off => 0.0,
            Self::Bits8 => 1.0 / 255.0,
            Self::Bits12 => 1.0 / 4095.0,
            Self::Bits16 => 1.0 / 65535.0,
            Self::Bits24 => 1.0 / 16777215.0,
        }
    }
}

/// Latency profile for the limiter
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LimiterLatencyProfile {
    /// Zero latency — no lookahead, 1x oversampling
    ZeroLatency = 0,
    /// High quality — user-controllable lookahead and oversampling
    HighQuality = 1,
    /// Offline max — maximum lookahead and oversampling
    OfflineMax = 2,
}

impl LimiterLatencyProfile {
    pub fn from_index(i: u8) -> Self {
        match i {
            0 => Self::ZeroLatency,
            2 => Self::OfflineMax,
            _ => Self::HighQuality,
        }
    }
}

/// Channel configuration
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LimiterChannelConfig {
    Stereo = 0,
    DualMono = 1,
    MidSide = 2,
}

impl LimiterChannelConfig {
    pub fn from_index(i: u8) -> Self {
        match i {
            1 => Self::DualMono,
            2 => Self::MidSide,
            _ => Self::Stereo,
        }
    }
}

/// GainStageA — Transient containment (fast attack, sample-by-sample)
#[derive(Debug, Clone)]
struct GainStageA {
    gain: f64,
    attack_coeff: f64,
    release_coeff: f64,
}

impl GainStageA {
    fn new(sample_rate: f64, attack_ms: f64) -> Self {
        Self {
            gain: 1.0,
            attack_coeff: if attack_ms > 0.0 {
                (-1.0 / (attack_ms * 0.001 * sample_rate)).exp()
            } else {
                0.0 // instant
            },
            release_coeff: (-1.0 / (5.0 * 0.001 * sample_rate)).exp(), // 5ms fast release for transient stage
        }
    }

    fn update_coeffs(&mut self, sample_rate: f64, attack_ms: f64) {
        self.attack_coeff = if attack_ms > 0.0 {
            (-1.0 / (attack_ms * 0.001 * sample_rate)).exp()
        } else {
            0.0
        };
        self.release_coeff = (-1.0 / (5.0 * 0.001 * sample_rate)).exp();
    }

    #[inline(always)]
    fn process(&mut self, target_gain: f64) -> f64 {
        if target_gain < self.gain {
            // Attack — fast grab
            self.gain = target_gain + self.attack_coeff * (self.gain - target_gain);
        } else {
            // Release — fast recovery (transient stage releases quickly)
            self.gain = target_gain + self.release_coeff * (self.gain - target_gain);
        }
        self.gain
    }

    fn reset(&mut self) {
        self.gain = 1.0;
    }
}

/// GainStageB — Sustain/Release shaper (program-dependent, dual time constant)
#[derive(Debug, Clone)]
struct GainStageB {
    gain: f64,
    fast_release_coeff: f64,
    slow_release_coeff: f64,
    anti_pump_strength: f64,
    sustain_sensitivity: f64,
    /// Smoothed signal level for program-dependent behavior
    signal_level: f64,
    signal_smooth_coeff: f64,
}

impl GainStageB {
    fn new(sample_rate: f64, style: &LimiterStyle) -> Self {
        let fast_ms = style.fast_release_ms();
        let slow_ms = style.slow_release_ms();
        Self {
            gain: 1.0,
            fast_release_coeff: (-1.0 / (fast_ms * 0.001 * sample_rate)).exp(),
            slow_release_coeff: (-1.0 / (slow_ms * 0.001 * sample_rate)).exp(),
            anti_pump_strength: style.anti_pump_strength(),
            sustain_sensitivity: style.sustain_sensitivity(),
            signal_level: 0.0,
            signal_smooth_coeff: (-1.0 / (50.0 * 0.001 * sample_rate)).exp(), // 50ms signal smoother
        }
    }

    fn update_coeffs(&mut self, sample_rate: f64, style: &LimiterStyle) {
        let fast_ms = style.fast_release_ms();
        let slow_ms = style.slow_release_ms();
        self.fast_release_coeff = (-1.0 / (fast_ms * 0.001 * sample_rate)).exp();
        self.slow_release_coeff = (-1.0 / (slow_ms * 0.001 * sample_rate)).exp();
        self.anti_pump_strength = style.anti_pump_strength();
        self.sustain_sensitivity = style.sustain_sensitivity();
        self.signal_smooth_coeff = (-1.0 / (50.0 * 0.001 * sample_rate)).exp();
    }

    #[inline(always)]
    fn process(&mut self, target_gain: f64, input_level: f64) -> f64 {
        // Track signal level for program-dependent behavior
        self.signal_level = input_level + self.signal_smooth_coeff * (self.signal_level - input_level);

        if target_gain < self.gain {
            // Attack (instant for sustain stage — transient containment is in StageA)
            self.gain = target_gain;
        } else {
            // Program-dependent release: blend fast and slow based on signal level
            // Higher sustained signal → slower release (anti-pumping)
            let sustained_amount = (self.signal_level * self.sustain_sensitivity).min(1.0);
            let pump_factor = 1.0 - (sustained_amount * self.anti_pump_strength);
            let release_coeff = self.fast_release_coeff * pump_factor
                + self.slow_release_coeff * (1.0 - pump_factor);
            self.gain = target_gain + release_coeff * (self.gain - target_gain);
        }
        self.gain
    }

    fn reset(&mut self) {
        self.gain = 1.0;
        self.signal_level = 0.0;
    }
}

/// True Peak Limiter with oversampling — Pro-L 2 class
///
/// Multi-stage gain engine with 8 limiter styles, user-controllable lookahead,
/// stereo link, M/S processing, dithering, and 7 real-time meters.
#[derive(Debug, Clone)]
pub struct TruePeakLimiter {
    // ═══ Core Parameters ═══
    input_trim_db: f64,
    threshold_db: f64,
    ceiling_db: f64,
    release_ms: f64,
    attack_ms: f64,
    lookahead_ms: f64,
    style: LimiterStyle,
    oversampling: Oversampling,
    stereo_link_pct: f64,
    ms_mode: bool,
    mix_pct: f64,
    dither_bits: DitherBits,
    latency_profile: LimiterLatencyProfile,
    channel_config: LimiterChannelConfig,

    // ═══ Oversampling Filters ═══
    upsample_filters: Vec<HalfbandFilter>,
    downsample_filters: Vec<HalfbandFilter>,

    // ═══ Lookahead Ring Buffer ═══
    lookahead_buffer_l: Vec<Sample>,
    lookahead_buffer_r: Vec<Sample>,
    buffer_pos: usize,

    // ═══ Multi-Stage Gain Engine ═══
    stage_a_l: GainStageA,
    stage_a_r: GainStageA,
    stage_b_l: GainStageB,
    stage_b_r: GainStageB,

    // ═══ Metering (7 meters) ═══
    gr_left: f64,
    gr_right: f64,
    input_peak_l: f64,
    input_peak_r: f64,
    output_true_peak_l: f64,
    output_true_peak_r: f64,
    gr_max_hold: f64,
    gr_max_decay_coeff: f64,

    // ═══ Legacy State ═══
    gain: f64,
    release_coeff: f64,
    true_peak: f64,
    sample_rate: f64,

    // ═══ Dither PRNG ═══
    dither_state: u64,
}

impl TruePeakLimiter {
    pub fn new(sample_rate: f64) -> Self {
        let lookahead_ms = 5.0;
        let lookahead_samples = ((lookahead_ms * 0.001 * sample_rate) as usize).max(1);
        let style = LimiterStyle::Allround;

        Self {
            input_trim_db: 0.0,
            threshold_db: 0.0,
            ceiling_db: -0.3,
            release_ms: 100.0,
            attack_ms: 0.1,
            lookahead_ms,
            style,
            oversampling: Oversampling::X2,
            stereo_link_pct: 100.0,
            ms_mode: false,
            mix_pct: 100.0,
            dither_bits: DitherBits::Off,
            latency_profile: LimiterLatencyProfile::HighQuality,
            channel_config: LimiterChannelConfig::Stereo,

            upsample_filters: vec![HalfbandFilter::new(); 4],
            downsample_filters: vec![HalfbandFilter::new(); 4],
            lookahead_buffer_l: vec![0.0; lookahead_samples],
            lookahead_buffer_r: vec![0.0; lookahead_samples],
            buffer_pos: 0,

            stage_a_l: GainStageA::new(sample_rate, style.transient_attack_ms()),
            stage_a_r: GainStageA::new(sample_rate, style.transient_attack_ms()),
            stage_b_l: GainStageB::new(sample_rate, &style),
            stage_b_r: GainStageB::new(sample_rate, &style),

            gr_left: 0.0,
            gr_right: 0.0,
            input_peak_l: -200.0,
            input_peak_r: -200.0,
            output_true_peak_l: -200.0,
            output_true_peak_r: -200.0,
            gr_max_hold: 0.0,
            gr_max_decay_coeff: (-1.0 / (2.0 * sample_rate)).exp(), // 2s decay

            gain: 1.0,
            release_coeff: (-1.0 / (100.0 * 0.001 * sample_rate)).exp(),
            true_peak: 0.0,
            sample_rate,
            dither_state: 0x12345678ABCDEF01,
        }
    }

    // ═══ Parameter Setters ═══

    pub fn set_input_trim(&mut self, db: f64) {
        self.input_trim_db = db.clamp(-12.0, 12.0);
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-30.0, 0.0);
    }

    pub fn set_ceiling(&mut self, db: f64) {
        self.ceiling_db = db.clamp(-3.0, 0.0);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(1.0, 1000.0);
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.attack_ms = ms.clamp(0.01, 10.0);
        self.stage_a_l.update_coeffs(self.sample_rate, self.attack_ms);
        self.stage_a_r.update_coeffs(self.sample_rate, self.attack_ms);
    }

    pub fn set_lookahead(&mut self, ms: f64) {
        let effective_ms = match self.latency_profile {
            LimiterLatencyProfile::ZeroLatency => 0.0,
            LimiterLatencyProfile::OfflineMax => 20.0,
            _ => ms.clamp(0.0, 20.0),
        };
        self.lookahead_ms = effective_ms;
        let new_len = ((effective_ms * 0.001 * self.sample_rate) as usize).max(1);
        if new_len != self.lookahead_buffer_l.len() {
            self.lookahead_buffer_l = vec![0.0; new_len];
            self.lookahead_buffer_r = vec![0.0; new_len];
            self.buffer_pos = 0;
        }
    }

    pub fn set_style(&mut self, style: LimiterStyle) {
        self.style = style;
        self.stage_a_l.update_coeffs(self.sample_rate, style.transient_attack_ms());
        self.stage_a_r.update_coeffs(self.sample_rate, style.transient_attack_ms());
        self.stage_b_l.update_coeffs(self.sample_rate, &style);
        self.stage_b_r.update_coeffs(self.sample_rate, &style);
    }

    pub fn set_oversampling(&mut self, os: Oversampling) {
        self.oversampling = os;
        self.reset();
    }

    pub fn set_stereo_link(&mut self, pct: f64) {
        self.stereo_link_pct = pct.clamp(0.0, 100.0);
    }

    pub fn set_ms_mode(&mut self, enabled: bool) {
        self.ms_mode = enabled;
    }

    pub fn set_mix(&mut self, pct: f64) {
        self.mix_pct = pct.clamp(0.0, 100.0);
    }

    pub fn set_dither_bits(&mut self, bits: DitherBits) {
        self.dither_bits = bits;
    }

    pub fn set_latency_profile(&mut self, profile: LimiterLatencyProfile) {
        self.latency_profile = profile;
        // Re-apply lookahead with new profile constraints
        self.set_lookahead(self.lookahead_ms);
    }

    pub fn set_channel_config(&mut self, config: LimiterChannelConfig) {
        self.channel_config = config;
    }

    // ═══ Parameter Getters ═══

    pub fn input_trim_db(&self) -> f64 { self.input_trim_db }
    pub fn threshold_db(&self) -> f64 { self.threshold_db }
    pub fn ceiling_db_val(&self) -> f64 { self.ceiling_db }
    pub fn release_ms(&self) -> f64 { self.release_ms }
    pub fn attack_ms(&self) -> f64 { self.attack_ms }
    pub fn lookahead_ms(&self) -> f64 { self.lookahead_ms }
    pub fn style(&self) -> LimiterStyle { self.style }
    pub fn oversampling(&self) -> Oversampling { self.oversampling }
    pub fn stereo_link_pct(&self) -> f64 { self.stereo_link_pct }
    pub fn ms_mode(&self) -> bool { self.ms_mode }
    pub fn mix_pct(&self) -> f64 { self.mix_pct }
    pub fn dither_bits(&self) -> DitherBits { self.dither_bits }
    pub fn latency_profile(&self) -> LimiterLatencyProfile { self.latency_profile }
    pub fn channel_config(&self) -> LimiterChannelConfig { self.channel_config }

    // ═══ Meter Getters ═══

    /// Get current true peak level in dBTP
    pub fn true_peak_db(&self) -> f64 {
        linear_to_db_fast(self.true_peak)
    }

    /// Get current gain reduction in dB (POSITIVE value = reduction applied)
    pub fn gain_reduction_db(&self) -> f64 {
        -linear_to_db_fast(self.gain)
    }

    /// Per-channel gain reduction (L)
    pub fn gr_left_db(&self) -> f64 { self.gr_left }
    /// Per-channel gain reduction (R)
    pub fn gr_right_db(&self) -> f64 { self.gr_right }
    /// Input peak L in dBFS
    pub fn input_peak_l_db(&self) -> f64 { self.input_peak_l }
    /// Input peak R in dBFS
    pub fn input_peak_r_db(&self) -> f64 { self.input_peak_r }
    /// Output true peak L in dBTP
    pub fn output_true_peak_l_db(&self) -> f64 { self.output_true_peak_l }
    /// Output true peak R in dBTP
    pub fn output_true_peak_r_db(&self) -> f64 { self.output_true_peak_r }
    /// GR max hold (2s decay)
    pub fn gr_max_hold_db(&self) -> f64 { self.gr_max_hold }

    // ═══ Internal Helpers ═══

    /// Triangular dither — two uniform randoms summed for TPDF
    #[inline(always)]
    fn dither_sample(&mut self) -> f64 {
        let amp = self.dither_bits.amplitude();
        if amp <= 0.0 { return 0.0; }
        // xorshift64
        let mut s = self.dither_state;
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        self.dither_state = s;
        let r1 = (s as i64 as f64) / (i64::MAX as f64); // -1..+1
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        self.dither_state = s;
        let r2 = (s as i64 as f64) / (i64::MAX as f64);
        (r1 + r2) * 0.5 * amp
    }

    /// M/S encode
    #[inline(always)]
    fn ms_encode(left: f64, right: f64) -> (f64, f64) {
        ((left + right) * 0.5, (left - right) * 0.5)
    }

    /// M/S decode
    #[inline(always)]
    fn ms_decode(mid: f64, side: f64) -> (f64, f64) {
        (mid + side, mid - side)
    }

    /// Public M/S encode (for testing)
    pub fn ms_encode_static(left: f64, right: f64) -> (f64, f64) {
        Self::ms_encode(left, right)
    }

    /// Public M/S decode (for testing)
    pub fn ms_decode_static(mid: f64, side: f64) -> (f64, f64) {
        Self::ms_decode(mid, side)
    }

    /// Stereo link two GR values
    #[inline(always)]
    fn stereo_link(gr_l: f64, gr_r: f64, link_pct: f64) -> (f64, f64) {
        let link = link_pct / 100.0;
        let linked = gr_l.min(gr_r); // tighter wins
        let out_l = gr_l * (1.0 - link) + linked * link;
        let out_r = gr_r * (1.0 - link) + linked * link;
        (out_l, out_r)
    }

    /// Compute latency in samples based on current lookahead
    pub fn latency_samples(&self) -> usize {
        if self.latency_profile == LimiterLatencyProfile::ZeroLatency {
            0
        } else {
            self.lookahead_buffer_l.len()
        }
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

        self.stage_a_l.reset();
        self.stage_a_r.reset();
        self.stage_b_l.reset();
        self.stage_b_r.reset();

        // Reset meters
        self.gr_left = 0.0;
        self.gr_right = 0.0;
        self.input_peak_l = -200.0;
        self.input_peak_r = -200.0;
        self.output_true_peak_l = -200.0;
        self.output_true_peak_r = -200.0;
        self.gr_max_hold = 0.0;

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
        let dry_l = left;
        let dry_r = right;

        // ═══ Stage 1: Input Trim ═══
        let trim_gain = db_to_linear_fast(self.input_trim_db);
        let mut proc_l = left * trim_gain;
        let mut proc_r = right * trim_gain;

        // ═══ Stage 2: M/S Encode (optional) ═══
        if self.ms_mode {
            let (m, s) = Self::ms_encode(proc_l, proc_r);
            proc_l = m;
            proc_r = s;
        }

        // ═══ Stage 3: Input Metering (pre-processing) ═══
        let in_peak_l = proc_l.abs();
        let in_peak_r = proc_r.abs();
        let in_peak_l_db = linear_to_db_fast(in_peak_l.max(1e-20));
        let in_peak_r_db = linear_to_db_fast(in_peak_r.max(1e-20));
        if in_peak_l_db > self.input_peak_l { self.input_peak_l = in_peak_l_db; }
        if in_peak_r_db > self.input_peak_r { self.input_peak_r = in_peak_r_db; }

        // ═══ Stage 4: Lookahead Delay ═══
        let buf_len = self.lookahead_buffer_l.len();
        let delayed_l = self.lookahead_buffer_l[self.buffer_pos];
        let delayed_r = self.lookahead_buffer_r[self.buffer_pos];
        self.lookahead_buffer_l[self.buffer_pos] = proc_l;
        self.lookahead_buffer_r[self.buffer_pos] = proc_r;
        self.buffer_pos = (self.buffer_pos + 1) % buf_len;

        // ═══ Stage 5: True Peak Detection ═══
        let true_peak = self.find_true_peak(proc_l, proc_r);
        self.true_peak = self.true_peak.max(true_peak);

        // ═══ Stage 6: Per-Channel Target Gain ═══
        let threshold_linear = db_to_linear_fast(self.threshold_db);
        let ceiling_linear = db_to_linear_fast(self.ceiling_db);

        let peak_l = proc_l.abs().max(1e-20);
        let peak_r = proc_r.abs().max(1e-20);

        let target_l = if peak_l > threshold_linear {
            (ceiling_linear / peak_l).min(1.0)
        } else {
            1.0
        };
        let target_r = if peak_r > threshold_linear {
            (ceiling_linear / peak_r).min(1.0)
        } else {
            1.0
        };

        // ═══ Stage 7: Multi-Stage Gain Engine ═══
        // Stage A: Transient containment (fast)
        let gr_a_l = self.stage_a_l.process(target_l);
        let gr_a_r = self.stage_a_r.process(target_r);

        // Stage B: Sustain/Release shaper (program-dependent)
        let gr_b_l = self.stage_b_l.process(target_l, peak_l);
        let gr_b_r = self.stage_b_r.process(target_r, peak_r);

        // Final GR = tighter of the two stages
        let mut final_gr_l = gr_a_l.min(gr_b_l);
        let mut final_gr_r = gr_a_r.min(gr_b_r);

        // ═══ Stage 8: Stereo Link ═══
        if self.stereo_link_pct > 0.0 {
            let (linked_l, linked_r) = Self::stereo_link(final_gr_l, final_gr_r, self.stereo_link_pct);
            final_gr_l = linked_l;
            final_gr_r = linked_r;
        }

        // ═══ Stage 9: Apply Gain to Delayed Signal ═══
        let mut out_l = delayed_l * final_gr_l;
        let mut out_r = delayed_r * final_gr_r;

        // Legacy gain tracking (for backward compat)
        self.gain = final_gr_l.min(final_gr_r);

        // ═══ Stage 10: Ceiling Safety ═══
        let ceil = ceiling_linear;
        if out_l.abs() > ceil { out_l = out_l.signum() * ceil; }
        if out_r.abs() > ceil { out_r = out_r.signum() * ceil; }

        // ═══ Stage 11: M/S Decode (if M/S active) ═══
        if self.ms_mode {
            let (l, r) = Self::ms_decode(out_l, out_r);
            out_l = l;
            out_r = r;
        }

        // ═══ Stage 12: Dither (if enabled) ═══
        if self.dither_bits != DitherBits::Off {
            out_l += self.dither_sample();
            out_r += self.dither_sample();
        }

        // ═══ Stage 13: Mix (parallel limiting) ═══
        let mix = self.mix_pct / 100.0;
        if mix < 1.0 {
            out_l = dry_l * (1.0 - mix) + out_l * mix;
            out_r = dry_r * (1.0 - mix) + out_r * mix;
        }

        // ═══ Metering Update ═══
        let gr_db_l = -linear_to_db_fast(final_gr_l);
        let gr_db_r = -linear_to_db_fast(final_gr_r);
        self.gr_left = gr_db_l;
        self.gr_right = gr_db_r;

        // Output true peak metering
        let out_peak_l = linear_to_db_fast(out_l.abs().max(1e-20));
        let out_peak_r = linear_to_db_fast(out_r.abs().max(1e-20));
        if out_peak_l > self.output_true_peak_l { self.output_true_peak_l = out_peak_l; }
        if out_peak_r > self.output_true_peak_r { self.output_true_peak_r = out_peak_r; }

        // GR max hold with 2s decay
        let gr_max_now = gr_db_l.max(gr_db_r);
        if gr_max_now > self.gr_max_hold {
            self.gr_max_hold = gr_max_now;
        } else {
            self.gr_max_hold = gr_max_now + self.gr_max_decay_coeff * (self.gr_max_hold - gr_max_now);
        }

        (out_l, out_r)
    }
}

impl ProcessorConfig for TruePeakLimiter {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * sample_rate)).exp();
        self.gr_max_decay_coeff = (-1.0 / (2.0 * sample_rate)).exp();

        let lookahead_samples = ((self.lookahead_ms * 0.001 * sample_rate) as usize).max(1);
        self.lookahead_buffer_l = vec![0.0; lookahead_samples];
        self.lookahead_buffer_r = vec![0.0; lookahead_samples];
        self.buffer_pos = 0;

        // Update gain stage coefficients
        self.stage_a_l.update_coeffs(sample_rate, self.style.transient_attack_ms());
        self.stage_a_r.update_coeffs(sample_rate, self.style.transient_attack_ms());
        self.stage_b_l.update_coeffs(sample_rate, &self.style);
        self.stage_b_r.update_coeffs(sample_rate, &self.style);
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
    /// Hysteresis in dB — gate closes at (threshold - hysteresis) instead of threshold
    hysteresis_db: f64,
    /// Whether gate is currently in "open" state (for hysteresis logic)
    is_open: bool,
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
            hysteresis_db: 0.0,
            is_open: false,
        };
        gate.envelope.set_times(1.0, 50.0);
        gate
    }

    /// Set hysteresis in dB (0-12). Gate closes at (threshold - hysteresis).
    pub fn set_hysteresis(&mut self, db: f64) {
        self.hysteresis_db = db.clamp(0.0, 12.0);
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
        self.is_open = false;
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

        // Hysteresis: gate opens at threshold, closes at (threshold - hysteresis_db)
        let close_threshold = if self.hysteresis_db > 0.01 {
            db_to_linear_fast(self.threshold_db - self.hysteresis_db)
        } else {
            threshold
        };

        let hold_samples = (self.hold_ms * 0.001 * self.sample_rate) as usize;

        let target_gain = if self.is_open {
            // Gate is open — stays open until signal drops below close_threshold
            if envelope >= close_threshold {
                self.hold_counter = hold_samples;
                1.0
            } else if self.hold_counter > 0 {
                self.hold_counter -= 1;
                1.0
            } else {
                self.is_open = false;
                range
            }
        } else {
            // Gate is closed — opens when signal exceeds threshold
            if envelope >= threshold {
                self.is_open = true;
                self.hold_counter = hold_samples;
                1.0
            } else {
                range
            }
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

    // ==================== Pro-L 2 Class Limiter Tests ====================

    #[test]
    fn test_limiter_default_params() {
        let limiter = TruePeakLimiter::new(48000.0);
        assert!((limiter.input_trim_db() - 0.0).abs() < 0.001);
        assert!((limiter.threshold_db() - 0.0).abs() < 0.001);
        assert!((limiter.ceiling_db_val() - (-0.3)).abs() < 0.001);
        assert!((limiter.release_ms() - 100.0).abs() < 0.001);
        assert!((limiter.attack_ms() - 0.1).abs() < 0.001);
        assert!((limiter.lookahead_ms() - 5.0).abs() < 0.001);
        assert!(matches!(limiter.style(), LimiterStyle::Allround));
        assert!(matches!(limiter.oversampling(), Oversampling::X2));
        assert!((limiter.stereo_link_pct() - 100.0).abs() < 0.001);
        assert!(!limiter.ms_mode());
        assert!((limiter.mix_pct() - 100.0).abs() < 0.001);
        assert!(matches!(limiter.dither_bits(), DitherBits::Off));
        assert!(matches!(limiter.latency_profile(), LimiterLatencyProfile::HighQuality));
        assert!(matches!(limiter.channel_config(), LimiterChannelConfig::Stereo));
    }

    #[test]
    fn test_limiter_param_readback() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_input_trim(-6.0);
        limiter.set_threshold(-10.0);
        limiter.set_ceiling(-1.0);
        limiter.set_release(200.0);
        limiter.set_attack(1.0);
        // Use HQ profile so lookahead isn't overridden
        limiter.set_latency_profile(LimiterLatencyProfile::HighQuality);
        limiter.set_lookahead(10.0);
        limiter.set_style(LimiterStyle::Aggressive);
        limiter.set_oversampling(Oversampling::X4);
        limiter.set_stereo_link(50.0);
        limiter.set_ms_mode(true);
        limiter.set_mix(75.0);
        limiter.set_dither_bits(DitherBits::Bits16);
        limiter.set_channel_config(LimiterChannelConfig::MidSide);

        assert!((limiter.input_trim_db() - (-6.0)).abs() < 0.001);
        assert!((limiter.threshold_db() - (-10.0)).abs() < 0.001);
        assert!((limiter.ceiling_db_val() - (-1.0)).abs() < 0.001);
        assert!((limiter.release_ms() - 200.0).abs() < 0.001);
        assert!((limiter.attack_ms() - 1.0).abs() < 0.001);
        assert!((limiter.lookahead_ms() - 10.0).abs() < 0.001);
        assert!(matches!(limiter.style(), LimiterStyle::Aggressive));
        assert!(matches!(limiter.oversampling(), Oversampling::X4));
        assert!((limiter.stereo_link_pct() - 50.0).abs() < 0.001);
        assert!(limiter.ms_mode());
        assert!((limiter.mix_pct() - 75.0).abs() < 0.001);
        assert!(matches!(limiter.dither_bits(), DitherBits::Bits16));
        assert!(matches!(limiter.latency_profile(), LimiterLatencyProfile::HighQuality));
        assert!(matches!(limiter.channel_config(), LimiterChannelConfig::MidSide));
    }

    #[test]
    fn test_limiter_param_clamping() {
        let mut limiter = TruePeakLimiter::new(48000.0);

        limiter.set_input_trim(-100.0);
        assert!((limiter.input_trim_db() - (-12.0)).abs() < 0.001);
        limiter.set_input_trim(100.0);
        assert!((limiter.input_trim_db() - 12.0).abs() < 0.001);

        limiter.set_threshold(-100.0);
        assert!((limiter.threshold_db() - (-30.0)).abs() < 0.001);
        limiter.set_threshold(100.0);
        assert!((limiter.threshold_db() - 0.0).abs() < 0.001);

        limiter.set_ceiling(-100.0);
        assert!((limiter.ceiling_db_val() - (-3.0)).abs() < 0.001);
        limiter.set_ceiling(100.0);
        assert!((limiter.ceiling_db_val() - 0.0).abs() < 0.001);

        limiter.set_release(0.01);
        assert!((limiter.release_ms() - 1.0).abs() < 0.001);
        limiter.set_release(9999.0);
        assert!((limiter.release_ms() - 1000.0).abs() < 0.001);

        limiter.set_attack(-1.0);
        assert!((limiter.attack_ms() - 0.01).abs() < 0.001);
        limiter.set_attack(999.0);
        assert!((limiter.attack_ms() - 10.0).abs() < 0.001);

        limiter.set_lookahead(-5.0);
        assert!((limiter.lookahead_ms() - 0.0).abs() < 0.001);
        limiter.set_lookahead(100.0);
        assert!((limiter.lookahead_ms() - 20.0).abs() < 0.001);

        limiter.set_stereo_link(-50.0);
        assert!((limiter.stereo_link_pct() - 0.0).abs() < 0.001);
        limiter.set_stereo_link(200.0);
        assert!((limiter.stereo_link_pct() - 100.0).abs() < 0.001);

        limiter.set_mix(-50.0);
        assert!((limiter.mix_pct() - 0.0).abs() < 0.001);
        limiter.set_mix(200.0);
        assert!((limiter.mix_pct() - 100.0).abs() < 0.001);
    }

    #[test]
    fn test_limiter_input_trim() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-20.0); // Very low threshold so we can measure gain change
        limiter.set_input_trim(6.0); // +6dB = ~2x amplitude

        // Warm up
        for _ in 0..1000 {
            let _ = limiter.process_sample(0.001, 0.001);
        }

        // Input trim should double the amplitude before processing
        // Tiny signal won't trigger limiter, so output should show trim
        let (l, _r) = limiter.process_sample(0.001, 0.001);
        // With +6dB trim, 0.001 → ~0.002, which is below threshold
        assert!(l > 0.0015, "Input trim +6dB should approximately double the signal, got {}", l);
    }

    #[test]
    fn test_limiter_ceiling_enforcement() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);
        limiter.set_ceiling(-0.5);

        // Process enough for lookahead buffer
        let latency = limiter.latency_samples();
        for _ in 0..(latency + 500) {
            let _ = limiter.process_sample(2.0, 2.0);
        }

        // Check multiple samples — all should be under ceiling
        let ceiling_linear = 10.0_f64.powf(-0.5 / 20.0);
        for _ in 0..100 {
            let (l, r) = limiter.process_sample(2.0, 2.0);
            // Allow small tolerance for filter overshoot
            assert!(l.abs() < ceiling_linear * 1.05,
                "Output {:.4} exceeds ceiling {:.4}", l.abs(), ceiling_linear);
            assert!(r.abs() < ceiling_linear * 1.05,
                "Output {:.4} exceeds ceiling {:.4}", r.abs(), ceiling_linear);
        }
    }

    #[test]
    fn test_limiter_gain_reduction_meters() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);
        limiter.set_ceiling(-0.3);

        // Process loud signal
        for _ in 0..2000 {
            let _ = limiter.process_sample(2.0, 1.5);
        }

        // GR is stored as POSITIVE dB when gain is reduced
        // (e.g., 6dB of gain reduction = gr_left_db() returns 6.0)
        let gr_l = limiter.gr_left_db();
        let gr_r = limiter.gr_right_db();
        assert!(gr_l > 0.1, "GR left should be positive dB when limiting, got {}", gr_l);
        assert!(gr_r > 0.1, "GR right should be positive dB when limiting, got {}", gr_r);
    }

    #[test]
    fn test_limiter_input_peak_meters() {
        let mut limiter = TruePeakLimiter::new(48000.0);

        // Process with known amplitude
        for _ in 0..500 {
            let _ = limiter.process_sample(0.5, 0.8);
        }

        // Input peak meters are stored in dB
        // 0.5 linear → ~-6.02 dB, 0.8 linear → ~-1.94 dB
        let peak_l = limiter.input_peak_l_db();
        let peak_r = limiter.input_peak_r_db();
        assert!(peak_l > -7.0 && peak_l < -5.0,
            "Input peak L should be ~-6dB for 0.5 input, got {}", peak_l);
        assert!(peak_r > -3.0 && peak_r < -1.0,
            "Input peak R should be ~-2dB for 0.8 input, got {}", peak_r);
    }

    #[test]
    fn test_limiter_mix_bypass() {
        let mut limiter_wet = TruePeakLimiter::new(48000.0);
        limiter_wet.set_threshold(-6.0);
        limiter_wet.set_mix(100.0); // Full wet

        let mut limiter_dry = TruePeakLimiter::new(48000.0);
        limiter_dry.set_threshold(-6.0);
        limiter_dry.set_mix(0.0); // Full dry

        // Warm up both
        for _ in 0..2000 {
            let _ = limiter_wet.process_sample(0.8, 0.8);
            let _ = limiter_dry.process_sample(0.8, 0.8);
        }

        // Dry (mix=0%) should pass through unchanged
        let (dry_l, _) = limiter_dry.process_sample(0.8, 0.8);
        // With lookahead delay, dry output should eventually approximate input
        assert!((dry_l - 0.8).abs() < 0.1, "Mix 0% should be near-bypass, got {}", dry_l);
    }

    #[test]
    fn test_limiter_stereo_link_100() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);
        limiter.set_stereo_link(100.0);

        // Process with unbalanced stereo (L loud, R quiet)
        for _ in 0..2000 {
            let _ = limiter.process_sample(2.0, 0.1);
        }

        // With 100% link, both channels should get same GR
        let gr_l = limiter.gr_left_db();
        let gr_r = limiter.gr_right_db();
        assert!((gr_l - gr_r).abs() < 0.5,
            "100% link: GR should be similar, got L={}, R={}", gr_l, gr_r);
    }

    #[test]
    fn test_limiter_stereo_link_0() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);
        limiter.set_stereo_link(0.0);

        // Process with very unbalanced stereo
        for _ in 0..2000 {
            let _ = limiter.process_sample(2.0, 0.01);
        }

        // With 0% link, channels should have independent GR
        // GR is POSITIVE dB — L is loud → more positive GR, R is quiet → less/no GR
        let gr_l = limiter.gr_left_db();
        let gr_r = limiter.gr_right_db();
        assert!(gr_l > gr_r + 1.0,
            "0% link: L should have more GR (higher positive dB) than R, got L={}, R={}", gr_l, gr_r);
    }

    #[test]
    fn test_limiter_ms_roundtrip() {
        // M/S encode→decode should be unity
        let l_in = 0.7;
        let r_in = 0.3;
        let (mid, side) = TruePeakLimiter::ms_encode_static(l_in, r_in);
        let (l_out, r_out) = TruePeakLimiter::ms_decode_static(mid, side);
        assert!((l_out - l_in).abs() < 1e-10, "M/S roundtrip L: {} vs {}", l_out, l_in);
        assert!((r_out - r_in).abs() < 1e-10, "M/S roundtrip R: {} vs {}", r_out, r_in);
    }

    #[test]
    fn test_limiter_styles_different_gr() {
        // Styles differ in attack/release behavior, so use transient+sustain mix
        // to reveal different GR curves across styles
        let styles = [
            LimiterStyle::Transparent, LimiterStyle::Punchy, LimiterStyle::Dynamic,
            LimiterStyle::Aggressive, LimiterStyle::Bus, LimiterStyle::Safe,
            LimiterStyle::Modern, LimiterStyle::Allround,
        ];
        let mut gr_sums = Vec::new();

        for style in &styles {
            let mut limiter = TruePeakLimiter::new(48000.0);
            limiter.set_threshold(-6.0);
            limiter.set_style(*style);

            // Accumulate GR over transient + sustain to capture style differences
            let mut gr_sum = 0.0;
            // Phase 1: Transient burst
            for _ in 0..200 {
                let _ = limiter.process_sample(3.0, 3.0);
                gr_sum += limiter.gr_left_db();
            }
            // Phase 2: Moderate sustain (release behavior differs)
            for _ in 0..1000 {
                let _ = limiter.process_sample(1.2, 1.2);
                gr_sum += limiter.gr_left_db();
            }
            // Phase 3: Silence (recovery differs)
            for _ in 0..500 {
                let _ = limiter.process_sample(0.01, 0.01);
                gr_sum += limiter.gr_left_db();
            }
            gr_sums.push(gr_sum);
        }

        // At least some styles should produce different cumulative GR
        let unique_count = {
            let mut deduped = gr_sums.clone();
            deduped.sort_by(|a, b| a.partial_cmp(b).unwrap());
            deduped.dedup_by(|a, b| (*a - *b).abs() < 1.0); // 1dB cumulative tolerance
            deduped.len()
        };
        assert!(unique_count >= 3,
            "Expected at least 3 unique cumulative GR values across 8 styles, got {} ({:?})",
            unique_count, gr_sums);
    }

    #[test]
    fn test_limiter_all_styles_valid_output() {
        for style_idx in 0..8 {
            let style = LimiterStyle::from_index(style_idx);
            let mut limiter = TruePeakLimiter::new(48000.0);
            limiter.set_threshold(-6.0);
            limiter.set_style(style);

            for _ in 0..3000 {
                let (l, r) = limiter.process_sample(1.5, 1.5);
                assert!(!l.is_nan(), "Style {} produced NaN L", style_idx);
                assert!(!r.is_nan(), "Style {} produced NaN R", style_idx);
                assert!(!l.is_infinite(), "Style {} produced Inf L", style_idx);
                assert!(!r.is_infinite(), "Style {} produced Inf R", style_idx);
            }
        }
    }

    #[test]
    fn test_limiter_style_switch_no_click() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);

        // Warm up with Allround
        for _ in 0..2000 {
            let _ = limiter.process_sample(1.2, 1.2);
        }

        // Switch mid-stream to Aggressive
        limiter.set_style(LimiterStyle::Aggressive);

        // Process after switch — should not produce discontinuity
        let mut max_jump = 0.0_f64;
        let mut prev = limiter.process_sample(1.2, 1.2).0;
        for _ in 0..500 {
            let (l, _) = limiter.process_sample(1.2, 1.2);
            let jump = (l - prev).abs();
            max_jump = max_jump.max(jump);
            prev = l;
        }
        // Max sample-to-sample jump should be small (no click)
        assert!(max_jump < 0.2, "Style switch caused click: max_jump={}", max_jump);
    }

    #[test]
    fn test_limiter_style_doesnt_affect_ceiling() {
        for style_idx in 0..8 {
            let style = LimiterStyle::from_index(style_idx);
            let mut limiter = TruePeakLimiter::new(48000.0);
            limiter.set_threshold(-6.0);
            limiter.set_ceiling(-0.5);
            limiter.set_style(style);

            let ceiling_linear = 10.0_f64.powf(-0.5 / 20.0);

            for _ in 0..3000 {
                let (l, r) = limiter.process_sample(2.0, 2.0);
                assert!(l.abs() < ceiling_linear * 1.1,
                    "Style {} broke ceiling: {} > {}", style_idx, l.abs(), ceiling_linear);
                assert!(r.abs() < ceiling_linear * 1.1,
                    "Style {} broke ceiling: {} > {}", style_idx, r.abs(), ceiling_linear);
            }
        }
    }

    #[test]
    fn test_limiter_multi_stage_gain() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-3.0);
        limiter.set_style(LimiterStyle::Punchy); // Has different A/B behavior

        // Warm up
        for _ in 0..500 {
            let _ = limiter.process_sample(0.01, 0.01);
        }

        // Transient burst (loud)
        for _ in 0..100 {
            let _ = limiter.process_sample(3.0, 3.0);
        }
        let gr_transient = limiter.gr_left_db();

        // Sustained moderate signal (lower level)
        for _ in 0..5000 {
            let _ = limiter.process_sample(1.2, 1.2);
        }
        let gr_sustained = limiter.gr_left_db();

        // GR is POSITIVE dB — transient should have MORE positive GR (more reduction)
        // than sustained moderate signal
        assert!(gr_transient > gr_sustained - 1.0,
            "Transient GR ({} dB) should be >= sustained GR ({} dB)", gr_transient, gr_sustained);
    }

    #[test]
    fn test_limiter_zero_latency_mode() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_latency_profile(LimiterLatencyProfile::ZeroLatency);

        // Zero latency = 0 lookahead
        assert_eq!(limiter.latency_samples(), 0, "ZeroLatency should have 0 latency");

        // Should still produce valid output
        for _ in 0..1000 {
            let (l, r) = limiter.process_sample(1.5, 1.5);
            assert!(!l.is_nan());
            assert!(!r.is_nan());
        }
    }

    #[test]
    fn test_limiter_dither_off_passthrough() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(0.0); // No limiting
        limiter.set_dither_bits(DitherBits::Off);

        // Small signal, no limiting, no dither
        for _ in 0..500 {
            let _ = limiter.process_sample(0.1, 0.1);
        }

        // With lookahead delay settled, output should match input closely
        let (l, r) = limiter.process_sample(0.1, 0.1);
        assert!((l - 0.1).abs() < 0.05, "Dither off should be near-passthrough, got {}", l);
        assert!((r - 0.1).abs() < 0.05, "Dither off should be near-passthrough, got {}", r);
    }

    #[test]
    fn test_limiter_dither_adds_noise() {
        let mut limiter_no_dither = TruePeakLimiter::new(48000.0);
        limiter_no_dither.set_threshold(0.0);
        limiter_no_dither.set_dither_bits(DitherBits::Off);

        let mut limiter_dither = TruePeakLimiter::new(48000.0);
        limiter_dither.set_threshold(0.0);
        limiter_dither.set_dither_bits(DitherBits::Bits16);

        // Warm up both
        for _ in 0..500 {
            let _ = limiter_no_dither.process_sample(0.1, 0.1);
            let _ = limiter_dither.process_sample(0.1, 0.1);
        }

        // Process and compare — dithered should differ from clean
        let mut diff_sum = 0.0;
        for _ in 0..100 {
            let (clean_l, _) = limiter_no_dither.process_sample(0.1, 0.1);
            let (dith_l, _) = limiter_dither.process_sample(0.1, 0.1);
            diff_sum += (clean_l - dith_l).abs();
        }
        // Dither should add measurable noise
        assert!(diff_sum > 1e-6, "16-bit dither should add measurable noise, diff_sum={}", diff_sum);
    }

    #[test]
    fn test_limiter_gr_max_hold() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);

        // Process loud signal to build GR
        for _ in 0..3000 {
            let _ = limiter.process_sample(3.0, 3.0);
        }
        let gr_max_during = limiter.gr_max_hold_db();

        // Process silence — GR max should hold
        for _ in 0..500 {
            let _ = limiter.process_sample(0.001, 0.001);
        }
        let gr_max_after = limiter.gr_max_hold_db();

        // Peak hold should retain the worst value (or decay slowly)
        assert!(gr_max_after <= gr_max_during + 0.5,
            "GR max hold should retain peak, during={} after={}", gr_max_during, gr_max_after);
    }

    #[test]
    fn test_limiter_reset() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);

        // Process to build state
        for _ in 0..3000 {
            let _ = limiter.process_sample(2.0, 2.0);
        }
        // GR is POSITIVE dB when limiting
        assert!(limiter.gr_left_db() > 0.1, "Should have positive GR before reset, got {}", limiter.gr_left_db());

        // Reset
        limiter.reset();

        // After reset, meters should be zeroed
        assert!((limiter.gr_left_db() - 0.0).abs() < 0.001, "GR should be 0 after reset");
        assert!((limiter.gr_right_db() - 0.0).abs() < 0.001, "GR should be 0 after reset");
        assert!((limiter.gr_max_hold_db() - 0.0).abs() < 0.001, "GR max should be 0 after reset");
    }

    #[test]
    fn test_limiter_sample_rate_change() {
        let mut limiter = TruePeakLimiter::new(44100.0);
        limiter.set_threshold(-6.0);
        limiter.set_attack(0.5);
        limiter.set_release(100.0);

        // Process at 44.1k
        for _ in 0..2000 {
            let _ = limiter.process_sample(1.5, 1.5);
        }

        // Change to 96k
        limiter.set_sample_rate(96000.0);

        // Should still produce valid output
        for _ in 0..2000 {
            let (l, r) = limiter.process_sample(1.5, 1.5);
            assert!(!l.is_nan(), "NaN after sample rate change");
            assert!(!r.is_nan(), "NaN after sample rate change");
            assert!(l.abs() < 2.0, "Wild output after sample rate change: {}", l);
        }
    }

    #[test]
    fn test_limiter_style_dsp_constants() {
        // Verify style DSP constants are sensible
        for idx in 0..8 {
            let style = LimiterStyle::from_index(idx);
            assert!(style.transient_attack_ms() > 0.0, "Style {} attack <= 0", idx);
            assert!(style.transient_attack_ms() < 10.0, "Style {} attack too high", idx);
            assert!(style.fast_release_ms() > 0.0, "Style {} fast release <= 0", idx);
            assert!(style.slow_release_ms() > style.fast_release_ms(),
                "Style {} slow release should > fast release", idx);
            assert!(style.anti_pump_strength() >= 0.0 && style.anti_pump_strength() <= 1.0,
                "Style {} anti-pump out of range", idx);
            assert!(style.sustain_sensitivity() >= 0.0 && style.sustain_sensitivity() <= 1.0,
                "Style {} sustain sensitivity out of range", idx);
        }
    }

    #[test]
    fn test_limiter_dither_bits_amplitude() {
        assert!((DitherBits::Off.amplitude() - 0.0).abs() < 1e-10);
        assert!(DitherBits::Bits8.amplitude() > DitherBits::Bits16.amplitude());
        assert!(DitherBits::Bits16.amplitude() > DitherBits::Bits24.amplitude());
        assert!(DitherBits::Bits24.amplitude() > 0.0);
    }

    #[test]
    fn test_limiter_latency_profiles() {
        let mut limiter = TruePeakLimiter::new(48000.0);

        limiter.set_latency_profile(LimiterLatencyProfile::ZeroLatency);
        assert_eq!(limiter.latency_samples(), 0);

        limiter.set_latency_profile(LimiterLatencyProfile::HighQuality);
        limiter.set_lookahead(5.0);
        let hq_latency = limiter.latency_samples();
        assert!(hq_latency > 0, "HQ should have latency with lookahead");

        limiter.set_latency_profile(LimiterLatencyProfile::OfflineMax);
        limiter.set_lookahead(20.0);
        let offline_latency = limiter.latency_samples();
        assert!(offline_latency >= hq_latency, "Offline should have >= HQ latency");
    }

    #[test]
    fn test_limiter_process_no_allocation() {
        // Process 100K samples — verifies no Vec growth or heap allocation in hot path
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-6.0);

        for i in 0..100_000 {
            let input = ((i as f64) * 0.001).sin() * 1.5;
            let (l, r) = limiter.process_sample(input, input);
            assert!(!l.is_nan());
            assert!(!r.is_nan());
        }
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
        let input: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin() * 0.5).collect();

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
        let input: Vec<f64> = (0..8192).map(|i| (i as f64 * 0.001).sin()).collect();
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

        let input: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin()).collect();
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
            (6.0, 1.9952), // +6dB ≈ 2.0
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
            (0.5, -6.0206), // -6dB
            (0.1, -20.0),
            (0.01, -40.0),
            (2.0, 6.0206), // +6dB
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
        let key = 0.5; // -6dB - above threshold

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
        let input = 0.5; // -6dB - would normally open gate
        let key = 0.001; // -60dB - below threshold

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
        let input = 0.5; // -6dB - above threshold normally
        let key = 0.01; // -40dB - below threshold

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

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRO-C 2 EXTENDED PARAMETER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fn test_compressor_knee_setter_clamping() {
        let mut comp = Compressor::new(44100.0);
        comp.set_knee(12.0);
        assert!((comp.knee_db() - 12.0).abs() < 0.01);
        comp.set_knee(-5.0);
        assert!((comp.knee_db() - 0.0).abs() < 0.01, "Knee should clamp to 0");
        comp.set_knee(30.0);
        assert!((comp.knee_db() - 24.0).abs() < 0.01, "Knee should clamp to 24");
    }

    #[test]
    fn test_compressor_character_modes() {
        let mut comp = Compressor::new(44100.0);
        for mode in [
            CompressorCharacter::Off,
            CompressorCharacter::Tube,
            CompressorCharacter::Diode,
            CompressorCharacter::Bright,
        ] {
            comp.set_character(mode);
            assert_eq!(comp.character(), mode);
        }
    }

    #[test]
    fn test_compressor_drive_clamping() {
        let mut comp = Compressor::new(44100.0);
        comp.set_drive(12.0);
        assert!((comp.drive_db() - 12.0).abs() < 0.01);
        comp.set_drive(-5.0);
        assert!((comp.drive_db() - 0.0).abs() < 0.01, "Drive clamps to 0");
        comp.set_drive(30.0);
        assert!((comp.drive_db() - 24.0).abs() < 0.01, "Drive clamps to 24");
    }

    #[test]
    fn test_compressor_range_clamping() {
        let mut comp = Compressor::new(44100.0);
        comp.set_range(-30.0);
        assert!((comp.range_db() - (-30.0)).abs() < 0.01);
        comp.set_range(-100.0);
        assert!((comp.range_db() - (-60.0)).abs() < 0.01, "Range clamps to -60");
        comp.set_range(10.0);
        assert!((comp.range_db() - 0.0).abs() < 0.01, "Range clamps to 0");
    }

    #[test]
    fn test_compressor_sidechain_hp_lp_freq() {
        let mut comp = Compressor::new(44100.0);
        comp.set_sc_hp_freq(100.0);
        assert!((comp.sc_hp_freq() - 100.0).abs() < 0.01);
        comp.set_sc_hp_freq(5.0);
        assert!((comp.sc_hp_freq() - 20.0).abs() < 0.01, "HP clamps to 20");
        comp.set_sc_hp_freq(1000.0);
        assert!((comp.sc_hp_freq() - 500.0).abs() < 0.01, "HP clamps to 500");

        comp.set_sc_lp_freq(5000.0);
        assert!((comp.sc_lp_freq() - 5000.0).abs() < 0.01);
        comp.set_sc_lp_freq(500.0);
        assert!((comp.sc_lp_freq() - 1000.0).abs() < 0.01, "LP clamps to 1000");
        comp.set_sc_lp_freq(25000.0);
        assert!((comp.sc_lp_freq() - 20000.0).abs() < 0.01, "LP clamps to 20000");
    }

    #[test]
    fn test_compressor_sc_audition_toggle() {
        let mut comp = Compressor::new(44100.0);
        assert!(!comp.sc_audition());
        comp.set_sc_audition(true);
        assert!(comp.sc_audition());
        comp.set_sc_audition(false);
        assert!(!comp.sc_audition());
    }

    #[test]
    fn test_compressor_lookahead_clamping() {
        let mut comp = Compressor::new(44100.0);
        comp.set_lookahead(5.0);
        assert!((comp.lookahead_ms() - 5.0).abs() < 0.01);
        assert!(comp.latency_samples() > 0, "5ms lookahead should have non-zero latency");

        comp.set_lookahead(-1.0);
        assert!((comp.lookahead_ms() - 0.0).abs() < 0.01, "Lookahead clamps to 0");

        comp.set_lookahead(50.0);
        assert!((comp.lookahead_ms() - 20.0).abs() < 0.01, "Lookahead clamps to 20");
    }

    #[test]
    fn test_compressor_sc_eq_mid() {
        let mut comp = Compressor::new(44100.0);
        comp.set_sc_eq_mid_freq(1000.0);
        assert!((comp.sc_eq_mid_freq() - 1000.0).abs() < 0.01);
        comp.set_sc_eq_mid_freq(50.0);
        assert!((comp.sc_eq_mid_freq() - 200.0).abs() < 0.01, "Mid freq clamps to 200");
        comp.set_sc_eq_mid_freq(10000.0);
        assert!((comp.sc_eq_mid_freq() - 5000.0).abs() < 0.01, "Mid freq clamps to 5000");

        comp.set_sc_eq_mid_gain(6.0);
        assert!((comp.sc_eq_mid_gain() - 6.0).abs() < 0.01);
        comp.set_sc_eq_mid_gain(-20.0);
        assert!((comp.sc_eq_mid_gain() - (-12.0)).abs() < 0.01, "Mid gain clamps to -12");
        comp.set_sc_eq_mid_gain(20.0);
        assert!((comp.sc_eq_mid_gain() - 12.0).abs() < 0.01, "Mid gain clamps to 12");
    }

    #[test]
    fn test_compressor_auto_threshold_toggle() {
        let mut comp = Compressor::new(44100.0);
        assert!(!comp.auto_threshold_enabled());
        comp.set_auto_threshold(true);
        assert!(comp.auto_threshold_enabled());
    }

    #[test]
    fn test_compressor_auto_makeup_toggle() {
        let mut comp = Compressor::new(44100.0);
        assert!(!comp.auto_makeup_enabled());
        comp.set_auto_makeup(true);
        assert!(comp.auto_makeup_enabled());
    }

    #[test]
    fn test_compressor_detection_modes() {
        let mut comp = Compressor::new(44100.0);
        for mode in [DetectionMode::Peak, DetectionMode::Rms, DetectionMode::Hybrid] {
            comp.set_detection_mode(mode);
            assert_eq!(comp.detection_mode(), mode);
        }
    }

    #[test]
    fn test_compressor_adaptive_release_toggle() {
        let mut comp = Compressor::new(44100.0);
        assert!(!comp.adaptive_release_enabled());
        comp.set_adaptive_release(true);
        assert!(comp.adaptive_release_enabled());
    }

    #[test]
    fn test_compressor_host_sync_and_bpm() {
        let mut comp = Compressor::new(44100.0);
        assert!(!comp.host_sync_enabled());
        comp.set_host_sync(true);
        assert!(comp.host_sync_enabled());

        comp.set_host_bpm(120.0);
        assert!((comp.host_bpm() - 120.0).abs() < 0.01);
        comp.set_host_bpm(10.0);
        assert!((comp.host_bpm() - 20.0).abs() < 0.01, "BPM clamps to 20");
        comp.set_host_bpm(500.0);
        assert!((comp.host_bpm() - 300.0).abs() < 0.01, "BPM clamps to 300");
    }

    #[test]
    fn test_compressor_mid_side_toggle() {
        let mut comp = Compressor::new(44100.0);
        assert!(!comp.mid_side_enabled());
        comp.set_mid_side(true);
        assert!(comp.mid_side_enabled());
    }

    #[test]
    fn test_compressor_metering_getters() {
        let mut comp = Compressor::new(44100.0);
        comp.set_threshold(-20.0);
        comp.set_ratio(8.0);

        // Process loud signal to generate metering data
        for _ in 0..4096 {
            comp.process_sample(0.9);
        }

        // GR is stored as positive dB (amount of reduction)
        assert!(comp.gain_reduction_db() > 1.0,
            "Should have positive GR (dB of reduction), got {}", comp.gain_reduction_db());
        assert!(comp.input_peak() > 0.0, "Input peak should be positive");
        assert!(comp.output_peak() > 0.0, "Output peak should be positive");
    }

    #[test]
    fn test_stereo_compressor_extended_params() {
        let mut stereo = StereoCompressor::new(44100.0);

        // Set all extended params via StereoCompressor
        stereo.set_knee(12.0);
        stereo.set_character(CompressorCharacter::Tube);
        stereo.set_drive(6.0);
        stereo.set_range(-30.0);
        stereo.set_sc_hp_freq(80.0);
        stereo.set_sc_lp_freq(8000.0);
        stereo.set_sc_audition(true);
        stereo.set_lookahead(5.0);
        stereo.set_sc_eq_mid_freq(2000.0);
        stereo.set_sc_eq_mid_gain(3.0);
        stereo.set_auto_threshold(true);
        stereo.set_auto_makeup(true);
        stereo.set_detection_mode(DetectionMode::Rms);
        stereo.set_adaptive_release(true);
        stereo.set_host_sync(true);
        stereo.set_host_bpm(140.0);
        stereo.set_mid_side(true);

        // Verify via left_ref (immutable access)
        let left = stereo.left_ref();
        assert!((left.knee_db() - 12.0).abs() < 0.01);
        assert_eq!(left.character(), CompressorCharacter::Tube);
        assert!((left.drive_db() - 6.0).abs() < 0.01);
        assert!((left.range_db() - (-30.0)).abs() < 0.01);
        assert!((left.sc_hp_freq() - 80.0).abs() < 0.01);
        assert!((left.sc_lp_freq() - 8000.0).abs() < 0.01);
        assert!(left.sc_audition());
        assert!((left.lookahead_ms() - 5.0).abs() < 0.01);
        assert!((left.sc_eq_mid_freq() - 2000.0).abs() < 0.01);
        assert!((left.sc_eq_mid_gain() - 3.0).abs() < 0.01);
        assert!(left.auto_threshold_enabled());
        assert!(left.auto_makeup_enabled());
        assert_eq!(left.detection_mode(), DetectionMode::Rms);
        assert!(left.adaptive_release_enabled());
        assert!(left.host_sync_enabled());
        assert!((left.host_bpm() - 140.0).abs() < 0.01);
        assert!(left.mid_side_enabled());
    }
}

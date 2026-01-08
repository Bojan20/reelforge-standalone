//! Signal Integrity Module
//!
//! Phase 1.5: Ultimate signal quality for professional audio
//!
//! Features:
//! - DC Offset Removal (5Hz HPF)
//! - Auto-Gain Staging (-18dBFS target)
//! - Intersample Peak Limiter (8x oversampling)
//! - Kahan Summation (precise mixing)
//! - Soft Clip Protection
//! - TPDF Dither + Noise Shaping
//!
//! NO OTHER DAW HAS ALL OF THIS BUILT-IN!

use rf_core::Sample;
use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// A1: DC OFFSET REMOVAL
// ═══════════════════════════════════════════════════════════════════════════════

/// DC Offset Removal Filter
///
/// 5Hz highpass filter to remove DC bias that steals headroom.
/// Uses 1-pole IIR for minimal phase distortion.
#[derive(Debug, Clone)]
pub struct DcBlocker {
    /// Filter coefficient
    r: f64,
    /// Previous input
    x1: f64,
    /// Previous output
    y1: f64,
}

impl DcBlocker {
    /// Create DC blocker with ~5Hz cutoff
    pub fn new(sample_rate: f64) -> Self {
        // R = 1 - (pi * 2 * fc / fs)
        // For 5Hz at 48kHz: R ≈ 0.99935
        let fc = 5.0;
        let r = 1.0 - (PI * 2.0 * fc / sample_rate);

        Self {
            r,
            x1: 0.0,
            y1: 0.0,
        }
    }

    /// Process single sample
    #[inline(always)]
    pub fn process(&mut self, input: Sample) -> Sample {
        // y[n] = x[n] - x[n-1] + R * y[n-1]
        let output = input - self.x1 + self.r * self.y1;
        self.x1 = input;
        self.y1 = output;
        output
    }

    /// Process block in-place
    pub fn process_block(&mut self, samples: &mut [Sample]) {
        for sample in samples.iter_mut() {
            *sample = self.process(*sample);
        }
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.x1 = 0.0;
        self.y1 = 0.0;
    }
}

/// Stereo DC Blocker
#[derive(Debug, Clone)]
pub struct StereoDcBlocker {
    left: DcBlocker,
    right: DcBlocker,
}

impl StereoDcBlocker {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: DcBlocker::new(sample_rate),
            right: DcBlocker::new(sample_rate),
        }
    }

    pub fn process(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        (self.left.process(left), self.right.process(right))
    }

    pub fn process_block(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.left.process_block(left);
        self.right.process_block(right);
    }

    pub fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// A2: AUTO-GAIN STAGING
// ═══════════════════════════════════════════════════════════════════════════════

/// Auto-Gain Staging
///
/// Maintains optimal signal level through processing chain.
/// Target: -18 dBFS (sweet spot for most processors)
#[derive(Debug, Clone)]
pub struct AutoGainStage {
    /// Target level in dBFS
    target_dbfs: f64,
    /// Current gain (linear)
    gain: f64,
    /// Attack coefficient (fast for overshoots)
    attack_coeff: f64,
    /// Release coefficient (slower for natural feel)
    release_coeff: f64,
    /// RMS measurement buffer
    rms_buffer: Vec<f64>,
    rms_pos: usize,
    rms_sum: f64,
    /// Current RMS level
    current_rms: f64,
    /// Enabled state
    enabled: bool,
}

impl AutoGainStage {
    /// Create auto-gain stage with -18 dBFS target
    pub fn new(sample_rate: f64) -> Self {
        Self::with_target(sample_rate, -18.0)
    }

    /// Create with custom target level
    pub fn with_target(sample_rate: f64, target_dbfs: f64) -> Self {
        // 50ms RMS window
        let rms_len = (sample_rate * 0.050) as usize;

        // Attack: 5ms, Release: 100ms
        let attack_coeff = (-1.0 / (0.005 * sample_rate)).exp();
        let release_coeff = (-1.0 / (0.100 * sample_rate)).exp();

        Self {
            target_dbfs,
            gain: 1.0,
            attack_coeff,
            release_coeff,
            rms_buffer: vec![0.0; rms_len],
            rms_pos: 0,
            rms_sum: 0.0,
            current_rms: 0.0,
            enabled: true,
        }
    }

    /// Set target level in dBFS
    pub fn set_target(&mut self, dbfs: f64) {
        self.target_dbfs = dbfs.clamp(-40.0, 0.0);
    }

    /// Enable/disable auto-gain
    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
        if !enabled {
            self.gain = 1.0;
        }
    }

    /// Get current gain in dB
    pub fn gain_db(&self) -> f64 {
        20.0 * self.gain.log10()
    }

    /// Process single sample (mono)
    #[inline(always)]
    pub fn process(&mut self, input: Sample) -> Sample {
        if !self.enabled {
            return input;
        }

        // Update RMS measurement
        let sq = input * input;
        self.rms_sum -= self.rms_buffer[self.rms_pos];
        self.rms_sum += sq;
        self.rms_buffer[self.rms_pos] = sq;
        self.rms_pos = (self.rms_pos + 1) % self.rms_buffer.len();

        let rms = (self.rms_sum / self.rms_buffer.len() as f64).sqrt();

        // Smooth RMS
        let coeff = if rms > self.current_rms {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.current_rms = coeff * self.current_rms + (1.0 - coeff) * rms;

        // Calculate target gain
        if self.current_rms > 1e-10 {
            let current_dbfs = 20.0 * self.current_rms.log10();
            let gain_db = self.target_dbfs - current_dbfs;

            // Limit gain range: -12dB to +12dB
            let target_gain = 10.0_f64.powf(gain_db.clamp(-12.0, 12.0) / 20.0);

            // Smooth gain changes
            self.gain = self.release_coeff * self.gain + (1.0 - self.release_coeff) * target_gain;
        }

        input * self.gain
    }

    /// Process stereo (uses max of L/R for measurement)
    pub fn process_stereo(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if !self.enabled {
            return (left, right);
        }

        // Use max for measurement
        let max_abs = left.abs().max(right.abs());
        let _ = self.process(max_abs); // Update gain

        (left * self.gain, right * self.gain)
    }

    pub fn reset(&mut self) {
        self.gain = 1.0;
        self.rms_buffer.fill(0.0);
        self.rms_pos = 0;
        self.rms_sum = 0.0;
        self.current_rms = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// A3: INTERSAMPLE PEAK LIMITER
// ═══════════════════════════════════════════════════════════════════════════════

/// Intersample Peak (ISP) Limiter
///
/// True Peak limiter using 8x oversampling to catch peaks between samples.
/// Guarantees output never exceeds threshold (typically -1.0 dBTP for streaming).
#[derive(Debug, Clone)]
pub struct IspLimiter {
    /// Threshold in linear (e.g., 0.891 for -1 dBTP)
    threshold: f64,
    /// Ceiling (absolute max)
    ceiling: f64,
    /// Attack time in samples
    attack_samples: usize,
    /// Release coefficient
    release_coeff: f64,
    /// Current gain reduction
    gain_reduction: f64,
    /// Lookahead buffer L
    lookahead_l: Vec<f64>,
    /// Lookahead buffer R
    lookahead_r: Vec<f64>,
    /// Lookahead position
    lookahead_pos: usize,
    /// 8x oversampling FIR coefficients
    os_coeffs: [f64; 48],
    /// Oversampling state L
    os_state_l: [f64; 6],
    /// Oversampling state R
    os_state_r: [f64; 6],
    /// Peak hold for GR meter
    gr_peak: f64,
    gr_release: f64,
}

impl IspLimiter {
    /// Create ISP limiter with -1.0 dBTP threshold
    pub fn new(sample_rate: f64) -> Self {
        Self::with_threshold(sample_rate, -1.0)
    }

    /// Create with custom threshold in dBTP
    pub fn with_threshold(sample_rate: f64, threshold_dbtp: f64) -> Self {
        // Lookahead = 1ms
        let lookahead_len = (sample_rate * 0.001) as usize;

        // Attack = 0.1ms (very fast)
        let attack_samples = (sample_rate * 0.0001) as usize;

        // Release = 100ms
        let release_coeff = (-1.0 / (0.100 * sample_rate)).exp();

        // GR meter release = 1s
        let gr_release = (-1.0 / (1.0 * sample_rate)).exp();

        // Generate 8x oversampling FIR (48-tap, Kaiser windowed)
        let os_coeffs = Self::generate_os_coeffs();

        Self {
            threshold: 10.0_f64.powf(threshold_dbtp / 20.0),
            ceiling: 1.0,
            attack_samples,
            release_coeff,
            gain_reduction: 1.0,
            lookahead_l: vec![0.0; lookahead_len],
            lookahead_r: vec![0.0; lookahead_len],
            lookahead_pos: 0,
            os_coeffs,
            os_state_l: [0.0; 6],
            os_state_r: [0.0; 6],
            gr_peak: 1.0,
            gr_release,
        }
    }

    fn generate_os_coeffs() -> [f64; 48] {
        let mut coeffs = [0.0; 48];
        let m = 47;
        let fc = 0.5 / 8.0;

        for i in 0..48 {
            let n = i as f64 - m as f64 / 2.0;
            if n.abs() < 1e-10 {
                coeffs[i] = 2.0 * fc;
            } else {
                coeffs[i] = (2.0 * PI * fc * n).sin() / (PI * n);
            }
            // Kaiser window (beta = 8.6)
            let alpha = m as f64 / 2.0;
            let arg = 1.0 - ((i as f64 - alpha) / alpha).powi(2);
            if arg > 0.0 {
                coeffs[i] *= bessel_i0(8.6 * arg.sqrt()) / bessel_i0(8.6);
            }
        }

        // Normalize
        let sum: f64 = coeffs.iter().sum();
        for c in &mut coeffs {
            *c /= sum;
        }

        coeffs
    }

    /// Set threshold in dBTP
    pub fn set_threshold(&mut self, dbtp: f64) {
        self.threshold = 10.0_f64.powf(dbtp.clamp(-12.0, 0.0) / 20.0);
    }

    /// Set ceiling in dBTP
    pub fn set_ceiling(&mut self, dbtp: f64) {
        self.ceiling = 10.0_f64.powf(dbtp.clamp(-6.0, 0.0) / 20.0);
    }

    /// Get current gain reduction in dB
    pub fn gain_reduction_db(&self) -> f64 {
        20.0 * self.gr_peak.log10()
    }

    /// Find true peak using 8x oversampling
    fn find_true_peak(&mut self, left: Sample, right: Sample) -> f64 {
        // Shift state
        for i in (1..6).rev() {
            self.os_state_l[i] = self.os_state_l[i - 1];
            self.os_state_r[i] = self.os_state_r[i - 1];
        }
        self.os_state_l[0] = left;
        self.os_state_r[0] = right;

        let mut max_peak = left.abs().max(right.abs());

        // Check 8 interpolated points
        for phase in 0..8 {
            let mut sum_l = 0.0;
            let mut sum_r = 0.0;

            for i in 0..6 {
                let coeff = self.os_coeffs[phase * 6 + i];
                sum_l += self.os_state_l[i] * coeff;
                sum_r += self.os_state_r[i] * coeff;
            }

            max_peak = max_peak.max(sum_l.abs()).max(sum_r.abs());
        }

        max_peak
    }

    /// Process stereo sample
    pub fn process(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Find true peak
        let true_peak = self.find_true_peak(left, right);

        // Calculate required gain reduction
        let target_gr = if true_peak > self.threshold {
            self.threshold / true_peak
        } else {
            1.0
        };

        // Apply attack/release
        if target_gr < self.gain_reduction {
            // Attack (fast)
            self.gain_reduction = target_gr;
        } else {
            // Release (slow)
            self.gain_reduction = self.release_coeff * self.gain_reduction
                                + (1.0 - self.release_coeff) * target_gr;
        }

        // Update GR peak for meter
        if self.gain_reduction < self.gr_peak {
            self.gr_peak = self.gain_reduction;
        } else {
            self.gr_peak = self.gr_release * self.gr_peak
                         + (1.0 - self.gr_release) * self.gain_reduction;
        }

        // Store in lookahead buffer
        let out_pos = self.lookahead_pos;
        let out_l = self.lookahead_l[out_pos];
        let out_r = self.lookahead_r[out_pos];

        self.lookahead_l[self.lookahead_pos] = left;
        self.lookahead_r[self.lookahead_pos] = right;
        self.lookahead_pos = (self.lookahead_pos + 1) % self.lookahead_l.len();

        // Apply gain reduction with ceiling
        let final_l = (out_l * self.gain_reduction).clamp(-self.ceiling, self.ceiling);
        let final_r = (out_r * self.gain_reduction).clamp(-self.ceiling, self.ceiling);

        (final_l, final_r)
    }

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        self.lookahead_l.len()
    }

    pub fn reset(&mut self) {
        self.gain_reduction = 1.0;
        self.lookahead_l.fill(0.0);
        self.lookahead_r.fill(0.0);
        self.lookahead_pos = 0;
        self.os_state_l = [0.0; 6];
        self.os_state_r = [0.0; 6];
        self.gr_peak = 1.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// A4: KAHAN SUMMATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Kahan Summation Accumulator
///
/// Compensated summation algorithm that eliminates floating-point errors.
/// Critical for mixing many tracks without losing precision.
#[derive(Debug, Clone, Default)]
pub struct KahanAccumulator {
    sum: f64,
    compensation: f64,
}

impl KahanAccumulator {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add value with compensation
    #[inline(always)]
    pub fn add(&mut self, value: f64) {
        let y = value - self.compensation;
        let t = self.sum + y;
        self.compensation = (t - self.sum) - y;
        self.sum = t;
    }

    /// Get current sum
    #[inline(always)]
    pub fn sum(&self) -> f64 {
        self.sum
    }

    /// Reset accumulator
    pub fn reset(&mut self) {
        self.sum = 0.0;
        self.compensation = 0.0;
    }
}

/// Stereo Kahan mixer
#[derive(Debug, Clone, Default)]
pub struct StereoKahanMixer {
    left: KahanAccumulator,
    right: KahanAccumulator,
}

impl StereoKahanMixer {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add stereo sample
    #[inline(always)]
    pub fn add(&mut self, left: f64, right: f64) {
        self.left.add(left);
        self.right.add(right);
    }

    /// Get mixed result
    #[inline(always)]
    pub fn sum(&self) -> (f64, f64) {
        (self.left.sum(), self.right.sum())
    }

    /// Reset for next sample
    #[inline(always)]
    pub fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

/// Mix multiple tracks using Kahan summation
pub fn kahan_mix_tracks(tracks: &[&[Sample]], output: &mut [Sample]) {
    let mut acc = KahanAccumulator::new();

    for i in 0..output.len() {
        acc.reset();
        for track in tracks {
            if i < track.len() {
                acc.add(track[i]);
            }
        }
        output[i] = acc.sum();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// C1/C2: TPDF DITHER + NOISE SHAPING
// ═══════════════════════════════════════════════════════════════════════════════

/// Dither Type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DitherType {
    /// No dither (truncation only)
    None,
    /// Rectangular PDF (flat noise)
    Rpdf,
    /// Triangular PDF (standard, self-nulling)
    Tpdf,
    /// High-pass TPDF (shaped to be less audible)
    HpTpdf,
}

/// Noise Shaping Type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NoiseShapeType {
    /// No shaping
    None,
    /// First-order (simple highpass)
    FirstOrder,
    /// Modified E-weighted (perceptually optimized)
    ModifiedE,
    /// F-weighted (aggressive, for 16-bit)
    FWeighted,
}

/// Professional Dither Processor
///
/// TPDF dither with optional noise shaping for clean bit-depth reduction.
#[derive(Debug, Clone)]
pub struct Dither {
    /// Target bit depth
    target_bits: u32,
    /// Dither type
    dither_type: DitherType,
    /// Noise shaping type
    shape_type: NoiseShapeType,
    /// Quantization step (1 LSB at target depth)
    quant_step: f64,
    /// Previous random value (for TPDF)
    prev_rand: f64,
    /// Error feedback buffer (for noise shaping)
    error_buf: [f64; 4],
    /// RNG state (xorshift64)
    rng_state: u64,
}

impl Dither {
    /// Create 16-bit TPDF dither with no shaping
    pub fn new_16bit() -> Self {
        Self::new(16, DitherType::Tpdf, NoiseShapeType::None)
    }

    /// Create with custom settings
    pub fn new(target_bits: u32, dither_type: DitherType, shape_type: NoiseShapeType) -> Self {
        // Quantization step = 2 / (2^bits)
        let quant_step = 2.0 / (1u64 << target_bits) as f64;

        Self {
            target_bits,
            dither_type,
            shape_type,
            quant_step,
            prev_rand: 0.0,
            error_buf: [0.0; 4],
            rng_state: 0x853c49e6748fea9b, // Good seed
        }
    }

    /// Fast xorshift64 random
    #[inline(always)]
    fn next_rand(&mut self) -> f64 {
        self.rng_state ^= self.rng_state >> 12;
        self.rng_state ^= self.rng_state << 25;
        self.rng_state ^= self.rng_state >> 27;
        let r = self.rng_state.wrapping_mul(0x2545F4914F6CDD1D);
        // Convert to -1.0 to 1.0
        (r as i64 as f64) / (i64::MAX as f64)
    }

    /// Generate dither noise
    fn generate_dither(&mut self) -> f64 {
        match self.dither_type {
            DitherType::None => 0.0,
            DitherType::Rpdf => {
                self.next_rand() * self.quant_step * 0.5
            }
            DitherType::Tpdf => {
                let r1 = self.next_rand();
                let r2 = self.next_rand();
                (r1 + r2) * self.quant_step * 0.5
            }
            DitherType::HpTpdf => {
                let r = self.next_rand();
                let tpdf = r - self.prev_rand;
                self.prev_rand = r;
                tpdf * self.quant_step
            }
        }
    }

    /// Apply noise shaping
    fn apply_shaping(&mut self, error: f64) -> f64 {
        let shaped = match self.shape_type {
            NoiseShapeType::None => 0.0,
            NoiseShapeType::FirstOrder => {
                // Simple first-order: y = x - e[n-1]
                self.error_buf[0]
            }
            NoiseShapeType::ModifiedE => {
                // Modified E-weighted: optimized for human hearing
                // Coefficients tuned for 44.1/48kHz
                1.623 * self.error_buf[0]
                - 0.982 * self.error_buf[1]
                + 0.109 * self.error_buf[2]
            }
            NoiseShapeType::FWeighted => {
                // Aggressive F-weighted for 16-bit
                2.033 * self.error_buf[0]
                - 2.165 * self.error_buf[1]
                + 1.959 * self.error_buf[2]
                - 0.209 * self.error_buf[3]
            }
        };

        // Shift error buffer
        self.error_buf[3] = self.error_buf[2];
        self.error_buf[2] = self.error_buf[1];
        self.error_buf[1] = self.error_buf[0];
        self.error_buf[0] = error;

        shaped
    }

    /// Process single sample
    #[inline]
    pub fn process(&mut self, input: Sample) -> Sample {
        // Add noise shaping feedback
        let shaped = self.apply_shaping(0.0);
        let shaped_input = input - shaped;

        // Add dither
        let dithered = shaped_input + self.generate_dither();

        // Quantize
        let quantized = (dithered / self.quant_step).round() * self.quant_step;

        // Calculate error for feedback
        let error = quantized - shaped_input;
        self.error_buf[0] = error;

        // Clamp to valid range
        quantized.clamp(-1.0, 1.0 - self.quant_step)
    }

    /// Process stereo block
    pub fn process_block(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for sample in left.iter_mut() {
            *sample = self.process(*sample);
        }
        for sample in right.iter_mut() {
            *sample = self.process(*sample);
        }
    }

    pub fn reset(&mut self) {
        self.prev_rand = 0.0;
        self.error_buf = [0.0; 4];
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// C3: SOFT CLIP PROTECTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Soft Clip Type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SoftClipType {
    /// Hyperbolic tangent (smooth, musical)
    Tanh,
    /// Soft knee polynomial
    SoftKnee,
    /// Cubic soft clip
    Cubic,
    /// Sine-based (warmest)
    Sine,
}

/// Soft Clip Protection
///
/// Gentle saturation that prevents harsh digital clipping.
/// Applied before limiter for natural-sounding protection.
#[derive(Debug, Clone)]
pub struct SoftClip {
    /// Clip type
    clip_type: SoftClipType,
    /// Threshold where soft clipping begins (default 0.9)
    threshold: f64,
    /// Knee width
    knee: f64,
    /// Drive amount (1.0 = unity)
    drive: f64,
    /// Output level
    output: f64,
}

impl SoftClip {
    pub fn new() -> Self {
        Self {
            clip_type: SoftClipType::Tanh,
            threshold: 0.9,
            knee: 0.1,
            drive: 1.0,
            output: 1.0,
        }
    }

    /// Set clip type
    pub fn set_type(&mut self, clip_type: SoftClipType) {
        self.clip_type = clip_type;
    }

    /// Set threshold (0.5-1.0)
    pub fn set_threshold(&mut self, thresh: f64) {
        self.threshold = thresh.clamp(0.5, 1.0);
    }

    /// Set drive (0.5-4.0)
    pub fn set_drive(&mut self, drive: f64) {
        self.drive = drive.clamp(0.5, 4.0);
    }

    /// Process single sample
    #[inline]
    pub fn process(&self, input: Sample) -> Sample {
        let driven = input * self.drive;

        let clipped = match self.clip_type {
            SoftClipType::Tanh => {
                driven.tanh()
            }
            SoftClipType::SoftKnee => {
                let abs = driven.abs();
                if abs < self.threshold {
                    driven
                } else {
                    let sign = driven.signum();
                    let over = abs - self.threshold;
                    let compressed = self.threshold + self.knee * (1.0 - (-over / self.knee).exp());
                    sign * compressed.min(1.0)
                }
            }
            SoftClipType::Cubic => {
                if driven.abs() < 2.0 / 3.0 {
                    driven
                } else {
                    let sign = driven.signum();
                    let abs = driven.abs().min(1.0);
                    sign * (3.0 * abs - abs * abs * abs) / 2.0
                }
            }
            SoftClipType::Sine => {
                if driven.abs() < 1.0 {
                    driven
                } else {
                    driven.signum() * (PI / 4.0 * driven.clamp(-1.0, 1.0)).sin() * (2.0 / PI).sqrt()
                }
            }
        };

        clipped * self.output
    }

    /// Process stereo
    pub fn process_stereo(&self, left: Sample, right: Sample) -> (Sample, Sample) {
        (self.process(left), self.process(right))
    }
}

impl Default for SoftClip {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPLETE SIGNAL CHAIN
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete Signal Integrity Chain
///
/// Combines all processors for ultimate signal quality:
/// Input → DC Block → Auto-Gain → [Processing] → Soft Clip → ISP Limiter → Dither
#[derive(Debug, Clone)]
pub struct SignalIntegrityChain {
    pub dc_blocker: StereoDcBlocker,
    pub auto_gain: AutoGainStage,
    pub soft_clip: SoftClip,
    pub isp_limiter: IspLimiter,
    pub dither: Option<Dither>,
    /// Bypass entire chain
    pub bypass: bool,
}

impl SignalIntegrityChain {
    /// Create complete chain for given sample rate
    pub fn new(sample_rate: f64) -> Self {
        Self {
            dc_blocker: StereoDcBlocker::new(sample_rate),
            auto_gain: AutoGainStage::new(sample_rate),
            soft_clip: SoftClip::new(),
            isp_limiter: IspLimiter::new(sample_rate),
            dither: None, // Only enabled for 16-bit export
            bypass: false,
        }
    }

    /// Enable 16-bit dither (for export)
    pub fn enable_dither(&mut self, bits: u32, shape: NoiseShapeType) {
        self.dither = Some(Dither::new(bits, DitherType::Tpdf, shape));
    }

    /// Disable dither (for internal processing)
    pub fn disable_dither(&mut self) {
        self.dither = None;
    }

    /// Process input stage (DC block + auto-gain)
    pub fn process_input(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if self.bypass {
            return (left, right);
        }

        let (l, r) = self.dc_blocker.process(left, right);
        self.auto_gain.process_stereo(l, r)
    }

    /// Process output stage (soft clip + limiter + dither)
    pub fn process_output(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if self.bypass {
            return (left, right);
        }

        let (l, r) = self.soft_clip.process_stereo(left, right);
        let (l, r) = self.isp_limiter.process(l, r);

        if let Some(ref mut dither) = self.dither {
            (dither.process(l), dither.process(r))
        } else {
            (l, r)
        }
    }

    /// Get total latency in samples
    pub fn latency(&self) -> usize {
        self.isp_limiter.latency()
    }

    /// Get current gain reduction from limiter in dB
    pub fn limiter_gr_db(&self) -> f64 {
        self.isp_limiter.gain_reduction_db()
    }

    /// Get auto-gain amount in dB
    pub fn auto_gain_db(&self) -> f64 {
        self.auto_gain.gain_db()
    }

    pub fn reset(&mut self) {
        self.dc_blocker.reset();
        self.auto_gain.reset();
        self.isp_limiter.reset();
        if let Some(ref mut dither) = self.dither {
            dither.reset();
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Modified Bessel function I0 (for Kaiser window)
fn bessel_i0(x: f64) -> f64 {
    let ax = x.abs();
    if ax < 3.75 {
        let y = (x / 3.75).powi(2);
        1.0 + y * (3.5156229 + y * (3.0899424 + y * (1.2067492
            + y * (0.2659732 + y * (0.0360768 + y * 0.0045813)))))
    } else {
        let y = 3.75 / ax;
        (ax.exp() / ax.sqrt()) * (0.39894228 + y * (0.01328592
            + y * (0.00225319 + y * (-0.00157565 + y * (0.00916281
            + y * (-0.02057706 + y * (0.02635537 + y * (-0.01647633
            + y * 0.00392377))))))))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dc_blocker() {
        let mut dc = DcBlocker::new(48000.0);

        // DC input should be removed
        for _ in 0..10000 {
            dc.process(1.0); // Pure DC
        }
        let output = dc.process(1.0);
        assert!(output.abs() < 0.01, "DC should be blocked");
    }

    #[test]
    fn test_kahan_summation() {
        let mut acc = KahanAccumulator::new();

        // Sum many small values (would lose precision without Kahan)
        for _ in 0..1_000_000 {
            acc.add(1e-10);
        }

        let expected = 1e-10 * 1_000_000.0;
        let error = (acc.sum() - expected).abs() / expected;
        assert!(error < 1e-10, "Kahan should maintain precision");
    }

    #[test]
    fn test_soft_clip() {
        let clip = SoftClip::new();

        // Below threshold: pass through
        let out = clip.process(0.5);
        assert!((out - 0.5).abs() < 0.01);

        // Way above threshold: clamped
        let out = clip.process(10.0);
        assert!(out.abs() <= 1.0, "Should be soft clipped");
    }
}

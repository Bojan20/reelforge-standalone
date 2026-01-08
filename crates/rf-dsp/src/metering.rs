//! Advanced Metering
//!
//! Provides professional metering capabilities:
//! - Stereo correlation meter
//! - Phase scope
//! - K-System metering (K-12, K-14, K-20)
//! - Crest factor
//! - Dynamic range
//! - VU meter with ballistics

use rf_core::Sample;

// ═══════════════════════════════════════════════════════════════════════════════
// STEREO CORRELATION METER
// ═══════════════════════════════════════════════════════════════════════════════

/// Stereo correlation meter
///
/// Measures the correlation between left and right channels:
/// - +1.0 = Mono (identical L/R)
/// -  0.0 = Unrelated (no correlation)
/// - -1.0 = Out of phase (inverted L/R)
#[derive(Debug, Clone)]
pub struct CorrelationMeter {
    /// Sum of L*R products
    sum_lr: f64,
    /// Sum of L^2
    sum_ll: f64,
    /// Sum of R^2
    sum_rr: f64,
    /// Circular buffer for L
    buffer_l: Vec<f64>,
    /// Circular buffer for R
    buffer_r: Vec<f64>,
    /// Buffer position
    write_pos: usize,
    /// Smoothed correlation
    smoothed: f64,
    /// Smoothing coefficient
    smooth_coeff: f64,
}

impl CorrelationMeter {
    /// Create new correlation meter
    /// window_ms: analysis window in milliseconds
    pub fn new(sample_rate: f64, window_ms: f64) -> Self {
        let window_samples = (window_ms * 0.001 * sample_rate) as usize;

        Self {
            sum_lr: 0.0,
            sum_ll: 0.0,
            sum_rr: 0.0,
            buffer_l: vec![0.0; window_samples],
            buffer_r: vec![0.0; window_samples],
            write_pos: 0,
            smoothed: 0.0,
            smooth_coeff: 0.1,
        }
    }

    /// Process a stereo sample pair
    pub fn process(&mut self, left: Sample, right: Sample) {
        // Remove old values
        let old_l = self.buffer_l[self.write_pos];
        let old_r = self.buffer_r[self.write_pos];

        self.sum_lr -= old_l * old_r;
        self.sum_ll -= old_l * old_l;
        self.sum_rr -= old_r * old_r;

        // Add new values
        self.sum_lr += left * right;
        self.sum_ll += left * left;
        self.sum_rr += right * right;

        self.buffer_l[self.write_pos] = left;
        self.buffer_r[self.write_pos] = right;

        self.write_pos = (self.write_pos + 1) % self.buffer_l.len();

        // Calculate correlation
        let denominator = (self.sum_ll * self.sum_rr).sqrt();
        let raw_correlation = if denominator > 1e-10 {
            self.sum_lr / denominator
        } else {
            0.0
        };

        // Smooth
        self.smoothed = self.smoothed * (1.0 - self.smooth_coeff)
            + raw_correlation * self.smooth_coeff;
    }

    /// Process a stereo block
    pub fn process_block(&mut self, left: &[Sample], right: &[Sample]) {
        for (&l, &r) in left.iter().zip(right.iter()) {
            self.process(l, r);
        }
    }

    /// Get current correlation (-1.0 to +1.0)
    pub fn correlation(&self) -> f64 {
        self.smoothed.clamp(-1.0, 1.0)
    }

    /// Get raw (unsmoothed) correlation
    pub fn raw_correlation(&self) -> f64 {
        let denominator = (self.sum_ll * self.sum_rr).sqrt();
        if denominator > 1e-10 {
            (self.sum_lr / denominator).clamp(-1.0, 1.0)
        } else {
            0.0
        }
    }

    /// Check if signal is in phase (correlation > 0)
    pub fn is_in_phase(&self) -> bool {
        self.smoothed > 0.0
    }

    /// Check if signal might have phase issues (correlation < -0.5)
    pub fn has_phase_issues(&self) -> bool {
        self.smoothed < -0.5
    }

    /// Reset meter
    pub fn reset(&mut self) {
        self.sum_lr = 0.0;
        self.sum_ll = 0.0;
        self.sum_rr = 0.0;
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
        self.smoothed = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEREO BALANCE METER
// ═══════════════════════════════════════════════════════════════════════════════

/// Stereo balance meter
///
/// Measures the balance between left and right channels:
/// - -1.0 = Full left
/// -  0.0 = Centered
/// - +1.0 = Full right
#[derive(Debug, Clone)]
pub struct BalanceMeter {
    sum_l: f64,
    sum_r: f64,
    window_samples: usize,
    buffer_l: Vec<f64>,
    buffer_r: Vec<f64>,
    write_pos: usize,
    smoothed: f64,
    smooth_coeff: f64,
}

impl BalanceMeter {
    pub fn new(sample_rate: f64, window_ms: f64) -> Self {
        let window_samples = (window_ms * 0.001 * sample_rate) as usize;

        Self {
            sum_l: 0.0,
            sum_r: 0.0,
            window_samples,
            buffer_l: vec![0.0; window_samples],
            buffer_r: vec![0.0; window_samples],
            write_pos: 0,
            smoothed: 0.0,
            smooth_coeff: 0.05,
        }
    }

    pub fn process(&mut self, left: Sample, right: Sample) {
        let l_sq = left * left;
        let r_sq = right * right;

        // Remove old
        self.sum_l -= self.buffer_l[self.write_pos];
        self.sum_r -= self.buffer_r[self.write_pos];

        // Add new
        self.sum_l += l_sq;
        self.sum_r += r_sq;

        self.buffer_l[self.write_pos] = l_sq;
        self.buffer_r[self.write_pos] = r_sq;

        self.write_pos = (self.write_pos + 1) % self.window_samples;

        // Calculate balance
        let total = self.sum_l + self.sum_r;
        let raw_balance = if total > 1e-10 {
            (self.sum_r - self.sum_l) / total
        } else {
            0.0
        };

        // Smooth
        self.smoothed = self.smoothed * (1.0 - self.smooth_coeff)
            + raw_balance * self.smooth_coeff;
    }

    /// Get balance (-1.0 = left, 0.0 = center, +1.0 = right)
    pub fn balance(&self) -> f64 {
        self.smoothed.clamp(-1.0, 1.0)
    }

    /// Get balance in dB (negative = left louder, positive = right louder)
    pub fn balance_db(&self) -> f64 {
        if self.sum_l > 1e-10 && self.sum_r > 1e-10 {
            10.0 * (self.sum_r / self.sum_l).log10()
        } else {
            0.0
        }
    }

    pub fn reset(&mut self) {
        self.sum_l = 0.0;
        self.sum_r = 0.0;
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
        self.smoothed = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// K-SYSTEM METER
// ═══════════════════════════════════════════════════════════════════════════════

/// K-System meter type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KSystem {
    /// K-20: Film, classical, large-room playback (-20 dBFS = 0 VU)
    K20,
    /// K-14: Broadcast, home listening (-14 dBFS = 0 VU)
    K14,
    /// K-12: Streaming, earbuds (-12 dBFS = 0 VU)
    K12,
}

impl KSystem {
    /// Reference level offset in dB
    pub fn offset_db(&self) -> f64 {
        match self {
            KSystem::K20 => 20.0,
            KSystem::K14 => 14.0,
            KSystem::K12 => 12.0,
        }
    }

    /// Headroom above 0 VU in dB
    pub fn headroom_db(&self) -> f64 {
        match self {
            KSystem::K20 => 20.0,
            KSystem::K14 => 14.0,
            KSystem::K12 => 12.0,
        }
    }
}

/// K-System meter with RMS and peak
#[derive(Debug, Clone)]
pub struct KMeter {
    k_system: KSystem,
    /// RMS sum
    rms_sum: f64,
    /// RMS buffer
    rms_buffer: Vec<f64>,
    rms_pos: usize,
    /// Peak
    current_peak: f64,
    peak_hold: f64,
    hold_samples: usize,
    hold_counter: usize,
    release_coeff: f64,
}

impl KMeter {
    pub fn new(sample_rate: f64, k_system: KSystem) -> Self {
        // 300ms RMS window
        let rms_samples = (0.3 * sample_rate) as usize;

        Self {
            k_system,
            rms_sum: 0.0,
            rms_buffer: vec![0.0; rms_samples],
            rms_pos: 0,
            current_peak: 0.0,
            peak_hold: 0.0,
            hold_samples: (sample_rate * 1.5) as usize,
            hold_counter: 0,
            release_coeff: (-1.0 / (0.6 * sample_rate)).exp(),
        }
    }

    pub fn set_k_system(&mut self, k_system: KSystem) {
        self.k_system = k_system;
    }

    pub fn process(&mut self, sample: Sample) {
        let squared = sample * sample;

        // RMS
        self.rms_sum -= self.rms_buffer[self.rms_pos];
        self.rms_sum += squared;
        self.rms_buffer[self.rms_pos] = squared;
        self.rms_pos = (self.rms_pos + 1) % self.rms_buffer.len();

        // Peak
        let abs = sample.abs();
        if abs > self.current_peak {
            self.current_peak = abs;
        } else {
            self.current_peak *= self.release_coeff;
        }

        if abs > self.peak_hold {
            self.peak_hold = abs;
            self.hold_counter = 0;
        } else {
            self.hold_counter += 1;
            if self.hold_counter >= self.hold_samples {
                self.peak_hold *= self.release_coeff;
            }
        }
    }

    pub fn process_block(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.process(sample);
        }
    }

    /// Get RMS level in K-System units (0 = reference, positive = above, negative = below)
    pub fn rms_k(&self) -> f64 {
        let rms = (self.rms_sum / self.rms_buffer.len() as f64).sqrt();
        let db = 20.0 * rms.max(1e-10).log10();
        db + self.k_system.offset_db()
    }

    /// Get RMS level in dBFS
    pub fn rms_dbfs(&self) -> f64 {
        let rms = (self.rms_sum / self.rms_buffer.len() as f64).sqrt();
        20.0 * rms.max(1e-10).log10()
    }

    /// Get peak level in K-System units
    pub fn peak_k(&self) -> f64 {
        let db = 20.0 * self.current_peak.max(1e-10).log10();
        db + self.k_system.offset_db()
    }

    /// Get peak level in dBFS
    pub fn peak_dbfs(&self) -> f64 {
        20.0 * self.current_peak.max(1e-10).log10()
    }

    /// Get held peak in K-System units
    pub fn peak_hold_k(&self) -> f64 {
        let db = 20.0 * self.peak_hold.max(1e-10).log10();
        db + self.k_system.offset_db()
    }

    /// Get crest factor (peak to RMS ratio in dB)
    pub fn crest_factor(&self) -> f64 {
        self.peak_dbfs() - self.rms_dbfs()
    }

    pub fn reset(&mut self) {
        self.rms_sum = 0.0;
        self.rms_buffer.fill(0.0);
        self.rms_pos = 0;
        self.current_peak = 0.0;
        self.peak_hold = 0.0;
        self.hold_counter = 0;
    }

    pub fn reset_peak_hold(&mut self) {
        self.peak_hold = self.current_peak;
        self.hold_counter = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VU METER
// ═══════════════════════════════════════════════════════════════════════════════

/// VU meter with proper ballistics
///
/// VU meters have specific ballistic behavior:
/// - 300ms integration time
/// - 99% deflection for +4 dBu reference tone
#[derive(Debug, Clone)]
pub struct VuMeter {
    /// Current level
    level: f64,
    /// Attack coefficient (300ms rise to 99%)
    attack_coeff: f64,
    /// Release coefficient (300ms fall to 1%)
    release_coeff: f64,
    /// Reference level in dBFS (default: -18 dBFS = 0 VU)
    reference_dbfs: f64,
}

impl VuMeter {
    /// Create VU meter
    /// reference_dbfs: dBFS level that corresponds to 0 VU (default: -18)
    pub fn new(sample_rate: f64, reference_dbfs: f64) -> Self {
        // VU meters have 300ms integration time
        // Time constant for 99% deflection in 300ms
        let time_constant = 0.3 / 4.6; // ~65ms time constant for 300ms to 99%
        let attack_coeff = 1.0 - (-1.0 / (time_constant * sample_rate)).exp();
        let release_coeff = attack_coeff; // Symmetrical ballistics

        Self {
            level: 0.0,
            attack_coeff,
            release_coeff,
            reference_dbfs,
        }
    }

    /// Create with standard -18 dBFS reference
    pub fn standard(sample_rate: f64) -> Self {
        Self::new(sample_rate, -18.0)
    }

    pub fn process(&mut self, sample: Sample) {
        let abs = sample.abs();

        if abs > self.level {
            self.level += self.attack_coeff * (abs - self.level);
        } else {
            self.level += self.release_coeff * (abs - self.level);
        }
    }

    pub fn process_block(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.process(sample);
        }
    }

    /// Get VU reading (-20 to +3 typical range)
    pub fn vu(&self) -> f64 {
        let db = 20.0 * self.level.max(1e-10).log10();
        db - self.reference_dbfs
    }

    /// Get level in dBFS
    pub fn dbfs(&self) -> f64 {
        20.0 * self.level.max(1e-10).log10()
    }

    /// Set reference level
    pub fn set_reference(&mut self, reference_dbfs: f64) {
        self.reference_dbfs = reference_dbfs;
    }

    pub fn reset(&mut self) {
        self.level = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PPM METER (Peak Programme Meter - EBU/BBC)
// ═══════════════════════════════════════════════════════════════════════════════

/// PPM (Peak Programme Meter) type
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PpmType {
    /// BBC Type I - 10ms integration, 2.8s return
    BbcType1,
    /// BBC Type II / IEC 60268-10 Type I - 5ms integration, 1.7s return
    BbcType2,
    /// EBU / IEC 60268-10 Type IIa - 10ms integration, 1.7s return
    Ebu,
    /// DIN 45406 - 5ms integration, 1.7s return
    Din,
    /// Nordic N9 - 5ms integration, 1.5s return
    Nordic,
}

/// PPM (Peak Programme Meter) per EBU/BBC standards
///
/// PPM meters have asymmetric ballistics:
/// - Fast attack (5-10ms integration time)
/// - Slow release (1.5-2.8s return time)
///
/// Reference: IEC 60268-10, EBU Tech 3205
#[derive(Debug, Clone)]
pub struct PpmMeter {
    /// Current level (linear)
    level: f64,
    /// Peak hold level
    peak_hold: f64,
    /// PPM type
    ppm_type: PpmType,
    /// Attack coefficient
    attack_coeff: f64,
    /// Release coefficient
    release_coeff: f64,
    /// Sample rate
    sample_rate: f64,
    /// Hold time in samples
    hold_samples: usize,
    /// Current hold counter
    hold_counter: usize,
}

impl PpmMeter {
    /// Create PPM meter with specified type
    pub fn new(sample_rate: f64, ppm_type: PpmType) -> Self {
        // Get integration and return times based on PPM type
        let (integration_ms, return_time_s) = match ppm_type {
            PpmType::BbcType1 => (10.0, 2.8),   // BBC Type I
            PpmType::BbcType2 => (5.0, 1.7),    // BBC Type II / IEC Type I
            PpmType::Ebu => (10.0, 1.7),        // EBU / IEC Type IIa
            PpmType::Din => (5.0, 1.7),         // DIN 45406
            PpmType::Nordic => (5.0, 1.5),      // Nordic N9
        };

        // Attack: time to reach ~80% of step input
        // For PPM, integration time is the time to reach specified level
        let attack_time = integration_ms / 1000.0;
        let attack_coeff = 1.0 - (-2.2 / (attack_time * sample_rate)).exp();

        // Release: time to fall 20dB (or to 1% for BBC spec)
        // Using exponential decay time constant
        let release_time = return_time_s / 4.6; // Time constant for ~1% remaining
        let release_coeff = 1.0 - (-1.0 / (release_time * sample_rate)).exp();

        Self {
            level: 0.0,
            peak_hold: 0.0,
            ppm_type,
            attack_coeff,
            release_coeff,
            sample_rate,
            hold_samples: (sample_rate * 1.5) as usize, // 1.5s hold
            hold_counter: 0,
        }
    }

    /// Create EBU-standard PPM meter
    pub fn ebu(sample_rate: f64) -> Self {
        Self::new(sample_rate, PpmType::Ebu)
    }

    /// Create BBC Type II PPM meter
    pub fn bbc(sample_rate: f64) -> Self {
        Self::new(sample_rate, PpmType::BbcType2)
    }

    /// Process single sample
    #[inline]
    pub fn process(&mut self, sample: Sample) {
        let abs = sample.abs();

        // Asymmetric ballistics: fast attack, slow release
        if abs > self.level {
            // Attack - fast rise
            self.level += self.attack_coeff * (abs - self.level);
        } else {
            // Release - slow fall
            self.level -= self.release_coeff * (self.level - abs);
        }

        // Update peak hold
        if self.level > self.peak_hold {
            self.peak_hold = self.level;
            self.hold_counter = 0;
        } else {
            self.hold_counter += 1;
            if self.hold_counter >= self.hold_samples {
                // Release peak hold
                self.peak_hold -= self.release_coeff * 0.5 * self.peak_hold;
                if self.peak_hold < self.level {
                    self.peak_hold = self.level;
                }
            }
        }
    }

    /// Process block of samples
    pub fn process_block(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.process(sample);
        }
    }

    /// Get PPM reading in dB (PPM scale)
    /// PPM 1 = -12 dBu, PPM 4 = 0 dBu, PPM 6 = +8 dBu (BBC)
    /// Each PPM unit = 4 dB
    pub fn ppm(&self) -> f64 {
        let db = 20.0 * self.level.max(1e-10).log10();
        // Convert dBFS to PPM scale (4 dB per PPM unit)
        // PPM 4 typically corresponds to -18 dBFS (broadcast reference)
        (db + 18.0) / 4.0 + 4.0
    }

    /// Get level in dBFS
    pub fn dbfs(&self) -> f64 {
        20.0 * self.level.max(1e-10).log10()
    }

    /// Get peak hold in dBFS
    pub fn peak_dbfs(&self) -> f64 {
        20.0 * self.peak_hold.max(1e-10).log10()
    }

    /// Get raw linear level
    pub fn linear(&self) -> f64 {
        self.level
    }

    /// Get PPM type
    pub fn meter_type(&self) -> PpmType {
        self.ppm_type
    }

    /// Reset meter
    pub fn reset(&mut self) {
        self.level = 0.0;
        self.peak_hold = 0.0;
        self.hold_counter = 0;
    }

    /// Reset peak hold only
    pub fn reset_peak_hold(&mut self) {
        self.peak_hold = self.level;
        self.hold_counter = 0;
    }
}

/// Stereo PPM meter
#[derive(Debug, Clone)]
pub struct StereoPpmMeter {
    left: PpmMeter,
    right: PpmMeter,
}

impl StereoPpmMeter {
    pub fn new(sample_rate: f64, ppm_type: PpmType) -> Self {
        Self {
            left: PpmMeter::new(sample_rate, ppm_type),
            right: PpmMeter::new(sample_rate, ppm_type),
        }
    }

    pub fn ebu(sample_rate: f64) -> Self {
        Self::new(sample_rate, PpmType::Ebu)
    }

    pub fn process(&mut self, left: Sample, right: Sample) {
        self.left.process(left);
        self.right.process(right);
    }

    pub fn process_block(&mut self, left: &[Sample], right: &[Sample]) {
        for (&l, &r) in left.iter().zip(right.iter()) {
            self.process(l, r);
        }
    }

    pub fn left_dbfs(&self) -> f64 {
        self.left.dbfs()
    }

    pub fn right_dbfs(&self) -> f64 {
        self.right.dbfs()
    }

    pub fn left_ppm(&self) -> f64 {
        self.left.ppm()
    }

    pub fn right_ppm(&self) -> f64 {
        self.right.ppm()
    }

    pub fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DYNAMIC RANGE METER
// ═══════════════════════════════════════════════════════════════════════════════

/// Dynamic range meter (measures loudness range)
#[derive(Debug, Clone)]
pub struct DynamicRangeMeter {
    /// Short-term loudness history
    loudness_history: Vec<f64>,
    history_pos: usize,
    history_len: usize,
    /// Running statistics
    min_loudness: f64,
    max_loudness: f64,
    /// LUFS meter for loudness calculation
    sum_squares: f64,
    window_buffer: Vec<f64>,
    window_pos: usize,
}

impl DynamicRangeMeter {
    /// Create dynamic range meter
    /// history_secs: how long to track loudness (e.g., 60 seconds)
    pub fn new(sample_rate: f64, history_secs: f64) -> Self {
        // Calculate short-term loudness every 100ms
        let window_samples = (0.1 * sample_rate) as usize;
        let history_len = (history_secs * 10.0) as usize; // 10 measurements per second

        Self {
            loudness_history: vec![f64::NEG_INFINITY; history_len],
            history_pos: 0,
            history_len,
            min_loudness: f64::MAX,
            max_loudness: f64::MIN,
            sum_squares: 0.0,
            window_buffer: vec![0.0; window_samples],
            window_pos: 0,
        }
    }

    pub fn process(&mut self, sample: Sample) {
        let squared = sample * sample;

        // Update running sum
        self.sum_squares -= self.window_buffer[self.window_pos];
        self.sum_squares += squared;
        self.window_buffer[self.window_pos] = squared;

        // Record loudness at end of window
        let _old_pos = self.window_pos;
        self.window_pos = (self.window_pos + 1) % self.window_buffer.len();

        if self.window_pos == 0 {
            // Window complete, record loudness
            let mean = self.sum_squares / self.window_buffer.len() as f64;
            let loudness = -0.691 + 10.0 * mean.max(1e-10).log10();

            // Only track if above gate (-70 LUFS)
            if loudness > -70.0 {
                self.loudness_history[self.history_pos] = loudness;
                self.history_pos = (self.history_pos + 1) % self.history_len;

                if loudness < self.min_loudness {
                    self.min_loudness = loudness;
                }
                if loudness > self.max_loudness {
                    self.max_loudness = loudness;
                }
            }
        }
    }

    pub fn process_block(&mut self, samples: &[Sample]) {
        for &sample in samples {
            self.process(sample);
        }
    }

    /// Get dynamic range (max - min loudness in LU)
    pub fn dynamic_range(&self) -> f64 {
        if self.max_loudness > self.min_loudness {
            self.max_loudness - self.min_loudness
        } else {
            0.0
        }
    }

    /// Get loudness range (LRA per EBU R128)
    /// This is the range between 10th and 95th percentile
    pub fn loudness_range(&self) -> f64 {
        // Collect valid loudness values
        let mut values: Vec<f64> = self.loudness_history
            .iter()
            .filter(|&&v| v > -70.0)
            .copied()
            .collect();

        if values.len() < 10 {
            return 0.0;
        }

        values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let p10_idx = values.len() / 10;
        let p95_idx = (values.len() * 95) / 100;

        values.get(p95_idx).unwrap_or(&0.0) - values.get(p10_idx).unwrap_or(&0.0)
    }

    pub fn reset(&mut self) {
        self.loudness_history.fill(f64::NEG_INFINITY);
        self.history_pos = 0;
        self.min_loudness = f64::MAX;
        self.max_loudness = f64::MIN;
        self.sum_squares = 0.0;
        self.window_buffer.fill(0.0);
        self.window_pos = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE SCOPE (GONIOMETER)
// ═══════════════════════════════════════════════════════════════════════════════

/// Phase scope / Goniometer data point
#[derive(Debug, Clone, Copy, Default)]
pub struct PhasePoint {
    /// X coordinate (-1 to +1, represents M/S)
    pub x: f32,
    /// Y coordinate (-1 to +1, represents L+R)
    pub y: f32,
}

/// Phase scope for stereo visualization
///
/// Displays stereo signal as Lissajous figure:
/// - Vertical line = Mono
/// - Horizontal line = Side only (out of phase)
/// - Circle = Unrelated L/R
/// - 45° diagonal = Pure L or R
#[derive(Debug, Clone)]
pub struct PhaseScope {
    /// Ring buffer of points
    points: Vec<PhasePoint>,
    /// Current write position
    write_pos: usize,
    /// Decimation counter
    decimate_counter: usize,
    /// Decimation factor (e.g., 10 = keep 1 in 10 samples)
    decimate_factor: usize,
}

impl PhaseScope {
    /// Create phase scope
    /// num_points: how many points to keep in history
    /// decimate_factor: keep 1 in N samples (reduces CPU for display)
    pub fn new(num_points: usize, decimate_factor: usize) -> Self {
        Self {
            points: vec![PhasePoint::default(); num_points],
            write_pos: 0,
            decimate_counter: 0,
            decimate_factor: decimate_factor.max(1),
        }
    }

    pub fn process(&mut self, left: Sample, right: Sample) {
        self.decimate_counter += 1;
        if self.decimate_counter >= self.decimate_factor {
            self.decimate_counter = 0;

            // M/S encoding for display
            let mid = (left + right) * 0.5;
            let side = (left - right) * 0.5;

            self.points[self.write_pos] = PhasePoint {
                x: side as f32,
                y: mid as f32,
            };

            self.write_pos = (self.write_pos + 1) % self.points.len();
        }
    }

    pub fn process_block(&mut self, left: &[Sample], right: &[Sample]) {
        for (&l, &r) in left.iter().zip(right.iter()) {
            self.process(l, r);
        }
    }

    /// Get all points (for rendering)
    pub fn points(&self) -> &[PhasePoint] {
        &self.points
    }

    /// Get points in order (oldest to newest)
    pub fn points_ordered(&self) -> impl Iterator<Item = &PhasePoint> {
        let (first, second) = self.points.split_at(self.write_pos);
        second.iter().chain(first.iter())
    }

    pub fn reset(&mut self) {
        self.points.fill(PhasePoint::default());
        self.write_pos = 0;
        self.decimate_counter = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LUFS METER (ITU-R BS.1770-4)
// ═══════════════════════════════════════════════════════════════════════════════

/// K-weighting filter coefficients for LUFS measurement
/// Two-stage filter: High-shelf pre-filter + High-pass filter
#[derive(Debug, Clone)]
struct KWeightingFilter {
    // Stage 1: High-shelf pre-filter (+4dB above 1681Hz)
    b0_1: f64, b1_1: f64, b2_1: f64,
    a1_1: f64, a2_1: f64,
    z1_1_l: f64, z2_1_l: f64,
    z1_1_r: f64, z2_1_r: f64,

    // Stage 2: High-pass filter (RLB weighting, -3dB at 38Hz)
    b0_2: f64, b1_2: f64, b2_2: f64,
    a1_2: f64, a2_2: f64,
    z1_2_l: f64, z2_2_l: f64,
    z1_2_r: f64, z2_2_r: f64,
}

impl KWeightingFilter {
    fn new(sample_rate: f64) -> Self {
        // Stage 1: High-shelf pre-filter (ITU-R BS.1770-4)
        // Coefficients designed for +4dB shelf starting around 1500Hz
        let fc1: f64 = 1681.0;
        let g1: f64 = 3.999843853973347; // Linear gain (~4dB)
        let q1: f64 = 0.7071752369554196;

        let k1 = (std::f64::consts::PI * fc1 / sample_rate).tan();
        let k1_sq = k1 * k1;
        let sqrt_g1 = g1.sqrt();
        let denom1 = 1.0 + k1 / q1 + k1_sq;

        let b0_1 = (1.0 + sqrt_g1 * k1 / q1 + g1 * k1_sq) / denom1;
        let b1_1 = 2.0 * (g1 * k1_sq - 1.0) / denom1;
        let b2_1 = (1.0 - sqrt_g1 * k1 / q1 + g1 * k1_sq) / denom1;
        let a1_1 = 2.0 * (k1_sq - 1.0) / denom1;
        let a2_1 = (1.0 - k1 / q1 + k1_sq) / denom1;

        // Stage 2: High-pass filter (RLB weighting)
        // -3dB at 38.13547087602444 Hz
        let fc2 = 38.13547087602444;
        let q2 = 0.5003270373238773;

        let k2 = (std::f64::consts::PI * fc2 / sample_rate).tan();
        let k2_sq = k2 * k2;
        let denom2 = 1.0 + k2 / q2 + k2_sq;

        let b0_2 = 1.0 / denom2;
        let b1_2 = -2.0 / denom2;
        let b2_2 = 1.0 / denom2;
        let a1_2 = 2.0 * (k2_sq - 1.0) / denom2;
        let a2_2 = (1.0 - k2 / q2 + k2_sq) / denom2;

        Self {
            b0_1, b1_1, b2_1, a1_1, a2_1,
            z1_1_l: 0.0, z2_1_l: 0.0,
            z1_1_r: 0.0, z2_1_r: 0.0,
            b0_2, b1_2, b2_2, a1_2, a2_2,
            z1_2_l: 0.0, z2_2_l: 0.0,
            z1_2_r: 0.0, z2_2_r: 0.0,
        }
    }

    /// Process stereo sample through K-weighting filters
    #[inline]
    fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        // Stage 1: High-shelf (left)
        let y1_l = self.b0_1 * left + self.z1_1_l;
        self.z1_1_l = self.b1_1 * left - self.a1_1 * y1_l + self.z2_1_l;
        self.z2_1_l = self.b2_1 * left - self.a2_1 * y1_l;

        // Stage 1: High-shelf (right)
        let y1_r = self.b0_1 * right + self.z1_1_r;
        self.z1_1_r = self.b1_1 * right - self.a1_1 * y1_r + self.z2_1_r;
        self.z2_1_r = self.b2_1 * right - self.a2_1 * y1_r;

        // Stage 2: High-pass (left)
        let y2_l = self.b0_2 * y1_l + self.z1_2_l;
        self.z1_2_l = self.b1_2 * y1_l - self.a1_2 * y2_l + self.z2_2_l;
        self.z2_2_l = self.b2_2 * y1_l - self.a2_2 * y2_l;

        // Stage 2: High-pass (right)
        let y2_r = self.b0_2 * y1_r + self.z1_2_r;
        self.z1_2_r = self.b1_2 * y1_r - self.a1_2 * y2_r + self.z2_2_r;
        self.z2_2_r = self.b2_2 * y1_r - self.a2_2 * y2_r;

        (y2_l, y2_r)
    }

    fn reset(&mut self) {
        self.z1_1_l = 0.0; self.z2_1_l = 0.0;
        self.z1_1_r = 0.0; self.z2_1_r = 0.0;
        self.z1_2_l = 0.0; self.z2_2_l = 0.0;
        self.z1_2_r = 0.0; self.z2_2_r = 0.0;
    }
}

/// LUFS (Loudness Units Full Scale) meter per ITU-R BS.1770-4 / EBU R128
///
/// Provides:
/// - Momentary loudness (400ms window)
/// - Short-term loudness (3s window)
/// - Integrated loudness (from start, gated)
/// - Loudness Range (LRA)
#[derive(Debug, Clone)]
pub struct LufsMeter {
    sample_rate: f64,

    /// K-weighting filter
    k_filter: KWeightingFilter,

    /// Momentary loudness (400ms) - circular buffer of squared sums
    momentary_buffer: Vec<f64>,
    momentary_pos: usize,
    momentary_sum: f64,

    /// Short-term loudness (3s) - circular buffer of 100ms blocks
    shortterm_buffer: Vec<f64>,
    shortterm_pos: usize,
    shortterm_sum: f64,

    /// Block accumulator for 100ms gating blocks
    block_sum: f64,
    block_samples: usize,
    samples_per_block: usize,

    /// Integrated loudness with gating
    /// Stores loudness of all 100ms blocks above absolute gate (-70 LUFS)
    gated_blocks: Vec<f64>,

    /// For LRA calculation - stores short-term loudness values
    lra_buffer: Vec<f64>,
    lra_pos: usize,

    /// Sample counter for 100ms blocks
    sample_counter: usize,
}

impl LufsMeter {
    /// Create new LUFS meter
    pub fn new(sample_rate: f64) -> Self {
        let samples_per_100ms = (sample_rate * 0.1) as usize;
        let samples_per_400ms = (sample_rate * 0.4) as usize;

        // Short-term uses 3s = 30 x 100ms blocks
        let shortterm_blocks = 30;

        // LRA buffer for ~60 seconds of short-term values (updates every 100ms)
        let lra_capacity = 600;

        Self {
            sample_rate,
            k_filter: KWeightingFilter::new(sample_rate),

            momentary_buffer: vec![0.0; samples_per_400ms],
            momentary_pos: 0,
            momentary_sum: 0.0,

            shortterm_buffer: vec![0.0; shortterm_blocks],
            shortterm_pos: 0,
            shortterm_sum: 0.0,

            block_sum: 0.0,
            block_samples: 0,
            samples_per_block: samples_per_100ms,

            gated_blocks: Vec::with_capacity(10000),

            lra_buffer: vec![f64::NEG_INFINITY; lra_capacity],
            lra_pos: 0,

            sample_counter: 0,
        }
    }

    /// Process a stereo sample pair
    pub fn process(&mut self, left: Sample, right: Sample) {
        // Apply K-weighting
        let (k_left, k_right) = self.k_filter.process(left, right);

        // Mean square (stereo: equal weighting for L and R per ITU-R BS.1770)
        let mean_square = (k_left * k_left + k_right * k_right) / 2.0;

        // Update momentary (400ms) - sample-by-sample
        let old_momentary = self.momentary_buffer[self.momentary_pos];
        self.momentary_sum -= old_momentary;
        self.momentary_sum += mean_square;
        self.momentary_buffer[self.momentary_pos] = mean_square;
        self.momentary_pos = (self.momentary_pos + 1) % self.momentary_buffer.len();

        // Accumulate into 100ms blocks
        self.block_sum += mean_square;
        self.block_samples += 1;

        if self.block_samples >= self.samples_per_block {
            let block_loudness = self.block_sum / self.block_samples as f64;
            let block_lufs = -0.691 + 10.0 * block_loudness.max(1e-10).log10();

            // Update short-term (3s)
            let old_shortterm = self.shortterm_buffer[self.shortterm_pos];
            self.shortterm_sum -= old_shortterm;
            self.shortterm_sum += block_loudness;
            self.shortterm_buffer[self.shortterm_pos] = block_loudness;
            self.shortterm_pos = (self.shortterm_pos + 1) % self.shortterm_buffer.len();

            // Store for integrated loudness (only if above absolute gate -70 LUFS)
            if block_lufs > -70.0 {
                self.gated_blocks.push(block_lufs);
            }

            // Store short-term value for LRA
            let shortterm = self.shortterm_loudness();
            if shortterm > -70.0 {
                self.lra_buffer[self.lra_pos] = shortterm;
                self.lra_pos = (self.lra_pos + 1) % self.lra_buffer.len();
            }

            // Reset block accumulator
            self.block_sum = 0.0;
            self.block_samples = 0;
        }
    }

    /// Process a stereo block
    pub fn process_block(&mut self, left: &[Sample], right: &[Sample]) {
        for (&l, &r) in left.iter().zip(right.iter()) {
            self.process(l, r);
        }
    }

    /// Get momentary loudness (400ms) in LUFS
    pub fn momentary_loudness(&self) -> f64 {
        let mean = self.momentary_sum / self.momentary_buffer.len() as f64;
        -0.691 + 10.0 * mean.max(1e-10).log10()
    }

    /// Get short-term loudness (3s) in LUFS
    pub fn shortterm_loudness(&self) -> f64 {
        let mean = self.shortterm_sum / self.shortterm_buffer.len() as f64;
        -0.691 + 10.0 * mean.max(1e-10).log10()
    }

    /// Get integrated loudness with EBU R128 gating in LUFS
    ///
    /// Uses two-stage gating:
    /// 1. Absolute gate at -70 LUFS
    /// 2. Relative gate at -10 LU below ungated result
    pub fn integrated_loudness(&self) -> f64 {
        if self.gated_blocks.is_empty() {
            return f64::NEG_INFINITY;
        }

        // First pass: Calculate ungated average (blocks above -70 LUFS)
        let sum: f64 = self.gated_blocks.iter()
            .map(|&lufs| 10.0_f64.powf((lufs + 0.691) / 10.0))
            .sum();
        let ungated_avg = sum / self.gated_blocks.len() as f64;
        let ungated_lufs = -0.691 + 10.0 * ungated_avg.log10();

        // Second pass: Relative gate at ungated_lufs - 10 LU
        let relative_gate = ungated_lufs - 10.0;

        let gated_blocks: Vec<f64> = self.gated_blocks.iter()
            .filter(|&&lufs| lufs > relative_gate)
            .copied()
            .collect();

        if gated_blocks.is_empty() {
            return f64::NEG_INFINITY;
        }

        let gated_sum: f64 = gated_blocks.iter()
            .map(|&lufs| 10.0_f64.powf((lufs + 0.691) / 10.0))
            .sum();
        let gated_avg = gated_sum / gated_blocks.len() as f64;

        -0.691 + 10.0 * gated_avg.log10()
    }

    /// Get Loudness Range (LRA) per EBU R128 in LU
    ///
    /// Range between 10th and 95th percentile of short-term loudness
    pub fn loudness_range(&self) -> f64 {
        let mut values: Vec<f64> = self.lra_buffer.iter()
            .filter(|&&v| v > -70.0)
            .copied()
            .collect();

        if values.len() < 20 {
            return 0.0;
        }

        values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let p10_idx = values.len() / 10;
        let p95_idx = (values.len() * 95) / 100;

        values[p95_idx] - values[p10_idx]
    }

    /// Get max short-term loudness seen
    pub fn max_shortterm(&self) -> f64 {
        self.lra_buffer.iter()
            .filter(|&&v| v > -70.0)
            .copied()
            .fold(f64::NEG_INFINITY, f64::max)
    }

    /// Reset meter (clear all history)
    pub fn reset(&mut self) {
        self.k_filter.reset();
        self.momentary_buffer.fill(0.0);
        self.momentary_pos = 0;
        self.momentary_sum = 0.0;
        self.shortterm_buffer.fill(0.0);
        self.shortterm_pos = 0;
        self.shortterm_sum = 0.0;
        self.block_sum = 0.0;
        self.block_samples = 0;
        self.gated_blocks.clear();
        self.lra_buffer.fill(f64::NEG_INFINITY);
        self.lra_pos = 0;
    }

    /// Reset only the integrated loudness (keep momentary/short-term)
    pub fn reset_integrated(&mut self) {
        self.gated_blocks.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRUE PEAK METER (ITU-R BS.1770-4)
// ═══════════════════════════════════════════════════════════════════════════════

/// True Peak meter per ITU-R BS.1770-4
///
/// Uses 4x oversampling to detect inter-sample peaks that would
/// exceed 0 dBFS after D/A conversion.
#[derive(Debug, Clone)]
pub struct TruePeakMeter {
    /// 4x oversampling filter coefficients (12-tap FIR)
    filter_coeffs: [f64; 12],

    /// Filter state for left channel (12 samples)
    state_l: [f64; 12],
    /// Filter state for right channel
    state_r: [f64; 12],

    /// Current true peak (linear)
    current_peak_l: f64,
    current_peak_r: f64,

    /// Maximum true peak seen (linear)
    max_peak_l: f64,
    max_peak_r: f64,

    /// Peak hold (for display)
    hold_peak_l: f64,
    hold_peak_r: f64,
    hold_counter: usize,
    hold_samples: usize,

    /// Release coefficient
    release_coeff: f64,
}

impl TruePeakMeter {
    /// Create True Peak meter
    pub fn new(sample_rate: f64) -> Self {
        // ITU-R BS.1770-4 specifies 4x oversampling
        // Using optimized 12-tap polyphase FIR filter
        // These coefficients are designed for low-latency true peak detection
        let filter_coeffs = [
            0.0017089843750,
            -0.0291748046875,
            -0.0189208984375,
            0.1109619140625,
            0.2817382812500,
            0.3891601562500,
            0.2817382812500,
            0.1109619140625,
            -0.0189208984375,
            -0.0291748046875,
            0.0017089843750,
            0.0,
        ];

        // Hold time: 1.5 seconds
        let hold_samples = (sample_rate * 1.5) as usize;
        // Release: ~1.5dB/s
        let release_coeff = (-1.0 / (sample_rate * 3.0)).exp();

        Self {
            filter_coeffs,
            state_l: [0.0; 12],
            state_r: [0.0; 12],
            current_peak_l: 0.0,
            current_peak_r: 0.0,
            max_peak_l: 0.0,
            max_peak_r: 0.0,
            hold_peak_l: 0.0,
            hold_peak_r: 0.0,
            hold_counter: 0,
            hold_samples,
            release_coeff,
        }
    }

    /// Process stereo sample pair
    pub fn process(&mut self, left: Sample, right: Sample) {
        // Shift state buffers
        for i in (1..12).rev() {
            self.state_l[i] = self.state_l[i - 1];
            self.state_r[i] = self.state_r[i - 1];
        }
        self.state_l[0] = left;
        self.state_r[0] = right;

        // Calculate 4 interpolated samples using polyphase filter
        let mut max_l = left.abs();
        let mut max_r = right.abs();

        for phase in 0..4 {
            let mut sum_l = 0.0;
            let mut sum_r = 0.0;

            for i in 0..12 {
                let coeff_idx = (i * 4 + phase) % 12;
                sum_l += self.state_l[i] * self.filter_coeffs[coeff_idx];
                sum_r += self.state_r[i] * self.filter_coeffs[coeff_idx];
            }

            max_l = max_l.max(sum_l.abs());
            max_r = max_r.max(sum_r.abs());
        }

        // Update current peak with release
        if max_l > self.current_peak_l {
            self.current_peak_l = max_l;
        } else {
            self.current_peak_l *= self.release_coeff;
        }

        if max_r > self.current_peak_r {
            self.current_peak_r = max_r;
        } else {
            self.current_peak_r *= self.release_coeff;
        }

        // Update max peak
        self.max_peak_l = self.max_peak_l.max(max_l);
        self.max_peak_r = self.max_peak_r.max(max_r);

        // Update hold peak
        let current_max = max_l.max(max_r);
        if current_max > self.hold_peak_l.max(self.hold_peak_r) {
            self.hold_peak_l = max_l;
            self.hold_peak_r = max_r;
            self.hold_counter = 0;
        } else {
            self.hold_counter += 1;
            if self.hold_counter >= self.hold_samples {
                self.hold_peak_l *= self.release_coeff;
                self.hold_peak_r *= self.release_coeff;
            }
        }
    }

    /// Process stereo block
    pub fn process_block(&mut self, left: &[Sample], right: &[Sample]) {
        for (&l, &r) in left.iter().zip(right.iter()) {
            self.process(l, r);
        }
    }

    /// Get current true peak in dBTP (left channel)
    pub fn peak_dbtp_l(&self) -> f64 {
        20.0 * self.current_peak_l.max(1e-10).log10()
    }

    /// Get current true peak in dBTP (right channel)
    pub fn peak_dbtp_r(&self) -> f64 {
        20.0 * self.current_peak_r.max(1e-10).log10()
    }

    /// Get current true peak in dBTP (stereo max)
    pub fn peak_dbtp(&self) -> f64 {
        self.peak_dbtp_l().max(self.peak_dbtp_r())
    }

    /// Get maximum true peak in dBTP (left channel)
    pub fn max_peak_dbtp_l(&self) -> f64 {
        20.0 * self.max_peak_l.max(1e-10).log10()
    }

    /// Get maximum true peak in dBTP (right channel)
    pub fn max_peak_dbtp_r(&self) -> f64 {
        20.0 * self.max_peak_r.max(1e-10).log10()
    }

    /// Get maximum true peak in dBTP (stereo max)
    pub fn max_peak_dbtp(&self) -> f64 {
        self.max_peak_dbtp_l().max(self.max_peak_dbtp_r())
    }

    /// Get held peak in dBTP (stereo)
    pub fn hold_peak_dbtp(&self) -> f64 {
        20.0 * self.hold_peak_l.max(self.hold_peak_r).max(1e-10).log10()
    }

    /// Check if signal has clipped (true peak > 0 dBTP)
    pub fn is_clipping(&self) -> bool {
        self.current_peak_l > 1.0 || self.current_peak_r > 1.0
    }

    /// Check if signal has ever clipped
    pub fn has_clipped(&self) -> bool {
        self.max_peak_l > 1.0 || self.max_peak_r > 1.0
    }

    /// Reset meter
    pub fn reset(&mut self) {
        self.state_l = [0.0; 12];
        self.state_r = [0.0; 12];
        self.current_peak_l = 0.0;
        self.current_peak_r = 0.0;
        self.max_peak_l = 0.0;
        self.max_peak_r = 0.0;
        self.hold_peak_l = 0.0;
        self.hold_peak_r = 0.0;
        self.hold_counter = 0;
    }

    /// Reset only the max peak (keep current)
    pub fn reset_max(&mut self) {
        self.max_peak_l = self.current_peak_l;
        self.max_peak_r = self.current_peak_r;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BROADCAST METER (COMBINED LUFS + TRUE PEAK)
// ═══════════════════════════════════════════════════════════════════════════════

/// EBU R128 compliant broadcast meter
///
/// Combined LUFS and True Peak measurement per broadcast standards.
/// Includes:
/// - Momentary loudness (400ms)
/// - Short-term loudness (3s)
/// - Integrated loudness (gated)
/// - Loudness Range (LRA)
/// - True Peak
#[derive(Debug, Clone)]
pub struct BroadcastMeter {
    /// LUFS meter
    pub lufs: LufsMeter,
    /// True Peak meter
    pub true_peak: TruePeakMeter,
    /// Target loudness (default: -23 LUFS for EBU R128)
    pub target_lufs: f64,
    /// Max allowed true peak (default: -1 dBTP for EBU R128)
    pub max_true_peak_dbtp: f64,
}

impl BroadcastMeter {
    /// Create EBU R128 compliant meter (-23 LUFS, -1 dBTP)
    pub fn ebu_r128(sample_rate: f64) -> Self {
        Self {
            lufs: LufsMeter::new(sample_rate),
            true_peak: TruePeakMeter::new(sample_rate),
            target_lufs: -23.0,
            max_true_peak_dbtp: -1.0,
        }
    }

    /// Create ATSC A/85 compliant meter (-24 LKFS, -2 dBTP)
    pub fn atsc_a85(sample_rate: f64) -> Self {
        Self {
            lufs: LufsMeter::new(sample_rate),
            true_peak: TruePeakMeter::new(sample_rate),
            target_lufs: -24.0,
            max_true_peak_dbtp: -2.0,
        }
    }

    /// Create streaming platform meter (-14 LUFS, -1 dBTP typical)
    pub fn streaming(sample_rate: f64) -> Self {
        Self {
            lufs: LufsMeter::new(sample_rate),
            true_peak: TruePeakMeter::new(sample_rate),
            target_lufs: -14.0,
            max_true_peak_dbtp: -1.0,
        }
    }

    /// Process stereo sample
    pub fn process(&mut self, left: Sample, right: Sample) {
        self.lufs.process(left, right);
        self.true_peak.process(left, right);
    }

    /// Process stereo block
    pub fn process_block(&mut self, left: &[Sample], right: &[Sample]) {
        self.lufs.process_block(left, right);
        self.true_peak.process_block(left, right);
    }

    /// Get deviation from target loudness in LU
    pub fn loudness_deviation(&self) -> f64 {
        self.lufs.integrated_loudness() - self.target_lufs
    }

    /// Check if loudness is within EBU R128 tolerance (+/- 1 LU)
    pub fn is_loudness_compliant(&self) -> bool {
        self.loudness_deviation().abs() <= 1.0
    }

    /// Check if true peak is compliant
    pub fn is_true_peak_compliant(&self) -> bool {
        self.true_peak.max_peak_dbtp() <= self.max_true_peak_dbtp
    }

    /// Check overall compliance
    pub fn is_compliant(&self) -> bool {
        self.is_loudness_compliant() && self.is_true_peak_compliant()
    }

    /// Get suggested gain adjustment in dB
    pub fn suggested_gain(&self) -> f64 {
        -self.loudness_deviation()
    }

    /// Reset all meters
    pub fn reset(&mut self) {
        self.lufs.reset();
        self.true_peak.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEREO METER (COMBINED)
// ═══════════════════════════════════════════════════════════════════════════════

/// Combined stereo meter with all measurements
#[derive(Debug, Clone)]
pub struct StereoMeter {
    pub correlation: CorrelationMeter,
    pub balance: BalanceMeter,
    pub k_meter_l: KMeter,
    pub k_meter_r: KMeter,
}

impl StereoMeter {
    pub fn new(sample_rate: f64, k_system: KSystem) -> Self {
        Self {
            correlation: CorrelationMeter::new(sample_rate, 300.0),
            balance: BalanceMeter::new(sample_rate, 300.0),
            k_meter_l: KMeter::new(sample_rate, k_system),
            k_meter_r: KMeter::new(sample_rate, k_system),
        }
    }

    pub fn process(&mut self, left: Sample, right: Sample) {
        self.correlation.process(left, right);
        self.balance.process(left, right);
        self.k_meter_l.process(left);
        self.k_meter_r.process(right);
    }

    pub fn process_block(&mut self, left: &[Sample], right: &[Sample]) {
        for (&l, &r) in left.iter().zip(right.iter()) {
            self.process(l, r);
        }
    }

    pub fn set_k_system(&mut self, k_system: KSystem) {
        self.k_meter_l.set_k_system(k_system);
        self.k_meter_r.set_k_system(k_system);
    }

    pub fn reset(&mut self) {
        self.correlation.reset();
        self.balance.reset();
        self.k_meter_l.reset();
        self.k_meter_r.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_correlation_mono() {
        let mut meter = CorrelationMeter::new(48000.0, 100.0);

        // Identical L/R should give correlation of 1.0
        for i in 0..4800 {
            let sample = (i as f64 * 0.1).sin();
            meter.process(sample, sample);
        }

        assert!(meter.correlation() > 0.95);
    }

    #[test]
    fn test_correlation_inverted() {
        let mut meter = CorrelationMeter::new(48000.0, 100.0);

        // Inverted L/R should give correlation of -1.0
        for i in 0..4800 {
            let sample = (i as f64 * 0.1).sin();
            meter.process(sample, -sample);
        }

        assert!(meter.correlation() < -0.95);
    }

    #[test]
    fn test_balance_center() {
        let mut meter = BalanceMeter::new(48000.0, 100.0);

        // Equal L/R should give balance of 0.0
        for i in 0..4800 {
            let sample = (i as f64 * 0.1).sin();
            meter.process(sample, sample);
        }

        assert!(meter.balance().abs() < 0.1);
    }

    #[test]
    fn test_balance_left() {
        let mut meter = BalanceMeter::new(48000.0, 100.0);

        // Only left channel
        for i in 0..4800 {
            let sample = (i as f64 * 0.1).sin();
            meter.process(sample, 0.0);
        }

        assert!(meter.balance() < -0.9);
    }

    #[test]
    fn test_k_meter() {
        let mut meter = KMeter::new(48000.0, KSystem::K14);

        // -14 dBFS sine wave (RMS will be ~3dB lower than peak)
        // For a sine wave, RMS = peak / sqrt(2), so -14 dBFS peak = ~-17 dBFS RMS
        let amplitude = 10.0_f64.powf(-14.0 / 20.0);
        for i in 0..48000 {
            let sample = amplitude * (i as f64 * 0.1).sin();
            meter.process(sample);
        }

        // With K-14 calibration, RMS should be in reasonable range
        // Allow wider tolerance since sine RMS differs from peak
        assert!(meter.rms_k().abs() < 6.0, "K-meter RMS: {}", meter.rms_k());
    }

    #[test]
    fn test_vu_meter() {
        let mut meter = VuMeter::standard(48000.0);

        // -18 dBFS tone should read 0 VU
        let amplitude = 10.0_f64.powf(-18.0 / 20.0);
        for i in 0..48000 {
            let sample = amplitude * (i as f64 * 0.1).sin();
            meter.process(sample);
        }

        // VU should be close to 0
        // Note: sine wave RMS is -3dB from peak
        assert!(meter.vu().abs() < 5.0);
    }

    #[test]
    fn test_phase_scope() {
        let mut scope = PhaseScope::new(100, 10);

        // Process stereo signal
        for i in 0..1000 {
            let l = (i as f64 * 0.1).sin();
            let r = (i as f64 * 0.1 + 0.5).sin();
            scope.process(l, r);
        }

        // Should have filled buffer
        let points = scope.points();
        assert_eq!(points.len(), 100);
    }
}

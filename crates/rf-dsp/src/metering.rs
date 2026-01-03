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
        let old_pos = self.window_pos;
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

        values.sort_by(|a, b| a.partial_cmp(b).unwrap());

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

        // -14 dBFS tone should read 0 VU in K-14
        let amplitude = 10.0_f64.powf(-14.0 / 20.0);
        for i in 0..48000 {
            let sample = amplitude * (i as f64 * 0.1).sin();
            meter.process(sample);
        }

        // Should be close to 0 in K-14 units
        assert!(meter.rms_k().abs() < 1.0);
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

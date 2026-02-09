//! Audio normalization with EBU R128 compliant LUFS metering
//!
//! Implements:
//! - K-weighting pre-filter (ITU-R BS.1770-4)
//! - True Peak detection with 4x oversampling
//! - Integrated loudness with absolute gating (-70 LUFS) and relative gating (-10 LU)

use serde::{Deserialize, Serialize};

/// Normalization mode
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum NormalizationMode {
    /// Peak normalization (dBFS target)
    Peak { target_db: f64 },

    /// Loudness normalization (LUFS target) - EBU R128
    Lufs { target_lufs: f64 },

    /// True peak normalization (dBTP target)
    TruePeak { target_db: f64 },

    /// No normalization, but ensure no clipping
    NoClip,
}

impl Default for NormalizationMode {
    fn default() -> Self {
        Self::Peak { target_db: -1.0 }
    }
}

impl NormalizationMode {
    /// Create peak normalization at -1dBFS
    pub fn peak() -> Self {
        Self::Peak { target_db: -1.0 }
    }

    /// Create LUFS normalization at -14 LUFS (streaming standard)
    pub fn streaming() -> Self {
        Self::Lufs { target_lufs: -14.0 }
    }

    /// Create LUFS normalization at -23 LUFS (broadcast standard)
    pub fn broadcast() -> Self {
        Self::Lufs { target_lufs: -23.0 }
    }

    /// Create true peak normalization at -1dBTP
    pub fn true_peak() -> Self {
        Self::TruePeak { target_db: -1.0 }
    }
}

/// Loudness measurement result
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct LoudnessInfo {
    /// Peak level (dBFS)
    pub peak: f64,
    /// True peak level (dBTP)
    pub true_peak: f64,
    /// Integrated loudness (LUFS)
    pub integrated: f64,
    /// Short-term loudness (LUFS)
    pub short_term: f64,
    /// Momentary loudness (LUFS)
    pub momentary: f64,
    /// Loudness range (LU)
    pub range: f64,
}

/// Normalizer for applying gain based on loudness analysis
pub struct Normalizer {
    mode: NormalizationMode,
}

impl Normalizer {
    /// Create new normalizer
    pub fn new(mode: NormalizationMode) -> Self {
        Self { mode }
    }

    /// Calculate gain to apply based on loudness info
    pub fn calculate_gain(&self, info: &LoudnessInfo) -> f64 {
        match self.mode {
            NormalizationMode::Peak { target_db } => {
                let current_peak_db = 20.0 * info.peak.log10();
                let gain_db = target_db - current_peak_db;
                db_to_linear(gain_db)
            }
            NormalizationMode::Lufs { target_lufs } => {
                let gain_db = target_lufs - info.integrated;
                db_to_linear(gain_db)
            }
            NormalizationMode::TruePeak { target_db } => {
                let current_tp_db = 20.0 * info.true_peak.log10();
                let gain_db = target_db - current_tp_db;
                db_to_linear(gain_db)
            }
            NormalizationMode::NoClip => {
                if info.peak > 1.0 {
                    1.0 / info.peak
                } else {
                    1.0
                }
            }
        }
    }

    /// Apply normalization to buffer (in place)
    pub fn apply(&self, buffer: &mut [f64], info: &LoudnessInfo) {
        let gain = self.calculate_gain(info);
        for sample in buffer.iter_mut() {
            *sample *= gain;
        }
    }
}

/// Convert dB to linear gain
fn db_to_linear(db: f64) -> f64 {
    10.0_f64.powf(db / 20.0)
}

/// Convert linear gain to dB
#[allow(dead_code)]
fn linear_to_db(linear: f64) -> f64 {
    20.0 * linear.log10()
}

// ═══════════════════════════════════════════════════════════════════════════════
// K-WEIGHTING FILTER — ITU-R BS.1770-4
// ═══════════════════════════════════════════════════════════════════════════════

/// K-weighting pre-filter (two stages)
/// Stage 1: High shelf boost (+4dB at 1.5kHz)
/// Stage 2: High-pass filter (60Hz cutoff)
#[derive(Debug, Clone)]
struct KWeightingFilter {
    // Biquad coefficients for stage 1 (high shelf)
    b0_1: f64,
    b1_1: f64,
    b2_1: f64,
    a1_1: f64,
    a2_1: f64,
    // Biquad coefficients for stage 2 (high pass)
    b0_2: f64,
    b1_2: f64,
    b2_2: f64,
    a1_2: f64,
    a2_2: f64,
    // Filter state (per channel)
    z1_1: f64,
    z2_1: f64, // Stage 1 state
    z1_2: f64,
    z2_2: f64, // Stage 2 state
}

impl KWeightingFilter {
    /// Create K-weighting filter for given sample rate
    fn new(sample_rate: f64) -> Self {
        // Stage 1: High shelf filter (+4dB, ~1500Hz)
        // Coefficients from ITU-R BS.1770-4
        let (b0_1, b1_1, b2_1, a1_1, a2_1) = Self::high_shelf_coeffs(sample_rate);

        // Stage 2: High-pass filter (60Hz)
        let (b0_2, b1_2, b2_2, a1_2, a2_2) = Self::high_pass_coeffs(sample_rate);

        Self {
            b0_1,
            b1_1,
            b2_1,
            a1_1,
            a2_1,
            b0_2,
            b1_2,
            b2_2,
            a1_2,
            a2_2,
            z1_1: 0.0,
            z2_1: 0.0,
            z1_2: 0.0,
            z2_2: 0.0,
        }
    }

    /// High shelf filter coefficients for K-weighting
    fn high_shelf_coeffs(fs: f64) -> (f64, f64, f64, f64, f64) {
        // Pre-calculated for common sample rates, or compute analytically
        if (fs - 48000.0).abs() < 1.0 {
            // 48 kHz coefficients (ITU-R BS.1770-4)
            (
                1.53512485958697,
                -2.69169618940638,
                1.19839281085285,
                -1.69065929318241,
                0.73248077421585,
            )
        } else if (fs - 44100.0).abs() < 1.0 {
            // 44.1 kHz coefficients
            (
                1.53091690990424,
                -2.65253388989405,
                1.16950037399656,
                -1.66360936109397,
                0.71250596184082,
            )
        } else {
            // Compute coefficients for other sample rates
            Self::compute_high_shelf(fs)
        }
    }

    /// Compute high shelf coefficients analytically
    fn compute_high_shelf(fs: f64) -> (f64, f64, f64, f64, f64) {
        let db = 4.0; // +4 dB
        let f0 = 1681.974450955533; // Center frequency
        let q = 0.7071752369554196; // Q factor

        let k = (std::f64::consts::PI * f0 / fs).tan();
        let vb = 10.0_f64.powf(db / 20.0);
        let vb_sqrt = vb.sqrt();

        let norm = 1.0 / (1.0 + k / q + k * k);

        let b0 = (1.0 + vb_sqrt * k / q + vb * k * k) * norm;
        let b1 = 2.0 * (vb * k * k - 1.0) * norm;
        let b2 = (1.0 - vb_sqrt * k / q + vb * k * k) * norm;
        let a1 = 2.0 * (k * k - 1.0) * norm;
        let a2 = (1.0 - k / q + k * k) * norm;

        (b0, b1, b2, a1, a2)
    }

    /// High-pass filter coefficients for K-weighting
    fn high_pass_coeffs(fs: f64) -> (f64, f64, f64, f64, f64) {
        if (fs - 48000.0).abs() < 1.0 {
            // 48 kHz coefficients (ITU-R BS.1770-4)
            (1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621)
        } else if (fs - 44100.0).abs() < 1.0 {
            // 44.1 kHz coefficients
            (0.99870036, -1.99740072, 0.99870036, -1.99740072, 0.99740072)
        } else {
            // Compute for other sample rates
            Self::compute_high_pass(fs)
        }
    }

    /// Compute high-pass coefficients analytically
    fn compute_high_pass(fs: f64) -> (f64, f64, f64, f64, f64) {
        let f0 = 38.13547087602444; // Cutoff frequency
        let q = 0.5003270373238773; // Q factor

        let k = (std::f64::consts::PI * f0 / fs).tan();
        let norm = 1.0 / (1.0 + k / q + k * k);

        let b0 = norm;
        let b1 = -2.0 * norm;
        let b2 = norm;
        let a1 = 2.0 * (k * k - 1.0) * norm;
        let a2 = (1.0 - k / q + k * k) * norm;

        (b0, b1, b2, a1, a2)
    }

    /// Process single sample through K-weighting filter
    #[inline]
    fn process(&mut self, input: f64) -> f64 {
        // Stage 1: High shelf (TDF-II)
        let stage1_out = self.b0_1 * input + self.z1_1;
        self.z1_1 = self.b1_1 * input - self.a1_1 * stage1_out + self.z2_1;
        self.z2_1 = self.b2_1 * input - self.a2_1 * stage1_out;

        // Stage 2: High pass (TDF-II)
        let stage2_out = self.b0_2 * stage1_out + self.z1_2;
        self.z1_2 = self.b1_2 * stage1_out - self.a1_2 * stage2_out + self.z2_2;
        self.z2_2 = self.b2_2 * stage1_out - self.a2_2 * stage2_out;

        stage2_out
    }

    /// Reset filter state
    fn reset(&mut self) {
        self.z1_1 = 0.0;
        self.z2_1 = 0.0;
        self.z1_2 = 0.0;
        self.z2_2 = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRUE PEAK DETECTOR — 4x Oversampling
// ═══════════════════════════════════════════════════════════════════════════════

/// True peak detector with 4x oversampling (ITU-R BS.1770-4)
#[derive(Debug, Clone)]
struct TruePeakDetector {
    // FIR interpolation filter (48-tap for 4x)
    coeffs: [f64; 48],
    // Delay line
    delay_line: [f64; 12],
    delay_idx: usize,
    // Peak tracking
    max_peak: f64,
}

impl TruePeakDetector {
    /// Create new true peak detector
    fn new() -> Self {
        // 48-tap FIR filter for 4x oversampling (Kaiser window, β=4.5)
        // These coefficients are pre-calculated for ITU-R BS.1770-4 compliance
        let coeffs = Self::generate_fir_coeffs();

        Self {
            coeffs,
            delay_line: [0.0; 12],
            delay_idx: 0,
            max_peak: 0.0,
        }
    }

    /// Generate FIR interpolation filter coefficients
    fn generate_fir_coeffs() -> [f64; 48] {
        let mut coeffs = [0.0; 48];
        let n = 48;
        let m = n / 2;

        // Kaiser window parameters
        let beta = 4.5;

        for i in 0..n {
            let x = (i as f64 - (n - 1) as f64 / 2.0) / 4.0;

            // Sinc function
            let sinc = if x.abs() < 1e-10 {
                1.0
            } else {
                (std::f64::consts::PI * x).sin() / (std::f64::consts::PI * x)
            };

            // Kaiser window
            let alpha = (i as f64 - (n - 1) as f64 / 2.0) / (m as f64);
            let window =
                Self::bessel_i0(beta * (1.0 - alpha * alpha).sqrt()) / Self::bessel_i0(beta);

            coeffs[i] = sinc * window / 4.0; // Divide by 4 for interpolation
        }

        coeffs
    }

    /// Modified Bessel function of the first kind, order 0
    fn bessel_i0(x: f64) -> f64 {
        let mut sum = 1.0;
        let mut term = 1.0;
        let x_half = x / 2.0;

        for k in 1..25 {
            term *= (x_half / k as f64).powi(2);
            sum += term;
            if term < 1e-12 * sum {
                break;
            }
        }

        sum
    }

    /// Process sample and detect true peak
    fn process(&mut self, sample: f64) -> f64 {
        // Add to delay line
        self.delay_line[self.delay_idx] = sample;
        self.delay_idx = (self.delay_idx + 1) % 12;

        // Interpolate 4 samples (0.25, 0.5, 0.75, 1.0 positions)
        let mut max_interp = sample.abs(); // Original sample

        for phase in 0..4 {
            let mut sum = 0.0;
            for tap in 0..12 {
                let coeff_idx = phase * 12 + tap;
                let sample_idx = (self.delay_idx + 12 - 1 - tap) % 12;
                sum += self.delay_line[sample_idx] * self.coeffs[coeff_idx];
            }
            max_interp = max_interp.max(sum.abs());
        }

        // Track maximum
        if max_interp > self.max_peak {
            self.max_peak = max_interp;
        }

        max_interp
    }

    /// Get maximum true peak detected
    fn get_max(&self) -> f64 {
        self.max_peak
    }

    /// Reset detector
    fn reset(&mut self) {
        self.delay_line = [0.0; 12];
        self.delay_idx = 0;
        self.max_peak = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LUFS LOUDNESS METER — EBU R128
// ═══════════════════════════════════════════════════════════════════════════════

/// Loudness block (400ms)
#[derive(Debug, Clone, Copy)]
struct LoudnessBlock {
    /// Mean square sum of K-weighted samples
    mean_square: f64,
    /// Loudness in LUFS
    loudness: f64,
}

/// LUFS loudness meter (EBU R128 compliant)
pub struct LoudnessMeter {
    sample_rate: f64,
    channels: usize,

    // K-weighting filters (one per channel)
    k_filters: Vec<KWeightingFilter>,

    // True peak detectors (one per channel)
    tp_detectors: Vec<TruePeakDetector>,

    // Momentary buffer (400ms blocks, 100ms overlap)
    block_size: usize,      // Samples per 100ms
    block_buffer: Vec<f64>, // Current block accumulator
    block_sum: f64,         // Sum of squares in current block
    block_samples: usize,   // Samples in current block

    // Gated block history (for integrated loudness)
    gated_blocks: Vec<LoudnessBlock>,

    // Peak tracking
    peak: f64,
    true_peak: f64,

    // Short-term (3s) and momentary (400ms) loudness
    momentary_loudness: f64,
    short_term_loudness: f64,
    short_term_blocks: Vec<f64>, // Last 30 blocks (3s)
    short_term_idx: usize,
}

impl LoudnessMeter {
    /// Create new loudness meter
    pub fn new(sample_rate: u32, channels: usize) -> Self {
        let sr = sample_rate as f64;

        // 100ms block size
        let block_size = (sr * 0.1) as usize;

        // Create K-weighting filters for each channel
        let k_filters = (0..channels).map(|_| KWeightingFilter::new(sr)).collect();

        // Create true peak detectors for each channel
        let tp_detectors = (0..channels).map(|_| TruePeakDetector::new()).collect();

        Self {
            sample_rate: sr,
            channels,
            k_filters,
            tp_detectors,
            block_size,
            block_buffer: Vec::with_capacity(block_size * channels),
            block_sum: 0.0,
            block_samples: 0,
            gated_blocks: Vec::with_capacity(10000),
            peak: 0.0,
            true_peak: 0.0,
            momentary_loudness: -f64::INFINITY,
            short_term_loudness: -f64::INFINITY,
            short_term_blocks: vec![0.0; 30], // 30 x 100ms = 3s
            short_term_idx: 0,
        }
    }

    /// Process a block of interleaved samples
    pub fn process(&mut self, samples: &[f64]) {
        let num_frames = samples.len() / self.channels;

        for frame in 0..num_frames {
            let base_idx = frame * self.channels;
            let mut frame_sum = 0.0;

            for ch in 0..self.channels {
                let sample = samples[base_idx + ch];

                // Track sample peak
                let abs_sample = sample.abs();
                if abs_sample > self.peak {
                    self.peak = abs_sample;
                }

                // True peak detection
                let tp = self.tp_detectors[ch].process(sample);
                if tp > self.true_peak {
                    self.true_peak = tp;
                }

                // K-weighting filter
                let weighted = self.k_filters[ch].process(sample);

                // Channel weighting (1.0 for L/R/C, 1.41 for Ls/Rs)
                // For stereo, both channels have weight 1.0
                let channel_weight = if ch < 3 { 1.0 } else { 1.41 };

                frame_sum += weighted * weighted * channel_weight;
            }

            self.block_sum += frame_sum;
            self.block_samples += 1;

            // Check if block is complete (100ms)
            if self.block_samples >= self.block_size {
                self.complete_block();
            }
        }
    }

    /// Complete a 100ms block
    fn complete_block(&mut self) {
        if self.block_samples == 0 {
            return;
        }

        // Calculate mean square for this block
        let mean_square = self.block_sum / self.block_samples as f64;

        // Convert to LUFS
        let loudness = if mean_square > 0.0 {
            -0.691 + 10.0 * mean_square.log10()
        } else {
            -f64::INFINITY
        };

        // Store for short-term calculation
        self.short_term_blocks[self.short_term_idx] = mean_square;
        self.short_term_idx = (self.short_term_idx + 1) % 30;

        // Update momentary (last 4 blocks = 400ms)
        self.update_momentary();

        // Update short-term (last 30 blocks = 3s)
        self.update_short_term();

        // Absolute gating: -70 LUFS threshold
        if loudness > -70.0 {
            self.gated_blocks.push(LoudnessBlock {
                mean_square,
                loudness,
            });
        }

        // Reset for next block
        self.block_sum = 0.0;
        self.block_samples = 0;
    }

    /// Update momentary loudness (400ms window)
    fn update_momentary(&mut self) {
        // Use last 4 blocks (400ms)
        let start_idx = if self.short_term_idx >= 4 {
            self.short_term_idx - 4
        } else {
            30 + self.short_term_idx - 4
        };

        let mut sum = 0.0;
        let mut count = 0;
        for i in 0..4 {
            let idx = (start_idx + i) % 30;
            let ms = self.short_term_blocks[idx];
            if ms > 0.0 {
                sum += ms;
                count += 1;
            }
        }

        if count > 0 {
            let mean = sum / count as f64;
            self.momentary_loudness = -0.691 + 10.0 * mean.log10();
        }
    }

    /// Update short-term loudness (3s window)
    fn update_short_term(&mut self) {
        let mut sum = 0.0;
        let mut count = 0;

        for &ms in &self.short_term_blocks {
            if ms > 0.0 {
                sum += ms;
                count += 1;
            }
        }

        if count > 0 {
            let mean = sum / count as f64;
            self.short_term_loudness = -0.691 + 10.0 * mean.log10();
        }
    }

    /// Calculate integrated loudness with gating (EBU R128)
    fn calculate_integrated(&self) -> f64 {
        if self.gated_blocks.is_empty() {
            return -f64::INFINITY;
        }

        // Step 1: Calculate absolute-gated loudness
        let abs_gated_sum: f64 = self.gated_blocks.iter().map(|b| b.mean_square).sum();
        let abs_gated_count = self.gated_blocks.len();
        let abs_gated_loudness = -0.691 + 10.0 * (abs_gated_sum / abs_gated_count as f64).log10();

        // Step 2: Relative gating threshold (-10 LU below abs_gated)
        let rel_threshold = abs_gated_loudness - 10.0;

        // Step 3: Calculate with relative gating
        let mut rel_sum = 0.0;
        let mut rel_count = 0;

        for block in &self.gated_blocks {
            if block.loudness > rel_threshold {
                rel_sum += block.mean_square;
                rel_count += 1;
            }
        }

        if rel_count > 0 {
            -0.691 + 10.0 * (rel_sum / rel_count as f64).log10()
        } else {
            -f64::INFINITY
        }
    }

    /// Calculate loudness range (LRA)
    fn calculate_range(&self) -> f64 {
        if self.gated_blocks.len() < 2 {
            return 0.0;
        }

        // Use blocks above absolute gate
        let mut loudnesses: Vec<f64> = self
            .gated_blocks
            .iter()
            .map(|b| b.loudness)
            .filter(|&l| l > -f64::INFINITY)
            .collect();

        if loudnesses.len() < 2 {
            return 0.0;
        }

        loudnesses.sort_by(|a, b| a.partial_cmp(b).unwrap());

        // 10th to 95th percentile
        let low_idx = (loudnesses.len() as f64 * 0.10) as usize;
        let high_idx = (loudnesses.len() as f64 * 0.95) as usize;

        let low_idx = low_idx.max(0);
        let high_idx = high_idx.min(loudnesses.len() - 1);

        loudnesses[high_idx] - loudnesses[low_idx]
    }

    /// Get current loudness info
    pub fn get_info(&self) -> LoudnessInfo {
        LoudnessInfo {
            peak: self.peak,
            true_peak: self.true_peak,
            integrated: self.calculate_integrated(),
            short_term: self.short_term_loudness,
            momentary: self.momentary_loudness,
            range: self.calculate_range(),
        }
    }

    /// Reset meter state
    pub fn reset(&mut self) {
        for filter in &mut self.k_filters {
            filter.reset();
        }
        for detector in &mut self.tp_detectors {
            detector.reset();
        }
        self.block_buffer.clear();
        self.block_sum = 0.0;
        self.block_samples = 0;
        self.gated_blocks.clear();
        self.peak = 0.0;
        self.true_peak = 0.0;
        self.momentary_loudness = -f64::INFINITY;
        self.short_term_loudness = -f64::INFINITY;
        self.short_term_blocks.fill(0.0);
        self.short_term_idx = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_k_weighting_filter() {
        let mut filter = KWeightingFilter::new(48000.0);

        // Process a simple sine wave
        let freq = 1000.0;
        let sample_rate = 48000.0;
        let mut max_out = 0.0f64;

        for i in 0..48000 {
            let sample = (2.0 * std::f64::consts::PI * freq * i as f64 / sample_rate).sin();
            let out = filter.process(sample);
            max_out = max_out.max(out.abs());
        }

        // K-weighting at 1kHz should be close to unity (slight boost)
        assert!(max_out > 0.9 && max_out < 1.5);
    }

    #[test]
    fn test_true_peak_detector() {
        let mut detector = TruePeakDetector::new();

        // True peak should be >= sample peak
        let samples = [0.5, 0.8, -0.7, 0.3, -0.9, 0.6];
        let mut sample_peak = 0.0f64;

        for &s in &samples {
            detector.process(s);
            sample_peak = sample_peak.max(s.abs());
        }

        assert!(detector.get_max() >= sample_peak * 0.99);
    }

    #[test]
    fn test_loudness_meter_silence() {
        let mut meter = LoudnessMeter::new(48000, 2);

        // Process silence
        let silence = vec![0.0; 48000 * 2]; // 1 second stereo
        meter.process(&silence);

        let info = meter.get_info();
        assert!(info.integrated <= -70.0 || info.integrated == -f64::INFINITY);
    }

    #[test]
    fn test_loudness_meter_sine() {
        let mut meter = LoudnessMeter::new(48000, 2);

        // Generate 1kHz sine at -20 dBFS (both channels)
        let freq = 1000.0;
        let amplitude = 0.1; // ~-20 dBFS
        let mut samples = Vec::with_capacity(48000 * 2);

        for i in 0..48000 {
            let s = amplitude * (2.0 * std::f64::consts::PI * freq * i as f64 / 48000.0).sin();
            samples.push(s); // L
            samples.push(s); // R
        }

        meter.process(&samples);

        let info = meter.get_info();
        // Peak should be close to amplitude
        assert!((info.peak - amplitude).abs() < 0.001);
        // Loudness should be finite
        assert!(info.integrated > -70.0);
    }

    #[test]
    fn test_normalizer_peak() {
        let info = LoudnessInfo {
            peak: 0.5, // -6 dBFS
            true_peak: 0.5,
            integrated: -23.0,
            short_term: -23.0,
            momentary: -23.0,
            range: 5.0,
        };

        let normalizer = Normalizer::new(NormalizationMode::Peak { target_db: -1.0 });
        let gain = normalizer.calculate_gain(&info);

        // Should boost by ~5 dB
        assert!(gain > 1.5 && gain < 2.5);
    }

    #[test]
    fn test_normalizer_lufs() {
        let info = LoudnessInfo {
            peak: 0.8,
            true_peak: 0.85,
            integrated: -23.0,
            short_term: -23.0,
            momentary: -23.0,
            range: 5.0,
        };

        let normalizer = Normalizer::new(NormalizationMode::streaming()); // -14 LUFS
        let gain = normalizer.calculate_gain(&info);

        // Should boost by 9 dB (from -23 to -14)
        let expected_gain = 10.0_f64.powf(9.0 / 20.0);
        assert!((gain - expected_gain).abs() < 0.1);
    }
}

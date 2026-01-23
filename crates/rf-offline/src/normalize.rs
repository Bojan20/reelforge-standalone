//! Audio normalization

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

/// LUFS loudness meter (EBU R128)
pub struct LoudnessMeter {
    sample_rate: f64,
    channels: usize,
    // Pre-filter states (K-weighting)
    stage1_state: Vec<[f64; 2]>, // High shelf
    stage2_state: Vec<[f64; 2]>, // High pass
    // Momentary buffer (400ms)
    momentary_buffer: Vec<f64>,
    momentary_sum: f64,
    momentary_count: usize,
    // Short-term buffer (3s)
    short_term_buffer: Vec<f64>,
    short_term_idx: usize,
    // Integrated buffer (gated)
    integrated_blocks: Vec<f64>,
    // Peak tracking
    peak: f64,
    true_peak_buffer: Vec<f64>,
    true_peak: f64,
}

impl LoudnessMeter {
    /// Create new loudness meter
    pub fn new(sample_rate: u32, channels: usize) -> Self {
        let sr = sample_rate as f64;

        // Samples for 400ms (momentary)
        let momentary_samples = (sr * 0.4) as usize;

        // Samples for 3s (short-term), 100ms overlap
        let short_term_blocks = 30; // 30 x 100ms = 3s

        Self {
            sample_rate: sr,
            channels,
            stage1_state: vec![[0.0; 2]; channels],
            stage2_state: vec![[0.0; 2]; channels],
            momentary_buffer: vec![0.0; momentary_samples],
            momentary_sum: 0.0,
            momentary_count: 0,
            short_term_buffer: vec![0.0; short_term_blocks],
            short_term_idx: 0,
            integrated_blocks: Vec::with_capacity(10000),
            peak: 0.0,
            true_peak_buffer: Vec::with_capacity(4), // 4x oversampling
            true_peak: 0.0,
        }
    }

    /// Process a block of samples
    pub fn process(&mut self, samples: &[f64]) {
        for &sample in samples {
            // Track peak
            let abs_sample = sample.abs();
            if abs_sample > self.peak {
                self.peak = abs_sample;
            }

            // True peak (simplified - in production would use 4x oversampling)
            if abs_sample > self.true_peak {
                self.true_peak = abs_sample;
            }

            // K-weighting filter would be applied here
            // For now, use unweighted (simplified implementation)
            let weighted = sample;

            // Accumulate for momentary loudness
            let squared = weighted * weighted;
            self.momentary_sum += squared;
            self.momentary_count += 1;
        }
    }

    /// Get current loudness info
    pub fn get_info(&self) -> LoudnessInfo {
        // Calculate momentary loudness
        let mean_square = if self.momentary_count > 0 {
            self.momentary_sum / self.momentary_count as f64
        } else {
            0.0
        };

        let momentary_lufs = if mean_square > 0.0 {
            -0.691 + 10.0 * mean_square.log10()
        } else {
            -70.0
        };

        LoudnessInfo {
            peak: self.peak,
            true_peak: self.true_peak,
            integrated: momentary_lufs, // Simplified
            short_term: momentary_lufs,
            momentary: momentary_lufs,
            range: 0.0,
        }
    }

    /// Reset meter state
    pub fn reset(&mut self) {
        for state in &mut self.stage1_state {
            *state = [0.0; 2];
        }
        for state in &mut self.stage2_state {
            *state = [0.0; 2];
        }
        self.momentary_buffer.fill(0.0);
        self.momentary_sum = 0.0;
        self.momentary_count = 0;
        self.short_term_buffer.fill(0.0);
        self.short_term_idx = 0;
        self.integrated_blocks.clear();
        self.peak = 0.0;
        self.true_peak = 0.0;
    }
}

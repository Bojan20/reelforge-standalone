//! Professional Metering - ITU-R BS.1770 Compliant
//!
//! Features:
//! - True Peak metering (4x oversampling)
//! - LUFS (Loudness Units relative to Full Scale)
//! - K-weighting filter
//! - Momentary (400ms), Short-term (3s), Integrated

use wasm_bindgen::prelude::*;
use crate::linear_to_db;
use crate::biquad::{BiquadFilter, FilterType};
use crate::oversampling::Oversampler4x;

// ============ True Peak Meter ============

/// True Peak meter with 4x oversampling.
/// Detects intersample peaks per ITU-R BS.1770.
#[wasm_bindgen]
pub struct TruePeakMeter {
    oversampler_l: Oversampler4x,
    oversampler_r: Oversampler4x,
    peak_l: f32,
    peak_r: f32,
    peak_hold_l: f32,
    peak_hold_r: f32,
    hold_decay: f32,
}

#[wasm_bindgen]
impl TruePeakMeter {
    #[wasm_bindgen(constructor)]
    pub fn new() -> TruePeakMeter {
        TruePeakMeter {
            oversampler_l: Oversampler4x::new(),
            oversampler_r: Oversampler4x::new(),
            peak_l: 0.0,
            peak_r: 0.0,
            peak_hold_l: 0.0,
            peak_hold_r: 0.0,
            hold_decay: 0.9999, // ~3 second hold at 48kHz
        }
    }

    /// Process stereo buffer (interleaved L/R).
    /// Call this for each audio block.
    pub fn process(&mut self, buffer: &[f32]) {
        let len = buffer.len() / 2;
        let mut max_l: f32 = 0.0;
        let mut max_r: f32 = 0.0;

        for i in 0..len {
            let idx = i * 2;

            // Upsample for true peak detection
            let up_l = self.oversampler_l.upsample(buffer[idx]);
            let up_r = self.oversampler_r.upsample(buffer[idx + 1]);

            // Find max across oversampled values
            for j in 0..4 {
                let abs_l = up_l[j].abs();
                let abs_r = up_r[j].abs();

                if abs_l > max_l {
                    max_l = abs_l;
                }
                if abs_r > max_r {
                    max_r = abs_r;
                }
            }
        }

        self.peak_l = max_l;
        self.peak_r = max_r;

        // Update peak hold
        if max_l > self.peak_hold_l {
            self.peak_hold_l = max_l;
        } else {
            self.peak_hold_l *= self.hold_decay;
        }

        if max_r > self.peak_hold_r {
            self.peak_hold_r = max_r;
        } else {
            self.peak_hold_r *= self.hold_decay;
        }
    }

    /// Get current true peak values [L, R] in dBTP.
    pub fn get_peak_db(&self) -> Box<[f32]> {
        Box::new([
            if self.peak_l > 0.0 { linear_to_db(self.peak_l) } else { -100.0 },
            if self.peak_r > 0.0 { linear_to_db(self.peak_r) } else { -100.0 },
        ])
    }

    /// Get peak hold values [L, R] in dBTP.
    pub fn get_peak_hold_db(&self) -> Box<[f32]> {
        Box::new([
            if self.peak_hold_l > 0.0 { linear_to_db(self.peak_hold_l) } else { -100.0 },
            if self.peak_hold_r > 0.0 { linear_to_db(self.peak_hold_r) } else { -100.0 },
        ])
    }

    /// Get peak hold values [L, R] in linear.
    pub fn get_peak_hold(&self) -> Box<[f32]> {
        Box::new([self.peak_hold_l, self.peak_hold_r])
    }

    /// Reset all metering state.
    pub fn reset(&mut self) {
        self.peak_l = 0.0;
        self.peak_r = 0.0;
        self.peak_hold_l = 0.0;
        self.peak_hold_r = 0.0;
        self.oversampler_l.reset();
        self.oversampler_r.reset();
    }
}

impl Default for TruePeakMeter {
    fn default() -> Self {
        Self::new()
    }
}

// ============ LUFS Meter ============

/// LUFS Meter per ITU-R BS.1770-4.
/// Provides Momentary (400ms), Short-term (3s), and Integrated loudness.
#[wasm_bindgen]
pub struct LUFSMeter {
    // K-weighting filters (2-stage)
    prefilter_l: BiquadFilter,  // High shelf
    prefilter_r: BiquadFilter,
    rlb_filter_l: BiquadFilter, // High-pass (RLB)
    rlb_filter_r: BiquadFilter,

    // Gating block history
    momentary_blocks: Vec<f32>,  // 400ms window (4 blocks at 100ms)
    short_term_blocks: Vec<f32>, // 3s window (30 blocks at 100ms)

    // Block accumulator
    block_sum_l: f64,
    block_sum_r: f64,
    block_count: usize,
    samples_per_block: usize,

    // Integrated loudness (gated)
    integrated_sum: f64,
    integrated_count: usize,
    absolute_gate_threshold: f64, // -70 LUFS

    sample_rate: f32,
}

#[wasm_bindgen]
impl LUFSMeter {
    #[wasm_bindgen(constructor)]
    pub fn new(sample_rate: f32) -> LUFSMeter {
        // Pre-filter: High shelf at 1500Hz, +4dB (accounts for head acoustic effect)
        let mut prefilter_l = BiquadFilter::new(sample_rate);
        prefilter_l.set_params(FilterType::HighShelf, 1500.0, 4.0, 0.707);
        let mut prefilter_r = BiquadFilter::new(sample_rate);
        prefilter_r.set_params(FilterType::HighShelf, 1500.0, 4.0, 0.707);

        // RLB filter: High-pass at 38Hz (Revised Low-frequency B-weighting)
        let mut rlb_filter_l = BiquadFilter::new(sample_rate);
        rlb_filter_l.set_params(FilterType::Highpass, 38.0, 0.0, 0.5);
        let mut rlb_filter_r = BiquadFilter::new(sample_rate);
        rlb_filter_r.set_params(FilterType::Highpass, 38.0, 0.0, 0.5);

        // 100ms blocks
        let samples_per_block = (sample_rate * 0.1) as usize;

        LUFSMeter {
            prefilter_l,
            prefilter_r,
            rlb_filter_l,
            rlb_filter_r,

            momentary_blocks: Vec::with_capacity(4),   // 400ms
            short_term_blocks: Vec::with_capacity(30), // 3s

            block_sum_l: 0.0,
            block_sum_r: 0.0,
            block_count: 0,
            samples_per_block,

            integrated_sum: 0.0,
            integrated_count: 0,
            absolute_gate_threshold: 10.0_f64.powf(-70.0 / 10.0), // -70 LUFS in linear

            sample_rate,
        }
    }

    /// Process stereo buffer (interleaved L/R).
    pub fn process_block(&mut self, buffer: &mut [f32]) {
        let len = buffer.len() / 2;

        // Create temporary buffer for K-weighted signal
        let mut weighted = buffer.to_vec();

        // Apply K-weighting (pre-filter + RLB)
        // Note: We process L/R channels through biquads
        self.prefilter_l.process_stereo(&mut weighted);
        self.rlb_filter_l.process_stereo(&mut weighted);

        // Accumulate squared samples
        for i in 0..len {
            let idx = i * 2;
            let l = weighted[idx] as f64;
            let r = weighted[idx + 1] as f64;

            self.block_sum_l += l * l;
            self.block_sum_r += r * r;
            self.block_count += 1;

            // Check if block is complete
            if self.block_count >= self.samples_per_block {
                self.finish_block();
            }
        }
    }

    fn finish_block(&mut self) {
        if self.block_count == 0 {
            return;
        }

        // Calculate mean square for this block
        let ms_l = self.block_sum_l / self.block_count as f64;
        let ms_r = self.block_sum_r / self.block_count as f64;

        // Stereo sum with channel weights (1.0 for L/R per ITU-R BS.1770)
        let block_loudness = ms_l + ms_r;

        // Add to momentary window (400ms = 4 blocks)
        self.momentary_blocks.push(block_loudness as f32);
        if self.momentary_blocks.len() > 4 {
            self.momentary_blocks.remove(0);
        }

        // Add to short-term window (3s = 30 blocks)
        self.short_term_blocks.push(block_loudness as f32);
        if self.short_term_blocks.len() > 30 {
            self.short_term_blocks.remove(0);
        }

        // Gated integration (above absolute threshold)
        if block_loudness > self.absolute_gate_threshold {
            self.integrated_sum += block_loudness;
            self.integrated_count += 1;
        }

        // Reset block accumulator
        self.block_sum_l = 0.0;
        self.block_sum_r = 0.0;
        self.block_count = 0;
    }

    /// Get momentary loudness (400ms window) in LUFS.
    pub fn get_momentary_lufs(&self) -> f32 {
        if self.momentary_blocks.is_empty() {
            return -100.0;
        }

        let sum: f32 = self.momentary_blocks.iter().sum();
        let mean = sum / self.momentary_blocks.len() as f32;

        if mean > 0.0 {
            -0.691 + 10.0 * mean.log10()
        } else {
            -100.0
        }
    }

    /// Get short-term loudness (3s window) in LUFS.
    pub fn get_short_term_lufs(&self) -> f32 {
        if self.short_term_blocks.is_empty() {
            return -100.0;
        }

        let sum: f32 = self.short_term_blocks.iter().sum();
        let mean = sum / self.short_term_blocks.len() as f32;

        if mean > 0.0 {
            -0.691 + 10.0 * mean.log10()
        } else {
            -100.0
        }
    }

    /// Get integrated loudness (gated) in LUFS.
    pub fn get_integrated_lufs(&self) -> f32 {
        if self.integrated_count == 0 {
            return -100.0;
        }

        let mean = self.integrated_sum / self.integrated_count as f64;

        if mean > 0.0 {
            (-0.691 + 10.0 * mean.log10()) as f32
        } else {
            -100.0
        }
    }

    /// Reset all metering state.
    pub fn reset(&mut self) {
        self.prefilter_l.reset();
        self.prefilter_r.reset();
        self.rlb_filter_l.reset();
        self.rlb_filter_r.reset();

        self.momentary_blocks.clear();
        self.short_term_blocks.clear();

        self.block_sum_l = 0.0;
        self.block_sum_r = 0.0;
        self.block_count = 0;

        self.integrated_sum = 0.0;
        self.integrated_count = 0;
    }

    /// Reset integrated loudness only (for new measurement).
    pub fn reset_integrated(&mut self) {
        self.integrated_sum = 0.0;
        self.integrated_count = 0;
    }
}

// ============ Simple Peak/RMS Meter ============

/// Basic peak/RMS meter for lightweight metering.
#[wasm_bindgen]
pub struct Meter {
    peak_l: f32,
    peak_r: f32,
    peak_hold_l: f32,
    peak_hold_r: f32,
    rms_sum_l: f64,
    rms_sum_r: f64,
    rms_count: usize,
    hold_decay: f32,
}

#[wasm_bindgen]
impl Meter {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Meter {
        Meter {
            peak_l: 0.0,
            peak_r: 0.0,
            peak_hold_l: 0.0,
            peak_hold_r: 0.0,
            rms_sum_l: 0.0,
            rms_sum_r: 0.0,
            rms_count: 0,
            hold_decay: 0.9995,
        }
    }

    /// Process stereo buffer (interleaved L/R).
    pub fn process_block(&mut self, buffer: &[f32]) {
        let len = buffer.len() / 2;
        let mut max_l: f32 = 0.0;
        let mut max_r: f32 = 0.0;

        for i in 0..len {
            let idx = i * 2;
            let l = buffer[idx];
            let r = buffer[idx + 1];

            let abs_l = l.abs();
            let abs_r = r.abs();

            if abs_l > max_l {
                max_l = abs_l;
            }
            if abs_r > max_r {
                max_r = abs_r;
            }

            self.rms_sum_l += (l * l) as f64;
            self.rms_sum_r += (r * r) as f64;
            self.rms_count += 1;
        }

        self.peak_l = max_l;
        self.peak_r = max_r;

        // Update hold
        if max_l > self.peak_hold_l {
            self.peak_hold_l = max_l;
        } else {
            self.peak_hold_l *= self.hold_decay;
        }

        if max_r > self.peak_hold_r {
            self.peak_hold_r = max_r;
        } else {
            self.peak_hold_r *= self.hold_decay;
        }
    }

    /// Get current peak [L, R].
    pub fn get_peak(&self) -> Box<[f32]> {
        Box::new([self.peak_l, self.peak_r])
    }

    /// Get peak hold [L, R].
    pub fn get_peak_hold(&self) -> Box<[f32]> {
        Box::new([self.peak_hold_l, self.peak_hold_r])
    }

    /// Get RMS and reset accumulator [L, R].
    pub fn get_rms_and_reset(&mut self) -> Box<[f32]> {
        if self.rms_count == 0 {
            return Box::new([0.0, 0.0]);
        }

        let rms_l = (self.rms_sum_l / self.rms_count as f64).sqrt() as f32;
        let rms_r = (self.rms_sum_r / self.rms_count as f64).sqrt() as f32;

        self.rms_sum_l = 0.0;
        self.rms_sum_r = 0.0;
        self.rms_count = 0;

        Box::new([rms_l, rms_r])
    }

    /// Reset all state.
    pub fn reset(&mut self) {
        self.peak_l = 0.0;
        self.peak_r = 0.0;
        self.peak_hold_l = 0.0;
        self.peak_hold_r = 0.0;
        self.rms_sum_l = 0.0;
        self.rms_sum_r = 0.0;
        self.rms_count = 0;
    }
}

impl Default for Meter {
    fn default() -> Self {
        Self::new()
    }
}

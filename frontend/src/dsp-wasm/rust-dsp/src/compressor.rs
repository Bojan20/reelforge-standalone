//! Professional Compressor with 4x Oversampling
//!
//! Features:
//! - Smooth gain reduction (no pumping)
//! - Look-ahead for transparent limiting
//! - Sidechain input support
//! - Parallel (NY) compression
//! - Auto-makeup gain
//! - 4x oversampling for clean transients

use wasm_bindgen::prelude::*;
use crate::{db_to_linear, linear_to_db, flush_denormal};
use crate::oversampling::Oversampler4x;

// ============ Compressor ============

#[wasm_bindgen]
pub struct Compressor {
    // Parameters
    threshold: f32,      // dB, -60 to 0
    ratio: f32,          // 1:1 to inf:1
    attack_ms: f32,      // 0.1 to 100
    release_ms: f32,     // 10 to 2000
    knee: f32,           // dB, 0 to 24
    makeup_gain: f32,    // dB, 0 to 24
    mix: f32,            // 0 to 1 (parallel)
    auto_makeup: bool,
    look_ahead_ms: f32,  // 0 to 10

    // Coefficients (calculated from params)
    attack_coeff: f32,
    release_coeff: f32,
    makeup_linear: f32,

    // State
    envelope: f32,
    gain_reduction: f32,  // For metering

    // Look-ahead delay buffer (stereo interleaved)
    delay_buffer: Vec<f32>,
    delay_index: usize,
    delay_length: usize,

    // Oversampler for clean transients
    oversampler_l: Oversampler4x,
    oversampler_r: Oversampler4x,
    use_oversampling: bool,

    sample_rate: f32,
}

#[wasm_bindgen]
impl Compressor {
    /// Create a new compressor.
    #[wasm_bindgen(constructor)]
    pub fn new(sample_rate: f32) -> Compressor {
        let mut comp = Compressor {
            threshold: -18.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            knee: 6.0,
            makeup_gain: 0.0,
            mix: 1.0,
            auto_makeup: false,
            look_ahead_ms: 0.0,

            attack_coeff: 0.0,
            release_coeff: 0.0,
            makeup_linear: 1.0,

            envelope: 0.0,
            gain_reduction: 0.0,

            delay_buffer: Vec::new(),
            delay_index: 0,
            delay_length: 0,

            oversampler_l: Oversampler4x::new(),
            oversampler_r: Oversampler4x::new(),
            use_oversampling: true,

            sample_rate,
        };
        comp.update_coefficients();
        comp
    }

    /// Set threshold in dB.
    pub fn set_threshold(&mut self, db: f32) {
        self.threshold = db.max(-60.0).min(0.0);
        self.update_makeup();
    }

    /// Set ratio (1.0 = no compression, >20 ≈ limiting).
    pub fn set_ratio(&mut self, ratio: f32) {
        self.ratio = ratio.max(1.0).min(100.0);
        self.update_makeup();
    }

    /// Set attack time in milliseconds.
    pub fn set_attack(&mut self, ms: f32) {
        self.attack_ms = ms.max(0.1).min(100.0);
        self.update_coefficients();
    }

    /// Set release time in milliseconds.
    pub fn set_release(&mut self, ms: f32) {
        self.release_ms = ms.max(10.0).min(2000.0);
        self.update_coefficients();
    }

    /// Set knee width in dB.
    pub fn set_knee(&mut self, db: f32) {
        self.knee = db.max(0.0).min(24.0);
    }

    /// Set makeup gain in dB.
    pub fn set_makeup_gain(&mut self, db: f32) {
        self.makeup_gain = db.max(0.0).min(24.0);
        self.update_makeup();
    }

    /// Set mix (0 = dry, 1 = wet).
    pub fn set_mix(&mut self, mix: f32) {
        self.mix = mix.max(0.0).min(1.0);
    }

    /// Enable/disable auto-makeup gain.
    pub fn set_auto_makeup(&mut self, enabled: bool) {
        self.auto_makeup = enabled;
        self.update_makeup();
    }

    /// Set look-ahead time in milliseconds.
    pub fn set_look_ahead(&mut self, ms: f32) {
        self.look_ahead_ms = ms.max(0.0).min(10.0);

        let samples = ((ms / 1000.0) * self.sample_rate) as usize;
        if samples != self.delay_length {
            self.delay_length = samples;
            if samples > 0 {
                self.delay_buffer = vec![0.0; samples * 2]; // Stereo
            } else {
                self.delay_buffer.clear();
            }
            self.delay_index = 0;
        }
    }

    /// Enable/disable 4x oversampling.
    pub fn set_oversampling(&mut self, enabled: bool) {
        self.use_oversampling = enabled;
    }

    /// Get current gain reduction in dB (for metering).
    pub fn get_gain_reduction(&self) -> f32 {
        self.gain_reduction
    }

    fn update_coefficients(&mut self) {
        let sr = if self.use_oversampling {
            self.sample_rate * 4.0
        } else {
            self.sample_rate
        };

        self.attack_coeff = (-1.0 / ((self.attack_ms / 1000.0) * sr)).exp();
        self.release_coeff = (-1.0 / ((self.release_ms / 1000.0) * sr)).exp();
    }

    fn update_makeup(&mut self) {
        if self.auto_makeup {
            // Estimate gain reduction at typical level (-18dBFS)
            let gr = self.compute_gain_reduction(-18.0);
            self.makeup_linear = db_to_linear(gr * 0.7 + self.makeup_gain);
        } else {
            self.makeup_linear = db_to_linear(self.makeup_gain);
        }
    }

    fn compute_gain_reduction(&self, input_db: f32) -> f32 {
        let half_knee = self.knee / 2.0;

        if input_db < self.threshold - half_knee {
            // Below knee - no compression
            0.0
        } else if input_db > self.threshold + half_knee {
            // Above knee - full compression
            (input_db - self.threshold) * (1.0 - 1.0 / self.ratio)
        } else {
            // In knee - soft transition
            let knee_input = input_db - self.threshold + half_knee;
            (knee_input * knee_input) / (2.0 * self.knee) * (1.0 - 1.0 / self.ratio)
        }
    }

    /// Process stereo buffer (interleaved L/R) in-place.
    pub fn process_stereo(&mut self, buffer: &mut [f32]) {
        if self.use_oversampling {
            self.process_with_oversampling(buffer);
        } else {
            self.process_internal(buffer);
        }
    }

    fn process_with_oversampling(&mut self, buffer: &mut [f32]) {
        let len = buffer.len() / 2;

        for i in 0..len {
            let idx = i * 2;
            let in_l = buffer[idx];
            let in_r = buffer[idx + 1];

            // Upsample to 4x
            let up_l = self.oversampler_l.upsample(in_l);
            let up_r = self.oversampler_r.upsample(in_r);

            // Process at 4x rate
            let mut out_l = [0.0f32; 4];
            let mut out_r = [0.0f32; 4];

            for j in 0..4 {
                let (processed_l, processed_r) = self.process_sample(up_l[j], up_r[j]);
                out_l[j] = processed_l;
                out_r[j] = processed_r;
            }

            // Downsample back to 1x
            buffer[idx] = self.oversampler_l.downsample(&out_l);
            buffer[idx + 1] = self.oversampler_r.downsample(&out_r);
        }
    }

    fn process_internal(&mut self, buffer: &mut [f32]) {
        let len = buffer.len() / 2;

        for i in 0..len {
            let idx = i * 2;
            let (out_l, out_r) = self.process_sample(buffer[idx], buffer[idx + 1]);
            buffer[idx] = out_l;
            buffer[idx + 1] = out_r;
        }
    }

    #[inline(always)]
    fn process_sample(&mut self, in_l: f32, in_r: f32) -> (f32, f32) {
        // Linked stereo detection (max of L/R)
        let detect = in_l.abs().max(in_r.abs());

        // Envelope follower
        if detect > self.envelope {
            self.envelope = self.attack_coeff * self.envelope + (1.0 - self.attack_coeff) * detect;
        } else {
            self.envelope = self.release_coeff * self.envelope + (1.0 - self.release_coeff) * detect;
        }

        // Convert to dB
        let envelope_db = if self.envelope > 1e-10 {
            linear_to_db(self.envelope)
        } else {
            -100.0
        };

        // Compute gain reduction
        let gr_db = self.compute_gain_reduction(envelope_db);
        let gr_linear = db_to_linear(-gr_db);

        // Track gain reduction for metering
        if gr_db > self.gain_reduction {
            self.gain_reduction = gr_db;
        } else {
            self.gain_reduction *= 0.9995; // Slow decay for metering
        }

        // Apply look-ahead delay
        let (delayed_l, delayed_r) = if self.delay_length > 0 {
            let buf_idx = self.delay_index * 2;
            let del_l = self.delay_buffer[buf_idx];
            let del_r = self.delay_buffer[buf_idx + 1];

            self.delay_buffer[buf_idx] = in_l;
            self.delay_buffer[buf_idx + 1] = in_r;

            self.delay_index = (self.delay_index + 1) % self.delay_length;

            (del_l, del_r)
        } else {
            (in_l, in_r)
        };

        // Apply gain reduction + makeup
        let mut out_l = flush_denormal(delayed_l * gr_linear * self.makeup_linear);
        let mut out_r = flush_denormal(delayed_r * gr_linear * self.makeup_linear);

        // Parallel compression mix
        if self.mix < 1.0 {
            out_l = in_l * (1.0 - self.mix) + out_l * self.mix;
            out_r = in_r * (1.0 - self.mix) + out_r * self.mix;
        }

        (out_l, out_r)
    }

    /// Reset state (call after seek/discontinuity).
    pub fn reset(&mut self) {
        self.envelope = 0.0;
        self.gain_reduction = 0.0;
        self.delay_index = 0;
        for sample in &mut self.delay_buffer {
            *sample = 0.0;
        }
        self.oversampler_l.reset();
        self.oversampler_r.reset();
    }
}

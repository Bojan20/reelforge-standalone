//! Broadcast-Quality Limiter
//!
//! Features:
//! - True peak limiting (intersample peaks)
//! - Look-ahead for transparent operation
//! - Soft-knee for musical response
//! - 4x oversampling for clean limiting

use wasm_bindgen::prelude::*;
use crate::{db_to_linear, linear_to_db, flush_denormal, soft_clip};
use crate::oversampling::Oversampler4x;

// ============ True Peak Limiter ============

#[wasm_bindgen]
pub struct TruePeakLimiter {
    // Parameters
    ceiling_db: f32,     // -12 to 0
    release_ms: f32,     // 10 to 1000

    // Coefficients
    ceiling_linear: f32,
    release_coeff: f32,

    // State
    gain: f32,           // Current gain multiplier
    peak_hold: f32,      // For metering

    // Look-ahead delay (stereo interleaved)
    delay_buffer: Vec<f32>,
    delay_index: usize,
    delay_length: usize,

    // Oversampler for true peak detection
    oversampler_l: Oversampler4x,
    oversampler_r: Oversampler4x,

    sample_rate: f32,
}

#[wasm_bindgen]
impl TruePeakLimiter {
    /// Create a new true peak limiter.
    /// Default: 5ms look-ahead for transparent operation.
    #[wasm_bindgen(constructor)]
    pub fn new(sample_rate: f32) -> TruePeakLimiter {
        let look_ahead_samples = ((5.0 / 1000.0) * sample_rate) as usize;

        TruePeakLimiter {
            ceiling_db: -0.3,
            release_ms: 100.0,

            ceiling_linear: db_to_linear(-0.3),
            release_coeff: (-1.0 / ((100.0 / 1000.0) * sample_rate)).exp(),

            gain: 1.0,
            peak_hold: 0.0,

            delay_buffer: vec![0.0; look_ahead_samples * 2],
            delay_index: 0,
            delay_length: look_ahead_samples,

            oversampler_l: Oversampler4x::new(),
            oversampler_r: Oversampler4x::new(),

            sample_rate,
        }
    }

    /// Set ceiling in dB (typically -0.1 to -1.0 for broadcast).
    pub fn set_ceiling(&mut self, db: f32) {
        self.ceiling_db = db.max(-12.0).min(0.0);
        self.ceiling_linear = db_to_linear(self.ceiling_db);
    }

    /// Set release time in milliseconds.
    pub fn set_release(&mut self, ms: f32) {
        self.release_ms = ms.max(10.0).min(1000.0);
        self.release_coeff = (-1.0 / ((ms / 1000.0) * self.sample_rate)).exp();
    }

    /// Set look-ahead time in milliseconds.
    pub fn set_look_ahead(&mut self, ms: f32) {
        let samples = ((ms.max(0.0).min(20.0) / 1000.0) * self.sample_rate) as usize;
        if samples != self.delay_length {
            self.delay_length = samples;
            if samples > 0 {
                self.delay_buffer = vec![0.0; samples * 2];
            } else {
                self.delay_buffer.clear();
            }
            self.delay_index = 0;
        }
    }

    /// Get current peak hold value (for metering).
    pub fn get_peak_hold(&self) -> f32 {
        self.peak_hold
    }

    /// Get current gain reduction in dB.
    pub fn get_gain_reduction_db(&self) -> f32 {
        if self.gain < 1.0 {
            -linear_to_db(self.gain)
        } else {
            0.0
        }
    }

    /// Process stereo buffer (interleaved L/R) in-place.
    /// Uses 4x oversampling for true peak detection.
    pub fn process_stereo(&mut self, buffer: &mut [f32]) {
        let len = buffer.len() / 2;

        for i in 0..len {
            let idx = i * 2;
            let in_l = buffer[idx];
            let in_r = buffer[idx + 1];

            // Upsample for true peak detection
            let up_l = self.oversampler_l.upsample(in_l);
            let up_r = self.oversampler_r.upsample(in_r);

            // Find true peak (max across all 4x samples)
            let mut true_peak: f32 = 0.0;
            for j in 0..4 {
                let peak = up_l[j].abs().max(up_r[j].abs());
                if peak > true_peak {
                    true_peak = peak;
                }
            }

            // Update peak hold for metering
            if true_peak > self.peak_hold {
                self.peak_hold = true_peak;
            } else {
                self.peak_hold *= 0.9999; // Slow decay
            }

            // Calculate target gain
            let target_gain = if true_peak > self.ceiling_linear {
                self.ceiling_linear / true_peak
            } else {
                1.0
            };

            // Apply gain smoothing (instant attack, smooth release)
            if target_gain < self.gain {
                // Instant attack for peaks
                self.gain = target_gain;
            } else {
                // Smooth release
                self.gain = self.release_coeff * self.gain + (1.0 - self.release_coeff) * target_gain;
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

            // Apply gain to delayed signal
            buffer[idx] = flush_denormal(delayed_l * self.gain);
            buffer[idx + 1] = flush_denormal(delayed_r * self.gain);
        }
    }

    /// Reset state.
    pub fn reset(&mut self) {
        self.gain = 1.0;
        self.peak_hold = 0.0;
        self.delay_index = 0;
        for sample in &mut self.delay_buffer {
            *sample = 0.0;
        }
        self.oversampler_l.reset();
        self.oversampler_r.reset();
    }
}

// ============ Soft Clipper ============

/// Musical soft clipper for saturation and protection.
#[wasm_bindgen]
pub struct SoftClipper {
    threshold: f32,      // Linear, 0.5 to 1.0
    drive: f32,          // Linear, 1.0 to 10.0
    output_gain: f32,    // Linear, compensates for drive
}

#[wasm_bindgen]
impl SoftClipper {
    #[wasm_bindgen(constructor)]
    pub fn new() -> SoftClipper {
        SoftClipper {
            threshold: 0.9,
            drive: 1.0,
            output_gain: 1.0,
        }
    }

    /// Set drive in dB (0 to 20).
    pub fn set_drive(&mut self, db: f32) {
        self.drive = db_to_linear(db.max(0.0).min(20.0));
        // Compensate output for drive
        self.output_gain = 1.0 / self.drive.sqrt();
    }

    /// Set threshold in dB (-6 to 0).
    pub fn set_threshold(&mut self, db: f32) {
        self.threshold = db_to_linear(db.max(-6.0).min(0.0));
    }

    /// Process stereo buffer (interleaved L/R) in-place.
    pub fn process_stereo(&mut self, buffer: &mut [f32]) {
        for sample in buffer.iter_mut() {
            // Apply drive
            let driven = *sample * self.drive;

            // Soft clip using tanh-like function
            let clipped = if driven.abs() > self.threshold {
                let sign = driven.signum();
                let excess = (driven.abs() - self.threshold) / (1.0 - self.threshold);
                sign * (self.threshold + (1.0 - self.threshold) * soft_clip(excess))
            } else {
                driven
            };

            // Apply output compensation
            *sample = flush_denormal(clipped * self.output_gain);
        }
    }
}

impl Default for SoftClipper {
    fn default() -> Self {
        Self::new()
    }
}

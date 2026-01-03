//! Biquad Filter - Professional EQ Implementation
//!
//! Direct Form II Transposed for numerical stability.
//! Coefficient caching for efficiency.
//! Stereo processing with independent state.

use wasm_bindgen::prelude::*;
use crate::{flush_denormal, TWO_PI};

// ============ Filter Types ============

#[wasm_bindgen]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FilterType {
    Lowpass = 0,
    Highpass = 1,
    Bandpass = 2,
    Notch = 3,
    Peak = 4,
    LowShelf = 5,
    HighShelf = 6,
    Allpass = 7,
}

// ============ Biquad State ============

/// Stereo biquad filter state.
/// Uses f64 internally for coefficient stability.
#[wasm_bindgen]
pub struct BiquadFilter {
    // Coefficients (f64 for precision)
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,

    // State for left channel
    z1_l: f64,
    z2_l: f64,

    // State for right channel
    z1_r: f64,
    z2_r: f64,

    // Cached params for dirty checking
    filter_type: FilterType,
    frequency: f32,
    gain: f32,
    q: f32,
    sample_rate: f32,
}

#[wasm_bindgen]
impl BiquadFilter {
    /// Create a new biquad filter.
    #[wasm_bindgen(constructor)]
    pub fn new(sample_rate: f32) -> BiquadFilter {
        BiquadFilter {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            z1_l: 0.0,
            z2_l: 0.0,
            z1_r: 0.0,
            z2_r: 0.0,
            filter_type: FilterType::Peak,
            frequency: 1000.0,
            gain: 0.0,
            q: 0.707,
            sample_rate,
        }
    }

    /// Update filter parameters.
    /// Only recalculates coefficients if parameters changed.
    pub fn set_params(&mut self, filter_type: FilterType, frequency: f32, gain: f32, q: f32) {
        // Check if anything changed
        if self.filter_type == filter_type
            && (self.frequency - frequency).abs() < 0.01
            && (self.gain - gain).abs() < 0.01
            && (self.q - q).abs() < 0.001
        {
            return;
        }

        self.filter_type = filter_type;
        self.frequency = frequency.max(20.0).min(20000.0);
        self.gain = gain.max(-24.0).min(24.0);
        self.q = q.max(0.1).min(18.0);

        self.calculate_coefficients();
    }

    /// Calculate biquad coefficients using RBJ Audio EQ Cookbook formulas.
    fn calculate_coefficients(&mut self) {
        let fs = self.sample_rate as f64;
        let f0 = self.frequency as f64;
        let gain_db = self.gain as f64;
        let q = self.q as f64;

        let a = 10.0_f64.powf(gain_db / 40.0);
        let w0 = TWO_PI as f64 * f0 / fs;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * q);

        let (b0, b1, b2, a0, a1, a2): (f64, f64, f64, f64, f64, f64);

        match self.filter_type {
            FilterType::Lowpass => {
                b0 = (1.0 - cos_w0) / 2.0;
                b1 = 1.0 - cos_w0;
                b2 = (1.0 - cos_w0) / 2.0;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            }
            FilterType::Highpass => {
                b0 = (1.0 + cos_w0) / 2.0;
                b1 = -(1.0 + cos_w0);
                b2 = (1.0 + cos_w0) / 2.0;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            }
            FilterType::Bandpass => {
                b0 = alpha;
                b1 = 0.0;
                b2 = -alpha;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            }
            FilterType::Notch => {
                b0 = 1.0;
                b1 = -2.0 * cos_w0;
                b2 = 1.0;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            }
            FilterType::Peak => {
                b0 = 1.0 + alpha * a;
                b1 = -2.0 * cos_w0;
                b2 = 1.0 - alpha * a;
                a0 = 1.0 + alpha / a;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha / a;
            }
            FilterType::LowShelf => {
                let sqrt_a = a.sqrt();
                let sqrt_a_2_alpha = 2.0 * sqrt_a * alpha;
                b0 = a * ((a + 1.0) - (a - 1.0) * cos_w0 + sqrt_a_2_alpha);
                b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w0);
                b2 = a * ((a + 1.0) - (a - 1.0) * cos_w0 - sqrt_a_2_alpha);
                a0 = (a + 1.0) + (a - 1.0) * cos_w0 + sqrt_a_2_alpha;
                a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cos_w0);
                a2 = (a + 1.0) + (a - 1.0) * cos_w0 - sqrt_a_2_alpha;
            }
            FilterType::HighShelf => {
                let sqrt_a = a.sqrt();
                let sqrt_a_2_alpha = 2.0 * sqrt_a * alpha;
                b0 = a * ((a + 1.0) + (a - 1.0) * cos_w0 + sqrt_a_2_alpha);
                b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0);
                b2 = a * ((a + 1.0) + (a - 1.0) * cos_w0 - sqrt_a_2_alpha);
                a0 = (a + 1.0) - (a - 1.0) * cos_w0 + sqrt_a_2_alpha;
                a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_w0);
                a2 = (a + 1.0) - (a - 1.0) * cos_w0 - sqrt_a_2_alpha;
            }
            FilterType::Allpass => {
                b0 = 1.0 - alpha;
                b1 = -2.0 * cos_w0;
                b2 = 1.0 + alpha;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            }
        }

        // Normalize coefficients
        self.b0 = b0 / a0;
        self.b1 = b1 / a0;
        self.b2 = b2 / a0;
        self.a1 = a1 / a0;
        self.a2 = a2 / a0;
    }

    /// Process stereo buffer (interleaved L/R) in-place.
    /// Uses Direct Form II Transposed for numerical stability.
    pub fn process_stereo(&mut self, buffer: &mut [f32]) {
        let len = buffer.len() / 2;

        for i in 0..len {
            let idx = i * 2;

            // Left channel
            let x_l = buffer[idx] as f64;
            let y_l = self.b0 * x_l + self.z1_l;
            self.z1_l = self.b1 * x_l - self.a1 * y_l + self.z2_l;
            self.z2_l = self.b2 * x_l - self.a2 * y_l;
            buffer[idx] = flush_denormal(y_l as f32);

            // Right channel
            let x_r = buffer[idx + 1] as f64;
            let y_r = self.b0 * x_r + self.z1_r;
            self.z1_r = self.b1 * x_r - self.a1 * y_r + self.z2_r;
            self.z2_r = self.b2 * x_r - self.a2 * y_r;
            buffer[idx + 1] = flush_denormal(y_r as f32);
        }

        // Denormal protection for state
        if self.z1_l.abs() < 1e-15 {
            self.z1_l = 0.0;
        }
        if self.z2_l.abs() < 1e-15 {
            self.z2_l = 0.0;
        }
        if self.z1_r.abs() < 1e-15 {
            self.z1_r = 0.0;
        }
        if self.z2_r.abs() < 1e-15 {
            self.z2_r = 0.0;
        }
    }

    /// Reset filter state (call after seek/discontinuity).
    pub fn reset(&mut self) {
        self.z1_l = 0.0;
        self.z2_l = 0.0;
        self.z1_r = 0.0;
        self.z2_r = 0.0;
    }

    /// Get frequency response magnitude at given frequency (in dB).
    pub fn get_magnitude_at(&self, frequency: f32) -> f32 {
        let w = TWO_PI as f64 * frequency as f64 / self.sample_rate as f64;
        let cos_w = w.cos();
        let cos_2w = (2.0 * w).cos();
        let sin_w = w.sin();
        let sin_2w = (2.0 * w).sin();

        // H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
        // At z = e^(j*w)
        let num_real = self.b0 + self.b1 * cos_w + self.b2 * cos_2w;
        let num_imag = -(self.b1 * sin_w + self.b2 * sin_2w);
        let den_real = 1.0 + self.a1 * cos_w + self.a2 * cos_2w;
        let den_imag = -(self.a1 * sin_w + self.a2 * sin_2w);

        // Complex division
        let den_mag2 = den_real * den_real + den_imag * den_imag;
        let h_real = (num_real * den_real + num_imag * den_imag) / den_mag2;
        let h_imag = (num_imag * den_real - num_real * den_imag) / den_mag2;

        let magnitude = (h_real * h_real + h_imag * h_imag).sqrt();
        (20.0 * magnitude.log10()) as f32
    }
}

// ============ Multi-band EQ ============

/// 8-band parametric EQ.
#[wasm_bindgen]
pub struct ParametricEQ {
    bands: [BiquadFilter; 8],
    band_active: [bool; 8],
    input_gain: f32,
    output_gain: f32,
    sample_rate: f32,
}

#[wasm_bindgen]
impl ParametricEQ {
    /// Create a new 8-band parametric EQ.
    #[wasm_bindgen(constructor)]
    pub fn new(sample_rate: f32) -> ParametricEQ {
        ParametricEQ {
            bands: [
                BiquadFilter::new(sample_rate),
                BiquadFilter::new(sample_rate),
                BiquadFilter::new(sample_rate),
                BiquadFilter::new(sample_rate),
                BiquadFilter::new(sample_rate),
                BiquadFilter::new(sample_rate),
                BiquadFilter::new(sample_rate),
                BiquadFilter::new(sample_rate),
            ],
            band_active: [false; 8],
            input_gain: 1.0,
            output_gain: 1.0,
            sample_rate,
        }
    }

    /// Set band parameters.
    pub fn set_band(&mut self, index: usize, freq: f32, gain: f32, q: f32, filter_type: FilterType) {
        if index < 8 {
            self.bands[index].set_params(filter_type, freq, gain, q);
        }
    }

    /// Set band active state.
    pub fn set_band_active(&mut self, index: usize, active: bool) {
        if index < 8 {
            self.band_active[index] = active;
        }
    }

    /// Set input gain (linear).
    pub fn set_input_gain(&mut self, gain: f32) {
        self.input_gain = gain.max(0.0).min(4.0);
    }

    /// Set output gain (linear).
    pub fn set_output_gain(&mut self, gain: f32) {
        self.output_gain = gain.max(0.0).min(4.0);
    }

    /// Process stereo buffer (interleaved L/R) in-place.
    pub fn process_block(&mut self, buffer: &mut [f32]) {
        // Apply input gain
        if (self.input_gain - 1.0).abs() > 1e-6 {
            for sample in buffer.iter_mut() {
                *sample *= self.input_gain;
            }
        }

        // Process through each active band
        for i in 0..8 {
            if self.band_active[i] {
                self.bands[i].process_stereo(buffer);
            }
        }

        // Apply output gain
        if (self.output_gain - 1.0).abs() > 1e-6 {
            for sample in buffer.iter_mut() {
                *sample = flush_denormal(*sample * self.output_gain);
            }
        }
    }

    /// Reset all band states.
    pub fn reset(&mut self) {
        for band in &mut self.bands {
            band.reset();
        }
    }

    /// Get combined frequency response at given frequency (in dB).
    pub fn get_response_at(&self, frequency: f32) -> f32 {
        let mut total = 0.0f32;
        for i in 0..8 {
            if self.band_active[i] {
                total += self.bands[i].get_magnitude_at(frequency);
            }
        }
        total
    }
}

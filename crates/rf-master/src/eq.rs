//! Spectral shaping and EQ for mastering
//!
//! Features:
//! - Linear phase mastering EQ
//! - Reference matching EQ
//! - Tilt EQ
//! - Spectral smoothing

use crate::error::{MasterError, MasterResult};
use crate::ReferenceProfile;
use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;
use std::sync::Arc;

/// Mastering EQ configuration
#[derive(Debug, Clone)]
pub struct MasterEqConfig {
    /// Sample rate
    pub sample_rate: u32,
    /// FFT size for linear phase
    pub fft_size: usize,
    /// Number of EQ bands
    pub num_bands: usize,
    /// Use linear phase
    pub linear_phase: bool,
    /// Smoothing factor for spectral matching
    pub smoothing: f32,
}

impl Default for MasterEqConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            fft_size: 4096,
            num_bands: 8,
            linear_phase: true,
            smoothing: 0.5,
        }
    }
}

/// Parametric EQ band
#[derive(Debug, Clone)]
pub struct EqBand {
    /// Center frequency
    pub freq: f32,
    /// Gain (dB)
    pub gain_db: f32,
    /// Q factor
    pub q: f32,
    /// Band type
    pub band_type: BandType,
    /// Enabled
    pub enabled: bool,
}

/// EQ band type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BandType {
    /// Bell/Peak filter
    Bell,
    /// Low shelf
    LowShelf,
    /// High shelf
    HighShelf,
    /// Low cut (highpass)
    LowCut,
    /// High cut (lowpass)
    HighCut,
    /// Notch
    Notch,
}

impl Default for EqBand {
    fn default() -> Self {
        Self {
            freq: 1000.0,
            gain_db: 0.0,
            q: 1.0,
            band_type: BandType::Bell,
            enabled: true,
        }
    }
}

/// Tilt EQ - simple spectral tilt control
pub struct TiltEq {
    /// Tilt amount (dB, positive = treble boost)
    tilt_db: f32,
    /// Center frequency
    center_freq: f32,
    /// Sample rate
    sample_rate: u32,
    /// Filter states
    lp_state_l: f64,
    lp_state_r: f64,
    hp_state_l: f64,
    hp_state_r: f64,
    /// Coefficients
    lp_coeff: f64,
    hp_coeff: f64,
    /// Gains
    low_gain: f32,
    high_gain: f32,
}

impl TiltEq {
    /// Create new tilt EQ
    pub fn new(sample_rate: u32) -> Self {
        let mut eq = Self {
            tilt_db: 0.0,
            center_freq: 1000.0,
            sample_rate,
            lp_state_l: 0.0,
            lp_state_r: 0.0,
            hp_state_l: 0.0,
            hp_state_r: 0.0,
            lp_coeff: 0.0,
            hp_coeff: 0.0,
            low_gain: 1.0,
            high_gain: 1.0,
        };
        eq.update_coefficients();
        eq
    }

    /// Set tilt amount
    pub fn set_tilt(&mut self, db: f32) {
        self.tilt_db = db;
        self.update_coefficients();
    }

    /// Set center frequency
    pub fn set_center(&mut self, freq: f32) {
        self.center_freq = freq;
        self.update_coefficients();
    }

    fn update_coefficients(&mut self) {
        let omega = 2.0 * std::f64::consts::PI * self.center_freq as f64 / self.sample_rate as f64;
        self.lp_coeff = omega / (omega + 1.0);
        self.hp_coeff = 1.0 / (omega + 1.0);

        // Half the tilt to each side
        self.low_gain = 10.0f32.powf(-self.tilt_db / 40.0);
        self.high_gain = 10.0f32.powf(self.tilt_db / 40.0);
    }

    /// Process stereo sample
    pub fn process(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Lowpass for low frequencies
        self.lp_state_l += self.lp_coeff * (left as f64 - self.lp_state_l);
        self.lp_state_r += self.lp_coeff * (right as f64 - self.lp_state_r);

        // Highpass for high frequencies
        self.hp_state_l += self.lp_coeff * (left as f64 - self.hp_state_l);
        self.hp_state_r += self.lp_coeff * (right as f64 - self.hp_state_r);

        let hp_l = left as f64 - self.hp_state_l;
        let hp_r = right as f64 - self.hp_state_r;

        // Combine with gains
        let out_l = self.lp_state_l * self.low_gain as f64 + hp_l * self.high_gain as f64;
        let out_r = self.lp_state_r * self.low_gain as f64 + hp_r * self.high_gain as f64;

        (out_l as f32, out_r as f32)
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.lp_state_l = 0.0;
        self.lp_state_r = 0.0;
        self.hp_state_l = 0.0;
        self.hp_state_r = 0.0;
    }
}

/// Linear phase mastering EQ
pub struct LinearPhaseEq {
    /// Configuration
    config: MasterEqConfig,
    /// FFT forward
    fft_forward: Arc<dyn RealToComplex<f32>>,
    /// FFT inverse
    fft_inverse: Arc<dyn realfft::ComplexToReal<f32>>,
    /// Analysis window
    window: Vec<f32>,
    /// Input buffer left
    input_buffer_l: Vec<f32>,
    /// Input buffer right
    input_buffer_r: Vec<f32>,
    /// Output buffer left
    output_buffer_l: Vec<f32>,
    /// Output buffer right
    output_buffer_r: Vec<f32>,
    /// Overlap buffer left
    overlap_l: Vec<f32>,
    /// Overlap buffer right
    overlap_r: Vec<f32>,
    /// EQ curve (magnitude per bin)
    eq_curve: Vec<f32>,
    /// Input position
    input_pos: usize,
    /// Bands
    bands: Vec<EqBand>,
}

impl LinearPhaseEq {
    /// Create new linear phase EQ
    pub fn new(config: MasterEqConfig) -> Self {
        let fft_size = config.fft_size;
        let bins = fft_size / 2 + 1;

        let mut planner = RealFftPlanner::<f32>::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Hann window
        let window: Vec<f32> = (0..fft_size)
            .map(|i| {
                let phase = 2.0 * std::f32::consts::PI * i as f32 / fft_size as f32;
                0.5 * (1.0 - phase.cos())
            })
            .collect();

        Self {
            config: config.clone(),
            fft_forward,
            fft_inverse,
            window,
            input_buffer_l: vec![0.0; fft_size],
            input_buffer_r: vec![0.0; fft_size],
            output_buffer_l: vec![0.0; fft_size],
            output_buffer_r: vec![0.0; fft_size],
            overlap_l: vec![0.0; fft_size],
            overlap_r: vec![0.0; fft_size],
            eq_curve: vec![1.0; bins],
            input_pos: 0,
            bands: Vec::new(),
        }
    }

    /// Add EQ band
    pub fn add_band(&mut self, band: EqBand) {
        self.bands.push(band);
        self.update_curve();
    }

    /// Set band parameters
    pub fn set_band(&mut self, index: usize, band: EqBand) {
        if index < self.bands.len() {
            self.bands[index] = band;
            self.update_curve();
        }
    }

    /// Update EQ curve from bands
    fn update_curve(&mut self) {
        let bins = self.eq_curve.len();
        let sample_rate = self.config.sample_rate as f32;
        let bin_width = sample_rate / (2.0 * bins as f32);

        // Reset to unity
        self.eq_curve.fill(1.0);

        for band in &self.bands {
            if !band.enabled {
                continue;
            }

            let gain = 10.0f32.powf(band.gain_db / 20.0);

            for (i, curve_val) in self.eq_curve.iter_mut().enumerate() {
                let freq = (i as f32 + 0.5) * bin_width;

                let band_gain = match band.band_type {
                    BandType::Bell => {
                        let ratio = freq / band.freq;
                        let w = ratio.ln() * band.q * 2.0;
                        let response = 1.0 / (1.0 + w * w);
                        1.0 + (gain - 1.0) * response
                    }
                    BandType::LowShelf => {
                        let ratio = freq / band.freq;
                        let transition = 1.0 / (1.0 + ratio.powf(2.0 * band.q));
                        1.0 + (gain - 1.0) * transition
                    }
                    BandType::HighShelf => {
                        let ratio = band.freq / freq;
                        let transition = 1.0 / (1.0 + ratio.powf(2.0 * band.q));
                        1.0 + (gain - 1.0) * transition
                    }
                    BandType::LowCut => {
                        let ratio = band.freq / freq;
                        1.0 / (1.0 + ratio.powf(2.0 * band.q))
                    }
                    BandType::HighCut => {
                        let ratio = freq / band.freq;
                        1.0 / (1.0 + ratio.powf(2.0 * band.q))
                    }
                    BandType::Notch => {
                        let ratio = freq / band.freq;
                        let w = (ratio - 1.0 / ratio) * band.q;
                        w * w / (1.0 + w * w)
                    }
                };

                *curve_val *= band_gain;
            }
        }
    }

    /// Process frame
    fn process_frame(&mut self) {
        let fft_size = self.config.fft_size;
        let bins = fft_size / 2 + 1;

        let mut fft_scratch_l = vec![0.0f32; fft_size];
        let mut fft_scratch_r = vec![0.0f32; fft_size];
        let mut spectrum_l = vec![Complex::new(0.0, 0.0); bins];
        let mut spectrum_r = vec![Complex::new(0.0, 0.0); bins];
        let mut ifft_scratch_l = vec![0.0f32; fft_size];
        let mut ifft_scratch_r = vec![0.0f32; fft_size];

        // Apply window
        for i in 0..fft_size {
            fft_scratch_l[i] = self.input_buffer_l[i] * self.window[i];
            fft_scratch_r[i] = self.input_buffer_r[i] * self.window[i];
        }

        // Forward FFT
        self.fft_forward.process(&mut fft_scratch_l, &mut spectrum_l).ok();
        self.fft_forward.process(&mut fft_scratch_r, &mut spectrum_r).ok();

        // Apply EQ curve
        for i in 0..bins {
            spectrum_l[i] = spectrum_l[i] * self.eq_curve[i];
            spectrum_r[i] = spectrum_r[i] * self.eq_curve[i];
        }

        // Inverse FFT
        self.fft_inverse.process(&mut spectrum_l, &mut ifft_scratch_l).ok();
        self.fft_inverse.process(&mut spectrum_r, &mut ifft_scratch_r).ok();

        // Normalize and apply synthesis window, overlap-add
        let norm = 1.0 / fft_size as f32;
        for i in 0..fft_size {
            self.overlap_l[i] += ifft_scratch_l[i] * norm * self.window[i];
            self.overlap_r[i] += ifft_scratch_r[i] * norm * self.window[i];
        }
    }

    /// Process buffer
    pub fn process(&mut self, input_l: &[f32], input_r: &[f32], output_l: &mut [f32], output_r: &mut [f32]) -> MasterResult<()> {
        if input_l.len() != output_l.len() {
            return Err(MasterError::BufferMismatch {
                expected: input_l.len(),
                got: output_l.len(),
            });
        }

        let fft_size = self.config.fft_size;
        let hop_size = fft_size / 4;

        for i in 0..input_l.len() {
            self.input_buffer_l[self.input_pos] = input_l[i];
            self.input_buffer_r[self.input_pos] = input_r[i];
            self.input_pos += 1;

            // Get output from overlap buffer
            output_l[i] = self.overlap_l[0];
            output_r[i] = self.overlap_r[0];

            // Shift overlap buffer
            self.overlap_l.copy_within(1.., 0);
            self.overlap_r.copy_within(1.., 0);
            self.overlap_l[fft_size - 1] = 0.0;
            self.overlap_r[fft_size - 1] = 0.0;

            // Process frame when ready
            if self.input_pos >= fft_size {
                self.process_frame();

                // Shift input buffer
                self.input_buffer_l.copy_within(hop_size.., 0);
                self.input_buffer_r.copy_within(hop_size.., 0);
                self.input_pos = fft_size - hop_size;
            }
        }

        Ok(())
    }

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        self.config.fft_size
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.input_buffer_l.fill(0.0);
        self.input_buffer_r.fill(0.0);
        self.overlap_l.fill(0.0);
        self.overlap_r.fill(0.0);
        self.input_pos = 0;
    }
}

/// Reference matching EQ
pub struct MatchingEq {
    /// Linear phase EQ
    eq: LinearPhaseEq,
    /// Reference spectrum
    reference_spectrum: Option<Vec<f32>>,
    /// Match amount (0-1)
    match_amount: f32,
    /// Smoothing
    smoothing: f32,
}

impl MatchingEq {
    /// Create new matching EQ
    pub fn new(sample_rate: u32) -> Self {
        let config = MasterEqConfig {
            sample_rate,
            ..Default::default()
        };

        Self {
            eq: LinearPhaseEq::new(config),
            reference_spectrum: None,
            match_amount: 1.0,
            smoothing: 0.5,
        }
    }

    /// Set reference profile
    pub fn set_reference(&mut self, profile: &ReferenceProfile) {
        self.reference_spectrum = Some(profile.spectrum.clone());
        self.update_match_curve();
    }

    /// Set match amount
    pub fn set_match_amount(&mut self, amount: f32) {
        self.match_amount = amount.clamp(0.0, 1.0);
        self.update_match_curve();
    }

    /// Update EQ curve to match reference
    fn update_match_curve(&mut self) {
        if let Some(ref reference) = self.reference_spectrum {
            let bins = self.eq.eq_curve.len();

            for i in 0..bins.min(reference.len()) {
                // Compute ratio (reference / current)
                // This would normally compare against analyzed input spectrum
                // For now, assume flat input and just use reference as target
                let ref_mag = reference[i].max(1e-10);
                let _target_gain = ref_mag; // Simplified

                // Apply smoothing
                let smoothed = if i > 0 && i < bins - 1 {
                    let prev = reference.get(i - 1).copied().unwrap_or(ref_mag);
                    let next = reference.get(i + 1).copied().unwrap_or(ref_mag);
                    self.smoothing * (prev + 2.0 * ref_mag + next) / 4.0
                        + (1.0 - self.smoothing) * ref_mag
                } else {
                    ref_mag
                };

                // Blend with flat
                self.eq.eq_curve[i] = 1.0 + self.match_amount * (smoothed - 1.0);
            }
        }
    }

    /// Process buffer
    pub fn process(&mut self, input_l: &[f32], input_r: &[f32], output_l: &mut [f32], output_r: &mut [f32]) -> MasterResult<()> {
        self.eq.process(input_l, input_r, output_l, output_r)
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.eq.reset();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tilt_eq() {
        let mut tilt = TiltEq::new(48000);
        tilt.set_tilt(3.0); // Treble boost

        let (l, r) = tilt.process(0.5, 0.5);
        assert!(l.is_finite());
        assert!(r.is_finite());
    }

    #[test]
    fn test_linear_phase_eq() {
        let config = MasterEqConfig::default();
        let mut eq = LinearPhaseEq::new(config);

        eq.add_band(EqBand {
            freq: 100.0,
            gain_db: 3.0,
            q: 1.0,
            band_type: BandType::LowShelf,
            enabled: true,
        });

        let input_l = vec![0.5f32; 4096];
        let input_r = vec![0.5f32; 4096];
        let mut output_l = vec![0.0f32; 4096];
        let mut output_r = vec![0.0f32; 4096];

        eq.process(&input_l, &input_r, &mut output_l, &mut output_r).unwrap();

        assert!(output_l.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn test_eq_band_types() {
        let config = MasterEqConfig::default();
        let mut eq = LinearPhaseEq::new(config);

        // Add various band types
        eq.add_band(EqBand {
            freq: 100.0,
            gain_db: 3.0,
            q: 1.0,
            band_type: BandType::LowShelf,
            enabled: true,
        });

        eq.add_band(EqBand {
            freq: 1000.0,
            gain_db: -2.0,
            q: 2.0,
            band_type: BandType::Bell,
            enabled: true,
        });

        eq.add_band(EqBand {
            freq: 10000.0,
            gain_db: 2.0,
            q: 0.7,
            band_type: BandType::HighShelf,
            enabled: true,
        });

        // Curve should be valid
        assert!(eq.eq_curve.iter().all(|v| v.is_finite() && *v > 0.0));
    }

    #[test]
    fn test_matching_eq() {
        let mut matching = MatchingEq::new(48000);
        matching.set_match_amount(0.5);

        let input_l = vec![0.5f32; 4096];
        let input_r = vec![0.5f32; 4096];
        let mut output_l = vec![0.0f32; 4096];
        let mut output_r = vec![0.0f32; 4096];

        matching.process(&input_l, &input_r, &mut output_l, &mut output_r).unwrap();

        assert!(output_l.iter().all(|s| s.is_finite()));
    }
}

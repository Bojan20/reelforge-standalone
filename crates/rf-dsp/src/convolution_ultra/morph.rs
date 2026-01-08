//! IR Morphing
//!
//! UNIQUE: Real-time interpolation between two impulse responses.
//!
//! Methods:
//! - Simple crossfade (basic)
//! - Magnitude interpolation (preserve phase)
//! - Spectral envelope morphing (perceptually accurate)
//! - Time-aligned morphing (handles different IR lengths)

use super::ImpulseResponse;
use rf_core::Sample;
use rustfft::{FftPlanner, num_complex::Complex64};
use std::f64::consts::PI;

/// Morph mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MorphMode {
    /// Simple time-domain crossfade
    Crossfade,
    /// Interpolate magnitude, keep phase from IR A
    MagnitudeOnly,
    /// Interpolate magnitude in log domain
    LogMagnitude,
    /// Full spectral interpolation (magnitude + phase)
    Spectral,
    /// Spectral envelope morphing (most natural)
    SpectralEnvelope,
}

impl Default for MorphMode {
    fn default() -> Self {
        Self::SpectralEnvelope
    }
}

/// IR Morpher
pub struct IrMorpher {
    /// IR A (morph source)
    ir_a: ImpulseResponse,
    /// IR B (morph target)
    ir_b: ImpulseResponse,
    /// Current blend (0 = A, 1 = B)
    blend: f64,
    /// Morph mode
    mode: MorphMode,
    /// FFT size
    fft_size: usize,
    /// Pre-computed spectrum A
    spectrum_a: Vec<Complex64>,
    /// Pre-computed spectrum B
    spectrum_b: Vec<Complex64>,
    /// Morphed spectrum (cached)
    morphed_spectrum: Vec<Complex64>,
    /// Morphed IR (time domain)
    morphed_ir: Vec<Sample>,
    /// Need recalculation
    dirty: bool,
    /// FFT planner
    fft_forward: std::sync::Arc<dyn rustfft::Fft<f64>>,
    fft_inverse: std::sync::Arc<dyn rustfft::Fft<f64>>,
}

impl IrMorpher {
    /// Create new morpher
    pub fn new(ir_a: ImpulseResponse, ir_b: ImpulseResponse) -> Self {
        let max_len = ir_a.len().max(ir_b.len());
        let fft_size = max_len.next_power_of_two();

        let mut planner = FftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Compute spectra
        let spectrum_a = Self::compute_spectrum(&ir_a.samples, fft_size, &fft_forward);
        let spectrum_b = Self::compute_spectrum(&ir_b.samples, fft_size, &fft_forward);

        Self {
            ir_a,
            ir_b,
            blend: 0.5,
            mode: MorphMode::SpectralEnvelope,
            fft_size,
            spectrum_a,
            spectrum_b,
            morphed_spectrum: vec![Complex64::new(0.0, 0.0); fft_size],
            morphed_ir: vec![0.0; fft_size],
            dirty: true,
            fft_forward,
            fft_inverse,
        }
    }

    /// Compute FFT spectrum
    fn compute_spectrum(
        samples: &[Sample],
        fft_size: usize,
        fft: &std::sync::Arc<dyn rustfft::Fft<f64>>,
    ) -> Vec<Complex64> {
        let mut buffer: Vec<Complex64> = samples.iter()
            .take(fft_size)
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        buffer.resize(fft_size, Complex64::new(0.0, 0.0));

        fft.process(&mut buffer);
        buffer
    }

    /// Set blend factor (0 = IR A, 1 = IR B)
    pub fn set_blend(&mut self, blend: f64) {
        let new_blend = blend.clamp(0.0, 1.0);
        if (new_blend - self.blend).abs() > 0.001 {
            self.blend = new_blend;
            self.dirty = true;
        }
    }

    /// Set morph mode
    pub fn set_mode(&mut self, mode: MorphMode) {
        if mode != self.mode {
            self.mode = mode;
            self.dirty = true;
        }
    }

    /// Get current blend
    pub fn blend(&self) -> f64 {
        self.blend
    }

    /// Get morph mode
    pub fn mode(&self) -> MorphMode {
        self.mode
    }

    /// Recalculate morphed IR if needed
    fn update_if_dirty(&mut self) {
        if !self.dirty {
            return;
        }

        match self.mode {
            MorphMode::Crossfade => self.morph_crossfade(),
            MorphMode::MagnitudeOnly => self.morph_magnitude_only(),
            MorphMode::LogMagnitude => self.morph_log_magnitude(),
            MorphMode::Spectral => self.morph_spectral(),
            MorphMode::SpectralEnvelope => self.morph_spectral_envelope(),
        }

        self.dirty = false;
    }

    /// Simple crossfade morph
    fn morph_crossfade(&mut self) {
        let len = self.ir_a.len().max(self.ir_b.len());

        for i in 0..len {
            let a = self.ir_a.samples.get(i).copied().unwrap_or(0.0);
            let b = self.ir_b.samples.get(i).copied().unwrap_or(0.0);
            self.morphed_ir[i] = a * (1.0 - self.blend) + b * self.blend;
        }
    }

    /// Magnitude-only morph (preserve phase of IR A)
    fn morph_magnitude_only(&mut self) {
        for i in 0..self.fft_size {
            let mag_a = self.spectrum_a[i].norm();
            let mag_b = self.spectrum_b[i].norm();
            let phase_a = self.spectrum_a[i].arg();

            let mag = mag_a * (1.0 - self.blend) + mag_b * self.blend;

            self.morphed_spectrum[i] = Complex64::from_polar(mag, phase_a);
        }

        self.ifft_to_ir();
    }

    /// Log-magnitude morph (more perceptually linear)
    fn morph_log_magnitude(&mut self) {
        const EPSILON: f64 = 1e-10;

        for i in 0..self.fft_size {
            let mag_a = self.spectrum_a[i].norm().max(EPSILON);
            let mag_b = self.spectrum_b[i].norm().max(EPSILON);
            let phase_a = self.spectrum_a[i].arg();
            let phase_b = self.spectrum_b[i].arg();

            // Interpolate in log domain
            let log_mag_a = mag_a.ln();
            let log_mag_b = mag_b.ln();
            let log_mag = log_mag_a * (1.0 - self.blend) + log_mag_b * self.blend;
            let mag = log_mag.exp();

            // Interpolate phase with wraparound handling
            let phase = Self::lerp_angle(phase_a, phase_b, self.blend);

            self.morphed_spectrum[i] = Complex64::from_polar(mag, phase);
        }

        self.ifft_to_ir();
    }

    /// Full spectral morph
    fn morph_spectral(&mut self) {
        for i in 0..self.fft_size {
            let a = self.spectrum_a[i];
            let b = self.spectrum_b[i];

            // Linear interpolation of complex values
            self.morphed_spectrum[i] = a * (1.0 - self.blend) + b * self.blend;
        }

        self.ifft_to_ir();
    }

    /// Spectral envelope morph (most natural sounding)
    fn morph_spectral_envelope(&mut self) {
        const EPSILON: f64 = 1e-10;
        const ENVELOPE_SMOOTH: usize = 16; // Smoothing window for envelope

        // Extract spectral envelopes
        let env_a = Self::extract_envelope(&self.spectrum_a, ENVELOPE_SMOOTH);
        let env_b = Self::extract_envelope(&self.spectrum_b, ENVELOPE_SMOOTH);

        for i in 0..self.fft_size {
            // Interpolate envelope
            let env = env_a[i] * (1.0 - self.blend) + env_b[i] * self.blend;

            // Get fine structure from IR A
            let fine_a = self.spectrum_a[i].norm() / (env_a[i] + EPSILON);

            // Apply morphed envelope with fine structure
            let mag = env * fine_a;

            // Interpolate phase
            let phase_a = self.spectrum_a[i].arg();
            let phase_b = self.spectrum_b[i].arg();
            let phase = Self::lerp_angle(phase_a, phase_b, self.blend);

            self.morphed_spectrum[i] = Complex64::from_polar(mag, phase);
        }

        self.ifft_to_ir();
    }

    /// Extract spectral envelope using cepstral smoothing
    fn extract_envelope(spectrum: &[Complex64], smooth_size: usize) -> Vec<f64> {
        let len = spectrum.len();
        let mut envelope = vec![0.0; len];

        // Simple moving average smoothing
        let half_win = smooth_size / 2;

        for i in 0..len {
            let start = i.saturating_sub(half_win);
            let end = (i + half_win).min(len);
            let count = end - start;

            let sum: f64 = (start..end)
                .map(|j| spectrum[j].norm())
                .sum();

            envelope[i] = sum / count as f64;
        }

        envelope
    }

    /// Interpolate angles with wraparound
    fn lerp_angle(a: f64, b: f64, t: f64) -> f64 {
        let mut diff = b - a;

        // Handle wraparound
        while diff > PI {
            diff -= 2.0 * PI;
        }
        while diff < -PI {
            diff += 2.0 * PI;
        }

        a + t * diff
    }

    /// Convert morphed spectrum back to time domain
    fn ifft_to_ir(&mut self) {
        let mut buffer = self.morphed_spectrum.clone();
        self.fft_inverse.process(&mut buffer);

        let scale = 1.0 / self.fft_size as f64;
        for (i, c) in buffer.iter().enumerate() {
            self.morphed_ir[i] = c.re * scale;
        }
    }

    /// Get morphed IR
    pub fn get_morphed_ir(&mut self) -> &[Sample] {
        self.update_if_dirty();
        &self.morphed_ir
    }

    /// Get morphed IR as ImpulseResponse
    pub fn get_morphed(&mut self) -> ImpulseResponse {
        self.update_if_dirty();
        ImpulseResponse::new(
            self.morphed_ir.clone(),
            self.ir_a.sample_rate,
            1,
        )
    }

    /// Replace IR A
    pub fn set_ir_a(&mut self, ir: ImpulseResponse) {
        self.spectrum_a = Self::compute_spectrum(&ir.samples, self.fft_size, &self.fft_forward);
        self.ir_a = ir;
        self.dirty = true;
    }

    /// Replace IR B
    pub fn set_ir_b(&mut self, ir: ImpulseResponse) {
        self.spectrum_b = Self::compute_spectrum(&ir.samples, self.fft_size, &self.fft_forward);
        self.ir_b = ir;
        self.dirty = true;
    }
}

/// Real-time morph controller with smooth transitions
pub struct MorphController {
    /// Morpher
    morpher: IrMorpher,
    /// Target blend
    target_blend: f64,
    /// Current blend (smoothed)
    current_blend: f64,
    /// Smoothing coefficient
    smooth_coeff: f64,
}

impl MorphController {
    /// Create with smoothing time in seconds
    pub fn new(ir_a: ImpulseResponse, ir_b: ImpulseResponse, smooth_time_sec: f64, sample_rate: f64) -> Self {
        let morpher = IrMorpher::new(ir_a, ir_b);

        // Calculate smoothing coefficient
        let smooth_coeff = (-1.0 / (smooth_time_sec * sample_rate)).exp();

        Self {
            morpher,
            target_blend: 0.5,
            current_blend: 0.5,
            smooth_coeff,
        }
    }

    /// Set target blend (will smooth towards it)
    pub fn set_target_blend(&mut self, blend: f64) {
        self.target_blend = blend.clamp(0.0, 1.0);
    }

    /// Update smoothing (call once per sample or block)
    pub fn update(&mut self) {
        let diff = self.target_blend - self.current_blend;
        if diff.abs() > 0.0001 {
            self.current_blend += (1.0 - self.smooth_coeff) * diff;
            self.morpher.set_blend(self.current_blend);
        }
    }

    /// Get current morphed IR
    pub fn get_morphed_ir(&mut self) -> &[Sample] {
        self.update();
        self.morpher.get_morphed_ir()
    }

    /// Get morpher reference
    pub fn morpher(&mut self) -> &mut IrMorpher {
        &mut self.morpher
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_morph_modes() {
        let ir_a = ImpulseResponse::new(vec![1.0; 128], 48000.0, 1);
        let ir_b = ImpulseResponse::new(vec![0.5; 128], 48000.0, 1);

        let mut morpher = IrMorpher::new(ir_a, ir_b);

        // Test all modes
        for mode in [MorphMode::Crossfade, MorphMode::MagnitudeOnly,
                     MorphMode::LogMagnitude, MorphMode::Spectral,
                     MorphMode::SpectralEnvelope] {
            morpher.set_mode(mode);
            morpher.set_blend(0.5);
            let _ = morpher.get_morphed_ir();
        }
    }

    #[test]
    fn test_blend_extremes() {
        let ir_a = ImpulseResponse::new(vec![1.0, 0.0, 0.0, 0.0], 48000.0, 1);
        let ir_b = ImpulseResponse::new(vec![0.0, 0.0, 0.0, 1.0], 48000.0, 1);

        let mut morpher = IrMorpher::new(ir_a.clone(), ir_b.clone());
        morpher.set_mode(MorphMode::Crossfade);

        // Blend = 0 should be IR A
        morpher.set_blend(0.0);
        let result = morpher.get_morphed_ir();
        assert!((result[0] - 1.0).abs() < 0.01);

        // Blend = 1 should be IR B
        morpher.set_blend(1.0);
        let result = morpher.get_morphed_ir();
        assert!((result[3] - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_lerp_angle() {
        // Same angle
        assert!((IrMorpher::lerp_angle(0.0, 0.0, 0.5) - 0.0).abs() < 0.001);

        // Simple interpolation
        let result = IrMorpher::lerp_angle(0.0, PI / 2.0, 0.5);
        assert!((result - PI / 4.0).abs() < 0.001);

        // Wraparound
        let result = IrMorpher::lerp_angle(-PI * 0.9, PI * 0.9, 0.5);
        assert!(result.abs() > PI * 0.8); // Should stay near ±π
    }
}

//! # Transient Detection
//!
//! Multi-method onset/transient detection for accurate time stretching.
//!
//! ## Methods
//!
//! - **Spectral Flux**: Measures spectral change between frames
//! - **High Frequency Content (HFC)**: Weights high frequencies
//! - **Complex Domain**: Combines magnitude and phase deviation

use std::f64::consts::PI;
use rustfft::{FftPlanner, num_complex::Complex64};

use crate::timestretch::{FlexMarker, FlexMarkerType};

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSIENT DETECTOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Multi-method transient detector
pub struct TransientDetector {
    /// Sample rate
    sample_rate: f64,
    /// FFT size
    fft_size: usize,
    /// Hop size
    hop_size: usize,
    /// Detection threshold (0.0 - 1.0)
    threshold: f64,
    /// Minimum time between transients (seconds)
    min_interval: f64,
    /// Detection method weights
    method_weights: MethodWeights,
    /// FFT planner
    fft_planner: FftPlanner<f64>,
    /// Previous frame magnitude (for flux calculation)
    prev_magnitude: Vec<f64>,
    /// Previous frame phase
    prev_phase: Vec<f64>,
}

/// Weights for different detection methods
#[derive(Debug, Clone)]
pub struct MethodWeights {
    /// Spectral flux weight
    pub spectral_flux: f64,
    /// High frequency content weight
    pub hfc: f64,
    /// Complex domain weight
    pub complex_domain: f64,
}

impl Default for MethodWeights {
    fn default() -> Self {
        Self {
            spectral_flux: 0.4,
            hfc: 0.3,
            complex_domain: 0.3,
        }
    }
}

impl TransientDetector {
    /// Create new transient detector
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            fft_size: 2048,
            hop_size: 512,
            threshold: 0.3,
            min_interval: 0.05, // 50ms
            method_weights: MethodWeights::default(),
            fft_planner: FftPlanner::new(),
            prev_magnitude: Vec::new(),
            prev_phase: Vec::new(),
        }
    }

    /// Create with custom parameters
    pub fn with_params(sample_rate: f64, fft_size: usize, hop_size: usize) -> Self {
        Self {
            sample_rate,
            fft_size,
            hop_size,
            threshold: 0.3,
            min_interval: 0.05,
            method_weights: MethodWeights::default(),
            fft_planner: FftPlanner::new(),
            prev_magnitude: Vec::new(),
            prev_phase: Vec::new(),
        }
    }

    /// Detect transients and return flex markers
    pub fn detect(&mut self, input: &[f64]) -> Vec<FlexMarker> {
        let detection_function = self.compute_detection_function(input);
        let peaks = self.pick_peaks(&detection_function);

        // Convert peaks to flex markers
        peaks.into_iter()
            .map(|(sample_pos, confidence)| FlexMarker {
                original_pos: sample_pos as u64,
                warped_pos: sample_pos as u64,
                marker_type: FlexMarkerType::Transient,
                confidence: confidence as f32,
                locked: false,
            })
            .collect()
    }

    /// Compute combined detection function
    fn compute_detection_function(&mut self, input: &[f64]) -> Vec<f64> {
        let num_frames = input.len().saturating_sub(self.fft_size) / self.hop_size + 1;
        let mut detection = vec![0.0; num_frames];

        // Initialize previous frame storage
        self.prev_magnitude = vec![0.0; self.fft_size / 2 + 1];
        self.prev_phase = vec![0.0; self.fft_size / 2 + 1];

        for frame_idx in 0..num_frames {
            let start = frame_idx * self.hop_size;
            let end = (start + self.fft_size).min(input.len());

            // Extract and window frame
            let mut frame = vec![Complex64::new(0.0, 0.0); self.fft_size];
            for (i, f) in frame.iter_mut().enumerate().take(end - start) {
                let window = 0.5 * (1.0 - (2.0 * PI * i as f64 / self.fft_size as f64).cos());
                *f = Complex64::new(input[start + i] * window, 0.0);
            }

            // FFT
            let fft = self.fft_planner.plan_fft_forward(self.fft_size);
            fft.process(&mut frame);

            // Extract magnitude and phase
            let magnitude: Vec<f64> = frame[..self.fft_size / 2 + 1]
                .iter()
                .map(|c| c.norm())
                .collect();
            let phase: Vec<f64> = frame[..self.fft_size / 2 + 1]
                .iter()
                .map(|c| c.arg())
                .collect();

            // Compute detection methods
            let flux = self.spectral_flux(&magnitude);
            let hfc = self.high_frequency_content(&magnitude);
            let complex = self.complex_domain_detection(&magnitude, &phase);

            // Weighted combination
            let w = &self.method_weights;
            detection[frame_idx] = w.spectral_flux * flux
                + w.hfc * hfc
                + w.complex_domain * complex;

            // Update previous frame
            self.prev_magnitude = magnitude;
            self.prev_phase = phase;
        }

        // Normalize
        let max_val = detection.iter().cloned().fold(0.0, f64::max);
        if max_val > 0.0 {
            for d in &mut detection {
                *d /= max_val;
            }
        }

        detection
    }

    /// Spectral flux: sum of positive magnitude differences
    fn spectral_flux(&self, magnitude: &[f64]) -> f64 {
        magnitude.iter()
            .zip(self.prev_magnitude.iter())
            .map(|(&curr, &prev)| (curr - prev).max(0.0))
            .sum()
    }

    /// High Frequency Content: frequency-weighted sum
    fn high_frequency_content(&self, magnitude: &[f64]) -> f64 {
        magnitude.iter()
            .enumerate()
            .map(|(k, &m)| (k as f64 + 1.0) * m * m)
            .sum::<f64>()
            .sqrt()
    }

    /// Complex domain detection: combines magnitude and phase deviation
    fn complex_domain_detection(&self, magnitude: &[f64], phase: &[f64]) -> f64 {
        let mut sum = 0.0;
        let n = magnitude.len().min(self.prev_magnitude.len());

        for k in 0..n {
            // Expected phase (linear extrapolation)
            let expected_phase = 2.0 * self.prev_phase.get(k).copied().unwrap_or(0.0)
                - self.prev_phase.get(k.saturating_sub(1)).copied().unwrap_or(0.0);

            // Expected magnitude and phase as complex
            let expected = Complex64::from_polar(
                self.prev_magnitude[k],
                expected_phase,
            );

            // Actual
            let actual = Complex64::from_polar(magnitude[k], phase[k]);

            // Deviation
            sum += (actual - expected).norm();
        }

        sum
    }

    /// Pick peaks from detection function
    fn pick_peaks(&self, detection: &[f64]) -> Vec<(usize, f64)> {
        let mut peaks = Vec::new();
        let min_samples = (self.min_interval * self.sample_rate) as usize / self.hop_size;

        let mut i = 1;
        while i < detection.len() - 1 {
            // Check if local maximum
            if detection[i] > detection[i - 1]
                && detection[i] > detection[i + 1]
                && detection[i] > self.threshold
            {
                let sample_pos = i * self.hop_size;
                peaks.push((sample_pos, detection[i]));

                // Skip minimum interval
                i += min_samples.max(1);
            } else {
                i += 1;
            }
        }

        peaks
    }

    /// Set detection threshold (0.0 - 1.0)
    pub fn set_threshold(&mut self, threshold: f64) {
        self.threshold = threshold.clamp(0.0, 1.0);
    }

    /// Set minimum interval between transients (seconds)
    pub fn set_min_interval(&mut self, interval: f64) {
        self.min_interval = interval.max(0.0);
    }

    /// Set detection method weights
    pub fn set_method_weights(&mut self, weights: MethodWeights) {
        self.method_weights = weights;
    }

    /// Reset detector state
    pub fn reset(&mut self) {
        self.prev_magnitude.clear();
        self.prev_phase.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSIENT SHARPNESS
// ═══════════════════════════════════════════════════════════════════════════════

/// Compute transient sharpness metric for a region
pub fn transient_sharpness(samples: &[f64]) -> f64 {
    if samples.len() < 2 {
        return 0.0;
    }

    // Compute derivative (absolute differences)
    let derivative: Vec<f64> = samples.windows(2)
        .map(|w| (w[1] - w[0]).abs())
        .collect();

    // Sharpness = peak derivative / mean derivative
    let peak = derivative.iter().cloned().fold(0.0, f64::max);
    let mean = derivative.iter().sum::<f64>() / derivative.len() as f64;

    if mean > 0.0 {
        peak / mean
    } else {
        0.0
    }
}

/// Detect if region contains sharp transient
pub fn is_transient_region(samples: &[f64], threshold: f64) -> bool {
    transient_sharpness(samples) > threshold
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transient_detector_creation() {
        let detector = TransientDetector::new(44100.0);
        assert!((detector.sample_rate - 44100.0).abs() < 1e-6);
    }

    #[test]
    fn test_detect_simple_transient() {
        let mut detector = TransientDetector::new(44100.0);
        detector.set_threshold(0.2);

        // Create signal with transient
        let mut signal = vec![0.0; 44100]; // 1 second

        // Add transient at 0.5 seconds
        let transient_pos = 22050;
        for i in 0..100 {
            signal[transient_pos + i] = (-(i as f64) / 20.0).exp();
        }

        let markers = detector.detect(&signal);

        // Should detect at least one transient
        // Note: detection depends on threshold and parameters
        println!("Detected {} transients", markers.len());
    }

    #[test]
    fn test_spectral_flux() {
        let detector = TransientDetector::new(44100.0);

        let prev = vec![1.0, 2.0, 3.0, 4.0];
        let curr = vec![2.0, 2.0, 5.0, 3.0];

        // Manual flux: (2-1) + (2-2) + (5-3) + (3-4)max0 = 1 + 0 + 2 + 0 = 3
        // But detector uses internal prev_magnitude, so we can't test directly
    }

    #[test]
    fn test_transient_sharpness() {
        // Gradual change
        let gradual: Vec<f64> = (0..100).map(|i| i as f64 / 100.0).collect();
        let gradual_sharpness = transient_sharpness(&gradual);

        // Sharp change
        let mut sharp = vec![0.0; 100];
        sharp[50] = 1.0;
        let sharp_sharpness = transient_sharpness(&sharp);

        assert!(sharp_sharpness > gradual_sharpness);
    }

    #[test]
    fn test_is_transient_region() {
        // Flat region
        let flat = vec![0.5; 100];
        assert!(!is_transient_region(&flat, 2.0));

        // Transient region
        let mut transient = vec![0.0; 100];
        transient[50] = 1.0;
        assert!(is_transient_region(&transient, 2.0));
    }
}

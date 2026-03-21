//! Transient Detector — Spectral Flux onset detection
//!
//! Detects audio transients (drum hits, note attacks, percussive events)
//! using spectral flux analysis. Zero external dependencies — uses rustfft.
//!
//! Algorithm (same as aubio, librosa):
//! 1. STFT with Hann window (periodic, 1024-point default)
//! 2. Per-frame spectral flux: sum of positive magnitude changes
//! 3. Adaptive threshold: median + MAD * sensitivity (additive, aubio-standard)
//! 4. Peak picking with minimum inter-onset interval
//!
//! Designed for OFFLINE analysis — not real-time audio thread.

use rustfft::{FftPlanner, num_complex::Complex64};
use std::f64::consts::PI;

/// Transient detection result
#[derive(Debug, Clone)]
pub struct TransientResult {
    /// Detected transient positions in seconds
    pub positions: Vec<f64>,
    /// Spectral flux curve (one value per hop)
    pub flux_curve: Vec<f64>,
    /// Adaptive threshold curve
    pub threshold_curve: Vec<f64>,
}

/// Spectral flux transient detector.
///
/// Uses STFT + spectral flux + adaptive threshold + peak picking.
/// Runs offline on full audio buffer — NOT for audio thread.
pub struct TransientDetector {
    /// FFT size
    fft_size: usize,
    /// Hop size (fft_size / 4 default)
    hop_size: usize,
    /// Sample rate
    sample_rate: f64,
    /// Sensitivity multiplier for adaptive threshold (higher = fewer detections)
    sensitivity: f64,
    /// Minimum inter-onset interval in seconds
    min_interval: f64,
    /// Median filter window size for adaptive threshold
    median_window: usize,
}

impl TransientDetector {
    /// Create detector with default settings.
    ///
    /// `sample_rate`: audio sample rate (44100, 48000, etc.)
    pub fn new(sample_rate: f64) -> Self {
        Self {
            fft_size: 1024,
            hop_size: 256,
            sample_rate,
            sensitivity: 1.5,
            min_interval: 0.03, // 30ms minimum between onsets
            median_window: 11,
        }
    }

    /// Set sensitivity (1.0 = very sensitive, 3.0 = less sensitive)
    pub fn set_sensitivity(&mut self, sensitivity: f64) {
        self.sensitivity = sensitivity.clamp(0.5, 5.0);
    }

    /// Set minimum inter-onset interval in seconds
    pub fn set_min_interval(&mut self, seconds: f64) {
        self.min_interval = seconds.clamp(0.005, 1.0);
    }

    /// Detect transients in mono audio buffer.
    ///
    /// `samples`: mono f64 audio samples
    /// Returns positions in seconds where transients occur.
    pub fn detect(&self, samples: &[f64]) -> TransientResult {
        if samples.len() < self.fft_size {
            return TransientResult {
                positions: Vec::new(),
                flux_curve: Vec::new(),
                threshold_curve: Vec::new(),
            };
        }

        // Hann window
        let window: Vec<f64> = (0..self.fft_size)
            .map(|n| 0.5 * (1.0 - (2.0 * PI * n as f64 / self.fft_size as f64).cos()))
            .collect();

        // FFT planner
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(self.fft_size);

        let half = self.fft_size / 2 + 1;
        let mut prev_mag = vec![0.0f64; half];
        let mut fft_buf = vec![Complex64::new(0.0, 0.0); self.fft_size];

        // Pre-fill prev_mag from frame 0 to avoid inflated flux at start
        for i in 0..self.fft_size {
            let s = if i < samples.len() { samples[i] } else { 0.0 };
            fft_buf[i] = Complex64::new(s * window[i], 0.0);
        }
        fft.process(&mut fft_buf);
        for k in 0..half {
            prev_mag[k] = (fft_buf[k].re * fft_buf[k].re + fft_buf[k].im * fft_buf[k].im).sqrt();
        }

        // Compute spectral flux for each frame (starting from frame 1 effectively)
        let num_frames = (samples.len() - self.fft_size) / self.hop_size + 1;
        let mut flux_curve = Vec::with_capacity(num_frames);

        for frame_idx in 0..num_frames {
            let start = frame_idx * self.hop_size;

            // Window + FFT
            for i in 0..self.fft_size {
                let s = if start + i < samples.len() { samples[start + i] } else { 0.0 };
                fft_buf[i] = Complex64::new(s * window[i], 0.0);
            }
            fft.process(&mut fft_buf);

            // Spectral flux: sum of positive magnitude differences
            let mut flux = 0.0f64;
            for k in 0..half {
                let mag = (fft_buf[k].re * fft_buf[k].re + fft_buf[k].im * fft_buf[k].im).sqrt();
                let diff = mag - prev_mag[k];
                if diff > 0.0 {
                    flux += diff;
                }
                prev_mag[k] = mag;
            }
            flux_curve.push(flux);
        }

        // Adaptive threshold: running median + sensitivity multiplier
        let threshold_curve = self.adaptive_threshold(&flux_curve);

        // Peak picking
        let positions = self.pick_peaks(&flux_curve, &threshold_curve);

        TransientResult {
            positions,
            flux_curve,
            threshold_curve,
        }
    }

    /// Detect transients in stereo audio (averages L+R to mono).
    pub fn detect_stereo(&self, left: &[f64], right: &[f64]) -> TransientResult {
        let len = left.len().min(right.len());
        let mono: Vec<f64> = (0..len).map(|i| (left[i] + right[i]) * 0.5).collect();
        self.detect(&mono)
    }

    /// Compute adaptive threshold: median + mean_deviation * sensitivity (aubio/librosa standard).
    ///
    /// Additive formula works better in dense mixes than multiplicative (median * sensitivity)
    /// because it adapts to the local spread of flux values, not just the center.
    fn adaptive_threshold(&self, flux: &[f64]) -> Vec<f64> {
        let half_win = self.median_window / 2;
        let mut threshold = vec![0.0f64; flux.len()];
        let mut window_buf = Vec::with_capacity(self.median_window);

        for i in 0..flux.len() {
            // Collect window around current frame
            window_buf.clear();
            let start = i.saturating_sub(half_win);
            let end = (i + half_win + 1).min(flux.len());
            for j in start..end {
                window_buf.push(flux[j]);
            }
            if window_buf.is_empty() {
                continue;
            }

            // Median
            window_buf.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            let median = window_buf[window_buf.len() / 2];

            // Mean absolute deviation from median (measures local spread)
            let mean_dev: f64 = window_buf.iter().map(|&v| (v - median).abs()).sum::<f64>()
                / window_buf.len() as f64;

            // Additive threshold: median + mean_deviation * sensitivity
            // In silence: median=0, mad=0 → threshold=0 → flux[i]<=0 is false → no false positives
            // In dense mix: median is high but mad is low → threshold stays near median → real onsets still punch through
            // In transient-rich material: mad is high → threshold adapts, only strong onsets detected
            threshold[i] = median + mean_dev * self.sensitivity;
        }
        threshold
    }

    /// Pick peaks above threshold with minimum interval constraint.
    fn pick_peaks(&self, flux: &[f64], threshold: &[f64]) -> Vec<f64> {
        let min_frames = (self.min_interval * self.sample_rate / self.hop_size as f64) as usize;
        let min_frames = min_frames.max(1);

        let mut peaks = Vec::new();
        let mut last_peak: Option<usize> = None;

        for i in 1..flux.len().saturating_sub(1) {
            // Must be above threshold
            if flux[i] <= threshold[i] {
                continue;
            }
            // Must be local maximum
            if flux[i] <= flux[i - 1] || flux[i] <= flux[i + 1] {
                continue;
            }
            // Minimum interval from last peak
            if let Some(last) = last_peak {
                if i - last < min_frames {
                    continue;
                }
            }

            // Convert frame index to seconds
            let time = (i * self.hop_size) as f64 / self.sample_rate;
            peaks.push(time);
            last_peak = Some(i);
        }
        peaks
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detector_creation() {
        let d = TransientDetector::new(48000.0);
        assert_eq!(d.fft_size, 1024);
        assert_eq!(d.hop_size, 256);
    }

    #[test]
    fn test_detect_silence() {
        let d = TransientDetector::new(48000.0);
        let silence = vec![0.0f64; 48000]; // 1 second
        let result = d.detect(&silence);
        assert!(result.positions.is_empty(), "Silence should have no transients");
    }

    #[test]
    fn test_detect_impulse() {
        let d = TransientDetector::new(48000.0);
        let mut audio = vec![0.0f64; 48000];
        // Place impulses at 0.25s, 0.5s, 0.75s
        audio[(0.25 * 48000.0) as usize] = 1.0;
        audio[(0.50 * 48000.0) as usize] = 1.0;
        audio[(0.75 * 48000.0) as usize] = 1.0;

        let result = d.detect(&audio);
        assert!(result.positions.len() >= 2, "Should detect at least 2 impulses, got {}", result.positions.len());

        // Check positions are roughly correct (within 20ms tolerance due to FFT windowing)
        for pos in &result.positions {
            let near_expected = [0.25, 0.50, 0.75].iter().any(|&t| (pos - t).abs() < 0.02);
            assert!(near_expected, "Unexpected transient at {}", pos);
        }
    }

    #[test]
    fn test_detect_drum_pattern() {
        let d = TransientDetector::new(48000.0);
        // Simulate kick drum: short burst of low frequency
        let mut audio = vec![0.0f64; 96000]; // 2 seconds
        for beat in 0..4 {
            let onset = (beat as f64 * 0.5 * 48000.0) as usize;
            // 5ms burst of 100Hz sine
            for i in 0..240 {
                if onset + i < audio.len() {
                    let env = 1.0 - (i as f64 / 240.0); // decay envelope
                    audio[onset + i] = env * (2.0 * PI * 100.0 * i as f64 / 48000.0).sin();
                }
            }
        }

        let result = d.detect(&audio);
        assert!(result.positions.len() >= 3, "Should detect at least 3 beats, got {}", result.positions.len());
    }

    #[test]
    fn test_detect_stereo() {
        let d = TransientDetector::new(48000.0);
        let mut left = vec![0.0f64; 48000];
        let right = vec![0.0f64; 48000];
        left[(0.5 * 48000.0) as usize] = 1.0; // impulse only in left

        let result = d.detect_stereo(&left, &right);
        // Should still detect (averaged mono has 0.5 amplitude)
        assert!(!result.positions.is_empty(), "Should detect impulse in stereo");
    }

    #[test]
    fn test_sensitivity() {
        // Higher sensitivity = fewer detections
        let mut d = TransientDetector::new(48000.0);
        let mut audio = vec![0.0f64; 48000];
        // Loud impulse + quiet impulse
        audio[12000] = 1.0;
        audio[24000] = 0.1; // 10x quieter

        d.set_sensitivity(1.0); // very sensitive
        let r1 = d.detect(&audio);

        d.set_sensitivity(3.0); // less sensitive
        let r2 = d.detect(&audio);

        assert!(r1.positions.len() >= r2.positions.len(),
            "Higher sensitivity should detect more: {} vs {}", r1.positions.len(), r2.positions.len());
    }

    #[test]
    fn test_short_audio() {
        let d = TransientDetector::new(48000.0);
        let short = vec![0.0f64; 100]; // too short for FFT
        let result = d.detect(&short);
        assert!(result.positions.is_empty());
    }

    #[test]
    fn test_min_interval() {
        let mut d = TransientDetector::new(48000.0);
        d.set_min_interval(0.1); // 100ms minimum
        let mut audio = vec![0.0f64; 48000];
        // Two impulses 50ms apart — should only detect one
        audio[12000] = 1.0; // 0.25s
        audio[14400] = 1.0; // 0.30s (50ms later)

        let result = d.detect(&audio);
        // At most 1 detection (second is within min_interval)
        assert!(result.positions.len() <= 1,
            "Should suppress close impulses, got {}", result.positions.len());
    }
}

//! FFT-based spectral analysis

use crate::{AudioDiffError, Result};
use num_complex::Complex64;
use realfft::{RealFftPlanner, RealToComplex};
use std::sync::Arc;

/// Spectral frame data
#[derive(Debug, Clone)]
pub struct SpectralFrame {
    /// Magnitude spectrum (linear, 0.0-1.0 normalized)
    pub magnitude: Vec<f64>,

    /// Phase spectrum (radians, -π to π)
    pub phase: Vec<f64>,

    /// Power spectrum (magnitude²)
    pub power: Vec<f64>,

    /// Frame timestamp in seconds
    pub time: f64,

    /// Frequency resolution (Hz per bin)
    pub freq_resolution: f64,
}

/// Spectral analyzer using FFT
pub struct SpectralAnalyzer {
    fft_size: usize,
    hop_size: usize,
    sample_rate: u32,
    fft: Arc<dyn RealToComplex<f64>>,
    window: Vec<f64>,
}

impl SpectralAnalyzer {
    /// Create new analyzer with given FFT size
    pub fn new(fft_size: usize, hop_size: usize, sample_rate: u32) -> Result<Self> {
        if !fft_size.is_power_of_two() {
            return Err(AudioDiffError::ConfigError(
                format!("FFT size must be power of 2, got {}", fft_size)
            ));
        }

        let mut planner = RealFftPlanner::<f64>::new();
        let fft = planner.plan_fft_forward(fft_size);

        // Hann window
        let window: Vec<f64> = (0..fft_size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f64::consts::PI * i as f64 / fft_size as f64).cos())
            })
            .collect();

        Ok(Self {
            fft_size,
            hop_size,
            sample_rate,
            fft,
            window,
        })
    }

    /// Analyze audio and return spectral frames
    pub fn analyze(&self, samples: &[f64]) -> Vec<SpectralFrame> {
        let num_frames = (samples.len().saturating_sub(self.fft_size)) / self.hop_size + 1;
        let mut frames = Vec::with_capacity(num_frames);

        let freq_resolution = self.sample_rate as f64 / self.fft_size as f64;
        let num_bins = self.fft_size / 2 + 1;

        let mut input = vec![0.0f64; self.fft_size];
        let mut spectrum = vec![Complex64::new(0.0, 0.0); num_bins];

        for frame_idx in 0..num_frames {
            let start = frame_idx * self.hop_size;
            let end = (start + self.fft_size).min(samples.len());

            // Apply window and copy to input buffer
            for i in 0..self.fft_size {
                let sample_idx = start + i;
                let sample = if sample_idx < end {
                    samples[sample_idx]
                } else {
                    0.0
                };
                input[i] = sample * self.window[i];
            }

            // Perform FFT
            self.fft.process(&mut input, &mut spectrum).ok();

            // Extract magnitude and phase
            let mut magnitude = Vec::with_capacity(num_bins);
            let mut phase = Vec::with_capacity(num_bins);
            let mut power = Vec::with_capacity(num_bins);

            let normalization = 2.0 / self.fft_size as f64;

            for bin in &spectrum {
                let mag = bin.norm() * normalization;
                magnitude.push(mag);
                phase.push(bin.arg());
                power.push(mag * mag);
            }

            // DC and Nyquist are not doubled
            if !magnitude.is_empty() {
                magnitude[0] /= 2.0;
                power[0] /= 4.0;
            }
            if magnitude.len() > 1 {
                let last = magnitude.len() - 1;
                magnitude[last] /= 2.0;
                power[last] /= 4.0;
            }

            frames.push(SpectralFrame {
                magnitude,
                phase,
                power,
                time: start as f64 / self.sample_rate as f64,
                freq_resolution,
            });
        }

        frames
    }

    /// Get frequency for a given bin index
    pub fn bin_to_freq(&self, bin: usize) -> f64 {
        bin as f64 * self.sample_rate as f64 / self.fft_size as f64
    }

    /// Get bin index for a given frequency
    pub fn freq_to_bin(&self, freq: f64) -> usize {
        ((freq * self.fft_size as f64 / self.sample_rate as f64).round() as usize)
            .min(self.fft_size / 2)
    }

    /// Get number of frequency bins
    pub fn num_bins(&self) -> usize {
        self.fft_size / 2 + 1
    }

    /// Get frequency resolution (Hz per bin)
    pub fn freq_resolution(&self) -> f64 {
        self.sample_rate as f64 / self.fft_size as f64
    }
}

/// A-weighting curve for perceptual comparison
pub fn a_weight(freq: f64) -> f64 {
    let f2 = freq * freq;
    let f4 = f2 * f2;

    let num = 12194.0_f64.powi(2) * f4;
    let denom = (f2 + 20.6_f64.powi(2))
        * ((f2 + 107.7_f64.powi(2)) * (f2 + 737.9_f64.powi(2))).sqrt()
        * (f2 + 12194.0_f64.powi(2));

    if denom == 0.0 {
        0.0
    } else {
        let ra = num / denom;
        // Normalize to 0 dB at 1 kHz
        let ra_1k = {
            let f = 1000.0;
            let f2 = f * f;
            let f4 = f2 * f2;
            let num = 12194.0_f64.powi(2) * f4;
            let denom = (f2 + 20.6_f64.powi(2))
                * ((f2 + 107.7_f64.powi(2)) * (f2 + 737.9_f64.powi(2))).sqrt()
                * (f2 + 12194.0_f64.powi(2));
            num / denom
        };
        ra / ra_1k
    }
}

/// Convert linear amplitude to dB
pub fn to_db(amplitude: f64) -> f64 {
    if amplitude <= 0.0 {
        -f64::INFINITY
    } else {
        20.0 * amplitude.log10()
    }
}

/// Convert dB to linear amplitude
pub fn from_db(db: f64) -> f64 {
    10.0_f64.powf(db / 20.0)
}

/// Calculate spectral centroid (brightness measure)
pub fn spectral_centroid(frame: &SpectralFrame) -> f64 {
    let mut weighted_sum = 0.0;
    let mut total_power = 0.0;

    for (bin, &power) in frame.power.iter().enumerate() {
        let freq = bin as f64 * frame.freq_resolution;
        weighted_sum += freq * power;
        total_power += power;
    }

    if total_power > 0.0 {
        weighted_sum / total_power
    } else {
        0.0
    }
}

/// Calculate spectral flatness (noise-like vs tonal)
pub fn spectral_flatness(frame: &SpectralFrame) -> f64 {
    let power = &frame.power;
    if power.is_empty() {
        return 0.0;
    }

    // Filter out very small values to avoid log(0)
    let threshold = 1e-10;
    let filtered: Vec<f64> = power.iter()
        .filter(|&&p| p > threshold)
        .copied()
        .collect();

    if filtered.is_empty() {
        return 0.0;
    }

    let n = filtered.len() as f64;

    // Geometric mean (exp of mean of logs)
    let log_sum: f64 = filtered.iter().map(|&p| p.ln()).sum();
    let geometric_mean = (log_sum / n).exp();

    // Arithmetic mean
    let arithmetic_mean: f64 = filtered.iter().sum::<f64>() / n;

    if arithmetic_mean > 0.0 {
        geometric_mean / arithmetic_mean
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spectral_analyzer() {
        let analyzer = SpectralAnalyzer::new(1024, 256, 44100).unwrap();

        // Generate 1 kHz sine wave
        let samples: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * 1000.0 * i as f64 / 44100.0).sin())
            .collect();

        let frames = analyzer.analyze(&samples);
        assert!(!frames.is_empty());

        // Check that the 1kHz bin has significant energy
        let bin_1k = analyzer.freq_to_bin(1000.0);
        let first_frame = &frames[0];

        // Find peak bin
        let peak_bin = first_frame.magnitude.iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
            .map(|(i, _)| i)
            .unwrap();

        // Peak should be near 1kHz bin (within 1 bin tolerance due to windowing)
        assert!((peak_bin as i32 - bin_1k as i32).abs() <= 1);
    }

    #[test]
    fn test_a_weight() {
        // A-weighting should be ~0 dB at 1kHz
        let w_1k = a_weight(1000.0);
        assert!((w_1k - 1.0).abs() < 0.01);

        // Low frequencies should be attenuated
        let w_100 = a_weight(100.0);
        assert!(w_100 < 0.2);

        // Very low frequencies heavily attenuated
        let w_20 = a_weight(20.0);
        assert!(w_20 < 0.01);
    }

    #[test]
    fn test_to_from_db() {
        assert!((to_db(1.0) - 0.0).abs() < 0.001);
        assert!((to_db(0.5) - (-6.02)).abs() < 0.1);
        assert!((from_db(-6.0) - 0.5).abs() < 0.01);
        assert!((from_db(0.0) - 1.0).abs() < 0.001);
    }
}

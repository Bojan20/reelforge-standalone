//! Spectral EQ matching

use std::sync::Arc;

use num_complex::Complex32;
use realfft::{RealFftPlanner, RealToComplex};

use crate::error::{MlError, MlResult};
use super::config::{MatchConfig, MatchWeighting};
use super::curve::{EqCurve, FrequencyBand};
use super::{EqMatcher, MatchResult};

/// Spectral EQ matcher
pub struct SpectralMatcher {
    /// Configuration
    config: MatchConfig,

    /// FFT planner
    fft: Arc<dyn RealToComplex<f32>>,

    /// Reference spectrum (averaged)
    reference_spectrum: Option<Vec<f32>>,

    /// Reference sample rate
    reference_sample_rate: Option<u32>,

    /// Analysis window (Hann)
    window: Vec<f32>,

    /// Perceptual weighting curve
    weighting: Vec<f32>,
}

impl SpectralMatcher {
    /// Create new spectral matcher
    pub fn new(config: MatchConfig) -> Self {
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(config.fft_size);

        // Create Hann window
        let window: Vec<f32> = (0..config.fft_size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / config.fft_size as f32).cos())
            })
            .collect();

        Self {
            config,
            fft,
            reference_spectrum: None,
            reference_sample_rate: None,
            window,
            weighting: Vec::new(),
        }
    }

    /// Compute perceptual weighting curve
    fn compute_weighting(&mut self, sample_rate: u32) {
        let n_bins = self.config.fft_size / 2 + 1;
        let freq_resolution = sample_rate as f32 / self.config.fft_size as f32;

        self.weighting = (0..n_bins)
            .map(|i| {
                let freq = i as f32 * freq_resolution;
                match self.config.weighting {
                    MatchWeighting::None => 1.0,
                    MatchWeighting::AWeighting => Self::a_weighting(freq),
                    MatchWeighting::CWeighting => Self::c_weighting(freq),
                    MatchWeighting::Itu468 => Self::itu468_weighting(freq),
                    MatchWeighting::Perceptual => Self::perceptual_weighting(freq),
                }
            })
            .collect();
    }

    /// A-weighting curve
    fn a_weighting(freq: f32) -> f32 {
        let f2 = freq * freq;
        let f4 = f2 * f2;

        let num = 12194.0_f32.powi(2) * f4;
        let den = (f2 + 20.6_f32.powi(2))
            * ((f2 + 107.7_f32.powi(2)) * (f2 + 737.9_f32.powi(2))).sqrt()
            * (f2 + 12194.0_f32.powi(2));

        if den > 0.0 {
            let ra = num / den;
            let db = 20.0 * ra.log10() + 2.0;
            10.0_f32.powf(db / 20.0)
        } else {
            0.0
        }
    }

    /// C-weighting curve
    fn c_weighting(freq: f32) -> f32 {
        let f2 = freq * freq;

        let num = 12194.0_f32.powi(2) * f2;
        let den = (f2 + 20.6_f32.powi(2)) * (f2 + 12194.0_f32.powi(2));

        if den > 0.0 {
            let rc = num / den;
            let db = 20.0 * rc.log10() + 0.06;
            10.0_f32.powf(db / 20.0)
        } else {
            0.0
        }
    }

    /// ITU-R 468 weighting curve (simplified)
    fn itu468_weighting(freq: f32) -> f32 {
        // Simplified ITU-R 468 approximation
        let log_freq = freq.log10();

        let db = if freq < 20.0 {
            -100.0
        } else if freq < 100.0 {
            -30.0 + (log_freq - 1.3) * 35.0
        } else if freq < 1000.0 {
            5.0 + (log_freq - 2.0) * 7.0
        } else if freq < 6300.0 {
            12.0
        } else if freq < 12500.0 {
            12.0 - (log_freq - 3.8) * 20.0
        } else {
            -20.0
        };

        10.0_f32.powf(db / 20.0)
    }

    /// Perceptual weighting (custom curve)
    fn perceptual_weighting(freq: f32) -> f32 {
        // Custom perceptual curve based on equal loudness contours
        if freq < 20.0 {
            0.0
        } else if freq < 100.0 {
            (freq / 100.0).sqrt()
        } else if freq < 1000.0 {
            1.0
        } else if freq < 4000.0 {
            1.0 + (freq - 1000.0) / 10000.0 // Slight boost in presence region
        } else if freq < 10000.0 {
            1.1 - (freq - 4000.0) / 20000.0
        } else {
            0.8 - (freq - 10000.0) / 50000.0
        }
    }

    /// Compute averaged spectrum from audio
    fn compute_spectrum(&self, audio: &[f32], channels: usize, _sample_rate: u32) -> MlResult<Vec<f32>> {
        // Convert to mono if needed
        let mono: Vec<f32> = if channels == 2 {
            audio
                .chunks(2)
                .map(|c| (c[0] + c.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect()
        } else {
            audio.to_vec()
        };

        let fft_size = self.config.fft_size;
        let hop_size = fft_size / 2;
        let n_bins = fft_size / 2 + 1;

        let num_frames = (mono.len() - fft_size) / hop_size + 1;
        if num_frames == 0 {
            return Err(MlError::BufferTooSmall {
                needed: fft_size,
                got: mono.len(),
            });
        }

        // Accumulate magnitude spectrum
        let mut spectrum_sum = vec![0.0f64; n_bins];

        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft.get_scratch_len()];

        for frame_idx in 0..num_frames {
            let start = frame_idx * hop_size;

            // Apply window
            let mut windowed: Vec<f32> = mono[start..start + fft_size]
                .iter()
                .zip(self.window.iter())
                .map(|(&s, &w)| s * w)
                .collect();

            // FFT
            let mut spectrum = vec![Complex32::new(0.0, 0.0); n_bins];
            self.fft
                .process_with_scratch(&mut windowed, &mut spectrum, &mut scratch)
                .map_err(|e| MlError::ProcessingFailed(format!("FFT failed: {}", e)))?;

            // Accumulate magnitude (in dB scale)
            for (i, &c) in spectrum.iter().enumerate() {
                let mag = c.norm();
                let mag_db = 20.0 * (mag.max(1e-10) as f64).log10();
                spectrum_sum[i] += mag_db;
            }
        }

        // Average
        let avg_spectrum: Vec<f32> = spectrum_sum
            .iter()
            .map(|&s| (s / num_frames as f64) as f32)
            .collect();

        Ok(avg_spectrum)
    }

    /// Compute difference curve and convert to EQ bands
    fn compute_eq_curve(
        &self,
        reference: &[f32],
        target: &[f32],
        sample_rate: u32,
    ) -> MlResult<EqCurve> {
        let n_bins = reference.len().min(target.len());
        let freq_resolution = sample_rate as f32 / self.config.fft_size as f32;

        // Compute difference with weighting
        let mut diff: Vec<f32> = (0..n_bins)
            .map(|i| {
                let weight = self.weighting.get(i).copied().unwrap_or(1.0);
                (reference[i] - target[i]) * weight
            })
            .collect();

        // Apply smoothing
        if self.config.smoothing > 0.0 {
            let window_size = ((n_bins as f32 * self.config.smoothing * 0.1) as usize).max(3);
            Self::smooth_array(&mut diff, window_size);
        }

        // Limit gain
        for d in &mut diff {
            *d = d.clamp(-self.config.max_gain_db, self.config.max_gain_db);
        }

        // Convert to EQ bands
        let bands = self.bins_to_bands(&diff, freq_resolution);

        // Compute quality metric
        let error: f32 = diff.iter().map(|&d| d.abs()).sum::<f32>() / diff.len() as f32;
        let quality = 1.0 - (error / self.config.max_gain_db).min(1.0);

        let mut curve = EqCurve::new(sample_rate);
        curve.bands = bands;
        curve.quality = quality;

        // Apply intensity
        if self.config.intensity < 1.0 {
            curve.scale(self.config.intensity);
        }

        Ok(curve)
    }

    /// Smooth array with moving average
    fn smooth_array(arr: &mut [f32], window_size: usize) {
        let half = window_size / 2;
        let temp: Vec<f32> = arr.to_vec();

        for i in 0..arr.len() {
            let start = i.saturating_sub(half);
            let end = (i + half + 1).min(arr.len());
            arr[i] = temp[start..end].iter().sum::<f32>() / (end - start) as f32;
        }
    }

    /// Convert frequency bins to EQ bands (log-spaced)
    fn bins_to_bands(&self, diff: &[f32], freq_resolution: f32) -> Vec<FrequencyBand> {
        let num_bands = self.config.num_bands;
        let min_freq = self.config.min_freq;
        let max_freq = self.config.max_freq;

        let log_min = min_freq.ln();
        let log_max = max_freq.ln();

        (0..num_bands)
            .map(|i| {
                // Logarithmic band center
                let t = i as f32 / (num_bands - 1).max(1) as f32;
                let center_freq = (log_min + t * (log_max - log_min)).exp();

                // Find corresponding bin range
                let lower_freq = if i > 0 {
                    let t_lower = (i as f32 - 0.5) / (num_bands - 1).max(1) as f32;
                    (log_min + t_lower * (log_max - log_min)).exp()
                } else {
                    min_freq
                };

                let upper_freq = if i < num_bands - 1 {
                    let t_upper = (i as f32 + 0.5) / (num_bands - 1).max(1) as f32;
                    (log_min + t_upper * (log_max - log_min)).exp()
                } else {
                    max_freq
                };

                let lower_bin = (lower_freq / freq_resolution) as usize;
                let upper_bin = (upper_freq / freq_resolution).ceil() as usize;
                let lower_bin = lower_bin.min(diff.len() - 1);
                let upper_bin = upper_bin.min(diff.len()).max(lower_bin + 1);

                // Average gain in this band
                let gain: f32 = diff[lower_bin..upper_bin].iter().sum::<f32>()
                    / (upper_bin - lower_bin) as f32;

                // Q based on bandwidth
                let octaves = (upper_freq / lower_freq).log2();
                let q = 1.0 / octaves.max(0.1);

                FrequencyBand::new(center_freq, gain, q)
            })
            .collect()
    }
}

impl EqMatcher for SpectralMatcher {
    fn set_reference(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<()> {
        // Compute weighting for this sample rate
        self.compute_weighting(sample_rate);

        // Compute reference spectrum
        let spectrum = self.compute_spectrum(audio, channels, sample_rate)?;

        self.reference_spectrum = Some(spectrum);
        self.reference_sample_rate = Some(sample_rate);

        Ok(())
    }

    fn compute_match(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<MatchResult> {
        let reference = self.reference_spectrum.as_ref().ok_or_else(|| {
            MlError::Internal("No reference spectrum set".into())
        })?;

        // Ensure sample rates match
        if self.reference_sample_rate != Some(sample_rate) {
            return Err(MlError::InvalidSampleRate {
                expected: self.reference_sample_rate.unwrap_or(0),
                got: sample_rate,
            });
        }

        // Compute target spectrum
        let target = self.compute_spectrum(audio, channels, sample_rate)?;

        // Compute EQ curve
        let eq_curve = self.compute_eq_curve(reference, &target, sample_rate)?;

        // Compute error metrics
        let error_db = eq_curve.gain_range_db();
        let perceptual_diff = 1.0 - eq_curve.quality;

        Ok(MatchResult {
            eq_curve,
            quality: 1.0 - perceptual_diff,
            error_db,
            perceptual_diff,
        })
    }

    fn reference_spectrum(&self) -> Option<&[f32]> {
        self.reference_spectrum.as_deref()
    }

    fn reset(&mut self) {
        self.reference_spectrum = None;
        self.reference_sample_rate = None;
    }

    fn num_bands(&self) -> usize {
        self.config.num_bands
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_weighting_curves() {
        // A-weighting should be low at low frequencies
        let a_20 = SpectralMatcher::a_weighting(20.0);
        let a_1000 = SpectralMatcher::a_weighting(1000.0);
        assert!(a_20 < a_1000);

        // Peak around 2-4kHz
        let a_3000 = SpectralMatcher::a_weighting(3000.0);
        assert!(a_3000 > a_1000);
    }

    #[test]
    fn test_spectral_matcher_creation() {
        let config = MatchConfig::default();
        let matcher = SpectralMatcher::new(config);
        assert!(matcher.reference_spectrum.is_none());
    }
}

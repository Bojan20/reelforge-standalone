//! # Sines-Transients-Noise (STN) Separation
//!
//! Decomposes audio into three components for optimal per-component processing:
//! - **Sines**: Harmonic content (phase vocoder optimal)
//! - **Transients**: Percussive/attack content (WSOLA optimal)
//! - **Noise**: Stochastic content (granular/neural optimal)
//!
//! ## Algorithm
//!
//! Based on median filtering in spectrogram domain:
//! 1. Horizontal median → transients
//! 2. Vertical median → sines
//! 3. Residual → noise

use rustfft::{FftPlanner, num_complex::Complex64};
use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// STN COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Separated audio components
#[derive(Debug, Clone)]
pub struct StnComponents {
    /// Sinusoidal/harmonic component
    pub sines: Vec<f64>,
    /// Transient/percussive component
    pub transients: Vec<f64>,
    /// Noise/stochastic component
    pub noise: Vec<f64>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// STN DECOMPOSER
// ═══════════════════════════════════════════════════════════════════════════════

/// Sines-Transients-Noise decomposer
pub struct StnDecomposer {
    /// Sample rate
    sample_rate: f64,
    /// FFT size
    fft_size: usize,
    /// Hop size
    hop_size: usize,
    /// Median filter size for harmonic detection (frequency bins)
    harmonic_filter_size: usize,
    /// Median filter size for percussive detection (time frames)
    percussive_filter_size: usize,
    /// Separation strength (0.0 - 1.0)
    separation_strength: f64,
    /// FFT planner
    fft_planner: FftPlanner<f64>,
}

impl StnDecomposer {
    /// Create new STN decomposer
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            fft_size: 4096,
            hop_size: 1024,
            harmonic_filter_size: 17, // Frequency median filter (odd number)
            percussive_filter_size: 17, // Time median filter (odd number)
            separation_strength: 1.0,
            fft_planner: FftPlanner::new(),
        }
    }

    /// Create with custom parameters
    pub fn with_params(
        sample_rate: f64,
        fft_size: usize,
        hop_size: usize,
        harmonic_filter: usize,
        percussive_filter: usize,
    ) -> Self {
        Self {
            sample_rate,
            fft_size,
            hop_size,
            harmonic_filter_size: harmonic_filter | 1, // Ensure odd
            percussive_filter_size: percussive_filter | 1,
            separation_strength: 1.0,
            fft_planner: FftPlanner::new(),
        }
    }

    /// Decompose audio into STN components
    pub fn decompose(&mut self, input: &[f64]) -> StnComponents {
        // 1. Compute STFT
        let (magnitude, phase) = self.stft(input);

        // 2. Separate harmonic and percussive in spectrogram domain
        let (harmonic_mask, percussive_mask) = self.compute_masks(&magnitude);

        // 3. Apply masks and compute noise mask
        let noise_mask = self.compute_noise_mask(&harmonic_mask, &percussive_mask);

        // 4. Inverse STFT for each component
        let sines = self.istft(&magnitude, &phase, &harmonic_mask);
        let transients = self.istft(&magnitude, &phase, &percussive_mask);
        let noise = self.istft(&magnitude, &phase, &noise_mask);

        StnComponents {
            sines,
            transients,
            noise,
        }
    }

    /// Compute STFT
    fn stft(&mut self, input: &[f64]) -> (Vec<Vec<f64>>, Vec<Vec<f64>>) {
        let num_frames = input.len().saturating_sub(self.fft_size) / self.hop_size + 1;
        let num_bins = self.fft_size / 2 + 1;

        let mut magnitude = vec![vec![0.0; num_bins]; num_frames];
        let mut phase = vec![vec![0.0; num_bins]; num_frames];

        for frame_idx in 0..num_frames {
            let start = frame_idx * self.hop_size;
            let end = (start + self.fft_size).min(input.len());

            // Window and prepare FFT buffer
            let mut buffer: Vec<Complex64> = vec![Complex64::new(0.0, 0.0); self.fft_size];
            for i in 0..(end - start) {
                let window = 0.5 * (1.0 - (2.0 * PI * i as f64 / self.fft_size as f64).cos());
                buffer[i] = Complex64::new(input[start + i] * window, 0.0);
            }

            // FFT
            let fft = self.fft_planner.plan_fft_forward(self.fft_size);
            fft.process(&mut buffer);

            // Extract magnitude and phase
            for (k, bin) in buffer[..num_bins].iter().enumerate() {
                magnitude[frame_idx][k] = bin.norm();
                phase[frame_idx][k] = bin.arg();
            }
        }

        (magnitude, phase)
    }

    /// Inverse STFT with mask
    fn istft(&mut self, magnitude: &[Vec<f64>], phase: &[Vec<f64>], mask: &[Vec<f64>]) -> Vec<f64> {
        if magnitude.is_empty() || magnitude[0].is_empty() {
            return vec![];
        }

        let num_frames = magnitude.len();
        let output_len = (num_frames - 1) * self.hop_size + self.fft_size;
        let mut output = vec![0.0; output_len];
        let mut norm = vec![0.0; output_len];

        for frame_idx in 0..num_frames {
            // Build complex spectrum with mask
            let mut buffer: Vec<Complex64> = vec![Complex64::new(0.0, 0.0); self.fft_size];

            let num_bins = magnitude[frame_idx].len();
            for k in 0..num_bins {
                let mag = magnitude[frame_idx][k] * mask[frame_idx][k];
                let ph = phase[frame_idx][k];
                buffer[k] = Complex64::from_polar(mag, ph);

                // Mirror for negative frequencies (except DC and Nyquist)
                if k > 0 && k < self.fft_size / 2 {
                    buffer[self.fft_size - k] = buffer[k].conj();
                }
            }

            // IFFT
            let ifft = self.fft_planner.plan_fft_inverse(self.fft_size);
            ifft.process(&mut buffer);

            // Overlap-add with synthesis window
            let start = frame_idx * self.hop_size;
            for (i, bin) in buffer.iter().enumerate() {
                if start + i < output_len {
                    let window = 0.5 * (1.0 - (2.0 * PI * i as f64 / self.fft_size as f64).cos());
                    output[start + i] += bin.re * window / self.fft_size as f64;
                    norm[start + i] += window * window;
                }
            }
        }

        // Normalize by window overlap
        for (out, n) in output.iter_mut().zip(norm.iter()) {
            if *n > 1e-10 {
                *out /= n;
            }
        }

        output
    }

    /// Compute harmonic and percussive masks using median filtering
    fn compute_masks(&self, magnitude: &[Vec<f64>]) -> (Vec<Vec<f64>>, Vec<Vec<f64>>) {
        let num_frames = magnitude.len();
        let num_bins = if num_frames > 0 {
            magnitude[0].len()
        } else {
            0
        };

        // Harmonic mask: median filter along frequency axis
        let harmonic_enhanced = self.median_filter_freq(magnitude);

        // Percussive mask: median filter along time axis
        let percussive_enhanced = self.median_filter_time(magnitude);

        // Compute soft masks using Wiener-like filtering
        let mut harmonic_mask = vec![vec![0.0; num_bins]; num_frames];
        let mut percussive_mask = vec![vec![0.0; num_bins]; num_frames];

        let p = self.separation_strength * 2.0; // Power for soft masking

        for t in 0..num_frames {
            for f in 0..num_bins {
                let h = harmonic_enhanced[t][f].powf(p);
                let pe = percussive_enhanced[t][f].powf(p);
                let total = h + pe + 1e-10;

                harmonic_mask[t][f] = h / total;
                percussive_mask[t][f] = pe / total;
            }
        }

        (harmonic_mask, percussive_mask)
    }

    /// Compute noise mask (residual after H+P)
    fn compute_noise_mask(
        &self,
        harmonic_mask: &[Vec<f64>],
        percussive_mask: &[Vec<f64>],
    ) -> Vec<Vec<f64>> {
        let num_frames = harmonic_mask.len();
        let num_bins = if num_frames > 0 {
            harmonic_mask[0].len()
        } else {
            0
        };

        let mut noise_mask = vec![vec![0.0; num_bins]; num_frames];

        for t in 0..num_frames {
            for f in 0..num_bins {
                // Noise is what's left after removing harmonics and percussive
                let h = harmonic_mask[t][f];
                let p = percussive_mask[t][f];
                noise_mask[t][f] = (1.0 - h.max(p)).max(0.0);
            }
        }

        noise_mask
    }

    /// Median filter along frequency axis (enhances harmonics)
    fn median_filter_freq(&self, magnitude: &[Vec<f64>]) -> Vec<Vec<f64>> {
        let num_frames = magnitude.len();
        let num_bins = if num_frames > 0 {
            magnitude[0].len()
        } else {
            0
        };
        let half = self.harmonic_filter_size / 2;

        let mut filtered = vec![vec![0.0; num_bins]; num_frames];

        for t in 0..num_frames {
            for f in 0..num_bins {
                // Collect neighborhood values
                let mut neighbors: Vec<f64> = Vec::with_capacity(self.harmonic_filter_size);

                for offset in 0..self.harmonic_filter_size {
                    let idx = f as i32 - half as i32 + offset as i32;
                    if idx >= 0 && (idx as usize) < num_bins {
                        neighbors.push(magnitude[t][idx as usize]);
                    }
                }

                filtered[t][f] = median(&mut neighbors);
            }
        }

        filtered
    }

    /// Median filter along time axis (enhances percussive)
    fn median_filter_time(&self, magnitude: &[Vec<f64>]) -> Vec<Vec<f64>> {
        let num_frames = magnitude.len();
        let num_bins = if num_frames > 0 {
            magnitude[0].len()
        } else {
            0
        };
        let half = self.percussive_filter_size / 2;

        let mut filtered = vec![vec![0.0; num_bins]; num_frames];

        for t in 0..num_frames {
            for f in 0..num_bins {
                // Collect neighborhood values
                let mut neighbors: Vec<f64> = Vec::with_capacity(self.percussive_filter_size);

                for offset in 0..self.percussive_filter_size {
                    let idx = t as i32 - half as i32 + offset as i32;
                    if idx >= 0 && (idx as usize) < num_frames {
                        neighbors.push(magnitude[idx as usize][f]);
                    }
                }

                filtered[t][f] = median(&mut neighbors);
            }
        }

        filtered
    }

    /// Set separation strength
    pub fn set_separation_strength(&mut self, strength: f64) {
        self.separation_strength = strength.clamp(0.0, 2.0);
    }
}

/// Compute median of a slice (modifies input order)
fn median(values: &mut [f64]) -> f64 {
    if values.is_empty() {
        return 0.0;
    }

    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let mid = values.len() / 2;
    if values.len().is_multiple_of(2) {
        (values[mid - 1] + values[mid]) / 2.0
    } else {
        values[mid]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stn_decomposer_creation() {
        let decomposer = StnDecomposer::new(44100.0);
        assert!((decomposer.sample_rate - 44100.0).abs() < 1e-6);
    }

    #[test]
    fn test_median() {
        let mut values = vec![3.0, 1.0, 4.0, 1.0, 5.0];
        assert!((median(&mut values) - 3.0).abs() < 1e-10);

        let mut values2 = vec![1.0, 2.0, 3.0, 4.0];
        assert!((median(&mut values2) - 2.5).abs() < 1e-10);
    }

    #[test]
    fn test_decompose() {
        let mut decomposer = StnDecomposer::new(44100.0);

        // Generate test signal: sine + click + noise
        let duration = 0.5; // 500ms
        let samples = (44100.0 * duration) as usize;
        let mut signal = vec![0.0; samples];

        // Add sine wave (harmonic content)
        for (i, s) in signal.iter_mut().enumerate() {
            *s += 0.5 * (2.0 * PI * 440.0 * i as f64 / 44100.0).sin();
        }

        // Add click (transient)
        signal[samples / 2] = 1.0;
        signal[samples / 2 + 1] = -0.5;

        // Add small noise
        for s in &mut signal {
            *s += 0.01 * (rand_simple() * 2.0 - 1.0);
        }

        let components = decomposer.decompose(&signal);

        assert!(!components.sines.is_empty());
        assert!(!components.transients.is_empty());
        assert!(!components.noise.is_empty());
    }

    // Simple pseudo-random for testing
    fn rand_simple() -> f64 {
        use std::time::{SystemTime, UNIX_EPOCH};
        let t = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        ((t % 1000) as f64) / 1000.0
    }
}

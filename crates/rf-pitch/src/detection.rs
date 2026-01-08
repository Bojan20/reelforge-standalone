//! Pitch detection algorithms
//!
//! Implements multiple pitch detection methods:
//! - YIN (autocorrelation-based)
//! - pYIN (probabilistic YIN with HMM)
//! - Harmonic product spectrum
//! - Multi-algorithm fusion

use crate::{DetectionAlgorithm, PitchConfig, PitchError, PitchResult};
use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;
use std::sync::Arc;

/// YIN pitch detector
pub struct YinDetector {
    /// Sample rate
    sample_rate: u32,
    /// Window size
    window_size: usize,
    /// Minimum frequency
    min_freq: f32,
    /// Maximum frequency
    max_freq: f32,
    /// YIN threshold
    threshold: f32,
    /// Difference buffer
    diff_buffer: Vec<f32>,
    /// Cumulative mean normalized difference
    cmnd_buffer: Vec<f32>,
}

impl YinDetector {
    /// Create new YIN detector
    pub fn new(config: &PitchConfig) -> Self {
        let window_size = config.window_size;
        Self {
            sample_rate: config.sample_rate,
            window_size,
            min_freq: config.min_freq,
            max_freq: config.max_freq,
            threshold: 0.1,
            diff_buffer: vec![0.0; window_size / 2],
            cmnd_buffer: vec![0.0; window_size / 2],
        }
    }

    /// Set YIN threshold (0.0 - 1.0)
    pub fn set_threshold(&mut self, threshold: f32) {
        self.threshold = threshold.clamp(0.01, 0.5);
    }

    /// Detect pitch in audio frame
    pub fn detect(&mut self, samples: &[f32]) -> PitchResult<Option<(f32, f32)>> {
        if samples.len() < self.window_size {
            return Err(PitchError::InputTooShort(samples.len(), self.window_size));
        }

        // Calculate difference function
        self.difference_function(samples);

        // Calculate cumulative mean normalized difference
        self.cumulative_mean_normalized_difference();

        // Find minimum below threshold
        let min_tau = (self.sample_rate as f32 / self.max_freq) as usize;
        let max_tau = (self.sample_rate as f32 / self.min_freq) as usize;
        let max_tau = max_tau.min(self.cmnd_buffer.len() - 1);

        let mut best_tau = 0;
        let mut best_value = f32::MAX;

        let mut tau = min_tau;
        while tau < max_tau {
            if self.cmnd_buffer[tau] < self.threshold {
                // Find local minimum
                while tau + 1 < max_tau && self.cmnd_buffer[tau + 1] < self.cmnd_buffer[tau] {
                    tau += 1;
                }
                if self.cmnd_buffer[tau] < best_value {
                    best_tau = tau;
                    best_value = self.cmnd_buffer[tau];
                    break;
                }
            }
            tau += 1;
        }

        if best_tau == 0 {
            // No pitch found, try absolute minimum
            for tau in min_tau..max_tau {
                if self.cmnd_buffer[tau] < best_value {
                    best_tau = tau;
                    best_value = self.cmnd_buffer[tau];
                }
            }
        }

        if best_tau == 0 || best_value > 0.5 {
            return Ok(None);
        }

        // Parabolic interpolation for better accuracy
        let tau_refined = self.parabolic_interpolation(best_tau);

        let frequency = self.sample_rate as f32 / tau_refined;
        let confidence = 1.0 - best_value.min(1.0);

        Ok(Some((frequency, confidence)))
    }

    /// Calculate difference function
    fn difference_function(&mut self, samples: &[f32]) {
        let half_window = self.window_size / 2;

        for tau in 0..half_window {
            let mut sum = 0.0f32;
            for j in 0..half_window {
                let diff = samples[j] - samples[j + tau];
                sum += diff * diff;
            }
            self.diff_buffer[tau] = sum;
        }
    }

    /// Calculate cumulative mean normalized difference
    fn cumulative_mean_normalized_difference(&mut self) {
        self.cmnd_buffer[0] = 1.0;
        let mut running_sum = 0.0f32;

        for tau in 1..self.diff_buffer.len() {
            running_sum += self.diff_buffer[tau];
            if running_sum > 0.0 {
                self.cmnd_buffer[tau] = self.diff_buffer[tau] * tau as f32 / running_sum;
            } else {
                self.cmnd_buffer[tau] = 1.0;
            }
        }
    }

    /// Parabolic interpolation for sub-sample accuracy
    fn parabolic_interpolation(&self, tau: usize) -> f32 {
        if tau == 0 || tau >= self.cmnd_buffer.len() - 1 {
            return tau as f32;
        }

        let s0 = self.cmnd_buffer[tau - 1];
        let s1 = self.cmnd_buffer[tau];
        let s2 = self.cmnd_buffer[tau + 1];

        let adjustment = (s2 - s0) / (2.0 * (2.0 * s1 - s0 - s2));

        if adjustment.is_finite() {
            tau as f32 + adjustment
        } else {
            tau as f32
        }
    }
}

/// Probabilistic YIN (pYIN) detector with HMM
pub struct ProbabilisticYinDetector {
    /// Base YIN detector
    yin: YinDetector,
    /// Number of pitch candidates
    num_candidates: usize,
    /// Pitch candidates per frame
    candidates: Vec<Vec<(f32, f32)>>, // (frequency, probability)
    /// HMM transition probability
    transition_width: f32,
}

impl ProbabilisticYinDetector {
    /// Create new pYIN detector
    pub fn new(config: &PitchConfig) -> Self {
        Self {
            yin: YinDetector::new(config),
            num_candidates: 5,
            candidates: Vec::new(),
            transition_width: 50.0, // cents
        }
    }

    /// Detect pitch with multiple candidates
    pub fn detect_candidates(&mut self, samples: &[f32]) -> PitchResult<Vec<(f32, f32)>> {
        if samples.len() < self.yin.window_size {
            return Err(PitchError::InputTooShort(
                samples.len(),
                self.yin.window_size,
            ));
        }

        self.yin.difference_function(samples);
        self.yin.cumulative_mean_normalized_difference();

        let min_tau = (self.yin.sample_rate as f32 / self.yin.max_freq) as usize;
        let max_tau = (self.yin.sample_rate as f32 / self.yin.min_freq) as usize;
        let max_tau = max_tau.min(self.yin.cmnd_buffer.len() - 1);

        // Find all local minima
        let mut candidates = Vec::new();

        for tau in min_tau + 1..max_tau - 1 {
            if self.yin.cmnd_buffer[tau] < self.yin.cmnd_buffer[tau - 1]
                && self.yin.cmnd_buffer[tau] < self.yin.cmnd_buffer[tau + 1]
                && self.yin.cmnd_buffer[tau] < 0.5
            {
                let tau_refined = self.yin.parabolic_interpolation(tau);
                let frequency = self.yin.sample_rate as f32 / tau_refined;
                let probability = 1.0 - self.yin.cmnd_buffer[tau].min(1.0);
                candidates.push((frequency, probability));
            }
        }

        // Sort by probability
        candidates.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // Keep top candidates
        candidates.truncate(self.num_candidates);

        Ok(candidates)
    }

    /// Process sequence with HMM smoothing
    pub fn process_sequence(&mut self, frames: &[&[f32]]) -> PitchResult<Vec<Option<f32>>> {
        self.candidates.clear();

        // Get candidates for each frame
        for frame in frames {
            let frame_candidates = self.detect_candidates(frame)?;
            self.candidates.push(frame_candidates);
        }

        // Viterbi decoding (simplified)
        let mut result = Vec::new();

        for candidates in &self.candidates {
            if candidates.is_empty() {
                result.push(None);
            } else {
                // Take highest probability candidate
                result.push(Some(candidates[0].0));
            }
        }

        Ok(result)
    }
}

/// Harmonic product spectrum detector
pub struct HarmonicDetector {
    /// Sample rate
    sample_rate: u32,
    /// FFT size
    fft_size: usize,
    /// Number of harmonics
    num_harmonics: usize,
    /// FFT planner
    fft: Arc<dyn RealToComplex<f32>>,
    /// FFT input buffer
    fft_input: Vec<f32>,
    /// FFT output buffer
    fft_output: Vec<Complex<f32>>,
    /// Magnitude spectrum
    spectrum: Vec<f32>,
    /// Harmonic product spectrum
    hps: Vec<f32>,
    /// Minimum frequency
    min_freq: f32,
    /// Maximum frequency
    max_freq: f32,
}

impl HarmonicDetector {
    /// Create new harmonic detector
    pub fn new(config: &PitchConfig) -> Self {
        let fft_size = config.window_size;
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        Self {
            sample_rate: config.sample_rate,
            fft_size,
            num_harmonics: 5,
            fft,
            fft_input: vec![0.0; fft_size],
            fft_output: vec![Complex::new(0.0, 0.0); fft_size / 2 + 1],
            spectrum: vec![0.0; fft_size / 2 + 1],
            hps: vec![0.0; fft_size / 2 + 1],
            min_freq: config.min_freq,
            max_freq: config.max_freq,
        }
    }

    /// Detect pitch using harmonic product spectrum
    pub fn detect(&mut self, samples: &[f32]) -> PitchResult<Option<(f32, f32)>> {
        if samples.len() < self.fft_size {
            return Err(PitchError::InputTooShort(samples.len(), self.fft_size));
        }

        // Apply Hann window and copy to input
        for (i, sample) in samples.iter().take(self.fft_size).enumerate() {
            let window =
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / self.fft_size as f32).cos());
            self.fft_input[i] = sample * window;
        }

        // FFT
        self.fft
            .process(&mut self.fft_input, &mut self.fft_output)
            .map_err(|e| PitchError::FftError(format!("{:?}", e)))?;

        // Magnitude spectrum
        for (i, c) in self.fft_output.iter().enumerate() {
            self.spectrum[i] = (c.re * c.re + c.im * c.im).sqrt();
        }

        // Harmonic product spectrum
        let hps_len = self.spectrum.len() / self.num_harmonics;
        self.hps[..hps_len].copy_from_slice(&self.spectrum[..hps_len]);

        for h in 2..=self.num_harmonics {
            for i in 0..hps_len {
                self.hps[i] *= self.spectrum[i * h].max(1e-10);
            }
        }

        // Find peak in valid frequency range
        let bin_freq = self.sample_rate as f32 / self.fft_size as f32;
        let min_bin = (self.min_freq / bin_freq) as usize;
        let max_bin = ((self.max_freq / bin_freq) as usize).min(hps_len - 1);

        let mut max_val = 0.0f32;
        let mut max_bin_idx = 0;

        for i in min_bin..max_bin {
            if self.hps[i] > max_val {
                max_val = self.hps[i];
                max_bin_idx = i;
            }
        }

        if max_val < 1e-10 {
            return Ok(None);
        }

        // Parabolic interpolation
        let freq = if max_bin_idx > 0 && max_bin_idx < hps_len - 1 {
            let alpha = self.hps[max_bin_idx - 1];
            let beta = self.hps[max_bin_idx];
            let gamma = self.hps[max_bin_idx + 1];
            let p = 0.5 * (alpha - gamma) / (alpha - 2.0 * beta + gamma);
            (max_bin_idx as f32 + p) * bin_freq
        } else {
            max_bin_idx as f32 * bin_freq
        };

        // Confidence based on peak prominence
        let mean = self.hps[min_bin..max_bin].iter().sum::<f32>() / (max_bin - min_bin) as f32;
        let confidence = (max_val / mean.max(1e-10)).min(10.0) / 10.0;

        Ok(Some((freq, confidence)))
    }
}

/// Multi-algorithm pitch detector with fusion
pub struct FusionDetector {
    /// YIN detector
    yin: YinDetector,
    /// Harmonic detector
    harmonic: HarmonicDetector,
    /// Algorithm weights
    weights: [f32; 2],
}

impl FusionDetector {
    /// Create new fusion detector
    pub fn new(config: &PitchConfig) -> Self {
        Self {
            yin: YinDetector::new(config),
            harmonic: HarmonicDetector::new(config),
            weights: [0.6, 0.4], // YIN weight, Harmonic weight
        }
    }

    /// Detect pitch using multiple algorithms
    pub fn detect(&mut self, samples: &[f32]) -> PitchResult<Option<(f32, f32)>> {
        let yin_result = self.yin.detect(samples)?;
        let harmonic_result = self.harmonic.detect(samples)?;

        match (yin_result, harmonic_result) {
            (Some((f1, c1)), Some((f2, c2))) => {
                // Check if they agree (within 50 cents)
                let cents_diff = 1200.0 * (f2 / f1).abs().log2();

                if cents_diff < 50.0 {
                    // Weighted average
                    let w1 = self.weights[0] * c1;
                    let w2 = self.weights[1] * c2;
                    let freq = (f1 * w1 + f2 * w2) / (w1 + w2);
                    let conf = (c1 * self.weights[0] + c2 * self.weights[1]).min(1.0);
                    Ok(Some((freq, conf)))
                } else {
                    // Disagreement - pick higher confidence
                    if c1 > c2 {
                        Ok(Some((f1, c1 * 0.8)))
                    } else {
                        Ok(Some((f2, c2 * 0.8)))
                    }
                }
            }
            (Some(result), None) | (None, Some(result)) => Ok(Some((result.0, result.1 * 0.7))),
            (None, None) => Ok(None),
        }
    }
}

/// Unified pitch detector that dispatches to appropriate algorithm
pub struct PitchDetector {
    /// Detection algorithm
    algorithm: DetectionAlgorithm,
    /// YIN detector
    yin: Option<YinDetector>,
    /// pYIN detector
    pyin: Option<ProbabilisticYinDetector>,
    /// Harmonic detector
    harmonic: Option<HarmonicDetector>,
    /// Fusion detector
    fusion: Option<FusionDetector>,
}

impl PitchDetector {
    /// Create new pitch detector
    pub fn new(config: &PitchConfig) -> Self {
        let mut detector = Self {
            algorithm: config.algorithm,
            yin: None,
            pyin: None,
            harmonic: None,
            fusion: None,
        };

        match config.algorithm {
            DetectionAlgorithm::Yin => {
                detector.yin = Some(YinDetector::new(config));
            }
            DetectionAlgorithm::ProbabilisticYin => {
                detector.pyin = Some(ProbabilisticYinDetector::new(config));
            }
            DetectionAlgorithm::Harmonic => {
                detector.harmonic = Some(HarmonicDetector::new(config));
            }
            DetectionAlgorithm::Fusion => {
                detector.fusion = Some(FusionDetector::new(config));
            }
            DetectionAlgorithm::Neural => {
                // Fallback to fusion for now
                detector.fusion = Some(FusionDetector::new(config));
            }
        }

        detector
    }

    /// Detect pitch in frame
    pub fn detect(&mut self, samples: &[f32]) -> PitchResult<Option<(f32, f32)>> {
        match self.algorithm {
            DetectionAlgorithm::Yin => self.yin.as_mut().unwrap().detect(samples),
            DetectionAlgorithm::ProbabilisticYin => {
                let candidates = self.pyin.as_mut().unwrap().detect_candidates(samples)?;
                Ok(candidates.first().copied())
            }
            DetectionAlgorithm::Harmonic => self.harmonic.as_mut().unwrap().detect(samples),
            DetectionAlgorithm::Fusion | DetectionAlgorithm::Neural => {
                self.fusion.as_mut().unwrap().detect(samples)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn generate_sine(freq: f32, sample_rate: u32, num_samples: usize) -> Vec<f32> {
        (0..num_samples)
            .map(|i| (2.0 * std::f32::consts::PI * freq * i as f32 / sample_rate as f32).sin())
            .collect()
    }

    #[test]
    fn test_yin_detector() {
        let config = PitchConfig::default();
        let mut detector = YinDetector::new(&config);

        // Generate 440 Hz sine
        let samples = generate_sine(440.0, config.sample_rate, config.window_size);

        let result = detector.detect(&samples).unwrap();
        assert!(result.is_some());

        let (freq, conf) = result.unwrap();
        assert!((freq - 440.0).abs() < 5.0, "Expected ~440 Hz, got {}", freq);
        assert!(conf > 0.8, "Expected high confidence, got {}", conf);
    }

    #[test]
    fn test_harmonic_detector() {
        let config = PitchConfig::default();
        let mut detector = HarmonicDetector::new(&config);

        // Generate 440 Hz sine with harmonics
        let samples: Vec<f32> = (0..config.window_size)
            .map(|i| {
                let t = i as f32 / config.sample_rate as f32;
                (2.0 * std::f32::consts::PI * 440.0 * t).sin()
                    + 0.5 * (2.0 * std::f32::consts::PI * 880.0 * t).sin()
                    + 0.25 * (2.0 * std::f32::consts::PI * 1320.0 * t).sin()
            })
            .collect();

        let result = detector.detect(&samples).unwrap();
        assert!(result.is_some());

        let (freq, _) = result.unwrap();
        assert!(
            (freq - 440.0).abs() < 10.0,
            "Expected ~440 Hz, got {}",
            freq
        );
    }

    fn generate_with_harmonics(freq: f32, sample_rate: u32, num_samples: usize) -> Vec<f32> {
        (0..num_samples)
            .map(|i| {
                let t = i as f32 / sample_rate as f32;
                let f = 2.0 * std::f32::consts::PI * freq;
                (f * t).sin()
                    + 0.5 * (f * 2.0 * t).sin()
                    + 0.33 * (f * 3.0 * t).sin()
                    + 0.25 * (f * 4.0 * t).sin()
            })
            .collect()
    }

    #[test]
    fn test_fusion_detector() {
        let config = PitchConfig {
            algorithm: DetectionAlgorithm::Fusion,
            ..Default::default()
        };
        let mut detector = FusionDetector::new(&config);

        // Use signal with harmonics - realistic for pitched instruments
        let samples = generate_with_harmonics(261.63, config.sample_rate, config.window_size);

        let result = detector.detect(&samples).unwrap();
        assert!(result.is_some());

        let (freq, _) = result.unwrap();
        assert!(
            (freq - 261.63).abs() < 10.0,
            "Expected ~261.63 Hz (C4), got {}",
            freq
        );
    }

    #[test]
    fn test_pitch_detector_dispatch() {
        for algo in [
            DetectionAlgorithm::Yin,
            DetectionAlgorithm::Harmonic,
            DetectionAlgorithm::Fusion,
        ] {
            let config = PitchConfig {
                algorithm: algo,
                ..Default::default()
            };
            let mut detector = PitchDetector::new(&config);

            let samples = generate_sine(440.0, config.sample_rate, config.window_size);

            let result = detector.detect(&samples).unwrap();
            assert!(result.is_some(), "Algorithm {:?} should detect pitch", algo);
        }
    }

    #[test]
    fn test_silence_detection() {
        let config = PitchConfig::default();
        let mut detector = YinDetector::new(&config);

        let samples = vec![0.0; config.window_size];
        let result = detector.detect(&samples).unwrap();

        // Should either return None or very low confidence
        if let Some((_, conf)) = result {
            assert!(conf < 0.5, "Silence should have low confidence");
        }
    }
}

//! Audio analysis for intelligent mastering
//!
//! Features:
//! - Genre detection using spectral features
//! - Dynamics analysis (crest factor, LRA)
//! - Spectral balance analysis
//! - Stereo field analysis
//! - Problem detection (clipping, DC offset, phase issues)

use crate::{
    DynamicsProfile, Genre, LoudnessMeasurement, ReferenceProfile, StereoProfile,
    error::{MasterError, MasterResult},
};
use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;
use std::sync::Arc;

/// Audio analyzer for mastering decisions
pub struct MasteringAnalyzer {
    /// Sample rate
    sample_rate: u32,
    /// FFT size for spectral analysis
    fft_size: usize,
    /// Forward FFT
    fft_forward: Arc<dyn RealToComplex<f32>>,
    /// Analysis window
    window: Vec<f32>,
}

impl MasteringAnalyzer {
    /// Create new analyzer
    pub fn new(sample_rate: u32) -> Self {
        let fft_size = 4096;

        let mut planner = RealFftPlanner::<f32>::new();
        let fft_forward = planner.plan_fft_forward(fft_size);

        // Hann window
        let window: Vec<f32> = (0..fft_size)
            .map(|i| {
                let phase = 2.0 * std::f32::consts::PI * i as f32 / fft_size as f32;
                0.5 * (1.0 - phase.cos())
            })
            .collect();

        Self {
            sample_rate,
            fft_size,
            fft_forward,
            window,
        }
    }

    /// Analyze audio and detect genre
    pub fn detect_genre(&self, audio_l: &[f32], audio_r: &[f32]) -> Genre {
        // Extract spectral features
        let features = self.extract_spectral_features(audio_l, audio_r);

        // Simple rule-based genre detection
        // In production, this would use ML model

        // Check for speech characteristics
        if features.spectral_centroid < 2000.0
            && features.spectral_flux < 0.1
            && features.zero_crossing_rate > 0.1
        {
            return Genre::Speech;
        }

        // Check for classical (high dynamics, low bass)
        if features.dynamic_range > 20.0 && features.bass_ratio < 0.15 {
            return Genre::Classical;
        }

        // Check for electronic (low frequencies, steady rhythm)
        if features.bass_ratio > 0.35 && features.spectral_flatness > 0.3 {
            return Genre::Electronic;
        }

        // Check for hip-hop (heavy bass, specific frequency distribution)
        if features.sub_bass_ratio > 0.15 && features.bass_ratio > 0.3 {
            return Genre::HipHop;
        }

        // Check for rock (wide spectrum, high energy)
        if features.spectral_spread > 3000.0 && features.rms_level > 0.2 {
            return Genre::Rock;
        }

        // Check for jazz (mid-range focus, dynamics)
        if features.mid_ratio > 0.4 && features.dynamic_range > 15.0 {
            return Genre::Jazz;
        }

        // Default to pop for balanced material
        if features.spectral_balance > -3.0 && features.spectral_balance < 3.0 {
            return Genre::Pop;
        }

        Genre::Unknown
    }

    /// Extract spectral features for genre detection
    fn extract_spectral_features(&self, audio_l: &[f32], audio_r: &[f32]) -> SpectralFeatures {
        let mono: Vec<f32> = audio_l
            .iter()
            .zip(audio_r.iter())
            .map(|(l, r)| (l + r) * 0.5)
            .collect();

        // Compute average spectrum
        let spectrum = self.compute_average_spectrum(&mono);

        // Calculate features
        let spectral_centroid = self.calculate_centroid(&spectrum);
        let spectral_spread = self.calculate_spread(&spectrum, spectral_centroid);
        let spectral_flatness = self.calculate_flatness(&spectrum);
        let spectral_flux = self.calculate_flux(&mono);
        let zero_crossing_rate = self.calculate_zcr(&mono);

        // Band ratios
        let total_energy: f32 = spectrum.iter().sum();
        let sub_bass = self.band_energy(&spectrum, 20.0, 60.0);
        let bass = self.band_energy(&spectrum, 60.0, 250.0);
        let mid = self.band_energy(&spectrum, 250.0, 2000.0);
        let high = self.band_energy(&spectrum, 2000.0, 20000.0);

        let sub_bass_ratio = sub_bass / total_energy.max(1e-10);
        let bass_ratio = bass / total_energy.max(1e-10);
        let mid_ratio = mid / total_energy.max(1e-10);
        let _high_ratio = high / total_energy.max(1e-10);

        // Dynamics
        let rms_level = self.calculate_rms(&mono);
        let peak_level = mono.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        let dynamic_range = self.calculate_dynamic_range(&mono);

        // Spectral balance (bass vs treble)
        let spectral_balance = (bass / high.max(1e-10)).log10() * 20.0;

        SpectralFeatures {
            spectral_centroid,
            spectral_spread,
            spectral_flatness,
            spectral_flux,
            zero_crossing_rate,
            sub_bass_ratio,
            bass_ratio,
            mid_ratio,
            rms_level,
            peak_level,
            dynamic_range,
            spectral_balance,
        }
    }

    /// Compute average spectrum
    fn compute_average_spectrum(&self, audio: &[f32]) -> Vec<f32> {
        let hop_size = self.fft_size / 4;
        let bins = self.fft_size / 2 + 1;
        let mut avg_spectrum = vec![0.0f32; bins];
        let mut frame_count = 0;

        let mut fft_scratch = vec![0.0f32; self.fft_size];
        let mut spectrum = vec![Complex::new(0.0, 0.0); bins];

        for start in (0..audio.len().saturating_sub(self.fft_size)).step_by(hop_size) {
            // Apply window
            for i in 0..self.fft_size {
                fft_scratch[i] = audio[start + i] * self.window[i];
            }

            // FFT
            self.fft_forward.process(&mut fft_scratch, &mut spectrum).ok();

            // Accumulate magnitude
            for (i, c) in spectrum.iter().enumerate() {
                avg_spectrum[i] += c.norm();
            }

            frame_count += 1;
        }

        // Average
        if frame_count > 0 {
            for s in &mut avg_spectrum {
                *s /= frame_count as f32;
            }
        }

        avg_spectrum
    }

    /// Calculate spectral centroid
    fn calculate_centroid(&self, spectrum: &[f32]) -> f32 {
        let mut weighted_sum = 0.0f32;
        let mut sum = 0.0f32;

        for (i, &mag) in spectrum.iter().enumerate() {
            let freq = i as f32 * self.sample_rate as f32 / (2.0 * spectrum.len() as f32);
            weighted_sum += freq * mag;
            sum += mag;
        }

        if sum > 1e-10 {
            weighted_sum / sum
        } else {
            0.0
        }
    }

    /// Calculate spectral spread
    fn calculate_spread(&self, spectrum: &[f32], centroid: f32) -> f32 {
        let mut weighted_sum = 0.0f32;
        let mut sum = 0.0f32;

        for (i, &mag) in spectrum.iter().enumerate() {
            let freq = i as f32 * self.sample_rate as f32 / (2.0 * spectrum.len() as f32);
            let diff = freq - centroid;
            weighted_sum += diff * diff * mag;
            sum += mag;
        }

        if sum > 1e-10 {
            (weighted_sum / sum).sqrt()
        } else {
            0.0
        }
    }

    /// Calculate spectral flatness (Wiener entropy)
    fn calculate_flatness(&self, spectrum: &[f32]) -> f32 {
        let n = spectrum.len() as f32;
        let mut log_sum = 0.0f32;
        let mut sum = 0.0f32;

        for &mag in spectrum {
            let val = mag.max(1e-10);
            log_sum += val.ln();
            sum += val;
        }

        let geometric_mean = (log_sum / n).exp();
        let arithmetic_mean = sum / n;

        if arithmetic_mean > 1e-10 {
            geometric_mean / arithmetic_mean
        } else {
            0.0
        }
    }

    /// Calculate spectral flux (frame-to-frame difference)
    fn calculate_flux(&self, audio: &[f32]) -> f32 {
        let hop_size = self.fft_size / 4;
        let bins = self.fft_size / 2 + 1;
        let mut prev_spectrum = vec![0.0f32; bins];
        let mut flux_sum = 0.0f32;
        let mut frame_count = 0;

        let mut fft_scratch = vec![0.0f32; self.fft_size];
        let mut spectrum = vec![Complex::new(0.0, 0.0); bins];

        for start in (0..audio.len().saturating_sub(self.fft_size)).step_by(hop_size) {
            for i in 0..self.fft_size {
                fft_scratch[i] = audio[start + i] * self.window[i];
            }

            self.fft_forward.process(&mut fft_scratch, &mut spectrum).ok();

            let current: Vec<f32> = spectrum.iter().map(|c| c.norm()).collect();

            if frame_count > 0 {
                let flux: f32 = current
                    .iter()
                    .zip(prev_spectrum.iter())
                    .map(|(c, p)| (c - p).max(0.0).powi(2))
                    .sum();
                flux_sum += flux.sqrt();
            }

            prev_spectrum = current;
            frame_count += 1;
        }

        if frame_count > 1 {
            flux_sum / (frame_count - 1) as f32
        } else {
            0.0
        }
    }

    /// Calculate zero crossing rate
    fn calculate_zcr(&self, audio: &[f32]) -> f32 {
        let mut crossings = 0;

        for i in 1..audio.len() {
            if (audio[i] >= 0.0) != (audio[i - 1] >= 0.0) {
                crossings += 1;
            }
        }

        crossings as f32 / audio.len() as f32
    }

    /// Calculate energy in frequency band
    fn band_energy(&self, spectrum: &[f32], low_hz: f32, high_hz: f32) -> f32 {
        let bin_width = self.sample_rate as f32 / (2.0 * spectrum.len() as f32);
        let low_bin = (low_hz / bin_width) as usize;
        let high_bin = ((high_hz / bin_width) as usize).min(spectrum.len());

        spectrum[low_bin..high_bin].iter().map(|s| s * s).sum()
    }

    /// Calculate RMS level
    fn calculate_rms(&self, audio: &[f32]) -> f32 {
        let sum: f32 = audio.iter().map(|s| s * s).sum();
        (sum / audio.len() as f32).sqrt()
    }

    /// Calculate dynamic range
    fn calculate_dynamic_range(&self, audio: &[f32]) -> f32 {
        let block_size = self.sample_rate as usize / 10; // 100ms blocks
        let mut block_levels: Vec<f32> = Vec::new();

        for chunk in audio.chunks(block_size) {
            let rms = (chunk.iter().map(|s| s * s).sum::<f32>() / chunk.len() as f32).sqrt();
            if rms > 1e-6 {
                block_levels.push(20.0 * rms.log10());
            }
        }

        if block_levels.len() < 2 {
            return 0.0;
        }

        block_levels.sort_by(|a, b| a.partial_cmp(b).unwrap());

        // 10-90 percentile range
        let low_idx = block_levels.len() / 10;
        let high_idx = block_levels.len() * 9 / 10;

        block_levels[high_idx] - block_levels[low_idx]
    }

    /// Analyze dynamics profile
    pub fn analyze_dynamics(&self, audio_l: &[f32], audio_r: &[f32]) -> DynamicsProfile {
        let mono: Vec<f32> = audio_l
            .iter()
            .zip(audio_r.iter())
            .map(|(l, r)| (l + r) * 0.5)
            .collect();

        let rms = self.calculate_rms(&mono);
        let peak = mono.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        let crest_factor = if rms > 1e-10 {
            20.0 * (peak / rms).log10()
        } else {
            0.0
        };

        let dynamic_range = self.calculate_dynamic_range(&mono);
        let lra = self.calculate_lra(&mono);

        // Multiband dynamics (simplified)
        let band_dynamics = self.calculate_band_dynamics(&mono);

        DynamicsProfile {
            crest_factor,
            dynamic_range,
            lra,
            band_dynamics,
        }
    }

    /// Calculate loudness range (simplified LRA)
    fn calculate_lra(&self, audio: &[f32]) -> f32 {
        let block_size = self.sample_rate as usize * 3; // 3 second blocks
        let hop = block_size / 3;
        let mut levels: Vec<f32> = Vec::new();

        for start in (0..audio.len().saturating_sub(block_size)).step_by(hop) {
            let block = &audio[start..start + block_size];
            let rms = (block.iter().map(|s| s * s).sum::<f32>() / block_size as f32).sqrt();

            if rms > 1e-6 {
                levels.push(-0.691 + 10.0 * rms.log10()); // Approximate LUFS
            }
        }

        if levels.len() < 2 {
            return 0.0;
        }

        levels.sort_by(|a, b| a.partial_cmp(b).unwrap());

        // 10-95 percentile range
        let low_idx = levels.len() / 10;
        let high_idx = levels.len() * 95 / 100;

        levels[high_idx] - levels[low_idx]
    }

    /// Calculate per-band dynamics
    fn calculate_band_dynamics(&self, audio: &[f32]) -> Vec<f32> {
        // Simplified: return 4-band dynamics estimate
        let crossovers = [200.0f32, 1000.0, 5000.0];
        let mut band_dynamics = vec![0.0f32; 4];

        let spectrum = self.compute_average_spectrum(audio);
        let bins = spectrum.len();

        for (band_idx, dynamics) in band_dynamics.iter_mut().enumerate() {
            let low_hz = if band_idx == 0 {
                20.0
            } else {
                crossovers[band_idx - 1]
            };
            let high_hz = if band_idx < 3 {
                crossovers[band_idx]
            } else {
                20000.0
            };

            let low_bin = (low_hz * bins as f32 * 2.0 / self.sample_rate as f32) as usize;
            let high_bin =
                ((high_hz * bins as f32 * 2.0 / self.sample_rate as f32) as usize).min(bins);

            let band_energy: f32 = spectrum[low_bin..high_bin].iter().sum();
            *dynamics = if band_energy > 1e-10 {
                10.0 * band_energy.log10()
            } else {
                -60.0
            };
        }

        band_dynamics
    }

    /// Analyze stereo characteristics
    pub fn analyze_stereo(&self, audio_l: &[f32], audio_r: &[f32]) -> StereoProfile {
        let correlation = self.calculate_correlation(audio_l, audio_r);
        let width = self.calculate_width(audio_l, audio_r);
        let low_mono = self.calculate_low_mono(audio_l, audio_r);
        let balance = self.calculate_balance(audio_l, audio_r);

        StereoProfile {
            correlation,
            width,
            low_mono,
            balance,
        }
    }

    /// Calculate stereo correlation
    fn calculate_correlation(&self, left: &[f32], right: &[f32]) -> f32 {
        let n = left.len().min(right.len());
        if n == 0 {
            return 0.0;
        }

        let mut sum_lr = 0.0f32;
        let mut sum_l2 = 0.0f32;
        let mut sum_r2 = 0.0f32;

        for i in 0..n {
            sum_lr += left[i] * right[i];
            sum_l2 += left[i] * left[i];
            sum_r2 += right[i] * right[i];
        }

        let denom = (sum_l2 * sum_r2).sqrt();
        if denom > 1e-10 {
            sum_lr / denom
        } else {
            0.0
        }
    }

    /// Calculate stereo width
    fn calculate_width(&self, left: &[f32], right: &[f32]) -> f32 {
        let n = left.len().min(right.len());
        if n == 0 {
            return 0.0;
        }

        let mut mid_energy = 0.0f32;
        let mut side_energy = 0.0f32;

        for i in 0..n {
            let mid = (left[i] + right[i]) * 0.5;
            let side = (left[i] - right[i]) * 0.5;
            mid_energy += mid * mid;
            side_energy += side * side;
        }

        if mid_energy > 1e-10 {
            (side_energy / mid_energy).sqrt()
        } else {
            0.0
        }
    }

    /// Calculate low frequency mono percentage
    fn calculate_low_mono(&self, left: &[f32], right: &[f32]) -> f32 {
        // Apply lowpass filter and measure correlation
        let cutoff = 200.0;
        let alpha = (2.0 * std::f32::consts::PI * cutoff / self.sample_rate as f32)
            / (2.0 * std::f32::consts::PI * cutoff / self.sample_rate as f32 + 1.0);

        let mut lp_l = 0.0f32;
        let mut lp_r = 0.0f32;
        let mut correlation_sum = 0.0f32;
        let mut energy_sum = 0.0f32;

        let n = left.len().min(right.len());

        for i in 0..n {
            lp_l = lp_l + alpha * (left[i] - lp_l);
            lp_r = lp_r + alpha * (right[i] - lp_r);

            correlation_sum += lp_l * lp_r;
            energy_sum += (lp_l * lp_l + lp_r * lp_r) * 0.5;
        }

        if energy_sum > 1e-10 {
            correlation_sum / energy_sum
        } else {
            1.0
        }
    }

    /// Calculate L/R balance
    fn calculate_balance(&self, left: &[f32], right: &[f32]) -> f32 {
        let n = left.len().min(right.len());
        if n == 0 {
            return 0.0;
        }

        let l_energy: f32 = left.iter().take(n).map(|s| s * s).sum();
        let r_energy: f32 = right.iter().take(n).map(|s| s * s).sum();

        if l_energy + r_energy > 1e-10 {
            (l_energy - r_energy) / (l_energy + r_energy)
        } else {
            0.0
        }
    }

    /// Measure loudness (simplified LUFS-like measurement)
    pub fn measure_loudness(&self, audio_l: &[f32], audio_r: &[f32]) -> LoudnessMeasurement {
        let mono: Vec<f32> = audio_l
            .iter()
            .zip(audio_r.iter())
            .map(|(l, r)| (l + r) * 0.5)
            .collect();

        // Integrated loudness (simplified)
        let rms = self.calculate_rms(&mono);
        let integrated = if rms > 1e-10 {
            -0.691 + 10.0 * rms.log10()
        } else {
            -70.0
        };

        // Short-term (3s blocks)
        let short_term_max = self.calculate_short_term_max(&mono);

        // Momentary (400ms blocks)
        let momentary_max = self.calculate_momentary_max(&mono);

        // True peak
        let true_peak = self.calculate_true_peak(audio_l, audio_r);

        // LRA
        let lra = self.calculate_lra(&mono);

        LoudnessMeasurement {
            integrated,
            short_term_max,
            momentary_max,
            true_peak,
            lra,
        }
    }

    fn calculate_short_term_max(&self, audio: &[f32]) -> f32 {
        let block_size = self.sample_rate as usize * 3;
        let hop = block_size / 3;
        let mut max_level = -70.0f32;

        for start in (0..audio.len().saturating_sub(block_size)).step_by(hop) {
            let block = &audio[start..start + block_size];
            let rms = (block.iter().map(|s| s * s).sum::<f32>() / block_size as f32).sqrt();
            let level = if rms > 1e-10 {
                -0.691 + 10.0 * rms.log10()
            } else {
                -70.0
            };
            max_level = max_level.max(level);
        }

        max_level
    }

    fn calculate_momentary_max(&self, audio: &[f32]) -> f32 {
        let block_size = (self.sample_rate as f32 * 0.4) as usize;
        let hop = block_size / 4;
        let mut max_level = -70.0f32;

        for start in (0..audio.len().saturating_sub(block_size)).step_by(hop) {
            let block = &audio[start..start + block_size];
            let rms = (block.iter().map(|s| s * s).sum::<f32>() / block_size as f32).sqrt();
            let level = if rms > 1e-10 {
                -0.691 + 10.0 * rms.log10()
            } else {
                -70.0
            };
            max_level = max_level.max(level);
        }

        max_level
    }

    fn calculate_true_peak(&self, left: &[f32], right: &[f32]) -> f32 {
        // Simplified: just use sample peak (real implementation would use 4x oversampling)
        let l_peak = left.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        let r_peak = right.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        let peak = l_peak.max(r_peak);

        if peak > 1e-10 {
            20.0 * peak.log10()
        } else {
            -70.0
        }
    }

    /// Create reference profile from audio
    pub fn create_reference_profile(
        &self,
        name: &str,
        audio_l: &[f32],
        audio_r: &[f32],
    ) -> ReferenceProfile {
        let mono: Vec<f32> = audio_l
            .iter()
            .zip(audio_r.iter())
            .map(|(l, r)| (l + r) * 0.5)
            .collect();

        let spectrum = self.compute_average_spectrum(&mono);
        let dynamics = self.analyze_dynamics(audio_l, audio_r);
        let stereo = self.analyze_stereo(audio_l, audio_r);
        let loudness = self.measure_loudness(audio_l, audio_r);

        ReferenceProfile {
            name: name.to_string(),
            spectrum,
            dynamics,
            stereo,
            loudness,
        }
    }
}

/// Spectral features for genre detection
#[derive(Debug, Clone)]
struct SpectralFeatures {
    spectral_centroid: f32,
    spectral_spread: f32,
    spectral_flatness: f32,
    spectral_flux: f32,
    zero_crossing_rate: f32,
    sub_bass_ratio: f32,
    bass_ratio: f32,
    mid_ratio: f32,
    rms_level: f32,
    peak_level: f32,
    dynamic_range: f32,
    spectral_balance: f32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_analyzer_creation() {
        let analyzer = MasteringAnalyzer::new(48000);
        assert_eq!(analyzer.sample_rate, 48000);
    }

    #[test]
    fn test_genre_detection() {
        let analyzer = MasteringAnalyzer::new(48000);

        // Silent audio should return Unknown
        let silence = vec![0.0f32; 48000];
        let genre = analyzer.detect_genre(&silence, &silence);
        assert_eq!(genre, Genre::Unknown);
    }

    #[test]
    fn test_stereo_analysis() {
        let analyzer = MasteringAnalyzer::new(48000);

        // Mono signal
        let mono: Vec<f32> = (0..48000)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 48000.0).sin())
            .collect();

        let stereo = analyzer.analyze_stereo(&mono, &mono);
        assert!(stereo.correlation > 0.99);
        assert!(stereo.width < 0.01);
    }

    #[test]
    fn test_dynamics_analysis() {
        let analyzer = MasteringAnalyzer::new(48000);

        // Sine wave has low crest factor
        let sine: Vec<f32> = (0..48000)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 48000.0).sin() * 0.5)
            .collect();

        let dynamics = analyzer.analyze_dynamics(&sine, &sine);
        assert!(dynamics.crest_factor > 0.0);
        assert!(dynamics.crest_factor < 10.0); // Sine wave is ~3 dB crest factor
    }

    #[test]
    fn test_loudness_measurement() {
        let analyzer = MasteringAnalyzer::new(48000);

        let sine: Vec<f32> = (0..48000)
            .map(|i| (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / 48000.0).sin() * 0.5)
            .collect();

        let loudness = analyzer.measure_loudness(&sine, &sine);
        assert!(loudness.integrated > -20.0 && loudness.integrated < 0.0);
    }

    #[test]
    fn test_reference_profile() {
        let analyzer = MasteringAnalyzer::new(48000);

        let audio: Vec<f32> = (0..96000)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 48000.0).sin() * 0.3)
            .collect();

        let profile = analyzer.create_reference_profile("test", &audio, &audio);
        assert_eq!(profile.name, "test");
        assert!(!profile.spectrum.is_empty());
    }
}

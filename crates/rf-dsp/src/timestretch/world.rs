//! # WORLD Vocoder Integration
//!
//! High-quality vocoder for monophonic speech/voice time stretching.
//!
//! ## Components
//!
//! - **Harvest/DIO**: F0 (pitch) estimation
//! - **CheapTrick**: Spectral envelope estimation
//! - **D4C**: Aperiodicity estimation
//!
//! ## References
//!
//! - Morise, M. (2016). "WORLD: a vocoder-based high-quality speech synthesis system"
//! - https://github.com/mmorise/World

use rustfft::{FftPlanner, num_complex::Complex64};
use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// WORLD ANALYSIS
// ═══════════════════════════════════════════════════════════════════════════════

/// WORLD analysis parameters
#[derive(Debug, Clone)]
pub struct WorldAnalysis {
    /// F0 contour (Hz, 0 for unvoiced)
    pub f0: Vec<f64>,
    /// Spectral envelope (time × frequency)
    pub spectral_envelope: Vec<Vec<f64>>,
    /// Aperiodicity (time × frequency bands)
    pub aperiodicity: Vec<Vec<f64>>,
    /// Frame period (seconds)
    pub frame_period: f64,
    /// Sample rate
    pub sample_rate: f64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// WORLD VOCODER
// ═══════════════════════════════════════════════════════════════════════════════

/// WORLD vocoder processor
pub struct WorldVocoder {
    /// Sample rate
    sample_rate: f64,
    /// Frame period (ms)
    frame_period_ms: f64,
    /// FFT size for spectral analysis
    fft_size: usize,
    /// F0 floor (Hz)
    f0_floor: f64,
    /// F0 ceiling (Hz)
    f0_ceiling: f64,
    /// FFT planner
    fft_planner: FftPlanner<f64>,
}

impl WorldVocoder {
    /// Create new WORLD vocoder
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            frame_period_ms: 5.0, // 5ms default
            fft_size: 2048,
            f0_floor: 71.0,    // Typical male low
            f0_ceiling: 800.0, // Typical female high
            fft_planner: FftPlanner::new(),
        }
    }

    /// Analyze audio signal
    pub fn analyze(&mut self, input: &[f64]) -> WorldAnalysis {
        let frame_period = self.frame_period_ms / 1000.0;
        let num_frames = (input.len() as f64 / self.sample_rate / frame_period).ceil() as usize;

        // 1. F0 estimation (simplified DIO)
        let f0 = self.estimate_f0(input, num_frames);

        // 2. Spectral envelope (simplified CheapTrick)
        let spectral_envelope = self.estimate_spectral_envelope(input, &f0);

        // 3. Aperiodicity (simplified D4C)
        let aperiodicity = self.estimate_aperiodicity(input, &f0);

        WorldAnalysis {
            f0,
            spectral_envelope,
            aperiodicity,
            frame_period,
            sample_rate: self.sample_rate,
        }
    }

    /// Synthesize with modified parameters
    pub fn synthesize(&mut self, analysis: &WorldAnalysis) -> Vec<f64> {
        let frame_samples = (analysis.frame_period * analysis.sample_rate) as usize;
        let output_len = analysis.f0.len() * frame_samples;
        let mut output = vec![0.0; output_len];

        let mut phase = 0.0;

        for (frame_idx, &f0) in analysis.f0.iter().enumerate() {
            let frame_start = frame_idx * frame_samples;

            if f0 > 0.0 {
                // Voiced frame
                let envelope = &analysis.spectral_envelope[frame_idx];
                let aperiodicity = &analysis.aperiodicity[frame_idx];

                for i in 0..frame_samples {
                    if frame_start + i >= output_len {
                        break;
                    }

                    // Generate excitation
                    let periodic = self.generate_pulse(phase);
                    let aperiodic = self.generate_noise();

                    // Mix based on average aperiodicity
                    let avg_ap = aperiodicity.iter().sum::<f64>() / aperiodicity.len() as f64;
                    let excitation = periodic * (1.0 - avg_ap) + aperiodic * avg_ap;

                    // Apply spectral envelope (simplified)
                    let filtered =
                        excitation * envelope.iter().sum::<f64>() / envelope.len() as f64;

                    output[frame_start + i] = filtered * 0.1; // Gain control

                    // Advance phase
                    phase += 2.0 * PI * f0 / analysis.sample_rate;
                    if phase > 2.0 * PI {
                        phase -= 2.0 * PI;
                    }
                }
            } else {
                // Unvoiced frame
                for i in 0..frame_samples {
                    if frame_start + i >= output_len {
                        break;
                    }
                    output[frame_start + i] = self.generate_noise() * 0.05;
                }
            }
        }

        output
    }

    /// Process with time stretch and pitch shift
    pub fn process(&mut self, input: &[f64], time_ratio: f64, pitch_ratio: f64) -> Vec<f64> {
        // 1. Analyze
        let analysis = self.analyze(input);

        // 2. Modify parameters
        let modified = self.modify_analysis(&analysis, time_ratio, pitch_ratio);

        // 3. Synthesize
        self.synthesize(&modified)
    }

    /// Modify analysis parameters for time/pitch change
    fn modify_analysis(
        &self,
        analysis: &WorldAnalysis,
        time_ratio: f64,
        pitch_ratio: f64,
    ) -> WorldAnalysis {
        let new_len = (analysis.f0.len() as f64 * time_ratio).round() as usize;

        // Interpolate F0
        let mut new_f0 = vec![0.0; new_len];
        for (i, f) in new_f0.iter_mut().enumerate() {
            let src_pos = i as f64 / time_ratio;
            let src_idx = src_pos.floor() as usize;
            let frac = src_pos - src_pos.floor();

            if src_idx < analysis.f0.len() {
                let f0_low = analysis.f0[src_idx];
                let f0_high = analysis.f0.get(src_idx + 1).copied().unwrap_or(f0_low);

                // Interpolate and apply pitch shift
                let interpolated = f0_low * (1.0 - frac) + f0_high * frac;
                *f = if interpolated > 0.0 {
                    interpolated * pitch_ratio
                } else {
                    0.0
                };
            }
        }

        // Interpolate spectral envelope
        let num_bins = analysis
            .spectral_envelope
            .first()
            .map(|v| v.len())
            .unwrap_or(0);
        let mut new_envelope = vec![vec![0.0; num_bins]; new_len];

        for (i, frame) in new_envelope.iter_mut().enumerate() {
            let src_pos = i as f64 / time_ratio;
            let src_idx = src_pos.floor() as usize;
            let frac = src_pos - src_pos.floor();

            if src_idx < analysis.spectral_envelope.len() {
                for (k, bin) in frame.iter_mut().enumerate() {
                    let low = analysis.spectral_envelope[src_idx]
                        .get(k)
                        .copied()
                        .unwrap_or(0.0);
                    let high = analysis
                        .spectral_envelope
                        .get(src_idx + 1)
                        .and_then(|v| v.get(k))
                        .copied()
                        .unwrap_or(low);
                    *bin = low * (1.0 - frac) + high * frac;
                }
            }
        }

        // Interpolate aperiodicity
        let ap_bins = analysis.aperiodicity.first().map(|v| v.len()).unwrap_or(0);
        let mut new_aperiodicity = vec![vec![0.0; ap_bins]; new_len];

        for (i, frame) in new_aperiodicity.iter_mut().enumerate() {
            let src_pos = i as f64 / time_ratio;
            let src_idx = src_pos.floor() as usize;
            let frac = src_pos - src_pos.floor();

            if src_idx < analysis.aperiodicity.len() {
                for (k, bin) in frame.iter_mut().enumerate() {
                    let low = analysis.aperiodicity[src_idx]
                        .get(k)
                        .copied()
                        .unwrap_or(0.0);
                    let high = analysis
                        .aperiodicity
                        .get(src_idx + 1)
                        .and_then(|v| v.get(k))
                        .copied()
                        .unwrap_or(low);
                    *bin = low * (1.0 - frac) + high * frac;
                }
            }
        }

        WorldAnalysis {
            f0: new_f0,
            spectral_envelope: new_envelope,
            aperiodicity: new_aperiodicity,
            frame_period: analysis.frame_period,
            sample_rate: analysis.sample_rate,
        }
    }

    /// Estimate F0 using autocorrelation (simplified DIO)
    fn estimate_f0(&mut self, input: &[f64], num_frames: usize) -> Vec<f64> {
        let frame_samples = (self.frame_period_ms / 1000.0 * self.sample_rate) as usize;
        let mut f0 = vec![0.0; num_frames];

        let min_period = (self.sample_rate / self.f0_ceiling) as usize;
        let max_period = (self.sample_rate / self.f0_floor) as usize;

        for (frame_idx, f) in f0.iter_mut().enumerate() {
            let start = frame_idx * frame_samples;
            let end = (start + self.fft_size).min(input.len());

            if end <= start {
                continue;
            }

            let frame = &input[start..end];

            // Autocorrelation-based pitch detection
            if let Some(period) = self.find_pitch_period(frame, min_period, max_period) {
                *f = self.sample_rate / period as f64;
            }
        }

        f0
    }

    /// Find pitch period using autocorrelation
    fn find_pitch_period(&self, frame: &[f64], min: usize, max: usize) -> Option<usize> {
        let max = max.min(frame.len() / 2);
        if min >= max {
            return None;
        }

        // Compute autocorrelation
        let mut best_period = 0;
        let mut best_value = 0.0;

        for period in min..max {
            let mut correlation = 0.0;
            let mut energy = 0.0;

            for i in 0..(frame.len() - period) {
                correlation += frame[i] * frame[i + period];
                energy += frame[i] * frame[i];
            }

            if energy > 0.0 {
                let normalized = correlation / energy;
                if normalized > best_value && normalized > 0.3 {
                    best_value = normalized;
                    best_period = period;
                }
            }
        }

        if best_period > 0 {
            Some(best_period)
        } else {
            None
        }
    }

    /// Estimate spectral envelope (simplified CheapTrick)
    fn estimate_spectral_envelope(&mut self, input: &[f64], f0: &[f64]) -> Vec<Vec<f64>> {
        let frame_samples = (self.frame_period_ms / 1000.0 * self.sample_rate) as usize;
        let num_bins = self.fft_size / 2 + 1;

        let mut envelope = Vec::with_capacity(f0.len());

        for (frame_idx, &_f0_val) in f0.iter().enumerate() {
            let start = frame_idx * frame_samples;
            let end = (start + self.fft_size).min(input.len());

            let mut frame_env = vec![0.0; num_bins];

            if end > start {
                // Compute spectrum
                let mut buffer: Vec<Complex64> = vec![Complex64::new(0.0, 0.0); self.fft_size];

                for (i, b) in buffer.iter_mut().enumerate().take(end - start) {
                    let window = 0.5 * (1.0 - (2.0 * PI * i as f64 / self.fft_size as f64).cos());
                    *b = Complex64::new(input[start + i] * window, 0.0);
                }

                let fft = self.fft_planner.plan_fft_forward(self.fft_size);
                fft.process(&mut buffer);

                // Take magnitude as envelope (simplified)
                for (k, env) in frame_env.iter_mut().enumerate() {
                    *env = buffer[k].norm();
                }
            }

            envelope.push(frame_env);
        }

        envelope
    }

    /// Estimate aperiodicity (simplified D4C)
    fn estimate_aperiodicity(&self, _input: &[f64], f0: &[f64]) -> Vec<Vec<f64>> {
        // Simplified: use fixed aperiodicity based on voicing
        // Real D4C is much more complex
        let num_bands = 5; // Simplified band-based aperiodicity

        f0.iter()
            .map(|&f| {
                if f > 0.0 {
                    // Voiced: mostly periodic
                    vec![0.1; num_bands]
                } else {
                    // Unvoiced: fully aperiodic
                    vec![1.0; num_bands]
                }
            })
            .collect()
    }

    /// Generate pulse for voiced excitation
    fn generate_pulse(&self, phase: f64) -> f64 {
        // Simple impulse train approximation
        if phase < 0.1 { 1.0 - phase * 10.0 } else { 0.0 }
    }

    /// Generate white noise for aperiodic excitation
    fn generate_noise(&self) -> f64 {
        // Simple pseudo-random noise
        use std::time::{SystemTime, UNIX_EPOCH};
        let t = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        ((t % 65536) as f64 / 32768.0) - 1.0
    }

    /// Reset vocoder state
    pub fn reset(&mut self) {
        // Nothing stateful to reset in basic implementation
    }

    /// Set F0 range
    pub fn set_f0_range(&mut self, floor: f64, ceiling: f64) {
        self.f0_floor = floor.max(20.0);
        self.f0_ceiling = ceiling.min(2000.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_world_creation() {
        let vocoder = WorldVocoder::new(44100.0);
        assert!((vocoder.sample_rate - 44100.0).abs() < 1e-6);
    }

    #[test]
    fn test_world_analyze() {
        let mut vocoder = WorldVocoder::new(44100.0);

        // Generate test signal (voiced speech-like)
        let duration = 0.1; // 100ms
        let samples = (44100.0 * duration) as usize;
        let f0 = 150.0; // Hz

        let signal: Vec<f64> = (0..samples)
            .map(|i| {
                let t = i as f64 / 44100.0;
                // Simple pulse train + formants
                let pulse = if (t * f0).fract() < 0.1 { 1.0 } else { 0.0 };
                pulse * (2.0 * PI * 500.0 * t).sin() * 0.5
            })
            .collect();

        let analysis = vocoder.analyze(&signal);

        assert!(!analysis.f0.is_empty());
        assert!(!analysis.spectral_envelope.is_empty());
        assert!(!analysis.aperiodicity.is_empty());
    }

    #[test]
    fn test_world_process() {
        let mut vocoder = WorldVocoder::new(44100.0);

        let duration = 0.1;
        let samples = (44100.0 * duration) as usize;
        let signal: Vec<f64> = (0..samples)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        let output = vocoder.process(&signal, 1.0, 1.0);
        assert!(!output.is_empty());
    }
}

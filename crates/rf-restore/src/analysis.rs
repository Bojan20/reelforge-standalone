//! Audio analysis for restoration detection

use crate::error::RestoreResult;
use crate::AnalysisResult;
use num_complex::Complex32;
use realfft::{RealFftPlanner, RealToComplex};
use std::sync::Arc;

/// Audio analyzer for restoration needs assessment
pub struct RestoreAnalyzer {
    /// Sample rate
    sample_rate: u32,
    /// FFT size
    fft_size: usize,
    /// FFT planner
    fft: Arc<dyn RealToComplex<f32>>,
    /// Analysis window
    window: Vec<f32>,
}

impl RestoreAnalyzer {
    /// Create new analyzer
    pub fn new(sample_rate: u32) -> Self {
        let fft_size = 4096;
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        let window: Vec<f32> = (0..fft_size)
            .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / fft_size as f32).cos()))
            .collect();

        Self {
            sample_rate,
            fft_size,
            fft,
            window,
        }
    }

    /// Analyze audio for restoration needs
    pub fn analyze(&self, audio: &[f32]) -> RestoreResult<AnalysisResult> {
        let mut result = AnalysisResult::default();

        // Clipping detection
        result.clipping_percent = self.detect_clipping(audio);

        // Click detection
        result.clicks_per_second = self.detect_clicks(audio);

        // Hum detection
        if let Some((freq, level)) = self.detect_hum(audio) {
            result.hum_frequency = Some(freq);
            result.hum_level_db = level;
        }

        // Noise floor estimation
        result.noise_floor_db = self.estimate_noise_floor(audio);

        // Reverb estimation
        result.reverb_tail_seconds = self.estimate_reverb_tail(audio);

        // Calculate quality score
        result.quality_score = self.calculate_quality_score(&result);

        // Generate suggestions
        result.suggestions = self.generate_suggestions(&result);

        Ok(result)
    }

    /// Detect clipping percentage
    fn detect_clipping(&self, audio: &[f32]) -> f32 {
        let threshold = 0.99;
        let clipped = audio.iter().filter(|&&s| s.abs() >= threshold).count();
        (clipped as f32 / audio.len() as f32) * 100.0
    }

    /// Detect clicks per second
    fn detect_clicks(&self, audio: &[f32]) -> f32 {
        let mut click_count = 0;
        let threshold = 0.3; // Derivative threshold

        let duration_seconds = audio.len() as f32 / self.sample_rate as f32;

        for i in 1..audio.len() - 1 {
            let derivative = (audio[i] - audio[i - 1]).abs();
            let second_derivative = (audio[i + 1] - 2.0 * audio[i] + audio[i - 1]).abs();

            // Click: large derivative + large second derivative
            if derivative > threshold && second_derivative > threshold * 2.0 {
                click_count += 1;
            }
        }

        click_count as f32 / duration_seconds.max(1.0)
    }

    /// Detect hum frequency and level
    fn detect_hum(&self, audio: &[f32]) -> Option<(f32, f32)> {
        // Look for 50Hz and 60Hz + harmonics
        let candidates = [50.0, 60.0, 100.0, 120.0, 150.0, 180.0];

        let mut spectrum = vec![Complex32::new(0.0, 0.0); self.fft_size / 2 + 1];
        let mut input = vec![0.0f32; self.fft_size];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft.get_scratch_len()];

        // Average multiple frames
        let mut avg_spectrum = vec![0.0f32; self.fft_size / 2 + 1];
        let hop = self.fft_size / 2;
        let mut frame_count = 0;

        for start in (0..audio.len().saturating_sub(self.fft_size)).step_by(hop) {
            // Window
            for (i, w) in self.window.iter().enumerate() {
                input[i] = audio[start + i] * w;
            }

            // FFT
            self.fft
                .process_with_scratch(&mut input, &mut spectrum, &mut scratch)
                .ok()?;

            // Accumulate magnitude
            for (i, c) in spectrum.iter().enumerate() {
                avg_spectrum[i] += c.norm();
            }
            frame_count += 1;
        }

        if frame_count == 0 {
            return None;
        }

        // Average
        for s in &mut avg_spectrum {
            *s /= frame_count as f32;
        }

        // Find strongest candidate
        let bin_width = self.sample_rate as f32 / self.fft_size as f32;
        let mut max_level = -120.0f32;
        let mut max_freq = 0.0f32;

        for &freq in &candidates {
            let bin = (freq / bin_width).round() as usize;
            if bin < avg_spectrum.len() {
                let level = 20.0 * (avg_spectrum[bin] + 1e-10).log10();
                if level > max_level {
                    max_level = level;
                    max_freq = freq;
                }
            }
        }

        // Only report if above threshold
        if max_level > -60.0 {
            Some((max_freq, max_level))
        } else {
            None
        }
    }

    /// Estimate noise floor
    fn estimate_noise_floor(&self, audio: &[f32]) -> f32 {
        // Find quiet sections
        let block_size = 1024;
        let mut min_rms = f32::MAX;

        for chunk in audio.chunks(block_size) {
            let rms = (chunk.iter().map(|s| s * s).sum::<f32>() / chunk.len() as f32).sqrt();
            if rms > 1e-10 {
                min_rms = min_rms.min(rms);
            }
        }

        20.0 * (min_rms + 1e-10).log10()
    }

    /// Estimate reverb tail length
    fn estimate_reverb_tail(&self, audio: &[f32]) -> f32 {
        // Simple decay analysis
        let block_size = self.sample_rate as usize / 10; // 100ms blocks

        let envelope: Vec<f32> = audio
            .chunks(block_size)
            .map(|chunk| chunk.iter().map(|s| s.abs()).sum::<f32>() / chunk.len() as f32)
            .collect();

        // Find peak and measure decay
        let max_idx = envelope
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .map(|(i, _)| i)
            .unwrap_or(0);

        let peak = envelope[max_idx];
        if peak < 1e-6 {
            return 0.0;
        }

        // Find -60dB point
        let threshold = peak * 0.001; // -60dB
        let mut decay_end = max_idx;

        for i in max_idx..envelope.len() {
            if envelope[i] < threshold {
                decay_end = i;
                break;
            }
            decay_end = i;
        }

        let samples = (decay_end - max_idx) * block_size;
        samples as f32 / self.sample_rate as f32
    }

    /// Calculate overall quality score
    fn calculate_quality_score(&self, result: &AnalysisResult) -> f32 {
        let mut score = 100.0;

        // Clipping penalty
        score -= result.clipping_percent * 5.0;

        // Click penalty
        score -= (result.clicks_per_second * 2.0).min(20.0);

        // Hum penalty
        if result.hum_frequency.is_some() {
            let hum_penalty = (result.hum_level_db + 60.0).max(0.0) / 3.0;
            score -= hum_penalty;
        }

        // Noise penalty
        let noise_penalty = (result.noise_floor_db + 60.0).max(0.0) / 3.0;
        score -= noise_penalty;

        score.clamp(0.0, 100.0)
    }

    /// Generate restoration suggestions
    fn generate_suggestions(&self, result: &AnalysisResult) -> Vec<String> {
        let mut suggestions = Vec::new();

        if result.clipping_percent > 0.1 {
            suggestions.push(format!(
                "Declipping recommended: {:.1}% samples clipped",
                result.clipping_percent
            ));
        }

        if result.clicks_per_second > 5.0 {
            suggestions.push(format!(
                "Declick recommended: {:.0} clicks/second detected",
                result.clicks_per_second
            ));
        }

        if let Some(freq) = result.hum_frequency {
            if result.hum_level_db > -50.0 {
                suggestions.push(format!(
                    "Dehum recommended: {:.0} Hz at {:.1} dB",
                    freq, result.hum_level_db
                ));
            }
        }

        if result.noise_floor_db > -50.0 {
            suggestions.push(format!(
                "Denoise recommended: noise floor at {:.1} dB",
                result.noise_floor_db
            ));
        }

        if result.reverb_tail_seconds > 1.0 {
            suggestions.push(format!(
                "Dereverb may help: {:.1}s reverb tail detected",
                result.reverb_tail_seconds
            ));
        }

        suggestions
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_analyzer_creation() {
        let analyzer = RestoreAnalyzer::new(48000);
        assert_eq!(analyzer.sample_rate, 48000);
    }

    #[test]
    fn test_clipping_detection() {
        let analyzer = RestoreAnalyzer::new(48000);

        // Clean signal
        let clean = vec![0.5f32; 1000];
        let result = analyzer.analyze(&clean).unwrap();
        assert_eq!(result.clipping_percent, 0.0);

        // Clipped signal
        let clipped: Vec<f32> = (0..1000)
            .map(|i| {
                let s = (i as f32 * 0.1).sin() * 2.0;
                s.clamp(-1.0, 1.0)
            })
            .collect();
        let result = analyzer.analyze(&clipped).unwrap();
        assert!(result.clipping_percent > 0.0);
    }
}

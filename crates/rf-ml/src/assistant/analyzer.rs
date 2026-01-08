//! Audio analyzer for the assistant

use std::path::Path;

use num_complex::Complex32;
use realfft::{RealFftPlanner, RealToComplex};
use std::sync::Arc;

use super::classifier::{Genre, GenreClassifier};
use super::config::AssistantConfig;
use super::suggestions::{Suggestion, SuggestionGenerator};
use super::{
    AnalysisResult, AudioAssistantTrait, ComparisonResult, DynamicsAnalysis, LoudnessAnalysis,
    SpectralAnalysis, StereoAnalysis,
};
use crate::error::{MlError, MlResult};

/// Audio analyzer
pub struct AudioAnalyzer {
    /// Configuration
    config: AssistantConfig,

    /// Genre classifier (optional)
    genre_classifier: Option<GenreClassifier>,

    /// FFT for spectral analysis
    fft: Arc<dyn RealToComplex<f32>>,

    /// Suggestion generator
    suggestion_gen: SuggestionGenerator,

    /// FFT size
    fft_size: usize,

    /// Window function
    window: Vec<f32>,
}

impl AudioAnalyzer {
    /// Create new analyzer with optional model
    pub fn new(config: AssistantConfig) -> Self {
        let fft_size = 4096;
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        let window: Vec<f32> = (0..fft_size)
            .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / fft_size as f32).cos()))
            .collect();

        let suggestion_gen =
            SuggestionGenerator::new().with_target_loudness(config.target_loudness_lufs);

        Self {
            config,
            genre_classifier: None,
            fft,
            suggestion_gen,
            fft_size,
            window,
        }
    }

    /// Create with genre classifier model
    pub fn with_genre_model<P: AsRef<Path>>(mut self, model_path: P) -> MlResult<Self> {
        self.genre_classifier = Some(GenreClassifier::new(model_path, self.config.use_gpu)?);
        Ok(self)
    }

    /// Analyze loudness
    fn analyze_loudness(
        &self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> LoudnessAnalysis {
        // Convert to mono for analysis
        let mono: Vec<f32> = if channels == 2 {
            audio
                .chunks(2)
                .map(|c| (c[0] + c.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect()
        } else {
            audio.to_vec()
        };

        // Calculate RMS and peak
        let rms = (mono.iter().map(|&s| s * s).sum::<f32>() / mono.len() as f32).sqrt();
        let peak = mono.iter().map(|s| s.abs()).fold(0.0f32, f32::max);

        // Convert to dB
        let rms_db = 20.0 * rms.max(1e-10).log10();
        let peak_db = 20.0 * peak.max(1e-10).log10();

        // Approximate LUFS (simplified - real implementation uses K-weighting)
        let integrated_lufs = rms_db - 0.691; // Simplified approximation

        // Calculate loudness range (simplified)
        let block_size = (sample_rate as usize * 3) / 10; // 300ms blocks
        let mut block_loudness: Vec<f32> = Vec::new();

        for chunk in mono.chunks(block_size) {
            let block_rms = (chunk.iter().map(|&s| s * s).sum::<f32>() / chunk.len() as f32).sqrt();
            if block_rms > 1e-10 {
                block_loudness.push(20.0 * block_rms.log10() - 0.691);
            }
        }

        block_loudness.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let loudness_range = if block_loudness.len() >= 4 {
            let low_idx = block_loudness.len() / 10;
            let high_idx = block_loudness.len() * 9 / 10;
            block_loudness[high_idx] - block_loudness[low_idx]
        } else {
            0.0
        };

        // True peak approximation (simplified - real would use oversampling)
        let true_peak_db = peak_db + 0.5; // Approximate headroom

        LoudnessAnalysis {
            integrated_lufs,
            short_term_lufs: integrated_lufs, // Simplified
            momentary_lufs: integrated_lufs,
            loudness_range,
            true_peak_db,
            target_deviation: integrated_lufs - self.config.target_loudness_lufs,
        }
    }

    /// Analyze spectral content
    fn analyze_spectral(
        &self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> SpectralAnalysis {
        let mono: Vec<f32> = if channels == 2 {
            audio
                .chunks(2)
                .map(|c| (c[0] + c.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect()
        } else {
            audio.to_vec()
        };

        // Compute average spectrum
        let hop_size = self.fft_size / 2;
        let num_frames = (mono.len() - self.fft_size) / hop_size + 1;
        let n_bins = self.fft_size / 2 + 1;

        if num_frames == 0 {
            return SpectralAnalysis::default();
        }

        let mut avg_magnitude = vec![0.0f64; n_bins];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft.get_scratch_len()];

        for frame_idx in 0..num_frames {
            let start = frame_idx * hop_size;

            let mut windowed: Vec<f32> = mono[start..start + self.fft_size]
                .iter()
                .zip(self.window.iter())
                .map(|(&s, &w)| s * w)
                .collect();

            let mut spectrum = vec![Complex32::new(0.0, 0.0); n_bins];
            if self
                .fft
                .process_with_scratch(&mut windowed, &mut spectrum, &mut scratch)
                .is_ok()
            {
                for (i, &c) in spectrum.iter().enumerate() {
                    avg_magnitude[i] += c.norm() as f64;
                }
            }
        }

        for m in &mut avg_magnitude {
            *m /= num_frames as f64;
        }

        let freq_resolution = sample_rate as f32 / self.fft_size as f32;

        // Compute spectral centroid
        let mut weighted_sum = 0.0f64;
        let mut magnitude_sum = 0.0f64;
        for (i, &m) in avg_magnitude.iter().enumerate() {
            let freq = i as f64 * freq_resolution as f64;
            weighted_sum += freq * m;
            magnitude_sum += m;
        }
        let centroid_hz = if magnitude_sum > 0.0 {
            (weighted_sum / magnitude_sum) as f32
        } else {
            0.0
        };

        // Compute spectral spread
        let mut spread_sum = 0.0f64;
        for (i, &m) in avg_magnitude.iter().enumerate() {
            let freq = i as f64 * freq_resolution as f64;
            spread_sum += (freq - centroid_hz as f64).powi(2) * m;
        }
        let spread_hz = if magnitude_sum > 0.0 {
            (spread_sum / magnitude_sum).sqrt() as f32
        } else {
            0.0
        };

        // Compute frequency band ratios
        let low_bin = (250.0 / freq_resolution) as usize;
        let high_bin = (4000.0 / freq_resolution) as usize;

        let total: f64 = avg_magnitude.iter().sum();
        let low_energy: f64 = avg_magnitude[..low_bin.min(n_bins)].iter().sum();
        let high_energy: f64 = avg_magnitude[high_bin.min(n_bins)..].iter().sum();
        let mid_energy = total - low_energy - high_energy;

        let low_ratio = if total > 0.0 {
            (low_energy / total) as f32
        } else {
            0.0
        };
        let mid_ratio = if total > 0.0 {
            (mid_energy / total) as f32
        } else {
            0.0
        };
        let high_ratio = if total > 0.0 {
            (high_energy / total) as f32
        } else {
            0.0
        };

        // Spectral flatness (geometric mean / arithmetic mean)
        let log_sum: f64 = avg_magnitude.iter().map(|&m| (m + 1e-10).ln()).sum();
        let geometric_mean = (log_sum / n_bins as f64).exp();
        let arithmetic_mean = total / n_bins as f64;
        let flatness = if arithmetic_mean > 0.0 {
            (geometric_mean / arithmetic_mean) as f32
        } else {
            0.0
        };

        // Rolloff (95% energy)
        let mut cumulative = 0.0f64;
        let threshold = total * 0.95;
        let mut rolloff_hz = sample_rate as f32 / 2.0;
        for (i, &m) in avg_magnitude.iter().enumerate() {
            cumulative += m;
            if cumulative >= threshold {
                rolloff_hz = i as f32 * freq_resolution;
                break;
            }
        }

        // Perceived brightness (-1 to 1)
        let brightness = (centroid_hz / 3000.0 - 1.0).clamp(-1.0, 1.0);

        SpectralAnalysis {
            centroid_hz,
            spread_hz,
            flatness,
            rolloff_hz,
            low_ratio,
            mid_ratio,
            high_ratio,
            brightness,
        }
    }

    /// Analyze dynamics
    fn analyze_dynamics(
        &self,
        audio: &[f32],
        channels: usize,
        _sample_rate: u32,
    ) -> DynamicsAnalysis {
        let mono: Vec<f32> = if channels == 2 {
            audio
                .chunks(2)
                .map(|c| (c[0] + c.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect()
        } else {
            audio.to_vec()
        };

        let rms = (mono.iter().map(|&s| s * s).sum::<f32>() / mono.len() as f32).sqrt();
        let peak = mono.iter().map(|s| s.abs()).fold(0.0f32, f32::max);

        let rms_db = 20.0 * rms.max(1e-10).log10();
        let peak_db = 20.0 * peak.max(1e-10).log10();
        let crest_factor_db = peak_db - rms_db;

        // Dynamic range (simplified)
        let block_size = 4096;
        let mut block_rms: Vec<f32> = Vec::new();

        for chunk in mono.chunks(block_size) {
            let r = (chunk.iter().map(|&s| s * s).sum::<f32>() / chunk.len() as f32).sqrt();
            if r > 1e-10 {
                block_rms.push(20.0 * r.log10());
            }
        }

        block_rms.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let dynamic_range_db = if block_rms.len() >= 4 {
            let low = block_rms[block_rms.len() / 10];
            let high = block_rms[block_rms.len() * 9 / 10];
            high - low
        } else {
            0.0
        };

        // Compression estimate (lower crest = more compressed)
        let compression_estimate = 1.0 - (crest_factor_db / 20.0).clamp(0.0, 1.0);

        // Transient sharpness (simplified)
        let mut max_slope = 0.0f32;
        for w in mono.windows(2) {
            let slope = (w[1] - w[0]).abs();
            max_slope = max_slope.max(slope);
        }
        let transient_sharpness = (max_slope / 0.5).clamp(0.0, 1.0);

        DynamicsAnalysis {
            crest_factor_db,
            dynamic_range_db,
            rms_db,
            peak_db,
            compression_estimate,
            transient_sharpness,
        }
    }

    /// Analyze stereo image
    fn analyze_stereo(&self, audio: &[f32], channels: usize, _sample_rate: u32) -> StereoAnalysis {
        if channels != 2 {
            return StereoAnalysis {
                width: 0.0,
                balance: 0.0,
                correlation: 1.0,
                mid_side_ratio: 0.0,
                phase_issues: false,
            };
        }

        let mut left_power = 0.0f64;
        let mut right_power = 0.0f64;
        let mut correlation_sum = 0.0f64;
        let mut mid_power = 0.0f64;
        let mut side_power = 0.0f64;

        for chunk in audio.chunks(2) {
            let left = chunk[0] as f64;
            let right = chunk.get(1).copied().unwrap_or(0.0) as f64;

            left_power += left * left;
            right_power += right * right;
            correlation_sum += left * right;

            let mid = (left + right) / 2.0;
            let side = (left - right) / 2.0;
            mid_power += mid * mid;
            side_power += side * side;
        }

        let num_samples = audio.len() as f64 / 2.0;
        left_power /= num_samples;
        right_power /= num_samples;
        correlation_sum /= num_samples;
        mid_power /= num_samples;
        side_power /= num_samples;

        // Correlation
        let denom = (left_power * right_power).sqrt();
        let correlation = if denom > 1e-10 {
            (correlation_sum / denom) as f32
        } else {
            1.0
        };

        // Balance
        let total_power = left_power + right_power;
        let balance = if total_power > 1e-10 {
            ((right_power - left_power) / total_power) as f32
        } else {
            0.0
        };

        // Width (based on side/mid ratio)
        let total_ms = mid_power + side_power;
        let mid_side_ratio = if total_ms > 1e-10 {
            (side_power / total_ms) as f32
        } else {
            0.0
        };
        let width = mid_side_ratio.sqrt();

        // Phase issues
        let phase_issues = correlation < 0.0;

        StereoAnalysis {
            width,
            balance,
            correlation,
            mid_side_ratio,
            phase_issues,
        }
    }

    /// Generate all suggestions
    fn generate_suggestions(
        &self,
        loudness: &LoudnessAnalysis,
        spectral: &SpectralAnalysis,
        stereo: &StereoAnalysis,
    ) -> Vec<Suggestion> {
        let mut suggestions = Vec::new();

        // Loudness suggestions
        suggestions.extend(self.suggestion_gen.from_loudness(
            loudness.integrated_lufs,
            loudness.true_peak_db,
            loudness.loudness_range,
        ));

        // Spectral suggestions
        suggestions.extend(self.suggestion_gen.from_spectral(
            spectral.low_ratio,
            spectral.mid_ratio,
            spectral.high_ratio,
            spectral.centroid_hz,
        ));

        // Stereo suggestions
        suggestions.extend(self.suggestion_gen.from_stereo(
            stereo.width,
            stereo.correlation,
            stereo.balance,
        ));

        // Sort by priority
        suggestions.sort_by(|a, b| b.priority.cmp(&a.priority));

        // Filter by confidence
        suggestions.retain(|s| s.confidence >= self.config.min_suggestion_confidence);

        suggestions
    }
}

impl AudioAssistantTrait for AudioAnalyzer {
    fn analyze(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<AnalysisResult> {
        let loudness = self.analyze_loudness(audio, channels, sample_rate);
        let spectral = self.analyze_spectral(audio, channels, sample_rate);
        let dynamics = self.analyze_dynamics(audio, channels, sample_rate);
        let stereo = self.analyze_stereo(audio, channels, sample_rate);

        // Genre classification
        let genres = if self.config.classify_genre {
            if let Some(ref mut classifier) = self.genre_classifier {
                classifier
                    .classify(audio, channels, sample_rate)
                    .unwrap_or_default()
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };

        // Mood classification
        let moods = if self.config.classify_mood {
            if let Some(ref mut classifier) = self.genre_classifier {
                classifier
                    .classify_mood(audio, channels, sample_rate)
                    .unwrap_or_default()
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };

        // Generate suggestions
        let suggestions = self.generate_suggestions(&loudness, &spectral, &stereo);

        // Calculate overall quality score
        let quality_score = self.calculate_quality_score(&loudness, &spectral, &dynamics, &stereo);

        Ok(AnalysisResult {
            genres,
            moods,
            tempo_bpm: None, // TODO: Implement tempo detection
            key: None,       // TODO: Implement key detection
            loudness,
            spectral,
            dynamics,
            stereo,
            suggestions,
            quality_score,
        })
    }

    fn classify_genre(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<Vec<(Genre, f32)>> {
        if let Some(ref mut classifier) = self.genre_classifier {
            classifier.classify(audio, channels, sample_rate)
        } else {
            Err(MlError::ModelNotFound {
                path: "genre_classifier".into(),
            })
        }
    }

    fn suggest(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<Vec<Suggestion>> {
        let loudness = self.analyze_loudness(audio, channels, sample_rate);
        let spectral = self.analyze_spectral(audio, channels, sample_rate);
        let stereo = self.analyze_stereo(audio, channels, sample_rate);

        Ok(self.generate_suggestions(&loudness, &spectral, &stereo))
    }

    fn compare_with_reference(
        &mut self,
        audio: &[f32],
        reference: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<ComparisonResult> {
        let target_loudness = self.analyze_loudness(audio, channels, sample_rate);
        let target_spectral = self.analyze_spectral(audio, channels, sample_rate);
        let target_stereo = self.analyze_stereo(audio, channels, sample_rate);

        let ref_loudness = self.analyze_loudness(reference, channels, sample_rate);
        let ref_spectral = self.analyze_spectral(reference, channels, sample_rate);
        let ref_stereo = self.analyze_stereo(reference, channels, sample_rate);

        // Calculate differences
        let loudness_diff = target_loudness.integrated_lufs - ref_loudness.integrated_lufs;

        // Spectral similarity (simplified)
        let spectral_similarity = 1.0
            - ((target_spectral.centroid_hz - ref_spectral.centroid_hz).abs() / 5000.0)
                .clamp(0.0, 1.0);

        // Dynamic similarity
        let dynamic_similarity = 1.0
            - ((target_loudness.loudness_range - ref_loudness.loudness_range).abs() / 20.0)
                .clamp(0.0, 1.0);

        // Stereo similarity
        let stereo_similarity = 1.0
            - ((target_stereo.width - ref_stereo.width).abs()
                + (target_stereo.correlation - ref_stereo.correlation).abs())
                / 2.0;

        // Overall similarity
        let similarity = (spectral_similarity + dynamic_similarity + stereo_similarity) / 3.0;

        // Generate suggestions to match
        let mut suggestions = Vec::new();

        if loudness_diff.abs() > 1.0 {
            suggestions.push(Suggestion::new(
                super::suggestions::SuggestionType::Level,
                super::suggestions::SuggestionPriority::High,
                format!("Adjust level by {:.1} dB", -loudness_diff),
                format!(
                    "Target is {:.1} LUFS, reference is {:.1} LUFS",
                    target_loudness.integrated_lufs, ref_loudness.integrated_lufs
                ),
            ));
        }

        Ok(ComparisonResult {
            similarity,
            loudness_diff_db: loudness_diff,
            spectral_similarity,
            dynamic_similarity,
            stereo_similarity,
            suggestions,
        })
    }

    fn reset(&mut self) {
        // Nothing to reset currently
    }
}

impl AudioAnalyzer {
    fn calculate_quality_score(
        &self,
        loudness: &LoudnessAnalysis,
        spectral: &SpectralAnalysis,
        dynamics: &DynamicsAnalysis,
        stereo: &StereoAnalysis,
    ) -> f32 {
        let mut score = 1.0f32;

        // Penalize for being far from target loudness
        score -= (loudness.target_deviation.abs() / 10.0).min(0.3);

        // Penalize for clipping
        if loudness.true_peak_db > -0.5 {
            score -= 0.2;
        }

        // Penalize for phase issues
        if stereo.phase_issues {
            score -= 0.3;
        }

        // Penalize for extreme frequency balance
        if spectral.low_ratio > 0.5 || spectral.high_ratio > 0.4 {
            score -= 0.1;
        }

        // Penalize for very low dynamic range
        if dynamics.crest_factor_db < 6.0 {
            score -= 0.1;
        }

        score.clamp(0.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_analyzer_creation() {
        let config = AssistantConfig::default();
        let analyzer = AudioAnalyzer::new(config);
        assert_eq!(analyzer.fft_size, 4096);
    }

    #[test]
    fn test_loudness_analysis() {
        let config = AssistantConfig::default();
        let analyzer = AudioAnalyzer::new(config);

        // Silent audio
        let audio = vec![0.0f32; 48000];
        let loudness = analyzer.analyze_loudness(&audio, 1, 48000);
        assert!(loudness.integrated_lufs < -50.0);

        // Loud audio
        let audio: Vec<f32> = (0..48000).map(|i| (i as f32 * 0.1).sin() * 0.5).collect();
        let loudness = analyzer.analyze_loudness(&audio, 1, 48000);
        assert!(loudness.integrated_lufs > -30.0);
    }
}

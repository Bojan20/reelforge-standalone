//! Reference track matching
//!
//! Analyze and match spectral/dynamic characteristics of reference tracks

use crate::analysis::MasteringAnalyzer;
use crate::error::{MasterError, MasterResult};
use crate::{DynamicsProfile, LoudnessMeasurement, ReferenceProfile, StereoProfile};

/// Reference matcher for comparing and matching tracks
pub struct ReferenceMatcher {
    /// Analyzer
    analyzer: MasteringAnalyzer,
    /// Reference profile
    reference: Option<ReferenceProfile>,
    /// Match settings
    settings: MatchSettings,
}

/// Settings for reference matching
#[derive(Debug, Clone)]
pub struct MatchSettings {
    /// Match spectral balance (0-1)
    pub spectral_match: f32,
    /// Match dynamics (0-1)
    pub dynamics_match: f32,
    /// Match stereo width (0-1)
    pub stereo_match: f32,
    /// Match loudness (0-1)
    pub loudness_match: f32,
    /// Smoothing for spectral match
    pub spectral_smoothing: f32,
}

impl Default for MatchSettings {
    fn default() -> Self {
        Self {
            spectral_match: 0.5,
            dynamics_match: 0.3,
            stereo_match: 0.2,
            loudness_match: 1.0,
            spectral_smoothing: 0.5,
        }
    }
}

/// Match result with recommendations
#[derive(Debug, Clone)]
pub struct MatchResult {
    /// Spectral difference (dB RMS)
    pub spectral_diff_db: f32,
    /// Dynamics difference
    pub dynamics_diff: f32,
    /// Stereo difference
    pub stereo_diff: f32,
    /// Loudness difference (LUFS)
    pub loudness_diff: f32,
    /// Recommended EQ curve
    pub eq_curve: Vec<f32>,
    /// Recommended compression settings
    pub compression: CompressionRecommendation,
    /// Recommended stereo adjustment
    pub stereo: StereoRecommendation,
    /// Overall match score (0-100)
    pub match_score: f32,
}

/// Compression recommendation
#[derive(Debug, Clone)]
pub struct CompressionRecommendation {
    /// Threshold adjustment (dB)
    pub threshold_adjust: f32,
    /// Ratio adjustment
    pub ratio_adjust: f32,
    /// Attack adjustment (ms)
    pub attack_adjust: f32,
    /// Release adjustment (ms)
    pub release_adjust: f32,
}

/// Stereo recommendation
#[derive(Debug, Clone)]
pub struct StereoRecommendation {
    /// Width adjustment
    pub width_adjust: f32,
    /// Balance adjustment
    pub balance_adjust: f32,
    /// Low mono frequency
    pub low_mono_freq: f32,
}

impl ReferenceMatcher {
    /// Create new reference matcher
    pub fn new(sample_rate: u32) -> Self {
        Self {
            analyzer: MasteringAnalyzer::new(sample_rate),
            reference: None,
            settings: MatchSettings::default(),
        }
    }

    /// Set reference from audio
    pub fn set_reference_audio(&mut self, name: &str, left: &[f32], right: &[f32]) {
        self.reference = Some(self.analyzer.create_reference_profile(name, left, right));
    }

    /// Set reference from profile
    pub fn set_reference(&mut self, profile: ReferenceProfile) {
        self.reference = Some(profile);
    }

    /// Set match settings
    pub fn set_settings(&mut self, settings: MatchSettings) {
        self.settings = settings;
    }

    /// Analyze and compare to reference
    pub fn analyze(&self, left: &[f32], right: &[f32]) -> MasterResult<MatchResult> {
        let reference = self
            .reference
            .as_ref()
            .ok_or(MasterError::ReferenceError("No reference set".to_string()))?;

        // Analyze input
        let input_profile = self.analyzer.create_reference_profile("input", left, right);

        // Calculate differences
        let spectral_diff =
            self.calculate_spectral_diff(&input_profile.spectrum, &reference.spectrum);
        let dynamics_diff =
            self.calculate_dynamics_diff(&input_profile.dynamics, &reference.dynamics);
        let stereo_diff = self.calculate_stereo_diff(&input_profile.stereo, &reference.stereo);
        let loudness_diff = reference.loudness.integrated - input_profile.loudness.integrated;

        // Generate EQ curve to match
        let eq_curve = self.generate_eq_curve(&input_profile.spectrum, &reference.spectrum);

        // Generate compression recommendation
        let compression =
            self.generate_compression_rec(&input_profile.dynamics, &reference.dynamics);

        // Generate stereo recommendation
        let stereo = self.generate_stereo_rec(&input_profile.stereo, &reference.stereo);

        // Calculate match score
        let match_score =
            self.calculate_match_score(spectral_diff, dynamics_diff, stereo_diff, loudness_diff);

        Ok(MatchResult {
            spectral_diff_db: spectral_diff,
            dynamics_diff,
            stereo_diff,
            loudness_diff,
            eq_curve,
            compression,
            stereo,
            match_score,
        })
    }

    fn calculate_spectral_diff(&self, input: &[f32], reference: &[f32]) -> f32 {
        let len = input.len().min(reference.len());
        if len == 0 {
            return 0.0;
        }

        let mut sum_sq_diff = 0.0f32;

        for i in 0..len {
            let in_db = if input[i] > 1e-10 {
                20.0 * input[i].log10()
            } else {
                -60.0
            };
            let ref_db = if reference[i] > 1e-10 {
                20.0 * reference[i].log10()
            } else {
                -60.0
            };
            let diff = in_db - ref_db;
            sum_sq_diff += diff * diff;
        }

        (sum_sq_diff / len as f32).sqrt()
    }

    fn calculate_dynamics_diff(&self, input: &DynamicsProfile, reference: &DynamicsProfile) -> f32 {
        let crest_diff = (input.crest_factor - reference.crest_factor).abs();
        let dr_diff = (input.dynamic_range - reference.dynamic_range).abs();
        let lra_diff = (input.lra - reference.lra).abs();

        // Normalize and combine
        (crest_diff / 6.0 + dr_diff / 20.0 + lra_diff / 15.0) / 3.0
    }

    fn calculate_stereo_diff(&self, input: &StereoProfile, reference: &StereoProfile) -> f32 {
        let corr_diff = (input.correlation - reference.correlation).abs();
        let width_diff = (input.width - reference.width).abs();
        let balance_diff = (input.balance - reference.balance).abs();

        (corr_diff + width_diff + balance_diff) / 3.0
    }

    fn generate_eq_curve(&self, input: &[f32], reference: &[f32]) -> Vec<f32> {
        let len = input.len().min(reference.len());
        let mut curve = vec![1.0f32; len];

        for i in 0..len {
            let in_mag = input[i].max(1e-10);
            let ref_mag = reference[i].max(1e-10);

            // Calculate ratio
            let ratio = ref_mag / in_mag;

            // Apply smoothing
            curve[i] = ratio.powf(self.settings.spectral_match);

            // Limit extreme corrections
            curve[i] = curve[i].clamp(0.25, 4.0);
        }

        // Apply spectral smoothing
        if self.settings.spectral_smoothing > 0.0 {
            let smooth_window = (len as f32 * self.settings.spectral_smoothing * 0.1) as usize;
            let smooth_window = smooth_window.max(1).min(len / 4);

            for _ in 0..3 {
                let mut smoothed = curve.clone();
                for i in smooth_window..(len - smooth_window) {
                    let mut sum = 0.0f32;
                    for j in (i - smooth_window)..=(i + smooth_window) {
                        sum += curve[j];
                    }
                    smoothed[i] = sum / (2 * smooth_window + 1) as f32;
                }
                curve = smoothed;
            }
        }

        curve
    }

    fn generate_compression_rec(
        &self,
        input: &DynamicsProfile,
        reference: &DynamicsProfile,
    ) -> CompressionRecommendation {
        let crest_diff = reference.crest_factor - input.crest_factor;
        let dr_diff = reference.dynamic_range - input.dynamic_range;

        // If reference has lower crest factor, we need more compression
        let threshold_adjust = if crest_diff < 0.0 {
            crest_diff * 0.5 // Lower threshold
        } else {
            0.0 // Don't add expansion
        };

        let ratio_adjust = if crest_diff < -3.0 {
            0.5 // Increase ratio
        } else if crest_diff > 3.0 {
            -0.3 // Decrease ratio
        } else {
            0.0
        };

        // Attack/release based on dynamics
        let attack_adjust = if dr_diff < -5.0 { -2.0 } else { 0.0 };
        let release_adjust = if dr_diff < -5.0 { -20.0 } else { 0.0 };

        CompressionRecommendation {
            threshold_adjust: threshold_adjust * self.settings.dynamics_match,
            ratio_adjust: ratio_adjust * self.settings.dynamics_match,
            attack_adjust: attack_adjust * self.settings.dynamics_match,
            release_adjust: release_adjust * self.settings.dynamics_match,
        }
    }

    fn generate_stereo_rec(
        &self,
        input: &StereoProfile,
        reference: &StereoProfile,
    ) -> StereoRecommendation {
        let width_diff = reference.width - input.width;
        let balance_diff = reference.balance - input.balance;

        // If reference is wider, increase width
        let width_adjust = width_diff * self.settings.stereo_match;

        // Balance adjustment
        let balance_adjust = balance_diff * self.settings.stereo_match;

        // Low mono frequency based on reference low mono
        let low_mono_freq = if reference.low_mono > 0.9 {
            200.0 // Reference has mono bass
        } else {
            80.0
        };

        StereoRecommendation {
            width_adjust,
            balance_adjust,
            low_mono_freq,
        }
    }

    fn calculate_match_score(
        &self,
        spectral: f32,
        dynamics: f32,
        stereo: f32,
        loudness: f32,
    ) -> f32 {
        // Weight factors
        let spectral_weight = 0.4;
        let dynamics_weight = 0.25;
        let stereo_weight = 0.15;
        let loudness_weight = 0.2;

        // Convert differences to scores (0-100)
        let spectral_score = 100.0 * (-spectral / 10.0).exp();
        let dynamics_score = 100.0 * (1.0 - dynamics.min(1.0));
        let stereo_score = 100.0 * (1.0 - stereo.min(1.0));
        let loudness_score = 100.0 * (-loudness.abs() / 10.0).exp();

        spectral_weight * spectral_score
            + dynamics_weight * dynamics_score
            + stereo_weight * stereo_score
            + loudness_weight * loudness_score
    }

    /// Get reference profile
    pub fn reference(&self) -> Option<&ReferenceProfile> {
        self.reference.as_ref()
    }
}

/// Pre-built reference profiles for common genres
pub struct GenreReference;

impl GenreReference {
    /// Create EDM reference profile (placeholder)
    pub fn edm() -> ReferenceProfile {
        ReferenceProfile {
            name: "EDM Reference".to_string(),
            spectrum: vec![1.0; 2049], // Would be actual spectrum
            dynamics: DynamicsProfile {
                crest_factor: 8.0,
                dynamic_range: 6.0,
                lra: 5.0,
                band_dynamics: vec![-10.0, -8.0, -6.0, -8.0],
            },
            stereo: StereoProfile {
                correlation: 0.6,
                width: 1.3,
                low_mono: 1.0,
                balance: 0.0,
            },
            loudness: LoudnessMeasurement {
                integrated: -8.0,
                short_term_max: -6.0,
                momentary_max: -4.0,
                true_peak: -0.5,
                lra: 5.0,
            },
        }
    }

    /// Create pop reference profile
    pub fn pop() -> ReferenceProfile {
        ReferenceProfile {
            name: "Pop Reference".to_string(),
            spectrum: vec![1.0; 2049],
            dynamics: DynamicsProfile {
                crest_factor: 10.0,
                dynamic_range: 8.0,
                lra: 7.0,
                band_dynamics: vec![-12.0, -10.0, -8.0, -10.0],
            },
            stereo: StereoProfile {
                correlation: 0.7,
                width: 1.1,
                low_mono: 1.0,
                balance: 0.0,
            },
            loudness: LoudnessMeasurement {
                integrated: -11.0,
                short_term_max: -9.0,
                momentary_max: -7.0,
                true_peak: -1.0,
                lra: 7.0,
            },
        }
    }

    /// Create classical reference profile
    pub fn classical() -> ReferenceProfile {
        ReferenceProfile {
            name: "Classical Reference".to_string(),
            spectrum: vec![1.0; 2049],
            dynamics: DynamicsProfile {
                crest_factor: 18.0,
                dynamic_range: 25.0,
                lra: 18.0,
                band_dynamics: vec![-20.0, -18.0, -16.0, -18.0],
            },
            stereo: StereoProfile {
                correlation: 0.5,
                width: 1.0,
                low_mono: 0.5,
                balance: 0.0,
            },
            loudness: LoudnessMeasurement {
                integrated: -23.0,
                short_term_max: -15.0,
                momentary_max: -10.0,
                true_peak: -1.0,
                lra: 18.0,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reference_matcher() {
        let mut matcher = ReferenceMatcher::new(48000);

        // Set EDM reference
        matcher.set_reference(GenreReference::edm());

        // Analyze test signal
        let audio: Vec<f32> = (0..96000)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 48000.0).sin() * 0.5)
            .collect();

        let result = matcher.analyze(&audio, &audio).unwrap();

        assert!(result.match_score >= 0.0 && result.match_score <= 100.0);
        assert!(!result.eq_curve.is_empty());
    }

    #[test]
    fn test_match_settings() {
        let settings = MatchSettings {
            spectral_match: 0.8,
            dynamics_match: 0.5,
            stereo_match: 0.3,
            loudness_match: 1.0,
            spectral_smoothing: 0.7,
        };

        let mut matcher = ReferenceMatcher::new(48000);
        matcher.set_settings(settings);
        matcher.set_reference(GenreReference::pop());

        assert!(matcher.reference().is_some());
    }

    #[test]
    fn test_genre_references() {
        let edm = GenreReference::edm();
        let pop = GenreReference::pop();
        let classical = GenreReference::classical();

        // EDM should be louder than classical
        assert!(edm.loudness.integrated > classical.loudness.integrated);

        // Classical should have more dynamics
        assert!(classical.dynamics.dynamic_range > edm.dynamics.dynamic_range);

        // Pop should be in between
        assert!(pop.loudness.integrated < edm.loudness.integrated);
        assert!(pop.loudness.integrated > classical.loudness.integrated);
    }
}

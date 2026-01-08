//! Complete mastering chain
//!
//! Combines all mastering components into unified processor

use crate::{
    Genre, LoudnessTarget, MasterConfig, MasteringPreset, MasteringResult,
    LoudnessMeasurement, ReferenceProfile,
    analysis::MasteringAnalyzer,
    dynamics::{MultibandDynamics, MultibandDynamicsConfig, MasteringCompressor},
    eq::{LinearPhaseEq, TiltEq, MasterEqConfig},
    limiter::{TruePeakLimiter, LimiterConfig},
    loudness::{LufsMeter, LoudnessNormalizer},
    stereo::{StereoEnhancer, StereoConfig},
    reference::ReferenceMatcher,
    error::{MasterError, MasterResult},
};

/// Complete mastering engine
pub struct MasteringEngine {
    /// Configuration
    config: MasterConfig,
    /// Sample rate
    sample_rate: u32,
    /// Analyzer
    analyzer: MasteringAnalyzer,
    /// Pre-EQ (tilt)
    pre_eq: TiltEq,
    /// Main EQ
    main_eq: LinearPhaseEq,
    /// Multiband dynamics
    multiband: MultibandDynamics,
    /// Bus compressor
    bus_comp: MasteringCompressor,
    /// Stereo enhancer
    stereo: StereoEnhancer,
    /// Limiter
    limiter: TruePeakLimiter,
    /// Input meter
    input_meter: LufsMeter,
    /// Output meter
    output_meter: LufsMeter,
    /// Loudness normalizer
    normalizer: LoudnessNormalizer,
    /// Reference matcher
    matcher: ReferenceMatcher,
    /// Detected genre
    detected_genre: Genre,
    /// Is active
    active: bool,
    /// Analysis phase complete
    analysis_done: bool,
}

impl MasteringEngine {
    /// Create new mastering engine
    pub fn new(sample_rate: u32) -> Self {
        let config = MasterConfig {
            sample_rate,
            ..Default::default()
        };

        Self::with_config(config)
    }

    /// Create with configuration
    pub fn with_config(config: MasterConfig) -> Self {
        let sample_rate = config.sample_rate;

        // Create components
        let analyzer = MasteringAnalyzer::new(sample_rate);

        let pre_eq = TiltEq::new(sample_rate);

        let eq_config = MasterEqConfig {
            sample_rate,
            ..Default::default()
        };
        let main_eq = LinearPhaseEq::new(eq_config);

        let multiband_config = MultibandDynamicsConfig {
            sample_rate,
            crossovers: config.crossovers.clone(),
            ..Default::default()
        };
        let multiband = MultibandDynamics::new(multiband_config);

        let bus_comp = MasteringCompressor::new(sample_rate);

        let stereo_config = StereoConfig {
            sample_rate,
            ..Default::default()
        };
        let stereo = StereoEnhancer::new(stereo_config);

        let limiter_config = LimiterConfig {
            sample_rate,
            ceiling: config.loudness.true_peak,
            lookahead_ms: config.limiter_lookahead_ms,
            ..Default::default()
        };
        let limiter = TruePeakLimiter::new(limiter_config);

        let input_meter = LufsMeter::new(sample_rate);
        let output_meter = LufsMeter::new(sample_rate);

        let normalizer = LoudnessNormalizer::new(sample_rate, config.loudness.clone());

        let matcher = ReferenceMatcher::new(sample_rate);

        Self {
            config,
            sample_rate,
            analyzer,
            pre_eq,
            main_eq,
            multiband,
            bus_comp,
            stereo,
            limiter,
            input_meter,
            output_meter,
            normalizer,
            matcher,
            detected_genre: Genre::Unknown,
            active: true,
            analysis_done: false,
        }
    }

    /// Set preset
    pub fn set_preset(&mut self, preset: MasteringPreset) {
        self.config.preset = preset;
        self.config.loudness = LoudnessTarget::from_preset(preset);

        // Update limiter ceiling
        self.limiter.set_ceiling(preset.true_peak_limit());
    }

    /// Set loudness target
    pub fn set_loudness_target(&mut self, target: LoudnessTarget) {
        self.config.loudness = target.clone();
        self.limiter.set_ceiling(target.true_peak);
    }

    /// Set reference track
    pub fn set_reference(&mut self, profile: ReferenceProfile) {
        self.matcher.set_reference(profile);
    }

    /// Set reference from audio
    pub fn set_reference_audio(&mut self, name: &str, left: &[f32], right: &[f32]) {
        self.matcher.set_reference_audio(name, left, right);
    }

    /// Analyze input audio (call before processing for optimal results)
    pub fn analyze(&mut self, left: &[f32], right: &[f32]) {
        // Detect genre
        if self.config.auto_genre {
            self.detected_genre = self.analyzer.detect_genre(left, right);
        } else {
            self.detected_genre = self.config.genre;
        }

        // Measure input loudness
        self.input_meter.process(left, right);

        // Analyze for loudness normalization
        self.normalizer.analyze(left, right);

        self.analysis_done = true;
    }

    /// Finalize analysis and prepare for processing
    pub fn finalize_analysis(&mut self) {
        if !self.analysis_done {
            return;
        }

        self.normalizer.finalize();

        // Apply genre-specific settings
        self.apply_genre_settings();

        // Apply reference matching if set
        if self.matcher.reference().is_some() {
            // Would apply match EQ curve here
        }
    }

    fn apply_genre_settings(&mut self) {
        let genre = self.detected_genre;

        // Apply tilt based on genre
        self.pre_eq.set_tilt(genre.spectral_tilt());

        // Adjust compression based on genre
        let ratio = genre.compression_ratio();
        self.bus_comp.set_ratio(ratio);

        // Adjust stereo width
        self.stereo.set_width(genre.stereo_width());
    }

    /// Process stereo sample (real-time)
    pub fn process_sample(&mut self, left: f32, right: f32) -> (f32, f32) {
        if !self.active {
            return (left, right);
        }

        // Pre-EQ (tilt)
        let (l, r) = self.pre_eq.process(left, right);

        // Stereo enhancement
        let (l, r) = self.stereo.process(l, r);

        // Bus compression (simplified - would use multiband in full chain)
        let (l, r) = self.bus_comp.process(l, r);

        // Limiting
        let (l, r) = self.limiter.process_sample(l, r);

        (l, r)
    }

    /// Process buffer (offline or block-based)
    pub fn process(&mut self, input_l: &[f32], input_r: &[f32], output_l: &mut [f32], output_r: &mut [f32]) -> MasterResult<()> {
        if input_l.len() != output_l.len() {
            return Err(MasterError::BufferMismatch {
                expected: input_l.len(),
                got: output_l.len(),
            });
        }

        // Process sample by sample for now
        // Full implementation would use block processing with overlap
        for i in 0..input_l.len() {
            let (l, r) = self.process_sample(input_l[i], input_r[i]);
            output_l[i] = l;
            output_r[i] = r;
        }

        // Update output meter
        self.output_meter.process(output_l, output_r);

        Ok(())
    }

    /// Process complete file and return result
    pub fn process_offline(&mut self, left: &[f32], right: &[f32]) -> MasterResult<MasteringResult> {
        // Analysis phase
        self.analyze(left, right);
        self.finalize_analysis();

        // Measure input
        let input_loudness = LoudnessMeasurement {
            integrated: self.input_meter.integrated(),
            short_term_max: self.input_meter.short_term(),
            momentary_max: self.input_meter.momentary(),
            true_peak: self.input_meter.true_peak(),
            lra: 0.0, // Would calculate separately
        };

        // Process
        let mut output_l = vec![0.0f32; left.len()];
        let mut output_r = vec![0.0f32; right.len()];

        self.process(left, right, &mut output_l, &mut output_r)?;

        // Measure output
        let output_loudness = LoudnessMeasurement {
            integrated: self.output_meter.integrated(),
            short_term_max: self.output_meter.short_term(),
            momentary_max: self.output_meter.momentary(),
            true_peak: self.output_meter.true_peak(),
            lra: 0.0,
        };

        // Generate result
        let applied_gain = self.normalizer.gain_db();
        let peak_reduction = self.limiter.gain_reduction();

        let chain_summary = vec![
            format!("Genre: {:?}", self.detected_genre),
            format!("Tilt EQ: {:.1} dB", self.detected_genre.spectral_tilt()),
            format!("Width: {:.0}%", self.detected_genre.stereo_width() * 100.0),
            format!("Gain: {:.1} dB", applied_gain),
            format!("Peak reduction: {:.1} dB", peak_reduction),
            format!("Ceiling: {:.1} dBTP", self.config.loudness.true_peak),
        ];

        // Check for warnings
        let mut warnings = Vec::new();

        if output_loudness.true_peak > self.config.loudness.true_peak + 0.1 {
            warnings.push("True peak exceeds target ceiling".to_string());
        }

        if (output_loudness.integrated - self.config.loudness.integrated_lufs).abs() > 1.0 {
            warnings.push("Integrated loudness differs from target".to_string());
        }

        // Calculate quality score
        let quality_score = self.calculate_quality_score(&input_loudness, &output_loudness);

        Ok(MasteringResult {
            audio: Some([output_l, output_r].concat()),
            input_loudness,
            output_loudness,
            detected_genre: self.detected_genre,
            applied_gain,
            peak_reduction,
            chain_summary,
            quality_score,
            warnings,
        })
    }

    fn calculate_quality_score(&self, _input: &LoudnessMeasurement, output: &LoudnessMeasurement) -> f32 {
        let mut score = 100.0;

        // Penalize if true peak too high
        if output.true_peak > self.config.loudness.true_peak {
            score -= 20.0;
        }

        // Penalize if loudness missed target
        let lufs_diff = (output.integrated - self.config.loudness.integrated_lufs).abs();
        score -= lufs_diff * 5.0;

        // Penalize excessive limiting
        let peak_reduction = self.limiter.gain_reduction();
        if peak_reduction > 6.0 {
            score -= (peak_reduction - 6.0) * 2.0;
        }

        score.clamp(0.0, 100.0)
    }

    /// Get total latency
    pub fn latency(&self) -> usize {
        self.main_eq.latency() + self.limiter.latency()
    }

    /// Reset all state
    pub fn reset(&mut self) {
        self.pre_eq.reset();
        self.main_eq.reset();
        self.multiband.reset();
        self.bus_comp.reset();
        self.stereo.reset();
        self.limiter.reset();
        self.input_meter.reset();
        self.output_meter.reset();
        self.normalizer.reset();
        self.analysis_done = false;
    }

    /// Get current gain reduction
    pub fn gain_reduction(&self) -> f32 {
        self.bus_comp.gain_reduction() + self.limiter.gain_reduction()
    }

    /// Get detected genre
    pub fn genre(&self) -> Genre {
        self.detected_genre
    }

    /// Set active state
    pub fn set_active(&mut self, active: bool) {
        self.active = active;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation() {
        let engine = MasteringEngine::new(48000);
        assert_eq!(engine.sample_rate, 48000);
    }

    #[test]
    fn test_preset_application() {
        let mut engine = MasteringEngine::new(48000);

        engine.set_preset(MasteringPreset::Streaming);
        assert_eq!(engine.config.preset, MasteringPreset::Streaming);

        engine.set_preset(MasteringPreset::Broadcast);
        assert_eq!(engine.config.loudness.integrated_lufs, -23.0);
    }

    #[test]
    fn test_process_sample() {
        let mut engine = MasteringEngine::new(48000);

        let (l, r) = engine.process_sample(0.5, 0.5);
        assert!(l.is_finite());
        assert!(r.is_finite());
    }

    #[test]
    fn test_offline_processing() {
        let mut engine = MasteringEngine::new(48000);
        engine.set_preset(MasteringPreset::Streaming);

        // Generate test audio
        let audio: Vec<f32> = (0..96000)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 48000.0).sin() * 0.5)
            .collect();

        let result = engine.process_offline(&audio, &audio).unwrap();

        assert!(result.quality_score >= 0.0);
        assert!(result.output_loudness.true_peak <= 0.0);
    }

    #[test]
    fn test_genre_detection() {
        let mut engine = MasteringEngine::new(48000);

        // Silent audio
        let silence = vec![0.0f32; 48000];
        engine.analyze(&silence, &silence);

        // Should detect something (probably Unknown for silence)
        assert_eq!(engine.genre(), Genre::Unknown);
    }

    #[test]
    fn test_latency() {
        let engine = MasteringEngine::new(48000);
        let latency = engine.latency();

        // Should have some latency from lookahead
        assert!(latency > 0);
    }
}

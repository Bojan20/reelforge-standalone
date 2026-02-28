use crate::core::config::FatigueConfig;

/// Converts fatigue metrics into audio regulation parameters.
pub struct PsychoRegulator;

impl PsychoRegulator {
    /// Compute HF shelf attenuation from fatigue index.
    ///
    /// Formula: quadratic ramp from 0 dB to max_hf_atten_db.
    /// fatigue=0 → 0 dB (no attenuation)
    /// fatigue=1 → max_hf_atten_db (e.g., -6 dB)
    ///
    /// Onset is gentle (quadratic) to avoid abrupt changes.
    pub fn hf_attenuation(fatigue_index: f64, config: &FatigueConfig) -> f64 {
        let f = fatigue_index.clamp(0.0, 1.0);
        // Quadratic onset: gentle start, accelerates at high fatigue
        f * f * config.max_hf_atten_db
    }

    /// Compute transient smoothing from fatigue index.
    ///
    /// Formula: S-curve (smoothstep) from 0.0 to max_transient_smooth.
    /// fatigue=0 → 0.0 (sharp transients preserved)
    /// fatigue=1 → max_transient_smooth (transients softened)
    pub fn transient_smoothing(fatigue_index: f64, config: &FatigueConfig) -> f64 {
        let f = fatigue_index.clamp(0.0, 1.0);
        // Smoothstep: 3f² - 2f³
        let s = f * f * (3.0 - 2.0 * f);
        s * config.max_transient_smooth
    }

    /// Compute stereo width narrowing from fatigue index.
    ///
    /// Formula: linear interpolation from 1.0 to max_width_narrow.
    /// fatigue=0 → 1.0 (full width)
    /// fatigue=1 → max_width_narrow (e.g., 0.6)
    pub fn width_narrowing(fatigue_index: f64, config: &FatigueConfig) -> f64 {
        let f = fatigue_index.clamp(0.0, 1.0);
        1.0 - f * (1.0 - config.max_width_narrow)
    }

    /// Compute micro-variation reduction from fatigue.
    ///
    /// At high fatigue, reduce micro-variation to provide a calmer experience.
    /// fatigue=0 → 1.0 (full variation)
    /// fatigue=1 → 0.3 (reduced variation)
    pub fn variation_reduction(fatigue_index: f64) -> f64 {
        let f = fatigue_index.clamp(0.0, 1.0);
        1.0 - f * 0.7
    }

    /// Compute all regulation outputs at once.
    pub fn compute_all(fatigue_index: f64, config: &FatigueConfig) -> RegulationOutput {
        RegulationOutput {
            hf_attenuation_db: Self::hf_attenuation(fatigue_index, config),
            transient_smoothing: Self::transient_smoothing(fatigue_index, config),
            width_factor: Self::width_narrowing(fatigue_index, config),
            variation_scale: Self::variation_reduction(fatigue_index),
        }
    }
}

/// Output from the psycho regulator.
#[derive(Debug, Clone, Copy)]
pub struct RegulationOutput {
    /// HF shelf attenuation in dB (0 to negative).
    pub hf_attenuation_db: f64,
    /// Transient smoothing factor (0.0 = sharp, 1.0 = smooth).
    pub transient_smoothing: f64,
    /// Stereo width multiplier (1.0 = full, 0.6 = narrowed).
    pub width_factor: f64,
    /// Variation intensity scale (1.0 = full, 0.3 = reduced).
    pub variation_scale: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> FatigueConfig {
        FatigueConfig::default()
    }

    #[test]
    fn test_no_regulation_when_fresh() {
        let cfg = default_config();
        let out = PsychoRegulator::compute_all(0.0, &cfg);
        assert_eq!(out.hf_attenuation_db, 0.0);
        assert_eq!(out.transient_smoothing, 0.0);
        assert_eq!(out.width_factor, 1.0);
        assert_eq!(out.variation_scale, 1.0);
    }

    #[test]
    fn test_full_regulation_when_fatigued() {
        let cfg = default_config();
        let out = PsychoRegulator::compute_all(1.0, &cfg);
        assert!((out.hf_attenuation_db - cfg.max_hf_atten_db).abs() < 0.01);
        assert!((out.transient_smoothing - cfg.max_transient_smooth).abs() < 0.01);
        assert!((out.width_factor - cfg.max_width_narrow).abs() < 0.01);
        assert!((out.variation_scale - 0.3).abs() < 0.01);
    }

    #[test]
    fn test_hf_attenuation_monotonic() {
        let cfg = default_config();
        let mut prev = 0.0;
        for i in 0..=100 {
            let f = i as f64 / 100.0;
            let val = PsychoRegulator::hf_attenuation(f, &cfg);
            // HF attenuation goes MORE negative (more reduction)
            assert!(val <= prev + 0.001, "Not monotonically decreasing at f={f}");
            prev = val;
        }
    }

    #[test]
    fn test_width_narrowing_range() {
        let cfg = default_config();
        let at_0 = PsychoRegulator::width_narrowing(0.0, &cfg);
        let at_1 = PsychoRegulator::width_narrowing(1.0, &cfg);
        assert_eq!(at_0, 1.0);
        assert!((at_1 - cfg.max_width_narrow).abs() < 0.01);
        assert!(at_1 < at_0);
    }

    #[test]
    fn test_transient_smoothing_s_curve() {
        let cfg = default_config();
        let at_half = PsychoRegulator::transient_smoothing(0.5, &cfg);
        // S-curve midpoint = 0.5 of max
        let expected = 0.5 * cfg.max_transient_smooth;
        assert!((at_half - expected).abs() < 0.01);
    }

    #[test]
    fn test_clamping() {
        let cfg = default_config();
        let out_neg = PsychoRegulator::compute_all(-0.5, &cfg);
        let out_over = PsychoRegulator::compute_all(1.5, &cfg);
        // Should clamp to valid ranges
        assert_eq!(out_neg.hf_attenuation_db, 0.0);
        assert!((out_over.hf_attenuation_db - cfg.max_hf_atten_db).abs() < 0.01);
    }
}

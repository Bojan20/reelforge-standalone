use crate::core::config::VolatilityConfig;

/// Translates a volatility index (0.0-1.0) into audio behavior parameters.
pub struct VolatilityTranslator;

impl VolatilityTranslator {
    /// Compute stereo elasticity from volatility.
    /// Higher volatility = wider, more responsive stereo field.
    ///
    /// Formula: cubic easing from elasticity_min to elasticity_max.
    /// volatility=0 → elasticity_min (tight, focused)
    /// volatility=1 → elasticity_max (wide, reactive)
    pub fn stereo_elasticity(volatility: f64, config: &VolatilityConfig) -> f64 {
        let v = volatility.clamp(0.0, 1.0);
        let curved = v.powf(config.elasticity_curve_exp);
        config.elasticity_min + curved * (config.elasticity_max - config.elasticity_min)
    }

    /// Compute energy density envelope from volatility.
    /// Higher volatility = denser, more packed audio energy.
    ///
    /// Formula: sigmoid-like S-curve for natural perception.
    /// volatility=0 → sparse (energy_density_min)
    /// volatility=1 → dense (energy_density_max)
    pub fn energy_density(volatility: f64, config: &VolatilityConfig) -> f64 {
        let v = volatility.clamp(0.0, 1.0);
        // S-curve: 3v² - 2v³ (smoothstep)
        let s = v * v * (3.0 - 2.0 * v);
        config.energy_density_min + s * (config.energy_density_max - config.energy_density_min)
    }

    /// Compute escalation rate from volatility.
    /// Higher volatility = faster ramp-up during wins.
    ///
    /// Formula: exponential ramp. Base rate 1.0 at volatility=0.
    /// volatility=0 → 1.0 (neutral)
    /// volatility=1 → escalation_rate_max
    pub fn escalation_rate(volatility: f64, config: &VolatilityConfig) -> f64 {
        let v = volatility.clamp(0.0, 1.0);
        // Quadratic ramp: feels more aggressive at high volatility
        1.0 + v * v * (config.escalation_rate_max - 1.0)
    }

    /// Compute micro dynamics intensity from volatility.
    /// Higher volatility = more micro-movement, flutter, variation.
    ///
    /// Formula: linear with subtle compression at extremes.
    /// volatility=0 → 0.0 (static)
    /// volatility=1 → micro_dynamics_max
    pub fn micro_dynamics(volatility: f64, config: &VolatilityConfig) -> f64 {
        let v = volatility.clamp(0.0, 1.0);
        // Slight saturation curve: fast rise, soft ceiling
        let curved = 1.0 - (1.0 - v).powi(2);
        curved * config.micro_dynamics_max
    }

    /// Compute all volatility outputs at once.
    pub fn compute_all(volatility: f64, config: &VolatilityConfig) -> VolatilityOutput {
        VolatilityOutput {
            stereo_elasticity: Self::stereo_elasticity(volatility, config),
            energy_density: Self::energy_density(volatility, config),
            escalation_rate: Self::escalation_rate(volatility, config),
            micro_dynamics: Self::micro_dynamics(volatility, config),
        }
    }
}

/// Output from the volatility translator.
#[derive(Debug, Clone, Copy)]
pub struct VolatilityOutput {
    pub stereo_elasticity: f64,
    pub energy_density: f64,
    pub escalation_rate: f64,
    pub micro_dynamics: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> VolatilityConfig {
        VolatilityConfig::default()
    }

    #[test]
    fn test_stereo_elasticity_range() {
        let cfg = default_config();
        let low = VolatilityTranslator::stereo_elasticity(0.0, &cfg);
        let high = VolatilityTranslator::stereo_elasticity(1.0, &cfg);

        assert!((low - cfg.elasticity_min).abs() < 1e-10);
        assert!((high - cfg.elasticity_max).abs() < 1e-10);
    }

    #[test]
    fn test_stereo_elasticity_monotonic() {
        let cfg = default_config();
        let mut prev = 0.0;
        for i in 0..=100 {
            let v = i as f64 / 100.0;
            let val = VolatilityTranslator::stereo_elasticity(v, &cfg);
            assert!(val >= prev, "Not monotonic at v={v}: {val} < {prev}");
            prev = val;
        }
    }

    #[test]
    fn test_energy_density_smoothstep() {
        let cfg = default_config();
        let at_0 = VolatilityTranslator::energy_density(0.0, &cfg);
        let at_half = VolatilityTranslator::energy_density(0.5, &cfg);
        let at_1 = VolatilityTranslator::energy_density(1.0, &cfg);

        assert!((at_0 - cfg.energy_density_min).abs() < 1e-10);
        assert!((at_1 - cfg.energy_density_max).abs() < 1e-10);
        // S-curve: midpoint should be close to the arithmetic mean
        let midpoint = (cfg.energy_density_min + cfg.energy_density_max) / 2.0;
        assert!((at_half - midpoint).abs() < 0.01);
    }

    #[test]
    fn test_escalation_rate_base() {
        let cfg = default_config();
        let at_0 = VolatilityTranslator::escalation_rate(0.0, &cfg);
        assert!((at_0 - 1.0).abs() < 1e-10, "Base rate should be 1.0");
    }

    #[test]
    fn test_escalation_rate_max() {
        let cfg = default_config();
        let at_1 = VolatilityTranslator::escalation_rate(1.0, &cfg);
        assert!((at_1 - cfg.escalation_rate_max).abs() < 1e-10);
    }

    #[test]
    fn test_micro_dynamics_range() {
        let cfg = default_config();
        let at_0 = VolatilityTranslator::micro_dynamics(0.0, &cfg);
        let at_1 = VolatilityTranslator::micro_dynamics(1.0, &cfg);

        assert!(at_0.abs() < 1e-10, "At v=0, micro_dynamics should be ~0");
        assert!((at_1 - cfg.micro_dynamics_max).abs() < 1e-10);
    }

    #[test]
    fn test_clamping() {
        let cfg = default_config();
        // Out-of-range volatility should clamp
        let neg = VolatilityTranslator::stereo_elasticity(-0.5, &cfg);
        let over = VolatilityTranslator::stereo_elasticity(1.5, &cfg);
        assert!((neg - cfg.elasticity_min).abs() < 1e-10);
        assert!((over - cfg.elasticity_max).abs() < 1e-10);
    }

    #[test]
    fn test_compute_all() {
        let cfg = default_config();
        let out = VolatilityTranslator::compute_all(0.7, &cfg);
        assert!(out.stereo_elasticity > cfg.elasticity_min);
        assert!(out.energy_density > cfg.energy_density_min);
        assert!(out.escalation_rate > 1.0);
        assert!(out.micro_dynamics > 0.0);
    }

    #[test]
    fn test_custom_config() {
        let cfg = VolatilityConfig {
            elasticity_min: 0.5,
            elasticity_max: 3.0,
            elasticity_curve_exp: 1.0, // linear
            ..Default::default()
        };
        let at_half = VolatilityTranslator::stereo_elasticity(0.5, &cfg);
        let expected = 0.5 + 0.5 * (3.0 - 0.5); // 1.75
        assert!((at_half - expected).abs() < 1e-10);
    }

    #[test]
    fn test_determinism() {
        let cfg = default_config();
        let a = VolatilityTranslator::compute_all(0.73, &cfg);
        let b = VolatilityTranslator::compute_all(0.73, &cfg);
        assert_eq!(a.stereo_elasticity, b.stereo_elasticity);
        assert_eq!(a.energy_density, b.energy_density);
        assert_eq!(a.escalation_rate, b.escalation_rate);
        assert_eq!(a.micro_dynamics, b.micro_dynamics);
    }
}

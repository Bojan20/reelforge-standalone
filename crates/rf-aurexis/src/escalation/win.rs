use crate::core::config::EscalationConfig;
use crate::core::parameter_map::EscalationCurveType;
use crate::escalation::curves::EscalationCurve;

/// Computes audio escalation parameters from win magnitude.
///
/// Single asset → infinite scaling through:
/// - Stereo width growth
/// - Harmonic excitation
/// - Reverb tail extension
/// - Sub-frequency reinforcement
/// - Transient sharpness
pub struct WinEscalationEngine;

impl WinEscalationEngine {
    /// Compute all escalation outputs from win data.
    ///
    /// `win_multiplier`: win_amount / bet_amount (0.0 = no win, 5.0 = 5x bet, etc.)
    /// `jackpot_proximity`: 0.0 (far) to 1.0 (imminent)
    /// `curve_type`: which curve shape to use
    pub fn compute(
        win_multiplier: f64,
        jackpot_proximity: f64,
        curve_type: EscalationCurveType,
        config: &EscalationConfig,
    ) -> EscalationOutput {
        // Normalize win multiplier: 0x=0, 1x=0.1, 10x=1.0, 100x=10.0
        let normalized = win_multiplier / 10.0;
        let curved = EscalationCurve::evaluate(normalized, curve_type);

        // Jackpot proximity adds extra escalation
        let jp_boost = jackpot_proximity * 0.3;
        let total = curved + jp_boost;

        EscalationOutput {
            width: Self::width_growth(total, config),
            harmonic_excitation: Self::harmonic_excite(total, config),
            reverb_tail_ms: Self::reverb_extension(total, config),
            sub_reinforcement_db: Self::sub_reinforce(total, config),
            transient_sharpness: Self::transient_sharp(total, config),
            multiplier: 1.0 + total,
        }
    }

    /// Stereo width growth. Exponential curve with saturation.
    /// 0 → 1.0 (neutral), max → width_max
    fn width_growth(escalation: f64, config: &EscalationConfig) -> f64 {
        let growth = escalation.powf(config.width_exponent);
        (1.0 + growth).min(config.width_max)
    }

    /// Harmonic excitation increase. Linear with rate, clamped.
    /// 0 → 1.0 (neutral), max → harmonic_max
    fn harmonic_excite(escalation: f64, config: &EscalationConfig) -> f64 {
        (1.0 + escalation * config.harmonic_rate).min(config.harmonic_max)
    }

    /// Reverb tail extension in ms. Linear, clamped.
    /// 0 → 0 ms, max → reverb_max_ms
    fn reverb_extension(escalation: f64, config: &EscalationConfig) -> f64 {
        (escalation * config.reverb_ms_per_unit).min(config.reverb_max_ms)
    }

    /// Sub-frequency reinforcement in dB. Linear, clamped.
    /// 0 → 0 dB, max → sub_max_db
    fn sub_reinforce(escalation: f64, config: &EscalationConfig) -> f64 {
        (escalation * config.sub_db_per_unit).min(config.sub_max_db)
    }

    /// Transient sharpness increase. Linear with rate, clamped.
    /// 0 → 1.0 (neutral), max → transient_max
    fn transient_sharp(escalation: f64, config: &EscalationConfig) -> f64 {
        (1.0 + escalation * config.transient_rate).min(config.transient_max)
    }
}

/// Output from the win escalation engine.
#[derive(Debug, Clone, Copy)]
pub struct EscalationOutput {
    /// Stereo width multiplier (1.0 = neutral).
    pub width: f64,
    /// Harmonic excitation multiplier (1.0 = neutral).
    pub harmonic_excitation: f64,
    /// Additional reverb tail in ms.
    pub reverb_tail_ms: f64,
    /// Sub reinforcement in dB.
    pub sub_reinforcement_db: f64,
    /// Transient sharpness multiplier (1.0 = neutral).
    pub transient_sharpness: f64,
    /// Overall escalation multiplier (1.0 = neutral).
    pub multiplier: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> EscalationConfig {
        EscalationConfig::default()
    }

    #[test]
    fn test_no_win_neutral() {
        let cfg = default_config();
        let out = WinEscalationEngine::compute(0.0, 0.0, EscalationCurveType::Linear, &cfg);
        assert_eq!(out.width, 1.0);
        assert_eq!(out.harmonic_excitation, 1.0);
        assert_eq!(out.reverb_tail_ms, 0.0);
        assert_eq!(out.sub_reinforcement_db, 0.0);
        assert_eq!(out.transient_sharpness, 1.0);
    }

    #[test]
    fn test_big_win_escalates() {
        let cfg = default_config();
        let out = WinEscalationEngine::compute(50.0, 0.0, EscalationCurveType::Linear, &cfg);
        assert!(out.width > 1.0);
        assert!(out.harmonic_excitation > 1.0);
        assert!(out.reverb_tail_ms > 0.0);
        assert!(out.sub_reinforcement_db > 0.0);
        assert!(out.transient_sharpness > 1.0);
    }

    #[test]
    fn test_jackpot_proximity_boosts() {
        let cfg = default_config();
        // Use small win so width doesn't saturate at width_max
        let without = WinEscalationEngine::compute(3.0, 0.0, EscalationCurveType::Linear, &cfg);
        let with = WinEscalationEngine::compute(3.0, 0.8, EscalationCurveType::Linear, &cfg);
        assert!(with.width > without.width);
        assert!(with.reverb_tail_ms > without.reverb_tail_ms);
    }

    #[test]
    fn test_saturation_limits() {
        let cfg = default_config();
        let out = WinEscalationEngine::compute(1000.0, 1.0, EscalationCurveType::Linear, &cfg);
        assert!(out.width <= cfg.width_max);
        assert!(out.harmonic_excitation <= cfg.harmonic_max);
        assert!(out.reverb_tail_ms <= cfg.reverb_max_ms);
        assert!(out.sub_reinforcement_db <= cfg.sub_max_db);
        assert!(out.transient_sharpness <= cfg.transient_max);
    }

    #[test]
    fn test_exponential_curve_slower_start() {
        let cfg = default_config();
        let linear = WinEscalationEngine::compute(5.0, 0.0, EscalationCurveType::Linear, &cfg);
        let exp = WinEscalationEngine::compute(5.0, 0.0, EscalationCurveType::Exponential, &cfg);
        // At 5x bet (normalized 0.5), exponential should be lower than linear
        assert!(exp.width <= linear.width + 0.01);
    }

    #[test]
    fn test_monotonic_escalation() {
        let cfg = default_config();
        let mut prev_width = 0.0;
        for mult_10x in 0..=200 {
            let mult = mult_10x as f64 / 10.0;
            let out = WinEscalationEngine::compute(mult, 0.0, EscalationCurveType::Linear, &cfg);
            assert!(out.width >= prev_width - 0.001,
                "Width should be monotonic at mult={mult}");
            prev_width = out.width;
        }
    }
}

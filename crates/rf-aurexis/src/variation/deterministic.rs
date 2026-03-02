use crate::core::config::VariationConfig;
use crate::variation::hash::{combine_seeds, seed_to_range};

/// Produces deterministic micro-variations from seed components.
/// Identical inputs always produce identical outputs across all platforms.
pub struct DeterministicVariationEngine;

impl DeterministicVariationEngine {
    /// Compute a seed from the 4 seed components.
    pub fn seed(sprite_id: u64, event_time: u64, game_state: u64, session_index: u64) -> u64 {
        combine_seeds(sprite_id, event_time, game_state, session_index)
    }

    /// Compute all micro-variations from a seed.
    pub fn compute(seed: u64, config: &VariationConfig) -> MicroVariation {
        MicroVariation {
            pan_drift: seed_to_range(seed, 0, -config.pan_drift_range, config.pan_drift_range),
            width_variance: seed_to_range(
                seed,
                1,
                -config.width_variance_range,
                config.width_variance_range,
            ),
            harmonic_shift: seed_to_range(
                seed,
                2,
                -config.harmonic_shift_range,
                config.harmonic_shift_range,
            ),
            reflection_weight: seed_to_range(
                seed,
                3,
                -config.reflection_weight_range,
                config.reflection_weight_range,
            ),
        }
    }

    /// Compute variations directly from seed components.
    pub fn compute_from_components(
        sprite_id: u64,
        event_time: u64,
        game_state: u64,
        session_index: u64,
        config: &VariationConfig,
    ) -> MicroVariation {
        let seed = Self::seed(sprite_id, event_time, game_state, session_index);
        Self::compute(seed, config)
    }
}

/// Micro-variation deltas applied to audio parameters.
#[derive(Debug, Clone, Copy)]
pub struct MicroVariation {
    /// Pan offset (±). Typically ±0.05.
    pub pan_drift: f64,
    /// Width offset (±). Typically ±0.03.
    pub width_variance: f64,
    /// Harmonic excitation offset (±). Typically ±0.02.
    pub harmonic_shift: f64,
    /// Early reflection weight offset (±). Typically ±0.04.
    pub reflection_weight: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> VariationConfig {
        VariationConfig::default()
    }

    #[test]
    fn test_determinism_100_runs() {
        let cfg = default_config();
        let reference = DeterministicVariationEngine::compute_from_components(42, 1000, 7, 0, &cfg);

        for _ in 0..100 {
            let result =
                DeterministicVariationEngine::compute_from_components(42, 1000, 7, 0, &cfg);
            assert_eq!(result.pan_drift, reference.pan_drift);
            assert_eq!(result.width_variance, reference.width_variance);
            assert_eq!(result.harmonic_shift, reference.harmonic_shift);
            assert_eq!(result.reflection_weight, reference.reflection_weight);
        }
    }

    #[test]
    fn test_different_sprites_different_output() {
        let cfg = default_config();
        let a = DeterministicVariationEngine::compute_from_components(1, 1000, 7, 0, &cfg);
        let b = DeterministicVariationEngine::compute_from_components(2, 1000, 7, 0, &cfg);
        // At least one value should differ
        assert!(
            (a.pan_drift - b.pan_drift).abs() > 0.001
                || (a.width_variance - b.width_variance).abs() > 0.001,
            "Different sprites should produce different variations"
        );
    }

    #[test]
    fn test_output_within_range() {
        let cfg = default_config();
        for sprite in 0..1000 {
            let v = DeterministicVariationEngine::compute_from_components(sprite, 500, 3, 0, &cfg);
            assert!(v.pan_drift.abs() <= cfg.pan_drift_range + 1e-10);
            assert!(v.width_variance.abs() <= cfg.width_variance_range + 1e-10);
            assert!(v.harmonic_shift.abs() <= cfg.harmonic_shift_range + 1e-10);
            assert!(v.reflection_weight.abs() <= cfg.reflection_weight_range + 1e-10);
        }
    }

    #[test]
    fn test_session_index_changes_output() {
        let cfg = default_config();
        let a = DeterministicVariationEngine::compute_from_components(42, 1000, 7, 0, &cfg);
        let b = DeterministicVariationEngine::compute_from_components(42, 1000, 7, 1, &cfg);
        assert_ne!(
            a.pan_drift, b.pan_drift,
            "Different session should give different output"
        );
    }

    #[test]
    fn test_independence_of_parameters() {
        let cfg = default_config();
        // Check that pan_drift and width_variance are not correlated
        let mut same_sign_count = 0;
        for i in 0..1000 {
            let v = DeterministicVariationEngine::compute_from_components(i, 500, 3, 0, &cfg);
            if v.pan_drift.signum() == v.width_variance.signum() {
                same_sign_count += 1;
            }
        }
        // If not perfectly correlated or anti-correlated, ratio should be
        // somewhere between 0 and 1. FNV sub-seeding may not give perfect 50/50.
        let ratio = same_sign_count as f64 / 1000.0;
        assert!(
            ratio > 0.15 && ratio < 0.85,
            "Parameters should not be perfectly correlated: same_sign_ratio={ratio}"
        );
    }
}

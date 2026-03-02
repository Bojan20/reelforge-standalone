use crate::core::parameter_map::DeterministicParameterMap;

/// Verifies deterministic replay: identical inputs → identical outputs.
pub struct ReplayVerifier {
    /// Recorded parameter snapshots for comparison.
    snapshots: Vec<DeterministicParameterMap>,
}

impl ReplayVerifier {
    pub fn new() -> Self {
        Self {
            snapshots: Vec::new(),
        }
    }

    /// Record a parameter map snapshot.
    pub fn record(&mut self, map: &DeterministicParameterMap) {
        self.snapshots.push(map.clone());
    }

    /// Get the number of recorded snapshots.
    pub fn snapshot_count(&self) -> usize {
        self.snapshots.len()
    }

    /// Verify that replaying the same sequence produces identical output.
    ///
    /// Returns the index of the first mismatch, or None if all match.
    pub fn verify_replay(&self, replay_snapshots: &[DeterministicParameterMap]) -> Option<usize> {
        for (i, (original, replay)) in self.snapshots.iter().zip(replay_snapshots).enumerate() {
            if !Self::maps_equal(original, replay) {
                return Some(i);
            }
        }
        None
    }

    /// Compare two parameter maps for exact equality.
    pub fn maps_equal(a: &DeterministicParameterMap, b: &DeterministicParameterMap) -> bool {
        a.stereo_width == b.stereo_width
            && a.stereo_elasticity == b.stereo_elasticity
            && a.pan_drift == b.pan_drift
            && a.width_variance == b.width_variance
            && a.hf_attenuation_db == b.hf_attenuation_db
            && a.harmonic_excitation == b.harmonic_excitation
            && a.sub_reinforcement_db == b.sub_reinforcement_db
            && a.transient_smoothing == b.transient_smoothing
            && a.transient_sharpness == b.transient_sharpness
            && a.energy_density == b.energy_density
            && a.reverb_send_bias == b.reverb_send_bias
            && a.reverb_tail_extension_ms == b.reverb_tail_extension_ms
            && a.z_depth_offset == b.z_depth_offset
            && a.early_reflection_weight == b.early_reflection_weight
            && a.escalation_multiplier == b.escalation_multiplier
            && a.attention_x == b.attention_x
            && a.attention_y == b.attention_y
            && a.attention_weight == b.attention_weight
            && a.center_occupancy == b.center_occupancy
            && a.voices_redistributed == b.voices_redistributed
            && a.ducking_bias_db == b.ducking_bias_db
            && a.platform_stereo_range == b.platform_stereo_range
            && a.platform_mono_safety == b.platform_mono_safety
            && a.platform_depth_range == b.platform_depth_range
            && a.fatigue_index == b.fatigue_index
            && a.variation_seed == b.variation_seed
    }

    /// Clear all recorded snapshots.
    pub fn clear(&mut self) {
        self.snapshots.clear();
    }
}

impl Default for ReplayVerifier {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::config::AurexisConfig;
    use crate::core::engine::AurexisEngine;

    #[test]
    fn test_replay_verification() {
        let config = AurexisConfig::default();

        // Record a session
        let mut engine_a = AurexisEngine::with_config(config.clone());
        engine_a.initialize();
        engine_a.set_volatility(0.6);
        engine_a.set_rtp(93.0);
        engine_a.set_seed(42, 500, 3, 0);

        let mut verifier = ReplayVerifier::new();
        for _ in 0..10 {
            let map = engine_a.compute_cloned(50);
            verifier.record(&map);
        }

        // Replay with identical inputs
        let mut engine_b = AurexisEngine::with_config(config);
        engine_b.initialize();
        engine_b.set_volatility(0.6);
        engine_b.set_rtp(93.0);
        engine_b.set_seed(42, 500, 3, 0);

        let mut replay: Vec<DeterministicParameterMap> = Vec::new();
        for _ in 0..10 {
            replay.push(engine_b.compute_cloned(50));
        }

        assert_eq!(
            verifier.verify_replay(&replay),
            None,
            "Replay should match exactly"
        );
    }
}

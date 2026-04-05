use crate::collision::priority::VoiceCollisionResolver;
use crate::core::config::CollisionConfig;

/// Result of redistributing a single voice.
#[derive(Debug, Clone)]
pub struct VoiceRedistribution {
    pub voice_id: u32,
    pub new_pan: f32,
    pub new_z_depth: f32,
    pub width_factor: f64,
    pub duck_db: f64,
}

/// Handles pan/depth/width redistribution when voices collide.
pub struct PanRedistributor;

impl PanRedistributor {
    /// Resolve all collisions and compute redistributions.
    ///
    /// Algorithm:
    /// 1. Sort voices by priority (highest stays in place)
    /// 2. Count voices in center zone
    /// 3. If over limit: push lowest-priority voices outward
    /// 4. Apply pan spread, z-displacement, width compression, ducking
    pub fn resolve(
        resolver: &mut VoiceCollisionResolver,
        config: &CollisionConfig,
    ) -> Vec<VoiceRedistribution> {
        let mut redistributions = Vec::new();

        // Reset all redistribution flags
        for voice in resolver.voices_mut().iter_mut() {
            voice.redistributed = false;
            voice.pan = voice.original_pan;
        }

        // Sort by priority (highest first — they stay in place)
        resolver.sort_by_priority();

        // Find center-zone voices
        let center_width = config.center_zone_width;
        let center_voices: Vec<usize> = resolver
            .voices()
            .iter()
            .enumerate()
            .filter(|(_, v)| (v.original_pan as f64).abs() <= center_width && v.z_depth < 0.3)
            .map(|(i, _)| i)
            .collect();

        if center_voices.len() <= config.max_center_voices as usize {
            return redistributions; // No collision
        }

        // Voices to push: skip the top N by priority, push the rest
        let to_push = &center_voices[config.max_center_voices as usize..];

        for (push_idx, &voice_idx) in to_push.iter().enumerate() {
            let step = (push_idx + 1) as f64;
            let voice = &resolver.voices()[voice_idx];

            // Alternate left/right spread
            let direction = if push_idx % 2 == 0 { 1.0 } else { -1.0 };
            let new_pan = Self::pan_spread(voice.original_pan as f64, direction, step, config);
            let new_z = Self::z_displacement(voice.z_depth as f64, step, config);
            let width_factor = Self::width_compression(step, config);
            let duck_db = Self::ducking_bias(step, config);

            redistributions.push(VoiceRedistribution {
                voice_id: voice.voice_id,
                new_pan: new_pan as f32,
                new_z_depth: new_z as f32,
                width_factor,
                duck_db,
            });
        }

        // Apply redistributions back to voices
        for redist in &redistributions {
            if let Some(voice) = resolver
                .voices_mut()
                .iter_mut()
                .find(|v| v.voice_id == redist.voice_id)
            {
                voice.pan = redist.new_pan;
                voice.z_depth = redist.new_z_depth;
                voice.redistributed = true;
            }
        }

        redistributions
    }

    /// Spread a voice away from center.
    /// Each step pushes further out, alternating L/R.
    fn pan_spread(original_pan: f64, direction: f64, step: f64, config: &CollisionConfig) -> f64 {
        let offset = direction * step * config.pan_spread_step;
        (original_pan + offset).clamp(-1.0, 1.0)
    }

    /// Push voice back in Z-depth (away from front).
    fn z_displacement(original_z: f64, step: f64, config: &CollisionConfig) -> f64 {
        let new_z = original_z + step * config.z_displacement_amount;
        new_z.clamp(0.0, 1.0)
    }

    /// Compress width of background voices. More pushed = narrower.
    fn width_compression(step: f64, config: &CollisionConfig) -> f64 {
        // Each step reduces width further, asymptotically approaching config.width_compression
        let factor = 1.0 - (1.0 - config.width_compression) * (1.0 - (-step * 0.5).exp());
        factor.clamp(config.width_compression, 1.0)
    }

    /// Auto-duck amount for pushed voices. More pushed = more ducking.
    fn ducking_bias(step: f64, config: &CollisionConfig) -> f64 {
        // Linear ducking per step
        (config.duck_amount_db * step).clamp(config.duck_amount_db * 4.0, 0.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> CollisionConfig {
        CollisionConfig::default()
    }

    #[test]
    fn test_no_collision() {
        let config = default_config();
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, -0.5, 0.0, 10);
        resolver.register_voice(2, 0.5, 0.0, 8);

        let redist = PanRedistributor::resolve(&mut resolver, &config);
        assert!(
            redist.is_empty(),
            "No center collision should produce no redistribution"
        );
    }

    #[test]
    fn test_center_collision_pushes_low_priority() {
        let config = default_config();
        let mut resolver = VoiceCollisionResolver::new();
        // 3 voices in center — max is 2
        resolver.register_voice(1, 0.0, 0.0, 10); // stays (highest priority)
        resolver.register_voice(2, 0.05, 0.0, 8); // stays (second highest)
        resolver.register_voice(3, -0.05, 0.0, 3); // pushed (lowest priority)

        let redist = PanRedistributor::resolve(&mut resolver, &config);
        assert_eq!(redist.len(), 1);
        assert_eq!(redist[0].voice_id, 3);
        // Should be pushed away from center
        assert!(redist[0].new_pan.abs() > 0.05);
    }

    #[test]
    fn test_multiple_collisions() {
        let config = default_config();
        let mut resolver = VoiceCollisionResolver::new();
        // 5 voices in center
        for i in 0..5 {
            resolver.register_voice(i, 0.0, 0.0, (10 - i) as i32);
        }

        let redist = PanRedistributor::resolve(&mut resolver, &config);
        assert_eq!(redist.len(), 3); // 5 - max_center(2) = 3 pushed

        // Verify alternating L/R spread
        let pans: Vec<f32> = redist.iter().map(|r| r.new_pan).collect();
        assert!(pans[0] != 0.0); // pushed away
    }

    #[test]
    fn test_z_displacement_applied() {
        let config = default_config();
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, 0.0, 0.0, 10);
        resolver.register_voice(2, 0.0, 0.0, 8);
        resolver.register_voice(3, 0.0, 0.0, 1);

        let redist = PanRedistributor::resolve(&mut resolver, &config);
        assert_eq!(redist.len(), 1);
        assert!(
            redist[0].new_z_depth > 0.0,
            "Pushed voice should be displaced in Z"
        );
    }

    #[test]
    fn test_width_compression_applied() {
        let config = default_config();
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, 0.0, 0.0, 10);
        resolver.register_voice(2, 0.0, 0.0, 8);
        resolver.register_voice(3, 0.0, 0.0, 1);

        let redist = PanRedistributor::resolve(&mut resolver, &config);
        assert!(
            redist[0].width_factor < 1.0,
            "Pushed voice should have compressed width"
        );
    }

    #[test]
    fn test_ducking_applied() {
        let config = default_config();
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, 0.0, 0.0, 10);
        resolver.register_voice(2, 0.0, 0.0, 8);
        resolver.register_voice(3, 0.0, 0.0, 1);

        let redist = PanRedistributor::resolve(&mut resolver, &config);
        assert!(redist[0].duck_db < 0.0, "Pushed voice should be ducked");
    }

    #[test]
    fn test_back_voices_not_counted_as_center() {
        let config = default_config();
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, 0.0, 0.0, 10); // front center
        resolver.register_voice(2, 0.0, 0.0, 8); // front center
        resolver.register_voice(3, 0.0, 0.5, 1); // back center (z > 0.3)

        let redist = PanRedistributor::resolve(&mut resolver, &config);
        assert!(
            redist.is_empty(),
            "Back-Z voice shouldn't count as center collision"
        );
    }
}

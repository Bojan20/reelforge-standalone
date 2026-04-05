use crate::collision::priority::VoiceCollisionResolver;

/// Spatial density analysis for voice clustering.
pub struct VoiceDensityAnalyzer;

impl VoiceDensityAnalyzer {
    /// Count voices in the center/front zone.
    pub fn center_occupancy(resolver: &VoiceCollisionResolver, center_width: f64) -> u32 {
        resolver.center_occupancy(center_width)
    }

    /// Generate a spatial density map (8 pan zones × 2 depth layers).
    /// Returns density counts per zone.
    pub fn density_map(resolver: &VoiceCollisionResolver) -> DensityMap {
        let mut map = DensityMap::default();

        for voice in resolver.voices() {
            let pan_zone = Self::pan_to_zone(voice.pan as f64);
            let depth_layer = if voice.z_depth < 0.5 { 0 } else { 1 };
            map.zones[depth_layer][pan_zone] += 1;
        }

        map.total_voices = resolver.voice_count() as u32;
        map.max_density = *map.zones.iter().flatten().max().unwrap_or(&0);
        map
    }

    /// Map pan (-1.0 to +1.0) to zone index (0-7).
    fn pan_to_zone(pan: f64) -> usize {
        let normalized = (pan.clamp(-1.0, 1.0) + 1.0) / 2.0; // 0.0-1.0
        let zone = (normalized * 8.0) as usize;
        zone.min(7)
    }
}

/// 8-zone × 2-depth density map.
#[derive(Debug, Clone, Default)]
pub struct DensityMap {
    /// `zones[depth_layer][pan_zone]` = voice count.
    /// depth 0 = front, depth 1 = back.
    /// pan zones: 0=hard left, 3-4=center, 7=hard right.
    pub zones: [[u32; 8]; 2],
    pub total_voices: u32,
    pub max_density: u32,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::collision::priority::VoiceCollisionResolver;

    #[test]
    fn test_density_map_empty() {
        let resolver = VoiceCollisionResolver::new();
        let map = VoiceDensityAnalyzer::density_map(&resolver);
        assert_eq!(map.total_voices, 0);
        assert_eq!(map.max_density, 0);
    }

    #[test]
    fn test_density_map_distribution() {
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, -0.9, 0.0, 10); // hard left, front
        resolver.register_voice(2, 0.0, 0.0, 8); // center, front
        resolver.register_voice(3, 0.0, 0.0, 5); // center, front
        resolver.register_voice(4, 0.9, 0.6, 3); // hard right, back

        let map = VoiceDensityAnalyzer::density_map(&resolver);
        assert_eq!(map.total_voices, 4);
        // Center front should have 2 voices
        assert_eq!(map.zones[0][4], 2); // pan=0.0 → zone 4
        // Hard left front should have 1
        assert_eq!(map.zones[0][0], 1);
        // Hard right back should have 1
        assert_eq!(map.zones[1][7], 1);
    }

    #[test]
    fn test_pan_to_zone() {
        assert_eq!(VoiceDensityAnalyzer::pan_to_zone(-1.0), 0);
        assert_eq!(VoiceDensityAnalyzer::pan_to_zone(0.0), 4);
        assert_eq!(VoiceDensityAnalyzer::pan_to_zone(1.0), 7);
    }
}

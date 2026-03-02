use crate::core::parameter_map::DeterministicParameterMap;
use crate::platform::profiles::PlatformProfile;

/// Applies platform profile modifications to the parameter map.
pub struct PlatformAdapter;

impl PlatformAdapter {
    /// Apply platform profile to parameter map (in-place).
    pub fn apply(map: &mut DeterministicParameterMap, profile: &PlatformProfile) {
        // Stereo width: scale by platform's stereo range factor
        map.stereo_width *= profile.stereo_range_factor;
        map.platform_stereo_range = profile.stereo_range_factor;

        // Pan drift: reduce for narrower platforms
        map.pan_drift *= profile.stereo_range_factor;

        // Width variance: reduce for narrower platforms
        map.width_variance *= profile.stereo_range_factor;

        // Mono safety
        map.platform_mono_safety = profile.mono_safety_level - 1.0; // 0.0 = no boost

        // Depth compression
        map.z_depth_offset *= profile.depth_compression;
        map.platform_depth_range = profile.depth_compression;

        // Reverb: reduce for cabinet/mobile (less spatial depth)
        if profile.depth_compression < 1.0 {
            map.reverb_send_bias *= profile.depth_compression;
            map.reverb_tail_extension_ms *= profile.depth_compression;
        }

        // Early reflections: reduce for collapsed depth
        map.early_reflection_weight *= profile.depth_compression;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::config::PlatformType;

    #[test]
    fn test_desktop_no_change() {
        let mut map = DeterministicParameterMap::default();
        map.stereo_width = 1.5;
        map.pan_drift = 0.04;

        let original_width = map.stereo_width;
        let original_drift = map.pan_drift;

        PlatformAdapter::apply(&mut map, &PlatformProfile::desktop());

        assert_eq!(map.stereo_width, original_width);
        assert_eq!(map.pan_drift, original_drift);
    }

    #[test]
    fn test_mobile_compresses_stereo() {
        let mut map = DeterministicParameterMap::default();
        map.stereo_width = 1.5;
        map.pan_drift = 0.04;

        PlatformAdapter::apply(&mut map, &PlatformProfile::mobile());

        assert!(
            map.stereo_width < 1.5,
            "Mobile should compress stereo width"
        );
        assert!(map.pan_drift < 0.04, "Mobile should reduce pan drift");
        assert_eq!(map.platform_stereo_range, 0.6);
    }

    #[test]
    fn test_headphones_widens() {
        let mut map = DeterministicParameterMap::default();
        map.stereo_width = 1.0;

        PlatformAdapter::apply(&mut map, &PlatformProfile::headphones());

        assert!(map.stereo_width > 1.0, "Headphones should widen stereo");
    }

    #[test]
    fn test_cabinet_mono_safe() {
        let mut map = DeterministicParameterMap::default();
        map.stereo_width = 1.5;
        map.reverb_send_bias = 0.5;

        PlatformAdapter::apply(&mut map, &PlatformProfile::cabinet());

        assert!(
            map.stereo_width < 1.0,
            "Cabinet should heavily compress stereo"
        );
        assert!(map.reverb_send_bias < 0.5, "Cabinet should reduce reverb");
    }

    #[test]
    fn test_platform_profile_lookup() {
        let desktop = PlatformProfile::for_platform(PlatformType::Desktop);
        assert_eq!(desktop.stereo_range_factor, 1.0);

        let mobile = PlatformProfile::for_platform(PlatformType::Mobile);
        assert_eq!(mobile.stereo_range_factor, 0.6);
    }
}

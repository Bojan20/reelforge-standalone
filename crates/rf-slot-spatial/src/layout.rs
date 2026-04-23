//! T7.2: Predefined slot audio layout presets for common VR/AR/Desktop scenarios.
//!
//! A layout preset maps standard slot audio zones to default 3D positions.
//! Designers can start from a preset and fine-tune individual sources.

use serde::{Deserialize, Serialize};
use crate::scene::{SphericalPosition, SpatialAudioSource, AttenuationCurve};

/// Standard audio zone in a slot game
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SlotAudioZone {
    /// Reel spinning area (mechanical sounds)
    ReelArea,
    /// Win presentation area (top of screen)
    WinDisplay,
    /// Ambient / background music (surrounds player)
    Ambient,
    /// Coin/credit sounds (near player's hands)
    CoinArea,
    /// Feature trigger zone (special area)
    FeatureZone,
    /// UI buttons (slightly behind screen plane)
    UiButtons,
    /// Jackpot event (above and surrounding)
    JackpotZone,
}

/// Predefined layout for a slot environment
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SlotLayoutPreset {
    /// Standard desktop/monitor setup (2D, near-field)
    Desktop,
    /// VR standing position (full 360° sphere)
    VrStanding,
    /// VR seated position (larger display in front)
    VrSeated,
    /// Live casino big screen (elevated wide display)
    LiveCasinoBigScreen,
    /// Mobile (mono/stereo, simplified)
    Mobile,
}

/// Get default spatial position for a zone within a preset
pub fn zone_position(preset: SlotLayoutPreset, zone: SlotAudioZone) -> SphericalPosition {
    use SlotLayoutPreset as P;
    use SlotAudioZone as Z;

    match (preset, zone) {
        // Desktop: flat plane, everything in front
        (P::Desktop, Z::ReelArea)       => SphericalPosition::new(0.0, -5.0, 0.8),
        (P::Desktop, Z::WinDisplay)     => SphericalPosition::new(0.0, 15.0, 0.9),
        (P::Desktop, Z::Ambient)        => SphericalPosition::new(0.0, 0.0, 2.0),
        (P::Desktop, Z::CoinArea)       => SphericalPosition::new(0.0, -20.0, 0.7),
        (P::Desktop, Z::FeatureZone)    => SphericalPosition::new(0.0, 20.0, 1.0),
        (P::Desktop, Z::UiButtons)      => SphericalPosition::new(0.0, 0.0, 0.6),
        (P::Desktop, Z::JackpotZone)    => SphericalPosition::new(0.0, 30.0, 1.2),

        // VR Standing: full 360°, reels at eye height in front
        (P::VrStanding, Z::ReelArea)    => SphericalPosition::new(0.0, 0.0, 1.5),
        (P::VrStanding, Z::WinDisplay)  => SphericalPosition::new(0.0, 20.0, 2.0),
        (P::VrStanding, Z::Ambient)     => SphericalPosition::new(0.0, 0.0, 5.0),
        (P::VrStanding, Z::CoinArea)    => SphericalPosition::new(-30.0, -30.0, 1.0),
        (P::VrStanding, Z::FeatureZone) => SphericalPosition::new(0.0, 0.0, 1.8),
        (P::VrStanding, Z::UiButtons)   => SphericalPosition::new(-45.0, -15.0, 0.8),
        (P::VrStanding, Z::JackpotZone) => SphericalPosition::new(0.0, 60.0, 3.0),

        // VR Seated: slot slightly elevated, immersive
        (P::VrSeated, Z::ReelArea)      => SphericalPosition::new(0.0, 10.0, 1.2),
        (P::VrSeated, Z::WinDisplay)    => SphericalPosition::new(0.0, 30.0, 1.5),
        (P::VrSeated, Z::Ambient)       => SphericalPosition::new(0.0, 10.0, 4.0),
        (P::VrSeated, Z::CoinArea)      => SphericalPosition::new(0.0, -25.0, 0.8),
        (P::VrSeated, Z::FeatureZone)   => SphericalPosition::new(0.0, 20.0, 1.5),
        (P::VrSeated, Z::UiButtons)     => SphericalPosition::new(-20.0, -10.0, 0.7),
        (P::VrSeated, Z::JackpotZone)   => SphericalPosition::new(0.0, 70.0, 2.5),

        // Live Casino Big Screen: large display above, coin tray below
        (P::LiveCasinoBigScreen, Z::ReelArea)    => SphericalPosition::new(0.0, 20.0, 2.0),
        (P::LiveCasinoBigScreen, Z::WinDisplay)  => SphericalPosition::new(0.0, 35.0, 2.5),
        (P::LiveCasinoBigScreen, Z::Ambient)     => SphericalPosition::new(0.0, 5.0, 6.0),
        (P::LiveCasinoBigScreen, Z::CoinArea)    => SphericalPosition::new(0.0, -40.0, 0.5),
        (P::LiveCasinoBigScreen, Z::FeatureZone) => SphericalPosition::new(0.0, 30.0, 2.0),
        (P::LiveCasinoBigScreen, Z::UiButtons)   => SphericalPosition::new(0.0, -20.0, 0.6),
        (P::LiveCasinoBigScreen, Z::JackpotZone) => SphericalPosition::new(0.0, 45.0, 3.0),

        // Mobile: all front, minimal separation
        (P::Mobile, _) => SphericalPosition::new(0.0, 0.0, 1.0),
    }
}

/// Get default attenuation for a zone
pub fn zone_attenuation(zone: SlotAudioZone) -> AttenuationCurve {
    match zone {
        SlotAudioZone::Ambient => AttenuationCurve::None,
        SlotAudioZone::JackpotZone => AttenuationCurve::None,
        _ => AttenuationCurve::InverseSquare,
    }
}

/// Generate default source list for a preset.
///
/// Maps common slot event names to their default zones.
pub fn layout_for_preset(
    preset: SlotLayoutPreset,
    game_id: &str,
) -> Vec<SpatialAudioSource> {
    let mappings: &[(&str, &str, SlotAudioZone)] = &[
        ("REEL_SPIN",        "Reel Spin",        SlotAudioZone::ReelArea),
        ("REEL_STOP",        "Reel Stop",        SlotAudioZone::ReelArea),
        ("SPIN_START",       "Spin Start",       SlotAudioZone::UiButtons),
        ("WIN_1",            "Win Tier 1",       SlotAudioZone::WinDisplay),
        ("WIN_2",            "Win Tier 2",       SlotAudioZone::WinDisplay),
        ("WIN_3",            "Win Tier 3",       SlotAudioZone::WinDisplay),
        ("WIN_4",            "Win Tier 4",       SlotAudioZone::WinDisplay),
        ("WIN_5",            "Win Tier 5 (Mega)",SlotAudioZone::JackpotZone),
        ("AMBIENT_BED",      "Ambient Bed",      SlotAudioZone::Ambient),
        ("FEATURE_TRIGGER",  "Feature Trigger",  SlotAudioZone::FeatureZone),
        ("BONUS_WIN",        "Bonus Win",        SlotAudioZone::FeatureZone),
        ("JACKPOT",          "Jackpot",          SlotAudioZone::JackpotZone),
        ("COIN_IN",          "Coin In",          SlotAudioZone::CoinArea),
        ("COIN_OUT",         "Coin Out",         SlotAudioZone::CoinArea),
        ("NEAR_MISS",        "Near Miss",        SlotAudioZone::ReelArea),
    ];

    let _ = game_id; // future: customize per-game

    mappings.iter().map(|(event_id, label, zone)| {
        let pos = zone_position(preset, *zone);
        let att = zone_attenuation(*zone);
        let mut src = SpatialAudioSource::new(*event_id, *label, pos);
        src.attenuation = att;
        src
    }).collect()
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_desktop_reel_area_is_in_front() {
        let pos = zone_position(SlotLayoutPreset::Desktop, SlotAudioZone::ReelArea);
        assert!(pos.azimuth_deg.abs() < 10.0, "ReelArea should be roughly in front");
        assert!(pos.distance_m < 2.0);
    }

    #[test]
    fn test_vr_jackpot_is_high_elevation() {
        let pos = zone_position(SlotLayoutPreset::VrStanding, SlotAudioZone::JackpotZone);
        assert!(pos.elevation_deg > 45.0, "VR jackpot should be above player");
    }

    #[test]
    fn test_ambient_has_no_attenuation() {
        let att = zone_attenuation(SlotAudioZone::Ambient);
        assert!(matches!(att, AttenuationCurve::None));
    }

    #[test]
    fn test_layout_for_preset_desktop_generates_sources() {
        let sources = layout_for_preset(SlotLayoutPreset::Desktop, "phoenix");
        assert!(!sources.is_empty());
        let event_ids: Vec<&str> = sources.iter().map(|s| s.event_id.as_str()).collect();
        assert!(event_ids.contains(&"SPIN_START"));
        assert!(event_ids.contains(&"WIN_5"));
        assert!(event_ids.contains(&"AMBIENT_BED"));
    }

    #[test]
    fn test_mobile_all_same_position() {
        let sources = layout_for_preset(SlotLayoutPreset::Mobile, "game");
        // All mobile sources should be at front (0,0,1)
        for src in &sources {
            assert_eq!(src.position.azimuth_deg, 0.0);
            assert_eq!(src.position.distance_m, 1.0);
        }
    }

    #[test]
    fn test_vr_standing_has_wider_separation() {
        let reel = zone_position(SlotLayoutPreset::VrStanding, SlotAudioZone::ReelArea);
        let jackpot = zone_position(SlotLayoutPreset::VrStanding, SlotAudioZone::JackpotZone);
        let el_diff = (jackpot.elevation_deg - reel.elevation_deg).abs();
        assert!(el_diff > 30.0, "VR should have significant elevation separation");
    }
}

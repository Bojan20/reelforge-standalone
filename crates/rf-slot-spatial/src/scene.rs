//! T7.2 + T7.3: 3D spatial scene for slot audio events.
//!
//! Defines positions for all audio sources in the slot game.
//! Each event gets spherical coordinates (azimuth, elevation, distance).

use serde::{Deserialize, Serialize};

/// Spherical coordinate position for an audio source.
///
/// Coordinate system (standard audio convention):
/// - Azimuth 0° = front, 90° = right, 180°/-180° = behind, -90° = left
/// - Elevation 0° = horizontal, +90° = directly above, -90° = below
/// - Distance in meters (1.0 = reference distance)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SphericalPosition {
    /// Azimuth angle in degrees (-180 to +180)
    pub azimuth_deg: f32,
    /// Elevation angle in degrees (-90 to +90)
    pub elevation_deg: f32,
    /// Source distance in meters (> 0)
    pub distance_m: f32,
}

impl SphericalPosition {
    pub fn new(azimuth_deg: f32, elevation_deg: f32, distance_m: f32) -> Self {
        Self {
            azimuth_deg: azimuth_deg.clamp(-180.0, 180.0),
            elevation_deg: elevation_deg.clamp(-90.0, 90.0),
            distance_m: distance_m.max(0.01),
        }
    }

    /// Direct front position (0°, 0°, 1m) — default for screen-facing slot
    pub fn front() -> Self { Self::new(0.0, 0.0, 1.0) }

    /// Convert to Cartesian coordinates (x=right, y=up, z=forward)
    pub fn to_cartesian(&self) -> (f32, f32, f32) {
        let az = self.azimuth_deg.to_radians();
        let el = self.elevation_deg.to_radians();
        let r = self.distance_m;
        let x = r * el.cos() * az.sin();
        let y = r * el.sin();
        let z = r * el.cos() * az.cos();
        (x, y, z)
    }
}

impl Default for SphericalPosition {
    fn default() -> Self { Self::front() }
}

/// Distance-based attenuation curve
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AttenuationCurve {
    /// Natural inverse-square law (6 dB per distance doubling)
    InverseSquare,
    /// Linear attenuation (softer rolloff)
    Linear { slope: f32 },
    /// No distance attenuation (ambient/global sources)
    None,
    /// Custom: max_distance before full attenuation
    MaxDistance { max_m: f32 },
}

impl Default for AttenuationCurve {
    fn default() -> Self { AttenuationCurve::InverseSquare }
}

impl AttenuationCurve {
    /// Compute gain multiplier (0.0–1.0) at the given distance.
    pub fn gain_at(&self, distance_m: f32) -> f32 {
        match self {
            Self::None => 1.0,
            Self::InverseSquare => {
                let ref_dist = 1.0_f32;
                (ref_dist / distance_m.max(ref_dist)).powi(2)
            }
            Self::Linear { slope } => {
                (1.0 - slope * (distance_m - 1.0).max(0.0)).clamp(0.0, 1.0)
            }
            Self::MaxDistance { max_m } => {
                (1.0 - distance_m / max_m.max(0.01)).clamp(0.0, 1.0)
            }
        }
    }
}

/// HRTF configuration for a binaural source (T7.3)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HrtfConfig {
    /// Enable HRTF binaural rendering for this source
    pub enabled: bool,
    /// Interpolation quality: 0 = nearest neighbor, 1 = linear, 2 = spherical
    pub interpolation_quality: u8,
    /// Near-field compensation (relevant for sources < 1m)
    pub nearfield_compensation: bool,
}

impl Default for HrtfConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            interpolation_quality: 1,
            nearfield_compensation: false,
        }
    }
}

/// Listener configuration (player's head position)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListenerConfig {
    /// Head position in world space (meters from slot origin)
    pub position: (f32, f32, f32),
    /// Forward direction vector (unit)
    pub forward: (f32, f32, f32),
    /// Up direction vector (unit)
    pub up: (f32, f32, f32),
    /// Head radius in meters (for near-field ITD)
    pub head_radius_m: f32,
}

impl Default for ListenerConfig {
    fn default() -> Self {
        Self {
            position: (0.0, 0.0, -1.5),  // 1.5m behind slot screen
            forward: (0.0, 0.0, 1.0),
            up: (0.0, 1.0, 0.0),
            head_radius_m: 0.0875,        // ITU-T P.58 average
        }
    }
}

/// A single audio source in 3D space
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialAudioSource {
    /// Audio event identifier (matches slot event system)
    pub event_id: String,
    /// Human-readable label
    pub label: String,
    /// Position in 3D space
    pub position: SphericalPosition,
    /// Distance attenuation model
    pub attenuation: AttenuationCurve,
    /// HRTF / binaural config
    pub hrtf: HrtfConfig,
    /// Whether to include in Ambisonics export
    pub include_in_ambisonics: bool,
    /// Base gain (0.0–1.0, pre-spatialization)
    pub gain: f32,
}

impl SpatialAudioSource {
    pub fn new(event_id: impl Into<String>, label: impl Into<String>, position: SphericalPosition) -> Self {
        Self {
            event_id: event_id.into(),
            label: label.into(),
            position,
            attenuation: AttenuationCurve::default(),
            hrtf: HrtfConfig::default(),
            include_in_ambisonics: true,
            gain: 1.0,
        }
    }

    /// Compute the effective gain at the listener (attenuation × base gain)
    pub fn effective_gain(&self) -> f32 {
        self.gain * self.attenuation.gain_at(self.position.distance_m)
    }
}

/// Complete 3D spatial scene for a slot game
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialSlotScene {
    /// Game identifier
    pub game_id: String,
    /// All spatial audio sources
    pub sources: Vec<SpatialAudioSource>,
    /// Listener / player head configuration
    pub listener: ListenerConfig,
    /// Scene description / notes
    pub description: String,
}

impl SpatialSlotScene {
    pub fn new(game_id: impl Into<String>) -> Self {
        Self {
            game_id: game_id.into(),
            sources: Vec::new(),
            listener: ListenerConfig::default(),
            description: String::new(),
        }
    }

    /// Add a source to the scene.
    pub fn add_source(&mut self, source: SpatialAudioSource) {
        self.sources.push(source);
    }

    /// Get a source by event_id.
    pub fn get_source(&self, event_id: &str) -> Option<&SpatialAudioSource> {
        self.sources.iter().find(|s| s.event_id == event_id)
    }

    /// Get mutable source by event_id.
    pub fn get_source_mut(&mut self, event_id: &str) -> Option<&mut SpatialAudioSource> {
        self.sources.iter_mut().find(|s| s.event_id == event_id)
    }

    /// Remove a source by event_id.
    pub fn remove_source(&mut self, event_id: &str) {
        self.sources.retain(|s| s.event_id != event_id);
    }

    /// Number of sources in the scene.
    pub fn source_count(&self) -> usize {
        self.sources.len()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spherical_position_clamps() {
        let pos = SphericalPosition::new(270.0, 180.0, -1.0);
        assert_eq!(pos.azimuth_deg, 180.0);
        assert_eq!(pos.elevation_deg, 90.0);
        assert!(pos.distance_m > 0.0);
    }

    #[test]
    fn test_cartesian_front() {
        let pos = SphericalPosition::front();
        let (x, y, z) = pos.to_cartesian();
        assert!((x).abs() < 1e-5, "front should have x ≈ 0");
        assert!((y).abs() < 1e-5, "front should have y ≈ 0");
        assert!((z - 1.0).abs() < 1e-5, "front should have z ≈ 1");
    }

    #[test]
    fn test_cartesian_right() {
        let pos = SphericalPosition::new(90.0, 0.0, 1.0);
        let (x, _y, z) = pos.to_cartesian();
        assert!(x > 0.9, "90° azimuth should be mostly to the right");
        assert!(z.abs() < 1e-4);
    }

    #[test]
    fn test_inverse_square_attenuation() {
        let att = AttenuationCurve::InverseSquare;
        assert_eq!(att.gain_at(1.0), 1.0);
        // At 2x distance: 1/4 gain
        let g = att.gain_at(2.0);
        assert!((g - 0.25).abs() < 1e-5);
    }

    #[test]
    fn test_no_attenuation() {
        let att = AttenuationCurve::None;
        assert_eq!(att.gain_at(100.0), 1.0);
    }

    #[test]
    fn test_max_distance_attenuation() {
        let att = AttenuationCurve::MaxDistance { max_m: 10.0 };
        assert!((att.gain_at(1.0) - 0.9).abs() < 1e-5);
        assert_eq!(att.gain_at(10.0), 0.0);
        assert_eq!(att.gain_at(20.0), 0.0); // clamp at 0
    }

    #[test]
    fn test_scene_add_and_get_source() {
        let mut scene = SpatialSlotScene::new("phoenix");
        scene.add_source(SpatialAudioSource::new(
            "SPIN_START", "Spin Start", SphericalPosition::front()
        ));
        assert!(scene.get_source("SPIN_START").is_some());
        assert_eq!(scene.source_count(), 1);
    }

    #[test]
    fn test_scene_remove_source() {
        let mut scene = SpatialSlotScene::new("phoenix");
        scene.add_source(SpatialAudioSource::new("A", "A", SphericalPosition::front()));
        scene.add_source(SpatialAudioSource::new("B", "B", SphericalPosition::front()));
        scene.remove_source("A");
        assert!(scene.get_source("A").is_none());
        assert_eq!(scene.source_count(), 1);
    }

    #[test]
    fn test_effective_gain() {
        let mut src = SpatialAudioSource::new("X", "X", SphericalPosition::new(0.0, 0.0, 2.0));
        src.gain = 0.5;
        src.attenuation = AttenuationCurve::InverseSquare;
        // At 2m: attenuation = 0.25, base = 0.5, effective = 0.125
        assert!((src.effective_gain() - 0.125).abs() < 1e-5);
    }
}

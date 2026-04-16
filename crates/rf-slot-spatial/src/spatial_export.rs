//! T7.4: Ambisonics export configuration and manifest.
//!
//! Generates Ambisonics metadata describing how to spatialize each
//! slot audio event in B-format. The actual encoding is done by
//! rf-spatial's AmbisonicEncoder; this module provides the data model
//! and configuration for the export pipeline.

use serde::{Deserialize, Serialize};
use crate::scene::{SpatialSlotScene, SpatialAudioSource, SphericalPosition};

/// Ambisonic order for export
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AmbisonicOrder {
    /// First order (4 channels: W, X, Y, Z) — standard B-format
    First = 1,
    /// Second order (9 channels) — good localization
    Second = 2,
    /// Third order (16 channels) — high quality, VR standard
    Third = 3,
}

impl AmbisonicOrder {
    pub fn channel_count(&self) -> usize {
        let n = *self as usize;
        (n + 1) * (n + 1)
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Self::First  => "1st Order (FOA, 4ch)",
            Self::Second => "2nd Order (SOA, 9ch)",
            Self::Third  => "3rd Order (TOA, 16ch)",
        }
    }
}

/// Output format for spatial export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SpatialExportFormat {
    /// Binaural stereo (L/R headphone render) — T7.3
    Binaural,
    /// First/Second/Third order Ambisonics B-format — T7.4
    Ambisonics(AmbisonicOrder),
    /// Both: generate both binaural and ambisonics versions
    Both(AmbisonicOrder),
}

impl SpatialExportFormat {
    pub fn display_name(&self) -> String {
        match self {
            Self::Binaural => "Binaural (Stereo)".to_string(),
            Self::Ambisonics(order) => format!("Ambisonics {}", order.display_name()),
            Self::Both(order) => format!("Binaural + Ambisonics {}", order.display_name()),
        }
    }
}

/// Configuration for a spatial export run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AmbisonicsExportConfig {
    pub format: SpatialExportFormat,
    /// Sample rate for output files
    pub sample_rate: u32,
    /// Whether to include gain compensation for normalization
    pub normalize_output: bool,
    /// Metadata only mode: generate metadata JSON without rendering audio
    pub metadata_only: bool,
}

impl Default for AmbisonicsExportConfig {
    fn default() -> Self {
        Self {
            format: SpatialExportFormat::Ambisonics(AmbisonicOrder::First),
            sample_rate: 48000,
            normalize_output: true,
            metadata_only: true, // Default: metadata-only until audio render pipeline wired up
        }
    }
}

/// Per-source export specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialSourceSpec {
    pub event_id: String,
    pub label: String,
    pub azimuth_deg: f32,
    pub elevation_deg: f32,
    pub distance_m: f32,
    pub gain: f32,
    pub effective_gain: f32,
    pub include_in_ambisonics: bool,
    /// Ambisonics encoding coefficients (W, X, Y, Z for FOA)
    pub ambisonics_coefficients: AmbisonicsCoefficients,
}

/// B-format Ambisonics encoding coefficients for a source position.
///
/// First-order encoding: ACN channel ordering, SN3D normalization.
/// - W = 1/sqrt(2) × gain
/// - X = cos(az) × cos(el) × gain
/// - Y = sin(az) × cos(el) × gain
/// - Z = sin(el) × gain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AmbisonicsCoefficients {
    /// Channel W (omnidirectional)
    pub w: f32,
    /// Channel X (front-back)
    pub x: f32,
    /// Channel Y (left-right)
    pub y: f32,
    /// Channel Z (up-down)
    pub z: f32,
    /// Higher-order coefficients (empty for FOA)
    pub higher_order: Vec<f32>,
}

impl AmbisonicsCoefficients {
    /// Compute first-order SN3D coefficients for a spherical position.
    pub fn from_position_foa(pos: &SphericalPosition, gain: f32) -> Self {
        let az = pos.azimuth_deg.to_radians();
        let el = pos.elevation_deg.to_radians();
        let g = gain;

        // SN3D normalization, ACN ordering
        let w = (1.0_f32 / 2.0_f32.sqrt()) * g;
        let y = az.sin() * el.cos() * g;   // ACN 1
        let z = el.sin() * g;               // ACN 2
        let x = az.cos() * el.cos() * g;   // ACN 3

        Self { w, x, y, z, higher_order: vec![] }
    }

    /// Compute up to third-order SN3D coefficients.
    pub fn from_position_hoa(pos: &SphericalPosition, gain: f32, order: AmbisonicOrder) -> Self {
        let az = pos.azimuth_deg.to_radians();
        let el = pos.elevation_deg.to_radians();
        let cos_el = el.cos();
        let sin_el = el.sin();
        let g = gain;

        // ACN/SN3D — compute all channels up to `order`
        let n_channels = order.channel_count();
        let mut coeffs = vec![0.0_f32; n_channels];

        // Order 0 (W)
        coeffs[0] = (1.0_f32 / 2.0_f32.sqrt()) * g;

        // Order 1
        if order as usize >= 1 {
            coeffs[1] = az.sin() * cos_el * g;             // Y
            coeffs[2] = sin_el * g;                         // Z
            coeffs[3] = az.cos() * cos_el * g;             // X
        }

        // Precompute multi-angle values (used in order 2 and 3)
        let cos2az = (2.0 * az).cos();
        let sin2az = (2.0 * az).sin();

        // Order 2
        if order as usize >= 2 {
            coeffs[4] = (3.0_f32.sqrt() / 2.0) * sin2az * cos_el.powi(2) * g;
            coeffs[5] = (3.0_f32.sqrt() / 2.0) * az.sin() * (2.0 * sin_el) * cos_el * g;
            coeffs[6] = 0.5 * (3.0 * sin_el.powi(2) - 1.0) * g;
            coeffs[7] = (3.0_f32.sqrt() / 2.0) * az.cos() * (2.0 * sin_el) * cos_el * g;
            coeffs[8] = (3.0_f32.sqrt() / 2.0) * cos2az * cos_el.powi(2) * g;
        }

        // Order 3 — standard real spherical harmonics (SN3D normalization)
        if order as usize >= 3 && n_channels >= 16 {
            let cos3az = (3.0 * az).cos();
            let sin3az = (3.0 * az).sin();
            let c = cos_el; let s = sin_el;
            coeffs[9]  = (5.0_f32.sqrt() * 0.5) * sin3az * c.powi(3) * g;
            coeffs[10] = (15.0_f32.sqrt() * 0.5) * sin2az * s * c.powi(2) * g;
            coeffs[11] = (3.0_f32 / 8.0).sqrt() * az.sin() * c * (5.0 * s.powi(2) - 1.0) * g;
            coeffs[12] = 0.5 * s * (5.0 * s.powi(2) - 3.0) * g;
            coeffs[13] = (3.0_f32 / 8.0).sqrt() * az.cos() * c * (5.0 * s.powi(2) - 1.0) * g;
            coeffs[14] = (15.0_f32.sqrt() * 0.5) * cos2az * s * c.powi(2) * g;
            coeffs[15] = (5.0_f32.sqrt() * 0.5) * cos3az * c.powi(3) * g;
        }

        Self {
            w: coeffs[0],
            x: if n_channels > 3 { coeffs[3] } else { 0.0 },
            y: if n_channels > 1 { coeffs[1] } else { 0.0 },
            z: if n_channels > 2 { coeffs[2] } else { 0.0 },
            higher_order: if n_channels > 4 { coeffs[4..].to_vec() } else { vec![] },
        }
    }
}

/// Complete result of a spatial export operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialExportResult {
    pub event_id: String,
    pub binaural_coefficients: Option<BinauralCoefficients>,
    pub ambisonics_coefficients: Option<AmbisonicsCoefficients>,
    pub gain: f32,
}

/// ITD/ILD binaural coefficients for a source (T7.3)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BinauralCoefficients {
    /// Interaural Time Difference in samples (at 48kHz)
    pub itd_samples: f32,
    /// Interaural Level Difference in dB
    pub ild_db: f32,
    /// Left channel gain
    pub left_gain: f32,
    /// Right channel gain
    pub right_gain: f32,
}

impl BinauralCoefficients {
    /// Compute ITD/ILD using the Woodworth spherical head model.
    ///
    /// head_radius_m: typically 0.0875m (ITU-T P.58)
    pub fn from_position(pos: &SphericalPosition, head_radius_m: f32, gain: f32) -> Self {
        const SPEED_OF_SOUND: f32 = 343.0; // m/s
        const SAMPLE_RATE: f32 = 48000.0;

        let az = pos.azimuth_deg.to_radians();
        let r = head_radius_m;

        // Woodworth formula: ITD = (r/c) * (az + sin(az))
        let itd_s = (r / SPEED_OF_SOUND) * (az + az.sin());
        let itd_samples = itd_s * SAMPLE_RATE;

        // Simple ILD model: |az| → level difference
        // At 90°: ~6 dB ILD. At 0°: 0 dB.
        let ild_db = 6.0 * (az.abs() / std::f32::consts::FRAC_PI_2).min(1.0);

        // Constant-power panning: at az=0 both L and R = cos(PI/4) = sqrt(2)/2
        // pan angle maps [-PI, +PI] azimuth → [-PI/4, +PI/4] panning angle
        let pan_angle = az.clamp(-std::f32::consts::FRAC_PI_2, std::f32::consts::FRAC_PI_2) / 2.0;
        // pan_angle > 0 = right: R increases, L decreases
        let pan_r = (std::f32::consts::FRAC_PI_4 - pan_angle).cos().clamp(0.0, 1.0);
        let pan_l = (std::f32::consts::FRAC_PI_4 + pan_angle).cos().clamp(0.0, 1.0);

        Self {
            itd_samples,
            ild_db,
            left_gain: pan_l * gain,
            right_gain: pan_r * gain,
        }
    }
}

/// Full export manifest for a scene
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialExportManifest {
    pub game_id: String,
    pub format: String,
    pub order_name: String,
    pub channel_count: usize,
    pub source_count: usize,
    pub sources: Vec<SpatialSourceSpec>,
    pub generated_at: String,
    pub config: AmbisonicsExportConfig,
}

impl SpatialExportManifest {
    /// Build export manifest from a scene.
    pub fn build(
        scene: &SpatialSlotScene,
        config: &AmbisonicsExportConfig,
        generated_at: &str,
    ) -> Self {
        let order = match &config.format {
            SpatialExportFormat::Binaural => None,
            SpatialExportFormat::Ambisonics(o) => Some(*o),
            SpatialExportFormat::Both(o) => Some(*o),
        };

        let channel_count = order.map(|o| o.channel_count()).unwrap_or(2);
        let order_name = config.format.display_name();

        let sources: Vec<SpatialSourceSpec> = scene.sources.iter()
            .filter(|s| s.include_in_ambisonics || matches!(config.format, SpatialExportFormat::Binaural))
            .map(|src| build_source_spec(src, order, config))
            .collect();

        Self {
            game_id: scene.game_id.clone(),
            format: order_name.clone(),
            order_name,
            channel_count,
            source_count: sources.len(),
            sources,
            generated_at: generated_at.to_string(),
            config: config.clone(),
        }
    }
}

fn build_source_spec(
    src: &SpatialAudioSource,
    order: Option<AmbisonicOrder>,
    _config: &AmbisonicsExportConfig,
) -> SpatialSourceSpec {
    let eff_gain = src.effective_gain();
    let coeffs = match order {
        Some(AmbisonicOrder::First) =>
            AmbisonicsCoefficients::from_position_foa(&src.position, eff_gain),
        Some(o) =>
            AmbisonicsCoefficients::from_position_hoa(&src.position, eff_gain, o),
        None =>
            AmbisonicsCoefficients::from_position_foa(&src.position, eff_gain),
    };

    SpatialSourceSpec {
        event_id: src.event_id.clone(),
        label: src.label.clone(),
        azimuth_deg: src.position.azimuth_deg,
        elevation_deg: src.position.elevation_deg,
        distance_m: src.position.distance_m,
        gain: src.gain,
        effective_gain: eff_gain,
        include_in_ambisonics: src.include_in_ambisonics,
        ambisonics_coefficients: coeffs,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene::{SpatialSlotScene, SpatialAudioSource, SphericalPosition};

    #[test]
    fn test_foa_channel_count() {
        assert_eq!(AmbisonicOrder::First.channel_count(), 4);
        assert_eq!(AmbisonicOrder::Second.channel_count(), 9);
        assert_eq!(AmbisonicOrder::Third.channel_count(), 16);
    }

    #[test]
    fn test_foa_front_source_has_max_w() {
        let pos = SphericalPosition::front();
        let coeffs = AmbisonicsCoefficients::from_position_foa(&pos, 1.0);
        // Front source: W = 1/sqrt(2), X = 1, Y = 0, Z = 0
        assert!((coeffs.w - 1.0_f32 / 2.0_f32.sqrt()).abs() < 1e-5);
        assert!((coeffs.x - 1.0).abs() < 1e-5);
        assert!(coeffs.y.abs() < 1e-5);
        assert!(coeffs.z.abs() < 1e-5);
    }

    #[test]
    fn test_foa_right_source() {
        let pos = SphericalPosition::new(90.0, 0.0, 1.0);
        let coeffs = AmbisonicsCoefficients::from_position_foa(&pos, 1.0);
        // At 90° azimuth: Y ≈ 1, X ≈ 0
        assert!(coeffs.y > 0.9);
        assert!(coeffs.x.abs() < 1e-4);
    }

    #[test]
    fn test_hoa_third_order_coefficient_count() {
        let pos = SphericalPosition::front();
        let coeffs = AmbisonicsCoefficients::from_position_hoa(&pos, 1.0, AmbisonicOrder::Third);
        // W + X + Y + Z + 12 higher-order = 16 total
        let total = 4 + coeffs.higher_order.len();
        assert_eq!(total, 16);
    }

    #[test]
    fn test_binaural_front_source_equal_panning() {
        let pos = SphericalPosition::front();
        let coeff = BinauralCoefficients::from_position(&pos, 0.0875, 1.0);
        assert!((coeff.left_gain - coeff.right_gain).abs() < 0.01, "Front: L ≈ R");
        assert!((coeff.itd_samples).abs() < 1e-3, "Front: ITD ≈ 0");
    }

    #[test]
    fn test_binaural_right_source_has_positive_ild() {
        let pos = SphericalPosition::new(90.0, 0.0, 1.0);
        let coeff = BinauralCoefficients::from_position(&pos, 0.0875, 1.0);
        assert!(coeff.ild_db > 0.0);
        assert!(coeff.right_gain > coeff.left_gain, "Right source: R gain > L gain");
    }

    #[test]
    fn test_manifest_builds_for_scene() {
        let mut scene = SpatialSlotScene::new("phoenix");
        scene.add_source(SpatialAudioSource::new(
            "SPIN_START", "Spin", SphericalPosition::front()
        ));
        scene.add_source(SpatialAudioSource::new(
            "WIN_5", "Jackpot", SphericalPosition::new(0.0, 60.0, 2.0)
        ));

        let config = AmbisonicsExportConfig::default();
        let manifest = SpatialExportManifest::build(&scene, &config, "2026-04-16T12:00:00Z");
        assert_eq!(manifest.source_count, 2);
        assert_eq!(manifest.channel_count, 4); // FOA
    }

    #[test]
    fn test_third_order_manifest() {
        let mut scene = SpatialSlotScene::new("game_x");
        scene.add_source(SpatialAudioSource::new("A", "A", SphericalPosition::front()));

        let config = AmbisonicsExportConfig {
            format: SpatialExportFormat::Ambisonics(AmbisonicOrder::Third),
            ..Default::default()
        };
        let manifest = SpatialExportManifest::build(&scene, &config, "2026-01-01");
        assert_eq!(manifest.channel_count, 16);
        // Higher-order coefficients present
        assert_eq!(
            manifest.sources[0].ambisonics_coefficients.higher_order.len(),
            12 // 16 total - 4 (W, X, Y, Z)
        );
    }
}

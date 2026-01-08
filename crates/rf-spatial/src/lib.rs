//! ReelForge Immersive Audio Engine
//!
//! Industry-leading spatial audio processing:
//!
//! ## Dolby Atmos
//! - Object-based audio (up to 128 objects)
//! - 7.1.4 bed rendering
//! - ADM metadata handling
//! - Height channels and overhead speakers
//!
//! ## Higher-Order Ambisonics (HOA)
//! - Up to 7th order (64 channels)
//! - SN3D/N3D/FuMa normalization
//! - ACN channel ordering
//! - Real-time rotation and transformation
//! - Binaural decode with HRTF
//!
//! ## MPEG-H 3D Audio
//! - Scene-based audio
//! - Personalized rendering
//! - Loudness and DRC metadata
//!
//! ## Binaural Processing
//! - HRTF convolution (SOFA support)
//! - ITD/ILD modeling
//! - Head tracking integration
//! - Cross-talk cancellation
//!
//! ## Room Simulation
//! - Ray tracing reverb
//! - Early reflections modeling
//! - Late reverb with diffusion
//! - Material absorption coefficients

#![allow(missing_docs)]
#![allow(dead_code)]

pub mod atmos;
pub mod binaural;
pub mod hoa;
pub mod mpeg_h;
pub mod room;

mod error;
mod position;

pub use error::{SpatialError, SpatialResult};
pub use position::{Position3D, Orientation, SphericalCoord, CartesianCoord};

use serde::{Deserialize, Serialize};

/// Speaker layout configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeakerLayout {
    /// Layout name
    pub name: String,
    /// Speaker positions
    pub speakers: Vec<Speaker>,
    /// Has LFE channel
    pub has_lfe: bool,
    /// Number of height layers
    pub height_layers: usize,
}

/// Single speaker definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Speaker {
    /// Speaker label (e.g., "L", "R", "C", "Lss")
    pub label: String,
    /// Position in space
    pub position: Position3D,
    /// Channel index
    pub channel: usize,
    /// Is this a subwoofer/LFE
    pub is_lfe: bool,
}

impl SpeakerLayout {
    /// Stereo (2.0)
    pub fn stereo() -> Self {
        Self {
            name: "Stereo".into(),
            speakers: vec![
                Speaker::new("L", Position3D::from_spherical(-30.0, 0.0, 1.0), 0),
                Speaker::new("R", Position3D::from_spherical(30.0, 0.0, 1.0), 1),
            ],
            has_lfe: false,
            height_layers: 0,
        }
    }

    /// 5.1 Surround
    pub fn surround_5_1() -> Self {
        Self {
            name: "5.1".into(),
            speakers: vec![
                Speaker::new("L", Position3D::from_spherical(-30.0, 0.0, 1.0), 0),
                Speaker::new("R", Position3D::from_spherical(30.0, 0.0, 1.0), 1),
                Speaker::new("C", Position3D::from_spherical(0.0, 0.0, 1.0), 2),
                Speaker::new_lfe("LFE", 3),
                Speaker::new("Ls", Position3D::from_spherical(-110.0, 0.0, 1.0), 4),
                Speaker::new("Rs", Position3D::from_spherical(110.0, 0.0, 1.0), 5),
            ],
            has_lfe: true,
            height_layers: 0,
        }
    }

    /// 7.1 Surround
    pub fn surround_7_1() -> Self {
        Self {
            name: "7.1".into(),
            speakers: vec![
                Speaker::new("L", Position3D::from_spherical(-30.0, 0.0, 1.0), 0),
                Speaker::new("R", Position3D::from_spherical(30.0, 0.0, 1.0), 1),
                Speaker::new("C", Position3D::from_spherical(0.0, 0.0, 1.0), 2),
                Speaker::new_lfe("LFE", 3),
                Speaker::new("Lss", Position3D::from_spherical(-90.0, 0.0, 1.0), 4),
                Speaker::new("Rss", Position3D::from_spherical(90.0, 0.0, 1.0), 5),
                Speaker::new("Lsr", Position3D::from_spherical(-135.0, 0.0, 1.0), 6),
                Speaker::new("Rsr", Position3D::from_spherical(135.0, 0.0, 1.0), 7),
            ],
            has_lfe: true,
            height_layers: 0,
        }
    }

    /// 7.1.4 Atmos (base config)
    pub fn atmos_7_1_4() -> Self {
        Self {
            name: "7.1.4".into(),
            speakers: vec![
                // Bed layer
                Speaker::new("L", Position3D::from_spherical(-30.0, 0.0, 1.0), 0),
                Speaker::new("R", Position3D::from_spherical(30.0, 0.0, 1.0), 1),
                Speaker::new("C", Position3D::from_spherical(0.0, 0.0, 1.0), 2),
                Speaker::new_lfe("LFE", 3),
                Speaker::new("Lss", Position3D::from_spherical(-90.0, 0.0, 1.0), 4),
                Speaker::new("Rss", Position3D::from_spherical(90.0, 0.0, 1.0), 5),
                Speaker::new("Lsr", Position3D::from_spherical(-135.0, 0.0, 1.0), 6),
                Speaker::new("Rsr", Position3D::from_spherical(135.0, 0.0, 1.0), 7),
                // Height layer
                Speaker::new("Ltf", Position3D::from_spherical(-45.0, 45.0, 1.0), 8),
                Speaker::new("Rtf", Position3D::from_spherical(45.0, 45.0, 1.0), 9),
                Speaker::new("Ltr", Position3D::from_spherical(-135.0, 45.0, 1.0), 10),
                Speaker::new("Rtr", Position3D::from_spherical(135.0, 45.0, 1.0), 11),
            ],
            has_lfe: true,
            height_layers: 1,
        }
    }

    /// 9.1.6 Atmos (theatrical)
    pub fn atmos_9_1_6() -> Self {
        Self {
            name: "9.1.6".into(),
            speakers: vec![
                // Bed layer
                Speaker::new("L", Position3D::from_spherical(-30.0, 0.0, 1.0), 0),
                Speaker::new("R", Position3D::from_spherical(30.0, 0.0, 1.0), 1),
                Speaker::new("C", Position3D::from_spherical(0.0, 0.0, 1.0), 2),
                Speaker::new_lfe("LFE", 3),
                Speaker::new("Lw", Position3D::from_spherical(-60.0, 0.0, 1.0), 4),
                Speaker::new("Rw", Position3D::from_spherical(60.0, 0.0, 1.0), 5),
                Speaker::new("Lss", Position3D::from_spherical(-90.0, 0.0, 1.0), 6),
                Speaker::new("Rss", Position3D::from_spherical(90.0, 0.0, 1.0), 7),
                Speaker::new("Lsr", Position3D::from_spherical(-135.0, 0.0, 1.0), 8),
                Speaker::new("Rsr", Position3D::from_spherical(135.0, 0.0, 1.0), 9),
                // Height layer
                Speaker::new("Ltf", Position3D::from_spherical(-45.0, 45.0, 1.0), 10),
                Speaker::new("Rtf", Position3D::from_spherical(45.0, 45.0, 1.0), 11),
                Speaker::new("Ltm", Position3D::from_spherical(-90.0, 45.0, 1.0), 12),
                Speaker::new("Rtm", Position3D::from_spherical(90.0, 45.0, 1.0), 13),
                Speaker::new("Ltr", Position3D::from_spherical(-135.0, 45.0, 1.0), 14),
                Speaker::new("Rtr", Position3D::from_spherical(135.0, 45.0, 1.0), 15),
            ],
            has_lfe: true,
            height_layers: 1,
        }
    }

    /// Get number of channels (excluding LFE)
    pub fn channel_count(&self) -> usize {
        self.speakers.iter().filter(|s| !s.is_lfe).count()
    }

    /// Get total channel count (including LFE)
    pub fn total_channels(&self) -> usize {
        self.speakers.len()
    }
}

impl Speaker {
    /// Create new speaker
    pub fn new(label: &str, position: Position3D, channel: usize) -> Self {
        Self {
            label: label.to_string(),
            position,
            channel,
            is_lfe: false,
        }
    }

    /// Create LFE speaker
    pub fn new_lfe(label: &str, channel: usize) -> Self {
        Self {
            label: label.to_string(),
            position: Position3D::origin(),
            channel,
            is_lfe: true,
        }
    }
}

/// Audio source in 3D space
#[derive(Debug, Clone)]
pub struct AudioObject {
    /// Unique identifier
    pub id: u32,
    /// Object name
    pub name: String,
    /// Current position
    pub position: Position3D,
    /// Size/spread (0 = point source, 1 = diffuse)
    pub size: f32,
    /// Gain (linear)
    pub gain: f32,
    /// Audio data (mono)
    pub audio: Vec<f32>,
    /// Sample rate
    pub sample_rate: u32,
    /// Automation data for position
    pub automation: Option<PositionAutomation>,
}

/// Position automation over time
#[derive(Debug, Clone)]
pub struct PositionAutomation {
    /// Keyframes: (time_samples, position)
    pub keyframes: Vec<(u64, Position3D)>,
    /// Interpolation type
    pub interpolation: InterpolationType,
}

/// Interpolation type for automation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InterpolationType {
    /// Linear interpolation
    Linear,
    /// Cubic spline
    Cubic,
    /// Hold previous value
    Step,
}

impl PositionAutomation {
    /// Get position at sample
    pub fn position_at(&self, sample: u64) -> Option<Position3D> {
        if self.keyframes.is_empty() {
            return None;
        }

        // Find surrounding keyframes
        let mut prev = &self.keyframes[0];
        let mut next = prev;

        for kf in &self.keyframes {
            if kf.0 <= sample {
                prev = kf;
            }
            if kf.0 >= sample {
                next = kf;
                break;
            }
        }

        // Interpolate
        match self.interpolation {
            InterpolationType::Step => Some(prev.1.clone()),
            InterpolationType::Linear => {
                if prev.0 == next.0 {
                    return Some(prev.1.clone());
                }
                let t = (sample - prev.0) as f64 / (next.0 - prev.0) as f64;
                Some(prev.1.lerp(&next.1, t as f32))
            }
            InterpolationType::Cubic => {
                // Simplified cubic - would need more keyframes for proper spline
                let t = if prev.0 == next.0 {
                    0.0
                } else {
                    (sample - prev.0) as f64 / (next.0 - prev.0) as f64
                };
                // Smoothstep
                let t = t * t * (3.0 - 2.0 * t);
                Some(prev.1.lerp(&next.1, t as f32))
            }
        }
    }
}

impl Default for AudioObject {
    fn default() -> Self {
        Self {
            id: 0,
            name: "Object".into(),
            position: Position3D::origin(),
            size: 0.0,
            gain: 1.0,
            audio: Vec::new(),
            sample_rate: 48000,
            automation: None,
        }
    }
}

/// Spatial audio renderer trait
pub trait SpatialRenderer: Send + Sync {
    /// Render objects to speaker layout
    fn render(
        &mut self,
        objects: &[AudioObject],
        output: &mut [f32],
        output_channels: usize,
    ) -> SpatialResult<()>;

    /// Get output speaker layout
    fn output_layout(&self) -> &SpeakerLayout;

    /// Set listener position (for binaural)
    fn set_listener_position(&mut self, position: Position3D, orientation: Orientation);

    /// Get latency in samples
    fn latency_samples(&self) -> usize;

    /// Reset internal state
    fn reset(&mut self);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_speaker_layouts() {
        let stereo = SpeakerLayout::stereo();
        assert_eq!(stereo.total_channels(), 2);
        assert!(!stereo.has_lfe);

        let surround = SpeakerLayout::surround_5_1();
        assert_eq!(surround.total_channels(), 6);
        assert!(surround.has_lfe);

        let atmos = SpeakerLayout::atmos_7_1_4();
        assert_eq!(atmos.total_channels(), 12);
        assert_eq!(atmos.height_layers, 1);
    }

    #[test]
    fn test_position_automation() {
        let automation = PositionAutomation {
            keyframes: vec![
                (0, Position3D::new(-1.0, 0.0, 0.0)),
                (1000, Position3D::new(1.0, 0.0, 0.0)),
            ],
            interpolation: InterpolationType::Linear,
        };

        let pos = automation.position_at(500).unwrap();
        assert!((pos.x - 0.0).abs() < 0.1);
    }
}

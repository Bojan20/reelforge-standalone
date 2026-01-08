//! ADM (Audio Definition Model) metadata for Atmos

use serde::{Deserialize, Serialize};
use crate::position::Position3D;

/// ADM metadata container
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AdmMetadata {
    /// Programme (mix) metadata
    pub programme: Programme,
    /// Content metadata
    pub contents: Vec<Content>,
    /// Object metadata
    pub objects: Vec<ObjectMetadata>,
}

/// Programme metadata
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Programme {
    /// Programme name
    pub name: String,
    /// Language
    pub language: String,
    /// Start time (seconds)
    pub start: f64,
    /// End time (seconds)
    pub end: f64,
    /// Loudness (LUFS)
    pub loudness_integrated: Option<f32>,
}

/// Content group metadata
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Content {
    /// Content name
    pub name: String,
    /// Content type
    pub content_type: ContentType,
    /// Dialogue flag
    pub is_dialogue: bool,
}

/// Content type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ContentType {
    /// Main dialogue
    #[default]
    Dialogue,
    /// Music
    Music,
    /// Effects
    Effects,
    /// Voice-over
    VoiceOver,
    /// Commentary
    Commentary,
    /// Emergency
    Emergency,
}

/// Object metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectMetadata {
    /// Object ID
    pub id: u32,
    /// Object name
    pub name: String,
    /// Position (normalized)
    pub position: Position3D,
    /// Gain (linear)
    pub gain: f32,
    /// Size (0 = point, 1 = diffuse)
    pub size: f32,
    /// Width (horizontal spread)
    pub width: f32,
    /// Height (vertical spread)
    pub height: f32,
    /// Depth (front-back spread)
    pub depth: f32,
    /// Divergence
    pub divergence: f32,
    /// Screen reference
    pub screen_ref: bool,
    /// Importance (for downmixing)
    pub importance: u8,
    /// Start time (samples)
    pub start_sample: u64,
    /// Duration (samples)
    pub duration_samples: u64,
    /// Position blocks for automation
    pub position_blocks: Vec<PositionBlock>,
}

impl Default for ObjectMetadata {
    fn default() -> Self {
        Self {
            id: 0,
            name: "Object".into(),
            position: Position3D::origin(),
            gain: 1.0,
            size: 0.0,
            width: 0.0,
            height: 0.0,
            depth: 0.0,
            divergence: 0.0,
            screen_ref: false,
            importance: 10,
            start_sample: 0,
            duration_samples: 0,
            position_blocks: Vec::new(),
        }
    }
}

/// Position automation block
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PositionBlock {
    /// Start time (samples)
    pub start_sample: u64,
    /// Duration (samples)
    pub duration_samples: u64,
    /// Position
    pub position: Position3D,
    /// Interpolation type
    pub interpolation: InterpolationType,
}

/// Interpolation type for position
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum InterpolationType {
    /// Linear interpolation
    #[default]
    Linear,
    /// Jump to position (no interpolation)
    Jump,
    /// Spline interpolation
    Spline,
}

impl AdmMetadata {
    /// Create new ADM metadata
    pub fn new() -> Self {
        Self::default()
    }

    /// Add object
    pub fn add_object(&mut self, object: ObjectMetadata) {
        self.objects.push(object);
    }

    /// Get object by ID
    pub fn get_object(&self, id: u32) -> Option<&ObjectMetadata> {
        self.objects.iter().find(|o| o.id == id)
    }

    /// Get mutable object by ID
    pub fn get_object_mut(&mut self, id: u32) -> Option<&mut ObjectMetadata> {
        self.objects.iter_mut().find(|o| o.id == id)
    }

    /// Get object position at time
    pub fn object_position_at(&self, id: u32, sample: u64) -> Option<Position3D> {
        let obj = self.get_object(id)?;

        if obj.position_blocks.is_empty() {
            return Some(obj.position);
        }

        // Find surrounding blocks
        let mut prev_block: Option<&PositionBlock> = None;
        let mut next_block: Option<&PositionBlock> = None;

        for block in &obj.position_blocks {
            if block.start_sample <= sample {
                prev_block = Some(block);
            }
            if block.start_sample >= sample && next_block.is_none() {
                next_block = Some(block);
            }
        }

        match (prev_block, next_block) {
            (Some(prev), Some(next)) => {
                if prev.start_sample == next.start_sample {
                    return Some(prev.position);
                }

                let t = (sample - prev.start_sample) as f32
                    / (next.start_sample - prev.start_sample) as f32;

                match prev.interpolation {
                    InterpolationType::Jump => Some(prev.position),
                    InterpolationType::Linear => Some(prev.position.lerp(&next.position, t)),
                    InterpolationType::Spline => {
                        // Simplified smoothstep
                        let t_smooth = t * t * (3.0 - 2.0 * t);
                        Some(prev.position.lerp(&next.position, t_smooth))
                    }
                }
            }
            (Some(prev), None) => Some(prev.position),
            (None, Some(next)) => Some(next.position),
            (None, None) => Some(obj.position),
        }
    }

    /// Export to JSON
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    /// Import from JSON
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_adm_creation() {
        let mut adm = AdmMetadata::new();

        adm.add_object(ObjectMetadata {
            id: 1,
            name: "Dialog".into(),
            position: Position3D::new(0.0, 1.0, 0.0),
            ..Default::default()
        });

        assert_eq!(adm.objects.len(), 1);
        assert!(adm.get_object(1).is_some());
    }

    #[test]
    fn test_position_interpolation() {
        let mut adm = AdmMetadata::new();

        let mut obj = ObjectMetadata {
            id: 1,
            name: "Moving".into(),
            ..Default::default()
        };

        obj.position_blocks = vec![
            PositionBlock {
                start_sample: 0,
                duration_samples: 1000,
                position: Position3D::new(-1.0, 0.0, 0.0),
                interpolation: InterpolationType::Linear,
            },
            PositionBlock {
                start_sample: 1000,
                duration_samples: 0,
                position: Position3D::new(1.0, 0.0, 0.0),
                interpolation: InterpolationType::Linear,
            },
        ];

        adm.add_object(obj);

        // Test interpolation at midpoint
        let pos = adm.object_position_at(1, 500).unwrap();
        assert!((pos.x - 0.0).abs() < 0.01);
    }

    #[test]
    fn test_json_roundtrip() {
        let mut adm = AdmMetadata::new();
        adm.programme.name = "Test Mix".into();
        adm.add_object(ObjectMetadata {
            id: 1,
            name: "Voice".into(),
            ..Default::default()
        });

        let json = adm.to_json().unwrap();
        let restored = AdmMetadata::from_json(&json).unwrap();

        assert_eq!(restored.programme.name, "Test Mix");
        assert_eq!(restored.objects.len(), 1);
    }
}

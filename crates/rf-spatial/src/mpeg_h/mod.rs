//! MPEG-H 3D Audio processing
//!
//! MPEG-H Audio implementation:
//! - Scene-based audio description
//! - Personalized rendering
//! - Loudness and DRC metadata
//! - Interactivity support

use serde::{Deserialize, Serialize};
use crate::error::SpatialResult;
use crate::position::Position3D;

/// MPEG-H audio scene
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MpegHScene {
    /// Scene ID
    pub id: u32,
    /// Scene description
    pub description: String,
    /// Audio elements in scene
    pub elements: Vec<AudioElement>,
    /// Switch groups (for interactivity)
    pub switch_groups: Vec<SwitchGroup>,
    /// Preset switches
    pub presets: Vec<Preset>,
    /// Loudness metadata
    pub loudness: LoudnessMetadata,
}

/// Audio element in MPEG-H scene
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioElement {
    /// Element ID
    pub id: u32,
    /// Element type
    pub element_type: ElementType,
    /// Element name
    pub name: String,
    /// Language code
    pub language: Option<String>,
    /// Default gain (dB)
    pub default_gain_db: f32,
    /// Gain range (min, max) in dB
    pub gain_range: (f32, f32),
    /// Position (for objects)
    pub position: Option<Position3D>,
    /// Importance (1-10)
    pub importance: u8,
    /// Is default on
    pub default_on: bool,
    /// Allow gain change
    pub allow_gain_change: bool,
    /// Allow position change
    pub allow_position_change: bool,
}

impl Default for AudioElement {
    fn default() -> Self {
        Self {
            id: 0,
            element_type: ElementType::Object,
            name: "Element".into(),
            language: None,
            default_gain_db: 0.0,
            gain_range: (-12.0, 12.0),
            position: None,
            importance: 5,
            default_on: true,
            allow_gain_change: true,
            allow_position_change: false,
        }
    }
}

/// Element type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ElementType {
    /// Channel-based (bed)
    Channel,
    /// Object-based
    #[default]
    Object,
    /// Higher-order ambisonics
    Hoa,
}

/// Switch group for mutually exclusive elements
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwitchGroup {
    /// Group ID
    pub id: u32,
    /// Group name
    pub name: String,
    /// Member element IDs
    pub members: Vec<u32>,
    /// Default member
    pub default_member: u32,
    /// Allow "off" selection
    pub allow_off: bool,
}

/// Preset configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Preset {
    /// Preset ID
    pub id: u32,
    /// Preset name
    pub name: String,
    /// Element gains (element_id -> gain_db)
    pub element_gains: Vec<(u32, f32)>,
    /// Switch group selections (group_id -> selected_element_id)
    pub switch_selections: Vec<(u32, u32)>,
}

/// Loudness metadata per MPEG-H
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LoudnessMetadata {
    /// Integrated loudness (LUFS)
    pub integrated_loudness: f32,
    /// Dialogue loudness (LUFS)
    pub dialogue_loudness: f32,
    /// Loudness range (LU)
    pub loudness_range: f32,
    /// True peak (dBTP)
    pub true_peak: f32,
    /// DRC profile
    pub drc_profile: DrcProfile,
}

/// DRC (Dynamic Range Control) profile
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum DrcProfile {
    /// No DRC
    #[default]
    None,
    /// Film standard
    FilmStandard,
    /// Film light
    FilmLight,
    /// Music standard
    MusicStandard,
    /// Music light
    MusicLight,
    /// Speech
    Speech,
    /// Night mode (heavy compression)
    NightMode,
    /// Limited range (for noisy environments)
    LimitedRange,
}

impl MpegHScene {
    /// Create new scene
    pub fn new(id: u32) -> Self {
        Self {
            id,
            ..Default::default()
        }
    }

    /// Add audio element
    pub fn add_element(&mut self, element: AudioElement) {
        self.elements.push(element);
    }

    /// Add switch group
    pub fn add_switch_group(&mut self, group: SwitchGroup) {
        self.switch_groups.push(group);
    }

    /// Add preset
    pub fn add_preset(&mut self, preset: Preset) {
        self.presets.push(preset);
    }

    /// Get element by ID
    pub fn get_element(&self, id: u32) -> Option<&AudioElement> {
        self.elements.iter().find(|e| e.id == id)
    }

    /// Apply preset
    pub fn apply_preset(&self, preset_id: u32) -> Option<Vec<(u32, f32)>> {
        let preset = self.presets.iter().find(|p| p.id == preset_id)?;
        Some(preset.element_gains.clone())
    }
}

/// MPEG-H renderer configuration
#[derive(Debug, Clone)]
pub struct MpegHConfig {
    /// Target loudness (LUFS)
    pub target_loudness: f32,
    /// Enable DRC
    pub enable_drc: bool,
    /// DRC profile override
    pub drc_profile: Option<DrcProfile>,
    /// Personalization gains (element_id -> gain_db)
    pub personalization: Vec<(u32, f32)>,
    /// Active switch selections
    pub switch_selections: Vec<(u32, u32)>,
}

impl Default for MpegHConfig {
    fn default() -> Self {
        Self {
            target_loudness: -24.0,
            enable_drc: true,
            drc_profile: None,
            personalization: Vec::new(),
            switch_selections: Vec::new(),
        }
    }
}

/// MPEG-H scene renderer
pub struct MpegHRenderer {
    /// Scene
    scene: MpegHScene,
    /// Configuration
    config: MpegHConfig,
    /// Element gains (computed from config)
    element_gains: Vec<(u32, f32)>,
    /// Sample rate
    sample_rate: u32,
}

impl MpegHRenderer {
    /// Create new renderer
    pub fn new(scene: MpegHScene, config: MpegHConfig, sample_rate: u32) -> Self {
        let mut renderer = Self {
            scene,
            config,
            element_gains: Vec::new(),
            sample_rate,
        };
        renderer.update_gains();
        renderer
    }

    /// Update configuration
    pub fn set_config(&mut self, config: MpegHConfig) {
        self.config = config;
        self.update_gains();
    }

    /// Set personalization gain for element
    pub fn set_element_gain(&mut self, element_id: u32, gain_db: f32) {
        // Find and update or add
        if let Some(idx) = self.config.personalization.iter().position(|(id, _)| *id == element_id) {
            self.config.personalization[idx].1 = gain_db;
        } else {
            self.config.personalization.push((element_id, gain_db));
        }
        self.update_gains();
    }

    /// Select switch group member
    pub fn select_switch(&mut self, group_id: u32, element_id: u32) {
        if let Some(idx) = self.config.switch_selections.iter().position(|(id, _)| *id == group_id) {
            self.config.switch_selections[idx].1 = element_id;
        } else {
            self.config.switch_selections.push((group_id, element_id));
        }
        self.update_gains();
    }

    /// Update computed gains
    fn update_gains(&mut self) {
        self.element_gains.clear();

        for element in &self.scene.elements {
            // Start with default gain
            let mut gain_db = element.default_gain_db;

            // Apply personalization
            if let Some((_, g)) = self.config.personalization.iter()
                .find(|(id, _)| *id == element.id)
            {
                if element.allow_gain_change {
                    gain_db += g.clamp(element.gain_range.0, element.gain_range.1);
                }
            }

            // Check switch group status
            let mut active = element.default_on;
            for group in &self.scene.switch_groups {
                if group.members.contains(&element.id) {
                    // Element is in a switch group
                    if let Some((_, selected)) = self.config.switch_selections.iter()
                        .find(|(id, _)| *id == group.id)
                    {
                        active = *selected == element.id;
                    } else {
                        active = group.default_member == element.id;
                    }
                }
            }

            if !active {
                gain_db = -96.0; // Mute
            }

            self.element_gains.push((element.id, gain_db));
        }
    }

    /// Get gain for element in linear
    pub fn get_element_gain_linear(&self, element_id: u32) -> f32 {
        self.element_gains
            .iter()
            .find(|(id, _)| *id == element_id)
            .map(|(_, g)| 10.0_f32.powf(*g / 20.0))
            .unwrap_or(1.0)
    }

    /// Process audio (apply gains)
    pub fn process(
        &self,
        element_audio: &[(u32, &[f32])],
        output: &mut [f32],
    ) {
        output.fill(0.0);

        for (element_id, audio) in element_audio {
            let gain = self.get_element_gain_linear(*element_id);

            for (i, &s) in audio.iter().enumerate() {
                if i < output.len() {
                    output[i] += s * gain;
                }
            }
        }

        // Apply loudness normalization
        let target_gain = 10.0_f32.powf(
            (self.config.target_loudness - self.scene.loudness.integrated_loudness) / 20.0
        );

        for s in output {
            *s *= target_gain;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scene_creation() {
        let mut scene = MpegHScene::new(1);

        scene.add_element(AudioElement {
            id: 1,
            name: "Dialogue".into(),
            element_type: ElementType::Object,
            ..Default::default()
        });

        scene.add_element(AudioElement {
            id: 2,
            name: "Music".into(),
            element_type: ElementType::Channel,
            ..Default::default()
        });

        assert_eq!(scene.elements.len(), 2);
    }

    #[test]
    fn test_switch_groups() {
        let mut scene = MpegHScene::new(1);

        scene.add_element(AudioElement {
            id: 1,
            name: "English".into(),
            ..Default::default()
        });

        scene.add_element(AudioElement {
            id: 2,
            name: "Spanish".into(),
            default_on: false,
            ..Default::default()
        });

        scene.add_switch_group(SwitchGroup {
            id: 1,
            name: "Language".into(),
            members: vec![1, 2],
            default_member: 1,
            allow_off: false,
        });

        let config = MpegHConfig::default();
        let renderer = MpegHRenderer::new(scene, config, 48000);

        // English should be on
        assert!(renderer.get_element_gain_linear(1) > 0.5);
        // Spanish should be off
        assert!(renderer.get_element_gain_linear(2) < 0.01);
    }

    #[test]
    fn test_personalization() {
        let mut scene = MpegHScene::new(1);

        scene.add_element(AudioElement {
            id: 1,
            name: "Dialogue".into(),
            gain_range: (-12.0, 12.0),
            ..Default::default()
        });

        let config = MpegHConfig::default();
        let mut renderer = MpegHRenderer::new(scene, config, 48000);

        // Boost dialogue by 6dB
        renderer.set_element_gain(1, 6.0);

        let gain = renderer.get_element_gain_linear(1);
        assert!(gain > 1.5 && gain < 2.5); // ~2x (6dB boost)
    }
}

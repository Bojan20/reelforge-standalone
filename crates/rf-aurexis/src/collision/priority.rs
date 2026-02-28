use serde::{Deserialize, Serialize};
use crate::MAX_VOICES;

/// A registered voice in the collision system.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoiceEntry {
    pub voice_id: u32,
    pub pan: f32,
    pub z_depth: f32,
    pub priority: i32,
    /// Original pan before redistribution.
    pub original_pan: f32,
    /// Whether this voice was redistributed.
    pub redistributed: bool,
}

/// Manages voice registration and collision detection.
pub struct VoiceCollisionResolver {
    voices: Vec<VoiceEntry>,
}

impl VoiceCollisionResolver {
    pub fn new() -> Self {
        Self {
            voices: Vec::with_capacity(MAX_VOICES),
        }
    }

    /// Register a new voice for collision tracking.
    pub fn register_voice(&mut self, voice_id: u32, pan: f32, z_depth: f32, priority: i32) -> bool {
        if self.voices.len() >= MAX_VOICES {
            log::warn!("AUREXIS: Voice capacity exceeded ({MAX_VOICES})");
            return false;
        }
        // Remove existing voice with same ID (re-register)
        self.voices.retain(|v| v.voice_id != voice_id);
        self.voices.push(VoiceEntry {
            voice_id,
            pan,
            z_depth,
            priority,
            original_pan: pan,
            redistributed: false,
        });
        true
    }

    /// Remove a voice from tracking.
    pub fn unregister_voice(&mut self, voice_id: u32) -> bool {
        let before = self.voices.len();
        self.voices.retain(|v| v.voice_id != voice_id);
        self.voices.len() < before
    }

    /// Get current voice count.
    pub fn voice_count(&self) -> usize {
        self.voices.len()
    }

    /// Get a reference to all voices.
    pub fn voices(&self) -> &[VoiceEntry] {
        &self.voices
    }

    /// Get a mutable reference to all voices (for redistribution).
    pub fn voices_mut(&mut self) -> &mut Vec<VoiceEntry> {
        &mut self.voices
    }

    /// Clear all voices.
    pub fn clear(&mut self) {
        self.voices.clear();
    }

    /// Count voices in the center zone (|pan| <= center_width).
    pub fn center_occupancy(&self, center_width: f64) -> u32 {
        self.voices
            .iter()
            .filter(|v| (v.pan as f64).abs() <= center_width && v.z_depth < 0.3)
            .count() as u32
    }

    /// Sort voices by priority (highest first).
    pub fn sort_by_priority(&mut self) {
        self.voices.sort_by(|a, b| b.priority.cmp(&a.priority));
    }
}

impl Default for VoiceCollisionResolver {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_register_unregister() {
        let mut resolver = VoiceCollisionResolver::new();
        assert!(resolver.register_voice(1, 0.0, 0.0, 10));
        assert!(resolver.register_voice(2, 0.5, 0.0, 5));
        assert_eq!(resolver.voice_count(), 2);

        assert!(resolver.unregister_voice(1));
        assert_eq!(resolver.voice_count(), 1);
        assert!(!resolver.unregister_voice(99)); // not found
    }

    #[test]
    fn test_re_register() {
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, 0.0, 0.0, 10);
        resolver.register_voice(1, 0.5, 0.1, 20); // re-register
        assert_eq!(resolver.voice_count(), 1);
        assert_eq!(resolver.voices()[0].pan, 0.5);
        assert_eq!(resolver.voices()[0].priority, 20);
    }

    #[test]
    fn test_center_occupancy() {
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, 0.0, 0.0, 10);   // center, front
        resolver.register_voice(2, 0.1, 0.0, 8);    // center, front
        resolver.register_voice(3, 0.5, 0.0, 5);    // off-center
        resolver.register_voice(4, 0.0, 0.5, 3);    // center, back (z > 0.3)

        assert_eq!(resolver.center_occupancy(0.15), 2); // voices 1, 2
    }

    #[test]
    fn test_sort_by_priority() {
        let mut resolver = VoiceCollisionResolver::new();
        resolver.register_voice(1, 0.0, 0.0, 5);
        resolver.register_voice(2, 0.0, 0.0, 10);
        resolver.register_voice(3, 0.0, 0.0, 1);

        resolver.sort_by_priority();
        assert_eq!(resolver.voices()[0].voice_id, 2); // priority 10
        assert_eq!(resolver.voices()[1].voice_id, 1); // priority 5
        assert_eq!(resolver.voices()[2].voice_id, 3); // priority 1
    }
}

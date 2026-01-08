//! Dolby Atmos object-based audio
//!
//! Full Atmos implementation:
//! - Object-based rendering (up to 128 objects)
//! - 7.1.4 bed mixing
//! - ADM (Audio Definition Model) metadata
//! - Height channel rendering
//! - Binaural Atmos rendering

mod renderer;
mod bed;
mod metadata;

pub use renderer::{AtmosRenderer, AtmosConfig};
pub use bed::AtmosBed;
pub use metadata::{AdmMetadata, ObjectMetadata};

use crate::Position3D;

/// Atmos object
#[derive(Debug, Clone)]
pub struct AtmosObject {
    /// Unique ID
    pub id: u32,
    /// Object name
    pub name: String,
    /// Position (normalized -1 to 1 for X/Y, 0 to 1 for Z)
    pub position: Position3D,
    /// Object size (0 = point, 1 = full)
    pub size: f32,
    /// Gain (linear)
    pub gain: f32,
    /// Divergence (spread)
    pub divergence: f32,
    /// Snap to nearest speaker
    pub snap: bool,
    /// Zone mask (which zones to render to)
    pub zone_mask: u32,
}

impl Default for AtmosObject {
    fn default() -> Self {
        Self {
            id: 0,
            name: "Object".into(),
            position: Position3D::origin(),
            size: 0.0,
            gain: 1.0,
            divergence: 0.0,
            snap: false,
            zone_mask: 0xFFFFFFFF,
        }
    }
}

/// Atmos zone
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AtmosZone {
    /// Screen zone (front)
    Screen,
    /// Surround zone (sides and rear)
    Surround,
    /// Height zone (overhead)
    Height,
    /// LFE zone
    Lfe,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_atmos_object_default() {
        let obj = AtmosObject::default();
        assert_eq!(obj.gain, 1.0);
        assert_eq!(obj.size, 0.0);
    }
}

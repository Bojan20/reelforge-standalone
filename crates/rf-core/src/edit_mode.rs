//! Edit Modes (Pro Tools Style)
//!
//! Four editing paradigms that change tool behavior:
//! - Slip: Free movement, no constraints
//! - Grid: Snap to tempo grid
//! - Shuffle: Auto-close gaps on movement
//! - Spot: Precise timecode placement via dialog

use serde::{Deserialize, Serialize};

/// Edit mode determines how editing tools behave
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum EditMode {
    /// Free movement - clips can be placed anywhere
    /// Use case: Podcast/speech editing, creative arrangement
    #[default]
    Slip,

    /// Snap to grid - clips align to tempo grid
    /// Use case: Music production, beat-aligned editing
    Grid,

    /// Auto-close gaps - moving clips closes empty space
    /// Use case: Rearranging song sections, removing silence
    Shuffle,

    /// Precise placement - dialog for exact timecode entry
    /// Use case: Film/TV post-production, sync work
    Spot,
}

impl EditMode {
    /// Get human-readable name
    pub fn name(&self) -> &'static str {
        match self {
            Self::Slip => "Slip",
            Self::Grid => "Grid",
            Self::Shuffle => "Shuffle",
            Self::Spot => "Spot",
        }
    }

    /// Get description
    pub fn description(&self) -> &'static str {
        match self {
            Self::Slip => "Free movement, no constraints",
            Self::Grid => "Snap to tempo grid",
            Self::Shuffle => "Auto-close gaps on movement",
            Self::Spot => "Precise timecode placement",
        }
    }

    /// Get keyboard shortcut (Pro Tools convention)
    pub fn shortcut(&self) -> &'static str {
        match self {
            Self::Slip => "F1",
            Self::Grid => "F2",
            Self::Shuffle => "F3",
            Self::Spot => "F4",
        }
    }
}

/// Grid resolution for Grid mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum GridResolution {
    /// 1 bar
    Bar,
    /// Half bar (2 beats in 4/4)
    HalfBar,
    /// Quarter note (1 beat)
    #[default]
    Beat,
    /// Eighth note
    Eighth,
    /// Sixteenth note
    Sixteenth,
    /// Thirty-second note
    ThirtySecond,
    /// Sixty-fourth note
    SixtyFourth,
    /// Triplet subdivision
    Triplet,
    /// Dotted subdivision
    Dotted,
    /// Frames (for video sync)
    Frames,
    /// Samples (finest resolution)
    Samples,
}

impl GridResolution {
    /// Get subdivision factor relative to beat
    pub fn beat_factor(&self) -> f64 {
        match self {
            Self::Bar => 4.0, // Assumes 4/4
            Self::HalfBar => 2.0,
            Self::Beat => 1.0,
            Self::Eighth => 0.5,
            Self::Sixteenth => 0.25,
            Self::ThirtySecond => 0.125,
            Self::SixtyFourth => 0.0625,
            Self::Triplet => 1.0 / 3.0,
            Self::Dotted => 1.5,
            Self::Frames => 0.0,  // Handled separately
            Self::Samples => 0.0, // Handled separately
        }
    }
}

/// Grid settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GridSettings {
    /// Grid resolution
    pub resolution: GridResolution,
    /// Grid is enabled
    pub enabled: bool,
    /// Snap strength (0.0 = no snap, 1.0 = full snap)
    pub strength: f64,
    /// Triplet mode
    pub triplet: bool,
    /// Swing percentage (0-100)
    pub swing: f64,
}

impl Default for GridSettings {
    fn default() -> Self {
        Self {
            resolution: GridResolution::Beat,
            enabled: true,
            strength: 1.0,
            triplet: false,
            swing: 0.0,
        }
    }
}

impl GridSettings {
    /// Calculate nearest grid position in samples
    pub fn snap_to_grid(&self, position_samples: u64, sample_rate: f64, tempo_bpm: f64) -> u64 {
        if !self.enabled || self.strength == 0.0 {
            return position_samples;
        }

        let samples_per_beat = (sample_rate * 60.0) / tempo_bpm;
        let grid_samples = samples_per_beat * self.resolution.beat_factor();

        if grid_samples <= 0.0 {
            return position_samples;
        }

        let grid_position = (position_samples as f64 / grid_samples).round() * grid_samples;
        let snapped = grid_position as u64;

        // Apply strength (blend between original and snapped)
        if self.strength < 1.0 {
            let blend =
                position_samples as f64 * (1.0 - self.strength) + snapped as f64 * self.strength;
            blend as u64
        } else {
            snapped
        }
    }
}

/// Spot mode dialog result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpotPlacement {
    /// Target position in samples
    pub position_samples: u64,
    /// Target position in timecode (SMPTE)
    pub timecode: Option<String>,
    /// User cancelled the dialog
    pub cancelled: bool,
}

/// Edit context for determining behavior
#[derive(Debug, Clone)]
pub struct EditContext {
    /// Current edit mode
    pub mode: EditMode,
    /// Grid settings
    pub grid: GridSettings,
    /// Current tempo in BPM
    pub tempo: f64,
    /// Current sample rate
    pub sample_rate: f64,
    /// Time signature numerator
    pub time_sig_num: u8,
    /// Time signature denominator
    pub time_sig_denom: u8,
}

impl Default for EditContext {
    fn default() -> Self {
        Self {
            mode: EditMode::Slip,
            grid: GridSettings::default(),
            tempo: 120.0,
            sample_rate: 48000.0,
            time_sig_num: 4,
            time_sig_denom: 4,
        }
    }
}

impl EditContext {
    /// Apply edit mode rules to a position
    pub fn apply_to_position(&self, position: u64) -> u64 {
        match self.mode {
            EditMode::Slip => position,
            EditMode::Grid => self
                .grid
                .snap_to_grid(position, self.sample_rate, self.tempo),
            EditMode::Shuffle => position, // Shuffle is handled at operation level
            EditMode::Spot => position,    // Spot uses dialog, not automatic
        }
    }

    /// Get samples per beat at current tempo
    pub fn samples_per_beat(&self) -> f64 {
        (self.sample_rate * 60.0) / self.tempo
    }

    /// Get samples per bar at current tempo/time signature
    pub fn samples_per_bar(&self) -> f64 {
        self.samples_per_beat() * self.time_sig_num as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grid_snap() {
        let grid = GridSettings {
            resolution: GridResolution::Beat,
            enabled: true,
            strength: 1.0,
            ..Default::default()
        };

        // At 120 BPM, 48kHz: 1 beat = 24000 samples
        let snapped = grid.snap_to_grid(25000, 48000.0, 120.0);
        assert_eq!(snapped, 24000); // Rounds to nearest beat
    }

    #[test]
    fn test_grid_strength() {
        let grid = GridSettings {
            resolution: GridResolution::Beat,
            enabled: true,
            strength: 0.5,
            ..Default::default()
        };

        // 50% strength should blend
        let snapped = grid.snap_to_grid(25000, 48000.0, 120.0);
        // Original: 25000, Grid: 24000, 50% blend: 24500
        assert_eq!(snapped, 24500);
    }

    #[test]
    fn test_edit_mode_names() {
        assert_eq!(EditMode::Slip.name(), "Slip");
        assert_eq!(EditMode::Grid.name(), "Grid");
        assert_eq!(EditMode::Shuffle.name(), "Shuffle");
        assert_eq!(EditMode::Spot.name(), "Spot");
    }
}

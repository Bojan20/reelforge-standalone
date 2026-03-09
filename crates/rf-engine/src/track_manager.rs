//! Track Manager - Cubase-style Track/Clip Management
//!
//! Provides:
//! - Track creation, deletion, reordering
//! - Clip management (move, resize, split, duplicate)
//! - Crossfade handling
//! - Undo/Redo command pattern
//! - Lock-free updates to audio thread

use dashmap::DashMap;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use crate::input_bus::{InputBusId, MonitorMode};

// ═══════════════════════════════════════════════════════════════════════════
// ID TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Unique track identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct TrackId(pub u64);

/// Unique clip identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ClipId(pub u64);

/// Unique crossfade identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CrossfadeId(pub u64);

/// Unique marker identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct MarkerId(pub u64);

/// Unique clip FX slot identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ClipFxSlotId(pub u64);

/// Unique take identifier (for comping)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct TakeId(pub u64);

/// Unique render region identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct RenderRegionId(pub u64);

/// Unique razor edit area identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct RazorAreaId(pub u64);

/// Unique mix snapshot identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct MixSnapshotId(pub u64);

/// Unique comp lane identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CompLaneId(pub u64);

// Global ID counter for generating unique IDs
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════
// OUTPUT BUS
// ═══════════════════════════════════════════════════════════════════════════

/// Output bus routing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum OutputBus {
    #[default]
    Master = 0,
    Music = 1,
    Sfx = 2,
    Voice = 3,
    Ambience = 4,
    Aux = 5,
}

impl From<u32> for OutputBus {
    fn from(value: u32) -> Self {
        match value {
            0 => Self::Master,
            1 => Self::Music,
            2 => Self::Sfx,
            3 => Self::Voice,
            4 => Self::Ambience,
            5 => Self::Aux,
            _ => Self::Master,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK
// ═══════════════════════════════════════════════════════════════════════════

/// Track send slot configuration
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TrackSendSlot {
    /// Send level (0.0 to 1.0)
    pub level: f64,
    /// Pre-fader send (true) or post-fader (false)
    pub pre_fader: bool,
    /// Muted state
    pub muted: bool,
    /// Destination bus ID (None = disabled)
    pub destination: Option<OutputBus>,
}

/// Maximum number of sends per track
pub const MAX_TRACK_SENDS: usize = 8;

/// Audio track with clips
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    pub id: TrackId,
    pub name: String,
    pub color: u32,  // ARGB color
    pub height: f64, // UI height in pixels
    pub output_bus: OutputBus,
    pub volume: f64, // 0.0 to 1.5 (linear, +6dB headroom)
    pub pan: f64,    // -1.0 to +1.0 (left channel for stereo dual-pan)
    /// Right channel pan for stereo dual-pan (Pro Tools style)
    /// For mono tracks, this is ignored
    /// For stereo: pan controls L channel, pan_right controls R channel
    #[serde(default)]
    pub pan_right: f64, // -1.0 to +1.0 (right channel for stereo dual-pan)
    /// Number of audio channels (1 = mono, 2 = stereo)
    #[serde(default = "default_channels")]
    pub channels: u32,
    pub muted: bool,
    pub soloed: bool,
    pub armed: bool,
    pub locked: bool,
    pub frozen: bool,
    pub input_monitor: bool,
    pub order: usize, // Position in track list
    /// Send effects routing
    #[serde(default)]
    pub sends: [TrackSendSlot; MAX_TRACK_SENDS],
    /// Input bus routing (None = no input, Some(id) = routed from input bus)
    #[serde(default)]
    pub input_bus: Option<InputBusId>,
    /// Input monitoring mode (Auto/Manual/Off)
    #[serde(default)]
    pub monitor_mode: MonitorMode,
    /// Phase invert (polarity flip)
    #[serde(default)]
    pub phase_inverted: bool,
}

/// Default channel count for serde
fn default_channels() -> u32 {
    2 // Default to stereo
}

impl Track {
    pub fn new(name: &str, color: u32, output_bus: OutputBus) -> Self {
        // Default to stereo with Pro Tools-style dual pan (L=-1, R=+1)
        Self::new_with_channels(name, color, output_bus, 2)
    }

    /// Create track with specific channel count
    /// For stereo: pan defaults to -1.0 (hard left), pan_right to +1.0 (hard right)
    /// For mono: pan defaults to 0.0 (center)
    pub fn new_with_channels(name: &str, color: u32, output_bus: OutputBus, channels: u32) -> Self {
        let (default_pan, default_pan_right) = if channels >= 2 {
            // Stereo: Pro Tools dual-pan style
            (-1.0, 1.0)
        } else {
            // Mono: center
            (0.0, 0.0)
        };

        Self {
            id: TrackId(next_id()),
            name: name.to_string(),
            color,
            height: 80.0,
            output_bus,
            volume: 1.0,
            pan: default_pan,
            pan_right: default_pan_right,
            channels,
            muted: false,
            soloed: false,
            armed: false,
            locked: false,
            frozen: false,
            input_monitor: false,
            order: 0,
            sends: Default::default(),
            input_bus: None,
            monitor_mode: MonitorMode::Auto,
            phase_inverted: false,
        }
    }

    /// Check if track is stereo
    #[inline]
    pub fn is_stereo(&self) -> bool {
        self.channels >= 2
    }

    /// Set send level
    pub fn set_send_level(&mut self, send_index: usize, level: f64) {
        if send_index < MAX_TRACK_SENDS {
            self.sends[send_index].level = level.clamp(0.0, 1.5);
        }
    }

    /// Set send destination
    pub fn set_send_destination(&mut self, send_index: usize, dest: Option<OutputBus>) {
        if send_index < MAX_TRACK_SENDS {
            self.sends[send_index].destination = dest;
        }
    }

    /// Set send pre/post fader
    pub fn set_send_pre_fader(&mut self, send_index: usize, pre_fader: bool) {
        if send_index < MAX_TRACK_SENDS {
            self.sends[send_index].pre_fader = pre_fader;
        }
    }

    /// Mute/unmute send
    pub fn set_send_muted(&mut self, send_index: usize, muted: bool) {
        if send_index < MAX_TRACK_SENDS {
            self.sends[send_index].muted = muted;
        }
    }

    /// Create track from template
    pub fn from_template(template: &TrackTemplate) -> Self {
        // Determine pan values based on template's channel config
        let (pan, pan_right) = if template.channels >= 2 {
            // Stereo: Pro Tools dual-pan style if template has default pan (0.0)
            if template.pan == 0.0 && template.pan_right == 0.0 {
                (-1.0, 1.0) // Default stereo
            } else {
                (template.pan, template.pan_right)
            }
        } else {
            (template.pan, 0.0) // Mono: use template pan, ignore pan_right
        };

        Self {
            id: TrackId(next_id()),
            name: template.name.clone(),
            color: template.color,
            height: template.height,
            output_bus: template.output_bus,
            volume: template.volume,
            pan,
            pan_right,
            channels: template.channels,
            muted: false,
            soloed: false,
            armed: false,
            locked: false,
            frozen: false,
            input_monitor: false,
            order: 0,
            sends: Default::default(),
            input_bus: None,
            monitor_mode: MonitorMode::Auto,
            phase_inverted: false,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK TEMPLATE
// ═══════════════════════════════════════════════════════════════════════════

/// Track template for saving/loading track configurations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackTemplate {
    /// Template ID (auto-generated on save)
    pub id: String,
    /// Template name (user-defined)
    pub template_name: String,
    /// Category for organization
    pub category: String,
    /// Description
    pub description: String,
    /// Creation timestamp
    pub created_at: u64,

    // Track configuration
    pub name: String,
    pub color: u32,
    pub height: f64,
    pub output_bus: OutputBus,
    pub volume: f64,
    pub pan: f64,
    /// Right channel pan for stereo dual-pan
    #[serde(default)]
    pub pan_right: f64,
    /// Number of channels (1 = mono, 2 = stereo)
    #[serde(default = "default_template_channels")]
    pub channels: u32,

    /// Tags for filtering
    pub tags: Vec<String>,
}

/// Default channel count for template serde
fn default_template_channels() -> u32 {
    2 // Default to stereo
}

impl TrackTemplate {
    /// Create template from existing track
    pub fn from_track(track: &Track, template_name: &str, category: &str) -> Self {
        use std::time::{SystemTime, UNIX_EPOCH};
        let created_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        Self {
            id: format!("tpl_{}", next_id()),
            template_name: template_name.to_string(),
            category: category.to_string(),
            description: String::new(),
            created_at,
            name: track.name.clone(),
            color: track.color,
            height: track.height,
            output_bus: track.output_bus,
            volume: track.volume,
            pan: track.pan,
            pan_right: track.pan_right,
            channels: track.channels,
            tags: Vec::new(),
        }
    }

    /// Create a default template (stereo)
    pub fn default_audio() -> Self {
        Self {
            id: "default_audio".to_string(),
            template_name: "Audio Track".to_string(),
            category: "Default".to_string(),
            description: "Standard audio track".to_string(),
            created_at: 0,
            name: "Audio".to_string(),
            color: 0xFF4A9EFF,
            height: 80.0,
            output_bus: OutputBus::Master,
            volume: 1.0,
            pan: -1.0,      // Stereo: L hard left
            pan_right: 1.0, // Stereo: R hard right
            channels: 2,
            tags: vec!["audio".to_string()],
        }
    }

    pub fn default_vocal() -> Self {
        Self {
            id: "default_vocal".to_string(),
            template_name: "Vocal Track".to_string(),
            category: "Default".to_string(),
            description: "Optimized for vocals".to_string(),
            created_at: 0,
            name: "Vocal".to_string(),
            color: 0xFFFF9040,
            height: 80.0,
            output_bus: OutputBus::Voice,
            volume: 1.0,
            pan: 0.0, // Mono: center
            pan_right: 0.0,
            channels: 1, // Vocals typically mono
            tags: vec!["vocal".to_string(), "voice".to_string()],
        }
    }

    pub fn default_drums() -> Self {
        Self {
            id: "default_drums".to_string(),
            template_name: "Drums Track".to_string(),
            category: "Default".to_string(),
            description: "Optimized for drums".to_string(),
            created_at: 0,
            name: "Drums".to_string(),
            color: 0xFFFF4060,
            height: 100.0,
            output_bus: OutputBus::Sfx,
            volume: 1.0,
            pan: -1.0,      // Stereo: L hard left
            pan_right: 1.0, // Stereo: R hard right
            channels: 2,    // Drums typically stereo
            tags: vec!["drums".to_string(), "percussion".to_string()],
        }
    }

    pub fn default_bass() -> Self {
        Self {
            id: "default_bass".to_string(),
            template_name: "Bass Track".to_string(),
            category: "Default".to_string(),
            description: "Optimized for bass".to_string(),
            created_at: 0,
            name: "Bass".to_string(),
            color: 0xFF40FF90,
            height: 80.0,
            output_bus: OutputBus::Music,
            volume: 1.0,
            pan: 0.0, // Mono: center
            pan_right: 0.0,
            channels: 1, // Bass typically mono
            tags: vec!["bass".to_string(), "music".to_string()],
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPING SYSTEM
// ═══════════════════════════════════════════════════════════════════════════

/// A take within a comp lane
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Take {
    pub id: TakeId,
    pub name: String,
    pub source_file: String,  // Audio file path
    pub source_offset: f64,   // Offset within source file (seconds)
    pub source_duration: f64, // Duration in source file (seconds)
    pub track_id: TrackId,
    pub lane_id: CompLaneId,
    pub start_time: f64, // Position on timeline (seconds)
    pub duration: f64,   // Duration on timeline (seconds)
    pub gain: f64,       // Take gain (linear, default 1.0)
    pub muted: bool,
    pub color: u32, // Take-specific color (ARGB)
    pub rating: u8, // 0-5 star rating
}

impl Take {
    pub fn new(
        source_file: &str,
        track_id: TrackId,
        lane_id: CompLaneId,
        start_time: f64,
        duration: f64,
    ) -> Self {
        Self {
            id: TakeId(next_id()),
            name: format!("Take {}", next_id() % 100),
            source_file: source_file.to_string(),
            source_offset: 0.0,
            source_duration: duration,
            track_id,
            lane_id,
            start_time,
            duration,
            gain: 1.0,
            muted: false,
            color: 0xFF4A9EFF, // Default blue
            rating: 0,
        }
    }
}

/// A comp region - selected portion of a take for final comp
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompRegion {
    pub start_time: f64, // Region start on timeline
    pub end_time: f64,   // Region end on timeline
    pub take_id: TakeId, // Which take is selected for this region
}

/// A comp lane containing multiple takes
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompLane {
    pub id: CompLaneId,
    pub name: String,
    pub track_id: TrackId,
    pub height: f64,  // UI height in pixels
    pub order: usize, // Order within track's comp lanes
    pub visible: bool,
    pub color: u32,
}

impl CompLane {
    pub fn new(name: &str, track_id: TrackId, order: usize) -> Self {
        Self {
            id: CompLaneId(next_id()),
            name: name.to_string(),
            track_id,
            height: 40.0,
            order,
            visible: true,
            color: 0xFF808090,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP FX CHAIN
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum number of FX slots per clip
pub const MAX_CLIP_FX_SLOTS: usize = 8;

/// Processor type for clip FX (serializable reference)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ClipFxType {
    /// Pro EQ with band configuration
    ProEq { bands: u8 },
    /// Ultra EQ (mastering)
    UltraEq,
    /// Pultec-style EQ
    Pultec,
    /// API 550 EQ
    Api550,
    /// Neve 1073 EQ
    Neve1073,
    /// Morph EQ (dynamic)
    MorphEq,
    /// Room correction EQ
    RoomCorrection,
    /// Compressor
    Compressor {
        ratio: f64,
        threshold_db: f64,
        attack_ms: f64,
        release_ms: f64,
    },
    /// Limiter
    Limiter { ceiling_db: f64 },
    /// Gate
    Gate {
        threshold_db: f64,
        attack_ms: f64,
        release_ms: f64,
    },
    /// Gain (simple volume/pan)
    Gain { db: f64, pan: f64 },
    /// Pitch shift
    PitchShift { semitones: f64, cents: f64 },
    /// Time stretch (offline/elastic)
    TimeStretch { ratio: f64 },
    /// Saturation/harmonic distortion
    Saturation { drive: f64, mix: f64 },
    /// External VST3/AU/CLAP plugin
    External {
        plugin_id: String,
        state: Option<Vec<u8>>,
    },
}

impl Default for ClipFxType {
    fn default() -> Self {
        Self::Gain { db: 0.0, pan: 0.0 }
    }
}

/// Single FX slot in a clip's effect chain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipFxSlot {
    pub id: ClipFxSlotId,
    /// FX processor type and parameters
    pub fx_type: ClipFxType,
    /// Bypass this slot (true = skip processing)
    pub bypass: bool,
    /// Wet/dry mix (0.0 = fully dry, 1.0 = fully wet)
    pub wet_dry: f64,
    /// Output gain in dB (-inf to +12)
    pub output_gain_db: f64,
    /// Slot name (user-defined or auto-generated)
    pub name: String,
    /// Slot order in chain (0 = first)
    pub order: usize,
}

impl ClipFxSlot {
    pub fn new(fx_type: ClipFxType) -> Self {
        Self {
            id: ClipFxSlotId(next_id()),
            fx_type,
            bypass: false,
            wet_dry: 1.0,
            output_gain_db: 0.0,
            name: String::new(),
            order: 0,
        }
    }

    /// Create with custom name
    pub fn with_name(mut self, name: &str) -> Self {
        self.name = name.to_string();
        self
    }

    /// Create bypassed slot
    pub fn bypassed(mut self) -> Self {
        self.bypass = true;
        self
    }

    /// Set wet/dry mix
    pub fn with_wet_dry(mut self, wet_dry: f64) -> Self {
        self.wet_dry = wet_dry.clamp(0.0, 1.0);
        self
    }

    /// Calculate linear gain from dB
    #[inline]
    pub fn output_gain_linear(&self) -> f64 {
        if self.output_gain_db <= -96.0 {
            0.0
        } else {
            10.0_f64.powf(self.output_gain_db / 20.0)
        }
    }
}

/// Per-clip effect chain (non-destructive, rendered at playback)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ClipFxChain {
    /// Ordered list of FX slots
    pub slots: Vec<ClipFxSlot>,
    /// Bypass entire chain
    pub bypass: bool,
    /// Pre-FX gain (before processing)
    pub input_gain_db: f64,
    /// Post-FX gain (after all processing)
    pub output_gain_db: f64,
}

impl ClipFxChain {
    pub fn new() -> Self {
        Self {
            slots: Vec::with_capacity(MAX_CLIP_FX_SLOTS),
            bypass: false,
            input_gain_db: 0.0,
            output_gain_db: 0.0,
        }
    }

    /// Add FX slot to end of chain
    pub fn add_slot(&mut self, mut slot: ClipFxSlot) -> ClipFxSlotId {
        if self.slots.len() >= MAX_CLIP_FX_SLOTS {
            // Remove oldest if at capacity
            self.slots.remove(0);
            self.reorder_slots();
        }
        slot.order = self.slots.len();
        let id = slot.id;
        self.slots.push(slot);
        id
    }

    /// Insert FX slot at specific position
    pub fn insert_slot(&mut self, index: usize, mut slot: ClipFxSlot) -> ClipFxSlotId {
        let index = index.min(self.slots.len());
        if self.slots.len() >= MAX_CLIP_FX_SLOTS {
            self.slots.pop();
        }
        slot.order = index;
        let id = slot.id;
        self.slots.insert(index, slot);
        self.reorder_slots();
        id
    }

    /// Remove FX slot by ID
    pub fn remove_slot(&mut self, slot_id: ClipFxSlotId) -> bool {
        let initial_len = self.slots.len();
        self.slots.retain(|s| s.id != slot_id);
        if self.slots.len() < initial_len {
            self.reorder_slots();
            true
        } else {
            false
        }
    }

    /// Move slot to new position
    pub fn move_slot(&mut self, slot_id: ClipFxSlotId, new_index: usize) -> bool {
        if let Some(old_index) = self.slots.iter().position(|s| s.id == slot_id) {
            let slot = self.slots.remove(old_index);
            let new_index = new_index.min(self.slots.len());
            self.slots.insert(new_index, slot);
            self.reorder_slots();
            true
        } else {
            false
        }
    }

    /// Get slot by ID
    pub fn get_slot(&self, slot_id: ClipFxSlotId) -> Option<&ClipFxSlot> {
        self.slots.iter().find(|s| s.id == slot_id)
    }

    /// Get mutable slot by ID
    pub fn get_slot_mut(&mut self, slot_id: ClipFxSlotId) -> Option<&mut ClipFxSlot> {
        self.slots.iter_mut().find(|s| s.id == slot_id)
    }

    /// Get active (non-bypassed) slots in order
    pub fn active_slots(&self) -> impl Iterator<Item = &ClipFxSlot> {
        self.slots.iter().filter(|s| !s.bypass)
    }

    /// Check if chain has any active processing
    pub fn has_active_processing(&self) -> bool {
        !self.bypass && self.slots.iter().any(|s| !s.bypass)
    }

    /// Calculate input gain as linear multiplier
    #[inline]
    pub fn input_gain_linear(&self) -> f64 {
        if self.input_gain_db <= -96.0 {
            0.0
        } else {
            10.0_f64.powf(self.input_gain_db / 20.0)
        }
    }

    /// Calculate output gain as linear multiplier
    #[inline]
    pub fn output_gain_linear(&self) -> f64 {
        if self.output_gain_db <= -96.0 {
            0.0
        } else {
            10.0_f64.powf(self.output_gain_db / 20.0)
        }
    }

    /// Reorder slot indices after modification
    fn reorder_slots(&mut self) {
        for (i, slot) in self.slots.iter_mut().enumerate() {
            slot.order = i;
        }
    }

    /// Clear all slots
    pub fn clear(&mut self) {
        self.slots.clear();
    }

    /// Get number of slots
    pub fn len(&self) -> usize {
        self.slots.len()
    }

    /// Check if chain is empty
    pub fn is_empty(&self) -> bool {
        self.slots.is_empty()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP ENVELOPE — Per-item automation (Reaper take envelopes)
// ═══════════════════════════════════════════════════════════════════════════

/// Curve type for clip envelope interpolation
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub enum ClipEnvelopeCurve {
    /// Linear interpolation
    #[default]
    Linear,
    /// Bezier curve (smooth)
    Bezier,
    /// Exponential
    Exponential,
    /// Logarithmic
    Logarithmic,
    /// Step (hold until next point)
    Step,
    /// S-Curve (smooth sigmoid)
    SCurve,
}

/// Single point in a clip envelope.
/// Positions are RELATIVE to clip start (in samples) — envelope moves with the clip.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipEnvelopePoint {
    /// Position in samples relative to clip start (NOT absolute timeline)
    pub offset_samples: u64,
    /// Value in parameter-native units:
    ///   - Pitch envelope: semitones (-24.0 to +24.0, 0.0 = no shift)
    ///   - Playrate envelope: rate multiplier (0.1 to 4.0, 1.0 = normal)
    ///   - Volume envelope: linear gain (0.0 to 2.0, 1.0 = unity)
    ///   - Pan envelope: pan position (-1.0 to 1.0, 0.0 = center)
    pub value: f64,
    /// Curve type to next point
    pub curve: ClipEnvelopeCurve,
    /// Bezier control points (relative, 0-1 in both axes)
    pub bezier_cp1: Option<(f64, f64)>,
    pub bezier_cp2: Option<(f64, f64)>,
}

impl ClipEnvelopePoint {
    pub fn new(offset_samples: u64, value: f64) -> Self {
        Self {
            offset_samples,
            value,
            curve: ClipEnvelopeCurve::Linear,
            bezier_cp1: None,
            bezier_cp2: None,
        }
    }

    pub fn with_curve(mut self, curve: ClipEnvelopeCurve) -> Self {
        self.curve = curve;
        self
    }
}

/// Per-clip envelope that moves with the clip on the timeline.
/// Used for pitch, playrate, volume, and pan automation at item level.
///
/// ## Key Differences from Track Automation:
/// - **Relative positions:** Points use clip-relative offsets, not absolute timeline positions
/// - **Moves with clip:** Drag clip → envelope moves with it
/// - **Multiplicative with track:** Clip volume envelope × track volume automation
/// - **Additive for pitch:** Clip pitch envelope + base pitch_shift + track pitch automation
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ClipEnvelope {
    /// Sorted points (by offset_samples)
    pub points: Vec<ClipEnvelopePoint>,
    /// Is this envelope enabled
    pub enabled: bool,
    /// Default value when no points (in native units)
    pub default_value: f64,
}

impl ClipEnvelope {
    pub fn new(default_value: f64) -> Self {
        Self {
            points: Vec::new(),
            enabled: true,
            default_value,
        }
    }

    /// Pitch envelope: default 0.0 semitones
    pub fn pitch() -> Self {
        Self::new(0.0)
    }

    /// Playrate envelope: default 1.0 (normal speed)
    pub fn playrate() -> Self {
        Self::new(1.0)
    }

    /// Volume envelope: default 1.0 (unity gain)
    pub fn volume() -> Self {
        Self::new(1.0)
    }

    /// Pan envelope: default 0.0 (center)
    pub fn pan() -> Self {
        Self::new(0.0)
    }

    /// Add a point, maintaining sorted order by offset_samples.
    /// If a point already exists at the same offset, it is replaced.
    pub fn add_point(&mut self, point: ClipEnvelopePoint) {
        match self
            .points
            .binary_search_by_key(&point.offset_samples, |p| p.offset_samples)
        {
            Ok(idx) => self.points[idx] = point,   // Replace existing
            Err(idx) => self.points.insert(idx, point), // Insert new
        }
    }

    /// Remove point at offset (within tolerance)
    pub fn remove_point_at(&mut self, offset_samples: u64, tolerance: u64) -> bool {
        if let Some(idx) = self.points.iter().position(|p| {
            (p.offset_samples as i64 - offset_samples as i64).unsigned_abs() <= tolerance
        }) {
            self.points.remove(idx);
            true
        } else {
            false
        }
    }

    /// Clear all points
    pub fn clear(&mut self) {
        self.points.clear();
    }

    /// Is envelope active (enabled and has points)
    #[inline]
    pub fn is_active(&self) -> bool {
        self.enabled && !self.points.is_empty()
    }

    /// Get value at clip-relative sample offset (interpolated).
    /// Returns native-unit value (semitones for pitch, multiplier for rate, etc.)
    pub fn value_at(&self, offset_samples: u64) -> f64 {
        if self.points.is_empty() {
            return self.default_value;
        }

        // Before first point
        if offset_samples <= self.points[0].offset_samples {
            return self.points[0].value;
        }

        // After last point
        let last = self.points.last().expect("checked non-empty");
        if offset_samples >= last.offset_samples {
            return last.value;
        }

        // Binary search for surrounding points
        let idx = self
            .points
            .binary_search_by_key(&offset_samples, |p| p.offset_samples)
            .unwrap_or_else(|i| i);

        if idx == 0 {
            return self.points[0].value;
        }

        let p1 = &self.points[idx - 1];
        let p2 = &self.points[idx];

        // Interpolation factor 0.0 - 1.0
        let t = (offset_samples - p1.offset_samples) as f64
            / (p2.offset_samples - p1.offset_samples) as f64;

        self.interpolate(p1, p2, t)
    }

    /// Compute the integral ∫₀^offset_samples value_at(t) dt
    /// Used for source position calculation with time-varying playback rate.
    /// For a rate envelope, this gives the total "source samples traversed" from clip start.
    ///
    /// For linear segments: ∫[a,b] (v1 + (v2-v1)*(t-a)/(b-a)) dt = (b-a) * (v1+v2)/2
    /// This is exact for Linear curves and a good approximation for others.
    pub fn integrated_value_to(&self, offset_samples: u64) -> f64 {
        if self.points.is_empty() {
            return self.default_value * offset_samples as f64;
        }

        let mut integral = 0.0;
        let mut prev_offset: u64 = 0;
        let mut prev_value = self.points[0].value; // Value before first point = first point value

        for point in &self.points {
            if point.offset_samples >= offset_samples {
                // Partial segment: from prev to offset_samples
                let seg_len = offset_samples.saturating_sub(prev_offset) as f64;
                let end_value = self.value_at(offset_samples);
                integral += seg_len * (prev_value + end_value) * 0.5;
                return integral;
            }

            // Full segment: from prev_offset to point.offset_samples
            let seg_len = point.offset_samples.saturating_sub(prev_offset) as f64;
            integral += seg_len * (prev_value + point.value) * 0.5;

            prev_offset = point.offset_samples;
            prev_value = point.value;
        }

        // After last point: constant value * remaining samples
        let remaining = offset_samples.saturating_sub(prev_offset) as f64;
        integral += remaining * prev_value;

        integral
    }

    /// Interpolate between two points using the curve of p1
    fn interpolate(&self, p1: &ClipEnvelopePoint, p2: &ClipEnvelopePoint, t: f64) -> f64 {
        match p1.curve {
            ClipEnvelopeCurve::Linear => p1.value + (p2.value - p1.value) * t,
            ClipEnvelopeCurve::Step => p1.value,
            ClipEnvelopeCurve::Exponential => {
                p1.value + (p2.value - p1.value) * (t * t)
            }
            ClipEnvelopeCurve::Logarithmic => {
                p1.value + (p2.value - p1.value) * t.sqrt()
            }
            ClipEnvelopeCurve::SCurve => {
                let s = t * t * (3.0 - 2.0 * t); // Hermite smoothstep
                p1.value + (p2.value - p1.value) * s
            }
            ClipEnvelopeCurve::Bezier => {
                let cp1 = p1.bezier_cp1.unwrap_or((0.33, 0.0));
                let cp2 = p1.bezier_cp2.unwrap_or((0.66, 0.0));

                let y0 = p1.value;
                let y3 = p2.value;
                let y1 = y0 + cp1.1 * (y3 - y0);
                let y2 = y0 + cp2.1 * (y3 - y0);

                let t2 = t * t;
                let t3 = t2 * t;
                let mt = 1.0 - t;
                let mt2 = mt * mt;
                let mt3 = mt2 * mt;

                mt3 * y0 + 3.0 * mt2 * t * y1 + 3.0 * mt * t2 * y2 + t3 * y3
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP
// ═══════════════════════════════════════════════════════════════════════════

/// Audio clip on a track
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Clip {
    pub id: ClipId,
    pub track_id: TrackId,
    pub name: String,
    pub color: Option<u32>, // Override track color if set

    // Timeline position (in seconds)
    pub start_time: f64,
    pub duration: f64,

    // Source audio reference
    pub source_file: String,  // Path to audio file
    pub source_offset: f64,   // Start offset within source (for trimming)
    pub source_duration: f64, // Original source file duration

    // Fades (in seconds)
    pub fade_in: f64,
    pub fade_out: f64,

    // Gain and state
    pub gain: f64, // 0.0 to 2.0 (linear)
    pub muted: bool,
    pub selected: bool,
    /// Play audio in reverse
    #[serde(default)]
    pub reversed: bool,

    /// Time stretch ratio (1.0 = normal, 0.5 = half speed, 2.0 = double speed)
    /// Applied as playback rate change — affects clip duration on timeline.
    #[serde(default = "default_stretch_ratio")]
    pub stretch_ratio: f64,

    /// Pitch shift in semitones (-24 to +24, 0.0 = no change)
    /// Applied independently of stretch ratio.
    #[serde(default)]
    pub pitch_shift: f64,

    /// Loop enabled — repeat clip content (Logic Pro X style)
    #[serde(default)]
    pub loop_enabled: bool,

    /// Loop count (0 = infinite, 1+ = specific count)
    #[serde(default)]
    pub loop_count: u32,

    /// Crossfade duration at loop point in seconds
    #[serde(default)]
    pub loop_crossfade: f64,

    /// Random start offset range in seconds (0 = disabled)
    #[serde(default)]
    pub loop_random_start: f64,

    /// Loop start boundary in samples (0 = from clip start)
    /// Defines where the loop region begins within the source audio.
    #[serde(default)]
    pub loop_start_samples: u64,

    /// Loop end boundary in samples (0 = use full clip duration)
    /// Defines where the loop region ends within the source audio.
    #[serde(default)]
    pub loop_end_samples: u64,

    /// Per-iteration gain factor (1.0 = unity, <1.0 = decay, >1.0 = crescendo)
    #[serde(default = "default_iteration_gain")]
    pub iteration_gain: f64,

    // Clip-based FX chain (non-destructive, per-clip processing)
    #[serde(default)]
    pub fx_chain: ClipFxChain,

    // Per-item envelopes (Reaper take envelopes)
    // Positions are RELATIVE to clip start — envelope moves with the clip

    /// Pitch envelope: value in semitones (-24 to +24), additive with base pitch_shift
    #[serde(default)]
    pub pitch_envelope: Option<ClipEnvelope>,

    /// Playrate envelope: value as rate multiplier (0.1 to 4.0), multiplied with base stretch_ratio
    #[serde(default)]
    pub playrate_envelope: Option<ClipEnvelope>,

    /// Volume envelope: value as linear gain (0.0 to 2.0), multiplied with base gain
    #[serde(default)]
    pub volume_envelope: Option<ClipEnvelope>,

    /// Pan envelope: value as pan position (-1.0 to 1.0), additive
    #[serde(default)]
    pub pan_envelope: Option<ClipEnvelope>,
}

fn default_stretch_ratio() -> f64 {
    1.0
}

fn default_iteration_gain() -> f64 {
    1.0
}

impl Clip {
    pub fn new(
        track_id: TrackId,
        name: &str,
        source_file: &str,
        start_time: f64,
        duration: f64,
    ) -> Self {
        Self {
            id: ClipId(next_id()),
            track_id,
            name: name.to_string(),
            color: None,
            start_time,
            duration,
            source_file: source_file.to_string(),
            source_offset: 0.0,
            source_duration: duration,
            fade_in: 0.0,
            fade_out: 0.0,
            gain: 1.0,
            muted: false,
            selected: false,
            reversed: false,
            stretch_ratio: 1.0,
            pitch_shift: 0.0,
            loop_enabled: false,
            loop_count: 0,
            loop_crossfade: 0.0,
            loop_random_start: 0.0,
            loop_start_samples: 0,
            loop_end_samples: 0,
            iteration_gain: 1.0,
            fx_chain: ClipFxChain::new(),
            pitch_envelope: None,
            playrate_envelope: None,
            volume_envelope: None,
            pan_envelope: None,
        }
    }

    /// Check if clip has any FX processing
    #[inline]
    pub fn has_fx(&self) -> bool {
        self.fx_chain.has_active_processing()
    }

    /// Add FX to this clip's chain
    pub fn add_fx(&mut self, fx_type: ClipFxType) -> ClipFxSlotId {
        let slot = ClipFxSlot::new(fx_type);
        self.fx_chain.add_slot(slot)
    }

    /// Remove FX from this clip's chain
    pub fn remove_fx(&mut self, slot_id: ClipFxSlotId) -> bool {
        self.fx_chain.remove_slot(slot_id)
    }

    /// Bypass/enable clip FX chain
    pub fn set_fx_bypass(&mut self, bypass: bool) {
        self.fx_chain.bypass = bypass;
    }

    /// Set time stretch ratio (clamped 0.25 to 4.0)
    pub fn set_stretch_ratio(&mut self, ratio: f64) {
        self.stretch_ratio = ratio.clamp(0.25, 4.0);
    }

    /// Set pitch shift in semitones (clamped -24 to +24)
    pub fn set_pitch_shift(&mut self, semitones: f64) {
        self.pitch_shift = semitones.clamp(-24.0, 24.0);
    }

    /// Effective playback rate considering stretch_ratio and pitch_shift.
    /// stretch_ratio affects timing (1.0=normal, 2.0=double speed).
    /// pitch_shift is additive semitones converted to rate multiplier.
    #[inline]
    pub fn effective_playback_rate(&self) -> f64 {
        let pitch_rate = 2.0_f64.powf(self.pitch_shift / 12.0);
        self.stretch_ratio * pitch_rate
    }

    /// End time on timeline (adjusted for stretch ratio)
    #[inline]
    pub fn end_time(&self) -> f64 {
        self.start_time + self.duration
    }

    /// Check if this clip overlaps with another time range
    pub fn overlaps(&self, start: f64, end: f64) -> bool {
        self.start_time < end && self.end_time() > start
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Per-item envelope methods
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable pitch envelope (creates if needed)
    pub fn enable_pitch_envelope(&mut self) -> &mut ClipEnvelope {
        self.pitch_envelope.get_or_insert_with(ClipEnvelope::pitch)
    }

    /// Enable playrate envelope (creates if needed)
    pub fn enable_playrate_envelope(&mut self) -> &mut ClipEnvelope {
        self.playrate_envelope
            .get_or_insert_with(ClipEnvelope::playrate)
    }

    /// Enable volume envelope (creates if needed)
    pub fn enable_volume_envelope(&mut self) -> &mut ClipEnvelope {
        self.volume_envelope
            .get_or_insert_with(ClipEnvelope::volume)
    }

    /// Enable pan envelope (creates if needed)
    pub fn enable_pan_envelope(&mut self) -> &mut ClipEnvelope {
        self.pan_envelope.get_or_insert_with(ClipEnvelope::pan)
    }

    /// Check if any per-item envelope is active
    #[inline]
    pub fn has_active_envelope(&self) -> bool {
        self.pitch_envelope
            .as_ref()
            .is_some_and(|e| e.is_active())
            || self
                .playrate_envelope
                .as_ref()
                .is_some_and(|e| e.is_active())
            || self
                .volume_envelope
                .as_ref()
                .is_some_and(|e| e.is_active())
            || self.pan_envelope.as_ref().is_some_and(|e| e.is_active())
    }

    /// Get effective pitch at clip-relative sample offset.
    /// Combines base pitch_shift + pitch envelope value (additive).
    #[inline]
    pub fn pitch_at(&self, clip_offset_samples: u64) -> f64 {
        let envelope_offset = self
            .pitch_envelope
            .as_ref()
            .filter(|e| e.is_active())
            .map(|e| e.value_at(clip_offset_samples))
            .unwrap_or(0.0);
        (self.pitch_shift + envelope_offset).clamp(-24.0, 24.0)
    }

    /// Get effective playback rate at clip-relative sample offset.
    /// Combines stretch_ratio × playrate envelope × pitch_at() rate factor.
    #[inline]
    pub fn playback_rate_at(&self, clip_offset_samples: u64) -> f64 {
        let rate_env = self
            .playrate_envelope
            .as_ref()
            .filter(|e| e.is_active())
            .map(|e| e.value_at(clip_offset_samples))
            .unwrap_or(1.0);

        let pitch = self.pitch_at(clip_offset_samples);
        let pitch_rate = 2.0_f64.powf(pitch / 12.0);

        self.stretch_ratio * rate_env * pitch_rate
    }

    /// Get effective gain at clip-relative sample offset.
    /// Combines base gain × volume envelope (multiplicative).
    #[inline]
    pub fn gain_at(&self, clip_offset_samples: u64) -> f64 {
        let vol_env = self
            .volume_envelope
            .as_ref()
            .filter(|e| e.is_active())
            .map(|e| e.value_at(clip_offset_samples))
            .unwrap_or(1.0);
        self.gain * vol_env
    }

    /// Get pan offset at clip-relative sample offset.
    /// Returns pan envelope value or 0.0 (center).
    #[inline]
    pub fn pan_at(&self, clip_offset_samples: u64) -> f64 {
        self.pan_envelope
            .as_ref()
            .filter(|e| e.is_active())
            .map(|e| e.value_at(clip_offset_samples))
            .unwrap_or(0.0)
    }

    /// Compute source position at clip-relative sample offset using integrated rate.
    /// This correctly handles time-varying playback rate (pitch + playrate envelopes)
    /// by integrating the rate over time: source_pos = ∫₀^offset rate(t) dt
    ///
    /// For static rate (no envelopes): returns offset * effective_playback_rate
    /// For envelope mode: uses trapezoidal integration of the combined rate curve
    pub fn source_position_at(
        &self,
        clip_offset_samples: u64,
        rate_ratio: f64,
        source_offset_samples: f64,
    ) -> f64 {
        if !self.has_active_envelope()
            || (self.pitch_envelope.is_none() && self.playrate_envelope.is_none())
        {
            // No pitch/rate envelopes: use static calculation (original behavior)
            return clip_offset_samples as f64 * rate_ratio * self.effective_playback_rate()
                + source_offset_samples;
        }

        // Has pitch or rate envelope: integrate the combined rate over time.
        // We iterate both envelope point arrays in sorted order (they're already sorted),
        // evaluating the trapezoidal integral between each pair of time boundaries.
        // ZERO ALLOCATIONS — only stack variables, no Vec/HashMap.

        // Collect boundary offsets from both envelopes by merging sorted point arrays.
        // We process boundaries in ascending order without allocating.
        let pitch_pts = self
            .pitch_envelope
            .as_ref()
            .filter(|e| e.is_active())
            .map(|e| e.points.as_slice())
            .unwrap_or(&[]);
        let rate_pts = self
            .playrate_envelope
            .as_ref()
            .filter(|e| e.is_active())
            .map(|e| e.points.as_slice())
            .unwrap_or(&[]);

        let mut integral = 0.0;
        let mut prev_t: u64 = 0;
        let mut prev_rate = self.playback_rate_at(0);

        // Merge-iterate both sorted point arrays
        let mut pi = 0usize;
        let mut ri = 0usize;

        loop {
            // Find next boundary from either envelope
            let next_pitch = if pi < pitch_pts.len() {
                Some(pitch_pts[pi].offset_samples)
            } else {
                None
            };
            let next_rate = if ri < rate_pts.len() {
                Some(rate_pts[ri].offset_samples)
            } else {
                None
            };

            let next_t = match (next_pitch, next_rate) {
                (Some(p), Some(r)) => {
                    let t = p.min(r);
                    if t >= clip_offset_samples {
                        break;
                    }
                    if p <= r {
                        pi += 1;
                    }
                    if r <= p {
                        ri += 1;
                    }
                    t
                }
                (Some(p), None) => {
                    if p >= clip_offset_samples {
                        break;
                    }
                    pi += 1;
                    p
                }
                (None, Some(r)) => {
                    if r >= clip_offset_samples {
                        break;
                    }
                    ri += 1;
                    r
                }
                (None, None) => break,
            };

            if next_t <= prev_t {
                continue; // Skip duplicates
            }

            let seg_len = (next_t - prev_t) as f64;
            let next_rate_val = self.playback_rate_at(next_t);
            integral += (prev_rate + next_rate_val) * 0.5 * seg_len;

            prev_t = next_t;
            prev_rate = next_rate_val;
        }

        // Final segment: from last boundary to clip_offset_samples
        if clip_offset_samples > prev_t {
            let seg_len = (clip_offset_samples - prev_t) as f64;
            let end_rate = self.playback_rate_at(clip_offset_samples);
            integral += (prev_rate + end_rate) * 0.5 * seg_len;
        }

        integral * rate_ratio + source_offset_samples
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSSFADE
// ═══════════════════════════════════════════════════════════════════════════

/// Crossfade curve type
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub enum CrossfadeCurve {
    /// Straight line (0dB at midpoint)
    Linear,
    /// Equal power/constant power (-3dB at midpoint)
    #[default]
    EqualPower,
    /// Smooth S-curve (slow start/end, fast middle)
    SCurve,
    /// Logarithmic (fast attack, slow release)
    Logarithmic,
    /// Exponential (slow attack, fast release)
    Exponential,
    /// Custom curve defined by control points
    /// Vec of (position, value) where position and value are 0.0-1.0
    Custom(Vec<(f32, f32)>),
}

impl CrossfadeCurve {
    /// Calculate curve value at normalized position (0.0 to 1.0)
    /// Returns fade-in gain (fade-out = 1.0 - this for symmetric)
    #[inline]
    pub fn evaluate(&self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);
        match self {
            CrossfadeCurve::Linear => t,
            CrossfadeCurve::EqualPower => {
                // Equal power: sin/cos crossfade (-3dB at midpoint)
                (t * std::f32::consts::FRAC_PI_2).sin()
            }
            CrossfadeCurve::SCurve => {
                // Smoothstep S-curve: 3t² - 2t³
                t * t * (3.0 - 2.0 * t)
            }
            CrossfadeCurve::Logarithmic => {
                // Logarithmic: fast start, slow end
                // log(1 + 9t) / log(10)
                (1.0 + 9.0 * t).ln() / 10.0_f32.ln()
            }
            CrossfadeCurve::Exponential => {
                // Exponential: slow start, fast end
                // (10^t - 1) / 9
                (10.0_f32.powf(t) - 1.0) / 9.0
            }
            CrossfadeCurve::Custom(points) => Self::evaluate_custom(points, t),
        }
    }

    /// Evaluate custom curve using linear interpolation between points
    fn evaluate_custom(points: &[(f32, f32)], t: f32) -> f32 {
        if points.is_empty() {
            return t; // Fallback to linear
        }
        if points.len() == 1 {
            return points[0].1;
        }

        // Find surrounding points
        let mut prev = (0.0_f32, 0.0_f32);
        let mut next = (1.0_f32, 1.0_f32);

        for &(pos, val) in points {
            if pos <= t {
                prev = (pos, val);
            }
            if pos >= t && next.0 > pos {
                next = (pos, val);
            }
        }

        // Edge cases
        if t <= prev.0 {
            return prev.1;
        }
        if t >= next.0 {
            return next.1;
        }

        // Linear interpolation
        let segment_t = (t - prev.0) / (next.0 - prev.0);
        prev.1 + segment_t * (next.1 - prev.1)
    }

    /// Get fade-out gain for symmetric crossfade
    #[inline]
    pub fn evaluate_fade_out(&self, t: f32) -> f32 {
        self.evaluate(1.0 - t)
    }
}

/// Crossfade shape for asymmetric fades
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CrossfadeShape {
    /// Symmetric - same curve mirrored for both clips
    Symmetric(CrossfadeCurve),
    /// Asymmetric - separate curves for fade-out and fade-in
    Asymmetric {
        fade_out: CrossfadeCurve,
        fade_in: CrossfadeCurve,
    },
}

impl Default for CrossfadeShape {
    fn default() -> Self {
        Self::Symmetric(CrossfadeCurve::default())
    }
}

impl CrossfadeShape {
    /// Create symmetric crossfade
    pub fn symmetric(curve: CrossfadeCurve) -> Self {
        Self::Symmetric(curve)
    }

    /// Create asymmetric crossfade
    pub fn asymmetric(fade_out: CrossfadeCurve, fade_in: CrossfadeCurve) -> Self {
        Self::Asymmetric { fade_out, fade_in }
    }

    /// Calculate gains at normalized position (0.0 to 1.0)
    /// Returns (fade_out_gain, fade_in_gain)
    #[inline]
    pub fn evaluate(&self, t: f32) -> (f32, f32) {
        match self {
            CrossfadeShape::Symmetric(curve) => {
                let fade_in = curve.evaluate(t);
                let fade_out = curve.evaluate(1.0 - t);
                (fade_out, fade_in)
            }
            CrossfadeShape::Asymmetric { fade_out, fade_in } => {
                (fade_out.evaluate(1.0 - t), fade_in.evaluate(t))
            }
        }
    }
}

/// Crossfade between two clips
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Crossfade {
    pub id: CrossfadeId,
    pub track_id: TrackId,
    pub clip_a_id: ClipId,
    pub clip_b_id: ClipId,
    pub start_time: f64,
    pub duration: f64,
    /// Shape controls both curves (symmetric or asymmetric)
    pub shape: CrossfadeShape,
    /// Legacy field for backwards compatibility
    #[serde(default)]
    pub curve: CrossfadeCurve,
}

impl Crossfade {
    pub fn new(
        track_id: TrackId,
        clip_a: ClipId,
        clip_b: ClipId,
        start_time: f64,
        duration: f64,
    ) -> Self {
        Self {
            id: CrossfadeId(next_id()),
            track_id,
            clip_a_id: clip_a,
            clip_b_id: clip_b,
            start_time,
            duration,
            shape: CrossfadeShape::default(),
            curve: CrossfadeCurve::default(),
        }
    }

    /// Create with symmetric curve
    pub fn with_curve(mut self, curve: CrossfadeCurve) -> Self {
        self.shape = CrossfadeShape::Symmetric(curve.clone());
        self.curve = curve;
        self
    }

    /// Create with asymmetric curves
    pub fn with_asymmetric(mut self, fade_out: CrossfadeCurve, fade_in: CrossfadeCurve) -> Self {
        self.shape = CrossfadeShape::Asymmetric { fade_out, fade_in };
        self
    }

    /// Calculate gains at sample position within crossfade
    /// Returns (clip_a_gain, clip_b_gain)
    #[inline]
    pub fn get_gains_at_time(&self, time: f64) -> (f32, f32) {
        if time < self.start_time {
            return (1.0, 0.0);
        }
        if time >= self.start_time + self.duration {
            return (0.0, 1.0);
        }

        let t = ((time - self.start_time) / self.duration) as f32;
        self.shape.evaluate(t)
    }

    /// Calculate gains at sample position (sample-accurate)
    #[inline]
    pub fn get_gains_at_sample(&self, sample: u64, sample_rate: u32) -> (f32, f32) {
        let time = sample as f64 / sample_rate as f64;
        self.get_gains_at_time(time)
    }

    /// Get crossfade end time
    #[inline]
    pub fn end_time(&self) -> f64 {
        self.start_time + self.duration
    }

    /// Check if a time falls within this crossfade
    #[inline]
    pub fn contains_time(&self, time: f64) -> bool {
        time >= self.start_time && time < self.end_time()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARKER
// ═══════════════════════════════════════════════════════════════════════════

/// Timeline marker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Marker {
    pub id: MarkerId,
    pub time: f64,
    pub name: String,
    pub color: u32,
}

impl Marker {
    pub fn new(time: f64, name: &str, color: u32) -> Self {
        Self {
            id: MarkerId(next_id()),
            time,
            name: name.to_string(),
            color,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOOP REGION
// ═══════════════════════════════════════════════════════════════════════════

/// Loop region on timeline
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct LoopRegion {
    pub start: f64,
    pub end: f64,
    pub enabled: bool,
}

impl Default for LoopRegion {
    fn default() -> Self {
        Self {
            start: 0.0,
            end: 8.0,
            enabled: false,
        }
    }
}

impl LoopRegion {
    pub fn duration(&self) -> f64 {
        self.end - self.start
    }
}

/// Cycle region for cycle recording (Cubase-style)
/// Similar to loop but for recording multiple takes in a region
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct CycleRegion {
    pub start: f64,
    pub end: f64,
    pub enabled: bool,
    /// Maximum cycles to record (None = unlimited)
    pub max_cycles: Option<u32>,
    /// Current cycle count during recording
    pub current_cycle: u32,
}

impl Default for CycleRegion {
    fn default() -> Self {
        Self {
            start: 0.0,
            end: 8.0,
            enabled: false,
            max_cycles: None,
            current_cycle: 0,
        }
    }
}

impl CycleRegion {
    pub fn duration(&self) -> f64 {
        self.end - self.start
    }

    pub fn reset_cycles(&mut self) {
        self.current_cycle = 0;
    }

    pub fn increment_cycle(&mut self) -> bool {
        self.current_cycle += 1;
        if let Some(max) = self.max_cycles {
            self.current_cycle < max
        } else {
            true // Unlimited cycles
        }
    }
}

/// Punch region for punch in/out recording
/// Records only within the specified time range
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct PunchRegion {
    pub punch_in: f64,
    pub punch_out: f64,
    pub enabled: bool,
    /// Pre-roll bars before punch in
    pub pre_roll_bars: f64,
    /// Post-roll bars after punch out
    pub post_roll_bars: f64,
}

impl Default for PunchRegion {
    fn default() -> Self {
        Self {
            punch_in: 0.0,
            punch_out: 8.0,
            enabled: false,
            pre_roll_bars: 2.0,
            post_roll_bars: 1.0,
        }
    }
}

impl PunchRegion {
    pub fn duration(&self) -> f64 {
        self.punch_out - self.punch_in
    }

    /// Check if time is within punch region
    pub fn is_punch_active(&self, time: f64) -> bool {
        self.enabled && time >= self.punch_in && time <= self.punch_out
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RENDER REGIONS (Named timeline regions for batch export)
// ═══════════════════════════════════════════════════════════════════════════

/// Named region on the timeline for batch rendering / Region Render Matrix.
///
/// Sound designers use named regions to mark individual sounds on the timeline
/// (e.g. "footstep_wood_01", "explosion_large_03", "UI_hover_click") and then
/// batch-render them all in one operation with configurable format settings.
///
/// ## Reaper Equivalent
/// Region Manager + Region Render Matrix — the killer feature for sound design.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderRegion {
    /// Unique region identifier
    pub id: RenderRegionId,
    /// Display name (used as export filename base)
    pub name: String,
    /// Start time on timeline (seconds)
    pub start: f64,
    /// End time on timeline (seconds)
    pub end: f64,
    /// Color for UI display (ARGB u32)
    pub color: u32,
    /// Include in batch render (can be toggled off per-region)
    pub enabled: bool,
    /// Include FX tail after region end
    pub include_tail: bool,
    /// Tail duration in seconds (reverb/delay decay)
    pub tail_seconds: f64,
    /// Per-region normalize override (None = use matrix default)
    pub normalize: Option<bool>,
    /// Per-region normalize target in dBFS (None = use matrix default)
    pub normalize_target: Option<f64>,
    /// Tags for filtering/grouping (e.g. ["footsteps", "wood", "indoor"])
    pub tags: Vec<String>,
    /// Sort/display order
    pub order: u32,
    /// Notes / description
    pub notes: String,
}

impl RenderRegion {
    /// Create a new render region
    pub fn new(name: &str, start: f64, end: f64) -> Self {
        Self {
            id: RenderRegionId(next_id()),
            name: name.to_string(),
            start,
            end,
            color: 0xFF4CAF50, // Green default
            enabled: true,
            include_tail: true,
            tail_seconds: 0.5,
            normalize: None,
            normalize_target: None,
            tags: Vec::new(),
            order: 0,
            notes: String::new(),
        }
    }

    /// Duration in seconds
    pub fn duration(&self) -> f64 {
        self.end - self.start
    }

    /// Total render duration including tail
    pub fn render_duration(&self) -> f64 {
        let base = self.duration();
        if self.include_tail {
            base + self.tail_seconds
        } else {
            base
        }
    }

    /// Check if a time falls within this region
    pub fn contains_time(&self, time: f64) -> bool {
        time >= self.start && time <= self.end
    }

    /// Check if this region overlaps with another time range
    pub fn overlaps(&self, start: f64, end: f64) -> bool {
        self.start < end && self.end > start
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RAZOR EDITS (Reaper-style Time-Area Selection)
// ═══════════════════════════════════════════════════════════════════════════

/// What content a razor edit area selects
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RazorContent {
    /// Select media items (clips) within the time range
    Media,
    /// Select automation envelope points within the time range
    Envelope,
    /// Select both media and envelope data
    Both,
}

impl Default for RazorContent {
    fn default() -> Self {
        Self::Both
    }
}

/// A single razor edit area — a time range on a specific track.
///
/// Razor edits are independent per-track time selections that can span
/// partial clips. Multiple razor areas can exist simultaneously on
/// different tracks (and even multiple per track). Operations like
/// cut/copy/delete/move/stretch act on all active razor areas at once.
///
/// This is fundamentally different from clip selection (which selects
/// entire clips) — razor edits select *time ranges* and can slice
/// through clips at arbitrary positions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RazorArea {
    /// Unique ID for this razor area
    pub id: RazorAreaId,
    /// Track this area belongs to
    pub track_id: TrackId,
    /// Start time in seconds (inclusive)
    pub start: f64,
    /// End time in seconds (exclusive)
    pub end: f64,
    /// What content this area selects
    pub content: RazorContent,
}

impl RazorArea {
    /// Create a new razor area
    pub fn new(track_id: TrackId, start: f64, end: f64) -> Self {
        let (s, e) = if start <= end {
            (start.max(0.0), end.max(0.0))
        } else {
            (end.max(0.0), start.max(0.0))
        };
        Self {
            id: RazorAreaId(next_id()),
            track_id,
            start: s,
            end: e,
            content: RazorContent::default(),
        }
    }

    /// Create with specific content type
    pub fn with_content(track_id: TrackId, start: f64, end: f64, content: RazorContent) -> Self {
        let mut area = Self::new(track_id, start, end);
        area.content = content;
        area
    }

    /// Duration of this area
    pub fn duration(&self) -> f64 {
        self.end - self.start
    }

    /// Check if this area is empty (zero or negative duration)
    pub fn is_empty(&self) -> bool {
        self.end <= self.start + 0.0001 // ~4 samples at 48kHz tolerance
    }

    /// Check if a time point falls within this area
    pub fn contains_time(&self, time: f64) -> bool {
        time >= self.start && time < self.end
    }

    /// Check if this area overlaps with a clip's time range
    pub fn overlaps_clip(&self, clip_start: f64, clip_end: f64) -> bool {
        self.start < clip_end && self.end > clip_start
    }

    /// Check if this area fully contains a clip
    pub fn fully_contains_clip(&self, clip_start: f64, clip_end: f64) -> bool {
        self.start <= clip_start && self.end >= clip_end
    }

    /// Get the intersection of this area with a clip's time range
    /// Returns None if no overlap
    pub fn clip_intersection(&self, clip_start: f64, clip_end: f64) -> Option<(f64, f64)> {
        let inter_start = self.start.max(clip_start);
        let inter_end = self.end.min(clip_end);
        if inter_start < inter_end {
            Some((inter_start, inter_end))
        } else {
            None
        }
    }

    /// Set new time bounds (auto-sorts start/end)
    pub fn set_bounds(&mut self, start: f64, end: f64) {
        if start <= end {
            self.start = start.max(0.0);
            self.end = end.max(0.0);
        } else {
            self.start = end.max(0.0);
            self.end = start.max(0.0);
        }
    }

    /// Move this area by a time delta
    pub fn offset_time(&mut self, delta: f64) {
        let new_start = (self.start + delta).max(0.0);
        let dur = self.duration();
        self.start = new_start;
        self.end = new_start + dur;
    }

    /// Stretch this area from one edge
    pub fn stretch_from_left(&mut self, new_start: f64) {
        self.start = new_start.max(0.0).min(self.end - 0.001);
    }

    pub fn stretch_from_right(&mut self, new_end: f64) {
        self.end = new_end.max(self.start + 0.001);
    }

    /// Whether media items should be affected
    pub fn affects_media(&self) -> bool {
        matches!(self.content, RazorContent::Media | RazorContent::Both)
    }

    /// Whether envelope data should be affected
    pub fn affects_envelope(&self) -> bool {
        matches!(self.content, RazorContent::Envelope | RazorContent::Both)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Central manager for all tracks, clips, crossfades, and markers
// ═══════════════════════════════════════════════════════════════════════════
// MIX SNAPSHOTS (SWS-style Save/Recall Mix States)
// ═══════════════════════════════════════════════════════════════════════════

/// Categories of mix state that can be selectively captured/recalled.
/// Mirrors Reaper SWS Mix Snapshots: 10 independent categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u32)]
pub enum SnapshotCategory {
    Volume = 0,
    Pan = 1,
    MuteSolo = 2,
    FxChain = 3, // Reserved — FX chain state lives in Dart/FxContainer, not Track struct
    Sends = 4,
    Phase = 5,
    OutputBus = 6,
    ChannelConfig = 7,
    TrackName = 8,
    ClipGain = 9,
}

impl SnapshotCategory {
    pub fn all() -> &'static [SnapshotCategory] {
        &[
            Self::Volume,
            Self::Pan,
            Self::MuteSolo,
            Self::FxChain,
            Self::Sends,
            Self::Phase,
            Self::OutputBus,
            Self::ChannelConfig,
            Self::TrackName,
            Self::ClipGain,
        ]
    }

    pub fn from_u32(v: u32) -> Option<Self> {
        match v {
            0 => Some(Self::Volume),
            1 => Some(Self::Pan),
            2 => Some(Self::MuteSolo),
            3 => Some(Self::FxChain),
            4 => Some(Self::Sends),
            5 => Some(Self::Phase),
            6 => Some(Self::OutputBus),
            7 => Some(Self::ChannelConfig),
            8 => Some(Self::TrackName),
            9 => Some(Self::ClipGain),
            _ => None,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Volume => "Volume",
            Self::Pan => "Pan",
            Self::MuteSolo => "Mute/Solo",
            Self::FxChain => "FX Chain",
            Self::Sends => "Sends",
            Self::Phase => "Phase",
            Self::OutputBus => "Output Bus",
            Self::ChannelConfig => "Channel Config",
            Self::TrackName => "Track Name",
            Self::ClipGain => "Clip Gain",
        }
    }
}

/// Snapshot of a single track's send slots
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotSends {
    pub sends: [TrackSendSlot; MAX_TRACK_SENDS],
}

/// Snapshot of a single clip's gain state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotClipGain {
    pub clip_id: ClipId,
    pub gain: f64,
    pub muted: bool,
}

/// Per-track snapshot data — only populated categories are Some
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackSnapshotData {
    pub track_id: TrackId,
    pub volume: Option<f64>,
    pub pan: Option<(f64, f64)>,      // (pan_left, pan_right)
    pub muted: Option<bool>,
    pub soloed: Option<bool>,
    pub phase_inverted: Option<bool>,
    pub output_bus: Option<OutputBus>,
    pub channels: Option<u32>,
    pub name: Option<String>,
    pub sends: Option<SnapshotSends>,
}

/// Complete mix snapshot — captures state of all tracks at a point in time
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MixSnapshot {
    pub id: MixSnapshotId,
    pub name: String,
    pub description: String,
    /// Which categories were captured in this snapshot
    pub categories: Vec<SnapshotCategory>,
    /// Per-track data
    pub tracks: Vec<TrackSnapshotData>,
    /// Clip gain data (separate — clips aren't 1:1 with tracks)
    pub clip_gains: Vec<SnapshotClipGain>,
    /// Timestamp (seconds since epoch)
    pub created_at: f64,
    /// Optional: only snapshot specific track IDs (empty = all tracks)
    pub track_filter: Vec<TrackId>,
}

impl MixSnapshot {
    pub fn has_category(&self, cat: SnapshotCategory) -> bool {
        self.categories.contains(&cat)
    }
}

pub struct TrackManager {
    /// All tracks - DashMap for lock-free concurrent access (audio thread safe)
    pub tracks: DashMap<TrackId, Track>,
    /// All clips - DashMap for lock-free concurrent access (audio thread safe)
    pub clips: DashMap<ClipId, Clip>,
    /// Crossfades between clips - DashMap for lock-free concurrent access
    pub crossfades: DashMap<CrossfadeId, Crossfade>,
    /// Timeline markers
    pub markers: RwLock<Vec<Marker>>,
    /// Loop region
    pub loop_region: RwLock<LoopRegion>,
    /// Cycle region (for cycle recording)
    pub cycle_region: RwLock<CycleRegion>,
    /// Punch region (for punch in/out recording)
    pub punch_region: RwLock<PunchRegion>,
    /// Track ordering
    pub track_order: RwLock<Vec<TrackId>>,
    /// Comp lanes for recording takes
    pub comp_lanes: RwLock<HashMap<CompLaneId, CompLane>>,
    /// All takes (for comping)
    pub takes: RwLock<HashMap<TakeId, Take>>,
    /// Comp regions (selected portions of takes)
    pub comp_regions: RwLock<HashMap<TrackId, Vec<CompRegion>>>,
    /// Track templates (user-saved and defaults)
    pub templates: RwLock<HashMap<String, TrackTemplate>>,
    /// Solo active flag - true if any track is soloed (Cubase-style solo behavior)
    pub solo_active: AtomicBool,
    /// Named render regions for Region Render Matrix (batch export)
    pub render_regions: RwLock<Vec<RenderRegion>>,
    /// Razor edit areas — per-track time-range selections (Reaper-style)
    pub razor_areas: RwLock<Vec<RazorArea>>,
    /// Mix snapshots — save/recall mix states (SWS-style)
    pub mix_snapshots: RwLock<Vec<MixSnapshot>>,
}

impl TrackManager {
    pub fn new() -> Self {
        // Initialize default templates
        let mut templates = HashMap::new();
        let defaults = [
            TrackTemplate::default_audio(),
            TrackTemplate::default_vocal(),
            TrackTemplate::default_drums(),
            TrackTemplate::default_bass(),
        ];
        for tpl in defaults {
            templates.insert(tpl.id.clone(), tpl);
        }

        Self {
            tracks: DashMap::new(),
            clips: DashMap::new(),
            crossfades: DashMap::new(),
            markers: RwLock::new(Vec::new()),
            loop_region: RwLock::new(LoopRegion::default()),
            cycle_region: RwLock::new(CycleRegion::default()),
            punch_region: RwLock::new(PunchRegion::default()),
            track_order: RwLock::new(Vec::new()),
            comp_lanes: RwLock::new(HashMap::new()),
            takes: RwLock::new(HashMap::new()),
            comp_regions: RwLock::new(HashMap::new()),
            templates: RwLock::new(templates),
            solo_active: AtomicBool::new(false),
            render_regions: RwLock::new(Vec::new()),
            razor_areas: RwLock::new(Vec::new()),
            mix_snapshots: RwLock::new(Vec::new()),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CYCLE REGION OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current cycle region
    pub fn get_cycle_region(&self) -> CycleRegion {
        *self.cycle_region.read()
    }

    /// Set cycle region start and end times
    pub fn set_cycle_region(&self, start: f64, end: f64) {
        let mut region = self.cycle_region.write();
        region.start = start;
        region.end = end;
    }

    /// Set cycle region enabled state
    pub fn set_cycle_enabled(&self, enabled: bool) {
        self.cycle_region.write().enabled = enabled;
    }

    /// Set maximum cycles for recording (None = unlimited)
    pub fn set_cycle_max(&self, max_cycles: Option<u32>) {
        self.cycle_region.write().max_cycles = max_cycles;
    }

    /// Reset cycle counter
    pub fn reset_cycle_counter(&self) {
        self.cycle_region.write().current_cycle = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PUNCH REGION OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current punch region
    pub fn get_punch_region(&self) -> PunchRegion {
        *self.punch_region.read()
    }

    /// Set punch in/out times
    pub fn set_punch_region(&self, punch_in: f64, punch_out: f64) {
        let mut region = self.punch_region.write();
        region.punch_in = punch_in;
        region.punch_out = punch_out;
    }

    /// Set punch enabled state
    pub fn set_punch_enabled(&self, enabled: bool) {
        self.punch_region.write().enabled = enabled;
    }

    /// Set pre-roll bars
    pub fn set_punch_pre_roll(&self, bars: f64) {
        self.punch_region.write().pre_roll_bars = bars;
    }

    /// Set post-roll bars
    pub fn set_punch_post_roll(&self, bars: f64) {
        self.punch_region.write().post_roll_bars = bars;
    }

    /// Check if time is within punch region
    pub fn is_punch_active(&self, time: f64) -> bool {
        self.punch_region.read().is_punch_active(time)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RENDER REGION OPERATIONS (Region Render Matrix)
    // ═══════════════════════════════════════════════════════════════════════

    /// Add a new render region. Returns the region ID.
    pub fn add_render_region(&self, name: &str, start: f64, end: f64) -> RenderRegionId {
        let mut regions = self.render_regions.write();
        let mut region = RenderRegion::new(name, start, end);
        region.order = regions.len() as u32;
        let id = region.id;
        regions.push(region);
        id
    }

    /// Remove a render region by ID. Returns true if found.
    pub fn remove_render_region(&self, id: RenderRegionId) -> bool {
        let mut regions = self.render_regions.write();
        if let Some(idx) = regions.iter().position(|r| r.id == id) {
            regions.remove(idx);
            // Re-order remaining
            for (i, r) in regions.iter_mut().enumerate() {
                r.order = i as u32;
            }
            true
        } else {
            false
        }
    }

    /// Update a render region. Applies closure to the region if found.
    pub fn update_render_region<F: FnOnce(&mut RenderRegion)>(
        &self,
        id: RenderRegionId,
        updater: F,
    ) -> bool {
        let mut regions = self.render_regions.write();
        if let Some(region) = regions.iter_mut().find(|r| r.id == id) {
            updater(region);
            true
        } else {
            false
        }
    }

    /// Get a clone of a render region by ID
    pub fn get_render_region(&self, id: RenderRegionId) -> Option<RenderRegion> {
        let regions = self.render_regions.read();
        regions.iter().find(|r| r.id == id).cloned()
    }

    /// Get all render regions sorted by order
    pub fn get_render_regions(&self) -> Vec<RenderRegion> {
        let regions = self.render_regions.read();
        let mut result: Vec<RenderRegion> = regions.clone();
        result.sort_by_key(|r| r.order);
        result
    }

    /// Get only enabled render regions sorted by start time
    pub fn get_enabled_render_regions(&self) -> Vec<RenderRegion> {
        let regions = self.render_regions.read();
        let mut result: Vec<RenderRegion> = regions.iter().filter(|r| r.enabled).cloned().collect();
        result.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap_or(std::cmp::Ordering::Equal));
        result
    }

    /// Get render regions by tag
    pub fn get_render_regions_by_tag(&self, tag: &str) -> Vec<RenderRegion> {
        let regions = self.render_regions.read();
        regions
            .iter()
            .filter(|r| r.tags.iter().any(|t| t == tag))
            .cloned()
            .collect()
    }

    /// Get count of render regions
    pub fn render_region_count(&self) -> usize {
        self.render_regions.read().len()
    }

    /// Clear all render regions
    pub fn clear_render_regions(&self) {
        self.render_regions.write().clear();
    }

    /// Create render regions from existing clips (auto-detect from timeline)
    /// Each clip becomes a render region with the clip name
    pub fn create_regions_from_clips(&self) -> Vec<RenderRegionId> {
        let mut ids = Vec::new();
        let regions_to_add: Vec<(String, f64, f64)> = self
            .clips
            .iter()
            .map(|entry| {
                let clip = entry.value();
                let name = if clip.name.is_empty() {
                    format!("clip_{}", clip.id.0)
                } else {
                    clip.name.clone()
                };
                (name, clip.start_time, clip.start_time + clip.duration)
            })
            .collect();

        for (name, start, end) in regions_to_add {
            let id = self.add_render_region(&name, start, end);
            ids.push(id);
        }
        ids
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRACK OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new track
    pub fn create_track(&self, name: &str, color: u32, output_bus: OutputBus) -> TrackId {
        let mut track = Track::new(name, color, output_bus);
        let id = track.id;

        // Set order to end
        let mut order = self.track_order.write();
        track.order = order.len();
        order.push(id);

        self.tracks.insert(id, track);
        id
    }

    /// Delete a track and all its clips
    pub fn delete_track(&self, track_id: TrackId) {
        // Remove all clips on this track
        let clip_ids: Vec<ClipId> = self
            .clips
            .iter()
            .filter(|entry| entry.value().track_id == track_id)
            .map(|entry| entry.value().id)
            .collect();

        for clip_id in clip_ids {
            self.delete_clip(clip_id);
        }

        // Remove from order
        self.track_order.write().retain(|&id| id != track_id);

        // Remove track
        self.tracks.remove(&track_id);
    }

    /// Get track by ID
    pub fn get_track(&self, track_id: TrackId) -> Option<Track> {
        self.tracks.get(&track_id).map(|r| r.clone())
    }

    /// Get all tracks in order
    pub fn get_all_tracks(&self) -> Vec<Track> {
        let order = self.track_order.read();
        order
            .iter()
            .filter_map(|id| self.tracks.get(id).map(|r| r.clone()))
            .collect()
    }

    /// Update track properties
    pub fn update_track<F>(&self, track_id: TrackId, f: F)
    where
        F: FnOnce(&mut Track),
    {
        if let Some(mut track) = self.tracks.get_mut(&track_id) {
            f(&mut track);
        }
    }

    /// Reorder tracks
    pub fn reorder_tracks(&self, new_order: Vec<TrackId>) {
        let mut order = self.track_order.write();
        *order = new_order;

        // Update track order fields
        for (idx, id) in order.iter().enumerate() {
            if let Some(mut track) = self.tracks.get_mut(id) {
                track.order = idx;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SOLO OPERATIONS (Cubase-style exclusive solo)
    // ═══════════════════════════════════════════════════════════════════════

    /// Update solo_active flag based on current track states
    /// Call this after any track solo state changes
    pub fn update_solo_state(&self) {
        let any_soloed = self.tracks.iter().any(|entry| entry.value().soloed);
        self.solo_active.store(any_soloed, Ordering::SeqCst);
    }

    /// Check if solo mode is active (any track is soloed)
    pub fn is_solo_active(&self) -> bool {
        self.solo_active.load(Ordering::SeqCst)
    }

    /// Check if a track should be audible considering solo state
    /// Returns true if track should play, false if it should be silent
    /// Logic: If solo_active AND this track is NOT soloed AND NOT muted → silent
    ///        If track is muted → silent
    ///        Otherwise → audible
    pub fn is_track_audible(&self, track_id: TrackId) -> bool {
        if let Some(track) = self.tracks.get(&track_id) {
            // Muted tracks are never audible
            if track.muted {
                return false;
            }
            // If solo is active, only soloed tracks are audible
            if self.solo_active.load(Ordering::SeqCst) && !track.soloed {
                return false;
            }
            true
        } else {
            false
        }
    }

    /// Set track solo state and update global solo_active flag
    pub fn set_track_solo(&self, track_id: TrackId, soloed: bool) {
        if let Some(mut track) = self.tracks.get_mut(&track_id) {
            track.soloed = soloed;
        }
        self.update_solo_state();
    }

    /// Clear all solos (unsolo all tracks)
    pub fn clear_all_solos(&self) {
        for mut entry in self.tracks.iter_mut() {
            entry.value_mut().soloed = false;
        }
        self.solo_active.store(false, Ordering::SeqCst);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLIP OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Add a new clip
    pub fn add_clip(&self, clip: Clip) -> ClipId {
        let id = clip.id;
        self.clips.insert(id, clip);
        id
    }

    /// Create and add a clip from an imported audio file
    pub fn create_clip(
        &self,
        track_id: TrackId,
        name: &str,
        source_file: &str,
        start_time: f64,
        duration: f64,
        source_duration: f64,
    ) -> ClipId {
        let mut clip = Clip::new(track_id, name, source_file, start_time, duration);
        clip.source_duration = source_duration;
        self.add_clip(clip)
    }

    /// Delete a clip
    pub fn delete_clip(&self, clip_id: ClipId) {
        // Remove associated crossfades
        let xfade_ids: Vec<CrossfadeId> = self
            .crossfades
            .iter()
            .filter(|entry| {
                let x = entry.value();
                x.clip_a_id == clip_id || x.clip_b_id == clip_id
            })
            .map(|entry| entry.value().id)
            .collect();

        for xfade_id in xfade_ids {
            self.crossfades.remove(&xfade_id);
        }

        self.clips.remove(&clip_id);
    }

    /// Get clip by ID
    pub fn get_clip(&self, clip_id: ClipId) -> Option<Clip> {
        self.clips.get(&clip_id).map(|r| r.clone())
    }

    /// Get all clips for a track
    pub fn get_clips_for_track(&self, track_id: TrackId) -> Vec<Clip> {
        self.clips
            .iter()
            .filter(|entry| entry.value().track_id == track_id)
            .map(|entry| entry.value().clone())
            .collect()
    }

    /// Get all clips sorted by start time
    pub fn get_all_clips(&self) -> Vec<Clip> {
        let mut clips: Vec<_> = self
            .clips
            .iter()
            .map(|entry| entry.value().clone())
            .collect();
        clips.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        clips
    }

    /// Move clip to new position (and optionally new track)
    pub fn move_clip(&self, clip_id: ClipId, new_track_id: TrackId, new_start_time: f64) {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.track_id = new_track_id;
            clip.start_time = new_start_time.max(0.0);
        }
    }

    /// Resize clip (change start, duration, and source offset)
    pub fn resize_clip(
        &self,
        clip_id: ClipId,
        new_start_time: f64,
        new_duration: f64,
        new_source_offset: f64,
    ) {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.start_time = new_start_time.max(0.0);
            clip.duration = new_duration.max(0.001);
            clip.source_offset = new_source_offset.max(0.0);
        }
    }

    /// Split clip at given time, returns IDs of both resulting clips
    pub fn split_clip(&self, clip_id: ClipId, split_time: f64) -> Option<(ClipId, ClipId)> {
        let original = self.get_clip(clip_id)?;

        // Validate split point is within clip
        if split_time <= original.start_time || split_time >= original.end_time() {
            return None;
        }

        let split_offset = split_time - original.start_time;

        // Create left clip (modify original in place)
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.duration = split_offset;
            clip.name = format!("{} (L)", original.name);
        }

        // Create right clip
        let mut right_clip = Clip::new(
            original.track_id,
            &format!("{} (R)", original.name),
            &original.source_file,
            split_time,
            original.duration - split_offset,
        );
        right_clip.source_offset = original.source_offset + split_offset;
        right_clip.source_duration = original.source_duration;
        right_clip.gain = original.gain;
        right_clip.color = original.color;

        let right_id = self.add_clip(right_clip);

        Some((clip_id, right_id))
    }

    /// Duplicate a clip
    pub fn duplicate_clip(&self, clip_id: ClipId) -> Option<ClipId> {
        let original = self.get_clip(clip_id)?;

        let mut new_clip = Clip::new(
            original.track_id,
            &format!("{} (copy)", original.name),
            &original.source_file,
            original.end_time(), // Place after original
            original.duration,
        );
        new_clip.source_offset = original.source_offset;
        new_clip.source_duration = original.source_duration;
        new_clip.fade_in = original.fade_in;
        new_clip.fade_out = original.fade_out;
        new_clip.gain = original.gain;
        new_clip.color = original.color;

        Some(self.add_clip(new_clip))
    }

    /// Update clip properties
    pub fn update_clip<F>(&self, clip_id: ClipId, f: F)
    where
        F: FnOnce(&mut Clip),
    {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            f(&mut clip);
        }
    }

    /// Set clip selection state
    pub fn select_clip(&self, clip_id: ClipId, selected: bool) {
        self.update_clip(clip_id, |c| c.selected = selected);
    }

    /// Clear all clip selections
    pub fn clear_selection(&self) {
        for mut entry in self.clips.iter_mut() {
            entry.value_mut().selected = false;
        }
    }

    /// Get selected clips
    pub fn get_selected_clips(&self) -> Vec<Clip> {
        self.clips
            .iter()
            .filter(|entry| entry.value().selected)
            .map(|entry| entry.value().clone())
            .collect()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RAZOR EDIT OPERATIONS (Reaper-style per-track time selection)
    // ═══════════════════════════════════════════════════════════════════════

    /// Add a razor edit area to a track.
    /// Returns the ID of the new area.
    pub fn add_razor_area(&self, track_id: TrackId, start: f64, end: f64) -> RazorAreaId {
        let area = RazorArea::new(track_id, start, end);
        let id = area.id;
        self.razor_areas.write().push(area);
        id
    }

    /// Add a razor area with specific content type
    pub fn add_razor_area_with_content(
        &self,
        track_id: TrackId,
        start: f64,
        end: f64,
        content: RazorContent,
    ) -> RazorAreaId {
        let area = RazorArea::with_content(track_id, start, end, content);
        let id = area.id;
        self.razor_areas.write().push(area);
        id
    }

    /// Update razor area bounds (during drag)
    pub fn update_razor_area(&self, area_id: RazorAreaId, start: f64, end: f64) {
        let mut areas = self.razor_areas.write();
        if let Some(area) = areas.iter_mut().find(|a| a.id == area_id) {
            area.set_bounds(start, end);
        }
    }

    /// Remove a specific razor area
    pub fn remove_razor_area(&self, area_id: RazorAreaId) {
        self.razor_areas.write().retain(|a| a.id != area_id);
    }

    /// Clear all razor edit areas
    pub fn clear_razor_areas(&self) {
        self.razor_areas.write().clear();
    }

    /// Clear razor areas for a specific track
    pub fn clear_track_razor_areas(&self, track_id: TrackId) {
        self.razor_areas.write().retain(|a| a.track_id != track_id);
    }

    /// Get all razor areas
    pub fn get_razor_areas(&self) -> Vec<RazorArea> {
        self.razor_areas.read().clone()
    }

    /// Get razor areas for a specific track
    pub fn get_track_razor_areas(&self, track_id: TrackId) -> Vec<RazorArea> {
        self.razor_areas
            .read()
            .iter()
            .filter(|a| a.track_id == track_id)
            .cloned()
            .collect()
    }

    /// Check if any razor areas exist
    pub fn has_razor_areas(&self) -> bool {
        !self.razor_areas.read().is_empty()
    }

    /// Get clips affected by all razor areas (clips that overlap any razor area)
    pub fn get_razor_affected_clips(&self) -> Vec<(RazorAreaId, ClipId, f64, f64)> {
        let areas = self.razor_areas.read();
        let mut result = Vec::new();

        for area in areas.iter() {
            if !area.affects_media() {
                continue;
            }
            for entry in self.clips.iter() {
                let clip = entry.value();
                if clip.track_id != area.track_id {
                    continue;
                }
                if let Some((inter_start, inter_end)) =
                    area.clip_intersection(clip.start_time, clip.end_time())
                {
                    result.push((area.id, clip.id, inter_start, inter_end));
                }
            }
        }
        result
    }

    /// Merge overlapping razor areas per-track into non-overlapping time ranges.
    /// Returns Vec<(TrackId, start, end)> sorted by track then time.
    /// Only includes areas that affect media.
    fn merged_razor_ranges(areas: &[RazorArea]) -> Vec<(TrackId, f64, f64)> {
        // Group by track
        let mut by_track: HashMap<TrackId, Vec<(f64, f64)>> = HashMap::new();
        for area in areas {
            if !area.affects_media() {
                continue;
            }
            by_track
                .entry(area.track_id)
                .or_default()
                .push((area.start, area.end));
        }

        let mut result = Vec::new();
        for (track_id, mut ranges) in by_track {
            // Sort by start time
            ranges.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());

            // Merge overlapping/adjacent ranges
            let mut merged: Vec<(f64, f64)> = Vec::new();
            for (s, e) in ranges {
                if let Some(last) = merged.last_mut() {
                    if s <= last.1 + 0.001 {
                        // Overlapping or adjacent — extend
                        last.1 = last.1.max(e);
                        continue;
                    }
                }
                merged.push((s, e));
            }

            for (s, e) in merged {
                result.push((track_id, s, e));
            }
        }
        result
    }

    /// Isolate clips within merged razor ranges by splitting at boundaries.
    /// Returns Vec of clip IDs that are fully inside the razor ranges.
    /// Each clip is split at most once per boundary — no double-processing.
    fn isolate_razor_clips(&self, merged: &[(TrackId, f64, f64)]) -> Vec<ClipId> {
        let mut isolated = Vec::new();

        for &(track_id, range_start, range_end) in merged {
            let track_clips = self.get_clips_for_track(track_id);
            for clip in &track_clips {
                let clip_end = clip.end_time();

                // Skip clips that don't overlap this range
                if clip.start_time >= range_end || clip_end <= range_start {
                    continue;
                }

                if range_start <= clip.start_time && range_end >= clip_end {
                    // Clip fully inside range — no split needed
                    isolated.push(clip.id);
                } else {
                    // Partial overlap — split at boundaries
                    let mut inner_id = clip.id;

                    // Split at range start if inside clip
                    if range_start > clip.start_time + 0.001 {
                        if let Some((_left, right)) = self.split_clip(inner_id, range_start) {
                            inner_id = right;
                        }
                    }

                    // Split at range end if inside the current piece
                    if let Some(c) = self.get_clip(inner_id) {
                        if range_end < c.end_time() - 0.001 {
                            if let Some((left, _right)) = self.split_clip(inner_id, range_end) {
                                inner_id = left;
                            }
                        }
                    }

                    isolated.push(inner_id);
                }
            }
        }

        isolated
    }

    /// Move all razor areas horizontally by a time delta.
    /// Also moves affected clip content.
    pub fn razor_move(&self, delta_time: f64, delta_track: Option<TrackId>) {
        let areas = self.razor_areas.read().clone();
        if areas.is_empty() {
            return;
        }

        // Phase 1: Merge overlapping areas, isolate clips
        let merged = Self::merged_razor_ranges(&areas);
        let clip_ids = self.isolate_razor_clips(&merged);

        // Phase 2: Apply moves
        for clip_id in &clip_ids {
            if let Some(mut clip) = self.clips.get_mut(clip_id) {
                clip.start_time = (clip.start_time + delta_time).max(0.0);
                if let Some(tid) = delta_track {
                    clip.track_id = tid;
                }
            }
        }

        // Phase 3: Move razor areas themselves
        drop(areas);
        let mut areas = self.razor_areas.write();
        for area in areas.iter_mut() {
            area.offset_time(delta_time);
            if let Some(tid) = delta_track {
                area.track_id = tid;
            }
        }
    }

    /// Delete content within all razor areas.
    /// Clips fully inside are deleted. Clips partially inside are trimmed.
    pub fn razor_delete(&self) {
        let areas = self.razor_areas.read().clone();
        if areas.is_empty() {
            return;
        }

        let merged = Self::merged_razor_ranges(&areas);
        let isolated = self.isolate_razor_clips(&merged);

        // All isolated clips are fully within merged ranges — delete them
        for clip_id in isolated {
            self.delete_clip(clip_id);
        }

        // Clear razor areas after delete
        self.clear_razor_areas();
    }

    /// Split clips at all razor area boundaries.
    /// Does not delete or move anything — just creates split points.
    pub fn razor_split(&self) {
        let areas = self.razor_areas.read().clone();
        if areas.is_empty() {
            return;
        }

        let merged = Self::merged_razor_ranges(&areas);
        // isolate_razor_clips already splits at all merged boundaries
        let _ = self.isolate_razor_clips(&merged);

        self.clear_razor_areas();
    }

    /// Copy clips within razor areas and return as a clipboard-ready collection.
    /// Returns Vec of (relative_time_offset, track_id, clip_data) tuples.
    /// The earliest razor start is time 0.
    pub fn razor_copy(&self) -> Vec<(f64, TrackId, Clip)> {
        let areas = self.razor_areas.read().clone();
        if areas.is_empty() {
            return Vec::new();
        }

        let merged = Self::merged_razor_ranges(&areas);
        if merged.is_empty() {
            return Vec::new();
        }

        let min_start = merged
            .iter()
            .map(|&(_, s, _)| s)
            .fold(f64::MAX, f64::min);

        let mut result = Vec::new();

        for &(track_id, range_start, range_end) in &merged {
            let track_clips = self.get_clips_for_track(track_id);
            for clip in &track_clips {
                let clip_end = clip.end_time();
                // Compute intersection with merged range
                let inter_start = range_start.max(clip.start_time);
                let inter_end = range_end.min(clip_end);
                if inter_end <= inter_start + 0.001 {
                    continue;
                }

                let mut copy = clip.clone();
                let trim_left = inter_start - clip.start_time;
                copy.start_time = inter_start;
                copy.duration = inter_end - inter_start;
                copy.source_offset += trim_left;
                copy.id = ClipId(next_id());
                copy.name = format!("{} (razor)", clip.name);

                let relative_time = inter_start - min_start;
                result.push((relative_time, track_id, copy));
            }
        }

        result
    }

    /// Cut clips within razor areas (copy + delete).
    /// Returns clipboard data, then removes razor content.
    pub fn razor_cut(&self) -> Vec<(f64, TrackId, Clip)> {
        let copied = self.razor_copy();
        self.razor_delete();
        copied
    }

    /// Paste razor clipboard at a given time position on given tracks.
    /// `paste_time` is where the first item begins.
    /// `track_map` maps original track IDs to paste target track IDs.
    /// If track_map is None, paste on same tracks.
    pub fn razor_paste(
        &self,
        clipboard: &[(f64, TrackId, Clip)],
        paste_time: f64,
        track_map: Option<&HashMap<TrackId, TrackId>>,
    ) -> Vec<ClipId> {
        let mut new_ids = Vec::new();
        for (rel_time, orig_track_id, clip_data) in clipboard {
            let target_track = track_map
                .and_then(|m| m.get(orig_track_id).copied())
                .unwrap_or(*orig_track_id);

            let mut new_clip = clip_data.clone();
            new_clip.id = ClipId(next_id());
            new_clip.track_id = target_track;
            new_clip.start_time = paste_time + rel_time;
            new_clip.selected = true;
            new_ids.push(self.add_clip(new_clip));
        }
        new_ids
    }

    /// Reverse audio within all razor areas.
    /// Uses merged ranges to avoid double-processing overlapping areas.
    pub fn razor_reverse(&self) {
        let areas = self.razor_areas.read().clone();
        if areas.is_empty() {
            return;
        }

        let merged = Self::merged_razor_ranges(&areas);
        let isolated = self.isolate_razor_clips(&merged);

        for clip_id in isolated {
            self.update_clip(clip_id, |c| c.reversed = !c.reversed);
        }
    }

    /// Stretch content within razor areas by a ratio.
    /// `ratio` > 1.0 = longer (slower), < 1.0 = shorter (faster).
    /// Uses merged ranges to avoid double-processing overlapping areas.
    pub fn razor_stretch(&self, ratio: f64) {
        let ratio = ratio.clamp(0.1, 10.0);
        let areas = self.razor_areas.read().clone();
        if areas.is_empty() {
            return;
        }

        let merged = Self::merged_razor_ranges(&areas);
        let isolated = self.isolate_razor_clips(&merged);

        for clip_id in isolated {
            if let Some(c) = self.get_clip(clip_id) {
                let new_duration = c.duration * ratio;
                self.update_clip(clip_id, |c| {
                    c.stretch_ratio *= ratio;
                    c.duration = new_duration;
                });
            }
        }

        // Stretch razor areas themselves
        let mut areas = self.razor_areas.write();
        for area in areas.iter_mut() {
            let new_duration = area.duration() * ratio;
            area.end = area.start + new_duration;
        }
    }

    /// Duplicate razor content — copy and paste immediately after.
    /// Returns IDs of new clips.
    pub fn razor_duplicate(&self) -> Vec<ClipId> {
        let areas = self.razor_areas.read().clone();
        if areas.is_empty() {
            return Vec::new();
        }

        let merged = Self::merged_razor_ranges(&areas);
        let min_start = merged.iter().map(|&(_, s, _)| s).fold(f64::MAX, f64::min);
        let max_end = merged.iter().map(|&(_, _, e)| e).fold(f64::MIN, f64::max);
        let total_duration = max_end - min_start;

        let copied = self.razor_copy();
        let mut new_ids = Vec::new();

        for (rel_time, _track_id, clip_data) in &copied {
            let mut new_clip = clip_data.clone();
            new_clip.id = ClipId(next_id());
            new_clip.start_time = min_start + total_duration + rel_time;
            new_clip.selected = true;
            new_ids.push(self.add_clip(new_clip));
        }

        // Move razor areas to duplicated region
        let mut areas = self.razor_areas.write();
        for area in areas.iter_mut() {
            area.offset_time(total_duration);
        }

        new_ids
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLIP FX OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Add FX to a clip's chain
    pub fn add_clip_fx(&self, clip_id: ClipId, fx_type: ClipFxType) -> Option<ClipFxSlotId> {
        self.clips
            .get_mut(&clip_id)
            .map(|mut clip| clip.add_fx(fx_type))
    }

    /// Add FX slot to a clip's chain
    pub fn add_clip_fx_slot(&self, clip_id: ClipId, slot: ClipFxSlot) -> Option<ClipFxSlotId> {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            Some(clip.fx_chain.add_slot(slot))
        } else {
            None
        }
    }

    /// Insert FX at specific position in clip's chain
    pub fn insert_clip_fx(
        &self,
        clip_id: ClipId,
        index: usize,
        fx_type: ClipFxType,
    ) -> Option<ClipFxSlotId> {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            let slot = ClipFxSlot::new(fx_type);
            Some(clip.fx_chain.insert_slot(index, slot))
        } else {
            None
        }
    }

    /// Remove FX from a clip's chain
    pub fn remove_clip_fx(&self, clip_id: ClipId, slot_id: ClipFxSlotId) -> bool {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.remove_fx(slot_id)
        } else {
            false
        }
    }

    /// Move FX slot to new position in clip's chain
    pub fn move_clip_fx(&self, clip_id: ClipId, slot_id: ClipFxSlotId, new_index: usize) -> bool {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.fx_chain.move_slot(slot_id, new_index)
        } else {
            false
        }
    }

    /// Bypass/enable a specific FX slot
    pub fn set_clip_fx_bypass(&self, clip_id: ClipId, slot_id: ClipFxSlotId, bypass: bool) -> bool {
        if let Some(mut clip) = self.clips.get_mut(&clip_id)
            && let Some(slot) = clip.fx_chain.get_slot_mut(slot_id)
        {
            slot.bypass = bypass;
            return true;
        }
        false
    }

    /// Bypass/enable entire clip FX chain
    pub fn set_clip_fx_chain_bypass(&self, clip_id: ClipId, bypass: bool) -> bool {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.set_fx_bypass(bypass);
            true
        } else {
            false
        }
    }

    /// Update FX slot parameters
    pub fn update_clip_fx<F>(&self, clip_id: ClipId, slot_id: ClipFxSlotId, f: F) -> bool
    where
        F: FnOnce(&mut ClipFxSlot),
    {
        if let Some(mut clip) = self.clips.get_mut(&clip_id)
            && let Some(slot) = clip.fx_chain.get_slot_mut(slot_id)
        {
            f(slot);
            return true;
        }
        false
    }

    /// Get clip's FX chain
    pub fn get_clip_fx_chain(&self, clip_id: ClipId) -> Option<ClipFxChain> {
        self.clips.get(&clip_id).map(|c| c.fx_chain.clone())
    }

    /// Get specific FX slot from a clip
    pub fn get_clip_fx_slot(&self, clip_id: ClipId, slot_id: ClipFxSlotId) -> Option<ClipFxSlot> {
        self.clips
            .get(&clip_id)
            .and_then(|c| c.fx_chain.get_slot(slot_id).cloned())
    }

    /// Get all clips that have active FX processing
    pub fn get_clips_with_fx(&self) -> Vec<Clip> {
        self.clips
            .iter()
            .filter(|entry| entry.value().has_fx())
            .map(|entry| entry.value().clone())
            .collect()
    }

    /// Clear all FX from a clip
    pub fn clear_clip_fx(&self, clip_id: ClipId) -> bool {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.fx_chain.clear();
            true
        } else {
            false
        }
    }

    /// Copy FX chain from one clip to another
    pub fn copy_clip_fx(&self, source_clip_id: ClipId, target_clip_id: ClipId) -> bool {
        let source_chain = self.clips.get(&source_clip_id).map(|c| c.fx_chain.clone());

        if let Some(chain) = source_chain
            && let Some(mut target_clip) = self.clips.get_mut(&target_clip_id)
        {
            // Clone chain but regenerate slot IDs
            target_clip.fx_chain.bypass = chain.bypass;
            target_clip.fx_chain.input_gain_db = chain.input_gain_db;
            target_clip.fx_chain.output_gain_db = chain.output_gain_db;
            target_clip.fx_chain.slots.clear();

            for slot in chain.slots {
                let mut new_slot = ClipFxSlot::new(slot.fx_type);
                new_slot.bypass = slot.bypass;
                new_slot.wet_dry = slot.wet_dry;
                new_slot.output_gain_db = slot.output_gain_db;
                new_slot.name = slot.name;
                target_clip.fx_chain.add_slot(new_slot);
            }
            return true;
        }
        false
    }

    /// Set clip FX chain input gain
    pub fn set_clip_fx_input_gain(&self, clip_id: ClipId, gain_db: f64) -> bool {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.fx_chain.input_gain_db = gain_db.clamp(-96.0, 12.0);
            true
        } else {
            false
        }
    }

    /// Set clip FX chain output gain
    pub fn set_clip_fx_output_gain(&self, clip_id: ClipId, gain_db: f64) -> bool {
        if let Some(mut clip) = self.clips.get_mut(&clip_id) {
            clip.fx_chain.output_gain_db = gain_db.clamp(-96.0, 12.0);
            true
        } else {
            false
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CROSSFADE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create crossfade between two adjacent clips (symmetric)
    pub fn create_crossfade(
        &self,
        clip_a_id: ClipId,
        clip_b_id: ClipId,
        duration: f64,
        curve: CrossfadeCurve,
    ) -> Option<CrossfadeId> {
        self.create_crossfade_with_shape(
            clip_a_id,
            clip_b_id,
            duration,
            CrossfadeShape::Symmetric(curve),
        )
    }

    /// Create asymmetric crossfade with separate fade-out/fade-in curves
    pub fn create_asymmetric_crossfade(
        &self,
        clip_a_id: ClipId,
        clip_b_id: ClipId,
        duration: f64,
        fade_out: CrossfadeCurve,
        fade_in: CrossfadeCurve,
    ) -> Option<CrossfadeId> {
        self.create_crossfade_with_shape(
            clip_a_id,
            clip_b_id,
            duration,
            CrossfadeShape::Asymmetric { fade_out, fade_in },
        )
    }

    /// Create crossfade with full shape control
    pub fn create_crossfade_with_shape(
        &self,
        clip_a_id: ClipId,
        clip_b_id: ClipId,
        duration: f64,
        shape: CrossfadeShape,
    ) -> Option<CrossfadeId> {
        let clip_a = self.get_clip(clip_a_id)?;
        let clip_b = self.get_clip(clip_b_id)?;

        // Clips must be on same track
        if clip_a.track_id != clip_b.track_id {
            return None;
        }

        // Determine crossfade start (overlap point)
        let start_time = clip_a.end_time() - duration / 2.0;

        let mut xfade = Crossfade::new(clip_a.track_id, clip_a_id, clip_b_id, start_time, duration);
        xfade.shape = shape;

        let id = xfade.id;
        self.crossfades.insert(id, xfade);

        Some(id)
    }

    /// Get all crossfades for a track
    pub fn get_crossfades_for_track(&self, track_id: TrackId) -> Vec<Crossfade> {
        self.crossfades
            .iter()
            .filter(|entry| entry.value().track_id == track_id)
            .map(|entry| entry.value().clone())
            .collect()
    }

    /// Get crossfade by ID
    pub fn get_crossfade(&self, xfade_id: CrossfadeId) -> Option<Crossfade> {
        self.crossfades.get(&xfade_id).map(|r| r.clone())
    }

    /// Find crossfade at given time on a track
    pub fn get_crossfade_at_time(&self, track_id: TrackId, time: f64) -> Option<Crossfade> {
        self.crossfades
            .iter()
            .find(|entry| entry.value().track_id == track_id && entry.value().contains_time(time))
            .map(|entry| entry.value().clone())
    }

    /// Update crossfade duration and curve (symmetric)
    pub fn update_crossfade(&self, xfade_id: CrossfadeId, duration: f64, curve: CrossfadeCurve) {
        if let Some(mut xfade) = self.crossfades.get_mut(&xfade_id) {
            xfade.duration = duration;
            xfade.shape = CrossfadeShape::Symmetric(curve.clone());
            xfade.curve = curve;
        }
    }

    /// Update crossfade with full shape control
    pub fn update_crossfade_shape(
        &self,
        xfade_id: CrossfadeId,
        duration: f64,
        shape: CrossfadeShape,
    ) {
        if let Some(mut xfade) = self.crossfades.get_mut(&xfade_id) {
            xfade.duration = duration;
            xfade.shape = shape;
        }
    }

    /// Delete crossfade
    pub fn delete_crossfade(&self, xfade_id: CrossfadeId) {
        self.crossfades.remove(&xfade_id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARKER OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Add marker
    pub fn add_marker(&self, time: f64, name: &str, color: u32) -> MarkerId {
        let marker = Marker::new(time, name, color);
        let id = marker.id;
        self.markers.write().push(marker);
        id
    }

    /// Get all markers sorted by time
    pub fn get_markers(&self) -> Vec<Marker> {
        let mut markers = self.markers.read().clone();
        markers.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap());
        markers
    }

    /// Delete marker
    pub fn delete_marker(&self, marker_id: MarkerId) {
        self.markers.write().retain(|m| m.id != marker_id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOOP REGION
    // ═══════════════════════════════════════════════════════════════════════

    /// Get loop region
    pub fn get_loop_region(&self) -> LoopRegion {
        *self.loop_region.read()
    }

    /// Set loop region
    pub fn set_loop_region(&self, start: f64, end: f64) {
        let mut region = self.loop_region.write();
        region.start = start.max(0.0);
        region.end = end.max(start + 0.001);
    }

    /// Enable/disable loop
    pub fn set_loop_enabled(&self, enabled: bool) {
        self.loop_region.write().enabled = enabled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROJECT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Clear all data (new project)
    pub fn clear(&self) {
        self.tracks.clear();
        self.clips.clear();
        self.crossfades.clear();
        self.markers.write().clear();
        self.track_order.write().clear();
        *self.loop_region.write() = LoopRegion::default();
    }

    /// Get total project duration (end of last clip)
    pub fn get_duration(&self) -> f64 {
        self.clips
            .iter()
            .map(|entry| entry.value().end_time())
            .fold(0.0, f64::max)
    }

    /// Get track count
    pub fn track_count(&self) -> usize {
        self.tracks.len()
    }

    /// Get clip count
    pub fn clip_count(&self) -> usize {
        self.clips.len()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COMPING OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new comp lane for a track
    pub fn create_comp_lane(&self, track_id: TrackId, name: &str) -> CompLaneId {
        let order = self
            .comp_lanes
            .read()
            .values()
            .filter(|l| l.track_id == track_id)
            .count();
        let lane = CompLane::new(name, track_id, order);
        let lane_id = lane.id;
        self.comp_lanes.write().insert(lane_id, lane);
        lane_id
    }

    /// Delete a comp lane and all its takes
    pub fn delete_comp_lane(&self, lane_id: CompLaneId) {
        // Remove all takes in this lane
        self.takes.write().retain(|_, take| take.lane_id != lane_id);
        // Remove the lane
        self.comp_lanes.write().remove(&lane_id);
    }

    /// Add a take to a comp lane
    pub fn add_take(
        &self,
        lane_id: CompLaneId,
        source_file: &str,
        start_time: f64,
        duration: f64,
    ) -> Option<TakeId> {
        let lane = self.comp_lanes.read().get(&lane_id)?.clone();
        let take = Take::new(source_file, lane.track_id, lane_id, start_time, duration);
        let take_id = take.id;
        self.takes.write().insert(take_id, take);
        Some(take_id)
    }

    /// Delete a take
    pub fn delete_take(&self, take_id: TakeId) {
        self.takes.write().remove(&take_id);
        // Also remove any comp regions using this take
        for regions in self.comp_regions.write().values_mut() {
            regions.retain(|r| r.take_id != take_id);
        }
    }

    /// Set take rating (0-5 stars)
    pub fn rate_take(&self, take_id: TakeId, rating: u8) {
        if let Some(take) = self.takes.write().get_mut(&take_id) {
            take.rating = rating.min(5);
        }
    }

    /// Mute/unmute a take
    pub fn mute_take(&self, take_id: TakeId, muted: bool) {
        if let Some(take) = self.takes.write().get_mut(&take_id) {
            take.muted = muted;
        }
    }

    /// Set comp region - select which take is active for a time range
    pub fn set_comp_region(
        &self,
        track_id: TrackId,
        start_time: f64,
        end_time: f64,
        take_id: TakeId,
    ) {
        let mut regions = self.comp_regions.write();
        let track_regions = regions.entry(track_id).or_default();

        // Remove overlapping regions
        track_regions.retain(|r| r.end_time <= start_time || r.start_time >= end_time);

        // Add new region
        track_regions.push(CompRegion {
            start_time,
            end_time,
            take_id,
        });

        // Sort by start time
        track_regions.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
    }

    /// Get all comp lanes for a track
    pub fn get_comp_lanes(&self, track_id: TrackId) -> Vec<CompLane> {
        self.comp_lanes
            .read()
            .values()
            .filter(|l| l.track_id == track_id)
            .cloned()
            .collect()
    }

    /// Get all takes for a comp lane
    pub fn get_takes(&self, lane_id: CompLaneId) -> Vec<Take> {
        self.takes
            .read()
            .values()
            .filter(|t| t.lane_id == lane_id)
            .cloned()
            .collect()
    }

    /// Get comp regions for a track
    pub fn get_comp_regions(&self, track_id: TrackId) -> Vec<CompRegion> {
        self.comp_regions
            .read()
            .get(&track_id)
            .cloned()
            .unwrap_or_default()
    }

    /// Flatten comp to clip - create a clip from the comp regions
    pub fn flatten_comp(&self, track_id: TrackId) -> Option<ClipId> {
        let regions = self.get_comp_regions(track_id);
        if regions.is_empty() {
            return None;
        }

        // Find overall time range
        let start = regions
            .iter()
            .map(|r| r.start_time)
            .fold(f64::INFINITY, f64::min);
        let end = regions
            .iter()
            .map(|r| r.end_time)
            .fold(f64::NEG_INFINITY, f64::max);

        // Create a new clip (audio will need to be rendered/bounced separately)
        // Source file will be set after rendering
        let clip = Clip::new(
            track_id,
            &format!("Comp {}", track_id.0),
            "",
            start,
            end - start,
        );
        let clip_id = clip.id;
        self.clips.insert(clip_id, clip);

        Some(clip_id)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRACK TEMPLATE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Save track as template
    pub fn save_track_as_template(
        &self,
        track_id: TrackId,
        template_name: &str,
        category: &str,
    ) -> Option<String> {
        let track = self.tracks.get(&track_id)?;
        let template = TrackTemplate::from_track(&track, template_name, category);
        let template_id = template.id.clone();
        self.templates.write().insert(template_id.clone(), template);
        Some(template_id)
    }

    /// Create track from template
    pub fn create_track_from_template(&self, template_id: &str) -> Option<TrackId> {
        let templates = self.templates.read();
        let template = templates.get(template_id)?;
        let track = Track::from_template(template);
        let track_id = track.id;
        drop(templates); // Release read lock before write

        let order = self.tracks.len();
        let mut track = track;
        track.order = order;
        self.tracks.insert(track_id, track);

        self.track_order.write().push(track_id);
        Some(track_id)
    }

    /// Get template by ID
    pub fn get_template(&self, template_id: &str) -> Option<TrackTemplate> {
        self.templates.read().get(template_id).cloned()
    }

    /// List all templates
    pub fn list_templates(&self) -> Vec<TrackTemplate> {
        self.templates.read().values().cloned().collect()
    }

    /// List templates by category
    pub fn list_templates_by_category(&self, category: &str) -> Vec<TrackTemplate> {
        self.templates
            .read()
            .values()
            .filter(|t| t.category == category)
            .cloned()
            .collect()
    }

    /// Delete template
    pub fn delete_template(&self, template_id: &str) -> bool {
        // Don't allow deleting default templates
        if template_id.starts_with("default_") {
            return false;
        }
        self.templates.write().remove(template_id).is_some()
    }

    /// Update template description
    pub fn update_template_description(&self, template_id: &str, description: &str) -> bool {
        if let Some(tpl) = self.templates.write().get_mut(template_id) {
            tpl.description = description.to_string();
            true
        } else {
            false
        }
    }

    /// Add tag to template
    pub fn add_template_tag(&self, template_id: &str, tag: &str) -> bool {
        if let Some(tpl) = self.templates.write().get_mut(template_id) {
            if !tpl.tags.contains(&tag.to_string()) {
                tpl.tags.push(tag.to_string());
            }
            true
        } else {
            false
        }
    }

    /// Get template count
    pub fn template_count(&self) -> usize {
        self.templates.read().len()
    }

    /// Search templates by tag
    pub fn search_templates_by_tag(&self, tag: &str) -> Vec<TrackTemplate> {
        self.templates
            .read()
            .values()
            .filter(|t| t.tags.iter().any(|tt| tt.contains(tag)))
            .cloned()
            .collect()
    }
}

impl Default for TrackManager {
    fn default() -> Self {
        Self::new()
    }
}

impl TrackManager {
    // ═══════════════════════════════════════════════════════════════════════
    // MIX SNAPSHOT OPERATIONS (SWS-style Save/Recall Mix States)
    // ═══════════════════════════════════════════════════════════════════════

    /// Capture current mix state as a snapshot.
    /// `categories` — which aspects to capture (empty = all).
    /// `track_filter` — specific tracks only (empty = all tracks).
    pub fn capture_mix_snapshot(
        &self,
        name: &str,
        description: &str,
        categories: &[SnapshotCategory],
        track_filter: &[TrackId],
    ) -> MixSnapshotId {
        let cats = if categories.is_empty() {
            SnapshotCategory::all().to_vec()
        } else {
            categories.to_vec()
        };

        let has = |c: SnapshotCategory| cats.contains(&c);

        // Gather track data
        let tracks_to_capture: Vec<Track> = if track_filter.is_empty() {
            self.tracks.iter().map(|r| r.value().clone()).collect()
        } else {
            track_filter
                .iter()
                .filter_map(|tid| self.tracks.get(tid).map(|r| r.value().clone()))
                .collect()
        };

        let track_snapshots: Vec<TrackSnapshotData> = tracks_to_capture
            .iter()
            .map(|t| TrackSnapshotData {
                track_id: t.id,
                volume: if has(SnapshotCategory::Volume) {
                    Some(t.volume)
                } else {
                    None
                },
                pan: if has(SnapshotCategory::Pan) {
                    Some((t.pan, t.pan_right))
                } else {
                    None
                },
                muted: if has(SnapshotCategory::MuteSolo) {
                    Some(t.muted)
                } else {
                    None
                },
                soloed: if has(SnapshotCategory::MuteSolo) {
                    Some(t.soloed)
                } else {
                    None
                },
                phase_inverted: if has(SnapshotCategory::Phase) {
                    Some(t.phase_inverted)
                } else {
                    None
                },
                output_bus: if has(SnapshotCategory::OutputBus) {
                    Some(t.output_bus)
                } else {
                    None
                },
                channels: if has(SnapshotCategory::ChannelConfig) {
                    Some(t.channels)
                } else {
                    None
                },
                name: if has(SnapshotCategory::TrackName) {
                    Some(t.name.clone())
                } else {
                    None
                },
                sends: if has(SnapshotCategory::Sends) {
                    Some(SnapshotSends {
                        sends: t.sends.clone(),
                    })
                } else {
                    None
                },
            })
            .collect();

        // Gather clip gains
        let clip_gains: Vec<SnapshotClipGain> = if has(SnapshotCategory::ClipGain) {
            let track_ids: std::collections::HashSet<TrackId> = if track_filter.is_empty() {
                self.tracks.iter().map(|r| *r.key()).collect()
            } else {
                track_filter.iter().copied().collect()
            };

            self.clips
                .iter()
                .filter(|r| track_ids.contains(&r.value().track_id))
                .map(|r| {
                    let c = r.value();
                    SnapshotClipGain {
                        clip_id: c.id,
                        gain: c.gain,
                        muted: c.muted,
                    }
                })
                .collect()
        } else {
            Vec::new()
        };

        let id = MixSnapshotId(next_id());
        let snapshot = MixSnapshot {
            id,
            name: name.to_string(),
            description: description.to_string(),
            categories: cats,
            tracks: track_snapshots,
            clip_gains,
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64())
                .unwrap_or(0.0),
            track_filter: track_filter.to_vec(),
        };

        self.mix_snapshots.write().push(snapshot);
        id
    }

    /// Recall (apply) a mix snapshot.
    /// `categories_override` — if non-empty, only recall these categories
    /// (even if the snapshot has more). Empty = recall all captured categories.
    /// `track_filter_override` — if non-empty, only apply to these tracks.
    /// Returns number of tracks affected, or 0 if snapshot not found.
    pub fn recall_mix_snapshot(
        &self,
        snapshot_id: MixSnapshotId,
        categories_override: &[SnapshotCategory],
        track_filter_override: &[TrackId],
    ) -> usize {
        let snapshots = self.mix_snapshots.read();
        let snapshot = match snapshots.iter().find(|s| s.id == snapshot_id) {
            Some(s) => s.clone(),
            None => return 0,
        };
        drop(snapshots);

        let cats = if categories_override.is_empty() {
            &snapshot.categories
        } else {
            categories_override
        };
        let has = |c: SnapshotCategory| cats.contains(&c);

        let track_filter_set: std::collections::HashSet<TrackId> = if !track_filter_override.is_empty() {
            track_filter_override.iter().copied().collect()
        } else {
            std::collections::HashSet::new()
        };

        let mut affected = 0usize;

        // If recalling MuteSolo, clear solo on all tracks in scope first
        // to prevent stale solos from persisting
        if has(SnapshotCategory::MuteSolo) {
            let snapshot_track_ids: std::collections::HashSet<TrackId> =
                snapshot.tracks.iter().map(|t| t.track_id).collect();
            for entry in self.tracks.iter() {
                let tid = *entry.key();
                // Only clear if this track is in recall scope
                if !track_filter_set.is_empty() && !track_filter_set.contains(&tid) {
                    continue;
                }
                // Only clear if this track was in the snapshot (we'll set it to correct value below)
                if snapshot_track_ids.contains(&tid) {
                    continue;
                }
                // Track NOT in snapshot but in scope — clear its solo
                if entry.value().soloed {
                    self.set_track_solo(tid, false);
                }
            }
        }

        for tdata in &snapshot.tracks {
            // Skip if track filter override is active and this track isn't in it
            if !track_filter_set.is_empty() && !track_filter_set.contains(&tdata.track_id) {
                continue;
            }

            // Check track still exists
            if !self.tracks.contains_key(&tdata.track_id) {
                continue;
            }

            let mut changed = false;

            if has(SnapshotCategory::Volume) {
                if let Some(vol) = tdata.volume {
                    self.update_track(tdata.track_id, |t| t.volume = vol);
                    changed = true;
                }
            }

            if has(SnapshotCategory::Pan) {
                if let Some((pan_l, pan_r)) = tdata.pan {
                    self.update_track(tdata.track_id, |t| {
                        t.pan = pan_l;
                        t.pan_right = pan_r;
                    });
                    changed = true;
                }
            }

            if has(SnapshotCategory::MuteSolo) {
                if let Some(muted) = tdata.muted {
                    self.update_track(tdata.track_id, |t| t.muted = muted);
                    changed = true;
                }
                if let Some(soloed) = tdata.soloed {
                    self.set_track_solo(tdata.track_id, soloed);
                    changed = true;
                }
            }

            if has(SnapshotCategory::Phase) {
                if let Some(phase) = tdata.phase_inverted {
                    self.update_track(tdata.track_id, |t| t.phase_inverted = phase);
                    changed = true;
                }
            }

            if has(SnapshotCategory::OutputBus) {
                if let Some(bus) = tdata.output_bus {
                    self.update_track(tdata.track_id, |t| t.output_bus = bus);
                    changed = true;
                }
            }

            if has(SnapshotCategory::ChannelConfig) {
                if let Some(ch) = tdata.channels {
                    self.update_track(tdata.track_id, |t| t.channels = ch);
                    changed = true;
                }
            }

            if has(SnapshotCategory::TrackName) {
                if let Some(ref name) = tdata.name {
                    self.update_track(tdata.track_id, |t| t.name = name.clone());
                    changed = true;
                }
            }

            if has(SnapshotCategory::Sends) {
                if let Some(ref sends_data) = tdata.sends {
                    self.update_track(tdata.track_id, |t| {
                        t.sends = sends_data.sends.clone();
                    });
                    changed = true;
                }
            }

            if changed {
                affected += 1;
            }
        }

        // Recall clip gains
        if has(SnapshotCategory::ClipGain) {
            for cg in &snapshot.clip_gains {
                // Apply only if clip still exists and matches track filter
                if let Some(clip) = self.get_clip(cg.clip_id) {
                    if !track_filter_set.is_empty()
                        && !track_filter_set.contains(&clip.track_id)
                    {
                        continue;
                    }
                    self.update_clip(cg.clip_id, |c| {
                        c.gain = cg.gain;
                        c.muted = cg.muted;
                    });
                }
            }
        }

        affected
    }

    /// Get all mix snapshots
    pub fn get_mix_snapshots(&self) -> Vec<MixSnapshot> {
        self.mix_snapshots.read().clone()
    }

    /// Get a single snapshot by ID
    pub fn get_mix_snapshot(&self, id: MixSnapshotId) -> Option<MixSnapshot> {
        self.mix_snapshots.read().iter().find(|s| s.id == id).cloned()
    }

    /// Delete a mix snapshot
    pub fn delete_mix_snapshot(&self, id: MixSnapshotId) -> bool {
        let mut snapshots = self.mix_snapshots.write();
        let before = snapshots.len();
        snapshots.retain(|s| s.id != id);
        snapshots.len() < before
    }

    /// Clear all mix snapshots
    pub fn clear_mix_snapshots(&self) {
        self.mix_snapshots.write().clear();
    }

    /// Rename a mix snapshot
    pub fn rename_mix_snapshot(&self, id: MixSnapshotId, name: &str) -> bool {
        let mut snapshots = self.mix_snapshots.write();
        if let Some(s) = snapshots.iter_mut().find(|s| s.id == id) {
            s.name = name.to_string();
            true
        } else {
            false
        }
    }

    /// Update (overwrite) a snapshot with current state, preserving ID and name.
    /// Recaptures using same categories and track filter as original.
    pub fn update_mix_snapshot(&self, id: MixSnapshotId) -> bool {
        // Read existing snapshot settings (categories, track_filter, name, description)
        let existing = {
            let snapshots = self.mix_snapshots.read();
            snapshots.iter().find(|s| s.id == id).cloned()
        };

        let existing = match existing {
            Some(e) => e,
            None => return false,
        };

        // Build fresh snapshot data inline (don't use capture_mix_snapshot to avoid
        // appending to vec and then having to remove — atomic replace instead)
        let cats = &existing.categories;
        let has = |c: SnapshotCategory| cats.contains(&c);

        let tracks_to_capture: Vec<Track> = if existing.track_filter.is_empty() {
            self.tracks.iter().map(|r| r.value().clone()).collect()
        } else {
            existing
                .track_filter
                .iter()
                .filter_map(|tid| self.tracks.get(tid).map(|r| r.value().clone()))
                .collect()
        };

        let track_snapshots: Vec<TrackSnapshotData> = tracks_to_capture
            .iter()
            .map(|t| TrackSnapshotData {
                track_id: t.id,
                volume: if has(SnapshotCategory::Volume) { Some(t.volume) } else { None },
                pan: if has(SnapshotCategory::Pan) { Some((t.pan, t.pan_right)) } else { None },
                muted: if has(SnapshotCategory::MuteSolo) { Some(t.muted) } else { None },
                soloed: if has(SnapshotCategory::MuteSolo) { Some(t.soloed) } else { None },
                phase_inverted: if has(SnapshotCategory::Phase) { Some(t.phase_inverted) } else { None },
                output_bus: if has(SnapshotCategory::OutputBus) { Some(t.output_bus) } else { None },
                channels: if has(SnapshotCategory::ChannelConfig) { Some(t.channels) } else { None },
                name: if has(SnapshotCategory::TrackName) { Some(t.name.clone()) } else { None },
                sends: if has(SnapshotCategory::Sends) {
                    Some(SnapshotSends { sends: t.sends.clone() })
                } else {
                    None
                },
            })
            .collect();

        let clip_gains: Vec<SnapshotClipGain> = if has(SnapshotCategory::ClipGain) {
            let track_ids: std::collections::HashSet<TrackId> = if existing.track_filter.is_empty() {
                self.tracks.iter().map(|r| *r.key()).collect()
            } else {
                existing.track_filter.iter().copied().collect()
            };
            self.clips
                .iter()
                .filter(|r| track_ids.contains(&r.value().track_id))
                .map(|r| {
                    let c = r.value();
                    SnapshotClipGain { clip_id: c.id, gain: c.gain, muted: c.muted }
                })
                .collect()
        } else {
            Vec::new()
        };

        // Atomic replace in-place
        let mut snapshots = self.mix_snapshots.write();
        if let Some(s) = snapshots.iter_mut().find(|s| s.id == id) {
            s.tracks = track_snapshots;
            s.clip_gains = clip_gains;
            s.created_at = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64())
                .unwrap_or(0.0);
            true
        } else {
            false
        }
    }

    /// Serialize all snapshots to JSON
    pub fn mix_snapshots_to_json(&self) -> String {
        let snapshots = self.mix_snapshots.read();
        serde_json::to_string(&*snapshots).unwrap_or_else(|_| "[]".to_string())
    }

    /// Load snapshots from JSON (replaces current)
    pub fn mix_snapshots_from_json(&self, json: &str) -> bool {
        match serde_json::from_str::<Vec<MixSnapshot>>(json) {
            Ok(loaded) => {
                *self.mix_snapshots.write() = loaded;
                true
            }
            Err(_) => false,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_track() {
        let manager = TrackManager::new();
        let id = manager.create_track("Audio 1", 0xFF4A9EFF, OutputBus::Master);

        let track = manager.get_track(id).unwrap();
        assert_eq!(track.name, "Audio 1");
        assert_eq!(track.output_bus, OutputBus::Master);
    }

    #[test]
    fn test_create_and_move_clip() {
        let manager = TrackManager::new();
        let track1 = manager.create_track("Track 1", 0xFF0000FF, OutputBus::Master);
        let track2 = manager.create_track("Track 2", 0xFFFF0000, OutputBus::Music);

        let clip_id = manager.create_clip(track1, "Clip", "audio.wav", 1.0, 4.0, 4.0);

        // Move to track 2 at time 5.0
        manager.move_clip(clip_id, track2, 5.0);

        let clip = manager.get_clip(clip_id).unwrap();
        assert_eq!(clip.track_id, track2);
        assert_eq!(clip.start_time, 5.0);
    }

    #[test]
    fn test_split_clip() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);
        let clip_id = manager.create_clip(track, "Clip", "audio.wav", 0.0, 4.0, 4.0);

        let (left_id, right_id) = manager.split_clip(clip_id, 2.0).unwrap();

        let left = manager.get_clip(left_id).unwrap();
        let right = manager.get_clip(right_id).unwrap();

        assert_eq!(left.duration, 2.0);
        assert_eq!(right.start_time, 2.0);
        assert_eq!(right.duration, 2.0);
    }

    #[test]
    fn test_duplicate_clip() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);
        let clip_id = manager.create_clip(track, "Clip", "audio.wav", 0.0, 4.0, 4.0);

        let dup_id = manager.duplicate_clip(clip_id).unwrap();
        let dup = manager.get_clip(dup_id).unwrap();

        assert_eq!(dup.start_time, 4.0); // Placed after original
        assert_eq!(dup.duration, 4.0);
    }

    #[test]
    fn test_loop_region() {
        let manager = TrackManager::new();
        manager.set_loop_region(4.0, 12.0);
        manager.set_loop_enabled(true);

        let region = manager.get_loop_region();
        assert_eq!(region.start, 4.0);
        assert_eq!(region.end, 12.0);
        assert!(region.enabled);
    }

    #[test]
    fn test_crossfade_curves() {
        // Test all curve types at key positions
        let curves = [
            CrossfadeCurve::Linear,
            CrossfadeCurve::EqualPower,
            CrossfadeCurve::SCurve,
            CrossfadeCurve::Logarithmic,
            CrossfadeCurve::Exponential,
        ];

        for curve in curves {
            // At start (t=0), fade-in should be 0
            let val_start = curve.evaluate(0.0);
            assert!(
                (0.0..=0.01).contains(&val_start),
                "{:?} start: {}",
                curve,
                val_start
            );

            // At end (t=1), fade-in should be 1
            let val_end = curve.evaluate(1.0);
            assert!(
                (0.99..=1.0).contains(&val_end),
                "{:?} end: {}",
                curve,
                val_end
            );

            // At midpoint, value should be between 0 and 1
            let val_mid = curve.evaluate(0.5);
            assert!(
                val_mid > 0.0 && val_mid < 1.0,
                "{:?} mid: {}",
                curve,
                val_mid
            );
        }
    }

    #[test]
    fn test_equal_power_crossfade() {
        // Equal power should maintain constant loudness
        let curve = CrossfadeCurve::EqualPower;

        // At t=0.5, the sum of fade_in² + fade_out² should ≈ 1
        let t = 0.5;
        let fade_in = curve.evaluate(t);
        let fade_out = curve.evaluate(1.0 - t);
        let sum_of_squares = fade_in * fade_in + fade_out * fade_out;

        // Should be close to 1.0 (within floating point tolerance)
        assert!(
            (sum_of_squares - 1.0).abs() < 0.01,
            "Equal power sum of squares: {}",
            sum_of_squares
        );
    }

    #[test]
    fn test_crossfade_shape_symmetric() {
        let shape = CrossfadeShape::Symmetric(CrossfadeCurve::Linear);

        // At t=0: fade_out=1, fade_in=0
        let (fo, fi) = shape.evaluate(0.0);
        assert!((fo - 1.0).abs() < 0.01);
        assert!(fi < 0.01);

        // At t=0.5: both should be 0.5
        let (fo, fi) = shape.evaluate(0.5);
        assert!((fo - 0.5).abs() < 0.01);
        assert!((fi - 0.5).abs() < 0.01);

        // At t=1: fade_out=0, fade_in=1
        let (fo, fi) = shape.evaluate(1.0);
        assert!(fo < 0.01);
        assert!((fi - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_crossfade_shape_asymmetric() {
        // Use different curves for fade-out and fade-in
        let shape = CrossfadeShape::Asymmetric {
            fade_out: CrossfadeCurve::Exponential, // Slow start
            fade_in: CrossfadeCurve::Logarithmic,  // Fast start
        };

        // Both should work independently
        let (fo, fi) = shape.evaluate(0.5);
        assert!(fo > 0.0 && fo < 1.0);
        assert!(fi > 0.0 && fi < 1.0);

        // Due to different curves, they should NOT be equal at midpoint
        // (unlike symmetric where they would be)
        // Just verify they're valid
        assert!((fo + fi) > 0.0);
    }

    #[test]
    fn test_custom_curve() {
        // Custom curve with specific control points
        let points = vec![
            (0.0, 0.0),
            (0.25, 0.5), // Fast initial rise
            (0.75, 0.5), // Plateau
            (1.0, 1.0),  // Final rise
        ];
        let curve = CrossfadeCurve::Custom(points);

        // Test interpolation
        assert!((curve.evaluate(0.0) - 0.0).abs() < 0.01);
        assert!((curve.evaluate(0.25) - 0.5).abs() < 0.01);
        assert!((curve.evaluate(0.5) - 0.5).abs() < 0.01); // Should be on plateau
        assert!((curve.evaluate(1.0) - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_crossfade_creation() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);

        // Create two adjacent clips
        let clip_a = manager.create_clip(track, "Clip A", "a.wav", 0.0, 4.0, 4.0);
        let clip_b = manager.create_clip(track, "Clip B", "b.wav", 3.5, 4.0, 4.0);

        // Create symmetric crossfade
        let xfade_id = manager
            .create_crossfade(clip_a, clip_b, 0.5, CrossfadeCurve::EqualPower)
            .unwrap();

        let xfade = manager.get_crossfade(xfade_id).unwrap();
        assert_eq!(xfade.duration, 0.5);
        assert!(matches!(
            xfade.shape,
            CrossfadeShape::Symmetric(CrossfadeCurve::EqualPower)
        ));
    }

    #[test]
    fn test_asymmetric_crossfade_creation() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);

        let clip_a = manager.create_clip(track, "Clip A", "a.wav", 0.0, 4.0, 4.0);
        let clip_b = manager.create_clip(track, "Clip B", "b.wav", 3.5, 4.0, 4.0);

        // Create asymmetric crossfade
        let xfade_id = manager
            .create_asymmetric_crossfade(
                clip_a,
                clip_b,
                0.5,
                CrossfadeCurve::Exponential,
                CrossfadeCurve::Logarithmic,
            )
            .unwrap();

        let xfade = manager.get_crossfade(xfade_id).unwrap();
        assert!(matches!(xfade.shape, CrossfadeShape::Asymmetric { .. }));
    }

    #[test]
    fn test_crossfade_gains_at_time() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);

        let clip_a = manager.create_clip(track, "A", "a.wav", 0.0, 4.0, 4.0);
        let clip_b = manager.create_clip(track, "B", "b.wav", 3.5, 4.0, 4.0);

        let xfade_id = manager
            .create_crossfade(clip_a, clip_b, 1.0, CrossfadeCurve::Linear)
            .unwrap();

        let xfade = manager.get_crossfade(xfade_id).unwrap();

        // Before crossfade
        let (ga, gb) = xfade.get_gains_at_time(3.0);
        assert!((ga - 1.0).abs() < 0.01);
        assert!(gb < 0.01);

        // After crossfade
        let (ga, gb) = xfade.get_gains_at_time(5.0);
        assert!(ga < 0.01);
        assert!((gb - 1.0).abs() < 0.01);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLIP FX TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_clip_fx_chain_basic() {
        let mut chain = ClipFxChain::new();

        assert!(chain.is_empty());
        assert!(!chain.has_active_processing());

        // Add a gain FX
        let slot = ClipFxSlot::new(ClipFxType::Gain { db: -6.0, pan: 0.0 });
        let slot_id = chain.add_slot(slot);

        assert_eq!(chain.len(), 1);
        assert!(chain.has_active_processing());

        // Verify slot exists
        let slot = chain.get_slot(slot_id).unwrap();
        assert!(!slot.bypass);
        assert_eq!(slot.wet_dry, 1.0);
    }

    #[test]
    fn test_clip_fx_chain_bypass() {
        let mut chain = ClipFxChain::new();

        let slot = ClipFxSlot::new(ClipFxType::Saturation {
            drive: 0.5,
            mix: 1.0,
        });
        let slot_id = chain.add_slot(slot);

        // Active by default
        assert!(chain.has_active_processing());

        // Bypass slot
        if let Some(slot) = chain.get_slot_mut(slot_id) {
            slot.bypass = true;
        }
        assert!(!chain.has_active_processing());

        // Re-enable slot
        if let Some(slot) = chain.get_slot_mut(slot_id) {
            slot.bypass = false;
        }
        assert!(chain.has_active_processing());

        // Bypass entire chain
        chain.bypass = true;
        assert!(!chain.has_active_processing());
    }

    #[test]
    fn test_clip_fx_chain_ordering() {
        let mut chain = ClipFxChain::new();

        // Add 3 FX in order
        let slot1 = ClipFxSlot::new(ClipFxType::Gain { db: 0.0, pan: 0.0 }).with_name("Gain 1");
        let slot2 = ClipFxSlot::new(ClipFxType::Compressor {
            ratio: 4.0,
            threshold_db: -20.0,
            attack_ms: 10.0,
            release_ms: 100.0,
        })
        .with_name("Compressor");
        let slot3 = ClipFxSlot::new(ClipFxType::Limiter { ceiling_db: -0.3 }).with_name("Limiter");

        let id1 = chain.add_slot(slot1);
        let id2 = chain.add_slot(slot2);
        let id3 = chain.add_slot(slot3);

        // Verify order
        assert_eq!(chain.slots[0].order, 0);
        assert_eq!(chain.slots[1].order, 1);
        assert_eq!(chain.slots[2].order, 2);

        // Move slot3 to position 1
        chain.move_slot(id3, 1);

        // Verify new order
        assert_eq!(chain.slots[0].id, id1);
        assert_eq!(chain.slots[1].id, id3);
        assert_eq!(chain.slots[2].id, id2);

        // Remove middle slot
        chain.remove_slot(id3);
        assert_eq!(chain.len(), 2);
        assert_eq!(chain.slots[0].order, 0);
        assert_eq!(chain.slots[1].order, 1);
    }

    #[test]
    fn test_clip_fx_max_slots() {
        let mut chain = ClipFxChain::new();

        // Fill to max
        for i in 0..MAX_CLIP_FX_SLOTS {
            let slot = ClipFxSlot::new(ClipFxType::Gain {
                db: i as f64,
                pan: 0.0,
            });
            chain.add_slot(slot);
        }

        assert_eq!(chain.len(), MAX_CLIP_FX_SLOTS);

        // Add one more - should remove oldest
        let new_slot = ClipFxSlot::new(ClipFxType::Limiter { ceiling_db: 0.0 });
        chain.add_slot(new_slot);

        // Still at max, but first slot was removed
        assert_eq!(chain.len(), MAX_CLIP_FX_SLOTS);

        // The new limiter should be the last slot
        let last = chain.slots.last().unwrap();
        assert!(matches!(last.fx_type, ClipFxType::Limiter { .. }));
    }

    #[test]
    fn test_clip_fx_gains() {
        let chain = ClipFxChain {
            slots: vec![],
            bypass: false,
            input_gain_db: -6.0, // -6dB = 0.5
            output_gain_db: 6.0, // +6dB = ~2.0
        };

        let input_gain = chain.input_gain_linear();
        let output_gain = chain.output_gain_linear();

        // -6dB should be approximately 0.501
        assert!((input_gain - 0.501).abs() < 0.01);

        // +6dB should be approximately 1.995
        assert!((output_gain - 1.995).abs() < 0.01);
    }

    #[test]
    fn test_clip_with_fx() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);
        let clip_id = manager.create_clip(track, "Clip", "audio.wav", 0.0, 4.0, 4.0);

        // Initially no FX
        let clip = manager.get_clip(clip_id).unwrap();
        assert!(!clip.has_fx());
        assert!(clip.fx_chain.is_empty());

        // Add FX via TrackManager
        let slot_id = manager
            .add_clip_fx(clip_id, ClipFxType::Gain { db: 3.0, pan: -0.5 })
            .unwrap();

        // Verify FX added
        let clip = manager.get_clip(clip_id).unwrap();
        assert!(clip.has_fx());
        assert_eq!(clip.fx_chain.len(), 1);

        // Get slot
        let slot = manager.get_clip_fx_slot(clip_id, slot_id).unwrap();
        assert!(
            matches!(slot.fx_type, ClipFxType::Gain { db, pan } if (db - 3.0).abs() < 0.01 && (pan - (-0.5)).abs() < 0.01)
        );

        // Bypass FX
        manager.set_clip_fx_bypass(clip_id, slot_id, true);
        let clip = manager.get_clip(clip_id).unwrap();
        assert!(!clip.has_fx()); // Bypassed = not active

        // Remove FX
        manager.remove_clip_fx(clip_id, slot_id);
        let clip = manager.get_clip(clip_id).unwrap();
        assert!(clip.fx_chain.is_empty());
    }

    #[test]
    fn test_copy_clip_fx() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);

        let clip1 = manager.create_clip(track, "Clip 1", "a.wav", 0.0, 2.0, 2.0);
        let clip2 = manager.create_clip(track, "Clip 2", "b.wav", 2.0, 2.0, 2.0);

        // Add FX to clip1
        manager.add_clip_fx(
            clip1,
            ClipFxType::Compressor {
                ratio: 4.0,
                threshold_db: -18.0,
                attack_ms: 5.0,
                release_ms: 50.0,
            },
        );
        manager.add_clip_fx(clip1, ClipFxType::Limiter { ceiling_db: -1.0 });
        manager.set_clip_fx_input_gain(clip1, -3.0);

        // Copy FX to clip2
        assert!(manager.copy_clip_fx(clip1, clip2));

        // Verify copy
        let chain1 = manager.get_clip_fx_chain(clip1).unwrap();
        let chain2 = manager.get_clip_fx_chain(clip2).unwrap();

        assert_eq!(chain2.len(), chain1.len());
        assert!((chain2.input_gain_db - chain1.input_gain_db).abs() < 0.01);

        // Slot IDs should be different (regenerated)
        assert_ne!(chain1.slots[0].id, chain2.slots[0].id);
    }

    #[test]
    fn test_clip_fx_slot_builder() {
        let slot = ClipFxSlot::new(ClipFxType::Saturation {
            drive: 0.7,
            mix: 0.8,
        })
        .with_name("Warm Saturation")
        .with_wet_dry(0.5)
        .bypassed();

        assert_eq!(slot.name, "Warm Saturation");
        assert_eq!(slot.wet_dry, 0.5);
        assert!(slot.bypass);
    }

    #[test]
    fn test_clip_fx_types() {
        // Test all FX types can be constructed
        let types = vec![
            ClipFxType::ProEq { bands: 8 },
            ClipFxType::UltraEq,
            ClipFxType::Pultec,
            ClipFxType::Api550,
            ClipFxType::Neve1073,
            ClipFxType::MorphEq,
            ClipFxType::RoomCorrection,
            ClipFxType::Compressor {
                ratio: 4.0,
                threshold_db: -20.0,
                attack_ms: 10.0,
                release_ms: 100.0,
            },
            ClipFxType::Limiter { ceiling_db: -0.1 },
            ClipFxType::Gate {
                threshold_db: -40.0,
                attack_ms: 1.0,
                release_ms: 50.0,
            },
            ClipFxType::Gain { db: 0.0, pan: 0.0 },
            ClipFxType::PitchShift {
                semitones: 12.0,
                cents: 0.0,
            },
            ClipFxType::TimeStretch { ratio: 1.0 },
            ClipFxType::Saturation {
                drive: 0.5,
                mix: 1.0,
            },
            ClipFxType::External {
                plugin_id: "com.vendor.plugin".to_string(),
                state: None,
            },
        ];

        for fx_type in types {
            let slot = ClipFxSlot::new(fx_type);
            assert!(!slot.bypass);
        }
    }

    #[test]
    fn test_clip_fx_gain_calculation() {
        let slot = ClipFxSlot {
            id: ClipFxSlotId(1),
            fx_type: ClipFxType::Gain { db: 0.0, pan: 0.0 },
            bypass: false,
            wet_dry: 1.0,
            output_gain_db: -6.0,
            name: String::new(),
            order: 0,
        };

        // -6dB should be approximately 0.501
        let gain = slot.output_gain_linear();
        assert!((gain - 0.501).abs() < 0.01);

        // Test -infinity
        let slot_muted = ClipFxSlot {
            output_gain_db: -100.0,
            ..slot
        };
        assert_eq!(slot_muted.output_gain_linear(), 0.0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // Clip Envelope Tests
    // ═════════════════════════════════════════════════════════════════════

    #[test]
    fn test_clip_envelope_default_value() {
        let env = ClipEnvelope::pitch();
        assert_eq!(env.value_at(0), 0.0);
        assert_eq!(env.value_at(48000), 0.0);
        assert!(!env.is_active());
    }

    #[test]
    fn test_clip_envelope_single_point() {
        let mut env = ClipEnvelope::pitch();
        env.add_point(ClipEnvelopePoint::new(24000, 5.0));
        assert!(env.is_active());

        // Before point: returns first point value
        assert_eq!(env.value_at(0), 5.0);
        // At point
        assert_eq!(env.value_at(24000), 5.0);
        // After point: returns last point value
        assert_eq!(env.value_at(48000), 5.0);
    }

    #[test]
    fn test_clip_envelope_linear_interpolation() {
        let mut env = ClipEnvelope::pitch();
        env.add_point(ClipEnvelopePoint::new(0, 0.0));
        env.add_point(ClipEnvelopePoint::new(48000, 12.0)); // 0 to +12 semitones over 1 sec

        // Midpoint: 6 semitones
        let val = env.value_at(24000);
        assert!((val - 6.0).abs() < 0.01, "Expected ~6.0, got {}", val);

        // Quarter: 3 semitones
        let val = env.value_at(12000);
        assert!((val - 3.0).abs() < 0.01, "Expected ~3.0, got {}", val);
    }

    #[test]
    fn test_clip_envelope_step_curve() {
        let mut env = ClipEnvelope::pitch();
        env.add_point(
            ClipEnvelopePoint::new(0, 0.0).with_curve(ClipEnvelopeCurve::Step),
        );
        env.add_point(ClipEnvelopePoint::new(48000, 12.0));

        // Step holds the value until next point
        assert_eq!(env.value_at(24000), 0.0);
        assert_eq!(env.value_at(47999), 0.0);
        assert_eq!(env.value_at(48000), 12.0);
    }

    #[test]
    fn test_clip_envelope_sorted_insertion() {
        let mut env = ClipEnvelope::pitch();
        env.add_point(ClipEnvelopePoint::new(48000, 12.0));
        env.add_point(ClipEnvelopePoint::new(0, 0.0));
        env.add_point(ClipEnvelopePoint::new(24000, 6.0));

        // Should be sorted by offset
        assert_eq!(env.points[0].offset_samples, 0);
        assert_eq!(env.points[1].offset_samples, 24000);
        assert_eq!(env.points[2].offset_samples, 48000);
    }

    #[test]
    fn test_clip_envelope_replace_at_same_offset() {
        let mut env = ClipEnvelope::pitch();
        env.add_point(ClipEnvelopePoint::new(24000, 5.0));
        env.add_point(ClipEnvelopePoint::new(24000, 10.0));

        // Should replace, not duplicate
        assert_eq!(env.points.len(), 1);
        assert_eq!(env.points[0].value, 10.0);
    }

    #[test]
    fn test_clip_envelope_playrate() {
        let mut env = ClipEnvelope::playrate();
        assert_eq!(env.default_value, 1.0);

        env.add_point(ClipEnvelopePoint::new(0, 1.0));
        env.add_point(ClipEnvelopePoint::new(48000, 2.0)); // Ramp from 1x to 2x

        let val = env.value_at(24000);
        assert!((val - 1.5).abs() < 0.01, "Expected ~1.5, got {}", val);
    }

    #[test]
    fn test_clip_pitch_at_with_envelope() {
        let mut clip = Clip::new(TrackId(1), "test", "test.wav", 0.0, 1.0);
        clip.set_pitch_shift(2.0); // Base: +2 semitones

        // No envelope: returns base
        assert_eq!(clip.pitch_at(0), 2.0);

        // With envelope adding +3 semitones at midpoint
        let env = clip.enable_pitch_envelope();
        env.add_point(ClipEnvelopePoint::new(0, 0.0));
        env.add_point(ClipEnvelopePoint::new(48000, 6.0));

        // At midpoint: base 2.0 + envelope 3.0 = 5.0
        let val = clip.pitch_at(24000);
        assert!((val - 5.0).abs() < 0.01, "Expected ~5.0, got {}", val);
    }

    #[test]
    fn test_clip_playback_rate_at_with_envelope() {
        let mut clip = Clip::new(TrackId(1), "test", "test.wav", 0.0, 1.0);
        clip.set_stretch_ratio(1.0);
        clip.set_pitch_shift(0.0);

        // With playrate envelope: ramp from 1x to 2x
        let env = clip.enable_playrate_envelope();
        env.add_point(ClipEnvelopePoint::new(0, 1.0));
        env.add_point(ClipEnvelopePoint::new(48000, 2.0));

        let rate = clip.playback_rate_at(24000);
        // stretch(1.0) * playrate_env(1.5) * 2^(0/12) = 1.5
        assert!(
            (rate - 1.5).abs() < 0.01,
            "Expected ~1.5, got {}",
            rate
        );
    }

    #[test]
    fn test_clip_source_position_with_envelope() {
        let mut clip = Clip::new(TrackId(1), "test", "test.wav", 0.0, 1.0);
        clip.set_pitch_shift(0.0);
        clip.set_stretch_ratio(1.0);

        // No envelope: source_pos = offset * rate_ratio * 1.0
        let pos = clip.source_position_at(48000, 1.0, 0.0);
        assert!((pos - 48000.0).abs() < 1.0, "Expected ~48000, got {}", pos);

        // With playrate envelope 2x constant: should traverse twice as fast
        let env = clip.enable_playrate_envelope();
        env.add_point(ClipEnvelopePoint::new(0, 2.0));

        let pos = clip.source_position_at(48000, 1.0, 0.0);
        assert!(
            (pos - 96000.0).abs() < 1.0,
            "Expected ~96000, got {}",
            pos
        );
    }

    #[test]
    fn test_clip_integrated_value() {
        let mut env = ClipEnvelope::playrate();
        // Constant rate 2.0 for 48000 samples: integral = 2.0 * 48000 = 96000
        env.add_point(ClipEnvelopePoint::new(0, 2.0));

        let integral = env.integrated_value_to(48000);
        assert!(
            (integral - 96000.0).abs() < 1.0,
            "Expected ~96000, got {}",
            integral
        );

        // Linear ramp 1.0 to 3.0 over 48000: integral = (1+3)/2 * 48000 = 96000
        let mut env2 = ClipEnvelope::playrate();
        env2.add_point(ClipEnvelopePoint::new(0, 1.0));
        env2.add_point(ClipEnvelopePoint::new(48000, 3.0));

        let integral2 = env2.integrated_value_to(48000);
        assert!(
            (integral2 - 96000.0).abs() < 1.0,
            "Expected ~96000, got {}",
            integral2
        );
    }

    #[test]
    fn test_clip_envelope_remove_point() {
        let mut env = ClipEnvelope::pitch();
        env.add_point(ClipEnvelopePoint::new(0, 0.0));
        env.add_point(ClipEnvelopePoint::new(24000, 6.0));
        env.add_point(ClipEnvelopePoint::new(48000, 12.0));

        assert_eq!(env.points.len(), 3);
        assert!(env.remove_point_at(24000, 100));
        assert_eq!(env.points.len(), 2);

        // Middle point removed: interpolation between 0 and 48000
        let val = env.value_at(24000);
        assert!((val - 6.0).abs() < 0.01);
    }

    #[test]
    fn test_clip_has_active_envelope() {
        let mut clip = Clip::new(TrackId(1), "test", "test.wav", 0.0, 1.0);
        assert!(!clip.has_active_envelope());

        // Create envelope but no points → not active
        clip.enable_pitch_envelope();
        assert!(!clip.has_active_envelope());

        // Add a point → active
        clip.pitch_envelope.as_mut().unwrap().add_point(
            ClipEnvelopePoint::new(0, 5.0),
        );
        assert!(clip.has_active_envelope());

        // Disable → not active
        clip.pitch_envelope.as_mut().unwrap().enabled = false;
        assert!(!clip.has_active_envelope());
    }

    // ═══════════════════════════════════════════════════════════════════
    // RAZOR EDIT TESTS
    // ═══════════════════════════════════════════════════════════════════

    #[test]
    fn test_razor_area_creation() {
        let area = RazorArea::new(TrackId(1), 2.0, 5.0);
        assert_eq!(area.track_id, TrackId(1));
        assert_eq!(area.start, 2.0);
        assert_eq!(area.end, 5.0);
        assert_eq!(area.duration(), 3.0);
        assert!(!area.is_empty());
        assert!(area.contains_time(3.0));
        assert!(!area.contains_time(1.0));
        assert!(!area.contains_time(5.0)); // exclusive end
    }

    #[test]
    fn test_razor_area_reversed_bounds() {
        // End before start should auto-sort
        let area = RazorArea::new(TrackId(1), 5.0, 2.0);
        assert_eq!(area.start, 2.0);
        assert_eq!(area.end, 5.0);
    }

    #[test]
    fn test_razor_area_clip_intersection() {
        let area = RazorArea::new(TrackId(1), 3.0, 7.0);

        // Clip fully inside razor
        assert_eq!(area.clip_intersection(4.0, 6.0), Some((4.0, 6.0)));
        assert!(area.fully_contains_clip(4.0, 6.0));

        // Clip partially overlapping left
        assert_eq!(area.clip_intersection(1.0, 5.0), Some((3.0, 5.0)));
        assert!(!area.fully_contains_clip(1.0, 5.0));

        // Clip partially overlapping right
        assert_eq!(area.clip_intersection(5.0, 9.0), Some((5.0, 7.0)));

        // No overlap
        assert_eq!(area.clip_intersection(0.0, 2.0), None);
        assert_eq!(area.clip_intersection(8.0, 10.0), None);

        // Clip spans entire razor
        assert_eq!(area.clip_intersection(1.0, 10.0), Some((3.0, 7.0)));
        assert!(!area.fully_contains_clip(1.0, 10.0));
    }

    #[test]
    fn test_razor_manager_crud() {
        let tm = TrackManager::new();
        assert!(!tm.has_razor_areas());

        // Add areas
        let id1 = tm.add_razor_area(TrackId(1), 2.0, 5.0);
        let id2 = tm.add_razor_area(TrackId(2), 3.0, 6.0);
        assert!(tm.has_razor_areas());

        let areas = tm.get_razor_areas();
        assert_eq!(areas.len(), 2);

        // Track-specific query
        let t1_areas = tm.get_track_razor_areas(TrackId(1));
        assert_eq!(t1_areas.len(), 1);
        assert_eq!(t1_areas[0].start, 2.0);

        // Update
        tm.update_razor_area(id1, 1.0, 4.0);
        let areas = tm.get_razor_areas();
        let a1 = areas.iter().find(|a| a.id == id1).unwrap();
        assert_eq!(a1.start, 1.0);
        assert_eq!(a1.end, 4.0);

        // Remove one
        tm.remove_razor_area(id2);
        assert_eq!(tm.get_razor_areas().len(), 1);

        // Clear all
        tm.clear_razor_areas();
        assert!(!tm.has_razor_areas());
    }

    #[test]
    fn test_razor_delete_full_clip() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        // Create clip at [2.0, 5.0]
        tm.create_clip(tid, "clip", "clip.wav", 2.0, 3.0, 10.0);

        // Razor covers entire clip
        tm.add_razor_area(tid, 1.0, 6.0);
        tm.razor_delete();

        assert_eq!(tm.get_clips_for_track(tid).len(), 0);
        assert!(!tm.has_razor_areas()); // Areas cleared after delete
    }

    #[test]
    fn test_razor_delete_left_trim() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        // Clip at [2.0, 8.0] (duration 6.0)
        tm.create_clip(tid, "clip", "clip.wav", 2.0, 6.0, 10.0);

        // Razor covers left portion [1.0, 4.0]
        tm.add_razor_area(tid, 1.0, 4.0);
        tm.razor_delete();

        let clips = tm.get_clips_for_track(tid);
        assert_eq!(clips.len(), 1);
        let clip = &clips[0];
        assert!((clip.start_time - 4.0).abs() < 0.01);
        assert!((clip.duration - 4.0).abs() < 0.01);
        assert!((clip.source_offset - 2.0).abs() < 0.01);
    }

    #[test]
    fn test_razor_delete_right_trim() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        // Clip at [2.0, 8.0]
        tm.create_clip(tid, "clip", "clip.wav", 2.0, 6.0, 10.0);

        // Razor covers right portion [6.0, 10.0]
        tm.add_razor_area(tid, 6.0, 10.0);
        tm.razor_delete();

        let clips = tm.get_clips_for_track(tid);
        assert_eq!(clips.len(), 1);
        let clip = &clips[0];
        assert!((clip.start_time - 2.0).abs() < 0.01);
        assert!((clip.duration - 4.0).abs() < 0.01);
    }

    #[test]
    fn test_razor_delete_middle_punch() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        // Clip at [1.0, 9.0] (duration 8.0)
        tm.create_clip(tid, "clip", "clip.wav", 1.0, 8.0, 10.0);

        // Razor punches hole in middle [3.0, 6.0]
        tm.add_razor_area(tid, 3.0, 6.0);
        tm.razor_delete();

        let mut clips = tm.get_clips_for_track(tid);
        clips.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        assert_eq!(clips.len(), 2);

        // Left piece [1.0, 3.0]
        assert!((clips[0].start_time - 1.0).abs() < 0.01);
        assert!((clips[0].duration - 2.0).abs() < 0.01);

        // Right piece [6.0, 9.0]
        assert!((clips[1].start_time - 6.0).abs() < 0.01);
        assert!((clips[1].duration - 3.0).abs() < 0.01);
    }

    #[test]
    fn test_razor_split() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        // Clip at [1.0, 9.0]
        tm.create_clip(tid, "clip", "clip.wav", 1.0, 8.0, 10.0);

        // Razor [3.0, 6.0] — splits at both boundaries
        tm.add_razor_area(tid, 3.0, 6.0);
        tm.razor_split();

        let mut clips = tm.get_clips_for_track(tid);
        clips.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        assert_eq!(clips.len(), 3);

        // [1.0, 3.0], [3.0, 6.0], [6.0, 9.0]
        assert!((clips[0].start_time - 1.0).abs() < 0.01);
        assert!((clips[0].duration - 2.0).abs() < 0.01);
        assert!((clips[1].start_time - 3.0).abs() < 0.01);
        assert!((clips[1].duration - 3.0).abs() < 0.01);
        assert!((clips[2].start_time - 6.0).abs() < 0.01);
        assert!((clips[2].duration - 3.0).abs() < 0.01);
    }

    #[test]
    fn test_razor_copy() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        // Clip at [2.0, 8.0]
        tm.create_clip(tid, "clip", "clip.wav", 2.0, 6.0, 10.0);

        // Razor [4.0, 6.0] — partial copy
        tm.add_razor_area(tid, 4.0, 6.0);
        let clipboard = tm.razor_copy();

        assert_eq!(clipboard.len(), 1);
        let (rel_time, track_id, clip) = &clipboard[0];
        assert_eq!(*rel_time, 0.0); // First item at relative 0
        assert_eq!(*track_id, tid);
        assert!((clip.duration - 2.0).abs() < 0.01);
        assert!((clip.source_offset - 2.0).abs() < 0.01); // 4.0 - 2.0 start offset

        // Original clip unchanged
        let clips = tm.get_clips_for_track(tid);
        assert_eq!(clips.len(), 1);
        assert!((clips[0].duration - 6.0).abs() < 0.01);
    }

    #[test]
    fn test_razor_cut() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        // Clip at [2.0, 8.0]
        tm.create_clip(tid, "clip", "clip.wav", 2.0, 6.0, 10.0);

        // Razor entire clip
        tm.add_razor_area(tid, 2.0, 8.0);
        let clipboard = tm.razor_cut();

        assert_eq!(clipboard.len(), 1);
        assert_eq!(tm.get_clips_for_track(tid).len(), 0); // Deleted after cut
    }

    #[test]
    fn test_razor_content_filter() {
        let area_media = RazorArea::with_content(TrackId(1), 0.0, 5.0, RazorContent::Media);
        assert!(area_media.affects_media());
        assert!(!area_media.affects_envelope());

        let area_env = RazorArea::with_content(TrackId(1), 0.0, 5.0, RazorContent::Envelope);
        assert!(!area_env.affects_media());
        assert!(area_env.affects_envelope());

        let area_both = RazorArea::with_content(TrackId(1), 0.0, 5.0, RazorContent::Both);
        assert!(area_both.affects_media());
        assert!(area_both.affects_envelope());
    }

    #[test]
    fn test_razor_multi_track() {
        let tm = TrackManager::new();
        let tid1 = tm.create_track("Track 1", 0xFFFF0000, OutputBus::Master);
        let tid2 = tm.create_track("Track 2", 0xFF00FF00, OutputBus::Master);

        tm.create_clip(tid1, "clip a", "a.wav", 1.0, 4.0, 10.0);
        tm.create_clip(tid2, "clip b", "b.wav", 2.0, 3.0, 10.0);

        // Razor areas on both tracks
        tm.add_razor_area(tid1, 2.0, 4.0);
        tm.add_razor_area(tid2, 3.0, 5.0);

        tm.razor_delete();

        // Track 1: clip [1.0, 5.0] with razor [2.0, 4.0] → [1.0, 2.0] and [4.0, 5.0]
        let mut clips1 = tm.get_clips_for_track(tid1);
        clips1.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        assert_eq!(clips1.len(), 2);
        assert!((clips1[0].start_time - 1.0).abs() < 0.01);
        assert!((clips1[0].duration - 1.0).abs() < 0.01);
        assert!((clips1[1].start_time - 4.0).abs() < 0.01);
        assert!((clips1[1].duration - 1.0).abs() < 0.01);

        // Track 2: clip [2.0, 5.0] with razor [3.0, 5.0] → trimmed to [2.0, 3.0]
        let clips2 = tm.get_clips_for_track(tid2);
        assert_eq!(clips2.len(), 1);
        assert!((clips2[0].duration - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_razor_duplicate() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        tm.create_clip(tid, "clip", "clip.wav", 2.0, 4.0, 10.0);

        // Razor the whole clip [2.0, 6.0]
        tm.add_razor_area(tid, 2.0, 6.0);
        let new_ids = tm.razor_duplicate();

        assert_eq!(new_ids.len(), 1);

        let mut clips = tm.get_clips_for_track(tid);
        clips.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        assert_eq!(clips.len(), 2);

        // Original at [2.0, 6.0]
        assert!((clips[0].start_time - 2.0).abs() < 0.01);
        // Duplicate at [6.0, 10.0]
        assert!((clips[1].start_time - 6.0).abs() < 0.01);
        assert!((clips[1].duration - 4.0).abs() < 0.01);
    }

    #[test]
    fn test_razor_reverse() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        tm.create_clip(tid, "clip", "clip.wav", 1.0, 8.0, 10.0);

        // Razor middle portion [3.0, 6.0]
        tm.add_razor_area(tid, 3.0, 6.0);
        tm.razor_reverse();

        let mut clips = tm.get_clips_for_track(tid);
        clips.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());

        // Should have 3 clips after split: [1,3] [3,6] [6,9]
        assert_eq!(clips.len(), 3);

        // Only middle is reversed
        assert!(!clips[0].reversed);
        assert!(clips[1].reversed);
        assert!(!clips[2].reversed);
    }

    #[test]
    fn test_razor_stretch() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Test", 0xFFFFFFFF, OutputBus::Master);

        tm.create_clip(tid, "clip", "clip.wav", 2.0, 4.0, 10.0);

        // Razor entire clip, stretch 2x
        tm.add_razor_area(tid, 2.0, 6.0);
        tm.razor_stretch(2.0);

        let clips = tm.get_clips_for_track(tid);
        assert_eq!(clips.len(), 1);
        assert!((clips[0].duration - 8.0).abs() < 0.01); // 4.0 * 2.0
        assert!((clips[0].stretch_ratio - 2.0).abs() < 0.01);

        // Razor areas also stretched
        let areas = tm.get_razor_areas();
        assert_eq!(areas.len(), 1);
        assert!((areas[0].duration() - 8.0).abs() < 0.01); // 4.0 * 2.0
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MIX SNAPSHOT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_snapshot_capture_all() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Vocals", 0xFF0000FF, OutputBus::Master);
        tm.update_track(tid, |t| {
            t.volume = 0.75;
            t.pan = -0.5;
            t.muted = true;
        });

        let sid = tm.capture_mix_snapshot("Before mix", "Initial state", &[], &[]);
        let snapshots = tm.get_mix_snapshots();
        assert_eq!(snapshots.len(), 1);
        assert_eq!(snapshots[0].name, "Before mix");
        assert_eq!(snapshots[0].categories.len(), 10); // All categories
        assert_eq!(snapshots[0].tracks.len(), 1);
        assert_eq!(snapshots[0].tracks[0].volume, Some(0.75));
        assert_eq!(snapshots[0].tracks[0].pan, Some((-0.5, 1.0))); // pan_right=1.0 default stereo
        assert_eq!(snapshots[0].tracks[0].muted, Some(true));

        // Now change and recall
        tm.update_track(tid, |t| {
            t.volume = 1.0;
            t.pan = 0.0;
            t.muted = false;
        });
        let affected = tm.recall_mix_snapshot(sid, &[], &[]);
        assert_eq!(affected, 1);

        let track = tm.get_track(tid).unwrap();
        assert!((track.volume - 0.75).abs() < 0.001);
        assert!((track.pan - (-0.5)).abs() < 0.001);
        assert!(track.muted);
    }

    #[test]
    fn test_snapshot_selective_recall() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Guitar", 0xFF00FF00, OutputBus::Master);
        tm.update_track(tid, |t| {
            t.volume = 0.5;
            t.pan = 0.7;
            t.muted = true;
        });

        let sid = tm.capture_mix_snapshot("Full", "", &[], &[]);

        // Change everything
        tm.update_track(tid, |t| {
            t.volume = 1.0;
            t.pan = 0.0;
            t.muted = false;
        });

        // Recall ONLY volume
        tm.recall_mix_snapshot(sid, &[SnapshotCategory::Volume], &[]);
        let track = tm.get_track(tid).unwrap();
        assert!((track.volume - 0.5).abs() < 0.001); // Restored
        assert!((track.pan - 0.0).abs() < 0.001); // NOT restored
        assert!(!track.muted); // NOT restored
    }

    #[test]
    fn test_snapshot_track_filter() {
        let tm = TrackManager::new();
        let t1 = tm.create_track("Track 1", 0xFFFFFFFF, OutputBus::Master);
        let t2 = tm.create_track("Track 2", 0xFFFFFFFF, OutputBus::Master);
        tm.update_track(t1, |t| t.volume = 0.3);
        tm.update_track(t2, |t| t.volume = 0.7);

        // Capture only Track 1
        let sid = tm.capture_mix_snapshot("T1 only", "", &[], &[t1]);
        let snap = tm.get_mix_snapshot(sid).unwrap();
        assert_eq!(snap.tracks.len(), 1);
        assert_eq!(snap.tracks[0].track_id, t1);

        // Change both
        tm.update_track(t1, |t| t.volume = 1.0);
        tm.update_track(t2, |t| t.volume = 1.0);

        // Recall — only T1 affected
        tm.recall_mix_snapshot(sid, &[], &[]);
        assert!((tm.get_track(t1).unwrap().volume - 0.3).abs() < 0.001);
        assert!((tm.get_track(t2).unwrap().volume - 1.0).abs() < 0.001); // Unchanged
    }

    #[test]
    fn test_snapshot_clip_gain() {
        let tm = TrackManager::new();
        let tid = tm.create_track("Audio", 0xFFFFFFFF, OutputBus::Master);
        let cid = tm.create_clip(tid, "vocal", "vocal.wav", 0.0, 5.0, 5.0);
        tm.update_clip(cid, |c| c.gain = 0.6);

        let sid = tm.capture_mix_snapshot("With gain", "", &[SnapshotCategory::ClipGain], &[]);

        // Change clip gain
        tm.update_clip(cid, |c| c.gain = 1.0);

        // Recall
        tm.recall_mix_snapshot(sid, &[], &[]);
        let clip = tm.get_clip(cid).unwrap();
        assert!((clip.gain - 0.6).abs() < 0.001);
    }

    #[test]
    fn test_snapshot_sends() {
        let tm = TrackManager::new();
        let tid = tm.create_track("FX Track", 0xFFFFFFFF, OutputBus::Master);
        tm.update_track(tid, |t| {
            t.sends[0].level = 0.8;
            t.sends[0].pre_fader = true;
            t.sends[0].destination = Some(OutputBus::Aux);
            t.sends[1].level = 0.4;
        });

        let sid = tm.capture_mix_snapshot("Send setup", "", &[SnapshotCategory::Sends], &[]);

        // Clear sends
        tm.update_track(tid, |t| {
            t.sends = Default::default();
        });

        // Recall
        tm.recall_mix_snapshot(sid, &[], &[]);
        let track = tm.get_track(tid).unwrap();
        assert!((track.sends[0].level - 0.8).abs() < 0.001);
        assert!(track.sends[0].pre_fader);
        assert_eq!(track.sends[0].destination, Some(OutputBus::Aux));
        assert!((track.sends[1].level - 0.4).abs() < 0.001);
    }

    #[test]
    fn test_snapshot_crud() {
        let tm = TrackManager::new();
        let _tid = tm.create_track("T", 0xFFFFFFFF, OutputBus::Master);

        let s1 = tm.capture_mix_snapshot("A", "", &[], &[]);
        let s2 = tm.capture_mix_snapshot("B", "", &[], &[]);
        assert_eq!(tm.get_mix_snapshots().len(), 2);

        // Rename
        assert!(tm.rename_mix_snapshot(s1, "A Renamed"));
        assert_eq!(tm.get_mix_snapshot(s1).unwrap().name, "A Renamed");

        // Delete
        assert!(tm.delete_mix_snapshot(s2));
        assert_eq!(tm.get_mix_snapshots().len(), 1);

        // Clear
        tm.clear_mix_snapshots();
        assert_eq!(tm.get_mix_snapshots().len(), 0);
    }

    #[test]
    fn test_snapshot_update() {
        let tm = TrackManager::new();
        let tid = tm.create_track("T", 0xFFFFFFFF, OutputBus::Master);
        tm.update_track(tid, |t| t.volume = 0.5);

        let sid = tm.capture_mix_snapshot("Snap", "", &[SnapshotCategory::Volume], &[]);

        // Change volume, then update snapshot
        tm.update_track(tid, |t| t.volume = 0.9);
        assert!(tm.update_mix_snapshot(sid));

        // Recall should give 0.9 (updated), not 0.5 (original)
        tm.update_track(tid, |t| t.volume = 0.0);
        tm.recall_mix_snapshot(sid, &[], &[]);
        assert!((tm.get_track(tid).unwrap().volume - 0.9).abs() < 0.001);
    }

    #[test]
    fn test_snapshot_json_roundtrip() {
        let tm = TrackManager::new();
        let tid = tm.create_track("JSON Test", 0xFF112233, OutputBus::Music);
        tm.update_track(tid, |t| {
            t.volume = 0.42;
            t.pan = -0.3;
            t.phase_inverted = true;
        });

        tm.capture_mix_snapshot("Export", "For JSON", &[], &[]);
        let json = tm.mix_snapshots_to_json();

        // Load into fresh manager
        let tm2 = TrackManager::new();
        assert!(tm2.mix_snapshots_from_json(&json));
        let loaded = tm2.get_mix_snapshots();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].name, "Export");
        assert_eq!(loaded[0].tracks[0].volume, Some(0.42));
        assert_eq!(loaded[0].tracks[0].phase_inverted, Some(true));
    }

    #[test]
    fn test_snapshot_multi_track_selective() {
        let tm = TrackManager::new();
        let t1 = tm.create_track("Vox", 0xFFFFFFFF, OutputBus::Master);
        let t2 = tm.create_track("Guitar", 0xFFFFFFFF, OutputBus::Music);
        let t3 = tm.create_track("Bass", 0xFFFFFFFF, OutputBus::Sfx);

        tm.update_track(t1, |t| { t.volume = 0.1; t.pan = -1.0; });
        tm.update_track(t2, |t| { t.volume = 0.2; t.pan = 0.5; });
        tm.update_track(t3, |t| { t.volume = 0.3; t.pan = 1.0; });

        // Capture all
        let sid = tm.capture_mix_snapshot("Full", "", &[], &[]);

        // Change all
        tm.update_track(t1, |t| { t.volume = 1.0; t.pan = 0.0; });
        tm.update_track(t2, |t| { t.volume = 1.0; t.pan = 0.0; });
        tm.update_track(t3, |t| { t.volume = 1.0; t.pan = 0.0; });

        // Recall volume only, only for T1 and T3
        tm.recall_mix_snapshot(sid, &[SnapshotCategory::Volume], &[t1, t3]);

        assert!((tm.get_track(t1).unwrap().volume - 0.1).abs() < 0.001);
        assert!((tm.get_track(t1).unwrap().pan - 0.0).abs() < 0.001); // Pan NOT recalled
        assert!((tm.get_track(t2).unwrap().volume - 1.0).abs() < 0.001); // T2 NOT affected
        assert!((tm.get_track(t3).unwrap().volume - 0.3).abs() < 0.001);
    }

    #[test]
    fn test_snapshot_solo_clear_on_recall() {
        let tm = TrackManager::new();
        let t1 = tm.create_track("Vox", 0xFFFFFFFF, OutputBus::Master);
        let t2 = tm.create_track("Guitar", 0xFFFFFFFF, OutputBus::Master);
        let t3 = tm.create_track("Keys", 0xFFFFFFFF, OutputBus::Master);

        // Snapshot: only T1 soloed
        tm.set_track_solo(t1, true);
        let sid = tm.capture_mix_snapshot("Solo", "", &[SnapshotCategory::MuteSolo], &[]);
        tm.set_track_solo(t1, false);

        // Now solo T3 (which wasn't in snapshot)
        tm.set_track_solo(t3, true);
        assert!(tm.get_track(t3).unwrap().soloed);

        // Recall — T1 should be soloed, T3 should be CLEARED
        tm.recall_mix_snapshot(sid, &[], &[]);
        assert!(tm.get_track(t1).unwrap().soloed);
        assert!(!tm.get_track(t2).unwrap().soloed);
        assert!(!tm.get_track(t3).unwrap().soloed); // Cleared by recall
    }

    #[test]
    fn test_snapshot_nonexistent_track_recall() {
        let tm = TrackManager::new();
        let t1 = tm.create_track("T1", 0xFFFFFFFF, OutputBus::Master);
        tm.update_track(t1, |t| t.volume = 0.5);

        let sid = tm.capture_mix_snapshot("Snap", "", &[], &[]);

        // Delete the track
        tm.delete_track(t1);

        // Recall should not crash, 0 tracks affected
        let affected = tm.recall_mix_snapshot(sid, &[], &[]);
        assert_eq!(affected, 0);
    }

    #[test]
    fn test_snapshot_update_atomic() {
        let tm = TrackManager::new();
        let tid = tm.create_track("T", 0xFFFFFFFF, OutputBus::Master);
        tm.update_track(tid, |t| t.volume = 0.3);

        let sid = tm.capture_mix_snapshot("V1", "", &[SnapshotCategory::Volume], &[]);
        assert_eq!(tm.get_mix_snapshots().len(), 1);

        // Update should NOT create extra snapshots
        tm.update_track(tid, |t| t.volume = 0.8);
        assert!(tm.update_mix_snapshot(sid));
        assert_eq!(tm.get_mix_snapshots().len(), 1); // Still 1, not 2

        // Recall gives updated value
        tm.update_track(tid, |t| t.volume = 0.0);
        tm.recall_mix_snapshot(sid, &[], &[]);
        assert!((tm.get_track(tid).unwrap().volume - 0.8).abs() < 0.001);
    }
}

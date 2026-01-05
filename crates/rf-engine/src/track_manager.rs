//! Track Manager - Cubase-style Track/Clip Management
//!
//! Provides:
//! - Track creation, deletion, reordering
//! - Clip management (move, resize, split, duplicate)
//! - Crossfade handling
//! - Undo/Redo command pattern
//! - Lock-free updates to audio thread

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use serde::{Deserialize, Serialize};
use parking_lot::RwLock;

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

// Global ID counter for generating unique IDs
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════
// OUTPUT BUS
// ═══════════════════════════════════════════════════════════════════════════

/// Output bus routing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OutputBus {
    Master = 0,
    Music = 1,
    Sfx = 2,
    Voice = 3,
    Ambience = 4,
    Aux = 5,
}

impl Default for OutputBus {
    fn default() -> Self {
        Self::Master
    }
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

/// Audio track with clips
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    pub id: TrackId,
    pub name: String,
    pub color: u32,           // ARGB color
    pub height: f64,          // UI height in pixels
    pub output_bus: OutputBus,
    pub volume: f64,          // 0.0 to 1.5 (linear, +6dB headroom)
    pub pan: f64,             // -1.0 to +1.0
    pub muted: bool,
    pub soloed: bool,
    pub armed: bool,
    pub locked: bool,
    pub frozen: bool,
    pub input_monitor: bool,
    pub order: usize,         // Position in track list
}

impl Track {
    pub fn new(name: &str, color: u32, output_bus: OutputBus) -> Self {
        Self {
            id: TrackId(next_id()),
            name: name.to_string(),
            color,
            height: 80.0,
            output_bus,
            volume: 1.0,
            pan: 0.0,
            muted: false,
            soloed: false,
            armed: false,
            locked: false,
            frozen: false,
            input_monitor: false,
            order: 0,
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
// CLIP
// ═══════════════════════════════════════════════════════════════════════════

/// Audio clip on a track
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Clip {
    pub id: ClipId,
    pub track_id: TrackId,
    pub name: String,
    pub color: Option<u32>,   // Override track color if set

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
    pub gain: f64,            // 0.0 to 2.0 (linear)
    pub muted: bool,
    pub selected: bool,
    /// Play audio in reverse
    #[serde(default)]
    pub reversed: bool,

    // Clip-based FX chain (non-destructive, per-clip processing)
    #[serde(default)]
    pub fx_chain: ClipFxChain,
}

impl Clip {
    pub fn new(track_id: TrackId, name: &str, source_file: &str, start_time: f64, duration: f64) -> Self {
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
            fx_chain: ClipFxChain::new(),
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

    /// End time on timeline
    #[inline]
    pub fn end_time(&self) -> f64 {
        self.start_time + self.duration
    }

    /// Check if this clip overlaps with another time range
    pub fn overlaps(&self, start: f64, end: f64) -> bool {
        self.start_time < end && self.end_time() > start
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSSFADE
// ═══════════════════════════════════════════════════════════════════════════

/// Crossfade curve type
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CrossfadeCurve {
    /// Straight line (0dB at midpoint)
    Linear,
    /// Equal power/constant power (-3dB at midpoint)
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

impl Default for CrossfadeCurve {
    fn default() -> Self {
        Self::EqualPower
    }
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
            CrossfadeCurve::Custom(points) => {
                Self::evaluate_custom(points, t)
            }
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
    pub fn new(track_id: TrackId, clip_a: ClipId, clip_b: ClipId, start_time: f64, duration: f64) -> Self {
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

// ═══════════════════════════════════════════════════════════════════════════
// TRACK MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Central manager for all tracks, clips, crossfades, and markers
pub struct TrackManager {
    /// All tracks (pub for lock-free audio thread access via try_read)
    pub tracks: RwLock<HashMap<TrackId, Track>>,
    /// All clips (pub for lock-free audio thread access via try_read)
    pub clips: RwLock<HashMap<ClipId, Clip>>,
    /// Crossfades between clips
    pub crossfades: RwLock<HashMap<CrossfadeId, Crossfade>>,
    /// Timeline markers
    pub markers: RwLock<Vec<Marker>>,
    /// Loop region
    pub loop_region: RwLock<LoopRegion>,
    /// Track ordering
    pub track_order: RwLock<Vec<TrackId>>,
}

impl TrackManager {
    pub fn new() -> Self {
        Self {
            tracks: RwLock::new(HashMap::new()),
            clips: RwLock::new(HashMap::new()),
            crossfades: RwLock::new(HashMap::new()),
            markers: RwLock::new(Vec::new()),
            loop_region: RwLock::new(LoopRegion::default()),
            track_order: RwLock::new(Vec::new()),
        }
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

        self.tracks.write().insert(id, track);
        id
    }

    /// Delete a track and all its clips
    pub fn delete_track(&self, track_id: TrackId) {
        // Remove all clips on this track
        let clip_ids: Vec<ClipId> = self.clips.read()
            .values()
            .filter(|c| c.track_id == track_id)
            .map(|c| c.id)
            .collect();

        for clip_id in clip_ids {
            self.delete_clip(clip_id);
        }

        // Remove from order
        self.track_order.write().retain(|&id| id != track_id);

        // Remove track
        self.tracks.write().remove(&track_id);
    }

    /// Get track by ID
    pub fn get_track(&self, track_id: TrackId) -> Option<Track> {
        self.tracks.read().get(&track_id).cloned()
    }

    /// Get all tracks in order
    pub fn get_all_tracks(&self) -> Vec<Track> {
        let tracks = self.tracks.read();
        let order = self.track_order.read();
        order.iter()
            .filter_map(|id| tracks.get(id).cloned())
            .collect()
    }

    /// Update track properties
    pub fn update_track<F>(&self, track_id: TrackId, f: F)
    where
        F: FnOnce(&mut Track),
    {
        if let Some(track) = self.tracks.write().get_mut(&track_id) {
            f(track);
        }
    }

    /// Reorder tracks
    pub fn reorder_tracks(&self, new_order: Vec<TrackId>) {
        let mut order = self.track_order.write();
        *order = new_order;

        // Update track order fields
        let mut tracks = self.tracks.write();
        for (idx, id) in order.iter().enumerate() {
            if let Some(track) = tracks.get_mut(id) {
                track.order = idx;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLIP OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Add a new clip
    pub fn add_clip(&self, clip: Clip) -> ClipId {
        let id = clip.id;
        self.clips.write().insert(id, clip);
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
        let xfade_ids: Vec<CrossfadeId> = self.crossfades.read()
            .values()
            .filter(|x| x.clip_a_id == clip_id || x.clip_b_id == clip_id)
            .map(|x| x.id)
            .collect();

        for xfade_id in xfade_ids {
            self.crossfades.write().remove(&xfade_id);
        }

        self.clips.write().remove(&clip_id);
    }

    /// Get clip by ID
    pub fn get_clip(&self, clip_id: ClipId) -> Option<Clip> {
        self.clips.read().get(&clip_id).cloned()
    }

    /// Get all clips for a track
    pub fn get_clips_for_track(&self, track_id: TrackId) -> Vec<Clip> {
        self.clips.read()
            .values()
            .filter(|c| c.track_id == track_id)
            .cloned()
            .collect()
    }

    /// Get all clips sorted by start time
    pub fn get_all_clips(&self) -> Vec<Clip> {
        let mut clips: Vec<_> = self.clips.read().values().cloned().collect();
        clips.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        clips
    }

    /// Move clip to new position (and optionally new track)
    pub fn move_clip(&self, clip_id: ClipId, new_track_id: TrackId, new_start_time: f64) {
        if let Some(clip) = self.clips.write().get_mut(&clip_id) {
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
        if let Some(clip) = self.clips.write().get_mut(&clip_id) {
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
        {
            let mut clips = self.clips.write();
            if let Some(clip) = clips.get_mut(&clip_id) {
                clip.duration = split_offset;
                clip.name = format!("{} (L)", original.name);
            }
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
        if let Some(clip) = self.clips.write().get_mut(&clip_id) {
            f(clip);
        }
    }

    /// Set clip selection state
    pub fn select_clip(&self, clip_id: ClipId, selected: bool) {
        self.update_clip(clip_id, |c| c.selected = selected);
    }

    /// Clear all clip selections
    pub fn clear_selection(&self) {
        for clip in self.clips.write().values_mut() {
            clip.selected = false;
        }
    }

    /// Get selected clips
    pub fn get_selected_clips(&self) -> Vec<Clip> {
        self.clips.read()
            .values()
            .filter(|c| c.selected)
            .cloned()
            .collect()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLIP FX OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Add FX to a clip's chain
    pub fn add_clip_fx(&self, clip_id: ClipId, fx_type: ClipFxType) -> Option<ClipFxSlotId> {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            Some(clip.add_fx(fx_type))
        } else {
            None
        }
    }

    /// Add FX slot to a clip's chain
    pub fn add_clip_fx_slot(&self, clip_id: ClipId, slot: ClipFxSlot) -> Option<ClipFxSlotId> {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            Some(clip.fx_chain.add_slot(slot))
        } else {
            None
        }
    }

    /// Insert FX at specific position in clip's chain
    pub fn insert_clip_fx(&self, clip_id: ClipId, index: usize, fx_type: ClipFxType) -> Option<ClipFxSlotId> {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            let slot = ClipFxSlot::new(fx_type);
            Some(clip.fx_chain.insert_slot(index, slot))
        } else {
            None
        }
    }

    /// Remove FX from a clip's chain
    pub fn remove_clip_fx(&self, clip_id: ClipId, slot_id: ClipFxSlotId) -> bool {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            clip.remove_fx(slot_id)
        } else {
            false
        }
    }

    /// Move FX slot to new position in clip's chain
    pub fn move_clip_fx(&self, clip_id: ClipId, slot_id: ClipFxSlotId, new_index: usize) -> bool {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            clip.fx_chain.move_slot(slot_id, new_index)
        } else {
            false
        }
    }

    /// Bypass/enable a specific FX slot
    pub fn set_clip_fx_bypass(&self, clip_id: ClipId, slot_id: ClipFxSlotId, bypass: bool) -> bool {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            if let Some(slot) = clip.fx_chain.get_slot_mut(slot_id) {
                slot.bypass = bypass;
                return true;
            }
        }
        false
    }

    /// Bypass/enable entire clip FX chain
    pub fn set_clip_fx_chain_bypass(&self, clip_id: ClipId, bypass: bool) -> bool {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
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
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            if let Some(slot) = clip.fx_chain.get_slot_mut(slot_id) {
                f(slot);
                return true;
            }
        }
        false
    }

    /// Get clip's FX chain
    pub fn get_clip_fx_chain(&self, clip_id: ClipId) -> Option<ClipFxChain> {
        self.clips.read().get(&clip_id).map(|c| c.fx_chain.clone())
    }

    /// Get specific FX slot from a clip
    pub fn get_clip_fx_slot(&self, clip_id: ClipId, slot_id: ClipFxSlotId) -> Option<ClipFxSlot> {
        self.clips.read()
            .get(&clip_id)
            .and_then(|c| c.fx_chain.get_slot(slot_id).cloned())
    }

    /// Get all clips that have active FX processing
    pub fn get_clips_with_fx(&self) -> Vec<Clip> {
        self.clips.read()
            .values()
            .filter(|c| c.has_fx())
            .cloned()
            .collect()
    }

    /// Clear all FX from a clip
    pub fn clear_clip_fx(&self, clip_id: ClipId) -> bool {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            clip.fx_chain.clear();
            true
        } else {
            false
        }
    }

    /// Copy FX chain from one clip to another
    pub fn copy_clip_fx(&self, source_clip_id: ClipId, target_clip_id: ClipId) -> bool {
        let source_chain = {
            let clips = self.clips.read();
            clips.get(&source_clip_id).map(|c| c.fx_chain.clone())
        };

        if let Some(chain) = source_chain {
            let mut clips = self.clips.write();
            if let Some(target_clip) = clips.get_mut(&target_clip_id) {
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
        }
        false
    }

    /// Set clip FX chain input gain
    pub fn set_clip_fx_input_gain(&self, clip_id: ClipId, gain_db: f64) -> bool {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            clip.fx_chain.input_gain_db = gain_db.clamp(-96.0, 12.0);
            true
        } else {
            false
        }
    }

    /// Set clip FX chain output gain
    pub fn set_clip_fx_output_gain(&self, clip_id: ClipId, gain_db: f64) -> bool {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
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

        let mut xfade = Crossfade::new(
            clip_a.track_id,
            clip_a_id,
            clip_b_id,
            start_time,
            duration,
        );
        xfade.shape = shape;

        let id = xfade.id;
        self.crossfades.write().insert(id, xfade);

        Some(id)
    }

    /// Get all crossfades for a track
    pub fn get_crossfades_for_track(&self, track_id: TrackId) -> Vec<Crossfade> {
        self.crossfades.read()
            .values()
            .filter(|x| x.track_id == track_id)
            .cloned()
            .collect()
    }

    /// Get crossfade by ID
    pub fn get_crossfade(&self, xfade_id: CrossfadeId) -> Option<Crossfade> {
        self.crossfades.read().get(&xfade_id).cloned()
    }

    /// Find crossfade at given time on a track
    pub fn get_crossfade_at_time(&self, track_id: TrackId, time: f64) -> Option<Crossfade> {
        self.crossfades.read()
            .values()
            .find(|x| x.track_id == track_id && x.contains_time(time))
            .cloned()
    }

    /// Update crossfade duration and curve (symmetric)
    pub fn update_crossfade(&self, xfade_id: CrossfadeId, duration: f64, curve: CrossfadeCurve) {
        if let Some(xfade) = self.crossfades.write().get_mut(&xfade_id) {
            xfade.duration = duration;
            xfade.shape = CrossfadeShape::Symmetric(curve.clone());
            xfade.curve = curve;
        }
    }

    /// Update crossfade with full shape control
    pub fn update_crossfade_shape(&self, xfade_id: CrossfadeId, duration: f64, shape: CrossfadeShape) {
        if let Some(xfade) = self.crossfades.write().get_mut(&xfade_id) {
            xfade.duration = duration;
            xfade.shape = shape;
        }
    }

    /// Delete crossfade
    pub fn delete_crossfade(&self, xfade_id: CrossfadeId) {
        self.crossfades.write().remove(&xfade_id);
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
        self.tracks.write().clear();
        self.clips.write().clear();
        self.crossfades.write().clear();
        self.markers.write().clear();
        self.track_order.write().clear();
        *self.loop_region.write() = LoopRegion::default();
    }

    /// Get total project duration (end of last clip)
    pub fn get_duration(&self) -> f64 {
        self.clips.read()
            .values()
            .map(|c| c.end_time())
            .fold(0.0, f64::max)
    }

    /// Get track count
    pub fn track_count(&self) -> usize {
        self.tracks.read().len()
    }

    /// Get clip count
    pub fn clip_count(&self) -> usize {
        self.clips.read().len()
    }
}

impl Default for TrackManager {
    fn default() -> Self {
        Self::new()
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
            assert!(val_start >= 0.0 && val_start <= 0.01,
                "{:?} start: {}", curve, val_start);

            // At end (t=1), fade-in should be 1
            let val_end = curve.evaluate(1.0);
            assert!(val_end >= 0.99 && val_end <= 1.0,
                "{:?} end: {}", curve, val_end);

            // At midpoint, value should be between 0 and 1
            let val_mid = curve.evaluate(0.5);
            assert!(val_mid > 0.0 && val_mid < 1.0,
                "{:?} mid: {}", curve, val_mid);
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
        assert!((sum_of_squares - 1.0).abs() < 0.01,
            "Equal power sum of squares: {}", sum_of_squares);
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
            fade_out: CrossfadeCurve::Exponential,  // Slow start
            fade_in: CrossfadeCurve::Logarithmic,   // Fast start
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
            (0.25, 0.5),  // Fast initial rise
            (0.75, 0.5),  // Plateau
            (1.0, 1.0),   // Final rise
        ];
        let curve = CrossfadeCurve::Custom(points);

        // Test interpolation
        assert!((curve.evaluate(0.0) - 0.0).abs() < 0.01);
        assert!((curve.evaluate(0.25) - 0.5).abs() < 0.01);
        assert!((curve.evaluate(0.5) - 0.5).abs() < 0.01);  // Should be on plateau
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
        let xfade_id = manager.create_crossfade(
            clip_a, clip_b, 0.5, CrossfadeCurve::EqualPower
        ).unwrap();

        let xfade = manager.get_crossfade(xfade_id).unwrap();
        assert_eq!(xfade.duration, 0.5);
        assert!(matches!(xfade.shape, CrossfadeShape::Symmetric(CrossfadeCurve::EqualPower)));
    }

    #[test]
    fn test_asymmetric_crossfade_creation() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);

        let clip_a = manager.create_clip(track, "Clip A", "a.wav", 0.0, 4.0, 4.0);
        let clip_b = manager.create_clip(track, "Clip B", "b.wav", 3.5, 4.0, 4.0);

        // Create asymmetric crossfade
        let xfade_id = manager.create_asymmetric_crossfade(
            clip_a, clip_b, 0.5,
            CrossfadeCurve::Exponential,
            CrossfadeCurve::Logarithmic,
        ).unwrap();

        let xfade = manager.get_crossfade(xfade_id).unwrap();
        assert!(matches!(xfade.shape, CrossfadeShape::Asymmetric { .. }));
    }

    #[test]
    fn test_crossfade_gains_at_time() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);

        let clip_a = manager.create_clip(track, "A", "a.wav", 0.0, 4.0, 4.0);
        let clip_b = manager.create_clip(track, "B", "b.wav", 3.5, 4.0, 4.0);

        let xfade_id = manager.create_crossfade(
            clip_a, clip_b, 1.0, CrossfadeCurve::Linear
        ).unwrap();

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

        let slot = ClipFxSlot::new(ClipFxType::Saturation { drive: 0.5, mix: 1.0 });
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
        let slot1 = ClipFxSlot::new(ClipFxType::Gain { db: 0.0, pan: 0.0 })
            .with_name("Gain 1");
        let slot2 = ClipFxSlot::new(ClipFxType::Compressor {
            ratio: 4.0,
            threshold_db: -20.0,
            attack_ms: 10.0,
            release_ms: 100.0,
        }).with_name("Compressor");
        let slot3 = ClipFxSlot::new(ClipFxType::Limiter { ceiling_db: -0.3 })
            .with_name("Limiter");

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
            let slot = ClipFxSlot::new(ClipFxType::Gain { db: i as f64, pan: 0.0 });
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
            input_gain_db: -6.0,   // -6dB = 0.5
            output_gain_db: 6.0,   // +6dB = ~2.0
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
        let slot_id = manager.add_clip_fx(clip_id, ClipFxType::Gain { db: 3.0, pan: -0.5 })
            .unwrap();

        // Verify FX added
        let clip = manager.get_clip(clip_id).unwrap();
        assert!(clip.has_fx());
        assert_eq!(clip.fx_chain.len(), 1);

        // Get slot
        let slot = manager.get_clip_fx_slot(clip_id, slot_id).unwrap();
        assert!(matches!(slot.fx_type, ClipFxType::Gain { db, pan } if (db - 3.0).abs() < 0.01 && (pan - (-0.5)).abs() < 0.01));

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
        manager.add_clip_fx(clip1, ClipFxType::Compressor {
            ratio: 4.0,
            threshold_db: -18.0,
            attack_ms: 5.0,
            release_ms: 50.0,
        });
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
        let slot = ClipFxSlot::new(ClipFxType::Saturation { drive: 0.7, mix: 0.8 })
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
            ClipFxType::PitchShift { semitones: 12.0, cents: 0.0 },
            ClipFxType::TimeStretch { ratio: 1.0 },
            ClipFxType::Saturation { drive: 0.5, mix: 1.0 },
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
}

//! Clip/Region System for Timeline
//!
//! Professional audio/MIDI clip management:
//! - Audio clips with non-destructive editing
//! - MIDI clips with note/CC data
//! - Clip pooling and references
//! - Time stretching and pitch shifting
//! - Crossfades (auto and manual)
//! - Clip colors and grouping
//! - Slip editing, trim, split
//!
//! ## Cubase-style features
//! - Audio events reference audio clips (pool)
//! - Multiple events can reference same clip
//! - Non-destructive fade and gain per event
//! - Clip-based and event-based editing

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

// ═══════════════════════════════════════════════════════════════════════════════
// CLIP IDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Unique clip ID generator
static NEXT_CLIP_ID: AtomicU64 = AtomicU64::new(1);
static NEXT_EVENT_ID: AtomicU64 = AtomicU64::new(1);

/// Clip ID (pool reference)
pub type ClipId = u64;

/// Event ID (timeline item)
pub type EventId = u64;

fn new_clip_id() -> ClipId {
    NEXT_CLIP_ID.fetch_add(1, Ordering::Relaxed)
}

fn new_event_id() -> EventId {
    NEXT_EVENT_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO CLIP (POOL ITEM)
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio clip in the pool
///
/// This is the source audio data reference. Multiple events can
/// reference the same clip (like Cubase's audio pool).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioClip {
    /// Unique clip ID
    pub id: ClipId,
    /// Display name
    pub name: String,
    /// Source file path (relative to project)
    pub file_path: String,
    /// Sample rate of source file
    pub sample_rate: u32,
    /// Total length in samples
    pub length_samples: u64,
    /// Number of channels
    pub channels: u8,
    /// Bit depth
    pub bit_depth: u8,
    /// Peak waveform data (for display)
    pub waveform_peaks: Option<WaveformData>,
    /// Musical mode (tempo-synced stretching)
    pub musical_mode: bool,
    /// Original tempo (for musical mode)
    pub original_tempo: Option<f64>,
    /// Root note (for pitch detection)
    pub root_note: Option<u8>,
    /// Clip color
    pub color: ClipColor,
    /// Usage count (how many events reference this)
    pub usage_count: u32,
}

impl AudioClip {
    pub fn new(
        name: &str,
        file_path: &str,
        sample_rate: u32,
        length_samples: u64,
        channels: u8,
    ) -> Self {
        Self {
            id: new_clip_id(),
            name: name.to_string(),
            file_path: file_path.to_string(),
            sample_rate,
            length_samples,
            channels,
            bit_depth: 24,
            waveform_peaks: None,
            musical_mode: false,
            original_tempo: None,
            root_note: None,
            color: ClipColor::default(),
            usage_count: 0,
        }
    }

    /// Duration in seconds
    pub fn duration_secs(&self) -> f64 {
        self.length_samples as f64 / self.sample_rate as f64
    }

    /// Duration in samples at given sample rate
    pub fn duration_at_rate(&self, target_rate: u32) -> u64 {
        (self.length_samples as f64 * target_rate as f64 / self.sample_rate as f64) as u64
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI CLIP
// ═══════════════════════════════════════════════════════════════════════════════

/// MIDI clip containing note and CC data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MidiClip {
    /// Unique clip ID
    pub id: ClipId,
    /// Display name
    pub name: String,
    /// MIDI notes
    pub notes: Vec<MidiNote>,
    /// Control change events
    pub control_changes: Vec<MidiCC>,
    /// Pitch bend events
    pub pitch_bends: Vec<MidiPitchBend>,
    /// Program changes
    pub program_changes: Vec<MidiProgramChange>,
    /// Length in ticks (PPQ-based)
    pub length_ticks: u64,
    /// Color
    pub color: ClipColor,
    /// Usage count
    pub usage_count: u32,
}

impl MidiClip {
    pub fn new(name: &str) -> Self {
        Self {
            id: new_clip_id(),
            name: name.to_string(),
            notes: Vec::new(),
            control_changes: Vec::new(),
            pitch_bends: Vec::new(),
            program_changes: Vec::new(),
            length_ticks: 0,
            color: ClipColor::default(),
            usage_count: 0,
        }
    }

    /// Add a note
    pub fn add_note(&mut self, note: MidiNote) {
        self.notes.push(note);
        // Update length if note extends beyond
        let note_end = note.start_tick + note.duration_ticks;
        if note_end > self.length_ticks {
            self.length_ticks = note_end;
        }
    }

    /// Get notes in range (for playback)
    pub fn notes_in_range(&self, start_tick: u64, end_tick: u64) -> Vec<&MidiNote> {
        self.notes
            .iter()
            .filter(|n| {
                let note_end = n.start_tick + n.duration_ticks;
                n.start_tick < end_tick && note_end > start_tick
            })
            .collect()
    }

    /// Quantize notes to grid
    pub fn quantize(&mut self, grid_ticks: u64, strength: f64) {
        for note in &mut self.notes {
            let nearest_grid =
                (note.start_tick as f64 / grid_ticks as f64).round() as u64 * grid_ticks;
            let diff = nearest_grid as i64 - note.start_tick as i64;
            note.start_tick = (note.start_tick as i64 + (diff as f64 * strength) as i64) as u64;
        }
    }

    /// Transpose all notes
    pub fn transpose(&mut self, semitones: i8) {
        for note in &mut self.notes {
            let new_pitch = note.pitch as i16 + semitones as i16;
            note.pitch = new_pitch.clamp(0, 127) as u8;
        }
    }
}

/// MIDI note event
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiNote {
    /// Start position in ticks
    pub start_tick: u64,
    /// Duration in ticks
    pub duration_ticks: u64,
    /// MIDI note number (0-127)
    pub pitch: u8,
    /// Velocity (0-127)
    pub velocity: u8,
    /// Release velocity
    pub release_velocity: u8,
    /// MIDI channel (0-15)
    pub channel: u8,
    /// Muted
    pub muted: bool,
}

impl MidiNote {
    pub fn new(start_tick: u64, duration_ticks: u64, pitch: u8, velocity: u8) -> Self {
        Self {
            start_tick,
            duration_ticks,
            pitch,
            velocity,
            release_velocity: 64,
            channel: 0,
            muted: false,
        }
    }
}

/// MIDI CC event
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiCC {
    pub tick: u64,
    pub channel: u8,
    pub controller: u8,
    pub value: u8,
}

/// MIDI pitch bend event
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiPitchBend {
    pub tick: u64,
    pub channel: u8,
    /// Pitch bend value (-8192 to 8191)
    pub value: i16,
}

/// MIDI program change
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiProgramChange {
    pub tick: u64,
    pub channel: u8,
    pub program: u8,
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO EVENT (TIMELINE ITEM)
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio event on timeline
///
/// References an AudioClip from the pool. Multiple events can
/// reference the same clip with different in/out points.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEvent {
    /// Unique event ID
    pub id: EventId,
    /// Referenced clip ID
    pub clip_id: ClipId,
    /// Track ID
    pub track_id: u64,
    /// Display name (defaults to clip name)
    pub name: String,
    /// Position on timeline (samples)
    pub position: u64,
    /// Length on timeline (samples)
    pub length: u64,
    /// Offset into source clip (samples)
    pub clip_offset: u64,
    /// Event gain (dB)
    pub gain_db: f64,
    /// Fade in
    pub fade_in: FadeSettings,
    /// Fade out
    pub fade_out: FadeSettings,
    /// Time stretch ratio (1.0 = no stretch)
    pub stretch_ratio: f64,
    /// Pitch shift (semitones)
    pub pitch_shift: f64,
    /// Reverse playback
    pub reversed: bool,
    /// Muted
    pub muted: bool,
    /// Locked (prevent editing)
    pub locked: bool,
    /// Color override (None = use clip color)
    pub color_override: Option<ClipColor>,
    /// Group ID (for linked editing)
    pub group_id: Option<u64>,
}

impl AudioEvent {
    pub fn new(clip_id: ClipId, track_id: u64, position: u64, length: u64) -> Self {
        Self {
            id: new_event_id(),
            clip_id,
            track_id,
            name: String::new(),
            position,
            length,
            clip_offset: 0,
            gain_db: 0.0,
            fade_in: FadeSettings::default(),
            fade_out: FadeSettings::default(),
            stretch_ratio: 1.0,
            pitch_shift: 0.0,
            reversed: false,
            muted: false,
            locked: false,
            color_override: None,
            group_id: None,
        }
    }

    /// End position on timeline
    pub fn end_position(&self) -> u64 {
        self.position + self.length
    }

    /// Check if position is within event
    pub fn contains(&self, pos: u64) -> bool {
        pos >= self.position && pos < self.end_position()
    }

    /// Check if overlaps with range
    pub fn overlaps(&self, start: u64, end: u64) -> bool {
        self.position < end && self.end_position() > start
    }

    /// Split event at position
    pub fn split(&self, at_position: u64) -> Option<(AudioEvent, AudioEvent)> {
        if at_position <= self.position || at_position >= self.end_position() {
            return None;
        }

        let split_offset = at_position - self.position;

        let mut left = self.clone();
        left.length = split_offset;
        left.fade_out = FadeSettings::default(); // Remove fade out from left

        let mut right = self.clone();
        right.id = new_event_id();
        right.position = at_position;
        right.length = self.length - split_offset;
        right.clip_offset = self.clip_offset + split_offset;
        right.fade_in = FadeSettings::default(); // Remove fade in from right

        Some((left, right))
    }

    /// Trim start (slip edit)
    pub fn trim_start(&mut self, new_position: u64, min_length: u64) {
        if new_position >= self.end_position() - min_length {
            return;
        }

        let delta = new_position as i64 - self.position as i64;
        self.clip_offset = (self.clip_offset as i64 + delta).max(0) as u64;
        self.length = (self.length as i64 - delta).max(min_length as i64) as u64;
        self.position = new_position;
    }

    /// Trim end
    pub fn trim_end(&mut self, new_end: u64, min_length: u64) {
        if new_end <= self.position + min_length {
            return;
        }

        self.length = new_end - self.position;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI EVENT (TIMELINE ITEM)
// ═══════════════════════════════════════════════════════════════════════════════

/// MIDI event on timeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MidiEvent {
    /// Unique event ID
    pub id: EventId,
    /// Referenced clip ID
    pub clip_id: ClipId,
    /// Track ID
    pub track_id: u64,
    /// Display name
    pub name: String,
    /// Position on timeline (ticks)
    pub position_ticks: u64,
    /// Length on timeline (ticks)
    pub length_ticks: u64,
    /// Offset into source clip (ticks)
    pub clip_offset_ticks: u64,
    /// Transpose (semitones)
    pub transpose: i8,
    /// Velocity scale (0.0-2.0)
    pub velocity_scale: f64,
    /// Muted
    pub muted: bool,
    /// Locked
    pub locked: bool,
    /// Color override
    pub color_override: Option<ClipColor>,
    /// Group ID
    pub group_id: Option<u64>,
}

impl MidiEvent {
    pub fn new(clip_id: ClipId, track_id: u64, position_ticks: u64, length_ticks: u64) -> Self {
        Self {
            id: new_event_id(),
            clip_id,
            track_id,
            name: String::new(),
            position_ticks,
            length_ticks,
            clip_offset_ticks: 0,
            transpose: 0,
            velocity_scale: 1.0,
            muted: false,
            locked: false,
            color_override: None,
            group_id: None,
        }
    }

    pub fn end_position(&self) -> u64 {
        self.position_ticks + self.length_ticks
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FADE SETTINGS
// ═══════════════════════════════════════════════════════════════════════════════

/// Fade configuration
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct FadeSettings {
    /// Fade length (samples)
    pub length: u64,
    /// Fade curve type
    pub curve: FadeCurve,
    /// Curve tension (-1.0 to 1.0)
    pub tension: f64,
}

impl Default for FadeSettings {
    fn default() -> Self {
        Self {
            length: 0,
            curve: FadeCurve::Linear,
            tension: 0.0,
        }
    }
}

impl FadeSettings {
    /// Calculate fade gain at position (0.0 to 1.0)
    pub fn gain_at(&self, position_in_fade: u64) -> f64 {
        if self.length == 0 {
            return 1.0;
        }

        let t = (position_in_fade as f64 / self.length as f64).clamp(0.0, 1.0);

        match self.curve {
            FadeCurve::Linear => t,
            FadeCurve::EqualPower => (t * std::f64::consts::FRAC_PI_2).sin(),
            FadeCurve::SCurve => {
                // Sine-based S-curve
                (1.0 - (t * std::f64::consts::PI).cos()) * 0.5
            }
            FadeCurve::Exponential => {
                if self.tension >= 0.0 {
                    t.powf(1.0 + self.tension * 3.0)
                } else {
                    1.0 - (1.0 - t).powf(1.0 - self.tension * 3.0)
                }
            }
            FadeCurve::Logarithmic => {
                // Log curve
                (1.0 + t * 9.0).log10()
            }
        }
    }
}

/// Fade curve types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum FadeCurve {
    #[default]
    Linear,
    EqualPower,
    SCurve,
    Exponential,
    Logarithmic,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CROSSFADE
// ═══════════════════════════════════════════════════════════════════════════════

/// Crossfade between two audio events
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Crossfade {
    /// Left event ID
    pub left_event_id: EventId,
    /// Right event ID
    pub right_event_id: EventId,
    /// Crossfade length (samples)
    pub length: u64,
    /// Crossfade position (center point)
    pub position: u64,
    /// Curve type
    pub curve: CrossfadeCurve,
    /// Asymmetry (-1.0 to 1.0)
    pub asymmetry: f64,
}

impl Crossfade {
    pub fn new(left_id: EventId, right_id: EventId, position: u64, length: u64) -> Self {
        Self {
            left_event_id: left_id,
            right_event_id: right_id,
            length,
            position,
            curve: CrossfadeCurve::EqualPower,
            asymmetry: 0.0,
        }
    }

    /// Get gains for left and right at position
    pub fn gains_at(&self, sample_pos: u64) -> (f64, f64) {
        let start = self.position - self.length / 2;
        let end = self.position + self.length / 2;

        if sample_pos < start {
            return (1.0, 0.0);
        }
        if sample_pos >= end {
            return (0.0, 1.0);
        }

        let t = (sample_pos - start) as f64 / self.length as f64;

        match self.curve {
            CrossfadeCurve::Linear => (1.0 - t, t),
            CrossfadeCurve::EqualPower => {
                let angle = t * std::f64::consts::FRAC_PI_2;
                (angle.cos(), angle.sin())
            }
            CrossfadeCurve::SCurve => {
                let s = (1.0 - (t * std::f64::consts::PI).cos()) * 0.5;
                (1.0 - s, s)
            }
        }
    }
}

/// Crossfade curve types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum CrossfadeCurve {
    Linear,
    #[default]
    EqualPower,
    SCurve,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLIP COLOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Clip/event color
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipColor {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Default for ClipColor {
    fn default() -> Self {
        // Default Cubase-like blue
        Self {
            r: 0x4a,
            g: 0x9e,
            b: 0xff,
        }
    }
}

impl ClipColor {
    pub const fn rgb(r: u8, g: u8, b: u8) -> Self {
        Self { r, g, b }
    }

    pub fn from_u32(color: u32) -> Self {
        Self {
            r: ((color >> 16) & 0xFF) as u8,
            g: ((color >> 8) & 0xFF) as u8,
            b: (color & 0xFF) as u8,
        }
    }

    pub fn to_u32(&self) -> u32 {
        ((self.r as u32) << 16) | ((self.g as u32) << 8) | (self.b as u32)
    }

    // Preset colors (Cubase-style palette)
    pub const RED: Self = Self::rgb(0xff, 0x40, 0x60);
    pub const ORANGE: Self = Self::rgb(0xff, 0x90, 0x40);
    pub const YELLOW: Self = Self::rgb(0xff, 0xff, 0x40);
    pub const GREEN: Self = Self::rgb(0x40, 0xff, 0x90);
    pub const CYAN: Self = Self::rgb(0x40, 0xc8, 0xff);
    pub const BLUE: Self = Self::rgb(0x4a, 0x9e, 0xff);
    pub const PURPLE: Self = Self::rgb(0xa0, 0x60, 0xff);
    pub const PINK: Self = Self::rgb(0xff, 0x60, 0xc0);
    pub const GRAY: Self = Self::rgb(0x80, 0x80, 0x80);
}

// ═══════════════════════════════════════════════════════════════════════════════
// WAVEFORM DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Waveform peak data for display
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaveformData {
    /// Peak data at multiple LOD levels
    pub levels: Vec<WaveformLod>,
    /// Sample rate of source
    pub sample_rate: u32,
    /// Total samples
    pub total_samples: u64,
}

/// Waveform LOD level
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaveformLod {
    /// Samples per peak
    pub samples_per_peak: u32,
    /// Min values (interleaved per channel)
    pub min_peaks: Vec<f32>,
    /// Max values (interleaved per channel)
    pub max_peaks: Vec<f32>,
}

impl WaveformData {
    /// Create waveform data from samples
    pub fn from_samples(samples: &[f32], channels: u8, sample_rate: u32) -> Self {
        let total_samples = samples.len() as u64 / channels as u64;

        // Generate LOD levels: 64, 256, 1024, 4096 samples per peak
        let lod_sizes = [64, 256, 1024, 4096];
        let levels: Vec<WaveformLod> = lod_sizes
            .iter()
            .map(|&spp| Self::generate_lod(samples, channels, spp))
            .collect();

        Self {
            levels,
            sample_rate,
            total_samples,
        }
    }

    fn generate_lod(samples: &[f32], channels: u8, samples_per_peak: u32) -> WaveformLod {
        let num_peaks = samples.len() / (samples_per_peak as usize * channels as usize);
        let mut min_peaks = Vec::with_capacity(num_peaks * channels as usize);
        let mut max_peaks = Vec::with_capacity(num_peaks * channels as usize);

        for peak_idx in 0..num_peaks {
            for ch in 0..channels as usize {
                let start = peak_idx * samples_per_peak as usize * channels as usize + ch;
                let end = start + samples_per_peak as usize * channels as usize;

                let mut min_val = f32::MAX;
                let mut max_val = f32::MIN;

                for i in (start..end.min(samples.len())).step_by(channels as usize) {
                    let sample = samples[i];
                    min_val = min_val.min(sample);
                    max_val = max_val.max(sample);
                }

                min_peaks.push(min_val);
                max_peaks.push(max_val);
            }
        }

        WaveformLod {
            samples_per_peak,
            min_peaks,
            max_peaks,
        }
    }

    /// Get appropriate LOD level for given zoom
    pub fn get_lod(&self, samples_per_pixel: u32) -> Option<&WaveformLod> {
        // Find the LOD level with closest samples_per_peak <= samples_per_pixel
        self.levels
            .iter()
            .filter(|l| l.samples_per_peak <= samples_per_pixel.max(64))
            .last()
            .or_else(|| self.levels.first())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLIP POOL
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio/MIDI clip pool (like Cubase's pool)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ClipPool {
    /// Audio clips
    pub audio_clips: HashMap<ClipId, AudioClip>,
    /// MIDI clips
    pub midi_clips: HashMap<ClipId, MidiClip>,
    /// Folders for organization
    pub folders: Vec<PoolFolder>,
}

/// Pool folder for organization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolFolder {
    pub id: u64,
    pub name: String,
    pub parent_id: Option<u64>,
    pub clip_ids: Vec<ClipId>,
}

impl ClipPool {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add audio clip to pool
    pub fn add_audio_clip(&mut self, clip: AudioClip) -> ClipId {
        let id = clip.id;
        self.audio_clips.insert(id, clip);
        id
    }

    /// Add MIDI clip to pool
    pub fn add_midi_clip(&mut self, clip: MidiClip) -> ClipId {
        let id = clip.id;
        self.midi_clips.insert(id, clip);
        id
    }

    /// Get audio clip by ID
    pub fn get_audio_clip(&self, id: ClipId) -> Option<&AudioClip> {
        self.audio_clips.get(&id)
    }

    /// Get mutable audio clip
    pub fn get_audio_clip_mut(&mut self, id: ClipId) -> Option<&mut AudioClip> {
        self.audio_clips.get_mut(&id)
    }

    /// Get MIDI clip by ID
    pub fn get_midi_clip(&self, id: ClipId) -> Option<&MidiClip> {
        self.midi_clips.get(&id)
    }

    /// Get mutable MIDI clip
    pub fn get_midi_clip_mut(&mut self, id: ClipId) -> Option<&mut MidiClip> {
        self.midi_clips.get_mut(&id)
    }

    /// Remove unused clips (usage_count == 0)
    pub fn remove_unused(&mut self) -> Vec<ClipId> {
        let unused_audio: Vec<ClipId> = self
            .audio_clips
            .iter()
            .filter(|(_, c)| c.usage_count == 0)
            .map(|(&id, _)| id)
            .collect();

        let unused_midi: Vec<ClipId> = self
            .midi_clips
            .iter()
            .filter(|(_, c)| c.usage_count == 0)
            .map(|(&id, _)| id)
            .collect();

        for id in &unused_audio {
            self.audio_clips.remove(id);
        }

        for id in &unused_midi {
            self.midi_clips.remove(id);
        }

        unused_audio.into_iter().chain(unused_midi).collect()
    }

    /// Find clips by name
    pub fn find_by_name(&self, query: &str) -> Vec<ClipId> {
        let query = query.to_lowercase();

        let audio_matches = self
            .audio_clips
            .iter()
            .filter(|(_, c)| c.name.to_lowercase().contains(&query))
            .map(|(&id, _)| id);

        let midi_matches = self
            .midi_clips
            .iter()
            .filter(|(_, c)| c.name.to_lowercase().contains(&query))
            .map(|(&id, _)| id);

        audio_matches.chain(midi_matches).collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages all events on timeline
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EventManager {
    /// Audio events
    pub audio_events: HashMap<EventId, AudioEvent>,
    /// MIDI events
    pub midi_events: HashMap<EventId, MidiEvent>,
    /// Crossfades
    pub crossfades: Vec<Crossfade>,
    /// Event groups
    pub groups: HashMap<u64, EventGroup>,
    /// Next group ID
    next_group_id: u64,
}

/// Event group for linked editing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventGroup {
    pub id: u64,
    pub name: String,
    pub event_ids: Vec<EventId>,
}

impl EventManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add audio event
    pub fn add_audio_event(&mut self, event: AudioEvent) -> EventId {
        let id = event.id;
        self.audio_events.insert(id, event);
        id
    }

    /// Add MIDI event
    pub fn add_midi_event(&mut self, event: MidiEvent) -> EventId {
        let id = event.id;
        self.midi_events.insert(id, event);
        id
    }

    /// Remove audio event
    pub fn remove_audio_event(&mut self, id: EventId) -> Option<AudioEvent> {
        // Also remove any crossfades
        self.crossfades
            .retain(|xf| xf.left_event_id != id && xf.right_event_id != id);
        self.audio_events.remove(&id)
    }

    /// Remove MIDI event
    pub fn remove_midi_event(&mut self, id: EventId) -> Option<MidiEvent> {
        self.midi_events.remove(&id)
    }

    /// Get audio events on track
    pub fn audio_events_on_track(&self, track_id: u64) -> Vec<&AudioEvent> {
        self.audio_events
            .values()
            .filter(|e| e.track_id == track_id)
            .collect()
    }

    /// Get audio events in range on track
    pub fn audio_events_in_range(&self, track_id: u64, start: u64, end: u64) -> Vec<&AudioEvent> {
        self.audio_events
            .values()
            .filter(|e| e.track_id == track_id && e.overlaps(start, end))
            .collect()
    }

    /// Get MIDI events on track
    pub fn midi_events_on_track(&self, track_id: u64) -> Vec<&MidiEvent> {
        self.midi_events
            .values()
            .filter(|e| e.track_id == track_id)
            .collect()
    }

    /// Find overlapping events (for crossfade detection)
    pub fn find_overlapping_audio(&self, track_id: u64) -> Vec<(EventId, EventId)> {
        let events: Vec<_> = self.audio_events_on_track(track_id);
        let mut overlaps = Vec::new();

        for i in 0..events.len() {
            for j in (i + 1)..events.len() {
                if events[i].overlaps(events[j].position, events[j].end_position()) {
                    overlaps.push((events[i].id, events[j].id));
                }
            }
        }

        overlaps
    }

    /// Auto-create crossfade for overlapping events
    pub fn create_auto_crossfade(
        &mut self,
        left_id: EventId,
        right_id: EventId,
    ) -> Option<&Crossfade> {
        let left = self.audio_events.get(&left_id)?;
        let right = self.audio_events.get(&right_id)?;

        // Check if they actually overlap
        if left.end_position() <= right.position || right.end_position() <= left.position {
            return None;
        }

        // Calculate overlap
        let overlap_start = left.position.max(right.position);
        let overlap_end = left.end_position().min(right.end_position());
        let overlap_length = overlap_end.saturating_sub(overlap_start);

        if overlap_length == 0 {
            return None;
        }

        let crossfade = Crossfade::new(
            left_id,
            right_id,
            overlap_start + overlap_length / 2,
            overlap_length,
        );

        self.crossfades.push(crossfade);
        self.crossfades.last()
    }

    /// Create event group
    pub fn create_group(&mut self, name: &str, event_ids: Vec<EventId>) -> u64 {
        let id = self.next_group_id;
        self.next_group_id += 1;

        // Update events
        for &eid in &event_ids {
            if let Some(e) = self.audio_events.get_mut(&eid) {
                e.group_id = Some(id);
            }
            if let Some(e) = self.midi_events.get_mut(&eid) {
                e.group_id = Some(id);
            }
        }

        self.groups.insert(
            id,
            EventGroup {
                id,
                name: name.to_string(),
                event_ids,
            },
        );

        id
    }

    /// Dissolve group
    pub fn dissolve_group(&mut self, group_id: u64) {
        if let Some(group) = self.groups.remove(&group_id) {
            for eid in group.event_ids {
                if let Some(e) = self.audio_events.get_mut(&eid) {
                    e.group_id = None;
                }
                if let Some(e) = self.midi_events.get_mut(&eid) {
                    e.group_id = None;
                }
            }
        }
    }

    /// Move events (respects groups)
    pub fn move_events(&mut self, event_ids: &[EventId], delta_samples: i64) {
        let mut all_ids: Vec<EventId> = event_ids.to_vec();

        // Add grouped events
        for &id in event_ids {
            if let Some(e) = self.audio_events.get(&id) {
                if let Some(group_id) = e.group_id {
                    if let Some(group) = self.groups.get(&group_id) {
                        for &gid in &group.event_ids {
                            if !all_ids.contains(&gid) {
                                all_ids.push(gid);
                            }
                        }
                    }
                }
            }
        }

        // Move all
        for id in all_ids {
            if let Some(e) = self.audio_events.get_mut(&id) {
                if !e.locked {
                    e.position = (e.position as i64 + delta_samples).max(0) as u64;
                }
            }
            if let Some(e) = self.midi_events.get_mut(&id) {
                if !e.locked {
                    e.position_ticks = (e.position_ticks as i64 + delta_samples).max(0) as u64;
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audio_clip_creation() {
        let clip = AudioClip::new("Test.wav", "audio/Test.wav", 48000, 480000, 2);
        assert_eq!(clip.duration_secs(), 10.0);
    }

    #[test]
    fn test_audio_event_split() {
        let mut pool = ClipPool::new();
        let clip = AudioClip::new("Test.wav", "audio/Test.wav", 48000, 480000, 2);
        let clip_id = pool.add_audio_clip(clip);

        let event = AudioEvent::new(clip_id, 1, 0, 480000);
        let (left, right) = event.split(240000).unwrap();

        assert_eq!(left.length, 240000);
        assert_eq!(right.position, 240000);
        assert_eq!(right.length, 240000);
        assert_eq!(right.clip_offset, 240000);
    }

    #[test]
    fn test_fade_curves() {
        let fade = FadeSettings {
            length: 100,
            curve: FadeCurve::Linear,
            tension: 0.0,
        };

        assert!((fade.gain_at(0) - 0.0).abs() < 0.001);
        assert!((fade.gain_at(50) - 0.5).abs() < 0.001);
        assert!((fade.gain_at(100) - 1.0).abs() < 0.001);

        let eq_power = FadeSettings {
            length: 100,
            curve: FadeCurve::EqualPower,
            tension: 0.0,
        };

        // Equal power should be ~0.707 at midpoint
        assert!((eq_power.gain_at(50) - 0.707).abs() < 0.01);
    }

    #[test]
    fn test_midi_clip_quantize() {
        let mut clip = MidiClip::new("Test");
        clip.add_note(MidiNote::new(95, 100, 60, 100)); // Slightly off grid
        clip.add_note(MidiNote::new(200, 100, 62, 100)); // On grid

        clip.quantize(100, 1.0); // Full quantize to 100-tick grid

        assert_eq!(clip.notes[0].start_tick, 100);
        assert_eq!(clip.notes[1].start_tick, 200);
    }

    #[test]
    fn test_crossfade() {
        let xf = Crossfade::new(1, 2, 1000, 200);

        let (l, r) = xf.gains_at(900); // Start
        assert!((l - 1.0).abs() < 0.001);
        assert!((r - 0.0).abs() < 0.001);

        let (l, r) = xf.gains_at(1100); // End
        assert!((l - 0.0).abs() < 0.001);
        assert!((r - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_event_overlap_detection() {
        let mut manager = EventManager::new();

        let event1 = AudioEvent::new(1, 1, 0, 1000);
        let event2 = AudioEvent::new(1, 1, 800, 1000);
        manager.add_audio_event(event1);
        manager.add_audio_event(event2);

        let overlaps = manager.find_overlapping_audio(1);
        assert_eq!(overlaps.len(), 1);
    }
}

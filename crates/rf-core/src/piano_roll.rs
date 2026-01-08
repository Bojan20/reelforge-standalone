//! Piano Roll Editor State and Operations
//!
//! Professional MIDI piano roll editor with:
//! - Multi-note selection and editing
//! - Snap-to-grid quantization
//! - Velocity editing
//! - Note stretching/moving
//! - Copy/paste operations
//! - Undo/redo support

use crate::midi::{MidiChannel, MidiClip, MidiNote, NoteName, NoteNumber, Velocity};
use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Ticks per quarter note (PPQ)
pub const TICKS_PER_BEAT: u64 = 960;

/// Grid divisions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GridDivision {
    /// 1 bar (4 beats in 4/4)
    Bar,
    /// Half note
    Half,
    /// Quarter note (beat)
    Quarter,
    /// Eighth note
    Eighth,
    /// Sixteenth note
    Sixteenth,
    /// Thirty-second note
    ThirtySecond,
    /// Eighth triplet
    EighthTriplet,
    /// Sixteenth triplet
    SixteenthTriplet,
}

impl GridDivision {
    /// Get ticks for this grid division
    pub fn ticks(&self, time_sig_numerator: u8, time_sig_denominator: u8) -> u64 {
        let beat_ticks = TICKS_PER_BEAT;
        let bar_ticks = beat_ticks * (time_sig_numerator as u64 * 4 / time_sig_denominator as u64);

        match self {
            GridDivision::Bar => bar_ticks,
            GridDivision::Half => beat_ticks * 2,
            GridDivision::Quarter => beat_ticks,
            GridDivision::Eighth => beat_ticks / 2,
            GridDivision::Sixteenth => beat_ticks / 4,
            GridDivision::ThirtySecond => beat_ticks / 8,
            GridDivision::EighthTriplet => beat_ticks / 3,
            GridDivision::SixteenthTriplet => beat_ticks / 6,
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            GridDivision::Bar => "1 Bar",
            GridDivision::Half => "1/2",
            GridDivision::Quarter => "1/4",
            GridDivision::Eighth => "1/8",
            GridDivision::Sixteenth => "1/16",
            GridDivision::ThirtySecond => "1/32",
            GridDivision::EighthTriplet => "1/8T",
            GridDivision::SixteenthTriplet => "1/16T",
        }
    }
}

impl Default for GridDivision {
    fn default() -> Self {
        GridDivision::Sixteenth
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT TOOL
// ═══════════════════════════════════════════════════════════════════════════════

/// Piano roll editing tool
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PianoRollTool {
    /// Select and move notes
    Select,
    /// Draw new notes
    Draw,
    /// Erase notes
    Erase,
    /// Edit velocity
    Velocity,
    /// Slice notes at position
    Slice,
    /// Glue notes together
    Glue,
    /// Mute/unmute notes
    Mute,
}

impl Default for PianoRollTool {
    fn default() -> Self {
        PianoRollTool::Select
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOTE SELECTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Extended note with editing metadata
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct PianoRollNote {
    /// Core note data
    pub note: MidiNote,
    /// Unique ID for this note instance
    pub id: u64,
    /// Is this note selected
    pub selected: bool,
    /// Is this note muted
    pub muted: bool,
    /// Color index (0-15 for different colors)
    pub color: u8,
}

impl PianoRollNote {
    pub fn new(note: MidiNote, id: u64) -> Self {
        Self {
            note,
            id,
            selected: false,
            muted: false,
            color: 0,
        }
    }

    pub fn with_color(mut self, color: u8) -> Self {
        self.color = color;
        self
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT OPERATION (for undo/redo)
// ═══════════════════════════════════════════════════════════════════════════════

/// A single edit operation that can be undone
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PianoRollEdit {
    /// Add a note
    AddNote { note: PianoRollNote },
    /// Remove a note
    RemoveNote { note: PianoRollNote },
    /// Move note(s)
    MoveNotes {
        note_ids: Vec<u64>,
        delta_tick: i64,
        delta_note: i8,
    },
    /// Resize note(s)
    ResizeNotes {
        note_ids: Vec<u64>,
        delta_duration: i64,
        from_start: bool,
    },
    /// Change velocity
    ChangeVelocity {
        note_ids: Vec<u64>,
        old_velocities: Vec<Velocity>,
        new_velocities: Vec<Velocity>,
    },
    /// Quantize notes
    Quantize {
        note_ids: Vec<u64>,
        old_positions: Vec<u64>,
        new_positions: Vec<u64>,
    },
    /// Batch operation (multiple edits as one undo step)
    Batch { edits: Vec<PianoRollEdit> },
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIEW STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// View/zoom state for the piano roll
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PianoRollView {
    /// Horizontal zoom (pixels per beat)
    pub pixels_per_beat: f64,
    /// Vertical zoom (pixels per note row)
    pub pixels_per_note: f64,
    /// Scroll position (tick)
    pub scroll_x_tick: u64,
    /// Scroll position (note number, 0=lowest visible)
    pub scroll_y_note: u8,
    /// Visible note range (lowest)
    pub visible_note_low: u8,
    /// Visible note range (highest)
    pub visible_note_high: u8,
    /// Show velocity lane
    pub show_velocity: bool,
    /// Show piano keys
    pub show_keys: bool,
    /// Velocity lane height (pixels)
    pub velocity_lane_height: f64,
    /// Piano keys width (pixels)
    pub keys_width: f64,
}

impl Default for PianoRollView {
    fn default() -> Self {
        Self {
            pixels_per_beat: 100.0,
            pixels_per_note: 16.0,
            scroll_x_tick: 0,
            scroll_y_note: 36,      // C2
            visible_note_low: 21,   // A0
            visible_note_high: 108, // C8
            show_velocity: true,
            show_keys: true,
            velocity_lane_height: 60.0,
            keys_width: 80.0,
        }
    }
}

impl PianoRollView {
    /// Convert tick to x pixel position
    pub fn tick_to_x(&self, tick: u64) -> f64 {
        let beats = (tick as f64) / (TICKS_PER_BEAT as f64);
        beats * self.pixels_per_beat
            - (self.scroll_x_tick as f64 / TICKS_PER_BEAT as f64) * self.pixels_per_beat
    }

    /// Convert x pixel to tick
    pub fn x_to_tick(&self, x: f64) -> u64 {
        let beats = x / self.pixels_per_beat + (self.scroll_x_tick as f64 / TICKS_PER_BEAT as f64);
        (beats * TICKS_PER_BEAT as f64).max(0.0) as u64
    }

    /// Convert note number to y pixel position
    pub fn note_to_y(&self, note: u8, _total_height: f64) -> f64 {
        let note_offset = (self.visible_note_high as f64) - (note as f64);
        note_offset * self.pixels_per_note
    }

    /// Convert y pixel to note number
    pub fn y_to_note(&self, y: f64) -> u8 {
        let note_offset = y / self.pixels_per_note;
        (self.visible_note_high as f64 - note_offset).clamp(0.0, 127.0) as u8
    }

    /// Zoom in horizontally
    pub fn zoom_in_h(&mut self) {
        self.pixels_per_beat = (self.pixels_per_beat * 1.25).min(500.0);
    }

    /// Zoom out horizontally
    pub fn zoom_out_h(&mut self) {
        self.pixels_per_beat = (self.pixels_per_beat / 1.25).max(20.0);
    }

    /// Zoom in vertically
    pub fn zoom_in_v(&mut self) {
        self.pixels_per_note = (self.pixels_per_note * 1.25).min(40.0);
    }

    /// Zoom out vertically
    pub fn zoom_out_v(&mut self) {
        self.pixels_per_note = (self.pixels_per_note / 1.25).max(6.0);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIANO ROLL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete piano roll editor state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PianoRollState {
    /// The MIDI clip being edited
    pub clip_id: u32,
    /// Notes with editing metadata
    pub notes: Vec<PianoRollNote>,
    /// Current selection
    pub selected_ids: Vec<u64>,
    /// View state
    pub view: PianoRollView,
    /// Current tool
    pub tool: PianoRollTool,
    /// Grid division
    pub grid: GridDivision,
    /// Snap to grid enabled
    pub snap_enabled: bool,
    /// Time signature numerator
    pub time_sig_num: u8,
    /// Time signature denominator
    pub time_sig_den: u8,
    /// Clip length in ticks
    pub clip_length: u64,
    /// Default note length (in grid divisions)
    pub default_note_length: u64,
    /// Default velocity
    pub default_velocity: Velocity,
    /// Default channel
    pub default_channel: MidiChannel,
    /// Undo stack
    undo_stack: Vec<PianoRollEdit>,
    /// Redo stack
    redo_stack: Vec<PianoRollEdit>,
    /// Next note ID
    next_id: u64,
    /// Clipboard
    clipboard: Vec<PianoRollNote>,
}

impl Default for PianoRollState {
    fn default() -> Self {
        Self {
            clip_id: 0,
            notes: Vec::new(),
            selected_ids: Vec::new(),
            view: PianoRollView::default(),
            tool: PianoRollTool::default(),
            grid: GridDivision::default(),
            snap_enabled: true,
            time_sig_num: 4,
            time_sig_den: 4,
            clip_length: TICKS_PER_BEAT * 4,         // 1 bar
            default_note_length: TICKS_PER_BEAT / 4, // 16th note
            default_velocity: 100,
            default_channel: 0,
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            next_id: 1,
            clipboard: Vec::new(),
        }
    }
}

impl PianoRollState {
    /// Create new piano roll state for a clip
    pub fn new(clip_id: u32) -> Self {
        Self {
            clip_id,
            ..Default::default()
        }
    }

    /// Load from MIDI clip
    pub fn from_clip(clip: &MidiClip, clip_id: u32) -> Self {
        let mut state = Self::new(clip_id);
        state.clip_length = clip.length_ticks;

        for note in &clip.notes {
            let pr_note = PianoRollNote::new(*note, state.next_id);
            state.next_id += 1;
            state.notes.push(pr_note);
        }

        state
    }

    /// Export to MIDI clip
    pub fn to_clip(&self, name: &str) -> MidiClip {
        let mut clip = MidiClip::new(&format!("clip_{}", self.clip_id), name);
        clip.length_ticks = self.clip_length;

        for pr_note in &self.notes {
            if !pr_note.muted {
                clip.notes.push(pr_note.note);
            }
        }

        clip.notes.sort_by_key(|n| n.start_tick);
        clip
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Note Operations
    // ─────────────────────────────────────────────────────────────────────────────

    /// Snap tick to grid
    pub fn snap_to_grid(&self, tick: u64) -> u64 {
        if !self.snap_enabled {
            return tick;
        }

        let grid_ticks = self.grid.ticks(self.time_sig_num, self.time_sig_den);
        ((tick + grid_ticks / 2) / grid_ticks) * grid_ticks
    }

    /// Add a new note
    pub fn add_note(
        &mut self,
        note: NoteNumber,
        start_tick: u64,
        duration: u64,
        velocity: Velocity,
    ) -> u64 {
        let start = if self.snap_enabled {
            self.snap_to_grid(start_tick)
        } else {
            start_tick
        };

        let midi_note = MidiNote {
            start_tick: start,
            duration_ticks: duration,
            note,
            velocity,
            release_velocity: 64,
            channel: self.default_channel,
        };

        let id = self.next_id;
        self.next_id += 1;

        let pr_note = PianoRollNote::new(midi_note, id);

        // Record edit for undo
        self.push_edit(PianoRollEdit::AddNote { note: pr_note });

        self.notes.push(pr_note);
        self.notes.sort_by_key(|n| n.note.start_tick);

        id
    }

    /// Remove note by ID
    pub fn remove_note(&mut self, id: u64) -> Option<PianoRollNote> {
        if let Some(pos) = self.notes.iter().position(|n| n.id == id) {
            let note = self.notes.remove(pos);
            self.selected_ids.retain(|&sid| sid != id);

            // Record edit for undo
            self.push_edit(PianoRollEdit::RemoveNote { note });

            Some(note)
        } else {
            None
        }
    }

    /// Remove selected notes
    pub fn remove_selected(&mut self) {
        let selected: Vec<_> = self.selected_ids.clone();
        for id in selected {
            self.remove_note(id);
        }
    }

    /// Move selected notes
    pub fn move_selected(&mut self, delta_tick: i64, delta_note: i8) {
        let ids: Vec<_> = self.selected_ids.clone();
        let snap_enabled = self.snap_enabled;
        let grid_ticks = self.grid.ticks(self.time_sig_num, self.time_sig_den);

        for id in &ids {
            if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                // Apply tick delta
                let new_tick = if delta_tick >= 0 {
                    note.note.start_tick.saturating_add(delta_tick as u64)
                } else {
                    note.note.start_tick.saturating_sub((-delta_tick) as u64)
                };
                // Snap inline to avoid borrow conflict
                note.note.start_tick = if snap_enabled {
                    ((new_tick + grid_ticks / 2) / grid_ticks) * grid_ticks
                } else {
                    new_tick
                };

                // Apply note delta
                let new_note = (note.note.note as i16 + delta_note as i16).clamp(0, 127) as u8;
                note.note.note = new_note;
            }
        }

        // Record edit for undo
        self.push_edit(PianoRollEdit::MoveNotes {
            note_ids: ids,
            delta_tick,
            delta_note,
        });

        self.notes.sort_by_key(|n| n.note.start_tick);
    }

    /// Resize selected notes
    pub fn resize_selected(&mut self, delta_duration: i64, from_start: bool) {
        let ids: Vec<_> = self.selected_ids.clone();
        let grid_ticks = self.grid.ticks(self.time_sig_num, self.time_sig_den);
        let min_duration = (grid_ticks as i64).max(1) as u64;
        let snap_enabled = self.snap_enabled;

        for id in &ids {
            if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                if from_start {
                    // Resize from start (move start, adjust duration)
                    let new_start = if delta_duration >= 0 {
                        note.note.start_tick.saturating_add(delta_duration as u64)
                    } else {
                        note.note
                            .start_tick
                            .saturating_sub((-delta_duration) as u64)
                    };
                    // Snap inline
                    let snapped_start = if snap_enabled {
                        ((new_start + grid_ticks / 2) / grid_ticks) * grid_ticks
                    } else {
                        new_start
                    };
                    let end_tick = note.note.start_tick + note.note.duration_ticks;

                    if snapped_start < end_tick {
                        note.note.duration_ticks = end_tick - snapped_start;
                        note.note.start_tick = snapped_start;
                    }
                } else {
                    // Resize from end (keep start, adjust duration)
                    let new_duration = if delta_duration >= 0 {
                        note.note
                            .duration_ticks
                            .saturating_add(delta_duration as u64)
                    } else {
                        note.note
                            .duration_ticks
                            .saturating_sub((-delta_duration) as u64)
                    };
                    note.note.duration_ticks = new_duration.max(min_duration);
                }
            }
        }

        self.push_edit(PianoRollEdit::ResizeNotes {
            note_ids: ids,
            delta_duration,
            from_start,
        });
    }

    /// Set velocity for selected notes
    pub fn set_selected_velocity(&mut self, velocity: Velocity) {
        let ids: Vec<_> = self.selected_ids.clone();
        let old_velocities: Vec<_> = ids
            .iter()
            .filter_map(|id| self.notes.iter().find(|n| n.id == *id))
            .map(|n| n.note.velocity)
            .collect();

        let count = old_velocities.len();

        for id in &ids {
            if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                note.note.velocity = velocity.clamp(1, 127);
            }
        }

        self.push_edit(PianoRollEdit::ChangeVelocity {
            note_ids: ids,
            old_velocities,
            new_velocities: vec![velocity; count],
        });
    }

    /// Quantize selected notes
    pub fn quantize_selected(&mut self, strength: f64) {
        let ids: Vec<_> = self.selected_ids.clone();
        let grid_ticks = self.grid.ticks(self.time_sig_num, self.time_sig_den);

        let old_positions: Vec<_> = ids
            .iter()
            .filter_map(|id| self.notes.iter().find(|n| n.id == *id))
            .map(|n| n.note.start_tick)
            .collect();

        let mut new_positions = Vec::new();

        for id in &ids {
            if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                let nearest = (note.note.start_tick + grid_ticks / 2) / grid_ticks * grid_ticks;
                let diff = nearest as f64 - note.note.start_tick as f64;
                let new_pos = (note.note.start_tick as f64 + diff * strength) as u64;
                note.note.start_tick = new_pos;
                new_positions.push(new_pos);
            }
        }

        self.push_edit(PianoRollEdit::Quantize {
            note_ids: ids,
            old_positions,
            new_positions,
        });

        self.notes.sort_by_key(|n| n.note.start_tick);
    }

    /// Transpose selected notes
    pub fn transpose_selected(&mut self, semitones: i8) {
        self.move_selected(0, semitones);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Selection
    // ─────────────────────────────────────────────────────────────────────────────

    /// Select note by ID
    pub fn select(&mut self, id: u64, add_to_selection: bool) {
        if !add_to_selection {
            self.deselect_all();
        }

        if let Some(note) = self.notes.iter_mut().find(|n| n.id == id) {
            note.selected = true;
            if !self.selected_ids.contains(&id) {
                self.selected_ids.push(id);
            }
        }
    }

    /// Toggle selection
    pub fn toggle_select(&mut self, id: u64) {
        if let Some(note) = self.notes.iter_mut().find(|n| n.id == id) {
            note.selected = !note.selected;
            if note.selected {
                if !self.selected_ids.contains(&id) {
                    self.selected_ids.push(id);
                }
            } else {
                self.selected_ids.retain(|&sid| sid != id);
            }
        }
    }

    /// Deselect all
    pub fn deselect_all(&mut self) {
        for note in &mut self.notes {
            note.selected = false;
        }
        self.selected_ids.clear();
    }

    /// Select all
    pub fn select_all(&mut self) {
        self.selected_ids.clear();
        for note in &mut self.notes {
            note.selected = true;
            self.selected_ids.push(note.id);
        }
    }

    /// Select notes in rectangle (tick_start, note_low) to (tick_end, note_high)
    pub fn select_rect(
        &mut self,
        tick_start: u64,
        tick_end: u64,
        note_low: u8,
        note_high: u8,
        add: bool,
    ) {
        if !add {
            self.deselect_all();
        }

        for note in &mut self.notes {
            let note_end = note.note.start_tick + note.note.duration_ticks;
            let overlaps = note.note.start_tick < tick_end
                && note_end > tick_start
                && note.note.note >= note_low
                && note.note.note <= note_high;

            if overlaps {
                note.selected = true;
                if !self.selected_ids.contains(&note.id) {
                    self.selected_ids.push(note.id);
                }
            }
        }
    }

    /// Get note at position
    pub fn note_at(&self, tick: u64, note_num: u8) -> Option<&PianoRollNote> {
        self.notes.iter().find(|n| {
            n.note.note == note_num
                && tick >= n.note.start_tick
                && tick < n.note.start_tick + n.note.duration_ticks
        })
    }

    /// Get note ID at position
    pub fn note_id_at(&self, tick: u64, note_num: u8) -> Option<u64> {
        self.note_at(tick, note_num).map(|n| n.id)
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Clipboard
    // ─────────────────────────────────────────────────────────────────────────────

    /// Copy selected notes
    pub fn copy(&mut self) {
        self.clipboard = self.notes.iter().filter(|n| n.selected).cloned().collect();
    }

    /// Cut selected notes
    pub fn cut(&mut self) {
        self.copy();
        self.remove_selected();
    }

    /// Paste notes at tick position
    pub fn paste(&mut self, tick: u64) {
        if self.clipboard.is_empty() {
            return;
        }

        // Clone clipboard to avoid borrow conflict
        let clipboard_copy: Vec<_> = self.clipboard.clone();

        // Find earliest tick in clipboard
        let min_tick = clipboard_copy
            .iter()
            .map(|n| n.note.start_tick)
            .min()
            .unwrap_or(0);

        let offset = tick.saturating_sub(min_tick);

        self.deselect_all();

        let mut new_ids = Vec::new();
        for clipboard_note in clipboard_copy {
            let mut new_note = clipboard_note.note;
            new_note.start_tick += offset;

            let id = self.add_note(
                new_note.note,
                new_note.start_tick,
                new_note.duration_ticks,
                new_note.velocity,
            );

            new_ids.push(id);
        }

        // Select all pasted notes
        for id in new_ids {
            self.select(id, true);
        }
    }

    /// Duplicate selected notes
    pub fn duplicate(&mut self, offset_ticks: u64) {
        self.copy();

        let min_tick = self
            .selected_ids
            .iter()
            .filter_map(|id| self.notes.iter().find(|n| n.id == *id))
            .map(|n| n.note.start_tick)
            .min()
            .unwrap_or(0);

        self.paste(min_tick + offset_ticks);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Undo/Redo
    // ─────────────────────────────────────────────────────────────────────────────

    fn push_edit(&mut self, edit: PianoRollEdit) {
        self.undo_stack.push(edit);
        self.redo_stack.clear();

        // Limit undo stack size
        if self.undo_stack.len() > 100 {
            self.undo_stack.remove(0);
        }
    }

    /// Undo last operation
    pub fn undo(&mut self) -> bool {
        if let Some(edit) = self.undo_stack.pop() {
            self.apply_edit_inverse(&edit);
            self.redo_stack.push(edit);
            true
        } else {
            false
        }
    }

    /// Redo last undone operation
    pub fn redo(&mut self) -> bool {
        if let Some(edit) = self.redo_stack.pop() {
            self.apply_edit(&edit);
            self.undo_stack.push(edit);
            true
        } else {
            false
        }
    }

    fn apply_edit(&mut self, edit: &PianoRollEdit) {
        match edit {
            PianoRollEdit::AddNote { note } => {
                self.notes.push(*note);
                self.notes.sort_by_key(|n| n.note.start_tick);
            }
            PianoRollEdit::RemoveNote { note } => {
                self.notes.retain(|n| n.id != note.id);
            }
            PianoRollEdit::MoveNotes {
                note_ids,
                delta_tick,
                delta_note,
            } => {
                for id in note_ids {
                    if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                        note.note.start_tick = if *delta_tick >= 0 {
                            note.note.start_tick.saturating_add(*delta_tick as u64)
                        } else {
                            note.note.start_tick.saturating_sub((-*delta_tick) as u64)
                        };
                        note.note.note =
                            (note.note.note as i16 + *delta_note as i16).clamp(0, 127) as u8;
                    }
                }
            }
            PianoRollEdit::ChangeVelocity {
                note_ids,
                new_velocities,
                ..
            } => {
                for (id, vel) in note_ids.iter().zip(new_velocities.iter()) {
                    if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                        note.note.velocity = *vel;
                    }
                }
            }
            _ => {}
        }
    }

    fn apply_edit_inverse(&mut self, edit: &PianoRollEdit) {
        match edit {
            PianoRollEdit::AddNote { note } => {
                self.notes.retain(|n| n.id != note.id);
            }
            PianoRollEdit::RemoveNote { note } => {
                self.notes.push(*note);
                self.notes.sort_by_key(|n| n.note.start_tick);
            }
            PianoRollEdit::MoveNotes {
                note_ids,
                delta_tick,
                delta_note,
            } => {
                for id in note_ids {
                    if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                        note.note.start_tick = if *delta_tick >= 0 {
                            note.note.start_tick.saturating_sub(*delta_tick as u64)
                        } else {
                            note.note.start_tick.saturating_add((-*delta_tick) as u64)
                        };
                        note.note.note =
                            (note.note.note as i16 - *delta_note as i16).clamp(0, 127) as u8;
                    }
                }
            }
            PianoRollEdit::ChangeVelocity {
                note_ids,
                old_velocities,
                ..
            } => {
                for (id, vel) in note_ids.iter().zip(old_velocities.iter()) {
                    if let Some(note) = self.notes.iter_mut().find(|n| n.id == *id) {
                        note.note.velocity = *vel;
                    }
                }
            }
            _ => {}
        }
    }

    /// Can undo?
    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    /// Can redo?
    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Utilities
    // ─────────────────────────────────────────────────────────────────────────────

    /// Get note name for display
    pub fn note_name(note: u8) -> String {
        let (name, octave) = NoteName::from_note(note);
        format!("{}{}", name.name(), octave)
    }

    /// Is note a black key?
    pub fn is_black_key(note: u8) -> bool {
        matches!(note % 12, 1 | 3 | 6 | 8 | 10)
    }

    /// Get notes for display
    pub fn visible_notes(&self) -> impl Iterator<Item = &PianoRollNote> {
        self.notes.iter()
    }

    /// Get grid lines for display
    pub fn grid_lines(&self, start_tick: u64, end_tick: u64) -> Vec<(u64, bool)> {
        let grid_ticks = self.grid.ticks(self.time_sig_num, self.time_sig_den);
        let bar_ticks = TICKS_PER_BEAT * (self.time_sig_num as u64 * 4 / self.time_sig_den as u64);

        let mut lines = Vec::new();
        let mut tick = (start_tick / grid_ticks) * grid_ticks;

        while tick <= end_tick {
            let is_bar = tick % bar_ticks == 0;
            lines.push((tick, is_bar));
            tick += grid_ticks;
        }

        lines
    }

    /// Get selected notes count
    pub fn selection_count(&self) -> usize {
        self.selected_ids.len()
    }

    /// Get total notes count
    pub fn note_count(&self) -> usize {
        self.notes.len()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grid_division() {
        let quarter = GridDivision::Quarter;
        assert_eq!(quarter.ticks(4, 4), 960);

        let eighth = GridDivision::Eighth;
        assert_eq!(eighth.ticks(4, 4), 480);

        let sixteenth = GridDivision::Sixteenth;
        assert_eq!(sixteenth.ticks(4, 4), 240);
    }

    #[test]
    fn test_add_remove_note() {
        let mut state = PianoRollState::new(1);

        let id = state.add_note(60, 0, 480, 100);
        assert_eq!(state.notes.len(), 1);

        state.remove_note(id);
        assert_eq!(state.notes.len(), 0);
    }

    #[test]
    fn test_selection() {
        let mut state = PianoRollState::new(1);

        let id1 = state.add_note(60, 0, 480, 100);
        let id2 = state.add_note(64, 480, 480, 100);

        state.select(id1, false);
        assert_eq!(state.selected_ids.len(), 1);

        state.select(id2, true);
        assert_eq!(state.selected_ids.len(), 2);

        state.deselect_all();
        assert_eq!(state.selected_ids.len(), 0);
    }

    #[test]
    fn test_move_notes() {
        let mut state = PianoRollState::new(1);
        state.snap_enabled = false;

        let id = state.add_note(60, 0, 480, 100);
        state.select(id, false);

        state.move_selected(240, 2);

        let note = state.notes.iter().find(|n| n.id == id).unwrap();
        assert_eq!(note.note.start_tick, 240);
        assert_eq!(note.note.note, 62);
    }

    #[test]
    fn test_undo_redo() {
        let mut state = PianoRollState::new(1);

        let id = state.add_note(60, 0, 480, 100);
        assert_eq!(state.notes.len(), 1);

        state.undo();
        assert_eq!(state.notes.len(), 0);

        state.redo();
        assert_eq!(state.notes.len(), 1);
    }

    #[test]
    fn test_snap_to_grid() {
        let state = PianoRollState::new(1);

        // Sixteenth note grid = 240 ticks
        assert_eq!(state.snap_to_grid(100), 0);
        assert_eq!(state.snap_to_grid(150), 240);
        assert_eq!(state.snap_to_grid(360), 480);
    }
}

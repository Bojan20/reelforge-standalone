//! MIDI Types and Events
//!
//! Provides comprehensive MIDI support:
//! - Standard MIDI events (Note On/Off, CC, Pitch Bend, etc.)
//! - High-resolution MIDI 2.0 support
//! - Sample-accurate timing
//! - MIDI buffer management
//! - MIDI file parsing helpers

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// MIDI 1.0 status bytes
pub mod status {
    pub const NOTE_OFF: u8 = 0x80;
    pub const NOTE_ON: u8 = 0x90;
    pub const POLY_PRESSURE: u8 = 0xA0;
    pub const CONTROL_CHANGE: u8 = 0xB0;
    pub const PROGRAM_CHANGE: u8 = 0xC0;
    pub const CHANNEL_PRESSURE: u8 = 0xD0;
    pub const PITCH_BEND: u8 = 0xE0;
    pub const SYSTEM: u8 = 0xF0;
}

/// Common MIDI CC numbers
pub mod cc {
    pub const BANK_SELECT_MSB: u8 = 0;
    pub const MOD_WHEEL: u8 = 1;
    pub const BREATH: u8 = 2;
    pub const FOOT_CONTROLLER: u8 = 4;
    pub const PORTAMENTO_TIME: u8 = 5;
    pub const DATA_ENTRY_MSB: u8 = 6;
    pub const VOLUME: u8 = 7;
    pub const BALANCE: u8 = 8;
    pub const PAN: u8 = 10;
    pub const EXPRESSION: u8 = 11;
    pub const EFFECT_1: u8 = 12;
    pub const EFFECT_2: u8 = 13;
    pub const BANK_SELECT_LSB: u8 = 32;
    pub const DATA_ENTRY_LSB: u8 = 38;
    pub const SUSTAIN: u8 = 64;
    pub const PORTAMENTO: u8 = 65;
    pub const SOSTENUTO: u8 = 66;
    pub const SOFT_PEDAL: u8 = 67;
    pub const LEGATO: u8 = 68;
    pub const HOLD_2: u8 = 69;
    pub const SOUND_VARIATION: u8 = 70;
    pub const RESONANCE: u8 = 71;
    pub const RELEASE_TIME: u8 = 72;
    pub const ATTACK_TIME: u8 = 73;
    pub const CUTOFF: u8 = 74;
    pub const DECAY_TIME: u8 = 75;
    pub const VIBRATO_RATE: u8 = 76;
    pub const VIBRATO_DEPTH: u8 = 77;
    pub const VIBRATO_DELAY: u8 = 78;
    pub const REVERB_SEND: u8 = 91;
    pub const TREMOLO: u8 = 92;
    pub const CHORUS_SEND: u8 = 93;
    pub const DETUNE: u8 = 94;
    pub const PHASER: u8 = 95;
    pub const DATA_INCREMENT: u8 = 96;
    pub const DATA_DECREMENT: u8 = 97;
    pub const NRPN_LSB: u8 = 98;
    pub const NRPN_MSB: u8 = 99;
    pub const RPN_LSB: u8 = 100;
    pub const RPN_MSB: u8 = 101;
    pub const ALL_SOUND_OFF: u8 = 120;
    pub const RESET_ALL_CONTROLLERS: u8 = 121;
    pub const LOCAL_CONTROL: u8 = 122;
    pub const ALL_NOTES_OFF: u8 = 123;
    pub const OMNI_OFF: u8 = 124;
    pub const OMNI_ON: u8 = 125;
    pub const MONO_ON: u8 = 126;
    pub const POLY_ON: u8 = 127;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI EVENT TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// MIDI channel (0-15)
pub type MidiChannel = u8;

/// MIDI note number (0-127)
pub type NoteNumber = u8;

/// MIDI velocity (0-127 for MIDI 1.0, 0-65535 for MIDI 2.0)
pub type Velocity = u16;

/// MIDI controller number (0-127)
pub type ControllerNumber = u8;

/// MIDI controller value (0-127 for MIDI 1.0, 0-16383 for high-res)
pub type ControllerValue = u16;

/// Note name helper
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NoteName {
    C, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B,
}

impl NoteName {
    pub fn from_note(note: NoteNumber) -> (Self, i8) {
        let octave = (note as i8 / 12) - 1;
        let name = match note % 12 {
            0 => NoteName::C,
            1 => NoteName::Cs,
            2 => NoteName::D,
            3 => NoteName::Ds,
            4 => NoteName::E,
            5 => NoteName::F,
            6 => NoteName::Fs,
            7 => NoteName::G,
            8 => NoteName::Gs,
            9 => NoteName::A,
            10 => NoteName::As,
            11 => NoteName::B,
            _ => unreachable!(),
        };
        (name, octave)
    }

    pub fn to_note(self, octave: i8) -> NoteNumber {
        let base = match self {
            NoteName::C => 0,
            NoteName::Cs => 1,
            NoteName::D => 2,
            NoteName::Ds => 3,
            NoteName::E => 4,
            NoteName::F => 5,
            NoteName::Fs => 6,
            NoteName::G => 7,
            NoteName::Gs => 8,
            NoteName::A => 9,
            NoteName::As => 10,
            NoteName::B => 11,
        };
        ((octave + 1) * 12 + base) as u8
    }

    pub fn name(&self) -> &'static str {
        match self {
            NoteName::C => "C",
            NoteName::Cs => "C#",
            NoteName::D => "D",
            NoteName::Ds => "D#",
            NoteName::E => "E",
            NoteName::F => "F",
            NoteName::Fs => "F#",
            NoteName::G => "G",
            NoteName::Gs => "G#",
            NoteName::A => "A",
            NoteName::As => "A#",
            NoteName::B => "B",
        }
    }
}

/// MIDI event data
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum MidiEventData {
    /// Note Off (note, velocity)
    NoteOff {
        note: NoteNumber,
        velocity: Velocity,
    },
    /// Note On (note, velocity) - velocity 0 = note off
    NoteOn {
        note: NoteNumber,
        velocity: Velocity,
    },
    /// Polyphonic Key Pressure (aftertouch per note)
    PolyPressure {
        note: NoteNumber,
        pressure: u16,
    },
    /// Control Change
    ControlChange {
        controller: ControllerNumber,
        value: ControllerValue,
    },
    /// Program Change
    ProgramChange {
        program: u8,
    },
    /// Channel Pressure (aftertouch for whole channel)
    ChannelPressure {
        pressure: u16,
    },
    /// Pitch Bend (-8192 to +8191, center = 0)
    PitchBend {
        value: i16,
    },
    /// System Exclusive (reference to data buffer)
    SysEx {
        length: u32,
        /// Offset into external sysex buffer
        offset: u32,
    },
    /// MIDI Time Code Quarter Frame
    MtcQuarterFrame {
        data: u8,
    },
    /// Song Position Pointer
    SongPosition {
        position: u16,
    },
    /// Song Select
    SongSelect {
        song: u8,
    },
    /// Tune Request
    TuneRequest,
    /// Timing Clock
    TimingClock,
    /// Start
    Start,
    /// Continue
    Continue,
    /// Stop
    Stop,
    /// Active Sensing
    ActiveSensing,
    /// System Reset
    SystemReset,
}

/// Sample-accurate MIDI event
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiEvent {
    /// Sample offset within the buffer (0 = start of buffer)
    pub sample_offset: u32,
    /// MIDI channel (0-15, or 0xFF for channel-less messages)
    pub channel: MidiChannel,
    /// Event data
    pub data: MidiEventData,
}

impl MidiEvent {
    /// Create a Note On event
    pub fn note_on(sample_offset: u32, channel: MidiChannel, note: NoteNumber, velocity: Velocity) -> Self {
        Self {
            sample_offset,
            channel,
            data: MidiEventData::NoteOn { note, velocity },
        }
    }

    /// Create a Note Off event
    pub fn note_off(sample_offset: u32, channel: MidiChannel, note: NoteNumber, velocity: Velocity) -> Self {
        Self {
            sample_offset,
            channel,
            data: MidiEventData::NoteOff { note, velocity },
        }
    }

    /// Create a CC event
    pub fn control_change(
        sample_offset: u32,
        channel: MidiChannel,
        controller: ControllerNumber,
        value: ControllerValue,
    ) -> Self {
        Self {
            sample_offset,
            channel,
            data: MidiEventData::ControlChange { controller, value },
        }
    }

    /// Create a Pitch Bend event
    pub fn pitch_bend(sample_offset: u32, channel: MidiChannel, value: i16) -> Self {
        Self {
            sample_offset,
            channel,
            data: MidiEventData::PitchBend { value },
        }
    }

    /// Create a Program Change event
    pub fn program_change(sample_offset: u32, channel: MidiChannel, program: u8) -> Self {
        Self {
            sample_offset,
            channel,
            data: MidiEventData::ProgramChange { program },
        }
    }

    /// Convert from raw MIDI bytes
    pub fn from_bytes(sample_offset: u32, bytes: &[u8]) -> Option<Self> {
        if bytes.is_empty() {
            return None;
        }

        let status = bytes[0];
        let channel = status & 0x0F;
        let msg_type = status & 0xF0;

        let data = match msg_type {
            status::NOTE_OFF if bytes.len() >= 3 => MidiEventData::NoteOff {
                note: bytes[1] & 0x7F,
                velocity: (bytes[2] & 0x7F) as u16,
            },
            status::NOTE_ON if bytes.len() >= 3 => {
                let velocity = (bytes[2] & 0x7F) as u16;
                if velocity == 0 {
                    MidiEventData::NoteOff {
                        note: bytes[1] & 0x7F,
                        velocity: 64,
                    }
                } else {
                    MidiEventData::NoteOn {
                        note: bytes[1] & 0x7F,
                        velocity,
                    }
                }
            }
            status::POLY_PRESSURE if bytes.len() >= 3 => MidiEventData::PolyPressure {
                note: bytes[1] & 0x7F,
                pressure: (bytes[2] & 0x7F) as u16,
            },
            status::CONTROL_CHANGE if bytes.len() >= 3 => MidiEventData::ControlChange {
                controller: bytes[1] & 0x7F,
                value: (bytes[2] & 0x7F) as u16,
            },
            status::PROGRAM_CHANGE if bytes.len() >= 2 => MidiEventData::ProgramChange {
                program: bytes[1] & 0x7F,
            },
            status::CHANNEL_PRESSURE if bytes.len() >= 2 => MidiEventData::ChannelPressure {
                pressure: (bytes[1] & 0x7F) as u16,
            },
            status::PITCH_BEND if bytes.len() >= 3 => {
                let lsb = bytes[1] as i16 & 0x7F;
                let msb = bytes[2] as i16 & 0x7F;
                let value = ((msb << 7) | lsb) - 8192;
                MidiEventData::PitchBend { value }
            }
            status::SYSTEM => match status {
                0xF8 => MidiEventData::TimingClock,
                0xFA => MidiEventData::Start,
                0xFB => MidiEventData::Continue,
                0xFC => MidiEventData::Stop,
                0xFE => MidiEventData::ActiveSensing,
                0xFF => MidiEventData::SystemReset,
                _ => return None,
            },
            _ => return None,
        };

        Some(Self {
            sample_offset,
            channel: if msg_type >= 0xF0 { 0xFF } else { channel },
            data,
        })
    }

    /// Convert to raw MIDI bytes
    pub fn to_bytes(&self, buffer: &mut [u8]) -> usize {
        match self.data {
            MidiEventData::NoteOff { note, velocity } => {
                if buffer.len() >= 3 {
                    buffer[0] = status::NOTE_OFF | (self.channel & 0x0F);
                    buffer[1] = note & 0x7F;
                    buffer[2] = (velocity.min(127)) as u8;
                    3
                } else {
                    0
                }
            }
            MidiEventData::NoteOn { note, velocity } => {
                if buffer.len() >= 3 {
                    buffer[0] = status::NOTE_ON | (self.channel & 0x0F);
                    buffer[1] = note & 0x7F;
                    buffer[2] = (velocity.min(127)) as u8;
                    3
                } else {
                    0
                }
            }
            MidiEventData::ControlChange { controller, value } => {
                if buffer.len() >= 3 {
                    buffer[0] = status::CONTROL_CHANGE | (self.channel & 0x0F);
                    buffer[1] = controller & 0x7F;
                    buffer[2] = (value.min(127)) as u8;
                    3
                } else {
                    0
                }
            }
            MidiEventData::PitchBend { value } => {
                if buffer.len() >= 3 {
                    let bent = (value + 8192).clamp(0, 16383) as u16;
                    buffer[0] = status::PITCH_BEND | (self.channel & 0x0F);
                    buffer[1] = (bent & 0x7F) as u8;
                    buffer[2] = ((bent >> 7) & 0x7F) as u8;
                    3
                } else {
                    0
                }
            }
            MidiEventData::ProgramChange { program } => {
                if buffer.len() >= 2 {
                    buffer[0] = status::PROGRAM_CHANGE | (self.channel & 0x0F);
                    buffer[1] = program & 0x7F;
                    2
                } else {
                    0
                }
            }
            MidiEventData::ChannelPressure { pressure } => {
                if buffer.len() >= 2 {
                    buffer[0] = status::CHANNEL_PRESSURE | (self.channel & 0x0F);
                    buffer[1] = (pressure.min(127)) as u8;
                    2
                } else {
                    0
                }
            }
            MidiEventData::PolyPressure { note, pressure } => {
                if buffer.len() >= 3 {
                    buffer[0] = status::POLY_PRESSURE | (self.channel & 0x0F);
                    buffer[1] = note & 0x7F;
                    buffer[2] = (pressure.min(127)) as u8;
                    3
                } else {
                    0
                }
            }
            MidiEventData::TimingClock => {
                if !buffer.is_empty() {
                    buffer[0] = 0xF8;
                    1
                } else {
                    0
                }
            }
            MidiEventData::Start => {
                if !buffer.is_empty() {
                    buffer[0] = 0xFA;
                    1
                } else {
                    0
                }
            }
            MidiEventData::Continue => {
                if !buffer.is_empty() {
                    buffer[0] = 0xFB;
                    1
                } else {
                    0
                }
            }
            MidiEventData::Stop => {
                if !buffer.is_empty() {
                    buffer[0] = 0xFC;
                    1
                } else {
                    0
                }
            }
            _ => 0,
        }
    }

    /// Check if this is a note event
    pub fn is_note(&self) -> bool {
        matches!(self.data, MidiEventData::NoteOn { .. } | MidiEventData::NoteOff { .. })
    }

    /// Check if this is a note on with velocity > 0
    pub fn is_note_on(&self) -> bool {
        matches!(self.data, MidiEventData::NoteOn { velocity, .. } if velocity > 0)
    }

    /// Check if this is a note off (or note on with velocity 0)
    pub fn is_note_off(&self) -> bool {
        matches!(
            self.data,
            MidiEventData::NoteOff { .. } | MidiEventData::NoteOn { velocity: 0, .. }
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Maximum events per buffer
pub const MAX_MIDI_EVENTS_PER_BUFFER: usize = 1024;

/// MIDI event buffer for a single processing block
#[derive(Debug, Clone)]
pub struct MidiBuffer {
    events: Vec<MidiEvent>,
    /// SysEx data storage
    sysex_data: Vec<u8>,
}

impl MidiBuffer {
    pub fn new() -> Self {
        Self {
            events: Vec::with_capacity(256),
            sysex_data: Vec::new(),
        }
    }

    pub fn with_capacity(event_capacity: usize) -> Self {
        Self {
            events: Vec::with_capacity(event_capacity),
            sysex_data: Vec::new(),
        }
    }

    /// Clear all events
    pub fn clear(&mut self) {
        self.events.clear();
        self.sysex_data.clear();
    }

    /// Add an event
    pub fn push(&mut self, event: MidiEvent) {
        if self.events.len() < MAX_MIDI_EVENTS_PER_BUFFER {
            self.events.push(event);
        }
    }

    /// Add a SysEx message
    pub fn push_sysex(&mut self, sample_offset: u32, data: &[u8]) {
        let offset = self.sysex_data.len() as u32;
        self.sysex_data.extend_from_slice(data);

        self.push(MidiEvent {
            sample_offset,
            channel: 0xFF,
            data: MidiEventData::SysEx {
                length: data.len() as u32,
                offset,
            },
        });
    }

    /// Get SysEx data for an event
    pub fn get_sysex(&self, offset: u32, length: u32) -> Option<&[u8]> {
        let start = offset as usize;
        let end = start + length as usize;
        if end <= self.sysex_data.len() {
            Some(&self.sysex_data[start..end])
        } else {
            None
        }
    }

    /// Get all events
    pub fn events(&self) -> &[MidiEvent] {
        &self.events
    }

    /// Get mutable events
    pub fn events_mut(&mut self) -> &mut Vec<MidiEvent> {
        &mut self.events
    }

    /// Number of events
    pub fn len(&self) -> usize {
        self.events.len()
    }

    /// Is empty
    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    /// Sort events by sample offset
    pub fn sort_by_time(&mut self) {
        self.events.sort_by_key(|e| e.sample_offset);
    }

    /// Iterate events in a sample range
    pub fn events_in_range(&self, start: u32, end: u32) -> impl Iterator<Item = &MidiEvent> {
        self.events
            .iter()
            .filter(move |e| e.sample_offset >= start && e.sample_offset < end)
    }

    /// Merge another buffer into this one
    pub fn merge(&mut self, other: &MidiBuffer) {
        for event in &other.events {
            self.push(*event);
        }
    }

    /// Offset all events by sample count
    pub fn offset_all(&mut self, samples: u32) {
        for event in &mut self.events {
            event.sample_offset += samples;
        }
    }
}

impl Default for MidiBuffer {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI NOTE STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Track which notes are currently on (for each channel)
#[derive(Debug, Clone)]
pub struct NoteStateTracker {
    /// 16 channels × 128 notes = 2048 bits = 256 bytes
    state: [[bool; 128]; 16],
}

impl NoteStateTracker {
    pub fn new() -> Self {
        Self {
            state: [[false; 128]; 16],
        }
    }

    /// Process an event and update state
    pub fn process(&mut self, event: &MidiEvent) {
        if event.channel >= 16 {
            return;
        }

        let ch = event.channel as usize;

        match event.data {
            MidiEventData::NoteOn { note, velocity } => {
                if note < 128 {
                    self.state[ch][note as usize] = velocity > 0;
                }
            }
            MidiEventData::NoteOff { note, .. } => {
                if note < 128 {
                    self.state[ch][note as usize] = false;
                }
            }
            MidiEventData::ControlChange { controller, .. } if controller == cc::ALL_NOTES_OFF => {
                self.state[ch] = [false; 128];
            }
            _ => {}
        }
    }

    /// Check if a note is on
    pub fn is_note_on(&self, channel: MidiChannel, note: NoteNumber) -> bool {
        if channel < 16 && note < 128 {
            self.state[channel as usize][note as usize]
        } else {
            false
        }
    }

    /// Get all active notes for a channel
    pub fn active_notes(&self, channel: MidiChannel) -> Vec<NoteNumber> {
        if channel >= 16 {
            return Vec::new();
        }

        self.state[channel as usize]
            .iter()
            .enumerate()
            .filter_map(|(note, &on)| if on { Some(note as u8) } else { None })
            .collect()
    }

    /// Generate note-off events for all active notes
    pub fn generate_all_notes_off(&self, sample_offset: u32) -> Vec<MidiEvent> {
        let mut events = Vec::new();

        for channel in 0..16 {
            for (note, &on) in self.state[channel].iter().enumerate() {
                if on {
                    events.push(MidiEvent::note_off(
                        sample_offset,
                        channel as u8,
                        note as u8,
                        64,
                    ));
                }
            }
        }

        events
    }

    /// Clear all note state
    pub fn reset(&mut self) {
        self.state = [[false; 128]; 16];
    }
}

impl Default for NoteStateTracker {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI SEQUENCE (FOR CLIPS)
// ═══════════════════════════════════════════════════════════════════════════════

/// A note event with duration (for sequencer)
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiNote {
    /// Start position in ticks (960 ticks per beat)
    pub start_tick: u64,
    /// Duration in ticks
    pub duration_ticks: u64,
    /// Note number
    pub note: NoteNumber,
    /// Velocity
    pub velocity: Velocity,
    /// Release velocity
    pub release_velocity: Velocity,
    /// Channel
    pub channel: MidiChannel,
}

impl MidiNote {
    pub fn new(start_tick: u64, duration_ticks: u64, note: NoteNumber, velocity: Velocity) -> Self {
        Self {
            start_tick,
            duration_ticks,
            note,
            velocity,
            release_velocity: 64,
            channel: 0,
        }
    }

    pub fn end_tick(&self) -> u64 {
        self.start_tick + self.duration_ticks
    }
}

/// MIDI clip/pattern
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MidiClip {
    /// Clip ID
    pub id: String,
    /// Clip name
    pub name: String,
    /// Notes in the clip
    pub notes: Vec<MidiNote>,
    /// CC automation
    pub cc_events: Vec<MidiCCEvent>,
    /// Pitch bend events
    pub pitch_bend_events: Vec<MidiPitchBendEvent>,
    /// Clip length in ticks
    pub length_ticks: u64,
    /// Loop enabled
    pub loop_enabled: bool,
}

/// CC event for sequencer
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiCCEvent {
    pub tick: u64,
    pub channel: MidiChannel,
    pub controller: ControllerNumber,
    pub value: ControllerValue,
}

/// Pitch bend event for sequencer
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct MidiPitchBendEvent {
    pub tick: u64,
    pub channel: MidiChannel,
    pub value: i16,
}

impl MidiClip {
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            notes: Vec::new(),
            cc_events: Vec::new(),
            pitch_bend_events: Vec::new(),
            length_ticks: 960 * 4, // 1 bar at 4/4
            loop_enabled: false,
        }
    }

    /// Add a note
    pub fn add_note(&mut self, note: MidiNote) {
        self.notes.push(note);
        self.notes.sort_by_key(|n| n.start_tick);
    }

    /// Remove a note by index
    pub fn remove_note(&mut self, index: usize) -> Option<MidiNote> {
        if index < self.notes.len() {
            Some(self.notes.remove(index))
        } else {
            None
        }
    }

    /// Get notes in tick range
    pub fn notes_in_range(&self, start: u64, end: u64) -> impl Iterator<Item = &MidiNote> {
        self.notes.iter().filter(move |n| {
            n.start_tick < end && n.end_tick() > start
        })
    }

    /// Quantize notes to grid
    pub fn quantize(&mut self, grid_ticks: u64, strength: f64) {
        for note in &mut self.notes {
            let nearest_grid = (note.start_tick + grid_ticks / 2) / grid_ticks * grid_ticks;
            let diff = nearest_grid as f64 - note.start_tick as f64;
            note.start_tick = (note.start_tick as f64 + diff * strength) as u64;
        }
    }

    /// Transpose all notes
    pub fn transpose(&mut self, semitones: i8) {
        for note in &mut self.notes {
            let new_note = (note.note as i16 + semitones as i16).clamp(0, 127) as u8;
            note.note = new_note;
        }
    }

    /// Scale velocities
    pub fn scale_velocity(&mut self, factor: f64) {
        for note in &mut self.notes {
            note.velocity = ((note.velocity as f64 * factor) as u16).clamp(1, 127);
        }
    }

    /// Generate MIDI events for playback
    pub fn generate_events(
        &self,
        start_tick: u64,
        end_tick: u64,
        ticks_per_sample: f64,
        _buffer_start_sample: u64,
    ) -> Vec<MidiEvent> {
        let mut events = Vec::new();

        // Notes
        for note in &self.notes {
            // Note on
            if note.start_tick >= start_tick && note.start_tick < end_tick {
                let sample_offset = ((note.start_tick - start_tick) as f64 / ticks_per_sample) as u32;
                events.push(MidiEvent::note_on(
                    sample_offset,
                    note.channel,
                    note.note,
                    note.velocity,
                ));
            }

            // Note off
            let note_end = note.end_tick();
            if note_end >= start_tick && note_end < end_tick {
                let sample_offset = ((note_end - start_tick) as f64 / ticks_per_sample) as u32;
                events.push(MidiEvent::note_off(
                    sample_offset,
                    note.channel,
                    note.note,
                    note.release_velocity,
                ));
            }
        }

        // CC events
        for cc in &self.cc_events {
            if cc.tick >= start_tick && cc.tick < end_tick {
                let sample_offset = ((cc.tick - start_tick) as f64 / ticks_per_sample) as u32;
                events.push(MidiEvent::control_change(
                    sample_offset,
                    cc.channel,
                    cc.controller,
                    cc.value,
                ));
            }
        }

        // Pitch bend events
        for pb in &self.pitch_bend_events {
            if pb.tick >= start_tick && pb.tick < end_tick {
                let sample_offset = ((pb.tick - start_tick) as f64 / ticks_per_sample) as u32;
                events.push(MidiEvent::pitch_bend(sample_offset, pb.channel, pb.value));
            }
        }

        events.sort_by_key(|e| e.sample_offset);
        events
    }
}

impl Default for MidiClip {
    fn default() -> Self {
        Self::new("", "New MIDI Clip")
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_note_name() {
        let (name, octave) = NoteName::from_note(60);
        assert_eq!(name, NoteName::C);
        assert_eq!(octave, 4);

        let note = NoteName::A.to_note(4);
        assert_eq!(note, 69); // A4 = 440Hz
    }

    #[test]
    fn test_midi_event_from_bytes() {
        // Note On
        let bytes = [0x91, 60, 100];
        let event = MidiEvent::from_bytes(0, &bytes).unwrap();
        assert_eq!(event.channel, 1);
        assert!(matches!(event.data, MidiEventData::NoteOn { note: 60, velocity: 100 }));

        // Note On with velocity 0 = Note Off
        let bytes = [0x90, 64, 0];
        let event = MidiEvent::from_bytes(0, &bytes).unwrap();
        assert!(event.is_note_off());
    }

    #[test]
    fn test_midi_event_to_bytes() {
        let event = MidiEvent::note_on(0, 0, 60, 127);
        let mut buffer = [0u8; 3];
        let len = event.to_bytes(&mut buffer);
        assert_eq!(len, 3);
        assert_eq!(buffer, [0x90, 60, 127]);
    }

    #[test]
    fn test_midi_buffer() {
        let mut buffer = MidiBuffer::new();
        buffer.push(MidiEvent::note_on(0, 0, 60, 100));
        buffer.push(MidiEvent::note_on(100, 0, 64, 100));
        buffer.push(MidiEvent::note_off(200, 0, 60, 0));

        assert_eq!(buffer.len(), 3);

        let in_range: Vec<_> = buffer.events_in_range(50, 150).collect();
        assert_eq!(in_range.len(), 1);
    }

    #[test]
    fn test_note_state_tracker() {
        let mut tracker = NoteStateTracker::new();

        tracker.process(&MidiEvent::note_on(0, 0, 60, 100));
        assert!(tracker.is_note_on(0, 60));

        tracker.process(&MidiEvent::note_off(0, 0, 60, 0));
        assert!(!tracker.is_note_on(0, 60));
    }

    #[test]
    fn test_midi_clip() {
        let mut clip = MidiClip::new("test", "Test Clip");
        clip.add_note(MidiNote::new(0, 480, 60, 100));
        clip.add_note(MidiNote::new(480, 480, 64, 100));

        assert_eq!(clip.notes.len(), 2);

        clip.transpose(12);
        assert_eq!(clip.notes[0].note, 72);
        assert_eq!(clip.notes[1].note, 76);
    }
}

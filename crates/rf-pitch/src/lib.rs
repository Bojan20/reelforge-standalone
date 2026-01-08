//! ReelForge Polyphonic Pitch Engine
//!
//! Melodyne DNA-level pitch manipulation for polyphonic audio:
//!
//! ## Features
//! - **Polyphonic Detection**: Separate individual notes from complex audio
//! - **Note Tracking**: Track pitch, amplitude, and timing per note
//! - **Pitch Correction**: Auto-tune and manual pitch editing
//! - **Time Stretching**: Independent time manipulation per note
//! - **Formant Preservation**: Maintain natural timbre during pitch shifts
//! - **Re-synthesis**: Reconstruct audio from modified note data
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_pitch::{PolyphonicEngine, NoteEvent, Scale};
//!
//! // Analyze audio
//! let mut engine = PolyphonicEngine::new(48000);
//! let notes = engine.analyze(&audio);
//!
//! // Modify notes
//! for note in &mut notes {
//!     note.pitch = engine.quantize_to_scale(note.pitch, Scale::major(0));
//! }
//!
//! // Re-synthesize
//! let corrected = engine.synthesize(&notes);
//! ```

#![allow(missing_docs)]
#![allow(dead_code)]

pub mod analysis;
pub mod correction;
pub mod detection;
pub mod scale;
pub mod synthesis;

mod error;

pub use error::{PitchError, PitchResult};

use serde::{Deserialize, Serialize};

/// Musical note with pitch, time, and amplitude information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteEvent {
    /// MIDI pitch (float for microtonal)
    pub pitch: f32,
    /// Pitch confidence (0-1)
    pub confidence: f32,
    /// Start time (samples)
    pub start_sample: usize,
    /// Duration (samples)
    pub duration: usize,
    /// Amplitude envelope
    pub amplitude: Vec<f32>,
    /// Pitch contour (pitch over time)
    pub pitch_contour: Vec<f32>,
    /// Formant shift (semitones)
    pub formant_shift: f32,
    /// Original frequency (Hz)
    pub original_freq: f32,
    /// Voice/channel ID
    pub voice_id: usize,
}

impl NoteEvent {
    /// Create new note event
    pub fn new(pitch: f32, start: usize, duration: usize) -> Self {
        Self {
            pitch,
            confidence: 1.0,
            start_sample: start,
            duration,
            amplitude: Vec::new(),
            pitch_contour: Vec::new(),
            formant_shift: 0.0,
            original_freq: 440.0 * 2.0f32.powf((pitch - 69.0) / 12.0),
            voice_id: 0,
        }
    }

    /// Get frequency at point in note
    pub fn frequency_at(&self, offset: usize) -> f32 {
        if self.pitch_contour.is_empty() {
            440.0 * 2.0f32.powf((self.pitch - 69.0) / 12.0)
        } else {
            let idx = offset.min(self.pitch_contour.len() - 1);
            self.pitch_contour[idx]
        }
    }

    /// Get amplitude at point in note
    pub fn amplitude_at(&self, offset: usize) -> f32 {
        if self.amplitude.is_empty() {
            1.0
        } else {
            let idx = offset.min(self.amplitude.len() - 1);
            self.amplitude[idx]
        }
    }

    /// Get end sample
    pub fn end_sample(&self) -> usize {
        self.start_sample + self.duration
    }

    /// Shift pitch by semitones
    pub fn shift_pitch(&mut self, semitones: f32) {
        self.pitch += semitones;
        for freq in &mut self.pitch_contour {
            *freq *= 2.0f32.powf(semitones / 12.0);
        }
    }

    /// Quantize to nearest semitone
    pub fn quantize(&mut self) {
        self.pitch = self.pitch.round();
        let ratio = 2.0f32.powf((self.pitch.round() - self.pitch) / 12.0);
        for freq in &mut self.pitch_contour {
            *freq *= ratio;
        }
    }
}

/// Voice/partials for polyphonic detection
#[derive(Debug, Clone)]
pub struct Voice {
    /// Fundamental frequency (Hz)
    pub fundamental: f32,
    /// Harmonic amplitudes
    pub harmonics: Vec<f32>,
    /// Harmonic phases
    pub phases: Vec<f32>,
    /// Spectral centroid
    pub centroid: f32,
    /// Spectral flux
    pub flux: f32,
    /// Is active
    pub active: bool,
}

impl Voice {
    /// Create new voice
    pub fn new(fundamental: f32) -> Self {
        Self {
            fundamental,
            harmonics: Vec::new(),
            phases: Vec::new(),
            centroid: fundamental,
            flux: 0.0,
            active: true,
        }
    }
}

/// Polyphonic pitch analysis result
#[derive(Debug, Clone)]
pub struct PolyphonicAnalysis {
    /// Detected notes
    pub notes: Vec<NoteEvent>,
    /// Detected voices (active at each frame)
    pub voices: Vec<Vec<Voice>>,
    /// Sample rate
    pub sample_rate: u32,
    /// Hop size used
    pub hop_size: usize,
    /// Analysis confidence
    pub confidence: f32,
}

/// Pitch detection algorithm
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DetectionAlgorithm {
    /// Autocorrelation-based (YIN)
    Yin,
    /// Probabilistic YIN (pYIN)
    ProbabilisticYin,
    /// Spectral/harmonic analysis
    Harmonic,
    /// Deep learning-based
    Neural,
    /// Multi-algorithm fusion
    Fusion,
}

/// Pitch engine configuration
#[derive(Debug, Clone)]
pub struct PitchConfig {
    /// Sample rate
    pub sample_rate: u32,
    /// Analysis window size
    pub window_size: usize,
    /// Hop size
    pub hop_size: usize,
    /// Minimum frequency to detect (Hz)
    pub min_freq: f32,
    /// Maximum frequency to detect (Hz)
    pub max_freq: f32,
    /// Minimum note duration (samples)
    pub min_duration: usize,
    /// Detection algorithm
    pub algorithm: DetectionAlgorithm,
    /// Maximum simultaneous voices
    pub max_voices: usize,
    /// Pitch tolerance for grouping (cents)
    pub pitch_tolerance_cents: f32,
    /// Use formant preservation
    pub preserve_formants: bool,
}

impl Default for PitchConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            window_size: 2048,
            hop_size: 512,
            min_freq: 50.0,
            max_freq: 4000.0,
            min_duration: 2048,
            algorithm: DetectionAlgorithm::Fusion,
            max_voices: 8,
            pitch_tolerance_cents: 50.0,
            preserve_formants: true,
        }
    }
}

/// Main polyphonic pitch engine
pub struct PolyphonicEngine {
    /// Configuration
    config: PitchConfig,
    /// Note detection state
    active_notes: Vec<NoteEvent>,
    /// Voice tracking state
    voice_states: Vec<Voice>,
    /// Next voice ID
    next_voice_id: usize,
}

impl PolyphonicEngine {
    /// Create new polyphonic engine
    pub fn new(sample_rate: u32) -> Self {
        Self::with_config(PitchConfig {
            sample_rate,
            ..Default::default()
        })
    }

    /// Create with configuration
    pub fn with_config(config: PitchConfig) -> Self {
        Self {
            config,
            active_notes: Vec::new(),
            voice_states: Vec::new(),
            next_voice_id: 0,
        }
    }

    /// Get configuration
    pub fn config(&self) -> &PitchConfig {
        &self.config
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.active_notes.clear();
        self.voice_states.clear();
        self.next_voice_id = 0;
    }
}

/// Convert frequency to MIDI note number
pub fn freq_to_midi(freq: f32) -> f32 {
    69.0 + 12.0 * (freq / 440.0).log2()
}

/// Convert MIDI note number to frequency
pub fn midi_to_freq(midi: f32) -> f32 {
    440.0 * 2.0f32.powf((midi - 69.0) / 12.0)
}

/// Convert frequency difference to cents
pub fn freq_to_cents(freq1: f32, freq2: f32) -> f32 {
    1200.0 * (freq2 / freq1).log2()
}

/// Note names
pub const NOTE_NAMES: [&str; 12] = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
];

/// Get note name from MIDI number
pub fn midi_to_note_name(midi: f32) -> String {
    let note = midi.round() as i32;
    let octave = note / 12 - 1;
    let note_idx = (note % 12) as usize;
    format!("{}{}", NOTE_NAMES[note_idx], octave)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_freq_to_midi() {
        // A4 = 440 Hz = MIDI 69
        assert!((freq_to_midi(440.0) - 69.0).abs() < 0.01);

        // C4 = 261.63 Hz = MIDI 60
        assert!((freq_to_midi(261.63) - 60.0).abs() < 0.1);
    }

    #[test]
    fn test_midi_to_freq() {
        assert!((midi_to_freq(69.0) - 440.0).abs() < 0.01);
        assert!((midi_to_freq(60.0) - 261.63).abs() < 0.1);
    }

    #[test]
    fn test_note_event() {
        let mut note = NoteEvent::new(60.0, 0, 48000);

        assert_eq!(note.pitch, 60.0);
        assert_eq!(note.start_sample, 0);
        assert_eq!(note.duration, 48000);

        note.shift_pitch(12.0);
        assert_eq!(note.pitch, 72.0);
    }

    #[test]
    fn test_note_name() {
        assert_eq!(midi_to_note_name(60.0), "C4");
        assert_eq!(midi_to_note_name(69.0), "A4");
        assert_eq!(midi_to_note_name(72.0), "C5");
    }

    #[test]
    fn test_engine_creation() {
        let engine = PolyphonicEngine::new(48000);
        assert_eq!(engine.config().sample_rate, 48000);
    }
}

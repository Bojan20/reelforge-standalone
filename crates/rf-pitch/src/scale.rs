//! Musical scales and pitch quantization
//!
//! Provides scale definitions and pitch correction utilities.

use serde::{Deserialize, Serialize};

/// Musical scale types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ScaleType {
    /// Chromatic (all 12 notes)
    Chromatic,
    /// Major scale
    Major,
    /// Natural minor
    NaturalMinor,
    /// Harmonic minor
    HarmonicMinor,
    /// Melodic minor
    MelodicMinor,
    /// Pentatonic major
    PentatonicMajor,
    /// Pentatonic minor
    PentatonicMinor,
    /// Blues scale
    Blues,
    /// Dorian mode
    Dorian,
    /// Phrygian mode
    Phrygian,
    /// Lydian mode
    Lydian,
    /// Mixolydian mode
    Mixolydian,
    /// Locrian mode
    Locrian,
    /// Whole tone
    WholeTone,
    /// Diminished (half-whole)
    DiminishedHalfWhole,
    /// Diminished (whole-half)
    DiminishedWholeHalf,
}

/// Musical scale with root note
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Scale {
    /// Scale type
    pub scale_type: ScaleType,
    /// Root note (0-11, where 0=C, 1=C#, etc.)
    pub root: u8,
    /// Custom intervals (overrides scale_type if non-empty)
    pub custom_intervals: Vec<u8>,
    /// Notes allowed in scale (computed from type + root)
    allowed_notes: [bool; 12],
}

impl Scale {
    /// Create new scale
    pub fn new(scale_type: ScaleType, root: u8) -> Self {
        let root = root % 12;
        let mut scale = Self {
            scale_type,
            root,
            custom_intervals: Vec::new(),
            allowed_notes: [false; 12],
        };
        scale.compute_allowed_notes();
        scale
    }

    /// Create chromatic scale
    pub fn chromatic() -> Self {
        Self::new(ScaleType::Chromatic, 0)
    }

    /// Create major scale
    pub fn major(root: u8) -> Self {
        Self::new(ScaleType::Major, root)
    }

    /// Create minor scale
    pub fn minor(root: u8) -> Self {
        Self::new(ScaleType::NaturalMinor, root)
    }

    /// Create pentatonic major
    pub fn pentatonic_major(root: u8) -> Self {
        Self::new(ScaleType::PentatonicMajor, root)
    }

    /// Create pentatonic minor
    pub fn pentatonic_minor(root: u8) -> Self {
        Self::new(ScaleType::PentatonicMinor, root)
    }

    /// Create blues scale
    pub fn blues(root: u8) -> Self {
        Self::new(ScaleType::Blues, root)
    }

    /// Create custom scale from intervals
    pub fn custom(root: u8, intervals: Vec<u8>) -> Self {
        let mut scale = Self {
            scale_type: ScaleType::Chromatic, // unused
            root: root % 12,
            custom_intervals: intervals,
            allowed_notes: [false; 12],
        };
        scale.compute_allowed_notes();
        scale
    }

    /// Get intervals for scale type
    fn get_intervals(&self) -> Vec<u8> {
        if !self.custom_intervals.is_empty() {
            return self.custom_intervals.clone();
        }

        match self.scale_type {
            ScaleType::Chromatic => vec![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            ScaleType::Major => vec![0, 2, 4, 5, 7, 9, 11],
            ScaleType::NaturalMinor => vec![0, 2, 3, 5, 7, 8, 10],
            ScaleType::HarmonicMinor => vec![0, 2, 3, 5, 7, 8, 11],
            ScaleType::MelodicMinor => vec![0, 2, 3, 5, 7, 9, 11],
            ScaleType::PentatonicMajor => vec![0, 2, 4, 7, 9],
            ScaleType::PentatonicMinor => vec![0, 3, 5, 7, 10],
            ScaleType::Blues => vec![0, 3, 5, 6, 7, 10],
            ScaleType::Dorian => vec![0, 2, 3, 5, 7, 9, 10],
            ScaleType::Phrygian => vec![0, 1, 3, 5, 7, 8, 10],
            ScaleType::Lydian => vec![0, 2, 4, 6, 7, 9, 11],
            ScaleType::Mixolydian => vec![0, 2, 4, 5, 7, 9, 10],
            ScaleType::Locrian => vec![0, 1, 3, 5, 6, 8, 10],
            ScaleType::WholeTone => vec![0, 2, 4, 6, 8, 10],
            ScaleType::DiminishedHalfWhole => vec![0, 1, 3, 4, 6, 7, 9, 10],
            ScaleType::DiminishedWholeHalf => vec![0, 2, 3, 5, 6, 8, 9, 11],
        }
    }

    /// Compute allowed notes based on scale type and root
    fn compute_allowed_notes(&mut self) {
        self.allowed_notes = [false; 12];
        for interval in self.get_intervals() {
            let note = (self.root + interval) % 12;
            self.allowed_notes[note as usize] = true;
        }
    }

    /// Check if a MIDI note is in the scale
    pub fn contains(&self, midi_note: f32) -> bool {
        let note_class = (midi_note.round() as i32 % 12 + 12) % 12;
        self.allowed_notes[note_class as usize]
    }

    /// Quantize MIDI note to nearest scale degree
    pub fn quantize(&self, midi_note: f32) -> f32 {
        if self.scale_type == ScaleType::Chromatic {
            return midi_note.round();
        }

        let octave = (midi_note / 12.0).floor() * 12.0;
        let note_in_octave = midi_note - octave;

        // Find nearest scale note
        let mut best_note = note_in_octave.round();
        let mut min_dist = f32::MAX;

        for semitone in 0..12 {
            if self.allowed_notes[semitone] {
                let dist = (note_in_octave - semitone as f32).abs();
                if dist < min_dist {
                    min_dist = dist;
                    best_note = semitone as f32;
                }
                // Also check octave wrap
                let dist_up = (note_in_octave - (semitone as f32 + 12.0)).abs();
                if dist_up < min_dist {
                    min_dist = dist_up;
                    best_note = semitone as f32;
                }
                let dist_down = (note_in_octave - (semitone as f32 - 12.0)).abs();
                if dist_down < min_dist {
                    min_dist = dist_down;
                    best_note = semitone as f32;
                }
            }
        }

        octave + best_note
    }

    /// Get all notes in scale (as pitch classes 0-11)
    pub fn get_notes(&self) -> Vec<u8> {
        self.allowed_notes
            .iter()
            .enumerate()
            .filter_map(|(i, &allowed)| if allowed { Some(i as u8) } else { None })
            .collect()
    }

    /// Get scale name
    pub fn name(&self) -> String {
        let root_names = [
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        ];
        let scale_name = match self.scale_type {
            ScaleType::Chromatic => "Chromatic",
            ScaleType::Major => "Major",
            ScaleType::NaturalMinor => "Minor",
            ScaleType::HarmonicMinor => "Harmonic Minor",
            ScaleType::MelodicMinor => "Melodic Minor",
            ScaleType::PentatonicMajor => "Pentatonic Major",
            ScaleType::PentatonicMinor => "Pentatonic Minor",
            ScaleType::Blues => "Blues",
            ScaleType::Dorian => "Dorian",
            ScaleType::Phrygian => "Phrygian",
            ScaleType::Lydian => "Lydian",
            ScaleType::Mixolydian => "Mixolydian",
            ScaleType::Locrian => "Locrian",
            ScaleType::WholeTone => "Whole Tone",
            ScaleType::DiminishedHalfWhole => "Diminished (H-W)",
            ScaleType::DiminishedWholeHalf => "Diminished (W-H)",
        };
        format!("{} {}", root_names[self.root as usize], scale_name)
    }
}

/// Key signature for automatic scale detection
#[derive(Debug, Clone)]
pub struct KeyDetector {
    /// Krumhansl-Schmuckler key profiles
    major_profile: [f32; 12],
    minor_profile: [f32; 12],
    /// Note histogram
    histogram: [f32; 12],
    /// Total notes counted
    total_notes: usize,
}

impl Default for KeyDetector {
    fn default() -> Self {
        Self::new()
    }
}

impl KeyDetector {
    /// Create new key detector with Krumhansl-Schmuckler profiles
    pub fn new() -> Self {
        Self {
            major_profile: [
                6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
            ],
            minor_profile: [
                6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
            ],
            histogram: [0.0; 12],
            total_notes: 0,
        }
    }

    /// Reset histogram
    pub fn reset(&mut self) {
        self.histogram = [0.0; 12];
        self.total_notes = 0;
    }

    /// Add note to histogram
    pub fn add_note(&mut self, midi_note: f32, weight: f32) {
        let note_class = ((midi_note.round() as i32) % 12 + 12) % 12;
        self.histogram[note_class as usize] += weight;
        self.total_notes += 1;
    }

    /// Add notes from pitch contour
    pub fn add_contour(&mut self, pitches: &[f32]) {
        for &pitch in pitches {
            if pitch > 0.0 {
                self.add_note(pitch, 1.0);
            }
        }
    }

    /// Detect key (returns root, is_major, correlation)
    pub fn detect(&self) -> (u8, bool, f32) {
        if self.total_notes == 0 {
            return (0, true, 0.0);
        }

        // Normalize histogram
        let sum: f32 = self.histogram.iter().sum();
        let normalized: Vec<f32> = if sum > 0.0 {
            self.histogram.iter().map(|&x| x / sum).collect()
        } else {
            return (0, true, 0.0);
        };

        let mut best_root = 0;
        let mut best_is_major = true;
        let mut best_correlation = -1.0f32;

        for root in 0..12 {
            // Rotate histogram to test this root
            let rotated: Vec<f32> = (0..12).map(|i| normalized[(i + root) % 12]).collect();

            // Correlation with major profile
            let major_corr = self.correlation(&rotated, &self.major_profile);
            if major_corr > best_correlation {
                best_correlation = major_corr;
                best_root = root as u8;
                best_is_major = true;
            }

            // Correlation with minor profile
            let minor_corr = self.correlation(&rotated, &self.minor_profile);
            if minor_corr > best_correlation {
                best_correlation = minor_corr;
                best_root = root as u8;
                best_is_major = false;
            }
        }

        (best_root, best_is_major, best_correlation)
    }

    /// Detect and return scale
    pub fn detect_scale(&self) -> Scale {
        let (root, is_major, _) = self.detect();
        if is_major {
            Scale::major(root)
        } else {
            Scale::minor(root)
        }
    }

    /// Pearson correlation coefficient
    fn correlation(&self, a: &[f32], b: &[f32; 12]) -> f32 {
        let n = 12.0;
        let sum_a: f32 = a.iter().sum();
        let sum_b: f32 = b.iter().sum();
        let mean_a = sum_a / n;
        let mean_b = sum_b / n;

        let mut cov = 0.0f32;
        let mut var_a = 0.0f32;
        let mut var_b = 0.0f32;

        for i in 0..12 {
            let da = a[i] - mean_a;
            let db = b[i] - mean_b;
            cov += da * db;
            var_a += da * da;
            var_b += db * db;
        }

        if var_a > 0.0 && var_b > 0.0 {
            cov / (var_a.sqrt() * var_b.sqrt())
        } else {
            0.0
        }
    }
}

/// Chord detection
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChordQuality {
    /// Major triad
    Major,
    /// Minor triad
    Minor,
    /// Diminished triad
    Diminished,
    /// Augmented triad
    Augmented,
    /// Dominant 7th
    Dominant7,
    /// Major 7th
    Major7,
    /// Minor 7th
    Minor7,
    /// Suspended 2
    Sus2,
    /// Suspended 4
    Sus4,
    /// Power chord (5th)
    Power,
}

/// Detected chord
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chord {
    /// Root note (0-11)
    pub root: u8,
    /// Chord quality
    pub quality: ChordQuality,
    /// Bass note if different from root
    pub bass: Option<u8>,
    /// Detection confidence
    pub confidence: f32,
}

impl Chord {
    /// Get chord name
    pub fn name(&self) -> String {
        let note_names = [
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        ];
        let quality_str = match self.quality {
            ChordQuality::Major => "",
            ChordQuality::Minor => "m",
            ChordQuality::Diminished => "dim",
            ChordQuality::Augmented => "aug",
            ChordQuality::Dominant7 => "7",
            ChordQuality::Major7 => "maj7",
            ChordQuality::Minor7 => "m7",
            ChordQuality::Sus2 => "sus2",
            ChordQuality::Sus4 => "sus4",
            ChordQuality::Power => "5",
        };

        let mut name = format!("{}{}", note_names[self.root as usize], quality_str);

        if let Some(bass) = self.bass {
            if bass != self.root {
                name.push('/');
                name.push_str(note_names[bass as usize]);
            }
        }

        name
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scale_creation() {
        let scale = Scale::major(0); // C major
        assert!(scale.contains(60.0)); // C
        assert!(scale.contains(62.0)); // D
        assert!(scale.contains(64.0)); // E
        assert!(!scale.contains(61.0)); // C# not in C major
        assert!(!scale.contains(63.0)); // D# not in C major
    }

    #[test]
    fn test_scale_quantization() {
        let scale = Scale::major(0); // C major

        // C# should quantize to C or D
        let quantized = scale.quantize(61.0);
        assert!(quantized == 60.0 || quantized == 62.0);

        // D should stay D
        assert_eq!(scale.quantize(62.0), 62.0);
    }

    #[test]
    fn test_minor_scale() {
        let scale = Scale::minor(9); // A minor

        // A minor: A B C D E F G
        assert!(scale.contains(69.0)); // A
        assert!(scale.contains(71.0)); // B
        assert!(scale.contains(72.0)); // C
        assert!(!scale.contains(70.0)); // A# not in A minor
    }

    #[test]
    fn test_pentatonic() {
        let scale = Scale::pentatonic_major(0); // C pentatonic

        // C D E G A
        assert!(scale.contains(60.0)); // C
        assert!(scale.contains(62.0)); // D
        assert!(scale.contains(64.0)); // E
        assert!(!scale.contains(65.0)); // F not in C pentatonic
    }

    #[test]
    fn test_key_detection() {
        let mut detector = KeyDetector::new();

        // Add C major scale notes
        for note in [60.0, 62.0, 64.0, 65.0, 67.0, 69.0, 71.0] {
            detector.add_note(note, 1.0);
        }

        let (root, is_major, confidence) = detector.detect();
        assert_eq!(root, 0); // C
        assert!(is_major);
        assert!(confidence > 0.5);
    }

    #[test]
    fn test_scale_name() {
        assert_eq!(Scale::major(0).name(), "C Major");
        assert_eq!(Scale::minor(9).name(), "A Minor");
        assert_eq!(Scale::blues(7).name(), "G Blues");
    }

    #[test]
    fn test_chord_name() {
        let chord = Chord {
            root: 0,
            quality: ChordQuality::Major,
            bass: None,
            confidence: 1.0,
        };
        assert_eq!(chord.name(), "C");

        let chord = Chord {
            root: 9,
            quality: ChordQuality::Minor7,
            bass: None,
            confidence: 1.0,
        };
        assert_eq!(chord.name(), "Am7");

        let chord = Chord {
            root: 0,
            quality: ChordQuality::Major,
            bass: Some(7),
            confidence: 1.0,
        };
        assert_eq!(chord.name(), "C/G");
    }

    #[test]
    fn test_chromatic_scale() {
        let scale = Scale::chromatic();

        // All notes should be in chromatic scale
        for i in 0..12 {
            assert!(scale.contains(60.0 + i as f32));
        }
    }
}

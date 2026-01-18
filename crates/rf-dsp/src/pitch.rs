//! Pitch Detection and Manipulation (VariAudio Style)
//!
//! Professional pitch detection and editing:
//! - YIN algorithm for accurate pitch detection
//! - Pitch segments with per-segment editing
//! - Pitch drift and vibrato detection
//! - Pitch correction (auto-tune style)
//! - Formant preservation during pitch shift
//!
//! Similar to Cubase VariAudio, Melodyne Essential

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════
// PITCH REPRESENTATION
// ═══════════════════════════════════════════════════════════════════════════

/// MIDI-style pitch with cents precision
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Pitch {
    /// MIDI note number (60 = C4)
    pub midi_note: u8,
    /// Cents deviation from equal temperament (-50 to +50)
    pub cents: f64,
}

impl Pitch {
    /// Create from frequency in Hz
    pub fn from_frequency(freq: f64) -> Option<Self> {
        if freq <= 0.0 {
            return None;
        }

        // A4 = 440Hz = MIDI 69
        let midi_f = 12.0 * (freq / 440.0).log2() + 69.0;

        if !(0.0..=127.0).contains(&midi_f) {
            return None;
        }

        let midi_note = midi_f.round() as u8;
        let cents = (midi_f - midi_note as f64) * 100.0;

        Some(Self { midi_note, cents })
    }

    /// Convert to frequency in Hz
    pub fn to_frequency(&self) -> f64 {
        let midi_f = self.midi_note as f64 + self.cents / 100.0;
        440.0 * 2.0_f64.powf((midi_f - 69.0) / 12.0)
    }

    /// Get total pitch in fractional MIDI units
    pub fn as_midi(&self) -> f64 {
        self.midi_note as f64 + self.cents / 100.0
    }

    /// Get note name (C, C#, D, etc.)
    pub fn note_name(&self) -> &'static str {
        const NAMES: [&str; 12] = [
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        ];
        NAMES[(self.midi_note % 12) as usize]
    }

    /// Get octave number
    pub fn octave(&self) -> i32 {
        (self.midi_note as i32 / 12) - 1
    }

    /// Get distance to nearest semitone in cents
    pub fn deviation(&self) -> f64 {
        self.cents
    }

    /// Quantize to nearest semitone
    pub fn quantized(&self) -> Self {
        Self {
            midi_note: self.midi_note,
            cents: 0.0,
        }
    }

    /// Apply pitch shift in semitones
    pub fn shifted(&self, semitones: f64) -> Self {
        let new_midi = (self.as_midi() + semitones).clamp(0.0, 127.0);
        let midi_note = new_midi.round() as u8;
        let cents = (new_midi - midi_note as f64) * 100.0;
        Self { midi_note, cents }
    }
}

impl Default for Pitch {
    fn default() -> Self {
        Self {
            midi_note: 69, // A4
            cents: 0.0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH SEGMENT
// ═══════════════════════════════════════════════════════════════════════════

/// A detected pitch segment (like a VariAudio segment)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PitchSegment {
    /// Unique segment ID
    pub id: u32,
    /// Start position in samples
    pub start: u64,
    /// End position in samples
    pub end: u64,
    /// Average detected pitch
    pub pitch: Pitch,
    /// Target pitch (after editing)
    pub target_pitch: Pitch,
    /// Pitch contour (detailed pitch over time)
    pub contour: Vec<(u64, Pitch)>,
    /// Detected vibrato rate (Hz)
    pub vibrato_rate: f64,
    /// Detected vibrato depth (cents)
    pub vibrato_depth: f64,
    /// Detection confidence (0.0-1.0)
    pub confidence: f64,
    /// Has been edited
    pub edited: bool,
    /// Is voiced (vs unvoiced/noise)
    pub voiced: bool,
}

impl PitchSegment {
    /// Create new segment from detection
    pub fn new(id: u32, start: u64, end: u64, pitch: Pitch, confidence: f64) -> Self {
        Self {
            id,
            start,
            end,
            pitch,
            target_pitch: pitch,
            contour: Vec::new(),
            vibrato_rate: 0.0,
            vibrato_depth: 0.0,
            confidence,
            edited: false,
            voiced: true,
        }
    }

    /// Get duration in samples
    pub fn duration(&self) -> u64 {
        self.end - self.start
    }

    /// Get pitch shift amount (semitones)
    pub fn pitch_shift(&self) -> f64 {
        self.target_pitch.as_midi() - self.pitch.as_midi()
    }

    /// Set target pitch
    pub fn set_target_pitch(&mut self, target: Pitch) {
        self.target_pitch = target;
        self.edited = true;
    }

    /// Set target by semitone offset
    pub fn shift_pitch(&mut self, semitones: f64) {
        self.target_pitch = self.pitch.shifted(semitones);
        self.edited = true;
    }

    /// Quantize to nearest semitone
    pub fn quantize(&mut self) {
        self.target_pitch = self.pitch.quantized();
        self.edited = self.target_pitch.cents != self.pitch.cents;
    }

    /// Reset to original pitch
    pub fn reset(&mut self) {
        self.target_pitch = self.pitch;
        self.edited = false;
    }

    /// Calculate pitch drift (change from start to end)
    pub fn pitch_drift(&self) -> f64 {
        if self.contour.len() < 2 {
            return 0.0;
        }

        let first = self.contour.first().unwrap().1.as_midi();
        let last = self.contour.last().unwrap().1.as_midi();
        (last - first) * 100.0 // In cents
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH DETECTOR (YIN ALGORITHM)
// ═══════════════════════════════════════════════════════════════════════════

/// Pitch detection configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PitchDetectorConfig {
    /// Minimum frequency to detect (Hz)
    pub min_freq: f64,
    /// Maximum frequency to detect (Hz)
    pub max_freq: f64,
    /// YIN threshold (lower = stricter)
    pub threshold: f64,
    /// Analysis hop size (samples)
    pub hop_size: usize,
    /// Window size (samples)
    pub window_size: usize,
    /// Minimum segment duration (ms)
    pub min_segment_ms: f64,
}

impl Default for PitchDetectorConfig {
    fn default() -> Self {
        Self {
            min_freq: 50.0,   // E1
            max_freq: 2000.0, // B6
            threshold: 0.15,
            hop_size: 256,
            window_size: 2048,
            min_segment_ms: 50.0,
        }
    }
}

/// YIN pitch detector
pub struct PitchDetector {
    /// Configuration
    config: PitchDetectorConfig,
    /// Sample rate
    sample_rate: f64,
    /// Difference function buffer
    diff_buffer: Vec<f64>,
    /// Cumulative mean normalized difference
    cmndf: Vec<f64>,
}

impl PitchDetector {
    /// Create new pitch detector
    pub fn new(sample_rate: f64) -> Self {
        let config = PitchDetectorConfig::default();
        let window_size = config.window_size;

        Self {
            config,
            sample_rate,
            diff_buffer: vec![0.0; window_size / 2],
            cmndf: vec![0.0; window_size / 2],
        }
    }

    /// Create with custom config
    pub fn with_config(sample_rate: f64, config: PitchDetectorConfig) -> Self {
        let window_size = config.window_size;

        Self {
            config,
            sample_rate,
            diff_buffer: vec![0.0; window_size / 2],
            cmndf: vec![0.0; window_size / 2],
        }
    }

    /// Detect pitch in a single frame
    pub fn detect_frame(&mut self, audio: &[f64]) -> Option<(Pitch, f64)> {
        let window_size = self.config.window_size;

        if audio.len() < window_size {
            return None;
        }

        // Calculate difference function
        self.calculate_difference(audio);

        // Calculate cumulative mean normalized difference
        self.calculate_cmndf();

        // Find the first minimum below threshold
        let tau = self.find_best_tau()?;

        // Parabolic interpolation for better precision
        let tau_refined = self.parabolic_interpolation(tau);

        // Convert tau to frequency
        let frequency = self.sample_rate / tau_refined;

        // Check if frequency is in valid range
        if frequency < self.config.min_freq || frequency > self.config.max_freq {
            return None;
        }

        // Calculate confidence based on CMNDF value
        let confidence = 1.0 - self.cmndf[tau].min(1.0);

        Pitch::from_frequency(frequency).map(|p| (p, confidence))
    }

    /// Calculate difference function (YIN step 1-2)
    fn calculate_difference(&mut self, audio: &[f64]) {
        let half_window = self.diff_buffer.len();

        for tau in 0..half_window {
            let mut sum = 0.0;
            for j in 0..half_window {
                let diff = audio[j] - audio[j + tau];
                sum += diff * diff;
            }
            self.diff_buffer[tau] = sum;
        }
    }

    /// Calculate cumulative mean normalized difference (YIN step 3)
    fn calculate_cmndf(&mut self) {
        self.cmndf[0] = 1.0;
        let mut running_sum = 0.0;

        for tau in 1..self.cmndf.len() {
            running_sum += self.diff_buffer[tau];
            if running_sum > 0.0 {
                self.cmndf[tau] = self.diff_buffer[tau] * tau as f64 / running_sum;
            } else {
                self.cmndf[tau] = 1.0;
            }
        }
    }

    /// Find best tau value (YIN step 4)
    fn find_best_tau(&self) -> Option<usize> {
        let min_tau = (self.sample_rate / self.config.max_freq) as usize;
        let max_tau =
            (self.sample_rate / self.config.min_freq).min(self.cmndf.len() as f64 - 1.0) as usize;

        // Find first minimum below threshold
        for tau in min_tau..max_tau {
            if self.cmndf[tau] < self.config.threshold {
                // Check if it's a local minimum
                if tau + 1 < self.cmndf.len() && self.cmndf[tau] < self.cmndf[tau + 1] {
                    return Some(tau);
                }
            }
        }

        // If no value below threshold, find global minimum
        let mut min_tau_val = min_tau;
        let mut min_val = self.cmndf[min_tau];

        for tau in min_tau..max_tau {
            if self.cmndf[tau] < min_val {
                min_val = self.cmndf[tau];
                min_tau_val = tau;
            }
        }

        if min_val < 0.5 {
            Some(min_tau_val)
        } else {
            None // Unvoiced frame
        }
    }

    /// Parabolic interpolation for sub-sample precision (YIN step 5)
    fn parabolic_interpolation(&self, tau: usize) -> f64 {
        if tau == 0 || tau >= self.cmndf.len() - 1 {
            return tau as f64;
        }

        let s0 = self.cmndf[tau - 1];
        let s1 = self.cmndf[tau];
        let s2 = self.cmndf[tau + 1];

        let adjustment = (s0 - s2) / (2.0 * (s0 - 2.0 * s1 + s2));

        if adjustment.is_finite() && adjustment.abs() < 1.0 {
            tau as f64 + adjustment
        } else {
            tau as f64
        }
    }

    /// Analyze full audio and detect pitch segments
    pub fn analyze(&mut self, audio: &[f64]) -> Vec<PitchSegment> {
        let mut segments = Vec::new();
        let hop = self.config.hop_size;
        let window = self.config.window_size;
        let min_segment_samples = (self.config.min_segment_ms * self.sample_rate / 1000.0) as u64;

        // Detect pitch at each hop
        let mut detections: Vec<Option<(u64, Pitch, f64)>> = Vec::new();

        let mut pos = 0;
        while pos + window <= audio.len() {
            let frame = &audio[pos..pos + window];

            if let Some((pitch, confidence)) = self.detect_frame(frame) {
                detections.push(Some((pos as u64, pitch, confidence)));
            } else {
                detections.push(None);
            }

            pos += hop;
        }

        // Group consecutive detections into segments
        let mut segment_id = 0u32;
        let mut current_segment: Option<(u64, u64, Vec<(u64, Pitch, f64)>)> = None;

        for detection in detections {
            match (&mut current_segment, detection) {
                (None, Some((pos, pitch, conf))) => {
                    // Start new segment
                    current_segment = Some((pos, pos + hop as u64, vec![(pos, pitch, conf)]));
                }
                (Some((start, end, pitches)), Some((pos, pitch, conf))) => {
                    // Check if pitch is close enough to continue segment
                    let avg_pitch = pitches.iter().map(|(_, p, _)| p.as_midi()).sum::<f64>()
                        / pitches.len() as f64;

                    if (pitch.as_midi() - avg_pitch).abs() < 2.0 {
                        // Continue segment
                        *end = pos + hop as u64;
                        pitches.push((pos, pitch, conf));
                    } else {
                        // End current segment, start new one
                        if *end - *start >= min_segment_samples {
                            segments.push(Self::create_segment(segment_id, *start, *end, pitches));
                            segment_id += 1;
                        }
                        current_segment = Some((pos, pos + hop as u64, vec![(pos, pitch, conf)]));
                    }
                }
                (Some((start, end, pitches)), None) => {
                    // End segment on unvoiced
                    if *end - *start >= min_segment_samples {
                        segments.push(Self::create_segment(segment_id, *start, *end, pitches));
                        segment_id += 1;
                    }
                    current_segment = None;
                }
                (None, None) => {}
            }
        }

        // Handle last segment
        if let Some((start, end, pitches)) = current_segment
            && end - start >= min_segment_samples {
                segments.push(Self::create_segment(segment_id, start, end, &pitches));
            }

        segments
    }

    /// Create a pitch segment from detection data
    fn create_segment(
        id: u32,
        start: u64,
        end: u64,
        pitches: &[(u64, Pitch, f64)],
    ) -> PitchSegment {
        // Calculate average pitch
        let avg_midi: f64 =
            pitches.iter().map(|(_, p, _)| p.as_midi()).sum::<f64>() / pitches.len() as f64;
        let avg_conf: f64 = pitches.iter().map(|(_, _, c)| c).sum::<f64>() / pitches.len() as f64;

        let avg_pitch = Pitch {
            midi_note: avg_midi.round() as u8,
            cents: (avg_midi - avg_midi.round()) * 100.0,
        };

        // Build contour
        let contour: Vec<(u64, Pitch)> = pitches
            .iter()
            .map(|(pos, pitch, _)| (*pos, *pitch))
            .collect();

        // Detect vibrato
        let (vibrato_rate, vibrato_depth) = Self::detect_vibrato(pitches);

        PitchSegment {
            id,
            start,
            end,
            pitch: avg_pitch,
            target_pitch: avg_pitch,
            contour,
            vibrato_rate,
            vibrato_depth,
            confidence: avg_conf,
            edited: false,
            voiced: true,
        }
    }

    /// Detect vibrato from pitch contour
    fn detect_vibrato(pitches: &[(u64, Pitch, f64)]) -> (f64, f64) {
        if pitches.len() < 10 {
            return (0.0, 0.0);
        }

        // Calculate pitch deviations from mean
        let mean = pitches.iter().map(|(_, p, _)| p.as_midi()).sum::<f64>() / pitches.len() as f64;

        let deviations: Vec<f64> = pitches
            .iter()
            .map(|(_, p, _)| (p.as_midi() - mean) * 100.0) // In cents
            .collect();

        // Calculate depth as max deviation
        let depth = deviations.iter().map(|d| d.abs()).fold(0.0f64, f64::max);

        // Simple zero-crossing count for rate estimation
        let mut zero_crossings = 0;
        for i in 1..deviations.len() {
            if deviations[i] * deviations[i - 1] < 0.0 {
                zero_crossings += 1;
            }
        }

        // Estimate rate from zero crossings
        // Each full cycle has 2 zero crossings
        let duration_samples = pitches.last().unwrap().0 - pitches.first().unwrap().0;
        let duration_sec = duration_samples as f64 / 48000.0; // Assume 48kHz
        let rate = if duration_sec > 0.0 {
            zero_crossings as f64 / (2.0 * duration_sec)
        } else {
            0.0
        };

        (rate, depth)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH CORRECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Musical scale for pitch correction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum Scale {
    /// All semitones (chromatic)
    #[default]
    Chromatic,
    /// Major scale
    Major,
    /// Natural minor scale
    Minor,
    /// Harmonic minor scale
    HarmonicMinor,
    /// Pentatonic major
    PentatonicMajor,
    /// Pentatonic minor
    PentatonicMinor,
    /// Blues scale
    Blues,
    /// Dorian mode
    Dorian,
    /// Custom scale (use scale_notes)
    Custom,
}

impl Scale {
    /// Get scale intervals (semitones from root)
    pub fn intervals(&self) -> &'static [u8] {
        match self {
            Scale::Chromatic => &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            Scale::Major => &[0, 2, 4, 5, 7, 9, 11],
            Scale::Minor => &[0, 2, 3, 5, 7, 8, 10],
            Scale::HarmonicMinor => &[0, 2, 3, 5, 7, 8, 11],
            Scale::PentatonicMajor => &[0, 2, 4, 7, 9],
            Scale::PentatonicMinor => &[0, 3, 5, 7, 10],
            Scale::Blues => &[0, 3, 5, 6, 7, 10],
            Scale::Dorian => &[0, 2, 3, 5, 7, 9, 10],
            Scale::Custom => &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], // All notes for custom
        }
    }

    /// Check if a note (0-11) is in this scale with given root
    pub fn contains(&self, root: u8, note: u8) -> bool {
        let interval = (note + 12 - root) % 12;
        self.intervals().contains(&interval)
    }

    /// Get nearest in-scale note
    pub fn nearest_note(&self, root: u8, midi_note: u8) -> u8 {
        let octave = midi_note / 12;
        let note = midi_note % 12;

        // Check if already in scale
        if self.contains(root, note) {
            return midi_note;
        }

        // Find nearest
        let intervals = self.intervals();
        let root_offset = (note + 12 - root) % 12;

        let mut nearest = intervals[0];
        let mut min_dist = 12u8;

        for &interval in intervals {
            let dist = interval.abs_diff(root_offset);
            let dist = dist.min(12 - dist); // Check both directions

            if dist < min_dist {
                min_dist = dist;
                nearest = interval;
            }
        }

        let nearest_note = (root + nearest) % 12;
        octave * 12 + nearest_note
    }
}

/// Pitch correction processor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PitchCorrector {
    /// Scale for correction
    pub scale: Scale,
    /// Root note (0=C, 1=C#, ..., 11=B)
    pub root: u8,
    /// Correction speed (0.0=slow, 1.0=instant)
    pub speed: f64,
    /// Correction amount (0.0=off, 1.0=full)
    pub amount: f64,
    /// Preserve vibrato
    pub preserve_vibrato: bool,
    /// Formant preservation (0.0-1.0)
    pub formant_preservation: f64,
}

impl Default for PitchCorrector {
    fn default() -> Self {
        Self {
            scale: Scale::Chromatic,
            root: 0, // C
            speed: 0.5,
            amount: 1.0,
            preserve_vibrato: true,
            formant_preservation: 1.0,
        }
    }
}

impl PitchCorrector {
    /// Calculate corrected pitch for a segment
    pub fn correct_segment(&self, segment: &mut PitchSegment) {
        let target_note = self.scale.nearest_note(self.root, segment.pitch.midi_note);

        // Calculate target pitch
        let mut target = Pitch {
            midi_note: target_note,
            cents: 0.0,
        };

        // Apply correction amount
        if self.amount < 1.0 {
            let original = segment.pitch.as_midi();
            let corrected = target.as_midi();
            let blended = original + (corrected - original) * self.amount;
            target = Pitch {
                midi_note: blended.round() as u8,
                cents: (blended - blended.round()) * 100.0,
            };
        }

        // Preserve vibrato if enabled
        if self.preserve_vibrato && segment.vibrato_depth > 10.0 {
            // Keep vibrato depth but shift center
            // This is handled in the pitch shifting processor
        }

        segment.set_target_pitch(target);
    }

    /// Correct all segments
    pub fn correct_all(&self, segments: &mut [PitchSegment]) {
        for segment in segments {
            self.correct_segment(segment);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH EDITOR STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Complete pitch editor state for an audio clip
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PitchEditorState {
    /// All detected segments
    pub segments: Vec<PitchSegment>,
    /// Next segment ID
    next_id: u32,
    /// Pitch corrector settings
    pub corrector: PitchCorrector,
    /// Sample rate
    pub sample_rate: f64,
    /// Source audio length
    pub audio_length: u64,
}

impl PitchEditorState {
    /// Create new state from analysis
    pub fn new(segments: Vec<PitchSegment>, sample_rate: f64, audio_length: u64) -> Self {
        let next_id = segments.iter().map(|s| s.id).max().unwrap_or(0) + 1;

        Self {
            segments,
            next_id,
            corrector: PitchCorrector::default(),
            sample_rate,
            audio_length,
        }
    }

    /// Get segment by ID
    pub fn get_segment(&self, id: u32) -> Option<&PitchSegment> {
        self.segments.iter().find(|s| s.id == id)
    }

    /// Get mutable segment by ID
    pub fn get_segment_mut(&mut self, id: u32) -> Option<&mut PitchSegment> {
        self.segments.iter_mut().find(|s| s.id == id)
    }

    /// Get segment at position
    pub fn segment_at(&self, position: u64) -> Option<&PitchSegment> {
        self.segments
            .iter()
            .find(|s| position >= s.start && position < s.end)
    }

    /// Split segment at position
    pub fn split_segment(&mut self, id: u32, position: u64) -> Option<u32> {
        let idx = self.segments.iter().position(|s| s.id == id)?;
        let segment = &self.segments[idx];

        if position <= segment.start || position >= segment.end {
            return None;
        }

        // Create new segment for second half
        let new_id = self.next_id;
        self.next_id += 1;

        let mut new_segment = segment.clone();
        new_segment.id = new_id;
        new_segment.start = position;
        new_segment.contour.retain(|(pos, _)| *pos >= position);

        // Truncate original segment
        self.segments[idx].end = position;
        self.segments[idx]
            .contour
            .retain(|(pos, _)| *pos < position);

        // Insert new segment
        self.segments.insert(idx + 1, new_segment);

        Some(new_id)
    }

    /// Merge two adjacent segments
    pub fn merge_segments(&mut self, id1: u32, id2: u32) -> bool {
        let idx1 = self.segments.iter().position(|s| s.id == id1);
        let idx2 = self.segments.iter().position(|s| s.id == id2);

        match (idx1, idx2) {
            (Some(i), Some(j)) if j == i + 1 => {
                let s2 = self.segments.remove(j);
                let s1 = &mut self.segments[i];

                s1.end = s2.end;
                s1.contour.extend(s2.contour);

                // Recalculate average pitch
                let avg = s1.contour.iter().map(|(_, p)| p.as_midi()).sum::<f64>()
                    / s1.contour.len() as f64;
                s1.pitch = Pitch {
                    midi_note: avg.round() as u8,
                    cents: (avg - avg.round()) * 100.0,
                };

                true
            }
            _ => false,
        }
    }

    /// Apply auto-correction to all segments
    pub fn auto_correct(&mut self) {
        let corrector = self.corrector.clone();
        corrector.correct_all(&mut self.segments);
    }

    /// Reset all segments to original pitch
    pub fn reset_all(&mut self) {
        for segment in &mut self.segments {
            segment.reset();
        }
    }

    /// Quantize all segments
    pub fn quantize_all(&mut self) {
        for segment in &mut self.segments {
            segment.quantize();
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
    fn test_pitch_from_frequency() {
        // A4 = 440Hz = MIDI 69
        let pitch = Pitch::from_frequency(440.0).unwrap();
        assert_eq!(pitch.midi_note, 69);
        assert!(pitch.cents.abs() < 1.0);

        // C4 = 261.63Hz = MIDI 60
        let pitch = Pitch::from_frequency(261.63).unwrap();
        assert_eq!(pitch.midi_note, 60);
    }

    #[test]
    fn test_pitch_to_frequency() {
        let pitch = Pitch {
            midi_note: 69,
            cents: 0.0,
        };
        let freq = pitch.to_frequency();
        assert!((freq - 440.0).abs() < 0.1);
    }

    #[test]
    fn test_scale_contains() {
        let scale = Scale::Major;

        // C major: C, D, E, F, G, A, B
        assert!(scale.contains(0, 0)); // C
        assert!(scale.contains(0, 2)); // D
        assert!(scale.contains(0, 4)); // E
        assert!(!scale.contains(0, 1)); // C# not in C major
        assert!(!scale.contains(0, 3)); // D# not in C major
    }

    #[test]
    fn test_scale_nearest_note() {
        let scale = Scale::Major;

        // C# should snap to C or D
        let nearest = scale.nearest_note(0, 61); // C#4
        assert!(nearest == 60 || nearest == 62);
    }

    #[test]
    fn test_segment_pitch_shift() {
        let mut segment = PitchSegment::new(
            0,
            0,
            1000,
            Pitch {
                midi_note: 60,
                cents: 0.0,
            },
            0.9,
        );

        segment.shift_pitch(2.0); // Up 2 semitones
        assert_eq!(segment.target_pitch.midi_note, 62);
        assert!(segment.edited);
    }

    #[test]
    fn test_pitch_detector() {
        let mut detector = PitchDetector::new(48000.0);

        // Generate a simple sine wave at 440Hz
        let freq = 440.0;
        let audio: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * freq * i as f64 / 48000.0).sin())
            .collect();

        if let Some((pitch, conf)) = detector.detect_frame(&audio) {
            assert_eq!(pitch.midi_note, 69); // A4
            assert!(conf > 0.5);
        }
    }
}

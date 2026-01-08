//! Click Track / Metronome System
//!
//! Professional metronome like Cubase/Pro Tools:
//! - Customizable click sounds
//! - Accent on downbeat
//! - Pre-count/count-in
//! - Pattern-based clicks (subdivision)
//! - MIDI output option
//! - Volume control
//!
//! ## Click Patterns
//! - Standard: accent + normal beats
//! - Subdivided: 8ths, 16ths, triplets
//! - Custom: user-defined patterns

use std::sync::atomic::{AtomicBool, Ordering};

use rf_core::Sample;

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK SOUNDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Click sound type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClickSoundType {
    /// Downbeat accent
    Accent,
    /// Normal beat
    Beat,
    /// Subdivision click
    Subdivision,
}

/// Click sound sample
#[derive(Debug, Clone)]
pub struct ClickSound {
    /// Audio samples (mono)
    pub samples: Vec<f32>,
    /// Sample rate
    pub sample_rate: u32,
    /// Gain (linear)
    pub gain: f32,
}

impl ClickSound {
    /// Generate default click sound (short sine burst)
    pub fn default_accent(sample_rate: u32) -> Self {
        Self::generate_click(sample_rate, 1000.0, 0.015, 0.8)
    }

    pub fn default_beat(sample_rate: u32) -> Self {
        Self::generate_click(sample_rate, 800.0, 0.012, 0.5)
    }

    pub fn default_subdivision(sample_rate: u32) -> Self {
        Self::generate_click(sample_rate, 600.0, 0.008, 0.3)
    }

    /// Generate click sound
    fn generate_click(sample_rate: u32, freq: f32, duration: f32, gain: f32) -> Self {
        let num_samples = (sample_rate as f32 * duration) as usize;
        let mut samples = Vec::with_capacity(num_samples);

        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            // Sine wave with exponential decay
            let envelope = (-t * 40.0).exp();
            let sample = (t * freq * std::f32::consts::TAU).sin() * envelope * gain;
            samples.push(sample);
        }

        Self {
            samples,
            sample_rate,
            gain: 1.0,
        }
    }

    /// Load from audio file (placeholder)
    pub fn from_file(_path: &str, sample_rate: u32) -> Self {
        // In real implementation, load and resample audio file
        Self::default_accent(sample_rate)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK PATTERN
// ═══════════════════════════════════════════════════════════════════════════════

/// Click subdivision pattern
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ClickPattern {
    /// Just quarter notes
    #[default]
    Quarter,
    /// Eighth notes
    Eighth,
    /// Sixteenth notes
    Sixteenth,
    /// Triplets
    Triplet,
    /// Only downbeat
    DownbeatOnly,
}

impl ClickPattern {
    /// Clicks per beat
    pub fn clicks_per_beat(&self) -> u32 {
        match self {
            ClickPattern::Quarter => 1,
            ClickPattern::Eighth => 2,
            ClickPattern::Sixteenth => 4,
            ClickPattern::Triplet => 3,
            ClickPattern::DownbeatOnly => 0, // Special case
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COUNT IN
// ═══════════════════════════════════════════════════════════════════════════════

/// Count-in mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CountInMode {
    /// No count-in
    #[default]
    Off,
    /// 1 bar count-in
    OneBar,
    /// 2 bar count-in
    TwoBars,
    /// 4 beats count-in
    FourBeats,
}

impl CountInMode {
    /// Number of beats for count-in
    pub fn beats(&self, beats_per_bar: u8) -> u32 {
        match self {
            CountInMode::Off => 0,
            CountInMode::OneBar => beats_per_bar as u32,
            CountInMode::TwoBars => beats_per_bar as u32 * 2,
            CountInMode::FourBeats => 4,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK TRACK
// ═══════════════════════════════════════════════════════════════════════════════

/// Metronome/Click track generator
#[allow(dead_code)]
pub struct ClickTrack {
    /// Enabled
    enabled: AtomicBool,
    /// Accent sound
    accent_sound: ClickSound,
    /// Beat sound
    beat_sound: ClickSound,
    /// Subdivision sound
    subdivision_sound: ClickSound,
    /// Master volume (linear)
    volume: f32,
    /// Click pattern
    pattern: ClickPattern,
    /// Count-in mode
    count_in: CountInMode,
    /// Current playback position in click sound
    playback_pos: usize,
    /// Current sound being played
    current_sound: Option<ClickSoundType>,
    /// Sample rate
    sample_rate: u32,
    /// PPQ (pulses per quarter note)
    ppq: u32,
    /// Only during recording
    only_during_record: bool,
    /// Pan position (-1.0 to 1.0)
    pan: f32,
}

impl ClickTrack {
    pub fn new(sample_rate: u32) -> Self {
        Self {
            enabled: AtomicBool::new(false),
            accent_sound: ClickSound::default_accent(sample_rate),
            beat_sound: ClickSound::default_beat(sample_rate),
            subdivision_sound: ClickSound::default_subdivision(sample_rate),
            volume: 0.7,
            pattern: ClickPattern::Quarter,
            count_in: CountInMode::Off,
            playback_pos: 0,
            current_sound: None,
            sample_rate,
            ppq: 960,
            only_during_record: false,
            pan: 0.0,
        }
    }

    /// Enable/disable click
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Set volume (0.0 - 1.0)
    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume.clamp(0.0, 1.0);
    }

    /// Set click pattern
    pub fn set_pattern(&mut self, pattern: ClickPattern) {
        self.pattern = pattern;
    }

    /// Set count-in mode
    pub fn set_count_in(&mut self, mode: CountInMode) {
        self.count_in = mode;
    }

    /// Set pan (-1.0 left, 0.0 center, 1.0 right)
    pub fn set_pan(&mut self, pan: f32) {
        self.pan = pan.clamp(-1.0, 1.0);
    }

    /// Set custom accent sound
    pub fn set_accent_sound(&mut self, sound: ClickSound) {
        self.accent_sound = sound;
    }

    /// Set custom beat sound
    pub fn set_beat_sound(&mut self, sound: ClickSound) {
        self.beat_sound = sound;
    }

    /// Trigger click at specific beat position
    pub fn trigger(&mut self, _beat_in_bar: u8, is_downbeat: bool, is_subdivision: bool) {
        if !self.is_enabled() {
            return;
        }

        self.current_sound = Some(if is_downbeat {
            ClickSoundType::Accent
        } else if is_subdivision {
            ClickSoundType::Subdivision
        } else {
            ClickSoundType::Beat
        });
        self.playback_pos = 0;
    }

    /// Check if click should trigger at this tick position
    pub fn should_trigger(&self, tick: u64, beats_per_bar: u8) -> Option<(bool, bool)> {
        // is_downbeat, is_subdivision
        let ticks_per_beat = self.ppq as u64;
        let ticks_per_bar = ticks_per_beat * beats_per_bar as u64;

        // Check for downbeat
        if tick % ticks_per_bar == 0 {
            return Some((true, false));
        }

        // Check for regular beat
        if tick % ticks_per_beat == 0 {
            if self.pattern != ClickPattern::DownbeatOnly {
                return Some((false, false));
            }
        }

        // Check for subdivisions
        match self.pattern {
            ClickPattern::Eighth => {
                let subdivision_ticks = ticks_per_beat / 2;
                if tick % subdivision_ticks == 0 && tick % ticks_per_beat != 0 {
                    return Some((false, true));
                }
            }
            ClickPattern::Sixteenth => {
                let subdivision_ticks = ticks_per_beat / 4;
                if tick % subdivision_ticks == 0 && tick % ticks_per_beat != 0 {
                    return Some((false, true));
                }
            }
            ClickPattern::Triplet => {
                let subdivision_ticks = ticks_per_beat / 3;
                if tick % subdivision_ticks == 0 && tick % ticks_per_beat != 0 {
                    return Some((false, true));
                }
            }
            _ => {}
        }

        None
    }

    /// Process audio block
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if !self.is_enabled() || self.current_sound.is_none() {
            return;
        }

        let sound = match self.current_sound {
            Some(ClickSoundType::Accent) => &self.accent_sound,
            Some(ClickSoundType::Beat) => &self.beat_sound,
            Some(ClickSoundType::Subdivision) => &self.subdivision_sound,
            None => return,
        };

        let samples_left = sound.samples.len().saturating_sub(self.playback_pos);
        if samples_left == 0 {
            self.current_sound = None;
            return;
        }

        // Calculate pan gains
        let left_gain = if self.pan <= 0.0 { 1.0 } else { 1.0 - self.pan };
        let right_gain = if self.pan >= 0.0 { 1.0 } else { 1.0 + self.pan };

        let to_process = samples_left.min(left.len());

        for i in 0..to_process {
            let sample = sound.samples[self.playback_pos + i] as f64
                * sound.gain as f64
                * self.volume as f64;

            left[i] += sample * left_gain as f64;
            right[i] += sample * right_gain as f64;
        }

        self.playback_pos += to_process;

        if self.playback_pos >= sound.samples.len() {
            self.current_sound = None;
        }
    }

    /// Reset playback state
    pub fn reset(&mut self) {
        self.current_sound = None;
        self.playback_pos = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK TRACK STATE (for serialization)
// ═══════════════════════════════════════════════════════════════════════════════

/// Click track settings (serializable)
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClickTrackSettings {
    pub enabled: bool,
    pub volume: f32,
    pub pattern: u8, // 0=Quarter, 1=Eighth, etc
    pub count_in: u8,
    pub pan: f32,
    pub accent_sound_path: Option<String>,
    pub beat_sound_path: Option<String>,
    pub only_during_record: bool,
}

impl Default for ClickTrackSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            volume: 0.7,
            pattern: 0,
            count_in: 0,
            pan: 0.0,
            accent_sound_path: None,
            beat_sound_path: None,
            only_during_record: false,
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
    fn test_click_sound_generation() {
        let sound = ClickSound::default_accent(48000);
        assert!(!sound.samples.is_empty());
        // ~15ms at 48kHz = ~720 samples
        assert!(sound.samples.len() > 500);
        assert!(sound.samples.len() < 1000);
    }

    #[test]
    fn test_click_pattern() {
        assert_eq!(ClickPattern::Quarter.clicks_per_beat(), 1);
        assert_eq!(ClickPattern::Eighth.clicks_per_beat(), 2);
        assert_eq!(ClickPattern::Triplet.clicks_per_beat(), 3);
    }

    #[test]
    fn test_count_in() {
        assert_eq!(CountInMode::Off.beats(4), 0);
        assert_eq!(CountInMode::OneBar.beats(4), 4);
        assert_eq!(CountInMode::TwoBars.beats(3), 6);
    }

    #[test]
    fn test_click_trigger() {
        let click = ClickTrack::new(48000);

        // Should trigger on downbeat (tick 0)
        assert!(click.should_trigger(0, 4).is_some());
        let (is_down, _) = click.should_trigger(0, 4).unwrap();
        assert!(is_down);

        // Should trigger on beat (tick 960)
        assert!(click.should_trigger(960, 4).is_some());
        let (is_down, _) = click.should_trigger(960, 4).unwrap();
        assert!(!is_down);
    }

    #[test]
    fn test_click_processing() {
        let mut click = ClickTrack::new(48000);
        click.set_enabled(true);
        click.trigger(0, true, false);

        let mut left = vec![0.0; 512];
        let mut right = vec![0.0; 512];

        click.process(&mut left, &mut right);

        // Should have non-zero samples
        assert!(left.iter().any(|&s| s.abs() > 0.001));
    }
}

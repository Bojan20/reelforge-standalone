//! Pitch correction and auto-tune
//!
//! Provides:
//! - Automatic pitch correction to scale
//! - Manual pitch editing
//! - Vibrato control
//! - Humanization options

use crate::{midi_to_freq, scale::Scale, NoteEvent, PitchConfig};
use serde::{Deserialize, Serialize};

/// Pitch correction mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CorrectionMode {
    /// No correction
    Off,
    /// Correct to nearest semitone
    Chromatic,
    /// Correct to scale notes only
    Scale,
    /// Snap to specific notes
    NoteSnap,
}

/// Pitch correction configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CorrectionConfig {
    /// Correction mode
    pub mode: CorrectionMode,
    /// Target scale (for Scale mode)
    pub scale: Option<Scale>,
    /// Correction speed (0 = slow/natural, 1 = instant)
    pub speed: f32,
    /// Correction amount (0 = none, 1 = full)
    pub amount: f32,
    /// Preserve vibrato
    pub preserve_vibrato: bool,
    /// Vibrato depth threshold (cents)
    pub vibrato_threshold: f32,
    /// Note transition smoothing (seconds)
    pub transition_time: f32,
    /// Tolerance before correction kicks in (cents)
    pub tolerance: f32,
    /// Humanization amount (adds slight randomness)
    pub humanize: f32,
}

impl Default for CorrectionConfig {
    fn default() -> Self {
        Self {
            mode: CorrectionMode::Chromatic,
            scale: None,
            speed: 0.5,
            amount: 1.0,
            preserve_vibrato: true,
            vibrato_threshold: 30.0,
            transition_time: 0.05,
            tolerance: 10.0,
            humanize: 0.0,
        }
    }
}

/// Real-time pitch corrector
pub struct PitchCorrector {
    /// Configuration
    config: CorrectionConfig,
    /// Sample rate
    sample_rate: u32,
    /// Current target pitch (MIDI)
    target_pitch: f32,
    /// Current smoothed pitch
    smoothed_pitch: f32,
    /// Vibrato detector state
    vibrato_phase: f32,
    /// Vibrato depth (cents)
    vibrato_depth: f32,
    /// Vibrato rate (Hz)
    vibrato_rate: f32,
    /// Pitch history for vibrato detection
    pitch_history: Vec<f32>,
    /// History write index
    history_idx: usize,
    /// Correction envelope
    correction_envelope: f32,
}

impl PitchCorrector {
    /// Create new pitch corrector
    pub fn new(sample_rate: u32) -> Self {
        Self {
            config: CorrectionConfig::default(),
            sample_rate,
            target_pitch: 0.0,
            smoothed_pitch: 0.0,
            vibrato_phase: 0.0,
            vibrato_depth: 0.0,
            vibrato_rate: 0.0,
            pitch_history: vec![0.0; 100],
            history_idx: 0,
            correction_envelope: 0.0,
        }
    }

    /// Set configuration
    pub fn set_config(&mut self, config: CorrectionConfig) {
        self.config = config;
    }

    /// Get configuration
    pub fn config(&self) -> &CorrectionConfig {
        &self.config
    }

    /// Set scale for correction
    pub fn set_scale(&mut self, scale: Scale) {
        self.config.scale = Some(scale);
        self.config.mode = CorrectionMode::Scale;
    }

    /// Process pitch value and return corrected pitch
    pub fn process(&mut self, input_pitch: f32) -> f32 {
        if self.config.mode == CorrectionMode::Off {
            return input_pitch;
        }

        // Initialize smoothed pitch on first call
        if self.smoothed_pitch == 0.0 && input_pitch != 0.0 {
            self.smoothed_pitch = input_pitch;
            self.target_pitch = self.get_target_pitch(input_pitch);
            self.pitch_history.fill(input_pitch);
        }

        // Update pitch history for vibrato detection
        self.pitch_history[self.history_idx] = input_pitch;
        self.history_idx = (self.history_idx + 1) % self.pitch_history.len();

        // Detect vibrato (only if we have enough history)
        let vibrato_component = if self.config.preserve_vibrato {
            self.detect_vibrato(input_pitch)
        } else {
            0.0
        };

        // Get target pitch (quantized)
        let base_pitch = input_pitch - vibrato_component;
        let target = self.get_target_pitch(base_pitch);

        // Check if within tolerance
        let error_cents = (target - base_pitch).abs() * 100.0; // semitones to cents approx
        if error_cents < self.config.tolerance {
            return input_pitch;
        }

        // Detect note change
        if (self.target_pitch - target).abs() > 0.5 {
            self.target_pitch = target;
            self.correction_envelope = 0.0;
        }

        // Smooth target transitions
        let transition_samples = (self.config.transition_time * self.sample_rate as f32).max(1.0);
        let alpha = 1.0 / transition_samples;
        self.smoothed_pitch += (target - self.smoothed_pitch) * alpha;

        // Apply correction with speed control
        let correction_alpha = self.config.speed; // Direct speed mapping
        self.correction_envelope += (1.0 - self.correction_envelope) * correction_alpha;
        self.correction_envelope = self.correction_envelope.min(1.0);

        // Interpolate from input towards target
        let corrected_base = base_pitch + (target - base_pitch) * self.correction_envelope;

        // Apply correction amount
        let final_base = base_pitch + (corrected_base - base_pitch) * self.config.amount;

        // Add back vibrato
        let mut final_pitch = final_base + vibrato_component;

        // Humanization
        if self.config.humanize > 0.0 {
            let noise = (self.history_idx as f32 * 0.1).sin() * 0.01;
            final_pitch += noise * self.config.humanize;
        }

        final_pitch
    }

    /// Get target pitch based on mode
    fn get_target_pitch(&self, pitch: f32) -> f32 {
        match self.config.mode {
            CorrectionMode::Off => pitch,
            CorrectionMode::Chromatic => pitch.round(),
            CorrectionMode::Scale => {
                if let Some(ref scale) = self.config.scale {
                    scale.quantize(pitch)
                } else {
                    pitch.round()
                }
            }
            CorrectionMode::NoteSnap => pitch.round(),
        }
    }

    /// Detect vibrato in pitch signal
    fn detect_vibrato(&mut self, current_pitch: f32) -> f32 {
        // Simple vibrato detection: find oscillation around mean
        let mean: f32 = self.pitch_history.iter().sum::<f32>() / self.pitch_history.len() as f32;

        // Deviation from mean (in semitones)
        let deviation = current_pitch - mean;

        // Check if deviation is within vibrato range
        let deviation_cents = deviation.abs() * 100.0;
        if deviation_cents > self.config.vibrato_threshold
            && deviation_cents < self.config.vibrato_threshold * 4.0
        {
            // Estimate vibrato parameters from zero crossings
            let mut zero_crossings = 0;
            let mut prev = self.pitch_history[0] - mean;

            for &p in &self.pitch_history[1..] {
                let curr = p - mean;
                if prev * curr < 0.0 {
                    zero_crossings += 1;
                }
                prev = curr;
            }

            // Update vibrato rate estimate
            let period_samples = if zero_crossings > 0 {
                self.pitch_history.len() as f32 * 2.0 / zero_crossings as f32
            } else {
                0.0
            };

            if period_samples > 0.0 {
                self.vibrato_rate = self.sample_rate as f32 / period_samples;
                self.vibrato_depth = deviation_cents;

                // Return the vibrato component
                return deviation;
            }
        }

        0.0
    }

    /// Reset corrector state
    pub fn reset(&mut self) {
        self.target_pitch = 0.0;
        self.smoothed_pitch = 0.0;
        self.vibrato_phase = 0.0;
        self.pitch_history.fill(0.0);
        self.history_idx = 0;
        self.correction_envelope = 0.0;
    }
}

/// Batch note corrector for offline processing
pub struct NoteCorrector {
    /// Configuration
    config: CorrectionConfig,
    /// Sample rate
    sample_rate: u32,
}

impl NoteCorrector {
    /// Create new note corrector
    pub fn new(config: &PitchConfig) -> Self {
        Self {
            config: CorrectionConfig::default(),
            sample_rate: config.sample_rate,
        }
    }

    /// Set configuration
    pub fn set_config(&mut self, config: CorrectionConfig) {
        self.config = config;
    }

    /// Correct notes to scale
    pub fn correct_notes(&self, notes: &mut [NoteEvent]) {
        for note in notes {
            self.correct_note(note);
        }
    }

    /// Correct single note
    pub fn correct_note(&self, note: &mut NoteEvent) {
        if self.config.mode == CorrectionMode::Off {
            return;
        }

        // Get target pitch
        let target = match self.config.mode {
            CorrectionMode::Off => return,
            CorrectionMode::Chromatic => note.pitch.round(),
            CorrectionMode::Scale => {
                if let Some(ref scale) = self.config.scale {
                    scale.quantize(note.pitch)
                } else {
                    note.pitch.round()
                }
            }
            CorrectionMode::NoteSnap => note.pitch.round(),
        };

        let pitch_shift = target - note.pitch;

        // Apply correction amount
        let final_shift = pitch_shift * self.config.amount;

        // Update note pitch
        note.pitch += final_shift;

        // Correct pitch contour
        if !note.pitch_contour.is_empty() {
            let freq_ratio = 2.0f32.powf(final_shift / 12.0);

            if self.config.preserve_vibrato {
                // Preserve vibrato shape while shifting center
                let mean_freq: f32 =
                    note.pitch_contour.iter().sum::<f32>() / note.pitch_contour.len() as f32;
                let target_freq = midi_to_freq(note.pitch);

                for freq in &mut note.pitch_contour {
                    let deviation = *freq - mean_freq;
                    *freq = target_freq + deviation;
                }
            } else {
                // Simple frequency scaling
                for freq in &mut note.pitch_contour {
                    *freq *= freq_ratio;
                }
            }
        }
    }

    /// Apply pitch drift correction (gradual pitch changes within note)
    pub fn correct_drift(&self, note: &mut NoteEvent) {
        if note.pitch_contour.is_empty() {
            return;
        }

        let target_freq = midi_to_freq(note.pitch);

        // Calculate drift correction curve
        let contour_len = note.pitch_contour.len();
        let attack_samples = (0.05 * self.sample_rate as f32) as usize;
        let release_samples = (0.02 * self.sample_rate as f32) as usize;

        for (i, freq) in note.pitch_contour.iter_mut().enumerate() {
            // Correction envelope (0 at start/end, 1 in middle)
            let env = if i < attack_samples {
                i as f32 / attack_samples as f32
            } else if i > contour_len - release_samples {
                (contour_len - i) as f32 / release_samples as f32
            } else {
                1.0
            };

            // Apply drift correction
            let correction = (target_freq - *freq) * env * self.config.amount * 0.5;
            *freq += correction;
        }
    }

    /// Add natural pitch variations
    pub fn humanize_notes(&self, notes: &mut [NoteEvent]) {
        if self.config.humanize <= 0.0 {
            return;
        }

        for (i, note) in notes.iter_mut().enumerate() {
            // Slight pitch offset (max ±10 cents)
            let offset = ((i as f32 * 7.3).sin() * 0.1) * self.config.humanize;
            note.pitch += offset;

            // Vary timing slightly
            let timing_var = ((i as f32 * 3.7).cos() * 0.01 * self.sample_rate as f32) as i32;
            note.start_sample = (note.start_sample as i32 + timing_var).max(0) as usize;
        }
    }
}

/// Pitch shift with formant preservation
#[derive(Debug, Clone)]
pub struct FormantPreserver {
    /// Sample rate
    sample_rate: u32,
    /// FFT size
    fft_size: usize,
    /// Formant shift (semitones)
    formant_shift: f32,
}

impl FormantPreserver {
    /// Create new formant preserver
    pub fn new(sample_rate: u32) -> Self {
        Self {
            sample_rate,
            fft_size: 2048,
            formant_shift: 0.0,
        }
    }

    /// Set formant shift (semitones, 0 = preserve original)
    pub fn set_formant_shift(&mut self, semitones: f32) {
        self.formant_shift = semitones;
    }

    /// Calculate formant preservation envelope
    pub fn calculate_envelope(&self, pitch_shift_semitones: f32) -> Vec<f32> {
        let num_bins = self.fft_size / 2 + 1;
        let mut envelope = vec![1.0; num_bins];

        // Formant preservation: scale spectral envelope inversely to pitch shift
        let formant_ratio = 2.0f32.powf(-pitch_shift_semitones / 12.0);
        let target_ratio = 2.0f32.powf(self.formant_shift / 12.0);
        let final_ratio = formant_ratio * target_ratio;

        for i in 1..num_bins {
            let source_bin = (i as f32 * final_ratio) as usize;
            if source_bin < num_bins {
                envelope[i] = 1.0; // Would interpolate from source spectrum
            } else {
                envelope[i] = 0.0; // Bin outside range
            }
        }

        envelope
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pitch_corrector_chromatic() {
        let mut corrector = PitchCorrector::new(48000);
        corrector.set_config(CorrectionConfig {
            mode: CorrectionMode::Chromatic,
            speed: 1.0,
            amount: 1.0,
            tolerance: 0.0,
            preserve_vibrato: false, // Disable vibrato detection for cleaner test
            ..Default::default()
        });

        // Process multiple times to let it converge
        let mut pitch = 60.3;
        for _ in 0..100 {
            pitch = corrector.process(pitch);
        }

        assert!(
            (pitch - 60.0).abs() < 0.1,
            "Should correct towards nearest semitone, got {}",
            pitch
        );
    }

    #[test]
    fn test_pitch_corrector_scale() {
        let mut corrector = PitchCorrector::new(48000);
        corrector.set_scale(Scale::major(0)); // C major
        corrector.set_config(CorrectionConfig {
            mode: CorrectionMode::Scale,
            scale: Some(Scale::major(0)),
            speed: 1.0,
            amount: 1.0,
            tolerance: 0.0,
            preserve_vibrato: false,
            ..Default::default()
        });

        // C# should correct to C or D
        let mut pitch = 61.0;
        for _ in 0..100 {
            pitch = corrector.process(pitch);
        }

        assert!(
            (pitch - 60.0).abs() < 0.1 || (pitch - 62.0).abs() < 0.1,
            "Should correct to scale note, got {}",
            pitch
        );
    }

    #[test]
    fn test_note_corrector() {
        let config = PitchConfig::default();
        let mut corrector = NoteCorrector::new(&config);
        corrector.set_config(CorrectionConfig {
            mode: CorrectionMode::Chromatic,
            amount: 1.0,
            ..Default::default()
        });

        let mut note = NoteEvent::new(60.4, 0, 48000);
        corrector.correct_note(&mut note);

        assert_eq!(note.pitch, 60.0);
    }

    #[test]
    fn test_correction_amount() {
        let config = PitchConfig::default();
        let mut corrector = NoteCorrector::new(&config);
        corrector.set_config(CorrectionConfig {
            mode: CorrectionMode::Chromatic,
            amount: 0.5, // 50% correction
            ..Default::default()
        });

        let mut note = NoteEvent::new(60.4, 0, 48000);
        corrector.correct_note(&mut note);

        // Should be halfway between 60.4 and 60.0
        assert!((note.pitch - 60.2).abs() < 0.01);
    }

    #[test]
    fn test_formant_preserver() {
        let preserver = FormantPreserver::new(48000);
        let envelope = preserver.calculate_envelope(12.0); // One octave up

        assert!(!envelope.is_empty());
        assert_eq!(envelope[0], 1.0);
    }

    #[test]
    fn test_correction_off() {
        let mut corrector = PitchCorrector::new(48000);
        corrector.set_config(CorrectionConfig {
            mode: CorrectionMode::Off,
            ..Default::default()
        });

        let result = corrector.process(60.7);
        assert_eq!(result, 60.7);
    }
}

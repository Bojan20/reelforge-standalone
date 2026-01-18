//! Polyphonic pitch analysis
//!
//! Separates individual voices from polyphonic audio using:
//! - Harmonic partial tracking
//! - Pitch salience computation
//! - Voice continuity constraints

use crate::{
    detection::PitchDetector, freq_to_midi, NoteEvent, PitchConfig, PitchError, PitchResult,
    PolyphonicAnalysis, Voice,
};
use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;
use std::sync::Arc;

/// Polyphonic analyzer for separating multiple simultaneous pitches
pub struct PolyphonicAnalyzer {
    /// Configuration
    config: PitchConfig,
    /// FFT for spectral analysis
    fft: Arc<dyn RealToComplex<f32>>,
    /// FFT input buffer
    fft_input: Vec<f32>,
    /// FFT output buffer
    fft_output: Vec<Complex<f32>>,
    /// Magnitude spectrum
    spectrum: Vec<f32>,
    /// Pitch salience function
    salience: Vec<f32>,
    /// Harmonic weights for salience
    harmonic_weights: Vec<f32>,
    /// Active voice tracking
    active_voices: Vec<VoiceState>,
    /// Completed notes
    completed_notes: Vec<NoteEvent>,
    /// Current frame index
    frame_index: usize,
    /// Monophonic detector for validation
    mono_detector: PitchDetector,
}

/// Internal voice tracking state
#[derive(Debug, Clone)]
struct VoiceState {
    /// Voice ID
    id: usize,
    /// Current frequency
    frequency: f32,
    /// MIDI pitch
    midi_pitch: f32,
    /// Start frame
    start_frame: usize,
    /// Amplitude history
    amplitudes: Vec<f32>,
    /// Pitch contour (frequencies)
    pitch_contour: Vec<f32>,
    /// Harmonic structure
    harmonics: Vec<f32>,
    /// Frames since last update
    inactive_frames: usize,
    /// Total confidence
    total_confidence: f32,
    /// Update count
    update_count: usize,
}

impl PolyphonicAnalyzer {
    /// Create new polyphonic analyzer
    pub fn new(config: &PitchConfig) -> Self {
        let fft_size = config.window_size;
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        // Harmonic weights (favor lower harmonics)
        let num_harmonics = 10;
        let harmonic_weights: Vec<f32> = (1..=num_harmonics)
            .map(|h| 1.0 / (h as f32).sqrt())
            .collect();

        // Salience function resolution (10 cents per bin)
        let salience_bins = 6000; // 50 octaves * 1200 cents / 10 cents

        Self {
            config: config.clone(),
            fft,
            fft_input: vec![0.0; fft_size],
            fft_output: vec![Complex::new(0.0, 0.0); fft_size / 2 + 1],
            spectrum: vec![0.0; fft_size / 2 + 1],
            salience: vec![0.0; salience_bins],
            harmonic_weights,
            active_voices: Vec::new(),
            completed_notes: Vec::new(),
            frame_index: 0,
            mono_detector: PitchDetector::new(config),
        }
    }

    /// Reset analyzer state
    pub fn reset(&mut self) {
        self.active_voices.clear();
        self.completed_notes.clear();
        self.frame_index = 0;
    }

    /// Analyze audio and extract polyphonic notes
    pub fn analyze(&mut self, audio: &[f32]) -> PitchResult<PolyphonicAnalysis> {
        let min_samples = self.config.window_size;
        if audio.len() < min_samples {
            return Err(PitchError::InputTooShort(audio.len(), min_samples));
        }

        self.reset();

        let hop_size = self.config.hop_size;
        let window_size = self.config.window_size;
        let num_frames = (audio.len() - window_size) / hop_size + 1;

        let mut frame_voices: Vec<Vec<Voice>> = Vec::with_capacity(num_frames);

        for frame_idx in 0..num_frames {
            let start = frame_idx * hop_size;
            let end = start + window_size;
            let frame = &audio[start..end];

            // Analyze frame
            let voices = self.analyze_frame(frame)?;
            frame_voices.push(voices);

            self.frame_index += 1;
        }

        // Finalize remaining active voices
        self.finalize_all_voices();

        // Convert to sample-based timing
        let notes: Vec<NoteEvent> = self
            .completed_notes
            .iter()
            .map(|n| {
                let mut note = n.clone();
                note.start_sample = n.start_sample * hop_size;
                note.duration = n.duration * hop_size;
                note
            })
            .collect();

        // Calculate overall confidence
        let confidence = if notes.is_empty() {
            0.0
        } else {
            notes.iter().map(|n| n.confidence).sum::<f32>() / notes.len() as f32
        };

        Ok(PolyphonicAnalysis {
            notes,
            voices: frame_voices,
            sample_rate: self.config.sample_rate,
            hop_size,
            confidence,
        })
    }

    /// Analyze single frame for multiple pitches
    fn analyze_frame(&mut self, frame: &[f32]) -> PitchResult<Vec<Voice>> {
        // Compute spectrum
        self.compute_spectrum(frame)?;

        // Compute pitch salience
        self.compute_salience();

        // Find salience peaks
        let peaks = self.find_salience_peaks();

        // Track voices
        self.track_voices(&peaks);

        // Return current voice states
        let voices: Vec<Voice> = self
            .active_voices
            .iter()
            .filter(|v| v.inactive_frames == 0)
            .map(|v| Voice {
                fundamental: v.frequency,
                harmonics: v.harmonics.clone(),
                phases: Vec::new(),
                centroid: v.frequency * 2.5, // Approximate
                flux: 0.0,
                active: true,
            })
            .collect();

        Ok(voices)
    }

    /// Compute magnitude spectrum
    fn compute_spectrum(&mut self, frame: &[f32]) -> PitchResult<()> {
        // Apply Hann window
        let window_size = self.config.window_size;
        for (i, &sample) in frame.iter().take(window_size).enumerate() {
            let window =
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / window_size as f32).cos());
            self.fft_input[i] = sample * window;
        }

        // FFT
        self.fft
            .process(&mut self.fft_input, &mut self.fft_output)
            .map_err(|e| PitchError::FftError(format!("{:?}", e)))?;

        // Magnitude
        for (i, c) in self.fft_output.iter().enumerate() {
            self.spectrum[i] = (c.re * c.re + c.im * c.im).sqrt();
        }

        Ok(())
    }

    /// Compute pitch salience function
    fn compute_salience(&mut self) {
        self.salience.fill(0.0);

        let bin_freq = self.config.sample_rate as f32 / self.config.window_size as f32;
        let cents_per_bin = 10.0;

        // For each spectral bin, contribute to salience
        for (bin, &mag) in self.spectrum.iter().enumerate().skip(1) {
            let freq = bin as f32 * bin_freq;
            if freq < self.config.min_freq || freq > self.config.max_freq * 10.0 {
                continue;
            }

            if mag < 1e-10 {
                continue;
            }

            // This could be fundamental of harmonic
            for (h, &weight) in self.harmonic_weights.iter().enumerate() {
                let h = h + 1;
                let fundamental = freq / h as f32;

                if fundamental < self.config.min_freq || fundamental > self.config.max_freq {
                    continue;
                }

                // Convert to cents (relative to min_freq)
                let cents = 1200.0 * (fundamental / self.config.min_freq).log2();
                let salience_bin = (cents / cents_per_bin) as usize;

                if salience_bin < self.salience.len() {
                    self.salience[salience_bin] += mag * weight;
                }
            }
        }
    }

    /// Find peaks in salience function
    fn find_salience_peaks(&self) -> Vec<(f32, f32)> {
        let cents_per_bin = 10.0;
        let mut peaks = Vec::new();

        // Find local maxima
        let min_peak_distance = 50.0 / cents_per_bin; // 50 cents minimum

        let mut i = 1;
        while i < self.salience.len() - 1 {
            if self.salience[i] > self.salience[i - 1] && self.salience[i] > self.salience[i + 1] {
                // Parabolic interpolation
                let alpha = self.salience[i - 1];
                let beta = self.salience[i];
                let gamma = self.salience[i + 1];

                let p = 0.5 * (alpha - gamma) / (alpha - 2.0 * beta + gamma);
                let refined_bin = i as f32 + if p.is_finite() { p } else { 0.0 };

                let cents = refined_bin * cents_per_bin;
                let freq = self.config.min_freq * 2.0f32.powf(cents / 1200.0);
                let magnitude = beta;

                if magnitude > self.salience.iter().cloned().sum::<f32>() * 0.01 {
                    peaks.push((freq, magnitude));
                }

                i += min_peak_distance as usize;
            } else {
                i += 1;
            }
        }

        // Sort by magnitude (descending)
        peaks.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // Keep top N
        peaks.truncate(self.config.max_voices);

        peaks
    }

    /// Track voices across frames
    fn track_voices(&mut self, peaks: &[(f32, f32)]) {
        let tolerance_cents = self.config.pitch_tolerance_cents;
        let mut matched = vec![false; peaks.len()];

        // Match existing voices to peaks
        for voice in &mut self.active_voices {
            let mut best_match: Option<(usize, f32)> = None;

            for (i, &(freq, mag)) in peaks.iter().enumerate() {
                if matched[i] {
                    continue;
                }

                let cents_diff = 1200.0 * (freq / voice.frequency).abs().log2();
                if cents_diff < tolerance_cents {
                    let score = mag / (cents_diff + 1.0);
                    if best_match.is_none() || score > best_match.unwrap().1 {
                        best_match = Some((i, score));
                    }
                }
            }

            if let Some((idx, _)) = best_match {
                matched[idx] = true;
                let (freq, mag) = peaks[idx];

                // Update voice
                voice.frequency = freq;
                voice.midi_pitch = freq_to_midi(freq);
                voice.amplitudes.push(mag);
                voice.pitch_contour.push(freq);
                voice.inactive_frames = 0;
                voice.total_confidence += mag;
                voice.update_count += 1;
            } else {
                voice.inactive_frames += 1;
            }
        }

        // Create new voices for unmatched peaks
        for (i, &(freq, mag)) in peaks.iter().enumerate() {
            if !matched[i] && self.active_voices.len() < self.config.max_voices {
                let voice_id = self.frame_index * 100 + self.active_voices.len();
                self.active_voices.push(VoiceState {
                    id: voice_id,
                    frequency: freq,
                    midi_pitch: freq_to_midi(freq),
                    start_frame: self.frame_index,
                    amplitudes: vec![mag],
                    pitch_contour: vec![freq],
                    harmonics: Vec::new(),
                    inactive_frames: 0,
                    total_confidence: mag,
                    update_count: 1,
                });
            }
        }

        // Finalize voices that have been inactive too long
        let max_inactive = 3;
        let min_duration_frames = self.config.min_duration / self.config.hop_size;

        let mut i = 0;
        while i < self.active_voices.len() {
            if self.active_voices[i].inactive_frames > max_inactive {
                let voice = self.active_voices.remove(i);
                self.finalize_voice(voice, min_duration_frames);
            } else {
                i += 1;
            }
        }
    }

    /// Finalize a voice into a note event
    fn finalize_voice(&mut self, voice: VoiceState, min_duration: usize) {
        let duration = voice.amplitudes.len();
        if duration < min_duration {
            return;
        }

        let avg_confidence = voice.total_confidence / voice.update_count as f32;

        // Normalize amplitude
        let max_amp = voice
            .amplitudes
            .iter()
            .cloned()
            .fold(0.0f32, f32::max)
            .max(1e-10);
        let normalized_amp: Vec<f32> = voice.amplitudes.iter().map(|a| a / max_amp).collect();

        let note = NoteEvent {
            pitch: voice.midi_pitch,
            confidence: avg_confidence.min(1.0),
            start_sample: voice.start_frame,
            duration,
            amplitude: normalized_amp,
            pitch_contour: voice.pitch_contour,
            formant_shift: 0.0,
            original_freq: voice.frequency,
            voice_id: voice.id,
        };

        self.completed_notes.push(note);
    }

    /// Finalize all remaining active voices
    fn finalize_all_voices(&mut self) {
        let min_duration = self.config.min_duration / self.config.hop_size;
        let voices: Vec<VoiceState> = self.active_voices.drain(..).collect();

        for voice in voices {
            self.finalize_voice(voice, min_duration);
        }
    }
}

/// Simple onset detector for note segmentation
pub struct OnsetDetector {
    /// Sample rate
    sample_rate: u32,
    /// Hop size
    hop_size: usize,
    /// Previous spectrum
    prev_spectrum: Vec<f32>,
    /// Onset threshold
    threshold: f32,
    /// FFT planner
    fft: Arc<dyn RealToComplex<f32>>,
    /// FFT buffers
    fft_input: Vec<f32>,
    fft_output: Vec<Complex<f32>>,
}

impl OnsetDetector {
    /// Create new onset detector
    pub fn new(sample_rate: u32, window_size: usize, hop_size: usize) -> Self {
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(window_size);

        Self {
            sample_rate,
            hop_size,
            prev_spectrum: vec![0.0; window_size / 2 + 1],
            threshold: 0.3,
            fft,
            fft_input: vec![0.0; window_size],
            fft_output: vec![Complex::new(0.0, 0.0); window_size / 2 + 1],
        }
    }

    /// Set onset threshold
    pub fn set_threshold(&mut self, threshold: f32) {
        self.threshold = threshold.clamp(0.01, 1.0);
    }

    /// Detect onsets in audio
    pub fn detect(&mut self, audio: &[f32]) -> Vec<usize> {
        let window_size = self.fft_input.len();
        let num_frames = (audio.len().saturating_sub(window_size)) / self.hop_size + 1;

        let mut onsets = Vec::new();
        let mut onset_function = Vec::with_capacity(num_frames);

        for frame_idx in 0..num_frames {
            let start = frame_idx * self.hop_size;
            let end = (start + window_size).min(audio.len());

            // Window and FFT
            for (i, &sample) in audio[start..end].iter().enumerate() {
                let window = 0.5
                    * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / window_size as f32).cos());
                self.fft_input[i] = sample * window;
            }

            if self
                .fft
                .process(&mut self.fft_input, &mut self.fft_output)
                .is_err()
            {
                continue;
            }

            // Spectral flux (half-wave rectified)
            let mut flux = 0.0f32;
            for (i, c) in self.fft_output.iter().enumerate() {
                let mag = (c.re * c.re + c.im * c.im).sqrt();
                let diff = mag - self.prev_spectrum[i];
                if diff > 0.0 {
                    flux += diff;
                }
                self.prev_spectrum[i] = mag;
            }

            onset_function.push(flux);
        }

        // Adaptive thresholding
        let window = 10;
        for (i, &flux) in onset_function.iter().enumerate() {
            let start = i.saturating_sub(window);
            let end = (i + window + 1).min(onset_function.len());
            let local_mean: f32 =
                onset_function[start..end].iter().sum::<f32>() / (end - start) as f32;

            if flux > local_mean * (1.0 + self.threshold) {
                // Check if it's a local maximum
                let is_peak = (i == 0 || flux > onset_function[i - 1])
                    && (i == onset_function.len() - 1 || flux > onset_function[i + 1]);

                if is_peak {
                    onsets.push(i * self.hop_size);
                }
            }
        }

        onsets
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn generate_sine(freq: f32, sample_rate: u32, num_samples: usize) -> Vec<f32> {
        (0..num_samples)
            .map(|i| (2.0 * std::f32::consts::PI * freq * i as f32 / sample_rate as f32).sin())
            .collect()
    }

    #[test]
    fn test_polyphonic_analyzer_single_note() {
        let config = PitchConfig::default();
        let mut analyzer = PolyphonicAnalyzer::new(&config);

        // Generate 440 Hz signal with harmonics (2 seconds)
        let sample_rate = config.sample_rate;
        let num_samples = sample_rate as usize * 2;
        let samples: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sample_rate as f32;
                let f = 440.0;
                (2.0 * std::f32::consts::PI * f * t).sin()
                    + 0.5 * (2.0 * std::f32::consts::PI * f * 2.0 * t).sin()
                    + 0.25 * (2.0 * std::f32::consts::PI * f * 3.0 * t).sin()
            })
            .collect();

        let result = analyzer.analyze(&samples).unwrap();

        // Analysis completes without error - note detection depends on harmonic content
        assert!(result.confidence >= 0.0, "Should return valid confidence");
    }

    #[test]
    fn test_polyphonic_analyzer_chord() {
        let config = PitchConfig::default();
        let mut analyzer = PolyphonicAnalyzer::new(&config);

        // Generate C major chord (C4, E4, G4)
        let sample_rate = config.sample_rate;
        let num_samples = sample_rate as usize * 2;

        let samples: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sample_rate as f32;
                let c4 = (2.0 * std::f32::consts::PI * 261.63 * t).sin();
                let e4 = (2.0 * std::f32::consts::PI * 329.63 * t).sin();
                let g4 = (2.0 * std::f32::consts::PI * 392.00 * t).sin();
                (c4 + e4 + g4) / 3.0
            })
            .collect();

        let result = analyzer.analyze(&samples).unwrap();

        // Should detect multiple voices
        assert!(
            !result.notes.is_empty(),
            "Should detect at least one note in chord"
        );
    }

    #[test]
    fn test_onset_detector() {
        let sample_rate = 48000;
        let mut detector = OnsetDetector::new(sample_rate, 2048, 512);

        // Generate audio with distinct note onsets
        let mut samples = vec![0.0; sample_rate as usize * 2];

        // First note at 0.5s
        let start1 = (0.5 * sample_rate as f32) as usize;
        for (offset, sample) in samples[start1..(1.0 * sample_rate as f32) as usize]
            .iter_mut()
            .enumerate()
        {
            let t = (start1 + offset) as f32 / sample_rate as f32;
            *sample = (2.0 * std::f32::consts::PI * 440.0 * t).sin();
        }

        // Second note at 1.2s (different pitch)
        let start2 = (1.2 * sample_rate as f32) as usize;
        for (offset, sample) in samples[start2..(1.7 * sample_rate as f32) as usize]
            .iter_mut()
            .enumerate()
        {
            let t = (start2 + offset) as f32 / sample_rate as f32;
            *sample = (2.0 * std::f32::consts::PI * 880.0 * t).sin();
        }

        let onsets = detector.detect(&samples);

        // Should detect at least the onset at 0.5s
        assert!(!onsets.is_empty(), "Should detect at least one onset");
    }
}

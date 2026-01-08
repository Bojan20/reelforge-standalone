//! Audio synthesis from pitch data
//!
//! Re-synthesizes audio from modified note events using:
//! - Additive synthesis with harmonic tracking
//! - Overlap-add with phase continuity
//! - Formant-aware processing

use crate::{NoteEvent, PitchConfig};
use realfft::{ComplexToReal, RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;
use std::sync::Arc;

/// Phase vocoder for time-pitch manipulation
pub struct PhaseVocoder {
    /// Sample rate
    sample_rate: u32,
    /// Analysis window size
    analysis_size: usize,
    /// Synthesis window size
    synthesis_size: usize,
    /// Hop size
    hop_size: usize,
    /// Forward FFT
    fft_forward: Arc<dyn RealToComplex<f32>>,
    /// Inverse FFT
    fft_inverse: Arc<dyn ComplexToReal<f32>>,
    /// Analysis buffer
    analysis_buffer: Vec<f32>,
    /// Synthesis buffer
    synthesis_buffer: Vec<f32>,
    /// FFT input
    fft_input: Vec<f32>,
    /// FFT output
    fft_output: Vec<Complex<f32>>,
    /// IFFT input
    ifft_input: Vec<Complex<f32>>,
    /// IFFT output
    ifft_output: Vec<f32>,
    /// Previous phase
    prev_phase: Vec<f32>,
    /// Phase accumulator
    phase_accum: Vec<f32>,
    /// Analysis window
    analysis_window: Vec<f32>,
    /// Synthesis window
    synthesis_window: Vec<f32>,
}

impl PhaseVocoder {
    /// Create new phase vocoder
    pub fn new(config: &PitchConfig) -> Self {
        let analysis_size = config.window_size;
        let synthesis_size = config.window_size;
        let hop_size = config.hop_size;

        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(analysis_size);
        let fft_inverse = planner.plan_fft_inverse(synthesis_size);

        let num_bins = analysis_size / 2 + 1;

        // Hann windows
        let analysis_window: Vec<f32> = (0..analysis_size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / analysis_size as f32).cos())
            })
            .collect();

        let synthesis_window: Vec<f32> = (0..synthesis_size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / synthesis_size as f32).cos())
            })
            .collect();

        Self {
            sample_rate: config.sample_rate,
            analysis_size,
            synthesis_size,
            hop_size,
            fft_forward,
            fft_inverse,
            analysis_buffer: vec![0.0; analysis_size],
            synthesis_buffer: vec![0.0; synthesis_size * 2],
            fft_input: vec![0.0; analysis_size],
            fft_output: vec![Complex::new(0.0, 0.0); num_bins],
            ifft_input: vec![Complex::new(0.0, 0.0); num_bins],
            ifft_output: vec![0.0; synthesis_size],
            prev_phase: vec![0.0; num_bins],
            phase_accum: vec![0.0; num_bins],
            analysis_window,
            synthesis_window,
        }
    }

    /// Reset phase vocoder state
    pub fn reset(&mut self) {
        self.prev_phase.fill(0.0);
        self.phase_accum.fill(0.0);
        self.synthesis_buffer.fill(0.0);
    }

    /// Process audio with pitch shift
    pub fn process(&mut self, input: &[f32], pitch_shift_semitones: f32) -> Vec<f32> {
        let pitch_ratio = 2.0f32.powf(pitch_shift_semitones / 12.0);
        let time_stretch = 1.0; // No time stretch for pure pitch shift

        self.process_with_time_stretch(input, pitch_ratio, time_stretch)
    }

    /// Process with independent pitch and time control
    pub fn process_with_time_stretch(
        &mut self,
        input: &[f32],
        pitch_ratio: f32,
        time_stretch: f32,
    ) -> Vec<f32> {
        let synthesis_hop = (self.hop_size as f32 * time_stretch) as usize;
        let analysis_hop = self.hop_size;

        let num_frames = (input.len().saturating_sub(self.analysis_size)) / analysis_hop + 1;
        let output_len = num_frames * synthesis_hop + self.synthesis_size;

        let mut output = vec![0.0; output_len];

        for frame in 0..num_frames {
            let analysis_pos = frame * analysis_hop;
            let synthesis_pos = frame * synthesis_hop;

            // Analysis
            self.analyze_frame(&input[analysis_pos..]);

            // Pitch shift in frequency domain
            self.shift_pitch(pitch_ratio);

            // Synthesis
            self.synthesize_frame(&mut output[synthesis_pos..]);
        }

        // Normalize overlap-add
        let norm = self.hop_size as f32 / self.analysis_size as f32 * 2.0;
        for sample in &mut output {
            *sample *= norm;
        }

        output
    }

    /// Analyze a frame
    fn analyze_frame(&mut self, input: &[f32]) {
        // Apply analysis window
        for (i, sample) in input.iter().take(self.analysis_size).enumerate() {
            self.fft_input[i] = sample * self.analysis_window[i];
        }

        // FFT
        let _ = self
            .fft_forward
            .process(&mut self.fft_input, &mut self.fft_output);
    }

    /// Shift pitch in frequency domain
    fn shift_pitch(&mut self, pitch_ratio: f32) {
        let num_bins = self.fft_output.len();
        let freq_per_bin = self.sample_rate as f32 / self.analysis_size as f32;
        let expected_phase_diff = 2.0 * std::f32::consts::PI * self.hop_size as f32;

        // Clear output
        self.ifft_input.fill(Complex::new(0.0, 0.0));

        for bin in 0..num_bins {
            let mag = (self.fft_output[bin].re.powi(2) + self.fft_output[bin].im.powi(2)).sqrt();
            let phase = self.fft_output[bin].im.atan2(self.fft_output[bin].re);

            // Phase unwrapping
            let phase_diff = phase - self.prev_phase[bin];
            self.prev_phase[bin] = phase;

            // Expected phase difference for this bin
            let expected = expected_phase_diff * bin as f32 / self.analysis_size as f32;

            // Deviation from expected (true frequency deviation)
            let mut dev = phase_diff - expected;
            dev = dev - (dev / (2.0 * std::f32::consts::PI)).round() * 2.0 * std::f32::consts::PI;

            // True frequency
            let true_freq = (bin as f32 + dev / expected_phase_diff) * freq_per_bin;

            // Target bin after pitch shift
            let target_bin = ((true_freq * pitch_ratio) / freq_per_bin) as usize;

            if target_bin < num_bins {
                // Accumulate phase for synthesis
                self.phase_accum[target_bin] += expected_phase_diff * target_bin as f32
                    / self.analysis_size as f32
                    + dev * pitch_ratio;

                // Add to output bin
                self.ifft_input[target_bin] += Complex::new(
                    mag * self.phase_accum[target_bin].cos(),
                    mag * self.phase_accum[target_bin].sin(),
                );
            }
        }
    }

    /// Synthesize a frame
    fn synthesize_frame(&mut self, output: &mut [f32]) {
        // IFFT
        let _ = self
            .fft_inverse
            .process(&mut self.ifft_input, &mut self.ifft_output);

        // Apply synthesis window and overlap-add
        let scale = 1.0 / self.synthesis_size as f32;
        for (i, sample) in self
            .ifft_output
            .iter()
            .take(self.synthesis_size)
            .enumerate()
        {
            if i < output.len() {
                output[i] += sample * self.synthesis_window[i] * scale;
            }
        }
    }
}

/// Additive synthesizer for note-based re-synthesis
pub struct AdditiveSynthesizer {
    /// Sample rate
    sample_rate: u32,
    /// Number of harmonics
    num_harmonics: usize,
    /// Harmonic phases
    phases: Vec<f32>,
    /// Harmonic amplitudes
    amplitudes: Vec<f32>,
}

impl AdditiveSynthesizer {
    /// Create new additive synthesizer
    pub fn new(sample_rate: u32, num_harmonics: usize) -> Self {
        Self {
            sample_rate,
            num_harmonics,
            phases: vec![0.0; num_harmonics],
            amplitudes: vec![0.0; num_harmonics],
        }
    }

    /// Reset synthesizer state
    pub fn reset(&mut self) {
        self.phases.fill(0.0);
        self.amplitudes.fill(0.0);
    }

    /// Synthesize audio from note events
    pub fn synthesize(&mut self, notes: &[NoteEvent], output_length: usize) -> Vec<f32> {
        let mut output = vec![0.0; output_length];

        for note in notes {
            self.synthesize_note(note, &mut output);
        }

        // Normalize
        let max = output.iter().cloned().fold(0.0f32, f32::max);
        if max > 0.0 {
            let norm = 0.9 / max;
            for sample in &mut output {
                *sample *= norm;
            }
        }

        output
    }

    /// Synthesize single note
    fn synthesize_note(&mut self, note: &NoteEvent, output: &mut [f32]) {
        let start = note.start_sample;
        let end = (start + note.duration).min(output.len());

        // Reset phases for new note
        for (i, phase) in self.phases.iter_mut().enumerate() {
            *phase = (i as f32 * 0.1) % (2.0 * std::f32::consts::PI); // Slight phase offset per harmonic
        }

        // Set harmonic amplitudes (decreasing with harmonic number)
        for (i, amp) in self.amplitudes.iter_mut().enumerate() {
            *amp = 1.0 / ((i + 1) as f32).sqrt();
        }

        let dt = 1.0 / self.sample_rate as f32;

        for i in start..end {
            let offset = i - start;

            // Get frequency at this point
            let freq = note.frequency_at(offset);

            // Get amplitude envelope
            let amp_env = note.amplitude_at(offset);

            // Synthesize sample using additive synthesis
            let mut sample = 0.0f32;

            for h in 0..self.num_harmonics {
                let harmonic_freq = freq * (h + 1) as f32;

                // Don't synthesize above Nyquist
                if harmonic_freq > self.sample_rate as f32 / 2.0 {
                    break;
                }

                sample += self.phases[h].sin() * self.amplitudes[h];

                // Update phase
                self.phases[h] += 2.0 * std::f32::consts::PI * harmonic_freq * dt;
                if self.phases[h] > 2.0 * std::f32::consts::PI {
                    self.phases[h] -= 2.0 * std::f32::consts::PI;
                }
            }

            output[i] += sample * amp_env;
        }
    }

    /// Set harmonic structure
    pub fn set_harmonics(&mut self, amplitudes: &[f32]) {
        let len = amplitudes.len().min(self.num_harmonics);
        self.amplitudes[..len].copy_from_slice(&amplitudes[..len]);
    }
}

/// Overlap-add processor for frame-based synthesis
pub struct OverlapAdd {
    /// Frame size
    frame_size: usize,
    /// Hop size
    hop_size: usize,
    /// Output buffer
    buffer: Vec<f32>,
    /// Write position
    write_pos: usize,
    /// Synthesis window
    window: Vec<f32>,
}

impl OverlapAdd {
    /// Create new overlap-add processor
    pub fn new(frame_size: usize, hop_size: usize) -> Self {
        // Synthesis window (square root of Hann for perfect reconstruction)
        let window: Vec<f32> = (0..frame_size)
            .map(|i| {
                let hann =
                    0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / frame_size as f32).cos());
                hann.sqrt()
            })
            .collect();

        Self {
            frame_size,
            hop_size,
            buffer: vec![0.0; frame_size * 4],
            write_pos: 0,
            window,
        }
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }

    /// Add a frame to the output
    pub fn add_frame(&mut self, frame: &[f32]) {
        for (i, sample) in frame.iter().take(self.frame_size).enumerate() {
            let pos = (self.write_pos + i) % self.buffer.len();
            self.buffer[pos] += sample * self.window[i];
        }
        self.write_pos = (self.write_pos + self.hop_size) % self.buffer.len();
    }

    /// Get output samples
    pub fn get_output(&self, output: &mut [f32], read_pos: usize) {
        for (i, out) in output.iter_mut().enumerate() {
            let pos = (read_pos + i) % self.buffer.len();
            *out = self.buffer[pos];
        }
    }
}

/// PSOLA (Pitch Synchronous Overlap-Add) for time-domain pitch shifting
pub struct PsolaProcessor {
    /// Sample rate
    sample_rate: u32,
    /// Analysis marks (pitch period boundaries)
    marks: Vec<usize>,
    /// Window size multiplier
    window_mult: f32,
}

impl PsolaProcessor {
    /// Create new PSOLA processor
    pub fn new(sample_rate: u32) -> Self {
        Self {
            sample_rate,
            marks: Vec::new(),
            window_mult: 2.0,
        }
    }

    /// Analyze pitch marks from audio
    pub fn analyze(&mut self, audio: &[f32], pitch_contour: &[f32], hop_size: usize) {
        self.marks.clear();

        let mut pos = 0usize;
        let mut i = 0;

        while pos < audio.len() {
            self.marks.push(pos);

            // Period length from pitch
            let freq = if i < pitch_contour.len() {
                pitch_contour[i]
            } else {
                pitch_contour.last().copied().unwrap_or(440.0)
            };

            let period = if freq > 0.0 {
                (self.sample_rate as f32 / freq) as usize
            } else {
                hop_size
            };

            pos += period;
            i += 1;
        }
    }

    /// Synthesize with pitch modification
    pub fn synthesize(&self, audio: &[f32], pitch_ratio: f32) -> Vec<f32> {
        if self.marks.len() < 2 {
            return audio.to_vec();
        }

        let output_len = (audio.len() as f32 / pitch_ratio) as usize;
        let mut output = vec![0.0; output_len];

        let mut output_pos = 0.0f32;

        for window_idx in 0..self.marks.len() {
            let mark = self.marks[window_idx];
            let period = if window_idx + 1 < self.marks.len() {
                self.marks[window_idx + 1] - mark
            } else {
                if window_idx > 0 {
                    mark - self.marks[window_idx - 1]
                } else {
                    256
                }
            };

            let window_size = (period as f32 * self.window_mult) as usize;
            let half_window = window_size / 2;

            // Calculate output position
            let out_mark = output_pos as usize;

            // Extract and window the grain
            for i in 0..window_size {
                let in_pos = (mark as i32 - half_window as i32 + i as i32) as usize;
                let out_pos = (out_mark as i32 - half_window as i32 + i as i32) as usize;

                if in_pos < audio.len() && out_pos < output.len() {
                    // Hann window
                    let w = 0.5
                        * (1.0
                            - (2.0 * std::f32::consts::PI * i as f32 / window_size as f32).cos());
                    output[out_pos] += audio[in_pos] * w;
                }
            }

            output_pos += period as f32 / pitch_ratio;
        }

        output
    }
}

/// High-quality pitch shifter combining multiple techniques
pub struct PitchShifter {
    /// Phase vocoder
    vocoder: PhaseVocoder,
    /// Sample rate
    sample_rate: u32,
    /// Formant preservation enabled
    preserve_formants: bool,
}

impl PitchShifter {
    /// Create new pitch shifter
    pub fn new(config: &PitchConfig) -> Self {
        Self {
            vocoder: PhaseVocoder::new(config),
            sample_rate: config.sample_rate,
            preserve_formants: config.preserve_formants,
        }
    }

    /// Shift pitch by semitones
    pub fn shift(&mut self, audio: &[f32], semitones: f32) -> Vec<f32> {
        self.vocoder.process(audio, semitones)
    }

    /// Shift pitch with time stretch
    pub fn shift_with_time(&mut self, audio: &[f32], semitones: f32, time_ratio: f32) -> Vec<f32> {
        let pitch_ratio = 2.0f32.powf(semitones / 12.0);
        self.vocoder
            .process_with_time_stretch(audio, pitch_ratio, time_ratio)
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.vocoder.reset();
    }
}

/// Synthesize audio from note events (main API)
pub fn synthesize_from_notes(notes: &[NoteEvent], sample_rate: u32, length: usize) -> Vec<f32> {
    let mut synth = AdditiveSynthesizer::new(sample_rate, 16);
    synth.synthesize(notes, length)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_phase_vocoder() {
        let config = PitchConfig::default();
        let mut vocoder = PhaseVocoder::new(&config);

        // Generate test signal
        let samples: Vec<f32> = (0..config.sample_rate as usize)
            .map(|i| {
                (2.0 * std::f32::consts::PI * 440.0 * i as f32 / config.sample_rate as f32).sin()
            })
            .collect();

        let shifted = vocoder.process(&samples, 0.0); // No shift

        assert!(!shifted.is_empty());
    }

    #[test]
    fn test_additive_synthesizer() {
        let sample_rate = 48000;
        let mut synth = AdditiveSynthesizer::new(sample_rate, 8);

        let note = NoteEvent::new(69.0, 0, sample_rate as usize); // A4, 1 second

        let output = synth.synthesize(&[note], sample_rate as usize);

        assert_eq!(output.len(), sample_rate as usize);

        // Check that audio was generated
        let max = output.iter().cloned().fold(0.0f32, f32::max);
        assert!(max > 0.0);
    }

    #[test]
    fn test_overlap_add() {
        let frame_size = 1024;
        let hop_size = 256;
        let mut ola = OverlapAdd::new(frame_size, hop_size);

        // Add some frames
        let frame = vec![0.5; frame_size];
        for _ in 0..10 {
            ola.add_frame(&frame);
        }

        let mut output = vec![0.0; hop_size];
        ola.get_output(&mut output, 0);

        // Should have some non-zero output
        assert!(output.iter().any(|&x| x != 0.0));
    }

    #[test]
    fn test_pitch_shifter() {
        let config = PitchConfig::default();
        let mut shifter = PitchShifter::new(&config);

        let samples: Vec<f32> = (0..config.sample_rate as usize)
            .map(|i| {
                (2.0 * std::f32::consts::PI * 440.0 * i as f32 / config.sample_rate as f32).sin()
            })
            .collect();

        // Shift up one octave
        let shifted = shifter.shift(&samples, 12.0);

        assert!(!shifted.is_empty());
    }

    #[test]
    fn test_synthesize_from_notes() {
        let notes = vec![
            NoteEvent::new(60.0, 0, 24000),     // C4
            NoteEvent::new(64.0, 24000, 24000), // E4
            NoteEvent::new(67.0, 48000, 24000), // G4
        ];

        let output = synthesize_from_notes(&notes, 48000, 72000);

        assert_eq!(output.len(), 72000);
        assert!(output.iter().any(|&x| x != 0.0));
    }
}

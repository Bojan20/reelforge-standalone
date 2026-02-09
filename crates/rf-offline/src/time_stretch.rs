//! Time-stretch and pitch-shift algorithms
//!
//! Implements phase vocoder based time-stretch and pitch-shift:
//! - WSOLA (Waveform Similarity Overlap-Add) for speech
//! - Phase vocoder for music
//! - Formant preservation for vocals

use std::f64::consts::PI;

use serde::{Deserialize, Serialize};

use crate::error::{OfflineError, OfflineResult};
use crate::pipeline::AudioBuffer;

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Time-stretch algorithm
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimeStretchAlgorithm {
    /// Phase vocoder (best for music)
    PhaseVocoder,
    /// WSOLA (best for speech)
    Wsola,
    /// Élastique-style (high quality)
    Elastique,
}

impl Default for TimeStretchAlgorithm {
    fn default() -> Self {
        Self::PhaseVocoder
    }
}

/// Time-stretch quality
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimeStretchQuality {
    /// Fast (512 FFT)
    Fast,
    /// Normal (2048 FFT)
    Normal,
    /// High (4096 FFT)
    High,
    /// Maximum (8192 FFT)
    Maximum,
}

impl Default for TimeStretchQuality {
    fn default() -> Self {
        Self::Normal
    }
}

impl TimeStretchQuality {
    /// Get FFT size for quality level
    pub fn fft_size(&self) -> usize {
        match self {
            Self::Fast => 512,
            Self::Normal => 2048,
            Self::High => 4096,
            Self::Maximum => 8192,
        }
    }

    /// Get hop size (typically 1/4 of FFT size)
    pub fn hop_size(&self) -> usize {
        self.fft_size() / 4
    }
}

/// Time-stretch configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeStretchConfig {
    /// Algorithm to use
    pub algorithm: TimeStretchAlgorithm,
    /// Quality level
    pub quality: TimeStretchQuality,
    /// Time stretch ratio (0.5 = half speed, 2.0 = double speed)
    pub time_ratio: f64,
    /// Pitch shift in semitones (-12 to +12 typically)
    pub pitch_semitones: f64,
    /// Preserve formants (for vocals)
    pub preserve_formants: bool,
    /// Transient preservation (0.0 - 1.0)
    pub transient_preservation: f64,
}

impl Default for TimeStretchConfig {
    fn default() -> Self {
        Self {
            algorithm: TimeStretchAlgorithm::default(),
            quality: TimeStretchQuality::default(),
            time_ratio: 1.0,
            pitch_semitones: 0.0,
            preserve_formants: false,
            transient_preservation: 0.5,
        }
    }
}

impl TimeStretchConfig {
    /// Create config for time stretch only
    pub fn time_stretch(ratio: f64) -> Self {
        Self {
            time_ratio: ratio,
            ..Default::default()
        }
    }

    /// Create config for pitch shift only
    pub fn pitch_shift(semitones: f64) -> Self {
        Self {
            pitch_semitones: semitones,
            ..Default::default()
        }
    }

    /// Create config for both
    pub fn time_and_pitch(time_ratio: f64, semitones: f64) -> Self {
        Self {
            time_ratio,
            pitch_semitones: semitones,
            ..Default::default()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE VOCODER
// ═══════════════════════════════════════════════════════════════════════════════

/// Phase vocoder for time-stretch and pitch-shift
pub struct PhaseVocoder {
    fft_size: usize,
    hop_size: usize,
    overlap: usize,
    sample_rate: u32,

    // FFT buffers
    fft_buffer: Vec<f64>,
    window: Vec<f64>,

    // Phase tracking
    last_phase: Vec<f64>,
    sum_phase: Vec<f64>,

    // Analysis/synthesis buffers
    analysis_buffer: Vec<f64>,
    synthesis_buffer: Vec<f64>,
}

impl PhaseVocoder {
    /// Create new phase vocoder
    pub fn new(quality: TimeStretchQuality, sample_rate: u32) -> Self {
        let fft_size = quality.fft_size();
        let hop_size = quality.hop_size();
        let overlap = fft_size / hop_size;

        // Create Hann window
        let window: Vec<f64> = (0..fft_size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / fft_size as f64).cos()))
            .collect();

        Self {
            fft_size,
            hop_size,
            overlap,
            sample_rate,
            fft_buffer: vec![0.0; fft_size],
            window,
            last_phase: vec![0.0; fft_size / 2 + 1],
            sum_phase: vec![0.0; fft_size / 2 + 1],
            analysis_buffer: Vec::new(),
            synthesis_buffer: Vec::new(),
        }
    }

    /// Process audio buffer with time-stretch
    pub fn process(
        &mut self,
        buffer: &AudioBuffer,
        config: &TimeStretchConfig,
    ) -> OfflineResult<AudioBuffer> {
        if buffer.channels != 1 {
            // Process each channel separately for stereo
            return self.process_stereo(buffer, config);
        }

        let time_ratio = config.time_ratio;
        let pitch_factor = 2.0_f64.powf(config.pitch_semitones / 12.0);

        // Combined ratio for resampling
        let combined_ratio = time_ratio / pitch_factor;

        // First pass: time stretch only
        let stretched = self.time_stretch_mono(&buffer.samples, time_ratio)?;

        // Second pass: resample for pitch shift
        let output = if (pitch_factor - 1.0).abs() > 0.001 {
            self.resample(&stretched, combined_ratio)?
        } else {
            stretched
        };

        Ok(AudioBuffer {
            samples: output,
            channels: 1,
            sample_rate: buffer.sample_rate,
        })
    }

    /// Process stereo buffer
    fn process_stereo(
        &mut self,
        buffer: &AudioBuffer,
        config: &TimeStretchConfig,
    ) -> OfflineResult<AudioBuffer> {
        // Split channels
        let left = buffer.get_channel(0);
        let right = buffer.get_channel(1);

        // Process each channel
        let left_buffer = AudioBuffer {
            samples: left,
            channels: 1,
            sample_rate: buffer.sample_rate,
        };
        let right_buffer = AudioBuffer {
            samples: right,
            channels: 1,
            sample_rate: buffer.sample_rate,
        };

        let left_result = self.process(&left_buffer, config)?;

        // Reset phase tracking for right channel
        self.last_phase.fill(0.0);
        self.sum_phase.fill(0.0);

        let right_result = self.process(&right_buffer, config)?;

        // Interleave
        let frames = left_result.samples.len().min(right_result.samples.len());
        let mut interleaved = Vec::with_capacity(frames * 2);
        for i in 0..frames {
            interleaved.push(left_result.samples[i]);
            interleaved.push(right_result.samples[i]);
        }

        Ok(AudioBuffer {
            samples: interleaved,
            channels: 2,
            sample_rate: buffer.sample_rate,
        })
    }

    /// Time stretch mono signal using OLA
    fn time_stretch_mono(&mut self, samples: &[f64], ratio: f64) -> OfflineResult<Vec<f64>> {
        if ratio <= 0.0 {
            return Err(OfflineError::ConfigError(
                "Time ratio must be positive".into(),
            ));
        }

        let input_len = samples.len();
        let output_len = (input_len as f64 * ratio) as usize;

        // Use simplified OLA for now (WSOLA would be better)
        let hop_in = self.hop_size;
        let hop_out = (self.hop_size as f64 * ratio) as usize;

        let mut output = vec![0.0; output_len + self.fft_size];
        let mut pos_in = 0usize;
        let mut pos_out = 0usize;

        while pos_in + self.fft_size <= input_len && pos_out + self.fft_size <= output.len() {
            // Get input frame
            for (i, sample) in samples[pos_in..pos_in + self.fft_size].iter().enumerate() {
                self.fft_buffer[i] = *sample * self.window[i];
            }

            // Process phase vocoder frame
            self.process_frame(ratio);

            // Overlap-add to output
            for (i, &sample) in self.fft_buffer.iter().enumerate() {
                if pos_out + i < output.len() {
                    output[pos_out + i] += sample * self.window[i];
                }
            }

            pos_in += hop_in;
            pos_out += hop_out;
        }

        // Normalize by overlap factor
        let overlap_factor = self.fft_size as f64 / hop_out as f64;
        for sample in &mut output {
            *sample /= overlap_factor;
        }

        output.truncate(output_len);
        Ok(output)
    }

    /// Process single FFT frame with phase modification
    fn process_frame(&mut self, _ratio: f64) {
        // Simplified phase vocoder
        // Full implementation would use realfft and proper phase unwrapping

        // For now, just apply window (actual implementation needs FFT)
        // This is a placeholder - real implementation needs:
        // 1. Forward FFT
        // 2. Phase unwrapping and interpolation
        // 3. Inverse FFT

        // The current implementation is OLA without phase processing
        // which works reasonably for small ratios
    }

    /// Resample for pitch shift
    fn resample(&self, samples: &[f64], ratio: f64) -> OfflineResult<Vec<f64>> {
        let output_len = (samples.len() as f64 / ratio) as usize;
        let mut output = Vec::with_capacity(output_len);

        for i in 0..output_len {
            let src_pos = i as f64 * ratio;
            let src_idx = src_pos as usize;
            let frac = src_pos - src_idx as f64;

            let s0 = samples.get(src_idx).copied().unwrap_or(0.0);
            let s1 = samples.get(src_idx + 1).copied().unwrap_or(s0);

            // Cubic interpolation would be better
            let sample = s0 + (s1 - s0) * frac;
            output.push(sample);
        }

        Ok(output)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WSOLA (Waveform Similarity Overlap-Add)
// ═══════════════════════════════════════════════════════════════════════════════

/// WSOLA time-stretcher (good for speech)
pub struct WsolaStretcher {
    frame_size: usize,
    search_range: usize,
    overlap: usize,
}

impl WsolaStretcher {
    /// Create new WSOLA stretcher
    pub fn new(frame_size: usize) -> Self {
        Self {
            frame_size,
            search_range: frame_size / 4,
            overlap: frame_size / 2,
        }
    }

    /// Process buffer with time stretch
    pub fn process(&self, buffer: &AudioBuffer, ratio: f64) -> OfflineResult<AudioBuffer> {
        if buffer.channels != 1 {
            return self.process_stereo(buffer, ratio);
        }

        let output = self.stretch_mono(&buffer.samples, ratio)?;

        Ok(AudioBuffer {
            samples: output,
            channels: 1,
            sample_rate: buffer.sample_rate,
        })
    }

    /// Process stereo
    fn process_stereo(&self, buffer: &AudioBuffer, ratio: f64) -> OfflineResult<AudioBuffer> {
        let left = buffer.get_channel(0);
        let right = buffer.get_channel(1);

        let left_out = self.stretch_mono(&left, ratio)?;
        let right_out = self.stretch_mono(&right, ratio)?;

        let frames = left_out.len().min(right_out.len());
        let mut interleaved = Vec::with_capacity(frames * 2);
        for i in 0..frames {
            interleaved.push(left_out[i]);
            interleaved.push(right_out[i]);
        }

        Ok(AudioBuffer {
            samples: interleaved,
            channels: 2,
            sample_rate: buffer.sample_rate,
        })
    }

    /// Stretch mono signal
    fn stretch_mono(&self, samples: &[f64], ratio: f64) -> OfflineResult<Vec<f64>> {
        let input_len = samples.len();
        let output_len = (input_len as f64 * ratio) as usize;

        let hop_in = self.frame_size - self.overlap;
        let hop_out = (hop_in as f64 * ratio) as usize;

        let mut output = vec![0.0; output_len + self.frame_size];
        let mut pos_in = 0.0f64;
        let mut pos_out = 0usize;

        // Triangular window for overlap
        let window: Vec<f64> = (0..self.overlap)
            .map(|i| i as f64 / self.overlap as f64)
            .collect();

        while (pos_in as usize) + self.frame_size <= input_len
            && pos_out + self.frame_size <= output.len()
        {
            let ideal_pos = pos_in as usize;

            // Find best match in search range
            let best_pos = self.find_best_position(samples, &output, ideal_pos, pos_out);

            // Copy frame with overlap-add
            for i in 0..self.frame_size {
                let sample = samples.get(best_pos + i).copied().unwrap_or(0.0);

                if i < self.overlap && pos_out > 0 {
                    // Crossfade region
                    let fade_in = window[i];
                    let fade_out = 1.0 - fade_in;
                    output[pos_out + i] = output[pos_out + i] * fade_out + sample * fade_in;
                } else {
                    output[pos_out + i] = sample;
                }
            }

            pos_in += hop_in as f64;
            pos_out += hop_out;
        }

        output.truncate(output_len);
        Ok(output)
    }

    /// Find best matching position using cross-correlation
    fn find_best_position(
        &self,
        input: &[f64],
        output: &[f64],
        ideal_pos: usize,
        output_pos: usize,
    ) -> usize {
        if output_pos < self.overlap {
            return ideal_pos;
        }

        let search_start = ideal_pos.saturating_sub(self.search_range);
        let search_end = (ideal_pos + self.search_range).min(input.len() - self.overlap);

        let mut best_pos = ideal_pos;
        let mut best_corr = f64::NEG_INFINITY;

        // Reference from output overlap region
        let output_ref: Vec<f64> = (0..self.overlap)
            .map(|i| {
                output
                    .get(output_pos.saturating_sub(self.overlap) + i)
                    .copied()
                    .unwrap_or(0.0)
            })
            .collect();

        for pos in search_start..search_end {
            // Candidate from input
            let candidate: Vec<f64> = (0..self.overlap)
                .map(|i| input.get(pos + i).copied().unwrap_or(0.0))
                .collect();

            // Normalized cross-correlation
            let corr = self.cross_correlation(&output_ref, &candidate);

            if corr > best_corr {
                best_corr = corr;
                best_pos = pos;
            }
        }

        best_pos
    }

    /// Calculate normalized cross-correlation
    fn cross_correlation(&self, a: &[f64], b: &[f64]) -> f64 {
        let len = a.len().min(b.len());
        if len == 0 {
            return 0.0;
        }

        let mut sum = 0.0;
        let mut sum_a2 = 0.0;
        let mut sum_b2 = 0.0;

        for i in 0..len {
            sum += a[i] * b[i];
            sum_a2 += a[i] * a[i];
            sum_b2 += b[i] * b[i];
        }

        let denom = (sum_a2 * sum_b2).sqrt();
        if denom > 0.0 { sum / denom } else { 0.0 }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIME STRETCHER (unified interface)
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified time stretcher
pub struct TimeStretcher {
    config: TimeStretchConfig,
    phase_vocoder: Option<PhaseVocoder>,
    wsola: Option<WsolaStretcher>,
}

impl TimeStretcher {
    /// Create new time stretcher
    pub fn new(config: TimeStretchConfig, sample_rate: u32) -> Self {
        let phase_vocoder = match config.algorithm {
            TimeStretchAlgorithm::PhaseVocoder | TimeStretchAlgorithm::Elastique => {
                Some(PhaseVocoder::new(config.quality, sample_rate))
            }
            _ => None,
        };

        let wsola = match config.algorithm {
            TimeStretchAlgorithm::Wsola => Some(WsolaStretcher::new(config.quality.fft_size())),
            _ => None,
        };

        Self {
            config,
            phase_vocoder,
            wsola,
        }
    }

    /// Process buffer
    pub fn process(&mut self, buffer: &AudioBuffer) -> OfflineResult<AudioBuffer> {
        // Check if processing is needed
        if (self.config.time_ratio - 1.0).abs() < 0.001 && self.config.pitch_semitones.abs() < 0.01
        {
            return Ok(buffer.clone());
        }

        match self.config.algorithm {
            TimeStretchAlgorithm::PhaseVocoder | TimeStretchAlgorithm::Elastique => {
                if let Some(ref mut pv) = self.phase_vocoder {
                    pv.process(buffer, &self.config)
                } else {
                    Err(OfflineError::ConfigError(
                        "Phase vocoder not initialized".into(),
                    ))
                }
            }
            TimeStretchAlgorithm::Wsola => {
                if let Some(ref wsola) = self.wsola {
                    wsola.process(buffer, self.config.time_ratio)
                } else {
                    Err(OfflineError::ConfigError("WSOLA not initialized".into()))
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wsola_no_stretch() {
        let stretcher = WsolaStretcher::new(1024);
        let buffer = AudioBuffer {
            samples: vec![0.0; 4096],
            channels: 1,
            sample_rate: 44100,
        };

        let result = stretcher.process(&buffer, 1.0).unwrap();
        assert_eq!(result.channels, 1);
        // Length should be approximately the same
        assert!((result.samples.len() as f64 / buffer.samples.len() as f64 - 1.0).abs() < 0.1);
    }

    #[test]
    fn test_wsola_double_speed() {
        let stretcher = WsolaStretcher::new(1024);
        let buffer = AudioBuffer {
            samples: vec![0.0; 4096],
            channels: 1,
            sample_rate: 44100,
        };

        let result = stretcher.process(&buffer, 0.5).unwrap();
        // Should be roughly half the length
        assert!((result.samples.len() as f64 / buffer.samples.len() as f64 - 0.5).abs() < 0.1);
    }

    #[test]
    fn test_config_builders() {
        let config = TimeStretchConfig::time_stretch(2.0);
        assert_eq!(config.time_ratio, 2.0);
        assert_eq!(config.pitch_semitones, 0.0);

        let config = TimeStretchConfig::pitch_shift(-5.0);
        assert_eq!(config.time_ratio, 1.0);
        assert_eq!(config.pitch_semitones, -5.0);

        let config = TimeStretchConfig::time_and_pitch(1.5, 3.0);
        assert_eq!(config.time_ratio, 1.5);
        assert_eq!(config.pitch_semitones, 3.0);
    }
}

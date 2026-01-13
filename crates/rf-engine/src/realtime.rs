//! Real-time audio engine integration
//!
//! Connects the Mixer to cpal audio streams.

use std::sync::Arc;

use rf_audio::{AudioConfig, AudioResult, AudioStream, get_default_output_device};
use rf_core::{BufferSize, Sample, SampleRate};

use crate::mixer::{MeterBridge, Mixer, MixerHandle};

/// Real-time audio engine
///
/// Manages the audio thread and provides handles for GUI control.
pub struct RealtimeEngine {
    stream: AudioStream,
    mixer_handle: MixerHandle,
    sample_rate: f64,
    block_size: usize,
}

impl RealtimeEngine {
    /// Create and start a new real-time engine
    pub fn new(sample_rate: SampleRate, buffer_size: BufferSize) -> AudioResult<Self> {
        let sr = sample_rate.as_f64();
        let bs = buffer_size.as_usize();

        // Create mixer (returns mixer, command producer, meter bridge)
        let (mut mixer, cmd_tx, meters) = Mixer::new(sr, bs);

        // Create mixer handle for GUI control
        let mixer_handle = MixerHandle::new(cmd_tx, meters);

        // Get default output device
        let output_device = get_default_output_device()?;

        // Audio config
        let config = AudioConfig {
            sample_rate,
            buffer_size,
            input_channels: 0,
            output_channels: 2,
        };

        // Create audio callback
        // The mixer processes and outputs to the interleaved buffer
        let callback = Box::new(move |_input: &[Sample], output: &mut [Sample]| {
            // Process through mixer - outputs interleaved stereo
            mixer.process(output);
        });

        // Create and start stream
        let stream = AudioStream::new(&output_device, None, config, callback)?;
        stream.start()?;

        Ok(Self {
            stream,
            mixer_handle,
            sample_rate: sr,
            block_size: bs,
        })
    }

    /// Get mixer handle for GUI control
    pub fn mixer_handle(&self) -> &MixerHandle {
        &self.mixer_handle
    }

    /// Get mutable mixer handle
    pub fn mixer_handle_mut(&mut self) -> &mut MixerHandle {
        &mut self.mixer_handle
    }

    /// Get meter bridge for real-time meter reading
    pub fn meters(&self) -> Arc<MeterBridge> {
        self.mixer_handle.meters()
    }

    /// Check if audio is running
    pub fn is_running(&self) -> bool {
        self.stream.is_running()
    }

    /// Stop audio
    pub fn stop(&self) -> AudioResult<()> {
        self.stream.stop()
    }

    /// Start audio
    pub fn start(&self) -> AudioResult<()> {
        self.stream.start()
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> f64 {
        self.sample_rate
    }

    /// Get block size
    pub fn block_size(&self) -> usize {
        self.block_size
    }
}

/// Audio source that can be routed to a mixer channel
pub trait AudioSource: Send {
    /// Fill the output buffers with audio
    fn fill(&mut self, left: &mut [Sample], right: &mut [Sample]);

    /// Check if source is finished (for one-shot playback)
    fn is_finished(&self) -> bool {
        false
    }

    /// Reset source to beginning
    fn reset(&mut self) {}
}

/// Simple test tone generator
pub struct TestTone {
    phase: f64,
    frequency: f64,
    sample_rate: f64,
    amplitude: f64,
}

impl TestTone {
    pub fn new(frequency: f64, sample_rate: f64) -> Self {
        Self {
            phase: 0.0,
            frequency,
            sample_rate,
            amplitude: 0.5,
        }
    }

    pub fn set_frequency(&mut self, freq: f64) {
        self.frequency = freq;
    }

    pub fn set_amplitude(&mut self, amp: f64) {
        self.amplitude = amp.clamp(0.0, 1.0);
    }
}

impl AudioSource for TestTone {
    fn fill(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        let phase_inc = self.frequency * 2.0 * std::f64::consts::PI / self.sample_rate;

        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let sample = self.phase.sin() * self.amplitude;
            *l = sample;
            *r = sample;

            self.phase += phase_inc;
            if self.phase > 2.0 * std::f64::consts::PI {
                self.phase -= 2.0 * std::f64::consts::PI;
            }
        }
    }
}

/// Audio file player (placeholder for future implementation)
pub struct AudioFilePlayer {
    samples_l: Vec<Sample>,
    samples_r: Vec<Sample>,
    position: usize,
    looping: bool,
}

impl AudioFilePlayer {
    pub fn new(samples_l: Vec<Sample>, samples_r: Vec<Sample>) -> Self {
        Self {
            samples_l,
            samples_r,
            position: 0,
            looping: false,
        }
    }

    pub fn set_looping(&mut self, looping: bool) {
        self.looping = looping;
    }
}

impl AudioSource for AudioFilePlayer {
    fn fill(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            if self.position < self.samples_l.len() {
                *l = self.samples_l[self.position];
                *r = self.samples_r.get(self.position).copied().unwrap_or(*l);
                self.position += 1;
            } else if self.looping {
                self.position = 0;
                *l = self.samples_l.first().copied().unwrap_or(0.0);
                *r = self.samples_r.first().copied().unwrap_or(*l);
            } else {
                *l = 0.0;
                *r = 0.0;
            }
        }
    }

    fn is_finished(&self) -> bool {
        !self.looping && self.position >= self.samples_l.len()
    }

    fn reset(&mut self) {
        self.position = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_test_tone() {
        let mut tone = TestTone::new(440.0, 48000.0);
        let mut left = vec![0.0; 256];
        let mut right = vec![0.0; 256];

        tone.fill(&mut left, &mut right);

        // Should produce non-zero output
        assert!(left.iter().any(|&s| s != 0.0));
        assert!(right.iter().any(|&s| s != 0.0));

        // Left and right should be equal (mono tone)
        for (l, r) in left.iter().zip(right.iter()) {
            assert!((l - r).abs() < 1e-10);
        }
    }

    #[test]
    fn test_audio_file_player() {
        let samples = vec![0.1, 0.2, 0.3, 0.4];
        let mut player = AudioFilePlayer::new(samples.clone(), samples.clone());

        let mut left = vec![0.0; 6];
        let mut right = vec![0.0; 6];

        player.fill(&mut left, &mut right);

        // First 4 samples from file, last 2 are zero
        assert!((left[0] - 0.1).abs() < 1e-10);
        assert!((left[3] - 0.4).abs() < 1e-10);
        assert!(left[4] == 0.0);
        assert!(left[5] == 0.0);

        assert!(player.is_finished());
    }
}

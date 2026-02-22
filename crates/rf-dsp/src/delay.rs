//! Delay processors
//!
//! Includes:
//! - Simple delay
//! - Ping-pong delay
//! - Multi-tap delay
//! - Modulated delay (chorus/flanger)

use rf_core::Sample;
use std::f64::consts::PI;

use crate::biquad::BiquadTDF2;
use crate::{MonoProcessor, Processor, ProcessorConfig, StereoProcessor};

/// Simple mono delay with feedback and filtering
#[derive(Debug, Clone)]
pub struct Delay {
    buffer: Vec<Sample>,
    write_pos: usize,
    delay_samples: usize,
    max_delay_samples: usize,
    feedback: f64,
    dry_wet: f64,

    // Feedback filtering
    highpass: BiquadTDF2,
    lowpass: BiquadTDF2,
    filter_enabled: bool,

    sample_rate: f64,
}

impl Delay {
    pub fn new(sample_rate: f64, max_delay_ms: f64) -> Self {
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;

        let mut delay = Self {
            buffer: vec![0.0; max_delay_samples],
            write_pos: 0,
            delay_samples: (500.0 * 0.001 * sample_rate) as usize, // Default 500ms
            max_delay_samples,
            feedback: 0.5,
            dry_wet: 0.5,
            highpass: BiquadTDF2::new(sample_rate),
            lowpass: BiquadTDF2::new(sample_rate),
            filter_enabled: true,
            sample_rate,
        };

        delay.highpass.set_highpass(80.0, 0.707);
        delay.lowpass.set_lowpass(8000.0, 0.707);

        delay
    }

    pub fn set_delay_ms(&mut self, ms: f64) {
        let samples = (ms * 0.001 * self.sample_rate) as usize;
        self.delay_samples = samples.min(self.max_delay_samples - 1);
    }

    pub fn set_delay_samples(&mut self, samples: usize) {
        self.delay_samples = samples.min(self.max_delay_samples - 1);
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(0.0, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    pub fn set_highpass(&mut self, freq: f64) {
        self.highpass.set_highpass(freq, 0.707);
    }

    pub fn set_lowpass(&mut self, freq: f64) {
        self.lowpass.set_lowpass(freq, 0.707);
    }

    pub fn set_filter_enabled(&mut self, enabled: bool) {
        self.filter_enabled = enabled;
    }

    fn read_delayed(&self) -> Sample {
        let read_pos =
            (self.write_pos + self.max_delay_samples - self.delay_samples) % self.max_delay_samples;
        self.buffer[read_pos]
    }
}

impl Processor for Delay {
    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.highpass.reset();
        self.lowpass.reset();
    }
}

impl MonoProcessor for Delay {
    fn process_sample(&mut self, input: Sample) -> Sample {
        let delayed = self.read_delayed();

        // Apply filtering to feedback path
        let filtered = if self.filter_enabled {
            let hp = self.highpass.process_sample(delayed);
            self.lowpass.process_sample(hp)
        } else {
            delayed
        };

        // Write to buffer with feedback
        self.buffer[self.write_pos] = input + filtered * self.feedback;
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Mix dry and wet
        input * (1.0 - self.dry_wet) + delayed * self.dry_wet
    }
}

impl ProcessorConfig for Delay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.delay_samples = (self.delay_samples as f64 * ratio) as usize;
        self.buffer = vec![0.0; self.max_delay_samples];
        self.highpass.set_sample_rate(sample_rate);
        self.lowpass.set_sample_rate(sample_rate);
    }
}

/// Stereo ping-pong delay
#[derive(Debug, Clone)]
pub struct PingPongDelay {
    buffer_l: Vec<Sample>,
    buffer_r: Vec<Sample>,
    write_pos: usize,
    delay_samples: usize,
    max_delay_samples: usize,
    feedback: f64,
    dry_wet: f64,
    ping_pong: f64, // 0.0 = normal stereo, 1.0 = full ping-pong

    // Feedback filtering
    highpass_l: BiquadTDF2,
    highpass_r: BiquadTDF2,
    lowpass_l: BiquadTDF2,
    lowpass_r: BiquadTDF2,

    sample_rate: f64,
}

impl PingPongDelay {
    pub fn new(sample_rate: f64, max_delay_ms: f64) -> Self {
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;

        let mut delay = Self {
            buffer_l: vec![0.0; max_delay_samples],
            buffer_r: vec![0.0; max_delay_samples],
            write_pos: 0,
            delay_samples: (500.0 * 0.001 * sample_rate) as usize,
            max_delay_samples,
            feedback: 0.5,
            dry_wet: 0.5,
            ping_pong: 1.0,
            highpass_l: BiquadTDF2::new(sample_rate),
            highpass_r: BiquadTDF2::new(sample_rate),
            lowpass_l: BiquadTDF2::new(sample_rate),
            lowpass_r: BiquadTDF2::new(sample_rate),
            sample_rate,
        };

        delay.highpass_l.set_highpass(80.0, 0.707);
        delay.highpass_r.set_highpass(80.0, 0.707);
        delay.lowpass_l.set_lowpass(8000.0, 0.707);
        delay.lowpass_r.set_lowpass(8000.0, 0.707);

        delay
    }

    pub fn set_delay_ms(&mut self, ms: f64) {
        let samples = (ms * 0.001 * self.sample_rate) as usize;
        self.delay_samples = samples.min(self.max_delay_samples - 1);
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(0.0, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    pub fn set_ping_pong(&mut self, amount: f64) {
        self.ping_pong = amount.clamp(0.0, 1.0);
    }

    /// Set feedback highpass filter frequency (Hz)
    pub fn set_hp_freq(&mut self, freq_hz: f64) {
        let f = freq_hz.clamp(20.0, 2000.0);
        self.highpass_l.set_highpass(f, 0.707);
        self.highpass_r.set_highpass(f, 0.707);
    }

    /// Set feedback lowpass filter frequency (Hz)
    pub fn set_lp_freq(&mut self, freq_hz: f64) {
        let f = freq_hz.clamp(200.0, 20000.0);
        self.lowpass_l.set_lowpass(f, 0.707);
        self.lowpass_r.set_lowpass(f, 0.707);
    }
}

impl Processor for PingPongDelay {
    fn reset(&mut self) {
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
        self.highpass_l.reset();
        self.highpass_r.reset();
        self.lowpass_l.reset();
        self.lowpass_r.reset();
    }
}

impl StereoProcessor for PingPongDelay {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let read_pos =
            (self.write_pos + self.max_delay_samples - self.delay_samples) % self.max_delay_samples;

        let delayed_l = self.buffer_l[read_pos];
        let delayed_r = self.buffer_r[read_pos];

        // Filter feedback
        let filtered_l = self
            .lowpass_l
            .process_sample(self.highpass_l.process_sample(delayed_l));
        let filtered_r = self
            .lowpass_r
            .process_sample(self.highpass_r.process_sample(delayed_r));

        // Ping-pong crossfeed
        let fb_l = filtered_l * (1.0 - self.ping_pong) + filtered_r * self.ping_pong;
        let fb_r = filtered_r * (1.0 - self.ping_pong) + filtered_l * self.ping_pong;

        // Write to buffers
        self.buffer_l[self.write_pos] = left + fb_l * self.feedback;
        self.buffer_r[self.write_pos] = right + fb_r * self.feedback;
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Mix
        let out_l = left * (1.0 - self.dry_wet) + delayed_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + delayed_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for PingPongDelay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.delay_samples = (self.delay_samples as f64 * ratio) as usize;
        self.buffer_l = vec![0.0; self.max_delay_samples];
        self.buffer_r = vec![0.0; self.max_delay_samples];
    }
}

/// Multi-tap delay
#[derive(Debug, Clone)]
pub struct MultiTapDelay {
    buffer: Vec<Sample>,
    write_pos: usize,
    max_delay_samples: usize,

    // Tap settings: (delay_samples, level, pan)
    taps: Vec<(usize, f64, f64)>,

    feedback: f64,
    dry_wet: f64,

    sample_rate: f64,
}

impl MultiTapDelay {
    pub fn new(sample_rate: f64, max_delay_ms: f64, num_taps: usize) -> Self {
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;

        // Default taps evenly spaced
        let taps: Vec<_> = (0..num_taps)
            .map(|i| {
                let delay = (i + 1) * max_delay_samples / (num_taps + 1);
                let level = 1.0 / (i + 1) as f64; // Decreasing level
                let pan = if i % 2 == 0 { -0.3 } else { 0.3 }; // Alternating pan
                (delay, level, pan)
            })
            .collect();

        Self {
            buffer: vec![0.0; max_delay_samples],
            write_pos: 0,
            max_delay_samples,
            taps,
            feedback: 0.3,
            dry_wet: 0.5,
            sample_rate,
        }
    }

    pub fn set_tap(&mut self, index: usize, delay_ms: f64, level: f64, pan: f64) {
        if index < self.taps.len() {
            let delay_samples = (delay_ms * 0.001 * self.sample_rate) as usize;
            self.taps[index] = (
                delay_samples.min(self.max_delay_samples - 1),
                level.clamp(0.0, 1.0),
                pan.clamp(-1.0, 1.0),
            );
        }
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(0.0, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }
}

impl Processor for MultiTapDelay {
    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }
}

impl StereoProcessor for MultiTapDelay {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let input = (left + right) * 0.5;

        // Read all taps and sum
        let mut wet_l = 0.0;
        let mut wet_r = 0.0;

        for &(delay_samples, level, pan) in &self.taps {
            let read_pos =
                (self.write_pos + self.max_delay_samples - delay_samples) % self.max_delay_samples;
            let delayed = self.buffer[read_pos] * level;

            // Pan law (constant power)
            let pan_angle = (pan + 1.0) * 0.5 * PI * 0.5;
            wet_l += delayed * pan_angle.cos();
            wet_r += delayed * pan_angle.sin();
        }

        // Feedback from last tap
        let last_tap_delay = self.taps.last().map(|t| t.0).unwrap_or(0);
        let last_read_pos =
            (self.write_pos + self.max_delay_samples - last_tap_delay) % self.max_delay_samples;
        let fb = self.buffer[last_read_pos] * self.feedback;

        // Write to buffer
        self.buffer[self.write_pos] = input + fb;
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Mix
        let out_l = left * (1.0 - self.dry_wet) + wet_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + wet_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for MultiTapDelay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.buffer = vec![0.0; self.max_delay_samples];

        // Scale tap delays
        for tap in &mut self.taps {
            tap.0 = (tap.0 as f64 * ratio) as usize;
        }
    }
}

/// Modulated delay (for chorus/flanger effects)
#[derive(Debug, Clone)]
pub struct ModulatedDelay {
    buffer_l: Vec<Sample>,
    buffer_r: Vec<Sample>,
    write_pos: usize,
    max_delay_samples: usize,

    // Base delay
    base_delay_samples: f64,

    // Modulation
    mod_depth: f64, // In samples
    mod_rate: f64,  // Hz
    mod_phase: f64,
    mod_stereo_offset: f64, // Phase offset between L/R

    feedback: f64,
    dry_wet: f64,

    sample_rate: f64,
}

impl ModulatedDelay {
    pub fn new(sample_rate: f64) -> Self {
        let max_delay_samples = (50.0 * 0.001 * sample_rate) as usize; // 50ms max

        Self {
            buffer_l: vec![0.0; max_delay_samples],
            buffer_r: vec![0.0; max_delay_samples],
            write_pos: 0,
            max_delay_samples,
            base_delay_samples: 10.0 * 0.001 * sample_rate, // 10ms default
            mod_depth: 2.0 * 0.001 * sample_rate,           // 2ms
            mod_rate: 0.5,                                  // 0.5 Hz
            mod_phase: 0.0,
            mod_stereo_offset: PI * 0.5, // 90 degree offset
            feedback: 0.0,
            dry_wet: 0.5,
            sample_rate,
        }
    }

    /// Create chorus preset
    pub fn chorus(sample_rate: f64) -> Self {
        let mut delay = Self::new(sample_rate);
        delay.set_delay_ms(20.0);
        delay.set_mod_depth_ms(3.0);
        delay.set_mod_rate(0.8);
        delay.set_feedback(0.0);
        delay.set_dry_wet(0.5);
        delay
    }

    /// Create flanger preset
    pub fn flanger(sample_rate: f64) -> Self {
        let mut delay = Self::new(sample_rate);
        delay.set_delay_ms(2.0);
        delay.set_mod_depth_ms(1.5);
        delay.set_mod_rate(0.3);
        delay.set_feedback(0.7);
        delay.set_dry_wet(0.5);
        delay
    }

    pub fn set_delay_ms(&mut self, ms: f64) {
        self.base_delay_samples = ms * 0.001 * self.sample_rate;
    }

    pub fn set_mod_depth_ms(&mut self, ms: f64) {
        self.mod_depth = ms * 0.001 * self.sample_rate;
    }

    pub fn set_mod_rate(&mut self, hz: f64) {
        self.mod_rate = hz.clamp(0.01, 20.0);
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(-0.99, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    /// Interpolated read from buffer
    fn read_interpolated(buffer: &[Sample], pos: f64, max_samples: usize) -> Sample {
        let pos = pos.rem_euclid(max_samples as f64);
        let index = pos as usize;
        let frac = pos - index as f64;

        let s0 = buffer[index % max_samples];
        let s1 = buffer[(index + 1) % max_samples];

        // Linear interpolation
        s0 + (s1 - s0) * frac
    }
}

impl Processor for ModulatedDelay {
    fn reset(&mut self) {
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
        self.mod_phase = 0.0;
    }
}

impl StereoProcessor for ModulatedDelay {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Calculate modulated delay times
        let mod_l = (self.mod_phase).sin();
        let mod_r = (self.mod_phase + self.mod_stereo_offset).sin();

        let delay_l = self.base_delay_samples + self.mod_depth * mod_l;
        let delay_r = self.base_delay_samples + self.mod_depth * mod_r;

        // Read with interpolation
        let read_pos_l = self.write_pos as f64 + self.max_delay_samples as f64 - delay_l;
        let read_pos_r = self.write_pos as f64 + self.max_delay_samples as f64 - delay_r;

        let delayed_l = Self::read_interpolated(&self.buffer_l, read_pos_l, self.max_delay_samples);
        let delayed_r = Self::read_interpolated(&self.buffer_r, read_pos_r, self.max_delay_samples);

        // Write with feedback
        self.buffer_l[self.write_pos] = left + delayed_l * self.feedback;
        self.buffer_r[self.write_pos] = right + delayed_r * self.feedback;
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Advance modulation phase
        self.mod_phase += 2.0 * PI * self.mod_rate / self.sample_rate;
        if self.mod_phase > 2.0 * PI {
            self.mod_phase -= 2.0 * PI;
        }

        // Mix
        let out_l = left * (1.0 - self.dry_wet) + delayed_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + delayed_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for ModulatedDelay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.base_delay_samples *= ratio;
        self.mod_depth *= ratio;
        self.buffer_l = vec![0.0; self.max_delay_samples];
        self.buffer_r = vec![0.0; self.max_delay_samples];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_delay() {
        let mut delay = Delay::new(48000.0, 1000.0);
        delay.set_delay_ms(100.0);
        delay.set_feedback(0.5);
        delay.set_dry_wet(0.5);

        // Send impulse
        let _ = delay.process_sample(1.0);

        // Wait for delay time
        for _ in 0..4799 {
            let _ = delay.process_sample(0.0);
        }

        // Should get delayed signal
        let out = delay.process_sample(0.0);
        assert!(out.abs() > 0.4);
    }

    #[test]
    fn test_ping_pong() {
        let mut delay = PingPongDelay::new(48000.0, 1000.0);
        delay.set_ping_pong(1.0);

        // Process some samples
        for _ in 0..1000 {
            let _ = delay.process_sample(0.5, 0.5);
        }
    }

    #[test]
    fn test_modulated_delay() {
        let mut chorus = ModulatedDelay::chorus(48000.0);

        // Process and verify modulation is working
        let mut outputs = Vec::new();
        for i in 0..1000 {
            let input = if i == 0 { 1.0 } else { 0.0 };
            let (l, r) = chorus.process_sample(input, input);
            outputs.push((l, r));
        }

        // L and R should differ due to stereo modulation
        let mut any_different = false;
        for (l, r) in &outputs {
            if (l - r).abs() > 0.001 {
                any_different = true;
                break;
            }
        }
        assert!(any_different);
    }
}

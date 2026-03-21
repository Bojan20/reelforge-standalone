//! AudioStretcher — Signalsmith Stretch wrapper for FluxForge Studio
//!
//! High-quality real-time time-stretching and pitch-shifting.
//! Uses Signalsmith Stretch (MIT) — quality near zplane Élastique Pro.
//!
//! Architecture (like Pro Tools / Cubase):
//! - Pre-allocate on UI thread (constructor does all heap allocation)
//! - process() on audio thread is zero-allocation
//! - Send + Sync — safe to move between threads
//!
//! Two independent controls:
//! - Time stretch: change speed without changing pitch
//! - Pitch shift: change pitch without changing speed

use signalsmith_stretch::Stretch;

/// Real-time audio stretcher/pitch-shifter per clip.
///
/// Wraps Signalsmith Stretch with pre-allocated interleaved buffers.
/// All allocation happens at construction (UI thread).
/// `process()` is zero-alloc, audio-thread safe.
pub struct AudioStretcher {
    /// Signalsmith Stretch instance (stereo)
    inner: Stretch,
    /// Sample rate
    sample_rate: u32,
    /// Current pitch shift in semitones
    pitch_semitones: f64,
    /// Current time stretch ratio (1.0 = normal, 2.0 = double length)
    stretch_ratio: f64,
    /// Pre-allocated interleaved input buffer [L,R,L,R,...] (f32 for Signalsmith)
    interleaved_in: Vec<f32>,
    /// Pre-allocated interleaved output buffer [L,R,L,R,...]
    interleaved_out: Vec<f32>,
    /// Maximum frames this stretcher can handle per block
    max_frames: usize,
}

impl AudioStretcher {
    /// Create a new stereo audio stretcher. ALL allocation happens here.
    ///
    /// `sample_rate`: engine sample rate (44100, 48000, etc.)
    /// `max_block_frames`: maximum audio block size (typically 8192)
    pub fn new(sample_rate: u32, max_block_frames: usize) -> Self {
        let mut inner = Stretch::preset_default(2, sample_rate);
        inner.set_transpose_factor_semitones(0.0, None);

        // Pre-allocate interleaved buffers for max block size
        // Extra 2x headroom for time-stretching that produces more output than input
        let buf_size = max_block_frames * 2 * 4; // frames * channels * headroom
        Self {
            inner,
            sample_rate,
            pitch_semitones: 0.0,
            stretch_ratio: 1.0,
            interleaved_in: vec![0.0f32; buf_size],
            interleaved_out: vec![0.0f32; buf_size],
            max_frames: max_block_frames,
        }
    }

    /// Set pitch shift in semitones (-24 to +24).
    /// Safe to call from UI thread while audio thread is NOT in process().
    pub fn set_pitch_semitones(&mut self, semitones: f64) {
        self.pitch_semitones = semitones.clamp(-24.0, 24.0);
        self.update_transpose();
    }

    /// Set time stretch ratio (0.25 to 4.0).
    /// 1.0 = normal speed, 2.0 = half speed (double length), 0.5 = double speed (half length).
    pub fn set_stretch_ratio(&mut self, ratio: f64) {
        self.stretch_ratio = ratio.clamp(0.25, 4.0);
        self.update_transpose();
    }

    /// Recalculate Signalsmith transpose from combined pitch + stretch.
    ///
    /// The sinc resampler already changes playback rate by stretch_ratio,
    /// which shifts pitch by 12*log2(stretch_ratio) semitones.
    /// Signalsmith compensates that pitch change AND adds user's pitch shift.
    ///
    /// effective_transpose = user_pitch - stretch_pitch_compensation
    ///                     = pitch_semitones - 12 * log2(stretch_ratio)
    fn update_transpose(&mut self) {
        let stretch_compensation = if self.stretch_ratio > 0.0 {
            12.0 * self.stretch_ratio.log2()
        } else {
            0.0
        };
        let effective = self.pitch_semitones - stretch_compensation;
        self.inner.set_transpose_factor_semitones(effective as f32, None);
    }

    /// Process a block of audio. Zero-allocation, audio-thread safe.
    ///
    /// `input_l`, `input_r`: source audio (f64, deinterleaved)
    /// `output_l`, `output_r`: destination (f64, deinterleaved, must be same length)
    /// `frames`: number of frames to process
    ///
    /// Time stretch is handled by ratio of input/output sizes passed to Signalsmith.
    /// Pitch shift is handled internally by Signalsmith's spectral processing.
    pub fn process(
        &mut self,
        input_l: &[f64],
        input_r: &[f64],
        output_l: &mut [f64],
        output_r: &mut [f64],
        frames: usize,
    ) {
        if frames == 0 || frames > self.max_frames {
            return;
        }

        // Convert f64 deinterleaved → f32 interleaved for Signalsmith
        let samples = frames * 2; // stereo interleaved
        for i in 0..frames {
            self.interleaved_in[i * 2] = input_l[i] as f32;
            self.interleaved_in[i * 2 + 1] = input_r[i] as f32;
        }

        // Same input/output length — Signalsmith only does pitch correction.
        // Time stretch is already handled by the sinc resampler changing playback rate.
        // Signalsmith compensates the pitch change from varispeed + adds user pitch shift.
        self.inner.process(
            &self.interleaved_in[..samples],
            &mut self.interleaved_out[..samples],
        );

        // Convert f32 interleaved → f64 deinterleaved
        for i in 0..frames {
            output_l[i] = self.interleaved_out[i * 2] as f64;
            output_r[i] = self.interleaved_out[i * 2 + 1] as f64;
        }
    }

    /// Reset internal state (call when seeking or transport stops).
    pub fn reset(&mut self) {
        self.inner.reset();
    }

    /// Current pitch shift in semitones.
    pub fn pitch_semitones(&self) -> f64 {
        self.pitch_semitones
    }

    /// Current stretch ratio.
    pub fn stretch_ratio(&self) -> f64 {
        self.stretch_ratio
    }

    /// Latency in samples introduced by the stretcher.
    pub fn latency(&self) -> usize {
        self.inner.input_latency() + self.inner.output_latency()
    }
}

impl std::fmt::Debug for AudioStretcher {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AudioStretcher")
            .field("sample_rate", &self.sample_rate)
            .field("pitch_semitones", &self.pitch_semitones)
            .field("stretch_ratio", &self.stretch_ratio)
            .field("max_frames", &self.max_frames)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_creation() {
        let s = AudioStretcher::new(48000, 4096);
        assert_eq!(s.sample_rate, 48000);
        assert_eq!(s.pitch_semitones(), 0.0);
        assert_eq!(s.stretch_ratio(), 1.0);
    }

    #[test]
    fn test_passthrough() {
        let mut s = AudioStretcher::new(48000, 8192);
        // pitch=0, stretch=1.0 → should be near-passthrough
        // Feed multiple blocks to overcome latency
        let block: Vec<f64> = (0..2048).map(|i| (i as f64 * 0.01).sin()).collect();
        let mut output_l = vec![0.0f64; 2048];
        let mut output_r = vec![0.0f64; 2048];

        // Process 4 blocks to fill internal buffers past latency
        for _ in 0..4 {
            s.process(&block, &block, &mut output_l, &mut output_r, 2048);
        }

        // After latency warmup, output should have energy
        let energy: f64 = output_l.iter().map(|x| x * x).sum();
        assert!(energy > 0.01, "Passthrough has no energy after warmup: {energy}");
    }

    #[test]
    fn test_pitch_shift_produces_output() {
        let mut s = AudioStretcher::new(48000, 8192);
        s.set_pitch_semitones(7.0); // +7 semitones (perfect fifth)

        let block: Vec<f64> = (0..2048)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 48000.0).sin())
            .collect();
        let mut output_l = vec![0.0f64; 2048];
        let mut output_r = vec![0.0f64; 2048];

        // Warmup past latency
        for _ in 0..4 {
            s.process(&block, &block, &mut output_l, &mut output_r, 2048);
        }

        let energy: f64 = output_l.iter().map(|x| x * x).sum();
        assert!(energy > 0.01, "Pitch-shifted output has no energy: {energy}");
        assert!(output_l.iter().all(|x| x.is_finite()), "Output has NaN/Inf");
    }

    #[test]
    fn test_time_stretch() {
        let mut s = AudioStretcher::new(48000, 8192);
        s.set_stretch_ratio(2.0); // pitch compensation = -12 semitones

        let block: Vec<f64> = (0..2048)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 48000.0).sin())
            .collect();
        let mut output_l = vec![0.0f64; 2048];
        let mut output_r = vec![0.0f64; 2048];

        // Warmup past latency
        for _ in 0..4 {
            s.process(&block, &block, &mut output_l, &mut output_r, 2048);
        }

        let energy: f64 = output_l.iter().map(|x| x * x).sum();
        assert!(energy > 0.01, "Stretched output has no energy: {energy}");
    }

    #[test]
    fn test_reset() {
        let mut s = AudioStretcher::new(48000, 4096);
        s.set_pitch_semitones(5.0);
        s.reset();
        // Should not crash, state should be clean
        let input = vec![0.0f64; 512];
        let mut out_l = vec![0.0f64; 512];
        let mut out_r = vec![0.0f64; 512];
        s.process(&input, &input, &mut out_l, &mut out_r, 512);
    }

    #[test]
    fn test_send_sync() {
        // AudioStretcher must be Send (move to audio thread) and Sync (shared access)
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}
        assert_send::<AudioStretcher>();
        assert_sync::<AudioStretcher>();
    }
}

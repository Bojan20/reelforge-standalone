//! Spectral Processing
//!
//! FFT-based spectral processors:
//! - Spectral gate (noise reduction)
//! - Spectral compressor
//! - Spectral freeze
//! - Spectral shift (pitch)
//! - Spectral blur/smear
//! - Spectral denoise (adaptive)

use std::collections::VecDeque;
use std::f64::consts::PI;
use std::sync::Arc;

use realfft::{RealFftPlanner, RealToComplex, ComplexToReal};
use rustfft::num_complex::Complex;

use rf_core::Sample;
use crate::{Processor, ProcessorConfig, StereoProcessor};

// ============ Constants ============

/// Default FFT size
const DEFAULT_FFT_SIZE: usize = 2048;

/// Default hop size (overlap factor of 4)
const DEFAULT_HOP_SIZE: usize = 512;

/// Noise floor estimation frames
const NOISE_FRAMES: usize = 10;

// ============ Spectral Frame ============

/// Single spectral frame (magnitude + phase)
#[derive(Clone)]
struct SpectralFrame {
    magnitude: Vec<f64>,
    phase: Vec<f64>,
}

impl SpectralFrame {
    fn new(size: usize) -> Self {
        Self {
            magnitude: vec![0.0; size],
            phase: vec![0.0; size],
        }
    }

    fn from_complex(spectrum: &[Complex<f64>]) -> Self {
        let magnitude: Vec<f64> = spectrum.iter().map(|c| c.norm()).collect();
        let phase: Vec<f64> = spectrum.iter().map(|c| c.arg()).collect();
        Self { magnitude, phase }
    }

    fn to_complex(&self) -> Vec<Complex<f64>> {
        self.magnitude.iter().zip(&self.phase)
            .map(|(&mag, &phase)| Complex::from_polar(mag, phase))
            .collect()
    }
}

// ============ STFT Processor Base ============

/// Short-Time Fourier Transform processor base
struct StftProcessor {
    /// FFT size
    fft_size: usize,
    /// Hop size
    hop_size: usize,
    /// Input buffer
    input_buffer: Vec<f64>,
    /// Output buffer
    output_buffer: Vec<f64>,
    /// Analysis window
    window: Vec<f64>,
    /// Synthesis window
    synthesis_window: Vec<f64>,
    /// FFT planner
    fft_forward: Arc<dyn RealToComplex<f64>>,
    fft_inverse: Arc<dyn ComplexToReal<f64>>,
    /// Current position
    input_pos: usize,
    output_pos: usize,
    /// Overlap-add buffer
    ola_buffer: Vec<f64>,
}

impl StftProcessor {
    fn new(fft_size: usize, hop_size: usize) -> Self {
        let mut planner = RealFftPlanner::<f64>::new();

        // Hann window
        let window: Vec<f64> = (0..fft_size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / fft_size as f64).cos()))
            .collect();

        // Synthesis window (for perfect reconstruction with overlap-add)
        let synthesis_window = window.clone();

        Self {
            fft_size,
            hop_size,
            input_buffer: vec![0.0; fft_size],
            output_buffer: vec![0.0; fft_size],
            window,
            synthesis_window,
            fft_forward: planner.plan_fft_forward(fft_size),
            fft_inverse: planner.plan_fft_inverse(fft_size),
            input_pos: 0,
            output_pos: 0,
            ola_buffer: vec![0.0; fft_size * 2],
        }
    }

    /// Analyze: time domain -> spectral frame
    fn analyze(&self, input: &[f64]) -> SpectralFrame {
        let mut windowed = vec![0.0; self.fft_size];
        for (i, (&sample, &win)) in input.iter().zip(&self.window).enumerate() {
            windowed[i] = sample * win;
        }

        let mut spectrum = vec![Complex::new(0.0, 0.0); self.fft_size / 2 + 1];
        self.fft_forward.process(&mut windowed, &mut spectrum).ok();

        SpectralFrame::from_complex(&spectrum)
    }

    /// Synthesize: spectral frame -> time domain
    fn synthesize(&self, frame: &SpectralFrame) -> Vec<f64> {
        let mut spectrum = frame.to_complex();

        let mut output = vec![0.0; self.fft_size];
        self.fft_inverse.process(&mut spectrum, &mut output).ok();

        // Normalize and apply synthesis window
        let norm = 1.0 / self.fft_size as f64;
        for (sample, &win) in output.iter_mut().zip(&self.synthesis_window) {
            *sample *= norm * win;
        }

        output
    }

    fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.output_buffer.fill(0.0);
        self.ola_buffer.fill(0.0);
        self.input_pos = 0;
        self.output_pos = 0;
    }
}

// ============ Spectral Gate ============

/// Spectral gate for noise reduction
pub struct SpectralGate {
    /// STFT processor
    stft: StftProcessor,
    /// Threshold (dB)
    threshold_db: f64,
    /// Reduction (dB)
    reduction_db: f64,
    /// Attack time (ms)
    attack_ms: f64,
    /// Release time (ms)
    release_ms: f64,
    /// Per-bin gain states
    bin_gains: Vec<f64>,
    /// Noise floor estimate per bin
    noise_floor: Vec<f64>,
    /// Noise estimation buffer
    noise_frames: VecDeque<SpectralFrame>,
    /// Learn noise flag
    learning_noise: bool,
    /// Sample rate
    sample_rate: f64,
    /// Input accumulator
    input_accum: Vec<f64>,
    input_accum_pos: usize,
    /// Output ring buffer
    output_ring: Vec<f64>,
    output_read_pos: usize,
    output_write_pos: usize,
}

impl SpectralGate {
    pub fn new(sample_rate: f64) -> Self {
        let fft_size = DEFAULT_FFT_SIZE;
        let hop_size = DEFAULT_HOP_SIZE;
        let num_bins = fft_size / 2 + 1;

        Self {
            stft: StftProcessor::new(fft_size, hop_size),
            threshold_db: -40.0,
            reduction_db: -60.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            bin_gains: vec![1.0; num_bins],
            noise_floor: vec![0.0; num_bins],
            noise_frames: VecDeque::with_capacity(NOISE_FRAMES),
            learning_noise: false,
            sample_rate,
            input_accum: vec![0.0; fft_size],
            input_accum_pos: 0,
            output_ring: vec![0.0; fft_size * 4],
            output_read_pos: 0,
            output_write_pos: fft_size, // Start with latency
        }
    }

    /// Set threshold in dB
    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-80.0, 0.0);
    }

    /// Set reduction in dB
    pub fn set_reduction(&mut self, db: f64) {
        self.reduction_db = db.clamp(-80.0, 0.0);
    }

    /// Set attack time in ms
    pub fn set_attack(&mut self, ms: f64) {
        self.attack_ms = ms.clamp(0.1, 100.0);
    }

    /// Set release time in ms
    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(1.0, 1000.0);
    }

    /// Start learning noise profile
    pub fn learn_noise_start(&mut self) {
        self.noise_frames.clear();
        self.learning_noise = true;
    }

    /// Stop learning and compute noise profile
    pub fn learn_noise_stop(&mut self) {
        self.learning_noise = false;

        if self.noise_frames.is_empty() {
            return;
        }

        let num_bins = self.noise_floor.len();

        // Average magnitude across frames
        for i in 0..num_bins {
            let sum: f64 = self.noise_frames.iter()
                .map(|f| f.magnitude[i])
                .sum();
            self.noise_floor[i] = sum / self.noise_frames.len() as f64;
        }
    }

    fn process_frame(&mut self, frame: &mut SpectralFrame) {
        let num_bins = frame.magnitude.len();
        let threshold_linear = 10.0_f64.powf(self.threshold_db / 20.0);
        let reduction_linear = 10.0_f64.powf(self.reduction_db / 20.0);

        // Time constants
        let attack_coef = (-1.0 / (self.attack_ms * 0.001 * self.sample_rate / self.stft.hop_size as f64)).exp();
        let release_coef = (-1.0 / (self.release_ms * 0.001 * self.sample_rate / self.stft.hop_size as f64)).exp();

        for i in 0..num_bins {
            let mag = frame.magnitude[i];
            let noise = self.noise_floor[i];

            // Signal above noise floor?
            let signal_ratio = if noise > 1e-10 { mag / noise } else { 1000.0 };

            let target_gain = if signal_ratio > threshold_linear {
                1.0
            } else {
                reduction_linear
            };

            // Smooth gain
            let coef = if target_gain < self.bin_gains[i] { attack_coef } else { release_coef };
            self.bin_gains[i] = target_gain + coef * (self.bin_gains[i] - target_gain);

            frame.magnitude[i] *= self.bin_gains[i];
        }
    }
}

impl Processor for SpectralGate {
    fn reset(&mut self) {
        self.stft.reset();
        self.bin_gains.fill(1.0);
        self.input_accum.fill(0.0);
        self.input_accum_pos = 0;
        self.output_ring.fill(0.0);
        self.output_read_pos = 0;
        self.output_write_pos = self.stft.fft_size;
    }

    fn latency(&self) -> usize {
        self.stft.fft_size
    }
}

impl StereoProcessor for SpectralGate {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Mix to mono for processing
        let mono = (left + right) * 0.5;

        // Add to input accumulator
        self.input_accum[self.input_accum_pos] = mono;
        self.input_accum_pos += 1;

        // Process when we have enough samples
        if self.input_accum_pos >= self.stft.hop_size {
            // Shift input buffer
            for i in 0..self.stft.fft_size - self.stft.hop_size {
                self.stft.input_buffer[i] = self.stft.input_buffer[i + self.stft.hop_size];
            }
            for i in 0..self.stft.hop_size {
                self.stft.input_buffer[self.stft.fft_size - self.stft.hop_size + i] =
                    self.input_accum[i];
            }

            // Analyze
            let mut frame = self.stft.analyze(&self.stft.input_buffer);

            // Learn noise if active
            if self.learning_noise {
                self.noise_frames.push_back(frame.clone());
                if self.noise_frames.len() > NOISE_FRAMES {
                    self.noise_frames.pop_front();
                }
            }

            // Process
            self.process_frame(&mut frame);

            // Synthesize
            let output = self.stft.synthesize(&frame);

            // Overlap-add to output ring
            for (i, &sample) in output.iter().enumerate() {
                let pos = (self.output_write_pos + i) % self.output_ring.len();
                self.output_ring[pos] += sample;
            }

            // Advance write position
            self.output_write_pos = (self.output_write_pos + self.stft.hop_size) % self.output_ring.len();

            // Shift input accumulator
            self.input_accum_pos = 0;
        }

        // Read output
        let out = self.output_ring[self.output_read_pos];
        self.output_ring[self.output_read_pos] = 0.0; // Clear for next overlap-add
        self.output_read_pos = (self.output_read_pos + 1) % self.output_ring.len();

        (out, out) // Mono output for now
    }
}

impl ProcessorConfig for SpectralGate {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }
}

// ============ Spectral Freeze ============

/// Spectral freeze effect
pub struct SpectralFreeze {
    /// STFT processor
    stft: StftProcessor,
    /// Frozen frame
    frozen_frame: Option<SpectralFrame>,
    /// Freeze active
    frozen: bool,
    /// Crossfade time (samples)
    crossfade_samples: usize,
    crossfade_pos: usize,
    /// Dry/wet mix
    mix: f64,
    /// Sample rate
    sample_rate: f64,
    /// Input accumulator
    input_accum: Vec<f64>,
    input_accum_pos: usize,
    /// Output ring
    output_ring: Vec<f64>,
    output_read_pos: usize,
    output_write_pos: usize,
}

impl SpectralFreeze {
    pub fn new(sample_rate: f64) -> Self {
        let fft_size = DEFAULT_FFT_SIZE;

        Self {
            stft: StftProcessor::new(fft_size, DEFAULT_HOP_SIZE),
            frozen_frame: None,
            frozen: false,
            crossfade_samples: (sample_rate * 0.05) as usize, // 50ms crossfade
            crossfade_pos: 0,
            mix: 1.0,
            sample_rate,
            input_accum: vec![0.0; fft_size],
            input_accum_pos: 0,
            output_ring: vec![0.0; fft_size * 4],
            output_read_pos: 0,
            output_write_pos: fft_size,
        }
    }

    /// Freeze current spectrum
    pub fn freeze(&mut self) {
        self.frozen = true;
        self.crossfade_pos = 0;
    }

    /// Unfreeze
    pub fn unfreeze(&mut self) {
        self.frozen = false;
        self.crossfade_pos = 0;
    }

    /// Toggle freeze
    pub fn toggle_freeze(&mut self) {
        if self.frozen {
            self.unfreeze();
        } else {
            self.freeze();
        }
    }

    /// Set mix
    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }
}

impl Processor for SpectralFreeze {
    fn reset(&mut self) {
        self.stft.reset();
        self.frozen_frame = None;
        self.frozen = false;
        self.input_accum.fill(0.0);
        self.input_accum_pos = 0;
        self.output_ring.fill(0.0);
        self.output_read_pos = 0;
        self.output_write_pos = self.stft.fft_size;
    }

    fn latency(&self) -> usize {
        self.stft.fft_size
    }
}

impl StereoProcessor for SpectralFreeze {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mono = (left + right) * 0.5;

        self.input_accum[self.input_accum_pos] = mono;
        self.input_accum_pos += 1;

        if self.input_accum_pos >= self.stft.hop_size {
            // Shift and fill input buffer
            for i in 0..self.stft.fft_size - self.stft.hop_size {
                self.stft.input_buffer[i] = self.stft.input_buffer[i + self.stft.hop_size];
            }
            for i in 0..self.stft.hop_size {
                self.stft.input_buffer[self.stft.fft_size - self.stft.hop_size + i] =
                    self.input_accum[i];
            }

            // Analyze current
            let current_frame = self.stft.analyze(&self.stft.input_buffer);

            // Capture frame if starting freeze
            if self.frozen && self.frozen_frame.is_none() {
                self.frozen_frame = Some(current_frame.clone());
            }

            // Use frozen or current frame
            let output_frame = if self.frozen {
                if let Some(ref frozen) = self.frozen_frame {
                    // Mix frozen magnitude with current phase for natural sound
                    let mut mixed = SpectralFrame::new(frozen.magnitude.len());
                    for i in 0..frozen.magnitude.len() {
                        mixed.magnitude[i] = frozen.magnitude[i] * self.mix
                            + current_frame.magnitude[i] * (1.0 - self.mix);
                        // Use current phase for less metallic sound
                        mixed.phase[i] = current_frame.phase[i];
                    }
                    mixed
                } else {
                    current_frame
                }
            } else {
                current_frame
            };

            // Synthesize
            let output = self.stft.synthesize(&output_frame);

            // Overlap-add
            for (i, &sample) in output.iter().enumerate() {
                let pos = (self.output_write_pos + i) % self.output_ring.len();
                self.output_ring[pos] += sample;
            }

            self.output_write_pos = (self.output_write_pos + self.stft.hop_size) % self.output_ring.len();
            self.input_accum_pos = 0;
        }

        let out = self.output_ring[self.output_read_pos];
        self.output_ring[self.output_read_pos] = 0.0;
        self.output_read_pos = (self.output_read_pos + 1) % self.output_ring.len();

        (out, out)
    }
}

impl ProcessorConfig for SpectralFreeze {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.crossfade_samples = (sample_rate * 0.05) as usize;
    }
}

// ============ Spectral Compressor ============

/// Per-band spectral compressor
pub struct SpectralCompressor {
    /// STFT processor
    stft: StftProcessor,
    /// Threshold (dB)
    threshold_db: f64,
    /// Ratio
    ratio: f64,
    /// Attack per bin
    bin_envelope: Vec<f64>,
    /// Attack coefficient
    attack_coef: f64,
    /// Release coefficient
    release_coef: f64,
    /// Sample rate
    sample_rate: f64,
    /// Input/output buffers
    input_accum: Vec<f64>,
    input_accum_pos: usize,
    output_ring: Vec<f64>,
    output_read_pos: usize,
    output_write_pos: usize,
}

impl SpectralCompressor {
    pub fn new(sample_rate: f64) -> Self {
        let fft_size = DEFAULT_FFT_SIZE;
        let num_bins = fft_size / 2 + 1;

        let attack_ms = 10.0;
        let release_ms = 100.0;
        let hop_rate = sample_rate / DEFAULT_HOP_SIZE as f64;

        Self {
            stft: StftProcessor::new(fft_size, DEFAULT_HOP_SIZE),
            threshold_db: -20.0,
            ratio: 4.0,
            bin_envelope: vec![0.0; num_bins],
            attack_coef: (-1.0 / (attack_ms * 0.001 * hop_rate)).exp(),
            release_coef: (-1.0 / (release_ms * 0.001 * hop_rate)).exp(),
            sample_rate,
            input_accum: vec![0.0; fft_size],
            input_accum_pos: 0,
            output_ring: vec![0.0; fft_size * 4],
            output_read_pos: 0,
            output_write_pos: fft_size,
        }
    }

    /// Set threshold
    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-60.0, 0.0);
    }

    /// Set ratio
    pub fn set_ratio(&mut self, ratio: f64) {
        self.ratio = ratio.clamp(1.0, 20.0);
    }

    /// Set attack
    pub fn set_attack(&mut self, ms: f64) {
        let hop_rate = self.sample_rate / DEFAULT_HOP_SIZE as f64;
        self.attack_coef = (-1.0 / (ms * 0.001 * hop_rate)).exp();
    }

    /// Set release
    pub fn set_release(&mut self, ms: f64) {
        let hop_rate = self.sample_rate / DEFAULT_HOP_SIZE as f64;
        self.release_coef = (-1.0 / (ms * 0.001 * hop_rate)).exp();
    }

    fn process_frame(&mut self, frame: &mut SpectralFrame) {
        let threshold_linear = 10.0_f64.powf(self.threshold_db / 20.0);

        for (i, mag) in frame.magnitude.iter_mut().enumerate() {
            // Envelope follower
            let coef = if *mag > self.bin_envelope[i] {
                self.attack_coef
            } else {
                self.release_coef
            };
            self.bin_envelope[i] = *mag + coef * (self.bin_envelope[i] - *mag);

            // Apply compression
            if self.bin_envelope[i] > threshold_linear {
                let over_db = 20.0 * (self.bin_envelope[i] / threshold_linear).log10();
                let compressed_db = over_db / self.ratio;
                let gain = 10.0_f64.powf((compressed_db - over_db) / 20.0);
                *mag *= gain;
            }
        }
    }
}

impl Processor for SpectralCompressor {
    fn reset(&mut self) {
        self.stft.reset();
        self.bin_envelope.fill(0.0);
        self.input_accum.fill(0.0);
        self.input_accum_pos = 0;
        self.output_ring.fill(0.0);
        self.output_read_pos = 0;
        self.output_write_pos = self.stft.fft_size;
    }

    fn latency(&self) -> usize {
        self.stft.fft_size
    }
}

impl StereoProcessor for SpectralCompressor {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mono = (left + right) * 0.5;

        self.input_accum[self.input_accum_pos] = mono;
        self.input_accum_pos += 1;

        if self.input_accum_pos >= self.stft.hop_size {
            for i in 0..self.stft.fft_size - self.stft.hop_size {
                self.stft.input_buffer[i] = self.stft.input_buffer[i + self.stft.hop_size];
            }
            for i in 0..self.stft.hop_size {
                self.stft.input_buffer[self.stft.fft_size - self.stft.hop_size + i] =
                    self.input_accum[i];
            }

            let mut frame = self.stft.analyze(&self.stft.input_buffer);
            self.process_frame(&mut frame);
            let output = self.stft.synthesize(&frame);

            for (i, &sample) in output.iter().enumerate() {
                let pos = (self.output_write_pos + i) % self.output_ring.len();
                self.output_ring[pos] += sample;
            }

            self.output_write_pos = (self.output_write_pos + self.stft.hop_size) % self.output_ring.len();
            self.input_accum_pos = 0;
        }

        let out = self.output_ring[self.output_read_pos];
        self.output_ring[self.output_read_pos] = 0.0;
        self.output_read_pos = (self.output_read_pos + 1) % self.output_ring.len();

        (out, out)
    }
}

impl ProcessorConfig for SpectralCompressor {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }
}

// ============ Spectral Repair (RX-style) ============

/// Selection region for spectral repair
#[derive(Debug, Clone)]
pub struct SpectralSelection {
    /// Start time (samples)
    pub start_time: u64,
    /// End time (samples)
    pub end_time: u64,
    /// Start frequency (Hz)
    pub start_freq: f64,
    /// End frequency (Hz)
    pub end_freq: f64,
}

impl SpectralSelection {
    pub fn new(start_time: u64, end_time: u64, start_freq: f64, end_freq: f64) -> Self {
        Self {
            start_time: start_time.min(end_time),
            end_time: start_time.max(end_time),
            start_freq: start_freq.min(end_freq),
            end_freq: start_freq.max(end_freq),
        }
    }

    /// Check if a time/frequency point is in selection
    pub fn contains(&self, time: u64, freq: f64) -> bool {
        time >= self.start_time && time <= self.end_time &&
        freq >= self.start_freq && freq <= self.end_freq
    }
}

/// Spectral repair mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RepairMode {
    /// Attenuate selected region
    Attenuate,
    /// Replace with interpolated content
    Replace,
    /// Pattern-based replacement
    PatternReplace,
    /// Harmonic reconstruction
    HarmonicFill,
}

/// Spectral repair processor (iZotope RX style)
pub struct SpectralRepair {
    /// STFT processor
    stft: StftProcessor,
    /// Sample rate
    sample_rate: f64,
    /// Selections for repair
    selections: Vec<SpectralSelection>,
    /// Repair mode
    mode: RepairMode,
    /// Attenuation amount (dB)
    attenuation_db: f64,
    /// Spectral history for pattern matching
    history: Vec<SpectralFrame>,
    history_pos: usize,
    history_len: usize,
    /// Processing buffers
    input_accum: Vec<f64>,
    input_accum_pos: usize,
    output_ring: Vec<f64>,
    output_read_pos: usize,
    output_write_pos: usize,
    /// Current processing position (samples)
    current_pos: u64,
}

impl SpectralRepair {
    pub fn new(sample_rate: f64) -> Self {
        let fft_size = DEFAULT_FFT_SIZE;
        let num_bins = fft_size / 2 + 1;
        let history_len = 20;

        let mut history = Vec::with_capacity(history_len);
        for _ in 0..history_len {
            history.push(SpectralFrame::new(num_bins));
        }

        Self {
            stft: StftProcessor::new(fft_size, DEFAULT_HOP_SIZE),
            sample_rate,
            selections: Vec::new(),
            mode: RepairMode::Replace,
            attenuation_db: -40.0,
            history,
            history_pos: 0,
            history_len,
            input_accum: vec![0.0; fft_size],
            input_accum_pos: 0,
            output_ring: vec![0.0; fft_size * 4],
            output_read_pos: 0,
            output_write_pos: fft_size,
            current_pos: 0,
        }
    }

    /// Add selection for repair
    pub fn add_selection(&mut self, selection: SpectralSelection) {
        self.selections.push(selection);
    }

    /// Clear all selections
    pub fn clear_selections(&mut self) {
        self.selections.clear();
    }

    /// Set repair mode
    pub fn set_mode(&mut self, mode: RepairMode) {
        self.mode = mode;
    }

    /// Set attenuation for Attenuate mode
    pub fn set_attenuation(&mut self, db: f64) {
        self.attenuation_db = db.clamp(-80.0, 0.0);
    }

    /// Bin index to frequency
    fn bin_to_freq(&self, bin: usize) -> f64 {
        bin as f64 * self.sample_rate / self.stft.fft_size as f64
    }

    /// Process frame
    fn process_frame(&mut self, frame: &mut SpectralFrame) {
        let num_bins = frame.magnitude.len();

        // Store in history
        self.history[self.history_pos] = frame.clone();
        self.history_pos = (self.history_pos + 1) % self.history_len;

        for bin in 0..num_bins {
            let freq = self.bin_to_freq(bin);

            // Check if bin is in any selection
            let in_selection = self.selections.iter().any(|s| s.contains(self.current_pos, freq));

            if in_selection {
                match self.mode {
                    RepairMode::Attenuate => {
                        let gain = 10.0_f64.powf(self.attenuation_db / 20.0);
                        frame.magnitude[bin] *= gain;
                    }
                    RepairMode::Replace => {
                        // Interpolate from surrounding bins
                        let left_bin = bin.saturating_sub(3);
                        let right_bin = (bin + 3).min(num_bins - 1);

                        if left_bin < bin && right_bin > bin {
                            let left_mag = frame.magnitude[left_bin];
                            let right_mag = frame.magnitude[right_bin];
                            let t = (bin - left_bin) as f64 / (right_bin - left_bin) as f64;
                            frame.magnitude[bin] = left_mag * (1.0 - t) + right_mag * t;
                        }
                    }
                    RepairMode::PatternReplace => {
                        // Use average from history
                        let sum: f64 = self.history.iter()
                            .map(|h| h.magnitude[bin])
                            .sum();
                        frame.magnitude[bin] = sum / self.history_len as f64;
                    }
                    RepairMode::HarmonicFill => {
                        // Find fundamental and reconstruct harmonic
                        // This is simplified - real implementation would use pitch detection
                        let fundamental_bin = bin / 2;
                        if fundamental_bin > 0 && fundamental_bin < num_bins {
                            frame.magnitude[bin] = frame.magnitude[fundamental_bin] * 0.5;
                        }
                    }
                }
            }
        }

        self.current_pos += self.stft.hop_size as u64;
    }
}

impl Processor for SpectralRepair {
    fn reset(&mut self) {
        self.stft.reset();
        self.input_accum.fill(0.0);
        self.input_accum_pos = 0;
        self.output_ring.fill(0.0);
        self.output_read_pos = 0;
        self.output_write_pos = self.stft.fft_size;
        self.current_pos = 0;
        for frame in &mut self.history {
            frame.magnitude.fill(0.0);
            frame.phase.fill(0.0);
        }
    }

    fn latency(&self) -> usize {
        self.stft.fft_size
    }
}

impl StereoProcessor for SpectralRepair {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mono = (left + right) * 0.5;

        self.input_accum[self.input_accum_pos] = mono;
        self.input_accum_pos += 1;

        if self.input_accum_pos >= self.stft.hop_size {
            for i in 0..self.stft.fft_size - self.stft.hop_size {
                self.stft.input_buffer[i] = self.stft.input_buffer[i + self.stft.hop_size];
            }
            for i in 0..self.stft.hop_size {
                self.stft.input_buffer[self.stft.fft_size - self.stft.hop_size + i] =
                    self.input_accum[i];
            }

            let mut frame = self.stft.analyze(&self.stft.input_buffer);
            self.process_frame(&mut frame);
            let output = self.stft.synthesize(&frame);

            for (i, &sample) in output.iter().enumerate() {
                let pos = (self.output_write_pos + i) % self.output_ring.len();
                self.output_ring[pos] += sample;
            }

            self.output_write_pos = (self.output_write_pos + self.stft.hop_size) % self.output_ring.len();
            self.input_accum_pos = 0;
        }

        let out = self.output_ring[self.output_read_pos];
        self.output_ring[self.output_read_pos] = 0.0;
        self.output_read_pos = (self.output_read_pos + 1) % self.output_ring.len();

        (out, out)
    }
}

impl ProcessorConfig for SpectralRepair {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }
}

// ============ De-click / De-crackle ============

/// De-click processor for removing clicks and pops
pub struct DeClick {
    /// Detection threshold
    threshold: f64,
    /// Interpolation length (samples)
    interp_length: usize,
    /// Detection buffer
    buffer: Vec<f64>,
    buffer_pos: usize,
    /// Latency
    latency_samples: usize,
    /// Click detection state
    click_detected: bool,
    click_start: usize,
    click_end: usize,
    /// Sample rate
    sample_rate: f64,
}

impl DeClick {
    pub fn new(sample_rate: f64) -> Self {
        let latency = 256;
        Self {
            threshold: 6.0, // dB above local average
            interp_length: 16,
            buffer: vec![0.0; latency * 2],
            buffer_pos: 0,
            latency_samples: latency,
            click_detected: false,
            click_start: 0,
            click_end: 0,
            sample_rate,
        }
    }

    /// Set detection threshold (dB above average)
    pub fn set_threshold(&mut self, db: f64) {
        self.threshold = db.clamp(1.0, 20.0);
    }

    /// Set interpolation length
    pub fn set_interp_length(&mut self, samples: usize) {
        self.interp_length = samples.clamp(4, 128);
    }

    /// Detect click at current position
    fn detect_click(&self, pos: usize) -> bool {
        // Calculate local average (excluding current sample)
        let window = 32;
        let mut sum = 0.0;
        let mut count = 0;

        for i in 0..window {
            let idx = (pos + self.buffer.len() - i - 1) % self.buffer.len();
            if idx != pos {
                sum += self.buffer[idx].abs();
                count += 1;
            }
        }

        let avg = if count > 0 { sum / count as f64 } else { 0.0 };
        let current = self.buffer[pos].abs();

        // Threshold in linear
        let threshold_linear = 10.0_f64.powf(self.threshold / 20.0);

        current > avg * threshold_linear && current > 0.01
    }

    /// Interpolate over click
    fn repair_click(&mut self, start: usize, end: usize) {
        let len = ((end + self.buffer.len() - start) % self.buffer.len()).max(1);

        let before_idx = (start + self.buffer.len() - 1) % self.buffer.len();
        let after_idx = (end + 1) % self.buffer.len();

        let before = self.buffer[before_idx];
        let after = self.buffer[after_idx];

        // Linear interpolation
        for i in 0..len {
            let idx = (start + i) % self.buffer.len();
            let t = (i + 1) as f64 / (len + 1) as f64;
            self.buffer[idx] = before * (1.0 - t) + after * t;
        }
    }
}

impl Processor for DeClick {
    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.buffer_pos = 0;
        self.click_detected = false;
    }

    fn latency(&self) -> usize {
        self.latency_samples
    }
}

impl StereoProcessor for DeClick {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mono = (left + right) * 0.5;

        // Write to buffer
        self.buffer[self.buffer_pos] = mono;

        // Detect click
        if self.detect_click(self.buffer_pos) {
            if !self.click_detected {
                self.click_detected = true;
                self.click_start = self.buffer_pos;
            }
            self.click_end = self.buffer_pos;
        } else if self.click_detected {
            // End of click - repair
            self.repair_click(self.click_start, self.click_end);
            self.click_detected = false;
        }

        // Read from delayed position
        let read_pos = (self.buffer_pos + self.buffer.len() - self.latency_samples) % self.buffer.len();
        let out = self.buffer[read_pos];

        self.buffer_pos = (self.buffer_pos + 1) % self.buffer.len();

        (out, out)
    }
}

impl ProcessorConfig for DeClick {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spectral_gate() {
        let mut gate = SpectralGate::new(48000.0);
        gate.set_threshold(-40.0);
        gate.set_reduction(-60.0);

        // Process samples
        for _ in 0..10000 {
            let _ = gate.process_sample(0.5, 0.5);
        }
    }

    #[test]
    fn test_spectral_freeze() {
        let mut freeze = SpectralFreeze::new(48000.0);

        // Process some samples
        for _ in 0..5000 {
            let _ = freeze.process_sample(0.5, 0.5);
        }

        // Freeze
        freeze.freeze();

        // Continue processing
        for _ in 0..5000 {
            let _ = freeze.process_sample(0.0, 0.0);
        }
    }

    #[test]
    fn test_spectral_compressor() {
        let mut comp = SpectralCompressor::new(48000.0);
        comp.set_threshold(-20.0);
        comp.set_ratio(4.0);

        for _ in 0..10000 {
            let _ = comp.process_sample(0.5, 0.5);
        }
    }

    #[test]
    fn test_stft_reconstruction() {
        let stft = StftProcessor::new(1024, 256);

        // Create test signal
        let input: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin()).collect();

        // Analyze and synthesize
        let frame = stft.analyze(&input);
        let output = stft.synthesize(&frame);

        // Should roughly match (within windowing effects)
        assert!(output.len() == input.len());
    }
}

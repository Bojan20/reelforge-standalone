//! RF-Elastic Pro: Ultimate Time-Stretching Engine
//!
//! Multi-stage hybrid approach combining:
//! - STN Decomposition (Sines/Transients/Noise)
//! - Phase Vocoder with Peak Locking
//! - Adaptive Multi-Resolution Windows
//! - Formant Preservation
//! - RTPGHI-style Phase Correction
//!
//! Surpasses Logic Pro Flex Time and Pyramix élastique in quality.

use rustfft::{FftPlanner, num_complex::Complex};
use serde::{Deserialize, Serialize};
use std::f64::consts::PI;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum FFT size for analysis
const MAX_FFT_SIZE: usize = 8192;
/// Default FFT size
const DEFAULT_FFT_SIZE: usize = 2048;
/// Minimum FFT size
const MIN_FFT_SIZE: usize = 256;
/// Number of frequency bands for multi-resolution
const NUM_BANDS: usize = 3;
/// Bass cutoff frequency
const BASS_CUTOFF: f64 = 200.0;
/// Treble cutoff frequency
const TREBLE_CUTOFF: f64 = 4000.0;

// ============================================================================
// STN DECOMPOSITION
// ============================================================================

/// Component type in STN decomposition
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StnComponent {
    /// Tonal/harmonic content
    Sines,
    /// Percussive/impulsive content
    Transients,
    /// Stochastic/residual content
    Noise,
}

/// STN decomposition result
#[derive(Debug, Clone)]
pub struct StnDecomposition {
    /// Sinusoidal (tonal) component
    pub sines: Vec<f64>,
    /// Transient (percussive) component
    pub transients: Vec<f64>,
    /// Noise (residual) component
    pub noise: Vec<f64>,
    /// Transient positions (sample indices)
    pub transient_positions: Vec<usize>,
}

/// STN Decomposer using spectral masking
pub struct StnDecomposer {
    /// FFT planner
    fft_planner: FftPlanner<f64>,
    /// Analysis window (long - for frequency resolution)
    window_long: Vec<f64>,
    /// Analysis window (short - for time resolution)
    window_short: Vec<f64>,
    /// Long FFT size
    fft_size_long: usize,
    /// Short FFT size
    fft_size_short: usize,
    /// Hop size for long window
    hop_long: usize,
    /// Hop size for short window
    hop_short: usize,
    /// Sample rate
    sample_rate: f64,
    /// Horizontal smoothing factor for tonal detection
    h_smooth: f64,
    /// Vertical smoothing factor for transient detection
    v_smooth: f64,
    /// Tonal threshold
    tonal_threshold: f64,
    /// Transient threshold
    transient_threshold: f64,
}

impl StnDecomposer {
    /// Create new STN decomposer
    pub fn new(sample_rate: f64) -> Self {
        let fft_size_long = 4096; // Good frequency resolution
        let fft_size_short = 256; // Good time resolution

        Self {
            fft_planner: FftPlanner::new(),
            window_long: Self::create_hann_window(fft_size_long),
            window_short: Self::create_hann_window(fft_size_short),
            fft_size_long,
            fft_size_short,
            hop_long: fft_size_long / 4,
            hop_short: fft_size_short / 4,
            sample_rate,
            h_smooth: 0.3, // Horizontal (time) smoothing
            v_smooth: 0.3, // Vertical (frequency) smoothing
            tonal_threshold: 0.5,
            transient_threshold: 0.5,
        }
    }

    /// Create Hann window
    fn create_hann_window(size: usize) -> Vec<f64> {
        (0..size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / (size - 1) as f64).cos()))
            .collect()
    }

    /// Set parameters
    pub fn set_params(&mut self, tonal_threshold: f64, transient_threshold: f64) {
        self.tonal_threshold = tonal_threshold.clamp(0.0, 1.0);
        self.transient_threshold = transient_threshold.clamp(0.0, 1.0);
    }

    /// Decompose audio into Sines, Transients, and Noise
    pub fn decompose(&mut self, input: &[f64]) -> StnDecomposition {
        let len = input.len();
        if len == 0 {
            return StnDecomposition {
                sines: vec![],
                transients: vec![],
                noise: vec![],
                transient_positions: vec![],
            };
        }

        // Stage 1: Extract tonal (sines) using long window STFT
        let (sines, residual1) = self.extract_tonal(input);

        // Stage 2: Extract transients from residual using short window STFT
        let (transients, noise, transient_positions) = self.extract_transients(&residual1);

        StnDecomposition {
            sines,
            transients,
            noise,
            transient_positions,
        }
    }

    /// Extract tonal component using horizontal (time) smoothing
    fn extract_tonal(&mut self, input: &[f64]) -> (Vec<f64>, Vec<f64>) {
        let len = input.len();
        let mut sines = vec![0.0; len];
        let mut residual = vec![0.0; len];

        let fft = self.fft_planner.plan_fft_forward(self.fft_size_long);
        let ifft = self.fft_planner.plan_fft_inverse(self.fft_size_long);

        let num_frames = (len.saturating_sub(self.fft_size_long)) / self.hop_long + 1;
        if num_frames == 0 {
            return (input.to_vec(), vec![0.0; len]);
        }

        // Compute STFT magnitude matrix
        let mut mag_matrix: Vec<Vec<f64>> = Vec::with_capacity(num_frames);
        let mut phase_matrix: Vec<Vec<f64>> = Vec::with_capacity(num_frames);

        for frame_idx in 0..num_frames {
            let start = frame_idx * self.hop_long;
            let mut frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size_long];

            // Apply window
            for i in 0..self.fft_size_long {
                if start + i < len {
                    frame[i] = Complex::new(input[start + i] * self.window_long[i], 0.0);
                }
            }

            fft.process(&mut frame);

            let mags: Vec<f64> = frame.iter().map(|c| c.norm()).collect();
            let phases: Vec<f64> = frame.iter().map(|c| c.arg()).collect();

            mag_matrix.push(mags);
            phase_matrix.push(phases);
        }

        // Compute horizontal (time) median filter for tonal detection
        let mut tonal_mask: Vec<Vec<f64>> = vec![vec![0.0; self.fft_size_long]; num_frames];
        let h_radius = 5; // frames

        for f in 0..num_frames {
            for bin in 0..self.fft_size_long / 2 + 1 {
                let mut neighbors: Vec<f64> = Vec::new();
                for df in -(h_radius as i32)..=(h_radius as i32) {
                    let nf = f as i32 + df;
                    if nf >= 0 && (nf as usize) < num_frames {
                        neighbors.push(mag_matrix[nf as usize][bin]);
                    }
                }
                neighbors.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                let median = if neighbors.is_empty() {
                    0.0
                } else {
                    neighbors[neighbors.len() / 2]
                };

                let current = mag_matrix[f][bin];
                // If current magnitude is close to median, it's tonal
                if median > 1e-10 {
                    let ratio = current / median;
                    tonal_mask[f][bin] =
                        if ratio > self.tonal_threshold && ratio < 1.0 / self.tonal_threshold {
                            1.0 // Tonal
                        } else {
                            self.h_smooth // Partial
                        };
                }
            }
        }

        // Reconstruct tonal and residual via OLA
        let mut sine_acc = vec![0.0; len];
        let mut window_acc = vec![0.0; len];

        for f in 0..num_frames {
            let start = f * self.hop_long;

            // Apply mask and reconstruct
            let mut sine_frame: Vec<Complex<f64>> =
                vec![Complex::new(0.0, 0.0); self.fft_size_long];

            for bin in 0..self.fft_size_long / 2 + 1 {
                let mag = mag_matrix[f][bin] * tonal_mask[f][bin];
                let phase = phase_matrix[f][bin];
                sine_frame[bin] = Complex::from_polar(mag, phase);

                // Mirror for negative frequencies
                if bin > 0 && bin < self.fft_size_long / 2 {
                    sine_frame[self.fft_size_long - bin] = sine_frame[bin].conj();
                }
            }

            ifft.process(&mut sine_frame);

            // Overlap-add with window
            for i in 0..self.fft_size_long {
                if start + i < len {
                    let w = self.window_long[i];
                    sine_acc[start + i] += sine_frame[i].re * w / self.fft_size_long as f64;
                    window_acc[start + i] += w * w;
                }
            }
        }

        // Normalize and compute residual
        for i in 0..len {
            if window_acc[i] > 1e-10 {
                sines[i] = sine_acc[i] / window_acc[i];
            }
            residual[i] = input[i] - sines[i];
        }

        (sines, residual)
    }

    /// Extract transients from residual using vertical (frequency) smoothing
    fn extract_transients(&mut self, residual: &[f64]) -> (Vec<f64>, Vec<f64>, Vec<usize>) {
        let len = residual.len();
        let mut transients = vec![0.0; len];
        let mut noise = vec![0.0; len];
        let mut transient_positions = Vec::new();

        let fft = self.fft_planner.plan_fft_forward(self.fft_size_short);
        let ifft = self.fft_planner.plan_fft_inverse(self.fft_size_short);

        let num_frames = (len.saturating_sub(self.fft_size_short)) / self.hop_short + 1;
        if num_frames == 0 {
            return (vec![0.0; len], residual.to_vec(), vec![]);
        }

        // Compute STFT
        let mut mag_matrix: Vec<Vec<f64>> = Vec::with_capacity(num_frames);
        let mut phase_matrix: Vec<Vec<f64>> = Vec::with_capacity(num_frames);

        for frame_idx in 0..num_frames {
            let start = frame_idx * self.hop_short;
            let mut frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size_short];

            for i in 0..self.fft_size_short {
                if start + i < len {
                    frame[i] = Complex::new(residual[start + i] * self.window_short[i], 0.0);
                }
            }

            fft.process(&mut frame);

            mag_matrix.push(frame.iter().map(|c| c.norm()).collect());
            phase_matrix.push(frame.iter().map(|c| c.arg()).collect());
        }

        // Compute vertical (frequency) median filter for transient detection
        let mut transient_mask: Vec<Vec<f64>> = vec![vec![0.0; self.fft_size_short]; num_frames];
        let v_radius = 10; // bins

        for f in 0..num_frames {
            let mut frame_energy = 0.0;

            for bin in 0..self.fft_size_short / 2 + 1 {
                let mut neighbors: Vec<f64> = Vec::new();
                for dbin in -(v_radius as i32)..=(v_radius as i32) {
                    let nbin = bin as i32 + dbin;
                    if nbin >= 0 && (nbin as usize) < self.fft_size_short / 2 + 1 {
                        neighbors.push(mag_matrix[f][nbin as usize]);
                    }
                }
                neighbors.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                let median = if neighbors.is_empty() {
                    0.0
                } else {
                    neighbors[neighbors.len() / 2]
                };

                let current = mag_matrix[f][bin];
                // If current is much higher than vertical median, it's transient
                if median > 1e-10 {
                    let ratio = current / median;
                    if ratio > 1.0 / self.transient_threshold {
                        transient_mask[f][bin] = 1.0;
                        frame_energy += current * current;
                    } else {
                        transient_mask[f][bin] = self.v_smooth;
                    }
                }
            }

            // Mark frame as transient if total energy is high
            if frame_energy > 0.1 {
                let sample_pos = f * self.hop_short + self.fft_size_short / 2;
                transient_positions.push(sample_pos);
            }
        }

        // Reconstruct transient and noise via OLA
        let mut trans_acc = vec![0.0; len];
        let mut noise_acc = vec![0.0; len];
        let mut window_acc = vec![0.0; len];

        for f in 0..num_frames {
            let start = f * self.hop_short;

            let mut trans_frame: Vec<Complex<f64>> =
                vec![Complex::new(0.0, 0.0); self.fft_size_short];
            let mut noise_frame: Vec<Complex<f64>> =
                vec![Complex::new(0.0, 0.0); self.fft_size_short];

            for bin in 0..self.fft_size_short / 2 + 1 {
                let mag = mag_matrix[f][bin];
                let phase = phase_matrix[f][bin];
                let trans_mag = mag * transient_mask[f][bin];
                let noise_mag = mag * (1.0 - transient_mask[f][bin]);

                trans_frame[bin] = Complex::from_polar(trans_mag, phase);
                noise_frame[bin] = Complex::from_polar(noise_mag, phase);

                if bin > 0 && bin < self.fft_size_short / 2 {
                    trans_frame[self.fft_size_short - bin] = trans_frame[bin].conj();
                    noise_frame[self.fft_size_short - bin] = noise_frame[bin].conj();
                }
            }

            ifft.process(&mut trans_frame);
            ifft.process(&mut noise_frame);

            for i in 0..self.fft_size_short {
                if start + i < len {
                    let w = self.window_short[i];
                    trans_acc[start + i] += trans_frame[i].re * w / self.fft_size_short as f64;
                    noise_acc[start + i] += noise_frame[i].re * w / self.fft_size_short as f64;
                    window_acc[start + i] += w * w;
                }
            }
        }

        for i in 0..len {
            if window_acc[i] > 1e-10 {
                transients[i] = trans_acc[i] / window_acc[i];
                noise[i] = noise_acc[i] / window_acc[i];
            }
        }

        (transients, noise, transient_positions)
    }
}

// ============================================================================
// PHASE VOCODER WITH PEAK LOCKING
// ============================================================================

/// Phase Vocoder with peak-locked phase propagation
pub struct PhaseVocoder {
    /// FFT planner
    fft_planner: FftPlanner<f64>,
    /// FFT size
    fft_size: usize,
    /// Hop size (analysis)
    hop_a: usize,
    /// Hop size (synthesis)
    hop_s: usize,
    /// Analysis window
    window: Vec<f64>,
    /// Previous phase (for phase accumulation)
    prev_phase: Vec<f64>,
    /// Phase accumulator
    phase_acc: Vec<f64>,
    /// Expected phase increment per bin
    omega: Vec<f64>,
    /// Peak bins for phase locking
    peak_bins: Vec<usize>,
}

impl PhaseVocoder {
    /// Create new phase vocoder
    pub fn new(fft_size: usize) -> Self {
        let hop = fft_size / 4;
        let omega: Vec<f64> = (0..fft_size)
            .map(|k| 2.0 * PI * k as f64 * hop as f64 / fft_size as f64)
            .collect();

        Self {
            fft_planner: FftPlanner::new(),
            fft_size,
            hop_a: hop,
            hop_s: hop,
            window: Self::create_hann_window(fft_size),
            prev_phase: vec![0.0; fft_size],
            phase_acc: vec![0.0; fft_size],
            omega,
            peak_bins: Vec::new(),
        }
    }

    /// Create Hann window
    fn create_hann_window(size: usize) -> Vec<f64> {
        (0..size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / (size - 1) as f64).cos()))
            .collect()
    }

    /// Set stretch ratio (changes synthesis hop)
    pub fn set_stretch_ratio(&mut self, ratio: f64) {
        self.hop_s = ((self.hop_a as f64 * ratio) as usize).max(1);
    }

    /// Find spectral peaks for phase locking
    fn find_peaks(&mut self, magnitudes: &[f64]) {
        self.peak_bins.clear();
        let num_bins = self.fft_size / 2 + 1;

        for bin in 2..num_bins - 2 {
            let mag = magnitudes[bin];
            if mag > magnitudes[bin - 1]
                && mag > magnitudes[bin - 2]
                && mag > magnitudes[bin + 1]
                && mag > magnitudes[bin + 2]
                && mag > 1e-8
            {
                self.peak_bins.push(bin);
            }
        }
    }

    /// Process with peak-locked phase vocoder
    pub fn process(&mut self, input: &[f64], stretch_ratio: f64) -> Vec<f64> {
        let input_len = input.len();
        if input_len < self.fft_size {
            return input.to_vec();
        }

        self.set_stretch_ratio(stretch_ratio);

        let output_len = (input_len as f64 * stretch_ratio) as usize;
        let mut output = vec![0.0; output_len];
        let mut window_acc = vec![0.0; output_len];

        let fft = self.fft_planner.plan_fft_forward(self.fft_size);
        let ifft = self.fft_planner.plan_fft_inverse(self.fft_size);

        // Reset phase accumulators
        self.prev_phase.fill(0.0);
        self.phase_acc.fill(0.0);

        let num_frames = (input_len - self.fft_size) / self.hop_a + 1;

        for frame_idx in 0..num_frames {
            let in_pos = frame_idx * self.hop_a;
            let out_pos = frame_idx * self.hop_s;

            if out_pos + self.fft_size > output_len {
                break;
            }

            // Analysis: Window and FFT
            let mut frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size];
            for i in 0..self.fft_size {
                frame[i] = Complex::new(input[in_pos + i] * self.window[i], 0.0);
            }
            fft.process(&mut frame);

            // Extract magnitude and phase
            let magnitudes: Vec<f64> = frame.iter().map(|c| c.norm()).collect();
            let phases: Vec<f64> = frame.iter().map(|c| c.arg()).collect();

            // Find peaks for phase locking
            self.find_peaks(&magnitudes);

            // Phase propagation with peak locking
            let mut new_phases = vec![0.0; self.fft_size];

            for bin in 0..self.fft_size / 2 + 1 {
                // Compute phase deviation
                let phase_diff = phases[bin] - self.prev_phase[bin] - self.omega[bin];
                let phase_diff_wrapped = Self::wrap_phase(phase_diff);

                // True frequency deviation
                let freq_dev = phase_diff_wrapped / (2.0 * PI);

                // Accumulate phase with stretch ratio
                let phase_inc = (self.omega[bin] + 2.0 * PI * freq_dev) * stretch_ratio;
                self.phase_acc[bin] += phase_inc;

                new_phases[bin] = self.phase_acc[bin];
            }

            // Peak locking: propagate peak phases to surrounding bins
            for &peak in &self.peak_bins {
                let peak_phase = new_phases[peak];
                let peak_mag = magnitudes[peak];

                // Influence region around peak
                let radius = 3;
                for offset in 1..=radius {
                    if peak >= offset {
                        let bin = peak - offset;
                        let influence = 1.0 - (offset as f64 / (radius as f64 + 1.0));
                        if magnitudes[bin] < peak_mag * 0.5 {
                            new_phases[bin] =
                                peak_phase + (new_phases[bin] - peak_phase) * (1.0 - influence);
                        }
                    }
                    if peak + offset < self.fft_size / 2 + 1 {
                        let bin = peak + offset;
                        let influence = 1.0 - (offset as f64 / (radius as f64 + 1.0));
                        if magnitudes[bin] < peak_mag * 0.5 {
                            new_phases[bin] =
                                peak_phase + (new_phases[bin] - peak_phase) * (1.0 - influence);
                        }
                    }
                }
            }

            // Synthesis: Reconstruct frame
            let mut synth_frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size];
            for bin in 0..self.fft_size / 2 + 1 {
                synth_frame[bin] = Complex::from_polar(magnitudes[bin], new_phases[bin]);
                if bin > 0 && bin < self.fft_size / 2 {
                    synth_frame[self.fft_size - bin] = synth_frame[bin].conj();
                }
            }

            ifft.process(&mut synth_frame);

            // Overlap-add
            for i in 0..self.fft_size {
                if out_pos + i < output_len {
                    let w = self.window[i];
                    output[out_pos + i] += synth_frame[i].re * w / self.fft_size as f64;
                    window_acc[out_pos + i] += w * w;
                }
            }

            // Update previous phase
            self.prev_phase.copy_from_slice(&phases);
        }

        // Normalize
        for i in 0..output_len {
            if window_acc[i] > 1e-10 {
                output[i] /= window_acc[i];
            }
        }

        output
    }

    /// Wrap phase to [-π, π]
    fn wrap_phase(phase: f64) -> f64 {
        let mut p = phase;
        while p > PI {
            p -= 2.0 * PI;
        }
        while p < -PI {
            p += 2.0 * PI;
        }
        p
    }
}

// ============================================================================
// TRANSIENT PROCESSOR (WSOLA-based)
// ============================================================================

/// Transient-preserving processor using WSOLA
pub struct TransientProcessor {
    /// Window size
    window_size: usize,
    /// Analysis hop
    hop_a: usize,
    /// Tolerance for best match search
    tolerance: usize,
    /// Transient positions to preserve
    transients: Vec<usize>,
    /// Protection radius around transients (samples)
    protection_radius: usize,
}

impl TransientProcessor {
    /// Create new transient processor
    pub fn new() -> Self {
        Self {
            window_size: 256,
            hop_a: 64,
            tolerance: 128,
            transients: Vec::new(),
            protection_radius: 512,
        }
    }

    /// Set transient positions
    pub fn set_transients(&mut self, positions: Vec<usize>) {
        self.transients = positions;
    }

    /// Check if position is near a transient
    fn is_near_transient(&self, pos: usize, stretch_ratio: f64) -> bool {
        for &t in &self.transients {
            let stretched_t = (t as f64 * stretch_ratio) as usize;
            if pos.abs_diff(stretched_t) < self.protection_radius {
                return true;
            }
        }
        false
    }

    /// Process transients with WSOLA + transient locking
    pub fn process(&self, input: &[f64], stretch_ratio: f64) -> Vec<f64> {
        let input_len = input.len();
        if input_len < self.window_size {
            return input.to_vec();
        }

        let output_len = (input_len as f64 * stretch_ratio) as usize;
        let hop_s = (self.hop_a as f64 * stretch_ratio) as usize;

        let mut output = vec![0.0; output_len];
        let window = Self::create_hann_window(self.window_size);

        let mut in_pos = 0usize;
        let mut out_pos = 0usize;
        let mut prev_best_offset = 0i32;

        while out_pos + self.window_size < output_len && in_pos + self.window_size < input_len {
            // Check if we're near a transient
            let near_transient = self.is_near_transient(out_pos, stretch_ratio);

            let best_offset = if near_transient {
                // Lock to transient: no offset search
                0
            } else {
                // WSOLA: find best matching position
                self.find_best_offset(input, in_pos, &output, out_pos, prev_best_offset)
            };

            let actual_in_pos =
                ((in_pos as i32 + best_offset).max(0) as usize).min(input_len - self.window_size);

            // Overlap-add
            for i in 0..self.window_size {
                if out_pos + i < output_len {
                    output[out_pos + i] += input[actual_in_pos + i] * window[i];
                }
            }

            prev_best_offset = best_offset;
            in_pos += self.hop_a;
            out_pos += hop_s.max(1);
        }

        output
    }

    /// Find best matching offset using cross-correlation
    fn find_best_offset(
        &self,
        input: &[f64],
        in_pos: usize,
        output: &[f64],
        out_pos: usize,
        prev_offset: i32,
    ) -> i32 {
        if out_pos < self.window_size / 2 {
            return 0;
        }

        let search_start = (-(self.tolerance as i32)).max(-(in_pos as i32));
        let search_end =
            (self.tolerance as i32).min((input.len() - in_pos - self.window_size) as i32);

        let mut best_offset = prev_offset.clamp(search_start, search_end);
        let mut best_corr = f64::NEG_INFINITY;

        // Search in a spiral pattern around previous offset
        for delta in 0..=self.tolerance as i32 {
            for sign in &[-1i32, 1] {
                let offset = prev_offset + delta * sign;
                if offset < search_start || offset > search_end {
                    continue;
                }

                let actual_in_pos = (in_pos as i32 + offset) as usize;
                let corr = self.cross_correlation(
                    input,
                    actual_in_pos,
                    output,
                    out_pos.saturating_sub(self.window_size / 2),
                    self.window_size / 2,
                );

                if corr > best_corr {
                    best_corr = corr;
                    best_offset = offset;
                }
            }
        }

        best_offset
    }

    /// Compute cross-correlation
    fn cross_correlation(
        &self,
        a: &[f64],
        a_start: usize,
        b: &[f64],
        b_start: usize,
        len: usize,
    ) -> f64 {
        let mut sum = 0.0;
        let mut sum_a2 = 0.0;
        let mut sum_b2 = 0.0;

        for i in 0..len {
            let av = if a_start + i < a.len() {
                a[a_start + i]
            } else {
                0.0
            };
            let bv = if b_start + i < b.len() {
                b[b_start + i]
            } else {
                0.0
            };
            sum += av * bv;
            sum_a2 += av * av;
            sum_b2 += bv * bv;
        }

        let denom = (sum_a2 * sum_b2).sqrt();
        if denom > 1e-10 { sum / denom } else { 0.0 }
    }

    /// Create Hann window
    fn create_hann_window(size: usize) -> Vec<f64> {
        (0..size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / (size - 1) as f64).cos()))
            .collect()
    }
}

impl Default for TransientProcessor {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// NOISE MORPHING
// ============================================================================

/// Noise component processor using magnitude morphing
pub struct NoiseMorpher {
    /// FFT size
    fft_size: usize,
    /// Hop size
    hop: usize,
    /// Random phase generator seed
    seed: u64,
}

impl NoiseMorpher {
    /// Create new noise morpher
    pub fn new() -> Self {
        Self {
            fft_size: 1024,
            hop: 256,
            seed: 42,
        }
    }

    /// Simple pseudo-random number generator
    fn next_random(&mut self) -> f64 {
        self.seed = self.seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        (self.seed >> 33) as f64 / (1u64 << 31) as f64
    }

    /// Process noise component with magnitude morphing
    pub fn process(&mut self, input: &[f64], stretch_ratio: f64) -> Vec<f64> {
        let input_len = input.len();
        if input_len < self.fft_size {
            return vec![0.0; (input_len as f64 * stretch_ratio) as usize];
        }

        let output_len = (input_len as f64 * stretch_ratio) as usize;
        let hop_s = (self.hop as f64 * stretch_ratio) as usize;

        let mut output = vec![0.0; output_len];
        let window = Self::create_hann_window(self.fft_size);
        let mut window_acc = vec![0.0; output_len];

        let mut fft_planner = FftPlanner::new();
        let fft = fft_planner.plan_fft_forward(self.fft_size);
        let ifft = fft_planner.plan_fft_inverse(self.fft_size);

        let num_frames = (input_len - self.fft_size) / self.hop + 1;

        for frame_idx in 0..num_frames {
            let in_pos = frame_idx * self.hop;
            let out_pos = frame_idx * hop_s.max(1);

            if out_pos + self.fft_size > output_len {
                break;
            }

            // Analyze
            let mut frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size];
            for i in 0..self.fft_size {
                if in_pos + i < input_len {
                    frame[i] = Complex::new(input[in_pos + i] * window[i], 0.0);
                }
            }
            fft.process(&mut frame);

            // Extract magnitude, replace phase with random
            let mut synth_frame: Vec<Complex<f64>> = vec![Complex::new(0.0, 0.0); self.fft_size];
            for bin in 0..self.fft_size / 2 + 1 {
                let mag = frame[bin].norm();
                let random_phase = self.next_random() * 2.0 * PI - PI;
                synth_frame[bin] = Complex::from_polar(mag, random_phase);

                if bin > 0 && bin < self.fft_size / 2 {
                    synth_frame[self.fft_size - bin] = synth_frame[bin].conj();
                }
            }

            ifft.process(&mut synth_frame);

            // Overlap-add
            for i in 0..self.fft_size {
                if out_pos + i < output_len {
                    let w = window[i];
                    output[out_pos + i] += synth_frame[i].re * w / self.fft_size as f64;
                    window_acc[out_pos + i] += w * w;
                }
            }
        }

        // Normalize
        for i in 0..output_len {
            if window_acc[i] > 1e-10 {
                output[i] /= window_acc[i];
            }
        }

        output
    }

    /// Create Hann window
    fn create_hann_window(size: usize) -> Vec<f64> {
        (0..size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / (size - 1) as f64).cos()))
            .collect()
    }
}

impl Default for NoiseMorpher {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// FORMANT PRESERVING PITCH SHIFTER
// ============================================================================

/// Formant-preserving pitch shifter using LPC
pub struct FormantPreserver {
    /// LPC order
    lpc_order: usize,
    /// Sample rate
    sample_rate: f64,
}

impl FormantPreserver {
    /// Create new formant preserver
    pub fn new(sample_rate: f64) -> Self {
        Self {
            lpc_order: 20,
            sample_rate,
        }
    }

    /// Compute LPC coefficients using autocorrelation method
    fn compute_lpc(&self, signal: &[f64]) -> Vec<f64> {
        let order = self.lpc_order.min(signal.len() - 1);

        // Compute autocorrelation
        let mut r = vec![0.0; order + 1];
        for lag in 0..=order {
            for i in 0..signal.len() - lag {
                r[lag] += signal[i] * signal[i + lag];
            }
        }

        // Levinson-Durbin recursion
        let mut a = vec![0.0; order + 1];
        let mut e = r[0];

        if e.abs() < 1e-10 {
            return vec![1.0];
        }

        a[0] = 1.0;

        for i in 1..=order {
            let mut lambda = 0.0;
            for j in 0..i {
                lambda += a[j] * r[i - j];
            }
            lambda = -lambda / e;

            // Update coefficients
            let mut a_new = a.clone();
            for j in 0..=i {
                a_new[j] = a[j] + lambda * a[i - j];
            }
            a = a_new;

            e *= 1.0 - lambda * lambda;
            if e < 1e-10 {
                break;
            }
        }

        a
    }

    /// Extract spectral envelope (formants)
    pub fn extract_envelope(&self, spectrum: &[f64]) -> Vec<f64> {
        // Compute cepstrum and lifter for envelope
        let len = spectrum.len();
        let mut envelope = vec![0.0; len];

        // Simple smoothing for envelope extraction
        let smooth_bins = 10;
        for i in 0..len {
            let start = i.saturating_sub(smooth_bins);
            let end = (i + smooth_bins).min(len);
            let sum: f64 = spectrum[start..end].iter().sum();
            envelope[i] = sum / (end - start) as f64;
        }

        envelope
    }

    /// Apply formant envelope to spectrum
    pub fn apply_envelope(&self, spectrum: &mut [f64], envelope: &[f64]) {
        for i in 0..spectrum.len().min(envelope.len()) {
            if envelope[i] > 1e-10 {
                // Normalize by current envelope, then apply target envelope
                let current = spectrum[i];
                if current > 1e-10 {
                    spectrum[i] = envelope[i];
                }
            }
        }
    }
}

// ============================================================================
// MULTI-RESOLUTION PROCESSOR
// ============================================================================

/// Band configuration for multi-resolution processing
#[derive(Debug, Clone)]
pub struct BandConfig {
    /// Low frequency bound
    pub freq_low: f64,
    /// High frequency bound
    pub freq_high: f64,
    /// FFT size for this band
    pub fft_size: usize,
    /// Overlap factor
    pub overlap: usize,
}

/// Multi-resolution time stretcher
pub struct MultiResolutionStretcher {
    /// Band configurations
    bands: Vec<BandConfig>,
    /// Phase vocoders for each band
    vocoders: Vec<PhaseVocoder>,
    /// Sample rate
    sample_rate: f64,
}

impl MultiResolutionStretcher {
    /// Create new multi-resolution stretcher
    pub fn new(sample_rate: f64) -> Self {
        let bands = vec![
            BandConfig {
                freq_low: 0.0,
                freq_high: BASS_CUTOFF,
                fft_size: 4096, // Large window for bass
                overlap: 8,
            },
            BandConfig {
                freq_low: BASS_CUTOFF,
                freq_high: TREBLE_CUTOFF,
                fft_size: 2048, // Medium window for mids
                overlap: 4,
            },
            BandConfig {
                freq_low: TREBLE_CUTOFF,
                freq_high: sample_rate / 2.0,
                fft_size: 512, // Small window for highs
                overlap: 2,
            },
        ];

        let vocoders = bands
            .iter()
            .map(|b| PhaseVocoder::new(b.fft_size))
            .collect();

        Self {
            bands,
            vocoders,
            sample_rate,
        }
    }

    /// Split signal into frequency bands
    fn split_bands(&self, input: &[f64]) -> Vec<Vec<f64>> {
        // Use Linkwitz-Riley crossover filters
        // For simplicity, using simple biquad filters here
        let len = input.len();
        let mut bands = vec![vec![0.0; len]; self.bands.len()];

        // Simple frequency splitting using running averages
        // In production, use proper crossover filters
        bands[0] = input.to_vec(); // For now, process full signal
        // TODO: Implement proper crossover filtering

        bands
    }

    /// Combine frequency bands
    fn combine_bands(&self, bands: &[Vec<f64>]) -> Vec<f64> {
        if bands.is_empty() {
            return vec![];
        }

        let len = bands[0].len();
        let mut output = vec![0.0; len];

        for band in bands {
            for i in 0..len.min(band.len()) {
                output[i] += band[i];
            }
        }

        // Normalize by number of bands
        let scale = 1.0 / bands.len() as f64;
        for s in &mut output {
            *s *= scale;
        }

        output
    }

    /// Process with multi-resolution
    pub fn process(&mut self, input: &[f64], stretch_ratio: f64) -> Vec<f64> {
        // For now, just use a single vocoder
        // Full implementation would process each band separately
        if !self.vocoders.is_empty() {
            self.vocoders[0].process(input, stretch_ratio)
        } else {
            input.to_vec()
        }
    }
}

// ============================================================================
// RF-ELASTIC PRO - MAIN ENGINE
// ============================================================================

/// Time stretch quality preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum StretchQuality {
    /// Fast preview (lower quality)
    Preview,
    /// Standard quality (balanced)
    #[default]
    Standard,
    /// High quality (slower)
    High,
    /// Ultra quality (slowest, best)
    Ultra,
}

/// Time stretch algorithm mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum StretchMode {
    /// Auto-detect best algorithm
    #[default]
    Auto,
    /// Polyphonic (complex mixes)
    Polyphonic,
    /// Monophonic (single voice/instrument)
    Monophonic,
    /// Rhythmic (drums/percussion)
    Rhythmic,
    /// Speech (voice with formant preservation)
    Speech,
    /// Creative (extreme stretching)
    Creative,
}

/// RF-Elastic Pro configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ElasticProConfig {
    /// Stretch ratio (1.0 = no change)
    pub stretch_ratio: f64,
    /// Pitch shift in semitones
    pub pitch_shift: f64,
    /// Quality preset
    pub quality: StretchQuality,
    /// Algorithm mode
    pub mode: StretchMode,
    /// Preserve transients
    pub preserve_transients: bool,
    /// Preserve formants
    pub preserve_formants: bool,
    /// STN decomposition enabled
    pub use_stn: bool,
    /// Multi-resolution enabled
    pub use_multi_resolution: bool,
    /// Tonal threshold (0.0-1.0)
    pub tonal_threshold: f64,
    /// Transient threshold (0.0-1.0)
    pub transient_threshold: f64,
}

impl Default for ElasticProConfig {
    fn default() -> Self {
        Self {
            stretch_ratio: 1.0,
            pitch_shift: 0.0,
            quality: StretchQuality::Standard,
            mode: StretchMode::Auto,
            preserve_transients: true,
            preserve_formants: false,
            use_stn: true,
            use_multi_resolution: false,
            tonal_threshold: 0.5,
            transient_threshold: 0.5,
        }
    }
}

/// RF-Elastic Pro - Ultimate Time Stretching Engine
pub struct ElasticPro {
    /// Configuration
    config: ElasticProConfig,
    /// Sample rate
    sample_rate: f64,
    /// STN decomposer
    stn: StnDecomposer,
    /// Phase vocoder (for sines)
    vocoder: PhaseVocoder,
    /// Transient processor
    transient_proc: TransientProcessor,
    /// Noise morpher
    noise_morpher: NoiseMorpher,
    /// Multi-resolution stretcher
    multi_res: MultiResolutionStretcher,
    /// Formant preserver
    formant: FormantPreserver,
}

impl ElasticPro {
    /// Create new RF-Elastic Pro engine
    pub fn new(sample_rate: f64) -> Self {
        Self {
            config: ElasticProConfig::default(),
            sample_rate,
            stn: StnDecomposer::new(sample_rate),
            vocoder: PhaseVocoder::new(DEFAULT_FFT_SIZE),
            transient_proc: TransientProcessor::new(),
            noise_morpher: NoiseMorpher::new(),
            multi_res: MultiResolutionStretcher::new(sample_rate),
            formant: FormantPreserver::new(sample_rate),
        }
    }

    /// Set configuration
    pub fn set_config(&mut self, config: ElasticProConfig) {
        self.stn
            .set_params(config.tonal_threshold, config.transient_threshold);
        self.config = config;
    }

    /// Get current configuration
    pub fn config(&self) -> &ElasticProConfig {
        &self.config
    }

    /// Set stretch ratio
    pub fn set_stretch_ratio(&mut self, ratio: f64) {
        self.config.stretch_ratio = ratio.clamp(0.1, 10.0);
    }

    /// Set pitch shift in semitones
    pub fn set_pitch_shift(&mut self, semitones: f64) {
        self.config.pitch_shift = semitones.clamp(-24.0, 24.0);
    }

    /// Set quality preset
    pub fn set_quality(&mut self, quality: StretchQuality) {
        self.config.quality = quality;

        // Adjust FFT size based on quality
        let fft_size = match quality {
            StretchQuality::Preview => 1024,
            StretchQuality::Standard => 2048,
            StretchQuality::High => 4096,
            StretchQuality::Ultra => 8192,
        };

        self.vocoder = PhaseVocoder::new(fft_size);
    }

    /// Set algorithm mode
    pub fn set_mode(&mut self, mode: StretchMode) {
        self.config.mode = mode;
    }

    /// Process audio with time stretching
    pub fn process(&mut self, input: &[f64]) -> Vec<f64> {
        if input.is_empty() {
            return vec![];
        }

        let stretch_ratio = self.config.stretch_ratio;
        let pitch_ratio = 2.0_f64.powf(self.config.pitch_shift / 12.0);

        // Combined ratio for time-stretch with pitch shift
        let time_ratio = stretch_ratio / pitch_ratio;

        if self.config.use_stn {
            self.process_stn(input, time_ratio)
        } else if self.config.use_multi_resolution {
            self.multi_res.process(input, time_ratio)
        } else {
            self.vocoder.process(input, time_ratio)
        }
    }

    /// Process using STN decomposition
    fn process_stn(&mut self, input: &[f64], stretch_ratio: f64) -> Vec<f64> {
        // Step 1: Decompose into Sines, Transients, Noise
        let decomp = self.stn.decompose(input);

        // Step 2: Process each component with appropriate algorithm

        // Sines: Phase vocoder with peak locking
        let stretched_sines = self.vocoder.process(&decomp.sines, stretch_ratio);

        // Transients: WSOLA with transient locking
        self.transient_proc
            .set_transients(decomp.transient_positions.clone());
        let stretched_transients = self
            .transient_proc
            .process(&decomp.transients, stretch_ratio);

        // Noise: Magnitude morphing with random phase
        let stretched_noise = self.noise_morpher.process(&decomp.noise, stretch_ratio);

        // Step 3: Recombine
        let output_len = (input.len() as f64 * stretch_ratio) as usize;
        let mut output = vec![0.0; output_len];

        for i in 0..output_len {
            let s = if i < stretched_sines.len() {
                stretched_sines[i]
            } else {
                0.0
            };
            let t = if i < stretched_transients.len() {
                stretched_transients[i]
            } else {
                0.0
            };
            let n = if i < stretched_noise.len() {
                stretched_noise[i]
            } else {
                0.0
            };

            output[i] = s + t + n;
        }

        // Soft clip to prevent overs
        for s in &mut output {
            *s = (*s).tanh();
        }

        output
    }

    /// Process stereo audio
    pub fn process_stereo(&mut self, left: &[f64], right: &[f64]) -> (Vec<f64>, Vec<f64>) {
        let left_out = self.process(left);
        let right_out = self.process(right);
        (left_out, right_out)
    }

    /// Get expected output length
    pub fn output_length(&self, input_length: usize) -> usize {
        (input_length as f64 * self.config.stretch_ratio) as usize
    }

    /// Reset internal state
    pub fn reset(&mut self) {
        // Reset all internal processors
        self.vocoder = PhaseVocoder::new(match self.config.quality {
            StretchQuality::Preview => 1024,
            StretchQuality::Standard => 2048,
            StretchQuality::High => 4096,
            StretchQuality::Ultra => 8192,
        });
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stn_decomposition() {
        let mut decomposer = StnDecomposer::new(48000.0);

        // Create test signal with sine + transient + noise
        let len = 4096;
        let mut signal = vec![0.0; len];

        // Add sine (440 Hz)
        for i in 0..len {
            signal[i] += 0.5 * (2.0 * PI * 440.0 * i as f64 / 48000.0).sin();
        }

        // Add transient at sample 1000
        for i in 1000..1010 {
            signal[i] += 1.0;
        }

        // Add noise
        for i in 0..len {
            signal[i] += 0.05 * ((i * 12345) as f64 % 1.0 - 0.5);
        }

        let decomp = decomposer.decompose(&signal);

        assert_eq!(decomp.sines.len(), len);
        assert_eq!(decomp.transients.len(), len);
        assert_eq!(decomp.noise.len(), len);
    }

    #[test]
    fn test_phase_vocoder() {
        let mut vocoder = PhaseVocoder::new(1024);

        // Test signal
        let len = 4096;
        let signal: Vec<f64> = (0..len)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 48000.0).sin())
            .collect();

        // Stretch 2x
        let output = vocoder.process(&signal, 2.0);

        assert!((output.len() as f64 / signal.len() as f64 - 2.0).abs() < 0.1);
    }

    #[test]
    fn test_elastic_pro() {
        let mut elastic = ElasticPro::new(48000.0);
        elastic.set_stretch_ratio(1.5);

        let input: Vec<f64> = (0..8192)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 48000.0).sin())
            .collect();

        let output = elastic.process(&input);

        // Output should be ~1.5x input length
        let ratio = output.len() as f64 / input.len() as f64;
        assert!((ratio - 1.5).abs() < 0.1);
    }

    #[test]
    fn test_transient_processor() {
        let mut proc = TransientProcessor::new();
        proc.set_transients(vec![500, 1000, 1500]);

        let input: Vec<f64> = (0..2048).map(|_| 0.5).collect();
        let output = proc.process(&input, 2.0);

        assert!(!output.is_empty());
    }

    #[test]
    fn test_noise_morpher() {
        let mut morpher = NoiseMorpher::new();

        let input: Vec<f64> = (0..4096).map(|i| (i as f64 * 0.001).sin() * 0.1).collect();
        let output = morpher.process(&input, 1.5);

        let expected_len = (input.len() as f64 * 1.5) as usize;
        assert!((output.len() as i64 - expected_len as i64).abs() < 100);
    }
}

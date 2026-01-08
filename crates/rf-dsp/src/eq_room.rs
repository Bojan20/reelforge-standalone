//! Room Correction EQ - Automatic Room Acoustics Correction
//!
//! Professional room correction system:
//! - Measurement microphone input
//! - Room mode detection
//! - Target curve matching (Harman, flat, custom)
//! - Psychoacoustic curve optimization
//! - Phase correction
//! - Excess group delay compensation

use std::f64::consts::PI;
use std::sync::Arc;

use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;

use crate::biquad::{BiquadCoeffs, BiquadTDF2};
use crate::{MonoProcessor, Processor, StereoProcessor};
use rf_core::Sample;

// ============================================================================
// CONSTANTS
// ============================================================================

/// FFT size for room measurement
const ROOM_FFT_SIZE: usize = 32768;

/// Smoothing octave fraction for room curves
const SMOOTHING_OCTAVE: f64 = 1.0 / 3.0; // 1/3 octave smoothing

/// Maximum correction filters
const MAX_CORRECTION_BANDS: usize = 64;

// ============================================================================
// TARGET CURVES
// ============================================================================

/// Standard target curves for room correction
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum TargetCurve {
    /// Flat response
    #[default]
    Flat,
    /// Harman target curve (bass boost, slight HF rolloff)
    Harman,
    /// B&K house curve
    BAndK,
    /// BBC reference curve
    BBC,
    /// X-curve (cinema)
    XCurve,
    /// Custom (user-defined)
    Custom,
}

impl TargetCurve {
    /// Get dB offset at frequency
    pub fn offset_at(&self, freq: f64) -> f64 {
        match self {
            TargetCurve::Flat => 0.0,
            TargetCurve::Harman => {
                // Harman target: bass boost, slight HF rolloff
                if freq < 20.0 {
                    0.0
                } else if freq < 150.0 {
                    // Bass boost region
                    let t = ((freq / 20.0).log2() / (150.0_f64 / 20.0).log2()).clamp(0.0, 1.0);
                    6.0 * (1.0 - t)
                } else if freq < 1000.0 {
                    0.0
                } else if freq > 10000.0 {
                    // HF rolloff
                    let t = ((freq / 10000.0).log2() / 2.0).clamp(0.0, 1.0);
                    -3.0 * t
                } else {
                    0.0
                }
            }
            TargetCurve::BAndK => {
                // B&K house curve: gentle bass boost, HF rolloff
                if freq < 80.0 {
                    let t = (freq / 80.0).log2().abs() / 2.0;
                    4.0 * t.min(1.0)
                } else if freq > 2000.0 {
                    let t = (freq / 2000.0).log2() / 3.5;
                    -t.min(1.0) * 6.0
                } else {
                    0.0
                }
            }
            TargetCurve::BBC => {
                // BBC: very gentle bass, HF rolloff
                if freq > 4000.0 {
                    let t = (freq / 4000.0).log2() / 2.5;
                    -t.min(1.0) * 4.0
                } else {
                    0.0
                }
            }
            TargetCurve::XCurve => {
                // X-Curve: cinema standard
                if freq < 63.0 {
                    let t = (freq / 63.0).log2().abs();
                    -3.0 * t.min(1.0)
                } else if freq > 2000.0 {
                    let t = (freq / 2000.0).log2();
                    -3.0 * t.min(1.0)
                } else {
                    0.0
                }
            }
            TargetCurve::Custom => 0.0,
        }
    }

    /// Generate full target curve
    pub fn generate(&self, num_points: usize, min_freq: f64, max_freq: f64) -> Vec<f64> {
        (0..num_points)
            .map(|i| {
                let t = i as f64 / (num_points - 1) as f64;
                let freq = min_freq * (max_freq / min_freq).powf(t);
                self.offset_at(freq)
            })
            .collect()
    }
}

// ============================================================================
// ROOM MEASUREMENT
// ============================================================================

/// Room measurement system
pub struct RoomMeasurement {
    /// FFT planner
    fft: Arc<dyn RealToComplex<f64>>,
    /// Input buffer
    input_buffer: Vec<f64>,
    /// Spectrum output
    spectrum: Vec<Complex<f64>>,
    /// Averaged magnitude response
    magnitude: Vec<f64>,
    /// Phase response
    phase: Vec<f64>,
    /// Group delay
    group_delay: Vec<f64>,
    /// Number of averages
    num_averages: usize,
    /// Current buffer position
    buffer_pos: usize,
    /// Sample rate
    sample_rate: f64,

    /// Detected room modes
    pub room_modes: Vec<RoomMode>,
}

/// Detected room mode
#[derive(Debug, Clone)]
pub struct RoomMode {
    /// Frequency (Hz)
    pub frequency: f64,
    /// Q factor (narrower = more problematic)
    pub q: f64,
    /// Magnitude (dB above average)
    pub magnitude_db: f64,
    /// Type of mode
    pub mode_type: RoomModeType,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum RoomModeType {
    /// Axial mode (1D standing wave)
    Axial,
    /// Tangential mode (2D)
    Tangential,
    /// Oblique mode (3D)
    Oblique,
}

impl RoomMeasurement {
    pub fn new(sample_rate: f64) -> Self {
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(ROOM_FFT_SIZE);

        Self {
            fft,
            input_buffer: vec![0.0; ROOM_FFT_SIZE],
            spectrum: vec![Complex::new(0.0, 0.0); ROOM_FFT_SIZE / 2 + 1],
            magnitude: vec![0.0; ROOM_FFT_SIZE / 2 + 1],
            phase: vec![0.0; ROOM_FFT_SIZE / 2 + 1],
            group_delay: vec![0.0; ROOM_FFT_SIZE / 2 + 1],
            num_averages: 0,
            buffer_pos: 0,
            sample_rate,
            room_modes: Vec::new(),
        }
    }

    /// Feed measurement samples
    pub fn feed(&mut self, samples: &[f64]) {
        for &sample in samples {
            self.input_buffer[self.buffer_pos] = sample;
            self.buffer_pos += 1;

            if self.buffer_pos >= ROOM_FFT_SIZE {
                self.process_block();
                self.buffer_pos = 0;
            }
        }
    }

    fn process_block(&mut self) {
        // Apply window
        let mut windowed = self.input_buffer.clone();
        for (i, s) in windowed.iter_mut().enumerate() {
            let t = i as f64 / (ROOM_FFT_SIZE - 1) as f64;
            let window = 0.5 - 0.5 * (2.0 * PI * t).cos(); // Hann
            *s *= window;
        }

        // FFT
        self.fft.process(&mut windowed, &mut self.spectrum).unwrap();

        // Accumulate magnitude
        for (i, c) in self.spectrum.iter().enumerate() {
            let mag = (c.re * c.re + c.im * c.im).sqrt();
            if self.num_averages == 0 {
                self.magnitude[i] = mag;
            } else {
                // Running average
                let alpha = 1.0 / (self.num_averages + 1) as f64;
                self.magnitude[i] = self.magnitude[i] * (1.0 - alpha) + mag * alpha;
            }

            // Store phase
            self.phase[i] = c.im.atan2(c.re);
        }

        // Calculate group delay
        self.calculate_group_delay();

        self.num_averages += 1;
    }

    fn calculate_group_delay(&mut self) {
        // Group delay = -d(phase)/d(omega)
        let freq_resolution = self.sample_rate / ROOM_FFT_SIZE as f64;

        for i in 1..self.phase.len() - 1 {
            let phase_diff = self.phase[i + 1] - self.phase[i - 1];

            // Unwrap phase
            let mut unwrapped = phase_diff;
            while unwrapped > PI {
                unwrapped -= 2.0 * PI;
            }
            while unwrapped < -PI {
                unwrapped += 2.0 * PI;
            }

            // Group delay in samples
            self.group_delay[i] = -unwrapped / (2.0 * 2.0 * PI * freq_resolution);
        }
    }

    /// Detect room modes from measurement
    pub fn detect_modes(&mut self) {
        self.room_modes.clear();

        if self.num_averages < 1 {
            return;
        }

        // Convert to dB
        let db: Vec<f64> = self
            .magnitude
            .iter()
            .map(|&m| 20.0 * m.max(1e-10).log10())
            .collect();

        // Calculate smoothed average
        let smoothed = self.smooth_1_3_octave(&db);

        // Find peaks above average
        for i in 2..db.len() - 2 {
            let freq = i as f64 * self.sample_rate / ROOM_FFT_SIZE as f64;

            // Skip below 20Hz and above 500Hz (typical modal range)
            if freq < 20.0 || freq > 500.0 {
                continue;
            }

            // Check if local maximum
            if db[i] > db[i - 1] && db[i] > db[i + 1] && db[i] > db[i - 2] && db[i] > db[i + 2] {
                let excess = db[i] - smoothed[i];

                // Significant peak (> 3dB above smoothed)
                if excess > 3.0 {
                    // Estimate Q from peak width
                    let q = self.estimate_q(&db, i, freq);

                    // Classify mode type based on frequency
                    let mode_type = if freq < 80.0 {
                        RoomModeType::Axial
                    } else if freq < 200.0 {
                        RoomModeType::Tangential
                    } else {
                        RoomModeType::Oblique
                    };

                    self.room_modes.push(RoomMode {
                        frequency: freq,
                        q,
                        magnitude_db: excess,
                        mode_type,
                    });
                }
            }
        }

        // Sort by magnitude (most problematic first)
        self.room_modes
            .sort_by(|a, b| b.magnitude_db.partial_cmp(&a.magnitude_db).unwrap());
    }

    fn smooth_1_3_octave(&self, db: &[f64]) -> Vec<f64> {
        let mut smoothed = vec![0.0; db.len()];

        for i in 0..db.len() {
            let freq = i as f64 * self.sample_rate / ROOM_FFT_SIZE as f64;
            if freq < 1.0 {
                smoothed[i] = db[i];
                continue;
            }

            // 1/3 octave smoothing window
            let low_freq = freq / 2.0_f64.powf(SMOOTHING_OCTAVE / 2.0);
            let high_freq = freq * 2.0_f64.powf(SMOOTHING_OCTAVE / 2.0);

            let low_bin = (low_freq * ROOM_FFT_SIZE as f64 / self.sample_rate) as usize;
            let high_bin = (high_freq * ROOM_FFT_SIZE as f64 / self.sample_rate) as usize;

            let low_bin = low_bin.max(0).min(db.len() - 1);
            let high_bin = high_bin.max(0).min(db.len() - 1);

            if high_bin > low_bin {
                let sum: f64 = db[low_bin..=high_bin].iter().sum();
                smoothed[i] = sum / (high_bin - low_bin + 1) as f64;
            } else {
                smoothed[i] = db[i];
            }
        }

        smoothed
    }

    fn estimate_q(&self, db: &[f64], peak_bin: usize, peak_freq: f64) -> f64 {
        let peak_db = db[peak_bin];
        let target_db = peak_db - 3.0; // -3dB points

        // Find -3dB points
        let mut low_bin = peak_bin;
        let mut high_bin = peak_bin;

        while low_bin > 0 && db[low_bin] > target_db {
            low_bin -= 1;
        }
        while high_bin < db.len() - 1 && db[high_bin] > target_db {
            high_bin += 1;
        }

        let low_freq = low_bin as f64 * self.sample_rate / ROOM_FFT_SIZE as f64;
        let high_freq = high_bin as f64 * self.sample_rate / ROOM_FFT_SIZE as f64;

        let bandwidth = high_freq - low_freq;
        if bandwidth > 0.0 {
            peak_freq / bandwidth
        } else {
            10.0 // Default high Q
        }
    }

    /// Get frequency response in dB
    pub fn get_response_db(&self) -> Vec<f64> {
        self.magnitude
            .iter()
            .map(|&m| 20.0 * m.max(1e-10).log10())
            .collect()
    }

    /// Get frequency bins
    pub fn get_frequencies(&self) -> Vec<f64> {
        (0..self.magnitude.len())
            .map(|i| i as f64 * self.sample_rate / ROOM_FFT_SIZE as f64)
            .collect()
    }

    /// Reset measurement
    pub fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.magnitude.fill(0.0);
        self.phase.fill(0.0);
        self.group_delay.fill(0.0);
        self.num_averages = 0;
        self.buffer_pos = 0;
        self.room_modes.clear();
    }
}

// ============================================================================
// ROOM CORRECTION EQ
// ============================================================================

/// Room correction filter band
#[derive(Debug, Clone)]
struct CorrectionBand {
    freq: f64,
    gain_db: f64,
    q: f64,
    enabled: bool,
    filter_l: BiquadTDF2,
    filter_r: BiquadTDF2,
}

impl CorrectionBand {
    fn new(freq: f64, gain_db: f64, q: f64, sample_rate: f64) -> Self {
        let mut band = Self {
            freq,
            gain_db,
            q,
            enabled: true,
            filter_l: BiquadTDF2::new(sample_rate),
            filter_r: BiquadTDF2::new(sample_rate),
        };
        band.update(sample_rate);
        band
    }

    fn update(&mut self, sample_rate: f64) {
        let coeffs = BiquadCoeffs::peaking(self.freq, self.q, self.gain_db, sample_rate);
        self.filter_l.set_coeffs(coeffs);
        self.filter_r.set_coeffs(coeffs);
    }

    fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        if !self.enabled {
            return (left, right);
        }
        (
            self.filter_l.process_sample(left),
            self.filter_r.process_sample(right),
        )
    }

    fn reset(&mut self) {
        self.filter_l.reset();
        self.filter_r.reset();
    }
}

/// Full room correction EQ
pub struct RoomCorrectionEq {
    /// Measurement system
    pub measurement: RoomMeasurement,
    /// Target curve
    pub target: TargetCurve,
    /// Custom target curve (if target == Custom)
    pub custom_target: Vec<f64>,
    /// Maximum correction amount (dB)
    pub max_correction: f64,
    /// Only correct cuts (don't boost)
    pub cut_only: bool,
    /// Correction bands
    bands: Vec<CorrectionBand>,
    /// Sample rate
    sample_rate: f64,
    /// Correction enabled
    pub enabled: bool,
}

impl RoomCorrectionEq {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            measurement: RoomMeasurement::new(sample_rate),
            target: TargetCurve::Harman,
            custom_target: Vec::new(),
            max_correction: 12.0,
            cut_only: true, // Safer default
            bands: Vec::with_capacity(MAX_CORRECTION_BANDS),
            sample_rate,
            enabled: false,
        }
    }

    /// Generate correction filters from measurement
    pub fn generate_correction(&mut self) {
        self.bands.clear();

        // Get measured response
        let measured = self.measurement.get_response_db();
        let freqs = self.measurement.get_frequencies();

        if measured.is_empty() || freqs.is_empty() {
            return;
        }

        // Calculate average level
        let avg_level: f64 = measured
            .iter()
            .skip(1) // Skip DC
            .take(measured.len() / 2) // Only up to Nyquist/2
            .sum::<f64>()
            / (measured.len() / 2) as f64;

        // Generate target
        let target: Vec<f64> = freqs
            .iter()
            .map(|&f| self.target.offset_at(f) + avg_level)
            .collect();

        // First, add correction for detected room modes
        for mode in &self.measurement.room_modes {
            let correction = (-mode.magnitude_db).clamp(-self.max_correction, 0.0);

            if correction.abs() > 0.5 {
                self.bands.push(CorrectionBand::new(
                    mode.frequency,
                    correction,
                    mode.q,
                    self.sample_rate,
                ));
            }
        }

        // Then, add broadband correction at key frequencies
        let correction_freqs = [
            31.5, 63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0,
        ];

        for &freq in &correction_freqs {
            // Skip if we already have a mode correction nearby
            let has_nearby = self.bands.iter().any(|b| (b.freq / freq - 1.0).abs() < 0.3);

            if has_nearby {
                continue;
            }

            // Find closest bin
            let bin = (freq * ROOM_FFT_SIZE as f64 / self.sample_rate) as usize;
            if bin >= measured.len() {
                continue;
            }

            // Calculate needed correction
            let mut correction = target[bin] - measured[bin];

            // Limit correction
            if self.cut_only && correction > 0.0 {
                correction = 0.0;
            }
            correction = correction.clamp(-self.max_correction, self.max_correction);

            if correction.abs() > 0.5 {
                // Use moderate Q for broadband corrections
                let q = 1.0;
                self.bands
                    .push(CorrectionBand::new(freq, correction, q, self.sample_rate));
            }
        }

        self.enabled = true;
    }

    /// Clear all corrections
    pub fn clear_correction(&mut self) {
        self.bands.clear();
        self.enabled = false;
    }

    /// Get correction curve for visualization
    pub fn get_correction_curve(&self, num_points: usize) -> Vec<f64> {
        (0..num_points)
            .map(|i| {
                let t = i as f64 / (num_points - 1) as f64;
                let freq = 20.0 * (1000.0_f64).powf(t);

                // Sum contribution from all bands
                let mut total_db = 0.0;
                for band in &self.bands {
                    if !band.enabled {
                        continue;
                    }

                    // Approximate band contribution (simplified)
                    let ratio = freq / band.freq;
                    let q_factor = band.q;

                    // Peaking filter magnitude approximation
                    let denom = (1.0 - ratio * ratio).powi(2) + (ratio / q_factor).powi(2);
                    let magnitude = (band.gain_db / 20.0).exp() / denom.sqrt();
                    total_db += 20.0 * magnitude.log10();
                }

                total_db
            })
            .collect()
    }

    /// Number of correction bands
    pub fn num_bands(&self) -> usize {
        self.bands.len()
    }
}

impl Processor for RoomCorrectionEq {
    fn reset(&mut self) {
        for band in &mut self.bands {
            band.reset();
        }
    }

    fn latency(&self) -> usize {
        0
    }
}

impl StereoProcessor for RoomCorrectionEq {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if !self.enabled {
            return (left, right);
        }

        let (mut l, mut r) = (left, right);

        for band in &mut self.bands {
            (l, r) = band.process(l, r);
        }

        (l, r)
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_target_curves() {
        let harman = TargetCurve::Harman;

        // Bass boost at 50Hz
        let bass = harman.offset_at(50.0);
        assert!(bass > 0.0);

        // Flat at 1kHz
        let mid = harman.offset_at(1000.0);
        assert!(mid.abs() < 0.1);

        // HF rolloff at 15kHz
        let high = harman.offset_at(15000.0);
        assert!(high < 0.0);
    }

    #[test]
    fn test_room_measurement() {
        let mut meas = RoomMeasurement::new(48000.0);

        // Feed some test signal
        let test_signal: Vec<f64> = (0..ROOM_FFT_SIZE)
            .map(|i| (2.0 * PI * 100.0 * i as f64 / 48000.0).sin())
            .collect();

        meas.feed(&test_signal);

        let response = meas.get_response_db();
        assert!(!response.is_empty());
    }

    #[test]
    fn test_room_correction() {
        let mut eq = RoomCorrectionEq::new(48000.0);
        eq.target = TargetCurve::Flat;

        let (l, r) = eq.process_sample(1.0, 1.0);
        // No correction yet, should pass through
        assert_eq!(l, 1.0);
        assert_eq!(r, 1.0);
    }
}

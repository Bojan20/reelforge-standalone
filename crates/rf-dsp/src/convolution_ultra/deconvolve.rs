//! IR Deconvolution
//!
//! UNIQUE: Extract impulse responses from sweep recordings.
//!
//! Supported sweep types:
//! - Linear sweep (constant frequency rate)
//! - Logarithmic sweep (constant octave rate, most common)
//! - Exponential sine sweep (ESS)
//! - MLS (Maximum Length Sequence)

use rf_core::Sample;
use rustfft::{FftPlanner, num_complex::Complex64};
use std::f64::consts::PI;

use super::ImpulseResponse;

/// Sweep type for IR measurement
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SweepType {
    /// Linear frequency sweep (chirp)
    Linear,
    /// Logarithmic sweep (constant octave rate)
    Logarithmic,
    /// Exponential sine sweep (ESS) - best for room acoustics
    ExponentialSine,
}

/// Sweep configuration
#[derive(Debug, Clone)]
pub struct SweepConfig {
    /// Sweep type
    pub sweep_type: SweepType,
    /// Start frequency (Hz)
    pub start_freq: f64,
    /// End frequency (Hz)
    pub end_freq: f64,
    /// Duration (seconds)
    pub duration: f64,
    /// Sample rate
    pub sample_rate: f64,
    /// Fade in/out time (seconds)
    pub fade_time: f64,
}

impl Default for SweepConfig {
    fn default() -> Self {
        Self {
            sweep_type: SweepType::ExponentialSine,
            start_freq: 20.0,
            end_freq: 20000.0,
            duration: 10.0,
            sample_rate: 48000.0,
            fade_time: 0.1,
        }
    }
}

impl SweepConfig {
    /// Standard room measurement sweep
    pub fn room_measurement() -> Self {
        Self {
            sweep_type: SweepType::ExponentialSine,
            start_freq: 20.0,
            end_freq: 20000.0,
            duration: 10.0,
            sample_rate: 48000.0,
            fade_time: 0.1,
        }
    }

    /// Quick sweep for testing
    pub fn quick() -> Self {
        Self {
            sweep_type: SweepType::Logarithmic,
            start_freq: 100.0,
            end_freq: 10000.0,
            duration: 3.0,
            sample_rate: 48000.0,
            fade_time: 0.05,
        }
    }
}

/// IR Deconvolver
pub struct IrDeconvolver {
    /// Configuration
    config: SweepConfig,
    /// Reference sweep signal
    reference_sweep: Vec<Sample>,
    /// Inverse filter in frequency domain
    inverse_filter: Vec<Complex64>,
    /// FFT size
    fft_size: usize,
    /// FFT planner
    fft_forward: std::sync::Arc<dyn rustfft::Fft<f64>>,
    fft_inverse: std::sync::Arc<dyn rustfft::Fft<f64>>,
}

impl IrDeconvolver {
    /// Create deconvolver with given configuration
    pub fn new(config: SweepConfig) -> Self {
        let num_samples = (config.duration * config.sample_rate) as usize;
        let fft_size = (num_samples * 2).next_power_of_two();

        let mut planner = FftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Generate reference sweep
        let reference_sweep = Self::generate_sweep(&config);

        // Compute inverse filter
        let inverse_filter = Self::compute_inverse_filter(
            &reference_sweep,
            fft_size,
            &fft_forward,
        );

        Self {
            config,
            reference_sweep,
            inverse_filter,
            fft_size,
            fft_forward,
            fft_inverse,
        }
    }

    /// Generate sweep signal
    pub fn generate_sweep(config: &SweepConfig) -> Vec<Sample> {
        let num_samples = (config.duration * config.sample_rate) as usize;
        let mut sweep = vec![0.0; num_samples];

        match config.sweep_type {
            SweepType::Linear => {
                Self::generate_linear_sweep(&mut sweep, config);
            }
            SweepType::Logarithmic => {
                Self::generate_log_sweep(&mut sweep, config);
            }
            SweepType::ExponentialSine => {
                Self::generate_ess(&mut sweep, config);
            }
        }

        // Apply fade in/out
        Self::apply_fades(&mut sweep, config);

        sweep
    }

    /// Generate linear frequency sweep
    fn generate_linear_sweep(sweep: &mut [Sample], config: &SweepConfig) {
        let num_samples = sweep.len();
        let f1 = config.start_freq;
        let f2 = config.end_freq;
        let duration = config.duration;

        for (i, sample) in sweep.iter_mut().enumerate() {
            let t = i as f64 / config.sample_rate;
            // Instantaneous frequency: f(t) = f1 + (f2-f1) * t/T
            // Phase: φ(t) = 2π * (f1*t + (f2-f1)*t²/(2T))
            let phase = 2.0 * PI * (f1 * t + (f2 - f1) * t * t / (2.0 * duration));
            *sample = phase.sin();
        }
    }

    /// Generate logarithmic frequency sweep
    fn generate_log_sweep(sweep: &mut [Sample], config: &SweepConfig) {
        let num_samples = sweep.len();
        let f1 = config.start_freq;
        let f2 = config.end_freq;
        let duration = config.duration;
        let k = (f2 / f1).ln();

        for (i, sample) in sweep.iter_mut().enumerate() {
            let t = i as f64 / config.sample_rate;
            // Instantaneous frequency: f(t) = f1 * e^(k*t/T)
            // Phase: φ(t) = 2π * f1 * T/k * (e^(k*t/T) - 1)
            let phase = 2.0 * PI * f1 * duration / k * ((k * t / duration).exp() - 1.0);
            *sample = phase.sin();
        }
    }

    /// Generate exponential sine sweep (ESS)
    fn generate_ess(sweep: &mut [Sample], config: &SweepConfig) {
        let num_samples = sweep.len();
        let f1 = config.start_freq;
        let f2 = config.end_freq;
        let duration = config.duration;

        // ESS formula (Farina method)
        let k = duration / (f2 / f1).ln();

        for (i, sample) in sweep.iter_mut().enumerate() {
            let t = i as f64 / config.sample_rate;
            // Phase: φ(t) = 2π * f1 * k * (e^(t/k) - 1)
            let phase = 2.0 * PI * f1 * k * ((t / k).exp() - 1.0);
            *sample = phase.sin();
        }
    }

    /// Apply fade in/out to avoid clicks
    fn apply_fades(sweep: &mut [Sample], config: &SweepConfig) {
        let fade_samples = (config.fade_time * config.sample_rate) as usize;
        let len = sweep.len();

        // Fade in (raised cosine)
        for i in 0..fade_samples.min(len) {
            let t = i as f64 / fade_samples as f64;
            let gain = 0.5 * (1.0 - (PI * t).cos());
            sweep[i] *= gain;
        }

        // Fade out
        for i in 0..fade_samples.min(len) {
            let idx = len - 1 - i;
            let t = i as f64 / fade_samples as f64;
            let gain = 0.5 * (1.0 - (PI * t).cos());
            sweep[idx] *= gain;
        }
    }

    /// Compute inverse filter for deconvolution
    fn compute_inverse_filter(
        sweep: &[Sample],
        fft_size: usize,
        fft: &std::sync::Arc<dyn rustfft::Fft<f64>>,
    ) -> Vec<Complex64> {
        // FFT of sweep
        let mut spectrum: Vec<Complex64> = sweep.iter()
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        spectrum.resize(fft_size, Complex64::new(0.0, 0.0));
        fft.process(&mut spectrum);

        // Compute inverse filter: H^(-1) = conj(H) / |H|²
        // With regularization to avoid division by zero
        const REGULARIZATION: f64 = 1e-10;

        spectrum.iter()
            .map(|&h| {
                let mag_sq = h.norm_sqr() + REGULARIZATION;
                h.conj() / mag_sq
            })
            .collect()
    }

    /// Extract IR from recorded response
    pub fn extract_ir(&self, recording: &[Sample]) -> ImpulseResponse {
        // Zero-pad recording to FFT size
        let mut rec_spectrum: Vec<Complex64> = recording.iter()
            .take(self.fft_size)
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        rec_spectrum.resize(self.fft_size, Complex64::new(0.0, 0.0));

        // FFT of recording
        self.fft_forward.process(&mut rec_spectrum);

        // Deconvolve: IR = IFFT(Recording * InverseFilter)
        let mut ir_spectrum: Vec<Complex64> = rec_spectrum.iter()
            .zip(self.inverse_filter.iter())
            .map(|(&r, &inv)| r * inv)
            .collect();

        // IFFT
        self.fft_inverse.process(&mut ir_spectrum);

        // Extract real part and scale
        let scale = 1.0 / self.fft_size as f64;
        let samples: Vec<Sample> = ir_spectrum.iter()
            .map(|c| c.re * scale)
            .collect();

        ImpulseResponse::new(samples, self.config.sample_rate, 1)
    }

    /// Extract IR with time alignment and trimming
    pub fn extract_ir_processed(&self, recording: &[Sample]) -> ImpulseResponse {
        let mut ir = self.extract_ir(recording);

        // Find peak (main impulse)
        let peak_idx = ir.samples.iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.abs().partial_cmp(&b.abs()).unwrap())
            .map(|(i, _)| i)
            .unwrap_or(0);

        // Shift to put peak at beginning
        if peak_idx > 0 && peak_idx < ir.samples.len() / 2 {
            ir.samples.rotate_left(peak_idx);
        }

        // Trim to meaningful length (-60dB)
        ir.trim(-60.0);

        // Normalize
        ir.normalize();

        ir
    }

    /// Get reference sweep signal
    pub fn reference_sweep(&self) -> &[Sample] {
        &self.reference_sweep
    }

    /// Get configuration
    pub fn config(&self) -> &SweepConfig {
        &self.config
    }
}

/// Stereo deconvolver for true stereo measurements
pub struct StereoDeconvolver {
    deconvolver: IrDeconvolver,
}

impl StereoDeconvolver {
    /// Create stereo deconvolver
    pub fn new(config: SweepConfig) -> Self {
        Self {
            deconvolver: IrDeconvolver::new(config),
        }
    }

    /// Extract stereo IR from stereo recording
    pub fn extract_stereo_ir(
        &self,
        recording_left: &[Sample],
        recording_right: &[Sample],
    ) -> ImpulseResponse {
        let ir_left = self.deconvolver.extract_ir_processed(recording_left);
        let ir_right = self.deconvolver.extract_ir_processed(recording_right);

        // Combine into stereo IR
        let max_len = ir_left.len().max(ir_right.len());
        let mut samples = Vec::with_capacity(max_len * 2);

        for i in 0..max_len {
            samples.push(ir_left.samples.get(i).copied().unwrap_or(0.0));
            samples.push(ir_right.samples.get(i).copied().unwrap_or(0.0));
        }

        ImpulseResponse::new(samples, ir_left.sample_rate, 2)
    }

    /// Get reference sweep
    pub fn reference_sweep(&self) -> &[Sample] {
        self.deconvolver.reference_sweep()
    }
}

/// MLS (Maximum Length Sequence) generator for alternative measurement
pub struct MlsGenerator {
    /// Sequence length (2^order - 1)
    length: usize,
    /// Sequence order
    order: u32,
    /// Generated sequence
    sequence: Vec<Sample>,
}

impl MlsGenerator {
    /// Create MLS generator with given order
    pub fn new(order: u32) -> Self {
        assert!(order >= 8 && order <= 24, "Order must be between 8 and 24");

        let length = (1 << order) - 1;
        let sequence = Self::generate_mls(order);

        Self {
            length,
            order,
            sequence,
        }
    }

    /// Generate MLS sequence
    fn generate_mls(order: u32) -> Vec<Sample> {
        let length = (1usize << order) - 1;
        let mut sequence = Vec::with_capacity(length);

        // LFSR taps (from standard polynomial tables)
        let taps = match order {
            8 => vec![8, 6, 5, 4],
            10 => vec![10, 7],
            12 => vec![12, 11, 10, 4],
            14 => vec![14, 13, 12, 2],
            16 => vec![16, 15, 13, 4],
            18 => vec![18, 11],
            20 => vec![20, 17],
            _ => vec![order, order - 1], // Generic fallback
        };

        let mut state = 1u32; // Initial state (non-zero)

        for _ in 0..length {
            // Output current bit
            let output = (state & 1) as i8;
            sequence.push(output as f64 * 2.0 - 1.0); // Convert to bipolar

            // Compute feedback
            let mut feedback = 0u32;
            for &tap in &taps {
                feedback ^= (state >> (tap - 1)) & 1;
            }

            // Shift register
            state = (state >> 1) | (feedback << (order - 1));
        }

        sequence
    }

    /// Get MLS sequence
    pub fn sequence(&self) -> &[Sample] {
        &self.sequence
    }

    /// Get sequence length
    pub fn length(&self) -> usize {
        self.length
    }

    /// Extract IR using MLS correlation
    pub fn extract_ir(&self, recording: &[Sample]) -> ImpulseResponse {
        // Circular cross-correlation with MLS
        let len = self.length;
        let mut ir = vec![0.0; len];

        // FFT-based correlation
        let mut planner = FftPlanner::new();
        let fft_size = len.next_power_of_two() * 2;
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // FFT of MLS
        let mut mls_spectrum: Vec<Complex64> = self.sequence.iter()
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        mls_spectrum.resize(fft_size, Complex64::new(0.0, 0.0));
        fft_forward.process(&mut mls_spectrum);

        // FFT of recording
        let mut rec_spectrum: Vec<Complex64> = recording.iter()
            .take(fft_size)
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        rec_spectrum.resize(fft_size, Complex64::new(0.0, 0.0));
        fft_forward.process(&mut rec_spectrum);

        // Cross-correlation: IFFT(conj(MLS) * Recording)
        let mut corr_spectrum: Vec<Complex64> = mls_spectrum.iter()
            .zip(rec_spectrum.iter())
            .map(|(m, r)| m.conj() * r)
            .collect();

        fft_inverse.process(&mut corr_spectrum);

        // Extract real part
        let scale = 1.0 / (fft_size as f64 * len as f64);
        for (i, &c) in corr_spectrum.iter().take(len).enumerate() {
            ir[i] = c.re * scale;
        }

        ImpulseResponse::new(ir, 48000.0, 1) // Assume 48kHz
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sweep_generation() {
        let config = SweepConfig::quick();
        let sweep = IrDeconvolver::generate_sweep(&config);

        let expected_len = (config.duration * config.sample_rate) as usize;
        assert_eq!(sweep.len(), expected_len);

        // Check amplitude bounds
        for &s in &sweep {
            assert!(s.abs() <= 1.0);
        }
    }

    #[test]
    fn test_deconvolution() {
        let config = SweepConfig::quick();
        let deconvolver = IrDeconvolver::new(config.clone());

        // Convolve sweep with simple IR (delta)
        let sweep = deconvolver.reference_sweep();
        let mut recording = vec![0.0; sweep.len() * 2];
        recording[..sweep.len()].copy_from_slice(sweep);

        // Extract IR
        let ir = deconvolver.extract_ir(&recording);

        // Should have a peak near the beginning
        let peak = ir.samples.iter()
            .take(100)
            .map(|s| s.abs())
            .fold(0.0, f64::max);

        assert!(peak > 0.1, "Peak should be significant: {}", peak);
    }

    #[test]
    fn test_mls_generation() {
        let mls = MlsGenerator::new(10);

        // Length should be 2^10 - 1 = 1023
        assert_eq!(mls.length(), 1023);

        // Check bipolar values
        for &s in mls.sequence() {
            assert!(s == -1.0 || s == 1.0);
        }

        // Check DC balance (should be close to zero)
        let sum: f64 = mls.sequence().iter().sum();
        assert!(sum.abs() <= 2.0, "MLS should be DC balanced: {}", sum);
    }

    #[test]
    fn test_sweep_types() {
        for sweep_type in [SweepType::Linear, SweepType::Logarithmic, SweepType::ExponentialSine] {
            let config = SweepConfig {
                sweep_type,
                duration: 1.0,
                ..SweepConfig::default()
            };

            let sweep = IrDeconvolver::generate_sweep(&config);
            assert!(!sweep.is_empty());
        }
    }
}

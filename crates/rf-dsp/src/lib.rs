//! rf-dsp: DSP processors for ReelForge
//!
//! High-performance, SIMD-optimized audio processing.
//!
//! ## Core Modules
//! - `simd` - Runtime SIMD dispatch (AVX-512/AVX2/SSE4.2/NEON)
//! - `automation` - Sample-accurate parameter automation
//! - `delay_compensation` - Full delay compensation system
//! - `smoothing` - Lock-free parameter smoothing
//!
//! ## DSP Modules
//! - `biquad` - TDF-II biquad filters (lowpass, highpass, peaking, shelving)
//! - `eq` - 64-band parametric EQ with dynamic EQ per band
//! - `dynamics` - Compressor (VCA/Opto/FET), limiter, gate, expander
//! - `reverb` - Convolution and algorithmic reverbs
//! - `delay` - Simple, ping-pong, multi-tap, and modulated delays
//! - `spatial` - Panner, width, M/S, stereo imaging
//! - `saturation` - Tape, tube, transistor saturation, waveshaper
//! - `channel` - Complete channel strip processor
//! - `analysis` - FFT, peak/RMS meters, LUFS, true peak
//!
//! ## Advanced DSP
//! - `convolution` - Professional partitioned convolution (IR reverb)
//! - `linear_phase` - True linear phase EQ (FIR-based)
//! - `spectral` - Spectral processing (gate, freeze, compressor)
//! - `multiband` - Multi-band dynamics (compressor, limiter)

#![feature(portable_simd)]

// Core infrastructure
pub mod simd;
pub mod automation;
pub mod delay_compensation;
pub mod smoothing;

// DSP processors
pub mod biquad;
pub mod eq;
pub mod dynamics;
pub mod reverb;
pub mod delay;
pub mod spatial;
pub mod saturation;
pub mod channel;
pub mod analysis;

// Advanced DSP
pub mod convolution;
pub mod linear_phase;
pub mod spectral;
pub mod multiband;
pub mod metering;

// Re-exports for convenience
pub use simd::{SimdLevel, DspDispatch, detect_simd_level, simd_level};
pub use simd::{apply_gain, process_biquad, mix_add, apply_stereo_gain};
pub use simd::{BiquadCoeffsSimd, BiquadStateSimd};

pub use automation::{CurveType, AutomationPoint, AutomationLane, AutomationManager};
pub use automation::AtomicAutomationValue;

pub use delay_compensation::{DelayLine, StereoDelayLine, DelayCompensationManager};
pub use delay_compensation::TrackDelayCompensation;

pub use smoothing::{SmoothingType, SmoothedParam, SmoothedStereoParam, ParameterBank};

use rf_core::Sample;

/// Trait for all DSP processors
pub trait Processor: Send + Sync {
    /// Reset processor state
    fn reset(&mut self);

    /// Get latency in samples
    fn latency(&self) -> usize {
        0
    }
}

/// Mono processor trait
pub trait MonoProcessor: Processor {
    /// Process a single sample
    fn process_sample(&mut self, input: Sample) -> Sample;

    /// Process a block of samples
    fn process_block(&mut self, buffer: &mut [Sample]) {
        for sample in buffer.iter_mut() {
            *sample = self.process_sample(*sample);
        }
    }
}

/// Stereo processor trait
pub trait StereoProcessor: Processor {
    /// Process a stereo sample pair
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample);

    /// Process stereo blocks
    fn process_block(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        debug_assert_eq!(left.len(), right.len());
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            (*l, *r) = self.process_sample(*l, *r);
        }
    }
}

/// Processor configuration for sample rate changes
pub trait ProcessorConfig {
    fn set_sample_rate(&mut self, sample_rate: f64);
}

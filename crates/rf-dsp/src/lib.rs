//! rf-dsp: DSP processors for ReelForge
//!
//! High-performance, SIMD-optimized audio processing.
//!
//! ## Modules
//! - `biquad` - TDF-II biquad filters (lowpass, highpass, peaking, shelving)
//! - `eq` - 64-band parametric EQ with dynamic EQ per band
//! - `dynamics` - Compressor (VCA/Opto/FET), limiter, gate, expander
//! - `reverb` - Convolution and algorithmic reverbs
//! - `delay` - Simple, ping-pong, multi-tap, and modulated delays
//! - `spatial` - Panner, width, M/S, stereo imaging
//! - `saturation` - Tape, tube, transistor saturation, waveshaper
//! - `channel` - Complete channel strip processor
//! - `analysis` - FFT, peak/RMS meters, LUFS, true peak

#![feature(portable_simd)]

pub mod biquad;
pub mod eq;
pub mod dynamics;
pub mod reverb;
pub mod delay;
pub mod spatial;
pub mod saturation;
pub mod channel;
pub mod analysis;

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

//! rf-dsp: DSP processors for FluxForge Studio
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
#![allow(dead_code)]
// GPU feature is conditional
#![allow(unexpected_cfgs)]

// Core infrastructure
pub mod automation;
pub mod delay_compensation;
pub mod simd;
pub mod smoothing;

// DSP processors
pub mod analysis;
pub mod biquad;
pub mod channel;
pub mod delay;
pub mod dynamics;
pub mod eq;
pub mod reverb;
pub mod saturation;
pub mod spatial;
pub mod surround;

// Advanced DSP
pub mod convolution;
pub mod linear_phase;
pub mod loudness_advanced; // Psychoacoustic loudness (Zwicker, sharpness, roughness)
pub mod metering;
pub mod metering_simd; // SIMD-optimized metering (AVX2/AVX-512, 8x True Peak)
pub mod multiband;
pub mod oversampling;
pub mod signal_integrity; // Signal integrity chain (DC block, auto-gain, ISP limiter, dither)
pub mod spectral; // Global oversampling + SIMD biquad batch processing

// DSD Ultimate (Phase 2)
pub mod dsd; // DSD64/128/256/512, DoP, SACD, SDM

// Convolution Ultimate (Phase 2)
pub mod convolution_ultra; // True Stereo, Non-uniform, Zero-latency, Morphing, Deconvolution

// GPU DSP (Phase 2)
pub mod gpu; // Hybrid GPU/CPU scheduler, compute shaders

// Advanced Formats (Phase 2)
pub mod formats; // MQA decode, TrueHD passthrough

// Professional EQ (Pro-Q 4 competitor)
pub mod eq_pro;

// Ultimate EQ (beyond any competitor)
pub mod eq_ultra;

// Advanced EQ modules
pub mod eq_analog; // Pultec, API, Neve emulations
pub mod eq_room; // Room correction, target curves
pub mod eq_stereo; // Bass mono, M/S, per-band stereo

// Audio analysis & manipulation
pub mod elastic;
pub mod elastic_pro; // Ultimate time-stretching (STN + Phase Vocoder + Formant)
pub mod pitch;
pub mod timestretch;
pub mod transient;
pub mod wavelet; // Multi-resolution analysis (DWT, CWT, CQT) // ULTIMATIVNI Time Stretch Engine (NSGT + RTPGHI + STN + Formant)

// Re-export transient shaper
pub use transient::{
    DetectionAlgorithm, DetectionSettings, MultibandTransientShaper, SliceGenerator,
    TransientDetector, TransientMarker, TransientShaper, TransientType,
};

// Re-export pitch editor
pub use pitch::{
    Pitch, PitchCorrector, PitchDetector, PitchDetectorConfig, PitchEditorState, PitchSegment,
    Scale,
};

// Re-export spectral processors
pub use spectral::{
    DeClick, RepairMode, SpectralCompressor, SpectralFreeze, SpectralGate, SpectralRepair,
    SpectralSelection,
};

// Re-export Professional EQ
pub use eq_pro::{
    AnalyzerMode, AutoGain, CollisionDetector, DynamicParams as ProDynamicParams,
    EqBand as ProEqBand, EqMatch, FilterShape, MAX_BANDS as PRO_EQ_MAX_BANDS,
    PhaseMode as ProPhaseMode, ProEq, Slope as FilterSlope2, SpectrumAnalyzer, StereoPlacement,
    SvfCoeffs, SvfCore,
};

// Re-export Ultimate EQ
pub use eq_ultra::{
    CorrelationMeter, EqualLoudness, FrequencyAnalyzer, FrequencySuggestion, HarmonicSaturator,
    MztCoeffs, MztFilter, OversampleMode, Oversampler, SaturationType,
    TransientDetector as UltraTransientDetector, ULTRA_MAX_BANDS, UltraBand, UltraEq,
    UltraFilterType,
};

// Re-export Analog EQ models
pub use eq_analog::{
    ANALOG_MAX_BANDS, Api550, Api550HighFreq, Api550LowFreq, Api550MidFreq, DiscreteSaturation,
    Neve1073, Neve1073HighFreq, Neve1073HpFreq, Neve1073LowFreq, NeveTransformer,
    OutputTransformer, PultecEqp1a, PultecHighAttenFreq, PultecHighBoostFreq, PultecLowFreq,
    StereoApi550, StereoNeve1073, StereoPultec, TubeSaturation,
};

// Re-export Stereo EQ
pub use eq_stereo::{
    BassMono, CrossoverSlope, STEREO_EQ_MAX_BANDS, StereoCorrector, StereoEq, StereoEqBand,
    StereoImageAnalyzer, StereoMode, WidthBand,
};

// Re-export Room Correction
pub use eq_room::{RoomCorrectionEq, RoomMeasurement, RoomMode, RoomModeType, TargetCurve};

// Re-export Wavelet/CQT analysis
pub use wavelet::{
    CQT, CQTResult, CWT, CWTResult, DWT, MultiResolutionAnalyzer, MultiResolutionResult,
    WaveletDecomposition, WaveletFilter, WaveletType,
};

// Re-export Elastic Pro (Ultimate Time Stretching)
pub use elastic_pro::{
    ElasticPro, ElasticProConfig, FormantPreserver, MultiResolutionStretcher, NoiseMorpher,
    PhaseVocoder, StnComponent, StnDecomposer, StnDecomposition, StretchMode, StretchQuality,
    TransientProcessor,
};

// Re-export LUFS and True Peak metering (ITU-R BS.1770-4 / EBU R128)
pub use metering::{
    BalanceMeter, BroadcastMeter, CorrelationMeter as StereoCorrelationMeter, DynamicRangeMeter,
    KMeter, KSystem, LufsMeter, PhasePoint, PhaseScope, PpmMeter, PpmType, StereoMeter,
    StereoPpmMeter, TruePeakMeter, VuMeter,
};

// Re-export SIMD-optimized metering (8x True Peak, PSR, vectorized RMS)
pub use metering_simd::{
    TruePeak8x, PsrMeter, CrestFactorMeter,
    calculate_rms_simd, find_peak_simd, calculate_correlation_simd,
};

// Re-exports for convenience
pub use simd::{BiquadCoeffsSimd, BiquadStateSimd};
pub use simd::{DspDispatch, SimdLevel, detect_simd_level, simd_level};
pub use simd::{apply_gain, apply_stereo_gain, mix_add, process_biquad};

pub use automation::AtomicAutomationValue;
pub use automation::{AutomationLane, AutomationManager, AutomationPoint, CurveType};

pub use delay_compensation::TrackDelayCompensation;
pub use delay_compensation::{DelayCompensationManager, DelayLine, StereoDelayLine};

pub use smoothing::{ParameterBank, SmoothedParam, SmoothedStereoParam, SmoothingType};

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

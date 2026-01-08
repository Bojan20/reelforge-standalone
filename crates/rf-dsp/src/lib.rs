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
#![allow(dead_code)]
// GPU feature is conditional
#![allow(unexpected_cfgs)]

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
pub mod surround;
pub mod saturation;
pub mod channel;
pub mod analysis;

// Advanced DSP
pub mod convolution;
pub mod linear_phase;
pub mod spectral;
pub mod multiband;
pub mod metering;
pub mod metering_simd;      // SIMD-optimized metering (AVX2/AVX-512, 8x True Peak)
pub mod loudness_advanced;  // Psychoacoustic loudness (Zwicker, sharpness, roughness)
pub mod signal_integrity;   // Signal integrity chain (DC block, auto-gain, ISP limiter, dither)
pub mod oversampling;       // Global oversampling + SIMD biquad batch processing

// DSD Ultimate (Phase 2)
pub mod dsd;                // DSD64/128/256/512, DoP, SACD, SDM

// Convolution Ultimate (Phase 2)
pub mod convolution_ultra;  // True Stereo, Non-uniform, Zero-latency, Morphing, Deconvolution

// GPU DSP (Phase 2)
pub mod gpu;                // Hybrid GPU/CPU scheduler, compute shaders

// Advanced Formats (Phase 2)
pub mod formats;            // MQA decode, TrueHD passthrough

// Professional EQ (Pro-Q 4 competitor)
pub mod eq_pro;

// Ultimate EQ (beyond any competitor)
pub mod eq_ultra;

// Advanced EQ modules
pub mod eq_analog;       // Pultec, API, Neve emulations
pub mod eq_minimum_phase; // Hilbert transform, zero-latency
pub mod eq_stereo;       // Bass mono, M/S, per-band stereo
pub mod eq_room;         // Room correction, target curves
pub mod eq_morph;        // Preset interpolation

// Audio analysis & manipulation
pub mod transient;
pub mod elastic;
pub mod elastic_pro;  // Ultimate time-stretching (STN + Phase Vocoder + Formant)
pub mod pitch;
pub mod wavelet;      // Multi-resolution analysis (DWT, CWT, CQT)
pub mod timestretch;  // ULTIMATIVNI Time Stretch Engine (NSGT + RTPGHI + STN + Formant)

// Re-export transient shaper
pub use transient::{
    TransientShaper,
    MultibandTransientShaper,
    TransientDetector,
    TransientMarker,
    TransientType,
    DetectionAlgorithm,
    DetectionSettings,
    SliceGenerator,
};

// Re-export pitch editor
pub use pitch::{
    Pitch,
    PitchSegment,
    PitchDetector,
    PitchDetectorConfig,
    PitchCorrector,
    PitchEditorState,
    Scale,
};

// Re-export spectral processors
pub use spectral::{
    SpectralGate,
    SpectralFreeze,
    SpectralCompressor,
    SpectralRepair,
    SpectralSelection,
    RepairMode,
    DeClick,
};

// Re-export Professional EQ
pub use eq_pro::{
    ProEq,
    EqBand as ProEqBand,
    FilterShape,
    Slope as FilterSlope2,
    PhaseMode as ProPhaseMode,
    StereoPlacement,
    AnalyzerMode,
    DynamicParams as ProDynamicParams,
    SpectrumAnalyzer,
    EqMatch,
    CollisionDetector,
    AutoGain,
    SvfCore,
    SvfCoeffs,
    MAX_BANDS as PRO_EQ_MAX_BANDS,
};

// Re-export Ultimate EQ
pub use eq_ultra::{
    UltraEq,
    UltraBand,
    MztCoeffs,
    MztFilter,
    Oversampler,
    OversampleMode,
    TransientDetector as UltraTransientDetector,
    HarmonicSaturator,
    SaturationType,
    EqualLoudness,
    CorrelationMeter,
    FrequencyAnalyzer,
    FrequencySuggestion,
    UltraFilterType,
    ULTRA_MAX_BANDS,
};

// Re-export Analog EQ models
pub use eq_analog::{
    PultecEqp1a,
    PultecLowFreq,
    PultecHighBoostFreq,
    PultecHighAttenFreq,
    Api550,
    Api550LowFreq,
    Api550MidFreq,
    Api550HighFreq,
    Neve1073,
    Neve1073HpFreq,
    Neve1073LowFreq,
    Neve1073HighFreq,
    TubeSaturation,
    OutputTransformer,
    DiscreteSaturation,
    NeveTransformer,
    StereoPultec,
    StereoApi550,
    StereoNeve1073,
    ANALOG_MAX_BANDS,
};

// Re-export Minimum Phase EQ
pub use eq_minimum_phase::{
    HilbertTransform,
    MinimumPhaseReconstructor,
    MinPhaseEq,
    MinPhaseEqBand,
    MinPhaseFilterType,
    LinearToMinPhase,
    MIN_PHASE_MAX_BANDS,
};

// Re-export Stereo EQ
pub use eq_stereo::{
    BassMono,
    CrossoverSlope,
    StereoMode,
    StereoEqBand,
    WidthBand,
    StereoEq,
    StereoImageAnalyzer,
    StereoCorrector,
    STEREO_EQ_MAX_BANDS,
};

// Re-export Room Correction
pub use eq_room::{
    TargetCurve,
    RoomMeasurement,
    RoomMode,
    RoomModeType,
    RoomCorrectionEq,
};

// Re-export Morphing EQ
pub use eq_morph::{
    BandSnapshot,
    MorphFilterType,
    EqPreset,
    MorphingEq,
    PRESET_MAX_BANDS,
};

// Re-export Wavelet/CQT analysis
pub use wavelet::{
    WaveletType,
    WaveletFilter,
    DWT,
    WaveletDecomposition,
    CWT,
    CWTResult,
    CQT,
    CQTResult,
    MultiResolutionAnalyzer,
    MultiResolutionResult,
};

// Re-export Elastic Pro (Ultimate Time Stretching)
pub use elastic_pro::{
    StnComponent,
    StnDecomposition,
    StnDecomposer,
    PhaseVocoder,
    TransientProcessor,
    NoiseMorpher,
    FormantPreserver,
    MultiResolutionStretcher,
    StretchQuality,
    StretchMode,
    ElasticProConfig,
    ElasticPro,
};

// Re-export LUFS and True Peak metering (ITU-R BS.1770-4 / EBU R128)
pub use metering::{
    LufsMeter,
    TruePeakMeter,
    BroadcastMeter,
    CorrelationMeter as StereoCorrelationMeter,
    BalanceMeter,
    KSystem,
    KMeter,
    VuMeter,
    PpmMeter,
    PpmType,
    StereoPpmMeter,
    DynamicRangeMeter,
    PhaseScope,
    PhasePoint,
    StereoMeter,
};

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

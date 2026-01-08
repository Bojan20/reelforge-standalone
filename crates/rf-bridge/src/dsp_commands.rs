//! DSP Command System - Lock-free audio thread communication
//!
//! All parameter changes from UI are sent through this command queue
//! to ensure real-time safety (no allocations, no locks in audio thread).

use std::sync::atomic::{AtomicU64, Ordering};

/// Unique ID for tracking commands
pub type CommandId = u64;

/// Global command ID counter
static COMMAND_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Generate unique command ID
pub fn next_command_id() -> CommandId {
    COMMAND_COUNTER.fetch_add(1, Ordering::Relaxed)
}

// ============================================================================
// FILTER TYPES
// ============================================================================

/// EQ filter shape (matches rf-dsp FilterShape)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum FilterType {
    Bell = 0,
    LowShelf = 1,
    HighShelf = 2,
    LowCut = 3,
    HighCut = 4,
    Notch = 5,
    Bandpass = 6,
    TiltShelf = 7,
    Allpass = 8,
    Brickwall = 9,
}

impl From<u8> for FilterType {
    fn from(v: u8) -> Self {
        match v {
            0 => FilterType::Bell,
            1 => FilterType::LowShelf,
            2 => FilterType::HighShelf,
            3 => FilterType::LowCut,
            4 => FilterType::HighCut,
            5 => FilterType::Notch,
            6 => FilterType::Bandpass,
            7 => FilterType::TiltShelf,
            8 => FilterType::Allpass,
            9 => FilterType::Brickwall,
            _ => FilterType::Bell,
        }
    }
}

/// Filter slope in dB/octave
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum FilterSlope {
    Db6 = 0,
    Db12 = 1,
    Db18 = 2,
    Db24 = 3,
    Db36 = 4,
    Db48 = 5,
    Db72 = 6,
    Db96 = 7,
}

impl From<u8> for FilterSlope {
    fn from(v: u8) -> Self {
        match v {
            0 => FilterSlope::Db6,
            1 => FilterSlope::Db12,
            2 => FilterSlope::Db18,
            3 => FilterSlope::Db24,
            4 => FilterSlope::Db36,
            5 => FilterSlope::Db48,
            6 => FilterSlope::Db72,
            7 => FilterSlope::Db96,
            _ => FilterSlope::Db12,
        }
    }
}

/// Phase mode for EQ
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PhaseMode {
    ZeroLatency = 0,
    Natural = 1,
    Linear = 2,
    Hybrid = 3,
}

impl From<u8> for PhaseMode {
    fn from(v: u8) -> Self {
        match v {
            0 => PhaseMode::ZeroLatency,
            1 => PhaseMode::Natural,
            2 => PhaseMode::Linear,
            3 => PhaseMode::Hybrid,
            _ => PhaseMode::ZeroLatency,
        }
    }
}

/// Stereo placement for EQ band
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum StereoPlacement {
    Stereo = 0,
    Left = 1,
    Right = 2,
    Mid = 3,
    Side = 4,
}

impl From<u8> for StereoPlacement {
    fn from(v: u8) -> Self {
        match v {
            0 => StereoPlacement::Stereo,
            1 => StereoPlacement::Left,
            2 => StereoPlacement::Right,
            3 => StereoPlacement::Mid,
            4 => StereoPlacement::Side,
            _ => StereoPlacement::Stereo,
        }
    }
}

/// Analyzer display mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum AnalyzerMode {
    Off = 0,
    PreEq = 1,
    PostEq = 2,
    Sidechain = 3,
    Delta = 4,
}

impl From<u8> for AnalyzerMode {
    fn from(v: u8) -> Self {
        match v {
            0 => AnalyzerMode::Off,
            1 => AnalyzerMode::PreEq,
            2 => AnalyzerMode::PostEq,
            3 => AnalyzerMode::Sidechain,
            4 => AnalyzerMode::Delta,
            _ => AnalyzerMode::Off,
        }
    }
}

/// Pultec frequency selections
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PultecLowFreq {
    Hz20 = 0,
    Hz30 = 1,
    Hz60 = 2,
    Hz100 = 3,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PultecHighBoostFreq {
    Khz3 = 0,
    Khz4 = 1,
    Khz5 = 2,
    Khz8 = 3,
    Khz10 = 4,
    Khz12 = 5,
    Khz16 = 6,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PultecHighAttenFreq {
    Khz5 = 0,
    Khz10 = 1,
    Khz20 = 2,
}

/// Target curve for room correction
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum TargetCurve {
    Flat = 0,
    Harman = 1,
    BK = 2,
    BBC = 3,
    XCurve = 4,
    Custom = 5,
}

impl From<u8> for TargetCurve {
    fn from(v: u8) -> Self {
        match v {
            0 => TargetCurve::Flat,
            1 => TargetCurve::Harman,
            2 => TargetCurve::BK,
            3 => TargetCurve::BBC,
            4 => TargetCurve::XCurve,
            5 => TargetCurve::Custom,
            _ => TargetCurve::Flat,
        }
    }
}

// ============================================================================
// DSP COMMANDS
// ============================================================================

/// All DSP parameter commands - sent from UI to audio thread
#[derive(Debug, Clone, Copy)]
pub enum DspCommand {
    // ═══════════════════════════════════════════════════════════════════════
    // PRO EQ (64-band)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set complete band parameters
    EqSetBand {
        track_id: u32,
        band_index: u8,
        freq: f64,
        gain_db: f64,
        q: f64,
        filter_type: FilterType,
        slope: FilterSlope,
        stereo: StereoPlacement,
    },

    /// Enable/disable single band
    EqEnableBand {
        track_id: u32,
        band_index: u8,
        enabled: bool,
    },

    /// Solo band (mute others for preview)
    EqSoloBand {
        track_id: u32,
        band_index: u8,
        solo: bool,
    },

    /// Set only frequency
    EqSetFrequency {
        track_id: u32,
        band_index: u8,
        freq: f64,
    },

    /// Set only gain
    EqSetGain {
        track_id: u32,
        band_index: u8,
        gain_db: f64,
    },

    /// Set only Q
    EqSetQ {
        track_id: u32,
        band_index: u8,
        q: f64,
    },

    /// Set filter type
    EqSetFilterType {
        track_id: u32,
        band_index: u8,
        filter_type: FilterType,
    },

    /// Global EQ bypass
    EqBypass {
        track_id: u32,
        bypass: bool,
    },

    /// Set phase mode
    EqSetPhaseMode {
        track_id: u32,
        mode: PhaseMode,
        hybrid_blend: f64, // 0-1, only used for Hybrid mode
    },

    /// Set output gain
    EqSetOutputGain {
        track_id: u32,
        gain_db: f64,
    },

    /// Auto-gain on/off
    EqSetAutoGain {
        track_id: u32,
        enabled: bool,
    },

    /// Set analyzer mode
    EqSetAnalyzerMode {
        track_id: u32,
        mode: AnalyzerMode,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // DYNAMIC EQ (per-band dynamics)
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable dynamic mode for band
    EqSetDynamicEnabled {
        track_id: u32,
        band_index: u8,
        enabled: bool,
    },

    /// Set dynamic parameters
    EqSetDynamicParams {
        track_id: u32,
        band_index: u8,
        threshold_db: f64,
        ratio: f64,
        attack_ms: f64,
        release_ms: f64,
        range_db: f64,
    },

    /// Set sidechain source for dynamic EQ
    EqSetSidechainSource {
        track_id: u32,
        band_index: u8,
        source_track_id: u32,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // ANALOG EQ - PULTEC EQP-1A
    // ═══════════════════════════════════════════════════════════════════════

    PultecSetLowBoost {
        track_id: u32,
        boost_db: f64,      // 0-10
        freq: PultecLowFreq,
    },

    PultecSetLowAtten {
        track_id: u32,
        atten_db: f64,      // 0-10
    },

    PultecSetHighBoost {
        track_id: u32,
        boost_db: f64,      // 0-10
        bandwidth: f64,     // 0=Sharp, 1=Broad
        freq: PultecHighBoostFreq,
    },

    PultecSetHighAtten {
        track_id: u32,
        atten_db: f64,      // 0-10
        freq: PultecHighAttenFreq,
    },

    PultecBypass {
        track_id: u32,
        bypass: bool,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // ANALOG EQ - API 550
    // ═══════════════════════════════════════════════════════════════════════

    Api550SetLow {
        track_id: u32,
        gain_db: f64,
        freq_index: u8,     // 0-4 (different frequencies)
    },

    Api550SetMid {
        track_id: u32,
        gain_db: f64,
        freq_hz: f64,       // Continuous 200-3200
    },

    Api550SetHigh {
        track_id: u32,
        gain_db: f64,
        freq_index: u8,
    },

    Api550Bypass {
        track_id: u32,
        bypass: bool,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // ANALOG EQ - NEVE 1073
    // ═══════════════════════════════════════════════════════════════════════

    Neve1073SetHighpass {
        track_id: u32,
        enabled: bool,
        freq_index: u8,     // 0=Off, 1=50Hz, 2=80Hz, 3=160Hz, 4=300Hz
    },

    Neve1073SetLow {
        track_id: u32,
        gain_db: f64,
        freq_index: u8,
    },

    Neve1073SetMid {
        track_id: u32,
        gain_db: f64,
        freq_hz: f64,
    },

    Neve1073SetHigh {
        track_id: u32,
        gain_db: f64,
        freq_index: u8,
    },

    Neve1073Bypass {
        track_id: u32,
        bypass: bool,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // STEREO EQ
    // ═══════════════════════════════════════════════════════════════════════

    /// Set bass mono crossover frequency
    StereoEqSetBassMonoFreq {
        track_id: u32,
        freq: f64,
    },

    /// Set bass mono blend
    StereoEqSetBassMonoBlend {
        track_id: u32,
        blend: f64,         // 0=Stereo, 1=Mono
    },

    /// Set per-band stereo width
    StereoEqSetBandWidth {
        track_id: u32,
        band_index: u8,
        width: f64,         // 0=Mono, 1=Normal, 2=Wide
    },

    /// Set per-band M/S mode
    StereoEqSetBandMsMode {
        track_id: u32,
        band_index: u8,
        mode: StereoPlacement,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // ROOM CORRECTION
    // ═══════════════════════════════════════════════════════════════════════

    /// Set target curve
    RoomEqSetTargetCurve {
        track_id: u32,
        curve: TargetCurve,
    },

    /// Set correction amount (0-100%)
    RoomEqSetAmount {
        track_id: u32,
        amount: f64,
    },

    /// Enable/disable room correction
    RoomEqBypass {
        track_id: u32,
        bypass: bool,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // MORPHING EQ
    // ═══════════════════════════════════════════════════════════════════════

    /// Set morph position (XY pad)
    MorphEqSetPosition {
        track_id: u32,
        x: f64,             // 0-1
        y: f64,             // 0-1
    },

    /// Store current EQ as preset A/B/C/D
    MorphEqStorePreset {
        track_id: u32,
        slot: u8,           // 0=A, 1=B, 2=C, 3=D
    },

    /// Set morph time (for animated transitions)
    MorphEqSetTime {
        track_id: u32,
        time_ms: f64,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // SPECTRUM ANALYZER
    // ═══════════════════════════════════════════════════════════════════════

    /// Set FFT size
    SpectrumSetFftSize {
        track_id: u32,
        size: u16,          // 1024, 2048, 4096, 8192, 16384, 32768
    },

    /// Set analyzer smoothing
    SpectrumSetSmoothing {
        track_id: u32,
        smoothing: f64,     // 0-1
    },

    /// Set peak hold time
    SpectrumSetPeakHold {
        track_id: u32,
        hold_ms: f64,
        decay_rate: f64,
    },

    /// Freeze spectrum
    SpectrumFreeze {
        track_id: u32,
        freeze: bool,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // EQ MATCH
    // ═══════════════════════════════════════════════════════════════════════

    /// Start learning source spectrum
    EqMatchStartLearnSource {
        track_id: u32,
    },

    /// Start learning reference spectrum
    EqMatchStartLearnReference {
        track_id: u32,
    },

    /// Stop learning
    EqMatchStopLearn {
        track_id: u32,
    },

    /// Apply learned match
    EqMatchApply {
        track_id: u32,
        amount: f64,        // 0-100%
        smoothing: f64,     // 0-100%
    },

    // ═══════════════════════════════════════════════════════════════════════
    // METERING REQUESTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Request spectrum data (triggers analysis update)
    RequestSpectrum {
        track_id: u32,
    },

    /// Request stereo correlation data
    RequestCorrelation {
        track_id: u32,
    },

    /// Request LUFS data
    RequestLufs {
        track_id: u32,
    },

    /// Request goniometer points
    RequestGoniometer {
        track_id: u32,
        num_points: u16,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // MIXER / TRACK CONTROLS
    // ═══════════════════════════════════════════════════════════════════════

    /// Set track volume (linear, 0.0-2.0, 1.0 = unity)
    TrackSetVolume {
        track_id: u32,
        volume: f64,
    },

    /// Set track pan (-1.0 left, 0.0 center, 1.0 right)
    TrackSetPan {
        track_id: u32,
        pan: f64,
    },

    /// Set track mute
    TrackSetMute {
        track_id: u32,
        muted: bool,
    },

    /// Set track solo
    TrackSetSolo {
        track_id: u32,
        solo: bool,
    },

    /// Set track output bus
    TrackSetBus {
        track_id: u32,
        bus_id: u8,
    },
}

impl DspCommand {
    /// Get track ID this command targets
    pub fn track_id(&self) -> u32 {
        match self {
            DspCommand::EqSetBand { track_id, .. } => *track_id,
            DspCommand::EqEnableBand { track_id, .. } => *track_id,
            DspCommand::EqSoloBand { track_id, .. } => *track_id,
            DspCommand::EqSetFrequency { track_id, .. } => *track_id,
            DspCommand::EqSetGain { track_id, .. } => *track_id,
            DspCommand::EqSetQ { track_id, .. } => *track_id,
            DspCommand::EqSetFilterType { track_id, .. } => *track_id,
            DspCommand::EqBypass { track_id, .. } => *track_id,
            DspCommand::EqSetPhaseMode { track_id, .. } => *track_id,
            DspCommand::EqSetOutputGain { track_id, .. } => *track_id,
            DspCommand::EqSetAutoGain { track_id, .. } => *track_id,
            DspCommand::EqSetAnalyzerMode { track_id, .. } => *track_id,
            DspCommand::EqSetDynamicEnabled { track_id, .. } => *track_id,
            DspCommand::EqSetDynamicParams { track_id, .. } => *track_id,
            DspCommand::EqSetSidechainSource { track_id, .. } => *track_id,
            DspCommand::PultecSetLowBoost { track_id, .. } => *track_id,
            DspCommand::PultecSetLowAtten { track_id, .. } => *track_id,
            DspCommand::PultecSetHighBoost { track_id, .. } => *track_id,
            DspCommand::PultecSetHighAtten { track_id, .. } => *track_id,
            DspCommand::PultecBypass { track_id, .. } => *track_id,
            DspCommand::Api550SetLow { track_id, .. } => *track_id,
            DspCommand::Api550SetMid { track_id, .. } => *track_id,
            DspCommand::Api550SetHigh { track_id, .. } => *track_id,
            DspCommand::Api550Bypass { track_id, .. } => *track_id,
            DspCommand::Neve1073SetHighpass { track_id, .. } => *track_id,
            DspCommand::Neve1073SetLow { track_id, .. } => *track_id,
            DspCommand::Neve1073SetMid { track_id, .. } => *track_id,
            DspCommand::Neve1073SetHigh { track_id, .. } => *track_id,
            DspCommand::Neve1073Bypass { track_id, .. } => *track_id,
            DspCommand::StereoEqSetBassMonoFreq { track_id, .. } => *track_id,
            DspCommand::StereoEqSetBassMonoBlend { track_id, .. } => *track_id,
            DspCommand::StereoEqSetBandWidth { track_id, .. } => *track_id,
            DspCommand::StereoEqSetBandMsMode { track_id, .. } => *track_id,
            DspCommand::RoomEqSetTargetCurve { track_id, .. } => *track_id,
            DspCommand::RoomEqSetAmount { track_id, .. } => *track_id,
            DspCommand::RoomEqBypass { track_id, .. } => *track_id,
            DspCommand::MorphEqSetPosition { track_id, .. } => *track_id,
            DspCommand::MorphEqStorePreset { track_id, .. } => *track_id,
            DspCommand::MorphEqSetTime { track_id, .. } => *track_id,
            DspCommand::SpectrumSetFftSize { track_id, .. } => *track_id,
            DspCommand::SpectrumSetSmoothing { track_id, .. } => *track_id,
            DspCommand::SpectrumSetPeakHold { track_id, .. } => *track_id,
            DspCommand::SpectrumFreeze { track_id, .. } => *track_id,
            DspCommand::EqMatchStartLearnSource { track_id, .. } => *track_id,
            DspCommand::EqMatchStartLearnReference { track_id, .. } => *track_id,
            DspCommand::EqMatchStopLearn { track_id, .. } => *track_id,
            DspCommand::EqMatchApply { track_id, .. } => *track_id,
            DspCommand::RequestSpectrum { track_id, .. } => *track_id,
            DspCommand::RequestCorrelation { track_id, .. } => *track_id,
            DspCommand::RequestLufs { track_id, .. } => *track_id,
            DspCommand::RequestGoniometer { track_id, .. } => *track_id,
            // Mixer commands
            DspCommand::TrackSetVolume { track_id, .. } => *track_id,
            DspCommand::TrackSetPan { track_id, .. } => *track_id,
            DspCommand::TrackSetMute { track_id, .. } => *track_id,
            DspCommand::TrackSetSolo { track_id, .. } => *track_id,
            DspCommand::TrackSetBus { track_id, .. } => *track_id,
        }
    }
}

// ============================================================================
// ANALYSIS DATA (Audio Thread → UI)
// ============================================================================

/// Spectrum data for visualization (256 bins, log-scaled)
#[derive(Clone)]
pub struct SpectrumData {
    /// Magnitude per bin in dB (-100 to 0)
    pub magnitudes: [f32; 256],
    /// Peak hold values
    pub peaks: [f32; 256],
    /// Pre-EQ spectrum (for delta mode)
    pub pre_eq: [f32; 256],
    /// FFT size used
    pub fft_size: u16,
}

impl Default for SpectrumData {
    fn default() -> Self {
        Self {
            magnitudes: [-100.0; 256],
            peaks: [-100.0; 256],
            pre_eq: [-100.0; 256],
            fft_size: 4096,
        }
    }
}

/// Stereo metering data
#[derive(Clone, Default)]
pub struct StereoMeterData {
    /// Correlation (-1 to +1)
    pub correlation: f32,
    /// Balance (-1 = left, +1 = right)
    pub balance: f32,
    /// Stereo width (0-1)
    pub width: f32,
    /// Phase coherence (0-1)
    pub coherence: f32,
    /// Goniometer points (for vectorscope)
    pub goniometer_points: Vec<(f32, f32)>,
}

/// Loudness metering data
#[derive(Clone, Default)]
pub struct LoudnessData {
    /// Momentary LUFS
    pub momentary: f32,
    /// Short-term LUFS
    pub short_term: f32,
    /// Integrated LUFS
    pub integrated: f32,
    /// Loudness range (LU)
    pub range: f32,
    /// True peak L
    pub true_peak_l: f32,
    /// True peak R
    pub true_peak_r: f32,
    /// Peak sample L
    pub peak_l: f32,
    /// Peak sample R
    pub peak_r: f32,
    /// Crest factor
    pub crest: f32,
    /// Dynamic range
    pub dynamic_range: f32,
}

/// Complete analysis data package
#[derive(Clone)]
pub struct AnalysisData {
    pub track_id: u32,
    pub spectrum: SpectrumData,
    pub stereo: StereoMeterData,
    pub loudness: LoudnessData,
    /// EQ curve magnitude response (256 points)
    pub eq_curve: [f32; 256],
    /// Dynamic EQ gain reduction per band (64 bands)
    pub dynamic_gr: [f32; 64],
    /// Timestamp (sample position)
    pub timestamp: u64,
}

impl Default for AnalysisData {
    fn default() -> Self {
        Self {
            track_id: 0,
            spectrum: SpectrumData::default(),
            stereo: StereoMeterData::default(),
            loudness: LoudnessData::default(),
            eq_curve: [0.0; 256],
            dynamic_gr: [0.0; 64],
            timestamp: 0,
        }
    }
}

// ============================================================================
// EQ BAND STATE (for UI sync)
// ============================================================================

/// Complete band state for UI synchronization
#[derive(Clone, Copy, Debug)]
pub struct EqBandState {
    pub enabled: bool,
    pub solo: bool,
    pub freq: f64,
    pub gain_db: f64,
    pub q: f64,
    pub filter_type: FilterType,
    pub slope: FilterSlope,
    pub stereo: StereoPlacement,
    // Dynamic EQ
    pub dynamic_enabled: bool,
    pub threshold_db: f64,
    pub ratio: f64,
    pub attack_ms: f64,
    pub release_ms: f64,
    pub range_db: f64,
    // Current state
    pub gain_reduction: f64,
}

impl Default for EqBandState {
    fn default() -> Self {
        Self {
            enabled: false,
            solo: false,
            freq: 1000.0,
            gain_db: 0.0,
            q: 1.0,
            filter_type: FilterType::Bell,
            slope: FilterSlope::Db12,
            stereo: StereoPlacement::Stereo,
            dynamic_enabled: false,
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            range_db: 24.0,
            gain_reduction: 0.0,
        }
    }
}

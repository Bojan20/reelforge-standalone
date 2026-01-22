//! rf-engine: Audio Graph and Routing Engine
//!
//! Provides professional audio routing with:
//! - Parallel graph processing (rayon)
//! - Insert/send effect routing
//! - Sidechain support
//! - Dual-path processing (realtime + guard)
//! - Delay compensation
//! - Lock-free communication

// Audio engine uses explicit indexing for SIMD optimization
#![allow(clippy::needless_range_loop)]
// Complex routing types are intentional
#![allow(clippy::type_complexity)]
// Too many arguments is common in audio processing functions
#![allow(clippy::too_many_arguments)]

// Core modules
mod bus;
mod graph;
mod mixer;
mod node;
mod processor;
mod realtime;

// Phase 2: Enhanced engine
mod click;
mod dual_path;
mod freeze;
pub mod groups;
mod insert_chain;
mod parallel_graph;
mod pdc;
mod send_return;
mod sidechain;

// Phase 3: Advanced features
mod anticipatory;
mod fx_container;

// Phase 4: Timeline & Track Management
pub mod audio_import;
pub mod ffi;
pub mod ffi_routing;
pub mod ffi_control_room;
pub mod playback;
pub mod track_manager;
pub mod waveform;

// Phase 5: Dynamic Routing System
pub mod routing;

// Phase 9: Control Room
pub mod control_room;

// Phase 6: DAW Integration
pub mod link;

// Phase 7: DSP Wrappers
pub mod dsp_wrappers;

// Phase 8: Automation Engine
pub mod automation;
pub mod param_smoother;

// Phase 10: Recording
pub mod recording_manager;

// Phase 11: Input Bus System
pub mod input_bus;

// Phase 12: Audio Export
pub mod export;

// Phase 13: Disk Streaming System
pub mod streaming;

// Phase 14: Wave Cache (Multi-Resolution Waveform Caching)
pub mod wave_cache;

// Phase 15: Stage Audio Integration
pub mod stage_audio;

// Phase 16: Middleware Integration
pub mod middleware_integration;

// Phase 17: Container System (Wwise/FMOD-style)
pub mod containers;

// Audio Preview Engine (dedicated one-shot playback for Slot Lab, audio browser, etc.)
pub mod preview;

// Re-exports: Core
pub use bus::*;
pub use graph::*;
pub use mixer::*;
pub use node::*;
pub use processor::*;
pub use realtime::*;

// Re-exports: Phase 2
pub use parallel_graph::{BufferPool, Connection, ConnectionType, ParallelAudioGraph};

pub use insert_chain::{
    InsertChain, InsertPosition, InsertProcessor, InsertSlot, MAX_INSERT_SLOTS,
};

pub use send_return::{
    MAX_RETURNS, MAX_SENDS, ReturnBus, ReturnBusManager, Send, SendBank, SendTapPoint,
};

pub use dual_path::{
    AudioBlock, AudioBlockPool, DualPathEngine, DualPathStats, FnGuardProcessor, GuardProcessor,
    ProcessingMode, MAX_BLOCK_SIZE,
};

pub use sidechain::{
    SidechainFilterMode, SidechainId, SidechainInput, SidechainRoute, SidechainRouter,
    SidechainSource,
};

pub use freeze::{FreezeConfig, FreezeError, FreezeManager, FrozenTrackInfo};

pub use groups::{
    FolderTrack, Group, GroupId, GroupInfo, GroupManager, LinkMode, LinkParameter, VcaFader, VcaId,
    VcaInfo,
};

pub use click::{ClickPattern, ClickSound, ClickTrack, ClickTrackSettings, CountInMode};

pub use pdc::{
    ConnectionType as PdcConnectionType, DEFAULT_CONSTRAIN_THRESHOLD, MAX_PDC_SAMPLES,
    NodeLatencyInfo, NodeType as PdcNodeType, PdcDelayLine, PdcManager, PdcStats, SendPdc,
    SidechainPdc,
};

pub use anticipatory::{
    AnticipatoryScheduler, NodeStats, ProcessingJob, ProcessingResult, SchedulerConfig,
    SchedulerStats,
};

pub use fx_container::{
    BlendMode, ContainerPath, FxContainer, MAX_MACROS, MAX_PARALLEL_PATHS, MacroMapping,
    MacroParameter, MappingCurve, PathId,
};

// Re-exports: Phase 4 - Timeline
pub use track_manager::{
    Clip,
    // Clip FX
    ClipFxChain,
    ClipFxSlot,
    ClipFxSlotId,
    ClipFxType,
    ClipId,
    Crossfade,
    CrossfadeCurve,
    CrossfadeId,
    CrossfadeShape,
    LoopRegion,
    MAX_CLIP_FX_SLOTS,
    Marker,
    MarkerId,
    OutputBus,
    Track,
    TrackId,
    TrackManager,
};

pub use audio_import::{AudioImporter, ImportError, ImportedAudio};

pub use waveform::{
    NUM_LOD_LEVELS, Peak, SAMPLES_PER_PEAK, StereoWaveformPeaks, WaveformCache, WaveformPeaks,
};

pub use playback::{
    AudioCache, BusBuffers, BusState, PlaybackEngine, PlaybackPosition, PlaybackState, TrackMeter,
};

// Re-exports: Phase 5 - Dynamic Routing
pub use routing::{
    Channel, ChannelId, ChannelKind, OutputDestination, RoutingError, RoutingGraph, SendConfig,
    SendTapPoint as RoutingSendTapPoint,
};

// Re-exports: Phase 6 - DAW Integration
pub use link::{LinkBeat, LinkConfig, LinkEvent, LinkHost, LinkSession, LinkState};

// Re-exports: Phase 7 - DSP Wrappers
pub use dsp_wrappers::{
    Api550Wrapper, CompressorWrapper, ExpanderWrapper, GateWrapper,
    Neve1073Wrapper, ProEqWrapper, PultecWrapper, RoomCorrectionWrapper, TruePeakLimiterWrapper,
    UltraEqWrapper, available_processors, create_processor, create_processor_extended,
};

// Re-exports: Phase 8 - Automation
pub use automation::{
    AutomationBlock, AutomationChange, AutomationEngine, AutomationLane, AutomationMode,
    AutomationPoint, CurveType, ParamChange, ParamId, TargetType,
};

// Re-exports: Phase 9 - Control Room
pub use control_room::{
    ControlRoom, CueMix, CueSend, MonitorSource, SoloMode, SpeakerSet, Talkback,
};

// Re-exports: Phase 10 - Recording
pub use recording_manager::RecordingManager;

// Re-exports: Phase 11 - Input Bus System
pub use input_bus::{InputBus, InputBusConfig, InputBusId, InputBusManager, MonitorMode};

// Re-exports: Phase 12 - Audio Export
pub use export::{ExportConfig, ExportEngine, ExportError, ExportFormat};

// Re-exports: Phase 13 - Disk Streaming
pub use streaming::{
    AssetCatalog, AssetInfo, AudioEvent, AudioFormat, AudioRingBuffer,
    ControlCommand, ControlCommandType, ControlQueue, DiskJob, DiskReaderPool,
    EventIndex, StreamRT, StreamState, StreamingEngine, TrackRT,
    DEFAULT_RING_BUFFER_FRAMES, HIGH_WATER_FRAMES, LOW_WATER_FRAMES,
};

// Re-exports: Phase 14 - Wave Cache
pub use wave_cache::{
    WaveCacheManager, WaveCacheBuilder, WaveCacheQuery, WaveCacheError,
    GetCacheResult, BuildProgress, BuildState, TileRequest, TileResponse,
    CachedTile, WfcFile, WfcHeader, MipLevel, TileData,
    build_from_samples, tiles_to_flat_array,
    WFC_MAGIC, WFC_VERSION, NUM_MIP_LEVELS, BASE_TILE_SAMPLES,
};

// Re-exports: Phase 15 - Stage Audio
pub use stage_audio::{StageAudioEngine, StageCue};

// Re-exports: Phase 16 - Middleware Integration
pub use middleware_integration::{
    ActionExecutor, AssetRegistry, AudioAsset, MiddlewareAudioEngine,
};

// Re-exports: Phase 17 - Container System
pub use containers::{
    // Types
    ContainerType, ContainerId, ChildId, Container,
    // Blend
    BlendContainer, BlendChild, BlendCurve, BlendResult,
    // Random
    RandomContainer, RandomChild, RandomMode, RandomResult, RandomVariation,
    // Sequence
    SequenceContainer, SequenceStep, SequenceEndBehavior, SequenceResult, SequenceState,
    // Group (P3C)
    ContainerGroup, GroupChild, GroupChildRef, GroupEvaluationMode, GroupResult,
    // Storage
    ContainerStorage,
};

// Re-exports: Freeze additions
pub use freeze::OfflineRenderer;

// Re-exports: Audio Import additions
pub use audio_import::{AudioFileInfo, SampleRateConverter, WaveformPeaks as ImportWaveformPeaks};

use rf_core::SampleRate;

/// Engine configuration
#[derive(Debug, Clone)]
pub struct EngineConfig {
    pub sample_rate: SampleRate,
    pub block_size: usize,
    pub num_buses: usize,
    pub num_returns: usize,
    pub lookahead_blocks: usize,
    pub processing_mode: ProcessingMode,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            sample_rate: SampleRate::Hz48000,
            block_size: 256,
            num_buses: 6,
            num_returns: 4,
            lookahead_blocks: 8,
            processing_mode: ProcessingMode::Hybrid,
        }
    }
}

impl EngineConfig {
    /// Create config for minimum latency
    pub fn low_latency() -> Self {
        Self {
            sample_rate: SampleRate::Hz48000,
            block_size: 64,
            num_buses: 6,
            num_returns: 2,
            lookahead_blocks: 4,
            processing_mode: ProcessingMode::RealTime,
        }
    }

    /// Create config for maximum quality
    pub fn high_quality() -> Self {
        Self {
            sample_rate: SampleRate::Hz96000,
            block_size: 512,
            num_buses: 6,
            num_returns: 8,
            lookahead_blocks: 16,
            processing_mode: ProcessingMode::Guard,
        }
    }
}

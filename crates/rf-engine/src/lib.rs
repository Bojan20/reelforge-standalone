//! rf-engine: Audio Graph and Routing Engine
//!
//! Provides professional audio routing with:
//! - Parallel graph processing (rayon)
//! - Insert/send effect routing
//! - Sidechain support
//! - Dual-path processing (realtime + guard)
//! - Delay compensation
//! - Lock-free communication

// Core modules
mod graph;
mod node;
mod bus;
mod processor;
mod mixer;
mod realtime;

// Phase 2: Enhanced engine
mod parallel_graph;
mod insert_chain;
mod send_return;
mod dual_path;
mod sidechain;
mod freeze;
mod groups;
mod click;
mod pdc;

// Re-exports: Core
pub use graph::*;
pub use node::*;
pub use bus::*;
pub use processor::*;
pub use mixer::*;
pub use realtime::*;

// Re-exports: Phase 2
pub use parallel_graph::{
    ParallelAudioGraph,
    Connection,
    ConnectionType,
    BufferPool,
};

pub use insert_chain::{
    InsertSlot,
    InsertChain,
    InsertPosition,
    InsertProcessor,
    MAX_INSERT_SLOTS,
};

pub use send_return::{
    Send,
    SendBank,
    SendTapPoint,
    ReturnBus,
    ReturnBusManager,
    MAX_SENDS,
    MAX_RETURNS,
};

pub use dual_path::{
    DualPathEngine,
    DualPathStats,
    ProcessingMode,
    AudioBlock,
    GuardProcessor,
    FnGuardProcessor,
};

pub use sidechain::{
    SidechainSource,
    SidechainFilterMode,
    SidechainInput,
    SidechainRoute,
    SidechainRouter,
    SidechainId,
};

pub use freeze::{
    FreezeStatus,
    FreezeMode,
    FreezeOptions,
    FrozenTrackData,
    FrozenOriginalState,
    TrackFreezer,
    FreezeRenderer,
    FreezeError,
};

pub use groups::{
    Group,
    GroupId,
    VcaFader,
    VcaId,
    FolderTrack,
    GroupManager,
    LinkParameter,
    LinkMode,
};

pub use click::{
    ClickTrack,
    ClickSound,
    ClickPattern,
    CountInMode,
    ClickTrackSettings,
};

pub use pdc::{
    PdcManager,
    PdcDelayLine,
    PdcStats,
    NodeLatencyInfo,
    NodeType as PdcNodeType,
    ConnectionType as PdcConnectionType,
    SidechainPdc,
    SendPdc,
    MAX_PDC_SAMPLES,
    DEFAULT_CONSTRAIN_THRESHOLD,
};

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

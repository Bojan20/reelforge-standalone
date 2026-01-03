//! rf-engine: Audio graph and routing engine
//!
//! Graph-based audio routing with lock-free communication.

mod graph;
mod node;
mod bus;
mod processor;
mod mixer;
mod realtime;

pub use graph::*;
pub use node::*;
pub use bus::*;
pub use processor::*;
pub use mixer::*;
pub use realtime::*;

use rf_core::SampleRate;

/// Engine configuration
#[derive(Debug, Clone)]
pub struct EngineConfig {
    pub sample_rate: SampleRate,
    pub block_size: usize,
    pub num_buses: usize,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            sample_rate: SampleRate::Hz48000,
            block_size: 256,
            num_buses: 6,
        }
    }
}

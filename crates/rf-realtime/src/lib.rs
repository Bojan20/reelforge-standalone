//! # ReelForge Real-Time Engine
//!
//! ULTIMATIVNI real-time audio processing with:
//! - Zero-latency processing pipeline
//! - Lock-free state synchronization
//! - SIMD optimization layer
//! - GPU compute integration
//! - Sample-accurate automation
//! - MassCore++ style processing (Phase 5.3)
//! - Performance benchmarking (Phase 5.3)

pub mod graph;
pub mod pipeline;
pub mod state;
pub mod simd;
pub mod gpu;
pub mod latency;
pub mod integration;
pub mod masscore;
pub mod benchmark;

pub use graph::*;
pub use pipeline::*;
pub use state::*;
pub use simd::*;
pub use gpu::*;
pub use latency::*;
pub use integration::*;
pub use masscore::*;
pub use benchmark::*;

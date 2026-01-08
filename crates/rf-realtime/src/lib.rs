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

#![allow(dead_code)]

pub mod benchmark;
pub mod gpu;
pub mod graph;
pub mod integration;
pub mod latency;
pub mod masscore;
pub mod pipeline;
pub mod simd;
pub mod state;

pub use benchmark::*;
pub use gpu::*;
pub use graph::*;
pub use integration::*;
pub use latency::*;
pub use masscore::*;
pub use pipeline::*;
pub use simd::*;
pub use state::*;

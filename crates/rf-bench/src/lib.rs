//! # rf-bench
//!
//! Performance benchmarks for FluxForge audio engine components.
//!
//! ## Benchmark Categories
//!
//! - **DSP Benchmarks**: Filter processing, dynamics, gain
//! - **SIMD Benchmarks**: Vectorized vs scalar operations
//! - **Buffer Benchmarks**: Memory throughput, copying
//!
//! ## Running Benchmarks
//!
//! ```bash
//! # Run all benchmarks
//! cargo bench -p rf-bench
//!
//! # Run specific benchmark
//! cargo bench -p rf-bench -- dsp
//!
//! # With baseline comparison
//! cargo bench -p rf-bench -- --save-baseline main
//! cargo bench -p rf-bench -- --baseline main
//! ```

pub mod generators;
pub mod utils;

pub use generators::*;
pub use utils::*;

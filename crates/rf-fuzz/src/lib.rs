//! # rf-fuzz
//!
//! FFI fuzzing framework for FluxForge audio engine testing.
//!
//! ## Features
//!
//! - **Random Input Generation**: Generate edge-case and boundary inputs
//! - **Reproducible Fuzzing**: Seed-based deterministic fuzzing
//! - **Crash Detection**: Catch panics and undefined behavior
//! - **Property Testing**: Validate output properties
//! - **CI Integration**: Generate reports for test automation
//!
//! ## Example
//!
//! ```rust,ignore
//! use rf_fuzz::{FuzzConfig, FuzzRunner, FuzzTarget};
//!
//! let config = FuzzConfig::default();
//! let runner = FuzzRunner::new(config);
//!
//! runner.fuzz(|input| {
//!     // Your FFI function under test
//!     unsafe { my_ffi_function(input.as_ptr(), input.len()) }
//! });
//! ```

pub mod config;
pub mod generators;
pub mod harness;
pub mod report;

pub use config::FuzzConfig;
pub use generators::*;
pub use harness::{FuzzRunner, FuzzResult, FuzzTarget};
pub use report::FuzzReport;

use thiserror::Error;

/// Errors that can occur during fuzzing
#[derive(Error, Debug)]
pub enum FuzzError {
    #[error("Fuzzing panic: {0}")]
    Panic(String),

    #[error("Invalid output: {0}")]
    InvalidOutput(String),

    #[error("Timeout after {0}ms")]
    Timeout(u64),

    #[error("Memory error: {0}")]
    MemoryError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, FuzzError>;

/// Quick fuzz test with default settings
pub fn quick_fuzz<F, R>(iterations: usize, target: F) -> FuzzResult
where
    F: Fn(Vec<u8>) -> R + std::panic::RefUnwindSafe,
{
    let config = FuzzConfig::default().with_iterations(iterations);
    let runner = FuzzRunner::new(config);
    runner.fuzz_bytes(target)
}

/// Fuzz test for f64 values
pub fn fuzz_f64<F, R>(iterations: usize, target: F) -> FuzzResult
where
    F: Fn(f64) -> R + std::panic::RefUnwindSafe,
{
    let config = FuzzConfig::default().with_iterations(iterations);
    let runner = FuzzRunner::new(config);
    runner.fuzz_f64(target)
}

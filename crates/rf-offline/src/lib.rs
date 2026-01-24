//! RF-Offline — Offline DSP Processing Pipeline
//!
//! High-performance batch audio processing for:
//! - Bounce/mixdown to various formats
//! - Stem export
//! - Batch effect processing
//! - Time-stretch and pitch-shift
//! - Normalization and limiting
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                    OfflineProcessor                              │
//! │                                                                  │
//! │  ┌─────────┐   ┌─────────────┐   ┌────────────┐   ┌──────────┐ │
//! │  │ Source  │ → │ DSP Chain   │ → │ Normalizer │ → │ Encoder  │ │
//! │  │ Decoder │   │ (effects)   │   │ (LUFS/Peak)│   │ (format) │ │
//! │  └─────────┘   └─────────────┘   └────────────┘   └──────────┘ │
//! │                                                                  │
//! │  ┌─────────────────────────────────────────────────────────────┐│
//! │  │                    Job Queue (rayon)                        ││
//! │  │  [Job1] [Job2] [Job3] ... [JobN] → ThreadPool              ││
//! │  └─────────────────────────────────────────────────────────────┘│
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_offline::{OfflineProcessor, OfflineJob, OutputFormat, NormalizationMode};
//!
//! let processor = OfflineProcessor::new();
//!
//! let job = OfflineJob::new()
//!     .input("/path/to/source.wav")
//!     .output("/path/to/output.wav")
//!     .format(OutputFormat::Wav { bit_depth: 24 })
//!     .normalize(NormalizationMode::Lufs { target: -14.0 })
//!     .build();
//!
//! let result = processor.process(job).await?;
//! ```

mod config;
mod decoder;
mod encoder;
mod error;
mod formats;
mod job;
mod normalize;
mod pipeline;
mod processors;
mod time_stretch;

pub use config::*;
pub use decoder::*;
pub use encoder::*;
pub use error::*;
pub use formats::*;
pub use job::*;
pub use normalize::*;
pub use pipeline::*;
pub use processors::*;
pub use time_stretch::*;

/// Library version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

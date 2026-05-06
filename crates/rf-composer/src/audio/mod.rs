//! Audio production layer — turn `StageAssetMap` into actual files.

mod batch;
mod elevenlabs;
mod generator;
mod local;
mod router;
mod suno;

pub use batch::{
    run_batch, AssetResult, BackendMap, BatchJob, BatchOutput, BatchProgress, ProgressHandle,
    DEFAULT_CONCURRENCY,
};
pub use elevenlabs::ElevenLabsBackend;
pub use generator::{
    sanitize_filename, AudioBackendId, AudioError, AudioGenerator, AudioKind, AudioOutput,
    AudioPrompt, AudioResult,
};
pub use local::LocalBackend;
pub use router::{classify, AudioRoutingTable};
pub use suno::SunoBackend;

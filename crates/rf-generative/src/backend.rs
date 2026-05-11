//! Backend trait + canonical error type.

use crate::{GenerationRequest, GenerationResponse};
use thiserror::Error;

/// The single entry point every generative backend exposes.
///
/// ## Threading
///
/// Implementations MUST be `Send + Sync`. Callers wrap them in `Arc` and call
/// `generate` from a worker thread (Tokio blocking task, std `thread::spawn`,
/// or an isolate on the Dart side). **Never** call `generate` on the audio
/// thread — model inference allocates and can take seconds.
///
/// ## Determinism contract
///
/// If `request.seed` is `Some(_)`, the same `(request)` MUST produce the
/// same `response.pcm` byte-for-byte across runs and across machines of the
/// same architecture. This is critical for:
/// - reproducible compliance audits (UKGC needs the same audio twice),
/// - A/B testing (you compare gains, not different random rolls).
pub trait GenerativeBackend: Send + Sync {
    /// Human-readable backend identifier, e.g. `"mock"`, `"tract-sam-small"`.
    fn id(&self) -> &str;

    /// Run inference. Blocking. Caller offloads to a worker.
    fn generate(&self, request: &GenerationRequest) -> Result<GenerationResponse, GenError>;

    /// Best-effort capability advertisement so the UI can hide unsupported
    /// controls. Default = "supports everything"; override as needed.
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities::default()
    }
}

/// What the backend can do. Used by the UI to grey out unsupported sliders
/// instead of failing at submit time.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BackendCapabilities {
    /// `request.seed` is honored deterministically.
    pub deterministic: bool,
    /// `request.style.emotional_arc` is honored (vs ignored).
    pub honors_emotional_arc: bool,
    /// `request.style.stage_hint` is honored (vs ignored).
    pub honors_stage_hint: bool,
    /// Stereo output supported. If `false`, callers will receive mono PCM
    /// and must upmix if they need stereo.
    pub stereo: bool,
    /// Maximum total duration in seconds the backend will accept.
    pub max_duration_seconds: f32,
}

impl Default for BackendCapabilities {
    fn default() -> Self {
        Self {
            deterministic: true,
            honors_emotional_arc: true,
            honors_stage_hint: true,
            stereo: true,
            max_duration_seconds: crate::MAX_DURATION_SECONDS,
        }
    }
}

/// Errors a backend can surface. Distinct variants because the UI shows
/// different recovery hints per case ("retry", "check model file", etc.).
#[derive(Debug, Error)]
pub enum GenError {
    #[error("invalid request: {0}")]
    InvalidRequest(String),

    #[error("model file not found at {path:?}")]
    ModelNotFound { path: String },

    #[error("model file is malformed or unsupported: {0}")]
    MalformedModel(String),

    #[error("inference failed: {0}")]
    Inference(String),

    #[error("backend does not support this capability: {0}")]
    Unsupported(String),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

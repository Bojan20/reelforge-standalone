//! rf-generative — On-device generative audio inference (FAZA 5.1)
//!
//! ## Scope
//!
//! This crate is the **execution layer** for generative audio inside FluxForge.
//! It is intentionally separate from `rf-ai-gen` (which is the *translation*
//! layer: text → `AudioDescriptor` → backend spec). `rf-generative` owns the
//! native inference runtime — load a model file, push a tensor in, get a
//! mono/stereo PCM buffer out.
//!
//! ## Architecture
//!
//! ```text
//! [GenerationRequest]
//!         │
//!         ▼
//!   GenerativeBackend (trait)
//!    ├── MockBackend       — deterministic, no deps, used in tests & previews
//!    └── OnnxBackend       — tract runtime, real models (feature = "onnx")
//!         │
//!         ▼
//! [GenerationResponse { pcm, sample_rate, channels, latency_ms, .. }]
//! ```
//!
//! ## Why a separate crate
//!
//! 1. **Build cost.** ONNX (`tract`) is heavy. Behind `feature = "onnx"` so
//!    most workspace builds stay fast.
//! 2. **Audio-thread safety.** `rf-generative` is *not* real-time. It is
//!    explicitly off-thread; callers must offload to a worker. The crate's
//!    public types are `Send + Sync` so this is easy to enforce.
//! 3. **Replaceability.** Today: tract + Stable Audio Open Small. Tomorrow:
//!    a remote/cloud backend or a different model. Same trait, swap one
//!    `Box<dyn GenerativeBackend>`.
//! 4. **Test isolation.** `MockBackend` lets the FAZA 5.x UI work be built
//!    and tested before any real model ships.
//!
//! ## Status (Sprint 18)
//!
//! - 5.1.1 ✅ crate skeleton, trait, `MockBackend`, deterministic PCM, tests
//! - 5.1.2 ⏳ tract ONNX runtime + Stable Audio Open Small loader
//! - 5.1.3 ⏳ `sam_ffi.rs` C ABI for Dart
//! - 5.1.8 ⏳ compliance validator pass on generated buffers

pub mod backend;
pub mod request;
pub mod response;
pub mod mock;

#[cfg(feature = "onnx")]
pub mod onnx;

pub use backend::{GenerativeBackend, GenError};
pub use mock::MockBackend;
pub use request::{
    EmotionalArc, EmotionalArcPoint, GenerationRequest, GenerationStyle,
    SlotStageHint,
};
pub use response::{GenerationResponse, ProvenanceTag};

/// Canonical native sample rate for FAZA 5.1 inference. Slot SFX uniformly
/// land at 48 kHz inside the engine; resamplers (`rf-r8brain`) convert if a
/// model emits 44.1 kHz natively.
pub const NATIVE_SAMPLE_RATE: u32 = 48_000;

/// Maximum generation duration FAZA 5 will accept in a single request, in
/// seconds. Caps the worst-case buffer at 48k × 2 × f32 × 60s ≈ 23 MB and
/// keeps inference time bounded.
pub const MAX_DURATION_SECONDS: f32 = 60.0;

/// Minimum generation duration. Anything below this is almost certainly a
/// user error (zero / NaN / sign flip).
pub const MIN_DURATION_SECONDS: f32 = 0.05;

//! rf-ai-gen — Procedural AI Audio Generation Engine (T8.1–T8.4)
//!
//! ## Architecture
//!
//! ```text
//! [Text Prompt] → PromptParser → [AudioDescriptor]
//!                                      ↓
//!                              GenerationPipeline
//!                               /         \
//!                   [LocalBackend]    [CloudBackend]
//!                  (AudioCraft IPC)   (ElevenLabs/etc)
//!                               \         /
//!                            [GeneratedAsset]
//!                                      ↓
//!                          PostProcessingPipeline
//!                          (loudness, fade, format)
//!                                      ↓
//!                            FfncClassifier
//!                          [FFNC Category + Tags]
//! ```
//!
//! This crate is the "translation layer" and domain-knowledge engine.
//! The actual audio synthesis (AudioCraft, ElevenLabs, OpenAI) is plugged in
//! via backend adapters — FluxForge handles all slot-domain-specific logic.
//!
//! ## T8.1 — Text Prompt → Audio Spec
//! Rule-based NLP that extracts audio parameters from free-text descriptions.
//! No external AI model required — pure domain knowledge.
//!
//! ## T8.2 — Backend Adapters
//! Structured generation request formatters for:
//! - AudioCraft (local, via subprocess IPC)
//! - ElevenLabs Sound Effects API
//! - Stability AI Audio API
//! - Stub backend (for testing)
//!
//! ## T8.3 — Post-Processing Pipeline
//! Loudness normalization (EBU R128), fade-in/out, format conversion specs.
//!
//! ## T8.4 — FFNC Auto-Categorization
//! Assigns generated assets to the correct FluxForge Neural Category based
//! on the original prompt and audio analysis metadata.

pub mod prompt;
pub mod generation;
pub mod postprocess;
pub mod classify;

pub use prompt::{AudioDescriptor, PromptParser, AudioMood, AudioStyle, InstrumentHint};
pub use generation::{
    GenerationSpec, GenerationBackend, BackendRequest,
    GenerationPipeline, GenerationResult, GenerationStatus,
};
pub use postprocess::{PostProcessingConfig, LoudnessTarget, FadeConfig, FormatSpec};
pub use classify::{FfncCategory, FfncClassifier, ClassificationResult, AudioAnalysisMetadata};

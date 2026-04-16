//! rf-slot-spatial — Slot Audio 3D Spatial Engine (T7.2–T7.4)
//!
//! ## Features
//!
//! ### T7.2 — 3D Scene Editor
//! Define 3D positions for every slot audio event.
//! VR-ready: azimuth, elevation, distance for each source.
//! Predefined slot layout presets (Desktop, VR Standing, Overhead).
//!
//! ### T7.3 — HRTF-based Spatialization
//! Binaural rendering config for headphone playback.
//! ITD/ILD model parameters exposed per-source.
//! Integrates with rf-spatial binaural engine.
//!
//! ### T7.4 — Ambisonics Export
//! Export slot audio positions as B-format Ambisonics metadata.
//! Supports First, Second, Third order (4/9/16 channels).

pub mod scene;
pub mod layout;
pub mod spatial_export;

pub use scene::{
    SpatialSlotScene, SpatialAudioSource, SphericalPosition,
    AttenuationCurve, HrtfConfig, ListenerConfig,
};
pub use layout::{SlotLayoutPreset, SlotAudioZone, layout_for_preset};
pub use spatial_export::{
    AmbisonicsExportConfig, AmbisonicOrder, SpatialExportFormat,
    SpatialExportResult, SpatialExportManifest,
};

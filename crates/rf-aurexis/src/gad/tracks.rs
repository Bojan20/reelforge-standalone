//! GAD Track Types — 8 specialized track types with metadata.
//!
//! Each track type carries per-track metadata for AUREXIS integration:
//! CanonicalEventBinding, SpectralRole, EmotionalBias, EnergyWeight, etc.

use serde::{Deserialize, Serialize};
use crate::spectral::SpectralRole;
use crate::priority::EventType;

/// 8 track types per MASTER_SPEC §15.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum GadTrackType {
    /// Background music layers — loops, adaptive stems.
    MusicLayer,
    /// Short transient hits — reels, buttons, feedback.
    Transient,
    /// Audio bound to specific reel positions/timings.
    ReelBound,
    /// Cascade/tumble layers — sequential audio chains.
    CascadeLayer,
    /// Jackpot progression — escalating ladder audio.
    JackpotLadder,
    /// UI feedback — buttons, navigation, notifications.
    Ui,
    /// System events — session start/end, errors.
    System,
    /// Ambient pads — background atmosphere, casino ambience.
    AmbientPad,
}

impl GadTrackType {
    /// Default spectral role for this track type.
    pub fn default_spectral_role(&self) -> SpectralRole {
        match self {
            Self::MusicLayer => SpectralRole::BackgroundPad,
            Self::Transient => SpectralRole::HighTransient,
            Self::ReelBound => SpectralRole::MidCore,
            Self::CascadeLayer => SpectralRole::FullSpectrum,
            Self::JackpotLadder => SpectralRole::MelodicTopline,
            Self::Ui => SpectralRole::HighTransient,
            Self::System => SpectralRole::NoiseImpact,
            Self::AmbientPad => SpectralRole::BackgroundPad,
        }
    }

    /// Default DPM event type for this track type.
    pub fn default_event_type(&self) -> EventType {
        match self {
            Self::MusicLayer => EventType::Background,
            Self::Transient => EventType::ReelStop,
            Self::ReelBound => EventType::ReelStop,
            Self::CascadeLayer => EventType::CascadeStep,
            Self::JackpotLadder => EventType::JackpotGrand,
            Self::Ui => EventType::Ui,
            Self::System => EventType::System,
            Self::AmbientPad => EventType::Background,
        }
    }

    /// Default energy weight for this track type.
    pub fn default_energy_weight(&self) -> f64 {
        match self {
            Self::MusicLayer => 0.3,
            Self::Transient => 0.6,
            Self::ReelBound => 0.5,
            Self::CascadeLayer => 0.7,
            Self::JackpotLadder => 1.0,
            Self::Ui => 0.2,
            Self::System => 0.1,
            Self::AmbientPad => 0.15,
        }
    }

    /// Display name.
    pub fn label(&self) -> &'static str {
        match self {
            Self::MusicLayer => "Music Layer",
            Self::Transient => "Transient",
            Self::ReelBound => "Reel-Bound",
            Self::CascadeLayer => "Cascade Layer",
            Self::JackpotLadder => "Jackpot Ladder",
            Self::Ui => "UI",
            Self::System => "System",
            Self::AmbientPad => "Ambient/Pad",
        }
    }

    /// All track types.
    pub fn all() -> &'static [GadTrackType] {
        &[
            Self::MusicLayer, Self::Transient, Self::ReelBound,
            Self::CascadeLayer, Self::JackpotLadder, Self::Ui,
            Self::System, Self::AmbientPad,
        ]
    }
}

/// Canonical event binding — which game event this track triggers on.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CanonicalEventBinding {
    /// Hook name (e.g., "SPIN_START", "REEL_STOP_3").
    pub hook: String,
    /// Substate context (e.g., "base", "freespin").
    pub substate: String,
    /// Whether this binding is required for BAKE validation.
    pub required: bool,
}

/// Voice priority class for DPM integration.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VoicePriorityClass {
    /// Never suppressed.
    Critical,
    /// High priority, only suppressed by Critical.
    High,
    /// Standard priority.
    Normal,
    /// Can be suppressed freely.
    Low,
    /// Background — ducked but never fully suppressed.
    Background,
}

impl VoicePriorityClass {
    pub fn weight(&self) -> f64 {
        match self {
            Self::Critical => 1.0,
            Self::High => 0.85,
            Self::Normal => 0.6,
            Self::Low => 0.4,
            Self::Background => 0.2,
        }
    }
}

/// Per-track metadata for AUREXIS integration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackMetadata {
    /// Canonical event binding (which hook triggers this).
    pub event_binding: Option<CanonicalEventBinding>,
    /// Spectral role assignment.
    pub spectral_role: SpectralRole,
    /// Emotional bias: -1.0 (tension) to 1.0 (euphoria).
    pub emotional_bias: f64,
    /// Energy weight: 0.0 (no contribution) to 1.0 (full).
    pub energy_weight: f64,
    /// Base weight for DPM priority.
    pub dpm_base_weight: f64,
    /// Voice priority class.
    pub voice_priority: VoicePriorityClass,
    /// Harmonic density contribution: 0 (silence) to 4 (dense).
    pub harmonic_density: u32,
    /// Turbo mode reduction factor: 0.0 (full reduction) to 1.0 (no reduction).
    pub turbo_reduction_factor: f64,
    /// Mobile optimization flag — if true, this track may be reduced on mobile.
    pub mobile_optimized: bool,
}

impl TrackMetadata {
    /// Create metadata with defaults for the given track type.
    pub fn for_track_type(track_type: GadTrackType) -> Self {
        Self {
            event_binding: None,
            spectral_role: track_type.default_spectral_role(),
            emotional_bias: 0.0,
            energy_weight: track_type.default_energy_weight(),
            dpm_base_weight: track_type.default_event_type().base_weight(),
            voice_priority: match track_type {
                GadTrackType::JackpotLadder => VoicePriorityClass::Critical,
                GadTrackType::MusicLayer | GadTrackType::AmbientPad => VoicePriorityClass::Background,
                GadTrackType::Transient | GadTrackType::ReelBound => VoicePriorityClass::Normal,
                GadTrackType::CascadeLayer => VoicePriorityClass::High,
                GadTrackType::Ui | GadTrackType::System => VoicePriorityClass::Low,
            },
            harmonic_density: match track_type {
                GadTrackType::MusicLayer => 3,
                GadTrackType::JackpotLadder | GadTrackType::CascadeLayer => 2,
                _ => 1,
            },
            turbo_reduction_factor: match track_type {
                GadTrackType::AmbientPad | GadTrackType::System => 0.3,
                GadTrackType::Ui => 0.5,
                _ => 1.0,
            },
            mobile_optimized: matches!(track_type,
                GadTrackType::AmbientPad | GadTrackType::System),
        }
    }

    /// Validate metadata constraints.
    pub fn validate(&self) -> Vec<String> {
        let mut errors = Vec::new();
        if self.emotional_bias < -1.0 || self.emotional_bias > 1.0 {
            errors.push(format!("emotional_bias {} out of range [-1, 1]", self.emotional_bias));
        }
        if self.energy_weight < 0.0 || self.energy_weight > 1.0 {
            errors.push(format!("energy_weight {} out of range [0, 1]", self.energy_weight));
        }
        if self.dpm_base_weight < 0.0 || self.dpm_base_weight > 1.0 {
            errors.push(format!("dpm_base_weight {} out of range [0, 1]", self.dpm_base_weight));
        }
        if self.harmonic_density > 4 {
            errors.push(format!("harmonic_density {} exceeds max 4", self.harmonic_density));
        }
        if self.turbo_reduction_factor < 0.0 || self.turbo_reduction_factor > 1.0 {
            errors.push(format!("turbo_reduction_factor {} out of range [0, 1]", self.turbo_reduction_factor));
        }
        errors
    }
}

/// Track state.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TrackState {
    Active,
    Muted,
    Solo,
    Disabled,
}

/// A single GAD track.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GadTrack {
    pub id: String,
    pub name: String,
    pub track_type: GadTrackType,
    pub metadata: TrackMetadata,
    pub state: TrackState,
    /// Audio file path (if assigned).
    pub audio_path: Option<String>,
    /// Color for UI display (ARGB).
    pub color: u32,
    /// Order index in track list.
    pub order: u32,
}

impl GadTrack {
    /// Create a new track with defaults for the given type.
    pub fn new(id: impl Into<String>, name: impl Into<String>, track_type: GadTrackType) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            track_type,
            metadata: TrackMetadata::for_track_type(track_type),
            state: TrackState::Active,
            audio_path: None,
            color: Self::default_color(track_type),
            order: 0,
        }
    }

    /// Default color per track type.
    fn default_color(tt: GadTrackType) -> u32 {
        match tt {
            GadTrackType::MusicLayer => 0xFF9370DB,
            GadTrackType::Transient => 0xFFFF9040,
            GadTrackType::ReelBound => 0xFF40C8FF,
            GadTrackType::CascadeLayer => 0xFF40FF90,
            GadTrackType::JackpotLadder => 0xFFFFD740,
            GadTrackType::Ui => 0xFF9E9E9E,
            GadTrackType::System => 0xFF607D8B,
            GadTrackType::AmbientPad => 0xFF4DB6AC,
        }
    }

    /// Validate track (metadata + required fields).
    pub fn validate(&self) -> Vec<String> {
        let mut errors = self.metadata.validate();
        if self.name.is_empty() {
            errors.push("Track name is empty".into());
        }
        errors
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_track_types() {
        assert_eq!(GadTrackType::all().len(), 8);
    }

    #[test]
    fn test_track_metadata_defaults() {
        for tt in GadTrackType::all() {
            let meta = TrackMetadata::for_track_type(*tt);
            assert!(meta.validate().is_empty(), "Track type {:?} has invalid defaults", tt);
        }
    }

    #[test]
    fn test_track_creation() {
        let track = GadTrack::new("t1", "My Music", GadTrackType::MusicLayer);
        assert_eq!(track.track_type, GadTrackType::MusicLayer);
        assert_eq!(track.metadata.spectral_role, SpectralRole::BackgroundPad);
        assert_eq!(track.metadata.voice_priority, VoicePriorityClass::Background);
        assert!(track.validate().is_empty());
    }

    #[test]
    fn test_metadata_validation_errors() {
        let mut meta = TrackMetadata::for_track_type(GadTrackType::Transient);
        meta.emotional_bias = 2.0; // out of range
        meta.harmonic_density = 5; // exceeds max
        let errors = meta.validate();
        assert_eq!(errors.len(), 2);
    }

    #[test]
    fn test_voice_priority_weights() {
        assert!(VoicePriorityClass::Critical.weight() > VoicePriorityClass::High.weight());
        assert!(VoicePriorityClass::High.weight() > VoicePriorityClass::Normal.weight());
        assert!(VoicePriorityClass::Normal.weight() > VoicePriorityClass::Low.weight());
        assert!(VoicePriorityClass::Low.weight() > VoicePriorityClass::Background.weight());
    }
}

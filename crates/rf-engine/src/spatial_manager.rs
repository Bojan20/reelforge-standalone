#![allow(clippy::field_reassign_with_default)]
//! SpatialManager — Real-time 3D audio state + render orchestration.
//!
//! Bridges Flutter spatial commands (CortexBridge) to the actual rf-spatial
//! rendering pipeline (BinauralRenderer / AtmosRenderer).
//!
//! ## Architecture
//! ```text
//!  Flutter UI (Dart)
//!      │  SpatialSetPosition / SpatialSetListener / SpatialBinaural
//!      ▼
//!  CortexBridge.handle_spatial()
//!      │  calls SPATIAL_MANAGER.write().set_*()
//!      ▼
//!  SpatialManager  ←──── state: sources, listener, reverb zones
//!      │  SpatialManager::render_binaural() / render_atmos()
//!      ▼
//!  PlaybackEngine output callback (mixes into master stereo bus)
//! ```
//!
//! ## Thread Safety
//! - State mutations (set_source_position etc.) use `RwLock` — called from UI/bridge thread
//! - `render_binaural()` takes `&mut self` — caller must hold the write lock for duration
//! - Audio thread never touches SPATIAL_MANAGER directly; PlaybackEngine polls a
//!   lock-free snapshot (see `SpatialSnapshot`)

#![allow(dead_code)]

use std::collections::HashMap;

use parking_lot::RwLock;
use std::sync::LazyLock;

use rf_spatial::{
    AudioObject, Orientation, Position3D, SpatialRenderer, SpeakerLayout,
    binaural::{BinauralConfig, BinauralRenderer},
    atmos::{AtmosConfig, AtmosRenderer},
};

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL INSTANCE
// ═══════════════════════════════════════════════════════════════════════════

/// Global SpatialManager — created lazily, accessible from FFI and CortexBridge.
pub static SPATIAL_MANAGER: LazyLock<RwLock<SpatialManager>> =
    LazyLock::new(|| RwLock::new(SpatialManager::new(48000)));

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Distance attenuation model.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AttenuationModel {
    /// Linear falloff: gain = clamp(1 - (d - min) / (max - min), 0, 1)
    Linear,
    /// Logarithmic: gain = 1 / (1 + k * (d - min))
    Logarithmic,
    /// Inverse-square law: gain = min² / max(d, min)²
    InverseSquare,
}

impl AttenuationModel {
    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => Self::Logarithmic,
            2 => Self::InverseSquare,
            _ => Self::Linear,
        }
    }

    pub fn gain(&self, distance: f32, min_dist: f32, max_dist: f32) -> f32 {
        let d = distance.max(min_dist);
        match self {
            Self::Linear => {
                if max_dist <= min_dist {
                    return 1.0;
                }
                (1.0 - (d - min_dist) / (max_dist - min_dist)).clamp(0.0, 1.0)
            }
            Self::Logarithmic => {
                let range = (max_dist - min_dist).max(0.001);
                let k = 10.0 / range;
                1.0 / (1.0 + k * (d - min_dist))
            }
            Self::InverseSquare => {
                let r = min_dist.max(0.001);
                (r * r) / (d * d)
            }
        }
    }
}

/// Per-source spatial state.
#[derive(Debug, Clone)]
pub struct SpatialSourceState {
    /// World-space position
    pub position: Position3D,
    /// Linear gain (after attenuation applied)
    pub gain: f32,
    /// Raw gain before attenuation (set by user)
    pub base_gain: f32,
    /// Attenuation model
    pub attenuation_model: AttenuationModel,
    /// Minimum audible distance (full gain)
    pub min_dist: f32,
    /// Maximum audible distance (silence)
    pub max_dist: f32,
    /// Reverb zone ID (None = no reverb)
    pub reverb_zone: Option<u32>,
}

impl Default for SpatialSourceState {
    fn default() -> Self {
        Self {
            position: Position3D::origin(),
            gain: 1.0,
            base_gain: 1.0,
            attenuation_model: AttenuationModel::InverseSquare,
            min_dist: 1.0,
            max_dist: 100.0,
            reverb_zone: None,
        }
    }
}

impl SpatialSourceState {
    /// Compute attenuated gain relative to listener position.
    pub fn compute_gain(&self, listener: &Position3D) -> f32 {
        let dx = self.position.x - listener.x;
        let dy = self.position.y - listener.y;
        let dz = self.position.z - listener.z;
        let distance = (dx * dx + dy * dy + dz * dz).sqrt();
        let att = self.attenuation_model.gain(distance, self.min_dist, self.max_dist);
        (self.base_gain * att).clamp(0.0, 4.0)
    }
}

/// Reverb zone descriptor.
#[derive(Debug, Clone)]
pub struct ReverbZone {
    pub zone_id: u32,
    /// Room size [0..1]
    pub size: f32,
    /// High-freq damping [0..1]
    pub damping: f32,
    /// Wet/dry mix [0..1]
    pub mix: f32,
}

/// Listener state.
#[derive(Debug, Clone)]
pub struct ListenerState {
    pub position: Position3D,
    pub orientation: Orientation,
}

impl Default for ListenerState {
    fn default() -> Self {
        Self {
            position: Position3D::origin(),
            orientation: Orientation::forward(),
        }
    }
}

/// Active rendering mode.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SpatialMode {
    /// Stereo passthrough — no 3D processing
    Stereo,
    /// HRTF binaural (headphone-optimized)
    Binaural,
    /// Dolby Atmos 7.1.4 object-based
    Atmos714,
    /// 5.1 Surround
    Surround51,
}

// ═══════════════════════════════════════════════════════════════════════════
// SPATIAL MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Core 3D audio state + renderer orchestrator.
pub struct SpatialManager {
    /// Current rendering mode
    pub mode: SpatialMode,
    /// Sample rate
    sample_rate: u32,
    /// Per-source states (source_id → state)
    sources: HashMap<u32, SpatialSourceState>,
    /// Listener pose
    pub listener: ListenerState,
    /// Reverb zones
    reverb_zones: HashMap<u32, ReverbZone>,
    /// Active renderer (boxed trait object — swapped on mode change)
    renderer: Box<dyn SpatialRenderer>,
    /// Optional HRTF profile name (for future SOFA file loading)
    hrtf_profile: Option<String>,
    /// Binaural enabled flag (distinct from mode for quick toggle)
    binaural_enabled: bool,
}

impl SpatialManager {
    /// Create with default binaural renderer at the given sample rate.
    pub fn new(sample_rate: u32) -> Self {
        let config = BinauralConfig::default();
        let renderer = Box::new(BinauralRenderer::new(config, sample_rate));
        Self {
            mode: SpatialMode::Binaural,
            sample_rate,
            sources: HashMap::new(),
            listener: ListenerState::default(),
            reverb_zones: HashMap::new(),
            renderer,
            hrtf_profile: None,
            binaural_enabled: false, // off by default until Flutter enables it
        }
    }

    /// Update sample rate (called when engine SR changes).
    pub fn set_sample_rate(&mut self, sr: u32) {
        if self.sample_rate != sr {
            self.sample_rate = sr;
            self.rebuild_renderer();
        }
    }

    // ───────────────────────────────────────────────────────────────────────
    // SOURCE MANAGEMENT
    // ───────────────────────────────────────────────────────────────────────

    /// Set or update a source's 3D position.
    pub fn set_source_position(&mut self, source_id: u32, x: f32, y: f32, z: f32) {
        let state = self.sources.entry(source_id).or_default();
        state.position = Position3D::new(x, y, z);
        // Recompute gain with current listener
        let listener_pos = self.listener.position;
        state.gain = state.compute_gain(&listener_pos);
    }

    /// Set distance attenuation parameters for a source.
    pub fn set_attenuation(&mut self, source_id: u32, model: u8, min_dist: f32, max_dist: f32) {
        let state = self.sources.entry(source_id).or_default();
        state.attenuation_model = AttenuationModel::from_u8(model);
        state.min_dist = min_dist.max(0.001);
        state.max_dist = max_dist.max(min_dist + 0.1);
        let listener_pos = self.listener.position;
        state.gain = state.compute_gain(&listener_pos);
    }

    /// Remove a source (called when audio object is destroyed).
    pub fn remove_source(&mut self, source_id: u32) {
        self.sources.remove(&source_id);
    }

    /// Get attenuated gain for a source (for audio thread pre-gain).
    pub fn source_gain(&self, source_id: u32) -> f32 {
        self.sources.get(&source_id).map(|s| s.gain).unwrap_or(1.0)
    }

    /// Get position for a source (for panning / HRTF lookup).
    pub fn source_position(&self, source_id: u32) -> Option<Position3D> {
        self.sources.get(&source_id).map(|s| s.position)
    }

    // ───────────────────────────────────────────────────────────────────────
    // LISTENER
    // ───────────────────────────────────────────────────────────────────────

    /// Update listener pose.
    pub fn set_listener(&mut self, x: f32, y: f32, z: f32, yaw: f32, pitch: f32) {
        self.listener.position = Position3D::new(x, y, z);
        self.listener.orientation = Orientation::new(yaw, pitch, 0.0);
        self.renderer.set_listener_position(
            self.listener.position,
            self.listener.orientation,
        );
        // Recompute all source attenuations after listener move
        let pos = self.listener.position;
        for state in self.sources.values_mut() {
            state.gain = state.compute_gain(&pos);
        }
    }

    // ───────────────────────────────────────────────────────────────────────
    // MODE CONTROL
    // ───────────────────────────────────────────────────────────────────────

    /// Enable/disable binaural HRTF processing.
    /// Also accepts optional HRTF profile name (reserved for SOFA loading).
    pub fn enable_binaural(&mut self, enabled: bool, hrtf_profile: Option<String>) {
        self.binaural_enabled = enabled;
        if let Some(profile) = hrtf_profile {
            self.hrtf_profile = Some(profile);
        }
        let new_mode = if enabled {
            SpatialMode::Binaural
        } else {
            SpatialMode::Stereo
        };
        if new_mode != self.mode {
            self.mode = new_mode;
            self.rebuild_renderer();
        }
    }

    /// Switch to Atmos 7.1.4 mode with given bed channels + object limit.
    pub fn configure_atmos(&mut self, bed_channels: u8, max_objects: u16) {
        let mut config = AtmosConfig::default();
        config.max_objects = max_objects as usize;
        // bed_channels determines layout
        config.layout = match bed_channels {
            6 => SpeakerLayout::surround_5_1(),
            8 => SpeakerLayout::surround_7_1(),
            12 => SpeakerLayout::atmos_7_1_4(),
            _ => SpeakerLayout::atmos_7_1_4(),
        };
        self.mode = SpatialMode::Atmos714;
        self.renderer = Box::new(AtmosRenderer::new(config, self.sample_rate));
    }

    // ───────────────────────────────────────────────────────────────────────
    // REVERB ZONES
    // ───────────────────────────────────────────────────────────────────────

    /// Register or update a reverb zone.
    pub fn set_reverb_zone(&mut self, zone_id: u32, size: f32, damping: f32, mix: f32) {
        self.reverb_zones.insert(zone_id, ReverbZone {
            zone_id,
            size: size.clamp(0.0, 1.0),
            damping: damping.clamp(0.0, 1.0),
            mix: mix.clamp(0.0, 1.0),
        });
    }

    pub fn remove_reverb_zone(&mut self, zone_id: u32) {
        self.reverb_zones.remove(&zone_id);
    }

    // ───────────────────────────────────────────────────────────────────────
    // RENDERING
    // ───────────────────────────────────────────────────────────────────────

    /// Render a batch of audio objects through the active spatial renderer.
    ///
    /// `output` must be pre-zeroed, length = `frames * output_channels`.
    /// For binaural mode, output_channels = 2.
    /// For Atmos714, output_channels = 12.
    pub fn render(
        &mut self,
        objects: &[AudioObject],
        output: &mut [f32],
        output_channels: usize,
    ) -> Result<(), String> {
        if !self.binaural_enabled && self.mode != SpatialMode::Atmos714 {
            // No spatial processing — caller handles stereo passthrough
            return Ok(());
        }
        self.renderer
            .render(objects, output, output_channels)
            .map_err(|e| format!("{e:?}"))
    }

    /// Build AudioObject for a tracked source with given audio data.
    pub fn make_audio_object(&self, source_id: u32, audio: Vec<f32>) -> AudioObject {
        let state = self.sources.get(&source_id);
        AudioObject {
            id: source_id,
            name: format!("src_{source_id}"),
            position: state.map(|s| s.position).unwrap_or(Position3D::origin()),
            size: 0.0,
            gain: state.map(|s| s.gain).unwrap_or(1.0),
            audio,
            sample_rate: self.sample_rate,
            automation: None,
        }
    }

    /// Is binaural processing currently active?
    pub fn is_binaural_active(&self) -> bool {
        self.binaural_enabled
    }

    /// Get current output channel count for the active mode.
    pub fn output_channels(&self) -> usize {
        match self.mode {
            SpatialMode::Stereo | SpatialMode::Binaural => 2,
            SpatialMode::Surround51 => 6,
            SpatialMode::Atmos714 => 12,
        }
    }

    // ───────────────────────────────────────────────────────────────────────
    // INTERNAL
    // ───────────────────────────────────────────────────────────────────────

    fn rebuild_renderer(&mut self) {
        match self.mode {
            SpatialMode::Binaural | SpatialMode::Stereo => {
                let config = BinauralConfig::default();
                self.renderer = Box::new(BinauralRenderer::new(config, self.sample_rate));
            }
            SpatialMode::Atmos714 => {
                let config = AtmosConfig::default();
                self.renderer = Box::new(AtmosRenderer::new(config, self.sample_rate));
            }
            SpatialMode::Surround51 => {
                // Use Atmos renderer with 5.1 layout
                let mut config = AtmosConfig::default();
                config.layout = SpeakerLayout::surround_5_1();
                self.renderer = Box::new(AtmosRenderer::new(config, self.sample_rate));
            }
        }
        // Reapply listener state to the new renderer
        self.renderer.set_listener_position(
            self.listener.position,
            self.listener.orientation,
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC API — called from ffi.rs or cortex_bridge.rs
// ═══════════════════════════════════════════════════════════════════════════

/// Set source position. Returns true if successful.
pub fn spatial_set_source_position(source_id: u32, x: f32, y: f32, z: f32) -> bool {
    SPATIAL_MANAGER.write().set_source_position(source_id, x, y, z);
    true
}

/// Update listener position + orientation (yaw/pitch in degrees).
pub fn spatial_set_listener(x: f32, y: f32, z: f32, yaw: f32, pitch: f32) -> bool {
    SPATIAL_MANAGER.write().set_listener(x, y, z, yaw, pitch);
    true
}

/// Enable or disable binaural HRTF processing.
/// `hrtf_profile` is optional (null/empty = synthetic default HRTF).
pub fn spatial_enable_binaural(enabled: bool, hrtf_profile: Option<String>) -> bool {
    SPATIAL_MANAGER.write().enable_binaural(enabled, hrtf_profile);
    true
}

/// Set distance attenuation for a source.
/// model: 0=Linear, 1=Logarithmic, 2=InverseSquare
pub fn spatial_set_attenuation(source_id: u32, model: u8, min_dist: f32, max_dist: f32) -> bool {
    SPATIAL_MANAGER.write().set_attenuation(source_id, model, min_dist, max_dist);
    true
}

/// Configure Atmos renderer.
pub fn spatial_configure_atmos(bed_channels: u8, max_objects: u16) -> bool {
    SPATIAL_MANAGER.write().configure_atmos(bed_channels, max_objects);
    true
}

/// Register a reverb zone.
pub fn spatial_set_reverb_zone(zone_id: u32, size: f32, damping: f32, mix: f32) -> bool {
    SPATIAL_MANAGER.write().set_reverb_zone(zone_id, size, damping, mix);
    true
}

/// Remove a source from spatial tracking.
pub fn spatial_remove_source(source_id: u32) -> bool {
    SPATIAL_MANAGER.write().remove_source(source_id);
    true
}

/// Query attenuated gain for a source (for debugging / UI metering).
pub fn spatial_source_gain(source_id: u32) -> f32 {
    SPATIAL_MANAGER.read().source_gain(source_id)
}

/// Is binaural mode currently active?
pub fn spatial_binaural_active() -> bool {
    SPATIAL_MANAGER.read().is_binaural_active()
}

//! Channel Strip Presets
//!
//! Saveable/loadable channel strip configurations including:
//! - EQ settings
//! - Dynamics settings
//! - Insert effects chain
//! - Send configurations
//!
//! Like Cubase's "Load/Save Channel Strip Preset" feature

use serde::{Deserialize, Serialize};

use crate::Decibels;

/// EQ band configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EqBandPreset {
    /// Band enabled
    pub enabled: bool,
    /// Filter type
    pub filter_type: EqFilterType,
    /// Frequency (Hz)
    pub frequency: f64,
    /// Gain (dB) - for bell/shelf
    pub gain: Decibels,
    /// Q factor
    pub q: f64,
}

impl Default for EqBandPreset {
    fn default() -> Self {
        Self {
            enabled: true,
            filter_type: EqFilterType::Bell,
            frequency: 1000.0,
            gain: Decibels::ZERO,
            q: 1.0,
        }
    }
}

/// EQ filter types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EqFilterType {
    /// High-pass filter
    HighPass,
    /// Low-shelf
    LowShelf,
    /// Parametric bell
    Bell,
    /// Notch filter
    Notch,
    /// High-shelf
    HighShelf,
    /// Low-pass filter
    LowPass,
    /// All-pass (phase shift)
    AllPass,
    /// Band-pass
    BandPass,
    /// Tilt EQ
    Tilt,
}

impl Default for EqFilterType {
    fn default() -> Self {
        Self::Bell
    }
}

/// Full EQ preset (up to 8 bands)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EqPreset {
    /// EQ enabled
    pub enabled: bool,
    /// EQ bands
    pub bands: Vec<EqBandPreset>,
    /// Output gain
    pub output_gain: Decibels,
    /// Auto gain compensation
    pub auto_gain: bool,
}

impl Default for EqPreset {
    fn default() -> Self {
        Self {
            enabled: true,
            bands: vec![
                EqBandPreset {
                    filter_type: EqFilterType::HighPass,
                    frequency: 80.0,
                    ..Default::default()
                },
                EqBandPreset {
                    filter_type: EqFilterType::LowShelf,
                    frequency: 200.0,
                    ..Default::default()
                },
                EqBandPreset {
                    filter_type: EqFilterType::Bell,
                    frequency: 500.0,
                    ..Default::default()
                },
                EqBandPreset {
                    filter_type: EqFilterType::Bell,
                    frequency: 2000.0,
                    ..Default::default()
                },
                EqBandPreset {
                    filter_type: EqFilterType::HighShelf,
                    frequency: 8000.0,
                    ..Default::default()
                },
                EqBandPreset {
                    filter_type: EqFilterType::LowPass,
                    frequency: 18000.0,
                    enabled: false,
                    ..Default::default()
                },
            ],
            output_gain: Decibels::ZERO,
            auto_gain: false,
        }
    }
}

/// Compressor/dynamics preset
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressorPreset {
    /// Compressor enabled
    pub enabled: bool,
    /// Threshold (dB)
    pub threshold: Decibels,
    /// Ratio (e.g., 4.0 = 4:1)
    pub ratio: f64,
    /// Attack time (ms)
    pub attack_ms: f64,
    /// Release time (ms)
    pub release_ms: f64,
    /// Knee width (dB)
    pub knee_db: f64,
    /// Makeup gain (dB)
    pub makeup_gain: Decibels,
    /// Auto makeup gain
    pub auto_makeup: bool,
    /// Mix (dry/wet)
    pub mix: f64,
}

impl Default for CompressorPreset {
    fn default() -> Self {
        Self {
            enabled: false,
            threshold: Decibels(-20.0),
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            knee_db: 6.0,
            makeup_gain: Decibels::ZERO,
            auto_makeup: true,
            mix: 1.0,
        }
    }
}

/// Gate/expander preset
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GatePreset {
    /// Gate enabled
    pub enabled: bool,
    /// Threshold (dB)
    pub threshold: Decibels,
    /// Range (dB of attenuation when closed)
    pub range: Decibels,
    /// Attack time (ms)
    pub attack_ms: f64,
    /// Hold time (ms)
    pub hold_ms: f64,
    /// Release time (ms)
    pub release_ms: f64,
    /// Sidechain filter enabled
    pub sidechain_filter: bool,
    /// Sidechain HPF frequency
    pub sidechain_hpf: f64,
    /// Sidechain LPF frequency
    pub sidechain_lpf: f64,
}

impl Default for GatePreset {
    fn default() -> Self {
        Self {
            enabled: false,
            threshold: Decibels(-40.0),
            range: Decibels(-80.0),
            attack_ms: 1.0,
            hold_ms: 50.0,
            release_ms: 100.0,
            sidechain_filter: false,
            sidechain_hpf: 80.0,
            sidechain_lpf: 12000.0,
        }
    }
}

/// Insert effect reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsertPreset {
    /// Plugin identifier (e.g., VST3 class ID)
    pub plugin_id: String,
    /// Plugin name (for display)
    pub plugin_name: String,
    /// Plugin state (opaque binary)
    pub state: Vec<u8>,
    /// Insert is active
    pub active: bool,
}

/// Send preset
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SendPreset {
    /// Destination bus name (resolved at load time)
    pub destination_name: String,
    /// Send level
    pub level: Decibels,
    /// Pre/post fader
    pub pre_fader: bool,
    /// Pan
    pub pan: f64,
    /// Muted
    pub muted: bool,
}

/// Complete channel strip preset
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelStripPreset {
    /// Preset name
    pub name: String,
    /// Category (e.g., "Vocals", "Drums", "Bass")
    pub category: Option<String>,
    /// Description
    pub description: Option<String>,
    /// Author
    pub author: Option<String>,
    /// Created timestamp
    pub created: u64,
    /// Modified timestamp
    pub modified: u64,

    // === Processing Chain ===
    /// Input gain
    pub input_gain: Decibels,
    /// Phase inverted
    pub phase_inverted: bool,

    /// Gate/Expander (first in chain)
    pub gate: GatePreset,

    /// Pre-EQ (before compressor)
    pub pre_eq: Option<EqPreset>,

    /// Compressor
    pub compressor: CompressorPreset,

    /// Post-EQ (after compressor)
    pub post_eq: EqPreset,

    /// Insert effects
    pub inserts: Vec<InsertPreset>,

    /// Sends
    pub sends: Vec<SendPreset>,

    /// Output gain/trim
    pub output_gain: Decibels,

    // === Metadata ===
    /// Tags for search
    pub tags: Vec<String>,
    /// Is factory preset
    pub factory: bool,
}

impl Default for ChannelStripPreset {
    fn default() -> Self {
        Self {
            name: "Default".to_string(),
            category: None,
            description: None,
            author: None,
            created: 0,
            modified: 0,

            input_gain: Decibels::ZERO,
            phase_inverted: false,

            gate: GatePreset::default(),
            pre_eq: None,
            compressor: CompressorPreset::default(),
            post_eq: EqPreset::default(),

            inserts: Vec::new(),
            sends: Vec::new(),

            output_gain: Decibels::ZERO,

            tags: Vec::new(),
            factory: false,
        }
    }
}

impl ChannelStripPreset {
    /// Create new preset with name
    pub fn new(name: impl Into<String>) -> Self {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        Self {
            name: name.into(),
            created: now,
            modified: now,
            ..Default::default()
        }
    }

    /// Create vocal preset
    pub fn vocal() -> Self {
        let mut preset = Self::new("Vocal");
        preset.category = Some("Vocals".to_string());
        preset.tags = vec!["vocal".to_string(), "voice".to_string()];

        // High-pass at 80Hz
        preset.post_eq.bands[0].frequency = 80.0;
        preset.post_eq.bands[0].enabled = true;

        // Presence boost at 3kHz
        preset.post_eq.bands[3].frequency = 3000.0;
        preset.post_eq.bands[3].gain = Decibels(2.0);

        // Air at 12kHz
        preset.post_eq.bands[4].frequency = 12000.0;
        preset.post_eq.bands[4].gain = Decibels(1.5);

        // Light compression
        preset.compressor.enabled = true;
        preset.compressor.threshold = Decibels(-18.0);
        preset.compressor.ratio = 3.0;
        preset.compressor.attack_ms = 15.0;
        preset.compressor.release_ms = 150.0;

        preset
    }

    /// Create drum bus preset
    pub fn drum_bus() -> Self {
        let mut preset = Self::new("Drum Bus");
        preset.category = Some("Drums".to_string());
        preset.tags = vec!["drums".to_string(), "bus".to_string(), "glue".to_string()];

        // Punchy compression
        preset.compressor.enabled = true;
        preset.compressor.threshold = Decibels(-12.0);
        preset.compressor.ratio = 4.0;
        preset.compressor.attack_ms = 30.0;
        preset.compressor.release_ms = 200.0;
        preset.compressor.mix = 0.5; // Parallel

        // Low end thump
        preset.post_eq.bands[1].frequency = 100.0;
        preset.post_eq.bands[1].gain = Decibels(2.0);

        // Snap
        preset.post_eq.bands[3].frequency = 4000.0;
        preset.post_eq.bands[3].gain = Decibels(1.5);

        preset
    }

    /// Create bass preset
    pub fn bass() -> Self {
        let mut preset = Self::new("Bass DI");
        preset.category = Some("Bass".to_string());
        preset.tags = vec!["bass".to_string(), "low end".to_string()];

        // Roll off sub
        preset.post_eq.bands[0].frequency = 40.0;

        // Low body
        preset.post_eq.bands[1].frequency = 80.0;
        preset.post_eq.bands[1].gain = Decibels(1.5);

        // Cut mud
        preset.post_eq.bands[2].frequency = 250.0;
        preset.post_eq.bands[2].gain = Decibels(-2.0);

        // Finger definition
        preset.post_eq.bands[3].frequency = 1200.0;
        preset.post_eq.bands[3].gain = Decibels(1.0);

        // Compress for consistency
        preset.compressor.enabled = true;
        preset.compressor.threshold = Decibels(-15.0);
        preset.compressor.ratio = 5.0;
        preset.compressor.attack_ms = 20.0;
        preset.compressor.release_ms = 100.0;

        preset
    }

    /// Update modified timestamp
    pub fn touch(&mut self) {
        self.modified = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
    }
}

/// Channel strip preset library
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChannelStripLibrary {
    /// User presets
    pub user_presets: Vec<ChannelStripPreset>,
    /// Factory presets (read-only)
    pub factory_presets: Vec<ChannelStripPreset>,
}

impl ChannelStripLibrary {
    /// Create new library with factory presets
    pub fn new() -> Self {
        let mut lib = Self::default();

        // Add factory presets
        let mut vocal = ChannelStripPreset::vocal();
        vocal.factory = true;
        lib.factory_presets.push(vocal);

        let mut drum_bus = ChannelStripPreset::drum_bus();
        drum_bus.factory = true;
        lib.factory_presets.push(drum_bus);

        let mut bass = ChannelStripPreset::bass();
        bass.factory = true;
        lib.factory_presets.push(bass);

        lib
    }

    /// Get all presets (factory + user)
    pub fn all(&self) -> impl Iterator<Item = &ChannelStripPreset> {
        self.factory_presets.iter().chain(self.user_presets.iter())
    }

    /// Find preset by name
    pub fn find(&self, name: &str) -> Option<&ChannelStripPreset> {
        self.all().find(|p| p.name == name)
    }

    /// Find presets by category
    pub fn by_category(&self, category: &str) -> Vec<&ChannelStripPreset> {
        self.all()
            .filter(|p| p.category.as_deref() == Some(category))
            .collect()
    }

    /// Find presets by tag
    pub fn by_tag(&self, tag: &str) -> Vec<&ChannelStripPreset> {
        self.all()
            .filter(|p| p.tags.iter().any(|t| t == tag))
            .collect()
    }

    /// Add user preset
    pub fn add(&mut self, preset: ChannelStripPreset) {
        self.user_presets.push(preset);
    }

    /// Remove user preset by name
    pub fn remove(&mut self, name: &str) -> Option<ChannelStripPreset> {
        if let Some(pos) = self.user_presets.iter().position(|p| p.name == name) {
            Some(self.user_presets.remove(pos))
        } else {
            None
        }
    }

    /// Get all categories
    pub fn categories(&self) -> Vec<String> {
        let mut cats: Vec<_> = self.all().filter_map(|p| p.category.clone()).collect();
        cats.sort();
        cats.dedup();
        cats
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_channel_strip_preset() {
        let preset = ChannelStripPreset::vocal();
        assert_eq!(preset.name, "Vocal");
        assert!(preset.compressor.enabled);
        assert!(preset.post_eq.bands.len() >= 4);
    }

    #[test]
    fn test_library() {
        let lib = ChannelStripLibrary::new();

        assert!(!lib.factory_presets.is_empty());
        assert!(lib.find("Vocal").is_some());
        assert!(!lib.categories().is_empty());
    }
}

//! SAM: Smart Controls
//!
//! 3 control groups (Energy, Clarity, Stability) with 11 total smart controls.
//! Each smart control maps to multiple engine parameters.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §13

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// Smart control group.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SmartControlGroup {
    Energy,
    Clarity,
    Stability,
}

impl SmartControlGroup {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Energy    => "Energy",
            Self::Clarity   => "Clarity",
            Self::Stability => "Stability",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Energy    => "Controls how audio energy responds to game events",
            Self::Clarity   => "Controls mix clarity and spectral characteristics",
            Self::Stability => "Controls fatigue, peak duration, and voice density",
        }
    }
}

/// Individual smart control identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SmartControl {
    // Energy group
    Intensity,
    BuildSpeed,
    PeakAggression,
    Decay,
    // Clarity group
    MixTightness,
    TransientSharpness,
    Width,
    Harmonics,
    // Stability group
    Fatigue,
    PeakDuration,
    VoiceDensity,
}

impl SmartControl {
    pub const COUNT: usize = 11;

    pub fn all() -> &'static [SmartControl; 11] {
        &[
            Self::Intensity, Self::BuildSpeed, Self::PeakAggression, Self::Decay,
            Self::MixTightness, Self::TransientSharpness, Self::Width, Self::Harmonics,
            Self::Fatigue, Self::PeakDuration, Self::VoiceDensity,
        ]
    }

    pub fn from_index(index: u8) -> Option<Self> {
        match index {
            0 => Some(Self::Intensity),
            1 => Some(Self::BuildSpeed),
            2 => Some(Self::PeakAggression),
            3 => Some(Self::Decay),
            4 => Some(Self::MixTightness),
            5 => Some(Self::TransientSharpness),
            6 => Some(Self::Width),
            7 => Some(Self::Harmonics),
            8 => Some(Self::Fatigue),
            9 => Some(Self::PeakDuration),
            10 => Some(Self::VoiceDensity),
            _ => None,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Intensity          => "Intensity",
            Self::BuildSpeed         => "Build Speed",
            Self::PeakAggression     => "Peak Aggression",
            Self::Decay              => "Decay",
            Self::MixTightness       => "Mix Tightness",
            Self::TransientSharpness => "Transient Sharpness",
            Self::Width              => "Width",
            Self::Harmonics          => "Harmonics",
            Self::Fatigue            => "Fatigue",
            Self::PeakDuration       => "Peak Duration",
            Self::VoiceDensity       => "Voice Density",
        }
    }

    pub fn group(&self) -> SmartControlGroup {
        match self {
            Self::Intensity | Self::BuildSpeed | Self::PeakAggression | Self::Decay
                => SmartControlGroup::Energy,
            Self::MixTightness | Self::TransientSharpness | Self::Width | Self::Harmonics
                => SmartControlGroup::Clarity,
            Self::Fatigue | Self::PeakDuration | Self::VoiceDensity
                => SmartControlGroup::Stability,
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Intensity          => "Overall audio energy level in response to game events",
            Self::BuildSpeed         => "How fast energy builds during escalation sequences",
            Self::PeakAggression     => "Maximum peak intensity during big wins/features",
            Self::Decay              => "Rate of energy decay after peak events",
            Self::MixTightness       => "Spectral separation and mix clarity",
            Self::TransientSharpness => "Attack definition and transient preservation",
            Self::Width              => "Stereo field width and spatial spread",
            Self::Harmonics          => "Harmonic richness and overtone presence",
            Self::Fatigue            => "Listener fatigue prevention target",
            Self::PeakDuration       => "Maximum consecutive peak energy frames",
            Self::VoiceDensity       => "Target voice count relative to budget",
        }
    }
}

/// Smart control value (0.0 – 1.0).
#[derive(Debug, Clone, Copy)]
pub struct SmartControlValue {
    pub control: SmartControl,
    pub value: f64,
}

impl SmartControlValue {
    pub fn new(control: SmartControl, value: f64) -> Self {
        Self { control, value: value.clamp(0.0, 1.0) }
    }
}

/// Energy control group values.
#[derive(Debug, Clone, Copy)]
pub struct EnergyControls {
    pub intensity: f64,
    pub build_speed: f64,
    pub peak_aggression: f64,
    pub decay: f64,
}

impl Default for EnergyControls {
    fn default() -> Self {
        Self { intensity: 0.5, build_speed: 0.5, peak_aggression: 0.5, decay: 0.5 }
    }
}

/// Clarity control group values.
#[derive(Debug, Clone, Copy)]
pub struct ClarityControls {
    pub mix_tightness: f64,
    pub transient_sharpness: f64,
    pub width: f64,
    pub harmonics: f64,
}

impl Default for ClarityControls {
    fn default() -> Self {
        Self { mix_tightness: 0.5, transient_sharpness: 0.5, width: 0.5, harmonics: 0.5 }
    }
}

/// Stability control group values.
#[derive(Debug, Clone, Copy)]
pub struct StabilityControls {
    pub fatigue: f64,
    pub peak_duration: f64,
    pub voice_density: f64,
}

impl Default for StabilityControls {
    fn default() -> Self {
        Self { fatigue: 0.5, peak_duration: 0.5, voice_density: 0.5 }
    }
}

/// Complete set of all 11 smart controls.
#[derive(Debug, Clone, Copy)]
pub struct SmartControlSet {
    pub energy: EnergyControls,
    pub clarity: ClarityControls,
    pub stability: StabilityControls,
}

impl SmartControlSet {
    /// Get value by control identifier.
    pub fn get(&self, control: SmartControl) -> f64 {
        match control {
            SmartControl::Intensity          => self.energy.intensity,
            SmartControl::BuildSpeed         => self.energy.build_speed,
            SmartControl::PeakAggression     => self.energy.peak_aggression,
            SmartControl::Decay              => self.energy.decay,
            SmartControl::MixTightness       => self.clarity.mix_tightness,
            SmartControl::TransientSharpness => self.clarity.transient_sharpness,
            SmartControl::Width              => self.clarity.width,
            SmartControl::Harmonics          => self.clarity.harmonics,
            SmartControl::Fatigue            => self.stability.fatigue,
            SmartControl::PeakDuration       => self.stability.peak_duration,
            SmartControl::VoiceDensity       => self.stability.voice_density,
        }
    }

    /// Set value by control identifier.
    pub fn set(&mut self, control: SmartControl, value: f64) {
        let v = value.clamp(0.0, 1.0);
        match control {
            SmartControl::Intensity          => self.energy.intensity = v,
            SmartControl::BuildSpeed         => self.energy.build_speed = v,
            SmartControl::PeakAggression     => self.energy.peak_aggression = v,
            SmartControl::Decay              => self.energy.decay = v,
            SmartControl::MixTightness       => self.clarity.mix_tightness = v,
            SmartControl::TransientSharpness => self.clarity.transient_sharpness = v,
            SmartControl::Width              => self.clarity.width = v,
            SmartControl::Harmonics          => self.clarity.harmonics = v,
            SmartControl::Fatigue            => self.stability.fatigue = v,
            SmartControl::PeakDuration       => self.stability.peak_duration = v,
            SmartControl::VoiceDensity       => self.stability.voice_density = v,
        }
    }

    /// Get all values as array (11 values).
    pub fn to_array(&self) -> [f64; 11] {
        [
            self.energy.intensity, self.energy.build_speed,
            self.energy.peak_aggression, self.energy.decay,
            self.clarity.mix_tightness, self.clarity.transient_sharpness,
            self.clarity.width, self.clarity.harmonics,
            self.stability.fatigue, self.stability.peak_duration,
            self.stability.voice_density,
        ]
    }

    /// Set all values from array (11 values).
    pub fn from_array(values: &[f64; 11]) -> Self {
        Self {
            energy: EnergyControls {
                intensity: values[0].clamp(0.0, 1.0),
                build_speed: values[1].clamp(0.0, 1.0),
                peak_aggression: values[2].clamp(0.0, 1.0),
                decay: values[3].clamp(0.0, 1.0),
            },
            clarity: ClarityControls {
                mix_tightness: values[4].clamp(0.0, 1.0),
                transient_sharpness: values[5].clamp(0.0, 1.0),
                width: values[6].clamp(0.0, 1.0),
                harmonics: values[7].clamp(0.0, 1.0),
            },
            stability: StabilityControls {
                fatigue: values[8].clamp(0.0, 1.0),
                peak_duration: values[9].clamp(0.0, 1.0),
                voice_density: values[10].clamp(0.0, 1.0),
            },
        }
    }
}

impl Default for SmartControlSet {
    fn default() -> Self {
        Self {
            energy: EnergyControls::default(),
            clarity: ClarityControls::default(),
            stability: StabilityControls::default(),
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_controls() {
        assert_eq!(SmartControl::all().len(), 11);
    }

    #[test]
    fn test_control_from_index() {
        for i in 0..11 {
            assert!(SmartControl::from_index(i).is_some());
        }
        assert!(SmartControl::from_index(11).is_none());
    }

    #[test]
    fn test_control_groups() {
        let energy_count = SmartControl::all().iter().filter(|c| c.group() == SmartControlGroup::Energy).count();
        let clarity_count = SmartControl::all().iter().filter(|c| c.group() == SmartControlGroup::Clarity).count();
        let stability_count = SmartControl::all().iter().filter(|c| c.group() == SmartControlGroup::Stability).count();
        assert_eq!(energy_count, 4);
        assert_eq!(clarity_count, 4);
        assert_eq!(stability_count, 3);
    }

    #[test]
    fn test_control_set_get_set() {
        let mut set = SmartControlSet::default();
        set.set(SmartControl::Intensity, 0.8);
        assert!((set.get(SmartControl::Intensity) - 0.8).abs() < 1e-10);
    }

    #[test]
    fn test_control_set_clamp() {
        let mut set = SmartControlSet::default();
        set.set(SmartControl::Width, 1.5);
        assert!((set.get(SmartControl::Width) - 1.0).abs() < 1e-10);
        set.set(SmartControl::Width, -0.5);
        assert!((set.get(SmartControl::Width)).abs() < 1e-10);
    }

    #[test]
    fn test_control_set_roundtrip() {
        let original = SmartControlSet::default();
        let arr = original.to_array();
        let restored = SmartControlSet::from_array(&arr);
        for i in 0..11 {
            let c = SmartControl::from_index(i as u8).unwrap();
            assert!((original.get(c) - restored.get(c)).abs() < 1e-10);
        }
    }
}

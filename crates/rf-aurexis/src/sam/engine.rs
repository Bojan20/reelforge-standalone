//! SAM: Smart Authoring Engine
//!
//! Orchestrates the 9-step guided creation workflow.
//! Maps smart controls to engine parameters.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §13

use super::archetypes::{SlotArchetype, MarketTarget};
use super::controls::{SmartControlSet, SmartControl};

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// 3 authoring modes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthoringMode {
    /// Default mode. 80% of controls hidden. Smart controls only.
    Smart,
    /// Full access to all engine parameters.
    Advanced,
    /// Raw engine state visualization for debugging.
    Debug,
}

impl AuthoringMode {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Smart    => "SMART",
            Self::Advanced => "ADVANCED",
            Self::Debug    => "DEBUG",
        }
    }

    pub fn from_index(index: u8) -> Option<Self> {
        match index {
            0 => Some(Self::Smart),
            1 => Some(Self::Advanced),
            2 => Some(Self::Debug),
            _ => None,
        }
    }
}

/// 9-step guided creation wizard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WizardStep {
    /// Step 1: Choose game archetype
    Archetype,
    /// Step 2: Set volatility level
    Volatility,
    /// Step 3: Select target market
    Market,
    /// Step 4: Import GDD (optional)
    GddImport,
    /// Step 5: Auto-configure from archetype + market + volatility
    AutoConfig,
    /// Step 6: Preview audio behavior
    Preview,
    /// Step 7: Run AIL analysis
    AilPass,
    /// Step 8: Adjust based on AIL recommendations
    Adjust,
    /// Step 9: Bake (requires PBSE + DRC certification)
    Bake,
}

impl WizardStep {
    pub const COUNT: usize = 9;

    pub fn all() -> &'static [WizardStep; 9] {
        &[
            Self::Archetype, Self::Volatility, Self::Market,
            Self::GddImport, Self::AutoConfig, Self::Preview,
            Self::AilPass, Self::Adjust, Self::Bake,
        ]
    }

    pub fn from_index(index: u8) -> Option<Self> {
        match index {
            0 => Some(Self::Archetype),
            1 => Some(Self::Volatility),
            2 => Some(Self::Market),
            3 => Some(Self::GddImport),
            4 => Some(Self::AutoConfig),
            5 => Some(Self::Preview),
            6 => Some(Self::AilPass),
            7 => Some(Self::Adjust),
            8 => Some(Self::Bake),
            _ => None,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Archetype  => "Archetype",
            Self::Volatility => "Volatility",
            Self::Market     => "Market",
            Self::GddImport  => "GDD Import",
            Self::AutoConfig => "Auto-Config",
            Self::Preview    => "Preview",
            Self::AilPass    => "AIL Pass",
            Self::Adjust     => "Adjust",
            Self::Bake       => "Bake",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Archetype  => "Choose game archetype (Classic, Hold&Win, Cascade, etc.)",
            Self::Volatility => "Set game volatility level within archetype range",
            Self::Market     => "Select target market (Casual, Standard, Premium)",
            Self::GddImport  => "Import Game Design Document for auto-detection (optional)",
            Self::AutoConfig => "Auto-configure engine parameters from archetype + market + volatility",
            Self::Preview    => "Preview audio behavior with test scenarios",
            Self::AilPass    => "Run AIL analysis for quality and safety review",
            Self::Adjust     => "Adjust parameters based on AIL recommendations",
            Self::Bake       => "Run PBSE + DRC certification and generate final build",
        }
    }

    pub fn index(&self) -> u8 {
        *self as u8
    }

    pub fn next(&self) -> Option<Self> {
        Self::from_index(self.index() + 1)
    }

    pub fn prev(&self) -> Option<Self> {
        if self.index() == 0 { return None; }
        Self::from_index(self.index() - 1)
    }
}

/// Engine parameter that smart controls map to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EngineParameter {
    EnergyIntensityMultiplier,
    EscalationRate,
    DecayHalfLife,
    PeakEnergyMultiplier,
    VoiceBudgetScale,
    SpectralBandwidth,
    TransientAttack,
    StereoWidth,
    HarmonicExcitation,
    FatigueThreshold,
    PeakDurationLimit,
    SciTarget,
}

impl EngineParameter {
    pub fn name(&self) -> &'static str {
        match self {
            Self::EnergyIntensityMultiplier => "energy_intensity_multiplier",
            Self::EscalationRate            => "escalation_rate",
            Self::DecayHalfLife             => "decay_half_life",
            Self::PeakEnergyMultiplier      => "peak_energy_multiplier",
            Self::VoiceBudgetScale          => "voice_budget_scale",
            Self::SpectralBandwidth         => "spectral_bandwidth",
            Self::TransientAttack           => "transient_attack",
            Self::StereoWidth               => "stereo_width",
            Self::HarmonicExcitation        => "harmonic_excitation",
            Self::FatigueThreshold          => "fatigue_threshold",
            Self::PeakDurationLimit         => "peak_duration_limit",
            Self::SciTarget                 => "sci_target",
        }
    }
}

/// Mapping from a smart control to engine parameters.
#[derive(Debug, Clone)]
pub struct ParameterMapping {
    pub control: SmartControl,
    pub targets: Vec<(EngineParameter, f64, f64)>, // (param, min_value, max_value)
}

/// Smart authoring state.
#[derive(Debug, Clone)]
pub struct SmartAuthoringState {
    pub mode: AuthoringMode,
    pub wizard_step: WizardStep,
    pub archetype: Option<SlotArchetype>,
    pub volatility: f64,
    pub market: MarketTarget,
    pub controls: SmartControlSet,
    pub gdd_imported: bool,
    pub auto_configured: bool,
    pub ail_passed: bool,
    pub ail_score: f64,
    pub certified: bool,
}

impl Default for SmartAuthoringState {
    fn default() -> Self {
        Self {
            mode: AuthoringMode::Smart,
            wizard_step: WizardStep::Archetype,
            archetype: None,
            volatility: 0.5,
            market: MarketTarget::Standard,
            controls: SmartControlSet::default(),
            gdd_imported: false,
            auto_configured: false,
            ail_passed: false,
            ail_score: 0.0,
            certified: false,
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// SMART AUTHORING ENGINE
// ═════════════════════════════════════════════════════════════════════════════

/// Smart Authoring Engine.
///
/// Manages the 9-step wizard, mode switching, archetype application,
/// and smart control → engine parameter mapping.
pub struct SmartAuthoringEngine {
    state: SmartAuthoringState,
    mappings: Vec<ParameterMapping>,
}

impl SmartAuthoringEngine {
    pub fn new() -> Self {
        Self {
            state: SmartAuthoringState::default(),
            mappings: Self::build_mappings(),
        }
    }

    pub fn state(&self) -> &SmartAuthoringState {
        &self.state
    }

    pub fn mode(&self) -> AuthoringMode {
        self.state.mode
    }

    pub fn wizard_step(&self) -> WizardStep {
        self.state.wizard_step
    }

    pub fn archetype(&self) -> Option<SlotArchetype> {
        self.state.archetype
    }

    pub fn controls(&self) -> &SmartControlSet {
        &self.state.controls
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODE CONTROL
    // ═══════════════════════════════════════════════════════════════════════

    pub fn set_mode(&mut self, mode: AuthoringMode) {
        self.state.mode = mode;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WIZARD NAVIGATION
    // ═══════════════════════════════════════════════════════════════════════

    pub fn set_wizard_step(&mut self, step: WizardStep) {
        self.state.wizard_step = step;
    }

    pub fn wizard_next(&mut self) -> bool {
        if let Some(next) = self.state.wizard_step.next() {
            self.state.wizard_step = next;
            true
        } else {
            false
        }
    }

    pub fn wizard_prev(&mut self) -> bool {
        if let Some(prev) = self.state.wizard_step.prev() {
            self.state.wizard_step = prev;
            true
        } else {
            false
        }
    }

    pub fn wizard_progress(&self) -> f64 {
        (self.state.wizard_step.index() as f64 + 1.0) / WizardStep::COUNT as f64
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ARCHETYPE & CONFIG
    // ═══════════════════════════════════════════════════════════════════════

    /// Select archetype and apply its defaults.
    pub fn select_archetype(&mut self, archetype: SlotArchetype) {
        self.state.archetype = Some(archetype);
        let defaults = archetype.defaults();
        self.state.volatility = defaults.volatility.default;
        self.state.market = defaults.market;

        // Apply archetype defaults to smart controls
        self.state.controls.energy.intensity = defaults.intensity;
        self.state.controls.energy.build_speed = defaults.build_speed;
        self.state.controls.energy.peak_aggression = defaults.peak_aggression;
        self.state.controls.energy.decay = defaults.decay_rate;
        self.state.controls.clarity.mix_tightness = defaults.mix_tightness;
        self.state.controls.clarity.transient_sharpness = defaults.transient_sharpness;
        self.state.controls.clarity.width = defaults.width;
        self.state.controls.clarity.harmonics = defaults.harmonics;
        self.state.controls.stability.fatigue = defaults.fatigue_target;
        self.state.controls.stability.peak_duration = defaults.peak_duration_target;
        self.state.controls.stability.voice_density = defaults.voice_density_target;
    }

    pub fn set_volatility(&mut self, value: f64) {
        if let Some(arch) = self.state.archetype {
            let range = arch.defaults().volatility;
            self.state.volatility = value.clamp(range.min, range.max);
        } else {
            self.state.volatility = value.clamp(0.0, 1.0);
        }
    }

    pub fn set_market(&mut self, market: MarketTarget) {
        self.state.market = market;
    }

    /// Auto-configure: apply archetype + volatility + market to controls.
    pub fn auto_configure(&mut self) {
        let archetype = match self.state.archetype {
            Some(a) => a,
            None => return,
        };

        let defaults = archetype.defaults();
        let vol_normalized = if defaults.volatility.max > defaults.volatility.min {
            (self.state.volatility - defaults.volatility.min) / (defaults.volatility.max - defaults.volatility.min)
        } else {
            0.5
        };

        // Market modifier: Casual dials down, Premium dials up
        let market_mod = match self.state.market {
            MarketTarget::Casual   => 0.85,
            MarketTarget::Standard => 1.0,
            MarketTarget::Premium  => 1.15,
        };

        // Scale controls based on volatility position + market
        let scale = |base: f64| -> f64 {
            let scaled = base * (0.7 + vol_normalized * 0.6) * market_mod;
            scaled.clamp(0.0, 1.0)
        };

        self.state.controls.energy.intensity = scale(defaults.intensity);
        self.state.controls.energy.build_speed = scale(defaults.build_speed);
        self.state.controls.energy.peak_aggression = scale(defaults.peak_aggression);
        self.state.controls.energy.decay = (defaults.decay_rate * (1.3 - vol_normalized * 0.6)).clamp(0.0, 1.0);
        self.state.controls.clarity.mix_tightness = (defaults.mix_tightness * market_mod).clamp(0.0, 1.0);
        self.state.controls.clarity.transient_sharpness = scale(defaults.transient_sharpness);
        self.state.controls.clarity.width = scale(defaults.width);
        self.state.controls.clarity.harmonics = scale(defaults.harmonics);
        self.state.controls.stability.fatigue = scale(defaults.fatigue_target);
        self.state.controls.stability.peak_duration = scale(defaults.peak_duration_target);
        self.state.controls.stability.voice_density = scale(defaults.voice_density_target);

        self.state.auto_configured = true;
    }

    /// Mark GDD as imported.
    pub fn set_gdd_imported(&mut self, imported: bool) {
        self.state.gdd_imported = imported;
    }

    /// Set AIL pass status.
    pub fn set_ail_result(&mut self, passed: bool, score: f64) {
        self.state.ail_passed = passed;
        self.state.ail_score = score;
    }

    /// Set certification status.
    pub fn set_certified(&mut self, certified: bool) {
        self.state.certified = certified;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SMART CONTROL ACCESS
    // ═══════════════════════════════════════════════════════════════════════

    pub fn get_control(&self, control: SmartControl) -> f64 {
        self.state.controls.get(control)
    }

    pub fn set_control(&mut self, control: SmartControl, value: f64) {
        self.state.controls.set(control, value);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PARAMETER MAPPING
    // ═══════════════════════════════════════════════════════════════════════

    /// Get mapped engine parameter values from current smart controls.
    pub fn compute_engine_params(&self) -> Vec<(EngineParameter, f64)> {
        let mut result = Vec::with_capacity(12);

        for mapping in &self.mappings {
            let control_value = self.state.controls.get(mapping.control);
            for &(param, min_val, max_val) in &mapping.targets {
                let engine_value = min_val + control_value * (max_val - min_val);
                result.push((param, engine_value));
            }
        }

        result
    }

    /// Get mapping table reference.
    pub fn mappings(&self) -> &[ParameterMapping] {
        &self.mappings
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RESET
    // ═══════════════════════════════════════════════════════════════════════

    pub fn reset(&mut self) {
        self.state = SmartAuthoringState::default();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE JSON
    // ═══════════════════════════════════════════════════════════════════════

    pub fn state_json(&self) -> Result<String, String> {
        use std::fmt::Write;
        let mut json = String::with_capacity(1024);

        write!(json, "{{").map_err(|e| e.to_string())?;
        write!(json, "\"mode\":\"{}\",", self.state.mode.name()).map_err(|e| e.to_string())?;
        write!(json, "\"wizard_step\":\"{}\",", self.state.wizard_step.name()).map_err(|e| e.to_string())?;
        write!(json, "\"wizard_step_index\":{},", self.state.wizard_step.index()).map_err(|e| e.to_string())?;
        write!(json, "\"wizard_progress\":{:.3},", self.wizard_progress()).map_err(|e| e.to_string())?;

        if let Some(arch) = self.state.archetype {
            write!(json, "\"archetype\":\"{}\",", arch.name()).map_err(|e| e.to_string())?;
        } else {
            write!(json, "\"archetype\":null,").map_err(|e| e.to_string())?;
        }

        write!(json, "\"volatility\":{:.4},", self.state.volatility).map_err(|e| e.to_string())?;
        write!(json, "\"market\":\"{}\",", self.state.market.name()).map_err(|e| e.to_string())?;
        write!(json, "\"gdd_imported\":{},", self.state.gdd_imported).map_err(|e| e.to_string())?;
        write!(json, "\"auto_configured\":{},", self.state.auto_configured).map_err(|e| e.to_string())?;
        write!(json, "\"ail_passed\":{},", self.state.ail_passed).map_err(|e| e.to_string())?;
        write!(json, "\"ail_score\":{:.1},", self.state.ail_score).map_err(|e| e.to_string())?;
        write!(json, "\"certified\":{},", self.state.certified).map_err(|e| e.to_string())?;

        // Controls
        write!(json, "\"controls\":{{").map_err(|e| e.to_string())?;
        let arr = self.state.controls.to_array();
        for (i, ctrl) in SmartControl::all().iter().enumerate() {
            if i > 0 { write!(json, ",").map_err(|e| e.to_string())?; }
            write!(json, "\"{}\":{:.4}", ctrl.name(), arr[i]).map_err(|e| e.to_string())?;
        }
        write!(json, "}}").map_err(|e| e.to_string())?;

        write!(json, "}}").map_err(|e| e.to_string())?;
        Ok(json)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    fn build_mappings() -> Vec<ParameterMapping> {
        vec![
            // Energy → engine params
            ParameterMapping {
                control: SmartControl::Intensity,
                targets: vec![
                    (EngineParameter::EnergyIntensityMultiplier, 0.3, 1.0),
                ],
            },
            ParameterMapping {
                control: SmartControl::BuildSpeed,
                targets: vec![
                    (EngineParameter::EscalationRate, 0.1, 2.0),
                ],
            },
            ParameterMapping {
                control: SmartControl::PeakAggression,
                targets: vec![
                    (EngineParameter::PeakEnergyMultiplier, 0.5, 1.5),
                ],
            },
            ParameterMapping {
                control: SmartControl::Decay,
                targets: vec![
                    (EngineParameter::DecayHalfLife, 100.0, 2000.0),
                ],
            },
            // Clarity → engine params
            ParameterMapping {
                control: SmartControl::MixTightness,
                targets: vec![
                    (EngineParameter::SpectralBandwidth, 0.3, 1.0),
                ],
            },
            ParameterMapping {
                control: SmartControl::TransientSharpness,
                targets: vec![
                    (EngineParameter::TransientAttack, 0.5, 50.0),
                ],
            },
            ParameterMapping {
                control: SmartControl::Width,
                targets: vec![
                    (EngineParameter::StereoWidth, 0.0, 2.0),
                ],
            },
            ParameterMapping {
                control: SmartControl::Harmonics,
                targets: vec![
                    (EngineParameter::HarmonicExcitation, 1.0, 3.0),
                ],
            },
            // Stability → engine params
            ParameterMapping {
                control: SmartControl::Fatigue,
                targets: vec![
                    (EngineParameter::FatigueThreshold, 0.3, 0.9),
                ],
            },
            ParameterMapping {
                control: SmartControl::PeakDuration,
                targets: vec![
                    (EngineParameter::PeakDurationLimit, 60.0, 240.0),
                ],
            },
            ParameterMapping {
                control: SmartControl::VoiceDensity,
                targets: vec![
                    (EngineParameter::VoiceBudgetScale, 0.3, 1.0),
                    (EngineParameter::SciTarget, 0.3, 0.85),
                ],
            },
        ]
    }
}

impl Default for SmartAuthoringEngine {
    fn default() -> Self {
        Self::new()
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation() {
        let engine = SmartAuthoringEngine::new();
        assert_eq!(engine.mode(), AuthoringMode::Smart);
        assert_eq!(engine.wizard_step(), WizardStep::Archetype);
        assert!(engine.archetype().is_none());
    }

    #[test]
    fn test_select_archetype() {
        let mut engine = SmartAuthoringEngine::new();
        engine.select_archetype(SlotArchetype::CascadeHeavy);
        assert_eq!(engine.archetype(), Some(SlotArchetype::CascadeHeavy));
        // Should apply archetype defaults
        let defaults = SlotArchetype::CascadeHeavy.defaults();
        assert!((engine.get_control(SmartControl::Intensity) - defaults.intensity).abs() < 1e-10);
    }

    #[test]
    fn test_wizard_navigation() {
        let mut engine = SmartAuthoringEngine::new();
        assert_eq!(engine.wizard_step(), WizardStep::Archetype);

        assert!(engine.wizard_next());
        assert_eq!(engine.wizard_step(), WizardStep::Volatility);

        assert!(engine.wizard_next());
        assert_eq!(engine.wizard_step(), WizardStep::Market);

        assert!(engine.wizard_prev());
        assert_eq!(engine.wizard_step(), WizardStep::Volatility);
    }

    #[test]
    fn test_wizard_bounds() {
        let mut engine = SmartAuthoringEngine::new();
        assert!(!engine.wizard_prev()); // Can't go before first
        engine.set_wizard_step(WizardStep::Bake);
        assert!(!engine.wizard_next()); // Can't go past last
    }

    #[test]
    fn test_wizard_progress() {
        let mut engine = SmartAuthoringEngine::new();
        let p1 = engine.wizard_progress();
        assert!((p1 - 1.0/9.0).abs() < 0.01);

        engine.set_wizard_step(WizardStep::Bake);
        let p9 = engine.wizard_progress();
        assert!((p9 - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_auto_configure() {
        let mut engine = SmartAuthoringEngine::new();
        engine.select_archetype(SlotArchetype::JackpotHeavy);
        engine.set_volatility(0.9);
        engine.set_market(MarketTarget::Premium);
        engine.auto_configure();

        assert!(engine.state().auto_configured);
        // Controls should be adjusted from defaults
        assert!(engine.get_control(SmartControl::Intensity) > 0.0);
        assert!(engine.get_control(SmartControl::Intensity) <= 1.0);
    }

    #[test]
    fn test_mode_switch() {
        let mut engine = SmartAuthoringEngine::new();
        engine.set_mode(AuthoringMode::Advanced);
        assert_eq!(engine.mode(), AuthoringMode::Advanced);
        engine.set_mode(AuthoringMode::Debug);
        assert_eq!(engine.mode(), AuthoringMode::Debug);
    }

    #[test]
    fn test_compute_engine_params() {
        let mut engine = SmartAuthoringEngine::new();
        engine.select_archetype(SlotArchetype::Classic3Reel);
        let params = engine.compute_engine_params();
        // Should have at least 12 mapped params (some controls map to 2)
        assert!(params.len() >= 12);
        for &(_param, value) in &params {
            // All values should be within their respective ranges
            assert!(value.is_finite());
        }
    }

    #[test]
    fn test_control_set_and_get() {
        let mut engine = SmartAuthoringEngine::new();
        engine.set_control(SmartControl::Width, 0.75);
        assert!((engine.get_control(SmartControl::Width) - 0.75).abs() < 1e-10);
    }

    #[test]
    fn test_state_json() {
        let mut engine = SmartAuthoringEngine::new();
        engine.select_archetype(SlotArchetype::TurboArcade);
        let json = engine.state_json().expect("JSON should work");
        assert!(json.contains("\"mode\":\"SMART\""));
        assert!(json.contains("\"archetype\":\"Turbo Arcade\""));
        assert!(json.contains("\"controls\":{"));
    }

    #[test]
    fn test_reset() {
        let mut engine = SmartAuthoringEngine::new();
        engine.select_archetype(SlotArchetype::MegawaysStyle);
        engine.set_mode(AuthoringMode::Advanced);
        engine.set_wizard_step(WizardStep::Preview);

        engine.reset();
        assert_eq!(engine.mode(), AuthoringMode::Smart);
        assert_eq!(engine.wizard_step(), WizardStep::Archetype);
        assert!(engine.archetype().is_none());
    }

    #[test]
    fn test_volatility_clamped_to_archetype_range() {
        let mut engine = SmartAuthoringEngine::new();
        engine.select_archetype(SlotArchetype::Classic3Reel);
        // Classic3Reel range: 0.1–0.4
        engine.set_volatility(0.9);
        assert!((engine.state().volatility - 0.4).abs() < 1e-10);
        engine.set_volatility(0.05);
        assert!((engine.state().volatility - 0.1).abs() < 1e-10);
    }

    #[test]
    fn test_authoring_mode_from_index() {
        assert_eq!(AuthoringMode::from_index(0), Some(AuthoringMode::Smart));
        assert_eq!(AuthoringMode::from_index(1), Some(AuthoringMode::Advanced));
        assert_eq!(AuthoringMode::from_index(2), Some(AuthoringMode::Debug));
        assert_eq!(AuthoringMode::from_index(3), None);
    }

    #[test]
    fn test_wizard_step_all() {
        let all = WizardStep::all();
        assert_eq!(all.len(), 9);
        for (i, step) in all.iter().enumerate() {
            assert_eq!(step.index(), i as u8);
        }
    }
}

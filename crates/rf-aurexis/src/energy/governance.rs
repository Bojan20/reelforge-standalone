//! GEG-1 + GEG-5: Energy Governor — core governance logic.
//!
//! `FinalCap = min(1.0, EI × SP × SM)` per energy domain.
//! Voice budget enforcement: Peak=90%, Mid=70%, Low=50%.

use serde::{Deserialize, Serialize};

use super::escalation::{GegCurveType, GegEscalationCurve};
use super::session_memory::SessionMemory;
use super::slot_profiles::{SlotProfile, SlotProfileData};

/// 5 energy domains tracked independently.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnergyDomain {
    /// Gain levels, dynamic range.
    Dynamic = 0,
    /// Attack density, transient frequency.
    Transient = 1,
    /// Width, motion, spatial spread.
    Spatial = 2,
    /// Harmonic layers, spectral richness.
    Harmonic = 3,
    /// Event frequency, temporal density.
    Temporal = 4,
}

impl EnergyDomain {
    pub fn all() -> [EnergyDomain; 5] {
        [
            EnergyDomain::Dynamic,
            EnergyDomain::Transient,
            EnergyDomain::Spatial,
            EnergyDomain::Harmonic,
            EnergyDomain::Temporal,
        ]
    }

    pub fn name(&self) -> &'static str {
        match self {
            EnergyDomain::Dynamic => "Dynamic",
            EnergyDomain::Transient => "Transient",
            EnergyDomain::Spatial => "Spatial",
            EnergyDomain::Harmonic => "Harmonic",
            EnergyDomain::Temporal => "Temporal",
        }
    }
}

/// Per-domain energy budget output.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct EnergyBudget {
    /// Final cap per domain [0.0, 1.0].
    pub caps: [f64; 5],
    /// Raw EI per domain before SP/SM modulation.
    pub raw_ei: [f64; 5],
    /// Overall energy cap (average of domain caps).
    pub overall_cap: f64,
}

impl Default for EnergyBudget {
    fn default() -> Self {
        Self {
            caps: [0.5; 5],
            raw_ei: [0.5; 5],
            overall_cap: 0.5,
        }
    }
}

/// Voice budget based on energy level.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct VoiceBudget {
    /// Maximum allowed voices.
    pub max_voices: u32,
    /// Current energy level classification.
    pub level: EnergyLevel,
    /// Voice budget percentage (0.5, 0.7, or 0.9).
    pub budget_ratio: f64,
}

/// Energy level classification for voice budget.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EnergyLevel {
    Low,
    Mid,
    Peak,
}

/// GEG-1: Energy Governor — main struct.
pub struct EnergyGovernor {
    /// Active slot profile.
    profile: SlotProfile,
    /// Session memory tracker.
    session_memory: SessionMemory,
    /// Active escalation curve for energy scaling.
    curve: GegCurveType,
    /// Last computed energy budget.
    budget: EnergyBudget,
    /// Last computed voice budget.
    voice_budget: VoiceBudget,
}

impl EnergyGovernor {
    /// Create a new governor with default profile.
    pub fn new() -> Self {
        let profile = SlotProfile::MediumVolatility;
        let profile_data = profile.data();
        Self {
            profile,
            session_memory: SessionMemory::new(),
            curve: profile_data.default_curve,
            budget: EnergyBudget::default(),
            voice_budget: VoiceBudget {
                max_voices: profile_data.voice_budget_max,
                level: EnergyLevel::Mid,
                budget_ratio: 0.7,
            },
        }
    }

    /// Create with a specific slot profile.
    pub fn with_profile(profile: SlotProfile) -> Self {
        let profile_data = profile.data();
        Self {
            profile,
            session_memory: SessionMemory::new(),
            curve: profile_data.default_curve,
            budget: EnergyBudget::default(),
            voice_budget: VoiceBudget {
                max_voices: profile_data.voice_budget_max,
                level: EnergyLevel::Mid,
                budget_ratio: 0.7,
            },
        }
    }

    // ─── Getters ───

    pub fn profile(&self) -> SlotProfile {
        self.profile
    }

    pub fn session_memory(&self) -> &SessionMemory {
        &self.session_memory
    }

    pub fn session_memory_mut(&mut self) -> &mut SessionMemory {
        &mut self.session_memory
    }

    pub fn budget(&self) -> &EnergyBudget {
        &self.budget
    }

    pub fn voice_budget(&self) -> &VoiceBudget {
        &self.voice_budget
    }

    pub fn curve(&self) -> GegCurveType {
        self.curve
    }

    // ─── Setters ───

    /// Change active slot profile.
    pub fn set_profile(&mut self, profile: SlotProfile) {
        self.profile = profile;
        let data = profile.data();
        self.curve = data.default_curve;
        self.voice_budget.max_voices = data.voice_budget_max;
    }

    /// Override escalation curve.
    pub fn set_curve(&mut self, curve: GegCurveType) {
        self.curve = curve;
    }

    // ─── Core compute ───

    /// Compute energy budget from emotional intensity values.
    ///
    /// `ei_per_domain`: raw emotional intensity per domain [0.0, 1.0+].
    /// Each EI value is scaled through the curve, then multiplied by SP and SM.
    ///
    /// Formula: `FinalCap[d] = min(1.0, curve(EI[d]) × SP_domain_cap[d] × SM)`
    pub fn compute(&mut self, ei_per_domain: [f64; 5]) -> &EnergyBudget {
        let profile_data = self.profile.data();
        let sm = self.session_memory.sm();

        let mut caps = [0.0; 5];
        let mut raw = [0.0; 5];

        for i in 0..5 {
            let scaled_ei = GegEscalationCurve::evaluate(ei_per_domain[i], self.curve);
            raw[i] = scaled_ei;
            caps[i] = (scaled_ei * profile_data.domain_caps[i] * sm).min(1.0);
        }

        let overall = caps.iter().sum::<f64>() / 5.0;

        self.budget = EnergyBudget {
            caps,
            raw_ei: raw,
            overall_cap: overall,
        };

        // Update voice budget based on overall cap
        self.update_voice_budget(overall, profile_data);

        &self.budget
    }

    /// GEG-5: Voice budget enforcement.
    fn update_voice_budget(&mut self, overall_cap: f64, profile: &SlotProfileData) {
        let (level, ratio) = if overall_cap >= 0.75 {
            (EnergyLevel::Peak, 0.9)
        } else if overall_cap >= 0.45 {
            (EnergyLevel::Mid, 0.7)
        } else {
            (EnergyLevel::Low, 0.5)
        };

        self.voice_budget = VoiceBudget {
            max_voices: (profile.voice_budget_max as f64 * ratio).round() as u32,
            level,
            budget_ratio: ratio,
        };
    }

    /// Get the cap for a specific domain.
    pub fn domain_cap(&self, domain: EnergyDomain) -> f64 {
        self.budget.caps[domain as usize]
    }

    /// Record a spin for session memory tracking.
    pub fn record_spin(&mut self, win_multiplier: f64, is_feature: bool, is_jackpot: bool) {
        self.session_memory
            .record_spin(win_multiplier, is_feature, is_jackpot);
    }

    /// Reset session (clears session memory, keeps profile).
    pub fn reset_session(&mut self) {
        self.session_memory.reset();
        self.budget = EnergyBudget::default();
        self.voice_budget = VoiceBudget {
            max_voices: self.profile.data().voice_budget_max,
            level: EnergyLevel::Mid,
            budget_ratio: 0.7,
        };
    }

    /// Serialize energy budget to JSON for bake output.
    pub fn budget_to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(&self.budget)
    }

    /// Serialize slot profile info to JSON for bake output.
    pub fn profile_to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self.profile.data())
    }
}

impl Default for EnergyGovernor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_governor() {
        let gov = EnergyGovernor::new();
        assert_eq!(gov.profile(), SlotProfile::MediumVolatility);
        assert_eq!(gov.session_memory().sm(), 1.0);
    }

    #[test]
    fn test_final_cap_formula() {
        let mut gov = EnergyGovernor::with_profile(SlotProfile::MediumVolatility);
        // Full intensity across all domains
        let budget = gov.compute([1.0, 1.0, 1.0, 1.0, 1.0]);
        // MedVol SP domain caps: [0.85, 0.80, 0.80, 0.75, 0.75], SM=1.0
        // curve(1.0) for SCurve = 1.0
        // So caps = [0.85, 0.80, 0.80, 0.75, 0.75]
        assert!(
            (budget.caps[0] - 0.85).abs() < 0.01,
            "Dynamic: {}",
            budget.caps[0]
        );
        assert!(
            (budget.caps[1] - 0.80).abs() < 0.01,
            "Transient: {}",
            budget.caps[1]
        );
        assert!(
            (budget.caps[2] - 0.80).abs() < 0.01,
            "Spatial: {}",
            budget.caps[2]
        );
        assert!(
            (budget.caps[3] - 0.75).abs() < 0.01,
            "Harmonic: {}",
            budget.caps[3]
        );
        assert!(
            (budget.caps[4] - 0.75).abs() < 0.01,
            "Temporal: {}",
            budget.caps[4]
        );
    }

    #[test]
    fn test_zero_intensity_zero_cap() {
        let mut gov = EnergyGovernor::new();
        let budget = gov.compute([0.0, 0.0, 0.0, 0.0, 0.0]);
        for cap in &budget.caps {
            assert_eq!(*cap, 0.0);
        }
    }

    #[test]
    fn test_cap_never_exceeds_one() {
        let mut gov = EnergyGovernor::with_profile(SlotProfile::HighVolatility);
        let budget = gov.compute([5.0, 5.0, 5.0, 5.0, 5.0]);
        for cap in &budget.caps {
            assert!(*cap <= 1.0, "Cap must not exceed 1.0: {cap}");
        }
    }

    #[test]
    fn test_session_memory_reduces_caps() {
        let mut gov = EnergyGovernor::new();

        // Fresh session
        let fresh = gov.compute([0.8, 0.8, 0.8, 0.8, 0.8]).caps;

        // Simulate long loss streak
        for _ in 0..30 {
            gov.record_spin(0.0, false, false);
        }
        let fatigued = gov.compute([0.8, 0.8, 0.8, 0.8, 0.8]).caps;

        // SM should be less than 1.0 now, so caps should be lower
        assert!(
            fatigued[0] < fresh[0],
            "Loss streak should reduce dynamic cap: fresh={}, fatigued={}",
            fresh[0],
            fatigued[0]
        );
    }

    #[test]
    fn test_voice_budget_peak() {
        let mut gov = EnergyGovernor::with_profile(SlotProfile::HighVolatility);
        gov.compute([1.0, 1.0, 1.0, 1.0, 1.0]);
        let vb = gov.voice_budget();
        assert_eq!(vb.level, EnergyLevel::Peak);
        assert_eq!(vb.budget_ratio, 0.9);
        // HighVol max=48, 90% = 43
        assert_eq!(vb.max_voices, 43);
    }

    #[test]
    fn test_voice_budget_low() {
        let mut gov = EnergyGovernor::new();
        gov.compute([0.1, 0.1, 0.1, 0.1, 0.1]);
        let vb = gov.voice_budget();
        assert_eq!(vb.level, EnergyLevel::Low);
        assert_eq!(vb.budget_ratio, 0.5);
    }

    #[test]
    fn test_voice_budget_mid() {
        let mut gov = EnergyGovernor::new();
        gov.compute([0.6, 0.6, 0.6, 0.6, 0.6]);
        let vb = gov.voice_budget();
        assert_eq!(vb.level, EnergyLevel::Mid);
        assert_eq!(vb.budget_ratio, 0.7);
    }

    #[test]
    fn test_profile_switch() {
        let mut gov = EnergyGovernor::new();
        assert_eq!(gov.profile(), SlotProfile::MediumVolatility);

        gov.set_profile(SlotProfile::Classic3Reel);
        assert_eq!(gov.profile(), SlotProfile::Classic3Reel);
        assert_eq!(gov.curve(), GegCurveType::Linear);
    }

    #[test]
    fn test_different_profiles_different_caps() {
        let mut high_vol = EnergyGovernor::with_profile(SlotProfile::HighVolatility);
        let mut classic = EnergyGovernor::with_profile(SlotProfile::Classic3Reel);

        let ei = [0.7, 0.7, 0.7, 0.7, 0.7];
        let high_caps = high_vol.compute(ei).caps;
        let classic_caps = classic.compute(ei).caps;

        // HighVol should have higher caps than Classic3Reel
        assert!(
            high_caps[0] > classic_caps[0],
            "HighVol dynamic cap should > Classic: {} vs {}",
            high_caps[0],
            classic_caps[0]
        );
    }

    #[test]
    fn test_reset_session() {
        let mut gov = EnergyGovernor::new();
        for _ in 0..20 {
            gov.record_spin(0.0, false, false);
        }
        gov.compute([0.8; 5]);
        assert!(gov.session_memory().sm() < 1.0);

        gov.reset_session();
        assert_eq!(gov.session_memory().sm(), 1.0);
        assert_eq!(gov.session_memory().total_spins(), 0);
    }

    #[test]
    fn test_determinism() {
        let mut a = EnergyGovernor::with_profile(SlotProfile::CascadeHeavy);
        let mut b = EnergyGovernor::with_profile(SlotProfile::CascadeHeavy);

        a.record_spin(5.0, true, false);
        b.record_spin(5.0, true, false);

        let ei = [0.6, 0.8, 0.5, 0.7, 0.9];
        let caps_a = a.compute(ei).caps;
        let caps_b = b.compute(ei).caps;

        for i in 0..5 {
            assert_eq!(caps_a[i], caps_b[i], "Domain {} not deterministic", i);
        }
    }

    #[test]
    fn test_overall_cap() {
        let mut gov = EnergyGovernor::new();
        let budget = gov.compute([0.5, 0.6, 0.7, 0.8, 0.9]);
        let expected_avg = budget.caps.iter().sum::<f64>() / 5.0;
        assert!((budget.overall_cap - expected_avg).abs() < 1e-10);
    }

    #[test]
    fn test_bake_json_output() {
        let mut gov = EnergyGovernor::new();
        gov.compute([0.5; 5]);
        let json = gov.budget_to_json().unwrap();
        assert!(json.contains("caps"));
        assert!(json.contains("overall_cap"));

        let profile_json = gov.profile_to_json().unwrap();
        assert!(profile_json.contains("sp_multiplier"));
    }

    #[test]
    fn test_curve_override() {
        let mut gov = EnergyGovernor::new();
        gov.set_curve(GegCurveType::Step);
        assert_eq!(gov.curve(), GegCurveType::Step);

        let budget = gov.compute([0.5, 0.5, 0.5, 0.5, 0.5]);
        // Step at 0.5 = 0.50
        for cap in &budget.caps {
            assert!(*cap > 0.0 && *cap <= 1.0);
        }
    }

    #[test]
    fn test_domain_cap_getter() {
        let mut gov = EnergyGovernor::new();
        gov.compute([0.5; 5]);
        let dynamic = gov.domain_cap(EnergyDomain::Dynamic);
        assert!(dynamic > 0.0 && dynamic <= 1.0);
    }

    #[test]
    fn test_all_profiles_valid() {
        for profile in SlotProfile::all() {
            let data = profile.data();
            assert!(data.sp_multiplier > 0.0 && data.sp_multiplier <= 1.0);
            assert!(data.voice_budget_max > 0 && data.voice_budget_max <= 64);
            for cap in &data.domain_caps {
                assert!(*cap > 0.0 && *cap <= 1.0);
            }
        }
    }
}

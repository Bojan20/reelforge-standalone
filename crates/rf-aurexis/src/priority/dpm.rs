//! DPM-1 to DPM-8: Dynamic Priority Matrix core logic.
//!
//! Formula: PriorityScore = BaseWeight × EmotionalWeight × ProfileWeight × EnergyWeight × ContextModifier
//!
//! Voice survival: sort by score descending → retain until voice budget → attenuate (within 10%) → suppress.
//! Special rules: Background never fully suppressed (ducking curve fallback), JACKPOT_GRAND override.

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT TYPES — DPM-2: 8 base event type weights
// ═══════════════════════════════════════════════════════════════════════════════

/// 8 event types with pre-defined base weights.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum EventType {
    JackpotGrand = 0,
    WinBig = 1,
    FeatureEnter = 2,
    CascadeStep = 3,
    ReelStop = 4,
    Background = 5,
    Ui = 6,
    System = 7,
}

impl EventType {
    /// Base weight for this event type (DPM-2).
    pub fn base_weight(self) -> f64 {
        match self {
            EventType::JackpotGrand => 1.00,
            EventType::WinBig => 0.95,
            EventType::FeatureEnter => 0.90,
            EventType::CascadeStep => 0.70,
            EventType::ReelStop => 0.65,
            EventType::Background => 0.50,
            EventType::Ui => 0.40,
            EventType::System => 0.30,
        }
    }

    /// Whether this is a background event (never-suppress rule, DPM-6).
    pub fn is_background(self) -> bool {
        matches!(self, EventType::Background)
    }

    /// Whether this is a jackpot grand (override rule, DPM-7).
    pub fn is_jackpot_grand(self) -> bool {
        matches!(self, EventType::JackpotGrand)
    }

    /// Display name.
    pub fn name(self) -> &'static str {
        match self {
            EventType::JackpotGrand => "Jackpot Grand",
            EventType::WinBig => "Win Big",
            EventType::FeatureEnter => "Feature Enter",
            EventType::CascadeStep => "Cascade Step",
            EventType::ReelStop => "Reel Stop",
            EventType::Background => "Background",
            EventType::Ui => "UI",
            EventType::System => "System",
        }
    }

    /// Get event type from index (0-7).
    pub fn from_index(i: u8) -> Option<Self> {
        match i {
            0 => Some(EventType::JackpotGrand),
            1 => Some(EventType::WinBig),
            2 => Some(EventType::FeatureEnter),
            3 => Some(EventType::CascadeStep),
            4 => Some(EventType::ReelStop),
            5 => Some(EventType::Background),
            6 => Some(EventType::Ui),
            7 => Some(EventType::System),
            _ => None,
        }
    }

    /// Number of event types.
    pub const COUNT: usize = 8;
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMOTIONAL STATES — DPM-3: 7 emotional state multipliers
// ═══════════════════════════════════════════════════════════════════════════════

/// 7 emotional states that modify priority weighting.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum EmotionalState {
    Neutral = 0,
    Anticipation = 1,
    Excitement = 2,
    Tension = 3,
    Relief = 4,
    Frustration = 5,
    Euphoria = 6,
}

impl EmotionalState {
    /// Emotional weight multipliers per event type (DPM-3).
    /// Returns [multiplier; 8] indexed by EventType.
    pub fn weights(self) -> [f64; 8] {
        match self {
            // Neutral: no modification
            EmotionalState::Neutral => [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
            // Anticipation: boost feature/reel, reduce UI
            EmotionalState::Anticipation => [1.0, 1.1, 1.2, 1.1, 1.15, 0.9, 0.8, 0.9],
            // Excitement: boost wins/features heavily
            EmotionalState::Excitement => [1.0, 1.3, 1.25, 1.2, 1.1, 0.85, 0.7, 0.8],
            // Tension: boost cascade/reel, reduce background
            EmotionalState::Tension => [1.0, 1.1, 1.15, 1.25, 1.2, 0.8, 0.85, 0.9],
            // Relief: boost background/ambient, reduce sharp events
            EmotionalState::Relief => [1.0, 0.9, 0.95, 0.85, 0.9, 1.3, 1.1, 1.0],
            // Frustration: reduce everything except UI/system
            EmotionalState::Frustration => [1.0, 0.85, 0.9, 0.8, 0.85, 0.9, 1.15, 1.1],
            // Euphoria: max boost on wins/features
            EmotionalState::Euphoria => [1.0, 1.4, 1.35, 1.3, 1.15, 0.75, 0.65, 0.7],
        }
    }

    /// Get emotional weight for a specific event type.
    pub fn weight_for(self, event: EventType) -> f64 {
        self.weights()[event as usize]
    }

    /// Display name.
    pub fn name(self) -> &'static str {
        match self {
            EmotionalState::Neutral => "Neutral",
            EmotionalState::Anticipation => "Anticipation",
            EmotionalState::Excitement => "Excitement",
            EmotionalState::Tension => "Tension",
            EmotionalState::Relief => "Relief",
            EmotionalState::Frustration => "Frustration",
            EmotionalState::Euphoria => "Euphoria",
        }
    }

    /// Get from index (0-6).
    pub fn from_index(i: u8) -> Option<Self> {
        match i {
            0 => Some(EmotionalState::Neutral),
            1 => Some(EmotionalState::Anticipation),
            2 => Some(EmotionalState::Excitement),
            3 => Some(EmotionalState::Tension),
            4 => Some(EmotionalState::Relief),
            5 => Some(EmotionalState::Frustration),
            6 => Some(EmotionalState::Euphoria),
            _ => None,
        }
    }

    /// Number of emotional states.
    pub const COUNT: usize = 7;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROFILE WEIGHT MODIFIERS — DPM-4: 9 slot profile modifiers from GEG
// ═══════════════════════════════════════════════════════════════════════════════

/// Per-profile event weight modifiers (indexed by SlotProfile 0-8, then EventType 0-7).
static PROFILE_MODIFIERS: [[f64; 8]; 9] = [
    // HighVolatility: boost jackpot/wins, reduce UI/system
    [1.2, 1.15, 1.1, 1.0, 0.95, 0.85, 0.8, 0.8],
    // MediumVolatility: balanced
    [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
    // LowVolatility: reduce extremes, boost steady events
    [0.85, 0.9, 0.95, 1.05, 1.1, 1.15, 1.1, 1.05],
    // CascadeHeavy: boost cascade/feature
    [1.0, 1.05, 1.15, 1.3, 1.1, 0.9, 0.85, 0.9],
    // FeatureHeavy: boost feature enter
    [1.0, 1.1, 1.3, 1.1, 1.0, 0.9, 0.85, 0.9],
    // JackpotFocused: boost jackpot/win heavily
    [1.3, 1.25, 1.0, 0.9, 0.85, 0.8, 0.8, 0.85],
    // Classic3Reel: boost reel stops, reduce cascade/feature
    [0.9, 0.95, 0.85, 0.8, 1.3, 1.1, 1.05, 1.0],
    // ClusterPay: boost cascade heavily
    [1.0, 1.1, 1.1, 1.35, 0.9, 0.9, 0.85, 0.9],
    // MegawaysStyle: boost cascades and features
    [1.05, 1.1, 1.2, 1.25, 1.0, 0.85, 0.8, 0.85],
];

/// Get profile weight modifier for a given profile and event type.
pub fn profile_modifier(profile_index: u8, event: EventType) -> f64 {
    if profile_index > 8 {
        return 1.0;
    }
    PROFILE_MODIFIERS[profile_index as usize][event as usize]
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE PRIORITY & SURVIVAL — DPM-5, DPM-6, DPM-7
// ═══════════════════════════════════════════════════════════════════════════════

/// A voice with its computed priority score.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoicePriority {
    pub voice_id: u32,
    pub event_type: EventType,
    pub priority_score: f64,
    pub context_modifier: f64,
}

/// Result of voice survival logic.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum SurvivalAction {
    /// Voice plays at full level.
    Retain,
    /// Voice plays at reduced level (×0.6).
    Attenuate,
    /// Voice is suppressed (silent).
    Suppress,
    /// Background voice: ducking curve instead of suppress (DPM-6).
    DuckCurve { duck_db: f64 },
}

/// Per-voice survival result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoiceSurvivalResult {
    pub voice_id: u32,
    pub priority_score: f64,
    pub action: SurvivalAction,
    pub event_type: EventType,
}

/// DPM output aggregate.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DpmOutput {
    /// All voice priorities (sorted descending by score).
    pub voice_priorities: Vec<VoicePriority>,
    /// Voice survival results.
    pub survival_results: Vec<VoiceSurvivalResult>,
    /// Number of voices retained.
    pub retained_count: u32,
    /// Number of voices attenuated.
    pub attenuated_count: u32,
    /// Number of voices suppressed.
    pub suppressed_count: u32,
    /// Number of background voices ducked.
    pub ducked_count: u32,
    /// Whether JACKPOT_GRAND override is active.
    pub jackpot_override_active: bool,
}

// ═══════════════════════════════════════════════════════════════════════════════
// DYNAMIC PRIORITY MATRIX — DPM-1
// ═══════════════════════════════════════════════════════════════════════════════

/// Dynamic Priority Matrix — computes voice priorities and survival.
#[derive(Debug)]
pub struct DynamicPriorityMatrix {
    /// Current emotional state.
    emotional_state: EmotionalState,
    /// Active slot profile index (0-8, from GEG).
    profile_index: u8,
    /// Energy overall cap from GEG (0.0-1.0).
    energy_cap: f64,
    /// Voice budget max from GEG.
    voice_budget_max: u32,
    /// Background duck amount in dB.
    background_duck_db: f64,
    /// Attenuate factor for voices within 10% of threshold (reserved for DSP consumers).
    _attenuate_factor: f64,
    /// Last computed output.
    last_output: DpmOutput,
}

impl DynamicPriorityMatrix {
    pub fn new() -> Self {
        Self {
            emotional_state: EmotionalState::Neutral,
            profile_index: 1, // MediumVolatility
            energy_cap: 0.5,
            voice_budget_max: 40,
            background_duck_db: -6.0,
            _attenuate_factor: 0.6,
            last_output: DpmOutput::default(),
        }
    }

    // ─── Setters ───

    pub fn set_emotional_state(&mut self, state: EmotionalState) {
        self.emotional_state = state;
    }

    pub fn set_profile_index(&mut self, idx: u8) {
        if idx <= 8 {
            self.profile_index = idx;
        }
    }

    pub fn set_energy_cap(&mut self, cap: f64) {
        self.energy_cap = cap.clamp(0.0, 1.0);
    }

    pub fn set_voice_budget_max(&mut self, max: u32) {
        self.voice_budget_max = max;
    }

    // ─── Getters ───

    pub fn emotional_state(&self) -> EmotionalState {
        self.emotional_state
    }

    pub fn profile_index(&self) -> u8 {
        self.profile_index
    }

    pub fn last_output(&self) -> &DpmOutput {
        &self.last_output
    }

    // ─── Core: Priority Calculation (DPM-1) ───

    /// Compute priority score for a single event.
    /// Formula: BaseWeight × EmotionalWeight × ProfileWeight × EnergyWeight × ContextModifier
    pub fn compute_priority(&self, event_type: EventType, context_modifier: f64) -> f64 {
        // DPM-7: JACKPOT_GRAND override — always returns maximum
        if event_type.is_jackpot_grand() {
            return f64::MAX;
        }

        let base = event_type.base_weight();
        let emotional = self.emotional_state.weight_for(event_type);
        let profile = profile_modifier(self.profile_index, event_type);

        // Energy weight: higher energy cap → higher priority allowance
        // Inverted: low cap → reduce priority of low-priority events more
        let energy_weight = 0.5 + (self.energy_cap * 0.5);

        let context = context_modifier.max(0.01); // never zero

        base * emotional * profile * energy_weight * context
    }

    /// Compute priorities for all active voices and apply survival logic.
    pub fn compute(
        &mut self,
        voices: &[(u32, EventType, f64)], // (voice_id, event_type, context_modifier)
    ) -> &DpmOutput {
        let mut priorities: Vec<VoicePriority> = voices
            .iter()
            .map(|&(voice_id, event_type, context_modifier)| {
                let score = self.compute_priority(event_type, context_modifier);
                VoicePriority {
                    voice_id,
                    event_type,
                    priority_score: score,
                    context_modifier,
                }
            })
            .collect();

        // Sort descending by priority score
        priorities.sort_by(|a, b| {
            b.priority_score
                .partial_cmp(&a.priority_score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        // Voice survival logic (DPM-5)
        let budget = self.voice_budget_max as usize;
        let mut survival_results = Vec::with_capacity(priorities.len());
        let mut retained = 0u32;
        let mut attenuated = 0u32;
        let mut suppressed = 0u32;
        let mut ducked = 0u32;
        let mut jackpot_override = false;

        // Find the priority score at the budget boundary
        let threshold_score = if budget < priorities.len() {
            priorities[budget.saturating_sub(1)].priority_score
        } else {
            0.0 // all fit within budget
        };

        for (i, vp) in priorities.iter().enumerate() {
            // DPM-7: JACKPOT_GRAND always retained
            if vp.event_type.is_jackpot_grand() {
                jackpot_override = true;
                survival_results.push(VoiceSurvivalResult {
                    voice_id: vp.voice_id,
                    priority_score: vp.priority_score,
                    action: SurvivalAction::Retain,
                    event_type: vp.event_type,
                });
                retained += 1;
                continue;
            }

            let action = if i < budget {
                // Within budget → retain
                retained += 1;
                SurvivalAction::Retain
            } else if threshold_score > 0.0 && vp.priority_score >= threshold_score * 0.9 {
                // Within 10% of threshold → attenuate (DPM-5)
                attenuated += 1;
                SurvivalAction::Attenuate
            } else if vp.event_type.is_background() {
                // DPM-6: Background never fully suppressed
                ducked += 1;
                SurvivalAction::DuckCurve {
                    duck_db: self.background_duck_db,
                }
            } else {
                suppressed += 1;
                SurvivalAction::Suppress
            };

            survival_results.push(VoiceSurvivalResult {
                voice_id: vp.voice_id,
                priority_score: vp.priority_score,
                action,
                event_type: vp.event_type,
            });
        }

        self.last_output = DpmOutput {
            voice_priorities: priorities,
            survival_results,
            retained_count: retained,
            attenuated_count: attenuated,
            suppressed_count: suppressed,
            ducked_count: ducked,
            jackpot_override_active: jackpot_override,
        };

        &self.last_output
    }

    /// Reset state.
    pub fn reset(&mut self) {
        self.emotional_state = EmotionalState::Neutral;
        self.energy_cap = 0.5;
        self.last_output = DpmOutput::default();
    }

    /// Serialize event weights to JSON for bake (DPM-10).
    pub fn event_weights_json() -> Result<String, serde_json::Error> {
        let mut weights = std::collections::BTreeMap::new();
        for i in 0..EventType::COUNT {
            if let Some(et) = EventType::from_index(i as u8) {
                weights.insert(et.name().to_string(), et.base_weight());
            }
        }
        serde_json::to_string_pretty(&weights)
    }

    /// Serialize profile modifiers to JSON for bake (DPM-10).
    pub fn profile_modifiers_json() -> Result<String, serde_json::Error> {
        let profile_names = [
            "HighVolatility",
            "MediumVolatility",
            "LowVolatility",
            "CascadeHeavy",
            "FeatureHeavy",
            "JackpotFocused",
            "Classic3Reel",
            "ClusterPay",
            "MegawaysStyle",
        ];
        let event_names: Vec<&str> = (0..8)
            .filter_map(|i| EventType::from_index(i))
            .map(|e| e.name())
            .collect();

        let mut result = std::collections::BTreeMap::new();
        for (pi, pname) in profile_names.iter().enumerate() {
            let mut mods = std::collections::BTreeMap::new();
            for (ei, ename) in event_names.iter().enumerate() {
                mods.insert(ename.to_string(), PROFILE_MODIFIERS[pi][ei]);
            }
            result.insert(pname.to_string(), mods);
        }
        serde_json::to_string_pretty(&result)
    }

    /// Serialize context rules to JSON for bake (DPM-10).
    pub fn context_rules_json() -> Result<String, serde_json::Error> {
        let rules = serde_json::json!({
            "jackpot_grand_override": true,
            "background_never_suppress": true,
            "background_duck_db": -6.0,
            "attenuate_threshold_percent": 10,
            "attenuate_factor": 0.6,
        });
        serde_json::to_string_pretty(&rules)
    }

    /// Serialize current priority matrix output to JSON for bake (DPM-10).
    pub fn priority_matrix_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(&self.last_output)
    }
}

impl Default for DynamicPriorityMatrix {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS — DPM-8: 15+ unit tests
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_base_weights_ordering() {
        // Verify base weights are in descending order
        assert!(EventType::JackpotGrand.base_weight() > EventType::WinBig.base_weight());
        assert!(EventType::WinBig.base_weight() > EventType::FeatureEnter.base_weight());
        assert!(EventType::FeatureEnter.base_weight() > EventType::CascadeStep.base_weight());
        assert!(EventType::CascadeStep.base_weight() > EventType::ReelStop.base_weight());
        assert!(EventType::ReelStop.base_weight() > EventType::Background.base_weight());
        assert!(EventType::Background.base_weight() > EventType::Ui.base_weight());
        assert!(EventType::Ui.base_weight() > EventType::System.base_weight());
    }

    #[test]
    fn test_emotional_neutral_is_identity() {
        let weights = EmotionalState::Neutral.weights();
        for w in weights.iter() {
            assert_eq!(*w, 1.0);
        }
    }

    #[test]
    fn test_emotional_excitement_boosts_wins() {
        let w = EmotionalState::Excitement.weight_for(EventType::WinBig);
        assert!(w > 1.0, "Excitement should boost WinBig: {w}");
        let w2 = EmotionalState::Excitement.weight_for(EventType::Ui);
        assert!(w2 < 1.0, "Excitement should reduce UI: {w2}");
    }

    #[test]
    fn test_priority_formula() {
        let dpm = DynamicPriorityMatrix::new();
        let score = dpm.compute_priority(EventType::WinBig, 1.0);
        // base=0.95, emotional=1.0 (neutral), profile=1.0 (medium), energy=0.75 (cap=0.5)
        let expected = 0.95 * 1.0 * 1.0 * 0.75 * 1.0;
        assert!(
            (score - expected).abs() < 0.001,
            "Expected {expected}, got {score}"
        );
    }

    #[test]
    fn test_jackpot_grand_override() {
        let dpm = DynamicPriorityMatrix::new();
        let score = dpm.compute_priority(EventType::JackpotGrand, 0.1);
        assert_eq!(score, f64::MAX, "JACKPOT_GRAND should always return MAX");
    }

    #[test]
    fn test_profile_modifier_high_vol() {
        let m = profile_modifier(0, EventType::JackpotGrand);
        assert!(m > 1.0, "HighVol should boost jackpot: {m}");
        let m2 = profile_modifier(0, EventType::System);
        assert!(m2 < 1.0, "HighVol should reduce system: {m2}");
    }

    #[test]
    fn test_profile_modifier_classic_3reel() {
        let m = profile_modifier(6, EventType::ReelStop);
        assert!(m > 1.0, "Classic3Reel should boost reel stops: {m}");
    }

    #[test]
    fn test_voice_survival_within_budget() {
        let mut dpm = DynamicPriorityMatrix::new();
        dpm.set_voice_budget_max(5);
        let voices: Vec<(u32, EventType, f64)> = vec![
            (1, EventType::WinBig, 1.0),
            (2, EventType::FeatureEnter, 1.0),
            (3, EventType::ReelStop, 1.0),
        ];
        let output = dpm.compute(&voices);
        assert_eq!(output.retained_count, 3);
        assert_eq!(output.suppressed_count, 0);
        assert_eq!(output.attenuated_count, 0);
    }

    #[test]
    fn test_voice_survival_over_budget() {
        let mut dpm = DynamicPriorityMatrix::new();
        dpm.set_voice_budget_max(2);
        let voices: Vec<(u32, EventType, f64)> = vec![
            (1, EventType::WinBig, 1.0),
            (2, EventType::FeatureEnter, 1.0),
            (3, EventType::System, 1.0),
            (4, EventType::Ui, 1.0),
        ];
        let output = dpm.compute(&voices);
        assert_eq!(output.retained_count, 2, "Should retain 2 voices");
        assert!(
            output.suppressed_count + output.attenuated_count > 0,
            "Excess voices should be suppressed or attenuated"
        );
    }

    #[test]
    fn test_background_never_suppressed() {
        let mut dpm = DynamicPriorityMatrix::new();
        dpm.set_voice_budget_max(1);
        let voices: Vec<(u32, EventType, f64)> =
            vec![(1, EventType::WinBig, 1.0), (2, EventType::Background, 1.0)];
        let output = dpm.compute(&voices);
        // Background should get DuckCurve, not Suppress
        let bg_result = output
            .survival_results
            .iter()
            .find(|r| r.voice_id == 2)
            .unwrap();
        match bg_result.action {
            SurvivalAction::DuckCurve { .. } => {} // OK
            SurvivalAction::Retain => {}           // Also OK if within budget
            _ => panic!(
                "Background should never be suppressed, got: {:?}",
                bg_result.action
            ),
        }
    }

    #[test]
    fn test_jackpot_grand_always_retained() {
        let mut dpm = DynamicPriorityMatrix::new();
        dpm.set_voice_budget_max(0); // zero budget
        let voices: Vec<(u32, EventType, f64)> = vec![(1, EventType::JackpotGrand, 1.0)];
        let output = dpm.compute(&voices);
        assert!(output.jackpot_override_active);
        assert_eq!(output.retained_count, 1);
    }

    #[test]
    fn test_emotional_state_affects_priority() {
        let mut dpm = DynamicPriorityMatrix::new();
        let neutral_score = dpm.compute_priority(EventType::WinBig, 1.0);

        dpm.set_emotional_state(EmotionalState::Euphoria);
        let euphoria_score = dpm.compute_priority(EventType::WinBig, 1.0);

        assert!(
            euphoria_score > neutral_score,
            "Euphoria should increase WinBig priority: neutral={neutral_score}, euphoria={euphoria_score}"
        );
    }

    #[test]
    fn test_energy_cap_affects_priority() {
        let mut dpm = DynamicPriorityMatrix::new();
        dpm.set_energy_cap(0.2);
        let low_score = dpm.compute_priority(EventType::ReelStop, 1.0);

        dpm.set_energy_cap(0.9);
        let high_score = dpm.compute_priority(EventType::ReelStop, 1.0);

        assert!(
            high_score > low_score,
            "Higher energy cap should increase priority: low={low_score}, high={high_score}"
        );
    }

    #[test]
    fn test_event_weights_json() {
        let json = DynamicPriorityMatrix::event_weights_json().unwrap();
        assert!(json.contains("Jackpot Grand"));
        assert!(json.contains("1.0"));
    }

    #[test]
    fn test_profile_modifiers_json() {
        let json = DynamicPriorityMatrix::profile_modifiers_json().unwrap();
        assert!(json.contains("HighVolatility"));
        assert!(json.contains("MediumVolatility"));
    }

    #[test]
    fn test_context_rules_json() {
        let json = DynamicPriorityMatrix::context_rules_json().unwrap();
        assert!(json.contains("jackpot_grand_override"));
        assert!(json.contains("background_never_suppress"));
    }

    #[test]
    fn test_determinism() {
        let mut dpm_a = DynamicPriorityMatrix::new();
        let mut dpm_b = DynamicPriorityMatrix::new();
        dpm_a.set_emotional_state(EmotionalState::Excitement);
        dpm_b.set_emotional_state(EmotionalState::Excitement);
        dpm_a.set_energy_cap(0.7);
        dpm_b.set_energy_cap(0.7);

        let voices: Vec<(u32, EventType, f64)> = vec![
            (1, EventType::WinBig, 1.0),
            (2, EventType::CascadeStep, 0.8),
            (3, EventType::Background, 1.0),
        ];
        let out_a = dpm_a.compute(&voices);
        let out_b = dpm_b.compute(&voices);

        assert_eq!(out_a.retained_count, out_b.retained_count);
        for (a, b) in out_a
            .voice_priorities
            .iter()
            .zip(out_b.voice_priorities.iter())
        {
            assert_eq!(a.priority_score, b.priority_score);
        }
    }

    #[test]
    fn test_attenuate_within_10_percent() {
        let mut dpm = DynamicPriorityMatrix::new();
        dpm.set_voice_budget_max(1);
        // Create voices with very close scores to trigger attenuation
        let voices: Vec<(u32, EventType, f64)> = vec![
            (1, EventType::WinBig, 1.0),       // highest
            (2, EventType::FeatureEnter, 1.0), // close to WinBig
        ];
        let output = dpm.compute(&voices);
        // Voice 2 should be attenuated (within 10% of threshold), not suppressed
        let v2 = output
            .survival_results
            .iter()
            .find(|r| r.voice_id == 2)
            .unwrap();
        assert!(
            matches!(
                v2.action,
                SurvivalAction::Attenuate | SurvivalAction::Retain
            ),
            "Voice close to threshold should be attenuated or retained, got: {:?}",
            v2.action
        );
    }

    #[test]
    fn test_reset() {
        let mut dpm = DynamicPriorityMatrix::new();
        dpm.set_emotional_state(EmotionalState::Euphoria);
        dpm.set_energy_cap(0.9);
        dpm.reset();
        assert_eq!(dpm.emotional_state(), EmotionalState::Neutral);
    }
}

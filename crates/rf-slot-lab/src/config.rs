//! Slot engine configuration

use serde::{Deserialize, Serialize};

/// Grid specification (reels × rows)
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct GridSpec {
    /// Number of reels (columns)
    pub reels: u8,
    /// Number of visible rows per reel
    pub rows: u8,
    /// Total paylines (0 = ways-to-win)
    pub paylines: u16,
}

impl GridSpec {
    /// Standard 5×3 with 20 paylines
    pub fn standard_5x3() -> Self {
        Self {
            reels: 5,
            rows: 3,
            paylines: 20,
        }
    }

    /// Standard 5×4 with 40 paylines
    pub fn standard_5x4() -> Self {
        Self {
            reels: 5,
            rows: 4,
            paylines: 40,
        }
    }

    /// 6×4 Megaways-style (ways calculated dynamically)
    pub fn megaways_6x4() -> Self {
        Self {
            reels: 6,
            rows: 4,
            paylines: 0, // Ways-to-win
        }
    }

    /// Total grid positions
    pub fn total_positions(&self) -> usize {
        self.reels as usize * self.rows as usize
    }

    /// Is this a ways-to-win game?
    pub fn is_ways(&self) -> bool {
        self.paylines == 0
    }
}

impl Default for GridSpec {
    fn default() -> Self {
        Self::standard_5x3()
    }
}

/// Volatility profile controlling win distribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolatilityProfile {
    /// Name for reference
    pub name: String,

    /// Base hit rate (% of spins that win something)
    /// Low vol: 35-40%, Medium: 25-30%, High: 15-20%
    pub hit_rate: f64,

    /// Big win frequency (% of wins that are big wins)
    pub big_win_frequency: f64,

    /// Feature trigger frequency (% of spins that trigger features)
    pub feature_frequency: f64,

    /// Jackpot trigger frequency (per spin, usually very low)
    pub jackpot_frequency: f64,

    /// Near miss frequency (for anticipation audio)
    pub near_miss_frequency: f64,

    /// Cascade probability (if cascades enabled)
    pub cascade_probability: f64,

    /// Win tier thresholds (bet multipliers)
    pub win_tier_thresholds: WinTierThresholds,
}

/// Thresholds for categorizing wins
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTierThresholds {
    /// Minimum ratio for "big win"
    pub big_win: f64,
    /// Minimum ratio for "mega win"
    pub mega_win: f64,
    /// Minimum ratio for "epic win"
    pub epic_win: f64,
    /// Minimum ratio for "ultra win"
    pub ultra_win: f64,
}

impl Default for WinTierThresholds {
    fn default() -> Self {
        Self {
            big_win: 15.0,
            mega_win: 25.0,
            epic_win: 50.0,
            ultra_win: 100.0,
        }
    }
}

impl VolatilityProfile {
    /// Low volatility - frequent small wins
    pub fn low() -> Self {
        Self {
            name: "Low".into(),
            hit_rate: 0.38,
            big_win_frequency: 0.02,
            feature_frequency: 0.012,
            jackpot_frequency: 0.0001,
            near_miss_frequency: 0.15,
            cascade_probability: 0.25,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// Medium volatility - balanced
    pub fn medium() -> Self {
        Self {
            name: "Medium".into(),
            hit_rate: 0.28,
            big_win_frequency: 0.05,
            feature_frequency: 0.008,
            jackpot_frequency: 0.00005,
            near_miss_frequency: 0.20,
            cascade_probability: 0.30,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// High volatility - rare big wins
    pub fn high() -> Self {
        Self {
            name: "High".into(),
            hit_rate: 0.18,
            big_win_frequency: 0.10,
            feature_frequency: 0.005,
            jackpot_frequency: 0.00002,
            near_miss_frequency: 0.25,
            cascade_probability: 0.35,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// Studio mode - high frequency for testing
    pub fn studio() -> Self {
        Self {
            name: "Studio".into(),
            hit_rate: 0.60,
            big_win_frequency: 0.20,
            feature_frequency: 0.10,
            jackpot_frequency: 0.01,
            near_miss_frequency: 0.30,
            cascade_probability: 0.50,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// Interpolate between two profiles
    pub fn interpolate(low: &Self, high: &Self, t: f64) -> Self {
        let t = t.clamp(0.0, 1.0);
        Self {
            name: format!("Custom ({:.0}%)", t * 100.0),
            hit_rate: low.hit_rate + (high.hit_rate - low.hit_rate) * t,
            big_win_frequency: low.big_win_frequency
                + (high.big_win_frequency - low.big_win_frequency) * t,
            feature_frequency: low.feature_frequency
                + (high.feature_frequency - low.feature_frequency) * t,
            jackpot_frequency: low.jackpot_frequency
                + (high.jackpot_frequency - low.jackpot_frequency) * t,
            near_miss_frequency: low.near_miss_frequency
                + (high.near_miss_frequency - low.near_miss_frequency) * t,
            cascade_probability: low.cascade_probability
                + (high.cascade_probability - low.cascade_probability) * t,
            win_tier_thresholds: low.win_tier_thresholds.clone(),
        }
    }
}

impl Default for VolatilityProfile {
    fn default() -> Self {
        Self::medium()
    }
}

/// Feature configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureConfig {
    /// Enable free spins feature
    pub free_spins_enabled: bool,
    /// Free spins count range (min, max)
    pub free_spins_range: (u32, u32),
    /// Multiplier during free spins
    pub free_spins_multiplier: f64,

    /// Enable cascades/tumbles
    pub cascades_enabled: bool,
    /// Max cascade steps
    pub max_cascade_steps: u32,
    /// Cascade multiplier progression (per step)
    pub cascade_multiplier_step: f64,

    /// Enable hold-and-spin
    pub hold_spin_enabled: bool,
    /// Hold-and-spin respins
    pub hold_spin_respins: u32,

    /// Enable gamble feature
    pub gamble_enabled: bool,
    /// Max gamble attempts per win
    pub max_gamble_attempts: u32,

    /// Jackpot tiers enabled
    pub jackpot_enabled: bool,
    /// Jackpot seed values (Mini, Minor, Major, Grand)
    pub jackpot_seeds: [f64; 4],
}

impl Default for FeatureConfig {
    fn default() -> Self {
        Self {
            free_spins_enabled: true,
            free_spins_range: (8, 15),
            free_spins_multiplier: 2.0,

            cascades_enabled: true,
            max_cascade_steps: 8,
            cascade_multiplier_step: 1.0,

            hold_spin_enabled: false,
            hold_spin_respins: 3,

            gamble_enabled: true,
            max_gamble_attempts: 5,

            jackpot_enabled: true,
            jackpot_seeds: [50.0, 200.0, 1000.0, 10000.0],
        }
    }
}

// ============================================================================
// ANTICIPATION SYSTEM V2 — Industry-Standard Per-Reel Tension
// ============================================================================

/// Trigger rule for anticipation activation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TriggerRules {
    /// Require exactly N trigger symbols (e.g., "exactly 3 scatters" for restricted reels)
    Exact(u8),
    /// Require at least N trigger symbols (e.g., "3 or more scatters" for all reels)
    AtLeast(u8),
}

impl Default for TriggerRules {
    fn default() -> Self {
        TriggerRules::AtLeast(3)
    }
}

/// Anticipation tension level (L1-L4)
/// Each level increases intensity: color saturation, volume, pitch
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum TensionLevel {
    /// Level 1: Gold (#FFD700), 60% volume, +1 semitone
    L1 = 1,
    /// Level 2: Orange (#FFA500), 70% volume, +2 semitones
    L2 = 2,
    /// Level 3: Red-Orange (#FF6347), 80% volume, +3 semitones
    L3 = 3,
    /// Level 4: Red (#FF4500), 90% volume, +4 semitones
    L4 = 4,
}

impl TensionLevel {
    /// Get color hex for this tension level
    pub fn color_hex(&self) -> &'static str {
        match self {
            TensionLevel::L1 => "#FFD700", // Gold
            TensionLevel::L2 => "#FFA500", // Orange
            TensionLevel::L3 => "#FF6347", // Red-Orange (Tomato)
            TensionLevel::L4 => "#FF4500", // Red (OrangeRed)
        }
    }

    /// Get volume multiplier for this tension level
    pub fn volume_multiplier(&self) -> f64 {
        match self {
            TensionLevel::L1 => 0.6,
            TensionLevel::L2 => 0.7,
            TensionLevel::L3 => 0.8,
            TensionLevel::L4 => 0.9,
        }
    }

    /// Get pitch offset in semitones for this tension level
    pub fn pitch_semitones(&self) -> i32 {
        match self {
            TensionLevel::L1 => 1,
            TensionLevel::L2 => 2,
            TensionLevel::L3 => 3,
            TensionLevel::L4 => 4,
        }
    }

    /// Get next higher tension level (clamped at L4)
    pub fn escalate(&self) -> TensionLevel {
        match self {
            TensionLevel::L1 => TensionLevel::L2,
            TensionLevel::L2 => TensionLevel::L3,
            TensionLevel::L3 => TensionLevel::L4,
            TensionLevel::L4 => TensionLevel::L4,
        }
    }

    /// Create from 1-based index (clamps to valid range)
    pub fn from_index(idx: u8) -> TensionLevel {
        match idx {
            0 | 1 => TensionLevel::L1,
            2 => TensionLevel::L2,
            3 => TensionLevel::L3,
            _ => TensionLevel::L4,
        }
    }
}

/// Anticipation configuration for a slot game
///
/// Defines which symbols trigger anticipation and on which reels.
///
/// # Examples
///
/// ## Tip A: Scatter on all reels, 3+ rule
/// ```ignore
/// AnticipationConfig {
///     trigger_symbol_ids: vec![SCATTER_ID, BONUS_ID],
///     min_trigger_count: 2,  // Universal rule: 2 triggers = anticipation
///     allowed_reels: None,   // All reels allowed
///     trigger_rules: TriggerRules::AtLeast(3),  // Game awards FS at 3+
/// }
/// ```
///
/// ## Tip B: Scatter only on reels 0, 2, 4 (exactly 3)
/// ```ignore
/// AnticipationConfig {
///     trigger_symbol_ids: vec![SCATTER_ID],
///     min_trigger_count: 2,  // Universal rule: 2 triggers = anticipation
///     allowed_reels: Some(vec![0, 2, 4]),  // Restricted positions
///     trigger_rules: TriggerRules::Exact(3),  // Game requires exactly 3
/// }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnticipationConfig {
    /// Symbol IDs that can trigger anticipation (Scatter, Bonus)
    /// NOTE: Wild symbols should NEVER be included here
    pub trigger_symbol_ids: Vec<u32>,

    /// Minimum number of triggers on allowed reels to activate anticipation
    /// Universal rule: This is always 2 for industry-standard anticipation
    pub min_trigger_count: u8,

    /// Which reels can have trigger symbols (None = all reels)
    /// Examples:
    /// - None: Scatter can land on any reel (Tip A)
    /// - Some([0, 2, 4]): Scatter only on reels 0, 2, 4 (Tip B)
    pub allowed_reels: Option<Vec<u8>>,

    /// How many triggers are needed for the actual feature (FS, Bonus)
    /// This affects the "game rule" but not anticipation activation
    pub trigger_rules: TriggerRules,

    /// Enable sequential reel stopping during anticipation
    /// When true, each anticipation reel stops one-by-one (industry standard)
    pub sequential_stop: bool,

    /// Enable tension level escalation (L1→L2→L3→L4)
    pub tension_escalation: bool,

    /// Enable near miss anticipation (2026-02-01)
    /// When false, near miss will NOT trigger anticipation effects
    /// When true, near miss uses volatility.near_miss_frequency (15-30% chance)
    /// Default: false (only scatter/bonus trigger anticipation)
    #[serde(default)]
    pub enable_near_miss_anticipation: bool,
}

impl Default for AnticipationConfig {
    fn default() -> Self {
        Self {
            // Default: Scatter (ID 12) and Bonus (ID 13) trigger anticipation
            // Wild (ID 11) does NOT trigger anticipation
            // MUST MATCH StandardSymbolSet: WILD=11, SCATTER=12, BONUS=13
            trigger_symbol_ids: vec![12, 13],
            min_trigger_count: 2, // Universal industry rule
            allowed_reels: None,  // All reels by default (Tip A behavior)
            trigger_rules: TriggerRules::AtLeast(3),
            sequential_stop: true,
            tension_escalation: true,
            enable_near_miss_anticipation: false, // Disabled by default (2026-02-01)
        }
    }
}

impl AnticipationConfig {
    /// Create config for "Tip A" games: Scatter on all reels, 3+ triggers
    pub fn tip_a(scatter_id: u32, bonus_id: Option<u32>) -> Self {
        let mut trigger_ids = vec![scatter_id];
        if let Some(bid) = bonus_id {
            trigger_ids.push(bid);
        }
        Self {
            trigger_symbol_ids: trigger_ids,
            min_trigger_count: 2,
            allowed_reels: None,
            trigger_rules: TriggerRules::AtLeast(3),
            sequential_stop: true,
            tension_escalation: true,
            enable_near_miss_anticipation: false,
        }
    }

    /// Create config for "Tip B" games: Scatter only on reels 0, 2, 4 (exactly 3)
    pub fn tip_b(scatter_id: u32, bonus_id: Option<u32>) -> Self {
        let mut trigger_ids = vec![scatter_id];
        if let Some(bid) = bonus_id {
            trigger_ids.push(bid);
        }
        Self {
            trigger_symbol_ids: trigger_ids,
            min_trigger_count: 2,
            allowed_reels: Some(vec![0, 2, 4]),
            trigger_rules: TriggerRules::Exact(3),
            sequential_stop: true,
            tension_escalation: true,
            enable_near_miss_anticipation: false,
        }
    }

    /// Check if a symbol ID is a trigger symbol
    pub fn is_trigger_symbol(&self, symbol_id: u32) -> bool {
        self.trigger_symbol_ids.contains(&symbol_id)
    }

    /// Check if a reel is allowed for trigger symbols
    pub fn is_reel_allowed(&self, reel_index: u8) -> bool {
        match &self.allowed_reels {
            None => true, // All reels allowed
            Some(allowed) => allowed.contains(&reel_index),
        }
    }

    /// Get effective allowed reels for a given total reel count
    pub fn effective_allowed_reels(&self, total_reels: u8) -> Vec<u8> {
        match &self.allowed_reels {
            None => (0..total_reels).collect(),
            Some(allowed) => allowed
                .iter()
                .filter(|&&r| r < total_reels)
                .copied()
                .collect(),
        }
    }

    /// Calculate which reels should have anticipation based on trigger positions
    ///
    /// # Arguments
    /// * `trigger_positions` - List of (reel_index, row_index) where triggers landed
    /// * `total_reels` - Total number of reels in the game
    ///
    /// # Returns
    /// List of reel indices that should have anticipation (in order)
    ///
    /// # Algorithm
    /// 1. Filter triggers to only those on allowed reels
    /// 2. If count < min_trigger_count, return empty (no anticipation)
    /// 3. Find the last (rightmost) trigger reel
    /// 4. Return all allowed reels AFTER the last trigger reel
    pub fn calculate_anticipation_reels(
        &self,
        trigger_positions: &[(u8, u8)],
        total_reels: u8,
    ) -> Vec<u8> {
        let effective_allowed = self.effective_allowed_reels(total_reels);

        // Get trigger reels that are on allowed positions
        let trigger_reels: Vec<u8> = trigger_positions
            .iter()
            .map(|(reel, _row)| *reel)
            .filter(|r| effective_allowed.contains(r))
            .collect();

        // Need at least min_trigger_count triggers
        if trigger_reels.len() < self.min_trigger_count as usize {
            return vec![];
        }

        // Find the last (rightmost) trigger reel
        let last_trigger_reel = trigger_reels.iter().max().copied().unwrap_or(0);

        // Return all allowed reels AFTER the last trigger
        effective_allowed
            .into_iter()
            .filter(|&r| r > last_trigger_reel)
            .collect()
    }

    /// Calculate tension level for an anticipation reel
    ///
    /// Tension escalates with each subsequent anticipation reel:
    /// - First anticipation reel: L1
    /// - Second anticipation reel: L2
    /// - Third anticipation reel: L3
    /// - Fourth+ anticipation reel: L4
    pub fn tension_level_for_reel(&self, anticipation_reel_index: usize) -> TensionLevel {
        if !self.tension_escalation {
            return TensionLevel::L1;
        }
        TensionLevel::from_index((anticipation_reel_index + 1) as u8)
    }
}

/// Complete slot configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotConfig {
    /// Game name
    pub name: String,
    /// Grid specification
    pub grid: GridSpec,
    /// Volatility profile
    pub volatility: VolatilityProfile,
    /// Feature configuration
    pub features: FeatureConfig,
    /// Anticipation configuration (V2 — industry-standard per-reel tension)
    pub anticipation: AnticipationConfig,
    /// Default bet amount
    pub default_bet: f64,
    /// Available bet levels
    pub bet_levels: Vec<f64>,
    /// RTP target (for display, not enforced)
    pub target_rtp: f64,
}

impl Default for SlotConfig {
    fn default() -> Self {
        Self {
            name: "Synthetic Slot".into(),
            grid: GridSpec::default(),
            volatility: VolatilityProfile::default(),
            features: FeatureConfig::default(),
            anticipation: AnticipationConfig::default(),
            default_bet: 1.0,
            bet_levels: vec![0.20, 0.50, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0],
            target_rtp: 96.5,
        }
    }
}

impl SlotConfig {
    /// Create config for audio testing (high event frequency)
    pub fn audio_test() -> Self {
        Self {
            name: "Audio Test Mode".into(),
            volatility: VolatilityProfile::studio(),
            features: FeatureConfig {
                free_spins_enabled: true,
                free_spins_range: (3, 5),
                cascades_enabled: true,
                max_cascade_steps: 3,
                ..Default::default()
            },
            anticipation: AnticipationConfig::default(),
            ..Default::default()
        }
    }

    /// Create config with Tip A anticipation (scatter on all reels, 3+)
    pub fn with_tip_a_anticipation(mut self, scatter_id: u32, bonus_id: Option<u32>) -> Self {
        self.anticipation = AnticipationConfig::tip_a(scatter_id, bonus_id);
        self
    }

    /// Create config with Tip B anticipation (scatter on 0, 2, 4 only)
    pub fn with_tip_b_anticipation(mut self, scatter_id: u32, bonus_id: Option<u32>) -> Self {
        self.anticipation = AnticipationConfig::tip_b(scatter_id, bonus_id);
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grid_spec() {
        let grid = GridSpec::standard_5x3();
        assert_eq!(grid.total_positions(), 15);
        assert!(!grid.is_ways());

        let mega = GridSpec::megaways_6x4();
        assert!(mega.is_ways());
    }

    #[test]
    fn test_volatility_interpolate() {
        let low = VolatilityProfile::low();
        let high = VolatilityProfile::high();
        let mid = VolatilityProfile::interpolate(&low, &high, 0.5);

        assert!(mid.hit_rate > high.hit_rate);
        assert!(mid.hit_rate < low.hit_rate);
    }

    // =========================================================================
    // ANTICIPATION SYSTEM V2 TESTS
    // =========================================================================

    #[test]
    fn test_tension_level_properties() {
        assert_eq!(TensionLevel::L1.color_hex(), "#FFD700");
        assert_eq!(TensionLevel::L2.color_hex(), "#FFA500");
        assert_eq!(TensionLevel::L3.color_hex(), "#FF6347");
        assert_eq!(TensionLevel::L4.color_hex(), "#FF4500");

        assert_eq!(TensionLevel::L1.volume_multiplier(), 0.6);
        assert_eq!(TensionLevel::L4.volume_multiplier(), 0.9);

        assert_eq!(TensionLevel::L1.pitch_semitones(), 1);
        assert_eq!(TensionLevel::L4.pitch_semitones(), 4);
    }

    #[test]
    fn test_tension_level_escalation() {
        assert_eq!(TensionLevel::L1.escalate(), TensionLevel::L2);
        assert_eq!(TensionLevel::L2.escalate(), TensionLevel::L3);
        assert_eq!(TensionLevel::L3.escalate(), TensionLevel::L4);
        assert_eq!(TensionLevel::L4.escalate(), TensionLevel::L4); // Clamp at L4
    }

    #[test]
    fn test_tension_level_from_index() {
        assert_eq!(TensionLevel::from_index(0), TensionLevel::L1);
        assert_eq!(TensionLevel::from_index(1), TensionLevel::L1);
        assert_eq!(TensionLevel::from_index(2), TensionLevel::L2);
        assert_eq!(TensionLevel::from_index(3), TensionLevel::L3);
        assert_eq!(TensionLevel::from_index(4), TensionLevel::L4);
        assert_eq!(TensionLevel::from_index(99), TensionLevel::L4); // Clamp
    }

    #[test]
    fn test_anticipation_tip_a_all_reels() {
        // Tip A: Scatter can land on any reel, 3+ triggers
        let config = AnticipationConfig::tip_a(10, Some(11));

        // All reels should be allowed
        assert!(config.is_reel_allowed(0));
        assert!(config.is_reel_allowed(1));
        assert!(config.is_reel_allowed(2));
        assert!(config.is_reel_allowed(3));
        assert!(config.is_reel_allowed(4));

        // Effective allowed reels for 5-reel game
        let effective = config.effective_allowed_reels(5);
        assert_eq!(effective, vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn test_anticipation_tip_b_restricted_reels() {
        // Tip B: Scatter only on reels 0, 2, 4 (exactly 3)
        let config = AnticipationConfig::tip_b(10, None);

        // Only reels 0, 2, 4 should be allowed
        assert!(config.is_reel_allowed(0));
        assert!(!config.is_reel_allowed(1));
        assert!(config.is_reel_allowed(2));
        assert!(!config.is_reel_allowed(3));
        assert!(config.is_reel_allowed(4));

        // Effective allowed reels
        let effective = config.effective_allowed_reels(5);
        assert_eq!(effective, vec![0, 2, 4]);
    }

    #[test]
    fn test_anticipation_tip_a_two_scatters_on_reels_0_1() {
        // Tip A: Scatter on all reels
        // 2 scatters on reels 0 and 1 → anticipation on 2, 3, 4
        let config = AnticipationConfig::tip_a(10, None);
        let trigger_positions = vec![(0, 1), (1, 0)]; // Scatter on reel 0 and 1

        let antic_reels = config.calculate_anticipation_reels(&trigger_positions, 5);
        assert_eq!(antic_reels, vec![2, 3, 4]);
    }

    #[test]
    fn test_anticipation_tip_a_two_scatters_on_reels_0_2() {
        // Tip A: Scatter on all reels
        // 2 scatters on reels 0 and 2 → anticipation on 3, 4
        let config = AnticipationConfig::tip_a(10, None);
        let trigger_positions = vec![(0, 1), (2, 0)];

        let antic_reels = config.calculate_anticipation_reels(&trigger_positions, 5);
        assert_eq!(antic_reels, vec![3, 4]);
    }

    #[test]
    fn test_anticipation_tip_a_single_scatter_no_anticipation() {
        // Tip A: Only 1 scatter → no anticipation
        let config = AnticipationConfig::tip_a(10, None);
        let trigger_positions = vec![(0, 1)];

        let antic_reels = config.calculate_anticipation_reels(&trigger_positions, 5);
        assert!(antic_reels.is_empty());
    }

    #[test]
    fn test_anticipation_tip_b_two_scatters_on_0_and_2() {
        // Tip B: Scatter only on 0, 2, 4
        // 2 scatters on reels 0 and 2 → anticipation on 4
        let config = AnticipationConfig::tip_b(10, None);
        let trigger_positions = vec![(0, 1), (2, 0)];

        let antic_reels = config.calculate_anticipation_reels(&trigger_positions, 5);
        assert_eq!(antic_reels, vec![4]);
    }

    #[test]
    fn test_anticipation_tip_b_scatter_on_non_allowed_reel_ignored() {
        // Tip B: Scatter only on 0, 2, 4
        // Scatter on reel 1 (not allowed) should be ignored
        let config = AnticipationConfig::tip_b(10, None);
        let trigger_positions = vec![(0, 1), (1, 0)]; // Reel 1 not allowed!

        let antic_reels = config.calculate_anticipation_reels(&trigger_positions, 5);
        // Only 1 valid scatter → no anticipation
        assert!(antic_reels.is_empty());
    }

    #[test]
    fn test_anticipation_tip_b_scatter_only_on_0_no_anticipation() {
        // Tip B: Scatter only on 0, 2, 4
        // 1 scatter on reel 0 → no anticipation (need 2)
        let config = AnticipationConfig::tip_b(10, None);
        let trigger_positions = vec![(0, 1)];

        let antic_reels = config.calculate_anticipation_reels(&trigger_positions, 5);
        assert!(antic_reels.is_empty());
    }

    #[test]
    fn test_anticipation_no_reels_after_last_trigger() {
        // If scatters are on the last possible reels, no anticipation
        let config = AnticipationConfig::tip_a(10, None);
        let trigger_positions = vec![(3, 0), (4, 1)]; // Scatters on reels 3 and 4

        let antic_reels = config.calculate_anticipation_reels(&trigger_positions, 5);
        assert!(antic_reels.is_empty()); // No reels after 4
    }

    #[test]
    fn test_anticipation_tension_level_escalation() {
        let config = AnticipationConfig::default();

        // First anticipation reel: L1
        assert_eq!(config.tension_level_for_reel(0), TensionLevel::L1);
        // Second anticipation reel: L2
        assert_eq!(config.tension_level_for_reel(1), TensionLevel::L2);
        // Third anticipation reel: L3
        assert_eq!(config.tension_level_for_reel(2), TensionLevel::L3);
        // Fourth+ anticipation reel: L4
        assert_eq!(config.tension_level_for_reel(3), TensionLevel::L4);
        assert_eq!(config.tension_level_for_reel(10), TensionLevel::L4);
    }

    #[test]
    fn test_anticipation_tension_disabled() {
        let mut config = AnticipationConfig::default();
        config.tension_escalation = false;

        // All reels should be L1 when escalation is disabled
        assert_eq!(config.tension_level_for_reel(0), TensionLevel::L1);
        assert_eq!(config.tension_level_for_reel(1), TensionLevel::L1);
        assert_eq!(config.tension_level_for_reel(2), TensionLevel::L1);
    }

    #[test]
    fn test_is_trigger_symbol() {
        let config = AnticipationConfig::tip_a(10, Some(11));

        assert!(config.is_trigger_symbol(10)); // Scatter
        assert!(config.is_trigger_symbol(11)); // Bonus
        assert!(!config.is_trigger_symbol(9)); // Wild - NOT a trigger
        assert!(!config.is_trigger_symbol(0)); // Random symbol
    }

    #[test]
    fn test_slot_config_with_anticipation() {
        let config = SlotConfig::default().with_tip_a_anticipation(10, Some(11));

        assert!(config.anticipation.is_trigger_symbol(10));
        assert!(config.anticipation.is_trigger_symbol(11));
        assert!(config.anticipation.allowed_reels.is_none());

        let config_b = SlotConfig::default().with_tip_b_anticipation(10, None);

        assert_eq!(config_b.anticipation.allowed_reels, Some(vec![0, 2, 4]));
    }
}

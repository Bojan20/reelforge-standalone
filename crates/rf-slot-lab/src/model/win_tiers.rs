//! Win Tiers — Win categorization and thresholds
//!
//! # P5 Win Tier System
//!
//! **Regular Wins (< 20x bet):**
//! - WIN_LOW: < 1x bet (sub-bet win)
//! - WIN_EQUAL: = 1x bet (push)
//! - WIN_1 through WIN_6: 1x to 20x bet
//!
//! **Big Wins (20x+ bet):**
//! - Single BIG_WIN with 5 internal tiers
//! - Configurable escalation through tiers
//!
//! All display labels are user-editable - no hardcoded names!

use serde::{Deserialize, Serialize};

// ============================================================================
// P5 Regular Win Tier Definition
// ============================================================================

/// Definition of a single regular win tier (P5 system)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegularWinTier {
    /// Tier ID (-1=LOW, 0=EQUAL, 1-6=regular tiers)
    pub tier_id: i32,

    /// Minimum multiplier (inclusive)
    pub from_multiplier: f64,

    /// Maximum multiplier (exclusive, last tier uses infinity)
    pub to_multiplier: f64,

    /// User-editable display label (no hardcoded names!)
    #[serde(default)]
    pub display_label: String,

    /// Rollup duration in milliseconds
    #[serde(default = "default_rollup_duration")]
    pub rollup_duration_ms: u32,

    /// Rollup tick rate (ticks per second)
    #[serde(default = "default_rollup_tick_rate")]
    pub rollup_tick_rate: u32,

    /// Particle burst count for celebration
    #[serde(default)]
    pub particle_burst_count: u32,
}

fn default_rollup_duration() -> u32 {
    1000
}

fn default_rollup_tick_rate() -> u32 {
    15
}

impl RegularWinTier {
    /// Create a new regular win tier
    pub fn new(
        tier_id: i32,
        from_multiplier: f64,
        to_multiplier: f64,
        display_label: impl Into<String>,
    ) -> Self {
        Self {
            tier_id,
            from_multiplier,
            to_multiplier,
            display_label: display_label.into(),
            rollup_duration_ms: default_rollup_duration(),
            rollup_tick_rate: default_rollup_tick_rate(),
            particle_burst_count: 0,
        }
    }

    /// Get stage name for this tier
    pub fn stage_name(&self) -> String {
        match self.tier_id {
            -1 => "WIN_LOW".to_string(),
            0 => "WIN_EQUAL".to_string(),
            n => format!("WIN_{}", n),
        }
    }

    /// Get win present stage name
    pub fn present_stage_name(&self) -> String {
        match self.tier_id {
            -1 => "WIN_PRESENT_LOW".to_string(),
            0 => "WIN_PRESENT_EQUAL".to_string(),
            n => format!("WIN_PRESENT_{}", n),
        }
    }

    /// Get rollup start stage name (None for WIN_LOW which is instant)
    pub fn rollup_start_stage_name(&self) -> Option<String> {
        if self.tier_id == -1 {
            None
        } else {
            let suffix = if self.tier_id == 0 { "EQUAL".to_string() } else { self.tier_id.to_string() };
            Some(format!("ROLLUP_START_{}", suffix))
        }
    }

    /// Check if win amount falls into this tier
    pub fn matches(&self, win_amount: f64, bet_amount: f64) -> bool {
        if bet_amount <= 0.0 {
            return false;
        }
        let multiplier = win_amount / bet_amount;
        multiplier >= self.from_multiplier && multiplier < self.to_multiplier
    }
}

// ============================================================================
// P5 Big Win Tier Definition
// ============================================================================

/// Definition of a single big win tier (internal escalation tier)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BigWinTier {
    /// Tier ID (1-5)
    pub tier_id: u32,

    /// Minimum multiplier (inclusive)
    pub from_multiplier: f64,

    /// Maximum multiplier (exclusive, tier 5 = infinity)
    pub to_multiplier: f64,

    /// User-editable display label (empty by default)
    #[serde(default)]
    pub display_label: String,

    /// Duration in milliseconds
    #[serde(default = "default_big_win_duration")]
    pub duration_ms: u32,

    /// Rollup tick rate during this tier
    #[serde(default = "default_big_win_tick_rate")]
    pub rollup_tick_rate: u32,

    /// Visual intensity multiplier (1.0 - 2.0)
    #[serde(default = "default_visual_intensity")]
    pub visual_intensity: f64,

    /// Particle effects multiplier
    #[serde(default = "default_particle_multiplier")]
    pub particle_multiplier: f64,

    /// Audio intensity (1.0 - 2.0)
    #[serde(default = "default_audio_intensity")]
    pub audio_intensity: f64,
}

fn default_big_win_duration() -> u32 {
    4000
}

fn default_big_win_tick_rate() -> u32 {
    10
}

fn default_visual_intensity() -> f64 {
    1.0
}

fn default_particle_multiplier() -> f64 {
    1.0
}

fn default_audio_intensity() -> f64 {
    1.0
}

impl BigWinTier {
    /// Create a new big win tier
    pub fn new(tier_id: u32, from_multiplier: f64, to_multiplier: f64) -> Self {
        Self {
            tier_id,
            from_multiplier,
            to_multiplier,
            display_label: String::new(),
            duration_ms: default_big_win_duration(),
            rollup_tick_rate: default_big_win_tick_rate(),
            visual_intensity: default_visual_intensity(),
            particle_multiplier: default_particle_multiplier(),
            audio_intensity: default_audio_intensity(),
        }
    }

    /// Get stage name for this tier
    pub fn stage_name(&self) -> String {
        format!("BIG_WIN_TIER_{}", self.tier_id)
    }

    /// Check if win amount falls into this tier
    pub fn matches(&self, win_amount: f64, bet_amount: f64) -> bool {
        if bet_amount <= 0.0 {
            return false;
        }
        let multiplier = win_amount / bet_amount;
        multiplier >= self.from_multiplier && multiplier < self.to_multiplier
    }
}

// ============================================================================
// P5 Big Win Configuration
// ============================================================================

/// Configuration for big win celebration system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BigWinConfig {
    /// Big win threshold multiplier (default 20x)
    #[serde(default = "default_big_win_threshold")]
    pub threshold: f64,

    /// Intro duration in milliseconds
    #[serde(default = "default_intro_duration")]
    pub intro_duration_ms: u32,

    /// End duration in milliseconds
    #[serde(default = "default_end_duration")]
    pub end_duration_ms: u32,

    /// Fade out duration in milliseconds
    #[serde(default = "default_fade_out_duration")]
    pub fade_out_duration_ms: u32,

    /// Tier definitions (ordered 1-5)
    pub tiers: Vec<BigWinTier>,
}

fn default_big_win_threshold() -> f64 {
    20.0
}

fn default_intro_duration() -> u32 {
    500
}

fn default_end_duration() -> u32 {
    4000
}

fn default_fade_out_duration() -> u32 {
    1000
}

impl BigWinConfig {
    /// Check if win qualifies for Big Win
    pub fn is_big_win(&self, win_amount: f64, bet_amount: f64) -> bool {
        if bet_amount <= 0.0 {
            return false;
        }
        let multiplier = win_amount / bet_amount;
        multiplier >= self.threshold
    }

    /// Get max tier for win amount (returns 0 if not a big win)
    pub fn get_max_tier(&self, win_amount: f64, bet_amount: f64) -> u32 {
        if !self.is_big_win(win_amount, bet_amount) {
            return 0;
        }

        let multiplier = win_amount / bet_amount;

        // Find highest tier that matches
        for tier in self.tiers.iter().rev() {
            if multiplier >= tier.from_multiplier {
                return tier.tier_id;
            }
        }
        1 // Default to tier 1 if big win but no tier matches
    }

    /// Get tier definition by ID
    pub fn get_tier(&self, tier_id: u32) -> Option<&BigWinTier> {
        self.tiers.iter().find(|t| t.tier_id == tier_id)
    }

    /// Get all tiers up to and including the max tier for this win
    pub fn get_tiers_for_win(&self, win_amount: f64, bet_amount: f64) -> Vec<&BigWinTier> {
        let max_tier = self.get_max_tier(win_amount, bet_amount);
        if max_tier == 0 {
            return Vec::new();
        }
        self.tiers.iter().filter(|t| t.tier_id <= max_tier).collect()
    }

    /// Calculate total celebration duration for a win
    pub fn get_total_duration_ms(&self, win_amount: f64, bet_amount: f64) -> u32 {
        let tiers = self.get_tiers_for_win(win_amount, bet_amount);
        if tiers.is_empty() {
            return 0;
        }

        let mut total = self.intro_duration_ms;
        for tier in tiers {
            total += tier.duration_ms;
        }
        total += self.end_duration_ms;
        total += self.fade_out_duration_ms;
        total
    }

    /// Default big win configuration based on industry research
    pub fn default_config() -> Self {
        Self {
            threshold: 20.0,
            intro_duration_ms: 500,
            end_duration_ms: 4000,
            fade_out_duration_ms: 1000,
            tiers: vec![
                BigWinTier {
                    tier_id: 1,
                    from_multiplier: 20.0,
                    to_multiplier: 50.0,
                    display_label: String::new(),
                    duration_ms: 4000,
                    rollup_tick_rate: 12,
                    visual_intensity: 1.0,
                    particle_multiplier: 1.0,
                    audio_intensity: 1.0,
                },
                BigWinTier {
                    tier_id: 2,
                    from_multiplier: 50.0,
                    to_multiplier: 100.0,
                    display_label: String::new(),
                    duration_ms: 4000,
                    rollup_tick_rate: 10,
                    visual_intensity: 1.2,
                    particle_multiplier: 1.5,
                    audio_intensity: 1.1,
                },
                BigWinTier {
                    tier_id: 3,
                    from_multiplier: 100.0,
                    to_multiplier: 250.0,
                    display_label: String::new(),
                    duration_ms: 4000,
                    rollup_tick_rate: 8,
                    visual_intensity: 1.4,
                    particle_multiplier: 2.0,
                    audio_intensity: 1.2,
                },
                BigWinTier {
                    tier_id: 4,
                    from_multiplier: 250.0,
                    to_multiplier: 500.0,
                    display_label: String::new(),
                    duration_ms: 4000,
                    rollup_tick_rate: 6,
                    visual_intensity: 1.6,
                    particle_multiplier: 2.5,
                    audio_intensity: 1.3,
                },
                BigWinTier {
                    tier_id: 5,
                    from_multiplier: 500.0,
                    to_multiplier: f64::INFINITY,
                    display_label: String::new(),
                    duration_ms: 4000,
                    rollup_tick_rate: 4,
                    visual_intensity: 2.0,
                    particle_multiplier: 3.0,
                    audio_intensity: 1.5,
                },
            ],
        }
    }
}

impl Default for BigWinConfig {
    fn default() -> Self {
        Self::default_config()
    }
}

// ============================================================================
// P5 Regular Win Configuration
// ============================================================================

/// Configuration for all regular win tiers (P5 system)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegularWinConfig {
    /// Config ID (e.g., "default", "high_volatility", "gdd_imported")
    #[serde(default = "default_config_id")]
    pub config_id: String,

    /// Display name for this config
    #[serde(default = "default_config_name")]
    pub name: String,

    /// List of tier definitions (ordered by from_multiplier)
    pub tiers: Vec<RegularWinTier>,
}

fn default_config_id() -> String {
    "default".to_string()
}

fn default_config_name() -> String {
    "Standard".to_string()
}

impl RegularWinConfig {
    /// Get tier for given win/bet amounts
    pub fn get_tier(&self, win_amount: f64, bet_amount: f64) -> Option<&RegularWinTier> {
        self.tiers.iter().find(|t| t.matches(win_amount, bet_amount))
    }

    /// Default configuration with standard win tiers
    pub fn default_config() -> Self {
        Self {
            config_id: "default".to_string(),
            name: "Standard".to_string(),
            tiers: vec![
                // WIN_LOW: < 1x bet (sub-bet win)
                RegularWinTier {
                    tier_id: -1,
                    display_label: String::new(),
                    from_multiplier: 0.0,
                    to_multiplier: 1.0,
                    rollup_duration_ms: 0, // Instant
                    rollup_tick_rate: 0,
                    particle_burst_count: 0,
                },
                // WIN_EQUAL: = 1x bet (push)
                RegularWinTier {
                    tier_id: 0,
                    display_label: "PUSH".to_string(),
                    from_multiplier: 1.0,
                    to_multiplier: 1.001,
                    rollup_duration_ms: 500,
                    rollup_tick_rate: 20,
                    particle_burst_count: 0,
                },
                // WIN_1: 1x < w ≤ 2x
                RegularWinTier {
                    tier_id: 1,
                    display_label: "WIN".to_string(),
                    from_multiplier: 1.001,
                    to_multiplier: 2.0,
                    rollup_duration_ms: 800,
                    rollup_tick_rate: 18,
                    particle_burst_count: 5,
                },
                // WIN_2: 2x < w ≤ 3x
                RegularWinTier {
                    tier_id: 2,
                    display_label: "WIN".to_string(),
                    from_multiplier: 2.0,
                    to_multiplier: 3.0,
                    rollup_duration_ms: 1000,
                    rollup_tick_rate: 16,
                    particle_burst_count: 8,
                },
                // WIN_3: 3x < w ≤ 5x
                RegularWinTier {
                    tier_id: 3,
                    display_label: "NICE".to_string(),
                    from_multiplier: 3.0,
                    to_multiplier: 5.0,
                    rollup_duration_ms: 1200,
                    rollup_tick_rate: 15,
                    particle_burst_count: 12,
                },
                // WIN_4: 5x < w ≤ 8x
                RegularWinTier {
                    tier_id: 4,
                    display_label: "NICE WIN".to_string(),
                    from_multiplier: 5.0,
                    to_multiplier: 8.0,
                    rollup_duration_ms: 1500,
                    rollup_tick_rate: 14,
                    particle_burst_count: 18,
                },
                // WIN_5: 8x < w ≤ 12x
                RegularWinTier {
                    tier_id: 5,
                    display_label: "GREAT WIN".to_string(),
                    from_multiplier: 8.0,
                    to_multiplier: 12.0,
                    rollup_duration_ms: 2000,
                    rollup_tick_rate: 12,
                    particle_burst_count: 25,
                },
                // WIN_6: 12x < w ≤ 20x
                RegularWinTier {
                    tier_id: 6,
                    display_label: "SUPER WIN".to_string(),
                    from_multiplier: 12.0,
                    to_multiplier: 20.0,
                    rollup_duration_ms: 2500,
                    rollup_tick_rate: 10,
                    particle_burst_count: 35,
                },
            ],
        }
    }
}

impl Default for RegularWinConfig {
    fn default() -> Self {
        Self::default_config()
    }
}

// ============================================================================
// P5 Combined Configuration
// ============================================================================

/// Combined configuration for all win tiers (regular + big win) - P5 System
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotWinConfig {
    /// Regular win tier configuration
    pub regular_wins: RegularWinConfig,

    /// Big win configuration
    pub big_wins: BigWinConfig,
}

impl SlotWinConfig {
    /// Get regular tier for win (returns None if big win)
    pub fn get_regular_tier(&self, win_amount: f64, bet_amount: f64) -> Option<&RegularWinTier> {
        if self.big_wins.is_big_win(win_amount, bet_amount) {
            return None;
        }
        self.regular_wins.get_tier(win_amount, bet_amount)
    }

    /// Check if win qualifies for big win
    pub fn is_big_win(&self, win_amount: f64, bet_amount: f64) -> bool {
        self.big_wins.is_big_win(win_amount, bet_amount)
    }

    /// Get max big win tier (0 if not a big win)
    pub fn get_big_win_max_tier(&self, win_amount: f64, bet_amount: f64) -> u32 {
        self.big_wins.get_max_tier(win_amount, bet_amount)
    }

    /// Evaluate win amount against bet and return tier result
    pub fn evaluate(&self, win_amount: f64, bet_amount: f64) -> WinTierResult {
        // No win
        if win_amount <= 0.0 || bet_amount <= 0.0 {
            return WinTierResult {
                is_big_win: false,
                multiplier: 0.0,
                regular_tier_id: None,
                big_win_max_tier: None,
                primary_stage: "NO_WIN".to_string(),
                display_label: String::new(),
                rollup_duration_ms: 0,
            };
        }

        let multiplier = win_amount / bet_amount;

        // Check for big win first
        if self.is_big_win(win_amount, bet_amount) {
            let max_tier = self.big_wins.get_max_tier(win_amount, bet_amount);
            if let Some(tier) = self.big_wins.get_tier(max_tier) {
                return WinTierResult::big_win(max_tier, tier, multiplier);
            }
            // Fallback if tier not found (shouldn't happen)
            return WinTierResult {
                is_big_win: true,
                multiplier,
                regular_tier_id: None,
                big_win_max_tier: Some(max_tier),
                primary_stage: "BIG_WIN_INTRO".to_string(),
                display_label: String::new(),
                rollup_duration_ms: 4000,
            };
        }

        // Regular win
        if let Some(tier) = self.get_regular_tier(win_amount, bet_amount) {
            return WinTierResult::regular(tier, multiplier);
        }

        // Fallback for edge cases (e.g., win_amount < bet_amount but > 0)
        WinTierResult {
            is_big_win: false,
            multiplier,
            regular_tier_id: Some(-1),
            big_win_max_tier: None,
            primary_stage: "WIN_LOW".to_string(),
            display_label: String::new(),
            rollup_duration_ms: 0,
        }
    }

    /// Validate configuration - returns true if valid
    pub fn validate(&self) -> bool {
        self.validation_errors().is_empty()
    }

    /// Get list of validation errors
    pub fn validation_errors(&self) -> Vec<String> {
        let mut errors = Vec::new();

        // Check regular win tiers
        if self.regular_wins.tiers.is_empty() {
            errors.push("No regular win tiers defined".to_string());
        }

        // Check for gaps in regular tier ranges
        let mut sorted_regular: Vec<_> = self.regular_wins.tiers.iter().collect();
        sorted_regular.sort_by(|a, b| {
            a.from_multiplier
                .partial_cmp(&b.from_multiplier)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        for i in 0..sorted_regular.len().saturating_sub(1) {
            let current = sorted_regular[i];
            let next = sorted_regular[i + 1];
            if (current.to_multiplier - next.from_multiplier).abs() > 0.001 {
                errors.push(format!(
                    "Gap in regular tiers: {} to {} has gap at {}",
                    current.tier_id, next.tier_id, current.to_multiplier
                ));
            }
        }

        // Check regular tiers don't overlap with big win threshold
        if let Some(last_regular) = sorted_regular.last() {
            if last_regular.to_multiplier > self.big_wins.threshold {
                errors.push(format!(
                    "Regular tier {} extends beyond big win threshold {}",
                    last_regular.tier_id, self.big_wins.threshold
                ));
            }
        }

        // Check big win tiers
        if self.big_wins.tiers.is_empty() {
            errors.push("No big win tiers defined".to_string());
        }

        // Check big win tier ranges
        let mut sorted_big: Vec<_> = self.big_wins.tiers.iter().collect();
        sorted_big.sort_by(|a, b| {
            a.from_multiplier
                .partial_cmp(&b.from_multiplier)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        // First big tier should start at threshold
        if let Some(first_big) = sorted_big.first() {
            if (first_big.from_multiplier - self.big_wins.threshold).abs() > 0.001 {
                errors.push(format!(
                    "First big win tier starts at {} but threshold is {}",
                    first_big.from_multiplier, self.big_wins.threshold
                ));
            }
        }

        // Check for gaps in big tier ranges
        for i in 0..sorted_big.len().saturating_sub(1) {
            let current = sorted_big[i];
            let next = sorted_big[i + 1];
            if (current.to_multiplier - next.from_multiplier).abs() > 0.001 {
                errors.push(format!(
                    "Gap in big win tiers: {} to {} has gap at {}",
                    current.tier_id, next.tier_id, current.to_multiplier
                ));
            }
        }

        // Last big tier should extend to infinity
        if let Some(last_big) = sorted_big.last() {
            if !last_big.to_multiplier.is_infinite() {
                errors.push(format!(
                    "Last big win tier {} should extend to infinity, ends at {}",
                    last_big.tier_id, last_big.to_multiplier
                ));
            }
        }

        // Validate threshold is positive
        if self.big_wins.threshold <= 0.0 {
            errors.push("Big win threshold must be positive".to_string());
        }

        errors
    }

    /// Get all stage names for audio assignment
    pub fn all_stage_names(&self) -> Vec<String> {
        let mut stages = Vec::new();

        // Regular win stages
        for tier in &self.regular_wins.tiers {
            stages.push(tier.stage_name());
            stages.push(tier.present_stage_name());
            if let Some(rollup_start) = tier.rollup_start_stage_name() {
                stages.push(rollup_start);
                let suffix = if tier.tier_id == 0 {
                    "EQUAL".to_string()
                } else {
                    tier.tier_id.to_string()
                };
                stages.push(format!("ROLLUP_TICK_{}", suffix));
                stages.push(format!("ROLLUP_END_{}", suffix));
            }
        }

        // Big win stages
        stages.push("BIG_WIN_INTRO".to_string());
        for tier in &self.big_wins.tiers {
            stages.push(tier.stage_name());
        }
        stages.push("BIG_WIN_END".to_string());
        stages.push("BIG_WIN_FADE_OUT".to_string());
        stages.push("BIG_WIN_ROLLUP_TICK".to_string());

        stages
    }

    /// Default configuration
    pub fn default_config() -> Self {
        Self {
            regular_wins: RegularWinConfig::default_config(),
            big_wins: BigWinConfig::default_config(),
        }
    }
}

impl Default for SlotWinConfig {
    fn default() -> Self {
        Self::default_config()
    }
}

// ============================================================================
// P5 Win Tier Result
// ============================================================================

/// Result of win tier evaluation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTierResult {
    /// Whether this is a big win (20x+ by default)
    pub is_big_win: bool,

    /// Win multiplier (win / bet)
    pub multiplier: f64,

    /// Regular tier ID (None if big win)
    pub regular_tier_id: Option<i32>,

    /// Big win max tier (None if regular win)
    pub big_win_max_tier: Option<u32>,

    /// Primary stage name to trigger
    pub primary_stage: String,

    /// Display label
    pub display_label: String,

    /// Rollup duration in ms
    pub rollup_duration_ms: u32,
}

impl WinTierResult {
    /// Create result for a regular win
    pub fn regular(tier: &RegularWinTier, multiplier: f64) -> Self {
        Self {
            is_big_win: false,
            multiplier,
            regular_tier_id: Some(tier.tier_id),
            big_win_max_tier: None,
            primary_stage: tier.stage_name(),
            display_label: tier.display_label.clone(),
            rollup_duration_ms: tier.rollup_duration_ms,
        }
    }

    /// Create result for a big win
    pub fn big_win(max_tier: u32, tier: &BigWinTier, multiplier: f64) -> Self {
        Self {
            is_big_win: true,
            multiplier,
            regular_tier_id: None,
            big_win_max_tier: Some(max_tier),
            primary_stage: "BIG_WIN_INTRO".to_string(),
            display_label: tier.display_label.clone(),
            rollup_duration_ms: tier.duration_ms,
        }
    }
}

// ============================================================================
// LEGACY SUPPORT (M4 System - Backward Compatibility)
// ============================================================================

/// Win tier configuration (Legacy M4 system)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTierConfig {
    /// Individual tier definitions
    pub tiers: Vec<WinTier>,

    /// Multiplier for "small win" display threshold
    #[serde(default = "default_display_threshold")]
    pub display_threshold: f64,
}

fn default_display_threshold() -> f64 {
    1.0
}

impl WinTierConfig {
    /// Standard tier configuration
    pub fn standard() -> Self {
        Self {
            tiers: vec![
                WinTier::new("small", 1.0, 5.0),
                WinTier::new("medium", 5.0, 15.0),
                WinTier::new("big", 15.0, 25.0),
                WinTier::new("mega", 25.0, 50.0),
                WinTier::new("epic", 50.0, 100.0),
                WinTier::new("ultra", 100.0, f64::INFINITY),
            ],
            display_threshold: 1.0,
        }
    }

    /// High volatility tiers
    pub fn high_volatility() -> Self {
        Self {
            tiers: vec![
                WinTier::new("small", 1.0, 10.0),
                WinTier::new("medium", 10.0, 25.0),
                WinTier::new("big", 25.0, 50.0),
                WinTier::new("mega", 50.0, 100.0),
                WinTier::new("epic", 100.0, 250.0),
                WinTier::new("ultra", 250.0, f64::INFINITY),
            ],
            display_threshold: 2.0,
        }
    }

    /// Get tier for a given win ratio
    pub fn get_tier(&self, win_ratio: f64) -> Option<&WinTier> {
        self.tiers
            .iter()
            .find(|t| win_ratio >= t.min_ratio && win_ratio < t.max_ratio)
    }

    /// Get tier name for a given win ratio
    pub fn get_tier_name(&self, win_ratio: f64) -> Option<&str> {
        self.get_tier(win_ratio).map(|t| t.name.as_str())
    }

    /// Check if win ratio should show celebration
    pub fn should_celebrate(&self, win_ratio: f64) -> bool {
        win_ratio >= self.display_threshold
    }

    /// Get all tier names in order
    pub fn tier_names(&self) -> Vec<&str> {
        self.tiers.iter().map(|t| t.name.as_str()).collect()
    }
}

impl Default for WinTierConfig {
    fn default() -> Self {
        Self::standard()
    }
}

/// A single win tier definition (Legacy M4)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTier {
    /// Tier name (e.g., "big", "mega", "epic")
    pub name: String,

    /// Minimum win ratio (inclusive)
    pub min_ratio: f64,

    /// Maximum win ratio (exclusive)
    pub max_ratio: f64,

    /// Celebration duration multiplier
    #[serde(default = "default_celebration_mult")]
    pub celebration_duration_mult: f64,

    /// Audio event suffix
    #[serde(default)]
    pub audio_suffix: Option<String>,

    /// Visual effect intensity (0.0 - 1.0)
    #[serde(default = "default_effect_intensity")]
    pub effect_intensity: f64,
}

fn default_celebration_mult() -> f64 {
    1.0
}

fn default_effect_intensity() -> f64 {
    0.5
}

impl WinTier {
    /// Create a new win tier
    pub fn new(name: impl Into<String>, min_ratio: f64, max_ratio: f64) -> Self {
        let name = name.into();
        let celebration_mult = match name.as_str() {
            "small" => 1.0,
            "medium" => 1.2,
            "big" => 1.5,
            "mega" => 2.0,
            "epic" => 2.5,
            "ultra" => 3.0,
            _ => 1.0,
        };
        let effect_intensity = match name.as_str() {
            "small" => 0.2,
            "medium" => 0.4,
            "big" => 0.6,
            "mega" => 0.8,
            "epic" => 0.9,
            "ultra" => 1.0,
            _ => 0.5,
        };

        Self {
            audio_suffix: Some(format!("_{}", name)),
            name,
            min_ratio,
            max_ratio,
            celebration_duration_mult: celebration_mult,
            effect_intensity,
        }
    }

    /// Check if a win ratio falls in this tier
    pub fn contains(&self, win_ratio: f64) -> bool {
        win_ratio >= self.min_ratio && win_ratio < self.max_ratio
    }

    /// Get the center point of this tier
    pub fn center_ratio(&self) -> f64 {
        if self.max_ratio.is_infinite() {
            self.min_ratio * 1.5
        } else {
            (self.min_ratio + self.max_ratio) / 2.0
        }
    }
}

/// Predefined win tier enum (Legacy M4)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WinTierType {
    Small,
    Medium,
    Big,
    Mega,
    Epic,
    Ultra,
}

impl WinTierType {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Small => "Small Win",
            Self::Medium => "Medium Win",
            Self::Big => "Big Win",
            Self::Mega => "Mega Win",
            Self::Epic => "Epic Win",
            Self::Ultra => "Ultra Win",
        }
    }

    /// Get from win ratio using standard thresholds
    pub fn from_ratio(ratio: f64) -> Option<Self> {
        match ratio {
            r if r >= 100.0 => Some(Self::Ultra),
            r if r >= 50.0 => Some(Self::Epic),
            r if r >= 25.0 => Some(Self::Mega),
            r if r >= 15.0 => Some(Self::Big),
            r if r >= 5.0 => Some(Self::Medium),
            r if r >= 1.0 => Some(Self::Small),
            _ => None,
        }
    }

    /// Get tier index
    pub fn index(&self) -> u8 {
        match self {
            Self::Small => 0,
            Self::Medium => 1,
            Self::Big => 2,
            Self::Mega => 3,
            Self::Epic => 4,
            Self::Ultra => 5,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_regular_win_tier() {
        let config = RegularWinConfig::default_config();

        // Test tier matching
        assert!(config.get_tier(1.5, 1.0).is_some());
        let tier = config.get_tier(1.5, 1.0).unwrap();
        assert_eq!(tier.tier_id, 1);
        assert_eq!(tier.stage_name(), "WIN_1");

        // Test WIN_LOW
        let low_tier = config.get_tier(0.5, 1.0).unwrap();
        assert_eq!(low_tier.tier_id, -1);
        assert_eq!(low_tier.stage_name(), "WIN_LOW");
    }

    #[test]
    fn test_big_win_tiers() {
        let config = BigWinConfig::default_config();

        // Test threshold
        assert!(!config.is_big_win(15.0, 1.0)); // 15x - not big win
        assert!(config.is_big_win(25.0, 1.0));  // 25x - big win tier 1

        // Test max tier
        assert_eq!(config.get_max_tier(25.0, 1.0), 1);  // 25x = tier 1
        assert_eq!(config.get_max_tier(60.0, 1.0), 2);  // 60x = tier 2
        assert_eq!(config.get_max_tier(150.0, 1.0), 3); // 150x = tier 3
        assert_eq!(config.get_max_tier(300.0, 1.0), 4); // 300x = tier 4
        assert_eq!(config.get_max_tier(600.0, 1.0), 5); // 600x = tier 5
    }

    #[test]
    fn test_slot_win_config() {
        let config = SlotWinConfig::default_config();

        // Regular win
        assert!(!config.is_big_win(5.0, 1.0));
        let regular = config.get_regular_tier(5.0, 1.0);
        assert!(regular.is_some());

        // Big win
        assert!(config.is_big_win(25.0, 1.0));
        let regular_for_big = config.get_regular_tier(25.0, 1.0);
        assert!(regular_for_big.is_none()); // Returns None for big wins
    }

    #[test]
    fn test_stage_names() {
        let config = SlotWinConfig::default_config();
        let stages = config.all_stage_names();

        // Check regular win stages
        assert!(stages.contains(&"WIN_LOW".to_string()));
        assert!(stages.contains(&"WIN_1".to_string()));
        assert!(stages.contains(&"WIN_PRESENT_1".to_string()));
        assert!(stages.contains(&"ROLLUP_START_1".to_string()));

        // Check big win stages
        assert!(stages.contains(&"BIG_WIN_INTRO".to_string()));
        assert!(stages.contains(&"BIG_WIN_TIER_1".to_string()));
        assert!(stages.contains(&"BIG_WIN_TIER_5".to_string()));
        assert!(stages.contains(&"BIG_WIN_END".to_string()));
    }

    #[test]
    fn test_evaluate_no_win() {
        let config = SlotWinConfig::default_config();

        // No win (zero amount)
        let result = config.evaluate(0.0, 1.0);
        assert!(!result.is_big_win);
        assert_eq!(result.multiplier, 0.0);
        assert_eq!(result.primary_stage, "NO_WIN");

        // Invalid bet
        let result = config.evaluate(10.0, 0.0);
        assert_eq!(result.multiplier, 0.0);
    }

    #[test]
    fn test_evaluate_regular_wins() {
        let config = SlotWinConfig::default_config();

        // Small win (1.5x)
        let result = config.evaluate(1.5, 1.0);
        assert!(!result.is_big_win);
        assert_eq!(result.multiplier, 1.5);
        assert_eq!(result.regular_tier_id, Some(1));
        assert_eq!(result.primary_stage, "WIN_1");

        // Medium win (5x)
        let result = config.evaluate(5.0, 1.0);
        assert_eq!(result.regular_tier_id, Some(4));
        assert_eq!(result.primary_stage, "WIN_4");

        // Near big win threshold (19x)
        let result = config.evaluate(19.0, 1.0);
        assert!(!result.is_big_win);
        assert_eq!(result.regular_tier_id, Some(6));
        assert_eq!(result.primary_stage, "WIN_6");
    }

    #[test]
    fn test_evaluate_big_wins() {
        let config = SlotWinConfig::default_config();

        // Just over threshold (25x)
        let result = config.evaluate(25.0, 1.0);
        assert!(result.is_big_win);
        assert_eq!(result.big_win_max_tier, Some(1));
        assert_eq!(result.primary_stage, "BIG_WIN_INTRO");

        // Tier 2 (60x)
        let result = config.evaluate(60.0, 1.0);
        assert!(result.is_big_win);
        assert_eq!(result.big_win_max_tier, Some(2));

        // Tier 5 (max - 600x)
        let result = config.evaluate(600.0, 1.0);
        assert!(result.is_big_win);
        assert_eq!(result.big_win_max_tier, Some(5));
    }

    #[test]
    fn test_validate_default_config() {
        let config = SlotWinConfig::default_config();
        assert!(config.validate());
        assert!(config.validation_errors().is_empty());
    }

    #[test]
    fn test_validate_invalid_config() {
        let mut config = SlotWinConfig::default_config();

        // Remove all big win tiers
        config.big_wins.tiers.clear();

        let errors = config.validation_errors();
        assert!(!errors.is_empty());
        assert!(errors.iter().any(|e| e.contains("No big win tiers")));
    }

    #[test]
    fn test_validate_threshold_mismatch() {
        let mut config = SlotWinConfig::default_config();

        // Change threshold but not tier ranges
        config.big_wins.threshold = 50.0;

        let errors = config.validation_errors();
        assert!(!errors.is_empty());
        assert!(errors.iter().any(|e| e.contains("threshold")));
    }

    // Legacy tests
    #[test]
    fn test_legacy_win_tier_config() {
        let config = WinTierConfig::standard();

        assert_eq!(config.get_tier_name(2.0), Some("small"));
        assert_eq!(config.get_tier_name(10.0), Some("medium"));
        assert_eq!(config.get_tier_name(20.0), Some("big"));
        assert_eq!(config.get_tier_name(30.0), Some("mega"));
        assert_eq!(config.get_tier_name(75.0), Some("epic"));
        assert_eq!(config.get_tier_name(150.0), Some("ultra"));
        assert_eq!(config.get_tier_name(0.5), None);
    }
}

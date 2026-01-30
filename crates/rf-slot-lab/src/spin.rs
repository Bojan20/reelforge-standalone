//! Spin result and stage event generation

use serde::{Deserialize, Serialize};

/// Default total reels (5) for anticipation calculations
fn default_total_reels() -> u8 {
    5
}

use rf_stage::{
    BigWinTier, FeatureType, JackpotTier, Stage, StageEvent, StagePayload,
};

use crate::paytable::{EvaluationResult, LineWin, ScatterWin};
use crate::timing::TimestampGenerator;

/// Complete spin result with all outcomes
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpinResult {
    /// Spin ID
    pub spin_id: String,
    /// Final grid (reels × rows)
    pub grid: Vec<Vec<u32>>,
    /// Bet amount
    pub bet: f64,
    /// Total win
    pub total_win: f64,
    /// Win-to-bet ratio
    pub win_ratio: f64,
    /// Line wins
    pub line_wins: Vec<LineWin>,
    /// Scatter win
    pub scatter_win: Option<ScatterWin>,
    /// Big win tier (if applicable)
    pub big_win_tier: Option<BigWinTier>,
    /// Win tier name from GameModel (e.g., "small", "big", "mega")
    #[serde(default)]
    pub win_tier_name: Option<String>,
    /// Feature triggered
    pub feature_triggered: Option<TriggeredFeature>,
    /// Jackpot won
    pub jackpot_won: Option<JackpotWin>,
    /// Cascade results (if cascades occurred)
    pub cascades: Vec<CascadeResult>,
    /// Was this a near miss?
    pub near_miss: bool,
    /// Reel anticipation info
    pub anticipation: Option<AnticipationInfo>,
    /// Is this a free spin (within feature)?
    pub is_free_spin: bool,
    /// Free spin index (if applicable)
    pub free_spin_index: Option<u32>,
    /// Current multiplier
    pub multiplier: f64,
}

/// Triggered feature info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggeredFeature {
    pub feature_type: FeatureType,
    pub total_spins: u32,
    pub multiplier: f64,
}

/// Jackpot win info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JackpotWin {
    pub tier: JackpotTier,
    pub amount: f64,
}

/// Cascade step result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CascadeResult {
    pub step_index: u32,
    pub grid: Vec<Vec<u32>>,
    pub win: f64,
    pub multiplier: f64,
}

/// Reason for anticipation trigger
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnticipationReason {
    /// Scatter symbols detected (most common)
    Scatter,
    /// Bonus symbols detected
    Bonus,
    /// Wild symbols detected (expanding wild, etc.)
    Wild,
    /// Jackpot symbols detected
    Jackpot,
    /// Near miss anticipation
    NearMiss,
    /// Custom reason (game-specific)
    Custom,
}

impl Default for AnticipationReason {
    fn default() -> Self {
        Self::Scatter
    }
}

impl AnticipationReason {
    /// Convert to string for legacy compatibility
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Scatter => "scatter",
            Self::Bonus => "bonus",
            Self::Wild => "wild",
            Self::Jackpot => "jackpot",
            Self::NearMiss => "near_miss",
            Self::Custom => "custom",
        }
    }

    /// Parse from string (case-insensitive)
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "scatter" => Self::Scatter,
            "bonus" => Self::Bonus,
            "wild" => Self::Wild,
            "jackpot" => Self::Jackpot,
            "near_miss" | "nearmiss" => Self::NearMiss,
            _ => Self::Custom,
        }
    }

    /// Get audio intensity layer for this reason (1-4)
    /// Higher = more important = louder tension
    pub fn base_intensity(&self) -> u8 {
        match self {
            Self::Jackpot => 4,    // Highest priority
            Self::Bonus => 3,
            Self::Scatter => 2,
            Self::Wild => 2,
            Self::NearMiss => 1,
            Self::Custom => 1,
        }
    }
}

/// Per-reel anticipation data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelAnticipation {
    /// Which reel (0-indexed)
    pub reel_index: u8,
    /// Tension layer level (1-4, escalates per reel)
    pub tension_level: u8,
    /// Progress through anticipation (0.0 - 1.0)
    pub progress: f32,
    /// Duration for this reel's anticipation (ms)
    pub duration_ms: u32,
}

/// Anticipation info — enhanced for per-reel system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnticipationInfo {
    /// Which reels had anticipation (legacy compatibility)
    pub reels: Vec<u8>,
    /// Reason enum (new)
    #[serde(default)]
    pub reason_type: AnticipationReason,
    /// Reason string (legacy compatibility)
    pub reason: String,
    /// Number of trigger symbols detected (e.g., 2 scatters)
    #[serde(default)]
    pub trigger_count: u8,
    /// Positions of trigger symbols [(reel, row), ...]
    #[serde(default)]
    pub trigger_positions: Vec<(u8, u8)>,
    /// Per-reel anticipation data (new)
    #[serde(default)]
    pub reel_data: Vec<ReelAnticipation>,
    /// Total number of reels in the game (for calculating intensity)
    #[serde(default = "default_total_reels")]
    pub total_reels: u8,
}

impl AnticipationInfo {
    /// Create anticipation info for scatter-based anticipation
    ///
    /// When 2+ scatters detected, anticipation triggers on ALL remaining reels.
    /// Example: Scatters on reel 0,1 → anticipation on reels 2,3,4
    /// Example: Scatters on reel 0,3 → anticipation on reels 4,5 (if exists)
    pub fn from_scatter_positions(
        scatter_positions: Vec<(u8, u8)>,
        total_reels: u8,
        base_duration_ms: u32,
    ) -> Option<Self> {
        if scatter_positions.len() < 2 {
            return None; // Need at least 2 scatters for anticipation
        }

        // Find the rightmost reel with a scatter
        let last_scatter_reel = scatter_positions.iter()
            .map(|(reel, _)| *reel)
            .max()
            .unwrap_or(0);

        // Anticipation happens on ALL reels AFTER the last scatter
        let anticipation_reels: Vec<u8> = ((last_scatter_reel + 1)..total_reels).collect();

        if anticipation_reels.is_empty() {
            return None; // No reels left for anticipation
        }

        // Build per-reel anticipation data with escalating tension
        let reel_data: Vec<ReelAnticipation> = anticipation_reels.iter()
            .enumerate()
            .map(|(idx, &reel)| {
                // Tension level escalates: first anticipation reel = L1, second = L2, etc.
                // Capped at L4 for maximum tension
                let tension_level = ((idx + 1) as u8).min(4);

                ReelAnticipation {
                    reel_index: reel,
                    tension_level,
                    progress: 0.0,
                    duration_ms: base_duration_ms,
                }
            })
            .collect();

        Some(Self {
            reels: anticipation_reels,
            reason_type: AnticipationReason::Scatter,
            reason: "scatter".to_string(),
            trigger_count: scatter_positions.len() as u8,
            trigger_positions: scatter_positions,
            reel_data,
            total_reels,
        })
    }

    /// Create anticipation from a generic reason and reel indices
    pub fn from_reels(
        reels: Vec<u8>,
        reason: AnticipationReason,
        total_reels: u8,
        base_duration_ms: u32,
    ) -> Self {
        let reel_data: Vec<ReelAnticipation> = reels.iter()
            .enumerate()
            .map(|(idx, &reel)| {
                let tension_level = ((idx + 1) as u8).min(4);
                ReelAnticipation {
                    reel_index: reel,
                    tension_level,
                    progress: 0.0,
                    duration_ms: base_duration_ms,
                }
            })
            .collect();

        Self {
            reels: reels.clone(),
            reason_type: reason,
            reason: reason.as_str().to_string(),
            trigger_count: 0,
            trigger_positions: Vec::new(),
            reel_data,
            total_reels,
        }
    }

    /// Get tension level for a specific reel (1-4, or 0 if not in anticipation)
    pub fn tension_level_for_reel(&self, reel_index: u8) -> u8 {
        self.reel_data.iter()
            .find(|r| r.reel_index == reel_index)
            .map(|r| r.tension_level)
            .unwrap_or(0)
    }

    /// Check if a specific reel is in anticipation
    pub fn has_reel(&self, reel_index: u8) -> bool {
        self.reels.contains(&reel_index)
    }

    /// Get the first reel in anticipation
    pub fn first_anticipation_reel(&self) -> Option<u8> {
        self.reels.first().copied()
    }

    /// Get the last reel in anticipation
    pub fn last_anticipation_reel(&self) -> Option<u8> {
        self.reels.last().copied()
    }

    /// Get color progression hex for a reel based on its position in anticipation sequence
    /// Returns: Gold → Orange → Red-Orange → Red
    pub fn color_for_reel(&self, reel_index: u8) -> &'static str {
        let tension = self.tension_level_for_reel(reel_index);
        match tension {
            1 => "#FFD700", // Gold
            2 => "#FFA500", // Orange
            3 => "#FF6347", // Red-Orange (Tomato)
            4 => "#FF4500", // Red (OrangeRed)
            _ => "#FFD700", // Default gold
        }
    }

    /// Get pitch multiplier for RTPC based on reel position
    /// Returns semitones to add: R2=+1st, R3=+2st, R4=+3st, R5=+4st
    pub fn pitch_semitones_for_reel(&self, reel_index: u8) -> f32 {
        let tension = self.tension_level_for_reel(reel_index);
        tension as f32
    }

    /// Get volume multiplier for this reel's tension layer
    /// L1=0.6, L2=0.7, L3=0.8, L4=0.9
    pub fn volume_for_reel(&self, reel_index: u8) -> f32 {
        let tension = self.tension_level_for_reel(reel_index);
        match tension {
            1 => 0.6,
            2 => 0.7,
            3 => 0.8,
            4 => 0.9,
            _ => 0.5,
        }
    }
}

impl SpinResult {
    /// Create a new spin result
    pub fn new(spin_id: String, grid: Vec<Vec<u32>>, bet: f64) -> Self {
        Self {
            spin_id,
            grid,
            bet,
            total_win: 0.0,
            win_ratio: 0.0,
            line_wins: Vec::new(),
            scatter_win: None,
            big_win_tier: None,
            win_tier_name: None,
            feature_triggered: None,
            jackpot_won: None,
            cascades: Vec::new(),
            near_miss: false,
            anticipation: None,
            is_free_spin: false,
            free_spin_index: None,
            multiplier: 1.0,
        }
    }

    /// Apply evaluation result
    pub fn with_evaluation(mut self, eval: EvaluationResult) -> Self {
        self.line_wins = eval.line_wins;
        self.scatter_win = eval.scatter_win;
        self.total_win = eval.total_win * self.multiplier;
        self.win_ratio = if self.bet > 0.0 {
            self.total_win / self.bet
        } else {
            0.0
        };
        self
    }

    /// Set big win tier based on ratio
    pub fn with_big_win_tier(mut self, thresholds: &crate::config::WinTierThresholds) -> Self {
        if self.win_ratio >= thresholds.ultra_win {
            self.big_win_tier = Some(BigWinTier::UltraWin);
        } else if self.win_ratio >= thresholds.epic_win {
            self.big_win_tier = Some(BigWinTier::EpicWin);
        } else if self.win_ratio >= thresholds.mega_win {
            self.big_win_tier = Some(BigWinTier::MegaWin);
        } else if self.win_ratio >= thresholds.big_win {
            self.big_win_tier = Some(BigWinTier::BigWin);
        } else if self.total_win > 0.0 {
            self.big_win_tier = Some(BigWinTier::Win);
        }
        self
    }

    /// Check if this is a win
    pub fn is_win(&self) -> bool {
        self.total_win > 0.0
    }

    /// Generate all stage events for this spin
    pub fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let mut events = Vec::new();

        // DEBUG: Log timing config for troubleshooting
        log::debug!("[SpinResult::generate_stages] Starting with {} reels, timing.current={}ms",
            self.grid.len(), timing.current());

        // 1. Spin Start
        events.push(StageEvent::new(Stage::SpinStart, timing.current()));

        // 2. P0.1: Per-reel spinning START events (one loop per reel for independent fade-out)
        // Each reel starts at slightly staggered time for stereo spread effect
        // When REEL_SPINNING_STOP_N fires, only that reel's loop is faded out
        //
        // CRITICAL FIX: Capture base time ONCE and reuse for all reels
        // Previously called timing.reel_spin(0) twice per reel which advanced timeline incorrectly
        let reel_count = self.grid.len() as u8;
        let spin_start_base = timing.reel_spin(0); // Single advance for all reels
        for reel in 0..reel_count {
            // Small stagger (10ms per reel) for audio spread, all reels start nearly together
            let stagger_ms = (reel as f64) * 10.0;
            let spin_time = spin_start_base + stagger_ms;

            // ReelSpinningStart triggers the per-reel spin loop audio
            events.push(StageEvent::new(
                Stage::ReelSpinningStart { reel_index: reel },
                spin_time,
            ));
            // Also emit legacy ReelSpinning for backwards compatibility (SAME timestamp)
            events.push(StageEvent::new(
                Stage::ReelSpinning { reel_index: reel },
                spin_time,
            ));
        }

        // 3. Reel Stop events (with anticipation if applicable)
        // CRITICAL FIX: Capture stop time ONCE per reel and reuse
        // Previously called timing.reel_stop(reel) twice which doubled the timeline advancement
        for reel in 0..reel_count {
            // Check for anticipation BEFORE calculating stop time
            // Anticipation extends the stop delay for this reel
            let has_anticipation = self.anticipation.as_ref()
                .map(|a| a.reels.contains(&reel))
                .unwrap_or(false);

            if has_anticipation {
                let antic = self.anticipation.as_ref().unwrap();
                let tension_level = antic.tension_level_for_reel(reel);

                // Anticipation ON happens at current timeline position (before stop)
                let antic_time = timing.anticipation_start();
                events.push(StageEvent::new(
                    Stage::AnticipationOn {
                        reel_index: reel,
                        reason: Some(antic.reason.clone()),
                    },
                    antic_time,
                ));

                // Generate AnticipationTensionLayer stage for audio escalation
                // Tension level escalates per reel: L1 → L2 → L3 → L4
                if tension_level > 0 {
                    events.push(StageEvent::new(
                        Stage::AnticipationTensionLayer {
                            reel_index: reel,
                            tension_level,
                            reason: Some(antic.reason.clone()),
                            progress: 0.0,
                        },
                        antic_time,
                    ));

                    // Also generate progress updates during anticipation (0.0 → 0.5 → 1.0)
                    let antic_duration = timing.config().anticipation_duration_ms;
                    let progress_50_time = antic_time + (antic_duration * 0.5);
                    events.push(StageEvent::new(
                        Stage::AnticipationTensionLayer {
                            reel_index: reel,
                            tension_level,
                            reason: Some(antic.reason.clone()),
                            progress: 0.5,
                        },
                        progress_50_time,
                    ));
                }

                // Anticipation OFF after duration (timeline advances)
                let antic_end = timing.anticipation_end();
                events.push(StageEvent::new(
                    Stage::AnticipationOff { reel_index: reel },
                    antic_end,
                ));
            }

            // CRITICAL: Capture stop time ONCE and reuse for both events
            let stop_time = timing.reel_stop(reel);

            // DEBUG: Log reel stop times for troubleshooting timing issues
            log::debug!("[SpinResult] REEL_STOP_{} → timestamp={}ms", reel, stop_time);

            // P0.1: Reel spinning STOP (triggers fade-out of spin loop audio)
            // Emitted at same time as ReelStop so audio fades as reel lands
            events.push(StageEvent::new(
                Stage::ReelSpinningStop { reel_index: reel },
                stop_time,
            ));

            // Reel stop (SAME timestamp as ReelSpinningStop!)
            let symbols = self.grid.get(reel as usize)
                .map(|r| r.iter().map(|&s| s).collect())
                .unwrap_or_default();

            events.push(StageEvent::new(
                Stage::ReelStop {
                    reel_index: reel,
                    symbols,
                },
                stop_time,
            ));
        }

        // 4. Evaluate Wins
        events.push(StageEvent::new(Stage::EvaluateWins, timing.advance(50.0)));

        // 5. Win presentation (if won)
        if self.is_win() {
            events.extend(self.generate_win_stages(timing));
        }

        // 6. Cascade stages (if any)
        for cascade in &self.cascades {
            events.extend(self.generate_cascade_stages(cascade, timing));
        }

        // 7. Feature trigger stages
        if let Some(ref feature) = self.feature_triggered {
            events.extend(self.generate_feature_stages(feature, timing));
        }

        // 8. Jackpot stages
        if let Some(ref jackpot) = self.jackpot_won {
            events.extend(self.generate_jackpot_stages(jackpot, timing));
        }

        // 9. Spin End
        events.push(StageEvent::new(Stage::SpinEnd, timing.advance(100.0)));

        // ═══════════════════════════════════════════════════════════════════════════
        // CRITICAL: Sort events by timestamp to ensure correct playback order
        // Without this, events are returned in code order which may not match timing
        // Example: EVALUATE_WINS might appear before REEL_STOP_4 in array
        // ═══════════════════════════════════════════════════════════════════════════
        events.sort_by(|a, b| a.timestamp_ms.partial_cmp(&b.timestamp_ms).unwrap_or(std::cmp::Ordering::Equal));

        events
    }

    fn generate_win_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let mut events = Vec::new();

        // Win Present
        let win_present_time = timing.win_reveal();
        events.push(StageEvent::with_payload(
            Stage::WinPresent {
                win_amount: self.total_win,
                line_count: self.line_wins.len() as u8,
            },
            win_present_time,
            StagePayload::with_win(self.total_win, Some(self.bet)),
        ));

        // Individual line wins
        for (i, line_win) in self.line_wins.iter().enumerate() {
            events.push(StageEvent::new(
                Stage::WinLineShow {
                    line_index: line_win.line_index,
                    line_amount: line_win.win_amount,
                },
                timing.win_line(),
            ));

            // Only show first few lines in detail
            if i >= 3 {
                break;
            }
        }

        // Big win tier
        if let Some(ref tier) = self.big_win_tier {
            if !matches!(tier, BigWinTier::Win) {
                let big_win_time = timing.big_win(self.win_ratio);
                events.push(StageEvent::with_payload(
                    Stage::BigWinTier {
                        tier: tier.clone(),
                        amount: self.total_win,
                    },
                    big_win_time,
                    StagePayload::with_win(self.total_win, Some(self.bet)),
                ));
            }
        }

        // Rollup
        let rollup_ticks = timing.rollup_ticks(self.total_win, 10);
        events.push(StageEvent::new(
            Stage::RollupStart {
                target_amount: self.total_win,
                start_amount: 0.0,
            },
            *rollup_ticks.first().unwrap_or(&timing.current()),
        ));

        for (i, tick_time) in rollup_ticks.iter().enumerate() {
            let progress = (i + 1) as f64 / rollup_ticks.len() as f64;
            events.push(StageEvent::new(
                Stage::RollupTick {
                    current_amount: self.total_win * progress,
                    progress,
                },
                *tick_time,
            ));
        }

        events.push(StageEvent::new(
            Stage::RollupEnd {
                final_amount: self.total_win,
            },
            timing.advance(100.0),
        ));

        events
    }

    fn generate_cascade_stages(&self, cascade: &CascadeResult, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let mut events = Vec::new();

        if cascade.step_index == 0 {
            events.push(StageEvent::new(Stage::CascadeStart, timing.cascade_step()));
        }

        events.push(StageEvent::with_payload(
            Stage::CascadeStep {
                step_index: cascade.step_index,
                multiplier: cascade.multiplier,
            },
            timing.cascade_step(),
            StagePayload::new().win_amount(cascade.win).multiplier(cascade.multiplier),
        ));

        events
    }

    fn generate_feature_stages(&self, feature: &TriggeredFeature, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let mut events = Vec::new();

        events.push(StageEvent::with_payload(
            Stage::FeatureEnter {
                feature_type: feature.feature_type,
                total_steps: Some(feature.total_spins),
                multiplier: feature.multiplier,
            },
            timing.feature_enter(),
            StagePayload::new()
                .spins_remaining(feature.total_spins)
                .multiplier(feature.multiplier),
        ));

        events
    }

    fn generate_jackpot_stages(&self, jackpot: &JackpotWin, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let mut events = Vec::new();

        events.push(StageEvent::new(
            Stage::JackpotTrigger {
                tier: jackpot.tier,
            },
            timing.advance(500.0),
        ));

        events.push(StageEvent::with_payload(
            Stage::JackpotPresent {
                amount: jackpot.amount,
                tier: jackpot.tier,
            },
            timing.advance(3000.0),
            StagePayload::new().win_amount(jackpot.amount),
        ));

        events.push(StageEvent::new(Stage::JackpotEnd, timing.advance(1000.0)));

        events
    }
}

/// Outcome type for forcing specific results
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ForcedOutcome {
    /// No win
    Lose,
    /// Small win (1-5x bet)
    SmallWin,
    /// Medium win (5-15x bet)
    MediumWin,
    /// Big win (15-25x bet)
    BigWin,
    /// Mega win (25-50x bet)
    MegaWin,
    /// Epic win (50-100x bet)
    EpicWin,
    /// Ultra win (100x+ bet)
    UltraWin,
    /// Free spins trigger
    FreeSpins,
    /// Jackpot win (Mini)
    JackpotMini,
    /// Jackpot win (Minor)
    JackpotMinor,
    /// Jackpot win (Major)
    JackpotMajor,
    /// Jackpot win (Grand)
    JackpotGrand,
    /// Near miss (close to big win)
    NearMiss,
    /// Cascade chain
    Cascade,
}

impl ForcedOutcome {
    /// Get target win ratio for this outcome
    pub fn target_ratio(&self) -> Option<f64> {
        match self {
            Self::Lose => Some(0.0),
            Self::SmallWin => Some(2.0),
            Self::MediumWin => Some(8.0),
            Self::BigWin => Some(18.0),
            Self::MegaWin => Some(35.0),
            Self::EpicWin => Some(70.0),
            Self::UltraWin => Some(150.0),
            Self::NearMiss => Some(0.0),
            _ => None,
        }
    }

    /// Does this outcome trigger a feature?
    pub fn triggers_feature(&self) -> bool {
        matches!(self, Self::FreeSpins)
    }

    /// Does this outcome trigger a jackpot?
    pub fn jackpot_tier(&self) -> Option<JackpotTier> {
        match self {
            Self::JackpotMini => Some(JackpotTier::Mini),
            Self::JackpotMinor => Some(JackpotTier::Minor),
            Self::JackpotMajor => Some(JackpotTier::Major),
            Self::JackpotGrand => Some(JackpotTier::Grand),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::timing::TimingConfig;

    #[test]
    fn test_spin_result_stages() {
        let grid = vec![
            vec![1, 2, 3],
            vec![1, 2, 3],
            vec![1, 2, 3],
            vec![4, 5, 6],
            vec![4, 5, 6],
        ];

        let mut result = SpinResult::new("test-001".into(), grid, 1.0);
        result.total_win = 10.0;
        result.win_ratio = 10.0;
        result.big_win_tier = Some(BigWinTier::Win);
        result.line_wins.push(LineWin {
            line_index: 0,
            symbol_id: 1,
            symbol_name: "HP1".into(),
            match_count: 3,
            win_amount: 10.0,
            positions: vec![(0, 0), (1, 0), (2, 0)],
            wild_positions: vec![],
        });

        let config = TimingConfig::studio();
        let mut timing = crate::timing::TimestampGenerator::new(config);
        let stages = result.generate_stages(&mut timing);

        // Should have spin_start, reel_spinning, reel_stop, evaluate, win_present, etc.
        assert!(stages.len() > 10);

        // First stage should be SpinStart
        assert!(matches!(stages[0].stage, Stage::SpinStart));

        // Last stage should be SpinEnd
        assert!(matches!(stages.last().unwrap().stage, Stage::SpinEnd));
    }

    #[test]
    fn test_forced_outcome() {
        assert_eq!(ForcedOutcome::SmallWin.target_ratio(), Some(2.0));
        assert!(ForcedOutcome::FreeSpins.triggers_feature());
        assert_eq!(
            ForcedOutcome::JackpotGrand.jackpot_tier(),
            Some(JackpotTier::Grand)
        );
    }

    #[test]
    fn test_stage_ordering_after_sorting() {
        // Create a winning spin result to ensure we get WIN_PRESENT and other win stages
        let grid = vec![
            vec![1, 1, 1],  // 5 reels x 3 rows
            vec![1, 1, 1],
            vec![1, 1, 1],
            vec![2, 2, 2],
            vec![2, 2, 2],
        ];

        let mut result = SpinResult::new("order-test".into(), grid, 1.0);
        result.total_win = 50.0;
        result.win_ratio = 50.0;
        result.big_win_tier = Some(BigWinTier::MegaWin);
        result.line_wins.push(LineWin {
            line_index: 0,
            symbol_id: 1,
            symbol_name: "HP1".into(),
            match_count: 5,
            win_amount: 50.0,
            positions: vec![(0, 1), (1, 1), (2, 1), (3, 1), (4, 1)],
            wild_positions: vec![],
        });

        let config = TimingConfig::normal();
        let mut timing = crate::timing::TimestampGenerator::new(config);
        let stages = result.generate_stages(&mut timing);

        // Find key stage timestamps
        let mut last_reel_stop_ts = 0.0_f64;
        let mut evaluate_wins_ts = None;
        let mut win_present_ts = None;

        for stage in &stages {
            match &stage.stage {
                Stage::ReelStop { reel_index, .. } => {
                    // Track the latest REEL_STOP timestamp
                    if stage.timestamp_ms > last_reel_stop_ts {
                        last_reel_stop_ts = stage.timestamp_ms;
                    }
                    println!("REEL_STOP_{}: {}ms", reel_index, stage.timestamp_ms);
                }
                Stage::EvaluateWins => {
                    evaluate_wins_ts = Some(stage.timestamp_ms);
                    println!("EVALUATE_WINS: {}ms", stage.timestamp_ms);
                }
                Stage::WinPresent { .. } => {
                    win_present_ts = Some(stage.timestamp_ms);
                    println!("WIN_PRESENT: {}ms", stage.timestamp_ms);
                }
                _ => {}
            }
        }

        // CRITICAL ASSERTIONS:
        // 1. All REEL_STOP events must have timestamps BEFORE EVALUATE_WINS
        let eval_ts = evaluate_wins_ts.expect("Should have EVALUATE_WINS stage");
        assert!(
            last_reel_stop_ts < eval_ts,
            "Last REEL_STOP ({}) must be before EVALUATE_WINS ({})",
            last_reel_stop_ts,
            eval_ts
        );

        // 2. EVALUATE_WINS must have timestamp BEFORE WIN_PRESENT
        let win_ts = win_present_ts.expect("Should have WIN_PRESENT stage for winning spin");
        assert!(
            eval_ts < win_ts,
            "EVALUATE_WINS ({}) must be before WIN_PRESENT ({})",
            eval_ts,
            win_ts
        );

        // 3. Verify stages are sorted by timestamp
        let mut prev_ts = 0.0_f64;
        for (i, stage) in stages.iter().enumerate() {
            assert!(
                stage.timestamp_ms >= prev_ts,
                "Stage {} has timestamp {} but previous was {} - NOT SORTED!",
                i,
                stage.timestamp_ms,
                prev_ts
            );
            prev_ts = stage.timestamp_ms;
        }

        println!("\n✅ Stage ordering is CORRECT:");
        println!("   Last REEL_STOP: {}ms", last_reel_stop_ts);
        println!("   EVALUATE_WINS: {}ms", eval_ts);
        println!("   WIN_PRESENT: {}ms", win_ts);
    }
}

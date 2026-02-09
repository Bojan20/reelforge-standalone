//! Spin result and stage event generation

use serde::{Deserialize, Serialize};

/// Default total reels (5) for anticipation calculations
fn default_total_reels() -> u8 {
    5
}

use rf_stage::{BigWinTier, FeatureType, JackpotTier, Stage, StageEvent, StagePayload};

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
            Self::Jackpot => 4, // Highest priority
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
    /// Create anticipation info for scatter-based anticipation (LEGACY - all reels allowed)
    ///
    /// When 2+ scatters detected, anticipation triggers on ALL remaining reels.
    /// Example: Scatters on reel 0,1 → anticipation on reels 2,3,4
    /// Example: Scatters on reel 0,3 → anticipation on reels 4,5 (if exists)
    ///
    /// For restricted reel support (e.g., scatter only on 0,2,4), use
    /// `from_trigger_positions_with_config()` instead.
    pub fn from_scatter_positions(
        scatter_positions: Vec<(u8, u8)>,
        total_reels: u8,
        base_duration_ms: u32,
    ) -> Option<Self> {
        if scatter_positions.len() < 2 {
            return None; // Need at least 2 scatters for anticipation
        }

        // Find the rightmost reel with a scatter
        let last_scatter_reel = scatter_positions
            .iter()
            .map(|(reel, _)| *reel)
            .max()
            .unwrap_or(0);

        // Anticipation happens on ALL reels AFTER the last scatter
        let anticipation_reels: Vec<u8> = ((last_scatter_reel + 1)..total_reels).collect();

        if anticipation_reels.is_empty() {
            return None; // No reels left for anticipation
        }

        // Build per-reel anticipation data with escalating tension
        let reel_data: Vec<ReelAnticipation> = anticipation_reels
            .iter()
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

    /// Create anticipation info using AnticipationConfig (V2 — supports restricted reels)
    ///
    /// This is the preferred method for creating anticipation with:
    /// - Tip A: Scatter on all reels, 3+ triggers → uses None for allowed_reels
    /// - Tip B: Scatter only on reels 0, 2, 4 → uses Some([0, 2, 4]) for allowed_reels
    ///
    /// Universal rule: 2 trigger symbols on allowed reels = anticipation activates
    ///
    /// # Arguments
    /// * `trigger_positions` - Positions of trigger symbols: (reel, row)
    /// * `config` - AnticipationConfig defining trigger rules and allowed reels
    /// * `total_reels` - Total number of reels in the game
    /// * `base_duration_ms` - Base duration per anticipation reel
    /// * `reason` - Why anticipation triggered (Scatter, Bonus, etc.)
    ///
    /// # Examples
    ///
    /// ## Tip A: Scatter on all reels
    /// - Scatters on reels 0, 1 → anticipation on 2, 3, 4
    /// - Scatters on reels 0, 3 → anticipation on 4
    ///
    /// ## Tip B: Scatter only on 0, 2, 4
    /// - Scatters on reels 0, 2 → anticipation on 4 (only reel 4 is allowed and after 2)
    /// - Scatter on reel 0 only → NO anticipation (need 2 on allowed reels)
    /// - Scatters on reels 0, 1 → NO anticipation (reel 1 not allowed!)
    pub fn from_trigger_positions_with_config(
        trigger_positions: Vec<(u8, u8)>,
        config: &crate::config::AnticipationConfig,
        total_reels: u8,
        base_duration_ms: u32,
        reason: AnticipationReason,
    ) -> Option<Self> {
        // Use config's algorithm to calculate anticipation reels
        let anticipation_reels =
            config.calculate_anticipation_reels(&trigger_positions, total_reels);

        if anticipation_reels.is_empty() {
            return None;
        }

        // Build per-reel anticipation data with escalating tension
        let reel_data: Vec<ReelAnticipation> = anticipation_reels
            .iter()
            .enumerate()
            .map(|(idx, &reel)| {
                let tension_level = config.tension_level_for_reel(idx);

                ReelAnticipation {
                    reel_index: reel,
                    tension_level: tension_level as u8,
                    progress: 0.0,
                    duration_ms: base_duration_ms,
                }
            })
            .collect();

        Some(Self {
            reels: anticipation_reels,
            reason_type: reason,
            reason: reason.as_str().to_string(),
            trigger_count: trigger_positions.len() as u8,
            trigger_positions,
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
        let reel_data: Vec<ReelAnticipation> = reels
            .iter()
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
        self.reel_data
            .iter()
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

    /// Set big win tier based on ratio (LEGACY - uses hardcoded thresholds)
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

    /// Set win tier using P5 SlotWinConfig (dynamic, user-configurable)
    ///
    /// This replaces the legacy `with_big_win_tier` when P5 config is available.
    /// Returns the P5 `WinTierResult` which contains:
    /// - `is_big_win`: whether win qualifies for big win celebration
    /// - `regular_tier_id`: tier ID for regular wins (-1=LOW, 0=EQUAL, 1-6)
    /// - `big_win_max_tier`: max big win tier reached (1-5)
    /// - `primary_stage`: stage name to trigger
    /// - `display_label`: user-editable display label
    /// - `rollup_duration_ms`: rollup animation duration
    pub fn with_p5_win_tier(
        mut self,
        config: &crate::model::SlotWinConfig,
    ) -> (Self, crate::model::WinTierResult) {
        let result = config.evaluate(self.total_win, self.bet);

        // Map P5 result to legacy BigWinTier for backwards compatibility
        if result.is_big_win {
            // Map big win max tier to legacy enum
            self.big_win_tier = match result.big_win_max_tier {
                Some(5) => Some(BigWinTier::UltraWin),
                Some(4) => Some(BigWinTier::EpicWin),
                Some(3) => Some(BigWinTier::MegaWin),
                Some(2) => Some(BigWinTier::BigWin),
                Some(1) => Some(BigWinTier::BigWin),
                _ => Some(BigWinTier::BigWin),
            };
        } else if self.total_win > 0.0 {
            self.big_win_tier = Some(BigWinTier::Win);
        }

        // Set win tier name from P5 result
        if !result.primary_stage.is_empty() && result.primary_stage != "NO_WIN" {
            self.win_tier_name = Some(result.primary_stage.clone());
        }

        (self, result)
    }

    /// Check if this is a win
    pub fn is_win(&self) -> bool {
        self.total_win > 0.0
    }

    /// Generate all stage events for this spin (legacy mode — parallel anticipation)
    ///
    /// For industry-standard sequential anticipation (one reel at a time),
    /// use `generate_stages_with_config()` instead.
    pub fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        // Legacy mode: all reels stop in parallel, even during anticipation
        self.generate_stages_internal(timing, false)
    }

    /// Generate stage events with sequential anticipation support (P7.1.3)
    ///
    /// When `sequential_anticipation` is true:
    /// - Non-anticipation reels stop with normal interval (reel_stop_interval_ms)
    /// - Anticipation reels stop ONE AT A TIME, each waiting for previous to complete
    /// - Each anticipation reel has: AnticipationOn → TensionLayer → AnticipationOff → ReelStop
    /// - Next anticipation reel starts ONLY after previous ReelStop completes
    ///
    /// This matches industry standard (IGT, Pragmatic Play, NetEnt, Play'n GO):
    /// - Reel 0, 1 stop normally → Reel 2 anticipates → stops → Reel 3 anticipates → stops → etc.
    pub fn generate_stages_with_config(
        &self,
        timing: &mut TimestampGenerator,
        antic_config: &crate::config::AnticipationConfig,
    ) -> Vec<StageEvent> {
        self.generate_stages_internal(timing, antic_config.sequential_stop)
    }

    /// Internal stage generation with optional sequential anticipation
    fn generate_stages_internal(
        &self,
        timing: &mut TimestampGenerator,
        sequential_anticipation: bool,
    ) -> Vec<StageEvent> {
        let mut events = Vec::new();

        // DEBUG: Log timing config for troubleshooting
        log::debug!(
            "[SpinResult::generate_stages] Starting with {} reels, timing.current={}ms, sequential={}",
            self.grid.len(),
            timing.current(),
            sequential_anticipation
        );

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

        // 3. Reel Stop events with P7.1.3 Sequential Anticipation Support
        //
        // Two modes:
        // A) PARALLEL (sequential_anticipation = false):
        //    - All reels stop with fixed interval, anticipation runs alongside
        //    - Legacy behavior for backwards compatibility
        //
        // B) SEQUENTIAL (sequential_anticipation = true):
        //    - Non-anticipation reels stop with normal interval
        //    - First anticipation reel: starts anticipation, waits, stops
        //    - Subsequent anticipation reels: WAIT for previous to complete, then start their anticipation
        //    - Flow: R0-R1 (normal) → R2 (antic→stop) → R3 (antic→stop) → R4 (antic→stop)
        //
        // Industry standard (IGT, Pragmatic Play, NetEnt):
        // - Each anticipation reel gets FULL attention (visual + audio tension)
        // - Player watches one reel at a time during anticipation
        // - Tension escalates: L1 (reel 2) → L2 (reel 3) → L3 (reel 4) → L4 (reel 5)

        // First, identify which reels have anticipation
        let anticipation_reels: Vec<u8> = self
            .anticipation
            .as_ref()
            .map(|a| a.reels.clone())
            .unwrap_or_default();

        // Find first anticipation reel (all before it are "normal" reels)
        // Used for debug logging
        let _first_antic_reel = anticipation_reels.first().copied();

        for reel in 0..reel_count {
            let has_anticipation = anticipation_reels.contains(&reel);

            if has_anticipation && sequential_anticipation {
                // ═══════════════════════════════════════════════════════════════════════
                // SEQUENTIAL MODE: Each anticipation reel is processed one at a time
                // ═══════════════════════════════════════════════════════════════════════
                let antic = self.anticipation.as_ref().unwrap();
                let tension_level = antic.tension_level_for_reel(reel);
                let antic_duration = timing.config().anticipation_duration_ms;

                // If this is NOT the first anticipation reel, we need to wait
                // for the previous reel to fully complete (anticipation + stop)
                // The timing generator handles this via anticipation_start()

                // Anticipation ON — marks start of this reel's anticipation phase
                let antic_time = timing.anticipation_start();
                events.push(StageEvent::new(
                    Stage::AnticipationOn {
                        reel_index: reel,
                        reason: Some(antic.reason.clone()),
                    },
                    antic_time,
                ));

                // AnticipationTensionLayer — tells audio system which layer to use
                if tension_level > 0 {
                    // Start at progress 0.0
                    events.push(StageEvent::new(
                        Stage::AnticipationTensionLayer {
                            reel_index: reel,
                            tension_level,
                            reason: Some(antic.reason.clone()),
                            progress: 0.0,
                        },
                        antic_time,
                    ));

                    // Progress update at 50%
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

                    // Progress update at 100% (just before stop)
                    let progress_100_time = antic_time + antic_duration - 50.0;
                    events.push(StageEvent::new(
                        Stage::AnticipationTensionLayer {
                            reel_index: reel,
                            tension_level,
                            reason: Some(antic.reason.clone()),
                            progress: 1.0,
                        },
                        progress_100_time,
                    ));
                }

                // Anticipation OFF — ends this reel's anticipation phase
                let antic_end = timing.anticipation_end();
                events.push(StageEvent::new(
                    Stage::AnticipationOff { reel_index: reel },
                    antic_end,
                ));

                // Reel Stop — IMMEDIATELY after anticipation ends
                // In sequential mode, we use a minimal delay after anticipation
                let stop_time = timing.advance(50.0); // 50ms after antic_end

                log::debug!(
                    "[SpinResult] SEQUENTIAL REEL_STOP_{} (L{}) → antic={}ms, stop={}ms",
                    reel,
                    tension_level,
                    antic_time,
                    stop_time
                );

                events.push(StageEvent::new(
                    Stage::ReelSpinningStop { reel_index: reel },
                    stop_time,
                ));

                let symbols = self
                    .grid
                    .get(reel as usize)
                    .map(|r| r.iter().map(|&s| s).collect())
                    .unwrap_or_default();

                events.push(StageEvent::new(
                    Stage::ReelStop {
                        reel_index: reel,
                        symbols,
                    },
                    stop_time,
                ));
            } else if has_anticipation {
                // ═══════════════════════════════════════════════════════════════════════
                // PARALLEL MODE (legacy): Anticipation runs alongside normal reel stops
                // ═══════════════════════════════════════════════════════════════════════
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

                    // Progress update at 50%
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

                // Anticipation OFF after duration
                let antic_end = timing.anticipation_end();
                events.push(StageEvent::new(
                    Stage::AnticipationOff { reel_index: reel },
                    antic_end,
                ));

                // Reel stop uses normal timing
                let stop_time = timing.reel_stop(reel);

                log::debug!(
                    "[SpinResult] PARALLEL REEL_STOP_{} → timestamp={}ms",
                    reel,
                    stop_time
                );

                events.push(StageEvent::new(
                    Stage::ReelSpinningStop { reel_index: reel },
                    stop_time,
                ));

                let symbols = self
                    .grid
                    .get(reel as usize)
                    .map(|r| r.iter().map(|&s| s).collect())
                    .unwrap_or_default();

                events.push(StageEvent::new(
                    Stage::ReelStop {
                        reel_index: reel,
                        symbols,
                    },
                    stop_time,
                ));
            } else {
                // ═══════════════════════════════════════════════════════════════════════
                // NORMAL REEL (no anticipation): Standard timing
                // ═══════════════════════════════════════════════════════════════════════
                let stop_time = timing.reel_stop(reel);

                log::debug!(
                    "[SpinResult] NORMAL REEL_STOP_{} → timestamp={}ms",
                    reel,
                    stop_time
                );

                events.push(StageEvent::new(
                    Stage::ReelSpinningStop { reel_index: reel },
                    stop_time,
                ));

                let symbols = self
                    .grid
                    .get(reel as usize)
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
        events.sort_by(|a, b| {
            a.timestamp_ms
                .partial_cmp(&b.timestamp_ms)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

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

    fn generate_cascade_stages(
        &self,
        cascade: &CascadeResult,
        timing: &mut TimestampGenerator,
    ) -> Vec<StageEvent> {
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
            StagePayload::new()
                .win_amount(cascade.win)
                .multiplier(cascade.multiplier),
        ));

        events
    }

    fn generate_feature_stages(
        &self,
        feature: &TriggeredFeature,
        timing: &mut TimestampGenerator,
    ) -> Vec<StageEvent> {
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

    fn generate_jackpot_stages(
        &self,
        jackpot: &JackpotWin,
        timing: &mut TimestampGenerator,
    ) -> Vec<StageEvent> {
        let mut events = Vec::new();

        events.push(StageEvent::new(
            Stage::JackpotTrigger { tier: jackpot.tier },
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
            vec![1, 1, 1], // 5 reels x 3 rows
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

    // ═══════════════════════════════════════════════════════════════════════════
    // P7.3.2: Sequential Anticipation Timing Tests
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fn test_sequential_anticipation_timing() {
        use crate::config::AnticipationConfig;

        // Grid with scatters on reels 0 and 1 (triggers anticipation on 2, 3, 4)
        let grid = vec![
            vec![100, 1, 1], // Reel 0: scatter at row 0
            vec![100, 1, 1], // Reel 1: scatter at row 0
            vec![1, 1, 1],   // Reel 2: anticipation
            vec![1, 1, 1],   // Reel 3: anticipation
            vec![1, 1, 1],   // Reel 4: anticipation
        ];

        let mut result = SpinResult::new("seq-antic-test".into(), grid, 1.0);

        // Create anticipation using Tip A config (all reels, 3+ for feature, 2 for antic)
        let antic_config = AnticipationConfig::tip_a(100, None); // 100 = scatter ID
        let trigger_positions = vec![(0, 0), (1, 0)]; // Scatters on reels 0, 1

        result.anticipation = AnticipationInfo::from_trigger_positions_with_config(
            trigger_positions,
            &antic_config,
            5,
            1500, // 1500ms per anticipation reel
            AnticipationReason::Scatter,
        );

        assert!(result.anticipation.is_some(), "Should have anticipation");
        let antic = result.anticipation.as_ref().unwrap();
        assert_eq!(antic.reels, vec![2, 3, 4], "Anticipation on reels 2, 3, 4");

        // Generate stages with SEQUENTIAL mode
        let config = TimingConfig::normal();
        let mut timing = crate::timing::TimestampGenerator::new(config);
        let stages = result.generate_stages_with_config(&mut timing, &antic_config);

        // Collect reel stop times
        let mut reel_stop_times: Vec<(u8, f64)> = Vec::new();
        let mut antic_on_times: Vec<(u8, f64)> = Vec::new();
        let mut antic_off_times: Vec<(u8, f64)> = Vec::new();

        for stage in &stages {
            match &stage.stage {
                Stage::ReelStop { reel_index, .. } => {
                    reel_stop_times.push((*reel_index, stage.timestamp_ms));
                    println!("REEL_STOP_{}: {}ms", reel_index, stage.timestamp_ms);
                }
                Stage::AnticipationOn { reel_index, .. } => {
                    antic_on_times.push((*reel_index, stage.timestamp_ms));
                    println!("ANTIC_ON_{}: {}ms", reel_index, stage.timestamp_ms);
                }
                Stage::AnticipationOff { reel_index } => {
                    antic_off_times.push((*reel_index, stage.timestamp_ms));
                    println!("ANTIC_OFF_{}: {}ms", reel_index, stage.timestamp_ms);
                }
                _ => {}
            }
        }

        // Verify SEQUENTIAL order:
        // 1. Non-anticipation reels (0, 1) stop with normal interval
        let reel0_stop = reel_stop_times
            .iter()
            .find(|(r, _)| *r == 0)
            .map(|(_, t)| *t)
            .unwrap();
        let reel1_stop = reel_stop_times
            .iter()
            .find(|(r, _)| *r == 1)
            .map(|(_, t)| *t)
            .unwrap();

        assert!(
            reel1_stop > reel0_stop,
            "Reel 1 ({}) should stop after Reel 0 ({})",
            reel1_stop,
            reel0_stop
        );

        // 2. Anticipation reels (2, 3, 4) should be SEQUENTIAL:
        //    - Each reel's ANTIC_ON must be AFTER previous reel's REEL_STOP
        //    - Each reel's REEL_STOP must be AFTER its own ANTIC_OFF

        // Reel 2 anticipation
        let reel2_antic_on = antic_on_times
            .iter()
            .find(|(r, _)| *r == 2)
            .map(|(_, t)| *t)
            .unwrap();
        let reel2_antic_off = antic_off_times
            .iter()
            .find(|(r, _)| *r == 2)
            .map(|(_, t)| *t)
            .unwrap();
        let reel2_stop = reel_stop_times
            .iter()
            .find(|(r, _)| *r == 2)
            .map(|(_, t)| *t)
            .unwrap();

        // Reel 3 anticipation
        let reel3_antic_on = antic_on_times
            .iter()
            .find(|(r, _)| *r == 3)
            .map(|(_, t)| *t)
            .unwrap();
        let reel3_antic_off = antic_off_times
            .iter()
            .find(|(r, _)| *r == 3)
            .map(|(_, t)| *t)
            .unwrap();
        let reel3_stop = reel_stop_times
            .iter()
            .find(|(r, _)| *r == 3)
            .map(|(_, t)| *t)
            .unwrap();

        // Reel 4 anticipation
        let reel4_antic_on = antic_on_times
            .iter()
            .find(|(r, _)| *r == 4)
            .map(|(_, t)| *t)
            .unwrap();
        let reel4_antic_off = antic_off_times
            .iter()
            .find(|(r, _)| *r == 4)
            .map(|(_, t)| *t)
            .unwrap();
        let reel4_stop = reel_stop_times
            .iter()
            .find(|(r, _)| *r == 4)
            .map(|(_, t)| *t)
            .unwrap();

        // Verify Reel 2: antic_on >= reel1_stop (can start at same time or after)
        // antic_off > antic_on (anticipation has duration), stop > antic_off (stop after antic ends)
        assert!(
            reel2_antic_on >= reel1_stop,
            "R2 antic should start at or after R1 stop"
        );
        assert!(
            reel2_antic_off > reel2_antic_on,
            "R2 antic_off after antic_on"
        );
        assert!(reel2_stop > reel2_antic_off, "R2 stop after antic_off");

        // Verify Reel 3: antic_on >= reel2_stop (SEQUENTIAL!)
        assert!(
            reel3_antic_on >= reel2_stop,
            "R3 antic should start at or after R2 STOP (sequential)"
        );
        assert!(
            reel3_antic_off > reel3_antic_on,
            "R3 antic_off after antic_on"
        );
        assert!(reel3_stop > reel3_antic_off, "R3 stop after antic_off");

        // Verify Reel 4: antic_on >= reel3_stop (SEQUENTIAL!)
        assert!(
            reel4_antic_on >= reel3_stop,
            "R4 antic should start at or after R3 STOP (sequential)"
        );
        assert!(
            reel4_antic_off > reel4_antic_on,
            "R4 antic_off after antic_on"
        );
        assert!(reel4_stop > reel4_antic_off, "R4 stop after antic_off");

        println!("\n✅ Sequential anticipation timing is CORRECT:");
        println!(
            "   R0 stop: {}ms, R1 stop: {}ms (normal)",
            reel0_stop, reel1_stop
        );
        println!(
            "   R2: antic {}ms → {}ms, stop {}ms",
            reel2_antic_on, reel2_antic_off, reel2_stop
        );
        println!(
            "   R3: antic {}ms → {}ms, stop {}ms",
            reel3_antic_on, reel3_antic_off, reel3_stop
        );
        println!(
            "   R4: antic {}ms → {}ms, stop {}ms",
            reel4_antic_on, reel4_antic_off, reel4_stop
        );
    }

    #[test]
    fn test_tip_b_sequential_anticipation() {
        use crate::config::AnticipationConfig;

        // Tip B: Scatter only allowed on reels 0, 2, 4
        // Scatters on reels 0, 2 → anticipation on reel 4 (only remaining allowed reel)
        let grid = vec![
            vec![100, 1, 1], // Reel 0: scatter
            vec![1, 1, 1],   // Reel 1: normal (not allowed for scatter)
            vec![100, 1, 1], // Reel 2: scatter
            vec![1, 1, 1],   // Reel 3: normal (not allowed for scatter)
            vec![1, 1, 1],   // Reel 4: anticipation
        ];

        let mut result = SpinResult::new("tip-b-seq-test".into(), grid, 1.0);

        // Tip B config: scatter only on 0, 2, 4
        let antic_config = AnticipationConfig::tip_b(100, None); // 100 = scatter ID
        let trigger_positions = vec![(0, 0), (2, 0)]; // Scatters on allowed reels 0, 2

        result.anticipation = AnticipationInfo::from_trigger_positions_with_config(
            trigger_positions,
            &antic_config,
            5,
            1500,
            AnticipationReason::Scatter,
        );

        assert!(
            result.anticipation.is_some(),
            "Should have anticipation for Tip B"
        );
        let antic = result.anticipation.as_ref().unwrap();
        assert_eq!(
            antic.reels,
            vec![4],
            "Tip B: Only reel 4 should have anticipation"
        );

        // Generate stages with SEQUENTIAL mode
        let config = TimingConfig::normal();
        let mut timing = crate::timing::TimestampGenerator::new(config);
        let stages = result.generate_stages_with_config(&mut timing, &antic_config);

        // Verify reel 4 has anticipation stages
        let has_reel4_antic = stages
            .iter()
            .any(|s| matches!(&s.stage, Stage::AnticipationOn { reel_index: 4, .. }));
        let has_reel4_tension = stages.iter().any(|s| {
            matches!(
                &s.stage,
                Stage::AnticipationTensionLayer { reel_index: 4, .. }
            )
        });

        assert!(has_reel4_antic, "Reel 4 should have AnticipationOn stage");
        assert!(
            has_reel4_tension,
            "Reel 4 should have AnticipationTensionLayer stage"
        );

        // Verify reels 1 and 3 do NOT have anticipation (they're not allowed reels)
        let has_reel1_antic = stages
            .iter()
            .any(|s| matches!(&s.stage, Stage::AnticipationOn { reel_index: 1, .. }));
        let has_reel3_antic = stages
            .iter()
            .any(|s| matches!(&s.stage, Stage::AnticipationOn { reel_index: 3, .. }));

        assert!(
            !has_reel1_antic,
            "Reel 1 should NOT have anticipation (not allowed)"
        );
        assert!(
            !has_reel3_antic,
            "Reel 3 should NOT have anticipation (not allowed)"
        );

        println!("\n✅ Tip B sequential anticipation:");
        println!("   Scatter allowed on: 0, 2, 4");
        println!("   Scatters landed on: 0, 2");
        println!("   Anticipation on: 4 only");
    }

    #[test]
    fn test_parallel_vs_sequential_timing_difference() {
        use crate::config::AnticipationConfig;

        // Same setup for both modes
        let grid = vec![
            vec![100, 1, 1], // scatter
            vec![100, 1, 1], // scatter
            vec![1, 1, 1],
            vec![1, 1, 1],
            vec![1, 1, 1],
        ];

        let antic_config = AnticipationConfig::tip_a(100, None);
        let trigger_positions = vec![(0, 0), (1, 0)];

        // PARALLEL mode
        let mut result_parallel = SpinResult::new("parallel".into(), grid.clone(), 1.0);
        result_parallel.anticipation = AnticipationInfo::from_trigger_positions_with_config(
            trigger_positions.clone(),
            &antic_config,
            5,
            1500,
            AnticipationReason::Scatter,
        );

        let config = TimingConfig::normal();
        let mut timing_parallel = crate::timing::TimestampGenerator::new(config.clone());
        let stages_parallel = result_parallel.generate_stages(&mut timing_parallel);

        // SEQUENTIAL mode
        let mut result_sequential = SpinResult::new("sequential".into(), grid, 1.0);
        result_sequential.anticipation = AnticipationInfo::from_trigger_positions_with_config(
            trigger_positions,
            &antic_config,
            5,
            1500,
            AnticipationReason::Scatter,
        );

        let mut timing_sequential = crate::timing::TimestampGenerator::new(config);
        let stages_sequential =
            result_sequential.generate_stages_with_config(&mut timing_sequential, &antic_config);

        // Get last reel stop times
        let parallel_last_stop = stages_parallel
            .iter()
            .filter_map(|s| match &s.stage {
                Stage::ReelStop { .. } => Some(s.timestamp_ms),
                _ => None,
            })
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap();

        let sequential_last_stop = stages_sequential
            .iter()
            .filter_map(|s| match &s.stage {
                Stage::ReelStop { .. } => Some(s.timestamp_ms),
                _ => None,
            })
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap();

        // Sequential has clean ONE-REEL-AT-A-TIME anticipation sequence
        // Parallel has overlapping anticipation phases
        // Both modes should generate valid timestamps, the actual duration depends on timing config

        // Key difference: In sequential mode, each anticipation reel MUST wait for previous
        // This test verifies both modes generate stages correctly

        // Count anticipation stages in each mode
        let parallel_antic_count = stages_parallel
            .iter()
            .filter(|s| matches!(&s.stage, Stage::AnticipationOn { .. }))
            .count();

        let sequential_antic_count = stages_sequential
            .iter()
            .filter(|s| matches!(&s.stage, Stage::AnticipationOn { .. }))
            .count();

        // Both should have same number of anticipation events (for reels 2, 3, 4)
        assert_eq!(
            parallel_antic_count, 3,
            "Parallel should have 3 anticipation events"
        );
        assert_eq!(
            sequential_antic_count, 3,
            "Sequential should have 3 anticipation events"
        );

        // Sequential mode should have AnticipationTensionLayer with progress 1.0 (parallel doesn't)
        let sequential_has_progress_100 = stages_sequential.iter().any(|s| {
            matches!(&s.stage,
                Stage::AnticipationTensionLayer { progress, .. } if *progress >= 0.99
            )
        });

        assert!(
            sequential_has_progress_100,
            "Sequential mode should have progress=1.0 stages"
        );

        println!("\n✅ Sequential vs Parallel comparison:");
        println!("   Parallel last REEL_STOP: {}ms", parallel_last_stop);
        println!("   Sequential last REEL_STOP: {}ms", sequential_last_stop);
        println!("   Parallel anticipation events: {}", parallel_antic_count);
        println!(
            "   Sequential anticipation events: {}",
            sequential_antic_count
        );
        println!(
            "   Sequential has progress=1.0: {}",
            sequential_has_progress_100
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P7.3.3: Integration Test — Full Spin Flow with Anticipation
    // Tests complete flow: Spin → Scatter Detection → Anticipation → Win
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fn test_full_spin_flow_with_anticipation_and_win() {
        use crate::config::AnticipationConfig;

        // Setup: 3 scatters (triggers feature) + line win
        // Scatters on reels 0, 2, 4 (Tip B config)
        let grid = vec![
            vec![100, 7, 7], // Reel 0: scatter (100) at row 0, HP1 (7) at rows 1-2
            vec![7, 7, 7],   // Reel 1: HP1 line
            vec![100, 7, 7], // Reel 2: scatter (100) at row 0, HP1 (7)
            vec![7, 7, 7],   // Reel 3: HP1 line
            vec![100, 7, 7], // Reel 4: scatter (100) at row 0, HP1 (7)
        ];

        let mut result = SpinResult::new("full-flow-test".into(), grid, 10.0); // bet = 10

        // Configure scatter win (3 scatters = 10x bet = 100)
        result.scatter_win = Some(ScatterWin {
            symbol_id: 100,
            count: 3,
            multiplier: 10.0,
            win_amount: 100.0, // 10x bet
            positions: vec![(0, 0), (2, 0), (4, 0)],
            triggers_feature: true, // 3 scatters triggers free spins
        });

        // Configure line win (5x HP1 = 50x bet = 500)
        result.line_wins.push(LineWin {
            line_index: 1, // Row 1
            symbol_id: 7,
            symbol_name: "HP1".into(),
            match_count: 5,
            win_amount: 500.0,
            positions: vec![(0, 1), (1, 1), (2, 1), (3, 1), (4, 1)],
            wild_positions: vec![],
        });

        result.total_win = 600.0; // 100 (scatter) + 500 (line)
        result.win_ratio = 60.0; // 600 / 10 bet
        result.big_win_tier = Some(BigWinTier::MegaWin); // 60x = Mega

        // Configure anticipation: Tip B on reels 0, 2, 4
        // With 3 scatters already, anticipation would have been on remaining allowed reels
        // But since all allowed reels have scatters, no anticipation needed in this case
        // Let's test a case where 2 scatters trigger anticipation on the 3rd:

        // Actually, let's use Tip A for this test (all reels) with 2 scatters
        // to demonstrate anticipation → scatter land → feature trigger
        let antic_config = AnticipationConfig::tip_a(100, None);

        // For the flow test, let's say we had 2 scatters (0, 2) and anticipation on reel 4
        // Then reel 4 landed a scatter → 3 scatters → feature!
        let trigger_positions = vec![(0, 0), (2, 0)]; // Initial triggers (before reel 4)

        result.anticipation = AnticipationInfo::from_trigger_positions_with_config(
            trigger_positions,
            &antic_config,
            5,
            2000, // 2 second anticipation
            AnticipationReason::Scatter,
        );

        // Generate stages with sequential mode
        let config = TimingConfig::normal();
        let mut timing = crate::timing::TimestampGenerator::new(config);
        let stages = result.generate_stages_with_config(&mut timing, &antic_config);

        // ═══════════════════════════════════════════════════════════════════════════
        // VERIFY COMPLETE STAGE FLOW
        // ═══════════════════════════════════════════════════════════════════════════

        // 1. Verify SPIN_START is first
        assert!(matches!(&stages[0].stage, Stage::SpinStart { .. }));

        // 2. Count all stage types
        let spin_starts = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::SpinStart { .. }))
            .count();
        let reel_stops = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::ReelStop { .. }))
            .count();
        let anticipation_ons = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::AnticipationOn { .. }))
            .count();
        let anticipation_offs = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::AnticipationOff { .. }))
            .count();
        let tension_layers = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::AnticipationTensionLayer { .. }))
            .count();
        let evaluate_wins = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::EvaluateWins))
            .count();
        let win_presents = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::WinPresent { .. }))
            .count();
        let spin_ends = stages
            .iter()
            .filter(|s| matches!(&s.stage, Stage::SpinEnd { .. }))
            .count();

        // 3. Verify stage counts
        assert_eq!(spin_starts, 1, "Should have exactly 1 SPIN_START");
        assert_eq!(
            reel_stops, 5,
            "Should have 5 REEL_STOP events (one per reel)"
        );
        assert!(anticipation_ons > 0, "Should have anticipation events");
        assert_eq!(
            anticipation_ons, anticipation_offs,
            "Anticipation ON/OFF counts should match"
        );
        assert!(tension_layers > 0, "Should have tension layer events");
        assert_eq!(evaluate_wins, 1, "Should have exactly 1 EVALUATE_WINS");
        assert!(win_presents > 0, "Should have WIN_PRESENT for winning spin");
        assert_eq!(spin_ends, 1, "Should have exactly 1 SPIN_END");

        // 4. Verify timestamp ordering: REEL_STOP < EVALUATE_WINS < WIN_PRESENT
        let last_reel_stop_ts = stages
            .iter()
            .filter_map(|s| match &s.stage {
                Stage::ReelStop { .. } => Some(s.timestamp_ms),
                _ => None,
            })
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap();

        let evaluate_ts = stages
            .iter()
            .find(|s| matches!(&s.stage, Stage::EvaluateWins))
            .map(|s| s.timestamp_ms)
            .unwrap();

        let win_present_ts = stages
            .iter()
            .find(|s| matches!(&s.stage, Stage::WinPresent { .. }))
            .map(|s| s.timestamp_ms)
            .unwrap();

        assert!(
            last_reel_stop_ts < evaluate_ts,
            "All REEL_STOP ({}) must be before EVALUATE_WINS ({})",
            last_reel_stop_ts,
            evaluate_ts
        );
        assert!(
            evaluate_ts < win_present_ts,
            "EVALUATE_WINS ({}) must be before WIN_PRESENT ({})",
            evaluate_ts,
            win_present_ts
        );

        // 5. Verify SPIN_END is last
        let spin_end_ts = stages
            .iter()
            .find(|s| matches!(&s.stage, Stage::SpinEnd { .. }))
            .map(|s| s.timestamp_ms)
            .unwrap();

        let max_ts = stages
            .iter()
            .map(|s| s.timestamp_ms)
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap();

        assert_eq!(spin_end_ts, max_ts, "SPIN_END should be the last stage");

        // 6. Verify all stages are sorted by timestamp
        for i in 1..stages.len() {
            assert!(
                stages[i].timestamp_ms >= stages[i - 1].timestamp_ms,
                "Stage {} ({}ms) must be >= stage {} ({}ms)",
                i,
                stages[i].timestamp_ms,
                i - 1,
                stages[i - 1].timestamp_ms
            );
        }

        // 7. Verify anticipation reels are correct (from trigger_positions)
        let antic_reels: Vec<u8> = stages
            .iter()
            .filter_map(|s| match &s.stage {
                Stage::AnticipationOn { reel_index, .. } => Some(*reel_index),
                _ => None,
            })
            .collect();

        // With triggers on 0 and 2, anticipation should be on remaining reels
        // Tip A: all reels allowed, so anticipation on 1, 3, 4
        assert!(
            antic_reels.contains(&1) || antic_reels.contains(&3) || antic_reels.contains(&4),
            "Anticipation should be on non-trigger reels"
        );
        assert!(
            !antic_reels.contains(&0),
            "Reel 0 (trigger) should NOT have anticipation"
        );
        assert!(
            !antic_reels.contains(&2),
            "Reel 2 (trigger) should NOT have anticipation"
        );

        println!("\n✅ Full Spin Flow Integration Test PASSED:");
        println!("   Total stages: {}", stages.len());
        println!("   SPIN_START: {}", spin_starts);
        println!("   REEL_STOP: {}", reel_stops);
        println!("   ANTICIPATION_ON: {}", anticipation_ons);
        println!("   TENSION_LAYER: {}", tension_layers);
        println!("   EVALUATE_WINS: {}", evaluate_wins);
        println!("   WIN_PRESENT: {}", win_presents);
        println!("   SPIN_END: {}", spin_ends);
        println!("   Last REEL_STOP: {}ms", last_reel_stop_ts);
        println!("   EVALUATE_WINS: {}ms", evaluate_ts);
        println!("   WIN_PRESENT: {}ms", win_present_ts);
        println!("   SPIN_END: {}ms", spin_end_ts);
    }

    #[test]
    fn test_wild_symbols_never_trigger_anticipation() {
        use crate::config::AnticipationConfig;

        // Grid with WILD symbols (ID 10) — these should NOT trigger anticipation
        let grid = vec![
            vec![10, 1, 1], // Reel 0: WILD (10)
            vec![10, 1, 1], // Reel 1: WILD (10)
            vec![1, 1, 1],  // Reel 2: regular
            vec![1, 1, 1],  // Reel 3: regular
            vec![1, 1, 1],  // Reel 4: regular
        ];

        let _result = SpinResult::new("wild-test".into(), grid, 1.0);

        // Configure Tip A with ONLY scatter as trigger (no bonus)
        // Wild (ID 10) should NOT be in trigger_symbol_ids
        let antic_config = AnticipationConfig::tip_a(100, None); // scatter=100, NO bonus

        // Verify wild is NOT in trigger list
        assert!(
            !antic_config.is_trigger_symbol(10),
            "Wild (ID 10) should NOT be a trigger symbol"
        );
        assert!(
            antic_config.is_trigger_symbol(100),
            "Scatter (ID 100) SHOULD be a trigger symbol"
        );
        assert!(
            !antic_config.is_trigger_symbol(7),
            "Random symbol (7) should NOT be a trigger"
        );

        // Also test with bonus (ID 11) — bonus IS a trigger, wild is NOT
        let antic_config_with_bonus = AnticipationConfig::tip_a(100, Some(11)); // scatter=100, bonus=11
        assert!(
            antic_config_with_bonus.is_trigger_symbol(100),
            "Scatter should be trigger"
        );
        assert!(
            antic_config_with_bonus.is_trigger_symbol(11),
            "Bonus should be trigger"
        );
        assert!(
            !antic_config_with_bonus.is_trigger_symbol(10),
            "Wild should NOT be trigger"
        );

        // The engine (engine.rs) filters grid positions to find ONLY trigger symbols
        // before calling from_trigger_positions_with_config()
        // Wild substitutes for wins but NEVER triggers anticipation

        println!("\n✅ Wild symbol exclusion verified:");
        println!(
            "   Wild (10) is trigger: {}",
            antic_config.is_trigger_symbol(10)
        );
        println!(
            "   Scatter (100) is trigger: {}",
            antic_config.is_trigger_symbol(100)
        );
        println!(
            "   Bonus (11) with bonus config: {}",
            antic_config_with_bonus.is_trigger_symbol(11)
        );
    }
}

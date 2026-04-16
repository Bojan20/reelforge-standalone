//! Stage Library — Pre-built audio envelopes for every canonical stage
//!
//! This is FluxForge's competitive moat. Every Stage variant has an atomically
//! defined StageEnvelope that describes:
//!
//! - **Audio behavior**: playback mode, layer, priority, ducking, bus routing
//! - **Timing**: attack/sustain/release, fade curves, sync constraints
//! - **Compliance**: jurisdiction-specific rules (UKGC, MGA, SE)
//! - **Visual hints**: suggested UI response (particles, shake, flash)
//! - **Math context**: RTP/volatility relevance, win tier implications
//!
//! IGT Playa requires manual config per event. FluxForge ships 54+ stage
//! envelopes out of the box — zero config for 90% of use cases, full
//! override for the remaining 10%.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::stage::{Stage, StageCategory};
use crate::taxonomy::BigWinTier;

// ═══════════════════════════════════════════════════════════════════════════════
// CORE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// How the audio asset should be played
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlaybackMode {
    /// Play once, fire-and-forget
    OneShot,
    /// Loop until explicitly stopped by a paired stage
    Loop,
    /// Crossfade from previous layer (smooth transition)
    Crossfade,
    /// Stinger — short accent layered on top of current audio
    Stinger,
    /// Tail — play when the associated loop stops (reverb tail, release)
    Tail,
}

/// Audio bus/layer assignment
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioLayer {
    /// Background ambient/music bed
    Ambient,
    /// Primary game mechanic sounds (spins, stops)
    Mechanics,
    /// Win celebrations, rollups
    Wins,
    /// Feature/bonus transitions
    Features,
    /// UI feedback (buttons, menus)
    UI,
    /// Stingers/accents layered on top
    Accent,
    /// Jackpot-dedicated channel (highest priority)
    Jackpot,
}

impl AudioLayer {
    /// Default priority for this layer (higher = more important)
    pub fn default_priority(&self) -> u8 {
        match self {
            Self::Ambient => 10,
            Self::UI => 20,
            Self::Mechanics => 30,
            Self::Wins => 50,
            Self::Accent => 60,
            Self::Features => 70,
            Self::Jackpot => 100,
        }
    }
}

/// Volume ducking behavior
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DuckBehavior {
    /// No ducking
    None,
    /// Duck ambient layer by given amount (0.0-1.0)
    DuckAmbient(f32),
    /// Duck all lower-priority layers
    DuckBelow(f32),
    /// Full mute of lower layers
    MuteBelow,
}

impl Default for DuckBehavior {
    fn default() -> Self {
        Self::None
    }
}

/// Fade curve shape
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum FadeCurve {
    /// Linear fade
    #[default]
    Linear,
    /// Exponential (natural sounding)
    Exponential,
    /// S-curve (smooth start and end)
    SCurve,
    /// Logarithmic (fast start, slow end)
    Logarithmic,
    /// Instant (no fade)
    Instant,
}

/// ADSR-like timing envelope for audio
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct AudioTiming {
    /// Fade-in duration (ms)
    pub attack_ms: f64,
    /// Sustain mode (true = hold until stop signal)
    pub sustain: bool,
    /// Fade-out duration (ms)
    pub release_ms: f64,
    /// Fade-in curve
    pub attack_curve: FadeCurve,
    /// Fade-out curve
    pub release_curve: FadeCurve,
    /// Minimum play duration before release allowed (ms)
    pub min_duration_ms: f64,
    /// Maximum play duration before auto-release (ms), 0 = unlimited
    pub max_duration_ms: f64,
}

impl Default for AudioTiming {
    fn default() -> Self {
        Self {
            attack_ms: 0.0,
            sustain: false,
            release_ms: 50.0,
            attack_curve: FadeCurve::Linear,
            release_curve: FadeCurve::Linear,
            min_duration_ms: 0.0,
            max_duration_ms: 0.0,
        }
    }
}

impl AudioTiming {
    /// Instant one-shot (no fades)
    pub fn instant() -> Self {
        Self {
            attack_ms: 0.0,
            sustain: false,
            release_ms: 0.0,
            attack_curve: FadeCurve::Instant,
            release_curve: FadeCurve::Instant,
            ..Default::default()
        }
    }

    /// Looping with crossfade
    pub fn looping(attack_ms: f64, release_ms: f64) -> Self {
        Self {
            attack_ms,
            sustain: true,
            release_ms,
            attack_curve: FadeCurve::Exponential,
            release_curve: FadeCurve::Exponential,
            ..Default::default()
        }
    }

    /// Stinger timing (short accent)
    pub fn stinger(duration_ms: f64) -> Self {
        Self {
            attack_ms: 0.0,
            sustain: false,
            release_ms: 30.0,
            max_duration_ms: duration_ms,
            ..Default::default()
        }
    }

    /// Celebration timing (long sustain, natural fade)
    pub fn celebration(min_ms: f64, max_ms: f64) -> Self {
        Self {
            attack_ms: 50.0,
            sustain: true,
            release_ms: 500.0,
            attack_curve: FadeCurve::Exponential,
            release_curve: FadeCurve::SCurve,
            min_duration_ms: min_ms,
            max_duration_ms: max_ms,
        }
    }
}

/// Compliance flags for a stage
///
/// Covers: UKGC (UK), MGA (Malta), SE (Sweden Spelinspektionen), DE (Germany GlüStV 2021)
/// Each field maps to a concrete regulatory requirement, not a vague "may apply".
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ComplianceFlags {
    /// Celebration must be proportional to win amount (UKGC RTS 7.1.1)
    pub proportional_celebration: bool,

    /// Must not disguise a loss as a win (LDW — win ≤ bet triggers this).
    /// When true, the stage must only fire if win > `ldw_threshold_pct` × bet.
    pub ldw_sensitive: bool,

    /// LDW threshold as % of bet (0.0–100.0). Default = 100.0 (win must exceed bet).
    /// UKGC guidance: any win ≤ total bet = LDW. Some jurisdictions use 50% or 80%.
    #[serde(default = "ComplianceFlags::default_ldw_threshold")]
    pub ldw_threshold_pct: f64,

    /// Near-miss audio restrictions apply (UKGC RTS 7.1.3, SE §32)
    pub near_miss_restricted: bool,

    /// Maximum stage/celebration duration (ms) per jurisdiction.
    /// Key: jurisdiction code (e.g., "ukgc", "mga", "se", "de")
    #[serde(default)]
    pub max_duration_by_jurisdiction: HashMap<String, f64>,

    /// Must be skippable by player (UKGC RTS 14.1)
    pub must_be_skippable: bool,

    /// Sound must respect responsible gaming mute/reduce settings
    pub rg_mutable: bool,

    /// Autoplay restrictions apply (max spins, loss limits, auto-stop on win)
    pub autoplay_restricted: bool,

    /// Maximum autoplay spins per jurisdiction (0 = no limit).
    /// UKGC: 300 spins max. SE: 150 spins max. MGA: no hard limit (best practice 300).
    #[serde(default)]
    pub autoplay_max_spins_by_jurisdiction: HashMap<String, u32>,

    /// Bonus Buy restricted (UKGC banned since Oct 2021, DE banned since 2021, SE restricted).
    /// When true, this stage/feature MUST NOT be triggered via Bonus Buy in affected jurisdictions.
    pub bonus_buy_restricted: bool,

    /// Jurisdictions where this stage/feature is completely prohibited (empty = allowed everywhere).
    /// Example: ["ukgc", "de"] for Bonus Buy stages.
    #[serde(default)]
    pub prohibited_in: Vec<String>,
}

impl ComplianceFlags {
    /// Default LDW threshold — 100% of bet (any win ≤ bet is LDW per UKGC guidance)
    fn default_ldw_threshold() -> f64 {
        100.0
    }

    /// No compliance restrictions (e.g. UI sound with no regulatory implications)
    pub fn none() -> Self {
        Self {
            ldw_threshold_pct: 100.0,
            ..Default::default()
        }
    }

    /// Win-related compliance — LDW guard + proportionality (UKGC RTS 7.1)
    pub fn win_stage() -> Self {
        Self {
            proportional_celebration: true,
            ldw_sensitive: true,
            ldw_threshold_pct: 100.0, // Win must exceed total bet to NOT be LDW
            must_be_skippable: true,
            rg_mutable: true,
            ..Default::default()
        }
    }

    /// Big win compliance — strict duration limits per jurisdiction (UKGC/MGA/SE)
    pub fn big_win(tier: &BigWinTier) -> Self {
        let mut max_durations = HashMap::new();
        let (ukgc_max, mga_max, se_max, de_max) = match tier {
            BigWinTier::Win      => (5_000.0,  8_000.0,  4_000.0,  5_000.0),
            BigWinTier::BigWin   => (8_000.0,  12_000.0, 6_000.0,  8_000.0),
            BigWinTier::MegaWin  => (12_000.0, 15_000.0, 8_000.0,  12_000.0),
            BigWinTier::EpicWin  => (15_000.0, 20_000.0, 10_000.0, 15_000.0),
            BigWinTier::UltraWin => (20_000.0, 25_000.0, 12_000.0, 20_000.0),
            BigWinTier::Custom(_)=> (10_000.0, 15_000.0, 8_000.0,  10_000.0),
        };
        max_durations.insert("ukgc".into(), ukgc_max);
        max_durations.insert("mga".into(),  mga_max);
        max_durations.insert("se".into(),   se_max);
        max_durations.insert("de".into(),   de_max);

        Self {
            proportional_celebration: true,
            ldw_sensitive: true,
            ldw_threshold_pct: 100.0,
            must_be_skippable: true,
            rg_mutable: true,
            max_duration_by_jurisdiction: max_durations,
            ..Default::default()
        }
    }

    /// Jackpot compliance — strictest, non-overridable, jurisdiction-limited
    pub fn jackpot() -> Self {
        let mut max_durations = HashMap::new();
        // UKGC: jackpot celebration ≤ 30s. MGA: ≤ 45s. SE: ≤ 20s. DE: ≤ 25s.
        max_durations.insert("ukgc".into(), 30_000.0);
        max_durations.insert("mga".into(),  45_000.0);
        max_durations.insert("se".into(),   20_000.0);
        max_durations.insert("de".into(),   25_000.0);

        Self {
            proportional_celebration: true,
            ldw_sensitive: false, // Jackpots are always real wins — LDW guard not applicable
            ldw_threshold_pct: 100.0,
            must_be_skippable: true,
            rg_mutable: true,
            max_duration_by_jurisdiction: max_durations,
            ..Default::default()
        }
    }

    /// Near-miss compliance — restricted audio, strict duration limits (UKGC RTS 7.1.3, SE §32)
    ///
    /// Near-miss must NOT be presented as near success. Audio must be:
    /// - Low volume (subdued, not exciting)
    /// - Short duration: UKGC ≤500ms, MGA ≤600ms, SE ≤400ms, DE ≤500ms
    /// - No visual excitement (no particles, no screen shake, no flash)
    pub fn near_miss() -> Self {
        let mut max_durations = HashMap::new();
        // Near-miss audio duration limits — shorter than spin result sound
        max_durations.insert("ukgc".into(), 500.0);
        max_durations.insert("mga".into(),  600.0);
        max_durations.insert("se".into(),   400.0);
        max_durations.insert("de".into(),   500.0);

        Self {
            near_miss_restricted: true,
            rg_mutable: true,
            must_be_skippable: false, // Near-miss is instant — skip not applicable
            max_duration_by_jurisdiction: max_durations,
            ldw_threshold_pct: 100.0,
            ..Default::default()
        }
    }

    /// Autoplay compliance — max spins per jurisdiction (UKGC: 300, SE: 150, MGA: best practice 300)
    pub fn autoplay() -> Self {
        let mut max_spins = HashMap::new();
        // Autoplay spin limits per jurisdiction
        max_spins.insert("ukgc".into(), 300_u32); // UKGC RTS 14.1 — max 300 autoplay spins
        max_spins.insert("se".into(),   150_u32); // SE Spelinspektionen — max 150
        max_spins.insert("mga".into(),  300_u32); // MGA: no hard limit, industry best practice
        max_spins.insert("de".into(),   100_u32); // DE GlüStV 2021 — very restrictive autoplay

        Self {
            autoplay_restricted: true,
            rg_mutable: true,
            autoplay_max_spins_by_jurisdiction: max_spins,
            ldw_threshold_pct: 100.0,
            ..Default::default()
        }
    }

    /// Bonus Buy compliance — banned in UKGC and DE, restricted in SE
    ///
    /// UKGC banned Bonus Buy in October 2021 (all licensees).
    /// DE GlüStV 2021 prohibits accelerated/turbo play including bonus buy.
    /// SE Spelinspektionen restricts buy features to specific license types.
    pub fn bonus_buy() -> Self {
        Self {
            bonus_buy_restricted: true,
            rg_mutable: true,
            must_be_skippable: true,
            ldw_threshold_pct: 100.0,
            prohibited_in: vec!["ukgc".into(), "de".into()], // Complete ban in UK + DE
            ..Default::default()
        }
    }

    /// Check if this stage/feature is allowed in a given jurisdiction.
    /// Returns false if `prohibited_in` contains the jurisdiction code.
    pub fn is_allowed_in(&self, jurisdiction: &str) -> bool {
        !self.prohibited_in.contains(&jurisdiction.to_lowercase())
    }

    /// Check if a win amount is LDW (Loss Disguised as Win) for a given bet.
    /// Returns true if win ≤ (ldw_threshold_pct / 100) × bet.
    pub fn is_ldw(&self, win_amount: f64, bet_amount: f64) -> bool {
        if !self.ldw_sensitive || bet_amount <= 0.0 {
            return false;
        }
        win_amount <= bet_amount * (self.ldw_threshold_pct / 100.0)
    }
}

/// Visual hint for UI layer
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct VisualHint {
    /// Suggested particle effect
    #[serde(default)]
    pub particle_effect: Option<String>,
    /// Screen shake intensity (0.0 = none, 1.0 = max)
    pub screen_shake: f32,
    /// Flash/glow intensity
    pub flash_intensity: f32,
    /// Suggested animation name
    #[serde(default)]
    pub animation: Option<String>,
    /// Color accent (hex)
    #[serde(default)]
    pub color_accent: Option<String>,
    /// Dim/darken background (0.0 = none, 1.0 = full black)
    pub bg_dim: f32,
}

impl VisualHint {
    pub fn none() -> Self {
        Self::default()
    }

    pub fn subtle_flash() -> Self {
        Self {
            flash_intensity: 0.3,
            ..Default::default()
        }
    }

    pub fn reel_stop() -> Self {
        Self {
            screen_shake: 0.05,
            flash_intensity: 0.1,
            animation: Some("reel_land".into()),
            ..Default::default()
        }
    }

    pub fn win_present(tier_ratio: f64) -> Self {
        let intensity = (tier_ratio / 100.0).min(1.0) as f32;
        Self {
            particle_effect: Some("coin_shower".into()),
            screen_shake: intensity * 0.3,
            flash_intensity: intensity * 0.8,
            animation: Some("win_celebration".into()),
            color_accent: Some("#FFD700".into()),
            bg_dim: intensity * 0.2,
        }
    }

    pub fn jackpot() -> Self {
        Self {
            particle_effect: Some("jackpot_explosion".into()),
            screen_shake: 0.8,
            flash_intensity: 1.0,
            animation: Some("jackpot_reveal".into()),
            color_accent: Some("#FF4500".into()),
            bg_dim: 0.6,
        }
    }

    pub fn feature_enter() -> Self {
        Self {
            particle_effect: Some("feature_transition".into()),
            screen_shake: 0.2,
            flash_intensity: 0.5,
            animation: Some("feature_intro".into()),
            bg_dim: 0.4,
            ..Default::default()
        }
    }

    pub fn anticipation(tension_level: u8) -> Self {
        let t = (tension_level as f32 / 4.0).min(1.0);
        Self {
            screen_shake: t * 0.15,
            flash_intensity: t * 0.3,
            animation: Some(format!("anticipation_l{tension_level}")),
            bg_dim: t * 0.15,
            ..Default::default()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE ENVELOPE — The atomic unit
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete audio envelope for a single stage.
///
/// This is what makes FluxForge different from every competitor:
/// each stage has a fully specified, production-ready envelope
/// that requires ZERO manual configuration to produce correct,
/// compliant, emotionally resonant audio behavior.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StageEnvelope {
    /// Stage type name (matches Stage::type_name())
    pub stage_type: String,

    /// Human-readable description
    pub description: String,

    /// Which category this belongs to
    pub category: StageCategory,

    // ═══ AUDIO ═══
    /// How to play the audio asset
    pub playback: PlaybackMode,

    /// Which audio bus/layer
    pub layer: AudioLayer,

    /// Priority within layer (higher = more important)
    pub priority: u8,

    /// ADSR timing
    pub timing: AudioTiming,

    /// Volume ducking behavior
    pub ducking: DuckBehavior,

    /// Base volume (0.0-1.0)
    pub volume: f32,

    /// Pan position (-1.0 left, 0.0 center, 1.0 right)
    pub pan: f32,

    /// Which stage stops this one (for loops)
    #[serde(default)]
    pub stopped_by: Vec<String>,

    /// Which stages this interrupts/cancels
    #[serde(default)]
    pub cancels: Vec<String>,

    // ═══ COMPLIANCE ═══
    /// Jurisdiction-aware compliance rules
    pub compliance: ComplianceFlags,

    // ═══ VISUAL ═══
    /// Suggested visual response
    pub visual: VisualHint,

    // ═══ METADATA ═══
    /// Suggested asset file pattern (e.g., "spin/reel_stop_{reel_index}")
    #[serde(default)]
    pub asset_pattern: Option<String>,

    /// Tags for filtering/routing in HELIX
    #[serde(default)]
    pub tags: Vec<String>,

    /// Whether this envelope can be overridden by blueprint config
    pub overridable: bool,
}

impl StageEnvelope {
    /// Check if this envelope requires a stop signal
    pub fn is_looping(&self) -> bool {
        self.playback == PlaybackMode::Loop
    }

    /// Check if compliance restricts this stage for a jurisdiction
    pub fn max_duration_for(&self, jurisdiction: &str) -> Option<f64> {
        self.compliance
            .max_duration_by_jurisdiction
            .get(jurisdiction)
            .copied()
    }

    /// Get effective priority (layer default + override)
    pub fn effective_priority(&self) -> u8 {
        if self.priority > 0 {
            self.priority
        } else {
            self.layer.default_priority()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE LIBRARY — The complete registry
// ═══════════════════════════════════════════════════════════════════════════════

/// The complete library of pre-built stage envelopes.
///
/// Created once at init, provides O(1) lookup by stage type name.
/// Blueprint-specific overrides are layered on top.
#[derive(Debug, Clone)]
pub struct StageLibrary {
    envelopes: HashMap<String, StageEnvelope>,
}

impl Default for StageLibrary {
    fn default() -> Self {
        Self::new()
    }
}

impl StageLibrary {
    /// Create with all built-in envelopes
    pub fn new() -> Self {
        let mut lib = Self {
            envelopes: HashMap::with_capacity(64),
        };
        lib.register_all_defaults();
        lib
    }

    /// Get envelope for a stage
    pub fn get(&self, stage: &Stage) -> Option<&StageEnvelope> {
        self.envelopes.get(stage.type_name())
    }

    /// Get envelope by type name
    pub fn get_by_name(&self, type_name: &str) -> Option<&StageEnvelope> {
        self.envelopes.get(type_name)
    }

    /// Override an envelope (blueprint customization)
    pub fn set_override(&mut self, envelope: StageEnvelope) {
        self.envelopes.insert(envelope.stage_type.clone(), envelope);
    }

    /// Get all envelopes
    pub fn all(&self) -> &HashMap<String, StageEnvelope> {
        &self.envelopes
    }

    /// Get envelopes by category
    pub fn by_category(&self, category: StageCategory) -> Vec<&StageEnvelope> {
        self.envelopes
            .values()
            .filter(|e| e.category == category)
            .collect()
    }

    /// Get all looping envelopes (need stop signals)
    pub fn looping_stages(&self) -> Vec<&StageEnvelope> {
        self.envelopes
            .values()
            .filter(|e| e.is_looping())
            .collect()
    }

    /// Validate that all stages have envelopes
    pub fn coverage_report(&self) -> StageCoverageReport {
        let all_names = Stage::all_type_names();
        let covered: Vec<&str> = all_names
            .iter()
            .filter(|n| self.envelopes.contains_key(**n))
            .copied()
            .collect();
        let missing: Vec<&str> = all_names
            .iter()
            .filter(|n| !self.envelopes.contains_key(**n))
            .copied()
            .collect();

        StageCoverageReport {
            total: all_names.len(),
            covered: covered.len(),
            missing_names: missing.iter().map(|s| s.to_string()).collect(),
            coverage_pct: if all_names.is_empty() {
                100.0
            } else {
                (covered.len() as f64 / all_names.len() as f64) * 100.0
            },
        }
    }

    /// Number of registered envelopes
    pub fn len(&self) -> usize {
        self.envelopes.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.envelopes.is_empty()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRATION — All 54+ stage envelopes
    // ═══════════════════════════════════════════════════════════════════════

    fn register_all_defaults(&mut self) {
        self.register_spin_lifecycle();
        self.register_anticipation();
        self.register_win_lifecycle();
        self.register_feature_lifecycle();
        self.register_cascade();
        self.register_bonus();
        self.register_gamble();
        self.register_jackpot();
        self.register_ui_idle();
        self.register_special();
    }

    fn register(&mut self, envelope: StageEnvelope) {
        self.envelopes
            .insert(envelope.stage_type.clone(), envelope);
    }

    // ─── SPIN LIFECYCLE ────────────────────────────────────────────────

    fn register_spin_lifecycle(&mut self) {
        // UiSpinPress — tactile button click
        self.register(StageEnvelope {
            stage_type: "ui_spin_press".into(),
            description: "Spin button pressed — tactile click feedback".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::UI,
            priority: 25,
            timing: AudioTiming::instant(),
            ducking: DuckBehavior::None,
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["idle_loop".into()],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::subtle_flash(),
            asset_pattern: Some("spin/button_press".into()),
            tags: vec!["input".into(), "haptic".into()],
            overridable: true,
        });

        // ReelSpinLoop — shared looping reel spin audio
        self.register(StageEnvelope {
            stage_type: "reel_spin_loop".into(),
            description: "Shared reel spin loop — plays until all reels stop".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Mechanics,
            priority: 35,
            timing: AudioTiming::looping(100.0, 200.0),
            ducking: DuckBehavior::DuckAmbient(0.3),
            volume: 0.6,
            pan: 0.0,
            stopped_by: vec!["spin_end".into()],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("spin/reel_spin_loop".into()),
            tags: vec!["mechanic".into(), "loop".into()],
            overridable: true,
        });

        // ReelSpinning — per-reel spin state (informational, no audio by default)
        self.register(StageEnvelope {
            stage_type: "reel_spinning".into(),
            description: "Individual reel spinning state marker".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Mechanics,
            priority: 30,
            timing: AudioTiming::looping(0.0, 0.0),
            ducking: DuckBehavior::None,
            volume: 0.0, // Silent by default — shared loop handles audio
            pan: 0.0,
            stopped_by: vec!["reel_stop".into(), "reel_spinning_stop".into()],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: None, // No asset — marker only
            tags: vec!["marker".into()],
            overridable: true,
        });

        // ReelSpinningStart — per-reel spin loop trigger
        self.register(StageEnvelope {
            stage_type: "reel_spinning_start".into(),
            description: "Per-reel spin loop start — for individual reel audio control".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Mechanics,
            priority: 32,
            timing: AudioTiming::looping(50.0, 150.0),
            ducking: DuckBehavior::None,
            volume: 0.4,
            pan: 0.0, // Will be spatialized by reel_index at runtime
            stopped_by: vec!["reel_spinning_stop".into()],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("spin/reel_spin_{reel_index}".into()),
            tags: vec!["mechanic".into(), "per_reel".into(), "loop".into()],
            overridable: true,
        });

        // ReelSpinningStop — per-reel spin loop fade-out trigger
        self.register(StageEnvelope {
            stage_type: "reel_spinning_stop".into(),
            description: "Per-reel spin loop stop — fade-out trigger".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::Tail,
            layer: AudioLayer::Mechanics,
            priority: 32,
            timing: AudioTiming {
                attack_ms: 0.0,
                sustain: false,
                release_ms: 150.0,
                release_curve: FadeCurve::Exponential,
                ..Default::default()
            },
            ducking: DuckBehavior::None,
            volume: 0.4,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("spin/reel_spin_stop_{reel_index}".into()),
            tags: vec!["mechanic".into(), "per_reel".into(), "tail".into()],
            overridable: true,
        });

        // ReelStop — reel landing impact
        self.register(StageEnvelope {
            stage_type: "reel_stop".into(),
            description: "Reel lands — satisfying mechanical thud".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 40,
            timing: AudioTiming::stinger(300.0),
            ducking: DuckBehavior::None,
            volume: 0.75,
            pan: 0.0, // Spatialized by reel_index at runtime
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::reel_stop(),
            asset_pattern: Some("spin/reel_stop_{reel_index}".into()),
            tags: vec!["mechanic".into(), "impact".into(), "per_reel".into()],
            overridable: true,
        });

        // EvaluateWins — brief processing moment
        self.register(StageEnvelope {
            stage_type: "evaluate_wins".into(),
            description: "Win evaluation — subtle processing indicator".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 20,
            timing: AudioTiming::instant(),
            ducking: DuckBehavior::None,
            volume: 0.0, // Silent by default — optional subtle tick
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: None,
            tags: vec!["marker".into()],
            overridable: true,
        });

        // SpinEnd — spin cycle complete
        self.register(StageEnvelope {
            stage_type: "spin_end".into(),
            description: "Spin cycle complete — cleanup and idle transition".into(),
            category: StageCategory::SpinLifecycle,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 15,
            timing: AudioTiming::instant(),
            ducking: DuckBehavior::None,
            volume: 0.0, // Silent marker
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["reel_spin_loop".into()],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: None,
            tags: vec!["marker".into(), "cleanup".into()],
            overridable: true,
        });
    }

    // ─── ANTICIPATION ──────────────────────────────────────────────────

    fn register_anticipation(&mut self) {
        // AnticipationOn — tension build starts
        self.register(StageEnvelope {
            stage_type: "anticipation_on".into(),
            description: "Anticipation triggered — tension build, slow spin".into(),
            category: StageCategory::Anticipation,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Accent,
            priority: 65,
            timing: AudioTiming::looping(200.0, 300.0),
            ducking: DuckBehavior::DuckAmbient(0.4),
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec!["anticipation_off".into(), "reel_stop".into()],
            cancels: vec![],
            compliance: ComplianceFlags {
                near_miss_restricted: true,
                rg_mutable: true,
                ..Default::default()
            },
            visual: VisualHint::anticipation(1),
            asset_pattern: Some("anticipation/tension_base".into()),
            tags: vec!["tension".into(), "loop".into()],
            overridable: true,
        });

        // AnticipationOff — tension resolved
        self.register(StageEnvelope {
            stage_type: "anticipation_off".into(),
            description: "Anticipation resolved — tension release".into(),
            category: StageCategory::Anticipation,
            playback: PlaybackMode::Tail,
            layer: AudioLayer::Accent,
            priority: 60,
            timing: AudioTiming {
                attack_ms: 0.0,
                sustain: false,
                release_ms: 500.0,
                release_curve: FadeCurve::Exponential,
                ..Default::default()
            },
            ducking: DuckBehavior::None,
            volume: 0.5,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["anticipation_on".into()],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("anticipation/resolve".into()),
            tags: vec!["tension".into(), "release".into()],
            overridable: true,
        });

        // AnticipationTensionLayer — escalating per-reel tension
        self.register(StageEnvelope {
            stage_type: "anticipation_tension_layer".into(),
            description: "Per-reel escalating tension — L1→L4 intensity layers".into(),
            category: StageCategory::Anticipation,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Accent,
            priority: 67,
            timing: AudioTiming::looping(150.0, 200.0),
            ducking: DuckBehavior::DuckAmbient(0.5),
            volume: 0.8,
            pan: 0.0,
            stopped_by: vec!["anticipation_off".into(), "reel_stop".into()],
            cancels: vec![],
            compliance: ComplianceFlags {
                near_miss_restricted: true,
                rg_mutable: true,
                ..Default::default()
            },
            visual: VisualHint::anticipation(2),
            asset_pattern: Some("anticipation/tension_l{tension_level}".into()),
            tags: vec!["tension".into(), "escalating".into(), "per_reel".into()],
            overridable: true,
        });
    }

    // ─── WIN LIFECYCLE ─────────────────────────────────────────────────

    fn register_win_lifecycle(&mut self) {
        // WinPresent
        self.register(StageEnvelope {
            stage_type: "win_present".into(),
            description: "Win celebration starting — fanfare proportional to win size".into(),
            category: StageCategory::WinLifecycle,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Wins,
            priority: 55,
            timing: AudioTiming {
                attack_ms: 10.0,
                sustain: false,
                release_ms: 200.0,
                min_duration_ms: 500.0,
                ..Default::default()
            },
            ducking: DuckBehavior::DuckAmbient(0.5),
            volume: 0.8,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint::win_present(1.0),
            asset_pattern: Some("wins/win_present".into()),
            tags: vec!["celebration".into(), "win".into()],
            overridable: true,
        });

        // WinLineShow
        self.register(StageEnvelope {
            stage_type: "win_line_show".into(),
            description: "Individual win line highlighted — short accent per line".into(),
            category: StageCategory::WinLifecycle,
            playback: PlaybackMode::Stinger,
            layer: AudioLayer::Wins,
            priority: 45,
            timing: AudioTiming::stinger(200.0),
            ducking: DuckBehavior::None,
            volume: 0.6,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint {
                flash_intensity: 0.4,
                animation: Some("line_highlight".into()),
                color_accent: Some("#FFD700".into()),
                ..Default::default()
            },
            asset_pattern: Some("wins/line_show".into()),
            tags: vec!["win".into(), "highlight".into()],
            overridable: true,
        });

        // RollupStart
        self.register(StageEnvelope {
            stage_type: "rollup_start".into(),
            description: "Win counter rollup beginning — ascending tone loop".into(),
            category: StageCategory::WinLifecycle,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Wins,
            priority: 50,
            timing: AudioTiming::looping(30.0, 100.0),
            ducking: DuckBehavior::DuckAmbient(0.4),
            volume: 0.65,
            pan: 0.0,
            stopped_by: vec!["rollup_end".into()],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint::none(),
            asset_pattern: Some("wins/rollup_loop".into()),
            tags: vec!["win".into(), "rollup".into(), "loop".into()],
            overridable: true,
        });

        // RollupTick
        self.register(StageEnvelope {
            stage_type: "rollup_tick".into(),
            description: "Rollup tick — granular counter sound, pitch rises with progress".into(),
            category: StageCategory::WinLifecycle,
            playback: PlaybackMode::Stinger,
            layer: AudioLayer::Wins,
            priority: 48,
            timing: AudioTiming::stinger(50.0),
            ducking: DuckBehavior::None,
            volume: 0.4,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint::none(),
            asset_pattern: Some("wins/rollup_tick".into()),
            tags: vec!["win".into(), "rollup".into(), "tick".into()],
            overridable: true,
        });

        // RollupEnd
        self.register(StageEnvelope {
            stage_type: "rollup_end".into(),
            description: "Rollup complete — satisfying resolution sting".into(),
            category: StageCategory::WinLifecycle,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Wins,
            priority: 52,
            timing: AudioTiming::stinger(500.0),
            ducking: DuckBehavior::None,
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["rollup_start".into()],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint::subtle_flash(),
            asset_pattern: Some("wins/rollup_end".into()),
            tags: vec!["win".into(), "rollup".into(), "resolve".into()],
            overridable: true,
        });

        // BigWinTier
        self.register(StageEnvelope {
            stage_type: "bigwin_tier".into(),
            description: "Big win tier reached — escalating celebration per tier".into(),
            category: StageCategory::WinLifecycle,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Wins,
            priority: 80,
            timing: AudioTiming::celebration(3_000.0, 20_000.0),
            ducking: DuckBehavior::DuckBelow(0.6),
            volume: 0.9,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::big_win(&BigWinTier::Win), // Overridden per-tier at runtime
            visual: VisualHint::win_present(50.0),
            asset_pattern: Some("wins/bigwin_{tier}".into()),
            tags: vec!["celebration".into(), "big_win".into(), "tiered".into()],
            overridable: true,
        });
    }

    // ─── FEATURE LIFECYCLE ─────────────────────────────────────────────

    fn register_feature_lifecycle(&mut self) {
        // FeatureEnter
        self.register(StageEnvelope {
            stage_type: "feature_enter".into(),
            description: "Entering feature — dramatic transition, music swap".into(),
            category: StageCategory::Feature,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Features,
            priority: 75,
            timing: AudioTiming {
                attack_ms: 300.0,
                sustain: false,
                release_ms: 0.0,
                attack_curve: FadeCurve::SCurve,
                min_duration_ms: 1_000.0,
                max_duration_ms: 3_000.0,
                ..Default::default()
            },
            ducking: DuckBehavior::DuckBelow(0.7),
            volume: 0.85,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["idle_loop".into(), "idle_start".into()],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::feature_enter(),
            asset_pattern: Some("features/{feature_type}/enter".into()),
            tags: vec!["feature".into(), "transition".into()],
            overridable: true,
        });

        // FeatureStep
        self.register(StageEnvelope {
            stage_type: "feature_step".into(),
            description: "Feature step (e.g., free spin) — contextual spin sound".into(),
            category: StageCategory::Feature,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Features,
            priority: 60,
            timing: AudioTiming::stinger(400.0),
            ducking: DuckBehavior::None,
            volume: 0.6,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("features/{feature_type}/step".into()),
            tags: vec!["feature".into(), "step".into()],
            overridable: true,
        });

        // FeatureRetrigger
        self.register(StageEnvelope {
            stage_type: "feature_retrigger".into(),
            description: "Feature retrigger — exciting bonus spins added".into(),
            category: StageCategory::Feature,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Features,
            priority: 78,
            timing: AudioTiming::celebration(1_500.0, 4_000.0),
            ducking: DuckBehavior::DuckBelow(0.5),
            volume: 0.85,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                particle_effect: Some("retrigger_burst".into()),
                screen_shake: 0.3,
                flash_intensity: 0.6,
                animation: Some("retrigger_celebration".into()),
                color_accent: Some("#00FF88".into()),
                ..Default::default()
            },
            asset_pattern: Some("features/{feature_type}/retrigger".into()),
            tags: vec!["feature".into(), "retrigger".into(), "celebration".into()],
            overridable: true,
        });

        // FeatureExit
        self.register(StageEnvelope {
            stage_type: "feature_exit".into(),
            description: "Exiting feature — transition back to base game".into(),
            category: StageCategory::Feature,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Features,
            priority: 70,
            timing: AudioTiming {
                attack_ms: 0.0,
                sustain: false,
                release_ms: 500.0,
                release_curve: FadeCurve::SCurve,
                min_duration_ms: 800.0,
                ..Default::default()
            },
            ducking: DuckBehavior::None,
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(), // Feature exit shows total win
            visual: VisualHint {
                animation: Some("feature_outro".into()),
                bg_dim: 0.2,
                ..Default::default()
            },
            asset_pattern: Some("features/{feature_type}/exit".into()),
            tags: vec!["feature".into(), "transition".into()],
            overridable: true,
        });
    }

    // ─── CASCADE ───────────────────────────────────────────────────────

    fn register_cascade(&mut self) {
        // CascadeStart
        self.register(StageEnvelope {
            stage_type: "cascade_start".into(),
            description: "Cascade/tumble sequence starting — symbols about to fall".into(),
            category: StageCategory::Cascade,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 45,
            timing: AudioTiming::stinger(300.0),
            ducking: DuckBehavior::None,
            volume: 0.6,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                animation: Some("cascade_shatter".into()),
                screen_shake: 0.1,
                ..Default::default()
            },
            asset_pattern: Some("cascade/start".into()),
            tags: vec!["cascade".into(), "mechanic".into()],
            overridable: true,
        });

        // CascadeStep
        self.register(StageEnvelope {
            stage_type: "cascade_step".into(),
            description: "Cascade step — symbols falling, pitch escalates per step".into(),
            category: StageCategory::Cascade,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 47,
            timing: AudioTiming::stinger(350.0),
            ducking: DuckBehavior::None,
            volume: 0.65,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                animation: Some("cascade_fall".into()),
                screen_shake: 0.08,
                ..Default::default()
            },
            asset_pattern: Some("cascade/step_{step_index}".into()),
            tags: vec!["cascade".into(), "escalating".into()],
            overridable: true,
        });

        // CascadeEnd
        self.register(StageEnvelope {
            stage_type: "cascade_end".into(),
            description: "Cascade complete — resolution sting".into(),
            category: StageCategory::Cascade,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 44,
            timing: AudioTiming::stinger(400.0),
            ducking: DuckBehavior::None,
            volume: 0.6,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("cascade/end".into()),
            tags: vec!["cascade".into(), "resolve".into()],
            overridable: true,
        });
    }

    // ─── BONUS ─────────────────────────────────────────────────────────

    fn register_bonus(&mut self) {
        // BonusEnter
        self.register(StageEnvelope {
            stage_type: "bonus_enter".into(),
            description: "Entering bonus game — dramatic scene change".into(),
            category: StageCategory::Bonus,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Features,
            priority: 75,
            timing: AudioTiming {
                attack_ms: 400.0,
                sustain: false,
                release_ms: 0.0,
                attack_curve: FadeCurve::SCurve,
                min_duration_ms: 1_500.0,
                max_duration_ms: 3_000.0,
                ..Default::default()
            },
            ducking: DuckBehavior::DuckBelow(0.7),
            volume: 0.85,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["idle_loop".into()],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::feature_enter(),
            asset_pattern: Some("bonus/{bonus_name}/enter".into()),
            tags: vec!["bonus".into(), "transition".into()],
            overridable: true,
        });

        // BonusChoice
        self.register(StageEnvelope {
            stage_type: "bonus_choice".into(),
            description: "Player making a choice — suspenseful awaiting input".into(),
            category: StageCategory::Bonus,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Features,
            priority: 55,
            timing: AudioTiming::looping(200.0, 300.0),
            ducking: DuckBehavior::DuckAmbient(0.3),
            volume: 0.5,
            pan: 0.0,
            stopped_by: vec!["bonus_reveal".into(), "bonus_prize_reveal".into()],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                animation: Some("choice_pulse".into()),
                flash_intensity: 0.2,
                ..Default::default()
            },
            asset_pattern: Some("bonus/choice_await".into()),
            tags: vec!["bonus".into(), "suspense".into(), "loop".into()],
            overridable: true,
        });

        // BonusReveal
        self.register(StageEnvelope {
            stage_type: "bonus_reveal".into(),
            description: "Bonus item revealed — surprise reveal sting".into(),
            category: StageCategory::Bonus,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Features,
            priority: 65,
            timing: AudioTiming::stinger(600.0),
            ducking: DuckBehavior::None,
            volume: 0.75,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["bonus_choice".into()],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint {
                particle_effect: Some("reveal_sparkle".into()),
                flash_intensity: 0.5,
                ..Default::default()
            },
            asset_pattern: Some("bonus/reveal".into()),
            tags: vec!["bonus".into(), "reveal".into()],
            overridable: true,
        });

        // BonusExit
        self.register(StageEnvelope {
            stage_type: "bonus_exit".into(),
            description: "Exiting bonus — transition to base game with win summary".into(),
            category: StageCategory::Bonus,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Features,
            priority: 70,
            timing: AudioTiming {
                attack_ms: 0.0,
                sustain: false,
                release_ms: 600.0,
                release_curve: FadeCurve::SCurve,
                min_duration_ms: 1_000.0,
                ..Default::default()
            },
            ducking: DuckBehavior::None,
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint {
                animation: Some("bonus_outro".into()),
                ..Default::default()
            },
            asset_pattern: Some("bonus/exit".into()),
            tags: vec!["bonus".into(), "transition".into()],
            overridable: true,
        });

        // BonusStart
        self.register(StageEnvelope {
            stage_type: "bonus_start".into(),
            description: "Bonus game starting — pick/wheel/etc begins".into(),
            category: StageCategory::Bonus,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Features,
            priority: 72,
            timing: AudioTiming {
                attack_ms: 100.0,
                sustain: false,
                release_ms: 200.0,
                min_duration_ms: 800.0,
                ..Default::default()
            },
            ducking: DuckBehavior::DuckAmbient(0.5),
            volume: 0.8,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::feature_enter(),
            asset_pattern: Some("bonus/{bonus_type}/start".into()),
            tags: vec!["bonus".into()],
            overridable: true,
        });

        // BonusPrizeReveal
        self.register(StageEnvelope {
            stage_type: "bonus_prize_reveal".into(),
            description: "Prize revealed in pick bonus — escalating excitement".into(),
            category: StageCategory::Bonus,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Features,
            priority: 68,
            timing: AudioTiming::stinger(700.0),
            ducking: DuckBehavior::None,
            volume: 0.75,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint {
                particle_effect: Some("prize_burst".into()),
                flash_intensity: 0.6,
                color_accent: Some("#FFD700".into()),
                ..Default::default()
            },
            asset_pattern: Some("bonus/prize_reveal_{prize_type}".into()),
            tags: vec!["bonus".into(), "reveal".into(), "prize".into()],
            overridable: true,
        });

        // BonusComplete
        self.register(StageEnvelope {
            stage_type: "bonus_complete".into(),
            description: "Bonus game complete — summary celebration".into(),
            category: StageCategory::Bonus,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Features,
            priority: 73,
            timing: AudioTiming::celebration(2_000.0, 6_000.0),
            ducking: DuckBehavior::DuckBelow(0.5),
            volume: 0.85,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint::win_present(30.0),
            asset_pattern: Some("bonus/complete".into()),
            tags: vec!["bonus".into(), "celebration".into()],
            overridable: true,
        });
    }

    // ─── GAMBLE ────────────────────────────────────────────────────────

    fn register_gamble(&mut self) {
        // GambleStart
        self.register(StageEnvelope {
            stage_type: "gamble_start".into(),
            description: "Gamble feature starting — tense atmosphere".into(),
            category: StageCategory::Gamble,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Features,
            priority: 65,
            timing: AudioTiming {
                attack_ms: 300.0,
                sustain: false,
                release_ms: 200.0,
                attack_curve: FadeCurve::SCurve,
                min_duration_ms: 500.0,
                ..Default::default()
            },
            ducking: DuckBehavior::DuckAmbient(0.5),
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags {
                rg_mutable: true,
                must_be_skippable: true,
                ..Default::default()
            },
            visual: VisualHint {
                bg_dim: 0.3,
                animation: Some("gamble_intro".into()),
                ..Default::default()
            },
            asset_pattern: Some("gamble/start".into()),
            tags: vec!["gamble".into(), "transition".into()],
            overridable: true,
        });

        // GambleChoice
        self.register(StageEnvelope {
            stage_type: "gamble_choice".into(),
            description: "Player making gamble choice — suspenseful loop".into(),
            category: StageCategory::Gamble,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Features,
            priority: 60,
            timing: AudioTiming::looping(200.0, 300.0),
            ducking: DuckBehavior::DuckAmbient(0.4),
            volume: 0.55,
            pan: 0.0,
            stopped_by: vec!["gamble_result".into()],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                animation: Some("gamble_pulse".into()),
                ..Default::default()
            },
            asset_pattern: Some("gamble/choice_loop".into()),
            tags: vec!["gamble".into(), "suspense".into(), "loop".into()],
            overridable: true,
        });

        // GambleResultStage
        self.register(StageEnvelope {
            stage_type: "gamble_result".into(),
            description: "Gamble result — win/lose/draw reveal".into(),
            category: StageCategory::Gamble,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Features,
            priority: 70,
            timing: AudioTiming::stinger(800.0),
            ducking: DuckBehavior::None,
            volume: 0.8,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["gamble_choice".into()],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint {
                flash_intensity: 0.6,
                ..Default::default()
            },
            asset_pattern: Some("gamble/result_{result}".into()),
            tags: vec!["gamble".into(), "result".into()],
            overridable: true,
        });

        // GambleEnd
        self.register(StageEnvelope {
            stage_type: "gamble_end".into(),
            description: "Gamble feature ending — collected or lost".into(),
            category: StageCategory::Gamble,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Features,
            priority: 62,
            timing: AudioTiming {
                attack_ms: 0.0,
                sustain: false,
                release_ms: 400.0,
                release_curve: FadeCurve::SCurve,
                ..Default::default()
            },
            ducking: DuckBehavior::None,
            volume: 0.6,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                animation: Some("gamble_outro".into()),
                ..Default::default()
            },
            asset_pattern: Some("gamble/end".into()),
            tags: vec!["gamble".into(), "transition".into()],
            overridable: true,
        });
    }

    // ─── JACKPOT ───────────────────────────────────────────────────────

    fn register_jackpot(&mut self) {
        // JackpotTrigger
        self.register(StageEnvelope {
            stage_type: "jackpot_trigger".into(),
            description: "Jackpot triggered — initial shock hit".into(),
            category: StageCategory::Jackpot,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Jackpot,
            priority: 95,
            timing: AudioTiming::stinger(1_500.0),
            ducking: DuckBehavior::MuteBelow,
            volume: 0.95,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![
                "idle_loop".into(),
                "reel_spin_loop".into(),
                "anticipation_on".into(),
            ],
            compliance: ComplianceFlags::jackpot(),
            visual: VisualHint {
                particle_effect: Some("jackpot_trigger_flash".into()),
                screen_shake: 0.6,
                flash_intensity: 1.0,
                color_accent: Some("#FF0000".into()),
                bg_dim: 0.5,
                ..Default::default()
            },
            asset_pattern: Some("jackpot/trigger_{tier}".into()),
            tags: vec!["jackpot".into(), "trigger".into(), "impact".into()],
            overridable: false, // Jackpot sounds are NOT overridable per compliance
        });

        // JackpotBuildup
        self.register(StageEnvelope {
            stage_type: "jackpot_buildup".into(),
            description: "Jackpot buildup — rising tension before tier reveal".into(),
            category: StageCategory::Jackpot,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Jackpot,
            priority: 97,
            timing: AudioTiming::looping(200.0, 400.0),
            ducking: DuckBehavior::MuteBelow,
            volume: 0.9,
            pan: 0.0,
            stopped_by: vec!["jackpot_reveal".into()],
            cancels: vec![],
            compliance: ComplianceFlags::jackpot(),
            visual: VisualHint {
                screen_shake: 0.4,
                flash_intensity: 0.7,
                animation: Some("jackpot_buildup_pulse".into()),
                bg_dim: 0.6,
                ..Default::default()
            },
            asset_pattern: Some("jackpot/buildup_{tier}".into()),
            tags: vec!["jackpot".into(), "buildup".into(), "tension".into()],
            overridable: false,
        });

        // JackpotReveal
        self.register(StageEnvelope {
            stage_type: "jackpot_reveal".into(),
            description: "Jackpot tier reveal — \"GRAND!\" announcement".into(),
            category: StageCategory::Jackpot,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Jackpot,
            priority: 100,
            timing: AudioTiming {
                attack_ms: 0.0,
                sustain: false,
                release_ms: 300.0,
                min_duration_ms: 2_000.0,
                max_duration_ms: 5_000.0,
                ..Default::default()
            },
            ducking: DuckBehavior::MuteBelow,
            volume: 1.0,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["jackpot_buildup".into()],
            compliance: ComplianceFlags::jackpot(),
            visual: VisualHint::jackpot(),
            asset_pattern: Some("jackpot/reveal_{tier}".into()),
            tags: vec!["jackpot".into(), "reveal".into(), "announcement".into()],
            overridable: false,
        });

        // JackpotPresent
        self.register(StageEnvelope {
            stage_type: "jackpot_present".into(),
            description: "Jackpot amount presentation — grand display with amount".into(),
            category: StageCategory::Jackpot,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Jackpot,
            priority: 98,
            timing: AudioTiming::celebration(5_000.0, 30_000.0),
            ducking: DuckBehavior::MuteBelow,
            volume: 1.0,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::jackpot(),
            visual: VisualHint::jackpot(),
            asset_pattern: Some("jackpot/present_{tier}".into()),
            tags: vec!["jackpot".into(), "celebration".into()],
            overridable: false,
        });

        // JackpotCelebration
        self.register(StageEnvelope {
            stage_type: "jackpot_celebration".into(),
            description: "Jackpot celebration loop — plays until player dismisses".into(),
            category: StageCategory::Jackpot,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Jackpot,
            priority: 96,
            timing: AudioTiming::looping(100.0, 800.0),
            ducking: DuckBehavior::MuteBelow,
            volume: 0.9,
            pan: 0.0,
            stopped_by: vec!["jackpot_end".into()],
            cancels: vec![],
            compliance: ComplianceFlags::jackpot(),
            visual: VisualHint {
                particle_effect: Some("jackpot_confetti".into()),
                screen_shake: 0.2,
                flash_intensity: 0.5,
                animation: Some("jackpot_celebration_loop".into()),
                color_accent: Some("#FFD700".into()),
                bg_dim: 0.4,
            },
            asset_pattern: Some("jackpot/celebration_{tier}".into()),
            tags: vec!["jackpot".into(), "celebration".into(), "loop".into()],
            overridable: false,
        });

        // JackpotEnd
        self.register(StageEnvelope {
            stage_type: "jackpot_end".into(),
            description: "Jackpot celebration complete — graceful fade to game".into(),
            category: StageCategory::Jackpot,
            playback: PlaybackMode::Tail,
            layer: AudioLayer::Jackpot,
            priority: 90,
            timing: AudioTiming {
                attack_ms: 0.0,
                sustain: false,
                release_ms: 1_000.0,
                release_curve: FadeCurve::SCurve,
                ..Default::default()
            },
            ducking: DuckBehavior::None,
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec!["jackpot_celebration".into()],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                animation: Some("jackpot_fade_out".into()),
                ..Default::default()
            },
            asset_pattern: Some("jackpot/end".into()),
            tags: vec!["jackpot".into(), "cleanup".into()],
            overridable: true,
        });
    }

    // ─── UI / IDLE ─────────────────────────────────────────────────────

    fn register_ui_idle(&mut self) {
        // IdleStart
        self.register(StageEnvelope {
            stage_type: "idle_start".into(),
            description: "Entering idle — ambient bed fades in".into(),
            category: StageCategory::UI,
            playback: PlaybackMode::Crossfade,
            layer: AudioLayer::Ambient,
            priority: 5,
            timing: AudioTiming {
                attack_ms: 2_000.0,
                sustain: false,
                release_ms: 500.0,
                attack_curve: FadeCurve::SCurve,
                ..Default::default()
            },
            ducking: DuckBehavior::None,
            volume: 0.4,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("ambient/idle_enter".into()),
            tags: vec!["ambient".into(), "transition".into()],
            overridable: true,
        });

        // IdleLoop
        self.register(StageEnvelope {
            stage_type: "idle_loop".into(),
            description: "Idle ambient loop — continuous background music/atmosphere".into(),
            category: StageCategory::UI,
            playback: PlaybackMode::Loop,
            layer: AudioLayer::Ambient,
            priority: 5,
            timing: AudioTiming::looping(0.0, 2_000.0),
            ducking: DuckBehavior::None,
            volume: 0.35,
            pan: 0.0,
            stopped_by: vec!["ui_spin_press".into(), "feature_enter".into(), "bonus_enter".into()],
            cancels: vec![],
            compliance: ComplianceFlags {
                rg_mutable: true,
                ..Default::default()
            },
            visual: VisualHint::none(),
            asset_pattern: Some("ambient/idle_loop".into()),
            tags: vec!["ambient".into(), "loop".into(), "music".into()],
            overridable: true,
        });

        // MenuOpen
        self.register(StageEnvelope {
            stage_type: "menu_open".into(),
            description: "Menu/settings opened — UI swoosh".into(),
            category: StageCategory::UI,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::UI,
            priority: 20,
            timing: AudioTiming::stinger(200.0),
            ducking: DuckBehavior::DuckAmbient(0.3),
            volume: 0.5,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("ui/menu_open".into()),
            tags: vec!["ui".into()],
            overridable: true,
        });

        // MenuClose
        self.register(StageEnvelope {
            stage_type: "menu_close".into(),
            description: "Menu/settings closed — UI swoosh reverse".into(),
            category: StageCategory::UI,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::UI,
            priority: 20,
            timing: AudioTiming::stinger(200.0),
            ducking: DuckBehavior::None,
            volume: 0.5,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("ui/menu_close".into()),
            tags: vec!["ui".into()],
            overridable: true,
        });

        // AutoplayStart
        self.register(StageEnvelope {
            stage_type: "autoplay_start".into(),
            description: "Autoplay engaged — subtle confirmation".into(),
            category: StageCategory::UI,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::UI,
            priority: 15,
            timing: AudioTiming::stinger(300.0),
            ducking: DuckBehavior::None,
            volume: 0.5,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::autoplay(),
            visual: VisualHint {
                animation: Some("autoplay_indicator".into()),
                ..Default::default()
            },
            asset_pattern: Some("ui/autoplay_on".into()),
            tags: vec!["ui".into(), "autoplay".into()],
            overridable: true,
        });

        // AutoplayStop
        self.register(StageEnvelope {
            stage_type: "autoplay_stop".into(),
            description: "Autoplay stopped — return to manual".into(),
            category: StageCategory::UI,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::UI,
            priority: 15,
            timing: AudioTiming::stinger(300.0),
            ducking: DuckBehavior::None,
            volume: 0.5,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::autoplay(),
            visual: VisualHint::none(),
            asset_pattern: Some("ui/autoplay_off".into()),
            tags: vec!["ui".into(), "autoplay".into()],
            overridable: true,
        });
    }

    // ─── SPECIAL ───────────────────────────────────────────────────────

    fn register_special(&mut self) {
        // SymbolTransform
        self.register(StageEnvelope {
            stage_type: "symbol_transform".into(),
            description: "Symbol morphing to another — magical transformation".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Accent,
            priority: 55,
            timing: AudioTiming::stinger(500.0),
            ducking: DuckBehavior::None,
            volume: 0.65,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                particle_effect: Some("transform_sparkle".into()),
                flash_intensity: 0.4,
                animation: Some("symbol_morph".into()),
                ..Default::default()
            },
            asset_pattern: Some("special/symbol_transform".into()),
            tags: vec!["special".into(), "transform".into()],
            overridable: true,
        });

        // WildExpand
        self.register(StageEnvelope {
            stage_type: "wild_expand".into(),
            description: "Wild expansion — dramatic reel fill".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Accent,
            priority: 60,
            timing: AudioTiming::stinger(800.0),
            ducking: DuckBehavior::DuckAmbient(0.3),
            volume: 0.75,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                particle_effect: Some("wild_expand_trail".into()),
                screen_shake: 0.15,
                flash_intensity: 0.5,
                animation: Some("wild_expand".into()),
                color_accent: Some("#00FF00".into()),
                ..Default::default()
            },
            asset_pattern: Some("special/wild_expand".into()),
            tags: vec!["special".into(), "wild".into()],
            overridable: true,
        });

        // MultiplierChange
        self.register(StageEnvelope {
            stage_type: "multiplier_change".into(),
            description: "Multiplier value changed — escalation accent".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::Stinger,
            layer: AudioLayer::Accent,
            priority: 55,
            timing: AudioTiming::stinger(400.0),
            ducking: DuckBehavior::None,
            volume: 0.65,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                flash_intensity: 0.4,
                animation: Some("multiplier_bump".into()),
                color_accent: Some("#FF6600".into()),
                ..Default::default()
            },
            asset_pattern: Some("special/multiplier_change".into()),
            tags: vec!["special".into(), "multiplier".into()],
            overridable: true,
        });

        // NearMiss
        self.register(StageEnvelope {
            stage_type: "near_miss".into(),
            description: "Near miss detected — subtle disappointment, compliance-restricted".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 35,
            timing: AudioTiming::stinger(400.0),
            ducking: DuckBehavior::None,
            volume: 0.3, // INTENTIONALLY LOW — near-miss must not be exciting (UKGC)
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::near_miss(),
            visual: VisualHint::none(), // NO visual excitement for near-miss (compliance)
            asset_pattern: Some("special/near_miss".into()),
            tags: vec!["special".into(), "near_miss".into(), "compliance".into()],
            overridable: false, // Near-miss audio is compliance-locked
        });

        // SymbolUpgrade
        self.register(StageEnvelope {
            stage_type: "symbol_upgrade".into(),
            description: "Symbol upgraded to higher tier — ascending tone".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Accent,
            priority: 58,
            timing: AudioTiming::stinger(500.0),
            ducking: DuckBehavior::None,
            volume: 0.7,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                particle_effect: Some("upgrade_shimmer".into()),
                flash_intensity: 0.5,
                animation: Some("symbol_upgrade".into()),
                color_accent: Some("#9900FF".into()),
                ..Default::default()
            },
            asset_pattern: Some("special/symbol_upgrade_t{upgrade_tier}".into()),
            tags: vec!["special".into(), "upgrade".into()],
            overridable: true,
        });

        // MysteryReveal
        self.register(StageEnvelope {
            stage_type: "mystery_reveal".into(),
            description: "Mystery symbols revealed — dramatic unveil".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Accent,
            priority: 62,
            timing: AudioTiming::stinger(700.0),
            ducking: DuckBehavior::DuckAmbient(0.3),
            volume: 0.75,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint {
                particle_effect: Some("mystery_unveil".into()),
                flash_intensity: 0.6,
                animation: Some("mystery_reveal".into()),
                color_accent: Some("#6600CC".into()),
                ..Default::default()
            },
            asset_pattern: Some("special/mystery_reveal".into()),
            tags: vec!["special".into(), "mystery".into(), "reveal".into()],
            overridable: true,
        });

        // MultiplierApply
        self.register(StageEnvelope {
            stage_type: "multiplier_apply".into(),
            description: "Multiplier applied to win — impact moment".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::Stinger,
            layer: AudioLayer::Wins,
            priority: 58,
            timing: AudioTiming::stinger(500.0),
            ducking: DuckBehavior::None,
            volume: 0.75,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::win_stage(),
            visual: VisualHint {
                screen_shake: 0.2,
                flash_intensity: 0.6,
                animation: Some("multiplier_apply_impact".into()),
                color_accent: Some("#FF6600".into()),
                ..Default::default()
            },
            asset_pattern: Some("special/multiplier_apply".into()),
            tags: vec!["special".into(), "multiplier".into(), "impact".into()],
            overridable: true,
        });

        // Custom (generic fallback)
        self.register(StageEnvelope {
            stage_type: "custom".into(),
            description: "Custom stage — engine-specific, fully overridable".into(),
            category: StageCategory::Special,
            playback: PlaybackMode::OneShot,
            layer: AudioLayer::Mechanics,
            priority: 30,
            timing: AudioTiming::stinger(300.0),
            ducking: DuckBehavior::None,
            volume: 0.5,
            pan: 0.0,
            stopped_by: vec![],
            cancels: vec![],
            compliance: ComplianceFlags::none(),
            visual: VisualHint::none(),
            asset_pattern: Some("custom/{name}".into()),
            tags: vec!["custom".into()],
            overridable: true,
        });
    }
}

/// Coverage report for stage library
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageCoverageReport {
    /// Total canonical stage count
    pub total: usize,
    /// Number of stages with envelopes
    pub covered: usize,
    /// Names of missing stages
    pub missing_names: Vec<String>,
    /// Coverage percentage
    pub coverage_pct: f64,
}

impl std::fmt::Display for StageCoverageReport {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Stage Coverage: {}/{} ({:.1}%)",
            self.covered, self.total, self.coverage_pct
        )?;
        if !self.missing_names.is_empty() {
            write!(f, " — Missing: {}", self.missing_names.join(", "))?;
        }
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_library_creates_with_all_defaults() {
        let lib = StageLibrary::new();
        assert!(lib.len() >= 50, "Expected 50+ envelopes, got {}", lib.len());
    }

    #[test]
    fn test_coverage_report() {
        let lib = StageLibrary::new();
        let report = lib.coverage_report();
        assert!(
            report.coverage_pct >= 90.0,
            "Coverage too low: {report}"
        );
    }

    #[test]
    fn test_every_stage_has_envelope() {
        let lib = StageLibrary::new();
        let report = lib.coverage_report();
        // We allow spin_start alias to be missing (it's mapped to ui_spin_press)
        let real_missing: Vec<_> = report
            .missing_names
            .iter()
            .filter(|n| *n != "spin_start")
            .collect();
        assert!(
            real_missing.is_empty(),
            "Missing envelopes: {:?}",
            real_missing
        );
    }

    #[test]
    fn test_lookup_by_stage() {
        let lib = StageLibrary::new();

        let envelope = lib.get(&Stage::UiSpinPress);
        assert!(envelope.is_some());
        assert_eq!(envelope.unwrap().playback, PlaybackMode::OneShot);
        assert_eq!(envelope.unwrap().layer, AudioLayer::UI);

        let envelope = lib.get(&Stage::ReelSpinLoop);
        assert!(envelope.is_some());
        assert_eq!(envelope.unwrap().playback, PlaybackMode::Loop);
    }

    #[test]
    fn test_lookup_by_name() {
        let lib = StageLibrary::new();

        let envelope = lib.get_by_name("reel_stop");
        assert!(envelope.is_some());
        assert_eq!(envelope.unwrap().layer, AudioLayer::Mechanics);
        assert!(envelope.unwrap().volume > 0.0);
    }

    #[test]
    fn test_looping_stages_have_stop_signals() {
        let lib = StageLibrary::new();
        for envelope in lib.looping_stages() {
            // Every looping stage should either have stopped_by or be a marker
            let is_marker = envelope.volume == 0.0;
            let has_stop = !envelope.stopped_by.is_empty();
            assert!(
                is_marker || has_stop,
                "Looping stage '{}' has no stop signal and is not a silent marker",
                envelope.stage_type
            );
        }
    }

    #[test]
    fn test_jackpot_stages_not_overridable() {
        let lib = StageLibrary::new();
        let jackpot_stages = lib.by_category(StageCategory::Jackpot);
        for env in &jackpot_stages {
            // All jackpot stages except jackpot_end should be locked
            if env.stage_type != "jackpot_end" {
                assert!(
                    !env.overridable,
                    "Jackpot stage '{}' should NOT be overridable (compliance)",
                    env.stage_type
                );
            }
        }
    }

    #[test]
    fn test_near_miss_compliance() {
        let lib = StageLibrary::new();
        let near_miss = lib.get_by_name("near_miss").unwrap();

        // Near-miss MUST be compliance-restricted
        assert!(near_miss.compliance.near_miss_restricted);
        // Near-miss MUST NOT be overridable
        assert!(!near_miss.overridable);
        // Near-miss MUST have low volume (not exciting)
        assert!(
            near_miss.volume <= 0.4,
            "Near-miss volume too high: {} (compliance risk)",
            near_miss.volume
        );
        // Near-miss MUST NOT have visual effects (no excitement)
        assert_eq!(
            near_miss.visual.screen_shake, 0.0,
            "Near-miss must not have screen shake"
        );
        assert_eq!(
            near_miss.visual.flash_intensity, 0.0,
            "Near-miss must not have flash"
        );
        assert!(
            near_miss.visual.particle_effect.is_none(),
            "Near-miss must not have particles"
        );
    }

    #[test]
    fn test_big_win_compliance_durations() {
        let compliance = ComplianceFlags::big_win(&BigWinTier::UltraWin);
        assert!(compliance.proportional_celebration);
        assert!(compliance.ldw_sensitive);
        assert!(compliance.must_be_skippable);

        // UKGC should have stricter limits than MGA
        let ukgc = compliance.max_duration_by_jurisdiction.get("ukgc").unwrap();
        let mga = compliance.max_duration_by_jurisdiction.get("mga").unwrap();
        assert!(ukgc < mga, "UKGC should be stricter than MGA");
    }

    #[test]
    fn test_audio_timing_presets() {
        let instant = AudioTiming::instant();
        assert_eq!(instant.attack_ms, 0.0);
        assert_eq!(instant.release_ms, 0.0);
        assert!(!instant.sustain);

        let looping = AudioTiming::looping(100.0, 200.0);
        assert!(looping.sustain);
        assert_eq!(looping.attack_ms, 100.0);
        assert_eq!(looping.release_ms, 200.0);

        let celebration = AudioTiming::celebration(3000.0, 10000.0);
        assert!(celebration.sustain);
        assert_eq!(celebration.min_duration_ms, 3000.0);
        assert_eq!(celebration.max_duration_ms, 10000.0);
    }

    #[test]
    fn test_category_filtering() {
        let lib = StageLibrary::new();

        let spin = lib.by_category(StageCategory::SpinLifecycle);
        assert!(spin.len() >= 7, "Expected 7+ spin stages, got {}", spin.len());

        let jackpot = lib.by_category(StageCategory::Jackpot);
        assert!(
            jackpot.len() >= 6,
            "Expected 6+ jackpot stages, got {}",
            jackpot.len()
        );

        let ui = lib.by_category(StageCategory::UI);
        assert!(ui.len() >= 5, "Expected 5+ UI stages, got {}", ui.len());
    }

    #[test]
    fn test_override_envelope() {
        let mut lib = StageLibrary::new();

        // Override reel_stop with custom volume
        let original = lib.get_by_name("reel_stop").unwrap().clone();
        assert_eq!(original.volume, 0.75);

        let mut custom = original;
        custom.volume = 0.9;
        lib.set_override(custom);

        let updated = lib.get_by_name("reel_stop").unwrap();
        assert_eq!(updated.volume, 0.9);
    }

    #[test]
    fn test_effective_priority() {
        let lib = StageLibrary::new();

        // Jackpot should have highest priority
        let jackpot = lib.get_by_name("jackpot_reveal").unwrap();
        let ui = lib.get_by_name("menu_open").unwrap();

        assert!(
            jackpot.effective_priority() > ui.effective_priority(),
            "Jackpot ({}) should be higher priority than UI ({})",
            jackpot.effective_priority(),
            ui.effective_priority()
        );
    }

    #[test]
    fn test_ducking_hierarchy() {
        let lib = StageLibrary::new();

        // Jackpot should mute everything below
        let jackpot = lib.get_by_name("jackpot_trigger").unwrap();
        assert_eq!(jackpot.ducking, DuckBehavior::MuteBelow);

        // Big win should duck below
        let bigwin = lib.get_by_name("bigwin_tier").unwrap();
        assert!(matches!(bigwin.ducking, DuckBehavior::DuckBelow(_)));

        // UI should not duck
        let menu = lib.get_by_name("menu_open").unwrap();
        assert!(matches!(menu.ducking, DuckBehavior::DuckAmbient(_)));
    }

    #[test]
    fn test_serialization_roundtrip() {
        let lib = StageLibrary::new();
        let envelope = lib.get_by_name("reel_stop").unwrap();

        let json = serde_json::to_string(envelope).unwrap();
        let deserialized: StageEnvelope = serde_json::from_str(&json).unwrap();

        assert_eq!(envelope.stage_type, deserialized.stage_type);
        assert_eq!(envelope.playback, deserialized.playback);
        assert_eq!(envelope.volume, deserialized.volume);
        assert_eq!(envelope.priority, deserialized.priority);
    }

    #[test]
    fn test_asset_patterns_are_present() {
        let lib = StageLibrary::new();
        let mut missing_patterns = Vec::new();

        for env in lib.all().values() {
            // Only marker stages (volume=0) can skip asset patterns
            if env.volume > 0.0 && env.asset_pattern.is_none() {
                missing_patterns.push(&env.stage_type);
            }
        }

        assert!(
            missing_patterns.is_empty(),
            "Stages with audio but no asset pattern: {:?}",
            missing_patterns
        );
    }

    // ─── Compliance Depth Tests ───────────────────────────────────────────────

    #[test]
    fn test_near_miss_has_jurisdiction_durations() {
        // ROOT CAUSE FIX: near_miss compliance had no max_duration_by_jurisdiction
        // UKGC/MGA/SE/DE all have near-miss duration limits — must be enforced
        let compliance = ComplianceFlags::near_miss();

        let ukgc = compliance.max_duration_by_jurisdiction.get("ukgc");
        let mga  = compliance.max_duration_by_jurisdiction.get("mga");
        let se   = compliance.max_duration_by_jurisdiction.get("se");
        let de   = compliance.max_duration_by_jurisdiction.get("de");

        assert!(ukgc.is_some(), "near_miss must have UKGC duration limit");
        assert!(mga.is_some(),  "near_miss must have MGA duration limit");
        assert!(se.is_some(),   "near_miss must have SE duration limit");
        assert!(de.is_some(),   "near_miss must have DE duration limit");

        // UKGC is most restrictive for near-miss
        assert!(*ukgc.unwrap() <= 500.0, "UKGC near-miss max must be ≤500ms");
        assert!(*se.unwrap()   <= 400.0, "SE near-miss max must be ≤400ms");
        assert!(*ukgc.unwrap() <= *mga.unwrap(), "UKGC must be ≤ MGA for near-miss");
        assert!(*se.unwrap()   <= *ukgc.unwrap(), "SE must be most restrictive");
    }

    #[test]
    fn test_bonus_buy_compliance_prohibited_jurisdictions() {
        // Bonus Buy is BANNED in UKGC (Oct 2021) and DE (GlüStV 2021)
        let compliance = ComplianceFlags::bonus_buy();

        assert!(compliance.bonus_buy_restricted, "bonus_buy must be restricted");
        assert!(!compliance.is_allowed_in("ukgc"), "Bonus Buy MUST be banned in UKGC");
        assert!(!compliance.is_allowed_in("de"),   "Bonus Buy MUST be banned in DE");
        assert!(compliance.is_allowed_in("mga"),   "Bonus Buy IS allowed in MGA (with restrictions)");
    }

    #[test]
    fn test_ldw_detection() {
        let compliance = ComplianceFlags::win_stage();

        // LDW: win ≤ bet = loss disguised as win
        assert!(compliance.is_ldw(1.0, 2.0),   "win=1, bet=2 → LDW (win < bet)");
        assert!(compliance.is_ldw(2.0, 2.0),   "win=2, bet=2 → LDW (win == bet, UKGC definition)");
        assert!(!compliance.is_ldw(2.01, 2.0), "win=2.01, bet=2 → NOT LDW");
        assert!(!compliance.is_ldw(10.0, 2.0), "win=10, bet=2 → NOT LDW");

        // LDW guard disabled for jackpot stages (always real win)
        let jackpot = ComplianceFlags::jackpot();
        assert!(!jackpot.is_ldw(1.0, 2.0), "Jackpot stage: LDW guard disabled (jackpots are real wins)");
    }

    #[test]
    fn test_autoplay_max_spins_by_jurisdiction() {
        let compliance = ComplianceFlags::autoplay();

        let ukgc = compliance.autoplay_max_spins_by_jurisdiction.get("ukgc");
        let se   = compliance.autoplay_max_spins_by_jurisdiction.get("se");
        let de   = compliance.autoplay_max_spins_by_jurisdiction.get("de");

        assert!(ukgc.is_some(), "Autoplay must have UKGC spin limit");
        assert!(se.is_some(),   "Autoplay must have SE spin limit");
        assert!(de.is_some(),   "Autoplay must have DE spin limit");

        // SE and DE are more restrictive than UKGC
        assert!(*se.unwrap()   <= *ukgc.unwrap(), "SE must be ≤ UKGC for autoplay spins");
        assert!(*de.unwrap()   <= *se.unwrap(),   "DE must be most restrictive (GlüStV 2021)");
        assert!(*ukgc.unwrap() <= 300,            "UKGC max autoplay ≤ 300");
        assert!(*de.unwrap()   <= 100,            "DE max autoplay ≤ 100");
    }
}

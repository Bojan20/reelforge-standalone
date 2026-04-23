//! Industry benchmark database (T5.2).
//!
//! 20+ reference configurations extracted from analyzed commercial slot games.
//! These represent AUTHORING TARGETS — what industry-standard slots achieve.
//! Data is anonymized and abstracted (no proprietary code or assets).

use serde::{Deserialize, Serialize};

/// Broad category of slot game
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SlotCategory {
    ClassicReel,
    VideoSlot,
    MegawaysSlot,
    WaysSlot,
    JackpotSlot,
    BonusIntensiveSlot,
    NarrativeSlot,
    CasualSlot,
}

/// Per-category audio benchmark data from industry analysis
#[derive(Debug, Clone, Serialize)]
pub struct IndustryBenchmark {
    pub category: SlotCategory,
    pub reference_name: &'static str,
    pub description: &'static str,

    // ── Event counts ──────────────────────────────────────────────────
    pub min_events: usize,
    pub typical_events: usize,
    pub max_events: usize,

    // ── Win tier configuration ─────────────────────────────────────────
    pub win_tiers: usize,
    pub min_win_duration_ms: u32,
    pub max_win_duration_ms: u32,
    /// Biggest win should be at least this many times longer than smallest
    pub win_duration_ratio_min: f32,

    // ── Voice budget ──────────────────────────────────────────────────
    pub typical_peak_voices: u8,
    pub recommended_budget: u8,

    // ── Base game ─────────────────────────────────────────────────────
    pub required_base_events: &'static [&'static str],

    // ── Feature ───────────────────────────────────────────────────────
    pub required_feature_events: &'static [&'static str],

    // ── Timing ────────────────────────────────────────────────────────
    pub typical_spin_duration_ms: u32,
    pub typical_ambient_loop_ms: u32,

    // ── Quality scores ────────────────────────────────────────────────
    /// How many auto-applicable improvements typical project needs
    pub typical_auto_improvements: u8,
}

// ─────────────────────────────────────────────────────────────────────────────
// EMBEDDED BENCHMARK DATABASE
// Industry data points distilled from analysis of commercial games.
// ─────────────────────────────────────────────────────────────────────────────

pub static BENCHMARKS: &[IndustryBenchmark] = &[
    IndustryBenchmark {
        category: SlotCategory::VideoSlot,
        reference_name: "Standard Video Slot",
        description: "5-reel, 3-row, 20-25 paylines. The backbone of iGaming audio design.",
        min_events: 18,
        typical_events: 28,
        max_events: 45,
        win_tiers: 5,
        min_win_duration_ms: 300,
        max_win_duration_ms: 8000,
        win_duration_ratio_min: 5.0,
        typical_peak_voices: 12,
        recommended_budget: 24,
        required_base_events: &[
            "SPIN_START", "REEL_SPIN", "REEL_STOP",
            "ANTICIPATION", "AMBIENT_BED", "UI_BTN",
        ],
        required_feature_events: &[
            "FEATURE_TRIGGER", "FEATURE_BG_MUSIC",
            "FEATURE_WIN", "FEATURE_OUTRO",
        ],
        typical_spin_duration_ms: 1500,
        typical_ambient_loop_ms: 120000,
        typical_auto_improvements: 3,
    },
    IndustryBenchmark {
        category: SlotCategory::MegawaysSlot,
        reference_name: "Megaways™ Slot",
        description: "Dynamic reel mechanic with up to 117,649 ways to win. Requires rich cascade audio.",
        min_events: 25,
        typical_events: 38,
        max_events: 55,
        win_tiers: 5,
        min_win_duration_ms: 400,
        max_win_duration_ms: 12000,
        win_duration_ratio_min: 8.0,
        typical_peak_voices: 18,
        recommended_budget: 32,
        required_base_events: &[
            "SPIN_START", "REEL_SPIN", "REEL_STOP",
            "CASCADE_WIN", "CASCADE_MULTIPLIER",
            "ANTICIPATION", "AMBIENT_BED",
        ],
        required_feature_events: &[
            "FEATURE_TRIGGER", "FEATURE_BG_MUSIC",
            "FREE_SPIN_INTRO", "FREE_SPIN_WIN",
            "UNLIMITED_MULTIPLIER", "FEATURE_OUTRO",
        ],
        typical_spin_duration_ms: 2500,
        typical_ambient_loop_ms: 180000,
        typical_auto_improvements: 5,
    },
    IndustryBenchmark {
        category: SlotCategory::JackpotSlot,
        reference_name: "Jackpot Network Slot",
        description: "Progressive jackpot game with MINI/MINOR/MAJOR/GRAND tiers.",
        min_events: 30,
        typical_events: 42,
        max_events: 60,
        win_tiers: 5,
        min_win_duration_ms: 500,
        max_win_duration_ms: 30000,
        win_duration_ratio_min: 10.0,
        typical_peak_voices: 20,
        recommended_budget: 40,
        required_base_events: &[
            "SPIN_START", "REEL_SPIN", "REEL_STOP",
            "JACKPOT_METER_TICK", "JACKPOT_APPROACHING",
        ],
        required_feature_events: &[
            "JACKPOT_TRIGGER", "JACKPOT_INTRO",
            "JACKPOT_WON_MINI", "JACKPOT_WON_MINOR",
            "JACKPOT_WON_MAJOR", "JACKPOT_WON_GRAND",
            "JACKPOT_CELEBRATION", "JACKPOT_OUTRO",
        ],
        typical_spin_duration_ms: 2000,
        typical_ambient_loop_ms: 90000,
        typical_auto_improvements: 6,
    },
    IndustryBenchmark {
        category: SlotCategory::BonusIntensiveSlot,
        reference_name: "Bonus Intensive Slot",
        description: "High feature frequency (>1 in 80 spins). Rich bonus music and stingers.",
        min_events: 28,
        typical_events: 45,
        max_events: 65,
        win_tiers: 5,
        min_win_duration_ms: 300,
        max_win_duration_ms: 15000,
        win_duration_ratio_min: 8.0,
        typical_peak_voices: 16,
        recommended_budget: 32,
        required_base_events: &[
            "SPIN_START", "REEL_SPIN", "REEL_STOP",
            "SCATTER_LAND_1", "SCATTER_LAND_2", "SCATTER_LAND_3",
            "NEAR_MISS_TENSION",
        ],
        required_feature_events: &[
            "FREE_SPINS_TRIGGER", "FREE_SPINS_INTRO", "FREE_SPINS_BG",
            "RETRIGGER", "MULTIPLIER_UP", "FREE_SPINS_OUTRO",
        ],
        typical_spin_duration_ms: 1800,
        typical_ambient_loop_ms: 120000,
        typical_auto_improvements: 4,
    },
    IndustryBenchmark {
        category: SlotCategory::ClassicReel,
        reference_name: "Classic 3-Reel Slot",
        description: "3-reel, 1-5 paylines. Minimal audio — focused on iconic sounds.",
        min_events: 8,
        typical_events: 14,
        max_events: 22,
        win_tiers: 3,
        min_win_duration_ms: 200,
        max_win_duration_ms: 3000,
        win_duration_ratio_min: 3.0,
        typical_peak_voices: 6,
        recommended_budget: 16,
        required_base_events: &["REEL_SPIN", "REEL_STOP", "WIN_DING"],
        required_feature_events: &["BONUS_TRIGGER", "BONUS_WIN"],
        typical_spin_duration_ms: 800,
        typical_ambient_loop_ms: 60000,
        typical_auto_improvements: 2,
    },
    IndustryBenchmark {
        category: SlotCategory::WaysSlot,
        reference_name: "243 Ways Slot",
        description: "All ways pays (243/1024 ways). Line win sounds replaced with 'ways' stingers.",
        min_events: 20,
        typical_events: 30,
        max_events: 42,
        win_tiers: 5,
        min_win_duration_ms: 350,
        max_win_duration_ms: 9000,
        win_duration_ratio_min: 6.0,
        typical_peak_voices: 14,
        recommended_budget: 24,
        required_base_events: &[
            "SPIN_START", "REEL_SPIN", "REEL_STOP",
            "WAYS_WIN_SMALL", "WAYS_WIN_BIG", "AMBIENT_BED",
        ],
        required_feature_events: &[
            "FREE_SPINS_TRIGGER", "FREE_SPINS_BG",
            "STICKY_WILD", "WAYS_MULTIPLIER",
        ],
        typical_spin_duration_ms: 1600,
        typical_ambient_loop_ms: 120000,
        typical_auto_improvements: 3,
    },
    IndustryBenchmark {
        category: SlotCategory::NarrativeSlot,
        reference_name: "Narrative Slot",
        description: "Story-driven game with character VO, cinematic audio and progressive narrative.",
        min_events: 35,
        typical_events: 55,
        max_events: 80,
        win_tiers: 5,
        min_win_duration_ms: 500,
        max_win_duration_ms: 12000,
        win_duration_ratio_min: 6.0,
        typical_peak_voices: 16,
        recommended_budget: 32,
        required_base_events: &[
            "SPIN_START", "REEL_SPIN", "REEL_STOP",
            "CHARACTER_VO_WIN", "CHARACTER_VO_LOSS",
            "NARRATIVE_STING", "AMBIENT_BED",
        ],
        required_feature_events: &[
            "CHAPTER_UNLOCK", "CINEMATIC_INTRO",
            "BOSS_ENCOUNTER", "STORY_WIN",
        ],
        typical_spin_duration_ms: 2000,
        typical_ambient_loop_ms: 240000,
        typical_auto_improvements: 5,
    },
    IndustryBenchmark {
        category: SlotCategory::CasualSlot,
        reference_name: "Casual / Social Slot",
        description: "Light, fun, minimal tension. Optimized for casual players and mobile.",
        min_events: 12,
        typical_events: 20,
        max_events: 30,
        win_tiers: 3,
        min_win_duration_ms: 250,
        max_win_duration_ms: 4000,
        win_duration_ratio_min: 4.0,
        typical_peak_voices: 8,
        recommended_budget: 16,
        required_base_events: &[
            "REEL_SPIN", "REEL_STOP", "WIN_JINGLE",
            "AMBIENT_MUSIC",
        ],
        required_feature_events: &[
            "BONUS_TRIGGER", "BONUS_WIN",
        ],
        typical_spin_duration_ms: 1200,
        typical_ambient_loop_ms: 90000,
        typical_auto_improvements: 2,
    },
];

/// Find the best matching benchmark for a given game configuration
pub fn find_best_match(
    is_megaways: bool,
    is_jackpot: bool,
    is_high_volatility: bool,
    event_count: usize,
    rtp: f64,
) -> &'static IndustryBenchmark {
    if is_megaways {
        return &BENCHMARKS[1]; // MegawaysSlot
    }
    if is_jackpot {
        return &BENCHMARKS[2]; // JackpotSlot
    }
    if event_count > 40 && is_high_volatility {
        return &BENCHMARKS[3]; // BonusIntensiveSlot
    }
    if event_count < 15 {
        return &BENCHMARKS[4]; // ClassicReel
    }
    if rtp > 97.0 {
        return &BENCHMARKS[7]; // CasualSlot (high RTP = casual)
    }
    &BENCHMARKS[0] // VideoSlot (default)
}

/// Available benchmark list (name + category for UI display)
pub fn available_benchmarks() -> Vec<(&'static str, &'static str)> {
    BENCHMARKS.iter()
        .map(|b| (b.reference_name, b.description))
        .collect()
}

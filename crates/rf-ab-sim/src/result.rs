//! Batch simulation result structures

use std::collections::HashMap;
use serde::{Deserialize, Serialize};

/// Frequency statistics for a single audio event
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct EventFrequency {
    /// Total times this event fired in the simulation
    pub count: u64,
    /// Average fires per 1000 spins
    pub avg_per_1000_spins: f64,
    /// Maximum simultaneous occurrences at any point
    pub peak_concurrent: u32,
    /// Minimum gap between consecutive fires (milliseconds)
    pub min_gap_ms: u64,
    /// Maximum gap between consecutive fires (milliseconds)
    pub max_gap_ms: u64,
    /// Standard deviation of gaps (milliseconds)
    pub gap_stddev_ms: f64,
}

impl EventFrequency {
    pub fn new(count: u64, spin_count: u64) -> Self {
        Self {
            count,
            avg_per_1000_spins: if spin_count > 0 {
                count as f64 / spin_count as f64 * 1000.0
            } else {
                0.0
            },
            ..Default::default()
        }
    }
}

/// Dry spell analysis
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DrySpellReport {
    /// Maximum consecutive non-winning spins in the simulation
    pub max_dry_spins: u32,
    /// Average dry spell length
    pub avg_dry_spins: f64,
    /// Percentage of spins that are dead (no win)
    pub dead_spin_pct: f64,
    /// Histogram: count of dry spells by length bucket
    /// Key: lower bound of bucket (0, 5, 10, 20, 50, 100, 200+)
    pub dry_spell_histogram: HashMap<u32, u64>,
}

/// Win distribution per tier
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WinDistribution {
    /// Count of wins per tier (tier_name → count)
    pub per_tier_count: HashMap<String, u64>,
    /// RTP contribution per tier (tier_name → fraction of total paid)
    pub per_tier_rtp_contribution: HashMap<String, f64>,
    /// Total wins in simulation
    pub total_wins: u64,
    /// Total spins with no win
    pub total_losses: u64,
    /// Computed actual RTP from simulation
    pub actual_rtp: f64,
}

/// A point-in-time sample from the simulation timeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineSample {
    /// Spin number at this sample point
    pub spin_number: u64,
    /// Events that fired at this spin
    pub events: Vec<String>,
    /// Active voice count at this spin
    pub active_voices: u32,
    /// Cumulative RTP at this point
    pub cumulative_rtp: f64,
    /// Consecutive dry spins before this sample
    pub consecutive_dry: u32,
}

/// Voice budget prediction summary
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct VoiceBudgetPrediction {
    /// Peak simultaneous voices observed across entire simulation
    pub peak_voices: u32,
    /// Configured voice budget limit
    pub voice_budget: u32,
    /// Fraction of time voices exceeded budget (0.0 = never)
    pub budget_exceeded_fraction: f64,
    /// Spins where budget was exceeded
    pub budget_exceeded_count: u64,
    /// Average voice utilization (0.0–1.0)
    pub avg_utilization: f64,
    /// Highest-risk audio scenarios (event combinations)
    pub high_risk_combinations: Vec<String>,
}

/// Complete batch simulation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchSimResult {
    // ── Core stats ──────────────────────────────────────────────────────────
    /// Actual RTP computed from simulation
    pub actual_rtp: f64,

    /// Target RTP from config (0.0 if not set)
    pub target_rtp: f64,

    /// RTP delta (actual - target)
    pub rtp_delta: f64,

    /// Total spins simulated
    pub spin_count: u64,

    /// Simulation duration in milliseconds
    pub sim_duration_ms: u64,

    // ── Event frequency heatmap ───────────────────────────────────────────
    /// Per-event frequency statistics
    pub event_frequency_map: HashMap<String, EventFrequency>,

    // ── Voice budget ─────────────────────────────────────────────────────
    /// Voice budget analysis
    pub voice_budget: VoiceBudgetPrediction,

    // ── Dry spell analysis ───────────────────────────────────────────────
    pub dry_spell_analysis: DrySpellReport,

    // ── Win distribution ─────────────────────────────────────────────────
    pub win_distribution: WinDistribution,

    // ── Timeline samples ─────────────────────────────────────────────────
    /// One sample per `timeline_sample_rate` spins
    pub timeline_samples: Vec<TimelineSample>,

    // ── Warnings ─────────────────────────────────────────────────────────
    pub warnings: Vec<String>,
}

impl BatchSimResult {
    pub fn empty(spin_count: u64, target_rtp: f64) -> Self {
        Self {
            actual_rtp: 0.0,
            target_rtp,
            rtp_delta: 0.0,
            spin_count,
            sim_duration_ms: 0,
            event_frequency_map: HashMap::new(),
            voice_budget: VoiceBudgetPrediction::default(),
            dry_spell_analysis: DrySpellReport::default(),
            win_distribution: WinDistribution::default(),
            timeline_samples: Vec::new(),
            warnings: Vec::new(),
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal per-thread accumulator (merged at end)
// ─────────────────────────────────────────────────────────────────────────────

/// Minimal accumulator for one simulation batch (per-thread, zero-alloc inner loop)
#[derive(Debug, Default)]
pub(crate) struct BatchAccumulator {
    pub spin_count: u64,
    pub total_win_amount: f64,
    pub total_bet_amount: f64,

    /// Event counters (event_name → count)
    pub event_counts: HashMap<String, u64>,

    /// Win tier counts
    pub win_tier_counts: HashMap<String, u64>,

    /// Win tier total payout
    pub win_tier_payout: HashMap<String, f64>,

    /// Dry spell tracking
    pub current_dry_streak: u32,
    pub max_dry_streak: u32,
    pub total_dry_spins: u64,
    pub dry_spell_lengths: Vec<u32>,

    /// Voice peak
    pub peak_voices: u32,

    /// Timeline samples
    pub timeline_samples: Vec<TimelineSample>,

    /// Gap tracking (last spin each event fired)
    pub last_event_spin: HashMap<String, u64>,
    pub min_gap_per_event: HashMap<String, u64>,
    pub max_gap_per_event: HashMap<String, u64>,
}

impl BatchAccumulator {
    /// Merge another accumulator into self
    pub fn merge(&mut self, other: BatchAccumulator) {
        self.spin_count += other.spin_count;
        self.total_win_amount += other.total_win_amount;
        self.total_bet_amount += other.total_bet_amount;

        for (name, count) in other.event_counts {
            *self.event_counts.entry(name).or_insert(0) += count;
        }
        for (name, count) in other.win_tier_counts {
            *self.win_tier_counts.entry(name).or_insert(0) += count;
        }
        for (name, payout) in other.win_tier_payout {
            *self.win_tier_payout.entry(name).or_insert(0.0) += payout;
        }

        self.max_dry_streak = self.max_dry_streak.max(other.max_dry_streak);
        self.total_dry_spins += other.total_dry_spins;
        self.dry_spell_lengths.extend(other.dry_spell_lengths);

        self.peak_voices = self.peak_voices.max(other.peak_voices);
        self.timeline_samples.extend(other.timeline_samples);

        // Merge gaps (take min/max across both)
        for (event, gap) in other.min_gap_per_event {
            let entry = self.min_gap_per_event.entry(event).or_insert(u64::MAX);
            *entry = (*entry).min(gap);
        }
        for (event, gap) in other.max_gap_per_event {
            let entry = self.max_gap_per_event.entry(event).or_insert(0);
            *entry = (*entry).max(gap);
        }
    }

    /// Finalize into BatchSimResult
    pub fn finalize(
        mut self,
        total_spins: u64,
        target_rtp: f64,
        voice_budget: u32,
        sim_duration_ms: u64,
    ) -> BatchSimResult {
        let actual_rtp = if self.total_bet_amount > 0.0 {
            self.total_win_amount / self.total_bet_amount
        } else {
            0.0
        };

        // Event frequency map
        let event_frequency_map: HashMap<String, EventFrequency> = self
            .event_counts
            .into_iter()
            .map(|(name, count)| {
                let min_gap = self.min_gap_per_event.get(&name).copied().unwrap_or(0);
                let max_gap = self.max_gap_per_event.get(&name).copied().unwrap_or(0);
                (
                    name,
                    EventFrequency {
                        count,
                        avg_per_1000_spins: count as f64 / total_spins as f64 * 1000.0,
                        peak_concurrent: 1, // TODO: track concurrent in voice sim
                        min_gap_ms: min_gap,
                        max_gap_ms: max_gap,
                        gap_stddev_ms: 0.0, // Approximate
                    },
                )
            })
            .collect();

        // Dry spell report
        let avg_dry = if self.dry_spell_lengths.is_empty() {
            0.0
        } else {
            self.dry_spell_lengths.iter().map(|&x| x as f64).sum::<f64>()
                / self.dry_spell_lengths.len() as f64
        };

        let mut dry_hist: HashMap<u32, u64> = HashMap::new();
        for &len in &self.dry_spell_lengths {
            let bucket = match len {
                0..=4 => 0,
                5..=9 => 5,
                10..=19 => 10,
                20..=49 => 20,
                50..=99 => 50,
                100..=199 => 100,
                _ => 200,
            };
            *dry_hist.entry(bucket).or_insert(0) += 1;
        }

        let dry_spell_analysis = DrySpellReport {
            max_dry_spins: self.max_dry_streak,
            avg_dry_spins: avg_dry,
            dead_spin_pct: self.total_dry_spins as f64 / total_spins.max(1) as f64,
            dry_spell_histogram: dry_hist,
        };

        // Win distribution
        let total_wins: u64 = self.win_tier_counts.values().sum();
        let total_losses = total_spins.saturating_sub(total_wins);
        let total_payout: f64 = self.win_tier_payout.values().sum();

        let per_tier_rtp: HashMap<String, f64> = self
            .win_tier_payout
            .iter()
            .map(|(k, v)| {
                (
                    k.clone(),
                    if total_payout > 0.0 { v / total_payout } else { 0.0 },
                )
            })
            .collect();

        let win_distribution = WinDistribution {
            per_tier_count: self.win_tier_counts,
            per_tier_rtp_contribution: per_tier_rtp,
            total_wins,
            total_losses,
            actual_rtp,
        };

        // Voice budget
        let voice_budget_pred = VoiceBudgetPrediction {
            peak_voices: self.peak_voices,
            voice_budget,
            budget_exceeded_fraction: 0.0, // TODO: track in voice simulation
            budget_exceeded_count: 0,
            avg_utilization: self.peak_voices as f64 / voice_budget.max(1) as f64,
            high_risk_combinations: Vec::new(),
        };

        // Sort timeline samples
        self.timeline_samples.sort_by_key(|s| s.spin_number);

        // Warnings
        let mut warnings = Vec::new();
        let rtp_delta = actual_rtp - target_rtp / 100.0;
        if target_rtp > 0.0 && rtp_delta.abs() > 0.005 {
            warnings.push(format!(
                "Simulated RTP {:.4}% differs from target {:.4}% by {:.4}%",
                actual_rtp * 100.0,
                target_rtp,
                rtp_delta.abs() * 100.0
            ));
        }
        if self.peak_voices > voice_budget {
            warnings.push(format!(
                "Peak voices ({}) exceeded budget ({}) — audio clipping risk",
                self.peak_voices, voice_budget
            ));
        }
        if dry_spell_analysis.max_dry_spins > 100 {
            warnings.push(format!(
                "Max dry spell of {} spins may cause player frustration",
                dry_spell_analysis.max_dry_spins
            ));
        }

        BatchSimResult {
            actual_rtp,
            target_rtp,
            rtp_delta,
            spin_count: total_spins,
            sim_duration_ms,
            event_frequency_map,
            voice_budget: voice_budget_pred,
            dry_spell_analysis,
            win_distribution,
            timeline_samples: self.timeline_samples,
            warnings,
        }
    }
}

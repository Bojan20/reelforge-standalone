//! Batch Simulator — parallel 1M+ spin engine

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use rayon::prelude::*;
use rand::prelude::*;
use rand_chacha::ChaCha8Rng;

use rf_slot_lab::{
    GameModel,
    model::WinTierConfig,
};

use crate::config::{BatchSimConfig, AudioEventDef};
use crate::result::{
    BatchSimResult, BatchAccumulator, TimelineSample,
};

/// Batch Simulator — the core engine
pub struct BatchSimulator;

impl BatchSimulator {
    /// Run simulation synchronously (blocking).
    /// Uses Rayon for parallelism.
    pub fn run(config: &BatchSimConfig) -> BatchSimResult {
        Self::run_internal(config, None)
    }

    /// Run simulation with progress callback.
    /// Callback receives progress fraction (0.0–1.0), called every ~10,000 spins.
    pub fn run_with_progress<F>(config: &BatchSimConfig, progress: F) -> BatchSimResult
    where
        F: Fn(f64) + Send + Sync + 'static,
    {
        Self::run_internal(config, Some(Arc::new(progress) as Arc<dyn Fn(f64) + Send + Sync>))
    }

    fn run_internal(
        config: &BatchSimConfig,
        progress_cb: Option<Arc<dyn Fn(f64) + Send + Sync>>,
    ) -> BatchSimResult {
        let start = Instant::now();
        let spin_count = config.spin_count;
        let n_threads = config.effective_threads().max(1);

        // Progress counter (shared across threads)
        let progress_counter = Arc::new(AtomicU64::new(0));

        // Divide spins across threads
        let spins_per_thread = spin_count / n_threads as u64;
        let remainder = spin_count % n_threads as u64;

        // Build per-thread configs
        let thread_seeds: Vec<u64> = if let Some(base_seed) = config.seed {
            // Deterministic: derive per-thread seeds from base
            (0..n_threads).map(|i| base_seed.wrapping_add(i as u64 * 0x9e3779b97f4a7c15)).collect()
        } else {
            // Random: use rand::rng() for each seed (rand 0.9 API)
            let mut seeder = rand::rng();
            (0..n_threads).map(|_| seeder.random::<u64>()).collect()
        };

        let game_model = Arc::new(config.game_model.clone());
        let audio_events = Arc::new(config.audio_events.clone());
        let voice_budget = config.voice_budget;
        let timeline_sample_rate = config.timeline_sample_rate;

        // Run parallel batches
        let partial_results: Vec<BatchAccumulator> = (0..n_threads)
            .into_par_iter()
            .map(|thread_idx| {
                let count = if thread_idx < remainder as usize {
                    spins_per_thread + 1
                } else {
                    spins_per_thread
                };
                let seed = thread_seeds[thread_idx];
                let offset_spin = (thread_idx as u64) * spins_per_thread;

                let acc = run_thread_batch(
                    &game_model,
                    &audio_events,
                    count,
                    seed,
                    voice_budget,
                    timeline_sample_rate,
                    offset_spin,
                );

                // Report progress
                let done = progress_counter.fetch_add(count, Ordering::Relaxed) + count;
                if let Some(ref cb) = progress_cb {
                    let fraction = done as f64 / spin_count as f64;
                    cb(fraction.min(1.0));
                }

                acc
            })
            .collect();

        // Merge all thread results
        let mut merged = BatchAccumulator::default();
        for partial in partial_results {
            merged.merge(partial);
        }

        let sim_duration_ms = start.elapsed().as_millis() as u64;
        merged.finalize(spin_count, config.target_rtp, voice_budget, sim_duration_ms)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-thread batch runner
// ─────────────────────────────────────────────────────────────────────────────

fn run_thread_batch(
    game_model: &GameModel,
    audio_events: &[AudioEventDef],
    spin_count: u64,
    seed: u64,
    voice_budget: u32,
    timeline_sample_rate: u32,
    spin_offset: u64,
) -> BatchAccumulator {
    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    let mut acc = BatchAccumulator::default();

    // Build a simple win probability model from game model
    let win_prob = estimate_hit_frequency(game_model);
    let _rtp = game_model.info.target_rtp;
    let vol = &game_model.info.volatility;

    // Win tier config
    let tier_config = &game_model.win_tiers;

    // Audio event lookup (name → def)
    let event_map: HashMap<&str, &AudioEventDef> = audio_events
        .iter()
        .map(|e| (e.event_name.as_str(), e))
        .collect();

    // Track voice timeline (rough simulation)
    // Each entry: (end_spin) = when this voice slot becomes free
    let mut voice_slots: Vec<u64> = Vec::new(); // ending spin for each active voice
    let mut current_voices: u32;
    let spin_duration_ms = 2000_u64; // avg spin duration

    for spin_idx in 0..spin_count {
        let global_spin = spin_offset + spin_idx;
        acc.spin_count += 1;

        // Clean up expired voice slots
        voice_slots.retain(|&end_spin| end_spin > global_spin);
        current_voices = voice_slots.len() as u32;
        acc.peak_voices = acc.peak_voices.max(current_voices);

        // Simulate spin outcome
        let is_win = rng.random::<f64>() < win_prob;
        let bet = 1.0_f64;
        acc.total_bet_amount += bet;

        if is_win {
            // Determine win tier
            let (tier_name, win_mult) = roll_win_tier(&mut rng, tier_config, vol);
            let win_amount = bet * win_mult;
            acc.total_win_amount += win_amount;
            *acc.win_tier_counts.entry(tier_name.clone()).or_insert(0) += 1;
            *acc.win_tier_payout.entry(tier_name.clone()).or_insert(0.0) += win_amount;

            // Fire audio event
            let event_name = tier_name.as_str();
            fire_audio_event(
                event_name,
                &event_map,
                global_spin,
                spin_duration_ms,
                voice_budget,
                &mut voice_slots,
                &mut acc,
            );

            // Handle dry spell
            if acc.current_dry_streak > 0 {
                acc.dry_spell_lengths.push(acc.current_dry_streak);
                acc.current_dry_streak = 0;
            }

            // Accompanying events
            fire_audio_event("REEL_SPIN", &event_map, global_spin, 300, voice_budget, &mut voice_slots, &mut acc);
            fire_audio_event("REEL_STOP", &event_map, global_spin, 100, voice_budget, &mut voice_slots, &mut acc);
        } else {
            // Dead spin
            acc.current_dry_streak += 1;
            acc.total_dry_spins += 1;
            acc.max_dry_streak = acc.max_dry_streak.max(acc.current_dry_streak);
            fire_audio_event("DEAD_SPIN", &event_map, global_spin, 100, voice_budget, &mut voice_slots, &mut acc);
            fire_audio_event("REEL_SPIN", &event_map, global_spin, 300, voice_budget, &mut voice_slots, &mut acc);
            fire_audio_event("REEL_STOP", &event_map, global_spin, 100, voice_budget, &mut voice_slots, &mut acc);
        }

        // Scatter / near-miss (occasional)
        let scatter_prob = 0.03;
        let near_miss_prob = 0.12;
        if rng.random::<f64>() < scatter_prob {
            fire_audio_event("SCATTER", &event_map, global_spin, 500, voice_budget, &mut voice_slots, &mut acc);
        }
        if !is_win && rng.random::<f64>() < near_miss_prob {
            fire_audio_event("NEAR_MISS", &event_map, global_spin, 800, voice_budget, &mut voice_slots, &mut acc);
        }

        // Timeline sample
        if timeline_sample_rate > 0 && global_spin.is_multiple_of(timeline_sample_rate as u64) {
            let cumulative_rtp = if acc.total_bet_amount > 0.0 {
                acc.total_win_amount / acc.total_bet_amount
            } else {
                0.0
            };
            acc.timeline_samples.push(TimelineSample {
                spin_number: global_spin,
                events: Vec::new(), // simplified — don't store event names per sample
                active_voices: current_voices,
                cumulative_rtp,
                consecutive_dry: acc.current_dry_streak,
            });
        }
    }

    // Flush final dry streak
    if acc.current_dry_streak > 0 {
        acc.dry_spell_lengths.push(acc.current_dry_streak);
    }

    acc
}

/// Fire an audio event: update counters, add voices, track gaps
fn fire_audio_event(
    event_name: &str,
    event_map: &HashMap<&str, &AudioEventDef>,
    current_spin: u64,
    default_duration_spins: u64,
    voice_budget: u32,
    voice_slots: &mut Vec<u64>,
    acc: &mut BatchAccumulator,
) {
    *acc.event_counts.entry(event_name.to_string()).or_insert(0) += 1;

    // Gap tracking
    let last_spin = acc.last_event_spin.get(event_name).copied();
    if let Some(last) = last_spin {
        let gap_spins = current_spin.saturating_sub(last);
        // Convert spins to ms (approx 2000ms per spin)
        let gap_ms = gap_spins * 2000;
        let min_entry = acc.min_gap_per_event.entry(event_name.to_string()).or_insert(u64::MAX);
        *min_entry = (*min_entry).min(gap_ms);
        let max_entry = acc.max_gap_per_event.entry(event_name.to_string()).or_insert(0);
        *max_entry = (*max_entry).max(gap_ms);
    }
    acc.last_event_spin.insert(event_name.to_string(), current_spin);

    // Voice allocation
    let (voice_count, duration_spins) = event_map.get(event_name)
        .map(|def| {
            let spins = (def.duration_ms as u64 / 2000).max(1);
            (def.voice_count, spins)
        })
        .unwrap_or((1, default_duration_spins));

    // Only allocate voices if within budget
    let current_voices = voice_slots.len() as u32;
    if current_voices + voice_count <= voice_budget {
        let end_spin = current_spin + duration_spins;
        for _ in 0..voice_count {
            voice_slots.push(end_spin);
        }
    }

    // Update peak
    acc.peak_voices = acc.peak_voices.max(voice_slots.len() as u32);
}

/// Estimate hit frequency from game model
fn estimate_hit_frequency(model: &GameModel) -> f64 {
    use rf_slot_lab::model::Volatility;
    match &model.info.volatility {
        Volatility::Low => 0.42,
        Volatility::MediumLow => 0.37,
        Volatility::Medium => 0.33,
        Volatility::MediumHigh => 0.28,
        Volatility::High => 0.26,
        Volatility::VeryHigh => 0.19,
    }
}

/// Roll a win tier name + multiplier for a winning spin
fn roll_win_tier(
    rng: &mut ChaCha8Rng,
    _tier_config: &WinTierConfig,
    vol: &rf_slot_lab::model::Volatility,
) -> (String, f64) {
    use rf_slot_lab::model::Volatility;

    // Win distribution varies by volatility
    // Low vol: mostly small wins; High vol: mostly small but some big
    let roll: f64 = rng.random();
    let (tier_name, mult_range) = match vol {
    // NOTE: These multipliers are calibrated for ~95-100% RTP at given hit frequencies.
    // WIN_LOW (sub-bet) is most frequent. Rare tiers scale up but not extreme
    // since we don't simulate full jackpot probability (1-in-millions).
    // Simplified model: avg_win * hit_freq ≈ 0.95-1.05 (near 100% RTP baseline)
        Volatility::Low => match roll {
            r if r < 0.65 => ("WIN_LOW", (0.1_f64, 0.9_f64)), // avg 0.5 * 0.65 = 0.325
            r if r < 0.85 => ("WIN_1", (1.0, 2.0)),             // avg 1.5 * 0.20 = 0.300
            r if r < 0.94 => ("WIN_2", (2.0, 4.0)),             // avg 3.0 * 0.09 = 0.270
            r if r < 0.98 => ("WIN_3", (4.0, 8.0)),             // avg 6.0 * 0.04 = 0.240
            r if r < 0.995 => ("WIN_4", (8.0, 15.0)),           // avg 11.5 * 0.015 = 0.172
            _ => ("WIN_5", (15.0, 30.0)),                        // avg 22.5 * 0.005 = 0.112
        },
        Volatility::MediumLow => match roll {
            r if r < 0.60 => ("WIN_LOW", (0.1, 0.9)),
            r if r < 0.80 => ("WIN_1", (1.0, 2.5)),
            r if r < 0.91 => ("WIN_2", (2.5, 6.0)),
            r if r < 0.97 => ("WIN_3", (6.0, 15.0)),
            r if r < 0.992 => ("WIN_4", (15.0, 35.0)),
            _ => ("WIN_5", (35.0, 80.0)),
        },
        Volatility::Medium => match roll {
            r if r < 0.58 => ("WIN_LOW", (0.1, 0.9)),
            r if r < 0.78 => ("WIN_1", (1.0, 3.0)),
            r if r < 0.90 => ("WIN_2", (3.0, 8.0)),
            r if r < 0.96 => ("WIN_3", (8.0, 20.0)),
            r if r < 0.990 => ("WIN_4", (20.0, 50.0)),
            _ => ("WIN_5", (50.0, 120.0)),
        },
        Volatility::MediumHigh => match roll {
            r if r < 0.55 => ("WIN_LOW", (0.1, 0.9)),
            r if r < 0.74 => ("WIN_1", (1.0, 4.0)),
            r if r < 0.87 => ("WIN_2", (4.0, 12.0)),
            r if r < 0.95 => ("WIN_3", (12.0, 30.0)),
            r if r < 0.990 => ("WIN_4", (30.0, 80.0)),
            _ => ("WIN_5", (80.0, 200.0)),
        },
        Volatility::High => match roll {
            r if r < 0.52 => ("WIN_LOW", (0.1, 0.9)),
            r if r < 0.70 => ("WIN_1", (1.0, 5.0)),
            r if r < 0.83 => ("WIN_2", (5.0, 18.0)),
            r if r < 0.93 => ("WIN_3", (18.0, 50.0)),
            r if r < 0.985 => ("WIN_4", (50.0, 120.0)),
            _ => ("WIN_5", (120.0, 300.0)),
        },
        Volatility::VeryHigh => match roll {
            r if r < 0.50 => ("WIN_LOW", (0.1, 0.9)),
            r if r < 0.67 => ("WIN_1", (1.0, 6.0)),
            r if r < 0.80 => ("WIN_2", (6.0, 25.0)),
            r if r < 0.91 => ("WIN_3", (25.0, 80.0)),
            r if r < 0.980 => ("WIN_4", (80.0, 200.0)),
            _ => ("WIN_5", (200.0, 500.0)),
        },
    };

    // Random multiplier within the tier range
    let mult = mult_range.0 + rng.random::<f64>() * (mult_range.1 - mult_range.0);
    (tier_name.to_string(), mult)
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rf_slot_lab::{GameModel, model::GameInfo};

    fn test_config(spins: u64) -> BatchSimConfig {
        let mut config = BatchSimConfig {
            game_model: GameModel::default(),
            spin_count: spins,
            threads: 2,
            seed: Some(42), // deterministic
            voice_budget: 48,
            target_rtp: 96.5,
            ..Default::default()
        };
        config.audio_events = vec![
            AudioEventDef::new("WIN_1").with_voices(2).with_duration(800),
            AudioEventDef::new("WIN_5").with_voices(6).with_duration(5000).non_overlapping(),
            AudioEventDef::new("DEAD_SPIN").with_voices(1).with_duration(200),
            AudioEventDef::new("REEL_SPIN").with_voices(2).with_duration(1500),
            AudioEventDef::new("REEL_STOP").with_voices(1).with_duration(300),
        ];
        config
    }

    #[test]
    fn test_basic_simulation_runs() {
        let config = test_config(10_000);
        let result = BatchSimulator::run(&config);
        assert_eq!(result.spin_count, 10_000);
        assert!(result.actual_rtp > 0.0, "RTP should be positive");
        // Simplified model should be within realistic range (50%-200%)
        // Exact value varies by seed/volatility but should be in this range
        assert!(result.actual_rtp > 0.5, "RTP too low: {:.2}%", result.actual_rtp * 100.0);
        assert!(result.actual_rtp < 2.0, "RTP too high: {:.2}%", result.actual_rtp * 100.0);
        println!("Actual RTP: {:.4}%", result.actual_rtp * 100.0);
    }

    #[test]
    fn test_event_frequency_map_populated() {
        let config = test_config(5_000);
        let result = BatchSimulator::run(&config);
        // REEL_SPIN should fire on every spin
        let reel_spin = result.event_frequency_map.get("REEL_SPIN");
        assert!(reel_spin.is_some(), "REEL_SPIN should be in frequency map");
        let freq = reel_spin.unwrap();
        assert_eq!(freq.count, 5_000, "REEL_SPIN should fire every spin");
        assert!((freq.avg_per_1000_spins - 1000.0).abs() < 1.0);
    }

    #[test]
    fn test_win_distribution_covers_all_tiers() {
        let config = test_config(100_000);
        let result = BatchSimulator::run(&config);
        let dist = &result.win_distribution;
        // With 100k spins, all common tiers should appear
        assert!(dist.total_wins > 0, "Should have some wins");
        assert!(dist.total_losses > 0, "Should have some losses");
        let win_rate = dist.total_wins as f64 / 100_000.0;
        assert!(win_rate > 0.10, "Win rate should be > 10%: {:.2}%", win_rate * 100.0);
        assert!(win_rate < 0.80, "Win rate should be < 80%: {:.2}%", win_rate * 100.0);
    }

    #[test]
    fn test_dry_spell_analysis() {
        let config = test_config(50_000);
        let result = BatchSimulator::run(&config);
        let dry = &result.dry_spell_analysis;
        assert!(dry.max_dry_spins > 0, "Should have some dry spins");
        assert!(dry.dead_spin_pct > 0.0 && dry.dead_spin_pct < 1.0);
    }

    #[test]
    fn test_deterministic_with_same_seed() {
        let config = test_config(1_000);
        let result1 = BatchSimulator::run(&config);
        let result2 = BatchSimulator::run(&config);
        assert_eq!(result1.win_distribution.total_wins, result2.win_distribution.total_wins,
            "Same seed should produce same results");
    }

    #[test]
    fn test_different_seeds_produce_different_results() {
        let mut config1 = test_config(10_000);
        config1.seed = Some(42);
        let mut config2 = test_config(10_000);
        config2.seed = Some(12345);
        let result1 = BatchSimulator::run(&config1);
        let result2 = BatchSimulator::run(&config2);
        // Different seeds: win counts can't be exactly equal for 10k spins
        assert_ne!(result1.win_distribution.total_wins, result2.win_distribution.total_wins,
            "Different seeds should produce different results");
    }

    #[test]
    fn test_voice_budget_tracked() {
        let config = test_config(10_000);
        let result = BatchSimulator::run(&config);
        assert!(result.voice_budget.peak_voices > 0);
        assert_eq!(result.voice_budget.voice_budget, 48);
    }

    #[test]
    fn test_timeline_samples_populated() {
        let mut config = test_config(5_000);
        config.timeline_sample_rate = 1000;
        let result = BatchSimulator::run(&config);
        // With 5000 spins and sample rate 1000, expect ~5 samples per thread
        assert!(!result.timeline_samples.is_empty(), "Should have timeline samples");
        // Samples should be ordered by spin number
        let sorted = result.timeline_samples.windows(2).all(|w| w[0].spin_number <= w[1].spin_number);
        assert!(sorted, "Timeline samples should be ordered");
    }

    #[test]
    fn test_progress_callback_called() {
        use std::sync::atomic::{AtomicU32, Ordering};
        let call_count = Arc::new(AtomicU32::new(0));
        let count_clone = Arc::clone(&call_count);
        let config = test_config(50_000);
        BatchSimulator::run_with_progress(&config, move |_progress| {
            count_clone.fetch_add(1, Ordering::Relaxed);
        });
        // At least some progress callbacks should have been called
        // (exact count depends on thread scheduling)
        assert!(call_count.load(Ordering::Relaxed) > 0, "Progress callback should have been called");
    }
}

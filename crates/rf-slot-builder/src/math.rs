//! # 3.7.K — RTP Solver
//!
//! Computes a suggested paytable distribution given target RTP and volatility.
//!
//! ## Algorithm
//!
//! 1. Model a **50-stop reel strip**. Assign each paying symbol a stop count
//!    using a Zipf distribution over stops (low vol → even distribution;
//!    high vol → premium symbols rare, low symbols abundant).
//!
//! 2. Symbol probability = stop_count / 50.
//!
//! 3. For each symbol tier assign pay multipliers using a geometric progression.
//!    The top symbol pays `base_top`× bet; each lower tier divides by `tier_ratio`.
//!
//! 4. Compute initial RTP using the standard slot math formula:
//!    ```text
//!    RTP = Σ_sym Σ_k P(k-match, sym) × pay[k]
//!    ```
//!    where `P(k-match) = p^k × (1-p)` for k < reels, `p^reels` for k = reels.
//!    Note: the paylines factor cancels (total bet = paylines × 1 unit per line,
//!    expected return = paylines × per-payline expected return → ratio = 1).
//!
//! 5. **Binary-search** a global pay-scale factor until `|achieved - target| < 5e-4`.
//!
//! 6. Round pays to integers and return the solved `MathConfig`.

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════
// Public Input / Output types
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for the RTP solver.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpSolverConfig {
    /// Target RTP, e.g. 0.965 for 96.5%. Clamped to [0.80, 0.999].
    pub target_rtp: f64,

    /// Volatility index 1–10 (1 = low, 10 = high). Drives Zipf stop distribution.
    pub volatility_index: u8,

    /// Number of distinct paying symbol tiers (excluding wild/scatter).
    /// Typical range: 4–10. Values outside this are clamped.
    pub paying_symbol_count: u8,

    /// Reel count (typically 5).
    pub reel_count: u8,

    /// Row count (typically 3).
    pub row_count: u8,

    /// Payline count (informational — affects hit frequency display only, not RTP).
    /// Pass 0 to use `row_count^reel_count` ways-to-win approximation.
    pub payline_count: u16,

    /// Include a wild symbol in the result set.
    pub include_wild: bool,

    /// Include a scatter / free-spin trigger in the result set.
    pub include_scatter: bool,
}

impl Default for RtpSolverConfig {
    fn default() -> Self {
        Self {
            target_rtp: 0.965,
            volatility_index: 5,
            paying_symbol_count: 6,
            reel_count: 5,
            row_count: 3,
            payline_count: 20,
            include_wild: true,
            include_scatter: true,
        }
    }
}

/// A single solved symbol with pay schedule and analytical statistics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolvedSymbol {
    /// Sequential ID (0 = highest paying premium, ascending).
    pub id: u32,
    /// Human-readable name, e.g. "Premium 1", "Low 3".
    pub name: String,
    /// Is this a wild symbol?
    pub is_wild: bool,
    /// Is this a scatter symbol?
    pub is_scatter: bool,
    /// Pay multipliers indexed by match count. Length = reel_count + 1.
    /// pays[0]=unused, pays[1]=1-of-N (usually 0), …, pays[5]=5-of-5.
    pub pays: Vec<f64>,
    /// Fraction of reel stops occupied by this symbol (stop_count / 50).
    pub reel_probability: f64,
    /// Stop count on a 50-stop reel strip.
    pub stop_count: u8,
    /// This symbol's RTP contribution (fraction of bet returned, per spin).
    pub rtp_contribution: f64,
    /// Probability of this symbol contributing to a win on a given spin.
    pub win_frequency: f64,
}

/// Full RTP solver solution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpSolution {
    /// Solved symbols with pay schedules.
    pub symbols: Vec<SolvedSymbol>,
    /// Achieved RTP (within 5e-4 of target before rounding, slightly different after).
    pub achieved_rtp: f64,
    /// Target RTP from config.
    pub target_rtp: f64,
    /// Delta: achieved − target (positive = slightly above, from rounding).
    pub rtp_delta: f64,
    /// Estimated hit frequency per spin (probability of winning on any payline).
    pub hit_frequency: f64,
    /// Number of binary-search iterations used.
    pub iterations: u32,
}

// ═══════════════════════════════════════════════════════════════════════════
// Strip stop model
// ═══════════════════════════════════════════════════════════════════════════

/// Compute stop counts for `n` paying symbols on a `STRIP_LEN`-stop reel.
///
/// High volatility → premium symbols very rare (1-2 stops),
/// low volatility → more even distribution.
fn compute_stop_counts(n: usize, vol_idx: f64) -> Vec<u8> {
    const STRIP_LEN: usize = 50;
    // Reserve 8 stops for blanks/scatter/wild (non-paying positions).
    let total_paying_stops = STRIP_LEN - 8;

    // Zipf exponent: vol=1 → s=0.5 (gentle); vol=10 → s=2.2 (steep).
    let s = 0.4 + (vol_idx - 1.0) / 9.0 * 1.8;

    // Raw Zipf weights: raw[0] = rank-1 (most common), raw[n-1] = rank-n (rarest).
    // We iterate in reverse so that after scaling, index 0 = premium (fewest stops)
    // and index n-1 = low symbol (most stops). This matches pays_table ordering
    // where i=0 is the highest-paying premium tier.
    let raw: Vec<f64> = (1..=n).map(|i| 1.0 / (i as f64).powf(s)).collect();
    let raw_sum: f64 = raw.iter().sum();

    // Scale to total_paying_stops, ensuring each symbol has at least 1 stop.
    // After rev: index 0 maps to raw[n-1] (rank-n, rarest) → premium (fewest stops).
    let mut counts: Vec<usize> = raw
        .iter()
        .rev()
        .map(|&w| ((w / raw_sum * total_paying_stops as f64).round() as usize).max(1))
        .collect();

    // Adjust to hit exact total (±1 corrections from rounding).
    // index 0 = premium (fewest stops), index n-1 = low (most stops).
    // Add/remove from the most abundant symbol (last index).
    let actual: usize = counts.iter().sum();
    if actual != total_paying_stops {
        let diff = total_paying_stops as isize - actual as isize;
        let last = counts.len() - 1;
        if diff > 0 {
            counts[last] += diff as usize;
        } else {
            counts[last] = counts[last].saturating_sub((-diff) as usize).max(1);
        }
    }

    counts.iter().map(|&c| c.min(255) as u8).collect()
}

// ═══════════════════════════════════════════════════════════════════════════
// RTP calculation
// ═══════════════════════════════════════════════════════════════════════════

/// Compute total RTP and per-payline win frequency for a given paytable and
/// symbol probabilities.
///
/// `pays_scale` multiplies every pay value before computing (use 1.0 for
/// already-scaled tables, other values during binary search).
///
/// # RTP formula
/// For each symbol `sym` with probability `p` on each reel:
/// ```text
/// P(k-of-N consecutive from left) =
///     p^k × (1-p)   for k < N
///     p^N           for k = N
///
/// RTP = Σ_sym Σ_k [P(k-of-N, sym) × pay_sym[k] × pays_scale]
/// ```
/// The paylines factor cancels (bet = paylines × 1, return = paylines × E[payline])
/// so the formula is payline-independent.
fn compute_rtp(
    pays_table: &[Vec<f64>],
    probs: &[f64],
    reels: usize,
    pays_scale: f64,
) -> (f64, f64) {
    let mut total_rtp = 0.0_f64;
    let mut hit_freq_per_payline = 0.0_f64;

    for (sym_idx, sym_pays) in pays_table.iter().enumerate() {
        let p = probs[sym_idx];
        for k in 3..=reels {
            if k >= sym_pays.len() {
                break;
            }
            let pay = sym_pays[k] * pays_scale;
            if pay <= 0.0 {
                continue;
            }
            let p_win = if k == reels {
                p.powi(k as i32)
            } else {
                p.powi(k as i32) * (1.0 - p)
            };
            total_rtp += pay * p_win;
            hit_freq_per_payline += p_win;
        }
    }
    (total_rtp, hit_freq_per_payline)
}

// ═══════════════════════════════════════════════════════════════════════════
// Solver entry point
// ═══════════════════════════════════════════════════════════════════════════

/// Solve a paytable distribution for the given config.
///
/// Returns `Err` only if the config is completely degenerate (zero pays, etc.).
pub fn solve_paytable(config: &RtpSolverConfig) -> Result<RtpSolution, String> {
    let target_rtp = config.target_rtp.clamp(0.80, 0.999);
    let vol_idx = config.volatility_index.clamp(1, 10) as f64;
    let n_paying = config.paying_symbol_count.clamp(2, 12) as usize;
    let reels = config.reel_count.max(3) as usize;
    let paylines = if config.payline_count == 0 {
        (config.row_count as u16).saturating_pow(config.reel_count as u32)
    } else {
        config.payline_count
    } as f64;

    // ── Strip stop model ─────────────────────────────────────────────────────
    let stop_counts = compute_stop_counts(n_paying, vol_idx);
    let symbol_probs: Vec<f64> = stop_counts.iter().map(|&s| s as f64 / 50.0).collect();

    // ── Initial pay schedule ─────────────────────────────────────────────────
    // tier_ratio: how much more each higher tier pays (vol=1 → 2.0, vol=10 → 5.0)
    let tier_ratio = 2.0 + (vol_idx - 1.0) / 9.0 * 3.0;

    // Base top-symbol 5-of-5 pay = 500 (will be scaled by binary search).
    let base_top_pay = 500.0_f64;

    // Match-count ratios: 3-of-5 = 8%, 4-of-5 = 30%, 5-of-5 = 100% of top5.
    // These ratios are industry-standard for the pay shape.
    let match_ratios = [0.0, 0.0, 0.0, 0.08, 0.30, 1.0];

    let mut pays_table: Vec<Vec<f64>> = (0..n_paying)
        .map(|i| {
            let top5 = base_top_pay / tier_ratio.powi(i as i32);
            (0..=reels)
                .map(|k| {
                    if !(3..=5).contains(&k) {
                        0.0
                    } else {
                        (top5 * match_ratios[k]).max(1.0)
                    }
                })
                .collect()
        })
        .collect();

    // ── Binary search for scale factor ───────────────────────────────────────
    let (init_rtp, _) = compute_rtp(&pays_table, &symbol_probs, reels, 1.0);
    if init_rtp <= 0.0 {
        return Err("RTP solver: zero expected value — degenerate config".into());
    }

    // Initial estimate: scale = target / init.
    // Binary search between [lo, hi] until converged.
    let init_scale = target_rtp / init_rtp;
    let mut lo = 0.0_f64;
    let mut hi = init_scale * 10.0_f64;
    let mut scale = init_scale;
    let mut iterations = 0u32;

    loop {
        iterations += 1;
        if iterations > 200 {
            break;
        }

        let (achieved, _) = compute_rtp(&pays_table, &symbol_probs, reels, scale);
        let delta = achieved - target_rtp;

        if delta.abs() < 5e-5 {
            break;
        }

        if delta < 0.0 {
            lo = scale;
        } else {
            hi = scale;
        }
        scale = (lo + hi) / 2.0;
    }

    // ── Apply scale (float — no rounding here to preserve RTP accuracy) ────
    // Rounding is deferred to solution_to_math_config() for export.
    for row in &mut pays_table {
        for p in row.iter_mut() {
            *p *= scale;
        }
    }

    // Final RTP with float pays — matches target within binary-search tolerance.
    let (achieved_rtp, hit_freq_per_payline) =
        compute_rtp(&pays_table, &symbol_probs, reels, 1.0);

    // ── Estimate per-spin hit frequency ─────────────────────────────────────
    // P(at least one payline wins) ≈ 1 - (1 - p_per_payline)^paylines
    // Clamped to [0, 1].
    let hit_frequency = (1.0 - (1.0 - hit_freq_per_payline.min(0.999)).powf(paylines))
        .clamp(0.0, 1.0);

    // ── Build result symbols ─────────────────────────────────────────────────
    let tier_labels = ["Premium", "High", "Mid", "Low", "Low"];
    let mut result_id = 0u32;

    let mut symbols: Vec<SolvedSymbol> = pays_table
        .iter()
        .enumerate()
        .map(|(i, pays)| {
            let p = symbol_probs[i];
            let sc = stop_counts[i];

            let sym_rtp: f64 = (3..=reels)
                .filter(|&k| k < pays.len() && pays[k] > 0.0)
                .map(|k| {
                    let p_win = if k == reels {
                        p.powi(k as i32)
                    } else {
                        p.powi(k as i32) * (1.0 - p)
                    };
                    pays[k] * p_win
                })
                .sum();

            let sym_win_freq: f64 = (3..=reels)
                .filter(|&k| k < pays.len() && pays[k] > 0.0)
                .map(|k| {
                    if k == reels {
                        p.powi(k as i32)
                    } else {
                        p.powi(k as i32) * (1.0 - p)
                    }
                })
                .sum();

            let tier_label = tier_labels[(i * 5 / n_paying).min(4)];
            let within_tier = i - (i * 5 / n_paying) * n_paying / 5;
            let name = format!("{} {}", tier_label, within_tier + 1);

            let id = result_id;
            result_id += 1;

            SolvedSymbol {
                id,
                name,
                is_wild: false,
                is_scatter: false,
                pays: pays.clone(),
                reel_probability: p,
                stop_count: sc,
                rtp_contribution: sym_rtp,
                win_frequency: sym_win_freq,
            }
        })
        .collect();

    // ── Optional wild / scatter ──────────────────────────────────────────────
    if config.include_wild {
        let top_pays: Vec<f64> = symbols[0]
            .pays
            .iter()
            .map(|&p| (p * 1.05).round())
            .collect();
        let wild_stops = (stop_counts[0] / 2).max(1);
        symbols.push(SolvedSymbol {
            id: result_id,
            name: "Wild".into(),
            is_wild: true,
            is_scatter: false,
            pays: top_pays,
            reel_probability: wild_stops as f64 / 50.0,
            stop_count: wild_stops,
            rtp_contribution: 0.0, // Substitution value modeled separately
            win_frequency: 0.0,
        });
        result_id += 1;
    }

    if config.include_scatter {
        symbols.push(SolvedSymbol {
            id: result_id,
            name: "Scatter".into(),
            is_wild: false,
            is_scatter: true,
            pays: vec![0.0, 0.0, 0.0, 2.0, 5.0, 10.0],
            reel_probability: 3.0 / 50.0, // 3 stops
            stop_count: 3,
            rtp_contribution: 0.0,
            win_frequency: 0.0,
        });
    }

    Ok(RtpSolution {
        symbols,
        achieved_rtp,
        target_rtp,
        rtp_delta: achieved_rtp - target_rtp,
        hit_frequency,
        iterations,
    })
}

/// Convert a `RtpSolution` into a `MathConfig` ready for blueprint injection.
pub fn solution_to_math_config(
    solution: &RtpSolution,
    config: &RtpSolverConfig,
) -> crate::blueprint::MathConfig {
    use crate::blueprint::{MathConfig, ReelStrip, Symbol};
    use std::collections::HashMap;

    let symbols: Vec<Symbol> = solution
        .symbols
        .iter()
        .map(|s| Symbol {
            id: s.id,
            name: s.name.clone(),
            // Round pays to integers for export (solver stores exact floats).
            pays: s.pays.iter().map(|&p| p.round().max(0.0)).collect(),
            is_wild: s.is_wild,
            is_scatter: s.is_scatter,
            is_bonus: false,
            can_expand: s.is_wild,
            meta: serde_json::json!({
                "stop_count": s.stop_count,
                "reel_probability": s.reel_probability,
                "rtp_contribution": s.rtp_contribution,
                "solver_generated": true,
            }),
        })
        .collect();

    // Build reel strips from stop counts.
    // Each symbol gets stop_count entries in the strip. Remaining = blank (id 255).
    let paying: Vec<&SolvedSymbol> = solution
        .symbols
        .iter()
        .filter(|s| !s.is_wild && !s.is_scatter)
        .collect();

    let mut strip: Vec<u32> = Vec::with_capacity(50);
    for sym in &paying {
        for _ in 0..sym.stop_count {
            strip.push(sym.id);
        }
    }
    // Wild stops (if any wild symbol)
    for sym in solution.symbols.iter().filter(|s| s.is_wild) {
        for _ in 0..sym.stop_count {
            strip.push(sym.id);
        }
    }
    // Scatter stops
    for sym in solution.symbols.iter().filter(|s| s.is_scatter) {
        for _ in 0..sym.stop_count {
            strip.push(sym.id);
        }
    }
    // Fill blanks
    while strip.len() < 50 {
        strip.push(255); // blank
    }
    strip.truncate(50);

    let reels_vec: Vec<ReelStrip> = (0..config.reel_count)
        .map(|i| ReelStrip {
            index: i,
            symbols: strip.clone(),
            weights: None,
            variant: None,
        })
        .collect();

    let mut reel_strips = HashMap::new();
    reel_strips.insert("base".into(), reels_vec);

    MathConfig {
        rtp_target: solution.achieved_rtp,
        volatility: config.volatility_index.clamp(1, 10),
        hit_frequency: solution.hit_frequency,
        reel_count: config.reel_count,
        row_count: config.row_count,
        payline_count: config.payline_count,
        reel_strips,
        symbols,
        max_payout: 5000.0,
        free_spins_count: 10,
        free_spins_multiplier: 1.0,
        buy_feature_cost: Some(100.0),
        jackpots: HashMap::new(),
        custom: HashMap::new(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_rtp(result: &RtpSolution, target: f64, tolerance: f64) {
        assert!(
            (result.achieved_rtp - target).abs() < tolerance,
            "achieved RTP {:.4} not within {tolerance} of target {:.4}",
            result.achieved_rtp,
            target,
        );
    }

    #[test]
    fn test_default_config_solves() {
        let config = RtpSolverConfig::default();
        let result = solve_paytable(&config).expect("solve should succeed");
        assert_rtp(&result, config.target_rtp, 0.01);
        assert!(result.symbols.len() >= 6);
        assert!(result.hit_frequency > 0.0);
        assert!(result.hit_frequency <= 1.0);
    }

    #[test]
    fn test_low_volatility() {
        let config = RtpSolverConfig {
            target_rtp: 0.970,
            volatility_index: 2,
            ..Default::default()
        };
        let result = solve_paytable(&config).expect("low vol solve");
        assert_rtp(&result, 0.970, 0.015);
        // Low vol → higher hit frequency than high vol
        assert!(result.hit_frequency > 0.10, "low vol hit freq = {}", result.hit_frequency);
    }

    #[test]
    fn test_high_volatility() {
        let config = RtpSolverConfig {
            target_rtp: 0.960,
            volatility_index: 9,
            ..Default::default()
        };
        let result = solve_paytable(&config).expect("high vol solve");
        assert_rtp(&result, 0.960, 0.015);
    }

    #[test]
    fn test_rtp_clamping() {
        // Below minimum RTP (0.75 → clamped to 0.80)
        let config = RtpSolverConfig {
            target_rtp: 0.75,
            ..Default::default()
        };
        let result = solve_paytable(&config).expect("clamped rtp solve");
        // Should achieve close to 0.80 (the clamped value)
        assert_rtp(&result, 0.80, 0.015);

        // Near-max RTP
        let config_high = RtpSolverConfig {
            target_rtp: 0.990,
            ..Default::default()
        };
        let result_high = solve_paytable(&config_high).expect("high rtp solve");
        assert_rtp(&result_high, 0.990, 0.015);
    }

    #[test]
    fn test_solution_to_math_config() {
        let config = RtpSolverConfig::default();
        let solution = solve_paytable(&config).expect("solve");
        let math = solution_to_math_config(&solution, &config);
        assert_eq!(math.reel_count, config.reel_count);
        assert_eq!(math.row_count, config.row_count);
        assert!(!math.symbols.is_empty());
        assert!(math.reel_strips.contains_key("base"));
        assert_eq!(math.reel_strips["base"].len(), config.reel_count as usize);
        // Each strip should be 50 stops
        assert_eq!(math.reel_strips["base"][0].symbols.len(), 50);
    }

    #[test]
    fn test_many_paying_symbols() {
        let config = RtpSolverConfig {
            target_rtp: 0.965,
            paying_symbol_count: 10,
            volatility_index: 5,
            ..Default::default()
        };
        let result = solve_paytable(&config).expect("many symbol solve");
        assert_rtp(&result, 0.965, 0.02);
    }

    #[test]
    fn test_solver_convergence() {
        let config = RtpSolverConfig::default();
        let result = solve_paytable(&config).expect("solve");
        assert!(
            result.iterations < 150,
            "solver took {} iterations",
            result.iterations
        );
    }

    #[test]
    fn test_symbol_pay_structure() {
        let config = RtpSolverConfig::default();
        let result = solve_paytable(&config).expect("solve");
        // Premium symbol should pay more than low symbol
        let paying: Vec<_> = result.symbols.iter().filter(|s| !s.is_wild && !s.is_scatter).collect();
        if paying.len() >= 2 {
            let premium_5of5 = paying[0].pays.last().copied().unwrap_or(0.0);
            let low_5of5 = paying[paying.len() - 1].pays.last().copied().unwrap_or(0.0);
            assert!(
                premium_5of5 >= low_5of5,
                "premium 5-of-5 ({premium_5of5}) should be >= low ({low_5of5})"
            );
        }
    }

    #[test]
    fn test_stop_counts_realistic() {
        // Stop counts should be reasonable (1–30 per symbol)
        let config = RtpSolverConfig::default();
        let stops = compute_stop_counts(config.paying_symbol_count as usize,
                                        config.volatility_index as f64);
        let total: usize = stops.iter().map(|&s| s as usize).sum();
        assert!(total <= 42, "total stops {total} should leave room for blanks");
        assert!(stops[0] < stops[stops.len()-1],
                "premium should have fewer stops than low symbol");
    }

    #[test]
    fn test_wild_and_scatter() {
        let config = RtpSolverConfig {
            include_wild: true,
            include_scatter: true,
            ..Default::default()
        };
        let result = solve_paytable(&config).expect("solve with extras");
        assert!(result.symbols.iter().any(|s| s.is_wild));
        assert!(result.symbols.iter().any(|s| s.is_scatter));
    }
}

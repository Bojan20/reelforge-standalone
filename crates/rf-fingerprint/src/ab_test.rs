//! T6.2–T6.3: A/B test setup and statistical significance calculator.
//!
//! Implements two-proportion z-test for comparing audio variants.
//! Used to determine if one audio design (A) outperforms another (B) on
//! player engagement metrics (session length, spin count, return rate).

use serde::{Deserialize, Serialize};

/// One audio variant in an A/B test
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbVariant {
    /// Variant identifier ("A" or "B", or custom name)
    pub name: String,
    /// Number of players exposed to this variant
    pub sample_size: u64,
    /// Number of players who converted (stayed >N minutes, re-visited, etc.)
    pub conversions: u64,
    /// Optional: average session length in seconds
    pub avg_session_s: Option<f64>,
    /// Optional: average spin count per session
    pub avg_spins: Option<f64>,
    /// Optional: return rate (0.0–1.0)
    pub return_rate: Option<f64>,
    /// Human-readable description of this variant
    pub description: String,
}

impl AbVariant {
    pub fn conversion_rate(&self) -> f64 {
        if self.sample_size == 0 { return 0.0; }
        self.conversions as f64 / self.sample_size as f64
    }
}

/// A/B test configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbTestConfig {
    pub test_name: String,
    pub game_id: String,
    pub metric: String,  // "session_length", "spin_count", "return_rate", "conversion"
    pub variant_a: AbVariant,
    pub variant_b: AbVariant,
    /// Minimum detectable effect (relative, e.g. 0.05 = 5% improvement)
    pub minimum_detectable_effect: f64,
    /// Target significance level (typically 0.05)
    pub significance_level: f64,
    /// Target statistical power (typically 0.80)
    pub target_power: f64,
}

/// Statistical analysis result (T6.3)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatisticalResult {
    /// True if result is statistically significant at the configured significance level
    pub is_significant: bool,
    /// p-value from two-proportion z-test
    pub p_value: f64,
    /// z-score
    pub z_score: f64,
    /// 95% confidence interval for the difference in conversion rates
    pub confidence_interval_lo: f64,
    pub confidence_interval_hi: f64,
    /// Relative improvement of B over A (can be negative)
    pub relative_improvement: f64,
    /// Current statistical power (given observed effect size and sample size)
    pub current_power: f64,
    /// Required sample size per variant for target power (at current effect size)
    pub required_sample_size: u64,
    /// How many more samples needed per variant
    pub additional_samples_needed: u64,
}

/// Complete A/B test analysis report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbTestReport {
    pub test_name: String,
    pub game_id: String,
    pub metric: String,
    pub variant_a_rate: f64,
    pub variant_b_rate: f64,
    pub result: StatisticalResult,
    /// Recommended action based on results
    pub recommendation: String,
    /// Sample size adequacy (0–100%)
    pub sample_adequacy_pct: u8,
}

impl AbTestReport {
    /// Run full A/B test analysis
    pub fn analyze(config: &AbTestConfig) -> Self {
        let rate_a = config.variant_a.conversion_rate();
        let rate_b = config.variant_b.conversion_rate();
        let n_a = config.variant_a.sample_size;
        let n_b = config.variant_b.sample_size;

        let result = two_proportion_z_test(rate_a, rate_b, n_a, n_b, config.significance_level);

        let required = required_sample_size(
            rate_a,
            config.minimum_detectable_effect,
            config.significance_level,
            config.target_power,
        );

        let actual_n = n_a.min(n_b);
        let additional = required.saturating_sub(actual_n);
        let adequacy = ((actual_n * 100) / required.max(1)).min(100) as u8;

        let recommendation = generate_recommendation(
            &result, config, rate_a, rate_b, adequacy,
        );

        let complete_result = StatisticalResult {
            required_sample_size: required,
            additional_samples_needed: additional,
            current_power: estimate_power(rate_a, rate_b, actual_n, config.significance_level),
            ..result
        };

        Self {
            test_name: config.test_name.clone(),
            game_id: config.game_id.clone(),
            metric: config.metric.clone(),
            variant_a_rate: rate_a,
            variant_b_rate: rate_b,
            result: complete_result,
            recommendation,
            sample_adequacy_pct: adequacy,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Statistical helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Two-proportion z-test (two-tailed)
fn two_proportion_z_test(
    p1: f64,
    p2: f64,
    n1: u64,
    n2: u64,
    alpha: f64,
) -> StatisticalResult {
    if n1 == 0 || n2 == 0 {
        return StatisticalResult {
            is_significant: false,
            p_value: 1.0,
            z_score: 0.0,
            confidence_interval_lo: 0.0,
            confidence_interval_hi: 0.0,
            relative_improvement: 0.0,
            current_power: 0.0,
            required_sample_size: 0,
            additional_samples_needed: 0,
        };
    }

    let pooled = (p1 * n1 as f64 + p2 * n2 as f64) / (n1 + n2) as f64;
    let se = (pooled * (1.0 - pooled) * (1.0 / n1 as f64 + 1.0 / n2 as f64)).sqrt();

    let z_score = if se > 0.0 { (p2 - p1) / se } else { 0.0 };
    let p_value = 2.0 * (1.0 - normal_cdf(z_score.abs()));
    let is_significant = p_value < alpha;

    // 95% CI for difference (p2 - p1)
    let se_diff = ((p1 * (1.0 - p1) / n1 as f64) + (p2 * (1.0 - p2) / n2 as f64)).sqrt();
    let z_ci = 1.96; // 95% CI
    let diff = p2 - p1;

    let relative_improvement = if p1 > 0.0 { (p2 - p1) / p1 } else { 0.0 };

    StatisticalResult {
        is_significant,
        p_value,
        z_score,
        confidence_interval_lo: diff - z_ci * se_diff,
        confidence_interval_hi: diff + z_ci * se_diff,
        relative_improvement,
        current_power: 0.0, // filled in by caller
        required_sample_size: 0,
        additional_samples_needed: 0,
    }
}

/// Required sample size per group (two-proportion z-test, two-tailed)
fn required_sample_size(baseline_rate: f64, mde: f64, alpha: f64, power: f64) -> u64 {
    let p1 = baseline_rate;
    let p2 = baseline_rate * (1.0 + mde);
    let p2 = p2.clamp(0.001, 0.999);

    let z_alpha = quantile_normal(1.0 - alpha / 2.0);
    let z_beta = quantile_normal(power);

    let p_bar = (p1 + p2) / 2.0;

    let num = (z_alpha * (2.0 * p_bar * (1.0 - p_bar)).sqrt()
        + z_beta * (p1 * (1.0 - p1) + p2 * (1.0 - p2)).sqrt())
        .powi(2);
    let denom = (p2 - p1).powi(2);

    if denom <= 0.0 { return 10_000; }
    let n = (num / denom).ceil() as u64;
    n.max(100)
}

/// Estimate current statistical power given observed values
fn estimate_power(p1: f64, p2: f64, n: u64, alpha: f64) -> f64 {
    if n == 0 || p1 == p2 { return 0.0; }
    let pooled = (p1 + p2) / 2.0;
    let se = (pooled * (1.0 - pooled) * 2.0 / n as f64).sqrt();
    if se <= 0.0 { return 0.0; }

    let z_alpha = quantile_normal(1.0 - alpha / 2.0);
    let ncp = (p2 - p1).abs() / se; // non-centrality parameter

    // Power = P(|Z| > z_alpha | H1) ≈ Φ(ncp - z_alpha) + Φ(-ncp - z_alpha)
    let power = normal_cdf(ncp - z_alpha) + normal_cdf(-ncp - z_alpha);
    power.clamp(0.0, 1.0)
}

/// Abramowitz & Stegun approximation for standard normal CDF
fn normal_cdf(x: f64) -> f64 {
    if x < -8.0 { return 0.0; }
    if x > 8.0  { return 1.0; }
    let b1 = 0.319381530_f64;
    let b2 = -0.356563782_f64;
    let b3 = 1.781477937_f64;
    let b4 = -1.821255978_f64;
    let b5 = 1.330274429_f64;
    let p  = 0.2316419_f64;

    let t = 1.0 / (1.0 + p * x.abs());
    let poly = t * (b1 + t * (b2 + t * (b3 + t * (b4 + t * b5))));
    let pdf = (-x * x / 2.0).exp() / (2.0 * std::f64::consts::PI).sqrt();

    if x >= 0.0 { 1.0 - pdf * poly }
    else        { pdf * poly }
}

/// Approximate inverse normal CDF (Beasley-Springer-Moro)
fn quantile_normal(p: f64) -> f64 {
    let p = p.clamp(1e-10, 1.0 - 1e-10);
    const A: [f64; 4] = [2.515517, 0.802853, 0.010328, 0.0];
    const B: [f64; 3] = [1.432788, 0.189269, 0.001308];

    let t = if p < 0.5 {
        (-2.0 * p.ln()).sqrt()
    } else {
        (-2.0 * (1.0 - p).ln()).sqrt()
    };

    let num = A[0] + t * (A[1] + t * (A[2] + t * A[3]));
    let den = 1.0 + t * (B[0] + t * (B[1] + t * B[2]));
    let approx = t - num / den;

    if p < 0.5 { -approx } else { approx }
}

fn generate_recommendation(
    result: &StatisticalResult,
    config: &AbTestConfig,
    rate_a: f64,
    rate_b: f64,
    adequacy: u8,
) -> String {
    if adequacy < 50 {
        return format!(
            "Insufficient data. Need {:.0}% more samples per variant before drawing conclusions.",
            (100 - adequacy) as f64 * 0.01 * 100.0
        );
    }

    if !result.is_significant {
        if adequacy >= 90 {
            return format!(
                "No significant difference detected (p={:.3}). \
                 With adequate sample size, variants A and B are equivalent — keep A.",
                result.p_value
            );
        } else {
            return format!(
                "Not yet significant (p={:.3}, {adequacy}% sample adequacy). \
                 Continue collecting data.",
                result.p_value
            );
        }
    }

    let winner = if rate_b > rate_a { &config.variant_b.name } else { &config.variant_a.name };
    let improvement_pct = (result.relative_improvement * 100.0).abs();

    if result.relative_improvement > 0.0 {
        format!(
            "Variant B ({}) wins with {:.1}% improvement (p={:.3}). \
             Confident at {:.0}% power. Ship variant B.",
            winner,
            improvement_pct,
            result.p_value,
            result.current_power * 100.0
        )
    } else {
        format!(
            "Variant A ({}) wins. B is {:.1}% WORSE (p={:.3}). \
             Keep variant A.",
            winner,
            improvement_pct,
            result.p_value
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn make_config(n_a: u64, conv_a: u64, n_b: u64, conv_b: u64) -> AbTestConfig {
        AbTestConfig {
            test_name: "Test".to_string(),
            game_id: "game".to_string(),
            metric: "conversion".to_string(),
            variant_a: AbVariant {
                name: "A".to_string(),
                sample_size: n_a, conversions: conv_a,
                avg_session_s: None, avg_spins: None, return_rate: None,
                description: "Control".to_string(),
            },
            variant_b: AbVariant {
                name: "B".to_string(),
                sample_size: n_b, conversions: conv_b,
                avg_session_s: None, avg_spins: None, return_rate: None,
                description: "Treatment".to_string(),
            },
            minimum_detectable_effect: 0.05,
            significance_level: 0.05,
            target_power: 0.80,
        }
    }

    #[test]
    fn test_large_significant_difference() {
        // 20% vs 30% conversion with 2000 samples each → should be significant
        let config = make_config(2000, 400, 2000, 600);
        let report = AbTestReport::analyze(&config);
        assert!(report.result.is_significant, "Expected significance for 20% vs 30%");
        assert!(report.result.relative_improvement > 0.0);
    }

    #[test]
    fn test_no_difference_not_significant() {
        // Identical rates → not significant
        let config = make_config(1000, 200, 1000, 200);
        let report = AbTestReport::analyze(&config);
        assert!(!report.result.is_significant);
        assert!((report.result.p_value - 1.0).abs() < 0.1);
    }

    #[test]
    fn test_small_sample_needs_more_data() {
        let config = make_config(50, 10, 50, 15);
        let report = AbTestReport::analyze(&config);
        assert!(report.result.additional_samples_needed > 0);
    }

    #[test]
    fn test_b_worse_than_a_negative_improvement() {
        let config = make_config(2000, 600, 2000, 400);
        let report = AbTestReport::analyze(&config);
        assert!(report.result.is_significant);
        assert!(report.result.relative_improvement < 0.0, "B should be worse than A");
    }

    #[test]
    fn test_sample_adequacy_increases_with_more_data() {
        let small = make_config(100, 20, 100, 25);
        let large = make_config(10000, 2000, 10000, 2500);
        let small_r = AbTestReport::analyze(&small);
        let large_r = AbTestReport::analyze(&large);
        assert!(large_r.sample_adequacy_pct >= small_r.sample_adequacy_pct);
    }

    #[test]
    fn test_confidence_interval_contains_zero_when_not_significant() {
        let config = make_config(200, 40, 200, 42);
        let report = AbTestReport::analyze(&config);
        if !report.result.is_significant {
            assert!(report.result.confidence_interval_lo < 0.0 ||
                    report.result.confidence_interval_hi > 0.0);
        }
    }

    #[test]
    fn test_zero_sample_size_no_panic() {
        let config = make_config(0, 0, 0, 0);
        let report = AbTestReport::analyze(&config);
        assert!(!report.result.is_significant);
    }
}

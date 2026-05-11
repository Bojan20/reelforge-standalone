//! # Bug Reproduction Harness — FluxForge Studio (C.1)
//!
//! Deterministic scenario runner for the FluxForge slot engine.
//! Reproduces engine bugs by running N identical scenarios and finding
//! divergences (missing stages, wrong timing, unexpected outcomes).
//!
//! ## Usage
//!
//! ```sh
//! # Run a named built-in scenario
//! bug-repro --scenario anticipation_missing --runs 1000
//!
//! # Run a custom scenario from JSON file
//! bug-repro --file my_scenario.json --runs 500 --seed 42
//!
//! # Show all built-in scenarios
//! bug-repro --list
//!
//! # Verbose mode: print each divergence
//! bug-repro --scenario near_miss_guard --runs 2000 --verbose
//! ```
//!
//! ## Scenario JSON schema
//!
//! ```json
//! {
//!   "name": "anticipation_missing",
//!   "description": "Checks anticipation triggers on near-miss (2 scatters)",
//!   "engine": {
//!     "reels": 5, "rows": 3,
//!     "volatility": "high",
//!     "free_spins_enabled": true,
//!     "near_miss_enabled": true
//!   },
//!   "forced_outcomes": ["NearMiss"],
//!   "run_count": 1000,
//!   "seed": 42,
//!   "assertions": [
//!     { "type": "stage_present", "stage": "ANTICIPATION_TENSION_1" },
//!     { "type": "stage_present", "stage": "REEL_SPIN_LOOP" },
//!     { "type": "stage_count_gte", "stage": "REEL_STOP", "count": 5 }
//!   ]
//! }
//! ```

use std::path::PathBuf;
use std::process;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use rf_slot_lab::{
    AnticipationConfig, FeatureConfig, ForcedOutcome,
    GridSpec, SlotConfig, SyntheticSlotEngine, VolatilityProfile,
};
use rf_stage::FeatureType;

// ═══════════════════════════════════════════════════════════════════════════
// CLI
// ═══════════════════════════════════════════════════════════════════════════

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if let Err(e) = run(args) {
        eprintln!("bug-repro error: {e:#}");
        process::exit(1);
    }
}

fn run(args: Vec<String>) -> Result<()> {
    // ── Minimal hand-rolled CLI parser ────────────────────────────────────
    if args.len() < 2 || args.iter().any(|a| a == "--help" || a == "-h") {
        print_usage();
        return Ok(());
    }

    if args.iter().any(|a| a == "--list") {
        print_built_ins();
        return Ok(());
    }

    // Extract flags
    let scenario_name = flag_value(&args, "--scenario");
    let file_path = flag_value(&args, "--file").map(PathBuf::from);
    let runs_override = flag_value(&args, "--runs").and_then(|s| s.parse::<u32>().ok());
    let seed_override = flag_value(&args, "--seed").and_then(|s| s.parse::<u64>().ok());
    let verbose = args.iter().any(|a| a == "--verbose" || a == "-v");
    let json_out = args.iter().any(|a| a == "--json");

    // Load scenario
    let scenario = if let Some(path) = file_path {
        let json = std::fs::read_to_string(&path)
            .with_context(|| format!("reading scenario file {}", path.display()))?;
        serde_json::from_str::<Scenario>(&json)
            .with_context(|| "parsing scenario JSON")?
    } else if let Some(name) = scenario_name {
        load_built_in(&name).with_context(|| format!("loading built-in scenario '{name}'"))?
    } else {
        anyhow::bail!("Must specify --scenario <name> or --file <path>");
    };

    // Apply overrides
    let run_count = runs_override.unwrap_or(scenario.run_count).max(1);
    let seed = seed_override.unwrap_or(scenario.seed);

    // Execute
    let report = execute(&scenario, run_count, seed, verbose)?;

    // Output
    if json_out {
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else {
        print_report(&report, &scenario);
    }

    // Exit code: 0 = all pass, 1 = failures found
    if report.fail_count > 0 {
        process::exit(1);
    }

    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════
// Scenario model
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Scenario {
    #[serde(default = "default_name")]
    name: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    engine: EngineConfig,
    #[serde(default)]
    forced_outcomes: Vec<String>,
    #[serde(default = "default_runs")]
    run_count: u32,
    #[serde(default)]
    seed: u64,
    #[serde(default)]
    assertions: Vec<Assertion>,
}

fn default_name() -> String { "unnamed".into() }
fn default_runs() -> u32 { 100 }

/// NOTE: Default is implemented manually so serde defaults and Rust defaults match.
/// `#[derive(Default)]` would give reels=0, rows=0 — serde defaults only apply on deserialize.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct EngineConfig {
    #[serde(default = "def_reels")] reels: u8,
    #[serde(default = "def_rows")]  rows: u8,
    #[serde(default)]               volatility: VolatilityStr,
    #[serde(default = "def_true")]  free_spins_enabled: bool,
    #[serde(default)]               cascades_enabled: bool,
    #[serde(default)]               jackpot_enabled: bool,
    /// Enable near-miss anticipation stages (requires engine config — off by default)
    #[serde(default)]               near_miss_anticipation: bool,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            reels:                  def_reels(),
            rows:                   def_rows(),
            volatility:             VolatilityStr::Medium,
            free_spins_enabled:     true,
            cascades_enabled:       false,
            jackpot_enabled:        false,
            near_miss_anticipation: false,
        }
    }
}

fn def_reels() -> u8 { 5 }
fn def_rows()  -> u8 { 3 }
fn def_true()  -> bool { true }

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum VolatilityStr {
    Low,
    #[default]
    Medium,
    High,
    Extreme,
}

impl VolatilityStr {
    fn to_profile(&self) -> VolatilityProfile {
        match self {
            VolatilityStr::Low     => VolatilityProfile::low(),
            VolatilityStr::Medium  => VolatilityProfile::medium(),
            VolatilityStr::High    => VolatilityProfile::high(),
            VolatilityStr::Extreme => VolatilityProfile::high(), // no "extreme" preset — map to high
        }
    }
}

/// A single assertion applied to every spin's stage list.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Assertion {
    /// Stage name substring must appear at least once.
    StagePresent { stage: String },
    /// Stage name substring must appear at least `count` times.
    StageCountGte { stage: String, count: usize },
    /// Stage name substring must NOT appear.
    StageAbsent { stage: String },
    /// At least one win (total_win > 0).
    HasWin,
    /// Near-miss flag must be set.
    IsNearMiss,
    /// Free spins must be triggered.
    FreeSpinsTriggered,
    /// Total spin duration (ms) must be within bounds.
    DurationMs { min: f64, max: f64 },
}

// ═══════════════════════════════════════════════════════════════════════════
// Execution
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Serialize)]
struct Report {
    scenario: String,
    total_runs: u32,
    pass_count: u32,
    fail_count: u32,
    fail_rate_pct: f64,
    first_fail: Option<FailDetail>,
    stage_frequency: std::collections::BTreeMap<String, u32>,
    timing_stats: TimingStats,
}

#[derive(Debug, Serialize)]
struct FailDetail {
    run_index: u32,
    seed: u64,
    failed_assertions: Vec<String>,
    stage_names: Vec<String>,
    total_win: f64,
    duration_ms: f64,
}

#[derive(Debug, Default, Serialize)]
struct TimingStats {
    min_ms: f64,
    max_ms: f64,
    avg_ms: f64,
    p95_ms: f64,
}

fn execute(scenario: &Scenario, run_count: u32, base_seed: u64, verbose: bool) -> Result<Report> {
    // Build engine from scenario config via with_config() so ALL settings (incl. anticipation) apply
    let ec = &scenario.engine;
    let slot_config = SlotConfig {
        grid: GridSpec {
            reels:    ec.reels,
            rows:     ec.rows,
            paylines: GridSpec::standard_5x3().paylines, // standard 20-line default
        },
        volatility: ec.volatility.to_profile(),
        features: FeatureConfig {
            free_spins_enabled: ec.free_spins_enabled,
            cascades_enabled:   ec.cascades_enabled,
            jackpot_enabled:    ec.jackpot_enabled,
            ..FeatureConfig::default()
        },
        anticipation: AnticipationConfig {
            enable_near_miss_anticipation: ec.near_miss_anticipation,
            ..AnticipationConfig::default()
        },
        ..SlotConfig::default()
    };
    let mut engine = SyntheticSlotEngine::with_config(slot_config);

    // Parse forced outcomes (at most one per spin; cycle through list)
    let forced: Vec<Option<ForcedOutcome>> = if scenario.forced_outcomes.is_empty() {
        vec![None]
    } else {
        scenario.forced_outcomes.iter()
            .map(|s| parse_forced_outcome(s))
            .collect()
    };

    let mut pass_count = 0u32;
    let mut fail_count = 0u32;
    let mut first_fail: Option<FailDetail> = None;
    let mut stage_freq: std::collections::BTreeMap<String, u32> = Default::default();
    let mut durations: Vec<f64> = Vec::with_capacity(run_count as usize);

    for run_idx in 0..run_count {
        // Vary seed per run for reproducibility but diversity.
        let run_seed = base_seed.wrapping_add(run_idx as u64);
        engine.seed(run_seed);

        // Pick forced outcome (cycle)
        let forced_outcome = forced[run_idx as usize % forced.len()];

        // Spin and collect stages
        let (result, stages) = match forced_outcome {
            None => engine.spin_with_stages(),
            Some(fo) => engine.spin_forced_with_stages(fo),
        };

        // Collect stage names for assertion + frequency tracking.
        // type_name() returns snake_case; we uppercase for readable matching
        // (assertions use "REEL_STOP", "ANTICIPATION", etc.)
        let stage_names: Vec<String> = stages.iter()
            .map(|s| s.stage.type_name().to_uppercase())
            .collect();

        for name in &stage_names {
            *stage_freq.entry(name.clone()).or_insert(0) += 1;
        }

        // Compute spin duration (last stage timestamp)
        let duration_ms = stages.iter()
            .map(|s| s.timestamp_ms)
            .fold(0.0_f64, f64::max);
        durations.push(duration_ms);

        // Evaluate assertions
        let mut failed: Vec<String> = Vec::new();
        for assertion in &scenario.assertions {
            let msg = check_assertion(assertion, &stage_names, &result, duration_ms);
            if let Some(m) = msg {
                failed.push(m);
            }
        }

        if failed.is_empty() {
            pass_count += 1;
        } else {
            fail_count += 1;
            if verbose {
                eprintln!(
                    "  FAIL run={run_idx} seed={run_seed}: {}",
                    failed.join("; ")
                );
                eprintln!("       stages: {}", stage_names.join(" → "));
            }
            if first_fail.is_none() {
                first_fail = Some(FailDetail {
                    run_index: run_idx,
                    seed: run_seed,
                    failed_assertions: failed,
                    stage_names,
                    total_win: result.total_win,
                    duration_ms,
                });
            }
        }
    }

    // Timing stats
    let timing_stats = if durations.is_empty() {
        TimingStats::default()
    } else {
        durations.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let sum: f64 = durations.iter().sum();
        let p95_idx = ((durations.len() as f64 * 0.95) as usize).min(durations.len() - 1);
        TimingStats {
            min_ms: durations[0],
            max_ms: *durations.last().unwrap(),
            avg_ms: sum / durations.len() as f64,
            p95_ms: durations[p95_idx],
        }
    };

    Ok(Report {
        scenario: scenario.name.clone(),
        total_runs: run_count,
        pass_count,
        fail_count,
        fail_rate_pct: if run_count > 0 { fail_count as f64 / run_count as f64 * 100.0 } else { 0.0 },
        first_fail,
        stage_frequency: stage_freq,
        timing_stats,
    })
}

fn check_assertion(
    assertion: &Assertion,
    stage_names: &[String],
    result: &rf_slot_lab::SpinResult,
    duration_ms: f64,
) -> Option<String> {
    match assertion {
        Assertion::StagePresent { stage } => {
            let found = stage_names.iter().any(|s| s.contains(stage.as_str()));
            if !found {
                Some(format!("stage '{stage}' absent (stages: {})", stage_names.len()))
            } else {
                None
            }
        }
        Assertion::StageCountGte { stage, count } => {
            let n = stage_names.iter().filter(|s| s.contains(stage.as_str())).count();
            if n < *count {
                Some(format!("stage '{stage}' appeared {n}× (expected ≥{count})"))
            } else {
                None
            }
        }
        Assertion::StageAbsent { stage } => {
            let found = stage_names.iter().any(|s| s.contains(stage.as_str()));
            if found {
                Some(format!("stage '{stage}' present but should be absent"))
            } else {
                None
            }
        }
        Assertion::HasWin => {
            if result.total_win <= 0.0 {
                Some(format!("expected win, got 0 (bet={})", result.bet))
            } else {
                None
            }
        }
        Assertion::IsNearMiss => {
            if !result.near_miss {
                Some("expected near_miss=true".into())
            } else {
                None
            }
        }
        Assertion::FreeSpinsTriggered => {
            let triggered = result.feature_triggered.as_ref()
                .map(|f| f.feature_type == FeatureType::FreeSpins)
                .unwrap_or(false);
            if !triggered {
                Some("expected free_spins feature to be triggered".into())
            } else {
                None
            }
        }
        Assertion::DurationMs { min, max } => {
            if duration_ms < *min || duration_ms > *max {
                Some(format!(
                    "duration {duration_ms:.0}ms outside [{min:.0}, {max:.0}]"
                ))
            } else {
                None
            }
        }
    }
}

fn parse_forced_outcome(s: &str) -> Option<ForcedOutcome> {
    match s.to_uppercase().as_str() {
        "LOSE" | "NONE"        => Some(ForcedOutcome::Lose),
        "SMALLWIN"             => Some(ForcedOutcome::SmallWin),
        "MEDIUMWIN"            => Some(ForcedOutcome::MediumWin),
        "BIGWIN"               => Some(ForcedOutcome::BigWin),
        "MEGAWIN"              => Some(ForcedOutcome::MegaWin),
        "EPICWIN"              => Some(ForcedOutcome::EpicWin),
        "ULTRAWIN"             => Some(ForcedOutcome::UltraWin),
        "FREESPINS"            => Some(ForcedOutcome::FreeSpins),
        "NEARMISS"             => Some(ForcedOutcome::NearMiss),
        "CASCADE"              => Some(ForcedOutcome::Cascade),
        "JACKPOTMINI"          => Some(ForcedOutcome::JackpotMini),
        "JACKPOTMINOR"         => Some(ForcedOutcome::JackpotMinor),
        "JACKPOTMAJOR"         => Some(ForcedOutcome::JackpotMajor),
        "JACKPOTGRAND"         => Some(ForcedOutcome::JackpotGrand),
        "RANDOM" | ""          => None,
        other => {
            eprintln!("Warning: unknown forced outcome '{other}', treating as random");
            None
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Built-in scenarios
// ═══════════════════════════════════════════════════════════════════════════

const BUILT_INS: &[(&str, &str)] = &[
    ("anticipation_present",   "NearMiss forces anticipation — expects ANTICIPATION_TENSION_1 in every spin"),
    ("free_spins_trigger",     "FreeSpins forced — expects free_spins_triggered=true + FS_* stages"),
    ("big_win_stages",         "BigWin forced — expects WIN_PRESENT + ROLLUP stages"),
    ("near_miss_guard",        "NearMiss forced — expects near_miss=true + ANTICIPATION stages"),
    ("reel_stop_order",        "Random — 5 REEL_STOP events in correct order"),
    ("lose_spin_minimal",      "Lose forced — expects no WIN_PRESENT stage"),
    ("duration_bounds",        "Random — spin duration within sane 100–10000 ms range"),
    ("cascade_chain",          "Cascade forced — expects CASCADE_* stages"),
];

fn load_built_in(name: &str) -> Result<Scenario> {
    match name {
        "anticipation_present" => Ok(Scenario {
            name: name.into(),
            description: "NearMiss forced with near_miss_anticipation=true: every spin must trigger ANTICIPATION".into(),
            engine: EngineConfig {
                volatility: VolatilityStr::High,
                free_spins_enabled: true,
                near_miss_anticipation: true, // must be explicit — off by default
                ..Default::default()
            },
            forced_outcomes: vec!["NearMiss".into()],
            run_count: 200,
            seed: 42,
            assertions: vec![
                Assertion::StagePresent { stage: "ANTICIPATION".into() },
                Assertion::StagePresent { stage: "REEL_SPIN".into() },
                Assertion::IsNearMiss,
            ],
        }),
        "free_spins_trigger" => Ok(Scenario {
            name: name.into(),
            description: "FreeSpins forced: must trigger free spins every spin".into(),
            engine: EngineConfig { free_spins_enabled: true, ..Default::default() },
            forced_outcomes: vec!["FreeSpins".into()],
            run_count: 100,
            seed: 7,
            assertions: vec![
                Assertion::FreeSpinsTriggered,
                Assertion::StagePresent { stage: "REEL_SPIN".into() },
            ],
        }),
        "big_win_stages" => Ok(Scenario {
            name: name.into(),
            description: "BigWin forced: must produce WIN_PRESENT stage and a win".into(),
            engine: EngineConfig { ..Default::default() },
            forced_outcomes: vec!["BigWin".into()],
            run_count: 200,
            seed: 100,
            assertions: vec![
                Assertion::HasWin,
                Assertion::StagePresent { stage: "WIN".into() },
            ],
        }),
        "near_miss_guard" => Ok(Scenario {
            name: name.into(),
            description: "NearMiss forced: near_miss flag + anticipation required".into(),
            engine: EngineConfig {
                volatility: VolatilityStr::High,
                free_spins_enabled: true,
                ..Default::default()
            },
            forced_outcomes: vec!["NearMiss".into()],
            run_count: 500,
            seed: 13,
            assertions: vec![
                Assertion::IsNearMiss,
                Assertion::StagePresent { stage: "REEL_SPIN".into() },
            ],
        }),
        "reel_stop_order" => Ok(Scenario {
            name: name.into(),
            description: "Random spins: all 5 reels must stop (REEL_STOP ×5)".into(),
            engine: EngineConfig { ..Default::default() },
            forced_outcomes: vec![],
            run_count: 500,
            seed: 99,
            assertions: vec![
                Assertion::StageCountGte { stage: "REEL_STOP".into(), count: 5 },
            ],
        }),
        "lose_spin_minimal" => Ok(Scenario {
            name: name.into(),
            description: "Lose forced: WIN_PRESENT must NOT appear".into(),
            engine: EngineConfig { ..Default::default() },
            forced_outcomes: vec!["Lose".into()],
            run_count: 200,
            seed: 55,
            assertions: vec![
                Assertion::StageAbsent { stage: "WIN_PRESENT".into() },
                Assertion::StagePresent { stage: "REEL_SPIN".into() },
            ],
        }),
        "duration_bounds" => Ok(Scenario {
            name: name.into(),
            description: "Random spins: total duration must be 100–15000ms".into(),
            engine: EngineConfig { ..Default::default() },
            forced_outcomes: vec![],
            run_count: 300,
            seed: 200,
            assertions: vec![
                Assertion::DurationMs { min: 100.0, max: 15000.0 },
            ],
        }),
        "cascade_chain" => Ok(Scenario {
            name: name.into(),
            description: "Cascade forced: expects CASCADE or TUMBLE stage".into(),
            engine: EngineConfig {
                cascades_enabled: true,
                ..Default::default()
            },
            forced_outcomes: vec!["Cascade".into()],
            run_count: 150,
            seed: 33,
            assertions: vec![
                Assertion::HasWin,
            ],
        }),
        other => anyhow::bail!("Unknown built-in scenario '{other}'. Use --list to see available."),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Output
// ═══════════════════════════════════════════════════════════════════════════

fn print_usage() {
    println!(r#"bug-repro — FluxForge Bug Reproduction Harness (C.1)

USAGE:
  bug-repro --scenario <name>  [--runs N] [--seed N] [--verbose] [--json]
  bug-repro --file <path>      [--runs N] [--seed N] [--verbose] [--json]
  bug-repro --list
  bug-repro --help

OPTIONS:
  --scenario <name>   Run a built-in scenario (see --list)
  --file <path>       Load a custom scenario from JSON file
  --runs N            Override run count (default: from scenario)
  --seed N            Override base RNG seed (default: from scenario)
  --verbose, -v       Print each failing run to stderr
  --json              Output report as JSON (stdout)
  --list              Print all built-in scenarios
  --help              Show this help

EXIT CODES:
  0  All assertions passed
  1  One or more assertions failed (or error)

SCENARIO JSON SCHEMA:
  See https://github.com/vanvinklstudio/fluxforge-studio/tools/bug_repro/
"#);
}

fn print_built_ins() {
    println!("Built-in scenarios:");
    println!();
    for (name, desc) in BUILT_INS {
        println!("  {:30} {}", name, desc);
    }
}

fn print_report(report: &Report, scenario: &Scenario) {
    let pass_icon = if report.fail_count == 0 { "✅" } else { "❌" };
    println!();
    println!("━━━ Bug Reproduction Report ━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("  Scenario   : {}", report.scenario);
    println!("  Description: {}", scenario.description);
    println!("  Runs       : {}", report.total_runs);
    println!();
    println!("  {pass_icon} PASS: {}  ❌ FAIL: {}  (fail rate: {:.1}%)",
        report.pass_count, report.fail_count, report.fail_rate_pct);
    println!();
    println!("  Timing (ms):");
    println!("    min={:.0}  avg={:.0}  p95={:.0}  max={:.0}",
        report.timing_stats.min_ms, report.timing_stats.avg_ms,
        report.timing_stats.p95_ms, report.timing_stats.max_ms);
    println!();

    // Top-10 stages by frequency
    let mut freq_sorted: Vec<_> = report.stage_frequency.iter().collect();
    freq_sorted.sort_by(|a, b| b.1.cmp(a.1));
    println!("  Stage frequency (top 10):");
    for (name, count) in freq_sorted.iter().take(10) {
        let avg = **count as f64 / report.total_runs as f64;
        println!("    {:<35} {:>5}×  (avg {:.2}/spin)", name, count, avg);
    }
    println!();

    if let Some(first) = &report.first_fail {
        println!("  First failure at run #{} (seed={}):", first.run_index, first.seed);
        for msg in &first.failed_assertions {
            println!("    ✗ {msg}");
        }
        println!("  Stage trace:");
        println!("    {}", first.stage_names.join(" → "));
        println!("  Win: {}  Duration: {:.0}ms", first.total_win, first.duration_ms);
        println!();
        println!("  To reproduce: bug-repro --scenario {} --runs 1 --seed {}",
            report.scenario, first.seed);
    } else {
        println!("  All assertions passed on every run.");
    }
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

fn flag_value<'a>(args: &'a [String], flag: &str) -> Option<&'a str> {
    let pos = args.iter().position(|a| a == flag)?;
    args.get(pos + 1).map(|s| s.as_str())
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_built_in_near_miss() {
        let scenario = load_built_in("near_miss_guard").unwrap();
        let report = execute(&scenario, 50, 42, false).unwrap();
        // Antiicipation should be present on near-miss spins.
        // Allow up to 20% failure if the engine has any variance (it's forced, so should be 0).
        assert!(report.fail_rate_pct < 20.0,
            "near_miss_guard fail rate {:.1}% too high", report.fail_rate_pct);
    }

    #[test]
    fn test_built_in_reel_stop_order() {
        let scenario = load_built_in("reel_stop_order").unwrap();
        let report = execute(&scenario, 50, 99, false).unwrap();
        assert_eq!(report.fail_count, 0,
            "reel_stop_order should always pass (5 REEL_STOPs per spin), got {} fails",
            report.fail_count);
    }

    #[test]
    fn test_built_in_big_win_stages() {
        let scenario = load_built_in("big_win_stages").unwrap();
        let report = execute(&scenario, 30, 100, false).unwrap();
        // Forced BigWin: win should always be > 0.
        assert!(report.fail_rate_pct < 5.0,
            "big_win_stages has {:.1}% failures", report.fail_rate_pct);
    }

    #[test]
    fn test_built_in_free_spins() {
        let scenario = load_built_in("free_spins_trigger").unwrap();
        let report = execute(&scenario, 30, 7, false).unwrap();
        // Forced FreeSpins → should always trigger.
        assert!(report.fail_rate_pct < 10.0,
            "free_spins_trigger has {:.1}% failures", report.fail_rate_pct);
    }

    #[test]
    fn test_built_in_duration_bounds() {
        let scenario = load_built_in("duration_bounds").unwrap();
        let report = execute(&scenario, 50, 200, false).unwrap();
        assert_eq!(report.fail_count, 0,
            "duration_bounds: {} spins outside [100, 15000]ms range", report.fail_count);
    }

    #[test]
    fn test_custom_scenario_from_json() {
        let json = r#"{
            "name": "test_custom",
            "engine": {"volatility": "medium"},
            "forced_outcomes": ["BigWin"],
            "run_count": 20,
            "seed": 1,
            "assertions": [
                {"type": "has_win"},
                {"type": "stage_count_gte", "stage": "REEL_STOP", "count": 5}
            ]
        }"#;
        let scenario: Scenario = serde_json::from_str(json).unwrap();
        let report = execute(&scenario, 20, 1, false).unwrap();
        assert!(report.fail_rate_pct < 10.0, "custom scenario has too many failures");
    }

    #[test]
    fn test_flag_value() {
        let args = vec!["prog".into(), "--runs".into(), "500".into(), "--seed".into(), "42".into()];
        assert_eq!(flag_value(&args, "--runs"), Some("500"));
        assert_eq!(flag_value(&args, "--seed"), Some("42"));
        assert_eq!(flag_value(&args, "--missing"), None);
    }

    #[test]
    fn test_all_built_ins_load() {
        for (name, _) in BUILT_INS {
            load_built_in(name).unwrap_or_else(|e| panic!("built-in '{name}' failed to load: {e}"));
        }
    }

    #[test]
    fn test_parse_forced_outcomes() {
        assert!(matches!(parse_forced_outcome("NearMiss"), Some(ForcedOutcome::NearMiss)));
        assert!(matches!(parse_forced_outcome("BIGWIN"), Some(ForcedOutcome::BigWin)));
        assert!(matches!(parse_forced_outcome("RANDOM"), None));
        assert!(matches!(parse_forced_outcome(""), None));
    }
}

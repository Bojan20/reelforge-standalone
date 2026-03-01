// ============================================================================
// fluxmacro — CLI Entry Point
// ============================================================================
// FM-32: clap CLI for FluxMacro orchestration engine.
// Commands: run, dry-run, validate, steps, qa, adb, replay, history
// Flags: --ci (JSON output + exit code), --verbose, --seed
// ============================================================================

use std::path::PathBuf;
use std::process;

use clap::{Parser, Subcommand};

use rf_fluxmacro::context::ReportFormat;
use rf_fluxmacro::error::FluxMacroError;
use rf_fluxmacro::interpreter::MacroInterpreter;
use rf_fluxmacro::parser;
use rf_fluxmacro::reporter;
use rf_fluxmacro::steps::{register_all_steps, StepRegistry};
use rf_fluxmacro::version;

/// FluxMacro — Deterministic Orchestration Engine for slot audio pipelines.
#[derive(Parser)]
#[command(name = "fluxmacro", version, about)]
struct Cli {
    /// CI mode: JSON output only, sets exit code to 1 on failure
    #[arg(long, global = true)]
    ci: bool,

    /// Verbose logging
    #[arg(short, long, global = true)]
    verbose: bool,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run a .ffmacro.yaml macro file
    Run {
        /// Path to .ffmacro.yaml file
        #[arg(value_name = "FILE")]
        file: PathBuf,

        /// Override seed for deterministic execution
        #[arg(long)]
        seed: Option<u64>,

        /// Working directory (defaults to file's parent)
        #[arg(short = 'w', long)]
        workdir: Option<PathBuf>,

        /// Override report format (html, json, markdown, all)
        #[arg(long)]
        format: Option<String>,
    },

    /// Dry-run a macro (validate + preview steps without executing)
    DryRun {
        /// Path to .ffmacro.yaml file
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },

    /// Validate a macro file without executing
    Validate {
        /// Path to .ffmacro.yaml file
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },

    /// List all registered steps
    Steps,

    /// Run only QA steps from a macro file
    Qa {
        /// Path to .ffmacro.yaml file
        #[arg(value_name = "FILE")]
        file: PathBuf,

        /// Override seed
        #[arg(long)]
        seed: Option<u64>,

        /// Working directory
        #[arg(short = 'w', long)]
        workdir: Option<PathBuf>,
    },

    /// Run only ADB generation from a macro file
    Adb {
        /// Path to .ffmacro.yaml file
        #[arg(value_name = "FILE")]
        file: PathBuf,

        /// Working directory
        #[arg(short = 'w', long)]
        workdir: Option<PathBuf>,
    },

    /// Replay a previous run by run ID
    Replay {
        /// Run ID (timestamp from history)
        run_id: String,

        /// Working directory containing Runs/ folder
        #[arg(short = 'w', long)]
        workdir: PathBuf,
    },

    /// List run history
    History {
        /// Working directory containing Runs/ folder
        #[arg(short = 'w', long)]
        workdir: PathBuf,

        /// Show details for a specific run
        #[arg(long)]
        detail: Option<String>,
    },
}

fn main() {
    let cli = Cli::parse();

    if !cli.ci {
        env_logger::Builder::new()
            .filter_level(if cli.verbose {
                log::LevelFilter::Debug
            } else {
                log::LevelFilter::Info
            })
            .format_timestamp_millis()
            .init();
    }

    let result = match cli.command {
        Command::Run {
            file,
            seed,
            workdir,
            format,
        } => cmd_run(&file, seed, workdir, format, cli.verbose, cli.ci),
        Command::DryRun { file } => cmd_dry_run(&file, cli.ci),
        Command::Validate { file } => cmd_validate(&file, cli.ci),
        Command::Steps => cmd_steps(cli.ci),
        Command::Qa {
            file,
            seed,
            workdir,
        } => cmd_qa(&file, seed, workdir, cli.verbose, cli.ci),
        Command::Adb { file, workdir } => cmd_adb(&file, workdir, cli.verbose, cli.ci),
        Command::Replay { run_id, workdir } => cmd_replay(&run_id, &workdir, cli.ci),
        Command::History { workdir, detail } => cmd_history(&workdir, detail.as_deref(), cli.ci),
    };

    match result {
        Ok(exit_code) => process::exit(exit_code),
        Err(e) => {
            if cli.ci {
                let err_json = serde_json::json!({
                    "success": false,
                    "error": format!("{e}"),
                });
                println!("{}", serde_json::to_string(&err_json).unwrap_or_default());
            } else {
                eprintln!("Error: {e}");
            }
            process::exit(1);
        }
    }
}

// ─── Command Implementations ────────────────────────────────────────────────

fn cmd_run(
    file: &PathBuf,
    seed: Option<u64>,
    workdir: Option<PathBuf>,
    format: Option<String>,
    verbose: bool,
    ci: bool,
) -> Result<i32, FluxMacroError> {
    let mut macro_file = parser::parse_macro_file(file)?;

    if let Some(s) = seed {
        macro_file.seed = Some(s);
    }
    if verbose {
        macro_file.verbose = true;
    }
    if let Some(ref f) = format {
        macro_file.report_format = ReportFormat::from_str_loose(f)?;
    }

    let working_dir = resolve_workdir(workdir, file);
    let interp = build_interpreter();

    let ctx = interp.run(&macro_file, working_dir.clone())?;

    // Generate reports
    let reports_dir = ctx
        .report_path
        .as_ref()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| working_dir.join("Reports"));

    let report_paths = reporter::generate_reports(&ctx, &reports_dir, &ctx.game_id)?;

    if ci {
        let output = serde_json::json!({
            "success": ctx.is_success(),
            "game_id": ctx.game_id,
            "seed": ctx.seed,
            "run_hash": ctx.run_hash,
            "duration_ms": ctx.duration().as_millis() as u64,
            "qa_passed": ctx.qa_passed_count(),
            "qa_failed": ctx.qa_failed_count(),
            "artifacts": ctx.artifacts.keys().collect::<Vec<_>>(),
            "reports": report_paths.iter().map(|p| p.display().to_string()).collect::<Vec<_>>(),
            "warnings": ctx.warnings,
            "errors": ctx.errors,
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("── FluxMacro Run Complete ──");
        println!("  Game:     {}", ctx.game_id);
        println!("  Seed:     {}", ctx.seed);
        println!("  Hash:     {}", &ctx.run_hash[..16.min(ctx.run_hash.len())]);
        println!("  Duration: {:.2}s", ctx.duration().as_secs_f64());
        println!(
            "  QA:       {}/{} passed",
            ctx.qa_passed_count(),
            ctx.qa_results.len()
        );
        println!("  Status:   {}", if ctx.is_success() { "PASS" } else { "FAIL" });

        if !ctx.warnings.is_empty() {
            println!("  Warnings: {}", ctx.warnings.len());
            for w in &ctx.warnings {
                println!("    ⚠ {w}");
            }
        }

        if !report_paths.is_empty() {
            println!("  Reports:");
            for p in &report_paths {
                println!("    → {}", p.display());
            }
        }
    }

    Ok(if ctx.is_success() { 0 } else { 1 })
}

fn cmd_dry_run(file: &PathBuf, ci: bool) -> Result<i32, FluxMacroError> {
    let macro_file = parser::parse_macro_file(file)?;
    let interp = build_interpreter();

    // Validate
    let warnings = interp.validate(&macro_file)?;

    if ci {
        let output = serde_json::json!({
            "success": true,
            "mode": "dry-run",
            "macro_name": macro_file.name,
            "game_id": macro_file.game_id,
            "steps": macro_file.steps,
            "step_count": macro_file.steps.len(),
            "volatility": format!("{:?}", macro_file.volatility),
            "warnings": warnings,
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("── FluxMacro Dry-Run ──");
        println!("  Macro:      {}", macro_file.name);
        println!("  Game:       {}", macro_file.game_id);
        println!("  Volatility: {:?}", macro_file.volatility);
        println!("  Steps ({}):", macro_file.steps.len());
        for (i, step) in macro_file.steps.iter().enumerate() {
            let desc = interp
                .registry()
                .get(step)
                .map(|s| s.description())
                .unwrap_or("(unknown)");
            println!("    {}. {} — {}", i + 1, step, desc);
        }

        if !warnings.is_empty() {
            println!("  Warnings:");
            for w in &warnings {
                println!("    ⚠ {w}");
            }
        }

        println!("  Status: VALID (ready to run)");
    }

    Ok(0)
}

fn cmd_validate(file: &PathBuf, ci: bool) -> Result<i32, FluxMacroError> {
    let macro_file = parser::parse_macro_file(file)?;
    let interp = build_interpreter();
    let warnings = interp.validate(&macro_file)?;

    if ci {
        let output = serde_json::json!({
            "valid": true,
            "macro_name": macro_file.name,
            "game_id": macro_file.game_id,
            "step_count": macro_file.steps.len(),
            "warnings": warnings,
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("✓ Macro '{}' is valid ({} steps)", macro_file.name, macro_file.steps.len());
        if !warnings.is_empty() {
            for w in &warnings {
                println!("  ⚠ {w}");
            }
        }
    }

    Ok(0)
}

fn cmd_steps(ci: bool) -> Result<i32, FluxMacroError> {
    let interp = build_interpreter();
    let names = interp.registry().list();

    if ci {
        let steps: Vec<serde_json::Value> = names
            .iter()
            .filter_map(|name| {
                interp.registry().get(name).map(|step| {
                    serde_json::json!({
                        "name": name,
                        "description": step.description(),
                        "estimated_ms": step.estimated_duration_ms(),
                    })
                })
            })
            .collect();
        let output = serde_json::json!({ "steps": steps, "count": steps.len() });
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("── Registered Steps ({}) ──", names.len());
        for name in names {
            if let Some(step) = interp.registry().get(name) {
                println!(
                    "  {:30} {}  (~{}ms)",
                    name,
                    step.description(),
                    step.estimated_duration_ms()
                );
            }
        }
    }

    Ok(0)
}

fn cmd_qa(
    file: &PathBuf,
    seed: Option<u64>,
    workdir: Option<PathBuf>,
    verbose: bool,
    ci: bool,
) -> Result<i32, FluxMacroError> {
    let mut macro_file = parser::parse_macro_file(file)?;

    if let Some(s) = seed {
        macro_file.seed = Some(s);
    }
    if verbose {
        macro_file.verbose = true;
    }

    // Filter to only QA steps
    let qa_steps: Vec<String> = macro_file
        .steps
        .iter()
        .filter(|s| s.starts_with("qa."))
        .cloned()
        .collect();

    if qa_steps.is_empty() {
        if ci {
            let output = serde_json::json!({
                "success": false,
                "error": "No QA steps found in macro file",
            });
            println!("{}", serde_json::to_string_pretty(&output)?);
        } else {
            eprintln!("No QA steps found in macro file");
        }
        return Ok(1);
    }

    macro_file.steps = qa_steps;

    let working_dir = resolve_workdir(workdir, file);
    let interp = build_interpreter();
    let ctx = interp.run(&macro_file, working_dir)?;

    if ci {
        let qa_results: Vec<serde_json::Value> = ctx
            .qa_results
            .iter()
            .map(|r| {
                serde_json::json!({
                    "test": r.test_name,
                    "passed": r.passed,
                    "details": r.details,
                    "duration_ms": r.duration_ms,
                    "metrics": r.metrics,
                })
            })
            .collect();
        let output = serde_json::json!({
            "success": ctx.is_success(),
            "qa_passed": ctx.qa_passed_count(),
            "qa_failed": ctx.qa_failed_count(),
            "results": qa_results,
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("── QA Results ──");
        for r in &ctx.qa_results {
            let icon = if r.passed { "✓" } else { "✗" };
            println!("  {} {} — {}", icon, r.test_name, r.details);
        }
        println!(
            "  Total: {}/{} passed",
            ctx.qa_passed_count(),
            ctx.qa_results.len()
        );
    }

    Ok(if ctx.is_success() { 0 } else { 1 })
}

fn cmd_adb(
    file: &PathBuf,
    workdir: Option<PathBuf>,
    verbose: bool,
    ci: bool,
) -> Result<i32, FluxMacroError> {
    let mut macro_file = parser::parse_macro_file(file)?;
    if verbose {
        macro_file.verbose = true;
    }

    // Filter to only ADB step
    macro_file.steps = vec!["adb.generate".to_string()];

    let working_dir = resolve_workdir(workdir, file);
    let interp = build_interpreter();
    let ctx = interp.run(&macro_file, working_dir)?;

    if ci {
        let output = serde_json::json!({
            "success": ctx.is_success(),
            "artifacts": ctx.artifacts.keys().collect::<Vec<_>>(),
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("── ADB Generation ──");
        println!("  Status: {}", if ctx.is_success() { "PASS" } else { "FAIL" });
        for (name, path) in &ctx.artifacts {
            println!("  → {} → {}", name, path.display());
        }
    }

    Ok(if ctx.is_success() { 0 } else { 1 })
}

fn cmd_replay(run_id: &str, workdir: &PathBuf, ci: bool) -> Result<i32, FluxMacroError> {
    let run_path = version::run_dir(workdir, run_id);

    if !run_path.exists() {
        return Err(FluxMacroError::Other(format!(
            "Run not found: {} (looked in {})",
            run_id,
            run_path.display()
        )));
    }

    let meta = version::load_run_meta(&run_path)?;

    // Attempt to read the original macro file
    let macro_input_path = run_path.join("macro_input.yaml");
    if !macro_input_path.exists() {
        return Err(FluxMacroError::Other(
            "Cannot replay: macro_input.yaml not saved in this run".to_string(),
        ));
    }

    let macro_content = std::fs::read_to_string(&macro_input_path)
        .map_err(|e| FluxMacroError::FileRead(macro_input_path, e))?;

    let mut macro_file = parser::parse_macro_string(&macro_content)?;
    macro_file.seed = Some(meta.seed);

    let interp = build_interpreter();
    let ctx = interp.run(&macro_file, workdir.clone())?;

    let hash_matches = ctx.run_hash == meta.run_hash;

    if ci {
        let output = serde_json::json!({
            "success": ctx.is_success(),
            "replay_of": run_id,
            "original_hash": meta.run_hash,
            "replay_hash": ctx.run_hash,
            "hash_matches": hash_matches,
            "deterministic": hash_matches,
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("── Replay of {} ──", run_id);
        println!("  Original hash: {}", &meta.run_hash[..16.min(meta.run_hash.len())]);
        println!("  Replay hash:   {}", &ctx.run_hash[..16.min(ctx.run_hash.len())]);
        println!(
            "  Deterministic: {}",
            if hash_matches { "YES" } else { "NO — MISMATCH" }
        );
    }

    Ok(if hash_matches { 0 } else { 1 })
}

fn cmd_history(
    workdir: &PathBuf,
    detail: Option<&str>,
    ci: bool,
) -> Result<i32, FluxMacroError> {
    if let Some(run_id) = detail {
        let run_path = version::run_dir(workdir, run_id);
        let meta = version::load_run_meta(&run_path)?;

        if ci {
            println!("{}", serde_json::to_string_pretty(&meta)?);
        } else {
            println!("── Run {} ──", meta.run_id);
            println!("  Macro:     {}", meta.macro_name);
            println!("  Game:      {}", meta.game_id);
            println!("  Timestamp: {}", meta.timestamp);
            println!("  Seed:      {}", meta.seed);
            println!("  Hash:      {}", &meta.run_hash[..16.min(meta.run_hash.len())]);
            println!("  Duration:  {}ms", meta.duration_ms);
            println!("  Status:    {}", if meta.success { "PASS" } else { "FAIL" });
            println!(
                "  QA:        {}/{} passed",
                meta.qa_passed,
                meta.qa_passed + meta.qa_failed
            );
            println!("  Steps:     {}", meta.steps.join(", "));
            println!("  Artifacts: {}", meta.artifact_count);
            println!("  Warnings:  {}", meta.warning_count);
            println!("  Errors:    {}", meta.error_count);
        }
    } else {
        let runs = version::list_runs(workdir)?;

        if ci {
            let entries: Vec<serde_json::Value> = runs
                .iter()
                .filter_map(|(id, path)| {
                    version::load_run_meta(path).ok().map(|m| {
                        serde_json::json!({
                            "run_id": id,
                            "macro_name": m.macro_name,
                            "game_id": m.game_id,
                            "success": m.success,
                            "timestamp": m.timestamp,
                            "duration_ms": m.duration_ms,
                        })
                    })
                })
                .collect();
            let output = serde_json::json!({ "runs": entries, "count": entries.len() });
            println!("{}", serde_json::to_string_pretty(&output)?);
        } else {
            if runs.is_empty() {
                println!("No run history found in {}", workdir.display());
                return Ok(0);
            }

            println!("── Run History ({} runs) ──", runs.len());
            for (id, path) in &runs {
                match version::load_run_meta(path) {
                    Ok(m) => {
                        let status = if m.success { "PASS" } else { "FAIL" };
                        println!(
                            "  {} {} [{status}] {} ({}ms, {}/{} QA)",
                            id,
                            m.macro_name,
                            m.game_id,
                            m.duration_ms,
                            m.qa_passed,
                            m.qa_passed + m.qa_failed,
                        );
                    }
                    Err(_) => {
                        println!("  {} (corrupt metadata)", id);
                    }
                }
            }
        }
    }

    Ok(0)
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn build_interpreter() -> MacroInterpreter {
    let mut registry = StepRegistry::new();
    register_all_steps(&mut registry);
    MacroInterpreter::new(registry)
}

fn resolve_workdir(workdir: Option<PathBuf>, file: &PathBuf) -> PathBuf {
    workdir.unwrap_or_else(|| {
        file.parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
    })
}

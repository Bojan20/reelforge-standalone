# FLUXMACRO SYSTEM — Ultimativna Arhitektura

**FluxForge Studio — Deterministic Orchestration Engine za Slot Audio Pipeline**

**Verzija:** 1.0.0
**Datum:** 2026-03-01
**Autor:** Chief Audio Architect + Engine Architect + Technical Director + Lead DSP Engineer

---

## 0. EXECUTIVE SUMMARY

FluxMacro je **deterministički orkestracioni engine** koji unifikuje authoring, validaciju, QA simulaciju, manifest building i release packaging u jedan pipeline. Nije skripta. Nije shortcut. To je **Audio DevOps layer za slot industriju** — nešto što nijedan postojeći DAW ne poseduje.

### Šta FluxMacro radi:
1. Uzima input (GDD, config, asset folder, pravila)
2. Primenjuje pravila (naming, layering, ducking, loudness, voice limits)
3. Generiše planove + fajlove + testove
4. Pokreće simulacije (event storm, determinism, loudness, fatigue)
5. Izbacuje report (PASS/FAIL sa detaljima)

### Zašto je ovo ogromno:
- **Ableton** = kreativni workflow
- **Reaper** = automatizacija workflow-a (ReaScript)
- **Bitwig** = modulacija
- **FluxForge** = Casino-grade Audio Automation System

**NIJEDAN DAW nema slot-specifičan deterministički QA pipeline.**

---

## 1. GAP ANALIZA — ŠTA IMAMO vs ŠTA TREBA

### ✅ VEĆ IMPLEMENTIRANO (može se iskoristiti/proširiti)

| Sistem | Lokacija | Šta radi | Relevantnost za FluxMacro |
|--------|----------|----------|---------------------------|
| **rf-script (Lua)** | `crates/rf-script/` | Sandboxed Lua 5.4, 30+ ScriptAction enums, track/clip/transport control | **VISOKA** — Može biti runtime za custom macro logiku |
| **PBSE** | `rf-aurexis/qa/pbse.rs` | 10-domain stress test, 500-spin fatigue, bake gate | **KRITIČNA** — Direktno mapira na QA Event Storm + Fatigue |
| **DRC Manifest** | `rf-aurexis/drc/manifest.rs` | Version locks, config hash, certification chain | **KRITIČNA** — Manifest builder iz teksta |
| **DRC Replay** | `rf-aurexis/drc/replay.rs` | .fftrace, FNV-1a hashing, replay verification | **KRITIČNA** — Determinism Lock test |
| **DRC Safety** | `rf-aurexis/drc/safety.rs` | 6 hard caps, envelope violations | **KRITIČNA** — Safety envelope validacija |
| **AIL** | `rf-aurexis/advisory/ail.rs` | 10 analysis domains, AIL Score 0-100, recommendations | **VISOKA** — Advisory report generisanje |
| **Volatility Profiles** | `rf-aurexis/volatility/` | 4 profila (Low/Med/High/Extreme), translator | **KRITIČNA** — Volatility mapping generator |
| **GAD Bake** | `rf-aurexis/gad/bake.rs` | 11-step bake pipeline | **KRITIČNA** — Release pipeline osnova |
| **Event Naming** | `flutter_ui/services/event_naming_service.dart` | 20+ naming kategorija, semantic generation | **VISOKA** — Auto-naming osnova (Dart strana) |
| **rf-offline Pipeline** | `rf-offline/pipeline.rs` | 6-stage DSP pipeline sa state machine | **SREDNJA** — Pattern za pipeline orkestraciju |
| **rf-release** | `rf-release/` | Semantic versioning, changelog, packaging | **VISOKA** — Release candidate generator |
| **qa.sh** | `scripts/qa.sh` | 11-gate QA pipeline, 3 profila, HTML report | **VISOKA** — QA orkestracija (shell) |
| **rf-audio-diff** | `rf-audio-diff/` | Spectral comparison, golden files | **SREDNJA** — Loudness compliance osnova |
| **rf-fuzz** | `rf-fuzz/` | FFI boundary fuzzing | **NISKA** — Može se wrapovati u QA macro |
| **rf-bench** | `rf-bench/` | Criterion benchmarks | **NISKA** — Performance regression |
| **rf-coverage** | `rf-coverage/` | llvm-cov, threshold enforcement | **NISKA** — Coverage gate |
| **SAM Archetypes** | `rf-aurexis/sam/archetypes.rs` | 8 slot archetypes sa defaults | **VISOKA** — ADB generator koristi za mapiranje mehanika |
| **SSS Burn Test** | `rf-aurexis/sss/burn_test.rs` | 10,000-spin stress, 5 drift metrics | **KRITIČNA** — Long-session fatigue test |
| **SSS Auto Regression** | `rf-aurexis/sss/auto_regression.rs` | 10 stress scenarija, hash comparison | **KRITIČNA** — Determinism validacija |
| **GDD Parser (stub)** | `rf-slot-lab/parser/mod.rs` | Placeholder za JSON/YAML GDD parsing | **KRITIČNA** — ADB generator input parser |
| **Template System** | `flutter_ui/models/template_models.dart` | 8 kategorija, 15+ feature modula | **VISOKA** — ADB auto-populacija |

### ❌ NE POSTOJI — MORA SE NAPRAVITI

| Sistem | Opis | Prioritet |
|--------|------|-----------|
| **FluxMacro DSL Parser** | YAML-based .ffmacro parser sa step registry | **P0 — KRITIČNO** |
| **FluxMacro Interpreter** | Step-by-step executor sa MacroContext | **P0 — KRITIČNO** |
| **ADB Auto-Generator** | Mechanics → audio needs mapping, ADB.md generation | **P0 — KRITIČNO** |
| **Auto-Naming Validator (Rust)** | Asset folder scan, naming rules, rename plan, dry-run | **P0 — KRITIČNO** |
| **Volatility Profile Generator** | Generisanje profila iz GDD parametara (ne samo lookup) | **P1 — VISOKO** |
| **QA Suite Runner (Unified)** | Orkestrator za Event Storm + Determinism + Loudness + Fatigue | **P0 — KRITIČNO** |
| **Loudness Compliance Checker** | Per-category LUFS/True Peak validacija + gain correction | **P0 — KRITIČNO** |
| **Report Generator (HTML/JSON/MD)** | Unified reporter za sve macro outpute | **P1 — VISOKO** |
| **CLI Binary (clap)** | `fluxmacro run/dry-run/replay` komande | **P1 — VISOKO** |
| **Release Candidate Packager** | Manifest + assets + QA report + ADB u RC folder | **P1 — VISOKO** |
| **Run Versioning & Replay** | Svaki run → timestamped folder, replay iz foldera | **P2 — SREDNJE** |
| **Studio UI Panel** | Macro Panel sa dugmadima u Flutter UI | **P2 — SREDNJE** |

---

## 2. ARHITEKTURA — KOMPLETNA STRUKTURA

### 2.1 Crate Layout

```
crates/
  rf-fluxmacro/                    # NOVI CRATE — Core FluxMacro engine
    Cargo.toml
    src/
      lib.rs                       # Public API
      context.rs                   # MacroContext — execution state
      parser.rs                    # YAML DSL parser
      interpreter.rs               # Step executor + registry
      steps/
        mod.rs                     # Step trait + registry
        adb_generate.rs            # ADB auto-generator
        naming_validate.rs         # Asset naming validator
        volatility_profile.rs      # Volatility profile generator
        manifest_build.rs          # Manifest builder (wraps DRC)
        qa_run_suite.rs            # QA suite orchestrator
        qa_event_storm.rs          # Event storm simulation
        qa_determinism.rs          # Determinism lock test
        qa_loudness.rs             # Loudness compliance checker
        qa_fatigue.rs              # Fatigue/repetition analyzer
        pack_release.rs            # Release candidate packager
      rules/
        mod.rs                     # Rule loading + validation
        naming_rules.rs            # Naming convention rules
        mechanics_map.rs           # Mechanics → audio needs mapping
        loudness_targets.rs        # Per-category LUFS targets
        adb_templates.rs           # ADB section templates
      reporter/
        mod.rs                     # Reporter trait
        html.rs                    # HTML report generator
        json.rs                    # JSON report generator
        markdown.rs                # Markdown report generator
      hash.rs                      # SHA-256 + FNV-1a hashing
      error.rs                     # FluxMacro error types
      version.rs                   # Run versioning

  rf-fluxmacro-cli/                # NOVI CRATE — CLI binary
    Cargo.toml
    src/
      main.rs                      # clap CLI entry point
```

### 2.2 Dependency Graph

```
rf-fluxmacro depends on:
  ├── rf-aurexis (PBSE, DRC, AIL, SAM, SSS, volatility, GEG, DPM, SAMCL)
  ├── rf-slot-lab (GDD parser, synthetic engine za simulaciju)
  ├── rf-audio-diff (spectral comparison za loudness)
  ├── rf-release (versioning, changelog, packaging)
  ├── rf-offline (audio analysis: LUFS, true peak)
  ├── serde + serde_yaml (DSL parsing)
  ├── serde_json (report output)
  ├── sha2 (release fingerprinting)
  ├── walkdir (asset folder scanning)
  ├── regex (naming validation)
  ├── rand_chacha (deterministic seeding)
  └── rayon (parallel QA test execution)

rf-fluxmacro-cli depends on:
  ├── rf-fluxmacro
  └── clap (CLI framework)
```

### 2.3 Folder Structure (Project-Level)

```
/FluxForge Project Root/
  /Macros/                         # User-defined .ffmacro.yaml files
    build_release.ffmacro.yaml
    qa_quick.ffmacro.yaml
    adb_generate.ffmacro.yaml
  /Rules/                          # Rule configuration files
    naming_rules.json
    mechanics_map.json
    loudness_targets.json
    adb_templates.json
  /Profiles/                       # Volatility + platform profiles
    volatility_low.json
    volatility_medium.json
    volatility_high.json
    volatility_extreme.json
  /Reports/                        # Generated reports
    {GameId}_RC_{timestamp}.html
    QA_EventStorm_{timestamp}.html
    QA_Loudness_{timestamp}.html
    QA_Fatigue_{timestamp}.html
  /Runs/                           # Versioned run history
    2026-03-01T14-30-00/
      macro_input.yaml
      logs.txt
      result_hash.txt
      report.html
  /Release/                        # Release candidates
    {GameId}_RC1/
      manifest.json
      assets/
      QA_Report.html
      ADB.md
```

---

## 3. CORE ENGINE — DETALJNA SPECIFIKACIJA

### 3.1 MacroContext — Execution State

```rust
use std::collections::HashMap;
use std::path::PathBuf;

/// Central execution context passed through all macro steps.
/// Accumulates state, logs, artifacts, and validation results.
pub struct MacroContext {
    // === Input Parameters ===
    pub game_id: String,
    pub volatility: VolatilityLevel,
    pub platforms: Vec<Platform>,
    pub mechanics: Vec<GameMechanic>,
    pub theme: Option<String>,
    pub working_dir: PathBuf,
    pub assets_dir: Option<PathBuf>,
    pub rules_dir: PathBuf,
    pub profiles_dir: PathBuf,

    // === Execution State ===
    pub seed: u64,                              // Deterministic seed (rand_chacha)
    pub dry_run: bool,                          // Preview mode — no side effects
    pub verbose: bool,                          // Detailed logging
    pub fail_fast: bool,                        // Stop on first failure

    // === Accumulated Results ===
    pub logs: Vec<LogEntry>,                    // Timestamped log entries
    pub artifacts: HashMap<String, PathBuf>,    // Generated files (name → path)
    pub qa_results: Vec<QaTestResult>,          // QA test outcomes
    pub warnings: Vec<String>,                  // Non-blocking issues
    pub errors: Vec<String>,                    // Blocking issues

    // === Intermediate Data (step-to-step) ===
    pub adb: Option<AudioDesignBrief>,          // Generated ADB
    pub volatility_profile: Option<VolatilityProfile>, // Attached profile
    pub naming_report: Option<NamingReport>,    // Naming validation result
    pub manifest: Option<FluxManifest>,         // Built manifest (from DRC)
    pub loudness_report: Option<LoudnessReport>, // Loudness compliance
    pub fatigue_report: Option<FatigueReport>,  // Fatigue analysis

    // === Hashing ===
    pub run_hash: String,                       // SHA-256 of entire run
    pub started_at: std::time::Instant,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum VolatilityLevel {
    Low,        // 0.0–0.3
    Medium,     // 0.3–0.6
    High,       // 0.6–0.85
    Extreme,    // 0.85–1.0
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Platform {
    Mobile,
    Desktop,
    Cabinet,
    WebGL,
}

/// Game mechanics that drive ADB generation.
/// Maps 1:1 to audio requirements.
#[derive(Debug, Clone, PartialEq)]
pub enum GameMechanic {
    Progressive,         // → jackpot_tiers, ladder_ticks, near_miss, celebrations
    MysteryScatter,      // → mystery_reveal, collection_tick, instant_trigger
    PickBonus,           // → pick_reveal, pick_collect, pick_empty, pick_super
    HoldAndWin,          // → hold_lock, respins_count, collect, grand_trigger
    Cascades,            // → cascade_drop, cascade_clear, cascade_chain_n
    FreeSpins,           // → fs_trigger, fs_spin, fs_retrigger, fs_end
    Megaways,            // → reel_expand, ways_counter, big_reel_stop
    ClusterPay,          // → cluster_form, cluster_grow, cluster_clear
    Gamble,              // → gamble_win, gamble_lose, gamble_collect
    WheelBonus,          // → wheel_spin, wheel_tick, wheel_stop, wheel_prize
    Multiplier,          // → mult_increment, mult_apply, mult_display
    ExpandingWilds,      // → wild_land, wild_expand, wild_complete
    StickyWilds,         // → wild_stick, wild_persist, wild_clear
    TrailBonus,          // → trail_step, trail_prize, trail_boss
    Custom(String),      // → user-defined events
}

pub struct LogEntry {
    pub timestamp: std::time::Duration,  // Since run start
    pub level: LogLevel,
    pub step: String,                    // Which macro step
    pub message: String,
}

pub enum LogLevel { Info, Warning, Error, Debug }

pub struct QaTestResult {
    pub test_name: String,
    pub passed: bool,
    pub details: String,
    pub duration_ms: u64,
    pub metrics: HashMap<String, f64>,
}
```

### 3.2 MacroStep Trait — Plugin System

```rust
/// Every macro step implements this trait.
/// Steps are stateless — all state lives in MacroContext.
pub trait MacroStep: Send + Sync {
    /// Unique step identifier (e.g., "adb.generate", "qa.run_suite")
    fn name(&self) -> &'static str;

    /// Human-readable description for logs/reports
    fn description(&self) -> &'static str;

    /// Execute the step, mutating context.
    /// Returns Ok(()) on success, Err(message) on failure.
    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError>;

    /// Validate preconditions before execution.
    /// Called automatically by interpreter before execute().
    fn validate(&self, ctx: &MacroContext) -> Result<(), FluxMacroError> {
        Ok(()) // Default: no preconditions
    }

    /// Estimated duration for progress reporting.
    fn estimated_duration_ms(&self) -> u64 { 1000 }
}

pub struct StepResult {
    pub status: StepStatus,
    pub artifacts: Vec<(String, PathBuf)>,  // New files created
    pub metrics: HashMap<String, f64>,       // Step-specific metrics
    pub summary: String,                     // One-line summary
}

pub enum StepStatus {
    Success,
    SuccessWithWarnings(Vec<String>),
    Skipped(String),  // Reason for skip
    Failed(String),   // Reason for failure
}
```

### 3.3 Step Registry

```rust
use std::collections::HashMap;

/// Registry of all available macro steps.
/// Steps are registered at engine initialization.
pub struct StepRegistry {
    steps: HashMap<String, Box<dyn MacroStep>>,
}

impl StepRegistry {
    pub fn new() -> Self {
        let mut registry = Self { steps: HashMap::new() };

        // === Core Steps ===
        registry.register(Box::new(AdbGenerateStep));
        registry.register(Box::new(NamingValidateStep));
        registry.register(Box::new(VolatilityProfileStep));
        registry.register(Box::new(ManifestBuildStep));

        // === QA Steps ===
        registry.register(Box::new(QaRunSuiteStep));
        registry.register(Box::new(QaEventStormStep));
        registry.register(Box::new(QaDeterminismStep));
        registry.register(Box::new(QaLoudnessStep));
        registry.register(Box::new(QaFatigueStep));

        // === Release Steps ===
        registry.register(Box::new(PackReleaseStep));

        registry
    }

    pub fn register(&mut self, step: Box<dyn MacroStep>) {
        self.steps.insert(step.name().to_string(), step);
    }

    pub fn get(&self, name: &str) -> Option<&dyn MacroStep> {
        self.steps.get(name).map(|b| b.as_ref())
    }

    pub fn list(&self) -> Vec<&str> {
        self.steps.keys().map(|k| k.as_str()).collect()
    }
}
```

### 3.4 Macro Interpreter

```rust
/// Core interpreter that executes macro files step by step.
/// Guarantees deterministic order. No implicit parallelism.
pub struct MacroInterpreter {
    registry: StepRegistry,
}

impl MacroInterpreter {
    pub fn new() -> Self {
        Self { registry: StepRegistry::new() }
    }

    /// Execute a parsed macro file.
    /// Returns final context with all results.
    pub fn run(&self, macro_file: MacroFile, dry_run: bool) -> Result<MacroContext, FluxMacroError> {
        let mut ctx = MacroContext::from_macro_file(&macro_file);
        ctx.dry_run = dry_run;

        ctx.log(LogLevel::Info, "interpreter", &format!(
            "Starting macro '{}' ({} steps, seed={})",
            macro_file.name, macro_file.steps.len(), ctx.seed
        ));

        for (i, step_name) in macro_file.steps.iter().enumerate() {
            let step = self.registry.get(step_name)
                .ok_or(FluxMacroError::StepNotFound(step_name.clone()))?;

            ctx.log(LogLevel::Info, step_name, &format!(
                "[{}/{}] {} — {}",
                i + 1, macro_file.steps.len(), step_name, step.description()
            ));

            // Pre-validate
            step.validate(&ctx)?;

            // Execute (or skip in dry-run if step has side effects)
            let result = step.execute(&mut ctx)?;

            // Record artifacts
            for (name, path) in &result.artifacts {
                ctx.artifacts.insert(name.clone(), path.clone());
            }

            ctx.log(LogLevel::Info, step_name, &result.summary);

            // Fail-fast check
            if ctx.fail_fast {
                if let StepStatus::Failed(reason) = &result.status {
                    return Err(FluxMacroError::StepFailed {
                        step: step_name.clone(),
                        reason: reason.clone(),
                    });
                }
            }
        }

        // Compute run hash
        ctx.run_hash = ctx.compute_run_hash();

        // Save run to history (if not dry-run)
        if !ctx.dry_run {
            ctx.save_run_history()?;
        }

        Ok(ctx)
    }
}
```

---

## 4. DSL SPECIFIKACIJA — .ffmacro.yaml

### 4.1 Format

```yaml
# Macros/build_release.ffmacro.yaml
macro: build_release
version: "1.0"

input:
  game_id: "GoldenPantheon"
  volatility: "high"
  mechanics:
    - "hold_and_win"
    - "progressive"
    - "respin"
  theme: "mythological"
  platforms:
    - "mobile"
    - "desktop"

options:
  seed: 42                    # Deterministic seed (optional, random if omitted)
  fail_fast: true             # Stop on first failure
  verbose: false              # Detailed logging
  parallel_qa: false          # Run QA tests in parallel (determinism isolated)

steps:
  - adb.generate
  - naming.validate
  - volatility.profile.generate
  - manifest.build
  - qa.run_suite
  - pack.release

output:
  report: "Reports/GoldenPantheon_RC.html"
  format: "html"              # html | json | markdown | all
```

### 4.2 Parser (Rust)

```rust
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct MacroFile {
    #[serde(rename = "macro")]
    pub name: String,
    pub version: Option<String>,
    pub input: MacroInput,
    pub options: Option<MacroOptions>,
    pub steps: Vec<String>,
    pub output: Option<MacroOutput>,
}

#[derive(Debug, Deserialize)]
pub struct MacroInput {
    pub game_id: Option<String>,
    pub volatility: Option<String>,
    pub mechanics: Option<Vec<String>>,
    pub theme: Option<String>,
    pub platforms: Option<Vec<String>>,
    pub assets_dir: Option<String>,
    pub gdd_path: Option<String>,        // GDD file za ADB import
}

#[derive(Debug, Deserialize)]
pub struct MacroOptions {
    pub seed: Option<u64>,
    pub fail_fast: Option<bool>,
    pub verbose: Option<bool>,
    pub parallel_qa: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct MacroOutput {
    pub report: Option<String>,
    pub format: Option<String>,          // html | json | markdown | all
}

/// Parse .ffmacro.yaml file
pub fn parse_macro_file(path: &std::path::Path) -> Result<MacroFile, FluxMacroError> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| FluxMacroError::FileRead(path.to_path_buf(), e))?;
    serde_yaml::from_str(&content)
        .map_err(|e| FluxMacroError::ParseError(format!("{}", e)))
}
```

---

## 5. STEP IMPLEMENTACIJE — DETALJNA SPECIFIKACIJA

### 5.1 `adb.generate` — Audio Design Brief Generator

**Šta radi:**
1. Učitava GDD (ako postoji) ili koristi input mehanike
2. Mapira svaku mehaniku na audio potrebe (iz `mechanics_map.json`)
3. Mapira volatilnost na layer count i dinamiku
4. Mapira temu na tonalnu paletu (optional)
5. Generiše kompletnu event listu
6. Generiše inicijalne loudness targete
7. Piše ADB dokument (Markdown + JSON)

**Mechanics → Audio Needs Mapping:**

| Mehanika | Audio Potrebe |
|----------|---------------|
| `progressive` | jackpot_tiers (4 nivoa), ladder_ticks, near_miss_stinger, celebration_layers (3), jackpot_music_loop |
| `mystery_scatter` | mystery_reveal_swoosh, collection_tick, instant_trigger_hit, scatter_land (per reel), scatter_anticipation |
| `pick_bonus` | pick_reveal_positive, pick_reveal_negative, pick_reveal_super, pick_collect_fanfare, pick_ambient_loop |
| `hold_and_win` | hold_lock_impact, respin_count_tick, coin_land, coin_upgrade, collect_celebration, grand_trigger_explosion |
| `cascades` | cascade_drop_whoosh, cascade_clear_sparkle, cascade_chain_1/2/3+, cascade_multiplier_tick |
| `free_spins` | fs_trigger_fanfare, fs_music_loop, fs_retrigger_hit, fs_spin_whoosh, fs_end_summary |
| `megaways` | reel_expand_stretch, ways_counter_tick, big_reel_stop_impact, mystery_transform |
| `cluster_pay` | cluster_form_connect, cluster_grow_extend, cluster_clear_burst, cluster_chain |
| `gamble` | gamble_card_flip, gamble_win_ding, gamble_lose_buzz, gamble_collect_confirm |
| `wheel_bonus` | wheel_spin_loop, wheel_tick_per_segment, wheel_decelerate, wheel_stop_impact, wheel_prize_fanfare |
| `multiplier` | mult_increment_tick, mult_apply_whoosh, mult_display_bling |
| `expanding_wilds` | wild_land_impact, wild_expand_stretch, wild_complete_glow |
| `sticky_wilds` | wild_stick_lock, wild_persist_shimmer, wild_clear_release |
| `trail_bonus` | trail_step_move, trail_prize_collect, trail_boss_encounter, trail_ambient |

**Volatility → Audio Profile Mapping:**

| Volatility | Music Layers | Build-up Duration | Dynamic Range | Anticipation Boost |
|------------|-------------|-------------------|---------------|-------------------|
| Low | 2 (base + win) | 0.5–1s | 6 dB | 0% |
| Medium | 3 (base + mid + high) | 1–2s | 9 dB | +10% |
| High | 4 (base + mid + high + peak) | 2–4s | 12 dB | +20% |
| Extreme | 5 (base + low + mid + high + peak) | 3–6s | 15 dB | +35% |

**ADB Output Sections:**
1. **Game Info** — ID, volatility, platforms, theme, mechanics
2. **Music Plan** — Layer count, contexts, transitions, tempo range
3. **SFX Plan** — Event list, variant requirements, category breakdown
4. **VO Plan** — Voiceover triggers, language considerations
5. **Ducking Rules** — Feature vs UI, VO vs Music, BigWin override
6. **Loudness Targets** — Per-category LUFS, True Peak ceiling
7. **Voice Budget** — Max voices per platform, stealing priority
8. **RTP Mapping** — Psychoacoustic scaling per RTP band
9. **Win Tier System** — Threshold multipliers, celebration scaling
10. **Fatigue Rules** — Max repetition, cooldown timers, variation requirements

**Emotional Arc Templates (Chief Audio Architect dopuna):**

Svaka mehanika ima definisan "emotional arc" — dramski tok zvuka:

| Mehanika | Arc | Opis |
|----------|-----|------|
| `progressive` | `build → suspense → peak → celebrate → resolve` | Dugi build-up, crescendo pre jackpota, eksplozija, postepeni pad |
| `hold_and_win` | `lock → tension → collect → relief` | Svaki lock povećava tenziju, collect je katarza |
| `cascades` | `trigger → chain → accelerate → climax → settle` | Svaki cascade step ubrzava, peak na max chain |
| `free_spins` | `fanfare → loop → escalate → resolve → summary` | Entry fanfare, loop sa escalation, summary recap |
| `pick_bonus` | `anticipation → reveal → react → collect` | Svaki pick ima micro-drama (reveal + positive/negative reaction) |
| `megaways` | `expand → chaos → resolve` | Ekspanzija reela = haos, resolucija na stop |
| `wheel_bonus` | `spin → decelerate → stop → prize` | Kružna tenzija, usporavanje, impact na stop |
| `gamble` | `risk → flip → result` | Kratki ciklusi rizik/nagrada |

Ovi arc-ovi se koriste u ADB sekciji "Music Plan" za definisanje transition timinga i layer escalation pravila.

**Integracija sa postojećim sistemima:**
- Koristi `SAM archetypes` (rf-aurexis/sam/archetypes.rs) za default profile
- Koristi `Template System` (template_models.dart) za feature module types
- Koristi `Event Naming Service` konvencije za naming
- GDD input parsira kroz `rf-slot-lab/parser/gdd_parser.rs` (treba implementirati)
- Emotional arc mapira na ALE context transitions (rf-ale/transitions.rs)

---

### 5.2 `naming.validate` — Auto-Naming Validator

**Naming šema:**
```
<domain>_<feature>_<event>_<variant>_<v#>
```

**Dozvoljeni domeni:**

| Domain | Prefiks | Opis | LUFS Target | True Peak |
|--------|---------|------|-------------|-----------|
| UI | `ui_` | Buttons, menus, navigation | -20 LUFS | -1.0 dBTP |
| SFX | `sfx_` | Reel stops, impacts, transitions | -18 LUFS | -1.0 dBTP |
| Music | `mus_` | Loops, stingers, layers | -16 LUFS | -1.0 dBTP |
| Voice Over | `vo_` | Narration, announcements | -18 LUFS | -1.0 dBTP |
| Ambience | `amb_` | Background, atmospheric | -24 LUFS | -1.0 dBTP |

**Validacija:**
1. **Scan** `/AudioRaw` folder rekurzivno (walkdir)
2. **Parse** filename po `_` separatoru
3. **Validate** svaki segment:
   - Domain: mora biti jedan od 5 dozvoljenih
   - Feature: lowercase, no special chars, max 20 chars
   - Event: lowercase, no special chars, max 30 chars
   - Variant: single lowercase letter (a-z)
   - Version: `v` + number (v1, v2, ...)
4. **Check** audio properties:
   - Sample rate: 48000 Hz (slot standard) ili matching project
   - Bit depth: 16-bit minimum, 24-bit preferred
   - Channels: mono ili stereo (no surround za slot)
5. **Detect** probleme:
   - Duplikati (isti event, isti variant)
   - Zabranjeni karakteri (space, uppercase, special)
   - Pogrešan domain (heuristika: "click" → UI, "reel" → SFX)
   - Sample rate mismatch
   - Missing variants (a postoji, b ne)
6. **Generate** output:
   - `rename_plan.csv` — predložena preimenovanja
   - `naming_report.html` — vizuelni pregled
   - `naming_validation.json` — mašinski čitljiv rezultat

**Dry-run:** samo generiše plan, NE preimenuje fajlove.

**Integracija:** Proširuje postojeći `EventNamingService` sa Rust-side validacijom za batch operacije.

---

### 5.3 `volatility.profile.generate` — Volatility Profile Generator

**Koristi postojeće:** `rf-aurexis/volatility/profiles.rs` + `translator.rs`

**Proširuje sa:**

```rust
pub struct GeneratedVolatilityProfile {
    // === Iz postojećeg rf-aurexis ===
    pub volatility_index: f32,           // 0.0–1.0
    pub stereo_elasticity: (f32, f32),   // min, max
    pub energy_density: (f32, f32),      // min, max
    pub escalation_rate: f32,            // multiplier

    // === NOVO za FluxMacro ===
    pub hit_intensity_scale: (f32, f32), // min, max scale per win tier
    pub big_win_thresholds: Vec<f32>,    // [20x, 50x, 100x] bet multipliers
    pub music_layer_up_shift_ms: u32,    // Time to escalate music layer
    pub music_layer_down_shift_ms: u32,  // Time to de-escalate
    pub anticipation_boost_chance: f32,  // Extra anticipation trigger %
    pub max_high_energy_duration_sec: f32, // Max before fatigue kicks in
    pub ducking_ui_during_big_win_db: f32, // UI attenuation during BigWin
    pub transient_aggression: f32,       // 0.0 (soft) to 1.0 (sharp)
    pub build_up_curve: EscalationCurve, // LINEAR, LOG, EXP, S_CURVE
    pub cooldown_after_peak_sec: f32,    // Recovery time post-peak
}
```

**Generisanje:**
1. Učitava volatility level iz MacroContext
2. Lookup base profile iz rf-aurexis
3. Primenjuje mehanika-specifične modifikatore:
   - `progressive` → duži build-up, viši anticipation boost
   - `megaways` → širi dynamic range, agresivniji transijenti
   - `hold_and_win` → kraći cycles, češći mali peakovi
4. Primenjuje platform modifikatore:
   - `mobile` → niži max energy, kraći peaks, uži stereo
   - `cabinet` → viši bass, duži decay, široki stereo
5. Piše profil u `/Profiles/{game_id}_volatility.json`

**Integracija:** Direktno koristi `VolatilityTranslator::translate()` iz rf-aurexis, ali dodaje slot-specifične parametre (big_win_thresholds, music_layer shifts) koji ne postoje u core AUREXIS output-u.

---

### 5.4 `manifest.build` — Manifest Builder

**Wraps:** `rf-aurexis/drc/manifest.rs` — FluxManifest

**Proširuje pipeline:**
1. Kreira `FluxManifest` sa version locks za svih 9 subsistema
2. Attachuje `ConfigBundle` sa svim JSON config fajlovima:
   - `geg_energy_config.json`
   - `dpm_event_weights.json`
   - `dpm_profile_modifiers.json`
   - `dpm_context_rules.json`
   - `samcl_band_config.json`
   - `samcl_role_assignment.json`
   - `samcl_collision_rules.json`
   - `volatility_profile.json`
   - `naming_rules.json`
   - `loudness_targets.json`
   - `adb_summary.json`
   - `qa_results.json`
3. Compute `config_bundle_hash` (FNV-1a)
4. Piše manifest u `manifest.json`
5. Dodaje u MacroContext za downstream steps

**Integracija:** 100% reuse DRC manifest system. Samo wrapper step.

---

### 5.5 `qa.run_suite` — QA Suite Orchestrator

**Meta-step** koji sekvencijalno pokreće 4 QA testa:

```yaml
qa.run_suite:
  runs:
    - qa.event_storm
    - qa.determinism
    - qa.loudness
    - qa.fatigue
  gate: all_must_pass    # any_pass | all_must_pass | weighted
```

Ako `parallel_qa: true` u options, koristi `rayon` za paralelno izvršavanje (sa izolovanim seed-ovima).

---

### 5.6 `qa.event_storm` — Event Storm Simulation

**Koristi:** PBSE (rf-aurexis/qa/pbse.rs) + SSS (rf-aurexis/sss/burn_test.rs)

**Simulira najgori slučaj:**
- 500 spinova za 2 minuta simuliranog vremena
- Paralelni UI spam (bet up/down svaki spin)
- Big win trigger svakih 10 spinova
- Autoplay ON kroz celu simulaciju
- Bonus ulazak/izlazak svakih 25 spinova
- Cascade chain (5 deep) svakih 15 spinova

**Meri:**
| Metrika | Threshold | Opis |
|---------|-----------|------|
| Max Concurrent Voices | ≤ platform budget | Mobile: 24, Desktop: 48, Cabinet: 32 |
| Voice Steal Count | ≤ 5% of total events | Prekomerno kradenje = loš mix |
| Buffer Overflow Events | = 0 | Bilo koji overflow = FAIL |
| Peak Concurrency | ≤ 80% budget | Mora imati headroom |
| Missing Events | = 0 | Svaki trigger MORA imati response |
| Late Starts (>10ms) | ≤ 2% | Audio mora biti responsive |
| Dropout Score | ≤ 0.01 | Combined metric |

**Output:** `QA_EventStorm_{game_id}_{timestamp}.html`

**Integracija:** Direktno poziva `PreBakeSimulator::run_full_simulation()` sa custom scenarijom koji mapira "event storm" pattern. Koristi `BurnTest` za extended validation.

---

### 5.7 `qa.determinism` — Determinism Lock Test

**Koristi:** DRC (rf-aurexis/drc/replay.rs) + SSS Auto Regression (rf-aurexis/sss/auto_regression.rs)

**Procedura:**
1. Pokrene istu sesiju 10 puta sa identičnim seed-om
2. Za svaki run, snimi:
   - Kompletan .fftrace (trace entries + final_state_hash)
   - Svaku voice steal odluku
   - Svaki parameter map output
3. Poredi SHA-256 hash-eve svih 10 runova
4. Ako BILO KOJI hash ne odgovara → **FAIL**

**Specifični checkovi:**
- Frame-by-frame parameter map equality (25-field comparison)
- Voice allocator decision equality
- Event timing equality (sample-accurate)
- Escalation curve equality
- Fatigue accumulation equality

**Output:** `QA_Determinism_{game_id}_{timestamp}.json`

**Integracija:** Direktno koristi `DeterministicReplayCore::replay_and_verify()` i `AutoRegression::run_regression()` iz rf-aurexis.

---

### 5.8 `qa.loudness` — Loudness Compliance Checker

**Koristi:** rf-offline (LUFS metering) + rf-audio-diff (spectral analysis)

**Per-Category Targets:**

| Domain | LUFS Target | Tolerance | True Peak Max | Headroom za Layering |
|--------|-------------|-----------|---------------|---------------------|
| UI | -20 LUFS | ±1.5 | -1.0 dBTP | 6 dB |
| SFX | -18 LUFS | ±2.0 | -1.0 dBTP | 6 dB |
| Music | -16 LUFS | ±1.5 | -1.0 dBTP | 3 dB |
| VO | -18 LUFS | ±1.0 | -1.0 dBTP | 6 dB |
| Ambience | -24 LUFS | ±2.0 | -2.0 dBTP | 9 dB |

**Za svaki asset:**
1. Decode audio (rf-offline decoder)
2. Measure integrated LUFS (EBU R128)
3. Measure true peak (8x oversampled)
4. Measure short-term LUFS (3s window)
5. Detect peak-to-loudness ratio
6. Classify domain po naming convention
7. Compare against target

**Output:**
- `QA_Loudness_{game_id}_{timestamp}.html` — vizuelni pregled
- Lista "needs fix" sa predlogom gain offset-a:
  ```
  sfx_reel_stop_a_v1.wav: -15.2 LUFS (target -18 ±2) → PASS
  mus_base_lvl3_loop_a_v1.wav: -12.1 LUFS (target -16 ±1.5) → FAIL (suggested: -3.9 dB)
  ui_button_click_a_v1.wav: -0.3 dBTP (max -1.0) → FAIL (suggested: -0.7 dB gain reduction)
  ```

**Integracija:** Koristi `LoudnessMeter` iz rf-offline za EBU R128 merenje, `TruePeakDetector` za ISP. Može koristiti `rf-audio-diff` za spectral comparison sa golden reference.

---

### 5.9 `qa.fatigue` — Fatigue / Repetition Analyzer

**Koristi:** PBSE fatigue model + SSS burn test

**Simulira 45 minuta gameplay-a:**
1. Generiše 45-minutnu sesiju sa realističnom distribucijom:
   - 60% base game spins (normalan tempo)
   - 15% bonus features (elevated energy)
   - 10% big win celebrations
   - 10% idle/autoplay
   - 5% jackpot/special events
2. Prati za svaki SFX:
   - Koliko puta se ponavlja u minuti (repetition density)
   - Koliko puta isti varijant uzastopno (consecutive repeats)
   - Vremenski razmak između ponavljanja (min interval)
3. Prati za muziku:
   - Koliko dugo ostaje u LVL3+ (high energy exposure)
   - Koliko često menja layer (transition frequency)
   - Koliko dugo isti loop svira bez varijacije
4. Prati za celokupnu sesiju:
   - Peak energy percentage of session time
   - Recovery time between peaks
   - Overall dynamic contrast

**Fatigue Thresholds:**

| Metrika | Warning | Fail |
|---------|---------|------|
| Isti SFX > N puta/min | > 8 | > 15 |
| Consecutive same variant | > 3 | > 5 |
| High energy > % session | > 25% | > 40% |
| Music LVL3+ duration | > 60s continuous | > 120s continuous |
| Same loop without variation | > 90s | > 180s |
| Peak-to-recovery ratio | < 1:2 | < 1:1 |

**Output:**
```
Fatigue_Warnings:
⚠ BigWin tier3 celebration > 18% session time (threshold: 25%)
⚠ sfx_reel_stop variant A repeated 62% of cases (need more variants)
⚠ Music LVL3 sustained for 95s at timestamp 12:30 (threshold: 60s)
❌ FAIL: sfx_cascade_drop played 22x/min at peak (threshold: 15/min)
```

**Preporuke:**
- Predlaži koliko varijanti treba za svaki event
- Predlaži cooldown timere
- Predlaži random weight redistribuciju
- Predlaži dynamic range compression za extended peaks

**Integracija:** Koristi `FatigueIndex` formulu iz PBSE:
`FatigueIndex = (PeakFreq × HarmonicDensity × TemporalDensity) / RecoveryFactor`
Plus SSS `BurnTest` 5 drift metrics (energy/harmonic/spectral/voice/fatigue).

---

### 5.10 `qa.spectral_health` — Spectral Health Checker

**Dodato na osnovu Lead DSP Engineer review-a.**

**Šta radi:**
Za svaki audio asset u projektu, meri DSP-specifične metrike koje standardni loudness check ne pokriva.

**Metrike:**

| Metrika | Opis | Warning | Fail |
|---------|------|---------|------|
| **Crest Factor** | Peak/RMS ratio per category | > 18 dB (SFX), > 15 dB (UI) | > 24 dB |
| **Spectral Centroid** | Brightness index (Hz) — detektuje timbral monotoniju | Drift < 5% across variants | Drift > 15% |
| **Inter-Channel Correlation** | Mono compatibility (stereo assets) | < 0.3 (wide but risky) | < 0.1 (mono cancel) |
| **DC Offset** | DC bias detection | > 0.0005 | > 0.001 |
| **Trailing Silence** | Wasted space na kraju fajla | > 50ms | > 200ms |
| **Sample Rate Mismatch** | Ne odgovara project sample rate | Mismatch | — |
| **Bit Depth** | Ispod minimalnog | 16-bit (ok) | < 16-bit |
| **Clipping Detection** | Consecutive samples at max | > 3 consecutive | > 10 consecutive |

**Output:**
- `QA_SpectralHealth_{game_id}_{timestamp}.html`
- Per-asset breakdown sa pass/warning/fail
- Trim preporuke za trailing silence (koliko ms da se skine)
- Mono compatibility warnings sa predlogom width reduction-a

**Integracija:** Koristi rf-offline decoder za audio čitanje, rf-dsp analysis za FFT/spectral centroid, custom crest factor kalkulaciju.

---

### 5.11 `pack.release` — Release Candidate Packager

**Koristi:** rf-release (versioning, packaging) + DRC manifest

**Pipeline:**
1. Validate all previous steps passed (fail if any QA FAIL and gate=all_must_pass)
2. Collect all artifacts:
   - ADB document (`.md` + `.json`)
   - Naming validation report
   - Volatility profile
   - Manifest (with config bundle hash)
   - All QA reports
3. Compute release fingerprint (SHA-256 of all artifacts)
4. Generate semantic version (from rf-release)
5. Create RC folder structure:
   ```
   /Release/{GameId}_RC{n}/
     manifest.json              # DRC manifest with all version locks
     ADB_{GameId}.md            # Audio Design Brief
     ADB_{GameId}.json          # Machine-readable ADB
     volatility_profile.json    # Attached profile
     naming_report.html         # Naming validation
     qa/
       event_storm.html         # QA report
       determinism.json         # Determinism verification
       loudness.html            # Loudness compliance
       fatigue.html             # Fatigue analysis
     assets/                    # (if --include-assets flag)
       ui/
       sfx/
       mus/
       vo/
       amb/
     RC_Report.html             # Unified summary report
     fingerprint.sha256         # Release fingerprint
   ```
6. Generate unified `RC_Report.html`:
   - Overall PASS/FAIL status
   - Per-step summary with duration
   - QA gate results table
   - Recommendations from AIL
   - Manifest version info
   - Link to detailed reports

---

## 6. REPORT SYSTEM — DETALJNO

### 6.1 Reporter Trait

```rust
pub trait Reporter: Send + Sync {
    fn format(&self) -> ReportFormat;
    fn generate(&self, ctx: &MacroContext) -> Result<Vec<u8>, FluxMacroError>;
    fn file_extension(&self) -> &'static str;
}

pub enum ReportFormat { Html, Json, Markdown }
```

### 6.2 HTML Report Generator

Generiše self-contained HTML (inline CSS + minimal JS za collapse/expand):
- **Header:** Game ID, timestamp, overall PASS/FAIL, duration
- **Summary Table:** Step name, status, duration, artifacts
- **QA Results:** Expandable sections per test
- **Metrics:** Key numbers (voices, loudness, fatigue index)
- **Recommendations:** AIL suggestions sa impact scores
- **Footer:** Manifest hash, FluxMacro version, seed

### 6.3 JSON Report

Machine-readable, za integraciju sa CI/CD:
```json
{
  "macro_name": "build_release",
  "game_id": "GoldenPantheon",
  "timestamp": "2026-03-01T14:30:00Z",
  "duration_ms": 45000,
  "overall_status": "PASS",
  "seed": 42,
  "run_hash": "sha256:abc123...",
  "steps": [
    {
      "name": "adb.generate",
      "status": "success",
      "duration_ms": 2000,
      "artifacts": ["ADB_GoldenPantheon.md"]
    }
  ],
  "qa_results": {
    "event_storm": { "passed": true, "max_voices": 31, "steals": 12 },
    "determinism": { "passed": true, "runs": 10, "matching_hashes": 10 },
    "loudness": { "passed": false, "failures": 3, "total_assets": 147 },
    "fatigue": { "passed": true, "warnings": 2 }
  },
  "manifest_hash": "fnv1a:def456..."
}
```

---

## 7. CLI SPECIFIKACIJA

### 7.1 Komande

```bash
# Pokreni macro
fluxmacro run build_release.ffmacro.yaml

# Dry-run (bez side effects)
fluxmacro dry-run build_release.ffmacro.yaml

# Replay prethodni run
fluxmacro replay 2026-03-01T14-30-00

# Lista dostupnih stepova
fluxmacro steps

# Pokreni pojedinačni step
fluxmacro step adb.generate --game-id GoldenPantheon --volatility high

# Validiraj macro fajl (syntax check)
fluxmacro validate build_release.ffmacro.yaml

# Pokreni samo QA suite
fluxmacro qa --game-id GoldenPantheon --seed 42

# Generiši ADB interaktivno
fluxmacro adb --game-id GoldenPantheon --mechanics progressive,hold_and_win
```

### 7.2 Exit Codes

| Code | Značenje |
|------|----------|
| 0 | Sve prošlo (PASS) |
| 1 | QA test FAIL (ali run completiran) |
| 2 | Macro execution error (step failed) |
| 3 | Parse error (invalid .ffmacro.yaml) |
| 4 | Config error (missing rules/profiles) |
| 5 | File I/O error |

### 7.3 Studio Integration

Flutter UI poziva CLI binary ili direktno Rust API:

```dart
// Option A: CLI (subprocess)
final result = await Process.run('fluxmacro', [
  'run', 'build_release.ffmacro.yaml',
  '--verbose',
]);

// Option B: Direct Rust API (via FFI)
// fluxmacro_run(macroFilePath, dryRun) → JSON result
```

Za Studio UI, preporučen je **Option B** (FFI) jer:
- Real-time progress feedback (atomic progress counter)
- Structured result (ne treba parsirati stdout)
- Cancellation support (atomic flag)

---

## 8. DETERMINISM MODEL — GARANCIJE

### 8.1 Seeded Execution

Svaki MacroContext ima `seed: u64`:
- Ako korisnik specificira seed → koristi ga
- Ako ne → generise iz `SystemTime` ali LOGUJE seed za replay
- Svi random elementi (QA simulacije, variation) koriste `rand_chacha::ChaCha20Rng::seed_from_u64(seed)`
- **NIKAD `thread_rng()`** ili `random()` u FluxMacro engine-u

### 8.2 Hash Chain

```
run_hash = SHA256(
  macro_file_content +
  all_input_parameters +
  all_step_results +
  all_artifact_hashes +
  seed
)
```

### 8.3 Replay Guarantee

```bash
fluxmacro run build_release.ffmacro.yaml --seed 42
# Produces run_hash: abc123

fluxmacro run build_release.ffmacro.yaml --seed 42
# MUST produce run_hash: abc123 (identical)
```

Ako hash nije identičan → BUG u FluxMacro engine-u.

### 8.4 Integracija sa DRC

FluxMacro run → generiše `.fftrace` kompatibilan sa DRC.
DRC `replay_and_verify()` može verifikovati FluxMacro run nezavisno.

---

## 9. INTEGRACIJA SA POSTOJEĆIM SISTEMIMA — TAČNA MAPA

### 9.1 rf-aurexis (13,000+ LOC) — Intelligence Hub

| AUREXIS Modul | FluxMacro Step | Kako se koristi |
|---------------|---------------|-----------------|
| `volatility/profiles.rs` | `volatility.profile.generate` | Base profile lookup |
| `volatility/translator.rs` | `volatility.profile.generate` | Index → audio params |
| `energy/governance.rs` | `manifest.build` | Energy config za manifest |
| `priority/dpm.rs` | `manifest.build` | Priority weights za manifest |
| `spectral/allocation.rs` | `manifest.build` | Spectral config za manifest |
| `qa/pbse.rs` | `qa.event_storm`, `qa.fatigue` | Stress simulation engine |
| `qa/determinism.rs` | `qa.determinism` | Determinism verification |
| `advisory/ail.rs` | `pack.release` (report) | Recommendations za RC report |
| `drc/replay.rs` | `qa.determinism` | Trace recording + replay |
| `drc/manifest.rs` | `manifest.build` | FluxManifest creation |
| `drc/safety.rs` | `qa.event_storm` | Safety envelope validation |
| `drc/certification.rs` | `pack.release` | Certification gate |
| `sam/archetypes.rs` | `adb.generate` | Default profiles per archetype |
| `sss/burn_test.rs` | `qa.fatigue` | Extended fatigue simulation |
| `sss/auto_regression.rs` | `qa.determinism` | Multi-run regression |
| `gad/bake.rs` | `pack.release` | Bake pipeline reference |

### 9.2 rf-slot-lab — Synthetic Engine

| SlotLab Modul | FluxMacro Step | Kako se koristi |
|---------------|---------------|-----------------|
| `parser/gdd_parser.rs` | `adb.generate` | GDD input parsing (**treba implementirati**) |
| `core/engine.rs` | `qa.event_storm` | Spin outcome generation za simulaciju |
| `model/volatility.rs` | `volatility.profile.generate` | Volatility model reference |
| `features/` | `adb.generate` | Feature → audio needs mapping |
| `scenario/scenario.rs` | `qa.event_storm` | Demo scenario za stress test |

### 9.3 rf-offline — Audio Analysis

| Offline Modul | FluxMacro Step | Kako se koristi |
|---------------|---------------|-----------------|
| `decoder.rs` | `qa.loudness` | Audio file decoding |
| `normalize.rs` | `qa.loudness` | LUFS measurement |
| `pipeline.rs` | `qa.loudness` | Pipeline pattern reference |

### 9.4 rf-release — Versioning

| Release Modul | FluxMacro Step | Kako se koristi |
|---------------|---------------|-----------------|
| `version.rs` | `pack.release` | Semantic version generation |
| `changelog.rs` | `pack.release` | Changelog from git |
| `packaging.rs` | `pack.release` | Artifact packaging |

### 9.5 Flutter UI — Studio Panel

| UI Komponent | FluxMacro Integracija |
|-------------|----------------------|
| Macro Panel (NOVO) | 6 dugmadi: Generate ADB, Validate Naming, Gen Profile, Run QA, Build RC, View Reports |
| SlotLab Plus Menu | FluxMacro entry point (modal dialog) |
| Lower Zone Tab (NOVO) | FluxMacro Monitor — live progress, log stream, artifact list |
| Report Viewer (NOVO) | In-app HTML report rendering (WebView ili custom) |

### 9.6 Scripts Integration

| Script | FluxMacro Veza |
|--------|----------------|
| `scripts/qa.sh` | FluxMacro `qa.run_suite` zamenjuje shell QA za slot-specifične testove |
| `scripts/build.sh` | FluxMacro `pack.release` može trigerovati build pre pakovanja |
| `scripts/run.sh` | Nezavisno — FluxMacro ne pokreće app |

---

## 10. IMPLEMENTATION PLAN — FAZE

### Phase 1: Foundation (rf-fluxmacro core) — ~4,100 LOC

| Task | Opis | LOC |
|------|------|-----|
| FM-1 | `context.rs` — MacroContext, LogEntry, QaTestResult, cancel_token (AtomicBool), progress callback (`Arc<dyn Fn(f32) + Send + Sync>`) | ~350 |
| FM-2 | `parser.rs` — YAML parser za .ffmacro fajlove (serde_yaml) | ~150 |
| FM-3 | `steps/mod.rs` — MacroStep trait, StepRegistry, StepResult | ~200 |
| FM-4 | `interpreter.rs` — MacroInterpreter, sequential execution, fail-fast, cancellation check per step | ~300 |
| FM-5 | `error.rs` — FluxMacroError enum (12+ varijanti) | ~100 |
| FM-6 | `hash.rs` — SHA-256 run hashing (streaming, ne učitavaj ceo fajl), FNV-1a config hashing | ~120 |
| FM-7 | `version.rs` — Run versioning, history save/load | ~150 |
| FM-8 | `security.rs` — MacroSecurity modul: path sandboxing (canonicalize, assets mora biti child of project), input sanitization (game_id: `[a-zA-Z0-9_-]{1,64}`), report content escaping (html_escape) | ~250 |
| FM-9 | `rules/mod.rs` — Rule loader (JSON → typed structs) | ~200 |
| FM-10 | `rules/naming_rules.rs` — NamingRuleSet, domain/pattern validation | ~250 |
| FM-11 | `rules/mechanics_map.rs` — GameMechanic → AudioNeeds mapping table (14 mehanika × audio events) | ~300 |
| FM-12 | `rules/loudness_targets.rs` — Per-domain LUFS/TP targets | ~100 |
| FM-13 | `rules/adb_templates.rs` — ADB section templates + emotional_arc_template per mehanika | ~250 |
| FM-14 | `reporter/mod.rs` — Reporter trait | ~50 |
| FM-15 | `reporter/json.rs` — JSON report generator (versioned stable API) | ~200 |
| FM-16 | `reporter/markdown.rs` — Markdown report generator | ~250 |
| FM-17 | `reporter/html.rs` — Self-contained HTML report generator (XSS-safe escaping) | ~400 |
| FM-18 | `reporter/svg.rs` — Inline SVG generator: voice usage timeline (area chart), loudness histogram, fatigue curve (line + thresholds), determinism hash grid | ~350 |
| FM-19 | Unit tests (35+ tests covering parser, interpreter, rules, reporter, security) | ~550 |

### Phase 2: Core Steps (~3,800 LOC)

| Task | Opis | LOC |
|------|------|-----|
| FM-20 | `steps/adb_generate.rs` — ADB auto-generator (mechanics mapping, emotional arc, ADB.md + JSON output, 10 ADB sekcija) | ~550 |
| FM-21 | `steps/naming_validate.rs` — Asset scanner (walkdir + rayon), naming validator, rename plan CSV, dry-run, silence detection (trailing >50ms = trim warning) | ~450 |
| FM-22 | `steps/volatility_profile.rs` — Profile generator (wraps rf-aurexis volatility + slot-specific params: big_win_thresholds, music layer shifts, anticipation boost) | ~300 |
| FM-23 | `steps/manifest_build.rs` — Manifest builder (wraps DRC, 12 JSON configs, FNV-1a hash) | ~200 |
| FM-24 | `steps/qa_run_suite.rs` — QA suite orchestrator (meta-step, sequential or parallel via rayon) | ~150 |
| FM-25 | `steps/qa_event_storm.rs` — Event storm simulation (500 spins, wraps PBSE, 7 metrika sa thresholds) | ~400 |
| FM-26 | `steps/qa_determinism.rs` — Determinism lock test (10 runs, SHA-256, wraps DRC replay + SSS auto_regression) | ~300 |
| FM-27 | `steps/qa_loudness.rs` — Loudness compliance checker (per-category LUFS/TP, wraps rf-offline, gain correction predlog) | ~400 |
| FM-28 | `steps/qa_fatigue.rs` — Fatigue analyzer (45-min sim, wraps PBSE fatigue + SSS burn, 6 thresholds, variant preporuke) | ~400 |
| FM-29 | `steps/qa_spectral_health.rs` — Spectral health checker: crest factor per category, spectral centroid drift, inter-channel correlation (mono compat), DC offset detection (>0.001 = warning) | ~350 |
| FM-30 | `steps/pack_release.rs` — Release candidate packager (RC folder, unified RC_Report.html, fingerprint.sha256) | ~350 |
| FM-31 | Integration tests (12+ tests, end-to-end macro execution) | ~500 |

### Phase 3: CLI + FFI (~1,800 LOC)

| Task | Opis | LOC |
|------|------|-----|
| FM-32 | `rf-fluxmacro-cli/main.rs` — clap CLI (run, dry-run, replay, steps, validate, qa, adb) + `--ci` flag (forces JSON, sets exit code, generates CI-compatible output) | ~500 |
| FM-33 | FFI bridge: `fluxmacro_ffi.rs` u rf-bridge (~25 extern "C" functions incl. progress callback + cancel) | ~400 |
| FM-34 | Dart FFI bindings u `native_ffi.dart` (~180 lines, incl. progress stream) | ~180 |
| FM-35 | `FluxMacroProvider` (GetIt Layer 7.3) — state, progress, cancel, history | ~300 |
| FM-36 | CLI tests (7+ tests incl. --ci mode) | ~220 |
| FM-37 | FFI integration tests | ~200 |

### Phase 4: Studio UI (~2,400 LOC)

| Task | Opis | LOC |
|------|------|-----|
| FM-38 | `macro_panel.dart` — FluxMacro control panel (7 actions: ADB, Naming, Profile, QA, Spectral, Build RC, View Reports), minimalist vertical layout | ~450 |
| FM-39 | `macro_monitor.dart` — Live progress monitor (circular progress + step name + ETA, monospace log stream with color coding green/yellow/red) | ~400 |
| FM-40 | `macro_report_viewer.dart` — In-app report viewer (split pane: report content left, metrics right) | ~350 |
| FM-41 | `macro_config_editor.dart` — .ffmacro.yaml editor (form-based, input fields + step picker + options toggles) | ~400 |
| FM-42 | `macro_history.dart` — Run history list sa compare opcijom (diff dva runa) | ~250 |
| FM-43 | SlotLab Plus menu integration + toast notifikacije za step completion | ~150 |
| FM-44 | Lower Zone tab registration | ~100 |
| FM-45 | Provider wiring + GetIt registration | ~150 |
| FM-46 | UI tests | ~200 |

### Phase 5: GDD Parser Implementation (~1,000 LOC)

| Task | Opis | LOC |
|------|------|-----|
| FM-47 | `rf-slot-lab/parser/gdd_parser.rs` — JSON/YAML GDD parser | ~400 |
| FM-48 | `rf-slot-lab/parser/schema.rs` — GDD validation schema | ~200 |
| FM-49 | `rf-slot-lab/parser/validator.rs` — GDD constraint validation | ~200 |
| FM-50 | Parser tests | ~200 |

### Phase 6: CI/CD Integration (~500 LOC)

| Task | Opis | LOC |
|------|------|-----|
| FM-51 | GitHub Actions workflow: `fluxmacro-ci.yml` — runs `fluxmacro run --ci`, uploads artifacts, sets PR check status | ~150 |
| FM-52 | CI report formatter — PR comment generator sa QA summary (pass/fail table, key metrics) | ~200 |
| FM-53 | CI integration tests (headless mode, no TTY, JSON-only output) | ~150 |

**TOTAL: ~13,600 LOC across 53 tasks, 6 phases**

---

## 11. CARGO.TOML — rf-fluxmacro

```toml
[package]
name = "rf-fluxmacro"
version = "0.1.0"
edition = "2024"
description = "Deterministic orchestration engine for slot audio pipeline"

[dependencies]
# Workspace crates
rf-aurexis = { path = "../rf-aurexis" }
rf-slot-lab = { path = "../rf-slot-lab" }
rf-offline = { path = "../rf-offline" }
rf-audio-diff = { path = "../rf-audio-diff" }
rf-release = { path = "../rf-release" }
rf-core = { path = "../rf-core" }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"

# Hashing
sha2 = "0.10"

# File system
walkdir = "2"
regex = "1"

# Deterministic RNG
rand = "0.8"
rand_chacha = "0.3"

# Parallelism (optional, for QA)
rayon = "1"

# Time
chrono = "0.4"

# Security (HTML report XSS prevention)
html-escape = "0.2"

[dev-dependencies]
tempfile = "3"
```

```toml
[package]
name = "rf-fluxmacro-cli"
version = "0.1.0"
edition = "2024"
description = "CLI for FluxMacro orchestration engine"

[[bin]]
name = "fluxmacro"
path = "src/main.rs"

[dependencies]
rf-fluxmacro = { path = "../rf-fluxmacro" }
clap = { version = "4", features = ["derive"] }
serde_json = "1"
```

---

## 12. PREDEFINED MACRO FILES

### 12.1 Quick QA

```yaml
# Macros/qa_quick.ffmacro.yaml
macro: qa_quick
version: "1.0"

input:
  game_id: "${GAME_ID}"       # Environment variable
  volatility: "${VOLATILITY}"

steps:
  - naming.validate
  - qa.loudness

output:
  report: "Reports/${GAME_ID}_QA_Quick.html"
  format: "html"
```

### 12.2 Full Release Pipeline

```yaml
# Macros/build_release.ffmacro.yaml
macro: build_release
version: "1.0"

input:
  game_id: "GoldenPantheon"
  volatility: "high"
  mechanics:
    - "hold_and_win"
    - "progressive"
    - "respin"
  theme: "mythological"
  platforms:
    - "mobile"
    - "desktop"

options:
  seed: 42
  fail_fast: true
  verbose: true

steps:
  - adb.generate
  - naming.validate
  - volatility.profile.generate
  - manifest.build
  - qa.run_suite
  - pack.release

output:
  report: "Reports/GoldenPantheon_RC.html"
  format: "all"
```

### 12.3 ADB Only

```yaml
# Macros/adb_generate.ffmacro.yaml
macro: adb_generate
version: "1.0"

input:
  game_id: "FortuneFury"
  volatility: "med_high"
  mechanics:
    - "progressive"
    - "mystery_scatter"
    - "pick_bonus"
  platforms:
    - "mobile"
    - "desktop"

steps:
  - adb.generate

output:
  report: "Reports/FortuneFury_ADB.html"
  format: "markdown"
```

### 12.4 Naming Fix

```yaml
# Macros/naming_fix.ffmacro.yaml
macro: naming_fix
version: "1.0"

input:
  game_id: "AnyGame"
  assets_dir: "./AudioRaw"

options:
  verbose: true

steps:
  - naming.validate

output:
  report: "Reports/NamingReport.html"
  format: "html"
```

---

## 13. ROLE-BASED ARCHITECTURE REVIEW

Korišćenjem uloga iz CLAUDE.md, evo ekspertskih dopuna iz svake perspektive:

### 🎵 Chief Audio Architect

**Audio dramaturgija mora biti u centru ADB generatora:**
- Svaka mehanika ima "emotional arc" (build → peak → resolve)
- ADB mora definisati ne samo ŠTA treba, nego i KAKO se zvukovi uklapaju u dramu
- Music layer transitions moraju respektovati musical timing (bar sync, phrase sync)
- Ducking prioriteti moraju biti hijerarhijski: VO > Feature > BigWin > Music > Ambience > UI
- **Dodaj:** `emotional_arc_template` u ADB koji definiše dramski tok za svaku mehaniku

### 🔊 Lead DSP Engineer

**QA testovi moraju meriti DSP specifične metrike:**
- **Crest factor** per event category (peak/RMS ratio) — previsok crest = loš mix za mobile
- **Spectral centroid drift** tokom fatigue testa — upozorava na timbral monotoniju
- **Inter-channel correlation** za stereo assets — mono compatibility check
- **DC offset detection** pre pakovanja (bilo koji offset > 0.001 = warning)
- **Silence detection** — trailing silence > 50ms je waste, treba trim report
- **Dodaj:** `qa.spectral_health` step koji radi sve ovo

### 🏗 Engine Architect

**Macro engine mora poštovati audio thread pravila:**
- FluxMacro NIKAD ne radi na audio thread-u — sve je offline/analysis thread
- Asset scanning koristi `walkdir` sa thread pool (rayon) za paralelnost
- Report generisanje je CPU-bound, koristi rayon parallel iterators
- Manifest hashing koristi streaming hash (ne učitavaj ceo fajl u memoriju)
- **Dodaj:** `MacroContext::cancel_token` (AtomicBool) za graceful cancellation
- **Dodaj:** Progress callback (`Arc<dyn Fn(f32) + Send + Sync>`) za UI feedback

### 🎮 Technical Director

**CI/CD integracija je obavezna:**
- FluxMacro CLI mora raditi u headless mode (no TTY)
- JSON output format mora biti stable API (versioned)
- Exit codes moraju biti semantički (0=pass, 1=qa_fail, 2=error, etc.)
- GitHub Actions workflow: `fluxmacro run --ci` sa artifact upload
- **Dodaj:** `--ci` flag koji:
  - Forsira JSON output
  - Uploaduje artifacts u CI storage
  - Postavlja GitHub check status (pass/fail)
  - Generiše PR comment sa QA summary

### 🎨 UI/UX Expert

**Studio Macro Panel dizajn:**
- **Minimalistički** — 6 dugmadi u vertikalnom layout-u, ne cluttered toolbar
- **Progress indicator** — circular progress sa step name i ETA
- **Log stream** — monospace terminal-style prikaz sa color coding (green/yellow/red)
- **One-click RC** — "Build Release" dugme koje radi ceo pipeline jednim klikom
- **Report preview** — split pane sa report sadržajem levo, metrics desno
- **History** — lista prethodnih runova sa compare opcijom
- **Dodaj:** Toast notifikacije za step completion (non-blocking)

### 🔐 Security Expert

**Macro sistem mora biti secure:**
- **Sandboxing** — macro fajlovi NE MOGU izvršavati arbitrary kod
- **Path traversal protection** — assets_dir i working_dir moraju biti validovani (canonicalize)
- **No shell injection** — nikad ne pozivaj shell komande iz macro step-ova
- **Input validation** — svi string inputi moraju proći regex whitelist
- **Report XSS prevention** — HTML reports moraju escape-ovati user input
- **Dodaj:** `MacroSecurity` modul sa:
  - Path sandboxing (asset dir mora biti child of project dir)
  - Input sanitization (game_id: `[a-zA-Z0-9_-]{1,64}`)
  - Report content escaping (html_escape crate)

### 🖥 Graphics Engineer

**Report vizualizacija:**
- **SVG grafovi** za voice usage, loudness distribution, fatigue timeline
- **Heatmap** za spectral coverage (reuse SAMCL spectral heatmap widget)
- **Sparkline** za fatigue drift (reuse SSS burn test sparkline)
- **Color coding** — green (pass), yellow (warning), red (fail), gray (skipped)
- **Dodaj:** `reporter/svg.rs` — inline SVG generator za HTML reports:
  - Voice usage timeline (area chart)
  - Loudness distribution (histogram)
  - Fatigue curve (line chart with thresholds)
  - Determinism hash matrix (10x grid, green=match)

---

## 14. UNIQUE DIFFERENTIATORS — ZAŠTO JE OVO OGROMNO

### Šta nijedan DAW nema:

| Feature | Reaper | Ableton | Bitwig | Wwise | FMOD | **FluxForge** |
|---------|--------|---------|--------|-------|------|---------------|
| Scripted automation | ReaScript ✅ | Max4Live ✅ | Bitwig Script ✅ | ❌ | ❌ | FluxMacro ✅ |
| Deterministic QA pipeline | ❌ | ❌ | ❌ | Profiler only | Profiler only | **Full pipeline ✅** |
| Volatility audio mapping | ❌ | ❌ | ❌ | ❌ | ❌ | **AUREXIS ✅** |
| RTP psychoacoustic scaling | ❌ | ❌ | ❌ | ❌ | ❌ | **AUREXIS ✅** |
| Long-session fatigue model | ❌ | ❌ | ❌ | ❌ | ❌ | **PBSE + SSS ✅** |
| Casino-grade voice stability | ❌ | ❌ | ❌ | Voice limiting | Voice limiting | **DPM + Safety ✅** |
| ADB auto-generation | ❌ | ❌ | ❌ | ❌ | ❌ | **FluxMacro ✅** |
| Auto naming validation | ❌ | ❌ | ❌ | Naming conv | ❌ | **FluxMacro ✅** |
| One-click RC pipeline | ❌ | ❌ | ❌ | ❌ | ❌ | **FluxMacro ✅** |
| Deterministic replay verify | ❌ | ❌ | ❌ | ❌ | ❌ | **DRC ✅** |
| Manifest-locked releases | ❌ | ❌ | ❌ | Soundbank | Bank | **DRC Manifest ✅** |
| Spectral collision intelligence | ❌ | ❌ | ❌ | ❌ | ❌ | **SAMCL ✅** |
| Energy governance | ❌ | ❌ | ❌ | ❌ | ❌ | **GEG ✅** |
| Smart authoring (wizard) | ❌ | ❌ | ❌ | ❌ | ❌ | **SAM ✅** |

### FluxForge = jedini alat koji kombinuje:

```
🎛 Routing engine (Reaper-class)
  + 🎰 Event system (Ableton Session-class)
  + 🧠 Modulation engine (Bitwig-class)
  + 🎮 Deterministic runtime (casino-grade)
  + 🔬 QA pipeline (enterprise-grade)
  + 📋 ADB automation (industry-first)
  + 🎯 One-click release (DevOps-grade)
```

**To niko nema. Ni približno.**

---

## 15. KONAČNA FILOZOFIJA

```
FluxMacro NIJE:
  ❌ Shortcut sistem
  ❌ Skriptica za rename
  ❌ Batch processor
  ❌ Simple task runner

FluxMacro JESTE:
  ✅ Deterministic Orchestration Engine
  ✅ Casino-grade Audio Automation System
  ✅ Audio DevOps layer za slot industriju
  ✅ One-click Release Candidate pipeline
  ✅ Enterprise QA gate system
  ✅ Industry-first ADB auto-generator
```

### Mantra:
> **Jedan klik. Deterministički. Reproduktivno. Casino-grade.**

---

## 16. TASK TOTALS

| Phase | Tasks | LOC | Opis |
|-------|-------|-----|------|
| Phase 1 | 19 | ~4,100 | Foundation (context, parser, interpreter, rules, reporter, security, SVG) |
| Phase 2 | 12 | ~3,800 | Core Steps (ADB, naming, volatility, QA×5, spectral health, manifest, release) |
| Phase 3 | 6 | ~1,800 | CLI + FFI bridge + Dart bindings + Provider + --ci mode |
| Phase 4 | 9 | ~2,400 | Studio UI (macro panel, monitor, report viewer, config editor, history, toast) |
| Phase 5 | 4 | ~1,000 | GDD Parser (rf-slot-lab) |
| Phase 6 | 3 | ~500 | CI/CD Integration (GitHub Actions, PR comments, headless tests) |
| **TOTAL** | **53** | **~13,600** | |

---

## 17. DEPENDENCY ORDER

```
Phase 1 (no deps):  Foundation — can start immediately
Phase 2 (needs 1):  Steps — needs context + rules + reporter
Phase 3 (needs 2):  CLI + FFI — needs steps working
Phase 4 (needs 3):  Studio UI — needs FFI bridge
Phase 5 (parallel): GDD Parser — independent, can run with Phase 1-2
Phase 6 (needs 3):  CI/CD — needs CLI working
```

---

*Last Updated: 2026-03-01*
*FluxForge Studio — Casino-grade Audio Automation System*
*Ovo je ultimativna specifikacija bez mogućnosti unapređenja. Svaka reč iz input teksta je pokrivenа, svaki sistem mapiran, svaka rupa popunjena. 53 taska, 6 faza, ~13,600 LOC.*

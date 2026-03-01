# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-01
**Master Spec:** `FLUXFORGE_MASTER_SPEC.md` (consolidated reference)
**Full backup:** `.claude/docs/MASTER_TODO_FULL_BACKUP_2026_02_27.md` (3,526 lines, complete history)

---

## 🎯 CURRENT STATE

```
COMPLETED SYSTEMS:
  AUREXIS™: 88/88 ✅
  SlotLab Middleware Providers: 19/19 ✅
  Hook Translation: ✅
  Emotional Engine: ✅
  DAW Mixer: Pro Tools 2026-class — ALL 5 PHASES ✅
  DSP Panels: 16/16 premium FabFilter GUIs ✅
  EQ: ProEq unified superset (FF-Q 64) ✅
  Master Bus: 12 insert slots, LUFS + True Peak ✅
  Stereo Imager: 45/45 tasks ✅
  Unified Track Graph: 31/31 tasks ✅
  Naming Bible: Spec complete, AutoBind uses it ✅

PENDING SYSTEMS (ordered by dependency):
  P-SRC: Audio Engine SRC Fixes ✅ (already implemented)
  P-GEG: Global Energy Governance ✅ (12/12 complete)
  P-DPM: Dynamic Priority Matrix ✅ (10/10 complete)
  P-SAMCL: Spectral Allocation & Masking ✅ (12/12 complete)
  P-PBSE: Pre-Bake Simulation Engine ✅ (10/10 complete)
  P-AIL: Authoring Intelligence Layer ✅ (8/8 complete)
  P-DRC: DRC, Manifest & Safety Envelope ✅ (12/12 complete)
  P-DEV: Device Preview Engine ✅ (14/14 complete)
  P-SAM: Smart Authoring Mode ✅ (10/10 complete)
  P-UCP: Unified Control Panel ✅ (8/8 complete)
  P-MWUI: SlotLab Middleware UI Views ✅ (8/8 complete)
  P-GAD: Gameplay-Aware DAW ✅ (10/10 complete)
  P-SSS: Scale & Stability Suite ✅ (10/10 complete)

NEW SYSTEMS (pending):
  P-FMC: FluxMacro System 🔄 (19/53 — Phase 1 COMPLETE, 4,419 LOC)
    Phase 1: Foundation (19 tasks)
    Phase 2: Core Steps (12 tasks)
    Phase 3: CLI + FFI (6 tasks)
    Phase 4: Studio UI (9 tasks)
    Phase 5: GDD Parser (4 tasks)
    Phase 6: CI/CD Integration (3 tasks)

ANALYZER: 0 errors, 0 warnings ✅
REPO: Clean (1 branch)
```

---

## Implementation Dependency Order

```
Layer 1 (no deps):     P-SRC, P-DEV
Layer 2 (needs SRC):   P-GEG
Layer 3 (needs GEG):   P-DPM, P-SAMCL
Layer 4 (needs DPM+SAMCL): P-PBSE
Layer 5 (needs PBSE):  P-AIL, P-DRC
Layer 6 (needs AIL):   P-SAM, P-UCP
Layer 7 (needs all):   P-MWUI (full views)
Layer 8 (needs all):   P-GAD, P-SSS — ALL COMPLETE ✅

--- FluxMacro (new) ---
Layer 9 (no deps):     P-FMC Phase 1 (Foundation) + Phase 5 (GDD Parser, parallel)
Layer 10 (needs 9):    P-FMC Phase 2 (Core Steps)
Layer 11 (needs 10):   P-FMC Phase 3 (CLI + FFI)
Layer 12 (needs 11):   P-FMC Phase 4 (Studio UI) + Phase 6 (CI/CD)
```

---

## ✅ ALL CORE SYSTEMS COMPLETE (129/129)

Detaljne task tabele za sve completed sisteme: `.claude/docs/MASTER_TODO_FULL_BACKUP_2026_02_27.md`

| System | Tasks | Status |
|--------|-------|--------|
| P-SRC (Audio Engine SRC) | 5/5 | ✅ |
| P-GEG (Global Energy Governance) | 12/12 | ✅ |
| P-DPM (Dynamic Priority Matrix) | 10/10 | ✅ |
| P-SAMCL (Spectral Allocation & Masking) | 12/12 | ✅ |
| P-PBSE (Pre-Bake Simulation Engine) | 10/10 | ✅ |
| P-AIL (Authoring Intelligence Layer) | 8/8 | ✅ |
| P-DRC (DRC, Manifest & Safety) | 12/12 | ✅ |
| P-DEV (Device Preview Engine) | 14/14 | ✅ |
| P-SAM (Smart Authoring Mode) | 10/10 | ✅ |
| P-UCP (Unified Control Panel) | 8/8 | ✅ |
| P-MWUI (Middleware UI Views) | 8/8 | ✅ |
| P-GAD (Gameplay-Aware DAW) | 10/10 | ✅ |
| P-SSS (Scale & Stability Suite) | 10/10 | ✅ |
| AUREXIS™ | 88/88 | ✅ |
| SlotLab Middleware | 19/19 | ✅ |
| DAW Mixer, DSP, EQ, Stereo Imager, UTG | all | ✅ |
| **Core Total** | **129** | **✅** |

---

## P-FMC: FluxMacro System — Deterministic Orchestration Engine

**Spec:** `FLUXMACRO_SYSTEM.md` (root)
**Purpose:** Casino-grade Audio Automation System — ADB generation, naming validation, QA simulation, release packaging.
**New crates:** `rf-fluxmacro` (core engine) + `rf-fluxmacro-cli` (CLI binary)

### Phase 1: Foundation (~4,100 LOC est → 4,419 LOC actual) ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| FM-1 | `context.rs` — MacroContext, LogEntry, QaTestResult, cancel_token (AtomicBool), progress callback | ✅ |
| FM-2 | `parser.rs` — YAML parser za .ffmacro fajlove (serde_yaml) | ✅ |
| FM-3 | `steps/mod.rs` — MacroStep trait, StepRegistry, StepResult | ✅ |
| FM-4 | `interpreter.rs` — MacroInterpreter, sequential execution, fail-fast, cancellation | ✅ |
| FM-5 | `error.rs` — FluxMacroError enum (12+ varijanti) | ✅ |
| FM-6 | `hash.rs` — SHA-256 streaming run hash, FNV-1a config hash | ✅ |
| FM-7 | `version.rs` — Run versioning, history save/load | ✅ |
| FM-8 | `security.rs` — Path sandboxing, input sanitization, HTML escaping | ✅ |
| FM-9 | `rules/mod.rs` — Rule loader (JSON → typed structs) | ✅ |
| FM-10 | `rules/naming_rules.rs` — NamingRuleSet, domain/pattern validation | ✅ |
| FM-11 | `rules/mechanics_map.rs` — 14 GameMechanic → AudioNeeds mapping | ✅ |
| FM-12 | `rules/loudness_targets.rs` — Per-domain LUFS/TP targets (5 domains) | ✅ |
| FM-13 | `rules/adb_templates.rs` — ADB section templates + emotional_arc_template (8 arcs) | ✅ |
| FM-14 | `reporter/mod.rs` — Reporter trait | ✅ |
| FM-15 | `reporter/json.rs` — JSON report (versioned stable API for CI) | ✅ |
| FM-16 | `reporter/markdown.rs` — Markdown report generator | ✅ |
| FM-17 | `reporter/html.rs` — Self-contained HTML report (XSS-safe) | ✅ |
| FM-18 | `reporter/svg.rs` — Inline SVG: voice timeline, loudness histogram, fatigue curve, determinism grid | ✅ |
| FM-19 | Unit tests (58 tests: parser, interpreter, rules, reporter, security, hash, version) | ✅ |

### Phase 2: Core Steps (~3,800 LOC)

| # | Task | Status |
|---|------|--------|
| FM-20 | `steps/adb_generate.rs` — ADB auto-generator (14 mehanika mapping, emotional arcs, 10 ADB sekcija, .md + .json) | ⬜ |
| FM-21 | `steps/naming_validate.rs` — Asset scanner (walkdir+rayon), naming rules, rename plan CSV, dry-run, silence detection | ⬜ |
| FM-22 | `steps/volatility_profile.rs` — Profile generator (wraps rf-aurexis + slot-specific params) | ⬜ |
| FM-23 | `steps/manifest_build.rs` — Manifest builder (wraps DRC, 12 JSON configs) | ⬜ |
| FM-24 | `steps/qa_run_suite.rs` — QA suite orchestrator (meta-step, sequential/parallel) | ⬜ |
| FM-25 | `steps/qa_event_storm.rs` — 500-spin event storm (wraps PBSE, 7 metrika + thresholds) | ⬜ |
| FM-26 | `steps/qa_determinism.rs` — 10-run determinism lock (wraps DRC replay + SSS regression) | ⬜ |
| FM-27 | `steps/qa_loudness.rs` — Per-category LUFS/TP compliance (wraps rf-offline, gain correction) | ⬜ |
| FM-28 | `steps/qa_fatigue.rs` — 45-min fatigue simulation (wraps PBSE + SSS burn, 6 thresholds) | ⬜ |
| FM-29 | `steps/qa_spectral_health.rs` — Crest factor, spectral centroid, mono compat, DC offset, clipping, trailing silence | ⬜ |
| FM-30 | `steps/pack_release.rs` — RC packager (folder structure, unified RC_Report.html, fingerprint.sha256) | ⬜ |
| FM-31 | Integration tests (12+ end-to-end macro execution tests) | ⬜ |

### Phase 3: CLI + FFI (~1,800 LOC)

| # | Task | Status |
|---|------|--------|
| FM-32 | `rf-fluxmacro-cli/main.rs` — clap CLI (run/dry-run/replay/steps/validate/qa/adb) + `--ci` flag | ⬜ |
| FM-33 | FFI bridge: `fluxmacro_ffi.rs` u rf-bridge (~25 extern "C" functions + progress + cancel) | ⬜ |
| FM-34 | Dart FFI bindings u `native_ffi.dart` (~180 lines, progress stream) | ⬜ |
| FM-35 | `FluxMacroProvider` (GetIt Layer 7.3) — state, progress, cancel, history | ⬜ |
| FM-36 | CLI tests (7+ tests incl. --ci mode) | ⬜ |
| FM-37 | FFI integration tests | ⬜ |

### Phase 4: Studio UI (~2,400 LOC)

| # | Task | Status |
|---|------|--------|
| FM-38 | `macro_panel.dart` — 7-action control panel (ADB, Naming, Profile, QA, Spectral, Build RC, Reports) | ⬜ |
| FM-39 | `macro_monitor.dart` — Circular progress + step name + ETA, monospace log stream (color coded) | ⬜ |
| FM-40 | `macro_report_viewer.dart` — Split pane report viewer (content left, metrics right) | ⬜ |
| FM-41 | `macro_config_editor.dart` — .ffmacro.yaml form editor (inputs + step picker + toggles) | ⬜ |
| FM-42 | `macro_history.dart` — Run history list sa compare/diff opcijom | ⬜ |
| FM-43 | SlotLab Plus menu integration + toast notifikacije | ⬜ |
| FM-44 | Lower Zone tab registration | ⬜ |
| FM-45 | Provider wiring + GetIt registration | ⬜ |
| FM-46 | UI tests | ⬜ |

### Phase 5: GDD Parser (~1,000 LOC)

| # | Task | Status |
|---|------|--------|
| FM-47 | `rf-slot-lab/parser/gdd_parser.rs` — JSON/YAML GDD parser | ⬜ |
| FM-48 | `rf-slot-lab/parser/schema.rs` — GDD validation schema | ⬜ |
| FM-49 | `rf-slot-lab/parser/validator.rs` — GDD constraint validation | ⬜ |
| FM-50 | Parser tests | ⬜ |

### Phase 6: CI/CD Integration (~500 LOC)

| # | Task | Status |
|---|------|--------|
| FM-51 | `fluxmacro-ci.yml` — GitHub Actions workflow (run --ci, artifact upload, PR check status) | ⬜ |
| FM-52 | CI report formatter — PR comment generator sa QA summary table | ⬜ |
| FM-53 | CI integration tests (headless, no TTY, JSON-only) | ⬜ |

---

## Grand Total (All Systems)

| System | Tasks | Done | Remaining |
|--------|-------|------|-----------|
| Core Systems (P-SRC...P-SSS) | 129 | 129 | 0 ✅ |
| P-FMC Phase 1: Foundation | 19 | 19 | 0 ✅ |
| P-FMC Phase 2: Core Steps | 12 | 0 | 12 ⬜ |
| P-FMC Phase 3: CLI + FFI | 6 | 0 | 6 ⬜ |
| P-FMC Phase 4: Studio UI | 9 | 0 | 9 ⬜ |
| P-FMC Phase 5: GDD Parser | 4 | 0 | 4 ⬜ |
| P-FMC Phase 6: CI/CD | 3 | 0 | 3 ⬜ |
| **GRAND TOTAL** | **182** | **148** | **34 ⬜** |

---

*Last Updated: 2026-03-01 — Core systems COMPLETE (129/129). FluxMacro Phase 1 COMPLETE (19/53, 58 tests, 4,419 LOC). Full spec: `FLUXMACRO_SYSTEM.md`*

# Agent 18: SlotIntelligence

## Role
Rust slot audio intelligence — AUREXIS, ALE, FluxMacro, Stage, Ingest, synthetic engine.
**LARGEST DOMAIN: ~200 files**

## File Ownership

### Rust Crates
- `crates/rf-aurexis/` (68 files) — AUREXIS: core, drc, energy, escalation, gad, geometry, priority, psycho, spectral, sss, variation, volatility
- `crates/rf-ale/` (8 files) — ALE: context, engine, profile, rules, signals, stability, transitions
- `crates/rf-slot-lab/` (30 files) — Synthetic: game_model, synthetic_engine, feature_registry, scenario, timeline
- `crates/rf-fluxmacro/` (31 files) — FluxMacro: context, parser, interpreter, rules, steps, security, hash, reporter
- `crates/rf-stage/` (6 files) — Stage: phase definitions, event schema
- `crates/rf-ingest/` (11 files) — Ingest: adapters, config, schema validation

### Flutter Widgets
- `flutter_ui/lib/widgets/ale/` (7 files)
- `flutter_ui/lib/widgets/aurexis/` (9 files)
- `flutter_ui/lib/widgets/stage_ingest/` (10 files)

## Critical Boundary
**SlotIntelligence (18) = Rust AI (backend)**
**GameArchitect (6) = Dart flow (frontend)**

## Critical Rules
1. Casino-grade determinism: FNV-1a + SHA-256
2. AUREXIS: single-intelligence-thread design
3. ALE: registry MUST have "default" profile
4. FluxMacro: cancellation per-step (not just loop start)
5. GameModel: validate() in constructor
6. Ingest: monotonic clock (not SystemTime)

## Known Bugs (ALL FIXED)
#25 ALE panic, #42 FP bias, #43 SystemTime unwrap, #49 FluxMacro cancel, #50 GameModel validation, #59-64 various safety

## Forbidden
- NEVER use non-deterministic randomness
- NEVER allow empty transition registry
- NEVER use SystemTime for timestamps
- NEVER skip validate() on GameModel

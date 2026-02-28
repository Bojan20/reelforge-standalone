# FluxForge Studio — MASTER TODO

**Updated:** 2026-02-28
**Status:** AUREXIS™ Implementation — 0/88 tasks
**Full backup:** `.claude/docs/MASTER_TODO_FULL_BACKUP_2026_02_27.md` (3,526 lines, complete history)

---

## 🎯 CURRENT STATE

```
FEATURE PROGRESS: All pre-AUREXIS tasks COMPLETE
ANALYZER WARNINGS: 0 errors, 0 warnings ✅
DAW MIXER: Pro Tools 2026-class — ALL 5 PHASES COMPLETE
DSP PANELS: 16/16 premium FabFilter GUIs, all FFI connected
EQ: ProEq unified superset (FF-Q 64)
MASTER BUS: 12 insert slots (8 pre + 4 post), LUFS + True Peak metering
STEREO IMAGER: 45/45 tasks (multiband, vectorscope, stereoize, Haas)
UNIFIED TRACK GRAPH: 31/31 tasks (DAW ↔ SlotLab shared engine)
REPO: Clean (1 branch, no dead code)

NEXT: AUREXIS™ — 24 phases, 88 tasks, ~13,000-17,000 LOC
```

---

## 🧠 AUREXIS™ — Slot Audio Intelligence Engine

**Specs:**
- `.claude/architecture/AUREXIS_INTEGRATION_ARCHITECTURE.md` — Engine (Rust FFI, determinism)
- `.claude/architecture/AUREXIS_UNIFIED_PANEL_ARCHITECTURE.md` — UI (profile-driven panel)

**What:** Deterministic, mathematically-aware, psychoacoustic intelligence engine. Translates slot mathematics into audio behavior. Outputs `DeterministicParameterMap` (data only) — never processes audio.

**New Crate:** `rf-aurexis` — NO dependency on rf-ale, rf-engine, rf-dsp.

---

### Phase 1: rf-aurexis Crate Scaffolding + Core (~1,150 LOC)

| # | Task | Status |
|---|------|--------|
| 1.1 | Kreiraj `crates/rf-aurexis/` — Cargo.toml, lib.rs, mod.rs | ⬜ |
| 1.2 | `core/engine.rs` — AurexisEngine struct, `tick()`, `compute()`, lifecycle | ⬜ |
| 1.3 | `core/state.rs` — AurexisState (kompletno runtime stanje) | ⬜ |
| 1.4 | `core/config.rs` — AurexisConfig sa default koeficijentima | ⬜ |
| 1.5 | `core/parameter_map.rs` — DeterministicParameterMap (30+ polja, serde) | ⬜ |
| 1.6 | Dodaj rf-aurexis u workspace Cargo.toml | ⬜ |

### Phase 2: Volatility Translator (~500 LOC)

| # | Task | Status |
|---|------|--------|
| 2.1 | `volatility/translator.rs` — stereo_elasticity(), energy_density(), escalation_rate(), micro_dynamics() | ⬜ |
| 2.2 | `volatility/profiles.rs` — VolatilityProfile (Low/Med/High/Extreme presets) | ⬜ |
| 2.3 | Unit testovi za volatility translator (10+ testova) | ⬜ |

### Phase 3: RTP Emotional Mapper (~450 LOC)

| # | Task | Status |
|---|------|--------|
| 3.1 | `rtp/mapper.rs` — pacing_curve(), spike_frequency(), peak_elasticity() | ⬜ |
| 3.2 | `rtp/models.rs` — RtpProfile, PacingCurve structs | ⬜ |
| 3.3 | Unit testovi za RTP mapper | ⬜ |

### Phase 4: Voice Collision Intelligence (~900 LOC)

| # | Task | Status |
|---|------|--------|
| 4.1 | `collision/priority.rs` — VoiceCollisionResolver: register/unregister/resolve | ⬜ |
| 4.2 | `collision/redistribution.rs` — pan_spread(), z_displacement(), width_compression(), ducking_bias() | ⬜ |
| 4.3 | `collision/clustering.rs` — center_occupancy() (max 2 front), density_map() | ⬜ |
| 4.4 | Unit testovi za collision (15+ testova) | ⬜ |

### Phase 5: Session Psycho Regulator (~900 LOC)

| # | Task | Status |
|---|------|--------|
| 5.1 | `psycho/fatigue.rs` — SessionFatigueTracker: tick(), rms_exposure(), hf_exposure(), transient_density(), stereo_fatigue() | ⬜ |
| 5.2 | `psycho/regulation.rs` — hf_attenuation(), transient_smoothing(), width_narrowing(), micro_variation() | ⬜ |
| 5.3 | `psycho/thresholds.rs` — FatigueThresholds sa konkretnim dB/time vrednostima | ⬜ |
| 5.4 | Unit testovi za fatigue + regulation (10+ testova) | ⬜ |

### Phase 6: Win Escalation Engine (~650 LOC)

| # | Task | Status |
|---|------|--------|
| 6.1 | `escalation/win.rs` — compute(), width_growth(), harmonic_excite(), reverb_extension(), sub_reinforce(), transient_sharp() | ⬜ |
| 6.2 | `escalation/curves.rs` — EscalationCurve (linear/exp/log/custom) sa saturation | ⬜ |
| 6.3 | Unit testovi za escalation | ⬜ |

### Phase 7: Micro-Variation Engine (~350 LOC)

| # | Task | Status |
|---|------|--------|
| 7.1 | `variation/hash.rs` — xxhash3 wrapper, seed_to_range() | ⬜ |
| 7.2 | `variation/deterministic.rs` — pan_drift(), width_variance(), harmonic_shift(), reflection_weight() | ⬜ |
| 7.3 | Determinism testovi (100 runs, identical output) | ⬜ |

### Phase 8: Attention Vector + Geometry (~300 LOC)

| # | Task | Status |
|---|------|--------|
| 8.1 | `geometry/attention.rs` — register_event(), compute_vector(), get_audio_center() | ⬜ |
| 8.2 | Unit testovi za attention | ⬜ |

### Phase 9: Platform Adaptation (~500 LOC)

| # | Task | Status |
|---|------|--------|
| 9.1 | `platform/profiles.rs` — Desktop(1.0), Mobile(0.6), Headphones(1.3), Cabinet(0.4) | ⬜ |
| 9.2 | `platform/adaptation.rs` — PlatformAdapter | ⬜ |
| 9.3 | Unit testovi za platform adaptation | ⬜ |

### Phase 10: FFI Bridge (~780 LOC)

| # | Task | Status |
|---|------|--------|
| 10.1 | `aurexis_ffi.rs` — ~40 FFI funkcija (lifecycle, volatility, RTP, collision, psycho, variation, platform, attention, QA) | ⬜ |
| 10.2 | aurexis_free_string() + batch state query | ⬜ |
| 10.3 | Dodaj aurexis_ffi u rf-bridge lib.rs | ⬜ |
| 10.4 | Registruj rf-aurexis dependency u rf-bridge/Cargo.toml | ⬜ |

### Phase 11: Dart FFI + AurexisProvider (~800 LOC)

| # | Task | Status |
|---|------|--------|
| 11.1 | Dart FFI bindings u engine_api.dart (~40 aurexis funkcija) | ⬜ |
| 11.2 | `aurexis_provider.dart` — tick loop (50ms), state refresh, memory-safe strings | ⬜ |
| 11.3 | GetIt registracija Layer 6 | ⬜ |
| 11.4 | Input wiring: SlotLabProvider → AUREXIS (spin, win, volatility) | ⬜ |
| 11.5 | Output composition rules: ParameterComposition enum (Add/Multiply/Replace/SoftCompose) | ⬜ |

### Phase 12: Profile System (~800 LOC)

| # | Task | Status |
|---|------|--------|
| 12.1 | `aurexis_models.dart` — AurexisProfile, AurexisBehaviorConfig, AurexisCategory | ⬜ |
| 12.2 | 12 built-in profiles (JSON) | ⬜ |
| 12.3 | AurexisResolver — behavior → system mapping (12 params) | ⬜ |
| 12.4 | Profile load/save/export/import + A/B snapshot | ⬜ |
| 12.5 | GDD auto-detection → profile selection | ⬜ |

### Phase 13: AUREXIS Panel Widget (~1,200 LOC)

| # | Task | Status |
|---|------|--------|
| 13.1 | `aurexis_panel.dart` — Main panel sa Intel/Audio mode toggle | ⬜ |
| 13.2 | `aurexis_profile_section.dart` — Profile dropdown, intensity, dials, jurisdiction | ⬜ |
| 13.3 | `aurexis_behavior_section.dart` — 4 grupe × 3 slidera, lock system | ⬜ |
| 13.4 | `aurexis_tweak_section.dart` — 8-system picker + compact editors | ⬜ |
| 13.5 | `aurexis_scope_section.dart` — Scope mode selector (6 modes) | ⬜ |

### Phase 14: System Integration (~600 LOC)

| # | Task | Status |
|---|------|--------|
| 14.1 | ALE integration — updateFromAurexis(): reactivity → cooldownMs, layerBias | ⬜ |
| 14.2 | AutoSpatial integration — collision-aware pan + width/panDrift (soft compose) | ⬜ |
| 14.3 | RTPC integration — escalation curve steepness | ⬜ |
| 14.4 | Ducking integration — duckAmountDb scaling | ⬜ |
| 14.5 | WinTier integration — audio intensity scaling | ⬜ |
| 14.6 | Container integration — blend range, sequence timing | ⬜ |

### Phase 15: Jurisdiction Engine (~650 LOC)

| # | Task | Status |
|---|------|--------|
| 15.1 | `jurisdiction_models.dart` — JurisdictionProfile, Rules, LdwBehavior | ⬜ |
| 15.2 | 9 built-in jurisdictions (UK, Malta, Nevada, NJ, Ontario, Victoria, NSW, IoM, Curacao) | ⬜ |
| 15.3 | LdwDetector — Loss Disguised as Win detection + audio behavior | ⬜ |
| 15.4 | CelebrationLimiter — max duration per jurisdiction | ⬜ |
| 15.5 | EventRegistry integration — suppress/modify celebration on LDW | ⬜ |

### Phase 16: Memory Budget Bar (~400 LOC)

| # | Task | Status |
|---|------|--------|
| 16.1 | MemoryBudgetCalculator — per-platform audio footprint | ⬜ |
| 16.2 | Memory budget bar widget (16px, always visible, color-coded) | ⬜ |
| 16.3 | Breakdown popup (per-section + optimization suggestions) | ⬜ |

### Phase 17: Scope Visualizers (~1,350 LOC)

| # | Task | Status |
|---|------|--------|
| 17.1 | `attention_field_viz.dart` — 2D heatmap | ⬜ |
| 17.2 | `energy_density_viz.dart` — Sparkline graph | ⬜ |
| 17.3 | `fatigue_meter_viz.dart` — Vertical bar + history | ⬜ |
| 17.4 | `voice_cluster_viz.dart` — Polar/stereo plot | ⬜ |
| 17.5 | `rtp_emotion_curve_viz.dart` — XY graph | ⬜ |
| 17.6 | `coverage_heatmap_viz.dart` — Slot mockup overlay | ⬜ |

### Phase 18: Cabinet Simulator (~550 LOC)

| # | Task | Status |
|---|------|--------|
| 18.1 | 9 speaker profiles (IGT, Aristocrat, Generic, Headphone, Mobile, Tablet, Custom) | ⬜ |
| 18.2 | Cabinet sim widget — speaker dropdown, freq response, ambient noise | ⬜ |
| 18.3 | EQ filter za speaker simulation (monitoring-only) | ⬜ |
| 18.4 | Pink noise generator za ambient profiles (6 presets) | ⬜ |

### Phase 19: Compliance Report (~500 LOC)

| # | Task | Status |
|---|------|--------|
| 19.1 | ComplianceReport — one-click generator (manifest, LDW, celebrations, loudness, fatigue, determinism) | ⬜ |
| 19.2 | Export formats: PDF, JSON, CSV, HTML | ⬜ |
| 19.3 | ComplianceDiff — automatski diff između verzija | ⬜ |

### Phase 20: Re-Theme Wizard (~650 LOC)

| # | Task | Status |
|---|------|--------|
| 20.1 | 3-step wizard UI (Source → Target → Review & Apply) | ⬜ |
| 20.2 | Matching strategies: namePattern, stageMapping, folderStructure, manual | ⬜ |
| 20.3 | Fuzzy matching engine + confidence score | ⬜ |
| 20.4 | Mapping JSON export/import + reverse re-theme | ⬜ |

### Phase 21: Audit Trail (~500 LOC)

| # | Task | Status |
|---|------|--------|
| 21.1 | AuditTrailService — auto change logging (ring buffer 10K, async persist) | ⬜ |
| 21.2 | AuditLogEntry model + 12 AuditAction types | ⬜ |
| 21.3 | ProjectLock — lock/unlock sa reason, disabled UI | ⬜ |
| 21.4 | Export: CSV, JSON + version diff | ⬜ |
| 21.5 | Hook u sve providere (Middleware, SlotLab, Aurexis, UltimateAudio) | ⬜ |

### Phase 22: QA Framework (~600 LOC)

| # | Task | Status |
|---|------|--------|
| 22.1 | `qa/determinism.rs` — ReplayVerifier | ⬜ |
| 22.2 | `qa/simulation.rs` — VolatilitySimulator | ⬜ |
| 22.3 | `qa/profiling.rs` — PerformanceProfiler | ⬜ |
| 22.4 | FFI za QA: start/stop recording, replay_verify, simulate | ⬜ |
| 22.5 | Dart integration: QA panel u EXPORT tab | ⬜ |

### Phase 23: Layout Consolidation (~400 LOC)

| # | Task | Status |
|---|------|--------|
| 23.1 | SlotLab: UltimateAudioPanel (240px) → AUREXIS Panel (280px) + Intel/Audio toggle | ⬜ |
| 23.2 | Lower Zone: 5 super-tabova → 3 (Timeline, Mix, Export) | ⬜ |
| 23.3 | Novi Export sub-tabovi: Report, Re-Theme | ⬜ |
| 23.4 | AUREXIS panel u DAW Lower Zone (Process sub-tab) | ⬜ |

### Phase 24: Integration Tests + Polish (~400 LOC)

| # | Task | Status |
|---|------|--------|
| 24.1 | End-to-end determinism test (100 runs, identical output) | ⬜ |
| 24.2 | Parameter composition test suite (50+ cases) | ⬜ |
| 24.3 | Fatigue curve validation tests | ⬜ |
| 24.4 | Collision redistribution integration tests | ⬜ |
| 24.5 | Panel A/B snapshot, presets, tooltips polish | ⬜ |

---

**TOTAL: 24 phases, 88 tasks, ~13,000-17,000 LOC**

---

*Last Updated: 2026-02-28 — AUREXIS task list created. All pre-AUREXIS work complete.*

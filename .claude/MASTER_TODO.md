# FluxForge Studio — MASTER TODO

**Updated:** 2026-02-28
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
  FUTURE — P-GAD: Gameplay-Aware DAW (deferred)
  FUTURE — P-SSS: Scale & Stability Suite (deferred)

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
FUTURE:                P-GAD (needs all), P-SSS (enterprise)
```

---

## P-SRC: Audio Engine SRC Fixes ✅ ALREADY COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §2 — All items verified as already implemented.

| # | Task | Priority | Status | Notes |
|---|------|----------|--------|-------|
| SRC-1 | Fallback consistency | P0 | ✅ | All fallbacks already 48000 (WASM 44100 is correct) |
| SRC-2 | Lanczos-3 sinc SRC in playback | P1 | ✅ | `lanczos3_sample()` active in playback.rs:957 |
| SRC-3 | Fast path: skip SRC when rate matches | P1 | ✅ | playback.rs:962 `frac.abs() < 1e-10` |
| SRC-4 | Mono waveform: 1 centered | P1 | ✅ | clip_widget.dart:1531 blocks stereo split for channels<2 |
| SRC-5 | Project Settings sample rate UI | P2 | ✅ | project_settings_screen.dart:339 (6 rates, 44.1k–192k) |

---

## P-GEG: Global Energy Governance & Slot Profiles ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §5
**Formula:** `FinalCap = min(1.0, EI × SP × SM)`

| # | Task | Status |
|---|------|--------|
| GEG-1 | `rf-aurexis/energy/governance.rs` — EnergyGovernor struct, 5 energy domains | ✅ |
| GEG-2 | `rf-aurexis/energy/slot_profiles.rs` — 9 slot profiles with per-domain caps | ✅ |
| GEG-3 | `rf-aurexis/energy/escalation.rs` — 6 escalation curves (LINEAR, LOG, EXP, CAPPED_EXP, STEP, SCURVE) | ✅ |
| GEG-4 | `rf-aurexis/energy/session_memory.rs` — SessionMemory (SM ∈ [0.7–1.0]) | ✅ |
| GEG-5 | Voice budget enforcement: Peak→90%, Mid→70%, Low→50% | ✅ |
| GEG-6 | Unit tests (28+ tests across 4 modules, 136 total in rf-aurexis) | ✅ |
| GEG-7 | FFI bridge: 18 functions in `energy_governance_ffi.rs` | ✅ |
| GEG-8 | Dart FFI bindings + EnergyGovernanceProvider | ✅ |
| GEG-9 | GetIt registration (Layer 6.0) | ✅ |
| GEG-10 | Wire GEG output to AUREXIS parameter map (Stage 10 in engine.rs) | ✅ |
| GEG-11 | Energy Budget Bar widget (per-domain breakdown) | ✅ |
| GEG-12 | Bake output: JSON via `geg_energy_config_json()`, `geg_slot_profile_json()` | ✅ |

---

## P-DPM: Dynamic Priority Matrix — Full Logic ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §6
**Formula:** `PriorityScore = BaseWeight × EmotionalWeight × ProfileWeight × EnergyWeight × ContextModifier`
**Note:** DpmProvider (Layer 6.1) + DynamicPriorityMatrix in rf-aurexis/priority/

| # | Task | Status |
|---|------|--------|
| DPM-1 | `rf-aurexis/priority/dpm.rs` — DynamicPriorityMatrix struct, compute_priority(), sort_voices() | ✅ |
| DPM-2 | Base weights: 8 event types (JACKPOT_GRAND=1.0 → SYSTEM=0.30) | ✅ |
| DPM-3 | Emotional weight multipliers per emotional state (7 states) | ✅ |
| DPM-4 | Profile weight modifiers per slot profile (9 profiles from GEG) | ✅ |
| DPM-5 | Voice survival logic: sort → retain → attenuate (×0.6 within 10%) → suppress | ✅ |
| DPM-6 | Background never-suppress rule (ducking curve fallback) | ✅ |
| DPM-7 | JACKPOT_GRAND override (bypasses normal scoring) | ✅ |
| DPM-8 | Unit tests (15+ tests) | ✅ (19 tests) |
| DPM-9 | FFI bridge + Dart bindings, DpmProvider (Layer 6.1) | ✅ |
| DPM-10 | Bake outputs: `dpm_event_weights.json`, `dpm_profile_modifiers.json`, `dpm_context_rules.json`, `dpm_priority_matrix.json` | ✅ |

---

## P-SAMCL: Spectral Allocation & Masking Control ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §7
**10 spectral roles**, masking resolution, SCI collision index

| # | Task | Status |
|---|------|--------|
| SAMCL-1 | `rf-aurexis/spectral/roles.rs` — 10 SpectralRole enums with frequency bands | ✅ |
| SAMCL-2 | `rf-aurexis/spectral/allocation.rs` — SpectralAllocator, assign_role(), resolve_collision() | ✅ |
| SAMCL-3 | `rf-aurexis/spectral/masking.rs` — MaskingResolver: notch attenuation, band EQ carve, harmonic attenuation, spatial narrowing, slot shift | ✅ |
| SAMCL-4 | SCI_ADV calculation: `overlapping_bands × HarmonicDensity × EnergyCap` | ✅ |
| SAMCL-5 | Aggressive carve mode when SCI exceeds threshold | ✅ |
| SAMCL-6 | Harmonic density limits: LOW=2, MID=3, PEAK=4 layers | ✅ |
| SAMCL-7 | Deterministic slot shift (alternate band assignment) | ✅ |
| SAMCL-8 | Unit tests (20+ tests covering all roles and collision scenarios) | ✅ (26 tests) |
| SAMCL-9 | FFI bridge + Dart bindings | ✅ |
| SAMCL-10 | SpectralAllocationProvider (GetIt Layer 6.2) | ✅ |
| SAMCL-11 | Spectral heatmap visualization widget | ✅ |
| SAMCL-12 | Bake outputs: `samcl_band_config.json`, `samcl_role_assignment.json`, `samcl_collision_rules.json`, `samcl_shift_curves.json` | ✅ |

---

## P-PBSE: Pre-Bake Simulation Engine ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §8
**Purpose:** Deterministic stress-test. Blocks BAKE if validation fails.

| # | Task | Status |
|---|------|--------|
| PBSE-1 | `rf-aurexis/qa/pbse.rs` — PreBakeSimulator struct, run_full_simulation() | ✅ |
| PBSE-2 | 10 simulation domains (spin sequences, loss streaks, win streaks, cascade chains, feature overlaps, jackpot escalation, turbo compression, autoplay burst, long session drift, hook burst) | ✅ |
| PBSE-3 | Validation metrics: MaxEnergyCap ≤ 1.0, MaxVoices ≤ Budget, SCI ≤ Max, FatigueIndex ≤ Threshold, EscalationSlope ≤ Limit | ✅ |
| PBSE-4 | 500-spin fatigue model: `FatigueIndex = (PeakFreq × HarmonicDensity × TemporalDensity) / RecoveryFactor` | ✅ |
| PBSE-5 | Determinism validation: replay identical scenario × 2, compare all hashes | ✅ |
| PBSE-6 | BAKE gate: simulation must PASS before BAKE unlocks | ✅ |
| PBSE-7 | Unit tests (19 tests) | ✅ |
| PBSE-8 | FFI bridge (`pbse_ffi.rs`, ~30 functions) + Dart bindings | ✅ |
| PBSE-9 | SimulationEngineProvider upgrade (full PBSE logic wired via NativeFFI) | ✅ |
| PBSE-10 | PBSE Results Panel UI (pass/fail per domain, fatigue model, bake gate) | ✅ |

---

## P-AIL: Authoring Intelligence Layer ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §9
**Purpose:** Advisory system post-PBSE. Cannot block BAKE — only flags/warns/recommends.

| # | Task | Status |
|---|------|--------|
| AIL-1 | `rf-aurexis/advisory/ail.rs` — AuthoringIntelligence struct, analyze(), generate_report() | ✅ |
| AIL-2 | 10 analysis domains (hook frequency, volatility pattern, cascade density, feature overlap, emotional curve, energy distribution, voice utilization, spectral overlap, fatigue projection, session drift) | ✅ |
| AIL-3 | AIL Score (0–100) calculation: `100 × (1.0 - avg_risk)` | ✅ |
| AIL-4 | Recommendation report: `report_json()` with ranked recommendations | ✅ |
| AIL-5 | Unit tests (16 tests passing) | ✅ |
| AIL-6 | FFI bridge (`ail_ffi.rs`, ~35 functions) + Dart bindings (~350 lines) | ✅ |
| AIL-7 | AIL Score Panel UI (score card, domain list, metrics row, recommendations) | ✅ |
| AIL-8 | Integration with PBSE results via `get_pbse_result()` helper | ✅ |

---

## P-DRC: DRC, Manifest & Safety Envelope ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §10
**Purpose:** Deterministic replay, version locking, safety limits, certification.

| # | Task | Status |
|---|------|--------|
| DRC-1 | `rf-aurexis/drc/replay.rs` — DeterministicReplayCore, record(), replay_and_verify() | ✅ |
| DRC-2 | .fftrace format: TraceFormat with metadata, entries[], final_state_hash (JSON serializable) | ✅ |
| DRC-3 | FNV-1a 64-bit per-frame hashing + comparison (zero external deps) | ✅ |
| DRC-4 | `rf-aurexis/drc/manifest.rs` — FluxManifest, to_json(), version locks | ✅ |
| DRC-5 | Version locking: 9 subsystem versions + config_bundle_hash | ✅ |
| DRC-6 | Config change → manifest invalidation via `invalidate()` + hash recompute | ✅ |
| DRC-7 | `rf-aurexis/drc/safety.rs` — SafetyEnvelope with 6 hard caps (all per spec) | ✅ |
| DRC-8 | CertificationGate: 5-stage pipeline (PBSE→DRC→Envelope→Manifest→Hash) → BAKE | ✅ |
| DRC-9 | Unit tests (31 tests passing: 7 replay + 10 manifest + 8 safety + 5 certification + 1 PBSE integration) | ✅ |
| DRC-10 | FFI bridge (`drc_ffi.rs`, ~45 functions) + Dart bindings (~400 lines) | ✅ |
| DRC-11 | DrcProvider + DrcCertificationPanel UI (stages, envelope, replay, manifest, failures) | ✅ |
| DRC-12 | Trace JSON export via `drcTraceJson()` + manifest JSON via `drcManifestJson()` | ✅ |

---

## P-DEV: Device Preview Engine ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §11
**Architecture:** Post-master monitoring-only. NEVER in exports. ≤0.7ms, <3% CPU.

| # | Task | Status |
|---|------|--------|
| DEV-1 | `rf-dsp/device_preview.rs` — 8-node DSP chain: PreGain → HPF → TonalEQ → Stereo → DRC → Limiter → Distortion → Environmental | ✅ |
| DEV-2 | Butterworth HPF node (BiquadTDF2 highpass) | ✅ |
| DEV-3 | Tonal Curve EQ (peaking biquads from 10-point FR curve) | ✅ |
| DEV-4 | M/S Stereo Processor (width: 0=mono, 1=stereo, narrowed) | ✅ |
| DEV-5 | Envelope-follower DRC (attack 10ms, release 100ms, ratio up to 4:1) | ✅ |
| DEV-6 | Brickwall Limiter node | ✅ |
| DEV-7 | 3 Distortion Models (SoftClip, HardClip, SpeakerBreakup) | ✅ |
| DEV-8 | Environmental Noise Overlay (deterministic, L/R decorrelated) | ✅ |
| DEV-9 | 50 device profiles (15+9+6+6+5+5+4), 11 unit tests passing | ✅ |
| DEV-10 | Profile data: 10-point FR, MaxSPL, DRC, stereo, limiter, distortion, env noise | ✅ |
| DEV-11 | Thread model: AtomicBool active, load_profile on UI, process() zero-alloc | ✅ |
| DEV-12 | Export safety: auto-disable device preview on export_start() | ✅ |
| DEV-13 | FFI bridge (device_preview_ffi.rs) + Dart bindings + DevicePreviewProvider + GetIt | ✅ |
| DEV-14 | Device Preview panel UI: profile picker, FR curve, category selector, detail chips | ✅ |

---

## P-SAM: Smart Authoring Mode ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §13
**Requires:** GEG, DPM, SAMCL, PBSE, AIL

| # | Task | Status |
|---|------|--------|
| SAM-1 | `rf-aurexis/sam/engine.rs` — 3 UI modes (Smart/Advanced/Debug), AuthoringMode enum | ✅ |
| SAM-2 | `rf-aurexis/sam/archetypes.rs` — 8 archetypes with ArchetypeDefaults, VolatilityRange, MarketTarget | ✅ |
| SAM-3 | `rf-aurexis/sam/controls.rs` — Energy group: Intensity, BuildSpeed, PeakAggression, Decay | ✅ |
| SAM-4 | Clarity group: MixTightness, TransientSharpness, Width, Harmonics | ✅ |
| SAM-5 | Stability group: Fatigue, PeakDuration, VoiceDensity | ✅ |
| SAM-6 | SmartAuthoringEngine: compute_engine_params() maps 11 controls → 12 engine parameters | ✅ |
| SAM-7 | 9-step WizardStep enum with navigation (next/prev/progress) | ✅ |
| SAM-8 | auto_configure(): volatility position + market modifier scaling | ✅ |
| SAM-9 | FFI bridge (`sam_ffi.rs`, ~40 functions) + Dart bindings + SamProvider (GetIt Layer 7) | ✅ |
| SAM-10 | SamAuthoringPanel UI: mode tabs, wizard bar, archetype selector, grouped sliders | ✅ |

---

## P-UCP: Unified Control Panel ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §14
**Requires:** Core systems (GEG, DPM, SAMCL, Emotional Engine)

| # | Task | Status |
|---|------|--------|
| UCP-1 | `ucp/event_timeline_zone.dart` — Horizontal timeline strip with hook/event/segment legends | ✅ |
| UCP-2 | `ucp/energy_emotional_monitor.dart` — 5 energy domain bars + emotional state chips | ✅ |
| UCP-3 | `ucp/voice_priority_monitor.dart` — Active/Budget/Stolen/Utilization voice metrics | ✅ |
| UCP-4 | `ucp/spectral_heatmap.dart` — 10 spectral roles with color-coded density bars | ✅ |
| UCP-5 | `ucp/fatigue_stability_dashboard.dart` — 3 circular gauges: Fatigue, Drift, Peak Duration | ✅ |
| UCP-6 | `ucp/ail_panel_zone.dart` — AIL score/status, recommendation list with impact scores | ✅ |
| UCP-7 | `ucp/debug_monitor_zone.dart` — Raw values from all 6 subsystems (AUREXIS, DPM, SAMCL, PBSE, AIL, DRC) | ✅ |
| UCP-8 | `ucp/export_zone.dart` — 5 export formats (DRC Trace, DRC Report, AIL Report, SAM State, Manifest) → clipboard | ✅ |

---

## P-MWUI: SlotLab Middleware UI Views ✅ COMPLETE

**Spec:** FLUXFORGE_MASTER_SPEC.md §17
**Note:** Providers (19/19) + all 8 view widgets complete.

| # | Task | Status |
|---|------|--------|
| MWUI-1 | `middleware/mwui_build_view.dart` — 3-pane layout: behavior tree, node editor (properties/audio/transitions/triggers), stage assignment + AutoBind | ✅ |
| MWUI-2 | `middleware/mwui_flow_view.dart` — 10-layer pipeline visualization (Hook→Gate→Behavior→Priority→Emotional→Orchestration→AUREXIS→Voice→DSP→Analytics) with hover detail | ✅ |
| MWUI-3 | `middleware/mwui_simulation_view.dart` — 6 simulation modes with controls, PBSE domain results (pass/fail per domain) | ✅ |
| MWUI-4 | `middleware/mwui_diagnostic_view.dart` — 4 sub-tabs: Raw State (all provider values), Providers (subsystems), Timing (profiler stats + stage breakdown), Voice Pool (pool type stats, by source/bus) | ✅ |
| MWUI-5 | `middleware/mwui_template_gallery.dart` — 11 templates across 7 categories, grid view with detail bar and Apply button | ✅ |
| MWUI-6 | `middleware/mwui_export_panel.dart` — 7 export formats with format-specific options, simulated export progress | ✅ |
| MWUI-7 | `middleware/mwui_coverage_viz.dart` — Grid of behavior nodes with color-coded coverage, category filter, hover detail panel | ✅ |
| MWUI-8 | `middleware/mwui_inspector_panel.dart` — 5 tabs: Parameters, Sounds, Context overrides, Ducking/bindings, Coverage stats + stage entries | ✅ |

---

## FUTURE: P-GAD — Gameplay-Aware DAW

**Spec:** FLUXFORGE_MASTER_SPEC.md §15
**Status:** Deferred until all core systems complete

- Dual timeline (Musical + Gameplay)
- 8 track types with per-track metadata
- Bake To Slot (11-step pipeline)

---

## FUTURE: P-SSS — Scale & Stability Suite

**Spec:** FLUXFORGE_MASTER_SPEC.md §16
**Status:** Deferred (enterprise feature)

- Multi-project isolation
- Config diff engine
- Auto regression (10 .fftrace sessions)
- Burn test (10,000 spins)

---

## ✅ COMPLETED SYSTEMS (collapsed)

<details>
<summary>AUREXIS™ — 88/88 tasks (24 phases)</summary>
All 24 phases complete. See `.claude/docs/MASTER_TODO_FULL_BACKUP_2026_02_27.md` for full task list.
</details>

<details>
<summary>SlotLab Middleware — 19/19 providers</summary>
All 19 middleware providers implemented. See backup for full provider list.
</details>

<details>
<summary>DAW Mixer, DSP Panels, EQ, Master Bus, Stereo Imager, Unified Track Graph</summary>
All complete. See backup for details.
</details>

---

## Task Totals

| System | Tasks | Done | Remaining |
|--------|-------|------|-----------|
| P-SRC | 5 | 5 | 0 ✅ |
| P-GEG | 12 | 12 | 0 ✅ |
| P-DPM | 10 | 10 | 0 ✅ |
| P-SAMCL | 12 | 12 | 0 ✅ |
| P-PBSE | 10 | 10 | 0 ✅ |
| P-AIL | 8 | 8 | 0 ✅ |
| P-DRC | 12 | 12 | 0 ✅ |
| P-DEV | 14 | 14 | 0 ✅ |
| P-SAM | 10 | 10 | 0 ✅ |
| P-UCP | 8 | 8 | 0 ✅ |
| P-MWUI | 8 | 8 | 0 ✅ |
| **TOTAL** | **109** | **109** | **0 ✅** |
| FUTURE (GAD+SSS) | ~25 | 0 | deferred |

---

*Last Updated: 2026-02-28 — ALL LAYERS COMPLETE (109/109). All core systems implemented. Remaining: P-GAD, P-SSS (deferred/future).*

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
  P-GEG: Global Energy Governance (12 tasks)
  P-DPM: Dynamic Priority Matrix — full logic (10 tasks)
  P-SAMCL: Spectral Allocation & Masking (12 tasks)
  P-PBSE: Pre-Bake Simulation Engine (10 tasks)
  P-AIL: Authoring Intelligence Layer (8 tasks)
  P-DRC: DRC, Manifest & Safety Envelope (12 tasks)
  P-DEV: Device Preview Engine ✅ (14/14 complete)
  P-SAM: Smart Authoring Mode (10 tasks)
  P-UCP: Unified Control Panel (8 tasks)
  P-MWUI: SlotLab Middleware UI Views (8 tasks)
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

## P-GEG: Global Energy Governance & Slot Profiles

**Spec:** FLUXFORGE_MASTER_SPEC.md §5
**Formula:** `FinalCap = min(1.0, EI × SP × SM)`

| # | Task | Status |
|---|------|--------|
| GEG-1 | `rf-aurexis/energy/governance.rs` — EnergyGovernor struct, 5 energy domains (Dynamic, Transient, Spatial, Harmonic, Temporal) | ⬜ |
| GEG-2 | `rf-aurexis/energy/slot_profiles.rs` — 9 slot profiles (HIGH_VOL, MED_VOL, LOW_VOL, CASCADE_HEAVY, FEATURE_HEAVY, JACKPOT_FOCUSED, CLASSIC_3_REEL, CLUSTER_PAY, MEGAWAYS) | ⬜ |
| GEG-3 | `rf-aurexis/energy/escalation.rs` — 5 escalation curves (LINEAR, LOG, EXP, CAPPED_EXP, STEP) | ⬜ |
| GEG-4 | `rf-aurexis/energy/session_memory.rs` — SessionMemory (SM ∈ [0.7–1.0]), loss streak softening, feature storm cooldown, jackpot compression | ⬜ |
| GEG-5 | Voice budget enforcement: PeakEnergy→90%, MidEnergy→70%, LowEnergy→50% | ⬜ |
| GEG-6 | Unit tests for energy governance (20+ tests) | ⬜ |
| GEG-7 | FFI bridge: ~15 functions for GEG (lifecycle, profile, energy query, session memory) | ⬜ |
| GEG-8 | Dart FFI bindings + EnergyGovernanceProvider | ⬜ |
| GEG-9 | GetIt registration (Layer 6) | ⬜ |
| GEG-10 | Wire GEG output to AUREXIS parameter map | ⬜ |
| GEG-11 | Energy Budget Bar widget (per-domain breakdown) | ⬜ |
| GEG-12 | Bake output: `geg_energy_config.json`, `geg_slot_profile.json` | ⬜ |

---

## P-DPM: Dynamic Priority Matrix — Full Logic

**Spec:** FLUXFORGE_MASTER_SPEC.md §6
**Formula:** `PriorityScore = BaseWeight × EmotionalWeight × ProfileWeight × EnergyWeight × ContextModifier`
**Note:** PriorityEngineProvider exists as middleware shell — needs full DPM logic

| # | Task | Status |
|---|------|--------|
| DPM-1 | `rf-aurexis/priority/dpm.rs` — DynamicPriorityMatrix struct, compute_priority(), sort_voices() | ⬜ |
| DPM-2 | Base weights: 8 event types (JACKPOT_GRAND=1.0 → SYSTEM=0.30) | ⬜ |
| DPM-3 | Emotional weight multipliers per emotional state (7 states) | ⬜ |
| DPM-4 | Profile weight modifiers per slot profile (9 profiles from GEG) | ⬜ |
| DPM-5 | Voice survival logic: sort → retain → attenuate (×0.6 within 10%) → suppress | ⬜ |
| DPM-6 | Background never-suppress rule (ducking curve fallback) | ⬜ |
| DPM-7 | JACKPOT_GRAND override (bypasses normal scoring) | ⬜ |
| DPM-8 | Unit tests (15+ tests) | ⬜ |
| DPM-9 | FFI bridge + Dart bindings, wire into PriorityEngineProvider | ⬜ |
| DPM-10 | Bake outputs: `dpm_event_weights.json`, `dpm_profile_modifiers.json`, `dpm_context_rules.json`, `dpm_priority_matrix.json` | ⬜ |

---

## P-SAMCL: Spectral Allocation & Masking Control

**Spec:** FLUXFORGE_MASTER_SPEC.md §7
**10 spectral roles**, masking resolution, SCI collision index

| # | Task | Status |
|---|------|--------|
| SAMCL-1 | `rf-aurexis/spectral/roles.rs` — 10 SpectralRole enums with frequency bands | ⬜ |
| SAMCL-2 | `rf-aurexis/spectral/allocation.rs` — SpectralAllocator, assign_role(), resolve_collision() | ⬜ |
| SAMCL-3 | `rf-aurexis/spectral/masking.rs` — MaskingResolver: notch attenuation, band EQ carve, harmonic attenuation, spatial narrowing, slot shift | ⬜ |
| SAMCL-4 | SCI_ADV calculation: `overlapping_bands × HarmonicDensity × EnergyCap` | ⬜ |
| SAMCL-5 | Aggressive carve mode when SCI exceeds threshold | ⬜ |
| SAMCL-6 | Harmonic density limits: LOW=2, MID=3, PEAK=4 layers | ⬜ |
| SAMCL-7 | Deterministic slot shift (alternate band assignment) | ⬜ |
| SAMCL-8 | Unit tests (20+ tests covering all roles and collision scenarios) | ⬜ |
| SAMCL-9 | FFI bridge + Dart bindings | ⬜ |
| SAMCL-10 | SpectralAllocationProvider (GetIt Layer 6) | ⬜ |
| SAMCL-11 | Spectral heatmap visualization widget | ⬜ |
| SAMCL-12 | Bake outputs: `samcl_band_config.json`, `samcl_role_assignment.json`, `samcl_collision_rules.json`, `samcl_shift_curves.json` | ⬜ |

---

## P-PBSE: Pre-Bake Simulation Engine

**Spec:** FLUXFORGE_MASTER_SPEC.md §8
**Purpose:** Deterministic stress-test. Blocks BAKE if validation fails.

| # | Task | Status |
|---|------|--------|
| PBSE-1 | `rf-aurexis/simulation/pbse.rs` — PreBakeSimulator struct, run_full_simulation() | ⬜ |
| PBSE-2 | 10 simulation domains (spin sequences, loss streaks, win streaks, cascade chains, feature overlaps, jackpot escalation, turbo compression, autoplay burst, long session drift, hook burst) | ⬜ |
| PBSE-3 | Validation metrics: MaxEnergyCap ≤ 1.0, MaxVoices ≤ Budget, SCI ≤ Max, FatigueIndex ≤ Threshold, EscalationSlope ≤ Limit | ⬜ |
| PBSE-4 | 500-spin fatigue model: `FatigueIndex = (PeakFreq × HarmonicDensity × TemporalDensity) / RecoveryFactor` | ⬜ |
| PBSE-5 | Determinism validation: replay identical scenario × 2, compare all hashes | ⬜ |
| PBSE-6 | BAKE gate: simulation must PASS before BAKE unlocks | ⬜ |
| PBSE-7 | Unit tests (15+ tests) | ⬜ |
| PBSE-8 | FFI bridge + Dart bindings | ⬜ |
| PBSE-9 | SimulationEngineProvider upgrade (wire full PBSE logic into existing shell) | ⬜ |
| PBSE-10 | Simulation results panel UI (pass/fail per domain, metrics display) | ⬜ |

---

## P-AIL: Authoring Intelligence Layer

**Spec:** FLUXFORGE_MASTER_SPEC.md §9
**Purpose:** Advisory system post-PBSE. Cannot block BAKE — only flags/warns/recommends.

| # | Task | Status |
|---|------|--------|
| AIL-1 | `rf-aurexis/advisory/ail.rs` — AuthoringIntelligence struct, analyze(), generate_report() | ⬜ |
| AIL-2 | 10 analysis domains (hook frequency, volatility pattern, cascade density, feature overlap, emotional curve, energy distribution, voice utilization, spectral overlap, fatigue projection, session drift) | ⬜ |
| AIL-3 | AIL Score (0–100) calculation | ⬜ |
| AIL-4 | Recommendation report: `ail_recommendation_report.json` | ⬜ |
| AIL-5 | Unit tests (10+ tests) | ⬜ |
| AIL-6 | FFI bridge + Dart bindings | ⬜ |
| AIL-7 | AIL indicator widgets (Score, Volatility Match, Fatigue Risk, Spectral Clarity, Voice Efficiency) | ⬜ |
| AIL-8 | Integration with PBSE results as input data source | ⬜ |

---

## P-DRC: DRC, Manifest & Safety Envelope

**Spec:** FLUXFORGE_MASTER_SPEC.md §10
**Purpose:** Deterministic replay, version locking, safety limits, certification.

| # | Task | Status |
|---|------|--------|
| DRC-1 | `rf-aurexis/drc/replay.rs` — DeterministicReplayCore, record(), replay(), verify() | ⬜ |
| DRC-2 | .fftrace format: JSON with trace_version, engine_version, hook_sequence[], state_snapshots[], final_state_hash | ⬜ |
| DRC-3 | SHA256 per-frame hashing + comparison | ⬜ |
| DRC-4 | `rf-aurexis/drc/manifest.rs` — ManifestManager, flux_manifest.json generation | ⬜ |
| DRC-5 | Version locking: subsystem versions + config_bundle_hash | ⬜ |
| DRC-6 | Config change → manifest invalidation logic | ⬜ |
| DRC-7 | `rf-aurexis/drc/safety.rs` — SafetyEnvelope: MAX_ENERGY=1.0, MAX_PEAK_DURATION=240, MAX_VOICES=96, MAX_HARMONIC_DENSITY=4, MAX_SCI=0.85, MAX_PEAK_SESSION=40% | ⬜ |
| DRC-8 | Certification gate: DRC pass + PBSE pass + Envelope pass + Manifest check → BAKE unlock | ⬜ |
| DRC-9 | Unit tests (15+ tests) | ⬜ |
| DRC-10 | FFI bridge + Dart bindings | ⬜ |
| DRC-11 | Manifest viewer UI + certification status panel | ⬜ |
| DRC-12 | .fftrace file save/load + diff viewer | ⬜ |

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

## P-SAM: Smart Authoring Mode

**Spec:** FLUXFORGE_MASTER_SPEC.md §13
**Requires:** GEG, DPM, SAMCL, PBSE, AIL

| # | Task | Status |
|---|------|--------|
| SAM-1 | 3 UI modes framework: SMART (80% hidden), ADVANCED (full), DEBUG (raw state) | ⬜ |
| SAM-2 | 8 archetypes: CLASSIC_3_REEL, HOLD_AND_WIN, CASCADE_HEAVY, MEGAWAYS, CLUSTER_PAY, JACKPOT_HEAVY, FEATURE_STORM, TURBO_ARCADE | ⬜ |
| SAM-3 | Smart controls: Energy group (Intensity/Build Speed/Peak Aggression/Decay) | ⬜ |
| SAM-4 | Smart controls: Clarity group (Mix Tightness/Transient Sharpness/Width/Harmonics) | ⬜ |
| SAM-5 | Smart controls: Stability group (Fatigue/Peak Duration/Voice Density) | ⬜ |
| SAM-6 | Smart → engine param mapping (each control maps to multiple engine params) | ⬜ |
| SAM-7 | 9-step guided creation wizard (Archetype → Volatility → Market → GDD → Auto-config → Preview → AIL → Adjust → Bake) | ⬜ |
| SAM-8 | GDD auto-detection → archetype + profile suggestion | ⬜ |
| SAM-9 | SmartAuthoringProvider (GetIt Layer 7) | ⬜ |
| SAM-10 | Integration: SAM controls → GEG/DPM/SAMCL params | ⬜ |

---

## P-UCP: Unified Control Panel

**Spec:** FLUXFORGE_MASTER_SPEC.md §14
**Requires:** Core systems (GEG, DPM, SAMCL, Emotional Engine)

| # | Task | Status |
|---|------|--------|
| UCP-1 | Event Timeline zone (hook events, canonical events, segment boundaries) | ⬜ |
| UCP-2 | Energy/Emotional Monitor zone (5 energy domains + emotional state + intensity) | ⬜ |
| UCP-3 | Voice/Priority Monitor zone (active voices, priority scores, survival status) | ⬜ |
| UCP-4 | Spectral Heatmap zone (10 spectral roles, masking visualization) | ⬜ |
| UCP-5 | Fatigue/Stability Dashboard (fatigue index, session drift, peak duration) | ⬜ |
| UCP-6 | AIL Panel integration (ranked recommendations, impact score, apply confirm) | ⬜ |
| UCP-7 | Debug mode (raw values, priority calcs, spectral coefficients, frame hashes) | ⬜ |
| UCP-8 | Export: UCP_Session_Report.md, UCP_Energy_Graph.json, UCP_Voice_Utilization.json, UCP_Spectral_Map.json | ⬜ |

---

## P-MWUI: SlotLab Middleware UI Views

**Spec:** FLUXFORGE_MASTER_SPEC.md §17
**Note:** Providers are done (19/19). These are the 4 full view modes.

| # | Task | Status |
|---|------|--------|
| MWUI-1 | BUILD View — primary 90% workflow: behavior tree, node editor, AutoBind panel, stage assignment | ⬜ |
| MWUI-2 | FLOW View — visual pipeline: hook → gate → behavior → priority → orchestration → voice | ⬜ |
| MWUI-3 | SIMULATION View — 6 modes: Spin Sequence, Loss Streak, Win Streak, Cascade Chain, Feature, Full Session | ⬜ |
| MWUI-4 | DIAGNOSTIC View — raw state, provider values, pipeline timing, voice pool status | ⬜ |
| MWUI-5 | Template gallery UI (7 categories) with apply + customize | ⬜ |
| MWUI-6 | Export panel UI (7 formats) with format-specific options | ⬜ |
| MWUI-7 | Coverage visualization (per-node binding status, missing hooks highlight) | ⬜ |
| MWUI-8 | Inspector panel (5 tabs: Properties, Audio, Behavior, Transitions, Debug) | ⬜ |

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
| P-GEG | 12 | 0 | 12 |
| P-DPM | 10 | 0 | 10 |
| P-SAMCL | 12 | 0 | 12 |
| P-PBSE | 10 | 0 | 10 |
| P-AIL | 8 | 0 | 8 |
| P-DRC | 12 | 0 | 12 |
| P-DEV | 14 | 14 | 0 ✅ |
| P-SAM | 10 | 0 | 10 |
| P-UCP | 8 | 0 | 8 |
| P-MWUI | 8 | 0 | 8 |
| **TOTAL** | **109** | **19** | **90** |
| FUTURE (GAD+SSS) | ~25 | 0 | deferred |

---

*Last Updated: 2026-02-28 — 109 new tasks across 11 systems. Dependency order: SRC/DEV → GEG → DPM+SAMCL → PBSE → AIL+DRC → SAM+UCP → MWUI*

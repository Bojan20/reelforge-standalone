# FluxForge Studio — Master Specification

**Consolidated:** 2026-02-28
**Sources:** 21 spec documents merged into single reference
**Status:** Blueprint — implementation tracked in `.claude/MASTER_TODO.md`

---

## Table of Contents

1. [AUREXIS™ Intelligence Engine](#1-aurexis-intelligence-engine)
2. [Audio Engine SRC & Mono/Stereo](#2-audio-engine-src--monostereo)
3. [Hook Translation Architecture](#3-hook-translation-architecture)
4. [Emotional Engine](#4-emotional-engine)
5. [Global Energy Governance & Slot Profiles](#5-global-energy-governance--slot-profiles)
6. [Dynamic Priority Matrix (DPM)](#6-dynamic-priority-matrix-dpm)
7. [Spectral Allocation & Masking (SAMCL)](#7-spectral-allocation--masking-samcl)
8. [Pre-Bake Simulation Engine (PBSE)](#8-pre-bake-simulation-engine-pbse)
9. [Authoring Intelligence Layer (AIL)](#9-authoring-intelligence-layer-ail)
10. [DRC, Manifest & Safety Envelope](#10-drc-manifest--safety-envelope)
11. [Device Preview Engine](#11-device-preview-engine)
12. [Slot Audio Naming Bible](#12-slot-audio-naming-bible)
13. [Smart Authoring Mode (SAM)](#13-smart-authoring-mode-sam)
14. [Unified Control Panel (UCP)](#14-unified-control-panel-ucp)
15. [Gameplay-Aware DAW Architecture](#15-gameplay-aware-daw-architecture)
16. [Scale & Stability Suite (SSS)](#16-scale--stability-suite-sss)
17. [SlotLab Middleware Architecture](#17-slotlab-middleware-architecture)

---

## 1. AUREXIS™ Intelligence Engine

**Purpose:** Deterministic, volatility-driven, psychoacoustic slot-audio intelligence engine. Translates 9 game inputs → 10 audio control outputs. NOT a DSP effect — outputs `DeterministicParameterMap` (data only).

**Pipeline:** Game Logic → Slot Mathematics → AUREXIS Core → Parameter Map → DSP Execution → Output

**Core Modules:**
- **Volatility Translator** — stereo elasticity, energy density, escalation rate per volatility level
- **RTP Emotional Mapper** — pacing curve, spike frequency, peak elasticity per RTP band
- **Voice Collision Intelligence** — pan redistribution, Z displacement, width compression, max 2 front voices
- **Session Psycho Regulator** — HF attenuation, transient smoothing, width narrowing after threshold exceeded
- **Win Escalation Engine** — single asset → infinite scaling (width, harmonics, reverb, sub, transients)
- **Micro-Variation Engine** — deterministic via `xxhash(spriteId + eventTime + gameState + sessionIndex)`
- **Attention Vector** — `attention = Σ(eventWeight × screenPosition × priority)`
- **Platform Adaptation** — Desktop(1.0), Mobile(0.6), Headphones(1.3), Cabinet(0.4)

**Performance:** <1.5% CPU for 20 voices. SIMD-optimized RMS. Separate analysis thread.

**Status:** ✅ IMPLEMENTED (rf-aurexis crate, 88/88 tasks complete)

---

## 2. Audio Engine SRC & Mono/Stereo

**Current State:** 90% REAPER parity. 11-level LOD waveform (superior to REAPER's 3-level).

**Gaps to fix:**

| # | Gap | Priority |
|---|-----|----------|
| G1 | Playback SRC: linear interpolation → Lanczos-3 sinc | P1 |
| G2 | Fallback inconsistency: rf-file/rf-offline use 44100, rf-engine uses 48000 | P0 |
| G3 | Mono waveform display: shows 2 identical, should be 1 centered | P1 |
| G4 | No SRC quality options (Playback vs Render) | P2 |
| G5 | Project sample rate hardcoded to 48000 | P2 |

**Implementation:**
- **P0:** All `unwrap_or(44100)` → `unwrap_or(48000)` in rf-file, rf-offline
- **P1:** Enable `SampleRateConverter::convert_sinc()` (Lanczos-3, already implemented) in playback Voice. Fast path for identical rates.
- **P1:** Flutter UI: if `isStereo == false`, render 1 centered waveform
- **P2:** Project Settings: sample rate selection (44.1k–192k), SRC quality options

**Key files:** `rf-engine/src/audio_import.rs` (L622-741 SRC), `rf-engine/src/playback.rs` (L5258-5275 rate ratio), `rf-engine/src/waveform.rs` (11-level LOD)

---

## 3. Hook Translation Architecture

**Purpose:** Deterministic, O(1) translation from raw engine hooks to canonical behavior events.

**Pipeline:** Raw Hook → Normalization → Translation (hash map) → Canonical Event → Emotional Engine → Audio

**14 Canonical Events:** SPIN_START, SPIN_END, REEL_STOP, CASCADE_START, CASCADE_STEP, CASCADE_END, WIN_EVALUATE, WIN_SMALL, WIN_BIG, FEATURE_ENTER, FEATURE_EXIT, JACKPOT_TRIGGER, UI_EVENT, SYSTEM_EVENT

**Segment Resolver:** Spin (SPIN_START→SPIN_END), Cascade (CASCADE_START→CASCADE_END), Win (WIN_EVALUATE→WIN_RESOLVE). Emotional updates only at segment completion.

**Edge cases handled:** Duplicate hook bursts, same-frame reel stops, out-of-order stops, partial abort, turbo compression, engine API naming changes.

**Strict Mode:** No authoring hooks, no experimental nodes, no non-baked overrides. Certification requires strict validation.

**Status:** ✅ IMPLEMENTED (TriggerLayerProvider, hook_translation_table in middleware)

---

## 4. Emotional Engine

**7 States:** NEUTRAL → BUILD → TENSION → NEAR_WIN → PEAK → AFTERGLOW → RECOVERY

**Transitions (deterministic, counter-based):**
- NEUTRAL→BUILD: `consecutive_no_win_spins >= 2`
- BUILD→TENSION: `consecutive_no_win_spins >= 3 AND reel_stop_counter == TOTAL_REELS`
- TENSION→PEAK: `cascade_depth >= 2 OR consecutive_win_spins >= 2`
- PEAK→AFTERGLOW: `win_detected AND onSpinEnd`
- AFTERGLOW→RECOVERY: `spin_index - last_win_spin_index >= 1`
- RECOVERY→NEUTRAL: `consecutive_no_win_spins == 0`

**Intensity:** `(no_win_spins × 0.08) + (cascade_depth × 0.15) + (win_spins × 0.20)`, clamped to 1.0
**Decay:** `intensity *= 0.85` per spin (no time-based decay)

**Bake outputs:** emotional_transition_table.json, orchestration_matrix.json, decay_config.json, voice_allocation_table.json

**Status:** ✅ IMPLEMENTED (EmotionalStateProvider, 8 states in middleware)

---

## 5. Global Energy Governance & Slot Profiles

**Energy Budget:** `FinalCap = min(1.0, EI × SP × SM)` where EI=Emotional Intensity, SP=Slot Profile, SM=Session Memory

**5 Energy Domains:** Dynamic (gain), Transient (attack density), Spatial (width/motion), Harmonic (layers), Temporal (event frequency)

**9 Slot Profiles:** HIGH_VOLATILITY, MEDIUM_VOLATILITY, LOW_VOLATILITY, CASCADE_HEAVY, FEATURE_HEAVY, JACKPOT_FOCUSED, CLASSIC_3_REEL, CLUSTER_PAY, MEGAWAYS_STYLE

**5 Escalation Curves:** LINEAR, LOGARITHMIC, EXPONENTIAL, CAPPED_EXPONENTIAL, STEP_CURVE

**Session Memory (SM ∈ [0.7–1.0]):** Long loss streak softens, feature storm triggers cooldown, jackpot compresses next escalation. Spin-based only.

**Voice Budget:** PeakEnergy→90%, MidEnergy→70%, LowEnergy→50%

**Status:** ⬜ NOT YET IMPLEMENTED (spec complete, needs Rust + Dart implementation)

---

## 6. Dynamic Priority Matrix (DPM)

**Formula:** `PriorityScore = BaseWeight × EmotionalWeight × ProfileWeight × EnergyWeight × ContextModifier`

**Base Weights:** JACKPOT_GRAND=1.00, WIN_BIG=0.95, FEATURE_ENTER=0.90, CASCADE_STEP=0.70, REEL_STOP=0.65, BACKGROUND=0.50, UI=0.40, SYSTEM=0.30

**Voice Survival:** Sort by PriorityScore descending → retain until budget met → attenuate (within 10% of threshold, ×0.6) → suppress (below threshold)

**Special Rules:** Background never fully suppressed (ducking curve instead). JACKPOT_GRAND overrides normal scoring. SCI integration from PBSE.

**Bake outputs:** dpm_event_weights.json, dpm_profile_modifiers.json, dpm_context_rules.json, dpm_priority_matrix.json

**Status:** ⬜ NOT YET IMPLEMENTED (PriorityEngineProvider exists as middleware shell, needs full DPM logic)

---

## 7. Spectral Allocation & Masking (SAMCL)

**10 Spectral Roles:** SUB_ENERGY(20–90Hz), LOW_BODY(80–250Hz), LOW_MID_BODY(200–600Hz), MID_CORE(500–2kHz), HIGH_TRANSIENT(2–6kHz), AIR_LAYER(6–14kHz), FULL_SPECTRUM(80–10kHz), NOISE_IMPACT, MELODIC_TOPLINE, BACKGROUND_PAD

**Masking Resolution:** Lower priority event gets notch attenuation (–3 to –6dB), band EQ carve, harmonic attenuation, spatial narrowing, or deterministic slot shift to alternate band.

**SCI_ADV:** `overlapping_bands × HarmonicDensity × EnergyCap` — if exceeded, aggressive carve mode.

**Harmonic Density Limits:** LOW=2 layers, MID=3, PEAK=4. Excess attenuated by masking priority.

**Bake outputs:** samcl_band_config.json, samcl_role_assignment.json, samcl_collision_rules.json, samcl_shift_curves.json

**Status:** ⬜ NOT YET IMPLEMENTED

---

## 8. Pre-Bake Simulation Engine (PBSE)

**Purpose:** Deterministic stress-test before BAKE. Blocks BAKE if validation fails.

**10 Simulation Domains:** Spin sequences, loss streaks, win streaks, cascade chains, feature overlaps, jackpot escalation, turbo compression, autoplay burst, long session drift, hook burst/frame collision

**Key Metrics:** MaxEnergyCap ≤ 1.0, MaxVoiceSimultaneity ≤ VoiceBudgetCap, SCI ≤ SCI_Max, FatigueIndex ≤ Threshold, EscalationSlope ≤ ProfileLimit

**Fatigue Model:** 500-spin session → `FatigueIndex = (PeakFrequency × HarmonicDensity × TemporalDensity) / RecoveryFactor`

**Determinism Validation:** Replay identical scenario twice, compare all hashes. Mismatch = BAKE FAIL.

**Status:** ⬜ NOT YET IMPLEMENTED

---

## 9. Authoring Intelligence Layer (AIL)

**Purpose:** Deterministic advisory system, post-PBSE, pre-BAKE. Cannot block BAKE — only flags/warns/recommends.

**10 Analysis Domains:** Hook frequency, volatility pattern detection, cascade density, feature overlap intensity, emotional curve stability, energy distribution, voice utilization, spectral overlap risk, fatigue projection, session drift

**Output:** `ail_recommendation_report.json` with profile suggestion, energy adjustment, escalation curve, fatigue score, spectral warnings, critical flags.

**UI:** AIL Score (0–100), Volatility Match, Fatigue Risk, Spectral Clarity, Voice Efficiency indicators.

**Status:** ⬜ NOT YET IMPLEMENTED

---

## 10. DRC, Manifest & Safety Envelope

**DRC (Deterministic Replay Core):** Record hook sequence + state → replay → compare SHA256 per-frame hashes. Any mismatch = determinism failure.

**Trace Format (.fftrace):** JSON with trace_version, engine_version, slot_profile, hook_sequence[], state_snapshots[], final_state_hash.

**Manifest (flux_manifest.json):** Version locks for all subsystems + config_bundle_hash. Any config change invalidates build.

**Safety Envelope:** Non-negotiable limits — MAX_ENERGY=1.0, MAX_PEAK_DURATION=240 frames, MAX_VOICES=96, MAX_HARMONIC_DENSITY=4, MAX_SCI=0.85, MAX_PEAK_SESSION=40%.

**Certification:** DRC pass + PBSE pass + Envelope pass + Manifest check + Hash validation → then BAKE unlocked.

**Status:** ⬜ NOT YET IMPLEMENTED

---

## 11. Device Preview Engine

**Architecture:** Post-master monitoring-only transform. NEVER in exports. ≤0.7ms latency, <3% CPU Apple Silicon.

**8-Node DSP Chain:** Pre-Gain → Device HPF (Butterworth) → Tonal Curve EQ (5-8 biquads) → Stereo Processor (M/S) → Multiband DRC (3 bands) → Device Limiter → Distortion Model (soft-clip) → Environmental Overlay

**50 Profiles (8 categories):** 15 smartphones, 9 headphones, 6 laptop/tablet, 6 TV/soundbar, 5 BT speakers, 5 reference monitors, 4 casino/environment

**Profile Data (v3 FINAL):** 10-point FR curve, Max SPL, DRC amount, stereo width %, bass management, limiter behavior, distortion model per profile.

**Export Safety:** `assert(MonitoringLayer.active == false)` — abort if not verified.

**Thread Model:** Audio thread executes process() with pre-computed coefficients. UI thread loads profiles + computes coefficients + atomic flag. Zero locking.

**Status:** ⬜ NOT YET IMPLEMENTED

---

## 12. Slot Audio Naming Bible

**Grammar:** `<phase>_<system>_<action>_<context>_<modifiers>_<variant>.<ext>`

**Rules:** Lowercase only, underscore only, no banned words (final/new/test/fix/old/temp), numbers always prefixed (r5, c3, m10, jt_grand), one filename = one intent, AUREXIS-parseable.

**Modifier Order:** positional → mechanic-depth → level/tier → timing → device → perspective → intensity → seed/uid → version

**Phase Tokens:** base, feature, bonus, jackpot, ui, system, ambient, music, meta
**System Tokens:** spin, reel, cascade, cluster, symbol, grid, hold, respin, multiplier, collect, transform, nudge, win, countup, feature, jackpot, ladder, reveal, wheel, pick, attract, voice, music, ambient
**Action Tokens:** start, stop, land, impact, step, tick, add, stack, collect, reset, lock, unlock, expand, shrink, explode, transform, reveal, intro, loop, outro, enter, exit, trigger, open, close, select, confirm, cancel, error, notify, idle, resume, pause

**Examples:** `base_reel_stop_r3_last.wav`, `base_cascade_step_c2.wav`, `jackpot_reveal_jt_grand.wav`, `music_base_l2_loop.wav`

**Validator:** Reject uppercase, spaces, hyphens, untagged digits, banned words, unknown tokens.

**Status:** ✅ SPEC COMPLETE (AutoBind engine uses this for parsing)

---

## 13. Smart Authoring Mode (SAM)

**3 UI Modes:** SMART (default, 80% hidden), ADVANCED (full access), DEBUG (raw state)

**8 Archetypes:** CLASSIC_3_REEL, HOLD_AND_WIN, CASCADE_HEAVY, MEGAWAYS_STYLE, CLUSTER_PAY, JACKPOT_HEAVY, FEATURE_STORM, TURBO_ARCADE

**Smart Controls:** Energy (Intensity/Build Speed/Peak Aggression/Decay), Clarity (Mix Tightness/Transient Sharpness/Width/Harmonics), Stability (Fatigue/Peak Duration/Voice Density). Each maps to multiple engine params.

**9-Step Guided Creation:** Archetype → Volatility → Market → GDD Import → Auto-config → Preview → AIL Pass → Adjust → Bake. Target: <30 min.

**Status:** ⬜ NOT YET IMPLEMENTED (requires GEG, DPM, SAMCL, PBSE, AIL first)

---

## 14. Unified Control Panel (UCP)

**5 Zones:** Event Timeline, Energy/Emotional Monitor, Voice/Priority Monitor, Spectral Heatmap, Fatigue/Stability Dashboard

**AIL Panel:** Ranked recommendations (INFO/WARNING/CRITICAL), Impact Score (0–100), user confirms to apply.

**Debug Mode:** Raw emotional values, priority calculations, spectral carve coefficients, voice suppression logs, frame-by-frame hash diff.

**Exports:** UCP_Session_Report.md, UCP_Energy_Graph.json, UCP_Voice_Utilization.json, UCP_Spectral_Map.json

**Status:** ⬜ NOT YET IMPLEMENTED (requires core systems first)

---

## 15. Gameplay-Aware DAW Architecture

**Dual Timeline:** Musical (bars/beats) + Gameplay (frame/event-driven with game hooks)

**8 Track Types:** Music Layer, Transient, Reel-Bound, Cascade Layer, Jackpot Ladder, UI, System, Ambient/Pad

**Track Metadata:** CanonicalEventBinding, SpectralRole, EmotionalBias, EnergyWeight, DPM_BaseWeight, VoicePriorityClass, HarmonicDensityContribution, TurboReductionFactor, MobileOptimizationFlag

**Bake To Slot (11 steps):** Freeze tracks → Validate metadata → Generate stems → Build mapping → DPM config → SAMCL role map → PBSE → Safety Envelope → DRC hash → Update Manifest → Create .fftrace

**Status:** ⬜ FUTURE (requires all core systems to be complete)

---

## 16. Scale & Stability Suite (SSS)

**Multi-Project Isolation:** Per-project manifest, configs, profiles, replay, regression, burn_tests, exports. No shared mutable config.

**Config Diff Engine:** Detect structural/behavioral changes, risk_level, regression_required flag.

**Auto Regression:** On config change → run 10 .fftrace sessions + stress scenarios → validate hash match.

**Burn Test:** 10,000 deterministic spins → measure energy drift, harmonic creep, spectral bias, voice trend, fatigue accumulation.

**Version Evolution:** Manifest locking with engine_version, config_bundle_hash, regression_suite_version, certification_hash.

**Status:** ⬜ FUTURE (enterprise feature)

---

## 17. SlotLab Middleware Architecture

**Full Spec:** `SlotLab_Middleware_Architecture_Ultimate.md` (v6.0, 1,873 lines, 39 sections)

**10-Layer Pipeline:** Engine Trigger → State Gate → Behavior Event → Priority Engine → Emotional State (parallel) → Orchestration → AUREXIS Modifier → Voice Allocation → DSP Execution → Analytics Feedback

**22 Behavior Nodes:** Replace 300+ raw hooks. Categories: REELS (Stop/Land/Anticipation/Nudge), CASCADE (Start/Step/End), WIN (Small/Big/Mega/Countup), FEATURE (Intro/Loop/Outro), JACKPOT (Mini/Major/Grand), UI (Button/Popup/Toggle), SYSTEM (SessionStart/End/Error)

**AutoBind:** 80%+ automatic coverage from filename parsing. 7-step pipeline: parse → phase → system → action → modifiers → behavior node → engine hook. Fuzzy matching fallback (70–90% confidence).

**6 Playback Modes:** one_shot, loop, loop_until_stop, retrigger, sequence, sustain
**6 Transition Types:** cut, crossfade, fade_out_fade_in, stinger_bridge, tail_overlap, beat_sync
**6 Contexts:** base, freespin, bonus, hold_and_win, gamble, jackpot_wheel
**8 Voice Pools:** Reel(10), Cascade(8), Win(6), Feature(8), Jackpot(4), UI(4), Ambient(4), Music(4)
**15-Bus Hierarchy:** Master → Music(Base/Wins/Feature) + SFX(Reels/Wins/Anticipation/Cascade/Jackpot) + Voice(Announcer/Celebration) + UI(Feedback) + Ambience(Casino)

**4 View Modes:** BUILD (90% workflow), FLOW (visualization), SIMULATION (6 modes), DIAGNOSTIC (advanced)
**7 Templates:** Standard 5-Reel, Megaways, Hold & Win, Cluster Pays, Jackpot Wheel, Buy Feature, Blank
**7 Export Formats:** .ffpkg, Wwise .bnk, FMOD .bank, Unity .unitypackage, Raw Stems, JSON Manifest, Compliance Report

**Status:** ✅ MIDDLEWARE PROVIDERS IMPLEMENTED (19/19). UI/panels partially implemented. Full Build/Flow/Simulation/Diagnostic views NOT yet built.

---

## System Architecture Hierarchy

```
Game Logic Layer
  └── Slot Mathematics (RTP/Volatility/Feature State)
      └── Hook Translation (O(1) hash map)
          └── State Gate (gameplay substate validation)
              └── Behavior Event Resolution (22 nodes)
                  └── Emotional State Engine (7 states, parallel)
                  └── Priority Engine (DPM, 6 classes)
                      └── Energy Governance (5 domains, 9 profiles)
                          └── SAMCL (10 spectral roles)
                              └── Orchestration Engine
                                  └── AUREXIS™ Modifier (30+ params)
                                      └── Voice Allocation (8 pools)
                                          └── DSP Execution
                                              └── Analytics Feedback Loop
```

**Validation Pipeline (pre-BAKE):** PBSE → Safety Envelope → AIL → DRC → Manifest Lock → BAKE

**Monitoring (non-export):** Device Preview Engine (50 profiles, 8-node DSP)

---

*© FluxForge Studio — Consolidated Master Specification*

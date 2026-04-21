# FluxForge Studio — Master Specification

**Consolidated:** 2026-03-25 | **Sources:** 21 spec documents | **Implementation:** `.claude/MASTER_TODO.md`

---

## System Overview

| # | System | Status | Summary |
|---|--------|--------|---------|
| 1 | AUREXIS Intelligence Engine | DONE | Deterministic psychoacoustic engine. 9 inputs → 10 outputs. <1.5% CPU/20 voices |
| 2 | Audio Engine SRC & Mono/Stereo | 90% | 11-level LOD waveform. Gaps: sinc SRC, mono display, project SR selection |
| 3 | Hook Translation | DONE | O(1) hash map, 14 canonical events, segment resolver, strict mode |
| 4 | Emotional Engine | DONE | 7 states, counter-based transitions, intensity formula, spin-based decay |
| 5 | Global Energy Governance | SPEC | `FinalCap = min(1.0, EI×SP×SM)`, 5 domains, 9 slot profiles, 5 escalation curves |
| 6 | Dynamic Priority Matrix | SPEC | `PriorityScore = Base×Emotional×Profile×Energy×Context`, voice survival sorting |
| 7 | SAMCL (Spectral Allocation) | SPEC | 10 spectral roles, masking resolution, harmonic density limits |
| 8 | Pre-Bake Simulation (PBSE) | SPEC | 10 simulation domains, fatigue model, determinism validation |
| 9 | Authoring Intelligence (AIL) | SPEC | 10 analysis domains, advisory only (no BAKE blocking), AIL Score 0-100 |
| 10 | DRC, Manifest & Safety | SPEC | Deterministic replay, .fftrace format, manifest hash locks, safety envelope |
| 11 | Device Preview Engine | SPEC | 8-node DSP chain, 50 profiles, monitoring-only, ≤0.7ms, never in exports |
| 12 | Slot Audio Naming Bible | DONE | `<phase>_<system>_<action>_<context>_<modifiers>_<variant>.<ext>`, validator |
| 13 | Smart Authoring Mode | SPEC | 3 UI modes, 8 archetypes, 9-step guided creation (<30 min) |
| 14 | Unified Control Panel | SPEC | 5 zones, AIL panel, debug mode, session reports |
| 15 | Gameplay-Aware DAW | FUTURE | Dual timeline (musical + gameplay), 8 track types, 11-step Bake To Slot |
| 16 | Scale & Stability Suite | FUTURE | Multi-project isolation, config diff, auto regression, 10k burn test |
| 17 | SlotLab Middleware | 98% | 10-layer pipeline, 22 behavior nodes, AutoBind, 6 playback modes, 15-bus hierarchy. 19/19 providers done, UI done |
| 18 | Plugin Hosting (VST3/AU/CLAP/LV2) | DONE | Full dlopen lifecycle, PDC, multi-output (64ch), MIDI instruments, null-safe Drop. GUI: AU ✅, VST3 partial, CLAP/LV2 TODO |
| 19 | MIDI Instrument Pipeline | DONE | MidiBuffer in process(), TrackType::Instrument, MIDI clip rendering in audio loop, plugin lifecycle, project save/load |
| 20 | Multi-Output Routing | DONE | Per-channel bus destinations via PinConnector, 32 stereo pairs (64ch), race-condition safe single try_read() scope |
| 21 | Project Save/Load | DONE | rf-bridge project_ffi.rs, automation CurveType (6 variants), ParamId reconstruction, clip properties (reversed/pitch/stretch), sample_rate guard |
| 22 | HELIX Neural Slot Design | DONE | 12 dock panela (FLOW/AUDIO/MATH/TIMELINE/INTEL/EXPORT/SFX/BT/DNA/AI GEN/CLOUD/A/B), spine panels, audio drag-drop, Spectral DNA auto-bind, compliance validator (UKGC/MGA/SE), 60+60+25 test suite |
| 23 | QA Bug Audit | DONE | 84/84 bagova reseno. Poslednji fix: #15 otool, #22 wgpu poll, #51 dead code, #73 automation badge, Spectral DNA FFI |

---

## Key Formulas & Parameters

**Emotional Intensity:** `(no_win_spins × 0.08) + (cascade_depth × 0.15) + (win_spins × 0.20)`, clamped 1.0, decay `×0.85/spin`

**Energy Budget:** `FinalCap = min(1.0, EI × SlotProfile × SessionMemory)` — SM ∈ [0.7–1.0]

**Priority:** `PriorityScore = BaseWeight × EmotionalWeight × ProfileWeight × EnergyWeight × ContextModifier`

**Safety Envelope:** MAX_ENERGY=1.0, MAX_VOICES=96, MAX_HARMONIC_DENSITY=4, MAX_SCI=0.85, MAX_PEAK_SESSION=40%

---

## AUREXIS Core Modules

Volatility Translator, RTP Emotional Mapper, Voice Collision Intelligence, Session Psycho Regulator, Win Escalation Engine, Micro-Variation Engine (`xxhash`-based), Attention Vector, Platform Adaptation (Desktop 1.0, Mobile 0.6, Headphones 1.3, Cabinet 0.4)

---

## Emotional Engine — 7 States

NEUTRAL → BUILD (≥2 no-win) → TENSION (≥3 no-win + all reels) → PEAK (cascade≥2 or win≥2) → AFTERGLOW (win detected) → RECOVERY (+1 spin) → NEUTRAL (no-win=0)

---

## SlotLab Middleware

**Pipeline:** Engine Trigger → State Gate → Behavior Event (22 nodes) → Priority → Emotional (parallel) → Orchestration → AUREXIS → Voice Allocation (8 pools) → DSP → Analytics

**AutoBind:** 80%+ auto coverage from filename parsing, 7-step pipeline, fuzzy fallback (70-90%).

**Resources:** 6 playback modes, 6 transition types, 6 contexts, 8 voice pools, 15-bus hierarchy, 4 view modes, 7 templates, 7 export formats.

---

## Validation Pipeline (pre-BAKE)

PBSE → Safety Envelope → AIL → DRC → Manifest Lock → BAKE

---

## System Architecture Hierarchy

```
Game Logic → Slot Mathematics → Hook Translation (O(1))
  → State Gate → Behavior Events (22 nodes)
    → Emotional Engine (7 states) + Priority Engine (DPM)
      → Energy Governance (5 domains, 9 profiles)
        → SAMCL (10 spectral roles) → Orchestration
          → AUREXIS (30+ params) → Voice Allocation (8 pools)
            → DSP Execution → Analytics Feedback
```

Monitoring (non-export): Device Preview Engine (50 profiles, 8-node DSP)

**Plugin Latency Compensation:** `AdjustedSample = SampleIndex - PluginLatency + ChainLatency`

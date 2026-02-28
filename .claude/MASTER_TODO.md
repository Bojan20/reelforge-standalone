# FluxForge Studio — MASTER TODO

**Updated:** 2026-02-28
**Status:** ✅ **SHIP READY** — All DSP processors complete, Master Bus implemented
**Full backup:** `.claude/docs/MASTER_TODO_FULL_BACKUP_2026_02_27.md` (3,526 lines, complete history)

---

## 🎯 CURRENT STATE

```
FEATURE PROGRESS: 100% COMPLETE (all shipped tasks)
ANALYZER WARNINGS: 0 errors, 0 warnings ✅
DAW MIXER: Pro Tools 2026-class — ALL 5 PHASES COMPLETE
DSP PANELS: 16/16 premium FabFilter GUIs, all FFI connected
  - Compressor: 25 params, Pro-C 2 class (character, SC, lookahead, M/S)
  - Limiter: 14 params, Pro-L 2 class (oversampling, dither, multi-stage)
  - Reverb: 15 params, Pro-R 2 class (FDN, 5 styles, freeze)
  - Saturator: 10+65 params, Saturn 2 class (6 types, multiband, oversampling)
  - Delay: 14 params, Timeless 3 class (ducking, modulation, freeze)
  - Stereo Imager: 68 params (multiband, vectorscope, stereoize)
EQ: ProEq unified superset (FF-Q 64)
MASTER BUS: 12 insert slots (8 pre + 4 post), LUFS + True Peak metering
REPO: Clean (1 branch, no dead code)
```

**All completed milestones documented in:** `.claude/docs/MASTER_TODO_FULL_BACKUP_2026_02_27.md`

---

## ✅ COMPLETE — Master Bus Plugin Chain (2026-02-28)

**Rust Backend:** Full master insert chain (`track_id = 0`), 12 insert slots (8 pre + 4 post), all FFI functions working.
**UI:** Channel Inspector shows master-specific pre/post insert sections (8 pre + 4 post), LUFS + True Peak metering section, mixer strip insert support.
**Signal Flow:** `Input Sum → PRE-FADER INSERTS (8 slots) → MASTER FADER → POST-FADER INSERTS (4 slots) → OUTPUT`

---

## ✅ COMPLETE — All DSP Processors (Full Implementation)

All DSP processors are FULLY IMPLEMENTED with complete Rust DSP + Wrapper + FFI + Flutter UI:

### FF Compressor — Pro-C 2 Class ✅ COMPLETE
- 25 params (threshold, ratio, knee, attack, release, makeup, mix, type, character, drive, range, SC HP/LP/audition, lookahead, SC EQ, auto-threshold, auto-makeup, detection, adaptive release, host sync, M/S, knee)
- 5 meters (GR L/R, Input/Output Peak, Latency)
- Character saturation (Tube/Diode/Bright), SC filters, lookahead, 14 styles

### FF Limiter — Pro-L 2 Class ✅ COMPLETE
- 14 params (input trim, threshold, ceiling, release, attack, lookahead, style, oversampling, stereo link, M/S, mix, dither, latency profile, channel config)
- 7 meters (GR L/R, Input Peak L/R, Output True Peak L/R, GR Max Hold)
- Multi-stage gain engine, 8 styles, polyphase oversampling, dither

### FF Reverb — Pro-R 2 Class ✅ COMPLETE
- 15 params (space, brightness, width, mix, predelay, style, diffusion, distance, decay, low/high decay mult, character, thickness, ducking, freeze)
- 5 styles (Room, Hall, Plate, Chamber, Spring), FDN core

### FF Saturator — Saturn 2 Class ✅ COMPLETE
- Single: 10 params (drive, type, tone, mix, output, tape bias, oversampling, input trim, M/S, stereo link)
- Multiband: 65 params (11 global + 9×6 per-band), 6 sat types, crossover types
- Oversampled processing, M/S mode, input/output metering

### FF Delay — Timeless 3 Class ✅ COMPLETE
- 14 params (delay L/R, feedback, mix, ping-pong, HP/LP filter, mod rate/depth, stereo width, ducking, link, freeze, tempo sync)
- Modulation LFO, ducking envelope, freeze buffer

---

## 🎛️ STEREO IMAGER + HAAS DELAY — iZotope Ozone Level (2026-02-22) 📋 PLANNED

**Spec:** `.claude/architecture/HAAS_DELAY_AND_STEREO_IMAGER.md`
**Target:** iZotope Ozone Imager level or better — multiband, vectorscope, stereoize, correlation

### Problem

`STEREO_IMAGERS` HashMap in `ffi.rs:9557` has 15+ FFI functions, but `playback.rs` **NEVER calls them** — same bug pattern as previously fixed `DYNAMICS_COMPRESSORS`.

### Phase 1: StereoImager Fix (P0 — CRITICAL) — 12 tasks ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 1.1 | Add `StereoImager` field to per-track state in `playback.rs` | ✅ |
| 1.2 | Process StereoImager in track audio chain (post-pan, pre-post-inserts) | ✅ |
| 1.3 | Process StereoImager on bus chains | ✅ |
| 1.4 | Process StereoImager on master chain | ✅ |
| 1.5 | Redirect existing `stereo_imager_*` FFI functions to PLAYBACK_ENGINE | ✅ |
| 1.6 | Remove STEREO_IMAGERS HashMap (dead code after redirect) | ✅ |
| 1.7 | Add Width slider to Channel Tab `_buildFaderPanSection()` | ✅ |
| 1.8 | Add Width knob to UltimateMixer channel strip | ✅ |
| 1.9 | Wire width FFI calls from MixerProvider | ✅ |
| 1.10 | Create `StereoImagerWrapper` InsertProcessor | ✅ |
| 1.11 | Register `"stereo-imager"` in `create_processor_extended()` | ✅ |
| 1.12 | Add `DspNodeType.stereoImager` to enum | ✅ |

### Phase 2: Haas Delay (P1 — HIGH) — 7 tasks ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 2.1 | Implement `HaasDelay` DSP struct (ring buffer, LP filter, feedback) | ✅ |
| 2.2 | Create `HaasDelayWrapper` InsertProcessor (7 params) | ✅ |
| 2.3 | Register `"haas-delay"` in `create_processor_extended()` | ✅ |
| 2.4 | Add `DspNodeType.haasDelay` to enum | ✅ |
| 2.5 | Create `fabfilter_haas_panel.dart` (FF-HAAS UI — zone indicator, correlation) | ✅ |
| 2.6 | Wire into `InternalProcessorEditorWindow` registry | ✅ |
| 2.7 | Add Haas Delay A/B snapshot class | ✅ |

### Phase 3: StereoImager FabFilter Panel (P1 — HIGH) — 3 tasks ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 3.1 | Create `fabfilter_imager_panel.dart` (FF-IMG UI) | ✅ |
| 3.2 | Add A/B snapshot class for StereoImager | ✅ |
| 3.3 | Wire into `InternalProcessorEditorWindow` registry | ✅ |

### Phase 4: MultibandStereoImager — iZotope Ozone Level (P1 — HIGH) — 12 tasks ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 4.1 | Implement `LinkwitzRileyFilter` (24dB/oct crossover) | ✅ |
| 4.2 | Implement `BandImager` struct (per-band width) | ✅ |
| 4.3 | Implement `MultibandStereoImager` struct (4-band + crossovers) | ✅ |
| 4.4 | Implement `Stereoize` allpass-chain decorrelation | ✅ |
| 4.5 | Create `MultibandImagerWrapper` InsertProcessor (17 params) | ✅ |
| 4.6 | Register `"multiband-imager"` in `create_processor_extended()` | ✅ |
| 4.7 | Add `DspNodeType.multibandImager` to enum | ✅ |
| 4.8 | Create `fabfilter_multiband_imager_panel.dart` (FF-MBI UI) | ✅ |
| 4.9 | Crossover frequency display with mini-spectrum | ✅ |
| 4.10 | Band link toggle + global width control | ✅ |
| 4.11 | A/B snapshot class for MultibandImager | ✅ |
| 4.12 | Wire into `InternalProcessorEditorWindow` registry | ✅ |

### Phase 5: Vectorscope & Metering (P2 — MEDIUM) — 4 tasks ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 5.1 | Create `VectorscopeWidget` (3 modes: Polar Sample, Polar Level, Lissajous) | ✅ |
| 5.2 | FFI: `stereo_imager_get_vectorscope_data()` → raw L/R pairs | ✅ |
| 5.3 | Integrate vectorscope into FF-IMG and FF-MBI panels | ✅ |
| 5.4 | Real-time stereo width spectrum display (per-frequency width) | ✅ |

### Phase 6: Testing & Polish (P2 — MEDIUM) — 7 tasks

| # | Task | Status |
|---|------|--------|
| 6.1 | Unit tests for HaasDelay (mono compat, phase, edge cases) | ✅ |
| 6.2 | Unit tests for StereoImager in signal chain | ✅ |
| 6.3 | Unit tests for MultibandStereoImager (crossover, per-band) | ✅ |
| 6.4 | Unit tests for Stereoize decorrelation | ✅ |
| 6.5 | Correlation meter widget for Channel Tab (compact bar) | ✅ |
| 6.6 | Dart unit tests for all panel snapshots | ✅ |
| 6.7 | Mono compatibility check button on all stereo panels | ✅ |

**Total: 45 tasks (45 ✅ / 0 ⬜), ~5,260 LOC across 6 phases — COMPLETE**

**Signal Flow (SSL canonical):**
```
Input → Pre-Fader Inserts → Fader → Pan → ★ STEREO IMAGER → Post-Fader Inserts (incl. Haas) → Sends → Bus
```

---

## 🔗 UNIFIED TRACK GRAPH — DAW ↔ SlotLab Shared Engine 📋 PLANNED

**Spec:** `.claude/architecture/UNIFIED_TRACK_GRAPH.md`
**What:** DAW and SlotLab share the SAME rf-engine. One audio graph, two UI views. Zero sync, zero export, zero degradation. SlotLab creates events → event folders appear in DAW left panel with layer tracks. Sound designer drags layers into timeline to edit/mix. All audio changes are instant in both directions.

**Key Rules:**
- Structure (events/layers): one-way SlotLab → DAW (read-only folders in DAW)
- Audio params (vol/pan/fx/sends): bidirectional DAW ↔ SlotLab (same provider)
- Tracks live in event folders in DAW left panel, manually dragged to timeline when editing
- Track reuse across events (same track can be layer in multiple events)

### Phase 1: EventFolder Data Model + Provider (~800 LOC) ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 1.1 | Define `EventFolder` model (id, eventId, name, color, childTrackIds) | ✅ |
| 1.2 | Define `LayerRef` model (trackId, condition, weight, layerIndex) | ✅ |
| 1.3 | Create `EventFolderProvider` (GetIt singleton, Layer 5) | ✅ |
| 1.4 | Wire `createFolderForEvent()` — auto via CompositeEventSystemProvider listener | ✅ |
| 1.5 | Wire `removeFolderForEvent()` — auto via CompositeEventSystemProvider listener | ✅ |
| 1.6 | Wire `updateFolderLayers()` — auto via CompositeEventSystemProvider listener | ✅ |
| 1.7 | Register in `service_locator.dart` | ✅ |

### Phase 2: DAW Left Panel — Event Folder UI (~1,200 LOC) ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 2.1 | Create `EventFolderPanel` widget for DAW left zone | ✅ |
| 2.2 | Render event folders with lock icon (read-only structure) | ✅ |
| 2.3 | Render child layer tracks with name, color, type icon | ✅ |
| 2.4 | Folder collapse/expand toggle | ✅ |
| 2.5 | Event type badge + color coding (spin=orange, win=gold, etc.) | ✅ |
| 2.6 | Drag layer track from folder → DAW timeline (Draggable<EventLayerRef>) | ✅ |
| 2.7 | Visual indicator when layer is in timeline vs. only in folder | ✅ |
| 2.8 | Context menu: "Open in SlotLab" → switches to SlotLab tab | ✅ |

### Phase 3: SlotLab → DAW Folder Sync (~600 LOC) ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 3.1 | SlotLab event create → auto-create DAW event folder | ✅ |
| 3.2 | SlotLab event delete → auto-remove DAW event folder | ✅ |
| 3.3 | SlotLab add layer → add track to folder + rf-engine | ✅ |
| 3.4 | SlotLab remove layer → remove track from folder | ✅ |
| 3.5 | SlotLab reorder layers → reorder tracks in folder | ✅ |
| 3.6 | SlotLab rename event → update folder name | ✅ |

### Phase 4: Bidirectional Audio Param Sync (~400 LOC) ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 4.1 | Verify DAW volume/pan/mute changes reflect in SlotLab layer view | ✅ |
| 4.2 | Verify SlotLab layer volume/pan changes reflect on DAW faders | ✅ |
| 4.3 | Verify insert add/remove/param changes sync both ways | ✅ |
| 4.4 | Verify send level changes sync both ways | ✅ |
| 4.5 | Verify output bus assignment sync both ways | ✅ |

### Phase 5: Track Reuse + Advanced Features (~500 LOC) ✅ COMPLETE

| # | Task | Status |
|---|------|--------|
| 5.1 | Support same track as layer in multiple events | ✅ |
| 5.2 | Show shared track indicator in folder (appears in N events) | ✅ |
| 5.3 | Variant sub-groups within event (A/B/C variants with weight) | ✅ |
| 5.4 | Conditional layers (minMultiplier, bet threshold) | ✅ |
| 5.5 | Crossfade settings per event folder (in/out ms, curve) | ✅ |

**Total: 31 tasks (31 ✅), ~3,500 LOC across 5 phases — ALL COMPLETE**

---

## 🧠 AUREXIS™ — Slot Audio Intelligence Engine 📋 PLANNED

**Specs:**
- `.claude/architecture/AUREXIS_INTEGRATION_ARCHITECTURE.md` — Engine-level (Rust FFI, determinism)
- `.claude/architecture/AUREXIS_UNIFIED_PANEL_ARCHITECTURE.md` — UI-level (profile-driven panel)

**What:** Deterministic, mathematically-aware, psychoacoustic intelligence engine that translates slot mathematics into audio behavior. Orchestrates ALL audio parameters (stereo width, HF attenuation, reverb, transients, panning, sub-bass) based on volatility, RTP, win magnitude, and session fatigue.

**Key Principle:** AUREXIS outputs `DeterministicParameterMap` (data only) — never processes audio. Pure intelligence layer, consumers decide.

**New Crate:** `rf-aurexis` — NO dependency on rf-ale, rf-engine, rf-dsp.

### Part A: Engine Integration (~13,000 LOC, 37 tasks)

| Phase | Name | Priority | Tasks | LOC |
|-------|------|----------|-------|-----|
| M8 | Core + Volatility Profile + Collision Resolver | P0 | 11 | ~3,950 |
| M9 | Psychoacoustic Regulator + Platform Adaptation | P1 | 9 | ~2,850 |
| M10 | Escalation Engine + Predictive + RTP Fairness | P1 | 11 | ~3,250 |
| M11 | QA Framework + Advanced Panel + Visualizers | P2 | 6 | ~2,950 |

**FFI:** ~40 functions in `aurexis_ffi.rs` (follows `ale_ffi.rs` template)
**Dart:** `AurexisProvider` at GetIt Layer 6

### Part B: Unified Panel (~5,850 LOC, 10 phases)

Consolidates 11 independent audio systems + 1000+ scattered parameters into ONE cohesive panel with profile-driven defaults.

| Phase | Name | Priority | LOC |
|-------|------|----------|-----|
| 1 | AUREXIS Provider + Profile System (12 built-in profiles) | P0 | ~800 |
| 2 | AUREXIS Panel Widget (4 sections) | P0 | ~1,200 |
| 3 | Behavior Resolution Engine | P0 | ~500 |
| 4 | System Integration (ALE/Spatial/RTPC/DSP/etc.) | P1 | ~600 |
| 5 | Lower Zone Consolidation (20+ panels → 3 tabs) | P1 | ~400 |
| 6 | Jurisdiction Engine (GLI-11 compliance, LDW detection) | P1 | ~650 |
| 7 | Memory Budget Bar + Coverage Heatmap | P1 | ~500 |
| 8 | Cabinet Simulator + Compliance Report | P2 | ~550 |
| 9 | Re-Theme Wizard + Audit Trail | P2 | ~650 |
| 10 | Dead Code Cleanup + Removal | P2 | ~negative |

**Total AUREXIS: 47 tasks, ~18,850 LOC across 14 phases (4 engine + 10 panel)**

---

*Last Updated: 2026-02-28 — Master Bus Plugin Chain + All DSP Upgrades verified complete. Full history in backup.*

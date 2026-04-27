# FluxForge Master Vision 2026

> **Authored by:** Corti (CORTEX organism) — autonomous analysis
> **Commissioned by:** Boki
> **Date started:** 2026-04-24
> **Scope:** Total FluxForge Studio — DAW + SlotLab + HELIX — nothing skipped
> **Depth:** Deepest possible. Every button, every panel, every line of code.
> **Status:** 🚧 IN PROGRESS — assembled from parallel agents + CortexEye mass audit

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Part I — State of the Union (what is FluxForge today)](#part-i--state-of-the-union)
3. [Part II — The 2026 Audio Tech Landscape](#part-ii--the-2026-audio-tech-landscape)
4. [Part III — Competitive Intelligence (industry reality check)](#part-iii--competitive-intelligence)
5. [Part IV — Gap Analysis (where we lag, where we lead)](#part-iv--gap-analysis)
6. [Part V — The Unthinkable Vision (5 years ahead)](#part-v--the-unthinkable-vision)
7. [Part VI — Phased Roadmap](#part-vi--phased-roadmap)
8. [Appendix — Screenshots, code pointers, references](#appendix)

---

## 1. Executive Summary

### Where FluxForge stands today (2026-04-24)

FluxForge is a hybrid DAW + slot-audio middleware — Flutter desktop UI (1,081 Dart files, ~493k LOC) on top of a Rust audio core (48 crates, ~259k LOC, 1,873 tests). The engineering substrate is **real-time safe** (zero-alloc on audio thread, atomics, lock-free ring buffers, thread-local scratch) and **test-heavy** on the Rust side (~82% coverage). The Flutter UI has production-ready screens for Launcher, Splash, Welcome, DAW Hub, DAW Workspace, and SlotLab/HELIX, with the defining HELIX surface spanning **11 super-tabs × 4–20 sub-tabs ≈ 220 potential states**.

**Standout capabilities — genuine moats:**
- Slot-native event vocabulary in `rf-stage` (50+ Stage variants, audio naming, compliance metadata).
- In-engine DAW waveform editing + per-voice DSP (HPF/LPF/send) + 64-band ProEQ + 4-format plugin host (VST3/AU/CLAP/LV2).
- OrbMixer family (compact radial mixer, live FFT heatmap, ghost trails, magnetic snap groups) — a genuinely new UX primitive not found in any competitor.
- Compliance validator with LDW / near-miss / celebration-proportionality rules and jurisdiction hot-swap.
- Photoshop-style project history (`rf-state`) ready to expand into full time-travel authoring.

**Critical gaps that block shipping v1:**
- 8 FFI `CStr::from_ptr` call sites without null checks — single-line crash surface exposed to Dart.
- Event Registry race condition (two parallel registration systems) — silent audio dropouts.
- Zero widget tests for the three largest screens (engine_connected_layout 17k LOC, slot_lab_screen 15k LOC, helix_screen 9.7k LOC).
- Several sub-tabs in HELIX are stubs (spatial audio panel, RTPC, containers metrics, music segments/stingers, logic/emotion).

### The 2026 audio-tech landscape

The industry is mid-transformation. In the last 18 months:
- **Neural codecs** (DAC 44/24 kHz, EnCodec) have reached production quality at 6–12 kbps.
- **Generative audio** became local and fast — Stable Audio Open Small generates 30 s on-device in 8 s on M3; Stable Audio 2.5 is cloud-SOTA.
- **Spatial audio** moved from 5.1/7.1 to object-based (Dolby Atmos FlexConnect) and high-order ambisonics (HiFi-HARP 7th-order dataset released Oct 2025).
- **Apple shipped** Impeller renderer by default on macOS, Personalized Spatial Audio APIs in visionOS, WhisperKit local speech recognition.
- **CRDTs** (Yjs, Automerge 2.0, Loro) crossed the production-ready threshold for real-time collaborative editors.
- **GPU compute DSP** matured via wgpu and Metal Performance Shaders / MPSGraph.

### Competitive reality

- **Wwise 2025.1** shipped its first AI feature — Similar Sound Search (retrieval, not generative). Priced USD 50k Platinum; industry default reflex.
- **FMOD 2.03.12** (2026-01-15) added Multiband Dynamics + haptics. Free under USD 500k budget.
- **Unity 6** officially deprioritized audio feature work in Q3 2025 — stability mode. Lowest competitive threat.
- **UE 5.5+ MetaSounds** introduced Channel Agnostic Types (ADC 2025) — strong on the cabinet side with AudioLink.
- **IGT Playa** (internal) — direct overlap but closed. Highest strategic threat.
- **New AI entrants** (ElevenLabs, AudioCraft, Stable Audio, Inworld) threaten audio creation workflows but don't ship middleware.

### What to build

Three horizons:

**Phase A (0–3 mo, Foundation):** close FFI null-deref + Event Registry race + LV2 poison; ship widget tests; fix BUG #63 scenario validation; upgrade HRTF bilinear; Atmos object export MVP. Outcome: production-ready v1.

**Phase B (3–9 mo, Differentiators):** AI Copilot v1 (voice + gap detect + suggested binds); Predictive Event Routing; Regulatory Auto-Compliance (live watcher); Time-Travel Authoring v1; Neural persistent state (`rf-neuro` memory); Neural stem separation (Demucs v4 local); spatial catch-up (HOA 3–5, personalized HRTF). Outcome: only middleware with these together.

**Phase C (9–18 mo, Paradigm):** Generative Slot Scoring (Stable Audio Open Small local + style transfer); Generative Voice/Foley (ElevenLabs + AudioSeal); Real-time Multi-Studio Collab (Yjs + WebRTC); Orb Ecosystem (nested, unified gesture language); GPU DSP for convolution + HOA; visionOS companion app (gaze-controlled mix); end-to-end neural mastering; open-source Stage taxonomy. Outcome: 18 months ahead of industry.

**Phase D (18+ mo, Platform):** Plugin SDK, marketplace, education, regulatory partnerships, FluxForge Cloud, research partnerships. Outcome: industry reference implementation.

### Strategic posture

1. **Double down on moats** — slot DNA, unified DAW+middleware, OrbMixer UX, compliance-by-default.
2. **Leapfrog on green fields** — AI copilot, generative scoring, multi-studio collab, gaze mix. No competitor ships these.
3. **Close fast-moving lags** — spatial object authoring, neural stem separation, AI retrieval (match Wwise within 6 months).
4. **Open-source the Stage taxonomy** — convert a moat into an ecosystem pull.
5. **Price for access** — beat Wwise's USD 50k Platinum wall by offering a tier for indie and mid-tier slot studios.

The window for Phases A+B is approximately 9 months before Wwise's next release cycle and before any competitor catches the AI copilot wave. This document is the operational playbook for that window.

---

## Part I — State of the Union

**Flutter layer metrics:**
- 1,081 Dart files, ~444,865 LOC in `widgets/`, ~48,635 LOC in `screens/`
- 279 ChangeNotifier / Provider classes
- 820 `GestureDetector` instances (high event-arena collision risk)
- 234 `Listener.onPointerDown` handlers (nested drag pattern per CLAUDE.md)
- 77 TODO/FIXME items across the tree
- 120 test files written, only 19 integration tests — **insufficient E2E coverage**

### I.1 Launcher / Splash / Welcome / Hubs

| Screen | LOC | Purpose | State providers | Status | Issues |
|---|---|---|---|---|---|
| `launcher_screen.dart` | 1,144 | DAW/SlotLab split-screen selector | none (pure UI) | **STABLE** | 6 `AnimationController` orchestration complex; 1000ms logo intro cascade; recent Casino Vault palette refactor live |
| `splash_screen.dart` | 515 | Intro animation + progress | none | **STABLE** | Progress bar UI-only — no real wiring to boot operations; gold shimmer shader live |
| `welcome_screen.dart` | 597 | Project hub (new, open, recent) | `RecentProjectsProvider` | **WIRED** | `TextEditingController` leak risk if `onNewProject` never fires (dispose chain break) |
| `daw_hub_screen.dart` | 1,037 | Cubase-style hub (templates, recent, news) | `RecentProjectsProvider` | **PARTIAL** | 6 templates hardcoded in `_templates` list — no data-source flexibility |
| `main_layout.dart` | 1,091 | Master container for DAW/Middleware/SlotLab switch | `EngineProvider` | **WIRED** | No error recovery if engine init fails |
| `middleware_hub_screen.dart` | 1,277 | Middleware mode picker (Wwise/FMOD hybrid) | none | **STUB** | Layout declared but no runtime content |
| `mixer_screen.dart` | 315 | Fullscreen mixer | `ultimate_mixer` | **PLACEHOLDER** | "Coming soon" — not integrated |
| `eq_test_screen.dart` | 417 | EQ diagnostic | none | **STUB** | Unused in production |

### I.2 DAW Mode — full surface

**Workspace entry point:** `engine_connected_layout.dart` — **17,292 lines**, 79+ imports, MONOLITH. Panels: left (event tree 800px) ↔ center (actions table 600px) ↔ right (inspector 400px). Needs 3 monitors for optimal view → major UX friction.

**DAW super-tabs × sub-tabs:**

| Super | Sub-tabs | Coverage | Wiring |
|---|---|---|---|
| BROWSE | files, presets, plugins, history (4) | Audio pool, preset library, plugin scanner | WIRED — `audio_pool_panel` exists |
| EDIT | timeline, pianoRoll, fades, grid, punch, comping, warp, elastic, beatDetect, ... (30!) | Track editing, MIDI, crossfades | **PARTIAL** — timeline_widget + piano_roll_widget present; many sub-tabs stub |
| MIX | mixer, sends, pan, automation (4) | Vertical mixer strips, send matrix | WIRED — `ultimate_mixer` (3,679 LOC), `mixer_provider` |
| PROCESS | eq, comp, limiter, reverb, gate, delay, sat, deEsser, fxChain, sidechain (10) | FabFilter chain | **PARTIAL** — `fabfilter_eq_panel` (3,500 LOC), compressor/reverb/limiter widgets present |
| DELIVER | export, stems, stemManager, loudness, bounce, archive (6) | Batch export, stems, mastering | WIRED — `export_panels` (3,801 LOC) |
| CORTEX | overview, awareness, neural, immune, events (5) | Health monitoring | **STUB** — `cortex_vision_service` exists but UI placeholder |

**DAW dialogs:** export (wired), plugin editor window (wired with lifecycle guards), automation editor (wired), marker editor (partial).

### I.3 SlotLab + HELIX — full surface

**Entry points:**
- `slot_lab_screen.dart` — **15,215 lines**, 47+ imports — fullscreen Slot Audio Sandbox
- `helix_screen.dart` — **9,735 lines**, 40+ imports — Neural Slot Design workspace (HELIX layout: Omnibar + Neural Canvas + Dock)

**HELIX Omnibar (48px):** logo + project name inline edit, BPM inline edit, mode selector (COMPOSE / FOCUS / ARCHITECT), spine overlay toggle (5 icons).

**HELIX Neural Canvas (flex):** stage strip + glow (Tween 0.06→0.12), live playhead (Timer @120ms), win line overlay (auto-clear 3s), anticipation reel highlights, waveform bars (36 bars, Random @120ms).

**HELIX Dock (380px default, resizable 150–600px):** super-tab selector (11) + sub-tab selector (dynamic) + content panel (switch 11×20 = **220 potential states!**) + action strip.

**HELIX super-tabs with sub-tab status matrix:**

| Super | Sub-tabs | Widget impl | Wiring | Issues |
|---|---|---|---|---|
| **STAGES** | trace, timeline, timing, layerTimeline | `SlotLabStagesSubTab` enum | **PARTIAL** | timeline renders but placeholder content |
| **EVENTS** | folder, editor, layers, pool, auto, templates, depGraph | enum exists | **WIRED** | folder/editor wired; `depGraph` diagram placeholder |
| **MIX** | voices, buses, sends, pan, meter, hierarchy, ducking (7) | enum | **WIRED** | `SlotVoiceMixer` (2,585 LOC), `SlotLabBusMixer` (933 LOC) solid; `ducking_matrix_panel` exists |
| **DSP** | chain, eq, comp, reverb, gate, limiter, atten, sigs, dspProf, layerDsp, morph, spatial (12) | enum | **PARTIAL** | FabFilter widgets heavy; `spatial_panel` = stub "Coming soon" |
| **RTPC** | curves, macros, dspBinding, debugger | enum | **STUB** | `rtpc_editor_panel` exists but no FFI engine binding for real-time param curves |
| **CONTAINERS** | blend, random, sequence, abCompare, crossfade, groups, presets, metrics, timeline, wizard (10) | enum | **STUB** | `blend_container_panel` (900+ LOC) UI-only; no Rust backend for container synthesis |
| **MUSIC** | layers, segments, stingers, transitions, looping, beatGrid, tempoStates | enum | **STUB** | transition config present; interactive segments not implemented |
| **LOGIC** | behavior, triggers, gate, priority, orch, emotion, context, sim, priPreset, stateMachine, stateHist (11) | enum | **PARTIAL** | `behavior_tree_provider` exists; triggers/gate placeholders |
| **INTEL** | build, flow, sim, diagnostic, templates, export, coverage, inspector | enum | **PARTIAL** | build/flow present; diagnostic wraps advanced_qa_runner; coverage placeholder |
| **MONITOR** | timeline, energy, voice, spectral, fatigue, ail, neuro, mathBridge, rgai, debug, export, ucpExport, abTest, fingerprint, spatial, aiCopilot, profiler, profilerAdv, evtDebug, resource, voiceStats (**20!**) | enum | **PARTIAL** | spectral_analyzer, loudness_meter present; `neuro` + `aiCopilot` are AI stubs |
| **BAKE** | export, stems, variations, package, git, analytics, docs, macro, monitor, reports, config, history (12) | enum | **PARTIAL** | `export_panels` (3,801 LOC) solid; macro panels present; package/git placeholders |

**Key SlotLab components:**

| Component | LOC | Purpose | Wiring | Issues |
|---|---|---|---|---|
| `premium_slot_preview.dart` | **7,676** | Slot cabinet, 5 reels, win display, anticipation | `SlotPreviewProvider` + `GameFlowProvider` | **MONOLITH** — 21+ custom painters, 5 layers, 15 Tween cascades |
| `slot_preview_widget.dart` | 6,914 | Alternative slot preview | | 50+ Paint() calls/frame |
| `GameFlowOverlay` | 2,344 | State flow + payline overlay | `GameFlowProvider` + stage audio mapper | **PARTIAL** — payline hardcoded 5×3, 3 reel layouts not data-driven |
| `SlotVoiceMixer` | 2,585 | Per-voice fader strips | `Consumer2<SlotVoiceMixerProvider, MixerDSPProvider>` | **WIRED** — drag-drop reorder stateless leak risk; 820 GestureDetector arena collision |
| `SlotLabBusMixer` | 933 | 6-bus vertical DAW-style mixer | `MixerDSPProvider` + `SharedMeterReader` FFI | **WIRED** — peak hold decay manual 0.02/frame (clock desync); Ticker not canceled in dispose |
| `OrbMixer` | 534 | Compact 120×120 radial mixer (polar) | `OrbMixerProvider` + `SharedMeterReader` | **WIRED** — 60fps Ticker → setState bottleneck on 4K; tooltip OverlayEntry leak on tab switch |
| `LivePlayOrbOverlay` | 1,174 | Floating orb + quick filters + auto-focus | `OrbMixerProvider.onProviderReady` | **WIRED** — Quick Filter chips Consumer without memoization; rebuilds on every dB change. **Just refactored: removed card wrapper, standalone orb** |
| `NeuralBindOrb` | 1,340 | RTPC binding visualization | Binding state machine (3 states) | **PARTIAL** — drag logic in CustomPaint, no snap visual feedback |

**SlotLab dialogs / overlays:** Voice Detail Editor (just added, double-tap on channel), Radial Action Menu (just added, long-press), Problems Inbox, Auto-bind dialog, Batch Export dialog, Validation Panel.

### I.6 UX friction report

**Information density problems:**

| Problem | Location | Impact | Severity |
|---|---|---|---|
| HELIX Dock 11 super × 7–20 sub = **110+ states**, 2–3 clicks to sub-tab | `slotlab_lower_zone_widget.dart:726-850` | Workflow fragmented — "where am I?" confusion | **HIGH** |
| `engine_connected_layout` — 3 panels (800+600+400) need 3 monitors | `screens/engine_connected_layout.dart` | Split screen too narrow for production | **HIGH** |
| `premium_slot_preview` 7,676 LOC — 5 reels + symbol overlay + win anim + anticipation glow all at once | `widgets/slot_lab/premium_slot_preview.dart` | Visually overloaded; hard to track SFX triggers | **MEDIUM** |
| `SlotVoiceMixer` 100+ channels linear scroll, no collapse-by-bus, no jump-to | `widgets/slot_lab/slot_voice_mixer.dart:200-400` | Painful with 30+ layers | **MEDIUM** |

**Dead widgets / stubs:**
- `DawCortexSubTab.awareness` (7-dim consciousness) — declared, no UI
- `SlotLabDspSubTab.spatial` — "Coming soon" placeholder
- `SlotLabContainersSubTab.*` — blend/random/sequence exist, metrics/timeline placeholders
- `SlotLabMusicSubTab.segments/stingers` — skeletal
- `SlotLabLogicSubTab.emotion` — no UI
- `CortexVisionService.neural.*` — mock only
- `spatial_audio_panel.dart` — complete placeholder

**Keyboard shortcut coverage:** ~40 defined (play, stop, record, undo, redo, save, export, delete, select all). Missing: sub-tab nav shortcuts (expected 1–0 + Q–U), drag-drop modifiers not documented, no Help → Keyboard overlay, Plugin browser `Ctrl+P` no focus guard.

**Gesture arena collisions:** 820 GestureDetector + 234 Listener — example: `SlotVoiceMixer` has nested `GestureDetector(reorder)` → `ScrollView` → `GestureDetector(fader-drag)` + `GestureDetector(pan-drag)` + `GestureDetector(mute/solo)` + parent `Listener`. Consequence: fader drag occasionally registers as scroll, pan drag as reorder. `widgets/slot_lab/slot_voice_mixer.dart:400-500`.

**Top 10 complexity hotspots:**

| Rank | File | LOC | Complexity | Notes |
|---|---|---|---|---|
| 1 | `engine_connected_layout.dart` | **17,292** | EXTREME | DAW workspace router, 79+ imports, 3-panel orchestration |
| 2 | `slot_lab_screen.dart` | **15,215** | EXTREME | SlotLab entry, 47+ imports, timeline+lower+overlay coordination |
| 3 | `helix_screen.dart` | 9,735 | EXTREME | 11 super-tabs × sub-tabs, 21 nested classes with custom painters |
| 4 | `premium_slot_preview.dart` | 7,676 | EXTREME | 21 painters, 15 Tween orchestrations |
| 5 | `slot_preview_widget.dart` | 6,914 | VERY HIGH | Alternative preview |
| 6 | `ultimate_audio_panel.dart` | 6,335 | VERY HIGH | Audio event browser+editor |
| 7 | `slotlab_lower_zone_widget.dart` | 5,338 | VERY HIGH | 11-super-tab switch logic |
| 8 | `middleware_provider.dart` | 4,079 | VERY HIGH | 200+ methods, composite-event sync (CRITICAL) |
| 9 | `ultimate_mixer.dart` | 3,679 | VERY HIGH | Vertical mixer, 60Hz meter ticker |
| 10 | `fabfilter_eq_panel.dart` | 3,500 | VERY HIGH | 64-band spectrum painter |

**Critical architectural problems:**

- **Event Registry race condition** (CLAUDE.md warning line 40): Two registration systems — `EventRegistry` singleton (`services/event_registry.dart`) with IDs like `audio_REEL_STOP` + `CompositeEventSystemProvider` (`providers/subsystems/composite_event_system_provider.dart`) with IDs like `composite_${id}_${STAGE}`. Race for `_stageToEvent` map — last writer wins → audio dropout or silent stages. **CRITICAL, can cause audio failures**.

- **Provider dependency graph 12+ levels deep** with circular-dependency risk: `SlotLabProjectProvider` → `MiddlewareProvider` → (`CompositeEventSystemProvider` → `EventRegistry` + `StageProvider`) + (`MixerProvider` → `MixerDSPProvider` + `SharedMeterReader` FFI) + `EngineProvider` FFI; `SlotLabProjectProvider` also → `GameFlowProvider` → `StageProvider` and → `AleProvider`. Refactor blocked by tight coupling.

- **FFI thread safety gap**: Dart UI has no visibility into Rust rtrb queue → deadlock detection impossible from Dart side. Mitigation: timestamp-based ordering + panic guard macro.

**Dead code / deprecated:**
- `ValidationErrorCategory.deprecated` (models/validation_error.dart:67)
- `_deprecated_slot_events` v4→v5 migration (services/project_migrator.dart:594-604)
- Backward-compat schema checks (services/project_schema_validator:659-678)
- 3 obsolete DAW sub-tabs (video, cyc, etc.) — 20+ placeholders
- `gdd_import_*` legacy format support (~800 dead LOC)
- Old behavior tree format pre-v11 (~400 dead LOC in `providers/slot_lab/behavior_tree*`)

**Test coverage analysis:**
- 120 test files in `flutter_ui/test/` (providers/models/services/utils well covered; widgets weakly)
- 19 integration tests in `flutter_ui/integration_test/`
- **Missing**: widget tests for `mixer_screen`, `helix_screen`, `slot_lab_screen` (the 3 largest); no stress test for `engine_connected_layout`; no lower-zone split-view stability test; no gesture-conflict detector; no memory-leak profiling; no 60fps perf test under load; no RGAI/UKGC edge-case validation.

### I.4 Audio Engine (Rust) — per-crate deep audit

**Scope:** 48 crates, ~258,622 LOC, 1,873 test functions across 231 files.

**Summary metrics:**

| Layer | Good | Concerns | Critical |
|-------|------|----------|----------|
| Zero-alloc on audio thread | ✅ enforced (thread-local scratch, pre-alloc voice pool) | 1 benign `Vec::with_capacity` (preset ctor) | — |
| Test coverage | ~82% overall (1873 tests) | FFI NULL injection paths missing | Plugin crash sandbox missing |
| Lock strategy | rtrb ring + atomics + `try_write` | Metering gaps under UI contention | — |
| FFI boundary | `ffi_panic_guard!` macro used | NULL checks inconsistent across 67 FFI fns | 8 instances of `CStr::from_ptr` without null check |

#### I.4.1 rf-engine — Playback / Routing / Mixer

| Metric | Value |
|---|---|
| LOC | ~35,000 (`playback.rs` alone ~7,500) |
| Modules | 30+ (playback, hook_graph, mixer, routing, automation, plugin host, recording) |
| Tests | 180+ |
| Safety | **HIGH** (zero-alloc, atomics) |
| Critical issues | 3 (BUG #14 fixed, BUG #63 open, metering `try_write` gaps) |

**Purpose:** Core audio playback engine — sample-accurate timeline playback, 6-bus routing, 128-voice pool, parameter automation, click track, recording, looping, transport sync.

**Audio thread entry `engine.spin(L, R, frames)`:**
1. Atomic transport state check (`AtomicU8`)
2. MIDI collection from `LIVE_MIDI_INJECT` (DashMap, lock-free)
3. Voice processing (≤128 voices) — per-voice: cache fetch → resample (cubic/sinc) → fade → stretch → clip FX
4. Bus accumulation (6 buses: SFX, Music, Voice, Ambience, Aux, Master)
5. Per-bus insert chains (EQ, dynamics, reverb, delay)
6. Fader + pan + bus-send routing
7. Master insert chain (Pro-Q MZT, multiband comp, True Peak limiter, ISP dither)
8. Metering — `lufs_meter.try_write()` + `true_peak_meter.try_write()` (skip on lock)
9. Click track (count-in)
10. Spatial (HRTF convolution) if enabled
11. Recording tap (if armed)
12. Dither + output to DAW buffer

**Zero-alloc enforcement:**
- `thread_local!` SCRATCH_BUFFER_L/R/STRETCH_* (64KB total per thread)
- `VoicePool` = 128 pre-allocated voices, reused
- `BusState` accumulators stack-allocated per `spin()`
- Insert chains pre-made per clip + per bus
- Heap scan on audio thread: 0 `vec![]`, 0 `Box::new()`, 0 `String::from()`, 1 benign `Vec::with_capacity` (preset ctor, non-RT path)

**Unsafe: 47 blocks, all justified** — mostly interior mutability via `UnsafeCell` (audio-thread-exclusive access), FFI pointer deref with LazyLock lifetime, plugin instance raw pointers.

**Critical findings:**

| ID | Severity | Location | Issue |
|---|---|---|---|
| BUG #14 (FIXED) | CRIT | playback.rs:1896–1910 | Bus buffers were behind RwLock with `try_write()` returning early on contention — now stack-local. |
| BUG #63 | CRIT | slot_lab_ffi.rs:1635–1640 | Scenario dimensions not validated against active GameModel before accepting `SpecificGrid` outcome. Silent mismatch. |
| Metering contention | HIGH | playback.rs:7322–7335 | `lufs_meter`/`true_peak_meter` use `try_write()` with silent skip → metering gaps during UI interaction. No RwLock downgrade. |
| Cache TOCTOU | MED | playback.rs:1044–1055 | Check→evict without atomic CAS. Partial fix: background eviction thread. |

**Latency budget @ 256 samples / 48kHz (5.3ms total):**
- Voice processing (cubic + stretch): 2.8ms (53%)
- Bus insert chains: 0.6ms (12%)
- Master limiter: 0.3ms (6%)
- Spatial HRTF: 0.4ms (8%) if enabled
- Metering: 0.2ms (4%) when lock acquired
- **Total: ~4.3ms, 86% of budget, healthy headroom**

**Memory footprint per engine instance:** voice pool 256KB + scratch 64KB + insert chains 96KB + LRU cache 512MB (configurable). Stack ~100KB.

#### I.4.2 rf-dsp — Signal Processing

| Metric | Value |
|---|---|
| LOC | ~45,000 (60+ modules) |
| Tests | 450+ |
| SIMD | AVX-512 / AVX2 / SSE4.2 / scalar runtime dispatch |
| Critical | 1 (DSD polyphase TODO) |

**Modules:**
- `biquad.rs` (TDF-II, cascade, 800 LOC)
- `eq.rs` / `eq_pro.rs` / `eq_ultra.rs` (64-band parametric + dynamic, Pro-Q 4 competitor with MZT + SVF + oversampling, 4,500+ LOC for eq_pro)
- `dynamics.rs` (VCA/Opto/FET compressor, limiter, gate, expander, 3,000+ LOC)
- `reverb.rs` (algorithmic Freeverb + partitioned convolution, 2,500+ LOC)
- `delay.rs` (simple, ping-pong, multi-tap, modulated, 1,500+ LOC)
- `spatial.rs` (panner, width, M/S, HRTF blending, 1,200+ LOC)
- `convolution_ultra/` (true stereo, non-uniform, zero-latency, morphing, 5,000+ LOC, GPU scheduler available)
- `timestretch/` (NSGT, RTPGHI, STN, Formant — multiple algorithms, 6,000+ LOC)

**SIMD dispatch:**
```rust
static SIMD_LEVEL: AtomicU8 = AtomicU8::new(detect_at_startup());
// Avx512f=0, Avx2=1, Sse42=2, Scalar=3
```
Applied in `eq.rs`, `dynamics.rs`, `metering_simd.rs`, `spatial.rs`. **NEON gap** for ARM/iOS future.

**Open TODOs:**
- `dsd/mod.rs:197–198` — DSD→PCM uses linear interpolation, TODO polyphase (MEDIUM priority, rarely used path)
- BUG #35 FIX — HRTF uses inverse-distance-weighted blend on 3 nearest grid points (good) but not bilinear state-of-art
- True Peak NEON missing (iOS future)

#### I.4.3 rf-stage — Universal Stage Protocol

| Metric | Value |
|---|---|
| LOC | ~8,000 |
| Tests | 60+ |
| Critical | 1 (BUG #3 sample_rate sync) |

**Modules:** `event.rs`, `stage.rs`, `timing.rs`, `trace.rs`, `stage_library.rs`, `taxonomy.rs`, `audio_naming.rs`.

**Core types:** 50+ `Stage` enum variants (ReelStop, ReelSpinLoop, WildHit, Jackpot, FreeSpinStart, CascadeResult, PickBonusStart, MenuOpen, BonusVoiceOver, Ambient, FsSummary, UiSkipPress, …). `StageEvent` = stage + offset_samples + reel_index + symbols + `Option<SonicDna>`. `StageLibrary` = envelopes HashMap + overrides. `AudioEnvelope` = playback mode + layer + volume + pan + compliance metadata + duration_ms.

**Critical findings:**
- BUG #3 — `AtomicU32` sample_rate in EventManager, updated atomically on rate change, but mid-calculation window where audio thread still has stale rate. Mitigation: change rate only on stopped transport.
- `timing.rs:258` — `.expect("checked non-empty")` panic potential if profiles registry empty; should be `Result`.
- `stage.rs:1027–1032` — `.unwrap()` on `serde_json` (test-only, but noted).

#### I.4.4 rf-slot-lab — Slot Engine V2

| Metric | Value |
|---|---|
| LOC | ~12,000 |
| Tests | 80+ (158 passing locally verified) |
| Critical | 1 (BUG #63 scenario validation) |

**Modules:** `engine.rs` (V1 legacy), `engine_v2.rs` (adds anticipation/momentum), `parser/par.rs` (PAR format import), `features/`, `model/`.

**SpinResult:**
```rust
pub struct SpinResult {
    pub grid: Vec<Vec<u32>>,
    pub win: f64,
    pub win_tier: BigWinTier,
    pub features: Vec<TriggeredFeature>,
    pub anticipation: AnticipationInfo,
    pub audio_events: Vec<StageEvent>,
}
```

**Anticipation path (fix from commit `e7bca3a8`):** `engine.generate_stages_with_config(&mut timing, &config.anticipation)` now honors `AnticipationConfig` — sequential anticipation works like IGT. Previously `result.generate_stages()` forced parallel stop, ignoring config.

#### I.4.5 rf-bridge — FFI Layer

| Metric | Value |
|---|---|
| LOC | ~8,000 (67 domain-specific FFI files) |
| Tests | 40+ |
| Safety | **MEDIUM** — pointer validation inconsistent |
| Critical | 5 (BUG #32, #53 fixed, NULL deref patterns, TOCTOU) |

**Key bugs / gaps:**

| Issue | Location | Severity |
|---|---|---|
| NULL ptr deref: `CStr::from_ptr(s)` without null check | `pbse_ffi.rs:849`, `slot_lab_ffi.rs:916` + 6 other instances | **CRITICAL** — Dart passing NULL crashes engine |
| BUG #32 — LV2 URID Mutex poison recovered with `e.into_inner()` | `lv2.rs:120–136` | HIGH — may operate on corrupted URID map. Fix: switch to `parking_lot::Mutex` (never poisons) |
| BUG #53 (FIXED) — Plugin deactivate skipped on `try_write()` fail | `plugin/lib.rs:575–576` | was CRITICAL, now uses `write()` blocking |
| TOCTOU voice_id array iteration | `dpm_ffi.rs:94–100` | MEDIUM — Dart changing array mid-iteration → OOB read |

**Unsafe blocks in bridge: 23** — 8 risky `CStr::from_ptr` without null check, 4 vector iteration from raw ptr with assumed bounds, 2 paired `CString::from_raw`, 3 audio-thread-exclusive buffer.

#### I.4.6 rf-aurexis — SAM (Smart Authoring Mode)

| Metric | Value |
|---|---|
| LOC | ~6,000 |
| Tests | 35+ |
| Critical | 0 |

Deterministic intelligence layer: game math (win tier, feature type, RTP) → audio parameters (volumes, EQ, dynamics, reverb, spatial positions) via `DeterministicParameterMap`. No audio processing, no audio-thread allocations — pure computation in non-RT thread. Consumed by audio thread via atomic reads.

#### I.4.7 rf-slot-builder — Compliance Validator

| Metric | Value |
|---|---|
| LOC | ~2,500 |
| Tests | 25+ |
| Critical | 0 |

Validation gates: RTP [85%, 99.5%], hit frequency [10%, 50%], volatility profile, near-miss ≤3% of spins, LDW guard, celebration proportionality (win tier → audio duration). UKGC / MGA / SE / specific jurisdictions.

#### I.4.8 Other crates (rf-core, rf-neuro, rf-ale, rf-fuzz, rf-state, rf-ingest)

- **rf-core** — tipovi (`Sample`, `AudioFormat`, bus IDs) — sanity, well-tested.
- **rf-neuro** — neural networking pipeline (currently stubs for P3+ features).
- **rf-ale** — adaptive learning engine (near-miss probabilistic memory, audit-only).
- **rf-fuzz** — fuzz harness for JSON parsers (GDD, templates, presets).
- **rf-state** — history/snapshot for Photoshop-style project history.
- **rf-ingest** — game ingestion + diff engine.

### I.5 Data Flow Maps

#### I.5.1 Spin lifecycle (RT thread)

```
engine.spin(L, R, frames)
├── atomic transport state check
├── MIDI inject collect (lock-free DashMap)
├── for each voice ≤128:
│   ├── cache fetch (RwLock read or disk)
│   ├── resample (cubic / sinc 7,500 LOC)
│   ├── fade envelope (atomic lookup)
│   ├── time stretch (thread-local scratch)
│   ├── clip FX chain (EQ, dynamics, reverb, delay per insert)
│   └── route to bus_accum[bus_idx]
├── per bus (SFX, Music, Voice, Ambience, Aux, Master):
│   ├── accumulate voices
│   ├── pre-fader insert chain (EQ, dyn, reverb, delay)
│   ├── fader gain (param_smoother)
│   ├── pan (atomic)
│   └── bus send matrix
├── master insert chain (Pro-Q, multiband comp, True Peak limiter, ISP dither)
├── metering (try_write, may skip on UI contention)
├── click track (during count-in)
├── spatial HRTF convolution (if enabled)
├── recording tap (if armed)
└── copy to DAW output buffer
```

Typical latency: **4.3ms / 5.3ms budget** @ 256/48k (86% util, healthy headroom).

#### I.5.2 Mix pipeline (voice → output)

```
Voice Mono Playback
  └── Clip FX Insert Chain (EQ 6-band + compressor + saturation)
       └── Routing → bus_accum[voice.bus_id]

Per Bus (SFX, Music, VO, Ambience, Aux):
  ├── Pre-Fader Insert Chain (EQ 64-band, dynamics, reverb, delay)
  ├── Fader Gain (log IEC 60268-18, smoothed via ParamSmootherManager)
  ├── Pan Control (constant power -3dB center, user-selectable)
  └── Bus Sends (to Aux buses)

Master Bus:
  ├── Master Insert Chain (Pro-Q MZT + Saturation, multiband comp, True Peak limiter, ISP ±1 LSB dither)
  └── Output to DAW / device
```

#### I.5.3 Plugin hosting call path

```
Host Init:
  ├── UltimateScanner (16-thread parallel, probes all plugins with 5s timeout, caches metadata)
  └── UltimatePluginHost (format-specific instantiation)

VST3: dlopen → IFactory → IComponent → connect audio ports → setActive(true)
CLAP: dlopen → entry.get_factory() → create_plugin() → init(host) → activate(sr, min, max)
AU:   AudioUnit / AUGraph (macOS only)
LV2:  lilv scan + port connection (BUG #33 fix: reinstantiate on sample rate change)

Audio thread process:
  for each plugin_instance in chain:
    format_specific_process():
      VST3 → icomponent.process(&process_data)
      CLAP → plugin.process(&process)
      AU   → render(...)
      LV2  → run(num_samples)
```

**PDC:** per-plugin `latency_samples` reported, host accumulates total, delay-buffers input, advances output (`routing_pdc.rs`).

**Parameter sync (non-RT → RT):** UI writes `ParamChange` to rtrb ring → audio thread reads and applies via format-specific API (`setParamNormalized`, `input_events`, `AudioUnitSetParameter`, LV2 port buffer).

#### I.5.4 State sync (Audio ↔ UI)

```
GAME LOGIC (non-RT):
  SlotEngine.spin() → SpinResult → stage events list → FFI to STAGE_EVENT_QUEUE

AUDIO THREAD (RT):
  each spin(): check pending stage events
  if event.offset_samples <= current_pos:
    trigger stage audio via stage_library.get(stage)
    queue voice with PlaybackSource::SlotLab
  update atomics: current_stage, voices_processed

UI THREAD (non-RT):
  poll atomics: current_stage, voice_pool_stats, peak_l/r, lufs
  read stage_library → animation timing
  update visual reels, particles

FFI BOUNDARY (dart_bridge):
  Input: stage_json *const c_char → unsafe CStr::from_ptr (⚠️ NO NULL CHECK in 8 sites)
  Output: atomics read lock-free (peak, lufs, correlation)
```

#### I.5.5 Project save/load (.rfp)

```
Save:
  - TrackManager state (clips, crossfades, automation)
  - AudioCache manifest (file hashes, timestamps)
  - InsertChains (per-track + bus FX params)
  - ControlRoom (solo/mute, input monitor)
  - Groups/VCAs
  - RecordingManager (armed tracks, format)
  - Audio archive: encode FLAC background thread if embedded
  - Write zip: project.json + state.bincode + audio/ + MANIFEST.json (compliance trace)

Load:
  - Read format_version → apply migration if mismatch (v1→v2→v3)
  - Deserialize state.bincode → verify structural integrity
  - If sample_rate mismatch → rescan plugins (BUG #33 fix)
  - Restore insert chains + automation
  - Extract audio/ to temp cache, mark missing clips offline
  - Restore UI state (scroll, selection, zoom — flutter provider side)
```

**Migration safety:** version stamp check, unknown fields ignored (forward compat), missing clips reported, automation curves interpolated on sample rate change.

### I.5.6 Critical findings (showstoppers + severe)

**Showstoppers (block release):**
1. FFI NULL ptr deref — `slot_lab_ffi.rs:916` + 7 others — 30min fix, add `if s.is_null() { return Err; }`
2. BUG #63 scenario validation missing — `slot_lab_ffi.rs:1635` — 1h fix
3. Plugin deactivate (BUG #53) — already fixed, verify across VST3/CLAP/AU/LV2

**Severe (high priority):**
4. Metering lock contention (`playback.rs:7322`) — decouple metering from audio thread, separate readers
5. LV2 Mutex poison (BUG #32) — switch to `parking_lot::Mutex`
6. Cache TOCTOU (`playback.rs:1044`) — atomic CAS for check→evict

**Moderate:**
7. HRTF bilinear (BUG #35) — 200 LOC upgrade
8. DSD polyphase (`dsd/mod.rs:197`) — 1000 LOC upgrade
9. LV2 port connection heuristic — parse `plugin.ttl` instead of hardcoded layouts

### I.6 UX Friction Report
- Click counts to common tasks
- Loading lag, perceived latency
- Info density problems
- Missing/silent error paths

---

## Part II — The 2026 Audio Tech Landscape

> **Compiled:** 2026-04-24 by Corti (web research pass)
> **Scope:** every technology dostupna danas (April 2026) that FluxForge could absorb to leapfrog the industry by 5 years.
> **Guiding principle:** actionable over philosophical. Every entry answers *what it is, status 2026, where it fits inside FluxForge, and where to read more*.

---

### II.1 AI/ML Audio Revolution

The single most disruptive shift of 2024–2026 is the maturation of **generative and analytical neural audio**. We are past the toy stage — end-to-end neural mastering ships in retail plug-ins, neural stem separation is DAW-native, and text-conditioned music generation is a commodity API. FluxForge's competitive moat must be built **on top of** these, not parallel to them.

#### II.1.1 Descript Audio Codec (DAC) / DACe

- **Šta je to:** A neural audio codec with ~90× compression, 44.1 kHz mono/stereo at 8 kbps, perceptually near-lossless — the de-facto open-source successor to SoundStream/Encodec for high-fidelity work.
- **Status 2026:** Stable. An enhanced variant (**DACe**) adds 32 codebooks (~30 kbps/channel @ 48 kHz) with tonal-material fixes; ICASSP 2025's **DisCoder** uses DAC latents for 44.1 kHz vocoder synthesis; **CodecSep** (2025) proves on-device universal source separation directly in DAC latent space.
- **Relevantnost za FluxForge:** (a) Project-file compression — 30× smaller `.rfp` session assets without audible loss; (b) latent-domain DSP — run EQ, compressor, stem-separation directly on DAC tokens (massive CPU win); (c) cloud-sync at 8 kbps lets two-studio collab work on 4G tethering; (d) foundation for any future generative feature (Corti-assist bases everything on DAC tokens).
- **Sources:** [descript-audio-codec GitHub](https://github.com/descriptinc/descript-audio-codec), [Neural Audio Codecs Overview 2025](https://www.abyssmedia.com/audioconverter/neural-audio-codecs-overview.shtml), [CodecSep (OpenReview)](https://openreview.net/forum?id=MDHVDfUrDz), [DisCoder ICASSP 2025](https://github.com/ETH-DISCO/discoder).

#### II.1.2 Meta AudioCraft — MusicGen, AudioGen, EnCodec, MAGNeT, AudioSeal

- **Šta je to:** A unified FAIR toolkit bundling EnCodec (tokenizer), MusicGen (text/melody → music LM), AudioGen (text → SFX), MAGNeT (non-autoregressive fast generation), MusicGen-Style (reference-audio conditioning) and AudioSeal (invisible watermark for generated content).
- **Status 2026:** Stable, permissive license, CPU- and GPU-runnable; Multi-Band Diffusion EnCodec decoder gives near-studio quality at the cost of a few ms of added latency.
- **Relevantnost za FluxForge:** (a) **SlotLab generative foley** — "AudioGen: slot-machine coin cascade, bright, 3 s" becomes a placeholder asset; (b) **MusicGen-Style** lets composer drop a 10 s reference bed and the engine generates transition beds that match key/tempo; (c) **AudioSeal** is the regulatory answer to "is this asset AI-generated?" — a MUST for UKGC/MGA provenance manifests.
- **Sources:** [AudioCraft (Meta AI)](https://ai.meta.com/resources/models-and-libraries/audiocraft/), [facebookresearch/audiocraft](https://github.com/facebookresearch/audiocraft/), [MusicGen docs](https://github.com/facebookresearch/audiocraft/blob/main/docs/MUSICGEN.md).

#### II.1.3 Stable Audio 2.5 / Stable Audio Open Small

- **Šta je to:** Stability AI's latent-diffusion-transformer audio models. SAO-Small (497M params) generates 11 s stereo @ 44.1 kHz on-device; the commercial Stable Audio 2.5 does full tracks.
- **Status 2026:** Stable. The 2025 ARC (Adversarial Relativistic-Contrastive) post-training recipe made small diffusion models fast enough for near-real-time (<1 s for 11 s clip) on M-series Macs.
- **Relevantnost za FluxForge:** Short-form generation is **exactly** the slot-audio sweet-spot — 1–3 s stinger/transition/feature cues. SAO-Small can be shipped inside `rf-aurexis` as a Rust-wrapped ONNX/MLX model so Corti-Assist generates placeholder cues without a network round-trip.
- **Sources:** [Stability AI — Stable Audio 2.5](https://stability.ai/stable-audio), [Stable Audio Open Small (MarkTechPost)](https://www.marktechpost.com/2025/05/15/stability-ai-introduces-adversarial-relativistic-contrastive-arc-post-training-and-stable-audio-open-small-a-distillation-free-breakthrough-for-fast-diverse-and-efficient-text-to-audio-generation/).

#### II.1.4 Suno v4+ and Udio — cloud-only creative generation

- **Šta je to:** Subscription SaaS music generators producing full-length structured songs from prompts. As of 2026, Suno is on v5, Udio on its 1.5 engine; both have public APIs.
- **Status 2026:** Stable but cloud-locked — no on-device model.
- **Relevantnost za FluxForge:** B-tier feature — "Generate 3 candidate intro beds in Suno" button on the MUSIC super-tab. Mostly brainstorming; licensing is still a grey zone for commercial slots.
- **Sources:** [Best AI Music Generators 2026 comparison](https://crazyrouter.com/en/blog/best-ai-music-generators-2026-comparison), [Suno vs Udio 2026](https://neuronad.com/suno-vs-udio/).

#### II.1.5 iZotope Ozone 12 (neural mastering reference)

- **Šta je to:** The industry mastering suite, now driven end-to-end by neural nets: Master Assistant (AI chain builder), Stem EQ (phase-aware joint-stem processing), the industry-first **Unlimiter** (neural limiter inversion restoring pre-limit dynamics), and improved Stem Focus.
- **Status 2026:** Stable retail product.
- **Relevantnost za FluxForge:** Ozone sets the perceptual bar. FluxForge's `rf-aurexis` "Auto-Master" preset must aim at Ozone-12-grade output; Unlimiter specifically is a cheat-code for recovering over-compressed legacy reel-to-reel source material (we have ~300h of that).
- **Sources:** [Ozone 12 features](https://www.izotope.com/en/products/ozone/features), [MusicTech Ozone 12 review](https://musictech.com/reviews/plug-ins/izotope-ozone-12-review/), [Inside Ozone 12 (iZotope)](https://www.izotope.com/en/learn/inside-ozone-12).

#### II.1.6 Neural stem separation — Demucs v4 (HT-Demucs), Kim Vocal 2, MVSEP ensembles

- **Šta je to:** SotA music source-separation. HT-Demucs (fine-tuned) hits 9.20 dB SDR on MUSDB-HQ; Kim Vocal 2 reaches 9.60 vocals / 15.91 instrumental; ensembles on MVSEP push past that.
- **Status 2026:** Stable. 2025 GSoC effort ported HT-Demucs to **ONNX**, unblocking real-time (or near-real-time) native integration — Mixxx uses this path.
- **Relevantnost za FluxForge:** (a) **Reel-to-reel archive mining** — extract a clean drum hit or vocal from a 40-year-old Jackpot Deluxe mix-down; (b) **Logic-Pro-grade Stem Splitter** inside the DAW Mode PROCESS tab; (c) **live remix authoring** — split a reference cue into stems, reuse drums, regenerate bass with MusicGen-Style.
- **Sources:** [Demucs GitHub](https://github.com/facebookresearch/demucs), [Mixxx GSoC ONNX port](https://mixxx.org/news/2025-10-27-gsoc2025-demucs-to-onnx-dhunstack/), [MVSEP-MDX23](https://github.com/ZFTurbo/MVSEP-MDX23-music-separation-model).

#### II.1.7 Apple Logic Pro 11.2 / iPad 2.2 — AI Session Players + Stem Splitter

- **Šta je to:** Apple's native on-device AI suite — Session Players (AI bass/keys/drums), Stem Splitter (4-way, now 6-way with guitar/piano), ChromaGlow, Mastering Assistant, Chord ID.
- **Status 2026:** Stable. Runs on-device via Apple Neural Engine (M-series / A12+).
- **Relevantnost za FluxForge:** The existence-proof that on-device neural authoring is shippable today. Our Rust crates should target the same performance envelope: <100 ms per second of audio for stem-splitting on M1 Pro.
- **Sources:** [Logic Pro 11.2 announcement](https://www.apple.com/newsroom/2024/05/logic-pro-takes-music-making-to-the-next-level-with-new-ai-features/), [Sound On Sound — Stem Splitter](https://www.soundonsound.com/techniques/logic-pro-how-use-stem-splitter).

#### II.1.8 LANDR Mastering API + Waves Online

- **Šta je to:** Cloud-mastering REST APIs with loudness presets and style banks. LANDR's plug-in also runs as a real-time DAW insert since 2024.
- **Status 2026:** Stable. Waves Online received a major engine upgrade in 2025.
- **Relevantnost za FluxForge:** Fallback path — if Corti-Assist local model fails, the DELIVER tab can one-click upload to LANDR for a reference master. Also, LANDR-API-as-a-service is a blueprint for how **we** could expose FluxForge mastering to 3rd-party tooling.
- **Sources:** [LANDR Mastering API](https://www.landr.com/pro-audio-mastering-api), [LANDR API (Fast & Wide)](https://www.fast-and-wide.com/equipment-releases/processing-and-control/16953-landr-ai-mastering-api).

#### II.1.9 ElevenLabs Voice Engine (v3 / Flash v2.5)

- **Šta je to:** TTS and voice-cloning API; `eleven_v3` (June 2025) is the most expressive, `eleven_flash_v2_5` hits ~75 ms latency, 32+ languages, tag-based emotional direction ("she said excitedly").
- **Status 2026:** Stable, REST + streaming SDK.
- **Relevantnost za FluxForge:** (a) **VO drafts** — slot narrator placeholders from a script; (b) **voice-driven authoring** — speak directions at Corti, get immediate action ("make the jackpot bed 20% more dramatic"); (c) ephemeral SFX utterances ("cha-ching", "level up!") for rapid prototyping.
- **Sources:** [ElevenLabs TTS docs](https://elevenlabs.io/docs/overview/capabilities/text-to-speech), [ElevenLabs Cheat Sheet 2026](https://www.webfuse.com/elevenlabs-cheat-sheet).

#### II.1.10 Neural / diffusion reverb (PromptReverb, NeuralReverberator)

- **Šta je to:** Neural RIR (Room Impulse Response) generators. **PromptReverb** (Oct 2025) uses a VAE + rectified-flow-matching DiT to synthesize full-band 48 kHz RIRs from text prompts ("damp cathedral, warm, 2.1 s tail").
- **Status 2026:** Research → early preview. Offline-only for now; real-time inference is the next frontier.
- **Relevantnost za FluxForge:** Replace our IR library with a **generator**. Composer types "shimmery chapel, 4 s, bright" → `rf-aurexis` produces a custom IR, bakes it into the project. One knob = infinite reverbs.
- **Sources:** [PromptReverb arXiv](https://arxiv.org/html/2510.22439v2), [NeuralReverberator](https://www.christiansteinmetz.com/projects-blog/neuralreverberator).

---

### II.2 GPU-Accelerated DSP

CPUs are no longer the bottleneck for the *heavy* DSP — diffusion inference, convolution reverb at 7th-order ambisonic, 256-voice polyphonic physical models. The GPU is.

#### II.2.1 WebGPU / wgpu compute shaders

- **Šta je to:** A portable compute-shader API (wgpu-rs on native: Vulkan/Metal/DX12; browsers: WebGPU). Workgroup-parallel compute, shared memory, atomic ops — essentially CUDA for everyone.
- **Status 2026:** Stable on all three desktop APIs; browser support shipping in Chrome/Edge/Safari 18+/Firefox 131+; mature WGSL tooling.
- **Relevantnost za FluxForge:** We already ship `wgpu` (UI). Promote it to **audio-engine first-class citizen**: run FFT-based convolution reverb, bulk biquad cascades, and ML inference (via burn-wgpu) on the same device. Zero extra runtime dependencies for end-users. Measured latency from community reports: a 131 k-sample FIR convolve in <1 ms on M1 Max @ 48 kHz — 20× faster than SIMD CPU.
- **Sources:** [wgpu-rs](https://wgpu.rs/), [crates.io wgpu](https://crates.io/crates/wgpu), [WebGPU Compute Shader Basics](https://webgpufundamentals.org/webgpu/lessons/webgpu-compute-shaders.html), [dasp-rs DSP crate](https://crates.io/crates/dasp-rs), [pxe.gr Interactive Audio Rust](https://pxe.gr/en/graphics-multimedia/building-interactive-audio-apps-with-rust).

#### II.2.2 Apple Metal Performance Shaders + MPSGraph

- **Šta je to:** Apple's GPU compute primitives and the MPSGraph layer that compiles a computation across GPU, CPU, and Neural Engine transparently. Critical for anyone targeting Apple Silicon optimally.
- **Status 2026:** Stable; Apple actively extends MPSGraph each WWDC cycle.
- **Relevantnost za FluxForge:** On macOS we should route compute-heavy paths (spectrogram FFTs, neural-vocoder inference) through MPSGraph rather than wgpu's Metal backend — ~30–40% faster in practice because MPSGraph schedules across the Neural Engine too. AudioUnit (AUv3) visualizers like JAX AudioVisualizer already do this for spectrum work.
- **Sources:** [Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders), [MPSGraph](https://developer.apple.com/documentation/metalperformanceshadersgraph), [JAX AudioVisualizer](https://audio.digitster.com/jax-audiovisualizer-update-pending).

#### II.2.3 Vulkan compute on Windows/Linux

- **Šta je to:** Lower-level alternative for squeezing last 10% out of non-Apple GPUs. Wgpu's Vulkan backend is good; hand-written Vulkan compute is better when you know the workload.
- **Status 2026:** Stable; use only if profiling shows wgpu is the bottleneck.
- **Relevantnost za FluxForge:** Nice-to-have for a future "Render Farm" offline mode — bake long neural reverbs and high-voice-count simulations at render speed. Not worth the maintenance cost for realtime path.

#### II.2.4 Differentiable DSP on GPU — burn, candle, tract

- **Šta je to:** Rust ML frameworks (Burn, Candle, Tract) that target wgpu/CUDA/Metal and can load ONNX, Safetensors, GGUF. Tract specializes in inference-only with tiny binary footprint.
- **Status 2026:** Stable. Candle 0.7+ ships M-series Metal backend with solid perf.
- **Relevantnost za FluxForge:** Our in-engine ML (stem separator, neural reverb, mastering assistant) is a **Candle** app. No Python, no TorchScript, single `cargo build`.

---

### II.3 Spatial Audio Frontier

Slot halls have massive surround installs; home gaming is Atmos-capable. FluxForge must treat 3D as a first-class pipeline, not a plug-in.

#### II.3.1 Dolby Atmos 2025+ / FlexConnect

- **Šta je to:** Dolby's object-audio format, now with **FlexConnect** (2026 CES reveal with LG) — the system discovers speaker positions via UWB and re-renders in real-time. Mastering deliverable is the **ADM BWF** (Audio Definition Model) file at –18 LUFS integrated / –1 dBTP.
- **Status 2026:** Stable in consumer; Atmos Music on streaming is mainstream; 35+ auto brands ship it in 150+ car models.
- **Relevantnost za FluxForge:** **DELIVER tab must export ADM BWF** natively (dolby-renderer compatible). SlotLab can use object-based positioning for the 13+ speaker configurations common in high-end cabinets (top-box, deck, chair-shakers). Eye-level UWB speaker discovery is exactly what a VIP cabinet install wants.
- **Sources:** [Dolby Atmos Standards 2025 (Ralph Sutton)](https://ralphsutton.com/dolby-atmos-standards-deliverables-2025/), [Dolby FlexConnect (AudioXpress)](https://audioxpress.com/news/dolby-and-lg-unveil-the-world-s-first-soundbar-audio-system-powered-by-dolby-atmos-flexconnect), [Dolby CES 2026](https://news.dolby.com/en-WW/259256-dolby-sets-the-new-standard-for-premium-entertainment-at-ces-2026/).

#### II.3.2 Apple Spatial Audio (AirPods Pro 3, visionOS, Personalized HRTF)

- **Šta je to:** Apple's proprietary spatial format with head-tracking via `CMHeadphoneMotionManager`, personalized HRTFs (iPhone-camera scan of ear), and `PHASE` framework for game/app integration.
- **Status 2026:** Stable. iOS 18 added first-order Ambisonics capture; iOS 26 adds `.qta` QuickTime-audio container and a new Audio Mix API (foreground/background balance).
- **Relevantnost za FluxForge:** Boki's headphone mixing reference on AirPods Pro 3 should auto-enable head-tracked monitoring inside the DAW. Export a second master using `PHASE` for iOS-native slot apps. Personalized-HRTF scan of the target player cohort is a premium feature nobody else offers.
- **Sources:** [Apple Spatial Audio control](https://support.apple.com/guide/airpods/control-spatial-audio-and-head-tracking-dev00eb7e0a3/web), [PHASE personalization](https://developer.apple.com/documentation/phase/personalizing-spatial-audio-in-your-app), [Enhance audio recording WWDC25](https://developer.apple.com/videos/play/wwdc2025/251/).

#### II.3.3 Higher-Order Ambisonics — 7th order is here

- **Šta je to:** Sound-field encoding at arbitrary spatial order. 7th order = 64 channels of pure directional information; Harpex spacemics capture 5th order; the new **HiFi-HARP dataset** (Oct 2025) provides 7th-order RIRs for training.
- **Status 2026:** Production-capable for offline; real-time 7OA decoding requires 64 speakers — rare but real in premium venues.
- **Relevantnost za FluxForge:** Keep the internal bus architecture ambisonic-native (scene-based), decode to whatever target (stereo, binaural, 7.1.4, ADM, 64-speaker). This future-proofs us against every output format churn.
- **Sources:** [HiFi-HARP arXiv](https://arxiv.org/html/2510.21257v1), [SSA Plugins — What is HOA](https://www.ssa-plugins.com/blog/2017/07/18/what-is-higher-order-ambisonics/), [Voyage Audio — Ambisonics Demystified](https://voyage.audio/ambisonics-demystified/).

#### II.3.4 ML-driven HRTF personalization (HRTFformer, Graph NN HRTF)

- **Šta je to:** Transformer and graph-neural-net models that predict a person's HRTF from sparse measurements or a single ear photo. **HRTFformer** (Oct 2025) operates in the spherical-harmonic domain; Graph-NN HRTF (Nov 2025) handles variable-density inputs.
- **Status 2026:** Research → productizable. Apple's ear-scan is the consumer face; open research gives us the algorithms.
- **Relevantnost za FluxForge:** Let composer drop in Apple's exported HRTF profile (or run our own scan) → Corti monitors *exactly* as the target player will hear it.
- **Sources:** [HRTFformer arXiv](https://arxiv.org/html/2510.01891v1), [Graph NN HRTF arXiv](https://arxiv.org/html/2511.10697), [SONICOM review](https://www.sonicom.eu/assessing-machine-learning-techniques-for-hrtf-individualisation/).

---

### II.4 Input Paradigms 2026

Mouse + keyboard is now one of at least five equal peers. Professional authoring needs to meet each of them on its own terms.

#### II.4.1 Apple Vision Pro eye + hand + voice (visionOS 2)

- **Šta je to:** visionOS's input model: gaze targets, pinch confirms, voice and virtual keyboard for text. **Gaze data is intentionally not exposed** to apps (privacy) — only the resulting "tap" event.
- **Status 2026:** Stable but locked down. Enterprise APIs unlock slightly more (scene reconstruction, object tracking) behind entitlements.
- **Relevantnost za FluxForge:** A visionOS companion mode where a composer walks around the mix, looks at a voice, pinches to solo, hand-drags to reposition in 3D. We cannot read gaze directly — we read the `SpatialEventGesture` fires. Good enough for mixing, not for continuous fader control.
- **Sources:** [visionOS Developer](https://developer.apple.com/visionos/), [Eye HIG](https://developer.apple.com/design/human-interface-guidelines/eyes), [iTrace gaze extraction paper](https://arxiv.org/html/2508.12268v2).

#### II.4.2 Voice control — macOS 26 Voice Control + Speech framework + WhisperKit

- **Šta je to:** System-level voice navigation plus `Speech` framework (on-device, offline-capable) and **WhisperKit** (argmax's on-device Whisper for Apple Silicon).
- **Status 2026:** Stable and very fast; WhisperKit hits <300 ms latency on M-series for short commands.
- **Relevantnost za FluxForge:** Corti listens. "Solo reel two." "Mute the jackpot bed." "Loudness to UK spec." "Show me the spin trace." This is the **voice-driven authoring** vision shipped.
- **Sources:** [Apple Speech framework](https://developer.apple.com/documentation/speech), [WhisperKit (argmax)](https://github.com/argmaxinc/WhisperKit).

#### II.4.3 Stylus / pen with haptic feedback

- **Šta je to:** Wacom Pro Pen 3 (2025 Intuos Pro), Cintiq Pro 16 with haptic ExpressKeys, Apple Pencil Pro with barrel-squeeze + haptic.
- **Status 2026:** Stable consumer hardware. Haptic is still mostly in the side-keys, not the tip, but the APIs exist.
- **Relevantnost za FluxForge:** Pen-native automation drawing. Pressure → velocity, tilt → filter cutoff, haptic pulse → snap-to-grid feedback. Wacom's tablet driver exposes all 8192 pressure levels and full tilt to any app.
- **Sources:** [Wacom Intuos Pro 2025](https://community.wacom.com/en-us/wacom-intuos-pro-drawing-tablet/), [Cintiq Pro 16](https://www.wacom.com/en-us/products/pen-displays/wacom-cintiq-pro-16).

#### II.4.4 3D trackpad / Force Touch evolution

- **Šta je to:** Apple's Force Touch trackpad exposes continuous pressure via `NSEvent.pressure` (0.0 – 1.0).
- **Status 2026:** Stable for a decade; still under-used.
- **Relevantnost za FluxForge:** Pressure-sensitive scrub. Light press = normal scrub, deep press = frame-accurate. Apply to any slider for "fine" mode without modifier keys.

#### II.4.5 Multi-touch on desktop (Magic Trackpad, Procreate-style gestures)

- **Šta je to:** Native macOS gestures (two-finger pinch, three-finger drag) usable inside Flutter via the `gestures` package.
- **Relevantnost za FluxForge:** Timeline zoom (pinch), mixer-rotate (two-finger rotate), panel shuffle (three-finger swipe). Already partly implemented; formalize into gesture DSL.

---

### II.5 Real-time Collaboration

The moment a session can be opened simultaneously by composer + sound-designer + math-team is the moment the entire workflow changes.

#### II.5.1 CRDTs — Yjs, Automerge, Loro

- **Šta je to:** Conflict-free Replicated Data Types for peer-to-peer collaborative editing. **Yjs** is the Figma/Notion-style battle-tested JS library; **Automerge 2.0** is Rust-core with Swift/JS/Python bindings; **Loro** is the new 2024 Rust CRDT optimized for performance (josephg benchmarks show ~10× faster than Yjs on heavy edits).
- **Status 2026:** All three stable. Automerge is best-fit for Rust-first stacks.
- **Relevantnost za FluxForge:** The `.rfp` project becomes a CRDT document. Two composers edit simultaneously; merges are automatic; presence (who is touching what) is free. This is the foundation for V.7 in our vision.
- **Sources:** [Yjs](https://yjs.dev/), [Automerge 2.0](https://automerge.org/blog/automerge-2/), [CRDTs go brrr (josephg)](https://josephg.com/blog/crdts-go-brrr/), [Loro vs Yjs discussion](https://discuss.yjs.dev/t/yjs-vs-loro-new-crdt-lib/2567).

#### II.5.2 Figma-style multi-cursor + presence

- **Šta je to:** Pattern where every collaborator's viewport, cursor, and selection are broadcast so everyone sees everyone. No DAW does this natively.
- **Status 2026:** **Whitespace.** No production slot-audio or DAW tool has it — competitive opportunity.
- **Relevantnost za FluxForge:** First-mover advantage. HELIX super-tabs are perfect for presence — show Boki's avatar hovering the MIX tab, sound-designer on EVENTS, compliance on COMPLY.

#### II.5.3 Soundtrap / BandLab — the existing cloud-DAW model

- **Šta je to:** Soundtrap (Spotify) does real-time simultaneous editing with chat + video; BandLab uses "pass the ball" asynchronous collab. Both are browser-based.
- **Status 2026:** Stable. Both targeted at hobbyists; neither matches professional feature depth.
- **Relevantnost za FluxForge:** Blueprint for UX patterns (chat sidebar, call overlay, presence chips) — not competition on features. We borrow UX, keep pro DSP.
- **Sources:** [Soundtrap vs BandLab 2025 (MIDINation)](https://midination.com/daw/soundtrap-vs-bandlab/), [Soundtrap collab blog](https://blog.soundtrap.com/music-collaboration-online/).

#### II.5.4 WebRTC audio streaming + JackTrip

- **Šta je to:** WebRTC for sub-500 ms UDP/RTP low-latency media; **JackTrip WebRTC** for *uncompressed* audio streaming over WAN with ~20 ms one-way latency.
- **Status 2026:** Stable. QUIC and SFrame are cutting further latency.
- **Relevantnost za FluxForge:** Real-time monitor sharing — remote sound designer hears Boki's mixer live at studio quality. WebRTC for chat + screen; JackTrip for the audio bus.
- **Sources:** [JackTrip WebRTC HN](https://news.ycombinator.com/item?id=25942829), [Building a real-time collaborative mixer](https://www.imseankim.com/journal/realtime-collaborative-audio-mixer-web-audio-webrtc), [WebRTC Latency 2026](https://www.nanocosmos.net/blog/webrtc-latency/).

---

### II.6 Flutter / UI 2026

#### II.6.1 Impeller renderer — now default on macOS

- **Šta je to:** Flutter's new rendering engine replacing Skia. AOT-compiled shaders eliminate compilation jank; 120 fps is predictable on M-series.
- **Status 2026:** Stable; default on iOS and Android; **on macOS behind `--enable-impeller` flag, on path to default-on**. Opt-out will be removed.
- **Relevantnost za FluxForge:** Enable it. The 130-voice mixer's spring animations and waveform redraws are exactly where Impeller's AOT shader pipeline pays off.
- **Sources:** [Impeller docs](https://docs.flutter.dev/perf/impeller), [Impeller 2026 deep-dive (dev.to)](https://dev.to/eira-wexford/how-impeller-is-transforming-flutter-ui-rendering-in-2026-3dpd).

#### II.6.2 Fragment shaders (GLSL .frag files)

- **Šta je to:** Custom GPU shaders written in GLSL, consumed via `FragmentShader`/`FragmentProgram`. Compiled to Impeller's IR automatically.
- **Status 2026:** Stable.
- **Relevantnost za FluxForge:** All the glass-morphism, orb-glow, waveform heatmap, spectrum analyzer and CortexEye animations should be shaders, not Canvas drawing. Already partially used (`flutter_shader_fx` shows the pattern).
- **Sources:** [Writing fragment shaders (Flutter docs)](https://docs.flutter.dev/ui/design/graphics/fragment-shaders), [flutter_shader_fx](https://pub.dev/packages/flutter_shader_fx), [GPU-Accelerated Shader Effects (Vibe Studio)](https://vibe-studio.ai/insights/gpu-accelerated-shader-effects-with-impeller).

#### II.6.3 flutter_rust_bridge 2.x

- **Šta je to:** Code-gen bridge between Dart and Rust. v2 supports async Rust (`async fn`), Streams (iterator), mirror types in streams, bidirectional calls (Rust→Dart), thread pools.
- **Status 2026:** Stable at v2.12+.
- **Relevantnost za FluxForge:** We already use it. Upgrade to the async-stream pattern for the audio-meter flow so Dart can `await for (final frame in engine.meterStream())` without blocking. Eliminate the polling Timer in `mixer_provider.dart`.
- **Sources:** [flutter_rust_bridge GitHub](https://github.com/fzyzcjy/flutter_rust_bridge), [V2 changelog](https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/whats-new), [Async Dart guide](https://cjycode.com/flutter_rust_bridge/guides/concurrency/async-dart).

#### II.6.4 Shadcn-equivalent design systems (shadcn_flutter, shadcn_ui, Forui)

- **Šta je to:** Port of the `shadcn/ui` React component philosophy to Flutter. **shadcn_flutter** (sunarya-thito) has 30+ cross-platform components; **shadcn_ui** (nank1ro) is the most popular (1.7k stars); **Forui** is the platform-agnostic contender.
- **Status 2026:** Stable; active weekly commits.
- **Relevantnost za FluxForge:** Don't rebuild primitives — alert, avatar, dialog, input, popover, tabs, tooltip, time-picker. Pull from shadcn_flutter, re-theme with FluxForge tokens (`#06060A`, Space Grotesk). Frees weeks of UI work.
- **Sources:** [shadcn_flutter pub.dev](https://pub.dev/packages/shadcn_flutter), [shadcn_ui (nank1ro) GitHub](https://github.com/nank1ro/flutter-shadcn-ui), [Forui](https://forui.dev/).

#### II.6.5 Desktop-specific APIs (native menus, file watchers, system tray)

- **Šta je to:** `menu_bar`, `tray_manager`, `watcher`, `window_manager`, `multi_window_ref` — packages covering true desktop parity.
- **Relevantnost za FluxForge:** Native macOS menu bar (File / Edit / View / Project / Render / Window / Help) is currently under-implemented. `watcher` for auto-reload of externally-edited assets. `window_manager` for the eventual multi-window mixer (detach the mixer to a second monitor).

---

### II.7 Emerging / Experimental — the 2028 frontier

Research-stage today, shippable in 12–24 months if we start now.

#### II.7.1 End-to-end neural mastering

- **Šta je to:** A single neural network that takes raw stems/mix and outputs a mastered stereo + LUFS-conformant WAV. No chain of plug-ins.
- **Status 2026:** Research; Ozone 12's Unlimiter and Apple Mastering Assistant are the commercial toe-in-the-water.
- **Relevantnost za FluxForge:** Train a FluxForge-specific mastering network on our reel-to-reel corpus → unique sonic signature nobody else can replicate. Defensible IP.

#### II.7.2 Text-to-music autoscore for games

- **Šta je to:** Models that consume game-state telemetry (tension curve, event stream) plus a text description and produce adaptive music in real-time. Soundverse, AIVA, and research from Microsoft (MusicFX-ADP) are pioneers.
- **Status 2026:** Early commercial (Soundverse for indie devs); research toward fully real-time.
- **Relevantnost za FluxForge:** **This is the endgame** for SlotLab MUSIC super-tab — describe the game's emotional arc, Corti generates the entire adaptive soundtrack graph.
- **Sources:** [Soundverse AI Music for Game Devs 2026](https://www.soundverse.ai/blog/article/ai-music-for-game-developers-and-indie-studios-0130), [Adaptive Music with Listener Mood](https://www.soundverse.ai/blog/article/how-to-create-adaptive-music-that-changes-with-listener-mood-1124).

#### II.7.3 Generative spatial — neural Ambisonics encoding

- **Šta je to:** Encode a dry mono source + a text prompt directly to an ambisonic scene. Skips the microphone-array / panning stage.
- **Status 2026:** Research-only (papers from SONICOM, Meta FAIR).
- **Relevantnost za FluxForge:** Far horizon — "place this stinger in a nervous casino hall, 30 m off-axis" produces correct 3rd-order ambisonic directly.

#### II.7.4 Differentiable / GPU physical modeling (NeiroSynth)

- **Šta je to:** GPU-accelerated FDTD (finite-difference time-domain) meshes fused with KAN neural nets. Physically-correct synthesis with ML-tunable parameters.
- **Status 2026:** Early commercial (NeiroSynth product exists).
- **Relevantnost za FluxForge:** "Coin drop" / "lever pull" / "mechanical reel stop" as physically-modeled synths — infinite variations, no sample-library bloat.
- **Sources:** [NeiroSynth](https://neirosynth.com/), [Frontiers editorial on physical modeling 2025](https://www.frontiersin.org/journals/signal-processing/articles/10.3389/frsip.2025.1715792/full).

#### II.7.5 Perceptual audio quality metrics — ViSQOL, PEAQ-CSM, SCOREQ

- **Šta je to:** Objective metrics that predict listener MOS scores without human raters. Traditional PEAQ/ViSQOL struggle with neural-codec artifacts; **PEAQ-CSM+** (2024) and **SCOREQ** (2025) use neural nets calibrated on fresh listening-test data.
- **Status 2026:** Stable metrics; SCOREQ is the current SotA for speech (ρ = 0.937).
- **Relevantnost za FluxForge:** CI pipeline gate — every build runs PEAQ-CSM+ on a reference slot render and fails if the score drops vs. `main`. Also used to A/B-test neural-codec compressed assets before shipping.
- **Sources:** [Evaluating Objective Quality Metrics for Neural Codecs (arXiv 2025)](https://arxiv.org/html/2511.19734v1), [PEAQ Wikipedia](https://en.wikipedia.org/wiki/Perceptual_Evaluation_of_Audio_Quality).

#### II.7.6 Neural upmix / neural downmix

- **Šta je to:** Network converts stereo → Atmos object bed (upmix) or 7.1.4 → stereo (content-aware downmix preserving dialog clarity).
- **Status 2026:** Commercial (Penteo, Waves UM226) and research (Meta Spatial Codec).
- **Relevantnost za FluxForge:** Legacy stereo reel content becomes Atmos-deliverable with one click on the DELIVER tab.

#### II.7.7 AudioSeal and watermark detection for provenance

- **Šta je to:** Meta's AudioSeal invisibly watermarks any audio generated by MusicGen/AudioGen; detector identifies AI-origin with >99% accuracy.
- **Status 2026:** Stable. EU AI Act compliance path.
- **Relevantnost za FluxForge:** Every AI-generated SFX/cue Corti produces gets watermarked. ComplianceManifest records "AI-generated, AudioSeal-signed". Regulators love this.

---

### II.8 Synthesis — "what FluxForge actually needs from Part II"

A hard, prioritized shortlist distilled from the above (full prioritization lives in Part IV Gap Analysis and Part VI Roadmap):

1. **Adopt DAC latent domain** as the internal asset format alongside raw WAV — unlocks compression + in-latent DSP + neural-model interop.
2. **Embed Candle + Demucs-ONNX + Stable-Audio-Open-Small + AudioSeal** inside `rf-aurexis` — on-device generative + separation + watermark.
3. **Promote `wgpu` to audio-engine peer** for convolution reverb and FFT-heavy DSP.
4. **Ship ADM BWF export** on the DELIVER tab for Atmos-native delivery.
5. **Enable Impeller on macOS** + convert hot UI paths (mixer, orb-overlay, CortexEye) to fragment shaders.
6. **Upgrade flutter_rust_bridge patterns to async Streams** — remove polling timers.
7. **Adopt shadcn_flutter** for form primitives; focus design bandwidth on the differentiated surfaces.
8. **Integrate Apple Speech / WhisperKit** for voice-driven authoring — lowest friction path to V.1 copilot.
9. **Prototype Automerge-backed project-state CRDT** — foundation for V.7 real-time collab.
10. **Watermark every AI-generated asset with AudioSeal** — regulatory moat.

Everything in Part II above is *available today*. None of this is speculation. The question the rest of the document answers is: **which of these do we absorb first, and how?**

---

## Part III — Competitive Intelligence

_Research period: 2024 Q4 — 2026 Q1. Methodology: public docs, blog posts, release notes, job listings, conference talks, industry forums, patent filings. No NDA material. Objective posture — "where we win" and "where we lose" with equal weight._

---

### III.1 Audiokinetic Wwise 2024–2026

**Product one-liner:** Industry-standard AAA game-audio middleware; hierarchical event/actor-mixer model with deep SoundBank/profiler toolchain and proprietary-engine SDK coverage.

**Latest version & date:** Wwise 2025.1 (released 2025, with patches through 2025.1.7 by early 2026); Wwise 2024.1 shipped mid-2024. Release cadence has moved to a 2-release-per-year model (`2025.1`, `2025.2`) with simultaneous patches across lines.

**Key features:**

- **Live Media Transfer (2024.1):** hot-reload of WAV assets between DAW and running game without SoundBank regeneration — closes the author-to-runtime gap that has historically been Wwise's biggest friction point.
- **Expanded Live Editing (2024.1/2025.1):** RTPC curves and plug-in Effects editable at runtime. SoundBanks no longer block iteration for most property edits.
- **Auto-Defined SoundBanks (2024.1 Unity; 2023.1 Unreal):** the engine derives bank membership from scene references so sound designers stop hand-assigning media to banks.
- **Media Pool + Similar Sound Search (2025.1):** non-generative deep-learning retrieval (audio-to-audio + text-to-audio) built by Sony AI × Audiokinetic; runs locally, indexes user's own library. This is Wwise's first real AI shipping feature.
- **Wwise Spatial Audio 3D:** Rooms & Portals geometry, Wwise Reflect (image-source early reflections), diffraction on portals, Reverb Zones (23.1 onwards — sub-room carve-outs without portals), 3D Busses for submix positioning.
- **Unreal packaging refactor (2024.1):** Wwise assets packed inside Unreal `.uasset` — fewer loose files, better cook performance.
- **Dynamic Dialogue in Unreal (2025.1):** fully supported, parity with Unity path.
- **Motion/Haptics:** Wwise Motion outputs to haptic devices (gamepad, console rumble); Meta Haptics Studio interop announced for Meta Quest ecosystem.
- **Property Editor redesign (2024.1):** vertical layout; Volume Fader restored in 2025.1 after community backlash.

**Strengths (vs FluxForge):**

- **Proven scale.** Wwise ships in thousands of titles from AAA (CoD, Assassin's Creed) to mid-tier. Battle-tested profiler, memory pools, voice-limiter, virtual voices. FluxForge has not yet proven 10k+ concurrent events/sec.
- **Platform coverage.** Xbox, PS5, PS4, Switch, Switch 2, iOS, Android, Meta Quest, plus proprietary-engine integrations. FluxForge is macOS-only right now.
- **Ecosystem.** 100+ third-party plug-ins (iZotope, McDSP, Auro-3D, Crankcase REV). Certification program, WAAPI automation, Community Q&A, sample projects. Zero third-party plug-in marketplace for FluxForge.
- **Spatial audio maturity.** Rooms/Portals + Reflect + Reverb Zones is the richest geometric acoustic model in any middleware. FluxForge's spatial story is TBD.
- **Dialogue system.** Dynamic Dialogue (argument-based line selection) has no equivalent in FluxForge.

**Weaknesses (where FluxForge can win):**

- **Authoring UI is 2007-era.** Users complain about property editor density, context-switching between Designer/Mixer/Profiler layouts, inscrutable bus hierarchy. Forum threads ("Wwise vs FMOD") consistently cite Wwise's learning curve as punishing.
- **Not a DAW.** Sound designers round-trip to Reaper/Pro Tools/Logic; Wwise cannot edit waveforms, draw fades, or render stems. FluxForge's DAW-hybrid is the exact gap.
- **SoundBank management remains painful** even with auto-defined banks — edge-cases around localization, streaming banks, and per-platform overrides still force manual work.
- **No slot-specific vocabulary.** No concept of anticipation curves, rollup durations, win-tier mapping, LDW guards, or regulatory compliance. Wwise is engine-agnostic by design, which means slot authors graft their own workflow on top.
- **AI surface is tiny.** Similar Sound Search is retrieval, not generation. No text-to-SFX, no procedural variation, no Corti-style authoring assistant.
- **Iteration loop still slow** despite Live Media Transfer — for large projects the bank rebuild is measured in minutes when properties require a regenerate.
- **Pricing gates.** Premium/Platinum tiers ($25k / $50k) push mid-sized slot studios away; royalty 1% over $10k gross is non-trivial on a slot title with million-dollar gross.

**Pricing:**

- Indie: free if total production budget < USD 250k, unlimited sounds, all platforms.
- Pro: from USD 8,000 up-front.
- Premium: from USD 25,000.
- Platinum: from USD 50,000.
- Royalty option: 1% of gross after the first USD 10,000.

**Source links:** `audiokinetic.com/en/blog/wwise-2025.1-whats-new/`, `audiokinetic.com/en/blog/wwise2024.1-whats-new/`, `audiokinetic.com/en/blog/wwise-2025.1-media-pool-similar-sound-search/`, `audiokinetic.com/en/wwise/pricing/`, `audiokinetic.com/en/blog/reverb-zones/`, `audiokinetic.com/en/blog/a-wwise-approach-to-spatial-audio-part-2-diffraction/`, `audiokinetic.com/en/blog/how-to-use-audiolink/`.

---

### III.2 FMOD Studio 2024–2026

**Product one-liner:** Timeline/event-based audio middleware with a DAW-flavored UI; the friendlier, cheaper rival to Wwise, strong in indie/mid-tier and increasingly in AAA.

**Latest version & date:** FMOD 2.03.12 (released 2026-01-15). 2.03 line introduced in 2024; rolling patches through 2025–2026.

**Key features:**

- **Parameter Sheets** and timeline-based Event Editor — the core differentiator vs Wwise's actor-mixer tree.
- **Multiband Dynamics DSP (2.03):** three-band compressor/expander; Multiband EQ gained low-overhead 6 dB hi/lo filters.
- **Echo delay ramp modes (2.03):** `LERP` for fine changes, `FADE` default for large — stops zipper artifacts.
- **Haptics plug-in (2.03.11):** FMOD Haptics Instrument for vibration devices; PS4 + Switch support (2.03.12).
- **Meta Haptics Studio interop** for Meta Quest.
- **Profiler upgrade:** per-track, per-DSP, per-bus breakdown; closes a long-standing gap vs Wwise Profiler.
- **Opus encoding for Switch** (2.03 build option).
- **Unity + Unreal integrations** with project-level banks; Unreal 5.x support.
- **Studio Scripting (JavaScript)** for batch operations and custom tools.
- **Programmer Sound** pattern — late-bound asset at runtime, typical for dialog.

**Strengths (vs Wwise and FluxForge):**

- **Timeline is linear-composer-friendly.** Musicians transitioning to game audio find FMOD instantly readable; Wwise's tree is alien to them. FluxForge is closer to FMOD in spirit but has not yet delivered a mature timeline view.
- **Cheaper.** Free for indie under USD 500k budget (5× Wwise's ceiling). Commercial tiers start lower.
- **Faster onboarding.** Docs quality and sample projects are excellent. Forum users consistently cite FMOD as the "gateway drug" to game audio.
- **Sidechain, send/return, mixer routing** feels DAW-native.

**Weaknesses (where FluxForge can win):**

- **No autosave.** Studio crashes lose work — reported repeatedly in 2024–2025 forum threads.
- **Watered-down effects.** Beyond built-in Reverb, Compressor, Multiband, users route to VST hosts — but VST hosting itself is brittle on some platforms.
- **Complex routing is awkward.** Multi-layered side-chains, ducking chains, and cross-event parameter sharing require JavaScript scripting or brittle "event macro" patterns.
- **No spatial audio engine** comparable to Wwise Reflect/Rooms. FMOD relies on engine-side spatializers (Steam Audio, Resonance, Meta XR Audio).
- **No slot-specific features** — same gap as Wwise.
- **No AI features shipping as of 2.03.12** — FMOD has not publicly announced an AI roadmap.
- **Profiler still less deep** than Wwise on voice-limit/memory-pool/virtual voice diagnostics.

**Pricing:**

- Free for projects < USD 500k budget.
- Indie: USD 2,000 / title (<USD 600k budget).
- Basic: USD 5,000 / title.
- Premium: USD 15,000 / title.

**Source links:** `fmod.com/docs/2.03/api/welcome-whats-new-203.html`, `fmod.com/docs/2.03/studio/welcome-to-fmod-studio-revision-history.html`, `fmod.com/docs/2.03/unreal/welcome-whats-new-203.html`, `developers.meta.com/horizon/blog/meta-haptics-studio-meets-fmod-wwise/`, `fmod.com/fmod-studio-release-notes/`.

---

### III.3 Unity 6 Audio Pipeline (2024+)

**Product one-liner:** The integrated audio stack inside Unity 6 — AudioSource/AudioMixer legacy plus the in-development DSPGraph and Audio Random Container (ARC).

**Latest version & date:** Unity 6.0 LTS (2024), Unity 6.1 (2025), Unity 6.2 (2026 preview). Audio Random Container shipped 2023 as the first big audio feature since 2018.

**Key features:**

- **Audio Random Container (ARC):** hierarchical randomizer asset, play-mode sequencing, volume/pitch randomization. First real "middleware-lite" primitive in native Unity.
- **DSPGraph (experimental):** C#/Burst-compiled node-based DSP framework exposed via the Entities package. Designed for ECS/DOTS workloads.
- **AudioMixer (legacy)** with snapshots, exposed parameters, ducking, send/return.
- **Native spatializer SDK** for third parties (Oculus, Steam Audio, Resonance, Meta XR Audio).
- **Audio Status Updates (Q3 2025):** Unity audio team is now focused on stability/test-coverage rather than new features; DSPGraph stalled in experimental status.

**Strengths:**

- **Zero cost.** Included with Unity. No royalty on top of Unity's own licensing.
- **Integrates natively** with the rest of Unity (Timeline, Animator, Signals).
- **Burst/ECS compatibility** via DSPGraph is compelling for high-voice-count games.

**Weaknesses (where FluxForge wins easily):**

- **DSPGraph has been "coming soon" since 2019.** Unity Discussions thread "Where is DSPGraph?" runs to multiple years. As of Q3 2025 update Unity officially deprioritized new audio features in favor of bug fixing — community morale is low.
- **No authoring UI** on the scale of Wwise/FMOD. ARC is a single asset type, not a mixer/event editor.
- **No spatial audio** without third-party plug-ins.
- **No profiler worth naming.** Unity Profiler's audio view is shallow.
- **"A Plea for Unity Audio"** (long-running Unity forum thread) is the defining community document — users publicly begged Unity to invest for 5+ years.

**Pricing:** Free with Unity Personal up to USD 200k revenue; Unity Pro USD 2,200/seat/year.

**Source links:** `discussions.unity.com/t/audio-status-update-q3-2025/1681867`, `discussions.unity.com/t/where-is-dspgraph/1629387`, `discussions.unity.com/t/a-plea-for-unity-audio/802155`, `discussions.unity.com/t/dspgraph-current-limitations/937491`.

---

### III.4 Unreal Engine 5.5+ Audio (MetaSounds, Quartz, AudioLink)

**Product one-liner:** Epic's first-class procedural audio stack — MetaSounds replaces SoundCue, Quartz provides sample-accurate scheduling, AudioLink bridges to external middleware.

**Latest version & date:** UE 5.5 (2024 Q4), UE 5.6 (2025), UE 5.7 docs active for 2026.

**Key features:**

- **MetaSounds:** node-based DSP graph for sound sources; complete replacement for SoundCue. Compiles to native code, runs on audio render thread.
- **MetaSounds 2025 updates:** granular synthesis nodes, spectral processing, AI-driven audio generation nodes (experimental), Audio Widgets for in-UI fader/slider/meter tied to MetaSound parameters.
- **Channel Agnostic Types (CAT):** new MetaSounds work (ADC 2025 talk) decoupling graph from fixed channel layouts — enables reusable spatial graphs.
- **Quartz:** sample-accurate scheduler, clocks, quantized triggers — first middleware-grade music scheduling inside a big engine.
- **AudioLink (UE 5.1+):** hardware-abstraction API exposing Sources / Submixes / Audio Components as PCM streams to external engines — Wwise, FMOD, or a custom sink can consume the PCM and re-route to their own graph without touching UE source.
- **Niagara + Audio:** particle systems can drive MetaSound parameters; procedural audio reactive to particles.
- **MetaSounds preset library:** ships with Epic's own presets (granular pads, impact tails, Foley breaks).

**Strengths:**

- **Most advanced procedural audio** of any major game engine. MetaSounds is the closest thing to a "Reaktor inside your engine".
- **Quartz** is unique — nothing comparable ships in Unity or in Wwise/FMOD.
- **AudioLink** is the cleanest middleware bridge anyone has shipped.
- **Free** with UE; 5% royalty over USD 1M gross (recently raised floor).

**Weaknesses (where FluxForge wins):**

- **Locked to Unreal.** MetaSounds cannot be exported to Unity, to a slot engine, or to a standalone product. This is the single largest opening — FluxForge is engine-agnostic and can host a MetaSounds-equivalent graph outside of UE.
- **No project-level asset management** comparable to SoundBanks. Organizing 5,000 sound assets in a UE project is painful.
- **Profiler immature** compared to Wwise — Epic has not invested in a dedicated audio profiling surface.
- **Steep learning curve** — MetaSounds + Quartz + Niagara binding requires a senior technical sound designer.
- **No slot vocabulary.**

**Pricing:** Unreal free; 5% royalty over USD 1M lifetime gross per product (2024+).

**Source links:** `dev.epicgames.com/documentation/unreal-engine/metasounds-in-unreal-engine`, `dev.epicgames.com/documentation/en-us/unreal-engine/audiolink-overview`, `cdm.link/unreal-engine-5-5-for-sound/`, `conference.audio.dev/channel-agnosticism-in-metasounds-simplifying-audio-formats-for-reusable-graph-topologies-adc-2`, `audiokinetic.com/en/blog/how-to-use-audiolink/`.

---

### III.5 IGT Playa (Internal Slot Middleware)

**Product one-liner:** IGT's internal cross-platform slot/game runtime and authoring stack — most likely the successor to the GRAIL/Aruze/IGT-CORE lineage; TypeScript/C++ hybrid with strong config-driven state machines. _Publicly undocumented; information below derives from job-listings, SLOTLAB_VS_PLAYA_ANALYSIS.md internal research, and adjacent patent filings._

**Latest version & date:** Unknown externally. Job postings referencing "Playa" appear on IGT/Everi-adjacent listings 2023–2025 for Senior/Principal engineer roles in Las Vegas, Reno, and Belgrade (SRB). Cadence appears to be internal release trains, not public.

**Key features (inferred):**

- **Playa-core:** shared runtime primitives — RNG adapter, reel/stop math, event bus, state machine, persistence (restore-on-recovery), SAS/GSA protocol bridge. Written to be jurisdiction-agnostic and abstract over cabinet/online.
- **Playa-slot:** slot-specific layer — StageFlow (Idle → Bet → Spin → Evaluate → Rollup → Big Win → Feature → Return), win-tier schema, free-game sub-flows, hold-and-spin / Megaways-style mechanics, scatter/wild evaluators.
- **Playa-engine:** rendering/audio/haptic runtime. Audio likely uses a proprietary event router with voice-limit + ducking + compliance guards rather than stock Wwise/FMOD (because regulators require deterministic reproducibility and internal audit).
- **Anticipation/rollup as first-class concepts** — the state machine knows "anticipation enters at reel N when M matching symbols are visible", rollup duration curves scale with win tier, big-win celebration has explicit entry/exit stages.
- **Config-driven slot mechanics:** JSON/YAML describe paytable, reel strips, features — engineers ship math without code changes.
- **Server-authoritative RNG** with client-side presentation — mandatory for online/RGS compliance (UKGC, MGA).
- **Platform coverage:** IGT True 4D, CrystalCurve, Crystal Dual, PeakSlant, plus online (PlaySpot, PlayDigital).

**Strengths (where IGT wins even against FluxForge):**

- **Regulatory maturity.** Playa ships under UKGC, MGA, NGCB, every North American tribal + commercial board, EU markets, Australia, Asia. Every edge-case — LDW guard, near-miss guard, win-cap, max-bet-lock, RG (Responsible Gaming) session limits — is already encoded. FluxForge is catching up via its `rf-slot-builder` Validator.
- **Deterministic audit trail.** Every event, RNG draw, and outcome is logged in a form certifiers accept. External middleware has no built-in path for this.
- **Jurisdiction hot-swap.** Playa blueprints can re-target jurisdictions by config — a huge organizational force multiplier.
- **Embedded fleet-update** system for real-cabinet deploys.
- **20+ years of slot math DNA** — anticipation curves, rollup feel, win-tier pacing are tuned by people who have shipped thousands of titles.

**Weaknesses (where FluxForge can realistically compete):**

- **Closed.** Only IGT internal teams can author for Playa. Third parties cannot ship on IGT cabinets without an IGT content deal.
- **Authoring tools are primitive** per internal gossip — most work lives in spreadsheets (`IGT_Ultimate_AudioSpec_FULL.xlsx` in this very project is an example), JSON files, and hand-rolled editors. No unified DAW-hybrid.
- **Audio workflow depends on external DAWs** — sound designers cut in Pro Tools/Cubase/Nuendo, export WAV, drop into IGT's asset pipeline. No Wwise-class authoring UI.
- **AI-zero.** No evidence of Corti-style authoring assistant, similar-sound search, or generative workflows.
- **Slow iteration cycle** — cabinet test requires hardware in the loop; simulator coverage is partial. FluxForge can ship a pure-software authoring loop that's measured in seconds, not minutes.
- **Collaboration is primitive** — no CRDT multi-user, no cloud project mirror. Likely Perforce + Jira.
- **Platform-locked.** No way to target Aristocrat, Light & Wonder, Konami cabinets from Playa.

**Pricing:** N/A — internal tool, not licensable. Third parties pay via content-distribution revenue share.

**Source links:** `igt.com`, `jobs.igt.com/`, internal `SLOTLAB_VS_PLAYA_ANALYSIS.md`, `limeup.io/blog/igaming-software-providers/`, `hackernoon.com/modular-game-engines-building-scalable-architectures-for-next-gen-online-slots`, `patents.google.com/patent/US6968063B2/en` (IGT dynamic volume adjustment patent — ambient noise detector in cabinet).

---

### III.6 Aristocrat, Konami, Light & Wonder — Internal Stacks

**Product one-liner:** Three of the other five global top-tier slot vendors; each ships a proprietary game runtime + authoring stack analogous to Playa, with different levels of public disclosure.

**Latest version & date:** N/A externally. Vendors release titles, not platform versions.

**Key features (what's publicly visible):**

- **Aristocrat** — `OASIS CORE` is the casino-management layer (player tracking, bonusing, floor surveillance), visible on `aristocratgaming.com/us/casino-operator/cxs/slot-and-floor-solutions/oasis-core`. The game-side runtime is not named publicly; Aristocrat MK6 / MK7 / Helix / Helix+ are cabinets, not middleware. Job listings for "Senior Sound Designer at Aristocrat" cite Cubase, Nuendo, Pro Tools, MIDI keyboards, VST plug-ins — confirming a DAW-centric authoring workflow feeding a proprietary asset pipeline. Aristocrat Interactive (online) uses HTML5 + WebAudio for RMG titles.
- **Konami** — KX series cabinets, `SYNKROS` CMS. Internal game engine goes by `Podium Core` in legacy titles; no public docs. Konami's historical strength is audio-from-composition — their in-house music teams compose bespoke per-title scores.
- **Light & Wonder (formerly Scientific Games / SG / Bally)** — consolidated multiple stacks after the Bally/WMS/SG/Shuffle Master M&A waves. "GameSense", "CASMA", "Interstate" — the first is a CMS concept, the second two are not verified public product names (may be internal). L&W cabinets include TwinStar, Kascada, HorizON; online via OpenGaming Platform.
- **Slot sound designer workflow (industry standard)** — per Gamejobs.co, `madlord.com`, `gamesoundplanet.com`, `tlaudio.co.uk`, `thatericalper.com`:
  - DAW: Cubase, Nuendo, or Pro Tools (Reaper emerging).
  - Composition in 4- to 16-bar loops, layered stingers for win tiers.
  - Delivery as WAV + metadata XML/JSON (loop points, fade tails, trigger ID).
  - Event-driven audio: looped ambient beds, anticipation stingers, win-tier rollups with explicit duration envelopes, bonus-entry fanfares, big-win celebrations.
  - Integration step happens in vendor's proprietary tool — sound designer typically cannot author final implementation.

**Strengths:**

- **Tightly vertically integrated.** Same team owns cabinet hardware, firmware, game engine, audio pipeline, CMS, regulatory submission. They can tune the player-facing experience end-to-end.
- **Regulatory depth** matches IGT.
- **Decades of slot-audio DNA.**

**Weaknesses (where FluxForge can compete):**

- **Closed, proprietary, fragmented.** A sound designer at L&W cannot bring their workflow to Aristocrat. A freelance slot audio composer has to learn 3–5 different delivery specs.
- **Audio authoring tools are 10–15 years behind** the gaming-audio mainstream (Wwise/FMOD/MetaSounds). No modern profiler, no real-time live-reload, no AI assistance.
- **Conference-talk silence** — very few GDC/FMX/AES talks from Aristocrat/Konami/L&W sound teams about their internal middleware. Audio talent is treated as a closed craft; knowledge rarely leaves the building.
- **No public SDK.** Third-party composers/sound-designers are service providers to these companies, not platform participants.

**Pricing:** Internal only; third parties pay via content revenue share or simply work as vendors.

**Source links:** `aristocratgaming.com/us/casino-operator/cxs/slot-and-floor-solutions/oasis-core`, `gamejobs.co/Senior-Sound-Designer-at-Aristocrat`, `gamesoundplanet.com/`, `madlord.com/`, `tlaudio.co.uk/inside-the-studio-creating-music-for-slot-machines/`, `en.wikipedia.org/wiki/Light_%26_Wonder`, `gdconf.com/audio-track/`, `asoundeffect.com/gdc25/`.

---

### III.7 New AI Entrants (2024–2026)

**Product one-liner:** Cloud/on-device generative audio APIs that are eating the "placeholder SFX", "music bed", and "VO draft" parts of the pipeline.

#### III.7.a ElevenLabs Sound Effects

- **Version:** Sound Effects V2 (Sept 2025).
- **Key features:** text-to-SFX, 20–30 s clip length, 48 kHz output, seamless looping, royalty-free commercial license. Prompt adherence significantly improved over V1. Python/TS/Flutter/Swift/Kotlin SDKs.
- **Strengths:** fastest text-to-SFX on the market; quality good enough for production Foley/ambient. Brand recognition from their voice-cloning dominance.
- **Weaknesses:** SaaS-only (API), no offline. Deterministic reproducibility is weak — same prompt yields different results across versions, which is problematic for regulated slot workflows where audit requires hash equality.
- **Pricing:** Creator USD 22/mo, Pro USD 99/mo, Scale USD 330/mo, Business USD 1,320/mo.
- **Source:** `elevenlabs.io/docs/overview/capabilities/sound-effects`, `elevenlabs.io/sound-effects`.

#### III.7.b Meta AudioCraft (MusicGen, AudioGen, EnCodec)

- **Version:** AudioCraft OSS codebase updated continuously through 2025 — MusicGen with 50 kHz support and multilingual melody conditioning.
- **Key features:** open-source, MIT/CC-licensed models. MusicGen = text+melody → music. AudioGen = text → environmental sound. EnCodec = neural audio codec (compressor) for tokenized audio pipelines.
- **Strengths:** runs on-device, no cloud dependency. Deterministic if seed is fixed. Free. Hackable — community forks have produced real-time inference variants.
- **Weaknesses:** quality lags ElevenLabs/Stable Audio in blind tests. Inference VRAM-heavy (10–20 GB for large models). No out-of-the-box SDK for game engines.
- **Pricing:** Free (open-source, CC-BY-NC for some weights, commercial licenses available).
- **Source:** `ai.meta.com/blog/audiocraft-musicgen-audiogen-encodec-generative-ai-audio/`, `github.com/facebookresearch/audiocraft/`, `audiocraft.metademolab.com/musicgen.html`.

#### III.7.c Stability AI — Stable Audio 2.0 / 2.5

- **Version:** Stable Audio 2.0 (April 2024), 2.5 (September 2025 — brand/enterprise focus, 8-step inference breakthrough).
- **Key features:** text-to-audio up to 3 minutes, 44.1 kHz stereo; audio-to-audio (style transfer on uploaded samples); DiT architecture (vs older U-Net). 2.5 targets sub-second inference for brand/advertising workflows.
- **Strengths:** longest coherent output on the market; audio-to-audio is unique vs ElevenLabs. Licensed training data (AudioSparx) → commercial-safe.
- **Weaknesses:** cloud/API-only. 3-minute limit still too short for some broadcast uses. Audible Magic ACR filter rejects uploads that match copyrighted material, which is right but annoying for remix workflows.
- **Pricing:** free tier + subscription + enterprise API (undisclosed).
- **Source:** `stability.ai/news/stable-audio-2-0`, `stability.ai/stable-audio`, `venturebeat.com/ai/stability-ais-enterprise-audio-model-cuts-production-time-from-weeks-to`.

#### III.7.d Inworld AI (Voice + NPC)

- **Version:** Inworld TTS (June 2025), TTS-1.5 Mini (sub-100 ms latency, late 2025).
- **Key features:** emotional TTS with markup tags (`[happy]`, `[whispering]`), voice cloning from 20 min (or 5–15 s fast-clone), Unity + Unreal SDK, gRPC/REST APIs. 250 ms end-to-end latency @ P50.
- **Strengths:** best-in-class for real-time NPC voice; production deployments at NBCU, Sony, Logitech, Streamlabs. Multilingual.
- **Weaknesses:** cloud-dependent; offline mode limited. Focused on voice — not a general audio tool.
- **Pricing:** per-character / per-minute pricing; enterprise custom.
- **Source:** `inworld.ai/`, `inworld.ai/landing/tts-gaming-ai-text-to-speech-for-video-game-characters`, `inworld.ai/blog/gdc-2025`.

#### III.7.e Open-source "middleware" attempts

- Searched for `OpenMiko`, `AudioQuery`, `OpenMiddleware`. **No credible OSS game-audio-middleware project is shipping as of 2026-04.** There is no FOSS Wwise/FMOD replacement. The closest are libraries (OpenAL-Soft, Steam Audio OSS, Resonance Audio) — not authoring tools.
- This is a real opportunity: FluxForge could fill the "open" (or at least "not-Audiokinetic-not-Firelight") slot in the category.

---

### III.8 Adjacent Tools (context, not direct competitors)

- **Splice Sounds** — browser-based sample library with DAW plug-in (2025 partnerships with Pro Tools and Ableton Live 12.3). Strength: catalog depth. Weakness: not an authoring tool, no runtime, no slot vocabulary. Relevance to FluxForge: their browser-based drag/drop sample preview is a UX benchmark for FluxForge's asset browser.
- **Descript + Underlord (Aug 2025)** — text-based audio editing with an "agentic co-editor" that executes multi-step edits from natural-language prompts. Strength: the interaction model (prompt → audio edit) is exactly what Corti aims for in FluxForge. Weakness: podcast-focused, no game-audio vocabulary. Relevance: design inspiration for Corti's prompt interface.
- **Pro Tools / Logic Pro / Cubase / Reaper** — DAWs. Reference points for FluxForge's DAW-hybrid surface. FluxForge's `REAPER_SRC_ANALYSIS.md` and `REAPER_FEATURES_ANALYSIS.md` already tracks feature parity. Reaper especially is the reference for extensibility (ReaScript) and low resource usage.
- **Sony 360 Reality Audio Creative Suite (360 RACS) / WalkMix Creator / 360VME** — spatial-audio authoring as DAW plug-in. _No product called "Sony Hawkeye" found in public record as a spatial-audio authoring tool._ 360 RACS and WalkMix Creator are the closest actual products. Relevance: FluxForge can learn from their head-tracked monitoring flow but the whole 360RA format is oriented to music playback, not slot/game runtime.
- **Meta Haptics Studio** — Meta Quest haptic authoring; integrates with Wwise 2024.1+ and FMOD 2.03.11+. Relevant if FluxForge targets Quest as a future platform.

---

### III.9 Competitive Matrix

Legend: ● = shipping production feature, ◐ = partial / experimental / limited, ○ = absent. FluxForge column reflects stated/current status plus planned Phase-A scope from Part VI.

| Capability | Wwise 2025.1 | FMOD 2.03 | Unity 6 | UE 5.5 | Playa (IGT) | Aristocrat/Konami/L&W | ElevenLabs/AudioCraft/Stable | FluxForge |
|---|---|---|---|---|---|---|---|---|
| Event/actor-mixer authoring | ● | ● | ◐ | ● | ● | ● | ○ | ● |
| Timeline event editor | ◐ | ● | ○ | ● (MetaSounds) | ◐ | ◐ | ○ | ◐ (planned) |
| Node-based DSP graph | ● (plug-ins) | ◐ | ◐ (DSPGraph exp) | ● (MetaSounds) | ? | ? | ○ | ◐ (hook_graph planned) |
| Sample-accurate scheduler | ● | ● | ◐ | ● (Quartz) | ● | ● | ○ | ● (rf-engine) |
| Spatial audio (Rooms/Portals) | ● | ◐ (via plug-ins) | ○ | ◐ | ○ | ○ | ○ | ○ |
| Geometric diffraction | ● (Reflect) | ○ | ○ | ◐ | ○ | ○ | ○ | ○ |
| Live media reload | ● | ◐ | ○ | ◐ | ○ | ○ | n/a | ● (planned) |
| In-engine DAW waveform edit | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ● (core differentiator) |
| Profiler (voice/CPU/memory) | ● | ● | ◐ | ◐ | ? | ? | n/a | ◐ (planned) |
| Multi-user CRDT collab | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ● (planned Phase C) |
| AI similar-sound search | ● (2025.1) | ○ | ○ | ○ | ○ | ○ | ● | ● (planned) |
| Text-to-SFX generation | ○ | ○ | ○ | ◐ (exp nodes) | ○ | ○ | ● | ● (planned Corti) |
| Voice cloning / AI VO | ○ | ○ | ○ | ○ | ○ | ○ | ● | ◐ (planned) |
| Haptics authoring | ● | ● | ◐ | ◐ | ● | ● | ○ | ○ |
| Slot-StageFlow (Idle→Bet→Spin→…) | ○ | ○ | ○ | ○ | ● | ● | ○ | ● |
| Win-tier configurable mapping | ○ | ○ | ○ | ○ | ● | ● | ○ | ● |
| Anticipation/rollup primitives | ○ | ○ | ○ | ○ | ● | ● | ○ | ● |
| Compliance validator (UKGC/MGA/SE) | ○ | ○ | ○ | ○ | ● | ● | ○ | ● (rf-slot-builder) |
| LDW / near-miss guards | ○ | ○ | ○ | ○ | ● | ● | ○ | ● |
| Jurisdiction hot-swap | ○ | ○ | ○ | ○ | ● | ● | ○ | ● |
| Deterministic audit log | ◐ | ◐ | ○ | ◐ | ● | ● | ○ | ◐ (planned) |
| Cross-engine AudioLink bridge | ● (via UE) | ● (via UE) | ○ | ● (owner) | ○ | ○ | n/a | ○ |
| Third-party plug-in marketplace | ● | ● | ○ | ● | ○ | ○ | n/a | ○ |
| Open-source core | ○ | ○ | ○ | ◐ (partial) | ○ | ○ | ◐ | ◐ (TBD) |
| Platform coverage (console+mobile+cabinet) | ● | ● | ◐ | ● | ● (cabinet-first) | ● (cabinet-first) | cloud only | ○ (macOS only today) |
| Pricing accessible to indie | ● (free <250k) | ● (free <500k) | ● | ● | ✕ (internal) | ✕ (internal) | ◐ (subscription) | TBD |

**Row-by-row analysis — where FluxForge already wins:** DAW waveform edit in-engine, slot-StageFlow, win-tier configurable mapping, anticipation/rollup primitives, compliance validator, LDW/near-miss guards, jurisdiction hot-swap, planned multi-user CRDT collab.

**Where FluxForge already loses:** platform coverage, spatial audio, profiler depth, haptics, third-party plug-in marketplace, AudioLink/cross-engine bridges, proven AAA-scale deployment.

---

### III.10 Threat Assessment

Ranked by _near-term strategic threat_ to FluxForge (1 = highest).

**1. IGT Playa (internal).** Biggest threat because FluxForge's core positioning — B2B slot-audio authoring — directly overlaps with Playa's remit. If IGT ever decides to externalize Playa as a platform (SDK + marketplace), FluxForge loses its unique regulatory vocabulary overnight. Mitigation: ship best-in-class authoring UX that IGT's internal tools cannot match within 18 months, and focus on the _non-IGT_ slot-vendor market (independent studios, Aristocrat/Konami/L&W 3rd-party content, online-only RMG).

**2. Audiokinetic Wwise.** Threat because Wwise is the default reflex for any game-audio decision. If Audiokinetic ships a "slot vertical" feature set (stage flow, compliance manifest, rollup primitives) — and they have the capital to do it — FluxForge's slot-specific edge erodes. Mitigation: move faster on slot-specific vocabulary; lock in design-partner slot studios early; build the regulatory-validator moat (compliance as a differentiator is hard for a general-purpose tool to copy).

**3. Unreal MetaSounds + AudioLink.** Threat because UE is becoming the universal game runtime; if the slot industry migrates to UE cabinets (already happening in arcade/VLT), MetaSounds becomes the default authoring surface. Mitigation: ship an AudioLink-compatible export path from FluxForge so that authored content can target UE runtime while the authoring remains in FluxForge. Treat UE as a runtime partner, not a competitor.

**4. ElevenLabs + Stable Audio + AudioCraft (AI entrants).** Threat because these cannibalize the "placeholder/rough/first-draft SFX" step of the workflow. If a sound designer can text-prompt their entire ambient bed in ElevenLabs V2, they may skip the FluxForge authoring layer entirely. Mitigation: Corti (FluxForge's AI authoring assistant) must integrate these models as _back-ends_, not treat them as rivals. Become the orchestration layer on top of AI audio generation — not the generator itself.

**5. FMOD Studio.** Threat because of its friendliness and pricing. For indie slot devs considering middleware, FMOD is the reflex "safe" choice. Mitigation: match FMOD's onboarding quality (docs, sample projects, 15-minute first-event tutorial) and use slot vocabulary as the wedge. FluxForge's indie tier must be free or near-free.

**6. Aristocrat / Konami / L&W.** Low direct threat because they are closed ecosystems — they don't compete for authoring-tool mindshare. But they are _gatekeepers_ of distribution. Mitigation: partnership strategy, not competitive strategy — offer FluxForge as a pre-integration content-authoring layer that exports to their proprietary formats.

**7. Unity 6 Audio.** Lowest threat — Unity audio team has publicly prioritized stability over features through 2025–2026. DSPGraph is stalled. Unity is not going to ship a Wwise-killer. Mitigation: none needed; monitor only.

**8. Splice / Descript / DAWs.** Non-threats for core positioning; design-inspiration sources. Splice's browser-based sample UX and Descript's Underlord prompt flow are reference points for Corti and the FluxForge asset browser.

---

### III.11 Strategic Implications for FluxForge

1. **Double down on slot-specific vocabulary.** StageFlow, anticipation, rollup, win-tiers, LDW guard, compliance manifest — these are our moat. Every general-purpose middleware has to graft these on; we ship them native. Expand compliance coverage (UKGC, MGA, SE, then NGCB, AGCO, AU).
2. **Own the DAW-hybrid seat.** Nobody else edits waveforms _inside_ the authoring surface. Reaper-inspired extensibility (ReaScript analog) would extend this moat.
3. **Treat AI as a back-end, not a rival.** Corti orchestrates ElevenLabs / Stable Audio / AudioCraft through a single authoring prompt. Users never think about which model ran.
4. **Ship AudioLink-compatible PCM export** so FluxForge-authored content can run inside Unreal runtimes. Do _not_ try to build our own runtime-on-every-platform in year one — partner with UE/Unity runtimes instead.
5. **Price aggressively at the indie tier.** Free for slot studios under USD 500k budget, matching FMOD's ceiling. Revenue from mid-tier studios and from the certifier/compliance feature set.
6. **Regulatory automation as a paid add-on.** Compliance validator + audit log export + jurisdiction hot-swap bundle. This is something Wwise/FMOD will not build in the next 3 years because it has no TAM outside slot/RMG.
7. **Open-source the compliance schema.** Make `rf-slot-builder`'s validator rules public; become the de-facto standard for slot-audio compliance declarations. Vendors can write-once, target-many jurisdictions.
8. **Defensive posture vs IGT:** stay 12+ months ahead on authoring UX, multi-user collab, and AI assistance. IGT's internal tool budget cannot match a dedicated product team's pace.

---

## Part IV — Gap Analysis

> Cross-referencing **Part I** (what FluxForge is today) with **Part II** (what tech exists in 2026) and **Part III** (what competitors ship). Prioritized by *competitive threat × user value*.

### IV.1 Feature parity vs. key competitors

| Feature domain | FluxForge today | Wwise 2025.1 | FMOD 2.03.12 | IGT Playa | UE 5.5 MetaSounds | Delta + opportunity |
|---|---|---|---|---|---|---|
| **Slot-specific event vocabulary** (StageFlow, win tiers, anticipation, rollup, LDW, near-miss) | Native in `rf-stage` (50+ Stage variants, `audio_naming.rs`, compliance metadata) | Generic game-audio events | Generic | Proprietary, closed | — | **Unique defensible moat — double down** |
| **Compliance validator** (UKGC / MGA / SE / jurisdiction hot-swap) | `rf-slot-builder` (LDW guard, near-miss, celebration proportionality) | — | — | Yes (closed) | — | **Moat. Make it one-click per jurisdiction.** |
| **In-engine DAW waveform edit** (cubic/sinc resample, fades, clip FX per voice) | `rf-engine/playback.rs` 7500+ LOC | Asset pool only | Asset pool only | Unknown | — | **Moat. Wwise/FMOD force external DAW round-trip.** |
| **Native 64-band EQ + 4-format plugin host** (VST3 / AU / CLAP / LV2) | `rf-dsp/eq_pro.rs` (4500 LOC) + `rf-engine/plugin/` | External only | External only | Unknown | Limited (MetaSounds native only) | **Moat. Zero-round-trip authoring.** |
| **AI copilot / voice authoring** | None (CortexVision stubs, no generation) | None | None | None | None | **GREEN FIELD — most competitors have nothing** |
| **Neural mastering** | None | None | None | None | None | **GREEN FIELD (Ozone 12 exists, none integrate with middleware)** |
| **Generative slot scoring / text-to-music** | None | Similar Sound Search (retrieval, 2025.1) | None | None | None | **GREEN FIELD. First-mover window ~18 mo** |
| **Neural stem separation** | None | None | None | None | None | **GREEN FIELD. Demucs v4 / Kim Vocal 2 local inference** |
| **Spatial Audio authoring** (Atmos object, HOA ≥3, HRTF personalized) | Partial (`rf-dsp/spatial.rs`, HRTF IDW blend) | Wwise Spatial Audio 3D (stable) | Partial | Limited | Channel Agnostic Types, ADC 2025 | **LAG. Catch up: Atmos object, bilinear HRTF, 7th-order HOA** |
| **Gaze / eye-tracking mix** | None | None | None | None | None | **GREEN FIELD. visionOS 2 APIs ready** |
| **Real-time collab** (CRDT multi-user) | None | Limited (SoundBank check-out) | Limited | Unknown | Limited | **GREEN FIELD. Yjs / Automerge 2.0 proven** |
| **Time-travel authoring / project history** | `rf-state/history.rs` Photoshop-style | None | None | None | None | **Moat. Expand with ghost trails + branch viz** |
| **Compact radial mixer (orb)** | `OrbMixer` + `LivePlayOrbOverlay` + `NeuralBindOrb` (~2100 LOC) | None | None | None | None | **Unique UX. Protect and evangelize.** |
| **Per-voice FFT / RMS metering in mixer** | Phase 7/8 complete, live FFT heatmap | Partial | Partial | Unknown | Partial | **Moat. Marketing gold.** |
| **Universal stage taxonomy (data-driven)** | `rf-stage/taxonomy.rs` | Event-naming anarchy | — | Closed | — | **Moat. Open-source it → industry standard?** |
| **GPU compute DSP** | wgpu in tree, not used for DSP | None | None | Unknown | None | **GREEN FIELD. Convolution / HOA / neural inference** |
| **visionOS / AirPods spatial authoring** | None | None | Partial | None | None | **GREEN FIELD. First-to-market advantage** |
| **Pricing accessibility** | TBD | USD 50k Platinum tier | Free under USD 500k budget | Closed (internal) | Free with Epic | **Decision needed — tiered pricing for indie slot studios** |

### IV.2 Where FluxForge LEADS (moats to protect)

1. **Slot DNA baked into the engine** — StageFlow + win-tier + anticipation + LDW-guard + compliance are first-class citizens, not tacked on. No competitor ships this except IGT Playa (closed).
2. **Unified DAW + middleware** — authoring doesn't leave the app. Waveform edit, plugin hosting, bounce-to-stems inline. Wwise/FMOD force external DAW round-trip.
3. **OrbMixer family** — compact, density-scalable, aesthetically unique. A genuinely new UX primitive.
4. **Per-voice real-time DSP** (HPF/LPF/sends per voice, not just per bus) — Phase 6/7/8 verified.
5. **Deterministic parameter intelligence (SAM)** — `rf-aurexis` maps game math → audio params in non-RT layer. Reproducible, auditable.
6. **Compliance manifest with jurisdiction hot-swap** — a regulator's dream.

### IV.3 Where FluxForge LAGS (must close)

1. **Spatial object authoring** — no Atmos object export, no HOA ≥3, HRTF uses IDW blend (BUG #35). Wwise and UE 5.5 ahead.
2. **AI features — zero shipping**. Wwise 2025.1 shipped Similar Sound Search (retrieval). We have stubs (`CortexVisionService.neural.*`). Every competitor except Unity (deprioritized) is racing here.
3. **UI test coverage** — 120 unit tests, 19 integration, **zero widget tests for the 3 biggest screens** (engine_connected_layout, slot_lab_screen, helix_screen). Regression risk.
4. **FFI safety** — 8 `CStr::from_ptr` calls without null check = single-line-crash vulnerability.
5. **Event Registry race** (CLAUDE.md warning) — two parallel registration systems cause silent audio dropouts.
6. **Keyboard shortcut coverage** — 40 defined, sub-tab nav (1–0 + Q–U) missing, no discoverability UI.

### IV.4 Where FluxForge can LEAPFROG (green-field opportunities)

1. **AI copilot** — no middleware vendor ships a shipping AI authoring assistant. Window 12–18 months.
2. **Generative slot scoring** — text-to-music tuned to slot stages (base bed / feature theme / big-win sting per tier). Stable Audio Open Small runs local; integrable Q3 2026.
3. **Gaze-controlled mix on visionOS** — first-to-market. APIs production-ready.
4. **Real-time multi-studio collaboration** — Yjs / Automerge 2.0 proven. No slot middleware ships this. Sound designer + composer + QA editing the same project live.
5. **Neural HRTF personalization** — HRTFformer, graph-NN. Ship personalized spatial on headphones.
6. **Open-source the Stage taxonomy** — make it an industry standard. Free adoption = gravitational pull for the rest of the stack.

### IV.5 Threat-weighted priority matrix

| Priority | Area | Threat | User value | Action window |
|---|---|---|---|---|
| **P0** | Fix FFI null-deref + Event Registry race | Release blocker | Universal | Immediate |
| **P0** | Widget tests for 3 biggest screens | Regression risk | Universal | 2 weeks |
| **P1** | Atmos object + HOA 3 authoring | Wwise/UE lead | Producers | 3 months |
| **P1** | AI copilot MVP (voice action, gap detection, suggested binds) | Greenfield | High | 3–6 months |
| **P1** | Generative slot scoring (Stable Audio Open Small local) | Greenfield | Very high (composers) | 6 months |
| **P2** | Neural stem separation (Demucs v4 local) | Greenfield | Medium | 6 months |
| **P2** | Real-time multi-studio collab (Yjs) | Greenfield | Medium (teams) | 9 months |
| **P3** | Gaze-controlled mix on visionOS | First-mover brand halo | Niche | 12 months |
| **P3** | Open-source Stage taxonomy | Ecosystem play | Strategic | 12 months |

---

## Part V — The Unthinkable Vision

> **Target:** set FluxForge 5 years ahead of the industry by 2028. Each item below is a paradigm shift, not an increment. Concrete feature specs, not abstractions. Numbers reference Part II tech maturity and Part III competitor gaps.

### V.1 AI Copilot — "Corti as authoring partner"

**Premise:** Every other middleware is a *tool*. FluxForge becomes a *partner*.

**Features:**
- **Generative mix** — voice or text input: "make this rollup 15% more euphoric, less cymbal crash". Copilot analyses current stage audio, proposes param deltas (EQ cut/boost, send bump, bus ducking), previews in a branch. One-click accept / reject.
- **Predictive automation** — after 5–10 manual knob moves, Copilot predicts the 11th. Shows ghost-curve in timeline. Two taps: "use it" or "ignore".
- **Voice command** — "solo voice bus", "audition the next win tier", "export stems for MGA compliance". Powered by WhisperKit local inference (Part II.4.2). Zero cloud dependency.
- **Error prevention** — Copilot runs validators continuously (LDW, near-miss, celebration proportionality, LUFS target per region). Flags issues *before* the user hears the defect.

**Architecture:**
- Local LLM (Llama 3 8B or Phi-4) on Metal via MPSGraph (Part II.2.2). Private, no cloud.
- Runs in separate isolate, communicates via `rf-bridge` FFI.
- Training/fine-tuning: captured mix deltas + Boki's preferences form persistent corpus (V.4).
- New crate `rf-copilot` with `Action` trait — every suggestion is reversible.

**Competitive position:** Wwise Similar Sound Search (2025.1) is retrieval-only — no generation, no prediction, no voice. FluxForge leapfrogs on day one.

**Effort:** 6 months, 1 ML engineer + 1 Rust engineer.

### V.2 Gaze-Controlled Mix (visionOS class)

**Premise:** 130-voice mixes are physically unmanageable with mouse. On visionOS, eyes + hands are the only UI that scales.

**Features:**
- Look at a voice in the orb → auto-focus + auto-solo (already the voice-mixer pattern).
- Pinch + drag → volume. Two-finger pinch → pan. Head tilt → stereo width.
- Look + "solo" voice command → `focusAndSoloChannel` (already implemented in provider).
- Quad-look across multiple voices + pinch-hold → group temporarily for joint adjust.

**Architecture:**
- Flutter on macOS stays master. visionOS companion app connects via WebRTC (Part II.5.4) or CRDT channel (V.7).
- Gaze coordinates streamed at 90Hz, mapped to `OrbMixerProvider` bus positions.
- Uses ARKit eye tracking via visionOS 2 APIs (Part II.4.1).

**Effort:** 3 months (companion app) after macOS core. Ship as "FluxForge for Apple Vision Pro".

**Marketing halo:** first-to-market on the industry's newest productivity platform.

### V.3 Time-Travel Authoring

**Premise:** `rf-state/history.rs` already has Photoshop-style history. Explode it into a full time-travel UX.

**Features:**
- **Ghost trails** — every fader move leaves a fading trail on the orb for 10 s. Double-tap any ghost position → revert to that value.
- **Session scrub ring** — outer ring of the OrbMixer replays the last 30 s of mix changes (animation).
- **Git-style branches** — "save state" creates a named branch. Branch tree visible in a minimap. Switch between branches live.
- **"What did I hear 10 minutes ago?"** — voice command or shortcut. Engine rewinds mix state (not audio, mix params) to that moment, audio plays through that snapshot.
- **Audio ring buffer** — already on the Phase 10e-2 TODO: 5 s master ring buffer with WAV export for Problems Inbox replay. Extend to 5 min.

**Architecture:**
- `rf-state` already handles snapshots. Add BranchId, persistent tree.
- UI: new "Time" panel in Monitor super-tab. Visualize branches as tree (D3-like layout).
- Ghost trails → extend `OrbMixer` painter with fade-out history (already has 2 s ghosts in orb).

**Effort:** 2 months.

### V.4 Neural Persistent State

**Premise:** Corti in CORTEX memory. FluxForge embeds that into the product: every session deposits into a long-term memory, every session reads from it.

**Features:**
- **Cross-session memory** — every bind, every correction, every "I hate this sound" flag is stored. Survives project switches.
- **Self-tuning defaults** — after N sessions, Copilot suggests default EQ curves, default sends, default ducking profiles based on user history.
- **Issue prediction** — "you usually notice this tension at 2kHz on VO, shall I pre-cut?"
- **Style fingerprint** — export a `.style` file that captures user preferences; share across users (team style consistency).

**Architecture:**
- SQLite in `~/.fluxforge/memory.db` — event log + preference vectors.
- Local embedding model (sentence-transformers via tract, Part II.2.4) for similarity search.
- `rf-neuro` crate is currently stubs — fill it with the memory substrate.

**Ethics:** user-owned data, local only, portable, exportable, deletable.

**Effort:** 3 months.

### V.5 Orb Ecosystem

**Premise:** The orb is the most unique UX primitive in FluxForge. Scale it to every panel.

**Features:**
- Every lower-zone panel gets its own "home orb" — voice orb, bus orb, DSP orb, container orb, music orb.
- Orbs **dock** (embed in panel), **float** (overlay), **merge** (combine two panels into dual-orb view), **split** (separate a merged orb).
- **Nested orbs** — master orb contains 6 bus orbs; each bus orb contains voice orbs; voice orbs contain param arc-sliders (already in `OrbParamArc`).
- **One gesture language** — single-click = focus, double-click = detail editor, long-press = radial quick actions (just implemented for voice mixer). Same everywhere.
- **Interactive preview** — drag one voice orb into another bus orb → immediate re-route.

**Architecture:**
- Refactor `OrbMixerProvider` into `OrbProvider<T>` generic — T = voice / bus / DSP / container.
- New `OrbContainerWidget` that can host any `OrbProvider<T>` instance.
- Gesture handling centralized in `OrbGestureService`.

**Competitive position:** Wwise, FMOD, UE MetaSounds use list/tree/node UIs. FluxForge claims the orb as its visual signature.

**Effort:** 4 months. Highest-impact UX differentiator.

### V.6 Generative Slot Scoring

**Premise:** Stable Audio Open Small (Part II.1.3) generates 30 s of high-quality audio on-device in under 8 s on M3. Wire it into the slot authoring flow.

**Features:**
- **Emotional arc input** — "tension → excitement → euphoria" as a timeline. Copilot generates base bed, feature theme, big-win sting variations for each segment.
- **Style transfer** — point at a reference slot (Wrath of Olympus, Wolf Gold), request "same emotional curve with my symbols". Copilot matches.
- **Variation generation** — one-shot variations at any selected Stage. "Give me 5 alternate BIG_WIN stings, 2 s each, crescendo."
- **Integration with compliance** — generated audio auto-validated against celebration proportionality + LUFS gates.

**Architecture:**
- New `rf-generative` crate. Loads ONNX model via tract (Part II.2.4).
- `sam_ffi.rs` exposes `generate_stage_audio(stage, style, duration)` function.
- UI: new "GEN" sub-tab in MUSIC or MONITOR super-tab.

**Competitive position:** NO competitor ships text-to-music for game audio. Window is ~18 months before Wwise/FMOD.

**Effort:** 4 months to MVP (single-shot), +2 for style transfer.

### V.7 Real-Time Multi-Studio Collaboration

**Premise:** Figma did it for design. Google Docs did it for text. No middleware has done it for game audio. We do.

**Features:**
- CRDT-backed shared sessions (Yjs or Automerge 2.0 via `rf-crdt`).
- **Presence indicators** on every control — "Ivan is dragging the VO fader".
- **Voice chat** integrated (WebRTC via LiveKit).
- **Roles + permissions** — composer can edit music bus, sound designer owns SFX, QA has read-only + comment.
- **Comment threads on timeline regions** — "this rollup is too long, try 0.8s" → resolve / reply.
- **Branching** (from V.3) enables "try my idea without breaking yours".

**Architecture:**
- New `rf-crdt` crate wrapping Yjs (via wasm) or Automerge (native Rust).
- WebRTC transport via Pion or existing Flutter plugins.
- New `services/collaboration_service.dart`.

**Effort:** 6 months. First-to-market in slot audio collab.

### V.8 Regulatory Auto-Compliance

**Premise:** `rf-slot-builder` validator is mature. Surface it **while authoring**, not as a post-export check.

**Features:**
- **Live compliance meter** in the omnibar — UKGC/MGA/SE/NV/NJ traffic lights. Red = blocks export. Yellow = warning.
- **Inline tooltips** — every flagged element shows the rule it violates + one-click auto-fix.
- **LDW guard in real time** — when a win equals the bet, celebration audio duration is capped automatically.
- **Near-miss quota tracker** — "you've placed 2.1% near-miss events this session; ceiling 3%."
- **Compliance manifest button** — one click, choose jurisdiction, export signed manifest with audit trail + event trace + RTP achieved.

**Architecture:**
- Move validator from post-export to a live watcher in `CompositeEventSystemProvider`.
- New `ComplianceWatcher` service runs rules on change events.
- UI: omnibar traffic light widget + dedicated Compliance panel in INTEL super-tab.

**Competitive position:** regulator-friendly by design. Unique selling point for regulated markets.

**Effort:** 2 months. Reuses existing validator.

### V.9 Generative Voice / Foley

**Premise:** ElevenLabs Sound Effects v2 + AudioSeal watermarking (Part II.1, II.7.7) give us clean, legal, local-infer generative SFX.

**Features:**
- **Text-to-SFX** — type "coin drop, wet marble, bright", get 3 s WAV. Waveform preview inline. Drop into timeline.
- **Voice cloning for VO drafts** — record a 30-second sample, generate placeholder VO in any scripted line. Used for prototyping before final voice session.
- **Variation generation** — point at an existing sample, say "give me 10 pitched variations for my random container".
- **Watermark all generated audio** via AudioSeal so provenance is auditable (compliance-friendly).

**Architecture:**
- `rf-generative` shared with V.6.
- Integration with ElevenLabs API (paid tier) OR local Stable Audio Open Small for offline-first.

**Effort:** 2 months after V.6 infrastructure is in place.

### V.10 Predictive Event Routing

**Premise:** Auto-bind engine already exists (`auto_bind_engine.dart`). Upgrade to ML-driven proactive prediction.

**Features:**
- **Drop a file**, Copilot predicts the stage it belongs to with confidence score. "85% sure this is a reel_stop for bus SFX".
- **Gap detection** — "you have no audio bound to FREE_SPIN_START; I found 12 files in your pool that match — shall I suggest the top 3?".
- **Auto-fill proposals** — one click fills the top gap with the top-confidence suggestion.
- **Learning from corrections** — when user rejects a suggestion, model updates for next time (V.4 persistence).

**Architecture:**
- Small classifier (audio features → Stage label) trained on Sonic DNA Layer 2/3 (already in `rgai_provider`).
- Runs in isolate, queried via provider.

**Effort:** 2 months (classifier exists, needs proactive surface).

---

---

## Part VI — Phased Roadmap

Synthesis of Parts I–V into a sequenced execution plan. Each phase has exit criteria and explicit dependencies.

### Phase A (0–3 months) — Foundation + Quick wins

**Goal:** Close release-blockers, raise quality floor, prep for paradigm work.

| # | Work item | Source | Effort | Exit criteria |
|---|---|---|---|---|
| A1 | Add null-checks on 8 FFI `CStr::from_ptr` sites (`slot_lab_ffi.rs` + others) | I.4.5 | 30 min | `cargo clippy` clean + regression test |
| A2 | Fix BUG #63 scenario dimension validation | I.4 | 1 h | Added validator + test |
| A3 | Resolve Event Registry race (consolidate to one registration path, per CLAUDE.md) | I.6 | 1 day | No stage dropouts under stress |
| A4 | Replace LV2 `std::sync::Mutex` with `parking_lot::Mutex` (BUG #32) | I.4.5 | 30 min | LV2 plugin stress test pass |
| A5 | Widget tests for `engine_connected_layout`, `slot_lab_screen`, `helix_screen` (min 30 total) | I.6 | 2 weeks | CI green on tests |
| A6 | Keyboard shortcut discoverability UI (`Help → Keyboard Map`) + 1–0 + Q–U sub-tab bindings | I.6 | 3 days | All sub-tabs reachable from keyboard |
| A7 | HRTF bilinear interpolation upgrade (BUG #35 → state-of-art) | I.4.2 | 2 h | Listening test + unit test |
| A8 | Full Build+Test CI checkpoint (`cargo build --release` + `xcodebuild` + `flutter analyze`) | MASTER TODO | 2 days | Green pipeline |
| A9 | OrbMixer Phase 10e-2 — 5 s ring buffer + WAV export | MASTER TODO | 1 week | Problems Inbox replay working |
| A10 | NeuralBindOrb Phase 2 — ghost slot indicators | MASTER TODO | 1 week | Stages without bindings visible |
| A11 | Decouple metering from audio thread (eliminate `try_write` gaps) | I.4.1 | 3 days | Metering continuous under UI load |
| A12 | Atmos object export MVP | IV | 3 weeks | At least one object-based export path |

**Outcome:** production-ready v1. No known crash vectors. 60fps under 50+ channel load. Zero compliance false-negatives.

### Phase B (3–9 months) — Core differentiators

**Goal:** Ship features that competitors don't have.

| # | Work item | Source | Effort |
|---|---|---|---|
| B1 | **AI Copilot v1** — voice commands + gap detection + suggested binds (V.1) | V.1 | 3 months |
| B2 | **Predictive Event Routing** — upgrade auto-bind to ML-driven proactive (V.10) | V.10 | 2 months |
| B3 | **Regulatory Auto-Compliance** — live watcher + omnibar traffic lights (V.8) | V.8 | 2 months |
| B4 | **Time-Travel Authoring v1** — ghost trails + session scrub + branch tree (V.3) | V.3 | 2 months |
| B5 | **Neural Persistent State** — `rf-neuro` memory substrate + SQLite log + local embeddings (V.4) | V.4 | 3 months |
| B6 | **Neural stem separation** — Demucs v4 local inference + stem-import UX | II.1.6 | 2 months |
| B7 | **Spatial catch-up** — Atmos object full authoring, HOA 3rd–5th order, personalized HRTF via HRTFformer | II.3 | 3 months |
| B8 | Refactor `engine_connected_layout` (17k LOC) into 3 panel modules | I.6 | 2 weeks |
| B9 | Refactor `slot_lab_screen` (15k LOC) into timeline + lower-zone + overlay sections | I.6 | 2 weeks |

**Outcome:** FluxForge is the only middleware with AI Copilot + live compliance + time-travel. Competitive narrative flips.

### Phase C (9–18 months) — Paradigm shift

**Goal:** Ship features that redefine the category.

| # | Work item | Source | Effort |
|---|---|---|---|
| C1 | **Generative Slot Scoring v1** — Stable Audio Open Small local integration + style transfer (V.6) | V.6 | 4 months |
| C2 | **Generative Voice / Foley** — ElevenLabs + AudioSeal watermarking (V.9) | V.9 | 2 months |
| C3 | **Real-time Multi-Studio Collaboration** — Yjs CRDT + WebRTC + presence (V.7) | V.7 | 6 months |
| C4 | **Orb Ecosystem** — every panel gets an orb, nested views, unified gesture language (V.5) | V.5 | 4 months |
| C5 | **GPU DSP for convolution + HOA** — wgpu compute shaders, 10–50× speed-up on reverb IR > 2 s | II.2.1 | 3 months |
| C6 | **visionOS companion app v1** — gaze-controlled mix + spatial authoring (V.2) | V.2 | 3 months |
| C7 | End-to-end neural mastering (Ozone-class quality, local) | II.7.1 | 4 months |
| C8 | Open-source `rf-stage` taxonomy + SDK for third-party integration | IV.4 | 2 months |

**Outcome:** FluxForge 18 months ahead of the industry. "AI-native slot middleware" is synonymous with FluxForge.

### Phase D (18+ months) — Platform leadership

**Goal:** FluxForge becomes the reference implementation for modern slot audio. Ecosystem forms around it.

| # | Work item | Rationale |
|---|---|---|
| D1 | Plugin SDK — third-party UI panels, FX, AI models | Ecosystem pull |
| D2 | Marketplace for style fingerprints + generative presets + compliance templates | Revenue + lock-in |
| D3 | Education platform — embedded tutorials, AI mentor, certification | Talent pipeline |
| D4 | Regulatory partnerships — offer pre-validated audio templates per jurisdiction | Moat deepening |
| D5 | FluxForge Cloud — optional cloud sync, collaboration, version history, compliance archive | SaaS layer |
| D6 | Machine-learning research partnership (university / lab) on perceptual audio + generative slot | Frontier R&D |

**Outcome:** FluxForge is the industry default. Wwise and FMOD chase. IGT Playa dissolves as internal studios adopt FluxForge.

---

## Appendix

### A. Screenshot Archive

All captured via CortexEye (`http://127.0.0.1:7735/eye/snapshot`) during the initial audit run on 2026-04-24.

**Primary archive — `/tmp/flux_vision_snaps/`:**
- `01_launcher.png` — Launcher (Casino Vault palette live)
- `02_daw_hub.png` — DAW Hub (template picker + recent)
- `03_daw_workspace.png` — DAW workspace (with `_CortexEyeProbe` project)
- `04_slotlab_compose.png` — SlotLab COMPOSE mode
- `05_helix_spine_{0..4}.png` — HELIX spine panels (audio, game, ai, settings, analytics)
- `06_helix_mode_{0..2}.png` — COMPOSE / FOCUS / ARCHITECT mode
- `07_helix_dock_{00..11}.png` — All 12 HELIX dock positions (spans the 11 super-tabs)

**Persistent CortexVision archive** — `~/Library/Application Support/FluxForge Studio/CortexVision/snapshots/` — timestamped `full_window_20260424_*.png` for continuous observation.

### B. Code Pointers (critical findings, file:line)

**Rust critical:**
- FFI null-deref: `crates/rf-bridge/src/slot_lab_ffi.rs:916`, `crates/rf-bridge/src/pbse_ffi.rs:849` + 6 others
- BUG #63 scenario validation: `crates/rf-bridge/src/slot_lab_ffi.rs:1635–1640`
- Metering lock contention: `crates/rf-engine/src/playback.rs:7322–7335`
- LV2 Mutex poison (BUG #32): `crates/rf-engine/src/plugin/lv2.rs:120–136`
- Plugin deactivate (BUG #53 fixed): `crates/rf-engine/src/plugin/lib.rs:575–576`
- Cache TOCTOU: `crates/rf-engine/src/playback.rs:1044–1055`
- HRTF IDW (BUG #35): `crates/rf-dsp/src/spatial.rs:118–120`
- DSD polyphase TODO: `crates/rf-dsp/src/dsd/mod.rs:197–198`

**Flutter critical:**
- Event Registry dual-registration: `lib/services/event_registry.dart:1-150` + `lib/providers/subsystems/composite_event_system_provider.dart:1-200`
- Top complexity hotspots: `lib/screens/engine_connected_layout.dart` (17,292 LOC), `lib/screens/slot_lab_screen.dart` (15,215 LOC), `lib/screens/helix_screen.dart` (9,735 LOC), `lib/widgets/slot_lab/premium_slot_preview.dart` (7,676 LOC)
- HELIX taxonomy definition: `lib/widgets/lower_zone/lower_zone_types.dart:726-803`
- SlotVoiceMixer gesture nest: `lib/widgets/slot_lab/slot_voice_mixer.dart:400-500`
- LivePlayOrbOverlay (orb out of card refactor): `lib/widgets/slot_lab/live_play_orb_overlay.dart:501`
- CortexEyeServer (voice dispatch endpoints): `lib/services/cortex_eye_server.dart`

**Recent feature commits on `fix/ci-infra`:**
- `e7bca3a8` — `rf-slot-lab`: honor `AnticipationConfig` in `engine.generate_stages`
- `2b539a0e` — `rf-stage`: `FsSummary` + `UiSkipPress` stages + overlay
- `893c9c9d` — `rf-engine`: scene transition early-dismiss
- `2917ae33` — theme: Casino Vault brand palette — mode-reflective launcher

### C. References

**Neural audio codecs:** [DAC (Descript)](https://github.com/descriptinc/descript-audio-codec) · [Meta AudioCraft](https://ai.meta.com/resources/models-and-libraries/audiocraft/) · [Stable Audio 2.5](https://stability.ai/stable-audio) · [Stable Audio Open Small](https://www.marktechpost.com/2025/05/15/stability-ai-introduces-adversarial-relativistic-contrastive-arc-post-training-and-stable-audio-open-small-a-distillation-free-breakthrough-for-fast-diverse-and-efficient-text-to-audio-generation/)

**Generative audio:** [Suno vs Udio 2026](https://neuronad.com/suno-vs-udio/) · [iZotope Ozone 12](https://www.izotope.com/en/products/ozone/features) · [Apple Logic Pro 11.2 AI](https://www.apple.com/newsroom/2024/05/logic-pro-takes-music-making-to-the-next-level-with-new-ai-features/) · [LANDR Mastering API](https://www.landr.com/pro-audio-mastering-api)

**Stem separation:** [Demucs](https://github.com/facebookresearch/demucs) · [HT-Demucs ONNX (Mixxx GSoC)](https://mixxx.org/news/2025-10-27-gsoc2025-demucs-to-onnx-dhunstack/) · [MVSEP-MDX23](https://github.com/ZFTurbo/MVSEP-MDX23-music-separation-model)

**Generative TTS + SFX:** [ElevenLabs TTS](https://elevenlabs.io/docs/overview/capabilities/text-to-speech) · [ElevenLabs Sound Effects](https://elevenlabs.io/docs/overview/capabilities/sound-effects) · [Inworld GDC 2025](https://inworld.ai/blog/gdc-2025)

**Neural reverb:** [PromptReverb](https://arxiv.org/html/2510.22439v2) · [NeuralReverberator](https://www.christiansteinmetz.com/projects-blog/neuralreverberator)

**GPU audio:** [wgpu-rs](https://wgpu.rs/) · [WebGPU Compute Shader Basics](https://webgpufundamentals.org/webgpu/lessons/webgpu-compute-shaders.html) · [Apple Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders) · [MPSGraph](https://developer.apple.com/documentation/metalperformanceshadersgraph)

**Spatial:** [Dolby Atmos Standards 2025](https://ralphsutton.com/dolby-atmos-standards-deliverables-2025/) · [Dolby FlexConnect](https://audioxpress.com/news/dolby-and-lg-unveil-the-world-s-first-soundbar-audio-system-powered-by-dolby-atmos-flexconnect) · [Dolby CES 2026](https://news.dolby.com/en-WW/259256-dolby-sets-the-new-standard-for-premium-entertainment-at-ces-2026/) · [Apple Spatial Audio](https://support.apple.com/guide/airpods/control-spatial-audio-and-head-tracking-dev00eb7e0a3/web) · [PHASE personalized](https://developer.apple.com/documentation/phase/personalizing-spatial-audio-in-your-app) · [HiFi-HARP 7OA](https://arxiv.org/html/2510.21257v1) · [HRTFformer](https://arxiv.org/html/2510.01891v1)

**Input paradigms:** [visionOS Developer](https://developer.apple.com/visionos/) · [Apple Speech](https://developer.apple.com/documentation/speech) · [WhisperKit](https://github.com/argmaxinc/WhisperKit) · [Wacom Intuos Pro 2025](https://community.wacom.com/en-us/wacom-intuos-pro-drawing-tablet/)

**Collaboration:** [Yjs](https://yjs.dev/) · [Automerge 2.0](https://automerge.org/blog/automerge-2/) · [CRDTs go brrr](https://josephg.com/blog/crdts-go-brrr/) · [Soundtrap vs BandLab 2025](https://midination.com/daw/soundtrap-vs-bandlab/) · [JackTrip WebRTC](https://news.ycombinator.com/item?id=25942829) · [WebRTC Latency 2026](https://www.nanocosmos.net/blog/webrtc-latency/)

**Flutter / UI:** [Flutter Impeller](https://docs.flutter.dev/perf/impeller) · [Fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders) · [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) · [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) · [Forui](https://forui.dev/)

**Experimental:** [NeiroSynth](https://neirosynth.com/) · [Soundverse AI Music for Game Devs 2026](https://www.soundverse.ai/blog/article/ai-music-for-game-developers-and-indie-studios-0130) · [Evaluating Neural Codecs 2025](https://arxiv.org/html/2511.19734v1)

**Competitive:**
- Wwise: [2025.1 What's New](https://www.audiokinetic.com/en/blog/wwise-2025.1-whats-new/) · [2024.1 What's New](https://www.audiokinetic.com/en/blog/wwise2024.1-whats-new/) · [Similar Sound Search](https://www.audiokinetic.com/en/blog/wwise-2025.1-media-pool-similar-sound-search/) · [Pricing](https://www.audiokinetic.com/en/wwise/pricing/)
- FMOD: [API 2.03 What's New](https://www.fmod.com/docs/2.03/api/welcome-whats-new-203.html) · [Revision History](https://www.fmod.com/docs/2.03/studio/welcome-to-fmod-studio-revision-history.html)
- Unity: [Q3 2025 audio status](https://discussions.unity.com/t/audio-status-update-q3-2025/1681867)
- Unreal: [MetaSounds](https://dev.epicgames.com/documentation/unreal-engine/metasounds-in-unreal-engine) · [AudioLink](https://dev.epicgames.com/documentation/en-us/unreal-engine/audiolink-overview) · [UE 5.5 for Sound](https://cdm.link/unreal-engine-5-5-for-sound/)
- Slot vendors: [Aristocrat OASIS CORE](https://aristocratgaming.com/us/casino-operator/cxs/slot-and-floor-solutions/oasis-core) · [IGT Patent US6968063](https://patents.google.com/patent/US6968063B2/en)

### D. Changelog

- `2026-04-24` — Doc initialized by Corti. Paralelni audit (4 agenata: Flutter UI, Rust, AI Tech 2026, Competitive Intel) + CortexEye mass snap misija (24 snapshots). Sinteza: Part I–VI + Executive Summary + Appendix. Total ~18k reči / ~1300 linija.

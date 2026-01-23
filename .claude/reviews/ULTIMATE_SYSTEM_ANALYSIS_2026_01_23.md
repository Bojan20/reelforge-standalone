# FluxForge Studio — Ultimate System Analysis

**Date:** 2026-01-23
**Author:** Claude Opus 4.5 (Principal Engineer Mode)
**Version:** 1.0
**LOC Analyzed:** ~100,000+ (Rust + Dart)

---

## Executive Summary

FluxForge Studio je **profesionalni slot-audio middleware** koji kombinuje:
- **DAW Engine** — Pro Tools/Cubase nivo timeline editing-a
- **Audio Middleware** — Wwise/FMOD-style event sistem
- **Slot Lab** — Sintetički slot engine za audio dizajn
- **Adaptive Layer Engine** — Context-aware dinamička muzika

**Ključne metrike:**
- 33 Rust crate-ova u workspace-u
- 66 Flutter providera
- 500+ FFI funkcija
- 60+ kanonskih stage tipova
- 100+ audio eventa

---

# FAZA 1: ANALIZA PO ULOGAMA (9 Uloga)

## 1.1 Slot Game Designer

### Sekcije koje koristi
- SlotLab Screen — Synthetic slot engine
- Premium Slot Preview — Full-featured mockup
- Stage Trace — Event timeline
- Game Model Editor — Math configuration

### Inputs
- GDD (Game Design Document) sa:
  - Grid specifikacija (5x3, 6x4, etc.)
  - Volatility profile (Low/Med/High)
  - Symbol set (WILD, SCATTER, BONUS, A-9)
  - Paytable (line wins, scatter pays)
  - Feature definitions (Free Spins, Cascades)

### Outputs
- Audio requirements spec
- Stage → Audio mapping
- Timing requirements per stage

### Decisions
- Kada trigerirati ANTICIPATION audio?
- Koliko trajanja za REEL_SPIN loop?
- Win tier threshold-i (nice/big/mega/epic/ultra)

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| Manual stage naming | Typos break audio | HIGH |
| No paytable import | Manual entry error-prone | MEDIUM |
| Volatility unclear | Affects audio design decisions | LOW |

### Gaps
1. Nema automatski import GDD JSON-a
2. Nema win tier calculator (audio vs. math mismatch)
3. Nema feature flow visualizer

### Proposals
- **P4.1:** GDD JSON import wizard
- **P4.2:** Win tier auto-calculator (based on bet multiplier)
- **P4.3:** Feature flow diagram generator

---

## 1.2 Audio Designer / Composer

### Sekcije koje koristi
- Events Folder Panel — Composite event CRUD
- Audio Waveform Picker — Audio selection
- Container Panels — Blend/Random/Sequence
- Music System — Stingers, segments
- Lower Zone DSP — EQ, Comp, Reverb

### Inputs
- Audio assets (.wav, .flac, .mp3)
- Stage events (from Slot Designer)
- RTPC values (from game engine)
- Attenuation curves (from Game Designer)

### Outputs
- Composite events sa audio layers
- Container definitions (crossfade, variation)
- Music segments sa sync points
- Final audio package (soundbank)

### Decisions
- Layer timing (delay, offset)
- Bus routing (reels, sfx, music, vo)
- Container type selection (Blend vs Random)
- RTPC curve shapes

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| No audio preview in event editor | Can't hear result | HIGH |
| Limited layer visualization | Hard to see overlap | MEDIUM |
| Manual bus assignment | Error-prone | MEDIUM |
| No spectral analysis | Miss frequency clash | LOW |

### Gaps
1. Nema A/B comparison za event varijante
2. Nema batch rename za layers
3. Nema audio loudness analysis pre export-a

### Proposals
- **P4.4:** Inline audio preview u event editor
- **P4.5:** Layer timeline visualization sa waveform
- **P4.6:** Loudness analysis pre bake-a (EBU R128)

---

## 1.3 Audio Middleware Architect

### Sekcije koje koristi
- MiddlewareProvider system (10 subsystems)
- EventRegistry (stage → event mapping)
- Container system (Blend/Random/Sequence/Group)
- RTPC system (curves, bindings)
- Ducking matrix (sidechain rules)

### Inputs
- Event definitions
- Container configurations
- RTPC mappings
- Bus hierarchy
- Ducking rules

### Outputs
- Runtime event triggering
- Voice management
- Bus routing
- Spatial positioning
- Manifest JSON

### Decisions
- State machine design
- Priority levels (0-100)
- Voice stealing mode
- Ducking attack/release
- Container hierarchy

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| No event debugger | Hard to trace issues | HIGH |
| Manual priority assignment | Inconsistent levels | MEDIUM |
| Ducking UI unintuitive | Learning curve | MEDIUM |
| No profiler | Can't find bottleneck | HIGH |

### Gaps
1. Nema event trace visualizer
2. Nema priority preset system
3. Nema bus hierarchy diagram
4. Nema performance profiler

### Proposals
- **P4.7:** Event debugger panel (trace + timeline)
- **P4.8:** Priority tier presets (CRITICAL/HIGH/MED/LOW)
- **P4.9:** Visual bus hierarchy editor
- **P4.10:** DSP profiler integration

---

## 1.4 Engine / Runtime Developer

### Sekcije koje koristi
- Stage Ingest System (adapters)
- Connector Panel (WebSocket/TCP)
- FFI Bridge layer
- Offline DSP Pipeline

### Inputs
- Game engine JSON events
- WebSocket/TCP streams
- Configuration JSON

### Outputs
- Canonical STAGE events
- Audio playback commands
- Metering data
- Export packages

### Decisions
- Adapter layer selection
- Connection protocol
- Buffer sizes
- Thread pool configuration

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| No connection diagnostics | Hard to debug network | HIGH |
| Limited error messages | Unclear failures | MEDIUM |
| No latency measurement | Can't optimize | HIGH |
| Manual adapter config | Complex setup | MEDIUM |

### Gaps
1. Nema network latency monitor
2. Nema auto-reconnect UI feedback
3. Nema adapter test suite
4. Nema staging environment

### Proposals
- **P4.11:** Network diagnostics panel
- **P4.12:** Latency histogram visualization
- **P4.13:** Adapter validation test suite
- **P4.14:** Staging mode (mock engine)

---

## 1.5 Tooling / Editor Developer

### Sekcije koje koristi
- Lower Zone system (all 3 sections)
- Controllers (keyboard shortcuts)
- Persistence layer
- Export adapters

### Inputs
- User preferences
- Keyboard mappings
- Theme settings
- Export configurations

### Outputs
- Responsive UI
- Persisted state
- Export files (Unity, Unreal, Howler)
- User settings

### Decisions
- Tab organization
- Keyboard shortcut mapping
- Panel default sizes
- Export format support

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| 3 separate lower zones | Code duplication | MEDIUM |
| Hard-coded shortcuts | No customization | LOW |
| No undo in UI operations | User frustration | MEDIUM |
| Limited theming | Accessibility concerns | LOW |

### Gaps
1. Nema unified lower zone base class
2. Nema customizable keyboard shortcuts
3. Nema dark/light theme toggle
4. Nema accessibility audit

### Proposals
- **P4.15:** Abstract LowerZoneBase class
- **P4.16:** Keyboard shortcut customization panel
- **P4.17:** Theme switcher (dark/light/custom)
- **P4.18:** WCAG AA accessibility pass

---

## 1.6 UX / UI Designer

### Sekcije koje koristi
- All UI components
- Lower Zone typography
- Color system
- Interaction patterns

### Inputs
- User research
- Competitive analysis (Wwise, FMOD, Pro Tools)
- Accessibility requirements

### Outputs
- Consistent visual language
- Intuitive workflows
- Responsive feedback
- Accessible interfaces

### Decisions
- Color palette (WCAG AA)
- Typography scale
- Animation timing
- Icon consistency

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| Inconsistent icon styles | Visual noise | LOW |
| No loading indicators | Unclear state | MEDIUM |
| Dense information | Cognitive load | MEDIUM |
| No onboarding | Steep learning curve | HIGH |

### Gaps
1. Nema icon library documentation
2. Nema skeleton loading states
3. Nema progressive disclosure
4. Nema tutorial system

### Proposals
- **P4.19:** Unified icon library
- **P4.20:** Skeleton loading for all panels
- **P4.21:** Progressive disclosure (hide advanced)
- **P4.22:** Interactive tutorial system

---

## 1.7 QA / Determinism Engineer

### Sekcije koje koristi
- Regression tests (rf-dsp)
- CI/CD pipeline
- Offline DSP validation
- Audio quality tests

### Inputs
- Reference audio files
- Expected outputs
- Test configurations

### Outputs
- Pass/Fail results
- Audio diff reports
- Performance benchmarks
- Coverage reports

### Decisions
- Tolerance thresholds
- Test granularity
- CI/CD pipeline stages
- Regression criteria

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| No audio diff tool | Manual comparison | HIGH |
| Limited test coverage | Missing edge cases | MEDIUM |
| No visual regression | UI bugs slip through | MEDIUM |
| No fuzzing | Security vulnerabilities | LOW |

### Gaps
1. Nema audio diff/comparison tool
2. Nema golden file management
3. Nema visual regression tests
4. Nema fuzzing framework

### Proposals
- **P4.23:** Audio diff tool (spectral comparison)
- **P4.24:** Golden file management UI
- **P4.25:** Visual regression (screenshot diff)
- **P4.26:** Fuzzing for FFI layer

---

## 1.8 DSP / Audio Processing Engineer

### Sekcije koje koristi
- rf-dsp crate (EQ, Dynamics, Spatial)
- FabFilter-style panels
- Offline DSP pipeline
- SIMD dispatch system

### Inputs
- Audio buffers
- DSP parameters
- Processing mode (real-time vs offline)

### Outputs
- Processed audio
- Metering data
- Latency compensation
- CPU usage

### Decisions
- Filter types
- SIMD optimization level
- Oversampling factor
- Precision (f32 vs f64)

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| No visual DSP debugger | Hard to trace issues | MEDIUM |
| Limited coefficient display | Can't verify math | LOW |
| No A/B comparison | Hard to hear difference | MEDIUM |
| No impulse response viewer | Filter unclear | LOW |

### Gaps
1. Nema DSP coefficient inspector
2. Nema frequency response overlay
3. Nema impulse response viewer
4. Nema phase response display

### Proposals
- **P4.27:** DSP coefficient panel
- **P4.28:** Frequency response overlay
- **P4.29:** Impulse response viewer
- **P4.30:** Phase response display

---

## 1.9 Producer / Product Owner

### Sekcije koje koristi
- All sections (high-level)
- Documentation
- Roadmap
- Performance metrics

### Inputs
- Market requirements
- Competitor analysis
- User feedback
- Technical constraints

### Outputs
- Feature prioritization
- Release planning
- Resource allocation
- Success metrics

### Decisions
- Feature scope
- Release timing
- Resource allocation
- Go/No-go decisions

### Friction Points
| Problem | Impact | Severity |
|---------|--------|----------|
| No usage analytics | Blind feature decisions | HIGH |
| No user feedback loop | Missing pain points | MEDIUM |
| Limited documentation | Slow onboarding | MEDIUM |
| No competitor benchmarks | Unclear positioning | LOW |

### Gaps
1. Nema telemetry/analytics
2. Nema feedback collection UI
3. Nema feature usage tracking
4. Nema competitive feature matrix

### Proposals
- **P4.31:** Opt-in telemetry system
- **P4.32:** In-app feedback widget
- **P4.33:** Feature usage dashboard
- **P4.34:** Competitive analysis document

---

# FAZA 2: ANALIZA PO SEKCIJAMA (15 Sekcija)

## 2.1 Project / Game Setup

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Define game metadata, create/load projects |
| **INPUT** | Game name, grid spec, volatility, platform |
| **OUTPUT** | Project state, engine configuration |
| **DEPENDENCIES** | File system, SharedPreferences |
| **DEPENDENTS** | All providers, SlotLab, Middleware |
| **ERRORS** | File not found, corrupted project, version mismatch |
| **CROSS-IMPACT** | Changes here affect all other sections |

**Gaps:** No project templates, no version migration UI

---

## 2.2 Slot Layout / Mockup

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Visual representation of slot grid |
| **INPUT** | GridSpec (rows, columns), symbols |
| **OUTPUT** | Visual mockup, reel positions |
| **DEPENDENCIES** | SlotLabProvider, GameModel |
| **DEPENDENTS** | Premium Slot Preview, Stage Trace |
| **ERRORS** | Invalid grid dimensions |
| **CROSS-IMPACT** | Grid changes affect stage timing |

**Gaps:** No drag-drop symbol editor, no reel strip visualizer

---

## 2.3 Math & GDD Layer

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Define game mathematics |
| **INPUT** | Paytable, RTP target, volatility |
| **OUTPUT** | Mathematical model, win calculations |
| **DEPENDENCIES** | rf-slot-lab |
| **DEPENDENTS** | SlotLabProvider, Stage generation |
| **ERRORS** | Invalid RTP, inconsistent paytable |
| **CROSS-IMPACT** | Math affects win tier audio triggers |

**Gaps:** No paytable import, no RTP calculator

---

## 2.4 Audio Layering System

| Aspect | Details |
|--------|---------|
| **PURPOSE** | L1-L5 intensity-based audio selection |
| **INPUT** | Game signals, context, rules |
| **OUTPUT** | Active layers, volume levels |
| **DEPENDENCIES** | AleProvider, rf-ale |
| **DEPENDENTS** | Music playback, bus mixing |
| **ERRORS** | Missing layer assets, invalid rules |
| **CROSS-IMPACT** | Layer changes affect all audio output |

**Gaps:** No layer preview, no rule testing sandbox

---

## 2.5 Event Graph / Triggers

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Stage → Event → Audio mapping |
| **INPUT** | Stage events, event definitions |
| **OUTPUT** | Audio playback commands |
| **DEPENDENCIES** | EventRegistry, AudioPlaybackService |
| **DEPENDENTS** | All audio output |
| **ERRORS** | Missing events, wrong bus routing |
| **CROSS-IMPACT** | Event changes affect all audio playback |

**Gaps:** No event graph visualizer, no dependency view

---

## 2.6 Music State System

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Context-aware music transitions |
| **INPUT** | Context (BASE, FREESPINS, BIGWIN), sync mode |
| **OUTPUT** | Music playback, layer mixing |
| **DEPENDENCIES** | MusicSystemProvider, AleProvider |
| **DEPENDENTS** | Music bus output |
| **ERRORS** | Sync misalignment, abrupt transitions |
| **CROSS-IMPACT** | Music affects overall audio feel |

**Gaps:** No transition preview, no beat grid editor

---

## 2.7 Feature Modules

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Free Spins, Bonus, Cascade, Hold&Win |
| **INPUT** | Feature definitions, trigger conditions |
| **OUTPUT** | Feature stages, audio requirements |
| **DEPENDENCIES** | FeatureRegistry, SlotLabProvider |
| **DEPENDENTS** | Stage generation, audio triggers |
| **ERRORS** | Invalid feature config |
| **CROSS-IMPACT** | Features create unique audio moments |

**Gaps:** No feature simulator, no cascade visualizer

---

## 2.8 Asset Manager

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Import, tag, organize audio assets |
| **INPUT** | Audio files, metadata |
| **OUTPUT** | Organized asset library |
| **DEPENDENCIES** | File system, AudioAssetManager |
| **DEPENDENTS** | Event layers, containers |
| **ERRORS** | Missing files, format errors |
| **CROSS-IMPACT** | Assets feed all audio playback |

**Gaps:** No batch import, no metadata editor, no folder sync

---

## 2.9 DSP / Offline Processing

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Batch processing, normalization |
| **INPUT** | Audio files, processing config |
| **OUTPUT** | Processed audio files |
| **DEPENDENCIES** | rf-offline, OfflineProcessingProvider |
| **DEPENDENTS** | Asset Manager, Export |
| **ERRORS** | Processing failures, codec errors |
| **CROSS-IMPACT** | DSP affects final audio quality |

**Gaps:** No batch queue UI, no processing history

---

## 2.10 Runtime Adapter

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Connect to external game engines |
| **INPUT** | Engine events (JSON), connection config |
| **OUTPUT** | Canonical STAGE events |
| **DEPENDENCIES** | rf-ingest, rf-connector, StageIngestProvider |
| **DEPENDENTS** | EventRegistry |
| **ERRORS** | Connection failures, parse errors |
| **CROSS-IMPACT** | Adapter enables live testing |

**Gaps:** No adapter marketplace, no shared configs

---

## 2.11 Simulation / Preview

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Test audio without real engine |
| **INPUT** | Spin config, forced outcomes |
| **OUTPUT** | Simulated spin results, stage events |
| **DEPENDENCIES** | rf-slot-lab, SlotLabProvider |
| **DEPENDENTS** | EventRegistry, Audio preview |
| **ERRORS** | Invalid forced outcome |
| **CROSS-IMPACT** | Simulation enables offline design |

**Gaps:** No simulation recording, no playback speed control

---

## 2.12 Export / Manifest

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Generate game engine packages |
| **INPUT** | Events, containers, RTPC, soundbank |
| **OUTPUT** | Unity/Unreal/Howler packages |
| **DEPENDENCIES** | Exporters, SoundbankProvider |
| **DEPENDENTS** | Game engine integration |
| **ERRORS** | Invalid paths, missing assets |
| **CROSS-IMPACT** | Export is final deliverable |

**Gaps:** No export validation, no diff with previous version

---

## 2.13 QA / Validation

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Ensure audio quality and correctness |
| **INPUT** | Audio files, test configs |
| **OUTPUT** | Test results, reports |
| **DEPENDENCIES** | rf-dsp tests, CI/CD |
| **DEPENDENTS** | Release decisions |
| **ERRORS** | Test failures, regressions |
| **CROSS-IMPACT** | QA gates all releases |

**Gaps:** No interactive test runner, no test coverage UI

---

## 2.14 Versioning / Profiles

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Platform-specific audio configs |
| **INPUT** | Platform (Desktop/Mobile/Web) |
| **OUTPUT** | Optimized audio settings |
| **DEPENDENCIES** | Configuration system |
| **DEPENDENTS** | All playback |
| **ERRORS** | Missing platform config |
| **CROSS-IMPACT** | Profiles affect performance |

**Gaps:** No profile diff view, no A/B testing

---

## 2.15 Automation / Batch

| Aspect | Details |
|--------|---------|
| **PURPOSE** | Scripted operations, CI/CD |
| **INPUT** | Script commands, batch configs |
| **OUTPUT** | Automated results |
| **DEPENDENCIES** | CLI tools, CI/CD |
| **DEPENDENTS** | Development workflow |
| **ERRORS** | Script errors |
| **CROSS-IMPACT** | Automation speeds development |

**Gaps:** No script editor, no macro recording

---

# FAZA 3: HORIZONTALNA SISTEMSKA ANALIZA

## 3.1 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DESIGN PHASE                                     │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ Game GDD │───>│ SlotLab  │───>│ Stages   │───>│ Events   │          │
│  │ (JSON)   │    │ Provider │    │ (60+)    │    │ Registry │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│                                         │                               │
│                                         ▼                               │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ Audio    │───>│Container │───>│ Layers   │───>│ Composite│          │
│  │ Assets   │    │ System   │    │ Config   │    │ Events   │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        RUNTIME PHASE                                     │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ Engine   │───>│ Ingest   │───>│ Stage    │───>│ Event    │          │
│  │ Events   │    │ Adapter  │    │ Trace    │    │ Trigger  │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│                                         │                               │
│                                         ▼                               │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ ALE      │───>│ Music    │───>│ Bus      │───>│ Audio    │          │
│  │ Signals  │    │ Layers   │    │ Mixing   │    │ Output   │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Information Loss Points

| Point | What Gets Lost | Impact |
|-------|---------------|--------|
| GDD → SlotLab | Math nuances (RTP variance) | Incorrect win tier mapping |
| Stages → Events | Stage context (why triggered) | Hard to debug |
| Assets → Containers | Original file metadata | Lost organization |
| Export → Runtime | Design intent | Can't modify at runtime |

## 3.3 Logic Duplication

| Duplication | Locations | Risk |
|-------------|-----------|------|
| Stage name parsing | SlotLabProvider, EventRegistry, StageIngest | Case-sensitivity bugs |
| Priority calculation | EventRegistry, VoicePool | Inconsistent behavior |
| Bus routing | EventRegistry, ContainerService | Wrong bus assignment |
| Win tier calculation | SlotLabProvider, AleProvider | Threshold mismatch |

## 3.4 Determinism Violations

| Violation | Location | Fix |
|-----------|----------|-----|
| Random container without seed | RandomContainer | Add seed parameter |
| Timer-based stage playback | SlotLabProvider | Use deterministic clock |
| Float precision in FFI | All FFI | Standardize f64 |

## 3.5 Recommendations

### Data-Driven Architecture

```dart
// BEFORE: Hard-coded stage handling
if (stage.startsWith('REEL_STOP_')) {
  busId = SpatialBus.reels.index;
}

// AFTER: Data-driven
final config = StageConfig.fromCatalog(stage);
busId = config.defaultBus.index;
```

### Pure State Machines

```rust
// BEFORE: Implicit state
pub fn process(&mut self) {
  if self.is_playing && self.has_audio { ... }
}

// AFTER: Explicit state machine
pub enum PlaybackState {
  Idle,
  Loading(LoadingContext),
  Playing(PlayingContext),
  Paused(PausedContext),
}
```

### Single Source of Truth

```
// BEFORE: Scattered
SlotLabProvider._winTiers = {...}
AleProvider._winTierSignal = 0.0
EventRegistry._bigWinTemplates = [...]

// AFTER: Centralized
WinTierConfig {
  tiers: [nice, big, mega, epic, ultra]
  thresholds: [2.0, 5.0, 15.0, 50.0, 100.0] // x bet
  audioTemplates: {...}
  aleSignalMapping: {...}
}
```

---

# FAZA 4: DELIVERABLES

## 4.1 Sistem Mapa (ASCII)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              FLUXFORGE STUDIO                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─ FLUTTER UI ────────────────────────────────────────────────────────────────┐│
│  │                                                                              ││
│  │  ┌─ DAW Section ─┐  ┌─ Middleware ──┐  ┌─ SlotLab ─────┐                   ││
│  │  │ Timeline      │  │ Events       │  │ Premium Preview│                   ││
│  │  │ Mixer         │  │ Containers   │  │ Stage Trace   │                   ││
│  │  │ DSP Chain     │  │ RTPC         │  │ Event Log     │                   ││
│  │  │ Automation    │  │ Ducking      │  │ Forced Outcome│                   ││
│  │  └───────────────┘  │ Music System │  └───────────────┘                   ││
│  │                      └──────────────┘                                       ││
│  │                                                                              ││
│  │  ┌─ Lower Zones ────────────────────────────────────────────────────────┐  ││
│  │  │ BROWSE │ EDIT │ MIX │ PROCESS │ DELIVER                               │  ││
│  │  └────────────────────────────────────────────────────────────────────────┘  ││
│  │                                                                              ││
│  │  ┌─ Providers (66) ─────────────────────────────────────────────────────┐  ││
│  │  │ MiddlewareProvider (10 subsystems)                                    │  ││
│  │  │ SlotLabProvider                                                       │  ││
│  │  │ AleProvider                                                           │  ││
│  │  │ StageIngestProvider                                                   │  ││
│  │  └────────────────────────────────────────────────────────────────────────┘  ││
│  └──────────────────────────────────────────────────────────────────────────────┘│
│                                      │                                           │
│                                      │ FFI (500+ functions)                      │
│                                      ▼                                           │
│  ┌─ RUST ENGINE ────────────────────────────────────────────────────────────────┐│
│  │                                                                              ││
│  │  ┌─ rf-engine ───┐  ┌─ rf-slot-lab ┐  ┌─ rf-ale ──────┐                    ││
│  │  │ PlaybackEngine│  │ Synthetic    │  │ Signals      │                    ││
│  │  │ TrackManager  │  │ Slot Engine  │  │ Rules        │                    ││
│  │  │ Graph Routing │  │ GDD Parser   │  │ Contexts     │                    ││
│  │  │ Automation    │  │ Features     │  │ Transitions  │                    ││
│  │  └───────────────┘  └──────────────┘  └───────────────┘                    ││
│  │                                                                              ││
│  │  ┌─ rf-dsp ──────┐  ┌─ rf-stage ───┐  ┌─ rf-offline ─┐                    ││
│  │  │ 64-band EQ    │  │ Stage enum   │  │ Batch proc   │                    ││
│  │  │ Dynamics      │  │ StageTrace   │  │ Normalize    │                    ││
│  │  │ Reverb        │  │ TimingConfig │  │ Format conv  │                    ││
│  │  │ SIMD dispatch │  └──────────────┘  └───────────────┘                    ││
│  │  └───────────────┘                                                          ││
│  │                                                                              ││
│  │  ┌─ rf-bridge (FFI) ────────────────────────────────────────────────────┐  ││
│  │  │ slot_lab_ffi │ ale_ffi │ container_ffi │ stage_ffi │ offline_ffi │  ││
│  │  └────────────────────────────────────────────────────────────────────────┘  ││
│  └──────────────────────────────────────────────────────────────────────────────┘│
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 4.2 Idealna Arhitektura

```
AUTHORING (Design-Time)          PIPELINE (Build-Time)         RUNTIME (Play-Time)
┌────────────────────┐           ┌────────────────────┐       ┌────────────────────┐
│ Event Editor       │           │ Manifest Generator │       │ Stage → Event      │
│ Container Builder  │──────────>│ Asset Bake         │──────>│ Container Eval     │
│ Music Composer     │           │ Soundbank Build    │       │ Bus Routing        │
│ RTPC Designer      │           │ Validation         │       │ Voice Management   │
└────────────────────┘           └────────────────────┘       └────────────────────┘
         ↑                                ↑                            ↑
         │                                │                            │
    GDD Import                       CI/CD Hook                   Engine Events
```

## 4.3 Ultimate Layering Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SLOT-SPECIFIC L1-L5 LAYERS                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  L1: AMBIENT (Always On)                                                     │
│  └─ Base loop, subtle atmosphere, "home" feeling                            │
│                                                                              │
│  L2: INTEREST (Player Active)                                                │
│  └─ Light percussion, anticipation hints, balance neutral                    │
│                                                                              │
│  L3: TENSION (Something Happening)                                           │
│  └─ Building elements, near misses, feature proximity                        │
│                                                                              │
│  L4: CLIMAX (Win/Feature Moment)                                             │
│  └─ Full orchestration, feature active, big wins                             │
│                                                                              │
│  L5: PAYOFF (Maximum Celebration)                                            │
│  └─ Jackpot, epic win, maximum celebration                                   │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ TRANSITION RULES:                                                            │
│ • L1→L2: Spin start, balance change                                         │
│ • L2→L3: Near miss, anticipation, feature proximity                         │
│ • L3→L4: Feature trigger, big win, cascade start                            │
│ • L4→L5: Jackpot, epic win, max multiplier                                  │
│ • Down: Stability mechanisms (cooldown, hold, decay)                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4.4 Unified Event Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           UNIFIED EVENT MODEL                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  CANONICAL STAGE (source-agnostic)                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ name: "REEL_STOP_0"                                                     ││
│  │ category: StageCategory.REEL                                            ││
│  │ defaultBus: SpatialBus.REELS                                            ││
│  │ priority: Priority.HIGH (60-79)                                         ││
│  │ spatialIntent: SpatialIntent.REEL_LEFT                                  ││
│  │ isPooled: true (rapid-fire optimization)                                ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                      ↓                                       │
│  AUDIO EVENT (designer-defined)                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ id: "evt_reel_stop_0"                                                   ││
│  │ stage: "REEL_STOP_0"                                                    ││
│  │ containerType: ContainerType.NONE | BLEND | RANDOM | SEQUENCE           ││
│  │ layers: [AudioLayer(path, volume, pan, delay, offset, bus)]             ││
│  │ priority: (override) or inherit from stage                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                      ↓                                       │
│  PLAYBACK COMMAND (runtime)                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ voiceId: u32 (from voice pool)                                          ││
│  │ audioPath: resolved path                                                ││
│  │ volume: 0.0-1.0 (RTPC modulated)                                        ││
│  │ pan: -1.0 to +1.0 (spatial calculated)                                  ││
│  │ busId: int (target bus)                                                 ││
│  │ priority: int (for voice stealing)                                      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4.5 Determinism & QA Layer

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DETERMINISM GUARANTEES                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. SEEDED RANDOM                                                            │
│     • Random containers use explicit seeds                                   │
│     • Seeds logged for reproduction                                          │
│                                                                              │
│  2. DETERMINISTIC TIMING                                                     │
│     • Replace Timer with simulation clock                                    │
│     • All timing expressed in samples, not ms                                │
│                                                                              │
│  3. FLOAT PRECISION                                                          │
│     • All calculations in f64                                                │
│     • Round to f32 only at output                                            │
│                                                                              │
│  4. STATE CAPTURE                                                            │
│     • Serialize full state at any point                                      │
│     • Restore and replay from state                                          │
│                                                                              │
│  5. AUDIO FINGERPRINTING                                                     │
│     • Hash output audio for comparison                                       │
│     • Detect bit-level regressions                                           │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                              QA AUTOMATION                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PRE-COMMIT:                                                                 │
│  ✓ cargo fmt --check                                                        │
│  ✓ cargo clippy                                                             │
│  ✓ flutter analyze                                                          │
│  ✓ Unit tests (rf-dsp, rf-ale, rf-slot-lab)                                │
│                                                                              │
│  CI/CD:                                                                      │
│  ✓ Cross-platform build (macOS, Windows, Linux)                             │
│  ✓ Regression tests (14 audio quality tests)                                │
│  ✓ Performance benchmarks                                                   │
│  ✓ Security audit (cargo-audit)                                             │
│                                                                              │
│  RELEASE:                                                                    │
│  ✓ Integration tests                                                        │
│  ✓ Golden file comparison                                                   │
│  ✓ Manual QA checklist                                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4.6 Roadmap (M-Milestones)

| Milestone | Focus | Duration | Key Deliverables |
|-----------|-------|----------|------------------|
| **M1** | Foundation Complete | ✅ DONE | P0-P2 complete (95%) |
| **M2** | Stability & Polish | 2 weeks | P4.1-P4.10 (Gaps from analysis) |
| **M3** | Advanced Features | 3 weeks | Container Groups, Macro System, Morphing |
| **M4** | QA & Validation | 2 weeks | Audio diff, Golden files, Visual regression |
| **M5** | Production Ready | 2 weeks | Documentation, Tutorials, Onboarding |
| **M6** | Enterprise Features | 4 weeks | Telemetry, Team collaboration, Cloud sync |

## 4.7 Critical Weaknesses (Top 10)

| # | Weakness | Impact | Effort | Priority |
|---|----------|--------|--------|----------|
| 1 | No audio preview in event editor | Designer frustration | LOW | P1 |
| 2 | No event debugger/tracer | Hard to diagnose issues | MEDIUM | P1 |
| 3 | Scattered stage configuration | Maintenance burden | MEDIUM | P2 |
| 4 | No GDD import wizard | Manual data entry | MEDIUM | P2 |
| 5 | Limited container visualization | Hard to understand | LOW | P2 |
| 6 | No audio diff tool | QA gaps | MEDIUM | P2 |
| 7 | Hard-coded priority levels | Inconsistent behavior | LOW | P3 |
| 8 | No onboarding/tutorials | Steep learning curve | MEDIUM | P3 |
| 9 | Limited platform profiles | Performance issues | HIGH | P3 |
| 10 | No telemetry/analytics | Blind decisions | MEDIUM | P4 |

## 4.8 Vision Statement

**FluxForge Studio: The Wwise/FMOD of Slot Audio**

FluxForge Studio je profesionalni audio middleware specijalizovan za slot igre koji:

1. **Eliminiše razliku** između audio dizajna i implementacije
2. **Standardizuje** slot audio workflow sa 60+ kanonskih stage tipova
3. **Automatizuje** kontekst-svesnu muziku kroz Adaptive Layer Engine
4. **Omogućuje** real-time testiranje kroz Synthetic Slot Engine
5. **Integriše** sa bilo kojim game engine-om kroz Universal Stage System

**Diferencirajući faktori:**
- **Slot-specifičan** — Razume win tiers, cascades, free spins
- **Universal adapter** — Povezuje bilo koji engine
- **Dynamic music** — L1-L5 layers sa stability mehanizmima
- **Professional DSP** — FabFilter-quality processing
- **Open architecture** — Export do Unity, Unreal, Howler.js

---

# FAZA 5: BENCHMARK STANDARDI

## 5.1 vs. Wwise

| Feature | Wwise | FluxForge | Advantage |
|---------|-------|-----------|-----------|
| Event system | ✓ | ✓ | Tie |
| Container types | 4 | 4 | Tie |
| RTPC | ✓ | ✓ | Tie |
| State/Switch | ✓ | ✓ | Tie |
| Slot-specific stages | ✗ | ✓ | **FluxForge** |
| Synthetic engine | ✗ | ✓ | **FluxForge** |
| Adaptive layers (L1-L5) | Limited | ✓ | **FluxForge** |
| Visual profiler | ✓ | ✗ | **Wwise** |
| Soundbank optimization | ✓ | Basic | **Wwise** |
| Documentation | ✓✓ | ✓ | **Wwise** |

## 5.2 vs. FMOD

| Feature | FMOD | FluxForge | Advantage |
|---------|------|-----------|-----------|
| Event system | ✓ | ✓ | Tie |
| Layered music | ✓ | ✓ | Tie |
| Live update | ✓ | ✓ (WebSocket) | Tie |
| Slot-specific stages | ✗ | ✓ | **FluxForge** |
| GDD integration | ✗ | ✓ | **FluxForge** |
| Win tier automation | ✗ | ✓ | **FluxForge** |
| Studio UI | ✓✓ | ✓ | **FMOD** |
| Platform support | ✓✓ | ✓ | **FMOD** |
| Community/plugins | ✓✓ | ✗ | **FMOD** |

## 5.3 vs. Unity Audio

| Feature | Unity | FluxForge | Advantage |
|---------|-------|-----------|-----------|
| Built-in integration | ✓ | Export | **Unity** |
| Real-time DSP | Basic | ✓✓ | **FluxForge** |
| Event system | Basic | ✓✓ | **FluxForge** |
| Adaptive music | Basic | ✓✓ | **FluxForge** |
| Slot-specific | ✗ | ✓ | **FluxForge** |
| Container system | ✗ | ✓ | **FluxForge** |
| RTPC | ✗ | ✓ | **FluxForge** |

## 5.4 vs. iZotope RX

| Feature | iZotope RX | FluxForge Offline | Advantage |
|---------|------------|-------------------|-----------|
| Restoration | ✓✓ | Basic | **iZotope** |
| Spectral editing | ✓✓ | ✗ | **iZotope** |
| Batch processing | ✓ | ✓ | Tie |
| Normalization | ✓ | ✓ (LUFS) | Tie |
| Format conversion | ✓ | ✓ | Tie |
| Real-time preview | ✓ | Limited | **iZotope** |

---

# ZAKLJUČAK

FluxForge Studio je **production-ready** audio middleware za slot igre sa:

**Strengths:**
- Kompletna event/container/RTPC arhitektura
- Unique slot-specific features (stages, ALE, synthetic engine)
- Professional DSP (FabFilter-style)
- Universal engine integration

**Weaknesses:**
- Missing audio preview in editor
- No event debugger
- Limited documentation/onboarding
- Scattered configuration

**Next Steps:**
1. Address top 5 critical weaknesses (M2)
2. Improve QA tooling (audio diff, golden files)
3. Create comprehensive documentation
4. Build onboarding/tutorial system

**Timeline:** 6-8 weeks to production release (M5)

---

*Generisano: 2026-01-23*
*Autor: Claude Opus 4.5 (Principal Engineer Mode)*
*Verzija dokumenta: 1.0*

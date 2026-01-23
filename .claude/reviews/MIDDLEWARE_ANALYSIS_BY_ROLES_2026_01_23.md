# FluxForge Middleware — Kompletna Analiza po Ulogama

**Datum:** 2026-01-23
**Verzija:** 1.0
**Fokus:** Middleware sekcija (MiddlewareProvider + subsystems + widgets)

---

## 📊 SISTEM OVERVIEW

### Arhitektura Middleware Sekcije

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MIDDLEWARE PROVIDER (~1900 LOC)                       │
│                    Coordinator + Batched Notifications                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                         16 SUBSYSTEM PROVIDERS                               │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│ │ StateGroups  │ │ SwitchGroups │ │    RTPC      │ │   Ducking    │        │
│ │   ~185 LOC   │ │   ~210 LOC   │ │   ~350 LOC   │ │   ~190 LOC   │        │
│ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘        │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│ │    Blend     │ │    Random    │ │   Sequence   │ │ MusicSystem  │        │
│ │  Containers  │ │  Containers  │ │  Containers  │ │  Provider    │        │
│ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘        │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│ │ EventSystem  │ │  Composite   │ │ BusHierarchy │ │   AuxSend    │        │
│ │  Provider    │ │   Events     │ │   Provider   │ │   Provider   │        │
│ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘        │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│ │  VoicePool   │ │ Attenuation  │ │   Memory     │ │    Event     │        │
│ │   Provider   │ │    Curves    │ │   Manager    │ │   Profiler   │        │
│ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │   MODELS  │   │  WIDGETS  │   │ SERVICES  │
            │ ~3000 LOC │   │ ~15000 LOC│   │ ~2500 LOC │
            └───────────┘   └───────────┘   └───────────┘
```

### Statistike

| Komponenta | Broj Fajlova | LOC (approx) |
|------------|--------------|--------------|
| MiddlewareProvider | 1 | ~1,900 |
| Subsystem Providers | 16 | ~5,490 |
| Models | 2 | ~4,400 |
| Widgets | 38 | ~15,000 |
| **TOTAL** | 57 | **~26,790** |

---

## 🎮 ULOGA 1: Slot Game Designer

### SEKCIJE
- **Attenuation Curves** — Slot-specifične krive (Win Amount, Near Win, Combo, Feature Progress)
- **Event Editor** — Definisanje audio eventa za slot stage-ove
- **Container System** — Random/Blend/Sequence za varijacije zvukova
- **Music System** — Segment tranzicije za feature muziku

### INPUTS
- Stage nazivi (SPIN_START, REEL_STOP, WIN_PRESENT...)
- Win tier definicije (Small, Big, Mega, Epic)
- Feature definicije (FreeSpins, Bonus, Hold&Win)
- Paytable struktura za audio mappings

### OUTPUTS
- Kompletna stage→audio mapiranja
- Audio profil za svaku slot igru
- Export za runtime (Unity/Unreal/Howler)

### DECISIONS
1. Koji stage koristi koji bus?
2. Kakve varijacije za repeated evente?
3. Win escalation audio strategija?
4. Feature audio character?

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **Stage discovery** | Nema centralni katalog svih mogućih stage-ova | HIGH |
| **Paytable disconnect** | Audio nema direktnu vezu sa math model-om | MEDIUM |
| **Win tier mapping** | Ručno mapiranje win iznosa na audio tier | HIGH |
| **Feature preview** | Ne može da testira feature audio bez simulatora | MEDIUM |

### GAPS
1. ❌ **GDD Import** — Nema automatsko generisanje stage-ova iz Game Design Document-a
2. ❌ **Math Model Integration** — Win tier pragovi se definišu odvojeno od audio-a
3. ❌ **Cascade Depth RTPC** — Nema automatska RTPC veza sa cascade dubinom
4. ❌ **Symbol Audio Palette** — Nema sistem za per-symbol audio definicije

### PROPOSAL
```
P1: GDD Import Wizard (✅ DONE - P3.4)
    - JSON/YAML GDD → auto-generisanje stage-ova

P2: Math Model Connector
    - Win tier pragovi automatski iz paytable
    - Volatility profili za audio (low/med/high)

P3: Cascade Audio Automation
    - Automatski pitch/layer escalation based on depth

P4: Symbol Audio Templates
    - Per-symbol audio templates (WILD, SCATTER, HIGH_PAY_1...)
```

---

## 🎵 ULOGA 2: Audio Designer / Composer

### SEKCIJE
- **Events Folder** — Kreiranje i organizacija audio eventa
- **Layer Timeline** — Multi-layer audio sa offset timing-om
- **Container System** — Blend (RTPC crossfade), Random (weighted), Sequence (timed)
- **Bus Hierarchy** — Routing i effects chain
- **Aux Send** — Reverb/Delay send levels
- **Music System** — Segments sa beat/bar sync

### INPUTS
- Audio fajlovi (.wav, .flac, .mp3)
- RTPC definicije za dinamičke parametre
- Tempo i time signature za muziku
- Bus routing setup

### OUTPUTS
- Kompletan audio mix za igru
- Preset biblioteka za reuse
- Export za sve target platforme

### DECISIONS
1. Layer arrangement i timing
2. Container strategy (random vs blend vs sequence)
3. Bus routing i effect chain
4. RTPC curve shapes

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **No waveform preview** | Hover ne pokazuje waveform u browseru | HIGH |
| **Manual offset entry** | Numerički unos umesto drag-to-position | MEDIUM |
| **Container visualization** | Teško videti kako container funkcioniše | HIGH |
| **A/B comparison** | Nema jednostavan način za compare | MEDIUM |

### GAPS
1. ❌ **Waveform Editor** — Nema inline trim/fade editing
2. ❌ **Multi-layer Preview** — Ne može simultano čuti sve layere sa offset-ima
3. ❌ **Container Auditioning** — Ne može testirati container bez event trigger-a
4. ❌ **Reference Track Import** — Nema A/B sa referentnom muzikom

### PROPOSAL
```
P1: Inline Waveform Actions
    - Right-click → Trim Start/End
    - Drag handles za fade in/out
    - Time-stretch za sync

P2: Multi-Layer Preview Mode
    - Play button sa composite playback
    - Solo/Mute per layer
    - Visual timeline sa playhead

P3: Container Preview Panel (✅ PARTIALLY DONE - P3.5)
    - BlendRtpcSlider ✅
    - RandomWeightPieChart ✅
    - SequenceTimelineVisualization ✅

P4: Reference Track Slot
    - Import reference → volume matched A/B
```

---

## 🧠 ULOGA 3: Audio Middleware Architect

### SEKCIJE
- **State Groups** — Global state machine (Menu/BaseGame/Bonus...)
- **Switch Groups** — Per-object variants (Surface/Material...)
- **RTPC System** — Real-time parameter control sa curve mapping
- **Ducking Matrix** — Source→Target bus ducking rules
- **Voice Pool** — Polyphony management sa stealing modes
- **Memory Manager** — Soundbank budget i LRU unloading

### INPUTS
- State/Switch taxonomy za igru
- RTPC source definicije (game metrics)
- Ducking relationships (VO ducks Music, etc.)
- Voice budget per platform

### OUTPUTS
- Runtime event model
- Optimized playback graph
- Memory-efficient bank loading
- Export manifest za engine integration

### DECISIONS
1. State vs Switch granularnost
2. RTPC curve shapes za natural feel
3. Ducking attack/release timing
4. Voice stealing strategy

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **State Machine Viz** | Nema vizualni graph state tranzicija | HIGH |
| **RTPC Debugging** | Teško videti live RTPC vrednosti | MEDIUM |
| **Ducking Preview** | Ne može čuti ducking bez full mix | HIGH |
| **Memory Profiler** | Nema real-time memory tracking | MEDIUM |

### GAPS
1. ❌ **State Transition Graph** — Vizualni editor za state machine (✅ DONE - P3.3)
2. ❌ **RTPC Monitor** — Real-time RTPC value visualization
3. ❌ **Ducking Simulator** — Test ducking sa mock audio
4. ❌ **Bank Dependency Graph** — Visualize bank load order

### PROPOSAL
```
P1: State Machine Graph (✅ DONE - state_machine_graph.dart)
    - Node-based visual editor
    - Transition arrows sa conditions
    - Live state highlighting

P2: RTPC Debugger Panel
    - Real-time value meters
    - Curve visualization sa current position
    - History graph

P3: Ducking Test Mode
    - Play source → see target duck
    - Adjustable timing preview

P4: Bank Load Visualizer
    - Dependency tree view
    - Load time estimates
    - Memory impact calculator
```

---

## 🛠 ULOGA 4: Engine / Runtime Developer

### SEKCIJE
- **VoicePool Provider** — Voice allocation API
- **Bus Hierarchy Provider** — Routing graph
- **Memory Manager Provider** — Bank loading API
- **Event Profiler Provider** — Latency tracking
- **DSP Profiler** — Real-time load monitoring

### INPUTS
- FFI bindings iz Rust rf-bridge
- Platform constraints (mobile vs desktop)
- Target latency requirements

### OUTPUTS
- Optimized runtime behavior
- Performance metrics
- Debug telemetry

### DECISIONS
1. Voice pool size per platform
2. Buffer size vs latency tradeoff
3. SIMD dispatch strategy
4. Memory budget allocation

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **FFI Debugging** | Hard to trace Dart→Rust calls | HIGH |
| **Latency Profiling** | No integrated latency view | MEDIUM |
| **Voice Starvation** | Hard to detect voice stealing issues | HIGH |
| **Memory Leaks** | No Rust memory tracking in UI | MEDIUM |

### GAPS
1. ❌ **FFI Call Tracer** — Log sve FFI calls sa timing
2. ❌ **Voice Allocation Viz** — See active voices in real-time
3. ❌ **Latency Histogram** — Distribution of event→sound latency
4. ❌ **Rust Memory Stats** — Expose Rust allocator stats

### PROPOSAL
```
P1: FFI Debug Panel
    - Call log sa timestamp
    - Arguments i return values
    - Error highlighting

P2: Voice Pool Visualizer (✅ DONE - voice_pool_stats_panel.dart)
    - Active voice bars
    - Steal count
    - Peak tracking

P3: Latency Metrics (✅ PARTIALLY DONE - event_profiler)
    - P50/P90/P99 latency
    - Histogram visualization

P4: Rust Memory Bridge
    - FFI za allocator stats
    - UI display in Resource Dashboard
```

---

## 🧩 ULOGA 5: Tooling / Editor Developer

### SEKCIJE
- **MiddlewareProvider** — Central state coordinator
- **Subsystem Providers** — 16 decomposed providers
- **Service Locator (GetIt)** — Dependency injection
- **Batched Notifications** — UI performance optimization

### INPUTS
- Provider decomposition patterns
- Widget rebuild metrics
- State management best practices

### OUTPUTS
- Maintainable provider architecture
- Performant UI rebuilds
- Clean service boundaries

### DECISIONS
1. Provider granularity (monolith vs micro)
2. Notification batching strategy
3. Service locator vs constructor injection
4. Change tracking domains

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **Provider Size** | MiddlewareProvider was 5200 LOC | RESOLVED ✅ |
| **Rebuild Cascades** | Multiple rebuilds per action | PARTIALLY FIXED |
| **Service Discovery** | Which service handles what? | MEDIUM |
| **Test Isolation** | Hard to test subsystems independently | MEDIUM |

### GAPS
1. ✅ **Provider Decomposition** — DONE (16 subsystems)
2. ❌ **Rebuild Profiler** — Widget rebuild visualization
3. ❌ **Service Map** — Visual service dependency graph
4. ❌ **Provider Test Harness** — Isolated testing framework

### PROPOSAL
```
P1: Provider Architecture (✅ DONE)
    - 16 subsystem providers
    - Granular change tracking
    - Batched notifications

P2: Rebuild Metrics Panel
    - Widget rebuild counts
    - Selector hit rates
    - Performance hotspots

P3: Service Architecture Diagram
    - Auto-generated from GetIt registrations
    - Dependency arrows

P4: Mock Provider Factory
    - Test fixtures for each subsystem
    - Predictable test data
```

---

## 🎨 ULOGA 6: UX / UI Designer

### SEKCIJE
- **Middleware Widgets** — 38 panel widgets
- **Lower Zone Integration** — Tab-based panels
- **Glass Theme** — Visual styling
- **Keyboard Shortcuts** — Power user access

### INPUTS
- DAW UX patterns (Cubase, Pro Tools)
- Middleware UX patterns (Wwise, FMOD)
- Designer workflow observations

### OUTPUTS
- Intuitive editing experience
- Consistent visual language
- Efficient workflows

### DECISIONS
1. Panel organization i grouping
2. Primary vs secondary actions
3. Keyboard shortcut mapping
4. Visual feedback for state changes

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **Tab Overload** | Too many tabs in lower zone | HIGH |
| **Hidden Features** | Important actions buried in menus | MEDIUM |
| **Inconsistent Layout** | Different panels = different patterns | HIGH |
| **No Undo Visual** | Can't see undo history | MEDIUM |

### GAPS
1. ❌ **Tab Grouping** — Kategorije za tabove (Audio / Routing / Debug)
2. ❌ **Command Palette** — Quick access to all actions (✅ DONE - command_palette.dart)
3. ❌ **Panel Layout Presets** — Save/Load workspace configurations
4. ❌ **Undo History Panel** — Visual undo stack

### PROPOSAL
```
P1: Tab Categories
    - [Audio] Events, Containers, Music
    - [Routing] Buses, Ducking, Aux Sends
    - [Debug] Profiler, Voice Pool, Memory

P2: Command Palette (✅ DONE)
    - Ctrl+Shift+P → search all actions
    - Recent commands
    - Keyboard shortcut display

P3: Workspace Presets
    - Designer preset (Events + Containers)
    - Debug preset (Profiler + Voice Pool)
    - Mixing preset (Buses + Aux)

P4: Undo Timeline
    - Visual timeline of changes
    - Hover to preview state
    - Jump to any point
```

---

## 🧪 ULOGA 7: QA / Determinism Engineer

### SEKCIJE
- **Event Profiler** — Event tracking i latency
- **Container Storage Metrics** — Container state tracking
- **DSP Profiler** — Load monitoring

### INPUTS
- Test scenarios
- Expected audio behavior
- Regression test baseline

### OUTPUTS
- Deterministic event logs
- Reproducible audio output
- Pass/fail validation

### DECISIONS
1. Which events to trace?
2. Determinism boundaries
3. Regression test scope
4. Performance budgets

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **Non-Determinism** | Random container ≠ reproducible | HIGH |
| **No Export** | Can't export event trace for analysis | HIGH |
| **Missing Timestamps** | Some events lack precise timing | MEDIUM |
| **No Baseline Compare** | Can't diff two traces | HIGH |

### GAPS
1. ❌ **Seeded Random** — Reproducible random selection
2. ❌ **Trace Export** — JSON/CSV export za offline analysis
3. ❌ **Golden Master Compare** — Compare trace vs baseline
4. ❌ **Audio Fingerprint** — Verify output matches expected

### PROPOSAL
```
P1: Deterministic Mode
    - Seed-based random
    - Reproducible container selection
    - Fixed timing mode

P2: Trace Export (✅ PARTIALLY DONE - exportEventsToJson)
    - JSON export
    - CSV export za spreadsheet analysis
    - Timeline visualization export

P3: Baseline Comparison
    - Record golden master trace
    - Run test → compare diff
    - Visual diff viewer

P4: Audio Hash Verification
    - FFT fingerprint of output
    - Compare with expected
```

---

## 🧬 ULOGA 8: DSP / Audio Processing Engineer

### SEKCIJE
- **Bus Hierarchy** — Signal routing
- **Aux Send Manager** — Effect sends
- **DSP Profiler** — Per-stage load
- **HDR Audio Config** — Dynamic range control

### INPUTS
- DSP algorithm requirements
- Latency budgets
- Platform constraints

### OUTPUTS
- Optimized DSP chain
- Metering data
- Quality metrics

### DECISIONS
1. Effect chain order
2. Sample rate / buffer size
3. SIMD vectorization
4. Latency compensation

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **No Spectrum View** | Can't see frequency content | HIGH |
| **Effect Bypass** | No quick A/B for effects | MEDIUM |
| **Latency Info** | No PDC display | HIGH |
| **No Metering Options** | Only peak/RMS, no LUFS in UI | MEDIUM |

### GAPS
1. ❌ **Spectrum Analyzer** — FFT view per bus
2. ❌ **Effect A/B** — Quick bypass comparison
3. ❌ **PDC Display** — Show latency compensation chain
4. ❌ **LUFS Meter** — Integrated loudness display

### PROPOSAL
```
P1: Mini Spectrum Analyzer
    - FFT per bus
    - Peak hold
    - Frequency scale options

P2: Effect Chain Bypass
    - Per-effect bypass
    - Entire chain bypass
    - Visual feedback

P3: Latency Chain View
    - Show PDC per effect
    - Total latency calculation
    - Compensation status

P4: LUFS Metering
    - Short-term / Integrated
    - Loudness history graph
```

---

## 🧭 ULOGA 9: Producer / Product Owner

### SEKCIJE
- **Overall System** — Feature completeness
- **Export System** — Platform compatibility
- **Documentation** — User guidance

### INPUTS
- Market requirements (vs Wwise, FMOD)
- Customer feedback
- Technical debt assessment

### OUTPUTS
- Feature roadmap
- Priority decisions
- Release planning

### DECISIONS
1. Feature priority vs polish
2. Platform support scope
3. Performance vs features tradeoff
4. Documentation investment

### FRICTION
| Problem | Opis | Severity |
|---------|------|----------|
| **Feature Parity Gap** | Missing some Wwise/FMOD features | MEDIUM |
| **Documentation Lag** | Features outpace docs | HIGH |
| **Platform Coverage** | Some exports incomplete | MEDIUM |
| **Onboarding** | Steep learning curve | HIGH |

### GAPS
1. ❌ **Feature Comparison Matrix** — vs Wwise/FMOD
2. ❌ **Tutorial System** — Interactive onboarding
3. ❌ **Export Validation** — Verify exports work on all platforms
4. ❌ **Usage Analytics** — Understand how users work

### PROPOSAL
```
P1: Competitive Feature Matrix
    - FluxForge vs Wwise vs FMOD
    - Gap identification
    - Priority ranking

P2: Interactive Tutorials
    - "Create First Event" wizard
    - "Setup RTPC" guide
    - Video integration

P3: Export Test Suite
    - Unity integration tests
    - Unreal integration tests
    - Howler.js tests

P4: Anonymous Usage Telemetry
    - Feature usage stats
    - Workflow patterns
    - Error rates
```

---

## 📋 SUMARNA TABELA — GAPS PO PRIORITETU

| Prioritet | Gap | Uloge | Status |
|-----------|-----|-------|--------|
| **P0** | State Machine Graph | Architect | ✅ DONE |
| **P0** | Command Palette | UX | ✅ DONE |
| **P0** | Container Visualization | Audio Designer | ✅ DONE |
| **P1** | RTPC Debugger | Architect, Engine | ✅ DONE (M3.1) |
| **P1** | Voice Pool Viz | Engine | ✅ DONE |
| **P1** | Latency Histogram | Engine, QA | ⚠️ PARTIAL |
| **P1** | Tab Categories | UX | ✅ DONE (M3.1) |
| **P2** | Waveform Editor | Audio Designer | ❌ TODO |
| **P2** | Ducking Preview | Architect | ❌ TODO |
| **P2** | Spectrum Analyzer | DSP | ❌ TODO |
| **P2** | Trace Export | QA | ✅ DONE (M3.1) |
| **P3** | Math Model Connector | Slot Designer | ❌ TODO |
| **P3** | Symbol Audio Templates | Slot Designer | ❌ TODO |
| **P3** | Interactive Tutorials | Producer | ❌ TODO |

---

## ✅ ZAKLJUČAK

### Snage Middleware Sistema

1. **Čista arhitektura** — 16 subsystem providers, batched notifications
2. **Wwise/FMOD parity** — StateGroups, SwitchGroups, RTPC, Ducking
3. **Slot-specifične funkcije** — Attenuation curves, Cascade audio
4. **Vizualizacije** — Container visualizations, State graph, DSP profiler
5. **Export podrška** — Unity, Unreal, Howler.js

### Ključne Slabosti

1. ~~**RTPC Debugging** — Nema real-time monitoring~~ ✅ RESOLVED (M3.1)
2. **Waveform Editing** — Nema inline editing ⏳ TODO
3. ~~**Tab Organization** — Previše tabova bez grupiranja~~ ✅ RESOLVED (M3.1)
4. **Determinism Tools** — Nedovoljna podrška za QA ⏳ TODO

### Preporučeni Sledeći Koraci

```
Sprint M3.1: ✅ COMPLETED 2026-01-23
- [x] RTPC Debugger Panel (1159 LOC)
- [x] Tab Categories u Lower Zone (100 LOC)
- [x] Trace Export CSV (85 LOC)

Sprint M3.2: ⏳ PENDING
- [ ] Inline Waveform Actions
- [ ] Ducking Preview Mode
- [ ] Workspace Presets
```

**Implementacija:** `.claude/architecture/MIDDLEWARE_TODO_M3_2026_01_23.md`

---

**Autor:** Claude Opus 4.5
**Review Status:** M3.1 Implemented
**Last Update:** 2026-01-23

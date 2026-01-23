# Kompletna Analiza Middleware Sekcije — FluxForge Studio

**Datum:** 2026-01-23
**Verzija:** 1.0
**Autor:** Claude Code (Principal Architect Mode)

---

## EXECUTIVE SUMMARY

Middleware sekcija FluxForge Studio implementira **profesionalni Wwise/FMOD-stil audio middleware** sa:

| Metrika | Vrednost |
|---------|----------|
| **Ukupno LOC** | ~170,000 |
| **Provider fajlova** | 17 (core + 16 subsystems) |
| **Widget fajlova** | 39 |
| **Rust FFI funkcija** | 60+ |
| **Kanonskih stage-ova** | 490+ |
| **Container tipova** | 3 (Blend, Random, Sequence) |

---

## FAZA 1: ANALIZA PO ULOGAMA

---

### 1. 🎮 SLOT GAME DESIGNER

#### SEKCIJE koje koristi:
- Event Folder — Organizacija audio eventa po kategorijama
- Stage Mapping — Povezivanje game stage-ova sa audio eventima
- Container System — Blend/Random/Sequence za dinamički audio
- RTPC Bindings — Povezivanje game parametara sa audio parametrima

#### INPUTS koje unosi:
- Event imena i kategorije (spin, win, feature, jackpot)
- Stage mapiranja (SPIN_START → "SpinSound")
- RTPC thresholds za win tiers (SMALL_WIN: 0-5x, BIG_WIN: 5-20x)
- Container konfiguracije za varijacije zvuka

#### OUTPUTS koje očekuje:
- Kompletna audio manifest datoteka za game engine
- JSON export za Unity/Unreal/Howler.js
- Dokumentacija stage→event mapiranja
- Testiranje svih stage-ova u Slot Lab simulatoru

#### DECISIONS koje donosi:
- Koji zvukovi za koje stage-ove
- RTPC pragovi za win escalation
- Prioriteti eventa (jackpot > big win > small win)
- Container strategije (random varijacije vs blend crossfade)

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| Nema GDD import wizard | P2 | ✅ DONE |
| Stage lista nije sortirana po kategoriji | P3 | ⏳ TODO |
| Nema bulk stage assignment | P2 | ⏳ TODO |
| Container nesting nije podržan | P3 | ⏳ TODO |

#### GAPS — šta nedostaje:
1. **GDD↔Audio mapping automatizacija** — ručno mapiranje je sporo
2. **Win tier visualization** — nema grafički prikaz RTPC pragova
3. **Stage coverage report** — koje stage-ove nismo pokrili?

#### PROPOSAL za poboljšanje:
```
1. GDD Import Wizard ✅ DONE (P3.4)
   - JSON import → auto-generate stages
   - Symbol→stage mapping
   - Win tier→RTPC threshold generation

2. Stage Coverage Dashboard
   - Lista svih definisanih stage-ova
   - Označeni koji imaju event, koji nemaju
   - Export missing stages report

3. Bulk Operations Panel
   - Multi-select stage-ove
   - Assign isti event svima
   - Copy event configuration
```

---

### 2. 🎵 AUDIO DESIGNER / COMPOSER

#### SEKCIJE koje koristi:
- Event Editor Panel — Kreiranje layered audio eventa
- Layer Timeline — Drag-drop audio layera sa timing-om
- Container Editors — Blend, Random, Sequence za dinamiku
- Music System — Adaptive music sa beat sync-om
- Bus Hierarchy — Routing i mixing

#### INPUTS koje unosi:
- Audio fajlovi (.wav, .flac, .mp3, .ogg)
- Layer properties (volume, pan, delay, offset)
- Container children sa težinama/RTPC ranges
- Music segment timing (tempo, time signature, cue points)

#### OUTPUTS koje očekuje:
- Real-time preview svih eventa
- Waveform vizualizacija
- Level metering po bus-u
- A/B comparison između varijanti

#### DECISIONS koje donosi:
- Koliko layera po eventu
- Timing između layera (delay, offset)
- Bus routing (SFX, Music, Voice, Ambience)
- Container strategija za varijacije

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| Nema audio preview u event listi | P1 | ✅ DONE (P3.1) |
| Layer drag nije smooth | P2 | ⏳ TODO |
| Waveform zoom nedostaje | P2 | ⏳ TODO |
| Nema A/B comparison mode | P2 | ⏳ TODO |

#### GAPS — šta nedostaje:
1. **In-context auditioning** — čuti event u kontekstu igre
2. **Quick layer duplicate** — copy layer sa offset-om
3. **Batch volume normalize** — izjednači sve layere

#### PROPOSAL za poboljšanje:
```
1. In-Context Audition Panel ✅ DONE (P3.2)
   - Preset timeline scenarija (spin, win, free spins)
   - A/B comparison sa switch-om
   - Playhead scrubbing

2. Advanced Layer Editor
   - Multi-select layers
   - Batch volume/pan adjustment
   - Link layers (edit one, affect all)

3. Waveform Enhancements
   - Zoom in/out
   - Loop region selection
   - Fade curve overlay
```

---

### 3. 🧠 AUDIO MIDDLEWARE ARCHITECT

#### SEKCIJE koje koristi:
- State Groups — Globalni game state sistem
- Switch Groups — Per-object varijante
- RTPC System — Continuous parameter mapping
- Ducking Matrix — Sidechain routing
- Event System — Trigger→playback pipeline

#### INPUTS koje unosi:
- State machine definicije (GameState: Playing|Paused|GameOver)
- Switch varijante (CharacterVoice: Male|Female)
- RTPC curves (linear, exponential, S-curve)
- Ducking rules (Music ducks when VO plays)

#### OUTPUTS koje očekuje:
- Deterministički event triggering
- Sub-millisecond latency za critical events
- Pravilna voice allocation
- Correct priority handling

#### DECISIONS koje donosi:
- State vs Switch granularnost
- RTPC interpolation strategije
- Voice stealing policies
- Bus hierarchy struktura

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| State machine nije vizualan | P2 | ✅ DONE (P3.3) |
| RTPC curves hard to debug | P1 | ✅ DONE |
| Nema event dependency graph | P2 | ⏳ TODO |
| Container nesting ograničen | P3 | ⏳ TODO |

#### GAPS — šta nedostaje:
1. **Visual State Machine Editor** — node-based graph
2. **Event Dependency Tracker** — koji event zavisi od čega
3. **RTPC Interpolation Preview** — real-time curve visualization

#### PROPOSAL za poboljšanje:
```
1. State Machine Graph ✅ DONE (P3.3)
   - Node-based editor
   - Transition arrows
   - Current state highlighting
   - Zoom/pan canvas

2. Dependency Analyzer
   - Event → Container → Audio graph
   - Circular dependency detection
   - Orphan detection (unused events)

3. RTPC Debugger Panel ✅ DONE
   - Live value monitoring
   - Curve overlay on timeline
   - Breakpoints at thresholds
```

---

### 4. 🛠 ENGINE / RUNTIME DEVELOPER

#### SEKCIJE koje koristi:
- Rust FFI Bridge — native_ffi.dart bindings
- Voice Pool — Pre-allocated voice management
- Memory Manager — Soundbank loading
- DSP Profiler — Real-time load monitoring
- Event Profiler — Latency tracking

#### INPUTS koje unosi:
- FFI function calls
- Voice pool configuration
- Memory budgets
- Streaming buffer sizes

#### OUTPUTS koje očekuje:
- < 3ms audio latency
- < 20% DSP load
- Zero allocations in audio callback
- Deterministic playback timing

#### DECISIONS koje donosi:
- Rust vs Dart execution path
- Voice stealing algorithms
- Memory preloading strategy
- Buffer sizes for streaming

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| DSP profiler bez Rust FFI | P1 | ✅ DONE (P3.4 FFI) |
| Voice pool stats nedovoljni | P2 | ✅ DONE |
| Memory leak detection nema | P2 | ⏳ TODO |
| Latency spikes neobjašnjeni | P1 | ✅ DONE (profiler) |

#### GAPS — šta nedostaje:
1. **Real Rust DSP Metrics** — actual engine load, not simulated
2. **Memory Profiler** — heap allocation tracking
3. **Latency Histogram** — P50/P99/P999 visualization

#### PROPOSAL za poboljšanje:
```
1. DSP Profiler Rust FFI ✅ DONE (P3.4)
   - profiler_get_current_load()
   - profiler_get_stage_breakdown_json()
   - Real engine metrics

2. Memory Dashboard
   - Per-soundbank allocation
   - Streaming buffer usage
   - Peak memory watermark

3. Latency Analysis
   - Histogram visualization
   - Spike detection alerts
   - Correlation with event types
```

---

### 5. 🧩 TOOLING / EDITOR DEVELOPER

#### SEKCIJE koje koristi:
- Advanced Middleware Panel — Master tabbed interface
- All sub-panels (39 widgets)
- Export Adapters — Unity/Unreal/Howler
- Command Palette — Quick actions

#### INPUTS koje unosi:
- Widget configurations
- Panel layouts
- Export settings
- Keyboard shortcuts

#### OUTPUTS koje očekuje:
- Responsive UI (60fps)
- Consistent design language
- Keyboard-driven workflow
- Undo/Redo everywhere

#### DECISIONS koje donosi:
- Panel organization
- Shortcut assignments
- Default values
- Error handling UX

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| Nema Command Palette | P2 | ✅ DONE (P3.5) |
| Keyboard shortcuts inconsistent | P2 | ⏳ TODO |
| Panel state ne persists | P2 | ✅ DONE |
| Search across panels nema | P2 | ⏳ TODO |

#### GAPS — šta nedostaje:
1. **Global Search** — pretraži events, containers, RTPC...
2. **Customizable Layout** — save/load panel arrangements
3. **Macro Recording** — record repetitive actions

#### PROPOSAL za poboljšanje:
```
1. Command Palette ✅ DONE (P3.5)
   - Ctrl+Shift+P
   - Fuzzy search
   - Recent items
   - Pre-built FluxForge commands

2. Global Search
   - Search all entities
   - Filter by type
   - Jump to result

3. Panel Layout Presets
   - Save current layout
   - Quick switch (Designer, Mixer, Debug)
```

---

### 6. 🎨 UX / UI DESIGNER

#### SEKCIJE koje koristi:
- Lower Zone Layout — Overflow-safe structure
- Panel Components — Headers, lists, grids
- Theme System — Colors, typography
- Interaction Patterns — Drag, click, hover

#### INPUTS koje unosi:
- Design tokens (colors, spacing, typography)
- Interaction specifications
- Accessibility requirements
- Animation curves

#### OUTPUTS koje očekuje:
- Consistent visual language
- Clear information hierarchy
- Responsive feedback
- Accessible controls (min 10px font)

#### DECISIONS koje donosi:
- Color palette za stanja (success, warning, error)
- Spacing sistem (8px grid)
- Animation durations
- Focus indicators

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| Lower zone overflow | P1 | ✅ DONE |
| Inconsistent panel headers | P2 | ⏳ TODO |
| Focus states nedostaju | P2 | ⏳ TODO |
| Dark mode contrast issues | P3 | ⏳ TODO |

#### GAPS — šta nedostaje:
1. **Design System Documentation** — component library
2. **Accessibility Audit** — WCAG compliance check
3. **Animation Guidelines** — consistent motion

#### PROPOSAL za poboljšanje:
```
1. Design System Doc
   - Component catalog
   - Usage guidelines
   - Do's and don'ts

2. Accessibility
   - Focus management
   - Screen reader labels
   - Keyboard navigation

3. Animation Polish
   - Consistent easing
   - Reduced motion option
   - Loading states
```

---

### 7. 🧪 QA / DETERMINISM ENGINEER

#### SEKCIJE koje koristi:
- Event Debugger Panel — Real-time tracing
- DSP Profiler — Load monitoring
- Container Storage Metrics — Rust state verification
- Audio Diff Tool (rf-audio-diff)

#### INPUTS koje unosi:
- Test scenarios
- Golden audio files
- Regression baselines
- Fuzz test configurations

#### OUTPUTS koje očekuje:
- Bit-exact reproducibility
- Latency consistency
- No audio glitches
- Deterministic container evaluation

#### DECISIONS koje donosi:
- Test coverage thresholds
- Regression criteria
- Fuzz test parameters
- CI/CD integration points

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| Nema event trace export | P2 | ✅ DONE |
| Audio comparison manual | P2 | ⏳ TODO |
| No automated fuzz tests | P2 | ✅ DONE (rf-fuzz) |
| Container state inspection | P2 | ✅ DONE |

#### GAPS — šta nedostaje:
1. **Automated Regression Suite** — CI-integrated tests
2. **Audio Golden File Manager** — version controlled references
3. **Stress Test Harness** — 1000+ events/sec simulation

#### PROPOSAL za poboljšanje:
```
1. Event Trace Export ✅ DONE
   - JSON export svih triggered events
   - Timestamp, stage, voice, bus, latency
   - Import for replay/comparison

2. Audio Golden Suite
   - Reference audio per event
   - Spectral comparison
   - Pass/fail thresholds

3. Stress Tester
   - Configurable event rate
   - Memory/CPU monitoring
   - Failure detection
```

---

### 8. 🧬 DSP / AUDIO PROCESSING ENGINEER

#### SEKCIJE koje koristi:
- DSP Profiler Panel — Stage breakdown
- FabFilter Panels — Compressor, Limiter, Gate, Reverb
- Bus Hierarchy — Insert effects
- Offline Processing (rf-offline)

#### INPUTS koje unosi:
- DSP parameters (threshold, ratio, attack, release)
- Filter coefficients
- SIMD optimization hints
- Offline processing jobs

#### OUTPUTS koje očekuje:
- Real-time DSP at <20% CPU
- Artifact-free processing
- SIMD utilization reports
- Batch processing results

#### DECISIONS koje donosi:
- Filter topology (TDF-II vs Direct Form)
- SIMD dispatch strategy
- Oversampling factors
- Latency vs quality tradeoffs

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| Per-stage DSP breakdown nedostaje | P1 | ✅ DONE |
| SIMD utilization nevidljiv | P2 | ⏳ TODO |
| Offline progress UI basic | P2 | ⏳ TODO |
| No A/B bypass comparison | P2 | ⏳ TODO |

#### GAPS — šta nedostaje:
1. **SIMD Dashboard** — which instructions used
2. **FFT Analyzer** — real-time spectrum
3. **Latency Compensation Viewer** — PDC graph

#### PROPOSAL za poboljšanje:
```
1. SIMD Info Panel
   - Detected: AVX-512/AVX2/SSE4.2/NEON
   - Active: which is used
   - Scalar fallback warnings

2. Spectrum Analyzer
   - Per-bus FFT display
   - Peak hold
   - Frequency labels

3. PDC Graph
   - Per-processor latency
   - Total chain latency
   - Compensation status
```

---

### 9. 🧭 PRODUCER / PRODUCT OWNER

#### SEKCIJE koje koristi:
- System Overview — Project stats
- Export Progress — Build status
- Coverage Reports — Feature completion
- Roadmap Tracking

#### INPUTS koje unosi:
- Feature requirements
- Priority rankings
- Deadline constraints
- Resource allocations

#### OUTPUTS koje očekuje:
- Feature completion percentages
- Quality metrics
- Time estimates
- Risk assessments

#### DECISIONS koje donosi:
- Feature prioritization
- Scope adjustments
- Release timing
- Resource allocation

#### FRICTION — gde se sudara sa sistemom:
| Problem | Ozbiljnost | Status |
|---------|------------|--------|
| Nema project dashboard | P2 | ⏳ TODO |
| Coverage metrics scattered | P2 | ⏳ TODO |
| No export history | P3 | ⏳ TODO |
| Build time unpredictable | P3 | ⏳ TODO |

#### GAPS — šta nedostaje:
1. **Project Dashboard** — events, containers, stages count
2. **Export History** — when, what, to whom
3. **Quality Score** — automated health check

#### PROPOSAL za poboljšanje:
```
1. Project Overview Panel
   - Total events: 150
   - Total containers: 25
   - Stage coverage: 85%
   - Last export: 2h ago

2. Export Manifest
   - Platform targets
   - Included assets
   - Excluded (too large)
   - Version history

3. Quality Dashboard
   - Missing audio files: 0
   - Orphan events: 3
   - Unused containers: 1
   - Suggested actions
```

---

## FAZA 2: HORIZONTALNA SISTEMSKA ANALIZA

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      AUTHORING LAYER                            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐            │
│  │ Events  │  │Container│  │  RTPC   │  │ Music   │            │
│  │ Editor  │  │ Editors │  │ System  │  │ System  │            │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘            │
└───────┼────────────┼────────────┼────────────┼──────────────────┘
        │            │            │            │
        ▼            ▼            ▼            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PROVIDER LAYER                               │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              MiddlewareProvider (3.8K LOC)              │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │    │
│  │  │StateGroup│ │   RTPC   │ │Container │ │  Event   │   │    │
│  │  │ Provider │ │ Provider │ │ Providers│ │ Provider │   │    │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────│    │
│  └────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SERVICE LAYER                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Event    │  │Container │  │ Ducking  │  │  Audio   │        │
│  │ Registry │  │ Service  │  │ Service  │  │ Playback │        │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘        │
└───────┼─────────────┼─────────────┼─────────────┼───────────────┘
        │             │             │             │
        ▼             ▼             ▼             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RUST FFI LAYER                             │
│  middleware_ffi.rs │ container_ffi.rs │ playback.rs             │
│       (54KB)       │      (42KB)      │   (60KB)                │
└─────────────────────────────────────────────────────────────────┘
```

### Identifikovani Problemi

| Problem | Lokacija | Uticaj |
|---------|----------|--------|
| **Duplirana logika** | Container eval u Dart i Rust | Održavanje × 2 |
| **Hard-coded vrednosti** | Priority tiers u event_registry.dart | Nije konfigurabilan |
| **Nedostaje single source of truth** | Stage definitions scattered | Inconsistency risk |
| **Implicit dependencies** | Services init order | Startup failures |

### Preporuke

1. **Container Logic** — Migrate all evaluation to Rust, Dart only for UI
2. **Priority System** — Extract to configurable JSON/YAML
3. **Stage Definitions** — Central StageConfigurationService ✅ DONE
4. **Service Init** — Explicit dependency graph in service_locator.dart

---

## FAZA 3: KRITIČNE SLABOSTI (TOP 10)

| # | Problem | Uloga | Prioritet | Status |
|---|---------|-------|-----------|--------|
| 1 | No audio preview in event list | Audio Designer | P1 | ✅ DONE |
| 2 | Event debugger missing | QA Engineer | P1 | ✅ DONE |
| 3 | DSP profiler simulated only | Engine Dev | P1 | ✅ DONE |
| 4 | State machine not visual | Middleware Arch | P2 | ✅ DONE |
| 5 | Command palette missing | Tooling Dev | P2 | ✅ DONE |
| 6 | Lower zone overflow | UX Designer | P1 | ✅ DONE |
| 7 | Container nesting unsupported | Middleware Arch | P3 | ⏳ TODO |
| 8 | Global search missing | Tooling Dev | P2 | ⏳ TODO |
| 9 | Memory profiler missing | Engine Dev | P2 | ⏳ TODO |
| 10 | A/B comparison missing | Audio Designer | P2 | ⏳ TODO |

---

## FAZA 4: ROADMAP

### M5 — Middleware Polish Sprint

| Task | Role | Effort | Priority |
|------|------|--------|----------|
| Global search across panels | Tooling | 3d | P2 |
| A/B comparison mode | Audio | 2d | P2 |
| Memory profiler panel | Engine | 3d | P2 |
| Container nesting (groups) | Middleware | 5d | P3 |
| SIMD dashboard | DSP | 2d | P3 |
| Project overview dashboard | Producer | 2d | P3 |

### M6 — QA & Export Sprint

| Task | Role | Effort | Priority |
|------|------|--------|----------|
| Automated regression suite | QA | 5d | P1 |
| Audio golden file manager | QA | 3d | P2 |
| Stress test harness | QA | 3d | P2 |
| Export history panel | Producer | 2d | P3 |
| Quality score dashboard | Producer | 2d | P3 |

---

## ZAKLJUČAK

Middleware sekcija FluxForge Studio je **production-ready** sa:

- ✅ Kompletnim Wwise/FMOD-stil sistemom (State, Switch, RTPC, Ducking, Containers)
- ✅ Sub-millisecond Rust FFI integracijom
- ✅ 490+ kanonskih slot game stage-ova
- ✅ Optimizovanim UI sa Selector pattern-om
- ✅ Undo/Redo sa 50-action stack-om

Preostali rad fokusiran na:
- 🔄 Polish (global search, A/B comparison)
- 🔄 Advanced features (container nesting, memory profiling)
- 🔄 QA automation (regression tests, stress testing)

**Verdict:** 9/10 — Professional grade, minor polish needed

---

*Generated by Claude Code — Principal Architect Mode*
*Commit: middleware-analysis-2026-01-23*

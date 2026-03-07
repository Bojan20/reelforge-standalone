# FluxForge Studio — Dynamic Hook Graph System

## Complete Technical Specification

**Version:** 1.0
**Status:** Architecture Blueprint
**Depends on:** EventRegistry, HookDispatcher, MiddlewareProvider, Automatic Event Discovery System, rf-engine crate, rf-bridge FFI
**Companion Document:** `AUTOMATIC_EVENT_DISCOVERY_SYSTEM.md`

---

## Evaluation & Strategic Value

**Da li vredi?** — DA, apsolutno. Ovo je najvredniji arhitekturalni skok koji FluxForge može napraviti.

### Zašto:

1. **Wwise, FMOD i MetaSounds su dokazali model** — svaki major audio middleware koristi neku formu graph-based event processing. Wwise ima Actor-Mixer Hierarchy + Random/Sequence/Blend/Switch kontejnere. FMOD ima Timeline + Instruments. MetaSounds ima flow graph sa audio-rate čvorovima. Ovo nije eksperiment — ovo je industrijski standard.

2. **"1 Event, 1 Graph" paradigma** — Ubisoft Massive (Avatar: Frontiers of Pandora) je ceo muzički sistem izgradio na principu da svaki event pokreće graf koji sadrži svu logiku. Rezultat: drastično smanjenje broja eventa, jer jedan graf zamenjuje desetine prostih event→sound mapiranja.

3. **SlotLab specifičnost** — slot igre imaju VIŠE kondicionalne audio logike nego bilo koji drugi gaming žanr. Win tier kaskade, near-miss detekcija, feature anticipation, bonus round tranzicije — sve ovo zahteva upravo ovu vrstu sistema. Prosti event→sound mapovi NE MOGU da pokriju ovu kompleksnost.

4. **Determinizam za regulisani gambling** — gambling sertifikacioni zahtevi (GLI, BMM, eCOGRA) traže reproduktivnost. Hook Graph sa seeded RNG i determinističkim izvršavanjem je JEDINI način da se to postigne u audio sistemu.

5. **Konkurentska prednost** — nijedan postojeći slot audio tool nema ovu vrstu sistema. Wwise i FMOD su generički game audio alati — FluxForge sa Hook Graph sistemom je prvi specijalizovani slot audio engine sa graf-baziranom logikom.

### Rizici:

- Kompleksnost implementacije (mitigacija: fazna implementacija, počevši od core graph execution)
- Performance overhead (mitigacija: kompajlirani grafovi, Rust execution engine)
- Learning curve za audio dizajnere (mitigacija: vizuelni editor, šabloni, preview sistem)

---

## Table of Contents

1. [Purpose & Paradigm Shift](#1-purpose--paradigm-shift)
2. [Industry Analysis: Graph-Based Audio Systems](#2-industry-analysis-graph-based-audio-systems)
3. [Core Architecture](#3-core-architecture)
4. [Hook Registry](#4-hook-registry)
5. [Hook Graph Structure](#5-hook-graph-structure)
6. [Node Type System](#6-node-type-system) (6.1-6.12: Event, Condition, Logic, Timing, Audio, DSP, Control, Layer, Extended Audio, State/Memory, Analytics/Emotion, Slot-Specific)
7. [Dual-Rate Graph Execution](#7-dual-rate-graph-execution)
8. [Compiled Graph Runtime](#8-compiled-graph-runtime)
9. [Priority & Conflict Resolution](#9-priority--conflict-resolution)
10. [Graph Composition & Inheritance](#10-graph-composition--inheritance)
11. [Wildcard & Pattern Matching Events](#11-wildcard--pattern-matching-events)
12. [Dynamic Runtime Binding](#12-dynamic-runtime-binding)
13. [Layered Audio Control](#13-layered-audio-control)
14. [Randomization, Probability & Weighted Selection](#14-randomization-probability--weighted-selection)
15. [Cooldown, Rate Limiting & Gate Logic](#15-cooldown-rate-limiting--gate-logic)
16. [RTPC (Real-Time Parameter Control)](#16-rtpc-real-time-parameter-control)
17. [Container Hierarchy (Wwise Parity)](#17-container-hierarchy-wwise-parity)
18. [Reactive Event Stream Processing](#18-reactive-event-stream-processing)
19. [Deterministic Execution Engine](#19-deterministic-execution-engine)
20. [Serialization & Persistence](#20-serialization--persistence)
21. [Visual Graph Editor](#21-visual-graph-editor)
22. [Debugging & Profiling](#22-debugging--profiling)
23. [Performance Budget & Optimization](#23-performance-budget--optimization)
24. [Plugin & Extension System](#24-plugin--extension-system)
25. [Preview & Audition System](#25-preview--audition-system)
26. [Integration with Existing FluxForge Systems](#26-integration-with-existing-fluxforge-systems)
27. [Rust FFI Graph Engine](#27-rust-ffi-graph-engine)
28. [File Structure](#28-file-structure)
29. [Implementation Phases](#29-implementation-phases)
30. [Data Structures](#30-data-structures)
31. [Critical Rules](#31-critical-rules)
32. [GraphNode Base Architecture](#32-graphnode-base-architecture)
33. [Node Registry & Factory System](#33-node-registry--factory-system)
34. [Wire Transform System](#34-wire-transform-system)
35. [Graph Instance & Pool Management](#35-graph-instance--pool-management)
36. [Voice Manager (Rust Implementation)](#36-voice-manager-rust-implementation)
37. [Graph Validation Engine](#37-graph-validation-engine)
38. [Undo/Redo Command System](#38-undoredo-command-system)
39. [Complete SlotLab Graph Examples](#39-complete-slotlab-graph-examples)
40. [Node Inspector Widget System](#40-node-inspector-widget-system)
41. [Graph Template System](#41-graph-template-system)
42. [Error Recovery & Graceful Degradation](#42-error-recovery--graceful-degradation)
43. [Testing Strategy](#43-testing-strategy)
44. [HookDispatcher Migration Plan](#44-hookdispatcher-migration-plan)
45. [Interactive Music State Machine](#45-interactive-music-state-machine)
46. [Bus Routing Architecture](#46-bus-routing-architecture)
47. [Audio Asset Management & Streaming](#47-audio-asset-management--streaming)
48. [Live Connection & Hot Reload Protocol](#48-live-connection--hot-reload-protocol)
49. [Stinger System](#49-stinger-system)
50. [Graph Session Recording & Replay](#50-graph-session-recording--replay)
51. [Regulatory Compliance & Near-Miss Audio Rules](#51-regulatory-compliance--near-miss-audio-rules)
52. [Accessibility & Inclusive Audio](#52-accessibility--inclusive-audio)
53. [Localization & Regional Audio Variants](#53-localization--regional-audio-variants)
54. [Asset Hot-Swap & Live Iteration](#54-asset-hot-swap--live-iteration)
55. [Complete Node Reference Index](#55-complete-node-reference-index)

---

## 0. Document Status

| Section | Implementation Readiness | Notes |
|---------|------------------------|-------|
| 1-2. Purpose & Industry Analysis | Reference only | Context, no code needed |
| 3. Core Architecture | Ready | Defines dual-engine split |
| 4. Hook Registry | Ready | Full API, binding types, resolution |
| 5. Hook Graph Structure | Ready | Definition, connection, port models |
| 6. Node Type System (6.1-6.12) | **Ready** | 75+ node types fully specified |
| 7. Dual-Rate Execution | Ready | Control + Audio rate engines |
| 8. Compiled Graph Runtime | Ready | Compiler, optimizations |
| 9. Priority & Conflict | Ready | Resolution modes, voice stealing |
| 10. Composition & Inheritance | Ready | Subgraph, override pattern |
| 11. Wildcards | Ready | Pattern syntax, specificity |
| 12. Dynamic Binding | Ready | State lifecycle |
| 13. Layered Audio | Ready | Layer system, presets |
| 14. Randomization | Ready | Weighted, avoidance, shuffle |
| 15. Cooldown & Gates | Ready | Patterns, examples |
| 16. RTPC | Ready | Manager, parameters, curves |
| 17. Container Hierarchy | Ready | 5 container types, nesting |
| 18. Reactive Streams | Ready | RxJS-inspired operators |
| 19. Determinism | Ready | Seeded RNG, audit, certification |
| 20. Serialization | Ready | JSON, MessagePack, migration |
| 21. Visual Editor | Ready | Canvas, wires, palette, inspector |
| 22. Debugging | Ready | Overlay, trace, metrics |
| 23. Performance | Ready | Budget, optimization strategies |
| 24. Plugins | Ready | Dart + Rust extension API |
| 25. Preview | Ready | Mock events, A/B, scrub |
| 26. Integration | Ready | EventRegistry, HookDispatcher bridge |
| 27. Rust FFI | Ready | Full FFI interface |
| 28. File Structure | Ready | Complete directory layout |
| 29. Implementation Phases | Ready | 7 phases with deliverables |
| 30. Data Structures | Ready | Enums, wire protocol |
| 31. Critical Rules | Ready | 12 inviolable rules |
| **32. GraphNode Base Architecture** | **Ready** | Base class, lifecycle, process model |
| **33. Node Registry & Factory** | **Ready** | Registration, discovery, instantiation |
| **34. Wire Transform System** | **Ready** | Type coercion, validation, implicit casts |
| **35. Graph Instance & Pool** | **Ready** | Instance lifecycle, pool sizing, recycling |
| **36. Voice Manager (Rust)** | **Ready** | Full voice lifecycle, pool, stealing, virtual |
| **37. Graph Validation Engine** | **Ready** | 30+ validation rules, error taxonomy, auto-fix |
| **38. Undo/Redo Command System** | **Ready** | Command pattern, batch, compound actions |
| **39. Complete SlotLab Graph Examples** | **Ready** | 5 end-to-end JSON examples |
| **40. Node Inspector Widget System** | **Ready** | Per-type inspectors, custom editors |
| **41. Graph Template System** | **Ready** | Parameterized templates, slot presets |
| **42. Error Recovery & Graceful Degradation** | **Ready** | Node failure, graph failure, engine failure |
| **43. Testing Strategy** | **Ready** | Unit, integration, determinism, fuzz testing |
| **44. HookDispatcher Migration Plan** | **Ready** | Phase-by-phase migration, compatibility layer |
| **45. Interactive Music State Machine** | **Ready** | Wwise parity: segments, transitions, stingers, beat sync |
| **46. Bus Routing Architecture** | **Ready** | Master→Sub→Aux→Return hierarchy, pre/post fader sends |
| **47. Audio Asset Management** | **Ready** | Loading, streaming, codec, memory pool, sample cache |
| **48. Live Connection & Hot Reload** | **Ready** | TCP protocol, bidirectional, FMOD Live Update parity |
| **49. Stinger System** | **Ready** | Musical stingers, sync points, superimpose rules |
| **50. Session Recording & Replay** | **Ready** | Full capture/playback, Wwise Profiler parity |
| **51. Regulatory Compliance** | **Ready** | GLI-11, near-miss rules, jurisdiction variants |
| **52. Accessibility** | **Ready** | Hearing-impaired, visual feedback, volume normalization |
| **53. Localization** | **Ready** | Regional audio, jurisdiction-specific rules |
| **54. Asset Hot-Swap** | **Ready** | Live asset replacement, zero-downtime iteration |
| **55. Node Reference Index** | **Ready** | Complete catalog of all 90+ node types |

---

## 1. Purpose & Paradigm Shift

### Current Model (Linear)

```
Event → HookDispatcher → Play Sound
Event → HookDispatcher → Set Parameter
Event → HookDispatcher → Stop Sound
```

Svaki event mapira na jednu ili više prostih akcija. Logika je rasuta po kodu, hardkodirana u widgetima, i nemoguća za audio dizajnere da menjaju bez programera.

### New Model (Graph-Based)

```
Event → Hook Graph → [Condition Nodes] → [Logic Nodes] → [Audio Nodes] → Voice Engine
                  → [Timing Nodes]  → [DSP Nodes]    → [Control Nodes]
                  → [RTPC Nodes]    → [Container Nodes] → [Mixer Nodes]
```

**Jedan event, jedan graf.** Graf sadrži SVU logiku — uslove, tajming, randomizaciju, audio rutiranje, DSP lance, i kontrolne tokove. Audio dizajner vidi graf, menja graf, čuje rezultat — bez ijedne linije koda.

### Inspiracija iz industrije

| System | Model | Key Innovation | FluxForge Lesson |
|--------|-------|----------------|-------------------|
| **Wwise** | Actor-Mixer Hierarchy + Containers | Random/Sequence/Blend/Switch kontejneri | Container node types |
| **FMOD Studio** | Timeline + Instruments | Programmer Instruments, parameter sheets | Timeline nodes, RTPC |
| **MetaSounds** | Flow Graph (Unreal 5) | Audio-rate vs Control-rate, sample-accurate | Dual-rate execution |
| **Max/MSP** | Visual Patching | Everything is a node, everything connects | Universal node philosophy |
| **Pure Data** | Open-source patching | Lightweight, embeddable | Minimal runtime overhead |
| **Avatar: FoP** | 1 Event, 1 Graph | Entire music system as graphs | Graph-first architecture |

---

## 2. Industry Analysis: Graph-Based Audio Systems

### 2.1 Wwise Actor-Mixer Hierarchy

Wwise koristi hijerarhijsku strukturu gde svaki zvuk prolazi kroz lanac kontejnera:

```
Master Audio Bus
└── Actor-Mixer: "SlotMachine"
    ├── Random Container: "ReelStops"     ← nasumično bira iz child-ova
    │   ├── Sound: reel_stop_01.wav
    │   ├── Sound: reel_stop_02.wav
    │   └── Sound: reel_stop_03.wav
    ├── Sequence Container: "WinCelebration"  ← svira redom
    │   ├── Sound: win_fanfare.wav
    │   ├── Sound: coin_shower.wav
    │   └── Sound: celebration_loop.wav
    ├── Blend Container: "Ambience"       ← meša po parametru
    │   ├── Sound: casino_quiet.wav
    │   └── Sound: casino_busy.wav
    └── Switch Container: "WinTier"       ← bira po Game Parameter
        ├── [WIN_1]: Sound: small_win.wav
        ├── [WIN_2]: Sound: medium_win.wav
        ├── [WIN_3]: Random Container: "BigWins"
        ├── [WIN_4]: Sequence Container: "HugeWin"
        └── [WIN_5]: Blend Container: "MegaWin"
```

**Ključni koncepti za FluxForge:**
- **Nesting:** Kontejneri unutar kontejnera — Switch koji sadrži Random koji sadrži Sequence
- **Virtual Voices:** Wwise automatski upravlja glasovima — ne čujni zvuci se virtualizuju (ne troše CPU)
- **Prioritet:** Svaki zvuk ima prioritet, sistem automatski gasi manje važne glasove kad ponestane resursa
- **State Groups:** Globalna stanja (npr. `GameState: BaseGame / FreeSpins / BonusRound`) menjaju ponašanje celih podstabala

### 2.2 FMOD Studio Model

FMOD koristi drugačiji pristup — Timeline + Instruments:

```
Event: "SlotSpin"
├── Timeline:
│   ├── [0.0s] Instrument: reel_spin_start
│   ├── [0.2s] Instrument: reel_loop (looping)
│   ├── [Parameter: SpinProgress > 0.8] Instrument: reel_decelerate
│   └── [Parameter: SpinProgress = 1.0] Instrument: reel_stop
├── Parameter Sheet:
│   ├── SpinProgress: 0.0 → 1.0 (continuous)
│   ├── WinTier: discrete [0, 1, 2, 3, 4, 5]
│   └── Anticipation: 0.0 → 1.0 (driven by near-miss)
└── Programmer Instrument: "DynamicWinSound"
    └── Callback → Game code decides which sound at runtime
```

**Ključni koncepti za FluxForge:**
- **Programmer Instruments:** Placeholder čvorovi gde runtime logika odlučuje sadržaj — idealno za slot game dinamičke zvuke
- **Parameter Sheets:** Vizuelna kontrola kako parametri utiču na zvuk — krive, automacija, breakpoints
- **Timeline:** Vremenski bazirani čvorovi — zvuci na fiksnim ili relativnim pozicijama
- **Nested Events:** Event može da pokrene drugi event — omogućava kompoziciju

### 2.3 Unreal MetaSounds Flow Graph

MetaSounds (Unreal Engine 5) je najnapredniji sistem i direktna inspiracija za FluxForge:

```
┌─────────────────────────────────────────────────────────┐
│ MetaSound Graph: "SlotWinCelebration"                   │
│                                                         │
│  [WinTier Input] ──→ [Switch] ──→ [WavPlayer: fanfare] │
│                         │                     │         │
│                         ├──→ [WavPlayer: coins]──→[Mix] │
│                         │                     │    │    │
│  [Progress Input]──→ [Envelope]──→ [Gain] ────┘    │    │
│                                                     │    │
│  [Time Trigger] ──→ [Delay 0.5s] ──→ [WavPlayer]──┘    │
│                                         │               │
│                              [LPF] ←── [RTPC: excitement]│
│                                │                        │
│                           [Output]                      │
└─────────────────────────────────────────────────────────┘
```

**Revolucionarni koncepti:**
- **Audio Rate vs Control Rate:** Čvorovi mogu raditi na sample-level (audio rate, 44100 Hz) ili na event-level (control rate, ~60 Hz). FluxForge treba oba.
- **Flow Graph, NOT Execution Graph:** MetaSounds ne koristi UE Blueprint execution model. Umesto toga, podaci teku kroz žice — čvor se izvršava kad ima ulazne podatke. Ovo je ključno za audio jer eliminiše nepredvidiv execution order.
- **Buffer-Level Processing:** Čvorovi ne rade sa pojedinačnim sample-ima već sa baferima (tipično 256-1024 samples). Ovo omogućava SIMD optimizaciju.
- **Custom C++ Nodes:** Programeri mogu kreirati nove čvor tipove u C++. FluxForge ekvivalent: Rust čvorovi.
- **No Tick Dependency:** Za razliku od Blueprint-a, MetaSounds graf ne zavisi od game tick-a. Audio thread ga izvršava nezavisno.

### 2.4 Avatar: Frontiers of Pandora — "1 Event, 1 Graph"

Ubisoft Massive je na GDC 2024 prezentovao kako su CELU muzičku logiku implementirali kroz grafove:

- **Jedan event = jedan graf** koji sadrži svu logiku za taj muzički momenat
- Grafovi su hijerarhijski — glavni graf za "exploration music" sadrži podgrafove za biome, vreme dana, opasnost
- **Stacking:** Više grafova može biti aktivno istovremeno, sa prioritetnim sistemom za mešanje
- **Rezultat:** ~200 grafova zamenjuje ~3000 tradicionalnih event→sound mapiranja
- **Audio dizajneri** su mogli da iteriraju na muzičkom sistemu BEZ programera

**Direktna primena na FluxForge SlotLab:**
- Jedan graf za "SPIN_SEQUENCE" — sadrži sve od anticipation zvuka do win celebration
- Podgrafovi za svaki win tier, feature type, bonus round
- Near-miss, scatter, wild — svaki ima graf koji upravlja celom audio sekvencom
- Audio dizajner menja graf, čuje rezultat, nema koda

---

## 3. Core Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     FluxForge Hook Graph System                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐    ┌───────────────┐    ┌──────────────────────┐ │
│  │ Event Source  │───→│ Hook Registry │───→│ Graph Resolver       │ │
│  │              │    │               │    │ (pattern matching,   │ │
│  │ - EventReg   │    │ - event→graph │    │  priority, wildcard) │ │
│  │ - Discovery  │    │ - wildcards   │    └──────────┬───────────┘ │
│  │ - RTPC       │    │ - priorities  │               │             │
│  │ - Timeline   │    └───────────────┘               ▼             │
│  └──────────────┘                        ┌──────────────────────┐ │
│                                          │ Graph Instance Pool  │ │
│                                          │ (pre-allocated,      │ │
│                                          │  recycled, pooled)   │ │
│                                          └──────────┬───────────┘ │
│                                                     │             │
│         ┌───────────────────────────────────────────┤             │
│         ▼                                           ▼             │
│  ┌──────────────┐                        ┌──────────────────────┐ │
│  │ Control-Rate │                        │ Audio-Rate Engine    │ │
│  │ Executor     │                        │ (Rust, SIMD)         │ │
│  │ (~60 Hz)     │                        │ (44100/48000 Hz)     │ │
│  │              │                        │                      │ │
│  │ - Conditions │    ┌──────────┐        │ - DSP Nodes          │ │
│  │ - Logic      │───→│ Command  │───→    │ - Buffer Processing  │ │
│  │ - Timing     │    │ Queue    │  FFI   │ - Voice Management   │ │
│  │ - RTPC       │    │ (lock-   │───→    │ - Mixing             │ │
│  │ - Containers │    │  free)   │        │ - Output             │ │
│  └──────────────┘    └──────────┘        └──────────────────────┘ │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Visual Graph Editor                        │  │
│  │  Canvas ←→ Node Widgets ←→ Connection Wires ←→ Graph Model   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                  Debug & Profile Overlay                      │  │
│  │  Live Wire Values │ Execution Heatmap │ Voice Monitor         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Dual-Engine Design

Kritična arhitekturalna odluka — dva executora:

1. **Control-Rate Executor (Dart, ~60 Hz):** Logički čvorovi, uslovi, tajming, RTPC kalkulacije, container selekcija. Ovo je "mozak" grafa — odlučuje ŠTA se dešava.

2. **Audio-Rate Engine (Rust, sample rate):** DSP čvorovi, buffer processing, voice management, mixing. Ovo je "mišić" grafa — izvršava audio operacije na audio thread-u.

Komunikacija između njih: **lock-free command queue** (`rtrb::RingBuffer`), identično postojećem FluxForge UI→Audio thread patternu.

---

## 4. Hook Registry

Hook Registry je centralna lookup tabela koja mapira evente na grafove.

```dart
class HookGraphRegistry {
  // Exact event → graph mapping
  final Map<String, List<HookGraphBinding>> _exactBindings = {};

  // Pattern-based bindings (wildcards, regex)
  final List<PatternBinding> _patternBindings = [];

  // Priority-sorted cache (invalidated on change)
  Map<String, List<ResolvedGraphBinding>>? _resolvedCache;

  // State group bindings
  final Map<String, Map<String, List<HookGraphBinding>>> _stateBindings = {};

  /// Register a graph for an event
  void bind({
    required String eventPattern,
    required HookGraphDefinition graph,
    int priority = 0,
    String? stateGroup,
    String? stateValue,
    bool exclusive = false,
  });

  /// Resolve all graphs that should execute for an event
  List<ResolvedGraphBinding> resolve(String eventId, {
    Map<String, String>? activeStates,
    Map<String, double>? rtpcValues,
  });

  /// Remove all bindings for a graph
  void unbind(String graphId);

  /// Snapshot for deterministic replay
  HookRegistrySnapshot snapshot();
}
```

### Binding Types

| Type | Pattern | Example | Use Case |
|------|---------|---------|----------|
| **Exact** | `"REEL_STOP"` | Tačno jedan event | Najčešći slučaj |
| **Wildcard** | `"REEL_*"` | Svi reel eventi | Grupna logika |
| **Regex** | `r"WIN_[1-5]"` | Win tier eventi | Flexible matching |
| **State-Scoped** | `"SPIN" @ BaseGame` | Event samo u base game | Context-aware |
| **Composite** | `"REEL_STOP + WIN_*"` | Kombinacija eventa | Complex triggers |

### Priority Resolution

```
Priority 1000: System graphs (hardcoded, cannot be overridden)
Priority 500:  Game-specific graphs (slot theme overrides)
Priority 100:  Default graphs (base behavior)
Priority 0:    Fallback graphs (catch-all)
Priority -100: Debug/preview graphs (lowest)
```

Kad se event desi, Registry vraća SORTIRANE grafove po prioritetu. Executor ih pokreće redom, uz mogućnost da graf označi event kao "consumed" (sprečava niže prioritete).

---

## 5. Hook Graph Structure

Graf je directed acyclic graph (DAG) sa typed portovima.

```dart
class HookGraphDefinition {
  final String id;
  final String name;
  final String? description;
  final int version;

  // Nodes
  final Map<String, GraphNode> nodes;

  // Connections (wire = output port → input port)
  final List<GraphConnection> connections;

  // Graph-level inputs (from event payload)
  final List<GraphPort> inputs;

  // Graph-level outputs (to voice engine)
  final List<GraphPort> outputs;

  // Subgraph references
  final Map<String, String> subgraphRefs; // nodeId → graphId

  // Metadata
  final GraphMetadata metadata;

  // Compile to optimized runtime representation
  CompiledGraph compile({required GraphCompilerOptions options});
}

class GraphConnection {
  final String sourceNodeId;
  final String sourcePortId;
  final String targetNodeId;
  final String targetPortId;

  // Optional: wire transform (type conversion, scaling)
  final WireTransform? transform;
}

class GraphPort {
  final String id;
  final String name;
  final PortType type;
  final PortDirection direction;
  final dynamic defaultValue;

  // Constraints
  final double? minValue;
  final double? maxValue;
  final List<String>? enumValues;
}

enum PortType {
  trigger,      // Bang/pulse — no data, just activation signal
  boolean,      // true/false
  integer,      // Whole numbers
  float,        // Decimal numbers (control rate)
  string,       // Text/identifiers
  audioBuffer,  // Float32 buffer (audio rate) — only in Rust nodes
  midiNote,     // MIDI note data
  eventPayload, // Arbitrary event data map
  graphRef,     // Reference to subgraph
  voiceHandle,  // Reference to active voice
  busHandle,    // Reference to audio bus
  curveData,    // Automation curve points
  any,          // Dynamic type (resolved at runtime)
}
```

### Graph Lifecycle

```
Definition → Compile → Instantiate → Execute → Recycle
     │           │          │           │          │
     │           │          │           │          └→ Return to pool
     │           │          │           └→ Process nodes topologically
     │           │          └→ Allocate from pool, bind event data
     │           └→ Topological sort, type check, optimize
     └→ Author in visual editor or code
```

---

## 6. Node Type System

### 6.1 Event Nodes (Ulaz u graf)

```dart
/// Entry point — receives event from Registry
class EventEntryNode extends GraphNode {
  // Outputs:
  // - trigger: Activation signal
  // - eventId: String
  // - payload: Map<String, dynamic>
  // - timestamp: int (microseconds)
}

/// Receives RTPC parameter changes
class RTPCInputNode extends GraphNode {
  final String parameterName;
  // Outputs:
  // - value: float (current parameter value)
  // - delta: float (change since last frame)
  // - velocity: float (rate of change)
}

/// Listens for state group changes
class StateInputNode extends GraphNode {
  final String stateGroup;
  // Outputs:
  // - currentState: String
  // - previousState: String
  // - changeTrigger: trigger
}

/// Timeline position input
class TimelineInputNode extends GraphNode {
  // Outputs:
  // - position: float (seconds)
  // - beat: int
  // - bar: int
  // - tempo: float (BPM)
  // - playing: bool
}
```

### 6.2 Condition Nodes

```dart
/// Compare two values
class CompareNode extends GraphNode {
  final CompareOp operator; // ==, !=, <, >, <=, >=
  // Inputs: a (any), b (any)
  // Outputs: result (bool), trueOut (trigger), falseOut (trigger)
}

/// Range check
class RangeNode extends GraphNode {
  // Inputs: value (float), min (float), max (float)
  // Outputs: inRange (bool), normalized (float 0..1), trigger (trigger)
}

/// Pattern match on string/enum
class MatchNode extends GraphNode {
  final Map<String, String> cases; // pattern → output port name
  // Inputs: value (string)
  // Outputs: dynamic ports per case + default (trigger)
}

/// Payload field extractor
class PayloadExtractNode extends GraphNode {
  final String fieldPath; // e.g., "winData.tier" — dot notation
  // Inputs: payload (eventPayload)
  // Outputs: value (any), exists (bool)
}

/// Multi-condition gate — all conditions must be true
class AllOfNode extends GraphNode {
  final int inputCount;
  // Inputs: condition_0..N (bool)
  // Outputs: result (bool), trigger (trigger)
}

/// Any condition gate
class AnyOfNode extends GraphNode {
  final int inputCount;
  // Inputs: condition_0..N (bool)
  // Outputs: result (bool), matchCount (int), trigger (trigger)
}
```

### 6.3 Logic Nodes

```dart
/// Boolean logic
class BoolLogicNode extends GraphNode {
  final BoolOp op; // AND, OR, NOT, XOR, NAND, NOR
  // Inputs: a (bool), b (bool) — NOT uses only a
  // Outputs: result (bool)
}

/// N-way switch (Wwise Switch Container equivalent)
class SwitchNode extends GraphNode {
  final List<String> cases;
  final String? defaultCase;
  // Inputs: selector (string or int)
  // Outputs: one trigger port per case
}

/// Weighted probability selector (Wwise Random Container equivalent)
class ProbabilityNode extends GraphNode {
  final List<WeightedOption> options;
  final bool avoidRepeat;        // Don't repeat last N selections
  final int avoidRepeatCount;    // How many to remember
  // Inputs: trigger (trigger), seed (int, optional)
  // Outputs: one trigger port per option + selectedIndex (int)
}

/// Sequence stepper (Wwise Sequence Container equivalent)
class SequenceNode extends GraphNode {
  final int stepCount;
  final SequenceMode mode; // forward, reverse, pingPong, random
  final bool resetOnEvent; // Reset to step 0 on specific event
  // Inputs: advance (trigger), reset (trigger)
  // Outputs: one trigger port per step + currentStep (int)
}

/// Blend/crossfade by parameter (Wwise Blend Container equivalent)
class BlendNode extends GraphNode {
  final int inputCount;
  final List<BlendPoint> blendPoints; // parameter value → weight curves
  // Inputs: parameter (float), audio_0..N (audioBuffer)
  // Outputs: blended (audioBuffer)
}

/// Cooldown — suppress repeated triggers
class CooldownNode extends GraphNode {
  // Inputs: trigger (trigger), cooldownTime (float, seconds)
  // Outputs: passed (trigger), blocked (trigger), remaining (float)
  // State: lastTriggerTime
}

/// Gate — pass or block based on condition
class GateNode extends GraphNode {
  // Inputs: input (trigger), open (bool)
  // Outputs: output (trigger), blocked (trigger)
}

/// Counter — count triggers, fire on threshold
class CounterNode extends GraphNode {
  final int threshold;
  final bool autoReset;
  // Inputs: increment (trigger), reset (trigger)
  // Outputs: count (int), thresholdReached (trigger)
}

/// Latch — remembers value until reset
class LatchNode extends GraphNode {
  // Inputs: set (trigger), reset (trigger), value (any)
  // Outputs: stored (any), isSet (bool)
}

/// Debounce — only fire after input stops for duration
class DebounceNode extends GraphNode {
  // Inputs: trigger (trigger), duration (float)
  // Outputs: debounced (trigger)
}
```

### 6.4 Timing Nodes

```dart
/// Delay trigger by duration
class DelayNode extends GraphNode {
  // Inputs: trigger (trigger), delay (float, seconds)
  // Outputs: delayed (trigger), cancel (trigger)
}

/// Fire trigger at interval
class MetronomeNode extends GraphNode {
  // Inputs: start (trigger), stop (trigger), interval (float),
  //         syncToTempo (bool), subdivisions (int)
  // Outputs: tick (trigger), tickCount (int)
}

/// Envelope generator (ADSR)
class EnvelopeNode extends GraphNode {
  // Inputs: noteOn (trigger), noteOff (trigger),
  //         attack (float), decay (float), sustain (float), release (float)
  // Outputs: value (float 0..1), phase (string), done (trigger)
}

/// Timeline scheduler — fire triggers at absolute times
class TimelineNode extends GraphNode {
  final List<TimelineCue> cues; // time → trigger port mapping
  // Inputs: start (trigger), stop (trigger), position (float)
  // Outputs: dynamic ports per cue + currentPosition (float)
}

/// Ramp/interpolate between values over time
class RampNode extends GraphNode {
  final CurveType curve; // linear, easeIn, easeOut, easeInOut, custom
  // Inputs: start (trigger), startValue (float), endValue (float),
  //         duration (float)
  // Outputs: value (float), progress (float 0..1), done (trigger)
}

/// Wait for multiple triggers (join/sync point)
class BarrierNode extends GraphNode {
  final int inputCount;
  final BarrierMode mode; // all (AND), any (OR), count (N of M)
  final int? requiredCount;
  // Inputs: trigger_0..N (trigger)
  // Outputs: complete (trigger), receivedCount (int)
}
```

### 6.5 Audio Nodes

```dart
/// Play a sound asset
class PlaySoundNode extends GraphNode {
  // Inputs: trigger (trigger), asset (string),
  //         volume (float), pitch (float), pan (float),
  //         bus (busHandle), priority (int),
  //         loop (bool), loopCount (int),
  //         startPosition (float), fadeIn (float)
  // Outputs: voice (voiceHandle), started (trigger),
  //          ended (trigger), position (float)
}

/// Stop a playing voice
class StopSoundNode extends GraphNode {
  // Inputs: voice (voiceHandle), fadeOut (float),
  //         stopMode (enum: immediate, fadeOut, endOfLoop)
  // Outputs: stopped (trigger)
}

/// Pause/resume
class PauseSoundNode extends GraphNode {
  // Inputs: voice (voiceHandle), pause (bool), fadeTime (float)
  // Outputs: paused (trigger), resumed (trigger)
}

/// Set voice parameter
class SetVoiceParamNode extends GraphNode {
  final VoiceParam param; // volume, pitch, pan, lowpass, highpass
  // Inputs: voice (voiceHandle), value (float),
  //         interpolationTime (float), curve (curveData)
  // Outputs: done (trigger)
}

/// Crossfade between two voices
class CrossfadeNode extends GraphNode {
  // Inputs: voiceA (voiceHandle), voiceB (voiceHandle),
  //         mix (float 0..1), duration (float), curve (curveData)
  // Outputs: done (trigger)
}

/// Programmer Instrument (FMOD-inspired)
/// Runtime callback decides the sound asset
class DynamicSoundNode extends GraphNode {
  // Inputs: trigger (trigger), context (eventPayload)
  // Outputs: requestAsset (trigger), asset (string) ← filled by callback
  // Callback: onAssetRequest(context) → assetPath
}
```

### 6.6 DSP Nodes (Audio-Rate, Rust)

```dart
/// Biquad filter (TDF-II implementation)
class FilterNode extends GraphNode {
  final FilterType type; // lowpass, highpass, bandpass, notch, peak, shelf
  // Inputs: audio (audioBuffer), cutoff (float), resonance (float),
  //         gain (float, for peak/shelf only)
  // Outputs: audio (audioBuffer)
  // Implementation: Rust, SIMD-optimized, zero allocation
}

/// Gain/volume with optional automation
class GainNode extends GraphNode {
  // Inputs: audio (audioBuffer), gain (float dB),
  //         automation (curveData)
  // Outputs: audio (audioBuffer), peak (float), rms (float)
}

/// Stereo panner
class PanNode extends GraphNode {
  final PanLaw panLaw; // linear, squareRoot, sinCos
  // Inputs: audio (audioBuffer), pan (float -1..1)
  // Outputs: audioL (audioBuffer), audioR (audioBuffer)
}

/// Delay effect
class AudioDelayNode extends GraphNode {
  // Inputs: audio (audioBuffer), delayTime (float ms),
  //         feedback (float 0..1), mix (float 0..1)
  // Outputs: audio (audioBuffer)
  // Pre-allocated circular buffer in Rust
}

/// Compressor/limiter
class CompressorNode extends GraphNode {
  // Inputs: audio (audioBuffer), threshold (float dB),
  //         ratio (float), attack (float ms), release (float ms),
  //         makeupGain (float dB)
  // Outputs: audio (audioBuffer), gainReduction (float)
}

/// Mixer — sum multiple audio inputs
class MixerNode extends GraphNode {
  final int inputCount;
  // Inputs: audio_0..N (audioBuffer), gain_0..N (float)
  // Outputs: mixed (audioBuffer), peak (float)
}

/// Send to bus
class BusSendNode extends GraphNode {
  // Inputs: audio (audioBuffer), bus (busHandle),
  //         sendLevel (float), pre (bool)
  // Outputs: sent (trigger)
}
```

### 6.7 Control Nodes

```dart
/// Subgraph — encapsulated graph as a single node
class SubgraphNode extends GraphNode {
  final String graphId; // Reference to another HookGraphDefinition
  // Inputs/Outputs: mirrors the referenced graph's inputs/outputs
}

/// Variable storage — read/write named variables within graph
class VariableNode extends GraphNode {
  final String variableName;
  final PortType variableType;
  // Inputs: set (trigger), value (any)
  // Outputs: value (any), changed (trigger)
}

/// Event emitter — fire a new event from within graph
class EmitEventNode extends GraphNode {
  // Inputs: trigger (trigger), eventId (string),
  //         payload (eventPayload)
  // Outputs: emitted (trigger)
  // WARNING: Can cause recursion — max depth enforced
}

/// Comment/annotation (no execution)
class CommentNode extends GraphNode {
  final String text;
  final Color color;
  // No inputs or outputs — visual only
}

/// Group box (visual organization)
class GroupNode extends GraphNode {
  final String label;
  final Color color;
  final List<String> containedNodeIds;
  // No inputs or outputs — visual only
}

/// Log/debug output (development only)
class DebugLogNode extends GraphNode {
  final String format;
  // Inputs: value (any), trigger (trigger)
  // Outputs: passthrough (any)
  // Shows value in debug overlay, NOT in console (per CLAUDE.md rule)
}
```

### 6.8 Layer Control Nodes

```dart
/// Start a music/ambience layer
class LayerStartNode extends GraphNode {
  // Inputs: trigger (trigger), layerName (string),
  //         fadeIn (float, seconds), volume (float dB)
  // Outputs: started (trigger), layerHandle (string)
}

/// Stop a music/ambience layer
class LayerStopNode extends GraphNode {
  // Inputs: trigger (trigger), layerName (string),
  //         fadeOut (float, seconds)
  // Outputs: stopped (trigger)
}

/// Fade a layer in/out without starting/stopping
class LayerFadeNode extends GraphNode {
  // Inputs: trigger (trigger), layerName (string),
  //         targetVolume (float dB), fadeTime (float, seconds),
  //         curve (curveData)
  // Outputs: done (trigger), currentVolume (float)
}

/// Blend between two layers based on parameter
class LayerBlendNode extends GraphNode {
  // Inputs: layerA (string), layerB (string),
  //         blendParam (float 0..1), blendTime (float, seconds),
  //         curve (curveData)
  // Outputs: done (trigger)
  // Example: blend between BaseLayer and IntensityLayer based on Excitement RTPC
}

/// Switch active layer set based on game state
class LayerSwitchNode extends GraphNode {
  final Map<String, List<String>> stateLayers; // state → active layers
  // Inputs: state (string), transitionTime (float, seconds)
  // Outputs: switched (trigger), previousState (string)
  // Auto-fades out previous state layers, fades in new ones
}

/// Duck other layers when this node is triggered
class DuckNode extends GraphNode {
  // Inputs: trigger (trigger), release (trigger),
  //         targetLayers (string list), duckAmount (float dB),
  //         attackTime (float ms), releaseTime (float ms),
  //         curve (curveData)
  // Outputs: ducking (bool), currentReduction (float dB)
  // Example: BigWin triggers → duck BaseMusic by -12dB
}

/// Sidechain compression — duck by audio input level
class SidechainNode extends GraphNode {
  // Inputs: audio (audioBuffer), sidechain (audioBuffer),
  //         threshold (float dB), ratio (float),
  //         attack (float ms), release (float ms)
  // Outputs: audio (audioBuffer), gainReduction (float)
  // Example: win celebration audio sidechains base music
}
```

### 6.9 Extended Audio Action Nodes

```dart
/// Seek to position in playing voice
class SeekNode extends GraphNode {
  // Inputs: voice (voiceHandle), position (float, seconds),
  //         mode (enum: absolute, relative, percentage),
  //         snapToZeroCrossing (bool)
  // Outputs: seeked (trigger), actualPosition (float)
}

/// Restart playback from beginning
class RestartNode extends GraphNode {
  // Inputs: voice (voiceHandle), fadeOut (float, seconds),
  //         fadeIn (float, seconds), delay (float, seconds)
  // Outputs: restarted (trigger)
  // Handles fade out → seek to 0 → fade in atomically
}

/// Multi-sound player — trigger multiple sounds simultaneously
class MultiPlayNode extends GraphNode {
  final int soundCount;
  // Inputs: trigger (trigger), asset_0..N (string),
  //         volume_0..N (float), delay_0..N (float),
  //         bus (busHandle)
  // Outputs: voices (voiceHandle list), allStarted (trigger),
  //          allEnded (trigger)
  // Useful for layered sound design (attack + body + tail)
}
```

### 6.10 State & Memory Nodes

```dart
/// Persistent state store — survives across graph executions
class StateStoreNode extends GraphNode {
  final String storeId; // Global store identifier
  final String key;
  // Inputs: set (trigger), value (any), clear (trigger)
  // Outputs: value (any), exists (bool), changed (trigger)
  // Unlike VariableNode: persists across graph instances
  // Use case: "remember last win tier for next spin's audio"
}

/// Session accumulator — accumulate values across session
class AccumulatorNode extends GraphNode {
  final String accumulatorId;
  // Inputs: add (trigger), value (float), reset (trigger)
  // Outputs: total (float), count (int), average (float),
  //          min (float), max (float)
  // Use case: track total session wins to drive excitement RTPC
}

/// Event history query — check what happened recently
class EventHistoryNode extends GraphNode {
  final String eventPattern;
  final Duration lookbackWindow;
  // Inputs: query (trigger)
  // Outputs: count (int), lastTimestamp (int),
  //          timeSinceLast (float), payloads (list)
  // Use case: "how many wins in last 30 seconds?" → drives audio intensity
}
```

### 6.11 Analytics & Emotion Nodes (FluxForge Unique)

```dart
/// Volatility analyzer — measures gameplay intensity over time
class VolatilityAnalyzerNode extends GraphNode {
  final Duration windowSize; // Analysis window (e.g., 60s)
  // Inputs: winAmount (float), betAmount (float),
  //         spinTrigger (trigger)
  // Outputs: volatility (float 0..1), trend (float -1..1),
  //          winRate (float 0..1), avgMultiplier (float),
  //          hotStreak (bool), coldStreak (bool)
  // Drives ambient music intensity, sound effect density
}

/// Excitement mapper — composite emotional state
class ExcitementMapperNode extends GraphNode {
  // Inputs: winTier (int), nearMiss (bool), featureActive (bool),
  //         consecutiveWins (int), rollupProgress (float),
  //         anticipationLevel (float), volatility (float)
  // Outputs: excitement (float 0..1), mood (string),
  //          intensityTarget (float), shouldEscalate (bool)
  // Weighted formula combines all inputs into single "excitement" metric
  // mood: "calm", "building", "excited", "euphoric", "cooling"
}

/// Player behavior detector — adapts audio to play patterns
class PlayerBehaviorNode extends GraphNode {
  // Inputs: spinTrigger (trigger), betChange (float),
  //         autoplayActive (bool), sessionDuration (float)
  // Outputs: playStyle (string), engagement (float 0..1),
  //          isCasual (bool), isHighRoller (bool),
  //          fatigueLevel (float 0..1)
  // playStyle: "explorer", "grinder", "high_roller", "casual"
  // fatigueLevel: increases over long sessions → can reduce audio intensity
}

/// Big win intensity controller — orchestrates escalating celebration
class BigWinOrchestratorNode extends GraphNode {
  // Inputs: winTier (int), winAmount (float), betAmount (float),
  //         trigger (trigger)
  // Outputs: phase (string), phaseProgress (float 0..1),
  //          phaseTrigger (trigger), intensity (float),
  //          layerTargets (list), dspTargets (list)
  // Phases: "intro" → "buildup" → "peak" → "celebration" → "cooldown"
  // Orchestrates multiple layers, DSP, and sound effects
  // Duration scales with win tier
}
```

### 6.12 Slot-Specific Nodes (FluxForge Unique)

```dart
/// Win tier resolver — maps win amount to tier
class WinTierNode extends GraphNode {
  // Inputs: winAmount (float), betAmount (float),
  //         payload (eventPayload)
  // Outputs: tier (string), tierIndex (int), multiplier (float),
  //          isJackpot (bool), isBigWin (bool)
  // Uses WinTierConfig — NEVER hardcoded thresholds
}

/// Reel analyzer — extract reel-specific data
class ReelAnalyzerNode extends GraphNode {
  // Inputs: payload (eventPayload), reelIndex (int)
  // Outputs: symbols (string list), isWild (bool), isScatter (bool),
  //          stopPosition (int), spinDuration (float),
  //          isNearMiss (bool), nearMissDistance (int)
}

/// Feature state tracker
class FeatureStateNode extends GraphNode {
  // Inputs: payload (eventPayload)
  // Outputs: currentFeature (string), isBaseGame (bool),
  //          isFreeSpins (bool), isBonus (bool), isPick (bool),
  //          freeSpinsRemaining (int), totalWin (float),
  //          featureDepth (int) // nested features
}

/// Anticipation calculator — drives suspense audio
class AnticipationNode extends GraphNode {
  // Inputs: reelsLanded (int), totalReels (int),
  //         scatterCount (int), requiredScatters (int),
  //         wildCount (int)
  // Outputs: anticipationLevel (float 0..1),
  //          isActive (bool), trigger (trigger),
  //          anticipationType (string) // scatter, wild, bonus
}

/// Rollup controller — manages win count-up audio
class RollupNode extends GraphNode {
  // Inputs: startAmount (float), endAmount (float),
  //         duration (float), trigger (trigger)
  // Outputs: currentAmount (float), progress (float 0..1),
  //          tick (trigger), // per increment
  //          halfway (trigger), almostDone (trigger),
  //          done (trigger)
}

/// Symbol match detector
class SymbolMatchNode extends GraphNode {
  // Inputs: payload (eventPayload)
  // Outputs: matchCount (int), matchSymbol (string),
  //          paylineIndex (int), isFullLine (bool),
  //          matchPositions (list), trigger (trigger)
}
```

---

## 7. Dual-Rate Graph Execution

Inspirisano MetaSounds-om — graf se ne izvršava uniformno. Različiti čvorovi rade na različitim frekvencijama.

### Control Rate (~60 Hz, Dart)

Logički čvorovi, uslovi, RTPC, tajming, kontejner selekcija. Ovo radi na UI thread-u (ili dedicated isolate).

```dart
class ControlRateExecutor {
  static const double controlRateHz = 60.0;
  static const Duration controlPeriod = Duration(microseconds: 16667); // ~60Hz

  final Map<String, GraphInstance> _activeGraphs = {};
  final CommandQueue _audioCommandQueue; // → Rust audio thread

  void tick() {
    final now = DateTime.now().microsecondsSinceEpoch;

    for (final graph in _activeGraphs.values) {
      // Topological order — pre-computed at compile time
      for (final nodeId in graph.compiledOrder) {
        final node = graph.nodes[nodeId]!;

        if (node.isAudioRate) continue; // Skip — handled by Rust

        if (node.needsUpdate(now)) {
          node.process(graph.connectionState);

          // If node produced audio commands, queue them
          for (final cmd in node.pendingCommands) {
            _audioCommandQueue.push(cmd);
          }
          node.pendingCommands.clear();
        }
      }
    }
  }
}
```

### Audio Rate (Sample Rate, Rust)

DSP čvorovi, buffer processing, voice mixing. Ovo radi na audio thread-u — **NEMA alokacija, NEMA lock-ova**.

```rust
/// Audio-rate graph processor — runs on audio thread
pub struct AudioRateProcessor {
    /// Pre-allocated node processors
    nodes: Vec<Box<dyn AudioNode>>,
    /// Topological execution order (computed once at compile)
    execution_order: Vec<usize>,
    /// Pre-allocated connection buffers
    wire_buffers: Vec<AudioBuffer>,
    /// Command receiver from control-rate
    command_rx: rtrb::Consumer<GraphCommand>,
}

impl AudioRateProcessor {
    /// Called per audio buffer — MUST be real-time safe
    pub fn process(&mut self, buffer_size: usize) {
        // Drain commands from control rate (non-blocking)
        while let Ok(cmd) = self.command_rx.pop() {
            self.apply_command(cmd);
        }

        // Process nodes in topological order
        for &node_idx in &self.execution_order {
            // SAFETY: indices are validated at compile time
            unsafe {
                self.nodes.get_unchecked_mut(node_idx)
                    .process(&mut self.wire_buffers, buffer_size);
            }
        }
    }

    fn apply_command(&mut self, cmd: GraphCommand) {
        match cmd {
            GraphCommand::StartVoice { node_idx, asset_id, params } => {
                self.nodes[node_idx].start_voice(asset_id, params);
            }
            GraphCommand::SetParam { node_idx, param, value, interp_samples } => {
                self.nodes[node_idx].set_param(param, value, interp_samples);
            }
            GraphCommand::StopVoice { node_idx, fade_samples } => {
                self.nodes[node_idx].stop_voice(fade_samples);
            }
            GraphCommand::StopGraph => {
                for node in &mut self.nodes {
                    node.stop_all();
                }
            }
        }
    }
}

/// Trait for audio-rate nodes — ALL methods must be RT-safe
pub trait AudioNode: Send {
    fn process(&mut self, buffers: &mut [AudioBuffer], buffer_size: usize);
    fn start_voice(&mut self, _asset_id: u32, _params: VoiceParams) {}
    fn stop_voice(&mut self, _fade_samples: u32) {}
    fn stop_all(&mut self) {}
    fn set_param(&mut self, _param: u32, _value: f32, _interp_samples: u32) {}
    fn reset(&mut self);
}
```

### Cross-Rate Communication

```
Control Rate (Dart, 60 Hz)          Audio Rate (Rust, 44100 Hz)
         │                                      │
         │   ┌──────────────────────┐           │
         ├──→│ Command Queue (SPSC) │──→────────┤
         │   │ rtrb::RingBuffer     │           │
         │   └──────────────────────┘           │
         │                                      │
         │   ┌──────────────────────┐           │
         ├──←│ Feedback Queue (SPSC)│←──────────┤
         │   │ Peak, RMS, position  │           │
         │   └──────────────────────┘           │
         │                                      │
```

---

## 8. Compiled Graph Runtime

Grafovi se NE interpretiraju u runtime-u. Kompajliraju se u optimizovanu reprezentaciju.

```dart
class GraphCompiler {
  CompiledGraph compile(HookGraphDefinition definition) {
    // 1. Validate — type checking, cycle detection, port compatibility
    final errors = _validate(definition);
    if (errors.isNotEmpty) throw GraphCompileError(errors);

    // 2. Topological sort — determine execution order
    final order = _topologicalSort(definition.nodes, definition.connections);

    // 3. Separate control-rate and audio-rate nodes
    final controlNodes = order.where((id) => !definition.nodes[id]!.isAudioRate);
    final audioNodes = order.where((id) => definition.nodes[id]!.isAudioRate);

    // 4. Allocate wire indices — replace string IDs with integers
    final wireMap = _allocateWireIndices(definition.connections);

    // 5. Dead node elimination — remove unreachable nodes
    final reachable = _findReachable(definition);

    // 6. Constant folding — pre-compute constant subgraphs
    final constants = _foldConstants(definition, reachable);

    // 7. Subgraph inlining — inline small subgraphs
    final inlined = _inlineSubgraphs(definition, reachable);

    // 8. Generate compiled representation
    return CompiledGraph(
      controlOrder: controlNodes.where(reachable.contains).toList(),
      audioOrder: audioNodes.where(reachable.contains).toList(),
      wireMap: wireMap,
      constants: constants,
      nodeData: _serializeNodes(definition, wireMap),
      estimatedVoiceCount: _estimateVoices(definition),
      estimatedBufferCount: _estimateBuffers(definition),
    );
  }
}

class CompiledGraph {
  final List<String> controlOrder;  // Topological order for control-rate
  final List<String> audioOrder;    // Topological order for audio-rate
  final Map<String, int> wireMap;   // Connection ID → buffer index
  final Map<String, dynamic> constants; // Pre-computed values
  final Uint8List nodeData;         // Serialized node configurations
  final int estimatedVoiceCount;    // For pool pre-allocation
  final int estimatedBufferCount;   // For buffer pre-allocation

  /// Serialize for Rust FFI
  Uint8List toRustFormat() {
    // MessagePack serialization for wire protocol
    // (see AUTOMATIC_EVENT_DISCOVERY_SYSTEM.md Section 25)
  }
}
```

### Compiler Optimizations

| Optimization | Description | Benefit |
|-------------|-------------|---------|
| **Dead Node Elimination** | Remove nodes with no path to output | Less processing |
| **Constant Folding** | Pre-compute nodes with constant inputs | Zero runtime cost |
| **Subgraph Inlining** | Inline small subgraphs (< 10 nodes) | No indirection overhead |
| **Wire Index Mapping** | Replace string IDs with integer indices | O(1) lookup |
| **Topological Caching** | Execution order computed once | No runtime sorting |
| **Voice Estimation** | Pre-size voice pool per graph | No runtime allocation |
| **Buffer Pre-allocation** | Allocate all wire buffers upfront | Zero audio-thread alloc |

---

## 9. Priority & Conflict Resolution

### Graph Priority Levels

```dart
enum GraphPriorityLevel {
  system(1000),      // Engine-critical (safety, regulatory)
  themeOverride(750), // Game theme customization
  feature(500),       // Feature-specific behavior
  base(100),          // Default behavior
  fallback(0),        // Catch-all
  debug(-100),        // Debug/preview (stripped in release)
}
```

### Conflict Resolution Modes

```dart
enum ConflictMode {
  /// All matching graphs execute (default)
  stackAll,

  /// Only highest priority executes
  exclusiveHighest,

  /// Highest priority can "consume" event, stopping propagation
  consumable,

  /// Blend results from all graphs by priority weight
  blendByPriority,

  /// First graph that produces audio output wins
  firstOutput,
}
```

### Voice Stealing

Kad se premašuje `maxVoices` limit:

```dart
class VoiceStealingPolicy {
  final int maxVoices;
  final StealMode mode;

  // Steal by:
  // - oldest: najstariji glas se gasi
  // - quietest: najtiši glas se gasi
  // - lowestPriority: najniži prioritet se gasi
  // - farthest: (za 3D audio) najdalji od listenera
  // - none: ne krade — novi zvuk se ne pušta
}
```

---

## 10. Graph Composition & Inheritance

### Subgraph Pattern

Grafovi mogu sadržati druge grafove kao čvorove — identično funkcijama u programiranju.

```
Master Graph: "SpinSequence"
├── [EventEntry: SPIN_START]
│       │
│       ├──→ [Subgraph: "ReelSpinAudio"]
│       │       ├── [PlaySound: reel_loop]
│       │       ├── [RTPC: SpinProgress → pitch]
│       │       └── [StopSound on REEL_STOP]
│       │
│       ├──→ [Subgraph: "AnticipationAudio"]
│       │       ├── [AnticipationNode]
│       │       ├── [Ramp: suspense_level]
│       │       └── [PlaySound: anticipation_swell]
│       │
│       └──→ [Subgraph: "WinEvaluation"]
│               ├── [WinTierNode]
│               ├── [Switch: tier → win_graph]
│               └── [Subgraph refs: "SmallWin", "BigWin", "MegaWin"]
```

### Graph Inheritance

Teme (slot game themes) mogu naslediti bazni graf i override-ovati specifične čvorove:

```dart
class GraphInheritance {
  final String baseGraphId;
  final Map<String, GraphNode> overriddenNodes;
  final List<GraphConnection> additionalConnections;
  final List<String> removedConnections;

  // Effective graph = base + overrides - removals + additions
}
```

**Primer:**
- Base graf: "GenericSlotSpin" — standardna spin sekvenca
- Theme override: "EgyptianSlotSpin" — isti flow, ali zamenjeni zvuci sa egyptian temom, dodat reverb na win sounds

### Composition Rules

1. **Subgraf izolacija:** Subgraf nema pristup parent varijablama osim eksplicitno prosleđenih inputa
2. **Max dubina:** 8 nivoa nestovanja (sprečava infinite recursion)
3. **Circular reference detection:** Kompajler detektuje i odbija cirkularne reference
4. **Port compatibility:** Subgraf portovi moraju type-match sa parent konexijama

---

## 11. Wildcard & Pattern Matching Events

### Pattern Syntax

```
"REEL_*"           → Matches REEL_START, REEL_STOP, REEL_SPIN, etc.
"WIN_[1-5]"        → Matches WIN_1 through WIN_5
"*_STOP"           → Matches REEL_STOP, SPIN_STOP, FEATURE_STOP
"FEATURE_**"       → Deep match: FEATURE_FREESPIN, FEATURE_BONUS_START, etc.
"!REEL_*"          → Negation: everything EXCEPT REEL_* events
"{SPIN,REEL}_*"    → Alternation: SPIN_* or REEL_*
```

### Pattern Priority

Specifičniji pattern ima viši implicitni prioritet:

```
"REEL_STOP"        → Specificity: 100 (exact match)
"REEL_*"           → Specificity: 50  (single wildcard)
"*_STOP"           → Specificity: 50  (single wildcard)
"*"                → Specificity: 0   (catch-all)
```

### Composite Event Patterns

```dart
/// Fire graph when multiple events occur within a time window
class CompositeEventPattern {
  final List<String> requiredEvents;
  final Duration timeWindow;
  final bool ordered; // Must occur in sequence?

  // Example: "REEL_STOP" + "WIN_EVAL" within 500ms → triggers "WinCelebration" graph
}
```

---

## 12. Dynamic Runtime Binding

Grafovi mogu biti bound i unbound u runtime — npr. kad se menja slot igra ili ulazi u feature.

```dart
class DynamicBinding {
  /// Bind graph on state change
  void onStateChange(String stateGroup, String newState) {
    // Unbind previous state's graphs
    final previous = _stateBindings[stateGroup];
    if (previous != null) {
      for (final binding in previous) {
        _registry.unbind(binding.graphId);
      }
    }

    // Bind new state's graphs
    final newBindings = _stateGraphs[stateGroup]?[newState] ?? [];
    for (final binding in newBindings) {
      _registry.bind(
        eventPattern: binding.eventPattern,
        graph: binding.graph,
        priority: binding.priority,
      );
    }

    _stateBindings[stateGroup] = newBindings;
  }

  /// Hot-reload graph definition (development only)
  void hotReload(String graphId, HookGraphDefinition newDefinition) {
    // 1. Compile new graph
    final compiled = _compiler.compile(newDefinition);

    // 2. Replace in all active instances (graceful — finish current, start new)
    for (final instance in _activeInstances[graphId] ?? []) {
      instance.scheduleReplacement(compiled);
    }

    // 3. Update registry
    _registry.updateGraph(graphId, newDefinition);
  }
}
```

### Game Session Lifecycle

```
Game Load → Load theme graphs → Bind base game events
         → Enter Free Spins → Unbind base, bind free spin graphs
         → Return to Base   → Unbind free spin, rebind base
         → Enter Bonus      → Bind bonus overlay graphs (stack with base)
         → Game Unload      → Unbind all, return graphs to pool
```

---

## 13. Layered Audio Control

Inspirisano Wwise State Groups — globalni audio layeri koji modifikuju sve aktivne grafove.

```dart
class AudioLayerSystem {
  // Active layers with blend weights
  final Map<String, AudioLayer> _activeLayers = {};

  void setLayer(String layerName, {
    required double volume,        // dB
    required double lowpassCutoff, // Hz
    required double highpassCutoff,// Hz
    required Duration fadeTime,
    required CurveType fadeCurve,
  });

  void clearLayer(String layerName, {Duration fadeTime = Duration.zero});
}

// Predefined layers for slot games:
const kLayerBase = 'BASE';           // Normal gameplay
const kLayerFreeSpins = 'FREESPINS'; // Feature mode — maybe more reverb
const kLayerBigWin = 'BIGWIN';       // Everything ducks except win sounds
const kLayerAutoplay = 'AUTOPLAY';   // Reduced audio for autoplay mode
const kLayerMuted = 'MUTED';         // Volume layer (user mute toggle)
const kLayerLobby = 'LOBBY';         // Background ambient when not playing
```

### Layer Application

Layeri se primenjuju kao post-processing na graf output:

```
Graph Output → [Layer: BASE vol=-3dB] → [Layer: BIGWIN duck=-12dB] → Final Mix
```

---

## 14. Randomization, Probability & Weighted Selection

### Weighted Random (Wwise Random Container Parity)

```dart
class WeightedRandomEngine {
  final List<WeightedOption> options;
  final int? seed; // For deterministic mode
  final RepeatAvoidance? avoidance;

  late final Random _rng;
  final Queue<int> _history = Queue();

  int select() {
    // Build cumulative weights, excluding avoided items
    final available = _getAvailableOptions();
    final totalWeight = available.fold<double>(0, (sum, o) => sum + o.weight);

    final roll = _rng.nextDouble() * totalWeight;
    double cumulative = 0;
    for (final option in available) {
      cumulative += option.weight;
      if (roll <= cumulative) {
        _updateHistory(option.index);
        return option.index;
      }
    }
    return available.last.index; // Floating point safety
  }
}

class RepeatAvoidance {
  final int historySize;    // Remember last N selections
  final AvoidanceMode mode;
  // - strict: never repeat within history
  // - weightReduction: reduce weight by factor for recent items
  // - shuffle: pre-shuffle, guarantee all play before repeat
}
```

### Weighted Selection UI

Vizuelni editor prikazuje bar chart sa težinama — audio dizajner drag-uje barove:

```
Sound A: ████████████████████ 40%
Sound B: ████████████         25%
Sound C: ████████████         25%
Sound D: █████                10%
```

---

## 15. Cooldown, Rate Limiting & Gate Logic

### Cooldown System

```dart
class CooldownSystem {
  final Map<String, CooldownState> _cooldowns = {};

  bool canTrigger(String cooldownId, Duration cooldownTime) {
    final state = _cooldowns[cooldownId];
    if (state == null) return true;
    return DateTime.now().difference(state.lastTrigger) >= cooldownTime;
  }

  void trigger(String cooldownId) {
    _cooldowns[cooldownId] = CooldownState(lastTrigger: DateTime.now());
  }
}
```

### Gate Patterns

```
┌──────────────────────────────────────────────────────┐
│ Pattern: "One-Shot Per Spin"                         │
│                                                      │
│ [SPIN_START] → [Gate: open=true] → ... audio ...     │
│                       ↑                              │
│ [SPIN_END]   → [Gate: close]                         │
│ [... audio end ...] → [Gate: close]                  │
│                                                      │
│ Result: Audio plays only on first trigger per spin   │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│ Pattern: "Escalating Repeats"                        │
│                                                      │
│ [WIN_EVAL] → [Counter] → [Switch: count]             │
│                              ├── 1: small celebration │
│                              ├── 2: medium            │
│                              ├── 3+: big celebration  │
│              [SPIN_START] → [Counter: reset]          │
│                                                      │
│ Result: Consecutive wins get louder celebrations     │
└──────────────────────────────────────────────────────┘
```

---

## 16. RTPC (Real-Time Parameter Control)

Inspirisano Wwise Game Parameters i FMOD Parameter Sheets.

```dart
class RTPCManager {
  final Map<String, RTPCParameter> _parameters = {};
  final Map<String, List<RTPCBinding>> _bindings = {};

  /// Define a parameter
  void define(String name, {
    required double min,
    required double max,
    required double defaultValue,
    RTPCInterpolation interpolation = RTPCInterpolation.linear,
    Duration smoothingTime = Duration.zero,
  });

  /// Set parameter value (from game logic)
  void setValue(String name, double value) {
    final param = _parameters[name]!;
    param.targetValue = value.clamp(param.min, param.max);

    // Notify all bound graph nodes
    for (final binding in _bindings[name] ?? []) {
      binding.onValueChanged(param.currentValue);
    }
  }

  /// Bind parameter to graph node property
  void bind(String paramName, String graphId, String nodeId, String property, {
    CurveData? mappingCurve, // Custom value → property mapping
  });
}
```

### Built-in RTPC Parameters for SlotLab

| Parameter | Range | Default | Driven By |
|-----------|-------|---------|-----------|
| `SpinProgress` | 0.0 → 1.0 | 0.0 | Reel spin animation |
| `WinMultiplier` | 0.0 → 10000.0 | 0.0 | Win evaluation |
| `AnticipationLevel` | 0.0 → 1.0 | 0.0 | AnticipationNode |
| `RollupProgress` | 0.0 → 1.0 | 0.0 | Rollup animation |
| `Excitement` | 0.0 → 1.0 | 0.0 | Composite metric |
| `SessionDuration` | 0.0 → ∞ | 0.0 | Session timer |
| `AutoplaySpeed` | 0.5 → 3.0 | 1.0 | Autoplay settings |
| `PlayerBalance` | 0.0 → ∞ | 0.0 | Game state |
| `FeatureDepth` | 0 → 5 | 0 | Feature nesting |

### RTPC Curve Editor

Audio dizajner crta krivu koja mapira parameter value → property value:

```
Volume (dB)
  0 ┤                                    ╭────
-10 ┤                              ╭─────╯
-20 ┤                        ╭─────╯
-30 ┤                  ╭─────╯
-40 ┤           ╭──────╯
-60 ┤───────────╯
    └────────────────────────────────────────
    0.0        0.2       0.4      0.6    1.0
                  AnticipationLevel
```

---

## 17. Container Hierarchy (Wwise Parity)

Puni container sistem, kompatibilan sa Wwise konceptima ali optimizovan za SlotLab.

### Container Types

```dart
abstract class AudioContainer {
  final String id;
  final String name;
  final List<AudioContainerChild> children;
  final ContainerProperties properties;

  /// Select which children to play
  List<int> selectChildren(ContainerContext context);
}

/// Plays one random child per trigger
class RandomContainer extends AudioContainer {
  final List<double> weights;
  final RepeatAvoidance? avoidance;
  final RandomMode mode; // standard, shuffle, shuffleNoRepeat

  // Wwise parity: initial delay, loop count, play mode, scope (global/gameObject)
}

/// Plays children in sequence
class SequenceContainer extends AudioContainer {
  final SequencePlayMode mode; // step, continuous
  final bool resetOnEvent;
  final SequenceDirection direction; // forward, reverse, pingPong

  // State: current step index
}

/// Blends children based on parameter
class BlendContainer extends AudioContainer {
  final String blendParameter; // RTPC parameter name
  final List<BlendTrack> tracks;
  // Each track: parameter range, volume curve, crossfade type

  // Wwise parity: crossfade shapes (linear, log, S-curve, exponential)
}

/// Selects child based on game state or parameter value
class SwitchContainer extends AudioContainer {
  final String switchParameter; // RTPC or state group
  final Map<String, int> switchMap; // value → child index
  final SwitchTransition transition; // xfade, delay, triggerRate
  final Duration transitionTime;

  // Wwise parity: fade-in, fade-out, play-to-end on switch
}

/// Plays multiple children simultaneously with volume offsets
class LayerContainer extends AudioContainer {
  final List<double> volumeOffsets; // per child volume adjustment (dB)
  // All children play simultaneously, mixed together
}
```

### Nested Container Example (SlotLab)

```
SwitchContainer: "WinAudio" (switch on WinTier RTPC)
├── [WIN_1]: RandomContainer: "SmallWin"
│   ├── Sound: small_win_01 (weight: 40)
│   ├── Sound: small_win_02 (weight: 30)
│   └── Sound: small_win_03 (weight: 30)
│
├── [WIN_2]: SequenceContainer: "MediumWin"
│   ├── Sound: fanfare_medium
│   └── RandomContainer: "CoinSounds"
│       ├── Sound: coins_01
│       ├── Sound: coins_02
│       └── Sound: coins_03
│
├── [WIN_3]: LayerContainer: "BigWin"
│   ├── Sound: epic_fanfare (vol: 0dB)
│   ├── Sound: crowd_cheer (vol: -3dB)
│   └── Sound: coin_shower_loop (vol: -6dB)
│
├── [WIN_4]: BlendContainer: "HugeWin" (blend on RollupProgress)
│   ├── [0.0-0.3]: Sound: huge_win_building
│   ├── [0.3-0.7]: Sound: huge_win_peak
│   └── [0.7-1.0]: Sound: huge_win_celebration
│
└── [WIN_5]: SequenceContainer: "MegaWin"
    ├── Sound: mega_intro
    ├── BlendContainer: "MegaCelebration"
    │   ├── Sound: mega_base
    │   └── Sound: mega_intense
    └── Sound: mega_outro
```

---

## 18. Reactive Event Stream Processing

Inspirisano RxJS/ReactiveX — event stream kao first-class koncept.

```dart
class EventStream {
  /// Debounce — fire only after quiet period
  EventStream debounce(Duration duration);

  /// Throttle — max one event per interval
  EventStream throttle(Duration interval);

  /// Buffer — collect events and emit as batch
  EventStream<List<T>> buffer(Duration window);

  /// Combine — merge multiple streams
  static EventStream combine(List<EventStream> streams);

  /// Filter — pass only matching events
  EventStream where(bool Function(Event) predicate);

  /// Map — transform event data
  EventStream<R> map<R>(R Function(Event) transform);

  /// Scan — accumulate state over events
  EventStream<R> scan<R>(R initial, R Function(R, Event) accumulator);

  /// Window — sliding window of events
  EventStream<List<Event>> window(int count);

  /// Distinct — skip duplicate events
  EventStream distinct({Duration? within});

  /// Timeout — fire error if no event within duration
  EventStream timeout(Duration duration, {Event? fallback});
}
```

### Reactive Patterns for SlotLab

```dart
// Pattern: "Win Streak Detection"
// Fire escalating celebration after N consecutive wins
eventStream
  .where((e) => e.id.startsWith('WIN_'))
  .scan<int>(0, (count, _) => count + 1) // Count consecutive wins
  .where((count) => count >= 3)
  .map((count) => Event('WIN_STREAK', {'count': count}));

// Pattern: "Near-Miss Cooldown"
// Don't play near-miss sound if one played within last 5 spins
eventStream
  .where((e) => e.id == 'NEAR_MISS')
  .throttle(Duration(seconds: 30)) // ~5 spins worth
  .listen((e) => graphExecutor.trigger('NearMissGraph', e));

// Pattern: "Progressive Excitement"
// Blend ambient based on recent win history
eventStream
  .where((e) => e.id.startsWith('WIN_') || e.id == 'SPIN_END')
  .window(10) // Last 10 events
  .map((events) {
    final wins = events.where((e) => e.id.startsWith('WIN_')).length;
    return wins / events.length; // Win ratio
  })
  .listen((excitement) => rtpcManager.setValue('Excitement', excitement));
```

---

## 19. Deterministic Execution Engine

**KRITIČNO za regulisani gambling.** Sertifikacioni zahtevi (GLI-11, BMM testlab, eCOGRA):
- Isti input MORA proizvesti isti output
- Audio ponašanje mora biti reproduktivno iz server seed-a
- Random selekcije u audio sistemu MORAJU koristiti separate seeded RNG

```dart
class DeterministicExecutor {
  final int seed;
  late final Random _rng;

  // Deterministic time source — NOT DateTime.now()
  int _deterministicTimeMicros = 0;

  DeterministicExecutor(this.seed) {
    _rng = Random(seed);
  }

  /// Advance deterministic clock by one control-rate tick
  void tick() {
    _deterministicTimeMicros += 16667; // Exactly 1/60th second
  }

  /// Get deterministic random value
  double nextRandom() => _rng.nextDouble();

  /// Get deterministic integer random in range
  int nextRandomInt(int max) => _rng.nextInt(max);

  /// Execute graph deterministically
  GraphResult executeDeterministic(
    CompiledGraph graph,
    Event event,
    Map<String, double> rtpcState,
  ) {
    // Every node that uses randomness gets values from _rng
    // Every timing node uses _deterministicTimeMicros
    // Result: same seed + same event = same audio behavior
  }

  /// Verify reproducibility (test mode)
  bool verifyDeterminism(
    CompiledGraph graph,
    Event event,
    Map<String, double> rtpcState,
    int runs,
  ) {
    final results = <GraphResult>[];
    for (int i = 0; i < runs; i++) {
      final executor = DeterministicExecutor(seed);
      results.add(executor.executeDeterministic(graph, event, rtpcState));
    }
    return results.every((r) => r == results.first);
  }
}
```

### Determinism Rules

1. **Svi Random čvorovi** koriste seeded RNG, NIKADA `Random()` bez seed-a
2. **Timing čvorovi** koriste determinističke counter-e, NIKADA `DateTime.now()` ili `Stopwatch`
3. **RTPC vrednosti** se snimaju u snapshot pre graf izvršavanja
4. **Graf izvršavanje** je single-threaded za determinizam (control-rate deo)
5. **Audio-rate** deo NE MORA biti determinističan (DSP output zavisi od sample rate, buffer size, hardware)
6. **Audit log** — svaka random selekcija se loguje sa seed, index, result

### Certification Testing Support

```dart
class DeterminismAuditor {
  /// Generate certification report
  CertificationReport audit({
    required List<GraphExecution> executions,
    required int requiredMatches, // Usually 1000+
  }) {
    // Group by identical input
    // Verify identical output for same input
    // Generate report with pass/fail per graph
  }
}
```

---

## 20. Serialization & Persistence

### Graph Format

```json
{
  "id": "win_celebration_v3",
  "name": "Win Celebration",
  "version": 3,
  "format": "fhg1",  // FluxForge Hook Graph v1
  "metadata": {
    "author": "Audio Designer",
    "created": "2026-03-07T12:00:00Z",
    "modified": "2026-03-07T14:30:00Z",
    "tags": ["win", "celebration", "slotlab"],
    "theme": "generic",
    "description": "Main win celebration graph with tier-based routing"
  },
  "inputs": [
    {"id": "event_in", "name": "Event", "type": "trigger"},
    {"id": "payload_in", "name": "Payload", "type": "eventPayload"}
  ],
  "outputs": [
    {"id": "audio_out", "name": "Audio Output", "type": "audioBuffer"}
  ],
  "nodes": {
    "win_tier": {
      "type": "WinTierNode",
      "position": {"x": 200, "y": 100},
      "config": {}
    },
    "switch_tier": {
      "type": "SwitchNode",
      "position": {"x": 400, "y": 100},
      "config": {
        "cases": ["WIN_1", "WIN_2", "WIN_3", "WIN_4", "WIN_5"]
      }
    },
    "play_small": {
      "type": "PlaySoundNode",
      "position": {"x": 600, "y": 50},
      "config": {
        "asset": "audio/wins/small_win_01.wav",
        "loop": false
      }
    }
  },
  "connections": [
    {
      "source": {"node": "event_in", "port": "trigger"},
      "target": {"node": "win_tier", "port": "trigger"}
    },
    {
      "source": {"node": "win_tier", "port": "tier"},
      "target": {"node": "switch_tier", "port": "selector"}
    },
    {
      "source": {"node": "switch_tier", "port": "WIN_1"},
      "target": {"node": "play_small", "port": "trigger"}
    }
  ]
}
```

### Binary Format (MessagePack)

Za runtime loading — 3-5x brži od JSON, 50-70% manji:

```dart
class GraphSerializer {
  /// Save as JSON (human-readable, version control friendly)
  String toJson(HookGraphDefinition graph);

  /// Save as MessagePack (fast loading, compact)
  Uint8List toMsgPack(HookGraphDefinition graph);

  /// Save as compiled binary (Rust-ready, fastest)
  Uint8List toCompiled(CompiledGraph graph);

  /// Load from any format (auto-detect)
  HookGraphDefinition load(dynamic source);
}
```

### Version Migration

```dart
class GraphMigration {
  /// Migrate graph from old version to current
  HookGraphDefinition migrate(Map<String, dynamic> json) {
    int version = json['version'] ?? 1;

    while (version < currentVersion) {
      json = _migrations[version]!(json);
      version++;
    }

    return HookGraphDefinition.fromJson(json);
  }

  static final Map<int, MigrationFn> _migrations = {
    1: _v1ToV2, // Added RTPC nodes
    2: _v2ToV3, // Changed port types
    // ...
  };
}
```

---

## 21. Visual Graph Editor

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│ Visual Graph Editor (Flutter Widget)                           │
│                                                                │
│ ┌──────────┐ ┌──────────────────────────────────────────────┐ │
│ │ Node     │ │ Canvas (CustomPainter)                       │ │
│ │ Palette  │ │                                              │ │
│ │          │ │  ┌─────────┐         ┌─────────┐            │ │
│ │ ▸ Event  │ │  │EventNode│────────→│ Switch  │            │ │
│ │ ▸ Logic  │ │  └─────────┘    ╱    └────┬────┘            │ │
│ │ ▸ Audio  │ │                ╱          │                  │ │
│ │ ▸ DSP    │ │  ┌─────────┐ ╱     ┌─────┴────┐            │ │
│ │ ▸ Timing │ │  │  RTPC   │╱      │PlaySound │            │ │
│ │ ▸ Slot   │ │  └─────────┘       └──────────┘            │ │
│ │ ▸ Control│ │                                              │ │
│ │          │ │  ┌──────────────────────────────────────┐    │ │
│ │          │ │  │ Node Inspector (selected node)       │    │ │
│ │          │ │  │ Name: [Switch Tier          ]        │    │ │
│ │          │ │  │ Cases: WIN_1, WIN_2, WIN_3, ...      │    │ │
│ │          │ │  └──────────────────────────────────────┘    │ │
│ └──────────┘ └──────────────────────────────────────────────┘ │
│                                                                │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Toolbar: [Save] [Load] [Compile] [Preview] [Debug] [Undo]│  │
│ └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

### Node Widget Design

```dart
class GraphNodeWidget extends StatelessWidget {
  final GraphNode node;
  final bool isSelected;
  final Offset position;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: _onDrag,  // Move node
        child: Container(
          decoration: BoxDecoration(
            color: _colorForNodeType(node.type),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with node name
              _buildHeader(),
              // Input ports (left side)
              ...node.inputs.map(_buildInputPort),
              // Output ports (right side)
              ...node.outputs.map(_buildOutputPort),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Connection Drawing (Bézier Wires)

```dart
class WirePainter extends CustomPainter {
  final List<GraphConnection> connections;
  final Map<String, Offset> portPositions;
  final Map<String, dynamic>? liveValues; // Debug mode

  @override
  void paint(Canvas canvas, Size size) {
    for (final conn in connections) {
      final start = portPositions['${conn.sourceNodeId}.${conn.sourcePortId}']!;
      final end = portPositions['${conn.targetNodeId}.${conn.targetPortId}']!;

      // Bézier curve
      final controlOffset = (end.dx - start.dx) * 0.5;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + controlOffset, start.dy,
          end.dx - controlOffset, end.dy,
          end.dx, end.dy,
        );

      // Wire color by type
      final paint = Paint()
        ..color = _colorForPortType(conn.type)
        ..strokeWidth = conn.type == PortType.audioBuffer ? 3.0 : 1.5
        ..style = PaintingStyle.stroke;

      // Animated flow in debug mode
      if (liveValues != null) {
        paint.shader = _flowShader(conn, liveValues!);
      }

      canvas.drawPath(path, paint);
    }
  }
}
```

### Wire Color Convention

| Port Type | Color | Wire Width |
|-----------|-------|------------|
| `trigger` | Yellow | 1.5px |
| `boolean` | Red/Green | 1.5px |
| `float` | Blue | 1.5px |
| `integer` | Cyan | 1.5px |
| `string` | White | 1.5px |
| `audioBuffer` | Orange | 3.0px (thick) |
| `eventPayload` | Purple | 2.0px |
| `voiceHandle` | Green | 2.0px |
| `busHandle` | Magenta | 2.0px |

### Editor Features

| Feature | Description |
|---------|-------------|
| **Drag & Drop** | Drag nodes from palette to canvas |
| **Wire Drawing** | Click output port → drag to input port |
| **Multi-Select** | Box select or Cmd+Click multiple nodes |
| **Copy/Paste** | Cmd+C/V with offset, remapped IDs |
| **Undo/Redo** | Full command history, unlimited |
| **Zoom/Pan** | Scroll wheel zoom, middle-click pan |
| **Minimap** | Overview of entire graph in corner |
| **Search** | Cmd+F to find nodes by name/type |
| **Node Groups** | Visual grouping with colored boxes |
| **Comments** | Sticky note annotations |
| **Alignment** | Grid snap, auto-align, distribute |
| **Subgraph Drill** | Double-click subgraph node to enter it |
| **Breadcrumb** | Navigation: Root > SubGraph1 > SubGraph2 |
| **Live Preview** | Real-time audio preview during editing |
| **Hot Reload** | Changes apply without restart |

### Implementation Note: Vyuh Node Flow

Razmatran Flutter paket `vyuh_node_flow` kao osnova za vizuelni editor. Prednosti:
- Već ima node canvas, port connection, pan/zoom
- Flutter-native (ne web wrapper)

Ali — verovatno nedovoljno za FluxForge potrebe. Preporuka: custom implementacija sa `CustomPainter` + `GestureDetector` bazirano na `InteractiveViewer` widget. FluxForge već ima sličan custom painting kod za waveform display i timeline.

---

## 22. Debugging & Profiling

### Live Debug Overlay

```dart
class GraphDebugOverlay {
  // Wire value display — show current value on each wire
  final bool showWireValues;

  // Execution heatmap — brighter = more frequently executed
  final bool showHeatmap;

  // Trigger flash — node flashes when triggered
  final bool showTriggerFlash;

  // Voice monitor — show active voices per PlaySound node
  final bool showVoiceCount;

  // Timing — show execution time per node
  final bool showTimings;

  // Breakpoints — pause execution at node
  final Set<String> breakpoints;
}
```

### Execution Trace

```dart
class GraphExecutionTrace {
  final String graphId;
  final String eventId;
  final DateTime timestamp;
  final List<NodeExecutionRecord> nodeRecords;

  // Each record:
  // - nodeId, nodeName, nodeType
  // - inputs: Map<portId, value>
  // - outputs: Map<portId, value>
  // - executionTimeUs: microseconds
  // - triggered: bool (did it fire?)
  // - randomSeed: int? (if used randomness)
  // - voicesStarted: int
  // - voicesStopped: int
}
```

### Profiling Metrics

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Graph compile time | < 10ms | 10-50ms | > 50ms |
| Control-rate tick | < 1ms | 1-5ms | > 5ms |
| Audio-rate buffer | < 2ms per buffer | 2-4ms | > 4ms |
| Active graph instances | < 50 | 50-100 | > 100 |
| Active voices | < 32 | 32-64 | > 64 |
| Wire buffer memory | < 4MB | 4-16MB | > 16MB |
| Graph instance pool | < 100 | 100-200 | > 200 |

### Integration with DiagnosticsService

Koristi postojeći DiagnosticsService (vidjeti MEMORY.md):
- `GraphExecutionMonitor` implementira `StageTriggerAware` i `SpinCompleteAware`
- Live monitoring u diagnostics panelu
- Auto-spin QA verifikuje graf determinizam

---

## 23. Performance Budget & Optimization

### Memory Budget

```
Per Graph Instance:
  - Node state:    ~64 bytes × N nodes
  - Wire buffers:  ~4 bytes × buffer_size × N audio wires
  - Compiled data: ~1-10 KB per graph
  - Voice pool:    ~128 bytes × estimated_voices

Typical SlotLab Session:
  - Active graphs:  5-15
  - Total nodes:    50-200
  - Audio wires:    10-30
  - Voices:         8-32

  → Total: ~500 KB - 2 MB (acceptable)
```

### Optimization Strategies

| Strategy | Where | Impact |
|----------|-------|--------|
| **Graph Instance Pool** | Dart | Eliminate GC pressure from graph allocation |
| **Compiled Execution Order** | Dart | No runtime topological sort |
| **Wire Buffer Pool** | Rust | Pre-allocated, reused audio buffers |
| **SIMD DSP Nodes** | Rust | 4-8x speedup for filter/gain/mix |
| **Dead Node Skip** | Both | Skip nodes with no downstream effect |
| **Lazy Evaluation** | Dart | Only compute nodes with changed inputs |
| **Batch Commands** | FFI | Collect multiple commands per tick, send as batch |
| **Voice Virtualization** | Rust | Inaudible voices skip DSP processing |

### Audio Thread Rules (Sacred — from CLAUDE.md)

DSP čvorovi (Rust, audio-rate) MORAJU poštovati:
- **ZERO alokacija** — svi baferi pre-alocirani
- **ZERO lock-ova** — samo atomics i lock-free queues
- **ZERO panic-a** — svaka greška se tiho ignoriše ili koristi fallback
- **Stack only** — sav state na stack-u ili u pre-alociranim strukturama
- **SIMD dispatch** — avx512f → avx2 → sse4.2 → scalar fallback

---

## 24. Plugin & Extension System

### Custom Node API

```dart
/// Register custom node type
class NodePluginRegistry {
  void registerNodeType<T extends GraphNode>({
    required String typeName,
    required String category,
    required String displayName,
    required NodeFactory<T> factory,
    required List<PortDefinition> inputs,
    required List<PortDefinition> outputs,
    required NodeProperties defaultProperties,
    Widget Function(T node)? inspectorWidget,
    Color? color,
    IconData? icon,
  });
}

/// Example: Custom "Scatter Detector" node for specific slot game
NodePluginRegistry.instance.registerNodeType<ScatterDetectorNode>(
  typeName: 'ScatterDetector',
  category: 'Slot',
  displayName: 'Scatter Detector',
  factory: (config) => ScatterDetectorNode(config),
  inputs: [
    PortDefinition('payload', PortType.eventPayload),
    PortDefinition('requiredCount', PortType.integer, defaultValue: 3),
  ],
  outputs: [
    PortDefinition('detected', PortType.trigger),
    PortDefinition('scatterCount', PortType.integer),
    PortDefinition('positions', PortType.string),
  ],
  defaultProperties: NodeProperties({'requiredCount': 3}),
);
```

### Rust Audio Node Plugin

```rust
/// Register custom audio-rate node
#[no_mangle]
pub extern "C" fn register_audio_node(
    registry: &mut AudioNodeRegistry,
) {
    registry.register(
        "CustomReverb",
        Box::new(|config| {
            Box::new(CustomReverbNode::new(config))
        }),
    );
}

struct CustomReverbNode {
    // Pre-allocated delay lines
    delay_lines: [DelayLine; 8],
    // Pre-allocated diffusion matrix
    diffusion: [[f32; 8]; 8],
}

impl AudioNode for CustomReverbNode {
    fn process(&mut self, buffers: &mut [AudioBuffer], buffer_size: usize) {
        // SIMD-optimized reverb processing
        // ZERO allocations, ZERO locks
    }

    fn reset(&mut self) {
        for dl in &mut self.delay_lines {
            dl.clear();
        }
    }
}
```

---

## 25. Preview & Audition System

### Inline Preview

Audio dizajner može čuti rezultat grafa bez puštanja cele igre:

```dart
class GraphPreviewEngine {
  /// Preview entire graph with mock event
  Future<void> previewGraph(
    HookGraphDefinition graph, {
    Event? mockEvent,
    Map<String, double>? mockRTPC,
    String? mockState,
  });

  /// Preview single node output
  Future<void> previewNode(
    HookGraphDefinition graph,
    String nodeId, {
    Map<String, dynamic>? mockInputs,
  });

  /// Preview from node to output (partial graph)
  Future<void> previewFromNode(
    HookGraphDefinition graph,
    String startNodeId,
  );

  /// A/B comparison — switch between two graph versions
  Future<void> abCompare(
    HookGraphDefinition graphA,
    HookGraphDefinition graphB,
    Event mockEvent,
  );

  /// Scrub — manually control timeline position
  void scrub(double position); // 0.0 → 1.0

  /// Solo — hear only one node's output
  void soloNode(String nodeId);

  /// Mute — silence one node
  void muteNode(String nodeId);
}
```

### Mock Event Generator

```dart
class MockEventGenerator {
  /// Generate realistic slot events for preview
  Event generateSpinStart({int betAmount = 100});
  Event generateReelStop({int reelIndex = 0, List<String>? symbols});
  Event generateWinEval({int tier = 1, double amount = 500});
  Event generateFeatureStart({String feature = 'FREE_SPINS'});
  Event generateNearMiss({int distance = 1, String type = 'scatter'});

  /// Generate a full spin sequence
  Stream<Event> generateSpinSequence({
    int winTier = 0,
    bool hasNearMiss = false,
    bool triggerFeature = false,
    Duration reelStopInterval = const Duration(milliseconds: 300),
  });
}
```

---

## 26. Integration with Existing FluxForge Systems

### EventRegistry Integration

```dart
// Hook Graph System receives events FROM EventRegistry
// EventRegistry → HookGraphRegistry → Graph Executor

class EventRegistryBridge {
  void connect(EventRegistry eventRegistry, HookGraphRegistry graphRegistry) {
    eventRegistry.addListener(() {
      // When EventRegistry fires an event, resolve matching graphs
      for (final event in eventRegistry.pendingEvents) {
        final graphs = graphRegistry.resolve(event.id);
        for (final binding in graphs) {
          _executor.execute(binding.compiledGraph, event);
        }
      }
    });
  }
}
```

### HookDispatcher Coexistence

Hook Graph System NE zamenjuje HookDispatcher — koegzistiraju:

```
Event Flow:
  EventRegistry → HookDispatcher (simple hooks, existing behavior)
                → HookGraphRegistry (graph-based hooks, new behavior)

  Priority: Graph hooks execute BEFORE simple hooks (by default)
  Migration: Existing simple hooks can be wrapped as single-node graphs
```

### MiddlewareProvider Integration

```dart
// Graph nodes can read from MiddlewareProvider
class MiddlewareBridgeNode extends GraphNode {
  // Outputs: compositeEvents, activeMiddlewares, etc.
  // Bridges existing middleware state into graph system
}
```

### SlotLabCoordinator Integration

```dart
// SlotLabCoordinator triggers graph events via existing stage system
// _triggerStage() → DiagnosticsService.onStageTrigger()
//                → HookGraphRegistry.resolve(stageEvent)
//                → Graph execution
```

---

## 27. Rust FFI Graph Engine

### FFI Interface

```rust
// rf-bridge/src/hook_graph_ffi.rs

/// Load compiled graph into audio engine
#[no_mangle]
pub extern "C" fn hook_graph_load(
    graph_data: *const u8,
    graph_len: usize,
    graph_id: u32,
) -> i32;

/// Unload graph from audio engine
#[no_mangle]
pub extern "C" fn hook_graph_unload(graph_id: u32) -> i32;

/// Trigger graph execution (from control-rate)
#[no_mangle]
pub extern "C" fn hook_graph_trigger(
    graph_id: u32,
    event_data: *const u8,
    event_len: usize,
) -> i32;

/// Send RTPC value to graph
#[no_mangle]
pub extern "C" fn hook_graph_set_rtpc(
    graph_id: u32,
    param_id: u32,
    value: f32,
    interp_ms: f32,
) -> i32;

/// Send command batch to audio-rate graph
#[no_mangle]
pub extern "C" fn hook_graph_send_commands(
    commands: *const u8,
    commands_len: usize,
) -> i32;

/// Get graph state (for debug overlay)
#[no_mangle]
pub extern "C" fn hook_graph_get_state(
    graph_id: u32,
    state_buffer: *mut u8,
    buffer_len: usize,
) -> i32;

/// Get active voice count
#[no_mangle]
pub extern "C" fn hook_graph_voice_count() -> u32;

/// Get peak/RMS meters
#[no_mangle]
pub extern "C" fn hook_graph_get_meters(
    meters: *mut f32,
    count: usize,
) -> i32;
```

### Rust Graph Engine Core

```rust
// rf-engine/src/hook_graph/mod.rs

pub struct HookGraphEngine {
    /// Loaded graphs (compiled)
    graphs: HashMap<u32, CompiledAudioGraph>,

    /// Active graph instances
    active: Vec<ActiveGraphInstance>,

    /// Instance pool
    pool: GraphInstancePool,

    /// Voice manager
    voices: VoiceManager,

    /// Global DSP state (reverb sends, master EQ, etc.)
    global_dsp: GlobalDspState,

    /// Command queue from Dart
    command_rx: rtrb::Consumer<GraphCommand>,

    /// Feedback queue to Dart
    feedback_tx: rtrb::Producer<GraphFeedback>,
}

impl HookGraphEngine {
    /// Process one audio buffer — called from audio callback
    pub fn process(&mut self, output: &mut [f32], buffer_size: usize) {
        // 1. Drain commands
        self.drain_commands();

        // 2. Process each active graph
        for instance in &mut self.active {
            instance.process(&mut self.voices, buffer_size);
        }

        // 3. Mix voices to output
        self.voices.mix_to_output(output, buffer_size);

        // 4. Apply global DSP
        self.global_dsp.process(output, buffer_size);

        // 5. Send feedback (meters, voice counts)
        self.send_feedback();

        // 6. Recycle finished instances
        self.recycle_finished();
    }
}
```

---

## 28. File Structure

```
flutter_ui/lib/
├── models/
│   └── hook_graph/
│       ├── graph_definition.dart       # HookGraphDefinition, GraphNode, GraphConnection
│       ├── graph_ports.dart            # PortType, PortDirection, GraphPort
│       ├── node_types.dart             # All node type classes
│       ├── container_types.dart        # RandomContainer, SequenceContainer, etc.
│       ├── compiled_graph.dart         # CompiledGraph, compilation result
│       └── graph_serialization.dart    # JSON/MessagePack serialization
│
├── services/
│   └── hook_graph/
│       ├── hook_graph_registry.dart    # HookGraphRegistry, pattern matching
│       ├── graph_compiler.dart         # GraphCompiler, optimizations
│       ├── graph_executor.dart         # ControlRateExecutor
│       ├── rtpc_manager.dart           # RTPCManager, parameter system
│       ├── audio_layer_system.dart     # AudioLayerSystem, global layers
│       ├── deterministic_executor.dart # DeterministicExecutor
│       ├── event_stream.dart           # Reactive event stream processing
│       ├── graph_preview_engine.dart   # Preview/audition system
│       └── graph_debug_service.dart    # Debug overlay, execution trace
│
├── providers/
│   └── hook_graph/
│       ├── hook_graph_provider.dart    # Main provider, bridges to UI
│       ├── graph_editor_provider.dart  # Visual editor state
│       └── graph_debug_provider.dart   # Debug/profiling state
│
├── widgets/
│   └── hook_graph/
│       ├── graph_editor_canvas.dart    # Main editor widget
│       ├── graph_node_widget.dart      # Individual node widget
│       ├── graph_wire_painter.dart     # Bézier wire drawing
│       ├── node_palette_widget.dart    # Draggable node palette
│       ├── node_inspector_widget.dart  # Selected node properties
│       ├── graph_toolbar_widget.dart   # Toolbar actions
│       ├── graph_minimap_widget.dart   # Minimap overview
│       └── graph_debug_overlay.dart    # Live debug overlay

rf-engine/src/
├── hook_graph/
│   ├── mod.rs                          # HookGraphEngine
│   ├── audio_node.rs                   # AudioNode trait
│   ├── voice_manager.rs                # Voice allocation, stealing, virtualization
│   ├── compiled_graph.rs               # CompiledAudioGraph
│   ├── instance_pool.rs                # GraphInstancePool
│   ├── dsp_nodes/
│   │   ├── filter.rs                   # Biquad TDF-II
│   │   ├── gain.rs                     # Gain with smoothing
│   │   ├── pan.rs                      # Stereo panner
│   │   ├── delay.rs                    # Delay effect
│   │   ├── compressor.rs              # Dynamics processor
│   │   ├── mixer.rs                    # N-input mixer
│   │   └── bus_send.rs                 # Bus routing
│   └── containers/
│       ├── random.rs                   # Weighted random selection
│       ├── sequence.rs                 # Sequential playback
│       ├── blend.rs                    # Parameter-driven blend
│       └── switch.rs                   # State-driven switch

rf-bridge/src/
├── hook_graph_ffi.rs                   # FFI interface for graph commands

rf-engine/src/
├── hook_graph/
│   ├── asset_manager.rs                # Audio asset loading, streaming, memory pool
│   ├── bus_graph.rs                    # Bus hierarchy processing
│   ├── live_server.rs                  # TCP server for live connection
│   └── music/
│       ├── state_machine.rs            # Music state machine
│       ├── segment.rs                  # Music segment model
│       ├── transition.rs               # Transition rules
│       └── stinger.rs                  # Stinger system

flutter_ui/lib/
├── services/
│   └── hook_graph/
│       ├── music_state_machine.dart    # MusicStateMachine controller
│       ├── stinger_manager.dart        # Stinger triggers + cooldowns
│       ├── bus_manager.dart            # Bus hierarchy, snapshots
│       ├── asset_hot_swap.dart         # File watcher, live asset replacement
│       ├── live_connection.dart        # TCP client for live update
│       ├── session_recorder.dart       # Session recording/replay
│       ├── regulatory_rules.dart       # Jurisdiction audio rules
│       └── accessibility_system.dart   # Visual feedback, haptics, subtitles

assets/
├── hook_graphs/
│   ├── templates/                      # Built-in graph templates
│   │   ├── basic_play.fhg.json
│   │   ├── tiered_win.fhg.json
│   │   ├── reel_stop_random.fhg.json
│   │   ├── feature_transition.fhg.json
│   │   ├── anticipation_swell.fhg.json
│   │   ├── rollup_audio.fhg.json
│   │   └── adaptive_ambient.fhg.json
│   ├── user/                           # User-created graphs
│   └── music/
│       ├── state_machines/             # Music state machine definitions
│       └── stingers/                   # Stinger definitions
├── regulatory/
│   ├── UKGC_audio_rules.json
│   ├── MGA_audio_rules.json
│   └── DEFAULT_audio_rules.json
└── localization/
    ├── EU/                             # European regional audio overrides
    ├── UK/                             # UK-specific overrides
    └── ASIA/                           # Asian market overrides
```

---

## 29. Implementation Phases

### Phase 1: Core Graph Engine (Foundation) — ~2 weeks
**Deliverables:** Graph can execute basic event→play sound flows
- `GraphNode` base class (S32), `WireState`, `GraphContext`
- `NodeTypeRegistry` (S33) — registration, factory, search
- `HookGraphDefinition`, `GraphConnection`, `GraphPort` modeli (S5)
- `GraphCompiler` — validation (S37), topological sort, type checking
- `WireTransformEngine` — implicit type coercion (S34)
- `ControlRateExecutor` — basic node processing (S7)
- Basic node types: EventEntry, Compare, Switch, Gate, PlaySound, StopSound
- `HookGraphRegistry` — exact match binding (S4)
- `GraphInstancePool` — pool lifecycle (S35)
- JSON serialization (S20)
- Unit tests (S43) — node-level, graph-level
- **Acceptance:** basic_play.fhg.json executes, produces StartVoiceCommand

### Phase 2: Container System + RTPC + Bus Routing — ~2 weeks
**Deliverables:** Tiered win celebration works end-to-end
- RandomContainer, SequenceContainer, SwitchContainer, BlendContainer, LayerContainer (S17)
- `RTPCManager` — parameter definition, binding, curve mapping (S16)
- Weighted random with repeat avoidance (S14)
- Container nesting
- SlotLab-specific nodes: WinTierNode, ReelAnalyzerNode, FeatureStateNode (S6.12)
- Bus hierarchy model (S46) — Master Bus, sub-buses, routing
- Cooldown, debounce, counter, latch nodes (S15, S6.3)
- **Acceptance:** tiered_win_celebration.fhg.json routes WIN_1-5 correctly

### Phase 3: Visual Graph Editor — ~3 weeks
**Deliverables:** Audio designers can create and edit graphs visually
- Graph canvas with `InteractiveViewer` + `CustomPainter` (S21)
- Node widgets with typed ports, color-coded by category
- Bézier wire drawing with type-colored wires (S21)
- Wire transform visualization (S34) — implicit/explicit/incompatible indicators
- Drag & drop from categorized palette
- Node inspector widgets — default auto-gen + per-type inspectors (S40)
- Copy/paste, undo/redo command system (S38)
- Save/load JSON
- Minimap, breadcrumb navigation for subgraphs
- Graph validation with error markers and auto-fix suggestions (S37)
- **Acceptance:** Designer creates tiered win graph from scratch in editor

### Phase 4: Rust Audio Engine — ~3 weeks
**Deliverables:** Audio actually plays through graph system
- `HookGraphEngine` in rf-engine (S27)
- `AudioNode` trait + DSP nodes: filter, gain, pan, delay, compressor, mixer (S6.6)
- `VoiceManager` — pool, stealing, virtualization, groups (S36)
- `BusGraph` — full bus hierarchy processing in Rust (S46)
- `AssetManager` — loading, streaming, memory pool, codec support (S47)
- Lock-free command queue Dart → Rust (`rtrb::RingBuffer`)
- FFI interface — all hook_graph_* functions (S27)
- Buffer pre-allocation, zero audio-thread allocation verified
- **Acceptance:** Slot spin with tiered wins produces audible, correctly routed audio

### Phase 5: Music & Advanced Audio — ~2 weeks
**Deliverables:** Interactive music, stingers, layers
- `MusicStateMachine` — segments, transitions, beat/bar sync (S45)
- `StingerSystem` — sync types, duck behavior, cooldowns (S49)
- Layer control nodes — start, stop, fade, blend, switch, duck, sidechain (S6.8)
- Audio layer system with predefined slot presets (S13)
- Timing nodes: delay, metronome, envelope, timeline, ramp, barrier (S6.4)
- Wildcard/regex pattern matching (S11)
- Graph composition & inheritance (S10)
- **Acceptance:** Full spin sequence with base→spin→win music transitions

### Phase 6: Advanced Logic & Analytics — ~2 weeks
**Deliverables:** Intelligent audio adaptation
- Reactive event streams (S18)
- State & Memory nodes: StateStore, Accumulator, EventHistory (S6.10)
- Analytics nodes: VolatilityAnalyzer, ExcitementMapper, PlayerBehavior, BigWinOrchestrator (S6.11)
- Dynamic runtime binding (S12)
- Plugin extension system — Dart + Rust APIs (S24)
- Localization node + regional audio config (S53)
- **Acceptance:** Audio adapts to simulated 100-spin session based on gameplay metrics

### Phase 7: Determinism & Compliance — ~1 week
**Deliverables:** Passes gambling certification requirements
- `DeterministicExecutor` with seeded RNG (S19)
- Certification audit logging + DeterminismAuditor (S19)
- Regulatory validation node + jurisdiction rules (S51)
- Near-miss audio rules enforcement (S51)
- Determinism test suite — 1000-run verification (S43)
- **Acceptance:** All graphs pass determinism audit, regulatory validator blocks prohibited audio

### Phase 8: Preview & Debugging — ~2 weeks
**Deliverables:** Complete design iteration loop
- Preview engine with mock events, A/B comparison (S25)
- Mock event generator — full spin sequence simulation (S25)
- Node solo/mute
- Live debug overlay — wire values, heatmap, trigger flash, voice count (S22)
- Execution trace recording (S22)
- Session recording & replay (S50)
- Performance profiling integration with DiagnosticsService (S22)
- MetaSounds-style wire visualization: trigger pulse, audio thickness, float color (S22)
- **Acceptance:** Designer can preview, debug, and profile graph in real-time

### Phase 9: Live Connection & Hot-Swap — ~1 week
**Deliverables:** Zero-iteration-cost workflow
- Live Connection TCP protocol (S48) — bidirectional MessagePack
- Auto-discovery on local network
- Graph hot-reload — push changes to running app
- Asset hot-swap — file watcher, zero-downtime replacement (S54)
- **Acceptance:** Designer edits graph, hears result in running app < 1 second

### Phase 10: Polish & Templates — ~1 week
**Deliverables:** Production-ready system
- Graph templates library — 7 built-in templates (S41)
- Template instantiation UI with parameter editing
- Accessibility system — visual feedback, haptics, subtitles (S52)
- Volume normalization — EBU R128 (S52)
- HookDispatcher migration — Phase M1-M2 (S44)
- Error recovery testing — fuzz tests, crash recovery (S42, S43)
- Complete node reference in documentation (S55)
- **Acceptance:** Audio designer onboarding — new user creates working slot audio in < 30 minutes

---

## 30. Data Structures

### Core Types

```dart
// Node execution state
enum NodeState { idle, active, cooldown, error }

// Graph instance state
enum GraphInstanceState {
  pooled,     // In pool, waiting for use
  allocated,  // Allocated, not yet executing
  executing,  // Currently processing
  finishing,  // Voices fading out
  done,       // Ready to recycle
}

// Voice state
enum VoiceState {
  idle, starting, playing, looping, stopping, stopped, virtual
}

// RTPC interpolation
enum RTPCInterpolation {
  none, linear, logarithmic, sCurve, exponential, custom
}

// Curve types for automation
enum CurveType {
  linear, easeIn, easeOut, easeInOut,
  logarithmic, exponential, sCurve, step, custom
}

// Filter types
enum FilterType {
  lowpass, highpass, bandpass, notch,
  allpass, peakEQ, lowShelf, highShelf
}

// Sequence modes
enum SequenceMode { forward, reverse, pingPong, random }

// Compare operators
enum CompareOp { eq, neq, lt, gt, lte, gte, contains, startsWith, endsWith }

// Bool operations
enum BoolOp { and, or, not, xor, nand, nor }
```

### Wire Protocol Commands (Dart → Rust)

```rust
#[repr(u8)]
enum GraphCommandType {
    LoadGraph = 1,
    UnloadGraph = 2,
    TriggerGraph = 3,
    StopGraph = 4,
    SetRTPC = 5,
    StartVoice = 10,
    StopVoice = 11,
    SetVoiceParam = 12,
    PauseVoice = 13,
    ResumeVoice = 14,
    SetNodeParam = 20,
    EnableNode = 21,
    DisableNode = 22,
    SetLayerVolume = 30,
    SetLayerFilter = 31,
    // Bus routing
    SetBusVolume = 40,
    SetBusMute = 41,
    SetBusSolo = 42,
    SetAuxSend = 43,
    ApplyMixSnapshot = 44,
    // Music
    MusicSetState = 50,
    MusicTriggerStinger = 51,
    MusicSetTempo = 52,
    // Asset
    AssetPreload = 60,
    AssetEvict = 61,
    AssetSwap = 62,
}
```

---

## 31. Critical Rules

1. **Audio thread = sacred** — DSP čvorovi (Rust): zero allocations, zero locks, zero panics. Bez izuzetka.

2. **Kompajler je čuvar** — graf se NE MOŽE izvršiti bez kompajliranja. Kompajler detektuje: cikluse, type mismatch, nedostajuće konekcije, nedostupne čvorove.

3. **Determinizam je opcioni ali striktni** — kad je uključen, SVAKA random operacija koristi seeded RNG, SVAKI timing koristi deterministički clock. Nema mešanja.

4. **Pool everything** — graf instance, voice-ovi, wire baferi — SVE se pooluje. GC pritisak = audio glitch.

5. **EventRegistry ostaje Single Source** — Hook Graph Registry je POTROŠAČ EventRegistry-ja, NIKADA ne zaobilazi ga. Jedan put registracije (CLAUDE.md pravilo) ostaje.

6. **HookDispatcher koegzistencija** — Hook Graph ne zamenjuje HookDispatcher. Koegzistiraju sa definisanim prioritetom. Migracija je postepena.

7. **Win tier konfiguracija** — NIKADA hardkodirati tier labele, boje, pragove u graf čvorovima. WinTierNode koristi WinTierConfig (data-driven).

8. **Subgraph dubina limit** — max 8 nivoa. Kompajler odbija dublje nestovanje.

9. **Max active graphs** — soft limit 50, hard limit 100. Iznad toga — voice stealing i graph recycling.

10. **Debug UI only** — dijagnostika se prikazuje u UI (debug overlay), NIKADA print/debugPrint (CLAUDE.md pravilo).

11. **Graph changes = new version** — nikada in-place mutacija. Nova verzija grafa, stara se gracefully završava.

12. **Binary wire protocol** — Dart↔Rust komunikacija koristi MessagePack, NIKADA JSON string parsing na audio-adjacent thread-ovima.

13. **Bus routing = Rust only** — bus hierarchy processing se dešava ISKLJUČIVO na audio thread-u u Rust-u. Dart šalje komande (SetBusVolume, etc.), Rust primenjuje.

14. **Asset memory budget** — hard limit 64MB za audio assets u memoriji. AssetManager eviktuje LRU assets kad se prekorači. Streaming za fajlove > 2MB.

15. **Music transitions = beat-synced** — MusicStateMachine NIKADA ne seče muziku na proizvoljnoj poziciji. Minimum sync = nextBeat. Immediate samo za emergency/stinger.

16. **Regulatory rules = pre-graph filter** — RegulatoryValidatorNode se postavlja ISPRED audio akcija, NIKADA posle. Blokirani zvuci se NE puštaju pa gase — oni se uopšte ne puštaju.

17. **Accessibility = opt-in, not degradation** — accessibility features (visual pulse, haptic, subtitle) su DODATAK zvuku, NIKADA zamena. Zvuk ostaje isti za sve igrače.

18. **Session recording = zero overhead when off** — SessionRecorder NE SMEJU uticati na performance kad nisu aktivni. Guard check na početku svake metode.

19. **Live connection = development only** — LiveServer se NE kompajlira u release build. `#if kDebugMode` guard na celom TCP stack-u.

20. **Asset hot-swap = non-destructive** — stara verzija asseta se NIKADA ne briše dok postoji voice koji je koristi. Version tracking sa ref counting.

---

## 32. GraphNode Base Architecture

Svaki node u sistemu nasleđuje zajedničku bazu. Ovo je fundament za polimorfno izvršavanje i registraciju.

```dart
/// Base class for ALL graph nodes
abstract class GraphNode {
  final String id;           // Unique within graph (UUID v4)
  final String typeId;       // Registry key: "PlaySoundNode", "SwitchNode", etc.
  final Offset position;     // Visual editor position (x, y)

  // Port definitions (immutable after creation)
  final List<GraphPort> inputPorts;
  final List<GraphPort> outputPorts;

  // Configurable parameters (editable in inspector)
  final Map<String, dynamic> parameters;

  // Runtime state (mutable during execution)
  NodeState _state = NodeState.idle;
  int _lastProcessedTick = -1;
  final List<GraphCommand> _pendingCommands = [];

  // Execution classification
  bool get isAudioRate => false;  // Override in DSP nodes
  bool get isStateful => false;   // Override in nodes that maintain state
  bool get isPure => true;        // Pure nodes can be constant-folded

  // --- Lifecycle ---

  /// Called once when graph instance is allocated from pool
  void initialize(GraphContext context) {
    _state = NodeState.idle;
    _lastProcessedTick = -1;
    _pendingCommands.clear();
    onInitialize(context);
  }

  /// Called every control-rate tick (override in subclasses)
  void process(WireState wires, int tick, GraphContext context) {
    if (_lastProcessedTick >= tick) return; // Already processed this tick
    _lastProcessedTick = tick;
    _state = NodeState.active;

    try {
      onProcess(wires, tick, context);
    } catch (e) {
      _state = NodeState.error;
      context.reportError(id, e);
      // Node enters error state — does NOT propagate, does NOT crash graph
    }
  }

  /// Called when graph instance is returned to pool
  void reset() {
    _state = NodeState.idle;
    _lastProcessedTick = -1;
    _pendingCommands.clear();
    onReset();
  }

  /// Check if this node needs processing (dirty check)
  bool needsUpdate(WireState wires, int tick) {
    if (_lastProcessedTick >= tick) return false;

    // Check if any input changed since last tick
    for (final port in inputPorts) {
      if (wires.isChanged(id, port.id, _lastProcessedTick)) {
        return true;
      }
    }

    // Stateful nodes (timer, cooldown) always need update
    if (isStateful) return true;

    return false;
  }

  // --- Pending audio commands ---

  List<GraphCommand> get pendingCommands => _pendingCommands;

  void emitCommand(GraphCommand cmd) {
    _pendingCommands.add(cmd);
  }

  // --- Abstract methods for subclasses ---

  /// Subclass initialization logic
  void onInitialize(GraphContext context) {}

  /// Subclass processing logic — MUST read from wires.read() and write to wires.write()
  void onProcess(WireState wires, int tick, GraphContext context);

  /// Subclass cleanup logic
  void onReset() {}

  // --- Serialization ---

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': typeId,
    'position': {'x': position.dx, 'y': position.dy},
    'parameters': parameters,
  };

  // --- Introspection ---

  /// Human-readable description for tooltip/inspector
  String get description;

  /// Category for palette grouping
  NodeCategory get category;

  /// Color for visual editor
  Color get nodeColor => category.color;

  /// Icon for node header
  IconData get nodeIcon;

  /// Validation rules specific to this node type
  List<NodeValidationRule> get validationRules => [];
}
```

### GraphContext — Shared Execution Context

```dart
/// Shared context available to all nodes during execution
class GraphContext {
  final int tick;                          // Current control-rate tick number
  final int deterministicTimeMicros;       // Deterministic clock
  final Random? deterministicRng;          // Seeded RNG (null if non-deterministic)
  final RTPCManager rtpcManager;           // Read RTPC values
  final StateStoreManager stateStore;      // Cross-graph persistent state
  final EventHistory eventHistory;         // Recent event lookback
  final GraphFeedbackSink feedbackSink;    // Send feedback to UI (meters, state)
  final AudioCommandSink audioCommandSink; // Send commands to Rust audio engine

  // Error handling
  void reportError(String nodeId, dynamic error) {
    feedbackSink.send(GraphFeedback.nodeError(nodeId, error.toString()));
  }

  // Debug
  void debugValue(String nodeId, String label, dynamic value) {
    if (kDebugMode) {
      feedbackSink.send(GraphFeedback.debugValue(nodeId, label, value));
    }
  }
}
```

### WireState — Connection Data Bus

```dart
/// Holds all wire values for a graph instance
class WireState {
  // Indexed by wire index (int), not string ID — for performance
  final List<dynamic> _values;
  final List<int> _lastWriteTick;
  final Map<String, int> _wireIndex; // "nodeId.portId" → index

  /// Read value from input port
  T read<T>(String nodeId, String portId) {
    final idx = _wireIndex['$nodeId.$portId']!;
    return _values[idx] as T;
  }

  /// Read with default if not yet written
  T readOr<T>(String nodeId, String portId, T defaultValue) {
    final idx = _wireIndex['$nodeId.$portId'];
    if (idx == null || _values[idx] == null) return defaultValue;
    return _values[idx] as T;
  }

  /// Write value to output port
  void write(String nodeId, String portId, dynamic value, int tick) {
    final idx = _wireIndex['$nodeId.$portId']!;
    _values[idx] = value;
    _lastWriteTick[idx] = tick;
  }

  /// Check if a wire value changed since given tick
  bool isChanged(String nodeId, String portId, int sinceTick) {
    final idx = _wireIndex['$nodeId.$portId'];
    if (idx == null) return false;
    return _lastWriteTick[idx] > sinceTick;
  }

  /// Reset all values (when graph instance is recycled)
  void clear() {
    _values.fillRange(0, _values.length, null);
    _lastWriteTick.fillRange(0, _lastWriteTick.length, -1);
  }

  /// Allocate from compiled graph specification
  factory WireState.fromCompiled(CompiledGraph compiled) {
    return WireState._(
      values: List.filled(compiled.wireMap.length, null),
      lastWriteTick: List.filled(compiled.wireMap.length, -1),
      wireIndex: compiled.wireMap,
    );
  }
}
```

### NodeCategory Enum

```dart
enum NodeCategory {
  event(Color(0xFFFFD700), 'Event', Icons.flash_on),           // Gold
  condition(Color(0xFFFF6B6B), 'Condition', Icons.help_outline), // Red
  logic(Color(0xFF4ECDC4), 'Logic', Icons.account_tree),        // Teal
  timing(Color(0xFFA78BFA), 'Timing', Icons.timer),             // Purple
  audio(Color(0xFFFF9F43), 'Audio', Icons.volume_up),           // Orange
  dsp(Color(0xFFEE5A24), 'DSP', Icons.graphic_eq),             // Dark Orange
  layer(Color(0xFF6C5CE7), 'Layer', Icons.layers),             // Indigo
  container(Color(0xFF00CEC9), 'Container', Icons.inventory),   // Cyan
  control(Color(0xFF636E72), 'Control', Icons.settings),        // Gray
  state(Color(0xFF55A3F0), 'State', Icons.save),               // Blue
  analytics(Color(0xFFE84393), 'Analytics', Icons.insights),    // Pink
  slot(Color(0xFFFDAA2D), 'Slot', Icons.casino),               // Amber
  debug(Color(0xFF95A5A6), 'Debug', Icons.bug_report),         // Light Gray
  utility(Color(0xFFBDC3C7), 'Utility', Icons.build),          // Silver
}
```

---

## 33. Node Registry & Factory System

Centralni registar svih dostupnih node tipova. Podržava built-in i plugin čvorove.

```dart
class NodeTypeRegistry {
  static final NodeTypeRegistry instance = NodeTypeRegistry._();
  NodeTypeRegistry._();

  final Map<String, NodeTypeDefinition> _types = {};

  /// Register a node type (called at startup)
  void register(NodeTypeDefinition definition) {
    if (_types.containsKey(definition.typeId)) {
      throw StateError('Node type "${definition.typeId}" already registered');
    }
    _types[definition.typeId] = definition;
  }

  /// Create node instance from type ID
  GraphNode create(String typeId, {
    required String nodeId,
    Offset position = Offset.zero,
    Map<String, dynamic>? parameters,
  }) {
    final definition = _types[typeId];
    if (definition == null) {
      throw ArgumentError('Unknown node type: $typeId');
    }
    return definition.factory(
      nodeId,
      position,
      parameters ?? definition.defaultParameters,
    );
  }

  /// Get all registered types
  List<NodeTypeDefinition> get allTypes => _types.values.toList();

  /// Get types by category
  List<NodeTypeDefinition> byCategory(NodeCategory category) {
    return _types.values.where((t) => t.category == category).toList();
  }

  /// Search types by name/description
  List<NodeTypeDefinition> search(String query) {
    final lower = query.toLowerCase();
    return _types.values.where((t) =>
      t.displayName.toLowerCase().contains(lower) ||
      t.description.toLowerCase().contains(lower) ||
      t.tags.any((tag) => tag.toLowerCase().contains(lower))
    ).toList();
  }

  /// Deserialize node from JSON
  GraphNode fromJson(Map<String, dynamic> json) {
    return create(
      json['type'] as String,
      nodeId: json['id'] as String,
      position: Offset(
        (json['position']['x'] as num).toDouble(),
        (json['position']['y'] as num).toDouble(),
      ),
      parameters: json['parameters'] as Map<String, dynamic>?,
    );
  }
}

/// Definition for a node type (metadata + factory)
class NodeTypeDefinition {
  final String typeId;
  final String displayName;
  final String description;
  final NodeCategory category;
  final List<PortDefinition> inputs;
  final List<PortDefinition> outputs;
  final Map<String, dynamic> defaultParameters;
  final List<String> tags; // For search
  final GraphNode Function(String id, Offset pos, Map<String, dynamic> params) factory;
  final Widget Function(GraphNode node, Function(String, dynamic) onParamChanged)? inspectorBuilder;
  final IconData? icon;
  final Color? customColor;

  // Constraints
  final int maxInstances;       // Max per graph (0 = unlimited)
  final bool allowMultiple;     // Can appear more than once?
  final bool isExperimental;    // Show warning badge
  final String? requiredPlugin; // Plugin dependency
}

class PortDefinition {
  final String id;
  final String name;
  final PortType type;
  final PortDirection direction;
  final dynamic defaultValue;
  final bool required;          // Connection required for valid graph?
  final String? tooltip;
  final double? minValue;
  final double? maxValue;
  final List<String>? enumValues;
}
```

### Built-in Registration

```dart
/// Called once at app startup
void registerBuiltInNodeTypes() {
  final registry = NodeTypeRegistry.instance;

  // --- Event Nodes ---
  registry.register(NodeTypeDefinition(
    typeId: 'EventEntryNode',
    displayName: 'Event Entry',
    description: 'Entry point — receives event from Registry',
    category: NodeCategory.event,
    inputs: [],
    outputs: [
      PortDefinition(id: 'trigger', name: 'Trigger', type: PortType.trigger, direction: PortDirection.output),
      PortDefinition(id: 'eventId', name: 'Event ID', type: PortType.string, direction: PortDirection.output),
      PortDefinition(id: 'payload', name: 'Payload', type: PortType.eventPayload, direction: PortDirection.output),
      PortDefinition(id: 'timestamp', name: 'Timestamp', type: PortType.integer, direction: PortDirection.output),
    ],
    defaultParameters: {'eventName': '', 'namespace': '*'},
    tags: ['event', 'entry', 'input', 'start'],
    factory: (id, pos, params) => EventEntryNode(id: id, position: pos, parameters: params),
    maxInstances: 0,
    allowMultiple: true,
    isExperimental: false,
  ));

  // --- Condition Nodes ---
  registry.register(NodeTypeDefinition(
    typeId: 'CompareNode',
    displayName: 'Compare',
    description: 'Compare two values (==, !=, <, >, <=, >=)',
    category: NodeCategory.condition,
    inputs: [
      PortDefinition(id: 'a', name: 'A', type: PortType.any, direction: PortDirection.input, required: true),
      PortDefinition(id: 'b', name: 'B', type: PortType.any, direction: PortDirection.input, required: true),
    ],
    outputs: [
      PortDefinition(id: 'result', name: 'Result', type: PortType.boolean, direction: PortDirection.output),
      PortDefinition(id: 'trueOut', name: 'True', type: PortType.trigger, direction: PortDirection.output),
      PortDefinition(id: 'falseOut', name: 'False', type: PortType.trigger, direction: PortDirection.output),
    ],
    defaultParameters: {'operator': 'eq'},
    tags: ['compare', 'condition', 'equals', 'greater', 'less'],
    factory: (id, pos, params) => CompareNode(id: id, position: pos, parameters: params),
  ));

  // ... register ALL 75+ node types following same pattern ...
  // Full registration list matches Section 6 node types 6.1-6.12
}
```

---

## 34. Wire Transform System

Žice između čvorova mogu imati implicitne ili eksplicitne type konverzije.

### Implicit Type Coercion

```dart
class WireTransformEngine {
  /// Check if connection is valid (with or without transform)
  ConnectionValidity canConnect(PortType source, PortType target) {
    if (source == target) return ConnectionValidity.direct;
    if (target == PortType.any) return ConnectionValidity.direct;
    if (source == PortType.any) return ConnectionValidity.direct;

    // Check implicit coercion table
    final transform = _implicitTransforms[_key(source, target)];
    if (transform != null) return ConnectionValidity.implicit(transform);

    // Check if explicit transform exists
    final explicit = _explicitTransforms[_key(source, target)];
    if (explicit != null) return ConnectionValidity.explicit(explicit);

    return ConnectionValidity.incompatible;
  }

  /// Apply transform to value
  dynamic transform(dynamic value, PortType source, PortType target) {
    if (source == target) return value;
    final fn = _implicitTransforms[_key(source, target)]
            ?? _explicitTransforms[_key(source, target)];
    if (fn == null) throw StateError('No transform: $source → $target');
    return fn(value);
  }
}
```

### Implicit Coercion Table

| Source | Target | Conversion | Example |
|--------|--------|-----------|---------|
| `integer` | `float` | `value.toDouble()` | 5 → 5.0 |
| `float` | `integer` | `value.round()` | 5.7 → 6 |
| `boolean` | `trigger` | `if (value) emit trigger` | true → bang |
| `boolean` | `integer` | `value ? 1 : 0` | true → 1 |
| `boolean` | `float` | `value ? 1.0 : 0.0` | false → 0.0 |
| `integer` | `boolean` | `value != 0` | 5 → true |
| `float` | `boolean` | `value != 0.0` | 0.0 → false |
| `integer` | `string` | `value.toString()` | 42 → "42" |
| `float` | `string` | `value.toStringAsFixed(3)` | 3.14 → "3.140" |
| `string` | `integer` | `int.tryParse(value) ?? 0` | "42" → 42 |
| `string` | `float` | `double.tryParse(value) ?? 0.0` | "3.14" → 3.14 |
| `trigger` | `boolean` | Always `true` on trigger | bang → true |

### Incompatible Types (Connection Refused)

| Source | Target | Reason |
|--------|--------|--------|
| `audioBuffer` | ANY control type | Audio buffers are Rust-only |
| ANY control type | `audioBuffer` | Cannot create audio from control |
| `voiceHandle` | `busHandle` | Different handle types |
| `curveData` | scalar types | Curve is complex structure |

### Wire Transform Visualization

U editoru, žice sa implicitnom konverzijom imaju mali ikonu na sredini:

```
[float] ───── → ─────[int]     (bez ikonice = direct)
[bool]  ──── ◆ → ────[trigger] (◆ = implicit transform)
[float] ── ⚡ → ──[string]     (⚡ = explicit transform, user-inserted)
[audio] ── ✕ → ──[float]      (✕ = incompatible, red dashed line)
```

---

## 35. Graph Instance & Pool Management

### GraphInstance — Runtime Representation

```dart
class GraphInstance {
  final String graphId;
  final String instanceId; // Unique per activation
  final CompiledGraph compiled;
  final WireState wires;
  final List<GraphNode> nodes; // Instantiated node objects
  final GraphContext context;

  GraphInstanceState _state = GraphInstanceState.pooled;
  int _activationTick = 0;
  Event? _triggerEvent;

  // Voice tracking
  final Set<int> _activeVoiceIds = {};
  int get activeVoiceCount => _activeVoiceIds.length;

  /// Activate instance for event processing
  void activate(Event event, int tick) {
    assert(_state == GraphInstanceState.pooled || _state == GraphInstanceState.done);
    _state = GraphInstanceState.allocated;
    _triggerEvent = event;
    _activationTick = tick;

    // Initialize all nodes
    for (final node in nodes) {
      node.initialize(context);
    }

    // Inject event data into entry nodes
    for (final nodeId in compiled.controlOrder) {
      final node = nodes.firstWhere((n) => n.id == nodeId);
      if (node is EventEntryNode) {
        wires.write(nodeId, 'trigger', true, tick);
        wires.write(nodeId, 'eventId', event.id, tick);
        wires.write(nodeId, 'payload', event.payload, tick);
        wires.write(nodeId, 'timestamp', event.timestamp, tick);
      }
    }

    _state = GraphInstanceState.executing;
  }

  /// Process one control-rate tick
  void tick(int tick) {
    if (_state != GraphInstanceState.executing) return;

    bool anyActive = false;
    for (final nodeId in compiled.controlOrder) {
      final node = nodes.firstWhere((n) => n.id == nodeId);
      if (node.needsUpdate(wires, tick)) {
        node.process(wires, tick, context);
        anyActive = true;

        // Forward pending commands to audio engine
        for (final cmd in node.pendingCommands) {
          context.audioCommandSink.send(cmd);
          if (cmd is StartVoiceCommand) {
            _activeVoiceIds.add(cmd.voiceId);
          }
        }
        node.pendingCommands.clear();
      }
    }

    // Check if graph is done (no active nodes, no active voices)
    if (!anyActive && _activeVoiceIds.isEmpty) {
      _state = GraphInstanceState.done;
    }
  }

  /// Notify that a voice has finished
  void onVoiceFinished(int voiceId) {
    _activeVoiceIds.remove(voiceId);
    if (_activeVoiceIds.isEmpty && _state == GraphInstanceState.finishing) {
      _state = GraphInstanceState.done;
    }
  }

  /// Gracefully stop — let voices fade out
  void stop({Duration fadeOut = const Duration(milliseconds: 100)}) {
    _state = GraphInstanceState.finishing;
    // Send stop commands for all active voices
    for (final voiceId in _activeVoiceIds) {
      context.audioCommandSink.send(
        StopVoiceCommand(voiceId: voiceId, fadeSamples: (fadeOut.inMicroseconds * 44.1 / 1000).round()),
      );
    }
  }

  /// Reset for pool recycling
  void recycle() {
    for (final node in nodes) {
      node.reset();
    }
    wires.clear();
    _activeVoiceIds.clear();
    _triggerEvent = null;
    _state = GraphInstanceState.pooled;
  }

  bool get isDone => _state == GraphInstanceState.done;
  bool get isActive => _state == GraphInstanceState.executing || _state == GraphInstanceState.finishing;
}
```

### GraphInstancePool

```dart
class GraphInstancePool {
  final Map<String, Queue<GraphInstance>> _pools = {};
  final Map<String, int> _poolSizes = {};

  int _totalAllocated = 0;
  static const int kMaxTotalInstances = 100;
  static const int kDefaultPoolSize = 4;

  /// Get or create instance for a graph
  GraphInstance acquire(String graphId, CompiledGraph compiled, GraphContext context) {
    final pool = _pools[graphId];

    // Try to get from pool
    if (pool != null && pool.isNotEmpty) {
      final instance = pool.removeFirst();
      return instance;
    }

    // Check hard limit
    if (_totalAllocated >= kMaxTotalInstances) {
      // Force recycle oldest instance across all pools
      _forceRecycleOldest();
    }

    // Create new instance
    _totalAllocated++;
    return GraphInstance(
      graphId: graphId,
      instanceId: '${graphId}_${_totalAllocated}',
      compiled: compiled,
      wires: WireState.fromCompiled(compiled),
      nodes: _instantiateNodes(compiled),
      context: context,
    );
  }

  /// Return instance to pool
  void release(GraphInstance instance) {
    instance.recycle();
    final poolSize = _poolSizes[instance.graphId] ?? kDefaultPoolSize;
    final pool = _pools.putIfAbsent(instance.graphId, () => Queue());

    if (pool.length < poolSize) {
      pool.addLast(instance);
    } else {
      // Pool full — discard instance
      _totalAllocated--;
    }
  }

  /// Pre-warm pool for frequently used graphs
  void preWarm(String graphId, CompiledGraph compiled, GraphContext context, {int count = 2}) {
    _poolSizes[graphId] = count;
    final pool = _pools.putIfAbsent(graphId, () => Queue());
    while (pool.length < count) {
      _totalAllocated++;
      pool.addLast(GraphInstance(
        graphId: graphId,
        instanceId: '${graphId}_prewarm_${pool.length}',
        compiled: compiled,
        wires: WireState.fromCompiled(compiled),
        nodes: _instantiateNodes(compiled),
        context: context,
      ));
    }
  }

  /// Pool statistics for debug overlay
  PoolStatistics get statistics => PoolStatistics(
    totalAllocated: _totalAllocated,
    totalPooled: _pools.values.fold(0, (sum, q) => sum + q.length),
    perGraph: _pools.map((k, v) => MapEntry(k, v.length)),
  );
}
```

---

## 36. Voice Manager (Rust Implementation)

Kompletna Rust implementacija voice menadžmenta — pool, lifecycle, stealing, virtualization.

```rust
// rf-engine/src/hook_graph/voice_manager.rs

pub struct VoiceManager {
    /// Pre-allocated voice pool
    voices: Vec<Voice>,
    /// Free list (indices into voices)
    free_list: Vec<usize>,
    /// Active voices sorted by priority (for stealing)
    active_sorted: Vec<usize>,
    /// Maximum simultaneous voices
    max_voices: usize,
    /// Stealing policy
    steal_policy: StealPolicy,
    /// Voice group limits
    group_limits: HashMap<u32, GroupLimit>,
    /// Feedback to Dart (voice finished events)
    feedback_tx: rtrb::Producer<VoiceFeedback>,
}

#[derive(Clone)]
pub struct Voice {
    state: VoiceState,
    asset_id: u32,
    graph_instance_id: u32,
    priority: i32,
    /// Current volume (with fades applied)
    volume: f32,
    /// Target volume (before fade)
    target_volume: f32,
    /// Fade state
    fade: FadeState,
    /// Playback position (samples)
    position: u64,
    /// Loop state
    loop_info: LoopInfo,
    /// Voice group ID (for group limits)
    group_id: u32,
    /// Creation tick (for age-based stealing)
    created_tick: u64,
    /// Is this voice "virtual" (inaudible, skip DSP)
    is_virtual: bool,
    /// Peak level from last buffer (for virtualization check)
    peak_level: f32,
    /// Pre-allocated per-voice DSP state
    dsp_state: VoiceDspState,
}

#[derive(Clone, Copy, PartialEq)]
pub enum VoiceState {
    Free,
    Starting,  // Fade-in in progress
    Playing,   // Normal playback
    Looping,   // Loop playback
    Stopping,  // Fade-out in progress
    Virtual,   // Inaudible — skip DSP but track position
}

struct FadeState {
    current: f32,       // 0.0 → 1.0
    target: f32,        // 0.0 (fade out) or 1.0 (fade in)
    increment: f32,     // Per-sample increment
    samples_remaining: u32,
}

struct LoopInfo {
    enabled: bool,
    count: i32,        // -1 = infinite
    current_loop: i32,
    loop_start: u64,   // Sample position
    loop_end: u64,     // Sample position
}

pub struct GroupLimit {
    max_voices: usize,
    steal_mode: StealPolicy,
}

#[derive(Clone, Copy)]
pub enum StealPolicy {
    Oldest,
    Quietest,
    LowestPriority,
    None, // Don't steal — reject new voice
}

impl VoiceManager {
    pub fn new(max_voices: usize, steal_policy: StealPolicy) -> Self {
        let mut voices = Vec::with_capacity(max_voices);
        let mut free_list = Vec::with_capacity(max_voices);
        for i in 0..max_voices {
            voices.push(Voice::default());
            free_list.push(i);
        }
        Self {
            voices,
            free_list,
            active_sorted: Vec::with_capacity(max_voices),
            max_voices,
            steal_policy,
            group_limits: HashMap::new(),
            feedback_tx: /* initialized elsewhere */,
        }
    }

    /// Allocate a voice — may steal if pool is exhausted
    pub fn start_voice(&mut self, params: VoiceParams) -> Option<usize> {
        // 1. Check group limit
        if let Some(limit) = self.group_limits.get(&params.group_id) {
            let group_count = self.active_sorted.iter()
                .filter(|&&i| self.voices[i].group_id == params.group_id)
                .count();
            if group_count >= limit.max_voices {
                // Steal within group
                if let Some(stolen) = self.steal_from_group(params.group_id, limit.steal_mode) {
                    self.stop_voice_immediate(stolen);
                } else {
                    return None; // Can't steal, reject
                }
            }
        }

        // 2. Get free voice
        let voice_idx = if let Some(idx) = self.free_list.pop() {
            idx
        } else {
            // Pool exhausted — steal globally
            match self.steal_global() {
                Some(idx) => {
                    self.stop_voice_immediate(idx);
                    idx
                }
                None => return None, // StealPolicy::None
            }
        };

        // 3. Initialize voice
        let voice = &mut self.voices[voice_idx];
        voice.state = VoiceState::Starting;
        voice.asset_id = params.asset_id;
        voice.graph_instance_id = params.graph_instance_id;
        voice.priority = params.priority;
        voice.target_volume = params.volume;
        voice.volume = 0.0;
        voice.fade = FadeState::fade_in(params.fade_in_samples);
        voice.position = params.start_position;
        voice.loop_info = params.loop_info;
        voice.group_id = params.group_id;
        voice.created_tick = params.tick;
        voice.is_virtual = false;
        voice.peak_level = 0.0;

        // 4. Insert into active list (sorted by priority)
        let insert_pos = self.active_sorted.partition_point(|&i| {
            self.voices[i].priority >= params.priority
        });
        self.active_sorted.insert(insert_pos, voice_idx);

        Some(voice_idx)
    }

    /// Stop voice with fade-out
    pub fn stop_voice(&mut self, voice_idx: usize, fade_out_samples: u32) {
        let voice = &mut self.voices[voice_idx];
        if voice.state == VoiceState::Free { return; }

        voice.state = VoiceState::Stopping;
        voice.fade = FadeState::fade_out(fade_out_samples);
    }

    /// Process all active voices — called from audio callback
    pub fn process(&mut self, output: &mut [f32], buffer_size: usize, assets: &AssetManager) {
        let mut voices_to_free = Vec::new();

        for &voice_idx in &self.active_sorted {
            let voice = &mut self.voices[voice_idx];

            // Skip virtual voices (but advance position)
            if voice.is_virtual {
                voice.position += buffer_size as u64;
                self.check_loop(voice);
                continue;
            }

            // Get audio data from asset
            let asset = match assets.get(voice.asset_id) {
                Some(a) => a,
                None => {
                    voices_to_free.push(voice_idx);
                    continue;
                }
            };

            // Mix voice into output buffer
            for i in 0..buffer_size {
                // Advance fade
                voice.fade.advance();
                let fade_gain = voice.fade.current;

                // Get sample
                let sample = if voice.position < asset.len() as u64 {
                    asset.sample_at(voice.position as usize)
                } else {
                    0.0
                };

                // Apply volume and fade
                let out_sample = sample * voice.target_volume * fade_gain;
                output[i * 2] += out_sample; // Left
                output[i * 2 + 1] += out_sample; // Right (mono-to-stereo)

                // Track peak
                let abs = out_sample.abs();
                if abs > voice.peak_level {
                    voice.peak_level = abs;
                }

                // Advance position
                voice.position += 1;
            }

            // Check loop
            self.check_loop(voice);

            // Check if fade-out complete
            if voice.state == VoiceState::Stopping && voice.fade.is_done() {
                voices_to_free.push(voice_idx);
            }

            // Check if playback complete (non-looping)
            if !voice.loop_info.enabled && voice.position >= asset.len() as u64 {
                voices_to_free.push(voice_idx);
            }

            // Virtualization: if peak is below threshold, virtualize
            if voice.peak_level < 0.001 && voice.state == VoiceState::Playing {
                voice.is_virtual = true;
                voice.state = VoiceState::Virtual;
            } else if voice.state == VoiceState::Starting && voice.fade.is_done() {
                voice.state = VoiceState::Playing;
            }

            // Reset peak for next buffer
            voice.peak_level = 0.0;
        }

        // Free completed voices
        for idx in voices_to_free {
            self.free_voice(idx);
        }
    }

    fn free_voice(&mut self, voice_idx: usize) {
        let voice = &mut self.voices[voice_idx];
        let graph_id = voice.graph_instance_id;
        voice.state = VoiceState::Free;

        self.active_sorted.retain(|&i| i != voice_idx);
        self.free_list.push(voice_idx);

        // Notify Dart
        let _ = self.feedback_tx.push(VoiceFeedback::VoiceFinished {
            voice_idx: voice_idx as u32,
            graph_instance_id: graph_id,
        });
    }

    fn steal_global(&self) -> Option<usize> {
        match self.steal_policy {
            StealPolicy::Oldest => {
                self.active_sorted.iter()
                    .filter(|&&i| self.voices[i].state == VoiceState::Playing)
                    .min_by_key(|&&i| self.voices[i].created_tick)
                    .copied()
            }
            StealPolicy::Quietest => {
                self.active_sorted.iter()
                    .filter(|&&i| self.voices[i].state == VoiceState::Playing)
                    .min_by(|&&a, &&b| {
                        self.voices[a].peak_level.partial_cmp(&self.voices[b].peak_level)
                            .unwrap_or(std::cmp::Ordering::Equal)
                    })
                    .copied()
            }
            StealPolicy::LowestPriority => {
                self.active_sorted.last().copied()
            }
            StealPolicy::None => None,
        }
    }

    /// Mix all active voices to output — convenience wrapper
    pub fn mix_to_output(&mut self, output: &mut [f32], buffer_size: usize) {
        // Clear output buffer
        for s in output.iter_mut() {
            *s = 0.0;
        }
        // Process mixes into output
        self.process(output, buffer_size, /* asset_manager */);
    }

    /// Get voice count for debug
    pub fn active_count(&self) -> u32 {
        self.active_sorted.len() as u32
    }

    pub fn virtual_count(&self) -> u32 {
        self.active_sorted.iter()
            .filter(|&&i| self.voices[i].is_virtual)
            .count() as u32
    }
}
```

---

## 37. Graph Validation Engine

Kompajler validacija sa detaljnim greškama i predlozima za popravku.

```dart
class GraphValidator {
  /// Validate graph definition — returns all errors and warnings
  GraphValidationResult validate(HookGraphDefinition graph) {
    final errors = <GraphValidationError>[];
    final warnings = <GraphValidationWarning>[];

    // Run all validation rules
    for (final rule in _rules) {
      rule.validate(graph, errors, warnings);
    }

    return GraphValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  final List<ValidationRule> _rules = [
    // --- Structural Rules ---
    CycleDetectionRule(),
    OrphanNodeRule(),
    DisconnectedSubgraphRule(),
    MissingRequiredConnectionRule(),
    DuplicateNodeIdRule(),
    DuplicateConnectionRule(),

    // --- Type Rules ---
    PortTypeCompatibilityRule(),
    WireTransformValidityRule(),
    PortDirectionRule(),
    MultipleConnectionToInputRule(), // Inputs accept only one connection

    // --- Semantic Rules ---
    EventEntryRequiredRule(),        // Graph must have at least one EventEntry
    OutputRequiredRule(),            // Graph must have at least one audio output
    UnreachableNodeRule(),           // Warn about nodes not reachable from entry
    InfiniteLoopDetectionRule(),     // EmitEvent → same event recursion
    SubgraphDepthRule(),             // Max 8 levels
    MaxNodeCountRule(),              // Warn if > 200 nodes
    MaxConnectionCountRule(),        // Warn if > 500 connections

    // --- Performance Rules ---
    AudioRateNodeInControlPath(),    // Warning: DSP node without audio connection
    ExcessiveVoiceCountRule(),       // Warn if estimated voices > 32
    UnboundRTPCRule(),               // Warning: RTPC input not bound to parameter
    DeadBranchRule(),                // Warning: switch case with no connections

    // --- SlotLab-Specific Rules ---
    WinTierHardcodeRule(),           // Error: hardcoded tier values in WinTierNode
    DeterminismViolationRule(),      // Error: DateTime.now() in deterministic graph
    MissingCooldownRule(),           // Warning: NearMiss without cooldown
    MissingFadeRule(),               // Warning: StopSound without fadeOut

    // --- Container Rules ---
    EmptyContainerRule(),            // Error: container with no children
    ContainerNestingDepthRule(),     // Warning: > 5 levels of container nesting
    SwitchMissingDefaultRule(),      // Warning: switch without default case
  ];
}
```

### Error Taxonomy

```dart
class GraphValidationError {
  final String ruleId;            // "CYCLE_DETECTED", "TYPE_MISMATCH", etc.
  final GraphValidationSeverity severity;
  final String message;           // Human-readable description
  final String? nodeId;           // Affected node (nullable for graph-level errors)
  final String? connectionId;     // Affected connection
  final String? suggestion;       // Auto-fix suggestion
  final AutoFix? autoFix;         // Executable auto-fix (if available)
}

enum GraphValidationSeverity {
  error,    // Blocks compilation — MUST fix
  warning,  // Compiles but may cause issues
  info,     // Optimization suggestion
}

/// Auto-fixable issues
abstract class AutoFix {
  String get description;
  HookGraphDefinition apply(HookGraphDefinition graph);
}

class InsertTransformFix extends AutoFix {
  final String connectionId;
  final WireTransform transform;
  @override String get description => 'Insert type transform on connection';
  @override HookGraphDefinition apply(HookGraphDefinition graph) {
    // Clone graph with transform added to connection
  }
}

class RemoveOrphanFix extends AutoFix {
  final String nodeId;
  @override String get description => 'Remove disconnected node "$nodeId"';
  @override HookGraphDefinition apply(HookGraphDefinition graph) {
    // Clone graph without the orphan node
  }
}

class AddDefaultCaseFix extends AutoFix {
  final String switchNodeId;
  @override String get description => 'Add default case to switch';
  @override HookGraphDefinition apply(HookGraphDefinition graph) {
    // Clone graph with default case added
  }
}
```

### Validation Rule Example — Cycle Detection

```dart
class CycleDetectionRule extends ValidationRule {
  @override
  void validate(HookGraphDefinition graph, List<GraphValidationError> errors, _) {
    // Kahn's algorithm for topological sort
    final inDegree = <String, int>{};
    final adjacency = <String, List<String>>{};

    for (final node in graph.nodes.keys) {
      inDegree[node] = 0;
      adjacency[node] = [];
    }

    for (final conn in graph.connections) {
      inDegree[conn.targetNodeId] = (inDegree[conn.targetNodeId] ?? 0) + 1;
      adjacency[conn.sourceNodeId]!.add(conn.targetNodeId);
    }

    final queue = Queue<String>();
    for (final entry in inDegree.entries) {
      if (entry.value == 0) queue.add(entry.key);
    }

    int visited = 0;
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      visited++;
      for (final neighbor in adjacency[node]!) {
        inDegree[neighbor] = inDegree[neighbor]! - 1;
        if (inDegree[neighbor] == 0) queue.add(neighbor);
      }
    }

    if (visited != graph.nodes.length) {
      // Find nodes in cycle
      final cycleNodes = inDegree.entries
          .where((e) => e.value > 0)
          .map((e) => e.key)
          .toList();

      errors.add(GraphValidationError(
        ruleId: 'CYCLE_DETECTED',
        severity: GraphValidationSeverity.error,
        message: 'Graph contains a cycle involving nodes: ${cycleNodes.join(", ")}',
        suggestion: 'Break the cycle by removing one connection in the loop. '
                     'If you need feedback, use a VariableNode or StateStoreNode instead.',
      ));
    }
  }
}
```

---

## 38. Undo/Redo Command System

Command pattern za editor — svaka akcija je reversibilna.

```dart
/// Base command
abstract class GraphEditorCommand {
  String get description;
  void execute(GraphEditorState state);
  void undo(GraphEditorState state);
}

/// Command history manager
class CommandHistory {
  final List<GraphEditorCommand> _undoStack = [];
  final List<GraphEditorCommand> _redoStack = [];
  static const int kMaxHistorySize = 500;

  void execute(GraphEditorCommand command, GraphEditorState state) {
    command.execute(state);
    _undoStack.add(command);
    _redoStack.clear(); // New action invalidates redo history

    // Trim if too large
    if (_undoStack.length > kMaxHistorySize) {
      _undoStack.removeAt(0);
    }
  }

  void undo(GraphEditorState state) {
    if (_undoStack.isEmpty) return;
    final command = _undoStack.removeLast();
    command.undo(state);
    _redoStack.add(command);
  }

  void redo(GraphEditorState state) {
    if (_redoStack.isEmpty) return;
    final command = _redoStack.removeLast();
    command.execute(state);
    _undoStack.add(command);
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  String? get undoDescription => _undoStack.lastOrNull?.description;
  String? get redoDescription => _redoStack.lastOrNull?.description;
}
```

### Concrete Commands

```dart
class AddNodeCommand extends GraphEditorCommand {
  final GraphNode node;
  @override String get description => 'Add ${node.typeId}';
  @override void execute(GraphEditorState state) => state.addNode(node);
  @override void undo(GraphEditorState state) => state.removeNode(node.id);
}

class RemoveNodeCommand extends GraphEditorCommand {
  final GraphNode node;
  final List<GraphConnection> removedConnections; // Saved for undo
  @override String get description => 'Remove ${node.typeId}';
  @override void execute(GraphEditorState state) {
    removedConnections.addAll(state.getConnectionsFor(node.id));
    state.removeNode(node.id);
  }
  @override void undo(GraphEditorState state) {
    state.addNode(node);
    for (final conn in removedConnections) {
      state.addConnection(conn);
    }
  }
}

class MoveNodeCommand extends GraphEditorCommand {
  final String nodeId;
  final Offset oldPosition;
  final Offset newPosition;
  @override String get description => 'Move node';
  @override void execute(GraphEditorState state) => state.setNodePosition(nodeId, newPosition);
  @override void undo(GraphEditorState state) => state.setNodePosition(nodeId, oldPosition);
}

class AddConnectionCommand extends GraphEditorCommand {
  final GraphConnection connection;
  @override String get description => 'Connect ${connection.sourceNodeId} → ${connection.targetNodeId}';
  @override void execute(GraphEditorState state) => state.addConnection(connection);
  @override void undo(GraphEditorState state) => state.removeConnection(connection);
}

class RemoveConnectionCommand extends GraphEditorCommand {
  final GraphConnection connection;
  @override String get description => 'Disconnect';
  @override void execute(GraphEditorState state) => state.removeConnection(connection);
  @override void undo(GraphEditorState state) => state.addConnection(connection);
}

class ChangeParameterCommand extends GraphEditorCommand {
  final String nodeId;
  final String paramName;
  final dynamic oldValue;
  final dynamic newValue;
  @override String get description => 'Change $paramName';
  @override void execute(GraphEditorState state) => state.setNodeParameter(nodeId, paramName, newValue);
  @override void undo(GraphEditorState state) => state.setNodeParameter(nodeId, paramName, oldValue);
}

/// Batch multiple commands as one undo step
class CompoundCommand extends GraphEditorCommand {
  final String label;
  final List<GraphEditorCommand> commands;
  @override String get description => label;
  @override void execute(GraphEditorState state) {
    for (final cmd in commands) { cmd.execute(state); }
  }
  @override void undo(GraphEditorState state) {
    for (final cmd in commands.reversed) { cmd.undo(state); }
  }
}

/// Paste nodes (compound: add N nodes + M connections)
class PasteCommand extends CompoundCommand {
  PasteCommand({required List<GraphNode> nodes, required List<GraphConnection> connections})
    : super(
        label: 'Paste ${nodes.length} nodes',
        commands: [
          ...nodes.map((n) => AddNodeCommand(node: n)),
          ...connections.map((c) => AddConnectionCommand(connection: c)),
        ],
      );
}
```

---

## 39. Complete SlotLab Graph Examples

### Example 1: Basic Win Sound (Simplest Possible Graph)

```json
{
  "id": "basic_win_sound",
  "name": "Basic Win Sound",
  "version": 1,
  "format": "fhg1",
  "metadata": {
    "author": "FluxForge Template",
    "tags": ["win", "basic", "template"],
    "description": "Plays a single win sound on WIN_EVAL event"
  },
  "nodes": {
    "entry": {
      "type": "EventEntryNode",
      "position": {"x": 100, "y": 200},
      "parameters": {"eventName": "WIN_EVAL"}
    },
    "play": {
      "type": "PlaySoundNode",
      "position": {"x": 400, "y": 200},
      "parameters": {
        "asset": "audio/wins/generic_win.wav",
        "volume": 0.0,
        "loop": false,
        "fadeIn": 0.01
      }
    }
  },
  "connections": [
    {"source": {"node": "entry", "port": "trigger"}, "target": {"node": "play", "port": "trigger"}}
  ]
}
```

### Example 2: Tiered Win Celebration (Switch + Random)

```json
{
  "id": "tiered_win_celebration",
  "name": "Tiered Win Celebration",
  "version": 1,
  "format": "fhg1",
  "metadata": {
    "author": "FluxForge Template",
    "tags": ["win", "tiered", "celebration", "template"],
    "description": "Routes win events to tier-appropriate celebration sounds with randomization"
  },
  "nodes": {
    "entry": {
      "type": "EventEntryNode",
      "position": {"x": 50, "y": 250},
      "parameters": {"eventName": "WIN_EVAL"}
    },
    "extract_payload": {
      "type": "PayloadExtractNode",
      "position": {"x": 250, "y": 150},
      "parameters": {"fieldPath": "payload"}
    },
    "win_tier": {
      "type": "WinTierNode",
      "position": {"x": 450, "y": 250},
      "parameters": {}
    },
    "switch_tier": {
      "type": "SwitchNode",
      "position": {"x": 700, "y": 250},
      "parameters": {"cases": ["WIN_1", "WIN_2", "WIN_3", "WIN_4", "WIN_5"]}
    },
    "random_small": {
      "type": "ProbabilityNode",
      "position": {"x": 950, "y": 50},
      "parameters": {
        "options": [
          {"weight": 40, "label": "variant_a"},
          {"weight": 35, "label": "variant_b"},
          {"weight": 25, "label": "variant_c"}
        ],
        "avoidRepeat": true,
        "avoidRepeatCount": 2
      }
    },
    "play_small_a": {
      "type": "PlaySoundNode",
      "position": {"x": 1200, "y": 20},
      "parameters": {"asset": "audio/wins/small_win_01.wav", "volume": -3.0}
    },
    "play_small_b": {
      "type": "PlaySoundNode",
      "position": {"x": 1200, "y": 60},
      "parameters": {"asset": "audio/wins/small_win_02.wav", "volume": -3.0}
    },
    "play_small_c": {
      "type": "PlaySoundNode",
      "position": {"x": 1200, "y": 100},
      "parameters": {"asset": "audio/wins/small_win_03.wav", "volume": -3.0}
    },
    "play_medium": {
      "type": "PlaySoundNode",
      "position": {"x": 950, "y": 200},
      "parameters": {"asset": "audio/wins/medium_win.wav", "volume": 0.0}
    },
    "duck_music": {
      "type": "DuckNode",
      "position": {"x": 950, "y": 350},
      "parameters": {
        "targetLayers": ["BASE"],
        "duckAmount": -12.0,
        "attackTime": 50,
        "releaseTime": 500
      }
    },
    "play_big": {
      "type": "MultiPlayNode",
      "position": {"x": 1200, "y": 350},
      "parameters": {
        "soundCount": 3,
        "asset_0": "audio/wins/big_fanfare.wav",
        "asset_1": "audio/wins/crowd_cheer.wav",
        "asset_2": "audio/wins/coin_shower.wav",
        "volume_0": 0.0,
        "volume_1": -3.0,
        "volume_2": -6.0,
        "delay_0": 0.0,
        "delay_1": 0.2,
        "delay_2": 0.5
      }
    },
    "play_huge": {
      "type": "SubgraphNode",
      "position": {"x": 950, "y": 450},
      "parameters": {"graphId": "huge_win_sequence"}
    },
    "play_mega": {
      "type": "SubgraphNode",
      "position": {"x": 950, "y": 550},
      "parameters": {"graphId": "mega_win_sequence"}
    }
  },
  "connections": [
    {"source": {"node": "entry", "port": "trigger"}, "target": {"node": "win_tier", "port": "trigger"}},
    {"source": {"node": "entry", "port": "payload"}, "target": {"node": "extract_payload", "port": "payload"}},
    {"source": {"node": "extract_payload", "port": "value"}, "target": {"node": "win_tier", "port": "payload"}},
    {"source": {"node": "win_tier", "port": "tier"}, "target": {"node": "switch_tier", "port": "selector"}},
    {"source": {"node": "switch_tier", "port": "WIN_1"}, "target": {"node": "random_small", "port": "trigger"}},
    {"source": {"node": "random_small", "port": "variant_a"}, "target": {"node": "play_small_a", "port": "trigger"}},
    {"source": {"node": "random_small", "port": "variant_b"}, "target": {"node": "play_small_b", "port": "trigger"}},
    {"source": {"node": "random_small", "port": "variant_c"}, "target": {"node": "play_small_c", "port": "trigger"}},
    {"source": {"node": "switch_tier", "port": "WIN_2"}, "target": {"node": "play_medium", "port": "trigger"}},
    {"source": {"node": "switch_tier", "port": "WIN_3"}, "target": {"node": "duck_music", "port": "trigger"}},
    {"source": {"node": "switch_tier", "port": "WIN_3"}, "target": {"node": "play_big", "port": "trigger"}},
    {"source": {"node": "switch_tier", "port": "WIN_4"}, "target": {"node": "duck_music", "port": "trigger"}},
    {"source": {"node": "switch_tier", "port": "WIN_4"}, "target": {"node": "play_huge", "port": "trigger"}},
    {"source": {"node": "switch_tier", "port": "WIN_5"}, "target": {"node": "duck_music", "port": "trigger"}},
    {"source": {"node": "switch_tier", "port": "WIN_5"}, "target": {"node": "play_mega", "port": "trigger"}}
  ]
}
```

### Example 3: Reel Stop with Anticipation

```json
{
  "id": "reel_stop_anticipation",
  "name": "Reel Stop with Anticipation",
  "version": 1,
  "format": "fhg1",
  "metadata": {
    "tags": ["reel", "stop", "anticipation", "near-miss"],
    "description": "Plays reel stop sounds with near-miss anticipation detection"
  },
  "nodes": {
    "entry": {
      "type": "EventEntryNode",
      "position": {"x": 50, "y": 200},
      "parameters": {"eventName": "REEL_STOP"}
    },
    "reel_info": {
      "type": "ReelAnalyzerNode",
      "position": {"x": 250, "y": 200},
      "parameters": {}
    },
    "random_stop": {
      "type": "ProbabilityNode",
      "position": {"x": 500, "y": 100},
      "parameters": {
        "options": [
          {"weight": 33, "label": "stop_1"},
          {"weight": 33, "label": "stop_2"},
          {"weight": 34, "label": "stop_3"}
        ],
        "avoidRepeat": true,
        "avoidRepeatCount": 1
      }
    },
    "play_stop_1": {
      "type": "PlaySoundNode",
      "position": {"x": 750, "y": 50},
      "parameters": {"asset": "audio/reels/reel_stop_01.wav", "volume": -6.0}
    },
    "play_stop_2": {
      "type": "PlaySoundNode",
      "position": {"x": 750, "y": 100},
      "parameters": {"asset": "audio/reels/reel_stop_02.wav", "volume": -6.0}
    },
    "play_stop_3": {
      "type": "PlaySoundNode",
      "position": {"x": 750, "y": 150},
      "parameters": {"asset": "audio/reels/reel_stop_03.wav", "volume": -6.0}
    },
    "anticipation": {
      "type": "AnticipationNode",
      "position": {"x": 500, "y": 300},
      "parameters": {}
    },
    "cooldown": {
      "type": "CooldownNode",
      "position": {"x": 750, "y": 300},
      "parameters": {}
    },
    "ramp_intensity": {
      "type": "RampNode",
      "position": {"x": 950, "y": 300},
      "parameters": {"curve": "easeIn"}
    },
    "play_anticipation": {
      "type": "PlaySoundNode",
      "position": {"x": 1150, "y": 250},
      "parameters": {"asset": "audio/anticipation/scatter_swell.wav", "volume": -3.0}
    },
    "set_rtpc": {
      "type": "SetVoiceParamNode",
      "position": {"x": 1150, "y": 350},
      "parameters": {"param": "volume"}
    }
  },
  "connections": [
    {"source": {"node": "entry", "port": "trigger"}, "target": {"node": "random_stop", "port": "trigger"}},
    {"source": {"node": "entry", "port": "payload"}, "target": {"node": "reel_info", "port": "payload"}},
    {"source": {"node": "random_stop", "port": "stop_1"}, "target": {"node": "play_stop_1", "port": "trigger"}},
    {"source": {"node": "random_stop", "port": "stop_2"}, "target": {"node": "play_stop_2", "port": "trigger"}},
    {"source": {"node": "random_stop", "port": "stop_3"}, "target": {"node": "play_stop_3", "port": "trigger"}},
    {"source": {"node": "reel_info", "port": "isNearMiss"}, "target": {"node": "anticipation", "port": "trigger"}},
    {"source": {"node": "reel_info", "port": "scatterCount"}, "target": {"node": "anticipation", "port": "scatterCount"}},
    {"source": {"node": "anticipation", "port": "trigger"}, "target": {"node": "cooldown", "port": "trigger"}},
    {"source": {"node": "cooldown", "port": "passed"}, "target": {"node": "play_anticipation", "port": "trigger"}},
    {"source": {"node": "cooldown", "port": "passed"}, "target": {"node": "ramp_intensity", "port": "start"}},
    {"source": {"node": "anticipation", "port": "anticipationLevel"}, "target": {"node": "ramp_intensity", "port": "endValue"}},
    {"source": {"node": "play_anticipation", "port": "voice"}, "target": {"node": "set_rtpc", "port": "voice"}},
    {"source": {"node": "ramp_intensity", "port": "value"}, "target": {"node": "set_rtpc", "port": "value"}}
  ]
}
```

### Example 4: Feature Transition (Free Spins Entry)

```json
{
  "id": "feature_freespin_entry",
  "name": "Free Spins Entry Transition",
  "version": 1,
  "format": "fhg1",
  "metadata": {
    "tags": ["feature", "freespins", "transition", "music"],
    "description": "Orchestrates audio transition from base game to free spins"
  },
  "nodes": {
    "entry": {
      "type": "EventEntryNode",
      "position": {"x": 50, "y": 250},
      "parameters": {"eventName": "FEATURE_START"}
    },
    "feature_check": {
      "type": "FeatureStateNode",
      "position": {"x": 250, "y": 250},
      "parameters": {}
    },
    "is_freespin": {
      "type": "CompareNode",
      "position": {"x": 450, "y": 250},
      "parameters": {"operator": "eq"}
    },
    "gate": {
      "type": "GateNode",
      "position": {"x": 650, "y": 250},
      "parameters": {}
    },
    "layer_fade_out": {
      "type": "LayerFadeNode",
      "position": {"x": 850, "y": 100},
      "parameters": {"layerName": "BASE", "targetVolume": -60.0, "fadeTime": 1.5}
    },
    "delay_transition": {
      "type": "DelayNode",
      "position": {"x": 850, "y": 250},
      "parameters": {}
    },
    "play_transition": {
      "type": "PlaySoundNode",
      "position": {"x": 850, "y": 400},
      "parameters": {"asset": "audio/transitions/freespin_whoosh.wav", "volume": 0.0}
    },
    "layer_start": {
      "type": "LayerStartNode",
      "position": {"x": 1100, "y": 200},
      "parameters": {"layerName": "FREESPINS", "fadeIn": 2.0, "volume": 0.0}
    },
    "play_intro": {
      "type": "PlaySoundNode",
      "position": {"x": 1100, "y": 350},
      "parameters": {"asset": "audio/features/freespin_intro.wav", "volume": 0.0}
    }
  },
  "connections": [
    {"source": {"node": "entry", "port": "payload"}, "target": {"node": "feature_check", "port": "payload"}},
    {"source": {"node": "feature_check", "port": "currentFeature"}, "target": {"node": "is_freespin", "port": "a"}},
    {"source": {"node": "feature_check", "port": "isFreeSpins"}, "target": {"node": "gate", "port": "open"}},
    {"source": {"node": "entry", "port": "trigger"}, "target": {"node": "gate", "port": "input"}},
    {"source": {"node": "gate", "port": "output"}, "target": {"node": "layer_fade_out", "port": "trigger"}},
    {"source": {"node": "gate", "port": "output"}, "target": {"node": "play_transition", "port": "trigger"}},
    {"source": {"node": "gate", "port": "output"}, "target": {"node": "delay_transition", "port": "trigger"}},
    {"source": {"node": "layer_fade_out", "port": "done"}, "target": {"node": "layer_start", "port": "trigger"}},
    {"source": {"node": "delay_transition", "port": "delayed"}, "target": {"node": "play_intro", "port": "trigger"}}
  ]
}
```

### Example 5: Adaptive Ambient with Excitement

```json
{
  "id": "adaptive_ambient",
  "name": "Adaptive Casino Ambient",
  "version": 1,
  "format": "fhg1",
  "metadata": {
    "tags": ["ambient", "adaptive", "music", "excitement"],
    "description": "Blends casino ambient layers based on gameplay excitement level"
  },
  "nodes": {
    "rtpc_excitement": {
      "type": "RTPCInputNode",
      "position": {"x": 50, "y": 200},
      "parameters": {"parameterName": "Excitement"}
    },
    "rtpc_session": {
      "type": "RTPCInputNode",
      "position": {"x": 50, "y": 400},
      "parameters": {"parameterName": "SessionDuration"}
    },
    "excitement_mapper": {
      "type": "ExcitementMapperNode",
      "position": {"x": 300, "y": 200},
      "parameters": {}
    },
    "fatigue_check": {
      "type": "CompareNode",
      "position": {"x": 300, "y": 400},
      "parameters": {"operator": "gt"}
    },
    "blend_ambient": {
      "type": "LayerBlendNode",
      "position": {"x": 600, "y": 200},
      "parameters": {
        "layerA": "AMBIENT_CALM",
        "layerB": "AMBIENT_INTENSE",
        "blendTime": 3.0
      }
    },
    "fatigue_reduce": {
      "type": "LayerFadeNode",
      "position": {"x": 600, "y": 400},
      "parameters": {
        "layerName": "AMBIENT_INTENSE",
        "targetVolume": -12.0,
        "fadeTime": 10.0
      }
    }
  },
  "connections": [
    {"source": {"node": "rtpc_excitement", "port": "value"}, "target": {"node": "excitement_mapper", "port": "anticipationLevel"}},
    {"source": {"node": "excitement_mapper", "port": "excitement"}, "target": {"node": "blend_ambient", "port": "blendParam"}},
    {"source": {"node": "rtpc_session", "port": "value"}, "target": {"node": "fatigue_check", "port": "a"}},
    {"source": {"node": "fatigue_check", "port": "trueOut"}, "target": {"node": "fatigue_reduce", "port": "trigger"}}
  ]
}
```

---

## 40. Node Inspector Widget System

Svaki node tip ima specijalizovan inspector widget u property panelu.

```dart
/// Registry of node-specific inspector widgets
class NodeInspectorRegistry {
  static final Map<String, InspectorBuilder> _builders = {};

  static void register(String nodeTypeId, InspectorBuilder builder) {
    _builders[nodeTypeId] = builder;
  }

  static Widget build(GraphNode node, Function(String, dynamic) onChanged) {
    final builder = _builders[node.typeId];
    if (builder != null) {
      return builder(node, onChanged);
    }
    return DefaultNodeInspector(node: node, onChanged: onChanged);
  }
}

typedef InspectorBuilder = Widget Function(GraphNode node, Function(String, dynamic) onChanged);
```

### Default Inspector (Auto-generated)

```dart
class DefaultNodeInspector extends StatelessWidget {
  final GraphNode node;
  final Function(String, dynamic) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node header
        _buildHeader(),
        const Divider(),

        // Auto-generate fields from parameters
        for (final entry in node.parameters.entries)
          _buildParameterField(entry.key, entry.value),

        const Divider(),

        // Port info
        Text('Inputs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        for (final port in node.inputPorts)
          _buildPortInfo(port),
        const SizedBox(height: 8),
        Text('Outputs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        for (final port in node.outputPorts)
          _buildPortInfo(port),
      ],
    );
  }

  Widget _buildParameterField(String key, dynamic value) {
    if (value is bool) {
      return SwitchListTile(
        title: Text(key, style: TextStyle(fontSize: 12)),
        value: value,
        onChanged: (v) => onChanged(key, v),
        dense: true,
      );
    }
    if (value is int) {
      return _buildIntField(key, value);
    }
    if (value is double) {
      return _buildDoubleField(key, value);
    }
    if (value is String) {
      return _buildStringField(key, value);
    }
    if (value is List) {
      return _buildListField(key, value);
    }
    return Text('$key: $value (unsupported type)', style: TextStyle(fontSize: 11));
  }
}
```

### Specialized Inspectors

```dart
// ProbabilityNode inspector — visual weight bars with drag
class ProbabilityNodeInspector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Draggable weight bars
      for (int i = 0; i < options.length; i++)
        WeightBar(
          label: options[i].label,
          weight: options[i].weight,
          totalWeight: totalWeight,
          onWeightChanged: (w) => onChanged('options[$i].weight', w),
        ),
      // Add/remove option buttons
      Row(children: [
        IconButton(icon: Icon(Icons.add), onPressed: _addOption),
        IconButton(icon: Icon(Icons.remove), onPressed: _removeOption),
      ]),
      // Avoid repeat toggle
      SwitchListTile(title: Text('Avoid Repeat'), value: avoidRepeat, ...),
    ]);
  }
}

// RTPCInputNode inspector — shows curve editor
class RTPCInputNodeInspector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Parameter selector dropdown
      DropdownButtonFormField(
        items: rtpcManager.allParameters.map((p) => DropdownMenuItem(...)),
        value: node.parameters['parameterName'],
        onChanged: (v) => onChanged('parameterName', v),
      ),
      // Mapping curve editor
      CurveEditorWidget(
        curve: node.parameters['mappingCurve'],
        xLabel: 'Parameter Value',
        yLabel: 'Output Value',
        onCurveChanged: (c) => onChanged('mappingCurve', c),
      ),
    ]);
  }
}

// PlaySoundNode inspector — asset picker + preview
class PlaySoundNodeInspector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Asset file picker with preview button
      AssetPickerField(
        value: node.parameters['asset'],
        onChanged: (v) => onChanged('asset', v),
        onPreview: () => _previewSound(node.parameters['asset']),
      ),
      // Volume slider with dB display
      VolumeSlider(
        value: node.parameters['volume'],
        onChanged: (v) => onChanged('volume', v),
      ),
      // Pitch slider
      PitchSlider(value: node.parameters['pitch'], ...),
      // Pan knob
      PanKnob(value: node.parameters['pan'], ...),
      // Loop toggle + count
      SwitchListTile(title: Text('Loop'), value: node.parameters['loop'], ...),
    ]);
  }
}

// WinTierNode inspector — shows tier configuration (read-only, from WinTierConfig)
class WinTierNodeInspector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('Win Tier Configuration (from WinTierConfig)'),
      // Read-only table showing current tier thresholds
      DataTable(
        columns: [DataColumn(label: Text('Tier')), DataColumn(label: Text('Multiplier'))],
        rows: WinTierConfig.tiers.map((t) => DataRow(cells: [
          DataCell(Text(t.label)),
          DataCell(Text('${t.minMultiplier}x - ${t.maxMultiplier}x')),
        ])).toList(),
      ),
      // Warning: "Thresholds are data-driven — edit WinTierConfig, not this node"
      Text('Thresholds are data-driven', style: TextStyle(color: Colors.orange, fontSize: 10)),
    ]);
  }
}
```

---

## 41. Graph Template System

Pre-built šabloni za česte slot audio scenarije. Parametrizovani za brzu customizaciju.

```dart
class GraphTemplateManager {
  final List<GraphTemplate> _templates = [];

  /// Load built-in templates
  void loadBuiltIn() {
    _templates.addAll([
      GraphTemplate(
        id: 'basic_play',
        name: 'Basic Play',
        description: 'Event → Play Sound',
        category: 'Basic',
        parameters: [
          TemplateParameter('eventName', 'Event Name', TemplateParamType.string, 'WIN_EVAL'),
          TemplateParameter('soundAsset', 'Sound File', TemplateParamType.asset, ''),
          TemplateParameter('volume', 'Volume (dB)', TemplateParamType.float, 0.0),
        ],
        graphFactory: _createBasicPlayGraph,
      ),
      GraphTemplate(
        id: 'tiered_win',
        name: 'Tiered Win Celebration',
        description: 'Switch on win tier → different sounds per tier',
        category: 'Win',
        parameters: [
          TemplateParameter('tierCount', 'Number of Tiers', TemplateParamType.integer, 5),
          TemplateParameter('duckMusic', 'Duck Base Music', TemplateParamType.boolean, true),
          TemplateParameter('duckAmount', 'Duck Amount (dB)', TemplateParamType.float, -12.0),
        ],
        graphFactory: _createTieredWinGraph,
      ),
      GraphTemplate(
        id: 'reel_stop_random',
        name: 'Reel Stop with Variants',
        description: 'Random reel stop sounds with repeat avoidance',
        category: 'Reel',
        parameters: [
          TemplateParameter('variantCount', 'Number of Variants', TemplateParamType.integer, 3),
          TemplateParameter('avoidRepeat', 'Avoid Repeats', TemplateParamType.boolean, true),
        ],
        graphFactory: _createReelStopGraph,
      ),
      GraphTemplate(
        id: 'feature_transition',
        name: 'Feature Transition',
        description: 'Crossfade music layers on feature enter/exit',
        category: 'Feature',
        parameters: [
          TemplateParameter('featureType', 'Feature Type', TemplateParamType.enumChoice,
              'FREE_SPINS', enumValues: ['FREE_SPINS', 'BONUS', 'PICK', 'GAMBLE']),
          TemplateParameter('transitionTime', 'Transition Time (s)', TemplateParamType.float, 1.5),
        ],
        graphFactory: _createFeatureTransitionGraph,
      ),
      GraphTemplate(
        id: 'anticipation_swell',
        name: 'Anticipation Swell',
        description: 'Rising sound when scatter/wild landing is possible',
        category: 'Anticipation',
        parameters: [
          TemplateParameter('anticipationType', 'Type', TemplateParamType.enumChoice,
              'scatter', enumValues: ['scatter', 'wild', 'bonus']),
          TemplateParameter('cooldownSeconds', 'Cooldown (s)', TemplateParamType.float, 5.0),
        ],
        graphFactory: _createAnticipationGraph,
      ),
      GraphTemplate(
        id: 'rollup_audio',
        name: 'Win Rollup Audio',
        description: 'Ticking sound during win count-up with tier-based intensity',
        category: 'Win',
        parameters: [
          TemplateParameter('tickRate', 'Tick Rate', TemplateParamType.enumChoice,
              'adaptive', enumValues: ['fixed', 'adaptive', 'accelerating']),
        ],
        graphFactory: _createRollupGraph,
      ),
      GraphTemplate(
        id: 'adaptive_ambient',
        name: 'Adaptive Ambient',
        description: 'Blend ambient layers based on excitement level',
        category: 'Music',
        parameters: [
          TemplateParameter('layerCount', 'Number of Layers', TemplateParamType.integer, 2),
          TemplateParameter('blendParameter', 'Blend RTPC', TemplateParamType.string, 'Excitement'),
        ],
        graphFactory: _createAdaptiveAmbientGraph,
      ),
    ]);
  }

  /// Instantiate template with parameter values
  HookGraphDefinition instantiate(String templateId, Map<String, dynamic> paramValues) {
    final template = _templates.firstWhere((t) => t.id == templateId);
    return template.graphFactory(paramValues);
  }

  /// Get templates by category
  List<GraphTemplate> byCategory(String category) {
    return _templates.where((t) => t.category == category).toList();
  }

  /// Search templates
  List<GraphTemplate> search(String query) {
    final lower = query.toLowerCase();
    return _templates.where((t) =>
      t.name.toLowerCase().contains(lower) ||
      t.description.toLowerCase().contains(lower)
    ).toList();
  }
}

class GraphTemplate {
  final String id;
  final String name;
  final String description;
  final String category;
  final List<TemplateParameter> parameters;
  final HookGraphDefinition Function(Map<String, dynamic>) graphFactory;
}

class TemplateParameter {
  final String id;
  final String displayName;
  final TemplateParamType type;
  final dynamic defaultValue;
  final List<String>? enumValues;
  final double? min;
  final double? max;
}
```

---

## 42. Error Recovery & Graceful Degradation

### Node-Level Recovery

```dart
/// Wrap each node's process() in error boundary
void processNodeSafe(GraphNode node, WireState wires, int tick, GraphContext context) {
  try {
    node.process(wires, tick, context);
  } catch (e, stack) {
    // 1. Mark node as errored
    node._state = NodeState.error;

    // 2. Write default values to outputs (prevent downstream crash)
    for (final port in node.outputPorts) {
      wires.write(node.id, port.id, port.defaultValue, tick);
    }

    // 3. Report to debug overlay (NOT console — CLAUDE.md rule)
    context.reportError(node.id, e);

    // 4. Log for diagnostics
    context.feedbackSink.send(GraphFeedback.nodeError(
      node.id, e.toString(), stack.toString(),
    ));

    // 5. Node stays in error state until graph reset
    // Other nodes continue executing with default values
  }
}
```

### Graph-Level Recovery

```dart
class GraphExecutorRecovery {
  /// Handle graph execution failure
  void onGraphError(GraphInstance instance, dynamic error) {
    // 1. Stop all voices gracefully (fade out, don't pop)
    instance.stop(fadeOut: Duration(milliseconds: 50));

    // 2. Mark graph as failed
    instance._state = GraphInstanceState.done;

    // 3. Notify debug overlay
    _feedbackSink.send(GraphFeedback.graphError(
      instance.graphId, error.toString(),
    ));

    // 4. DO NOT re-throw — other graphs keep running
    // 5. Pool will recycle this instance normally
  }

  /// Handle audio engine disconnect (FFI failure)
  void onAudioEngineDisconnect() {
    // 1. All audio commands go to /dev/null — queue them for later
    _commandQueue.setMode(CommandQueueMode.buffer);

    // 2. Control-rate keeps running (logic still executes)
    // 3. When engine reconnects, flush buffered commands
    // 4. Show warning in UI: "Audio engine disconnected"
  }

  /// Handle corrupt graph file
  HookGraphDefinition? loadGraphSafe(String path) {
    try {
      final json = _readFile(path);
      final graph = GraphSerializer().load(json);
      final validation = GraphValidator().validate(graph);

      if (!validation.isValid) {
        // Try auto-fix
        var fixed = graph;
        for (final error in validation.errors) {
          if (error.autoFix != null) {
            fixed = error.autoFix!.apply(fixed);
          }
        }

        // Re-validate
        final revalidation = GraphValidator().validate(fixed);
        if (revalidation.isValid) {
          return fixed; // Auto-fixed successfully
        }

        // Can't auto-fix — return null, report errors
        _reportLoadErrors(path, validation.errors);
        return null;
      }

      return graph;
    } catch (e) {
      _reportLoadFailure(path, e);
      return null; // Don't crash — skip this graph
    }
  }
}
```

### Audio Thread Recovery (Rust)

```rust
impl HookGraphEngine {
    /// Safe process wrapper — catches panics
    pub fn process_safe(&mut self, output: &mut [f32], buffer_size: usize) {
        // Clear output first — if we crash, silence is better than garbage
        for s in output.iter_mut() { *s = 0.0; }

        // Process with catch_unwind — audio thread MUST NOT panic
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.process(output, buffer_size);
        }));

        if result.is_err() {
            // Panic caught — reset all state
            self.emergency_reset();
            // Send error feedback to Dart
            let _ = self.feedback_tx.push(GraphFeedback::EnginePanic);
        }
    }

    fn emergency_reset(&mut self) {
        // Stop all voices immediately (no fade — emergency)
        self.voices = VoiceManager::new(self.voices.max_voices, self.voices.steal_policy);
        // Clear all active instances
        self.active.clear();
        // Drain command queue
        while let Ok(_) = self.command_rx.pop() {}
    }
}
```

---

## 43. Testing Strategy

### Unit Tests — Node Level

```dart
// test/hook_graph/nodes/compare_node_test.dart

void main() {
  group('CompareNode', () {
    late CompareNode node;
    late WireState wires;
    late GraphContext context;

    setUp(() {
      node = CompareNode(id: 'test', position: Offset.zero, parameters: {'operator': 'eq'});
      wires = WireState.forTest({'test.a': null, 'test.b': null, 'test.result': null});
      context = GraphContext.forTest();
    });

    test('equal values → true', () {
      wires.write('test', 'a', 42, 1);
      wires.write('test', 'b', 42, 1);
      node.process(wires, 1, context);
      expect(wires.read<bool>('test', 'result'), isTrue);
    });

    test('unequal values → false', () {
      wires.write('test', 'a', 42, 1);
      wires.write('test', 'b', 99, 1);
      node.process(wires, 1, context);
      expect(wires.read<bool>('test', 'result'), isFalse);
    });

    test('null input → false (no crash)', () {
      node.process(wires, 1, context);
      expect(wires.read<bool>('test', 'result'), isFalse);
    });
  });
}
```

### Integration Tests — Graph Level

```dart
// test/hook_graph/graph_execution_test.dart

void main() {
  group('Graph Execution', () {
    test('basic event → play sound graph', () {
      final graph = GraphSerializer().load(
        File('assets/hook_graphs/templates/basic_play.fhg.json').readAsStringSync()
      );
      final compiled = GraphCompiler().compile(graph);
      final executor = ControlRateExecutor.forTest();

      // Trigger event
      final event = Event('WIN_EVAL', {'winAmount': 100, 'betAmount': 10});
      executor.trigger(compiled, event);

      // Tick once
      executor.tick();

      // Verify audio command was produced
      expect(executor.pendingCommands, hasLength(1));
      expect(executor.pendingCommands.first, isA<StartVoiceCommand>());
    });

    test('tiered win routes to correct tier', () {
      final graph = GraphSerializer().load(
        File('assets/hook_graphs/templates/win_celebration.fhg.json').readAsStringSync()
      );
      final compiled = GraphCompiler().compile(graph);

      for (int tier = 1; tier <= 5; tier++) {
        final executor = ControlRateExecutor.forTest();
        final event = Event('WIN_EVAL', {
          'winAmount': tier * 100.0,
          'betAmount': 1.0,
          'tier': 'WIN_$tier',
        });
        executor.trigger(compiled, event);
        executor.tick();

        // Verify correct branch was taken
        expect(executor.pendingCommands, isNotEmpty,
          reason: 'Tier $tier should produce audio commands');
      }
    });
  });
}
```

### Determinism Tests

```dart
// test/hook_graph/determinism_test.dart

void main() {
  group('Deterministic Execution', () {
    test('same seed + same event = identical output', () {
      final graph = /* graph with RandomSelector */;
      final compiled = GraphCompiler().compile(graph);
      final event = Event('REEL_STOP', {});

      final results = <List<GraphCommand>>[];

      for (int i = 0; i < 100; i++) {
        final executor = DeterministicExecutor(seed: 12345);
        final instance = executor.executeDeterministic(compiled, event, {});
        results.add(List.from(instance.allCommands));
      }

      // All 100 runs must produce identical commands
      for (int i = 1; i < results.length; i++) {
        expect(results[i], equals(results[0]),
          reason: 'Run $i differs from run 0');
      }
    });

    test('different seed = different output', () {
      final graph = /* graph with RandomSelector */;
      final compiled = GraphCompiler().compile(graph);
      final event = Event('REEL_STOP', {});

      final result1 = DeterministicExecutor(seed: 111).executeDeterministic(compiled, event, {});
      final result2 = DeterministicExecutor(seed: 222).executeDeterministic(compiled, event, {});

      // With different seeds and RandomSelector, results should differ
      // (statistically, not guaranteed, but with enough variants it's near-certain)
      expect(result1.allCommands, isNot(equals(result2.allCommands)));
    });

    test('certification audit passes', () {
      final auditor = DeterminismAuditor();
      final graph = /* full slot spin graph */;
      final compiled = GraphCompiler().compile(graph);

      final executions = <GraphExecution>[];
      for (int seed = 0; seed < 1000; seed++) {
        final executor = DeterministicExecutor(seed: seed);
        // Run same event with same seed twice
        final run1 = executor.executeDeterministic(compiled, Event('SPIN_END', {}), {});
        final executor2 = DeterministicExecutor(seed: seed);
        final run2 = executor2.executeDeterministic(compiled, Event('SPIN_END', {}), {});

        executions.add(GraphExecution(seed: seed, run1: run1, run2: run2));
      }

      final report = auditor.audit(executions: executions, requiredMatches: 1000);
      expect(report.allPassed, isTrue);
      expect(report.matchCount, equals(1000));
    });
  });
}
```

### Fuzz Tests

```dart
// test/hook_graph/fuzz_test.dart

void main() {
  group('Graph Fuzzing', () {
    test('random graphs compile or fail gracefully', () {
      final rng = Random(42);

      for (int i = 0; i < 1000; i++) {
        final graph = _generateRandomGraph(rng, nodeCount: rng.nextInt(50) + 1);

        try {
          final result = GraphValidator().validate(graph);
          if (result.isValid) {
            final compiled = GraphCompiler().compile(graph);
            // If it compiled, tick it 100 times without crash
            final executor = ControlRateExecutor.forTest();
            executor.trigger(compiled, Event('TEST', {}));
            for (int t = 0; t < 100; t++) {
              executor.tick();
            }
          }
        } catch (e) {
          // Expected: invalid graphs throw during validation/compile
          // NOT expected: crashes/panics during execution
          if (e is! GraphCompileError && e is! GraphValidationError) {
            fail('Unexpected error on fuzz iteration $i: $e');
          }
        }
      }
    });

    test('random event payloads dont crash nodes', () {
      final graph = /* standard tiered win graph */;
      final compiled = GraphCompiler().compile(graph);
      final rng = Random(42);

      for (int i = 0; i < 1000; i++) {
        final payload = _generateRandomPayload(rng);
        final executor = ControlRateExecutor.forTest();
        executor.trigger(compiled, Event('WIN_EVAL', payload));

        // Must not throw
        for (int t = 0; t < 10; t++) {
          executor.tick();
        }
      }
    });
  });
}
```

### Rust Audio Tests

```rust
// rf-engine/tests/hook_graph_tests.rs

#[test]
fn voice_manager_handles_pool_exhaustion() {
    let mut vm = VoiceManager::new(4, StealPolicy::Oldest);

    // Fill all voices
    for i in 0..4 {
        let result = vm.start_voice(VoiceParams { asset_id: i, priority: 0, ..default() });
        assert!(result.is_some());
    }

    // 5th voice should steal oldest
    let result = vm.start_voice(VoiceParams { asset_id: 99, priority: 0, ..default() });
    assert!(result.is_some());
    assert_eq!(vm.active_count(), 4); // Still 4, not 5
}

#[test]
fn audio_node_process_no_allocation() {
    // Verify zero allocations during process
    let mut node = FilterNode::new(FilterType::Lowpass, 1000.0, 0.707);
    let mut buffers = vec![AudioBuffer::new(256); 4];

    // Warm up
    node.process(&mut buffers, 256);

    // Measure allocations
    let allocs_before = GLOBAL_ALLOCATOR.allocations();
    for _ in 0..1000 {
        node.process(&mut buffers, 256);
    }
    let allocs_after = GLOBAL_ALLOCATOR.allocations();

    assert_eq!(allocs_before, allocs_after, "DSP node allocated during process!");
}
```

---

## 44. HookDispatcher Migration Plan

Postepena migracija od HookDispatcher ka Hook Graph sistemu — bez breaking changes.

### Phase M1: Coexistence Layer (Non-Breaking)

```dart
/// Bridge that wraps HookDispatcher hooks as single-node graphs
class HookDispatcherBridge {
  final HookDispatcher _dispatcher;
  final HookGraphRegistry _graphRegistry;

  /// Wrap all existing HookDispatcher registrations as graphs
  void bridgeAll() {
    for (final hook in _dispatcher.registeredHooks) {
      final graph = _wrapAsGraph(hook);
      _graphRegistry.bind(
        eventPattern: hook.eventPattern,
        graph: graph,
        priority: hook.priority - 1, // Slightly lower than graph equivalents
      );
    }
  }

  HookGraphDefinition _wrapAsGraph(HookRegistration hook) {
    // Create minimal graph: EventEntry → callback bridge node
    return HookGraphDefinition(
      id: 'legacy_${hook.id}',
      name: 'Legacy: ${hook.name}',
      nodes: {
        'entry': EventEntryNode(eventName: hook.eventPattern),
        'action': LegacyHookNode(hookCallback: hook.callback),
      },
      connections: [
        GraphConnection(
          sourceNodeId: 'entry', sourcePortId: 'trigger',
          targetNodeId: 'action', targetPortId: 'trigger',
        ),
      ],
    );
  }
}
```

### Phase M2: Dual Registration

```
Event Flow (Phase M2):
  EventRegistry
    ├─→ HookGraphRegistry → Graph Executor    (NEW: graphs execute first)
    └─→ HookDispatcher → Simple callbacks     (LEGACY: existing hooks)

  Ordering:
    1. Graph hooks process (may "consume" event)
    2. If not consumed, HookDispatcher processes
    3. Both outputs go to audio engine
```

### Phase M3: Gradual Migration

| Hook Category | Migration Approach | Priority |
|--------------|-------------------|----------|
| Win sounds | Replace with Tiered Win graph template | P1 |
| Reel stops | Replace with Reel Stop Random graph | P1 |
| Feature transitions | Replace with Feature Transition graph | P2 |
| Anticipation | Replace with Anticipation Swell graph | P2 |
| Ambient/music | Replace with Adaptive Ambient graph | P3 |
| UI sounds | Keep as simple HookDispatcher (no graph needed) | P4 (keep) |

### Phase M4: Deprecation

```dart
/// Mark HookDispatcher as deprecated after all audio hooks migrated
@Deprecated('Use HookGraphRegistry instead. HookDispatcher retained only for non-audio UI hooks.')
class HookDispatcher {
  // ...existing code...
}
```

### Migration Checklist

- [ ] Phase M1: HookDispatcherBridge implemented and tested
- [ ] Phase M1: Both systems run simultaneously without interference
- [ ] Phase M2: Event flow dual-routes to both systems
- [ ] Phase M2: "consumed" flag prevents double-processing
- [ ] Phase M3: Win sounds migrated to graph
- [ ] Phase M3: Reel stop sounds migrated to graph
- [ ] Phase M3: Feature transitions migrated to graph
- [ ] Phase M3: Anticipation sounds migrated to graph
- [ ] Phase M3: All migrated graphs have determinism tests passing
- [ ] Phase M4: HookDispatcher deprecated, only UI hooks remain
- [ ] Phase M4: Documentation updated

---

## 45. Interactive Music State Machine

Wwise Interactive Music sistem je industriski standard za adaptivnu muziku. FluxForge mora imati paritet.

### Music Segment Model

```dart
/// A music segment — represents a loopable section of music
class MusicSegment {
  final String id;
  final String name;
  final String assetPath;
  final double duration;        // Seconds
  final double tempo;           // BPM
  final int timeSignatureNum;   // e.g., 4 (4/4 time)
  final int timeSignatureDen;   // e.g., 4
  final double barDuration;     // Computed: (60 / tempo) * timeSignatureNum
  final double beatDuration;    // Computed: 60 / tempo

  // Sync points — positions where transitions can occur
  final List<MusicSyncPoint> syncPoints;

  // Loop region
  final double loopStart;       // Seconds
  final double loopEnd;         // Seconds (-1 = end of file)
  final int loopCount;          // -1 = infinite

  // Pre-entry and post-exit regions (for crossfades)
  final double preEntryDuration;
  final double postExitDuration;
}

class MusicSyncPoint {
  final String name;            // "Chorus", "Bridge", "Drop", etc.
  final double position;        // Seconds from start
  final MusicSyncType type;
}

enum MusicSyncType {
  immediate,     // Transition NOW
  nextBeat,      // Wait for next beat boundary
  nextBar,       // Wait for next bar boundary
  nextCue,       // Wait for next named cue point
  nextSegment,   // Wait for current segment to end
  exitCue,       // Transition at segment's designated exit point
  custom,        // Transition at specific beat/bar count
}
```

### Music State Machine

```dart
/// State machine that controls music flow
class MusicStateMachine {
  final String id;
  final Map<String, MusicState> states;
  final List<MusicTransition> transitions;
  String _currentState;
  MusicSegment? _currentSegment;
  double _playbackPosition = 0.0;

  /// Transition to new state
  void setState(String newState) {
    final transition = _findTransition(_currentState, newState);
    if (transition == null) {
      // No explicit transition — use default (immediate crossfade)
      _executeTransition(MusicTransition.defaultCrossfade(_currentState, newState));
    } else {
      _executeTransition(transition);
    }
    _currentState = newState;
  }
}

class MusicState {
  final String id;
  final String name;
  final List<MusicSegment> segments;         // Segments to play in this state
  final MusicPlayMode playMode;              // sequential, random, shuffle
  final Map<String, List<String>> subTracks; // Switch sub-tracks per game state
}

enum MusicPlayMode { sequential, random, shuffle, single }

class MusicTransition {
  final String fromState;
  final String toState;

  // Source behavior
  final MusicSyncType syncType;              // When to leave source
  final double fadeOutDuration;              // Seconds
  final CurveType fadeOutCurve;

  // Transition segment (optional — plays between source and destination)
  final MusicSegment? transitionSegment;

  // Destination behavior
  final double fadeInDuration;               // Seconds
  final CurveType fadeInCurve;
  final double destinationOffset;            // Where to start in destination (seconds)
  final bool playPreEntry;                   // Play destination's pre-entry region

  // Custom filter during transition
  final double? lowpassDuringTransition;     // Hz (e.g., 500 Hz for muffled effect)
  final double? highpassDuringTransition;
}
```

### SlotLab Music State Machine Example

```
States:
  IDLE         → Ambient loop (low energy)
  BASE_GAME    → Base game music loop
  SPINNING     → Spin music (higher energy)
  WIN_SMALL    → Brief celebration, return to BASE_GAME
  WIN_BIG      → Extended celebration music
  FREE_SPINS   → Free spins music (different key/tempo)
  BONUS_ROUND  → Bonus round music
  JACKPOT      → Jackpot music (longest, most epic)

Transitions:
  IDLE → BASE_GAME:        Sync: nextBar,    fadeOut: 2s,  fadeIn: 2s
  BASE_GAME → SPINNING:    Sync: nextBeat,   fadeOut: 0.5s, fadeIn: 0.1s
  SPINNING → WIN_SMALL:    Sync: immediate,  fadeOut: 0.2s, fadeIn: 0s
  SPINNING → WIN_BIG:      Sync: immediate,  transition: "BigWinTransition" segment
  SPINNING → BASE_GAME:    Sync: nextBar,    fadeOut: 1s,  fadeIn: 1s (no win)
  BASE_GAME → FREE_SPINS:  Sync: exitCue,    transition: "FreeSpinTransition" segment
  FREE_SPINS → BASE_GAME:  Sync: nextSegment, fadeOut: 3s, fadeIn: 2s
  ANY → JACKPOT:           Sync: immediate,  fadeOut: 0.1s, ducking on all other buses
```

### Music State Machine Node

```dart
/// Graph node that controls Music State Machine
class MusicStateMachineNode extends GraphNode {
  // Inputs: setState (string), trigger (trigger),
  //         syncOverride (enum MusicSyncType, optional)
  // Outputs: currentState (string), previousState (string),
  //          transitionStarted (trigger), transitionComplete (trigger),
  //          beat (trigger), bar (trigger), position (float),
  //          tempo (float), segment (string)
  // State: MusicStateMachine instance
}
```

---

## 46. Bus Routing Architecture

Kompletna audio bus hijerarhija — od individualnih glasova do master output-a.

### Bus Hierarchy

```
Master Bus (stereo output)
├── Music Bus
│   ├── Base Music Sub-Bus
│   ├── Feature Music Sub-Bus
│   └── Stinger Bus
├── SFX Bus
│   ├── Reel SFX Sub-Bus
│   ├── Win SFX Sub-Bus
│   ├── UI SFX Sub-Bus
│   └── Anticipation Sub-Bus
├── Ambience Bus
│   ├── Casino Ambient Sub-Bus
│   └── Feature Ambient Sub-Bus
├── Voice Bus (narrator/announcer)
└── Aux Send Buses
    ├── Reverb Send
    ├── Delay Send
    └── Chorus Send
```

### Bus Definition

```dart
class AudioBus {
  final String id;
  final String name;
  final String? parentId;        // null = Master Bus
  final List<String> childIds;

  // Per-bus DSP chain
  final List<DspEffect> insertEffects;

  // Volume
  double volume;                 // dB
  bool muted;
  bool soloed;

  // Aux sends (pre or post fader)
  final List<AuxSend> sends;

  // Metering
  double peakL, peakR;
  double rmsL, rmsR;

  // Voice limit per bus
  int? maxVoices;
  StealPolicy? stealPolicy;
}

class AuxSend {
  final String targetBusId;
  double sendLevel;              // dB
  bool preFader;                 // true = pre-fader (unaffected by bus volume)
  bool enabled;
}

class DspEffect {
  final String effectType;       // "reverb", "compressor", "eq", etc.
  final Map<String, double> parameters;
  bool bypassed;
  bool wet;                      // true = 100% wet (for send effects)
}
```

### Bus Routing Nodes

```dart
/// Route voice to specific bus
class BusRouteNode extends GraphNode {
  // Inputs: voice (voiceHandle), busName (string)
  // Outputs: routed (trigger)
}

/// Set bus volume/mute/solo
class BusControlNode extends GraphNode {
  // Inputs: busName (string), volume (float dB),
  //         mute (bool), solo (bool),
  //         fadeTime (float, seconds)
  // Outputs: done (trigger)
}

/// Set aux send level
class AuxSendControlNode extends GraphNode {
  // Inputs: sourceBus (string), targetBus (string),
  //         sendLevel (float dB), preFader (bool)
  // Outputs: done (trigger)
}

/// Snapshot — set multiple bus parameters at once
class MixSnapshotNode extends GraphNode {
  final Map<String, BusSnapshot> busSettings;
  // Inputs: trigger (trigger), fadeTime (float)
  // Outputs: applied (trigger)
  // Example: "BigWin" snapshot: duck music -12dB, boost SFX +3dB, add reverb send
}
```

### Rust Bus Implementation

```rust
pub struct BusGraph {
    buses: Vec<Bus>,
    bus_map: HashMap<String, usize>, // name → index
    processing_order: Vec<usize>,     // Leaf → root topological order

    // Pre-allocated mix buffers (one per bus, stereo)
    mix_buffers: Vec<[f32; BUFFER_SIZE * 2]>,

    // Aux send buffers
    aux_buffers: Vec<[f32; BUFFER_SIZE * 2]>,
}

impl BusGraph {
    /// Mix all voices through bus hierarchy — called per audio buffer
    pub fn process(&mut self, voices: &[Voice], output: &mut [f32], buffer_size: usize) {
        // 1. Clear all mix buffers
        for buf in &mut self.mix_buffers {
            buf.fill(0.0);
        }
        for buf in &mut self.aux_buffers {
            buf.fill(0.0);
        }

        // 2. Route each voice to its target bus buffer
        for voice in voices {
            let bus_idx = self.bus_map[&voice.bus_name];
            // Mix voice into bus buffer
            self.mix_voice_to_bus(voice, bus_idx, buffer_size);
        }

        // 3. Process buses in topological order (leaves first, master last)
        for &bus_idx in &self.processing_order {
            let bus = &self.buses[bus_idx];

            // Apply insert effects
            for effect in &bus.insert_effects {
                effect.process(&mut self.mix_buffers[bus_idx], buffer_size);
            }

            // Apply volume + mute
            if !bus.muted {
                let gain = db_to_linear(bus.volume);
                for sample in &mut self.mix_buffers[bus_idx] {
                    *sample *= gain;
                }
            } else {
                self.mix_buffers[bus_idx].fill(0.0);
            }

            // Send to aux buses (pre/post fader)
            for send in &bus.sends {
                if send.enabled {
                    let send_gain = db_to_linear(send.send_level);
                    let aux_idx = self.bus_map[&send.target_bus_id];
                    for i in 0..(buffer_size * 2) {
                        self.aux_buffers[aux_idx][i] += self.mix_buffers[bus_idx][i] * send_gain;
                    }
                }
            }

            // Sum into parent bus
            if let Some(parent_idx) = bus.parent_idx {
                for i in 0..(buffer_size * 2) {
                    self.mix_buffers[parent_idx][i] += self.mix_buffers[bus_idx][i];
                }
            }
        }

        // 4. Process aux buses and sum into their outputs
        for (aux_idx, aux_buf) in self.aux_buffers.iter().enumerate() {
            let bus = &self.buses[aux_idx];
            // Aux buses have wet effects (reverb, delay)
            // Sum into master or designated return bus
        }

        // 5. Master bus → output
        let master_idx = self.bus_map["Master"];
        output[..buffer_size * 2].copy_from_slice(&self.mix_buffers[master_idx][..buffer_size * 2]);
    }
}
```

---

## 47. Audio Asset Management & Streaming

### Asset Pipeline

```
Source File (.wav, .ogg, .mp3, .flac)
     │
     ▼
Import → Transcode to internal format (.ffa — FluxForge Audio)
     │
     ├── Small files (< 256KB): Load entirely into memory
     ├── Medium files (256KB - 2MB): Load on demand, cache
     └── Large files (> 2MB): Stream from disk
     │
     ▼
Asset Registry (manifest.json — all assets indexed)
```

### Asset Manager (Rust)

```rust
pub struct AssetManager {
    /// Fully loaded assets (in memory)
    loaded: HashMap<u32, LoadedAsset>,
    /// Streaming assets (partial, ring buffer)
    streaming: HashMap<u32, StreamingAsset>,
    /// Asset metadata (always in memory)
    metadata: HashMap<u32, AssetMetadata>,
    /// Memory pool for loaded assets
    memory_pool: AudioMemoryPool,
    /// Background loader thread
    loader_tx: crossbeam_channel::Sender<LoadRequest>,
    /// Load completion receiver
    loader_rx: crossbeam_channel::Receiver<LoadComplete>,
    /// Total memory usage
    total_memory_bytes: AtomicUsize,
    /// Memory budget
    max_memory_bytes: usize, // Default: 64MB
}

pub struct AssetMetadata {
    pub id: u32,
    pub name: String,
    pub path: String,
    pub format: AudioFormat,
    pub sample_rate: u32,
    pub channels: u16,
    pub duration_samples: u64,
    pub duration_seconds: f64,
    pub file_size_bytes: usize,
    pub load_strategy: LoadStrategy,
}

pub enum LoadStrategy {
    Preload,           // Load at startup, always in memory
    OnDemand,          // Load when first requested, cache
    Stream,            // Never fully load, stream from disk
    OnDemandStream,    // Load header + start, stream rest
}

pub enum AudioFormat {
    PcmI16,            // 16-bit PCM (uncompressed, fast)
    PcmF32,            // 32-bit float PCM (uncompressed, highest quality)
    Vorbis,            // OGG Vorbis (compressed, good for music)
    Opus,              // Opus (compressed, excellent for voice/SFX)
    Adpcm,             // IMA ADPCM (4:1 compression, very fast decode)
}

impl AssetManager {
    /// Get sample data for a voice — RT-safe (no allocation, no blocking)
    pub fn sample_at(&self, asset_id: u32, position: u64) -> f32 {
        if let Some(loaded) = self.loaded.get(&asset_id) {
            // Fully loaded — direct access
            loaded.samples[position as usize]
        } else if let Some(streaming) = self.streaming.get(&asset_id) {
            // Streaming — read from ring buffer
            streaming.read_sample(position)
        } else {
            0.0 // Asset not loaded — silence
        }
    }

    /// Preload assets for a graph (call before graph activation)
    pub fn preload_for_graph(&mut self, compiled: &CompiledAudioGraph) {
        for asset_id in &compiled.required_assets {
            if !self.loaded.contains_key(asset_id) {
                self.loader_tx.send(LoadRequest::Load(*asset_id)).ok();
            }
        }
    }

    /// Evict least-recently-used assets when over memory budget
    fn evict_lru(&mut self) {
        while self.total_memory_bytes.load(Ordering::Relaxed) > self.max_memory_bytes {
            // Find oldest non-playing asset
            if let Some((&id, _)) = self.loaded.iter()
                .filter(|(_, a)| a.ref_count.load(Ordering::Relaxed) == 0)
                .min_by_key(|(_, a)| a.last_access) {
                let asset = self.loaded.remove(&id).unwrap();
                self.total_memory_bytes.fetch_sub(asset.memory_bytes, Ordering::Relaxed);
            } else {
                break; // All assets in use — can't evict
            }
        }
    }
}
```

### Codec Support

| Format | Decode Speed | Compression | Quality | Use Case |
|--------|-------------|-------------|---------|----------|
| PCM 16-bit | Instant | 1:1 | Lossless | Short SFX, one-shots |
| PCM 32-bit | Instant | 1:1 | Lossless | DSP processing, mastering |
| IMA ADPCM | Very Fast | 4:1 | Good | SFX with memory constraint |
| Vorbis | Fast | 10:1-20:1 | Good | Music, long ambient |
| Opus | Fast | 10:1-30:1 | Excellent | Voice, dialog, long SFX |

---

## 48. Live Connection & Hot Reload Protocol

Inspirisano FMOD Live Update — bidirekciona TCP konekcija između editora i running app.

### Protocol Architecture

```
┌─────────────────┐                    ┌─────────────────┐
│  FluxForge       │                    │  Running App     │
│  Graph Editor    │                    │  (SlotLab)       │
│                  │   TCP Socket       │                  │
│  ┌────────────┐  │   Port 47100      │  ┌────────────┐  │
│  │ LiveClient │◄─┼──────────────────►┼──│ LiveServer │  │
│  └────────────┘  │                    │  └────────────┘  │
│                  │                    │                  │
│  Commands OUT:   │                    │  Feedback IN:    │
│  - Graph update  │ ──────────────►    │  - Voice count   │
│  - RTPC set      │                    │  - Peak meters   │
│  - State change  │ ◄────────────────  │  - Exec trace    │
│  - Asset swap    │                    │  - Errors        │
│  - Snapshot req  │                    │  - Graph state   │
└─────────────────┘                    └─────────────────┘
```

### Protocol Messages (MessagePack)

```rust
#[derive(Serialize, Deserialize)]
enum LiveMessage {
    // Editor → App
    GraphUpdate { graph_id: String, compiled_data: Vec<u8> },
    RTPCSet { param_name: String, value: f32 },
    StateChange { state_group: String, new_state: String },
    AssetSwap { asset_id: u32, new_path: String },
    TriggerEvent { event_id: String, payload: HashMap<String, Value> },
    RequestSnapshot,
    StartProfiling,
    StopProfiling,
    SetBreakpoint { graph_id: String, node_id: String },
    ClearBreakpoint { graph_id: String, node_id: String },

    // App → Editor
    Snapshot { graphs: Vec<GraphSnapshot>, voices: Vec<VoiceSnapshot>, buses: Vec<BusSnapshot> },
    VoiceFeedback { active: u32, virtual: u32, peak_l: f32, peak_r: f32 },
    ExecutionTrace { graph_id: String, trace: Vec<NodeTraceEntry> },
    NodeError { graph_id: String, node_id: String, error: String },
    BreakpointHit { graph_id: String, node_id: String, wire_state: HashMap<String, Value> },
    ProfilingData { cpu_percent: f32, memory_bytes: u64, buffer_underruns: u32 },
    AssetLoaded { asset_id: u32, success: bool },
    Heartbeat { timestamp: u64 },
}
```

### Hot Reload Process

```
1. Designer changes graph in editor
2. Editor compiles graph (< 10ms)
3. Editor sends GraphUpdate message via TCP
4. App receives, validates new compiled graph
5. App schedules graph replacement:
   a. New voices start with new graph
   b. Existing voices continue with old graph until done
   c. Old graph recycled when last voice finishes
6. App sends acknowledgment back to editor
7. Designer hears updated audio on next event trigger
```

### Connection Management

```dart
class LiveConnectionManager {
  static const int kDefaultPort = 47100;
  static const Duration kHeartbeatInterval = Duration(seconds: 2);
  static const Duration kReconnectDelay = Duration(seconds: 5);

  Socket? _socket;
  bool _connected = false;
  Timer? _heartbeat;

  /// Connect to running app
  Future<bool> connect(String host, {int port = kDefaultPort});

  /// Auto-discover apps on local network (UDP broadcast)
  Stream<DiscoveredApp> discover();

  /// Send graph update (auto-compiles first)
  Future<void> pushGraph(HookGraphDefinition graph);

  /// Request full state snapshot
  Future<AppSnapshot> requestSnapshot();

  /// Start receiving profiling data
  Stream<ProfilingData> startProfiling();

  /// Disconnect gracefully
  Future<void> disconnect();

  bool get isConnected => _connected;
}
```

---

## 49. Stinger System

Stingeri su kratki muzički fragmenti koji se superimponuju na trenutno puštanu muziku — npr. win fanfare, feature trigger sting, near-miss accent.

### Stinger Definition

```dart
class Stinger {
  final String id;
  final String name;
  final String assetPath;
  final double duration;             // Seconds
  final StingerSyncType syncType;    // When to start playing
  final double volume;               // dB
  final String targetBus;            // Which bus to play on (usually "Stinger Bus")

  // How stinger interacts with underlying music
  final StingerDuckBehavior duckBehavior;
  final double duckAmount;           // dB (how much to duck music)
  final double duckAttack;           // ms
  final double duckRelease;          // ms

  // Playback rules
  final double cooldown;             // Seconds between repeats
  final int maxSimultaneous;         // Max overlapping stingers (usually 1)
  final StingerPriority priority;
}

enum StingerSyncType {
  immediate,    // Play right now
  nextBeat,     // Sync to next beat of current music
  nextBar,      // Sync to next bar
  nextCue,      // Sync to next cue point in music segment
}

enum StingerDuckBehavior {
  none,         // Don't duck music (just layer on top)
  duckMusic,    // Duck music bus during stinger
  duckAll,      // Duck all buses except stinger bus
  sidechain,    // Sidechain compress music by stinger signal
}
```

### Stinger Trigger Node

```dart
/// Play a stinger synchronized to music
class StingerNode extends GraphNode {
  // Inputs: trigger (trigger), stingerId (string),
  //         syncOverride (StingerSyncType, optional),
  //         volumeOverride (float dB, optional)
  // Outputs: played (trigger), blocked (trigger),
  //          syncPosition (float), actualStartTime (float)
  // The node checks cooldown, max simultaneous, and priority
  // before actually playing
}
```

### SlotLab Stinger Presets

| Stinger | Sync | Duck | Cooldown | Use Case |
|---------|------|------|----------|----------|
| Win Fanfare (small) | nextBeat | duckMusic -6dB | 1s | WIN_1, WIN_2 |
| Win Fanfare (big) | immediate | duckAll -12dB | 0s | WIN_3+ |
| Feature Trigger | nextBar | duckMusic -9dB | 5s | Free spins trigger |
| Near-Miss Accent | nextBeat | none | 10s | Scatter near-miss |
| Scatter Land | immediate | none | 0s | Each scatter symbol |
| Wild Expand | immediate | duckMusic -3dB | 0s | Wild expansion |
| Jackpot Hit | immediate | duckAll -18dB | 0s | Jackpot |
| Bonus Collect | nextBeat | none | 0.5s | Bonus item collected |

---

## 50. Graph Session Recording & Replay

Kompletno snimanje i reprodukcija cele audio sesije — za debugging, QA, i regulatory audit.

### Session Recorder

```dart
class GraphSessionRecorder {
  final List<SessionEvent> _events = [];
  bool _recording = false;
  int _startTimeMicros = 0;

  void startRecording() {
    _events.clear();
    _startTimeMicros = DateTime.now().microsecondsSinceEpoch;
    _recording = true;
  }

  void stopRecording() => _recording = false;

  /// Called by graph executor on every event
  void recordEvent(SessionEvent event) {
    if (!_recording) return;
    event.timestamp = DateTime.now().microsecondsSinceEpoch - _startTimeMicros;
    _events.add(event);
  }

  /// Save session to file
  Future<void> save(String path) async {
    final data = SessionData(
      events: _events,
      duration: _events.last.timestamp,
      metadata: SessionMetadata(
        date: DateTime.now(),
        graphIds: _events.map((e) => e.graphId).toSet().toList(),
        eventCount: _events.length,
        voiceCount: _events.whereType<VoiceStartEvent>().length,
      ),
    );
    await File(path).writeAsBytes(data.toMsgPack());
  }
}
```

### Session Events

```dart
abstract class SessionEvent {
  int timestamp; // Microseconds from session start
  String get type;
}

class EventTriggerSessionEvent extends SessionEvent {
  final String eventId;
  final Map<String, dynamic> payload;
  @override String get type => 'event_trigger';
}

class GraphActivateSessionEvent extends SessionEvent {
  final String graphId;
  final String instanceId;
  @override String get type => 'graph_activate';
}

class NodeExecuteSessionEvent extends SessionEvent {
  final String graphId;
  final String nodeId;
  final Map<String, dynamic> inputs;
  final Map<String, dynamic> outputs;
  final int executionTimeUs;
  @override String get type => 'node_execute';
}

class VoiceStartSessionEvent extends SessionEvent {
  final int voiceId;
  final String assetPath;
  final double volume;
  final String bus;
  @override String get type => 'voice_start';
}

class VoiceStopSessionEvent extends SessionEvent {
  final int voiceId;
  final String reason; // "natural", "stolen", "stopped", "error"
  @override String get type => 'voice_stop';
}

class RTPCChangeSessionEvent extends SessionEvent {
  final String paramName;
  final double oldValue;
  final double newValue;
  @override String get type => 'rtpc_change';
}

class StateChangeSessionEvent extends SessionEvent {
  final String stateGroup;
  final String oldState;
  final String newState;
  @override String get type => 'state_change';
}
```

### Session Replay

```dart
class GraphSessionPlayer {
  final SessionData session;
  int _playbackPosition = 0;
  bool _playing = false;
  double _playbackSpeed = 1.0;

  /// Replay session through graph executor
  void play(ControlRateExecutor executor) {
    _playing = true;
    _scheduleNext(executor);
  }

  /// Scrub to position
  void seekTo(int timestampMicros) {
    _playbackPosition = timestampMicros;
  }

  /// Step one event at a time (debug mode)
  void stepForward(ControlRateExecutor executor) {
    if (_playbackPosition >= session.events.length) return;
    _replayEvent(session.events[_playbackPosition], executor);
    _playbackPosition++;
  }

  /// Export timeline view for debugging
  SessionTimeline generateTimeline() {
    // Creates visual timeline of all events, voices, RTPC changes
    // Renderable in debug overlay
  }
}
```

---

## 51. Regulatory Compliance & Near-Miss Audio Rules

### GLI-11 Audio Requirements

Gaming Laboratories International (GLI) Standard 11 governs electronic gaming machines including slot machines.

```dart
class RegulatoryAudioRules {
  /// Near-miss sounds MUST NOT sound like win sounds
  /// Regulatory requirement: audio must clearly differentiate between
  /// a near-miss and an actual win
  static const nearMissRules = NearMissAudioRules(
    // Near-miss celebration sounds are PROHIBITED in many jurisdictions
    maxNearMissVolumeRelativeToWin: -12.0, // dB below smallest win sound
    allowNearMissFanfare: false,           // NO fanfare/celebration for near-miss
    allowNearMissCoins: false,             // NO coin sounds for near-miss
    nearMissAccentOnly: true,              // Only subtle accent sounds allowed
    // Cooldown to prevent near-miss sound fatigue / manipulation perception
    minNearMissCooldown: Duration(seconds: 5),
  );

  /// Win sounds MUST play for actual wins
  static const winSoundRules = WinAudioRules(
    // Win must have audible confirmation
    minWinSoundDuration: Duration(milliseconds: 500),
    // Win sound must be proportional to win size
    tieredRequired: true,
    // Player must be able to skip/speed up win celebration
    skipMustBePossible: true,
    skipMinPlayTime: Duration(seconds: 2), // Must play at least 2s before skip
  );

  /// Volume and player control
  static const playerControlRules = PlayerControlRules(
    // Player MUST be able to mute all audio
    muteRequired: true,
    // Volume setting must persist across sessions
    volumePersistence: true,
    // Default volume must not be maximum
    maxDefaultVolume: 0.8,
  );
}
```

### Jurisdiction-Specific Rules

| Jurisdiction | Near-Miss Audio | Win Audio | Auto-play Audio |
|-------------|----------------|-----------|-----------------|
| **UK (UKGC)** | Strict: no celebratory sounds | Must match win magnitude | Must be reducible |
| **Malta (MGA)** | Moderate: subtle accents OK | Required for all wins | Standard |
| **Gibraltar** | Moderate | Required | Standard |
| **Curacao** | Lenient | Required | Standard |
| **Nevada (NGCB)** | No specific audio rules | Must be audible | N/A (no online) |
| **New Jersey (DGE)** | Moderate | Required, proportional | Must be adjustable |
| **Ontario (AGCO)** | Strict: no misleading audio | Required, clear | Reduced recommended |

### Regulatory Validation Node

```dart
/// Validates audio decisions against regulatory rules
class RegulatoryValidatorNode extends GraphNode {
  final String jurisdiction; // "UKGC", "MGA", "NGCB", etc.
  // Inputs: eventType (string), audioDecision (string),
  //         isNearMiss (bool), isWin (bool), winTier (int)
  // Outputs: allowed (bool), blocked (trigger),
  //          reason (string), suggestedAlternative (string)
  // Blocks audio that violates jurisdiction rules
  // Reports violations to DiagnosticsService
}
```

---

## 52. Accessibility & Inclusive Audio

### Visual Feedback for Hearing-Impaired Players

```dart
class AudioAccessibilitySystem {
  /// Generate visual pulses synchronized to audio events
  void onAudioEvent(String eventType, double volume, double frequency) {
    // Map audio characteristics to visual effects:
    // - Bass heavy → screen edge pulse
    // - High frequency → particle effects
    // - Loud → bright flash
    // - Win → color cascade
    _visualFeedbackController.pulse(
      intensity: volume,
      color: _frequencyToColor(frequency),
      pattern: _eventToPattern(eventType),
    );
  }

  /// Haptic feedback on supported devices
  void triggerHaptic(String eventType, double intensity) {
    // Map audio events to haptic patterns
    // Win → strong pulse
    // Reel stop → light tap
    // Feature trigger → long buzz
  }

  /// Subtitle system for audio cues
  void showAudioSubtitle(String description, Duration duration) {
    // "[Win Sound - Big Win]"
    // "[Music - Free Spins Theme Starting]"
    // "[Sound Effect - Reel Stop]"
  }
}
```

### Volume Normalization

```dart
class VolumeNormalizationSystem {
  /// EBU R128 loudness normalization
  /// Target: -23 LUFS for broadcast, -16 LUFS for games
  static const double kTargetLoudness = -16.0; // LUFS

  /// Per-asset loudness analysis (done at import time)
  double analyzeAssetLoudness(AudioAsset asset) {
    // Measure integrated loudness using ITU-R BS.1770-4 algorithm
    // Store result in asset metadata
  }

  /// Runtime gain compensation
  double compensationGain(double measuredLoudness) {
    return kTargetLoudness - measuredLoudness; // dB
  }
}
```

### Accessibility Settings Node

```dart
/// Graph node that adapts audio for accessibility
class AccessibilityNode extends GraphNode {
  // Inputs: trigger (trigger), audioEvent (string),
  //         volume (float), frequency (float)
  // Outputs: adjustedVolume (float), visualPulse (trigger),
  //          hapticPulse (trigger), subtitle (string)
  // Reads accessibility settings:
  // - hearingMode: normal, enhanced (boost clarity), minimal, off
  // - visualFeedback: on/off
  // - hapticFeedback: on/off
  // - subtitles: on/off
}
```

---

## 53. Localization & Regional Audio Variants

### Regional Audio Config

```dart
class RegionalAudioConfig {
  final String regionId;          // "EU", "UK", "US_NV", "ASIA", "LATAM"
  final String jurisdictionId;    // "UKGC", "MGA", "NGCB", etc.

  // Asset overrides per region
  final Map<String, String> assetOverrides; // base_asset → regional_asset

  // Volume adjustments
  final Map<String, double> busVolumeOffsets; // bus → dB offset

  // Feature restrictions
  final bool nearMissAudioEnabled;
  final bool autoplayAudioReduced;
  final double maxWinCelebrationDuration; // Seconds (-1 = unlimited)
  final bool lossDisguisedAsWinBlocked; // Some jurisdictions block LDW sounds

  // Language-specific voice assets
  final String? narratorLocale; // "en-US", "de-DE", "ja-JP", etc.
}
```

### Localization Node

```dart
/// Resolves regional audio variant
class LocalizationNode extends GraphNode {
  // Inputs: baseAsset (string), region (string)
  // Outputs: resolvedAsset (string), isOverridden (bool)
  // Looks up regional override for base asset
  // Falls back to base if no override exists
}
```

### Region Switch Graph Pattern

```
[EventEntry] → [RegionSwitch]
                 ├── [UK]: NearMiss audio DISABLED, reduced celebration
                 ├── [EU]: Standard audio, moderate celebration
                 ├── [US]: Full audio, extended celebration
                 └── [ASIA]: Custom sounds, different scales/instruments
```

---

## 54. Asset Hot-Swap & Live Iteration

Zero-downtime zamena zvučnih fajlova — kritično za audio dizajnerski workflow.

### Hot-Swap Pipeline

```
1. Designer modifies .wav file on disk
2. File watcher detects change (FSEvents on macOS)
3. New file imported → transcoded to internal format
4. AssetManager receives swap command
5. New asset loaded alongside old one
6. Next voice that requests this asset gets new version
7. Voices already playing old version continue undisturbed
8. Old asset evicted when last voice using it finishes
```

### Implementation

```dart
class AssetHotSwapManager {
  final FileSystemWatcher _watcher;
  final AssetManager _assetManager;

  /// Watch asset directories for changes
  void startWatching(List<String> directories) {
    for (final dir in directories) {
      _watcher.watch(dir, (event) {
        if (event.type == FileSystemEvent.modify || event.type == FileSystemEvent.create) {
          if (_isAudioFile(event.path)) {
            _handleAssetChange(event.path);
          }
        }
      });
    }
  }

  Future<void> _handleAssetChange(String path) async {
    // 1. Find asset ID by path
    final assetId = _assetManager.findByPath(path);
    if (assetId == null) return; // Unknown file, ignore

    // 2. Transcode new version
    final transcoded = await AudioTranscoder.transcode(path);

    // 3. Send swap command to Rust engine (non-blocking)
    _assetManager.swapAsset(assetId, transcoded);

    // 4. Show notification in UI
    _feedbackSink.send(AssetFeedback.swapped(assetId, path));
  }
}
```

### Asset Version Tracking

```rust
pub struct VersionedAsset {
    pub id: u32,
    pub version: u32,
    pub current: LoadedAsset,
    pub previous: Option<LoadedAsset>, // Kept alive while voices reference it
    pub ref_count_current: AtomicU32,
    pub ref_count_previous: AtomicU32,
}

impl VersionedAsset {
    pub fn swap(&mut self, new_asset: LoadedAsset) {
        // Move current to previous (if no refs, drop it)
        if let Some(prev) = self.previous.take() {
            if self.ref_count_previous.load(Ordering::Relaxed) == 0 {
                drop(prev); // No voices using it, safe to drop
            }
            // else: leak — will be cleaned up on next swap
        }
        self.previous = Some(std::mem::replace(&mut self.current, new_asset));
        self.ref_count_previous.store(
            self.ref_count_current.swap(0, Ordering::Relaxed),
            Ordering::Relaxed
        );
        self.version += 1;
    }
}
```

---

## 55. Complete Node Reference Index

Kompletni katalog svih node tipova u sistemu — **93 node tipa** u 14 kategorija.

### Event Nodes (4)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| EventEntryNode | — | trigger, eventId, payload, timestamp | 6.1 |
| RTPCInputNode | — | value, delta, velocity | 6.1 |
| StateInputNode | — | currentState, previousState, changeTrigger | 6.1 |
| TimelineInputNode | — | position, beat, bar, tempo, playing | 6.1 |

### Condition Nodes (6)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| CompareNode | a, b | result, trueOut, falseOut | 6.2 |
| RangeNode | value, min, max | inRange, normalized, trigger | 6.2 |
| MatchNode | value | dynamic per case + default | 6.2 |
| PayloadExtractNode | payload | value, exists | 6.2 |
| AllOfNode | condition_0..N | result, trigger | 6.2 |
| AnyOfNode | condition_0..N | result, matchCount, trigger | 6.2 |

### Logic Nodes (11)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| BoolLogicNode | a, b | result | 6.3 |
| SwitchNode | selector | per-case triggers | 6.3 |
| ProbabilityNode | trigger, seed | per-option triggers, selectedIndex | 6.3 |
| SequenceNode | advance, reset | per-step triggers, currentStep | 6.3 |
| BlendNode | parameter, audio_0..N | blended | 6.3 |
| CooldownNode | trigger, cooldownTime | passed, blocked, remaining | 6.3 |
| GateNode | input, open | output, blocked | 6.3 |
| CounterNode | increment, reset | count, thresholdReached | 6.3 |
| LatchNode | set, reset, value | stored, isSet | 6.3 |
| DebounceNode | trigger, duration | debounced | 6.3 |
| RegulatoryValidatorNode | eventType, audioDecision, isNearMiss | allowed, blocked, reason | 51 |

### Timing Nodes (6)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| DelayNode | trigger, delay | delayed, cancel | 6.4 |
| MetronomeNode | start, stop, interval | tick, tickCount | 6.4 |
| EnvelopeNode | noteOn, noteOff, ADSR | value, phase, done | 6.4 |
| TimelineNode | start, stop, position | per-cue triggers, currentPosition | 6.4 |
| RampNode | start, startValue, endValue, duration | value, progress, done | 6.4 |
| BarrierNode | trigger_0..N | complete, receivedCount | 6.4 |

### Audio Nodes (9)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| PlaySoundNode | trigger, asset, volume, pitch, pan, bus | voice, started, ended, position | 6.5 |
| StopSoundNode | voice, fadeOut, stopMode | stopped | 6.5 |
| PauseSoundNode | voice, pause, fadeTime | paused, resumed | 6.5 |
| SetVoiceParamNode | voice, value, interpolationTime | done | 6.5 |
| CrossfadeNode | voiceA, voiceB, mix, duration | done | 6.5 |
| DynamicSoundNode | trigger, context | requestAsset, asset | 6.5 |
| SeekNode | voice, position, mode | seeked, actualPosition | 6.9 |
| RestartNode | voice, fadeOut, fadeIn, delay | restarted | 6.9 |
| MultiPlayNode | trigger, asset_0..N, volume_0..N | voices, allStarted, allEnded | 6.9 |

### DSP Nodes (7) — Audio-Rate, Rust
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| FilterNode | audio, cutoff, resonance | audio | 6.6 |
| GainNode | audio, gain, automation | audio, peak, rms | 6.6 |
| PanNode | audio, pan | audioL, audioR | 6.6 |
| AudioDelayNode | audio, delayTime, feedback, mix | audio | 6.6 |
| CompressorNode | audio, threshold, ratio, attack, release | audio, gainReduction | 6.6 |
| MixerNode | audio_0..N, gain_0..N | mixed, peak | 6.6 |
| BusSendNode | audio, bus, sendLevel, pre | sent | 6.6 |

### Layer Nodes (7)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| LayerStartNode | trigger, layerName, fadeIn, volume | started, layerHandle | 6.8 |
| LayerStopNode | trigger, layerName, fadeOut | stopped | 6.8 |
| LayerFadeNode | trigger, layerName, targetVolume, fadeTime | done, currentVolume | 6.8 |
| LayerBlendNode | layerA, layerB, blendParam, blendTime | done | 6.8 |
| LayerSwitchNode | state, transitionTime | switched, previousState | 6.8 |
| DuckNode | trigger, release, targetLayers, duckAmount | ducking, currentReduction | 6.8 |
| SidechainNode | audio, sidechain, threshold, ratio | audio, gainReduction | 6.8 |

### Control Nodes (7)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| SubgraphNode | mirrors subgraph I/O | mirrors subgraph I/O | 6.7 |
| VariableNode | set, value | value, changed | 6.7 |
| EmitEventNode | trigger, eventId, payload | emitted | 6.7 |
| CommentNode | — | — | 6.7 |
| GroupNode | — | — | 6.7 |
| DebugLogNode | value, trigger | passthrough | 6.7 |
| AccessibilityNode | trigger, audioEvent, volume | adjustedVolume, visualPulse, hapticPulse | 52 |

### State & Memory Nodes (3)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| StateStoreNode | set, value, clear | value, exists, changed | 6.10 |
| AccumulatorNode | add, value, reset | total, count, average, min, max | 6.10 |
| EventHistoryNode | query | count, lastTimestamp, timeSinceLast, payloads | 6.10 |

### Analytics & Emotion Nodes (4)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| VolatilityAnalyzerNode | winAmount, betAmount, spinTrigger | volatility, trend, winRate, hotStreak, coldStreak | 6.11 |
| ExcitementMapperNode | winTier, nearMiss, featureActive, etc. | excitement, mood, intensityTarget | 6.11 |
| PlayerBehaviorNode | spinTrigger, betChange, autoplayActive | playStyle, engagement, fatigueLevel | 6.11 |
| BigWinOrchestratorNode | winTier, winAmount, betAmount, trigger | phase, phaseProgress, intensity, layerTargets | 6.11 |

### Slot-Specific Nodes (7)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| WinTierNode | winAmount, betAmount, payload | tier, tierIndex, multiplier, isJackpot | 6.12 |
| ReelAnalyzerNode | payload, reelIndex | symbols, isWild, isScatter, isNearMiss | 6.12 |
| FeatureStateNode | payload | currentFeature, isBaseGame, isFreeSpins, featureDepth | 6.12 |
| AnticipationNode | reelsLanded, totalReels, scatterCount | anticipationLevel, isActive, anticipationType | 6.12 |
| RollupNode | startAmount, endAmount, duration, trigger | currentAmount, progress, tick, done | 6.12 |
| SymbolMatchNode | payload | matchCount, matchSymbol, paylineIndex, isFullLine | 6.12 |
| LocalizationNode | baseAsset, region | resolvedAsset, isOverridden | 53 |

### Music Nodes (2)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| MusicStateMachineNode | setState, trigger, syncOverride | currentState, beat, bar, position, tempo | 45 |
| StingerNode | trigger, stingerId, syncOverride | played, blocked, syncPosition | 49 |

### Bus Routing Nodes (4)
| Node | Inputs | Outputs | Section |
|------|--------|---------|---------|
| BusRouteNode | voice, busName | routed | 46 |
| BusControlNode | busName, volume, mute, solo | done | 46 |
| AuxSendControlNode | sourceBus, targetBus, sendLevel | done | 46 |
| MixSnapshotNode | trigger, fadeTime | applied | 46 |

### Container Nodes (5)
| Node | Type | Section |
|------|------|---------|
| RandomContainer | Weighted random child selection | 17 |
| SequenceContainer | Sequential child playback | 17 |
| BlendContainer | Parameter-driven blend | 17 |
| SwitchContainer | State-driven switch | 17 |
| LayerContainer | Simultaneous playback | 17 |

**Total: 93 node types across 14 categories.**

---

## Cross-Reference: Related Documents

| Document | Relationship |
|----------|-------------|
| `AUTOMATIC_EVENT_DISCOVERY_SYSTEM.md` | Discovery → events → Hook Graph Registry → execution |
| `CLAUDE.md` | Core rules that Hook Graph MUST follow |
| `.claude/architecture/UNIFIED_SLOTLAB.md` | SlotLab architecture that Hook Graph integrates with |
| `.claude/architecture/AUREXIS.md` | Audio engine that Hook Graph Rust nodes run on |
| `.claude/architecture/EVENT_SYNC.md` | Event synchronization system |
| `.claude/docs/DEPENDENCY_INJECTION.md` | GetIt singleton pattern for providers |

---

*Ovaj dokument je architecture blueprint. Implementacija ide fazno (Phase 1-7). Svaka faza se implementira, testira, i validira pre prelaska na sledeću.*

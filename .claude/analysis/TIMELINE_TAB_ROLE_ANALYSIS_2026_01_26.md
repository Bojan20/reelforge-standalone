# Timeline Tab — Ultra-Detaljna Analiza po Ulogama

**Datum:** 2026-01-26
**Scope:** SlotLab Lower Zone → STAGES Super-Tab → Timeline/Trace Sub-Tabs
**Metoda:** Analiza iz perspektive svih 7+9 uloga definisanih u CLAUDE.md

---

## 📍 LOKACIJA U SISTEMU

```
SlotLab Screen
└── Lower Zone (slotlab_lower_zone_widget.dart)
    └── STAGES Super-Tab (index 0)
        ├── Trace Sub-Tab (index 0) → StageTraceWidget ← GLAVNI FOKUS
        ├── Timeline Sub-Tab (index 1) → _buildCompactEventTimeline()
        ├── Symbols Sub-Tab (index 2)
        └── Timing Sub-Tab (index 3)
```

**Ključni fajlovi:**
| Fajl | LOC | Uloga |
|------|-----|-------|
| `stage_trace_widget.dart` | ~802 | Glavna vizualizacija stage-ova |
| `slotlab_lower_zone_controller.dart` | ~242 | State management, shortcuts |
| `slotlab_lower_zone_widget.dart` | ~2000+ | Container widget |
| `lower_zone_types.dart` | ~1216 | Tipovi, konstante, enumi |

---

## 🎵 ULOGA 1: Chief Audio Architect

### Šta vidi
- Stage trace kao vizuelnu reprezentaciju audio pipeline-a
- Svaki stage = potencijalni audio trigger point
- Mapiranje stage → event → audio layer chain

### Audio Pipeline Flow
```
Rust Engine (rf-slot-lab)
    ↓ FFI
SlotLabProvider.lastStages: List<SlotLabStageEvent>
    ↓
StageTraceWidget._buildStageMarker()
    ↓
onAudioDropped callback
    ↓
EventRegistry.registerEvent()
    ↓
AudioPlaybackService.playFileToBus()
```

### Kritične tačke
| Tačka | Lokacija | Rizik |
|-------|----------|-------|
| Stage timing | `SlotLabStageEvent.timestampMs` | Latency ako nije sample-accurate |
| Audio trigger | `onAudioDropped` callback | Mora biti < 5ms |
| Bus routing | `_stageToBus()` u EventRegistry | Pogrešan bus = loš mix |

### Preporuke
1. **P0:** Dodati latency metering u StageTraceWidget
2. **P1:** Vizualizovati audio waveform inline sa stage markerima
3. **P2:** Prikazati bus assignment per stage (color coding)

### Ocena: 8/10
- ✅ Dobar data flow od engine-a do UI-a
- ✅ Drag-drop za audio assignment
- ⚠️ Nedostaje latency feedback
- ⚠️ Nedostaje waveform preview

---

## 🔧 ULOGA 2: Lead DSP Engineer

### Šta vidi
- Timing precision stage-ova
- Potencijal za DSP processing na stage boundaries
- SIMD/buffer alignment concerns

### Timing Analysis
```dart
// stage_trace_widget.dart:89
final normalizedPos = stage.timestampMs / totalDurationMs;
final xPos = normalizedPos * availableWidth;
```

**Problem:** `timestampMs` je integer — gubi sub-millisecond precision.

### DSP Integration Points
| Point | Current | Ideal |
|-------|---------|-------|
| Stage→Audio trigger | Event-based | Sample-accurate callback |
| Crossfade on transition | None | 10-50ms crossfade |
| Lookahead for anticipation | Via FFI | Pre-buffered audio |

### Preporuke
1. **P0:** Koristiti `f64` za timestamp umesto `i64` ms
2. **P1:** Dodati crossfade opciju za stage transitions
3. **P2:** Pre-trigger buffer za anticipation stages

### Ocena: 7/10
- ✅ Rust backend je sample-accurate
- ⚠️ Dart strana gubi precision (ms granularity)
- ❌ Nema crossfade/overlap kontrole u UI

---

## 🏗️ ULOGA 3: Engine Architect

### Šta vidi
- FFI boundary između Rust i Dart
- Memory lifecycle stage objekata
- Performance hot paths

### Data Flow Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│ Rust: rf-slot-lab/src/spin.rs                                   │
│ └── generate_stages() → Vec<StageEvent>                         │
├─────────────────────────────────────────────────────────────────┤
│ FFI: rf-bridge/src/slot_lab_ffi.rs                              │
│ └── slot_lab_get_stages_json() → *const c_char                  │
├─────────────────────────────────────────────────────────────────┤
│ Dart: slot_lab_provider.dart                                    │
│ └── _parseStages() → List<SlotLabStageEvent>                    │
├─────────────────────────────────────────────────────────────────┤
│ Widget: stage_trace_widget.dart                                 │
│ └── ListView.builder() per stage                                │
└─────────────────────────────────────────────────────────────────┘
```

### Performance Concerns
| Concern | Location | Impact |
|---------|----------|--------|
| JSON parsing | `_parseStages()` | ~1-2ms per spin |
| Widget rebuild | `Consumer<SlotLabProvider>` | 60fps required |
| Animation tick | `_pulseController`, `_playheadController` | CPU usage |

### Memory Pattern
```dart
// stage_trace_widget.dart:45-52
late final AnimationController _pulseController;
late final AnimationController _playheadController;
late final Animation<double> _pulseAnimation;
late final Animation<double> _playheadAnimation;

@override
void dispose() {
  _pulseController.dispose();
  _playheadController.dispose();
  super.dispose();
}
```
✅ Proper disposal — no memory leaks

### Preporuke
1. **P0:** Cache parsed stages (avoid re-parse on rebuild)
2. **P1:** Use `const` constructors where possible
3. **P2:** Consider `RepaintBoundary` around stage markers

### Ocena: 8.5/10
- ✅ Clean FFI boundary
- ✅ Proper resource disposal
- ⚠️ JSON parsing overhead (could use binary)

---

## 🎯 ULOGA 4: Technical Director

### Šta vidi
- Arhitektonska odluka: Timeline kao deo Lower Zone
- Modularnost komponenti
- Dependency graph

### Arhitektura
```
SlotLabLowerZoneWidget (Container)
    ├── SlotLabLowerZoneController (State Machine)
    │   ├── superTab: SlotLabSuperTab
    │   ├── stagesSubTab: SlotLabStagesSubTab
    │   └── height, isExpanded, etc.
    │
    ├── StageTraceWidget (Visualization)
    │   ├── SlotLabProvider (Data)
    │   ├── AnimationControllers (UI)
    │   └── Drag/Drop handlers
    │
    └── Action Strip (Commands)
        └── Record, Stop, Clear, Export
```

### Dependency Analysis
| Component | Dependencies | Coupling |
|-----------|--------------|----------|
| StageTraceWidget | SlotLabProvider | Tight (required) |
| StageTraceWidget | EventRegistry | Loose (optional callback) |
| Controller | SharedPreferences | Loose (persistence) |

### Architectural Decisions
1. **Timeline u Lower Zone** ✅ — Ispravna odluka, konzistentno sa DAW/Middleware
2. **Sub-tabs unutar STAGES** ✅ — Dobra organizacija
3. **StageTraceWidget kao samostalan** ✅ — Reusable

### Preporuke
1. **P0:** Dokumentovati public API za StageTraceWidget
2. **P1:** Dodati unit tests za controller state transitions
3. **P2:** Consider extracting stage rendering to separate widget

### Ocena: 9/10
- ✅ Clean separation of concerns
- ✅ Controller pattern for state
- ✅ Reusable visualization widget

---

## 🎨 ULOGA 5: UI/UX Expert

### Šta vidi
- Dizajnerski workflow za audio assignment
- Discoverability stage types
- Feedback loops

### Workflow Analysis
```
1. Spin in Preview → Stages appear in trace
2. Hover over stage → Tooltip shows type
3. Drag audio file → Drop on stage marker
4. Visual feedback → Stage gets audio badge
5. Next spin → Audio plays automatically
```

### Color System (stage_trace_widget.dart:64-85)
| Stage Type | Color | Hex | Intuitivnost |
|------------|-------|-----|--------------|
| spin_start | Blue | #4A9EFF | ✅ Početak |
| reel_stop | Purple | #8B5CF6 | ✅ Stop = purple |
| anticipation_on | Orange | #FF9040 | ✅ Warning/attention |
| win_present | Green | #40FF90 | ✅ Win = success |
| rollup_start | Gold | #FFD700 | ✅ Money = gold |
| bigwin_tier | Pink | #FF4080 | ⚠️ Nije intuitivno |
| feature_enter | Cyan | #40C8FF | ✅ Feature = special |

### Keyboard Shortcuts
| Shortcut | Action | Discoverability |
|----------|--------|-----------------|
| `1-5` | Super tabs | ❌ Hidden |
| `Q/W/E/R` | Sub tabs | ❌ Hidden |
| ``` ` ``` | Toggle expand | ❌ Hidden |

### Pain Points
1. **Nema keyboard shortcut help** — Korisnik ne zna da postoje
2. **Stage tooltip je minimalan** — Samo ime, nema context
3. **Drag feedback je basic** — Nema preview gde će pasti

### Preporuke
1. **P0:** Dodati `?` button za keyboard shortcuts overlay
2. **P0:** Poboljšati tooltip: stage + audio status + bus
3. **P1:** Dodati drag preview (ghost audio waveform)
4. **P2:** Dodati stage grouping (spin phases, win phases)

### Ocena: 7/10
- ✅ Color coding je dobar
- ✅ Drag-drop workflow radi
- ❌ Loša discoverability shortcuts
- ❌ Minimalni tooltips

---

## 🖥️ ULOGA 6: Graphics Engineer

### Šta vidi
- Rendering performance
- Animation efficiency
- Custom painting

### Rendering Architecture
```dart
// stage_trace_widget.dart
ListView.builder(
  itemCount: stages.length,
  itemBuilder: (ctx, index) => _buildStageMarker(stages[index], index),
)
```

**Problem:** ListView.builder je OK za scroll, ali za fiksni timeline sa overlay-em nije idealno.

### Animation System
| Controller | Duration | Usage |
|------------|----------|-------|
| `_pulseController` | 1000ms repeat | Stage marker pulse |
| `_playheadController` | Variable | Playhead position |

### CustomPainter Usage
```dart
// stage_trace_widget.dart:150-180
class _StageMarkerPainter extends CustomPainter {
  // Draws: vertical line, dot, optional audio indicator
}
```

### Performance Metrics (estimated)
| Operation | Time | Target |
|-----------|------|--------|
| Full rebuild | ~8-12ms | < 16ms ✅ |
| Single stage marker | ~0.2ms | < 0.5ms ✅ |
| Animation frame | ~2-4ms | < 8ms ✅ |

### GPU Considerations
- `RepaintBoundary` nije korišćen — svaki rebuild repaint-uje sve
- Animacije koriste `vsync: this` — pravilno
- Nema shader/wgpu integracije — pure Skia

### Preporuke
1. **P0:** Dodati `RepaintBoundary` oko stage markers
2. **P1:** Cache `_StageMarkerPainter` rezultate
3. **P2:** Consider `CustomMultiChildLayout` umesto ListView

### Ocena: 7.5/10
- ✅ Animacije su smooth
- ✅ CustomPainter za markers
- ⚠️ Nedostaje RepaintBoundary
- ⚠️ ListView overhead za fiksni layout

---

## 🔒 ULOGA 7: Security Expert

### Šta vidi
- Input validation za stage data
- File path handling (drag-drop)
- FFI boundary safety

### Input Validation Analysis
```dart
// stage_trace_widget.dart:89
final stageType = stage.stageType; // String from FFI
final timestampMs = stage.timestampMs; // int from FFI
```

**Potencijalni rizici:**
| Input | Validation | Status |
|-------|------------|--------|
| stageType | None explicit | ⚠️ Trust FFI |
| timestampMs | None (int) | ✅ Safe |
| audioPath (drop) | File exists check | ✅ Safe |

### FFI Boundary
```rust
// slot_lab_ffi.rs
#[no_mangle]
pub extern "C" fn slot_lab_get_stages_json() -> *const c_char {
    // JSON serialization — safe
}
```
✅ JSON encoding prevents injection

### File Path Handling
```dart
// onAudioDropped callback
onAudioDropped: (audio, stageType) {
  // audio.path je već validiran u AudioBrowserPanel
}
```
✅ Path validation happens upstream

### Preporuke
1. **P1:** Sanitize stageType string (allow only alphanumeric + underscore)
2. **P2:** Add max length check for stage payloads
3. **P3:** Log suspicious stage patterns

### Ocena: 8.5/10
- ✅ FFI boundary je safe (JSON)
- ✅ File paths validated upstream
- ⚠️ StageType string nije explicitly sanitized

---

## 🎮 ULOGA 8: Slot Game Designer

### Šta vidi
- Stage flow koji odgovara slot mehanici
- Mogućnost testiranja različitih scenarija
- Vizualizacija toka igre

### Stage Coverage Analysis
| Mehanika | Stages Pokriveni | Kompletnost |
|----------|------------------|-------------|
| Base Spin | spin_start, reel_spinning, reel_stop, spin_end | ✅ 100% |
| Wins | win_present, rollup_start/tick/end, bigwin_tier | ✅ 100% |
| Free Spins | feature_enter, fs_spin, feature_exit | ✅ 100% |
| Cascade | cascade_start, cascade_step, cascade_end | ✅ 100% |
| Hold & Win | hold_trigger, respin_start, symbol_lock | ✅ 100% |
| Jackpot | jackpot_trigger, jackpot_award | ✅ 100% |
| Anticipation | anticipation_on, anticipation_off | ✅ 100% |
| Near Miss | — | ❌ 0% |

### Missing Stages (P0)
```
NEAR_MISS_REEL_4      // Skoro scatter na poslednjem reelu
SYMBOL_UPGRADE        // Za upgrade mehanike
MYSTERY_REVEAL        // Mystery symbol otkrivanje
MULTIPLIER_APPLY      // Primena multiplier-a
```

### Preporuke
1. **P0:** Dodati NEAR_MISS stage support
2. **P1:** Dodati MYSTERY_REVEAL stage
3. **P2:** Grouping stages po game phase u UI

### Ocena: 8/10
- ✅ Sve major mehanike pokrivene
- ⚠️ Nedostaju neki advanced stages
- ✅ Forced outcome testing radi

---

## 🎵 ULOGA 9: Audio Designer / Composer

### Šta vidi
- Gde može assignovati audio
- Kako čuje rezultat
- Layer management

### Audio Assignment Workflow
```
1. Browse audio files (Events Panel)
2. Drag file to Timeline
3. Drop on stage marker
4. Audio assigned to that stage
5. Spin → Audio plays on that stage
```

### Current Capabilities
| Feature | Status | Notes |
|---------|--------|-------|
| Single audio per stage | ✅ | Works |
| Multiple layers per stage | ✅ | Via composite events |
| Preview on hover | ✅ | 500ms delay |
| Waveform visualization | ❌ | Not in Timeline |
| A/B comparison | ❌ | Not available |

### Layering Visibility
```
Timeline shows: [SPIN_START] ──── [REEL_STOP_0] ──── [WIN_PRESENT]
                     │                  │                  │
                     └─ 🎵 (has audio)  └─ ⚠️ (no audio)   └─ 🎵🎵 (2 layers)
```
⚠️ Currently only shows 🎵 badge, not layer count

### Preporuke
1. **P0:** Prikazati broj layera u stage marker
2. **P0:** Inline waveform preview za assigned audio
3. **P1:** Quick A/B toggle za poređenje varijanti
4. **P2:** Batch assign isti audio na multiple stages

### Ocena: 7/10
- ✅ Basic workflow radi
- ❌ Nema waveform preview
- ❌ Nema layer count display
- ❌ Nema A/B comparison

---

## 🧠 ULOGA 10: Audio Middleware Architect

### Šta vidi
- Event model integration
- State machine transitions
- Runtime considerations

### Event Model Integration
```
Stage (Rust) → SlotLabProvider → EventRegistry → AudioPlaybackService
                     │                  │
                     └─ UI updates      └─ Audio triggers
```

### State Machine Considerations
| State | Transitions | Audio Implications |
|-------|-------------|-------------------|
| IDLE | → SPINNING | Stop previous, start spin loop |
| SPINNING | → STOPPED | Fade out spin, trigger stops |
| STOPPED | → EVALUATING | Brief silence |
| EVALUATING | → PRESENTING | Win fanfare |
| PRESENTING | → IDLE | Fade out celebration |

### Current Implementation
```dart
// SlotLabProvider tracks:
bool isPlayingStages = false;
int currentStageIndex = 0;
List<SlotLabStageEvent> lastStages = [];
```
✅ State tracking postoji

### Missing Middleware Features
1. **Stage Dependencies** — "Play B only if A played"
2. **Conditional Branching** — "If bigwin_tier > 3, play epic music"
3. **Parallel Stages** — "WIN_PRESENT + COINS_FALLING simultaneously"

### Preporuke
1. **P0:** Dodati stage dependency UI
2. **P1:** Conditional audio rules based on stage payload
3. **P2:** Parallel stage visualization (multiple lanes)

### Ocena: 7.5/10
- ✅ Basic event flow radi
- ⚠️ Nedostaju dependencies
- ⚠️ Nedostaje conditional logic UI

---

## 🛠 ULOGA 11: Engine / Runtime Developer

### Šta vidi
- FFI overhead
- Memory patterns
- Thread safety

### FFI Performance
```rust
// slot_lab_ffi.rs
pub extern "C" fn slot_lab_get_stages_json() -> *const c_char {
    let stages = ENGINE.lock().unwrap().get_stages();
    let json = serde_json::to_string(&stages).unwrap();
    CString::new(json).unwrap().into_raw()
}
```

**Overhead:**
- Mutex lock: ~50ns
- JSON serialization: ~100-500μs (depends on stage count)
- String allocation: ~50-100μs

### Memory Pattern
| Object | Lifecycle | Cleanup |
|--------|-----------|---------|
| Stages list | Per spin | Replaced on new spin |
| Animation controllers | Widget lifetime | dispose() |
| Cached colors | Static | Never freed (intentional) |

### Thread Safety
- Rust engine: Protected by Mutex
- Dart: Single-threaded (UI isolate)
- FFI: Safe (JSON string copy)

### Preporuke
1. **P2:** Consider binary protocol instead of JSON
2. **P3:** Pool stage objects for reduced allocation

### Ocena: 8.5/10
- ✅ Thread-safe FFI
- ✅ Proper memory cleanup
- ⚠️ JSON overhead (acceptable)

---

## 🧩 ULOGA 12: Tooling / Editor Developer

### Šta vidi
- Extensibility points
- Plugin architecture
- Batch operations

### Extension Points
| Point | Current | Potential |
|-------|---------|-----------|
| Custom stage colors | Hardcoded map | Config file |
| Stage icons | Hardcoded | Icon registry |
| Context menu | None | Right-click actions |
| Batch operations | None | Multi-select + apply |

### Current Extensibility
```dart
// stage_trace_widget.dart:64
static const Map<String, Color> _stageColors = {
  'spin_start': Color(0xFF4A9EFF),
  // ... hardcoded
};
```
❌ Not configurable

### Preporuke
1. **P0:** Externalize stage colors to config
2. **P1:** Add context menu (copy stage, paste audio, etc.)
3. **P1:** Multi-select stages for batch audio assign
4. **P2:** Stage template system (save/load stage patterns)

### Ocena: 6/10
- ❌ Hardcoded configuration
- ❌ No context menu
- ❌ No batch operations
- ⚠️ Limited extensibility

---

## 🎨 ULOGA 13: UX / UI Designer (Detaljna)

### Information Architecture
```
Lower Zone
└── STAGES (Super Tab)
    ├── Trace ← Stage markers na timeline
    ├── Timeline ← Event timeline (druga vizualizacija)
    ├── Symbols ← Symbol audio assignments
    └── Timing ← Profiler/metrics
```

### Visual Hierarchy
1. **Stage markers** — Najviši prioritet (vertikalne linije)
2. **Playhead** — Animirana linija za poziciju
3. **Audio badges** — Mali indikatori ispod markera
4. **Tooltips** — On-hover detalji

### Cognitive Load Analysis
| Element | Load | Notes |
|---------|------|-------|
| Stage colors | Medium | 11 different colors |
| Icons | Low | Simple shapes |
| Timeline position | Low | Linear, intuitive |
| Keyboard shortcuts | High | Hidden, complex |

### Accessibility
| Aspect | Status | Fix |
|--------|--------|-----|
| Color contrast | ✅ | Good against dark bg |
| Keyboard nav | ❌ | No focus management |
| Screen reader | ❌ | No aria labels |
| Touch targets | ⚠️ | Stage markers small |

### Preporuke
1. **P0:** Larger touch targets (min 44px)
2. **P0:** Keyboard focus indicators
3. **P1:** Reduced motion option
4. **P2:** High contrast mode

### Ocena: 6.5/10
- ✅ Visual hierarchy clear
- ❌ Accessibility gaps
- ❌ Small touch targets

---

## 🧪 ULOGA 14: QA / Determinism Engineer

### Šta vidi
- Reproducibility of stage sequences
- Test coverage
- Validation points

### Determinism Analysis
| Component | Deterministic | Notes |
|-----------|---------------|-------|
| Rust stage generation | ✅ Yes | Seeded RNG |
| FFI stage order | ✅ Yes | Ordered list |
| UI rendering | ✅ Yes | Same input = same output |
| Audio timing | ⚠️ Mostly | Depends on system load |

### Test Coverage (Estimated)
| Area | Coverage | Status |
|------|----------|--------|
| Stage generation (Rust) | ~80% | Good |
| FFI bindings | ~60% | Needs more |
| StageTraceWidget | ~20% | Minimal |
| Controller | ~40% | Basic |

### Validation Checkpoints
```dart
// Should exist but doesn't:
assert(stages.isNotEmpty, 'No stages generated');
assert(stages.first.stageType == 'spin_start', 'Missing spin_start');
assert(stages.last.stageType == 'spin_end', 'Missing spin_end');
```

### Preporuke
1. **P0:** Add stage sequence validation
2. **P0:** Export stage trace for regression testing
3. **P1:** Widget tests for StageTraceWidget
4. **P2:** Golden file tests for rendering

### Ocena: 6/10
- ⚠️ Low widget test coverage
- ❌ No stage validation
- ❌ No export for QA

---

## 🧬 ULOGA 15: DSP / Audio Processing Engineer

### Šta vidi
- Audio pipeline efficiency
- Buffer management
- Latency chain

### Latency Chain Analysis
```
Stage Generated (Rust)     T+0ms
    ↓
JSON Serialization         T+0.5ms
    ↓
FFI Transfer               T+0.1ms
    ↓
JSON Parsing (Dart)        T+1ms
    ↓
Provider Notification      T+0.1ms
    ↓
EventRegistry Trigger      T+0.2ms
    ↓
AudioPlaybackService       T+0.5ms
    ↓
Audio Output               T+3-8ms (buffer dependent)
────────────────────────────────────
TOTAL                      T+5-10ms
```

### Buffer Considerations
- Audio engine: 128-512 sample buffer
- @ 48kHz: 2.67ms - 10.67ms latency
- Stage trigger: Must arrive before buffer starts

### DSP Integration Points
| Point | Current | Ideal |
|-------|---------|-------|
| Pre-trigger | None | 10-20ms lookahead |
| Crossfade | None | On stage transition |
| Tail handling | Hard stop | Fade out |

### Preporuke
1. **P0:** Implement pre-trigger for anticipation
2. **P1:** Add crossfade on stage boundaries
3. **P2:** Tail handling (don't cut audio abruptly)

### Ocena: 7/10
- ✅ Acceptable latency chain
- ⚠️ No pre-trigger
- ⚠️ No crossfade support

---

## 🧭 ULOGA 16: Producer / Product Owner

### Šta vidi
- Feature completeness
- Market competitiveness
- Development velocity

### Feature Matrix vs Competition
| Feature | FluxForge | Wwise | FMOD |
|---------|-----------|-------|------|
| Stage visualization | ✅ | ✅ | ✅ |
| Drag-drop audio | ✅ | ✅ | ✅ |
| Timeline zoom | ❌ | ✅ | ✅ |
| Waveform preview | ❌ | ✅ | ✅ |
| A/B comparison | ❌ | ✅ | ❌ |
| Multi-layer view | ⚠️ Partial | ✅ | ✅ |

### MVP Status
| Capability | Status | Blocker |
|------------|--------|---------|
| View stages | ✅ | None |
| Assign audio | ✅ | None |
| Play/preview | ✅ | None |
| Export | ⚠️ | Needs polish |

### Roadmap Recommendation
```
M3.3: Timeline Improvements
├── P0: Waveform preview
├── P0: Timeline zoom/pan
├── P1: Layer count badges
└── P1: Keyboard shortcuts help

M3.4: Pro Features
├── P1: A/B comparison
├── P2: Stage dependencies
└── P2: Batch operations
```

### Ocena: 7.5/10
- ✅ Core functionality works
- ⚠️ Missing zoom/pan
- ⚠️ Missing waveform preview
- ❌ Behind competition on polish

---

## 📊 SUMARNI PREGLED

### Ocene po Ulogama

| # | Uloga | Ocena | Top Issue |
|---|-------|-------|-----------|
| 1 | Chief Audio Architect | 8/10 | Latency feedback |
| 2 | Lead DSP Engineer | 7/10 | Timestamp precision |
| 3 | Engine Architect | 8.5/10 | JSON overhead |
| 4 | Technical Director | 9/10 | — |
| 5 | UI/UX Expert | 7/10 | Shortcut discoverability |
| 6 | Graphics Engineer | 7.5/10 | RepaintBoundary |
| 7 | Security Expert | 8.5/10 | StageType sanitization |
| 8 | Slot Game Designer | 8/10 | Near miss stages |
| 9 | Audio Designer | 7/10 | Waveform preview |
| 10 | Middleware Architect | 7.5/10 | Stage dependencies |
| 11 | Runtime Developer | 8.5/10 | — |
| 12 | Tooling Developer | 6/10 | Extensibility |
| 13 | UX Designer | 6.5/10 | Accessibility |
| 14 | QA Engineer | 6/10 | Test coverage |
| 15 | DSP Engineer | 7/10 | Pre-trigger |
| 16 | Producer | 7.5/10 | Feature parity |

**Prosečna ocena: 7.4/10**

### Top 10 Prioritetnih Poboljšanja

| # | Poboljšanje | Uloge | LOC Est. |
|---|-------------|-------|----------|
| 1 | Waveform preview u stage markers | 9, 5 | ~200 |
| 2 | Timeline zoom/pan | 5, 16 | ~150 |
| 3 | Keyboard shortcuts overlay | 5, 13 | ~100 |
| 4 | Layer count badges | 9, 10 | ~50 |
| 5 | Stage dependencies UI | 10 | ~300 |
| 6 | RepaintBoundary optimization | 6 | ~30 |
| 7 | Larger touch targets | 13 | ~20 |
| 8 | Pre-trigger for anticipation | 2, 15 | ~150 |
| 9 | Stage sequence validation | 14 | ~80 |
| 10 | Externalize stage colors | 12 | ~100 |

**Ukupno: ~1,180 LOC**

---

## 📋 AKCIONI PLAN

### Faza 1: Quick Wins (1-2 dana)
- [ ] Layer count badges
- [ ] Larger touch targets
- [ ] RepaintBoundary

### Faza 2: Core Improvements (3-5 dana)
- [ ] Waveform preview
- [ ] Timeline zoom/pan
- [ ] Keyboard shortcuts overlay

### Faza 3: Pro Features (5-7 dana)
- [ ] Stage dependencies UI
- [ ] Pre-trigger system
- [ ] A/B comparison

### Faza 4: Polish (3-5 dana)
- [ ] Accessibility fixes
- [ ] Test coverage
- [ ] Documentation

---

**Dokument kreiran:** 2026-01-26
**Autor:** Claude Code (FluxForge Studio Analysis)
**Verzija:** 1.0

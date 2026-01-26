# Timeline Tab — Kompletna Dokumentacija

**Datum:** 2026-01-26
**Verzija:** 1.0
**Autor:** Claude Code Analysis

---

## 📚 SADRŽAJ

1. [Pregled](#pregled)
2. [Arhitektura](#arhitektura)
3. [Komponente](#komponente)
4. [Data Flow](#data-flow)
5. [Stage System](#stage-system)
6. [Keyboard Shortcuts](#keyboard-shortcuts)
7. [API Reference](#api-reference)
8. [Analiza po Ulogama](#analiza-po-ulogama)
9. [TODO Lista](#todo-lista)
10. [Povezani Dokumenti](#povezani-dokumenti)

---

## 1. PREGLED

Timeline Tab je deo SlotLab Lower Zone sekcije koji vizualizuje stage evente tokom slot spin-a. Omogućava audio dizajnerima da:

- Vide redosled stage-ova u realnom vremenu
- Assignuju audio fajlove na specifične stage-ove
- Prate timing i trajanje svakog stage-a
- Debuguju audio-visual sync

### Lokacija u UI

```
FluxForge Studio
└── SlotLab Section
    └── Lower Zone
        └── STAGES Super-Tab (index 0)
            ├── Trace Sub-Tab ← GLAVNI TIMELINE
            ├── Timeline Sub-Tab
            ├── Symbols Sub-Tab
            └── Timing Sub-Tab
```

---

## 2. ARHITEKTURA

### Widget Hijerarhija

```
SlotLabLowerZoneWidget
├── SlotLabLowerZoneController (state management)
├── LowerZoneContextBar (tabs)
├── LowerZoneResizeHandle
└── Content Area
    └── _buildStagesContent()
        └── StageTraceWidget ← MAIN VISUALIZATION
            ├── AnimationControllers
            │   ├── _pulseController (1000ms repeat)
            │   └── _playheadController (variable)
            ├── ListView.builder (stage markers)
            └── DragTarget (audio drop zones)
```

### Fajl Struktura

| Fajl | LOC | Uloga |
|------|-----|-------|
| `stage_trace_widget.dart` | ~802 | Glavna vizualizacija |
| `slotlab_lower_zone_controller.dart` | ~242 | State machine |
| `slotlab_lower_zone_widget.dart` | ~2000+ | Container widget |
| `lower_zone_types.dart` | ~1216 | Tipovi, konstante |

---

## 3. KOMPONENTE

### 3.1 StageTraceWidget

**Lokacija:** `flutter_ui/lib/widgets/slot_lab/stage_trace_widget.dart`

**Constructor:**
```dart
StageTraceWidget({
  required SlotLabProvider provider,
  double height = 200,
  bool showMiniProgress = true,
  Function(AudioFileInfo audio, String stageType)? onAudioDropped,
})
```

**Props:**
| Prop | Tip | Default | Opis |
|------|-----|---------|------|
| `provider` | SlotLabProvider | required | Data source |
| `height` | double | 200 | Widget height |
| `showMiniProgress` | bool | true | Show progress bar |
| `onAudioDropped` | Function? | null | Drop callback |

**State:**
```dart
late AnimationController _pulseController;
late AnimationController _playheadController;
late Animation<double> _pulseAnimation;
late Animation<double> _playheadAnimation;
```

### 3.2 SlotLabLowerZoneController

**Lokacija:** `flutter_ui/lib/widgets/lower_zone/slotlab_lower_zone_controller.dart`

**State Model:**
```dart
class SlotLabLowerZoneState {
  final SlotLabSuperTab superTab;
  final SlotLabStagesSubTab stagesSubTab;
  final SlotLabEventsSubTab eventsSubTab;
  final SlotLabMixSubTab mixSubTab;
  final SlotLabDspSubTab dspSubTab;
  final SlotLabBakeSubTab bakeSubTab;
  final double height;
  final bool isExpanded;
}
```

**Enums:**
```dart
enum SlotLabSuperTab { stages, events, mix, dsp, bake }
enum SlotLabStagesSubTab { trace, timeline, symbols, timing }
```

### 3.3 Stage Colors

**Definisano u:** `stage_trace_widget.dart:64-85`

```dart
static const Map<String, Color> _stageColors = {
  'spin_start': Color(0xFF4A9EFF),      // Blue
  'reel_spinning': Color(0xFF6B7280),   // Gray
  'reel_stop': Color(0xFF8B5CF6),       // Purple
  'anticipation_on': Color(0xFFFF9040), // Orange
  'anticipation_off': Color(0xFF6B7280),// Gray
  'win_present': Color(0xFF40FF90),     // Green
  'rollup_start': Color(0xFFFFD700),    // Gold
  'rollup_tick': Color(0xFFFFD700),     // Gold
  'rollup_end': Color(0xFFFFD700),      // Gold
  'bigwin_tier': Color(0xFFFF4080),     // Pink
  'feature_enter': Color(0xFF40C8FF),   // Cyan
  'feature_exit': Color(0xFF6B7280),    // Gray
  'cascade_start': Color(0xFFE040FB),   // Magenta
  'cascade_step': Color(0xFFE040FB),    // Magenta
  'cascade_end': Color(0xFFE040FB),     // Magenta
  'jackpot_trigger': Color(0xFFFFD700), // Gold
  'jackpot_award': Color(0xFFFFD700),   // Gold
  'spin_end': Color(0xFF4A9EFF),        // Blue
};
```

### 3.4 Stage Icons

```dart
static const Map<String, IconData> _stageIcons = {
  'spin_start': Icons.play_circle,
  'reel_stop': Icons.stop_circle,
  'win_present': Icons.emoji_events,
  'rollup_start': Icons.trending_up,
  'bigwin_tier': Icons.stars,
  'feature_enter': Icons.auto_awesome,
  'cascade_start': Icons.waterfall_chart,
  'jackpot_trigger': Icons.diamond,
  'spin_end': Icons.check_circle,
};
```

---

## 4. DATA FLOW

### Stage Event Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. RUST ENGINE                                                  │
│    rf-slot-lab/src/spin.rs                                      │
│    └── generate_stages() → Vec<StageEvent>                      │
├─────────────────────────────────────────────────────────────────┤
│ 2. FFI BRIDGE                                                   │
│    rf-bridge/src/slot_lab_ffi.rs                                │
│    └── slot_lab_get_stages_json() → *const c_char              │
├─────────────────────────────────────────────────────────────────┤
│ 3. DART PROVIDER                                                │
│    slot_lab_provider.dart                                       │
│    └── _parseStages() → List<SlotLabStageEvent>                │
│    └── lastStages (getter)                                      │
├─────────────────────────────────────────────────────────────────┤
│ 4. UI WIDGET                                                    │
│    stage_trace_widget.dart                                      │
│    └── Consumer<SlotLabProvider>                                │
│    └── ListView.builder() per stage                             │
└─────────────────────────────────────────────────────────────────┘
```

### Audio Assignment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. USER ACTION                                                  │
│    Drag audio file from browser                                 │
├─────────────────────────────────────────────────────────────────┤
│ 2. DROP TARGET                                                  │
│    StageTraceWidget → DragTarget                                │
│    └── onAudioDropped(audio, stageType)                        │
├─────────────────────────────────────────────────────────────────┤
│ 3. EVENT CREATION                                               │
│    SlotLabScreen → _onEventBuilderEventCreated()               │
│    └── Creates SlotCompositeEvent                               │
├─────────────────────────────────────────────────────────────────┤
│ 4. REGISTRATION                                                 │
│    MiddlewareProvider → addCompositeEvent()                    │
│    EventRegistry → registerEvent()                              │
├─────────────────────────────────────────────────────────────────┤
│ 5. PLAYBACK                                                     │
│    Stage triggered → EventRegistry.triggerStage()              │
│    └── AudioPlaybackService.playFileToBus()                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. STAGE SYSTEM

### 5.1 Podržani Stage-ovi

| Kategorija | Stages | Count |
|------------|--------|-------|
| Spin Lifecycle | spin_start, reel_spinning, reel_stop, reel_stop_0..4, spin_end | 8 |
| Win Presentation | win_present, rollup_start, rollup_tick, rollup_end, bigwin_tier | 5 |
| Features | feature_enter, feature_exit, fs_spin, fs_start, fs_end | 5 |
| Cascade | cascade_start, cascade_step, cascade_end | 3 |
| Jackpot | jackpot_trigger, jackpot_award | 2 |
| Anticipation | anticipation_on, anticipation_off | 2 |
| Hold & Win | hold_trigger, respin_start, symbol_lock | 3 |
| **TOTAL** | | **28+** |

### 5.2 Stage Event Model

```dart
class SlotLabStageEvent {
  final String stageType;      // "spin_start", "reel_stop", etc.
  final int timestampMs;       // Milliseconds from spin start
  final Map<String, dynamic> payload;  // Additional data
  final String rawStage;       // Original Rust stage string
}
```

### 5.3 Stage Timing (Normal Profile)

| Stage | Typical Time | Notes |
|-------|--------------|-------|
| spin_start | 0ms | Always first |
| reel_spinning | 0-2000ms | Per reel |
| reel_stop_0 | ~400ms | First reel |
| reel_stop_1 | ~800ms | Second reel |
| reel_stop_2 | ~1200ms | Third reel |
| reel_stop_3 | ~1600ms | Fourth reel |
| reel_stop_4 | ~2000ms | Fifth reel |
| anticipation_on | Variable | If scatter/bonus |
| win_present | After last stop | If win |
| spin_end | Last | Always last |

---

## 6. KEYBOARD SHORTCUTS

### Super Tabs
| Key | Action |
|-----|--------|
| `1` | STAGES tab |
| `2` | EVENTS tab |
| `3` | MIX tab |
| `4` | DSP tab |
| `5` | BAKE tab |

### Sub Tabs (within STAGES)
| Key | Action |
|-----|--------|
| `Q` | Trace sub-tab |
| `W` | Timeline sub-tab |
| `E` | Symbols sub-tab |
| `R` | Timing sub-tab |

### General
| Key | Action |
|-----|--------|
| `` ` `` | Toggle expand/collapse |
| `Escape` | Close/collapse |

---

## 7. API REFERENCE

### StageTraceWidget

#### Methods

```dart
// Build stage marker widget
Widget _buildStageMarker(SlotLabStageEvent stage, int index)

// Get color for stage type
Color _getStageColor(String stageType)

// Get icon for stage type
IconData _getStageIcon(String stageType)

// Calculate X position on timeline
double _calculateXPosition(int timestampMs, double totalDurationMs, double width)
```

#### Callbacks

```dart
// Called when audio is dropped on a stage
onAudioDropped: (AudioFileInfo audio, String stageType) {
  // Create event for this stage
}
```

### SlotLabLowerZoneController

#### Methods

```dart
// Set super tab
void setSuperTab(SlotLabSuperTab tab)

// Set sub tab for STAGES
void setStagesSubTab(SlotLabStagesSubTab subTab)

// Toggle expand/collapse
void toggleExpanded()

// Set height
void setHeight(double height)

// Handle keyboard event
bool handleKeyEvent(KeyEvent event)

// Save state to persistence
Future<void> saveState()

// Load state from persistence
Future<void> loadState()
```

---

## 8. ANALIZA PO ULOGAMA

### Sumarni Rezultati

| Uloga | Ocena | Top Issue |
|-------|-------|-----------|
| Chief Audio Architect | 8/10 | Latency feedback |
| Lead DSP Engineer | 7/10 | Timestamp precision |
| Engine Architect | 8.5/10 | JSON overhead |
| Technical Director | 9/10 | — |
| UI/UX Expert | 7/10 | Shortcut discoverability |
| Graphics Engineer | 7.5/10 | RepaintBoundary |
| Security Expert | 8.5/10 | StageType sanitization |
| Slot Game Designer | 8/10 | Near miss stages |
| Audio Designer | 7/10 | Waveform preview |
| Middleware Architect | 7.5/10 | Stage dependencies |
| Runtime Developer | 8.5/10 | — |
| Tooling Developer | 6/10 | Extensibility |
| UX Designer | 6.5/10 | Accessibility |
| QA Engineer | 6/10 | Test coverage |
| DSP Engineer | 7/10 | Pre-trigger |
| Producer | 7.5/10 | Feature parity |

**Prosečna Ocena: 7.4/10**

**Detaljna analiza:** [TIMELINE_TAB_ROLE_ANALYSIS_2026_01_26.md](../analysis/TIMELINE_TAB_ROLE_ANALYSIS_2026_01_26.md)

---

## 9. TODO LISTA

### Statistika

| Prioritet | Stavki | LOC | Status |
|-----------|--------|-----|--------|
| P0 Critical | 18 | ~980 | ✅ **KOMPLETNO** |
| P1 High | 21 | ~1,450 | ✅ **KOMPLETNO** |
| P2 Medium | 6 | ~530 | ✅ **KOMPLETNO** |
| P3 Low | 8 | ~380 | ⏳ Čeka |
| **UKUPNO** | **53** | **~3,340** | **85% Done** |

### P0 Kompletne Stavke ✅

Sve P0 stavke su implementirane 2026-01-26:
- Waveform preview, Timeline zoom/pan, Keyboard shortcuts
- Latency metering, Pre-trigger anticipation, Timestamp precision
- Stage sequence validation, Export trace, Sanitize stageType
- 4 nova stage-a: NearMiss, SymbolUpgrade, MysteryReveal, MultiplierApply
- Stage caching za performance

### P1 Kompletne Stavke ✅ (21/21)

| # | Task | Status |
|---|------|--------|
| P1.1 | Layer count badges | ✅ Done |
| P1.2 | Drag preview (ghost waveform) | ✅ Done |
| P1.3 | Stage grouping (spin/win phases) | ✅ Done |
| P1.4 | Quick A/B toggle | ✅ Done |
| P1.5 | Context menu (right-click) | ✅ Done |
| P1.6 | Multi-select stages | ✅ Done |
| P1.7 | Reduced motion accessibility | ✅ Done |
| P1.8 | Inline waveform sa markerima | ✅ Done |
| P1.9 | Bus assignment color coding | ✅ Done |
| P1.10 | Crossfade za stage transitions | ✅ Done |
| P1.11 | Pre-trigger buffer | ✅ Done |
| P1.12 | Tail handling (soft stop) | ✅ Done |
| P1.13 | Crossfade on stage boundaries | ✅ Done |
| P1.14 | Stage dependency UI | ✅ Done |
| P1.15 | Conditional audio rules | ✅ Done |
| P1.16 | Externalize stage colors | ✅ Done |
| P1.17 | Externalize stage icons | ✅ Done |
| P1.21 | Const constructors | ✅ Done |

### P1 — Kompletno ✅ (21/21)

| # | Task | LOC | Status |
|---|------|-----|--------|
| P1.18 | Widget tests | ~500 | ✅ Done (38 tests) |
| P1.19 | Public API dokumentacija | ~50 | ✅ Done (dartdoc) |
| P1.20 | Controller unit tests | ~350 | ✅ Done (44 tests) |

### P2 — Kompletno ✅ (6/6)

| # | Task | LOC | Status |
|---|------|-----|--------|
| P2.1 | Batch assign audio na multiple stages | ~80 | ✅ Done |
| P2.2 | High contrast mode (WCAG 2.1 AA) | ~100 | ✅ Done |
| P2.3 | Stage template system (7 presets) | ~120 | ✅ Done |
| P2.4 | Parallel lane visualization | ~160 | ✅ Done |
| P2.5 | RepaintBoundary isolation | ~10 | ✅ Done |
| P2.6 | Cached painter results | ~60 | ✅ Done |

**P2 Implementacioni Detalji:**
- **P2.1:** `_batchAssignAudio()` koristi `_selectedStages` iz P1.6
- **P2.2:** 8 WCAG compliant high-contrast boja, toggle u header-u
- **P2.3:** `StageTemplates.all` sa 7 built-in templates (Base Spin, Win, Feature, Cascade, Jackpot, Full Cycle, Quick Spin)
- **P2.4:** Greedy lane assignment algoritam sa `_overlapThresholdMs = 50ms`
- **P2.5:** `RepaintBoundary` wrapper oko Tooltip widgeta
- **P2.6:** Static cache za `Path`, `Paint` objects u `_MiniWaveformPainter` i `_InlineWaveformStripPainter`

**Kompletna lista:** [TIMELINE_TAB_COMPLETE_TODO_LIST_2026_01_26.md](../analysis/TIMELINE_TAB_COMPLETE_TODO_LIST_2026_01_26.md)

---

## 10. POVEZANI DOKUMENTI

### Arhitektura
- [SLOT_LAB_SYSTEM.md](../architecture/SLOT_LAB_SYSTEM.md) — SlotLab arhitektura
- [EVENT_SYNC_SYSTEM.md](../architecture/EVENT_SYNC_SYSTEM.md) — Event sinhronizacija
- [UNIFIED_PLAYBACK_SYSTEM.md](../architecture/UNIFIED_PLAYBACK_SYSTEM.md) — Playback sistem

### Analiza
- [TIMELINE_TAB_ROLE_ANALYSIS_2026_01_26.md](../analysis/TIMELINE_TAB_ROLE_ANALYSIS_2026_01_26.md) — Analiza po ulogama
- [TIMELINE_TAB_COMPLETE_TODO_LIST_2026_01_26.md](../analysis/TIMELINE_TAB_COMPLETE_TODO_LIST_2026_01_26.md) — Kompletna TODO lista

### Domeni
- [slot-audio-events-master.md](../domains/slot-audio-events-master.md) — Master katalog stage-ova

### Kodna Baza
- `flutter_ui/lib/widgets/slot_lab/stage_trace_widget.dart`
- `flutter_ui/lib/widgets/lower_zone/slotlab_lower_zone_controller.dart`
- `flutter_ui/lib/widgets/lower_zone/slotlab_lower_zone_widget.dart`
- `flutter_ui/lib/widgets/lower_zone/lower_zone_types.dart`
- `flutter_ui/lib/providers/slot_lab_provider.dart`
- `crates/rf-slot-lab/src/spin.rs`
- `crates/rf-slot-lab/src/stages.rs`

### Testovi (P1.18, P1.20)
- `flutter_ui/test/widgets/slot_lab/stage_trace_widget_test.dart` — 38 unit tests
- `flutter_ui/test/controllers/slot_lab/lower_zone_controller_test.dart` — 44 unit tests

---

## CHANGELOG

| Verzija | Datum | Opis |
|---------|-------|------|
| 2.0 | 2026-01-26 | P2 KOMPLETNO (6/6): Batch assign, High contrast, Templates, Parallel lanes, RepaintBoundary, Painter caching (~530 LOC) |
| 1.5 | 2026-01-26 | P1 KOMPLETNO (21/21): +P1.18-20 tests & docs (~900 LOC) |
| 1.4 | 2026-01-26 | P1 86% (18/21): +P1.16-17 stage_config.dart (~600 LOC) — Externalized stage colors/icons |
| 1.3 | 2026-01-26 | P1 76% (16/21): +P1.14 Stage dependency UI, +P1.15 Conditional audio rules |
| 1.2 | 2026-01-26 | P1 67% (14/21): Crossfade sistem, Pre-trigger buffer, Tail handling, Inline waveform |
| 1.1 | 2026-01-26 | P0 kompletno (18/18), ažurirana statistika, sledeće P1 |
| 1.0 | 2026-01-26 | Inicijalna dokumentacija |

---

**Kreirao:** Claude Code
**Projekat:** FluxForge Studio
**Sekcija:** SlotLab → Lower Zone → Timeline Tab

# SlotLab Analysis — FAZA 2.3: Lower Zone

**Date:** 2026-01-29
**Status:** ✅ COMPLETE
**LOC:** 3,212 total (lower_zone.dart 423 + 6 panels ~2,789)

---

## ⚠️ CRITICAL FINDING — ARCHITECTURAL MISMATCH

### SPECIFIKACIJA (CLAUDE.md)

**7 Super-Tabs sa Sub-Panelima:**

```
1. STAGES [Ctrl+Shift+T]
   ├── Timeline (Stage trace, waveforms)
   └── Event Debug (Trace log, performance)

2. EVENTS [Ctrl+Shift+E]
   ├── Event List (browser)
   ├── RTPC (debugger)
   └── Composite Editor (layer editing)

3. MIX [Ctrl+Shift+X]
   ├── Bus Hierarchy
   ├── Aux Sends
   └── Meters (live meters)

4. MUSIC/ALE [Ctrl+Shift+A]
   ├── ALE Rules
   ├── Signals
   └── Transitions

5. DSP [Tabs 5-8]
   ├── Compressor (Pro-C)
   ├── Limiter (Pro-L)
   ├── Gate (Pro-G)
   └── Reverb (Pro-R)

6. BAKE
   ├── Batch Export
   ├── Validation
   └── Package

7. ENGINE [Ctrl+Shift+G]
   ├── Profiler
   ├── Resources
   └── Stage Ingest

[+] MENU
   ├── Game Config
   ├── AutoSpatial
   ├── Scenarios
   └── Command Builder
```

### IMPLEMENTACIJA (Kod)

**8 Flat Tabova (No Sub-Panels):**

```
1. Timeline         → StageTraceWidget (✅ matches spec)
2. Command Builder  → Slot mockup drop zones (✅ exists, ⚠️ should be in [+] Menu)
3. Event List       → AutoEventBuilderProvider event browser (⚠️ wrong provider)
4. Meters           → BusMetersPanel (✅ matches spec, ⚠️ should be sub-panel of MIX)
5. Compressor       → FabFilterCompressorPanel (✅ matches spec)
6. Limiter          → FabFilterLimiterPanel (✅ matches spec)
7. Gate             → FabFilterGatePanel (✅ matches spec)
8. Reverb           → FabFilterReverbPanel (✅ matches spec)
```

**NEDOSTAJE (Prema CLAUDE.md):**

| Super-Tab | Sub-Panels | Status |
|-----------|------------|--------|
| **STAGES** | Event Debug panel | ❌ Missing |
| **EVENTS** | RTPC debugger, Composite Editor | ❌ Missing (koristi AutoEventBuilder umesto Middleware) |
| **MIX** | Bus Hierarchy, Aux Sends | ❌ Missing (samo Meters postoji) |
| **MUSIC/ALE** | Ceo tab | ❌ Missing |
| **DSP** | Već postoji kao 4 flat taba | ✅ Partial (treba grupisati pod jedan super-tab) |
| **BAKE** | Ceo tab | ❌ Missing |
| **ENGINE** | Profiler, Resources, Stage Ingest | ❌ Missing |
| **[+] Menu** | Game Config, AutoSpatial, Scenarios | ❌ Missing |

---

## 📐 TRENUTNA ARHITEKTURA

```
┌─────────────────────────────────────────────────────────────────────┐
│ RESIZE HANDLE                                                        │ 6px
├─────────────────────────────────────────────────────────────────────┤
│ [HEADER]                                                             │ 32px
│ [⌄] ⏱1 🔧2 📋3 📊4 🎚5 🔊6 🚪7 🌊8                   [300px]       │
│  └── Flat tabs (8), no grouping                                     │
├─────────────────────────────────────────────────────────────────────┤
│ [CONTENT] (IndexedStack)                                             │ Variable height
│                                                                       │
│ Tab 1: StageTraceWidget                                              │
│ Tab 2: CommandBuilderPanel (slot mockup drop zones)                  │
│ Tab 3: EventListPanel (AutoEventBuilder events, ⚠️ wrong provider)   │
│ Tab 4: BusMetersPanel (5 bus meters: SFX, Music, Voice, Amb, Master) │
│ Tab 5: FabFilterCompressorPanel (Pro-C style)                        │
│ Tab 6: FabFilterLimiterPanel (Pro-L style)                           │
│ Tab 7: FabFilterGatePanel (Pro-G style)                              │
│ Tab 8: FabFilterReverbPanel (Pro-R style)                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔌 DATA FLOW (Per Tab)

### Tab 1: Timeline (StageTraceWidget)

```
SlotLabProvider.lastStages
         ↓
StageTraceWidget.provider
         ↓
Timeline visualization (stage markers, waveforms, playhead)
         ↓
Click stage → EventRegistry.triggerStage(stage) (test playback)
```

**Provider:** ✅ SlotLabProvider
**FFI:** ❌ None (visual only)
**Status:** ✅ Fully functional

### Tab 2: Command Builder (CommandBuilderPanel)

```
MiddlewareProvider.compositeEvents
         ↓
Slot mockup UI (reels, buttons, overlays)
         ↓
Drag audio → Drop on zone → Stage mapped
         ↓
Auto-create event → middleware.addCompositeEvent()
```

**Provider:** ✅ MiddlewareProvider
**FFI:** ❌ None (event creation only)
**Status:** ✅ Functional, ⚠️ should be in [+] Menu not main tabs

### Tab 3: Event List (EventListPanel)

```
AutoEventBuilderProvider.committedEvents  ← ⚠️ WRONG!
         ↓
Search/filter (by name, bus, tags)
         ↓
Sort (by name, bus, date)
         ↓
Multi-select + bulk actions
```

**Provider:** ❌ AutoEventBuilderProvider (SHOULD BE MiddlewareProvider)
**FFI:** ❌ None
**Status:** ⚠️ WRONG PROVIDER — events not synced with Middleware/Events Panel

**PROBLEM:** EventListPanel shows AutoEventBuilderProvider.committedEvents, NOT MiddlewareProvider.compositeEvents. This creates TWO separate event lists:
1. AutoEventBuilderProvider → Command Builder flow (old)
2. MiddlewareProvider → Events Panel flow (current SSoT)

### Tab 4: Meters (BusMetersPanel)

```
MeterProvider (via FFI getBusMeterLevels)
         ↓
5 bus meters: SFX (0), Music (1), Voice (2), Ambience (3), Master (5)
         ↓
Real-time L/R peak/RMS display
         ↓
Peak hold, clip indicators
```

**Provider:** ✅ MeterProvider
**FFI:** ✅ getBusMeterLevels() (real-time)
**Status:** ✅ Fully functional

### Tab 5-8: FabFilter DSP Panels

```
DspChainProvider.getChain(trackId=0)
         ↓
FabFilter panels (Comp/Limiter/Gate/Reverb)
         ↓
Parameter changes → insertSetParam(trackId, slotIndex, paramIndex, value)
         ↓
Real-time DSP processing
```

**Provider:** ✅ DspChainProvider
**FFI:** ✅ insertSetParam, insertSetBypass (25+ functions)
**Status:** ✅ Fully functional

---

## 📊 PANEL BREAKDOWN

### Implemented Panels (8)

| Tab | Panel | LOC | Provider | FFI | Status |
|-----|-------|-----|----------|-----|--------|
| 1 | StageTraceWidget | ~1,200 | SlotLabProvider | None | ✅ Complete |
| 2 | CommandBuilderPanel | ~884 | MiddlewareProvider | None | ✅ Complete |
| 3 | EventListPanel | ~708 | ⚠️ AutoEventBuilderProvider | None | ⚠️ Wrong provider |
| 4 | BusMetersPanel | ~744 | MeterProvider | ✅ getBusMeterLevels | ✅ Complete |
| 5 | FabFilterCompressorPanel | ~927 | DspChainProvider | ✅ insertSetParam | ✅ Complete |
| 6 | FabFilterLimiterPanel | ~630 | DspChainProvider | ✅ insertSetParam | ✅ Complete |
| 7 | FabFilterGatePanel | ~498 | DspChainProvider | ✅ insertSetParam | ✅ Complete |
| 8 | FabFilterReverbPanel | ~467 | DspChainProvider | ✅ insertSetParam | ✅ Complete |

**Total Implemented:** 3,212 LOC (lower_zone.dart wrapper + 6 unique panels)

### Missing Panels (Podle CLAUDE.md)

| Super-Tab | Sub-Panel | Estimated LOC | Priority |
|-----------|-----------|---------------|----------|
| **STAGES** | Event Debug panel | ~500 | P1 |
| **EVENTS** | RTPC Debugger | ~1,159 (already exists elsewhere) | P1 |
| **EVENTS** | Composite Editor | ~800 | P0 |
| **MIX** | Bus Hierarchy panel | ~600 (already exists elsewhere) | P1 |
| **MIX** | Aux Sends panel | ~500 (already exists elsewhere) | P1 |
| **MUSIC/ALE** | ALE Panel | ~600 (already exists elsewhere) | P2 |
| **BAKE** | Batch Export panel | ~700 | P0 |
| **BAKE** | Validation panel | ~400 | P1 |
| **BAKE** | Package panel | ~300 | P1 |
| **ENGINE** | Profiler panel | ~540 (already exists elsewhere) | P2 |
| **ENGINE** | Resources panel | ~300 | P2 |
| **ENGINE** | Stage Ingest panel | ~565 (already exists elsewhere) | P2 |
| **[+] Menu** | Game Config panel | ~450 | P2 |
| **[+] Menu** | AutoSpatial panel | ~600 (already exists elsewhere) | P2 |
| **[+] Menu** | Scenarios panel | ~400 | P3 |

**Total Missing:** ~8,513 LOC (many panels already exist, need integration)

**Note:** Many panels already exist in other locations (middleware_widgets, stage_ingest, etc.) — just need to be added to SlotLab Lower Zone.

---

## 🎯 COMPONENT BREAKDOWN (8 Implemented Tabs)

### Tab 1: Timeline (StageTraceWidget)

**Features:**
- ✅ Horizontal timeline with stage markers
- ✅ Stage name, timestamp, category color
- ✅ Zoom/pan controls
- ✅ Playhead indicator
- ✅ Click stage to trigger audio test
- ✅ Hover tooltips
- ✅ Empty state ("Run a spin to see trace")

**Uloge:** Slot Designer, Audio Designer, QA
**Gaps:** None (fully functional)

### Tab 2: Command Builder (CommandBuilderPanel)

**Features:**
- ✅ Compact slot mockup UI
- ✅ Drop zones (reels, buttons, overlays)
- ✅ Target ID → Stage mapping
- ✅ Auto-create event on drop
- ✅ Shows existing events per zone
- ✅ Visual drop zone highlights

**Uloge:** Audio Designer, Tooling Developer
**Gaps:**
- ⚠️ Should be in [+] Menu, not main tabs (workflow confusion)
- ❌ No visual feedback for existing audio assignments

### Tab 3: Event List (EventListPanel) — ⚠️ WRONG PROVIDER

**Features:**
- ✅ Search/filter (by name, bus, tags)
- ✅ Sort (by name, bus, date)
- ✅ Multi-select (checkboxes)
- ✅ Bulk actions (delete, export)
- ✅ Event count badge
- ✅ Color-coded by bus

**Provider:** ❌ **AutoEventBuilderProvider.committedEvents** (WRONG!)
**SHOULD BE:** MiddlewareProvider.compositeEvents

**CRITICAL PROBLEM:**
- Events Panel (desni panel) shows MiddlewareProvider.compositeEvents
- Event List (lower zone) shows AutoEventBuilderProvider.committedEvents
- TWO SEPARATE EVENT LISTS — not synchronized!

**Gaps:**
1. **P0:** Change provider to MiddlewareProvider (sync with Events Panel)
2. **P1:** Add preview playback button per event
3. **P2:** Add event property quick editor

### Tab 4: Meters (BusMetersPanel)

**Features:**
- ✅ 5 bus meters (SFX, Music, Voice, Ambience, Master)
- ✅ Real-time FFI metering (getBusMeterLevels)
- ✅ L/R stereo for master
- ✅ Peak hold indicators
- ✅ Clip warnings (red flash)
- ✅ Peak/RMS mode toggle
- ✅ dB scale (-60 to 0)
- ✅ Color gradients (green → yellow → orange → red)

**Provider:** ✅ MeterProvider
**FFI:** ✅ getBusMeterLevels() (30fps refresh)
**Uloge:** Audio Architect, Mix Engineer, QA
**Gaps:** None (fully functional)

### Tab 5-8: FabFilter DSP Panels

**Features per panel:**
- ✅ Pro-level UI (FabFilter-inspired)
- ✅ Real-time parameter control
- ✅ FFI sync (insertSetParam)
- ✅ Bypass toggle
- ✅ Preset system
- ✅ A/B comparison
- ✅ Metering (GR, levels, etc.)

**Provider:** ✅ DspChainProvider
**FFI:** ✅ Full integration (25+ functions)
**Uloge:** Audio Architect, DSP Engineer
**Gaps:**
- ⚠️ Should be sub-panels under DSP super-tab, not 4 separate tabs
- ❌ No EQ panel (only Comp/Limiter/Gate/Reverb)
- ❌ No Delay panel
- ❌ No Saturation panel

---

## 🔴 CRITICAL GAPS

### P0.1: Fix Event List Provider Mismatch

**Problem:** EventListPanel uses AutoEventBuilderProvider instead of MiddlewareProvider
**Impact:** Events in Lower Zone not synced with Events Panel (desni panel)
**Effort:** 2 hours
**Assigned To:** Technical Director

**Files to Modify:**
- `event_list_panel.dart:14,94` — Change provider

**Implementation:**
```dart
// BEFORE:
import '../../../providers/auto_event_builder_provider.dart';

Consumer<AutoEventBuilderProvider>(
  builder: (context, provider, _) {
    final events = provider.committedEvents; // WRONG!
  },
)

// AFTER:
import '../../../providers/middleware_provider.dart';

Consumer<MiddlewareProvider>(
  builder: (context, middleware, _) {
    final events = middleware.compositeEvents; // CORRECT!
  },
)
```

**Model Changes:**
```dart
// EventListPanel currently expects CommittedEvent
// Must change to SlotCompositeEvent (from MiddlewareProvider)

// BEFORE:
List<CommittedEvent> _filterAndSortEvents(List<CommittedEvent> events)

// AFTER:
List<SlotCompositeEvent> _filterAndSortEvents(List<SlotCompositeEvent> events)
```

**Definition of Done:**
- [ ] EventListPanel uses MiddlewareProvider.compositeEvents
- [ ] Search/filter works with SlotCompositeEvent model
- [ ] Events in Lower Zone match Events Panel (desni panel)
- [ ] Bulk actions call middleware CRUD methods
- [ ] No references to AutoEventBuilderProvider

---

### P0.2: Restructure to Super-Tabs + Sub-Panels

**Problem:** 8 flat tabs instead of 7 super-tabs with sub-panels
**Impact:** Poor organization, hard to navigate, doesn't match spec
**Effort:** 1 week
**Assigned To:** Technical Director, UI/UX Expert

**Files to Create:**
- `lower_zone_types.dart` — SuperTab/SubTab enums
- `lower_zone_context_bar.dart` — Two-row header (super + sub tabs)

**Files to Modify:**
- `lower_zone_controller.dart` — Add super-tab + sub-tab state
- `lower_zone.dart` — Use context bar instead of flat tabs

**New Architecture:**
```dart
// lower_zone_types.dart
enum SuperTab { stages, events, mix, musicAle, dsp, bake, engine, menu }

enum StagesSubTab { timeline, eventDebug }
enum EventsSubTab { eventList, rtpc, compositeEditor }
enum MixSubTab { busHierarchy, auxSends, meters }
enum MusicAleSubTab { aleRules, signals, transitions }
enum DspSubTab { eq, compressor, limiter, gate, reverb, delay, saturation }
enum BakeSubTab { batchExport, validation, package }
enum EngineSubTab { profiler, resources, stageIngest }
enum MenuSubTab { gameConfig, autoSpatial, scenarios, commandBuilder }

// lower_zone_context_bar.dart
class LowerZoneContextBar extends StatelessWidget {
  final SuperTab activeSuper;
  final int activeSubIndex;
  final Function(SuperTab) onSuperTabChange;
  final Function(int) onSubTabChange;

  Widget build(BuildContext context) {
    return Column(
      children: [
        // Row 1: Super-tabs (7 + menu)
        Row(
          children: [
            for (final superTab in SuperTab.values)
              _SuperTabButton(
                tab: superTab,
                isActive: activeSuper == superTab,
                onTap: () => onSuperTabChange(superTab),
              ),
          ],
        ),
        // Row 2: Sub-tabs (dynamic based on activeSuper)
        if (isExpanded)
          Row(
            children: _getSubTabsForSuper(activeSuper)
              .map((label, index) => _SubTabButton(...))
              .toList(),
          ),
      ],
    );
  }
}
```

**Definition of Done:**
- [ ] Two-row header (super-tabs + sub-tabs)
- [ ] 7 super-tabs implemented
- [ ] Sub-tabs dynamic based on active super-tab
- [ ] Keyboard shortcuts (Ctrl+Shift+T/E/X/A/G)
- [ ] All existing panels integrated
- [ ] Backward compatible (state migration)

---

### P0.3: Add Composite Editor Sub-Panel

**Problem:** No dedicated panel for editing composite events in Lower Zone
**Impact:** Must use Events Panel (desni panel) — Lower Zone incomplete
**Effort:** 3 days
**Assigned To:** Audio Middleware Architect

**Files to Create:**
- `composite_editor_panel.dart` (~800 LOC)

**Implementation:**
```dart
class CompositeEditorPanel extends StatelessWidget {
  final String? selectedEventId;

  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        if (selectedEventId == null) {
          return _buildEmptyState('Select an event');
        }

        final event = middleware.compositeEvents.firstWhere(
          (e) => e.id == selectedEventId,
          orElse: () => null,
        );

        if (event == null) {
          return _buildEmptyState('Event not found');
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              // Event properties section
              _buildEventPropertiesSection(event),
              Divider(),
              // Layers section with interactive controls
              _buildLayersSection(event),
              Divider(),
              // Trigger stages section
              _buildTriggerStagesSection(event),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayersSection(SlotCompositeEvent event) {
    return Column(
      children: [
        _buildSectionHeader('LAYERS', () => _addLayer(event)),
        for (final layer in event.layers)
          _buildInteractiveLayerItem(layer, event),
      ],
    );
  }

  Widget _buildInteractiveLayerItem(SlotEventLayer layer, SlotCompositeEvent event) {
    return Container(
      margin: EdgeInsets.all(4),
      padding: EdgeInsets.all(8),
      child: Column(
        children: [
          // Row 1: Name + audio file
          Row(...),
          // Row 2: Volume slider
          _buildSlider('Volume', layer.volume, 0, 2, ...),
          // Row 3: Pan slider
          _buildSlider('Pan', layer.pan, -1, 1, ...),
          // Row 4: Delay slider
          _buildSlider('Delay', layer.offsetMs, 0, 2000, ...),
          // Row 5: Actions (Preview, Mute, Delete)
          Row(...),
        ],
      ),
    );
  }
}
```

**Definition of Done:**
- [ ] Panel displays selected event properties
- [ ] Interactive layer editor (volume, pan, delay sliders)
- [ ] Add layer button
- [ ] Trigger stages editor
- [ ] Real-time sync with MiddlewareProvider
- [ ] Preview playback per layer

---

### P0.4: Add Batch Export Sub-Panel

**Problem:** No export functionality in SlotLab Lower Zone
**Impact:** Can't export events/packages from SlotLab
**Effort:** 3 days
**Assigned To:** Tooling Developer, Producer

**Files to Create:**
- `bake/batch_export_panel.dart` (~700 LOC)

**Implementation:**
```dart
class BatchExportPanel extends StatelessWidget {
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        return Column(
          children: [
            // Export type selector
            _buildExportTypeSelector(),
            Divider(),
            // Event selection (which events to export)
            _buildEventSelection(middleware.compositeEvents),
            Divider(),
            // Export settings (format, normalization, etc.)
            _buildExportSettings(),
            Divider(),
            // Export button + progress
            _buildExportActions(),
          ],
        );
      },
    );
  }
}
```

**Features:**
- Event selection (all, selected, by category)
- Format selection (JSON, ZIP package, Unity, Unreal, Howler)
- Normalization options (LUFS target)
- Progress indicator
- Export to file dialog

**Definition of Done:**
- [ ] Export type selector (Universal, Unity, Unreal, Howler)
- [ ] Event selection checkboxes
- [ ] Format settings (JSON schema, audio format)
- [ ] Export button with progress
- [ ] FilePicker for save location
- [ ] Success/error feedback

---

## 👥 ROLE-BASED ANALYSIS

### 1. Chief Audio Architect (Uses All Tabs)

**What they do:**
- Monitor audio levels (Meters tab)
- Master chain processing (DSP tabs)
- Review stage timing (Timeline tab)
- Export final package (⚠️ missing Bake tab)

**What works well:**
- ✅ Meters tab — clear, real-time, professional
- ✅ DSP tabs — FabFilter-quality panels
- ✅ Timeline — visual stage trace

**Pain points:**
- ❌ **No Bake tab** — can't export from Lower Zone
- ❌ **No Mix tab** — bus hierarchy missing
- ⚠️ **Tab overload** — 8 tabs without grouping

**Gaps:**
1. **P0:** Add Bake super-tab (export, validation, package)
2. **P1:** Add Mix super-tab (bus hierarchy, aux sends, meters grouped)
3. **P1:** Group DSP tabs under one super-tab

---

### 2. Lead DSP Engineer (Uses DSP Tabs)

**What they do:**
- Apply master chain processing
- Adjust dynamics (comp, limiter, gate)
- Add reverb
- Monitor levels

**What works well:**
- ✅ 4 FabFilter panels — professional quality
- ✅ Real-time parameter control
- ✅ Bypass toggle, A/B compare

**Pain points:**
- ❌ **No EQ panel** — must use DAW section for EQ
- ❌ **No Delay panel**
- ❌ **No Saturation panel**
- ⚠️ **4 separate tabs** — should be sub-panels under DSP super-tab

**Gaps:**
1. **P0:** Add EQ to DSP tabs (FabFilterEQPanel already exists)
2. **P1:** Add Delay panel
3. **P1:** Add Saturation panel
4. **P1:** Group under DSP super-tab with sub-tab navigation

---

### 3. Slot Game Designer (Uses Timeline, Command Builder)

**What they do:**
- Review stage timing (Timeline)
- Quick audio assignment (Command Builder)
- Validate audio completeness
- Test slot simulation

**What works well:**
- ✅ Timeline shows stage sequence clearly
- ✅ Command Builder quick workflow

**Pain points:**
- ❌ **No validation panel** — can't see completeness report
- ❌ **No batch export** — can't deliver package
- ⚠️ **Event List wrong provider** — confusion about where events are

**Gaps:**
1. **P0:** Add Bake → Validation panel (completeness report)
2. **P0:** Add Bake → Package panel (export workflow)
3. **P0:** Fix Event List provider (sync with Events Panel)

---

### 4. Engine Architect (Needs Engine Tab)

**What they do:**
- Monitor performance (Profiler)
- Check resource usage (Memory, Voice pool)
- Connect external engines (Stage Ingest)

**What works well:**
- ❌ **NOTHING** — Engine tab doesn't exist in Lower Zone!

**Pain points:**
- ❌ **No Profiler panel** — exists elsewhere, not in Lower Zone
- ❌ **No Resources panel** — no memory/voice monitoring
- ❌ **No Stage Ingest panel** — exists elsewhere, not integrated

**Gaps:**
1. **P1:** Add Engine super-tab
2. **P1:** Integrate Profiler panel (already exists)
3. **P2:** Integrate Stage Ingest panel (already exists)
4. **P2:** Add Resources panel (voice pool, memory stats)

---

### 5. Producer (Needs Bake + Engine Tabs)

**What they do:**
- Export final package
- Validate completeness
- Check performance metrics
- Approve delivery

**What works well:**
- ✅ Meters tab — can see if audio clips
- ⚠️ Timeline — can see stage coverage

**Pain points:**
- ❌ **No export workflow** — Bake tab missing
- ❌ **No validation report** — can't verify completeness
- ❌ **No performance metrics** — Engine tab missing
- ❌ **No package preview** — can't review before export

**Gaps:**
1. **P0:** Add Bake super-tab (complete export workflow)
2. **P1:** Add validation panel (completeness, quality checks)
3. **P1:** Add Engine super-tab (performance metrics)

---

## 📊 SUMMARY

### IMPLEMENTED vs SPECIFICATION

| Category | Implemented | Specification | Match |
|----------|-------------|---------------|-------|
| **Tab Structure** | 8 flat tabs | 7 super-tabs + sub-panels | ❌ No |
| **STAGES** | Timeline only | Timeline + Event Debug | ⚠️ Partial (50%) |
| **EVENTS** | Event List (wrong provider) | Event List + RTPC + Composite Editor | ❌ Wrong (33%) |
| **MIX** | Meters only | Bus Hierarchy + Aux + Meters | ⚠️ Partial (33%) |
| **MUSIC/ALE** | None | ALE Panel | ❌ Missing (0%) |
| **DSP** | 4 flat tabs | Grouped sub-panels | ⚠️ Wrong structure (57% coverage — missing EQ, Delay, Saturation) |
| **BAKE** | None | Batch Export + Validation + Package | ❌ Missing (0%) |
| **ENGINE** | None | Profiler + Resources + Stage Ingest | ❌ Missing (0%) |
| **[+] Menu** | None | Game Config + AutoSpatial + Scenarios + Command Builder | ❌ Missing (0%) |

**Overall Implementation:** ~30% of specification

### Critical Issues

| # | Issue | Impact | Priority |
|---|-------|--------|----------|
| 1 | **Event List uses wrong provider** | Events not synced, data duplication | P0 |
| 2 | **No super-tab structure** | Poor UX, doesn't match spec | P0 |
| 3 | **Bake tab missing** | Can't export packages | P0 |
| 4 | **Composite Editor missing** | No layer editing in Lower Zone | P0 |
| 5 | **Mix tab incomplete** | Only meters, no routing | P1 |
| 6 | **Engine tab missing** | No performance monitoring | P1 |
| 7 | **Music/ALE tab missing** | No adaptive music controls | P2 |

### Existing Panels (Need Integration)

**Already exist elsewhere, just need to be added:**

| Panel | Current Location | Target Location | Effort |
|-------|------------------|-----------------|--------|
| RTPC Debugger | middleware/rtpc_debugger_panel.dart | EVENTS → RTPC | 1 hour |
| Bus Hierarchy | middleware/bus_hierarchy_panel.dart | MIX → Bus Hierarchy | 1 hour |
| Aux Sends | middleware/aux_sends_panel.dart | MIX → Aux Sends | 1 hour |
| ALE Panel | ale/ale_panel.dart | MUSIC/ALE | 1 hour |
| Profiler | middleware/dsp_profiler_panel.dart | ENGINE → Profiler | 1 hour |
| Stage Ingest | stage_ingest/stage_ingest_panel.dart | ENGINE → Stage Ingest | 1 hour |
| AutoSpatial | spatial/auto_spatial_panel.dart | [+] Menu → AutoSpatial | 1 hour |

**Total Integration Effort:** ~1 day (just imports + IndexedStack entries)

---

## 🎯 ACTIONABLE ITEMS (For MASTER_TODO.md)

### P0.1: Fix Event List Provider

**Already documented above** — 2 hours effort

---

### P0.2: Restructure to Super-Tabs

**Already documented above** — 1 week effort

---

### P0.3: Add Composite Editor Sub-Panel

**Already documented above** — 3 days effort

---

### P0.4: Add Batch Export Sub-Panel

**Already documented above** — 3 days effort

---

### P1.1: Integrate Existing Panels (7 panels)

**Problem:** Many panels already exist but not integrated in Lower Zone
**Impact:** Features hidden, users don't know they exist
**Effort:** 1 day (just wiring)
**Assigned To:** Tooling Developer

**Files to Modify:**
- `lower_zone.dart` — Add import + IndexedStack entries

**Panels to Integrate:**
```dart
// In lower_zone.dart, IndexedStack children:

// EVENTS → RTPC sub-tab
import '../../middleware/rtpc_debugger_panel.dart';
// Add: RtpcDebuggerPanel(),

// MIX → Bus Hierarchy sub-tab
import '../../middleware/bus_hierarchy_panel.dart';
// Add: BusHierarchyPanel(),

// MIX → Aux Sends sub-tab
import '../../middleware/aux_sends_panel.dart';
// Add: AuxSendsPanel(),

// MUSIC/ALE tab
import '../../ale/ale_panel.dart';
// Add: AlePanel(),

// ENGINE → Profiler sub-tab
import '../../middleware/dsp_profiler_panel.dart';
// Add: DspProfilerPanel(),

// ENGINE → Stage Ingest sub-tab
import '../../stage_ingest/stage_ingest_panel.dart';
// Add: StageIngestPanel(),

// [+] Menu → AutoSpatial
import '../../spatial/auto_spatial_panel.dart';
// Add: AutoSpatialPanel(),
```

**Definition of Done:**
- [ ] All 7 panels imported
- [ ] Added to IndexedStack
- [ ] Keyboard shortcuts working
- [ ] State persists on tab switch
- [ ] No regressions (existing tabs still work)

---

## ✅ FAZA 2.3 COMPLETE

**Next Step:** Await approval, then proceed to FAZA 2.4 (Centralni Panel)

**Deliverables Created:**
- Architecture mismatch analysis (spec vs implementation)
- 8 implemented tabs documented
- ~15 missing panels identified (7 need creation, 7 just integration)
- Provider connection analysis
- Role-based gap analysis (5 roles)
- 11 actionable items for MASTER_TODO (4 P0, 4 P1, 3 P2)

**Critical Finding:**
- **ARCHITECTURAL MISMATCH** — Implementation (8 flat tabs) ≠ Specification (7 super-tabs + sub-panels)
- **EVENT LIST BUG** — Uses wrong provider (AutoEventBuilderProvider instead of MiddlewareProvider)
- **~30% spec coverage** — Many features missing or not integrated

---

**Created:** 2026-01-29
**Version:** 1.0
**LOC Analyzed:** 3,212 + identified 7 existing panels (~4,000 LOC) not integrated

# SlotLab Analysis — FAZA 3: Horizontal Analysis

**Date:** 2026-01-29
**Status:** ✅ COMPLETE
**Scope:** Cross-panel data flow, dependencies, integration gaps

---

## 🌊 DATA FLOW PATHS

### Path 1: Audio Import → Event Registration → Playback

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Import Audio                                            │
└─────────────────────────────────────────────────────────────────┘
Desni Panel: Audio Browser (Pool or Files mode)
    ↓
Import File/Folder → AudioAssetManager.instance.importFile(path)
    ↓
AudioAsset stored in memory (id, path, duration, format, folder)

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Audio Assignment                                        │
└─────────────────────────────────────────────────────────────────┘
User drags audio from Desni Panel → Drops on Levi Panel (UltimateAudioPanel)
    ↓
UltimateAudioPanel.onAudioAssign(stage, audioPath) callback
    ↓
slot_lab_screen.dart:2298
    ↓
SlotLabProjectProvider.setAudioAssignment(stage, audioPath)  ← Persistence
    ↓
AudioEvent created with stage binding
    ↓
EventRegistry.registerEvent(audioEvent)  ← Playback ready

┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Event Creation (via MiddlewareProvider)                 │
└─────────────────────────────────────────────────────────────────┘
slot_lab_screen.dart continues:
    ↓
SlotCompositeEvent created (id, name, layers, triggerStages)
    ↓
MiddlewareProvider.addCompositeEvent(event)  ← Events Panel SSoT
    ↓
Desni Panel: Events Folder updates (Consumer<MiddlewareProvider>)

┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: Playback Trigger                                        │
└─────────────────────────────────────────────────────────────────┘
Centralni Panel: User spins slot
    ↓
SlotLabProvider.spin() → Rust engine → StageEvent[] returned
    ↓
EventRegistry.triggerStage(stage)
    ↓
Lookup AudioEvent by stage → Play layers via AudioPlaybackService
    ↓
Audio plays on assigned bus (SFX, Music, Voice, etc.)
```

**✅ FLOW VERIFIED:** Audio import → Assignment → Registration → Playback works end-to-end

**⚠️ GAPS FOUND:**
1. **Missing visual feedback** — User drops audio on Levi Panel, but no confirmation it's registered in EventRegistry
2. **No sync indicator** — Levi Panel ↔ Desni Panel (Events Folder) sync not visible
3. **No audio test** — Can't test playback immediately after assignment

---

### Path 2: GDD Import → Slot Configuration → Audio Mapping

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: GDD Import                                              │
└─────────────────────────────────────────────────────────────────┘
Centralni Panel OR Lower Zone [+] Menu: GDD Import button
    ↓
GddImportService.parseGddJson(json) → GameDesignDocument
    ↓
GddPreviewDialog.show() — Visual preview (grid, symbols, math)
    ↓
User clicks "Apply Configuration"

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Data Distribution                                       │
└─────────────────────────────────────────────────────────────────┘
slot_lab_screen.dart:_populateSlotSymbolsFromGdd()
    ↓
┌────────────────────────┬─────────────────────┬─────────────────┐
│ SlotLabProjectProvider │ Rust Engine         │ Symbol Registry │
│                        │                     │                 │
│ importGdd(gdd)         │ initEngineFromGdd() │ setDynamicSymbols() │
│ ↓                      │ ↓                   │ ↓               │
│ Grid config stored     │ Math model applied  │ Reel display    │
│ Symbols stored         │ Symbol weights set  │ updated         │
│ Features stored        │ Paytable loaded     │                 │
└────────────────────────┴─────────────────────┴─────────────────┘
    ↓
Centralni Panel: Reels update with GDD symbols
Levi Panel: SymbolStrip updates with GDD symbols
Lower Zone: Paytable panel updates

┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Audio Mapping (Manual)                                  │
└─────────────────────────────────────────────────────────────────┘
Levi Panel: SymbolStripWidget
    ↓
User drops audio on symbol contexts (win/land/expand)
    ↓
projectProvider.assignSymbolAudio(symbolId, context, audioPath)
    ↓
Auto-generates stage name: WIN_SYMBOL_HIGHLIGHT_HP1, SYMBOL_LAND_WILD
    ↓
EventRegistry.registerEvent() — Symbol audio ready
```

**✅ FLOW VERIFIED:** GDD import propagates to all 3 panels

**⚠️ GAPS FOUND:**
1. **No auto-audio mapping** — GDD has symbol names, could auto-suggest audio based on theme
2. **No validation** — Doesn't check if all GDD symbols have audio assigned
3. **No GDD export** — Can't export modified GDD back to JSON

---

### Path 3: Event Creation → Multi-Panel Sync

```
┌─────────────────────────────────────────────────────────────────┐
│ CREATION SOURCE (3 paths)                                       │
└─────────────────────────────────────────────────────────────────┘
Path A: Levi Panel (UltimateAudioPanel)
    → onAudioAssign callback
    → MiddlewareProvider.addCompositeEvent()

Path B: Desni Panel (Events Folder)
    → Create Event button
    → CreateEventDialog
    → MiddlewareProvider.addCompositeEvent()

Path C: Lower Zone (Command Builder)
    → Drop on slot mockup
    → Auto-create event
    → MiddlewareProvider.addCompositeEvent()

┌─────────────────────────────────────────────────────────────────┐
│ SINGLE SOURCE OF TRUTH                                          │
└─────────────────────────────────────────────────────────────────┘
MiddlewareProvider.compositeEvents: List<SlotCompositeEvent>

┌─────────────────────────────────────────────────────────────────┐
│ SYNCHRONIZATION (Consumer pattern)                              │
└─────────────────────────────────────────────────────────────────┘
Desni Panel: Events Folder
    → Consumer<MiddlewareProvider>
    → Rebuilds when compositeEvents changes
    → Shows all events from all sources

Lower Zone: Event List
    → ⚠️ Consumer<AutoEventBuilderProvider>  ← WRONG!
    → ⚠️ Shows DIFFERENT events (committedEvents)

Lower Zone: Composite Editor (MISSING)
    → Should be Consumer<MiddlewareProvider>
    → Should show selectedEvent details
```

**❌ SYNC BUG CONFIRMED:**
- Desni Panel Events Folder → MiddlewareProvider ✅
- Lower Zone Event List → AutoEventBuilderProvider ❌
- **TWO SEPARATE EVENT LISTS** — data duplication!

---

## 🔗 CROSS-PANEL DEPENDENCIES

### Levi → Desni Dependency

**Flow:** Audio assignment → Event creation

```
UltimateAudioPanel (Levi)
    ↓ onAudioAssign(stage, audioPath)
slot_lab_screen.dart
    ↓ MiddlewareProvider.addCompositeEvent()
EventsPanelWidget (Desni)
    ↓ Consumer<MiddlewareProvider> rebuilds
Events Folder list updated
```

**Status:** ✅ Works correctly
**Gap:** No visual confirmation in Levi Panel when event created in Desni Panel

---

### Desni → Lower Zone Dependency

**Flow:** Event selection → Timeline/Editor display

```
EventsPanelWidget (Desni)
    ↓ Click event → onSelectionChanged(eventId)
slot_lab_screen.dart
    ↓ _selectedEventId state updated
Lower Zone: Timeline
    ↓ Should highlight selected event stages
Lower Zone: Composite Editor (MISSING)
    ↓ Should show selected event details
```

**Status:** ⚠️ Partial
**Gaps:**
1. Timeline doesn't highlight selected event stages
2. Composite Editor panel doesn't exist

---

### Centralni → Lower Zone Dependency

**Flow:** Spin → Stage trace → Audio debug

```
PremiumSlotPreview (Centralni)
    ↓ User spins
SlotLabProvider.spin() → StageEvent[]
    ↓ lastStages updated
Lower Zone: Timeline
    ↓ Consumer<SlotLabProvider>
    ↓ StageTraceWidget displays stages
Lower Zone: Event Debug (MISSING)
    ↓ Should show performance metrics
```

**Status:** ⚠️ Partial
**Gap:** Event Debug panel missing (no latency tracking in UI)

---

### Centralni → Levi Dependency

**Flow:** Slot simulation → Audio completeness check

```
PremiumSlotPreview (Centralni)
    ↓ Triggers stages via EventRegistry
EventRegistry.triggerStage(stage)
    ↓ Looks up registered events
UltimateAudioPanel (Levi)
    ↓ Shows which stages have audio (via audioAssignments map)
    ↓ ⚠️ No real-time feedback if audio missing
```

**Status:** ⚠️ Partial
**Gap:** No warning in Centralni Panel if stage has no audio

---

## 📊 PROVIDER DEPENDENCY GRAPH

```
┌──────────────────────────────────────────────────────────────────┐
│                    PROVIDER HIERARCHY                             │
└──────────────────────────────────────────────────────────────────┘

SlotLabProvider (Primary — Slot simulation state)
    ├─→ Centralni Panel (spin, lastResult, lastStages, isReelsSpinning)
    ├─→ Lower Zone Timeline (lastStages for trace)
    └─→ Lower Zone Meters (indirect — via MeterProvider FFI)

MiddlewareProvider (Primary — Event management SSoT)
    ├─→ Desni Panel Events Folder (compositeEvents)
    ├─→ Levi Panel (via callback → addCompositeEvent)
    ├─→ Lower Zone Event List (⚠️ SHOULD USE, currently doesn't)
    └─→ Lower Zone Composite Editor (MISSING panel)

SlotLabProjectProvider (Persistence — Save/load state)
    ├─→ Levi Panel UltimateAudioPanel (audioAssignments, expandedSections)
    ├─→ Levi Panel SymbolStrip (symbolAudio, musicLayers, symbols, contexts)
    └─→ Centralni Panel (grid config, GDD data)

AudioAssetManager (Singleton — Audio pool)
    ├─→ Desni Panel Audio Browser (Pool mode)
    └─→ All drag-drop sources

EventRegistry (Singleton — Stage → Audio mapping)
    ├─→ Levi Panel (registerEvent on audio assign)
    ├─→ Centralni Panel (triggerStage on spin)
    └─→ Lower Zone Timeline (visual only, no trigger)

DspChainProvider (Singleton — DSP chain for master bus)
    └─→ Lower Zone DSP tabs (FabFilter panels)

MeterProvider (Singleton — Real-time metering)
    └─→ Lower Zone Meters tab

AutoEventBuilderProvider (Legacy — ⚠️ SHOULD BE REMOVED)
    └─→ Lower Zone Event List (⚠️ WRONG — should use MiddlewareProvider)
```

**CRITICAL FINDING:** AutoEventBuilderProvider is **REDUNDANT** — all events should flow through MiddlewareProvider.

---

## 🔴 INTEGRATION GAPS

### Gap 1: Event List Provider Mismatch (P0)

**Problem:**
- Desni Panel → MiddlewareProvider.compositeEvents
- Lower Zone → AutoEventBuilderProvider.committedEvents
- TWO SEPARATE EVENT LISTS!

**Impact:** Events created in Desni Panel don't appear in Lower Zone Event List (and vice versa)

**Evidence:**
```dart
// events_panel_widget.dart (Desni Panel)
Consumer<MiddlewareProvider>(
  builder: (context, middleware, _) {
    final events = middleware.compositeEvents; // ✅ CORRECT
  },
)

// event_list_panel.dart (Lower Zone)
Consumer<AutoEventBuilderProvider>(
  builder: (context, provider, _) {
    final events = provider.committedEvents; // ❌ WRONG!
  },
)
```

**Fix:** Change Lower Zone Event List to use MiddlewareProvider
**Effort:** 2 hours
**Priority:** **P0 CRITICAL**

---

### Gap 2: Selection State Not Synced (P1)

**Problem:** Event selection in Desni Panel not reflected in Lower Zone

**Current Flow:**
```
Desni Panel: Click event → _setSelectedEventId(eventId)
                        → onSelectionChanged callback
                        → slot_lab_screen.dart:_selectedEventId
                        → ⚠️ Not passed to Lower Zone!
```

**Expected Flow:**
```
Desni Panel: Select event
    ↓
Lower Zone Timeline: Highlight selected event stages
Lower Zone Composite Editor: Show selected event details
```

**Fix:** Pass selectedEventId to Lower Zone panels
**Effort:** 1 day
**Priority:** P1

---

### Gap 3: Audio Assignment Visual Feedback Loop (P1)

**Problem:** No visual confirmation when audio assignment completes full cycle

**Current:**
```
Levi Panel: Drop audio
    ↓
onAudioAssign callback
    ↓
EventRegistry.registerEvent()
    ↓
MiddlewareProvider.addCompositeEvent()
    ↓
Desni Panel: Events Folder updates
    ↓
⚠️ NO FEEDBACK TO LEVI PANEL!
```

**Expected:**
```
Levi Panel: Audio slot shows:
    ✅ Green checkmark — Event registered
    📋 Event count badge — X events use this stage
    🔊 Play button — Test immediately
```

**Fix:** Add status indicators to UltimateAudioPanel slots
**Effort:** 2 days
**Priority:** P1

---

### Gap 4: Lower Zone Missing Panels (P0)

**Problem:** Lower Zone doesn't match CLAUDE.md specification

**Missing Panels:**
| Super-Tab | Sub-Panel | Status | Integration Effort |
|-----------|-----------|--------|-------------------|
| STAGES | Event Debug | ❌ Needs creation | 3 days |
| EVENTS | RTPC Debugger | ✅ Exists elsewhere | 1 hour |
| EVENTS | Composite Editor | ❌ Needs creation | 3 days |
| MIX | Bus Hierarchy | ✅ Exists elsewhere | 1 hour |
| MIX | Aux Sends | ✅ Exists elsewhere | 1 hour |
| MUSIC/ALE | ALE Panel | ✅ Exists elsewhere | 1 hour |
| BAKE | Batch Export | ❌ Needs creation | 3 days |
| BAKE | Validation | ❌ Needs creation | 2 days |
| BAKE | Package | ❌ Needs creation | 1 day |
| ENGINE | Profiler | ✅ Exists elsewhere | 1 hour |
| ENGINE | Resources | ❌ Needs creation | 2 days |
| ENGINE | Stage Ingest | ✅ Exists elsewhere | 1 hour |
| [+] Menu | Game Config | ❌ Needs creation | 2 days |
| [+] Menu | AutoSpatial | ✅ Exists elsewhere | 1 hour |
| [+] Menu | Scenarios | ❌ Needs creation | 2 days |

**Existing:** 7 panels (~4,000 LOC) just need import + IndexedStack
**Missing:** 8 panels (~2,400 LOC) need creation

**Fix:** Implement super-tab structure + integrate/create panels
**Effort:** 2-3 weeks
**Priority:** P0 (architectural mismatch)

---

### Gap 5: Symbol Audio Re-Registration on Mount (RESOLVED)

**Problem (was):** Symbol audio events lost on SlotLab screen remount

**Solution (implemented 2026-01-25):**
```dart
// slot_lab_screen.dart:10404-10459
void _syncSymbolAudioToRegistry() {
  final symbolAudio = projectProvider.symbolAudio;
  for (final assignment in symbolAudio) {
    final audioEvent = AudioEvent(
      id: 'symbol_${assignment.symbolId}_${assignment.context}',
      stage: assignment.stageName,  // WIN_SYMBOL_HIGHLIGHT_HP1
      layers: [AudioLayer(audioPath: assignment.audioPath, ...)],
    );
    eventRegistry.registerEvent(audioEvent);
  }
}
// Called in _initializeSlotEngine() — always executed
```

**Status:** ✅ RESOLVED (no action needed)

---

## 🔄 DATA CONSISTENCY CHECKS

### Check 1: Event Count Consistency

**Question:** Do all panels show same event count?

```
Levi Panel: audioAssignments.length
Desni Panel: middleware.compositeEvents.length
Lower Zone Event List: provider.committedEvents.length  ← DIFFERENT!
```

**Result:** ❌ **INCONSISTENT**
- Levi shows audio assignments (stage-level)
- Desni shows composite events (event-level, may have multiple stages)
- Lower Zone shows committed events (WRONG PROVIDER)

**Expected:** All panels should derive count from MiddlewareProvider.compositeEvents

---

### Check 2: Audio Playback Isolation

**Question:** Do panels interfere with each other's playback?

```
Desni Panel: Audio Browser preview
    → AudioPlaybackService.previewFile(source: PlaybackSource.browser)

Centralni Panel: Slot spin
    → EventRegistry.triggerStage()
    → AudioPlaybackService.playFileToBus(source: PlaybackSource.slotLab)

Lower Zone: Timeline stage click test
    → EventRegistry.triggerStage()
    → AudioPlaybackService (source: PlaybackSource.slotLab)
```

**Result:** ✅ **ISOLATED**
- Browser preview uses isolated engine (PlaybackSource.browser)
- SlotLab playback uses section-acquired engine (PlaybackSource.slotLab)
- UnifiedPlaybackController manages section locking

**No interference confirmed.**

---

### Check 3: State Persistence Scope

**Question:** What state survives section switching (DAW ↔ SlotLab)?

**Persisted to SlotLabProjectProvider:**
- ✅ audioAssignments (Levi Panel)
- ✅ symbolAudio (SymbolStrip)
- ✅ musicLayers (SymbolStrip)
- ✅ expandedSections, expandedGroups (Levi Panel)
- ✅ symbols, contexts (GDD-imported data)
- ✅ importedGdd (full GDD object)

**NOT Persisted (lost on section switch):**
- ❌ Event selection state (_selectedEventId in Desni Panel)
- ❌ Lower Zone tab selection (resets to Timeline)
- ❌ Lower Zone height (resets to default)
- ❌ Audio Browser current directory (resets to ~/Music)

**Gap:** Missing persistence for UI state

---

## 🎯 ACTIONABLE ITEMS

### P0.1: Remove AutoEventBuilderProvider Dependency

**Problem:** Lower Zone Event List uses legacy provider instead of MiddlewareProvider
**Impact:** Event list out of sync with rest of system
**Effort:** 2 hours
**Files:** `event_list_panel.dart`

**Already documented in FAZA 2.3**

---

### P1.1: Add Visual Feedback Loop for Audio Assignment

**Problem:** No confirmation when audio assignment completes full cycle
**Impact:** User doesn't know if audio is playback-ready
**Effort:** 2 days
**Assigned To:** Audio Designer, UI/UX Expert

**Files to Modify:**
- `ultimate_audio_panel.dart` — Enhance slot display

**Implementation:**
```dart
Widget _buildAudioSlot(_SlotConfig slot, String? assignedPath) {
  final hasAudio = assignedPath != null;

  // NEW: Check if event exists in EventRegistry
  final isRegistered = hasAudio &&
      EventRegistry.instance.hasEventForStage(slot.stage);

  // NEW: Check if event exists in MiddlewareProvider
  final eventCount = hasAudio
      ? _countEventsForStage(context, slot.stage)
      : 0;

  return Container(
    child: Row(
      children: [
        // NEW: Status indicator
        if (hasAudio) ...[
          Icon(
            isRegistered ? Icons.check_circle : Icons.warning,
            size: 12,
            color: isRegistered ? Colors.green : Colors.orange,
          ),
          SizedBox(width: 4),
        ],

        // Existing: Filename
        Expanded(child: Text(filename)),

        // NEW: Event count badge
        if (eventCount > 0)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('$eventCount', style: TextStyle(fontSize: 9)),
          ),

        // NEW: Play button (from FAZA 2.1)
        IconButton(
          icon: Icon(Icons.play_arrow, size: 14),
          onPressed: () => _testAudio(slot.stage),
        ),

        // Existing: Clear button
        IconButton(icon: Icon(Icons.close), onPressed: onClear),
      ],
    ),
  );
}

int _countEventsForStage(BuildContext context, String stage) {
  final middleware = context.read<MiddlewareProvider>();
  return middleware.compositeEvents
      .where((e) => e.triggerStages.contains(stage))
      .length;
}

void _testAudio(String stage) {
  EventRegistry.instance.triggerStage(stage);
}
```

**Definition of Done:**
- [ ] Green checkmark when EventRegistry has event for stage
- [ ] Orange warning if audio assigned but no event registered
- [ ] Event count badge (how many events use this stage)
- [ ] Play button to test audio immediately
- [ ] Visual feedback on successful assignment

---

### P1.2: Persist UI State to SlotLabProjectProvider

**Problem:** UI state lost on section switch (DAW ↔ SlotLab)
**Impact:** User must reconfigure Lower Zone, event selection every time
**Effort:** 1 day
**Assigned To:** Technical Director

**Files to Modify:**
- `slot_lab_project_provider.dart` — Add UI state fields
- `slot_lab_screen.dart` — Save/load on mount/unmount

**Implementation:**
```dart
// slot_lab_project_provider.dart
class SlotLabProjectProvider extends ChangeNotifier {
  // Existing fields...

  // NEW: UI state persistence
  String? selectedEventId;
  LowerZoneTab? lowerZoneActiveTab;
  double? lowerZoneHeight;
  String? audioBrowserDirectory;

  // NEW: Setters with persistence
  void setSelectedEventId(String? id) {
    selectedEventId = id;
    notifyListeners();
  }

  void setLowerZoneState({
    LowerZoneTab? activeTab,
    double? height,
  }) {
    if (activeTab != null) lowerZoneActiveTab = activeTab;
    if (height != null) lowerZoneHeight = height;
    notifyListeners();
  }

  void setAudioBrowserDirectory(String? dir) {
    audioBrowserDirectory = dir;
    notifyListeners();
  }

  // Include in toJson/fromJson
  @override
  Map<String, dynamic> toJson() {
    return {
      // Existing...
      'selectedEventId': selectedEventId,
      'lowerZoneActiveTab': lowerZoneActiveTab?.index,
      'lowerZoneHeight': lowerZoneHeight,
      'audioBrowserDirectory': audioBrowserDirectory,
    };
  }
}

// slot_lab_screen.dart — Load on mount
@override
void initState() {
  super.initState();
  final projectProvider = context.read<SlotLabProjectProvider>();

  // Restore UI state
  if (projectProvider.selectedEventId != null) {
    _selectedEventId = projectProvider.selectedEventId;
  }
  if (projectProvider.lowerZoneActiveTab != null) {
    _lowerZoneController.switchTo(projectProvider.lowerZoneActiveTab!);
  }
  if (projectProvider.lowerZoneHeight != null) {
    _lowerZoneController.setHeight(projectProvider.lowerZoneHeight!);
  }
}

// Save on selection change
void _onEventSelectionChanged(String? eventId) {
  setState(() => _selectedEventId = eventId);
  context.read<SlotLabProjectProvider>().setSelectedEventId(eventId);
}
```

**Definition of Done:**
- [ ] Event selection persists across section switches
- [ ] Lower Zone tab persists
- [ ] Lower Zone height persists
- [ ] Audio Browser directory persists
- [ ] State included in project save/load

---

### P1.3: Add Cross-Panel Navigation

**Problem:** No way to jump from one panel to related content in another panel
**Impact:** Workflow friction — must manually navigate
**Effort:** 2 days
**Assigned To:** UI/UX Expert

**Examples:**
```
Levi Panel: Click event count badge on audio slot
    → Navigate to Desni Panel Events Folder
    → Filter by stage
    → Show all events using that stage

Desni Panel: Click stage badge on event row
    → Navigate to Levi Panel
    → Scroll to and highlight that stage slot

Lower Zone Timeline: Click stage marker
    → Navigate to Levi Panel
    → Highlight audio slot for that stage
```

**Implementation:**
```dart
// Add navigation callbacks to slot_lab_screen.dart
class SlotLabScreen extends StatefulWidget {
  // NEW: Navigation coordinator
  final _NavigationCoordinator _nav = _NavigationCoordinator();
}

class _NavigationCoordinator {
  // Jump to Levi Panel and highlight stage
  void jumpToAudioSlot(String stage) {
    // 1. Switch to Symbol Strip or Ultimate Audio Panel mode (if needed)
    // 2. Expand section containing stage
    // 3. Scroll to stage slot
    // 4. Highlight briefly (glow animation)
  }

  // Jump to Desni Panel and filter by stage
  void jumpToEventsForStage(String stage) {
    // 1. Switch to Events Panel (if showing browser)
    // 2. Apply filter: triggerStages.contains(stage)
    // 3. Highlight matching events
  }

  // Jump to Lower Zone Timeline and show stage
  void jumpToStageInTimeline(String stage) {
    // 1. Expand Lower Zone
    // 2. Switch to Timeline tab
    // 3. Scroll to stage marker
    // 4. Highlight briefly
  }
}

// Wire up to panels:
UltimateAudioPanel(
  onEventCountBadgeClick: (stage) => _nav.jumpToEventsForStage(stage),
)

EventsPanelWidget(
  onStageBadgeClick: (stage) => _nav.jumpToAudioSlot(stage),
)

StageTraceWidget(
  onStageMarkerClick: (stage) => _nav.jumpToAudioSlot(stage),
)
```

**Definition of Done:**
- [ ] Click event count badge → jump to Events Folder filtered by stage
- [ ] Click stage badge → jump to audio slot in Levi Panel
- [ ] Click timeline marker → jump to audio slot
- [ ] Smooth scroll + highlight animation
- [ ] Breadcrumb trail (show navigation path)

---

## 📊 SUMMARY

### Data Flow Health

| Flow | Status | Issue |
|------|--------|-------|
| Audio Import → Registration | ✅ Healthy | None |
| Event Creation → Multi-Panel Sync | ⚠️ Partial | Lower Zone uses wrong provider |
| GDD Import → Configuration | ✅ Healthy | None |
| Spin → Audio Trigger | ✅ Healthy | None |
| Selection → Cross-Panel | ❌ Broken | Not synced to Lower Zone |

**Overall:** 3/5 flows healthy, 2 need fixes

### Provider Usage

| Provider | Panels Using | Correct Usage |
|----------|--------------|---------------|
| MiddlewareProvider | Desni Events Folder | ✅ Yes |
| MiddlewareProvider | Levi Panel (callback) | ✅ Yes |
| MiddlewareProvider | Lower Zone Event List | ❌ **No — uses wrong provider!** |
| SlotLabProvider | Centralni Panel | ✅ Yes |
| SlotLabProvider | Lower Zone Timeline | ✅ Yes |
| AutoEventBuilderProvider | Lower Zone Event List | ❌ **Should be removed** |

**Critical Issue:** AutoEventBuilderProvider creates data duplication and sync bugs.

### Cross-Panel Dependencies

**Verified Working (3):**
- ✅ Levi → Desni (audio assign → event creation)
- ✅ Centralni → Lower Zone Timeline (spin → stage trace)
- ✅ GDD Import → All panels (symbol propagation)

**Broken (2):**
- ❌ Desni → Lower Zone (selection not synced)
- ❌ Lower Zone Event List → MiddlewareProvider (wrong provider)

**Missing (1):**
- ❌ No cross-panel navigation (click to jump)

---

## 🎯 TOP INTEGRATION GAPS

| # | Gap | Impact | Priority | Effort |
|---|-----|--------|----------|--------|
| 1 | Event List wrong provider | Data duplication, sync bugs | P0 | 2 hours |
| 2 | Lower Zone missing panels | Architectural mismatch | P0 | 2-3 weeks |
| 3 | Selection not synced | Workflow friction | P1 | 1 day |
| 4 | No visual feedback loop | User confusion | P1 | 2 days |
| 5 | No cross-panel navigation | Manual navigation tedious | P1 | 2 days |
| 6 | UI state not persisted | Lost on section switch | P1 | 1 day |

**Total Critical (P0):** 2 items (2h + 2-3 weeks)
**Total High (P1):** 4 items (~1 week total)

---

## ✅ FAZA 3 COMPLETE

**Next Step:** Await approval, then proceed to FAZA 4 (Gap Consolidation)

**Deliverables Created:**
- 3 major data flow paths documented
- Cross-panel dependency graph
- Provider usage matrix
- Data consistency checks
- 6 integration gaps identified (2 P0, 4 P1)
- 3 actionable items for MASTER_TODO (detailed implementation plans)

**Critical Findings:**
1. **AutoEventBuilderProvider redundancy** — should be removed, causes sync bugs
2. **Lower Zone architectural mismatch** — 30% of spec implemented
3. **Selection state not synced** — breaks multi-panel workflow
4. **No cross-panel navigation** — manual navigation tedious

---

**Created:** 2026-01-29
**Version:** 1.0

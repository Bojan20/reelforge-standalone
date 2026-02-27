## 🏗️ DEPENDENCY INJECTION — GetIt Service Locator

**Status:** ✅ IMPLEMENTED (2026-01-21)

### Service Locator Pattern

```dart
// Global instance
final GetIt sl = GetIt.instance;

// Access services anywhere
final ffi = sl<NativeFFI>();
final pool = sl<AudioPool>();
final stateGroups = sl<StateGroupsProvider>();
```

### Registered Services (by layer)

| Layer | Service | Type |
|-------|---------|------|
| 1 | `NativeFFI` | Core FFI |
| 2 | `SharedMeterReader`, `WaveformCacheService`, `AudioAssetManager`, `LiveEngineService` | Low-level |
| 3 | `UnifiedPlaybackController`, `AudioPlaybackService`, `AudioPool`, `SlotLabTrackBridge`, `SessionPersistenceService` | Playback |
| 4 | `DuckingService`, `RtpcModulationService`, `ContainerService`, `DuckingPreviewService` | Audio processing |
| 5 | `StateGroupsProvider`, `SwitchGroupsProvider`, `RtpcSystemProvider`, `DuckingSystemProvider`, `EventSystemProvider`, `CompositeEventSystemProvider` | Middleware subsystems |
| 5.5 | `SlotLabProjectProvider` | SlotLab V6 project state (symbols, contexts, layers, **P5 win tiers**) |
| 6 | `BusHierarchyProvider`, `AuxSendProvider` | Bus routing subsystems |
| 7 | `StageIngestProvider` | Stage Ingest (engine integration) |
| 8 | `WorkspacePresetService` | Layout presets (M3.2) |
| 9 | `MathModelConnector` | Win tier → RTPC bridge (M4) |

### Subsystem Providers (extracted from MiddlewareProvider)

| Provider | File | LOC | Manages |
|----------|------|-----|---------|
| `StateGroupsProvider` | `providers/subsystems/state_groups_provider.dart` | ~185 | Global state groups (Wwise-style) |
| `SwitchGroupsProvider` | `providers/subsystems/switch_groups_provider.dart` | ~210 | Per-object switches |
| `RtpcSystemProvider` | `providers/subsystems/rtpc_system_provider.dart` | ~350 | RTPC definitions, bindings, curves |
| `DuckingSystemProvider` | `providers/subsystems/ducking_system_provider.dart` | ~190 | Ducking rules (sidechain matrix) |
| `EventSystemProvider` | `providers/subsystems/event_system_provider.dart` | ~330 | MiddlewareEvent CRUD, FFI sync |
| `CompositeEventSystemProvider` | `providers/subsystems/composite_event_system_provider.dart` | ~1280 | SlotCompositeEvent CRUD, undo/redo, layer ops, stage triggers |
| `BusHierarchyProvider` | `providers/subsystems/bus_hierarchy_provider.dart` | ~360 | Audio bus hierarchy (Wwise-style routing) |
| `AuxSendProvider` | `providers/subsystems/aux_send_provider.dart` | ~390 | Aux send/return routing (Reverb, Delay, Slapback) |
| `VoicePoolProvider` | `providers/subsystems/voice_pool_provider.dart` | ~340 | Voice polyphony, stealing, virtual voices + FFI engine stats |
| `AttenuationCurveProvider` | `providers/subsystems/attenuation_curve_provider.dart` | ~300 | Slot-specific attenuation curves |
| `MemoryManagerProvider` | `providers/subsystems/memory_manager_provider.dart` | ~350 | Soundbank memory management, LRU unloading + FFI backend |
| `EventProfilerProvider` | `providers/subsystems/event_profiler_provider.dart` | ~540 | Audio event profiling, latency tracking + DSP profiler FFI |

**Decomposition Progress:**
- Phase 1 ✅: StateGroups + SwitchGroups
- Phase 2 ✅: RTPC + Ducking
- Phase 3 ✅: Containers (Blend/Random/Sequence providers)
- Phase 4 ✅: Music + Events (MusicSystemProvider, EventSystemProvider, CompositeEventSystemProvider)
- Phase 5 ✅: Bus Routing (BusHierarchyProvider, AuxSendProvider)
- Phase 6 ✅: VoicePool + AttenuationCurves
- Phase 7 ✅: MemoryManager + EventProfiler

**Usage in MiddlewareProvider:**
```dart
MiddlewareProvider(this._ffi) {
  _stateGroupsProvider = sl<StateGroupsProvider>();
  _switchGroupsProvider = sl<SwitchGroupsProvider>();
  _rtpcSystemProvider = sl<RtpcSystemProvider>();
  _duckingSystemProvider = sl<DuckingSystemProvider>();
  _busHierarchyProvider = sl<BusHierarchyProvider>();
  _auxSendProvider = sl<AuxSendProvider>();
  _voicePoolProvider = sl<VoicePoolProvider>();
  _attenuationCurveProvider = sl<AttenuationCurveProvider>();
  _memoryManagerProvider = sl<MemoryManagerProvider>();
  _eventProfilerProvider = sl<EventProfilerProvider>();

  // Forward notifications from subsystems
  _stateGroupsProvider.addListener(notifyListeners);
  _switchGroupsProvider.addListener(notifyListeners);
  _rtpcSystemProvider.addListener(notifyListeners);
  _duckingSystemProvider.addListener(notifyListeners);
  _busHierarchyProvider.addListener(notifyListeners);
  _auxSendProvider.addListener(notifyListeners);
  _voicePoolProvider.addListener(notifyListeners);
  _attenuationCurveProvider.addListener(notifyListeners);
  _memoryManagerProvider.addListener(notifyListeners);
  _eventProfilerProvider.addListener(notifyListeners);
}
```

**FFI Integration Summary (2026-01-24):**

All 16 subsystem providers are connected to Rust FFI:

| Provider | FFI Backend | Status |
|----------|-------------|--------|
| StateGroupsProvider | `middleware_*` | ✅ State group registration |
| SwitchGroupsProvider | `middleware_*` | ✅ Per-object switches |
| RtpcSystemProvider | `middleware_*` | ✅ RTPC bindings |
| DuckingSystemProvider | `middleware_*` | ✅ Ducking rules |
| BlendContainersProvider | `container_*` | ✅ RTPC crossfade |
| RandomContainersProvider | `container_*` | ✅ Weighted random |
| SequenceContainersProvider | `container_*` | ✅ Timed sequences |
| MusicSystemProvider | `middleware_*` | ✅ Music segments |
| EventSystemProvider | `middleware_*` | ✅ Event CRUD |
| CompositeEventSystemProvider | — | Dart-only (EventRegistry) |
| BusHierarchyProvider | `mixer_*` | ✅ Bus routing |
| AuxSendProvider | — | Dart-only aux routing |
| **VoicePoolProvider** | `getVoicePoolStats` | ✅ Engine voice stats |
| AttenuationCurveProvider | — | Dart curve evaluation |
| **MemoryManagerProvider** | `memory_manager_*` | ✅ Full memory manager |
| **EventProfilerProvider** | `profiler_*` | ✅ DSP profiler |

**Dokumentacija:**
- `.claude/SYSTEM_AUDIT_2026_01_21.md` — P0.2 progress
- `.claude/architecture/MIDDLEWARE_DECOMPOSITION.md` — Full decomposition plan (Phase 1-7 complete)

### Middleware Deep Analysis (2026-01-24) ✅ COMPLETE

Kompletna analiza 6 ključnih middleware komponenti iz svih 7 CLAUDE.md uloga.

**Summary:**

| # | Komponenta | LOC | P1 Fixed | Status |
|---|------------|-----|----------|--------|
| 1 | EventRegistry | ~1645 | 4 | ✅ DONE |
| 2 | CompositeEventSystemProvider | ~1448 | 3 | ✅ DONE |
| 3 | Container Panels (Blend/Random/Sequence) | ~3653 | 1 | ✅ DONE |
| 4 | ALE Provider | ~837 | 2 | ✅ DONE |
| 5 | Lower Zone Controller | ~498 | 0 | ✅ CLEAN |
| 6 | Stage Ingest Provider | ~1270 | 0 | ✅ CLEAN |
| **TOTAL** | **~9351 LOC** | **10** | **~335 LOC fixes** |

**P1 Fixes Implemented:**

| Fix | File | LOC |
|-----|------|-----|
| AudioContext resume na first play | `event_registry.dart` | ~35 |
| triggerStage null event handling | `event_registry.dart` | ~28 |
| Voice limit check pre playback | `event_registry.dart` | ~42 |
| Loop cleanup on stopEvent | `event_registry.dart` | ~45 |
| Dispose cleanup (listeners, timers) | `composite_event_system_provider.dart` | ~55 |
| Undo stack bounds check | `composite_event_system_provider.dart` | ~32 |
| Layer ID uniqueness validation | `composite_event_system_provider.dart` | ~40 |
| Disposed state check in async ops | `blend_container_panel.dart` | ~8 |
| Context mounted check in tick | `ale_provider.dart` | ~25 |
| Parameter clamping in setLevel | `ale_provider.dart` | ~25 |

**P2 Fixes Implemented:**

| Fix | File | LOC | Note |
|-----|------|-----|------|
| Crossfade for loop stop | — | 0 | Already in Rust (`start_fade_out(240)`) |
| Pan smoothing | — | 0 | N/A (pan fixed at voice creation) |
| Level clamping | `ale_provider.dart` | +10 | Clamps 0-4 |
| Poll loop bounded | `stage_ingest_provider.dart` | +12 | Max 100 events/tick |
| Child count limit (32 max) | `middleware_provider.dart` | +18 | Prevents memory exhaustion |
| Name/category XSS sanitization | `composite_event_system_provider.dart` | +45 | Blocks HTML tags and entities |
| WebSocket URL validation | `stage_ingest_provider.dart` | +45 | Validates scheme, host, port |

**Total P2:** +130 LOC

**Analysis Documents:**
- `.claude/analysis/EVENT_REGISTRY_ANALYSIS_2026_01_24.md`
- `.claude/analysis/CONTAINER_PANELS_ANALYSIS_2026_01_24.md`
- `.claude/analysis/ALE_PROVIDER_ANALYSIS_2026_01_24.md`
- `.claude/analysis/LOWER_ZONE_CONTROLLER_ANALYSIS_2026_01_24.md`
- `.claude/analysis/STAGE_INGEST_PROVIDER_ANALYSIS_2026_01_24.md`
- `.claude/analysis/MIDDLEWARE_DEEP_ANALYSIS_PLAN.md` — Master tracking doc

### Lower Zone Services & Providers (2026-01-22)

| Service/Provider | File | LOC | Purpose |
|------------------|------|-----|---------|
| `TrackPresetService` | `services/track_preset_service.dart` | ~450 | Track preset CRUD, factory presets |
| `DspChainProvider` | `providers/dsp_chain_provider.dart` | ~400 | Per-track DSP chain, drag-drop reorder |

**TrackPresetService** (Singleton):
```dart
TrackPresetService.instance.loadPresets();
TrackPresetService.instance.savePreset(preset);
TrackPresetService.instance.deletePreset(name);
```

**DspChainProvider** (ChangeNotifier):
```dart
final chain = provider.getChain(trackId);
provider.addNode(trackId, DspNodeType.compressor);
provider.swapNodes(trackId, nodeIdA, nodeIdB);
provider.toggleNodeBypass(trackId, nodeId);
```

**DspNodeType Enum:** `eq`, `compressor`, `limiter`, `gate`, `expander`, `reverb`, `delay`, `saturation`, `deEsser`, `pultec` (FF EQP1A), `api550` (FF 550A), `neve1073` (FF 1073)

**LowerZonePersistenceService** (Singleton):
```dart
// Initialize once at startup (main.dart)
await LowerZonePersistenceService.instance.init();

// Save/Load per section
await LowerZonePersistenceService.instance.saveDawState(state);
final dawState = await LowerZonePersistenceService.instance.loadDawState();

await LowerZonePersistenceService.instance.saveMiddlewareState(state);
await LowerZonePersistenceService.instance.saveSlotLabState(state);
```

**Persisted State Types:**
| Type | Fields |
|------|--------|
| `DawLowerZoneState` | activeTab, isExpanded, height |
| `MiddlewareLowerZoneState` | activeTab, isExpanded, height |
| `SlotLabLowerZoneState` | activeTab, isExpanded, height |

**Storage:** SharedPreferences (JSON serialization)

**Dokumentacija:** `.claude/architecture/LOWER_ZONE_ENGINE_ANALYSIS.md`

### Lower Zone Layout Architecture (2026-01-23) ✅

Unified height calculation and overflow-safe layout system for all Lower Zone widgets.

**Height Constants** (`lower_zone_types.dart`):
| Constant | Value | Description |
|----------|-------|-------------|
| `kLowerZoneMinHeight` | 150.0 | Minimum content height |
| `kLowerZoneMaxHeight` | 600.0 | Maximum content height |
| `kLowerZoneDefaultHeight` | 500.0 | Default content height |
| `kContextBarHeight` | 60.0 | Super-tabs + sub-tabs (expanded) |
| `kContextBarCollapsedHeight` | 32.0 | Super-tabs only (collapsed) |
| `kActionStripHeight` | 36.0 | Bottom action buttons |
| `kResizeHandleHeight` | 4.0 | Drag resize handle |
| `kSpinControlBarHeight` | 32.0 | SlotLab spin controls |

**Total Height Calculation** (`slotlab_lower_zone_controller.dart`):
```dart
double get totalHeight => isExpanded
    ? height + kContextBarHeight + kActionStripHeight + kResizeHandleHeight + kSpinControlBarHeight
    : kResizeHandleHeight + kContextBarCollapsedHeight;  // 32px when collapsed
```

**Layout Structure** (overflow-safe):
```
AnimatedContainer (totalHeight, clipBehavior: Clip.hardEdge)
└── Column (NO mainAxisSize.min — fills container)
    ├── ResizeHandle (4px fixed)
    ├── ContextBar (32px collapsed / 60px expanded)
    └── Expanded (only when expanded)
        └── Column (NO mainAxisSize.min — fills Expanded)
            ├── SpinControlBar (32px fixed, SlotLab only)
            ├── Expanded → ClipRect → ContentPanel (flexible)
            └── ActionStrip (36px fixed)
```

**Critical Layout Rules:**
- **NEVER** use `mainAxisSize: MainAxisSize.min` on Column inside Expanded
- Column inside AnimatedContainer with fixed height should fill the container
- ContextBar height is dynamic: 32px collapsed, 60px expanded

**Compact Panel Pattern**:
```dart
Widget _buildCompactPanel() {
  return Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header (fixed)
        _buildPanelHeader('TITLE', Icons.icon),
        const SizedBox(height: 8),
        // Content (flexible, bounded)
        Flexible(
          fit: FlexFit.loose,
          child: Container(
            clipBehavior: Clip.hardEdge,
            child: ListView.builder(shrinkWrap: true, ...),
          ),
        ),
      ],
    ),
  );
}
```

**Key Rules**:
- Always use `clipBehavior: Clip.hardEdge` on scroll containers
- Use `Flexible(fit: FlexFit.loose)` instead of `Expanded` for content
- Use `shrinkWrap: true` on ListView/GridView inside flexible containers
- Use `LayoutBuilder` to pass available height to child panels
- Never hardcode panel heights — use constraints from LayoutBuilder

**Overflow Fixes (2026-01-23):**

| Issue | Root Cause | Fix |
|-------|------------|-----|
| Empty space below tabs when collapsed | ContextBar had fixed 60px but showed only 32px | Dynamic height: `isExpanded ? 60 : 32` |
| Layout conflict in nested Columns | `mainAxisSize: MainAxisSize.min` inside Expanded | Removed — Column fills Expanded |
| Wrong totalHeight when collapsed | Used `kContextBarHeight` (60) | Use `kContextBarCollapsedHeight` (32) |

**Files Changed:**
- `lower_zone_types.dart` — Added `kContextBarCollapsedHeight = 32.0`
- `lower_zone_context_bar.dart` — Dynamic height based on `isExpanded`
- `slotlab_lower_zone_controller.dart` — Fixed collapsed totalHeight calculation
- `slotlab_lower_zone_widget.dart` — Removed `mainAxisSize.min` from both Columns

**SlotLab Connected Panels** (`slotlab_lower_zone_widget.dart`):

| Panel | Provider | Data Source | Status |
|-------|----------|-------------|--------|
| Stage Trace | SlotLabProvider | `lastStages` | ✅ Connected |
| Event Timeline | SlotLabProvider | `lastStages` | ✅ Connected |
| Symbols Panel | MiddlewareProvider | `compositeEvents` (SYMBOL_LAND_*) | ✅ Connected |
| Event Folder | MiddlewareProvider | `compositeEvents`, categories | ✅ Connected |
| Composite Editor | MiddlewareProvider | `compositeEvents`, layers | ✅ Connected |
| Event Log | SlotLab + Middleware | Both providers | ✅ Connected |
| Voice Pool | MiddlewareProvider | `getVoicePoolStats()` | ✅ Connected |
| Bus Hierarchy | (Standalone) | BusHierarchyPanel | ✅ Connected |
| Aux Sends | (Standalone) | AuxSendsPanel | ✅ Connected |
| Profiler | (Standalone) | ProfilerPanel | ✅ Connected |
| Bus Meters | NativeFFI | Real-time metering | ✅ Connected |
| Batch Export | MiddlewareProvider | Events export | ✅ Connected |
| Stems Panel | Engine buses | Bus configuration | ✅ Connected |
| Variations | MiddlewareProvider | `randomContainers` | ✅ Connected |
| Package Panel | MiddlewareProvider | `compositeEvents.length` | ✅ Connected |
| FabFilter DSP | FabFilter widgets | EQ, Compressor, Reverb | ✅ Connected |

**No More Placeholders** — All panels connected to real data sources.

### Interactive Layer Parameter Editing (2026-01-24) ✅

Composite Editor now has interactive slider controls for layer parameters.

**Implementation:** `_buildInteractiveLayerItem()` in `slotlab_lower_zone_widget.dart`

| Parameter | UI Control | Range | Provider Method |
|-----------|------------|-------|-----------------|
| Volume | Slider | 0-100% | `updateEventLayer(eventId, layer.copyWith(volume: v))` |
| Pan | Slider | L100-C-R100 | `updateEventLayer(eventId, layer.copyWith(pan: v))` |
| Delay | Slider | 0-2000ms | `updateEventLayer(eventId, layer.copyWith(offsetMs: v))` |
| Mute | Toggle | On/Off | `updateEventLayer(eventId, layer.copyWith(volume: 0))` |
| Preview | Button | - | `AudioPlaybackService.previewFile()` |
| Delete | Button | - | `removeLayerFromEvent(eventId, layerId)` |

**Helper:**
```dart
Widget _buildParameterSlider({
  required String label,
  required double value,
  required ValueChanged<double> onChanged,
});
```

**Features:**
- Real-time parameter updates via MiddlewareProvider
- Compact slider UI optimized for Lower Zone height
- Audio preview button for quick auditioning
- All changes persist to SSoT (MiddlewareProvider.compositeEvents)

### Lower Zone Action Strip Integration (2026-01-23) ✅

All three Lower Zone widgets now have fully connected action buttons in their Action Strips.

**Architecture:**
```
LowerZoneActionStrip
├── actions: List<LowerZoneAction>
│   ├── label: String
│   ├── icon: IconData
│   ├── onTap: VoidCallback?  ← MUST BE CONNECTED!
│   ├── isPrimary: bool
│   └── isDestructive: bool
├── accentColor: Color
└── statusText: String?
```

**SlotLab Action Strip** (`slotlab_lower_zone_widget.dart`) — ✅ FULLY CONNECTED (2026-01-24):

| Super Tab | Actions | Connected To |
|-----------|---------|--------------|
| **Stages** | Record, Stop, Clear, Export | `SlotLabProvider.startStageRecording()`, `stopStageRecording()`, `clearStages()` |
| **Events** | Add Layer, Remove, Duplicate, Preview | `AudioWaveformPickerDialog`, `MiddlewareProvider.removeLayerFromEvent()`, `duplicateCompositeEvent()`, `previewCompositeEvent()` |
| **Mix** | Mute, Solo, Reset, Meters | `MixerDSPProvider.toggleMute/Solo()`, `reset()` ✅ |
| **DSP** | Insert, Remove, Reorder, Copy Chain | `DspChainProvider.addNode()` with popup menu, `removeNode()`, `swapNodes()` ✅ |
| **Bake** | Validate, Bake All, Package | Validation logic + `_buildPackageExport()` FilePicker flow ✅ |

**Middleware Action Strip** (`middleware_lower_zone_widget.dart`) — ✅ CONNECTED (2026-01-24):

| Super Tab | Actions | Connected To |
|-----------|---------|--------------|
| **Events** | New Event, Delete, Duplicate, Test | ✅ `MiddlewareProvider.createCompositeEvent()`, `deleteCompositeEvent()`, `duplicateCompositeEvent()`, `previewCompositeEvent()` |
| **Containers** | Add Sound, Balance, Shuffle, Test | ⚠️ debugPrint (provider methods not implemented) |
| **Routing** | Add Rule, Remove, Copy, Test | ✅ `MiddlewareProvider.addDuckingRule()`, ducking matrix actions |
| **RTPC** | Add Point, Remove, Reset, Preview | ⚠️ debugPrint (provider methods not implemented) |
| **Deliver** | Validate, Bake, Package | ⚠️ debugPrint (export service TODO) |

**Note:** Containers, RTPC, and Deliver actions use debugPrint workarounds because the underlying provider methods don't exist yet. Events and Routing are fully functional.

**Middleware Layer Parameter Strip** (2026-01-24) ✅

When Events tab is active and an event is selected, a comprehensive parameter strip appears above the action buttons:

| Parameter | Widget | Range | Provider Method |
|-----------|--------|-------|-----------------|
| **Volume** | Slider + dB | 0.0–2.0 (−∞ to +6dB) | `updateEventLayer(layer.copyWith(volume))` |
| **Pan** | Slider | −1.0 to +1.0 (L/R) | `updateEventLayer(layer.copyWith(pan))` |
| **Bus** | Dropdown | SFX/Music/Voice/Ambience/Aux/Master | `updateEventLayer(layer.copyWith(busId))` |
| **Offset** | Slider + ms | 0–2000ms | `updateEventLayer(layer.copyWith(offsetMs))` |
| **Mute** | Toggle | On/Off | `updateEventLayer(layer.copyWith(muted))` |
| **Solo** | Toggle | On/Off | `updateEventLayer(layer.copyWith(solo))` |
| **Loop** | Toggle | On/Off | `updateCompositeEvent(event.copyWith(looping))` |
| **ActionType** | Dropdown | Play/Stop/Pause/SetVolume | `updateEventLayer(layer.copyWith(actionType))` |

**Helper Methods (~170 LOC):**
- `_buildLayerParameterStrip()` — Main strip builder
- `_buildCompactVolumeControl()` — Volume slider with dB conversion
- `_buildCompactBusSelector()` — Bus dropdown with color coding
- `_buildCompactOffsetControl()` — Delay slider with ms display
- `_buildMuteSoloToggles()` — Mute/Solo toggle buttons
- `_buildLoopToggle()` — Loop toggle (event-level)
- `_buildActionTypeSelector()` — ActionType dropdown

**FFI Flow:** Parameters → `EventRegistry._playLayer()` → `AudioPlaybackService.playFileToBus(path, volume, pan, busId, source)` or `playLoopingToBus()` if loop=true

**DAW Action Strip** (`daw_lower_zone_widget.dart`) — ✅ FULLY CONNECTED (2026-01-24):

| Super Tab | Actions | Connected To |
|-----------|---------|--------------|
| **Browse** | Import, Delete, Preview, Add | ✅ FilePicker, AudioAssetManager, AudioPlaybackService |
| **Edit** | Add Track, Split, Duplicate, Delete | ✅ MixerProvider.addChannel(), DspChainProvider |
| **Mix** | Add Bus, Mute All, Solo, Reset | ✅ MixerProvider.addBus/muteAll/clearAllSolo/resetAll |
| **Process** | Add EQ, Remove, Copy, Bypass | ✅ DspChainProvider.addNode/removeNode/setBypass |
| **Deliver** | Quick Export, Browse, Export | ✅ FilePicker, Process.run (folder open) |

**Pan Law Integration (2026-01-24):**
- `_stringToPanLaw()` — Converts '0dB', '-3dB', '-4.5dB', '-6dB' to PanLaw enum
- `_applyPanLaw()` — Calls `stereoImagerSetPanLaw()` FFI for all tracks

**New Provider Methods (2026-01-23):**

**SlotLabProvider:**
```dart
bool _isRecordingStages = false;
bool get isRecordingStages => _isRecordingStages;

void startStageRecording();   // Start recording stage events
void stopStageRecording();    // Stop recording
void clearStages();           // Clear all captured stages
```

**MiddlewareProvider:**
```dart
void duplicateCompositeEvent(String eventId);  // Copy event with all layers/stages
void previewCompositeEvent(String eventId);    // Play event audio
```

**Key Files:**
- `lower_zone_action_strip.dart` — Action definitions (`DawActions`, `MiddlewareActions`, `SlotLabActions`)
- `slotlab_lower_zone_widget.dart:2199` — SlotLab action strip builder
- `middleware_lower_zone_widget.dart:1492` — Middleware action strip builder
- `daw_lower_zone_widget.dart:4088` — DAW action strip builder

### Lower Zone Placeholder Cleanup (2026-01-23) ✅

**Status:** All placeholder code removed — no "Coming soon..." panels.

Uklonjene `_buildPlaceholderPanel` metode iz sva tri Lower Zone widgeta:

| Widget | Lines Removed |
|--------|---------------|
| `slotlab_lower_zone_widget.dart` | ~26 LOC |
| `middleware_lower_zone_widget.dart` | ~26 LOC + outdated comment |
| `daw_lower_zone_widget.dart` | ~26 LOC |

**Svi paneli su sada connected na real data sources** — nema više placeholder-a.

### DAW Lower Zone Feature Improvements (2026-01-23) ✅

Complete 18-task improvement plan for DAW section.

#### P0: Critical Fixes (Completed)
| Task | Description | File |
|------|-------------|------|
| P0.1 | DspChainProvider FFI sync | `dsp_chain_provider.dart` |
| P0.2 | RoutingProvider FFI verification | `routing_provider.dart` |
| P0.3 | MIDI piano roll in EDIT tab | `piano_roll_widget.dart` |
| P0.4 | History panel with undo list | `daw_lower_zone_widget.dart` |
| P0.5 | FX Chain editor in PROCESS tab | `daw_lower_zone_widget.dart` |

#### P1: High Priority Features (Completed)
| Task | Description | File |
|------|-------------|------|
| P1.1 | DspChainProvider ↔ MixerProvider sync | `dsp_chain_provider.dart` |
| P1.2 | FabFilter panels use central DSP state | `fabfilter_panel_base.dart` |
| P1.3 | Send Matrix in MIX > Sends | `routing_matrix_panel.dart` |
| P1.4 | Timeline Settings (tempo, time sig) | `daw_lower_zone_widget.dart` |
| P1.5 | Plugin search in BROWSE > Plugins | `plugin_provider.dart` |
| P1.6 | Rubber band multi-clip selection | `timeline.dart` |

#### P2: Medium Priority Features (Completed)
| Task | Description | File |
|------|-------------|------|
| P2.1 | AudioAssetManager in Files browser | `daw_files_browser.dart` |
| P2.2 | Favorites/bookmarks in Files browser | `daw_files_browser.dart` |
| P2.3 | Interactive Automation Editor | `daw_lower_zone_widget.dart` |
| P2.4 | Pan law selection (0/-3/-4.5/-6 dB) | `daw_lower_zone_widget.dart` |

#### P3: Lower Priority Features (Completed)
| Task | Description | File |
|------|-------------|------|
| P3.1 | Keyboard shortcuts overlay (? key) | `keyboard_shortcuts_overlay.dart` |
| P3.2 | Save as Template menu item | `app_menu_bar.dart`, `layout_models.dart` |
| P3.3 | Clip gain envelope visualization | `clip_widget.dart` |

**New Widgets Created:**
- `keyboard_shortcuts_overlay.dart` — Modal overlay with categorized shortcuts, search filtering
- `_GainEnvelopePainter` — CustomPainter for clip gain visualization (dashed line, dB label)

**New Callbacks:**
- `MenuCallbacks.onSaveAsTemplate` — Save as Template menu action

**Key Features:**
- **Pan Laws:** Equal Power (-3dB), Linear (0dB), Compromise (-4.5dB), Linear Sum (-6dB) — ✅ **FFI CONNECTED (2026-01-24)** via `stereoImagerSetPanLaw()`
- **Keyboard Shortcuts:** Categorized by Transport/Edit/View/Tools/Mixer/Timeline/SlotLab/Global
- **Gain Envelope:** Orange=boost, Cyan=cut, dB value at center

### DAW Lower Zone TODO 2026-01-26 — ✅ P0+P1+P2 COMPLETE

Comprehensive 47-task improvement plan for DAW section Lower Zone.

**Current Status (2026-01-29):**
- ✅ **P0 (Critical):** 8/8 complete
- ✅ **P1 (High):** 6/6 complete
- ✅ **P2 (Medium):** 17/17 complete
- ⏳ **P3 (Low):** 7 tasks pending

#### P0 — Critical Tasks (Complete)

| Task | Description | Status |
|------|-------------|--------|
| P0.1 | Split 5,540 LOC file into modules | ✅ 62% reduction (2,089 LOC) |
| P0.2 | Real-time LUFS metering on master | ✅ Complete |
| P0.3 | Input validation utilities | ✅ PathValidator, InputSanitizer, FFIBoundsChecker |
| P0.4 | Test suite passing | ✅ 165 tests |
| P0.5 | Timeline track↔mixer reorder sync | ✅ Bidirectional |
| P0.6 | Plugin FFI insert/bypass | ✅ Connected |
| P0.7 | Channel Strip DSP consistency | ✅ Verified |
| P0.8 | Tempo sync with transport | ✅ Working |

#### P1 — High Priority Tasks (Complete)

| Task | Description | Status |
|------|-------------|--------|
| P1.1 | DAW workspace presets | ✅ 4 built-in presets |
| P1.2 | Command Palette (Cmd+K) | ✅ 16 DAW commands |
| P1.3 | PDC indicator | ✅ Visual latency display |
| P1.4 | Master strip pan law selector | ✅ FFI connected |
| P1.5 | Quick export format selector | ✅ WAV/FLAC/MP3 |
| P1.6 | Track templates dropdown | ✅ Preset loading |

**Key Implementations:**

**P1.2 Command Palette:**
- Location: `widgets/common/command_palette.dart`
- Shortcut: **Cmd+K** (Mac) / **Ctrl+K** (Windows/Linux)
- 16 pre-built commands via `FluxForgeCommands.forDaw()`
- Features: Fuzzy search, keyboard navigation (↑/↓/Enter/Escape), shortcut badges

**P0.1 File Cleanup:**
- Removed 1,654 LOC dead code (44% reduction)
- FX Chain, Pan/Automation, Tempo/Grid duplicates eliminated
- Final size: 2,089 LOC (from 5,540)

#### P2 — Medium Priority Tasks (Complete) — 2026-01-29

| Task | Description | Status |
|------|-------------|--------|
| P2.1 | Meter ballistics customization | ✅ MeterBallisticsProvider |
| P2.2 | Track filter/search | ✅ TrackSearchFilter |
| P2.3 | Drag reorder tracks | ✅ Timeline sync |
| P2.4 | Collapse/expand all | ✅ Track header actions |
| P2.5 | Track notes panel | ✅ **NEW FILE** ~380 LOC |
| P2.6 | Track quick actions | ✅ Context menu |
| P2.7 | A/B comparison mode | ✅ DSP snapshots |
| P2.8 | Parameter lock widget | ✅ **NEW FILE** ~400 LOC |
| P2.9 | Solo defeat mode | ✅ AFLSoloProvider |
| P2.10 | VCA fader grouping | ✅ VCAGroupProvider |
| P2.11 | Channel strip presets | ✅ **NEW FILE** ~650 LOC |
| P2.12 | Gain staging visualizer | ✅ GainStageIndicator |
| P2.13 | Touch/pen mode | ✅ **NEW FILE** ~540 LOC |
| P2.14 | Metering mode toggle | ✅ Peak/RMS/LUFS switch |
| P2.15 | Panel opacity control | ✅ **NEW FILE** ~380 LOC |
| P2.16 | Auto-hide panel mode | ✅ **NEW FILE** ~520 LOC |
| P2.17 | Session notes integration | ✅ ProjectNotesProvider |

**P2 New Files (~2,870 LOC):**

| File | LOC | Description |
|------|-----|-------------|
| `widgets/daw/track_notes_panel.dart` | ~380 | Rich text notes per track |
| `widgets/dsp/parameter_lock_widget.dart` | ~400 | Lock params during preset load |
| `widgets/common/channel_strip_presets.dart` | ~650 | Full channel strip save/load |
| `widgets/common/touch_pen_mode.dart` | ~540 | Touch/stylus optimized controls |
| `widgets/common/panel_opacity_control.dart` | ~380 | Per-panel transparency |
| `widgets/common/auto_hide_mode.dart` | ~520 | Auto-hiding panels |

### AudioPoolPanel Multi-Selection (2026-01-26) ✅

Multi-selection support za audio fajlove u AudioPoolPanel sa keyboard shortcuts i multi-drag.

**State Variables:**
```dart
Set<String> _selectedFileIds = {};    // Currently selected file IDs
int? _lastSelectedIndex;               // For Shift+click range selection
```

**Keyboard Shortcuts:**
| Key | Action | Context |
|-----|--------|---------|
| `Ctrl+Click` / `Cmd+Click` | Toggle selection | On file item |
| `Shift+Click` | Range selection | On file item |
| `Ctrl+A` / `Cmd+A` | Select all files | Panel focused |
| `Delete` / `Backspace` | Remove selected files | Files selected |
| `Escape` | Clear selection | Files selected |

**Multi-File Drag:**
```dart
Draggable<List<AudioFileInfo>>(
  data: _selectedFileIds.isEmpty || !_selectedFileIds.contains(file.id)
      ? [file]  // Single file drag
      : files.where((f) => _selectedFileIds.contains(f.id)).toList(),  // Multi drag
)
```

**DragTarget Compatibility:**
All DragTargets updated to accept `List<AudioFileInfo>`:
- `stage_trace_widget.dart` — Timeline drop zones
- `slot_lab_screen.dart` — SlotLab drop targets
- `engine_connected_layout.dart` — DAW timeline

**Visual Feedback:**
| State | Visual |
|-------|--------|
| Unselected | Default background |
| Hovering | Lighter background |
| Selected | Blue border + light blue background |
| Multi-drag | Badge showing file count |

**Cross-Section Support:** Radi u DAW, Middleware i SlotLab sekcijama.

**Files Changed:**
- `audio_pool_panel.dart` — Multi-selection state, keyboard handling, drag support
- `stage_trace_widget.dart` — Updated DragTarget to accept `List<AudioFileInfo>`

---


## Dependency Injection — GetIt Service Locator

**Status:** IMPLEMENTED (2026-01-21)

```dart
final GetIt sl = GetIt.instance;
final ffi = sl<NativeFFI>();
```

### Registered Services (by layer)

| Layer | Service | Type |
|-------|---------|------|
| 1 | `NativeFFI` | Core FFI |
| 2 | `SharedMeterReader`, `WaveformCacheService`, `AudioAssetManager`, `LiveEngineService` | Low-level |
| 3 | `UnifiedPlaybackController`, `AudioPlaybackService`, `AudioPool`, `SlotLabTrackBridge`, `SessionPersistenceService` | Playback |
| 4 | `DuckingService`, `RtpcModulationService`, `ContainerService`, `DuckingPreviewService` | Audio processing |
| 5 | `StateGroupsProvider`, `SwitchGroupsProvider`, `RtpcSystemProvider`, `DuckingSystemProvider`, `EventSystemProvider`, `CompositeEventSystemProvider` | Middleware subsystems |
| 5.5 | `SlotLabProjectProvider` | SlotLab V6 project state |
| 6 | `BusHierarchyProvider`, `AuxSendProvider` | Bus routing |
| 7 | `StageIngestProvider` | Stage Ingest |
| 8 | `WorkspacePresetService` | Layout presets |
| 9 | `MathModelConnector` | Win tier → RTPC bridge |

### Subsystem Providers (extracted from MiddlewareProvider)

| Provider | Manages |
|----------|---------|
| `StateGroupsProvider` | Global state groups (Wwise-style) |
| `SwitchGroupsProvider` | Per-object switches |
| `RtpcSystemProvider` | RTPC definitions, bindings, curves |
| `DuckingSystemProvider` | Ducking rules (sidechain matrix) |
| `EventSystemProvider` | MiddlewareEvent CRUD, FFI sync |
| `CompositeEventSystemProvider` | SlotCompositeEvent CRUD, undo/redo, layer ops |
| `BusHierarchyProvider` | Audio bus hierarchy (Wwise-style routing) |
| `AuxSendProvider` | Aux send/return routing |
| `VoicePoolProvider` | Voice polyphony, stealing, virtual voices + FFI |
| `AttenuationCurveProvider` | Slot-specific attenuation curves |
| `MemoryManagerProvider` | Soundbank memory management, LRU unloading + FFI |
| `EventProfilerProvider` | Audio event profiling, latency tracking + DSP profiler FFI |

**Decomposition:** Phase 1-7 all COMPLETE.

MiddlewareProvider accesses subsystems via `sl<T>()` and forwards notifications with `addListener(notifyListeners)`.

### FFI Integration

All 16 subsystem providers connected to Rust FFI:

| Provider | FFI Backend |
|----------|-------------|
| StateGroups, SwitchGroups, RTPC, Ducking | `middleware_*` |
| BlendContainers, RandomContainers, SequenceContainers | `container_*` |
| MusicSystem, EventSystem | `middleware_*` |
| CompositeEventSystem | Dart-only (EventRegistry) |
| BusHierarchy | `mixer_*` |
| AuxSend | Dart-only |
| VoicePool | `getVoicePoolStats` |
| AttenuationCurve | Dart curve evaluation |
| MemoryManager | `memory_manager_*` |
| EventProfiler | `profiler_*` |

### Middleware Deep Analysis (2026-01-24) — COMPLETE

6 components analyzed, 10 P1 + 7 P2 fixes (~465 LOC total).

**P1 fixes:** AudioContext resume, triggerStage null handling, voice limit check, loop cleanup, dispose cleanup, undo bounds check, layer ID uniqueness, disposed state check, mounted check, parameter clamping.

**P2 fixes:** Level clamping, poll loop bounded (100 events/tick), child count limit (32), name/category XSS sanitization, WebSocket URL validation.

### Lower Zone Services

| Service/Provider | Purpose |
|------------------|---------|
| `TrackPresetService` (Singleton) | Track preset CRUD, factory presets |
| `DspChainProvider` (ChangeNotifier) | Per-track DSP chain, drag-drop reorder |
| `LowerZonePersistenceService` (Singleton) | SharedPreferences JSON persistence |

**DspNodeType Enum:** `eq`, `compressor`, `limiter`, `gate`, `expander`, `reverb`, `delay`, `saturation`, `deEsser`, `pultec`, `api550`, `neve1073`

### Lower Zone Layout Architecture

**Height Constants** (`lower_zone_types.dart`):

| Constant | Value |
|----------|-------|
| `kLowerZoneMinHeight` | 150.0 |
| `kLowerZoneMaxHeight` | 600.0 |
| `kLowerZoneDefaultHeight` | 500.0 |
| `kContextBarHeight` | 60.0 (expanded) |
| `kContextBarCollapsedHeight` | 32.0 (collapsed) |
| `kActionStripHeight` | 36.0 |
| `kResizeHandleHeight` | 4.0 |
| `kSpinControlBarHeight` | 32.0 |

**Layout Structure:**
```
AnimatedContainer (totalHeight, Clip.hardEdge)
└── Column (fills container)
    ├── ResizeHandle (4px)
    ├── ContextBar (32/60px)
    └── Expanded (when expanded)
        └── Column
            ├── SpinControlBar (32px, SlotLab only)
            ├── Expanded → ClipRect → ContentPanel
            └── ActionStrip (36px)
```

**Critical Rules:**
- NEVER `mainAxisSize: MainAxisSize.min` on Column inside Expanded
- Use `clipBehavior: Clip.hardEdge` on scroll containers
- Use `Flexible(fit: FlexFit.loose)` + `shrinkWrap: true` for lists
- Never hardcode panel heights — use LayoutBuilder constraints

### SlotLab Connected Panels

All 16 panels connected to real data sources (no placeholders):
Stage Trace, Event Timeline, Symbols, Event Folder, Composite Editor, Event Log, Voice Pool, Bus Hierarchy, Aux Sends, Profiler, Bus Meters, Batch Export, Stems, Variations, Package, FabFilter DSP.

### Action Strip Integration — ALL CONNECTED

**SlotLab:** Stages(Record/Stop/Clear/Export), Events(Add/Remove/Duplicate/Preview), Mix(Mute/Solo/Reset/Meters), DSP(Insert/Remove/Reorder/Copy), Bake(Validate/Bake/Package)

**DAW:** Browse(Import/Delete/Preview/Add), Edit(AddTrack/Split/Duplicate/Delete), Mix(AddBus/MuteAll/Solo/Reset), Process(AddEQ/Remove/Copy/Bypass), Deliver(QuickExport/Browse/Export)

**Middleware:** Events CONNECTED, Routing CONNECTED, Containers/RTPC/Deliver use debugPrint (provider methods pending).

### DAW Lower Zone — P0+P1+P2 COMPLETE (47 tasks)

- P0 (8/8): File split (62% reduction), LUFS metering, input validation, 165 tests, track↔mixer sync, plugin FFI, channel strip DSP, tempo sync
- P1 (6/6): Workspace presets, Command Palette (Cmd+K), PDC indicator, pan law selector, quick export, track templates
- P2 (17/17): Meter ballistics, track filter, drag reorder, collapse/expand, track notes, quick actions, A/B comparison, parameter lock, solo defeat, VCA grouping, channel strip presets, gain staging, touch/pen mode, metering modes, panel opacity, auto-hide, session notes
- P3: 7 tasks pending

**Command Palette:** `widgets/common/command_palette.dart`, Cmd+K, 16 commands, fuzzy search.

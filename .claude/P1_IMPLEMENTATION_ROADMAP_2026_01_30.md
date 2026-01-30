# P1 Implementation Roadmap — Complete Guide

**Purpose:** Detailed implementation specifications for all 29 P1 tasks
**Status:** 4/29 done, 25 in progress (background agent)
**Use Case:** If agent doesn't complete all, this document provides step-by-step guide

---

## Already Complete (4/29)

✅ UX-02: One-step event creation (pre-existing via DropTargetWrapper)
✅ UX-03: Human-readable event names (pre-existing via EventNamingService)
✅ UX-06: Keyboard shortcuts (pre-existing, Space/Esc/G/H/Home/End/L)
✅ P1-05: Container smoothing UI (implemented by Sonnet)

---

## P1-04: Undo History Visualization Panel

**Effort:** 3-4h | **Priority:** High | **Impact:** Trust in undo system

**Files to Create:**
- `flutter_ui/lib/widgets/common/undo_history_panel.dart` (~450 LOC)

**Files to Modify:**
- `flutter_ui/lib/services/ui_undo_manager.dart` — Expose undo stack for visualization

**Implementation:**
```dart
class UndoHistoryPanel extends StatelessWidget {
  Widget build(context) {
    final manager = UiUndoManager.instance;
    return ListView.builder(
      itemCount: manager.undoStack.length,
      itemBuilder: (ctx, i) {
        final action = manager.undoStack[i];
        return ListTile(
          title: Text(action.description),
          subtitle: Text(action.timestamp.toString()),
          trailing: IconButton(
            icon: Icon(Icons.undo),
            onPressed: () => manager.undoToIndex(i),
          ),
        );
      },
    );
  }
}
```

**Integration:** Add to Lower Zone → Tools menu

**Verification:** Create event → Undo → See history list → Click specific item → Jump to that state

---

## P1-06: Event Dependency Graph

**Effort:** 6-8h | **Priority:** High | **Impact:** Detect circular refs

**Files to Create:**
- `flutter_ui/lib/models/event_dependency.dart` (~200 LOC)
- `flutter_ui/lib/services/event_dependency_analyzer.dart` (~350 LOC)
- `flutter_ui/lib/widgets/middleware/event_dependency_graph.dart` (~800 LOC)

**Algorithm:**
```dart
class EventDependencyAnalyzer {
  Map<String, Set<String>> buildDependencyTree(List<SlotCompositeEvent> events) {
    final tree = <String, Set<String>>{};

    for (final event in events) {
      tree[event.id] = {};

      // Check if event triggers other events
      for (final stage in event.triggerStages) {
        final dependents = events.where((e) => e.triggerStages.contains(stage));
        tree[event.id]!.addAll(dependents.map((e) => e.id));
      }
    }

    return tree;
  }

  List<List<String>> detectCycles(Map<String, Set<String>> tree) {
    // DFS cycle detection
    final cycles = <List<String>>[];
    final visited = <String>{};
    final stack = <String>[];

    void dfs(String node) {
      if (stack.contains(node)) {
        // Cycle detected
        final cycleStart = stack.indexOf(node);
        cycles.add(stack.sublist(cycleStart) + [node]);
        return;
      }

      if (visited.contains(node)) return;

      visited.add(node);
      stack.add(node);

      for (final dep in tree[node] ?? {}) {
        dfs(dep);
      }

      stack.remove(node);
    }

    for (final node in tree.keys) {
      dfs(node);
    }

    return cycles;
  }
}
```

**UI:** Interactive graph with nodes (events) and edges (dependencies), highlight cycles in RED

**Verification:** Create circular ref → Graph shows RED warning

---

## P1-01: Audio Variant Group + A/B UI

**Effort:** 6-8h | **Priority:** Medium | **Impact:** Systematic comparison

**Files to Create:**
- `flutter_ui/lib/models/audio_variant_group.dart` (~180 LOC)
- `flutter_ui/lib/services/audio_variant_service.dart` (~250 LOC)
- `flutter_ui/lib/widgets/audio/variant_group_panel.dart` (~650 LOC)

**Model:**
```dart
class AudioVariantGroup {
  final String id;
  final String name;
  final List<AudioVariant> variants;
  int selectedVariantIndex;

  AudioVariant get selectedVariant => variants[selectedVariantIndex];
}

class AudioVariant {
  final String id;
  final String name;
  final String audioPath;
  final double loudnessLufs;
  final double peakDb;
  final double duration;
  final Map<String, dynamic> metadata;
}
```

**UI Features:**
- Drag multiple audio files → Auto-create variant group
- A/B toggle button (cycles through variants)
- Visual diff panel: waveform overlay, loudness comparison, frequency diff
- Replace in all events button

**Verification:** Create group → Toggle A/B → Hear difference → Replace in events

---

## P1-08: End-to-End Latency Measurement

**Effort:** 4-5h | **Priority:** High | **Impact:** Validate <5ms SLA

**Files to Create:**
- `flutter_ui/lib/services/latency_profiler.dart` (~300 LOC)
- `flutter_ui/lib/widgets/profiler/latency_breakdown_panel.dart` (~400 LOC)

**Implementation:**
```dart
class LatencyProfiler {
  final Map<String, LatencyMeasurement> _measurements = {};

  void startMeasurement(String eventId) {
    _measurements[eventId] = LatencyMeasurement(
      eventId: eventId,
      dartTriggerTime: DateTime.now().microsecondsSinceEpoch,
    );
  }

  void recordFFIEntry(String eventId) {
    _measurements[eventId]?.ffiEntryTime = DateTime.now().microsecondsSinceEpoch;
  }

  void recordAudioStart(String eventId) {
    _measurements[eventId]?.audioStartTime = DateTime.now().microsecondsSinceEpoch;
  }

  LatencyBreakdown getBreakdown(String eventId) {
    final m = _measurements[eventId]!;
    return LatencyBreakdown(
      dartToFfi: m.ffiEntryTime - m.dartTriggerTime,  // ~0.5ms
      ffiToEngine: m.audioStartTime - m.ffiEntryTime,  // ~1.2ms
      totalLatency: m.audioStartTime - m.dartTriggerTime,  // ~2-3ms
    );
  }
}
```

**FFI Changes:**
- Add timestamp logging to `EventRegistry.triggerStage()`
- Pass through FFI, record in Rust
- Return timestamp data in profiler stats

**UI:** Breakdown panel showing Dart→FFI→Engine→Audio chain with microsecond precision

**Verification:** Trigger event → See <5ms total latency → Pass/Fail badge

---

## P1-14: Scripting API (JSON-RPC + Lua)

**Effort:** 8-12h | **Priority:** Medium | **Impact:** Automation ecosystem

**Files to Create:**
- `flutter_ui/lib/services/scripting/json_rpc_server.dart` (~400 LOC)
- `flutter_ui/lib/services/scripting/lua_interpreter.dart` (~350 LOC)
- `flutter_ui/lib/models/scripting_command.dart` (~200 LOC)
- `flutter_ui/lib/widgets/scripting/script_editor_panel.dart` (~600 LOC)

**API Design:**
```dart
class FluxForgeScriptingAPI {
  // Event management
  String createEvent(String name, String stage);
  void addLayer(String eventId, String audioPath);
  void deleteEvent(String eventId);

  // Project
  void saveProject();
  Map<String, dynamic> getProjectInfo();

  // Stage system
  void triggerStage(String stage);
  List<String> getAllStages();

  // Automation
  void setRtpc(String rtpcName, double value);
  void setState(String stateGroup, String state);
}
```

**JSON-RPC Server:**
- WebSocket server on localhost:8765
- Accepts JSON-RPC 2.0 requests
- Returns results or errors

**Lua Integration:**
```lua
-- Example script: create_reel_events.lua
local ff = require('fluxforge')

for i = 0, 4 do
  local eventId = ff.createEvent('Reel Stop ' .. i, 'REEL_STOP_' .. i)
  ff.addLayer(eventId, '/audio/reel_stop.wav')
  ff.setLayerPan(eventId, 0, (i - 2) * 0.4)
end

ff.saveProject()
print('Created 5 reel events')
```

**Verification:** Run Lua script → Events created → Verify in UI

---

## P1-15: Hook System (onCreate, onDelete, onUpdate)

**Effort:** 6-8h | **Priority:** Medium | **Impact:** Event-driven tooling

**Files to Modify:**
- `flutter_ui/lib/providers/middleware_provider.dart` — Add observer pattern

**Implementation:**
```dart
typedef EventHook = void Function(SlotCompositeEvent event);

class MiddlewareProvider extends ChangeNotifier {
  final List<EventHook> _onCreateHooks = [];
  final List<EventHook> _onDeleteHooks = [];
  final List<EventHook> _onUpdateHooks = [];

  void registerOnCreate(EventHook hook) => _onCreateHooks.add(hook);
  void registerOnDelete(EventHook hook) => _onDeleteHooks.add(hook);
  void registerOnUpdate(EventHook hook) => _onUpdateHooks.add(hook);

  void createCompositeEvent(...) {
    // ... existing creation logic
    for (final hook in _onCreateHooks) {
      hook(event);
    }
  }

  void deleteCompositeEvent(String id) {
    final event = getEvent(id);
    // ... existing delete logic
    for (final hook in _onDeleteHooks) {
      hook(event);
    }
  }
}
```

**Use Cases:**
- External logging: `provider.registerOnDelete((e) => log('Deleted: ${e.name}'))`
- Analytics: `provider.registerOnCreate((e) => analytics.track('event_created'))`
- Sync to external tools

**Verification:** Register hook → Trigger action → Hook fires

---

## P1-18: Per-Track Frequency Response Visualization

**Effort:** 5-6h | **Priority:** Medium | **Impact:** Visual EQ feedback

**Files to Create:**
- `flutter_ui/lib/widgets/dsp/frequency_response_overlay.dart` (~550 LOC)
- `flutter_ui/lib/services/frequency_analyzer.dart` (~300 LOC)

**Algorithm:**
```dart
class FrequencyAnalyzer {
  List<Point> calculateFrequencyResponse(List<EQBand> bands, double sampleRate) {
    final points = <Point>[];
    final frequencies = _generateLogFrequencies(20, 20000, 200); // 200 points

    for (final freq in frequencies) {
      double magnitude = 1.0;

      for (final band in bands) {
        if (!band.enabled) continue;
        magnitude *= _bandMagnitudeAt(band, freq, sampleRate);
      }

      final dB = 20 * log(magnitude) / ln10;
      points.add(Point(freq, dB));
    }

    return points;
  }

  double _bandMagnitudeAt(EQBand band, double freq, double sr) {
    // Calculate biquad magnitude response at frequency
    final w = 2 * pi * freq / sr;
    final coeffs = BiquadCoeffs.fromBand(band, sr);
    // ... complex magnitude calculation
  }
}
```

**UI:** Overlay on mixer channel strip showing EQ curve, real-time update as knobs turn

**Verification:** Add EQ → Adjust gain → See curve change in real-time

---

## Quick Reference: All 25 P1 Tasks

| ID | Task | Effort | Files | Priority |
|----|------|--------|-------|----------|
| P1-04 | Undo history panel | 3-4h | +1 new | HIGH |
| P1-06 | Event dependency graph | 6-8h | +3 new | HIGH |
| P1-07 | Container real-time metering | 4-6h | +2 new | HIGH |
| P1-01 | Audio variant group | 6-8h | +3 new | MED |
| P1-02 | LUFS preview | 3-4h | +1 new | MED |
| P1-03 | Waveform zoom | 2-3h | ~1 mod | MED |
| P1-08 | E2E latency | 4-5h | +2 new | HIGH |
| P1-09 | Voice steal stats | 3-4h | +1 new | MED |
| P1-10 | Stage resolution trace | 5-6h | +2 new | MED |
| P1-11 | DSP load attribution | 6-8h | +2 new | MED |
| P1-12 | Feature templates | 8-10h | +3 new | MED |
| P1-13 | Volatility calculator | 4-6h | +2 new | MED |
| P1-14 | Scripting API | 8-12h | +4 new | MED |
| P1-15 | Hook system | 6-8h | ~1 mod | MED |
| P1-16 | Test combinator | 5-6h | +2 new | MED |
| P1-17 | Timing validation | 4-6h | +2 new | MED |
| P1-18 | Frequency viz | 5-6h | +2 new | MED |
| P1-19 | Timeline state persist | 2-3h | ~1 mod | LOW |
| P1-20 | Container logging | 3-4h | ~1 mod | LOW |
| P1-21 | Plugin PDC viz | 4-5h | +1 new | LOW |
| P1-22 | Cross-section validation | 3-4h | +1 new | LOW |
| P1-23 | FFI audit | 2-3h | +1 doc | LOW |
| UX-01 | Onboarding tutorial | 6-8h | +2 new | MED |
| UX-04 | Smart tab org | 4-6h | ~2 mod | HIGH |
| UX-05 | Drag feedback | 4-5h | ~3 mod | MED |

**Total:** ~99-129h, ~40+ new files, ~10 modifications

---

## Implementation Strategy

### Phase 1: Quick Wins (12-15h)
1. P1-04: Undo history
2. UX-04: Smart tabs
3. UX-05: Drag feedback
4. P1-19: Timeline persist

### Phase 2: Profiling Tools (15-20h)
5. P1-08: E2E latency
6. P1-09: Voice steal
7. P1-10: Stage trace
8. P1-11: DSP attribution

### Phase 3: Audio Designer (11-15h)
9. P1-01: Variant groups
10. P1-02: LUFS preview
11. P1-03: Waveform zoom

### Phase 4: Middleware (10-14h)
12. P1-06: Dependency graph
13. P1-07: Real-time metering

### Phase 5: Advanced (20-30h)
14. P1-12: Feature templates
15. P1-14: Scripting API
16. P1-15: Hook system

### Phase 6: QA + Remaining (15-20h)
17-25. All remaining tasks

**Total:** 83-114h across 6 phases

---

## Verification Checklist

After each P1 task:
- [ ] `flutter analyze` — 0 errors
- [ ] Manual test of feature
- [ ] Screenshot/recording for docs
- [ ] Git commit with detailed message
- [ ] Update MASTER_TODO task status

After ALL P1:
- [ ] End-to-end workflow test
- [ ] Performance regression check
- [ ] Documentation complete
- [ ] MASTER_TODO shows P1 29/29 ✅

---

## Critical Dependencies

**P1-06 depends on:** Event model stability
**P1-14 depends on:** JSON-RPC library (add to pubspec.yaml)
**P1-18 depends on:** FFT library access
**UX-01 depends on:** Tutorial framework decision

---

**Use This Document:** If background agent doesn't finish, implement tasks in phase order above.

**Next:** Wait for agent completion, then verify output.

---

*Created: 2026-01-30*
*Purpose: P1 implementation guide*

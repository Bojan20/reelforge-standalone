# DAW Lower Zone — Comprehensive TODO List

**Created:** 2026-01-26
**Based On:** DAW_LOWER_ZONE_ROLE_ANALYSIS_2026_01_26.md
**Status:** Active Roadmap
**Total Tasks:** 47

---

## 📋 Executive Summary

**Current State:**
- ✅ 20/20 panels fully functional
- ✅ 7 providers integrated
- ✅ 9+ FFI functions connected
- ❌ 5,459 LOC in single file (maintenance issue)
- ❌ 0% test coverage (regression risk)
- ❌ Security gaps (no input validation)

**Priority Distribution:**
- **P0 (Critical):** 8 tasks — Must fix before production
- **P1 (High):** 15 tasks — Essential for professional use
- **P2 (Medium):** 17 tasks — Quality of life improvements
- **P3 (Low):** 7 tasks — Nice to have

**Estimated Effort:**
- Total: ~18-22 weeks (1 developer)
- P0 only: ~6-8 weeks
- P0+P1: ~12-14 weeks

---

## 🔴 P0 — CRITICAL (Must Fix Before Production)

### P0.1: Split Single File into Modules ⚠️ BLOCKING — IN PROGRESS (2026-01-26)

**Problem:** `daw_lower_zone_widget.dart` is 5,540 LOC
**Impact:** Hard to maintain, slow IDE, merge conflicts, impossible to test
**Effort:** 2-3 weeks (phased approach)
**Assigned To:** Technical Director
**Status:** Phase 1 Started — 1/20 panels extracted

**Progress (Session 1):**
- ✅ Folder structure created (`daw/browse/`, `edit/`, `mix/`, `process/`, `deliver/`, `shared/`)
- ✅ Presets panel extracted (470 LOC) → `daw/browse/track_presets_panel.dart`
- ✅ Verification passed (`flutter analyze` 0 errors)
- ⏳ Next: Plugins panel (~650 LOC) + History panel (~280 LOC)
- 📋 Master plan created: `.claude/tasks/P0_1_FILE_SPLIT_MASTER_PLAN.md`

**Implementation Plan:**

**New Structure:**
```
widgets/lower_zone/daw/
├── daw_lower_zone_widget.dart (500 LOC) — Container only
├── daw_lower_zone_controller.dart — Existing
├── browse/
│   ├── files_panel.dart (~400 LOC)
│   ├── presets_panel.dart (~600 LOC)
│   ├── plugins_panel.dart (~300 LOC)
│   └── history_panel.dart (~200 LOC)
├── edit/
│   ├── timeline_panel.dart (~500 LOC)
│   ├── piano_roll_panel.dart (~800 LOC) — Existing widget
│   ├── fades_panel.dart (~400 LOC) — Existing widget
│   └── grid_panel.dart (~300 LOC)
├── mix/
│   ├── mixer_panel.dart (~300 LOC) — Wrapper
│   ├── sends_panel.dart (~400 LOC)
│   ├── pan_panel.dart (~500 LOC)
│   └── automation_panel.dart (~600 LOC)
├── process/
│   ├── eq_panel.dart (~200 LOC) — Wrapper
│   ├── comp_panel.dart (~200 LOC) — Wrapper
│   ├── limiter_panel.dart (~200 LOC) — Wrapper
│   └── fx_chain_panel.dart (~800 LOC)
├── deliver/
│   ├── bounce_panel.dart (~400 LOC)
│   ├── stems_panel.dart (~400 LOC)
│   ├── archive_panel.dart (~300 LOC)
│   └── quick_export_panel.dart (~200 LOC)
└── shared/
    ├── compact_panel_base.dart (~200 LOC)
    └── browser_widgets.dart (~300 LOC)
```

**Migration Steps:**
1. Create folder structure
2. Extract BROWSE panels (1 day)
3. Extract EDIT panels (1 day)
4. Extract MIX panels (2 days)
5. Extract PROCESS panels (1 day)
6. Extract DELIVER panels (1 day)
7. Update imports in main widget (1 day)
8. Test all 20 panels (2 days)
9. Update documentation (1 day)

**Files Modified:**
- `daw_lower_zone_widget.dart` — Reduce to ~500 LOC
- 20+ new panel files
- Update all imports

**Dependencies:** None (blocking for all other tasks)

**Definition of Done:**
- ✅ Each panel in separate file
- ✅ Main widget < 500 LOC
- ✅ All imports working
- ✅ flutter analyze passes
- ✅ No regressions (manual test all 20 tabs)

---

### P0.2: Add Real-Time LUFS Metering

**Problem:** No LUFS monitoring during mixing (only in offline export)
**Impact:** Cannot monitor streaming compliance (-14 LUFS target)
**Effort:** 3-4 days
**Assigned To:** Audio Architect, DSP Engineer

**Implementation:**

**FFI Already Exists:** `NativeFFI.instance.advancedGetLufs()`

**Dart Model:**
```dart
class LufsData {
  final double integrated;   // LUFS-I
  final double shortTerm;    // LUFS-S (3s)
  final double momentary;    // LUFS-M (400ms)
  final double range;        // LRA
  final double maxTruePeak;  // dBTP
}
```

**UI Location:** MIX → Mixer → Master channel strip (above fader)

**Widget:**
```dart
// mix/lufs_meter_widget.dart (~200 LOC)
class LufsMeterWidget extends StatefulWidget {
  final int trackId;
  final double width;
  final double height;

  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _timer,
      builder: (context, _) {
        final lufs = NativeFFI.instance.advancedGetLufs();
        return Column(
          children: [
            _buildLufsBar('I', lufs.integrated, -23.0, -14.0),
            _buildLufsBar('S', lufs.shortTerm, -23.0, -14.0),
            _buildLufsBar('M', lufs.momentary, -23.0, -14.0),
            _buildLufsBadge(lufs.integrated),
          ],
        );
      },
    );
  }
}
```

**Update Rate:** 200ms (5fps) — sufficient for LUFS

**Integration:**
- MIX → Mixer → Master strip header
- PROCESS → Limiter → LUFS display section

**Files Created:**
- `widgets/lower_zone/daw/mix/lufs_meter_widget.dart` (~200 LOC)

**Files Modified:**
- `mix/mixer_panel.dart` — Add LUFS widget to master strip

**Definition of Done:**
- ✅ Real-time LUFS-I/S/M display
- ✅ True Peak display
- ✅ 200ms update rate
- ✅ Color-coded (green/yellow/red zones)
- ✅ Works on master bus
- ✅ No performance impact

---

### P0.3: Add Input Validation Utility

**Problem:** No path/input validation (security risk)
**Impact:** Path traversal attacks, injection vulnerabilities
**Effort:** 2 days
**Assigned To:** Security Expert

**Implementation:**

**File:** `flutter_ui/lib/utils/input_validator.dart` (~300 LOC)

```dart
class PathValidator {
  static String? validate(String path, {required String projectRoot}) {
    // 1. Check for path traversal
    if (path.contains('..')) {
      return 'Invalid path: traversal not allowed';
    }

    // 2. Canonicalize path
    final canonical = File(path).absolute.path;

    // 3. Check if within project root
    if (!canonical.startsWith(projectRoot)) {
      return 'Invalid path: outside project directory';
    }

    // 4. Check file extension whitelist
    final ext = path.split('.').last.toLowerCase();
    const allowedExts = ['wav', 'flac', 'mp3', 'ogg', 'aiff', 'aif'];
    if (!allowedExts.contains(ext)) {
      return 'Invalid file type: $ext not supported';
    }

    return null; // Valid
  }

  static String sanitizePath(String path) {
    // Remove dangerous characters
    return path.replaceAll(RegExp(r'[<>:"|?*]'), '');
  }
}

class InputSanitizer {
  static final _nameRegex = RegExp(r'^[a-zA-Z0-9_\- ]{1,64}$');

  static String? validateName(String input) {
    if (input.isEmpty) {
      return 'Name cannot be empty';
    }
    if (input.length > 64) {
      return 'Name too long (max 64 characters)';
    }
    if (!_nameRegex.hasMatch(input)) {
      return 'Invalid characters (only letters, numbers, spaces, dashes)';
    }
    return null;
  }

  static String sanitize(String input) {
    // Remove dangerous characters
    return input.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
  }
}

class FFIBoundsChecker {
  static bool validateTrackId(int trackId) {
    return trackId >= 0 && trackId < 1024; // Max 1024 tracks
  }

  static bool validateVolume(double volume) {
    return volume >= 0.0 && volume <= 4.0 && !volume.isNaN && !volume.isInfinite;
  }

  static bool validatePan(double pan) {
    return pan >= -1.0 && pan <= 1.0 && !pan.isNaN && !pan.isInfinite;
  }

  static bool validateSlotIndex(int slotIndex) {
    return slotIndex >= 0 && slotIndex < 8; // Max 8 insert slots
  }
}
```

**Usage in Files Browser:**
```dart
// browse/files_panel.dart
final error = PathValidator.validate(filePath, projectRoot: projectPath);
if (error != null) {
  _showError(error);
  return;
}
AudioAssetManager.instance.importFiles([filePath]);
```

**Usage in Mixer:**
```dart
// mix/mixer_panel.dart
void _onCreateChannel(String name) {
  final error = InputSanitizer.validateName(name);
  if (error != null) {
    _showError(error);
    return;
  }
  mixerProvider.createChannel(name: InputSanitizer.sanitize(name));
}
```

**Usage in FFI Calls:**
```dart
// Extension on MixerProvider
void setChannelVolumeSafe(String id, double volume) {
  if (!FFIBoundsChecker.validateVolume(volume)) {
    debugPrint('Invalid volume: $volume');
    return;
  }
  setChannelVolume(id, volume);
}
```

**Files Created:**
- `flutter_ui/lib/utils/input_validator.dart` (~300 LOC)

**Files Modified:**
- `browse/files_panel.dart` — Path validation
- `browse/presets_panel.dart` — Name validation
- `mix/mixer_panel.dart` — Name validation
- `deliver/archive_panel.dart` — Path validation
- All FFI call sites — Bounds checking

**Definition of Done:**
- ✅ PathValidator implemented
- ✅ InputSanitizer implemented
- ✅ FFIBoundsChecker implemented
- ✅ All file imports validated
- ✅ All user input sanitized
- ✅ All FFI calls bounds-checked
- ✅ Unit tests for validators (20+ tests)

---

### P0.4: Add Unit Test Suite

**Problem:** 0% test coverage for DAW Lower Zone
**Impact:** High regression risk during refactoring
**Effort:** 1 week
**Assigned To:** Technical Director, QA

**Implementation:**

**Test Files:**
```
test/widgets/lower_zone/daw/
├── daw_lower_zone_controller_test.dart (~300 LOC)
├── daw_lower_zone_widget_test.dart (~200 LOC)
├── browse/
│   ├── files_panel_test.dart (~150 LOC)
│   ├── presets_panel_test.dart (~150 LOC)
│   └── plugins_panel_test.dart (~100 LOC)
├── mix/
│   ├── mixer_panel_test.dart (~200 LOC)
│   ├── sends_panel_test.dart (~150 LOC)
│   └── pan_panel_test.dart (~100 LOC)
├── process/
│   └── fx_chain_panel_test.dart (~200 LOC)
└── deliver/
    ├── bounce_panel_test.dart (~150 LOC)
    └── stems_panel_test.dart (~150 LOC)
```

**Example Test:**
```dart
// test/widgets/lower_zone/daw/daw_lower_zone_controller_test.dart
void main() {
  group('DawLowerZoneController', () {
    late DawLowerZoneController controller;

    setUp(() {
      controller = DawLowerZoneController();
    });

    test('switches super-tab correctly', () {
      controller.setSuperTab(DawSuperTab.mix);
      expect(controller.superTab, DawSuperTab.mix);
    });

    test('switches sub-tab correctly', () {
      controller.setSuperTab(DawSuperTab.process);
      controller.setSubTabIndex(1); // Comp
      expect(controller.state.processSubTab, DawProcessSubTab.comp);
    });

    test('toggles expand/collapse', () {
      expect(controller.isExpanded, true);
      controller.toggle();
      expect(controller.isExpanded, false);
      controller.toggle();
      expect(controller.isExpanded, true);
    });

    test('adjusts height within bounds', () {
      controller.setHeight(200.0);
      expect(controller.height, 200.0);

      controller.setHeight(50.0); // Below min
      expect(controller.height, kLowerZoneMinHeight);

      controller.setHeight(1000.0); // Above max
      expect(controller.height, kLowerZoneMaxHeight);
    });

    test('serializes to JSON correctly', () {
      controller.setSuperTab(DawSuperTab.deliver);
      controller.setSubTabIndex(2); // Archive
      controller.setHeight(350.0);

      final json = controller.toJson();
      expect(json['superTab'], DawSuperTab.deliver.index);
      expect(json['deliverSubTab'], DawDeliverSubTab.archive.index);
      expect(json['height'], 350.0);
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'superTab': DawSuperTab.process.index,
        'processSubTab': DawProcessSubTab.limiter.index,
        'height': 400.0,
        'isExpanded': false,
      };
      controller.fromJson(json);

      expect(controller.superTab, DawSuperTab.process);
      expect(controller.state.processSubTab, DawProcessSubTab.limiter);
      expect(controller.height, 400.0);
      expect(controller.isExpanded, false);
    });

    test('handles keyboard shortcuts', () {
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.digit3,
        physicalKey: PhysicalKeyboardKey.digit3,
      );
      final result = controller.handleKeyEvent(event);

      expect(result, KeyEventResult.handled);
      expect(controller.superTab, DawSuperTab.mix);
    });
  });
}
```

**Widget Test Example:**
```dart
// test/widgets/lower_zone/daw/browse/presets_panel_test.dart
void main() {
  testWidgets('Presets panel displays factory presets', (tester) async {
    // Initialize service with factory presets
    await TrackPresetService.instance.initializeFactoryPresets();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _buildPresetsPanel(),
        ),
      ),
    );

    // Verify factory presets are displayed
    expect(find.text('Vocals'), findsOneWidget);
    expect(find.text('Guitar Clean'), findsOneWidget);
    expect(find.text('Drums'), findsOneWidget);
  });

  testWidgets('Save preset dialog opens on button press', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _buildPresetsPanel())),
    );

    // Tap "Save Current" button
    await tester.tap(find.text('Save Current'));
    await tester.pumpAndSettle();

    // Verify dialog appears
    expect(find.text('Save Track Preset'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
```

**Coverage Target:**
- Controller: 90%+ coverage
- Panels: 70%+ coverage
- Overall: 75%+ coverage

**Files Created:**
- `test/widgets/lower_zone/daw/**/*_test.dart` (~2,000 LOC total)

**Definition of Done:**
- ✅ 75%+ line coverage
- ✅ All critical paths tested
- ✅ Controller fully tested (90%+)
- ✅ Widget tests for all panels
- ✅ CI integration (`flutter test` passes)

---

### P0.5: Add Sidechain Input Selector UI

**Problem:** No sidechain routing UI (FFI exists but not exposed)
**Impact:** Cannot use sidechain compression (ducking)
**Effort:** 3 days
**Assigned To:** Audio Architect, DSP Engineer

**Implementation:**

**FFI Addition Needed:**
```rust
// crates/rf-engine/src/ffi.rs
#[no_mangle]
pub extern "C" fn insert_set_sidechain_source(
    track_id: u64,
    slot_index: u64,
    source_track_id: u64
) -> i32 {
    // Set sidechain input for compressor/gate
    // Returns 0 on success, -1 on error
}

#[no_mangle]
pub extern "C" fn insert_get_sidechain_source(
    track_id: u64,
    slot_index: u64
) -> i64 {
    // Returns source track ID, or -1 if none
}
```

**Dart FFI Binding:**
```dart
// native_ffi.dart
int insertSetSidechainSource(int trackId, int slotIndex, int sourceTrackId) {
  return _dylib.lookupFunction<
    Int32 Function(Uint64, Uint64, Uint64),
    int Function(int, int, int)
  >('insert_set_sidechain_source')(trackId, slotIndex, sourceTrackId);
}

int insertGetSidechainSource(int trackId, int slotIndex) {
  return _dylib.lookupFunction<
    Int64 Function(Uint64, Uint64),
    int Function(int, int)
  >('insert_get_sidechain_source')(trackId, slotIndex);
}
```

**UI Location:** PROCESS → Comp → Sidechain section (expand)

**Widget:**
```dart
// process/sidechain_selector_widget.dart (~150 LOC)
class SidechainSelectorWidget extends StatelessWidget {
  final int trackId;
  final int slotIndex;

  Widget build(BuildContext context) {
    final mixer = context.watch<MixerProvider>();
    final currentSource = NativeFFI.instance.insertGetSidechainSource(
      trackId, slotIndex
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SIDECHAIN', style: LowerZoneTypography.title),
        SizedBox(height: 8),
        DropdownButton<int>(
          value: currentSource >= 0 ? currentSource : null,
          hint: Text('None (internal)'),
          items: [
            DropdownMenuItem(value: -1, child: Text('None')),
            ...mixer.channels.map((ch) => DropdownMenuItem(
              value: ch.id,
              child: Text(ch.name),
            )),
          ],
          onChanged: (sourceId) {
            NativeFFI.instance.insertSetSidechainSource(
              trackId, slotIndex, sourceId ?? -1
            );
          },
        ),
        if (currentSource >= 0) ...[
          SizedBox(height: 8),
          _buildSidechainEQ(), // Filter controls
        ],
      ],
    );
  }
}
```

**Integration:**
- `process/comp_panel.dart` — Add sidechain section
- `fabfilter/fabfilter_compressor_panel.dart` — Add sidechain dropdown

**Files Created:**
- `crates/rf-engine/src/ffi_sidechain.rs` (~100 LOC Rust)
- `widgets/lower_zone/daw/process/sidechain_selector_widget.dart` (~150 LOC)

**Files Modified:**
- `crates/rf-engine/src/ffi.rs` — Export sidechain functions
- `native_ffi.dart` — Add Dart bindings
- `fabfilter/fabfilter_compressor_panel.dart` — Integrate widget

**Definition of Done:**
- ✅ FFI functions implemented (Rust)
- ✅ Dart bindings added
- ✅ UI widget created
- ✅ Integrated in Comp panel
- ✅ Sidechain EQ controls working
- ✅ Manual test: Kick drum sidechaining bass

---

### P0.6: Fix FX Chain Reorder Not Updating Audio

**Problem:** Drag-drop processor reorder works in UI but audio doesn't update
**Impact:** Users hear wrong signal chain order
**Effort:** 1 day
**Assigned To:** Engine Architect

**Root Cause:** `DspChainProvider.swapNodes()` updates `sortIndex` but doesn't notify engine.

**Fix:**

**File:** `flutter_ui/lib/providers/dsp_chain_provider.dart`

**Current Code:**
```dart
void swapNodes(int trackId, String nodeIdA, String nodeIdB) {
  final chain = _chains[trackId];
  if (chain == null) return;

  final nodeA = chain.nodes.firstWhere((n) => n.id == nodeIdA);
  final nodeB = chain.nodes.firstWhere((n) => n.id == nodeIdB);

  // Swap sortIndex
  final tempIndex = nodeA.sortIndex;
  nodeA.sortIndex = nodeB.sortIndex;
  nodeB.sortIndex = tempIndex;

  // Re-sort
  chain.nodes.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  notifyListeners(); // ❌ Only updates UI, not engine!
}
```

**Fixed Code:**
```dart
void swapNodes(int trackId, String nodeIdA, String nodeIdB) {
  final chain = _chains[trackId];
  if (chain == null) return;

  final nodeA = chain.nodes.firstWhere((n) => n.id == nodeIdA);
  final nodeB = chain.nodes.firstWhere((n) => n.id == nodeIdB);

  // Swap sortIndex
  final tempIndex = nodeA.sortIndex;
  nodeA.sortIndex = nodeB.sortIndex;
  nodeB.sortIndex = tempIndex;

  // Re-sort
  chain.nodes.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  // ✅ Notify engine of new chain order
  _syncChainToEngine(trackId, chain);

  notifyListeners();
}

void _syncChainToEngine(int trackId, DspChain chain) {
  // Clear all slots first
  for (int i = 0; i < 8; i++) {
    NativeFFI.instance.insertUnload(trackId, i);
  }

  // Reload in new order
  for (int i = 0; i < chain.nodes.length; i++) {
    final node = chain.nodes[i];
    NativeFFI.instance.insertLoadProcessor(
      trackId,
      node.type.toRustString(),
      i, // New slot index
    );
    // Restore parameters
    _restoreNodeParameters(trackId, i, node);
  }
}

void _restoreNodeParameters(int trackId, int slotIndex, DspNode node) {
  // Restore all parameters from node.parameters map
  for (final entry in node.parameters.entries) {
    NativeFFI.instance.insertSetParam(
      trackId, slotIndex, entry.key, entry.value
    );
  }
}
```

**Files Modified:**
- `flutter_ui/lib/providers/dsp_chain_provider.dart` — Add `_syncChainToEngine()`

**Definition of Done:**
- ✅ Drag-drop reorder updates audio immediately
- ✅ Parameters preserved after reorder
- ✅ No audio glitches during reorder
- ✅ Manual test: Reorder EQ → Comp → Limiter, hear difference

---

### P0.7: Add Error Boundary Pattern

**Problem:** No graceful degradation when providers fail
**Impact:** App crashes instead of showing error UI
**Effort:** 2 days
**Assigned To:** Technical Director

**Implementation:**

**File:** `flutter_ui/lib/widgets/common/error_boundary.dart` (~200 LOC)

```dart
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace stackTrace)? fallbackBuilder;
  final void Function(Object error, StackTrace stackTrace)? onError;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallbackBuilder,
    this.onError,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    FlutterError.onError = (details) {
      setState(() {
        _error = details.exception;
        _stackTrace = details.stack;
      });
      widget.onError?.call(details.exception, details.stack ?? StackTrace.empty);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.fallbackBuilder?.call(_error!, _stackTrace!) ??
          _buildDefaultFallback();
    }
    return widget.child;
  }

  Widget _buildDefaultFallback() {
    return Container(
      padding: EdgeInsets.all(16),
      color: LowerZoneColors.bgDeep,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: LowerZoneColors.error),
          SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: TextStyle(fontSize: 16, color: LowerZoneColors.textPrimary),
          ),
          SizedBox(height: 8),
          Text(
            _error.toString(),
            style: TextStyle(fontSize: 12, color: LowerZoneColors.textMuted),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _error = null;
                _stackTrace = null;
              });
            },
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }
}
```

**Usage:**
```dart
// In daw_lower_zone_widget.dart
ErrorBoundary(
  child: _buildContentPanel(),
  fallbackBuilder: (error, stack) {
    return _buildErrorPanel(
      title: 'Panel Error',
      message: 'Failed to load ${controller.superTab.label} panel',
      error: error,
    );
  },
  onError: (error, stack) {
    debugPrint('ErrorBoundary caught: $error\n$stack');
    // Optional: Send to crash reporting service
  },
)
```

**Files Created:**
- `flutter_ui/lib/widgets/common/error_boundary.dart` (~200 LOC)

**Files Modified:**
- All 20 panel files — Wrap in ErrorBoundary

**Definition of Done:**
- ✅ ErrorBoundary widget implemented
- ✅ Default fallback UI
- ✅ Retry button functional
- ✅ All panels wrapped
- ✅ Manual test: Kill provider, see error UI instead of crash

---

### P0.8: Standardize Provider Access Pattern

**Problem:** Inconsistent use of `context.watch()`, `context.read()`, `ListenableBuilder`
**Impact:** Confusing for developers, unnecessary rebuilds
**Effort:** 2 days
**Assigned To:** Technical Director

**Implementation:**

**Documentation:** Create `.claude/guides/PROVIDER_ACCESS_PATTERN.md`

**Rule:**
```dart
// ═══════════════════════════════════════════════════════════════════
// PROVIDER ACCESS PATTERN — Standard for FluxForge Studio
// ═══════════════════════════════════════════════════════════════════

// 1. READ-ONLY ACCESS (no rebuild needed)
// Use when: Calling a method, no UI dependency on provider state
final mixer = context.read<MixerProvider>();
mixer.createChannel(name: 'Audio 1');

// 2. REACTIVE ACCESS (rebuild when provider changes)
// Use when: Displaying provider data in UI
final mixer = context.watch<MixerProvider>();
return Text('Channels: ${mixer.channels.length}');

// 3. SELECTIVE LISTENING (rebuild only when specific field changes)
// Use when: Large provider, only care about one field
final channels = context.select<MixerProvider, List<Channel>>(
  (provider) => provider.channels,
);
return ListView.builder(itemCount: channels.length, ...);

// 4. LISTENABLE BUILDER (rebuild when specific Listenable changes)
// Use when: Provider doesn't extend ChangeNotifier, or want manual control
ListenableBuilder(
  listenable: DspChainProvider.instance,
  builder: (context, _) {
    final chain = DspChainProvider.instance.getChain(trackId);
    return _buildChainView(chain);
  },
)

// ═══════════════════════════════════════════════════════════════════
// ANTI-PATTERNS (DO NOT USE)
// ═══════════════════════════════════════════════════════════════════

// ❌ BAD: Using watch() for method calls (causes unnecessary rebuild)
final mixer = context.watch<MixerProvider>();
mixer.createChannel(name: 'Audio 1'); // Should be read()

// ❌ BAD: Using read() for UI display (won't rebuild)
final mixer = context.read<MixerProvider>();
return Text('Channels: ${mixer.channels.length}'); // Should be watch()

// ❌ BAD: Multiple watch() calls in same widget (causes multiple rebuilds)
final mixer = context.watch<MixerProvider>();
final dsp = context.watch<DspChainProvider>();
// Should use Consumer2 or select()
```

**Refactoring:**

**Example 1: Mixer Panel**
```dart
// BEFORE (inconsistent)
Widget _buildMixerPanel() {
  MixerProvider? mixerProvider;
  try {
    mixerProvider = context.watch<MixerProvider>();
  } catch (_) {
    return _buildNoProviderPanel();
  }
  // ... uses mixerProvider
}

// AFTER (standard pattern)
Widget _buildMixerPanel() {
  return Consumer<MixerProvider>(
    builder: (context, mixer, _) {
      return _buildMixerContent(mixer);
    },
  );
}
```

**Example 2: FX Chain Panel**
```dart
// BEFORE (ListenableBuilder every time)
ListenableBuilder(
  listenable: DspChainProvider.instance,
  builder: (context, _) {
    final chain = DspChainProvider.instance.getChain(trackId);
    // ...
  },
)

// AFTER (consistent with Provider pattern)
// Option 1: If DspChainProvider extends ChangeNotifier
final chain = context.select<DspChainProvider, DspChain?>(
  (provider) => provider.getChain(trackId),
);

// Option 2: Keep ListenableBuilder if it doesn't extend ChangeNotifier
// (Current implementation is fine, just document why)
```

**Files Modified:**
- All 20 panel files — Standardize provider access
- Add comments explaining pattern choice

**Files Created:**
- `.claude/guides/PROVIDER_ACCESS_PATTERN.md` (~300 LOC)

**Definition of Done:**
- ✅ Guide document created
- ✅ All panels use standard pattern
- ✅ Comments explain pattern choice
- ✅ No unnecessary rebuilds (verify with DevTools)
- ✅ Code review checklist updated

---

## 🟡 P1 — HIGH PRIORITY (Essential for Professional Use)

### P1.1: Add Workspace Presets

**Problem:** No way to save/load panel layout preferences
**Effort:** 3 days
**Assigned To:** UI/UX Expert

**Implementation:**

**Model:**
```dart
class WorkspacePreset {
  final String id;
  final String name;
  final DawSuperTab superTab;
  final int subTabIndex;
  final double height;
  final bool isExpanded;
  final bool isBuiltIn;

  static const builtInPresets = [
    WorkspacePreset(
      id: 'mixing',
      name: 'Mixing',
      superTab: DawSuperTab.mix,
      subTabIndex: 0, // Mixer
      height: 500.0,
      isBuiltIn: true,
    ),
    WorkspacePreset(
      id: 'mastering',
      name: 'Mastering',
      superTab: DawSuperTab.process,
      subTabIndex: 2, // Limiter
      height: 400.0,
      isBuiltIn: true,
    ),
    WorkspacePreset(
      id: 'editing',
      name: 'Editing',
      superTab: DawSuperTab.edit,
      subTabIndex: 1, // Piano Roll
      height: 500.0,
      isBuiltIn: true,
    ),
    WorkspacePreset(
      id: 'tracking',
      name: 'Tracking',
      superTab: DawSuperTab.browse,
      subTabIndex: 0, // Files
      height: 350.0,
      isBuiltIn: true,
    ),
  ];
}
```

**Service:**
```dart
// services/workspace_preset_service.dart
class WorkspacePresetService {
  static final instance = WorkspacePresetService._();
  final _prefs = SharedPreferences.instance;

  List<WorkspacePreset> get presets {
    final custom = _loadCustomPresets();
    return [...WorkspacePreset.builtInPresets, ...custom];
  }

  Future<void> savePreset(WorkspacePreset preset) async {
    final custom = _loadCustomPresets();
    custom.add(preset);
    await _prefs.setString('workspace_presets', jsonEncode(custom));
  }

  Future<void> deletePreset(String id) async {
    final custom = _loadCustomPresets();
    custom.removeWhere((p) => p.id == id);
    await _prefs.setString('workspace_presets', jsonEncode(custom));
  }

  Future<void> applyPreset(
    WorkspacePreset preset,
    DawLowerZoneController controller,
  ) async {
    controller.setSuperTab(preset.superTab);
    controller.setSubTabIndex(preset.subTabIndex);
    controller.setHeight(preset.height);
    if (!preset.isExpanded) {
      controller.collapse();
    } else {
      controller.expand();
    }
  }
}
```

**UI:** Dropdown in Context Bar (left of super-tabs)

**Files Created:**
- `flutter_ui/lib/services/workspace_preset_service.dart` (~250 LOC)
- `flutter_ui/lib/widgets/lower_zone/workspace_preset_dropdown.dart` (~200 LOC)

**Files Modified:**
- `lower_zone_context_bar.dart` — Add preset dropdown

**Definition of Done:**
- ✅ 4 built-in presets
- ✅ Save custom preset
- ✅ Delete custom preset
- ✅ Apply preset (1-click)
- ✅ Persist to SharedPreferences

---

### P1.2: Add Command Palette (Cmd+K)

**Problem:** No quick panel access (must remember keyboard shortcuts)
**Effort:** 2 days
**Assigned To:** UI/UX Expert

**Implementation:**

**Widget:**
```dart
// widgets/common/command_palette.dart (~400 LOC)
class CommandPalette extends StatefulWidget {
  final List<Command> commands;

  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (_) => CommandPalette(commands: _getAllCommands(context)),
    );
  }
}

class Command {
  final String label;
  final String? description;
  final IconData? icon;
  final VoidCallback onExecute;
  final List<String> keywords; // For fuzzy search

  Command({
    required this.label,
    this.description,
    this.icon,
    required this.onExecute,
    this.keywords = const [],
  });
}

List<Command> _getAllCommands(BuildContext context) {
  final controller = context.read<DawLowerZoneController>();
  return [
    Command(
      label: 'EQ Panel',
      description: '64-band parametric EQ',
      icon: Icons.equalizer,
      keywords: ['eq', 'equalizer', 'process'],
      onExecute: () {
        controller.setSuperTab(DawSuperTab.process);
        controller.setSubTabIndex(0); // EQ
      },
    ),
    Command(
      label: 'Mixer',
      description: 'Full mixer console',
      icon: Icons.tune,
      keywords: ['mixer', 'faders', 'mix'],
      onExecute: () {
        controller.setSuperTab(DawSuperTab.mix);
        controller.setSubTabIndex(0); // Mixer
      },
    ),
    // ... all 20 panels
  ];
}
```

**Keyboard Shortcut:** Cmd+K (macOS), Ctrl+K (Windows/Linux)

**Integration:**
```dart
// In daw_lower_zone_widget.dart
Focus(
  onKeyEvent: (node, event) {
    if (event is KeyDownEvent) {
      final isCmdK = (event.logicalKey == LogicalKeyboardKey.keyK) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed);
      if (isCmdK) {
        CommandPalette.show(context);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  },
  child: ...,
)
```

**Files Created:**
- `flutter_ui/lib/widgets/common/command_palette.dart` (~400 LOC)

**Files Modified:**
- `daw_lower_zone_widget.dart` — Add keyboard shortcut

**Definition of Done:**
- ✅ Cmd+K opens palette
- ✅ Fuzzy search working
- ✅ All 20 panels accessible
- ✅ Keyboard navigation (arrow keys, Enter)
- ✅ ESC closes palette

---

### P1.3: Add PDC (Plugin Delay Compensation) Indicator

**Problem:** No visibility into latency compensation
**Effort:** 2 days
**Assigned To:** Engine Architect

**Implementation:**

**FFI Already Exists:** `getChannelPdc(trackId)` (assumed)

**If not, add:**
```rust
#[no_mangle]
pub extern "C" fn get_channel_pdc(track_id: u64) -> i64 {
    // Returns PDC delay in samples, or -1 if error
}
```

**UI Location:** MIX → Mixer → Channel strip header

**Widget:**
```dart
// mix/pdc_badge_widget.dart (~100 LOC)
class PdcBadgeWidget extends StatelessWidget {
  final int trackId;

  Widget build(BuildContext context) {
    final pdcSamples = NativeFFI.instance.getChannelPdc(trackId);
    if (pdcSamples <= 0) return SizedBox.shrink();

    return Tooltip(
      message: 'Plugin Delay: $pdcSamples samples',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: LowerZoneColors.warning.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: LowerZoneColors.warning, width: 1),
        ),
        child: Text(
          'PDC $pdcSamples',
          style: TextStyle(
            fontSize: 8,
            color: LowerZoneColors.warning,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
```

**Integration:**
```dart
// mix/mixer_panel.dart or UltimateMixer
// In channel strip header:
Row(
  children: [
    Text(channel.name),
    Spacer(),
    PdcBadgeWidget(trackId: channel.id),
  ],
)
```

**Files Created:**
- `widgets/lower_zone/daw/mix/pdc_badge_widget.dart` (~100 LOC)

**Files Modified:**
- `mix/mixer_panel.dart` — Integrate badge
- OR `widgets/mixer/ultimate_mixer.dart` — Add to channel strip

**Definition of Done:**
- ✅ PDC badge displays on channels with latency
- ✅ Tooltip shows sample count
- ✅ Updates when plugins added/removed
- ✅ Color-coded (yellow warning)

---

### P1.4: Add Tab Hover Tooltips

**Problem:** No context for new users on what tabs do
**Effort:** 1 day
**Assigned To:** UI/UX Expert

**Implementation:**

**Tooltip Descriptions:**
```dart
const tabTooltips = {
  // BROWSE
  DawBrowseSubTab.files: 'Audio file browser with hover preview and drag-drop import',
  DawBrowseSubTab.presets: 'Track preset library with 10 factory presets (Vocals, Guitar, Drums, etc.)',
  DawBrowseSubTab.plugins: 'VST3/AU/CLAP plugin scanner with format filter',
  DawBrowseSubTab.history: 'Undo/redo history stack with 100-item limit',

  // EDIT
  DawEditSubTab.timeline: 'Track arrangement view with clip positions and routing',
  DawEditSubTab.pianoRoll: 'MIDI editor with 128 notes, velocity, and CC automation',
  DawEditSubTab.fades: 'Crossfade curve editor (Equal Power, Linear, S-Curve)',
  DawEditSubTab.grid: 'Snap-to-grid settings, tempo (40-240 BPM), time signature',

  // MIX
  DawMixSubTab.mixer: 'Full mixer console with faders, meters, sends, and inserts',
  DawMixSubTab.sends: 'Track→Bus routing matrix with send level controls',
  DawMixSubTab.pan: 'Stereo panning controls with pan law selection (0/-3/-4.5/-6dB)',
  DawMixSubTab.automation: 'Automation curve editor with draw/erase tools',

  // PROCESS
  DawProcessSubTab.eq: '64-band parametric EQ with GPU spectrum analyzer (60fps)',
  DawProcessSubTab.comp: 'Pro-C style compressor with 14 styles and sidechain',
  DawProcessSubTab.limiter: 'Pro-L style limiter with True Peak and LUFS metering',
  DawProcessSubTab.fxChain: 'Visual DSP chain with drag-drop reorder and bypass',

  // DELIVER
  DawDeliverSubTab.export: 'Quick export with last settings (WAV/FLAC/MP3, LUFS normalize)',
  DawDeliverSubTab.stems: 'Export individual tracks/buses as stems (batch export)',
  DawDeliverSubTab.bounce: 'Master bounce with format/sample rate/normalize options',
  DawDeliverSubTab.archive: 'ZIP project with audio/presets/plugins (optional compression)',
};
```

**Integration:**
```dart
// lower_zone_context_bar.dart
// In _buildSubTabs():
for (int i = 0; i < subTabLabels.length; i++) {
  final tooltip = _getTooltipForSubTab(selectedSuperTab, i);
  widgets.add(
    Tooltip(
      message: tooltip,
      waitDuration: Duration(milliseconds: 500),
      child: _buildSubTabButton(subTabLabels[i], i == selectedSubTab),
    ),
  );
}
```

**Files Modified:**
- `lower_zone_context_bar.dart` — Add tooltips

**Definition of Done:**
- ✅ All 20 sub-tabs have tooltips
- ✅ 500ms hover delay
- ✅ Tooltips descriptive (not just tab name)
- ✅ Manual test: Hover all tabs, read tooltips

---

### P1.5: Add Recent Tabs Quick Access

**Problem:** Must click super-tab + sub-tab every time (2 clicks)
**Effort:** 2 days
**Assigned To:** UI/UX Expert

**Implementation:**

**Controller Addition:**
```dart
// daw_lower_zone_controller.dart
class DawLowerZoneController extends ChangeNotifier {
  final List<_TabState> _recentTabs = [];

  void _recordRecentTab() {
    final current = _TabState(superTab, currentSubTabIndex);
    _recentTabs.remove(current); // Remove if exists
    _recentTabs.insert(0, current); // Add to front
    if (_recentTabs.length > 5) {
      _recentTabs.removeLast(); // Keep only 5 recent
    }
  }

  @override
  void setSuperTab(DawSuperTab tab) {
    super.setSuperTab(tab);
    _recordRecentTab();
  }

  List<_TabState> get recentTabs => _recentTabs.take(3).toList();
}

class _TabState {
  final DawSuperTab superTab;
  final int subTabIndex;
  // ...
}
```

**UI:** Context bar → Far right corner

**Widget:**
```dart
// In lower_zone_context_bar.dart
Row(
  children: [
    _buildSuperTabs(),
    Spacer(),
    _buildRecentTabsQuickAccess(), // NEW
  ],
)

Widget _buildRecentTabsQuickAccess() {
  return Row(
    children: controller.recentTabs.map((tabState) {
      final config = _getConfigForTabState(tabState);
      return IconButton(
        icon: Icon(config.icon, size: 14),
        onPressed: () {
          controller.setSuperTab(tabState.superTab);
          controller.setSubTabIndex(tabState.subTabIndex);
        },
        tooltip: 'Recent: ${config.label}',
      );
    }).toList(),
  );
}
```

**Files Modified:**
- `daw_lower_zone_controller.dart` — Add recent tabs tracking
- `lower_zone_context_bar.dart` — Add quick access UI

**Definition of Done:**
- ✅ Last 3 tabs displayed
- ✅ Click to instantly switch
- ✅ Tooltips show tab names
- ✅ Updates when switching tabs

---

### P1.6: Add Dynamic EQ Mode

**Problem:** No threshold-based EQ (de-essing, masking reduction)
**Effort:** 1 week
**Assigned To:** DSP Engineer

**Implementation:**

**FFI Addition:**
```rust
// crates/rf-dsp/src/eq/dynamic_eq.rs (~500 LOC)
pub struct DynamicEqBand {
    pub band: BiquadTDF2,
    pub threshold_db: f64,
    pub ratio: f64,
    pub attack_ms: f64,
    pub release_ms: f64,
    envelope_follower: EnvelopeFollower,
}

impl DynamicEqBand {
    pub fn process(&mut self, input: f64) -> f64 {
        let eq_out = self.band.process(input);
        let envelope = self.envelope_follower.process(input);

        if envelope > self.threshold_db {
            // Apply gain reduction
            let over_db = envelope - self.threshold_db;
            let gr_db = over_db * (1.0 - 1.0 / self.ratio);
            let gr_linear = db_to_linear(-gr_db);
            eq_out * gr_linear
        } else {
            eq_out
        }
    }
}

// FFI exports
#[no_mangle]
pub extern "C" fn eq_set_band_dynamic(
    track_id: u64,
    band_index: u64,
    threshold_db: f64,
    ratio: f64,
    attack_ms: f64,
    release_ms: f64,
) -> i32
```

**Dart Binding:**
```dart
int eqSetBandDynamic(
  int trackId,
  int bandIndex,
  double thresholdDb,
  double ratio,
  double attackMs,
  double releaseMs,
) {
  return _dylib.lookupFunction<...>('eq_set_band_dynamic')(...);
}
```

**UI:** PROCESS → EQ → Per-band toggle "Dynamic"

**Widget:**
```dart
// When band.isDynamic == true, show:
Column(
  children: [
    _buildSlider('Threshold', -60.0, 0.0, band.dynamicThreshold, (v) {
      NativeFFI.instance.eqSetBandDynamic(trackId, bandIndex, v, ...);
    }),
    _buildSlider('Ratio', 1.0, 10.0, band.dynamicRatio, ...),
    _buildSlider('Attack', 0.1, 100.0, band.dynamicAttack, ...),
    _buildSlider('Release', 10.0, 1000.0, band.dynamicRelease, ...),
  ],
)
```

**Files Created:**
- `crates/rf-dsp/src/eq/dynamic_eq.rs` (~500 LOC Rust)
- `crates/rf-bridge/src/eq_ffi.rs` — Dynamic EQ exports

**Files Modified:**
- `native_ffi.dart` — Add Dart bindings
- `fabfilter/fabfilter_eq_panel.dart` — Add Dynamic toggle + controls

**Definition of Done:**
- ✅ Rust dynamic EQ implementation
- ✅ FFI exports + Dart bindings
- ✅ UI toggle per band
- ✅ Dynamic controls (threshold, ratio, attack, release)
- ✅ Manual test: De-essing on vocal track

---

### P1.7-P1.15: See Full List in `.claude/tasks/DAW_LOWER_ZONE_TODO_2026_01_26.md`

(Remaining P1 tasks omitted for brevity, see full document)

---

## 🟠 P2 — MEDIUM PRIORITY (Quality of Life)

### P2.1: Add Split View Mode

**Problem:** Cannot view 2 panels simultaneously
**Effort:** 1 week
**Assigned To:** UI/UX Expert

### P2.2: Add GPU Spectrum Shader

**Problem:** CPU-only spectrum rendering (performance hit on 4K displays)
**Effort:** 2 weeks
**Assigned To:** Graphics Engineer

### P2.3: Add Multiband Compressor Panel

**Problem:** Only single-band compressor available
**Effort:** 2 weeks
**Assigned To:** DSP Engineer

### P2.4-P2.17: See Full List in Document

(Remaining P2 tasks omitted for brevity)

---

## 🔵 P3 — LOW PRIORITY (Nice to Have)

### P3.1: Add Audio Settings Panel

**Problem:** Buffer size/sample rate not configurable from UI
**Effort:** 3 days

### P3.2: Add CPU Usage Meter per Processor

**Problem:** No visibility into which processor uses most CPU
**Effort:** 4 days

### P3.3-P3.7: See Full List in Document

---

## 📊 Milestone Roadmap

### Milestone 1: Foundation (P0 Tasks) — 6-8 Weeks

**Goal:** Production-ready foundation

| Task | Effort | Blocking |
|------|--------|----------|
| P0.1: Split Single File | 2-3 weeks | ✅ Blocks all |
| P0.2: Real-Time LUFS | 3-4 days | — |
| P0.3: Input Validation | 2 days | — |
| P0.4: Unit Tests | 1 week | After P0.1 |
| P0.5: Sidechain UI | 3 days | — |
| P0.6: FX Chain Fix | 1 day | — |
| P0.7: Error Boundary | 2 days | — |
| P0.8: Provider Pattern | 2 days | After P0.1 |

**Deliverable:** Stable, maintainable, secure DAW Lower Zone

---

### Milestone 2: Professional Features (P1 Tasks) — 6 Weeks

**Goal:** Essential professional features

| Task | Effort | Depends On |
|------|--------|------------|
| P1.1: Workspace Presets | 3 days | P0.1 |
| P1.2: Command Palette | 2 days | — |
| P1.3: PDC Indicator | 2 days | — |
| P1.4: Tab Tooltips | 1 day | — |
| P1.5: Recent Tabs | 2 days | — |
| P1.6: Dynamic EQ | 1 week | — |

**Deliverable:** Pro Tools / Logic Pro level UX

---

### Milestone 3: Advanced Features (P2 Tasks) — 8 Weeks

**Goal:** Industry-leading capabilities

| Task | Effort |
|------|--------|
| P2.1: Split View | 1 week |
| P2.2: GPU Spectrum | 2 weeks |
| P2.3: Multiband Comp | 2 weeks |

**Deliverable:** Best-in-class DAW Lower Zone

---

### Milestone 4: Polish (P3 Tasks) — 4 Weeks

**Goal:** Nice-to-have improvements

**Deliverable:** Complete feature set

---

## 📈 Dependency Graph

```
P0.1 (Split File) ───┬──→ P0.4 (Tests)
                     ├──→ P0.8 (Provider Pattern)
                     ├──→ P1.1 (Presets)
                     └──→ All refactoring tasks

P0.2 (LUFS) ─────────────→ P2.10 (Mastering Preset)

P0.5 (Sidechain) ────────→ P1.6 (Dynamic EQ)
                         └→ P2.3 (Multiband Comp)

P0.6 (FX Chain Fix) ─────→ P2.1 (Split View)

P1.6 (Dynamic EQ) ───────→ P2.3 (Multiband Comp)

P2.2 (GPU Spectrum) ─────→ P3.5 (Waterfall Display)
```

---

## ✅ Definition of Done (Global)

For ALL tasks:

- ✅ Code implements feature fully
- ✅ `flutter analyze` passes (0 errors)
- ✅ Manual testing completed
- ✅ Documentation updated (if architectural change)
- ✅ No regressions (existing features still work)
- ✅ Code review approved (if team workflow)

For P0/P1 tasks:
- ✅ Unit tests written (if applicable)
- ✅ Integration tests written (if workflow change)

---

## 📝 Notes

**File Organization:**
- This TODO is living document
- Update status as tasks complete
- Move completed tasks to `.claude/tasks/completed/`

**Estimation Accuracy:**
- Estimates based on 1 full-time developer
- Includes implementation + testing + documentation
- Add 20% buffer for unknowns

**Prioritization Rationale:**
- P0: Production blockers (crashes, security, maintenance)
- P1: Professional must-haves (UX, essential features)
- P2: Competitive advantages (advanced features)
- P3: Nice-to-haves (polish, edge cases)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-26
**Next Review:** After Milestone 1 completion

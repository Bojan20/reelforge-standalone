# Lower Zone Implementation — Complete Documentation

> **Version:** 1.1
> **Date:** 2026-01-22
> **Status:** FULLY IMPLEMENTED
> **Last Update:** UltimateMixer integration (replaced ProDawMixer)

---

## 1. OVERVIEW

Lower Zone je kompletno implementiran za sve tri sekcije FluxForge Studio-a:
- **DAW** — Timeline-based audio production
- **Middleware** — Wwise/FMOD-style event logic
- **SlotLab** — Synthetic slot engine testing

### Statistics

| Metric | Value |
|--------|-------|
| Total Panels | 60 (20 per section × 3 sections) |
| Controllers | 3 (one per section) |
| State Classes | 3 (with full JSON serialization) |
| Custom Painters | 6 (visualization curves) |
| LOC (estimated) | ~8,000 |

---

## 2. FILE STRUCTURE

```
flutter_ui/lib/
├── widgets/lower_zone/
│   ├── lower_zone.dart                      # Barrel export
│   ├── lower_zone_types.dart                # Enums, state, constants (474 lines)
│   ├── lower_zone_context_bar.dart          # Super-tabs + Sub-tabs widget
│   ├── lower_zone_action_strip.dart         # Action strip + predefined actions
│   ├── daw_lower_zone_controller.dart       # DAW controller (252 lines)
│   ├── middleware_lower_zone_controller.dart # Middleware controller (238 lines)
│   ├── slotlab_lower_zone_controller.dart   # SlotLab controller (238 lines)
│   ├── daw_lower_zone_widget.dart           # DAW widget + 20 panels (~640 lines)
│   ├── middleware_lower_zone_widget.dart    # Middleware widget + 20 panels (~1550 lines)
│   └── slotlab_lower_zone_widget.dart       # SlotLab widget + 20 panels (~1620 lines)
│
└── services/
    └── lower_zone_persistence_service.dart  # SharedPreferences persistence (160 lines)
```

---

## 3. TYPE SYSTEM

### 3.1 Enums per Section

**DAW Section:**
```dart
enum DawSuperTab { browse, edit, mix, process, deliver }
enum DawBrowseSubTab { files, presets, plugins, history }
enum DawEditSubTab { timeline, clips, fades, grid }
enum DawMixSubTab { mixer, sends, pan, automation }
enum DawProcessSubTab { eq, comp, limiter, fxChain }
enum DawDeliverSubTab { export, stems, bounce, archive }
```

**Middleware Section:**
```dart
enum MiddlewareSuperTab { events, containers, routing, rtpc, deliver }
enum MiddlewareEventsSubTab { browser, editor, triggers, actions }
enum MiddlewareContainersSubTab { random, sequence, blend, switchTab }
enum MiddlewareRoutingSubTab { buses, ducking, matrix, spatial }
enum MiddlewareRtpcSubTab { curves, bindings, meters, debug }
enum MiddlewareDeliverSubTab { bake, soundbank, validate, package }
```

**SlotLab Section:**
```dart
enum SlotLabSuperTab { stages, events, mix, dsp, bake }
enum SlotLabStagesSubTab { trace, timeline, symbols, timing }
enum SlotLabEventsSubTab { folder, editor, layers, pool }
enum SlotLabMixSubTab { buses, sends, pan, meter }
enum SlotLabDspSubTab { chain, eq, comp, reverb }
enum SlotLabBakeSubTab { export, stems, variations, package }
```

### 3.2 State Classes

Sve state klase imaju:
- Mutable fields za svaki tab
- `isExpanded` i `height` za UI state
- `copyWith()` za immutable updates
- `toJson()` / `fromJson()` za persistence

```dart
class DawLowerZoneState {
  DawSuperTab superTab;
  DawBrowseSubTab browseSubTab;
  DawEditSubTab editSubTab;
  DawMixSubTab mixSubTab;
  DawProcessSubTab processSubTab;
  DawDeliverSubTab deliverSubTab;
  bool isExpanded;
  double height;

  // Computed properties
  int get currentSubTabIndex;
  List<String> get subTabLabels;

  // Mutations
  void setSubTabIndex(int index);

  // Serialization
  Map<String, dynamic> toJson();
  factory DawLowerZoneState.fromJson(Map<String, dynamic> json);
}
```

### 3.3 Constants

```dart
const double kLowerZoneMinHeight = 150.0;
const double kLowerZoneMaxHeight = 600.0;
const double kLowerZoneDefaultHeight = 280.0;
const double kContextBarHeight = 60.0;
const double kActionStripHeight = 36.0;
const Duration kLowerZoneAnimationDuration = Duration(milliseconds: 200);
```

### 3.4 Colors

```dart
class LowerZoneColors {
  // Backgrounds
  static const Color bgDeepest = Color(0xFF0A0A0C);
  static const Color bgDeep = Color(0xFF121216);
  static const Color bgMid = Color(0xFF1A1A20);
  static const Color bgSurface = Color(0xFF242430);

  // Section Accents
  static const Color dawAccent = Color(0xFF4A9EFF);       // Blue
  static const Color middlewareAccent = Color(0xFFFF9040); // Orange
  static const Color slotLabAccent = Color(0xFF40C8FF);    // Cyan

  // Status
  static const Color success = Color(0xFF40FF90);
  static const Color warning = Color(0xFFFFFF40);
  static const Color error = Color(0xFFFF4060);
}
```

---

## 4. CONTROLLERS

### 4.1 Controller Pattern

Svi controlleri extenduju `ChangeNotifier` i imaju:

```dart
class XxxLowerZoneController extends ChangeNotifier {
  XxxLowerZoneState _state;

  // GETTERS
  XxxLowerZoneState get state;
  XxxSuperTab get superTab;
  bool get isExpanded;
  double get height;
  int get currentSubTabIndex;
  List<String> get subTabLabels;
  double get totalHeight;
  Color get accentColor;

  // SUPER-TAB ACTIONS
  void setSuperTab(XxxSuperTab tab);
  void setSuperTabIndex(int index);

  // SUB-TAB ACTIONS
  void setSubTabIndex(int index);
  void setXxxSubTab(XxxYyySubTab tab);  // Type-safe per-tab setters

  // EXPAND/COLLAPSE
  void toggle();
  void expand();
  void collapse();

  // HEIGHT
  void setHeight(double newHeight);
  void adjustHeight(double delta);

  // KEYBOARD SHORTCUTS
  KeyEventResult handleKeyEvent(KeyEvent event);

  // SERIALIZATION
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);

  // PERSISTENCE
  Future<void> loadFromStorage();
  Future<void> saveToStorage();
  void _updateAndSave(XxxLowerZoneState newState);
}
```

### 4.2 Auto-Save Pattern

Sve state mutacije koriste `_updateAndSave()`:

```dart
void _updateAndSave(DawLowerZoneState newState) {
  _state = newState;
  notifyListeners();
  saveToStorage();  // Async, non-blocking
}

void setSuperTab(DawSuperTab tab) {
  if (_state.superTab == tab && _state.isExpanded) {
    _updateAndSave(_state.copyWith(isExpanded: false));
  } else {
    _updateAndSave(_state.copyWith(superTab: tab, isExpanded: true));
  }
}
```

### 4.3 Keyboard Shortcuts

| Key | Action |
|-----|--------|
| ` (backtick) | Toggle expand/collapse |
| 1-5 | Switch super-tab |
| Q, W, E, R | Switch sub-tab (0-3) |

Shortcuts zahtevaju da nema modifier keys (Cmd/Ctrl/Alt/Shift).

---

## 5. PERSISTENCE SERVICE

### 5.1 Service Implementation

```dart
class LowerZonePersistenceService {
  static const String _dawKey = 'lower_zone_daw_state';
  static const String _middlewareKey = 'lower_zone_middleware_state';
  static const String _slotLabKey = 'lower_zone_slotlab_state';

  static LowerZonePersistenceService? _instance;
  static LowerZonePersistenceService get instance;

  SharedPreferences? _prefs;

  Future<void> init();
  Future<SharedPreferences> _getPrefs();

  // Per-section
  Future<bool> saveDawState(DawLowerZoneState state);
  Future<DawLowerZoneState> loadDawState();
  // ... similar for Middleware and SlotLab

  // Batch
  Future<({...})> loadAllStates();
  Future<void> saveAllStates({...});
  Future<void> clearAllStates();
}
```

### 5.2 Initialization

U `main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServiceLocator.init();
  await LowerZonePersistenceService.instance.init();  // <-- Added
  runApp(const FluxForgeApp());
}
```

### 5.3 What Gets Persisted

| Field | Type | Default |
|-------|------|---------|
| superTab | int (index) | Section-specific |
| xxxSubTab (×5) | int (index) | 0 |
| isExpanded | bool | true |
| height | double | 280.0 |

---

## 6. WIDGET IMPLEMENTATIONS

### 6.1 Widget Structure

```dart
class XxxLowerZoneWidget extends StatefulWidget {
  final XxxLowerZoneController controller;
  // Section-specific props (providers, callbacks)

  @override
  State<XxxLowerZoneWidget> createState() => _XxxLowerZoneWidgetState();
}

class _XxxLowerZoneWidgetState extends State<XxxLowerZoneWidget> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return AnimatedContainer(
          duration: kLowerZoneAnimationDuration,
          height: widget.controller.totalHeight,
          child: Column(
            children: [
              _buildContextBar(),
              if (widget.controller.isExpanded) ...[
                _buildResizeHandle(),
                Expanded(child: _buildContent()),
                _buildActionStrip(),
              ],
            ],
          ),
        );
      },
    );
  }
}
```

### 6.2 Content Routing

```dart
Widget _buildContent() {
  return switch (widget.controller.superTab) {
    XxxSuperTab.first => _buildFirstContent(),
    XxxSuperTab.second => _buildSecondContent(),
    // ...
  };
}

Widget _buildFirstContent() {
  final subTab = widget.controller.state.firstSubTab;
  return switch (subTab) {
    XxxFirstSubTab.a => _buildAPanel(),
    XxxFirstSubTab.b => _buildBPanel(),
    // ...
  };
}
```

---

## 7. PANEL IMPLEMENTATIONS

### 7.1 DAW Panels (20)

| Super-Tab | Sub-Tab | Panel | Integration |
|-----------|---------|-------|-------------|
| **BROWSE** | Files | `_buildCompactFilesBrowser()` | Custom folder tree + file list |
| | Presets | `_buildCompactPresetsBrowser()` | Grid of preset cards |
| | Plugins | `_buildCompactPluginsScanner()` | VST3/AU plugin list |
| | History | `_buildCompactHistoryPanel()` | Undo stack with current marker |
| **EDIT** | Timeline | `_buildTimelinePanel()` | Placeholder |
| | Clips | `_buildClipsPanel()` | Placeholder |
| | Fades | `_buildFadesPanel()` | Placeholder |
| | Grid | `_buildGridPanel()` | Placeholder |
| **MIX** | Mixer | `UltimateMixer(compact: true)` | **Full integration** (VCA, stereo pan, sends) |
| | Sends | `_buildCompactSendsPanel()` | 4 aux sends with faders |
| | Pan | `_buildCompactPannerPanel()` | Stereo panner visualization |
| | Automation | `_buildCompactAutomationPanel()` | Curve painter + mode chips |
| **PROCESS** | EQ | `FabFilterEQPanel` | **Full integration** |
| | Comp | `FabFilterCompressorPanel` | **Full integration** |
| | Limiter | `FabFilterLimiterPanel` | **Full integration** |
| | FX Chain | `_buildFxChainPanel()` | Placeholder |
| **DELIVER** | Export | `_buildPlaceholderPanel()` | Placeholder |
| | Stems | `_buildPlaceholderPanel()` | Placeholder |
| | Bounce | `_buildPlaceholderPanel()` | Placeholder |
| | Archive | `_buildPlaceholderPanel()` | Placeholder |

### 7.2 Middleware Panels (20)

| Super-Tab | Sub-Tab | Panel | Integration |
|-----------|---------|-------|-------------|
| **EVENTS** | Browser | `EventsFolderPanel` | **Full integration** |
| | Editor | `EventEditorPanel` | **Full integration** |
| | Triggers | `_buildCompactTriggersPanel()` | Trigger list + condition editor |
| | Actions | `_buildCompactActionsPanel()` | 8 action cards grid |
| **CONTAINERS** | Random | `RandomContainerPanel` | **Full integration** |
| | Sequence | `SequenceContainerPanel` | **Full integration** |
| | Blend | `BlendContainerPanel` | **Full integration** |
| | Switch | `_buildCompactSwitchContainer()` | State selector + sound assignment |
| **ROUTING** | Buses | `BusHierarchyPanel` | **Full integration** |
| | Ducking | `DuckingMatrixPanel` | **Full integration** |
| | Matrix | `_buildCompactRoutingMatrix()` | 4×4 connection matrix |
| | Spatial | `_buildCompactSpatialPanel()` | 4 aux send faders |
| **RTPC** | Curves | `_buildCompactRtpcCurves()` | Curve list + `_RtpcCurvePainter` |
| | Bindings | `_buildCompactBindingsPanel()` | Parameter binding rows |
| | Meters | `_buildCompactMetersPanel()` | 6 real-time meter columns |
| | Debug | `RtpcDebuggerPanel` | **Full integration** |
| **DELIVER** | Bake | `_buildCompactBakePanel()` | Settings + bake button |
| | Soundbank | `_buildCompactSoundbankPanel()` | Bank list with load status |
| | Validate | `_buildCompactValidatePanel()` | Validation results list |
| | Package | `_buildCompactPackagePanel()` | Settings + export button |

### 7.3 SlotLab Panels (20)

| Super-Tab | Sub-Tab | Panel | Integration |
|-----------|---------|-------|-------------|
| **STAGES** | Trace | `StageTraceWidget` | **Full integration** |
| | Timeline | `_buildCompactEventTimeline()` | `_TimelinePainter` |
| | Symbols | `_buildCompactSymbolsPanel()` | 8 symbol cards grid |
| | Timing | `ProfilerPanel` | **Full integration** |
| **EVENTS** | Folder | `_buildCompactEventFolder()` | Folder tree + event list |
| | Editor | `_buildCompactCompositeEditor()` | Layer list editor |
| | Layers | `EventLogPanel` | **Full integration** |
| | Pool | `_buildCompactVoicePool()` | Voice usage bars per bus |
| **MIX** | Buses | `BusHierarchyPanel` | **Full integration** |
| | Sends | `AuxSendsPanel` | **Full integration** |
| | Pan | `_buildCompactPanPanel()` | 4 channel pan widgets |
| | Meter | `_buildCompactMeterPanel()` | 5 stereo meter pairs |
| **DSP** | Chain | `_buildCompactDspChain()` | Signal flow nodes |
| | EQ | `_buildCompactEqPanel()` | `_EqCurvePainter` |
| | Comp | `_buildCompactCompressorPanel()` | 4 knobs + meter |
| | Reverb | `_buildCompactReverbPanel()` | 4 knobs + `_ReverbDecayPainter` |
| **BAKE** | Export | `_buildCompactExportPanel()` | Settings + export button |
| | Stems | `_buildCompactStemsPanel()` | Checkbox list |
| | Variations | `_buildCompactVariationsPanel()` | Pitch/Vol/Pan sliders |
| | Package | `_buildCompactPackagePanel()` | Settings + package button |

---

## 8. CUSTOM PAINTERS

### 8.1 DAW Painters

**`_AutomationCurvePainter`:**
- Draws cubic bezier automation curve
- Fill gradient under curve
- Control points as circles
- Used in: DAW MIX > Automation

### 8.2 Middleware Painters

**`_RtpcCurvePainter`:**
- Draws exponential decay RTPC curve
- Grid lines (4×4)
- Control points
- Fill gradient
- Used in: Middleware RTPC > Curves

### 8.3 SlotLab Painters

**`_TimelinePainter`:**
- Draws vertical grid lines
- Stage blocks as rounded rectangles
- 5 sample stages: SPIN, REEL, STOP, EVAL, WIN
- Used in: SlotLab STAGES > Timeline

**`_EqCurvePainter`:**
- Draws multi-band EQ curve
- Low shelf boost, 200Hz dip, 3kHz boost, high shelf
- 4 band points as circles
- Center line at 0dB
- Used in: SlotLab DSP > EQ

**`_ReverbDecayPainter`:**
- Draws exponential reverb decay
- Fill gradient
- Mathematical decay: `y = 0.1 + 0.85 * (1 - 1/(1 + 2t²))`
- Used in: SlotLab DSP > Reverb

---

## 9. HELPER METHODS

### 9.1 Common Builders

```dart
// Panel header with icon and title
Widget _buildPanelHeader(String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 16, color: LowerZoneColors.xxxAccent),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: LowerZoneColors.xxxAccent,
        letterSpacing: 1.0,
      )),
    ],
  );
}

// Placeholder for unimplemented panels
Widget _buildPlaceholderPanel(String title, IconData icon) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: LowerZoneColors.textMuted),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(...)),
        Text('Coming soon', style: TextStyle(...)),
      ],
    ),
  );
}

// For panels requiring unavailable provider
Widget _buildNoProviderPanel(String title, IconData icon, String providerName) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: LowerZoneColors.textMuted.withOpacity(0.5)),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(...)),
        Text('Requires $providerName', style: TextStyle(...)),
      ],
    ),
  );
}
```

### 9.2 Provider Access

```dart
SlotLabProvider? _tryGetSlotLabProvider() {
  try {
    return context.read<SlotLabProvider>();
  } catch (_) {
    return null;
  }
}

MiddlewareProvider? _tryGetMiddlewareProvider() {
  try {
    return context.read<MiddlewareProvider>();
  } catch (_) {
    return null;
  }
}
```

---

## 10. INTEGRATION POINTS

### 10.1 Integrated Existing Panels

| Panel | Source | Used In |
|-------|--------|---------|
| `UltimateMixer` | `widgets/mixer/ultimate_mixer.dart` | DAW MIX > Mixer (replaced ProDawMixer) |
| `FabFilterEQPanel` | `widgets/fabfilter/` | DAW PROCESS > EQ |
| `FabFilterCompressorPanel` | `widgets/fabfilter/` | DAW PROCESS > Comp |
| `FabFilterLimiterPanel` | `widgets/fabfilter/` | DAW PROCESS > Limiter |
| `EventsFolderPanel` | `widgets/middleware/` | Middleware EVENTS > Browser |
| `EventEditorPanel` | `widgets/middleware/` | Middleware EVENTS > Editor |
| `RandomContainerPanel` | `widgets/middleware/` | Middleware CONTAINERS > Random |
| `SequenceContainerPanel` | `widgets/middleware/` | Middleware CONTAINERS > Sequence |
| `BlendContainerPanel` | `widgets/middleware/` | Middleware CONTAINERS > Blend |
| `BusHierarchyPanel` | `widgets/middleware/` | Middleware ROUTING > Buses, SlotLab MIX > Buses |
| `DuckingMatrixPanel` | `widgets/middleware/` | Middleware ROUTING > Ducking |
| `RtpcDebuggerPanel` | `widgets/middleware/` | Middleware RTPC > Debug |
| `StageTraceWidget` | `widgets/slot_lab/` | SlotLab STAGES > Trace |
| `EventLogPanel` | `widgets/slot_lab/` | SlotLab EVENTS > Layers |
| `ProfilerPanel` | `widgets/slot_lab/` | SlotLab STAGES > Timing |
| `AuxSendsPanel` | `widgets/slot_lab/` | SlotLab MIX > Sends |

### 10.2 Provider Dependencies

| Panel | Required Provider |
|-------|-------------------|
| ProDawMixer | `MixerProvider` |
| StageTraceWidget | `SlotLabProvider` |
| EventLogPanel | `SlotLabProvider`, `MiddlewareProvider` |

---

## 11. ACTION STRIP

### 11.1 Predefined Actions

**DAW Actions:**
```dart
class DawActions {
  static List<LowerZoneAction> forBrowse() => [
    LowerZoneAction(icon: Icons.add, label: 'Add', onPressed: () {}),
    LowerZoneAction(icon: Icons.delete, label: 'Delete', onPressed: () {}),
    // ...
  ];
  // forEdit(), forMix(), forProcess(), forDeliver()
}
```

**Middleware Actions:** `MiddlewareActions`
**SlotLab Actions:** `SlotLabActions`

### 11.2 Status Text

Dinamički generisan na osnovu trenutnog stanja:
- DAW: "Selected track: --" ili track name
- Middleware: "Events: X" count
- SlotLab: "Stages: X" count

---

## 12. USAGE EXAMPLE

```dart
class DawScreen extends StatefulWidget {
  @override
  State<DawScreen> createState() => _DawScreenState();
}

class _DawScreenState extends State<DawScreen> {
  late DawLowerZoneController _lowerZoneController;

  @override
  void initState() {
    super.initState();
    _lowerZoneController = DawLowerZoneController();
    _lowerZoneController.loadFromStorage();  // Restore last session
  }

  @override
  void dispose() {
    _lowerZoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: DawMainContent()),
        DawLowerZoneWidget(
          controller: _lowerZoneController,
          selectedTrackId: _currentTrackId,
        ),
      ],
    );
  }
}
```

---

## 13. TESTING CHECKLIST

### 13.1 Flutter Analyze
```bash
cd flutter_ui && flutter analyze
# Expected: No issues found!
```

### 13.2 Manual Testing

- [ ] DAW: All 5 super-tabs switch correctly
- [ ] DAW: All 20 sub-tabs display content
- [ ] DAW: Expand/collapse works
- [ ] DAW: Height resize works
- [ ] DAW: Keyboard shortcuts work
- [ ] DAW: State persists across restarts
- [ ] Middleware: Same as above
- [ ] SlotLab: Same as above
- [ ] Integrated panels render without errors
- [ ] Custom painters render correctly

---

## 14. FUTURE IMPROVEMENTS

### 14.1 Planned
- Connect placeholder panels to actual functionality
- Add drag-and-drop for file browser
- Add real-time metering updates
- Add preset save/load for DSP panels

### 14.2 Optional Enhancements
- Animated tab transitions
- Panel pinning/floating
- Custom panel arrangements
- Multi-monitor support

---

**Document Status:** COMPLETE
**Last Updated:** 2026-01-22

# AutoSpatial UI Panel — Implementation Plan

## Status: ✅ COMPLETED (2026-01-22)

## Goal

Create a comprehensive UI panel for configuring and monitoring the AutoSpatialEngine.

## Existing Infrastructure

- **Engine**: `flutter_ui/lib/spatial/auto_spatial.dart` (2,296 LOC, fully implemented)
- **30+ Intent Rules**: `SlotIntentRules.defaults` (pre-defined for slots)
- **Bus Policies**: Per-bus spatial modifiers (UI, reels, sfx, vo, music, ambience)
- **Event Tracking**: Object-pooled EventTrackerPool with Kalman filtering
- **Anchor Registry**: UI element position tracking

## Implemented Features

### Tab 1: Intent Rules Editor ✅
- List all intent rules with search/filter
- Per-rule configuration:
  - Fusion weights (wAnchor, wMotion, wIntent)
  - Panning (width, deadzone, maxPan)
  - Smoothing (tauMs)
  - Distance model & rolloff
  - Doppler (enable, scale)
  - LPF mapping (yToLPF, distanceToLPF)
  - Reverb (baseLevel, distanceScale)
  - Easing function (13 options)
- Create/duplicate/delete rules
- Export/import as JSON

### Tab 2: Bus Policies Editor ✅
- 6 bus types: UI, reels, sfx, vo, music, ambience
- Per-bus modifiers:
  - widthMul, maxPanMul, tauMul
  - reverbMul, dopplerMul
  - enableHRTF, priorityBoost
- Visual preview with CustomPaint

### Tab 3: Anchor Monitor (Real-time) ✅
- Visual representation of registered anchors
- Position, size, velocity indicators
- Confidence levels
- Last update timestamps
- Test anchor creation (Center, corners, Reel 1-5)

### Tab 4: Engine Stats & Config ✅
- Stats display (activeEvents, pool utilization, processing time, events/sec, dropped, rate-limited)
- Config toggles (Doppler, distance attenuation, occlusion, reverb, HRTF, frequency absorption)
- Listener position controls (x, y, z, rotation)
- Render mode selector (Stereo, Binaural, FOA, HOA, Atmos)
- Global pan/width scales

### Tab 5: Live Event Visualizer ✅
- Real-time 2D radar view of active events
- Pan/width/distance/doppler indicators
- Color-coded by bus type
- Click-to-inspect event details
- Pan meter aggregate
- Test event buttons (Spin Start, Reel 1/3/5, Big Win, Mega Win, UI Click, Coin Fly)

## File Structure

```
flutter_ui/lib/
├── providers/
│   └── auto_spatial_provider.dart     # ✅ State management (~350 LOC)
└── widgets/spatial/
    ├── auto_spatial_panel.dart        # ✅ Main panel with 5 tabs (~260 LOC)
    ├── intent_rule_editor.dart        # ✅ Tab 1: Rule editing (~600 LOC)
    ├── bus_policy_editor.dart         # ✅ Tab 2: Bus policies (~350 LOC)
    ├── anchor_monitor.dart            # ✅ Tab 3: Anchor visualization (~500 LOC)
    ├── spatial_stats_panel.dart       # ✅ Tab 4: Stats & config (~500 LOC)
    ├── spatial_event_visualizer.dart  # ✅ Tab 5: Live radar (~550 LOC)
    └── spatial_widgets.dart           # ✅ Shared widgets (~250 LOC)
```

## Provider Features

```dart
class AutoSpatialProvider extends ChangeNotifier {
  // Singleton access
  static final AutoSpatialProvider instance = AutoSpatialProvider._();

  // Intent rules (mutable copy from defaults)
  final Map<String, IntentRule> _customRules;

  // Bus policies (mutable copy)
  final Map<SpatialBus, BusPolicy> _customPolicies;

  // Real-time stats (10Hz refresh)
  AutoSpatialStats _stats;

  // Engine configuration
  bool dopplerEnabled, distanceAttenuationEnabled, occlusionEnabled;
  bool reverbEnabled, hrtfEnabled, freqAbsorptionEnabled;
  SpatialRenderMode renderMode;
  Offset3D listenerPosition;
  double listenerRotation;
  double globalPanScale, globalWidthScale;

  // CRUD operations
  void updateRule(String intent, IntentRule rule);
  void deleteRule(String intent);
  void addRule(String intent, IntentRule rule);
  void resetRulesToDefaults();

  void updatePolicy(SpatialBus bus, BusPolicy policy);
  void resetPoliciesToDefaults();

  // JSON export/import
  String exportRulesJson();
  void importRulesJson(String json);
}
```

## Completed TODO List

### Phase 1: Foundation ✅
- [x] Read existing auto_spatial.dart
- [x] Create AutoSpatialProvider
- [x] Create main panel scaffold (auto_spatial_panel.dart)

### Phase 2: Intent Rules Editor ✅
- [x] IntentRule list with search
- [x] IntentRule detail form
- [x] Create/duplicate/delete
- [x] JSON export/import

### Phase 3: Bus Policy Editor ✅
- [x] Bus list (6 buses)
- [x] Policy editor per bus
- [x] Visual preview
- [x] Reset to defaults

### Phase 4: Anchor Monitor ✅
- [x] AnchorFrame list
- [x] Visual anchor positions (2D map)
- [x] Confidence indicators
- [x] Test anchor creation

### Phase 5: Stats & Config ✅
- [x] Stats display (activeEvents, processing time, etc.)
- [x] Config toggles (Doppler, HRTF, etc.)
- [x] Listener position controls
- [x] Render mode selector

### Phase 6: Live Visualizer ✅
- [x] 2D radar canvas
- [x] Event position markers
- [x] Color by bus
- [x] Click-to-inspect
- [x] Test event buttons

### Phase 7: Integration ✅
- [x] Add to SlotLab lower zone (tab "AutoSpatial")
- [x] flutter analyze — No issues found!

## Final Statistics

| Component | LOC (actual) |
|-----------|-------------|
| AutoSpatialProvider | ~350 |
| auto_spatial_panel.dart | ~260 |
| intent_rule_editor.dart | ~600 |
| bus_policy_editor.dart | ~350 |
| anchor_monitor.dart | ~500 |
| spatial_stats_panel.dart | ~500 |
| spatial_event_visualizer.dart | ~550 |
| spatial_widgets.dart | ~250 |
| **TOTAL** | **~3,360** |

## Future Enhancements (TODO)

### Priority 1: Engine Integration
- [ ] FFI Bridge for Rust AutoSpatialEngine
- [ ] Connect provider to real engine (currently mock data)
- [ ] Real-time spatial processing

### Priority 2: UX Improvements
- [ ] Rule Templates (pre-made presets for Cascade, BigWin, Jackpot scenarios)
- [ ] A/B Comparison mode
- [ ] Undo/Redo for rule editing
- [ ] Drag & drop rule reordering

### Priority 3: Advanced Visualizations
- [ ] 3D Visualizer option (WebGL/wgpu)
- [ ] Waveform + Spatial overlay
- [ ] Historical activity heatmap

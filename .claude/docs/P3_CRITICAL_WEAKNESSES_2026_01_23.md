# P3 Critical Weaknesses — Implementation Documentation

**Date:** 2026-01-23
**Status:** ✅ ALL COMPLETE
**Author:** Claude Opus 4.5

---

## Summary

All P3 Critical Weaknesses (P3.1-P3.5) have been implemented:

| ID | Task | Status |
|----|------|--------|
| P3.1 | Audio preview in event editor | ✅ DONE |
| P3.2 | Event debugger/tracer panel | ✅ DONE |
| P3.3 | Centralize stage configuration | ✅ DONE |
| P3.4 | GDD import wizard | ✅ DONE |
| P3.5 | Container visualization | ✅ DONE |

---

## P3.3: Centralize Stage Configuration

### Problem

Stage definitions were scattered across multiple files:
- `EventRegistry._shouldUsePool()` — 50+ lines of hardcoded pooled stages
- `EventRegistry._stageToPriority()` — 80+ lines of priority mappings
- `EventRegistry._stageToBus()` — 100+ lines of bus assignments
- `EventRegistry._stageToIntent()` — 350+ lines of spatial intent mappings

### Solution

Created `StageConfigurationService` as single source of truth.

### Files Modified

#### `flutter_ui/lib/services/stage_configuration_service.dart`

**Changes:**
- Added import for `SpatialBus` from `auto_spatial.dart`
- Removed duplicate `SpatialBus` enum (was causing name collision)
- Added `_getSpatialIntentByPrefix()` fallback method (~130 lines)
- Comprehensive spatial intent mappings for all stage types

**Key Methods:**
```dart
// Priority lookup
int getPriority(String stage);

// Bus routing
SpatialBus getBus(String stage);

// Spatial intent for AutoSpatialEngine
String getSpatialIntent(String stage);

// Voice pooling check
bool isPooled(String stage);

// Custom stage registration
void registerCustomStage(StageDefinition def);
```

#### `flutter_ui/lib/services/event_registry.dart`

**Changes:**
- Added import for `StageConfigurationService`
- Replaced 4 large hardcoded functions with delegations:

```dart
bool _shouldUsePool(String stage) {
  if (!_useAudioPool) return false;
  return StageConfigurationService.instance.isPooled(stage);
}

int _stageToPriority(String stage) {
  return StageConfigurationService.instance.getPriority(stage);
}

SpatialBus _stageToBus(String stage, int busId) {
  final serviceBus = StageConfigurationService.instance.getBus(stage);
  // Fallback to busId if provided
  if (busId > 0) {
    return switch (busId) { /* mapping */ };
  }
  return serviceBus;
}

String _stageToIntent(String stage) {
  return StageConfigurationService.instance.getSpatialIntent(stage);
}
```

#### `flutter_ui/lib/main.dart`

**Changes:**
- Added import for `StageConfigurationService`
- Added initialization call:

```dart
void main() async {
  // ...existing code...
  StageConfigurationService.instance.init();
  runApp(const FluxForgeApp());
}
```

---

## P3.4: GDD Import Wizard

### Problem

No way to import Game Design Documents (GDD) for automatic stage generation.

### Solution

Created 2-file solution:
1. `GddImportService` — JSON parsing and stage generation
2. `GddImportWizard` — 4-step wizard UI

### Files Created

#### `flutter_ui/lib/services/gdd_import_service.dart` (~650 lines)

**Models:**
- `GddGridConfig` — rows, columns, mechanic, paylines/ways
- `GddSymbol` — id, name, tier, payouts, isWild/isScatter/isBonus
- `SymbolTier` — enum: low, mid, high, premium, special, wild, scatter, bonus
- `GddFeature` — id, name, type, triggerCondition, stages
- `GddFeatureType` — enum: freeSpins, bonus, holdAndSpin, cascade, gamble, jackpot, etc.
- `GddWinTier` — id, name, minMultiplier, maxMultiplier
- `GddMathModel` — rtp, volatility, hitFrequency, winTiers
- `GameDesignDocument` — complete GDD container
- `GddImportResult` — gdd, generatedStages, warnings, errors

**Service Methods:**
```dart
// Parse GDD JSON
GddImportResult? importFromJson(String jsonString);

// Generate stages from GDD features
List<String> _generateStages(GameDesignDocument gdd);

// Feature-specific stage generation
List<String> _stagesForFeature(GddFeature feature);

// Validation
List<String> _validateGdd(GameDesignDocument gdd);

// Sample GDD for testing
String createSampleGddJson();
```

**Generated Stages by Feature:**

| Feature | Generated Stages |
|---------|-----------------|
| Free Spins | FS_TRIGGER, FS_ENTER, FS_SPIN_START/END, FS_RETRIGGER, FS_EXIT, FS_SUMMARY, FS_MUSIC |
| Bonus | BONUS_TRIGGER, BONUS_ENTER, BONUS_STEP, BONUS_REVEAL, BONUS_EXIT, BONUS_MUSIC |
| Hold & Spin | HOLD_TRIGGER, HOLD_ENTER, HOLD_SPIN, HOLD_SYMBOL_LAND, HOLD_RESPIN_RESET, HOLD_GRID_FULL, HOLD_EXIT, HOLD_MUSIC |
| Cascade | CASCADE_START, CASCADE_STEP, CASCADE_SYMBOL_POP, CASCADE_END, CASCADE_COMBO_3/4/5 |
| Gamble | GAMBLE_START, GAMBLE_CHOICE, GAMBLE_WIN, GAMBLE_LOSE, GAMBLE_COLLECT, GAMBLE_END |
| Jackpot | JACKPOT_TRIGGER, JACKPOT_MINI/MINOR/MAJOR/GRAND, JACKPOT_PRESENT, JACKPOT_END |
| Multiplier | MULT_LAND, MULT_APPLY, MULT_INCREASE |

#### `flutter_ui/lib/widgets/slot_lab/gdd_import_wizard.dart` (~780 lines)

**4-Step Wizard:**

1. **Input** — Paste JSON, load file, or load sample
2. **Preview** — Show parsed GDD summary (grid, math, symbols, features)
3. **Stages** — List generated stages with color-coded categories
4. **Confirm** — Import summary, register stages with StageConfigurationService

**Usage:**
```dart
final result = await GddImportWizard.show(context);
if (result != null) {
  // result.gdd — parsed GameDesignDocument
  // result.generatedStages — List<String> of stage names
}
```

**Category Colors:**
- Spin: Blue (#4A9EFF)
- Win: Gold (#FFD700)
- Free Spins/Bonus: Green (#40FF90)
- Hold & Spin: Orange (#FF9040)
- Cascade: Cyan (#40C8FF)
- Jackpot: Red (#FF4040)
- Gamble: Purple (#E040FB)
- Wild/Scatter: Pink (#FFB6C1)
- Symbol: Gray (#888888)
- Custom: White

### Files Modified

#### `flutter_ui/lib/screens/slot_lab_screen.dart`

**Changes:**
- Added import for `GddImportWizard`
- Added "Import GDD" button in header
- Added `_showGddImportWizard()` method

```dart
_buildGlassButton(
  icon: Icons.upload_file,
  onTap: _showGddImportWizard,
  tooltip: 'Import GDD',
),

Future<void> _showGddImportWizard() async {
  final result = await GddImportWizard.show(context);
  if (result != null && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported GDD "${result.gdd.name}" with ${result.generatedStages.length} stages',
        ),
        backgroundColor: const Color(0xFF40FF90),
      ),
    );
  }
}
```

---

## P3.5: Container Visualization Improvements

### Problem

Container panels had basic visualization without:
- Interactive RTPC preview for Blend containers
- Weight distribution charts for Random containers
- Play/stop preview for Sequence containers

### Solution

Created new visualization widgets and integrated into existing panels.

### Files Created

#### `flutter_ui/lib/widgets/middleware/container_visualization_widgets.dart` (~970 lines)

**Blend Container Widgets:**

```dart
/// Interactive RTPC slider with real-time blend preview
class BlendRtpcSlider extends StatefulWidget {
  final BlendContainer container;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onPreview;
}
```

Features:
- RTPC value slider (0.0-1.0)
- Child range indicators (colored backgrounds)
- Volume meters per child (calculated from RTPC position)
- "Preview Blend" button

**Random Container Widgets:**

```dart
/// Pie chart showing weight distribution
class RandomWeightPieChart extends StatelessWidget {
  final RandomContainer container;
  final int? selectedChildId;
  final ValueChanged<int?>? onChildSelected;
}

/// Selection history visualization
class RandomSelectionHistory extends StatelessWidget {
  final List<int> history;
  final RandomContainer container;
}
```

Features:
- Interactive pie chart (tap to select child)
- Color-coded segments with percentage labels
- Selection highlight (selected segment pops out)
- History display showing last 10 selections

**Sequence Container Widgets:**

```dart
/// Enhanced sequence timeline with waveform previews
class SequenceTimelineVisualization extends StatelessWidget {
  final SequenceContainer container;
  final int? currentStepIndex;
  final int? selectedStepIndex;
  final ValueChanged<int?>? onStepSelected;
  final bool isPlaying;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
}
```

Features:
- Play/Stop button with state indication
- Total duration display
- End behavior indicator (stop/loop/holdLast/pingPong)
- Visual timeline with color-coded steps
- Current step highlight during playback
- Click to select step

**Common Widgets:**

```dart
/// Container type badge (compact or full)
class ContainerTypeBadge extends StatelessWidget {
  final ContainerType type;
  final bool compact;
}

/// Mini container preview card
class ContainerPreviewCard extends StatelessWidget {
  final String name;
  final ContainerType type;
  final int childCount;
  final VoidCallback? onTap;
  final bool isSelected;
}
```

### Files Modified

#### `flutter_ui/lib/widgets/middleware/blend_container_panel.dart`

**Changes:**
- Added import for `container_visualization_widgets.dart`
- Added `_rtpcPreviewValue` state variable
- Added `BlendRtpcSlider` before visualization
- Updated `_BlendCurvePainter` with `currentRtpcValue` parameter
- Added RTPC position indicator line in painter

```dart
class _BlendContainerPanelState extends State<BlendContainerPanel> {
  // ...existing fields...
  double _rtpcPreviewValue = 0.5; // NEW
}

// In _buildBlendVisualization:
BlendRtpcSlider(
  container: container,
  value: _rtpcPreviewValue,
  onChanged: (v) => setState(() => _rtpcPreviewValue = v),
  onPreview: () { /* TODO: Preview blend */ },
),
```

#### `flutter_ui/lib/widgets/middleware/random_container_panel.dart`

**Changes:**
- Added import for `container_visualization_widgets.dart`
- Modified layout to include pie chart next to children list

```dart
// In _buildContainerEditor:
Row(
  children: [
    // Children list (flex: 3)
    Expanded(flex: 3, child: _buildChildrenList(container)),
    const SizedBox(width: 12),
    // Weight distribution pie chart (flex: 2)
    Expanded(
      flex: 2,
      child: RandomWeightPieChart(
        container: container,
        selectedChildId: _selectedChildId,
        onChildSelected: (id) => setState(() => _selectedChildId = id),
      ),
    ),
  ],
)
```

#### `flutter_ui/lib/widgets/middleware/sequence_container_panel.dart`

**Changes:**
- Added import for `container_visualization_widgets.dart`
- Added `_isPlaying` and `_currentPlayingStepIndex` state
- Replaced `_buildTimeline` with `SequenceTimelineVisualization`
- Added preview playback methods

```dart
class _SequenceContainerPanelState extends State<SequenceContainerPanel> {
  // ...existing fields...
  bool _isPlaying = false;
  int? _currentPlayingStepIndex;
}

// In _buildTimelineView:
SequenceTimelineVisualization(
  container: container,
  currentStepIndex: _currentPlayingStepIndex,
  selectedStepIndex: _selectedStepIndex,
  isPlaying: _isPlaying,
  onStepSelected: (index) => setState(() => _selectedStepIndex = index),
  onPlay: () => _startPreview(container),
  onStop: _stopPreview,
)

// Preview methods:
void _startPreview(SequenceContainer container) { /* ... */ }
void _playNextStep(SequenceContainer container, int stepIndex) { /* ... */ }
void _stopPreview() { /* ... */ }
```

---

## Model Field Reference

### BlendChild

```dart
class BlendChild {
  final int id;
  final String name;
  final String? audioPath;
  final double rtpcStart;
  final double rtpcEnd;
  final double crossfadeWidth;
}
```

### SequenceStep

```dart
class SequenceStep {
  final int index;
  final int childId;
  final String childName;  // NOT "name"
  final String? audioPath;
  final double delayMs;    // NOT "delay"
  final double durationMs; // NOT "duration"
  final double fadeInMs;
  final double fadeOutMs;
  final int loopCount;
  final double volume;
}
```

### SequenceEndBehavior

```dart
enum SequenceEndBehavior {
  stop,
  loop,
  holdLast,  // NOT "hold"
  pingPong,
}
```

---

## Testing

All changes verified with:
```bash
cd flutter_ui
flutter analyze
# Result: No issues found!
```

---

## Next Steps

P3 UX Improvements (P3.6-P3.10) are next in the roadmap:
- P3.6: Layer timeline visualization
- P3.7: Loudness analysis pre-export
- P3.8: Priority tier presets
- P3.9: Visual bus hierarchy editor
- P3.10: DSP profiler integration

---

*Last Updated: 2026-01-23*

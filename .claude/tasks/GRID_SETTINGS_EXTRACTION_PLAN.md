# Grid Settings Panel — Extraction Plan

**Created:** 2026-01-26
**Complexity:** HIGH (state lifting required)
**Effort:** 1-1.5 hours
**Status:** READY FOR NEXT SESSION

---

## 📊 Scope Analysis

**Location:** Lines 1852-2432 (~580 LOC total)
**Components:** 11 methods + state + dialog

---

## 🔍 Complete Component List

### Main Builder
- `_buildCompactGridSettings()` (70 LOC) — Main panel layout

### Helper Methods (10)
1. `_buildSubSectionHeader()` (12 LOC) — Section headers
2. `_buildTempoControl()` (75 LOC) — Tempo display + tap-to-edit
3. `_showTempoEditDialog()` (50 LOC) — Tempo input dialog
4. `_buildTimeSignatureControl()` (45 LOC) — Time sig display + dropdown
5. `_buildTimeSignatureDropdown()` (30 LOC) — Time sig menu
6. `_buildTimeSignaturePreset()` (25 LOC) — Quick preset buttons
7. `_buildGridToggle()` (40 LOC) — Snap/Triplet toggles
8. `_buildGridResolutionSelector()` (60 LOC) — Note value chips
9. `_buildGridResolutionChip()` (30 LOC) — Individual chip
10. `_buildSnapIndicator()` (140 LOC) — Visual grid preview

### State Variables (Currently in Parent)

**From `DawLowerZoneWidget` class (lines 63-72, 115-118):**
```dart
final bool snapEnabled;           // Passed from parent
final bool tripletGrid;           // Passed from parent
final ValueChanged<bool>? onSnapEnabledChanged;  // Callback
final ValueChanged<bool>? onTripletGridChanged;  // Callback
```

**Note:** These are READONLY properties — grid panel displays them but doesn't own state.

---

## 🚨 Critical Issue: State Ownership

**Problem:** Grid settings are controlled by PARENT widget, not panel itself.

**Current Architecture:**
```
EngineConnectedLayout (top-level)
    ↓ (passes snapEnabled, tripletGrid, callbacks)
DawLowerZoneWidget
    ↓ (passes to GridSettings panel via widget.xxx)
_buildCompactGridSettings()
```

**Implication:** Grid panel must be **CONTROLLED** component (like a form input).

---

## 🎯 Extraction Strategy

### Option A: Controlled Component (Recommended)

**Pattern:** Panel receives all state via props, calls callbacks on changes.

```dart
class GridSettingsPanel extends StatelessWidget {
  // State from parent
  final bool snapEnabled;
  final bool tripletGrid;
  final double tempo;
  final (int, int) timeSignature;
  final GridResolution gridResolution;

  // Callbacks to parent
  final ValueChanged<bool>? onSnapEnabledChanged;
  final ValueChanged<bool>? onTripletGridChanged;
  final ValueChanged<double>? onTempoChanged;
  final ValueChanged<(int, int)>? onTimeSignatureChanged;
  final ValueChanged<GridResolution>? onGridResolutionChanged;

  const GridSettingsPanel({
    super.key,
    required this.snapEnabled,
    required this.tripletGrid,
    this.tempo = 120.0,
    this.timeSignature = (4, 4),
    this.gridResolution = GridResolution.quarter,
    this.onSnapEnabledChanged,
    this.onTripletGridChanged,
    this.onTempoChanged,
    this.onTimeSignatureChanged,
    this.onGridResolutionChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Use properties, call callbacks
  }
}
```

**Pro:** Clean separation, no state duplication
**Con:** More properties to pass

---

### Option B: Autonomous Component with Initial Values

**Pattern:** Panel owns state, initializes from props.

```dart
class GridSettingsPanel extends StatefulWidget {
  final bool initialSnapEnabled;
  final bool initialTripletGrid;
  final ValueChanged<GridSettings>? onSettingsChanged;

  // ...
}

class _GridSettingsPanelState extends State<GridSettingsPanel> {
  late bool _snapEnabled;
  late bool _tripletGrid;
  late double _tempo;
  // ...

  @override
  void initState() {
    super.initState();
    _snapEnabled = widget.initialSnapEnabled;
    _tripletGrid = widget.initialTripletGrid;
    // ...
  }

  void _updateSettings() {
    widget.onSettingsChanged?.call(GridSettings(
      snapEnabled: _snapEnabled,
      tripletGrid: _tripletGrid,
      tempo: _tempo,
      // ...
    ));
  }
}
```

**Pro:** Self-contained, easier to extract
**Con:** State duplication, sync issues

---

## ✅ RECOMMENDATION: Option A (Controlled)

**Why:**
- Matches Flutter best practices (like TextField)
- No state duplication
- Parent retains control (important for global timeline settings)
- Easier to test

**Trade-off:** More props, but cleaner architecture

---

## 📋 Extraction Steps

### Step 1: Create GridSettings Model (if needed)

```dart
// In lower_zone_types.dart or grid_settings_panel.dart
enum GridResolution {
  whole,
  half,
  quarter,
  eighth,
  sixteenth,
  thirtySecond,
  sixtyFourth,
}

extension GridResolutionExt on GridResolution {
  String get label => switch (this) {
    GridResolution.whole => '1/1',
    GridResolution.half => '1/2',
    GridResolution.quarter => '1/4',
    GridResolution.eighth => '1/8',
    GridResolution.sixteenth => '1/16',
    GridResolution.thirtySecond => '1/32',
    GridResolution.sixtyFourth => '1/64',
  };
}
```

---

### Step 2: Extract Panel File

**File:** `daw/edit/grid_settings_panel.dart` (~580 LOC)

**Structure:**
```dart
import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';

class GridSettingsPanel extends StatelessWidget {
  // All properties (controlled component)
  final bool snapEnabled;
  final bool tripletGrid;
  final double tempo;
  final (int, int) timeSignature;
  final GridResolution gridResolution;

  // All callbacks
  final ValueChanged<bool>? onSnapEnabledChanged;
  final ValueChanged<bool>? onTripletGridChanged;
  final ValueChanged<double>? onTempoChanged;
  final ValueChanged<(int, int)>? onTimeSignatureChanged;
  final ValueChanged<GridResolution>? onGridResolutionChanged;

  const GridSettingsPanel({...});

  @override
  Widget build(BuildContext context) {
    // Extracted _buildCompactGridSettings() code
  }

  // All 10 helper methods
  Widget _buildSubSectionHeader(String label) { ... }
  Widget _buildTempoControl() { ... }
  // etc.
}

// Tempo Edit Dialog (if exists as separate class)
class _TempoEditDialog extends StatefulWidget { ... }
```

---

### Step 3: Update Main Widget

**Add to DawLowerZoneWidget:**
```dart
import 'daw/edit/grid_settings_panel.dart';

// In _buildGridPanel():
Widget _buildGridPanel() => GridSettingsPanel(
  snapEnabled: widget.snapEnabled,
  tripletGrid: widget.tripletGrid,
  tempo: _currentTempo,  // If local state exists
  timeSignature: _currentTimeSignature,
  gridResolution: _currentGridResolution,
  onSnapEnabledChanged: widget.onSnapEnabledChanged,
  onTripletGridChanged: widget.onTripletGridChanged,
  onTempoChanged: (tempo) {
    setState(() => _currentTempo = tempo);
    // Optionally notify parent via callback
  },
  onTimeSignatureChanged: (timeSig) {
    setState(() => _currentTimeSignature = timeSig);
  },
  onGridResolutionChanged: (res) {
    setState(() => _currentGridResolution = res);
  },
);
```

---

### Step 4: State Migration

**Current state in main widget (if any):**
```dart
class _DawLowerZoneWidgetState extends State<DawLowerZoneWidget> {
  double _currentTempo = 120.0;
  (int, int) _currentTimeSignature = (4, 4);
  GridResolution _currentGridResolution = GridResolution.quarter;
  // ...
}
```

**After extraction:** Keep state in main widget, pass via props

**Alternative:** Move state to Grid panel if it's panel-specific only

---

## ⚠️ Edge Cases to Handle

### Edge Case 1: Tempo Edit Dialog

**Check if exists:**
```bash
grep -n "class _TempoEditDialog" daw_lower_zone_widget.dart
```

**If exists:** Extract to grid_settings_panel.dart
**If inline:** Keep inline in `_showTempoEditDialog()` method

---

### Edge Case 2: Time Signature Presets

**Lines ~2138-2170:** Preset buttons (2/4, 3/4, 4/4, etc.)

**Action:** Include in `_buildTimeSignatureControl()` section

---

### Edge Case 3: Snap Indicator Painter

**Lines 2329-2400:** Visual grid preview with CustomPainter

**Check for separate class:**
```bash
grep -n "class _.*Painter.*snap\|class _.*Painter.*grid" daw_lower_zone_widget.dart
```

**If separate:** Include at end of grid_settings_panel.dart

---

## 📝 Verification Checklist

**Before extraction:**
- [ ] Identified all 11 methods
- [ ] Identified all state variables
- [ ] Identified all callbacks
- [ ] Checked for dialogs/painters
- [ ] Confirmed property ownership

**After extraction:**
- [ ] `flutter analyze` passes (panel file)
- [ ] All imports correct
- [ ] All callbacks wired
- [ ] Properties documented
- [ ] Main widget updated
- [ ] `flutter analyze` passes (main widget)

---

## 🎯 Expected Result

**New File:**
- `daw/edit/grid_settings_panel.dart` (~600 LOC)
- GridSettingsPanel class (controlled component)
- 11 helper methods
- 1-2 painter classes (if exist)
- Tempo edit dialog (if exists)

**Main Widget:**
- Import added
- `_buildGridPanel()` replaced with `GridSettingsPanel(...)`
- Properties passed via constructor
- Callbacks wired

**LOC Reduction:**
- Before: ~4,217 LOC
- After: ~3,617 LOC
- Reduction: ~600 LOC (35% total)

---

## ⏭️ After Grid Settings

**Remaining EDIT panels:**
- Piano Roll wrapper (~100 LOC) — SIMPLE
- Clip Properties (~150 LOC) — SIMPLE

**Total Phase 2:** ~750 LOC remaining
**Estimated:** 30-40 min after Grid Settings

---

**Plan Complete — Ready for Implementation**

**Next Session:** Start here, execute plan, complete Phase 2

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>

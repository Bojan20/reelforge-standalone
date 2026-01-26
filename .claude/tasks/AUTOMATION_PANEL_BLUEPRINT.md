# Automation Panel Extraction Blueprint

**Created:** 2026-01-26
**Lines:** 1764-2017 + 3226-3375 (~400 LOC total)
**Complexity:** HIGH (stateful, painter, gesture detection)
**Status:** READY FOR EXTRACTION

---

## 📋 Complete Scope

### State Variables (lines 1764-1768)
```dart
String _automationMode = 'Read';  // Read, Write, Touch
String _automationParameter = 'Volume';
List<Offset> _automationPoints = [];
int? _selectedAutomationPointIndex;
```

### Main Builder (lines 1771-1894)
- Header with mode chips
- Parameter dropdown
- Clear button
- Point count display
- Interactive editor or placeholder

### Helper Methods (3)
1. `_buildNoTrackAutomationPlaceholder()` (27 LOC)
2. `_buildInteractiveAutomationEditor()` (97 LOC)
3. `_buildAutomationModeChip()` (24 LOC)

### Painter Class (lines 3226-3375, ~150 LOC)
- `_InteractiveAutomationCurvePainter`
- Grid drawing
- Curve drawing (cubic bezier)
- Point rendering
- Value labels

---

## 🎯 Extraction Template

```dart
/// DAW Automation Panel (P0.1 Extracted)
///
/// Interactive automation curve editor:
/// - Mode selection (Read, Write, Touch)
/// - Parameter selection (Volume, Pan, Send, etc.)
/// - Point-based curve editing
/// - Cubic bezier interpolation
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1764-2017 + 3226-3375 (~400 LOC)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';

class AutomationPanel extends StatefulWidget {
  final int? selectedTrackId;

  const AutomationPanel({super.key, this.selectedTrackId});

  @override
  State<AutomationPanel> createState() => _AutomationPanelState();
}

class _AutomationPanelState extends State<AutomationPanel> {
  String _automationMode = 'Read';
  String _automationParameter = 'Volume';
  List<Offset> _automationPoints = [];
  int? _selectedAutomationPointIndex;

  @override
  Widget build(BuildContext context) {
    // COPY lines 1776-1894
  }

  Widget _buildNoTrackAutomationPlaceholder() {
    // COPY lines 1897-1924
  }

  Widget _buildInteractiveAutomationEditor() {
    // COPY lines 1926-1984
  }

  Widget _buildAutomationModeChip(String label, bool isActive) {
    // COPY lines 1987-2011
  }
}

class AutomationCurvePainter extends CustomPainter {
  // COPY lines 3227-3375 (rename _InteractiveAutomationCurvePainter → AutomationCurvePainter)
}
```

---

## ⚠️ Critical Points

### Point 1: Context for setState

**Line 1830:** `setState(() => _automationParameter = value)`
**Line 1868:** `setState(() => _automationPoints.clear())`
**Lines 1930-1960:** Multiple setState calls in gestures

**All handled** — panel is StatefulWidget

---

### Point 2: Painter Rename

**Original:** `_InteractiveAutomationCurvePainter` (private)
**Extracted:** `AutomationCurvePainter` (public)

**Why:** Panel file exports it

---

### Point 3: Gesture Detection

**Lines 1927-1962:** Complex gesture handling (tap, pan, double-tap)

**Keep intact** — critical for automation editing

---

## 📝 Extraction Checklist

- [ ] Create automation_panel.dart file
- [ ] Copy state variables (4)
- [ ] Copy main builder (124 LOC)
- [ ] Copy helper methods (3)
- [ ] Copy painter class (150 LOC)
- [ ] Rename painter (remove _ prefix)
- [ ] Fix imports
- [ ] Verify flutter analyze
- [ ] Update main widget
- [ ] Test automation editing

---

## ✅ Expected Result

**File:** `daw/mix/automation_panel.dart` (~400 LOC)

**Main Widget Update:**
```dart
import 'daw/mix/automation_panel.dart';

Widget _buildAutomationPanel() => AutomationPanel(
  selectedTrackId: widget.selectedTrackId,
);
```

**LOC Reduction:** ~400 LOC from main widget

---

**Blueprint Complete — Execute in Next Session**

**Effort:** 45 minutes

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>

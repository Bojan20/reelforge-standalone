# Grid Settings Panel — Complete Extraction Blueprint

**Created:** 2026-01-26
**For:** Next session implementation
**Lines to Extract:** 1852-2432 + 5326-5385 (~640 LOC total)
**Complexity:** VERY HIGH (10+ properties, 3 callbacks, painter, dialog)

---

## 📋 COMPLETE COMPONENT MANIFEST

### Properties (From Parent Widget)

```dart
// From DawLowerZoneWidget properties (lines 63-72):
final double tempo;                    // Current tempo (BPM)
final int timeSignatureNumerator;      // Time sig numerator (2-12)
final int timeSignatureDenominator;    // Time sig denominator (2,4,8,16)
final bool snapEnabled;                // Snap to grid enabled
final bool tripletGrid;                // Triplet grid mode
final double snapValue;                // Snap value in beats (0.0625-4.0)

// Callbacks (lines 73-78):
final ValueChanged<double>? onTempoChanged;
final void Function(int numerator, int denominator)? onTimeSignatureChanged;
final ValueChanged<bool>? onSnapEnabledChanged;
final ValueChanged<bool>? onTripletGridChanged;
final ValueChanged<double>? onSnapValueChanged;
```

---

### Methods to Extract (11)

**Location:** Lines 1852-2432

| Method | Lines | LOC | Description |
|--------|-------|-----|-------------|
| `_buildCompactGridSettings()` | 1853-1921 | 69 | Main panel layout |
| `_buildSubSectionHeader()` | 1925-1935 | 11 | Section headers ("TEMPO", "GRID", etc.) |
| `_buildTempoControl()` | 1938-2013 | 76 | Tempo display + TAP button |
| `_showTempoEditDialog()` | 2016-2064 | 49 | Tempo input dialog |
| `_buildTimeSignatureControl()` | 2067-2112 | 46 | Time sig display + dropdowns |
| `_buildTimeSignatureDropdown()` | 2115-2142 | 28 | Dropdown widget |
| `_buildTimeSignaturePreset()` | 2145-2175 | 31 | Quick preset buttons (4/4, 3/4, 6/8) |
| `_buildGridToggle()` | 2178-2244 | 67 | Snap/Triplet toggle switches |
| `_buildGridResolutionSelector()` | 2247-2327 | 81 | Grid resolution chips |
| `_buildSnapIndicator()` | 2330-2398 | 69 | Visual grid preview |
| `_snapValueToLabel()` | 2401-2409 | 9 | Convert value → label |

**Total:** 536 LOC (methods only)

---

### Painter Class to Extract

**Location:** Lines 5326-5385 (~60 LOC)

```dart
class _GridPreviewPainter extends CustomPainter {
  final double snapValue;
  final bool isActive;
  final Color accentColor;

  _GridPreviewPainter({
    required this.snapValue,
    required this.isActive,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Grid line rendering (~40 LOC)
  }

  @override
  bool shouldRepaint(_GridPreviewPainter oldDelegate) {
    return oldDelegate.snapValue != snapValue ||
        oldDelegate.isActive != isActive ||
        oldDelegate.accentColor != accentColor;
  }
}
```

**Rename to:** `GridPreviewPainter` (remove `_` prefix for export)

---

### Shared Method (_buildSectionHeader)

**Note:** `_buildSectionHeader()` (lines 2411-2427) is used by MULTIPLE panels.

**Decision:** Extract to `daw/shared/common_builders.dart` OR duplicate in each panel.

**Recommendation:** Duplicate (only 17 LOC, avoid extra import complexity).

---

## 🎯 COMPLETE FILE TEMPLATE

```dart
/// DAW Grid/Timeline Settings Panel (P0.1 Extracted)
///
/// Interactive timeline settings:
/// - Tempo (20-999 BPM) with tap-to-edit
/// - Time signature (2-12 / 2,4,8,16)
/// - Snap to grid (1/64 - Bar)
/// - Triplet grid mode
/// - Visual snap indicator
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1852-2432 + 5326-5385 (~640 LOC total)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GRID SETTINGS PANEL (CONTROLLED COMPONENT)
// ═══════════════════════════════════════════════════════════════════════════

class GridSettingsPanel extends StatelessWidget {
  // Timeline settings (from parent)
  final double tempo;
  final int timeSignatureNumerator;
  final int timeSignatureDenominator;
  final bool snapEnabled;
  final bool tripletGrid;
  final double snapValue; // In beats (0.0625 = 1/64, 1.0 = 1/4, 4.0 = Bar)

  // Callbacks to parent
  final ValueChanged<double>? onTempoChanged;
  final void Function(int numerator, int denominator)? onTimeSignatureChanged;
  final ValueChanged<bool>? onSnapEnabledChanged;
  final ValueChanged<bool>? onTripletGridChanged;
  final ValueChanged<double>? onSnapValueChanged;

  const GridSettingsPanel({
    super.key,
    this.tempo = 120.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
    this.snapEnabled = true,
    this.tripletGrid = false,
    this.snapValue = 1.0, // 1/4 note default
    this.onTempoChanged,
    this.onTimeSignatureChanged,
    this.onSnapEnabledChanged,
    this.onTripletGridChanged,
    this.onSnapValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('TIMELINE SETTINGS', Icons.settings),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column: Tempo & Time Signature
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tempo section
                        _buildSubSectionHeader('TEMPO'),
                        const SizedBox(height: 8),
                        _buildTempoControl(context),
                        const SizedBox(height: 16),
                        // Time Signature section
                        _buildSubSectionHeader('TIME SIGNATURE'),
                        const SizedBox(height: 8),
                        _buildTimeSignatureControl(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right column: Grid Settings
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSubSectionHeader('GRID'),
                        const SizedBox(height: 8),
                        // Snap Enable Toggle
                        _buildGridToggle(
                          label: 'Snap to Grid',
                          value: snapEnabled,
                          icon: Icons.grid_on,
                          onChanged: onSnapEnabledChanged,
                        ),
                        const SizedBox(height: 8),
                        // Grid Resolution Selector
                        _buildGridResolutionSelector(),
                        const SizedBox(height: 8),
                        // Triplet Grid Toggle
                        _buildGridToggle(
                          label: 'Triplet Grid',
                          value: tripletGrid,
                          icon: Icons.grid_3x3,
                          onChanged: onTripletGridChanged,
                        ),
                        const SizedBox(height: 12),
                        // Visual indicator of current snap
                        _buildSnapIndicator(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section Headers ───────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSubSectionHeader(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: LowerZoneColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }

  // ─── Tempo Controls ────────────────────────────────────────────────────────

  Widget _buildTempoControl(BuildContext context) {
    // COPY lines 1939-2012 (74 LOC)
    // Replace _showTempoEditDialog() with _showTempoEditDialog(context)
  }

  void _showTempoEditDialog(BuildContext context) {
    // COPY lines 2016-2063 (48 LOC)
    // Replace widget.tempo → tempo
    // Replace widget.onTempoChanged → onTempoChanged
  }

  // ─── Time Signature Controls ───────────────────────────────────────────────

  Widget _buildTimeSignatureControl() {
    // COPY lines 2068-2111 (44 LOC)
    // Replace widget.timeSignatureXxx → timeSignatureXxx
    // Replace widget.onTimeSignatureChanged → onTimeSignatureChanged
  }

  Widget _buildTimeSignatureDropdown({
    required int value,
    required List<int> items,
    required ValueChanged<int> onChanged,
  }) {
    // COPY lines 2120-2141 (22 LOC)
  }

  Widget _buildTimeSignaturePreset(String label, int num, int denom) {
    // COPY lines 2145-2174 (30 LOC)
    // Replace widget.timeSignatureXxx → timeSignatureXxx
    // Replace widget.onTimeSignatureChanged → onTimeSignatureChanged
  }

  // ─── Grid Controls ─────────────────────────────────────────────────────────

  Widget _buildGridToggle({
    required String label,
    required bool value,
    required IconData icon,
    ValueChanged<bool>? onChanged,
  }) {
    // COPY lines 2184-2243 (60 LOC)
  }

  Widget _buildGridResolutionSelector() {
    // COPY lines 2247-2326 (80 LOC)
    // Replace widget.snapValue → snapValue
    // Replace widget.onSnapValueChanged → onSnapValueChanged
  }

  Widget _buildSnapIndicator() {
    // COPY lines 2330-2397 (68 LOC)
    // Replace widget.snapValue → snapValue
    // Replace widget.snapEnabled → snapEnabled
    // Replace widget.tripletGrid → tripletGrid
  }

  String _snapValueToLabel(double value) {
    // COPY lines 2401-2408 (8 LOC)
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GRID PREVIEW PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class GridPreviewPainter extends CustomPainter {
  // COPY lines 5327-5385 (59 LOC)
  // Remove _ prefix (make public)
}
```

---

## 📝 Extraction Checklist

**Pre-extraction:**
- [ ] Confirm all 11 methods identified
- [ ] Confirm all 6 properties identified
- [ ] Confirm all 5 callbacks identified
- [ ] Confirm painter class location (line 5326)
- [ ] Check for dialog classes (none found)

**During extraction:**
- [ ] Copy template above to `daw/edit/grid_settings_panel.dart`
- [ ] Copy method bodies (preserve line numbers in comments)
- [ ] Replace all `widget.xxx` → `xxx` (use properties directly)
- [ ] Fix imports (need `../../lower_zone_types.dart`)
- [ ] Remove `_` prefix from GridPreviewPainter
- [ ] Add `@override` to build()

**Post-extraction:**
- [ ] `flutter analyze` panel file (must pass)
- [ ] Update main widget (add import)
- [ ] Update `_buildGridPanel()` method
- [ ] Pass all 11 parameters (6 props + 5 callbacks)
- [ ] `flutter analyze` main widget (must pass)

---

## 🎯 Main Widget Integration Code

**Add import:**
```dart
import 'daw/edit/grid_settings_panel.dart';
```

**Replace builder:**
```dart
// OLD:
Widget _buildGridPanel() => _buildCompactGridSettings();

// NEW:
Widget _buildGridPanel() => GridSettingsPanel(
  tempo: widget.tempo,
  timeSignatureNumerator: widget.timeSignatureNumerator,
  timeSignatureDenominator: widget.timeSignatureDenominator,
  snapEnabled: widget.snapEnabled,
  tripletGrid: widget.tripletGrid,
  snapValue: widget.snapValue,
  onTempoChanged: widget.onTempoChanged,
  onTimeSignatureChanged: widget.onTimeSignatureChanged,
  onSnapEnabledChanged: widget.onSnapEnabledChanged,
  onTripletGridChanged: widget.onTripletGridChanged,
  onSnapValueChanged: widget.onSnapValueChanged,
);
```

---

## ⚠️ Critical Notes

### Note 1: Controlled Component Pattern

This panel is **CONTROLLED** — it does NOT own state.

- Properties flow DOWN from parent
- Callbacks flow UP to parent
- Parent owns state (EngineConnectedLayout or DawLowerZoneWidget)

**Do NOT add state to panel** — keep it stateless.

---

### Note 2: Context for Dialog

**Line 1951:** `_showTempoEditDialog()` — needs BuildContext

**Current:**
```dart
onTap: () => _showTempoEditDialog(),
```

**Fixed:**
```dart
Widget _buildTempoControl(BuildContext context) {
  // ...
  onTap: () => _showTempoEditDialog(context),
```

**In method signature:**
```dart
void _showTempoEditDialog(BuildContext context) {
  showDialog(context: context, ...);
}
```

---

### Note 3: Painter Class Rename

**Original:** `class _GridPreviewPainter` (private)
**Extracted:** `class GridPreviewPainter` (public)

**Why:** Panel file exports it, can't be private.

---

### Note 4: ScaffoldMessenger

**Line 1986:** `ScaffoldMessenger.of(context)` — needs context

**Ensure context is available** in `_buildTempoControl()`.

---

## 🚀 Expected Result

**New File:** `daw/edit/grid_settings_panel.dart` (~640 LOC)

**Structure:**
```
GridSettingsPanel class (StatelessWidget)
├── 6 properties (tempo, timeSig, snap settings)
├── 5 callbacks
├── build() method
├── 11 helper methods
│   ├── Section headers (2)
│   ├── Tempo controls (2)
│   ├── Time sig controls (3)
│   ├── Grid controls (3)
│   └── Utility (1)
└── GridPreviewPainter class (at end)
```

**Main Widget:**
- Import added
- `_buildGridPanel()` replaced with GridSettingsPanel instantiation
- 11 parameters passed

**LOC Reduction:**
- Before: ~4,217 LOC
- After: ~3,577 LOC (-640)
- Total reduction: 35%

---

## ✅ Ready for Implementation

**Effort:** 60-90 minutes
**Difficulty:** HIGH (many properties, controlled component)
**Verification:** Critical (must test all controls work)

**Next after this:** Piano Roll + Clip Properties (30-40 min combined)

---

**Blueprint Complete — Execute in Next Session**

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>

# P0.1 Next Session Plan — Phase 2 EDIT Panels

**Created:** 2026-01-26
**For:** Next development session
**Estimated Effort:** 2-3 hours

---

## 📊 Current Status

**Completed:**
- ✅ Phase 1: BROWSE panels (4/4 complete)
  - Presets (470 LOC)
  - Plugins (407 LOC)
  - History (178 LOC)
  - Files (pre-existing)
- ✅ Timeline Overview (268 LOC) — BONUS

**Main Widget:**
- Start: 5,540 LOC
- Current: ~4,217 LOC (after Timeline extraction)
- Reduction: 24%

**Progress:** 5/20 panels (25%)

---

## 🎯 Phase 2: EDIT Panels — Scope

### Panel 1: Timeline Overview ✅ DONE

**Status:** Already extracted
**File:** `daw/edit/timeline_overview_panel.dart` (268 LOC)

---

### Panel 2: Grid Settings ⚡ PRIORITY NEXT

**Location:** Lines 1852-2329 (~477 LOC)
**Complexity:** HIGH (state, tempo, time sig, snap controls)

**Components to Extract:**
- Main builder: `_buildCompactGridSettings()`
- Sub-section header: `_buildGridSubSection()`
- Tempo control: `_buildTempoControl()`
- Tempo edit dialog: `_showTempoEditDialog()`
- Time signature control: `_buildTimeSignatureControl()`
- Time sig dropdown: `_buildTimeSignatureDropdown()`
- Time sig presets: `_buildTimeSignaturePreset()`
- Grid toggle: `_buildGridToggle()`
- Grid resolution: `_buildGridResolutionSelector()`
- Grid chip: `_buildGridResolutionChip()`
- Visual snap indicator: `_buildSnapIndicator()`

**State Variables:**
- `_currentTempo` (double, ~120.0)
- `_currentTimeSignature` ((int, int), (4, 4))
- `_gridEnabled` (bool, true)
- `_gridResolution` (GridResolution enum)

**Dependencies:**
- No external providers (self-contained)
- Uses LowerZoneColors

**Target File:** `daw/edit/grid_settings_panel.dart` (500 LOC)

---

### Panel 3: Piano Roll Wrapper 🔧 SIMPLE

**Location:** Lines 1620-1717 (~97 LOC)

**Components:**
- Wrapper for `PianoRollWidget` (already exists)
- No state
- No helpers
- Simple instantiation

**Target File:** `daw/edit/piano_roll_panel.dart` (100 LOC)

---

### Panel 4: Fades/Clip Properties 🔧 MEDIUM

**Location:** Lines 1718-1850 (~132 LOC)

**Components:**
- Wrapper for `CrossfadeEditor` (already exists)
- Clip properties section
- Placeholder for no clip selected

**State Variables:**
- Uses `widget.selectedClip` (passed from parent)

**Target File:** `daw/edit/clip_properties_panel.dart` (150 LOC)

---

## 📋 Extraction Sequence (Optimized)

### Step 1: Piano Roll Wrapper (~15 min)

**Why First:** Simplest, zero state, zero helpers
**LOC:** ~100
**Verification:** Quick

---

### Step 2: Clip Properties Wrapper (~20 min)

**Why Second:** Simple, minimal state
**LOC:** ~150
**Verification:** Quick

---

### Step 3: Grid Settings (~60 min)

**Why Last:** Most complex, has state + dialog
**LOC:** ~500
**Verification:** Thorough

---

### Step 4: Integration (~30 min)

**Tasks:**
- Add 3 imports to main widget
- Replace builders
- Verify `flutter analyze`
- Manual test all 4 EDIT tabs

---

## 🔍 Grid Settings Extraction Details

### State Variables to Extract

```dart
// From main widget state:
double _currentTempo = 120.0;
(int, int) _currentTimeSignature = (4, 4);
bool _gridEnabled = true;
GridResolution _gridResolution = GridResolution.quarter;
```

### Helper Methods to Extract (11)

1. `_buildCompactGridSettings()` — Main builder
2. `_buildGridSubSection()` — Section headers
3. `_buildTempoControl()` — Tempo display + tap-to-edit
4. `_showTempoEditDialog()` — Tempo input dialog
5. `_buildTimeSignatureControl()` — Time sig display
6. `_buildTimeSignatureDropdown()` — Time sig menu
7. `_buildTimeSignaturePreset()` — Quick presets (2/4, 3/4, 4/4, etc.)
8. `_buildGridToggle()` — Snap on/off toggle
9. `_buildGridResolutionSelector()` — Note value chips
10. `_buildGridResolutionChip()` — Individual chip
11. `_buildSnapIndicator()` — Visual grid lines preview

### Enums Needed

```dart
enum GridResolution {
  whole,
  half,
  quarter,
  eighth,
  sixteenth,
  thirtySecond,
  sixtyFourth,
}
```

**Note:** Check if GridResolution exists globally or needs to be panel-local.

---

## ⚠️ Known Challenges

### Challenge 1: State Management

**Issue:** Grid settings have local state that may need persistence

**Solution:** Keep state in panel widget (encapsulated)
**Callback:** Add `onTempoChange`, `onTimeSignatureChange`, `onGridChange` callbacks

---

### Challenge 2: Dialog Widget

**Issue:** Tempo edit dialog may be separate class at end of file

**Solution:** Search for `class _TempoEditDialog` and include in panel file

---

### Challenge 3: Enum Dependencies

**Issue:** GridResolution may be defined globally

**Solution:** Check `lower_zone_types.dart` first, if not there define in panel file

---

## ✅ Phase 2 Definition of Done

**All 4 EDIT panels extracted:**
- [x] Timeline Overview (done)
- [ ] Piano Roll Wrapper
- [ ] Clip Properties
- [ ] Grid Settings

**Main widget updated:**
- [ ] Imports added
- [ ] Builders replaced
- [ ] `flutter analyze` passes

**Verification:**
- [ ] All panels analyzed (0 errors)
- [ ] Manual test EDIT super-tab
- [ ] No regressions

**LOC Reduction:**
- Current: ~4,217 LOC
- Target after Phase 2: ~3,100 LOC
- Reduction: ~1,117 LOC (44% total)

---

## 🚀 Execution Protocol

### For Each Panel:

1. **Identify Scope** (5 min)
   ```bash
   grep -n "_buildXxx" file.dart
   grep -n "class _Xxx" file.dart  # Dialogs
   grep -n "_xxx.*=" file.dart     # State vars
   ```

2. **Extract Code** (10-40 min depending on complexity)
   - Copy to new file
   - Fix imports
   - Add callbacks
   - Encapsulate state

3. **Verify** (2 min)
   ```bash
   flutter analyze lib/widgets/lower_zone/daw/edit/xxx_panel.dart
   ```

4. **Repeat** for next panel

5. **Integrate** (after all 3 remaining panels done)
   - Add imports to main widget
   - Replace builders
   - Verify main widget

---

## 📝 Quick Reference

**Import Depth from** `daw/edit/`:
- Siblings: `../../` (lower_zone_types.dart)
- Services: `../../../../services/`
- Providers: `../../../../providers/`
- Models: `../../../../models/`

**Callback Pattern:**
```dart
class XxxPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;
  const XxxPanel({super.key, this.onAction});
}
```

**Provider Access:**
```dart
// For reactive UI:
final provider = context.watch<XxxProvider>();

// For method calls:
final provider = context.read<XxxProvider>();
```

---

**Ready for Next Session — Clear Plan Established!**

**Estimated Session Time:** 2-3 hours for complete Phase 2

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>

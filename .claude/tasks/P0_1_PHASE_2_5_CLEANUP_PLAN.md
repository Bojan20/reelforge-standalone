# P0.1 Phase 2.5 — Cleanup Plan

**Created:** 2026-01-26
**Purpose:** Remove old code from main widget after Phase 1+2 extraction
**Effort:** 30-45 minutes
**Status:** READY FOR EXECUTION

---

## 🎯 Objective

**Current:** Main widget = 5,571 LOC (new imports + old code)
**Target:** Main widget = ~3,500 LOC (44% reduction)
**Method:** Delete extracted code that's now in separate panel files

---

## 📋 Code Sections to Delete

### Section 1: Timeline Overview (~184 LOC)

**Deleted:** Lines 1459-1642
**Replacement:** 2-line comment

**Methods to remove:**
- `_buildCompactTimelineOverview()` (25 LOC)
- `_buildTrackList()` (84 LOC)
- `_buildMixerTrackItem()` (40 LOC)
- `_buildTrackListItem()` (25 LOC)
- `_buildTimelineVisualization()` (10 LOC)

**Status:** ✅ DONE (replaced with comment)

---

### Section 2: Piano Roll (~98 LOC)

**Deleted:** Lines 1462-1559 (after Section 1 removal)
**Replacement:** 2-line comment

**Methods to remove:**
- `_buildMidiPianoRoll()` (98 LOC)

**Status:** ✅ DONE (replaced with comment)

---

### Section 3: Clip Properties + Fades (~131 LOC)

**Deleted:** Lines 1467-1597 (after previous removals)
**Replacement:** 2-line comment

**Methods to remove:**
- `_buildCompactClipProperties()` (30 LOC)
- `_buildNoClipSelected()` (56 LOC)
- `_buildPropertyRow()` (27 LOC)
- `_buildCompactFadeEditor()` (10 LOC)

**Status:** ✅ DONE (replaced with comment)

---

### Section 4: Grid Settings (~580 LOC) — LARGEST

**To Delete:** Lines ~1471-2050
**Replacement:** 2-line comment

**Methods to remove:**
- `_buildCompactGridSettings()` (69 LOC)
- `_buildSubSectionHeader()` (11 LOC)
- `_buildTempoControl()` (76 LOC)
- `_showTempoEditDialog()` (49 LOC)
- `_buildTimeSignatureControl()` (46 LOC)
- `_buildTimeSignatureDropdown()` (28 LOC)
- `_buildTimeSignaturePreset()` (31 LOC)
- `_buildGridToggle()` (67 LOC)
- `_buildGridResolutionSelector()` (81 LOC)
- `_buildSnapIndicator()` (69 LOC)
- `_snapValueToLabel()` (9 LOC)

**Status:** ⏳ TODO (next)

---

### Section 5: Painter Classes (~155 LOC)

**Classes to Delete:**

**_TimelineOverviewPainter:**
- Lines: ~4729-4812 (~84 LOC)
- Status: Extracted to timeline_overview_panel.dart

**_GridPreviewPainter:**
- Lines: ~5326-5385 (~60 LOC)
- Status: Extracted to grid_settings_panel.dart (renamed to GridPreviewPainter)

**Status:** ⏳ TODO

---

### Section 6: EditableClipPanel Class (~320 LOC)

**To Delete:** Lines ~4973-5293

**Classes:**
- `_EditableClipPanel` (StatefulWidget)
- `_EditableClipPanelState`

**Status:** Extracted to clip_properties_panel.dart (renamed to EditableClipPanel)

**Status:** ⏳ TODO

---

## 🔧 Execution Steps

### Step 1: Verify Backup Exists ✅

```bash
ls -lh flutter_ui/lib/widgets/lower_zone/daw_lower_zone_widget.dart.backup_2026_01_26
```

**Confirmed:** ✅ Backup created

---

### Step 2: Delete Grid Settings Section

**Command:**
```bash
# Delete lines 1471-2050 (Grid Settings)
sed -i.tmp '1471,2050d' daw_lower_zone_widget.dart

# Add replacement comment at line 1471
sed -i.tmp '1471i\
  // ✅ P0.1: Grid Settings extracted to daw/edit/grid_settings_panel.dart\
  // Old code removed (was lines 1471-2050, ~580 LOC)
' daw_lower_zone_widget.dart
```

**Verification:**
```bash
flutter analyze lib/widgets/lower_zone/daw_lower_zone_widget.dart
```

---

### Step 3: Delete Painter Classes

**_TimelineOverviewPainter (lines ~4729-4812):**
```bash
# Find exact lines first
grep -n "class _TimelineOverviewPainter" daw_lower_zone_widget.dart
# Delete range
sed -i.tmp 'XXX,YYYd' daw_lower_zone_widget.dart
```

**_GridPreviewPainter (lines ~5326-5385):**
```bash
# Find exact lines first
grep -n "class _GridPreviewPainter" daw_lower_zone_widget.dart
# Delete range
sed -i.tmp 'XXX,YYYd' daw_lower_zone_widget.dart
```

---

### Step 4: Delete EditableClipPanel Class

**Lines ~4973-5293:**
```bash
# Find exact lines first
grep -n "class _EditableClipPanel" daw_lower_zone_widget.dart
# Delete range (including both class definitions)
sed -i.tmp 'XXX,YYYd' daw_lower_zone_widget.dart
```

---

### Step 5: Verify After Each Deletion

**After each delete:**
```bash
flutter analyze lib/widgets/lower_zone/daw_lower_zone_widget.dart
# Must show: No issues found!
```

**If errors:** Restore from backup and retry

---

### Step 6: Check Final Size

```bash
wc -l daw_lower_zone_widget.dart
# Expected: ~3,500 LOC (down from 5,571)
```

---

## ⚠️ Safety Protocol

**Before ANY deletion:**
1. ✅ Backup exists
2. Verify line numbers are correct
3. Delete ONE section at a time
4. Run `flutter analyze` after EACH deletion
5. If error → restore backup immediately

**Never delete multiple sections without verification between.**

---

## 📊 Expected Results

**Before Cleanup:**
- Main widget: 5,571 LOC
- Extracted panels: 8 files, 2,413 LOC
- Duplication: ~2,000 LOC (old code still in main)

**After Cleanup:**
- Main widget: ~3,500 LOC
- Extracted panels: 8 files, 2,413 LOC
- Duplication: 0 LOC
- Net reduction: ~2,040 LOC (37%)

---

## ✅ Cleanup Checklist

**Preparation:**
- [x] Backup created
- [ ] Line numbers confirmed (grep -n)
- [ ] sed commands tested on small section first

**Execution:**
- [ ] Delete Grid Settings (~580 LOC)
- [ ] Verify flutter analyze
- [ ] Delete _TimelineOverviewPainter (~84 LOC)
- [ ] Verify flutter analyze
- [ ] Delete _GridPreviewPainter (~60 LOC)
- [ ] Verify flutter analyze
- [ ] Delete _EditableClipPanel (~320 LOC)
- [ ] Verify flutter analyze

**Verification:**
- [ ] `flutter analyze` passes (0 errors)
- [ ] Main widget size ~3,500 LOC
- [ ] No unused imports
- [ ] No orphaned code

---

## 🎯 Alternative: Manual Deletion (Safer)

**If sed is risky, use Edit tool:**

1. Read section to delete
2. Use Edit tool to replace with comment
3. Verify after each
4. Repeat for all sections

**Effort:** Same (~30-45 min)
**Safety:** Higher (Edit tool validates)

---

**Plan Complete — Execute in Next Session or Continue Now**

**Estimated:** 30-45 minutes for complete cleanup

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>

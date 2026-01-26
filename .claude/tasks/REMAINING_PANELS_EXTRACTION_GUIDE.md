# Remaining Panels Extraction Guide

**Created:** 2026-01-26
**Status:** Roadmap for Phases 3-5
**Remaining:** 11 panels (~2,800 LOC)

---

## 📊 Current Progress

**Completed (9/20 panels, 45%):**
- ✅ BROWSE: 4/4 (Presets, Plugins, History, Files)
- ✅ EDIT: 4/4 (Timeline, Grid, Piano Roll, Clip)
- ✅ MIX: 1/4 (Mixer)

**Main Widget:** 4,202 LOC (down from 5,540)
**Reduction:** 24% (after BROWSE cleanup)

---

## 🎯 Phase 3: MIX Panels (3 remaining)

### Panel: Sends ✅ DONE (wrapper)

**File:** `daw/mix/sends_panel.dart` (25 LOC)
**Status:** Created

---

### Panel: Pan (~260 LOC) — NEXT

**Location:** Lines 1471-1730
**Complexity:** MEDIUM (pan law, stereo width)

**Components:**
- Pan law chips (0dB, -3dB, -4.5dB, -6dB)
- Mono/Stereo panner display
- Large knobs for L/R pan
- Stereo width visualization
- `_StereoWidthPainter` class (find around line 5xxx)

**State:**
- `_selectedPanLaw` (String, default '-3dB')

**Dependencies:**
- `MixerProvider` ✅
- `LargeKnob` widget ✅
- `NativeFFI.instance.stereoImagerSetPanLaw()` ✅

**Target:** `daw/mix/pan_panel.dart` (~300 LOC)

---

### Panel: Automation (~270 LOC)

**Location:** Lines 1731-2000 (approx)
**Complexity:** MEDIUM (curve editor)

**Components:**
- Automation mode buttons (Read, Write, Touch, Latch)
- Parameter selector dropdown
- Curve shape selector
- Add/remove points UI
- Visual curve display

**Target:** `daw/mix/automation_panel.dart` (~300 LOC)

---

## 🎯 Phase 4: PROCESS Panels (4 remaining)

### Panels: EQ, Comp, Limiter (wrappers)

**Effort:** 15 min each (~45 min total)

**Pattern:**
```dart
class EqPanel extends StatelessWidget {
  final int? selectedTrackId;
  const EqPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return buildEmptyState(
        icon: Icons.equalizer,
        title: 'No Track Selected',
        subtitle: 'Select a track to open EQ',
      );
    }
    return FabFilterEqPanel(trackId: selectedTrackId!);
  }
}
```

**Files:**
- `daw/process/eq_panel.dart` (~50 LOC)
- `daw/process/comp_panel.dart` (~50 LOC)
- `daw/process/limiter_panel.dart` (~50 LOC)

---

### Panel: FX Chain (~800 LOC)

**Location:** Lines ~3400-4200
**Complexity:** HIGH (drag-drop, visual chain)

**Components:**
- Signal flow visualization
- Processor cards with drag-drop
- Add processor menu
- Chain bypass toggle
- Copy/paste chain
- Integration with DspChainProvider

**Target:** `daw/process/fx_chain_panel.dart` (~850 LOC)

---

## 🎯 Phase 5: DELIVER Panels (4 panels)

### Panel: Export (~200 LOC)

**Wrapper for export_panels.dart widgets**

**Target:** `daw/deliver/export_panel.dart` (~200 LOC)

---

### Panel: Stems (~250 LOC)

**Components:**
- Track/bus selection checkboxes
- Format selector
- Export button with progress
- Uses `DawStemsPanel` from export_panels.dart

**Target:** `daw/deliver/stems_panel.dart` (~250 LOC)

---

### Panel: Bounce (~250 LOC)

**Components:**
- Format/SR selection
- Normalize options (Peak, LUFS)
- Export button
- Uses `DawBouncePanel` from export_panels.dart

**Target:** `daw/deliver/bounce_panel.dart` (~250 LOC)

---

### Panel: Archive (~200 LOC)

**Location:** Lines ~3630-3830
**Complexity:** MEDIUM

**Components:**
- Include options (audio, presets, plugins)
- Compress toggle
- Export button with progress
- Uses `ProjectArchiveService`

**Target:** `daw/deliver/archive_panel.dart` (~200 LOC)

---

## 📋 Extraction Template

**For Each Panel:**

1. **Identify scope** (5 min)
   ```bash
   grep -n "Widget _buildXxxPanel" daw_lower_zone_widget.dart
   grep -n "_xxx\|_buildXxx" daw_lower_zone_widget.dart
   ```

2. **Create panel file** (10-30 min)
   - Use template from existing panels
   - Copy all helpers
   - Copy state variables
   - Fix imports

3. **Verify** (2 min)
   ```bash
   flutter analyze lib/widgets/lower_zone/daw/.../xxx_panel.dart
   ```

4. **Update main widget** (5 min)
   - Add import
   - Replace builder

5. **Verify integration** (2 min)
   ```bash
   flutter analyze lib/widgets/lower_zone/daw_lower_zone_widget.dart
   ```

---

## 📊 Effort Estimates

| Phase | Panels | LOC | Effort |
|-------|--------|-----|--------|
| **3: MIX** | 2 | ~560 | 1.5h |
| **4: PROCESS** | 4 | ~1,000 | 2h |
| **5: DELIVER** | 4 | ~900 | 2h |
| **Total** | **10** | **~2,460** | **5.5h** |

**After all extractions:**
- Main widget: ~400 LOC ✅ TARGET
- Total reduction: 93%

---

## ✅ Success Criteria

**For P0.1 Complete:**
- [ ] 20/20 panels extracted
- [ ] Main widget < 500 LOC
- [ ] All old code removed
- [ ] `flutter analyze` passes (0 errors)
- [ ] All 20 panels manually tested

---

**Guide Complete — Execute in Next 2-3 Sessions**

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>

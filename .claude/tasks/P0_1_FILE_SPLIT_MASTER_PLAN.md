# P0.1: File Split Master Plan — Phased Extraction

**Created:** 2026-01-26
**Scope:** Split `daw_lower_zone_widget.dart` (5,540 LOC) into 20+ modular files
**Effort:** 2-3 weeks (phased approach)
**Status:** Phase 1 Started (BROWSE extraction)

---

## 🎯 Strategy — Phased Extraction with Continuous Verification

**Principle:** ULTIMATIVNO, nikad najjednostavnije
- Extract complete panels (not partial)
- Include ALL helper methods
- Include ALL state variables
- Include ALL dialogs
- Verify each panel independently before moving on

**Safety:** Zero downtime, zero regressions
- One panel at a time
- `flutter analyze` after each extraction
- Keep main widget functional at all times
- Test each panel after extraction

---

## 📊 Extraction Manifest

### Current State (Before)

**File:** `daw_lower_zone_widget.dart`
- **Total:** 5,540 LOC
- **Super-tabs:** 5 (BROWSE, EDIT, MIX, PROCESS, DELIVER)
- **Sub-tabs:** 20 (4 per super-tab)
- **Helper methods:** ~80
- **State variables:** ~15
- **Dialog widgets:** ~3

---

### Target State (After)

**Main Widget:** `daw_lower_zone_widget.dart` (~400 LOC)
- Container only
- Tab routing logic
- Minimal state (tab selection, expand/collapse)

**Panel Files:** 20+ files (~4,800 LOC total)
- Each panel self-contained
- All helpers included
- All state encapsulated

**Shared Files:** 2-3 files (~300 LOC)
- Common widgets
- Shared utilities
- Base classes

---

## 📋 Phase Breakdown

### Phase 1: BROWSE Panels (Week 1) — IN PROGRESS

**Target LOC:** ~1,200

| Panel | Status | LOC | Helpers | State | Dialogs |
|-------|--------|-----|---------|-------|---------|
| **Files** | ✅ EXISTS | 800 | — | — | — |
| **Presets** | ✅ DONE | 470 | 7 | 1 | 1 |
| **Plugins** | 📋 TODO | 650 | 8 | 2 | 0 |
| **History** | 📋 TODO | 280 | 4 | 0 | 0 |

**Files:**
- ✅ `daw_files_browser.dart` — Already exists (moved from root)
- ✅ `daw/browse/track_presets_panel.dart` — Extracted (470 LOC)
- 📋 `daw/browse/plugins_scanner_panel.dart` — TODO
- 📋 `daw/browse/history_panel.dart` — TODO

**Dependencies:**
- `TrackPresetService` ✅
- `PluginProvider` (for plugins)
- `UndoManager` (for history)

**Verification:**
- [x] Presets panel: flutter analyze passes
- [ ] Plugins panel: TBD
- [ ] History panel: TBD
- [ ] Integration test: All 4 BROWSE tabs work

---

### Phase 2: EDIT Panels (Week 2)

**Target LOC:** ~1,400

| Panel | LOC | Helpers | State | Complexity |
|-------|-----|---------|-------|------------|
| **Timeline** | 600 | 6 | 3 | Medium |
| **Piano Roll** | — | — | — | **EXISTS** (separate widget) |
| **Fades** | — | — | — | **EXISTS** (CrossfadeEditor) |
| **Grid** | 800 | 10 | 5 | High |

**Files:**
- `daw/edit/timeline_overview_panel.dart` — NEW
- Piano Roll — Already exists
- Crossfade Editor — Already exists
- `daw/edit/grid_settings_panel.dart` — NEW (includes tempo, time sig, snap)

**Dependencies:**
- `MixerProvider` (for timeline)
- Grid settings panel (current inline, needs extraction)

---

### Phase 3: MIX Panels (Week 2)

**Target LOC:** ~900

| Panel | LOC | Helpers | State | Complexity |
|-------|-----|---------|-------|------------|
| **Mixer** | 300 | 3 | 1 | Low (wrapper) |
| **Sends** | 400 | 5 | 2 | Medium |
| **Pan** | 500 | 8 | 4 | High |
| **Automation** | 600 | 10 | 5 | High |

**Files:**
- `daw/mix/mixer_panel.dart` — Wrapper for UltimateMixer
- `daw/mix/sends_panel.dart` — Currently RoutingMatrixPanel wrapper
- `daw/mix/pan_panel.dart` — Pan law, width controls
- `daw/mix/automation_panel.dart` — Automation curve editor

**Dependencies:**
- `MixerProvider` ✅
- `UltimateMixer` widget ✅
- `RoutingMatrixPanel` widget ✅

---

### Phase 4: PROCESS Panels (Week 3)

**Target LOC:** ~1,000

| Panel | LOC | Helpers | State | Complexity |
|-------|-----|---------|-------|------------|
| **EQ** | 200 | 2 | 1 | Low (wrapper) |
| **Comp** | 200 | 2 | 1 | Low (wrapper) |
| **Limiter** | 200 | 2 | 1 | Low (wrapper) |
| **FX Chain** | 800 | 12 | 4 | High |

**Files:**
- `daw/process/eq_panel.dart` — Wrapper for FabFilterEqPanel
- `daw/process/comp_panel.dart` — Wrapper for FabFilterCompressorPanel
- `daw/process/limiter_panel.dart` — Wrapper for FabFilterLimiterPanel
- `daw/process/fx_chain_panel.dart` — Visual chain editor

**Dependencies:**
- `DspChainProvider` ✅
- FabFilter panels ✅

---

### Phase 5: DELIVER Panels (Week 3)

**Target LOC:** ~1,200

| Panel | LOC | Helpers | State | Complexity |
|-------|-----|---------|-------|------------|
| **Export** | 300 | 4 | 2 | Medium |
| **Stems** | 400 | 6 | 3 | Medium |
| **Bounce** | 400 | 5 | 3 | Medium |
| **Archive** | 300 | 4 | 2 | Medium |

**Files:**
- `daw/deliver/quick_export_panel.dart` — One-click export
- `daw/deliver/stems_panel.dart` — Multi-track export
- `daw/deliver/bounce_panel.dart` — Master bounce
- `daw/deliver/archive_panel.dart` — Project ZIP

**Dependencies:**
- `export_panels.dart` (may need to extract from it)
- `ProjectArchiveService` ✅

---

### Phase 6: Main Widget Reduction (Week 3)

**Target:** Reduce `daw_lower_zone_widget.dart` to ~400 LOC

**Remaining Code:**
- Widget class definition
- Controller integration
- Tab routing (_getContentForCurrentTab)
- Action strip integration
- Resize handle
- Context bar integration

**Removed Code:**
- All panel builders (moved to separate files)
- All helper methods (moved with panels)
- All state variables (encapsulated in panels)
- All dialogs (moved with panels)

---

## 🔄 Extraction Protocol (Per Panel)

### Step 1: Identify Scope

```bash
# Find panel builder method
grep -n "Widget _buildXxxPanel" file.dart

# Find all related methods
grep -n "_xxx\|_buildXxx" file.dart

# Find all related state
grep -n "String\? _selected\|bool _\|List _" file.dart

# Find all related dialogs
grep -n "class _Xxx" file.dart
```

---

### Step 2: Create Panel File

**Template:**
```dart
/// DAW [Panel Name] Panel (P0.1 Extracted)
///
/// [Description]
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines [start]-[end] (~[LOC] LOC)
library;

import 'dart:xxx';
import 'package:flutter/material.dart';
import '../../lower_zone_types.dart'; // Colors, constants
import '../../../../services/xxx.dart'; // Services
import '../../../../providers/xxx.dart'; // Providers

class [PanelName]Panel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const [PanelName]Panel({super.key, this.onAction});

  @override
  State<[PanelName]Panel> createState() => _[PanelName]PanelState();
}

class _[PanelName]PanelState extends State<[PanelName]Panel> {
  // State variables from original

  @override
  Widget build(BuildContext context) {
    // Extracted builder code
  }

  // All helper methods
  // All dialogs (as separate classes at end of file)
}
```

---

### Step 3: Extract Code

1. Copy panel builder method → `build()`
2. Copy all helper methods (preserve order)
3. Copy all state variables → class fields
4. Copy all related dialogs → bottom of file
5. Fix imports (adjust `../` path depth)
6. Add widget parameters for callbacks

---

### Step 4: Verify

```bash
cd flutter_ui
flutter analyze lib/widgets/lower_zone/daw/[folder]/[panel].dart
# Must pass with 0 errors
```

---

### Step 5: Update Main Widget

Replace panel builder with import + instantiation:

```dart
// Before:
Widget _buildXxxPanel() {
  // 200 lines of code
}

// After:
import 'daw/xxx/xxx_panel.dart';

Widget _buildXxxPanel() => XxxPanel(onAction: widget.onDspAction);
```

---

### Step 6: Integration Test

```bash
flutter analyze lib/widgets/lower_zone/daw_lower_zone_widget.dart
# Must pass
```

Manual test:
1. Run app
2. Navigate to panel
3. Verify functionality
4. Check for regressions

---

## ✅ Extraction Checklist (Per Panel)

- [ ] Scope identified (methods, state, dialogs)
- [ ] Panel file created
- [ ] All code extracted (no leftovers)
- [ ] Imports fixed (correct path depth)
- [ ] `flutter analyze` passes (panel file)
- [ ] Main widget updated (import + instantiation)
- [ ] `flutter analyze` passes (main widget)
- [ ] Manual test (panel works)
- [ ] No regressions (other panels still work)

---

## 📊 Progress Tracking

### Phase 1: BROWSE (Week 1)

| Panel | Extraction | Verification | Integration | Status |
|-------|-----------|--------------|-------------|--------|
| Files | N/A | N/A | N/A | ✅ Pre-existing |
| Presets | ✅ Done | ✅ Pass | 📋 TODO | 50% |
| Plugins | 📋 TODO | — | — | 0% |
| History | 📋 TODO | — | — | 0% |

**Phase 1 Progress:** 1/4 panels (25%)

---

### Phase 2-5: Remaining (Weeks 2-3)

**Pending:** 16 panels

**Estimated:**
- Week 2: EDIT (4 panels) + MIX (4 panels) = 8 panels
- Week 3: PROCESS (4 panels) + DELIVER (4 panels) = 8 panels
- Week 3 end: Main widget reduction

---

## 🚨 Risk Mitigation

### Risk 1: Breaking Callbacks

**Mitigation:** Add callback parameters to all panels
**Pattern:**
```dart
final void Function(String action, Map<String, dynamic> data)? onAction;
```

---

### Risk 2: Missing Dependencies

**Mitigation:** Preserve ALL imports from original
**Verification:** `flutter analyze` must pass

---

### Risk 3: State Loss

**Mitigation:** Encapsulate state in panel widgets
**Pattern:** StatefulWidget for all panels with state

---

### Risk 4: Import Path Errors

**Mitigation:** Calculate correct `../` depth per folder
**Depths:**
- `daw/browse/` → `../../` (lower_zone_types), `../../../../` (services)
- `daw/edit/` → same
- `daw/mix/` → same
- `daw/process/` → same
- `daw/deliver/` → same

---

## ✅ Definition of Done (Global)

**For P0.1 Complete:**

- [ ] All 20 panels extracted
- [ ] Main widget < 500 LOC
- [ ] `flutter analyze` passes (0 errors)
- [ ] All 20 panels manually tested
- [ ] No regressions
- [ ] Documentation updated (this plan)

---

## 📝 Next Steps (Immediate)

1. ✅ Extract Presets panel (DONE)
2. 📋 Extract Plugins panel (~650 LOC)
3. 📋 Extract History panel (~280 LOC)
4. 📋 Update main widget (replace builders with panel imports)
5. 📋 Verify BROWSE super-tab works
6. 📋 Move to Phase 2 (EDIT panels)

---

**Plan Status:** ACTIVE
**Next Session:** Continue Phase 1 (Plugins + History extraction)

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>

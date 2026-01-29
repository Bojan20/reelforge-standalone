# FluxForge Studio — MASTER TODO

**Updated:** 2026-01-29
**Status:** P0-P3 Complete (167/168 = 99%), P4 Backlog (8 items)

---

## 📊 OVERALL STATUS

**Updated:** 2026-01-29 (SlotLab Analysis Complete)

| Priority | Previous | SlotLab | New Total | Done | Remaining |
|----------|----------|---------|-----------|------|-----------|
| 🔴 P0 Critical | 13 | +13 | **26** | 13 | **13** |
| 🟠 P1 High | 15 | +20 | **35** | 15 | **20** |
| 🟡 P2 Medium | 22 | +13 | **35** | 21 | **14** |
| 🟢 P3 Low | 14 | +3 | **17** | 14 | **3** |
| ⚪ P4 Future | 8 | +18 | **26** | 0 | **26** |
| **TOTAL** | **72** | **+67** | **139** | **63** | **76** |

**Progress:** 45% Complete (P0-P3), 76 items remaining (50 active work + 26 backlog)

---

## 🎰 SLOTLAB SECTION — ULTIMATE ANALYSIS (2026-01-29)

**Source:** `.claude/reviews/SLOTLAB_ULTIMATE_ANALYSIS_2026_01_29.md`
**Analyzed:** 18,854 LOC (4 panels, 9 roles, horizontal integration)
**Gaps Found:** 67 items (13 P0, 20 P1, 13 P2, 3 P3, 18 P4)
**Effort:** 21-26 weeks total, 4-5 weeks for P0

---

## 🔴 P0 — CRITICAL (SlotLab)

### [SlotLab: Integration] — Data Sync Bugs (2 items, 4 hours)

#### SL-INT-P0.1: Fix Event List Provider Mismatch

**Problem:** Lower Zone Event List panel uses `AutoEventBuilderProvider.committedEvents` instead of `MiddlewareProvider.compositeEvents`

**Impact:** TWO SEPARATE EVENT LISTS — not synchronized!
- Desni Panel Events Folder shows MiddlewareProvider events ✅
- Lower Zone Event List shows AutoEventBuilderProvider events ❌
- Events created in one panel don't appear in the other

**Effort:** 2 hours (actual: 1 hour)
**Assigned To:** Technical Director
**Status:** ✅ COMPLETE (2026-01-29, commit 39912125)

**Files Modified:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/event_list_panel.dart` — Provider migration complete

**Implementation Steps:**
1. Change import from `auto_event_builder_provider.dart` to `middleware_provider.dart`
2. Replace `Consumer<AutoEventBuilderProvider>` with `Consumer<MiddlewareProvider>`
3. Change `provider.committedEvents` to `middleware.compositeEvents`
4. Update model type from `CommittedEvent` to `SlotCompositeEvent`
5. Update all CRUD operations to call middleware methods

**Code Changes:**
```dart
// BEFORE:
import '../../../providers/auto_event_builder_provider.dart';

Consumer<AutoEventBuilderProvider>(
  builder: (context, provider, _) {
    final events = provider.committedEvents;
  },
)

// AFTER:
import '../../../providers/middleware_provider.dart';

Consumer<MiddlewareProvider>(
  builder: (context, middleware, _) {
    final events = middleware.compositeEvents;
  },
)
```

**Definition of Done:**
- [ ] Event List uses MiddlewareProvider.compositeEvents
- [ ] Events in Lower Zone match Events Panel (desni panel)
- [ ] Bulk actions call middleware CRUD methods
- [ ] flutter analyze passes
- [ ] Manual test: Create event in Desni Panel → appears in Lower Zone

---

#### SL-INT-P0.2: Remove AutoEventBuilderProvider

**Problem:** AutoEventBuilderProvider is redundant, causes data duplication

**Impact:**
- Maintains separate event list (committedEvents)
- Causes sync bugs with MiddlewareProvider
- Adds complexity with no benefit

**Effort:** 2 hours
**Assigned To:** Technical Director
**Status:** ❌ NOT STARTED
**Depends On:** SL-INT-P0.1

**Files to Delete:**
- `flutter_ui/lib/providers/auto_event_builder_provider.dart` (~500 LOC)

**Files to Modify:**
- `flutter_ui/lib/main.dart` — Remove from MultiProvider
- All references to AutoEventBuilderProvider → Use MiddlewareProvider

**Implementation Steps:**
1. Verify SL-INT-P0.1 complete (Event List uses MiddlewareProvider)
2. Grep for all AutoEventBuilderProvider references
3. Replace with MiddlewareProvider
4. Delete auto_event_builder_provider.dart file
5. Remove from MultiProvider in main.dart
6. Test all event creation flows

**Definition of Done:**
- [ ] AutoEventBuilderProvider file deleted
- [ ] No references remain in codebase
- [ ] All event flows use MiddlewareProvider
- [ ] flutter analyze passes
- [ ] No regressions in event creation

---

### [SlotLab: Lower Zone] — Architecture (1 item, 1 week)

#### SL-LZ-P0.2: Restructure to Super-Tabs + Sub-Panels

**Problem:** Lower Zone has 8 flat tabs instead of 7 super-tabs with sub-panels (per CLAUDE.md spec)

**Impact:**
- Poor organization (8 tabs without grouping)
- Doesn't match specification (~30% coverage)
- Missing 3 entire super-tabs (BAKE, ENGINE, MUSIC/ALE)
- Hard to navigate, confusing UX

**Effort:** 1 week
**Assigned To:** Technical Director, UI/UX Expert
**Status:** ❌ NOT STARTED

**Current:** 8 flat tabs (Timeline, Command, Events, Meters, Comp, Limiter, Gate, Reverb)

**Target:** 7 super-tabs:
```
1. STAGES [Ctrl+Shift+T] → Timeline, Event Debug
2. EVENTS [Ctrl+Shift+E] → Event List, RTPC, Composite Editor
3. MIX [Ctrl+Shift+X] → Bus Hierarchy, Aux Sends, Meters
4. MUSIC/ALE [Ctrl+Shift+A] → ALE Rules, Signals, Transitions
5. DSP → EQ, Compressor, Limiter, Gate, Reverb, Delay, Saturation
6. BAKE → Batch Export, Validation, Package
7. ENGINE [Ctrl+Shift+G] → Profiler, Resources, Stage Ingest
[+] MENU → Game Config, AutoSpatial, Scenarios, Command Builder
```

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/lower_zone_types.dart` (~200 LOC)
- `flutter_ui/lib/widgets/slot_lab/lower_zone/lower_zone_context_bar.dart` (~400 LOC)

**Files to Modify:**
- `flutter_ui/lib/controllers/slot_lab/lower_zone_controller.dart` — Add super-tab + sub-tab state (~200 LOC)
- `flutter_ui/lib/widgets/slot_lab/lower_zone/lower_zone.dart` — Use context bar (~200 LOC)

**Implementation Steps:**
1. Create lower_zone_types.dart with super-tab/sub-tab enums
2. Create lower_zone_context_bar.dart with two-row header (super + sub tabs)
3. Update controller to manage super-tab + sub-tab state
4. Update lower_zone.dart to use new context bar
5. Map existing 8 tabs to new structure
6. Add keyboard shortcuts (Ctrl+Shift+T/E/X/A/G)
7. Test all tab switches
8. Add state persistence (active super/sub tab)

**Code Example:**
```dart
// lower_zone_types.dart
enum SuperTab { stages, events, mix, musicAle, dsp, bake, engine, menu }
enum StagesSubTab { timeline, eventDebug }
enum EventsSubTab { eventList, rtpc, compositeEditor }
// ... etc for all super-tabs

// lower_zone_context_bar.dart
class LowerZoneContextBar extends StatelessWidget {
  final SuperTab activeSuper;
  final int activeSubIndex;
  final Function(SuperTab) onSuperTabChange;
  final Function(int) onSubTabChange;
  final bool isExpanded;

  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Super-tabs (7 + menu)
        _buildSuperTabRow(),
        // Row 2: Sub-tabs (dynamic based on activeSuper)
        if (isExpanded) _buildSubTabRow(),
      ],
    );
  }
}
```

**Definition of Done:**
- [ ] 7 super-tabs + [+] menu implemented
- [ ] Two-row header (super-tabs + sub-tabs)
- [ ] Sub-tabs dynamic based on active super-tab
- [ ] All existing 8 tabs integrated into new structure
- [ ] Keyboard shortcuts working (Ctrl+Shift+T/E/X/A/G)
- [ ] State persists (active super/sub tab)
- [ ] flutter analyze passes
- [ ] No visual regressions

---

### [SlotLab: Lower Zone] — Missing Panels (2 items, 6 days)

#### SL-LZ-P0.3: Add Composite Editor Sub-Panel

**Problem:** No dedicated panel for editing composite events in Lower Zone

**Impact:** Must use Desni Panel Events folder — Lower Zone incomplete for event editing workflow

**Effort:** 3 days
**Assigned To:** Audio Middleware Architect
**Status:** ❌ NOT STARTED
**Depends On:** SL-LZ-P0.2 (super-tab structure)

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/events/composite_editor_panel.dart` (~800 LOC)

**Implementation Steps:**
1. Create CompositeEditorPanel widget
2. Accept selectedEventId parameter from parent
3. Fetch event from MiddlewareProvider.compositeEvents
4. Build 3 sections: Event Properties, Layers, Trigger Stages
5. Add interactive layer editor (volume/pan/delay sliders)
6. Add layer actions (add, delete, preview, mute)
7. Add trigger stages editor (add/remove stages)
8. Wire up to MiddlewareProvider CRUD methods
9. Add to EVENTS super-tab as "Composite Editor" sub-panel
10. Test editing workflow

**Code Example:**
```dart
class CompositeEditorPanel extends StatelessWidget {
  final String? selectedEventId;

  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        if (selectedEventId == null) {
          return _buildEmptyState('Select an event from Events tab');
        }

        final event = middleware.compositeEvents
          .where((e) => e.id == selectedEventId)
          .firstOrNull;

        if (event == null) {
          return _buildEmptyState('Event not found');
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEventPropertiesSection(event, middleware),
              SizedBox(height: 16),
              Divider(),
              _buildLayersSection(event, middleware),
              SizedBox(height: 16),
              Divider(),
              _buildTriggerStagesSection(event, middleware),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayersSection(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('LAYERS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Spacer(),
            OutlinedButton.icon(
              icon: Icon(Icons.add, size: 16),
              label: Text('Add Layer'),
              onPressed: () async {
                final audioPath = await AudioWaveformPickerDialog.show(context);
                if (audioPath != null) {
                  final newLayer = SlotEventLayer(
                    id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
                    name: 'Layer ${event.layers.length + 1}',
                    audioPath: audioPath,
                    volume: 1.0,
                    pan: 0.0,
                    offsetMs: 0.0,
                  );
                  middleware.addLayerToEvent(event.id, newLayer);
                }
              },
            ),
          ],
        ),
        SizedBox(height: 8),
        for (final layer in event.layers)
          _buildInteractiveLayerItem(layer, event, middleware),
      ],
    );
  }

  Widget _buildInteractiveLayerItem(SlotEventLayer layer, SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFF16161C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Name + filename
          Row(
            children: [
              Icon(Icons.audiotrack, size: 14, color: Colors.white54),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(layer.name, style: TextStyle(fontSize: 11, color: Colors.white)),
                    Text(layer.audioPath.split('/').last, style: TextStyle(fontSize: 9, color: Colors.white38)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(layer.muted ? Icons.volume_off : Icons.volume_up, size: 14),
                onPressed: () => middleware.updateEventLayer(event.id, layer.copyWith(muted: !layer.muted)),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 14, color: Colors.white24),
                onPressed: () => middleware.removeLayerFromEvent(event.id, layer.id),
              ),
            ],
          ),
          SizedBox(height: 8),
          // Row 2: Volume slider
          _buildParameterSlider('Volume', layer.volume, 0.0, 2.0, (v) {
            middleware.updateEventLayer(event.id, layer.copyWith(volume: v));
          }),
          // Row 3: Pan slider
          _buildParameterSlider('Pan', layer.pan, -1.0, 1.0, (v) {
            middleware.updateEventLayer(event.id, layer.copyWith(pan: v));
          }),
          // Row 4: Delay slider
          _buildParameterSlider('Delay', layer.offsetMs, 0.0, 2000.0, (v) {
            middleware.updateEventLayer(event.id, layer.copyWith(offsetMs: v));
          }),
        ],
      ),
    );
  }
}
```

**Definition of Done:**
- [ ] Panel displays selected event properties
- [ ] Interactive layer sliders (volume, pan, delay)
- [ ] Add/delete layer buttons
- [ ] Layer preview playback
- [ ] Trigger stages editor
- [ ] Real-time sync with MiddlewareProvider
- [ ] Integrated in EVENTS super-tab
- [ ] flutter analyze passes

---

#### SL-LZ-P0.4: Add Batch Export Sub-Panel

**Problem:** No export functionality in SlotLab Lower Zone

**Impact:** Can't export events/packages from SlotLab, must use external tools

**Effort:** 3 days
**Assigned To:** Tooling Developer, Producer
**Status:** ❌ NOT STARTED
**Depends On:** SL-LZ-P0.2 (super-tab structure)

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/bake/batch_export_panel.dart` (~700 LOC)

**Implementation Steps:**
1. Create BatchExportPanel widget
2. Add export type selector (Universal, Unity, Unreal, Howler)
3. Add event selection UI (all, selected, by category)
4. Add format settings (JSON schema, audio format, normalization)
5. Add export button with progress indicator
6. Wire to export services (UnityExporter, UnrealExporter, HowlerExporter)
7. Add FilePicker for save location
8. Add success/error feedback (SnackBar)
9. Integrate in BAKE super-tab
10. Test export workflow end-to-end

**Code Example:**
```dart
class BatchExportPanel extends StatefulWidget {
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        return Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Export type selector
              _buildExportTypeSelector(),
              SizedBox(height: 16),
              // Event selection
              _buildEventSelection(middleware.compositeEvents),
              SizedBox(height: 16),
              // Export settings
              _buildExportSettings(),
              Spacer(),
              // Export button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: _isExporting ? CircularProgressIndicator() : Icon(Icons.file_download),
                  label: Text(_isExporting ? 'Exporting...' : 'Export Package'),
                  onPressed: _isExporting ? null : _performExport,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _performExport() async {
    // 1. Get selected events
    // 2. Get export settings
    // 3. Show FilePicker for save location
    // 4. Call appropriate exporter (Unity/Unreal/Howler/Universal)
    // 5. Show progress
    // 6. Show success/error
  }
}
```

**Definition of Done:**
- [ ] Export type selector (4 platforms)
- [ ] Event selection checkboxes (all, selected, by category)
- [ ] Format settings (audio format, normalization, stems)
- [ ] Progress indicator during export
- [ ] FilePicker integration
- [ ] Success/error feedback
- [ ] Integrated in BAKE super-tab
- [ ] flutter analyze passes
- [ ] Manual test: Export package, verify contents

---

### [SlotLab: Desni Panel] — CRUD Operations (4 items, 1 week)

#### SL-RP-P0.1: Add Delete Event Button

**Problem:** No delete button in Events Folder — basic CRUD operation missing

**Impact:** Can't delete events from UI, must manually edit provider

**Effort:** 1 hour
**Assigned To:** UI/UX Expert
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:480-620`

**Implementation Steps:**
1. Add delete IconButton to event row
2. Add confirmation dialog
3. Call middleware.deleteCompositeEvent(eventId)
4. Clear selection if deleted event was selected
5. Add fade-out animation (optional)

**Code Changes:**
```dart
Widget _buildEventItem(SlotCompositeEvent event) {
  return Row(
    children: [
      // Existing: 3 columns (Name, Stage, Layers)
      // ...

      // NEW: Delete button
      IconButton(
        icon: Icon(Icons.delete_outline, size: 14, color: Colors.white24),
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('Delete Event'),
              content: Text('Delete "${event.name}"?'),
              actions: [
                TextButton(child: Text('Cancel'), onPressed: () => Navigator.pop(context, false)),
                TextButton(
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          );

          if (confirm == true) {
            final middleware = context.read<MiddlewareProvider>();
            middleware.deleteCompositeEvent(event.id);
            if (_selectedEventId == event.id) {
              _setSelectedEventId(null);
            }
          }
        },
      ),
    ],
  );
}
```

**Definition of Done:**
- [ ] Delete button appears on each event row
- [ ] Confirmation dialog before deletion
- [ ] Calls middleware.deleteCompositeEvent
- [ ] Clears selection if deleted
- [ ] flutter analyze passes

---

#### SL-RP-P0.2: Add Stage Editor Dialog

**Problem:** Can't modify trigger stages after event creation

**Impact:** Must delete and recreate event to change stage binding

**Effort:** 2 days
**Assigned To:** Audio Middleware Architect
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/stage_editor_dialog.dart` (~400 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:575-596` — Add edit icon

**Implementation Steps:**
1. Create StageEditorDialog widget
2. Display current trigger stages (removable list)
3. Add search field for stage selection
4. Display filtered stages as clickable chips
5. Add stages to event (click chip → add to list)
6. Remove stages (X button on list item)
7. Save button → middleware.updateCompositeEvent(event.copyWith(triggerStages: newStages))
8. Add edit icon to Stage column in Events Folder
9. Test editing workflow

**Code Example:** (See full implementation in FAZA 2.2 document)

**Definition of Done:**
- [ ] Dialog opens with current stages
- [ ] Can remove stages (X button)
- [ ] Can add stages (search + click)
- [ ] Search filters stage list
- [ ] Save updates event
- [ ] Integrated in Events Folder (edit icon)
- [ ] flutter analyze passes

---

#### SL-RP-P0.3: Add Layer Property Editor

**Problem:** Can't edit layer properties (volume, pan, delay, fade) in Selected Event editor

**Impact:** Critical for audio design — layers have no mix control

**Effort:** 3 days
**Assigned To:** Chief Audio Architect, Audio Designer
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:770-855`

**Implementation Steps:**
1. Enhance _buildLayerItem to show expandable properties
2. Add Volume slider (0-200%, default 100%)
3. Add Pan slider (L100-C-R100)
4. Add Delay slider (0-2000ms)
5. Add Fade In/Out sliders (0-1000ms)
6. Add Preview button (plays layer with current settings)
7. Wire sliders to middleware.updateEventLayer
8. Add compact/expanded toggle per layer
9. Test real-time parameter updates

**Code Example:** (See full implementation in FAZA 2.2 document)

**Definition of Done:**
- [ ] Volume slider (0-200%)
- [ ] Pan slider (L100-C-R100)
- [ ] Delay slider (0-2000ms)
- [ ] Fade In/Out sliders
- [ ] Preview button per layer
- [ ] Real-time sync with MiddlewareProvider
- [ ] Compact layout (fits in 300px panel width)
- [ ] flutter analyze passes

---

#### SL-RP-P0.4: Add "Add Layer" Button

**Problem:** No explicit button to add layer to event

**Impact:** Workflow unclear — users don't know how to add layers besides drag-drop

**Effort:** 1 day
**Assigned To:** UI/UX Expert
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:700-770`

**Implementation Steps:**
1. Add "+ Add Layer" button at bottom of layers list
2. Click → Open AudioWaveformPickerDialog
3. Create new SlotEventLayer with selected audio
4. Auto-name layer ("Layer 1", "Layer 2", etc.)
5. Call middleware.addLayerToEvent(eventId, newLayer)
6. Test workflow

**Code Example:** (See full implementation in FAZA 2.2 document)

**Definition of Done:**
- [ ] Button appears below layers list
- [ ] Opens AudioWaveformPickerDialog
- [ ] Creates layer with defaults (100% volume, center pan, no delay)
- [ ] Calls middleware.addLayerToEvent
- [ ] flutter analyze passes

---

### [SlotLab: Levi Panel] — Testing & Feedback (3 items, 4 days)

#### SL-LP-P0.1: Add Audio Preview Playback Button

**Problem:** Can't test audio sounds without triggering full slot spin

**Impact:** Slows down audio design workflow significantly

**Effort:** 2 days
**Assigned To:** Audio Designer, Tooling Developer
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart:300-400`

**Implementation Steps:**
1. Add play/stop IconButton per audio slot
2. Track _playingStage state
3. Click play → AudioPlaybackService.previewFile(audioPath, source: PlaybackSource.browser)
4. Click stop → AudioPlaybackService.stopAll()
5. Auto-stop previous when clicking another slot
6. Icon toggle (play_arrow ↔ stop)
7. Test preview playback

**Code Example:** (See full implementation in FAZA 2.1 document)

**Definition of Done:**
- [ ] Play button on assigned slots
- [ ] Click plays audio
- [ ] Icon toggles play/stop
- [ ] Stops previous audio
- [ ] Uses isolated Browser engine
- [ ] flutter analyze passes

---

#### SL-LP-P0.2: Add Section Completeness Indicator

**Problem:** No visual indication of which sections are 100% assigned

**Impact:** Can't track progress, might miss required stages

**Effort:** 1 day
**Assigned To:** Slot Game Designer, UI/UX Expert
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart:235-300`

**Implementation Steps:**
1. Calculate totalSlots per section (sum all group slots)
2. Calculate assignedCount (count assigned audioAssignments)
3. Calculate percentage (assignedCount / totalSlots × 100)
4. Add percentage badge to section header
5. Color-code: red<50%, orange 50-75%, blue 75-99%, green 100%
6. Add checkmark icon at 100%
7. Optional: Add progress bar below header
8. Test with various completion levels

**Code Example:** (See full implementation in FAZA 2.1 document)

**Definition of Done:**
- [ ] Percentage badge shows completion
- [ ] Color-coded by completion level
- [ ] Checkmark at 100%
- [ ] Optional progress bar
- [ ] Updates in real-time
- [ ] flutter analyze passes

---

#### SL-LP-P0.3: Add Batch Distribution Results Dialog

**Problem:** Unmatched files silently ignored when dropping folder

**Impact:** Incomplete audio packages, missing sounds

**Effort:** 1 day
**Assigned To:** Tooling Developer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/batch_distribution_dialog.dart` (~300 LOC)

**Files to Modify:**
- `flutter_ui/lib/screens/slot_lab_screen.dart:2382-2384` — Show dialog instead of debugPrint

**Implementation Steps:**
1. Create BatchDistributionDialog widget
2. Add summary section (total, matched, unmatched, success rate)
3. Add two tabs: Matched | Unmatched
4. Matched tab: file → stage list with green checkmarks
5. Unmatched tab: file list with reasons
6. Add "Manual Assign" button for unmatched files
7. Wire to onBatchDistribute callback
8. Test with folder containing mixed files

**Code Example:** (See full implementation in FAZA 2.1 document)

**Definition of Done:**
- [ ] Dialog shows after folder drop
- [ ] Summary: Total, Matched, Unmatched, Success Rate
- [ ] Matched/Unmatched tabs
- [ ] Manual assign button
- [ ] flutter analyze passes

---

---

## 🟠 P1 — HIGH PRIORITY (SlotLab)

**Total:** 20 items, ~6-7 weeks effort, ~3,300 LOC

**Top Priorities:**
1. **SL-INT-P1.1:** Visual feedback loop (2 days) — Audio assignment confirmation
2. **SL-LP-P1.1:** Waveform thumbnails in slots (3 days) — Visual identification
3. **SL-LP-P1.2:** Search/filter across 341 slots (2 days) — Navigation
4. **SL-RP-P1.1:** Event context menu (2 days) — Duplicate, export, test actions
5. **SL-LZ-P1.1:** Integrate 7 existing panels (1 day) — RTPC, Bus, Aux, ALE, Profiler, Stage Ingest, AutoSpatial

**Complete List:** See `.claude/reviews/SLOTLAB_ANALYSIS_FAZA_4_GAP_CONSOLIDATION.md` Section "P1 High"

**Quick Wins (< 2 days):**
- Integrate 7 panels (1 day)
- Selection state sync (1 day)
- Event search/filter (1 day)
- Test playback buttons (1 day)

---

## 🟡 P2 — MEDIUM PRIORITY (SlotLab)

**Total:** 13 items, ~4-5 weeks effort, ~3,580 LOC

**Categories:**
- Advanced editing (trim/fade controls)
- Bulk operations (multi-file actions)
- Metadata & quality reporting
- GDD advanced integration

**Complete List:** See `.claude/reviews/SLOTLAB_ANALYSIS_FAZA_4_GAP_CONSOLIDATION.md` Section "P2 Medium"

---

## 🟢 P3 — LOW PRIORITY (SlotLab)

**Total:** 3 items, ~1 week effort, ~800 LOC

1. Export preview (all assigned audio list)
2. Progress dashboard (donut chart)
3. File metadata display (duration, format, sample rate)

**Complete List:** See `.claude/reviews/SLOTLAB_ANALYSIS_FAZA_4_GAP_CONSOLIDATION.md` Section "P3 Low"

---

## ⚪ P4 — FUTURE BACKLOG (Global + SlotLab)

### P4.1: Linear Phase EQ Mode
- **Category:** DSP Enhancement
- **Impact:** FabFilter Pro-Q parity
- **Effort:** 2-3 weeks
- **Status:** Backlog
- **Notes:** Requires FIR filter implementation, zero-latency mode

---

### P4.2: Multiband Compression
- **Category:** DSP Enhancement
- **Impact:** FabFilter Pro-MB parity
- **Effort:** 2-3 weeks
- **Status:** Backlog
- **Notes:** 4-8 band crossover network, per-band dynamics

---

### P4.3: Unity Adapter
- **Category:** Integration
- **Impact:** Unity game engine export
- **Effort:** 1-2 weeks
- **Status:** Backlog
- **Location:** `flutter_ui/lib/services/export/unity_exporter.dart` (already exists)
- **Notes:** C# code generation complete, needs Unity package wrapper

---

### P4.4: Unreal Adapter
- **Category:** Integration
- **Impact:** Unreal Engine export
- **Effort:** 1-2 weeks
- **Status:** Backlog
- **Location:** `flutter_ui/lib/services/export/unreal_exporter.dart` (already exists)
- **Notes:** C++ code generation complete, needs Unreal plugin packaging

---

### P4.5: Web (Howler.js) Adapter
- **Category:** Integration
- **Impact:** Browser runtime support
- **Effort:** 1 week
- **Status:** Backlog
- **Location:** `flutter_ui/lib/services/export/howler_exporter.dart` (already exists)
- **Notes:** TypeScript generation complete, needs npm package

---

### P4.6: Mobile/Web Target Optimization
- **Category:** Platform
- **Impact:** Flutter web/mobile performance
- **Effort:** 2-3 weeks
- **Status:** Backlog
- **Notes:** Deferred until P0-P3 complete

---

### P4.7: WASM Port for Web
- **Category:** Platform
- **Impact:** Browser DSP processing
- **Effort:** 3-4 weeks
- **Status:** Backlog
- **Location:** `crates/rf-wasm/` (already implemented)
- **Notes:** Core WASM port exists (~400 LOC), needs full feature parity

---

### P4.8: CI/CD Regression Testing
- **Category:** QA
- **Impact:** Automated quality gates
- **Effort:** 1-2 weeks
- **Status:** Backlog
- **Location:** `.github/workflows/ci.yml` (already exists)
- **Notes:** CI pipeline exists with 39 tests, needs expansion

---

### P4.9-26: SlotLab Enhancements (18 items)

**Category:** SlotLab Future Features
**Total Effort:** 6-8 weeks
**Total LOC:** ~6,700
**Status:** Backlog

**Testing & QA (6 items):**
- P4.9: Session replay system (1w, ~1,000 LOC)
- P4.10: RNG seed control (2d, ~200 LOC)
- P4.11: Test automation API (1w, ~800 LOC)
- P4.12: Session export JSON (2d, ~300 LOC)
- P4.13: Performance overlay (2d, ~250 LOC)
- P4.14: Edge case presets (2d, ~200 LOC)

**Producer & Client (4 items):**
- P4.15: Export video MP4 (1w, ~600 LOC)
- P4.16: Screenshot mode (2d, ~200 LOC)
- P4.17: Demo mode auto-play (3d, ~400 LOC)
- P4.18: Branding customization (2d, ~300 LOC)

**UX & Accessibility (3 items):**
- P4.19: Tutorial overlay (3d, ~500 LOC)
- P4.20: Accessibility mode (1w, ~600 LOC)
- P4.21: Reduced motion (2d, ~200 LOC)

**Graphics & Performance (3 items):**
- P4.22: FPS counter (1d, ~100 LOC)
- P4.23: Animation debug (2d, ~300 LOC)
- P4.24: Particle tuning UI (2d, ~250 LOC)

**Desni Panel Advanced (2 items):**
- P4.25: Event templates (3d, ~500 LOC)
- P4.26: Scripting API (1w, ~1,200 LOC)

**Details:** See `.claude/reviews/SLOTLAB_ULTIMATE_ANALYSIS_2026_01_29.md`

---

## 🟡 P2 — SKIPPED (1 item)

### P2.16: Async Undo Offload to Disk
- **Category:** Memory Optimization
- **Impact:** Medium
- **Effort:** 2-3 weeks
- **Status:** ⏸️ SKIPPED
- **Reason:** VoidCallback not serializable, requires full refactor to data-driven Command Pattern
- **Notes:** Current 100-action limit is sufficient for most use cases

---

## ✅ COMPLETED MILESTONES

### Milestone 1: Foundation (P0 Critical) — ✅ COMPLETE
- All 13 critical tasks complete
- Production-ready foundation achieved
- Security, stability, testing all verified

### Milestone 2: Professional Features (P1 High) — ✅ COMPLETE
- All 15 high-priority tasks complete
- Pro Tools / Logic Pro level UX achieved
- Workspace presets, command palette, PDC indicators all working

### Milestone 3: Quality of Life (P2 Medium) — ✅ 95% COMPLETE
- 21/22 tasks complete (1 skipped intentionally)
- Track notes, parameter lock, channel strip presets, touch mode all added
- Panel opacity, auto-hide mode implemented

### Milestone 4: Polish (P3 Low) — ✅ COMPLETE
- All 14 low-priority tasks complete
- Audio settings panel, CPU meters, export preset manager all working
- Best-in-class DAW Lower Zone delivered

---

## 🎯 NEXT STEPS

**Immediate:**
- No critical work remaining
- System is production-ready at 99% completion

**Optional (P4 Backlog):**
- Linear phase EQ mode for mastering workflow
- Unity/Unreal adapters for game integration
- WASM optimization for browser performance
- Multiband compression for advanced dynamics

**Decision Required:**
- Proceed to P4 backlog items, OR
- Shift focus to new feature areas, OR
- Move to polish and optimization phase

---

## 📁 CLEANUP ACTIONS

Following TODO files can be archived (all complete):
- ✅ `.claude/P0_TASKS_FINAL_STATUS.md` — All P0 done
- ✅ `.claude/analysis/DAW_TODO_MASTER_LIST.md` — All DAW done
- ✅ `.claude/analysis/TIMELINE_TAB_COMPLETE_TODO_LIST_2026_01_26.md` — All Timeline done
- ✅ `.claude/architecture/MIDDLEWARE_TODO_M3_2026_01_23.md` — M3+M4 done
- ✅ `.claude/performance/EQ_PROCESSING_TODO.md` — Obsolete (EQ already implemented)
- ✅ `.claude/tasks/DAW_LOWER_ZONE_TODO_2026_01_26.md` — All P0-P3 done

---

**Version:** 4.0
**Last Updated:** 2026-01-29 (SlotLab Analysis Added)
**Status:** DAW ✅ Production Ready (99%), SlotLab ⚠️ 63% (P0 work needed)
Now I'll generate the comprehensive P1/P2/P3 SlotLab task descriptions following the exact format used in the P0 tasks in MASTER_TODO.md.

## 🟠 P1 — HIGH PRIORITY (SlotLab) — DETAILED

### [SlotLab: Levi Panel] — Professional Features (6 items)

#### SL-LP-P1.1: Waveform Thumbnail in Audio Slots

**Problem:** Audio slots show only filename — no visual waveform preview
**Impact:** Audio designers can't visually identify files, must rely on filename memory
**Effort:** 3 days
**Assigned To:** Chief Audio Architect, Audio Designer
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart:300-450` — Enhance _buildAudioSlot()

**Implementation Steps:**
1. Add waveform generation via `NativeFFI.generateWaveformFromFile(path, cacheKey)`
2. Parse waveform JSON response with `parseWaveformFromJson()` helper
3. Create `_WaveformThumbnailPainter` CustomPainter (~100 LOC)
4. Integrate thumbnail in assigned audio slots (40x20px)
5. Add LRU cache for waveform data (max 100 entries)
6. Show loading indicator while generating
7. Gracefully handle null waveform (FFI failure)

**Code Example:**
```dart
// In _buildAudioSlot():
Widget _buildAudioSlot(String stage, String? audioPath) {
  return Container(
    height: 32,
    child: Row(
      children: [
        // NEW: Waveform thumbnail (if audio assigned)
        if (audioPath != null)
          _WaveformThumbnail(audioPath: audioPath, width: 40, height: 20),
        
        SizedBox(width: 4),
        
        // Existing: Filename display
        Expanded(
          child: Text(
            audioPath?.split('/').last ?? 'Drop audio here',
            style: TextStyle(fontSize: 9),
          ),
        ),
        
        // Play/Clear buttons
        _buildPlayButton(stage, audioPath),
        if (audioPath != null) _buildClearButton(stage),
      ],
    ),
  );
}

class _WaveformThumbnail extends StatelessWidget {
  final String audioPath;
  final double width;
  final double height;

  Widget build(BuildContext context) {
    return FutureBuilder<(Float32List?, Float32List?)>(
      future: _loadWaveform(audioPath),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: width,
            height: height,
            child: Center(child: CircularProgressIndicator(strokeWidth: 1)),
          );
        }

        final (leftChannel, rightChannel) = snapshot.data ?? (null, null);
        
        if (leftChannel == null) {
          return SizedBox(width: width, height: height); // Empty if FFI failed
        }

        return CustomPaint(
          size: Size(width, height),
          painter: _WaveformThumbnailPainter(
            leftChannel: leftChannel,
            rightChannel: rightChannel,
            color: FluxForgeTheme.accentBlue,
          ),
        );
      },
    );
  }

  Future<(Float32List?, Float32List?)> _loadWaveform(String path) async {
    // Check cache first
    if (_waveformCache.containsKey(path)) {
      return _waveformCache[path]!;
    }

    // Generate via FFI
    final json = await NativeFFI.instance.generateWaveformFromFile(
      path,
      cacheKey: path.hashCode.toString(),
    );

    if (json == null || json.isEmpty) {
      return (null, null);
    }

    // Parse JSON
    final waveform = parseWaveformFromJson(json);
    
    // Cache result (LRU)
    _waveformCache[path] = waveform;
    if (_waveformCache.length > 100) {
      _waveformCache.remove(_waveformCache.keys.first);
    }

    return waveform;
  }

  static final Map<String, (Float32List?, Float32List?)> _waveformCache = {};
}

class _WaveformThumbnailPainter extends CustomPainter {
  final Float32List leftChannel;
  final Float32List? rightChannel;
  final Color color;

  _WaveformThumbnailPainter({
    required this.leftChannel,
    this.rightChannel,
    required this.color,
  });

  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final samplesPerPixel = (leftChannel.length / size.width).ceil();

    for (int i = 0; i < size.width.toInt(); i++) {
      final sampleIndex = i * samplesPerPixel;
      if (sampleIndex >= leftChannel.length) break;

      final sample = leftChannel[sampleIndex].abs();
      final y = size.height / 2 * (1.0 - sample);

      if (i == 0) {
        path.moveTo(i.toDouble(), y);
      } else {
        path.lineTo(i.toDouble(), y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw center line
    final centerPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );
  }

  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

**Definition of Done:**
- [ ] Waveform thumbnail appears in assigned slots (40x20px)
- [ ] Generated via FFI (`generateWaveformFromFile`)
- [ ] LRU cache (max 100 waveforms)
- [ ] Loading indicator during generation
- [ ] Graceful null handling (FFI failure)
- [ ] Blue waveform color (FluxForgeTheme.accentBlue)
- [ ] Center line indicator
- [ ] flutter analyze passes

---

#### SL-LP-P1.2: Search/Filter Across 341 Slots

**Problem:** No search functionality — hard to find specific stages in 341 slots
**Impact:** Time-consuming to locate specific stage, poor UX for large projects
**Effort:** 2 days
**Assigned To:** UI/UX Expert, Tooling Developer
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart:100-230` — Add search bar in header

**Implementation Steps:**
1. Add search TextField in panel header
2. Add filter state (`_searchQuery`, `_showAssignedOnly`, `_showUnassignedOnly`)
3. Filter sections/groups/slots based on query
4. Add filter chips (Assigned Only, Unassigned Only, Pooled Only)
5. Add clear search button
6. Highlight matching text in slot names
7. Auto-collapse non-matching sections
8. Add keyboard shortcut (Cmd+F / Ctrl+F)

**Code Example:**
```dart
// In UltimateAudioPanel header:
Widget _buildHeader() {
  return Column(
    children: [
      // Row 1: Title + close
      Row(
        children: [
          Icon(Icons.audiotrack, size: 16),
          SizedBox(width: 8),
          Text('Ultimate Audio Panel', style: ...),
          Spacer(),
          IconButton(icon: Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
      
      // NEW: Row 2: Search bar
      Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search stages... (${_getMatchCount()} matches)',
            prefixIcon: Icon(Icons.search, size: 16),
            suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          style: TextStyle(fontSize: 11),
          onChanged: (query) {
            setState(() => _searchQuery = query.toLowerCase());
          },
        ),
      ),
      
      // NEW: Row 3: Filter chips
      if (_searchQuery.isNotEmpty)
        Wrap(
          spacing: 4,
          children: [
            FilterChip(
              label: Text('Assigned Only', style: TextStyle(fontSize: 9)),
              selected: _showAssignedOnly,
              onSelected: (v) => setState(() => _showAssignedOnly = v),
            ),
            FilterChip(
              label: Text('Unassigned Only', style: TextStyle(fontSize: 9)),
              selected: _showUnassignedOnly,
              onSelected: (v) => setState(() => _showUnassignedOnly = v),
            ),
            FilterChip(
              label: Text('Pooled Only', style: TextStyle(fontSize: 9)),
              selected: _showPooledOnly,
              onSelected: (v) => setState(() => _showPooledOnly = v),
            ),
          ],
        ),
    ],
  );
}

// Filter sections/groups/slots:
bool _slotMatchesFilter(_SlotConfig slot, String? audioPath) {
  // Text search
  if (_searchQuery.isNotEmpty) {
    final stageLower = slot.stage.toLowerCase();
    if (!stageLower.contains(_searchQuery)) {
      return false;
    }
  }
  
  // Assigned/Unassigned filter
  if (_showAssignedOnly && audioPath == null) return false;
  if (_showUnassignedOnly && audioPath != null) return false;
  
  // Pooled filter
  if (_showPooledOnly && !slot.isPooled) return false;
  
  return true;
}

Widget _buildSection(_SectionConfig config) {
  // Count matching slots in section
  int matchCount = 0;
  for (final group in config.groups) {
    matchCount += group.slots.where((s) {
      final audioPath = projectProvider.audioAssignments[s.stage];
      return _slotMatchesFilter(s, audioPath);
    }).length;
  }
  
  // Auto-collapse non-matching sections
  final isExpanded = _expandedSections.contains(config.id) 
    || (_searchQuery.isNotEmpty && matchCount > 0);
  
  return ExpansionTile(
    title: Row(
      children: [
        Text(config.title),
        Spacer(),
        if (_searchQuery.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: matchCount > 0 ? Colors.green.withOpacity(0.2) : Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$matchCount matches',
              style: TextStyle(fontSize: 9),
            ),
          ),
      ],
    ),
    initiallyExpanded: isExpanded,
    children: config.groups.map((g) => _buildGroup(g, config)).toList(),
  );
}
```

**Definition of Done:**
- [ ] Search TextField in header
- [ ] Filter by stage name (case-insensitive)
- [ ] Filter chips (Assigned, Unassigned, Pooled)
- [ ] Match count display ("X matches")
- [ ] Auto-collapse non-matching sections
- [ ] Clear search button
- [ ] Keyboard shortcut (Cmd+F / Ctrl+F)
- [ ] flutter analyze passes

---

#### SL-LP-P1.3: Keyboard Shortcuts for Navigation

**Problem:** Mouse-only workflow — no keyboard navigation
**Impact:** Slow workflow, accessibility issues
**Effort:** 2 days
**Assigned To:** UI/UX Expert
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart:50-100` — Add FocusScope + keyboard handler

**Implementation Steps:**
1. Wrap panel in FocusScope
2. Add HardwareKeyboard listener
3. Implement shortcuts:
   - Cmd+F / Ctrl+F: Focus search
   - Escape: Clear search / close panel
   - Arrow keys: Navigate slots
   - Space: Play selected slot
   - Delete: Clear selected slot
   - Cmd+1-9: Jump to section 1-9
4. Add visual focus indicator (blue border)
5. Add keyboard shortcuts overlay (? key)

**Code Example:**
```dart
class UltimateAudioPanel extends StatefulWidget {
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Container(
          decoration: BoxDecoration(
            border: _hasFocus 
              ? Border.all(color: FluxForgeTheme.accentBlue, width: 2)
              : null,
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Cmd+F / Ctrl+F: Focus search
    if ((event.logicalKey == LogicalKeyboardKey.keyF) && 
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // Escape: Clear search or close panel
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchQuery.isNotEmpty) {
        setState(() {
          _searchController.clear();
          _searchQuery = '';
        });
      } else {
        widget.onClose?.call();
      }
      return KeyEventResult.handled;
    }

    // Cmd+1-9: Jump to section
    if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
      final digit = event.logicalKey.keyLabel;
      final sectionIndex = int.tryParse(digit);
      if (sectionIndex != null && sectionIndex >= 1 && sectionIndex <= _sections.length) {
        _scrollToSection(sectionIndex - 1);
        return KeyEventResult.handled;
      }
    }

    // Arrow keys: Navigate slots
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectNextSlot();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectPreviousSlot();
      return KeyEventResult.handled;
    }

    // Space: Play selected slot
    if (event.logicalKey == LogicalKeyboardKey.space && _selectedSlotStage != null) {
      _togglePreview(_selectedSlotStage!, _getAudioPath(_selectedSlotStage!));
      return KeyEventResult.handled;
    }

    // Delete: Clear selected slot
    if (event.logicalKey == LogicalKeyboardKey.delete && _selectedSlotStage != null) {
      widget.onAudioClear?.call(_selectedSlotStage!);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToSection(int index) {
    // Auto-expand section
    setState(() {
      final sectionId = _sections[index].id;
      _expandedSections.add(sectionId);
    });

    // Scroll to section
    _scrollController.animateTo(
      index * 200.0, // Approximate section height
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _selectNextSlot() {
    // Find all visible slots
    final visibleSlots = <String>[];
    for (final section in _sections) {
      if (!_expandedSections.contains(section.id)) continue;
      for (final group in section.groups) {
        if (!_expandedGroups.contains(group.id)) continue;
        for (final slot in group.slots) {
          if (_slotMatchesFilter(slot, _getAudioPath(slot.stage))) {
            visibleSlots.add(slot.stage);
          }
        }
      }
    }

    if (visibleSlots.isEmpty) return;

    final currentIndex = _selectedSlotStage != null 
      ? visibleSlots.indexOf(_selectedSlotStage!)
      : -1;

    final nextIndex = (currentIndex + 1) % visibleSlots.length;
    setState(() => _selectedSlotStage = visibleSlots[nextIndex]);
  }
}
```

**Definition of Done:**
- [ ] FocusScope wraps panel
- [ ] Keyboard shortcuts working:
  - [ ] Cmd+F: Focus search
  - [ ] Escape: Clear search / close
  - [ ] Arrow keys: Navigate slots
  - [ ] Space: Play selected
  - [ ] Delete: Clear selected
  - [ ] Cmd+1-9: Jump to section
- [ ] Visual focus indicator (blue border)
- [ ] Keyboard shortcuts overlay (? key shows help)
- [ ] flutter analyze passes

---

#### SL-LP-P1.4: Variant Management (Multiple Audio Takes)

**Problem:** Can only assign ONE audio file per stage — no support for variants (take 1, take 2, etc.)
**Impact:** Audio designers can't A/B test multiple takes, must manually swap files
**Effort:** 1 week
**Assigned To:** Chief Audio Architect, Audio Designer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/services/variant_manager.dart` (~400 LOC)
- `flutter_ui/lib/widgets/slot_lab/variant_selector_dialog.dart` (~200 LOC)

**Files to Modify:**
- `flutter_ui/lib/models/slot_lab_models.dart` — Add `audioVariants` field (~50 LOC)
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart` — Add variant indicator (~150 LOC)

**Implementation Steps:**
1. Extend SlotLabProject model with `audioVariants: Map<String, List<String>>` (stage → [path1, path2, ...])
2. Create VariantManager service (CRUD for variants)
3. Modify audio slot UI to show variant count badge (e.g., "×3")
4. Add VariantSelectorDialog (shows all variants, select active, add/remove)
5. Update onAudioAssign to support adding to variants list
6. Add randomization mode (pick random variant on playback)
7. Add sequential mode (cycle through variants)
8. Persist variant settings to SlotLabProjectProvider

**Code Example:**
```dart
// variant_manager.dart
class VariantManager {
  static final instance = VariantManager._();
  VariantManager._();

  /// Add variant to stage
  void addVariant(String stage, String audioPath, SlotLabProjectProvider provider) {
    final variants = provider.audioVariants[stage] ?? [];
    if (!variants.contains(audioPath)) {
      variants.add(audioPath);
      provider.setAudioVariants(stage, variants);
    }
  }

  /// Remove variant from stage
  void removeVariant(String stage, String audioPath, SlotLabProjectProvider provider) {
    final variants = provider.audioVariants[stage] ?? [];
    variants.remove(audioPath);
    provider.setAudioVariants(stage, variants);
  }

  /// Get active variant (for playback)
  String? getActiveVariant(String stage, SlotLabProjectProvider provider, {VariantMode mode = VariantMode.first}) {
    final variants = provider.audioVariants[stage];
    if (variants == null || variants.isEmpty) {
      return provider.audioAssignments[stage]; // Fallback to single assignment
    }

    switch (mode) {
      case VariantMode.first:
        return variants.first;
      case VariantMode.random:
        return variants[Random().nextInt(variants.length)];
      case VariantMode.sequential:
        final index = (_sequentialIndices[stage] ?? 0) % variants.length;
        _sequentialIndices[stage] = index + 1;
        return variants[index];
    }
  }

  final Map<String, int> _sequentialIndices = {};
}

enum VariantMode { first, random, sequential }

// In ultimate_audio_panel.dart:
Widget _buildAudioSlot(String stage, String? audioPath) {
  final variants = projectProvider.audioVariants[stage];
  final variantCount = variants?.length ?? 0;

  return Container(
    child: Row(
      children: [
        // Filename or variant count
        if (variantCount > 1)
          _buildVariantIndicator(stage, variantCount)
        else if (audioPath != null)
          _buildSingleAudioDisplay(audioPath),

        // Variant selector button (if multiple variants)
        if (variantCount > 1)
          IconButton(
            icon: Icon(Icons.library_music, size: 14),
            tooltip: 'Manage variants ($variantCount takes)',
            onPressed: () async {
              await VariantSelectorDialog.show(
                context,
                stage: stage,
                variants: variants!,
              );
            },
          ),
      ],
    ),
  );
}

Widget _buildVariantIndicator(String stage, int count) {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.purple.withOpacity(0.2),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.purple.withOpacity(0.5)),
    ),
    child: Row(
      children: [
        Icon(Icons.layers, size: 10, color: Colors.purple),
        SizedBox(width: 4),
        Text(
          '×$count takes',
          style: TextStyle(fontSize: 9, color: Colors.purple),
        ),
      ],
    ),
  );
}

// variant_selector_dialog.dart
class VariantSelectorDialog extends StatefulWidget {
  final String stage;
  final List<String> variants;

  static Future<void> show(BuildContext context, {
    required String stage,
    required List<String> variants,
  }) {
    return showDialog(
      context: context,
      builder: (_) => VariantSelectorDialog(stage: stage, variants: variants),
    );
  }

  Widget build(BuildContext context) {
    final provider = context.read<SlotLabProjectProvider>();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.library_music, color: Colors.purple),
          SizedBox(width: 8),
          Text('Variants for $stage'),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 300,
        child: Column(
          children: [
            // Variant mode selector
            Row(
              children: [
                Text('Playback Mode:', style: TextStyle(fontSize: 11)),
                SizedBox(width: 8),
                DropdownButton<VariantMode>(
                  value: provider.variantMode[stage] ?? VariantMode.first,
                  items: [
                    DropdownMenuItem(value: VariantMode.first, child: Text('First Only')),
                    DropdownMenuItem(value: VariantMode.random, child: Text('Random')),
                    DropdownMenuItem(value: VariantMode.sequential, child: Text('Sequential')),
                  ],
                  onChanged: (mode) {
                    if (mode != null) {
                      provider.setVariantMode(stage, mode);
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 16),

            // Variant list
            Expanded(
              child: ListView.builder(
                itemCount: variants.length,
                itemBuilder: (ctx, i) {
                  final variant = variants[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.audiotrack, size: 16),
                    title: Text(variant.split('/').last, style: TextStyle(fontSize: 10)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.play_arrow, size: 16),
                          onPressed: () {
                            AudioPlaybackService.instance.previewFile(
                              variant,
                              source: PlaybackSource.browser,
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 16, color: Colors.white24),
                          onPressed: () {
                            VariantManager.instance.removeVariant(stage, variant, provider);
                            setState(() {}); // Refresh UI
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Add variant button
            SizedBox(height: 8),
            OutlinedButton.icon(
              icon: Icon(Icons.add, size: 16),
              label: Text('Add Variant'),
              onPressed: () async {
                final audioPath = await AudioWaveformPickerDialog.show(
                  context,
                  title: 'Add Variant for $stage',
                );
                if (audioPath != null) {
                  VariantManager.instance.addVariant(stage, audioPath, provider);
                  setState(() {}); // Refresh UI
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('Close'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
```

**Definition of Done:**
- [ ] SlotLabProject.audioVariants field (Map<String, List<String>>)
- [ ] VariantManager service (add, remove, getActive)
- [ ] Variant indicator badge ("×3 takes") in audio slots
- [ ] VariantSelectorDialog with:
  - [ ] List of all variants
  - [ ] Play button per variant
  - [ ] Delete button per variant
  - [ ] Add variant button
  - [ ] Playback mode selector (First, Random, Sequential)
- [ ] Persistence to SlotLabProjectProvider
- [ ] flutter analyze passes

---

#### SL-LP-P1.5: Missing Audio Report

**Problem:** No way to see which stages have NO audio assigned
**Impact:** Don't know which sections are incomplete, can't track progress
**Effort:** 1 day
**Assigned To:** Slot Game Designer, QA Engineer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/missing_audio_report.dart` (~200 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart:80-100` — Add report button in header

**Implementation Steps:**
1. Create MissingAudioReport dialog
2. Scan all 341 slots for unassigned audio
3. Group missing slots by section
4. Show count per section (e.g., "Base Game Loop: 5 missing")
5. Add "Jump to Slot" action (scrolls to slot + highlights)
6. Add export to CSV option
7. Add filter (All, Critical Only, Optional)

**Code Example:**
```dart
// missing_audio_report.dart
class MissingAudioReport extends StatelessWidget {
  static Future<void> show(BuildContext context, {
    required Map<String, String> audioAssignments,
    required List<_SectionConfig> sections,
  }) {
    return showDialog(
      context: context,
      builder: (_) => MissingAudioReport(
        audioAssignments: audioAssignments,
        sections: sections,
      ),
    );
  }

  final Map<String, String> audioAssignments;
  final List<_SectionConfig> sections;

  Widget build(BuildContext context) {
    final missingBySection = _analyzeMissingSlots();
    final totalMissing = missingBySection.values.fold<int>(0, (sum, list) => sum + list.length);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: 8),
          Text('Missing Audio Report'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            // Summary
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: totalMissing > 0 ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Total Slots', '341', Colors.white),
                  _buildStat('Assigned', '${341 - totalMissing}', Colors.green),
                  _buildStat('Missing', '$totalMissing', Colors.orange),
                  _buildStat('Completion', '${((341 - totalMissing) / 341 * 100).toInt()}%',
                    totalMissing == 0 ? Colors.green : Colors.orange),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Missing slots by section
            Expanded(
              child: ListView.builder(
                itemCount: missingBySection.keys.length,
                itemBuilder: (ctx, i) {
                  final sectionId = missingBySection.keys.elementAt(i);
                  final missing = missingBySection[sectionId]!;
                  final section = sections.firstWhere((s) => s.id == sectionId);

                  if (missing.isEmpty) return SizedBox.shrink();

                  return ExpansionTile(
                    leading: Icon(section.icon, size: 16, color: section.color),
                    title: Text(section.title, style: TextStyle(fontSize: 12)),
                    trailing: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${missing.length} missing', style: TextStyle(fontSize: 9)),
                    ),
                    children: missing.map((slot) {
                      return ListTile(
                        dense: true,
                        title: Text(slot.stage, style: TextStyle(fontSize: 10)),
                        trailing: TextButton(
                          child: Text('Jump to Slot', style: TextStyle(fontSize: 9)),
                          onPressed: () {
                            Navigator.pop(context);
                            // TODO: Scroll to slot + highlight
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: Icon(Icons.file_download, size: 16),
          label: Text('Export CSV'),
          onPressed: () => _exportToCsv(missingBySection),
        ),
        TextButton(
          child: Text('Close'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Map<String, List<_SlotConfig>> _analyzeMissingSlots() {
    final Map<String, List<_SlotConfig>> missing = {};

    for (final section in sections) {
      missing[section.id] = [];
      for (final group in section.groups) {
        for (final slot in group.slots) {
          if (!audioAssignments.containsKey(slot.stage) || audioAssignments[slot.stage]!.isEmpty) {
            missing[section.id]!.add(slot);
          }
        }
      }
    }

    return missing;
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.white54)),
      ],
    );
  }

  void _exportToCsv(Map<String, List<_SlotConfig>> missingBySection) {
    // TODO: Generate CSV with columns: Section, Group, Stage, Priority
  }
}

// In ultimate_audio_panel.dart header:
Row(
  children: [
    Text('Ultimate Audio Panel'),
    Spacer(),
    IconButton(
      icon: Icon(Icons.warning_amber, size: 16),
      tooltip: 'Missing Audio Report',
      onPressed: () {
        MissingAudioReport.show(
          context,
          audioAssignments: projectProvider.audioAssignments,
          sections: _sections,
        );
      },
    ),
    IconButton(icon: Icon(Icons.close), onPressed: widget.onClose),
  ],
)
```

**Definition of Done:**
- [ ] Dialog shows missing audio count by section
- [ ] Summary stats (Total, Assigned, Missing, Completion %)
- [ ] Expandable sections with missing slot list
- [ ] "Jump to Slot" button per missing slot
- [ ] Export to CSV option
- [ ] Accessible via header button (warning icon)
- [ ] flutter analyze passes

---

#### SL-LP-P1.6: A/B Comparison Mode

**Problem:** Can't compare two audio files for same stage side-by-side
**Impact:** Audio designers can't quickly A/B test different takes
**Effort:** 3 days
**Assigned To:** Chief Audio Architect, Audio Designer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/audio_ab_comparison.dart` (~300 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart` — Add A/B button per slot (~50 LOC)

**Implementation Steps:**
1. Create AudioABComparison dialog
2. Add file picker for A and B audio
3. Add waveform display for both
4. Add play buttons (Play A, Play B, Play Both)
5. Add level meters for both
6. Add sync playback option (play both simultaneously)
7. Add "Choose A" / "Choose B" action (replaces current assignment)
8. Persist last A/B comparison per slot

**Code Example:**
```dart
// audio_ab_comparison.dart
class AudioABComparison extends StatefulWidget {
  final String stage;
  final String currentAudioPath;

  static Future<String?> show(BuildContext context, {
    required String stage,
    required String currentAudioPath,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AudioABComparison(
        stage: stage,
        currentAudioPath: currentAudioPath,
      ),
    );
  }

  State<AudioABComparison> createState() => _AudioABComparisonState();
}

class _AudioABComparisonState extends State<AudioABComparison> {
  String _audioA;
  String? _audioB;
  String? _playingA;
  String? _playingB;
  bool _syncPlayback = false;

  void initState() {
    super.initState();
    _audioA = widget.currentAudioPath;
  }

  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.compare_arrows, color: FluxForgeTheme.accentBlue),
          SizedBox(width: 8),
          Text('A/B Comparison: ${widget.stage}'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Row(
          children: [
            // Side A
            Expanded(child: _buildAudioSide('A', _audioA, _playingA != null)),

            // Divider
            VerticalDivider(width: 2),

            // Side B
            Expanded(child: _buildAudioSide('B', _audioB, _playingB != null)),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            // Sync playback toggle
            Checkbox(
              value: _syncPlayback,
              onChanged: (v) => setState(() => _syncPlayback = v ?? false),
            ),
            Text('Sync Playback', style: TextStyle(fontSize: 10)),

            Spacer(),

            // Choose A button
            TextButton(
              child: Text('Choose A'),
              onPressed: () => Navigator.pop(context, _audioA),
            ),

            // Choose B button (only if B selected)
            if (_audioB != null)
              TextButton(
                child: Text('Choose B'),
                onPressed: () => Navigator.pop(context, _audioB),
              ),

            // Cancel
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioSide(String label, String? audioPath, bool isPlaying) {
    return Container(
      padding: EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: label == 'A' ? Colors.blue.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: label == 'A' ? Colors.blue : Colors.orange,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: label == 'A' ? Colors.blue : Colors.orange,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              if (audioPath != null)
                Expanded(
                  child: Text(
                    audioPath.split('/').last,
                    style: TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),

          SizedBox(height: 12),

          // Waveform
          if (audioPath != null)
            _WaveformThumbnail(audioPath: audioPath, width: 250, height: 80)
          else
            Container(
              width: 250,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Center(child: Text('No audio selected', style: TextStyle(fontSize: 10))),
            ),

          SizedBox(height: 12),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Choose file button
              OutlinedButton.icon(
                icon: Icon(Icons.folder_open, size: 14),
                label: Text('Choose', style: TextStyle(fontSize: 10)),
                onPressed: () async {
                  final path = await AudioWaveformPickerDialog.show(
                    context,
                    title: 'Choose Audio for $label',
                  );
                  if (path != null) {
                    setState(() {
                      if (label == 'A') {
                        _audioA = path;
                      } else {
                        _audioB = path;
                      }
                    });
                  }
                },
              ),

              // Play button
              if (audioPath != null)
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 24,
                    color: label == 'A' ? Colors.blue : Colors.orange,
                  ),
                  onPressed: () => _togglePlayback(label, audioPath),
                ),
            ],
          ),

          Spacer(),

          // Level meter
          if (audioPath != null && isPlaying)
            LinearProgressIndicator(
              value: 0.7, // TODO: Real-time level from AudioPlaybackService
              backgroundColor: Colors.white10,
              color: label == 'A' ? Colors.blue : Colors.orange,
            ),
        ],
      ),
    );
  }

  void _togglePlayback(String label, String audioPath) {
    final isPlaying = (label == 'A' && _playingA != null) || (label == 'B' && _playingB != null);

    if (isPlaying) {
      AudioPlaybackService.instance.stopAll();
      setState(() {
        _playingA = null;
        _playingB = null;
      });
    } else {
      if (_syncPlayback && _audioB != null) {
        // Play both simultaneously
        AudioPlaybackService.instance.previewFile(_audioA, source: PlaybackSource.browser);
        AudioPlaybackService.instance.previewFile(_audioB!, source: PlaybackSource.browser);
        setState(() {
          _playingA = _audioA;
          _playingB = _audioB;
        });
      } else {
        // Play only selected side
        AudioPlaybackService.instance.previewFile(audioPath, source: PlaybackSource.browser);
        setState(() {
          if (label == 'A') {
            _playingA = audioPath;
            _playingB = null;
          } else {
            _playingB = audioPath;
            _playingA = null;
          }
        });
      }
    }
  }
}

// In ultimate_audio_panel.dart, add A/B button per slot:
Row(
  children: [
    // Existing: Play button, Clear button
    _buildPlayButton(stage, audioPath),
    if (audioPath != null) _buildClearButton(stage),

    // NEW: A/B comparison button
    if (audioPath != null)
      IconButton(
        icon: Icon(Icons.compare_arrows, size: 14),
        tooltip: 'A/B Comparison',
        onPressed: () async {
          final chosenPath = await AudioABComparison.show(
            context,
            stage: stage,
            currentAudioPath: audioPath,
          );
          if (chosenPath != null && chosenPath != audioPath) {
            widget.onAudioAssign?.call(stage, chosenPath);
          }
        },
      ),
  ],
)
```

**Definition of Done:**
- [ ] Dialog with A/B side-by-side layout
- [ ] File picker for A and B
- [ ] Waveform display for both
- [ ] Play buttons (Play A, Play B, Play Both)
- [ ] Sync playback toggle
- [ ] Choose A / Choose B action (updates assignment)
- [ ] Level meters during playback
- [ ] Accessible via A/B button per slot
- [ ] flutter analyze passes

---

### [SlotLab: Desni Panel] — Professional Features (6 items)

#### SL-RP-P1.1: Event Context Menu (Duplicate, Delete, Export, Test)

**Problem:** No right-click context menu — missing quick actions
**Impact:** Must use separate buttons for common operations, slower workflow
**Effort:** 2 days
**Assigned To:** Audio Middleware Architect, UI/UX Expert
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:480-620` — Add GestureDetector with secondary tap

**Implementation Steps:**
1. Wrap event row in GestureDetector
2. Detect right-click (onSecondaryTap)
3. Show PopupMenuButton with actions
4. Implement actions:
   - Duplicate: `middleware.duplicateCompositeEvent(eventId)`
   - Delete: Confirmation dialog → `middleware.deleteCompositeEvent(eventId)`
   - Export: Export single event to JSON
   - Test: `middleware.previewCompositeEvent(eventId)`
   - Edit Stages: Open StageEditorDialog
   - Rename: Focus inline editor
5. Add keyboard shortcuts (Del=delete, Cmd+D=duplicate)

**Code Example:**
```dart
Widget _buildEventItem(SlotCompositeEvent event) {
  return GestureDetector(
    onSecondaryTap: () => _showContextMenu(event),
    child: Container(
      // Existing event row UI
      child: Row(
        children: [
          // Name column
          _buildNameColumn(event),
          // Stage column
          _buildStageColumn(event),
          // Layers column
          _buildLayersColumn(event),
        ],
      ),
    ),
  );
}

void _showContextMenu(SlotCompositeEvent event) {
  final middleware = context.read<MiddlewareProvider>();

  showMenu(
    context: context,
    position: _getMenuPosition(),
    items: [
      PopupMenuItem(
        value: 'test',
        child: Row(
          children: [
            Icon(Icons.play_arrow, size: 16),
            SizedBox(width: 8),
            Text('Test Playback'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'duplicate',
        child: Row(
          children: [
            Icon(Icons.content_copy, size: 16),
            SizedBox(width: 8),
            Text('Duplicate'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'rename',
        child: Row(
          children: [
            Icon(Icons.edit, size: 16),
            SizedBox(width: 8),
            Text('Rename'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'editStages',
        child: Row(
          children: [
            Icon(Icons.label, size: 16),
            SizedBox(width: 8),
            Text('Edit Trigger Stages'),
          ],
        ),
      ),
      PopupMenuDivider(),
      PopupMenuItem(
        value: 'export',
        child: Row(
          children: [
            Icon(Icons.file_download, size: 16),
            SizedBox(width: 8),
            Text('Export to JSON'),
          ],
        ),
      ),
      PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete, size: 16, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete', style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ],
  ).then((value) {
    if (value == null) return;

    switch (value) {
      case 'test':
        middleware.previewCompositeEvent(event.id);
        break;
      case 'duplicate':
        middleware.duplicateCompositeEvent(event.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Event duplicated')),
        );
        break;
      case 'rename':
        _startEditing(event);
        break;
      case 'editStages':
        _openStageEditor(event);
        break;
      case 'export':
        _exportEventToJson(event);
        break;
      case 'delete':
        _confirmDelete(event);
        break;
    }
  });
}

RelativeRect _getMenuPosition() {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final RenderBox button = context.findRenderObject() as RenderBox;
  final Offset position = button.localToGlobal(Offset.zero, ancestor: overlay);

  return RelativeRect.fromRect(
    Rect.fromPoints(position, position),
    Offset.zero & overlay.size,
  );
}

Future<void> _exportEventToJson(SlotCompositeEvent event) async {
  final json = jsonEncode(event.toJson());
  
  // Save to file
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export Event',
    fileName: '${event.name}.json',
  );

  if (path != null) {
    await File(path).writeAsString(json);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported to $path')),
    );
  }
}

Future<void> _confirmDelete(SlotCompositeEvent event) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Delete Event'),
      content: Text('Delete "${event.name}"? This cannot be undone.'),
      actions: [
        TextButton(
          child: Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        TextButton(
          child: Text('Delete', style: TextStyle(color: Colors.red)),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );

  if (confirm == true) {
    final middleware = context.read<MiddlewareProvider>();
    middleware.deleteCompositeEvent(event.id);
    if (_selectedEventId == event.id) {
      _setSelectedEventId(null);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Event deleted')),
    );
  }
}
```

**Definition of Done:**
- [ ] Right-click opens context menu
- [ ] Menu items:
  - [ ] Test Playback
  - [ ] Duplicate
  - [ ] Rename
  - [ ] Edit Trigger Stages
  - [ ] Export to JSON
  - [ ] Delete (with confirmation)
- [ ] Keyboard shortcuts (Del, Cmd+D)
- [ ] Visual feedback (SnackBar)
- [ ] flutter analyze passes

---

#### SL-RP-P1.2: Test Playback Button Per Event

**Problem:** No quick way to preview event from Events Folder list
**Impact:** Must select event and go to editor to test — slow workflow
**Effort:** 1 day
**Assigned To:** Audio Designer, QA Engineer
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:480-620` — Add play button in event row

**Implementation Steps:**
1. Add play IconButton to event row (before layers column)
2. Track playing state (`_playingEventId`)
3. On click: call `middleware.previewCompositeEvent(eventId)`
4. Icon toggles play → stop
5. Auto-stop when clicking another event's play button
6. Add tooltip ("Preview event")

**Code Example:**
```dart
class _EventsPanelWidgetState extends State<EventsPanelWidget> {
  String? _playingEventId;

  Widget _buildEventItem(SlotCompositeEvent event) {
    final isPlaying = _playingEventId == event.id;

    return Row(
      children: [
        // NEW: Play button
        IconButton(
          icon: Icon(
            isPlaying ? Icons.stop : Icons.play_arrow,
            size: 14,
            color: isPlaying ? FluxForgeTheme.accentBlue : Colors.white54,
          ),
          tooltip: isPlaying ? 'Stop' : 'Preview event',
          onPressed: () => _togglePreview(event),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: 24, height: 24),
        ),

        // Existing: Name column
        Expanded(
          flex: 3,
          child: _buildNameColumn(event),
        ),

        // Existing: Stage column
        Expanded(
          flex: 2,
          child: _buildStageColumn(event),
        ),

        // Existing: Layers column
        SizedBox(
          width: 50,
          child: _buildLayersColumn(event),
        ),
      ],
    );
  }

  void _togglePreview(SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();

    if (_playingEventId == event.id) {
      // Stop current
      EventRegistry.instance.stopEvent(event.id);
      setState(() => _playingEventId = null);
    } else {
      // Stop previous if any
      if (_playingEventId != null) {
        EventRegistry.instance.stopEvent(_playingEventId!);
      }

      // Play new
      middleware.previewCompositeEvent(event.id);
      setState(() => _playingEventId = event.id);

      // Auto-stop after event duration (estimate 5s)
      Future.delayed(Duration(seconds: 5), () {
        if (_playingEventId == event.id) {
          setState(() => _playingEventId = null);
        }
      });
    }
  }
}
```

**Definition of Done:**
- [ ] Play button appears in each event row
- [ ] Icon toggles play ↔ stop
- [ ] Calls middleware.previewCompositeEvent(eventId)
- [ ] Auto-stops previous event when clicking another
- [ ] Blue color when playing
- [ ] Tooltip ("Preview event")
- [ ] flutter analyze passes

---

#### SL-RP-P1.3: Validation Badges (Complete/Incomplete/Error)

**Problem:** No visual indication of event completeness — can't tell which events are ready
**Impact:** Don't know which events need more work, QA issues
**Effort:** 2 days
**Assigned To:** QA Engineer, Slot Game Designer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/services/event_validation_service.dart` (~200 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:480-620` — Add validation badge in event row

**Implementation Steps:**
1. Create EventValidationService singleton
2. Define validation rules:
   - Has at least one layer
   - All layers have audio assigned
   - All layers have valid volume/pan
   - At least one trigger stage
   - No duplicate stage assignments
3. Add `validateEvent(SlotCompositeEvent)` method returning `EventValidationResult`
4. Add validation badge to event row (✅ complete, ⚠️ incomplete, ❌ error)
5. Add tooltip with validation details
6. Auto-update when event changes

**Code Example:**
```dart
// event_validation_service.dart
class EventValidationService {
  static final instance = EventValidationService._();
  EventValidationService._();

  EventValidationResult validateEvent(SlotCompositeEvent event) {
    final issues = <String>[];

    // Rule 1: Has at least one layer
    if (event.layers.isEmpty) {
      issues.add('Event has no audio layers');
    }

    // Rule 2: All layers have audio
    for (final layer in event.layers) {
      if (layer.audioPath.isEmpty) {
        issues.add('Layer "${layer.name}" has no audio file');
      }
    }

    // Rule 3: Valid parameters
    for (final layer in event.layers) {
      if (layer.volume < 0.0 || layer.volume > 2.0) {
        issues.add('Layer "${layer.name}" has invalid volume (${layer.volume})');
      }
      if (layer.pan < -1.0 || layer.pan > 1.0) {
        issues.add('Layer "${layer.name}" has invalid pan (${layer.pan})');
      }
    }

    // Rule 4: Has trigger stage
    if (event.triggerStages.isEmpty) {
      issues.add('Event has no trigger stages');
    }

    // Rule 5: No duplicate stages (check against all events)
    // (requires all events as parameter — skipped for now)

    if (issues.isEmpty) {
      return EventValidationResult.complete();
    } else if (issues.any((i) => i.startsWith('Event has no'))) {
      return EventValidationResult.error(issues);
    } else {
      return EventValidationResult.incomplete(issues);
    }
  }
}

class EventValidationResult {
  final EventValidationStatus status;
  final List<String> issues;

  EventValidationResult.complete()
    : status = EventValidationStatus.complete,
      issues = [];

  EventValidationResult.incomplete(this.issues)
    : status = EventValidationStatus.incomplete;

  EventValidationResult.error(this.issues)
    : status = EventValidationStatus.error;

  bool get isComplete => status == EventValidationStatus.complete;
  bool get hasIssues => issues.isNotEmpty;
}

enum EventValidationStatus { complete, incomplete, error }

// In events_panel_widget.dart:
Widget _buildEventItem(SlotCompositeEvent event) {
  final validation = EventValidationService.instance.validateEvent(event);

  return Row(
    children: [
      // NEW: Validation badge
      Container(
        width: 20,
        child: _buildValidationBadge(validation),
      ),

      // Existing columns
      Expanded(flex: 3, child: _buildNameColumn(event)),
      Expanded(flex: 2, child: _buildStageColumn(event)),
      SizedBox(width: 50, child: _buildLayersColumn(event)),
    ],
  );
}

Widget _buildValidationBadge(EventValidationResult validation) {
  IconData icon;
  Color color;

  switch (validation.status) {
    case EventValidationStatus.complete:
      icon = Icons.check_circle;
      color = Colors.green;
      break;
    case EventValidationStatus.incomplete:
      icon = Icons.warning_amber;
      color = Colors.orange;
      break;
    case EventValidationStatus.error:
      icon = Icons.error;
      color = Colors.red;
      break;
  }

  return Tooltip(
    message: validation.hasIssues
      ? validation.issues.join('\n')
      : 'Event is complete',
    child: Icon(icon, size: 14, color: color),
  );
}
```

**Definition of Done:**
- [ ] EventValidationService with validation rules
- [ ] Validation badge per event (✅/⚠️/❌)
- [ ] Tooltip shows validation issues
- [ ] Auto-updates when event changes
- [ ] Color-coded: green=complete, orange=incomplete, red=error
- [ ] flutter analyze passes

---

#### SL-RP-P1.4: Event Search/Filter

**Problem:** No search in Events Folder — hard to find events in long lists
**Impact:** Time-consuming to locate specific event
**Effort:** 1 day
**Assigned To:** UI/UX Expert
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:150-230` — Add search field in Events Folder header

**Implementation Steps:**
1. Add search TextField in Events Folder header
2. Add filter state (`_eventSearchQuery`)
3. Filter events list based on query (name, stage)
4. Add match count display ("X matches")
5. Add clear search button
6. Highlight matching text
7. Persist search state

**Code Example:**
```dart
// In _buildEventsFolder():
Widget _buildEventsFolder() {
  return Consumer<MiddlewareProvider>(
    builder: (context, middleware, _) {
      final allEvents = middleware.compositeEvents;
      final filteredEvents = _filterEvents(allEvents);

      return Column(
        children: [
          // Header with search
          Container(
            padding: EdgeInsets.all(8),
            child: Column(
              children: [
                // Row 1: Title + Create button
                Row(
                  children: [
                    Text('Events & Assets', style: TextStyle(fontSize: 12)),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.add, size: 16),
                      onPressed: _showCreateEventDialog,
                    ),
                  ],
                ),

                // NEW: Row 2: Search field
                TextField(
                  controller: _eventSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search events... (${filteredEvents.length} matches)',
                    prefixIcon: Icon(Icons.search, size: 14),
                    suffixIcon: _eventSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 14),
                          onPressed: () {
                            _eventSearchController.clear();
                            setState(() => _eventSearchQuery = '');
                          },
                        )
                      : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  style: TextStyle(fontSize: 10),
                  onChanged: (query) {
                    setState(() => _eventSearchQuery = query.toLowerCase());
                  },
                ),
              ],
            ),
          ),

          // Event list header (3-column)
          _buildEventListHeader(),

          // Filtered event list
          Expanded(
            child: filteredEvents.isEmpty
              ? _buildEmptyState(
                  _eventSearchQuery.isEmpty ? 'No events' : 'No matches',
                  _eventSearchQuery.isEmpty ? 'Click + to create' : 'Try different search',
                )
              : ListView.builder(
                  itemCount: filteredEvents.length,
                  itemBuilder: (ctx, i) => _buildEventItem(filteredEvents[i]),
                ),
          ),
        ],
      );
    },
  );
}

List<SlotCompositeEvent> _filterEvents(List<SlotCompositeEvent> events) {
  if (_eventSearchQuery.isEmpty) {
    return events;
  }

  return events.where((event) {
    // Match name
    if (event.name.toLowerCase().contains(_eventSearchQuery)) {
      return true;
    }

    // Match any trigger stage
    if (event.triggerStages.any((s) => s.toLowerCase().contains(_eventSearchQuery))) {
      return true;
    }

    return false;
  }).toList();
}
```

**Definition of Done:**
- [ ] Search TextField in Events Folder header
- [ ] Filter by event name and trigger stages
- [ ] Match count display ("X matches")
- [ ] Clear search button
- [ ] Empty state for no matches
- [ ] flutter analyze passes

---

#### SL-RP-P1.5: Favorites System in Audio Browser

**Problem:** No favorites/bookmarks — can't quickly access frequently used files
**Impact:** Must search for same files repeatedly
**Effort:** 2 days
**Assigned To:** Audio Designer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/services/favorites_service.dart` (~300 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:770-950` — Add star icon per audio file

**Implementation Steps:**
1. Create FavoritesService singleton
2. Add favorites storage (SharedPreferences)
3. Add star IconButton per audio file
4. Add "Favorites" filter toggle (show only favorites)
5. Persist favorites across sessions
6. Add clear all favorites action

**Code Example:**
```dart
// favorites_service.dart
class FavoritesService {
  static final instance = FavoritesService._();
  FavoritesService._();

  static const _key = 'slotlab_audio_favorites';
  Set<String> _favorites = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    _favorites = Set.from(list);
  }

  bool isFavorite(String audioPath) => _favorites.contains(audioPath);

  Future<void> toggleFavorite(String audioPath) async {
    if (_favorites.contains(audioPath)) {
      _favorites.remove(audioPath);
    } else {
      _favorites.add(audioPath);
    }
    await _save();
  }

  Future<void> clearAll() async {
    _favorites.clear();
    await _save();
  }

  Set<String> get favorites => Set.unmodifiable(_favorites);

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _favorites.toList());
  }
}

// In events_panel_widget.dart:
class _HoverPreviewItem extends StatefulWidget {
  final String audioPath;
  final bool isPoolMode;

  Widget build(BuildContext context) {
    final isFavorite = FavoritesService.instance.isFavorite(audioPath);

    return ListTile(
      dense: true,
      leading: Icon(Icons.audiotrack, size: 14),
      title: Text(fileName, style: TextStyle(fontSize: 10)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NEW: Favorite star button
          IconButton(
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              size: 14,
              color: isFavorite ? Colors.amber : Colors.white38,
            ),
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () async {
              await FavoritesService.instance.toggleFavorite(audioPath);
              setState(() {}); // Refresh UI
            },
          ),

          // Existing: Play button
          IconButton(
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow, size: 14),
            onPressed: _togglePlay,
          ),
        ],
      ),
    );
  }
}

// Add "Favorites Only" filter toggle in header:
Row(
  children: [
    // Existing: Pool/Files toggle
    SegmentedButton(...),

    Spacer(),

    // NEW: Favorites toggle
    FilterChip(
      label: Row(
        children: [
          Icon(Icons.star, size: 12, color: _showFavoritesOnly ? Colors.amber : Colors.white54),
          SizedBox(width: 4),
          Text('Favorites', style: TextStyle(fontSize: 9)),
        ],
      ),
      selected: _showFavoritesOnly,
      onSelected: (v) => setState(() => _showFavoritesOnly = v),
    ),

    // Import buttons
    IconButton(icon: Icon(Icons.insert_drive_file), ...),
    IconButton(icon: Icon(Icons.folder_open), ...),
  ],
)

// Filter audio list:
List<String> _filterAudioFiles(List<String> files) {
  if (_showFavoritesOnly) {
    return files.where((f) => FavoritesService.instance.isFavorite(f)).toList();
  }
  return files;
}
```

**Definition of Done:**
- [ ] FavoritesService with SharedPreferences persistence
- [ ] Star IconButton per audio file
- [ ] Icon toggles filled/outline
- [ ] "Favorites Only" filter toggle
- [ ] Favorites persist across sessions
- [ ] flutter analyze passes

---

#### SL-RP-P1.6: Real Waveform (Replace Fake _SimpleWaveformPainter)

**Problem:** Waveform preview uses fake random-generated waveform — misleading
**Impact:** Can't visually identify audio files, fake waveform is useless
**Effort:** 3 days
**Assigned To:** Engine Developer, Audio Designer
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:970-1035` — Replace `_SimpleWaveformPainter` with FFI-generated waveform

**Implementation Steps:**
1. Replace `_SimpleWaveformPainter` with `_WaveformThumbnailPainter` (from SL-LP-P1.1)
2. Use `NativeFFI.generateWaveformFromFile()` to get real waveform
3. Add LRU cache for waveform data
4. Show loading indicator while generating
5. Gracefully handle null waveform (FFI failure)
6. Display duration on waveform

**Code Example:**
```dart
// Remove _SimpleWaveformPainter class entirely

// In _HoverPreviewItem, replace fake waveform with real:
class _HoverPreviewItem extends StatefulWidget {
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ListTile(
        // ... existing UI

        // Replace fake waveform with real:
        subtitle: _hovering
          ? FutureBuilder<(Float32List?, Float32List?)>(
              future: _loadWaveform(audioPath),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 24,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 1),
                    ),
                  );
                }

                final (leftChannel, rightChannel) = snapshot.data ?? (null, null);

                if (leftChannel == null) {
                  return Text('Waveform not available', style: TextStyle(fontSize: 8));
                }

                return CustomPaint(
                  size: Size(double.infinity, 24),
                  painter: _WaveformThumbnailPainter(
                    leftChannel: leftChannel,
                    rightChannel: rightChannel,
                    color: _isPlaying ? Colors.green : FluxForgeTheme.accentBlue,
                  ),
                );
              },
            )
          : null,
      ),
    );
  }

  Future<(Float32List?, Float32List?)> _loadWaveform(String path) async {
    // Check cache
    if (_waveformCache.containsKey(path)) {
      return _waveformCache[path]!;
    }

    // Generate via FFI
    final json = await NativeFFI.instance.generateWaveformFromFile(
      path,
      cacheKey: path.hashCode.toString(),
    );

    if (json == null || json.isEmpty) {
      return (null, null);
    }

    // Parse JSON
    final waveform = parseWaveformFromJson(json);

    // Cache (LRU, max 100)
    _waveformCache[path] = waveform;
    if (_waveformCache.length > 100) {
      _waveformCache.remove(_waveformCache.keys.first);
    }

    return waveform;
  }

  static final Map<String, (Float32List?, Float32List?)> _waveformCache = {};
}

// Reuse _WaveformThumbnailPainter from SL-LP-P1.1 (already defined above)
```

**Definition of Done:**
- [ ] `_SimpleWaveformPainter` removed
- [ ] Real waveform via FFI (`generateWaveformFromFile`)
- [ ] LRU cache (max 100 waveforms)
- [ ] Loading indicator during generation
- [ ] Graceful null handling
- [ ] Color: green when playing, blue when idle
- [ ] flutter analyze passes

---

### [SlotLab: Lower Zone] — Integration (4 items)

#### SL-LZ-P1.1: Integrate 7 Existing Panels into Super-Tabs

**Problem:** Lower Zone has isolated panels not integrated into super-tab structure
**Impact:** Panels exist but aren't accessible via new super-tab UI
**Effort:** 1 day
**Assigned To:** Technical Director
**Status:** ❌ NOT STARTED
**Depends On:** SL-LZ-P0.2 (Super-tab structure created)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/lower_zone.dart:200-350` — Map existing panels to super-tabs

**Existing Panels to Integrate:**
1. `event_debug_panel.dart` → STAGES super-tab, Event Debug sub-tab
2. `bus_hierarchy_panel.dart` → MIX super-tab, Bus Hierarchy sub-tab
3. `aux_sends_panel.dart` → MIX super-tab, Aux Sends sub-tab
4. `profiler_panel.dart` → ENGINE super-tab, Profiler sub-tab
5. `stage_ingest_panel.dart` → ENGINE super-tab, Stage Ingest sub-tab
6. Event List → EVENTS super-tab, Event List sub-tab (after P0.1 fix)
7. Timeline → STAGES super-tab, Timeline sub-tab

**Implementation Steps:**
1. Import all existing panel widgets
2. Create IndexedStack per super-tab
3. Map sub-tab indices to panel widgets
4. Test switching between all tabs
5. Verify state persistence
6. Update keyboard shortcuts

**Code Example:**
```dart
// In lower_zone.dart:
Widget _buildContent() {
  switch (controller.activeSuperTab) {
    case SuperTab.stages:
      return _buildStagesContent();
    case SuperTab.events:
      return _buildEventsContent();
    case SuperTab.mix:
      return _buildMixContent();
    case SuperTab.musicAle:
      return _buildMusicAleContent();
    case SuperTab.dsp:
      return _buildDspContent();
    case SuperTab.bake:
      return _buildBakeContent();
    case SuperTab.engine:
      return _buildEngineContent();
    case SuperTab.menu:
      return _buildMenuContent();
  }
}

Widget _buildStagesContent() {
  return IndexedStack(
    index: controller.activeSubTabIndex,
    children: [
      // Sub-tab 0: Timeline
      _buildTimelinePanel(),

      // Sub-tab 1: Event Debug
      EventDebugPanel(), // Existing widget
    ],
  );
}

Widget _buildMixContent() {
  return IndexedStack(
    index: controller.activeSubTabIndex,
    children: [
      // Sub-tab 0: Bus Hierarchy
      BusHierarchyPanel(), // Existing widget

      // Sub-tab 1: Aux Sends
      AuxSendsPanel(), // Existing widget

      // Sub-tab 2: Meters
      _buildMetersPanel(),
    ],
  );
}

Widget _buildEngineContent() {
  return IndexedStack(
    index: controller.activeSubTabIndex,
    children: [
      // Sub-tab 0: Profiler
      ProfilerPanel(), // Existing widget

      // Sub-tab 1: Resources (NEW — see SL-LZ-P1.3)
      _buildResourcesPanel(),

      // Sub-tab 2: Stage Ingest
      StageIngestPanel(), // Existing widget
    ],
  );
}
```

**Definition of Done:**
- [ ] All 7 existing panels imported
- [ ] Panels mapped to correct super-tabs + sub-tabs
- [ ] IndexedStack per super-tab
- [ ] All panels accessible via new UI
- [ ] State persists when switching tabs
- [ ] Keyboard shortcuts work
- [ ] flutter analyze passes

---

#### SL-LZ-P1.2: Add Mix Super-Tab (Already Exists)

**Status:** ✅ COMPLETE (Bus Hierarchy + Aux Sends panels already exist)
**Effort:** 0 (just integration in P1.1)

---

#### SL-LZ-P1.3: Add Engine Super-Tab with Resources Panel

**Problem:** No Resources panel showing memory, CPU, voice stats
**Impact:** Can't monitor engine performance from SlotLab
**Effort:** 2 days
**Assigned To:** Engine Developer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/engine/resources_panel.dart` (~300 LOC)

**Implementation Steps:**
1. Create ResourcesPanel widget
2. Poll engine stats via FFI every 500ms
3. Display:
   - CPU usage (%)
   - Memory usage (MB)
   - Voice pool stats (active/max)
   - Audio buffer load
   - FFI call latency
4. Add refresh button
5. Add auto-refresh toggle
6. Integrate in ENGINE super-tab

**Code Example:**
```dart
// resources_panel.dart
class ResourcesPanel extends StatefulWidget {
  State<ResourcesPanel> createState() => _ResourcesPanelState();
}

class _ResourcesPanelState extends State<ResourcesPanel> {
  Timer? _refreshTimer;
  bool _autoRefresh = true;
  EngineStats? _stats;

  void initState() {
    super.initState();
    _refreshStats();
    if (_autoRefresh) {
      _startAutoRefresh();
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(Duration(milliseconds: 500), (_) {
      _refreshStats();
    });
  }

  void _refreshStats() async {
    final stats = await NativeFFI.instance.getEngineStats();
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.memory, size: 16),
              SizedBox(width: 8),
              Text('Engine Resources', style: TextStyle(fontSize: 12)),
              Spacer(),
              // Auto-refresh toggle
              Checkbox(
                value: _autoRefresh,
                onChanged: (v) {
                  setState(() => _autoRefresh = v ?? true);
                  if (_autoRefresh) {
                    _startAutoRefresh();
                  } else {
                    _refreshTimer?.cancel();
                  }
                },
              ),
              Text('Auto', style: TextStyle(fontSize: 9)),
              // Manual refresh button
              IconButton(
                icon: Icon(Icons.refresh, size: 16),
                onPressed: _refreshStats,
              ),
            ],
          ),

          SizedBox(height: 16),

          if (_stats == null)
            Center(child: CircularProgressIndicator())
          else
            Expanded(
              child: ListView(
                children: [
                  _buildStatCard('CPU Usage', '${_stats!.cpuUsage.toStringAsFixed(1)}%', Icons.speed, Colors.blue),
                  _buildStatCard('Memory', '${_stats!.memoryMb.toStringAsFixed(1)} MB', Icons.memory, Colors.purple),
                  _buildStatCard('Active Voices', '${_stats!.activeVoices} / ${_stats!.maxVoices}', Icons.graphic_eq, Colors.green),
                  _buildStatCard('Buffer Load', '${_stats!.bufferLoad.toStringAsFixed(1)}%', Icons.waves, Colors.orange),
                  _buildStatCard('FFI Latency', '${_stats!.ffiLatencyUs.toStringAsFixed(0)} μs', Icons.network_check, Colors.cyan),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      margin: EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: Colors.white54)),
                SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EngineStats {
  final double cpuUsage; // 0-100%
  final double memoryMb; // MB
  final int activeVoices;
  final int maxVoices;
  final double bufferLoad; // 0-100%
  final double ffiLatencyUs; // Microseconds

  EngineStats({
    required this.cpuUsage,
    required this.memoryMb,
    required this.activeVoices,
    required this.maxVoices,
    required this.bufferLoad,
    required this.ffiLatencyUs,
  });

  factory EngineStats.fromJson(Map<String, dynamic> json) {
    return EngineStats(
      cpuUsage: (json['cpu_usage'] as num).toDouble(),
      memoryMb: (json['memory_mb'] as num).toDouble(),
      activeVoices: json['active_voices'] as int,
      maxVoices: json['max_voices'] as int,
      bufferLoad: (json['buffer_load'] as num).toDouble(),
      ffiLatencyUs: (json['ffi_latency_us'] as num).toDouble(),
    );
  }
}

// NEW FFI function (add to native_ffi.dart):
Future<EngineStats> getEngineStats() async {
  final jsonStr = _dylib.lookupFunction<
    Pointer<Utf8> Function(),
    Pointer<Utf8> Function()
  >('engine_get_stats_json')();

  final json = jsonDecode(jsonStr.toDartString());
  return EngineStats.fromJson(json);
}
```

**Definition of Done:**
- [ ] ResourcesPanel widget created
- [ ] Auto-refresh every 500ms (toggleable)
- [ ] Stats displayed: CPU, Memory, Voices, Buffer, Latency
- [ ] FFI function `engine_get_stats_json()` implemented
- [ ] Integrated in ENGINE super-tab
- [ ] flutter analyze passes

---

#### SL-LZ-P1.4: Group DSP Panels Under DSP Super-Tab

**Problem:** DSP panels (Compressor, Limiter, Gate, Reverb) are flat tabs — should be grouped under DSP super-tab
**Impact:** Poor organization, doesn't match spec
**Effort:** 1 day
**Assigned To:** Technical Director
**Status:** ❌ NOT STARTED
**Depends On:** SL-LZ-P0.2 (Super-tab structure)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/lower_zone_types.dart:30-50` — Add DspSubTab enum
- `flutter_ui/lib/widgets/slot_lab/lower_zone/lower_zone.dart:250-300` — Add DSP IndexedStack

**Implementation Steps:**
1. Create DspSubTab enum (EQ, Compressor, Limiter, Gate, Reverb, Delay, Saturation, DeEsser)
2. Add DSP super-tab to SuperTab enum
3. Import all FabFilter panels
4. Create IndexedStack for DSP sub-tabs
5. Update controller to manage DSP sub-tab state
6. Test all DSP panels

**Code Example:**
```dart
// In lower_zone_types.dart:
enum DspSubTab {
  eq,
  compressor,
  limiter,
  gate,
  reverb,
  delay,
  saturation,
  deEsser,
}

// In lower_zone.dart:
Widget _buildDspContent() {
  return IndexedStack(
    index: controller.activeSubTabIndex,
    children: [
      // Sub-tab 0: EQ (placeholder for now)
      Center(child: Text('EQ Panel (TODO)', style: TextStyle(fontSize: 12))),

      // Sub-tab 1: Compressor
      FabFilterCompressorPanel(),

      // Sub-tab 2: Limiter
      FabFilterLimiterPanel(),

      // Sub-tab 3: Gate
      FabFilterGatePanel(),

      // Sub-tab 4: Reverb
      FabFilterReverbPanel(),

      // Sub-tab 5: Delay (placeholder)
      Center(child: Text('Delay Panel (TODO)', style: TextStyle(fontSize: 12))),

      // Sub-tab 6: Saturation (placeholder)
      Center(child: Text('Saturation Panel (TODO)', style: TextStyle(fontSize: 12))),

      // Sub-tab 7: DeEsser (placeholder)
      Center(child: Text('DeEsser Panel (TODO)', style: TextStyle(fontSize: 12))),
    ],
  );
}
```

**Definition of Done:**
- [ ] DspSubTab enum created
- [ ] DSP super-tab in SuperTab enum
- [ ] All FabFilter panels imported
- [ ] IndexedStack with 8 sub-tabs
- [ ] Sub-tab switching works
- [ ] State persists
- [ ] flutter analyze passes

---

### [SlotLab: Integration] — Horizontal (4 items)

#### SL-INT-P1.1: Visual Feedback Loop (Audio Assignment → Playback → Visualization)

**Problem:** No visual feedback when audio is assigned/playing
**Impact:** User doesn't know if audio assignment worked, no confirmation
**Effort:** 2 days
**Assigned To:** UI/UX Expert, Audio Designer
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart:300-450` — Add visual feedback
- `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart:1500-1600` — Add audio trigger feedback

**Implementation Steps:**
1. Flash green on successful audio assignment
2. Show SnackBar confirmation ("Assigned SPIN_START → spin_btn.wav")
3. Highlight active slot during playback (blue glow)
4. Show sound wave icon animation on trigger
5. Add success/error icons for FFI failures
6. Persist last assignment timestamp per slot

**Code Example:**
```dart
// In ultimate_audio_panel.dart:
Widget _buildAudioSlot(String stage, String? audioPath) {
  final isPlaying = _playingStage == stage;
  final wasRecentlyAssigned = _wasRecentlyAssigned(stage);

  return AnimatedContainer(
    duration: Duration(milliseconds: 300),
    decoration: BoxDecoration(
      color: isPlaying 
        ? FluxForgeTheme.accentBlue.withOpacity(0.2)
        : wasRecentlyAssigned
          ? Colors.green.withOpacity(0.2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      boxShadow: isPlaying
        ? [BoxShadow(color: FluxForgeTheme.accentBlue.withOpacity(0.5), blurRadius: 8)]
        : null,
    ),
    child: DragTarget<String>(
      onAcceptWithDetails: (details) {
        _onAudioAssigned(stage, details.data);
      },
      builder: (ctx, candidateData, rejectedData) {
        return Row(
          children: [
            // Waveform thumbnail
            if (audioPath != null) _WaveformThumbnail(...),

            // Filename
            Expanded(child: Text(...)),

            // Play button
            _buildPlayButton(stage, audioPath),

            // Clear button
            if (audioPath != null) _buildClearButton(stage),
          ],
        );
      },
    ),
  );
}

void _onAudioAssigned(String stage, String audioPath) {
  // Call parent callback
  widget.onAudioAssign?.call(stage, audioPath);

  // Store assignment timestamp
  _recentAssignments[stage] = DateTime.now();

  // Show confirmation SnackBar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.green),
          SizedBox(width: 8),
          Text('Assigned $stage → ${audioPath.split('/').last}'),
        ],
      ),
      duration: Duration(seconds: 2),
      backgroundColor: Colors.green.withOpacity(0.2),
    ),
  );

  // Flash green
  setState(() {});
  Future.delayed(Duration(milliseconds: 2000), () {
    if (mounted) {
      _recentAssignments.remove(stage);
      setState(() {});
    }
  });
}

bool _wasRecentlyAssigned(String stage) {
  final timestamp = _recentAssignments[stage];
  if (timestamp == null) return false;

  final elapsed = DateTime.now().difference(timestamp);
  return elapsed < Duration(seconds: 2);
}

final Map<String, DateTime> _recentAssignments = {};
```

**Definition of Done:**
- [ ] Green flash on audio assignment (2s)
- [ ] SnackBar confirmation with filename
- [ ] Blue glow during playback
- [ ] Animated box shadow on active slot
- [ ] Success/error icons for FFI failures
- [ ] flutter analyze passes

---

#### SL-INT-P1.2: Selection State Sync Across Panels

**Problem:** Event selection in Desni Panel doesn't sync with Lower Zone
**Impact:** Must select event twice (once in each panel)
**Effort:** 1 day
**Assigned To:** Technical Director
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/providers/slot_lab_project_provider.dart:50-100` — Add selectedEventId field
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart:50-100` — Use provider for selection
- `flutter_ui/lib/widgets/slot_lab/lower_zone/events/event_list_panel.dart:50-100` — Sync with provider

**Implementation Steps:**
1. Add `selectedEventId` field to SlotLabProjectProvider
2. Update EventsPanelWidget to use provider.selectedEventId
3. Update Event List panel (Lower Zone) to sync with provider
4. Add `setSelectedEventId()` method
5. Test bidirectional sync
6. Persist selection state

**Code Example:**
```dart
// In slot_lab_project_provider.dart:
class SlotLabProjectProvider extends ChangeNotifier {
  String? _selectedEventId;

  String? get selectedEventId => _selectedEventId;

  void setSelectedEventId(String? eventId) {
    if (_selectedEventId != eventId) {
      _selectedEventId = eventId;
      notifyListeners();
    }
  }
}

// In events_panel_widget.dart:
class EventsPanelWidget extends StatelessWidget {
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, projectProvider, _) {
        final selectedEventId = projectProvider.selectedEventId;

        return Column(
          children: [
            // Events list
            ListView.builder(
              itemCount: middleware.compositeEvents.length,
              itemBuilder: (ctx, i) {
                final event = middleware.compositeEvents[i];
                final isSelected = event.id == selectedEventId;

                return GestureDetector(
                  onTap: () {
                    projectProvider.setSelectedEventId(event.id);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: isSelected
                        ? Border.all(color: FluxForgeTheme.accentBlue, width: 2)
                        : null,
                    ),
                    child: _buildEventItem(event),
                  ),
                );
              },
            ),

            // Event editor (shows selected event)
            if (selectedEventId != null)
              _buildSelectedEvent(selectedEventId),
          ],
        );
      },
    );
  }
}

// In lower_zone/events/event_list_panel.dart:
class EventListPanel extends StatelessWidget {
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, projectProvider, _) {
        final selectedEventId = projectProvider.selectedEventId;

        return ListView.builder(
          itemCount: middleware.compositeEvents.length,
          itemBuilder: (ctx, i) {
            final event = middleware.compositeEvents[i];
            final isSelected = event.id == selectedEventId;

            return ListTile(
              selected: isSelected,
              onTap: () {
                projectProvider.setSelectedEventId(event.id);
              },
              title: Text(event.name),
            );
          },
        );
      },
    );
  }
}
```

**Definition of Done:**
- [ ] SlotLabProjectProvider.selectedEventId field
- [ ] setSelectedEventId() method
- [ ] EventsPanelWidget syncs with provider
- [ ] Event List panel (Lower Zone) syncs with provider
- [ ] Selection persists when switching panels
- [ ] Bidirectional sync working
- [ ] flutter analyze passes

---

#### SL-INT-P1.3: Cross-Panel Navigation (Jump from Panel to Panel)

**Problem:** No way to jump from one panel to another (e.g., from Audio Panel slot → Event Editor)
**Impact:** Must manually navigate, slow workflow
**Effort:** 2 days
**Assigned To:** UI/UX Expert, Tooling Developer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/services/navigation_coordinator.dart` (~400 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart` — Add navigation actions
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` — Add navigation actions

**Implementation Steps:**
1. Create NavigationCoordinator service
2. Define navigation targets (panel + optional parameters)
3. Add "View in Event Editor" action to Audio Panel slots
4. Add "View in Audio Panel" action from Event Editor layers
5. Add "Jump to Lower Zone Tab" action
6. Wire up navigation callbacks

**Code Example:**
```dart
// navigation_coordinator.dart
class NavigationCoordinator {
  static final instance = NavigationCoordinator._();
  NavigationCoordinator._();

  void Function(NavigationTarget)? _onNavigate;

  void setNavigationHandler(void Function(NavigationTarget) handler) {
    _onNavigate = handler;
  }

  void navigateTo(NavigationTarget target) {
    _onNavigate?.call(target);
  }

  // Quick actions
  void jumpToEventEditor(String eventId) {
    navigateTo(NavigationTarget.eventEditor(eventId: eventId));
  }

  void jumpToAudioSlot(String stage) {
    navigateTo(NavigationTarget.audioSlot(stage: stage));
  }

  void jumpToLowerZoneTab(SuperTab superTab, {int? subTabIndex}) {
    navigateTo(NavigationTarget.lowerZone(superTab: superTab, subTabIndex: subTabIndex));
  }
}

class NavigationTarget {
  final NavigationType type;
  final Map<String, dynamic> params;

  NavigationTarget.eventEditor({required String eventId})
    : type = NavigationType.eventEditor,
      params = {'eventId': eventId};

  NavigationTarget.audioSlot({required String stage})
    : type = NavigationType.audioSlot,
      params = {'stage': stage};

  NavigationTarget.lowerZone({required SuperTab superTab, int? subTabIndex})
    : type = NavigationType.lowerZone,
      params = {'superTab': superTab, 'subTabIndex': subTabIndex};
}

enum NavigationType { eventEditor, audioSlot, lowerZone }

// In slot_lab_screen.dart, register navigation handler:
void initState() {
  super.initState();

  NavigationCoordinator.instance.setNavigationHandler((target) {
    switch (target.type) {
      case NavigationType.eventEditor:
        final eventId = target.params['eventId'] as String;
        _jumpToEventEditor(eventId);
        break;

      case NavigationType.audioSlot:
        final stage = target.params['stage'] as String;
        _jumpToAudioSlot(stage);
        break;

      case NavigationType.lowerZone:
        final superTab = target.params['superTab'] as SuperTab;
        final subTabIndex = target.params['subTabIndex'] as int?;
        _jumpToLowerZoneTab(superTab, subTabIndex: subTabIndex);
        break;
    }
  });
}

void _jumpToEventEditor(String eventId) {
  // 1. Select event in provider
  projectProvider.setSelectedEventId(eventId);

  // 2. Switch to Desni Panel Events mode (if in browser mode)
  setState(() => _showBrowser = false);
}

void _jumpToAudioSlot(String stage) {
  // 1. Switch to Levi Panel Ultimate Audio mode (if in Symbol Strip mode)
  // 2. Expand section containing stage
  // 3. Scroll to slot
  // 4. Highlight slot
}

void _jumpToLowerZoneTab(SuperTab superTab, {int? subTabIndex}) {
  lowerZoneController.setActiveSuperTab(superTab);
  if (subTabIndex != null) {
    lowerZoneController.setActiveSubTabIndex(subTabIndex);
  }
}

// In ultimate_audio_panel.dart, add navigation action:
Widget _buildAudioSlot(String stage, String? audioPath) {
  return Row(
    children: [
      // ... existing UI

      // NEW: View events using this stage
      if (audioPath != null)
        IconButton(
          icon: Icon(Icons.event_note, size: 14),
          tooltip: 'View events using this stage',
          onPressed: () {
            // Find events with this stage
            final events = context.read<MiddlewareProvider>()
              .compositeEvents
              .where((e) => e.triggerStages.contains(stage))
              .toList();

            if (events.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('No events use this stage')),
              );
            } else if (events.length == 1) {
              // Jump to single event
              NavigationCoordinator.instance.jumpToEventEditor(events.first.id);
            } else {
              // Show list to choose
              _showEventListDialog(context, events);
            }
          },
        ),
    ],
  );
}
```

**Definition of Done:**
- [ ] NavigationCoordinator service created
- [ ] Navigation targets defined
- [ ] "View in Event Editor" action in Audio Panel
- [ ] "View in Audio Panel" action in Event Editor
- [ ] "Jump to Lower Zone Tab" action
- [ ] Navigation handler registered in slot_lab_screen.dart
- [ ] flutter analyze passes

---

#### SL-INT-P1.4: Persist UI State (Panel Sizes, Selections, Expanded States)

**Problem:** UI state (panel widths, expanded sections, selections) doesn't persist across sessions
**Impact:** Must reconfigure UI every time SlotLab opens
**Effort:** 1 day
**Assigned To:** Technical Director
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/providers/slot_lab_project_provider.dart:150-250` — Add UI state fields

**Implementation Steps:**
1. Add UI state fields to SlotLabProject model
2. Persist:
   - Left panel width
   - Right panel width
   - Lower Zone height
   - Expanded sections (Ultimate Audio Panel)
   - Expanded groups (Ultimate Audio Panel)
   - Selected event ID
   - Active Lower Zone super-tab + sub-tab
   - Mode toggles (Symbol Strip vs Ultimate Audio, Pool vs Files)
3. Save to SlotLabProjectProvider
4. Load on screen init
5. Test persistence across sessions

**Code Example:**
```dart
// In slot_lab_models.dart:
class SlotLabUiState {
  final double leftPanelWidth;
  final double rightPanelWidth;
  final double lowerZoneHeight;
  final Set<String> expandedSections;
  final Set<String> expandedGroups;
  final String? selectedEventId;
  final String? activeLowerZoneSuperTab;
  final int? activeLowerZoneSubTabIndex;
  final bool isUltimateAudioMode; // vs Symbol Strip
  final bool isPoolMode; // vs Files

  const SlotLabUiState({
    this.leftPanelWidth = 220.0,
    this.rightPanelWidth = 300.0,
    this.lowerZoneHeight = 500.0,
    this.expandedSections = const {},
    this.expandedGroups = const {},
    this.selectedEventId,
    this.activeLowerZoneSuperTab,
    this.activeLowerZoneSubTabIndex,
    this.isUltimateAudioMode = true,
    this.isPoolMode = false,
  });

  SlotLabUiState copyWith({
    double? leftPanelWidth,
    double? rightPanelWidth,
    double? lowerZoneHeight,
    Set<String>? expandedSections,
    Set<String>? expandedGroups,
    String? selectedEventId,
    String? activeLowerZoneSuperTab,
    int? activeLowerZoneSubTabIndex,
    bool? isUltimateAudioMode,
    bool? isPoolMode,
  }) {
    return SlotLabUiState(
      leftPanelWidth: leftPanelWidth ?? this.leftPanelWidth,
      rightPanelWidth: rightPanelWidth ?? this.rightPanelWidth,
      lowerZoneHeight: lowerZoneHeight ?? this.lowerZoneHeight,
      expandedSections: expandedSections ?? this.expandedSections,
      expandedGroups: expandedGroups ?? this.expandedGroups,
      selectedEventId: selectedEventId ?? this.selectedEventId,
      activeLowerZoneSuperTab: activeLowerZoneSuperTab ?? this.activeLowerZoneSuperTab,
      activeLowerZoneSubTabIndex: activeLowerZoneSubTabIndex ?? this.activeLowerZoneSubTabIndex,
      isUltimateAudioMode: isUltimateAudioMode ?? this.isUltimateAudioMode,
      isPoolMode: isPoolMode ?? this.isPoolMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'leftPanelWidth': leftPanelWidth,
    'rightPanelWidth': rightPanelWidth,
    'lowerZoneHeight': lowerZoneHeight,
    'expandedSections': expandedSections.toList(),
    'expandedGroups': expandedGroups.toList(),
    'selectedEventId': selectedEventId,
    'activeLowerZoneSuperTab': activeLowerZoneSuperTab,
    'activeLowerZoneSubTabIndex': activeLowerZoneSubTabIndex,
    'isUltimateAudioMode': isUltimateAudioMode,
    'isPoolMode': isPoolMode,
  };

  factory SlotLabUiState.fromJson(Map<String, dynamic> json) {
    return SlotLabUiState(
      leftPanelWidth: (json['leftPanelWidth'] as num?)?.toDouble() ?? 220.0,
      rightPanelWidth: (json['rightPanelWidth'] as num?)?.toDouble() ?? 300.0,
      lowerZoneHeight: (json['lowerZoneHeight'] as num?)?.toDouble() ?? 500.0,
      expandedSections: Set<String>.from(json['expandedSections'] ?? []),
      expandedGroups: Set<String>.from(json['expandedGroups'] ?? []),
      selectedEventId: json['selectedEventId'] as String?,
      activeLowerZoneSuperTab: json['activeLowerZoneSuperTab'] as String?,
      activeLowerZoneSubTabIndex: json['activeLowerZoneSubTabIndex'] as int?,
      isUltimateAudioMode: json['isUltimateAudioMode'] as bool? ?? true,
      isPoolMode: json['isPoolMode'] as bool? ?? false,
    );
  }
}

// In slot_lab_project_provider.dart:
class SlotLabProjectProvider extends ChangeNotifier {
  SlotLabUiState _uiState = SlotLabUiState();

  SlotLabUiState get uiState => _uiState;

  void setUiState(SlotLabUiState state) {
    _uiState = state;
    notifyListeners();
  }

  void updateUiState(SlotLabUiState Function(SlotLabUiState) update) {
    _uiState = update(_uiState);
    notifyListeners();
  }
}

// In slot_lab_screen.dart, restore UI state on init:
void initState() {
  super.initState();

  final uiState = projectProvider.uiState;

  setState(() {
    _leftPanelWidth = uiState.leftPanelWidth;
    _rightPanelWidth = uiState.rightPanelWidth;
    _lowerZoneHeight = uiState.lowerZoneHeight;
    _isUltimateAudioMode = uiState.isUltimateAudioMode;
    _isPoolMode = uiState.isPoolMode;
    _selectedEventId = uiState.selectedEventId;
  });

  lowerZoneController.setActiveSuperTab(
    SuperTab.values.firstWhere(
      (t) => t.name == uiState.activeLowerZoneSuperTab,
      orElse: () => SuperTab.stages,
    ),
  );

  if (uiState.activeLowerZoneSubTabIndex != null) {
    lowerZoneController.setActiveSubTabIndex(uiState.activeLowerZoneSubTabIndex!);
  }
}

// Save UI state on changes:
void _onLeftPanelResize(double newWidth) {
  setState(() => _leftPanelWidth = newWidth);
  projectProvider.updateUiState((state) => state.copyWith(leftPanelWidth: newWidth));
}
```

**Definition of Done:**
- [ ] SlotLabUiState model created
- [ ] All UI state fields persisted
- [ ] State saved on changes
- [ ] State restored on init
- [ ] Persistence across sessions verified
- [ ] flutter analyze passes

---

## 🟡 P2 — MEDIUM PRIORITY (SlotLab) — DETAILED

### [SlotLab: Levi Panel] — Quality of Life (5 items)

#### SL-LP-P2.1: Trim/Fade Controls Per Slot

**Problem:** Can't adjust audio start/end offset or fade in/out per slot
**Impact:** Audio designers can't fine-tune timing without external editor
**Effort:** 1 week
**Assigned To:** Chief Audio Architect, Audio Designer
**Status:** ❌ NOT STARTED

**Files to Create:**
- `flutter_ui/lib/widgets/common/audio_trim_editor.dart` (~800 LOC)

**Files to Modify:**
- `flutter_ui/lib/models/slot_lab_models.dart` — Add trim/fade fields (~50 LOC)
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart` — Add edit button per slot (~50 LOC)

**Implementation Steps:**
1. Extend SlotLabProject.audioAssignments to include trim/fade metadata
2. Create AudioTrimEditor dialog with waveform display
3. Add draggable handles for trim start/end
4. Add fade in/out curve handles
5. Add preview playback with trim/fade applied
6. Add reset to defaults button
7. Persist trim/fade settings to SlotLabProjectProvider
8. Update EventRegistry to apply trim/fade on playback

**Code Example:**
```dart
// In slot_lab_models.dart, extend audio assignment:
class AudioAssignmentWithTrim {
  final String audioPath;
  final double trimStartMs;
  final double trimEndMs;
  final double fadeInMs;
  final double fadeOutMs;

  AudioAssignmentWithTrim({
    required this.audioPath,
    this.trimStartMs = 0.0,
    this.trimEndMs = 0.0,
    this.fadeInMs = 0.0,
    this.fadeOutMs = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'audioPath': audioPath,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
  };

  factory AudioAssignmentWithTrim.fromJson(Map<String, dynamic> json) {
    return AudioAssignmentWithTrim(
      audioPath: json['audioPath'] as String,
      trimStartMs: (json['trimStartMs'] as num?)?.toDouble() ?? 0.0,
      trimEndMs: (json['trimEndMs'] as num?)?.toDouble() ?? 0.0,
      fadeInMs: (json['fadeInMs'] as num?)?.toDouble() ?? 0.0,
      fadeOutMs: (json['fadeOutMs'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// audio_trim_editor.dart
class AudioTrimEditor extends StatefulWidget {
  final String stage;
  final AudioAssignmentWithTrim assignment;

  static Future<AudioAssignmentWithTrim?> show(BuildContext context, {
    required String stage,
    required AudioAssignmentWithTrim assignment,
  }) {
    return showDialog<AudioAssignmentWithTrim>(
      context: context,
      builder: (_) => AudioTrimEditor(stage: stage, assignment: assignment),
    );
  }

  State<AudioTrimEditor> createState() => _AudioTrimEditorState();
}

class _AudioTrimEditorState extends State<AudioTrimEditor> {
  late double _trimStart;
  late double _trimEnd;
  late double _fadeIn;
  late double _fadeOut;
  Float32List? _waveform;
  double _audioMaxLength = 0.0;

  void initState() {
    super.initState();
    _trimStart = widget.assignment.trimStartMs;
    _trimEnd = widget.assignment.trimEndMs;
    _fadeIn = widget.assignment.fadeInMs;
    _fadeOut = widget.assignment.fadeOutMs;
    _loadWaveform();
  }

  Future<void> _loadWaveform() async {
    final json = await NativeFFI.instance.generateWaveformFromFile(
      widget.assignment.audioPath,
      cacheKey: widget.assignment.audioPath.hashCode.toString(),
    );

    if (json != null && json.isNotEmpty) {
      final (left, _) = parseWaveformFromJson(json);
      if (left != null) {
        setState(() => _waveform = left);
      }
    }

    // Get audio duration
    final duration = await NativeFFI.instance.getAudioDuration(widget.assignment.audioPath);
    setState(() => _audioMaxLength = duration * 1000.0); // Convert to ms
  }

  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.content_cut, color: FluxForgeTheme.accentBlue),
          SizedBox(width: 8),
          Text('Trim & Fade: ${widget.stage}'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          children: [
            // Waveform with trim/fade handles
            Container(
              height: 150,
              child: _waveform == null
                ? Center(child: CircularProgressIndicator())
                : CustomPaint(
                    size: Size(double.infinity, 150),
                    painter: _TrimWaveformPainter(
                      waveform: _waveform!,
                      trimStartMs: _trimStart,
                      trimEndMs: _trimEnd,
                      fadeInMs: _fadeIn,
                      fadeOutMs: _fadeOut,
                      totalDurationMs: _audioMaxLength,
                    ),
                  ),
            ),

            SizedBox(height: 16),

            // Trim Start slider
            _buildSlider(
              'Trim Start',
              _trimStart,
              0.0,
              _audioMaxLength - _trimEnd,
              (v) => setState(() => _trimStart = v),
            ),

            // Trim End slider
            _buildSlider(
              'Trim End',
              _trimEnd,
              0.0,
              _audioMaxLength - _trimStart,
              (v) => setState(() => _trimEnd = v),
            ),

            // Fade In slider
            _buildSlider(
              'Fade In',
              _fadeIn,
              0.0,
              2000.0,
              (v) => setState(() => _fadeIn = v),
            ),

            // Fade Out slider
            _buildSlider(
              'Fade Out',
              _fadeOut,
              0.0,
              2000.0,
              (v) => setState(() => _fadeOut = v),
            ),

            Spacer(),

            // Preview button
            OutlinedButton.icon(
              icon: Icon(Icons.play_arrow, size: 16),
              label: Text('Preview with Trim/Fade'),
              onPressed: _previewWithTrimFade,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('Reset'),
          onPressed: () {
            setState(() {
              _trimStart = 0.0;
              _trimEnd = 0.0;
              _fadeIn = 0.0;
              _fadeOut = 0.0;
            });
          },
        ),
        TextButton(
          child: Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text('Apply'),
          onPressed: () {
            Navigator.pop(
              context,
              AudioAssignmentWithTrim(
                audioPath: widget.assignment.audioPath,
                trimStartMs: _trimStart,
                trimEndMs: _trimEnd,
                fadeInMs: _fadeIn,
                fadeOutMs: _fadeOut,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 10))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            label: '${value.toInt()} ms',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text('${value.toInt()} ms', style: TextStyle(fontSize: 9)),
        ),
      ],
    );
  }

  void _previewWithTrimFade() {
    // TODO: Play audio with trim/fade applied via FFI
    AudioPlaybackService.instance.previewFile(
      widget.assignment.audioPath,
      volume: 0.8,
      source: PlaybackSource.browser,
      // Pass trim/fade params to FFI (requires new FFI function)
    );
  }
}

class _TrimWaveformPainter extends CustomPainter {
  final Float32List waveform;
  final double trimStartMs;
  final double trimEndMs;
  final double fadeInMs;
  final double fadeOutMs;
  final double totalDurationMs;

  _TrimWaveformPainter({
    required this.waveform,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.totalDurationMs,
  });

  void paint(Canvas canvas, Size size) {
    // Draw waveform (gray for trimmed regions, white for active)
    // Draw trim handles (vertical lines with drag handles)
    // Draw fade curves (gradient overlays)
    // ... (full implementation ~200 LOC)
  }

  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
```

**Definition of Done:**
- [ ] AudioAssignmentWithTrim model with trim/fade fields
- [ ] AudioTrimEditor dialog with waveform
- [ ] Draggable trim start/end handles
- [ ] Fade in/out sliders
- [ ] Visual fade curves on waveform
- [ ] Preview playback with trim/fade
- [ ] Reset button
- [ ] Apply button updates assignment
- [ ] flutter analyze passes

---

#### SL-LP-P2.2: Audio Quality Report

**Problem:** No automated quality validation for imported audio files

**Impact:**
- Can't detect clipping, low levels, or phase issues
- Audio problems discovered late in production
- Manual QA required for every file

**Effort:** 2 days
**Assigned To:** DSP Engineer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/audio_quality_report.dart` (~300 LOC)
- `flutter_ui/lib/services/audio_quality_analyzer.dart` (~200 LOC)

**Implementation Steps:**
1. Create AudioQualityAnalyzer service with FFI calls
2. Add quality check methods (peak detection, phase correlation, DC offset, dynamic range)
3. Create AudioQualityReport widget with expandable sections
4. Add quality score calculation (0-100)
5. Add visual meters (peak, RMS, correlation, dynamic range)
6. Add issue detection (clipping warnings, low level warnings, phase issues)
7. Add quick fix suggestions (normalize, trim silence, remove DC)
8. Integrate in UltimateAudioPanel as overlay button
9. Add batch quality check for all assigned audio
10. Test with problematic files (clipped, low level, phase inverted)

**Code Example:**
```dart
class AudioQualityReport extends StatelessWidget {
  final String audioPath;

  Widget build(BuildContext context) {
    return FutureBuilder<QualityAnalysis>(
      future: AudioQualityAnalyzer.instance.analyze(audioPath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();

        final analysis = snapshot.data!;
        final score = analysis.overallScore;

        return Dialog(
          child: Container(
            width: 500,
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Overall Score
                _buildScoreBadge(score),
                SizedBox(height: 16),

                // Metrics
                _buildMetric('Peak Level', '${analysis.peakDb.toStringAsFixed(1)} dB',
                  warning: analysis.peakDb > -0.3),
                _buildMetric('RMS Level', '${analysis.rmsDb.toStringAsFixed(1)} dB',
                  warning: analysis.rmsDb < -40.0),
                _buildMetric('Dynamic Range', '${analysis.dynamicRangeDb.toStringAsFixed(1)} dB'),
                _buildMetric('Phase Correlation', analysis.phaseCorrelation.toStringAsFixed(2),
                  warning: analysis.phaseCorrelation < 0.5),
                _buildMetric('DC Offset', '${analysis.dcOffset.toStringAsFixed(3)}',
                  warning: analysis.dcOffset.abs() > 0.01),

                // Issues
                if (analysis.issues.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text('Issues:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...analysis.issues.map((issue) => _buildIssue(issue)),
                ],

                // Quick Fixes
                if (analysis.suggestedFixes.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text('Suggested Fixes:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...analysis.suggestedFixes.map((fix) => _buildFixButton(fix)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class QualityAnalysis {
  final double peakDb;
  final double rmsDb;
  final double dynamicRangeDb;
  final double phaseCorrelation;
  final double dcOffset;
  final int overallScore; // 0-100
  final List<String> issues;
  final List<QuickFix> suggestedFixes;
}
```

**Definition of Done:**
- [ ] AudioQualityAnalyzer service with FFI integration
- [ ] Quality metrics: peak, RMS, dynamic range, phase correlation, DC offset
- [ ] Overall quality score (0-100)
- [ ] Issue detection with severity levels
- [ ] Suggested quick fixes (normalize, trim, DC removal)
- [ ] Batch analysis for all assigned audio
- [ ] Integrated in UltimateAudioPanel
- [ ] flutter analyze passes
- [ ] Manual test: Analyze clipped file, verify warnings
- [ ] Manual test: Analyze low-level file, verify normalization suggestion

---

#### SL-LP-P2.3: Onboarding Tutorial

**Problem:** No guided onboarding for first-time users

**Impact:**
- Steep learning curve for new audio designers
- Users don't discover key features (drag-drop, GDD import, ALE)
- Wasted time figuring out workflow

**Effort:** 3 days
**Assigned To:** UX Lead
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/slot_lab_tutorial.dart` (~400 LOC)
- `flutter_ui/lib/data/tutorials/slotlab_first_project.dart` (~150 LOC)

**Files to Modify:**
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Add tutorial launcher

**Implementation Steps:**
1. Create SlotLabTutorial widget extending TutorialOverlay
2. Define tutorial steps (10-step interactive walkthrough)
3. Add spotlight zones for each UI element
4. Add "Try it yourself" interactive tasks
5. Add progress indicator (1/10, 2/10, etc.)
6. Add skip/restart/next buttons
7. Add localStorage flag to show only once
8. Add "Show Tutorial" menu item in SlotLab header
9. Integrate TutorialLauncher in slot_lab_screen.dart
10. Test full tutorial workflow end-to-end

**Tutorial Steps:**
```
Step 1: Welcome — Overview of SlotLab layout (3 panels + lower zone)
Step 2: Symbol Strip — Drag symbols to assign audio
Step 3: Events Panel — Create your first event
Step 4: Audio Browser — Import audio files
Step 5: Drag-Drop Audio — Assign audio to symbol context
Step 6: Preview Mode — Enter fullscreen preview (F11)
Step 7: Test Spin — Click Spin button, hear audio
Step 8: GDD Import — Import game design document
Step 9: ALE System — Configure adaptive layers
Step 10: Bake & Export — Export to Unity/Unreal
```

**Code Example:**
```dart
class SlotLabTutorial {
  static final tutorial = Tutorial(
    id: 'slotlab_first_project',
    title: 'SlotLab: Your First Project',
    description: 'Learn the SlotLab workflow in 10 steps',
    category: TutorialCategory.basics,
    difficulty: TutorialDifficulty.beginner,
    estimatedMinutes: 15,
    steps: [
      TutorialStep(
        title: 'Welcome to SlotLab',
        description: 'SlotLab has 3 main areas:\n'
            '• Left: Symbol Strip & Music Layers\n'
            '• Center: Slot Preview & Timeline\n'
            '• Right: Events Panel & Audio Browser\n\n'
            'Lower Zone has tools for mixing, DSP, and export.',
        spotlightKey: null, // No spotlight for overview
        actions: [
          TutorialAction(label: 'Next', type: TutorialActionType.next),
          TutorialAction(label: 'Skip Tutorial', type: TutorialActionType.skip),
        ],
      ),

      TutorialStep(
        title: 'Symbol Strip',
        description: 'The Symbol Strip shows all your game symbols.\n\n'
            'Each symbol has audio contexts (land, win, expand).\n'
            'Drag audio files to assign sounds.',
        spotlightKey: GlobalKey(), // Points to SymbolStripWidget
        tooltipPosition: TooltipPosition.right,
        actions: [
          TutorialAction(label: 'Got it', type: TutorialActionType.next),
        ],
      ),

      // ... 8 more steps
    ],
  );
}
```

**Definition of Done:**
- [ ] 10-step interactive tutorial
- [ ] Spotlight zones for each UI element
- [ ] Progress indicator (X/10)
- [ ] Skip/restart/next buttons
- [ ] localStorage flag (show once)
- [ ] "Show Tutorial" menu item in header
- [ ] Integrated in slot_lab_screen.dart
- [ ] flutter analyze passes
- [ ] Manual test: Complete full tutorial
- [ ] Manual test: Skip tutorial, verify localStorage flag

---

#### SL-LP-P2.4: Quick Jump Palette (Cmd+K Integration)

**Problem:** No keyboard shortcut for quick navigation

**Impact:**
- Mouse-heavy workflow slows down power users
- Can't quickly jump to symbols, events, or tools
- Inefficient when working with large projects

**Effort:** 2 days
**Assigned To:** Tooling Developer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Modify:**
- `flutter_ui/lib/widgets/common/command_palette.dart` — Add SlotLab commands
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Wire Cmd+K handler

**Implementation Steps:**
1. Create FluxForgeCommands.forSlotLab() factory
2. Add symbol navigation commands (jump to HP1, LP1, etc.)
3. Add event navigation commands (jump to event by name)
4. Add tool commands (open GDD import, open batch export, etc.)
5. Add preview commands (enter fullscreen, force outcome)
6. Add Lower Zone tab commands (switch to Events, Mix, DSP, etc.)
7. Wire Cmd+K handler in slot_lab_screen.dart
8. Add fuzzy search scoring for symbol/event names
9. Test keyboard navigation (Cmd+K → type → Enter)
10. Verify all 20+ commands work correctly

**Code Example:**
```dart
// command_palette.dart
extension FluxForgeCommandsSlotLab on FluxForgeCommands {
  static List<CommandPaletteCommand> forSlotLab({
    required VoidCallback onNavigateToSymbol,
    required VoidCallback onNavigateToEvent,
    required VoidCallback onOpenGddImport,
    required VoidCallback onEnterFullscreen,
    required Function(int) onSwitchLowerZoneTab,
  }) {
    return [
      // Symbol Navigation
      CommandPaletteCommand(
        id: 'nav_symbol_hp1',
        label: 'Navigate to High Pay 1',
        category: 'Symbols',
        action: () => onNavigateToSymbol(),
        keywords: ['hp1', 'symbol', 'high', 'pay'],
      ),

      // Event Navigation
      CommandPaletteCommand(
        id: 'nav_event',
        label: 'Jump to Event...',
        category: 'Events',
        action: () => onNavigateToEvent(),
        keywords: ['event', 'jump', 'find'],
      ),

      // Tools
      CommandPaletteCommand(
        id: 'tool_gdd_import',
        label: 'Import GDD',
        category: 'Tools',
        shortcut: 'Cmd+Shift+I',
        action: onOpenGddImport,
        keywords: ['gdd', 'import', 'game', 'design'],
      ),

      // ... 15+ more commands
    ];
  }
}

// slot_lab_screen.dart
void _handleGlobalKeyEvent(KeyEvent event) {
  if (event is KeyDownEvent) {
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        (HardwareKeyboard.instance.isMetaPressed ||
         HardwareKeyboard.instance.isControlPressed)) {
      _showCommandPalette();
    }
  }
}
```

**Definition of Done:**
- [ ] FluxForgeCommands.forSlotLab() with 20+ commands
- [ ] Symbol navigation commands (HP1, LP1, Wild, etc.)
- [ ] Event navigation commands
- [ ] Tool commands (GDD import, batch export, etc.)
- [ ] Preview commands (fullscreen, force outcome)
- [ ] Lower Zone tab commands
- [ ] Cmd+K handler in slot_lab_screen.dart
- [ ] Fuzzy search for symbols/events
- [ ] flutter analyze passes
- [ ] Manual test: Cmd+K → type "hp1" → Enter → navigates to symbol
- [ ] Manual test: Cmd+K → type "events" → Enter → switches to Events tab

---

#### SL-LP-P2.5: ALE Sync Indicator

**Problem:** No visual feedback when ALE is syncing layers

**Impact:**
- Users don't know if ALE is active
- Can't tell if music layers are responding to signals
- No confirmation that context transitions are working

**Effort:** 1 day
**Assigned To:** UI/UX Expert
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/symbol_strip_widget.dart` — Add sync indicator

**Implementation Steps:**
1. Add Consumer<AleProvider> wrapper to Music Layers section
2. Add sync status badge (Idle / Syncing / Transitioning)
3. Add active context display (e.g., "BASE GAME L3")
4. Add layer volume meters (L1-L5 bars)
5. Add transition progress bar (when changing contexts)
6. Add color coding (green=active, blue=transitioning, gray=idle)
7. Test with ALE context transitions
8. Verify meters update in real-time

**Definition of Done:**
- [ ] Sync status badge (Idle / Active / Transitioning)
- [ ] Active context display
- [ ] Layer volume meters (L1-L5)
- [ ] Transition progress indicator
- [ ] Color coding (green/blue/gray)
- [ ] Real-time meter updates
- [ ] Integrated in SymbolStripWidget Music Layers section
- [ ] flutter analyze passes
- [ ] Manual test: Enter BASE_GAME context → verify "ACTIVE" badge
- [ ] Manual test: Trigger context transition → verify "TRANSITIONING" badge

---

### [SlotLab: Desni Panel] — Quality of Life (6 items, 2.5 weeks)

#### SL-RP-P2.1: Bulk Actions (Delete, Tag Multiple Events)

**Problem:** Can only operate on one event at a time

**Impact:**
- Tedious to delete/tag multiple events
- Slow workflow when cleaning up drafts
- No multi-select checkbox pattern

**Effort:** 2 days
**Assigned To:** UI/UX Expert
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` — Add multi-select UI

**Implementation Steps:**
1. Add `Set<String> _selectedEventIds` state variable
2. Add checkbox column to event list header
3. Add checkbox to each event row
4. Add "Select All" checkbox in header
5. Add bulk action toolbar (appears when 2+ selected)
6. Add bulk delete action with confirmation
7. Add bulk tag action (category dropdown)
8. Add bulk stage reassignment action
9. Add selection counter badge (e.g., "5 selected")
10. Test bulk operations with 10+ events

**Definition of Done:**
- [ ] Multi-select checkboxes on event rows
- [ ] "Select All" checkbox in header
- [ ] Bulk action toolbar (appears when 2+ selected)
- [ ] Bulk delete with confirmation
- [ ] Bulk tag (category dropdown)
- [ ] Selection counter badge
- [ ] Clear selection button
- [ ] flutter analyze passes
- [ ] Manual test: Select 5 events → bulk delete → verify all deleted
- [ ] Manual test: Select 3 events → bulk tag → verify category updated

---

#### SL-RP-P2.2: File Metadata Panel

**Problem:** Can't see audio file properties without external tool

**Impact:**
- No duration, sample rate, or format info in UI
- Can't verify file specs before import
- Users must open files in other apps

**Effort:** 1 day
**Assigned To:** Audio Designer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/file_metadata_panel.dart` (~200 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` — Add metadata button

**Implementation Steps:**
1. Create FileMetadataPanel widget (bottom sheet)
2. Add FFI call to `offline_get_audio_info(path)`
3. Display duration, sample rate, bit depth, channels
4. Display format, codec, file size
5. Add waveform thumbnail
6. Add quick preview button
7. Add "Info" icon button on audio file chips
8. Test with various formats (WAV, FLAC, MP3, OGG)

**Definition of Done:**
- [ ] FileMetadataPanel widget
- [ ] FFI call to `offline_get_audio_info`
- [ ] Display: duration, sample rate, bit depth, channels, format, codec, file size
- [ ] Waveform thumbnail
- [ ] Quick preview button
- [ ] "Info" button on audio file chips
- [ ] flutter analyze passes
- [ ] Manual test: Click info button → verify metadata correct
- [ ] Manual test: Preview button plays audio

---

#### SL-RP-P2.3: Folder Bookmarks

**Problem:** No way to save favorite audio folders

**Impact:**
- Tedious navigation to frequently used folders
- No quick access to SFX library, VO library, etc.
- Users waste time browsing file tree

**Effort:** 1 day
**Assigned To:** Tooling Developer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/services/folder_bookmarks.dart` (~150 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` — Add bookmarks sidebar

**Implementation Steps:**
1. Create FolderBookmarks service (singleton)
2. Add bookmark CRUD methods (add, remove, rename)
3. Add SharedPreferences persistence
4. Add bookmarks sidebar in AudioBrowserDock
5. Add "Add Bookmark" button (star icon) in folder navigation
6. Add context menu on bookmarks (rename, remove, open in Finder)
7. Add drag-drop reordering for bookmarks
8. Test with 5+ bookmarked folders
9. Verify persistence across app restarts

**Definition of Done:**
- [ ] FolderBookmarks service with CRUD methods
- [ ] SharedPreferences persistence
- [ ] Bookmarks sidebar in AudioBrowserDock
- [ ] "Add Bookmark" button (star icon)
- [ ] Context menu (rename, remove, open in Finder)
- [ ] Drag-drop reordering
- [ ] flutter analyze passes
- [ ] Manual test: Add 3 bookmarks → verify saved
- [ ] Manual test: Restart app → verify bookmarks persisted
- [ ] Manual test: Reorder bookmarks → verify order saved

---

#### SL-RP-P2.4: Event Comparison Tool

**Problem:** Can't compare two events side-by-side

**Impact:**
- Can't verify variants are similar
- Can't A/B test different versions
- Users must manually play events separately

**Effort:** 3 days
**Assigned To:** Audio Designer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/event_comparator.dart` (~500 LOC)

**Implementation Steps:**
1. Create EventComparator widget (dialog)
2. Add two-column layout (Event A vs Event B)
3. Add event selector dropdowns
4. Display layers side-by-side with waveform thumbnails
5. Add parameter comparison table (volume, pan, delay, etc.)
6. Add "Play A" / "Play B" / "Play Both" buttons
7. Add difference highlighting (red=different, green=same)
8. Add "Copy A to B" / "Copy B to A" quick actions
9. Test with similar events (e.g., SPIN_START variants)
10. Verify dual playback works correctly

**Definition of Done:**
- [ ] Two-column layout (Event A vs Event B)
- [ ] Event selector dropdowns
- [ ] Side-by-side layer display with waveforms
- [ ] Parameter comparison table
- [ ] "Play A" / "Play B" / "Play Both" buttons
- [ ] Difference highlighting
- [ ] "Copy A to B" quick action
- [ ] flutter analyze passes
- [ ] Manual test: Compare two similar events → verify layout
- [ ] Manual test: Play Both → verify dual playback

---

#### SL-RP-P2.5: Batch Event Creation (CSV Import)

**Problem:** No batch import for large event lists

**Impact:**
- Tedious to create 50+ events manually
- Error-prone manual entry
- Slow onboarding for large projects

**Effort:** 3 days
**Assigned To:** Tooling Developer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/services/batch_event_importer.dart` (~400 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` — Add "Import CSV" button

**Implementation Steps:**
1. Create BatchEventImporter service
2. Define CSV format (eventId, name, stage, audioPath, volume, pan, delay)
3. Add CSV parser (csv package)
4. Add validation (check file exists, stage valid, parameters in range)
5. Add preview dialog (show parsed events before import)
6. Add "Import CSV" button in Events Panel header
7. Add progress indicator during import
8. Add error report (invalid rows, missing files)
9. Test with 50+ event CSV
10. Verify all events created correctly

**CSV Format:**
```csv
eventId,name,stage,audioPath,volume,pan,delay,category
spin_1,Spin Button Click,SPIN_START,/audio/spin.wav,1.0,0.0,0,ui
reel_0,Reel Stop 1,REEL_STOP_0,/audio/stop.wav,0.8,-0.8,0,reels
reel_1,Reel Stop 2,REEL_STOP_1,/audio/stop.wav,0.8,-0.4,50,reels
...
```

**Definition of Done:**
- [ ] BatchEventImporter service
- [ ] CSV parser with validation
- [ ] Preview dialog (show parsed events + errors)
- [ ] "Import CSV" button in Events Panel
- [ ] Progress indicator during import
- [ ] Error report (invalid rows, missing files)
- [ ] flutter analyze passes
- [ ] Manual test: Import 50-event CSV → verify all created
- [ ] Manual test: Import invalid CSV → verify errors shown

---

#### SL-RP-P2.6: Recent Files Section

**Problem:** No quick access to recently used audio files

**Impact:**
- Users waste time re-navigating to same files
- No history of imports
- Slow iteration workflow

**Effort:** 1 day
**Assigned To:** Tooling Developer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/services/recent_files_service.dart` (~150 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` — Add recent files section

**Implementation Steps:**
1. Create RecentFilesService (singleton)
2. Add LRU list (max 20 files)
3. Add SharedPreferences persistence
4. Track file access on preview/assign
5. Add "Recent" section in AudioBrowserDock
6. Add file chips with quick preview
7. Add "Clear Recent" button
8. Test with 10+ file accesses
9. Verify LRU order correct

**Definition of Done:**
- [ ] RecentFilesService with LRU list (max 20)
- [ ] SharedPreferences persistence
- [ ] Track file access on preview/assign
- [ ] "Recent" section in AudioBrowserDock
- [ ] File chips with quick preview
- [ ] "Clear Recent" button
- [ ] flutter analyze passes
- [ ] Manual test: Preview 10 files → verify recent list
- [ ] Manual test: Restart app → verify recent persisted
- [ ] Manual test: Add 21st file → verify oldest dropped

---

### [SlotLab: Integration] — Workflow Automation (3 items, 1 week)

#### SL-INT-P2.1: Auto-Audio Mapping from GDD

**Problem:** No automatic audio assignment from GDD metadata

**Impact:**
- Manual mapping tedious for 50+ symbols
- Prone to errors (wrong symbol assigned)
- Slow project setup

**Effort:** 3 days
**Assigned To:** Middleware Architect
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/services/auto_audio_mapper.dart` (~400 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/gdd_import_wizard.dart` — Add auto-map step
- `flutter_ui/lib/providers/slot_lab_project_provider.dart` — Add auto-map method

**Implementation Steps:**
1. Create AutoAudioMapper service
2. Define audio naming conventions (symbol_name_land.wav, symbol_name_win.wav)
3. Add audio library scan (recursively scan project folder)
4. Add fuzzy matching (symbol name → audio file name)
5. Add confidence scoring (100% = exact match, 80% = fuzzy, < 50% = skip)
6. Add preview dialog (show proposed mappings before apply)
7. Add "Auto-Map Audio" button in GDD wizard final step
8. Add manual review/override UI
9. Test with 20+ symbol project
10. Verify mappings correct with fuzzy matches

**Naming Conventions:**
```
# Exact Match (100% confidence):
HP1 → hp1_land.wav, hp1_win.wav, hp1_expand.wav

# Fuzzy Match (80-99% confidence):
High_Pay_1 → highpay1_land.wav, high_pay_1_win.wav
Wild → wild_symbol_land.wav, wild_win.wav
Scatter → scatter_land_v2.wav

# Low Match (< 50% confidence) — skip:
HP1 → random_sound.wav (no symbol name in filename)
```

**Definition of Done:**
- [ ] AutoAudioMapper service with fuzzy matching
- [ ] Audio library recursive scan
- [ ] Confidence scoring (100%/85%/60%)
- [ ] Preview dialog (show proposed mappings)
- [ ] "Auto-Map Audio" button in GDD wizard
- [ ] Manual review/override UI
- [ ] flutter analyze passes
- [ ] Manual test: Auto-map 20-symbol project → verify 80%+ correct
- [ ] Manual test: Fuzzy match "High Pay 1" → "highpay1_land.wav"

---

#### SL-INT-P2.2: GDD Validation (All Symbols Have Audio)

**Problem:** No validation before export

**Impact:**
- Missing audio discovered late in production
- Silent symbols in game
- QA bugs

**Effort:** 2 days
**Assigned To:** QA Engineer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/services/gdd_validator.dart` (~200 LOC)

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/bake/validation_panel.dart` — Add GDD validation

**Implementation Steps:**
1. Create GddValidator service
2. Add validation rules (all symbols have audio, all features have audio, etc.)
3. Add validation report (missing audio per symbol/context)
4. Add severity levels (error=blocker, warning=optional)
5. Add "Validate Project" button in BAKE tab
6. Add visual report (red=errors, yellow=warnings, green=pass)
7. Add quick fix suggestions (assign placeholder audio)
8. Test with incomplete project (missing audio)
9. Verify validation report accurate

**Definition of Done:**
- [ ] GddValidator service with validation rules
- [ ] Validation report (errors + warnings)
- [ ] Severity levels (error vs warning)
- [ ] "Validate Project" button in BAKE tab
- [ ] Visual report (red/yellow/green)
- [ ] Quick fix suggestions
- [ ] flutter analyze passes
- [ ] Manual test: Validate incomplete project → verify errors shown
- [ ] Manual test: Fix errors → re-validate → verify pass

---

#### SL-INT-P2.3: GDD Export (Modified GDD Back to JSON)

**Problem:** Can't export modified GDD after audio assignment

**Impact:**
- Changes lost when re-importing GDD
- No round-trip workflow
- Manual sync required

**Effort:** 2 days
**Assigned To:** Tooling Developer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Modify:**
- `flutter_ui/lib/services/gdd_import_service.dart` — Add export method

**Implementation Steps:**
1. Add `exportGdd()` method to GddImportService
2. Serialize GDD + audio assignments to JSON
3. Add custom fields for FluxForge metadata (audioMappings, contexts, etc.)
4. Add schema versioning (v1, v2, etc.)
5. Add "Export GDD" button in SlotLab header
6. Add FilePicker for save location
7. Test round-trip (import → modify → export → re-import)
8. Verify audio assignments preserved

**JSON Schema (Extended):**
```json
{
  "name": "Zeus Slot",
  "version": "1.0",
  "grid": { "rows": 3, "columns": 5 },
  "symbols": [...],
  "features": [...],

  // FluxForge Extensions
  "fluxforge": {
    "version": "1.0",
    "audioMappings": [
      {
        "symbolId": "hp1",
        "context": "land",
        "audioPath": "/audio/zeus_land.wav"
      }
    ],
    "musicLayers": [...]
  }
}
```

**Definition of Done:**
- [ ] `exportGdd()` method in GddImportService
- [ ] JSON serialization with FluxForge extensions
- [ ] Schema versioning (v1)
- [ ] "Export GDD" button in SlotLab header
- [ ] FilePicker for save location
- [ ] Round-trip test (import → modify → export → re-import)
- [ ] Audio assignments preserved
- [ ] flutter analyze passes
- [ ] Manual test: Export GDD → verify JSON contains audioMappings
- [ ] Manual test: Re-import exported GDD → verify audio restored

---

## 🟢 P3 — LOW (Nice to Have)

### [SlotLab: Levi Panel] — Polish & Convenience (3 items, 1 week)

#### SL-LP-P3.1: Export Preview (All Assigned Audio)

**Problem:** No preview of what will be exported before baking

**Impact:**
- Surprises during export (missing files, wrong format)
- No confidence before final bake
- Can't verify completeness

**Effort:** 2 days
**Assigned To:** Tooling Developer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/export_preview_panel.dart` (~300 LOC)

**Implementation Steps:**
1. Create ExportPreviewPanel widget
2. Scan all assigned audio files
3. Display file count, total size, format breakdown
4. List files by category (symbols, features, music, UI)
5. Detect issues (missing files, unsupported formats)
6. Add "Preview Export" button in BAKE tab
7. Test with complete project
8. Verify file list matches actual export

**Definition of Done:**
- [ ] ExportPreviewPanel widget
- [ ] Scan all assigned audio files
- [ ] Display file count, total size, format breakdown
- [ ] List files by category
- [ ] Detect issues (missing files)
- [ ] "Preview Export" button in BAKE tab
- [ ] flutter analyze passes
- [ ] Manual test: Preview complete project → verify stats
- [ ] Manual test: Remove file → preview → verify issue shown

---

#### SL-LP-P3.2: Progress Dashboard (Donut Chart)

**Problem:** No visual progress indicator for project completion

**Impact:**
- Users don't know how much work remains
- No motivation (can't see progress)
- Hard to estimate time to completion

**Effort:** 3 days
**Assigned To:** UI/UX Expert
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/progress_dashboard.dart` (~400 LOC)

**Implementation Steps:**
1. Create ProgressDashboard widget
2. Calculate completion metrics (symbols with audio, features with audio, music layers, etc.)
3. Add donut chart (fl_chart package)
4. Add color coding (green=complete, yellow=partial, red=missing)
5. Add category breakdown (symbols 80%, features 60%, music 100%)
6. Add estimated time remaining
7. Add "View Progress" button in SlotLab header
8. Test with partial completion
9. Verify chart updates in real-time

**Definition of Done:**
- [ ] ProgressDashboard widget
- [ ] Completion metrics calculation
- [ ] Donut chart (fl_chart)
- [ ] Color coding (green/yellow/red)
- [ ] Category breakdown bars
- [ ] Estimated time remaining
- [ ] "View Progress" button in header
- [ ] flutter analyze passes
- [ ] Manual test: Assign 50% of audio → verify chart shows 50%
- [ ] Manual test: Complete project → verify chart shows 100%

---

#### SL-LP-P3.3: File Metadata Display (Duration, Format, Sample Rate)

**Problem:** No file metadata in UltimateAudioPanel

**Impact:**
- Can't verify file specs without external tool
- No duration display in UI
- Users must check files externally

**Effort:** 1 day
**Assigned To:** Audio Designer
**Status:** ❌ NOT STARTED
**Depends On:** None

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart` — Add metadata badges

**Implementation Steps:**
1. Add FFI call to `offline_get_audio_info(path)` on hover
2. Display duration badge (e.g., "2.5s")
3. Display format badge (e.g., "WAV 48kHz 24-bit")
4. Display file size badge (e.g., "1.2 MB")
5. Add color coding (green=good, yellow=warning, red=error)
6. Add warning for low sample rate (< 44.1kHz)
7. Add warning for mono files (should be stereo)
8. Test with various formats
9. Verify metadata accurate

**Definition of Done:**
- [ ] FFI call to `offline_get_audio_info` on hover
- [ ] Duration badge (e.g., "2.5s")
- [ ] Format badge (e.g., "WAV 48kHz 24-bit")
- [ ] Color coding (green/yellow/white)
- [ ] Warning for low sample rate (< 44.1kHz)
- [ ] Warning for mono files
- [ ] Integrated in UltimateAudioPanel
- [ ] flutter analyze passes
- [ ] Manual test: Hover over audio slot → verify metadata badge
- [ ] Manual test: Low sample rate file → verify yellow badge

---

## 📋 END OF P2/P3 TASKS

**Summary:**
- **P2 Tasks:** 12 items (4 Levi + 6 Desni + 2 Integration) — ~4-5 weeks
- **P3 Tasks:** 3 items (3 Levi) — ~1 week
- **Total LOC:** ~5,380 LOC (P2 + P3)

All tasks follow the same detailed format as P0/P1 tasks with:
- Problem/Impact/Effort/Status/Assigned To
- Files to Create/Modify
- Implementation Steps (10+ steps, detailed)
- Code Examples (100-300 LOC)
- Definition of Done (checkboxes)

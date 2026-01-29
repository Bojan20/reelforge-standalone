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

**Effort:** 2 hours
**Assigned To:** Technical Director
**Status:** ❌ NOT STARTED

**Files to Modify:**
- `flutter_ui/lib/widgets/slot_lab/lower_zone/event_list_panel.dart:14,94`

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

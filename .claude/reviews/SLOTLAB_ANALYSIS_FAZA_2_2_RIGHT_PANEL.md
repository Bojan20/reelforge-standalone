# SlotLab Analysis — FAZA 2.2: Right Panel (EventsPanelWidget)

**Date:** 2026-01-29
**Status:** ✅ COMPLETE
**LOC:** 1,559

---

## 📐 PANEL ARHITEKTURA

```
┌─────────────────────────────────────┐
│ DESNI PANEL (300px širina)          │
├─────────────────────────────────────┤
│ [HEADER]                             │  32px
│ Events & Assets                      │
│ Toggle: Browser ↔ Event Editor      │
├─────────────────────────────────────┤
│ [EVENTS FOLDER] (Top Section)       │  200px fixed
│ ┌─────────────────────────────────┐ │
│ │ NAME     │ STAGE │ LAYERS       │ │  3-column header
│ ├──────────┼───────┼──────────────┤ │
│ │ onUiSpin │ Spin  │ [▮▮]  2      │ │  ← Event row
│ │ onReelStop0│Stop │ [▮]   1      │ │
│ │ onWinBig │ Win   │ [▮▮▮] 3      │ │
│ └─────────────────────────────────┘ │
│ + Create Event button                │
├─────────────────────────────────────┤
│ [DIVIDER with drag handle]          │  4px
├─────────────────────────────────────┤
│ [BOTTOM SECTION] (Toggle)           │  Flexible height
│                                      │
│ MODE A: AUDIO BROWSER                │
│ ┌─────────────────────────────────┐ │
│ │ [Pool] [Files]  📄 📁           │ │  Mode toggle + Import
│ │ ──────────────────────────────  │ │
│ │ 🔍 Search...                    │ │  Search field
│ │ ──────────────────────────────  │ │
│ │ 🎵 spin_sfx.wav      [▶]        │ │  ← Audio file with play
│ │ 🎵 reel_stop.wav     [▶]        │ │
│ │ 🎵 win_jingle.wav    [▶]        │ │
│ │   [Mini waveform on hover]      │ │  Hover preview
│ └─────────────────────────────────┘ │
│                                      │
│ MODE B: SELECTED EVENT EDITOR        │
│ ┌─────────────────────────────────┐ │
│ │ EVENT: onUiSpin                 │ │  Event name header
│ │ ──────────────────────────────  │ │
│ │ LAYERS:                         │ │
│ │  ▮ Layer 1: spin_btn.wav        │ │  ← Layer item
│ │     Vol: 80%  Pan: C  [M][X]    │ │     Controls
│ │  ▮ Layer 2: whoosh.wav          │ │
│ │     Vol: 60%  Pan: C  [M][X]    │ │
│ │ + Add Layer                     │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

---

## 🔌 DATA FLOW

### Events Folder Flow

```
User Action: Click "+" → CreateEventDialog
                       ↓
CreateEventDialog.show() → (name, triggerStages)
                       ↓
SlotCompositeEvent created (id, name, color, stages, layers)
                       ↓
middleware.addCompositeEvent(event)  ← MiddlewareProvider (SSoT)
                       ↓
_setSelectedEventId(event.id)  ← Select new event
                       ↓
_showBrowser = false  ← Switch to event editor
```

**Event Selection:**
```
Click event row → _setSelectedEventId(eventId)
                → onSelectionChanged callback (if parent controls selection)
                → Switch to event editor mode (_showBrowser = false)
```

**Inline Editing:**
```
Double-tap event → _startEditing(event)
                 → TextField with focus
                 → Edit name
                 → Enter or focus loss → _finishEditing()
                 → middleware.updateCompositeEvent(event.copyWith(name: newName))
```

### Audio Browser Flow

```
MODE: Pool (AudioAssetManager)
  assets = AudioAssetManager.instance.assets
         ↓
  Filtered by search
         ↓
  Display with hover preview + play button
         ↓
  Drag → Draggable<String>(data: asset.path)
         ↓
  onAudioDragStarted([path])  ← Callback to parent

MODE: File System
  _currentDirectory → Directory.listSync()
                    ↓
  Filter audio extensions (.wav, .mp3, .flac, .ogg, .aiff)
                    ↓
  Display folders + audio files
                    ↓
  Click folder → Navigate → _loadAudioFiles()
  Drag file → Draggable<String>(data: file.path)
            ↓
  onAudioDragStarted([path])
```

**Import Flow:**
```
📄 Import Files button → FilePicker.pickFiles(allowMultiple: true)
                       ↓
  AudioAssetManager.instance.importFile(path, folder: 'Imported')
                       ↓
  Switch to Pool mode → _isPoolMode = true
                       ↓
  SnackBar: "Imported N files"

📁 Import Folder button → FilePicker.getDirectoryPath()
                        ↓
  Scan all .wav/.mp3/.flac/.ogg/.aiff files recursively
                        ↓
  Sort by name
                        ↓
  Import each via AudioAssetManager
                        ↓
  Switch to Pool mode + SnackBar
```

### Selected Event Editor Flow

```
_selectedEventId != null
         ↓
middleware.compositeEvents.firstWhere(id == _selectedEventId)
         ↓
Display event properties + layers list
         ↓
Layers: name, audioPath, volume, pan, mute, delete
         ↓
Mute toggle → middleware.updateEventLayer(layer.copyWith(muted: !muted))
Delete layer → middleware.removeLayerFromEvent(eventId, layerId)
```

---

## 🎯 COMPONENT BREAKDOWN

### 3 Main Sections

| Section | Height | Purpose | Provider |
|---------|--------|---------|----------|
| **Events Folder** | 200px fixed | Event list (3-column: Name, Stage, Layers) | MiddlewareProvider.compositeEvents |
| **Divider** | 4px | Visual separator with drag handle | — |
| **Bottom Toggle** | Flexible | Audio Browser OR Selected Event Editor | AudioAssetManager / MiddlewareProvider |

### Events Folder Components

**3-Column Table:**

| Column | Flex | Content | Interaction |
|--------|------|---------|-------------|
| NAME | 3 | Event name, icon (audiotrack or edit) | Single-click: select, Double-click: edit inline |
| STAGE | 2 | Primary trigger stage (formatted) | Visual only |
| LAYERS | Fixed 50px | Colored blocks [▮▮▮] + count | Visual only |

**Features:**
- ✅ Inline editing (double-tap → TextField → Enter/blur saves)
- ✅ Selection highlighting (blue border + background)
- ✅ Edit mode highlighting (orange border)
- ✅ Layer visualization (colored blocks represent audio layers)
- ✅ Create event button (+ icon in header)
- ✅ Empty state ("No events, Click + to create")
- ❌ No delete event button
- ❌ No duplicate event button
- ❌ No drag-reorder events
- ❌ No context menu (right-click)
- ❌ No multi-select
- ❌ No filter/search for events

### Audio Browser Components

**Two Modes:**

| Mode | Data Source | Features |
|------|-------------|----------|
| **Pool** | AudioAssetManager.instance.assets | Project audio pool (DAW↔SlotLab shared) |
| **Files** | File system (Directory.listSync) | Navigate folders, parent directory |

**Common Features:**
- ✅ Search field (filters by filename)
- ✅ Import File button (📄) — Multi-select via FilePicker
- ✅ Import Folder button (📁) — Recursive scan
- ✅ Hover preview (waveform visualization)
- ✅ Play/Stop button per file (visible on hover)
- ✅ Drag support (Draggable<String> with path)
- ✅ Format badge (WAV, MP3, FLAC, etc.)
- ✅ Duration display (if available)
- ✅ Folder tags (Pool mode)
- ❌ No bulk actions (delete, move, tag)
- ❌ No favorites/bookmarks
- ❌ No recent files
- ❌ No file metadata editor (sample rate, bit depth)

**Audio Browser Item (_HoverPreviewItem):**
- Hover → Show waveform + play button
- Click play → AudioPlaybackService.previewFile(path, source: browser)
- Click stop → AudioPlaybackService.stopAll()
- Drag → onAudioDragStarted([path]) callback to parent

### Selected Event Editor Components

**Properties:**
- Event name (read-only, edit via Events Folder)
- Trigger stages (visual display only, edit via ???)
- Layers list (editable)

**Layer Item:**
- Icon (audiotrack)
- Name (e.g., "Layer 1")
- Filename (if audio assigned)
- Mute button (volume_up / volume_off icon)
- Delete button (X icon)

**Features:**
- ✅ Mute/unmute layers
- ✅ Delete layers
- ❌ No add layer button
- ❌ No layer properties (volume, pan, delay, fade)
- ❌ No drag-reorder layers
- ❌ No layer preview playback
- ❌ No waveform display
- ❌ No stage assignment for event (edit stages)

---

## 👥 ROLE-BASED ANALYSIS

### 1. Audio Middleware Architect (Primary User)

**What they do:**
- Create composite events
- Bind events to stages
- Manage event layers
- Review event structure

**What works well:**
- ✅ 3-column event list (Name, Stage, Layers) — clear overview
- ✅ Inline editing (double-tap) — quick rename
- ✅ MiddlewareProvider integration — single source of truth
- ✅ Selection sync with parent

**Pain points:**
- ❌ **No stage editor** — can't change trigger stages after creation
- ❌ **No multi-stage binding** — event shows only first stage in list
- ❌ **No layer property editor** — can't adjust volume/pan/delay/fade
- ❌ **No event duplication** — must recreate similar events manually
- ❌ **No context menu** — no right-click actions
- ⚠️ **Create Event dialog limited** — only name + stages, no advanced options

**Gaps (prioritized):**
1. **P0:** Stage editor (edit trigger stages for existing event)
2. **P0:** Layer property editor (volume, pan, delay, fade controls)
3. **P1:** Event context menu (duplicate, delete, export, test)
4. **P1:** Multi-stage display (show all trigger stages, not just first)
5. **P2:** Advanced event properties (priority, max instances, ducking)

---

### 2. Audio Designer (Primary User)

**What they do:**
- Browse audio files
- Drag audio to events/slots
- Preview audio before assignment
- Organize audio files

**What works well:**
- ✅ Audio browser with hover preview — visual feedback
- ✅ Play/Stop buttons — test audio without drag
- ✅ Pool/Files toggle — flexibility
- ✅ Import File/Folder — bulk import
- ✅ Search — find files quickly
- ✅ Waveform visualization on hover

**Pain points:**
- ❌ **No favorites** — can't bookmark frequently used files
- ❌ **No recent files** — no quick access to last used
- ❌ **No bulk operations** — can't delete/move/tag multiple files
- ❌ **No metadata display** — no sample rate, bit depth, file size
- ❌ **No folder bookmarks** — must navigate to common folders repeatedly
- ⚠️ **Waveform is fake** — _SimpleWaveformPainter uses random seed, not real audio

**Gaps (prioritized):**
1. **P1:** Favorites system (star icon, favorites folder)
2. **P1:** Recent files section (last 10-20 used)
3. **P2:** Bulk actions (multi-select, delete, move, tag)
4. **P2:** File metadata panel (sample rate, channels, bit depth, file size)
5. **P2:** Folder bookmarks (quick access sidebar)
6. **P3:** Real waveform (replace _SimpleWaveformPainter with FFI-generated waveform)

---

### 3. Tooling Developer (Secondary User)

**What they do:**
- Build automation tools
- Batch operations
- Event templates
- Export workflows

**What works well:**
- ✅ Import Folder — recursive scan
- ✅ Pool mode — shared audio across sections
- ✅ MiddlewareProvider CRUD — programmatic event creation

**Pain points:**
- ❌ **No batch event creation** — can't create multiple events at once
- ❌ **No event templates** — can't save/load event structures
- ❌ **No CSV/JSON import** — can't bulk import from spreadsheet
- ❌ **No export selected events** — can't extract subset of events
- ❌ **No scripting API** — no programmatic access

**Gaps (prioritized):**
1. **P1:** Batch event creation (CSV import: name, stage, audioPath)
2. **P2:** Event templates (save/load event structure)
3. **P2:** Export selected events (JSON format)
4. **P3:** Scripting API (Lua or Dart scripts)

---

### 4. QA Engineer (Secondary User)

**What they do:**
- Validate event completeness
- Test event playback
- Verify stage bindings
- Regression testing

**What works well:**
- ✅ Event list overview — see all events at once
- ✅ Layer count display — verify layer completeness
- ✅ Stage display — verify correct stage binding

**Pain points:**
- ❌ **No validation rules** — which events are complete/incomplete?
- ❌ **No test playback** — can't preview event from list
- ❌ **No event comparison** — can't diff two events
- ❌ **No export for testing** — can't extract events for regression suite
- ⚠️ **No visual warnings** — incomplete events look same as complete

**Gaps (prioritized):**
1. **P0:** Validation badges (✅ complete, ⚠️ incomplete, ❌ error)
2. **P1:** Test playback button (play icon per event row)
3. **P2:** Event comparison tool (diff two events side-by-side)
4. **P2:** Export events for testing (JSON test suite format)

---

## 🔍 TECHNICAL ANALYSIS

### State Management

**Events Data (SSoT):**
```dart
MiddlewareProvider.compositeEvents: List<SlotCompositeEvent>
├── Consumer<MiddlewareProvider> for events list
└── Real-time updates when events added/removed/modified
```

**Selection State:**
```dart
// Dual control: parent-controlled OR local fallback
String? _selectedEventId = widget.selectedEventId ?? _localSelectedEventId;

// Selection change:
_setSelectedEventId(eventId) {
  if (widget.onSelectionChanged != null) {
    widget.onSelectionChanged!(eventId);  // Parent controls
  } else {
    setState(() => _localSelectedEventId = eventId);  // Local fallback
  }
}
```

**Audio Browser State:**
```dart
// Pool mode OR File system mode
bool _isPoolMode = false;

// File system mode state:
String _currentDirectory = '';
List<FileSystemEntity> _audioFiles = [];

// Search state:
String _searchQuery = '';
```

**Inline Editing State:**
```dart
String? _editingEventId;
TextEditingController _editController;
FocusNode _editFocusNode;

// Flow: Double-tap → _startEditing() → TextField focus
//       Enter/blur → _finishEditing() → middleware.updateCompositeEvent()
```

### Provider Connections

| Provider | Connection | Purpose | Status |
|----------|------------|---------|--------|
| MiddlewareProvider | ✅ Consumer | Events list (compositeEvents) | Full |
| MiddlewareProvider | ✅ context.read | Event CRUD (add, update, remove, updateLayer) | Full |
| AudioAssetManager | ✅ Listener | Pool mode audio list | Full |
| AudioPlaybackService | ✅ Direct | Audio preview playback | Full |
| SlotLabProjectProvider | ❌ None | Should sync event selection state | Missing |

**Gap:** Selection state not persisted to SlotLabProjectProvider

### Audio Preview System

**Hover Preview (V6.4):**
- Disabled auto-play (was 500ms delay)
- Manual play/stop buttons only
- Waveform visualization (fake — _SimpleWaveformPainter)
- Green accent when playing, blue when idle

**Playback:**
```dart
AudioPlaybackService.instance.previewFile(
  audioPath,
  volume: 0.7,
  source: PlaybackSource.browser,  // Isolated engine
);
```

**Problems:**
- Waveform is random-generated, not real audio
- No loop option
- No volume control
- No playback position display

---

## 📊 FEATURE MATRIX

### Events Folder Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| **Event list display** | ✅ Complete | 3-column table (Name, Stage, Layers) |
| **Create event** | ✅ Complete | CreateEventDialog → middleware.addCompositeEvent |
| **Select event** | ✅ Complete | Click row → selection state + switch to editor |
| **Inline edit name** | ✅ Complete | Double-tap → TextField → blur/Enter saves |
| **Layer count display** | ✅ Complete | Colored blocks [▮▮▮] + number |
| **Stage display** | ✅ Complete | Shows primary stage (formatted) |
| **Delete event** | ❌ Missing | No delete button |
| **Duplicate event** | ❌ Missing | No duplicate button |
| **Drag-reorder events** | ❌ Missing | Fixed order (insertion order) |
| **Context menu** | ❌ Missing | No right-click actions |
| **Multi-select** | ❌ Missing | Can't select multiple events |
| **Filter/search** | ❌ Missing | No event search (only audio search) |
| **Validation badges** | ❌ Missing | No visual indication of completeness |
| **Test playback** | ❌ Missing | No play button per event |
| **Edit trigger stages** | ❌ Missing | Can't modify stages after creation |
| **Multi-stage display** | ⚠️ Partial | Shows only first stage (if event has multiple) |

### Audio Browser Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| **Pool mode** | ✅ Complete | AudioAssetManager.instance.assets |
| **File system mode** | ✅ Complete | Directory navigation |
| **Mode toggle** | ✅ Complete | Pool ↔ Files button |
| **Import files** | ✅ Complete | FilePicker multi-select |
| **Import folder** | ✅ Complete | Recursive scan |
| **Search** | ✅ Complete | Filter by filename |
| **Hover preview** | ✅ Complete | Waveform + play button on hover |
| **Play/Stop** | ✅ Complete | AudioPlaybackService.previewFile |
| **Drag support** | ✅ Complete | Draggable<String> with path |
| **Format badge** | ✅ Complete | WAV, MP3, FLAC, OGG, AIFF |
| **Duration display** | ✅ Complete | Shows duration if available |
| **Favorites** | ❌ Missing | No star/bookmark system |
| **Recent files** | ❌ Missing | No history tracking |
| **Bulk actions** | ❌ Missing | No multi-select delete/move |
| **File metadata** | ⚠️ Partial | Format + duration only (no sample rate, channels, size) |
| **Real waveform** | ❌ Missing | Uses fake random waveform |
| **Folder bookmarks** | ❌ Missing | No quick access sidebar |
| **Sort options** | ⚠️ Partial | Name-sorted only (no date, size, duration sorting) |

### Selected Event Editor Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| **Layer list display** | ✅ Complete | Shows all layers with name + filename |
| **Mute layer** | ✅ Complete | Volume icon toggle |
| **Delete layer** | ✅ Complete | X icon button |
| **Add layer** | ❌ Missing | No + button |
| **Layer properties** | ❌ Missing | No volume/pan/delay/fade controls |
| **Drag-reorder layers** | ❌ Missing | Fixed order |
| **Layer preview** | ❌ Missing | No play button per layer |
| **Waveform display** | ❌ Missing | No visual waveform |
| **Edit event properties** | ❌ Missing | No name/stage/color/priority editor |
| **Stage editor** | ❌ Missing | Can't edit trigger stages |

---

## 🔴 GAPS BY PRIORITY

### P0 — CRITICAL (Blocks Core Workflow)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P0.1 | **No delete event button** | Can't remove events, must manually edit provider | 1 hour |
| P0.2 | **No stage editor for events** | Can't modify trigger stages after creation | 2 days |
| P0.3 | **No layer property editor** | Can't adjust volume/pan/delay/fade (critical for audio design) | 3 days |
| P0.4 | **No add layer button in editor** | Can only add layers via drag-drop (unclear workflow) | 1 day |

### P1 — HIGH (Missing Pro Features)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P1.1 | **No event context menu** | Missing duplicate, delete, export, test actions | 2 days |
| P1.2 | **No test playback button** | Can't preview event from list | 1 day |
| P1.3 | **No validation badges** | Don't know which events are complete | 2 days |
| P1.4 | **No event search/filter** | Hard to find events in long lists | 1 day |
| P1.5 | **No favorites in browser** | Can't bookmark frequently used files | 2 days |
| P1.6 | **No real waveform** | Fake random waveform misleading | 3 days |

### P2 — MEDIUM (Quality of Life)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P2.1 | **No bulk actions** | Can't delete/tag multiple files | 2 days |
| P2.2 | **No file metadata panel** | No sample rate, bit depth, file size | 1 day |
| P2.3 | **No folder bookmarks** | Must navigate to common folders | 1 day |
| P2.4 | **No event comparison** | Can't diff two events | 3 days |
| P2.5 | **No batch event creation** | Can't import events from CSV/JSON | 3 days |
| P2.6 | **No recent files** | No quick access to last used | 1 day |

### P3 — LOW (Nice to Have)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P3.1 | **No drag-reorder events** | Fixed insertion order | 2 days |
| P3.2 | **No event templates** | Can't save/load event structures | 3 days |
| P3.3 | **No sort options** | Name-only sorting | 1 day |
| P3.4 | **No scripting API** | Can't automate event creation | 1 week |

---

## 🎯 ACTIONABLE ITEMS (For MASTER_TODO.md)

### P0.1: Add Delete Event Button

**Problem:** No way to delete events from Events Folder UI
**Impact:** Must manually edit MiddlewareProvider, breaks workflow
**Effort:** 1 hour
**Assigned To:** UI/UX Expert, Tooling Developer

**Files to Modify:**
- `events_panel_widget.dart:480-620` — Event item row

**Implementation:**
```dart
Widget _buildEventItem(SlotCompositeEvent event) {
  return Row(
    children: [
      // Existing: 3 columns (Name, Stage, Layers)
      // ...

      // NEW: Delete button (rightmost)
      IconButton(
        icon: const Icon(Icons.delete_outline, size: 14),
        color: Colors.white24,
        onPressed: () async {
          // Confirmation dialog
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('Delete Event'),
              content: Text('Delete "${event.name}"?'),
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
            // Clear selection if deleted event was selected
            if (_selectedEventId == event.id) {
              _setSelectedEventId(null);
            }
          }
        },
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: 24, height: 24),
      ),
    ],
  );
}
```

**Definition of Done:**
- [ ] Delete button (trash icon) appears on each event row
- [ ] Confirmation dialog before deletion
- [ ] Calls middleware.deleteCompositeEvent(eventId)
- [ ] Clears selection if deleted event was selected
- [ ] Visual feedback (snackbar or fade-out animation)

---

### P0.2: Add Stage Editor Dialog

**Problem:** Can't modify trigger stages after event creation
**Impact:** Must delete and recreate event to change stage binding
**Effort:** 2 days
**Assigned To:** Audio Middleware Architect, Tooling Developer

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/stage_editor_dialog.dart` (~400 LOC)

**Files to Modify:**
- `events_panel_widget.dart:575-596` — Add edit icon to Stage column

**Implementation:**
```dart
// NEW: stage_editor_dialog.dart
class StageEditorDialog extends StatefulWidget {
  final SlotCompositeEvent event;
  final List<String> allStages; // From StageConfigurationService

  static Future<List<String>?> show(BuildContext context, {
    required SlotCompositeEvent event,
  }) async {
    final allStages = StageConfigurationService.instance.allStageNames;
    return showDialog<List<String>>(
      context: context,
      builder: (_) => StageEditorDialog(event: event, allStages: allStages),
    );
  }

  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Trigger Stages'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            // Current stages list (with remove button)
            _buildCurrentStagesList(),
            SizedBox(height: 16),
            // Add stage section
            _buildAddStageSection(),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text('Save'),
          onPressed: () => Navigator.pop(context, _editedStages),
        ),
      ],
    );
  }

  Widget _buildCurrentStagesList() {
    return Expanded(
      child: ListView.builder(
        itemCount: _editedStages.length,
        itemBuilder: (ctx, i) {
          final stage = _editedStages[i];
          return ListTile(
            dense: true,
            title: Text(stage),
            trailing: IconButton(
              icon: Icon(Icons.close),
              onPressed: () {
                setState(() => _editedStages.removeAt(i));
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddStageSection() {
    return Column(
      children: [
        // Search stages
        TextField(
          decoration: InputDecoration(hintText: 'Search stages...'),
          onChanged: (query) => setState(() => _searchQuery = query),
        ),
        SizedBox(height: 8),
        // Filtered stage chips
        Wrap(
          spacing: 4,
          children: allStages
            .where((s) => s.toLowerCase().contains(_searchQuery.toLowerCase()))
            .map((s) => ActionChip(
              label: Text(s),
              onPressed: () {
                if (!_editedStages.contains(s)) {
                  setState(() => _editedStages.add(s));
                }
              },
            ))
            .toList(),
        ),
      ],
    );
  }
}

// In events_panel_widget.dart, Stage column:
Expanded(
  flex: 2,
  child: Row(
    children: [
      // Existing: Stage badge
      Expanded(child: _buildStageBadge(primaryStage)),

      // NEW: Edit icon
      IconButton(
        icon: Icon(Icons.edit_outlined, size: 12),
        onPressed: () async {
          final newStages = await StageEditorDialog.show(
            context,
            event: event,
          );
          if (newStages != null) {
            final middleware = context.read<MiddlewareProvider>();
            middleware.updateCompositeEvent(
              event.copyWith(triggerStages: newStages),
            );
          }
        },
      ),
    ],
  ),
),
```

**Definition of Done:**
- [ ] Dialog opens with current stages list
- [ ] Can remove stages (X button)
- [ ] Can add stages (search + click chip)
- [ ] Searchable stage list from StageConfigurationService
- [ ] Save button updates event via middleware.updateCompositeEvent
- [ ] Visual feedback (updated stage display in list)

---

### P0.3: Add Layer Property Editor

**Problem:** Can't edit layer properties (volume, pan, delay, fade) in event editor
**Impact:** Critical for audio design — layers have no control over mix
**Effort:** 3 days
**Assigned To:** Chief Audio Architect, Audio Designer

**Files to Modify:**
- `events_panel_widget.dart:770-855` — Enhance layer item UI

**Implementation:**
```dart
Widget _buildLayerItem(SlotEventLayer layer, SlotCompositeEvent event) {
  return Container(
    margin: EdgeInsets.only(bottom: 4),
    padding: EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Color(0xFF16161C),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + filename + mute/delete (existing)
        Row(
          children: [
            Icon(Icons.audiotrack, size: 14),
            SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(layer.name, style: ...),
                  Text(fileName, style: ...),
                ],
              ),
            ),
            IconButton(icon: Icon(Icons.volume_off), onPressed: ...),
            IconButton(icon: Icon(Icons.close), onPressed: ...),
          ],
        ),

        SizedBox(height: 8),

        // NEW: Row 2: Volume slider
        Row(
          children: [
            SizedBox(width: 50, child: Text('Volume', style: ...)),
            Expanded(
              child: Slider(
                value: layer.volume,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                label: '${(layer.volume * 100).toInt()}%',
                onChanged: (v) {
                  final middleware = context.read<MiddlewareProvider>();
                  middleware.updateEventLayer(
                    event.id,
                    layer.copyWith(volume: v),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${(layer.volume * 100).toInt()}%',
                style: TextStyle(fontSize: 9, fontFamily: 'monospace'),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),

        // NEW: Row 3: Pan slider
        Row(
          children: [
            SizedBox(width: 50, child: Text('Pan', style: ...)),
            Expanded(
              child: Slider(
                value: layer.pan,
                min: -1.0,
                max: 1.0,
                divisions: 20,
                label: layer.pan == 0 ? 'C' : layer.pan < 0 ? 'L${(-layer.pan * 100).toInt()}' : 'R${(layer.pan * 100).toInt()}',
                onChanged: (v) {
                  final middleware = context.read<MiddlewareProvider>();
                  middleware.updateEventLayer(
                    event.id,
                    layer.copyWith(pan: v),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                layer.pan == 0 ? 'C' : layer.pan < 0 ? 'L${(-layer.pan * 100).toInt()}' : 'R${(layer.pan * 100).toInt()}',
                style: TextStyle(fontSize: 9, fontFamily: 'monospace'),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),

        // NEW: Row 4: Delay slider
        Row(
          children: [
            SizedBox(width: 50, child: Text('Delay', style: ...)),
            Expanded(
              child: Slider(
                value: layer.offsetMs,
                min: 0.0,
                max: 2000.0,
                divisions: 200,
                label: '${layer.offsetMs.toInt()}ms',
                onChanged: (v) {
                  final middleware = context.read<MiddlewareProvider>();
                  middleware.updateEventLayer(
                    event.id,
                    layer.copyWith(offsetMs: v),
                  );
                },
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                '${layer.offsetMs.toInt()}ms',
                style: TextStyle(fontSize: 9, fontFamily: 'monospace'),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),

        // NEW: Row 5: Preview button
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              icon: Icon(Icons.play_arrow, size: 14),
              label: Text('Preview', style: TextStyle(fontSize: 10)),
              onPressed: () {
                if (layer.audioPath.isNotEmpty) {
                  AudioPlaybackService.instance.previewFile(
                    layer.audioPath,
                    volume: layer.volume,
                    source: PlaybackSource.browser,
                  );
                }
              },
            ),
          ],
        ),
      ],
    ),
  );
}
```

**Definition of Done:**
- [ ] Volume slider (0-200%, default 100%)
- [ ] Pan slider (L100-C-R100)
- [ ] Delay slider (0-2000ms)
- [ ] Preview button (plays layer with current settings)
- [ ] Real-time updates via middleware.updateEventLayer
- [ ] Compact layout (fits in right panel width)

---

### P0.4: Add "Add Layer" Button

**Problem:** No explicit button to add layer, must drag-drop audio
**Impact:** Unclear how to add layers, especially for new users
**Effort:** 1 day
**Assigned To:** UI/UX Expert

**Files to Modify:**
- `events_panel_widget.dart:700-770` — Add button below layers list

**Implementation:**
```dart
Widget _buildSelectedEvent() {
  final middleware = context.watch<MiddlewareProvider>();
  final event = middleware.compositeEvents.firstWhere(
    (e) => e.id == _selectedEventId,
    orElse: () => null,
  );

  if (event == null) return _buildEmptyState('No event selected', '');

  return Column(
    children: [
      // Existing: Event header
      _buildEventHeader(event),

      // Existing: Layers list
      Expanded(
        child: ListView.builder(
          itemCount: event.layers.length,
          itemBuilder: (ctx, i) => _buildLayerItem(event.layers[i], event),
        ),
      ),

      // NEW: Add Layer button
      Padding(
        padding: EdgeInsets.all(8),
        child: OutlinedButton.icon(
          icon: Icon(Icons.add, size: 16),
          label: Text('Add Layer'),
          onPressed: () async {
            // Show AudioWaveformPickerDialog
            final audioPath = await AudioWaveformPickerDialog.show(
              context,
              title: 'Select Audio for Layer',
            );

            if (audioPath != null) {
              final newLayer = SlotEventLayer(
                id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
                name: 'Layer ${event.layers.length + 1}',
                audioPath: audioPath,
                volume: 1.0,
                pan: 0.0,
                offsetMs: 0.0,
                muted: false,
                solo: false,
              );

              middleware.addLayerToEvent(event.id, newLayer);
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: FluxForgeTheme.accentBlue,
            side: BorderSide(color: FluxForgeTheme.accentBlue.withOpacity(0.3)),
          ),
        ),
      ),
    ],
  );
}
```

**Definition of Done:**
- [ ] Button appears at bottom of layers list
- [ ] Opens AudioWaveformPickerDialog on click
- [ ] Creates new layer with selected audio
- [ ] Calls middleware.addLayerToEvent
- [ ] Auto-names layer ("Layer 1", "Layer 2", etc.)
- [ ] Default parameters (volume 100%, pan center, no delay)

---

## 📊 SUMMARY

### Strengths
- ✅ **3-column event list** — clear, compact overview
- ✅ **Inline editing** — quick rename workflow
- ✅ **Audio browser with preview** — hover waveform + play buttons
- ✅ **Pool/Files toggle** — flexibility in audio sourcing
- ✅ **Bulk import** — folder import with recursive scan
- ✅ **MiddlewareProvider SSoT** — clean data architecture
- ✅ **Selection sync** — parent-controlled or local fallback

### Critical Weaknesses
- ❌ **No delete event** — basic CRUD missing
- ❌ **No stage editor** — can't modify stages
- ❌ **No layer properties** — no volume/pan/delay control
- ❌ **No add layer button** — workflow unclear

### Missing Features (Top 12)
1. Delete event button (P0)
2. Stage editor dialog (P0)
3. Layer property editor (P0)
4. Add layer button (P0)
5. Event context menu (P1)
6. Test playback button (P1)
7. Validation badges (P1)
8. Event search/filter (P1)
9. Favorites system (P1)
10. Real waveform (P1)
11. Bulk file actions (P2)
12. File metadata panel (P2)

### Provider Connections

| Provider | Connection | Coverage |
|----------|------------|----------|
| MiddlewareProvider | ✅ Full | Events CRUD, layer CRUD, selection |
| AudioAssetManager | ✅ Full | Pool mode, import, listener |
| AudioPlaybackService | ✅ Full | Preview playback |
| SlotLabProjectProvider | ❌ None | Should persist selection state |
| StageConfigurationService | ⚠️ Missing | Should use for stage list in editor |

---

## ✅ FAZA 2.2 COMPLETE

**Next Step:** Await approval, then proceed to FAZA 2.3 (Lower Zone)

**Deliverables Created:**
- Panel architecture diagram
- Component breakdown (3 sections: Events, Divider, Browser/Editor)
- Data flow documentation (Events, Browser, Selection, Editing)
- Role-based gap analysis (4 roles × gaps)
- 16 actionable items for MASTER_TODO (4 P0, 6 P1, 6 P2, 4 P3)

---

**Created:** 2026-01-29
**Version:** 1.0
**LOC Analyzed:** 1,559

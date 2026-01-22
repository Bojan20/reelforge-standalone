# P2 UX Improvements — Implementation Documentation

**Status:** ✅ COMPLETED (2026-01-22)
**Priority:** Medium
**Total LOC:** ~3,380

---

## Overview

P2 implements four medium-priority UX improvements identified in the system review:

| ID | Feature | Effort | Impact | Status |
|----|---------|--------|--------|--------|
| P2.1 | Export Functionality | HIGH | HIGH | ✅ Done |
| P2.2 | Panel Undo System | HIGH | MEDIUM | ✅ Done |
| P2.3 | Unified Search (Cmd+F) | MEDIUM | MEDIUM | ✅ Done |
| P2.4 | Recent/Favorites | MEDIUM | MEDIUM | ✅ Done |

---

## P2.1: Export Functionality

### Purpose
Professional export system for DAW timeline and SlotLab events with format selection, progress tracking, and batch processing.

### Files

| File | LOC | Description |
|------|-----|-------------|
| `services/export_service.dart` | ~280 | Core export service with FFI integration |
| `widgets/lower_zone/export_panels.dart` | ~750 | Four export panel widgets |

### Components

#### ExportService (`services/export_service.dart`)

```dart
class ExportService {
  // Singleton pattern
  static final ExportService instance = ExportService._();

  // Core methods
  Future<String?> exportProject(ExportConfig config);
  Future<List<String>> exportStems(StemExportConfig config);
  Future<String?> bounceRealtime(BounceConfig config);
  Stream<ExportProgress> get progressStream;
}
```

**Enums:**
- `ExportFormat` — wav, flac, mp3, ogg (with file extensions and codec names)
- `BitDepth` — bit16, bit24, bit32
- `SampleRate` — rate44100, rate48000, rate96000, rate192000
- `NormalizationMode` — none, peak, lufs

**Config Classes:**
- `ExportConfig` — Format, quality, time range, normalization
- `StemExportConfig` — Track/bus selection for multi-stem export
- `BounceConfig` — Realtime bounce with tail and monitoring options

#### Export Panels (`widgets/lower_zone/export_panels.dart`)

**DawExportPanel:**
- Format dropdown (WAV/FLAC/MP3/OGG)
- Bit depth selection (16/24/32-bit)
- Sample rate selection (44.1-192kHz)
- Normalization options (None/Peak/LUFS)
- Progress bar with ETA
- File size estimation

**DawStemsPanel:**
- Track list with checkboxes
- Bus list with checkboxes
- Select All / Deselect All
- Naming pattern preview
- Progress per stem

**DawBouncePanel:**
- Realtime bounce toggle
- Tail length setting (0-10s)
- Peak meters during bounce
- Monitor output toggle

**SlotLabBatchExportPanel:**
- Event list from MiddlewareProvider
- Variation count per event
- Format/quality settings
- Batch progress tracking

### Integration Points

- DAW Lower Zone: Export, Stems, Bounce tabs
- SlotLab Lower Zone: Export tab in Bake section
- FFI: `bounceStart`, `bounceGetProgress`, `bounceIsComplete`, `exportStems`

---

## P2.2: Panel Undo System

### Purpose
Per-panel undo/redo with action merging for continuous parameter changes (e.g., dragging a knob).

### Files

| File | LOC | Description |
|------|-----|-------------|
| `providers/panel_undo_manager.dart` | ~320 | Undo manager and action classes |
| `widgets/common/panel_undo_toolbar.dart` | ~400 | UI components |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ PanelUndoRegistry (Singleton)                               │
│ ├── managers: Map<String, PanelUndoManager>                 │
│ └── getManager(panelId) → creates or returns existing       │
├─────────────────────────────────────────────────────────────┤
│ PanelUndoManager                                            │
│ ├── _undoStack: List<PanelUndoAction>                      │
│ ├── _redoStack: List<PanelUndoAction>                      │
│ ├── mergeWindow: Duration (default 500ms)                  │
│ └── maxStackSize: int (default 50)                         │
├─────────────────────────────────────────────────────────────┤
│ PanelUndoAction (abstract)                                  │
│ ├── ParameterChangeAction                                   │
│ ├── BatchParameterChangeAction                              │
│ ├── EqBandAction                                            │
│ ├── PresetChangeAction                                      │
│ └── ABSwitchAction                                          │
└─────────────────────────────────────────────────────────────┘
```

### Action Classes

```dart
// Base action
abstract class PanelUndoAction {
  final String description;
  final DateTime timestamp;

  void undo();
  void redo();
  bool canMerge(PanelUndoAction other);
  PanelUndoAction merge(PanelUndoAction other);
}

// Parameter change (mergeable within 500ms)
class ParameterChangeAction extends PanelUndoAction {
  final String parameterId;
  final dynamic oldValue;
  final dynamic newValue;
  final void Function(dynamic) applyValue;
}

// Batch parameter change
class BatchParameterChangeAction extends PanelUndoAction {
  final Map<String, dynamic> oldValues;
  final Map<String, dynamic> newValues;
  final void Function(Map<String, dynamic>) applyValues;
}

// EQ band change
class EqBandAction extends PanelUndoAction {
  final int bandIndex;
  final EqBandState? oldState;
  final EqBandState? newState;
  final void Function(int, EqBandState?) applyBand;
}

// Preset change
class PresetChangeAction extends PanelUndoAction {
  final String? oldPresetId;
  final String? newPresetId;
  final Map<String, dynamic> oldParameters;
  final Map<String, dynamic> newParameters;
  final void Function(String?, Map<String, dynamic>) applyPreset;
}

// A/B switch
class ABSwitchAction extends PanelUndoAction {
  final bool wasAActive;
  final Map<String, dynamic> aState;
  final Map<String, dynamic> bState;
  final void Function(bool, Map<String, dynamic>) applyState;
}
```

### PanelUndoHelper

Integration helper for StatefulWidgets:

```dart
class _MyPanelState extends State<MyPanel> {
  late final PanelUndoHelper _undoHelper;

  @override
  void initState() {
    super.initState();
    _undoHelper = PanelUndoHelper(
      panelId: 'my_panel',
      onChanged: () => setState(() {}),
    );
  }

  void _onKnobChanged(double oldValue, double newValue) {
    _undoHelper.recordParam('gain', oldValue, newValue, 'Change gain');
  }

  @override
  void dispose() {
    _undoHelper.dispose();
    super.dispose();
  }
}
```

### UI Components

**PanelUndoToolbar:**
- Compact mode: Just undo/redo icons
- Full mode: Icons + labels + action count + clear button
- Tooltips show action descriptions

**PanelUndoHistoryDropdown:**
- Scrollable history list
- Click to undo to specific point
- Timestamps (Just now, 2m ago, etc.)
- Icons per action type

**PanelUndoFocusWrapper:**
- Wraps panel content
- Captures Cmd+Z / Cmd+Shift+Z / Ctrl+Y
- Returns `KeyEventResult.handled` to prevent bubbling

---

## P2.3: Unified Search (Cmd+F)

### Purpose
Spotlight-style global search overlay that searches across all content types.

### Files

| File | LOC | Description |
|------|-----|-------------|
| `services/unified_search_service.dart` | ~350 | Search service and providers |
| `widgets/common/unified_search_overlay.dart` | ~500 | Search UI overlay |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ UnifiedSearchService (Singleton)                            │
│ ├── _providers: List<SearchProvider>                        │
│ ├── _recentSearches: List<SearchResult>                    │
│ └── search(query, filters) → SearchResults                 │
├─────────────────────────────────────────────────────────────┤
│ SearchProvider (Interface)                                  │
│ ├── HelpSearchProvider (built-in)                          │
│ ├── StaticSearchProvider (files, presets)                  │
│ └── [Custom providers can be registered]                   │
├─────────────────────────────────────────────────────────────┤
│ SearchResult                                                │
│ ├── id, title, subtitle                                    │
│ ├── category: SearchCategory                               │
│ ├── relevance: double (0.0-1.0)                           │
│ └── onSelect: VoidCallback?                                │
└─────────────────────────────────────────────────────────────┘
```

### SearchCategory Enum

```dart
enum SearchCategory {
  file('📄', 'File', Colors.blue),
  event('🎵', 'Event', Colors.green),
  track('🎚', 'Track', Colors.orange),
  clip('📎', 'Clip', Colors.purple),
  plugin('🔌', 'Plugin', Colors.cyan),
  preset('💾', 'Preset', Colors.pink),
  parameter('🎛', 'Parameter', Colors.amber),
  stage('🎭', 'Stage', Colors.teal),
  help('❓', 'Help', Colors.grey),
  recent('🕐', 'Recent', Colors.blueGrey);
}
```

### Built-in HelpSearchProvider

Pre-populated with keyboard shortcuts:

| Shortcut | Description |
|----------|-------------|
| Space | Play / Pause |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+S | Save Project |
| Cmd+F | Search |
| 1-0 | Forced outcomes (SlotLab) |
| Tab | Switch section |

### UnifiedSearchOverlay

**Features:**
- Auto-focus on open
- 150ms debounce on typing
- Category filter chips
- Keyboard navigation (↑↓ Enter Esc)
- Result count and search time display
- Recent searches when empty

**Usage:**
```dart
// Show overlay and get selected result
final result = await UnifiedSearchOverlay.show(context, accentColor: Colors.blue);
if (result != null) {
  result.onSelect?.call();
}
```

---

## P2.4: Recent/Favorites

### Purpose
Quick access panel for recently used and favorited items with persistent storage.

### Files

| File | LOC | Description |
|------|-----|-------------|
| `services/recent_favorites_service.dart` | ~280 | Service with SharedPreferences |
| `widgets/common/quick_access_panel.dart` | ~500 | Panel and bar widgets |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ RecentFavoritesService (Singleton)                          │
│ ├── _recentItems: List<RecentItem>                         │
│ ├── maxRecentItems: 100                                    │
│ ├── SharedPreferences persistence                          │
│ └── ChangeNotifier for UI updates                          │
├─────────────────────────────────────────────────────────────┤
│ RecentItem                                                  │
│ ├── id, title, subtitle                                    │
│ ├── type: RecentItemType                                   │
│ ├── path: String?                                          │
│ ├── isFavorite: bool                                       │
│ ├── accessCount: int                                       │
│ └── lastAccessed: DateTime                                 │
└─────────────────────────────────────────────────────────────┘
```

### RecentItemType Enum

```dart
enum RecentItemType {
  file('📄'),
  project('📁'),
  preset('💾'),
  event('🎵'),
  plugin('🔌'),
  folder('📂');
}
```

### Service Methods

```dart
class RecentFavoritesService {
  // Add/update recent item
  void addRecent(RecentItem item);

  // Get recent items (optionally filtered by type)
  List<RecentItem> getRecent(RecentItemType type, {int? limit});
  List<RecentItem> getAllRecent({int? limit});

  // Favorites management
  List<RecentItem> getFavorites({RecentItemType? type});
  void toggleFavorite(String id);

  // Most used (sorted by accessCount)
  List<RecentItem> getMostUsed({int limit = 10, RecentItemType? type});

  // Persistence
  Future<void> load();
  Future<void> save();
  void clear();
}
```

### UI Components

**QuickAccessPanel:**
- Three tabs: Recent / Favorites / Most Used
- Category filter bar (All, Files, Projects, Presets, Events)
- Inline favorite toggle (star icon)
- Access count badge (for Most Used tab)
- Empty state messages

**FavoritesBar:**
- Horizontal compact widget
- Shows favorited items as chips
- Type emoji + title
- Click to select and add to recent

### Persistence Format

```json
{
  "recent_items": [
    {
      "id": "file_abc123",
      "title": "My Sound.wav",
      "subtitle": "/sounds/effects/",
      "type": "file",
      "path": "/sounds/effects/My Sound.wav",
      "isFavorite": true,
      "accessCount": 5,
      "lastAccessed": "2026-01-22T10:30:00Z"
    }
  ]
}
```

---

## Integration Summary

### DAW Lower Zone

```dart
// Bake tab sub-tabs now use functional panels:
Widget _buildExportPanel() => const DawExportPanel();
Widget _buildStemsPanel() => const DawStemsPanel();
Widget _buildBouncePanel() => const DawBouncePanel();
```

### SlotLab Lower Zone

```dart
// Export tab uses batch export panel:
Widget _buildExportPanel() => const SlotLabBatchExportPanel();
```

### Global Keyboard Shortcuts

| Shortcut | Action | Handler |
|----------|--------|---------|
| Cmd+F | Open unified search | App-level |
| Cmd+Z | Undo (panel-local) | PanelUndoFocusWrapper |
| Cmd+Shift+Z | Redo (panel-local) | PanelUndoFocusWrapper |
| Ctrl+Y | Redo (Windows) | PanelUndoFocusWrapper |

---

## Future Enhancements

### P2.1 Export
- [ ] Add AAC/ALAC formats
- [ ] Dithering options
- [ ] Metadata embedding
- [ ] Batch presets

### P2.2 Panel Undo
- [ ] Undo grouping (named groups)
- [ ] Branch history (tree instead of stack)
- [ ] Export undo history

### P2.3 Unified Search
- [ ] Fuzzy matching
- [ ] Search history persistence
- [ ] Custom search providers API
- [ ] Search within results

### P2.4 Recent/Favorites
- [ ] Folders for favorites
- [ ] Tags/labels
- [ ] Smart collections (auto-populated)
- [ ] Sync across devices

---

## Dependencies

```yaml
# pubspec.yaml additions
dependencies:
  file_picker: ^9.2.0      # For export path selection
  shared_preferences: ^2.0  # For recent/favorites persistence
```

---

## Testing Checklist

- [ ] Export WAV/FLAC/MP3/OGG with all quality settings
- [ ] Stem export with track selection
- [ ] Realtime bounce with monitoring
- [ ] Batch export SlotLab events
- [ ] Undo/redo parameter changes
- [ ] Undo merge within 500ms window
- [ ] Search across all categories
- [ ] Keyboard navigation in search
- [ ] Add/remove favorites
- [ ] Recent items persistence across app restart
- [ ] Most used sorting accuracy

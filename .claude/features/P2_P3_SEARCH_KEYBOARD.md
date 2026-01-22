# P2/P3 Search & Keyboard Improvements

**Status:** COMPLETED (2026-01-22)
**Sprint:** UX Polish

---

## Overview

Medium and low priority UX improvements for the unified search system and keyboard customization.

---

## P2: Search Providers (Medium Priority)

### P2.1: FileSearchProvider

**Purpose:** Search audio assets by name, path, folder.

**Implementation:**

```dart
class FileSearchProvider extends SearchProvider {
  List<Map<String, dynamic>> Function()? _getAssetsCallback;
  void Function(String path)? _onFileSelectCallback;

  void init({
    required List<Map<String, dynamic>> Function() getAssets,
    void Function(String path)? onFileSelect,
  }) { ... }

  @override
  Set<SearchCategory> get categories => {SearchCategory.file};

  @override
  Future<List<SearchResult>> search(String query, ...) async {
    // Fuzzy match against name, path, folder
    // Returns sorted results by relevance
  }
}
```

**Searchable Fields:**
- `name` — File name
- `path` — Full file path
- `folder` — Folder name in Audio Pool

**Files:**
- [unified_search_service.dart](../../../flutter_ui/lib/services/unified_search_service.dart) — Provider class
- [engine_connected_layout.dart](../../../flutter_ui/lib/screens/engine_connected_layout.dart) — Init callback

---

### P2.2: TrackSearchProvider

**Purpose:** Search DAW timeline tracks.

**Implementation:**

```dart
class TrackSearchProvider extends SearchProvider {
  List<Map<String, dynamic>> Function()? _getTracksCallback;
  void Function(String trackId)? _onTrackSelectCallback;

  @override
  Set<SearchCategory> get categories => {SearchCategory.track};

  @override
  Future<List<SearchResult>> search(String query, ...) async {
    // Match against track name
    // Show type badge (audio/midi/folder)
  }
}
```

**Searchable Fields:**
- `id` — Track ID
- `name` — Track name
- `type` — Track type (audio, midi, folder)
- `isMuted`, `isSolo`, `isArmed` — State flags

**Files:**
- [unified_search_service.dart](../../../flutter_ui/lib/services/unified_search_service.dart)
- [engine_connected_layout.dart](../../../flutter_ui/lib/screens/engine_connected_layout.dart)

---

### P2.3: PresetSearchProvider

**Purpose:** Search DSP presets and containers.

**Implementation:**

```dart
class PresetSearchProvider extends SearchProvider {
  List<Map<String, dynamic>> Function()? _getPresetsCallback;
  void Function(String presetId)? _onPresetSelectCallback;

  @override
  Set<SearchCategory> get categories => {SearchCategory.preset};

  @override
  Future<List<SearchResult>> search(String query, ...) async {
    // Match against name, plugin, category
  }
}
```

**Current Data Sources:**
- Blend Containers
- Random Containers
- Sequence Containers

**Files:**
- [unified_search_service.dart](../../../flutter_ui/lib/services/unified_search_service.dart)
- [engine_connected_layout.dart](../../../flutter_ui/lib/screens/engine_connected_layout.dart)

---

## P3: Polish Features (Low Priority)

### P3.1: Keyboard Shortcuts Customization

**Purpose:** Allow users to remap keyboard commands.

**API:**

```dart
// In KeyboardFocusProvider:

// Check current mapping
LogicalKeyboardKey? getKeyForCommand(KeyboardCommand command);
KeyboardCommand? getCommandForKey(LogicalKeyboardKey key);

// Remap
KeyboardCommand? remapCommand(KeyboardCommand command, LogicalKeyboardKey newKey);
void swapCommands(KeyboardCommand cmd1, KeyboardCommand cmd2);

// Reset
void resetCommandMapping(KeyboardCommand command);
void resetAllMappings();

// Persistence
Map<String, dynamic> exportMappings();
void importMappings(Map<String, dynamic> json);

// UI Helper
List<({KeyboardCommand command, LogicalKeyboardKey? key, bool isCustom})> getCustomizableCommands();
```

**Storage Format:**
```json
{
  "4294967302": "copy",      // keyId → command name
  "4294967303": "paste"
}
```

**Files:**
- [keyboard_focus_provider.dart](../../../flutter_ui/lib/providers/keyboard_focus_provider.dart#L545-L650)

---

### P3.2: Fuzzy Search Matching

**Purpose:** More forgiving search with typo tolerance.

**Implementation:**

```dart
double _fuzzyMatch(String query, String target) {
  // 1.0 = exact match
  // 0.9 = starts with query
  // 0.7 = contains query
  // 0.5 = subsequence match
  // 0.3-0.6 = Levenshtein distance based
  // 0.0 = no match
}

bool _isSubsequence(String query, String target);
int _levenshteinDistance(String s1, String s2);
```

**Example Matches:**
| Query | Target | Score |
|-------|--------|-------|
| `comp` | `Compressor` | 0.9 (prefix) |
| `cmprssor` | `Compressor` | 0.5 (subsequence) |
| `compresser` | `Compressor` | 0.54 (levenshtein) |

**Files:**
- [unified_search_service.dart](../../../flutter_ui/lib/services/unified_search_service.dart#L700-L750)

---

### P3.3: Search History Persistence

**Purpose:** Remember past searches across sessions.

**API:**

```dart
// In UnifiedSearchService:

// Auto-recorded on search()
void recordSearch(String query, int resultCount);

// Query
List<String> getRecentQueries({int maxResults = 10});
List<SearchHistoryEntry> get searchHistory;

// Persistence
List<Map<String, dynamic>> exportSearchHistory();
void importSearchHistory(List<dynamic> json);

// Clear
void clearSearchHistory();
```

**Storage Format:**
```json
[
  {
    "query": "compressor",
    "timestamp": "2026-01-22T10:30:00.000",
    "resultCount": 5
  }
]
```

**Files:**
- [unified_search_service.dart](../../../flutter_ui/lib/services/unified_search_service.dart#L380-L435)

---

## Registration Flow

```
service_locator.dart::init()
    │
    └─► _initializeSearchProviders()
           │
           ├─► HelpSearchProvider()      // Built-in, no init needed
           ├─► RecentSearchProvider()    // Built-in, no init needed
           ├─► FileSearchProvider()      // Needs init()
           ├─► TrackSearchProvider()     // Needs init()
           └─► PresetSearchProvider()    // Needs init()

engine_connected_layout.dart::initState()
    │
    └─► _initializeP2SearchProviders()
           │
           ├─► fileProvider.init(getAssets: ...)
           ├─► trackProvider.init(getTracks: ...)
           └─► presetProvider.init(getPresets: ...)
```

---

## Files Modified

| File | Changes | LOC |
|------|---------|-----|
| `unified_search_service.dart` | P2 providers, fuzzy matching, history | +280 |
| `keyboard_focus_provider.dart` | Customization API | +130 |
| `service_locator.dart` | P2 provider registration | +5 |
| `engine_connected_layout.dart` | P2 provider init callbacks | +80 |

**Total:** ~495 LOC

---

## Testing

### Search Providers

```dart
// File search
final results = await search.search('spin');
assert(results.any((r) => r.category == SearchCategory.file));

// Track search
final trackResults = await search.search('vocals');
assert(trackResults.any((r) => r.category == SearchCategory.track));

// Preset search
final presetResults = await search.search('blend');
assert(presetResults.any((r) => r.category == SearchCategory.preset));
```

### Keyboard Customization

```dart
final keyboard = context.read<KeyboardFocusProvider>();

// Remap copy from C to X
keyboard.remapCommand(KeyboardCommand.copy, LogicalKeyboardKey.keyX);
assert(keyboard.getKeyForCommand(KeyboardCommand.copy) == LogicalKeyboardKey.keyX);

// Reset
keyboard.resetAllMappings();
assert(keyboard.getKeyForCommand(KeyboardCommand.copy) == LogicalKeyboardKey.keyC);
```

### Search History

```dart
// Perform search
await search.search('compressor');

// Check history
final history = search.searchHistory;
assert(history.first.query == 'compressor');

// Export/import
final json = search.exportSearchHistory();
search.clearSearchHistory();
search.importSearchHistory(json);
assert(search.searchHistory.isNotEmpty);
```

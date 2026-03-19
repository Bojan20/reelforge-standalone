# FFNC Implementation Plan — FluxForge Studio

**Version:** 1.0
**Date:** 2026-03-19
**Depends on:** [FFNC.md](FFNC.md) (naming convention specification)

---

## Overview

This document describes the complete implementation plan for integrating FFNC (FluxForge Audio Naming Convention) into FluxForge Studio. Four phases, each independent and delivering value on its own.

**Goal:** Transform the audio setup workflow from ~70 minutes of manual clicking to ~10 minutes of folder drop + fine-tuning.

---

## Architecture Principle

No existing runtime is modified. All changes are **input-side only**:

```
                    ┌─────────────────┐
FFNC Parser ──────→ │                 │
Smart Defaults ───→ │ SlotComposite   │ → _syncEventToRegistry() → EventRegistry → Rust Engine
Rename Tool ──────→ │ Event           │
Batch Edit ───────→ │ (same as today) │
Profile Import ──→  │                 │
                    └─────────────────┘
```

**What does NOT change:**
- EventRegistry — receives same AudioEvent objects
- SlotAudioProvider — plays audio the same way
- SlotStageProvider — triggers stages the same way
- CompositeEventSystemProvider — same CRUD operations
- `_syncEventToRegistry()` — same single registration point
- Rust engine / FFI — zero changes

---

# PHASE 1 — FFNC Parser + Smart Defaults

**Impact:** AUTOBIND goes from "80% guess with default params" to "100% match with correct volume/bus/fade"
**Risk:** Zero — additive only, no existing code modified until integration step
**Estimated new code:** ~600 lines

---

## 1.1 FFNC Parser

**New file:** `flutter_ui/lib/services/ffnc/ffnc_parser.dart`

### What it does

Takes a filename, returns structured data:

```dart
class FFNCResult {
  final String stage;           // Internal stage name (e.g., "REEL_STOP_0")
  final FFNCCategory category;  // sfx, mus, amb, trn, ui, vo
  final int layer;              // 1 = default/only, 2+ = multi-layer
  final String? variant;        // null = no variant, "a"/"b"/"c" = round-robin
  final bool isFFNC;            // true = matched FFNC prefix
}

enum FFNCCategory { sfx, mus, amb, trn, ui, vo }
```

### Parser flow

```
Input: "sfx_reel_stop_2_layer1_variant_a.wav"

1. Strip extension → "sfx_reel_stop_2_layer1_variant_a"
2. Extract _variant_x → variant="a", remainder="sfx_reel_stop_2_layer1"
3. Extract _layerN → layer=1, remainder="sfx_reel_stop_2"
4. Match prefix → category=sfx, remainder="reel_stop_2"
5. Apply transformations:
   - sfx_reel_stop_N → REEL_STOP_(N-1)  [1-based → 0-based]
   - sfx_win_tier_N → WIN_PRESENT_N
6. Result: stage="REEL_STOP_1", category=sfx, layer=1, variant="a"
```

### Transformation rules (from FFNC.md)

```dart
// In ffnc_parser.dart
String _transformSfx(String name) {
  // win_tier_N → WIN_PRESENT_N
  final winTier = RegExp(r'^win_tier_(\d+)$').firstMatch(name);
  if (winTier != null) return 'WIN_PRESENT_${winTier.group(1)}';

  // win_low, win_equal, win_end
  if (name == 'win_low') return 'WIN_PRESENT_LOW';
  if (name == 'win_equal') return 'WIN_PRESENT_EQUAL';
  if (name == 'win_end') return 'WIN_PRESENT_END';

  // reel_stop_N → REEL_STOP_(N-1)  [only REEL_STOP is 0-based]
  final reelStop = RegExp(r'^reel_stop_(\d+)$').firstMatch(name);
  if (reelStop != null) {
    final n = int.parse(reelStop.group(1)!);
    return 'REEL_STOP_${n - 1}';
  }

  // Everything else: direct uppercase
  return name.toUpperCase();
}

String _transformMus(String name) {
  // base_game → BASE
  name = name.replaceFirst('base_game', 'base');
  // freespin → FS
  name = name.replaceFirst('freespin', 'fs');
  return 'MUSIC_${name.toUpperCase()}';
}

String _transformAmb(String name) {
  // base_game → BASE, freespin → FS, big_win → BIGWIN
  if (name == 'base_game') return 'AMBIENT_BASE';
  if (name == 'freespin') return 'AMBIENT_FS';
  if (name == 'big_win') return 'AMBIENT_BIGWIN';
  // attract_*, idle_* → strip amb_ prefix
  if (name.startsWith('attract_') || name.startsWith('idle_')) {
    return name.toUpperCase();
  }
  return 'AMBIENT_${name.toUpperCase()}';
}

String _transformTrn(String name) {
  // base_game → BASE, freespin → FS
  name = name.replaceAll('base_game', 'base');
  name = name.replaceAll('freespin', 'fs');
  return 'TRANSITION_${name.toUpperCase()}';
}

// ui_ and vo_ → direct uppercase (prefix is already part of stage name)
```

### FFNC detection

```dart
bool isFFNC(String filename) {
  final lower = filename.toLowerCase();
  return lower.startsWith('sfx_') ||
         lower.startsWith('mus_') ||
         lower.startsWith('amb_') ||
         lower.startsWith('trn_') ||
         lower.startsWith('ui_')  ||
         lower.startsWith('vo_');
}
```

If not FFNC → return null, caller falls through to legacy alias matching.

---

## 1.2 Smart Defaults

**New file:** `flutter_ui/lib/services/ffnc/stage_defaults.dart`

### What it does

Maps stage names to default audio parameters. Used when AUTOBIND creates composite events — instead of volume 1.0 / bus sfx for everything, each stage gets sensible defaults.

```dart
class StageDefault {
  final double volume;
  final int busId;
  final double? fadeInMs;
  final double? fadeOutMs;
  final bool loop;

  const StageDefault({
    required this.volume,
    required this.busId,
    this.fadeInMs,
    this.fadeOutMs,
    this.loop = false,
  });
}
```

### Default resolution

```dart
StageDefault getDefaultForStage(String stage) {
  // 1. Exact match
  if (_exactDefaults.containsKey(stage)) return _exactDefaults[stage]!;

  // 2. Wildcard match (longest prefix)
  for (final entry in _wildcardDefaults.entries) {
    if (stage.startsWith(entry.key)) return entry.value;
  }

  // 3. Category fallback (from prefix in stage name)
  if (stage.startsWith('UI_')) return _uiDefault;
  if (stage.startsWith('VO_')) return _voDefault;
  if (stage.startsWith('MUSIC_')) return _musicDefault;
  if (stage.startsWith('AMBIENT_')) return _ambientDefault;
  if (stage.startsWith('TRANSITION_')) return _transitionDefault;

  // 4. Global fallback
  return _globalDefault; // volume 1.0, bus sfx(2), no fade, no loop
}
```

### Default values

All values from FFNC.md Smart Defaults tables. Example subset:

```dart
const _exactDefaults = <String, StageDefault>{
  'SPIN_START':       StageDefault(volume: 0.70, busId: 2),
  'REEL_SPIN_LOOP':   StageDefault(volume: 0.60, busId: 2, loop: true),
  'SPIN_END':         StageDefault(volume: 0.50, busId: 2),
  'SLAM_STOP':        StageDefault(volume: 0.90, busId: 2),
  'QUICK_STOP':       StageDefault(volume: 0.85, busId: 2),

  'WIN_PRESENT_LOW':  StageDefault(volume: 0.40, busId: 2),
  'WIN_PRESENT_EQUAL':StageDefault(volume: 0.50, busId: 2),
  'WIN_PRESENT_1':    StageDefault(volume: 0.55, busId: 2),
  'WIN_PRESENT_2':    StageDefault(volume: 0.60, busId: 2),
  'WIN_PRESENT_3':    StageDefault(volume: 0.65, busId: 2),
  'WIN_PRESENT_4':    StageDefault(volume: 0.70, busId: 2),
  'WIN_PRESENT_5':    StageDefault(volume: 0.75, busId: 2),
  // ... all values from FFNC.md

  'BIG_WIN_START':    StageDefault(volume: 1.00, busId: 2),
  'BIG_WIN_END':      StageDefault(volume: 0.80, busId: 2, fadeOutMs: 500),

  'MUSIC_BASE_L1':    StageDefault(volume: 1.00, busId: 1, loop: true),
  'AMBIENT_BASE':     StageDefault(volume: 0.40, busId: 4, fadeInMs: 500, loop: true),
  'ATTRACT_LOOP':     StageDefault(volume: 0.35, busId: 4, fadeInMs: 1000, loop: true),
  // ... complete list from FFNC.md
};

const _wildcardDefaults = <String, StageDefault>{
  'REEL_STOP_':          StageDefault(volume: 0.80, busId: 2, fadeOutMs: 100),
  'ANTICIPATION_':       StageDefault(volume: 0.50, busId: 2, fadeInMs: 300, loop: true),
  'BIG_WIN_TIER_':       StageDefault(volume: 0.90, busId: 2, fadeInMs: 50),
  'SCATTER_LAND_':       StageDefault(volume: 0.80, busId: 2),
  'MUSIC_BASE_L':        StageDefault(volume: 0.00, busId: 1, loop: true), // L2+ silent
  'MUSIC_FS_L':          StageDefault(volume: 0.00, busId: 1, loop: true),
  'MUSIC_BONUS_L':       StageDefault(volume: 0.00, busId: 1, loop: true),
  'MUSIC_HOLD_L':        StageDefault(volume: 0.00, busId: 1, loop: true),
  'MUSIC_JACKPOT_L':     StageDefault(volume: 0.00, busId: 1, loop: true),
  'MUSIC_GAMBLE_L':      StageDefault(volume: 0.00, busId: 1, loop: true),
  'MUSIC_REVEAL_L':      StageDefault(volume: 0.00, busId: 1, loop: true),
  'MUSIC_TENSION_':      StageDefault(volume: 0.60, busId: 1, fadeInMs: 300, loop: true),
  'AMBIENT_':            StageDefault(volume: 0.40, busId: 4, fadeInMs: 500, loop: true),
  'TRANSITION_':         StageDefault(volume: 0.70, busId: 2),
  'CASCADE_STEP_':       StageDefault(volume: 0.60, busId: 2),
  'MULTIPLIER_X':        StageDefault(volume: 0.80, busId: 2),
  'WIN_PRESENT_':        StageDefault(volume: 0.65, busId: 2),
  'JACKPOT_':            StageDefault(volume: 0.85, busId: 2),
};
```

---

## 1.3 AUTOBIND Integration

**Modified file:** `flutter_ui/lib/providers/slot_lab_project_provider.dart`
**Modified method:** `autoBindFromFolder()` (line 591)

### Change summary

Add FFNC detection as **first step** before alias matching. Apply smart defaults when creating composite events.

### Current flow (simplified):

```
for each audio file:
  normalize filename
  _resolveStageFromFilename() → alias matching (80% accuracy)
  if matched: bindings[stage] = path (volume 1.0, bus sfx)
  else: unmapped.add(filename)
```

### New flow:

```
for each audio file:
  if isFFNC(filename):
    result = ffncParser.parse(filename)  ← NEW: 100% accurate
    if result != null:
      bindings[stage] = path
      ffncResults[stage] = result  ← store for layer/variant processing
      continue

  // Legacy fallback (unchanged)
  normalize filename
  _resolveStageFromFilename() → alias matching
  if matched: bindings[stage] = path
  else: unmapped.add(filename)
```

### Multi-layer handling (NEW):

After all files are processed, group by stage + layer:

```dart
// Group FFNC results by stage
final stageGroups = <String, List<FFNCResult>>{};
for (final entry in ffncResults.entries) {
  final stage = entry.value.stage;
  stageGroups.putIfAbsent(stage, () => []).add(entry.value);
}

// For multi-layer events (layer > 1), create multi-layer composite
for (final group in stageGroups.entries) {
  if (group.value.length > 1 || group.value.first.layer > 1) {
    // Create multi-layer SlotCompositeEvent
    _createMultiLayerComposite(group.key, group.value, bindings);
  }
}
```

### Variant handling (NEW):

```dart
// For variant files, populate _audioVariants pool
for (final entry in ffncResults.entries) {
  if (entry.value.variant != null) {
    final stage = entry.value.stage;
    _audioVariants.putIfAbsent(stage, () => []);
    if (!_audioVariants[stage]!.contains(bindings[entry.key])) {
      _audioVariants[stage]!.add(bindings[entry.key]!);
    }
  }
}
```

### Smart Defaults integration:

**Modified file:** `flutter_ui/lib/screens/slot_lab_screen.dart`
**Modified method:** `_ensureCompositeEventForStage()` (line 542)

Currently, all non-special stages get:
- volume: 1.0
- busId: `_getBusForStage(stage)` (from StageConfigurationService)
- fadeIn/fadeOut: 0
- loop: `StageConfigurationService.isLooping(stage)`

Change: lookup smart defaults first, use as base:

```dart
void _ensureCompositeEventForStage(String stage, String audioPath, ...) {
  // ... existing special cases (GAME_START, BIG_WIN_START, BIG_WIN_END, SLAM_STOP) ...

  // NEW: Get smart defaults for this stage
  final defaults = StageDefaults.getDefaultForStage(stage);

  final busId = defaults.busId;  // was: _getBusForStage(stage)
  final shouldLoop = defaults.loop;  // was: StageConfigurationService.isLooping(stage)
  final volume = defaults.volume;  // was: 1.0
  final fadeInMs = defaults.fadeInMs ?? 0;  // was: 0
  final fadeOutMs = defaults.fadeOutMs ?? 0;  // was: 0

  // ... rest of method uses these values instead of hardcoded ...
}
```

---

## 1.35 Parameter Resolution Priority Chain

When creating a composite event, multiple systems can provide volume, bus, fade, and loop values. This is the definitive priority order (highest wins):

```
PRIORITY 1 (highest): ASSIGN tab manual override
  → User explicitly set volume/bus/fade via UI slider/dropdown
  → Stored in SlotCompositeEvent layer properties
  → ALWAYS wins — user intent is sacred

PRIORITY 2: FFNC file name parameters (future, if ever added)
  → Currently NOT in FFNC spec (we decided against params in filenames)
  → Reserved for potential future use

PRIORITY 3: Smart Defaults (stage_defaults.dart)
  → Exact stage match: SPIN_START → volume 0.70, bus sfx
  → Wildcard match: REEL_STOP_* → volume 0.80, bus sfx, fadeOut 100
  → Category match: UI_* → volume 0.50, bus sfx
  → Applied during _ensureCompositeEventForStage()

PRIORITY 4: StageConfigurationService
  → getBus(stage) → engine bus ID
  → isLooping(stage) → loop flag
  → Used as FALLBACK when Smart Defaults don't cover a stage

PRIORITY 5 (lowest): Global default
  → volume: 1.0, busId: 2 (sfx), fadeIn: 0, fadeOut: 0, loop: false
  → Used when nothing else matches
```

### Implementation in `_ensureCompositeEventForStage()`:

```dart
// Priority 3: Smart Defaults
final defaults = StageDefaults.getDefaultForStage(stage);

// Priority 4: StageConfigurationService (fallback for bus/loop)
final scsBus = StageConfigurationService.instance.getBus(stage).engineBusId;
final scsLoop = StageConfigurationService.instance.isLooping(stage);

// Merge: Smart Defaults win over SCS, but SCS fills gaps
final busId = defaults.busId;  // Smart Defaults always has a value (global fallback = sfx)
final shouldLoop = defaults.loop;  // Same
final volume = defaults.volume;
final fadeInMs = defaults.fadeInMs ?? 0.0;
final fadeOutMs = defaults.fadeOutMs ?? 0.0;

// Priority 1: If user later edits in ASSIGN tab, those values
// are written directly to SlotCompositeEvent and override everything above.
```

### Key rule

Smart Defaults in `stage_defaults.dart` must be a SUPERSET of what `StageConfigurationService` provides. Every stage that SCS knows about must have an entry (exact or wildcard) in Smart Defaults. This ensures Smart Defaults is always the single source of truth for initial values.

---

## 1.4 Rename Tool

**New files:**
- `flutter_ui/lib/services/ffnc/ffnc_renamer.dart` (~150 lines)
- `flutter_ui/lib/widgets/slot_lab/ffnc_rename_dialog.dart` (~250 lines)

### What it does

Takes a folder of arbitrarily-named audio files, uses the existing 150+ alias system to identify stages, generates FFNC-compliant names, and copies files to output folder.

### ffnc_renamer.dart

```dart
class FFNCRenameResult {
  final String originalPath;
  final String originalName;
  final String? ffncName;        // null = unmatched
  final String? stage;           // resolved stage
  final FFNCCategory? category;  // determined prefix
  final bool isExactMatch;       // true = confident, false = fuzzy
}

class FFNCRenamer {
  /// Analyze a folder and generate rename suggestions
  List<FFNCRenameResult> analyze(String folderPath) {
    // 1. Scan folder for audio files
    // 2. For each file, run through existing _resolveStageFromFilename()
    // 3. If matched, determine FFNC prefix from stage category
    // 4. Generate FFNC filename using reverse transformation
    // 5. Return list of suggestions
  }

  /// Generate FFNC filename from stage name
  String generateFFNCName(String stage, FFNCCategory category) {
    // Reverse transformations:
    // REEL_STOP_0 → sfx_reel_stop_1 (0-based → 1-based)
    // WIN_PRESENT_3 → sfx_win_tier_3 (WIN_PRESENT → win_tier)
    // MUSIC_BASE_L1 → mus_base_game_l1 (BASE → base_game)
    // MUSIC_FS_L2 → mus_freespin_l2 (FS → freespin)
    // AMBIENT_BASE → amb_base_game
    // AMBIENT_FS → amb_freespin
    // TRANSITION_BASE_TO_FS → trn_base_game_to_freespin
    // UI_SPIN_PRESS → ui_spin_press (direct lowercase)
    // VO_BIG_WIN → vo_big_win (direct lowercase)
  }

  /// Determine prefix category from stage name
  FFNCCategory categorizeStage(String stage) {
    if (stage.startsWith('MUSIC_')) return FFNCCategory.mus;
    if (stage.startsWith('AMBIENT_') ||
        stage.startsWith('ATTRACT_') ||
        stage.startsWith('IDLE_')) return FFNCCategory.amb;
    if (stage.startsWith('TRANSITION_')) return FFNCCategory.trn;
    if (stage.startsWith('UI_')) return FFNCCategory.ui;
    if (stage.startsWith('VO_')) return FFNCCategory.vo;
    return FFNCCategory.sfx;
  }

  /// Copy files with new names to output folder
  Future<int> copyRenamed(List<FFNCRenameResult> results, String outputPath);

  /// Suggest closest stage for unmatched filename (typo correction)
  List<StageSuggestion> suggestStage(String unmatchedName, {int maxResults = 3}) {
    // 1. Normalize unmatched name (lowercase, strip prefix/suffix)
    // 2. Calculate Levenshtein distance to all 593 known stage names
    // 3. Return top N closest matches with distance score
    // 4. Only suggest if distance <= 3 (avoid wild guesses)
  }
}

class StageSuggestion {
  final String stage;       // e.g., "REEL_STOP"
  final String ffncName;    // e.g., "sfx_reel_stop"
  final int distance;       // Levenshtein distance (lower = closer match)
}
```

### Typo detection in Rename Tool

When a file doesn't match any alias or FFNC pattern, the Rename Tool calculates Levenshtein distance against all known stage names and suggests closest matches:

```
Unmatched: reel_stopp.wav
Suggestions:
  ● sfx_reel_stop        (distance: 1 — typo: extra 'p')
  ○ sfx_reel_slow_stop   (distance: 5)
  ○ sfx_reel_spin_loop   (distance: 7)
```

```
Unmatched: big_winn_start.wav
Suggestions:
  ● sfx_big_win_start    (distance: 1 — typo: extra 'n')
  ○ sfx_big_win_tier_1   (distance: 6)
```

Only suggestions with distance ≤ 3 are shown. If nothing is close enough, the file is marked as truly unmatched and requires manual stage selection from dropdown.

### Levenshtein implementation

```dart
int levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final matrix = List.generate(a.length + 1,
      (i) => List.generate(b.length + 1, (j) => i == 0 ? j : (j == 0 ? i : 0)));

  for (int i = 1; i <= a.length; i++) {
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,      // deletion
        matrix[i][j - 1] + 1,      // insertion
        matrix[i - 1][j - 1] + cost // substitution
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  return matrix[a.length][b.length];
}
```

~30 lines, no dependencies. Built into `ffnc_renamer.dart`.

### ffnc_rename_dialog.dart

Dialog UI in ASSIGN tab:

```
┌─ FFNC Rename Tool ──────────────────────────────────────────────┐
│                                                                   │
│ Source: /Raw Audio/                                 [Browse...]    │
│ Output: /FluxForge Audio/                          [Browse...]    │
│                                                                   │
│ ┌───────────────────────────────────────────────────────────────┐ │
│ │ ORIGINAL                 → FFNC NAME               STATUS    │ │
│ │                                                               │ │
│ │ 004_ReelStop_2.wav       → sfx_reel_stop_2.wav       ✓ auto  │ │
│ │ BG_Music_Level3.wav      → mus_base_game_l3.wav      ✓ auto  │ │
│ │ big win loop.wav         → sfx_big_win_start.wav     ✓ auto  │ │
│ │ SFX_SpinButton.wav       → ui_spin_press.wav         ✓ auto  │ │
│ │ hit_impact_big.wav       → ???                        ⚠ ???   │ │
│ └───────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ ⚠ 1 unmatched — click row to assign manually                     │
│                                                                   │
│ Unmatched: hit_impact_big.wav                                     │
│ Stage: [big_win_tier_1 ▾]  Category: [sfx ▾]                     │
│                                                                   │
│ ☑ Copy to output folder (originals unchanged)                     │
│ ☐ Rename in place (modifies originals)                            │
│                                                                   │
│ Matched: 8/9 (89%)                                                │
│                                                                   │
│ [Rename & Copy]  [Cancel]                                         │
└───────────────────────────────────────────────────────────────────┘
```

### UI integration

**Modified file:** `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart`

Add button in header row (line ~503), next to existing Auto-Bind button:

```dart
_compactActionBtn(
  icon: Icons.drive_file_rename_outline,
  color: FluxForgeTheme.accentCyan,
  tooltip: 'FFNC Rename Tool',
  onTap: () => _showFFNCRenameDialog(context),
),
```

---

## 1.5 New files summary

```
flutter_ui/lib/services/ffnc/
├── ffnc_parser.dart           ~120 lines  — parse FFNC filenames
├── stage_defaults.dart        ~250 lines  — smart defaults per stage
└── ffnc_renamer.dart          ~150 lines  — generate FFNC names from legacy

flutter_ui/lib/widgets/slot_lab/
└── ffnc_rename_dialog.dart    ~250 lines  — rename tool UI
```

### Modified files

```
slot_lab_project_provider.dart  — autoBindFromFolder(): add FFNC detection path (~30 lines)
slot_lab_screen.dart            — _ensureCompositeEventForStage(): use smart defaults (~15 lines)
ultimate_audio_panel.dart       — add Rename Tool button in header (~5 lines)
```

---

# PHASE 2 — Batch Operations in ASSIGN Tab

**Impact:** 10 events changed in 1 click instead of 10
**Risk:** Low — UI-only changes, no data model changes
**Estimated new code:** ~400 lines

---

## 2.1 Multi-Select

**Modified file:** `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart`

### State change

Currently single selection:
```dart
// Parent provides:
String? quickAssignSelectedSlot;
```

Add multi-select:
```dart
// NEW state in UltimateAudioPanel:
Set<String> _selectedSlots = {};
bool _multiSelectMode = false;
```

### Interaction

- **Single click** (normal mode) → select one slot (existing Quick Assign behavior)
- **Shift+click** → add/remove from multi-selection
- **Click phase header checkbox** → select all slots in that phase
- **Escape** → clear selection

### Visual feedback

Selected slots get a colored left border + subtle background tint. Selection count badge appears in header.

```dart
// In _buildSlot():
final isMultiSelected = _selectedSlots.contains(slot.stage);

Container(
  decoration: BoxDecoration(
    border: Border(
      left: BorderSide(
        color: isMultiSelected ? FluxForgeTheme.accentOrange : Colors.transparent,
        width: 3,
      ),
    ),
    color: isMultiSelected
        ? FluxForgeTheme.accentOrange.withOpacity(0.08)
        : null,
  ),
  // ... existing slot content
)
```

---

## 2.2 Batch Edit Bar

When `_selectedSlots.isNotEmpty`, show a sticky bar at the top of the panel:

```
┌─ 5 selected ────────────────────────────────────────────────┐
│ Volume: [====●====] 0.80   Bus: [sfx ▾]   FadeOut: [100ms] │
│                                                              │
│ [Apply to Selected]  [Clear All]  [Select None]              │
└──────────────────────────────────────────────────────────────┘
```

### Implementation

**New widget:** embedded in `ultimate_audio_panel.dart` build method (~100 lines)

```dart
Widget _buildBatchEditBar() {
  if (_selectedSlots.isEmpty) return const SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    color: FluxForgeTheme.bgMid,
    child: Column(
      children: [
        Row(children: [
          Text('${_selectedSlots.length} selected',
              style: TextStyle(color: FluxForgeTheme.accentOrange, fontSize: 11)),
          const Spacer(),
          // Close button
          IconButton(icon: Icon(Icons.close, size: 14), onPressed: _clearSelection),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          // Volume slider
          _batchSlider('Vol', _batchVolume, (v) => setState(() => _batchVolume = v)),
          const SizedBox(width: 12),
          // Bus dropdown
          _batchBusDropdown(),
          const SizedBox(width: 12),
          // Fade out field
          _batchFadeField('FO', _batchFadeOut, (v) => setState(() => _batchFadeOut = v)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          ElevatedButton(
            onPressed: _applyBatchEdit,
            child: const Text('Apply to Selected'),
          ),
        ]),
      ],
    ),
  );
}
```

### Apply logic

```dart
void _applyBatchEdit() {
  for (final stage in _selectedSlots) {
    // Update composite event for each selected stage
    widget.onBatchUpdate?.call(stage, BatchParams(
      volume: _batchVolume,
      busId: _batchBusId,
      fadeOutMs: _batchFadeOut,
    ));
  }
  _clearSelection();
}
```

**New callback on UltimateAudioPanel:**
```dart
final Function(String stage, BatchParams params)? onBatchUpdate;
```

**Handler in slot_lab_screen.dart:**
```dart
onBatchUpdate: (stage, params) {
  // Find composite event for this stage
  // Update volume/bus/fade on all auto-layers
  // Re-sync to EventRegistry
}
```

---

## 2.3 Event Presets (Save / Load per Event)

Individual event presets — save the configuration of one event and apply it to another.

### Use case

Designer configures a perfect "Reel Stop" event (volume 0.8, bus reels, fadeOut 100ms, 1 layer). Wants to apply the same setup to all 5 reel stops, or reuse in next project.

### UI

Right-click any assigned slot in ASSIGN tab:

```
Save as Event Preset...
├── Name: [Standard Reel Stop    ]
└── [Save]

Load Event Preset...
├── Standard Reel Stop (v:0.8, reels, fo:100ms)
├── Heavy Impact (v:0.9, sfx)
├── Music Loop (v:0.6, music, loop, fi:200ms)
├── Ambient Pad (v:0.4, ambience, loop, fi:500ms)
└── UI Click (v:0.5, ui)
```

### Data model

```dart
class EventPreset {
  final String name;
  final double volume;
  final int busId;
  final double fadeInMs;
  final double fadeOutMs;
  final bool loop;
  final bool overlap;
  final int crossfadeMs;

  Map<String, dynamic> toJson();
  factory EventPreset.fromJson(Map<String, dynamic> json);
}
```

### Storage

Presets saved to `~/.fluxforge/event_presets.json`:

```json
{
  "presets": [
    {
      "name": "Standard Reel Stop",
      "volume": 0.8,
      "busId": 2,
      "fadeInMs": 0,
      "fadeOutMs": 100,
      "loop": false,
      "overlap": true,
      "crossfadeMs": 0
    }
  ]
}
```

### Apply logic

When loading a preset onto a slot:
1. Find the composite event for that stage
2. Update volume, bus, fade, loop on all auto-generated layers
3. Keep the audio file path unchanged (preset only changes parameters, not audio)
4. Re-sync to EventRegistry

### Built-in presets

Ship with 5-6 default presets that cover common patterns:

| Preset | Volume | Bus | FadeIn | FadeOut | Loop |
|--------|--------|-----|--------|---------|------|
| Standard Reel Stop | 0.80 | sfx | — | 100ms | — |
| Heavy Impact | 0.90 | sfx | — | — | — |
| Music Loop | 0.60 | music | 200ms | — | ✓ |
| Ambient Pad | 0.40 | ambience | 500ms | — | ✓ |
| UI Click | 0.50 | sfx | — | — | — |
| Win Celebration | 0.75 | sfx | 50ms | — | — |

**New file:** `flutter_ui/lib/services/ffnc/event_presets.dart` (~80 lines)

---

## 2.5 Phase Presets

Right-click on phase header → context menu:

```
Apply Preset to Phase:
├── Standard Slot (balanced volumes, standard buses)
├── High Energy (louder wins, faster rollup)
├── Cinematic (longer fades, ambient emphasis)
├── Mobile (lower volumes, shorter fades)
└── Reset to Smart Defaults
```

### Implementation

**New file:** `flutter_ui/lib/services/ffnc/phase_presets.dart` (~100 lines)

```dart
class PhasePreset {
  final String name;
  final Map<String, StageDefault> overrides;  // stage → custom defaults
}

const standardPreset = PhasePreset(
  name: 'Standard Slot',
  overrides: {}, // uses smart defaults as-is
);

const highEnergyPreset = PhasePreset(
  name: 'High Energy',
  overrides: {
    'WIN_PRESENT_1': StageDefault(volume: 0.70, busId: 2),
    'WIN_PRESENT_2': StageDefault(volume: 0.75, busId: 2),
    // ... boosted volumes
  },
);
```

**Apply:** iterates all stages in phase, updates composite events with preset values.

---

## 2.6 Copy Phase Config Between Projects

Right-click phase header → "Copy Phase Config"

Serializes all stage parameters in that phase to clipboard as JSON:

```json
{
  "phase": "WINS",
  "stages": {
    "WIN_PRESENT_1": { "volume": 0.55, "busId": 2 },
    "WIN_PRESENT_2": { "volume": 0.60, "busId": 2 },
    "ROLLUP_TICK": { "volume": 0.40, "busId": 2 }
  }
}
```

In another project: right-click phase → "Paste Phase Config" → applies parameters (not audio files).

---

# PHASE 3 — Audio Profile System

**Impact:** New project setup from template in 5 minutes instead of 70
**Risk:** Low — uses existing serialization infrastructure
**Estimated new code:** ~500 lines

---

## 3.1 FluxForge Audio Profile (.ffap)

A `.ffap` file is a ZIP archive containing:

```
zeus_thunderbolt.ffap (ZIP)
├── manifest.json           — metadata
├── events.json             — all SlotCompositeEvent objects
├── win_tiers.json          — WinTierConfig
├── music_layers.json       — MusicLayerConfig
├── stage_defaults.json     — custom smart default overrides
└── README.txt              — human-readable auto-generated summary
```

### manifest.json

```json
{
  "name": "Zeus Thunderbolt",
  "version": "1.0",
  "created": "2026-03-19T14:00:00Z",
  "creator": "Bojan",
  "reels": 5,
  "eventCount": 42,
  "mechanics": ["cascade", "free_spins", "hold_and_win"],
  "ffncVersion": "1.0",
  "fluxforgeVersion": "2.1.0"
}
```

### events.json

Uses existing `CompositeEventSystemProvider.exportCompositeEventsToJson()` format — already implemented, zero new serialization code needed.

### win_tiers.json

Uses existing `SlotWinConfiguration.toJson()` format — already implemented.

### music_layers.json

Uses existing `MusicLayerConfig.toJson()` format — already implemented.

### README.txt

Auto-generated human-readable summary:

```
FluxForge Audio Profile: Zeus Thunderbolt
Created: 2026-03-19 by Bojan
Reels: 5 | Events: 42 | Mechanics: cascade, free_spins, hold_and_win

SPIN (6 events):
  SPIN_START          → sfx/spin_whoosh.wav (v:0.70, sfx)
  REEL_SPIN_LOOP      → sfx/reel_loop.wav (v:0.60, reels, loop)
  REEL_STOP_0..4      → sfx/reel_impact.wav (v:0.80, reels, fo:100ms)
  SPIN_END            → sfx/settle.wav (v:0.50, sfx)

WINS (8 events):
  WIN_PRESENT_1..5    → progressive volume 0.55-0.75
  ROLLUP_TICK         → sfx/tick.wav (v:0.40, wins) [4 variants]
  ROLLUP_END          → sfx/end.wav (v:0.50, wins)

BIG WINS (5 events):
  BIG_WIN_START       → 2 layers (impact + theme loop)
  BIG_WIN_TIER_1..3   → sfx/bigwin.wav (v:0.90-1.00, wins)
  BIG_WIN_END         → sfx/end.wav (v:0.80, fo:500ms)

MUSIC (5 layers):
  Base Game L1..L3    → mus/base_1..3.wav (crossfade)
  Free Spins L1..L2   → mus/fs_1..2.wav

WIN TIERS:
  Regular: 8 tiers (0x-20x)
  Big Win: 3 tiers (20x-250x+)
```

This README allows git diff review even without FluxForge Studio open.

---

## 3.2 Export

**New file:** `flutter_ui/lib/services/ffnc/profile_exporter.dart` (~150 lines)

```dart
class ProfileExporter {
  /// Export current project state as .ffap file
  Future<String> export({
    required SlotLabProjectProvider projectProvider,
    required CompositeEventSystemProvider compositeProvider,
    required String outputPath,
    String? name,
    String? creator,
  }) async {
    // 1. Collect data from providers (existing toJson methods)
    // 2. Generate README.txt
    // 3. Create ZIP archive with all JSON files
    // 4. Write to outputPath
    // 5. Return path
  }
}
```

### UI integration

```
File menu → Export Audio Profile...
  → file save dialog (.ffap extension)
  → ProfileExporter.export()
  → toast: "Profile exported to zeus_thunderbolt.ffap"
```

---

## 3.3 Import

**New file:** `flutter_ui/lib/services/ffnc/profile_importer.dart` (~200 lines)

```dart
class ProfileImporter {
  /// Preview what a profile contains (without applying)
  Future<ProfilePreview> preview(String ffapPath);

  /// Import profile into current project
  Future<void> import({
    required String ffapPath,
    required SlotLabProjectProvider projectProvider,
    required CompositeEventSystemProvider compositeProvider,
    required ProfileImportOptions options,
  });
}

class ProfileImportOptions {
  final bool importEvents;          // default: true
  final bool importWinTiers;        // default: true
  final bool importMusicLayers;     // default: true
  final String? remapAudioFolder;   // null = keep original paths
  final ConflictResolution conflict; // skip, overwrite, merge
}
```

### Import dialog

```
┌─ Import Profile: zeus_thunderbolt.ffap ─────────────────────┐
│                                                               │
│ Found: 42 events, 8 win tiers, 3 music layers                │
│                                                               │
│ Import:                                                       │
│ ☑ Events (42)                                                 │
│ ☑ Win Tier Config                                             │
│ ☑ Music Layer Config                                          │
│                                                               │
│ Audio files:                                                  │
│ ○ Keep original paths (same machine)                          │
│ ● Remap to folder: [Browse...]                                │
│   /themes/book_of_ra/audio/                                   │
│                                                               │
│ Conflicts:                                                    │
│ ○ Skip existing    ● Overwrite    ○ Merge                     │
│                                                               │
│ [Preview] [Import] [Cancel]                                   │
└───────────────────────────────────────────────────────────────┘
```

### Audio path remapping

When importing a profile from another project, audio paths won't match. Remap option:

```dart
String remapAudioPath(String originalPath, String remapFolder) {
  final filename = path.basename(originalPath);  // "sfx_reel_stop_1.wav"
  final remapped = path.join(remapFolder, filename);
  if (File(remapped).existsSync()) return remapped;
  return originalPath;  // keep original if remap not found
}
```

If files use FFNC naming, filenames match across projects → remap works perfectly.

---

## 3.4 Template Library

**New file:** `flutter_ui/lib/services/ffnc/template_library.dart` (~100 lines)

Templates are `.ffap` files without audio files — only configuration (volumes, buses, fades, win tiers, music layers).

### Built-in templates

Bundled in `assets/templates/`:

```
assets/templates/
├── classic_5reel.ffap          — standard 5-reel slot (~40 events)
├── megaways.ffap               — megaways specific (~55 events, cascade)
├── cascading.ffap              — tumble/cascade mechanics
├── hold_and_win.ffap           — hold & win + respins
├── bonus_wheel.ffap            — wheel bonus + pick games
└── jackpot_progressive.ffap    — progressive jackpot focus
```

### User templates

Saved to `~/.fluxforge/templates/`:

```dart
File menu → Save as Template...
  → name dialog
  → exports .ffap to ~/.fluxforge/templates/
```

### New Project from Template

```
File menu → New from Template...
  → template picker dialog
  → creates project with all config pre-filled
  → user runs Auto-Bind to add audio files
```

---

# PHASE 4 — Inline Validation

**Impact:** Catch errors before runtime — no more "why is there no sound?"
**Risk:** Zero — read-only analysis, displays warnings
**Estimated new code:** ~300 lines

---

## 4.1 Assignment Validator

**New file:** `flutter_ui/lib/services/ffnc/assignment_validator.dart` (~200 lines)

```dart
class AssignmentWarning {
  final String stage;
  final WarningType type;
  final String message;
  final WarningSeverity severity;  // error, warning, info
}

enum WarningType {
  missingAudio,       // stage has no audio file assigned
  missingFile,        // assigned file doesn't exist on disk
  invalidBus,         // bus name not recognized
  zeroVolume,         // volume is 0.0 (intentional?)
  noFadeOnLoop,       // looping sound with no fade-out (potential pop)
  duplicateAssignment,// two stages point to same file (intentional?)
  missingVariant,     // stage has variants but primary is missing
  layerGap,           // layer1 and layer3 exist but not layer2
}

class AssignmentValidator {
  List<AssignmentWarning> validate({
    required Map<String, String> audioAssignments,
    required List<SlotCompositeEvent> compositeEvents,
    required Set<String> enabledStages,  // from FeatureComposerProvider
  }) {
    final warnings = <AssignmentWarning>[];

    for (final stage in enabledStages) {
      // Check: has audio assigned?
      if (!audioAssignments.containsKey(stage)) {
        warnings.add(AssignmentWarning(
          stage: stage,
          type: WarningType.missingAudio,
          message: 'No audio assigned',
          severity: _getSeverity(stage),  // P0 stages = error, P2 = info
        ));
        continue;
      }

      // Check: file exists?
      final path = audioAssignments[stage]!;
      if (!File(path).existsSync()) {
        warnings.add(AssignmentWarning(
          stage: stage,
          type: WarningType.missingFile,
          message: 'File not found: ${path.split('/').last}',
          severity: WarningSeverity.error,
        ));
      }
    }

    // Check composite events for issues
    for (final event in compositeEvents) {
      // Zero volume check
      if (event.masterVolume == 0.0) {
        warnings.add(AssignmentWarning(
          stage: event.triggerStages.firstOrNull ?? event.id,
          type: WarningType.zeroVolume,
          message: 'Volume is 0.0',
          severity: WarningSeverity.warning,
        ));
      }

      // Loop without fade-out
      if (event.looping) {
        for (final layer in event.layers) {
          if (layer.loop && layer.fadeOutMs == 0) {
            warnings.add(AssignmentWarning(
              stage: event.triggerStages.firstOrNull ?? event.id,
              type: WarningType.noFadeOnLoop,
              message: 'Layer "${layer.name}" loops without fade-out',
              severity: WarningSeverity.info,
            ));
          }
        }
      }
    }

    return warnings;
  }

  WarningSeverity _getSeverity(String stage) {
    // P0 stages (critical gameplay) = error
    if (['SPIN_START', 'REEL_STOP', 'SPIN_END'].contains(stage)) {
      return WarningSeverity.error;
    }
    // P1 stages (important) = warning
    if (stage.startsWith('WIN_') || stage.startsWith('BIG_WIN_')) {
      return WarningSeverity.warning;
    }
    // P2 stages (optional) = info
    return WarningSeverity.info;
  }
}
```

---

## 4.2 Phase Completion Indicators

**Modified file:** `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart`

Phase headers show completion status:

```
▼ CORE LOOP  [18/22 ✓]                    ← all assigned
▼ WINS       [6/8]  ⚠ 2 warnings          ← partially assigned
▼ FEATURES   [0/12]                        ← nothing assigned (red text)
▼ MUSIC      [5/5 ✓]                      ← all assigned
▼ UI         [3/10]                        ← partially assigned
```

### Implementation

In `_buildPhase()` method, add validation badge:

```dart
// After existing assigned/total counter
final warnings = validator.getWarningsForPhase(phase.id);
if (warnings.isNotEmpty) {
  final errorCount = warnings.where((w) => w.severity == WarningSeverity.error).length;
  final warnCount = warnings.where((w) => w.severity == WarningSeverity.warning).length;

  Text(
    '⚠ ${errorCount + warnCount}',
    style: TextStyle(
      color: errorCount > 0 ? FluxForgeTheme.accentRed : FluxForgeTheme.accentYellow,
      fontSize: 9,
    ),
  );
}
```

---

## 4.3 Slot-Level Warnings

Individual slots show warning icons:

```
REEL_STOP_3    sfx_reel_stop_3.wav    v:0.8    ✓
REEL_STOP_4    ??? (missing)                    ⚠ No audio
WIN_TIER_3     sfx_win_tier_3.wav     v:0.0    ⚠ Zero volume
FEATURE_ENTER  sfx_missing.wav                  ✗ File not found
```

### Implementation

In `_buildSlot()`, add warning indicator:

```dart
final warning = validator.getWarningForStage(slot.stage);
if (warning != null) {
  Tooltip(
    message: warning.message,
    child: Icon(
      warning.severity == WarningSeverity.error ? Icons.error : Icons.warning,
      size: 12,
      color: warning.severity == WarningSeverity.error
          ? FluxForgeTheme.accentRed
          : FluxForgeTheme.accentYellow,
    ),
  );
}
```

---

## 4.4 Validation Panel (Optional)

New button in header: "Validate" → shows all warnings in a scrollable list:

```
┌─ Validation Results ─────────────────────────────────────────┐
│                                                               │
│ ✗ 2 errors  ⚠ 5 warnings  ℹ 3 info                          │
│                                                               │
│ ERRORS:                                                       │
│  ✗ REEL_STOP_4     — No audio assigned                        │
│  ✗ FEATURE_ENTER   — File not found: sfx_missing.wav          │
│                                                               │
│ WARNINGS:                                                     │
│  ⚠ WIN_TIER_3      — Volume is 0.0                            │
│  ⚠ ROLLUP_TICK     — No variants (single sound on repeat)     │
│  ⚠ BIG_WIN_TIER_3  — Bus "sfxx" not recognized                │
│  ⚠ REEL_SPIN_LOOP  — Loops without fade-out                   │
│  ⚠ ANTICIPATION    — No audio for enabled mechanic            │
│                                                               │
│ Click any row to jump to that slot in ASSIGN tab.             │
│                                                               │
│ [Re-Validate]  [Close]                                        │
└───────────────────────────────────────────────────────────────┘
```

---

# Summary

## All new files

```
flutter_ui/lib/services/ffnc/
├── ffnc_parser.dart             ~120 lines  Phase 1
├── stage_defaults.dart          ~250 lines  Phase 1
├── ffnc_renamer.dart            ~180 lines  Phase 1 (includes Levenshtein typo suggestion)
├── event_presets.dart           ~80 lines   Phase 2
├── phase_presets.dart           ~100 lines  Phase 2
├── profile_exporter.dart        ~150 lines  Phase 3
├── profile_importer.dart        ~200 lines  Phase 3
├── template_library.dart        ~100 lines  Phase 3
├── readme_generator.dart        ~80 lines   Phase 3
└── assignment_validator.dart    ~200 lines  Phase 4

flutter_ui/lib/widgets/slot_lab/
└── ffnc_rename_dialog.dart      ~250 lines  Phase 1

assets/templates/
├── classic_5reel.ffap           Phase 3
├── megaways.ffap                Phase 3
├── cascading.ffap               Phase 3
├── hold_and_win.ffap            Phase 3
├── bonus_wheel.ffap             Phase 3
└── jackpot_progressive.ffap     Phase 3
```

## All modified files

```
Phase 1:
  slot_lab_project_provider.dart   — FFNC detection in autoBindFromFolder() (~30 lines)
  slot_lab_screen.dart             — smart defaults in _ensureCompositeEventForStage() (~15 lines)
  ultimate_audio_panel.dart        — Rename Tool button (~5 lines)

Phase 2:
  ultimate_audio_panel.dart        — multi-select + batch edit bar + event preset menu (~250 lines)
  slot_lab_screen.dart             — batch update handler + preset apply handler (~40 lines)

Phase 3:
  slot_lab_screen.dart             — File menu export/import/template (~40 lines)

Phase 4:
  ultimate_audio_panel.dart        — phase/slot warning badges (~50 lines)
```

## User data locations

```
~/.fluxforge/
├── event_presets.json            — saved event presets (Phase 2)
└── templates/                    — user-saved templates (Phase 3)
    ├── my_template_1.ffap
    └── my_template_2.ffap
```

## What does NOT change (ever)

```
event_registry.dart              — same AudioEvent objects
slot_audio_provider.dart         — same playback logic
slot_stage_provider.dart         — same trigger logic
slot_engine_provider.dart        — same spin logic
composite_event_system_provider  — same CRUD operations
_syncEventToRegistry()           — same single registration point
win_tier_config.dart             — same model (only new consumers)
native_ffi.dart                  — zero FFI changes
Rust engine                      — zero changes
```

## Timeline

```
Phase 1: FFNC Parser + Smart Defaults + Rename Tool + Typo Suggestion
  → Biggest impact, foundation for everything else
  → AUTOBIND becomes 100% accurate for FFNC files
  → Smart Defaults eliminate "volume 1.0, bus sfx" on everything
  → Rename Tool converts legacy names to FFNC
  → Typo suggestion catches "reel_stopp" → "reel_stop"

Phase 2: Multi-Select + Batch Edit + Event Presets + Phase Presets
  → Quality of life for daily work
  → Shift+click to select 10 events, change volume in 1 click
  → Save event config as preset, reuse across stages/projects
  → Apply "High Energy" or "Cinematic" preset to entire phase

Phase 3: Profile Export/Import + Templates
  → Reusability across projects
  → Export complete audio profile as .ffap
  → Import with audio path remapping
  → Built-in templates for common slot types
  → User-saved templates

Phase 4: Inline Validation
  → Error prevention, polish
  → Missing audio, missing files, zero volume warnings
  → Phase completion indicators
  → Validation panel with all issues
```

Each phase is independent. Each delivers value on its own. Each can be shipped and used while the next is being built.

---

## Checklist — Everything We Discussed

| Topic | Status | Location |
|---|---|---|
| FFNC naming convention (6 prefixes) | ✓ Documented | FFNC.md |
| Full names (base_game, freespin, layer, variant) | ✓ Documented | FFNC.md |
| 1-based numbering | ✓ Documented | FFNC.md |
| Directional transitions (base_game_to_freespin) | ✓ Documented | FFNC.md |
| Game intro, plaque appear/disappear | ✓ Documented | FFNC.md |
| All realistic transition flows | ✓ Documented | FFNC.md |
| amb_ prefix for ambience/attract/idle | ✓ Documented | FFNC.md |
| Engine bus ID reference | ✓ Documented | FFNC.md |
| Smart Defaults per stage | ✓ Documented | FFNC.md + Phase 1 |
| FFNC Parser | ✓ Specified | Phase 1.1 |
| AUTOBIND integration | ✓ Specified | Phase 1.3 |
| Parameter resolution priority chain | ✓ Specified | Phase 1.35 |
| Rename Tool with UI | ✓ Specified | Phase 1.4 |
| Typo suggestion (Levenshtein) | ✓ Specified | Phase 1.4 |
| Multi-select in ASSIGN | ✓ Specified | Phase 2.1 |
| Batch Edit Bar | ✓ Specified | Phase 2.2 |
| Event Presets (save/load per event) | ✓ Specified | Phase 2.3 |
| Phase Presets (Standard/High Energy/Cinematic/Mobile) | ✓ Specified | Phase 2.5 |
| Copy Phase Config between projects | ✓ Specified | Phase 2.6 |
| .ffap Profile Export | ✓ Specified | Phase 3.1-3.2 |
| .ffap Profile Import with remap | ✓ Specified | Phase 3.3 |
| Template library (built-in + user) | ✓ Specified | Phase 3.4 |
| README.txt auto-generated summary | ✓ Specified | Phase 3.1 |
| Assignment Validator | ✓ Specified | Phase 4.1 |
| Phase completion indicators | ✓ Specified | Phase 4.2 |
| Slot-level warnings | ✓ Specified | Phase 4.3 |
| Validation panel | ✓ Specified | Phase 4.4 |
| Zero runtime changes | ✓ Confirmed | Architecture Principle |
| Legacy alias matching still works | ✓ Confirmed | Phase 1.3 |
| Multi-layer from filenames | ✓ Specified | FFNC.md + Phase 1.3 |
| Variant pool from filenames | ✓ Specified | FFNC.md + Phase 1.3 |

Each phase is independent. Each delivers value on its own. Each can be shipped and used while the next is being built.

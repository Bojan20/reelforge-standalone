# P13 Feature Builder — Apply & Build Integration

**Status:** ✅ P13.8.1-P13.8.6 COMPLETE (2026-02-01)
**Tracking:** MASTER_TODO.md → P13.8 Phase 9

---

## Overview

Feature Builder "Apply & Build" functionality implementirana — omogućava dizajnerima da:
1. Konfigurišu slot igru u Feature Builder panelu
2. Pritisnu "Apply & Build" dugme
3. Slot mašina se renderuje u **centralnom panelu** SlotLab-a (embedded mode)
4. **NE** otvara se fullscreen prozor

---

## Implementirane Komponente

### P13.8.1 — SlotLabScreen Integration ✅

**File:** `flutter_ui/lib/screens/slot_lab_screen.dart`

```dart
// FEATURES dugme u header-u (već postojalo)
void _showFeatureBuilder() async {
  final result = await FeatureBuilderPanel.show(context);
  if (result != null && mounted) {
    _applyFeatureBuilderResult(result);
  }
}

// Nova metoda za primenu rezultata
void _applyFeatureBuilderResult(FeatureBuilderResult result) {
  // Update grid settings (embedded mode, NO fullscreen)
  setState(() {
    _slotLabSettings = _slotLabSettings.copyWith(
      reels: result.reelCount,
      rows: result.rowCount,
    );
  });

  // Generate symbols if needed
  if (projectProvider.symbols.isEmpty) {
    _generateDefaultSymbols(result.symbolCount, projectProvider);
  }

  // Sync engine
  slotLabProvider.updateGridSize(result.reelCount, result.rowCount);
}
```

### P13.8.2 — FeatureBuilderProvider Registration ✅

**File:** `flutter_ui/lib/main.dart`

```dart
import 'providers/feature_builder_provider.dart';

// In MultiProvider:
ChangeNotifierProvider(create: (_) => FeatureBuilderProvider()),
```

### P13.8.3 — Apply & Build Callback ✅

**File:** `flutter_ui/lib/widgets/slot_lab/feature_builder_panel.dart`

```dart
// New callback parameter
final void Function(int reels, int rows, int symbols)? onApplyAndBuild;

// Result class
class FeatureBuilderResult {
  final int reelCount;
  final int rowCount;
  final int symbolCount;
}

// Static show method returns result
static Future<FeatureBuilderResult?> show(BuildContext context) async {
  FeatureBuilderResult? result;
  await showDialog(
    context: context,
    builder: (context) => FeatureBuilderPanel(
      onClose: () => Navigator.of(context).pop(),
      onApplyAndBuild: (reels, rows, symbols) {
        result = FeatureBuilderResult(
          reelCount: reels,
          rowCount: rows,
          symbolCount: symbols,
        );
        Navigator.of(context).pop();
      },
    ),
  );
  return result;
}

// Apply & Build button in footer
ElevatedButton.icon(
  icon: const Icon(Icons.build, size: 16),
  label: const Text('Apply & Build'),
  style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF40FF90),
    foregroundColor: Colors.black,
  ),
  onPressed: () {
    // Validate first
    final validationResult = provider.validate();
    if (!validationResult.isValid) {
      // Show error
      return;
    }

    // Generate stages
    final stageResult = provider.generateStages();
    if (stageResult.isValid) {
      provider.exportStagesToConfiguration();
    }

    // Get grid config and call callback
    widget.onApplyAndBuild?.call(reelCount, rowCount, symbolCount);
  },
),
```

### P13.8.4 — SlotLabProvider Grid Update ✅

**File:** `flutter_ui/lib/providers/slot_lab_provider.dart`

```dart
int _totalReels = 5;
int _totalRows = 3;

int get totalReels => _totalReels;
int get totalRows => _totalRows;

void updateGridSize(int reels, int rows) {
  if (reels != _totalReels || rows != _totalRows) {
    _totalReels = reels;
    _totalRows = rows;
    _reinitializeEngine();
    notifyListeners();
  }
}

void _reinitializeEngine() {
  // Re-initialize synthetic slot engine with new dimensions
  // This affects reel count, symbol positions, etc.
}
```

### P13.8.5 — Symbol Generation ✅

**File:** `flutter_ui/lib/screens/slot_lab_screen.dart`

```dart
void _generateDefaultSymbols(int count, SlotLabProjectProvider provider) {
  final defaultSymbols = <SymbolDefinition>[];

  const symbolEmojis = ['🍒', '🍋', '🍊', '🍇', '⭐', '💎', '7️⃣', '🔔', '🍀', '👑', '🎰', '💰'];
  const symbolNames = ['Cherry', 'Lemon', 'Orange', 'Grapes', 'Star', 'Diamond', 'Seven', 'Bell', 'Clover', 'Crown', 'Jackpot', 'Money'];

  for (int i = 0; i < count && i < symbolEmojis.length; i++) {
    final type = i < 4 ? SymbolType.lowPay
        : i < 7 ? SymbolType.mediumPay
        : i < 9 ? SymbolType.highPay
        : i == count - 2 ? SymbolType.scatter
        : i == count - 1 ? SymbolType.wild
        : SymbolType.highPay;

    defaultSymbols.add(SymbolDefinition(
      id: 'sym_$i',
      name: symbolNames[i],
      emoji: symbolEmojis[i],
      type: type,
      contexts: const ['land', 'win'],
    ));
  }

  for (final symbol in defaultSymbols) {
    provider.addSymbol(symbol);
  }
}
```

---

## Workflow Flow

```
1. User clicks FEATURES button in SlotLab header
2. FeatureBuilderPanel.show() opens modal dialog
3. User configures:
   - Grid (reels × rows)
   - Symbol count
   - Features (Free Spins, Cascades, etc.)
4. User clicks "Apply & Build" (green button)
5. Panel validates configuration
6. Panel generates stages
7. Panel returns FeatureBuilderResult
8. _applyFeatureBuilderResult() applies:
   - Grid dimensions to _slotLabSettings
   - Generates default symbols if empty
   - Updates SlotLabProvider engine
9. Slot machine renders in CENTER panel (embedded)
10. User can spin immediately
```

---

## Key Design Decisions

### Embedded vs Fullscreen

**Problem:** `_isPreviewMode = true` aktivira fullscreen PremiumSlotPreview koji prekriva ceo ekran.

**Rešenje:** Slot mašina se već prikazuje u centralnom panelu kroz `_buildMockSlot()`. Samo ažuriramo `_slotLabSettings` bez postavljanja `_isPreviewMode`.

```dart
// WRONG - opens fullscreen
_isPreviewMode = true;

// CORRECT - stays embedded
setState(() {
  _slotLabSettings = _slotLabSettings.copyWith(
    reels: result.reelCount,
    rows: result.rowCount,
  );
});
```

### SymbolDefinition API

`SymbolDefinition` koristi `contexts: List<String>` umesto `audioContexts: Set<SymbolAudioContext>`.

```dart
// WRONG
audioContexts: {SymbolAudioContext.land, SymbolAudioContext.win}

// CORRECT
contexts: const ['land', 'win']
```

---

## Files Changed

| File | LOC Changed | Description |
|------|-------------|-------------|
| `main.dart` | +3 | Provider registration |
| `feature_builder_panel.dart` | +80 | onApplyAndBuild callback, FeatureBuilderResult |
| `slot_lab_screen.dart` | +100 | _applyFeatureBuilderResult, _generateDefaultSymbols |
| `slot_lab_provider.dart` | +25 | updateGridSize method |

**Total:** ~208 LOC

---

### P13.8.6 — UltimateAudioPanel Stage Registration ✅

**Ultimate solution for instant stage display in UltimateAudioPanel.**

**Architecture:**
```
FeatureBuilderProvider.generateStages()
         ↓
StageGenerationResult.stages (List<GeneratedStageEntry>)
         ↓
UltimateAudioPanel(generatedStages: stages)
         ↓
_FeatureBuilderSection (FIRST section, dynamic groups by category)
         ↓
Instant display — no delay, no refresh needed
```

**Files Changed:**

| File | Changes | LOC |
|------|---------|-----|
| `ultimate_audio_panel.dart` | +1 import, +8 param, +85 section class | ~94 |
| `slot_lab_screen.dart` | +1 import, Consumer → Consumer2, +4 stage passing | ~6 |

**New Widget Parameter:**
```dart
/// Generated stages from Feature Builder (Apply & Build)
/// These appear FIRST in the panel for immediate audio assignment.
final List<GeneratedStageEntry>? generatedStages;
```

**New Dynamic Section:**
```dart
class _FeatureBuilderSection extends _SectionConfig {
  @override String get id => 'feature_builder';
  @override String get title => 'FEATURE BUILDER';
  @override String get icon => '⚡';
  @override Color get color => const Color(0xFF40FF90); // Green

  @override
  List<_GroupConfig> get groups {
    // Groups stages by category (free_spins, bonus, cascade, etc.)
    // Sorts by priority order
    // Adds markers: ⚡ for pooled, 🔄 for looping
  }
}
```

**Consumer2 Integration:**
```dart
Consumer2<SlotLabProjectProvider, FeatureBuilderProvider>(
  builder: (context, projectProvider, featureBuilderProvider, _) {
    final stageResult = featureBuilderProvider.generateStages();
    final generatedStages = stageResult.isValid ? stageResult.stages : null;

    return UltimateAudioPanel(
      // ... existing params ...
      generatedStages: generatedStages,  // P13.8.6
    );
  },
)
```

**Key Features:**
- ⚡ **INSTANT** — stages appear immediately when Feature Builder generates them
- 📦 **GROUPED** — stages organized by category (free_spins, bonus, cascade, etc.)
- 🎯 **PRIORITIZED** — Feature Builder section appears FIRST in panel
- ⚡🔄 **MARKED** — pooled and looping stages have visual markers
- 🟢 **GREEN** — distinctive color for Feature Builder stages

---

## Pending Tasks (P13.8.7-P13.8.9)

| ID | Task | Status |
|----|------|--------|
| P13.8.7 | ForcedOutcomePanel dynamic controls | ⏳ |
| P13.8.8 | Unit tests (30+) | ⏳ |
| P13.8.9 | Integration tests (10) | ⏳ |

---

*Created: 2026-02-01*
*Updated: 2026-02-01 — P13.8.6 COMPLETE*

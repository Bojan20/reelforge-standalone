# GDD Import System

**Status:** V9 Complete (2026-01-26)

Game Design Document (GDD) import system za automatsku konfiguraciju SlotLab projekata.

---

## Overview

GDD Import System omogućava:
1. Parsiranje GDD dokumenata (JSON i PDF/text format)
2. Automatsko kreiranje grid konfiguracije (rows × columns)
3. Generisanje simbola sa tierovima i emoji-ima
4. Kreiranje stage-ova za features
5. Preview dialog pre primene
6. Perzistenciju u SlotLab projektu

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         GDD IMPORT FLOW (V9)                          │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   Input (JSON/PDF/Text)                                              │
│          ↓                                                           │
│   GddImportService.importFromJson()                                  │
│          ↓                                                           │
│   ┌─────────────────────────────────────────────┐                    │
│   │ GameDesignDocument                          │                    │
│   │ ├── name, version, description              │                    │
│   │ ├── grid: GddGridConfig                     │                    │
│   │ ├── math: GddMathModel                      │                    │
│   │ ├── symbols: List<GddSymbol>                │                    │
│   │ ├── features: List<GddFeature>              │                    │
│   │ ├── customStages: List<String>              │                    │
│   │ └── toRustJson() → Rust-compatible format   │ ← NEW V9           │
│   └─────────────────────────────────────────────┘                    │
│          ↓                                                           │
│   GddImportResult                                                    │
│   ├── gdd: GameDesignDocument                                        │
│   ├── generatedStages: List<String>                                  │
│   ├── generatedSymbols: List<SymbolDefinition>                       │
│   └── warnings/errors: List<String>                                  │
│          ↓                                                           │
│   GddPreviewDialog (V8)                                              │
│   ├── Visual slot mockup (columns × rows)                            │
│   ├── Math panel (RTP, volatility, hit rate)                         │
│   ├── Symbols list with emojis                                       │
│   ├── Features list with types                                       │
│   └── [Apply Configuration] button                                   │
│          ↓                                                           │
│   SlotLabScreen._showGddImportWizard()                               │
│   ├── projectProvider.importGdd()                                    │
│   ├── _populateSlotSymbolsFromGdd()  ← NEW V9 (dynamic symbols)     │
│   ├── slotLabProvider.initEngineFromGdd(toRustJson())               │
│   ├── _slotLabSettings.copyWith(reels, rows)                         │
│   └── _isPreviewMode = true  ← OPENS FULLSCREEN                      │
│          ↓                                                           │
│   ┌─────────────────────────────────────────────┐                    │
│   │ PremiumSlotPreview (FULLSCREEN)             │                    │
│   │ ├── Reels: SlotSymbol.effectiveSymbols      │ ← GDD symbols      │
│   │ ├── Paytable: _PaytablePanel(gddSymbols)    │ ← GDD payouts      │
│   │ ├── Grid: columns × rows from GDD           │                    │
│   │ ├── Volatility from GDD math model          │                    │
│   │ └── ESC to exit fullscreen                  │                    │
│   └─────────────────────────────────────────────┘                    │
│                                                                       │
│   ┌─────────────────────────────────────────────┐                    │
│   │ Rust Engine (rf-slot-lab)                   │                    │
│   │ ├── Grid: reels × rows                      │                    │
│   │ ├── Symbols: id, type, pays[], tier         │ ← toRustJson()     │
│   │ ├── Symbol Weights per reel                 │                    │
│   │ ├── Win Mechanism (paylines/ways/cluster)   │                    │
│   │ └── Features: type, trigger, spins          │                    │
│   └─────────────────────────────────────────────┘                    │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## GDD Models

### GddGridConfig

```dart
class GddGridConfig {
  final int rows;        // 3-8 typical
  final int columns;     // 3-10 typical (reels)
  final String mechanic; // 'lines', 'ways', 'cluster', 'megaways'
  final int? paylines;   // For 'lines' mechanic
  final int? ways;       // For 'ways' mechanic
}
```

### GddSymbol

```dart
class GddSymbol {
  final String id;
  final String name;
  final SymbolTier tier;  // low, mid, high, premium, special, wild, scatter, bonus
  final Map<int, double> payouts;  // count -> multiplier
  final bool isWild;
  final bool isScatter;
  final bool isBonus;
}
```

### SymbolTier Enum

| Tier | Description | Typical Symbols |
|------|-------------|-----------------|
| `low` | Low-paying card symbols | 9, 10, J, Q, K, A |
| `mid` | Medium-paying symbols | Themed objects |
| `high` | High-paying premium symbols | Characters, artifacts |
| `premium` | Highest paying themed symbols | Main character |
| `wild` | Wild/substitute symbol | Joker, Logo |
| `scatter` | Scatter/trigger symbol | Star, Bonus |
| `bonus` | Bonus trigger symbol | Special symbol |
| `special` | Other special symbols | Multiplier, Collector |

### GddFeature

```dart
class GddFeature {
  final String id;
  final String name;
  final GddFeatureType type;  // freeSpins, bonus, holdAndSpin, cascade, etc.
  final String? triggerCondition;  // "3+ scatter"
  final int? initialSpins;
  final int? retriggerable;
  final List<String> stages;  // Associated audio stages
}
```

### GddMathModel

```dart
class GddMathModel {
  final double rtp;           // 0.0-1.0 (e.g., 0.96 = 96%)
  final String volatility;    // 'low', 'medium', 'high', 'very_high'
  final double hitFrequency;  // 0.0-1.0 (e.g., 0.25 = 25%)
  final List<GddWinTier> winTiers;
}
```

---

## PDF/Text Parsing

GDD Import service can parse both JSON and plain text (extracted from PDF).

### Text Parser Features

1. **Grid Detection:**
   - Patterns: `5x3`, `6x4`, `5 reels`, `3 rows`
   - Mechanic detection: `ways`, `cluster`, `megaways`, `paylines`

2. **Symbol Detection:**
   - Theme-specific keywords (Greek, Egyptian, Asian, Norse, Irish, etc.)
   - Paytable pattern: `SYMBOL_NAME: 5x=100, 4x=50, 3x=20`
   - Tier assignment based on payouts

3. **Feature Detection:**
   - Free Spins: `free spin`, `freespin`, `fs`
   - Hold & Win: `hold and win`, `hold & win`, `respins`
   - Cascade: `cascade`, `tumble`, `avalanche`
   - Jackpot: `jackpot`, `grand`, `major`, `minor`, `mini`

4. **Math Detection:**
   - RTP: `rtp: 96.5%`, `return to player: 96.5`
   - Volatility: `high volatility`, `medium variance`
   - Hit rate: `hit frequency: 25%`

### Theme-Specific Symbol Keywords

| Theme | Keywords |
|-------|----------|
| Greek | zeus, poseidon, hades, athena, apollo, hermes, medusa, pegasus, cerberus, olympus, trident, thunder, lightning |
| Egyptian | ra, anubis, horus, cleopatra, pharaoh, scarab, sphinx, pyramid, ankh, eye of ra |
| Asian | dragon, tiger, phoenix, koi, panda, fu, lu, shou, jade, lotus, pagoda |
| Norse | odin, thor, freya, loki, mjolnir, yggdrasil, valhalla, rune, viking |
| Irish/Celtic | leprechaun, shamrock, pot of gold, rainbow, clover, harp |
| Adventure | explorer, treasure, map, compass, ship, chest |
| Animal | lion, wolf, eagle, bear, buffalo, elephant |

---

## Usage

### 1. GDD Import Wizard

```dart
// Open GDD Import Wizard
final result = await GddImportWizard.show(context);
if (result != null) {
  // result.gdd — parsed GameDesignDocument
  // result.generatedStages — auto-generated stage names
  // result.generatedSymbols — converted SymbolDefinition list
}
```

### 2. Preview Dialog

```dart
// Show preview before applying
final confirmed = await GddPreviewDialog.show(context, result);
if (confirmed == true) {
  // Apply to slot mockup
}
```

### 3. Store in Provider

```dart
// Store GDD in provider (persists to project file)
final projectProvider = context.read<SlotLabProjectProvider>();
projectProvider.importGdd(result.gdd, generatedSymbols: result.generatedSymbols);

// Access later
final gdd = projectProvider.importedGdd;
final grid = projectProvider.gridConfig;
```

### 4. Project Persistence

GDD data is automatically saved when project is saved:

```json
{
  "name": "Wrath of Olympus",
  "version": "1.0",
  "symbols": [...],
  "gridConfig": {
    "rows": 3,
    "columns": 5,
    "mechanic": "ways",
    "ways": 243
  },
  "importedGdd": {
    "name": "Wrath of Olympus",
    "grid": {...},
    "math": {...},
    "symbols": [...],
    "features": [...]
  }
}
```

---

## Key Files

| File | LOC | Description |
|------|-----|-------------|
| `services/gdd_import_service.dart` | ~1500 | GDD parsing, toRustJson(), stage generation, symbol conversion |
| `widgets/slot_lab/gdd_import_wizard.dart` | ~780 | 4-step import wizard UI |
| `widgets/slot_lab/gdd_preview_dialog.dart` | ~450 | Visual preview dialog with slot mockup |
| `widgets/slot_lab/slot_preview_widget.dart` | ~1500 | SlotSymbol dynamic registry, reel rendering |
| `widgets/slot_lab/premium_slot_preview.dart` | ~4100 | _PaytablePanel with GDD symbols, fullscreen UI |
| `screens/slot_lab_screen.dart` | ~12000 | _populateSlotSymbolsFromGdd(), _showGddImportWizard() |
| `providers/slot_lab_project_provider.dart` | ~800 | GDD storage, gddSymbols getter |
| `models/slot_lab_models.dart` | ~1000 | SlotLabProject with gridConfig/importedGdd |

---

## V8 Changes (2026-01-25)

1. **GddPreviewDialog** — New visual preview showing slot mockup before applying
2. **Provider Storage** — Full GDD stored in `SlotLabProjectProvider._importedGdd`
3. **Grid Config Persistence** — `GddGridConfig` saved in project file
4. **PDF Text Parser** — Enhanced theme keyword detection (~90 symbols)
5. **Emoji Mapping** — Auto-assign emojis based on symbol name/theme
6. **Fullscreen Slot Preview on Apply** — When user clicks "Apply Configuration", fullscreen `PremiumSlotPreview` opens automatically with new grid dimensions

---

## V8.1: Fullscreen Preview on Apply (2026-01-25)

When user clicks "Apply Configuration" in GDD Preview Dialog:

1. Dialog closes (`Navigator.pop(true)`)
2. `slot_lab_screen.dart` receives `confirmed == true`
3. Grid settings applied to `_slotLabSettings`
4. **`_isPreviewMode = true`** — Opens fullscreen slot machine

```dart
// slot_lab_screen.dart:3047-3055
setState(() {
  _slotLabSettings = _slotLabSettings.copyWith(
    reels: newReels,
    rows: newRows,
    volatility: _volatilityFromGdd(result.gdd.math.volatility),
  );
  _isPreviewMode = true;  // Opens fullscreen slot machine
});
```

### Flow Diagram

```
GDD Preview Dialog
    ↓
[Apply Configuration] clicked
    ↓
Navigator.pop(true)
    ↓
slot_lab_screen._handleGddImport()
    ↓
confirmed == true
    ↓
├── projectProvider.importGdd(gdd)
├── _slotLabSettings.copyWith(reels, rows)
└── _isPreviewMode = true  ← FULLSCREEN OPENS
    ↓
PremiumSlotPreview (fullscreen)
├── key: ValueKey('fullscreen_slot_${reels}x${rows}')
├── New grid dimensions from GDD
└── Ready for audio testing
```

### ValueKey Force Rebuild

Widget uses `ValueKey` to force recreation when dimensions change:

```dart
// premium_slot_preview.dart
key: ValueKey('slot_preview_${reels}x$rows'),

// slot_lab_screen.dart (fullscreen mode)
key: ValueKey('fullscreen_slot_${_reelCount}x$_rowCount'),

// slot_lab_screen.dart (embedded mode)
key: ValueKey('premium_slot_${_reelCount}x$_rowCount'),
```

This ensures new grid is always displayed after GDD import.

---

## V9: Complete GDD→Slot Machine Integration (2026-01-26)

### New Features

1. **toRustJson() Conversion** — Dart GDD format converted to Rust-expected format
2. **Dynamic Slot Symbol Registry** — GDD symbols displayed on reels
3. **Paytable from GDD** — Pay values shown in info panel
4. **Symbol Weights** — Tier-based frequency distribution
5. **70+ Emoji Mappings** — Theme-based symbol visualization

### Dart → Rust JSON Conversion

```dart
// gdd_import_service.dart
Map<String, dynamic> toRustJson() {
  return {
    'game': { 'name': name, 'id': ..., 'volatility': ..., 'target_rtp': ... },
    'grid': { 'reels': columns, 'rows': rows, 'paylines': ... },
    'win_mechanism': 'paylines' | 'ways_243' | 'cluster' | 'megaways',
    'symbols': [
      { 'id': 0, 'name': 'Zeus', 'type': 'high_pay', 'pays': [0,0,20,50,100], 'tier': 4 },
      ...
    ],
    'features': [
      { 'type': 'free_spins', 'trigger': '3+ scatter', 'spins': 10 },
      ...
    ],
    'math': {
      'target_rtp': 0.965,
      'volatility': 'high',
      'symbol_weights': { 'Zeus': [5,5,5,5,5], 'Wild': [2,2,2,2,2], ... }
    }
  };
}
```

### Symbol Type Mapping

| Dart Tier | Rust Type | Weight |
|-----------|-----------|--------|
| `premium` | `high_pay` | 5 |
| `high` | `high_pay` | 8 |
| `mid` | `mid_pay` | 12 |
| `low` | `low_pay` | 18 |
| `wild` | `wild` | 2 |
| `scatter` | `scatter` | 3 |
| `bonus` | `bonus` | 3 |
| `special` | `regular` | 4 |

### Payout Array Format

GDD payouts `{3: 20, 4: 50, 5: 100}` → Rust pays `[0, 0, 0, 20, 50, 100]`
- Index = symbol count
- Value = payout multiplier

### Dynamic Slot Symbol Registry

```dart
// slot_preview_widget.dart
class SlotSymbol {
  static Map<int, SlotSymbol> _dynamicSymbols = {};

  static void setDynamicSymbols(Map<int, SlotSymbol> symbols);
  static void clearDynamicSymbols();
  static Map<int, SlotSymbol> get effectiveSymbols;
}

// slot_lab_screen.dart — called after GDD import
void _populateSlotSymbolsFromGdd(List<GddSymbol> gddSymbols) {
  // Convert GDD symbols to SlotSymbol format
  // Assign tier-based colors and emojis
  SlotSymbol.setDynamicSymbols(convertedSymbols);
}
```

### Paytable Panel Integration

```dart
// premium_slot_preview.dart
class _PaytablePanel extends StatelessWidget {
  final List<GddSymbol> gddSymbols;  // From SlotLabProjectProvider

  // Falls back to defaults when gddSymbols is empty
  List<_SymbolPayData> get _symbols =>
    gddSymbols.isEmpty ? _defaultSymbols : gddSymbols.map(_gddToPayData).toList();
}
```

### Theme-Based Emoji Mapping (70+ patterns)

| Theme | Keywords → Emoji |
|-------|------------------|
| Greek | zeus/thunder=⚡, poseidon/trident=🔱, athena/wisdom=🦉, medusa/snake=🐍 |
| Egyptian | ra/eye=👁️, anubis/jackal=🐺, horus/falcon=🦅, pharaoh/king=👑 |
| Asian | dragon=🐉, tiger=🐅, phoenix=🔥, koi/fish=🐟, panda=🐼 |
| Norse | odin=🧙, thor/hammer=🔨, freya/love=❤️, viking/ship=⛵ |
| Irish | leprechaun=🍀, shamrock/clover=☘️, rainbow=🌈 |
| Fruit | cherry=🍒, lemon=🍋, orange=🍊, grape=🍇, apple=🍎 |
| Cards | ace=🂡, king=🂮, queen=🂭, jack=🂫 |

### Tier Color Gradients

| Tier | Gradient Colors | Glow |
|------|-----------------|------|
| Premium | Gold (#FFD700 → #FFAA00 → #CC8800) | #FFD700 |
| High | Pink (#FF6699 → #FF4080 → #CC0044) | #FF4080 |
| Mid | Green (#88FF88 → #4CAF50 → #2E7D32) | #4CAF50 |
| Low | Blue (#9999FF → #7986CB → #3F51B5) | #7986CB |
| Wild | Gold (#FFE55C → #FFD700 → #CC9900) | #FFD700 |
| Scatter | Magenta (#FF66FF → #E040FB → #9C27B0) | #E040FB |
| Bonus | Cyan (#80EEFF → #40C8FF → #0088CC) | #40C8FF |

### Complete V9 Flow

```
GDD JSON Import
    ↓
GddImportWizard.show()
    ↓
GddPreviewDialog (user confirms)
    ↓
slot_lab_screen._showGddImportWizard()
    ↓
├── projectProvider.importGdd(gdd)           → Persist to project
├── _populateSlotSymbolsFromGdd(symbols)     → Update reel symbols
├── slotLabProvider.initEngineFromGdd(json)  → Rust engine init
└── setState(_isPreviewMode = true)          → Open fullscreen
    ↓
PremiumSlotPreview
├── Reels use SlotSymbol.effectiveSymbols    → GDD symbols on reels
├── _PaytablePanel uses gddSymbols           → Pay values from GDD
├── Grid uses gdd.grid.columns × rows        → Grid from GDD
└── Volatility from gdd.math.volatility      → Math from GDD
```

---

## Sample JSON GDD

```json
{
  "name": "Wrath of Olympus",
  "version": "1.0",
  "description": "Greek mythology themed slot",
  "grid": {
    "rows": 3,
    "columns": 5,
    "mechanic": "ways",
    "ways": 243
  },
  "math": {
    "rtp": 0.965,
    "volatility": "high",
    "hitFrequency": 0.28
  },
  "symbols": [
    {"id": "zeus", "name": "Zeus", "tier": "premium", "payouts": {"5": 100, "4": 50, "3": 20}},
    {"id": "wild", "name": "Wild", "tier": "wild", "isWild": true, "payouts": {"5": 200}},
    {"id": "scatter", "name": "Scatter", "tier": "scatter", "isScatter": true}
  ],
  "features": [
    {"id": "fs", "name": "Divine Free Spins", "type": "freeSpins", "triggerCondition": "3+ scatter", "initialSpins": 10}
  ]
}
```

---

## Related Documentation

- [SLOT_LAB_SYSTEM.md](SLOT_LAB_SYSTEM.md) — SlotLab architecture
- [DYNAMIC_SYMBOL_CONFIGURATION.md](DYNAMIC_SYMBOL_CONFIGURATION.md) — Symbol presets
- [EVENT_SYNC_SYSTEM.md](EVENT_SYNC_SYSTEM.md) — Stage→Event mapping

# Template Gallery System

**Status:** ✅ COMPLETE (2026-01-31)
**Task:** P3-12

---

## Overview

Template Gallery sistem omogućava brz početak SlotLab audio projekata korišćenjem predefinisanih template-a za različite tipove slot igara.

**Ključne karakteristike:**
- Templates su **čisti JSON** (bez audio fajlova)
- Koriste **generičke simbol identifikatore** (HP1, HP2, MP1, LP1, WILD, SCATTER, BONUS)
- **RTPC win system** sa korisnički konfigurisanim pragovima (tier1-tier6)
- Auto-wiring sistema: stages, events, buseva, ducking, ALE, RTPC

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     TEMPLATE GALLERY FLOW                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   JSON Template File (assets/templates/*.json)                   │
│           ↓                                                      │
│   SlotTemplate.fromJson() → SlotTemplate model                   │
│           ↓                                                      │
│   TemplateBuilderService.buildTemplate()                         │
│           ↓                                                      │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │           AUTO-CONFIGURATORS (Parallel)                  │   │
│   ├─────────────────────────────────────────────────────────┤   │
│   │ StageAutoRegistrar      → Registers stages              │   │
│   │ EventAutoRegistrar      → Creates placeholder events    │   │
│   │ BusAutoConfigurator     → Sets up audio busses          │   │
│   │ DuckingAutoConfigurator → Configures ducking rules      │   │
│   │ AleAutoConfigurator     → Sets up ALE contexts/layers   │   │
│   │ RtpcAutoConfigurator    → Configures win RTPC system    │   │
│   └─────────────────────────────────────────────────────────┘   │
│           ↓                                                      │
│   BuiltTemplate (runtime-ready)                                  │
│           ↓                                                      │
│   User assigns audio files to events                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
flutter_ui/
├── lib/
│   ├── models/
│   │   └── template_models.dart          # Core models (~650 LOC)
│   │
│   ├── services/
│   │   └── template/
│   │       ├── template_builder_service.dart    # Main builder (~380 LOC)
│   │       ├── template_validation_service.dart # Validation (~280 LOC)
│   │       ├── stage_auto_registrar.dart        # Stage registration (~220 LOC)
│   │       ├── event_auto_registrar.dart        # Event creation (~260 LOC)
│   │       ├── bus_auto_configurator.dart       # Bus setup (~180 LOC)
│   │       ├── ducking_auto_configurator.dart   # Ducking rules (~200 LOC)
│   │       ├── ale_auto_configurator.dart       # ALE contexts (~240 LOC)
│   │       └── rtpc_auto_configurator.dart      # RTPC win system (~220 LOC)
│   │
│   └── widgets/
│       └── template/
│           └── template_gallery_panel.dart      # UI panel (~780 LOC)
│
└── assets/
    └── templates/                         # 8 built-in templates
        ├── classic_5x3.json
        ├── ways_243.json
        ├── megaways_117649.json
        ├── cluster_pays.json
        ├── hold_and_win.json
        ├── cascading_reels.json
        ├── jackpot_network.json
        └── bonus_buy.json
```

**Total:** ~3,210 LOC (services + models + UI)

---

## Core Models

### SlotTemplate

```dart
class SlotTemplate {
  final String id;
  final String name;
  final String version;
  final TemplateCategory category;
  final String description;
  final String? author;
  final int reelCount;
  final int rowCount;
  final bool hasMegaways;

  final List<TemplateSymbol> symbols;
  final List<WinTierConfig> winTiers;
  final List<TemplateStageDefinition> coreStages;
  final List<FeatureModule> modules;
  final List<TemplateDuckingRule> duckingRules;
  final List<TemplateAleContext> aleContexts;
  final TemplateRtpcConfig? winMultiplierRtpc;
  final List<AudioMappingPattern> mappingPatterns;
  final Map<String, dynamic> metadata;
}
```

### TemplateCategory Enum

```dart
enum TemplateCategory {
  classic,    // Classic 3-reel or 5-reel payline slots
  video,      // Modern video slots with 243+ ways
  megaways,   // Dynamic reel slots (up to 117,649 ways)
  cluster,    // Cluster pays mechanics
  holdWin,    // Hold & Win / Lightning Link style
  jackpot,    // Progressive jackpot focused
  branded,    // Licensed/themed slots
  custom,     // User-created templates
}
```

### WinTierConfig

```dart
class WinTierConfig {
  final WinTier tier;           // tier1, tier2, tier3, tier4, tier5, tier6
  final String label;           // "Win", "Nice Win", "Big Win", etc.
  final double threshold;       // x bet multiplier (1.0, 5.0, 15.0, 30.0, 60.0, 100.0)
  final double volumeMultiplier;
  final double pitchOffset;
  final int rollupDurationMs;
  final bool hasScreenEffect;
}
```

### FeatureModule

```dart
class FeatureModule {
  final String id;
  final String name;
  final FeatureModuleType type;
  final String description;
  final List<TemplateStageDefinition> stages;
  final List<String> conflictsWith;
  final List<String> interactsWith;
  final Map<String, dynamic> defaultConfig;
}

enum FeatureModuleType {
  freeSpins,
  holdWin,
  cascade,
  jackpot,
  gamble,
  multiplier,
  mystery,
  buyBonus,
}
```

### BuiltTemplate

```dart
class BuiltTemplate {
  final SlotTemplate source;
  final String audioFolderPath;
  final Map<String, String> audioMappings;
  final DateTime builtAt;
  final List<String> warnings;
}
```

---

## Built-in Templates (8 Total)

| Template | Category | Grid | Key Features |
|----------|----------|------|--------------|
| **classic_5x3** | classic | 5×3 | 10 paylines, Free Spins with retrigger |
| **ways_243** | video | 5×3 | 243 ways, Free Spins with multiplier |
| **megaways_117649** | megaways | 6×7* | Cascade, Free Spins, unlimited multiplier |
| **cluster_pays** | cluster | 7×7 | Cluster wins, Cascade, Free Spins |
| **hold_and_win** | holdWin | 5×3 | Coins, Respins, 4-tier jackpots |
| **cascading_reels** | video | 5×4 | Tumble, escalating multipliers |
| **jackpot_network** | jackpot | 5×3 | Progressive jackpots, wheel bonus |
| **bonus_buy** | video | 5×4 | Feature buy, multiplier wilds |

*Megaways: variable rows 2-7 per reel

---

## Template JSON Structure

```json
{
  "id": "classic_5x3",
  "name": "Classic 5x3",
  "version": "1.0.0",
  "category": "classic",
  "description": "Traditional 5-reel, 3-row slot with paylines",
  "author": "FluxForge Studio",
  "reelCount": 5,
  "rowCount": 3,
  "hasMegaways": false,

  "symbols": [
    {"id": "HP1", "type": "highPay", "tier": 1, "audioContexts": ["land", "win"]},
    {"id": "WILD", "type": "wild", "tier": 0, "audioContexts": ["land", "win", "expand"]},
    {"id": "SCATTER", "type": "scatter", "tier": 0, "audioContexts": ["land", "win", "trigger"]}
  ],

  "winTiers": [
    {"tier": "tier1", "label": "Win", "threshold": 1.0, "volumeMultiplier": 0.75, ...},
    {"tier": "tier3", "label": "Big Win", "threshold": 15.0, "volumeMultiplier": 0.95, ...}
  ],

  "coreStages": [
    {"id": "SPIN_START", "name": "Spin Start", "category": "spin", "priority": 80, ...},
    {"id": "REEL_STOP_0", "name": "Reel 0 Stop", "category": "spin", "priority": 75, ...}
  ],

  "modules": [
    {
      "id": "free_spins",
      "type": "freeSpins",
      "stages": [...],
      "defaultConfig": {"spins": 10}
    }
  ],

  "duckingRules": [
    {"sourceBus": "sfx", "targetBus": "music", "duckAmountDb": -6.0, ...}
  ],

  "aleContexts": [
    {
      "id": "base_game",
      "layers": [
        {"index": 0, "assetPattern": "base_L1_*", "baseVolume": 0.7}
      ],
      "entryStages": ["SPIN_END"],
      "exitStages": ["FS_ENTER"]
    }
  ],

  "winMultiplierRtpc": {
    "name": "winMultiplier",
    "min": 0.0,
    "max": 100.0,
    "volumeCurve": [{"x": 0.0, "y": 0.75}, {"x": 1.0, "y": 1.0}],
    "pitchCurve": [{"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 2.0}]
  }
}
```

---

## Auto-Configurators

### 1. StageAutoRegistrar

Registruje sve stage-ove iz template-a u `StageConfigurationService`.

**Input:** `SlotTemplate.coreStages` + `modules[].stages`
**Output:** Registered stages sa priority, bus, pooled, looping flags

### 2. EventAutoRegistrar

Kreira placeholder evente za svaki stage.

**Input:** Registered stages
**Output:** `SlotCompositeEvent` sa praznim layers (čeka audio assignment)

### 3. BusAutoConfigurator

Postavlja audio bus hijerarhiju.

**Default Buses:**
- Master (0)
- Music (1)
- SFX (2)
- Voice (3)
- Ambience (4)
- Wins (5)
- UI (6)

### 4. DuckingAutoConfigurator

Konfigurišу ducking rules.

**Input:** `SlotTemplate.duckingRules`
**Output:** `DuckingRule` entries u `MiddlewareProvider`

### 5. AleAutoConfigurator

Postavlja Adaptive Layer Engine kontekste.

**Input:** `SlotTemplate.aleContexts`
**Output:** ALE contexts sa entry/exit stages i layer patterns

### 6. RtpcAutoConfigurator

Konfigurišе win RTPC sistem za dinamičnu audio modulaciju.

**Input:** `SlotTemplate.winTiers` + `winMultiplierRtpc`
**Output:** RTPC bindings za volume/pitch based on win multiplier

---

## Template Gallery UI

```
┌─────────────────────────────────────────────────────────────────┐
│  TEMPLATE GALLERY                                    [Search 🔍]│
├─────────────────────────────────────────────────────────────────┤
│  [All] [Classic] [Video] [Megaways] [Cluster] [Hold] [Jackpot] │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   CLASSIC    │  │  WAYS 243    │  │  MEGAWAYS    │          │
│  │     5×3      │  │   5×3 243    │  │  117,649     │          │
│  │              │  │              │  │              │          │
│  │ ⭐⭐⭐☆☆   │  │ ⭐⭐⭐⭐☆   │  │ ⭐⭐⭐⭐⭐   │          │
│  │  [Use]       │  │  [Use]       │  │  [Use]       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   CLUSTER    │  │ HOLD & WIN   │  │  CASCADING   │          │
│  │   7×7        │  │  5×3 Coins   │  │   5×4        │          │
│  │              │  │              │  │              │          │
│  │ ⭐⭐⭐⭐☆   │  │ ⭐⭐⭐⭐⭐   │  │ ⭐⭐⭐⭐☆   │          │
│  │  [Use]       │  │  [Use]       │  │  [Use]       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │   JACKPOT    │  │  BONUS BUY   │                             │
│  │  Progressive │  │   Feature    │                             │
│  │              │  │              │                             │
│  │ ⭐⭐⭐⭐⭐   │  │ ⭐⭐⭐⭐⭐   │                             │
│  │  [Use]       │  │  [Use]       │                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- Category filtering
- Search by name/description
- Template preview with grid visualization
- One-click template application
- Custom template import

---

## Usage Flow

### 1. Select Template
```dart
// In TemplateGalleryPanel
final template = await _loadTemplate('hold_and_win');
```

### 2. Build Template
```dart
final buildResult = await TemplateBuilderService.instance.buildTemplate(
  template: template,
  audioFolderPath: '/path/to/audio',
);
```

### 3. Auto-Wire Systems
```dart
// Automatic via buildTemplate():
// - Stages registered
// - Events created (placeholder)
// - Buses configured
// - Ducking rules applied
// - ALE contexts set up
// - RTPC bindings created
```

### 4. Assign Audio Files
```dart
// User drops audio files onto events in Events Panel
// Or uses batch import with matching patterns
```

### 5. Test & Export
```dart
// Preview in SlotLab
// Export to Unity/Unreal/Howler.js
```

---

## Validation

`TemplateValidationService` validates:

1. **Required Fields:** id, name, category
2. **Symbol Uniqueness:** No duplicate symbol IDs
3. **Win Tier Order:** Thresholds must be increasing
4. **Stage References:** All referenced stages exist
5. **Module Conflicts:** Check `conflictsWith` declarations
6. **RTPC Curves:** Validate curve points (0.0-1.0 x range)

---

## Creating Custom Templates

1. Copy existing template JSON as base
2. Modify grid, symbols, features
3. Add custom stages for unique mechanics
4. Configure win tiers for desired volatility
5. Set up ALE contexts for adaptive music
6. Save to `assets/templates/` or user directory
7. Template appears in gallery with `custom` category

---

## Integration Points

| System | Integration |
|--------|-------------|
| **EventRegistry** | Events registered via `EventAutoRegistrar` |
| **StageConfigurationService** | Stages registered via `StageAutoRegistrar` |
| **MiddlewareProvider** | Ducking rules, RTPC bindings |
| **AleProvider** | Contexts, layers, signals |
| **SlotLabProjectProvider** | Symbol definitions, audio assignments |
| **BusHierarchyProvider** | Bus setup |

---

## Future Enhancements

- [ ] Template versioning/updates
- [ ] Cloud template sharing
- [ ] Template marketplace
- [ ] AI-assisted template generation
- [ ] Template diff/merge tools

---

*Last updated: 2026-01-31*

# P3-12: Template Gallery — Ultimativna Specifikacija

**Status:** IN PROGRESS
**Verzija:** 2.1.0
**Datum:** 2026-01-31

---

## 1. Koncept

Template = **čista JSON konfiguracija** bez audio fajlova.

- User importuje svoj audio folder
- Template daje strukturu: stages, events, routing, RTPC, ALE
- Tematski agnostičan — generic identifiers (HP1, MP1, WILD, TIER_1...)
- Zero hardcoding — sve user-configurable

---

## 2. Template Hijerarhija

```
┌─────────────────────────────────────────────────────────────┐
│  LEVEL 1: SlotTemplate                                      │
│  - Grid config, symbols, features, stages                   │
├─────────────────────────────────────────────────────────────┤
│  LEVEL 2: EventTemplate                                     │
│  - Stage→Event mappings, priorities, bus routing            │
├─────────────────────────────────────────────────────────────┤
│  LEVEL 3: MixTemplate                                       │
│  - Bus hierarchy, ducking rules, DSP chains                 │
├─────────────────────────────────────────────────────────────┤
│  LEVEL 4: ALETemplate                                       │
│  - Contexts, rules, transitions, stability                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Symbol System (Generički)

### 3.1 Symbol Identifiers

| Tier | ID Format | Opis |
|------|-----------|------|
| Premium | HP1, HP2, HP3, HP4, HP5, HP6 | High Pay symbols |
| Medium | MP1, MP2, MP3 | Mid Pay symbols |
| Low | LP1, LP2, LP3, LP4 | Low Pay symbols |
| Special | WILD | Wild symbol |
| Special | SCATTER | Scatter symbol |
| Special | BONUS | Bonus trigger symbol |
| Special | COIN | Collect/coin (Hold & Win) |
| Special | MYSTERY | Mystery/transform symbol |
| Special | MULTIPLIER | Multiplier symbol |
| Special | JACKPOT_MINI | Jackpot coin - Mini |
| Special | JACKPOT_MINOR | Jackpot coin - Minor |
| Special | JACKPOT_MAJOR | Jackpot coin - Major |
| Special | JACKPOT_GRAND | Jackpot coin - Grand |

### 3.2 Symbol Contexts (Audio Triggers)

| Context | Stage Format | Opis |
|---------|--------------|------|
| land | SYMBOL_LAND_{ID} | Symbol lands on reel |
| win | WIN_SYMBOL_HIGHLIGHT_{ID} | Symbol part of win |
| expand | SYMBOL_EXPAND_{ID} | Symbol expands |
| lock | SYMBOL_LOCK_{ID} | Symbol locks (Hold & Win) |
| transform | SYMBOL_TRANSFORM_{ID} | Symbol transforms |
| collect | SYMBOL_COLLECT_{ID} | Symbol collected |

### 3.3 Symbol Config Schema

```json
{
  "symbols": [
    {
      "id": "HP1",
      "type": "highPay",
      "tier": 1,
      "contexts": ["land", "win"]
    },
    {
      "id": "WILD",
      "type": "wild",
      "tier": 0,
      "contexts": ["land", "win", "expand", "substitute"]
    },
    {
      "id": "SCATTER",
      "type": "scatter",
      "tier": 0,
      "contexts": ["land", "collect", "trigger"]
    }
  ]
}
```

---

## 4. Win System (Full RTPC)

### 4.1 Filozofija

- **RTPC kontinualna modulacija** za smooth audio response
- **Discrete stages** za trigger specifičnih zvukova
- **User-defined thresholds** — potpuna kontrola
- **Zero hardcoding** — sve iz konfiga

### 4.2 RTPC Parameter

```
RTPC: winMultiplier
Source: winAmount / betAmount
Range: 0.0 → ∞
```

### 4.3 Win Levels (Discrete Stages)

| ID | Default Threshold | Opis |
|----|-------------------|------|
| WIN_LEVEL_1 | 1.0x | Minimum win (= bet) |
| WIN_LEVEL_2 | 2.5x | User configurable |
| WIN_LEVEL_3 | 5.0x | User configurable |
| WIN_LEVEL_4 | 10.0x | User configurable |
| WIN_LEVEL_5 | 15.0x | User configurable |

**Note:** User može dodati više nivoa ili ukloniti postojeće.

### 4.4 Big Win Tiers (Celebration System)

| ID | Default Threshold | Opis |
|----|-------------------|------|
| TIER_1 | 20.0x | First big win tier |
| TIER_2 | 35.0x | Second tier |
| TIER_3 | 50.0x | Third tier |
| TIER_4 | 75.0x | Fourth tier |
| TIER_5 | 100.0x | Highest tier |

**Note:** Threshold za prelaz u Big Win sistem je takođe user-configurable (default: 20.0x).

### 4.5 Big Win Stages

| Stage | Opis |
|-------|------|
| BIG_WIN_TIER_{N}_START | Početak tier N celebration |
| BIG_WIN_TIER_{N}_LOOP | Loop tokom countdown/rollup |
| BIG_WIN_TIER_{N}_END | Kraj celebration |
| ROLLUP_TIER_{N}_TICK | Rollup tick sound |
| ROLLUP_TIER_{N}_END | Rollup završen |

### 4.6 Tier Labels (User-Defined)

```json
{
  "tierLabels": {
    "TIER_1": "",
    "TIER_2": "",
    "TIER_3": "",
    "TIER_4": "",
    "TIER_5": ""
  }
}
```

User popunjava sa svojim imenima:
- "BIG WIN", "SUPER WIN", "MEGA WIN", "EPIC WIN", "ULTRA WIN"
- "GRANDE", "ENORME", "MASSIVO", "COLOSSALE", "LEGGENDARIO"
- Bilo koja custom imena

### 4.7 RTPC Curves

```json
{
  "rtpcCurves": {
    "volume": {
      "type": "logarithmic",
      "points": [
        {"rtpc": 0.0, "value": 0.5},
        {"rtpc": 1.0, "value": 0.8},
        {"rtpc": 5.0, "value": 1.0},
        {"rtpc": 20.0, "value": 1.2}
      ]
    },
    "pitch": {
      "type": "linear",
      "points": [
        {"rtpc": 0.0, "value": -0.05},
        {"rtpc": 1.0, "value": 0.0},
        {"rtpc": 10.0, "value": 0.10}
      ]
    },
    "rollupSpeed": {
      "type": "exponential",
      "points": [
        {"rtpc": 1.0, "value": 1.0},
        {"rtpc": 10.0, "value": 1.5},
        {"rtpc": 50.0, "value": 2.5},
        {"rtpc": 100.0, "value": 4.0}
      ]
    }
  }
}
```

### 4.8 Full Win Config Schema

```json
{
  "winConfig": {
    "rtpc": {
      "parameter": "winMultiplier",
      "source": "winAmount / betAmount",
      "curves": {
        "volume": {
          "type": "logarithmic",
          "points": [
            {"rtpc": 0.0, "value": 0.5},
            {"rtpc": 1.0, "value": 0.8},
            {"rtpc": 5.0, "value": 1.0},
            {"rtpc": 20.0, "value": 1.2}
          ]
        },
        "pitch": {
          "type": "linear",
          "points": [
            {"rtpc": 0.0, "value": -0.05},
            {"rtpc": 1.0, "value": 0.0},
            {"rtpc": 10.0, "value": 0.10}
          ]
        }
      }
    },

    "levels": [
      {"id": "WIN_LEVEL_1", "threshold": 1.0, "removable": false},
      {"id": "WIN_LEVEL_2", "threshold": 2.5, "removable": true},
      {"id": "WIN_LEVEL_3", "threshold": 5.0, "removable": true},
      {"id": "WIN_LEVEL_4", "threshold": 10.0, "removable": true},
      {"id": "WIN_LEVEL_5", "threshold": 15.0, "removable": true}
    ],

    "bigWin": {
      "threshold": 20.0,
      "tiers": [
        {"id": "TIER_1", "threshold": 20.0, "label": ""},
        {"id": "TIER_2", "threshold": 35.0, "label": ""},
        {"id": "TIER_3", "threshold": 50.0, "label": ""},
        {"id": "TIER_4", "threshold": 75.0, "label": ""},
        {"id": "TIER_5", "threshold": 100.0, "label": ""}
      ],
      "tierColors": {
        "TIER_1": "",
        "TIER_2": "",
        "TIER_3": "",
        "TIER_4": "",
        "TIER_5": ""
      },
      "tierDurations": {
        "TIER_1": 3000,
        "TIER_2": 5000,
        "TIER_3": 8000,
        "TIER_4": 12000,
        "TIER_5": 20000
      }
    }
  }
}
```

### 4.9 Runtime Logic

```dart
void onWin(double winAmount, double betAmount) {
  final multiplier = betAmount > 0 ? winAmount / betAmount : 0;

  // 1. UVEK update RTPC (kontinualno)
  rtpcProvider.setValue('winMultiplier', multiplier);

  // 2. Check za Big Win
  if (multiplier >= config.bigWin.threshold) {
    final tier = _getBigWinTier(multiplier);
    eventRegistry.triggerStage('BIG_WIN_${tier}_START');
    _startBigWinCelebration(tier, multiplier);
    return;
  }

  // 3. Check za discrete WIN_LEVEL
  final level = _getWinLevel(multiplier);
  if (level != null) {
    eventRegistry.triggerStage(level);
  }

  // 4. RTPC modulira audio čak i bez discrete stage
}

String? _getWinLevel(double multiplier) {
  for (int i = config.levels.length - 1; i >= 0; i--) {
    if (multiplier >= config.levels[i].threshold) {
      return config.levels[i].id;
    }
  }
  return null;  // multiplier < 1.0, samo RTPC radi
}

String _getBigWinTier(double multiplier) {
  for (int i = config.bigWin.tiers.length - 1; i >= 0; i--) {
    if (multiplier >= config.bigWin.tiers[i].threshold) {
      return config.bigWin.tiers[i].id;
    }
  }
  return 'TIER_1';
}
```

---

## 5. Built-in Templates

### 5.1 Template Lista

| # | Template | Grid | Mehanika | Symbols | Events | Optional Modules |
|---|----------|------|----------|---------|--------|------------------|
| 1 | Classic 3-Reel | 3×3 | Lines (5) | HP1-2, MP1, LP1-2, WILD, SCATTER* | ~55 base | Respin (+7), Free Spins (+19) |
| 2 | Standard 5×3 Video | 5×3 | Lines (20) | HP1-4, MP1-3, LP1-4, WILD, SCATTER | ~125 base | Hold & Win (+31), Hold & Respin (+16) |
| 3 | Megaways | 6×2-7 | Ways | HP1-6, LP1-4, WILD, SCATTER, MYSTERY | ~185 | — |
| 4 | Hold & Win | 5×3 | Lines (20) | HP1-4, MP1-3, LP1-4, WILD, SCATTER, COIN, JACKPOT_* | ~155 | — |
| 5 | Cascade/Tumble | 5×5 | Cluster | HP1-4, MP1-2, LP1-4, WILD, SCATTER, MULTIPLIER | ~145 | — |
| 6 | Cluster Pays | 7×7 | Cluster (5+) | HP1-4, MP1-2, LP1-4, WILD, SCATTER | ~130 | — |
| 7 | Jackpot Progressive | 5×3 | Lines (25) | HP1-4, MP1-3, LP1-4, WILD, SCATTER, JACKPOT | ~105 | — |
| 8 | Bonus Wheel | 5×3 | Lines (20) | HP1-4, MP1-3, LP1-4, WILD, SCATTER, BONUS | ~115 | — |

*SCATTER is optional for Classic 3-Reel (required only if Free Spins module is enabled)

### 5.1.1 Optional Modules Concept

Templates mogu imati **opcione module** koje user uključuje/isključuje.

**Prednosti:**
- Bazni template ostaje jednostavan
- User bira samo feature-e koje treba
- Manje nepotrebnih stage-ova

**UI u Apply Wizard (Step 0):**
```
┌─────────────────────────────────────────────────────────────────┐
│  Classic 3-Reel — Optional Features                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [✓] Respin Feature                                             │
│      Adds 7 stages for respin mechanic                          │
│      Trigger: 2 matching symbols                                │
│                                                                 │
│  [✓] Free Spins Feature                                         │
│      Adds 19 stages for free spins + SCATTER symbol             │
│      Trigger: 3 SCATTER symbols                                 │
│                                                                 │
│  Selected: Base (55) + Respin (7) + Free Spins (19) = 81 stages │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Template: Classic 3-Reel

```json
{
  "$schema": "https://fluxforge.studio/schemas/slot-template-v1.json",
  "type": "slot",
  "version": "1.0.0",

  "meta": {
    "id": "classic-3reel",
    "name": "Classic 3-Reel",
    "description": "Traditional 3-reel slot with classic symbols",
    "author": "FluxForge",
    "tags": ["classic", "3-reel", "simple"],
    "estimatedSetupTime": "3 min",
    "eventCount": 50
  },

  "grid": {
    "reels": 3,
    "rows": 3,
    "mechanic": "lines",
    "paylines": 5
  },

  "symbols": [
    {"id": "HP1", "type": "highPay", "tier": 1, "contexts": ["land", "win"]},
    {"id": "HP2", "type": "highPay", "tier": 2, "contexts": ["land", "win"]},
    {"id": "MP1", "type": "midPay", "tier": 3, "contexts": ["land", "win"]},
    {"id": "LP1", "type": "lowPay", "tier": 4, "contexts": ["land", "win"]},
    {"id": "LP2", "type": "lowPay", "tier": 5, "contexts": ["land", "win"]},
    {"id": "WILD", "type": "wild", "tier": 0, "contexts": ["land", "win"]},
    {"id": "SCATTER", "type": "scatter", "tier": 0, "contexts": ["land", "collect", "trigger"], "optional": true}
  ],

  "features": {
    "wilds": {"enabled": true, "expanding": false, "sticky": false},
    "respin": {"enabled": true, "optional": true},
    "freeSpins": {"enabled": true, "optional": true, "triggerCount": 3, "baseSpins": 10}
  },

  "optionalModules": {
    "respin": {
      "description": "Respin feature - triggered when 2 matching symbols appear",
      "stages": [
        "RESPIN_TRIGGER",
        "RESPIN_START",
        "REEL_RESPIN_SPINNING",
        "REEL_RESPIN_STOP",
        "RESPIN_WIN",
        "RESPIN_NO_WIN",
        "RESPIN_END"
      ]
    },
    "freeSpins": {
      "description": "Free Spins feature - triggered by 3 Scatters",
      "stages": [
        "FS_TRIGGER",
        "FS_INTRO",
        "FS_COUNTER_SHOW",
        "FS_MUSIC_START",
        "FS_SPIN_START",
        "FS_SPIN_END",
        "FS_REEL_STOP_0",
        "FS_REEL_STOP_1",
        "FS_REEL_STOP_2",
        "FS_COUNTER_DECREMENT",
        "FS_RETRIGGER",
        "FS_RETRIGGER_COUNT",
        "FS_MULTIPLIER_INCREASE",
        "FS_MUSIC_TENSION",
        "FS_LAST_SPIN",
        "FS_OUTRO",
        "FS_TOTAL_WIN",
        "FS_MUSIC_END",
        "FS_EXIT"
      ]
    }
  },

  "stages": {
    "spin": [
      "SPIN_START",
      "SPIN_END",
      "REEL_SPINNING"
    ],
    "reelStop": [
      "REEL_STOP_0",
      "REEL_STOP_1",
      "REEL_STOP_2"
    ],
    "symbols": [
      "SYMBOL_LAND_HP1",
      "SYMBOL_LAND_HP2",
      "SYMBOL_LAND_MP1",
      "SYMBOL_LAND_LP1",
      "SYMBOL_LAND_LP2",
      "SYMBOL_LAND_WILD",
      "SYMBOL_LAND_SCATTER",
      "WIN_SYMBOL_HIGHLIGHT_HP1",
      "WIN_SYMBOL_HIGHLIGHT_HP2",
      "WIN_SYMBOL_HIGHLIGHT_MP1",
      "WIN_SYMBOL_HIGHLIGHT_LP1",
      "WIN_SYMBOL_HIGHLIGHT_LP2",
      "WIN_SYMBOL_HIGHLIGHT_WILD"
    ],
    "wins": [
      "WIN_LEVEL_1",
      "WIN_LEVEL_2",
      "WIN_LEVEL_3",
      "WIN_LEVEL_4",
      "WIN_LEVEL_5",
      "BIG_WIN_TIER_1_START",
      "BIG_WIN_TIER_1_LOOP",
      "BIG_WIN_TIER_1_END",
      "BIG_WIN_TIER_2_START",
      "BIG_WIN_TIER_2_LOOP",
      "BIG_WIN_TIER_2_END",
      "BIG_WIN_TIER_3_START",
      "BIG_WIN_TIER_3_LOOP",
      "BIG_WIN_TIER_3_END",
      "BIG_WIN_TIER_4_START",
      "BIG_WIN_TIER_4_LOOP",
      "BIG_WIN_TIER_4_END",
      "BIG_WIN_TIER_5_START",
      "BIG_WIN_TIER_5_LOOP",
      "BIG_WIN_TIER_5_END"
    ],
    "rollup": [
      "ROLLUP_TIER_1_TICK",
      "ROLLUP_TIER_1_END",
      "ROLLUP_TIER_2_TICK",
      "ROLLUP_TIER_2_END",
      "ROLLUP_TIER_3_TICK",
      "ROLLUP_TIER_3_END",
      "ROLLUP_TIER_4_TICK",
      "ROLLUP_TIER_4_END",
      "ROLLUP_TIER_5_TICK",
      "ROLLUP_TIER_5_END"
    ],
    "music": [
      "MUSIC_BASE",
      "MUSIC_WIN",
      "MUSIC_FS"
    ]
  }
}
```

### 5.3 Template: Standard 5×3 Video

```json
{
  "$schema": "https://fluxforge.studio/schemas/slot-template-v1.json",
  "type": "slot",
  "version": "1.0.0",

  "meta": {
    "id": "standard-5x3-video",
    "name": "Standard 5×3 Video Slot",
    "description": "Industry-standard video slot with Free Spins and optional Hold & Win",
    "author": "FluxForge",
    "tags": ["video", "5x3", "freespins", "wilds", "scatters", "hold-and-win-optional"],
    "estimatedSetupTime": "8 min",
    "eventCount": 125,
    "eventCountWithOptional": 190
  },

  "optionalModules": {
    "holdAndWin": {
      "description": "Hold & Win bonus feature with coin symbols and jackpots",
      "additionalSymbols": [
        {"id": "COIN", "type": "coin", "tier": 0, "contexts": ["land", "lock", "collect"]},
        {"id": "JACKPOT_MINI", "type": "jackpot", "tier": 0, "contexts": ["land", "lock"]},
        {"id": "JACKPOT_MINOR", "type": "jackpot", "tier": 0, "contexts": ["land", "lock"]},
        {"id": "JACKPOT_MAJOR", "type": "jackpot", "tier": 0, "contexts": ["land", "lock"]},
        {"id": "JACKPOT_GRAND", "type": "jackpot", "tier": 0, "contexts": ["land", "lock"]}
      ],
      "stages": [
        "HOLD_TRIGGER",
        "HOLD_INTRO",
        "HOLD_GRID_SETUP",
        "HOLD_COINS_LOCK",
        "HOLD_RESPINS_START",
        "HOLD_RESPIN_COUNT",
        "HOLD_SPIN_START",
        "HOLD_SPIN_END",
        "HOLD_REEL_STOP_0",
        "HOLD_REEL_STOP_1",
        "HOLD_REEL_STOP_2",
        "HOLD_REEL_STOP_3",
        "HOLD_REEL_STOP_4",
        "HOLD_COIN_LAND",
        "HOLD_COIN_LOCK",
        "HOLD_RESPINS_RESET",
        "HOLD_NO_COIN",
        "HOLD_JACKPOT_MINI",
        "HOLD_JACKPOT_MINOR",
        "HOLD_JACKPOT_MAJOR",
        "HOLD_JACKPOT_GRAND",
        "HOLD_GRID_FULL",
        "HOLD_WIN_EVAL",
        "HOLD_COIN_COLLECT",
        "HOLD_TOTAL_WIN",
        "HOLD_OUTRO",
        "HOLD_EXIT",
        "SYMBOL_LAND_COIN",
        "SYMBOL_LOCK_COIN",
        "SYMBOL_COLLECT_COIN",
        "MUSIC_HOLD"
      ]
    },
    "holdAndRespin": {
      "description": "Simplified Hold & Respin feature (no jackpots, just respins)",
      "stages": [
        "RESPIN_TRIGGER",
        "RESPIN_INTRO",
        "RESPIN_SYMBOLS_LOCK",
        "RESPIN_START",
        "RESPIN_REEL_SPINNING",
        "RESPIN_REEL_STOP_0",
        "RESPIN_REEL_STOP_1",
        "RESPIN_REEL_STOP_2",
        "RESPIN_REEL_STOP_3",
        "RESPIN_REEL_STOP_4",
        "RESPIN_NEW_SYMBOL_LOCK",
        "RESPIN_NO_NEW_SYMBOL",
        "RESPIN_WIN",
        "RESPIN_NO_WIN",
        "RESPIN_OUTRO",
        "RESPIN_EXIT"
      ]
    }
  },

  "grid": {
    "reels": 5,
    "rows": 3,
    "mechanic": "lines",
    "paylines": 20
  },

  "symbols": [
    {"id": "HP1", "type": "highPay", "tier": 1, "contexts": ["land", "win"]},
    {"id": "HP2", "type": "highPay", "tier": 2, "contexts": ["land", "win"]},
    {"id": "HP3", "type": "highPay", "tier": 3, "contexts": ["land", "win"]},
    {"id": "HP4", "type": "highPay", "tier": 4, "contexts": ["land", "win"]},
    {"id": "MP1", "type": "midPay", "tier": 5, "contexts": ["land", "win"]},
    {"id": "MP2", "type": "midPay", "tier": 6, "contexts": ["land", "win"]},
    {"id": "MP3", "type": "midPay", "tier": 7, "contexts": ["land", "win"]},
    {"id": "LP1", "type": "lowPay", "tier": 8, "contexts": ["land", "win"]},
    {"id": "LP2", "type": "lowPay", "tier": 9, "contexts": ["land", "win"]},
    {"id": "LP3", "type": "lowPay", "tier": 10, "contexts": ["land", "win"]},
    {"id": "LP4", "type": "lowPay", "tier": 11, "contexts": ["land", "win"]},
    {"id": "WILD", "type": "wild", "tier": 0, "contexts": ["land", "win", "expand"]},
    {"id": "SCATTER", "type": "scatter", "tier": 0, "contexts": ["land", "collect", "trigger"]}
  ],

  "features": {
    "freeSpins": {
      "enabled": true,
      "triggerCount": 3,
      "baseSpins": 10,
      "retrigger": true
    },
    "wilds": {
      "enabled": true,
      "expanding": false,
      "sticky": false
    },
    "scatters": {
      "enabled": true,
      "payAnywhere": true
    }
  },

  "stages": {
    "spin": [
      "SPIN_START",
      "SPIN_END",
      "REEL_SPINNING"
    ],
    "reelStop": [
      "REEL_STOP_0",
      "REEL_STOP_1",
      "REEL_STOP_2",
      "REEL_STOP_3",
      "REEL_STOP_4"
    ],
    "anticipation": [
      "ANTICIPATION_ON",
      "ANTICIPATION_OFF",
      "ANTICIPATION_TENSION_R0_L1",
      "ANTICIPATION_TENSION_R0_L2",
      "ANTICIPATION_TENSION_R0_L3",
      "ANTICIPATION_TENSION_R0_L4",
      "ANTICIPATION_TENSION_R1_L1",
      "ANTICIPATION_TENSION_R1_L2",
      "ANTICIPATION_TENSION_R1_L3",
      "ANTICIPATION_TENSION_R1_L4",
      "ANTICIPATION_TENSION_R2_L1",
      "ANTICIPATION_TENSION_R2_L2",
      "ANTICIPATION_TENSION_R2_L3",
      "ANTICIPATION_TENSION_R2_L4",
      "ANTICIPATION_TENSION_R3_L1",
      "ANTICIPATION_TENSION_R3_L2",
      "ANTICIPATION_TENSION_R3_L3",
      "ANTICIPATION_TENSION_R3_L4",
      "ANTICIPATION_TENSION_R4_L1",
      "ANTICIPATION_TENSION_R4_L2",
      "ANTICIPATION_TENSION_R4_L3",
      "ANTICIPATION_TENSION_R4_L4"
    ],
    "symbols": [
      "SYMBOL_LAND_HP1",
      "SYMBOL_LAND_HP2",
      "SYMBOL_LAND_HP3",
      "SYMBOL_LAND_HP4",
      "SYMBOL_LAND_MP1",
      "SYMBOL_LAND_MP2",
      "SYMBOL_LAND_MP3",
      "SYMBOL_LAND_LP1",
      "SYMBOL_LAND_LP2",
      "SYMBOL_LAND_LP3",
      "SYMBOL_LAND_LP4",
      "SYMBOL_LAND_WILD",
      "SYMBOL_LAND_SCATTER"
    ],
    "winHighlight": [
      "WIN_SYMBOL_HIGHLIGHT_HP1",
      "WIN_SYMBOL_HIGHLIGHT_HP2",
      "WIN_SYMBOL_HIGHLIGHT_HP3",
      "WIN_SYMBOL_HIGHLIGHT_HP4",
      "WIN_SYMBOL_HIGHLIGHT_MP1",
      "WIN_SYMBOL_HIGHLIGHT_MP2",
      "WIN_SYMBOL_HIGHLIGHT_MP3",
      "WIN_SYMBOL_HIGHLIGHT_LP1",
      "WIN_SYMBOL_HIGHLIGHT_LP2",
      "WIN_SYMBOL_HIGHLIGHT_LP3",
      "WIN_SYMBOL_HIGHLIGHT_LP4",
      "WIN_SYMBOL_HIGHLIGHT_WILD"
    ],
    "winLine": [
      "WIN_LINE_SHOW",
      "WIN_LINE_HIDE"
    ],
    "wins": [
      "WIN_LEVEL_1",
      "WIN_LEVEL_2",
      "WIN_LEVEL_3",
      "WIN_LEVEL_4",
      "WIN_LEVEL_5"
    ],
    "bigWin": [
      "BIG_WIN_TIER_1_START",
      "BIG_WIN_TIER_1_LOOP",
      "BIG_WIN_TIER_1_END",
      "BIG_WIN_TIER_2_START",
      "BIG_WIN_TIER_2_LOOP",
      "BIG_WIN_TIER_2_END",
      "BIG_WIN_TIER_3_START",
      "BIG_WIN_TIER_3_LOOP",
      "BIG_WIN_TIER_3_END",
      "BIG_WIN_TIER_4_START",
      "BIG_WIN_TIER_4_LOOP",
      "BIG_WIN_TIER_4_END",
      "BIG_WIN_TIER_5_START",
      "BIG_WIN_TIER_5_LOOP",
      "BIG_WIN_TIER_5_END"
    ],
    "rollup": [
      "ROLLUP_TIER_1_TICK",
      "ROLLUP_TIER_1_END",
      "ROLLUP_TIER_2_TICK",
      "ROLLUP_TIER_2_END",
      "ROLLUP_TIER_3_TICK",
      "ROLLUP_TIER_3_END",
      "ROLLUP_TIER_4_TICK",
      "ROLLUP_TIER_4_END",
      "ROLLUP_TIER_5_TICK",
      "ROLLUP_TIER_5_END"
    ],
    "freeSpins": [
      "FREESPIN_TRIGGER",
      "FREESPIN_INTRO",
      "FREESPIN_SPIN_START",
      "FREESPIN_SPIN_END",
      "FREESPIN_RETRIGGER",
      "FREESPIN_SPIN_COUNT",
      "FREESPIN_LAST_SPIN",
      "FREESPIN_OUTRO",
      "FREESPIN_TOTAL_WIN"
    ],
    "music": [
      "MUSIC_BASE",
      "MUSIC_FREESPINS",
      "MUSIC_BIGWIN"
    ]
  },

  "stageConfig": {
    "reelStop": {
      "REEL_STOP_0": {"bus": "reels", "priority": 75, "pooled": true, "pan": -0.8},
      "REEL_STOP_1": {"bus": "reels", "priority": 75, "pooled": true, "pan": -0.4},
      "REEL_STOP_2": {"bus": "reels", "priority": 75, "pooled": true, "pan": 0.0},
      "REEL_STOP_3": {"bus": "reels", "priority": 75, "pooled": true, "pan": 0.4},
      "REEL_STOP_4": {"bus": "reels", "priority": 75, "pooled": true, "pan": 0.8}
    }
  }
}
```

---

## 6. Bus Routing

### 6.1 Default Bus Hierarchy

```
MASTER
├── MUSIC      (ducked by: WINS, VO)
├── SFX
├── REELS
├── WINS
├── VO
├── UI
└── AMBIENCE
```

### 6.2 Bus Config Schema

```json
{
  "buses": {
    "master": {
      "id": "master",
      "volume": 1.0,
      "children": ["music", "sfx", "reels", "wins", "vo", "ui", "ambience"]
    },
    "music": {
      "id": "music",
      "volume": 0.7,
      "duckedBy": ["wins", "vo"]
    },
    "sfx": {
      "id": "sfx",
      "volume": 0.9
    },
    "reels": {
      "id": "reels",
      "volume": 0.85
    },
    "wins": {
      "id": "wins",
      "volume": 1.0
    },
    "vo": {
      "id": "vo",
      "volume": 1.0
    },
    "ui": {
      "id": "ui",
      "volume": 0.8
    },
    "ambience": {
      "id": "ambience",
      "volume": 0.5
    }
  }
}
```

### 6.3 Ducking Rules

```json
{
  "ducking": [
    {
      "source": "wins",
      "target": "music",
      "amount": -12,
      "attackMs": 50,
      "holdMs": 100,
      "releaseMs": 500,
      "curve": "exponential"
    },
    {
      "source": "vo",
      "target": "music",
      "amount": -8,
      "attackMs": 100,
      "holdMs": 50,
      "releaseMs": 300,
      "curve": "linear"
    }
  ]
}
```

---

## 7. ALE (Adaptive Layer Engine) Config

### 7.1 Music Contexts

| Context | Opis |
|---------|------|
| BASE_GAME | Default gameplay |
| FREE_SPINS | During free spins feature |
| BIG_WIN | During big win celebration |
| BONUS | During bonus game |
| HOLD_WIN | During Hold & Win feature |

### 7.2 ALE Config Schema

```json
{
  "ale": {
    "contexts": [
      {
        "id": "BASE_GAME",
        "layers": ["L1", "L2", "L3", "L4", "L5"],
        "defaultLevel": "L2",
        "entryTransition": "bar",
        "exitTransition": "phrase"
      },
      {
        "id": "FREE_SPINS",
        "layers": ["L1", "L2", "L3", "L4", "L5"],
        "defaultLevel": "L3",
        "entryTransition": "immediate",
        "exitTransition": "bar"
      },
      {
        "id": "BIG_WIN",
        "layers": ["L1", "L2", "L3", "L4", "L5"],
        "defaultLevel": "L4",
        "entryTransition": "immediate",
        "exitTransition": "phrase"
      }
    ],

    "rules": [
      {
        "id": "win_step_up",
        "condition": {"signal": "winMultiplier", "operator": ">", "value": 5},
        "action": "step_up",
        "cooldownMs": 2000
      },
      {
        "id": "loss_step_down",
        "condition": {"signal": "consecutiveLosses", "operator": ">", "value": 10},
        "action": "step_down",
        "cooldownMs": 5000
      },
      {
        "id": "big_win_max",
        "condition": {"signal": "winMultiplier", "operator": ">=", "value": 20},
        "action": "set_level",
        "targetLevel": "L5",
        "cooldownMs": 0
      }
    ],

    "stability": {
      "globalCooldownMs": 1000,
      "hysteresis": {
        "upThreshold": 0.7,
        "downThreshold": 0.3
      },
      "levelInertia": [1.0, 1.2, 1.5, 2.0, 2.5],
      "decayAfterMs": 30000,
      "decayRate": 0.1
    },

    "transitions": {
      "default": {
        "syncMode": "bar",
        "fadeMs": 500,
        "curve": "ease_out_quad"
      },
      "urgent": {
        "syncMode": "beat",
        "fadeMs": 200,
        "curve": "linear"
      },
      "smooth": {
        "syncMode": "phrase",
        "fadeMs": 1000,
        "curve": "ease_in_out_quad"
      }
    }
  }
}
```

---

## 8. Template Gallery UI

### 8.1 Main Gallery View

```
┌─────────────────────────────────────────────────────────────────┐
│  TEMPLATE GALLERY                                    [Search]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FILTERS: [All] [Classic] [Video] [Megaways] [Features]        │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │    3×3      │  │    5×3      │  │    6×7      │             │
│  │  ░░░░░░░░░  │  │  ░░░░░░░░░  │  │  ░░░░░░░░░  │             │
│  │  ░░░░░░░░░  │  │  ░░░░░░░░░  │  │  ░░░░░░░░░  │             │
│  │  ░░░░░░░░░  │  │  ░░░░░░░░░  │  │  ░░░░░░░░░  │             │
│  │             │  │             │  │             │             │
│  │ Classic     │  │ Standard    │  │ Megaways    │             │
│  │ 3-Reel      │  │ 5×3 Video   │  │             │             │
│  │             │  │             │  │             │             │
│  │ ~50 events  │  │ ~120 events │  │ ~180 events │             │
│  │ ~3 min      │  │ ~8 min      │  │ ~12 min     │             │
│  │             │  │             │  │             │             │
│  │  [Preview]  │  │  [Preview]  │  │  [Preview]  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │    5×3      │  │    5×5      │  │    7×7      │             │
│  │  Hold &     │  │  Cascade    │  │  Cluster    │             │
│  │  Win        │  │  Tumble     │  │  Pays       │             │
│  │             │  │             │  │             │             │
│  │ ~150 events │  │ ~140 events │  │ ~130 events │             │
│  │ ~10 min     │  │ ~10 min     │  │ ~9 min      │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  [+ Create Custom]  [Import Template]  [Export Current]         │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Template Preview Dialog

```
┌─────────────────────────────────────────────────────────────────┐
│  Standard 5×3 Video Slot                              [×]       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────┐  ┌─────────────────────────────────┐│
│  │                       │  │ GRID                            ││
│  │    ░░░ ░░░ ░░░ ░░░ ░░░│  │ Reels: 5                        ││
│  │    ░░░ ░░░ ░░░ ░░░ ░░░│  │ Rows: 3                         ││
│  │    ░░░ ░░░ ░░░ ░░░ ░░░│  │ Mechanic: Lines (20)            ││
│  │                       │  │                                 ││
│  │   [ SPIN ]            │  │ SYMBOLS                         ││
│  └───────────────────────┘  │ • 4 High Pay (HP1-HP4)          ││
│                             │ • 3 Mid Pay (MP1-MP3)           ││
│  FEATURES                   │ • 4 Low Pay (LP1-LP4)           ││
│  ✓ Free Spins (3+ Scatter)  │ • Wild, Scatter                 ││
│  ✓ Wilds                    │                                 ││
│  ✓ Scatters                 │ STAGES                          ││
│  ✗ Expanding Wilds          │ • Spin: 3                       ││
│  ✗ Sticky Wilds             │ • Reel Stop: 5                  ││
│                             │ • Anticipation: 22              ││
│  AUDIO                      │ • Symbols: 26                   ││
│  • Total Events: ~120       │ • Wins: 25                      ││
│  • Estimated Setup: ~8 min  │ • Free Spins: 9                 ││
│                             │ • Music: 3                      ││
│                             └─────────────────────────────────┘│
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│              [Cancel]                    [Apply Template]       │
└─────────────────────────────────────────────────────────────────┘
```

### 8.3 Apply Template Wizard

```
┌─────────────────────────────────────────────────────────────────┐
│  Apply Template: Standard 5×3 Video                   [×]       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  STEP 1 OF 3: Import Audio                                      │
│  ═══════════════════════════════════════════════════════════    │
│                                                                 │
│  Select folder containing your audio files:                     │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  /Users/audio/my-slot-sounds                       [...]│   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Found: 87 audio files                                          │
│                                                                 │
│  Suggested folder structure:                                    │
│  ├── spin/          (spin_start.wav, spin_loop.wav)            │
│  ├── reels/         (reel_stop_01.wav - reel_stop_05.wav)      │
│  ├── symbols/       (hp1_land.wav, wild_land.wav, etc.)        │
│  ├── wins/          (win_level_1.wav - win_level_5.wav)        │
│  ├── bigwin/        (tier_1_start.wav, tier_1_loop.wav, etc.)  │
│  ├── freespins/     (fs_trigger.wav, fs_intro.wav, etc.)       │
│  └── music/         (base_loop.wav, fs_loop.wav, etc.)         │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│              [Back]                              [Next →]       │
└─────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│  Apply Template: Standard 5×3 Video                   [×]       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  STEP 2 OF 3: Auto-Mapping                                      │
│  ═══════════════════════════════════════════════════════════    │
│                                                                 │
│  Auto-mapped: 72/120 stages                                     │
│                                                                 │
│  ┌───────────────────┬────────────────────────────┬──────────┐ │
│  │ STAGE             │ MAPPED FILE                │ STATUS   │ │
│  ├───────────────────┼────────────────────────────┼──────────┤ │
│  │ SPIN_START        │ spin/spin_start.wav        │ ✓ Auto   │ │
│  │ SPIN_END          │ spin/spin_end.wav          │ ✓ Auto   │ │
│  │ REEL_STOP_0       │ reels/reel_stop_01.wav     │ ✓ Auto   │ │
│  │ REEL_STOP_1       │ reels/reel_stop_02.wav     │ ✓ Auto   │ │
│  │ REEL_STOP_2       │ reels/reel_stop_03.wav     │ ✓ Auto   │ │
│  │ REEL_STOP_3       │ reels/reel_stop_04.wav     │ ✓ Auto   │ │
│  │ REEL_STOP_4       │ reels/reel_stop_05.wav     │ ✓ Auto   │ │
│  │ SYMBOL_LAND_HP1   │ symbols/hp1_land.wav       │ ✓ Auto   │ │
│  │ SYMBOL_LAND_WILD  │ symbols/wild_land.wav      │ ✓ Auto   │ │
│  │ WIN_LEVEL_1       │ wins/win_level_1.wav       │ ✓ Auto   │ │
│  │ ...               │ ...                        │          │ │
│  │ ANTICIPATION_ON   │ (unmapped)                 │ ⚠ Manual │ │
│  │ FREESPIN_TRIGGER  │ (unmapped)                 │ ⚠ Manual │ │
│  └───────────────────┴────────────────────────────┴──────────┘ │
│                                                                 │
│  [Show All] [Show Unmapped Only]  Unmapped: 48 stages          │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│              [← Back]                            [Next →]       │
└─────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│  Apply Template: Standard 5×3 Video                   [×]       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  STEP 3 OF 3: Configuration                                     │
│  ═══════════════════════════════════════════════════════════    │
│                                                                 │
│  WIN LEVELS                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ WIN_LEVEL_1  ●─────────────────  1.0x  [locked]         │   │
│  │ WIN_LEVEL_2  ──●───────────────  2.5x                   │   │
│  │ WIN_LEVEL_3  ─────●────────────  5.0x                   │   │
│  │ WIN_LEVEL_4  ──────────●───────  10.0x                  │   │
│  │ WIN_LEVEL_5  ───────────────●──  15.0x                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  BIG WIN TIERS                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Threshold:   ──────────────●───  20.0x                  │   │
│  │                                                         │   │
│  │ TIER_1  ●────────  20.0x   Label: [________________]    │   │
│  │ TIER_2  ───●─────  35.0x   Label: [________________]    │   │
│  │ TIER_3  ──────●──  50.0x   Label: [________________]    │   │
│  │ TIER_4  ─────────● 75.0x   Label: [________________]    │   │
│  │ TIER_5  ──────────●100.0x  Label: [________________]    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  [✓] Apply bus routing                                          │
│  [✓] Apply ducking rules                                        │
│  [✓] Apply ALE configuration                                    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│              [← Back]                        [Apply Template]   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. File Structure

```
flutter_ui/lib/
├── models/
│   ├── template_models.dart           # SlotTemplate, EventTemplate, etc.
│   └── win_config_models.dart         # WinConfig, WinLevel, BigWinTier
├── services/
│   ├── template_service.dart          # Load, save, apply, export
│   └── audio_auto_mapper.dart         # Auto-mapping logic
├── providers/
│   └── template_provider.dart         # Template state management
├── widgets/
│   └── template/
│       ├── template_gallery.dart      # Main gallery widget
│       ├── template_card.dart         # Template preview card
│       ├── template_preview_dialog.dart
│       ├── template_apply_wizard.dart # Multi-step apply flow
│       ├── audio_mapping_panel.dart   # Auto-map UI
│       └── win_config_editor.dart     # Win levels & tiers editor
└── data/
    └── templates/
        ├── classic_3reel.json
        ├── standard_5x3.json
        ├── megaways.json
        ├── hold_and_win.json
        ├── cascade_tumble.json
        ├── cluster_pays.json
        ├── jackpot_progressive.json
        └── bonus_wheel.json
```

---

## 10. Implementation Phases

### Phase 1: Core Models (~400 LOC)
- [ ] template_models.dart
- [ ] win_config_models.dart

### Phase 2: Template Service (~500 LOC)
- [ ] template_service.dart
- [ ] audio_auto_mapper.dart

### Phase 3: Built-in Templates (~800 LOC JSON)
- [ ] All 8 template JSON files

### Phase 4: Gallery UI (~1200 LOC)
- [ ] template_gallery.dart
- [ ] template_card.dart
- [ ] template_preview_dialog.dart

### Phase 5: Apply Wizard (~1000 LOC)
- [ ] template_apply_wizard.dart
- [ ] audio_mapping_panel.dart
- [ ] win_config_editor.dart

### Phase 6: Integration (~300 LOC)
- [ ] template_provider.dart
- [ ] SlotLab screen integration

**Total Estimated:** ~4,200 LOC

---

## 11. Open Questions

1. **Auto-mapping algoritam** — Koje naming convention-e podržavamo?
2. **Custom templates** — Da li user može kreirati i deliti svoje template?
3. **Template versioning** — Kako handlujemo breaking changes?
4. **Partial apply** — Da li user može apply-ovati samo deo template-a?

---

## 12. Next Steps

1. Definisati ostale template-e (Megaways, Hold & Win, etc.)
2. Definisati auto-mapping naming conventions
3. Definisati UI flow za custom template creation
4. Implementacija Phase 1-6

---

*Dokument će biti dopunjavan tokom diskusije.*

---

## 13. Complete Stage Lists — All Templates

### 13.1 Template 1: Classic 3-Reel (~55 base + ~26 optional)

**Base Game (~55 stages):**

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

REEL STOPS (3):
├── REEL_STOP_0
├── REEL_STOP_1
└── REEL_STOP_2

SYMBOLS - LAND (7):
├── SYMBOL_LAND_HP1
├── SYMBOL_LAND_HP2
├── SYMBOL_LAND_MP1
├── SYMBOL_LAND_LP1
├── SYMBOL_LAND_LP2
├── SYMBOL_LAND_WILD
└── SYMBOL_LAND_SCATTER (optional - only with FS module)

SYMBOLS - WIN HIGHLIGHT (6):
├── WIN_SYMBOL_HIGHLIGHT_HP1
├── WIN_SYMBOL_HIGHLIGHT_HP2
├── WIN_SYMBOL_HIGHLIGHT_MP1
├── WIN_SYMBOL_HIGHLIGHT_LP1
├── WIN_SYMBOL_HIGHLIGHT_LP2
└── WIN_SYMBOL_HIGHLIGHT_WILD

WIN LEVELS (5):
├── WIN_LEVEL_1
├── WIN_LEVEL_2
├── WIN_LEVEL_3
├── WIN_LEVEL_4
└── WIN_LEVEL_5

BIG WIN TIERS (15):
├── BIG_WIN_TIER_1_START
├── BIG_WIN_TIER_1_LOOP
├── BIG_WIN_TIER_1_END
├── BIG_WIN_TIER_2_START
├── BIG_WIN_TIER_2_LOOP
├── BIG_WIN_TIER_2_END
├── BIG_WIN_TIER_3_START
├── BIG_WIN_TIER_3_LOOP
├── BIG_WIN_TIER_3_END
├── BIG_WIN_TIER_4_START
├── BIG_WIN_TIER_4_LOOP
├── BIG_WIN_TIER_4_END
├── BIG_WIN_TIER_5_START
├── BIG_WIN_TIER_5_LOOP
└── BIG_WIN_TIER_5_END

ROLLUP (10):
├── ROLLUP_TIER_1_TICK
├── ROLLUP_TIER_1_END
├── ROLLUP_TIER_2_TICK
├── ROLLUP_TIER_2_END
├── ROLLUP_TIER_3_TICK
├── ROLLUP_TIER_3_END
├── ROLLUP_TIER_4_TICK
├── ROLLUP_TIER_4_END
├── ROLLUP_TIER_5_TICK
└── ROLLUP_TIER_5_END

WIN LINES (2):
├── WIN_LINE_SHOW
└── WIN_LINE_HIDE

MUSIC (3):
├── MUSIC_BASE
├── MUSIC_WIN
└── MUSIC_FS (optional - only with FS module)

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

**Optional Module: Respin (+7 stages):**

```
RESPIN:
├── RESPIN_TRIGGER
├── RESPIN_START
├── REEL_RESPIN_SPINNING
├── REEL_RESPIN_STOP
├── RESPIN_WIN
├── RESPIN_NO_WIN
└── RESPIN_END
```

**Optional Module: Free Spins (+19 stages):**

```
FREE SPINS:
├── FS_TRIGGER
├── FS_INTRO
├── FS_COUNTER_SHOW
├── FS_MUSIC_START
├── FS_SPIN_START
├── FS_SPIN_END
├── FS_REEL_STOP_0
├── FS_REEL_STOP_1
├── FS_REEL_STOP_2
├── FS_COUNTER_DECREMENT
├── FS_RETRIGGER
├── FS_RETRIGGER_COUNT
├── FS_MULTIPLIER_INCREASE
├── FS_MUSIC_TENSION
├── FS_LAST_SPIN
├── FS_OUTRO
├── FS_TOTAL_WIN
├── FS_MUSIC_END
└── FS_EXIT
```

---

### 13.2 Template 2: Standard 5×3 Video (~125 base + ~47 optional)

**Base Game (~125 stages):**

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

REEL STOPS (5):
├── REEL_STOP_0
├── REEL_STOP_1
├── REEL_STOP_2
├── REEL_STOP_3
└── REEL_STOP_4

ANTICIPATION (22):
├── ANTICIPATION_ON
├── ANTICIPATION_OFF
├── ANTICIPATION_TENSION_R0_L1 → L4
├── ANTICIPATION_TENSION_R1_L1 → L4
├── ANTICIPATION_TENSION_R2_L1 → L4
├── ANTICIPATION_TENSION_R3_L1 → L4
└── ANTICIPATION_TENSION_R4_L1 → L4

SYMBOLS - LAND (13):
├── SYMBOL_LAND_HP1
├── SYMBOL_LAND_HP2
├── SYMBOL_LAND_HP3
├── SYMBOL_LAND_HP4
├── SYMBOL_LAND_MP1
├── SYMBOL_LAND_MP2
├── SYMBOL_LAND_MP3
├── SYMBOL_LAND_LP1
├── SYMBOL_LAND_LP2
├── SYMBOL_LAND_LP3
├── SYMBOL_LAND_LP4
├── SYMBOL_LAND_WILD
└── SYMBOL_LAND_SCATTER

SYMBOLS - WIN HIGHLIGHT (12):
├── WIN_SYMBOL_HIGHLIGHT_HP1 → HP4
├── WIN_SYMBOL_HIGHLIGHT_MP1 → MP3
├── WIN_SYMBOL_HIGHLIGHT_LP1 → LP4
└── WIN_SYMBOL_HIGHLIGHT_WILD

WIN LEVELS (5):
└── WIN_LEVEL_1 → WIN_LEVEL_5

BIG WIN TIERS (15):
└── BIG_WIN_TIER_1 → TIER_5 (_START, _LOOP, _END)

ROLLUP (10):
└── ROLLUP_TIER_1 → TIER_5 (_TICK, _END)

WIN LINES (2):
├── WIN_LINE_SHOW
└── WIN_LINE_HIDE

FREE SPINS (20):
├── FS_TRIGGER
├── FS_SCATTER_COLLECT_1 → 5
├── FS_INTRO
├── FS_COUNTER_SHOW
├── FS_MUSIC_START
├── FS_SPIN_START
├── FS_SPIN_END
├── FS_REEL_STOP_0 → 4
├── FS_COUNTER_DECREMENT
├── FS_RETRIGGER
├── FS_RETRIGGER_COUNT
├── FS_LAST_SPIN
├── FS_OUTRO
├── FS_TOTAL_WIN
├── FS_MUSIC_END
└── FS_EXIT

MUSIC (4):
├── MUSIC_BASE
├── MUSIC_FS
├── MUSIC_BIGWIN
└── MUSIC_TENSION

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

**Optional Module: Hold & Win (+31 stages):**

```
HOLD & WIN:
├── HOLD_TRIGGER
├── HOLD_INTRO
├── HOLD_GRID_SETUP
├── HOLD_COINS_LOCK
├── HOLD_RESPINS_START
├── HOLD_RESPIN_COUNT
├── HOLD_SPIN_START
├── HOLD_SPIN_END
├── HOLD_REEL_STOP_0 → 4 (5 stages)
├── HOLD_COIN_LAND
├── HOLD_COIN_LOCK
├── HOLD_RESPINS_RESET
├── HOLD_NO_COIN
├── HOLD_JACKPOT_MINI
├── HOLD_JACKPOT_MINOR
├── HOLD_JACKPOT_MAJOR
├── HOLD_JACKPOT_GRAND
├── HOLD_GRID_FULL
├── HOLD_WIN_EVAL
├── HOLD_COIN_COLLECT
├── HOLD_TOTAL_WIN
├── HOLD_OUTRO
├── HOLD_EXIT
├── SYMBOL_LAND_COIN
├── SYMBOL_LOCK_COIN
├── SYMBOL_COLLECT_COIN
└── MUSIC_HOLD
```

**Optional Module: Hold & Respin (+16 stages):**

```
HOLD & RESPIN (simplified, no jackpots):
├── RESPIN_TRIGGER
├── RESPIN_INTRO
├── RESPIN_SYMBOLS_LOCK
├── RESPIN_START
├── RESPIN_REEL_SPINNING
├── RESPIN_REEL_STOP_0 → 4 (5 stages)
├── RESPIN_NEW_SYMBOL_LOCK
├── RESPIN_NO_NEW_SYMBOL
├── RESPIN_WIN
├── RESPIN_NO_WIN
├── RESPIN_OUTRO
└── RESPIN_EXIT
```

**Note:** Hold & Win i Hold & Respin su međusobno isključivi — user bira jedan.

---

### 13.3 Template 3: Megaways (~185 stages)

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

REEL STOPS (6):
└── REEL_STOP_0 → REEL_STOP_5

REEL HEIGHT CHANGE (12):
├── REEL_HEIGHT_2 → REEL_HEIGHT_7 (per reel)
└── REEL_HEIGHT_CHANGE_DRAMATIC

ANTICIPATION (26):
├── ANTICIPATION_ON
├── ANTICIPATION_OFF
└── ANTICIPATION_TENSION_R0 → R5_L1 → L4

SYMBOLS - LAND (11):
├── SYMBOL_LAND_HP1 → HP6
├── SYMBOL_LAND_LP1 → LP4
└── SYMBOL_LAND_WILD

SYMBOLS - SPECIAL (6):
├── SYMBOL_LAND_SCATTER
├── SYMBOL_LAND_MYSTERY
├── MYSTERY_REVEAL_START
├── MYSTERY_REVEAL_SYMBOL
├── MYSTERY_REVEAL_END
└── SYMBOL_LAND_MULTIPLIER

SYMBOLS - WIN HIGHLIGHT (11):
└── WIN_SYMBOL_HIGHLIGHT_HP1 → HP6, LP1 → LP4, WILD

WIN LEVELS (5):
└── WIN_LEVEL_1 → WIN_LEVEL_5

BIG WIN TIERS (15):
└── BIG_WIN_TIER_1 → TIER_5 (_START, _LOOP, _END)

ROLLUP (10):
└── ROLLUP_TIER_1 → TIER_5 (_TICK, _END)

WIN LINES (2):
├── WIN_LINE_SHOW
└── WIN_LINE_HIDE

WAYS COUNT (6):
├── WAYS_100
├── WAYS_1000
├── WAYS_10000
├── WAYS_50000
├── WAYS_100000
└── WAYS_MEGAWAYS (117649)

CASCADE/TUMBLE (12):
├── CASCADE_START
├── CASCADE_DROP
├── CASCADE_LAND
├── CASCADE_WIN_EVAL
├── CASCADE_STEP_1 → 10
└── CASCADE_END

FREE SPINS (25):
├── FS_TRIGGER
├── FS_INTRO
├── FS_MULTIPLIER_START
├── FS_MULTIPLIER_INCREASE
├── FS_MULTIPLIER_DISPLAY
├── FS_SPIN_START
├── FS_SPIN_END
├── FS_REEL_STOP_0 → 5
├── FS_COUNTER_DECREMENT
├── FS_RETRIGGER
├── FS_UNLIMITED_MODE
├── FS_LAST_SPIN
├── FS_OUTRO
├── FS_TOTAL_WIN
└── FS_EXIT

FEATURE BUY (4):
├── FEATURE_BUY_OPEN
├── FEATURE_BUY_CONFIRM
├── FEATURE_BUY_CANCEL
└── FEATURE_BUY_TRIGGER

MUSIC (5):
├── MUSIC_BASE
├── MUSIC_FS
├── MUSIC_BIGWIN
├── MUSIC_TENSION
└── MUSIC_CASCADE

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

---

### 13.4 Template 4: Hold & Win (~155 stages)

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

REEL STOPS (5):
└── REEL_STOP_0 → REEL_STOP_4

ANTICIPATION (22):
└── (same as Standard 5×3)

SYMBOLS - LAND (15):
├── SYMBOL_LAND_HP1 → HP4
├── SYMBOL_LAND_MP1 → MP3
├── SYMBOL_LAND_LP1 → LP4
├── SYMBOL_LAND_WILD
├── SYMBOL_LAND_SCATTER
└── SYMBOL_LAND_COIN

COIN VALUES (8):
├── COIN_VALUE_MINI
├── COIN_VALUE_MINOR
├── COIN_VALUE_MAJOR
├── COIN_VALUE_GRAND
├── COIN_VALUE_1X → 5X
└── COIN_VALUE_MULTIPLIER

SYMBOLS - WIN HIGHLIGHT (12):
└── WIN_SYMBOL_HIGHLIGHT_HP1 → HP4, MP1 → MP3, LP1 → LP4, WILD

WIN LEVELS (5):
└── WIN_LEVEL_1 → WIN_LEVEL_5

BIG WIN TIERS (15):
└── BIG_WIN_TIER_1 → TIER_5 (_START, _LOOP, _END)

ROLLUP (10):
└── ROLLUP_TIER_1 → TIER_5 (_TICK, _END)

WIN LINES (2):
├── WIN_LINE_SHOW
└── WIN_LINE_HIDE

HOLD & WIN FEATURE (35):
├── HOLD_TRIGGER
├── HOLD_INTRO
├── HOLD_GRID_SETUP
├── HOLD_COINS_LOCK (initial)
├── HOLD_RESPINS_START
├── HOLD_RESPIN_COUNT (3)
├── HOLD_SPIN_START
├── HOLD_SPIN_END
├── HOLD_REEL_STOP_0 → 4
├── HOLD_COIN_LAND
├── HOLD_COIN_LOCK
├── HOLD_RESPINS_RESET (to 3)
├── HOLD_NO_COIN
├── HOLD_JACKPOT_MINI
├── HOLD_JACKPOT_MINOR
├── HOLD_JACKPOT_MAJOR
├── HOLD_JACKPOT_GRAND
├── HOLD_GRID_FULL
├── HOLD_WIN_EVAL
├── HOLD_COIN_COLLECT
├── HOLD_TOTAL_WIN
├── HOLD_OUTRO
└── HOLD_EXIT

FREE SPINS (15):
├── FS_TRIGGER
├── FS_INTRO
├── FS_SPIN_START
├── FS_SPIN_END
├── FS_REEL_STOP_0 → 4
├── FS_COUNTER_DECREMENT
├── FS_RETRIGGER
├── FS_HOLD_TRIGGER (Hold within FS)
├── FS_OUTRO
├── FS_TOTAL_WIN
└── FS_EXIT

MUSIC (6):
├── MUSIC_BASE
├── MUSIC_FS
├── MUSIC_HOLD
├── MUSIC_BIGWIN
├── MUSIC_JACKPOT
└── MUSIC_TENSION

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

---

### 13.5 Template 5: Cascade/Tumble (~145 stages)

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

REEL STOPS (5):
└── REEL_STOP_0 → REEL_STOP_4

SYMBOLS - LAND (12):
├── SYMBOL_LAND_HP1 → HP4
├── SYMBOL_LAND_MP1 → MP2
├── SYMBOL_LAND_LP1 → LP4
├── SYMBOL_LAND_WILD
└── SYMBOL_LAND_SCATTER

SYMBOLS - WIN HIGHLIGHT (11):
└── WIN_SYMBOL_HIGHLIGHT_*

SYMBOLS - EXPLODE (11):
└── SYMBOL_EXPLODE_* (matching WIN_SYMBOL_HIGHLIGHT)

CASCADE MECHANIC (25):
├── CASCADE_START
├── CASCADE_SYMBOLS_MARK
├── CASCADE_SYMBOLS_EXPLODE
├── CASCADE_SYMBOLS_CLEAR
├── CASCADE_DROP_START
├── CASCADE_DROP_SYMBOLS
├── CASCADE_DROP_LAND
├── CASCADE_STEP_1 → 15 (max cascade depth)
├── CASCADE_WIN_EVAL
├── CASCADE_NO_MORE_WINS
└── CASCADE_END

MULTIPLIER (10):
├── MULTIPLIER_SHOW
├── MULTIPLIER_1X → 8X
└── MULTIPLIER_RESET

WIN LEVELS (5):
└── WIN_LEVEL_1 → WIN_LEVEL_5

BIG WIN TIERS (15):
└── BIG_WIN_TIER_1 → TIER_5 (_START, _LOOP, _END)

ROLLUP (10):
└── ROLLUP_TIER_1 → TIER_5 (_TICK, _END)

FREE SPINS (20):
├── FS_TRIGGER
├── FS_INTRO
├── FS_SPIN_START
├── FS_SPIN_END
├── FS_REEL_STOP_0 → 4
├── FS_CASCADE_*
├── FS_MULTIPLIER_CARRY
├── FS_COUNTER_DECREMENT
├── FS_RETRIGGER
├── FS_OUTRO
├── FS_TOTAL_WIN
└── FS_EXIT

MUSIC (5):
├── MUSIC_BASE
├── MUSIC_FS
├── MUSIC_BIGWIN
├── MUSIC_CASCADE
└── MUSIC_TENSION

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

---

### 13.6 Template 6: Cluster Pays (~130 stages)

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

GRID DROP (7):
├── GRID_DROP_START
├── GRID_DROP_COLUMN_0 → 6
└── GRID_DROP_END

SYMBOLS - LAND (12):
├── SYMBOL_LAND_HP1 → HP4
├── SYMBOL_LAND_MP1 → MP2
├── SYMBOL_LAND_LP1 → LP4
├── SYMBOL_LAND_WILD
└── SYMBOL_LAND_SCATTER

CLUSTER DETECTION (15):
├── CLUSTER_FOUND
├── CLUSTER_SIZE_5
├── CLUSTER_SIZE_8
├── CLUSTER_SIZE_12
├── CLUSTER_SIZE_15
├── CLUSTER_SIZE_20
├── CLUSTER_SIZE_25
├── CLUSTER_SIZE_30
├── CLUSTER_SIZE_MEGA
├── CLUSTER_SYMBOLS_MARK
├── CLUSTER_SYMBOLS_EXPLODE
├── CLUSTER_SYMBOLS_CLEAR
├── CLUSTER_WIN_SHOW
└── CLUSTER_WIN_HIDE

CASCADE (12):
├── CASCADE_START
├── CASCADE_DROP
├── CASCADE_LAND
├── CASCADE_STEP_1 → 10
└── CASCADE_END

WIN LEVELS (5):
└── WIN_LEVEL_1 → WIN_LEVEL_5

BIG WIN TIERS (15):
└── BIG_WIN_TIER_1 → TIER_5 (_START, _LOOP, _END)

ROLLUP (10):
└── ROLLUP_TIER_1 → TIER_5 (_TICK, _END)

FREE SPINS (18):
├── FS_TRIGGER
├── FS_INTRO
├── FS_SPIN_START
├── FS_SPIN_END
├── FS_GRID_DROP
├── FS_CLUSTER_*
├── FS_CASCADE_*
├── FS_COUNTER_DECREMENT
├── FS_RETRIGGER
├── FS_OUTRO
├── FS_TOTAL_WIN
└── FS_EXIT

MUSIC (5):
├── MUSIC_BASE
├── MUSIC_FS
├── MUSIC_BIGWIN
├── MUSIC_CASCADE
└── MUSIC_CLUSTER

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

---

### 13.7 Template 7: Jackpot Progressive (~105 stages)

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

REEL STOPS (5):
└── REEL_STOP_0 → REEL_STOP_4

SYMBOLS - LAND (14):
├── SYMBOL_LAND_HP1 → HP4
├── SYMBOL_LAND_MP1 → MP3
├── SYMBOL_LAND_LP1 → LP4
├── SYMBOL_LAND_WILD
├── SYMBOL_LAND_SCATTER
└── SYMBOL_LAND_JACKPOT

WIN LEVELS (5):
└── WIN_LEVEL_1 → WIN_LEVEL_5

BIG WIN TIERS (15):
└── BIG_WIN_TIER_1 → TIER_5 (_START, _LOOP, _END)

ROLLUP (10):
└── ROLLUP_TIER_1 → TIER_5 (_TICK, _END)

WIN LINES (2):
├── WIN_LINE_SHOW
└── WIN_LINE_HIDE

JACKPOT SYSTEM (25):
├── JACKPOT_TRIGGER
├── JACKPOT_TRANSITION
├── JACKPOT_WHEEL_INTRO
├── JACKPOT_WHEEL_SPIN_START
├── JACKPOT_WHEEL_SPINNING
├── JACKPOT_WHEEL_DECEL
├── JACKPOT_WHEEL_STOP
├── JACKPOT_TIER_REVEAL
├── JACKPOT_MINI_WIN
├── JACKPOT_MINOR_WIN
├── JACKPOT_MAJOR_WIN
├── JACKPOT_GRAND_WIN
├── JACKPOT_AMOUNT_SHOW
├── JACKPOT_ROLLUP_START
├── JACKPOT_ROLLUP_TICK
├── JACKPOT_ROLLUP_END
├── JACKPOT_CELEBRATION
├── JACKPOT_CONFETTI
├── JACKPOT_OUTRO
└── JACKPOT_EXIT

PROGRESSIVE TICKER (4):
├── JACKPOT_TICKER_UPDATE
├── JACKPOT_NEAR_THRESHOLD
├── JACKPOT_SEED_RESET
└── JACKPOT_CONTRIBUTION

FREE SPINS (15):
├── FS_TRIGGER
├── FS_INTRO
├── FS_SPIN_START
├── FS_SPIN_END
├── FS_REEL_STOP_0 → 4
├── FS_JACKPOT_TRIGGER (Jackpot within FS)
├── FS_COUNTER_DECREMENT
├── FS_OUTRO
├── FS_TOTAL_WIN
└── FS_EXIT

MUSIC (5):
├── MUSIC_BASE
├── MUSIC_FS
├── MUSIC_BIGWIN
├── MUSIC_JACKPOT
└── MUSIC_JACKPOT_WHEEL

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

---

### 13.8 Template 8: Bonus Wheel (~115 stages)

```
SPIN FLOW (3):
├── SPIN_START
├── SPIN_END
└── REEL_SPINNING

REEL STOPS (5):
└── REEL_STOP_0 → REEL_STOP_4

SYMBOLS - LAND (14):
├── SYMBOL_LAND_HP1 → HP4
├── SYMBOL_LAND_MP1 → MP3
├── SYMBOL_LAND_LP1 → LP4
├── SYMBOL_LAND_WILD
├── SYMBOL_LAND_SCATTER
└── SYMBOL_LAND_BONUS

WIN LEVELS (5):
└── WIN_LEVEL_1 → WIN_LEVEL_5

BIG WIN TIERS (15):
└── BIG_WIN_TIER_1 → TIER_5 (_START, _LOOP, _END)

ROLLUP (10):
└── ROLLUP_TIER_1 → TIER_5 (_TICK, _END)

WIN LINES (2):
├── WIN_LINE_SHOW
└── WIN_LINE_HIDE

BONUS WHEEL SYSTEM (30):
├── BONUS_TRIGGER
├── BONUS_TRANSITION
├── BONUS_WHEEL_INTRO
├── BONUS_WHEEL_SHOW
├── BONUS_WHEEL_SPIN_PROMPT
├── BONUS_WHEEL_SPIN_START
├── BONUS_WHEEL_SPINNING
├── BONUS_WHEEL_TICK (per segment)
├── BONUS_WHEEL_DECEL
├── BONUS_WHEEL_STOP
├── BONUS_PRIZE_REVEAL
├── BONUS_PRIZE_MULTIPLIER_1X → 10X
├── BONUS_PRIZE_FREE_SPINS
├── BONUS_PRIZE_INSTANT_WIN
├── BONUS_PRIZE_RESPIN
├── BONUS_PRIZE_SUPER_WHEEL
├── BONUS_COLLECT_PROMPT
├── BONUS_COLLECT
├── BONUS_GAMBLE_PROMPT
├── BONUS_GAMBLE_WIN
├── BONUS_GAMBLE_LOSE
├── BONUS_CONFETTI
├── BONUS_OUTRO
└── BONUS_EXIT

SUPER WHEEL (10):
├── SUPER_WHEEL_INTRO
├── SUPER_WHEEL_SHOW
├── SUPER_WHEEL_SPIN_START
├── SUPER_WHEEL_SPINNING
├── SUPER_WHEEL_STOP
├── SUPER_WHEEL_MEGA_PRIZE
├── SUPER_WHEEL_JACKPOT
├── SUPER_WHEEL_CELEBRATE
└── SUPER_WHEEL_EXIT

FREE SPINS (15):
└── (same as Standard 5×3)

MUSIC (6):
├── MUSIC_BASE
├── MUSIC_FS
├── MUSIC_BIGWIN
├── MUSIC_BONUS_WHEEL
├── MUSIC_SUPER_WHEEL
└── MUSIC_TENSION

UI (3):
├── UI_SPIN_BUTTON
├── UI_BALANCE_UPDATE
└── UI_BET_CHANGE
```

---

## 14. Stage Naming Conventions Summary

| Category | Pattern | Examples |
|----------|---------|----------|
| **Spin** | `SPIN_*` | SPIN_START, SPIN_END |
| **Reel** | `REEL_*` | REEL_STOP_0, REEL_SPINNING |
| **Symbol Land** | `SYMBOL_LAND_{ID}` | SYMBOL_LAND_HP1, SYMBOL_LAND_WILD |
| **Symbol Win** | `WIN_SYMBOL_HIGHLIGHT_{ID}` | WIN_SYMBOL_HIGHLIGHT_HP1 |
| **Win Level** | `WIN_LEVEL_{N}` | WIN_LEVEL_1, WIN_LEVEL_5 |
| **Big Win** | `BIG_WIN_TIER_{N}_*` | BIG_WIN_TIER_1_START |
| **Rollup** | `ROLLUP_TIER_{N}_*` | ROLLUP_TIER_1_TICK |
| **Free Spins** | `FS_*` | FS_TRIGGER, FS_SPIN_START |
| **Hold & Win** | `HOLD_*` | HOLD_TRIGGER, HOLD_COIN_LOCK |
| **Cascade** | `CASCADE_*` | CASCADE_START, CASCADE_STEP_1 |
| **Jackpot** | `JACKPOT_*` | JACKPOT_TRIGGER, JACKPOT_GRAND_WIN |
| **Bonus** | `BONUS_*` | BONUS_WHEEL_SPIN_START |
| **Anticipation** | `ANTICIPATION_*` | ANTICIPATION_TENSION_R2_L3 |
| **Music** | `MUSIC_*` | MUSIC_BASE, MUSIC_FS |
| **UI** | `UI_*` | UI_SPIN_BUTTON |

---

## 15. Total Stage Count Summary

| Template | Base Stages | Optional | Max Total |
|----------|-------------|----------|-----------|
| Classic 3-Reel | 55 | +26 (Respin/FS) | 81 |
| Standard 5×3 Video | 125 | +31 (H&W) or +16 (H&R) | 156 |
| Megaways | 185 | — | 185 |
| Hold & Win | 155 | — | 155 |
| Cascade/Tumble | 145 | — | 145 |
| Cluster Pays | 130 | — | 130 |
| Jackpot Progressive | 105 | — | 105 |
| Bonus Wheel | 115 | — | 115 |
| **TOTAL** | **~1,015** | **+57** | **~1,072** |

**Legend:**
- H&W = Hold & Win (full feature with jackpots)
- H&R = Hold & Respin (simplified, no jackpots)
- FS = Free Spins

---

## 16. Modular Template Builder — Ultimate System

### 16.1 Filozofija

**"One Click, Everything Works"** — Kada user primeni template:

1. SVE stage-ovi su kreirani
2. SVE event template-i su povezani
3. SVE bus routing je podešen
4. SVE ducking pravila su aktivna
5. SVE ALE konfiguracija je spremna
6. User samo treba da MAP-ira audio fajlove

**NEMA RUPA** — Sistem automatski generiše kompletan audio graf.

---

### 16.2 Kako Radi — Complete Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  KORAK 1: Izbor Base Template                                               │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                             │
│  User bira: "Standard 5×3 Video Slot"                                       │
│  Base: 125 stages, 13 symbols, Free Spins uključen                          │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  KORAK 2: Izbor Feature Modula (Klik na toggle)                             │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                             │
│  [✓] Free Spins (već uključen u base)                                       │
│  [+] Hold & Win                    → +31 stages, +5 symbols, RTP +2%        │
│  [ ] Cascade                       → +25 stages, RTP +1.5%                  │
│  [ ] Jackpot Progressive           → +29 stages, +4 symbols                 │
│  [+] Multiplier System             → +10 stages                             │
│                                                                             │
│  ──────────────────────────────────────────────────────────────────────     │
│  TOTAL: 125 + 31 + 10 = 166 stages                                          │
│  Estimated RTP: 96.5% (+2.0%)                                               │
│  Volatility: High (↑ from Medium)                                           │
│  Max Win: 5,000x → 15,000x (H&W jackpot potential)                          │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  KORAK 3: FluxForge Auto-Generates EVERYTHING                               │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                             │
│  ✓ 166 stage definicija kreirano                                            │
│  ✓ 166 event template-a povezano (stage → event → bus → priority)           │
│  ✓ 18 simbola registrovano sa audio kontekstima                             │
│  ✓ 7 bus-eva konfigurisano (MASTER → children)                              │
│  ✓ 12 ducking pravila aktivno                                               │
│  ✓ 5 ALE konteksta definisano (BASE, FS, HOLD, BIGWIN, JACKPOT)             │
│  ✓ 15 ALE pravila za tranzicije                                             │
│  ✓ RTPC winMultiplier krive podešene                                        │
│  ✓ Module interactions linked (FS → HOLD → JACKPOT chain)                   │
│                                                                             │
│  ❗ ČEKA SAMO: Audio file mapping (Step 4)                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 16.3 Feature Module Catalog (14 Modula)

#### Kategorija: Core Features

| # | Modul | Stages | Add. Symbols | RTP Impact | Volatility Impact | Description |
|---|-------|--------|--------------|------------|-------------------|-------------|
| 1 | **Free Spins** | +19 | SCATTER | +0.5% | ↑ Low | Standard free spins |
| 2 | **Free Spins + Multiplier** | +29 | SCATTER | +1.0% | ↑↑ Medium | FS with progressive multiplier |
| 3 | **Respin** | +7 | — | +0.3% | — | Single symbol respin |
| 4 | **Wild Expansion** | +8 | — | +0.4% | ↑ Low | Wilds expand to full reel |
| 5 | **Sticky Wilds** | +6 | — | +0.3% | — | Wilds persist across spins |

#### Kategorija: Bonus Features

| # | Modul | Stages | Add. Symbols | RTP Impact | Volatility Impact | Description |
|---|-------|--------|--------------|------------|-------------------|-------------|
| 6 | **Hold & Win** | +31 | COIN, JACKPOT_* | +2.0% | ↑↑↑ High | Full H&W with jackpots |
| 7 | **Hold & Respin** | +16 | — | +0.8% | ↑ Medium | Simplified hold/respin |
| 8 | **Bonus Wheel** | +30 | BONUS | +1.5% | ↑↑ High | Wheel of fortune bonus |
| 9 | **Pick Bonus** | +20 | BONUS | +1.0% | ↑ Medium | Pick-a-prize feature |

#### Kategorija: Cascade/Tumble

| # | Modul | Stages | Add. Symbols | RTP Impact | Volatility Impact | Description |
|---|-------|--------|--------------|------------|-------------------|-------------|
| 10 | **Cascade (Basic)** | +12 | — | +0.8% | ↑ Medium | Symbols drop, wins explode |
| 11 | **Cascade + Multiplier** | +22 | MULTIPLIER | +1.5% | ↑↑ High | Cascade with inc. multiplier |

#### Kategorija: Jackpot

| # | Modul | Stages | Add. Symbols | RTP Impact | Volatility Impact | Description |
|---|-------|--------|--------------|------------|-------------------|-------------|
| 12 | **Jackpot (4-tier)** | +29 | JACKPOT_MINI/MINOR/MAJOR/GRAND | +1.5% | ↑↑↑ Very High | Progressive jackpots |
| 13 | **Mystery Jackpot** | +15 | MYSTERY | +0.8% | ↑↑ High | Random jackpot trigger |

#### Kategorija: Utility

| # | Modul | Stages | Add. Symbols | RTP Impact | Volatility Impact | Description |
|---|-------|--------|--------------|------------|-------------------|-------------|
| 14 | **Multiplier System** | +10 | MULTIPLIER | +0.5% | ↑ Low | Global multiplier events |

---

### 16.4 Module Stage Definitions

#### Module 1: Free Spins (+19 stages)

```
FS_TRIGGER
FS_SCATTER_COLLECT_1
FS_SCATTER_COLLECT_2
FS_SCATTER_COLLECT_3
FS_SCATTER_COLLECT_4  (optional - 4th scatter)
FS_SCATTER_COLLECT_5  (optional - 5th scatter)
FS_INTRO
FS_COUNTER_SHOW
FS_MUSIC_START
FS_SPIN_START
FS_SPIN_END
FS_REEL_STOP_0 → 4   (use base reel count)
FS_COUNTER_DECREMENT
FS_RETRIGGER
FS_RETRIGGER_COUNT
FS_LAST_SPIN
FS_OUTRO
FS_TOTAL_WIN
FS_MUSIC_END
FS_EXIT
```

**Event Template Connections:**

| Stage | Event Template | Bus | Priority | Pooled |
|-------|---------------|-----|----------|--------|
| FS_TRIGGER | evt_fs_trigger | sfx | 90 | ✗ |
| FS_SCATTER_COLLECT_* | evt_scatter_collect | sfx | 85 | ✓ |
| FS_INTRO | evt_fs_intro | sfx | 90 | ✗ |
| FS_MUSIC_START | evt_fs_music | music | 100 | ✗ |
| FS_SPIN_START | evt_spin_start | sfx | 70 | ✗ |
| FS_SPIN_END | evt_spin_end | sfx | 70 | ✗ |
| FS_REEL_STOP_* | evt_reel_stop | reels | 75 | ✓ |
| FS_COUNTER_DECREMENT | evt_counter_tick | ui | 50 | ✓ |
| FS_RETRIGGER | evt_fs_retrigger | sfx | 95 | ✗ |
| FS_LAST_SPIN | evt_last_spin | sfx | 85 | ✗ |
| FS_OUTRO | evt_fs_outro | sfx | 90 | ✗ |
| FS_TOTAL_WIN | evt_total_win | wins | 95 | ✗ |
| FS_EXIT | evt_fs_exit | sfx | 80 | ✗ |

**ALE Context:**

```json
{
  "context": "FREE_SPINS",
  "layers": ["L1", "L2", "L3", "L4", "L5"],
  "defaultLevel": "L3",
  "entryStage": "FS_MUSIC_START",
  "exitStage": "FS_EXIT",
  "entryTransition": "immediate",
  "exitTransition": "bar"
}
```

#### Module 6: Hold & Win (+31 stages)

```
HOLD_TRIGGER
HOLD_INTRO
HOLD_GRID_SETUP
HOLD_COINS_LOCK
HOLD_RESPINS_START
HOLD_RESPIN_COUNT
HOLD_SPIN_START
HOLD_SPIN_END
HOLD_REEL_STOP_0 → 4
HOLD_COIN_LAND
HOLD_COIN_LOCK
HOLD_RESPINS_RESET
HOLD_NO_COIN
HOLD_JACKPOT_MINI
HOLD_JACKPOT_MINOR
HOLD_JACKPOT_MAJOR
HOLD_JACKPOT_GRAND
HOLD_GRID_FULL
HOLD_WIN_EVAL
HOLD_COIN_COLLECT
HOLD_TOTAL_WIN
HOLD_OUTRO
HOLD_EXIT
SYMBOL_LAND_COIN
SYMBOL_LOCK_COIN
SYMBOL_COLLECT_COIN
MUSIC_HOLD
```

**Additional Symbols:**

| ID | Type | Contexts |
|----|------|----------|
| COIN | coin | land, lock, collect |
| JACKPOT_MINI | jackpot | land, lock, win |
| JACKPOT_MINOR | jackpot | land, lock, win |
| JACKPOT_MAJOR | jackpot | land, lock, win |
| JACKPOT_GRAND | jackpot | land, lock, win |

**Event Template Connections:**

| Stage | Event Template | Bus | Priority | Pooled |
|-------|---------------|-----|----------|--------|
| HOLD_TRIGGER | evt_hold_trigger | sfx | 95 | ✗ |
| HOLD_INTRO | evt_hold_intro | sfx | 90 | ✗ |
| HOLD_GRID_SETUP | evt_grid_setup | ui | 60 | ✗ |
| HOLD_COINS_LOCK | evt_coins_lock | sfx | 80 | ✗ |
| HOLD_RESPINS_START | evt_respins_start | sfx | 75 | ✗ |
| HOLD_RESPIN_COUNT | evt_respin_count | ui | 50 | ✓ |
| HOLD_SPIN_* | evt_hold_spin | sfx | 70 | ✗ |
| HOLD_REEL_STOP_* | evt_hold_reel_stop | reels | 75 | ✓ |
| HOLD_COIN_LAND | evt_coin_land | sfx | 85 | ✓ |
| HOLD_COIN_LOCK | evt_coin_lock | sfx | 85 | ✓ |
| HOLD_RESPINS_RESET | evt_respins_reset | ui | 60 | ✗ |
| HOLD_NO_COIN | evt_no_coin | sfx | 50 | ✗ |
| HOLD_JACKPOT_* | evt_jackpot_tier | wins | 100 | ✗ |
| HOLD_GRID_FULL | evt_grid_full | sfx | 95 | ✗ |
| HOLD_COIN_COLLECT | evt_coin_collect | wins | 90 | ✗ |
| HOLD_TOTAL_WIN | evt_hold_total_win | wins | 95 | ✗ |
| HOLD_OUTRO | evt_hold_outro | sfx | 90 | ✗ |
| HOLD_EXIT | evt_hold_exit | sfx | 80 | ✗ |
| MUSIC_HOLD | evt_music_hold | music | 100 | ✗ |

**ALE Context:**

```json
{
  "context": "HOLD_WIN",
  "layers": ["L1", "L2", "L3", "L4", "L5"],
  "defaultLevel": "L3",
  "entryStage": "HOLD_INTRO",
  "exitStage": "HOLD_EXIT",
  "entryTransition": "immediate",
  "exitTransition": "phrase",
  "rules": [
    {
      "signal": "respinsRemaining",
      "operator": "==",
      "value": 1,
      "action": "set_level",
      "targetLevel": "L5",
      "comment": "Tension on last respin"
    },
    {
      "signal": "coinsCollected",
      "operator": ">",
      "value": 10,
      "action": "step_up",
      "comment": "Energy increases with more coins"
    }
  ]
}
```

---

### 16.5 Module Interactions — Combination Stages

Kada user uključi **VIŠE modula**, FluxForge automatski kreira **interaction stages** za prelaze.

#### Free Spins + Hold & Win Interaction (+8 stages)

```
FS_HOLD_TRIGGER       → Hold & Win triggered during Free Spins
FS_HOLD_INTRO         → Special intro (FS context preserved)
FS_HOLD_EXIT          → Return to Free Spins after Hold
FS_HOLD_BONUS_COINS   → Extra coins during FS-Hold
HOLD_FS_RETRIGGER     → FS retrigger from within Hold
HOLD_FS_SCATTER_LAND  → Scatter lands during Hold phase
MUSIC_FS_HOLD         → Layered music (FS base + Hold overlay)
ALE_FS_HOLD_BLEND     → Smooth transition between contexts
```

#### Free Spins + Cascade Interaction (+5 stages)

```
FS_CASCADE_START      → Cascade in FS context
FS_CASCADE_MULTIPLIER → FS-specific multiplier increase
FS_CASCADE_MEGA       → Mega cascade (15+ symbols)
CASCADE_FS_CONTEXT    → Cascade-specific FS music layer
MUSIC_FS_CASCADE      → Cascade music overlay on FS
```

#### Hold & Win + Jackpot Interaction (+4 stages)

```
HOLD_JACKPOT_TRIGGER  → Jackpot wheel from Hold
HOLD_JACKPOT_RETURN   → Return to Hold after jackpot
JACKPOT_HOLD_CONTEXT  → Jackpot with Hold visual overlay
MUSIC_HOLD_JACKPOT    → Combined music context
```

---

### 16.6 Conflict Rules — Mutually Exclusive Modules

Neki moduli **NE MOGU** biti aktivni istovremeno:

| Module A | Module B | Conflict Reason | Resolution |
|----------|----------|-----------------|------------|
| Hold & Win | Hold & Respin | Same mechanic, different depth | User chooses one |
| Cascade (Basic) | Cascade + Multiplier | Basic is subset | Auto-upgrade to +Multiplier |
| Jackpot (4-tier) | Mystery Jackpot | Different jackpot systems | User chooses one |
| Free Spins | Free Spins + Multiplier | Basic is subset | Auto-upgrade to +Multiplier |

**UI Handling:**

```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠️ Conflict Detected                                            │
│                                                                 │
│  "Hold & Win" and "Hold & Respin" cannot be used together.     │
│  Both features use the same hold/respin mechanic.              │
│                                                                 │
│  Please choose one:                                             │
│                                                                 │
│  [Hold & Win]           [Hold & Respin]         [Cancel]       │
│  Full feature with      Simplified version                     │
│  4-tier jackpots        No jackpots                            │
│  +31 stages, +5 sym     +16 stages                             │
│  RTP +2.0%              RTP +0.8%                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 16.7 Auto-Calculation Logic

FluxForge automatski računa matematiku na osnovu izabranih modula.

#### RTP Calculation

```dart
double calculateEstimatedRtp(
  SlotTemplate baseTemplate,
  List<FeatureModule> enabledModules,
) {
  double baseRtp = baseTemplate.baseRtp; // e.g., 94.5%

  for (final module in enabledModules) {
    baseRtp += module.rtpContribution;
  }

  // Apply interaction bonuses
  if (hasModule('freeSpins') && hasModule('holdAndWin')) {
    baseRtp += 0.3; // FS+H&W synergy bonus
  }

  if (hasModule('cascade') && hasModule('multiplier')) {
    baseRtp += 0.2; // Cascade+Mult synergy
  }

  return baseRtp.clamp(88.0, 99.0); // Legal range
}
```

#### Volatility Calculation

```dart
enum Volatility { low, mediumLow, medium, mediumHigh, high, veryHigh }

Volatility calculateVolatility(
  SlotTemplate baseTemplate,
  List<FeatureModule> enabledModules,
) {
  int volatilityScore = baseTemplate.baseVolatilityScore; // 0-100

  for (final module in enabledModules) {
    volatilityScore += module.volatilityImpact;
  }

  // Convert score to enum
  if (volatilityScore >= 80) return Volatility.veryHigh;
  if (volatilityScore >= 65) return Volatility.high;
  if (volatilityScore >= 50) return Volatility.mediumHigh;
  if (volatilityScore >= 35) return Volatility.medium;
  if (volatilityScore >= 20) return Volatility.mediumLow;
  return Volatility.low;
}
```

#### Max Win Calculation

```dart
int calculateMaxWin(
  SlotTemplate baseTemplate,
  List<FeatureModule> enabledModules,
) {
  int maxWin = baseTemplate.baseMaxWin; // e.g., 5000x

  for (final module in enabledModules) {
    maxWin = (maxWin * module.maxWinMultiplier).round();
  }

  // Jackpot adds flat bonus
  if (hasModule('jackpot4Tier')) {
    maxWin += 10000; // Grand jackpot contribution
  }

  return maxWin;
}
```

#### Hit Frequency Estimation

```dart
double calculateHitFrequency(
  SlotTemplate baseTemplate,
  List<FeatureModule> enabledModules,
) {
  double baseHitFreq = baseTemplate.baseHitFrequency; // e.g., 0.28 (28%)

  // More features = more ways to win
  for (final module in enabledModules) {
    baseHitFreq += module.hitFrequencyBonus;
  }

  // But volatility reduces small wins
  final volatility = calculateVolatility(baseTemplate, enabledModules);
  if (volatility == Volatility.veryHigh) {
    baseHitFreq *= 0.85; // -15% for very high vol
  } else if (volatility == Volatility.high) {
    baseHitFreq *= 0.92; // -8% for high vol
  }

  return baseHitFreq.clamp(0.15, 0.50);
}
```

---

### 16.8 Complete Stage Generation

Kada user klikne "Apply Template", FluxForge:

#### Step 1: Collect All Stages

```dart
List<StageDefinition> generateAllStages(
  SlotTemplate template,
  List<FeatureModule> modules,
) {
  final stages = <StageDefinition>[];

  // 1. Base template stages
  stages.addAll(template.baseStages);

  // 2. Module stages
  for (final module in modules) {
    stages.addAll(module.stages);
  }

  // 3. Module interaction stages
  stages.addAll(_generateInteractionStages(modules));

  // 4. Remove duplicates (modules may share stages)
  return stages.toSet().toList();
}
```

#### Step 2: Create Event Templates

```dart
List<EventTemplate> generateEventTemplates(List<StageDefinition> stages) {
  return stages.map((stage) => EventTemplate(
    id: 'evt_${stage.id.toLowerCase()}',
    stage: stage.id,
    bus: stage.defaultBus,
    priority: stage.defaultPriority,
    pooled: stage.isPooled,
    layers: [
      EventLayer(
        id: 'layer_0',
        audioPath: null, // User maps later
        volume: 1.0,
        pan: stage.defaultPan,
        delay: 0,
      ),
    ],
  )).toList();
}
```

#### Step 3: Setup Bus Routing

```dart
BusHierarchy generateBusRouting(SlotTemplate template) {
  return BusHierarchy(
    master: BusNode(id: 'master', volume: 1.0, children: [
      BusNode(id: 'music', volume: 0.7, duckedBy: ['wins', 'vo']),
      BusNode(id: 'sfx', volume: 0.9),
      BusNode(id: 'reels', volume: 0.85),
      BusNode(id: 'wins', volume: 1.0),
      BusNode(id: 'vo', volume: 1.0),
      BusNode(id: 'ui', volume: 0.8),
      BusNode(id: 'ambience', volume: 0.5),
    ]),
    duckingRules: _generateDuckingRules(template),
  );
}

List<DuckingRule> _generateDuckingRules(SlotTemplate template) {
  return [
    DuckingRule(
      source: 'wins',
      target: 'music',
      amount: -12.0,
      attackMs: 50,
      holdMs: 100,
      releaseMs: 500,
    ),
    DuckingRule(
      source: 'vo',
      target: 'music',
      amount: -8.0,
      attackMs: 100,
      holdMs: 50,
      releaseMs: 300,
    ),
    // Add more based on enabled modules
    if (template.hasModule('holdAndWin'))
      DuckingRule(
        source: 'wins',
        target: 'sfx',
        amount: -6.0,
        attackMs: 30,
        holdMs: 50,
        releaseMs: 200,
      ),
  ];
}
```

#### Step 4: Configure ALE Contexts

```dart
ALEConfiguration generateALEConfig(
  SlotTemplate template,
  List<FeatureModule> modules,
) {
  final contexts = <ALEContext>[
    ALEContext(
      id: 'BASE_GAME',
      layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
      defaultLevel: 'L2',
      entryTransition: 'bar',
      exitTransition: 'phrase',
    ),
  ];

  // Add contexts for enabled modules
  if (hasModule('freeSpins', modules)) {
    contexts.add(ALEContext(
      id: 'FREE_SPINS',
      layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
      defaultLevel: 'L3',
      entryStage: 'FS_MUSIC_START',
      exitStage: 'FS_EXIT',
      entryTransition: 'immediate',
      exitTransition: 'bar',
    ));
  }

  if (hasModule('holdAndWin', modules)) {
    contexts.add(ALEContext(
      id: 'HOLD_WIN',
      layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
      defaultLevel: 'L3',
      entryStage: 'HOLD_INTRO',
      exitStage: 'HOLD_EXIT',
      entryTransition: 'immediate',
      exitTransition: 'phrase',
    ));
  }

  // BIG_WIN context always present
  contexts.add(ALEContext(
    id: 'BIG_WIN',
    layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
    defaultLevel: 'L4',
    entryTransition: 'immediate',
    exitTransition: 'phrase',
  ));

  return ALEConfiguration(
    contexts: contexts,
    rules: _generateALERules(modules),
    stability: _generateStabilityConfig(),
    transitions: _generateTransitionProfiles(),
  );
}
```

---

### 16.9 Auto-Wiring System — "Everything Just Works"

Ovo je KLJUČNI deo — kako se SVE automatski povezuje.

#### 16.9.1 Stage → Event → Bus → Audio Chain

```
USER ACTION                     FLUXFORGE AUTO-GENERATES
────────────────────────────────────────────────────────────────────

Apply Template                  → Creates 166 StageDefinitions
                                → Creates 166 EventTemplates
                                → Links Stage.id ↔ EventTemplate.stage
                                → Sets EventTemplate.bus from StageDefinition.defaultBus
                                → Sets EventTemplate.priority from StageDefinition.defaultPriority
                                → Sets EventTemplate.pooled from StageDefinition.isPooled

Map Audio File                  → Sets EventTemplate.layers[0].audioPath
(reel_stop.wav → REEL_STOP_0)   → Auto-detects REEL_STOP_1-4 from naming
                                → Applies per-reel pan: -0.8, -0.4, 0.0, 0.4, 0.8

Runtime: REEL_STOP_0 fired      → EventRegistry.triggerStage('REEL_STOP_0')
                                → Finds EventTemplate with stage='REEL_STOP_0'
                                → Gets layers, bus, priority
                                → AudioPlaybackService.playFileToBus(
                                    path: layers[0].audioPath,
                                    bus: 'reels',
                                    priority: 75,
                                    pan: -0.8
                                  )
```

#### 16.9.2 Auto-Registration Flow

```dart
class TemplateApplyService {
  Future<void> applyTemplate(
    SlotTemplate template,
    List<FeatureModule> modules,
    Map<String, String> audioMappings,
  ) async {
    // 1. Generate all configurations
    final stages = generateAllStages(template, modules);
    final events = generateEventTemplates(stages);
    final buses = generateBusRouting(template);
    final ale = generateALEConfig(template, modules);
    final rtpc = generateRTPCConfig(template);

    // 2. Apply audio mappings
    for (final event in events) {
      final audioPath = audioMappings[event.stage];
      if (audioPath != null) {
        event.layers[0].audioPath = audioPath;
      }
    }

    // 3. Register EVERYTHING with providers

    // 3a. Register stages with StageConfigurationService
    StageConfigurationService.instance.registerStages(
      stages.map((s) => s.toStageDefinition()).toList(),
    );

    // 3b. Register events with EventRegistry
    for (final event in events) {
      if (event.layers[0].audioPath != null) {
        EventRegistry.instance.registerEvent(event.toAudioEvent());
      }
    }

    // 3c. Setup bus hierarchy
    BusHierarchyProvider.instance.setBusHierarchy(buses);

    // 3d. Apply ducking rules
    DuckingService.instance.setRules(buses.duckingRules);

    // 3e. Configure ALE
    AleProvider.instance.loadConfiguration(ale);

    // 3f. Setup RTPC curves
    RtpcSystemProvider.instance.setConfiguration(rtpc);

    // 4. DONE — Everything is wired and ready
    debugPrint('[TemplateApply] ✅ Applied template with ${stages.length} stages');
  }
}
```

#### 16.9.3 Automatic Event Triggering

Kada SlotLabProvider emituje stage, EventRegistry automatski pronalazi i svira audio:

```dart
// SlotLabProvider (from spin result)
void _broadcastStage(String stageType) {
  notifyListeners();

  // EventRegistry automatically picks this up via listener
  // No manual triggering needed — it's wired at apply time
}

// EventRegistry (in constructor, wired during apply)
void _onSlotLabStageChange() {
  final stages = slotLabProvider.lastStages;
  for (final stage in stages) {
    triggerStage(stage.stageType);
  }
}

// triggerStage already knows what to do
void triggerStage(String stage) {
  final event = _findEventForStage(stage);
  if (event != null) {
    _playEvent(event);
  } else {
    // Stage exists but no audio mapped — show warning
    _logUnmappedStage(stage);
  }
}
```

---

### 16.10 Template Builder UI

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  MODULAR TEMPLATE BUILDER                                         [×]      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  BASE TEMPLATE                                                              │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                             │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐               │
│  │ Classic │ │ Standard│ │Megaways │ │ Hold &  │ │ Cascade │               │
│  │  3×3    │ │  5×3  ●│ │  6×7    │ │   Win   │ │ Tumble  │               │
│  │ 55 stg  │ │ 125 stg │ │ 185 stg │ │ 155 stg │ │ 145 stg │               │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘               │
│                                                                             │
│  FEATURE MODULES                                                            │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                             │
│  Core Features                           Bonus Features                     │
│  ┌────────────────────────────────┐     ┌────────────────────────────────┐ │
│  │ [✓] Free Spins        +19 stg │     │ [✓] Hold & Win        +31 stg │ │
│  │     RTP +0.5%  Vol: ↑ Low     │     │     RTP +2.0%  Vol: ↑↑↑ High  │ │
│  │                               │     │     +5 symbols (COIN, JP_*)    │ │
│  │ [ ] Free Spins + Mult +29 stg │     │                                │ │
│  │     RTP +1.0%  Vol: ↑↑ Med    │     │ [ ] Hold & Respin     +16 stg │ │
│  │                               │     │     RTP +0.8%  Vol: ↑ Med      │ │
│  │ [ ] Respin            +7 stg  │     │     ⚠️ Conflicts with H&W     │ │
│  │     RTP +0.3%  Vol: —         │     │                                │ │
│  │                               │     │ [ ] Bonus Wheel       +30 stg │ │
│  │ [ ] Wild Expansion    +8 stg  │     │     RTP +1.5%  Vol: ↑↑ High   │ │
│  │     RTP +0.4%  Vol: ↑ Low     │     │     +1 symbol (BONUS)          │ │
│  │                               │     │                                │ │
│  │ [ ] Sticky Wilds      +6 stg  │     │ [ ] Pick Bonus        +20 stg │ │
│  │     RTP +0.3%  Vol: —         │     │     RTP +1.0%  Vol: ↑ Med      │ │
│  └────────────────────────────────┘     └────────────────────────────────┘ │
│                                                                             │
│  Cascade/Tumble                          Jackpot                            │
│  ┌────────────────────────────────┐     ┌────────────────────────────────┐ │
│  │ [ ] Cascade (Basic)   +12 stg │     │ [ ] Jackpot 4-tier    +29 stg │ │
│  │     RTP +0.8%  Vol: ↑ Med     │     │     RTP +1.5%  Vol: ↑↑↑ VHigh │ │
│  │                               │     │     +4 symbols (JP_*)          │ │
│  │ [ ] Cascade + Mult    +22 stg │     │                                │ │
│  │     RTP +1.5%  Vol: ↑↑ High   │     │ [ ] Mystery Jackpot   +15 stg │ │
│  │     +1 symbol (MULT)          │     │     RTP +0.8%  Vol: ↑↑ High   │ │
│  └────────────────────────────────┘     │     ⚠️ Conflicts with 4-tier │ │
│                                         └────────────────────────────────┘ │
│  Utility                                                                    │
│  ┌────────────────────────────────┐                                        │
│  │ [✓] Multiplier System +10 stg │                                        │
│  │     RTP +0.5%  Vol: ↑ Low     │                                        │
│  └────────────────────────────────┘                                        │
│                                                                             │
│  ═══════════════════════════════════════════════════════════════════════    │
│  CALCULATED STATS                                                           │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                             │
│  Total Stages:     166  (Base: 125 + Modules: 41)                          │
│  Total Symbols:    18   (Base: 13 + Added: 5)                              │
│  Estimated RTP:    97.0% (Base: 94.5% + Modules: +2.5%)                    │
│  Volatility:       High ↑↑↑ (from Medium)                                  │
│  Hit Frequency:    ~25% (adjusted for volatility)                          │
│  Max Win:          15,000x (Base: 5,000x × H&W jackpot potential)          │
│                                                                             │
│  MODULE INTERACTIONS                                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ✓ Free Spins + Hold & Win → +8 interaction stages                  │   │
│  │   FS_HOLD_TRIGGER, FS_HOLD_INTRO, FS_HOLD_EXIT, etc.                │   │
│  │                                                                     │   │
│  │ ✓ Free Spins + Multiplier → +3 interaction stages                  │   │
│  │   FS_MULTIPLIER_CARRY, FS_MULTIPLIER_BOOST, etc.                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│              [Cancel]                              [Build Template →]       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 16.11 Module Data Schema

```json
{
  "modules": [
    {
      "id": "freeSpins",
      "name": "Free Spins",
      "category": "core",
      "description": "Standard free spins triggered by 3+ Scatters",

      "stageCount": 19,
      "stages": [
        "FS_TRIGGER",
        "FS_SCATTER_COLLECT_1",
        "FS_SCATTER_COLLECT_2",
        "FS_SCATTER_COLLECT_3",
        "FS_INTRO",
        "FS_COUNTER_SHOW",
        "FS_MUSIC_START",
        "FS_SPIN_START",
        "FS_SPIN_END",
        "FS_COUNTER_DECREMENT",
        "FS_RETRIGGER",
        "FS_RETRIGGER_COUNT",
        "FS_LAST_SPIN",
        "FS_OUTRO",
        "FS_TOTAL_WIN",
        "FS_MUSIC_END",
        "FS_EXIT"
      ],

      "additionalSymbols": [
        {
          "id": "SCATTER",
          "type": "scatter",
          "contexts": ["land", "collect", "trigger"]
        }
      ],

      "rtpContribution": 0.5,
      "volatilityImpact": 10,
      "hitFrequencyBonus": 0.02,
      "maxWinMultiplier": 1.2,

      "aleContext": {
        "id": "FREE_SPINS",
        "defaultLevel": "L3",
        "entryStage": "FS_MUSIC_START",
        "exitStage": "FS_EXIT"
      },

      "eventTemplates": [
        {
          "stage": "FS_TRIGGER",
          "bus": "sfx",
          "priority": 90,
          "pooled": false
        }
      ],

      "interactions": {
        "holdAndWin": {
          "stages": [
            "FS_HOLD_TRIGGER",
            "FS_HOLD_INTRO",
            "FS_HOLD_EXIT",
            "FS_HOLD_BONUS_COINS",
            "HOLD_FS_RETRIGGER",
            "HOLD_FS_SCATTER_LAND",
            "MUSIC_FS_HOLD",
            "ALE_FS_HOLD_BLEND"
          ]
        },
        "cascade": {
          "stages": [
            "FS_CASCADE_START",
            "FS_CASCADE_MULTIPLIER",
            "FS_CASCADE_MEGA",
            "CASCADE_FS_CONTEXT",
            "MUSIC_FS_CASCADE"
          ]
        }
      },

      "conflicts": []
    },

    {
      "id": "holdAndWin",
      "name": "Hold & Win",
      "category": "bonus",
      "description": "Full Hold & Win with 4-tier jackpots",

      "stageCount": 31,
      "stages": ["HOLD_TRIGGER", "HOLD_INTRO", "..."],

      "additionalSymbols": [
        {"id": "COIN", "type": "coin", "contexts": ["land", "lock", "collect"]},
        {"id": "JACKPOT_MINI", "type": "jackpot", "contexts": ["land", "lock", "win"]},
        {"id": "JACKPOT_MINOR", "type": "jackpot", "contexts": ["land", "lock", "win"]},
        {"id": "JACKPOT_MAJOR", "type": "jackpot", "contexts": ["land", "lock", "win"]},
        {"id": "JACKPOT_GRAND", "type": "jackpot", "contexts": ["land", "lock", "win"]}
      ],

      "rtpContribution": 2.0,
      "volatilityImpact": 30,
      "hitFrequencyBonus": 0.01,
      "maxWinMultiplier": 3.0,

      "conflicts": ["holdAndRespin"]
    }
  ]
}
```

---

### 16.12 Implementation File Structure

```
flutter_ui/lib/
├── models/
│   ├── template_models.dart           # SlotTemplate, FeatureModule
│   ├── module_models.dart             # Module definitions
│   └── calculated_stats_models.dart   # RTP, Volatility, MaxWin
├── services/
│   ├── template_builder_service.dart  # Build custom templates
│   ├── module_resolver_service.dart   # Resolve conflicts, interactions
│   ├── stats_calculator_service.dart  # RTP, Vol, HitFreq, MaxWin
│   └── auto_wire_service.dart         # Wire everything together
├── providers/
│   └── template_builder_provider.dart # State management
├── widgets/
│   └── template/
│       ├── template_builder.dart      # Main builder widget
│       ├── module_selector.dart       # Module toggle UI
│       ├── conflict_dialog.dart       # Conflict resolution
│       ├── stats_panel.dart           # Calculated stats display
│       └── interaction_preview.dart   # Module interaction preview
└── data/
    └── modules/
        ├── free_spins.json
        ├── hold_and_win.json
        ├── cascade.json
        ├── jackpot.json
        └── ...
```

---

### 16.13 Summary — What Makes This "Ultimate"

| Aspekt | Rešenje |
|--------|---------|
| **Zero Hardcoding** | SVE iz JSON konfiguracije |
| **One Click Apply** | User bira module, klikne Apply, SVE radi |
| **Auto-Calculation** | RTP, Vol, HitFreq, MaxWin automatski računati |
| **Auto-Wiring** | Stage→Event→Bus→Audio chain automatski povezan |
| **Module Interactions** | Kombinacije modula generišu dodatne stage-ove |
| **Conflict Resolution** | UI jasno prikazuje konflikte i traži izbor |
| **User Customization** | Tier labels, thresholds, colors — sve user-defined |
| **ALE Integration** | Konteksti automatski kreirani za svaki modul |
| **Ducking Rules** | Automatski podešeni na osnovu modula |
| **RTPC Curves** | winMultiplier krive automatski konfigurisane |
| **Audio Mapping** | Smart auto-mapper + manual override |
| **Preview** | Pre-apply preview svih stage-ova i statistika |

**Total Implementation:** ~4,200 LOC (Phase 1-6 from Section 10) + ~1,800 LOC (Modular Builder) = **~6,000 LOC**

---

## 17. Auto-Mapping Naming Conventions

### 17.1 Filozofija

FluxForge koristi **intent-based pattern matching** za automatsko mapiranje audio fajlova na stage-ove.

**Prioritet:**
1. Exact match (highest)
2. Pattern match with index
3. Pattern match without index
4. Fuzzy match (lowest)

---

### 17.2 Naming Patterns

#### Spin Flow

| Stage | Recognized Patterns |
|-------|---------------------|
| SPIN_START | `spin_start`, `spin_button`, `spin_press`, `spin_click`, `ui_spin`, `btn_spin` |
| SPIN_END | `spin_end`, `spin_stop`, `spin_complete`, `spin_finish` |
| REEL_SPINNING | `spin_loop`, `reel_spin`, `reel_loop`, `spinning`, `reels_spinning` |

#### Reel Stops

| Stage | Recognized Patterns |
|-------|---------------------|
| REEL_STOP_0 | `reel_stop_0`, `reel_stop_1`, `stop_0`, `stop_1`, `land_0`, `land_1`, `reel_land_1` |
| REEL_STOP_1 | `reel_stop_1`, `reel_stop_2`, `stop_1`, `stop_2`, `land_1`, `land_2`, `reel_land_2` |
| REEL_STOP_2 | `reel_stop_2`, `reel_stop_3`, `stop_2`, `stop_3`, `land_2`, `land_3`, `reel_land_3` |
| REEL_STOP_3 | `reel_stop_3`, `reel_stop_4`, `stop_3`, `stop_4`, `land_3`, `land_4`, `reel_land_4` |
| REEL_STOP_4 | `reel_stop_4`, `reel_stop_5`, `stop_4`, `stop_5`, `land_4`, `land_5`, `reel_land_5` |

**Note:** Podržava i 0-indexed i 1-indexed naming.

#### Symbols

| Stage | Recognized Patterns |
|-------|---------------------|
| SYMBOL_LAND_HP1 | `hp1_land`, `land_hp1`, `symbol_hp1`, `high1_land`, `premium1_land` |
| SYMBOL_LAND_WILD | `wild_land`, `land_wild`, `symbol_wild`, `wild_appear` |
| SYMBOL_LAND_SCATTER | `scatter_land`, `land_scatter`, `symbol_scatter`, `scatter_appear` |
| WIN_SYMBOL_HIGHLIGHT_HP1 | `hp1_win`, `win_hp1`, `hp1_highlight`, `highlight_hp1` |

#### Win Levels

| Stage | Recognized Patterns |
|-------|---------------------|
| WIN_LEVEL_1 | `win_1`, `win_level_1`, `small_win`, `win_small`, `win_low` |
| WIN_LEVEL_2 | `win_2`, `win_level_2`, `medium_win`, `win_medium` |
| WIN_LEVEL_3 | `win_3`, `win_level_3`, `nice_win`, `win_nice` |
| WIN_LEVEL_4 | `win_4`, `win_level_4`, `great_win`, `win_great` |
| WIN_LEVEL_5 | `win_5`, `win_level_5`, `amazing_win`, `win_amazing` |

#### Big Win Tiers

| Stage | Recognized Patterns |
|-------|---------------------|
| BIG_WIN_TIER_1_START | `tier1_start`, `bigwin_start`, `bigwin_1_start`, `bw_tier1_start` |
| BIG_WIN_TIER_1_LOOP | `tier1_loop`, `bigwin_loop`, `bigwin_1_loop`, `bw_tier1_loop` |
| BIG_WIN_TIER_1_END | `tier1_end`, `bigwin_end`, `bigwin_1_end`, `bw_tier1_end` |
| ROLLUP_TIER_1_TICK | `rollup_tick`, `rollup_1_tick`, `counter_tick`, `coins_tick` |
| ROLLUP_TIER_1_END | `rollup_end`, `rollup_1_end`, `counter_end`, `coins_end` |

#### Free Spins

| Stage | Recognized Patterns |
|-------|---------------------|
| FS_TRIGGER | `fs_trigger`, `freespin_trigger`, `free_spin_trigger`, `scatter_trigger` |
| FS_INTRO | `fs_intro`, `freespin_intro`, `free_spin_intro`, `fs_start` |
| FS_SPIN_START | `fs_spin_start`, `freespin_spin`, `free_spin_spin` |
| FS_RETRIGGER | `fs_retrigger`, `freespin_retrigger`, `fs_more` |
| FS_OUTRO | `fs_outro`, `freespin_outro`, `fs_end`, `freespin_end` |
| FS_TOTAL_WIN | `fs_total`, `fs_total_win`, `freespin_total` |

#### Hold & Win

| Stage | Recognized Patterns |
|-------|---------------------|
| HOLD_TRIGGER | `hold_trigger`, `holdwin_trigger`, `hw_trigger`, `coin_trigger` |
| HOLD_INTRO | `hold_intro`, `holdwin_intro`, `hw_intro` |
| HOLD_COIN_LAND | `coin_land`, `hold_coin`, `hw_coin_land` |
| HOLD_COIN_LOCK | `coin_lock`, `hold_lock`, `hw_coin_lock` |
| HOLD_JACKPOT_MINI | `jackpot_mini`, `jp_mini`, `mini_jackpot`, `hold_mini` |
| HOLD_JACKPOT_GRAND | `jackpot_grand`, `jp_grand`, `grand_jackpot`, `hold_grand` |

#### Music

| Stage | Recognized Patterns |
|-------|---------------------|
| MUSIC_BASE | `music_base`, `base_music`, `main_music`, `game_music`, `bg_music` |
| MUSIC_FS | `music_fs`, `fs_music`, `freespin_music`, `free_spin_music` |
| MUSIC_HOLD | `music_hold`, `hold_music`, `holdwin_music`, `hw_music` |
| MUSIC_BIGWIN | `music_bigwin`, `bigwin_music`, `bw_music`, `celebration_music` |

---

### 17.3 Auto-Mapping Algorithm

```dart
class AudioAutoMapper {
  /// Maps audio files to stages
  Map<String, String> autoMap(
    List<String> audioPaths,
    List<StageDefinition> stages,
  ) {
    final mappings = <String, String>{};
    final unmappedStages = stages.toList();

    // Sort by specificity (longer patterns first)
    audioPaths.sort((a, b) => b.length.compareTo(a.length));

    for (final path in audioPaths) {
      final filename = _extractFilename(path);
      final normalizedName = _normalize(filename);

      // Try each matching strategy
      final match = _tryExactMatch(normalizedName, unmappedStages)
          ?? _tryPatternMatchWithIndex(normalizedName, unmappedStages)
          ?? _tryPatternMatch(normalizedName, unmappedStages)
          ?? _tryFuzzyMatch(normalizedName, unmappedStages);

      if (match != null) {
        mappings[match.id] = path;
        unmappedStages.remove(match);
      }
    }

    return mappings;
  }

  String _normalize(String filename) {
    return filename
        .toLowerCase()
        .replaceAll(RegExp(r'\.(wav|mp3|ogg|flac|aiff)$'), '')
        .replaceAll(RegExp(r'[-_\s]+'), '_')
        .trim();
  }

  StageDefinition? _tryExactMatch(String name, List<StageDefinition> stages) {
    return stages.firstWhereOrNull(
      (s) => _normalize(s.id) == name,
    );
  }

  StageDefinition? _tryPatternMatchWithIndex(
    String name,
    List<StageDefinition> stages,
  ) {
    // Extract index from filename
    final indexMatch = RegExp(r'(\d+)$').firstMatch(name);
    if (indexMatch == null) return null;

    final index = int.parse(indexMatch.group(1)!);
    final baseName = name.substring(0, indexMatch.start);

    // Try both 0-indexed and 1-indexed
    for (final stage in stages) {
      final patterns = _getPatternsForStage(stage);
      for (final pattern in patterns) {
        final patternBase = pattern.replaceAll(RegExp(r'\d+$'), '');
        if (baseName.contains(patternBase)) {
          // Check if index matches
          final stageIndex = _extractStageIndex(stage.id);
          if (stageIndex == index || stageIndex == index - 1) {
            return stage;
          }
        }
      }
    }
    return null;
  }

  StageDefinition? _tryPatternMatch(String name, List<StageDefinition> stages) {
    for (final stage in stages) {
      final patterns = _getPatternsForStage(stage);
      for (final pattern in patterns) {
        if (name.contains(pattern)) {
          return stage;
        }
      }
    }
    return null;
  }

  StageDefinition? _tryFuzzyMatch(String name, List<StageDefinition> stages) {
    // Use Levenshtein distance for fuzzy matching
    StageDefinition? bestMatch;
    int bestScore = 0;

    for (final stage in stages) {
      final score = _calculateMatchScore(name, stage);
      if (score > bestScore && score >= 60) { // Minimum 60% match
        bestScore = score;
        bestMatch = stage;
      }
    }

    return bestMatch;
  }

  int _calculateMatchScore(String filename, StageDefinition stage) {
    // Word-based matching
    final filenameWords = filename.split('_').toSet();
    final stageWords = stage.id.toLowerCase().split('_').toSet();

    final intersection = filenameWords.intersection(stageWords);
    final union = filenameWords.union(stageWords);

    // Jaccard similarity * 100
    return ((intersection.length / union.length) * 100).round();
  }
}
```

---

### 17.4 Folder Structure Suggestions

FluxForge preporučuje sledeću strukturu:

```
audio/
├── spin/
│   ├── spin_start.wav
│   ├── spin_loop.wav
│   └── spin_end.wav
├── reels/
│   ├── reel_stop_1.wav
│   ├── reel_stop_2.wav
│   ├── reel_stop_3.wav
│   ├── reel_stop_4.wav
│   └── reel_stop_5.wav
├── symbols/
│   ├── hp1_land.wav
│   ├── hp2_land.wav
│   ├── wild_land.wav
│   ├── scatter_land.wav
│   └── ...
├── wins/
│   ├── win_level_1.wav
│   ├── win_level_2.wav
│   ├── win_level_3.wav
│   ├── win_level_4.wav
│   └── win_level_5.wav
├── bigwin/
│   ├── tier1_start.wav
│   ├── tier1_loop.wav
│   ├── tier1_end.wav
│   ├── tier2_start.wav
│   ├── tier2_loop.wav
│   └── ...
├── rollup/
│   ├── rollup_tick.wav
│   └── rollup_end.wav
├── freespins/
│   ├── fs_trigger.wav
│   ├── fs_intro.wav
│   ├── fs_spin.wav
│   ├── fs_retrigger.wav
│   ├── fs_outro.wav
│   └── fs_total.wav
├── holdwin/
│   ├── hold_trigger.wav
│   ├── hold_intro.wav
│   ├── coin_land.wav
│   ├── coin_lock.wav
│   ├── jp_mini.wav
│   ├── jp_minor.wav
│   ├── jp_major.wav
│   ├── jp_grand.wav
│   └── hold_outro.wav
└── music/
    ├── base_music.wav
    ├── fs_music.wav
    ├── hold_music.wav
    └── bigwin_music.wav
```

---

### 17.5 Auto-Expansion for Per-Reel Stages

Kada user mapira JEDAN generički fajl na per-reel stage, FluxForge automatski kreira 5 kopija sa različitim pan vrednostima:

**Input:**
```
reel_stop.wav → REEL_STOP (generic)
```

**Auto-Expansion:**
```
REEL_STOP_0 → reel_stop.wav (pan: -0.8)
REEL_STOP_1 → reel_stop.wav (pan: -0.4)
REEL_STOP_2 → reel_stop.wav (pan: 0.0)
REEL_STOP_3 → reel_stop.wav (pan: +0.4)
REEL_STOP_4 → reel_stop.wav (pan: +0.8)
```

**Expandable Stage Patterns:**

| Generic Stage | Expands To | Pan Values |
|--------------|------------|------------|
| REEL_STOP | REEL_STOP_0 → 4 | -0.8, -0.4, 0.0, +0.4, +0.8 |
| FS_REEL_STOP | FS_REEL_STOP_0 → 4 | -0.8, -0.4, 0.0, +0.4, +0.8 |
| HOLD_REEL_STOP | HOLD_REEL_STOP_0 → 4 | -0.8, -0.4, 0.0, +0.4, +0.8 |
| WIN_LINE_SHOW | WIN_LINE_SHOW_0 → 4 | -0.8, -0.4, 0.0, +0.4, +0.8 |
| CASCADE_STEP | CASCADE_STEP_0 → 15 | 0.0 (center all) |
| SYMBOL_LAND | SYMBOL_LAND_* (per symbol) | 0.0 (center all) |

---

### 17.6 Mapping UI

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  AUDIO MAPPING                                        [Auto-Map] [Clear]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Auto-mapped: 72/166 stages (43%)                                           │
│  ██████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░       │
│                                                                             │
│  ┌───────────────────────┬────────────────────────────────┬────────────┐   │
│  │ STAGE                 │ MAPPED FILE                    │ STATUS     │   │
│  ├───────────────────────┼────────────────────────────────┼────────────┤   │
│  │ SPIN_START            │ spin/spin_start.wav            │ ✓ Exact    │   │
│  │ SPIN_END              │ spin/spin_end.wav              │ ✓ Exact    │   │
│  │ REEL_STOP_0           │ reels/reel_stop_1.wav          │ ✓ Index    │   │
│  │ REEL_STOP_1           │ reels/reel_stop_2.wav          │ ✓ Index    │   │
│  │ REEL_STOP_2           │ reels/reel_stop_3.wav          │ ✓ Index    │   │
│  │ REEL_STOP_3           │ reels/reel_stop_4.wav          │ ✓ Index    │   │
│  │ REEL_STOP_4           │ reels/reel_stop_5.wav          │ ✓ Index    │   │
│  │ SYMBOL_LAND_HP1       │ symbols/hp1_land.wav           │ ✓ Pattern  │   │
│  │ SYMBOL_LAND_WILD      │ symbols/wild_land.wav          │ ✓ Pattern  │   │
│  │ WIN_LEVEL_1           │ wins/win_level_1.wav           │ ✓ Exact    │   │
│  │ ...                   │ ...                            │            │   │
│  │ FS_TRIGGER            │ (click to map)                 │ ⚠ Unmapped│   │
│  │ FS_INTRO              │ (click to map)                 │ ⚠ Unmapped│   │
│  └───────────────────────┴────────────────────────────────┴────────────┘   │
│                                                                             │
│  FILTER: [All ▼] [✓ Auto-mapped] [⚠ Unmapped Only]                         │
│                                                                             │
│  BATCH ACTIONS:                                                             │
│  [Map Folder to Category...]  [Clear Category...]  [Reset All]              │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                           [← Back] [Next →] │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 18. Complete System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                     │
│  ╔═══════════════════════════════════════════════════════════════════════════════╗ │
│  ║  STEP 1: Template Selection                                                   ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════╝ │
│                                                                                     │
│  User → Opens Template Gallery → Selects "Standard 5×3 Video"                       │
│                                                                                     │
│  ╔═══════════════════════════════════════════════════════════════════════════════╗ │
│  ║  STEP 2: Module Selection                                                     ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════╝ │
│                                                                                     │
│  User → Clicks [+] Hold & Win → Clicks [+] Multiplier System                        │
│       → Sees conflict if any → Resolves conflict                                    │
│       → Sees calculated stats (RTP, Vol, MaxWin)                                    │
│       → Clicks [Build Template]                                                     │
│                                                                                     │
│  ╔═══════════════════════════════════════════════════════════════════════════════╗ │
│  ║  STEP 3: FluxForge Auto-Generation (happens instantly, no user action)       ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════╝ │
│                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ generateAllStages()                                                         │   │
│  │ ├── Base: 125 stages (Standard 5×3)                                         │   │
│  │ ├── Module: +31 stages (Hold & Win)                                         │   │
│  │ ├── Module: +10 stages (Multiplier)                                         │   │
│  │ ├── Interaction: +8 stages (FS + H&W)                                       │   │
│  │ └── Total: 174 stages                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                              ↓                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ generateEventTemplates()                                                    │   │
│  │ ├── Creates 174 EventTemplate objects                                       │   │
│  │ ├── Links stage → event ID                                                  │   │
│  │ ├── Sets bus, priority, pooled from StageDefinition                         │   │
│  │ └── Leaves audioPath = null (user maps later)                               │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                              ↓                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ generateBusRouting()                                                        │   │
│  │ ├── MASTER → music, sfx, reels, wins, vo, ui, ambience                      │   │
│  │ └── Ducking rules: wins→music (-12dB), vo→music (-8dB)                      │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                              ↓                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ generateALEConfig()                                                         │   │
│  │ ├── Context: BASE_GAME (default L2, entry: bar, exit: phrase)               │   │
│  │ ├── Context: FREE_SPINS (default L3, entry: immediate, exit: bar)           │   │
│  │ ├── Context: HOLD_WIN (default L3, entry: immediate, exit: phrase)          │   │
│  │ ├── Context: BIG_WIN (default L4, entry: immediate, exit: phrase)           │   │
│  │ └── Rules: winMultiplier triggers, respinsRemaining triggers                │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                              ↓                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ generateRTPCConfig()                                                        │   │
│  │ ├── RTPC: winMultiplier (0 → ∞)                                             │   │
│  │ ├── Curve: volume (logarithmic, 0.5 → 1.2)                                  │   │
│  │ ├── Curve: pitch (linear, -0.05 → +0.10)                                    │   │
│  │ └── Curve: rollupSpeed (exponential, 1.0 → 4.0)                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
│  ╔═══════════════════════════════════════════════════════════════════════════════╗ │
│  ║  STEP 4: Audio Import & Mapping                                               ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════╝ │
│                                                                                     │
│  User → Selects audio folder → FluxForge auto-maps 72/174 (41%)                     │
│       → User manually maps remaining 102 stages                                     │
│       → OR ignores some stages (will play silent)                                   │
│                                                                                     │
│  ╔═══════════════════════════════════════════════════════════════════════════════╗ │
│  ║  STEP 5: Configuration (Optional)                                             ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════╝ │
│                                                                                     │
│  User → Adjusts win level thresholds (1.0x, 2.5x, 5.0x, 10.0x, 15.0x)               │
│       → Sets big win tier thresholds (20x, 35x, 50x, 75x, 100x)                     │
│       → Enters tier labels ("BIG WIN!", "SUPER WIN!", etc.)                         │
│       → Toggles: Apply bus routing ✓, Apply ducking ✓, Apply ALE ✓                 │
│                                                                                     │
│  ╔═══════════════════════════════════════════════════════════════════════════════╗ │
│  ║  STEP 6: Apply Template (One Click)                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════╝ │
│                                                                                     │
│  User → Clicks [Apply Template]                                                     │
│                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ TemplateApplyService.applyTemplate()                                        │   │
│  │                                                                             │   │
│  │ 1. StageConfigurationService.registerStages(174 stages)                     │   │
│  │    → All stages now known to the system                                     │   │
│  │                                                                             │   │
│  │ 2. EventRegistry.registerEvents(mapped events)                              │   │
│  │    → Only events with audio are registered                                  │   │
│  │    → Unmapped stages will show ⚠ warning in Event Log                       │   │
│  │                                                                             │   │
│  │ 3. BusHierarchyProvider.setBusHierarchy(buses)                              │   │
│  │    → Bus tree configured                                                    │   │
│  │                                                                             │   │
│  │ 4. DuckingService.setRules(duckingRules)                                    │   │
│  │    → Ducking active                                                         │   │
│  │                                                                             │   │
│  │ 5. AleProvider.loadConfiguration(aleConfig)                                 │   │
│  │    → Music contexts ready                                                   │   │
│  │                                                                             │   │
│  │ 6. RtpcSystemProvider.setConfiguration(rtpcConfig)                          │   │
│  │    → winMultiplier curves active                                            │   │
│  │                                                                             │   │
│  │ 7. SlotLabProjectProvider.importTemplate(template)                          │   │
│  │    → Template data persisted                                                │   │
│  │                                                                             │   │
│  │ ✅ DONE — Everything wired and ready                                        │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
│  ╔═══════════════════════════════════════════════════════════════════════════════╗ │
│  ║  RUNTIME: Stage → Audio (Automatic)                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════╝ │
│                                                                                     │
│  SlotLabProvider.spin()                                                             │
│         ↓                                                                           │
│  Generates stages: [SPIN_START, REEL_SPINNING, REEL_STOP_0, ...]                    │
│         ↓                                                                           │
│  notifyListeners()                                                                  │
│         ↓                                                                           │
│  EventRegistry._onSlotLabStageChange()  [listener wired at apply time]              │
│         ↓                                                                           │
│  For each stage:                                                                    │
│    EventRegistry.triggerStage(stage)                                                │
│         ↓                                                                           │
│    _findEventForStage(stage) → EventTemplate                                        │
│         ↓                                                                           │
│    _playEvent(event):                                                               │
│      - Get layers, bus, priority                                                    │
│      - Apply RTPC modulation (winMultiplier → volume/pitch)                         │
│      - Check ducking state                                                          │
│      - AudioPlaybackService.playFileToBus(                                          │
│          path: layers[0].audioPath,                                                 │
│          bus: event.bus,                                                            │
│          priority: event.priority,                                                  │
│          pan: event.pan,                                                            │
│          volume: rtpcModulatedVolume,                                               │
│          pitch: rtpcModulatedPitch,                                                 │
│        )                                                                            │
│         ↓                                                                           │
│  🔊 AUDIO PLAYS                                                                     │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 19. Final Implementation Checklist

### Phase 1: Core Models (~600 LOC)
- [ ] `template_models.dart` — SlotTemplate, FeatureModule, StageDefinition
- [ ] `module_models.dart` — 14 module definitions
- [ ] `calculated_stats_models.dart` — RTP, Volatility, HitFreq, MaxWin

### Phase 2: Services (~1200 LOC)
- [ ] `template_builder_service.dart` — generateAllStages(), generateEventTemplates()
- [ ] `module_resolver_service.dart` — Conflict detection, interaction stages
- [ ] `stats_calculator_service.dart` — RTP, Vol, HitFreq, MaxWin calculations
- [ ] `auto_mapper_service.dart` — Audio file → stage mapping
- [ ] `auto_wire_service.dart` — Register everything with providers

### Phase 3: Built-in Templates (~1000 LOC JSON)
- [ ] 8 base template JSON files
- [ ] 14 module JSON files
- [ ] Interaction stage definitions

### Phase 4: Gallery UI (~1200 LOC)
- [ ] `template_gallery.dart` — Main gallery view
- [ ] `template_card.dart` — Template preview card
- [ ] `template_preview_dialog.dart` — Detailed preview

### Phase 5: Builder UI (~1500 LOC)
- [ ] `template_builder.dart` — Modular builder main view
- [ ] `module_selector.dart` — Module toggle grid
- [ ] `conflict_dialog.dart` — Conflict resolution UI
- [ ] `stats_panel.dart` — Calculated stats display
- [ ] `interaction_preview.dart` — Module interaction preview

### Phase 6: Apply Wizard (~1000 LOC)
- [ ] `template_apply_wizard.dart` — Multi-step wizard
- [ ] `audio_import_step.dart` — Folder selection
- [ ] `audio_mapping_step.dart` — Auto-map + manual mapping
- [ ] `configuration_step.dart` — Win levels, tier labels
- [ ] `apply_confirmation_step.dart` — Final apply

### Phase 7: Integration (~500 LOC)
- [ ] `template_provider.dart` — State management
- [ ] SlotLab screen integration
- [ ] Menu integration

**TOTAL: ~7,000 LOC**

---

## 20. Ultimate Auto-Wiring System — Deep Dive

### 20.1 Problem Statement

Kada user primeni template, mora **ODMAH** da radi. To znači:

1. Svaki stage koji engine emituje mora imati event listener
2. Svaki event mora znati na koji bus da ide
3. Svaki audio layer mora imati sve parametre (volume, pan, priority)
4. ALE mora znati kada da promeni muziku
5. RTPC mora modulirati volume/pitch na osnovu winMultiplier
6. Ducking mora automatski raditi

**Problem:** Ovo tradicionalno zahteva ručno povezivanje svakog elementa.

**Rešenje:** Auto-wiring koji povezuje SVE automatski.

---

### 20.2 Stage Registration — First Step

Kada se template primeni, PRVI korak je registracija SVIH stage-ova:

```dart
class StageAutoRegistrar {
  void registerAll(BuiltTemplate template) {
    final stageService = StageConfigurationService.instance;

    for (final stage in template.stages) {
      stageService.registerStage(StageDefinition(
        stage: stage.id,
        category: _categorizeStage(stage.id),
        priority: stage.priority,
        bus: _mapBusFromTemplate(stage.bus),
        spatialIntent: _inferSpatialIntent(stage.id),
        pooled: stage.pooled,
        isLooping: stage.isLooping,
        description: stage.description,
      ));
    }

    debugPrint('[AutoWiring] ✅ Registered ${template.stages.length} stages');
  }

  StageCategory _categorizeStage(String stageId) {
    if (stageId.startsWith('SPIN_')) return StageCategory.spin;
    if (stageId.startsWith('REEL_')) return StageCategory.spin;
    if (stageId.startsWith('WIN_')) return StageCategory.win;
    if (stageId.startsWith('BIG_WIN_')) return StageCategory.win;
    if (stageId.startsWith('ROLLUP_')) return StageCategory.win;
    if (stageId.startsWith('FS_')) return StageCategory.feature;
    if (stageId.startsWith('HOLD_')) return StageCategory.hold;
    if (stageId.startsWith('JACKPOT_')) return StageCategory.jackpot;
    if (stageId.startsWith('BONUS_')) return StageCategory.feature;
    if (stageId.startsWith('CASCADE_')) return StageCategory.win;
    if (stageId.startsWith('MUSIC_')) return StageCategory.music;
    if (stageId.startsWith('UI_')) return StageCategory.ui;
    if (stageId.startsWith('SYMBOL_')) return StageCategory.symbol;
    return StageCategory.custom;
  }

  SpatialBus _mapBusFromTemplate(String templateBus) {
    return switch (templateBus) {
      'sfx' => SpatialBus.sfx,
      'music' => SpatialBus.music,
      'reels' => SpatialBus.reels,
      'wins' => SpatialBus.sfx,
      'vo' => SpatialBus.vo,
      'ui' => SpatialBus.ui,
      'ambience' => SpatialBus.ambience,
      _ => SpatialBus.sfx,
    };
  }

  String _inferSpatialIntent(String stageId) {
    // Per-reel stages get spatial intent with reel index
    final reelMatch = RegExp(r'REEL_STOP_(\d+)').firstMatch(stageId);
    if (reelMatch != null) {
      final reelIndex = int.parse(reelMatch.group(1)!);
      return 'reel_stop_$reelIndex';  // AutoSpatial will pan accordingly
    }

    // Feature intents
    if (stageId.contains('FS_')) return 'freespins';
    if (stageId.contains('HOLD_')) return 'holdwin';
    if (stageId.contains('JACKPOT_')) return 'jackpot';
    if (stageId.contains('BIG_WIN_')) return 'bigwin';

    return 'default';
  }
}
```

---

### 20.3 Event Registration — Second Step

Nakon stage registracije, registruju se eventi:

```dart
class EventAutoRegistrar {
  void registerAll(BuiltTemplate template, Map<String, String> audioMappings) {
    final eventRegistry = EventRegistry.instance;

    int registered = 0;
    int skipped = 0;

    for (final stage in template.stages) {
      final audioPath = audioMappings[stage.id];

      if (audioPath == null) {
        // Stage bez audio-a — registrujemo placeholder event
        // koji će triggerovati warning u Event Log
        _registerPlaceholderEvent(stage);
        skipped++;
        continue;
      }

      final event = AudioEvent(
        id: 'evt_${stage.id.toLowerCase()}',
        name: _generateEventName(stage.id),
        stage: stage.id,
        layers: [
          AudioLayer(
            id: 'layer_0',
            audioPath: audioPath,
            volume: 1.0,
            pan: _calculatePan(stage.id),
            delay: 0,
            offsetMs: 0,
            busId: _busToEngineId(stage.bus),
            actionType: stage.isLooping ? ActionType.playLooping : ActionType.play,
          ),
        ],
        duration: null,  // Will be calculated from audio file
        loop: stage.isLooping,
        priority: stage.priority,
      );

      eventRegistry.registerEvent(event);
      registered++;
    }

    debugPrint('[AutoWiring] ✅ Registered $registered events, ⚠️ $skipped stages without audio');
  }

  void _registerPlaceholderEvent(StageDefinition stage) {
    // Placeholder event that shows warning in Event Log
    final eventRegistry = EventRegistry.instance;

    eventRegistry.registerStagePlaceholder(
      stage.id,
      warningMessage: 'No audio mapped for ${stage.id}',
    );
  }

  double _calculatePan(String stageId) {
    // Per-reel panning
    final reelMatch = RegExp(r'REEL_STOP_(\d+)').firstMatch(stageId);
    if (reelMatch != null) {
      final reelIndex = int.parse(reelMatch.group(1)!);
      // Formula: (reelIndex - 2) * 0.4 for 5 reels
      // Reel 0: -0.8, Reel 1: -0.4, Reel 2: 0.0, Reel 3: +0.4, Reel 4: +0.8
      return (reelIndex - 2) * 0.4;
    }

    // Win line panning (same formula)
    final lineMatch = RegExp(r'WIN_LINE_SHOW_(\d+)').firstMatch(stageId);
    if (lineMatch != null) {
      final lineIndex = int.parse(lineMatch.group(1)!);
      return (lineIndex - 2) * 0.4;
    }

    // Center for everything else
    return 0.0;
  }

  int _busToEngineId(String bus) {
    return switch (bus) {
      'sfx' => 2,
      'music' => 1,
      'reels' => 2,  // Reels uses SFX bus
      'wins' => 2,   // Wins uses SFX bus
      'vo' => 3,
      'ui' => 4,
      'ambience' => 5,
      _ => 0,  // Master
    };
  }

  String _generateEventName(String stageId) {
    // Convert SPIN_START → onSpinStart
    // Convert REEL_STOP_0 → onReelStop0
    // Convert BIG_WIN_TIER_1_START → onBigWinTier1Start

    final parts = stageId.toLowerCase().split('_');
    final camelCase = parts.mapIndexed((i, part) {
      if (i == 0) return part;
      return part[0].toUpperCase() + part.substring(1);
    }).join('');

    return 'on${camelCase[0].toUpperCase()}${camelCase.substring(1)}';
  }
}
```

---

### 20.4 Bus Hierarchy Setup — Third Step

```dart
class BusAutoConfigurator {
  void configure(BuiltTemplate template) {
    final busProvider = BusHierarchyProvider.instance;

    // Clear existing
    busProvider.clearAll();

    // Create standard bus hierarchy
    busProvider.createBus(AudioBus(
      id: 'master',
      name: 'Master',
      engineIndex: 0,
      children: ['music', 'sfx', 'vo', 'ui', 'ambience'],
    ));

    busProvider.createBus(AudioBus(
      id: 'music',
      name: 'Music',
      engineIndex: 1,
      parent: 'master',
      children: [],
    ));

    busProvider.createBus(AudioBus(
      id: 'sfx',
      name: 'SFX',
      engineIndex: 2,
      parent: 'master',
      children: ['reels', 'wins'],
    ));

    // Sub-buses
    busProvider.createBus(AudioBus(
      id: 'reels',
      name: 'Reels',
      engineIndex: 2,  // Uses SFX engine bus
      parent: 'sfx',
      children: [],
    ));

    busProvider.createBus(AudioBus(
      id: 'wins',
      name: 'Wins',
      engineIndex: 2,  // Uses SFX engine bus
      parent: 'sfx',
      children: [],
    ));

    busProvider.createBus(AudioBus(
      id: 'vo',
      name: 'Voice',
      engineIndex: 3,
      parent: 'master',
      children: [],
    ));

    busProvider.createBus(AudioBus(
      id: 'ui',
      name: 'UI',
      engineIndex: 4,
      parent: 'master',
      children: [],
    ));

    busProvider.createBus(AudioBus(
      id: 'ambience',
      name: 'Ambience',
      engineIndex: 5,
      parent: 'master',
      children: [],
    ));

    debugPrint('[AutoWiring] ✅ Bus hierarchy configured: ${busProvider.busCount} buses');
  }
}
```

---

### 20.5 Ducking Rules Setup — Fourth Step

```dart
class DuckingAutoConfigurator {
  void configure(BuiltTemplate template) {
    final duckingService = DuckingService.instance;

    // Clear existing
    duckingService.clearAllRules();

    // Standard ducking rules for slots

    // 1. Wins duck music
    duckingService.addRule(DuckingRule(
      id: 'wins_duck_music',
      sourceBus: 'wins',
      targetBus: 'music',
      duckAmount: -12.0,  // dB
      attackMs: 50,
      releaseMs: 500,
      holdMs: 100,
      curve: DuckingCurve.easeInOut,
      enabled: true,
    ));

    // 2. Voice ducks music
    duckingService.addRule(DuckingRule(
      id: 'vo_duck_music',
      sourceBus: 'vo',
      targetBus: 'music',
      duckAmount: -8.0,
      attackMs: 30,
      releaseMs: 300,
      holdMs: 50,
      curve: DuckingCurve.easeOut,
      enabled: true,
    ));

    // 3. Voice ducks SFX (slightly)
    duckingService.addRule(DuckingRule(
      id: 'vo_duck_sfx',
      sourceBus: 'vo',
      targetBus: 'sfx',
      duckAmount: -4.0,
      attackMs: 20,
      releaseMs: 200,
      holdMs: 30,
      curve: DuckingCurve.linear,
      enabled: true,
    ));

    // 4. Big Win ducks everything except wins
    duckingService.addRule(DuckingRule(
      id: 'bigwin_duck_ambience',
      sourceBus: 'wins',  // Big win sounds come from wins bus
      targetBus: 'ambience',
      duckAmount: -18.0,
      attackMs: 50,
      releaseMs: 1000,
      holdMs: 500,
      curve: DuckingCurve.easeInOut,
      enabled: true,
      condition: 'isBigWin',  // Only when big win is active
    ));

    // 5. Feature modules may add their own rules
    if (template.hasModule('holdAndWin')) {
      duckingService.addRule(DuckingRule(
        id: 'hold_duck_music',
        sourceBus: 'sfx',
        targetBus: 'music',
        duckAmount: -10.0,
        attackMs: 100,
        releaseMs: 800,
        holdMs: 200,
        curve: DuckingCurve.easeInOut,
        enabled: true,
        condition: 'isHoldActive',
      ));
    }

    debugPrint('[AutoWiring] ✅ Ducking rules configured: ${duckingService.ruleCount} rules');
  }
}
```

---

### 20.6 ALE Context Setup — Fifth Step

```dart
class AleAutoConfigurator {
  void configure(BuiltTemplate template) {
    final aleProvider = AleProvider.instance;

    // Clear existing
    aleProvider.clearConfiguration();

    // Base Game context (always present)
    aleProvider.addContext(AleContext(
      id: 'BASE_GAME',
      displayName: 'Base Game',
      layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
      defaultLevel: 'L2',
      entryTransition: AleTransition.bar,
      exitTransition: AleTransition.phrase,
    ));

    // Free Spins context (if module enabled)
    if (template.hasModule('freeSpins') || template.hasModule('freeSpinsMultiplier')) {
      aleProvider.addContext(AleContext(
        id: 'FREE_SPINS',
        displayName: 'Free Spins',
        layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
        defaultLevel: 'L3',  // Higher energy in FS
        entryTransition: AleTransition.immediate,
        exitTransition: AleTransition.bar,
      ));

      // Rule: Enter FS context on FS_MUSIC_START
      aleProvider.addRule(AleRule(
        id: 'enter_fs',
        condition: AleCondition(
          signal: 'stageTriggered',
          operator: AleOperator.equals,
          value: 'FS_MUSIC_START',
        ),
        action: AleAction.enterContext('FREE_SPINS'),
      ));

      // Rule: Exit FS context on FS_EXIT
      aleProvider.addRule(AleRule(
        id: 'exit_fs',
        condition: AleCondition(
          signal: 'stageTriggered',
          operator: AleOperator.equals,
          value: 'FS_EXIT',
        ),
        action: AleAction.exitContext(),
      ));
    }

    // Hold & Win context
    if (template.hasModule('holdAndWin') || template.hasModule('holdAndRespin')) {
      aleProvider.addContext(AleContext(
        id: 'HOLD_WIN',
        displayName: 'Hold & Win',
        layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
        defaultLevel: 'L3',
        entryTransition: AleTransition.immediate,
        exitTransition: AleTransition.phrase,
      ));

      aleProvider.addRule(AleRule(
        id: 'enter_hold',
        condition: AleCondition(
          signal: 'stageTriggered',
          operator: AleOperator.equals,
          value: 'HOLD_INTRO',
        ),
        action: AleAction.enterContext('HOLD_WIN'),
      ));

      aleProvider.addRule(AleRule(
        id: 'exit_hold',
        condition: AleCondition(
          signal: 'stageTriggered',
          operator: AleOperator.equals,
          value: 'HOLD_EXIT',
        ),
        action: AleAction.exitContext(),
      ));

      // Rule: Increase intensity based on respins remaining
      aleProvider.addRule(AleRule(
        id: 'hold_tension',
        condition: AleCondition(
          signal: 'respinsRemaining',
          operator: AleOperator.lessThanOrEqual,
          value: 2,
        ),
        action: AleAction.stepUp(),
        cooldownMs: 500,
      ));
    }

    // Big Win context (always present)
    aleProvider.addContext(AleContext(
      id: 'BIG_WIN',
      displayName: 'Big Win',
      layers: ['L1', 'L2', 'L3', 'L4', 'L5'],
      defaultLevel: 'L4',  // High energy for celebration
      entryTransition: AleTransition.immediate,
      exitTransition: AleTransition.phrase,
    ));

    aleProvider.addRule(AleRule(
      id: 'enter_bigwin',
      condition: AleCondition(
        signal: 'winMultiplier',
        operator: AleOperator.greaterThanOrEqual,
        value: template.config.bigWin.threshold,
      ),
      action: AleAction.enterContext('BIG_WIN'),
    ));

    // RTPC-based intensity rules
    aleProvider.addRule(AleRule(
      id: 'winMultiplier_stepUp',
      condition: AleCondition(
        signal: 'winMultiplier',
        operator: AleOperator.greaterThan,
        value: 5.0,
      ),
      action: AleAction.stepUp(),
      cooldownMs: 1000,
    ));

    debugPrint('[AutoWiring] ✅ ALE configured: ${aleProvider.contextCount} contexts, ${aleProvider.ruleCount} rules');
  }
}
```

---

### 20.7 RTPC Configuration — Sixth Step

```dart
class RtpcAutoConfigurator {
  void configure(BuiltTemplate template) {
    final rtpcProvider = RtpcSystemProvider.instance;

    // Clear existing
    rtpcProvider.clearConfiguration();

    // Create winMultiplier RTPC
    rtpcProvider.createRtpc(RtpcDefinition(
      id: 'winMultiplier',
      name: 'Win Multiplier',
      source: RtpcSource.winAmount_dividedBy_betAmount,
      min: 0.0,
      max: 1000.0,  // Theoretical max for jackpots
      defaultValue: 0.0,
    ));

    // Volume curve
    rtpcProvider.addCurve(RtpcCurve(
      rtpcId: 'winMultiplier',
      target: RtpcTarget.volume,
      curveType: RtpcCurveType.logarithmic,
      points: [
        RtpcPoint(rtpc: 0.0, value: 0.5),
        RtpcPoint(rtpc: 1.0, value: 0.8),
        RtpcPoint(rtpc: 5.0, value: 1.0),
        RtpcPoint(rtpc: 20.0, value: 1.2),
        RtpcPoint(rtpc: 100.0, value: 1.3),
      ],
    ));

    // Pitch curve
    rtpcProvider.addCurve(RtpcCurve(
      rtpcId: 'winMultiplier',
      target: RtpcTarget.pitch,
      curveType: RtpcCurveType.linear,
      points: [
        RtpcPoint(rtpc: 0.0, value: -0.05),
        RtpcPoint(rtpc: 1.0, value: 0.0),
        RtpcPoint(rtpc: 10.0, value: 0.10),
        RtpcPoint(rtpc: 50.0, value: 0.15),
      ],
    ));

    // Rollup speed curve
    rtpcProvider.addCurve(RtpcCurve(
      rtpcId: 'winMultiplier',
      target: RtpcTarget.rollupSpeed,
      curveType: RtpcCurveType.exponential,
      points: [
        RtpcPoint(rtpc: 1.0, value: 1.0),
        RtpcPoint(rtpc: 10.0, value: 1.5),
        RtpcPoint(rtpc: 50.0, value: 2.5),
        RtpcPoint(rtpc: 100.0, value: 4.0),
      ],
    ));

    // Bind RTPC to all win-related events
    final winEventPatterns = ['WIN_LEVEL_', 'BIG_WIN_', 'ROLLUP_'];
    for (final pattern in winEventPatterns) {
      rtpcProvider.addBinding(RtpcBinding(
        rtpcId: 'winMultiplier',
        eventPattern: pattern,
        applyVolume: true,
        applyPitch: true,
      ));
    }

    debugPrint('[AutoWiring] ✅ RTPC configured: ${rtpcProvider.rtpcCount} parameters, ${rtpcProvider.curveCount} curves');
  }
}
```

---

### 20.8 The Master Wiring Function

```dart
class TemplateAutoWireService {
  static final instance = TemplateAutoWireService._();
  TemplateAutoWireService._();

  final _stageRegistrar = StageAutoRegistrar();
  final _eventRegistrar = EventAutoRegistrar();
  final _busConfigurator = BusAutoConfigurator();
  final _duckingConfigurator = DuckingAutoConfigurator();
  final _aleConfigurator = AleAutoConfigurator();
  final _rtpcConfigurator = RtpcAutoConfigurator();

  /// Wire EVERYTHING from template + audio mappings
  ///
  /// After this call completes:
  /// - All stages are registered and known
  /// - All events are registered with audio layers
  /// - Bus hierarchy is configured
  /// - Ducking rules are active
  /// - ALE contexts and rules are set
  /// - RTPC parameters and curves are configured
  /// - SlotLabProvider stage changes will automatically trigger audio
  Future<WireResult> wireTemplate(
    BuiltTemplate template,
    Map<String, String> audioMappings,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Register all stages
      _stageRegistrar.registerAll(template);

      // 2. Register all events (with audio mappings)
      _eventRegistrar.registerAll(template, audioMappings);

      // 3. Configure bus hierarchy
      _busConfigurator.configure(template);

      // 4. Configure ducking rules
      _duckingConfigurator.configure(template);

      // 5. Configure ALE contexts and rules
      _aleConfigurator.configure(template);

      // 6. Configure RTPC parameters and curves
      _rtpcConfigurator.configure(template);

      // 7. Connect SlotLabProvider to EventRegistry
      _connectSlotLabToEventRegistry();

      // 8. Initialize RTPC modulation
      _initializeRtpcModulation();

      stopwatch.stop();

      debugPrint('[AutoWiring] ✅ COMPLETE in ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('[AutoWiring]    Stages: ${template.stages.length}');
      debugPrint('[AutoWiring]    Events: ${audioMappings.length} mapped');
      debugPrint('[AutoWiring]    Buses: ${BusHierarchyProvider.instance.busCount}');
      debugPrint('[AutoWiring]    Ducking: ${DuckingService.instance.ruleCount} rules');
      debugPrint('[AutoWiring]    ALE: ${AleProvider.instance.contextCount} contexts');
      debugPrint('[AutoWiring]    RTPC: ${RtpcSystemProvider.instance.rtpcCount} params');

      return WireResult(
        success: true,
        stagesRegistered: template.stages.length,
        eventsMapped: audioMappings.length,
        unmappedStages: template.stages.length - audioMappings.length,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );

    } catch (e, stack) {
      debugPrint('[AutoWiring] ❌ FAILED: $e');
      debugPrint(stack.toString());

      return WireResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  void _connectSlotLabToEventRegistry() {
    final slotLabProvider = SlotLabProvider.instance;
    final eventRegistry = EventRegistry.instance;

    // Remove any existing listener to avoid duplicates
    slotLabProvider.removeListener(_onSlotLabChange);

    // Add listener that triggers events
    slotLabProvider.addListener(_onSlotLabChange);

    debugPrint('[AutoWiring] ✅ SlotLabProvider → EventRegistry connected');
  }

  void _onSlotLabChange() {
    final slotLabProvider = SlotLabProvider.instance;
    final eventRegistry = EventRegistry.instance;

    // Get new stages since last check
    final stages = slotLabProvider.lastStages;

    for (final stage in stages) {
      eventRegistry.triggerStage(stage.stageType);
    }
  }

  void _initializeRtpcModulation() {
    final rtpcProvider = RtpcSystemProvider.instance;
    final rtpcModulation = RtpcModulationService.instance;

    // Connect RTPC to modulation service
    rtpcModulation.connectRtpc('winMultiplier');

    debugPrint('[AutoWiring] ✅ RTPC modulation initialized');
  }
}

class WireResult {
  final bool success;
  final int stagesRegistered;
  final int eventsMapped;
  final int unmappedStages;
  final int elapsedMs;
  final String? error;

  WireResult({
    required this.success,
    this.stagesRegistered = 0,
    this.eventsMapped = 0,
    this.unmappedStages = 0,
    this.elapsedMs = 0,
    this.error,
  });
}
```

---

### 20.9 Validation System

```dart
class TemplateValidationService {
  static final instance = TemplateValidationService._();
  TemplateValidationService._();

  /// Validate that template is fully wired
  ValidationReport validate() {
    final issues = <ValidationIssue>[];

    // 1. Check all stages have events
    _validateStageEventMapping(issues);

    // 2. Check all events have audio
    _validateEventAudioMapping(issues);

    // 3. Check bus hierarchy is complete
    _validateBusHierarchy(issues);

    // 4. Check ducking rules don't conflict
    _validateDuckingRules(issues);

    // 5. Check ALE contexts are reachable
    _validateAleContexts(issues);

    // 6. Check RTPC bindings exist
    _validateRtpcBindings(issues);

    return ValidationReport(
      valid: issues.where((i) => i.severity == Severity.error).isEmpty,
      issues: issues,
    );
  }

  void _validateStageEventMapping(List<ValidationIssue> issues) {
    final stageService = StageConfigurationService.instance;
    final eventRegistry = EventRegistry.instance;

    for (final stage in stageService.allStages) {
      if (!eventRegistry.hasEventForStage(stage.stage)) {
        issues.add(ValidationIssue(
          severity: Severity.warning,
          code: 'UNMAPPED_STAGE',
          message: 'Stage "${stage.stage}" has no event mapping',
          suggestion: 'Map an audio file to this stage or remove it from template',
        ));
      }
    }
  }

  void _validateEventAudioMapping(List<ValidationIssue> issues) {
    final eventRegistry = EventRegistry.instance;

    for (final event in eventRegistry.allEvents) {
      if (event.layers.isEmpty) {
        issues.add(ValidationIssue(
          severity: Severity.error,
          code: 'EVENT_NO_AUDIO',
          message: 'Event "${event.id}" has no audio layers',
          suggestion: 'Add at least one audio layer to this event',
        ));
        continue;
      }

      for (final layer in event.layers) {
        if (layer.audioPath == null || layer.audioPath!.isEmpty) {
          issues.add(ValidationIssue(
            severity: Severity.warning,
            code: 'LAYER_NO_PATH',
            message: 'Event "${event.id}" layer "${layer.id}" has no audio path',
            suggestion: 'Map an audio file to this layer',
          ));
        }
      }
    }
  }

  void _validateBusHierarchy(List<ValidationIssue> issues) {
    final busProvider = BusHierarchyProvider.instance;

    // Check master exists
    if (!busProvider.hasBus('master')) {
      issues.add(ValidationIssue(
        severity: Severity.error,
        code: 'NO_MASTER_BUS',
        message: 'Master bus is missing',
        suggestion: 'Template must define a master bus',
      ));
    }

    // Check all referenced buses exist
    final eventRegistry = EventRegistry.instance;
    for (final event in eventRegistry.allEvents) {
      for (final layer in event.layers) {
        final busId = _engineIdToBusName(layer.busId);
        if (!busProvider.hasBus(busId)) {
          issues.add(ValidationIssue(
            severity: Severity.warning,
            code: 'MISSING_BUS',
            message: 'Event "${event.id}" references bus "$busId" which doesn\'t exist',
            suggestion: 'Add bus "$busId" to bus hierarchy or change event routing',
          ));
        }
      }
    }
  }

  void _validateDuckingRules(List<ValidationIssue> issues) {
    final duckingService = DuckingService.instance;

    // Check for circular ducking
    final rules = duckingService.allRules;
    for (final rule in rules) {
      // Check if there's a reverse rule that would cause feedback
      final reverseRule = rules.firstWhereOrNull(
        (r) => r.sourceBus == rule.targetBus && r.targetBus == rule.sourceBus,
      );

      if (reverseRule != null) {
        issues.add(ValidationIssue(
          severity: Severity.warning,
          code: 'CIRCULAR_DUCKING',
          message: 'Ducking rules "${rule.id}" and "${reverseRule.id}" may cause feedback',
          suggestion: 'Remove one of the rules or adjust attack/release times',
        ));
      }
    }
  }

  void _validateAleContexts(List<ValidationIssue> issues) {
    final aleProvider = AleProvider.instance;

    // Check all contexts have entry/exit rules
    for (final context in aleProvider.allContexts) {
      if (context.id == 'BASE_GAME') continue;  // Base doesn't need rules

      final hasEntryRule = aleProvider.allRules.any(
        (r) => r.action.type == AleActionType.enterContext &&
               r.action.contextId == context.id,
      );

      final hasExitRule = aleProvider.allRules.any(
        (r) => r.action.type == AleActionType.exitContext,
      );

      if (!hasEntryRule) {
        issues.add(ValidationIssue(
          severity: Severity.warning,
          code: 'ALE_NO_ENTRY_RULE',
          message: 'ALE context "${context.id}" has no entry rule',
          suggestion: 'Add a rule that enters this context when appropriate',
        ));
      }

      if (!hasExitRule) {
        issues.add(ValidationIssue(
          severity: Severity.warning,
          code: 'ALE_NO_EXIT_RULE',
          message: 'ALE context "${context.id}" has no exit rule',
          suggestion: 'Add a rule that exits this context when appropriate',
        ));
      }
    }
  }

  void _validateRtpcBindings(List<ValidationIssue> issues) {
    final rtpcProvider = RtpcSystemProvider.instance;

    // Check winMultiplier exists
    if (!rtpcProvider.hasRtpc('winMultiplier')) {
      issues.add(ValidationIssue(
        severity: Severity.error,
        code: 'NO_WIN_MULTIPLIER_RTPC',
        message: 'winMultiplier RTPC is not configured',
        suggestion: 'Template must define winMultiplier RTPC for proper win audio',
      ));
    }

    // Check curves exist
    if (!rtpcProvider.hasCurve('winMultiplier', RtpcTarget.volume)) {
      issues.add(ValidationIssue(
        severity: Severity.warning,
        code: 'NO_VOLUME_CURVE',
        message: 'winMultiplier has no volume curve',
        suggestion: 'Add a volume curve for better win audio dynamics',
      ));
    }
  }

  String _engineIdToBusName(int engineId) {
    return switch (engineId) {
      0 => 'master',
      1 => 'music',
      2 => 'sfx',
      3 => 'vo',
      4 => 'ui',
      5 => 'ambience',
      _ => 'unknown',
    };
  }
}

class ValidationReport {
  final bool valid;
  final List<ValidationIssue> issues;

  ValidationReport({required this.valid, required this.issues});

  int get errorCount => issues.where((i) => i.severity == Severity.error).length;
  int get warningCount => issues.where((i) => i.severity == Severity.warning).length;
  int get infoCount => issues.where((i) => i.severity == Severity.info).length;
}

class ValidationIssue {
  final Severity severity;
  final String code;
  final String message;
  final String suggestion;

  ValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    required this.suggestion,
  });
}

enum Severity { error, warning, info }
```

---

### 20.10 Runtime Flow After Wiring

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  RUNTIME AFTER WIRING — AUTOMATIC AUDIO                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  User clicks SPIN button                                                    │
│         ↓                                                                   │
│  SlotLabProvider.spin()                                                     │
│         ↓                                                                   │
│  Engine generates stages: [SPIN_START, REEL_SPINNING, REEL_STOP_0, ...]     │
│         ↓                                                                   │
│  SlotLabProvider.notifyListeners()                                          │
│         ↓                                                                   │
│  TemplateAutoWireService._onSlotLabChange() [wired listener]                │
│         ↓                                                                   │
│  For each new stage:                                                        │
│    │                                                                        │
│    ├─→ EventRegistry.triggerStage('SPIN_START')                             │
│    │         ↓                                                              │
│    │   EventRegistry._findEventForStage('SPIN_START')                       │
│    │         ↓                                                              │
│    │   Found: evt_spin_start (bus: sfx, priority: 70)                       │
│    │         ↓                                                              │
│    │   EventRegistry._playEvent(evt_spin_start)                             │
│    │         ↓                                                              │
│    │   ┌─────────────────────────────────────────────────────────────────┐  │
│    │   │ Get current RTPC values:                                        │  │
│    │   │   winMultiplier = 0.0 (no win yet)                              │  │
│    │   │   volume = 0.5 (from curve)                                     │  │
│    │   │   pitch = -0.05 (from curve)                                    │  │
│    │   │                                                                 │  │
│    │   │ Check ducking:                                                  │  │
│    │   │   No active ducking                                             │  │
│    │   │                                                                 │  │
│    │   │ Play audio:                                                     │  │
│    │   │   AudioPlaybackService.playFileToBus(                           │  │
│    │   │     path: 'spin/spin_start.wav',                                │  │
│    │   │     bus: 2 (SFX),                                               │  │
│    │   │     priority: 70,                                               │  │
│    │   │     volume: 0.5,                                                │  │
│    │   │     pitch: -0.05,                                               │  │
│    │   │     pan: 0.0,                                                   │  │
│    │   │   )                                                             │  │
│    │   └─────────────────────────────────────────────────────────────────┘  │
│    │         ↓                                                              │
│    │   🔊 spin_start.wav PLAYS                                              │
│    │                                                                        │
│    ├─→ EventRegistry.triggerStage('REEL_SPINNING')                          │
│    │         ↓                                                              │
│    │   🔊 reel_spin_loop.wav PLAYS (looping)                                │
│    │                                                                        │
│    ├─→ EventRegistry.triggerStage('REEL_STOP_0')                            │
│    │         ↓                                                              │
│    │   Found: evt_reel_stop_0 (pan: -0.8)                                   │
│    │         ↓                                                              │
│    │   🔊 reel_stop_1.wav PLAYS (panned LEFT)                               │
│    │                                                                        │
│    └─→ ... continues for all stages                                         │
│                                                                             │
│  ON WIN (winAmount = 500, betAmount = 10 → multiplier = 50x):               │
│         ↓                                                                   │
│  RtpcSystemProvider.setValue('winMultiplier', 50.0)                         │
│         ↓                                                                   │
│  Volume curve: 50x → 1.2                                                    │
│  Pitch curve: 50x → 0.15                                                    │
│         ↓                                                                   │
│  EventRegistry.triggerStage('BIG_WIN_TIER_3_START')                         │
│         ↓                                                                   │
│  🔊 tier3_start.wav PLAYS at volume 1.2, pitch +0.15                        │
│         ↓                                                                   │
│  DuckingService activates wins→music (-12dB)                                │
│         ↓                                                                   │
│  🔇 music ducks by -12dB                                                    │
│         ↓                                                                   │
│  AleProvider.enterContext('BIG_WIN')                                        │
│         ↓                                                                   │
│  🎵 Music layer increases to L4                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 20.11 Summary — What "Auto-Wiring" Means

| Aspekt | Automatski | Manualno |
|--------|------------|----------|
| Stage registration | ✅ | — |
| Event creation | ✅ | — |
| Bus routing | ✅ | — |
| Ducking rules | ✅ | — |
| ALE contexts | ✅ | — |
| ALE rules | ✅ | — |
| RTPC parameters | ✅ | — |
| RTPC curves | ✅ | — |
| Audio file mapping | ⚠️ Auto-map | Manual override |
| Win thresholds | ⚠️ Defaults | User configurable |
| Tier labels | — | ✅ User enters |

**After wiring:**
- Spin produces audio ✅
- Reel stops are panned ✅
- Wins trigger celebrations ✅
- Big wins duck music ✅
- Music changes with context ✅
- Volume/pitch scale with win size ✅

**NO additional setup required.**

---

## 21. Implementation Priority

### Phase 0: Core Infrastructure (Must Have First)

```
1. StageConfigurationService — ALREADY EXISTS
2. EventRegistry — ALREADY EXISTS
3. BusHierarchyProvider — ALREADY EXISTS
4. DuckingService — ALREADY EXISTS
5. AleProvider — ALREADY EXISTS
6. RtpcSystemProvider — ALREADY EXISTS

✅ Infrastructure is READY
```

### Phase 1: Auto-Wire Service (~800 LOC)

```
1. TemplateAutoWireService
2. StageAutoRegistrar
3. EventAutoRegistrar
4. BusAutoConfigurator
5. DuckingAutoConfigurator
6. AleAutoConfigurator
7. RtpcAutoConfigurator
```

### Phase 2: Validation Service (~400 LOC)

```
1. TemplateValidationService
2. ValidationReport
3. ValidationIssue
```

### Phase 3: Template Models (~600 LOC)

```
1. SlotTemplate
2. FeatureModule
3. StageDefinition
4. BuiltTemplate
```

### Phase 4: Gallery + Builder UI (~2,500 LOC)

```
1. Template Gallery
2. Template Builder
3. Module Selector
4. Apply Wizard
```

### Phase 5: Built-in Templates (~1,000 LOC JSON)

```
1. 8 base templates
2. 14 modules
```

**TOTAL NEW CODE: ~5,300 LOC**

---

*Dokument verzija: 2.1.0*
*Poslednje ažuriranje: 2026-01-31*

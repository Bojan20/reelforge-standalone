# Special Symbol Audio Behavior — WILD vs SCATTER/BONUS

> Specifikacija audio ponašanja za specijalne simbole u slot mašini.

**Datum:** 2026-01-31
**Status:** ✅ IMPLEMENTED

---

## Overview

Specijalni simboli (WILD, SCATTER, BONUS) imaju različita audio ponašanja jer služe različitim svrhama u slot igri.

| Simbol | Svrha | LAND Event | WIN Priority |
|--------|-------|------------|--------------|
| **WILD** | Zamenjuje druge simbole | ✅ SYMBOL_LAND_WILD | ✅ WIN_SYMBOL_HIGHLIGHT_WILD |
| **SCATTER** | Trigeruje Free Spins | ✅ SYMBOL_LAND_SCATTER | ❌ NE |
| **BONUS** | Trigeruje Bonus igru | ✅ SYMBOL_LAND_BONUS | ❌ NE |

---

## WILD — Win Priority

### Zašto WILD ima Win Priority?

WILD simbol **zamenjuje** druge simbole u dobitnoj kombinaciji. Kada igrač dobije winning line sa:
- HP1 - HP1 - **WILD** - HP1 - HP1

Vizualno vidi HP1 dobitnu liniju, ali WILD je "zaslužan" za taj dobitak jer je zamenio nedostajući HP1.

**Audio pravilo:** Kada je WILD deo dobitne kombinacije, `WIN_SYMBOL_HIGHLIGHT_WILD` ima prioritet.

### Implementacija

```dart
// slot_preview_widget.dart - P0.2 Pre-trigger & _finalizeSpin

// Track WILD symbols in winning positions
bool hasWildInWin = false;
final Set<String> wildPositions = {};

for (final lineWin in result.lineWins) {
  for (final pos in lineWin.positions) {
    final reelIdx = pos[0];
    final rowIdx = pos[1];

    // Check actual symbol on grid (not lineWin.symbolName)
    final actualSymbolId = _targetGrid[reelIdx][rowIdx];
    if (actualSymbolId == 11) { // WILD
      hasWildInWin = true;
      wildPositions.add('$reelIdx,$rowIdx');
    }
  }
}

// Add WILD to winning symbols if present
if (hasWildInWin) {
  _winningSymbolNames.add('WILD');
  _winningPositionsBySymbol['WILD'] = wildPositions;
}
```

---

## SCATTER & BONUS — Land Only

### Zašto SCATTER i BONUS NEMAJU Win Priority?

SCATTER i BONUS simboli **ne zamenjuju** druge simbole. Oni služe za **trigerovanje feature-a**:

- **SCATTER** → Trigeruje Free Spins (obično 3+ scattera)
- **BONUS** → Trigeruje Bonus igru (obično 3+ bonusa)

Njihov audio se pušta kada **slete na reel** (LAND event), ne kada su deo winning kombinacije.

### Implementacija

```dart
// slot_preview_widget.dart - _triggerReelStopAudio()

// When a reel stops, check for special symbols
if (reelIndex < _targetGrid.length) {
  final reelSymbols = _targetGrid[reelIndex];
  for (int rowIndex = 0; rowIndex < reelSymbols.length; rowIndex++) {
    final symbolId = reelSymbols[rowIndex];
    String? symbolLandStage;

    switch (symbolId) {
      case 11: // WILD
        symbolLandStage = 'SYMBOL_LAND_WILD';
        break;
      case 12: // SCATTER
        symbolLandStage = 'SYMBOL_LAND_SCATTER';
        break;
      case 13: // BONUS
        symbolLandStage = 'SYMBOL_LAND_BONUS';
        break;
    }

    if (symbolLandStage != null) {
      eventRegistry.triggerStage(symbolLandStage, context: {
        'reel_index': reelIndex,
        'row_index': rowIndex,
        'symbol_id': symbolId,
      });
    }
  }
}
```

---

## Symbol IDs

Definisano u `StandardSymbolSet` (Rust):

| ID | Symbol | Type |
|----|--------|------|
| 11 | WILD | Substitutes |
| 12 | SCATTER | Triggers Free Spins |
| 13 | BONUS | Triggers Bonus Game |

---

## Stage Registration

`stage_configuration_service.dart`:

```dart
// Special Symbol Lands — Fire when symbols land on reels
_register('SYMBOL_LAND_WILD', StageCategory.symbol, 60, SpatialBus.sfx, 'DEFAULT');
_register('SYMBOL_LAND_SCATTER', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
_register('SYMBOL_LAND_BONUS', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');

// Special Symbol Win Highlights
_register('WIN_SYMBOL_HIGHLIGHT_WILD', StageCategory.win, 65, SpatialBus.sfx, 'WIN_BIG');
// NOTE: SCATTER and BONUS do NOT have win highlight stages
```

---

## Audio Designer Guidelines

### WILD Audio
1. Assign **SYMBOL_LAND_WILD** — Plays when WILD lands on any reel
2. Assign **WIN_SYMBOL_HIGHLIGHT_WILD** — Plays when WILD is part of a winning combination

### SCATTER Audio
1. Assign **SYMBOL_LAND_SCATTER** — Plays when SCATTER lands (each occurrence)
2. For Free Spins trigger, use **FS_TRIGGER** or **FREESPIN_START** stages

### BONUS Audio
1. Assign **SYMBOL_LAND_BONUS** — Plays when BONUS lands (each occurrence)
2. For Bonus game trigger, use **BONUS_TRIGGER** or **BONUS_ENTER** stages

---

## Files Modified

| File | Changes |
|------|---------|
| `slot_preview_widget.dart` | SYMBOL_LAND_* triggers, WILD-only win priority |
| `stage_configuration_service.dart` | Stage registration |

---

## Related Documentation

- `.claude/architecture/SLOT_LAB_AUDIO_FEATURES.md` — All P0/P1 audio features
- `.claude/domains/slot-audio-events-master.md` — Complete stage catalog
- `.claude/architecture/ANTICIPATION_SYSTEM.md` — Scatter-triggered anticipation

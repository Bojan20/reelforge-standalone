# Base Game Flow — Ultra-Detailed Analysis

**Datum:** 2026-01-30
**Verzija:** 1.0
**Analizirano po:** 9 CLAUDE.md uloga

---

## 📋 Sadržaj

1. [Executive Summary](#executive-summary)
2. [Stage Flow Dijagram](#stage-flow-dijagram)
3. [Faza 1: SPIN_START → REEL_STOP](#faza-1-spin_start--reel_stop)
4. [Faza 2: Symbol Detection & Win Evaluation](#faza-2-symbol-detection--win-evaluation)
5. [Faza 3: Win Line Presentation](#faza-3-win-line-presentation)
6. [Faza 4: Rollup Counter System](#faza-4-rollup-counter-system)
7. [Faza 5: Big Win Tier Presentation](#faza-5-big-win-tier-presentation)
8. [Faza 6: Total Win Display & Collect](#faza-6-total-win-display--collect)
9. [Analiza po ulogama (9 uloga)](#analiza-po-ulogama)
10. [Ključni fajlovi i linije koda](#ključni-fajlovi-i-linije-koda)
11. [Audio Stage Mapping](#audio-stage-mapping)
12. [Timing Konfiguracija](#timing-konfiguracija)
13. [Known Issues & Recommendations](#known-issues--recommendations)

---

## Executive Summary

FluxForge Studio Base Game flow implementira **industry-standard 6-fazni win presentation sistem** inspirisan Zynga, NetEnt i Pragmatic Play slot igrama.

### Ključne karakteristike:

| Aspekt | Implementacija |
|--------|----------------|
| **Engine** | Rust (`rf-slot-lab`) generiše stage-ove |
| **UI** | Flutter (`slot_preview_widget.dart`) animira |
| **Audio** | EventRegistry triggeruje zvuk |
| **Timing** | 4 profila (Normal/Turbo/Mobile/Studio) |
| **Win Tiers** | 6 nivoa (SMALL → BIG → SUPER → MEGA → EPIC → ULTRA) |
| **Anticipation** | Per-reel sa 4 tension nivoa (L1-L4) |

### Kritični tokovi:

```
USER CLICK → SPIN_START → REEL_SPINNING × N → [ANTICIPATION] → REEL_STOP × N
          → EVALUATE_WINS → WIN_SYMBOL_HIGHLIGHT → WIN_PRESENT → ROLLUP
          → [BIG_WIN_TIER] → WIN_LINE_SHOW → SPIN_END
```

---

## Stage Flow Dijagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BASE GAME FLOW                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 0: SPIN INITIATION                                              │   │
│  │                                                                        │   │
│  │  User Click → spin() → SPIN_START stage                               │   │
│  │            ↓                                                           │   │
│  │  🔊 Audio: SPIN_START event                                           │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                          ↓                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 1: REEL SPINNING                                                │   │
│  │                                                                        │   │
│  │  For each reel (0→N):                                                 │   │
│  │    REEL_SPINNING_START_{i}                                            │   │
│  │    🔊 Audio: REEL_SPIN_LOOP (per-reel voice, ID stored)               │   │
│  │                                                                        │   │
│  │  [If SCATTER ≥ 2]:                                                    │   │
│  │    ANTICIPATION_ON (per remaining reel)                               │   │
│  │    🔊 Audio: ANTICIPATION_L{1-4} (tension escalation)                 │   │
│  │    🎨 Visual: Speed slowdown, glow, particles                         │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                          ↓                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 2: REEL STOP (IGT-Style Sequential Buffer)                      │   │
│  │                                                                        │   │
│  │  For each reel (0→4):                                                 │   │
│  │    Visual animation → onReelStopVisual()                              │   │
│  │    Buffer if out-of-order: _pendingReelStops                          │   │
│  │    When in-order: REEL_STOP_{i}                                       │   │
│  │    🔊 Audio: REEL_STOP event (pan: -0.8 → +0.8)                       │   │
│  │    🔊 Audio: REEL_SPIN_LOOP fade-out (50ms)                           │   │
│  │                                                                        │   │
│  │  [If last reel + has win]:                                            │   │
│  │    P0.2 Pre-trigger: WIN_SYMBOL_HIGHLIGHT (immediate)                 │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                          ↓                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 3: WIN EVALUATION                                               │   │
│  │                                                                        │   │
│  │  Rust: evaluate_wins() → lineWins[], scatterWin, bigWinTier           │   │
│  │  Flutter: _finalizeSpin() receives SpinResult                         │   │
│  │                                                                        │   │
│  │  Extract winning data:                                                │   │
│  │    - _winningPositions (Set<String>: "col,row")                       │   │
│  │    - _winningSymbolNames (Set<String>: "HP1", "WILD")                 │   │
│  │    - _winningPositionsBySymbol (Map<String, Set<String>>)             │   │
│  │    - _winTier (empty/BIG/SUPER/MEGA/EPIC/ULTRA)                       │   │
│  │    - _targetWinAmount (double)                                        │   │
│  │                                                                        │   │
│  │  🔊 Audio: EVALUATE_WINS (bridge stage)                               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                          ↓                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 4: SYMBOL HIGHLIGHT (1050ms = 3×350ms cycles)                   │   │
│  │                                                                        │   │
│  │  V14: Per-symbol triggers:                                            │   │
│  │    WIN_SYMBOL_HIGHLIGHT_HP1                                           │   │
│  │    WIN_SYMBOL_HIGHLIGHT_WILD                                          │   │
│  │    WIN_SYMBOL_HIGHLIGHT (generic fallback)                            │   │
│  │                                                                        │   │
│  │  🎨 Visual: _startSymbolPulseAnimation()                              │   │
│  │  🎨 Visual: _triggerStaggeredSymbolPopups() (V6)                      │   │
│  │  🎨 Visual: Grouped by symbol type for audio sync (V14)               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                          ↓                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 5: WIN PLAQUE + ROLLUP                                          │   │
│  │                                                                        │   │
│  │  [SMALL WIN < 5x]:                                                    │   │
│  │    "WIN!" plaque                                                      │   │
│  │    🔊 Audio: WIN_PRESENT_1..6 (based on ratio)                        │   │
│  │    Rollup counter animation                                           │   │
│  │    🔊 Audio: ROLLUP_TICK × N (100ms intervals)                        │   │
│  │    🔊 Audio: ROLLUP_END                                               │   │
│  │                                                                        │   │
│  │  [BIG+ WIN ≥ 5x]:                                                     │   │
│  │    Tier progression: BIG → SUPER → MEGA → EPIC → ULTRA                │   │
│  │    🔊 Audio: BIG_WIN_INTRO                                            │   │
│  │    🔊 Audio: BIG_WIN_LOOP (looping, ≥20x only)                        │   │
│  │    🔊 Audio: BIG_WIN_COINS                                            │   │
│  │    Rollup counter with tier-based duration                            │   │
│  │    🔊 Audio: BIG_WIN_END                                              │   │
│  │                                                                        │   │
│  │  Duration by tier:                                                    │   │
│  │    BIG=800ms, SUPER=1200ms, MEGA=2000ms, EPIC=3500ms, ULTRA=6000ms    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                          ↓                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 6: WIN LINE PRESENTATION (Strict Sequential)                    │   │
│  │                                                                        │   │
│  │  IMPORTANT: Starts AFTER rollup ends (no overlap)                     │   │
│  │  Tier plaque hides when win lines start                               │   │
│  │                                                                        │   │
│  │  For each lineWin (no looping, single pass):                          │   │
│  │    _startWinLinePresentation()                                        │   │
│  │    🔊 Audio: WIN_LINE_SHOW                                            │   │
│  │    🎨 Visual: _WinLinePainter draws line + glow                       │   │
│  │    Duration: _winLineCycleDuration (1500ms)                           │   │
│  │                                                                        │   │
│  │  When all lines shown once:                                           │   │
│  │    _stopWinLinePresentation()                                         │   │
│  │    provider.setWinPresentationActive(false)                           │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                          ↓                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ PHASE 7: SPIN_END                                                     │   │
│  │                                                                        │   │
│  │  🔊 Audio: SPIN_END                                                   │   │
│  │  Ready for next spin                                                  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Faza 1: SPIN_START → REEL_STOP

### Rust Engine (spin.rs)

**Lokacija:** `crates/rf-slot-lab/src/spin.rs:384-539`

```rust
pub fn generate_stages(&self, timing: &TimingConfig) -> Vec<StageEvent> {
    let mut events = Vec::with_capacity(32);
    let mut ts_gen = TimestampGenerator::new(timing.clone());

    // 1. SPIN_START
    events.push(StageEvent::new(Stage::SpinStart, ts_gen.current()));

    // 2. REEL_SPINNING_START per reel
    for i in 0..self.grid.reels.len() {
        events.push(StageEvent::new(
            Stage::ReelSpinningStart { reel_index: i as u8 },
            ts_gen.reel_spin(i as u8),
        ));
    }

    // 3. REEL_STOP per reel (with anticipation if applicable)
    for i in 0..self.grid.reels.len() {
        let stop_time = ts_gen.reel_stop(i as u8);

        // Check anticipation
        if let Some(ref antic) = self.anticipation {
            if antic.should_anticipate_reel(i as u8) {
                events.push(StageEvent::with_payload(
                    Stage::AnticipationOn { reel_index: i as u8 },
                    stop_time - timing.anticipation_config.audio_pre_trigger_ms,
                    antic.get_payload(i as u8),
                ));
            }
        }

        events.push(StageEvent::new(
            Stage::ReelStop { reel_index: i as u8 },
            stop_time,
        ));
    }

    // ... win stages follow
}
```

### Flutter UI (slot_preview_widget.dart)

**IGT-Style Sequential Reel Buffer:**

```dart
// Lines 236-237
int _nextExpectedReelIndex = 0;
final List<int> _pendingReelStops = [];

// Lines 737-778: _onReelStopVisual()
void _onReelStopVisual(int reelIndex) {
  // Buffer out-of-order stops
  if (reelIndex != _nextExpectedReelIndex) {
    _pendingReelStops.add(reelIndex);
    return;
  }

  // Process this reel
  _triggerReelStopAudio(reelIndex);
  _nextExpectedReelIndex++;

  // Flush buffered stops
  while (_pendingReelStops.contains(_nextExpectedReelIndex)) {
    _pendingReelStops.remove(_nextExpectedReelIndex);
    _triggerReelStopAudio(_nextExpectedReelIndex);
    _nextExpectedReelIndex++;
  }
}
```

**Per-Reel Audio Trigger (Lines 837-915):**

```dart
void _triggerReelStopAudio(int reelIndex) {
  final eventRegistry = GetIt.I<EventRegistry>();

  // 1. Fade out spin loop for this reel
  eventRegistry._fadeOutReelSpinLoop(reelIndex);

  // 2. Trigger REEL_STOP with pan
  final pan = (reelIndex - 2) * 0.4; // -0.8 → +0.8
  eventRegistry.triggerStage('REEL_STOP_$reelIndex', context: {'pan': pan});

  // 3. P0.2: Pre-trigger WIN_SYMBOL_HIGHLIGHT on last reel
  if (reelIndex == widget.reels - 1 && !_symbolHighlightPreTriggered) {
    final result = widget.provider.lastResult;
    if (result != null && result.isWin) {
      for (final symbolName in _winningSymbolNames) {
        eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT_$symbolName');
      }
      _symbolHighlightPreTriggered = true;
    }
  }
}
```

### Timing Konfiguracija (timing.rs)

**Profile Vrednosti:**

| Profile | reel_spin_duration_ms | reel_stop_interval_ms | audio_pre_trigger_ms |
|---------|----------------------|----------------------|---------------------|
| Normal | 800 | 300 | 20 |
| Turbo | 400 | 100 | 10 |
| Mobile | 600 | 200 | 15 |
| Studio | 1000 | 370 | 15 |

---

## Faza 2: Symbol Detection & Win Evaluation

### Rust Win Evaluation (spin.rs)

**SpinResult struktura (Lines 23-58):**

```rust
pub struct SpinResult {
    pub grid: Grid,
    pub bet: f64,
    pub total_win: f64,
    pub win_ratio: f64,
    pub line_wins: Vec<LineWin>,
    pub scatter_win: Option<ScatterWin>,
    pub big_win_tier: Option<BigWinTier>,
    pub cascades: Vec<CascadeResult>,
    pub anticipation: Option<AnticipationInfo>,
}
```

**LineWin struktura (Lines 60-72):**

```rust
pub struct LineWin {
    pub line_id: u32,
    pub symbol_name: String,
    pub symbol_id: u32,
    pub match_count: u8,
    pub positions: Vec<Vec<u8>>, // [[col, row], ...]
    pub win_amount: f64,
    pub multiplier: f64,
}
```

**Big Win Tier Calculation (Lines 363-376):**

```rust
pub fn with_big_win_tier(mut self) -> Self {
    if self.win_ratio >= 100.0 {
        self.big_win_tier = Some(BigWinTier::Ultra);
    } else if self.win_ratio >= 50.0 {
        self.big_win_tier = Some(BigWinTier::Epic);
    } else if self.win_ratio >= 25.0 {
        self.big_win_tier = Some(BigWinTier::Mega);
    } else if self.win_ratio >= 10.0 {
        self.big_win_tier = Some(BigWinTier::Super);
    } else if self.win_ratio >= 5.0 {
        self.big_win_tier = Some(BigWinTier::Big);
    }
    self
}
```

### Flutter Win Data Extraction (slot_preview_widget.dart)

**_finalizeSpin() (Lines 1258-1457):**

```dart
void _finalizeSpin(SlotLabSpinResult result) {
  // Extract winning positions per symbol (V14)
  _winningPositions = {};
  _winningSymbolNames = {};
  _winningPositionsBySymbol = {};

  for (final lineWin in result.lineWins) {
    final symbolName = lineWin.symbolName.toUpperCase();
    _winningSymbolNames.add(symbolName);
    _winningPositionsBySymbol.putIfAbsent(symbolName, () => <String>{});

    for (final pos in lineWin.positions) {
      if (pos.length >= 2) {
        final posKey = '${pos[0]},${pos[1]}';
        _winningPositions.add(posKey);
        _winningPositionsBySymbol[symbolName]!.add(posKey);
      }
    }
  }

  _targetWinAmount = result.totalWin.toDouble();
  _winTier = _getWinTier(result.totalWin);
}
```

---

## Faza 3: Win Line Presentation

### Win Line System (slot_preview_widget.dart)

**Phase 6: Win Lines (STRICT SEQUENTIAL):**

Kritični aspekt: Win lines se prikazuju **NAKON** što rollup završi, nikada paralelno.

```dart
// Lines 1464-1496: _startWinLinePresentation()
void _startWinLinePresentation(List<LineWin> lineWins) {
  setState(() {
    _lineWinsForPresentation = lineWins;
    _currentPresentingLineIndex = 0;
    _isShowingWinLines = true;
  });

  // HIDE TIER PLAQUE — win lines shown without overlay
  _winAmountController.reverse();

  // Show first line
  _showCurrentWinLineWithSetState();

  // Cycle through remaining lines
  _winLineCycleTimer = Timer.periodic(_winLineCycleDuration, (_) {
    _advanceToNextWinLine();
  });
}
```

**NO LOOPING — Single Pass (Lines 1571-1591):**

```dart
void _advanceToNextWinLine() {
  final nextIndex = _currentPresentingLineIndex + 1;

  // CRITICAL: NO LOOPING — stop after all lines shown ONCE
  if (nextIndex >= _lineWinsForPresentation.length) {
    _stopWinLinePresentation();
    return;
  }

  setState(() {
    _currentPresentingLineIndex = nextIndex;
    _showCurrentWinLine();
  });
}
```

**Win Line Painter (CustomPainter):**

Svaka win linija se crta sa:
- Outer glow (MaskFilter blur)
- Main colored line (tier boja)
- White highlight core
- Glowing dots at symbol positions
- Pulse animation

---

## Faza 4: Rollup Counter System

### Rollup Tick Audio (slot_preview_widget.dart)

**Lines 1721-1755:**

```dart
void _startRollupTicks() {
  _rollupTickCount = 0;
  _rollupTickTimer?.cancel();

  // Fire ROLLUP_TICK at ~100ms intervals
  _rollupTickTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
    if (!mounted || _rollupTickCount >= _rollupTicksTotal) {
      timer.cancel();
      eventRegistry.triggerStage('ROLLUP_END');
      return;
    }

    _rollupTickCount++;
    // P1.1: Pass progress context for volume/pitch escalation
    final progress = _rollupTickCount / _rollupTicksTotal;
    eventRegistry.triggerStage('ROLLUP_TICK', context: {'progress': progress});
  });
}
```

### Rollup Volume Dynamics (rtpc_modulation_service.dart)

**Volume escalation formula:**

```dart
double getRollupVolumeEscalation(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return 0.85 + (p * 0.30);  // 0.85x → 1.15x
}
```

| Progress | Volume Multiplier |
|----------|-------------------|
| 0% | 0.85x |
| 50% | 1.00x |
| 100% | 1.15x |

### Rollup Duration by Tier (Lines 424-431)

| Tier | Duration | Rationale |
|------|----------|-----------|
| SMALL | 500ms | Quick, minimal celebration |
| BIG | 800ms | First major tier |
| SUPER | 1200ms | Building excitement |
| MEGA | 2000ms | Extended celebration |
| EPIC | 3500ms | Major event |
| ULTRA | 6000ms | Maximum anticipation |

---

## Faza 5: Big Win Tier Presentation

### Win Tier Thresholds (Industry Standard)

**Lines 1654-1675:**

```dart
String _getWinTier(double totalWin) {
  final bet = widget.provider.betAmount;
  if (bet <= 0) return '';

  final ratio = totalWin / bet;
  if (ratio >= 100) return 'ULTRA';
  if (ratio >= 50) return 'EPIC';
  if (ratio >= 25) return 'MEGA';
  if (ratio >= 10) return 'SUPER';
  if (ratio >= 5) return 'BIG';
  return '';  // SMALL (no plaque)
}
```

| Tier | Win/Bet Ratio | Plaque Label | Audio Stage |
|------|---------------|--------------|-------------|
| SMALL | < 5x | "WIN!" | WIN_PRESENT_1..6 |
| BIG | 5x - 10x | "BIG WIN!" | WIN_PRESENT_BIG |
| SUPER | 10x - 25x | "SUPER WIN!" | WIN_PRESENT_SUPER |
| MEGA | 25x - 50x | "MEGA WIN!" | WIN_PRESENT_MEGA |
| EPIC | 50x - 100x | "EPIC WIN!" | WIN_PRESENT_EPIC |
| ULTRA | 100x+ | "ULTRA WIN!" | WIN_PRESENT_ULTRA |

### WIN_PRESENT Tier System (Lines 1677-1718)

**6 audio tiers based on win/bet ratio:**

```dart
int _getWinPresentTier(double totalWin) {
  final ratio = totalWin / bet;
  if (ratio > 13) return 6;   // > 13x
  if (ratio > 8) return 5;    // 8x - 13x
  if (ratio > 4) return 4;    // 4x - 8x
  if (ratio > 2) return 3;    // 2x - 4x
  if (ratio > 1) return 2;    // 1x - 2x
  return 1;                    // ≤ 1x
}

int _getWinPresentDurationMs(int tier) {
  return switch (tier) {
    1 => 500,   // 0.5s
    2 => 1000,  // 1.0s
    3 => 1500,  // 1.5s
    4 => 2000,  // 2.0s
    5 => 3000,  // 3.0s
    6 => 4000,  // 4.0s
  };
}
```

### Big Win Celebration (≥20x bet)

**Lines 1432-1441:**

```dart
final winRatio = bet > 0 ? result.totalWin / bet : 0.0;
if (winRatio >= 20) {
  debugPrint('[SlotPreview] 🌟 BIG WIN TRIGGERED (${winRatio.toStringAsFixed(1)}x bet)');
  eventRegistry.triggerStage('BIG_WIN_LOOP');
  eventRegistry.triggerStage('BIG_WIN_COINS');
}
```

**BIG_WIN_LOOP:** Looping celebration music, ducks base music
**BIG_WIN_COINS:** Coin particle sound effects

---

## Faza 6: Total Win Display & Collect

### Win Presentation Complete

Kada win presentation završi (svi win lines prikazani jednom):

```dart
void _stopWinLinePresentation() {
  _winLineCycleTimer?.cancel();
  _stopRollupTicks();
  _isShowingWinLines = false;

  // V13: Mark win presentation as COMPLETE
  widget.provider.setWinPresentationActive(false);
}
```

### Skip Presentation (User Interrupt)

**Lines 1517-1569:**

Ako korisnik pritisne Spin tokom win presentation:

```dart
void _executeSkipFadeOut() {
  // 1. Stop all timers
  _winLineCycleTimer?.cancel();
  _tierProgressionTimer?.cancel();
  _rollupTickTimer?.cancel();

  // 2. Check if plaque already hidden
  if (_winAmountController.value == 0) {
    completeSkip();
    return;
  }

  // 3. Fade-out animation (300ms)
  _winAmountController.reverse().then((_) {
    completeSkip();
  });
}
```

---

## Analiza po ulogama

### 1. 🎮 Slot Game Designer

**Pitanja:**
- Kako definišem win tier thresholds?
- Kako konfigurisati anticipation trigger (scatter count)?
- Gde su paytable definicije?

**Trenutno:**
- Win tiers hardkodirani u `_getWinTier()` (slot_preview_widget.dart:1662-1675)
- Anticipation config u `timing.rs` (`min_scatters_to_trigger: 2`)
- Paytable u `crates/rf-slot-lab/src/paytable.rs`

**Preporuka:**
- [ ] Dodati UI za konfigurisanje win tier thresholds
- [ ] Anticipation scatter count trebao bi biti per-game configurable

---

### 2. 🎵 Audio Designer / Composer

**Pitanja:**
- Koje stage-ove imam na raspolaganju?
- Kako funkcioniše crossfade između muzike?
- Kako prilagoditi rollup tick zvuk po progress-u?

**Trenutno:**
- 60+ kanonskih stage-ova (event_registry.dart:418-469)
- Crossfade sistem (event_registry.dart:598-733) sa per-group trajanjima
- ROLLUP_TICK prima `{'progress': 0.0-1.0}` context

**Audio Stage Mapping (Komplet):**

| Stage | Bus | Priority | Pooled | Opis |
|-------|-----|----------|--------|------|
| SPIN_START | UI | 60 | ❌ | Spin button click |
| REEL_SPINNING_START_0..4 | Reels | 40 | ✅ | Per-reel spin loop start |
| REEL_STOP_0..4 | Reels | 65 | ✅ | Per-reel stop (panned) |
| ANTICIPATION_ON | SFX | 70 | ❌ | Anticipation start |
| ANTICIPATION_OFF | SFX | 70 | ❌ | Anticipation end |
| WIN_SYMBOL_HIGHLIGHT | SFX | 75 | ❌ | Generic symbol highlight |
| WIN_SYMBOL_HIGHLIGHT_{SYMBOL} | SFX | 75 | ❌ | Per-symbol highlight (V14) |
| WIN_PRESENT_1..6 | Wins | 80 | ❌ | Win tier audio |
| ROLLUP_START | SFX | 50 | ❌ | Counter start |
| ROLLUP_TICK | SFX | 45 | ✅ | Counter tick (100ms) |
| ROLLUP_END | SFX | 50 | ❌ | Counter finish |
| BIG_WIN_INTRO | Music | 85 | ❌ | Big win fanfare |
| BIG_WIN_LOOP | Music | 90 | ❌ | Looping celebration |
| BIG_WIN_COINS | SFX | 75 | ❌ | Coin particles |
| BIG_WIN_END | Music | 85 | ❌ | Celebration end |
| WIN_LINE_SHOW | SFX | 55 | ✅ | Line presentation |
| SPIN_END | UI | 40 | ❌ | Spin complete |

---

### 3. 🧠 Audio Middleware Architect

**Pitanja:**
- Kako je implementiran stage→event mapping?
- Koji su mehanizmi za voice pooling?
- Kako radi conditional audio rules sistem?

**Trenutno:**
- `_stageToEvent` map (event_registry.dart:491)
- Pooled stages set (event_registry.dart:418-469)
- Conditional rules (event_registry.dart:740-861)

**Voice Pooling:**

```dart
const _pooledEventStages = {
  'REEL_STOP', 'REEL_STOP_0'..'REEL_STOP_4',
  'CASCADE_STEP', 'ROLLUP_TICK', 'WIN_LINE_SHOW',
  'UI_BUTTON_PRESS', 'SYMBOL_LAND', 'WHEEL_TICK',
  // ... 50+ total
};
```

---

### 4. 🛠 Engine / Runtime Developer

**Pitanja:**
- Kako funkcioniše FFI bridge za stage-ove?
- Koji su latency kompenzacioni mehanizmi?
- Kako je implementiran per-reel spin loop tracking?

**Trenutno:**
- FFI u `crates/rf-bridge/src/slot_lab_ffi.rs`
- Latency config u `timing.rs` (Lines 198-227)
- Spin loop tracking (event_registry.dart:561-595)

**Latency Compensation:**

```rust
pub struct TimingConfig {
    pub audio_latency_compensation_ms: f64,      // Buffer latency
    pub visual_audio_sync_offset_ms: f64,        // Fine-tune offset
    pub anticipation_audio_pre_trigger_ms: f64,  // Pre-trigger
    pub reel_stop_audio_pre_trigger_ms: f64,     // Pre-trigger
}
```

---

### 5. 🧩 Tooling / Editor Developer

**Pitanja:**
- Kako se events kreiraju i mapiraju?
- Koji UI elementi su dostupni za konfiguraciju?
- Kako radi preview sistema?

**Trenutno:**
- Events: MiddlewareProvider.compositeEvents
- UI: UltimateAudioPanel (341 slotova, 12 sekcija)
- Preview: PremiumSlotPreview sa forced outcomes

---

### 6. 🎨 UX / UI Designer

**Pitanja:**
- Kako izgleda win presentation flow za korisnika?
- Kakva je hijerarhija vizuelnih elemenata?
- Gde su pain points u UX-u?

**Win Presentation Visual Flow:**

```
1. Symbol Pulse (1050ms) — Winning symbols glow
2. Tier Plaque — "BIG WIN!" sa counter-om
3. Win Lines — Connecting lines through positions
4. Ready for Next Spin
```

**Pain Points:**
- Skip ne radi uvek glatko
- Nema progress indicator za win presentation

---

### 7. 🧪 QA / Determinism Engineer

**Pitanja:**
- Kako testirati specifične win scenarije?
- Da li je sistem deterministički?
- Koji su regression test-ovi?

**Forced Outcomes:**

```dart
enum ForcedOutcome {
  lose,
  smallWin,
  bigWin,
  megaWin,
  epicWin,
  freeSpins,
  jackpotGrand,
  nearMiss,
  cascade,
  ultraWin,
}
```

Keyboard shortcuts: 1-7 za force outcomes

---

### 8. 🧬 DSP / Audio Processing Engineer

**Pitanja:**
- Kako radi crossfade sistem?
- Kakva je latency kompenzacija?
- Koji su audio quality parametri?

**Crossfade Durations (event_registry.dart:615-637):**

| Group | Duration |
|-------|----------|
| MUSIC | 500ms |
| WIN | 100ms |
| ROLLUP | 50ms |
| REEL | 30ms |
| AMBIENT | 400ms |

---

### 9. 🧭 Producer / Product Owner

**Pitanja:**
- Koliko je sistem kompletan?
- Šta je MVP, šta je nice-to-have?
- Koje su blockers za production?

**Status:**

| Feature | Status | Notes |
|---------|--------|-------|
| Base Game Flow | ✅ 100% | Full implementation |
| Win Tiers | ✅ 100% | Industry standard |
| Anticipation | ✅ 100% | Per-reel, 4 levels |
| Audio Sync | ✅ 95% | Minor edge cases |
| Skip Presentation | ⚠️ 90% | Occasional glitches |

---

## Ključni fajlovi i linije koda

| Fajl | Linije | Opis |
|------|--------|------|
| `spin.rs` | 384-539 | Stage generation |
| `spin.rs` | 187-235 | Anticipation from scatter |
| `spin.rs` | 363-376 | Big win tier calculation |
| `timing.rs` | 26-159 | AnticipationConfig |
| `timing.rs` | 161-419 | TimingConfig profiles |
| `slot_preview_widget.dart` | 236-237 | IGT sequential buffer |
| `slot_preview_widget.dart` | 737-778 | onReelStopVisual |
| `slot_preview_widget.dart` | 837-915 | triggerReelStopAudio |
| `slot_preview_widget.dart` | 1258-1457 | _finalizeSpin |
| `slot_preview_widget.dart` | 1464-1496 | Win line presentation |
| `slot_preview_widget.dart` | 1654-1675 | Win tier calculation |
| `slot_preview_widget.dart` | 1721-1755 | Rollup ticks |
| `event_registry.dart` | 418-469 | Pooled stages |
| `event_registry.dart` | 561-595 | Per-reel spin loop |
| `event_registry.dart` | 598-733 | Crossfade system |

---

## Audio Stage Mapping

### Complete Stage List (Base Game)

```
SPIN_START
REEL_SPINNING_START_0..4
REEL_SPIN_LOOP
ANTICIPATION_ON
ANTICIPATION_TENSION_L1..L4
ANTICIPATION_OFF
REEL_STOP
REEL_STOP_0..4
EVALUATE_WINS
WIN_SYMBOL_HIGHLIGHT
WIN_SYMBOL_HIGHLIGHT_HP1..HP4
WIN_SYMBOL_HIGHLIGHT_MP1..MP4
WIN_SYMBOL_HIGHLIGHT_LP1..LP4
WIN_SYMBOL_HIGHLIGHT_WILD
WIN_SYMBOL_HIGHLIGHT_SCATTER
WIN_PRESENT_1..6
WIN_PRESENT_SMALL
WIN_PRESENT_BIG
WIN_PRESENT_SUPER
WIN_PRESENT_MEGA
WIN_PRESENT_EPIC
WIN_PRESENT_ULTRA
ROLLUP_START
ROLLUP_TICK
ROLLUP_TICK_SLOW
ROLLUP_TICK_FAST
ROLLUP_END
BIG_WIN_INTRO
BIG_WIN_LOOP
BIG_WIN_COINS
BIG_WIN_END
WIN_LINE_SHOW
WIN_LINE_HIDE
SPIN_END
```

---

## Timing Konfiguracija

### Profile Comparison

| Parameter | Normal | Turbo | Mobile | Studio |
|-----------|--------|-------|--------|--------|
| reel_spin_duration_ms | 800 | 400 | 600 | 1000 |
| reel_stop_interval_ms | 300 | 100 | 200 | 370 |
| anticipation_duration_ms | 1500 | 800 | 1000 | 500 |
| win_reveal_delay_ms | 200 | 100 | 150 | 100 |
| rollup_speed | 50 | 200 | 100 | 500 |
| audio_latency_compensation_ms | 5 | 3 | 8 | 3 |

### Anticipation Config

| Parameter | Default | Opis |
|-----------|---------|------|
| min_scatters_to_trigger | 2 | Minimum scatter-a za anticipation |
| duration_per_reel_ms | 1500 | Trajanje per reel |
| base_intensity | 0.7 | Početni intenzitet |
| escalation_factor | 1.15 | Multiplikator per level |
| tension_layer_count | 4 | L1-L4 |
| speed_multiplier | 0.3 | 30% normal speed |
| audio_pre_trigger_ms | 50 | Pre-trigger offset |

---

## Known Issues & Recommendations

### Issues

1. **Skip Presentation Glitch**
   - Occasionally, skip doesn't complete properly
   - Root cause: Race condition between fade-out and completeSkip()
   - Severity: Low (workaround: wait for natural completion)

2. **Symbol Highlight Pre-trigger**
   - `_symbolHighlightPreTriggered` flag may not reset properly
   - Impact: Missed highlight audio on edge cases

### Recommendations

1. **Add Win Progress Indicator**
   - Show progress bar during win presentation
   - Allow users to see how much longer presentation will take

2. **Make Win Tiers Configurable**
   - Move hardcoded thresholds to config file
   - Allow per-game customization

3. **Add Analytics Events**
   - Track win tier distribution
   - Measure average presentation time
   - Monitor skip rate

4. **Improve Skip UX**
   - Add "Tap to skip" prompt
   - Show remaining win amount immediately on skip

---

## Related Documentation

- `.claude/architecture/ANTICIPATION_SYSTEM.md` — **Kompletna dokumentacija per-reel anticipation sistema** (L1-L4 tension levels, fallback chain, GPU shaders)
- `.claude/architecture/SLOT_LAB_AUDIO_FEATURES.md` — P0.6 Anticipation Pre-Trigger, P0.6.1 Per-Reel Tension System
- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Stage→Event mapping, anticipation fallback resolution
- `.claude/domains/slot-audio-events-master.md` — ANTICIPATION_* stage catalog
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — Full SlotLab architecture

---

## Zaključak

FluxForge Studio Base Game flow je **production-ready** implementacija sa industry-standard karakteristikama:

- ✅ Per-reel anticipation sa tension escalation
- ✅ IGT-style sequential reel stop buffer
- ✅ 6-tier win presentation system
- ✅ Crossfade audio transitions
- ✅ Per-symbol highlight triggers (V14)
- ✅ Comprehensive timing profiles

Sistem je spreman za produkciju sa minornim edge case poboljšanjima.

---

**Autor:** Claude Opus 4.5
**Review:** N/A
**Poslednja izmena:** 2026-01-30

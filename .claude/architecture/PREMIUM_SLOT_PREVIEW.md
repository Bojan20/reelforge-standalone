# Premium Slot Preview — Architecture Document

**Date:** 2026-01-24
**Status:** ✅ VISUAL-SYNC IMPLEMENTED (P0+P1+P2+P3 Complete)
**LOC:** ~5,600 total (4,100 + 1,500)

---

## ✅ RESOLVED: Audio-Visual Sync Implemented (2026-01-24)

### Solution Summary

**PremiumSlotPreview (fullscreen)** sada ima Visual-Sync sa EventRegistry integracijom:

| Mode | Visual-Sync | Audio Timing | Status |
|------|-------------|--------------|--------|
| **Normal (EmbeddedSlotMockup)** | ✅ 6 callbacks | Audio prati VIZUAL | ✅ |
| **Fullscreen (PremiumSlotPreview)** | ✅ Timer-based | Audio prati VIZUAL | ✅ FIXED |

### Implemented Methods

| Method | Description |
|--------|-------------|
| `_scheduleVisualSyncCallbacks()` | Schedules SPIN_START + staggered REEL_STOP_0..4 |
| `_checkAnticipation()` | Detects big win → triggers ANTICIPATION_ON |
| `_onAllReelsStopped()` | Triggers REVEAL + appropriate WIN stage |
| `_triggerWinStage()` | Maps win tier → WIN_SMALL/BIG/MEGA/EPIC/ULTRA |

### Triggered Stages

| Stage | When Triggered |
|-------|----------------|
| `SPIN_START` | Immediately on spin button press |
| `REEL_STOP_0..4` | Staggered, when each reel visually stops |
| `ANTICIPATION_ON` | When pending result is big win (MEGA/EPIC/ULTRA) |
| `REVEAL` | When all reels have stopped |
| `WIN_*` | Based on win tier (SMALL/BIG/MEGA/EPIC/ULTRA) |
| `WIN_PRESENT` | On any win for general celebration |

### Timing Calculation

```dart
// Per-reel stop time = staggerStart + animationDuration
final baseDelay = _isTurbo ? 100 : 250;      // Reel stagger
final baseAnimDuration = _isTurbo ? 600 : 1000;  // Spin animation
final staggerDelay = _isTurbo ? 60 : 120;    // Start stagger

// Reel 0: 0 + 1000 + 0 = 1000ms (normal)
// Reel 1: 120 + 1000 + 250 = 1370ms
// Reel 2: 240 + 1000 + 500 = 1740ms
// Reel 3: 360 + 1000 + 750 = 2110ms
// Reel 4: 480 + 1000 + 1000 = 2480ms
```

---

## Visual Improvements (2026-01-24)

### Win Line Painter

Win lines are now drawn as connecting lines through winning symbol positions using `_WinLinePainter` CustomPainter in `slot_preview_widget.dart`.

**Rendering Layers:**
1. **Outer Glow** — MaskFilter blur, 14-18px stroke width
2. **Main Line** — Win tier color, 5-7px stroke width
3. **White Core** — Highlight, 2px stroke width
4. **Position Dots** — Glowing dots at each symbol position

**Animation:** Pulse effect via `_winPulseAnimation.value` (0.0 - 1.0)

### STOP Button

- Spin button shows **"STOP"** (red gradient) when reels are spinning
- Click or press **SPACE** to stop immediately
- Flow: `stopStagePlayback()` → `stopImmediately()` → `_finalizeSpin()`

### Gamble Feature Disabled

- `showGamble: false` in `_WinPresenter`
- Gamble overlay: `if (false && _showGambleScreen)`
- Code preserved for future re-enabling

---

## Overview

Premium Slot Preview je fullscreen casino-grade slot machine UI za SlotLab. Služi kao audio sandbox za dizajnere — omogućava testiranje audio eventa u realističnom okruženju.

**Trigger:** F11 key u SlotLab screen-u

---

## File Structure

| File | LOC | Purpose |
|------|-----|---------|
| `premium_slot_preview.dart` | ~5,700 | Main UI, 8 zones, state management, gamble (disabled) |
| `slot_preview_widget.dart` | ~2,100 | Reel animation, particles, `_WinLinePainter`, STOP button |

---

## 8-Zone Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ A. HEADER (48px) — Menu, Logo, Balance, VIP, Audio, Settings   │
├─────────────────────────────────────────────────────────────────┤
│ B. JACKPOT (30px) — Mini│Minor│Major│Grand + Progressive Meter │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    C. MAIN GAME ZONE                           │
│                    (Reels + Particles)                          │
│                                                                 │
│              ┌─────────────────────────────┐                    │
│              │    D. WIN PRESENTER         │                    │
│              │    (Rollup + Particles)     │                    │
│              └─────────────────────────────┘                    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ E. FEATURE INDICATORS — FS│Bonus│Mult│Cascade│Special│Progress │
├─────────────────────────────────────────────────────────────────┤
│ F. CONTROL BAR (80px) — Lines│Coin│Bet│Spin│MaxBet│Auto│Turbo  │
├──────────┬──────────────────────────────────────────────────────┤
│ G. INFO  │ (Docked left — Paytable, Rules, History, Stats)     │
│ PANELS   │                                                      │
├──────────┴──────────────────────────────────────────────────────┤
│ H. SETTINGS OVERLAY — Volume, Music, SFX, Quality, Animations   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Zone Details

### Zone A: Header (lines 75-222)

| Component | Widget | Status |
|-----------|--------|--------|
| Menu button | `_HeaderIconButton` | ⚠️ Placeholder |
| Logo | FluxForge branding | ✅ Done |
| Balance | `_BalanceDisplay` | ✅ Animated (500ms) |
| VIP badge | `_VipBadge` | ✅ 4-tier colors |
| Music toggle | `_HeaderIconButton` | ⚠️ Visual only |
| SFX toggle | `_HeaderIconButton` | ⚠️ Visual only |
| Settings | `_HeaderIconButton` | ✅ Opens overlay |
| Exit | `_HeaderIconButton` | ✅ Calls onExit() |

### Zone B: Jackpot (lines 457-813)

| Tier | Size | Color | Status |
|------|------|-------|--------|
| MINI | 85px | Green | ✅ Animated |
| MINOR | 100px | Purple | ✅ Animated |
| MAJOR | 115px | Magenta | ✅ Animated |
| GRAND | 140px | Gold | ✅ Animated |
| MYSTERY | 100px | Cyan | ✅ Optional |
| Progressive Meter | 180px | Gold | ✅ Done |

**Jackpot Growth Logic (lines 3278-3292):**
```dart
void _tickJackpots() {
  _miniJackpot += 0.001 * _progressiveContribution;
  _minorJackpot += 0.003 * _progressiveContribution;
  _majorJackpot += 0.008 * _progressiveContribution;
  _grandJackpot += 0.02 * _progressiveContribution;
}
```
⚠️ **Problem:** Hardcoded multipliers, not connected to bet math.

### Zone C: Main Game (lines 831-1221)

| Component | Status | Notes |
|-----------|--------|-------|
| Reel Frame | ✅ Done | AspectRatio 5/3 * 1.2 |
| Ambient Particles | ✅ Done | 40 particles, 4 colors |
| SlotPreviewWidget | ✅ Done | Full animation system |
| Payline Visualizer | ✅ Done | Win line animation |
| Win Highlight Overlay | ✅ Done | Tier-specific glow |
| Anticipation Frame | ✅ Done | Golden pulse |
| Wild Expansion | ⚠️ Placeholder | lines 1115-1130 |
| Scatter Collect | ⚠️ Placeholder | lines 1131-1150 |
| Cascade Layer | ⚠️ Placeholder | lines 1151-1170 |

### Zone D: Win Presenter (lines 1222-1608)

| Feature | Duration | Status |
|---------|----------|--------|
| Rollup animation | 1500ms | ✅ Done |
| Coin particles | 3000ms | ✅ 30 particles |
| Pulse effect | 600ms | ✅ Scale 0.95-1.05 |
| Tier badge | — | ✅ Color-coded |
| Collect button | — | ✅ Connected |
| Gamble button | — | ❌ Disabled (2026-01-24) |

**Win Tier Colors:**
| Tier | Color | Threshold |
|------|-------|-----------|
| ULTRA | #FF4080 | >= $100 |
| EPIC | #E040FB | >= $50 |
| MEGA | #FFD700 | >= $25 |
| BIG | #40FF90 | >= $10 |
| SMALL | #40C8FF | < $10 |

### Zone E: Feature Indicators (lines 1610-1843)

| Indicator | Widget | Status |
|-----------|--------|--------|
| Free Spins | Counter badge | ✅ Done |
| Bonus Meter | Progress bar | ✅ Animated |
| Multiplier | X badge | ✅ Done |
| Cascade Count | Counter | ✅ Done |
| Special Symbols | Counter | ✅ Done |
| Feature Progress | Thin bar | ✅ Done |

### Zone F: Control Bar (lines 1844-2398)

| Control | Type | Range | Status |
|---------|------|-------|--------|
| Lines | Slider | 1-25 | ✅ Done |
| Coin Value | Dropdown | 0.01-1.00 | ✅ Done |
| Bet Level | Slider | 1-10 | ✅ Done |
| Total Bet | Text | Calculated | ✅ Live |
| Spin | Button | — | ✅ Connected |
| Max Bet | Button | — | ✅ Done |
| Auto-spin | Toggle | 0-50 | ✅ Done |
| Turbo | Toggle | On/Off | ✅ Done |

**Bet Calculation:**
```dart
double _totalBetAmount => _lines * _coinValue * _betLevel;
// Example: 25 * 0.10 * 5 = $12.50 per spin
```

### Zone G: Info Panels (lines 2399-2721)

| Panel | Content | Status |
|-------|---------|--------|
| Paytable | Symbol values | ⚠️ Mock data |
| Rules | Game rules | ⚠️ Static text |
| History | Recent 10 wins | ✅ Connected |
| Stats | Session stats | ✅ Connected |

### Zone H: Settings (lines 2722-3130)

| Control | Range | Status |
|---------|-------|--------|
| Master Volume | 0-1.0 | ⚠️ State only |
| Music Toggle | On/Off | ⚠️ State only |
| SFX Toggle | On/Off | ⚠️ State only |
| Quality | Low/Med/High | ✅ State |
| Animations | On/Off | ✅ State |

---

## Reel Animation System (slot_preview_widget.dart)

### Animation Controllers

| Controller | Duration | Purpose |
|-----------|----------|---------|
| `_spinControllers` | 1000ms + 250ms×index | Per-reel staggered spin |
| `_winPulseController` | 600ms reverse | Border glow pulse |
| `_winAmountController` | 800ms elasticOut | Win overlay scale |
| `_winCounterController` | 1500ms | Rollup number |
| `_symbolBounceController` | 400ms elasticOut | Winning symbol jump |
| `_particleController` | 3000ms | Particle system |
| `_anticipationController` | 400ms reverse | Golden border pulse |
| `_nearMissController` | 600ms | Red shake effect |
| `_cascadePopController` | 400ms easeInBack | Symbol pop/shrink |

### Symbol Definitions (10 built-in)

| ID | Symbol | Colors | Special |
|----|--------|--------|---------|
| 0 | WILD ★ | Gold gradient | ✨ Glow |
| 1 | SCATTER ◆ | Magenta gradient | ✨ Glow |
| 2 | BONUS ♦ | Cyan gradient | ✨ Glow |
| 3 | SEVEN 7 | Red gradient | — |
| 4 | BAR ▬ | Green gradient | — |
| 5 | BELL 🔔 | Yellow gradient | — |
| 6 | CHERRY 🍒 | Orange gradient | — |
| 7 | LEMON 🍋 | Yellow gradient | — |
| 8 | ORANGE 🍊 | Orange gradient | — |
| 9 | GRAPE 🍇 | Purple gradient | — |

### Particle System

**Object Pool Pattern (lines 1302-1341):**
- Pool size: max 100 particles
- Reuse instances to reduce GC

**Particle Physics:**
- Gravity: 0.0005 per tick
- Horizontal damping: 0.99
- Life: 1.0 → 0.0 @ 0.015/tick (3s total)

---

## Provider Integration

**SlotLabProvider Connection (line 3575):**
```dart
final provider = context.watch<SlotLabProvider>();
final isSpinning = provider.isPlayingStages;
final canSpin = _balance >= _totalBetAmount && !isSpinning;
```

**Data from Provider:**
- `lastResult` — Spin result (grid, totalWin)
- `isPlayingStages` — Animation state
- `lastStages` — Stage events
- `betAmount` — Current bet

---

## Keyboard Shortcuts

| Key | Action | Debug Only |
|-----|--------|-----------|
| F11 | Toggle fullscreen | No |
| ESC | Exit / close | No |
| Space | Spin | No |
| M | Toggle music | No |
| S | Toggle stats | No |
| T | Toggle turbo | No |
| A | Toggle auto-spin | No |
| 1 | Force Lose | Yes |
| 2 | Force Small Win | Yes |
| 3 | Force Big Win | Yes |
| 4 | Force Mega Win | Yes |
| 5 | Force Epic Win | Yes |
| 6 | Force Free Spins | Yes |
| 7 | Force Grand Jackpot | Yes |

---

## TODO — Implementation Priority

### ✅ P0: Visual-Sync Integration — COMPLETE (5/5)

**Implementirano:** 2026-01-24

| # | Task | LOC | Solution | Status |
|---|------|-----|----------|--------|
| PSP-P0.1 | Add Visual-Sync state & scheduling | ~50 | `_reelsStopped`, `_pendingResultForWinStage`, `_reelStopTimers` | ✅ Done |
| PSP-P0.2 | Staggered reel stop timing | ~60 | `_scheduleVisualSyncCallbacks()` sa Timer-based scheduling | ✅ Done |
| PSP-P0.3 | EventRegistry stage triggering | ~30 | `eventRegistry.triggerStage()` za SPIN_START, REEL_STOP_0..4 | ✅ Done |
| PSP-P0.4 | Anticipation detection | ~15 | `_checkAnticipation()` na osnovu win tier-a | ✅ Done |
| PSP-P0.5 | Win tier stage triggering | ~25 | `_triggerWinStage()` → WIN_SMALL/BIG/MEGA/EPIC/ULTRA | ✅ Done |

**Implementacija (lines 5108-5250):**

```dart
/// Schedule Visual-Sync callbacks for staggered reel stops
void _scheduleVisualSyncCallbacks(SlotLabSpinResult? pendingResult) {
  // Cancel any existing timers
  for (final timer in _reelStopTimers) { timer.cancel(); }
  _reelStopTimers.clear();

  // SPIN_START — Trigger immediately
  eventRegistry.triggerStage('SPIN_START');

  // Staggered reel stops — matches SlotPreviewWidget animation timing
  final baseDelay = _isTurbo ? 100 : 250;
  final baseAnimDuration = _isTurbo ? 600 : 1000;
  final staggerDelay = _isTurbo ? 60 : 120;

  for (int i = 0; i < widget.reels; i++) {
    final stopTime = (staggerDelay * i) + baseAnimDuration + (baseDelay * i);
    final timer = Timer(Duration(milliseconds: stopTime), () {
      eventRegistry.triggerStage('REEL_STOP_$i');
      if (i == widget.reels - 2) _checkAnticipation();
      if (i == widget.reels - 1) _onAllReelsStopped();
    });
    _reelStopTimers.add(timer);
  }
}
```

---

### ✅ P1: Critical (Blocking Audio Testing) — COMPLETE

| # | Task | Solution | Status |
|---|------|----------|--------|
| PSP-P1.1 | Cascade animation | `_CascadeOverlay` — falling symbols, glow, rotation | ✅ Done |
| PSP-P1.2 | Wild expansion | `_WildExpansionOverlay` — expanding star, sparkle particles | ✅ Done |
| PSP-P1.3 | Scatter collection | `_ScatterCollectOverlay` — flying diamonds with trails | ✅ Done |
| PSP-P1.4 | Audio toggles | Connected to `NativeFFI.setBusMute()` (bus 1=SFX, 2=Music) | ✅ Done |

### ✅ P2: High (Realism) — COMPLETE

| # | Task | Solution | Status |
|---|------|----------|--------|
| PSP-P2.1 | Collect/Gamble logic | Full gamble flow implemented, **Gamble disabled** (2026-01-24) — code preserved | ✅ Done |
| PSP-P2.2 | Paytable from math model | `_PaytablePanel` connected to engine via `slotLabExportPaytable()` | ✅ Done |
| PSP-P2.3 | RNG from engine | `_getEngineRandomGrid()` via `slotLabSpin()` FFI | ✅ Done |
| PSP-P2.4 | Jackpot growth from bet | `_tickJackpots()` uses `_progressiveContribution` from bet math | ✅ Done |

### ✅ P3: Medium (Polish) — COMPLETE

| # | Task | Solution | Status |
|---|------|----------|--------|
| PSP-P3.1 | Menu functionality | `_MenuPanel` with Paytable/Rules/History/Stats/Settings/Help access | ✅ Done |
| PSP-P3.2 | Rules from game config | `_GameRulesConfig.fromJson()` via `slotLabExportConfig()` FFI | ✅ Done |
| PSP-P3.3 | Settings persistence | SharedPreferences for turbo/music/sfx/volume/quality/animations | ✅ Done |
| PSP-P3.4 | Theme consolidation | `_SlotTheme` documented with FluxForgeTheme color mappings | ✅ Done |

---

### 🔵 P4: Unification (Future Refactor)

**Cilj:** Ujediniti `PremiumSlotPreview` i `EmbeddedSlotMockup` u jedan reusable core.

| # | Task | LOC | Solution | Status |
|---|------|-----|----------|--------|
| PSP-P4.1 | Extract SlotMachineCore | ~800 | Shared reel logic, timing, callbacks | ❌ Future |
| PSP-P4.2 | Theme injection | ~200 | `SlotMachineTheme` data class | ❌ Future |
| PSP-P4.3 | Layout variants | ~300 | Compact vs Fullscreen via builder | ❌ Future |
| PSP-P4.4 | Single testing path | ~150 | One widget, multiple skins | ❌ Future |

**Benefit:** Eliminacija duplikacije, jedan source of truth za slot ponašanje.

---

## Summary Table

| Priority | Tasks | Done | Remaining | Progress |
|----------|-------|------|-----------|----------|
| ✅ P0: Visual-Sync | 5 | **5** | 0 | **100%** |
| ✅ P1: Critical UI | 4 | **4** | 0 | 100% |
| ✅ P2: Realism | 4 | **4** | 0 | 100% |
| ✅ P3: Polish | 4 | **4** | 0 | 100% |
| 🔵 P4: Unification | 4 | 0 | 4 | 0% |
| **TOTAL** | **21** | **17** | **4** | **81%** |

---

## Color Palette

```dart
// Background
bgDeep:     #0a0a12
bgDark:     #121218
bgMid:      #1a1a24
bgSurface:  #242432

// Accents
accentBlue:  #4a9eff
accentCyan:  #40c8ff
accentGreen: #40ff90
accentRed:   #ff4040

// Casino
gold:        #FFD700
silver:      #C0C0C0
bronze:      #CD7F32

// Jackpots
jackpotGrand:    #FFD700  (gold)
jackpotMajor:    #FF4080  (magenta)
jackpotMinor:    #8B5CF6  (purple)
jackpotMini:     #4CAF50  (green)
```

---

*Generated: 2026-01-24*
*Updated: 2026-01-24 — Visual-Sync implemented*
*Status: 81% Complete (17/21 tasks done) — P0+P1+P2+P3 Done, P4 Unification FUTURE*

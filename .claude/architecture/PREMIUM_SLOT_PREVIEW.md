# Premium Slot Preview — Architecture Document

**Date:** 2026-01-24
**Status:** 95% Complete
**LOC:** ~5,213 total (3,728 + 1,485)

---

## Overview

Premium Slot Preview je fullscreen casino-grade slot machine UI za SlotLab. Služi kao audio sandbox za dizajnere — omogućava testiranje audio eventa u realističnom okruženju.

**Trigger:** F11 key u SlotLab screen-u

---

## File Structure

| File | LOC | Purpose |
|------|-----|---------|
| `premium_slot_preview.dart` | 3,728 | Main UI, 8 zones, state management |
| `slot_preview_widget.dart` | 1,485 | Reel animation system, particles |

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
| Collect button | — | ⚠️ No logic |
| Gamble button | — | ⚠️ No logic |

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

### ✅ P1: Critical (Blocking Audio Testing) — COMPLETE

| # | Task | Solution | Status |
|---|------|----------|--------|
| PSP-P1.1 | Cascade animation | `_CascadeOverlay` — falling symbols, glow, rotation | ✅ Done |
| PSP-P1.2 | Wild expansion | `_WildExpansionOverlay` — expanding star, sparkle particles | ✅ Done |
| PSP-P1.3 | Scatter collection | `_ScatterCollectOverlay` — flying diamonds with trails | ✅ Done |
| PSP-P1.4 | Audio toggles | Connected to `NativeFFI.setBusMute()` (bus 1=SFX, 2=Music) | ✅ Done |

### P2: High (Realism)

| # | Task | Effort |
|---|------|--------|
| PSP-P2.1 | Collect/Gamble logic | 2-3h |
| PSP-P2.2 | Paytable from math model | 2-3h |
| PSP-P2.3 | RNG from engine | 2-3h |
| PSP-P2.4 | Jackpot growth from bet | 2-3h |

### P3: Medium (Polish)

| # | Task | Effort |
|---|------|--------|
| PSP-P3.1 | Menu functionality | 2-3h |
| PSP-P3.2 | Rules from game config | 1-2h |
| PSP-P3.3 | Settings persistence | 1-2h |
| PSP-P3.4 | Theme consolidation | 2-3h |

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
*Status: 95% UI Complete, 4/12 TODO items done (P1 Complete), 8 remaining*

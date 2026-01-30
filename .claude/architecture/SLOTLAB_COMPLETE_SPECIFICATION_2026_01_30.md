# SlotLab Complete Specification

**Version:** 2.0.0
**Last Updated:** 2026-01-30
**Status:** Production Ready

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Screen Layout Architecture](#2-screen-layout-architecture)
3. [Left Panel — Ultimate Audio Panel](#3-left-panel--ultimate-audio-panel)
4. [Center Panel — Slot Machine Preview](#4-center-panel--slot-machine-preview)
5. [Right Panel — Events Inspector](#5-right-panel--events-inspector)
6. [Bottom Dock — Audio Browser](#6-bottom-dock--audio-browser)
7. [Lower Zone — Super-Tab System](#7-lower-zone--super-tab-system)
8. [Drop Zone System](#8-drop-zone-system)
9. [Keyboard Shortcuts](#9-keyboard-shortcuts)
10. [State Machine](#10-state-machine)
11. [Data Models](#11-data-models)
12. [Provider Integration](#12-provider-integration)
13. [Feature Modules](#13-feature-modules)
14. [GDD Import Flow](#14-gdd-import-flow)
15. [Export System](#15-export-system)
16. [Audio Systems](#16-audio-systems)
17. [Visual Effects](#17-visual-effects)
18. [Error Handling](#18-error-handling)

---

## 1. Executive Summary

### 1.1 Purpose

SlotLab is a professional slot game audio authoring environment within FluxForge Studio. It provides:

- **Visual slot machine preview** with industry-standard reel animations
- **Drag-drop audio assignment** to 35+ stage-mapped drop targets
- **Real-time audio-visual synchronization** with per-reel callbacks
- **Game flow organization** with 341 audio slots across 12 sections
- **GDD import** for automatic symbol and paytable configuration
- **Multi-format export** to Unity, Unreal, Howler.js, and native formats

### 1.2 Design Philosophy

1. **Game Flow First** — Audio slots organized by gameplay sequence (Spin→Stop→Win→Feature)
2. **Visual-Audio Sync** — Callbacks ensure audio triggers exactly when reels visually stop
3. **Data-Driven** — GDD import auto-generates symbols, stages, and paytables
4. **Industry Standard** — Win tiers, anticipation, and rollup follow NetEnt/Pragmatic Play patterns
5. **Single Source of Truth** — MiddlewareProvider owns all event data

### 1.3 Target Users

| Role | Primary Tasks |
|------|---------------|
| **Audio Designer** | Assign audio to stages, preview in context, mix buses |
| **Sound Designer** | Layer sounds, adjust timing, create variations |
| **Composer** | Set up music layers, ALE rules, context transitions |
| **Game Designer** | Import GDD, configure grid, test forced outcomes |
| **QA Engineer** | Validate event coverage, test edge cases, export packages |

---

## 2. Screen Layout Architecture

### 2.1 Three-Panel Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│ HEADER (App Bar)                                              Height: 48px │
├────────────────┬─────────────────────────────────┬──────────────────────┤
│                │                                 │                      │
│  ULTIMATE      │        CENTER PANEL             │    EVENTS            │
│  AUDIO         │   (Slot Machine Preview)        │    INSPECTOR         │
│  PANEL         │                                 │                      │
│                │   - Header Zone                 │   - Events Folder    │
│  Width: 220px  │   - Jackpot Zone                │   - Selected Event   │
│  Min: 180px    │   - Reel Frame                  │   - Layer Editor     │
│  Max: 300px    │   - Win Presenter               │                      │
│                │   - Control Bar                 │    Width: 300px      │
│  12 Sections   │                                 │    Min: 250px        │
│  341 Slots     │   Flexible Width                │    Max: 400px        │
│                │   Min: 600px                    │                      │
├────────────────┴─────────────────────────────────┴──────────────────────┤
│ AUDIO BROWSER DOCK                                           Height: 90px │
│ (Collapsible to 28px)                                                    │
├─────────────────────────────────────────────────────────────────────────┤
│ LOWER ZONE                                            Height: 150-600px │
│ (7 Super-Tabs: Stages, Events, Mix, Music, Meters, Debug, Engine)        │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Layout Constants

```dart
// Panel Dimensions (lower_zone_types.dart)
const double kLeftPanelWidth = 220.0;
const double kLeftPanelMinWidth = 180.0;
const double kLeftPanelMaxWidth = 300.0;

const double kRightPanelWidth = 300.0;
const double kRightPanelMinWidth = 250.0;
const double kRightPanelMaxWidth = 400.0;

const double kCenterPanelMinWidth = 600.0;

// Lower Zone Heights
const double kLowerZoneMinHeight = 150.0;
const double kLowerZoneMaxHeight = 600.0;
const double kLowerZoneDefaultHeight = 250.0;

// Component Heights
const double kContextBarHeight = 60.0;           // Expanded (super-tabs + sub-tabs)
const double kContextBarCollapsedHeight = 32.0;  // Collapsed (super-tabs only)
const double kActionStripHeight = 36.0;          // Bottom action buttons
const double kResizeHandleHeight = 4.0;          // Drag resize handle
const double kSpinControlBarHeight = 32.0;       // SlotLab spin controls

// Audio Browser Dock
const double kAudioBrowserDockHeight = 90.0;     // Expanded
const double kAudioBrowserDockCollapsedHeight = 28.0;  // Collapsed
```

### 2.3 Responsive Behavior

| Screen Width | Left Panel | Center Panel | Right Panel |
|--------------|------------|--------------|-------------|
| < 1200px | Hidden (drawer) | Full width | Hidden (drawer) |
| 1200-1600px | 180px | Flexible | 250px |
| 1600-2000px | 220px | Flexible | 300px |
| > 2000px | 280px | Flexible | 350px |

---

## 3. Left Panel — Ultimate Audio Panel

### 3.1 Overview

The Ultimate Audio Panel (V8) organizes 341 audio slots across 12 sections following game flow.

**File:** `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart`

### 3.2 Section Hierarchy

```
ULTIMATE AUDIO PANEL (341 slots)
├── 1. BASE GAME LOOP (41 slots)        [Primary]   #4A9EFF
├── 2. SYMBOLS & LANDS (46 slots)       [Primary]   #9370DB
├── 3. WIN PRESENTATION (41 slots)      [Primary]   #FFD700
├── 4. CASCADING MECHANICS (24 slots)   [Secondary] #FF6B6B
├── 5. MULTIPLIERS (18 slots)           [Secondary] #FF9040
├── 6. FREE SPINS (24 slots)            [Feature]   #40FF90
├── 7. BONUS GAMES (32 slots)           [Feature]   #9370DB
├── 8. HOLD & WIN (24 slots)            [Feature]   #40C8FF
├── 9. JACKPOTS (26 slots)              [Premium]   #FFD700 🏆
├── 10. GAMBLE (16 slots)               [Optional]  #FF6B6B
├── 11. MUSIC & AMBIENCE (27 slots)     [Background]#40C8FF
└── 12. UI & SYSTEM (22 slots)          [Utility]   #808080
```

### 3.3 Section 1: Base Game Loop (41 slots)

| Slot ID | Stage | Description | Pooled |
|---------|-------|-------------|--------|
| `spin_button_press` | SPIN_START | UI button press feedback | No |
| `spin_button_release` | — | Button release feedback | No |
| `spin_initiate` | SPIN_START | Spin confirmation | No |
| `reel_spin_start` | REEL_SPINNING | Initial reel acceleration | No |
| `reel_spin_loop` | REEL_SPIN_LOOP | Continuous spin sound | Loop |
| `reel_stop_0` | REEL_STOP_0 | First reel landing | ⚡ Yes |
| `reel_stop_1` | REEL_STOP_1 | Second reel landing | ⚡ Yes |
| `reel_stop_2` | REEL_STOP_2 | Third reel landing | ⚡ Yes |
| `reel_stop_3` | REEL_STOP_3 | Fourth reel landing | ⚡ Yes |
| `reel_stop_4` | REEL_STOP_4 | Fifth reel landing | ⚡ Yes |
| `reel_stop_generic` | REEL_STOP | Generic reel stop (fallback) | ⚡ Yes |
| `anticipation_start` | ANTICIPATION_ON | Anticipation begins | No |
| `anticipation_buildup` | ANTICIPATION_TENSION | Rising tension | No |
| `anticipation_resolve` | ANTICIPATION_OFF | Anticipation ends | No |
| `spin_complete` | SPIN_END | All reels stopped | No |
| ... | ... | ... | ... |

### 3.4 Section 2: Symbols & Lands (46 slots)

| Slot ID | Stage Pattern | Description |
|---------|---------------|-------------|
| `symbol_land_hp1` | SYMBOL_LAND_HP1 | High pay 1 landing |
| `symbol_land_hp2` | SYMBOL_LAND_HP2 | High pay 2 landing |
| `symbol_land_hp3` | SYMBOL_LAND_HP3 | High pay 3 landing |
| `symbol_land_hp4` | SYMBOL_LAND_HP4 | High pay 4 landing |
| `symbol_land_lp1` | SYMBOL_LAND_LP1 | Low pay 1 landing |
| `symbol_land_lp2` | SYMBOL_LAND_LP2 | Low pay 2 landing |
| `symbol_land_lp3` | SYMBOL_LAND_LP3 | Low pay 3 landing |
| `symbol_land_lp4` | SYMBOL_LAND_LP4 | Low pay 4 landing |
| `symbol_land_lp5` | SYMBOL_LAND_LP5 | Low pay 5 landing |
| `symbol_land_lp6` | SYMBOL_LAND_LP6 | Low pay 6 landing |
| `symbol_land_wild` | SYMBOL_LAND_WILD | Wild symbol landing |
| `symbol_land_scatter` | SYMBOL_LAND_SCATTER | Scatter symbol landing |
| `symbol_land_bonus` | SYMBOL_LAND_BONUS | Bonus symbol landing |
| `wild_expand` | WILD_EXPAND | Wild expansion animation |
| `wild_substitute` | WILD_SUBSTITUTE | Wild substitution |
| `scatter_collect` | SCATTER_COLLECT | Scatter collection |
| ... | ... | ... |

### 3.5 Section 3: Win Presentation (41 slots)

| Slot ID | Stage | Win Tier | Description |
|---------|-------|----------|-------------|
| `win_small_present` | WIN_PRESENT_SMALL | < 5x | Small win reveal |
| `win_big_present` | WIN_PRESENT_BIG | 5-15x | Big win fanfare |
| `win_super_present` | WIN_PRESENT_SUPER | 15-30x | Super win celebration |
| `win_mega_present` | WIN_PRESENT_MEGA | 30-60x | Mega win explosion |
| `win_epic_present` | WIN_PRESENT_EPIC | 60-100x | Epic win extravaganza |
| `win_ultra_present` | WIN_PRESENT_ULTRA | 100x+ | Ultra win maximum |
| `win_symbol_highlight` | WIN_SYMBOL_HIGHLIGHT | — | Winning symbol glow |
| `win_line_show_0` | WIN_LINE_SHOW_0 | — | First payline display |
| `win_line_show_1` | WIN_LINE_SHOW_1 | — | Second payline display |
| `win_line_show_2` | WIN_LINE_SHOW_2 | — | Third payline display |
| `rollup_tick` | ROLLUP_TICK | — | Counter tick | ⚡ Yes |
| `rollup_tick_fast` | ROLLUP_TICK_FAST | — | Fast counter tick | ⚡ Yes |
| `rollup_complete` | ROLLUP_END | — | Counter finished |
| ... | ... | ... | ... |

### 3.6 Section Details (Continued)

**Section 4: Cascading Mechanics (24 slots)**
- CASCADE_START, CASCADE_STEP (⚡ pooled), CASCADE_END
- TUMBLE_DROP, TUMBLE_LAND, AVALANCHE_FALL

**Section 5: Multipliers (18 slots)**
- MULTIPLIER_INCREASE, MULTIPLIER_DECREASE, MULTIPLIER_APPLY
- MULT_2X, MULT_3X, MULT_5X, MULT_10X, MULT_WILD

**Section 6: Free Spins (24 slots)**
- FS_TRIGGER, FS_ENTER, FS_SPIN, FS_RETRIGGER, FS_EXIT
- FS_MUSIC_START, FS_MUSIC_LOOP, FS_MUSIC_END

**Section 7: Bonus Games (32 slots)**
- BONUS_TRIGGER, BONUS_ENTER, BONUS_PICK, BONUS_REVEAL
- BONUS_WIN, BONUS_COMPLETE, BONUS_EXIT
- WHEEL_SPIN, WHEEL_TICK (⚡ pooled), WHEEL_STOP

**Section 8: Hold & Win (24 slots)**
- HOLD_TRIGGER, HOLD_ENTER, HOLD_SPIN, HOLD_LAND
- HOLD_COLLECT, HOLD_RESPIN, HOLD_COMPLETE

**Section 9: Jackpots (26 slots)** 🏆
- JACKPOT_TRIGGER, JACKPOT_BUILDUP, JACKPOT_REVEAL
- JACKPOT_MINI, JACKPOT_MINOR, JACKPOT_MAJOR, JACKPOT_GRAND
- JACKPOT_CELEBRATION, JACKPOT_COLLECT

**Section 10: Gamble (16 slots)**
- GAMBLE_ENTER, GAMBLE_CHOICE, GAMBLE_REVEAL
- GAMBLE_WIN, GAMBLE_LOSE, GAMBLE_COLLECT, GAMBLE_EXIT

**Section 11: Music & Ambience (27 slots)**
- MUSIC_BASE, MUSIC_TENSION_L1-L4, MUSIC_FEATURE
- AMBIENT_LOOP, AMBIENT_HIT, ATTRACT_MUSIC

**Section 12: UI & System (22 slots)**
- UI_BUTTON_PRESS, UI_BUTTON_HOVER, UI_NAVIGATION
- SYSTEM_ERROR, SYSTEM_NOTIFICATION, CONNECTION_LOST

### 3.7 Panel UI Components

```
┌─────────────────────────────────────┐
│ 🔍 Search: [________________] [X]   │  ← Search bar (filters all sections)
├─────────────────────────────────────┤
│ ▼ 1. BASE GAME LOOP            (41) │  ← Section header (collapsible)
│   │ ⚡ reel_stop_0     [🔊][───]   │  ← Audio slot (pooled indicator)
│   │ ⚡ reel_stop_1     [🔊][───]   │
│   │   spin_initiate   [🔊][wav]   │  ← Assigned audio (waveform preview)
│   └ ...                            │
├─────────────────────────────────────┤
│ ▶ 2. SYMBOLS & LANDS           (46) │  ← Collapsed section
├─────────────────────────────────────┤
│ ▼ 3. WIN PRESENTATION          (41) │
│   │   win_big_present [🔊][wav]   │
│   │ ⚡ rollup_tick    [🔊][───]   │  ← Pooled rapid-fire event
│   └ ...                            │
└─────────────────────────────────────┘
```

### 3.8 Audio Slot Item States

| State | Visual | Interaction |
|-------|--------|-------------|
| **Empty** | Dashed border, muted text | Drop target active |
| **Assigned** | Solid border, waveform preview | Click to preview |
| **Playing** | Green glow, animated waveform | Click to stop |
| **Pooled** | ⚡ icon, cyan accent | Rapid-fire optimized |
| **Hover** | Highlight, show controls | — |
| **Dragging Over** | Blue glow, "Drop here" | Accept drop |

### 3.9 Section Header Actions

| Action | Icon | Behavior |
|--------|------|----------|
| **Expand/Collapse** | ▼/▶ | Toggle section visibility |
| **Play All** | ▶ | Preview all assigned audio in sequence |
| **Clear All** | 🗑 | Remove all audio assignments (with confirmation) |
| **Audio Count** | Badge | Shows assigned/total (e.g., "12/41") |

---

## 4. Center Panel — Slot Machine Preview

### 4.1 Overview

The center panel contains the interactive slot machine preview with casino-grade visual elements.

**File:** `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart`

### 4.2 Zone Hierarchy

```
CENTER PANEL
├── A. HEADER ZONE (48px)
│   ├── Menu Button
│   ├── Logo
│   ├── Balance Display
│   ├── VIP Badge
│   ├── Audio Controls
│   ├── Settings
│   └── Exit Button
├── B. JACKPOT ZONE (80px)
│   ├── Mini Jackpot Ticker
│   ├── Minor Jackpot Ticker
│   ├── Major Jackpot Ticker
│   ├── Grand Jackpot Ticker
│   ├── [Mystery Jackpot Ticker]
│   └── Progressive Meter
├── C. MAIN GAME ZONE (Flexible)
│   ├── Background Layer
│   ├── Ambient Particles
│   ├── Reel Frame (5x3 grid)
│   ├── Payline Visualizer
│   ├── Win Highlight Overlay
│   ├── Anticipation Frame
│   ├── Wild Expansion Layer
│   ├── Scatter Collection Layer
│   └── Cascade Layer
├── D. WIN PRESENTER (Overlay)
│   ├── Tier Plaque
│   ├── Coin Rollup Counter
│   ├── Particle Burst
│   └── Gamble Option
├── E. FEATURE INDICATORS (32px)
│   ├── Free Spins Counter
│   ├── Bonus Meter
│   └── Multiplier Display
└── F. CONTROL BAR (64px)
    ├── Lines/Coin/Bet Selectors
    ├── Auto-spin Button
    ├── Turbo Toggle
    └── Spin/Stop Button
```

### 4.3 Theme Colors (_SlotTheme)

```dart
class _SlotTheme {
  // Backgrounds
  static const Color bgDark = Color(0xFF0a0a10);
  static const Color bgDeep = Color(0xFF0f0f18);
  static const Color bgMid = Color(0xFF1a1a28);
  static const Color bgSurface = Color(0xFF242438);

  // Jackpot Tiers
  static const Color jackpotGrand = Color(0xFFFFD700);   // Gold
  static const Color jackpotMajor = Color(0xFFFF4080);   // Pink
  static const Color jackpotMinor = Color(0xFF8B5CF6);   // Purple
  static const Color jackpotMini = Color(0xFF4CAF50);    // Green
  static const Color jackpotMystery = Color(0xFFE91E63); // Mystery Pink

  // Win Tiers
  static const Color winUltra = Color(0xFFFF00FF);   // Magenta
  static const Color winEpic = Color(0xFFFF4500);    // Red-Orange
  static const Color winMega = Color(0xFFFFD700);    // Gold
  static const Color winBig = Color(0xFF00FF00);     // Green
  static const Color winSmall = Color(0xFF4A9EFF);   // Blue

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0C0);
  static const Color textMuted = Color(0xFF606070);

  // Accents
  static const Color gold = Color(0xFFFFD700);
  static const Color goldLight = Color(0xFFFFE066);
  static const Color accentBlue = Color(0xFF4A9EFF);
  static const Color accentGreen = Color(0xFF40FF90);
}
```

### 4.4 Header Zone (A)

```
┌─────────────────────────────────────────────────────────────────┐
│ [☰]  FluxForge Logo   $12,500.00   ⭐VIP 7  [🔊][⚙][✕]        │
└─────────────────────────────────────────────────────────────────┘
```

| Component | Width | Description |
|-----------|-------|-------------|
| Menu Button | 48px | Opens menu panel (Paytable, Rules, History, etc.) |
| Logo | 120px | FluxForge Studio branding |
| Balance | 150px | Current session balance with animated updates |
| VIP Badge | 80px | VIP level indicator with gradient colors |
| Audio Toggle | 32px | Mute/unmute with bus control |
| Settings | 32px | Opens settings panel |
| Exit Button | 32px | Exit fullscreen / close preview |

### 4.5 Jackpot Zone (B)

```
┌─────────────────────────────────────────────────────────────────┐
│  ┌──────┐ ┌────────┐ ┌──────────┐ ┌────────────┐  CONTRIBUTION │
│  │ MINI │ │ MINOR  │ │  MAJOR   │ │   GRAND    │  ────────────  │
│  │$1.2K │ │$5.8K   │ │ $28.5K   │ │  $125.8K   │  $0.15        │
│  └──────┘ └────────┘ └──────────┘ └────────────┘  [━━━━━━━━░░] │
└─────────────────────────────────────────────────────────────────┘
```

**Jackpot Ticker Dimensions:**

| Size | Width | Label | Amount | Use |
|------|-------|-------|--------|-----|
| Small | 85px | 8px | 12px | Mini |
| Medium | 100px | 9px | 14px | Minor, Mystery |
| Large | 115px | 10px | 16px | Major |
| Grand | 140px | 11px | 20px | Grand |

**Jackpot Animation:**
- Pulse animation: 1500ms cycle, 0.8-1.0 opacity
- Amount ticker: 30 steps × 20ms = 600ms roll-up
- Glow radius scales with tier

### 4.6 Main Game Zone (C)

#### Reel Configuration

```dart
// Default grid
int reels = 5;    // Columns (3-10 configurable)
int rows = 3;     // Rows (2-8 configurable)

// Reel dimensions
double symbolWidth = (availableWidth - frameMargin) / reels;
double symbolHeight = (availableHeight - frameMargin) / rows;

// Animation timing (Studio profile)
const Duration reelStagger = Duration(milliseconds: 370);
const Duration accelerate = Duration(milliseconds: 100);
const Duration spinning = Duration(milliseconds: 560);
const Duration decelerate = Duration(milliseconds: 300);
const Duration bounce = Duration(milliseconds: 200);
```

#### Symbol Registry

```dart
class SlotSymbol {
  final int id;
  final String name;
  final String emoji;
  final Color color;
  final Color glowColor;

  // Default symbols
  static const hp1 = SlotSymbol(0, 'HP1', '💎', Color(0xFF4A9EFF));
  static const hp2 = SlotSymbol(1, 'HP2', '👑', Color(0xFFFFD700));
  static const hp3 = SlotSymbol(2, 'HP3', '🔔', Color(0xFFFF9040));
  static const hp4 = SlotSymbol(3, 'HP4', '7️⃣', Color(0xFFFF4060));
  static const lp1 = SlotSymbol(4, 'LP1', '🍒', Color(0xFFFF6B6B));
  static const lp2 = SlotSymbol(5, 'LP2', '🍋', Color(0xFFFFEB3B));
  static const lp3 = SlotSymbol(6, 'LP3', '🍊', Color(0xFFFF9800));
  static const lp4 = SlotSymbol(7, 'LP4', '🍇', Color(0xFF9C27B0));
  static const lp5 = SlotSymbol(8, 'LP5', '🍉', Color(0xFF4CAF50));
  static const lp6 = SlotSymbol(9, 'LP6', '⭐', Color(0xFFFFD700));
  static const wild = SlotSymbol(10, 'WILD', '🃏', Color(0xFF00E676));
  static const scatter = SlotSymbol(11, 'SCATTER', '💫', Color(0xFFE91E63));
  static const bonus = SlotSymbol(12, 'BONUS', '🎁', Color(0xFF9C27B0));

  // Dynamic symbols (from GDD import)
  static Map<int, SlotSymbol> _dynamicSymbols = {};
  static void setDynamicSymbols(Map<int, SlotSymbol> symbols) {
    _dynamicSymbols = symbols;
  }
}
```

### 4.7 Win Presenter (D)

#### Win Tier Thresholds

| Tier | Multiplier | Plaque Label | Rollup Duration | Ticks/sec |
|------|------------|--------------|-----------------|-----------|
| SMALL | < 5x | "WIN!" | 1500ms | 15 |
| BIG | 5x - 15x | "BIG WIN!" | 2500ms | 12 |
| SUPER | 15x - 30x | "SUPER WIN!" | 4000ms | 10 |
| MEGA | 30x - 60x | "MEGA WIN!" | 7000ms | 8 |
| EPIC | 60x - 100x | "EPIC WIN!" | 12000ms | 6 |
| ULTRA | 100x+ | "ULTRA WIN!" | 20000ms | 4 |

#### Win Presentation Flow (3 Phases)

```
Phase 1: Symbol Highlight (1050ms)
├── 350ms × 3 cycles: Winning symbols glow/bounce
├── Stage: WIN_SYMBOL_HIGHLIGHT
└── Audio: win_symbol_highlight

Phase 2: Tier Plaque + Rollup (1500-20000ms based on tier)
├── Screen flash (150ms white/gold)
├── Plaque glow pulse (400ms repeating)
├── Particle burst (10-80 particles by tier)
├── Coin counter rollup animation
├── Stage: WIN_PRESENT_[TIER], ROLLUP_START/TICK/END
└── Audio: win_[tier]_present, rollup_tick

Phase 3: Win Line Cycling (1500ms per line, STRICT SEQUENTIAL)
├── Win lines show one at a time
├── ONLY after Phase 2 ends
├── Stage: WIN_LINE_SHOW_0, WIN_LINE_SHOW_1, ...
└── Audio: win_line_show_[n]
```

### 4.8 Control Bar (F)

```
┌─────────────────────────────────────────────────────────────────┐
│ LINES    COIN     BET      [AUTO] [⚡TURBO]    [ S P I N ]     │
│ [  25]   [0.10]   [2.50]                       [  S T O P ]     │
└─────────────────────────────────────────────────────────────────┘
```

| Control | Type | Range | Default |
|---------|------|-------|---------|
| Lines | Dropdown | 1-50 | 25 |
| Coin Value | Dropdown | 0.01-10.00 | 0.10 |
| Total Bet | Display | Lines × Coin | 2.50 |
| Auto-Spin | Toggle | On/Off | Off |
| Turbo | Toggle | On/Off | Off |
| Spin/Stop | Button | Context | Spin |

**Spin Button States:**

| State | Label | Color | Icon |
|-------|-------|-------|------|
| Ready | "SPIN" | Green gradient | ▶ |
| Spinning | "STOP" | Red gradient | ⬛ |
| Disabled | "SPIN" | Gray | ▶ |
| Auto-Active | "STOP AUTO" | Orange | ⬛ |

---

## 5. Right Panel — Events Inspector

### 5.1 Overview

The Events Inspector provides event management and layer editing.

**File:** `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart`

### 5.2 Panel Structure

```
┌─────────────────────────────────────┐
│ EVENTS                        [+]   │  ← Header with Add button
├─────────────────────────────────────┤
│ 📁 Spin Events (5)                 │  ← Folder (collapsible)
│   ├── onUiSpin           [▶][...]  │
│   ├── onReelStop0        [▶][...]  │
│   ├── onReelStop1        [▶][...]  │
│   ├── onReelStop2        [▶][...]  │
│   └── onReelStop3        [▶][...]  │
│ 📁 Win Events (3)                  │
│   ├── onWinSmall         [▶][...]  │
│   ├── onWinBig           [▶][...]  │
│   └── onWinMega          [▶][...]  │
│ 📁 Feature Events (2)              │
│   ├── onFsTrigger        [▶][...]  │
│   └── onBonusEnter       [▶][...]  │
├─────────────────────────────────────┤
│ SELECTED EVENT                      │
│ ┌─────────────────────────────────┐ │
│ │ onWinBig                      ✏️ │ │  ← Editable name
│ │ Stage: WIN_PRESENT_BIG         │ │
│ │ Bus: WINS (#6)                 │ │
│ │ Priority: 80                    │ │
│ │ Loop: No                        │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ LAYERS (2)                    [+]   │
│ ┌─────────────────────────────────┐ │
│ │ Layer 1: big_win_fanfare.wav   │ │
│ │ Vol: [━━━━━━━━░░] 80%          │ │
│ │ Pan: [░░░░━━━━░░] C            │ │
│ │ Delay: [0]ms  [▶][🗑]          │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ Layer 2: coin_shower.wav       │ │
│ │ Vol: [━━━━━━░░░░] 60%          │ │
│ │ Pan: [░░░░━━━━░░] C            │ │
│ │ Delay: [500]ms  [▶][🗑]        │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 5.3 Event Folder Tree

| Folder | Contains | Color |
|--------|----------|-------|
| Spin Events | SPIN_START, REEL_STOP_* | Blue |
| Win Events | WIN_PRESENT_*, ROLLUP_* | Gold |
| Feature Events | FS_*, BONUS_*, HOLD_* | Green |
| Jackpot Events | JACKPOT_* | Gold |
| UI Events | UI_* | Gray |
| Custom Events | User-created | Purple |

### 5.4 Event Properties

| Property | Type | Editable | Description |
|----------|------|----------|-------------|
| Name | String | ✏️ Yes | Event display name |
| Stage | String | ✏️ Yes | Trigger stage mapping |
| Bus | Enum | ✏️ Yes | Audio bus routing |
| Priority | Int (0-100) | ✏️ Yes | Voice priority |
| Loop | Boolean | ✏️ Yes | Loop playback |
| Container | Enum | ✏️ Yes | Blend/Random/Sequence |

### 5.5 Layer Editor

| Property | Control | Range | Default |
|----------|---------|-------|---------|
| Volume | Slider | 0-200% | 100% |
| Pan | Slider | L100-C-R100 | C |
| Delay | Number Input | 0-5000ms | 0ms |
| Fade In | Slider | 0-1000ms | 0ms |
| Fade Out | Slider | 0-1000ms | 0ms |
| Trim Start | Slider | 0-10000ms | 0ms |
| Trim End | Slider | 0-10000ms | 0ms |

### 5.6 Layer Actions

| Action | Icon | Shortcut | Description |
|--------|------|----------|-------------|
| Preview | ▶ | Space | Play layer audio |
| Delete | 🗑 | Delete | Remove layer |
| Duplicate | 📋 | Cmd+D | Copy layer |
| Move Up | ↑ | Cmd+↑ | Reorder layer |
| Move Down | ↓ | Cmd+↓ | Reorder layer |

---

## 6. Bottom Dock — Audio Browser

### 6.1 Overview

Horizontal audio browser dock following Wwise/FMOD patterns.

**File:** `flutter_ui/lib/widgets/slot_lab/audio_browser_dock.dart`

### 6.2 Dock Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ AUDIO BROWSER                                      [Pool▾][▼]  │
├─────────────────────────────────────────────────────────────────┤
│ 🔍[________] [📄][📁]  │ [spin.wav][stop.wav][win.wav][...] ▶│ │
│                        │ [🔊 3 files selected]                │ │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Components

| Component | Description |
|-----------|-------------|
| Mode Toggle | Switch between Pool (AudioAssetManager) and Files (file system) |
| Search | Filter files by name |
| Import File | Import individual audio files |
| Import Folder | Import entire folder recursively |
| Audio Chips | Draggable audio file chips |
| Selection Badge | Shows selected file count |
| Collapse Button | Toggle dock height (90px ↔ 28px) |

### 6.4 Audio Chip States

| State | Visual | Interaction |
|-------|--------|-------------|
| Idle | Gray border | Hover to preview |
| Selected | Green background, checkbox | Part of multi-select |
| Playing | Cyan glow | Click to stop |
| Dragging | Opacity 0.5 | Shows file count badge |

### 6.5 Multi-Select Operations

| Action | Trigger | Description |
|--------|---------|-------------|
| Toggle Select | Long-press | Add/remove from selection |
| Select All | Cmd+A | Select all visible files |
| Clear | Escape | Clear selection |
| Drag Multi | Drag selected | Drag multiple files at once |

---

## 7. Lower Zone — Super-Tab System

### 7.1 Overview

The Lower Zone uses a super-tab and sub-tab hierarchy for organization.

**File:** `flutter_ui/lib/widgets/lower_zone/slotlab_lower_zone_widget.dart`

### 7.2 Super-Tab Structure

```
LOWER ZONE SUPER-TABS
├── 1. STAGES (Keyboard: 1)
│   ├── Stage Trace
│   ├── Event Timeline
│   └── Stage Config
├── 2. EVENTS (Keyboard: 2)
│   ├── Events Folder
│   ├── Composite Editor
│   └── RTPC Bindings
├── 3. MIX (Keyboard: 3)
│   ├── Bus Hierarchy
│   ├── Aux Sends
│   └── Voice Pool
├── 4. DSP (Keyboard: 4)
│   ├── FabFilter Compressor
│   ├── FabFilter Limiter
│   ├── FabFilter Gate
│   └── FabFilter Reverb
├── 5. BAKE (Keyboard: 5)
│   ├── Batch Export
│   ├── Stems Panel
│   └── Package Panel
└── [+] PLUS MENU
    ├── Game Config
    ├── AutoSpatial
    ├── Scenarios
    └── Command Builder
```

### 7.3 Super-Tab Enum

```dart
enum SlotLabSuperTab {
  stages,   // Stage trace, timeline
  events,   // Event management
  mix,      // Bus mixing
  dsp,      // FabFilter DSP
  bake,     // Export/package
}
```

### 7.4 Sub-Tab Enums

```dart
enum StagesSubTab { trace, timeline, config }
enum EventsSubTab { folder, editor, rtpc }
enum MixSubTab { buses, sends, voices }
enum DspSubTab { compressor, limiter, gate, reverb }
enum BakeSubTab { export, stems, package }
```

### 7.5 Context Bar Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ [STAGES] [EVENTS] [MIX] [DSP] [BAKE] [+]              [—][□][X] │ ← Super-tabs (32px)
├─────────────────────────────────────────────────────────────────┤
│ [Trace] [Timeline] [Config]                              [⚙]   │ ← Sub-tabs (28px, when expanded)
└─────────────────────────────────────────────────────────────────┘
```

### 7.6 Spin Control Bar

```
┌─────────────────────────────────────────────────────────────────┐
│ Outcome: [Normal▾] Volatility: [Medium▾] Timing: [Studio▾] Grid: [5×3▾] │
└─────────────────────────────────────────────────────────────────┘
```

| Control | Options | Default |
|---------|---------|---------|
| Outcome | Normal, BigWin, FreeSpins, Jackpot, NearMiss, Cascade | Normal |
| Volatility | Low, Medium, High, Studio | Medium |
| Timing | Normal, Turbo, Mobile, Studio | Studio |
| Grid | 3×3, 5×3, 5×4, 6×4, 7×3, Custom | 5×3 |

### 7.7 Action Strip

```
┌─────────────────────────────────────────────────────────────────┐
│ [Record] [Stop] [Clear] [Export]          Status: Ready  │ [?] │
└─────────────────────────────────────────────────────────────────┘
```

| Super-Tab | Actions |
|-----------|---------|
| STAGES | Record, Stop, Clear, Export |
| EVENTS | Add Layer, Remove, Duplicate, Preview |
| MIX | Mute, Solo, Reset, Meters |
| DSP | Insert, Remove, Reorder, Copy Chain |
| BAKE | Validate, Bake All, Package |

---

## 8. Drop Zone System

### 8.1 Overview

The Drop Zone System enables drag-drop audio assignment to 35+ targets.

**File:** `flutter_ui/lib/widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart`

### 8.2 Target ID Format

```
{category}.{element}[.{modifier}]

Examples:
- ui.spin           → SPIN_START
- reel.0            → REEL_STOP_0
- reel.4            → REEL_STOP_4
- overlay.win.big   → WIN_PRESENT_BIG
- symbol.wild       → SYMBOL_LAND_WILD
- music.base        → MUSIC_BASE
```

### 8.3 Complete Target Map

| Target ID | Stage | Bus | Pan |
|-----------|-------|-----|-----|
| `ui.spin` | SPIN_START | UI (4) | 0.0 |
| `ui.autoplay` | AUTOPLAY_START | UI (4) | 0.0 |
| `ui.turbo` | TURBO_TOGGLE | UI (4) | 0.0 |
| `reel.0` | REEL_STOP_0 | Reels (5) | -0.8 |
| `reel.1` | REEL_STOP_1 | Reels (5) | -0.4 |
| `reel.2` | REEL_STOP_2 | Reels (5) | 0.0 |
| `reel.3` | REEL_STOP_3 | Reels (5) | +0.4 |
| `reel.4` | REEL_STOP_4 | Reels (5) | +0.8 |
| `reel.anticipation` | ANTICIPATION_ON | Reels (5) | 0.0 |
| `overlay.win.small` | WIN_PRESENT_SMALL | Wins (6) | 0.0 |
| `overlay.win.big` | WIN_PRESENT_BIG | Wins (6) | 0.0 |
| `overlay.win.mega` | WIN_PRESENT_MEGA | Wins (6) | 0.0 |
| `overlay.win.epic` | WIN_PRESENT_EPIC | Wins (6) | 0.0 |
| `overlay.win.ultra` | WIN_PRESENT_ULTRA | Wins (6) | 0.0 |
| `symbol.wild` | SYMBOL_LAND_WILD | SFX (2) | 0.0 |
| `symbol.scatter` | SYMBOL_LAND_SCATTER | SFX (2) | 0.0 |
| `symbol.bonus` | SYMBOL_LAND_BONUS | SFX (2) | 0.0 |
| `symbol.hp1` | SYMBOL_LAND_HP1 | SFX (2) | 0.0 |
| `symbol.hp2` | SYMBOL_LAND_HP2 | SFX (2) | 0.0 |
| `symbol.hp3` | SYMBOL_LAND_HP3 | SFX (2) | 0.0 |
| `symbol.hp4` | SYMBOL_LAND_HP4 | SFX (2) | 0.0 |
| `symbol.lp1` | SYMBOL_LAND_LP1 | SFX (2) | 0.0 |
| `symbol.lp2` | SYMBOL_LAND_LP2 | SFX (2) | 0.0 |
| `jackpot.mini` | JACKPOT_MINI | Wins (6) | 0.0 |
| `jackpot.minor` | JACKPOT_MINOR | Wins (6) | 0.0 |
| `jackpot.major` | JACKPOT_MAJOR | Wins (6) | 0.0 |
| `jackpot.grand` | JACKPOT_GRAND | Wins (6) | 0.0 |
| `music.base` | MUSIC_BASE | Music (1) | 0.0 |
| `music.tension` | MUSIC_TENSION | Music (1) | 0.0 |
| `music.feature` | MUSIC_FEATURE | Music (1) | 0.0 |
| `feature.freespins` | FS_TRIGGER | SFX (2) | 0.0 |
| `feature.bonus` | BONUS_TRIGGER | SFX (2) | 0.0 |
| `feature.cascade` | CASCADE_START | SFX (2) | 0.0 |

### 8.4 Bus ID Constants

```dart
class SlotBusIds {
  static const int master = 0;
  static const int music = 1;
  static const int sfx = 2;
  static const int voice = 3;
  static const int ui = 4;
  static const int reels = 5;
  static const int wins = 6;
  static const int anticipation = 7;
}
```

### 8.5 Per-Reel Pan Formula

```dart
// Stereo spread across 5 reels
double panForReel(int reelIndex) {
  // reel.0 = -0.8 (far left)
  // reel.1 = -0.4
  // reel.2 =  0.0 (center)
  // reel.3 = +0.4
  // reel.4 = +0.8 (far right)
  return (reelIndex - 2) * 0.4;
}
```

### 8.6 Drop Target Visual States

| State | Border | Background | Glow |
|-------|--------|------------|------|
| Idle (Edit Mode) | Dashed cyan | Transparent | None |
| Hover | Solid cyan | 10% cyan | Subtle |
| Drag Over | Solid blue | 20% blue | Bright |
| Assigned | Solid green | 10% green | None |
| Error | Solid red | 10% red | Pulse |

### 8.7 Drop Flow

```
1. User drags audio from Browser/Pool
   ↓
2. DropTargetWrapper.onAcceptWithDetails()
   ↓
3. _targetIdToStage(targetId) → stage name
   ↓
4. _targetTypeToBusId(targetId) → bus ID
   ↓
5. MiddlewareProvider.createCompositeEvent()
   ↓
6. EventRegistry.registerEvent()
   ↓
7. Visual feedback (glow, count badge)
```

---

## 9. Keyboard Shortcuts

### 9.1 Global Shortcuts

| Key | Action | Context |
|-----|--------|---------|
| Space | Spin / Stop | Slot Preview |
| F11 | Toggle Fullscreen | Any |
| Escape | Exit / Close Panel | Any |
| Cmd+K | Command Palette | Any |
| Cmd+S | Save Project | Any |
| Cmd+Z | Undo | Any |
| Cmd+Shift+Z | Redo | Any |

### 9.2 Super-Tab Navigation

| Key | Action |
|-----|--------|
| 1 | STAGES super-tab |
| 2 | EVENTS super-tab |
| 3 | MIX super-tab |
| 4 | DSP super-tab |
| 5 | BAKE super-tab |
| ` | Toggle Lower Zone |

### 9.3 Sub-Tab Navigation

| Key | Action |
|-----|--------|
| Q | First sub-tab |
| W | Second sub-tab |
| E | Third sub-tab |
| R | Fourth sub-tab |

### 9.4 Slot Preview Shortcuts

| Key | Action |
|-----|--------|
| Space | Spin / Stop |
| M | Toggle Music |
| S | Toggle SFX |
| T | Toggle Turbo |
| A | Toggle Auto-spin |
| 1-7 | Force outcome (debug) |

### 9.5 Event Editor Shortcuts

| Key | Action |
|-----|--------|
| Delete | Delete selected layer |
| Cmd+D | Duplicate layer |
| Cmd+C | Copy layer(s) |
| Cmd+V | Paste layer(s) |
| Cmd+A | Select all layers |
| ↑/↓ | Navigate layers |

---

## 10. State Machine

### 10.1 Slot Preview States

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│    ┌──────────┐                                              │
│    │   IDLE   │←───────────────────────────────────────┐     │
│    └────┬─────┘                                        │     │
│         │ [SPIN pressed]                               │     │
│         ↓                                              │     │
│    ┌──────────┐                                        │     │
│    │ SPINNING │                                        │     │
│    └────┬─────┘                                        │     │
│         │ [All reels stopped]                          │     │
│         ↓                                              │     │
│    ┌────────────────┐                                  │     │
│    │ EVALUATING     │                                  │     │
│    └────────┬───────┘                                  │     │
│             │                                          │     │
│      ┌──────┴──────┐                                   │     │
│      │             │                                   │     │
│      ↓             ↓                                   │     │
│ [No Win]      [Has Win]                                │     │
│      │             │                                   │     │
│      │             ↓                                   │     │
│      │    ┌────────────────────┐                       │     │
│      │    │ WIN_PRESENTATION   │                       │     │
│      │    └────────┬───────────┘                       │     │
│      │             │ [Rollup complete]                 │     │
│      │             ↓                                   │     │
│      │    ┌────────────────────┐                       │     │
│      │    │ WIN_LINES_DISPLAY  │                       │     │
│      │    └────────┬───────────┘                       │     │
│      │             │ [All lines shown]                 │     │
│      └──────┬──────┘                                   │     │
│             │                                          │     │
│             │ [Feature?]                               │     │
│      ┌──────┴──────┐                                   │     │
│      │             │                                   │     │
│      ↓             ↓                                   │     │
│ [No Feature] [Has Feature]                             │     │
│      │             │                                   │     │
│      │             ↓                                   │     │
│      │    ┌────────────────────┐                       │     │
│      │    │ FEATURE_ACTIVE     │                       │     │
│      │    │ (FS/Bonus/Hold)    │                       │     │
│      │    └────────┬───────────┘                       │     │
│      │             │ [Feature complete]                │     │
│      └──────┬──────┘                                   │     │
│             │                                          │     │
│             └──────────────────────────────────────────┘     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 10.2 State Definitions

```dart
enum SlotPreviewState {
  idle,              // Ready for spin
  spinning,          // Reels rotating
  evaluating,        // Calculating wins
  winPresentation,   // Showing win plaque
  winLinesDisplay,   // Cycling win lines
  featureActive,     // In feature mode
}
```

### 10.3 State Transitions

| From | To | Trigger |
|------|-----|---------|
| idle | spinning | SPIN_START stage |
| spinning | evaluating | Last REEL_STOP |
| evaluating | idle | No win |
| evaluating | winPresentation | Has win |
| winPresentation | winLinesDisplay | Rollup complete |
| winLinesDisplay | idle | All lines shown (no feature) |
| winLinesDisplay | featureActive | Feature triggered |
| featureActive | idle | Feature complete |

### 10.4 Reel Animation States

```dart
enum ReelPhase {
  idle,           // Stationary
  accelerating,   // 0 → full speed (100ms)
  spinning,       // Constant speed (560ms+)
  decelerating,   // Slowing down (300ms)
  bouncing,       // Overshoot (200ms)
  stopped,        // Complete
}
```

---

## 11. Data Models

### 11.1 SlotCompositeEvent

```dart
class SlotCompositeEvent {
  final String id;              // Unique identifier
  final String name;            // Display name
  final String stage;           // Trigger stage
  final List<SlotEventLayer> layers;  // Audio layers
  final int busId;              // Audio bus
  final int priority;           // Voice priority (0-100)
  final bool looping;           // Loop playback
  final ContainerType containerType;  // none/blend/random/sequence
  final String? containerId;    // Container reference
  final DateTime createdAt;
  final DateTime modifiedAt;

  // Computed
  double get totalDuration;
  int get layerCount;

  // Serialization
  Map<String, dynamic> toJson();
  factory SlotCompositeEvent.fromJson(Map<String, dynamic> json);

  // Copy
  SlotCompositeEvent copyWith({...});
}
```

### 11.2 SlotEventLayer

```dart
class SlotEventLayer {
  final String id;              // Unique identifier
  final String audioPath;       // Audio file path
  final String name;            // Display name
  final double volume;          // 0.0-2.0 (100% = 1.0)
  final double pan;             // -1.0 (L) to +1.0 (R)
  final int offsetMs;           // Delay before playing
  final int fadeInMs;           // Fade in duration
  final int fadeOutMs;          // Fade out duration
  final int trimStartMs;        // Start trim
  final int trimEndMs;          // End trim
  final int busId;              // Bus override
  final ActionType actionType;  // play/stop/pause/setVolume
  final bool muted;
  final bool solo;

  // Computed
  double get durationSeconds;
  String get fileName;

  // Serialization
  Map<String, dynamic> toJson();
  factory SlotEventLayer.fromJson(Map<String, dynamic> json);
}
```

### 11.3 SlotLabSpinResult

```dart
class SlotLabSpinResult {
  final String spinId;          // Unique spin identifier
  final List<List<int>> grid;   // Symbol IDs per reel
  final double totalWin;        // Win amount
  final double bet;             // Bet amount
  final bool isWin;             // Has any win
  final String? winTier;        // small/big/mega/epic/ultra
  final List<WinLine> winLines; // Winning paylines
  final bool triggeredFeature;  // Free spins/bonus triggered
  final FeatureType? featureType;
  final int? freeSpinsAwarded;
  final Map<String, dynamic> metadata;
}
```

### 11.4 SlotLabStageEvent

```dart
class SlotLabStageEvent {
  final String stageType;       // Stage name (SPIN_START, REEL_STOP_0, etc.)
  final double timestampMs;     // Time offset from spin start
  final Map<String, dynamic> payload;  // Stage-specific data
  final Map<String, dynamic> rawStage; // Raw Rust data

  // Helpers
  bool get isReelStop => stageType.startsWith('REEL_STOP');
  bool get isWinPresent => stageType.startsWith('WIN_PRESENT');
  int? get reelIndex;           // Extract from REEL_STOP_N
}
```

### 11.5 SymbolDefinition

```dart
class SymbolDefinition {
  final String id;              // 'hp1', 'wild', 'scatter'
  final String name;            // 'High Pay 1', 'Wild'
  final String emoji;           // '💎', '🃏'
  final SymbolType type;        // wild/scatter/bonus/highPay/etc.
  final Set<SymbolAudioContext> audioContexts;

  // Stage name generators
  String get stageIdLand => 'SYMBOL_LAND_${id.toUpperCase()}';
  String get stageIdWin => 'WIN_SYMBOL_HIGHLIGHT_${id.toUpperCase()}';
  String get stageIdExpand => 'SYMBOL_EXPAND_${id.toUpperCase()}';
}

enum SymbolType {
  wild,
  scatter,
  bonus,
  highPay,
  mediumPay,
  lowPay,
  multiplier,
  collector,
  mystery,
  custom,
}

enum SymbolAudioContext {
  land,       // Symbol lands on reel
  win,        // Symbol part of win
  expand,     // Wild expansion
  lock,       // Hold & Win lock
  transform,  // Symbol transforms
  collect,    // Collector trigger
  stack,      // Stacked symbol
  trigger,    // Feature trigger
  anticipation, // Anticipation
}
```

### 11.6 WinTierConfig

```dart
class WinTierConfig {
  final String id;
  final String name;
  final List<WinTierThreshold> tiers;

  WinTier getTierForMultiplier(double multiplier);
}

class WinTierThreshold {
  final WinTier tier;
  final double minMultiplier;
  final double maxMultiplier;
  final String triggerStage;
  final double rtpcValue;
  final int rollupDurationMs;
  final int rollupTickRate;
}

enum WinTier {
  noWin,
  smallWin,    // < 5x
  bigWin,      // 5x - 15x (FIRST major tier)
  superWin,    // 15x - 30x
  megaWin,     // 30x - 60x
  epicWin,     // 60x - 100x
  ultraWin,    // 100x+
}
```

---

## 12. Provider Integration

### 12.1 Provider Hierarchy

```
MultiProvider
├── SlotLabProvider              // Synthetic slot engine state
├── SlotLabProjectProvider       // Project persistence (symbols, contexts)
├── MiddlewareProvider           // Event/container management (SSoT)
├── AleProvider                  // Adaptive Layer Engine
├── MixerDSPProvider             // Bus mixing
├── EventSystemProvider          // Event registry
└── StageIngestProvider          // External engine integration
```

### 12.2 SlotLabProvider

**File:** `flutter_ui/lib/providers/slot_lab_provider.dart`

```dart
class SlotLabProvider extends ChangeNotifier {
  // ─── Engine State ─────────────────────────────────
  bool _initialized = false;
  bool _isSpinning = false;
  int _spinCount = 0;

  // ─── Spin Result ─────────────────────────────────
  SlotLabSpinResult? _lastResult;
  List<SlotLabStageEvent> _lastStages = [];

  // ─── Configuration ────────────────────────────────
  double _volatilitySlider = 0.5;
  VolatilityPreset _volatilityPreset = VolatilityPreset.medium;
  TimingProfileType _timingProfile = TimingProfileType.normal;
  double _betAmount = 1.0;

  // ─── Stage Playback ───────────────────────────────
  bool _isPlayingStages = false;
  bool _isReelsSpinning = false;
  bool _isWinPresentationActive = false;

  // ─── Public API ───────────────────────────────────
  Future<void> init();
  Future<SlotLabSpinResult?> spin();
  Future<SlotLabSpinResult?> spinForced(ForcedOutcome outcome);
  void stopStagePlayback();
  void pauseStagePlayback();
  void resumeStagePlayback();

  // ─── Callbacks ────────────────────────────────────
  void Function(int reelIndex, String reason, {int tensionLevel})? onAnticipationStart;
  void Function(int reelIndex)? onAnticipationEnd;
  void Function(int reelIndex)? onReelVisualStop;
}
```

### 12.3 SlotLabProjectProvider

**File:** `flutter_ui/lib/providers/slot_lab_project_provider.dart`

```dart
class SlotLabProjectProvider extends ChangeNotifier {
  // ─── Symbol Configuration ─────────────────────────
  List<SymbolDefinition> _symbols = [];
  List<SymbolAudioAssignment> _symbolAudio = [];

  // ─── Context Configuration ────────────────────────
  List<ContextDefinition> _contexts = [];
  List<MusicLayerAssignment> _musicLayers = [];

  // ─── GDD Import ───────────────────────────────────
  GameDesignDocument? _importedGdd;
  GddGridConfig? get gridConfig;
  List<GddSymbol> get gddSymbols;

  // ─── Public API ───────────────────────────────────
  void addSymbol(SymbolDefinition symbol);
  void removeSymbol(String symbolId);
  void assignSymbolAudio(String symbolId, SymbolAudioContext context, String audioPath);
  void assignMusicLayer(String contextId, int layerIndex, String audioPath);
  void importGdd(GameDesignDocument gdd, {List<SymbolDefinition>? generatedSymbols});

  // ─── Bulk Operations ──────────────────────────────
  void resetAllSymbolAudio();
  void resetAllMusicLayers();
  Map<String, int> getAudioAssignmentCounts();
}
```

### 12.4 MiddlewareProvider (SSoT for Events)

**File:** `flutter_ui/lib/providers/middleware_provider.dart`

```dart
class MiddlewareProvider extends ChangeNotifier {
  // ─── Composite Events (Single Source of Truth) ────
  List<SlotCompositeEvent> _compositeEvents = [];

  // ─── Event CRUD ───────────────────────────────────
  SlotCompositeEvent createCompositeEvent({
    required String name,
    required String stage,
    int busId = 0,
    int priority = 50,
    bool looping = false,
  });

  void updateCompositeEvent(SlotCompositeEvent event);
  void deleteCompositeEvent(String eventId);
  void duplicateCompositeEvent(String eventId);

  // ─── Layer Operations ─────────────────────────────
  void addLayerToEvent(String eventId, SlotEventLayer layer);
  void updateEventLayer(String eventId, SlotEventLayer layer);
  void removeLayerFromEvent(String eventId, String layerId);
  void reorderLayers(String eventId, int oldIndex, int newIndex);

  // ─── Preview ──────────────────────────────────────
  void previewCompositeEvent(String eventId);
  void stopPreview();
}
```

---

## 13. Feature Modules

### 13.1 Free Spins Module

**Stages:**
```
FS_TRIGGER          → Feature triggered
FS_INTRO            → Intro sequence
FS_ENTER            → Transition to FS mode
FS_SPIN             → Each free spin
FS_RETRIGGER        → Additional spins awarded
FS_TOTAL_WIN        → Summary display
FS_EXIT             → Return to base game
FS_MUSIC_START      → Feature music begins
FS_MUSIC_LOOP       → Looping feature music
FS_MUSIC_END        → Feature music fades
```

**State Variables:**
```dart
bool _inFreeSpins = false;
int _freeSpinsRemaining = 0;
int _freeSpinsTotal = 0;
double _freeSpinsTotalWin = 0.0;
int _currentFreeSpinNumber = 0;
```

### 13.2 Hold & Win Module

**Stages:**
```
HOLD_TRIGGER        → Feature triggered
HOLD_ENTER          → Grid transition
HOLD_SPIN           → Each respin
HOLD_LAND           → Coin/symbol lands
HOLD_COLLECT        → Value collected
HOLD_RESPIN_RESET   → Respins reset
HOLD_UPGRADE        → Symbol upgrade
HOLD_COMPLETE       → Feature ends
HOLD_JACKPOT        → Jackpot triggered during hold
```

**State Variables:**
```dart
bool _inHoldWin = false;
int _holdRespinsRemaining = 3;
int _holdRespinsTotal = 3;
double _holdCollectedValue = 0.0;
Set<(int, int)> _lockedPositions = {};
```

### 13.3 Jackpot Module

**Stages:**
```
JACKPOT_TRIGGER     → Jackpot triggered (500ms alert)
JACKPOT_BUILDUP     → Rising tension (2000ms)
JACKPOT_REVEAL      → Tier revealed (1000ms)
JACKPOT_MINI        → Mini tier (5000ms)
JACKPOT_MINOR       → Minor tier (8000ms)
JACKPOT_MAJOR       → Major tier (12000ms)
JACKPOT_GRAND       → Grand tier (20000ms)
JACKPOT_CELEBRATION → Looping celebration
JACKPOT_COLLECT     → Amount awarded
JACKPOT_END         → Return to game (500ms)
```

**Tier Values (Default):**
```dart
const jackpotSeeds = {
  'mini': 100.0,
  'minor': 500.0,
  'major': 2500.0,
  'grand': 10000.0,
};

const jackpotContributionRate = 0.005; // 0.5% of bet
```

### 13.4 Cascade/Tumble Module

**Stages:**
```
CASCADE_START       → Cascade begins
CASCADE_REMOVE      → Winning symbols removed
CASCADE_DROP        → New symbols fall
CASCADE_STEP        → Each cascade level (⚡ pooled)
CASCADE_MULTIPLIER  → Multiplier increases
CASCADE_END         → No more wins
```

**Timing:**
```dart
const cascadeRemoveDuration = 300;  // ms
const cascadeDropDuration = 400;    // ms
const cascadeStepDelay = 100;       // ms between levels
```

---

## 14. GDD Import Flow

### 14.1 Overview

GDD (Game Design Document) import enables automatic configuration from game specifications.

**Service:** `flutter_ui/lib/services/gdd_import_service.dart`

### 14.2 GDD JSON Structure

```json
{
  "name": "Zeus Slots",
  "version": "1.0.0",
  "theme": "greek",
  "grid": {
    "rows": 3,
    "columns": 5,
    "mechanic": "ways",
    "ways": 243
  },
  "symbols": [
    {
      "id": "zeus",
      "name": "Zeus",
      "tier": "premium",
      "payouts": { "3": 50, "4": 200, "5": 1000 },
      "isWild": false,
      "isScatter": false
    }
  ],
  "features": [
    {
      "id": "free_spins",
      "name": "Olympus Free Spins",
      "type": "free_spins",
      "triggerSymbol": "scatter",
      "triggerCount": 3
    }
  ],
  "math": {
    "rtp": 96.5,
    "volatility": "high",
    "hitFrequency": 0.25
  }
}
```

### 14.3 Import Flow

```
1. User opens GDD Import wizard
   ↓
2. Paste JSON / Load file / Extract from PDF
   ↓
3. GddImportService.parseGdd()
   ↓
4. GddPreviewDialog shows:
   - Grid mockup (columns × rows)
   - Symbol list with auto-assigned emojis
   - Paytable preview
   - Math panel (RTP, volatility)
   ↓
5. User clicks "Apply Configuration"
   ↓
6. SlotLabProjectProvider.importGdd()
   ↓
7. SlotLabProvider.initEngineFromGdd()
   ↓
8. _populateSlotSymbolsFromGdd()
   ↓
9. Grid settings applied
   ↓
10. Fullscreen preview opens
```

### 14.4 Auto-Symbol Emoji Detection

```dart
// Theme-specific mapping (90+ symbols)
const symbolEmojiMap = {
  // Greek
  'zeus': '⚡', 'poseidon': '🔱', 'hades': '💀',
  'athena': '🦉', 'medusa': '🐍', 'pegasus': '🦄',

  // Egyptian
  'ra': '☀️', 'anubis': '🐺', 'cleopatra': '👑',
  'scarab': '🪲', 'pyramid': '🔺', 'sphinx': '🦁',

  // Asian
  'dragon': '🐉', 'tiger': '🐯', 'phoenix': '🔥',
  'koi': '🐟', 'panda': '🐼', 'bamboo': '🎋',

  // Standard
  'wild': '🃏', 'scatter': '💫', 'bonus': '🎁',
  'a': '🅰️', 'k': '👑', 'q': '👸', 'j': '🤴',
};
```

### 14.5 Rust Engine Integration

```dart
// Convert GDD to Rust-expected format
Map<String, dynamic> toRustJson() => {
  'game': {
    'name': name,
    'volatility': volatility,
    'target_rtp': rtp,
  },
  'grid': {
    'reels': columns,
    'rows': rows,
    'paylines': paylines,
  },
  'symbols': symbols.map((s) => {
    'id': index,
    'name': s.name,
    'type': symbolTypeStr(s),
    'pays': payoutsToArray(s.payouts),
    'tier': tierToNum(s.tier),
  }).toList(),
  'math': {
    'symbol_weights': generateWeightsByTier(),
  },
};
```

---

## 15. Export System

### 15.1 Export Formats

| Format | Use Case | Files Generated |
|--------|----------|-----------------|
| **Universal** | FluxForge native | `.ffbank` archive |
| **Unity** | Unity integration | C# scripts, JSON config |
| **Unreal** | Unreal Engine | C++ headers, JSON config |
| **Howler.js** | Web games | TypeScript, JSON config |
| **FMOD** | FMOD Studio | Bank structure |

### 15.2 Universal Package Structure

```
MyGame.ffbank/
├── manifest.json           # Package manifest
├── events/
│   ├── events.json         # Event definitions
│   └── stages.json         # Stage mappings
├── audio/
│   ├── base_game/          # Base game sounds
│   ├── features/           # Feature sounds
│   └── music/              # Music files
├── containers/
│   ├── blend.json          # Blend containers
│   ├── random.json         # Random containers
│   └── sequence.json       # Sequence containers
├── config/
│   ├── buses.json          # Bus configuration
│   ├── rtpc.json           # RTPC definitions
│   └── states.json         # State groups
└── metadata/
    ├── gdd.json            # Imported GDD
    └── version.json        # Version info
```

### 15.3 Export Flow

```
1. User opens BAKE super-tab
   ↓
2. Selects export format
   ↓
3. Configures options:
   - Audio format (WAV/FLAC/MP3/OGG)
   - Compression
   - Platform (Desktop/Mobile/Web)
   ↓
4. Click "Bake"
   ↓
5. Validate all events
   ↓
6. Process audio (normalization, format conversion)
   ↓
7. Generate code/config files
   ↓
8. Create archive
   ↓
9. Save to disk
```

### 15.4 Unity Export

**Generated Files:**

```csharp
// FFEvents.cs
public enum FFEvent {
    SpinStart = 1000,
    ReelStop0 = 1001,
    WinPresentBig = 1200,
    // ...
}

public static class FFAudioEvents {
    public static void Post(FFEvent evt) { /* ... */ }
    public static void PostWithCallback(FFEvent evt, Action<FFCallbackInfo> callback) { /* ... */ }
}

// FFRtpc.cs
public enum FFRTPC {
    WinMultiplier = 100,
    BetLevel = 101,
    Volatility = 102,
}

// FFAudioManager.cs
public class FFAudioManager : MonoBehaviour {
    public void Initialize();
    public void PostEvent(FFEvent evt);
    public void SetRTPC(FFRTPC rtpc, float value);
    public void SetState(string group, string state);
}
```

---

## 16. Audio Systems

### 16.1 EventRegistry

**File:** `flutter_ui/lib/services/event_registry.dart`

```dart
class EventRegistry {
  // ─── Event Storage ────────────────────────────────
  final Map<String, AudioEvent> _events = {};          // eventId → event
  final Map<String, Set<String>> _stageToEvents = {};  // stage → eventIds

  // ─── Voice Tracking ───────────────────────────────
  final Map<int, PlayingVoice> _activeVoices = {};     // voiceId → info
  final Map<int, int> _reelSpinLoopVoices = {};        // reelIndex → voiceId

  // ─── Public API ───────────────────────────────────
  void registerEvent(AudioEvent event);
  void unregisterEvent(String eventId);
  void triggerStage(String stage);
  void stopEvent(String eventId);
  void stopAllEvents();

  // ─── Callbacks ────────────────────────────────────
  Stream<EventTriggerInfo> get onEventTriggered;
}
```

### 16.2 AudioPool

**File:** `flutter_ui/lib/services/audio_pool.dart`

```dart
class AudioPool {
  // ─── Pool Configuration ───────────────────────────
  static const int defaultPoolSize = 8;
  static const int maxPoolSize = 32;
  static const Duration idleTimeout = Duration(seconds: 30);

  // ─── Pooled Events ────────────────────────────────
  static const pooledEvents = {
    'REEL_STOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2', 'REEL_STOP_3', 'REEL_STOP_4',
    'CASCADE_STEP', 'ROLLUP_TICK', 'ROLLUP_TICK_FAST',
    'WIN_LINE_SHOW', 'WIN_SYMBOL_HIGHLIGHT',
    'WHEEL_TICK', 'TRAIL_MOVE_STEP',
    'UI_BUTTON_PRESS', 'UI_BUTTON_HOVER',
  };

  // ─── Public API ───────────────────────────────────
  int acquire(String eventKey, String audioPath, int busId, double volume);
  void release(int voiceId);
  double get hitRate;
}
```

### 16.3 Stage Audio Mapper

**File:** `flutter_ui/lib/services/stage_audio_mapper.dart`

```dart
class StageAudioMapper {
  // ─── Fallback Resolution ──────────────────────────
  // REEL_STOP_0 → REEL_STOP (if REEL_STOP_0 not found)
  String? getFallbackStage(String stage);

  // ─── Loop Detection ───────────────────────────────
  bool isLooping(String stage);  // MUSIC_*, AMBIENT_*, *_LOOP

  // ─── Priority Mapping ─────────────────────────────
  int getPriority(String stage);  // 0-100

  // ─── Bus Mapping ──────────────────────────────────
  int getBusId(String stage);  // SlotBusIds
}
```

### 16.4 Bus System

```dart
// Bus hierarchy
Master (0)
├── Music (1)
├── SFX (2)
├── Voice (3)
├── UI (4)
├── Reels (5)
├── Wins (6)
└── Anticipation (7)

// Bus routing
Stage → _stageToBus() → busId → AudioPlaybackService.playFileToBus()
```

---

## 17. Visual Effects

### 17.1 Anticipation System

**Per-Reel Tension Levels:**

| Level | Color | Volume | Pitch | Glow Radius |
|-------|-------|--------|-------|-------------|
| L1 | Gold #FFD700 | 0.6x | +1st | 8px |
| L2 | Orange #FFA500 | 0.7x | +2st | 12px |
| L3 | Red-Orange #FF6347 | 0.8x | +3st | 16px |
| L4 | Red #FF4500 | 0.9x | +4st | 20px |

**Stage Format:**
```
ANTICIPATION_TENSION_R{reel}_L{level}
Example: ANTICIPATION_TENSION_R3_L2
```

### 17.2 Win Plaque Animation

**Animation Sequence:**

1. **Screen Flash** (150ms)
   - White/gold flash
   - Opacity: 0.8 → 0.0

2. **Plaque Entry** (300ms)
   - Scale: 0.5 → 1.0 + tier multiplier
   - Opacity: 0.0 → 1.0
   - Slide: 80px from bottom

3. **Glow Pulse** (400ms, repeating)
   - Intensity: 0.7 → 1.0
   - Color matches tier

4. **Particle Burst**
   - Count by tier: SMALL=10, BIG=20, SUPER=30, MEGA=45, EPIC=60, ULTRA=80

**Tier Scale Multipliers:**
```dart
const tierScales = {
  'ULTRA': 1.25,
  'EPIC': 1.20,
  'MEGA': 1.15,
  'SUPER': 1.10,
  'BIG': 1.05,
  'SMALL': 1.00,
};
```

### 17.3 Win Line Painter

```dart
class _WinLinePainter extends CustomPainter {
  void paint(Canvas canvas, Size size) {
    // 1. Outer glow
    final glowPaint = Paint()
      ..color = lineColor.withOpacity(0.4)
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);

    // 2. Main line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    // 3. White core
    final corePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // 4. Glowing dots at symbol positions
    for (final position in winPositions) {
      canvas.drawCircle(position, 6.0, glowPaint);
      canvas.drawCircle(position, 4.0, linePaint);
    }
  }
}
```

---

## 18. Error Handling

### 18.1 Error Categories

| Category | Examples | Handling |
|----------|----------|----------|
| **FFI Errors** | Library not loaded, function not found | Graceful degradation, warning overlay |
| **Audio Errors** | File not found, format unsupported | Skip with warning, use placeholder |
| **State Errors** | Invalid stage, missing event | Log warning, continue |
| **Config Errors** | Invalid GDD, malformed JSON | Show dialog, prevent import |
| **Resource Errors** | Out of voices, memory limit | Steal oldest voice, warn |

### 18.2 Error Display

```dart
// FFI not loaded
Widget _buildFfiWarning() {
  return Container(
    color: Colors.orange.withOpacity(0.2),
    child: Row(
      children: [
        Icon(Icons.warning, color: Colors.orange),
        Text('Rust library not loaded. Audio features disabled.'),
        TextButton(onPressed: _retry, child: Text('Retry')),
      ],
    ),
  );
}

// Missing audio
void _handleMissingAudio(String path, String stage) {
  debugPrint('[EventRegistry] ⚠️ Audio not found: $path for $stage');
  _eventLog.add(EventLogEntry(
    stage: stage,
    status: EventStatus.warning,
    message: 'Audio file not found',
  ));
}
```

### 18.3 Validation

```dart
class EventValidator {
  ValidationResult validate(SlotCompositeEvent event) {
    final errors = <String>[];
    final warnings = <String>[];

    // Required fields
    if (event.name.isEmpty) errors.add('Event name is required');
    if (event.stage.isEmpty) errors.add('Stage is required');
    if (event.layers.isEmpty) warnings.add('Event has no audio layers');

    // Layer validation
    for (final layer in event.layers) {
      if (!File(layer.audioPath).existsSync()) {
        warnings.add('Audio file not found: ${layer.audioPath}');
      }
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}
```

---

## Appendix A: File Reference

| Component | File Path |
|-----------|-----------|
| Main Screen | `flutter_ui/lib/screens/slot_lab_screen.dart` |
| Premium Preview | `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` |
| Ultimate Audio Panel | `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart` |
| Events Panel | `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` |
| Audio Browser Dock | `flutter_ui/lib/widgets/slot_lab/audio_browser_dock.dart` |
| Lower Zone Widget | `flutter_ui/lib/widgets/lower_zone/slotlab_lower_zone_widget.dart` |
| Lower Zone Controller | `flutter_ui/lib/widgets/lower_zone/slotlab_lower_zone_controller.dart` |
| Drop Target Wrapper | `flutter_ui/lib/widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` |
| Slot Preview Widget | `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` |
| Reel Animation | `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` |
| SlotLab Provider | `flutter_ui/lib/providers/slot_lab_provider.dart` |
| Project Provider | `flutter_ui/lib/providers/slot_lab_project_provider.dart` |
| Event Registry | `flutter_ui/lib/services/event_registry.dart` |
| Audio Pool | `flutter_ui/lib/services/audio_pool.dart` |
| GDD Import Service | `flutter_ui/lib/services/gdd_import_service.dart` |
| Stage Audio Mapper | `flutter_ui/lib/services/stage_audio_mapper.dart` |
| Data Models | `flutter_ui/lib/models/slot_lab_models.dart` |
| Audio Events | `flutter_ui/lib/models/slot_audio_events.dart` |
| Lower Zone Types | `flutter_ui/lib/widgets/lower_zone/lower_zone_types.dart` |

---

## Appendix B: Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-20 | Initial SlotLab implementation |
| 1.5.0 | 2026-01-23 | V6 layout, super-tabs, symbol strip |
| 1.8.0 | 2026-01-25 | Industry-standard win presentation |
| 1.9.0 | 2026-01-26 | Ultimate Audio Panel V8, bottom dock |
| 2.0.0 | 2026-01-30 | Complete specification document |

---

**End of Specification**

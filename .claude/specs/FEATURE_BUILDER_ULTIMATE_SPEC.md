# 🎰 FEATURE BUILDER PANEL — Ultimate Specification

**Version:** 1.0.0
**Created:** 2026-02-01
**Author:** Claude Opus 4.5 + User Vision
**Status:** APPROVED FOR IMPLEMENTATION

---

## 1. EXECUTIVE SUMMARY

Feature Builder Panel transformiše SlotLab iz "audio authoring tool-a" u **kompletni no-code slot design studio**.

**Filozofija:** Dizajner čekira šta igra ima → SlotLab automatski generiše SVE ostalo.

### Šta Feature Builder generiše:

| Output | Opis |
|--------|------|
| **Mockup Layout** | Grid, symbols, overlays |
| **State Machine** | Game flow, feature transitions |
| **Outcome Controls** | Relevantne force opcije |
| **Stage Definitions** | 60+ audio trigger points |
| **Audio Hookovi** | Per-feature audio mappings |
| **Rust Engine Config** | Full-stack engine sync |

### Šta Feature Builder NIJE:

- ❌ Code editor
- ❌ Math model calculator
- ❌ Audio editor
- ❌ Animation timeline

Feature Builder je **konfigurator** — čist, deklarativan, bez runtime logike u panelu.

---

## 2. PANEL ARCHITECTURE

### 2.1 Panel Type: Dockable Floating Panel

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SLOTLAB HEADER                                              [Feature ▼]   │
├─────────────────────┬───────────────────────────────────────────────────────┤
│                     │                                                       │
│  ┌───────────────┐  │                  SLOT MOCKUP                          │
│  │ FEATURE       │  │              (Live Preview Area)                      │
│  │ BUILDER       │  │                                                       │
│  │ PANEL         │  │         [🎰] [🎰] [🎰] [🎰] [🎰]                      │
│  │               │  │         [🎰] [🎰] [🎰] [🎰] [🎰]                      │
│  │ (Dockable)    │  │         [🎰] [🎰] [🎰] [🎰] [🎰]                      │
│  │               │  │                                                       │
│  │ Width: 380px  │  │              [ SPIN ]  [ STOP ]                       │
│  │ Min: 320px    │  │                                                       │
│  │ Max: 500px    │  │         Balance: 1000.00  Bet: 1.00                   │
│  │               │  │                                                       │
│  └───────────────┘  │                                                       │
│                     │                                                       │
├─────────────────────┴───────────────────────────────────────────────────────┤
│  LOWER ZONE (Audio Panel, Events, etc.)                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Docking Capabilities

| Dock Position | Behavior |
|---------------|----------|
| **Left** | Default, side-by-side with mockup |
| **Right** | Mirror of left |
| **Floating** | Detached window, stays on top |
| **Hidden** | Collapsed to toolbar button |

**Panel Controls:**
- Drag header to reposition
- Double-click header to toggle float/dock
- Edge drag to resize
- Close button (X) to hide
- Pin button to keep visible across sections

### 2.3 Panel Internal Layout

```
┌─────────────────────────────────────────┐
│  FEATURE BUILDER              [≡] [📌] [×] │  ← Header with dock controls
├─────────────────────────────────────────┤
│  [Preset: Classic 5x3 ▼] [Save] [Load]  │  ← Preset bar
├─────────────────────────────────────────┤
│                                         │
│  ▼ CORE BLOCKS                          │  ← Collapsible section
│  ┌─────────────────────────────────────┐│
│  │ ☑ Game Core          [⚙]           ││  ← Block with settings button
│  │ ☑ Grid               [⚙]           ││
│  │ ☑ Symbol Set         [⚙]           ││
│  └─────────────────────────────────────┘│
│                                         │
│  ▼ FEATURE BLOCKS                       │
│  ┌─────────────────────────────────────┐│
│  │ ☑ Free Spins         [⚙] ⚠️        ││  ← Warning icon for dependencies
│  │ ☐ Respin             [⚙]           ││
│  │ ☐ Hold & Win         [⚙]           ││
│  │ ☑ Cascades           [⚙]           ││
│  │ ☐ Collector          [⚙]           ││
│  └─────────────────────────────────────┘│
│                                         │
│  ▼ PRESENTATION BLOCKS                  │
│  ┌─────────────────────────────────────┐│
│  │ ☑ Win Presentation   [⚙]           ││
│  │ ☐ Music States       [⚙]           ││
│  └─────────────────────────────────────┘│
│                                         │
├─────────────────────────────────────────┤
│  ACTIVE: 6 blocks    WARNINGS: 1        │  ← Status bar
├─────────────────────────────────────────┤
│  [Apply Configuration]  [Reset All]     │  ← Action buttons
└─────────────────────────────────────────┘
```

### 2.4 Block Settings Slide-Out

Kada se klikne [⚙], otvara se slide-out panel SA DESNE STRANE:

```
┌────────────────────────┬────────────────────────────────────┐
│  FEATURE BUILDER       │  FREE SPINS SETTINGS              │
│                        │                                    │
│  ▼ CORE BLOCKS         │  Trigger Type                      │
│  ...                   │  ○ Scatter Count (3+)              │
│                        │  ● Meter Fill                      │
│  ▼ FEATURE BLOCKS      │  ○ Instant (Buy Feature)           │
│  ☑ Free Spins    [⚙]◀──│                                    │
│  ...                   │  Spin Count                        │
│                        │  ○ Fixed: [12] spins               │
│                        │  ● Dynamic: [8-20] range           │
│                        │                                    │
│                        │  Retrigger                         │
│                        │  ☑ Enabled                         │
│                        │  └─ Max retriggers: [3]            │
│                        │                                    │
│                        │  Multiplier                        │
│                        │  ☑ Progressive (starts at 1x)      │
│                        │  └─ Step: [+1x] per [5] spins      │
│                        │                                    │
│                        │  ──────────────────────────────    │
│                        │  DEPENDENCIES                      │
│                        │  ├─ Enables: Respin (in FS)        │
│                        │  ├─ Modifies: Win Presentation     │
│                        │  └─ Audio: 8 stages registered     │
│                        │                                    │
│                        │  [Done]                            │
└────────────────────────┴────────────────────────────────────┘
```

---

## 3. BLOCK SPECIFICATIONS

### 3.1 CORE BLOCKS (Always Active)

#### 3.1.1 GAME CORE Block

**Purpose:** Definiše fundamentalni tip igre.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Pay Model** | Lines, Ways, Clusters, Cascades | Lines | Win evaluation logic |
| **Spin Type** | Normal, Turbo, Quick | Normal | Animation timing |
| **Presentation Style** | Classic, Modern, Arcade | Modern | UI theme hints |
| **Base RTP Target** | 92% - 98% | 96% | Math hints (not enforced) |
| **Volatility** | Low, Medium, High, Very High | Medium | Feature frequency |

**Generated Outputs:**
- `GameMode` enum selection
- Base state machine (IDLE → SPINNING → EVALUATING → PRESENTING → IDLE)
- Timing profile selection

**Rust Mapping:**
```rust
SlotConfig {
    volatility: VolatilityProfile::medium(),
    // ... other fields
}
```

#### 3.1.2 GRID Block

**Purpose:** Definiše vizuelni i logički grid.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Reels** | 3-8 | 5 | Horizontal positions |
| **Rows** | 2-7 | 3 | Vertical positions |
| **Grid Shape** | Regular, Masked, Dynamic | Regular | Position validity |
| **Cell Size** | Small, Medium, Large | Medium | Symbol rendering |
| **Paylines** | 1-100 (if Lines mode) | 20 | Win patterns |
| **Ways** | 243, 1024, 117649 (if Ways mode) | 243 | Win calculation |

**Grid Shape Options:**
```
REGULAR:        MASKED:           DYNAMIC (Megaways):
[■][■][■][■][■]  [■][■][■][■][■]   [■■][■■■][■■■■][■■■][■■]
[■][■][■][■][■]  [ ][■][■][■][ ]   [■■][■■■][■■■■][■■■][■■]
[■][■][■][■][■]  [■][■][■][■][■]   [■][■■][■■■][■■][■]
```

**Generated Outputs:**
- Reel containers
- Symbol drop zones
- Gravity vectors (for Cascades)
- Position validity mask

**Rust Mapping:**
```rust
GridSpec {
    reels: 5,
    rows: 3,
    paylines: Some(20),
    ways: None,
}
```

#### 3.1.3 SYMBOL SET Block

**Purpose:** Definiše strukturu simbola.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Low Pay Count** | 1-6 | 4 | 9, 10, J, Q, K, A equivalents |
| **Mid Pay Count** | 1-4 | 2 | Theme symbols |
| **High Pay Count** | 1-3 | 2 | Premium symbols |
| **Wild** | None, Standard, Expanding, Sticky, Multiplier | Standard | Substitution logic |
| **Scatter** | None, Standard, Collecting | Standard | Feature triggers |
| **Bonus** | None, Standard | None | Bonus game triggers |

**Symbol Behavior Flags:**
- ☐ Can Transform (Mystery symbols)
- ☐ Can Explode (Cascades)
- ☐ Can Split (Symbol splitting)
- ☐ Can Upgrade (Symbol upgrades)
- ☐ Can Stack (Stacked symbols)

**Generated Outputs:**
- Symbol ID registry
- Per-symbol audio stages (SYMBOL_LAND_*, WIN_SYMBOL_HIGHLIGHT_*)
- Animation placeholder hooks
- Win evaluation weights

**Rust Mapping:**
```rust
SymbolSetConfig {
    symbols: vec![
        SymbolConfig { id: 0, name: "LP1", tier: SymbolTier::Low, ... },
        // ...
    ],
    wild_id: Some(10),
    scatter_id: Some(11),
}
```

---

### 3.2 FEATURE BLOCKS (Checkable)

#### 3.2.1 FREE SPINS Block

**Purpose:** Omogućava free spins feature.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Trigger Type** | Scatter Count, Meter, Instant | Scatter Count | How FS starts |
| **Scatter Count** | 3, 4, 5 (if Scatter trigger) | 3 | Trigger threshold |
| **Spin Count Mode** | Fixed, Dynamic, Player Choice | Fixed | Spin allocation |
| **Fixed Spins** | 5-50 | 10 | If Fixed mode |
| **Dynamic Range** | [min]-[max] | 8-20 | If Dynamic mode |
| **Retrigger** | Disabled, Enabled | Enabled | Can extend FS |
| **Max Retriggers** | 1-10 | 3 | If Retrigger enabled |
| **Multiplier Mode** | None, Fixed, Progressive | None | Win multiplier |
| **Fixed Multiplier** | 2x-10x | 3x | If Fixed |
| **Progressive Step** | +1x per N spins | +1x/5 | If Progressive |
| **Special Reels** | None, Expanding Wilds, Sticky Wilds, Extra Wilds | None | FS mechanics |

**Dependencies:**
- **Enables:** Respin (context: "in Free Spins")
- **Modifies:** Win Presentation (adds FS multiplier display)
- **Requires:** Symbol Set (needs Scatter symbol)

**Generated Stages (8):**
```
FS_TRIGGER          → Scatter lands, triggers free spins
FS_INTRO            → Transition animation
FS_SPIN_START       → Each free spin begins
FS_SPIN_LOOP        → Reel spinning (looping audio)
FS_SPIN_END         → Each free spin ends
FS_RETRIGGER        → Additional spins awarded
FS_TOTAL_WIN        → Final win presentation
FS_OUTRO            → Exit transition
```

**Rust Mapping:**
```rust
FeatureConfig {
    free_spins: true,
    free_spins_range: (10, 10),  // Fixed 10
    free_spins_multiplier: 1.0,
    // ...
}
```

#### 3.2.2 RESPIN Block

**Purpose:** Omogućava respin mehaniku.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Context** | Base Game, Free Spins, Both | Base Game | Where respin works |
| **Trigger** | Any Win, Specific Symbols, Random | Any Win | When respin triggers |
| **Lock Symbols** | None, Winners, Specific | Winners | What stays |
| **Counter Mode** | Fixed, Reset on Win, Decrease Only | Fixed | Respin counting |
| **Initial Respins** | 1-5 | 3 | Starting count |
| **Max Respins** | 1-10 | 5 | Limit |

**Dependencies:**
- **Enabled by:** Free Spins (optional context)
- **Conflicts:** Hold & Win (different respin paradigm)

**Generated Stages (5):**
```
RESPIN_TRIGGER      → Respin awarded
RESPIN_LOCK         → Symbols lock in place
RESPIN_SPIN         → Respin occurs
RESPIN_WIN          → Respin results in win
RESPIN_END          → Respin sequence complete
```

#### 3.2.3 HOLD & WIN Block

**Purpose:** Omogućava Hold & Win / Lightning Link mehaniku.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Variant** | Hold & Win, Hold & Respin, Cash on Reels | Hold & Win | Mechanic style |
| **Grid Mode** | Base Grid, Separate Grid | Base Grid | Visual treatment |
| **Trigger** | 6+ Coins, Scatter + Coins, Instant | 6+ Coins | Entry condition |
| **Initial Respins** | 3-5 | 3 | Starting respins |
| **End Condition** | No Respins Left, Full Grid, Max Rounds | No Respins Left | Exit condition |
| **Max Rounds** | 10-50 | 20 | If Max Rounds mode |
| **Jackpot Integration** | None, Mini/Minor/Major/Grand | All 4 tiers | Jackpot coins |
| **Coin Values** | Fixed, Random Range, Multiplier | Random Range | Coin payouts |

**Dependencies:**
- **Disables:** Normal spin flow during feature
- **Enables:** Collector (coin collection)
- **Requires:** Symbol Set (needs Coin/Money symbol)

**Generated Stages (12):**
```
HNW_TRIGGER         → Feature triggered
HNW_INTRO           → Transition to hold grid
HNW_SPIN            → Each respin
HNW_COIN_LAND       → New coin lands
HNW_COIN_UPGRADE    → Coin value increases
HNW_RESPIN_RESET    → Respins reset to initial
HNW_GRID_FILL       → Grid completely filled
HNW_JACKPOT_MINI    → Mini jackpot won
HNW_JACKPOT_MINOR   → Minor jackpot won
HNW_JACKPOT_MAJOR   → Major jackpot won
HNW_JACKPOT_GRAND   → Grand jackpot won
HNW_TOTAL_WIN       → Final payout
HNW_OUTRO           → Exit transition
```

**Rust Mapping:**
```rust
FeatureConfig {
    hold_spin: true,
    hold_spin_respins: 3,
    jackpot: true,
    jackpot_seeds: JackpotSeeds {
        mini: 10.0,
        minor: 25.0,
        major: 100.0,
        grand: 500.0,
    },
}
```

#### 3.2.4 CASCADES Block

**Purpose:** Omogućava tumbling/cascading reels.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Gravity Type** | Vertical, Diagonal, Custom | Vertical | How symbols fall |
| **Max Cascades** | 5, 10, Unlimited | Unlimited | Cascade limit |
| **Multiplier Mode** | None, Per Cascade, Progressive | Per Cascade | Win multiplier |
| **Multiplier Step** | +1x, +2x, ×2 | +1x | Per cascade increase |
| **Max Multiplier** | 5x, 10x, Unlimited | Unlimited | Multiplier cap |
| **Symbol Removal** | Explode, Fade, Collect | Explode | Visual style |

**Dependencies:**
- **Modifies:** Win Presentation (multiple win phases)
- **Modifies:** Game Core (if Cascades pay model selected, auto-enables)
- **Affects:** Audio pacing (rapid-fire win sounds)

**Generated Stages (8):**
```
CASCADE_START       → Cascade sequence begins
CASCADE_WIN_SHOW    → Winning symbols highlighted
CASCADE_EXPLODE     → Symbols removed
CASCADE_DROP        → New symbols fall
CASCADE_LAND        → Symbols land
CASCADE_STEP_N      → Cascade N occurs (pooled audio)
CASCADE_MULTIPLIER  → Multiplier increases
CASCADE_END         → No more cascades
```

**Timing Configuration:**
```dart
CascadeTiming {
  explosionDuration: 200ms,
  dropDuration: 300ms,
  evaluationDelay: 100ms,
  multiplierShowDuration: 500ms,
}
```

#### 3.2.5 COLLECTOR Block

**Purpose:** Omogućava meter/collection mehaniku.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Collection Type** | Per Spin, Per Feature, Persistent | Per Feature | When meter resets |
| **Collection Source** | Special Symbols, Any Win, Specific Wins | Special Symbols | What fills meter |
| **Meter Size** | 5, 10, 20, Custom | 10 | Collection target |
| **Reward Type** | Feature Trigger, Multiplier, Extra Spins, Prize | Feature Trigger | What full meter gives |
| **Partial Rewards** | None, Milestones | Milestones | Rewards before full |
| **Milestones** | [3, 6, 9] for 10-meter | [30%, 60%, 90%] | Milestone positions |

**Dependencies:**
- **Enabled by:** Hold & Win (coin collection)
- **Requires:** Symbol Set (needs collectible symbol)

**Generated Stages (6):**
```
COLLECT_SYMBOL      → Symbol added to meter
COLLECT_MILESTONE   → Milestone reached
COLLECT_FULL        → Meter completely filled
COLLECT_REWARD      → Reward granted
COLLECT_RESET       → Meter resets
COLLECT_PROGRESS    → Progress indicator update
```

---

### 3.3 PRESENTATION BLOCKS

#### 3.3.1 WIN PRESENTATION Block

**Purpose:** Kontroliše win prikaz i tier eskalaciju.

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Win Tiers** | See P5 Win Tier System | Standard preset | Tier thresholds |
| **Display Style** | Incremental, Burst, Hybrid | Incremental | Rollup animation |
| **Line Animation** | Sequential, Simultaneous, Priority | Sequential | Win line display |
| **Celebration Level** | Minimal, Standard, Epic | Standard | Particle intensity |
| **Skip Option** | None, After Delay, Immediate | After Delay | Player skip control |
| **Sound Ducking** | None, Music Only, All | Music Only | Audio priority |

**Win Tier Integration (from P5 system):**
```
Regular Wins:
├── WIN_LOW     (< 1x bet)
├── WIN_EQUAL   (= 1x bet)
├── WIN_1       (1x - 2x)
├── WIN_2       (2x - 5x)
├── WIN_3       (5x - 8x)
├── WIN_4       (8x - 12x)
├── WIN_5       (12x - 16x)
└── WIN_6       (16x - 20x)

Big Wins (≥ threshold):
├── BIG_WIN_TIER_1   (20x - 50x)
├── BIG_WIN_TIER_2   (50x - 100x)
├── BIG_WIN_TIER_3   (100x - 250x)
├── BIG_WIN_TIER_4   (250x - 500x)
└── BIG_WIN_TIER_5   (500x+)
```

**Generated Stages (20+):**
```
WIN_EVAL            → Win evaluation complete
WIN_PRESENT_*       → Per-tier presentation (WIN_PRESENT_3, etc.)
WIN_LINE_SHOW       → Individual line highlight
WIN_LINE_HIDE       → Line highlight ends
WIN_SYMBOL_HIGHLIGHT → Winning symbol glow
ROLLUP_START_*      → Rollup begins (per tier)
ROLLUP_TICK_*       → Rollup increment (pooled, per tier)
ROLLUP_END_*        → Rollup completes
BIG_WIN_INTRO       → Big win fanfare
BIG_WIN_PRESENT_*   → Big win tier (1-5)
BIG_WIN_LOOP        → Looping celebration
BIG_WIN_END         → Celebration ends
```

#### 3.3.2 MUSIC STATES Block

**Purpose:** Integriše sa ALE (Adaptive Layer Engine).

| Option | Values | Default | Impact |
|--------|--------|---------|--------|
| **Enable ALE** | Yes, No | Yes | Adaptive music |
| **Base Layers** | 1-5 intensity levels | 3 | L1-L5 base game |
| **Feature Layers** | Per-feature overrides | Auto | FS, HNW music |
| **Win Escalation** | None, Subtle, Dramatic | Subtle | Win tier → layer |
| **Transition Sync** | Immediate, Beat, Bar, Phrase | Bar | Music sync mode |
| **Fade Curve** | Linear, EaseIn, EaseOut, SCurve | EaseOut | Crossfade shape |

**Generated Contexts:**
```
BASE_GAME           → Default music context
FREE_SPINS          → FS music context
HOLD_AND_WIN        → HNW music context
BONUS               → Bonus game context
BIG_WIN             → Big win celebration context
```

**ALE Signal Mappings:**
```
winTier       → Layer intensity (higher tier = higher layer)
cascadeDepth  → Intensity boost during cascades
multiplier    → Subtle intensity increase
featureActive → Context switch trigger
```

---

## 4. DEPENDENCY SYSTEM

### 4.1 Dependency Types

| Type | Description | Example |
|------|-------------|---------|
| **ENABLES** | Block A enables options in Block B | Free Spins ENABLES Respin (in FS context) |
| **REQUIRES** | Block A needs Block B to function | Collector REQUIRES special symbol |
| **MODIFIES** | Block A changes Block B behavior | Cascades MODIFIES Win Presentation timing |
| **CONFLICTS** | Block A cannot coexist with Block B | Respin CONFLICTS Hold & Win |
| **DISABLES** | Block A disables normal flow | Hold & Win DISABLES normal spin |

### 4.2 Dependency Graph

```
                    ┌─────────────┐
                    │  GAME CORE  │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼─────┐ ┌────▼────┐ ┌─────▼─────┐
        │   GRID    │ │ SYMBOLS │ │  TIMING   │
        └─────┬─────┘ └────┬────┘ └───────────┘
              │            │
              │     ┌──────┴──────┐
              │     │             │
        ┌─────▼─────▼───┐   ┌─────▼─────┐
        │  FREE SPINS   │   │ CASCADES  │
        └───────┬───────┘   └─────┬─────┘
                │                 │
    ┌───────────┼─────────┐       │
    │           │         │       │
┌───▼───┐  ┌────▼────┐   ┌▼───────▼───┐
│RESPIN │  │COLLECTOR│   │WIN PRESENT │
└───────┘  └────┬────┘   └────────────┘
                │
          ┌─────▼─────┐
          │HOLD & WIN │
          └───────────┘

Legend:
─────►  Enables/Requires
- - -►  Modifies
═════►  Conflicts
```

### 4.3 Conflict Resolution

**Automatic Resolution:**
```dart
class DependencyResolver {
  List<Resolution> resolve(Set<String> enabledBlocks) {
    final resolutions = <Resolution>[];

    // Example: Respin + Hold & Win conflict
    if (enabledBlocks.contains('respin') &&
        enabledBlocks.contains('holdandwin')) {
      resolutions.add(Resolution(
        type: ResolutionType.autoDisable,
        block: 'respin',
        reason: 'Hold & Win uses its own respin mechanic',
        action: () => enabledBlocks.remove('respin'),
      ));
    }

    return resolutions;
  }
}
```

**Warning Display:**
```
⚠️ DEPENDENCY WARNING
────────────────────────────────────
Respin block has been disabled.

Reason: Hold & Win uses its own respin mechanic.
The standard Respin feature would conflict with
Hold & Win's built-in respin system.

[Keep Hold & Win]  [Keep Respin Instead]
```

### 4.4 Dependency Matrix

| Block | Enables | Requires | Modifies | Conflicts |
|-------|---------|----------|----------|-----------|
| **Game Core** | All | None | None | None |
| **Grid** | None | Game Core | None | None |
| **Symbol Set** | None | Game Core | None | None |
| **Free Spins** | Respin (in FS) | Scatter symbol | Win Presentation | None |
| **Respin** | None | None | Spin flow | Hold & Win |
| **Hold & Win** | Collector | Coin symbol | Disables spin | Respin |
| **Cascades** | None | None | Win Presentation, Timing | None |
| **Collector** | None | Special symbol | None | None |
| **Win Presentation** | None | None | None | None |
| **Music States** | None | None | All audio | None |

---

## 5. CONFIGURATION GENERATOR

### 5.1 Generation Pipeline

```
┌─────────────────┐
│ Enabled Blocks  │
│ + Block Options │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   VALIDATOR     │  ← Check dependencies, resolve conflicts
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   GENERATOR     │  ← Create configuration objects
└────────┬────────┘
         │
    ┌────┴────┬────────────┬────────────┐
    ▼         ▼            ▼            ▼
┌───────┐ ┌───────┐ ┌───────────┐ ┌─────────┐
│Mockup │ │State  │ │ Outcome   │ │  Rust   │
│Layout │ │Machine│ │ Controls  │ │ Config  │
└───────┘ └───────┘ └───────────┘ └─────────┘
    │         │            │            │
    └─────────┴────────────┴────────────┘
                    │
                    ▼
         ┌─────────────────┐
         │   APPLY TO      │
         │  SLOTLAB        │
         └─────────────────┘
```

### 5.2 Generated Outputs

#### 5.2.1 Mockup Layout
```dart
class GeneratedMockupLayout {
  final GridLayout grid;              // Reel/row configuration
  final List<SymbolSlot> symbolSlots; // Position definitions
  final List<Overlay> overlays;       // Feature overlays (FS counter, etc.)
  final List<UiElement> uiElements;   // Buttons, meters, displays
  final Map<String, Animation> animations; // Animation hooks
}
```

#### 5.2.2 State Machine
```dart
class GeneratedStateMachine {
  final String initialState;
  final Map<String, GameState> states;
  final List<StateTransition> transitions;
  final Map<String, List<String>> stateStages; // State → audio stages
}

class GameState {
  final String id;
  final StateType type;  // idle, spinning, evaluating, presenting, feature
  final Duration? timeout;
  final List<String> entryStages;
  final List<String> exitStages;
}
```

#### 5.2.3 Outcome Controls
```dart
class GeneratedOutcomeControls {
  final List<OutcomeControl> controls;

  // Only relevant controls for enabled features
  // Example: If Hold & Win disabled, no HNW force options
}

class OutcomeControl {
  final String id;
  final String label;
  final String? keyboardShortcut;
  final List<String> expectedStages;
  final IconData icon;
  final Color color;
  final OutcomeType type;
}
```

#### 5.2.4 Stage Definitions
```dart
class GeneratedStageDefinitions {
  final List<StageDefinition> stages;

  // Auto-registered with StageConfigurationService
  // Includes: priority, bus, pooled flag, looping flag
}
```

#### 5.2.5 Visual Transitions (NEW)

**Purpose:** Automatski generiše vizualne tranzicije na osnovu enabled feature-a.

```dart
class GeneratedVisualTransitions {
  final List<TransitionDefinition> transitions;
  final Map<String, AnimationConfig> featureAnimations;
  final Map<String, OverlayConfig> featureOverlays;
  final Map<String, ParticleConfig> particleSystems;
}

class TransitionDefinition {
  final String id;
  final String fromState;           // npr. "base_game"
  final String toState;             // npr. "free_spins"
  final TransitionType type;        // fade, slide, zoom, custom
  final Duration duration;
  final Curve curve;                // easeInOut, elasticOut, etc.
  final List<String> triggerStages; // Koji audio stages se trigeruju tokom tranzicije
  final List<AnimationStep> steps;  // Sekvenca vizualnih koraka
}

class AnimationStep {
  final String element;             // "reels", "overlay", "background", "meter"
  final AnimationAction action;     // fadeIn, fadeOut, slideUp, scale, glow
  final Duration delay;             // Offset od početka tranzicije
  final Duration duration;
  final Map<String, dynamic> params; // Per-action parameters
}
```

**Feature → Transition Mapping:**

| Feature | Entry Transition | Exit Transition | In-Feature Animations |
|---------|------------------|-----------------|----------------------|
| **Free Spins** | FS intro screen, reel flash | FS outro, win summary | Spin counter decrement |
| **Hold & Win** | Lock animation, grid highlight | Unlock, prize collect | Symbol lock glow, meter fill |
| **Cascades** | Winning symbols explode | Cascade end settle | Fall animation, multiplier popup |
| **Collector** | Meter appears | Meter reward animation | Symbol fly-to-meter |
| **Big Win** | Screen shake, coin burst | Celebration fade | Tier escalation, rollup counter |
| **Bonus** | Scene transition | Return to base | Mini-game specific |
| **Gamble** | Card/coin appear | Result flash | Double-or-nothing animation |

**Generated Animation Configs:**
```dart
// Example: Free Spins enabled
final fsTransitions = {
  'fs_enter': TransitionDefinition(
    fromState: 'base_game',
    toState: 'free_spins',
    duration: Duration(milliseconds: 1500),
    steps: [
      AnimationStep(
        element: 'background',
        action: AnimationAction.crossfade,
        delay: Duration.zero,
        duration: Duration(milliseconds: 800),
        params: {'toBackground': 'fs_background'},
      ),
      AnimationStep(
        element: 'fs_intro_overlay',
        action: AnimationAction.fadeIn,
        delay: Duration(milliseconds: 400),
        duration: Duration(milliseconds: 600),
      ),
      AnimationStep(
        element: 'fs_counter',
        action: AnimationAction.scaleIn,
        delay: Duration(milliseconds: 1000),
        duration: Duration(milliseconds: 400),
        params: {'from': 0.0, 'to': 1.0, 'curve': 'elasticOut'},
      ),
    ],
    triggerStages: ['FS_TRIGGER', 'FS_INTRO', 'FS_COUNT_SHOW'],
  ),
  'fs_exit': TransitionDefinition(
    fromState: 'free_spins',
    toState: 'base_game',
    duration: Duration(milliseconds: 2000),
    steps: [
      AnimationStep(
        element: 'fs_summary_overlay',
        action: AnimationAction.fadeIn,
        delay: Duration.zero,
        duration: Duration(milliseconds: 500),
      ),
      AnimationStep(
        element: 'fs_total_win',
        action: AnimationAction.countUp,
        delay: Duration(milliseconds: 500),
        duration: Duration(milliseconds: 1000),
      ),
      AnimationStep(
        element: 'background',
        action: AnimationAction.crossfade,
        delay: Duration(milliseconds: 1500),
        duration: Duration(milliseconds: 500),
        params: {'toBackground': 'base_background'},
      ),
    ],
    triggerStages: ['FS_END', 'FS_SUMMARY', 'FS_TOTAL_WIN', 'FS_RETURN'],
  ),
};
```

**Cascade Animations:**
```dart
final cascadeAnimations = {
  'cascade_explode': AnimationConfig(
    element: 'winning_symbols',
    type: AnimationType.particleBurst,
    duration: Duration(milliseconds: 200),
    params: {
      'particleCount': 15,
      'colors': ['#FFD700', '#FFA500', '#FF6347'],
      'spread': 1.5,
      'gravity': 2.0,
    },
    triggerStage: 'CASCADE_EXPLODE',
  ),
  'cascade_drop': AnimationConfig(
    element: 'new_symbols',
    type: AnimationType.fall,
    duration: Duration(milliseconds: 300),
    params: {
      'easing': 'bounceOut',
      'staggerDelay': 50,  // Per-reel stagger
    },
    triggerStage: 'CASCADE_DROP',
  ),
  'cascade_multiplier': AnimationConfig(
    element: 'multiplier_badge',
    type: AnimationType.popup,
    duration: Duration(milliseconds: 500),
    params: {
      'scale': 1.3,
      'glow': true,
      'pulseCount': 2,
    },
    triggerStage: 'CASCADE_MULTIPLIER',
  ),
};
```

**Integration with Mockup:**

Kada ručno napraviš mockup i zatim koristiš Feature Builder:
1. Feature Builder generiše `TransitionDefinition` za svaki enabled feature
2. Mockup prima `featureAnimations` i registruje animacije
3. Stage eventi trigeruju vizualne i audio tranzicije SINHRONIZOVANO

```dart
// slot_preview_widget.dart integration
void _onStageTriggered(String stage) {
  // Audio
  eventRegistry.triggerStage(stage);

  // Visual (from Feature Builder)
  final animation = _featureAnimations[stage];
  if (animation != null) {
    _animationController.play(animation);
  }
}
```

#### 5.2.6 Rust Engine Config
```dart
class GeneratedRustConfig {
  final Map<String, dynamic> slotConfig;  // → slot_lab_apply_config(json)
  final Map<String, dynamic> featureConfig;
  final Map<String, dynamic> gridConfig;
  final Map<String, dynamic> symbolConfig;
  final Map<String, dynamic> transitionConfig; // NEW: Visual transitions

  String toJson() => jsonEncode({
    'grid': gridConfig,
    'symbols': symbolConfig,
    'features': featureConfig,
    'transitions': transitionConfig,  // NEW
    'config': slotConfig,
  });
}
```

### 5.3 FFI Integration

**New FFI Function (Rust side):**
```rust
// crates/rf-bridge/src/slot_lab_ffi.rs

#[no_mangle]
pub extern "C" fn slot_lab_apply_feature_config(
    json_ptr: *const c_char,
) -> i32 {
    let json_str = unsafe { CStr::from_ptr(json_ptr).to_str().unwrap() };

    match serde_json::from_str::<FeatureBuilderConfig>(json_str) {
        Ok(config) => {
            // Apply to engine
            let mut engine = SLOT_ENGINE.lock().unwrap();
            engine.apply_config(config);
            0  // Success
        }
        Err(e) => {
            eprintln!("Config parse error: {}", e);
            -1  // Error
        }
    }
}

#[no_mangle]
pub extern "C" fn slot_lab_get_current_config() -> *const c_char {
    let engine = SLOT_ENGINE.lock().unwrap();
    let config = engine.export_config();
    let json = serde_json::to_string(&config).unwrap();
    CString::new(json).unwrap().into_raw()
}
```

**Dart FFI Binding:**
```dart
// flutter_ui/lib/src/rust/native_ffi.dart

extension FeatureBuilderFFI on NativeFFI {
  int slotLabApplyFeatureConfig(String configJson) {
    final jsonPtr = configJson.toNativeUtf8();
    try {
      return _bindings.slot_lab_apply_feature_config(jsonPtr.cast());
    } finally {
      malloc.free(jsonPtr);
    }
  }

  String slotLabGetCurrentConfig() {
    final ptr = _bindings.slot_lab_get_current_config();
    final json = ptr.cast<Utf8>().toDartString();
    _bindings.free_string(ptr);
    return json;
  }
}
```

---

## 5.4 MOCKUP + TRANSITIONS INTEGRATION

### 5.4.1 Workflow: Ručni Mockup → Feature Builder

Kada dizajner ručno kreira mockup u SlotLab-u, Feature Builder automatski generiše tranzicije:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 1: RUČNI MOCKUP DESIGN                                                │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Dizajner definiše:                                                          │
│  • Grid layout (5x3, 6x4, megaways...)                                       │
│  • Simbole (Wild, Scatter, High Pay, Low Pay...)                            │
│  • Pozicije elemenata (buttons, meters, counters)                           │
│  • Custom overlays (FS banner, HNW grid, bonus screen)                      │
│                                                                              │
│  Rezultat: MockupLayout sa svim vizualnim elementima                        │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 2: FEATURE BUILDER CONFIGURATION                                      │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Dizajner čekira feature blokove:                                            │
│  ☑ Free Spins (10 spins, retrigger ON)                                      │
│  ☑ Cascades (unlimited, multiplier escalation)                              │
│  ☑ Collector (meter to 10, triggers FS)                                     │
│  ☐ Hold & Win                                                                │
│                                                                              │
│  Rezultat: FeatureBuilderConfig sa enabled blokovima                        │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 3: AUTO-GENERATION (Feature Builder Magic)                            │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Feature Builder generiše:                                                   │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │ STATE MACHINE   │  │ TRANSITIONS     │  │ AUDIO HOOKS     │              │
│  │                 │  │                 │  │                 │              │
│  │ base_game       │  │ fs_enter        │  │ FS_TRIGGER      │              │
│  │   ↓             │  │ fs_exit         │  │ FS_INTRO        │              │
│  │ free_spins      │  │ cascade_explode │  │ FS_SPIN         │              │
│  │   ↓             │  │ cascade_drop    │  │ CASCADE_EXPLODE │              │
│  │ cascade         │  │ collect_fly     │  │ CASCADE_DROP    │              │
│  │   ↓             │  │ meter_fill      │  │ COLLECT_SYMBOL  │              │
│  │ (loop)          │  │ ...             │  │ ...             │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│                                                                              │
│  Rezultat: Kompletna konfiguracija sa sinhronizovanim tranzicijama          │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 4: APPLY TO MOCKUP                                                    │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Mockup prima generisane tranzicije i povezuje ih sa elementima:            │
│                                                                              │
│  Element: "fs_counter"     ←→  Animation: scaleIn on FS_COUNT_SHOW          │
│  Element: "winning_symbols"←→  Animation: explode on CASCADE_EXPLODE        │
│  Element: "collect_meter"  ←→  Animation: fillUp on COLLECT_SYMBOL          │
│  Element: "multiplier_badge"←→ Animation: popup on CASCADE_MULTIPLIER       │
│                                                                              │
│  Rezultat: Mockup sa živim, sinhronizovanim tranzicijama                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.4.2 Element Mapping

Feature Builder prepoznaje standardne mockup elemente i mapira ih na tranzicije:

| Mockup Element | Feature | Animation | Trigger Stage |
|----------------|---------|-----------|---------------|
| `fs_counter` | Free Spins | scaleIn, decrement | FS_COUNT_SHOW, FS_SPIN |
| `fs_intro_overlay` | Free Spins | fadeIn/fadeOut | FS_INTRO, FS_START |
| `fs_summary_overlay` | Free Spins | slideIn, countUp | FS_END, FS_SUMMARY |
| `winning_symbols` | Cascades | glow, explode | CASCADE_WIN_SHOW, CASCADE_EXPLODE |
| `new_symbols` | Cascades | fall, bounce | CASCADE_DROP, CASCADE_LAND |
| `multiplier_badge` | Cascades | popup, pulse | CASCADE_MULTIPLIER |
| `collect_meter` | Collector | fillUp, glow | COLLECT_SYMBOL, COLLECT_MILESTONE |
| `collect_reward` | Collector | burst, expand | COLLECT_FULL, COLLECT_REWARD |
| `hnw_grid` | Hold & Win | lockGlow, expand | HOLD_SYMBOL_LOCK, HOLD_BOARD_EXPAND |
| `hnw_respins` | Hold & Win | decrement, pulse | HOLD_RESPIN, HOLD_RESET |
| `jackpot_display` | Win Tiers | shake, flash | JACKPOT_TRIGGER, JACKPOT_AWARD |
| `big_win_plaque` | Win Tiers | scaleIn, glow | BIG_WIN_INTRO, BIG_WIN_TIER_* |
| `coin_particles` | Win Tiers | burst, gravity | BIG_WIN_COINS, WIN_CELEBRATE |
| `background` | All | crossfade | *_ENTER, *_EXIT |
| `reels` | All | spin, stop, bounce | SPIN_START, REEL_STOP_* |

### 5.4.3 Custom Element Registration

Za custom mockup elemente, dizajner može ručno mapirati animacije:

```dart
// U mockup editoru
mockupEditor.registerCustomElement(
  elementId: 'my_bonus_wheel',
  animations: {
    'BONUS_WHEEL_SPIN': AnimationConfig(
      type: AnimationType.rotate,
      duration: Duration(seconds: 3),
      params: {'rotations': 5, 'easing': 'easeOutQuart'},
    ),
    'BONUS_WHEEL_STOP': AnimationConfig(
      type: AnimationType.bounce,
      duration: Duration(milliseconds: 500),
    ),
    'BONUS_WHEEL_RESULT': AnimationConfig(
      type: AnimationType.glow,
      duration: Duration(milliseconds: 800),
      params: {'color': '#FFD700', 'intensity': 1.5},
    ),
  },
);
```

### 5.4.4 Sync Guarantee

**Kritično:** Visual i Audio tranzicije su UVEK sinhronizovane:

```dart
class TransitionOrchestrator {
  void executeTransition(String transitionId) {
    final transition = _transitions[transitionId];
    if (transition == null) return;

    // 1. Start all animations
    for (final step in transition.steps) {
      _scheduleAnimation(step);
    }

    // 2. Trigger all audio stages
    for (final stage in transition.triggerStages) {
      eventRegistry.triggerStage(stage);
    }

    // 3. Update state machine
    stateMachine.transitionTo(transition.toState);
  }

  void _scheduleAnimation(AnimationStep step) {
    Future.delayed(step.delay, () {
      final element = mockup.findElement(step.element);
      element?.animate(step.action, step.duration, step.params);
    });
  }
}
```

### 5.4.5 Timing Fine-Tuning

Svaka tranzicija ima timing kontrole u Feature Builder:

```
┌─────────────────────────────────────────────────────────────────┐
│  FREE SPINS TRANSITION TIMING                           [⚙]    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Entry Transition                                                │
│  ────────────────────────────────────────────────────────────   │
│  Total Duration:   [1500] ms                                     │
│                                                                  │
│  Background Fade:  ├──────────[800ms]──────────┤                │
│  Intro Overlay:         ├────[600ms]────┤                       │
│  Counter Appear:                    ├───[400ms]───┤             │
│  Audio: FS_TRIGGER    ▲                                          │
│         FS_INTRO           ▲                                     │
│         FS_COUNT_SHOW                          ▲                │
│                                                                  │
│  [Preview] [Reset to Default]                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. PRESET SYSTEM

### 6.1 Preset Model

```dart
class FeaturePreset {
  final String id;
  final String name;
  final String description;
  final String category;  // classic, video, megaways, holdwin, cluster
  final String thumbnailAsset;
  final Set<String> enabledBlocks;
  final Map<String, Map<String, dynamic>> blockOptions;
  final DateTime? createdAt;
  final bool isBuiltIn;
  final String? author;
  final String schemaVersion;

  // Serialization
  Map<String, dynamic> toJson();
  factory FeaturePreset.fromJson(Map<String, dynamic> json);
}
```

### 6.2 Built-in Presets (12)

| # | Preset Name | Category | Blocks | Description |
|---|-------------|----------|--------|-------------|
| 1 | Classic 3x3 Fruit | classic | Core + WinPres | Minimal 3-reel fruit |
| 2 | Classic 5x3 Lines | classic | Core + FS + WinPres | Traditional 5x3 with FS |
| 3 | Ways 243 | video | Core + FS + Cascades + WinPres | 243 ways with cascades |
| 4 | Ways 1024 | video | Core + FS + WinPres + Music | 1024 ways modern |
| 5 | Megaways | megaways | Core (dynamic) + FS + Cascades + WinPres | 117649 ways |
| 6 | Cluster Pays | cluster | Core (cluster) + Cascades + Collector + WinPres | Cluster mechanics |
| 7 | Hold & Win Basic | holdwin | Core + HNW + WinPres | Simple hold & win |
| 8 | Hold & Win + FS | holdwin | Core + FS + HNW + WinPres | Combined features |
| 9 | Cascades + Multiplier | video | Core + Cascades + WinPres + Music | Cascade focus |
| 10 | Collector + FS | video | Core + FS + Collector + WinPres | Meter-based FS trigger |
| 11 | Full Feature | video | ALL BLOCKS | Everything enabled |
| 12 | Audio Test Mode | test | Core + WinPres | High frequency events |

### 6.3 Preset File Format

```json
{
  "schemaVersion": "1.0.0",
  "id": "classic-5x3-fs",
  "name": "Classic 5x3 with Free Spins",
  "description": "Traditional 5-reel, 3-row slot with 20 paylines and free spins feature",
  "category": "classic",
  "author": "FluxForge",
  "createdAt": "2026-02-01T00:00:00Z",
  "isBuiltIn": true,
  "enabledBlocks": [
    "gameCore",
    "grid",
    "symbolSet",
    "freeSpins",
    "winPresentation"
  ],
  "blockOptions": {
    "gameCore": {
      "payModel": "lines",
      "spinType": "normal",
      "presentationStyle": "classic",
      "volatility": "medium"
    },
    "grid": {
      "reels": 5,
      "rows": 3,
      "paylines": 20
    },
    "symbolSet": {
      "lowPayCount": 4,
      "midPayCount": 2,
      "highPayCount": 2,
      "wild": "standard",
      "scatter": "standard"
    },
    "freeSpins": {
      "triggerType": "scatterCount",
      "scatterCount": 3,
      "spinCountMode": "fixed",
      "fixedSpins": 10,
      "retrigger": true,
      "maxRetriggers": 3
    },
    "winPresentation": {
      "displayStyle": "incremental",
      "lineAnimation": "sequential",
      "celebrationLevel": "standard"
    }
  }
}
```

### 6.4 Preset Storage

```
~/.fluxforge/presets/
├── built-in/                    # Read-only, bundled with app
│   ├── classic-3x3-fruit.json
│   ├── classic-5x3-lines.json
│   └── ...
├── user/                        # User-created presets
│   ├── my-custom-slot.json
│   └── ...
└── shared/                      # Imported from others
    └── ...
```

---

## 7. USER EXPERIENCE FLOWS

### 7.1 First-Time User Flow

```
1. User opens SlotLab
   ↓
2. Feature Builder panel appears (first-time prompt)
   "Would you like to configure your slot features?"
   [Start with Preset] [Start from Scratch] [Skip]
   ↓
3a. If "Start with Preset":
    → Preset gallery opens
    → User selects preset
    → Configuration loaded
    → [Apply] to confirm
   ↓
3b. If "Start from Scratch":
    → Empty configuration
    → Core blocks enabled by default
    → User checks desired features
   ↓
4. User clicks [Apply Configuration]
   ↓
5. Confirmation dialog:
   "This will regenerate your slot configuration.
    Existing audio assignments will be preserved."
   [Cancel] [Apply]
   ↓
6. SlotLab regenerates:
   - Mockup layout
   - State flow
   - Outcome controls
   - Stage definitions
   ↓
7. User can now:
   - Test with spin button
   - Force outcomes
   - Assign audio in Ultimate Audio Panel
```

### 7.2 Modify Existing Configuration Flow

```
1. User opens Feature Builder (already configured slot)
   ↓
2. Current configuration loaded
   - Blocks show current state
   - Options show current values
   ↓
3. User enables new block (e.g., Cascades)
   ↓
4. Dependency check:
   - ⚠️ "Cascades will modify Win Presentation timing"
   - [OK, I understand]
   ↓
5. User clicks [Apply Configuration]
   ↓
6. Confirmation dialog:
   "Changes detected:
    + Cascades block enabled
    ~ Win Presentation timing modified

    Audio assignments will be preserved.
    New stages will need audio assignment."
   [Cancel] [Apply]
   ↓
7. SlotLab regenerates with cascades
   ↓
8. User sees new stages in Ultimate Audio Panel:
   - CASCADE_START (unassigned)
   - CASCADE_STEP (unassigned)
   - etc.
```

### 7.3 Save/Load Preset Flow

```
SAVE:
1. User configures features
2. Click [Save Preset]
3. Dialog:
   Name: [My Custom Slot]
   Description: [5x4 cascades with progressive multiplier]
   Category: [video ▼]
   [Cancel] [Save]
4. Preset saved to ~/.fluxforge/presets/user/

LOAD:
1. Click [Load Preset ▼]
2. Dropdown shows:
   ── Built-in ──
   ○ Classic 5x3 Lines
   ○ Ways 243
   ○ Hold & Win Basic
   ── User Presets ──
   ○ My Custom Slot
   ── Import ──
   ○ Import from file...
3. Select preset
4. Configuration loaded
5. [Apply] to confirm
```

---

## 8. OUTCOME CONTROLLER INTEGRATION

### 8.1 Dynamic Control Generation

Outcome controls are generated based on enabled blocks:

```dart
List<OutcomeControl> generateOutcomeControls(Set<String> enabledBlocks) {
  final controls = <OutcomeControl>[];

  // Always present
  controls.add(OutcomeControl.forceLoss());
  controls.add(OutcomeControl.forceWinTier(tier: 1));
  controls.add(OutcomeControl.forceWinTier(tier: 2));
  controls.add(OutcomeControl.forceWinTier(tier: 3));
  // ... up to tier 6

  // Conditional based on blocks
  if (enabledBlocks.contains('freeSpins')) {
    controls.add(OutcomeControl.forceFsTrigger());
    controls.add(OutcomeControl.forceFsRetrigger());
  }

  if (enabledBlocks.contains('holdAndWin')) {
    controls.add(OutcomeControl.forceHnwTrigger());
    controls.add(OutcomeControl.forceFullGrid());
    controls.add(OutcomeControl.forceJackpot(tier: 'mini'));
    controls.add(OutcomeControl.forceJackpot(tier: 'minor'));
    controls.add(OutcomeControl.forceJackpot(tier: 'major'));
    controls.add(OutcomeControl.forceJackpot(tier: 'grand'));
  }

  if (enabledBlocks.contains('cascades')) {
    controls.add(OutcomeControl.forceCascade(count: 3));
    controls.add(OutcomeControl.forceCascade(count: 5));
    controls.add(OutcomeControl.forceNoCascade());
  }

  if (enabledBlocks.contains('collector')) {
    controls.add(OutcomeControl.forceCollectionComplete());
    controls.add(OutcomeControl.forceMilestone(index: 1));
  }

  return controls;
}
```

### 8.2 Updated Forced Outcome Panel

```
┌─────────────────────────────────────────────────────────────┐
│  FORCED OUTCOMES                            [Auto-generated] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  BASE OUTCOMES                                              │
│  [1] Force Loss        [2] Win Tier 1    [3] Win Tier 2     │
│  [4] Win Tier 3        [5] Win Tier 4    [6] Win Tier 5     │
│                                                             │
│  BIG WINS                                                   │
│  [7] Big Win T1        [8] Big Win T2    [9] Big Win T3     │
│                                                             │
│  ─────────────── FREE SPINS ───────────────                 │
│  [F] Trigger FS        [R] Retrigger FS                     │
│                                                             │
│  ─────────────── CASCADES ──────────────────                │
│  [C] 3x Cascade        [V] 5x Cascade    [X] No Cascade     │
│                                                             │
│  (Hold & Win controls hidden - block not enabled)           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. AUDIO INTEGRATION

### 9.1 Stage-to-Audio Mapping

Feature Builder generates stage definitions that integrate with Ultimate Audio Panel:

```dart
class FeatureStageMapping {
  final String featureId;
  final String stageName;
  final String category;        // Maps to UltimateAudioPanel section
  final int defaultPriority;
  final SpatialBus defaultBus;
  final bool isPooled;
  final bool isLooping;
  final String? description;
}

// Example mappings for Free Spins
final freeSpinsStages = [
  FeatureStageMapping(
    featureId: 'freeSpins',
    stageName: 'FS_TRIGGER',
    category: 'Free Spins',         // Section 6 in UltimateAudioPanel
    defaultPriority: 85,
    defaultBus: SpatialBus.sfx,
    isPooled: false,
    isLooping: false,
    description: 'Scatter lands, triggers free spins',
  ),
  FeatureStageMapping(
    featureId: 'freeSpins',
    stageName: 'FS_SPIN_LOOP',
    category: 'Free Spins',
    defaultPriority: 50,
    defaultBus: SpatialBus.music,
    isPooled: false,
    isLooping: true,
    description: 'Looping reel spin during free spins',
  ),
  // ... more stages
];
```

### 9.2 Ultimate Audio Panel Integration

When Feature Builder applies configuration:

1. **New stages added** → Appear in appropriate section with "unassigned" status
2. **Existing stages preserved** → Audio assignments kept
3. **Removed stages** → Moved to "Unused" section (not deleted)

```
ULTIMATE AUDIO PANEL - SECTION 6: FREE SPINS
┌─────────────────────────────────────────────────────────────┐
│ ▼ Free Spins (8 slots)                          [Collapse]  │
├─────────────────────────────────────────────────────────────┤
│ FS_TRIGGER        │ 🔊 fs_trigger.wav           │ [▶][×]   │
│ FS_INTRO          │ ⚠️ Unassigned               │ [+]      │
│ FS_SPIN_START     │ 🔊 fs_spin_start.wav        │ [▶][×]   │
│ FS_SPIN_LOOP      │ 🔊 fs_spin_loop.wav    🔁   │ [▶][×]   │
│ FS_SPIN_END       │ ⚠️ Unassigned               │ [+]      │
│ FS_RETRIGGER      │ 🔊 fs_retrigger.wav         │ [▶][×]   │
│ FS_TOTAL_WIN      │ ⚠️ Unassigned               │ [+]      │
│ FS_OUTRO          │ 🔊 fs_outro.wav             │ [▶][×]   │
└─────────────────────────────────────────────────────────────┘
```

### 9.3 Audio Preset Templates

Feature Builder can include audio assignment templates:

```dart
class AudioPresetTemplate {
  final String featureId;
  final Map<String, AudioAssignment> assignments;
}

class AudioAssignment {
  final String stageName;
  final String? suggestedFileName;  // e.g., "fs_trigger.wav"
  final double defaultVolume;
  final double defaultPan;
  final String? busOverride;
}

// Example: Free Spins audio template
final freeSpinsAudioTemplate = AudioPresetTemplate(
  featureId: 'freeSpins',
  assignments: {
    'FS_TRIGGER': AudioAssignment(
      stageName: 'FS_TRIGGER',
      suggestedFileName: 'fs_trigger.wav',
      defaultVolume: 1.0,
      defaultPan: 0.0,
    ),
    'FS_SPIN_LOOP': AudioAssignment(
      stageName: 'FS_SPIN_LOOP',
      suggestedFileName: 'fs_spin_loop.wav',
      defaultVolume: 0.8,
      defaultPan: 0.0,
      busOverride: 'music',
    ),
    // ... more assignments
  },
);
```

---

## 10. VALIDATION SYSTEM

### 10.1 Validation Rules

```dart
abstract class ValidationRule {
  final String id;
  final ValidationSeverity severity;  // error, warning, info

  ValidationResult validate(FeatureConfiguration config);
}

// Example rules
class ScatterRequiredForFreeSpins extends ValidationRule {
  @override
  ValidationResult validate(FeatureConfiguration config) {
    if (config.hasBlock('freeSpins') &&
        config.getOption('freeSpins', 'triggerType') == 'scatterCount') {
      if (!config.getOption('symbolSet', 'scatter')) {
        return ValidationResult.error(
          'Free Spins with Scatter trigger requires Scatter symbol',
          fix: 'Enable Scatter in Symbol Set block',
        );
      }
    }
    return ValidationResult.ok();
  }
}

class CascadeTimingWarning extends ValidationRule {
  @override
  ValidationResult validate(FeatureConfiguration config) {
    if (config.hasBlock('cascades') && config.hasBlock('freeSpins')) {
      return ValidationResult.warning(
        'Cascades during Free Spins may create long spin sequences',
        info: 'Consider limiting max cascades to 10 during FS',
      );
    }
    return ValidationResult.ok();
  }
}
```

### 10.2 Validation Display

```
┌─────────────────────────────────────────────────────────────┐
│  VALIDATION                                                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ❌ ERROR (1)                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Free Spins with Scatter trigger requires Scatter    │   │
│  │ symbol in Symbol Set.                               │   │
│  │                                                     │   │
│  │ [Fix: Enable Scatter in Symbol Set]                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⚠️ WARNING (2)                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Cascades during Free Spins may create long spin     │   │
│  │ sequences. Consider limiting max cascades.          │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Hold & Win disables normal spin flow. Ensure        │   │
│  │ audio covers HNW-specific stages.                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ℹ️ INFO (1)                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 12 new stages will be registered. Audio assignment  │   │
│  │ required for full coverage.                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  [Apply Anyway]  [Fix Errors First]                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. IMPLEMENTATION ARCHITECTURE

### 11.1 File Structure

```
flutter_ui/lib/
├── models/feature_builder/
│   ├── feature_block.dart              # Base block model
│   ├── block_category.dart             # Categories enum
│   ├── block_dependency.dart           # Dependency types
│   ├── block_options.dart              # Per-block options
│   ├── feature_preset.dart             # Preset model
│   ├── generated_config.dart           # Output models
│   └── validation_rule.dart            # Validation system
│
├── services/feature_builder/
│   ├── feature_block_registry.dart     # Block registry
│   ├── dependency_resolver.dart        # Dependency logic
│   ├── configuration_generator.dart    # Config generation
│   ├── preset_service.dart             # Preset CRUD
│   ├── validation_service.dart         # Rule execution
│   └── rust_config_bridge.dart         # FFI integration
│
├── widgets/feature_builder/
│   ├── feature_builder_panel.dart      # Main panel
│   ├── block_list_widget.dart          # Checkbox list
│   ├── block_settings_sheet.dart       # Options slide-out
│   ├── dependency_badge.dart           # Warning indicators
│   ├── preset_dropdown.dart            # Preset selector
│   ├── validation_panel.dart           # Error display
│   └── apply_confirmation_dialog.dart  # Confirmation
│
├── blocks/                             # Individual block implementations
│   ├── game_core_block.dart
│   ├── grid_block.dart
│   ├── symbol_set_block.dart
│   ├── free_spins_block.dart
│   ├── respin_block.dart
│   ├── hold_and_win_block.dart
│   ├── cascades_block.dart
│   ├── collector_block.dart
│   ├── win_presentation_block.dart
│   └── music_states_block.dart
│
└── providers/
    └── feature_builder_provider.dart   # State management

crates/
├── rf-slot-lab/src/
│   └── feature_builder_config.rs       # Rust config parsing
│
└── rf-bridge/src/
    └── feature_builder_ffi.rs          # FFI functions
```

### 11.2 Class Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    FeatureBuilderProvider                        │
│  ─────────────────────────────────────────────────────────────  │
│  - _enabledBlocks: Set<String>                                  │
│  - _blockOptions: Map<String, Map<String, dynamic>>             │
│  - _validationResults: List<ValidationResult>                   │
│  - _generatedConfig: GeneratedConfiguration?                    │
│  ─────────────────────────────────────────────────────────────  │
│  + enableBlock(String blockId)                                  │
│  + disableBlock(String blockId)                                 │
│  + setBlockOption(String blockId, String key, dynamic value)    │
│  + validate(): List<ValidationResult>                           │
│  + applyConfiguration(): Future<void>                           │
│  + loadPreset(FeaturePreset preset)                             │
│  + savePreset(String name): FeaturePreset                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ uses
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   FeatureBlockRegistry                           │
│  ─────────────────────────────────────────────────────────────  │
│  - _blocks: Map<String, FeatureBlock>                           │
│  ─────────────────────────────────────────────────────────────  │
│  + register(FeatureBlock block)                                 │
│  + getBlock(String id): FeatureBlock?                           │
│  + getAllBlocks(): List<FeatureBlock>                           │
│  + getBlocksByCategory(BlockCategory): List<FeatureBlock>       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ contains
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FeatureBlock (abstract)                     │
│  ─────────────────────────────────────────────────────────────  │
│  + id: String                                                   │
│  + name: String                                                 │
│  + category: BlockCategory                                      │
│  + dependencies: List<BlockDependency>                          │
│  + optionDefinitions: List<BlockOption>                         │
│  ─────────────────────────────────────────────────────────────  │
│  + getDefaultOptions(): Map<String, dynamic>                    │
│  + validateOptions(Map<String, dynamic>): ValidationResult      │
│  + generateStages(): List<StageDefinition>                      │
│  + generateRustConfig(): Map<String, dynamic>                   │
└─────────────────────────────────────────────────────────────────┘
         △                    △                    △
         │                    │                    │
    ┌────┴────┐          ┌────┴────┐          ┌────┴────┐
    │GameCore │          │FreeSpins│          │Cascades │
    │  Block  │          │  Block  │          │  Block  │
    └─────────┘          └─────────┘          └─────────┘
```

### 11.3 Service Registration (GetIt)

```dart
// service_locator.dart

void setupFeatureBuilder() {
  // Layer 10: Feature Builder (after SlotLab providers)

  sl.registerLazySingleton<FeatureBlockRegistry>(
    () => FeatureBlockRegistry()..registerBuiltInBlocks(),
  );

  sl.registerLazySingleton<DependencyResolver>(
    () => DependencyResolver(sl<FeatureBlockRegistry>()),
  );

  sl.registerLazySingleton<ConfigurationGenerator>(
    () => ConfigurationGenerator(
      sl<FeatureBlockRegistry>(),
      sl<StageConfigurationService>(),
    ),
  );

  sl.registerLazySingleton<PresetService>(
    () => PresetService(),
  );

  sl.registerLazySingleton<ValidationService>(
    () => ValidationService()..registerBuiltInRules(),
  );

  sl.registerFactory<FeatureBuilderProvider>(
    () => FeatureBuilderProvider(
      sl<FeatureBlockRegistry>(),
      sl<DependencyResolver>(),
      sl<ConfigurationGenerator>(),
      sl<PresetService>(),
      sl<ValidationService>(),
    ),
  );
}
```

---

## 12. IMPLEMENTATION PHASES

### Phase 1: Foundation (3 days, ~1,500 LOC)

**Deliverables:**
- [ ] FeatureBlock base model + 3 Core blocks
- [ ] BlockCategory, BlockDependency, BlockOption models
- [ ] FeatureBlockRegistry with registration
- [ ] FeaturePreset model with JSON serialization
- [ ] Basic FeatureBuilderProvider

**Files:**
- `models/feature_builder/*.dart` (~800 LOC)
- `blocks/game_core_block.dart` (~150 LOC)
- `blocks/grid_block.dart` (~150 LOC)
- `blocks/symbol_set_block.dart` (~200 LOC)
- `services/feature_builder/feature_block_registry.dart` (~200 LOC)

### Phase 2: Feature Blocks (4 days, ~2,000 LOC)

**Deliverables:**
- [ ] FreeSpinsBlock with all options
- [ ] RespinBlock with all options
- [ ] HoldAndWinBlock with all options
- [ ] CascadesBlock with all options
- [ ] CollectorBlock with all options
- [ ] WinPresentationBlock with P5 integration
- [ ] MusicStatesBlock with ALE integration

**Files:**
- `blocks/free_spins_block.dart` (~300 LOC)
- `blocks/respin_block.dart` (~200 LOC)
- `blocks/hold_and_win_block.dart` (~350 LOC)
- `blocks/cascades_block.dart` (~250 LOC)
- `blocks/collector_block.dart` (~200 LOC)
- `blocks/win_presentation_block.dart` (~400 LOC)
- `blocks/music_states_block.dart` (~300 LOC)

### Phase 3: Dependency System (2 days, ~800 LOC)

**Deliverables:**
- [ ] DependencyResolver with all rules
- [ ] Conflict detection and auto-resolution
- [ ] Dependency graph visualization data
- [ ] Warning generation

**Files:**
- `services/feature_builder/dependency_resolver.dart` (~500 LOC)
- `models/feature_builder/block_dependency.dart` (~300 LOC)

### Phase 4: Configuration Generator (3 days, ~1,500 LOC)

**Deliverables:**
- [ ] GeneratedConfiguration models
- [ ] Mockup layout generation
- [ ] State machine generation
- [ ] Outcome controls generation
- [ ] Stage definitions generation
- [ ] Integration with SlotLabProjectProvider

**Files:**
- `services/feature_builder/configuration_generator.dart` (~800 LOC)
- `models/feature_builder/generated_config.dart` (~400 LOC)
- Integration updates (~300 LOC)

### Phase 5: Rust FFI Integration (2 days, ~600 LOC)

**Deliverables:**
- [ ] FeatureBuilderConfig Rust struct
- [ ] slot_lab_apply_feature_config FFI
- [ ] slot_lab_get_current_config FFI
- [ ] Dart FFI bindings
- [ ] RustConfigBridge service

**Files:**
- `crates/rf-slot-lab/src/feature_builder_config.rs` (~300 LOC)
- `crates/rf-bridge/src/feature_builder_ffi.rs` (~150 LOC)
- `services/feature_builder/rust_config_bridge.dart` (~150 LOC)

### Phase 6: UI Panel (4 days, ~2,500 LOC)

**Deliverables:**
- [ ] FeatureBuilderPanel (dockable)
- [ ] BlockListWidget with checkboxes
- [ ] BlockSettingsSheet slide-out
- [ ] DependencyBadge indicators
- [ ] PresetDropdown
- [ ] ApplyConfirmationDialog
- [ ] Dock controls (position, resize, float)

**Files:**
- `widgets/feature_builder/feature_builder_panel.dart` (~600 LOC)
- `widgets/feature_builder/block_list_widget.dart` (~400 LOC)
- `widgets/feature_builder/block_settings_sheet.dart` (~500 LOC)
- `widgets/feature_builder/dependency_badge.dart` (~150 LOC)
- `widgets/feature_builder/preset_dropdown.dart` (~300 LOC)
- `widgets/feature_builder/apply_confirmation_dialog.dart` (~250 LOC)
- Dock system (~300 LOC)

### Phase 7: Validation System (2 days, ~700 LOC)

**Deliverables:**
- [ ] ValidationRule base + 15 built-in rules
- [ ] ValidationService
- [ ] ValidationPanel UI
- [ ] Auto-fix suggestions

**Files:**
- `models/feature_builder/validation_rule.dart` (~200 LOC)
- `services/feature_builder/validation_service.dart` (~300 LOC)
- `widgets/feature_builder/validation_panel.dart` (~200 LOC)

### Phase 8: Preset System (2 days, ~800 LOC)

**Deliverables:**
- [ ] PresetService with CRUD
- [ ] 12 built-in presets
- [ ] Import/export functionality
- [ ] Preset gallery UI

**Files:**
- `services/feature_builder/preset_service.dart` (~400 LOC)
- `data/feature_builder/built_in_presets.dart` (~300 LOC)
- Preset gallery UI (~100 LOC)

### Phase 9: Integration & Testing (2 days, ~500 LOC)

**Deliverables:**
- [ ] SlotLabScreen integration
- [ ] Ultimate Audio Panel stage registration
- [ ] Forced Outcome Panel dynamic controls
- [ ] 30+ unit tests
- [ ] Integration tests

**Files:**
- Integration updates (~200 LOC)
- Tests (~300 LOC)

---

## 13. TOTAL ESTIMATES

| Phase | Days | LOC | Description |
|-------|------|-----|-------------|
| 1. Foundation | 3 | 1,500 | Models, core blocks, registry |
| 2. Feature Blocks | 4 | 2,000 | 7 feature blocks |
| 3. Dependencies | 2 | 800 | Resolver, conflicts |
| 4. Generator | 3 | 1,500 | Config generation |
| 5. Rust FFI | 2 | 600 | Engine integration |
| 6. UI Panel | 4 | 2,500 | Dockable panel |
| 7. Validation | 2 | 700 | Rules, service, UI |
| 8. Presets | 2 | 800 | Service, built-ins |
| 9. Integration | 2 | 500 | Testing, polish |
| **TOTAL** | **24 days** | **~10,900 LOC** | |

---

## 14. SUCCESS CRITERIA

### 14.1 Functional Requirements

- [ ] All 10 blocks fully implemented with all options
- [ ] Dependency system correctly resolves all conflicts
- [ ] Configuration applies to both Dart UI and Rust engine
- [ ] All 12 built-in presets work correctly
- [ ] Outcome controls dynamically reflect enabled blocks
- [ ] Audio stages correctly registered and assignable
- [ ] Validation catches all invalid configurations

### 14.2 Performance Requirements

- [ ] Panel opens in < 100ms
- [ ] Configuration applies in < 500ms
- [ ] Preset load in < 100ms
- [ ] No UI jank during Apply

### 14.3 UX Requirements

- [ ] First-time user can configure slot in < 2 minutes
- [ ] Dependency warnings are clear and actionable
- [ ] Panel docking works smoothly
- [ ] All options have tooltips/descriptions

---

## 15. FUTURE ENHANCEMENTS (V2+)

### 15.1 Custom Block Plugin System

```dart
// External developers can create blocks
class CustomBlock extends FeatureBlock {
  // Load from JSON definition
  factory CustomBlock.fromJson(Map<String, dynamic> json);
}

// Plugin registry
PluginRegistry.registerBlockPlugin('my-custom-feature.json');
```

### 15.2 Visual Flow Editor

Replace text-based dependencies with visual node editor:
- Drag blocks onto canvas
- Connect with wires
- Visual feedback for data flow

### 15.3 Math Model Integration

Connect Feature Builder to actual math model:
- RTP validation
- Hit frequency analysis
- Volatility calculation

### 15.4 Team Collaboration

- Shared presets via cloud
- Preset versioning
- Comments on configurations

---

## 16. APPENDIX: COMPLETE STAGE CATALOG

### Core Stages (Always Present)
```
SPIN_START, SPIN_END
REEL_SPIN_LOOP
REEL_STOP_0, REEL_STOP_1, REEL_STOP_2, REEL_STOP_3, REEL_STOP_4
WIN_EVAL
```

### Win Presentation Stages
```
WIN_PRESENT_LOW, WIN_PRESENT_EQUAL, WIN_PRESENT_1-6
WIN_LINE_SHOW, WIN_LINE_HIDE
WIN_SYMBOL_HIGHLIGHT
ROLLUP_START_*, ROLLUP_TICK_*, ROLLUP_END_*
BIG_WIN_INTRO, BIG_WIN_PRESENT_1-5, BIG_WIN_LOOP, BIG_WIN_END
```

### Free Spins Stages
```
FS_TRIGGER, FS_INTRO
FS_SPIN_START, FS_SPIN_LOOP, FS_SPIN_END
FS_RETRIGGER, FS_TOTAL_WIN, FS_OUTRO
```

### Respin Stages
```
RESPIN_TRIGGER, RESPIN_LOCK, RESPIN_SPIN
RESPIN_WIN, RESPIN_END
```

### Hold & Win Stages
```
HNW_TRIGGER, HNW_INTRO
HNW_SPIN, HNW_COIN_LAND, HNW_COIN_UPGRADE
HNW_RESPIN_RESET, HNW_GRID_FILL
HNW_JACKPOT_MINI, HNW_JACKPOT_MINOR, HNW_JACKPOT_MAJOR, HNW_JACKPOT_GRAND
HNW_TOTAL_WIN, HNW_OUTRO
```

### Cascade Stages
```
CASCADE_START, CASCADE_WIN_SHOW, CASCADE_EXPLODE
CASCADE_DROP, CASCADE_LAND
CASCADE_STEP_N (pooled)
CASCADE_MULTIPLIER, CASCADE_END
```

### Collector Stages
```
COLLECT_SYMBOL, COLLECT_MILESTONE
COLLECT_FULL, COLLECT_REWARD, COLLECT_RESET
COLLECT_PROGRESS
```

### Music/ALE Stages (Context Switches)
```
CONTEXT_BASE_GAME, CONTEXT_FREE_SPINS
CONTEXT_HOLD_AND_WIN, CONTEXT_BONUS
CONTEXT_BIG_WIN
```

---

**END OF SPECIFICATION**

---

*Document generated by Claude Opus 4.5*
*FluxForge Studio — Feature Builder Panel Ultimate Specification v1.0.0*

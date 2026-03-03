# FluxForge Modular Slot Machine Builder — Ultimate Specification

**Version:** 1.0.0
**Date:** 2026-03-01
**Author:** Chief Audio Architect + Engine Architect + Technical Director
**Status:** SPECIFICATION (pre-implementation)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Analysis](#2-current-state-analysis)
3. [Architecture Gap Analysis](#3-architecture-gap-analysis)
4. [L3: Game Flow State Machine](#4-l3-game-flow-state-machine)
5. [L4: Feature Executor](#5-l4-feature-executor)
6. [L5: Feature UI Components](#6-l5-feature-ui-components)
7. [L6: Reactive Preview Pipeline](#7-l6-reactive-preview-pipeline)
8. [Block Interaction Matrix](#8-block-interaction-matrix)
9. [Feature Combination Scenarios](#9-feature-combination-scenarios)
10. [State Persistence & Serialization](#10-state-persistence--serialization)
11. [Edge Cases & Error Recovery](#11-edge-cases--error-recovery)
12. [Data Models](#12-data-models)
13. [Implementation Phases](#13-implementation-phases)

---

## 1. Executive Summary

### Problem

FluxForge has 17 feature blocks that generate **audio stages** (events for middleware), but the slot machine preview widget has NO runtime awareness of feature-specific game flow. When a user enables "Free Spins" in Feature Builder, the audio stage `FS_ENTER` is created — but the slot preview doesn't know how to:

- Enter a Free Spins mode with a spin counter
- Display a multiplier that increases per cascade
- Show a Hold & Win coin grid with locked positions
- Run a Bonus Game pick screen
- Offer a Gamble double-or-nothing after a win

The slot preview currently runs a single loop: **SPIN → STOP → EVALUATE → PRESENT WIN → REPEAT**. All 17 blocks collapse into this one loop regardless of configuration.

### Solution

Four new architectural layers that transform Feature Builder from an "audio stage generator" into a **complete modular slot machine runtime**:

| Layer | Name | Purpose |
|-------|------|---------|
| L3 | Game Flow State Machine | FSM that manages game states (BASE_GAME, FREE_SPINS, HOLD_WIN, BONUS, GAMBLE) with transitions |
| L4 | Feature Executor | Runtime engine that executes feature logic (trigger detection, loop management, exit conditions) |
| L5 | Feature UI Components | Per-feature visual widgets (spin counter, multiplier display, coin grid, pick screen, gamble cards) |
| L6 | Reactive Preview Pipeline | Live preview updates while editing blocks (not just on dialog close) |

### Existing Layers (already implemented)

| Layer | Name | Status |
|-------|------|--------|
| L1 | Block Config | ✅ 17 blocks, 400+ options, dependency resolution |
| L2 | Stage Composition | ✅ FeatureComposerProvider, 3-layer stage system, mechanic→stage mapping |

---

## 2. Current State Analysis

### What Works (L1 + L2)

**L1 — Block Config (FeatureBuilderProvider):**
- 17 registered blocks: 3 core (game_core, grid, symbol_set) + 14 feature/presentation
- 400+ configurable options across all blocks
- Undo/redo (50-deep stack)
- Preset save/load
- Advanced dependency resolution with cycle detection
- Block enable/disable with automatic dependency cascading
- Serialization (export/import JSON)

**L2 — Stage Composition (FeatureComposerProvider):**
- SlotMachineConfig model (reels, rows, paylines, mechanics, volatility)
- 3-layer stage system:
  - Layer 1: Engine Core — 40 locked stages (SPIN_START, REEL_STOP_0..N, WIN_TIER_1..N)
  - Layer 2: Feature-Derived — mechanic-specific (CASCADE_START, FEATURE_ENTER, HOLD_WIN_LOCK)
  - Layer 3: Always-Visible — music, UI, ambience (15 stages)
- ComposedStage model with hooks, priority, bus assignment
- Block ID → SlotMechanic mapping in `_builderBlockToMechanics()`

### What's Missing (L3 + L4 + L5 + L6)

**L3 — Game Flow State Machine:** ❌ DOES NOT EXIST
- No FSM — slot preview has one hardcoded loop
- No state transitions (BASE_GAME → FREE_SPINS → back)
- No nested feature loops (free spins within free spins via retrigger)
- No feature trigger detection beyond win evaluation
- No feature queue (what if scatter + bonus trigger simultaneously?)

**L4 — Feature Executor:** ❌ DOES NOT EXIST
- No runtime logic for any feature (free spins counter, cascade chain, hold & win respins)
- No feature-specific win evaluation modifications
- No multiplier application pipeline
- No feature exit condition evaluation
- No feature interaction resolution (cascade multiplier + free spins multiplier)

**L5 — Feature UI Components:** ❌ DOES NOT EXIST
- No free spins counter overlay
- No multiplier display
- No hold & win coin grid
- No bonus game screens (pick, wheel, trail, ladder)
- No gamble interface (cards, coins, wheel)
- No collector meter
- No jackpot display

**L6 — Reactive Preview:** ❌ DOES NOT EXIST
- Changes only apply on dialog close via `_applyFeatureBuilderResult()`
- No live preview while editing
- No visual diff (before/after block toggle)
- No stage count feedback while editing

---

## 3. Architecture Gap Analysis

### Current Flow (Broken)

```
FeatureBuilder Dialog
  └── User enables Free Spins block
  └── User configures 27 options
  └── User closes dialog
       └── _applyFeatureBuilderResult()
            └── Maps blocks → SlotMechanic enum
            └── Creates SlotMachineConfig
            └── composer.applyConfig()  ← ONLY audio stages updated
            └── Updates grid size
            └── Generates default symbols
            └── Triggers first spin
                 └── Spin runs SAME loop as before
                 └── Free Spins NEVER triggers
                 └── No visual difference
```

### Target Flow (Complete)

```
FeatureBuilder Dialog (or inline panel)
  └── User enables Free Spins block
       └── L6: Reactive preview updates stage count badge
       └── L6: Preview shows "Free Spins capable" indicator
  └── User configures options (trigger: scatter, spins: 10, multiplier: progressive)
       └── L6: Preview updates in real-time
  └── User closes dialog (or changes auto-apply)
       └── L2: Stage composition updates (FS_ENTER, FS_SPIN_START, etc.)
       └── L3: FSM registers FREE_SPINS state + transition rules
       └── L4: FreeSpinsExecutor instantiated with config
       └── L5: FreeSpinsOverlay widget registered
  └── User spins
       └── L3: FSM in BASE_GAME state
       └── Reels stop → win evaluation
       └── L4: Feature trigger scan:
            └── 3+ scatters landed? → FREE_SPINS trigger!
       └── L3: FSM transitions BASE_GAME → FREE_SPINS
            └── L4: FreeSpinsExecutor.enter() — sets counter=10, multiplier=1x
            └── L5: FreeSpinsOverlay appears (counter: 10, multiplier: 1x)
            └── Audio: FS_TRIGGER → FS_INTRO_START → FS_ENTER
       └── Free spin loop:
            └── L4: Auto-spin (no bet deduction)
            └── L3: FSM in FREE_SPINS state
            └── Win? → L4: apply multiplier → L5: update multiplier display
            └── L4: decrement counter → L5: update counter
            └── Counter == 0? → L3: FSM transitions FREE_SPINS → BASE_GAME
                 └── L4: FreeSpinsExecutor.exit() — total win calculated
                 └── L5: FreeSpinsOverlay removed, total win displayed
                 └── Audio: FS_OUTRO_START → FS_EXIT → FS_TOTAL_WIN
```

---

## 4. L3: Game Flow State Machine

### 4.1 State Definitions

```
┌─────────────────────────────────────────────────────────┐
│                    GAME FLOW FSM                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────┐     trigger      ┌──────────────┐        │
│  │          │ ──────────────── │              │        │
│  │  BASE    │                  │  FREE_SPINS  │◄──┐    │
│  │  GAME    │ ◄─────────────  │              │   │    │
│  │          │     exit         │              │───┘    │
│  └────┬─────┘                  └──────────────┘retrig  │
│       │                                                 │
│       │ trigger    ┌──────────────┐                     │
│       ├──────────► │  HOLD_WIN    │                     │
│       │            └──────┬───────┘                     │
│       │                   │ exit                        │
│       │◄──────────────────┘                             │
│       │                                                 │
│       │ trigger    ┌──────────────┐                     │
│       ├──────────► │  BONUS_GAME  │                     │
│       │            └──────┬───────┘                     │
│       │                   │ exit                        │
│       │◄──────────────────┘                             │
│       │                                                 │
│       │ win        ┌──────────────┐                     │
│       ├──────────► │   GAMBLE     │                     │
│       │            └──────┬───────┘                     │
│       │                   │ collect/lose                │
│       │◄──────────────────┘                             │
│       │                                                 │
│       │ trigger    ┌──────────────┐                     │
│       ├──────────► │   RESPIN     │                     │
│       │            └──────┬───────┘                     │
│       │                   │ exit                        │
│       │◄──────────────────┘                             │
│       │                                                 │
│       │ cascade    ┌──────────────┐                     │
│       └──────────► │  CASCADE     │                     │
│                    └──────┬───────┘                     │
│                           │ no more wins               │
│         ◄─────────────────┘                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Game States

```dart
enum GameFlowState {
  /// Initial state, waiting for user action
  idle,

  /// Base game spin cycle: SPIN → STOP → EVALUATE → PRESENT
  baseGame,

  /// Cascade/Tumble chain: remove winning symbols, drop new, re-evaluate
  cascading,

  /// Free spins mode: N free spins with optional multiplier
  freeSpins,

  /// Hold & Win / Cash on Reels: lock coins, respin for more
  holdAndWin,

  /// Bonus game: pick, wheel, trail, ladder, etc.
  bonusGame,

  /// Gamble/Double-up: risk current win for multiplier
  gamble,

  /// Respin: re-spin specific reels
  respin,

  /// Jackpot presentation: special celebration sequence
  jackpotPresentation,

  /// Win presentation: big win, mega win, etc.
  winPresentation,
}
```

### 4.3 Transition Rules

Each transition has:
- **Source state** — where we are
- **Trigger condition** — what causes the transition
- **Priority** — which feature wins if multiple trigger simultaneously
- **Target state** — where we go
- **Entry action** — what happens on entering target state
- **Exit action** — what happens on leaving source state

```dart
class FlowTransition {
  final GameFlowState source;
  final GameFlowState target;
  final TransitionTrigger trigger;
  final int priority;          // Higher = evaluated first
  final bool interruptible;    // Can this transition be interrupted?
  final String? audioStageId;  // Stage to fire on transition
}

enum TransitionTrigger {
  /// Symbol-based triggers
  scatterCount,        // N+ scatters landed
  bonusSymbolCount,    // N+ bonus symbols landed
  coinCount,           // N+ coin symbols landed (Hold & Win)

  /// Win-based triggers
  anyWin,              // Any winning combination
  noWin,               // No winning combination (cascade end)
  winTierReached,      // Specific win tier threshold

  /// Feature-based triggers
  featureBuy,          // Player purchased feature
  retrigger,           // Feature retrigger condition met
  featureComplete,     // Feature loop finished (counter=0, grid full, etc.)
  randomTrigger,       // RNG-based trigger (mystery features)

  /// Player actions
  playerCollect,       // Player chose to collect (gamble)
  playerGamble,        // Player chose to gamble
  playerPick,          // Player made a pick selection

  /// Automatic
  cascadeWin,          // Win detected during cascade evaluation
  cascadeNoWin,        // No win during cascade — chain ends
  respinComplete,      // Respin finished
  jackpotTriggered,    // Jackpot condition met
}
```

### 4.4 Transition Priority Resolution

When multiple features trigger simultaneously (e.g., 3 scatters + 6 coins on same spin):

```
Priority Order (highest first):
  1. Jackpot (priority: 100) — always takes precedence
  2. Hold & Win (priority: 90) — locks coins immediately
  3. Free Spins (priority: 80) — enters free spins mode
  4. Bonus Game (priority: 70) — enters bonus
  5. Respin (priority: 60) — enters respin
  6. Cascade (priority: 50) — starts cascade chain
  7. Gamble (priority: 30) — offered after win presentation

Queue Rule: Lower-priority features are QUEUED, not discarded.
After the highest-priority feature completes, the queue is checked.
Example: Jackpot triggers → after celebration → check if Free Spins
was also triggered → enter Free Spins.
```

### 4.5 Feature Queue

```dart
class FeatureQueue {
  final Queue<PendingFeature> _queue = Queue();

  void enqueue(PendingFeature feature);
  PendingFeature? dequeue();
  bool get isEmpty;
  void clear();

  /// Sort by priority, highest first
  void prioritize();
}

class PendingFeature {
  final GameFlowState targetState;
  final Map<String, dynamic> triggerContext;  // scatter positions, coin values, etc.
  final int priority;
  final String sourceBlockId;
}
```

### 4.6 Nested Features

Some features can trigger WITHIN other features:

```
BASE_GAME
  └── Free Spins triggered (3 scatters)
       └── FREE_SPINS (10 spins)
            ├── Spin 3: Cascade triggered (any win)
            │    └── CASCADING (within free spins context)
            │         └── Cascade multiplier: 1x → 2x → 3x
            │         └── No more wins → back to FREE_SPINS
            ├── Spin 5: Retrigger (3+ scatters again)
            │    └── FREE_SPINS counter += retriggerSpins
            ├── Spin 8: Hold & Win triggered (6+ coins)
            │    └── HOLD_WIN (within free spins context)
            │         └── All coins collected → back to FREE_SPINS
            │         └── Free spins multiplier APPLIES to Hold & Win total
            └── Spin 10: Exit → total win → back to BASE_GAME
                 └── Gamble offered (if gambling block enabled)
                      └── GAMBLE
                           └── Collect/Lose → BASE_GAME
```

**Nesting Rules:**
- CASCADE can nest inside: BASE_GAME, FREE_SPINS, RESPIN
- HOLD_WIN can nest inside: FREE_SPINS (if triggerInFreeSpins=true)
- GAMBLE can trigger after: any feature exit with win > 0
- RESPIN can nest inside: FREE_SPINS
- BONUS_GAME can nest inside: FREE_SPINS (if bonus symbols land)
- JACKPOT can trigger from: any state

```dart
class GameFlowStack {
  final List<GameFlowFrame> _stack = [];

  GameFlowFrame get current => _stack.last;
  int get depth => _stack.length;

  void push(GameFlowFrame frame);
  GameFlowFrame pop();
  bool canNest(GameFlowState child, GameFlowState parent);
}

class GameFlowFrame {
  final GameFlowState state;
  final Map<String, dynamic> context;  // feature-specific data
  final DateTime enteredAt;
  final GameFlowState? parentState;    // null for BASE_GAME
}
```

### 4.7 State Machine Provider

```dart
class GameFlowProvider extends ChangeNotifier {
  GameFlowState _currentState = GameFlowState.idle;
  final GameFlowStack _stack = GameFlowStack();
  final FeatureQueue _featureQueue = FeatureQueue();
  final Map<GameFlowState, List<FlowTransition>> _transitions = {};

  // Public API
  GameFlowState get currentState => _currentState;
  bool get isInFeature => _currentState != GameFlowState.baseGame
                       && _currentState != GameFlowState.idle;
  int get featureDepth => _stack.depth;
  GameFlowState? get parentState => _stack.current.parentState;

  /// Register transitions based on enabled blocks
  void configureFromBlocks(List<FeatureBlock> enabledBlocks);

  /// Evaluate triggers after reel stop / win evaluation
  void evaluateTriggers(SpinResult result);

  /// Manually trigger a state change (feature buy, player action)
  void triggerTransition(TransitionTrigger trigger, {Map<String, dynamic>? context});

  /// Complete current feature and return to parent or dequeue next
  void completeCurrentFeature();

  /// Force return to base game (error recovery)
  void resetToBaseGame();
}
```

---

## 5. L4: Feature Executor

### 5.1 Executor Interface

Every feature block that affects game flow has a corresponding Executor:

```dart
abstract class FeatureExecutor {
  /// Block this executor belongs to
  String get blockId;

  /// Initialize with block config options
  void configure(Map<String, dynamic> options);

  /// Called when FSM enters this feature's state
  /// Returns the initial feature state (counters, multipliers, etc.)
  FeatureState enter(TriggerContext context);

  /// Called each spin/action within the feature
  /// Returns updated state + whether feature should continue
  FeatureStepResult step(SpinResult spinResult, FeatureState currentState);

  /// Called when feature exits (counter=0, grid full, player collect, etc.)
  FeatureExitResult exit(FeatureState finalState);

  /// Check if this feature should trigger given current spin result
  bool shouldTrigger(SpinResult result, GameFlowState currentState);

  /// Modify win evaluation for this feature (e.g., apply multiplier)
  WinResult modifyWin(WinResult baseWin, FeatureState state);

  /// Get current audio stage ID for middleware
  String? getCurrentAudioStage(FeatureState state);

  /// Cleanup
  void dispose();
}
```

### 5.2 Feature State

```dart
class FeatureState {
  final String featureId;
  final int spinsRemaining;      // Free spins counter
  final int spinsCompleted;      // How many done
  final int totalSpins;          // Total allocated
  final double currentMultiplier; // Active multiplier
  final double maxMultiplier;
  final int cascadeDepth;        // Current cascade chain
  final int respinsRemaining;    // Hold & Win respins
  final Map<String, dynamic> customData;  // Feature-specific data

  // Hold & Win specific
  final List<CoinPosition>? lockedCoins;
  final int gridPositionsFilled;
  final int gridPositionsTotal;

  // Bonus Game specific
  final int currentLevel;
  final int totalLevels;
  final int picksRemaining;
  final double accumulatedPrize;

  // Gamble specific
  final double currentStake;
  final int roundsPlayed;
  final int maxRounds;

  // Collector specific
  final Map<String, int> meterValues;   // meterId → current count
  final Map<String, int> meterTargets;  // meterId → target

  // Computed
  bool get isComplete;
  double get progress;  // 0.0 → 1.0
}
```

### 5.3 Concrete Executors

#### 5.3.1 FreeSpinsExecutor

```dart
class FreeSpinsExecutor extends FeatureExecutor {
  // Config from block options
  late FreeSpinsTriggerMode _triggerMode;
  late int _baseSpinsCount;
  late bool _variableSpins;
  late Map<int, int> _spinsPerScatterCount;  // {3: 10, 4: 15, 5: 20}
  late RetriggerMode _retriggerMode;
  late int _retriggerSpins;
  late int _maxRetriggers;
  late bool _hasMultiplier;
  late MultiplierBehavior _multiplierBehavior;
  late int _baseMultiplier;
  late int _maxMultiplier;
  late int _multiplierStep;

  @override
  bool shouldTrigger(SpinResult result, GameFlowState currentState) {
    if (currentState == GameFlowState.freeSpins) {
      // Check retrigger
      return _canRetrigger(result);
    }
    switch (_triggerMode) {
      case FreeSpinsTriggerMode.scatter:
        return result.scatterCount >= _minScattersToTrigger;
      case FreeSpinsTriggerMode.bonus:
        return result.bonusSymbolCount >= _minScattersToTrigger;
      case FreeSpinsTriggerMode.anyWin:
        return result.hasWin && _randomCheck(_triggerChance);
      case FreeSpinsTriggerMode.featureBuy:
        return false; // Manual trigger only
      // ... etc
    }
  }

  @override
  FeatureState enter(TriggerContext context) {
    int spins = _baseSpinsCount;
    if (_variableSpins && context.scatterCount != null) {
      spins = _spinsPerScatterCount[context.scatterCount] ?? _baseSpinsCount;
    }
    return FeatureState(
      featureId: 'free_spins',
      spinsRemaining: spins,
      totalSpins: spins,
      currentMultiplier: _hasMultiplier ? _baseMultiplier.toDouble() : 1.0,
      maxMultiplier: _maxMultiplier.toDouble(),
    );
  }

  @override
  FeatureStepResult step(SpinResult spinResult, FeatureState state) {
    var newState = state.copyWith(
      spinsRemaining: state.spinsRemaining - 1,
      spinsCompleted: state.spinsCompleted + 1,
    );

    // Apply multiplier behavior
    if (_hasMultiplier) {
      newState = _updateMultiplier(newState, spinResult);
    }

    // Check retrigger
    if (_retriggerMode != RetriggerMode.none && shouldTrigger(spinResult, GameFlowState.freeSpins)) {
      newState = _applyRetrigger(newState);
    }

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: newState.spinsRemaining > 0,
      audioStages: _getStepAudioStages(newState, spinResult),
    );
  }

  @override
  WinResult modifyWin(WinResult baseWin, FeatureState state) {
    if (!_hasMultiplier) return baseWin;
    return baseWin.copyWith(
      amount: baseWin.amount * state.currentMultiplier,
      appliedMultiplier: state.currentMultiplier,
    );
  }
}
```

#### 5.3.2 CascadeExecutor

```dart
class CascadeExecutor extends FeatureExecutor {
  late CascadeTrigger _trigger;
  late RemovalStyle _removalStyle;
  late FillStyle _fillStyle;
  late int _cascadeDelay;
  late int _maxCascades;
  late CascadeMultiplierType _multiplierType;
  late int _baseMultiplier;
  late int _multiplierIncrement;
  late int _maxMultiplier;

  @override
  bool shouldTrigger(SpinResult result, GameFlowState currentState) {
    // Cascades trigger on ANY win (most common)
    switch (_trigger) {
      case CascadeTrigger.anyWin:
        return result.hasWin;
      case CascadeTrigger.specificSymbols:
        return result.hasWinningSymbol(_targetSymbol);
      case CascadeTrigger.scatterBased:
        return result.scatterCount >= 2;
      case CascadeTrigger.wildBased:
        return result.wildCount >= 1 && result.hasWin;
    }
  }

  @override
  FeatureStepResult step(SpinResult spinResult, FeatureState state) {
    // Each cascade step:
    // 1. Remove winning symbols from grid
    // 2. Drop new symbols into empty positions
    // 3. Re-evaluate wins
    // 4. If win → continue chain, else → end

    var newState = state.copyWith(
      cascadeDepth: state.cascadeDepth + 1,
    );

    if (_multiplierType == CascadeMultiplierType.progressive) {
      double newMult = (_baseMultiplier + (state.cascadeDepth * _multiplierIncrement))
          .toDouble()
          .clamp(1.0, _maxMultiplier.toDouble());
      newState = newState.copyWith(currentMultiplier: newMult);
    }

    bool maxReached = _maxCascades > 0 && newState.cascadeDepth >= _maxCascades;
    bool shouldContinue = spinResult.hasWin && !maxReached;

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: shouldContinue,
      gridModification: GridModification(
        removedPositions: spinResult.winningPositions,
        removalStyle: _removalStyle,
        fillStyle: _fillStyle,
        delayMs: _cascadeDelay,
      ),
    );
  }
}
```

#### 5.3.3 HoldAndWinExecutor

```dart
class HoldAndWinExecutor extends FeatureExecutor {
  late HoldAndWinMode _mode;
  late int _minCoinsToTrigger;
  late int _initialRespins;
  late bool _respinsReset;
  late bool _hasJackpots;
  late int _jackpotTierCount;
  late CoinValueType _coinValueType;

  @override
  FeatureState enter(TriggerContext context) {
    // Lock initial coins that triggered the feature
    List<CoinPosition> coins = context.triggeringCoins!.map((pos) {
      return CoinPosition(
        reel: pos.reel,
        row: pos.row,
        value: _generateCoinValue(),
        isLocked: true,
        isSpecial: false, // multiplier/collector/upgrade coins
      );
    }).toList();

    return FeatureState(
      featureId: 'hold_and_win',
      respinsRemaining: _initialRespins,
      lockedCoins: coins,
      gridPositionsFilled: coins.length,
      gridPositionsTotal: _reelCount * _rowCount,
    );
  }

  @override
  FeatureStepResult step(SpinResult spinResult, FeatureState state) {
    var newState = state;
    List<String> audioStages = [];

    // Check for new coins
    List<CoinPosition> newCoins = _findNewCoins(spinResult, state.lockedCoins!);

    if (newCoins.isNotEmpty) {
      // New coins landed — reset respins
      var updatedCoins = [...state.lockedCoins!, ...newCoins];
      newState = state.copyWith(
        lockedCoins: updatedCoins,
        gridPositionsFilled: updatedCoins.length,
        respinsRemaining: _respinsReset ? _initialRespins : state.respinsRemaining - 1,
      );
      for (var coin in newCoins) {
        audioStages.add('HOLD_COIN_LAND');
        if (coin.isSpecial) audioStages.add('HOLD_${coin.specialType.toUpperCase()}_COIN');
      }
    } else {
      // No new coins — decrement respins
      newState = state.copyWith(respinsRemaining: state.respinsRemaining - 1);
    }

    // Check grid full
    bool gridFull = newState.gridPositionsFilled >= newState.gridPositionsTotal;
    if (gridFull) {
      audioStages.add('HOLD_GRID_FULL');
      if (_hasJackpots) audioStages.add('HOLD_GRAND_PRIZE');
    }

    bool shouldContinue = !gridFull && newState.respinsRemaining > 0;

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: shouldContinue,
      audioStages: audioStages,
    );
  }
}
```

#### 5.3.4 BonusGameExecutor

```dart
class BonusGameExecutor extends FeatureExecutor {
  late String _bonusType;  // pick, wheel, trail, ladder, expanding, match
  late bool _multiLevel;
  late int _levelCount;

  @override
  FeatureState enter(TriggerContext context) {
    return FeatureState(
      featureId: 'bonus_game',
      currentLevel: 1,
      totalLevels: _multiLevel ? _levelCount : 1,
      picksRemaining: _bonusType == 'pick' ? _pickAllowed : 0,
      accumulatedPrize: 0.0,
      customData: {
        'bonusType': _bonusType,
        'items': _generateBonusItems(),
        'revealed': <int>[],
      },
    );
  }

  /// Bonus game steps are driven by PLAYER ACTION, not auto-spin
  /// The step() method is called when player makes a pick/spin/move
  @override
  FeatureStepResult step(SpinResult spinResult, FeatureState state) {
    switch (_bonusType) {
      case 'pick':
        return _stepPick(spinResult, state);
      case 'wheel':
        return _stepWheel(spinResult, state);
      case 'trail':
        return _stepTrail(spinResult, state);
      case 'ladder':
        return _stepLadder(spinResult, state);
      case 'match':
        return _stepMatch(spinResult, state);
      default:
        return FeatureStepResult(updatedState: state, shouldContinue: false);
    }
  }

  FeatureStepResult _stepPick(SpinResult result, FeatureState state) {
    int selectedIndex = result.customData['selectedIndex'] as int;
    var items = state.customData['items'] as List<BonusItem>;
    var revealed = List<int>.from(state.customData['revealed'] as List);
    revealed.add(selectedIndex);

    BonusItem item = items[selectedIndex];
    List<String> audioStages = ['BONUS_PICK_SELECT'];

    double newPrize = state.accumulatedPrize;
    bool shouldContinue = true;

    switch (item.type) {
      case BonusItemType.prize:
        newPrize += item.value;
        audioStages.add('BONUS_PICK_REVEAL_PRIZE');
        break;
      case BonusItemType.multiplier:
        newPrize *= item.value;
        audioStages.add('BONUS_PICK_REVEAL_UPGRADE');
        break;
      case BonusItemType.collect:
        audioStages.add('BONUS_PICK_REVEAL_COLLECT');
        shouldContinue = false;  // Popper — game over
        break;
      case BonusItemType.freeSpins:
        // Queue free spins after bonus
        audioStages.add('BONUS_PICK_REVEAL_PRIZE');
        break;
    }

    // Check if picks exhausted
    int picksLeft = state.picksRemaining - 1;
    if (picksLeft <= 0 && _pickUntilPopper) {
      // Continue until popper — don't end
    } else if (picksLeft <= 0) {
      shouldContinue = false;
    }

    return FeatureStepResult(
      updatedState: state.copyWith(
        picksRemaining: picksLeft,
        accumulatedPrize: newPrize,
        customData: {...state.customData, 'revealed': revealed},
      ),
      shouldContinue: shouldContinue,
      audioStages: audioStages,
    );
  }
}
```

#### 5.3.5 GambleExecutor

```dart
class GambleExecutor extends FeatureExecutor {
  late String _gambleType;
  late int _maxRounds;
  late double _maxWinMultiplier;
  late bool _allowHalfGamble;

  @override
  bool shouldTrigger(SpinResult result, GameFlowState currentState) {
    // Gamble only offered after a win in base game or feature exit
    return result.hasWin && result.winAmount > 0;
  }

  @override
  FeatureState enter(TriggerContext context) {
    return FeatureState(
      featureId: 'gamble',
      currentStake: context.winAmount!,
      roundsPlayed: 0,
      maxRounds: _maxRounds,
      customData: {
        'gambleType': _gambleType,
        'originalWin': context.winAmount,
        'history': <GambleResult>[],
      },
    );
  }

  @override
  FeatureStepResult step(SpinResult result, FeatureState state) {
    // Player chose gamble or collect
    if (result.customData['action'] == 'collect') {
      return FeatureStepResult(
        updatedState: state,
        shouldContinue: false,
        audioStages: ['GAMBLE_COLLECT'],
      );
    }

    bool won = _evaluateGamble(result, state);
    var history = List<GambleResult>.from(state.customData['history'] as List);

    if (won) {
      double multiplier = _getWinMultiplier();
      double newStake = state.currentStake * multiplier;
      bool maxReached = newStake >= state.customData['originalWin']! * _maxWinMultiplier;
      bool roundsExhausted = state.roundsPlayed + 1 >= _maxRounds;

      history.add(GambleResult(won: true, multiplier: multiplier));

      return FeatureStepResult(
        updatedState: state.copyWith(
          currentStake: newStake,
          roundsPlayed: state.roundsPlayed + 1,
          customData: {...state.customData, 'history': history},
        ),
        shouldContinue: !maxReached && !roundsExhausted,
        audioStages: ['GAMBLE_REVEAL', 'GAMBLE_WIN'],
      );
    } else {
      history.add(GambleResult(won: false, multiplier: 0));
      return FeatureStepResult(
        updatedState: state.copyWith(
          currentStake: 0,
          roundsPlayed: state.roundsPlayed + 1,
          customData: {...state.customData, 'history': history},
        ),
        shouldContinue: false,
        audioStages: ['GAMBLE_REVEAL', 'GAMBLE_LOSE'],
      );
    }
  }
}
```

#### 5.3.6 Additional Executors

| Executor | Key Logic |
|----------|-----------|
| **RespinExecutor** | Lock triggering symbols, respin remaining reels, check for new symbols, countdown/untilNoNew/untilFull |
| **CollectorExecutor** | Track meter progress per spin, fire milestone rewards, handle meter full (trigger FS, award prize, upgrade symbol) |
| **MultiplierExecutor** | Track global/reel/symbol/random multipliers, apply to win pipeline, handle progression |
| **JackpotExecutor** | Monitor jackpot trigger conditions, handle progressive pool, tier-specific celebrations |
| **WildFeatureExecutor** | Track sticky/walking/expanding wilds across spins, manage positions, handle expiry |

### 5.4 Executor Registry

```dart
class FeatureExecutorRegistry {
  final Map<String, FeatureExecutor> _executors = {};

  /// Build executors from enabled blocks
  void buildFromBlocks(List<FeatureBlock> enabledBlocks) {
    _executors.clear();
    for (final block in enabledBlocks) {
      final executor = _createExecutor(block);
      if (executor != null) {
        executor.configure(block.currentValues);
        _executors[block.id] = executor;
      }
    }
  }

  FeatureExecutor? _createExecutor(FeatureBlock block) {
    switch (block.id) {
      case 'free_spins': return FreeSpinsExecutor();
      case 'cascades': return CascadeExecutor();
      case 'hold_and_win': return HoldAndWinExecutor();
      case 'bonus_game': return BonusGameExecutor();
      case 'gambling': return GambleExecutor();
      case 'respin': return RespinExecutor();
      case 'collector': return CollectorExecutor();
      case 'multiplier': return MultiplierExecutor();
      case 'jackpot': return JackpotExecutor();
      case 'wild_features': return WildFeatureExecutor();
      default: return null; // Presentation blocks don't have executors
    }
  }

  /// Get all executors that should trigger for this spin result
  List<FeatureExecutor> getTriggeredExecutors(
    SpinResult result,
    GameFlowState currentState,
  ) {
    return _executors.values
      .where((e) => e.shouldTrigger(result, currentState))
      .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  FeatureExecutor? getExecutor(String blockId) => _executors[blockId];
}
```

### 5.5 Win Pipeline

The win evaluation pipeline applies feature modifications in order:

```
Raw Win (from symbol evaluation)
  │
  ├── CascadeExecutor.modifyWin()      — cascade multiplier (e.g., 3x on 3rd cascade)
  │
  ├── FreeSpinsExecutor.modifyWin()    — free spins multiplier (e.g., 5x progressive)
  │
  ├── MultiplierExecutor.modifyWin()   — global/reel/symbol multipliers
  │
  ├── WildFeatureExecutor.modifyWin()  — wild multipliers (if wild in winning combo)
  │
  └── Final Win Amount
       │
       ├── Win Tier Determination (small, big, super, mega, epic, ultra)
       │
       ├── Win Presentation (rollup, plaque, celebration)
       │
       └── Gamble Offer (if gambling block enabled && win > 0)
```

```dart
class WinPipeline {
  final List<FeatureExecutor> _activeExecutors;

  WinResult process(WinResult rawWin, Map<String, FeatureState> featureStates) {
    WinResult result = rawWin;
    for (final executor in _activeExecutors) {
      final state = featureStates[executor.blockId];
      if (state != null) {
        result = executor.modifyWin(result, state);
      }
    }
    return result;
  }
}
```

---

## 6. L5: Feature UI Components

### 6.1 Component Architecture

Each feature has a dedicated overlay widget that the slot preview widget hosts:

```dart
/// Base class for all feature overlay widgets
abstract class FeatureOverlay extends StatefulWidget {
  final FeatureState featureState;
  final VoidCallback? onAction;  // Player input for interactive features

  const FeatureOverlay({required this.featureState, this.onAction});
}
```

### 6.2 Free Spins Overlay

```
┌─────────────────────────────────────────┐
│  ╔═══════════════════════════════════╗  │
│  ║  FREE SPINS: 7 / 10              ║  │
│  ║  MULTIPLIER: 3x                  ║  │
│  ║  TOTAL WIN: 450.00               ║  │
│  ╚═══════════════════════════════════╝  │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │                                 │    │
│  │     [Slot Machine Grid]         │    │
│  │     (auto-spinning)             │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  Spin 1: 25.00 (1x)            │    │
│  │  Spin 2: ---                    │    │
│  │  Spin 3: 150.00 (2x)           │    │
│  │  ▼ more...                      │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

**Widget:** `FreeSpinsOverlay`
**Data from:** `FeatureState.spinsRemaining`, `.currentMultiplier`, accumulated win
**Animations:**
- Counter decrement: number flip animation
- Multiplier increase: scale bounce + color flash
- Retrigger: "+5 SPINS!" text animation
- Last spin: counter pulses red

### 6.3 Hold & Win Overlay

```
┌─────────────────────────────────────────┐
│  ╔═══════════════════════════════════╗  │
│  ║  HOLD & WIN    Respins: 3        ║  │
│  ╚═══════════════════════════════════╝  │
│                                         │
│  ┌─────┬─────┬─────┬─────┬─────┐      │
│  │     │ 5x  │     │ 2x  │     │      │
│  ├─────┼─────┼─────┼─────┼─────┤      │
│  │ 3x  │     │ 10x │     │ 1x  │      │
│  ├─────┼─────┼─────┼─────┼─────┤      │
│  │     │ 1x  │     │     │ 5x  │      │
│  └─────┴─────┴─────┴─────┴─────┘      │
│   Filled: 7/15                          │
│                                         │
│  JACKPOTS:                              │
│  [MINI: 20x] [MINOR: 50x]              │
│  [MAJOR: 250x] [★ GRAND: 1000x]        │
└─────────────────────────────────────────┘
```

**Widget:** `HoldAndWinOverlay`
**Data from:** `FeatureState.lockedCoins`, `.respinsRemaining`, `.gridPositionsFilled`
**Animations:**
- Coin land: drop + bounce + value reveal
- Respin reset: counter flash green
- Grid full: all coins pulse gold + grand prize sequence
- Special coins: multiplier coins glow blue, collector coins glow green

### 6.4 Cascade Overlay

```
┌─────────────────────────────────────────┐
│  CASCADE: Level 4    Multiplier: 4x     │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │                                 │    │
│  │  [Grid with exploding symbols]  │    │
│  │  [New symbols dropping in]      │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Chain: █████████░░░░░░ (4/10 max)      │
│  Cascade Win: 320.00                    │
└─────────────────────────────────────────┘
```

**Widget:** `CascadeOverlay`
**Not a separate screen** — modifies the existing grid with:
- Symbol removal animation (explode/dissolve/fallOff/collect/shatter)
- Symbol fill animation (dropFromTop/slideIn/fadeIn/popIn)
- Multiplier badge in corner
- Chain progress bar (if maxCascades > 0)

### 6.5 Bonus Game Overlays

**Pick Game:**
```
┌─────────────────────────────────────────┐
│  BONUS ROUND — Pick 3 items!            │
│                                         │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐       │
│  │??│ │??│ │25│ │??│ │??│ │??│       │
│  └──┘ └──┘ └──┘ └──┘ └──┘ └──┘       │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐       │
│  │??│ │??│ │??│ │50│ │??│ │??│       │
│  └──┘ └──┘ └──┘ └──┘ └──┘ └──┘       │
│                                         │
│  Picks remaining: 2                     │
│  Total won: 75.00                       │
└─────────────────────────────────────────┘
```

**Wheel Game:**
```
┌─────────────────────────────────────────┐
│  BONUS ROUND — Spin the Wheel!          │
│                                         │
│          ╭─────────────╮                │
│        ╱   50  │  100   ╲               │
│      ╱  25 ────┼──── 200 ╲              │
│     │   10 ────┼──── 500  │             │
│      ╲  25 ────┼──── 150 ╱              │
│        ╲   50  │   75  ╱               │
│          ╰─────────────╯                │
│              ▲ pointer                  │
│                                         │
│  [SPIN]                                 │
│  Total won: 0.00                        │
└─────────────────────────────────────────┘
```

**Widget:** `BonusGameOverlay` with sub-widgets per type:
- `PickGameWidget` — grid of hidden items, tap to reveal
- `WheelGameWidget` — spinning wheel with pointer
- `TrailGameWidget` — board game path with dice
- `LadderGameWidget` — vertical ladder with safe zones
- `MatchGameWidget` — memory card matching

### 6.6 Gamble Overlay

```
┌─────────────────────────────────────────┐
│  GAMBLE — Double or Nothing!            │
│                                         │
│  Current Win: 200.00                    │
│  Potential: 400.00                      │
│                                         │
│       ┌────────┐    ┌────────┐          │
│       │        │    │   ??   │          │
│       │  ♥ 7   │    │        │          │
│       │        │    │        │          │
│       └────────┘    └────────┘          │
│      Dealer Card    Your Card           │
│                                         │
│  Pick: [RED]  [BLACK]                   │
│                                         │
│  History: ♥ ♠ ♥ ♥ ♠ ♦ ♣                │
│                                         │
│  [COLLECT 200.00]  Round 2/5            │
└─────────────────────────────────────────┘
```

**Widget:** `GambleOverlay` with sub-widgets:
- `CardGambleWidget` — card color/suit prediction
- `CoinFlipWidget` — heads/tails
- `GambleWheelWidget` — multiplier wheel
- `LadderGambleWidget` — climb ladder
- `DiceGambleWidget` — higher/lower dice

### 6.7 Collector Meter

```
┌─────────────────────────────────────────┐
│  Not a separate screen — persistent     │
│  overlay on the grid                    │
│                                         │
│  ┌────────────────────┐                 │
│  │ ★ Collector        │                 │
│  │ ████████████░░░░░░ │ 18/25           │
│  │ Milestone: 20 → 🎁 │                 │
│  └────────────────────┘                 │
│                                         │
│  Multiple meters stack vertically       │
│  Fly-to animation from grid to meter    │
└─────────────────────────────────────────┘
```

### 6.8 Multiplier Display

```
┌─────────────────────────────────────────┐
│  Floating badge on grid corner          │
│                                         │
│  ┌──────┐                               │
│  │  5x  │  ← Global multiplier         │
│  └──────┘                               │
│                                         │
│  Per-reel: overlay on reel header       │
│  Per-symbol: badge on individual symbol │
│  Random: dramatic reveal animation      │
└─────────────────────────────────────────┘
```

### 6.9 Jackpot Display

```
┌─────────────────────────────────────────┐
│  Persistent ticker above grid           │
│                                         │
│  MINI: 20.00  MINOR: 50.00             │
│  MAJOR: 250.00  GRAND: 1,000.00        │
│                                         │
│  Contribution animation: +0.02 per spin │
│  Near-trigger: tier pulses/glows        │
│  Triggered: fullscreen celebration      │
└─────────────────────────────────────────┘
```

### 6.10 Widget Registration

```dart
class FeatureOverlayRegistry {
  final Map<String, FeatureOverlayBuilder> _builders = {};

  void register(String blockId, FeatureOverlayBuilder builder);

  /// Build all active overlays for current game state
  List<Widget> buildActiveOverlays(
    GameFlowState state,
    Map<String, FeatureState> featureStates,
  ) {
    return featureStates.entries
      .where((e) => _builders.containsKey(e.key))
      .map((e) => _builders[e.key]!(e.value))
      .toList();
  }
}

typedef FeatureOverlayBuilder = Widget Function(FeatureState state);
```

---

## 7. L6: Reactive Preview Pipeline

### 7.1 Real-Time Block Editing

Currently, block changes only apply when the Feature Builder dialog closes. The target is **live preview**:

```
User toggles "Free Spins" ON in Feature Builder
  │
  ├── IMMEDIATE (< 16ms):
  │    └── Stage count badge updates ("+27 stages")
  │    └── Feature indicator appears on preview ("FS" chip)
  │    └── Dependency validation runs (warnings/errors)
  │
  ├── DEFERRED (< 100ms):
  │    └── FeatureComposerProvider recomposes stages
  │    └── GameFlowProvider registers new transitions
  │    └── FeatureExecutorRegistry creates FreeSpinsExecutor
  │
  └── ON NEXT SPIN:
       └── Full feature flow active (trigger detection, counter, multiplier)
```

### 7.2 Preview Stream

```dart
class FeaturePreviewStream {
  final StreamController<PreviewUpdate> _controller =
      StreamController<PreviewUpdate>.broadcast();

  Stream<PreviewUpdate> get updates => _controller.stream;

  void onBlockToggled(String blockId, bool enabled) {
    // Immediate visual feedback
    _controller.add(PreviewUpdate.blockToggle(blockId, enabled));

    // Deferred composition
    _scheduleRecomposition();
  }

  void onOptionChanged(String blockId, String optionId, dynamic value) {
    // Immediate option feedback (e.g., grid size change)
    _controller.add(PreviewUpdate.optionChange(blockId, optionId, value));

    // Some options require grid rebuild
    if (_isGridAffectingOption(blockId, optionId)) {
      _scheduleGridRebuild();
    }
  }
}

class PreviewUpdate {
  final PreviewUpdateType type;
  final String? blockId;
  final String? optionId;
  final dynamic value;
  final int? stageCountDelta;
  final List<String>? newStageIds;
  final List<String>? removedStageIds;
}
```

### 7.3 Split Panel Preview

Feature Builder and slot preview can be shown side-by-side:

```
┌──────────────────────┬──────────────────────┐
│  FEATURE BUILDER     │  LIVE PREVIEW        │
│                      │                      │
│  ☑ Game Core         │  ┌────────────────┐  │
│  ☑ Grid (5x3)       │  │                │  │
│  ☑ Symbol Set        │  │  [Slot Grid]   │  │
│  ☑ Free Spins ←NEW  │  │  5x3, 20 lines │  │
│    Trigger: Scatter  │  │                │  │
│    Spins: 10         │  └────────────────┘  │
│    Multiplier: Prog  │                      │
│  ☐ Cascades          │  Features: FS        │
│  ☐ Hold & Win        │  Stages: 67          │
│  ☐ Bonus Game        │  States: 3           │
│                      │  (BASE, FS, GAMBLE)  │
│  Stages: 67 (+27)   │                      │
│  Warnings: 0         │  [SPIN] [AUTO]       │
│  Errors: 0           │                      │
└──────────────────────┴──────────────────────┘
```

### 7.4 Feature Capability Indicators

Visual chips on the preview showing which features are "armed":

```dart
class FeatureCapabilityChips extends StatelessWidget {
  final List<String> enabledFeatures;

  // Renders horizontal row of chips:
  // [FS] [CASCADE] [JACKPOT] [GAMBLE] [WILD×3]
  // Each chip is color-coded by category:
  // - Green: active features (FS, CASCADE, H&W)
  // - Gold: win modifiers (MULTIPLIER, JACKPOT)
  // - Blue: presentation (WIN_PRES, MUSIC, TRANSITIONS)
  // - Purple: interactive (GAMBLE, BONUS)
}
```

---

## 8. Block Interaction Matrix

### 8.1 Feature Combination Rules

| Block A | Block B | Interaction | Resolution |
|---------|---------|-------------|------------|
| Free Spins | Cascades | Cascade multiplier active during FS | Both multipliers multiply (not add) |
| Free Spins | Hold & Win | H&W can trigger inside FS if `triggerInFreeSpins=true` | FS pauses, H&W runs, total applied with FS multiplier |
| Free Spins | Multiplier | Global multiplier applies to FS wins | FS multiplier × global multiplier |
| Free Spins | Gamble | Gamble offered after FS total win | Gamble stake = FS total win |
| Free Spins | Collector | Meter continues during FS, meter full can retrigger FS | Retrigger adds spins |
| Free Spins | Wild Features | Sticky/expanding/walking wilds persist across FS spins | Wild positions tracked in FS state |
| Cascades | Multiplier | Both cascade mult and global mult apply | Cascade × Global |
| Cascades | Wild Features | Wilds can expand/stick during cascade chain | Wild state preserved between cascades |
| Hold & Win | Jackpot | Grid full = Grand jackpot | Jackpot value from jackpot block config |
| Hold & Win | Respin | CONFLICT — overlapping mechanics | Only one can be enabled (dependency rule) |
| Hold & Win | Multiplier | Multiplier coins exist | Special coin values multiply total |
| Hold & Win | Collector | Collector coins exist | Coins add to meter |
| Bonus Game | Jackpot | Wheel/pick can award jackpot | Jackpot prize from jackpot block config |
| Bonus Game | Free Spins | Pick can award FS | Queue FS after bonus exit |
| Bonus Game | Multiplier | Bonus prizes can have multipliers | Multiplier applied to bonus total |
| Gamble | ANY | Offered after any feature exit with win > 0 | Stake = total win from feature |
| Jackpot | ANY | Can trigger from any state | Interrupts current state, queues return |
| Anticipation | Grid | Per-reel anticipation based on reel count | Stages generated per reel |
| Anticipation | Symbol Set | Trigger symbol type (scatter/bonus/wild) | From anticipation block config |
| Music States | ALL features | Each feature has dedicated music context | Crossfade between contexts |
| Transitions | ALL features | Each feature entry/exit has transition audio | Stingers, crossfades, beat-sync |
| Win Presentation | ALL features | Win tier thresholds, rollup, celebration | All features feed into win pipeline |

### 8.2 Multiplier Stacking Rules

When multiple multipliers are active simultaneously:

```
Scenario: Free Spins (3x) + Cascade (4th cascade = 4x) + Wild Multiplier (2x)

Option A — MULTIPLICATIVE (industry standard):
  Base win: 50.00
  After cascade: 50.00 × 4 = 200.00
  After FS: 200.00 × 3 = 600.00
  After wild: 600.00 × 2 = 1,200.00

Option B — ADDITIVE:
  Base win: 50.00
  Combined multiplier: 4 + 3 + 2 - 2 = 7x  (subtract overlap)
  Final: 50.00 × 7 = 350.00

DECISION: Use MULTIPLICATIVE (matches industry standard: NetEnt, Pragmatic, BTG).
Each multiplier source is independent and multiplies the running total.
```

### 8.3 Conflict Resolution

| Conflict | Resolution |
|----------|------------|
| Hold & Win + Respin | Mutually exclusive — dependency system prevents both enabled |
| Free Spins retrigger + Bonus trigger on same spin | Priority: Bonus queued, retrigger applied first (spins added) |
| Jackpot + any feature | Jackpot interrupts — current feature state preserved on stack |
| Cascade + Hold & Win trigger | Cascade completes first, then H&W triggers from cascade result |
| Multiple feature triggers on same spin | Priority queue: Jackpot > H&W > FS > Bonus > Respin > Cascade |

---

## 9. Feature Combination Scenarios

### Scenario 1: Base Game Only (Core Blocks Only)

**Config:** game_core + grid (5×3) + symbol_set
**Flow:**
```
IDLE → [SPIN] → BASE_GAME
  → Reels spin (REEL_SPIN_LOOP)
  → Reels stop sequentially (REEL_STOP_0..4)
  → Win evaluation (WIN_EVAL)
  → If win: WIN_SYMBOL_HIGHLIGHT → WIN_LINE_SHOW → ROLLUP → WIN_COMPLETE
  → If no win: back to IDLE
```
**States:** IDLE, BASE_GAME
**UI Components:** None (just base grid)

### Scenario 2: Free Spins + Cascades

**Config:** Core + free_spins (scatter trigger, 10 spins, progressive 2x→10x) + cascades (anyWin, progressive multiplier)
**Flow:**
```
BASE_GAME → spin → 3 scatters land
  → ANTICIPATION (if enabled, reels 3-5 slow)
  → FS_TRIGGER → FS_INTRO_START → FS_ENTER
  → FREE_SPINS state (counter: 10, FS mult: 2x)
       Spin 1: Win! → CASCADE state (nested)
         → CASCADE_START (cascade mult: 1x)
         → Remove winners → Drop new → Re-evaluate
         → Win again! CASCADE_STEP (cascade mult: 2x)
         → Remove → Drop → Re-evaluate
         → No win → CASCADE_END
         → Total cascade win: 150 × 2x(cascade) × 2x(FS) = 600
         → Back to FREE_SPINS (counter: 9)
       Spin 5: 3 scatters again → RETRIGGER
         → FS_RETRIGGER → counter += 5 (now 14-5=9 left → 14 total)
         → FS mult: 2x → 3x (progressive)
       Spin 14: Last spin → FS_LAST_SPIN
         → FS_OUTRO → FS_EXIT → FS_TOTAL_WIN
         → Total: 4,500
         → Back to BASE_GAME
```

### Scenario 3: Hold & Win + Jackpots

**Config:** Core + hold_and_win (classic, 6 coins trigger, 3 respins) + jackpot (4 tiers)
**Flow:**
```
BASE_GAME → spin → 6 coin symbols land
  → HOLD_TRIGGER → HOLD_INTRO → HOLD_ENTER
  → HOLD_WIN state (coins: 6, respins: 3)
       Respin 1: 2 new coins land
         → HOLD_COIN_LAND × 2 → respins reset to 3
         → coins: 8, respins: 3
       Respin 2: 1 new coin (MINI jackpot symbol!)
         → HOLD_COIN_LAND → HOLD_JACKPOT_MINI
         → coins: 9, respins: 3
       Respin 3: no new coins → respins: 2
       Respin 4: no new coins → respins: 1
       Respin 5: no new coins → respins: 0
         → HOLD_COLLECT_START → coin-by-coin collection
         → HOLD_COIN_COLLECT × 9 (sequential with delay)
         → HOLD_COLLECT_END → HOLD_TOTAL_WIN
         → Back to BASE_GAME
  Special: If ALL 15 positions filled:
    → HOLD_GRID_FULL → HOLD_GRAND_PRIZE
    → JACKPOT_REVEAL_GRAND → celebration sequence
```

### Scenario 4: Full Feature Stack (Maximum Complexity)

**Config:** Core + free_spins + cascades + hold_and_win + jackpot + multiplier (global progressive) + collector + gambling + wild_features (expanding, sticky) + anticipation + win_presentation + music_states + transitions

**Flow (complex chain):**
```
BASE_GAME → spin → 3 scatters + expanding wild on reel 3
  → WILD_EXPAND (reel 3 fills with wilds)
  → ANTICIPATION_ON (scatter on reels 1, 3 — waiting for more)
  → Reel 4: scatter! → ANTICIPATION_TENSION_R4_L3
  → Reel 5: no scatter → ANTICIPATION_FAIL
  → Win evaluation: 3 scatters → FS trigger, wild in winning combo
  → Feature queue: [FREE_SPINS(priority:80)]
  → Transition: BASE_GAME → FREE_SPINS
  → CONTEXT_BASE_TO_FS → MUSIC_CROSSFADE_BASE_TO_FS
  → FS_ENTER (counter: 15 for 3 scatters, FS mult: 1x, global mult: 1x)

  FREE_SPINS:
    Spin 1: Win with cascade trigger
      → CASCADE (nested in FS)
        → Cascade 1: win (cascade mult: 1x)
        → Cascade 2: win (cascade mult: 2x) + collector symbol
          → COLLECT_SYMBOL → COLLECT_FLY_START → COLLECT_METER_UPDATE
        → Cascade 3: no win
        → CASCADE_END, total: 200 × 2x(cascade) × 1x(FS) = 400
        → Global multiplier: 1x → 2x (cascade linked)

    Spin 4: Sticky wild lands → WILD_STICK_APPLY (persists)
    Spin 5: 6 coins land → H&W trigger!
      → FREE_SPINS paused (stack: [BASE→FS→H&W])
      → HOLD_WIN (nested in FS)
        → 3 respins, coins collecting
        → Grid full! → HOLD_GRAND_PRIZE
        → JACKPOT_TRIGGER → JACKPOT_REVEAL_GRAND
        → H&W total: 1000x bet
        → Apply FS multiplier (3x by now): 3000x
        → Apply global multiplier (2x): 6000x
        → Back to FREE_SPINS (stack: [BASE→FS])

    Spin 12: Collector meter full!
      → COLLECT_METER_FULL → COLLECT_FS_TRIGGER
      → Retrigger: +10 spins (now 13 remaining)

    Spin 25 (last): FS_LAST_SPIN
      → FS_OUTRO → FS_EXIT → FS_TOTAL_WIN: 12,500x
      → Win tier: ULTRA WIN (> 100x threshold)
      → BIG_WIN_INTRO → BIG_WIN_LOOP → BIG_WIN_COINS → BIG_WIN_END
      → GAMBLE_OFFER
        → Player gambles: GAMBLE_ENTER
          → Round 1: RED selected → card flip → RED! Won!
            → GAMBLE_WIN_DOUBLE: 25,000x
          → Round 2: Player collects
            → GAMBLE_COLLECT → GAMBLE_EXIT
      → Back to BASE_GAME
      → Music: MUSIC_FS_EXIT → MUSIC_CROSSFADE_FS_TO_BASE → MUSIC_BASE
```

### Scenario 5: Megaways + Cascades + Multiplier

**Config:** Core (payModel: megaways) + grid (6 reels, dynamic 2-7 rows) + cascades + multiplier (global, cascade-linked)
**Flow:**
```
Each spin: random rows per reel (2-7)
  Total ways: reel1_rows × reel2_rows × ... × reel6_rows
  Example: 7×5×6×7×4×3 = 17,640 ways

  Win on spin → CASCADE
    → Remove ALL winning symbols (potentially hundreds)
    → Drop new (random row counts can change!)
    → Global multiplier: +1 per cascade
    → Cascade 1: 1x, Cascade 2: 2x, ..., Cascade 15: 15x
    → Each cascade can produce massive wins on 100K+ ways
    → No win → cascade end, multiplier resets (unless persists)
```

### Scenario 6: Bonus Game (Multi-Level Trail) + Jackpot

**Config:** Core + bonus_game (trail, 3 levels, dice movement) + jackpot (wheel trigger)
**Flow:**
```
BASE_GAME → 3 bonus symbols → BONUS_TRIGGER
  → BONUS_INTRO_START → BONUS_MUSIC_START
  → BONUS_GAME state (level 1, position 0)

  Level 1 (20 spaces):
    → Player rolls dice → BONUS_TRAIL_DICE_ROLL → result: 4
    → Move 4 spaces → BONUS_TRAIL_STEP × 4
    → Land on prize space → BONUS_TRAIL_PRIZE_SPACE
    → Prize: 50x
    → Continue rolling...
    → Reach end → BONUS_LEVEL_1_COMPLETE → BONUS_LEVEL_UP

  Level 2 (20 spaces, higher prizes):
    → Same flow, prizes 100x-500x
    → Land on JACKPOT space → BONUS_TRAIL_BONUS_SPACE
    → Jackpot wheel! → JACKPOT_WHEEL_SPIN → JACKPOT_WHEEL_STOP
    → Won MAJOR! → JACKPOT_REVEAL_MAJOR → celebration
    → Continue trail...

  Level 3 (20 spaces, 1000x+ prizes):
    → Reach end → BONUS_END
    → Total prize: 2,500x
    → BONUS_RETURN_TO_GAME → BASE_GAME
```

---

## 10. State Persistence & Serialization

### 10.1 Session State

The complete game state must be serializable for:
- Session save/load
- Undo/redo during testing
- Replay for determinism verification

```dart
class GameSessionState {
  final GameFlowState currentState;
  final List<GameFlowFrame> stateStack;
  final Map<String, FeatureState> activeFeatures;
  final FeatureQueue pendingFeatures;
  final SlotMachineConfig config;
  final List<List<String>> currentGrid;  // reel × row symbol IDs
  final double balance;
  final double totalWin;
  final int spinCount;
  final Map<String, dynamic> collectorMeters;
  final Map<String, double> jackpotPools;
  final List<WildPosition> activeWilds;  // sticky/walking positions

  Map<String, dynamic> toJson();
  factory GameSessionState.fromJson(Map<String, dynamic> json);
}
```

### 10.2 Configuration Persistence

```dart
class ModularSlotConfig {
  final SlotMachineConfig machineConfig;
  final Map<String, Map<String, dynamic>> blockOptions;  // blockId → options
  final List<String> enabledBlockIds;
  final String configVersion;
  final DateTime createdAt;

  Map<String, dynamic> toJson();
  factory ModularSlotConfig.fromJson(Map<String, dynamic> json);
}
```

---

## 11. Edge Cases & Error Recovery

### 11.1 Edge Cases

| Edge Case | Resolution |
|-----------|------------|
| Feature trigger during win presentation | Queue trigger, process after presentation completes |
| Multiple jackpots on same spin | Highest tier wins, others ignored |
| Free spins retrigger at max retriggers | Ignore retrigger, continue countdown |
| Hold & Win with 0 respins remaining | Feature exits, collect coins |
| Cascade infinite loop (always wins) | maxCascades enforced (default: 0 = unlimited, but 50 hard cap) |
| Gamble max win reached | Auto-collect, no more gamble rounds |
| Bonus game pick reveals "COLLECT" on first pick | Feature exits with accumulated prize (even if 0) |
| Grid full during cascade (no empty positions) | Cascade ends — can't drop new symbols |
| Collector meter full during free spins | Queue FS retrigger, apply after current FS completes |
| Wild walking off grid edge | Wild removed, WILD_WALK_EXIT stage fired |
| Negative balance during feature buy | Block purchase, show insufficient funds |
| Feature exit with 0 win | Skip gamble offer, return to base game directly |
| Simultaneous scatter + bonus + coin symbols | Priority queue resolves order: Jackpot > H&W > FS > Bonus |

### 11.2 Error Recovery

```dart
class GameFlowErrorRecovery {
  /// If FSM gets stuck (shouldn't happen but safety net)
  static const Duration maxFeatureDuration = Duration(minutes: 5);

  /// If cascade chain exceeds hard limit
  static const int maxCascadeHardCap = 50;

  /// If feature stack depth exceeds limit (nested features)
  static const int maxStackDepth = 5;

  /// Recovery actions
  void onStuck(GameFlowProvider flow) {
    // Log error state
    // Force exit current feature
    // Collect any accumulated wins
    // Return to BASE_GAME
    flow.resetToBaseGame();
  }

  void onStackOverflow(GameFlowProvider flow) {
    // Too many nested features
    // Complete innermost, work outward
    while (flow.featureDepth > 1) {
      flow.completeCurrentFeature();
    }
  }
}
```

---

## 12. Data Models

### 12.1 Spin Result

```dart
class SpinResult {
  final List<List<String>> grid;         // Final grid state after stop
  final List<WinLine> winLines;          // All winning combinations
  final double totalWin;                 // Sum of all line wins
  final int scatterCount;               // Scatter symbols landed
  final int bonusSymbolCount;           // Bonus symbols landed
  final int coinCount;                  // Coin symbols landed
  final int wildCount;                  // Wild symbols landed
  final bool hasWin;                    // Any winning combination
  final Map<String, List<GridPosition>> symbolPositions;  // symbol → positions
  final List<GridPosition> winningPositions;  // All positions in wins
  final WinTier winTier;                // Determined tier
  final Map<String, dynamic> customData; // Feature-specific data

  // Computed
  List<GridPosition> get scatterPositions;
  List<GridPosition> get coinPositions;
  List<GridPosition> get wildPositions;
}

class WinLine {
  final int lineIndex;
  final List<GridPosition> positions;
  final String symbolId;
  final int symbolCount;
  final double amount;
  final double multiplier;  // From wild multiplier if applicable
}

class GridPosition {
  final int reel;
  final int row;
}
```

### 12.2 Grid Modification (for Cascades)

```dart
class GridModification {
  final List<GridPosition> removedPositions;
  final RemovalStyle removalStyle;
  final FillStyle fillStyle;
  final int delayMs;
  final List<GridPosition>? newWildPositions;  // If wild generation enabled
}
```

### 12.3 Coin Position (for Hold & Win)

```dart
class CoinPosition {
  final int reel;
  final int row;
  final double value;        // Multiplier of bet
  final bool isLocked;
  final bool isSpecial;
  final CoinSpecialType? specialType;  // multiplier, collector, upgrade, wild
  final double? specialValue;
}

enum CoinSpecialType {
  multiplier,   // Multiplies total H&W win
  collector,    // Collects all visible coin values
  upgrade,      // Upgrades adjacent coins
  wild,         // Random value each respin
}
```

### 12.4 Bonus Items (for Bonus Game)

```dart
class BonusItem {
  final int index;
  final BonusItemType type;
  final double value;
  final bool isRevealed;
  final String? displayLabel;
}

enum BonusItemType {
  prize,        // Credit value
  multiplier,   // Multiply accumulated
  freeSpins,    // Award free spins
  collect,      // End bonus (popper)
  jackpot,      // Award jackpot tier
  upgrade,      // Upgrade other items
  extraPick,    // +1 pick
  empty,        // Nothing (for match game misses)
}
```

---

## 13. Implementation Phases

### Phase 1: L3 — Game Flow State Machine (~2,500 LOC)

| # | Task | LOC |
|---|------|-----|
| MSB-1 | `GameFlowState` enum + `FlowTransition` model | 150 |
| MSB-2 | `GameFlowStack` (push/pop/canNest) | 200 |
| MSB-3 | `FeatureQueue` (priority queue) | 150 |
| MSB-4 | `GameFlowProvider` (ChangeNotifier, FSM core) | 600 |
| MSB-5 | `configureFromBlocks()` — build transitions from enabled blocks | 400 |
| MSB-6 | `evaluateTriggers()` — scan spin result for feature triggers | 300 |
| MSB-7 | State transition animations + audio stage firing | 300 |
| MSB-8 | Error recovery (stuck detection, stack overflow, hard caps) | 200 |
| MSB-9 | Unit tests (state transitions, nesting, priority, queue) | 400 |

### Phase 2: L4 — Feature Executors (~4,200 LOC)

| # | Task | LOC |
|---|------|-----|
| MSB-10 | `FeatureExecutor` abstract class + `FeatureState` model | 250 |
| MSB-11 | `FeatureExecutorRegistry` (create/configure/lookup) | 200 |
| MSB-12 | `FreeSpinsExecutor` (trigger, enter, step, exit, retrigger, multiplier) | 450 |
| MSB-13 | `CascadeExecutor` (trigger, removal, fill, multiplier chain) | 400 |
| MSB-14 | `HoldAndWinExecutor` (coins, respins, jackpot, grid full) | 500 |
| MSB-15 | `BonusGameExecutor` (pick, wheel, trail, ladder, match, multi-level) | 600 |
| MSB-16 | `GambleExecutor` (card, coin, wheel, ladder, dice, history) | 350 |
| MSB-17 | `RespinExecutor` (lock, nudge, countdown, progression) | 300 |
| MSB-18 | `CollectorExecutor` (meters, milestones, fly-to, rewards) | 300 |
| MSB-19 | `MultiplierExecutor` (global, reel, symbol, random, stacking) | 300 |
| MSB-20 | `JackpotExecutor` (tiers, progressive, mystery, trigger) | 250 |
| MSB-21 | `WildFeatureExecutor` (expand, sticky, walking, stack, multiplier) | 300 |
| MSB-22 | `WinPipeline` (ordered multiplier application) | 200 |
| MSB-23 | Integration tests (feature chains, nesting, win pipeline) | 500 |

### Phase 3: L5 — Feature UI Components (~3,800 LOC)

| # | Task | LOC |
|---|------|-----|
| MSB-24 | `FeatureOverlay` base class + `FeatureOverlayRegistry` | 150 |
| MSB-25 | `FreeSpinsOverlay` (counter, multiplier, total, spin history) | 400 |
| MSB-26 | `HoldAndWinOverlay` (coin grid, respins, jackpot tickers) | 500 |
| MSB-27 | `CascadeOverlay` (removal/fill animations, multiplier badge, chain bar) | 350 |
| MSB-28 | `PickGameWidget` (hidden items, tap-to-reveal, prize display) | 300 |
| MSB-29 | `WheelGameWidget` (spinning wheel, pointer, segment highlight) | 350 |
| MSB-30 | `TrailGameWidget` (board path, dice, movement, prizes) | 350 |
| MSB-31 | `LadderGameWidget` (rungs, climb/fall, safe zones) | 300 |
| MSB-32 | `GambleOverlay` (card flip, coin toss, history, collect/gamble buttons) | 400 |
| MSB-33 | `CollectorMeterWidget` (meter bar, fly-to animation, milestones) | 250 |
| MSB-34 | `MultiplierBadgeWidget` (global/reel/symbol display, increase animation) | 200 |
| MSB-35 | `JackpotTickerWidget` (tier display, contribution animation, near trigger) | 250 |
| MSB-36 | `FeatureCapabilityChips` (armed feature indicators) | 100 |
| MSB-37 | Widget tests | 400 |

### Phase 4: L6 — Reactive Preview + Integration (~2,000 LOC)

| # | Task | LOC |
|---|------|-----|
| MSB-38 | `FeaturePreviewStream` (block toggle/option change → preview update) | 300 |
| MSB-39 | Split panel layout (Feature Builder + Live Preview side-by-side) | 250 |
| MSB-40 | Stage count badge + diff display (+/- stages on toggle) | 150 |
| MSB-41 | Real-time FeatureComposerProvider recomposition on change | 200 |
| MSB-42 | GameFlowProvider auto-reconfigure on block change | 200 |
| MSB-43 | SlotPreviewWidget integration (host overlays, FSM-driven flow) | 400 |
| MSB-44 | Feature Builder → Game Flow wiring (end-to-end) | 200 |
| MSB-45 | GetIt registration (GameFlowProvider, FeatureExecutorRegistry, etc.) | 100 |
| MSB-46 | Integration tests (full flow: builder → preview → spin → feature) | 400 |

### Phase Summary

| Phase | Tasks | LOC | Dependencies |
|-------|-------|-----|--------------|
| Phase 1: L3 FSM | MSB-1 → MSB-9 | ~2,500 | None |
| Phase 2: L4 Executors | MSB-10 → MSB-23 | ~4,200 | Phase 1 |
| Phase 3: L5 UI | MSB-24 → MSB-37 | ~3,800 | Phase 2 |
| Phase 4: L6 Reactive | MSB-38 → MSB-46 | ~2,000 | Phase 1+2+3 |
| **TOTAL** | **46 tasks** | **~12,500** | |

---

## Appendix A: Block Stage Count Summary

| Block | Min Stages | Max Stages | Depends On |
|-------|-----------|-----------|------------|
| game_core | 4 | 4 | — |
| grid | 6 | 11 | reelCount |
| symbol_set | 5 | 25+ | symbolCount, landMode |
| free_spins | 8 | 27 | options enabled |
| cascades | 8 | 28+ | options enabled |
| hold_and_win | 10 | 35+ | options, jackpot tiers |
| jackpot | 5 | 30+ | tiers, trigger mode |
| collector | 6 | 25+ | meters, milestones |
| gambling | 10 | 50+ | gamble type, options |
| multiplier | 4 | 20+ | mult types enabled |
| bonus_game | 8 | 40+ | bonus type, levels |
| wild_features | 2 | 20+ | wild types enabled |
| respin | 6 | 20+ | options enabled |
| win_presentation | 10 | 40+ | tier system, rollup |
| music_states | 6 | 40+ | contexts, layers |
| transitions | 8 | 60+ | context pairs enabled |
| anticipation | 4 | 25+ | levels, per-reel |

**Minimum (core only):** ~15 stages
**Typical (core + 3 features):** ~80-120 stages
**Maximum (all blocks, all options):** ~400+ stages

---

## Appendix B: Audio Stage → Middleware Event Mapping

Every ComposedStage maps to a middleware event that triggers audio:

```
ComposedStage.id → TriggerLayerProvider event → ALE hook → Audio asset playback

Example chain:
  "FS_ENTER" stage
    → GameFlowProvider fires "onFeatureEnter" event
    → TriggerLayerProvider matches hook "onFeatureEnter"
    → Finds audio asset assigned to FS_ENTER stage
    → ALE processes: bus routing, volume, pan, priority
    → Audio plays through rf-engine
```

---

*End of Specification*

*Total: 13 sections, 46 implementation tasks, ~12,500 LOC estimated*
*Coverage: ALL 17 blocks, ALL feature combinations, ALL edge cases*
*Architecture: L3 (FSM) + L4 (Executors) + L5 (UI) + L6 (Reactive Preview)*

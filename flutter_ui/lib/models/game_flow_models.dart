/// Game Flow Models — State machine models for modular slot machine builder
///
/// Part of L3: Game Flow State Machine (FLUXFORGE_MODULAR_SLOT_BUILDER.md)
/// Defines game states, transitions, feature state, and execution results.
library;

import '../src/rust/native_ffi.dart' show SlotLabSpinResult;

// ═══════════════════════════════════════════════════════════════════════════
// GAME FLOW STATE — All possible game phases
// ═══════════════════════════════════════════════════════════════════════════

enum GameFlowState {
  /// Waiting for user action (no spin in progress)
  idle('Idle'),

  /// Base game spin: SPIN → STOP → EVALUATE → PRESENT
  baseGame('Base Game'),

  /// Cascade/tumble chain: remove → drop → re-evaluate
  cascading('Cascading'),

  /// Free spins mode with counter + optional multiplier
  freeSpins('Free Spins'),

  /// Hold & Win / Cash on Reels: lock coins, respin
  holdAndWin('Hold & Win'),

  /// Bonus game: pick, wheel, trail, ladder, match
  bonusGame('Bonus Game'),

  /// Gamble/double-up: risk current win
  gamble('Gamble'),

  /// Respin: re-spin specific reels
  respin('Respin'),

  /// Jackpot celebration sequence
  jackpotPresentation('Jackpot'),

  /// Win presentation: big win, mega win, etc.
  winPresentation('Win Presentation');

  final String displayName;
  const GameFlowState(this.displayName);

  /// Whether this state represents an active feature (not base game)
  bool get isFeature => this != idle && this != baseGame && this != winPresentation;

  /// Whether spins in this state are "free" (no bet deduction)
  bool get isFreeSpin => this == freeSpins || this == holdAndWin || this == respin;
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSITION TRIGGER — What causes a state change
// ═══════════════════════════════════════════════════════════════════════════

enum TransitionTrigger {
  // Symbol-based
  scatterCount,
  bonusSymbolCount,
  coinCount,

  // Win-based
  anyWin,
  noWin,
  winTierReached,

  // Feature-based
  featureBuy,
  retrigger,
  featureComplete,
  randomTrigger,

  // Player actions
  playerCollect,
  playerGamble,
  playerPick,

  // Automatic
  cascadeWin,
  cascadeNoWin,
  respinComplete,
  jackpotTriggered,
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW TRANSITION — A single state transition rule
// ═══════════════════════════════════════════════════════════════════════════

class FlowTransition {
  final GameFlowState source;
  final GameFlowState target;
  final TransitionTrigger trigger;
  final int priority;
  final bool interruptible;
  final String? audioStageId;

  /// Condition function — returns true if transition should fire
  final bool Function(SpinContext context)? condition;

  const FlowTransition({
    required this.source,
    required this.target,
    required this.trigger,
    this.priority = 50,
    this.interruptible = false,
    this.audioStageId,
    this.condition,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SPIN CONTEXT — Data available for trigger evaluation
// ═══════════════════════════════════════════════════════════════════════════

class SpinContext {
  final SlotLabSpinResult result;
  final GameFlowState currentState;
  final Map<String, FeatureState> activeFeatures;
  final int scatterCount;
  final int bonusSymbolCount;
  final int coinCount;
  final int wildCount;

  const SpinContext({
    required this.result,
    required this.currentState,
    this.activeFeatures = const {},
    this.scatterCount = 0,
    this.bonusSymbolCount = 0,
    this.coinCount = 0,
    this.wildCount = 0,
  });

  /// Create from SpinResult with symbol counting
  factory SpinContext.fromResult(
    SlotLabSpinResult result,
    GameFlowState currentState, {
    Map<String, FeatureState> activeFeatures = const {},
    int scatterSymbolId = 12,
    int bonusSymbolId = 11,
    int coinSymbolId = 13,
    int wildSymbolId = 10,
  }) {
    int scatters = 0;
    int bonuses = 0;
    int coins = 0;
    int wilds = 0;

    for (final reel in result.grid) {
      for (final symbol in reel) {
        if (symbol == scatterSymbolId) scatters++;
        if (symbol == bonusSymbolId) bonuses++;
        if (symbol == coinSymbolId) coins++;
        if (symbol == wildSymbolId) wilds++;
      }
    }

    return SpinContext(
      result: result,
      currentState: currentState,
      activeFeatures: activeFeatures,
      scatterCount: scatters,
      bonusSymbolCount: bonuses,
      coinCount: coins,
      wildCount: wilds,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GAME FLOW STACK — Nested feature support (FS → H&W → back to FS)
// ═══════════════════════════════════════════════════════════════════════════

class GameFlowFrame {
  final GameFlowState state;
  final Map<String, dynamic> context;
  final DateTime enteredAt;
  final GameFlowState? parentState;

  const GameFlowFrame({
    required this.state,
    this.context = const {},
    required this.enteredAt,
    this.parentState,
  });
}

class GameFlowStack {
  final List<GameFlowFrame> _stack = [];

  GameFlowFrame get current => _stack.last;
  int get depth => _stack.length;
  bool get isEmpty => _stack.isEmpty;
  bool get isNotEmpty => _stack.isNotEmpty;
  List<GameFlowFrame> get frames => List.unmodifiable(_stack);

  void push(GameFlowFrame frame) {
    _stack.add(frame);
  }

  GameFlowFrame pop() {
    return _stack.removeLast();
  }

  void clear() {
    _stack.clear();
  }

  /// Check if a child state can nest inside current parent
  bool canNest(GameFlowState child, GameFlowState parent) {
    // Nesting rules based on spec
    switch (child) {
      case GameFlowState.cascading:
        // Cascade can nest inside: baseGame, freeSpins, respin
        return parent == GameFlowState.baseGame ||
            parent == GameFlowState.freeSpins ||
            parent == GameFlowState.respin;
      case GameFlowState.holdAndWin:
        // H&W can nest inside: freeSpins
        return parent == GameFlowState.freeSpins;
      case GameFlowState.gamble:
        // Gamble after any feature exit with win > 0
        return true;
      case GameFlowState.respin:
        // Respin can nest inside: freeSpins
        return parent == GameFlowState.freeSpins;
      case GameFlowState.bonusGame:
        // Bonus can nest inside: freeSpins
        return parent == GameFlowState.freeSpins;
      case GameFlowState.jackpotPresentation:
        // Jackpot can trigger from any state
        return true;
      default:
        return false;
    }
  }

  /// Maximum nesting depth (safety)
  static const int maxDepth = 5;
}

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE QUEUE — Priority queue for simultaneous triggers
// ═══════════════════════════════════════════════════════════════════════════

class PendingFeature implements Comparable<PendingFeature> {
  final GameFlowState targetState;
  final Map<String, dynamic> triggerContext;
  final int priority;
  final String sourceBlockId;

  const PendingFeature({
    required this.targetState,
    this.triggerContext = const {},
    required this.priority,
    required this.sourceBlockId,
  });

  @override
  int compareTo(PendingFeature other) => other.priority.compareTo(priority);
}

class FeatureQueue {
  final List<PendingFeature> _queue = [];

  void enqueue(PendingFeature feature) {
    _queue.add(feature);
    _queue.sort();
  }

  PendingFeature? dequeue() {
    if (_queue.isEmpty) return null;
    return _queue.removeAt(0);
  }

  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  int get length => _queue.length;

  void clear() {
    _queue.clear();
  }

  List<PendingFeature> get pending => List.unmodifiable(_queue);
}

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE STATE — Runtime state for an active feature
// ═══════════════════════════════════════════════════════════════════════════

class FeatureState {
  final String featureId;
  final int spinsRemaining;
  final int spinsCompleted;
  final int totalSpins;
  final double currentMultiplier;
  final double maxMultiplier;
  final int cascadeDepth;
  final int respinsRemaining;
  final double accumulatedWin;

  // Hold & Win
  final List<CoinPosition> lockedCoins;
  final int gridPositionsFilled;
  final int gridPositionsTotal;

  // Bonus Game
  final int currentLevel;
  final int totalLevels;
  final int picksRemaining;
  final double accumulatedPrize;

  // Gamble
  final double currentStake;
  final int roundsPlayed;
  final int maxRounds;

  // Collector
  final Map<String, int> meterValues;
  final Map<String, int> meterTargets;

  // Generic custom data
  final Map<String, dynamic> customData;

  const FeatureState({
    required this.featureId,
    this.spinsRemaining = 0,
    this.spinsCompleted = 0,
    this.totalSpins = 0,
    this.currentMultiplier = 1.0,
    this.maxMultiplier = 1.0,
    this.cascadeDepth = 0,
    this.respinsRemaining = 0,
    this.accumulatedWin = 0.0,
    this.lockedCoins = const [],
    this.gridPositionsFilled = 0,
    this.gridPositionsTotal = 0,
    this.currentLevel = 0,
    this.totalLevels = 0,
    this.picksRemaining = 0,
    this.accumulatedPrize = 0.0,
    this.currentStake = 0.0,
    this.roundsPlayed = 0,
    this.maxRounds = 0,
    this.meterValues = const {},
    this.meterTargets = const {},
    this.customData = const {},
  });

  bool get isComplete {
    switch (featureId) {
      case 'free_spins':
        return spinsRemaining <= 0;
      case 'cascades':
        return false; // Cascade checks via shouldContinue
      case 'hold_and_win':
        return respinsRemaining <= 0 || gridPositionsFilled >= gridPositionsTotal;
      case 'bonus_game':
        return picksRemaining <= 0 && currentLevel >= totalLevels;
      case 'gamble':
        return currentStake <= 0 || roundsPlayed >= maxRounds;
      case 'respin':
        return respinsRemaining <= 0;
      default:
        return false;
    }
  }

  double get progress {
    if (totalSpins > 0) return spinsCompleted / totalSpins;
    if (gridPositionsTotal > 0) return gridPositionsFilled / gridPositionsTotal;
    if (totalLevels > 0) return currentLevel / totalLevels;
    return 0.0;
  }

  FeatureState copyWith({
    String? featureId,
    int? spinsRemaining,
    int? spinsCompleted,
    int? totalSpins,
    double? currentMultiplier,
    double? maxMultiplier,
    int? cascadeDepth,
    int? respinsRemaining,
    double? accumulatedWin,
    List<CoinPosition>? lockedCoins,
    int? gridPositionsFilled,
    int? gridPositionsTotal,
    int? currentLevel,
    int? totalLevels,
    int? picksRemaining,
    double? accumulatedPrize,
    double? currentStake,
    int? roundsPlayed,
    int? maxRounds,
    Map<String, int>? meterValues,
    Map<String, int>? meterTargets,
    Map<String, dynamic>? customData,
  }) {
    return FeatureState(
      featureId: featureId ?? this.featureId,
      spinsRemaining: spinsRemaining ?? this.spinsRemaining,
      spinsCompleted: spinsCompleted ?? this.spinsCompleted,
      totalSpins: totalSpins ?? this.totalSpins,
      currentMultiplier: currentMultiplier ?? this.currentMultiplier,
      maxMultiplier: maxMultiplier ?? this.maxMultiplier,
      cascadeDepth: cascadeDepth ?? this.cascadeDepth,
      respinsRemaining: respinsRemaining ?? this.respinsRemaining,
      accumulatedWin: accumulatedWin ?? this.accumulatedWin,
      lockedCoins: lockedCoins ?? this.lockedCoins,
      gridPositionsFilled: gridPositionsFilled ?? this.gridPositionsFilled,
      gridPositionsTotal: gridPositionsTotal ?? this.gridPositionsTotal,
      currentLevel: currentLevel ?? this.currentLevel,
      totalLevels: totalLevels ?? this.totalLevels,
      picksRemaining: picksRemaining ?? this.picksRemaining,
      accumulatedPrize: accumulatedPrize ?? this.accumulatedPrize,
      currentStake: currentStake ?? this.currentStake,
      roundsPlayed: roundsPlayed ?? this.roundsPlayed,
      maxRounds: maxRounds ?? this.maxRounds,
      meterValues: meterValues ?? this.meterValues,
      meterTargets: meterTargets ?? this.meterTargets,
      customData: customData ?? this.customData,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COIN POSITION — Hold & Win locked coin data
// ═══════════════════════════════════════════════════════════════════════════

class CoinPosition {
  final int reel;
  final int row;
  final double value;
  final bool isLocked;
  final CoinSpecialType? specialType;
  final double? specialValue;

  const CoinPosition({
    required this.reel,
    required this.row,
    required this.value,
    this.isLocked = true,
    this.specialType,
    this.specialValue,
  });

  String get positionKey => '$reel,$row';
}

enum CoinSpecialType {
  multiplier,
  collector,
  upgrade,
  wild,
}

// ═══════════════════════════════════════════════════════════════════════════
// BONUS ITEM — Bonus game item data
// ═══════════════════════════════════════════════════════════════════════════

class BonusItem {
  final int index;
  final BonusItemType type;
  final double value;
  final bool isRevealed;
  final String? displayLabel;

  const BonusItem({
    required this.index,
    required this.type,
    required this.value,
    this.isRevealed = false,
    this.displayLabel,
  });

  BonusItem reveal() => BonusItem(
        index: index,
        type: type,
        value: value,
        isRevealed: true,
        displayLabel: displayLabel,
      );
}

enum BonusItemType {
  prize,
  multiplier,
  freeSpins,
  collect,
  jackpot,
  upgrade,
  extraPick,
  empty,
}

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE STEP RESULT — Result of one step within a feature
// ═══════════════════════════════════════════════════════════════════════════

class FeatureStepResult {
  final FeatureState updatedState;
  final bool shouldContinue;
  final List<String> audioStages;
  final GridModification? gridModification;

  const FeatureStepResult({
    required this.updatedState,
    required this.shouldContinue,
    this.audioStages = const [],
    this.gridModification,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE EXIT RESULT — Result of exiting a feature
// ═══════════════════════════════════════════════════════════════════════════

class FeatureExitResult {
  final double totalWin;
  final List<String> audioStages;
  final bool offerGamble;
  final PendingFeature? queuedFeature;

  const FeatureExitResult({
    required this.totalWin,
    this.audioStages = const [],
    this.offerGamble = false,
    this.queuedFeature,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// GRID MODIFICATION — Cascade symbol removal and fill
// ═══════════════════════════════════════════════════════════════════════════

class GridModification {
  final Set<String> removedPositions;
  final String removalStyle;
  final String fillStyle;
  final int delayMs;

  const GridModification({
    required this.removedPositions,
    this.removalStyle = 'explode',
    this.fillStyle = 'dropFromTop',
    this.delayMs = 300,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// TRIGGER CONTEXT — Data passed when entering a feature
// ═══════════════════════════════════════════════════════════════════════════

class TriggerContext {
  final int? scatterCount;
  final int? coinCount;
  final double? winAmount;
  final List<CoinPosition>? triggeringCoins;
  final Map<String, dynamic> extra;

  const TriggerContext({
    this.scatterCount,
    this.coinCount,
    this.winAmount,
    this.triggeringCoins,
    this.extra = const {},
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// WIN RESULT — Modified win after feature multiplier pipeline
// ═══════════════════════════════════════════════════════════════════════════

class ModifiedWinResult {
  final double originalAmount;
  final double finalAmount;
  final double appliedMultiplier;
  final List<String> multiplierSources;

  const ModifiedWinResult({
    required this.originalAmount,
    required this.finalAmount,
    this.appliedMultiplier = 1.0,
    this.multiplierSources = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SCENE TRANSITION — Visual transition between game phases
// ═══════════════════════════════════════════════════════════════════════════

/// Transition dismissal mode
enum TransitionDismissMode {
  /// Auto-dismiss after configured duration
  timed('Timed'),

  /// Wait for user tap/click
  clickToContinue('Click to Continue'),

  /// Timed with optional early dismiss on click
  timedOrClick('Timed + Click');

  final String label;
  const TransitionDismissMode(this.label);
}

/// Visual transition style
enum TransitionStyle {
  fade('Fade'),
  slideUp('Slide Up'),
  slideDown('Slide Down'),
  zoom('Zoom'),
  swoosh('Swoosh');

  final String label;
  const TransitionStyle(this.label);
}

/// Configuration for a scene transition (e.g., Base → Free Spins)
class SceneTransitionConfig {
  /// Duration in milliseconds (used when mode is timed)
  final int durationMs;

  /// How the transition is dismissed
  final TransitionDismissMode dismissMode;

  /// Visual style
  final TransitionStyle style;

  /// Whether to show a plaque (e.g., "FREE SPINS WON!")
  final bool showPlaque;

  /// Plaque text override (null = auto-generated from feature name)
  final String? plaqueText;

  /// Whether to show win amount on exit plaque
  final bool showWinOnExit;

  /// Audio stage to fire when transition starts
  final String? audioStage;

  const SceneTransitionConfig({
    this.durationMs = 3000,
    this.dismissMode = TransitionDismissMode.timedOrClick,
    this.style = TransitionStyle.fade,
    this.showPlaque = true,
    this.plaqueText,
    this.showWinOnExit = true,
    this.audioStage,
  });

  SceneTransitionConfig copyWith({
    int? durationMs,
    TransitionDismissMode? dismissMode,
    TransitionStyle? style,
    bool? showPlaque,
    String? plaqueText,
    bool? showWinOnExit,
    String? audioStage,
  }) {
    return SceneTransitionConfig(
      durationMs: durationMs ?? this.durationMs,
      dismissMode: dismissMode ?? this.dismissMode,
      style: style ?? this.style,
      showPlaque: showPlaque ?? this.showPlaque,
      plaqueText: plaqueText ?? this.plaqueText,
      showWinOnExit: showWinOnExit ?? this.showWinOnExit,
      audioStage: audioStage ?? this.audioStage,
    );
  }
}

/// Active transition state (runtime — what's currently showing)
enum TransitionPhase {
  /// No transition active
  none,

  /// Entering a feature (Base → Feature intro)
  entering,

  /// Exiting a feature (Feature outro → Base)
  exiting,
}

/// Runtime state for an active transition
class ActiveTransition {
  final TransitionPhase phase;
  final GameFlowState fromState;
  final GameFlowState toState;
  final SceneTransitionConfig config;
  final double totalWin;
  final DateTime startedAt;

  const ActiveTransition({
    required this.phase,
    required this.fromState,
    required this.toState,
    required this.config,
    this.totalWin = 0,
    required this.startedAt,
  });

  String get plaqueText {
    if (config.plaqueText != null) return config.plaqueText!;
    if (phase == TransitionPhase.entering) {
      return '${toState.displayName.toUpperCase()}!';
    }
    return '${fromState.displayName.toUpperCase()} COMPLETE';
  }
}

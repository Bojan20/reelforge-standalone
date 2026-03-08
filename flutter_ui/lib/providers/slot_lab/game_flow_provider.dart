/// Game Flow Provider — FSM for modular slot machine game states
///
/// Part of L3: Game Flow State Machine (FLUXFORGE_MODULAR_SLOT_BUILDER.md)
///
/// Manages game state transitions (BASE_GAME → FREE_SPINS → CASCADING → etc),
/// nested feature support, feature queue, and integration with existing
/// SlotLabCoordinator/SlotEngineProvider/SlotStageProvider infrastructure.
///
/// This provider does NOT replace SlotLabCoordinator — it sits ON TOP as an
/// orchestration layer that tracks which game phase is active and drives
/// feature-specific behavior.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/game_flow_models.dart';
import '../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../../services/event_registry.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE EXECUTOR — Abstract interface for feature-specific logic
// ═══════════════════════════════════════════════════════════════════════════

abstract class FeatureExecutor {
  String get blockId;
  int get priority;

  void configure(Map<String, dynamic> options);

  bool shouldTrigger(SpinContext context);

  FeatureState enter(TriggerContext context);

  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState);

  FeatureExitResult exit(FeatureState finalState);

  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state);

  String? getCurrentAudioStage(FeatureState state);

  void dispose() {}
}

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE EXECUTOR REGISTRY
// ═══════════════════════════════════════════════════════════════════════════

class FeatureExecutorRegistry {
  final Map<String, FeatureExecutor> _executors = {};

  void register(String blockId, FeatureExecutor executor) {
    _executors[blockId] = executor;
  }

  void unregister(String blockId) {
    _executors.remove(blockId);
  }

  void clear() {
    for (final executor in _executors.values) {
      executor.dispose();
    }
    _executors.clear();
  }

  FeatureExecutor? getExecutor(String blockId) => _executors[blockId];

  List<FeatureExecutor> getTriggeredExecutors(SpinContext context) {
    return _executors.values
        .where((e) => e.shouldTrigger(context))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  List<FeatureExecutor> get all => List.unmodifiable(_executors.values.toList());

  bool get isEmpty => _executors.isEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════
// GAME FLOW PROVIDER — Central FSM
// ═══════════════════════════════════════════════════════════════════════════

class GameFlowProvider extends ChangeNotifier {
  // ─── State ───────────────────────────────────────────────────────────────
  GameFlowState _currentState = GameFlowState.idle;
  final GameFlowStack _stack = GameFlowStack();
  final FeatureQueue _featureQueue = FeatureQueue();
  final Map<String, FeatureState> _activeFeatures = {};
  final FeatureExecutorRegistry _executors = FeatureExecutorRegistry();
  double _totalWin = 0;
  ModifiedWinResult? _lastWinPipeline;

  // ─── Scene Transitions ─────────────────────────────────────────────────
  ActiveTransition? _activeTransition;
  bool _transitionsEnabled = true;
  final Map<String, SceneTransitionConfig> _transitionConfigs = {};

  /// Default transition config (used when no specific config exists)
  SceneTransitionConfig _defaultTransitionConfig = const SceneTransitionConfig();

  // ─── Transition Rules ────────────────────────────────────────────────────
  final List<FlowTransition> _transitions = [];

  // ─── Configuration ───────────────────────────────────────────────────────
  int _scatterSymbolId = 12;
  int _bonusSymbolId = 11;
  int _coinSymbolId = 13;
  int _wildSymbolId = 10;
  int _reelCount = 5;
  int _rowCount = 3;
  bool _gamblingEnabled = false;

  // ─── Callbacks ───────────────────────────────────────────────────────────
  /// Called when game state changes (for UI overlay updates)
  void Function(GameFlowState oldState, GameFlowState newState)? onStateChanged;

  /// Called when a feature's internal state updates (counter, multiplier, etc.)
  void Function(String featureId, FeatureState state)? onFeatureStateUpdated;

  /// Called when feature queue changes
  void Function(List<PendingFeature> pending)? onQueueChanged;

  /// Called to trigger audio stages
  void Function(String stageId)? onAudioStage;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  GameFlowState get currentState => _currentState;
  bool get isInFeature => _currentState.isFeature;
  bool get isIdle => _currentState == GameFlowState.idle;
  bool get isBaseGame => _currentState == GameFlowState.baseGame;
  int get featureDepth => _stack.depth;
  GameFlowState? get parentState =>
      _stack.isNotEmpty ? _stack.current.parentState : null;
  Map<String, FeatureState> get activeFeatures =>
      Map.unmodifiable(_activeFeatures);
  FeatureQueue get featureQueue => _featureQueue;
  FeatureExecutorRegistry get executors => _executors;
  bool get hasQueuedFeatures => _featureQueue.isNotEmpty;

  /// Get feature state for a specific feature
  FeatureState? getFeatureState(String featureId) =>
      _activeFeatures[featureId];

  /// Get the active free spins state (convenience)
  FeatureState? get freeSpinsState => _activeFeatures['free_spins'];

  /// Get the active cascade state (convenience)
  FeatureState? get cascadeState => _activeFeatures['cascades'];

  /// Get the active hold & win state (convenience)
  FeatureState? get holdAndWinState => _activeFeatures['hold_and_win'];

  /// Get the active gamble state (convenience)
  FeatureState? get gambleState => _activeFeatures['gamble'];

  /// Get the active bonus game state (convenience)
  FeatureState? get bonusGameState => _activeFeatures['bonus_game'];

  /// Get the active respin state (convenience)
  FeatureState? get respinState => _activeFeatures['respin'];

  /// Current total win amount
  double get totalWin => _totalWin;

  /// Active scene transition (null = no transition in progress)
  ActiveTransition? get activeTransition => _activeTransition;

  /// Whether a transition is currently active (blocks spins)
  bool get isInTransition => _activeTransition != null;

  /// Whether scene transitions are enabled
  bool get transitionsEnabled => _transitionsEnabled;

  /// Last win pipeline result (with multiplier sources)
  ModifiedWinResult? get lastWinPipeline => _lastWinPipeline;

  /// Get the active wild features state (convenience)
  FeatureState? get wildFeaturesState => _activeFeatures['wild_features'];

  /// Get the active multiplier state (convenience)
  FeatureState? get multiplierState => _activeFeatures['multiplier'];

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void configure({
    int? scatterSymbolId,
    int? bonusSymbolId,
    int? coinSymbolId,
    int? wildSymbolId,
    int? reelCount,
    int? rowCount,
    bool? gamblingEnabled,
  }) {
    if (scatterSymbolId != null) _scatterSymbolId = scatterSymbolId;
    if (bonusSymbolId != null) _bonusSymbolId = bonusSymbolId;
    if (coinSymbolId != null) _coinSymbolId = coinSymbolId;
    if (wildSymbolId != null) _wildSymbolId = wildSymbolId;
    if (reelCount != null) _reelCount = reelCount;
    if (rowCount != null) _rowCount = rowCount;
    if (gamblingEnabled != null) _gamblingEnabled = gamblingEnabled;
  }

  /// Register a feature executor
  void registerExecutor(FeatureExecutor executor) {
    _executors.register(executor.blockId, executor);
    _rebuildTransitions();
  }

  /// Unregister a feature executor
  void unregisterExecutor(String blockId) {
    _executors.unregister(blockId);
    _activeFeatures.remove(blockId);
    _rebuildTransitions();
  }

  /// Clear all executors and reset state
  void clearExecutors() {
    _executors.clear();
    _activeFeatures.clear();
    _transitions.clear();
    _featureQueue.clear();
    _stack.clear();
    _currentState = GameFlowState.idle;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSITION RULE BUILDING
  // ═══════════════════════════════════════════════════════════════════════════

  void _rebuildTransitions() {
    _transitions.clear();

    // Base transitions that always exist
    _transitions.add(FlowTransition(
      source: GameFlowState.idle,
      target: GameFlowState.baseGame,
      trigger: TransitionTrigger.anyWin,
      priority: 0,
    ));

    // Build feature-specific transitions from registered executors
    for (final executor in _executors.all) {
      final transitions = _transitionsForExecutor(executor);
      _transitions.addAll(transitions);
    }
  }

  List<FlowTransition> _transitionsForExecutor(FeatureExecutor executor) {
    final result = <FlowTransition>[];

    switch (executor.blockId) {
      case 'free_spins':
        result.add(FlowTransition(
          source: GameFlowState.baseGame,
          target: GameFlowState.freeSpins,
          trigger: TransitionTrigger.scatterCount,
          priority: 80,
          audioStageId: 'FS_HOLD_INTRO',
        ));
        result.add(FlowTransition(
          source: GameFlowState.freeSpins,
          target: GameFlowState.freeSpins,
          trigger: TransitionTrigger.retrigger,
          priority: 85,
          audioStageId: 'FS_RETRIGGER',
        ));

      case 'cascades':
        result.add(FlowTransition(
          source: GameFlowState.baseGame,
          target: GameFlowState.cascading,
          trigger: TransitionTrigger.cascadeWin,
          priority: 50,
          audioStageId: 'CASCADE_START',
        ));
        result.add(FlowTransition(
          source: GameFlowState.freeSpins,
          target: GameFlowState.cascading,
          trigger: TransitionTrigger.cascadeWin,
          priority: 50,
          audioStageId: 'CASCADE_START',
        ));
        result.add(FlowTransition(
          source: GameFlowState.cascading,
          target: GameFlowState.baseGame,
          trigger: TransitionTrigger.cascadeNoWin,
          priority: 50,
          audioStageId: 'CASCADE_END',
        ));

      case 'hold_and_win':
        result.add(FlowTransition(
          source: GameFlowState.baseGame,
          target: GameFlowState.holdAndWin,
          trigger: TransitionTrigger.coinCount,
          priority: 90,
          audioStageId: 'HOLD_TRIGGER',
        ));
        result.add(FlowTransition(
          source: GameFlowState.freeSpins,
          target: GameFlowState.holdAndWin,
          trigger: TransitionTrigger.coinCount,
          priority: 90,
          audioStageId: 'HOLD_TRIGGER',
        ));

      case 'bonus_game':
        result.add(FlowTransition(
          source: GameFlowState.baseGame,
          target: GameFlowState.bonusGame,
          trigger: TransitionTrigger.bonusSymbolCount,
          priority: 70,
          audioStageId: 'BONUS_TRIGGER',
        ));

      case 'gambling':
        result.add(FlowTransition(
          source: GameFlowState.baseGame,
          target: GameFlowState.gamble,
          trigger: TransitionTrigger.playerGamble,
          priority: 30,
          audioStageId: 'GAMBLE_ENTER',
        ));

      case 'respin':
        result.add(FlowTransition(
          source: GameFlowState.baseGame,
          target: GameFlowState.respin,
          trigger: TransitionTrigger.scatterCount,
          priority: 60,
          audioStageId: 'RESPIN_TRIGGER',
        ));

      case 'jackpot':
        result.add(FlowTransition(
          source: GameFlowState.baseGame,
          target: GameFlowState.jackpotPresentation,
          trigger: TransitionTrigger.jackpotTriggered,
          priority: 100,
          audioStageId: 'JACKPOT_TRIGGER',
        ));
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CORE FSM — State transitions
  // ═══════════════════════════════════════════════════════════════════════════

  /// Transition to a new state
  void _transitionTo(GameFlowState newState, {Map<String, dynamic>? context}) {
    if (_currentState == newState && newState != GameFlowState.freeSpins) return;

    final oldState = _currentState;

    // Push current state onto stack if entering a nested feature
    if (newState.isFeature && _currentState.isFeature && _currentState != newState) {
      if (_stack.depth < GameFlowStack.maxDepth) {
        _stack.push(GameFlowFrame(
          state: _currentState,
          context: context ?? {},
          enteredAt: DateTime.now(),
          parentState: _stack.isNotEmpty ? _stack.current.state : null,
        ));
      }
    }

    _currentState = newState;
    onStateChanged?.call(oldState, newState);
    notifyListeners();
  }

  /// Start a spin from base game (or current state if feature spin)
  void onSpinStart() {
    if (_currentState == GameFlowState.idle) {
      _transitionTo(GameFlowState.baseGame);
    }
  }

  /// Process spin result — evaluate triggers and manage state
  void onSpinComplete(SlotLabSpinResult result) {
    final context = SpinContext.fromResult(
      result,
      _currentState,
      activeFeatures: _activeFeatures,
      scatterSymbolId: _scatterSymbolId,
      bonusSymbolId: _bonusSymbolId,
      coinSymbolId: _coinSymbolId,
      wildSymbolId: _wildSymbolId,
    );

    // Step 1: If in a feature, step the feature executor
    if (_currentState.isFeature) {
      _stepCurrentFeature(result);
    }

    // Step 2: Evaluate triggers for new features
    _evaluateTriggers(context);
  }

  /// Evaluate all registered executors for trigger conditions
  void _evaluateTriggers(SpinContext context) {
    final triggered = _executors.getTriggeredExecutors(context);

    if (triggered.isEmpty) {
      // No features triggered
      if (_currentState == GameFlowState.cascading) {
        // Cascade ended — no more wins
        _exitCurrentFeature();
      }
      return;
    }

    // Enqueue all triggered features by priority
    for (final executor in triggered) {
      final targetState = _stateForBlockId(executor.blockId);
      if (targetState == null) continue;

      // Don't re-trigger a feature that's already active
      if (_activeFeatures.containsKey(executor.blockId) &&
          executor.blockId != 'cascades') {
        continue;
      }

      _featureQueue.enqueue(PendingFeature(
        targetState: targetState,
        priority: executor.priority,
        sourceBlockId: executor.blockId,
        triggerContext: {
          'scatterCount': context.scatterCount,
          'coinCount': context.coinCount,
          'winAmount': context.result.totalWin,
        },
      ));
    }

    onQueueChanged?.call(_featureQueue.pending);

    // Process highest priority feature
    _processNextQueuedFeature();
  }

  /// Process the next feature from the queue
  void _processNextQueuedFeature() {
    if (_featureQueue.isEmpty) return;

    final pending = _featureQueue.dequeue();
    if (pending == null) return;

    final executor = _executors.getExecutor(pending.sourceBlockId);
    if (executor == null) return;

    // Enter the feature
    _enterFeature(executor, pending);
  }

  /// Enter a feature state (with optional scene transition)
  void _enterFeature(FeatureExecutor executor, PendingFeature pending) {
    final triggerCtx = TriggerContext(
      scatterCount: pending.triggerContext['scatterCount'] as int?,
      coinCount: pending.triggerContext['coinCount'] as int?,
      winAmount: pending.triggerContext['winAmount'] as double?,
    );

    final featureState = executor.enter(triggerCtx);
    _activeFeatures[executor.blockId] = featureState;

    // Fire entry audio
    final transition = _transitions
        .where((t) => t.target == pending.targetState)
        .firstOrNull;
    if (transition?.audioStageId != null) {
      _fireAudioStage(transition!.audioStageId!);
    }

    // Scene transition: show intro plaque before entering feature
    final fromState = _currentState;
    final toState = pending.targetState;

    if (_transitionsEnabled && toState.isFeature && toState != GameFlowState.cascading) {
      // Pass feature data to transition for dynamic plaque content
      final transitionData = <String, dynamic>{
        'totalSpins': featureState.totalSpins,
        'scatterCount': pending.triggerContext['scatterCount'],
        ...pending.triggerContext,
      };
      _startEnterTransition(fromState, toState, onComplete: () {
        _transitionTo(toState);
        onFeatureStateUpdated?.call(executor.blockId, featureState);
      }, featureData: transitionData);
    } else {
      _transitionTo(toState);
      onFeatureStateUpdated?.call(executor.blockId, featureState);
    }
  }

  /// Step the current feature with a spin result
  void _stepCurrentFeature(SlotLabSpinResult result) {
    final blockId = _blockIdForState(_currentState);
    if (blockId == null) return;

    final executor = _executors.getExecutor(blockId);
    if (executor == null) return;

    final currentFeatureState = _activeFeatures[blockId];
    if (currentFeatureState == null) return;

    final stepResult = executor.step(result, currentFeatureState);

    // Update state
    _activeFeatures[blockId] = stepResult.updatedState;

    // Fire audio stages
    for (final stage in stepResult.audioStages) {
      _fireAudioStage(stage);
    }

    onFeatureStateUpdated?.call(blockId, stepResult.updatedState);
    notifyListeners();

    // Check if feature should end
    if (!stepResult.shouldContinue) {
      _exitCurrentFeature();
    }
  }

  /// Exit the current feature and return to parent or process queue
  void _exitCurrentFeature() {
    final blockId = _blockIdForState(_currentState);
    if (blockId == null) {
      _transitionTo(GameFlowState.baseGame);
      return;
    }

    final executor = _executors.getExecutor(blockId);
    final featureState = _activeFeatures[blockId];
    double exitWin = 0;

    if (executor != null && featureState != null) {
      final exitResult = executor.exit(featureState);
      exitWin = exitResult.totalWin;

      // Fire exit audio
      for (final stage in exitResult.audioStages) {
        _fireAudioStage(stage);
      }

      // Queue gamble if applicable
      if (exitResult.offerGamble && _gamblingEnabled && exitResult.totalWin > 0) {
        _featureQueue.enqueue(PendingFeature(
          targetState: GameFlowState.gamble,
          priority: 30,
          sourceBlockId: 'gambling',
          triggerContext: {'winAmount': exitResult.totalWin},
        ));
      }

      // Queue any follow-up feature
      if (exitResult.queuedFeature != null) {
        _featureQueue.enqueue(exitResult.queuedFeature!);
      }
    }

    final exitingState = _currentState;

    // Determine return state
    GameFlowState returnState;
    if (_stack.isNotEmpty) {
      returnState = _stack.pop().state;
    } else {
      returnState = GameFlowState.idle;
    }

    // Remove active feature
    _activeFeatures.remove(blockId);

    // Scene transition: show exit plaque with total win before returning
    if (_transitionsEnabled && exitingState.isFeature &&
        exitingState != GameFlowState.cascading) {
      _startExitTransition(exitingState, returnState, exitWin, onComplete: () {
        if (_featureQueue.isNotEmpty) {
          _processNextQueuedFeature();
        } else {
          _currentState = returnState;
          onStateChanged?.call(exitingState, returnState);
          notifyListeners();
        }
      });
    } else {
      if (_featureQueue.isNotEmpty) {
        _processNextQueuedFeature();
      } else {
        _currentState = returnState;
        onStateChanged?.call(exitingState, returnState);
        notifyListeners();
      }
    }
  }

  /// Manually trigger a state change (feature buy, player action)
  void triggerManual(TransitionTrigger trigger, {Map<String, dynamic>? context}) {
    switch (trigger) {
      case TransitionTrigger.playerGamble:
        if (_currentState != GameFlowState.baseGame &&
            _currentState != GameFlowState.winPresentation) return;
        final executor = _executors.getExecutor('gambling');
        if (executor != null) {
          _enterFeature(executor, PendingFeature(
            targetState: GameFlowState.gamble,
            priority: 30,
            sourceBlockId: 'gambling',
            triggerContext: context ?? {},
          ));
        }

      case TransitionTrigger.playerCollect:
        if (_currentState == GameFlowState.gamble) {
          _exitCurrentFeature();
        }

      case TransitionTrigger.playerPick:
        // Bonus game pick — step the executor
        if (_currentState == GameFlowState.bonusGame) {
          final executor = _executors.getExecutor('bonus_game');
          final state = _activeFeatures['bonus_game'];
          if (executor != null && state != null) {
            final fakeResult = SlotLabSpinResult(
              spinId: 'pick_${DateTime.now().millisecondsSinceEpoch}',
              grid: const [],
              bet: 0,
              totalWin: 0,
              winRatio: 0,
              lineWins: const [],
              featureTriggered: false,
              nearMiss: false,
              isFreeSpins: false,
              multiplier: 1,
              cascadeCount: 0,
            );
            _stepCurrentFeature(fakeResult);
          }
        }

      case TransitionTrigger.featureBuy:
        final blockId = context?['blockId'] as String?;
        if (blockId != null) {
          final executor = _executors.getExecutor(blockId);
          if (executor != null) {
            final targetState = _stateForBlockId(blockId);
            if (targetState != null) {
              _enterFeature(executor, PendingFeature(
                targetState: targetState,
                priority: executor.priority,
                sourceBlockId: blockId,
                triggerContext: context ?? {},
              ));
            }
          }
        }

      case TransitionTrigger.featureComplete:
        _exitCurrentFeature();

      default:
        break;
    }
  }

  /// Force return to base game (error recovery)
  void resetToBaseGame() {
    _transitionDismissTimer?.cancel();
    _transitionDismissTimer = null;
    _activeTransition = null;
    _pendingTransitionComplete = null;
    _activeFeatures.clear();
    _featureQueue.clear();
    _stack.clear();
    _currentState = GameFlowState.idle;
    _totalWin = 0.0;
    _lastWinPipeline = null;
    notifyListeners();
  }

  /// Apply multiplier pipeline to a win amount
  ModifiedWinResult applyWinPipeline(double rawWin) {
    double current = rawWin;
    final sources = <String>[];

    for (final entry in _activeFeatures.entries) {
      final executor = _executors.getExecutor(entry.key);
      if (executor != null) {
        final modified = executor.modifyWin(current, entry.value);
        if (modified.appliedMultiplier != 1.0) {
          sources.add('${entry.key}: ${modified.appliedMultiplier}x');
        }
        current = modified.finalAmount;
      }
    }

    final result = ModifiedWinResult(
      originalAmount: rawWin,
      finalAmount: current,
      appliedMultiplier: rawWin > 0 ? current / rawWin : 1.0,
      multiplierSources: sources,
    );

    _totalWin = result.finalAmount;
    _lastWinPipeline = result;

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  GameFlowState? _stateForBlockId(String blockId) {
    return switch (blockId) {
      'free_spins' => GameFlowState.freeSpins,
      'cascades' => GameFlowState.cascading,
      'hold_and_win' => GameFlowState.holdAndWin,
      'bonus_game' => GameFlowState.bonusGame,
      'gambling' => GameFlowState.gamble,
      'respin' => GameFlowState.respin,
      'jackpot' => GameFlowState.jackpotPresentation,
      _ => null,
    };
  }

  String? _blockIdForState(GameFlowState state) {
    return switch (state) {
      GameFlowState.freeSpins => 'free_spins',
      GameFlowState.cascading => 'cascades',
      GameFlowState.holdAndWin => 'hold_and_win',
      GameFlowState.bonusGame => 'bonus_game',
      GameFlowState.gamble => 'gambling',
      GameFlowState.respin => 'respin',
      GameFlowState.jackpotPresentation => 'jackpot',
      _ => null,
    };
  }

  void _fireAudioStage(String stageId) {
    if (onAudioStage != null) {
      onAudioStage!(stageId);
    } else {
      // Fallback: use EventRegistry directly
      try {
        EventRegistry.instance.triggerStage(stageId);
      } catch (_) {
        // EventRegistry may not be initialized
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENE TRANSITIONS — Visual transitions between game phases
  // ═══════════════════════════════════════════════════════════════════════════

  /// Configure transition settings
  void configureTransitions({
    bool? enabled,
    SceneTransitionConfig? defaultConfig,
    Map<String, SceneTransitionConfig>? configs,
  }) {
    if (enabled != null) _transitionsEnabled = enabled;
    if (defaultConfig != null) _defaultTransitionConfig = defaultConfig;
    if (configs != null) {
      _transitionConfigs
        ..clear()
        ..addAll(configs);
    }
  }

  /// Set transition config for a specific scene pair (e.g., "baseGame_to_freeSpins")
  void setTransitionConfig(String key, SceneTransitionConfig config) {
    _transitionConfigs[key] = config;
    notifyListeners();
  }

  /// All per-scene transition configs (read-only)
  Map<String, SceneTransitionConfig> get transitionConfigs =>
      Map.unmodifiable(_transitionConfigs);

  /// Default transition config (used when no per-scene config exists)
  SceneTransitionConfig get defaultTransitionConfig => _defaultTransitionConfig;

  /// Set default transition config
  set defaultTransitionConfig(SceneTransitionConfig config) {
    _defaultTransitionConfig = config;
    notifyListeners();
  }

  /// Get transition config for a scene pair (public)
  SceneTransitionConfig getTransitionConfigForPair(GameFlowState from, GameFlowState to) {
    return _getTransitionConfig(from, to);
  }

  /// Get transition config for a scene pair
  SceneTransitionConfig _getTransitionConfig(GameFlowState from, GameFlowState to) {
    final key = '${from.name}_to_${to.name}';
    return _transitionConfigs[key] ?? _defaultTransitionConfig;
  }

  /// Start an entering transition (Base → Feature)
  void _startEnterTransition(GameFlowState from, GameFlowState to, {
    void Function()? onComplete,
    Map<String, dynamic> featureData = const {},
  }) {
    if (!_transitionsEnabled) {
      onComplete?.call();
      return;
    }

    final config = _getTransitionConfig(from, to);
    _activeTransition = ActiveTransition(
      phase: TransitionPhase.entering,
      fromState: from,
      toState: to,
      config: config,
      startedAt: DateTime.now(),
      featureData: featureData,
    );

    // Fire transition audio
    if (config.audioStage != null && config.audioStage!.isNotEmpty) {
      _fireAudioStage(config.audioStage!);
    }
    _fireAudioStage('CONTEXT_${_stateKey(from)}_TO_${_stateKey(to)}');

    _pendingTransitionComplete = onComplete;
    notifyListeners();

    // Auto-dismiss if timed (clickToContinue waits for user tap → dismissTransition)
    if (config.dismissMode == TransitionDismissMode.timed ||
        config.dismissMode == TransitionDismissMode.timedOrClick) {
      _transitionDismissTimer?.cancel();
      _transitionDismissTimer = Timer(Duration(milliseconds: config.durationMs), () {
        if (_activeTransition?.phase == TransitionPhase.entering &&
            _activeTransition?.toState == to) {
          dismissTransition();
        }
      });
    }
  }

  /// Start an exit transition (Feature → Base) with total win plaque
  void _startExitTransition(GameFlowState from, GameFlowState to, double totalWin, {
    void Function()? onComplete,
  }) {
    if (!_transitionsEnabled) {
      onComplete?.call();
      return;
    }

    final config = _getTransitionConfig(from, to);
    _activeTransition = ActiveTransition(
      phase: TransitionPhase.exiting,
      fromState: from,
      toState: to,
      config: config,
      totalWin: totalWin,
      startedAt: DateTime.now(),
    );

    // Fire transition audio
    if (config.audioStage != null && config.audioStage!.isNotEmpty) {
      _fireAudioStage(config.audioStage!);
    }
    _fireAudioStage('CONTEXT_${_stateKey(from)}_TO_${_stateKey(to)}');

    _pendingTransitionComplete = onComplete;
    notifyListeners();

    // Auto-dismiss if timed (clickToContinue waits for user tap → dismissTransition)
    if (config.dismissMode == TransitionDismissMode.timed ||
        config.dismissMode == TransitionDismissMode.timedOrClick) {
      _transitionDismissTimer?.cancel();
      _transitionDismissTimer = Timer(Duration(milliseconds: config.durationMs), () {
        if (_activeTransition?.phase == TransitionPhase.exiting &&
            _activeTransition?.fromState == from) {
          dismissTransition();
        }
      });
    }
  }

  /// Show a test/preview transition without changing game state
  void showTestTransition({
    GameFlowState from = GameFlowState.baseGame,
    GameFlowState to = GameFlowState.freeSpins,
    bool isExit = false,
    SceneTransitionConfig? configOverride,
  }) {
    final config = configOverride ?? _getTransitionConfig(from, to);
    _activeTransition = ActiveTransition(
      phase: isExit ? TransitionPhase.exiting : TransitionPhase.entering,
      fromState: from,
      toState: to,
      config: config,
      totalWin: isExit ? 1234.56 : 0,
      startedAt: DateTime.now(),
      featureData: {'scatterCount': 3, 'isTestPreview': true},
    );

    if (config.audioStage != null && config.audioStage!.isNotEmpty) {
      _fireAudioStage(config.audioStage!);
    }

    _pendingTransitionComplete = null;
    notifyListeners();

    // Always auto-dismiss test transitions
    _transitionDismissTimer?.cancel();
    _transitionDismissTimer = Timer(Duration(milliseconds: config.durationMs), () {
      if (_activeTransition != null) dismissTransition();
    });
  }

  /// Dismiss the active transition (click-to-continue or early dismiss)
  void dismissTransition() {
    if (_activeTransition == null) return;

    _transitionDismissTimer?.cancel();
    _transitionDismissTimer = null;
    final pending = _pendingTransitionComplete;
    _activeTransition = null;
    _pendingTransitionComplete = null;
    notifyListeners();

    // Execute pending completion callback
    pending?.call();
  }

  void Function()? _pendingTransitionComplete;
  Timer? _transitionDismissTimer;

  /// State name key for audio stage naming (e.g., "BASE", "FS", "BONUS")
  String _stateKey(GameFlowState state) {
    return switch (state) {
      GameFlowState.idle || GameFlowState.baseGame => 'BASE',
      GameFlowState.freeSpins => 'FS',
      GameFlowState.cascading => 'CASCADE',
      GameFlowState.holdAndWin => 'HOLDWIN',
      GameFlowState.bonusGame => 'BONUS',
      GameFlowState.gamble => 'GAMBLE',
      GameFlowState.respin => 'RESPIN',
      GameFlowState.jackpotPresentation => 'JACKPOT',
      GameFlowState.winPresentation => 'WIN',
    };
  }

  @override
  void dispose() {
    _transitionDismissTimer?.cancel();
    _transitionDismissTimer = null;
    _executors.clear();
    super.dispose();
  }
}

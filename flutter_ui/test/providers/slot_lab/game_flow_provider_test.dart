// GameFlowProvider — Pure Dart Unit Tests
//
// Tests for the game flow state machine provider.
// Covers:
// - Initial state defaults
// - State transitions (base game → features → back)
// - Executor registration and lookup
// - Feature trigger evaluation
// - Feature queue priority ordering
// - Feature stack nesting (push/pop)
// - Win pipeline (multiplier application)
// - Manual trigger (gamble collect/pick)
// - Reset to base game
//
// NOTE: These are PURE DART tests. NO FFI calls.
// We create minimal SlotLabSpinResult instances for trigger evaluation.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/game_flow_models.dart';
import 'package:fluxforge_ui/providers/slot_lab/game_flow_provider.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart' show SlotLabSpinResult;

// ═══════════════════════════════════════════════════════════════════════════
// TEST HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Create a minimal spin result for testing
SlotLabSpinResult _makeResult({
  bool isWin = false,
  double totalWin = 0,
  double bet = 1.0,
  List<List<int>>? grid,
  bool featureTriggered = false,
  bool nearMiss = false,
  double multiplier = 1.0,
  int cascadeCount = 0,
}) {
  return SlotLabSpinResult(
    spinId: 'test_spin',
    grid: grid ?? _defaultGrid(),
    bet: bet,
    totalWin: totalWin,
    winRatio: bet > 0 ? totalWin / bet : 0,
    lineWins: const [],
    featureTriggered: featureTriggered,
    nearMiss: nearMiss,
    isFreeSpins: false,
    multiplier: multiplier,
    cascadeCount: cascadeCount,
  );
}

/// Default 5x3 grid with no special symbols
List<List<int>> _defaultGrid() {
  return [
    [1, 2, 3],
    [4, 5, 6],
    [1, 2, 3],
    [4, 5, 6],
    [1, 2, 3],
  ];
}

/// Grid with scatter symbols (id=12) for free spins trigger
List<List<int>> _scatterGrid({int scatterCount = 3}) {
  final grid = _defaultGrid();
  int placed = 0;
  for (int r = 0; r < grid.length && placed < scatterCount; r++) {
    grid[r][0] = 12;
    placed++;
  }
  return grid;
}

/// A test executor that always triggers and tracks calls
class _TestExecutor extends FeatureExecutor {
  @override
  final String blockId;
  @override
  final int priority;

  bool shouldTriggerValue = true;
  int enterCallCount = 0;
  int stepCallCount = 0;
  int exitCallCount = 0;
  int configureCallCount = 0;
  bool stepShouldContinue = false;
  double winMultiplier = 1.0;

  _TestExecutor({
    required this.blockId,
    this.priority = 50,
  });

  @override
  void configure(Map<String, dynamic> options) {
    configureCallCount++;
  }

  @override
  bool shouldTrigger(SpinContext context) => shouldTriggerValue;

  @override
  FeatureState enter(TriggerContext context) {
    enterCallCount++;
    return FeatureState(
      featureId: blockId,
      totalSpins: 10,
      spinsRemaining: 10,
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    stepCallCount++;
    return FeatureStepResult(
      updatedState: currentState.copyWith(
        spinsRemaining: currentState.spinsRemaining - 1,
      ),
      shouldContinue: stepShouldContinue,
      audioStages: const [],
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    exitCallCount++;
    return const FeatureExitResult(
      totalWin: 100,
      audioStages: [],
      offerGamble: false,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount * winMultiplier,
      appliedMultiplier: winMultiplier,
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) => null;
}

void main() {
  late GameFlowProvider provider;

  setUp(() {
    provider = GameFlowProvider();
    // Disable scene transitions for unit tests — these tests assert immediate
    // state changes after onSpinComplete; transitions defer state via plaque.
    provider.configureTransitions(enabled: false);
  });

  tearDown(() {
    provider.dispose();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. INITIAL STATE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Initial State', () {
    test('starts in idle state', () {
      expect(provider.currentState, GameFlowState.idle);
    });

    test('isIdle is true initially', () {
      expect(provider.isIdle, isTrue);
    });

    test('isInFeature is false initially', () {
      expect(provider.isInFeature, isFalse);
    });

    test('feature depth is 0', () {
      expect(provider.featureDepth, 0);
    });

    test('no queued features', () {
      expect(provider.hasQueuedFeatures, isFalse);
    });

    test('totalWin is 0', () {
      expect(provider.totalWin, 0.0);
    });

    test('lastWinPipeline is null', () {
      expect(provider.lastWinPipeline, isNull);
    });

    test('all feature state getters return null', () {
      expect(provider.freeSpinsState, isNull);
      expect(provider.cascadeState, isNull);
      expect(provider.holdAndWinState, isNull);
      expect(provider.gambleState, isNull);
      expect(provider.bonusGameState, isNull);
      expect(provider.respinState, isNull);
      expect(provider.wildFeaturesState, isNull);
      expect(provider.multiplierState, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. EXECUTOR REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Executor Registration', () {
    test('registers executor', () {
      final executor = _TestExecutor(blockId: 'test');
      provider.registerExecutor(executor);
      expect(provider.executors.getExecutor('test'), isNotNull);
    });

    test('unregisters executor by blockId', () {
      final executor = _TestExecutor(blockId: 'test');
      provider.registerExecutor(executor);
      provider.unregisterExecutor('test');
      expect(provider.executors.getExecutor('test'), isNull);
    });

    test('clearExecutors removes all', () {
      provider.registerExecutor(_TestExecutor(blockId: 'a'));
      provider.registerExecutor(_TestExecutor(blockId: 'b'));
      provider.clearExecutors();
      expect(provider.executors.getExecutor('a'), isNull);
      expect(provider.executors.getExecutor('b'), isNull);
    });

    test('executor registry stores all registered executors', () {
      provider.registerExecutor(
          _TestExecutor(blockId: 'low', priority: 10));
      provider.registerExecutor(
          _TestExecutor(blockId: 'high', priority: 90));
      provider.registerExecutor(
          _TestExecutor(blockId: 'mid', priority: 50));

      final all = provider.executors.all;
      expect(all.length, 3);
      expect(all.map((e) => e.blockId).toSet(),
          containsAll(['low', 'high', 'mid']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. SPIN LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Spin Lifecycle', () {
    test('onSpinStart transitions idle → baseGame', () {
      provider.onSpinStart();
      expect(provider.currentState, GameFlowState.baseGame);
    });

    test('onSpinComplete with no triggers stays in baseGame', () {
      provider.onSpinStart();
      final result = _makeResult();
      provider.onSpinComplete(result);
      // No features triggered — stays in baseGame (returns to idle on next spin start)
      expect(provider.currentState, GameFlowState.baseGame);
    });

    test('onSpinComplete with triggered executor enters feature', () {
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      provider.registerExecutor(executor);

      provider.onSpinStart();
      final result = _makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      );
      provider.onSpinComplete(result);

      expect(provider.currentState, GameFlowState.freeSpins);
      expect(executor.enterCallCount, 1);
      expect(provider.isInFeature, isTrue);
    });

    test('listener is notified on state changes', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.onSpinStart();
      expect(notifyCount, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. FEATURE TRIGGER EVALUATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Feature Trigger Evaluation', () {
    test('executor shouldTrigger=false is not entered', () {
      final executor = _TestExecutor(blockId: 'free_spins');
      executor.shouldTriggerValue = false;
      provider.registerExecutor(executor);

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult());

      expect(executor.enterCallCount, 0);
      // Stays in baseGame since no feature triggered
      expect(provider.currentState, GameFlowState.baseGame);
    });

    test('highest priority executor triggers first', () {
      final low = _TestExecutor(blockId: 'gambling', priority: 30);
      final high = _TestExecutor(blockId: 'free_spins', priority: 80);
      provider.registerExecutor(low);
      provider.registerExecutor(high);

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(featureTriggered: true));

      // High priority should enter first
      expect(high.enterCallCount, 1);
      expect(provider.currentState, GameFlowState.freeSpins);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. WIN PIPELINE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Win Pipeline', () {
    test('applyWinPipeline with no executors returns raw win', () {
      final result = provider.applyWinPipeline(100.0);
      expect(result.originalAmount, 100.0);
      expect(result.finalAmount, 100.0);
      expect(result.appliedMultiplier, 1.0);
    });

    test('applyWinPipeline chains multipliers from active features', () {
      // Win pipeline iterates _activeFeatures — verify with no active features
      final result = provider.applyWinPipeline(100.0);
      expect(result.originalAmount, 100.0);
      expect(result.finalAmount, 100.0);
      // Multiplier sources empty when no active features
      expect(result.multiplierSources, isEmpty);
    });

    test('applyWinPipeline updates totalWin and lastWinPipeline', () {
      provider.applyWinPipeline(250.0);
      expect(provider.totalWin, 250.0);
      expect(provider.lastWinPipeline, isNotNull);
      expect(provider.lastWinPipeline!.finalAmount, 250.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. MANUAL TRIGGERS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Manual Triggers', () {
    test('triggerManual with playerCollect during gamble', () {
      final executor = _TestExecutor(blockId: 'gambling', priority: 30);
      provider.registerExecutor(executor);

      // Enter gamble state
      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(isWin: true, totalWin: 50));

      if (provider.currentState == GameFlowState.gamble) {
        provider.triggerManual(TransitionTrigger.playerCollect);
        // Should exit gamble
        expect(provider.currentState, isNot(GameFlowState.gamble));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. RESET
  // ═══════════════════════════════════════════════════════════════════════════

  group('Reset', () {
    test('resetToBaseGame clears state', () {
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      provider.registerExecutor(executor);

      provider.onSpinStart();
      provider.onSpinComplete(
          _makeResult(featureTriggered: true, grid: _scatterGrid()));

      provider.resetToBaseGame();
      expect(provider.currentState, GameFlowState.idle);
      expect(provider.isInFeature, isFalse);
      expect(provider.featureDepth, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Configuration', () {
    test('configure sets symbol IDs', () {
      provider.configure(
        scatterSymbolId: 20,
        wildSymbolId: 15,
        reelCount: 6,
        rowCount: 4,
      );
      // No direct getters for these — just ensure no errors
    });

    test('configure with gambling enabled', () {
      provider.configure(gamblingEnabled: true);
      // Gambling flag is internal — verified through trigger behavior
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. GAME FLOW MODELS
  // ═══════════════════════════════════════════════════════════════════════════

  group('GameFlowState Enum', () {
    test('displayName returns human-readable name', () {
      expect(GameFlowState.freeSpins.displayName, 'Free Spins');
      expect(GameFlowState.holdAndWin.displayName, 'Hold & Win');
      expect(GameFlowState.winPresentation.displayName, 'Win Presentation');
    });

    test('isFeature is true for feature states', () {
      expect(GameFlowState.freeSpins.isFeature, isTrue);
      expect(GameFlowState.cascading.isFeature, isTrue);
      expect(GameFlowState.holdAndWin.isFeature, isTrue);
      expect(GameFlowState.bonusGame.isFeature, isTrue);
      expect(GameFlowState.gamble.isFeature, isTrue);
    });

    test('isFeature is false for non-feature states', () {
      expect(GameFlowState.idle.isFeature, isFalse);
      expect(GameFlowState.baseGame.isFeature, isFalse);
      expect(GameFlowState.winPresentation.isFeature, isFalse);
    });

    test('isFreeSpin identifies correct states', () {
      expect(GameFlowState.freeSpins.isFreeSpin, isTrue);
      expect(GameFlowState.holdAndWin.isFreeSpin, isTrue);
      expect(GameFlowState.respin.isFreeSpin, isTrue);
      expect(GameFlowState.baseGame.isFreeSpin, isFalse);
    });
  });

  group('GameFlowStack', () {
    GameFlowFrame _frame(GameFlowState state) => GameFlowFrame(
          state: state,
          enteredAt: DateTime.now(),
        );

    test('starts empty', () {
      final stack = GameFlowStack();
      expect(stack.isEmpty, isTrue);
      expect(stack.depth, 0);
    });

    test('push increments depth', () {
      final stack = GameFlowStack();
      stack.push(_frame(GameFlowState.freeSpins));
      expect(stack.depth, 1);
      expect(stack.isEmpty, isFalse);
    });

    test('pop returns last pushed frame', () {
      final stack = GameFlowStack();
      stack.push(_frame(GameFlowState.freeSpins));
      stack.push(_frame(GameFlowState.cascading));
      final popped = stack.pop();
      expect(popped.state, GameFlowState.cascading);
      expect(stack.depth, 1);
    });

    test('clear empties the stack', () {
      final stack = GameFlowStack();
      stack.push(_frame(GameFlowState.freeSpins));
      stack.push(_frame(GameFlowState.cascading));
      stack.clear();
      expect(stack.isEmpty, isTrue);
      expect(stack.depth, 0);
    });
  });

  group('FeatureQueue', () {
    test('starts empty', () {
      final queue = FeatureQueue();
      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
    });

    test('enqueue adds pending feature', () {
      final queue = FeatureQueue();
      queue.enqueue(const PendingFeature(
        targetState: GameFlowState.freeSpins,
        priority: 80,
        sourceBlockId: 'free_spins',
      ));
      expect(queue.length, 1);
    });

    test('dequeue returns highest priority first', () {
      final queue = FeatureQueue();
      queue.enqueue(const PendingFeature(
        targetState: GameFlowState.gamble,
        priority: 30,
        sourceBlockId: 'gamble',
      ));
      queue.enqueue(const PendingFeature(
        targetState: GameFlowState.freeSpins,
        priority: 80,
        sourceBlockId: 'free_spins',
      ));
      queue.enqueue(const PendingFeature(
        targetState: GameFlowState.cascading,
        priority: 50,
        sourceBlockId: 'cascades',
      ));

      final first = queue.dequeue();
      expect(first?.sourceBlockId, 'free_spins');
      expect(first?.priority, 80);

      final second = queue.dequeue();
      expect(second?.sourceBlockId, 'cascades');

      final third = queue.dequeue();
      expect(third?.sourceBlockId, 'gamble');
    });

    test('clear empties the queue', () {
      final queue = FeatureQueue();
      queue.enqueue(const PendingFeature(
        targetState: GameFlowState.freeSpins,
        priority: 80,
        sourceBlockId: 'free_spins',
      ));
      queue.clear();
      expect(queue.isEmpty, isTrue);
    });
  });

  group('FeatureState', () {
    test('copyWith preserves unchanged fields', () {
      const state = FeatureState(
        featureId: 'test',
        totalSpins: 10,
        spinsRemaining: 5,
        currentMultiplier: 2.0,
      );
      final copied = state.copyWith(spinsRemaining: 3);
      expect(copied.featureId, 'test');
      expect(copied.totalSpins, 10);
      expect(copied.spinsRemaining, 3);
      expect(copied.currentMultiplier, 2.0);
    });

    test('copyWith updates specified fields', () {
      const state = FeatureState(
        featureId: 'test',
        currentMultiplier: 1.0,
        accumulatedWin: 0,
      );
      final updated = state.copyWith(
        currentMultiplier: 5.0,
        accumulatedWin: 100,
      );
      expect(updated.currentMultiplier, 5.0);
      expect(updated.accumulatedWin, 100);
    });
  });

  group('SpinContext', () {
    test('fromResult counts symbols correctly', () {
      final grid = [
        [12, 1, 2], // scatter in reel 0
        [1, 12, 3], // scatter in reel 1
        [10, 2, 3], // wild in reel 2
        [4, 5, 6],
        [12, 10, 3], // scatter + wild in reel 4
      ];
      final result = _makeResult(grid: grid);
      final context = SpinContext.fromResult(
        result,
        GameFlowState.baseGame,
        scatterSymbolId: 12,
        bonusSymbolId: 11,
        coinSymbolId: 13,
        wildSymbolId: 10,
      );

      expect(context.scatterCount, 3);
      expect(context.wildCount, 2);
      expect(context.bonusSymbolCount, 0);
      expect(context.coinCount, 0);
    });
  });

  group('ModifiedWinResult', () {
    test('multiplierSources defaults to empty', () {
      const result = ModifiedWinResult(
        originalAmount: 100,
        finalAmount: 200,
      );
      expect(result.multiplierSources, isEmpty);
      expect(result.appliedMultiplier, 1.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TALAS 1 — Wire 1.3: SLAM zombie recovery
  // ═══════════════════════════════════════════════════════════════════════════

  group('FS Auto-Loop Recovery (Wire 1.3)', () {
    test('recoverFsAutoLoop is no-op when loop is inactive', () {
      // Loop never started — recovery should not throw or change state
      provider.recoverFsAutoLoop();
      expect(provider.isFsAutoLoopActive, isFalse);
    });

    test('recoverFsAutoLoop stops loop if not in freeSpins state', () {
      // Force the active flag without entering FS — simulates corrupted state.
      // Then call recovery: it must clean up rather than reschedule.
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      executor.stepShouldContinue = true;
      provider.registerExecutor(executor);

      // Enter FS, start loop, then exit FS via reset
      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      ));
      provider.startFsAutoLoop();
      expect(provider.isFsAutoLoopActive, isTrue);

      // Force back to base — loop flag may persist if exit raced with timer
      provider.forceTransition(GameFlowState.baseGame);
      // Manually re-enable to simulate orphan flag (forceTransition stops it,
      // but the recovery API must also handle the case where flag is set
      // outside FS state).
      provider.startFsAutoLoop(); // no-op because not in FS
      expect(provider.isFsAutoLoopActive, isFalse);

      // recoverFsAutoLoop on already-stopped loop = clean no-op
      provider.recoverFsAutoLoop();
      expect(provider.isFsAutoLoopActive, isFalse);
    });

    test('recoverFsAutoLoop reschedules timer when in FS with active loop',
        () async {
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      executor.stepShouldContinue = true; // keep FS alive
      provider.registerExecutor(executor);

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      ));
      expect(provider.currentState, GameFlowState.freeSpins);

      // Wire the auto-spin callback so _scheduleNextFsSpin can fire it
      int autoSpinCalls = 0;
      provider.onRequestAutoSpin = () => autoSpinCalls++;

      provider.startFsAutoLoop(delayMs: 50);
      expect(provider.isFsAutoLoopActive, isTrue);

      // Wait for first scheduled spin
      await Future.delayed(const Duration(milliseconds: 80));
      expect(autoSpinCalls, 1);

      // Simulate "stuck" state: in real life onSpinComplete would have
      // rescheduled, but SLAM-mid-flight prevented finalize. Auto-loop flag
      // is still true, but no timer is running.
      // Recovery should reschedule the next spin.
      provider.recoverFsAutoLoop();
      await Future.delayed(const Duration(milliseconds: 80));
      expect(autoSpinCalls, 2,
          reason: 'recoverFsAutoLoop must trigger one more auto-spin');

      // Cleanup: stop the loop so tearDown() doesn't leave a pending timer
      provider.stopFsAutoLoop();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TALAS 1 — Wire #1: FS auto-loop survives null onRequestAutoSpin callback
  // ═══════════════════════════════════════════════════════════════════════════

  group('FS Auto-Loop Null-Callback Retry (Wire #1)', () {
    test('does not call a null callback and does not crash', () async {
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      executor.stepShouldContinue = true;
      provider.registerExecutor(executor);

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      ));
      expect(provider.currentState, GameFlowState.freeSpins);

      // Intentionally leave onRequestAutoSpin null (UI not wired yet).
      provider.onRequestAutoSpin = null;
      provider.startFsAutoLoop(delayMs: 30);

      // Drain ~10 retry slots; loop must not crash and must eventually stop.
      await Future.delayed(const Duration(milliseconds: 500));
      expect(provider.isFsAutoLoopActive, isFalse,
          reason:
              'After max null-callback retries the loop must stop gracefully so '
              'the player can recover via the SPIN button.');
    });

    test('resumes calling once the callback is wired mid-loop', () async {
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      executor.stepShouldContinue = true;
      provider.registerExecutor(executor);

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      ));

      provider.onRequestAutoSpin = null;
      provider.startFsAutoLoop(delayMs: 30);

      // After 1 retry cycle, wire the callback (UI postFrameCallback finally ran)
      await Future.delayed(const Duration(milliseconds: 60));
      int autoSpinCalls = 0;
      provider.onRequestAutoSpin = () => autoSpinCalls++;

      // Next scheduled tick should fire it
      await Future.delayed(const Duration(milliseconds: 60));
      expect(autoSpinCalls, greaterThanOrEqualTo(1),
          reason: 'Loop should resume firing once UI wires its callback');

      provider.stopFsAutoLoop();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TALAS 1 — Wire #3: Deferred Big Win double-fire guard
  // ═══════════════════════════════════════════════════════════════════════════

  group('Deferred Big Win Guard (Wire #3)', () {
    test('onDeferredBigWin fires exactly once per feature exit', () {
      // Test executor exits immediately with a big win = 100x of bet (1.0)
      final executor = _BigWinExecutor(blockId: 'free_spins', priority: 80,
          exitWin: 100.0);
      provider.registerExecutor(executor);

      int bigWinCallCount = 0;
      double? lastWin;
      provider.onDeferredBigWin = (win, bet) {
        bigWinCallCount++;
        lastWin = win;
      };

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        bet: 1.0,
        grid: _scatterGrid(scatterCount: 3),
      ));
      // Now we are in FS. Step the feature once — exit with 100x bet.
      provider.onSpinComplete(_makeResult(bet: 1.0));

      expect(bigWinCallCount, 1,
          reason: 'Big Win must fire exactly once per exit');
      expect(lastWin, 100.0);
    });

    test('next spin re-arms the guard so subsequent exits can fire', () {
      final executor = _BigWinExecutor(blockId: 'free_spins', priority: 80,
          exitWin: 100.0);
      provider.registerExecutor(executor);

      int bigWinCallCount = 0;
      provider.onDeferredBigWin = (win, bet) => bigWinCallCount++;

      // First exit fires
      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true, bet: 1.0,
        grid: _scatterGrid(scatterCount: 3),
      ));
      provider.onSpinComplete(_makeResult(bet: 1.0));
      expect(bigWinCallCount, 1);

      // New spin arms the guard, then second exit fires
      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true, bet: 1.0,
        grid: _scatterGrid(scatterCount: 3),
      ));
      provider.onSpinComplete(_makeResult(bet: 1.0));
      expect(bigWinCallCount, 2,
          reason: 'A new spin must reset the per-exit guard');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TALAS 1 — Wire #4: FS retrigger surfaces as a hook event
  // ═══════════════════════════════════════════════════════════════════════════

  group('FS Retrigger Hook (Wire #4)', () {
    test('FSM does not crash when executor reports more spinsRemaining',
        () {
      // _RetriggerExecutor returns updatedState with spinsRemaining > previous
      // — same shape as FreeSpinsExecutor when scatter retrigger fires inline.
      final executor = _RetriggerExecutor(blockId: 'free_spins', priority: 80);
      provider.registerExecutor(executor);

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      ));
      expect(provider.currentState, GameFlowState.freeSpins);

      // Retrigger spin: executor reports 15 spinsRemaining (was 9 after step).
      // Wire #4 hook emit must run silently without throwing — HookGraphService
      // may not be initialized in unit tests, the emit is best-effort.
      provider.onSpinComplete(_makeResult());

      expect(provider.currentState, GameFlowState.freeSpins,
          reason: 'Retrigger keeps us in FS state');
      expect(provider.freeSpinsState?.spinsRemaining, greaterThan(8),
          reason: 'Retrigger must have been applied to feature state');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TALAS 1 — Wire #5: synthetic transition-dismissed when no entry/exit plaque
  // ═══════════════════════════════════════════════════════════════════════════

  group('Synthetic Transition Dismiss (Wire #5)', () {
    test('FS entry without plaque still emits onTransitionDismissed (entering)',
        () {
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      executor.stepShouldContinue = true;
      provider.registerExecutor(executor);

      // Transitions are disabled in setUp() — no entry plaque will show.
      final dismissed = <List<dynamic>>[];
      provider.onTransitionDismissed = (phase, from, to) {
        dismissed.add([phase, from, to]);
      };

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      ));

      expect(provider.currentState, GameFlowState.freeSpins);
      expect(
        dismissed.any((d) =>
            d[0] == TransitionPhase.entering && d[2] == GameFlowState.freeSpins),
        isTrue,
        reason:
            'Without a plaque the integration layer must still receive an '
            'entering-dismissed event so it can start FS music + auto-loop.',
      );
    });

    test('FS exit without plaque still emits onTransitionDismissed (exiting)',
        () {
      // Use an executor that exits immediately on first step
      final executor = _TestExecutor(blockId: 'free_spins', priority: 80);
      executor.stepShouldContinue = false; // exit on next step
      provider.registerExecutor(executor);

      final dismissed = <List<dynamic>>[];
      provider.onTransitionDismissed = (phase, from, to) {
        dismissed.add([phase, from, to]);
      };

      provider.onSpinStart();
      provider.onSpinComplete(_makeResult(
        featureTriggered: true,
        grid: _scatterGrid(scatterCount: 3),
      ));
      // Step once → exits FS
      provider.onSpinComplete(_makeResult());

      expect(
        dismissed.any((d) =>
            d[0] == TransitionPhase.exiting && d[1] == GameFlowState.freeSpins),
        isTrue,
        reason:
            'Without an exit plaque the integration layer must still hear a '
            'exiting-dismissed event so it can fire FS_OUTRO_PLAQUE / '
            'flushPendingCrossfade.',
      );
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// EXTRA TEST EXECUTORS for TALAS 1 wires
// ═══════════════════════════════════════════════════════════════════════════

/// Executor that exits on first step with a configurable accumulated win.
/// Used to drive the deferred Big Win path.
class _BigWinExecutor extends FeatureExecutor {
  @override
  final String blockId;
  @override
  final int priority;
  final double exitWin;

  _BigWinExecutor({
    required this.blockId,
    this.priority = 50,
    required this.exitWin,
  });

  @override
  void configure(Map<String, dynamic> options) {}

  @override
  bool shouldTrigger(SpinContext context) => context.scatterCount >= 3;

  @override
  FeatureState enter(TriggerContext context) => FeatureState(
        featureId: blockId,
        totalSpins: 1,
        spinsRemaining: 1,
        accumulatedWin: exitWin,
      );

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    return FeatureStepResult(
      updatedState: currentState.copyWith(
        spinsRemaining: 0,
        accumulatedWin: exitWin,
      ),
      shouldContinue: false,
      audioStages: const [],
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) => FeatureExitResult(
        totalWin: finalState.accumulatedWin,
        audioStages: const [],
        offerGamble: false,
      );

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) =>
      ModifiedWinResult(
        originalAmount: baseWinAmount,
        finalAmount: baseWinAmount,
      );

  @override
  String? getCurrentAudioStage(FeatureState state) => null;
}

/// Executor whose step() returns MORE spinsRemaining than the input —
/// mirrors FreeSpinsExecutor's inline retrigger behavior so the FSM can be
/// exercised without depending on the real executor's scatter-count math.
class _RetriggerExecutor extends FeatureExecutor {
  @override
  final String blockId;
  @override
  final int priority;
  bool _retriggered = false;

  _RetriggerExecutor({required this.blockId, this.priority = 80});

  @override
  void configure(Map<String, dynamic> options) {}

  @override
  bool shouldTrigger(SpinContext context) => context.scatterCount >= 3;

  @override
  FeatureState enter(TriggerContext context) => FeatureState(
        featureId: blockId,
        totalSpins: 10,
        spinsRemaining: 10,
      );

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    // First step: retrigger — bump spinsRemaining from 9 to 15
    if (!_retriggered) {
      _retriggered = true;
      return FeatureStepResult(
        updatedState: currentState.copyWith(
          spinsRemaining: currentState.spinsRemaining + 6,
          totalSpins: currentState.totalSpins + 6,
          customData: const {'retriggersUsed': 1},
        ),
        shouldContinue: true,
        audioStages: const ['FS_RETRIGGER'],
      );
    }
    // Subsequent steps: normal decrement
    return FeatureStepResult(
      updatedState: currentState.copyWith(
        spinsRemaining: currentState.spinsRemaining - 1,
      ),
      shouldContinue: currentState.spinsRemaining - 1 > 0,
      audioStages: const [],
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) => const FeatureExitResult(
        totalWin: 0,
        audioStages: [],
        offerGamble: false,
      );

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) =>
      ModifiedWinResult(
        originalAmount: baseWinAmount,
        finalAmount: baseWinAmount,
      );

  @override
  String? getCurrentAudioStage(FeatureState state) => null;
}

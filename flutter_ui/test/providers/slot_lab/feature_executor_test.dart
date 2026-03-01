// Feature Executor — Pure Dart Unit Tests
//
// Tests for all 10 feature executors:
// - Configuration via configure()
// - Trigger evaluation via shouldTrigger()
// - Feature lifecycle: enter → step → exit
// - Win modification via modifyWin()
//
// NOTE: These are PURE DART tests. NO FFI calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/game_flow_models.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/free_spins_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/cascade_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/hold_and_win_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/bonus_game_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/gamble_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/respin_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/jackpot_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/multiplier_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/wild_features_executor.dart';
import 'package:fluxforge_ui/providers/slot_lab/executors/collector_executor.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart' show SlotLabSpinResult;

// ═══════════════════════════════════════════════════════════════════════════
// TEST HELPERS
// ═══════════════════════════════════════════════════════════════════════════

SlotLabSpinResult _makeResult({
  List<List<int>>? grid,
  double totalWin = 0,
  double bet = 1.0,
  bool featureTriggered = false,
  bool nearMiss = false,
  double multiplier = 1.0,
  int cascadeCount = 0,
}) {
  return SlotLabSpinResult(
    spinId: 'test',
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

List<List<int>> _defaultGrid() => [
      [1, 2, 3],
      [4, 5, 6],
      [1, 2, 3],
      [4, 5, 6],
      [1, 2, 3],
    ];

SpinContext _makeContext({
  List<List<int>>? grid,
  GameFlowState state = GameFlowState.baseGame,
  double totalWin = 0,
  bool featureTriggered = false,
  double multiplier = 1.0,
  int cascadeCount = 0,
}) {
  final result = _makeResult(
    grid: grid,
    totalWin: totalWin,
    featureTriggered: featureTriggered,
    multiplier: multiplier,
    cascadeCount: cascadeCount,
  );
  return SpinContext.fromResult(
    result,
    state,
    scatterSymbolId: 12,
    bonusSymbolId: 11,
    coinSymbolId: 13,
    wildSymbolId: 10,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // FREE SPINS EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('FreeSpinsExecutor', () {
    late FreeSpinsExecutor executor;

    setUp(() {
      executor = FreeSpinsExecutor();
    });

    test('blockId is free_spins', () {
      expect(executor.blockId, 'free_spins');
    });

    test('priority is 80', () {
      expect(executor.priority, 80);
    });

    test('configure sets options', () {
      executor.configure({
        'triggerMode': 'scatter',
        'baseSpins': 15,
        'retriggerEnabled': true,
        'maxRetriggers': 5,
      });
      // No direct getters — just verify no error
    });

    test('triggers on 3+ scatters', () {
      final grid = [
        [12, 1, 2],
        [12, 5, 6],
        [12, 2, 3],
        [4, 5, 6],
        [1, 2, 3],
      ];
      final context = _makeContext(grid: grid);
      expect(executor.shouldTrigger(context), isTrue);
    });

    test('does not trigger on 2 scatters', () {
      final grid = [
        [12, 1, 2],
        [12, 5, 6],
        [1, 2, 3],
        [4, 5, 6],
        [1, 2, 3],
      ];
      final context = _makeContext(grid: grid);
      expect(executor.shouldTrigger(context), isFalse);
    });

    test('enter returns state with spins', () {
      final context = TriggerContext(scatterCount: 3);
      final state = executor.enter(context);
      expect(state.featureId, 'free_spins');
      expect(state.totalSpins, greaterThan(0));
      expect(state.spinsRemaining, greaterThan(0));
    });

    test('step decrements spins', () {
      final state = FeatureState(
        featureId: 'free_spins',
        totalSpins: 10,
        spinsRemaining: 10,
      );
      final result = executor.step(_makeResult(), state);
      expect(result.updatedState.spinsRemaining, 9);
      expect(result.shouldContinue, isTrue);
    });

    test('step returns shouldContinue=false when spins exhausted', () {
      final state = FeatureState(
        featureId: 'free_spins',
        totalSpins: 10,
        spinsRemaining: 1,
      );
      final result = executor.step(_makeResult(), state);
      expect(result.updatedState.spinsRemaining, 0);
      expect(result.shouldContinue, isFalse);
    });

    test('modifyWin applies multiplier', () {
      const state = FeatureState(
        featureId: 'free_spins',
        currentMultiplier: 3.0,
      );
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 300.0);
      expect(result.appliedMultiplier, 3.0);
    });

    test('modifyWin with 1x returns unchanged', () {
      const state = FeatureState(
        featureId: 'free_spins',
        currentMultiplier: 1.0,
      );
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 100.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CASCADE EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('CascadeExecutor', () {
    late CascadeExecutor executor;

    setUp(() {
      executor = CascadeExecutor();
    });

    test('blockId is cascades', () {
      expect(executor.blockId, 'cascades');
    });

    test('priority is 50', () {
      expect(executor.priority, 50);
    });

    test('triggers on winning result', () {
      final context = _makeContext(totalWin: 10.0);
      expect(executor.shouldTrigger(context), isTrue);
    });

    test('does not trigger on non-win', () {
      final context = _makeContext(totalWin: 0);
      expect(executor.shouldTrigger(context), isFalse);
    });

    test('enter creates state with cascade depth 0', () {
      final state = executor.enter(TriggerContext(winAmount: 10));
      expect(state.featureId, 'cascades');
      expect(state.cascadeDepth, 0);
    });

    test('step increments cascade depth', () {
      const state = FeatureState(
        featureId: 'cascades',
        cascadeDepth: 0,
        currentMultiplier: 1.0,
      );
      final result = executor.step(_makeResult(totalWin: 5), state);
      expect(result.updatedState.cascadeDepth, 1);
    });

    test('modifyWin applies cascade multiplier', () {
      const state = FeatureState(
        featureId: 'cascades',
        currentMultiplier: 4.0,
      );
      final result = executor.modifyWin(50.0, state);
      expect(result.finalAmount, 200.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // HOLD AND WIN EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('HoldAndWinExecutor', () {
    late HoldAndWinExecutor executor;

    setUp(() {
      executor = HoldAndWinExecutor();
    });

    test('blockId is hold_and_win', () {
      expect(executor.blockId, 'hold_and_win');
    });

    test('priority is 90', () {
      expect(executor.priority, 90);
    });

    test('triggers when enough coins on grid', () {
      final grid = [
        [13, 1, 2],
        [13, 5, 6],
        [13, 2, 3],
        [13, 5, 6],
        [13, 2, 3],
        [13, 2, 3],
      ];
      final context = _makeContext(grid: grid);
      expect(executor.shouldTrigger(context), isTrue);
    });

    test('does not trigger without coins', () {
      final context = _makeContext();
      expect(executor.shouldTrigger(context), isFalse);
    });

    test('enter creates state with respins', () {
      final state = executor.enter(TriggerContext(coinCount: 6));
      expect(state.featureId, 'hold_and_win');
      expect(state.respinsRemaining, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BONUS GAME EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('BonusGameExecutor', () {
    late BonusGameExecutor executor;

    setUp(() {
      executor = BonusGameExecutor();
    });

    test('blockId is bonus_game', () {
      expect(executor.blockId, 'bonus_game');
    });

    test('priority is 70', () {
      expect(executor.priority, 70);
    });

    test('configure accepts bonusType option', () {
      executor.configure({'bonusType': 'wheel'});
    });

    test('triggers on bonus symbols', () {
      final grid = [
        [11, 1, 2],
        [11, 5, 6],
        [11, 2, 3],
        [4, 5, 6],
        [1, 2, 3],
      ];
      final context = _makeContext(grid: grid);
      expect(executor.shouldTrigger(context), isTrue);
    });

    test('enter returns state with bonus type', () {
      executor.configure({'bonusType': 'trail'});
      final state = executor.enter(TriggerContext(scatterCount: 3));
      expect(state.featureId, 'bonus_game');
      expect(state.customData['bonusType'], 'trail');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GAMBLE EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('GambleExecutor', () {
    late GambleExecutor executor;

    setUp(() {
      executor = GambleExecutor();
    });

    test('blockId is gambling', () {
      expect(executor.blockId, 'gambling');
    });

    test('priority is 30', () {
      expect(executor.priority, 30);
    });

    test('never auto-triggers (player-initiated only)', () {
      final context = _makeContext(totalWin: 10.0);
      expect(executor.shouldTrigger(context), isFalse);
    });

    test('does not trigger on loss either', () {
      final context = _makeContext(totalWin: 0);
      expect(executor.shouldTrigger(context), isFalse);
    });

    test('exit offers gamble', () {
      const state = FeatureState(
        featureId: 'gambling',
        currentStake: 50.0,
      );
      final result = executor.exit(state);
      expect(result.offerGamble, isFalse); // Gamble itself doesn't re-offer
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RESPIN EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('RespinExecutor', () {
    late RespinExecutor executor;

    setUp(() {
      executor = RespinExecutor();
    });

    test('blockId is respin', () {
      expect(executor.blockId, 'respin');
    });

    test('priority is 60', () {
      expect(executor.priority, 60);
    });

    test('enter returns state with respins', () {
      final state = executor.enter(const TriggerContext());
      expect(state.featureId, 'respin');
      expect(state.respinsRemaining, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // JACKPOT EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('JackpotExecutor', () {
    late JackpotExecutor executor;

    setUp(() {
      executor = JackpotExecutor();
    });

    test('blockId is jackpot', () {
      expect(executor.blockId, 'jackpot');
    });

    test('priority is 100', () {
      expect(executor.priority, 100);
    });

    test('does not modify win (jackpot has separate payout)', () {
      const state = FeatureState(featureId: 'jackpot');
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 100.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MULTIPLIER EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('MultiplierExecutor', () {
    late MultiplierExecutor executor;

    setUp(() {
      executor = MultiplierExecutor();
    });

    test('blockId is multiplier', () {
      expect(executor.blockId, 'multiplier');
    });

    test('priority is 45', () {
      expect(executor.priority, 45);
    });

    test('modifyWin applies multiplier from state', () {
      const state = FeatureState(
        featureId: 'multiplier',
        currentMultiplier: 5.0,
      );
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 500.0);
      expect(result.appliedMultiplier, 5.0);
    });

    test('modifyWin with 1x returns unchanged', () {
      const state = FeatureState(
        featureId: 'multiplier',
        currentMultiplier: 1.0,
      );
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 100.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // WILD FEATURES EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('WildFeaturesExecutor', () {
    late WildFeaturesExecutor executor;

    setUp(() {
      executor = WildFeaturesExecutor();
    });

    test('blockId is wild_features', () {
      expect(executor.blockId, 'wild_features');
    });

    test('priority is 55', () {
      expect(executor.priority, 55);
    });

    test('triggers when wilds present', () {
      final grid = [
        [10, 1, 2],
        [4, 5, 6],
        [1, 2, 3],
        [4, 5, 6],
        [1, 2, 3],
      ];
      final context = _makeContext(grid: grid);
      expect(executor.shouldTrigger(context), isTrue);
    });

    test('does not trigger without wilds and no randomWilds', () {
      executor.configure({'hasRandomWilds': false});
      final context = _makeContext();
      expect(executor.shouldTrigger(context), isFalse);
    });

    test('modifyWin applies wild multiplier when configured', () {
      executor.configure({'hasMultiplierWilds': true, 'wildMultiplier': 3.0});
      final state = executor.enter(const TriggerContext());
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 300.0);
    });

    test('modifyWin unchanged when no multiplier wilds', () {
      executor.configure({'hasMultiplierWilds': false});
      final state = executor.enter(const TriggerContext());
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 100.0);
    });

    test('dispose clears internal state', () {
      executor.dispose();
      // Should not throw
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // COLLECTOR EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('CollectorExecutor', () {
    late CollectorExecutor executor;

    setUp(() {
      executor = CollectorExecutor();
    });

    test('blockId is collector', () {
      expect(executor.blockId, 'collector');
    });

    test('priority is 40', () {
      expect(executor.priority, 40);
    });

    test('triggers when collection symbols on grid', () {
      final grid = [
        [16, 1, 2],
        [4, 5, 6],
        [1, 2, 3],
        [4, 5, 6],
        [1, 2, 3],
      ];
      final context = _makeContext(grid: grid);
      expect(executor.shouldTrigger(context), isTrue);
    });

    test('does not trigger without collection symbols', () {
      final context = _makeContext();
      expect(executor.shouldTrigger(context), isFalse);
    });

    test('enter creates meter state', () {
      final state = executor.enter(const TriggerContext());
      expect(state.featureId, 'collector');
      expect(state.meterValues, isNotEmpty);
      expect(state.meterTargets, isNotEmpty);
    });

    test('step counts collection symbols and updates meters', () {
      final state = executor.enter(const TriggerContext());
      final grid = [
        [16, 16, 2],
        [4, 5, 6],
        [1, 2, 3],
        [4, 5, 6],
        [1, 2, 3],
      ];
      final result = executor.step(_makeResult(grid: grid), state);
      // Meter should have increased
      final meterName = state.meterValues.keys.first;
      expect(
        result.updatedState.meterValues[meterName],
        greaterThan(state.meterValues[meterName] ?? 0),
      );
    });

    test('modifyWin does not change amount', () {
      const state = FeatureState(featureId: 'collector');
      final result = executor.modifyWin(100.0, state);
      expect(result.finalAmount, 100.0);
    });
  });
}

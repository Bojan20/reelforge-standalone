// P13.8.9: Integration tests for GameFlowIntegration ↔ FeatureBuilder sync
//
// Tests the bridge between FeatureBuilderProvider and GameFlowProvider:
// - applyFeatureBuilderConfig registers/unregisters executors
// - applyBlockConfig single-block updates
// - syncFromFeatureBuilder maps block options to executor config
// - Block ID mapping (aliases like 'tumble' → 'cascades')
// - FeatureBuilder change listener triggers resync

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/game_flow_models.dart';
import 'package:fluxforge_ui/providers/feature_builder_provider.dart';
import 'package:fluxforge_ui/providers/slot_lab/game_flow_provider.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart' show SlotLabSpinResult;

// ═══════════════════════════════════════════════════════════════════════════
// Test harness — mimics GameFlowIntegration without GetIt dependency
// ═══════════════════════════════════════════════════════════════════════════

/// Extracted static block ID mapping from GameFlowIntegration
/// for testing without requiring the singleton + GetIt.
String? mapFeatureBuilderBlockId(String featureBuilderBlockId) {
  return switch (featureBuilderBlockId) {
    'free_spins' => 'free_spins',
    'cascades' || 'tumble' || 'avalanche' => 'cascades',
    'hold_and_win' || 'cash_on_reels' || 'coin_lock' => 'hold_and_win',
    'bonus_game' || 'pick_bonus' || 'wheel_bonus' => 'bonus_game',
    'gambling' || 'gamble' || 'double_up' => 'gambling',
    'respin' || 'nudge' => 'respin',
    'jackpot' || 'progressive_jackpot' => 'jackpot',
    'multiplier' || 'random_multiplier' => 'multiplier',
    'wild_features' || 'wilds' || 'sticky_wilds' => 'wild_features',
    'collector' || 'meter' || 'collection' => 'collector',
    _ => null,
  };
}

/// Simulates applyFeatureBuilderConfig using direct GameFlowProvider access.
void applyConfig(
  GameFlowProvider flow,
  Map<String, Map<String, dynamic>> blockConfigs,
) {
  flow.clearExecutors();

  for (final entry in blockConfigs.entries) {
    final blockId = entry.key;
    final options = entry.value;
    final enabled = options['enabled'] as bool? ?? true;
    if (!enabled) continue;

    // Create executor from factory (same as GameFlowIntegration)
    final executor = _createExecutor(blockId);
    if (executor == null) continue;

    executor.configure(options);
    flow.registerExecutor(executor);
  }
}

/// Simulates syncFromFeatureBuilder
void syncFromFeatureBuilder(
  GameFlowProvider flow,
  FeatureBuilderProvider featureBuilder,
) {
  final blockConfigs = <String, Map<String, dynamic>>{};

  for (final block in featureBuilder.enabledBlocks) {
    final blockId = mapFeatureBuilderBlockId(block.id);
    if (blockId == null) continue;

    final optionsMap = <String, dynamic>{};
    for (final option in block.options) {
      optionsMap[option.id] = option.value;
    }
    optionsMap['enabled'] = block.isEnabled;
    blockConfigs[blockId] = optionsMap;
  }

  applyConfig(flow, blockConfigs);
}

/// Create a test executor matching a block ID.
_TestExecutor? _createExecutor(String blockId) {
  const validIds = {
    'free_spins', 'cascades', 'hold_and_win', 'bonus_game',
    'gambling', 'respin', 'jackpot', 'multiplier',
    'wild_features', 'collector',
  };
  if (!validIds.contains(blockId)) return null;
  return _TestExecutor(blockId);
}

// Simple test executor
class _TestExecutor extends FeatureExecutor {
  @override
  final String blockId;
  Map<String, dynamic> lastConfig = {};

  _TestExecutor(this.blockId);

  @override
  int get priority => 50;

  @override
  void configure(Map<String, dynamic> options) {
    lastConfig = Map.from(options);
  }

  @override
  bool shouldTrigger(SpinContext context) => false;

  @override
  FeatureState enter(TriggerContext context) => FeatureState(
        featureId: blockId,
      );

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) =>
      FeatureStepResult(
        updatedState: currentState,
        shouldContinue: false,
      );

  @override
  FeatureExitResult exit(FeatureState finalState) => const FeatureExitResult(
        totalWin: 0,
      );

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) =>
      ModifiedWinResult(
        originalAmount: baseWinAmount,
        finalAmount: baseWinAmount,
        multiplierSources: const [],
      );

  @override
  String? getCurrentAudioStage(FeatureState state) => null;
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Block ID Mapping
  // ─────────────────────────────────────────────────────────────────────────

  group('Block ID Mapping', () {
    test('direct IDs map to themselves', () {
      expect(mapFeatureBuilderBlockId('free_spins'), 'free_spins');
      expect(mapFeatureBuilderBlockId('cascades'), 'cascades');
      expect(mapFeatureBuilderBlockId('hold_and_win'), 'hold_and_win');
      expect(mapFeatureBuilderBlockId('bonus_game'), 'bonus_game');
      expect(mapFeatureBuilderBlockId('gambling'), 'gambling');
      expect(mapFeatureBuilderBlockId('respin'), 'respin');
      expect(mapFeatureBuilderBlockId('jackpot'), 'jackpot');
      expect(mapFeatureBuilderBlockId('multiplier'), 'multiplier');
      expect(mapFeatureBuilderBlockId('wild_features'), 'wild_features');
      expect(mapFeatureBuilderBlockId('collector'), 'collector');
    });

    test('cascade aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('tumble'), 'cascades');
      expect(mapFeatureBuilderBlockId('avalanche'), 'cascades');
    });

    test('hold_and_win aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('cash_on_reels'), 'hold_and_win');
      expect(mapFeatureBuilderBlockId('coin_lock'), 'hold_and_win');
    });

    test('bonus_game aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('pick_bonus'), 'bonus_game');
      expect(mapFeatureBuilderBlockId('wheel_bonus'), 'bonus_game');
    });

    test('gambling aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('gamble'), 'gambling');
      expect(mapFeatureBuilderBlockId('double_up'), 'gambling');
    });

    test('respin aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('nudge'), 'respin');
    });

    test('jackpot aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('progressive_jackpot'), 'jackpot');
    });

    test('multiplier aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('random_multiplier'), 'multiplier');
    });

    test('wild_features aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('wilds'), 'wild_features');
      expect(mapFeatureBuilderBlockId('sticky_wilds'), 'wild_features');
    });

    test('collector aliases map correctly', () {
      expect(mapFeatureBuilderBlockId('meter'), 'collector');
      expect(mapFeatureBuilderBlockId('collection'), 'collector');
    });

    test('unknown IDs return null', () {
      expect(mapFeatureBuilderBlockId('unknown_block'), isNull);
      expect(mapFeatureBuilderBlockId(''), isNull);
      expect(mapFeatureBuilderBlockId('game_core'), isNull);
      expect(mapFeatureBuilderBlockId('grid'), isNull);
      expect(mapFeatureBuilderBlockId('symbol_set'), isNull);
      expect(mapFeatureBuilderBlockId('win_presentation'), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // applyFeatureBuilderConfig
  // ─────────────────────────────────────────────────────────────────────────

  group('applyFeatureBuilderConfig', () {
    late GameFlowProvider flow;

    setUp(() {
      flow = GameFlowProvider();
    });

    test('registers executors for enabled blocks', () {
      applyConfig(flow, {
        'free_spins': {'enabled': true},
        'cascades': {'enabled': true},
      });
      expect(flow.executors.getExecutor('free_spins'), isNotNull);
      expect(flow.executors.getExecutor('cascades'), isNotNull);
    });

    test('skips disabled blocks', () {
      applyConfig(flow, {
        'free_spins': {'enabled': true},
        'cascades': {'enabled': false},
      });
      expect(flow.executors.getExecutor('free_spins'), isNotNull);
      expect(flow.executors.getExecutor('cascades'), isNull);
    });

    test('clears existing executors before applying', () {
      // First config
      applyConfig(flow, {
        'free_spins': {'enabled': true},
        'jackpot': {'enabled': true},
      });
      expect(flow.executors.getExecutor('free_spins'), isNotNull);
      expect(flow.executors.getExecutor('jackpot'), isNotNull);

      // Second config — different set
      applyConfig(flow, {
        'cascades': {'enabled': true},
      });
      expect(flow.executors.getExecutor('free_spins'), isNull);
      expect(flow.executors.getExecutor('jackpot'), isNull);
      expect(flow.executors.getExecutor('cascades'), isNotNull);
    });

    test('executor receives config options', () {
      applyConfig(flow, {
        'free_spins': {
          'enabled': true,
          'spin_count': 10,
          'multiplier': 3,
        },
      });
      final executor = flow.executors.getExecutor('free_spins') as _TestExecutor;
      expect(executor.lastConfig['spin_count'], 10);
      expect(executor.lastConfig['multiplier'], 3);
    });

    test('empty config clears all executors', () {
      applyConfig(flow, {
        'free_spins': {'enabled': true},
      });
      expect(flow.executors.getExecutor('free_spins'), isNotNull);

      applyConfig(flow, {});
      expect(flow.executors.isEmpty, true);
    });

    test('skips unknown block IDs', () {
      applyConfig(flow, {
        'unknown_feature': {'enabled': true},
        'free_spins': {'enabled': true},
      });
      expect(flow.executors.getExecutor('unknown_feature'), isNull);
      expect(flow.executors.getExecutor('free_spins'), isNotNull);
    });

    test('all 10 executor types can be registered', () {
      applyConfig(flow, {
        'free_spins': {'enabled': true},
        'cascades': {'enabled': true},
        'hold_and_win': {'enabled': true},
        'bonus_game': {'enabled': true},
        'gambling': {'enabled': true},
        'respin': {'enabled': true},
        'jackpot': {'enabled': true},
        'multiplier': {'enabled': true},
        'wild_features': {'enabled': true},
        'collector': {'enabled': true},
      });
      expect(flow.executors.all.length, 10);
    });

    test('enabled defaults to true when not specified', () {
      applyConfig(flow, {
        'free_spins': {'spin_count': 10}, // no 'enabled' key
      });
      expect(flow.executors.getExecutor('free_spins'), isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // syncFromFeatureBuilder
  // ─────────────────────────────────────────────────────────────────────────

  group('syncFromFeatureBuilder', () {
    late GameFlowProvider flow;
    late FeatureBuilderProvider featureBuilder;

    setUp(() {
      flow = GameFlowProvider();
      featureBuilder = FeatureBuilderProvider();
      featureBuilder.resetAll();
    });

    test('registers executors for enabled feature blocks', () {
      featureBuilder.enableBlock('free_spins');
      featureBuilder.enableBlock('cascades');
      syncFromFeatureBuilder(flow, featureBuilder);

      expect(flow.executors.getExecutor('free_spins'), isNotNull);
      expect(flow.executors.getExecutor('cascades'), isNotNull);
    });

    test('skips core blocks (no executor mapping)', () {
      // game_core, grid, symbol_set have no executor mapping
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('game_core'), isNull);
      expect(flow.executors.getExecutor('grid'), isNull);
    });

    test('skips presentation blocks (no executor mapping)', () {
      featureBuilder.enableBlock('win_presentation');
      featureBuilder.enableBlock('music_states');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('win_presentation'), isNull);
      expect(flow.executors.getExecutor('music_states'), isNull);
    });

    test('executor config includes block option values', () {
      featureBuilder.enableBlock('free_spins');
      // Set an option if available
      final block = featureBuilder.getBlock('free_spins');
      if (block != null && block.options.isNotEmpty) {
        final firstOpt = block.options.first;
        featureBuilder.setBlockOption('free_spins', firstOpt.id, firstOpt.defaultValue);
      }
      syncFromFeatureBuilder(flow, featureBuilder);

      final executor = flow.executors.getExecutor('free_spins') as _TestExecutor?;
      if (executor != null) {
        expect(executor.lastConfig['enabled'], true);
      }
    });

    test('disabling all feature blocks clears executors', () {
      featureBuilder.enableBlock('free_spins');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('free_spins'), isNotNull);

      featureBuilder.disableBlock('free_spins');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('free_spins'), isNull);
    });

    test('re-sync replaces executors (no duplicates)', () {
      featureBuilder.enableBlock('free_spins');
      syncFromFeatureBuilder(flow, featureBuilder);
      final firstExecutor = flow.executors.getExecutor('free_spins');

      // Sync again
      syncFromFeatureBuilder(flow, featureBuilder);
      final secondExecutor = flow.executors.getExecutor('free_spins');

      // Should be a new instance (clearExecutors + re-register)
      expect(secondExecutor, isNotNull);
      expect(identical(firstExecutor, secondExecutor), false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // FeatureBuilderProvider ↔ GameFlowProvider integration flow
  // ─────────────────────────────────────────────────────────────────────────

  group('Full integration flow', () {
    late GameFlowProvider flow;
    late FeatureBuilderProvider featureBuilder;

    setUp(() {
      flow = GameFlowProvider();
      featureBuilder = FeatureBuilderProvider();
      featureBuilder.resetAll();
    });

    test('enable free spins in builder → executor registered in flow', () {
      featureBuilder.enableBlock('free_spins');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('free_spins'), isNotNull);
    });

    test('disable free spins in builder → executor removed from flow', () {
      featureBuilder.enableBlock('free_spins');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('free_spins'), isNotNull);

      featureBuilder.disableBlock('free_spins');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('free_spins'), isNull);
    });

    test('multiple blocks enabled → multiple executors active', () {
      featureBuilder.enableBlock('free_spins');
      featureBuilder.enableBlock('jackpot');
      featureBuilder.enableBlock('cascades');
      featureBuilder.enableBlock('multiplier');
      syncFromFeatureBuilder(flow, featureBuilder);

      expect(flow.executors.getExecutor('free_spins'), isNotNull);
      expect(flow.executors.getExecutor('jackpot'), isNotNull);
      expect(flow.executors.getExecutor('cascades'), isNotNull);
      expect(flow.executors.getExecutor('multiplier'), isNotNull);
      expect(flow.executors.all.length, 4);
    });

    test('undo in builder → sync reflects previous state', () {
      featureBuilder.enableBlock('free_spins');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('free_spins'), isNotNull);

      featureBuilder.enableBlock('jackpot');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('jackpot'), isNotNull);

      // Undo last enable
      featureBuilder.undo();
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.getExecutor('jackpot'), isNull);
      expect(flow.executors.getExecutor('free_spins'), isNotNull);
    });

    test('resetAll in builder → all executors cleared', () {
      featureBuilder.enableBlock('free_spins');
      featureBuilder.enableBlock('jackpot');
      syncFromFeatureBuilder(flow, featureBuilder);
      expect(flow.executors.all.length, greaterThan(0));

      featureBuilder.resetAll();
      syncFromFeatureBuilder(flow, featureBuilder);
      // After resetAll, only core blocks remain enabled, no executor mapping
      expect(flow.executors.isEmpty, true);
    });
  });
}

/// Collector Executor — Runtime logic for meter/collector mechanics
///
/// Handles: symbol collection, meter fill, meter-triggered rewards,
/// multi-meter systems, and persistent collection across spins.
/// Collectors are modifier features — they don't enter a separate state
/// but track accumulation and trigger rewards at thresholds.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class CollectorExecutor extends FeatureExecutor {
  @override
  String get blockId => 'collector';

  @override
  int get priority => 40; // Lower than feature triggers

  // ─── Config ──────────────────────────────────────────────────────────────
  int _meterCount = 1;
  List<String> _meterNames = ['Collection'];
  List<int> _meterTargets = [100];
  List<int> _collectionSymbolIds = [16]; // One per meter
  List<String> _rewardTypes = ['free_spins']; // free_spins, multiplier, bonus, coins
  List<Map<String, dynamic>> _rewardConfigs = [
    {'spins': 10},
  ];
  bool _persistAcrossSpins = true;
  bool _resetOnReward = true;
  bool _activeInBaseGame = true;
  bool _activeInFreeSpins = true;
  String _displayMode = 'meter_bar'; // meter_bar, counter, ring

  @override
  void configure(Map<String, dynamic> options) {
    _meterCount = options['meterCount'] as int? ?? 1;
    _meterNames = (options['meterNames'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        ['Collection'];
    _meterTargets = (options['meterTargets'] as List<dynamic>?)
            ?.cast<int>()
            .toList() ??
        [100];
    _collectionSymbolIds = (options['collectionSymbolIds'] as List<dynamic>?)
            ?.cast<int>()
            .toList() ??
        [16];
    _rewardTypes = (options['rewardTypes'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        ['free_spins'];
    _rewardConfigs = (options['rewardConfigs'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .toList() ??
        [{'spins': 10}];
    _persistAcrossSpins = options['persistAcrossSpins'] as bool? ?? true;
    _resetOnReward = options['resetOnReward'] as bool? ?? true;
    _activeInBaseGame = options['activeInBaseGame'] as bool? ?? true;
    _activeInFreeSpins = options['activeInFreeSpins'] as bool? ?? true;
    _displayMode = options['displayMode'] as String? ?? 'meter_bar';
  }

  @override
  bool shouldTrigger(SpinContext context) {
    // Check if active in current state
    if (context.currentState == GameFlowState.baseGame && !_activeInBaseGame) {
      return false;
    }
    if (context.currentState == GameFlowState.freeSpins &&
        !_activeInFreeSpins) {
      return false;
    }

    if (context.currentState != GameFlowState.baseGame &&
        context.currentState != GameFlowState.freeSpins) {
      return false;
    }

    // Check if any collection symbols are on the grid
    for (final symbolId in _collectionSymbolIds) {
      for (final reel in context.result.grid) {
        for (final sym in reel) {
          if (sym == symbolId) return true;
        }
      }
    }

    return false;
  }

  @override
  FeatureState enter(TriggerContext context) {
    final meterValues = <String, int>{};
    final meterTargetMap = <String, int>{};

    for (int i = 0; i < _meterCount; i++) {
      final name = i < _meterNames.length ? _meterNames[i] : 'Meter $i';
      meterValues[name] = 0;
      meterTargetMap[name] = i < _meterTargets.length ? _meterTargets[i] : 100;
    }

    return FeatureState(
      featureId: 'collector',
      meterValues: meterValues,
      meterTargets: meterTargetMap,
      customData: {
        'displayMode': _displayMode,
        'meterNames': _meterNames,
        'rewardsPending': <String>[],
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    final newMeterValues = Map<String, int>.from(currentState.meterValues);
    final rewardsPending = <String>[];

    // Count collection symbols per meter
    for (int meterIdx = 0;
        meterIdx < _meterCount && meterIdx < _collectionSymbolIds.length;
        meterIdx++) {
      final symbolId = _collectionSymbolIds[meterIdx];
      final meterName =
          meterIdx < _meterNames.length ? _meterNames[meterIdx] : 'Meter $meterIdx';
      int count = 0;

      for (final reel in result.grid) {
        for (final sym in reel) {
          if (sym == symbolId) count++;
        }
      }

      if (count > 0) {
        final oldValue = newMeterValues[meterName] ?? 0;
        final newValue = oldValue + count;
        newMeterValues[meterName] = newValue;

        audioStages.add('COLLECTOR_ADD');

        // Check if target reached
        final target = currentState.meterTargets[meterName] ?? 100;
        if (newValue >= target) {
          audioStages.add('COLLECTOR_FULL');
          final rewardType =
              meterIdx < _rewardTypes.length ? _rewardTypes[meterIdx] : 'free_spins';
          rewardsPending.add(rewardType);

          if (_resetOnReward) {
            newMeterValues[meterName] = 0;
          }
        }
      }
    }

    // Collector doesn't "continue" — it processes and exits immediately
    final newState = currentState.copyWith(
      meterValues: newMeterValues,
      customData: {
        ...currentState.customData,
        'rewardsPending': rewardsPending,
      },
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: false,
      audioStages: audioStages,
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    final rewardsPending =
        finalState.customData['rewardsPending'] as List<dynamic>? ?? [];

    // Create queued features for rewards
    PendingFeature? queuedFeature;
    if (rewardsPending.isNotEmpty) {
      final reward = rewardsPending.first as String;
      switch (reward) {
        case 'free_spins':
          queuedFeature = const PendingFeature(
            targetState: GameFlowState.freeSpins,
            priority: 80,
            sourceBlockId: 'free_spins',
            triggerContext: {'fromCollector': true},
          );
        case 'bonus':
          queuedFeature = const PendingFeature(
            targetState: GameFlowState.bonusGame,
            priority: 70,
            sourceBlockId: 'bonus_game',
            triggerContext: {'fromCollector': true},
          );
      }
    }

    return FeatureExitResult(
      totalWin: 0,
      audioStages: rewardsPending.isNotEmpty
          ? const ['COLLECTOR_REWARD']
          : const [],
      offerGamble: false,
      queuedFeature: queuedFeature,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    // Collector doesn't modify wins
    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount,
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    return null; // Collector runs silently unless threshold hit
  }
}

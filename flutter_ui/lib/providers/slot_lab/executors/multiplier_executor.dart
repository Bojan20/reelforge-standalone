/// Multiplier Executor — Runtime logic for global/random multiplier system
///
/// Handles: per-spin random multiplier, progressive multiplier, wild multiplier,
/// multiplier reels, and symbol-linked multiplier features.
/// This is a non-state-changing feature — it modifies win amounts without
/// entering a separate game state.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class MultiplierExecutor extends FeatureExecutor {
  @override
  String get blockId => 'multiplier';

  @override
  int get priority => 45; // Between cascade (50) and gamble (30)

  // ─── Config ──────────────────────────────────────────────────────────────
  String _multiplierType = 'random'; // random, progressive, symbol, wild, reel
  double _minMultiplier = 2.0;
  double _maxMultiplier = 10.0;
  List<double> _possibleValues = [2, 3, 5, 10];
  double _triggerChance = 0.15; // 15% chance per spin
  bool _activeInFreeSpins = true;
  bool _activeInBaseGame = true;
  bool _stackWithOtherMultipliers = true;
  String _displayMode = 'overlay'; // overlay, reel, symbol

  // Progressive-specific
  double _progressiveStep = 0.5;
  bool _resetOnNoWin = false;

  // Symbol-linked
  int _multiplierSymbolId = 15;

  @override
  void configure(Map<String, dynamic> options) {
    _multiplierType =
        options['multiplierType'] as String? ?? 'random';
    _minMultiplier =
        (options['minMultiplier'] as num?)?.toDouble() ?? 2.0;
    _maxMultiplier =
        (options['maxMultiplier'] as num?)?.toDouble() ?? 10.0;
    _possibleValues = (options['possibleValues'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [2, 3, 5, 10];
    _triggerChance =
        (options['triggerChance'] as num?)?.toDouble() ?? 0.15;
    _activeInFreeSpins =
        options['activeInFreeSpins'] as bool? ?? true;
    _activeInBaseGame =
        options['activeInBaseGame'] as bool? ?? true;
    _stackWithOtherMultipliers =
        options['stackWithOtherMultipliers'] as bool? ?? true;
    _displayMode = options['displayMode'] as String? ?? 'overlay';
    _progressiveStep =
        (options['progressiveStep'] as num?)?.toDouble() ?? 0.5;
    _resetOnNoWin = options['resetOnNoWin'] as bool? ?? false;
    _multiplierSymbolId = options['multiplierSymbolId'] as int? ?? 15;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    // Check if active in current state
    if (context.currentState == GameFlowState.baseGame && !_activeInBaseGame) {
      return false;
    }
    if (context.currentState == GameFlowState.freeSpins && !_activeInFreeSpins) {
      return false;
    }

    // Only valid in base game or free spins
    if (context.currentState != GameFlowState.baseGame &&
        context.currentState != GameFlowState.freeSpins) {
      return false;
    }

    // Must have a win to apply multiplier
    if (!context.result.isWin) return false;

    switch (_multiplierType) {
      case 'random':
        // Engine decides via RNG — check featureTriggered or multiplier field
        return context.result.multiplier > 1;
      case 'symbol':
        // Check for multiplier symbols on grid
        return _countMultiplierSymbols(context.result) > 0;
      case 'wild':
        return context.wildCount > 0;
      case 'progressive':
        return true; // Always active, builds up
      case 'reel':
        return context.result.multiplier > 1;
      default:
        return false;
    }
  }

  int _countMultiplierSymbols(SlotLabSpinResult result) {
    int count = 0;
    for (final reel in result.grid) {
      for (final sym in reel) {
        if (sym == _multiplierSymbolId) count++;
      }
    }
    return count;
  }

  @override
  FeatureState enter(TriggerContext context) {
    double multiplierValue;

    switch (_multiplierType) {
      case 'random':
        // Use the multiplier from engine result, or default
        multiplierValue = _minMultiplier;
      case 'symbol':
        multiplierValue = _minMultiplier;
      case 'progressive':
        multiplierValue = _minMultiplier;
      case 'wild':
        multiplierValue = _minMultiplier;
      default:
        multiplierValue = _minMultiplier;
    }

    return FeatureState(
      featureId: 'multiplier',
      currentMultiplier: multiplierValue,
      maxMultiplier: _maxMultiplier,
      customData: {
        'multiplierType': _multiplierType,
        'displayMode': _displayMode,
        'stackable': _stackWithOtherMultipliers,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    double newMult = currentState.currentMultiplier;

    switch (_multiplierType) {
      case 'progressive':
        if (result.isWin) {
          newMult = (currentState.currentMultiplier + _progressiveStep)
              .clamp(_minMultiplier, _maxMultiplier);
          audioStages.add('MULTIPLIER_INCREASE');
        } else if (_resetOnNoWin) {
          newMult = _minMultiplier;
          audioStages.add('MULTIPLIER_RESET');
        }
      case 'symbol':
        final symCount = _countMultiplierSymbols(result);
        if (symCount > 0) {
          newMult = (_minMultiplier * symCount).clamp(1.0, _maxMultiplier);
          audioStages.add('MULTIPLIER_SYMBOL');
        }
      default:
        break;
    }

    final newState = currentState.copyWith(
      currentMultiplier: newMult,
    );

    // Multiplier executor doesn't "continue" — it applies and exits
    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: false,
      audioStages: audioStages,
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    return FeatureExitResult(
      totalWin: 0, // Multiplier doesn't generate its own win
      audioStages: const [],
      offerGamble: false,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    if (state.currentMultiplier <= 1.0) {
      return ModifiedWinResult(
        originalAmount: baseWinAmount,
        finalAmount: baseWinAmount,
      );
    }

    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount * state.currentMultiplier,
      appliedMultiplier: state.currentMultiplier,
      multiplierSources: ['Global: ${state.currentMultiplier}x'],
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    if (state.currentMultiplier > 1.0) return 'MULTIPLIER_ACTIVE';
    return null;
  }
}

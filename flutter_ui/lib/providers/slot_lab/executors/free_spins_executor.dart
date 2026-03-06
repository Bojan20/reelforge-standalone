/// Free Spins Executor — Runtime logic for free spins feature
///
/// Handles: trigger detection, spin counter, multiplier progression,
/// retrigger, sticky/expanding/walking wilds during FS.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class FreeSpinsExecutor extends FeatureExecutor {
  @override
  String get blockId => 'free_spins';

  @override
  int get priority => 80;

  // ─── Config ──────────────────────────────────────────────────────────────
  String _triggerMode = 'scatter';
  int _minScattersToTrigger = 3;
  int _baseSpinsCount = 10;
  bool _variableSpins = true;
  Map<int, int> _spinsPerScatterCount = {3: 10, 4: 15, 5: 20};
  String _retriggerMode = 'addSpins';
  int _retriggerSpins = 5;
  int _maxRetriggers = 3;
  int _retriggersUsed = 0;
  bool _hasMultiplier = true;
  String _multiplierBehavior = 'fixed';
  double _baseMultiplier = 2.0;
  double _maxMultiplier = 10.0;
  double _multiplierStep = 1.0;
  bool _hasIntroSequence = true;
  bool _hasOutroSequence = true;
  int _scatterSymbolId = 12;

  @override
  void configure(Map<String, dynamic> options) {
    _triggerMode = options['triggerMode'] as String? ?? 'scatter';
    _minScattersToTrigger = options['minScattersToTrigger'] as int? ?? 3;
    _baseSpinsCount = options['baseSpinsCount'] as int? ?? 10;
    _variableSpins = options['variableSpins'] as bool? ?? true;

    // Build scatter→spins map
    _spinsPerScatterCount = {
      3: options['spinsFor3Scatters'] as int? ?? 10,
      4: options['spinsFor4Scatters'] as int? ?? 15,
      5: options['spinsFor5Scatters'] as int? ?? 20,
    };

    _retriggerMode = options['retriggerMode'] as String? ?? 'addSpins';
    _retriggerSpins = options['retriggerSpins'] as int? ?? 5;
    _maxRetriggers = options['maxRetriggers'] as int? ?? 3;
    _hasMultiplier = options['hasMultiplier'] as bool? ?? true;
    _multiplierBehavior = options['multiplierBehavior'] as String? ?? 'fixed';
    _baseMultiplier = (options['baseMultiplier'] as num?)?.toDouble() ?? 2.0;
    _maxMultiplier = (options['maxMultiplier'] as num?)?.toDouble() ?? 10.0;
    _multiplierStep = (options['multiplierStep'] as num?)?.toDouble() ?? 1.0;
    _hasIntroSequence = options['hasIntroSequence'] as bool? ?? true;
    _hasOutroSequence = options['hasOutroSequence'] as bool? ?? true;
    _scatterSymbolId = options['scatterSymbolId'] as int? ?? 12;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    // Don't trigger if already in free spins (retrigger is handled separately)
    if (context.currentState == GameFlowState.freeSpins) {
      return false;
    }

    switch (_triggerMode) {
      case 'scatter':
        return context.scatterCount >= _minScattersToTrigger;
      case 'bonus':
        return context.bonusSymbolCount >= _minScattersToTrigger;
      case 'anyWin':
        return context.result.isWin;
      case 'featureBuy':
        return false; // Manual trigger only
      default:
        return context.scatterCount >= _minScattersToTrigger;
    }
  }

  /// Check if retrigger conditions are met during free spins
  bool canRetrigger(SpinContext context) {
    if (_retriggerMode == 'none') return false;
    if (_maxRetriggers > 0 && _retriggersUsed >= _maxRetriggers) return false;
    return context.scatterCount >= _minScattersToTrigger;
  }

  @override
  FeatureState enter(TriggerContext context) {
    _retriggersUsed = 0;

    int spins = _baseSpinsCount;
    if (_variableSpins && context.scatterCount != null) {
      spins = _spinsPerScatterCount[context.scatterCount] ?? _baseSpinsCount;
    }

    return FeatureState(
      featureId: 'free_spins',
      spinsRemaining: spins,
      totalSpins: spins,
      spinsCompleted: 0,
      currentMultiplier: _hasMultiplier ? _baseMultiplier : 1.0,
      maxMultiplier: _maxMultiplier,
      customData: {
        'retriggersUsed': 0,
        'hasIntro': _hasIntroSequence,
        'hasOutro': _hasOutroSequence,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    var newState = currentState.copyWith(
      spinsRemaining: currentState.spinsRemaining - 1,
      spinsCompleted: currentState.spinsCompleted + 1,
    );

    // Multiplier progression
    if (_hasMultiplier) {
      newState = _updateMultiplier(newState, result);
      if (newState.currentMultiplier != currentState.currentMultiplier) {
        audioStages.add('FS_MULTIPLIER_INCREASE');
        if (newState.currentMultiplier >= _maxMultiplier) {
          audioStages.add('FS_MULTIPLIER_MAX');
        }
      }
    }

    // Accumulate win (with multiplier applied)
    if (result.isWin) {
      final winWithMult = result.totalWin * newState.currentMultiplier;
      newState = newState.copyWith(
        accumulatedWin: newState.accumulatedWin + winWithMult,
      );
    }

    // Check retrigger (scatter count from grid)
    int scatterCount = 0;
    for (final reel in result.grid) {
      for (final sym in reel) {
        if (sym == _scatterSymbolId) scatterCount++;
      }
    }
    if (_retriggerMode != 'none' &&
        scatterCount >= _minScattersToTrigger &&
        (_maxRetriggers == 0 || _retriggersUsed < _maxRetriggers)) {
      _retriggersUsed++;
      final addedSpins = _retriggerSpins;
      newState = newState.copyWith(
        spinsRemaining: newState.spinsRemaining + addedSpins,
        totalSpins: newState.totalSpins + addedSpins,
        customData: {
          ...newState.customData,
          'retriggersUsed': _retriggersUsed,
          'lastRetriggerSpins': addedSpins,
        },
      );
      audioStages.add('FS_RETRIGGER');
      audioStages.add('FS_SPINS_ADDED');
    }

    // Spin counter audio
    audioStages.add('FS_SPIN_END');
    if (newState.spinsRemaining == 1) {
      audioStages.add('FS_LAST_SPIN');
    }

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: newState.spinsRemaining > 0,
      audioStages: audioStages,
    );
  }

  FeatureState _updateMultiplier(FeatureState state, SlotLabSpinResult result) {
    double newMult = state.currentMultiplier;

    switch (_multiplierBehavior) {
      case 'progressive':
        // Increases each spin
        newMult = (state.currentMultiplier + _multiplierStep)
            .clamp(1.0, _maxMultiplier);
      case 'cascadeLinked':
        // Increases per cascade within FS spin
        if (result.cascadeCount > 0) {
          newMult = (_baseMultiplier + (result.cascadeCount * _multiplierStep))
              .clamp(1.0, _maxMultiplier);
        }
      case 'wildLinked':
        // Placeholder: increases per wild symbol
        break;
      case 'random':
        // Placeholder: random multiplier each spin
        break;
      case 'resetting':
        newMult = _baseMultiplier; // Resets each spin
      case 'fixed':
      default:
        // Fixed — stays at base
        break;
    }

    if (newMult != state.currentMultiplier) {
      return state.copyWith(currentMultiplier: newMult);
    }
    return state;
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    final audioStages = <String>[];

    audioStages.add('FS_END');

    return FeatureExitResult(
      totalWin: finalState.accumulatedWin,
      audioStages: audioStages,
      offerGamble: finalState.accumulatedWin > 0,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    if (!_hasMultiplier || state.currentMultiplier <= 1.0) {
      return ModifiedWinResult(
        originalAmount: baseWinAmount,
        finalAmount: baseWinAmount,
      );
    }

    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount * state.currentMultiplier,
      appliedMultiplier: state.currentMultiplier,
      multiplierSources: ['Free Spins: ${state.currentMultiplier}x'],
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    if (state.spinsRemaining == state.totalSpins) return 'FS_START';
    if (state.spinsRemaining <= 0) return 'FS_END';
    return 'FS_SPIN_START';
  }
}

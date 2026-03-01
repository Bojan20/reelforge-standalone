/// Cascade Executor — Runtime logic for cascade/tumble/avalanche mechanic
///
/// Handles: win detection → symbol removal → drop/refill → re-evaluation loop.
/// Supports progressive multiplier, max cascade depth, multiple removal styles.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class CascadeExecutor extends FeatureExecutor {
  @override
  String get blockId => 'cascades';

  @override
  int get priority => 50;

  // ─── Config ──────────────────────────────────────────────────────────────
  String _removalStyle = 'explode'; // explode, dissolve, shatter, burn
  String _fillStyle = 'dropFromTop'; // dropFromTop, slideFromSide, fadeIn
  bool _hasProgressiveMultiplier = true;
  double _baseMultiplier = 1.0;
  double _multiplierStep = 1.0;
  double _maxMultiplier = 0.0; // 0 = unlimited
  String _multiplierMode = 'additive'; // additive, multiplicative, fibonacci
  int _maxCascadeDepth = 0; // 0 = unlimited
  int _removalDelayMs = 300;
  int _fillDelayMs = 250;
  bool _resetMultiplierPerSpin = true;
  bool _cascadeDuringFreeSpins = true;

  // ─── Fibonacci cache ────────────────────────────────────────────────────
  final List<double> _fibSequence = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55];

  @override
  void configure(Map<String, dynamic> options) {
    _removalStyle = options['removalStyle'] as String? ?? 'explode';
    _fillStyle = options['fillStyle'] as String? ?? 'dropFromTop';
    _hasProgressiveMultiplier =
        options['hasProgressiveMultiplier'] as bool? ?? true;
    _baseMultiplier =
        (options['baseMultiplier'] as num?)?.toDouble() ?? 1.0;
    _multiplierStep =
        (options['multiplierStep'] as num?)?.toDouble() ?? 1.0;
    _maxMultiplier =
        (options['maxMultiplier'] as num?)?.toDouble() ?? 0.0;
    _multiplierMode =
        options['multiplierMode'] as String? ?? 'additive';
    _maxCascadeDepth = options['maxCascadeDepth'] as int? ?? 0;
    _removalDelayMs = options['removalDelayMs'] as int? ?? 300;
    _fillDelayMs = options['fillDelayMs'] as int? ?? 250;
    _resetMultiplierPerSpin =
        options['resetMultiplierPerSpin'] as bool? ?? true;
    _cascadeDuringFreeSpins =
        options['cascadeDuringFreeSpins'] as bool? ?? true;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    // Cascade triggers on any win in base game or free spins
    if (!context.result.isWin) return false;

    // Don't trigger during states that don't support cascading
    final validStates = {
      GameFlowState.baseGame,
      GameFlowState.freeSpins,
      GameFlowState.respin,
    };
    if (!validStates.contains(context.currentState)) return false;

    // Check if free spins cascading is enabled
    if (context.currentState == GameFlowState.freeSpins &&
        !_cascadeDuringFreeSpins) {
      return false;
    }

    return true;
  }

  @override
  FeatureState enter(TriggerContext context) {
    return FeatureState(
      featureId: 'cascades',
      cascadeDepth: 0,
      currentMultiplier: _baseMultiplier,
      maxMultiplier: _maxMultiplier > 0 ? _maxMultiplier : double.maxFinite,
      accumulatedWin: context.winAmount ?? 0.0,
      customData: {
        'removalStyle': _removalStyle,
        'fillStyle': _fillStyle,
        'removalDelayMs': _removalDelayMs,
        'fillDelayMs': _fillDelayMs,
        'resetMultiplierPerSpin': _resetMultiplierPerSpin,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    final newDepth = currentState.cascadeDepth + 1;
    final hasWin = result.isWin;

    // Calculate new multiplier
    double newMultiplier = currentState.currentMultiplier;
    if (_hasProgressiveMultiplier && hasWin) {
      newMultiplier = _calculateMultiplier(newDepth);
    }

    // Multiplier change audio
    if (newMultiplier != currentState.currentMultiplier) {
      audioStages.add('CASCADE_MULTIPLIER_UP');
    }

    // Accumulate win with current multiplier
    double addedWin = 0;
    if (hasWin) {
      addedWin = result.totalWin * newMultiplier;
    }

    // Determine winning positions for removal
    final removedPositions = <String>{};
    if (hasWin) {
      for (final lineWin in result.lineWins) {
        for (final pos in lineWin.positions) {
          // positions is List<List<int>> — each pos is [reel, row]
          if (pos.length >= 2) {
            removedPositions.add('${pos[0]},${pos[1]}');
          }
        }
      }
    }

    // Check if cascade should continue
    bool shouldContinue = hasWin;
    if (_maxCascadeDepth > 0 && newDepth >= _maxCascadeDepth) {
      shouldContinue = false;
    }

    // Audio stages
    if (hasWin) {
      audioStages.add('CASCADE_STEP');
      audioStages.add('CASCADE_WIN_$newDepth');
    }
    if (!shouldContinue) {
      audioStages.add('CASCADE_END');
    }

    final newState = currentState.copyWith(
      cascadeDepth: newDepth,
      currentMultiplier: newMultiplier,
      accumulatedWin: currentState.accumulatedWin + addedWin,
      customData: {
        ...currentState.customData,
        'lastCascadeHadWin': hasWin,
        'totalCascades': newDepth,
      },
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: shouldContinue,
      audioStages: audioStages,
      gridModification: hasWin
          ? GridModification(
              removedPositions: removedPositions,
              removalStyle: _removalStyle,
              fillStyle: _fillStyle,
              delayMs: _removalDelayMs,
            )
          : null,
    );
  }

  double _calculateMultiplier(int depth) {
    double mult;
    switch (_multiplierMode) {
      case 'additive':
        mult = _baseMultiplier + (depth * _multiplierStep);
      case 'multiplicative':
        mult = _baseMultiplier;
        for (int i = 0; i < depth; i++) {
          mult *= (1 + _multiplierStep);
        }
      case 'fibonacci':
        final idx = depth.clamp(0, _fibSequence.length - 1);
        mult = _fibSequence[idx];
      default:
        mult = _baseMultiplier + (depth * _multiplierStep);
    }

    if (_maxMultiplier > 0) {
      mult = mult.clamp(1.0, _maxMultiplier);
    }
    return mult;
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    final audioStages = <String>['CASCADE_COMPLETE'];

    final totalCascades =
        finalState.customData['totalCascades'] as int? ?? finalState.cascadeDepth;

    if (totalCascades >= 5) {
      audioStages.add('CASCADE_MEGA_CHAIN');
    } else if (totalCascades >= 3) {
      audioStages.add('CASCADE_BIG_CHAIN');
    }

    return FeatureExitResult(
      totalWin: finalState.accumulatedWin,
      audioStages: audioStages,
      offerGamble: finalState.accumulatedWin > 0,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    if (!_hasProgressiveMultiplier || state.currentMultiplier <= 1.0) {
      return ModifiedWinResult(
        originalAmount: baseWinAmount,
        finalAmount: baseWinAmount,
      );
    }

    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount * state.currentMultiplier,
      appliedMultiplier: state.currentMultiplier,
      multiplierSources: ['Cascade ${state.cascadeDepth}x: ${state.currentMultiplier}x'],
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    if (state.cascadeDepth == 0) return 'CASCADE_START';
    return 'CASCADE_STEP';
  }
}

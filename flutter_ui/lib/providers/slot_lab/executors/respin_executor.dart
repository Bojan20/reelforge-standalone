/// Respin Executor — Runtime logic for re-spin specific reels
///
/// Handles: nudge, re-spin triggered reels, sticky positions during respin,
/// configurable respin count and trigger conditions.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class RespinExecutor extends FeatureExecutor {
  @override
  String get blockId => 'respin';

  @override
  int get priority => 60;

  // ─── Config ──────────────────────────────────────────────────────────────
  String _triggerMode = 'near_miss'; // near_miss, symbol_match, random, manual
  int _baseRespins = 1;
  bool _stickyPositions = false;
  List<int> _reelsToRespin = []; // Empty = all reels
  bool _hasMultiplier = false;
  double _respinMultiplier = 2.0;
  int _minMatchForTrigger = 2;
  bool _nudgeAvailable = false;
  int _nudgeDistance = 1;

  @override
  void configure(Map<String, dynamic> options) {
    _triggerMode = options['triggerMode'] as String? ?? 'near_miss';
    _baseRespins = options['baseRespins'] as int? ?? 1;
    _stickyPositions = options['stickyPositions'] as bool? ?? false;
    _reelsToRespin = (options['reelsToRespin'] as List<dynamic>?)
            ?.cast<int>()
            .toList() ??
        [];
    _hasMultiplier = options['hasMultiplier'] as bool? ?? false;
    _respinMultiplier =
        (options['respinMultiplier'] as num?)?.toDouble() ?? 2.0;
    _minMatchForTrigger = options['minMatchForTrigger'] as int? ?? 2;
    _nudgeAvailable = options['nudgeAvailable'] as bool? ?? false;
    _nudgeDistance = options['nudgeDistance'] as int? ?? 1;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    if (context.currentState != GameFlowState.baseGame) return false;

    switch (_triggerMode) {
      case 'near_miss':
        return context.result.nearMiss;
      case 'symbol_match':
        // Check if enough matching symbols on consecutive reels
        return _checkSymbolMatch(context.result);
      case 'random':
        return false; // Engine decides
      case 'manual':
        return false; // Player-triggered only
      default:
        return false;
    }
  }

  bool _checkSymbolMatch(SlotLabSpinResult result) {
    if (result.grid.isEmpty) return false;

    // Check first row for consecutive matches
    for (int row = 0; row < result.grid[0].length; row++) {
      int matches = 1;
      for (int reel = 1; reel < result.grid.length; reel++) {
        if (result.grid[reel][row] == result.grid[reel - 1][row]) {
          matches++;
        } else {
          break;
        }
      }
      if (matches >= _minMatchForTrigger && matches < result.grid.length) {
        return true; // Near win — enough to justify respin
      }
    }
    return false;
  }

  @override
  FeatureState enter(TriggerContext context) {
    return FeatureState(
      featureId: 'respin',
      respinsRemaining: _baseRespins,
      currentMultiplier: _hasMultiplier ? _respinMultiplier : 1.0,
      customData: {
        'reelsToRespin': _reelsToRespin,
        'stickyPositions': _stickyPositions,
        'nudgeAvailable': _nudgeAvailable,
        'nudgeDistance': _nudgeDistance,
        'totalRespins': _baseRespins,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    final newRespins = currentState.respinsRemaining - 1;

    audioStages.add('RESPIN_STEP');

    double winAdd = 0;
    if (result.isWin) {
      winAdd = result.totalWin * currentState.currentMultiplier;
      audioStages.add('RESPIN_WIN');
    }

    final shouldContinue = newRespins > 0;
    if (!shouldContinue) {
      audioStages.add('RESPIN_COMPLETE');
    }

    final newState = currentState.copyWith(
      respinsRemaining: newRespins,
      accumulatedWin: currentState.accumulatedWin + winAdd,
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: shouldContinue,
      audioStages: audioStages,
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    return FeatureExitResult(
      totalWin: finalState.accumulatedWin,
      audioStages: const ['RESPIN_EXIT'],
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
      multiplierSources: ['Respin: ${state.currentMultiplier}x'],
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    if (state.respinsRemaining == 0) return 'RESPIN_EXIT';
    return 'RESPIN_START';
  }
}

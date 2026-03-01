/// Bonus Game Executor — Runtime logic for pick/wheel/trail/ladder bonus rounds
///
/// Handles: pick-and-click, wheel of fortune, board trail, ladder climb,
/// match-3, and multi-level bonus game mechanics.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class BonusGameExecutor extends FeatureExecutor {
  @override
  String get blockId => 'bonus_game';

  @override
  int get priority => 70;

  // ─── Config ──────────────────────────────────────────────────────────────
  String _bonusType = 'pick'; // pick, wheel, trail, ladder, match
  int _minBonusSymbolsToTrigger = 3;
  int _basePicks = 5;
  bool _variablePicks = true;
  Map<int, int> _picksPerBonusCount = {3: 5, 4: 8, 5: 12};
  int _totalLevels = 1;
  bool _hasCollectOption = true;
  double _maxWinMultiplier = 500.0;
  bool _hasMultiplierPrize = true;
  bool _hasFreeSpinsPrize = true;
  bool _hasJackpotPrize = true;
  bool _hasExtraPickPrize = true;
  String _triggerMode = 'bonus_symbol'; // bonus_symbol, scatter, random

  // Wheel-specific
  int _wheelSegments = 8;

  // Trail-specific
  int _trailLength = 20;

  // Ladder-specific
  int _ladderRungs = 10;

  @override
  void configure(Map<String, dynamic> options) {
    _bonusType = options['bonusType'] as String? ?? 'pick';
    _minBonusSymbolsToTrigger =
        options['minBonusSymbolsToTrigger'] as int? ?? 3;
    _basePicks = options['basePicks'] as int? ?? 5;
    _variablePicks = options['variablePicks'] as bool? ?? true;
    _picksPerBonusCount = {
      3: options['picksFor3Bonus'] as int? ?? 5,
      4: options['picksFor4Bonus'] as int? ?? 8,
      5: options['picksFor5Bonus'] as int? ?? 12,
    };
    _totalLevels = options['totalLevels'] as int? ?? 1;
    _hasCollectOption = options['hasCollectOption'] as bool? ?? true;
    _maxWinMultiplier =
        (options['maxWinMultiplier'] as num?)?.toDouble() ?? 500.0;
    _hasMultiplierPrize = options['hasMultiplierPrize'] as bool? ?? true;
    _hasFreeSpinsPrize = options['hasFreeSpinsPrize'] as bool? ?? true;
    _hasJackpotPrize = options['hasJackpotPrize'] as bool? ?? true;
    _hasExtraPickPrize = options['hasExtraPickPrize'] as bool? ?? true;
    _triggerMode = options['triggerMode'] as String? ?? 'bonus_symbol';
    _wheelSegments = options['wheelSegments'] as int? ?? 8;
    _trailLength = options['trailLength'] as int? ?? 20;
    _ladderRungs = options['ladderRungs'] as int? ?? 10;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    if (context.currentState != GameFlowState.baseGame &&
        context.currentState != GameFlowState.freeSpins) {
      return false;
    }

    switch (_triggerMode) {
      case 'bonus_symbol':
        return context.bonusSymbolCount >= _minBonusSymbolsToTrigger;
      case 'scatter':
        return context.scatterCount >= _minBonusSymbolsToTrigger;
      case 'random':
        return false; // Engine decides
      default:
        return context.bonusSymbolCount >= _minBonusSymbolsToTrigger;
    }
  }

  @override
  FeatureState enter(TriggerContext context) {
    int picks = _basePicks;
    if (_variablePicks && context.scatterCount != null) {
      picks = _picksPerBonusCount[context.scatterCount] ?? _basePicks;
    }

    return FeatureState(
      featureId: 'bonus_game',
      picksRemaining: _bonusType == 'pick' ? picks : 0,
      currentLevel: 0,
      totalLevels: _totalLevels,
      accumulatedPrize: 0,
      currentMultiplier: 1.0,
      customData: {
        'bonusType': _bonusType,
        'hasCollectOption': _hasCollectOption,
        'wheelSegments': _wheelSegments,
        'trailPosition': 0,
        'trailLength': _trailLength,
        'ladderRung': 0,
        'ladderRungs': _ladderRungs,
        'revealedItems': <int>[],
        'totalPicks': picks,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];

    switch (_bonusType) {
      case 'pick':
        return _stepPick(currentState, audioStages);
      case 'wheel':
        return _stepWheel(currentState, audioStages);
      case 'trail':
        return _stepTrail(currentState, audioStages);
      case 'ladder':
        return _stepLadder(currentState, audioStages);
      default:
        return _stepPick(currentState, audioStages);
    }
  }

  FeatureStepResult _stepPick(
      FeatureState currentState, List<String> audioStages) {
    final newPicks = currentState.picksRemaining - 1;

    // Simulate a pick result — engine will provide actual prize
    // For now: add a placeholder prize value
    audioStages.add('BONUS_PICK');
    audioStages.add('BONUS_REVEAL');

    final revealedItems = List<int>.from(
        currentState.customData['revealedItems'] as List<dynamic>? ?? []);
    revealedItems.add(revealedItems.length);

    final shouldContinue = newPicks > 0;
    if (!shouldContinue) {
      audioStages.add('BONUS_ALL_PICKED');
    }

    final newState = currentState.copyWith(
      picksRemaining: newPicks,
      customData: {
        ...currentState.customData,
        'revealedItems': revealedItems,
      },
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: shouldContinue,
      audioStages: audioStages,
    );
  }

  FeatureStepResult _stepWheel(
      FeatureState currentState, List<String> audioStages) {
    audioStages.add('BONUS_WHEEL_SPIN');
    audioStages.add('BONUS_WHEEL_RESULT');

    // Wheel completes in a single spin
    final newState = currentState.copyWith(
      currentLevel: currentState.currentLevel + 1,
    );

    final shouldContinue =
        currentState.currentLevel + 1 < currentState.totalLevels;

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: shouldContinue,
      audioStages: audioStages,
    );
  }

  FeatureStepResult _stepTrail(
      FeatureState currentState, List<String> audioStages) {
    final currentPos =
        currentState.customData['trailPosition'] as int? ?? 0;
    final newPos = currentPos + 1;

    audioStages.add('BONUS_TRAIL_MOVE');

    final atEnd = newPos >= _trailLength;
    if (atEnd) {
      audioStages.add('BONUS_TRAIL_COMPLETE');
    }

    final newState = currentState.copyWith(
      customData: {
        ...currentState.customData,
        'trailPosition': newPos,
      },
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: !atEnd,
      audioStages: audioStages,
    );
  }

  FeatureStepResult _stepLadder(
      FeatureState currentState, List<String> audioStages) {
    final currentRung =
        currentState.customData['ladderRung'] as int? ?? 0;
    final newRung = currentRung + 1;

    audioStages.add('BONUS_LADDER_CLIMB');

    final atTop = newRung >= _ladderRungs;
    if (atTop) {
      audioStages.add('BONUS_LADDER_TOP');
    }

    final newState = currentState.copyWith(
      currentLevel: newRung,
      customData: {
        ...currentState.customData,
        'ladderRung': newRung,
      },
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: !atTop,
      audioStages: audioStages,
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    final audioStages = <String>[
      'BONUS_EXIT',
      'BONUS_TOTAL_WIN',
    ];

    return FeatureExitResult(
      totalWin: finalState.accumulatedPrize,
      audioStages: audioStages,
      offerGamble: finalState.accumulatedPrize > 0,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    // Bonus game doesn't modify base spin wins
    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount,
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    if (state.picksRemaining > 0) return 'BONUS_PICK_START';
    return 'BONUS_EXIT';
  }
}

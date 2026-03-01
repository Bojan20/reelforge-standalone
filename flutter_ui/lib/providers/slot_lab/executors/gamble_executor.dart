/// Gamble Executor — Runtime logic for double-up / risk mechanic
///
/// Handles: card gamble (red/black, suit), coin flip, wheel gamble,
/// 50/50 risk, ladder gamble. Optional gamble limit.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class GambleExecutor extends FeatureExecutor {
  @override
  String get blockId => 'gambling';

  @override
  int get priority => 30;

  // ─── Config ──────────────────────────────────────────────────────────────
  String _gambleType = 'card_color'; // card_color, card_suit, coin_flip, wheel
  int _maxRounds = 5;
  double _maxWinMultiplier = 10.0;
  bool _halfGambleAvailable = true;
  double _colorMultiplier = 2.0; // Red/Black = 2x
  double _suitMultiplier = 4.0; // Suit = 4x
  bool _showHistory = true;
  int _historyLength = 10;
  double _maxGambleAmount = 0; // 0 = unlimited

  @override
  void configure(Map<String, dynamic> options) {
    _gambleType = options['gambleType'] as String? ?? 'card_color';
    _maxRounds = options['maxRounds'] as int? ?? 5;
    _maxWinMultiplier =
        (options['maxWinMultiplier'] as num?)?.toDouble() ?? 10.0;
    _halfGambleAvailable =
        options['halfGambleAvailable'] as bool? ?? true;
    _colorMultiplier =
        (options['colorMultiplier'] as num?)?.toDouble() ?? 2.0;
    _suitMultiplier =
        (options['suitMultiplier'] as num?)?.toDouble() ?? 4.0;
    _showHistory = options['showHistory'] as bool? ?? true;
    _historyLength = options['historyLength'] as int? ?? 10;
    _maxGambleAmount =
        (options['maxGambleAmount'] as num?)?.toDouble() ?? 0;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    // Gamble never auto-triggers — only via player action
    return false;
  }

  @override
  FeatureState enter(TriggerContext context) {
    final stake = context.winAmount ?? 0.0;

    return FeatureState(
      featureId: 'gambling',
      currentStake: stake,
      roundsPlayed: 0,
      maxRounds: _maxRounds,
      accumulatedWin: stake,
      customData: {
        'gambleType': _gambleType,
        'halfGambleAvailable': _halfGambleAvailable,
        'colorMultiplier': _colorMultiplier,
        'suitMultiplier': _suitMultiplier,
        'history': <Map<String, dynamic>>[],
        'showHistory': _showHistory,
        'originalStake': stake,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    final newRound = currentState.roundsPlayed + 1;

    // The result of the gamble is determined by engine/RNG
    // Here we model the state transitions
    // result.totalWin > 0 indicates player won the gamble
    final playerWon = result.totalWin > 0;

    double newStake;
    if (playerWon) {
      // Apply multiplier based on gamble type
      double mult;
      switch (_gambleType) {
        case 'card_color':
        case 'coin_flip':
          mult = _colorMultiplier;
        case 'card_suit':
          mult = _suitMultiplier;
        case 'wheel':
          mult = result.multiplier.toDouble(); // Dynamic from wheel
        default:
          mult = _colorMultiplier;
      }
      newStake = currentState.currentStake * mult;
      audioStages.add('GAMBLE_WIN');
    } else {
      // Player lost — check if half gamble was used
      final isHalf = result.featureTriggered; // Repurpose field
      if (isHalf && _halfGambleAvailable) {
        newStake = currentState.currentStake / 2;
        audioStages.add('GAMBLE_HALF_LOSE');
      } else {
        newStake = 0;
        audioStages.add('GAMBLE_LOSE');
      }
    }

    // Cap at max win multiplier
    final originalStake =
        currentState.customData['originalStake'] as double? ??
            currentState.currentStake;
    if (_maxWinMultiplier > 0 && newStake > originalStake * _maxWinMultiplier) {
      newStake = originalStake * _maxWinMultiplier;
      audioStages.add('GAMBLE_MAX_REACHED');
    }

    // Update history
    final history = List<Map<String, dynamic>>.from(
        currentState.customData['history'] as List<dynamic>? ?? []);
    history.add({
      'round': newRound,
      'won': playerWon,
      'stake': currentState.currentStake,
      'result': newStake,
    });
    if (history.length > _historyLength) {
      history.removeAt(0);
    }

    final shouldContinue = newStake > 0 && newRound < _maxRounds;

    audioStages.add('GAMBLE_ROUND_END');

    final newState = currentState.copyWith(
      currentStake: newStake,
      roundsPlayed: newRound,
      accumulatedWin: newStake,
      customData: {
        ...currentState.customData,
        'history': history,
        'lastRoundWon': playerWon,
      },
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: shouldContinue,
      audioStages: audioStages,
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    final audioStages = <String>[];

    if (finalState.currentStake > 0) {
      audioStages.add('GAMBLE_COLLECT');
    } else {
      audioStages.add('GAMBLE_BUST');
    }
    audioStages.add('GAMBLE_EXIT');

    return FeatureExitResult(
      totalWin: finalState.currentStake,
      audioStages: audioStages,
      offerGamble: false, // No re-gamble
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    // Gamble replaces the win, doesn't multiply it
    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount,
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    if (state.roundsPlayed == 0) return 'GAMBLE_ENTER';
    if (state.currentStake <= 0) return 'GAMBLE_BUST';
    return 'GAMBLE_ROUND_START';
  }
}

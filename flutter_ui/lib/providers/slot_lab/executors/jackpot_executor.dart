/// Jackpot Executor — Runtime logic for progressive/fixed jackpot system
///
/// Handles: jackpot tier detection, contribution tracking,
/// presentation sequencing, multi-tier progressive jackpots.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class JackpotExecutor extends FeatureExecutor {
  @override
  String get blockId => 'jackpot';

  @override
  int get priority => 100; // Highest — always processes first

  // ─── Config ──────────────────────────────────────────────────────────────
  String _jackpotMode = 'progressive'; // progressive, fixed, mystery
  int _tierCount = 4;
  List<String> _tierNames = ['Mini', 'Minor', 'Major', 'Grand'];
  List<double> _tierSeeds = [100, 500, 5000, 50000];
  List<double> _tierContributionRates = [0.005, 0.003, 0.001, 0.0005];
  List<double> _tierCurrentValues = [100, 500, 5000, 50000];
  String _triggerCondition = 'symbol_match'; // symbol_match, random, max_bet
  int _minSymbolsForJackpot = 5; // Full screen of jackpot symbol
  bool _maxBetOnly = false;
  double _mysteryMinBet = 0.0;
  int _presentationDurationMs = 5000;

  @override
  void configure(Map<String, dynamic> options) {
    _jackpotMode = options['jackpotMode'] as String? ?? 'progressive';
    _tierCount = options['tierCount'] as int? ?? 4;
    _tierNames = (options['tierNames'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        ['Mini', 'Minor', 'Major', 'Grand'];
    _tierSeeds = (options['tierSeeds'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [100, 500, 5000, 50000];
    _tierContributionRates = (options['tierContributionRates'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [0.005, 0.003, 0.001, 0.0005];
    _tierCurrentValues = List<double>.from(_tierSeeds);
    _triggerCondition =
        options['triggerCondition'] as String? ?? 'symbol_match';
    _minSymbolsForJackpot =
        options['minSymbolsForJackpot'] as int? ?? 5;
    _maxBetOnly = options['maxBetOnly'] as bool? ?? false;
    _mysteryMinBet =
        (options['mysteryMinBet'] as num?)?.toDouble() ?? 0.0;
    _presentationDurationMs =
        options['presentationDurationMs'] as int? ?? 5000;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    switch (_triggerCondition) {
      case 'symbol_match':
        // Full screen of jackpot symbol (or minimum count)
        return _checkJackpotSymbols(context);
      case 'random':
        // Engine decides — never triggers from Dart side
        return false;
      case 'max_bet':
        // Only at max bet — engine would signal via featureTriggered
        return context.result.featureTriggered && _maxBetOnly;
      default:
        return false;
    }
  }

  bool _checkJackpotSymbols(SpinContext context) {
    // Count jackpot symbols across grid (typically coin or special symbol)
    // In H&W mode, full grid = Grand Jackpot — handled by H&W executor
    // Standalone jackpot: check for dedicated jackpot symbol
    int jackpotSymCount = 0;
    for (final reel in context.result.grid) {
      for (final sym in reel) {
        if (sym == 14) jackpotSymCount++; // TODO: configurable jackpot symbol ID
      }
    }
    return jackpotSymCount >= _minSymbolsForJackpot;
  }

  /// Called each spin to accumulate progressive jackpot values
  void contributeToJackpot(double betAmount) {
    if (_jackpotMode != 'progressive') return;

    for (int i = 0; i < _tierCount && i < _tierContributionRates.length; i++) {
      _tierCurrentValues[i] += betAmount * _tierContributionRates[i];
    }
  }

  /// Get current jackpot value for a tier
  double getJackpotValue(int tierIndex) {
    if (tierIndex < 0 || tierIndex >= _tierCurrentValues.length) return 0;
    return _tierCurrentValues[tierIndex];
  }

  /// Get tier name
  String getTierName(int tierIndex) {
    if (tierIndex < 0 || tierIndex >= _tierNames.length) return 'Unknown';
    return _tierNames[tierIndex];
  }

  /// Get all tiers as display data
  List<({String name, double value})> get tierDisplayData {
    final data = <({String name, double value})>[];
    for (int i = 0; i < _tierCount; i++) {
      data.add((
        name: i < _tierNames.length ? _tierNames[i] : 'Tier $i',
        value: i < _tierCurrentValues.length ? _tierCurrentValues[i] : 0,
      ));
    }
    return data;
  }

  @override
  FeatureState enter(TriggerContext context) {
    // Determine which jackpot tier was won
    int wonTier = 0; // Default: lowest
    final jackpotTier = context.extra['jackpotTier'] as int?;
    if (jackpotTier != null) {
      wonTier = jackpotTier;
    }

    final wonValue = getJackpotValue(wonTier);

    return FeatureState(
      featureId: 'jackpot',
      accumulatedWin: wonValue,
      currentLevel: wonTier,
      totalLevels: _tierCount,
      customData: {
        'wonTierIndex': wonTier,
        'wonTierName': getTierName(wonTier),
        'wonValue': wonValue,
        'presentationDurationMs': _presentationDurationMs,
        'jackpotMode': _jackpotMode,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    // Jackpot presentation is a single sequence — no stepping needed
    return FeatureStepResult(
      updatedState: currentState,
      shouldContinue: false,
      audioStages: const ['JACKPOT_REVEAL', 'JACKPOT_AWARD'],
    );
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    final wonTier =
        finalState.customData['wonTierIndex'] as int? ?? 0;
    final wonValue =
        finalState.customData['wonValue'] as double? ?? 0;

    // Reset the won tier to seed value
    if (wonTier < _tierCurrentValues.length) {
      _tierCurrentValues[wonTier] = _tierSeeds[wonTier];
    }

    return FeatureExitResult(
      totalWin: wonValue,
      audioStages: const ['JACKPOT_EXIT', 'JACKPOT_TOTAL_WIN'],
      offerGamble: false, // Never gamble a jackpot
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    // Jackpot doesn't modify base wins
    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount,
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    return 'JACKPOT_PRESENTATION';
  }
}

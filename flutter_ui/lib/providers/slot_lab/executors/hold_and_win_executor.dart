/// Hold & Win Executor — Runtime logic for coin-lock respin mechanic
///
/// Handles: coin trigger detection, grid lock/unlock, respin counter reset,
/// special coin types (multiplier/collector/upgrade), jackpot fill detection.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class HoldAndWinExecutor extends FeatureExecutor {
  @override
  String get blockId => 'hold_and_win';

  @override
  int get priority => 90;

  // ─── Config ──────────────────────────────────────────────────────────────
  int _minCoinsToTrigger = 6;
  int _baseRespins = 3;
  bool _resetRespinsOnNewCoin = true;
  int _reelCount = 5;
  int _rowCount = 3;
  bool _hasSpecialCoins = true;
  bool _hasGrandJackpot = true; // All positions filled = Grand Jackpot
  String _coinValueMode = 'bet_multiplier'; // bet_multiplier, fixed, random
  double _minCoinMultiplier = 1.0;
  double _maxCoinMultiplier = 50.0;
  double _grandJackpotMultiplier = 1000.0;
  double _majorJackpotMultiplier = 100.0;
  double _minorJackpotMultiplier = 20.0;
  double _miniJackpotMultiplier = 10.0;
  bool _stickyCoins = true;
  int _maxRespins = 10;
  int _coinSymbolId = 13;

  // Special coin probabilities (designer-configurable)
  double _multiplierCoinChance = 0.05;
  double _collectorCoinChance = 0.03;
  double _upgradeCoinChance = 0.02;
  double _wildCoinChance = 0.01;

  @override
  void configure(Map<String, dynamic> options) {
    _minCoinsToTrigger = options['minCoinsToTrigger'] as int? ?? 6;
    _baseRespins = options['baseRespins'] as int? ?? 3;
    _resetRespinsOnNewCoin =
        options['resetRespinsOnNewCoin'] as bool? ?? true;
    _reelCount = options['reelCount'] as int? ?? 5;
    _rowCount = options['rowCount'] as int? ?? 3;
    _hasSpecialCoins = options['hasSpecialCoins'] as bool? ?? true;
    _hasGrandJackpot = options['hasGrandJackpot'] as bool? ?? true;
    _coinValueMode =
        options['coinValueMode'] as String? ?? 'bet_multiplier';
    _minCoinMultiplier =
        (options['minCoinMultiplier'] as num?)?.toDouble() ?? 1.0;
    _maxCoinMultiplier =
        (options['maxCoinMultiplier'] as num?)?.toDouble() ?? 50.0;
    _grandJackpotMultiplier =
        (options['grandJackpotMultiplier'] as num?)?.toDouble() ?? 1000.0;
    _majorJackpotMultiplier =
        (options['majorJackpotMultiplier'] as num?)?.toDouble() ?? 100.0;
    _minorJackpotMultiplier =
        (options['minorJackpotMultiplier'] as num?)?.toDouble() ?? 20.0;
    _miniJackpotMultiplier =
        (options['miniJackpotMultiplier'] as num?)?.toDouble() ?? 10.0;
    _stickyCoins = options['stickyCoins'] as bool? ?? true;
    _maxRespins = options['maxRespins'] as int? ?? 10;
    _multiplierCoinChance =
        (options['multiplierCoinChance'] as num?)?.toDouble() ?? 0.05;
    _collectorCoinChance =
        (options['collectorCoinChance'] as num?)?.toDouble() ?? 0.03;
    _upgradeCoinChance =
        (options['upgradeCoinChance'] as num?)?.toDouble() ?? 0.02;
    _wildCoinChance =
        (options['wildCoinChance'] as num?)?.toDouble() ?? 0.01;
    _coinSymbolId = options['coinSymbolId'] as int? ?? 13;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    // Only trigger from base game or free spins
    if (context.currentState != GameFlowState.baseGame &&
        context.currentState != GameFlowState.freeSpins) {
      return false;
    }

    return context.coinCount >= _minCoinsToTrigger;
  }

  @override
  FeatureState enter(TriggerContext context) {
    final totalPositions = _reelCount * _rowCount;

    // Create initial locked coins from trigger
    final lockedCoins = <CoinPosition>[];
    if (context.triggeringCoins != null) {
      lockedCoins.addAll(context.triggeringCoins!);
    }

    return FeatureState(
      featureId: 'hold_and_win',
      respinsRemaining: _baseRespins,
      gridPositionsFilled: lockedCoins.length,
      gridPositionsTotal: totalPositions,
      lockedCoins: lockedCoins,
      accumulatedWin: _sumCoinValues(lockedCoins),
      customData: {
        'hasGrandJackpot': _hasGrandJackpot,
        'stickyCoins': _stickyCoins,
        'grandJackpotMultiplier': _grandJackpotMultiplier,
        'majorJackpotMultiplier': _majorJackpotMultiplier,
        'minorJackpotMultiplier': _minorJackpotMultiplier,
        'miniJackpotMultiplier': _miniJackpotMultiplier,
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    var newLockedCoins = List<CoinPosition>.from(currentState.lockedCoins);
    var newRespins = currentState.respinsRemaining - 1;
    bool newCoinsLanded = false;

    // Check for new coins in non-locked positions
    final lockedPositions = <String>{};
    for (final coin in newLockedCoins) {
      lockedPositions.add(coin.positionKey);
    }

    // Scan grid for new coin symbols
    for (int reel = 0; reel < result.grid.length; reel++) {
      final reelData = result.grid[reel];
      for (int row = 0; row < reelData.length; row++) {
        final posKey = '$reel,$row';
        if (lockedPositions.contains(posKey)) continue;

        if (reelData[row] == _coinSymbolId) {
          final coinValue = _generateCoinValue(result.bet);
          final specialType = _hasSpecialCoins ? _rollSpecialType() : null;

          newLockedCoins.add(CoinPosition(
            reel: reel,
            row: row,
            value: coinValue,
            specialType: specialType,
            specialValue: _getSpecialValue(specialType, coinValue),
          ));
          newCoinsLanded = true;
          audioStages.add('HOLD_COIN_LAND');
        }
      }
    }

    // Reset respins if new coins landed
    if (newCoinsLanded && _resetRespinsOnNewCoin) {
      newRespins = _baseRespins;
      audioStages.add('HOLD_RESPIN_RESET');
    }

    // Clamp respins
    newRespins = newRespins.clamp(0, _maxRespins);

    final newFilled = newLockedCoins.length;
    final totalPositions = _reelCount * _rowCount;

    // Process special coins
    _processSpecialCoins(newLockedCoins, audioStages);

    // Calculate total accumulated win
    final totalWin = _sumCoinValues(newLockedCoins);

    // Check for jackpots
    bool gridFull = newFilled >= totalPositions;
    if (gridFull && _hasGrandJackpot) {
      audioStages.add('HOLD_GRAND_JACKPOT');
    }

    // Check minor jackpot tiers (by row/column completion)
    _checkJackpotTiers(newLockedCoins, audioStages);

    // Determine if feature continues
    bool shouldContinue = newRespins > 0 && !gridFull;

    // Audio
    if (!newCoinsLanded) {
      audioStages.add('HOLD_NO_COIN');
    }
    if (newRespins == 1 && shouldContinue) {
      audioStages.add('HOLD_LAST_RESPIN');
    }
    audioStages.add('HOLD_RESPIN_END');

    final newState = currentState.copyWith(
      respinsRemaining: newRespins,
      gridPositionsFilled: newFilled,
      lockedCoins: newLockedCoins,
      accumulatedWin: totalWin,
      customData: {
        ...currentState.customData,
        'lastSpinNewCoins': newCoinsLanded,
        'gridFull': gridFull,
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
    var totalWin = finalState.accumulatedWin;

    final gridFull =
        finalState.customData['gridFull'] as bool? ?? false;

    if (gridFull && _hasGrandJackpot) {
      totalWin += finalState.lockedCoins.first.value * _grandJackpotMultiplier;
      audioStages.add('HOLD_GRAND_JACKPOT_AWARD');
    }

    audioStages.add('HOLD_EXIT');
    audioStages.add('HOLD_TOTAL_WIN');

    return FeatureExitResult(
      totalWin: totalWin,
      audioStages: audioStages,
      offerGamble: totalWin > 0,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    // H&W doesn't modify base game wins — it has its own win accumulation
    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount,
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    if (state.respinsRemaining == _baseRespins &&
        state.gridPositionsFilled == 0) {
      return 'HOLD_ENTER';
    }
    if (state.respinsRemaining <= 0) return 'HOLD_EXIT';
    return 'HOLD_RESPIN_START';
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  double _sumCoinValues(List<CoinPosition> coins) {
    double sum = 0;
    for (final coin in coins) {
      sum += coin.value;
    }
    return sum;
  }

  double _generateCoinValue(double bet) {
    switch (_coinValueMode) {
      case 'bet_multiplier':
        // Random multiplier between min and max × bet
        // For now use midpoint — runtime will use RNG
        final midMult = (_minCoinMultiplier + _maxCoinMultiplier) / 2;
        return bet * midMult;
      case 'fixed':
        return bet * _minCoinMultiplier;
      case 'random':
        return bet * _minCoinMultiplier;
      default:
        return bet * _minCoinMultiplier;
    }
  }

  CoinSpecialType? _rollSpecialType() {
    // Deterministic probabilities from config — no actual RNG here
    // Runtime engine will handle actual randomization
    // This returns null as default; engine integration will provide actual type
    return null;
  }

  double? _getSpecialValue(CoinSpecialType? type, double baseValue) {
    if (type == null) return null;
    switch (type) {
      case CoinSpecialType.multiplier:
        return 2.0; // Default 2x multiplier coin
      case CoinSpecialType.collector:
        return 0; // Collects all values
      case CoinSpecialType.upgrade:
        return baseValue * 2; // Doubles value
      case CoinSpecialType.wild:
        return 0; // Acts as any coin
    }
  }

  void _processSpecialCoins(
      List<CoinPosition> coins, List<String> audioStages) {
    bool hasCollector = false;
    double collectorTotal = 0;

    for (final coin in coins) {
      if (coin.specialType == CoinSpecialType.collector) {
        hasCollector = true;
      }
      if (coin.specialType == CoinSpecialType.multiplier) {
        audioStages.add('HOLD_MULTIPLIER_COIN');
      }
    }

    if (hasCollector) {
      // Collector coin sums all other coin values
      for (final coin in coins) {
        if (coin.specialType != CoinSpecialType.collector) {
          collectorTotal += coin.value;
        }
      }
      audioStages.add('HOLD_COLLECTOR_COIN');
    }
  }

  void _checkJackpotTiers(
      List<CoinPosition> coins, List<String> audioStages) {
    // Check if a full row or column is filled
    final filledPositions = <String>{};
    for (final coin in coins) {
      filledPositions.add(coin.positionKey);
    }

    // Check rows
    for (int row = 0; row < _rowCount; row++) {
      bool rowFull = true;
      for (int reel = 0; reel < _reelCount; reel++) {
        if (!filledPositions.contains('$reel,$row')) {
          rowFull = false;
          break;
        }
      }
      if (rowFull) {
        audioStages.add('HOLD_ROW_COMPLETE');
      }
    }

    // Check columns
    for (int reel = 0; reel < _reelCount; reel++) {
      bool colFull = true;
      for (int row = 0; row < _rowCount; row++) {
        if (!filledPositions.contains('$reel,$row')) {
          colFull = false;
          break;
        }
      }
      if (colFull) {
        audioStages.add('HOLD_COLUMN_COMPLETE');
      }
    }
  }
}

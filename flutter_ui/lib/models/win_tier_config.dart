/// Win Tier Configuration Model (M4)
///
/// Defines win tier thresholds from slot game math model/paytable.
/// Used to auto-generate RTPC thresholds for audio layer escalation.
///
/// Win tiers are typically:
/// - NO_WIN: 0x bet
/// - SMALL_WIN: 0.1x - 2x bet
/// - MEDIUM_WIN: 2x - 5x bet
/// - BIG_WIN: 5x - 20x bet
/// - MEGA_WIN: 20x - 50x bet
/// - EPIC_WIN: 50x+ bet
/// - JACKPOT: Fixed amounts or progressive

import 'dart:convert';

/// Standard win tier enum
enum WinTier {
  noWin,
  smallWin,
  mediumWin,
  bigWin,
  megaWin,
  epicWin,
  ultraWin,
  jackpotMini,
  jackpotMinor,
  jackpotMajor,
  jackpotGrand;

  String get displayName {
    switch (this) {
      case WinTier.noWin:
        return 'No Win';
      case WinTier.smallWin:
        return 'Small Win';
      case WinTier.mediumWin:
        return 'Medium Win';
      case WinTier.bigWin:
        return 'Big Win';
      case WinTier.megaWin:
        return 'Mega Win';
      case WinTier.epicWin:
        return 'Epic Win';
      case WinTier.ultraWin:
        return 'Ultra Win';
      case WinTier.jackpotMini:
        return 'Mini Jackpot';
      case WinTier.jackpotMinor:
        return 'Minor Jackpot';
      case WinTier.jackpotMajor:
        return 'Major Jackpot';
      case WinTier.jackpotGrand:
        return 'Grand Jackpot';
    }
  }

  /// Audio intensity level (0-10) for this tier
  int get audioIntensity {
    switch (this) {
      case WinTier.noWin:
        return 0;
      case WinTier.smallWin:
        return 2;
      case WinTier.mediumWin:
        return 4;
      case WinTier.bigWin:
        return 6;
      case WinTier.megaWin:
        return 7;
      case WinTier.epicWin:
        return 8;
      case WinTier.ultraWin:
        return 9;
      case WinTier.jackpotMini:
        return 7;
      case WinTier.jackpotMinor:
        return 8;
      case WinTier.jackpotMajor:
        return 9;
      case WinTier.jackpotGrand:
        return 10;
    }
  }
}

/// Win tier threshold definition
class WinTierThreshold {
  final WinTier tier;

  /// Minimum win in bet multiplier (e.g., 5.0 = 5x bet)
  final double minXBet;

  /// Maximum win in bet multiplier (null = unlimited)
  final double? maxXBet;

  /// RTPC value to set when this tier is reached (0.0 - 1.0)
  final double rtpcValue;

  /// Stage to trigger when this tier is reached
  final String? triggerStage;

  /// Whether this tier should trigger celebration animation
  final bool triggerCelebration;

  /// Rollup duration multiplier (1.0 = normal, 2.0 = slower for big wins)
  final double rollupDurationMultiplier;

  const WinTierThreshold({
    required this.tier,
    required this.minXBet,
    this.maxXBet,
    required this.rtpcValue,
    this.triggerStage,
    this.triggerCelebration = false,
    this.rollupDurationMultiplier = 1.0,
  });

  WinTierThreshold copyWith({
    WinTier? tier,
    double? minXBet,
    double? maxXBet,
    double? rtpcValue,
    String? triggerStage,
    bool? triggerCelebration,
    double? rollupDurationMultiplier,
  }) {
    return WinTierThreshold(
      tier: tier ?? this.tier,
      minXBet: minXBet ?? this.minXBet,
      maxXBet: maxXBet ?? this.maxXBet,
      rtpcValue: rtpcValue ?? this.rtpcValue,
      triggerStage: triggerStage ?? this.triggerStage,
      triggerCelebration: triggerCelebration ?? this.triggerCelebration,
      rollupDurationMultiplier:
          rollupDurationMultiplier ?? this.rollupDurationMultiplier,
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'minXBet': minXBet,
        'maxXBet': maxXBet,
        'rtpcValue': rtpcValue,
        'triggerStage': triggerStage,
        'triggerCelebration': triggerCelebration,
        'rollupDurationMultiplier': rollupDurationMultiplier,
      };

  factory WinTierThreshold.fromJson(Map<String, dynamic> json) {
    return WinTierThreshold(
      tier: WinTier.values.firstWhere(
        (t) => t.name == json['tier'],
        orElse: () => WinTier.noWin,
      ),
      minXBet: (json['minXBet'] as num).toDouble(),
      maxXBet: (json['maxXBet'] as num?)?.toDouble(),
      rtpcValue: (json['rtpcValue'] as num).toDouble(),
      triggerStage: json['triggerStage'] as String?,
      triggerCelebration: json['triggerCelebration'] as bool? ?? false,
      rollupDurationMultiplier:
          (json['rollupDurationMultiplier'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Win tier configuration for a game
class WinTierConfig {
  final String gameId;
  final String gameName;
  final List<WinTierThreshold> tiers;

  /// RTPC parameter to bind win tier to
  final String rtpcParameterName;

  /// Default base bet for calculations
  final double defaultBaseBet;

  /// Maximum win cap (in currency, not multiplier)
  final double? maxWinCap;

  /// Whether to use linear or logarithmic RTPC scaling
  final bool useLogarithmicScaling;

  const WinTierConfig({
    required this.gameId,
    required this.gameName,
    required this.tiers,
    this.rtpcParameterName = 'winTier',
    this.defaultBaseBet = 1.0,
    this.maxWinCap,
    this.useLogarithmicScaling = true,
  });

  WinTierConfig copyWith({
    String? gameId,
    String? gameName,
    List<WinTierThreshold>? tiers,
    String? rtpcParameterName,
    double? defaultBaseBet,
    double? maxWinCap,
    bool? useLogarithmicScaling,
  }) {
    return WinTierConfig(
      gameId: gameId ?? this.gameId,
      gameName: gameName ?? this.gameName,
      tiers: tiers ?? this.tiers,
      rtpcParameterName: rtpcParameterName ?? this.rtpcParameterName,
      defaultBaseBet: defaultBaseBet ?? this.defaultBaseBet,
      maxWinCap: maxWinCap ?? this.maxWinCap,
      useLogarithmicScaling:
          useLogarithmicScaling ?? this.useLogarithmicScaling,
    );
  }

  /// Get the tier for a given win amount
  WinTierThreshold? getTierForWin(double winAmount, double betAmount) {
    if (betAmount <= 0) return null;
    final xBet = winAmount / betAmount;

    WinTierThreshold? result;
    for (final tier in tiers) {
      if (xBet >= tier.minXBet) {
        if (tier.maxXBet == null || xBet < tier.maxXBet!) {
          result = tier;
        }
      }
    }
    return result;
  }

  /// Get RTPC value for a given win amount
  double getRtpcForWin(double winAmount, double betAmount) {
    final tier = getTierForWin(winAmount, betAmount);
    return tier?.rtpcValue ?? 0.0;
  }

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'gameName': gameName,
        'tiers': tiers.map((t) => t.toJson()).toList(),
        'rtpcParameterName': rtpcParameterName,
        'defaultBaseBet': defaultBaseBet,
        'maxWinCap': maxWinCap,
        'useLogarithmicScaling': useLogarithmicScaling,
      };

  factory WinTierConfig.fromJson(Map<String, dynamic> json) {
    return WinTierConfig(
      gameId: json['gameId'] as String,
      gameName: json['gameName'] as String,
      tiers: (json['tiers'] as List<dynamic>)
          .map((t) => WinTierThreshold.fromJson(t as Map<String, dynamic>))
          .toList(),
      rtpcParameterName:
          json['rtpcParameterName'] as String? ?? 'winTier',
      defaultBaseBet: (json['defaultBaseBet'] as num?)?.toDouble() ?? 1.0,
      maxWinCap: (json['maxWinCap'] as num?)?.toDouble(),
      useLogarithmicScaling: json['useLogarithmicScaling'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory WinTierConfig.fromJsonString(String jsonString) {
    return WinTierConfig.fromJson(jsonDecode(jsonString));
  }
}

/// Default win tier configurations
class DefaultWinTierConfigs {
  /// Standard slot configuration (5x3 video slot)
  static WinTierConfig get standard => const WinTierConfig(
        gameId: 'standard',
        gameName: 'Standard Slot',
        tiers: [
          WinTierThreshold(
            tier: WinTier.noWin,
            minXBet: 0,
            maxXBet: 0.1,
            rtpcValue: 0.0,
          ),
          WinTierThreshold(
            tier: WinTier.smallWin,
            minXBet: 0.1,
            maxXBet: 2.0,
            rtpcValue: 0.2,
            triggerStage: 'WIN_SMALL',
          ),
          WinTierThreshold(
            tier: WinTier.mediumWin,
            minXBet: 2.0,
            maxXBet: 5.0,
            rtpcValue: 0.4,
            triggerStage: 'WIN_MEDIUM',
          ),
          WinTierThreshold(
            tier: WinTier.bigWin,
            minXBet: 5.0,
            maxXBet: 20.0,
            rtpcValue: 0.6,
            triggerStage: 'WIN_BIG',
            triggerCelebration: true,
            rollupDurationMultiplier: 1.5,
          ),
          WinTierThreshold(
            tier: WinTier.megaWin,
            minXBet: 20.0,
            maxXBet: 50.0,
            rtpcValue: 0.8,
            triggerStage: 'WIN_MEGA',
            triggerCelebration: true,
            rollupDurationMultiplier: 2.0,
          ),
          WinTierThreshold(
            tier: WinTier.epicWin,
            minXBet: 50.0,
            maxXBet: null,
            rtpcValue: 1.0,
            triggerStage: 'WIN_EPIC',
            triggerCelebration: true,
            rollupDurationMultiplier: 3.0,
          ),
        ],
      );

  /// High volatility slot configuration
  static WinTierConfig get highVolatility => const WinTierConfig(
        gameId: 'high_volatility',
        gameName: 'High Volatility Slot',
        tiers: [
          WinTierThreshold(
            tier: WinTier.noWin,
            minXBet: 0,
            maxXBet: 1.0,
            rtpcValue: 0.0,
          ),
          WinTierThreshold(
            tier: WinTier.smallWin,
            minXBet: 1.0,
            maxXBet: 5.0,
            rtpcValue: 0.15,
            triggerStage: 'WIN_SMALL',
          ),
          WinTierThreshold(
            tier: WinTier.mediumWin,
            minXBet: 5.0,
            maxXBet: 20.0,
            rtpcValue: 0.3,
            triggerStage: 'WIN_MEDIUM',
          ),
          WinTierThreshold(
            tier: WinTier.bigWin,
            minXBet: 20.0,
            maxXBet: 100.0,
            rtpcValue: 0.5,
            triggerStage: 'WIN_BIG',
            triggerCelebration: true,
            rollupDurationMultiplier: 2.0,
          ),
          WinTierThreshold(
            tier: WinTier.megaWin,
            minXBet: 100.0,
            maxXBet: 500.0,
            rtpcValue: 0.7,
            triggerStage: 'WIN_MEGA',
            triggerCelebration: true,
            rollupDurationMultiplier: 3.0,
          ),
          WinTierThreshold(
            tier: WinTier.epicWin,
            minXBet: 500.0,
            maxXBet: 1000.0,
            rtpcValue: 0.85,
            triggerStage: 'WIN_EPIC',
            triggerCelebration: true,
            rollupDurationMultiplier: 4.0,
          ),
          WinTierThreshold(
            tier: WinTier.ultraWin,
            minXBet: 1000.0,
            maxXBet: null,
            rtpcValue: 1.0,
            triggerStage: 'WIN_ULTRA',
            triggerCelebration: true,
            rollupDurationMultiplier: 5.0,
          ),
        ],
      );

  /// Jackpot slot configuration
  static WinTierConfig get jackpot => const WinTierConfig(
        gameId: 'jackpot',
        gameName: 'Jackpot Slot',
        tiers: [
          WinTierThreshold(
            tier: WinTier.noWin,
            minXBet: 0,
            maxXBet: 0.5,
            rtpcValue: 0.0,
          ),
          WinTierThreshold(
            tier: WinTier.smallWin,
            minXBet: 0.5,
            maxXBet: 3.0,
            rtpcValue: 0.15,
            triggerStage: 'WIN_SMALL',
          ),
          WinTierThreshold(
            tier: WinTier.mediumWin,
            minXBet: 3.0,
            maxXBet: 10.0,
            rtpcValue: 0.3,
            triggerStage: 'WIN_MEDIUM',
          ),
          WinTierThreshold(
            tier: WinTier.bigWin,
            minXBet: 10.0,
            maxXBet: 50.0,
            rtpcValue: 0.5,
            triggerStage: 'WIN_BIG',
            triggerCelebration: true,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotMini,
            minXBet: 50.0,
            maxXBet: 200.0,
            rtpcValue: 0.7,
            triggerStage: 'JACKPOT_MINI',
            triggerCelebration: true,
            rollupDurationMultiplier: 2.0,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotMinor,
            minXBet: 200.0,
            maxXBet: 1000.0,
            rtpcValue: 0.8,
            triggerStage: 'JACKPOT_MINOR',
            triggerCelebration: true,
            rollupDurationMultiplier: 3.0,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotMajor,
            minXBet: 1000.0,
            maxXBet: 5000.0,
            rtpcValue: 0.9,
            triggerStage: 'JACKPOT_MAJOR',
            triggerCelebration: true,
            rollupDurationMultiplier: 4.0,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotGrand,
            minXBet: 5000.0,
            maxXBet: null,
            rtpcValue: 1.0,
            triggerStage: 'JACKPOT_GRAND',
            triggerCelebration: true,
            rollupDurationMultiplier: 5.0,
          ),
        ],
      );
}

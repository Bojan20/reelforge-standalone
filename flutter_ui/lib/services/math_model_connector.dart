/// Math Model Connector Service (M4)
///
/// Connects slot game math model (paytable, win tiers) to the audio system.
/// Auto-generates RTPC thresholds from win tier configuration.
/// Links win tiers to attenuation curves for dynamic audio escalation.
///
/// Use cases:
/// - Import paytable → auto-generate RTPC thresholds
/// - Link win multipliers to audio intensity
/// - Sync rollup duration with win size
/// - Trigger appropriate stages based on win tier

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/win_tier_config.dart';

/// Result of RTPC threshold generation
class RtpcThresholdResult {
  final String rtpcName;
  final double minValue;
  final double maxValue;
  final List<RtpcThresholdPoint> points;

  const RtpcThresholdResult({
    required this.rtpcName,
    required this.minValue,
    required this.maxValue,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'rtpcName': rtpcName,
        'minValue': minValue,
        'maxValue': maxValue,
        'points': points.map((p) => p.toJson()).toList(),
      };
}

/// Single RTPC threshold point
class RtpcThresholdPoint {
  final double xBet;
  final double rtpcValue;
  final WinTier tier;

  const RtpcThresholdPoint({
    required this.xBet,
    required this.rtpcValue,
    required this.tier,
  });

  Map<String, dynamic> toJson() => {
        'xBet': xBet,
        'rtpcValue': rtpcValue,
        'tier': tier.name,
      };
}

/// Attenuation curve link configuration
class AttenuationCurveLink {
  final String curveName;
  final WinTier triggerTier;
  final double volumeMultiplier;
  final double fadeInMs;
  final double fadeOutMs;

  const AttenuationCurveLink({
    required this.curveName,
    required this.triggerTier,
    this.volumeMultiplier = 1.0,
    this.fadeInMs = 100.0,
    this.fadeOutMs = 500.0,
  });

  Map<String, dynamic> toJson() => {
        'curveName': curveName,
        'triggerTier': triggerTier.name,
        'volumeMultiplier': volumeMultiplier,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
      };
}

/// Math Model Connector Service
class MathModelConnector extends ChangeNotifier {
  static final MathModelConnector _instance = MathModelConnector._();
  static MathModelConnector get instance => _instance;

  MathModelConnector._();

  /// Active win tier configurations per game
  final Map<String, WinTierConfig> _configs = {};

  /// Generated RTPC thresholds
  final Map<String, RtpcThresholdResult> _rtpcThresholds = {};

  /// Attenuation curve links
  final List<AttenuationCurveLink> _curveLinks = [];

  /// Callback for RTPC value changes
  ValueChanged<double>? onRtpcChanged;

  /// Callback for stage triggers
  ValueChanged<String>? onStageTrigger;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a win tier configuration
  void registerConfig(WinTierConfig config) {
    _configs[config.gameId] = config;

    // Auto-generate RTPC thresholds
    final thresholds = generateRtpcThresholds(config);
    _rtpcThresholds[config.gameId] = thresholds;

    notifyListeners();
  }

  /// Get config for a game
  WinTierConfig? getConfig(String gameId) => _configs[gameId];

  /// Get all registered configs
  List<WinTierConfig> get configs => _configs.values.toList();

  /// Remove a config
  void removeConfig(String gameId) {
    _configs.remove(gameId);
    _rtpcThresholds.remove(gameId);
    notifyListeners();
  }

  /// Load default configurations
  void loadDefaults() {
    registerConfig(DefaultWinTierConfigs.standard);
    registerConfig(DefaultWinTierConfigs.highVolatility);
    registerConfig(DefaultWinTierConfigs.jackpot);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC THRESHOLD GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate RTPC thresholds from a win tier config
  RtpcThresholdResult generateRtpcThresholds(WinTierConfig config) {
    final points = <RtpcThresholdPoint>[];

    for (final tier in config.tiers) {
      points.add(RtpcThresholdPoint(
        xBet: tier.minXBet,
        rtpcValue: tier.rtpcValue,
        tier: tier.tier,
      ));
    }

    // Sort by xBet
    points.sort((a, b) => a.xBet.compareTo(b.xBet));

    return RtpcThresholdResult(
      rtpcName: config.rtpcParameterName,
      minValue: 0.0,
      maxValue: 1.0,
      points: points,
    );
  }

  /// Get RTPC thresholds for a game
  RtpcThresholdResult? getRtpcThresholds(String gameId) =>
      _rtpcThresholds[gameId];

  /// Calculate RTPC value for a given win
  double calculateRtpcValue(
    String gameId,
    double winAmount,
    double betAmount,
  ) {
    final config = _configs[gameId];
    if (config == null || betAmount <= 0) return 0.0;

    final xBet = winAmount / betAmount;
    final thresholds = _rtpcThresholds[gameId];
    if (thresholds == null) return 0.0;

    // Find the appropriate threshold point
    double rtpcValue = 0.0;
    for (final point in thresholds.points) {
      if (xBet >= point.xBet) {
        rtpcValue = point.rtpcValue;
      }
    }

    // Apply logarithmic scaling if enabled
    if (config.useLogarithmicScaling && xBet > 0) {
      // Log scale between min and max thresholds
      final maxXBet = config.tiers.last.minXBet;
      if (maxXBet > 1) {
        final logValue = _logScale(xBet, 0, maxXBet);
        rtpcValue = rtpcValue * 0.7 + logValue * 0.3;
      }
    }

    return rtpcValue.clamp(0.0, 1.0);
  }

  double _logScale(double value, double min, double max) {
    if (value <= min) return 0.0;
    if (value >= max) return 1.0;

    // Log scale: log(value) / log(max)
    final logValue = value > 0 ? (value / max).abs() : 0.0;
    return logValue.clamp(0.0, 1.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN PROCESSING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Process a win and trigger appropriate audio events
  WinProcessResult processWin(
    String gameId,
    double winAmount,
    double betAmount,
  ) {
    final config = _configs[gameId];
    if (config == null) {
      return WinProcessResult(
        tier: null,
        rtpcValue: 0.0,
        triggerStage: null,
        rollupDuration: 1000,
      );
    }

    // Get tier for this win
    final tier = config.getTierForWin(winAmount, betAmount);

    // Calculate RTPC value
    final rtpcValue = calculateRtpcValue(gameId, winAmount, betAmount);

    // Notify RTPC change
    onRtpcChanged?.call(rtpcValue);

    // Calculate rollup duration
    final baseDuration = 1000; // 1 second base
    final rollupDuration =
        (baseDuration * (tier?.rollupDurationMultiplier ?? 1.0)).round();

    // Trigger stage if configured
    if (tier?.triggerStage != null) {
      onStageTrigger?.call(tier!.triggerStage!);
    }


    return WinProcessResult(
      tier: tier,
      rtpcValue: rtpcValue,
      triggerStage: tier?.triggerStage,
      rollupDuration: rollupDuration,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ATTENUATION CURVE LINKING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add attenuation curve link
  void addCurveLink(AttenuationCurveLink link) {
    _curveLinks.add(link);
    notifyListeners();
  }

  /// Remove curve link
  void removeCurveLink(String curveName) {
    _curveLinks.removeWhere((l) => l.curveName == curveName);
    notifyListeners();
  }

  /// Get curve links for a tier
  List<AttenuationCurveLink> getCurveLinksForTier(WinTier tier) {
    return _curveLinks.where((l) => l.triggerTier == tier).toList();
  }

  /// Get all curve links
  List<AttenuationCurveLink> get curveLinks => List.unmodifiable(_curveLinks);

  /// Generate default curve links for a config
  List<AttenuationCurveLink> generateDefaultCurveLinks(WinTierConfig config) {
    final links = <AttenuationCurveLink>[];

    for (final tier in config.tiers) {
      if (tier.triggerCelebration) {
        links.add(AttenuationCurveLink(
          curveName: '${tier.tier.name}_celebration',
          triggerTier: tier.tier,
          volumeMultiplier: 1.0 + (tier.rtpcValue * 0.3),
          fadeInMs: 50 + (tier.rtpcValue * 200),
          fadeOutMs: 300 + (tier.rtpcValue * 700),
        ));
      }
    }

    return links;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAYTABLE IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import paytable from JSON and generate win tier config
  WinTierConfig? importPaytable(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Extract game info
      final gameId = json['gameId'] as String? ?? 'imported';
      final gameName = json['gameName'] as String? ?? 'Imported Game';

      // Extract win tiers or paylines
      List<WinTierThreshold> tiers;
      if (json.containsKey('winTiers')) {
        // Direct win tier format
        tiers = (json['winTiers'] as List<dynamic>)
            .map((t) => WinTierThreshold.fromJson(t as Map<String, dynamic>))
            .toList();
      } else if (json.containsKey('paylines')) {
        // Paytable format - derive tiers from paylines
        tiers = _deriveTiersFromPaylines(json['paylines'] as List<dynamic>);
      } else {
        // Use default standard tiers
        tiers = DefaultWinTierConfigs.standard.tiers;
      }

      final config = WinTierConfig(
        gameId: gameId,
        gameName: gameName,
        tiers: tiers,
        defaultBaseBet: (json['baseBet'] as num?)?.toDouble() ?? 1.0,
        maxWinCap: (json['maxWinCap'] as num?)?.toDouble(),
      );

      registerConfig(config);
      return config;
    } catch (e) {
      return null;
    }
  }

  List<WinTierThreshold> _deriveTiersFromPaylines(List<dynamic> paylines) {
    // Find max payout to determine tier boundaries
    double maxPayout = 0;
    for (final line in paylines) {
      final payout = (line['payout'] as num?)?.toDouble() ?? 0;
      if (payout > maxPayout) maxPayout = payout;
    }

    if (maxPayout <= 0) maxPayout = 1000;

    // Generate tiers based on max payout
    return [
      WinTierThreshold(
        tier: WinTier.noWin,
        minXBet: 0,
        maxXBet: 0.5,
        rtpcValue: 0.0,
      ),
      WinTierThreshold(
        tier: WinTier.smallWin,
        minXBet: 0.5,
        maxXBet: maxPayout * 0.05,
        rtpcValue: 0.2,
        triggerStage: 'WIN_SMALL',
      ),
      WinTierThreshold(
        tier: WinTier.mediumWin,
        minXBet: maxPayout * 0.05,
        maxXBet: maxPayout * 0.15,
        rtpcValue: 0.4,
        triggerStage: 'WIN_MEDIUM',
      ),
      WinTierThreshold(
        tier: WinTier.bigWin,
        minXBet: maxPayout * 0.15,
        maxXBet: maxPayout * 0.4,
        rtpcValue: 0.6,
        triggerStage: 'WIN_BIG',
        triggerCelebration: true,
      ),
      WinTierThreshold(
        tier: WinTier.megaWin,
        minXBet: maxPayout * 0.4,
        maxXBet: maxPayout * 0.7,
        rtpcValue: 0.8,
        triggerStage: 'WIN_MEGA',
        triggerCelebration: true,
        rollupDurationMultiplier: 2.0,
      ),
      WinTierThreshold(
        tier: WinTier.epicWin,
        minXBet: maxPayout * 0.7,
        maxXBet: null,
        rtpcValue: 1.0,
        triggerStage: 'WIN_EPIC',
        triggerCelebration: true,
        rollupDurationMultiplier: 3.0,
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all configs to JSON
  String exportToJson() {
    return jsonEncode({
      'configs': _configs.values.map((c) => c.toJson()).toList(),
      'curveLinks': _curveLinks.map((l) => l.toJson()).toList(),
    });
  }

  /// Import from JSON
  void importFromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Clear existing
      _configs.clear();
      _rtpcThresholds.clear();
      _curveLinks.clear();

      // Load configs
      final configs = json['configs'] as List<dynamic>?;
      if (configs != null) {
        for (final c in configs) {
          final config = WinTierConfig.fromJson(c as Map<String, dynamic>);
          registerConfig(config);
        }
      }

      // Load curve links
      final links = json['curveLinks'] as List<dynamic>?;
      if (links != null) {
        for (final l in links) {
          final link = l as Map<String, dynamic>;
          _curveLinks.add(AttenuationCurveLink(
            curveName: link['curveName'] as String,
            triggerTier: WinTier.values.firstWhere(
              (t) => t.name == link['triggerTier'],
              orElse: () => WinTier.noWin,
            ),
            volumeMultiplier: (link['volumeMultiplier'] as num?)?.toDouble() ?? 1.0,
            fadeInMs: (link['fadeInMs'] as num?)?.toDouble() ?? 100.0,
            fadeOutMs: (link['fadeOutMs'] as num?)?.toDouble() ?? 500.0,
          ));
        }
      }

      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  /// Clear all data
  void clear() {
    _configs.clear();
    _rtpcThresholds.clear();
    _curveLinks.clear();
    notifyListeners();
  }
}

/// Result of win processing
class WinProcessResult {
  final WinTierThreshold? tier;
  final double rtpcValue;
  final String? triggerStage;
  final int rollupDuration;

  const WinProcessResult({
    required this.tier,
    required this.rtpcValue,
    required this.triggerStage,
    required this.rollupDuration,
  });
}

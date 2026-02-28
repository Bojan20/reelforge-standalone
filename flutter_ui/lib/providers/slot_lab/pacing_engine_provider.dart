/// Pacing Engine Provider — Trostepeni Stage System
///
/// "Generate Audio Map From Math" — computes emotional/orchestration
/// presets from game mathematics (RTP, volatility, hit frequency, etc.)
///
/// Outputs a PacingTemplate that feeds into OrchestrationContext,
/// shaping how the middleware pipeline responds to gameplay events.
///
/// This is a DESIGN-TIME tool, not runtime. Sound designers set math
/// parameters once, and the engine generates audio behavior presets.
///
/// See: .claude/architecture/TROSTEPENI_STAGE_SYSTEM.md

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'orchestration_engine_provider.dart';
import 'emotional_state_provider.dart';

// =============================================================================
// PACING TEMPLATE (output)
// =============================================================================

/// Computed audio behavior preset from game math inputs
class PacingTemplate {
  /// Base tension level (0.0-1.0) — higher = more anticipation in base game
  final double baseTension;

  /// Escalation curve shape (1.0=linear, 2.0+=exponential)
  /// Higher volatility → sharper escalation peaks
  final double escalationCurve;

  /// Session fatigue growth rate (per minute)
  /// Higher hit frequency → faster fatigue (more repetition)
  final double sessionFatigueRate;

  /// Win tier thresholds (bet multipliers)
  /// e.g. [5x, 15x, 50x, 200x, 1000x]
  final List<double> winThresholds;

  /// Which reel begins anticipation buildup (0-indexed)
  /// Low frequency → earlier anticipation (reel 2), high → later (reel 4)
  final int anticipationStartReel;

  /// Maximum anticipation tension level (1-4)
  final int maxAnticipationLevel;

  /// Suggested emotional state durations (seconds)
  /// Adjusts how long each emotional state persists
  final Map<String, double> emotionalDurations;

  /// Gain envelope: how much dB swing on big wins
  final double maxGainSwingDb;

  /// Stereo width envelope: peak stereo width on features
  final double maxStereoWidth;

  const PacingTemplate({
    this.baseTension = 0.2,
    this.escalationCurve = 1.5,
    this.sessionFatigueRate = 0.01,
    this.winThresholds = const [5.0, 15.0, 50.0, 200.0, 1000.0],
    this.anticipationStartReel = 2,
    this.maxAnticipationLevel = 3,
    this.emotionalDurations = const {},
    this.maxGainSwingDb = 6.0,
    this.maxStereoWidth = 1.5,
  });
}

// =============================================================================
// VOLATILITY PROFILE
// =============================================================================

/// Predefined volatility profiles
enum VolatilityProfile {
  low('Low', 0.2),
  mediumLow('Medium-Low', 0.35),
  medium('Medium', 0.5),
  mediumHigh('Medium-High', 0.65),
  high('High', 0.8),
  extreme('Extreme', 0.95);

  const VolatilityProfile(this.displayName, this.value);
  final String displayName;
  final double value;
}

// =============================================================================
// PROVIDER
// =============================================================================

class PacingEngineProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // MATH INPUTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Return to Player percentage (0.90 - 0.99)
  double _rtp = 0.965;

  /// Volatility index (0.0 - 1.0)
  double _volatility = 0.5;

  /// Hit frequency (0.0 - 1.0, percentage of spins that win)
  double _hitFrequency = 0.30;

  /// Maximum win multiplier (e.g. 5000x, 10000x, 50000x)
  double _maxWin = 5000.0;

  /// Feature trigger frequency (1 in N spins)
  double _featureFrequency = 180.0;

  /// Number of reels
  int _reelCount = 5;

  /// Volatility profile preset
  VolatilityProfile _volatilityProfile = VolatilityProfile.medium;

  /// Last computed template (cached)
  PacingTemplate? _cachedTemplate;
  bool _templateDirty = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  double get rtp => _rtp;
  double get volatility => _volatility;
  double get hitFrequency => _hitFrequency;
  double get maxWin => _maxWin;
  double get featureFrequency => _featureFrequency;
  int get reelCount => _reelCount;
  VolatilityProfile get volatilityProfile => _volatilityProfile;

  /// Get or compute the pacing template
  PacingTemplate get template {
    if (_templateDirty || _cachedTemplate == null) {
      _cachedTemplate = _computeTemplate();
      _templateDirty = false;
    }
    return _cachedTemplate!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  void setRtp(double value) {
    _rtp = value.clamp(0.85, 0.995);
    _templateDirty = true;
    notifyListeners();
  }

  void setVolatility(double value) {
    _volatility = value.clamp(0.0, 1.0);
    // Auto-update profile
    _volatilityProfile = _closestProfile(value);
    _templateDirty = true;
    notifyListeners();
  }

  void setVolatilityProfile(VolatilityProfile profile) {
    _volatilityProfile = profile;
    _volatility = profile.value;
    _templateDirty = true;
    notifyListeners();
  }

  void setHitFrequency(double value) {
    _hitFrequency = value.clamp(0.05, 0.80);
    _templateDirty = true;
    notifyListeners();
  }

  void setMaxWin(double value) {
    _maxWin = value.clamp(100.0, 100000.0);
    _templateDirty = true;
    notifyListeners();
  }

  void setFeatureFrequency(double value) {
    _featureFrequency = value.clamp(10.0, 1000.0);
    _templateDirty = true;
    notifyListeners();
  }

  void setReelCount(int value) {
    _reelCount = value.clamp(3, 8);
    _templateDirty = true;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPLATE COMPUTATION
  // ═══════════════════════════════════════════════════════════════════════════

  PacingTemplate _computeTemplate() {
    // ── Base Tension ──
    // Low hit frequency = more time between wins = more tension in base game
    // Low RTP = player feels "losing" = more tension
    final hitTension = (1.0 - _hitFrequency).clamp(0.0, 1.0) * 0.5;
    final rtpTension = ((0.97 - _rtp) * 5.0).clamp(0.0, 0.3);
    final baseTension = (hitTension + rtpTension + _volatility * 0.2).clamp(0.0, 0.8);

    // ── Escalation Curve ──
    // High volatility → exponential (sharp peaks, quiet valleys)
    // Low volatility → linear (steady progression)
    final escalationCurve = 1.0 + _volatility * 2.0; // 1.0-3.0

    // ── Session Fatigue Rate ──
    // High hit frequency → more repetitive sounds → faster fatigue
    // Low volatility → more similar wins → faster fatigue
    final baseFatigue = 0.005; // per minute
    final hitFatigue = _hitFrequency * 0.02; // high hits = +0.016/min
    final volFatigue = (1.0 - _volatility) * 0.01; // low vol = +0.01/min
    final sessionFatigueRate = baseFatigue + hitFatigue + volFatigue;

    // ── Win Thresholds ──
    // Scale with maxWin to distribute tiers proportionally
    final tierScale = _maxWin / 5000.0; // normalized to 5000x base
    final winThresholds = [
      (5.0 * tierScale).clamp(2.0, 100.0),
      (15.0 * tierScale).clamp(10.0, 500.0),
      (50.0 * tierScale).clamp(25.0, 2000.0),
      (200.0 * tierScale).clamp(100.0, 10000.0),
      (1000.0 * tierScale).clamp(500.0, 50000.0),
    ];

    // ── Anticipation Timing ──
    // Low feature frequency → build anticipation earlier (more suspense per opportunity)
    // High frequency → later anticipation (less buildup needed)
    final freqNorm = (_featureFrequency / 500.0).clamp(0.0, 1.0);
    final startReel = (1 + (freqNorm * (_reelCount - 2)).round()).clamp(1, _reelCount - 1);

    // ── Max Anticipation Level ──
    // High volatility → can reach L4 (maximum tension)
    // Low volatility → caps at L2
    final maxLevel = (_volatility > 0.7) ? 4
        : (_volatility > 0.4) ? 3
        : 2;

    // ── Emotional Durations ──
    // High volatility → longer peak/afterglow (savor rare wins)
    // Low volatility → shorter durations (quick reset for next spin)
    final volDurationMod = 0.5 + _volatility; // 0.5x - 1.5x
    final emotionalDurations = {
      'build': 5.0 * volDurationMod,
      'tension': 4.0 * volDurationMod,
      'nearWin': 3.0 * volDurationMod,
      'release': 2.0 * volDurationMod,
      'peak': 8.0 * volDurationMod,
      'afterglow': 6.0 * volDurationMod,
      'recovery': 10.0 * volDurationMod,
    };

    // ── Gain Swing ──
    // Higher maxWin → more dramatic gain differences
    final gainSwing = (3.0 + math.log(_maxWin / 1000.0 + 1) * 3.0).clamp(3.0, 12.0);

    // ── Stereo Width ──
    // Higher volatility → wider stereo on wins (more dramatic)
    final stereoWidth = 1.0 + _volatility * 0.8; // 1.0-1.8

    return PacingTemplate(
      baseTension: baseTension,
      escalationCurve: escalationCurve,
      sessionFatigueRate: sessionFatigueRate,
      winThresholds: winThresholds,
      anticipationStartReel: startReel,
      maxAnticipationLevel: maxLevel,
      emotionalDurations: emotionalDurations,
      maxGainSwingDb: gainSwing,
      maxStereoWidth: stereoWidth,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ORCHESTRATION CONTEXT GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate an OrchestrationContext from the current template.
  /// This is the bridge between math inputs and the middleware pipeline.
  OrchestrationContext toOrchestrationContext({
    double currentEscalation = 0.0,
    int currentChainDepth = 0,
    double currentWinMagnitude = 0.0,
    double currentSessionMinutes = 0.0,
  }) {
    final t = template;

    // Session fatigue computed from rate and time
    final fatigue = (t.sessionFatigueRate * currentSessionMinutes).clamp(0.0, 1.0);

    return OrchestrationContext(
      emotionalOutput: EmotionalOutput(
        tension: t.baseTension,
        stereoWidthMod: t.maxStereoWidth,
      ),
      escalationIndex: currentEscalation,
      chainDepth: currentChainDepth,
      winMagnitude: currentWinMagnitude,
      sessionFatigue: fatigue,
      volatilityIndex: _volatility,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Low volatility classic slot (frequent small wins)
  void presetClassic() {
    _rtp = 0.960;
    _volatility = 0.2;
    _hitFrequency = 0.45;
    _maxWin = 1000.0;
    _featureFrequency = 300.0;
    _volatilityProfile = VolatilityProfile.low;
    _templateDirty = true;
    notifyListeners();
  }

  /// Medium volatility modern video slot
  void presetModern() {
    _rtp = 0.965;
    _volatility = 0.5;
    _hitFrequency = 0.30;
    _maxWin = 5000.0;
    _featureFrequency = 180.0;
    _volatilityProfile = VolatilityProfile.medium;
    _templateDirty = true;
    notifyListeners();
  }

  /// High volatility megaways-style slot
  void presetHighVol() {
    _rtp = 0.963;
    _volatility = 0.85;
    _hitFrequency = 0.20;
    _maxWin = 20000.0;
    _featureFrequency = 250.0;
    _volatilityProfile = VolatilityProfile.high;
    _templateDirty = true;
    notifyListeners();
  }

  /// Extreme volatility jackpot slot
  void presetExtreme() {
    _rtp = 0.950;
    _volatility = 0.95;
    _hitFrequency = 0.15;
    _maxWin = 50000.0;
    _featureFrequency = 400.0;
    _volatilityProfile = VolatilityProfile.extreme;
    _templateDirty = true;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'rtp': _rtp,
    'volatility': _volatility,
    'hitFrequency': _hitFrequency,
    'maxWin': _maxWin,
    'featureFrequency': _featureFrequency,
    'reelCount': _reelCount,
    'volatilityProfile': _volatilityProfile.name,
  };

  void fromJson(Map<String, dynamic> json) {
    _rtp = (json['rtp'] as num?)?.toDouble() ?? 0.965;
    _volatility = (json['volatility'] as num?)?.toDouble() ?? 0.5;
    _hitFrequency = (json['hitFrequency'] as num?)?.toDouble() ?? 0.30;
    _maxWin = (json['maxWin'] as num?)?.toDouble() ?? 5000.0;
    _featureFrequency = (json['featureFrequency'] as num?)?.toDouble() ?? 180.0;
    _reelCount = (json['reelCount'] as int?) ?? 5;
    final profileName = json['volatilityProfile'] as String?;
    _volatilityProfile = VolatilityProfile.values
        .where((p) => p.name == profileName)
        .firstOrNull ?? VolatilityProfile.medium;
    _templateDirty = true;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  VolatilityProfile _closestProfile(double value) {
    VolatilityProfile closest = VolatilityProfile.medium;
    double minDiff = double.infinity;
    for (final p in VolatilityProfile.values) {
      final diff = (p.value - value).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = p;
      }
    }
    return closest;
  }
}

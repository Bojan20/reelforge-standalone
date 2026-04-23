/// MathAudio Bridge Service — T2.5 + T2.8
///
/// THE heart of the MathAudio Bridge™.
/// Converts a PAR document into a complete audio event map with:
/// - Auto-generated events for all game states
/// - RTP-contribution-based audio weights
/// - Suggested audio tier (subtle/standard/prominent/flagship)
/// - Change notification system when PAR is updated
///
/// ## T2.8: Auto Audio Map Generator
/// PAR → complete AudioEventMap (all triggers, win tiers, features)
///
/// ## T2.5: Math-Audio Bridge Notification System
/// Notifies when imported PAR changes affect the audio map:
/// - New feature discovered (needs new audio event)
/// - Win tier thresholds recalibrated (existing events affected)
/// - RTP contribution shifts (audio weight changed)

import 'package:flutter/foundation.dart';
import 'par_import_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO EVENT MAP MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio importance tier — determines celebration scale
enum AudioTier {
  /// Background SFX, very subtle (audioWeight < 0.01)
  subtle,
  /// Normal celebration SFX (audioWeight 0.01–0.05)
  standard,
  /// Big win territory, notable audio (audioWeight 0.05–0.15)
  prominent,
  /// Jackpot-level, full orchestration (audioWeight > 0.15)
  flagship;

  String get displayName => switch (this) {
    AudioTier.subtle => 'Subtle',
    AudioTier.standard => 'Standard',
    AudioTier.prominent => 'Prominent',
    AudioTier.flagship => 'Flagship',
  };

  static AudioTier fromWeight(double weight) {
    if (weight >= 0.15) return AudioTier.flagship;
    if (weight >= 0.05) return AudioTier.prominent;
    if (weight >= 0.01) return AudioTier.standard;
    return AudioTier.subtle;
  }
}

/// Event category for grouping in UI
enum AudioEventCategory {
  baseGame,   // SPIN_START, REEL_SPIN, REEL_STOP, DEAD_SPIN
  win,        // WIN_LOW, WIN_1..WIN_5, WIN_EQUAL
  nearMiss,   // NEAR_MISS variants
  feature,    // FREE_SPIN_TRIGGER, BONUS_TRIGGER, etc.
  jackpot,    // JACKPOT_WON_* levels
  special,    // SCATTER, ANTICIPATION, WILD_EXPAND
}

/// A single audio event in the map
class AudioEvent {
  /// Stage/event name (e.g. "WIN_3", "FREE_SPIN_TRIGGER")
  final String name;

  /// Human-readable description
  final String description;

  /// Event category
  final AudioEventCategory category;

  /// Audio importance tier (drives celebration scale)
  final AudioTier tier;

  /// Audio weight (0.0–1.0 fraction of total RTP)
  final double audioWeight;

  /// Suggested voice count
  final int suggestedVoiceCount;

  /// Suggested duration in milliseconds
  final int suggestedDurationMs;

  /// Trigger probability per spin (from PAR, 0.0 if base game event)
  final double triggerProbability;

  /// RTP contribution fraction (0.0–1.0)
  final double rtpContribution;

  /// Is this event required for compliance? (REEL_SPIN, etc.)
  final bool isRequired;

  const AudioEvent({
    required this.name,
    required this.description,
    required this.category,
    required this.tier,
    required this.audioWeight,
    this.suggestedVoiceCount = 2,
    this.suggestedDurationMs = 1000,
    this.triggerProbability = 0.0,
    this.rtpContribution = 0.0,
    this.isRequired = false,
  });

  AudioEvent copyWith({AudioTier? tier, double? audioWeight}) => AudioEvent(
    name: name,
    description: description,
    category: category,
    tier: tier ?? this.tier,
    audioWeight: audioWeight ?? this.audioWeight,
    suggestedVoiceCount: suggestedVoiceCount,
    suggestedDurationMs: suggestedDurationMs,
    triggerProbability: triggerProbability,
    rtpContribution: rtpContribution,
    isRequired: isRequired,
  );
}

/// Complete audio event map generated from PAR
class AudioEventMap {
  final List<AudioEvent> events;
  final List<String> warnings;
  final List<String> missingCoverage;
  final ParDocument source;
  final DateTime generatedAt;

  const AudioEventMap({
    required this.events,
    required this.warnings,
    required this.missingCoverage,
    required this.source,
    required this.generatedAt,
  });

  /// Events by category
  List<AudioEvent> byCategory(AudioEventCategory cat) =>
      events.where((e) => e.category == cat).toList();

  /// Events by tier
  List<AudioEvent> byTier(AudioTier tier) =>
      events.where((e) => e.tier == tier).toList();

  /// Is the event map complete (no missing coverage)?
  bool get isComplete => missingCoverage.isEmpty;

  /// Total events generated
  int get eventCount => events.length;

  /// Coverage percentage (events present vs expected minimum)
  double get coveragePct {
    if (events.isEmpty) return 0.0;
    final requiredMissing = missingCoverage.length;
    final totalExpected = events.length + requiredMissing;
    return events.length / totalExpected.clamp(1, 999999);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// T2.5: BRIDGE NOTIFICATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Type of MathAudio Bridge notification
enum BridgeNotificationType {
  /// New feature in PAR needs audio coverage
  newFeatureDetected,
  /// Win tier thresholds changed after recalibration
  winTiersRecalibrated,
  /// RTP contribution shift changes audio weight of event
  audioWeightChanged,
  /// PAR imported successfully, full map generated
  mapGenerated,
  /// PAR validation warning that affects audio
  parValidationWarning,
}

/// A notification from the MathAudio Bridge system
class BridgeNotification {
  final BridgeNotificationType type;
  final String message;
  final String? affectedEvent;
  final DateTime timestamp;
  final bool isActionRequired;

  BridgeNotification({
    required this.type,
    required this.message,
    this.affectedEvent,
    required this.isActionRequired,
  }) : timestamp = DateTime.now();

  String get typeLabel => switch (type) {
    BridgeNotificationType.newFeatureDetected => 'NEW FEATURE',
    BridgeNotificationType.winTiersRecalibrated => 'TIERS UPDATED',
    BridgeNotificationType.audioWeightChanged => 'WEIGHT CHANGE',
    BridgeNotificationType.mapGenerated => 'MAP READY',
    BridgeNotificationType.parValidationWarning => 'PAR WARNING',
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// MathAudio Bridge Service — T2.5 + T2.8
class MathAudioBridgeService extends ChangeNotifier {
  AudioEventMap? _lastMap;
  AudioEventMap? get lastMap => _lastMap;

  final List<BridgeNotification> _notifications = [];
  List<BridgeNotification> get notifications => List.unmodifiable(_notifications);

  List<BridgeNotification> get unreadNotifications =>
      _notifications.where((n) => n.isActionRequired).toList();

  // ──────────────────────────────────────────────────────────────────────────
  // T2.8: Auto Audio Map Generator
  // ──────────────────────────────────────────────────────────────────────────

  /// Generate complete audio event map from PAR document.
  AudioEventMap generateEventMap(ParDocument par) {
    final events = <AudioEvent>[];
    final warnings = <String>[];
    final missingCoverage = <String>[];

    final totalRtp = par.rtpTarget / 100.0;

    // ── 1. Base game events ──────────────────────────────────────────────────
    events.addAll(_buildBaseGameEvents(par));

    // ── 2. Win tier events (using calibrated thresholds if available) ────────
    events.addAll(_buildWinTierEvents(par, totalRtp));

    // ── 3. Near-miss events ──────────────────────────────────────────────────
    events.addAll(_buildNearMissEvents(par));

    // ── 4. Feature-triggered events ──────────────────────────────────────────
    final (featureEvents, featureWarnings) = _buildFeatureEvents(par);
    events.addAll(featureEvents);
    warnings.addAll(featureWarnings);

    // ── 5. Jackpot events ────────────────────────────────────────────────────
    // ParDocument doesn't carry jackpot level detail — use default tiers
    // when any feature is tagged as jackpot type.
    if (par.features.any((f) => f.featureType == ParFeatureType.jackpot)) {
      events.addAll(_buildJackpotEvents(par));
    }

    // ── 6. Validate coverage ─────────────────────────────────────────────────
    final requiredStages = [
      'SPIN_START',
      'REEL_SPIN',
      'REEL_STOP',
      'WIN_1',
      'DEAD_SPIN',
    ];
    final eventNames = events.map((e) => e.name).toSet();
    for (final required in requiredStages) {
      if (!eventNames.contains(required)) {
        missingCoverage.add(required);
      }
    }

    // ── 7. Validate PAR completeness ─────────────────────────────────────────
    if (par.symbolCount == 0) {
      warnings.add('No symbol table in PAR — near-miss analysis limited');
    }
    if (par.hitFrequency == 0.0) {
      warnings.add('Hit frequency not specified in PAR');
    }

    final map = AudioEventMap(
      events: events,
      warnings: warnings,
      missingCoverage: missingCoverage,
      source: par,
      generatedAt: DateTime.now(),
    );

    // Compare with previous map for notifications (T2.5)
    _detectChanges(map);

    _lastMap = map;

    // Emit map generated notification
    _addNotification(BridgeNotification(
      type: BridgeNotificationType.mapGenerated,
      message: 'Audio map generated: ${events.length} events from "${par.gameName}"',
      isActionRequired: missingCoverage.isNotEmpty,
    ));

    notifyListeners();
    return map;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // T2.5: Notification management
  // ──────────────────────────────────────────────────────────────────────────

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  void markAllRead() {
    // In a real app, track read state per notification
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private: event builders
  // ──────────────────────────────────────────────────────────────────────────

  List<AudioEvent> _buildBaseGameEvents(ParDocument par) {
    final events = <AudioEvent>[];

    events.add(const AudioEvent(
      name: 'SPIN_START',
      description: 'Spin initiated (button press)',
      category: AudioEventCategory.baseGame,
      tier: AudioTier.subtle,
      audioWeight: 0.0,
      suggestedVoiceCount: 1,
      suggestedDurationMs: 150,
      isRequired: true,
    ));

    events.add(const AudioEvent(
      name: 'REEL_SPIN',
      description: 'Reels spinning ambient loop',
      category: AudioEventCategory.baseGame,
      tier: AudioTier.subtle,
      audioWeight: 0.0,
      suggestedVoiceCount: 2,
      suggestedDurationMs: 1500,
      isRequired: true,
    ));

    // Per-reel stop events
    for (var i = 0; i < par.reels; i++) {
      events.add(AudioEvent(
        name: 'REEL_STOP_$i',
        description: 'Reel $i stop click',
        category: AudioEventCategory.baseGame,
        tier: AudioTier.subtle,
        audioWeight: 0.0,
        suggestedVoiceCount: 1,
        suggestedDurationMs: 200,
        isRequired: i == 0,
      ));
    }

    // Generic REEL_STOP for backward compat
    events.add(const AudioEvent(
      name: 'REEL_STOP',
      description: 'Any reel stop (generic)',
      category: AudioEventCategory.baseGame,
      tier: AudioTier.subtle,
      audioWeight: 0.0,
      suggestedVoiceCount: 1,
      suggestedDurationMs: 200,
      isRequired: true,
    ));

    events.add(AudioEvent(
      name: 'DEAD_SPIN',
      description: 'No win on this spin',
      category: AudioEventCategory.baseGame,
      tier: AudioTier.subtle,
      audioWeight: 0.0,
      suggestedVoiceCount: 1,
      suggestedDurationMs: 300,
      triggerProbability: par.deadSpinFrequency,
      isRequired: true,
    ));

    events.add(const AudioEvent(
      name: 'SPIN_END',
      description: 'Spin resolution complete',
      category: AudioEventCategory.baseGame,
      tier: AudioTier.subtle,
      audioWeight: 0.0,
      suggestedVoiceCount: 1,
      suggestedDurationMs: 100,
    ));

    return events;
  }

  List<AudioEvent> _buildWinTierEvents(ParDocument par, double totalRtp) {
    final events = <AudioEvent>[];
    final baseRtp = par.rtpBreakdown.baseGameRtp > 0
        ? par.rtpBreakdown.baseGameRtp
        : totalRtp * 0.70;

    // WIN_LOW: sub-bet win — very common, very small RTP contribution
    final winLowWeight = (baseRtp * 0.10 / totalRtp.clamp(0.01, 1.0)).clamp(0.0, 1.0);
    events.add(AudioEvent(
      name: 'WIN_LOW',
      description: 'Sub-bet win (win < bet)',
      category: AudioEventCategory.win,
      tier: AudioTier.fromWeight(winLowWeight),
      audioWeight: winLowWeight,
      suggestedVoiceCount: 1,
      suggestedDurationMs: 300,
      triggerProbability: par.hitFrequency * 0.4,
      rtpContribution: winLowWeight,
    ));

    // WIN_EQUAL: exactly 1x bet — push
    events.add(AudioEvent(
      name: 'WIN_EQUAL',
      description: 'Push — win equals bet',
      category: AudioEventCategory.win,
      tier: AudioTier.subtle,
      audioWeight: 0.005,
      suggestedVoiceCount: 1,
      suggestedDurationMs: 400,
    ));

    // WIN_1 through WIN_5 — distribution derived from PAR RTP
    // RTP fraction assigned per tier using descending geometric series
    final winTierRtpFractions = [0.20, 0.18, 0.15, 0.10, 0.07]; // of baseRtp
    final winTierDurations = [800, 1200, 2000, 3500, 5000];
    final winTierVoices = [2, 3, 4, 5, 6];
    final winTierProbs = [
      par.hitFrequency * 0.25,
      par.hitFrequency * 0.12,
      par.hitFrequency * 0.06,
      par.hitFrequency * 0.02,
      par.hitFrequency * 0.005,
    ];

    for (var i = 1; i <= 5; i++) {
      final rtpFrac = winTierRtpFractions[i - 1];
      final weight = (baseRtp * rtpFrac / totalRtp.clamp(0.01, 1.0)).clamp(0.0, 1.0);
      events.add(AudioEvent(
        name: 'WIN_$i',
        description: 'Win tier $i',
        category: AudioEventCategory.win,
        tier: AudioTier.fromWeight(weight),
        audioWeight: weight,
        suggestedVoiceCount: winTierVoices[i - 1],
        suggestedDurationMs: winTierDurations[i - 1],
        triggerProbability: winTierProbs[i - 1],
        rtpContribution: baseRtp * rtpFrac,
      ));
    }

    // BIG_WIN_START — fired when WIN_5+ kicks into big win mode
    events.add(AudioEvent(
      name: 'BIG_WIN_START',
      description: 'Big win celebration begins',
      category: AudioEventCategory.win,
      tier: AudioTier.flagship,
      audioWeight: 0.20,
      suggestedVoiceCount: 8,
      suggestedDurationMs: 6000,
      triggerProbability: par.hitFrequency * 0.002,
    ));

    return events;
  }

  List<AudioEvent> _buildNearMissEvents(ParDocument par) {
    return [
      AudioEvent(
        name: 'NEAR_MISS',
        description: 'Near miss — 2/3 scatter visible',
        category: AudioEventCategory.nearMiss,
        tier: AudioTier.standard,
        audioWeight: 0.008,
        suggestedVoiceCount: 3,
        suggestedDurationMs: 800,
        triggerProbability: 0.12,
      ),
      const AudioEvent(
        name: 'ANTICIPATION',
        description: 'Reel lock / anticipation before stop',
        category: AudioEventCategory.nearMiss,
        tier: AudioTier.standard,
        audioWeight: 0.006,
        suggestedVoiceCount: 3,
        suggestedDurationMs: 1500,
      ),
      const AudioEvent(
        name: 'SCATTER',
        description: 'Scatter symbol landed',
        category: AudioEventCategory.special,
        tier: AudioTier.standard,
        audioWeight: 0.010,
        suggestedVoiceCount: 3,
        suggestedDurationMs: 800,
      ),
    ];
  }

  (List<AudioEvent>, List<String>) _buildFeatureEvents(ParDocument par) {
    final events = <AudioEvent>[];
    final warnings = <String>[];

    for (final feature in par.features) {
      final triggerProb = feature.triggerProbability;
      final rtpContrib = feature.rtpContribution;
      final totalRtp = par.rtpTarget / 100.0;
      final weight = totalRtp > 0 ? (rtpContrib / totalRtp).clamp(0.0, 1.0) : 0.0;
      final tier = AudioTier.fromWeight(weight);

      switch (feature.featureType) {
        case ParFeatureType.freeSpins:
          events.addAll([
            AudioEvent(
              name: 'FREE_SPIN_TRIGGER',
              description: 'Free spins triggered',
              category: AudioEventCategory.feature,
              tier: tier == AudioTier.subtle ? AudioTier.prominent : tier,
              audioWeight: weight,
              suggestedVoiceCount: 6,
              suggestedDurationMs: 4000,
              triggerProbability: triggerProb,
              rtpContribution: rtpContrib,
            ),
            AudioEvent(
              name: 'FREE_SPIN_START',
              description: 'Free spins mode begins',
              category: AudioEventCategory.feature,
              tier: AudioTier.prominent,
              audioWeight: weight * 0.3,
              suggestedVoiceCount: 5,
              suggestedDurationMs: 2000,
            ),
            AudioEvent(
              name: 'FREE_SPIN_WIN',
              description: 'Win during free spins',
              category: AudioEventCategory.feature,
              tier: AudioTier.standard,
              audioWeight: weight * 0.2,
              suggestedVoiceCount: 4,
              suggestedDurationMs: 1500,
            ),
            AudioEvent(
              name: 'FREE_SPIN_END',
              description: 'Free spins complete',
              category: AudioEventCategory.feature,
              tier: AudioTier.prominent,
              audioWeight: weight * 0.1,
              suggestedVoiceCount: 4,
              suggestedDurationMs: 2000,
            ),
            // Include retrigger event when PAR data indicates retrigger capability
            if (feature.retriggerProbability > 0)
              AudioEvent(
                name: 'FREE_SPIN_RETRIGGER',
                description: 'Free spins retriggered',
                category: AudioEventCategory.feature,
                tier: AudioTier.prominent,
                audioWeight: weight * 0.5,
                suggestedVoiceCount: 5,
                suggestedDurationMs: 2500,
                triggerProbability: feature.retriggerProbability,
              )
            else if (feature.avgPayoutMultiplier > 1.5)
              // Retrigger not specified — infer from high multiplier
              AudioEvent(
                name: 'FREE_SPIN_RETRIGGER',
                description: 'Free spins retriggered',
                category: AudioEventCategory.feature,
                tier: AudioTier.prominent,
                audioWeight: weight * 0.5,
                suggestedVoiceCount: 5,
                suggestedDurationMs: 2500,
                triggerProbability: triggerProb * 0.1,
              ),
          ]);

        case ParFeatureType.holdAndWin:
          events.addAll([
            AudioEvent(
              name: 'HOLD_AND_WIN_TRIGGER',
              description: 'Hold & Win feature triggered',
              category: AudioEventCategory.feature,
              tier: tier == AudioTier.subtle ? AudioTier.prominent : tier,
              audioWeight: weight,
              suggestedVoiceCount: 6,
              suggestedDurationMs: 3500,
              triggerProbability: triggerProb,
              rtpContribution: rtpContrib,
            ),
            const AudioEvent(
              name: 'HOLD_AND_WIN_COIN_LAND',
              description: 'Coin lands on grid',
              category: AudioEventCategory.feature,
              tier: AudioTier.standard,
              audioWeight: 0.005,
              suggestedVoiceCount: 2,
              suggestedDurationMs: 400,
            ),
            const AudioEvent(
              name: 'HOLD_AND_WIN_RESPIN',
              description: 'Respin in Hold & Win mode',
              category: AudioEventCategory.feature,
              tier: AudioTier.standard,
              audioWeight: 0.003,
              suggestedVoiceCount: 2,
              suggestedDurationMs: 600,
            ),
          ]);

        case ParFeatureType.cascade:
          events.addAll([
            AudioEvent(
              name: 'CASCADE_START',
              description: 'Cascade/avalanche begins',
              category: AudioEventCategory.feature,
              tier: AudioTier.standard,
              audioWeight: weight,
              suggestedVoiceCount: 3,
              suggestedDurationMs: 800,
              triggerProbability: triggerProb,
              rtpContribution: rtpContrib,
            ),
            AudioEvent(
              name: 'CASCADE_WIN',
              description: 'Win in cascade sequence',
              category: AudioEventCategory.feature,
              tier: AudioTier.standard,
              audioWeight: weight * 0.6,
              suggestedVoiceCount: 3,
              suggestedDurationMs: 700,
            ),
          ]);

        case ParFeatureType.gamble:
          events.addAll([
            const AudioEvent(
              name: 'GAMBLE_AVAILABLE',
              description: 'Gamble option presented',
              category: AudioEventCategory.feature,
              tier: AudioTier.subtle,
              audioWeight: 0.002,
              suggestedVoiceCount: 2,
              suggestedDurationMs: 500,
            ),
            const AudioEvent(
              name: 'GAMBLE_WIN',
              description: 'Gamble successful — win doubled',
              category: AudioEventCategory.feature,
              tier: AudioTier.standard,
              audioWeight: 0.015,
              suggestedVoiceCount: 3,
              suggestedDurationMs: 1200,
            ),
            const AudioEvent(
              name: 'GAMBLE_LOSE',
              description: 'Gamble failed — win lost',
              category: AudioEventCategory.feature,
              tier: AudioTier.subtle,
              audioWeight: 0.001,
              suggestedVoiceCount: 1,
              suggestedDurationMs: 800,
            ),
          ]);

        case ParFeatureType.bonus:
        case ParFeatureType.pickBonus:
          events.addAll([
            AudioEvent(
              name: 'BONUS_TRIGGER',
              description: '${feature.name.isEmpty ? "Bonus" : feature.name} triggered',
              category: AudioEventCategory.feature,
              tier: tier == AudioTier.subtle ? AudioTier.prominent : tier,
              audioWeight: weight,
              suggestedVoiceCount: 5,
              suggestedDurationMs: 3000,
              triggerProbability: triggerProb,
              rtpContribution: rtpContrib,
            ),
            const AudioEvent(
              name: 'BONUS_WIN',
              description: 'Win revealed in bonus',
              category: AudioEventCategory.feature,
              tier: AudioTier.standard,
              audioWeight: 0.02,
              suggestedVoiceCount: 3,
              suggestedDurationMs: 1000,
            ),
          ]);

        case ParFeatureType.wheelBonus:
          events.add(AudioEvent(
            name: 'WHEEL_SPIN',
            description: 'Bonus wheel spinning',
            category: AudioEventCategory.feature,
            tier: AudioTier.prominent,
            audioWeight: weight,
            suggestedVoiceCount: 4,
            suggestedDurationMs: 3000,
            triggerProbability: triggerProb,
          ));

        default:
          // Generic feature
          if (triggerProb > 0 || rtpContrib > 0) {
            final featureName = feature.name.isNotEmpty
                ? feature.name.toUpperCase().replaceAll(' ', '_')
                : 'FEATURE_TRIGGER';
            events.add(AudioEvent(
              name: featureName,
              description: 'Feature trigger: ${feature.name}',
              category: AudioEventCategory.feature,
              tier: tier,
              audioWeight: weight,
              suggestedVoiceCount: 4,
              suggestedDurationMs: 2500,
              triggerProbability: triggerProb,
              rtpContribution: rtpContrib,
            ));
          }
      }
    }

    return (events, warnings);
  }

  List<AudioEvent> _buildJackpotEvents(ParDocument par) {
    final normalizer = (par.rtpTarget / 100.0).clamp(0.01, 1.0);

    // T2.7: Use jackpotLevels (ParJackpotLevel) when available — these carry
    // per-level name, seed, trigger probability, and RTP contribution.
    if (par.jackpotLevels.isNotEmpty) {
      return par.jackpotLevels.map((level) {
        final levelName = level.name.toUpperCase().replaceAll(' ', '_');
        final weight = level.rtpContribution > 0
            ? (level.rtpContribution / normalizer).clamp(0.0, 1.0)
            : 0.10;
        // Duration scales with jackpot importance:
        // MINI=6s, MINOR=8s, MAJOR=10s, GRAND=15s, MEGA=20s
        final durationMs = switch (levelName) {
          'MINI' => 6000,
          'MINOR' => 8000,
          'MAJOR' => 10000,
          'GRAND' || 'MEGA' => 15000,
          _ => 10000,
        };
        return AudioEvent(
          name: 'JACKPOT_WON_$levelName',
          description: 'Jackpot won: ${level.name}',
          category: AudioEventCategory.jackpot,
          tier: AudioTier.flagship,
          audioWeight: weight,
          suggestedVoiceCount: 8,
          suggestedDurationMs: durationMs,
          triggerProbability: level.triggerProbability,
          rtpContribution: level.rtpContribution,
        );
      }).toList();
    }

    // Fall back to jackpot features with named levels
    final jackpotFeatures = par.features
        .where((f) => f.featureType == ParFeatureType.jackpot && f.name.isNotEmpty)
        .toList();

    if (jackpotFeatures.isNotEmpty) {
      return jackpotFeatures.map((f) {
        final levelName = f.name.toUpperCase().replaceAll(' ', '_');
        final weight = f.rtpContribution > 0
            ? (f.rtpContribution / normalizer).clamp(0.0, 1.0)
            : 0.10;
        return AudioEvent(
          name: 'JACKPOT_WON_$levelName',
          description: 'Jackpot won: ${f.name}',
          category: AudioEventCategory.jackpot,
          tier: AudioTier.flagship,
          audioWeight: weight,
          suggestedVoiceCount: 8,
          suggestedDurationMs: 10000,
          triggerProbability: f.triggerProbability,
          rtpContribution: f.rtpContribution,
        );
      }).toList();
    }

    // Ultimate fallback: standard MINI/MINOR/MAJOR/GRAND
    return _buildDefaultJackpotEvents();
  }

  List<AudioEvent> _buildDefaultJackpotEvents() {
    return [
      const AudioEvent(
        name: 'JACKPOT_WON_MINI',
        description: 'Mini jackpot won',
        category: AudioEventCategory.jackpot,
        tier: AudioTier.prominent,
        audioWeight: 0.02,
        suggestedVoiceCount: 6,
        suggestedDurationMs: 6000,
      ),
      const AudioEvent(
        name: 'JACKPOT_WON_MINOR',
        description: 'Minor jackpot won',
        category: AudioEventCategory.jackpot,
        tier: AudioTier.flagship,
        audioWeight: 0.05,
        suggestedVoiceCount: 7,
        suggestedDurationMs: 8000,
      ),
      const AudioEvent(
        name: 'JACKPOT_WON_MAJOR',
        description: 'Major jackpot won',
        category: AudioEventCategory.jackpot,
        tier: AudioTier.flagship,
        audioWeight: 0.10,
        suggestedVoiceCount: 8,
        suggestedDurationMs: 10000,
      ),
      const AudioEvent(
        name: 'JACKPOT_WON_GRAND',
        description: 'Grand jackpot won',
        category: AudioEventCategory.jackpot,
        tier: AudioTier.flagship,
        audioWeight: 0.20,
        suggestedVoiceCount: 8,
        suggestedDurationMs: 15000,
      ),
    ];
  }

  // ──────────────────────────────────────────────────────────────────────────
  // T2.5: Change detection
  // ──────────────────────────────────────────────────────────────────────────

  void _detectChanges(AudioEventMap newMap) {
    final previous = _lastMap;
    if (previous == null) return;

    final prevNames = previous.events.map((e) => e.name).toSet();
    final newNames = newMap.events.map((e) => e.name).toSet();

    // New events detected
    for (final name in newNames.difference(prevNames)) {
      _addNotification(BridgeNotification(
        type: BridgeNotificationType.newFeatureDetected,
        message: 'New audio event needed: $name — assign audio asset',
        affectedEvent: name,
        isActionRequired: true,
      ));
    }

    // Audio weight changes (> 20% relative change)
    final prevMap = {for (final e in previous.events) e.name: e};
    for (final event in newMap.events) {
      final prev = prevMap[event.name];
      if (prev != null && prev.audioWeight > 0.001) {
        final delta = (event.audioWeight - prev.audioWeight).abs() / prev.audioWeight;
        if (delta > 0.20) {
          _addNotification(BridgeNotification(
            type: BridgeNotificationType.audioWeightChanged,
            message: '${event.name} audio weight changed '
                '${(prev.audioWeight * 100).toStringAsFixed(1)}% → '
                '${(event.audioWeight * 100).toStringAsFixed(1)}% — '
                'review celebration scale',
            affectedEvent: event.name,
            isActionRequired: false,
          ));
        }
      }
    }
  }

  void _addNotification(BridgeNotification notification) {
    _notifications.insert(0, notification);
    // Keep last 50 notifications
    if (_notifications.length > 50) {
      _notifications.removeRange(50, _notifications.length);
    }
  }
}

/// Voice Budget Analyzer Service — T2.6
///
/// Analytical peak voice prediction from math model + AudioEventMap.
/// NO simulation required — O(n) on event count, runs in microseconds.
///
/// Theory: For a Poisson arrival process, E[concurrent voices] for event E =
///   λ_E × μ_E  (Little's Law)
/// where:
///   λ_E = trigger probability per spin × voices_per_event
///   μ_E = duration_ms / avg_spin_cycle_ms
///
/// Peak is estimated as expected + 3σ (99.7th percentile) assuming
/// Poisson-distributed arrivals.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'math_audio_bridge_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Risk classification for voice budget usage
enum BudgetRisk {
  /// < 50% of budget — comfortable headroom
  low,
  /// 50–75% of budget — watch but OK
  medium,
  /// 75–90% of budget — consider optimization
  high,
  /// > 90% of budget — will likely exceed under load
  critical;

  String get displayName => switch (this) {
    BudgetRisk.low => 'Low Risk',
    BudgetRisk.medium => 'Medium Risk',
    BudgetRisk.high => 'High Risk',
    BudgetRisk.critical => 'Critical',
  };

  int get colorValue => switch (this) {
    BudgetRisk.low => 0xFF4CAF50,
    BudgetRisk.medium => 0xFFFFEB3B,
    BudgetRisk.high => 0xFFFF9800,
    BudgetRisk.critical => 0xFFF44336,
  };
}

/// Per-event voice contribution breakdown
class EventVoiceContribution {
  /// Event name (e.g. "WIN_3", "FREE_SPIN_TRIGGER")
  final String eventName;

  /// Expected concurrent voices from this event alone (Little's Law)
  final double expectedConcurrent;

  /// 99.7th percentile peak contribution
  final double peakContribution;

  /// Voices per occurrence
  final int voicesPerOccurrence;

  /// Trigger probability per spin
  final double triggerProbability;

  /// Duration in milliseconds
  final int durationMs;

  const EventVoiceContribution({
    required this.eventName,
    required this.expectedConcurrent,
    required this.peakContribution,
    required this.voicesPerOccurrence,
    required this.triggerProbability,
    required this.durationMs,
  });
}

/// Complete analytical voice budget analysis
class VoiceBudgetAnalysis {
  /// Expected simultaneous voices under normal play (Little's Law sum)
  final double expectedPeakVoices;

  /// 99.7th percentile estimate (expected + 3σ Poisson)
  final double statisticalPeakVoices;

  /// Absolute worst case — all events fire in same frame
  final int absoluteWorstCase;

  /// Recommended voice budget (statistical peak × 1.25 safety factor, ≥16)
  final int recommendedBudget;

  /// Risk level vs standard 48-voice budget
  final BudgetRisk riskVs48;

  /// Risk level vs recommended budget
  final BudgetRisk riskVsRecommended;

  /// Per-event breakdown (sorted by peakContribution, descending)
  final List<EventVoiceContribution> perEventBreakdown;

  /// Assumptions used (spin cycle ms, player archetype)
  final String assumptions;

  /// Warnings from analysis
  final List<String> warnings;

  const VoiceBudgetAnalysis({
    required this.expectedPeakVoices,
    required this.statisticalPeakVoices,
    required this.absoluteWorstCase,
    required this.recommendedBudget,
    required this.riskVs48,
    required this.riskVsRecommended,
    required this.perEventBreakdown,
    required this.assumptions,
    this.warnings = const [],
  });

  /// Top N voice consumers (by peak contribution)
  List<EventVoiceContribution> topConsumers({int n = 5}) =>
      perEventBreakdown.take(n).toList();

  /// Utilization fraction vs 48-voice budget
  double get utilization48 => statisticalPeakVoices / 48.0;

  /// Utilization fraction vs recommended budget
  double get utilizationRecommended =>
      statisticalPeakVoices / recommendedBudget.clamp(1, 999);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANALYZER
// ═══════════════════════════════════════════════════════════════════════════════

/// Analytical voice budget prediction from AudioEventMap.
///
/// Does NOT run simulation — uses queuing theory (Little's Law) for O(n) speed.
class VoiceBudgetAnalyzerService extends ChangeNotifier {
  VoiceBudgetAnalysis? _lastAnalysis;
  VoiceBudgetAnalysis? get lastAnalysis => _lastAnalysis;

  /// Analyze an AudioEventMap for peak voice usage.
  ///
  /// [map] — the audio event map (from MathAudioBridgeService)
  /// [spinCycleMs] — estimated time per spin cycle in ms (default 3000ms = standard)
  /// [playerArchetype] — 'casual' (4s), 'regular' (3s), 'turbo' (1.5s)
  VoiceBudgetAnalysis analyze(
    AudioEventMap map, {
    String playerArchetype = 'regular',
    int? spinCycleMsOverride,
  }) {
    final spinMs = spinCycleMsOverride ?? _spinCycleMs(playerArchetype);
    final warnings = <String>[];
    final contributions = <EventVoiceContribution>[];

    // ── Apply Little's Law per event ─────────────────────────────────────────
    // E[concurrent] = λ × μ
    // λ = trigger_probability_per_spin × voices_per_event
    // μ = duration_ms / spin_cycle_ms  (average service time in spin units)
    double totalExpected = 0.0;
    double totalVariance = 0.0;
    int absoluteWorstCase = 0;

    for (final event in map.events) {
      final lambda = event.triggerProbability > 0
          ? event.triggerProbability
          : _estimateTriggerProbability(event);

      if (lambda <= 0.0) continue;

      final voices = event.suggestedVoiceCount.clamp(1, 32);
      final duration = event.suggestedDurationMs.clamp(50, 60000);

      // Occupancy fraction: fraction of spin cycle this event "holds" voices
      final occupancy = duration / spinMs.clamp(1, 60000);

      // Expected concurrent voices from this event
      final expectedConcurrent = lambda * voices * occupancy;

      // For Poisson: Var = E[N] (mean = variance)
      // Peak estimate (99.7% = mean + 3σ, σ = sqrt(λ × μ) for Poisson)
      final peakContribution =
          expectedConcurrent + 3.0 * math.sqrt(expectedConcurrent.clamp(0, double.infinity));

      contributions.add(EventVoiceContribution(
        eventName: event.name,
        expectedConcurrent: expectedConcurrent,
        peakContribution: peakContribution,
        voicesPerOccurrence: voices,
        triggerProbability: lambda,
        durationMs: duration,
      ));

      totalExpected += expectedConcurrent;
      totalVariance += lambda * voices * occupancy; // Poisson: var = mean
      absoluteWorstCase += voices;
    }

    // ── System-level peak estimate ───────────────────────────────────────────
    // System Poisson: total expected + 3√(total variance)
    final systemStddev = math.sqrt(totalVariance);
    final statisticalPeak = totalExpected + 3.0 * systemStddev;

    // ── Recommended budget ───────────────────────────────────────────────────
    // 1.25× safety factor, round up to next multiple of 8, minimum 16
    final rawRecommended = (statisticalPeak * 1.25).ceil();
    final recommended = (((rawRecommended + 7) ~/ 8) * 8).clamp(16, 256);

    // ── Risk levels ──────────────────────────────────────────────────────────
    final riskVs48 = _riskFromUtilization(statisticalPeak / 48.0);
    final riskVsRecommended = _riskFromUtilization(statisticalPeak / recommended);

    // ── Warnings ─────────────────────────────────────────────────────────────
    if (statisticalPeak > 48) {
      warnings.add(
        'Statistical peak ${statisticalPeak.toStringAsFixed(1)} exceeds '
        'standard 48-voice budget — run batch simulation to verify',
      );
    }
    if (absoluteWorstCase > 128) {
      warnings.add(
        'Worst case simultaneous voice count is $absoluteWorstCase — '
        'ensure audio middleware has appropriate pool size',
      );
    }
    final highDurationEvents = contributions
        .where((c) => c.durationMs > 10000 && c.triggerProbability > 0.001)
        .toList();
    for (final e in highDurationEvents) {
      warnings.add(
        '${e.eventName} has ${(e.durationMs / 1000).toStringAsFixed(1)}s '
        'duration — may stack with itself if not exclusive',
      );
    }

    // ── Sort breakdown by peak contribution, descending ──────────────────────
    contributions.sort((a, b) => b.peakContribution.compareTo(a.peakContribution));

    final analysis = VoiceBudgetAnalysis(
      expectedPeakVoices: totalExpected,
      statisticalPeakVoices: statisticalPeak,
      absoluteWorstCase: absoluteWorstCase,
      recommendedBudget: recommended,
      riskVs48: riskVs48,
      riskVsRecommended: riskVsRecommended,
      perEventBreakdown: contributions,
      assumptions:
          'Player: $playerArchetype (${spinMs}ms/spin), '
          '${map.eventCount} events, '
          '99.7th percentile Poisson estimate',
      warnings: warnings,
    );

    _lastAnalysis = analysis;
    notifyListeners();
    return analysis;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  int _spinCycleMs(String archetype) => switch (archetype) {
    'turbo' => 1500,
    'casual' => 4000,
    _ => 3000, // 'regular'
  };

  /// Fallback trigger probability estimate for base game events
  /// (triggerProbability = 0.0 for always-firing events like SPIN_START)
  double _estimateTriggerProbability(AudioEvent event) =>
    switch (event.name) {
      'SPIN_START' || 'SPIN_END' => 1.0,
      'REEL_SPIN' => 1.0,
      'REEL_STOP' => 1.0,
      'DEAD_SPIN' => 0.35,  // ~35% dead spins is industry norm
      'NEAR_MISS' => 0.12,
      'ANTICIPATION' => 0.08,
      'SCATTER' => 0.20,
      _ when event.name.startsWith('REEL_STOP_') => 1.0,
      _ when event.name.startsWith('WIN_') => 0.05,
      _ when event.name.startsWith('JACKPOT_') => 0.0001,
      _ => 0.0,
    };

  BudgetRisk _riskFromUtilization(double utilization) {
    if (utilization >= 0.90) return BudgetRisk.critical;
    if (utilization >= 0.75) return BudgetRisk.high;
    if (utilization >= 0.50) return BudgetRisk.medium;
    return BudgetRisk.low;
  }
}

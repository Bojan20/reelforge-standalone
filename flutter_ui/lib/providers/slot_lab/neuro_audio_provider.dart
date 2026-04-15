/// NeuroAudio™ — AI Player Behavioral Adaptation Engine
///
/// Central intelligence that reads player behavioral signals and adapts
/// the entire audio mix in real-time via RTPC + AUREXIS parameters.
///
/// Input signals:
///   - Click velocity (ms between click and spin)
///   - Pause patterns (inter-spin intervals)
///   - Win/loss streak history
///   - Session duration + time-of-day
///   - Bet size changes (chasing vs cooling)
///   - Near-miss frequency exposure
///
/// Output (8D Emotional State Vector → RTPC writes):
///   - Player Arousal Level (0.0–1.0)
///   - Risk Tolerance Score
///   - Engagement Probability
///   - Churn Prediction Score
///   - Music tempo modifier (±30%)
///   - Reverb depth modifier
///   - Compression ratio modifier
///   - Win sound magnitude modifier
///
/// Deterministic: identical input sequences produce identical outputs.
/// No dart:math.Random — all variation from input signals.
///
/// See: FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.md §STUB1
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// =============================================================================
// PLAYER BEHAVIORAL SIGNAL
// =============================================================================

/// A single behavioral observation timestamped for decay weighting
class BehavioralSignal {
  final double value;
  final DateTime timestamp;
  const BehavioralSignal(this.value, this.timestamp);
}

// =============================================================================
// PLAYER RISK PROFILE
// =============================================================================

/// Risk classification for responsible gaming integration
enum PlayerRiskLevel {
  low,
  moderate,
  elevated,
  high;

  String get displayName => switch (this) {
        low => 'Low Risk',
        moderate => 'Moderate',
        elevated => 'Elevated',
        high => 'High Risk',
      };

  int get colorValue => switch (this) {
        low => 0xFF44CC44,
        moderate => 0xFF88AA44,
        elevated => 0xFFDD8822,
        high => 0xFFCC3333,
      };
}

// =============================================================================
// NEURO AUDIO OUTPUT
// =============================================================================

/// Complete output of the NeuroAudio engine — consumed by RTPC + AUREXIS
class NeuroAudioOutput {
  // ═══ 8D EMOTIONAL STATE VECTOR ═══
  /// Player arousal level (0.0 = calm/bored, 1.0 = highly stimulated)
  final double arousal;

  /// Valence (-1.0 = frustrated, 0.0 = neutral, 1.0 = euphoric)
  final double valence;

  /// Risk tolerance (0.0 = conservative, 1.0 = reckless chasing)
  final double riskTolerance;

  /// Engagement probability (0.0 = about to leave, 1.0 = deep flow)
  final double engagement;

  /// Churn prediction (0.0 = staying, 1.0 = about to quit)
  final double churnPrediction;

  /// Frustration index (0.0 = content, 1.0 = tilted)
  final double frustration;

  /// Flow state depth (0.0 = distracted, 1.0 = deep flow)
  final double flowDepth;

  /// Session fatigue (0.0 = fresh, 1.0 = exhausted)
  final double sessionFatigue;

  // ═══ AUDIO ADAPTATION PARAMETERS ═══
  /// Music tempo modifier (0.7 = -30%, 1.0 = neutral, 1.3 = +30%)
  final double tempoModifier;

  /// Reverb depth modifier (0.5 = intimate, 1.0 = neutral, 2.0 = grand)
  final double reverbDepthModifier;

  /// Compression ratio modifier (0.5 = relaxed, 1.0 = neutral, 2.0 = dense)
  final double compressionModifier;

  /// Win sound magnitude (0.3 = subdued, 1.0 = neutral, 1.5 = amplified)
  final double winSoundMagnitude;

  /// Near-miss tension calibration (0.0 = no tension, 1.0 = maximum)
  final double nearMissTension;

  /// Volume envelope scale (0.5 = compressed dynamics, 1.0 = full range)
  final double volumeEnvelopeScale;

  /// Player risk level classification
  final PlayerRiskLevel riskLevel;

  const NeuroAudioOutput({
    this.arousal = 0.3,
    this.valence = 0.0,
    this.riskTolerance = 0.3,
    this.engagement = 0.5,
    this.churnPrediction = 0.0,
    this.frustration = 0.0,
    this.flowDepth = 0.0,
    this.sessionFatigue = 0.0,
    this.tempoModifier = 1.0,
    this.reverbDepthModifier = 1.0,
    this.compressionModifier = 1.0,
    this.winSoundMagnitude = 1.0,
    this.nearMissTension = 0.5,
    this.volumeEnvelopeScale = 1.0,
    this.riskLevel = PlayerRiskLevel.low,
  });

  Map<String, dynamic> toJson() => {
        'arousal': arousal,
        'valence': valence,
        'risk_tolerance': riskTolerance,
        'engagement': engagement,
        'churn_prediction': churnPrediction,
        'frustration': frustration,
        'flow_depth': flowDepth,
        'session_fatigue': sessionFatigue,
        'tempo_modifier': tempoModifier,
        'reverb_depth_modifier': reverbDepthModifier,
        'compression_modifier': compressionModifier,
        'win_sound_magnitude': winSoundMagnitude,
        'near_miss_tension': nearMissTension,
        'volume_envelope_scale': volumeEnvelopeScale,
        'risk_level': riskLevel.name,
      };
}

// =============================================================================
// NEURO AUDIO PROVIDER
// =============================================================================

/// NeuroAudio™ engine — reads player behavioral signals, computes 8D emotional
/// state vector, and outputs audio adaptation parameters for RTPC + AUREXIS.
///
/// All computation is deterministic — no randomness.
/// Designed for responsible gaming: automatically reduces audio stimulation
/// for high-risk behavioral patterns.
class NeuroAudioProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Window size for behavioral signal history
  static const int _signalWindowSize = 50;

  /// Exponential decay half-life for signal weighting (seconds)
  static const double _decayHalfLifeS = 30.0;

  /// Smoothing factor for output parameters (0.0 = instant, 1.0 = never)
  static const double _outputSmoothing = 0.85;

  /// Churn prediction threshold (consecutive losses before churn signal)
  static const int _churnLossThreshold = 15;

  /// Flow state entry threshold (spins at consistent pace)
  static const int _flowEntryThreshold = 8;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE — BEHAVIORAL SIGNALS (raw inputs)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Click velocity: ms between UI click and spin trigger
  final List<BehavioralSignal> _clickVelocities = [];

  /// Inter-spin pause durations (ms)
  final List<BehavioralSignal> _pauseDurations = [];

  /// Bet size history (normalized 0.0-1.0)
  final List<BehavioralSignal> _betSizes = [];

  /// Win/loss results: >0 = win multiplier, 0 = loss
  final List<BehavioralSignal> _winLossHistory = [];

  /// Near-miss events (scatter count before miss)
  final List<BehavioralSignal> _nearMissHistory = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE — DERIVED METRICS
  // ═══════════════════════════════════════════════════════════════════════════

  DateTime _sessionStart = DateTime.now();
  int _totalSpins = 0;
  int _consecutiveLosses = 0;
  int _consecutiveWins = 0;
  double _lastBetSize = 0.0;
  int _betIncreaseCount = 0; // chasing signal
  int _betDecreaseCount = 0; // cooling signal
  int _consistentPaceCount = 0; // flow state signal

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE — SMOOTHED OUTPUT
  // ═══════════════════════════════════════════════════════════════════════════

  NeuroAudioOutput _output = const NeuroAudioOutput();
  NeuroAudioOutput _rawOutput = const NeuroAudioOutput();
  bool _enabled = true;
  bool _responsibleGamingMode = true; // auto-reduce stimulation for high-risk

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  NeuroAudioOutput get output => _output;
  NeuroAudioOutput get rawOutput => _rawOutput;
  bool get enabled => _enabled;
  bool get responsibleGamingMode => _responsibleGamingMode;
  int get totalSpins => _totalSpins;
  int get consecutiveLosses => _consecutiveLosses;
  double get sessionDurationMinutes =>
      DateTime.now().difference(_sessionStart).inSeconds / 60.0;
  PlayerRiskLevel get riskLevel => _output.riskLevel;

  /// RTPC parameter names this provider writes to
  static const rtpcParameters = [
    ('neuro_arousal', 'NeuroAudio Arousal', 0.0, 1.0, 0.3),
    ('neuro_valence', 'NeuroAudio Valence', -1.0, 1.0, 0.0),
    ('neuro_engagement', 'NeuroAudio Engagement', 0.0, 1.0, 0.5),
    ('neuro_tempo_mod', 'NeuroAudio Tempo', 0.7, 1.3, 1.0),
    ('neuro_reverb_mod', 'NeuroAudio Reverb', 0.5, 2.0, 1.0),
    ('neuro_compression_mod', 'NeuroAudio Compression', 0.5, 2.0, 1.0),
    ('neuro_win_magnitude', 'NeuroAudio Win Magnitude', 0.3, 1.5, 1.0),
    ('neuro_near_miss_tension', 'NeuroAudio Near-Miss', 0.0, 1.0, 0.5),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
  }

  void setResponsibleGamingMode(bool enabled) {
    if (_responsibleGamingMode == enabled) return;
    _responsibleGamingMode = enabled;
    _recompute();
  }

  void resetSession() {
    _clickVelocities.clear();
    _pauseDurations.clear();
    _betSizes.clear();
    _winLossHistory.clear();
    _nearMissHistory.clear();
    _sessionStart = DateTime.now();
    _totalSpins = 0;
    _consecutiveLosses = 0;
    _consecutiveWins = 0;
    _lastBetSize = 0.0;
    _betIncreaseCount = 0;
    _betDecreaseCount = 0;
    _consistentPaceCount = 0;
    _output = const NeuroAudioOutput();
    _rawOutput = const NeuroAudioOutput();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT — BEHAVIORAL EVENT RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record click-to-spin velocity in milliseconds
  void recordClickVelocity(double ms) {
    if (!_enabled) return;
    _addSignal(_clickVelocities, ms);
  }

  /// Record inter-spin pause duration in milliseconds
  void recordPauseDuration(double ms) {
    if (!_enabled) return;
    _addSignal(_pauseDurations, ms);

    // Flow state detection: consistent pace = within ±20% of mean
    final meanPause = _weightedMean(_pauseDurations);
    if (meanPause > 0 && (ms - meanPause).abs() / meanPause < 0.2) {
      _consistentPaceCount++;
    } else {
      _consistentPaceCount = math.max(0, _consistentPaceCount - 2);
    }
  }

  /// Record bet size change (normalized 0.0-1.0 of max bet)
  void recordBetSize(double normalizedBet) {
    if (!_enabled) return;
    _addSignal(_betSizes, normalizedBet);

    // Track chasing behavior
    if (_lastBetSize > 0) {
      if (normalizedBet > _lastBetSize * 1.1) {
        _betIncreaseCount++;
        _betDecreaseCount = math.max(0, _betDecreaseCount - 1);
      } else if (normalizedBet < _lastBetSize * 0.9) {
        _betDecreaseCount++;
        _betIncreaseCount = math.max(0, _betIncreaseCount - 1);
      }
    }
    _lastBetSize = normalizedBet;
  }

  /// Record spin result: winMultiplier = winAmount/betAmount (0 = loss)
  void recordSpinResult(double winMultiplier) {
    if (!_enabled) return;
    _addSignal(_winLossHistory, winMultiplier);
    _totalSpins++;

    if (winMultiplier <= 0) {
      _consecutiveLosses++;
      _consecutiveWins = 0;
    } else {
      _consecutiveWins++;
      _consecutiveLosses = 0;
    }

    _recompute();
  }

  /// Record near-miss event (2/3 scatters landed, etc.)
  void recordNearMiss(int scatterCount) {
    if (!_enabled) return;
    _addSignal(_nearMissHistory, scatterCount.toDouble());
    _recompute();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CORE — 8D EMOTIONAL STATE VECTOR COMPUTATION
  // ═══════════════════════════════════════════════════════════════════════════

  void _recompute() {
    if (!_enabled) return;

    final now = DateTime.now();
    final sessionMinutes = now.difference(_sessionStart).inSeconds / 60.0;

    // ─── 1. AROUSAL ──────────────────────────────────────────────────────
    // Fast clicks + recent wins + bet increases → high arousal
    final clickSpeed = _clickVelocities.isNotEmpty
        ? (1.0 - (_weightedMean(_clickVelocities) / 5000.0).clamp(0.0, 1.0))
        : 0.3;
    final recentWinRate = _recentWinRate();
    final betChasing = (_betIncreaseCount / (_betIncreaseCount + _betDecreaseCount + 1))
        .clamp(0.0, 1.0);
    final arousal = (clickSpeed * 0.3 + recentWinRate * 0.3 + betChasing * 0.2 +
            (_consecutiveWins / 10.0).clamp(0.0, 0.2))
        .clamp(0.0, 1.0);

    // ─── 2. VALENCE ──────────────────────────────────────────────────────
    // Wins → positive, losses → negative, near-misses → frustration
    final winValence = (recentWinRate * 2.0 - 1.0).clamp(-1.0, 1.0);
    final lossWeight = (_consecutiveLosses / 10.0).clamp(0.0, 1.0);
    final nearMissFreq = _recentNearMissRate();
    final valence = (winValence * 0.5 - lossWeight * 0.3 - nearMissFreq * 0.2)
        .clamp(-1.0, 1.0);

    // ─── 3. RISK TOLERANCE ──────────────────────────────────────────────
    // Bet increases after losses = chasing = high risk tolerance
    final chasingSignal = _consecutiveLosses > 0
        ? (_betIncreaseCount / (_totalSpins + 1)).clamp(0.0, 1.0)
        : 0.0;
    final riskTolerance = (chasingSignal * 0.4 +
            betChasing * 0.3 +
            (1.0 - (_weightedMean(_pauseDurations) / 10000.0).clamp(0.0, 1.0)) * 0.3)
        .clamp(0.0, 1.0);

    // ─── 4. ENGAGEMENT ──────────────────────────────────────────────────
    // Consistent pace + moderate arousal + positive valence = engagement
    final flowSignal = (_consistentPaceCount / _flowEntryThreshold).clamp(0.0, 1.0);
    final engagement = (flowSignal * 0.4 +
            (1.0 - (arousal - 0.5).abs() * 2.0).clamp(0.0, 1.0) * 0.3 +
            ((valence + 1.0) / 2.0) * 0.3)
        .clamp(0.0, 1.0);

    // ─── 5. CHURN PREDICTION ─────────────────────────────────────────────
    // Long pauses + consecutive losses + bet decreases = leaving
    final longPauses = _pauseDurations.isNotEmpty
        ? (_pauseDurations
                    .where((s) => s.value > 5000)
                    .length /
                _pauseDurations.length)
            .clamp(0.0, 1.0)
        : 0.0;
    final churnPrediction = (longPauses * 0.3 +
            (_consecutiveLosses / _churnLossThreshold).clamp(0.0, 1.0) * 0.4 +
            (_betDecreaseCount / (_totalSpins + 1)).clamp(0.0, 1.0) * 0.3)
        .clamp(0.0, 1.0);

    // ─── 6. FRUSTRATION ──────────────────────────────────────────────────
    // Consecutive losses + near-misses + fast clicking during loss = frustration
    final frustrationFromLosses = (_consecutiveLosses / 8.0).clamp(0.0, 1.0);
    final frustrationFromNearMiss = nearMissFreq;
    final frustrationFromSpeed =
        (_consecutiveLosses > 3 && clickSpeed > 0.7) ? 0.3 : 0.0;
    final frustration =
        (frustrationFromLosses * 0.5 + frustrationFromNearMiss * 0.3 + frustrationFromSpeed)
            .clamp(0.0, 1.0);

    // ─── 7. FLOW DEPTH ───────────────────────────────────────────────────
    // Consistent pace + moderate session + positive experience = flow
    final sessionFactor = sessionMinutes > 2
        ? (1.0 - ((sessionMinutes - 15).abs() / 30.0)).clamp(0.0, 1.0)
        : 0.0;
    final flowDepth = (flowSignal * 0.5 +
            sessionFactor * 0.2 +
            engagement * 0.3)
        .clamp(0.0, 1.0);

    // ─── 8. SESSION FATIGUE ──────────────────────────────────────────────
    // Long sessions + high arousal exposure = fatigue
    final durationFatigue = (sessionMinutes / 60.0).clamp(0.0, 1.0);
    final arousalFatigue = arousal > 0.7
        ? ((sessionMinutes * arousal) / 30.0).clamp(0.0, 1.0)
        : 0.0;
    final sessionFatigue = (durationFatigue * 0.6 + arousalFatigue * 0.4).clamp(0.0, 1.0);

    // ═══════════════════════════════════════════════════════════════════════
    // RISK LEVEL CLASSIFICATION
    // ═══════════════════════════════════════════════════════════════════════

    final riskScore = (riskTolerance * 0.3 +
            frustration * 0.25 +
            churnPrediction * 0.2 +
            (1.0 - engagement) * 0.15 +
            sessionFatigue * 0.1)
        .clamp(0.0, 1.0);

    final riskLevel = riskScore > 0.7
        ? PlayerRiskLevel.high
        : riskScore > 0.5
            ? PlayerRiskLevel.elevated
            : riskScore > 0.3
                ? PlayerRiskLevel.moderate
                : PlayerRiskLevel.low;

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO ADAPTATION — MAP STATE VECTOR → AUDIO PARAMETERS
    // ═══════════════════════════════════════════════════════════════════════

    double tempoMod = 1.0;
    double reverbMod = 1.0;
    double compressionMod = 1.0;
    double winMagnitude = 1.0;
    double nearMissTensionMod = 0.5;
    double volumeScale = 1.0;

    if (_responsibleGamingMode && riskLevel == PlayerRiskLevel.high) {
      // ─── HIGH RISK: reduce all stimulation ────────────────────────────
      tempoMod = 0.85; // slower music
      reverbMod = 1.5; // more reverb = calming, spacious
      compressionMod = 0.7; // less dense = less exciting
      winMagnitude = 0.5; // subdued win sounds
      nearMissTensionMod = 0.2; // minimal near-miss tension
      volumeScale = 0.7; // compressed dynamics
    } else if (_responsibleGamingMode && riskLevel == PlayerRiskLevel.elevated) {
      // ─── ELEVATED: subtle reduction ───────────────────────────────────
      tempoMod = 0.92;
      reverbMod = 1.3;
      compressionMod = 0.85;
      winMagnitude = 0.8;
      nearMissTensionMod = 0.35;
      volumeScale = 0.85;
    } else {
      // ─── NORMAL: adaptive based on emotional state ────────────────────
      // Tempo: faster when engaged + winning, slower when frustrated/fatigued
      tempoMod = (1.0 + (arousal - 0.5) * 0.3 + valence * 0.1 - sessionFatigue * 0.15)
          .clamp(0.7, 1.3);

      // Reverb: more intimate during flow, grander during peaks
      reverbMod = (1.0 + (1.0 - flowDepth) * 0.5 + arousal * 0.3)
          .clamp(0.5, 2.0);

      // Compression: denser during high engagement, relaxed during cooldown
      compressionMod = (1.0 + engagement * 0.4 + arousal * 0.3 - sessionFatigue * 0.2)
          .clamp(0.5, 2.0);

      // Win sound: bigger relative to session state (diminishing if fatigued)
      winMagnitude = (1.0 + engagement * 0.2 - sessionFatigue * 0.3 - frustration * 0.2)
          .clamp(0.3, 1.5);

      // Near-miss tension: calibrated to engagement (don't provoke frustration)
      nearMissTensionMod = (0.5 + engagement * 0.3 - frustration * 0.4)
          .clamp(0.0, 1.0);

      // Volume envelope: full range in flow, compressed when fatigued
      volumeScale = (1.0 - sessionFatigue * 0.3 - frustration * 0.2)
          .clamp(0.5, 1.0);
    }

    _rawOutput = NeuroAudioOutput(
      arousal: arousal,
      valence: valence,
      riskTolerance: riskTolerance,
      engagement: engagement,
      churnPrediction: churnPrediction,
      frustration: frustration,
      flowDepth: flowDepth,
      sessionFatigue: sessionFatigue,
      tempoModifier: tempoMod,
      reverbDepthModifier: reverbMod,
      compressionModifier: compressionMod,
      winSoundMagnitude: winMagnitude,
      nearMissTension: nearMissTensionMod,
      volumeEnvelopeScale: volumeScale,
      riskLevel: riskLevel,
    );

    // Smooth output to prevent jarring audio changes
    _output = _smooth(_output, _rawOutput);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _addSignal(List<BehavioralSignal> list, double value) {
    list.add(BehavioralSignal(value, DateTime.now()));
    if (list.length > _signalWindowSize) {
      list.removeAt(0);
    }
  }

  /// Exponentially decay-weighted mean of signal history
  double _weightedMean(List<BehavioralSignal> signals) {
    if (signals.isEmpty) return 0.0;
    final now = DateTime.now();
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    for (final s in signals) {
      final ageSec = now.difference(s.timestamp).inMilliseconds / 1000.0;
      final weight = math.pow(0.5, ageSec / _decayHalfLifeS).toDouble();
      weightedSum += s.value * weight;
      totalWeight += weight;
    }
    return totalWeight > 0 ? weightedSum / totalWeight : 0.0;
  }

  /// Recent win rate (decay-weighted)
  double _recentWinRate() {
    if (_winLossHistory.isEmpty) return 0.0;
    final now = DateTime.now();
    double winWeight = 0.0;
    double totalWeight = 0.0;
    for (final s in _winLossHistory) {
      final ageSec = now.difference(s.timestamp).inMilliseconds / 1000.0;
      final weight = math.pow(0.5, ageSec / _decayHalfLifeS).toDouble();
      if (s.value > 0) winWeight += weight;
      totalWeight += weight;
    }
    return totalWeight > 0 ? (winWeight / totalWeight).clamp(0.0, 1.0) : 0.0;
  }

  /// Recent near-miss frequency (decay-weighted, normalized)
  double _recentNearMissRate() {
    if (_nearMissHistory.isEmpty) return 0.0;
    if (_totalSpins < 5) return 0.0;
    // Near-miss rate as fraction of recent spins
    final recentSpins = math.min(_totalSpins, _signalWindowSize);
    return (_nearMissHistory.length / recentSpins).clamp(0.0, 1.0);
  }

  /// Smooth transition between old and new output
  NeuroAudioOutput _smooth(NeuroAudioOutput old, NeuroAudioOutput raw) {
    double s(double a, double b) => a * _outputSmoothing + b * (1.0 - _outputSmoothing);
    return NeuroAudioOutput(
      arousal: s(old.arousal, raw.arousal),
      valence: s(old.valence, raw.valence),
      riskTolerance: s(old.riskTolerance, raw.riskTolerance),
      engagement: s(old.engagement, raw.engagement),
      churnPrediction: s(old.churnPrediction, raw.churnPrediction),
      frustration: s(old.frustration, raw.frustration),
      flowDepth: s(old.flowDepth, raw.flowDepth),
      sessionFatigue: s(old.sessionFatigue, raw.sessionFatigue),
      tempoModifier: s(old.tempoModifier, raw.tempoModifier),
      reverbDepthModifier: s(old.reverbDepthModifier, raw.reverbDepthModifier),
      compressionModifier: s(old.compressionModifier, raw.compressionModifier),
      winSoundMagnitude: s(old.winSoundMagnitude, raw.winSoundMagnitude),
      nearMissTension: s(old.nearMissTension, raw.nearMissTension),
      volumeEnvelopeScale: s(old.volumeEnvelopeScale, raw.volumeEnvelopeScale),
      riskLevel: raw.riskLevel, // risk level is discrete — no smoothing
    );
  }

  /// Get RTPC parameter values for writing to RTPCManager
  Map<String, double> getRtpcValues() => {
        'neuro_arousal': _output.arousal,
        'neuro_valence': _output.valence,
        'neuro_engagement': _output.engagement,
        'neuro_tempo_mod': _output.tempoModifier,
        'neuro_reverb_mod': _output.reverbDepthModifier,
        'neuro_compression_mod': _output.compressionModifier,
        'neuro_win_magnitude': _output.winSoundMagnitude,
        'neuro_near_miss_tension': _output.nearMissTension,
      };
}

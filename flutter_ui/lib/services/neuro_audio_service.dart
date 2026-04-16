/// NeuroAudio™ Service — T4.1+T4.2
///
/// Dart wrapper around the rf-neuro Rust crate FFI.
/// Provides:
/// - Real-time behavioral signal processing (T4.1)
/// - 8D Player State Vector (T4.2)
/// - AudioAdaptation output → RTPC parameters (T4.3)
/// - Session simulation for authoring preview (T4.8)
/// - Responsible Gaming auto-intervention (T4.5)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Mirrors Rust NeuroConfig
class NeuroConfig {
  final int windowMs;
  final int maxSamples;
  final double smoothing;
  final bool rgModeEnabled;
  final double decayHalfLifeS;

  const NeuroConfig({
    this.windowMs = 300000,
    this.maxSamples = 2000,
    this.smoothing = 0.30,
    this.rgModeEnabled = true,
    this.decayHalfLifeS = 120.0,
  });

  Map<String, dynamic> toJson() => {
    'window_ms': windowMs,
    'max_samples': maxSamples,
    'smoothing': smoothing,
    'rg_mode_enabled': rgModeEnabled,
    'decay_half_life_s': decayHalfLifeS,
  };
}

/// 8-dimensional Player State Vector (mirrors Rust PlayerStateVector)
class PlayerStateVector {
  final double arousal;
  final double valence;
  final double engagement;
  final double riskTolerance;
  final double frustration;
  final double anticipation;
  final double fatigue;
  final double churnProbability;

  const PlayerStateVector({
    required this.arousal,
    required this.valence,
    required this.engagement,
    required this.riskTolerance,
    required this.frustration,
    required this.anticipation,
    required this.fatigue,
    required this.churnProbability,
  });

  factory PlayerStateVector.neutral() => const PlayerStateVector(
    arousal: 0.30, valence: 0.50, engagement: 0.60, riskTolerance: 0.30,
    frustration: 0.00, anticipation: 0.20, fatigue: 0.00, churnProbability: 0.10,
  );

  factory PlayerStateVector.fromJson(Map<String, dynamic> j) => PlayerStateVector(
    arousal:           (j['arousal']           as num?)?.toDouble() ?? 0.30,
    valence:           (j['valence']           as num?)?.toDouble() ?? 0.50,
    engagement:        (j['engagement']        as num?)?.toDouble() ?? 0.60,
    riskTolerance:     (j['risk_tolerance']    as num?)?.toDouble() ?? 0.30,
    frustration:       (j['frustration']       as num?)?.toDouble() ?? 0.00,
    anticipation:      (j['anticipation']      as num?)?.toDouble() ?? 0.20,
    fatigue:           (j['fatigue']           as num?)?.toDouble() ?? 0.00,
    churnProbability:  (j['churn_probability'] as num?)?.toDouble() ?? 0.10,
  );

  /// Composite RG risk score (matches Rust rg_risk_score())
  double get rgRiskScore =>
    (riskTolerance * 0.30 + frustration * 0.25 + churnProbability * 0.20 +
     (1.0 - engagement) * 0.15 + fatigue * 0.10).clamp(0.0, 1.0);

  RiskLevel get riskLevel {
    final s = rgRiskScore;
    if (s > 0.70) return RiskLevel.high;
    if (s > 0.50) return RiskLevel.elevated;
    if (s > 0.30) return RiskLevel.moderate;
    return RiskLevel.low;
  }
}

enum RiskLevel {
  low, moderate, elevated, high;

  String get displayName => switch (this) {
    RiskLevel.low      => 'Low Risk',
    RiskLevel.moderate => 'Moderate',
    RiskLevel.elevated => 'Elevated',
    RiskLevel.high     => 'High Risk',
  };

  int get colorValue => switch (this) {
    RiskLevel.low      => 0xFF44CC44,
    RiskLevel.moderate => 0xFF88AA44,
    RiskLevel.elevated => 0xFFDD8822,
    RiskLevel.high     => 0xFFCC3333,
  };
}

/// Audio adaptation output (mirrors Rust AudioAdaptation)
class AudioAdaptation {
  final double musicBpmMultiplier;
  final double reverbDepth;
  final double compressionRatio;
  final double winMagnitudeBias;
  final double tensionCalibration;
  final double volumeEnvelopeShape;
  final double hfBrightness;
  final double spatialWidth;
  final RgIntervention? rgIntervention;

  const AudioAdaptation({
    required this.musicBpmMultiplier,
    required this.reverbDepth,
    required this.compressionRatio,
    required this.winMagnitudeBias,
    required this.tensionCalibration,
    required this.volumeEnvelopeShape,
    required this.hfBrightness,
    required this.spatialWidth,
    this.rgIntervention,
  });

  factory AudioAdaptation.neutral() => const AudioAdaptation(
    musicBpmMultiplier: 1.0, reverbDepth: 0.5, compressionRatio: 2.0,
    winMagnitudeBias: 1.0, tensionCalibration: 0.5, volumeEnvelopeShape: 0.7,
    hfBrightness: 0.7, spatialWidth: 0.5,
  );

  factory AudioAdaptation.fromJson(Map<String, dynamic> j) => AudioAdaptation(
    musicBpmMultiplier: (j['music_bpm_multiplier'] as num?)?.toDouble() ?? 1.0,
    reverbDepth:        (j['reverb_depth']          as num?)?.toDouble() ?? 0.5,
    compressionRatio:   (j['compression_ratio']     as num?)?.toDouble() ?? 2.0,
    winMagnitudeBias:   (j['win_magnitude_bias']    as num?)?.toDouble() ?? 1.0,
    tensionCalibration: (j['tension_calibration']   as num?)?.toDouble() ?? 0.5,
    volumeEnvelopeShape:(j['volume_envelope_shape'] as num?)?.toDouble() ?? 0.7,
    hfBrightness:       (j['hf_brightness']         as num?)?.toDouble() ?? 0.7,
    spatialWidth:       (j['spatial_width']         as num?)?.toDouble() ?? 0.5,
    rgIntervention:     j['rg_intervention'] != null
        ? RgIntervention.fromJson(j['rg_intervention'] as Map<String, dynamic>)
        : null,
  );

  /// RTPC parameter map — feed directly to RtpcModulationService
  Map<String, double> get rtpcValues => {
    'neuro_bpm_mult':      musicBpmMultiplier,
    'neuro_reverb':        reverbDepth,
    'neuro_compression':   compressionRatio,
    'neuro_win_bias':      winMagnitudeBias,
    'neuro_tension':       tensionCalibration,
    'neuro_volume_shape':  volumeEnvelopeShape,
    'neuro_hf_bright':     hfBrightness,
    'neuro_spatial':       spatialWidth,
  };
}

class RgIntervention {
  final String level; // "active" | "subtle"
  final double rgScore;

  const RgIntervention({required this.level, required this.rgScore});

  factory RgIntervention.fromJson(Map<String, dynamic> j) => RgIntervention(
    level: (j['level'] as String?) ?? 'subtle',
    rgScore: (j['rg_score'] as num?)?.toDouble() ?? 0.0,
  );

  bool get isActive => level == 'active';
}

// ─────────────────────────────────────────────────────────────────────────────
// BEHAVIORAL EVENTS
// ─────────────────────────────────────────────────────────────────────────────

enum SpinOutcome {
  loss, nearMiss, smallWin, mediumWin, bigWin, megaWin, featureTriggered;

  String get jsonKey => switch (this) {
    SpinOutcome.loss             => 'loss',
    SpinOutcome.nearMiss         => 'near_miss',
    SpinOutcome.smallWin         => 'small_win',
    SpinOutcome.mediumWin        => 'medium_win',
    SpinOutcome.bigWin           => 'big_win',
    SpinOutcome.megaWin          => 'mega_win',
    SpinOutcome.featureTriggered => 'feature_triggered',
  };
}

/// Builder for BehavioralSample JSON
class BehavioralSampleBuilder {
  static Map<String, dynamic> spinClick(int timestampMs, int interSpinMs) => {
    'timestamp_ms': timestampMs,
    'event': {
      'type': 'spin_click',
      'data': { 'inter_spin_ms': interSpinMs },
    },
  };

  static Map<String, dynamic> spinResult(
    int timestampMs,
    SpinOutcome outcome,
    double winCredits,
    double betCredits,
  ) => {
    'timestamp_ms': timestampMs,
    'event': {
      'type': 'spin_result',
      'data': {
        'outcome': outcome.jsonKey,
        'win_credits': winCredits,
        'bet_credits': betCredits,
      },
    },
  };

  static Map<String, dynamic> betChange(
    int timestampMs,
    double newBet,
    double prevBet,
    bool afterLoss,
  ) => {
    'timestamp_ms': timestampMs,
    'event': {
      'type': 'bet_change',
      'data': {
        'new_bet': newBet,
        'prev_bet': prevBet,
        'after_loss': afterLoss,
      },
    },
  };

  static Map<String, dynamic> pause(int timestampMs, int durationMs, bool afterLoss) => {
    'timestamp_ms': timestampMs,
    'event': {
      'type': 'pause',
      'data': { 'duration_ms': durationMs, 'after_loss': afterLoss },
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ARCHETYPE
// ─────────────────────────────────────────────────────────────────────────────

class PlayerArchetype {
  final String key;
  final String displayName;

  const PlayerArchetype({required this.key, required this.displayName});

  factory PlayerArchetype.fromJson(Map<String, dynamic> j) => PlayerArchetype(
    key: (j['key'] as String?) ?? '',
    displayName: (j['name'] as String?) ?? '',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SIMULATION RESULT
// ─────────────────────────────────────────────────────────────────────────────

class NeuroSimulationResult {
  final String archetype;
  final int spinCount;
  final List<PlayerStateVector> stateTimeline;
  final List<AudioAdaptation> adaptationTimeline;
  final PlayerStateVector finalState;
  final AudioAdaptation finalAdaptation;
  final double peakChurn;
  final double rgInterventionFraction;

  const NeuroSimulationResult({
    required this.archetype,
    required this.spinCount,
    required this.stateTimeline,
    required this.adaptationTimeline,
    required this.finalState,
    required this.finalAdaptation,
    required this.peakChurn,
    required this.rgInterventionFraction,
  });

  factory NeuroSimulationResult.fromJson(Map<String, dynamic> j) => NeuroSimulationResult(
    archetype:  (j['archetype'] as String?) ?? '',
    spinCount:  (j['spin_count'] as int?) ?? 0,
    stateTimeline: ((j['state_timeline'] as List?) ?? [])
        .map((e) => PlayerStateVector.fromJson(e as Map<String, dynamic>))
        .toList(),
    adaptationTimeline: ((j['adaptation_timeline'] as List?) ?? [])
        .map((e) => AudioAdaptation.fromJson(e as Map<String, dynamic>))
        .toList(),
    finalState: PlayerStateVector.fromJson(
        (j['final_state'] as Map<String, dynamic>?) ?? {}),
    finalAdaptation: AudioAdaptation.fromJson(
        (j['final_adaptation'] as Map<String, dynamic>?) ?? {}),
    peakChurn:               (j['peak_churn']                as num?)?.toDouble() ?? 0.0,
    rgInterventionFraction:  (j['rg_intervention_fraction']  as num?)?.toDouble() ?? 0.0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// NeuroAudio™ Service — manages NeuroEngine lifecycle + FFI calls
class NeuroAudioService extends ChangeNotifier {
  int _engineId = -1;
  PlayerStateVector _state = PlayerStateVector.neutral();
  AudioAdaptation _adaptation = AudioAdaptation.neutral();
  bool _isInitialized = false;
  List<PlayerArchetype> _archetypes = [];

  PlayerStateVector get state => _state;
  AudioAdaptation get adaptation => _adaptation;
  bool get isInitialized => _isInitialized;
  List<PlayerArchetype> get archetypes => _archetypes;
  int get engineId => _engineId;

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  /// Initialize with optional config. Must be called before processing events.
  void initialize({NeuroConfig? config}) {
    if (_isInitialized) return;

    final configJson = config != null ? jsonEncode(config.toJson()) : null;
    _engineId = NativeFFI.instance.neuroEngineCreate(configJson: configJson);
    _isInitialized = _engineId > 0;

    // Load available archetypes
    _loadArchetypes();
    notifyListeners();
  }

  void _loadArchetypes() {
    try {
      final json = NativeFFI.instance.neuroAvailableArchetypes();
      if (json == null) return;
      final list = jsonDecode(json) as List;
      _archetypes = list
          .map((e) => PlayerArchetype.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  /// Reset engine for a new session
  void resetSession() {
    if (!_isInitialized) return;
    NativeFFI.instance.neuroEngineReset(_engineId);
    _state = PlayerStateVector.neutral();
    _adaptation = AudioAdaptation.neutral();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isInitialized && _engineId > 0) {
      NativeFFI.instance.neuroEngineDestroy(_engineId);
    }
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Real-time processing (T4.1–T4.2)
  // ──────────────────────────────────────────────────────────────────────────

  /// Process a spin click event.
  void onSpinClick(int timestampMs, int interSpinMs) {
    _processEvent(BehavioralSampleBuilder.spinClick(timestampMs, interSpinMs));
  }

  /// Process a spin result.
  void onSpinResult(int timestampMs, SpinOutcome outcome, double winCredits, double betCredits) {
    _processEvent(BehavioralSampleBuilder.spinResult(timestampMs, outcome, winCredits, betCredits));
  }

  /// Process a bet change.
  void onBetChange(int timestampMs, double newBet, double prevBet, bool afterLoss) {
    _processEvent(BehavioralSampleBuilder.betChange(timestampMs, newBet, prevBet, afterLoss));
  }

  /// Process a player pause.
  void onPause(int timestampMs, int durationMs, bool afterLoss) {
    _processEvent(BehavioralSampleBuilder.pause(timestampMs, durationMs, afterLoss));
  }

  void _processEvent(Map<String, dynamic> sampleMap) {
    if (!_isInitialized) return;

    final eventJson = jsonEncode(sampleMap);
    final stateJson = NativeFFI.instance.neuroEngineProcess(_engineId, eventJson);
    if (stateJson == null) return;

    try {
      _state = PlayerStateVector.fromJson(jsonDecode(stateJson) as Map<String, dynamic>);
    } catch (_) { return; }

    // Fetch adaptation
    _updateAdaptation();
    notifyListeners();
  }

  void _updateAdaptation() {
    final adaptJson = NativeFFI.instance.neuroEngineAdaptation(_engineId);
    if (adaptJson == null) return;
    try {
      _adaptation = AudioAdaptation.fromJson(jsonDecode(adaptJson) as Map<String, dynamic>);
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Simulation for authoring (T4.8)
  // ──────────────────────────────────────────────────────────────────────────

  /// Simulate a session for authoring preview.
  /// Returns null if simulation fails.
  Future<NeuroSimulationResult?> simulate({
    required String archetypeKey,
    int spinCount = 100,
    NeuroConfig? config,
  }) async {
    final simRequest = {
      'archetype': archetypeKey,
      'spin_count': spinCount,
      'config': (config ?? const NeuroConfig()).toJson(),
    };

    return compute(_simulateInBackground, jsonEncode(simRequest));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate helper
// ─────────────────────────────────────────────────────────────────────────────

NeuroSimulationResult? _simulateInBackground(String simJson) {
  final resultJson = NativeFFI.instance.neuroEngineSimulate(simJson);
  if (resultJson == null) return null;
  try {
    return NeuroSimulationResult.fromJson(jsonDecode(resultJson) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// FluxForge Envelope Follower RTPC Service
///
/// Extracts amplitude envelope from audio signals and outputs to RTPC system.
/// Enables audio-reactive parameter control for dynamic, responsive audio.
///
/// Features:
/// - Extract envelope from audio signal (track, bus, or sidechain)
/// - Attack/Release controls for envelope shaping
/// - RMS vs Peak detection modes
/// - Output to RTPC system for parameter modulation
/// - Threshold gate to ignore low-level signals
/// - Smoothing filter for clean, stable control signals
///
/// Use cases:
/// - Music-reactive visual effects
/// - Ducking based on amplitude
/// - Auto-gain riding
/// - Slot game win intensity control
/// - Dynamic reverb/delay modulation
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../providers/middleware_provider.dart';

/// Sentinel for copyWith null handling
const Object _sentinel = Object();

/// Envelope detection mode
enum EnvelopeDetectionMode {
  /// Peak detection (fast transients)
  peak(0, 'Peak', 'Responds to instantaneous peaks'),

  /// RMS detection (average level)
  rms(1, 'RMS', 'Responds to average signal level'),

  /// Peak-RMS hybrid (peak for attack, RMS for release)
  hybrid(2, 'Hybrid', 'Peak attack with RMS release');

  final int value;
  final String label;
  final String description;
  const EnvelopeDetectionMode(this.value, this.label, this.description);
}

/// Source type for envelope follower
enum EnvelopeSourceType {
  /// Track output
  track(0, 'Track'),

  /// Bus output
  bus(1, 'Bus'),

  /// Aux send
  aux(2, 'Aux'),

  /// Sidechain input
  sidechain(3, 'Sidechain'),

  /// External input
  external(4, 'External');

  final int value;
  final String label;
  const EnvelopeSourceType(this.value, this.label);
}

/// Configuration for an envelope follower
class EnvelopeFollowerConfig {
  final int id;
  final String name;
  final EnvelopeSourceType sourceType;
  final int sourceId;
  final EnvelopeDetectionMode mode;
  final double attackMs;
  final double releaseMs;
  final double thresholdDb;
  final double smoothingMs;
  final double minOutput;
  final double maxOutput;
  final int? targetRtpcId;
  final bool enabled;
  final bool inverted;

  const EnvelopeFollowerConfig({
    required this.id,
    required this.name,
    this.sourceType = EnvelopeSourceType.bus,
    this.sourceId = 0,
    this.mode = EnvelopeDetectionMode.rms,
    this.attackMs = 10.0,
    this.releaseMs = 100.0,
    this.thresholdDb = -60.0,
    this.smoothingMs = 20.0,
    this.minOutput = 0.0,
    this.maxOutput = 1.0,
    this.targetRtpcId,
    this.enabled = true,
    this.inverted = false,
  });

  EnvelopeFollowerConfig copyWith({
    int? id,
    String? name,
    EnvelopeSourceType? sourceType,
    int? sourceId,
    EnvelopeDetectionMode? mode,
    double? attackMs,
    double? releaseMs,
    double? thresholdDb,
    double? smoothingMs,
    double? minOutput,
    double? maxOutput,
    Object? targetRtpcId = _sentinel,
    bool? enabled,
    bool? inverted,
  }) {
    return EnvelopeFollowerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      mode: mode ?? this.mode,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
      thresholdDb: thresholdDb ?? this.thresholdDb,
      smoothingMs: smoothingMs ?? this.smoothingMs,
      minOutput: minOutput ?? this.minOutput,
      maxOutput: maxOutput ?? this.maxOutput,
      targetRtpcId: targetRtpcId == _sentinel ? this.targetRtpcId : targetRtpcId as int?,
      enabled: enabled ?? this.enabled,
      inverted: inverted ?? this.inverted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sourceType': sourceType.value,
        'sourceId': sourceId,
        'mode': mode.value,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'thresholdDb': thresholdDb,
        'smoothingMs': smoothingMs,
        'minOutput': minOutput,
        'maxOutput': maxOutput,
        'targetRtpcId': targetRtpcId,
        'enabled': enabled,
        'inverted': inverted,
      };

  factory EnvelopeFollowerConfig.fromJson(Map<String, dynamic> json) {
    return EnvelopeFollowerConfig(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Envelope Follower',
      sourceType: EnvelopeSourceType.values[json['sourceType'] as int? ?? 0],
      sourceId: json['sourceId'] as int? ?? 0,
      mode: EnvelopeDetectionMode.values[json['mode'] as int? ?? 1],
      attackMs: (json['attackMs'] as num?)?.toDouble() ?? 10.0,
      releaseMs: (json['releaseMs'] as num?)?.toDouble() ?? 100.0,
      thresholdDb: (json['thresholdDb'] as num?)?.toDouble() ?? -60.0,
      smoothingMs: (json['smoothingMs'] as num?)?.toDouble() ?? 20.0,
      minOutput: (json['minOutput'] as num?)?.toDouble() ?? 0.0,
      maxOutput: (json['maxOutput'] as num?)?.toDouble() ?? 1.0,
      targetRtpcId: json['targetRtpcId'] as int?,
      enabled: json['enabled'] as bool? ?? true,
      inverted: json['inverted'] as bool? ?? false,
    );
  }
}

/// Envelope follower state (runtime values)
class EnvelopeFollowerState {
  final int configId;
  double currentEnvelope;
  double smoothedEnvelope;
  double currentOutputValue;
  double peakHold;
  int peakHoldSamples;

  EnvelopeFollowerState({
    required this.configId,
    this.currentEnvelope = 0.0,
    this.smoothedEnvelope = 0.0,
    this.currentOutputValue = 0.0,
    this.peakHold = 0.0,
    this.peakHoldSamples = 0,
  });

  void reset() {
    currentEnvelope = 0.0;
    smoothedEnvelope = 0.0;
    currentOutputValue = 0.0;
    peakHold = 0.0;
    peakHoldSamples = 0;
  }
}

/// Envelope Follower RTPC Service
class EnvelopeFollowerRtpcService {
  static final EnvelopeFollowerRtpcService _instance = EnvelopeFollowerRtpcService._();
  static EnvelopeFollowerRtpcService get instance => _instance;

  EnvelopeFollowerRtpcService._();

  /// Whether the service is initialized
  bool _initialized = false;

  /// Reference to middleware provider (for RTPC output)
  MiddlewareProvider? _middleware;

  /// Registered envelope followers
  final Map<int, EnvelopeFollowerConfig> _configs = {};

  /// Runtime state for each follower
  final Map<int, EnvelopeFollowerState> _states = {};

  /// ID counter
  int _nextId = 1;

  /// Update timer
  Timer? _updateTimer;

  /// Sample rate (assumed, can be updated)
  double _sampleRate = 44100.0;

  /// Listeners for value changes
  final List<void Function(int configId, double value)> _valueListeners = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize with middleware provider
  void init(MiddlewareProvider middleware) {
    if (_initialized) return;
    _middleware = middleware;
    _initialized = true;
    debugPrint('[EnvelopeFollower] Initialized with MiddlewareProvider');
  }

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// Set sample rate for accurate timing
  void setSampleRate(double sampleRate) {
    _sampleRate = sampleRate;
  }

  /// Dispose resources
  void dispose() {
    _stopUpdateLoop();
    _configs.clear();
    _states.clear();
    _valueListeners.clear();
    _initialized = false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOLLOWER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new envelope follower
  EnvelopeFollowerConfig createFollower({
    required String name,
    EnvelopeSourceType sourceType = EnvelopeSourceType.bus,
    int sourceId = 0,
    EnvelopeDetectionMode mode = EnvelopeDetectionMode.rms,
    double attackMs = 10.0,
    double releaseMs = 100.0,
    int? targetRtpcId,
  }) {
    final config = EnvelopeFollowerConfig(
      id: _nextId++,
      name: name,
      sourceType: sourceType,
      sourceId: sourceId,
      mode: mode,
      attackMs: attackMs,
      releaseMs: releaseMs,
      targetRtpcId: targetRtpcId,
    );

    _configs[config.id] = config;
    _states[config.id] = EnvelopeFollowerState(configId: config.id);

    _startUpdateLoopIfNeeded();
    debugPrint('[EnvelopeFollower] Created follower ${config.id}: ${config.name}');
    return config;
  }

  /// Update a follower configuration
  void updateFollower(EnvelopeFollowerConfig config) {
    _configs[config.id] = config;
    debugPrint('[EnvelopeFollower] Updated follower ${config.id}');
  }

  /// Remove a follower
  void removeFollower(int configId) {
    _configs.remove(configId);
    _states.remove(configId);

    if (_configs.isEmpty) {
      _stopUpdateLoop();
    }
    debugPrint('[EnvelopeFollower] Removed follower $configId');
  }

  /// Get a follower by ID
  EnvelopeFollowerConfig? getFollower(int configId) => _configs[configId];

  /// Get all followers
  List<EnvelopeFollowerConfig> get allFollowers => _configs.values.toList();

  /// Get follower state
  EnvelopeFollowerState? getState(int configId) => _states[configId];

  // ═══════════════════════════════════════════════════════════════════════════
  // ATTACK / RELEASE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set attack time in milliseconds (0.1-500ms)
  void setAttack(int configId, double attackMs) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(
      attackMs: attackMs.clamp(0.1, 500.0),
    );
  }

  /// Set release time in milliseconds (10-5000ms)
  void setRelease(int configId, double releaseMs) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(
      releaseMs: releaseMs.clamp(10.0, 5000.0),
    );
  }

  /// Calculate attack coefficient from time constant
  double _attackCoefficient(double attackMs) {
    return math.exp(-1.0 / (_sampleRate * attackMs / 1000.0));
  }

  /// Calculate release coefficient from time constant
  double _releaseCoefficient(double releaseMs) {
    return math.exp(-1.0 / (_sampleRate * releaseMs / 1000.0));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETECTION MODE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set detection mode
  void setMode(int configId, EnvelopeDetectionMode mode) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(mode: mode);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // THRESHOLD GATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set threshold in dB (-96 to 0dB)
  void setThreshold(int configId, double thresholdDb) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(
      thresholdDb: thresholdDb.clamp(-96.0, 0.0),
    );
  }

  /// Convert dB to linear
  double _dbToLinear(double db) {
    return math.pow(10.0, db / 20.0).toDouble();
  }

  /// Convert linear to dB
  double _linearToDb(double linear) {
    if (linear <= 0.0) return -96.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SMOOTHING FILTER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set smoothing time in milliseconds (0-200ms)
  void setSmoothing(int configId, double smoothingMs) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(
      smoothingMs: smoothingMs.clamp(0.0, 200.0),
    );
  }

  /// Calculate smoothing coefficient
  double _smoothingCoefficient(double smoothingMs) {
    if (smoothingMs <= 0.0) return 0.0;
    return math.exp(-1.0 / (_sampleRate * smoothingMs / 1000.0));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OUTPUT RANGE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set output range
  void setOutputRange(int configId, double min, double max) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(
      minOutput: min,
      maxOutput: max,
    );
  }

  /// Set inversion
  void setInverted(int configId, bool inverted) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(inverted: inverted);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC TARGET
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set target RTPC ID
  void setTargetRtpc(int configId, int? rtpcId) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(targetRtpcId: rtpcId);
    debugPrint('[EnvelopeFollower] Set RTPC target for $configId: $rtpcId');
  }

  /// Clear RTPC target
  void clearTargetRtpc(int configId) {
    setTargetRtpc(configId, null);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENABLE / DISABLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable a follower
  void setEnabled(int configId, bool enabled) {
    final config = _configs[configId];
    if (config == null) return;

    _configs[configId] = config.copyWith(enabled: enabled);

    if (!enabled) {
      _states[configId]?.reset();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROCESSING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Process an input sample and return envelope value
  /// This is the core envelope detection algorithm
  double processSample(int configId, double inputSample) {
    final config = _configs[configId];
    final state = _states[configId];
    if (config == null || state == null || !config.enabled) return 0.0;

    // Get absolute value
    final absInput = inputSample.abs();

    // Threshold gate
    final thresholdLinear = _dbToLinear(config.thresholdDb);
    if (absInput < thresholdLinear) {
      // Below threshold, use release
      final releaseCoeff = _releaseCoefficient(config.releaseMs);
      state.currentEnvelope = releaseCoeff * state.currentEnvelope;
    } else {
      // Apply detection based on mode
      double detectedLevel;
      switch (config.mode) {
        case EnvelopeDetectionMode.peak:
          detectedLevel = absInput;
          break;
        case EnvelopeDetectionMode.rms:
          // Simple RMS approximation (square, filter, sqrt)
          detectedLevel = math.sqrt(absInput * absInput);
          break;
        case EnvelopeDetectionMode.hybrid:
          // Use peak for attack, RMS for release
          final rmsLevel = math.sqrt(absInput * absInput);
          detectedLevel = absInput > state.currentEnvelope ? absInput : rmsLevel;
          break;
      }

      // Apply attack/release
      if (detectedLevel > state.currentEnvelope) {
        // Attack
        final attackCoeff = _attackCoefficient(config.attackMs);
        state.currentEnvelope = attackCoeff * state.currentEnvelope + (1.0 - attackCoeff) * detectedLevel;
      } else {
        // Release
        final releaseCoeff = _releaseCoefficient(config.releaseMs);
        state.currentEnvelope = releaseCoeff * state.currentEnvelope + (1.0 - releaseCoeff) * detectedLevel;
      }
    }

    // Apply smoothing
    final smoothCoeff = _smoothingCoefficient(config.smoothingMs);
    if (smoothCoeff > 0.0) {
      state.smoothedEnvelope = smoothCoeff * state.smoothedEnvelope + (1.0 - smoothCoeff) * state.currentEnvelope;
    } else {
      state.smoothedEnvelope = state.currentEnvelope;
    }

    // Map to output range
    var output = _mapToOutputRange(state.smoothedEnvelope, config);

    // Apply inversion
    if (config.inverted) {
      output = config.maxOutput - (output - config.minOutput);
    }

    state.currentOutputValue = output;
    return output;
  }

  /// Process a block of samples
  double processBlock(int configId, List<double> samples) {
    if (samples.isEmpty) return 0.0;

    final config = _configs[configId];
    if (config == null || !config.enabled) return 0.0;

    // Calculate block level based on mode
    double blockLevel;
    switch (config.mode) {
      case EnvelopeDetectionMode.peak:
        blockLevel = samples.map((s) => s.abs()).reduce(math.max);
        break;
      case EnvelopeDetectionMode.rms:
        final sumSquares = samples.fold<double>(0.0, (sum, s) => sum + s * s);
        blockLevel = math.sqrt(sumSquares / samples.length);
        break;
      case EnvelopeDetectionMode.hybrid:
        final peak = samples.map((s) => s.abs()).reduce(math.max);
        final sumSquares = samples.fold<double>(0.0, (sum, s) => sum + s * s);
        final rms = math.sqrt(sumSquares / samples.length);
        // Combine peak and RMS
        blockLevel = math.max(peak * 0.7, rms);
        break;
    }

    // Process as single sample (simplified for block processing)
    return processSample(configId, blockLevel);
  }

  /// Map envelope value to output range
  double _mapToOutputRange(double envelope, EnvelopeFollowerConfig config) {
    // Envelope is typically 0-1 range
    final normalized = envelope.clamp(0.0, 1.0);
    return config.minOutput + normalized * (config.maxOutput - config.minOutput);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPDATE LOOP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start the update loop for simulated input
  void _startUpdateLoopIfNeeded() {
    if (_updateTimer != null) return;
    if (_configs.isEmpty) return;

    // 60fps update rate
    const updateInterval = Duration(milliseconds: 16);
    _updateTimer = Timer.periodic(updateInterval, (_) => _updateTick());
    debugPrint('[EnvelopeFollower] Started update loop');
  }

  /// Stop the update loop
  void _stopUpdateLoop() {
    _updateTimer?.cancel();
    _updateTimer = null;
    debugPrint('[EnvelopeFollower] Stopped update loop');
  }

  /// Update tick - called periodically to update followers
  void _updateTick() {
    for (final config in _configs.values) {
      if (!config.enabled) continue;

      final state = _states[config.id];
      if (state == null) continue;

      // Simulate decay when no input (for demo purposes)
      // In real usage, processSample/processBlock would be called with actual audio
      final releaseCoeff = _releaseCoefficient(config.releaseMs);
      state.currentEnvelope *= releaseCoeff;

      final smoothCoeff = _smoothingCoefficient(config.smoothingMs);
      if (smoothCoeff > 0.0) {
        state.smoothedEnvelope = smoothCoeff * state.smoothedEnvelope +
            (1.0 - smoothCoeff) * state.currentEnvelope;
      } else {
        state.smoothedEnvelope = state.currentEnvelope;
      }

      var output = _mapToOutputRange(state.smoothedEnvelope, config);
      if (config.inverted) {
        output = config.maxOutput - (output - config.minOutput);
      }
      state.currentOutputValue = output;

      // Output to RTPC if configured
      if (config.targetRtpcId != null && _middleware != null) {
        _middleware!.setRtpc(config.targetRtpcId!, output);
      }

      // Notify value listeners
      for (final listener in _valueListeners) {
        listener(config.id, output);
      }
    }
  }

  /// Feed input to a follower (call this with actual audio levels)
  void feedInput(int configId, double level) {
    final config = _configs[configId];
    final state = _states[configId];
    if (config == null || state == null || !config.enabled) return;

    // Process the input level
    final output = processSample(configId, level);

    // Output to RTPC if configured
    if (config.targetRtpcId != null && _middleware != null) {
      _middleware!.setRtpc(config.targetRtpcId!, output);
    }

    // Notify listeners
    for (final listener in _valueListeners) {
      listener(configId, output);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LISTENERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a value change listener
  void addValueListener(void Function(int configId, double value) listener) {
    _valueListeners.add(listener);
  }

  /// Remove a value change listener
  void removeValueListener(void Function(int configId, double value) listener) {
    _valueListeners.remove(listener);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CURRENT VALUES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current output value for a follower
  double getCurrentValue(int configId) {
    return _states[configId]?.currentOutputValue ?? 0.0;
  }

  /// Get current envelope level (before output mapping)
  double getCurrentEnvelope(int configId) {
    return _states[configId]?.smoothedEnvelope ?? 0.0;
  }

  /// Get current envelope in dB
  double getCurrentEnvelopeDb(int configId) {
    final envelope = getCurrentEnvelope(configId);
    return _linearToDb(envelope);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export to JSON
  Map<String, dynamic> toJson() {
    return {
      'followers': _configs.values.map((c) => c.toJson()).toList(),
      'nextId': _nextId,
    };
  }

  /// Import from JSON
  void fromJson(Map<String, dynamic> json) {
    _configs.clear();
    _states.clear();

    final followersList = json['followers'] as List<dynamic>? ?? [];
    for (final followerJson in followersList) {
      final config = EnvelopeFollowerConfig.fromJson(followerJson as Map<String, dynamic>);
      _configs[config.id] = config;
      _states[config.id] = EnvelopeFollowerState(configId: config.id);
    }

    _nextId = json['nextId'] as int? ?? _configs.length + 1;
    _startUpdateLoopIfNeeded();

    debugPrint('[EnvelopeFollower] Loaded ${_configs.length} followers from JSON');
  }

  /// Clear all followers
  void clear() {
    _stopUpdateLoop();
    _configs.clear();
    _states.clear();
    _nextId = 1;
  }
}

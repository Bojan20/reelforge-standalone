/// Meter Provider
///
/// Real-time audio metering with:
/// - Peak/RMS levels
/// - Peak hold with decay
/// - Stereo L/R metering
/// - LUFS short-term
/// - Visibility-based throttling

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';

// ============ Types ============

class MeterState {
  /// Peak level normalized 0-1
  final double peak;
  /// Peak level right channel
  final double peakR;
  /// RMS level normalized 0-1
  final double rms;
  /// RMS level right channel
  final double rmsR;
  /// Peak hold (decaying)
  final double peakHold;
  /// Peak hold right channel
  final double peakHoldR;
  /// Is clipping
  final bool isClipping;
  /// LUFS short-term
  final double lufsShort;

  const MeterState({
    this.peak = 0,
    this.peakR = 0,
    this.rms = 0,
    this.rmsR = 0,
    this.peakHold = 0,
    this.peakHoldR = 0,
    this.isClipping = false,
    this.lufsShort = -60,
  });

  MeterState copyWith({
    double? peak,
    double? peakR,
    double? rms,
    double? rmsR,
    double? peakHold,
    double? peakHoldR,
    bool? isClipping,
    double? lufsShort,
  }) {
    return MeterState(
      peak: peak ?? this.peak,
      peakR: peakR ?? this.peakR,
      rms: rms ?? this.rms,
      rmsR: rmsR ?? this.rmsR,
      peakHold: peakHold ?? this.peakHold,
      peakHoldR: peakHoldR ?? this.peakHoldR,
      isClipping: isClipping ?? this.isClipping,
      lufsShort: lufsShort ?? this.lufsShort,
    );
  }

  static const MeterState zero = MeterState();
}

class BusMeterState {
  /// Current peak level (0-1)
  final double peak;
  /// RMS level (0-1)
  final double rms;
  /// Peak hold level (0-1)
  final double peakHold;
  /// Whether signal is clipping
  final bool clipping;

  const BusMeterState({
    this.peak = 0,
    this.rms = 0,
    this.peakHold = 0,
    this.clipping = false,
  });

  BusMeterState copyWith({
    double? peak,
    double? rms,
    double? peakHold,
    bool? clipping,
  }) {
    return BusMeterState(
      peak: peak ?? this.peak,
      rms: rms ?? this.rms,
      peakHold: peakHold ?? this.peakHold,
      clipping: clipping ?? this.clipping,
    );
  }

  static const BusMeterState zero = BusMeterState();
}

// ============ Constants ============

const double kPeakHoldTime = 1500; // ms to hold peak
const double kPeakDecayRate = 0.05; // decay per frame
const double kSmoothing = 0.8;

// ============ Provider ============

class MeterProvider extends ChangeNotifier {
  final Map<String, MeterState> _meterStates = {};
  final Map<String, double> _peakHoldL = {};
  final Map<String, double> _peakHoldR = {};
  final Map<String, DateTime> _lastPeakTime = {};

  Timer? _updateTimer;
  bool _isActive = true;
  bool _isPlaying = false;

  // Simulated noise for demo
  final Map<String, double> _noiseValues = {};

  Map<String, MeterState> get meterStates => Map.unmodifiable(_meterStates);

  MeterState getMeterState(String meterId) {
    return _meterStates[meterId] ?? MeterState.zero;
  }

  void setActive(bool active) {
    _isActive = active;
    if (active && _isPlaying) {
      _startUpdateLoop();
    } else if (!active) {
      _stopUpdateLoop();
    }
  }

  void setPlaying(bool playing) {
    _isPlaying = playing;
    if (playing && _isActive) {
      _startUpdateLoop();
    } else if (!playing) {
      _startDecayLoop();
    }
  }

  void _startUpdateLoop() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 16), // ~60fps
      (_) => _updateMeters(),
    );
  }

  void _startDecayLoop() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _decayMeters(),
    );
  }

  void _stopUpdateLoop() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  void _updateMeters() {
    final now = DateTime.now();

    for (final meterId in _meterStates.keys.toList()) {
      final state = _meterStates[meterId]!;

      // Smooth random walk for noise
      var noise = _noiseValues[meterId] ?? 0.5;
      noise += (_randomValue() - 0.5) * 0.3;
      noise = noise.clamp(0.1, 0.9);
      _noiseValues[meterId] = noise;

      // Simulated levels
      final peak = (noise + _randomValue() * 0.1).clamp(0.0, 1.0);
      final rms = noise * 0.7;

      // Peak hold decay
      var peakHoldL = _peakHoldL[meterId] ?? 0;
      var peakHoldR = _peakHoldR[meterId] ?? 0;
      final lastPeak = _lastPeakTime[meterId] ?? now;

      if (peak > peakHoldL) {
        peakHoldL = peak;
        _lastPeakTime[meterId] = now;
      } else if (now.difference(lastPeak).inMilliseconds > kPeakHoldTime) {
        peakHoldL = (peakHoldL - kPeakDecayRate).clamp(0.0, 1.0);
      }

      if (peak > peakHoldR) {
        peakHoldR = peak;
      } else if (now.difference(lastPeak).inMilliseconds > kPeakHoldTime) {
        peakHoldR = (peakHoldR - kPeakDecayRate).clamp(0.0, 1.0);
      }

      _peakHoldL[meterId] = peakHoldL;
      _peakHoldR[meterId] = peakHoldR;

      _meterStates[meterId] = state.copyWith(
        peak: peak,
        peakR: peak * 0.95,
        rms: rms,
        rmsR: rms * 0.95,
        peakHold: peakHoldL,
        peakHoldR: peakHoldR,
        isClipping: peak > 0.99,
        lufsShort: _peakToLufs(rms),
      );
    }

    notifyListeners();
  }

  void _decayMeters() {
    bool hasActivity = false;

    for (final meterId in _meterStates.keys.toList()) {
      final state = _meterStates[meterId]!;

      final newPeak = state.peak * 0.85;
      final newRms = state.rms * 0.85;
      final newPeakHold = state.peakHold * 0.9;

      if (newPeak > 0.001 || newRms > 0.001) {
        hasActivity = true;
      }

      _meterStates[meterId] = state.copyWith(
        peak: newPeak,
        peakR: state.peakR * 0.85,
        rms: newRms,
        rmsR: state.rmsR * 0.85,
        peakHold: newPeakHold,
        peakHoldR: state.peakHoldR * 0.9,
        isClipping: false,
      );
    }

    notifyListeners();

    if (!hasActivity) {
      _stopUpdateLoop();
    }
  }

  void registerMeter(String meterId) {
    if (!_meterStates.containsKey(meterId)) {
      _meterStates[meterId] = MeterState.zero;
      _peakHoldL[meterId] = 0;
      _peakHoldR[meterId] = 0;
      _noiseValues[meterId] = 0.5;
    }
  }

  void unregisterMeter(String meterId) {
    _meterStates.remove(meterId);
    _peakHoldL.remove(meterId);
    _peakHoldR.remove(meterId);
    _noiseValues.remove(meterId);
    _lastPeakTime.remove(meterId);
  }

  double _peakToLufs(double peak) {
    // Rough approximation
    if (peak <= 0) return -60;
    return 20 * _log10(peak) - 14;
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}

// ============ Utility Functions ============

/// Convert linear amplitude to dB
double linearToDb(double linear) {
  if (linear <= 0) return double.negativeInfinity;
  return 20 * _log10(linear);
}

/// Convert dB to linear amplitude
double dbToLinear(double db) {
  return _pow(10, db / 20);
}

/// Convert dB to normalized 0-1
double dbToNormalized(double db, {double minDb = -60, double maxDb = 0}) {
  if (db <= minDb) return 0;
  if (db >= maxDb) return 1;
  return (db - minDb) / (maxDb - minDb);
}

/// Convert normalized 0-1 to dB
double normalizedToDb(double normalized, {double minDb = -60, double maxDb = 0}) {
  return minDb + normalized * (maxDb - minDb);
}

/// Get color for meter level
Color getMeterColor(double level) {
  if (level > 0.95) return const Color(0xFFEF4444); // Red - clipping
  if (level > 0.80) return const Color(0xFFF59E0B); // Yellow - hot
  if (level > 0.50) return const Color(0xFF22C55E); // Green - normal
  return const Color(0xFF4ADE80); // Light green - low
}

// Random generator for demo/simulation
final _random = math.Random();
double _randomValue() => _random.nextDouble();

// Math utilities
double _log10(double x) => x > 0 ? math.log(x) / math.ln10 : double.negativeInfinity;
double _pow(double x, double y) => math.pow(x, y).toDouble();

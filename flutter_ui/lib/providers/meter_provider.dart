// Meter Provider
//
// Real-time audio metering with:
// - Peak/RMS levels
// - Peak hold with decay
// - Stereo L/R metering
// - LUFS short-term
// - Visibility-based throttling
// - Integration with Rust engine metering

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';

import '../src/rust/engine_api.dart';

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

  StreamSubscription<MeteringState>? _meteringSubscription;
  StreamSubscription<TransportState>? _transportSubscription;
  Timer? _decayTimer;
  Timer? _silenceTimer;
  bool _isActive = true;
  bool _isPlaying = false;
  DateTime _lastMeteringUpdate = DateTime.now();
  DateTime? _lastNotify; // Throttling for notifyListeners()
  static const _throttleMs = 33; // 30fps max update rate

  // Master meter state (from engine)
  MeterState _masterState = MeterState.zero;

  // Bus meter states (from engine)
  final List<MeterState> _busStates = [];

  MeterProvider() {
    _subscribeToEngine();
    _subscribeToTransport();
    _startSilenceDetection();
  }

  /// Throttled notify - max 30fps to prevent rebuild storm
  void _throttledNotify() {
    final now = DateTime.now();
    if (_lastNotify != null &&
        now.difference(_lastNotify!).inMilliseconds < _throttleMs) {
      return; // Skip this update
    }
    _lastNotify = now;
    notifyListeners();
  }

  /// Subscribe to transport state to detect playback stop
  void _subscribeToTransport() {
    _transportSubscription = engine.transportStream.listen((transport) {
      final wasPlaying = _isPlaying;
      _isPlaying = transport.isPlaying;

      // When playback stops, immediately start decay (Cubase-style instant meter drop)
      if (wasPlaying && !_isPlaying) {
        _startDecayLoop();
      }
    });
  }

  /// Start silence detection timer - if no metering updates for 100ms, start decay
  void _startSilenceDetection() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _checkForSilence(),
    );
  }

  void _checkForSilence() {
    final now = DateTime.now();
    final timeSinceUpdate = now.difference(_lastMeteringUpdate).inMilliseconds;

    // If no metering updates for 100ms + we have non-zero levels, start decay
    if (timeSinceUpdate > 100 && _decayTimer == null) {
      final hasSignal = _masterState.peak > 0.001 ||
          _masterState.rms > 0.001 ||
          _busStates.any((s) => s.peak > 0.001 || s.rms > 0.001);

      if (hasSignal) {
        _startDecayLoop();
      }
    }
  }

  Map<String, MeterState> get meterStates => Map.unmodifiable(_meterStates);
  MeterState get masterState => _masterState;
  List<MeterState> get busStates => List.unmodifiable(_busStates);

  MeterState getMeterState(String meterId) {
    return _meterStates[meterId] ?? MeterState.zero;
  }

  /// Get bus meter state by index
  MeterState getBusState(int index) {
    if (index >= 0 && index < _busStates.length) {
      return _busStates[index];
    }
    return MeterState.zero;
  }

  void setActive(bool active) {
    _isActive = active;
    if (!active) {
      _startDecayLoop();
    }
  }

  void _subscribeToEngine() {
    _meteringSubscription = engine.meteringStream.listen(_onMeteringUpdate);
  }

  void _onMeteringUpdate(MeteringState metering) {
    if (!_isActive) return;

    final now = DateTime.now();
    _lastMeteringUpdate = now;

    // Stop decay timer when we receive new data
    _decayTimer?.cancel();
    _decayTimer = null;

    // Update master meter
    _masterState = _convertToMeterState(
      'master',
      metering.masterPeakL,
      metering.masterPeakR,
      metering.masterRmsL,
      metering.masterRmsR,
      metering.masterLufsS,
      now,
    );

    // Update bus meters
    _busStates.clear();
    for (int i = 0; i < metering.buses.length; i++) {
      final bus = metering.buses[i];
      final busState = _convertToMeterState(
        'bus_$i',
        bus.peakL,
        bus.peakR,
        bus.rmsL,
        bus.rmsR,
        -14.0, // No LUFS for individual buses
        now,
      );
      _busStates.add(busState);
    }

    // Update registered meters (for custom meter IDs)
    for (final meterId in _meterStates.keys.toList()) {
      if (meterId == 'master') {
        _meterStates[meterId] = _masterState;
      } else if (meterId.startsWith('bus_')) {
        final index = int.tryParse(meterId.substring(4));
        if (index != null && index < _busStates.length) {
          _meterStates[meterId] = _busStates[index];
        }
      }
    }

    _throttledNotify(); // Throttled to 30fps
  }

  /// Convert dB values from engine to normalized MeterState
  MeterState _convertToMeterState(
    String meterId,
    double peakLDb,
    double peakRDb,
    double rmsLDb,
    double rmsRDb,
    double lufsShort,
    DateTime now,
  ) {
    // Convert dB to normalized 0-1 (assuming -60dB to 0dB range)
    final peakL = dbToNormalized(peakLDb);
    final peakR = dbToNormalized(peakRDb);
    final rmsL = dbToNormalized(rmsLDb);
    final rmsR = dbToNormalized(rmsRDb);

    // Peak hold logic
    var peakHoldL = _peakHoldL[meterId] ?? 0;
    var peakHoldR = _peakHoldR[meterId] ?? 0;
    final lastPeak = _lastPeakTime[meterId] ?? now;

    if (peakL > peakHoldL) {
      peakHoldL = peakL;
      _lastPeakTime[meterId] = now;
    } else if (now.difference(lastPeak).inMilliseconds > kPeakHoldTime) {
      peakHoldL = (peakHoldL - kPeakDecayRate).clamp(0.0, 1.0);
    }

    if (peakR > peakHoldR) {
      peakHoldR = peakR;
    } else if (now.difference(lastPeak).inMilliseconds > kPeakHoldTime) {
      peakHoldR = (peakHoldR - kPeakDecayRate).clamp(0.0, 1.0);
    }

    _peakHoldL[meterId] = peakHoldL;
    _peakHoldR[meterId] = peakHoldR;

    return MeterState(
      peak: peakL,
      peakR: peakR,
      rms: rmsL,
      rmsR: rmsR,
      peakHold: peakHoldL,
      peakHoldR: peakHoldR,
      isClipping: peakL > 0.99 || peakR > 0.99,
      lufsShort: lufsShort,
    );
  }

  void _startDecayLoop() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _decayMeters(),
    );
  }

  void _stopDecayLoop() {
    _decayTimer?.cancel();
    _decayTimer = null;
  }

  void _decayMeters() {
    bool hasActivity = false;

    // Decay master
    if (_masterState.peak > 0.001 || _masterState.rms > 0.001) {
      hasActivity = true;
      _masterState = _masterState.copyWith(
        peak: _masterState.peak * 0.85,
        peakR: _masterState.peakR * 0.85,
        rms: _masterState.rms * 0.85,
        rmsR: _masterState.rmsR * 0.85,
        peakHold: _masterState.peakHold * 0.9,
        peakHoldR: _masterState.peakHoldR * 0.9,
        isClipping: false,
      );
    }

    // Decay buses
    for (int i = 0; i < _busStates.length; i++) {
      final state = _busStates[i];
      if (state.peak > 0.001 || state.rms > 0.001) {
        hasActivity = true;
        _busStates[i] = state.copyWith(
          peak: state.peak * 0.85,
          peakR: state.peakR * 0.85,
          rms: state.rms * 0.85,
          rmsR: state.rmsR * 0.85,
          peakHold: state.peakHold * 0.9,
          peakHoldR: state.peakHoldR * 0.9,
          isClipping: false,
        );
      }
    }

    // Decay registered meters
    for (final meterId in _meterStates.keys.toList()) {
      final state = _meterStates[meterId]!;

      if (state.peak > 0.001 || state.rms > 0.001) {
        hasActivity = true;
      }

      _meterStates[meterId] = state.copyWith(
        peak: state.peak * 0.85,
        peakR: state.peakR * 0.85,
        rms: state.rms * 0.85,
        rmsR: state.rmsR * 0.85,
        peakHold: state.peakHold * 0.9,
        peakHoldR: state.peakHoldR * 0.9,
        isClipping: false,
      );
    }

    _throttledNotify(); // Throttled to 30fps

    if (!hasActivity) {
      _stopDecayLoop();
    }
  }

  void registerMeter(String meterId) {
    if (!_meterStates.containsKey(meterId)) {
      _meterStates[meterId] = MeterState.zero;
      _peakHoldL[meterId] = 0;
      _peakHoldR[meterId] = 0;
    }
  }

  void unregisterMeter(String meterId) {
    _meterStates.remove(meterId);
    _peakHoldL.remove(meterId);
    _peakHoldR.remove(meterId);
    _lastPeakTime.remove(meterId);
  }

  @override
  void dispose() {
    _meteringSubscription?.cancel();
    _transportSubscription?.cancel();
    _decayTimer?.cancel();
    _silenceTimer?.cancel();
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

// Math utilities
double _log10(double x) => x > 0 ? math.log(x) / math.ln10 : double.negativeInfinity;
double _pow(double x, double y) => math.pow(x, y).toDouble();

// Meter Provider - Cubase-Style Optimized
//
// Real-time audio metering with:
// - Peak/RMS levels
// - Peak hold with decay
// - Stereo L/R metering
// - LUFS short-term
// - OPTIMIZED: No rebuild storms, minimal allocations

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

  /// Check if meter has any activity worth displaying
  bool get hasActivity => peak > 0.001 || rms > 0.001 || peakR > 0.001 || rmsR > 0.001;

  static const MeterState zero = MeterState();
}

class BusMeterState {
  final double peak;
  final double rms;
  final double peakHold;
  final bool clipping;

  const BusMeterState({
    this.peak = 0,
    this.rms = 0,
    this.peakHold = 0,
    this.clipping = false,
  });

  static const BusMeterState zero = BusMeterState();
}

// ============ Constants ============

const double kPeakHoldTime = 1500; // ms to hold peak
const double kPeakDecayRate = 0.05; // decay per frame
const double kMeterDecay = 0.85; // multiplier for meter decay
const double kPeakHoldDecay = 0.9; // multiplier for peak hold decay
const double kActivityThreshold = 0.001; // below this = silent

// ============ Provider ============

class MeterProvider extends ChangeNotifier {
  // OPTIMIZED: Use fixed-size list for buses instead of dynamic clear/rebuild
  final List<MeterState> _busStates = List.filled(6, MeterState.zero, growable: false);
  int _activeBusCount = 0;

  // OPTIMIZED: Single map for registered meters, iterate keys directly
  final Map<String, MeterState> _meterStates = {};

  // OPTIMIZED: Combined peak hold data to reduce map lookups
  final Map<String, _PeakHoldData> _peakHoldData = {};

  StreamSubscription<MeteringState>? _meteringSubscription;
  StreamSubscription<TransportState>? _transportSubscription;
  Timer? _decayTimer;
  bool _isActive = true;
  bool _isPlaying = false;
  int _lastNotifyMs = 0;

  // OPTIMIZED: 20Hz = 50ms (matches engine metering rate, no wasted cycles)
  static const _updateIntervalMs = 50;

  MeterState _masterState = MeterState.zero;

  MeterProvider() {
    _subscribeToEngine();
    _subscribeToTransport();
  }

  /// Throttled notify - max 30fps
  void _throttledNotify() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastNotifyMs < _updateIntervalMs) {
      return;
    }
    _lastNotifyMs = nowMs;
    notifyListeners();
  }

  void _subscribeToTransport() {
    _transportSubscription = engine.transportStream.listen((transport) {
      final wasPlaying = _isPlaying;
      _isPlaying = transport.isPlaying;

      if (wasPlaying && !_isPlaying) {
        _startDecayLoop();
      }
    });
  }

  Map<String, MeterState> get meterStates => _meterStates;
  MeterState get masterState => _masterState;
  List<MeterState> get busStates => _busStates.sublist(0, _activeBusCount);

  MeterState getMeterState(String meterId) {
    return _meterStates[meterId] ?? MeterState.zero;
  }

  MeterState getBusState(int index) {
    if (index >= 0 && index < _activeBusCount) {
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

    // Stop decay when receiving new data
    _decayTimer?.cancel();
    _decayTimer = null;

    final now = DateTime.now();

    // Update master
    _masterState = _convertToMeterState(
      'master',
      metering.masterPeakL,
      metering.masterPeakR,
      metering.masterRmsL,
      metering.masterRmsR,
      metering.masterLufsS,
      now,
    );

    // OPTIMIZED: Update buses in-place, no clear/rebuild
    _activeBusCount = metering.buses.length.clamp(0, 6);
    for (int i = 0; i < _activeBusCount; i++) {
      final bus = metering.buses[i];
      _busStates[i] = _convertToMeterState(
        'bus_$i',
        bus.peakL,
        bus.peakR,
        bus.rmsL,
        bus.rmsR,
        -14.0,
        now,
      );
    }

    // OPTIMIZED: Update registered meters directly (no toList() copy)
    _meterStates.forEach((meterId, _) {
      if (meterId == 'master') {
        _meterStates[meterId] = _masterState;
      } else if (meterId.startsWith('bus_')) {
        final index = int.tryParse(meterId.substring(4));
        if (index != null && index < _activeBusCount) {
          _meterStates[meterId] = _busStates[index];
        }
      }
    });

    _throttledNotify();
  }

  MeterState _convertToMeterState(
    String meterId,
    double peakLDb,
    double peakRDb,
    double rmsLDb,
    double rmsRDb,
    double lufsShort,
    DateTime now,
  ) {
    final peakL = dbToNormalized(peakLDb);
    final peakR = dbToNormalized(peakRDb);
    final rmsL = dbToNormalized(rmsLDb);
    final rmsR = dbToNormalized(rmsRDb);

    // OPTIMIZED: Get or create peak hold data
    var holdData = _peakHoldData[meterId];
    if (holdData == null) {
      holdData = _PeakHoldData();
      _peakHoldData[meterId] = holdData;
    }

    // Peak hold logic
    if (peakL > holdData.peakHoldL) {
      holdData.peakHoldL = peakL;
      holdData.lastPeakTime = now;
    } else if (now.difference(holdData.lastPeakTime).inMilliseconds > kPeakHoldTime) {
      holdData.peakHoldL = (holdData.peakHoldL - kPeakDecayRate).clamp(0.0, 1.0);
    }

    if (peakR > holdData.peakHoldR) {
      holdData.peakHoldR = peakR;
    } else if (now.difference(holdData.lastPeakTime).inMilliseconds > kPeakHoldTime) {
      holdData.peakHoldR = (holdData.peakHoldR - kPeakDecayRate).clamp(0.0, 1.0);
    }

    return MeterState(
      peak: peakL,
      peakR: peakR,
      rms: rmsL,
      rmsR: rmsR,
      peakHold: holdData.peakHoldL,
      peakHoldR: holdData.peakHoldR,
      isClipping: peakL > 0.99 || peakR > 0.99,
      lufsShort: lufsShort,
    );
  }

  void _startDecayLoop() {
    _decayTimer?.cancel();
    // OPTIMIZED: Decay at same rate as notify throttle (33ms = 30fps)
    _decayTimer = Timer.periodic(
      const Duration(milliseconds: _updateIntervalMs),
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
    if (_masterState.hasActivity) {
      hasActivity = true;
      _masterState = _masterState.copyWith(
        peak: _masterState.peak * kMeterDecay,
        peakR: _masterState.peakR * kMeterDecay,
        rms: _masterState.rms * kMeterDecay,
        rmsR: _masterState.rmsR * kMeterDecay,
        peakHold: _masterState.peakHold * kPeakHoldDecay,
        peakHoldR: _masterState.peakHoldR * kPeakHoldDecay,
        isClipping: false,
      );
    }

    // Decay buses (only active ones)
    for (int i = 0; i < _activeBusCount; i++) {
      final state = _busStates[i];
      if (state.hasActivity) {
        hasActivity = true;
        _busStates[i] = state.copyWith(
          peak: state.peak * kMeterDecay,
          peakR: state.peakR * kMeterDecay,
          rms: state.rms * kMeterDecay,
          rmsR: state.rmsR * kMeterDecay,
          peakHold: state.peakHold * kPeakHoldDecay,
          peakHoldR: state.peakHoldR * kPeakHoldDecay,
          isClipping: false,
        );
      }
    }

    // OPTIMIZED: Iterate directly, no toList() copy
    _meterStates.forEach((meterId, state) {
      if (state.hasActivity) {
        hasActivity = true;
        _meterStates[meterId] = state.copyWith(
          peak: state.peak * kMeterDecay,
          peakR: state.peakR * kMeterDecay,
          rms: state.rms * kMeterDecay,
          rmsR: state.rmsR * kMeterDecay,
          peakHold: state.peakHold * kPeakHoldDecay,
          peakHoldR: state.peakHoldR * kPeakHoldDecay,
          isClipping: false,
        );
      }
    });

    // Only notify if there's activity (prevents unnecessary rebuilds)
    if (hasActivity) {
      _throttledNotify();
    } else {
      _stopDecayLoop();
    }
  }

  void registerMeter(String meterId) {
    if (!_meterStates.containsKey(meterId)) {
      _meterStates[meterId] = MeterState.zero;
      _peakHoldData[meterId] = _PeakHoldData();
    }
  }

  void unregisterMeter(String meterId) {
    _meterStates.remove(meterId);
    _peakHoldData.remove(meterId);
  }

  @override
  void dispose() {
    _meteringSubscription?.cancel();
    _transportSubscription?.cancel();
    _decayTimer?.cancel();
    super.dispose();
  }
}

/// OPTIMIZED: Combined peak hold data to reduce map lookups
class _PeakHoldData {
  double peakHoldL = 0;
  double peakHoldR = 0;
  DateTime lastPeakTime = DateTime.now();
}

// ============ Utility Functions ============

double linearToDb(double linear) {
  if (linear <= 0) return double.negativeInfinity;
  return 20 * _log10(linear);
}

double dbToLinear(double db) {
  return _pow(10, db / 20);
}

double dbToNormalized(double db, {double minDb = -60, double maxDb = 0}) {
  if (db <= minDb) return 0;
  if (db >= maxDb) return 1;
  return (db - minDb) / (maxDb - minDb);
}

double normalizedToDb(double normalized, {double minDb = -60, double maxDb = 0}) {
  return minDb + normalized * (maxDb - minDb);
}

Color getMeterColor(double level) {
  if (level > 0.95) return const Color(0xFFEF4444);
  if (level > 0.80) return const Color(0xFFF59E0B);
  if (level > 0.50) return const Color(0xFF22C55E);
  return const Color(0xFF4ADE80);
}

double _log10(double x) => x > 0 ? math.log(x) / math.ln10 : double.negativeInfinity;
double _pow(double x, double y) => math.pow(x, y).toDouble();

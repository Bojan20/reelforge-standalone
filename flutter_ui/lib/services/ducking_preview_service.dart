/// Ducking Preview Service (M3.2)
///
/// Provides audio preview for testing ducking rules without full mix.
/// Generates sine/noise signals and visualizes ducking envelope.
///
/// Features:
/// - Sine wave generator for source bus preview
/// - White noise generator for sustained sound
/// - Visual ducking curve display
/// - Real-time envelope visualization

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/middleware_models.dart';
import 'ducking_service.dart';

/// Preview signal type
enum PreviewSignalType {
  sine,
  noise,
  pulse,
}

/// Ducking envelope point for visualization
class DuckingEnvelopePoint {
  final double timeMs;
  final double level; // 0.0 = full duck, 1.0 = no duck

  const DuckingEnvelopePoint(this.timeMs, this.level);
}

/// Service for previewing ducking behavior
class DuckingPreviewService {
  static final DuckingPreviewService _instance = DuckingPreviewService._();
  static DuckingPreviewService get instance => _instance;

  DuckingPreviewService._();

  /// Whether a preview is currently running
  bool _isPreviewActive = false;
  bool get isPreviewActive => _isPreviewActive;

  /// Current preview rule
  DuckingRule? _currentRule;
  DuckingRule? get currentRule => _currentRule;

  /// Preview timer
  Timer? _previewTimer;

  /// Envelope history for visualization
  final List<DuckingEnvelopePoint> _envelopeHistory = [];
  List<DuckingEnvelopePoint> get envelopeHistory =>
      List.unmodifiable(_envelopeHistory);

  /// Current ducking level (0.0-1.0, where 0.0 = full duck)
  double _currentDuckLevel = 1.0;
  double get currentDuckLevel => _currentDuckLevel;

  /// Preview start time
  DateTime? _previewStartTime;

  /// Signal type
  PreviewSignalType _signalType = PreviewSignalType.sine;
  PreviewSignalType get signalType => _signalType;

  /// Preview duration in ms
  int _previewDurationMs = 3000;
  int get previewDurationMs => _previewDurationMs;

  /// Listeners for UI updates
  final List<VoidCallback> _listeners = [];

  /// Add listener
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notify listeners
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Start preview for a ducking rule
  void startPreview(
    DuckingRule rule, {
    PreviewSignalType signal = PreviewSignalType.sine,
    int durationMs = 3000,
  }) {
    if (_isPreviewActive) stopPreview();

    _currentRule = rule;
    _signalType = signal;
    _previewDurationMs = durationMs;
    _isPreviewActive = true;
    _envelopeHistory.clear();
    _currentDuckLevel = 1.0;
    _previewStartTime = DateTime.now();


    // Simulate source bus becoming active
    DuckingService.instance.notifyBusActive(rule.sourceBusId);

    // Start envelope tracking
    const updateInterval = Duration(milliseconds: 16);
    _previewTimer = Timer.periodic(updateInterval, _updateEnvelope);

    _notifyListeners();
  }

  /// Update envelope during preview
  void _updateEnvelope(Timer timer) {
    if (!_isPreviewActive || _currentRule == null) {
      stopPreview();
      return;
    }

    final rule = _currentRule!;
    final elapsedMs = DateTime.now().difference(_previewStartTime!).inMilliseconds.toDouble();

    // Calculate expected ducking level based on attack curve
    double targetLevel;
    if (elapsedMs < rule.attackMs) {
      // Attack phase - ducking increasing
      final attackProgress = elapsedMs / rule.attackMs;
      targetLevel = 1.0 - _applyCurve(attackProgress, rule.curve);
    } else if (elapsedMs < _previewDurationMs - rule.releaseMs) {
      // Sustain phase - full duck
      targetLevel = 1.0 - _dbToLinear(rule.duckAmountDb);
    } else if (elapsedMs < _previewDurationMs) {
      // Release phase - ducking decreasing
      final releaseProgress =
          (elapsedMs - (_previewDurationMs - rule.releaseMs)) / rule.releaseMs;
      final duckAmount = 1.0 - _dbToLinear(rule.duckAmountDb);
      targetLevel = 1.0 - (duckAmount * (1.0 - _applyCurve(releaseProgress, rule.curve)));
    } else {
      // Preview complete
      stopPreview();
      return;
    }

    _currentDuckLevel = targetLevel;
    _envelopeHistory.add(DuckingEnvelopePoint(elapsedMs, targetLevel));

    // Limit history size
    if (_envelopeHistory.length > 500) {
      _envelopeHistory.removeAt(0);
    }

    _notifyListeners();
  }

  /// Apply ducking curve to progress (0-1)
  double _applyCurve(double progress, DuckingCurve curve) {
    switch (curve) {
      case DuckingCurve.linear:
        return progress;
      case DuckingCurve.exponential:
        return math.pow(progress, 2).toDouble();
      case DuckingCurve.logarithmic:
        return math.log(1 + progress * (math.e - 1)) / math.log(math.e);
      case DuckingCurve.sCurve:
        return progress < 0.5
            ? 2 * progress * progress
            : 1 - math.pow(-2 * progress + 2, 2) / 2;
    }
  }

  /// Convert dB to linear (0-1 where 0dB = 1.0, -48dB = 0.004)
  double _dbToLinear(double db) {
    return math.pow(10.0, db / 20.0).toDouble();
  }

  /// Stop preview
  void stopPreview() {
    if (!_isPreviewActive) return;

    _previewTimer?.cancel();
    _previewTimer = null;

    if (_currentRule != null) {
      DuckingService.instance.notifyBusInactive(_currentRule!.sourceBusId);
    }

    _isPreviewActive = false;
    _currentDuckLevel = 1.0;

    _notifyListeners();
  }

  /// Generate envelope curve points for visualization
  List<DuckingEnvelopePoint> generateIdealEnvelope(DuckingRule rule,
      {int durationMs = 3000}) {
    final points = <DuckingEnvelopePoint>[];
    const resolution = 2.0; // ms per point

    for (double t = 0; t <= durationMs; t += resolution) {
      double level;

      if (t < rule.attackMs) {
        // Attack phase
        final progress = t / rule.attackMs;
        final duckAmount = 1.0 - _dbToLinear(rule.duckAmountDb);
        level = 1.0 - (duckAmount * _applyCurve(progress, rule.curve));
      } else if (t < durationMs - rule.releaseMs) {
        // Sustain phase
        level = _dbToLinear(rule.duckAmountDb);
      } else {
        // Release phase
        final progress = (t - (durationMs - rule.releaseMs)) / rule.releaseMs;
        final duckAmount = 1.0 - _dbToLinear(rule.duckAmountDb);
        level = 1.0 - (duckAmount * (1.0 - _applyCurve(progress, rule.curve)));
      }

      points.add(DuckingEnvelopePoint(t, level));
    }

    return points;
  }

  /// Get preview progress (0-1)
  double get previewProgress {
    if (!_isPreviewActive || _previewStartTime == null) return 0.0;
    final elapsed =
        DateTime.now().difference(_previewStartTime!).inMilliseconds;
    return (elapsed / _previewDurationMs).clamp(0.0, 1.0);
  }

  /// Dispose resources
  void dispose() {
    stopPreview();
    _listeners.clear();
  }
}

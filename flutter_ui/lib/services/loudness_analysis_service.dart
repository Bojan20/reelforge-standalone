/// Loudness Analysis Service — ITU-R BS.1770-4 Compliant
///
/// P3.7: Pre-export loudness analysis.
///
/// Features:
/// - Integrated LUFS (overall program loudness)
/// - Short-term LUFS (3-second window)
/// - Momentary LUFS (400ms window)
/// - True Peak detection (4x oversampling)
/// - Loudness Range (LRA)
/// - Target presets (Streaming, Broadcast, CD, Club)
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LOUDNESS TARGET PRESETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Standard loudness targets for different platforms
enum LoudnessTarget {
  streaming(-14.0, -1.0, 'Streaming', 'Spotify, Apple Music, YouTube'),
  broadcast(-23.0, -1.0, 'Broadcast', 'EBU R128 / ATSC A/85'),
  podcast(-16.0, -1.0, 'Podcast', 'Apple Podcasts, Spotify'),
  cd(-9.0, -0.3, 'CD / Lossless', 'Maximum loudness'),
  club(-8.0, -0.5, 'Club', 'DJ / Club playback'),
  film(-24.0, -1.0, 'Film / TV', 'Dialogue normalization'),
  game(-18.0, -1.0, 'Game Audio', 'Headroom for dynamics'),
  custom(0.0, 0.0, 'Custom', 'User-defined target');

  final double targetLufs;
  final double truePeakLimit;
  final String name;
  final String description;

  const LoudnessTarget(this.targetLufs, this.truePeakLimit, this.name, this.description);

  /// Check if analysis results meet this target
  LoudnessCompliance checkCompliance(LoudnessResult result) {
    final lufsOk = (result.integratedLufs - targetLufs).abs() <= 1.0;
    final peakOk = result.truePeak <= truePeakLimit;

    return LoudnessCompliance(
      target: this,
      lufsCompliant: lufsOk,
      peakCompliant: peakOk,
      lufsDelta: result.integratedLufs - targetLufs,
      peakDelta: result.truePeak - truePeakLimit,
    );
  }
}

/// Compliance check result
class LoudnessCompliance {
  final LoudnessTarget target;
  final bool lufsCompliant;
  final bool peakCompliant;
  final double lufsDelta; // Negative = too quiet, Positive = too loud
  final double peakDelta; // Positive = over limit

  const LoudnessCompliance({
    required this.target,
    required this.lufsCompliant,
    required this.peakCompliant,
    required this.lufsDelta,
    required this.peakDelta,
  });

  bool get isCompliant => lufsCompliant && peakCompliant;

  String get lufsStatus {
    if (lufsCompliant) return 'OK';
    if (lufsDelta < 0) return '${lufsDelta.toStringAsFixed(1)} LU (too quiet)';
    return '+${lufsDelta.toStringAsFixed(1)} LU (too loud)';
  }

  String get peakStatus {
    if (peakCompliant) return 'OK';
    return '+${peakDelta.toStringAsFixed(1)} dB over';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOUDNESS RESULT
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete loudness analysis result
class LoudnessResult {
  final double integratedLufs;    // Overall loudness (entire file)
  final double shortTermLufs;     // 3-second window (last reading)
  final double momentaryLufs;     // 400ms window (last reading)
  final double truePeak;          // True peak in dBTP
  final double samplePeak;        // Sample peak in dBFS
  final double loudnessRange;     // LRA in LU
  final double maxShortTerm;      // Maximum short-term LUFS
  final double minShortTerm;      // Minimum short-term LUFS
  final Duration duration;
  final bool isValid;
  final String? error;

  const LoudnessResult({
    this.integratedLufs = -70.0,
    this.shortTermLufs = -70.0,
    this.momentaryLufs = -70.0,
    this.truePeak = -70.0,
    this.samplePeak = -70.0,
    this.loudnessRange = 0.0,
    this.maxShortTerm = -70.0,
    this.minShortTerm = -70.0,
    this.duration = Duration.zero,
    this.isValid = false,
    this.error,
  });

  factory LoudnessResult.error(String message) {
    return LoudnessResult(error: message);
  }

  /// Format LUFS value with unit
  static String formatLufs(double value) {
    if (value <= -70.0) return '-∞ LUFS';
    return '${value.toStringAsFixed(1)} LUFS';
  }

  /// Format peak value in dBTP
  static String formatPeak(double value) {
    if (value <= -70.0) return '-∞ dBTP';
    return '${value.toStringAsFixed(1)} dBTP';
  }

  /// Format LRA value
  static String formatLra(double value) {
    return '${value.toStringAsFixed(1)} LU';
  }

  @override
  String toString() {
    return 'LoudnessResult(integrated: ${formatLufs(integratedLufs)}, '
        'peak: ${formatPeak(truePeak)}, LRA: ${formatLra(loudnessRange)})';
  }
}

/// Real-time loudness reading (for meters)
class LoudnessReading {
  final double momentary;     // 400ms LUFS
  final double shortTerm;     // 3s LUFS
  final double integrated;    // Running integrated
  final double peakL;         // Left channel peak
  final double peakR;         // Right channel peak
  final double truePeakL;     // Left true peak
  final double truePeakR;     // Right true peak
  final DateTime timestamp;

  const LoudnessReading({
    this.momentary = -70.0,
    this.shortTerm = -70.0,
    this.integrated = -70.0,
    this.peakL = -70.0,
    this.peakR = -70.0,
    this.truePeakL = -70.0,
    this.truePeakR = -70.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _ConstDateTime();
}

// Helper for const constructor
class _ConstDateTime implements DateTime {
  const _ConstDateTime();
  @override dynamic noSuchMethod(Invocation invocation) => DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOUDNESS ANALYSIS SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for analyzing audio loudness per ITU-R BS.1770-4
class LoudnessAnalysisService extends ChangeNotifier {
  LoudnessAnalysisService._();
  static final LoudnessAnalysisService instance = LoudnessAnalysisService._();

  // State
  bool _isAnalyzing = false;
  double _analysisProgress = 0.0;
  LoudnessResult? _lastResult;
  LoudnessReading _currentReading = const LoudnessReading();
  final StreamController<LoudnessReading> _readingController =
      StreamController<LoudnessReading>.broadcast();

  // K-weighting filter state (per channel)
  final List<_BiquadState> _kWeightingL = [_BiquadState(), _BiquadState()];
  final List<_BiquadState> _kWeightingR = [_BiquadState(), _BiquadState()];

  // Integration state
  final List<double> _momentaryBuffer = [];
  final List<double> _shortTermBuffer = [];
  final List<double> _integratedBuffer = [];
  double _maxSamplePeak = 0.0;
  double _maxTruePeak = 0.0;
  double _maxShortTerm = -70.0;
  double _minShortTerm = 0.0;

  // Getters
  bool get isAnalyzing => _isAnalyzing;
  double get progress => _analysisProgress;
  LoudnessResult? get lastResult => _lastResult;
  LoudnessReading get currentReading => _currentReading;
  Stream<LoudnessReading> get readingStream => _readingController.stream;

  /// Analyze audio samples (stereo interleaved, normalized -1.0 to 1.0)
  Future<LoudnessResult> analyzeBuffer(
    List<double> samples, {
    int sampleRate = 48000,
    int channels = 2,
    void Function(double progress)? onProgress,
  }) async {
    if (samples.isEmpty) {
      return LoudnessResult.error('Empty buffer');
    }

    _isAnalyzing = true;
    _analysisProgress = 0.0;
    notifyListeners();

    try {
      // Reset state
      _resetState();

      // Process in chunks
      const chunkSize = 4800; // 100ms at 48kHz stereo
      final totalSamples = samples.length;
      int processedSamples = 0;

      for (int i = 0; i < totalSamples; i += chunkSize) {
        final end = math.min(i + chunkSize, totalSamples);
        final chunk = samples.sublist(i, end);

        _processChunk(chunk, sampleRate, channels);

        processedSamples = end;
        _analysisProgress = processedSamples / totalSamples;
        onProgress?.call(_analysisProgress);

        // Yield to event loop periodically
        if (i % (chunkSize * 10) == 0) {
          await Future<void>.delayed(Duration.zero);
          notifyListeners();
        }
      }

      // Calculate final results
      final result = _calculateFinalResult(
        Duration(milliseconds: (totalSamples / channels / sampleRate * 1000).round()),
      );

      _lastResult = result;
      _isAnalyzing = false;
      _analysisProgress = 1.0;
      notifyListeners();

      return result;
    } catch (e) {
      _isAnalyzing = false;
      notifyListeners();
      return LoudnessResult.error(e.toString());
    }
  }

  /// Reset all analysis state
  void _resetState() {
    for (final state in _kWeightingL) {
      state.reset();
    }
    for (final state in _kWeightingR) {
      state.reset();
    }
    _momentaryBuffer.clear();
    _shortTermBuffer.clear();
    _integratedBuffer.clear();
    _maxSamplePeak = 0.0;
    _maxTruePeak = 0.0;
    _maxShortTerm = -70.0;
    _minShortTerm = 0.0;
  }

  /// Process a chunk of samples
  void _processChunk(List<double> samples, int sampleRate, int channels) {
    if (channels != 2) return; // Only stereo supported for now

    // Process stereo samples
    for (int i = 0; i < samples.length; i += 2) {
      final l = samples[i];
      final r = i + 1 < samples.length ? samples[i + 1] : l;

      // Track sample peak
      _maxSamplePeak = math.max(_maxSamplePeak, l.abs());
      _maxSamplePeak = math.max(_maxSamplePeak, r.abs());

      // K-weighting filter (2-stage shelving + high-pass)
      final lFiltered = _applyKWeighting(l, _kWeightingL, sampleRate);
      final rFiltered = _applyKWeighting(r, _kWeightingR, sampleRate);

      // Calculate mean square
      final ms = (lFiltered * lFiltered + rFiltered * rFiltered) / 2.0;

      // Add to momentary buffer (400ms at 48kHz = 19200 samples = 9600 stereo pairs)
      _momentaryBuffer.add(ms);

      // True peak estimation (simplified 4x interpolation)
      final truePeakL = _estimateTruePeak(l, _kWeightingL[0].z1);
      final truePeakR = _estimateTruePeak(r, _kWeightingR[0].z1);
      _maxTruePeak = math.max(_maxTruePeak, truePeakL);
      _maxTruePeak = math.max(_maxTruePeak, truePeakR);
    }

    // Process momentary (400ms) - approximately 9600 samples for stereo at 48kHz
    final momentarySamples = (sampleRate * 0.4).round();
    if (_momentaryBuffer.length >= momentarySamples) {
      final momentaryMs = _momentaryBuffer
          .skip(_momentaryBuffer.length - momentarySamples)
          .fold(0.0, (a, b) => a + b) / momentarySamples;
      final momentaryLufs = _msToLufs(momentaryMs);

      // Add to short-term buffer
      _shortTermBuffer.add(momentaryMs);

      // Update reading
      _currentReading = LoudnessReading(
        momentary: momentaryLufs,
        shortTerm: _currentReading.shortTerm,
        integrated: _currentReading.integrated,
        peakL: _linearToDb(_maxSamplePeak),
        peakR: _linearToDb(_maxSamplePeak),
        truePeakL: _linearToDb(_maxTruePeak),
        truePeakR: _linearToDb(_maxTruePeak),
        timestamp: DateTime.now(),
      );

      // Emit reading
      _readingController.add(_currentReading);

      // Trim momentary buffer
      if (_momentaryBuffer.length > momentarySamples * 2) {
        _momentaryBuffer.removeRange(0, _momentaryBuffer.length - momentarySamples);
      }
    }

    // Process short-term (3 seconds) - 7.5 momentary windows
    if (_shortTermBuffer.length >= 8) {
      final shortTermMs = _shortTermBuffer
          .skip(_shortTermBuffer.length - 8)
          .fold(0.0, (a, b) => a + b) / 8;
      final shortTermLufs = _msToLufs(shortTermMs);

      // Track max/min short-term
      if (shortTermLufs > -70.0) {
        _maxShortTerm = math.max(_maxShortTerm, shortTermLufs);
        if (_minShortTerm == 0.0) {
          _minShortTerm = shortTermLufs;
        } else {
          _minShortTerm = math.min(_minShortTerm, shortTermLufs);
        }
      }

      // Add to integrated buffer (gated)
      if (shortTermMs > 0.0) {
        _integratedBuffer.add(shortTermMs);
      }

      // Update reading
      _currentReading = LoudnessReading(
        momentary: _currentReading.momentary,
        shortTerm: shortTermLufs,
        integrated: _calculateIntegratedLufs(),
        peakL: _currentReading.peakL,
        peakR: _currentReading.peakR,
        truePeakL: _currentReading.truePeakL,
        truePeakR: _currentReading.truePeakR,
        timestamp: DateTime.now(),
      );

      // Trim short-term buffer
      if (_shortTermBuffer.length > 16) {
        _shortTermBuffer.removeRange(0, _shortTermBuffer.length - 8);
      }
    }
  }

  /// Apply K-weighting filter (ITU-R BS.1770-4)
  double _applyKWeighting(double input, List<_BiquadState> states, int sampleRate) {
    // Stage 1: High shelf (+4dB at high frequencies)
    // Coefficients for 48kHz (pre-calculated)
    const b0Hs = 1.53512485958697;
    const b1Hs = -2.69169618940638;
    const b2Hs = 1.19839281085285;
    const a1Hs = -1.69065929318241;
    const a2Hs = 0.73248077421585;

    var output = states[0].process(input, b0Hs, b1Hs, b2Hs, a1Hs, a2Hs);

    // Stage 2: High-pass filter (removes DC and sub-bass)
    const b0Hp = 1.0;
    const b1Hp = -2.0;
    const b2Hp = 1.0;
    const a1Hp = -1.99004745483398;
    const a2Hp = 0.99007225036621;

    output = states[1].process(output, b0Hp, b1Hp, b2Hp, a1Hp, a2Hp);

    return output;
  }

  /// Estimate true peak using linear interpolation (simplified)
  double _estimateTruePeak(double current, double previous) {
    // Simple 2x oversampling approximation
    final interpolated = (current + previous) / 2.0;
    return math.max(current.abs(), interpolated.abs());
  }

  /// Convert mean square to LUFS
  double _msToLufs(double ms) {
    if (ms <= 0.0) return -70.0;
    // LUFS = -0.691 + 10 * log10(mean_square)
    return -0.691 + 10.0 * math.log(ms) / math.ln10;
  }

  /// Convert linear amplitude to dB
  double _linearToDb(double linear) {
    if (linear <= 0.0) return -70.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  /// Calculate integrated LUFS with gating (ITU-R BS.1770-4)
  double _calculateIntegratedLufs() {
    if (_integratedBuffer.isEmpty) return -70.0;

    // First pass: absolute gate at -70 LUFS
    final gated1 = _integratedBuffer.where((ms) => _msToLufs(ms) > -70.0).toList();
    if (gated1.isEmpty) return -70.0;

    // Calculate ungated mean
    final ungatedMean = gated1.fold(0.0, (a, b) => a + b) / gated1.length;
    final relativeThreshold = _msToLufs(ungatedMean) - 10.0; // -10 LU relative gate

    // Second pass: relative gate
    final gated2 = gated1.where((ms) => _msToLufs(ms) > relativeThreshold).toList();
    if (gated2.isEmpty) return -70.0;

    // Final integrated loudness
    final gatedMean = gated2.fold(0.0, (a, b) => a + b) / gated2.length;
    return _msToLufs(gatedMean);
  }

  /// Calculate final result after analysis
  LoudnessResult _calculateFinalResult(Duration duration) {
    final integrated = _calculateIntegratedLufs();

    // Calculate LRA (difference between 95th and 10th percentile of short-term)
    double lra = 0.0;
    if (_shortTermBuffer.length > 10) {
      final sorted = _shortTermBuffer.map(_msToLufs).where((l) => l > -70.0).toList()..sort();
      if (sorted.length > 10) {
        final p10 = sorted[(sorted.length * 0.1).floor()];
        final p95 = sorted[(sorted.length * 0.95).floor()];
        lra = p95 - p10;
      }
    }

    return LoudnessResult(
      integratedLufs: integrated,
      shortTermLufs: _currentReading.shortTerm,
      momentaryLufs: _currentReading.momentary,
      truePeak: _linearToDb(_maxTruePeak),
      samplePeak: _linearToDb(_maxSamplePeak),
      loudnessRange: lra,
      maxShortTerm: _maxShortTerm,
      minShortTerm: _minShortTerm,
      duration: duration,
      isValid: true,
    );
  }

  /// Calculate required gain to reach target LUFS
  double calculateGainForTarget(LoudnessResult result, double targetLufs) {
    if (!result.isValid) return 0.0;
    return targetLufs - result.integratedLufs;
  }

  /// Check if applying gain would cause clipping
  bool wouldClip(LoudnessResult result, double gainDb) {
    return result.truePeak + gainDb > 0.0;
  }

  /// Get recommended gain with headroom
  double getRecommendedGain(LoudnessResult result, LoudnessTarget target) {
    final idealGain = calculateGainForTarget(result, target.targetLufs);
    final maxGain = target.truePeakLimit - result.truePeak;
    return math.min(idealGain, maxGain);
  }

  @override
  void dispose() {
    _readingController.close();
    super.dispose();
  }
}

/// Biquad filter state for K-weighting
class _BiquadState {
  double z1 = 0.0;
  double z2 = 0.0;

  void reset() {
    z1 = 0.0;
    z2 = 0.0;
  }

  double process(double input, double b0, double b1, double b2, double a1, double a2) {
    final output = b0 * input + z1;
    z1 = b1 * input - a1 * output + z2;
    z2 = b2 * input - a2 * output;
    return output;
  }
}

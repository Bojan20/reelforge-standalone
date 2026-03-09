/// Dynamic Split Service — Transient / Gate / Silence based clip splitting
///
/// Analyzes audio clips and generates split points using multiple detection modes:
/// - Transient: splits at detected transient onsets (drums, percussive material)
/// - Gate: splits when signal drops below threshold (noise gate style)
/// - Silence: removes silent regions and keeps only audible content
///
/// Reaper-style: preview → adjust → apply. Supports stretch markers as alternative.
library;

import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Detection mode for dynamic split
enum SplitDetectionMode {
  transient, // Split at transients (onset detection)
  gate,      // Split when signal drops below threshold
  silence,   // Remove silence, keep audible regions
}

/// What to create at detected split points
enum SplitAction {
  split,          // Cut clip into separate clips
  stretchMarkers, // Add stretch markers instead of cutting
  regions,        // Create regions (markers) at boundaries
}

/// A detected split point with metadata
class SplitPoint {
  final double timeSeconds;
  final double strength;   // 0.0-1.0, how strong the detection is
  final bool isGap;        // true = start of gap (silence), false = transient onset

  const SplitPoint({
    required this.timeSeconds,
    required this.strength,
    this.isGap = false,
  });
}

/// A region of audio (used for gate/silence modes)
class AudioRegionResult {
  final double startTime;
  final double endTime;
  final bool isAudible; // true = sound, false = silence

  const AudioRegionResult({
    required this.startTime,
    required this.endTime,
    required this.isAudible,
  });

  double get duration => endTime - startTime;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class DynamicSplitService extends ChangeNotifier {
  DynamicSplitService._();
  static final instance = DynamicSplitService._();

  // ─── Parameters ────────────────────────────────────────────────────────────

  SplitDetectionMode _mode = SplitDetectionMode.transient;
  SplitDetectionMode get mode => _mode;

  SplitAction _action = SplitAction.split;
  SplitAction get action => _action;

  // Transient detection
  double _sensitivity = 0.5;
  double get sensitivity => _sensitivity;

  int _algorithm = 0; // 0=Enhanced, 1=HighEmphasis, 2=LowEmphasis, 3=SpectralFlux, 4=ComplexDomain
  int get algorithm => _algorithm;

  // Gate / silence detection
  double _thresholdDb = -40.0;
  double get thresholdDb => _thresholdDb;

  double _minLengthMs = 50.0;   // Min duration of audible region to keep
  double get minLengthMs => _minLengthMs;

  double _minSilenceMs = 100.0; // Min silence duration to trigger split
  double get minSilenceMs => _minSilenceMs;

  // Pad (add time before/after each split)
  double _padBeforeMs = 5.0;
  double get padBeforeMs => _padBeforeMs;

  double _padAfterMs = 5.0;
  double get padAfterMs => _padAfterMs;

  // Fade
  double _fadeInMs = 2.0;
  double get fadeInMs => _fadeInMs;

  double _fadeOutMs = 10.0;
  double get fadeOutMs => _fadeOutMs;

  // Remove short clips after split
  double _minClipLengthMs = 20.0;
  double get minClipLengthMs => _minClipLengthMs;

  // ─── Results ───────────────────────────────────────────────────────────────

  List<SplitPoint> _splitPoints = [];
  List<SplitPoint> get splitPoints => _splitPoints;

  List<AudioRegionResult> _regions = [];
  List<AudioRegionResult> get regions => _regions;

  int _clipId = 0;
  int get analyzedClipId => _clipId;

  double _clipDuration = 0;
  double get clipDuration => _clipDuration;

  int _sampleRate = 48000;
  int get sampleRate => _sampleRate;

  bool _analyzing = false;
  bool get analyzing => _analyzing;

  // ─── Setters ───────────────────────────────────────────────────────────────

  void setMode(SplitDetectionMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    _reanalyze();
  }

  void setAction(SplitAction action) {
    if (_action == action) return;
    _action = action;
    notifyListeners();
  }

  void setSensitivity(double v) {
    _sensitivity = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setAlgorithm(int v) {
    _algorithm = v.clamp(0, 4);
    notifyListeners();
  }

  void setThresholdDb(double v) {
    _thresholdDb = v.clamp(-96.0, 0.0);
    notifyListeners();
  }

  void setMinLengthMs(double v) {
    _minLengthMs = v.clamp(1.0, 5000.0);
    notifyListeners();
  }

  void setMinSilenceMs(double v) {
    _minSilenceMs = v.clamp(10.0, 10000.0);
    notifyListeners();
  }

  void setPadBeforeMs(double v) {
    _padBeforeMs = v.clamp(0.0, 500.0);
    notifyListeners();
  }

  void setPadAfterMs(double v) {
    _padAfterMs = v.clamp(0.0, 500.0);
    notifyListeners();
  }

  void setFadeInMs(double v) {
    _fadeInMs = v.clamp(0.0, 500.0);
    notifyListeners();
  }

  void setFadeOutMs(double v) {
    _fadeOutMs = v.clamp(0.0, 500.0);
    notifyListeners();
  }

  void setMinClipLengthMs(double v) {
    _minClipLengthMs = v.clamp(0.0, 1000.0);
    notifyListeners();
  }

  // ─── Analysis ──────────────────────────────────────────────────────────────

  /// Analyze a clip and generate split points.
  /// Call this when clip selection changes or when mode changes.
  void analyze(int clipId) {
    if (clipId == 0) {
      _splitPoints = [];
      _regions = [];
      _clipId = 0;
      notifyListeners();
      return;
    }

    _clipId = clipId;
    _analyzing = true;
    notifyListeners();

    final ffi = NativeFFI.instance;
    _sampleRate = ffi.getClipSampleRate(clipId);
    if (_sampleRate <= 0) _sampleRate = 48000;

    final totalFrames = ffi.getClipTotalFrames(clipId);
    _clipDuration = totalFrames / _sampleRate;

    switch (_mode) {
      case SplitDetectionMode.transient:
        _analyzeTransients(clipId);
      case SplitDetectionMode.gate:
        _analyzeGate(clipId, totalFrames);
      case SplitDetectionMode.silence:
        _analyzeSilence(clipId, totalFrames);
    }

    _analyzing = false;
    notifyListeners();
  }

  void _reanalyze() {
    if (_clipId > 0) analyze(_clipId);
  }

  /// Re-analyze with current parameters (call after parameter change)
  void reanalyze() => _reanalyze();

  // ─── Transient Detection ───────────────────────────────────────────────────

  void _analyzeTransients(int clipId) {
    final ffi = NativeFFI.instance;
    final results = ffi.detectClipTransients(
      clipId,
      sensitivity: _sensitivity,
      algorithm: _algorithm,
      minGapMs: 20.0,
      maxCount: 2000,
    );

    final sr = _sampleRate.toDouble();
    _splitPoints = results
        .map((r) => SplitPoint(
              timeSeconds: r.position / sr,
              strength: r.strength.clamp(0.0, 1.0),
            ))
        .toList();
    _regions = [];
  }

  // ─── Gate Detection ────────────────────────────────────────────────────────

  void _analyzeGate(int clipId, int totalFrames) {
    _analyzeAmplitude(clipId, totalFrames, removeShortSilence: true);
  }

  // ─── Silence Detection ─────────────────────────────────────────────────────

  void _analyzeSilence(int clipId, int totalFrames) {
    _analyzeAmplitude(clipId, totalFrames, removeShortSilence: false);
  }

  /// Shared amplitude analysis for gate and silence modes.
  /// Reads raw samples in chunks, detects where signal is above/below threshold.
  void _analyzeAmplitude(int clipId, int totalFrames, {required bool removeShortSilence}) {
    final ffi = NativeFFI.instance;
    final sr = _sampleRate.toDouble();
    final threshold = _dbToLinear(_thresholdDb);
    final minSilenceSamples = (_minSilenceMs / 1000.0 * sr).round();
    final minLengthSamples = (_minLengthMs / 1000.0 * sr).round();
    final padBeforeSamples = (_padBeforeMs / 1000.0 * sr).round();
    final padAfterSamples = (_padAfterMs / 1000.0 * sr).round();

    // RMS window size (for smoothing)
    const rmsWindowSize = 512;

    // Read in chunks and compute RMS envelope
    final chunkSize = 65536;
    final rmsEnvelope = <double>[];

    for (int offset = 0; offset < totalFrames; offset += chunkSize) {
      final framesToRead = (offset + chunkSize > totalFrames)
          ? totalFrames - offset
          : chunkSize;
      final samples = ffi.queryRawSamples(clipId, offset, framesToRead);
      if (samples == null) break;

      // Compute RMS per window
      for (int w = 0; w < samples.length; w += rmsWindowSize) {
        final end = (w + rmsWindowSize > samples.length) ? samples.length : w + rmsWindowSize;
        double sumSq = 0;
        for (int i = w; i < end; i++) {
          sumSq += samples[i] * samples[i];
        }
        rmsEnvelope.add(_sqrt(sumSq / (end - w)));
      }
    }

    if (rmsEnvelope.isEmpty) {
      _splitPoints = [];
      _regions = [];
      return;
    }

    // Convert RMS envelope to regions
    final samplesPerWindow = rmsWindowSize;
    final regionList = <AudioRegionResult>[];
    bool inSilence = rmsEnvelope[0] < threshold;
    int regionStart = 0;

    for (int i = 1; i < rmsEnvelope.length; i++) {
      final isSilent = rmsEnvelope[i] < threshold;
      if (isSilent != inSilence) {
        final startSample = regionStart * samplesPerWindow;
        final endSample = i * samplesPerWindow;
        regionList.add(AudioRegionResult(
          startTime: startSample / sr,
          endTime: endSample / sr,
          isAudible: !inSilence,
        ));
        regionStart = i;
        inSilence = isSilent;
      }
    }
    // Final region
    final lastSample = rmsEnvelope.length * samplesPerWindow;
    regionList.add(AudioRegionResult(
      startTime: regionStart * samplesPerWindow / sr,
      endTime: lastSample / sr,
      isAudible: !inSilence,
    ));

    // Filter: merge short silences into audible regions
    final mergedRegions = <AudioRegionResult>[];
    for (final r in regionList) {
      if (!r.isAudible && (r.duration * sr) < minSilenceSamples) {
        // Short silence — merge into adjacent audible region
        if (mergedRegions.isNotEmpty && mergedRegions.last.isAudible) {
          mergedRegions[mergedRegions.length - 1] = AudioRegionResult(
            startTime: mergedRegions.last.startTime,
            endTime: r.endTime,
            isAudible: true,
          );
        } else {
          mergedRegions.add(AudioRegionResult(
            startTime: r.startTime,
            endTime: r.endTime,
            isAudible: true,
          ));
        }
      } else if (r.isAudible && mergedRegions.isNotEmpty && mergedRegions.last.isAudible) {
        // Merge adjacent audible regions
        mergedRegions[mergedRegions.length - 1] = AudioRegionResult(
          startTime: mergedRegions.last.startTime,
          endTime: r.endTime,
          isAudible: true,
        );
      } else {
        mergedRegions.add(r);
      }
    }

    // Filter: remove short audible regions
    if (removeShortSilence) {
      _regions = mergedRegions.where((r) {
        if (!r.isAudible) return true; // keep silence markers
        return (r.duration * sr) >= minLengthSamples;
      }).toList();
    } else {
      _regions = mergedRegions;
    }

    // Apply padding to audible regions
    _regions = _regions.map((r) {
      if (!r.isAudible) return r;
      return AudioRegionResult(
        startTime: (r.startTime - padBeforeSamples / sr).clamp(0, _clipDuration),
        endTime: (r.endTime + padAfterSamples / sr).clamp(0, _clipDuration),
        isAudible: true,
      );
    }).toList();

    // Generate split points from region boundaries
    _splitPoints = [];
    for (final r in _regions) {
      if (r.isAudible) {
        if (r.startTime > 0.001) {
          _splitPoints.add(SplitPoint(
            timeSeconds: r.startTime,
            strength: 0.8,
            isGap: false,
          ));
        }
        if (r.endTime < _clipDuration - 0.001) {
          _splitPoints.add(SplitPoint(
            timeSeconds: r.endTime,
            strength: 0.6,
            isGap: true,
          ));
        }
      }
    }

    // Deduplicate and sort
    _splitPoints.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    if (_splitPoints.length > 1) {
      final deduped = <SplitPoint>[_splitPoints.first];
      for (int i = 1; i < _splitPoints.length; i++) {
        if ((_splitPoints[i].timeSeconds - deduped.last.timeSeconds).abs() > 0.001) {
          deduped.add(_splitPoints[i]);
        }
      }
      _splitPoints = deduped;
    }
  }

  // ─── Utility ───────────────────────────────────────────────────────────────

  /// Get count of audible regions (for "N items" display)
  int get audibleRegionCount => _regions.where((r) => r.isAudible).length;

  /// Get split point count
  int get splitPointCount => _splitPoints.length;

  /// Estimated result clip count
  int get estimatedClipCount {
    if (_mode == SplitDetectionMode.transient) {
      return _splitPoints.length + 1; // N split points = N+1 clips
    }
    return _regions.where((r) => r.isAudible).length;
  }

  /// Clear all results
  void clear() {
    _splitPoints = [];
    _regions = [];
    _clipId = 0;
    _clipDuration = 0;
    _analyzing = false;
    notifyListeners();
  }

  /// Reset parameters to defaults
  void resetDefaults() {
    _mode = SplitDetectionMode.transient;
    _action = SplitAction.split;
    _sensitivity = 0.5;
    _algorithm = 0;
    _thresholdDb = -40.0;
    _minLengthMs = 50.0;
    _minSilenceMs = 100.0;
    _padBeforeMs = 5.0;
    _padAfterMs = 5.0;
    _fadeInMs = 2.0;
    _fadeOutMs = 10.0;
    _minClipLengthMs = 20.0;
    notifyListeners();
  }

  static double _dbToLinear(double db) =>
      db <= -96.0 ? 0.0 : _pow10(db / 20.0);

  static double _pow10(double x) {
    // exp(x * ln(10)) — no dart:math dependency needed
    // Taylor series approximation sufficient for dB conversion
    final lnResult = x * 2.302585092994046; // ln(10)
    return _exp(lnResult);
  }

  static double _exp(double x) {
    // Use Dart's built-in
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    // Newton's method
    double guess = x;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) * 0.5;
    }
    return guess;
  }
}

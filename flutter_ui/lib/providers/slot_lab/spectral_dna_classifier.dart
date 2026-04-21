/// Spectral DNA Audio Classifier — Level 2 Auto-bind
///
/// Analyzes audio files by spectral content (not filename) to automatically
/// classify them into slot stage events. Uses Rust FFI for real DSP analysis.
///
/// 3-tier classification:
///   Level 1: FFNC naming convention (deterministic, 100%)
///   Level 2: Spectral DNA (this) — DSP analysis with confidence scores
///   Level 3: AI Tagging (future)

import 'dart:convert';
import 'dart:developer' as dev;
import '../../src/rust/native_ffi.dart';

/// Result of spectral DNA analysis for a single audio file.
class SpectralDnaResult {
  final String filePath;
  final double durationMs;
  final double attackMs;
  final double rmsEnergy;
  final double peakAmplitude;
  final double spectralCentroidHz;
  final bool isLoopable;
  final int transientCount;
  final bool hasSustain;
  final double brightness;
  final List<StageCandidate> candidates;

  SpectralDnaResult({
    required this.filePath,
    required this.durationMs,
    required this.attackMs,
    required this.rmsEnergy,
    required this.peakAmplitude,
    required this.spectralCentroidHz,
    required this.isLoopable,
    required this.transientCount,
    required this.hasSustain,
    required this.brightness,
    required this.candidates,
  });

  /// Parse from JSON returned by Rust FFI.
  factory SpectralDnaResult.fromJson(String filePath, Map<String, dynamic> json) {
    final candidatesList = (json['candidates'] as List<dynamic>?)
        ?.map((c) => StageCandidate(
              stage: c['stage'] as String? ?? '',
              confidence: (c['confidence'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList() ?? [];

    // Sort by confidence descending
    candidatesList.sort((a, b) => b.confidence.compareTo(a.confidence));

    return SpectralDnaResult(
      filePath: filePath,
      durationMs: (json['duration_ms'] as num?)?.toDouble() ?? 0.0,
      attackMs: (json['attack_ms'] as num?)?.toDouble() ?? 0.0,
      rmsEnergy: (json['rms_energy'] as num?)?.toDouble() ?? 0.0,
      peakAmplitude: (json['peak_amplitude'] as num?)?.toDouble() ?? 0.0,
      spectralCentroidHz: (json['spectral_centroid_hz'] as num?)?.toDouble() ?? 0.0,
      isLoopable: json['is_loopable'] as bool? ?? false,
      transientCount: json['transient_count'] as int? ?? 0,
      hasSustain: json['has_sustain'] as bool? ?? false,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      candidates: candidatesList,
    );
  }

  /// The best candidate stage (highest confidence).
  StageCandidate? get bestCandidate =>
      candidates.isNotEmpty ? candidates.first : null;

  /// Whether the confidence is high enough to auto-assign without user confirmation.
  bool get isHighConfidence =>
      bestCandidate != null && bestCandidate!.confidence >= 0.75;

  /// Whether the confidence is medium — suggest but ask user.
  bool get isMediumConfidence =>
      bestCandidate != null &&
      bestCandidate!.confidence >= 0.50 &&
      bestCandidate!.confidence < 0.75;

  /// Human-readable classification summary.
  String get summary {
    if (candidates.isEmpty) return 'Unclassified';
    final best = bestCandidate!;
    final confPercent = (best.confidence * 100).toStringAsFixed(0);
    return '${best.stage} ($confPercent%)';
  }

  /// Duration category for UI display.
  String get durationCategory {
    if (durationMs < 100) return 'Ultra Short';
    if (durationMs < 300) return 'Short Hit';
    if (durationMs < 1500) return 'Medium';
    if (durationMs < 5000) return 'Long';
    return 'Music/Loop';
  }
}

/// A candidate stage assignment with confidence score.
class StageCandidate {
  final String stage;
  final double confidence;

  StageCandidate({required this.stage, required this.confidence});

  @override
  String toString() => '$stage (${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Service that wraps Rust FFI for spectral DNA analysis.
///
/// Usage:
/// ```dart
/// final classifier = SpectralDnaClassifier(nativeFFI);
/// final result = classifier.analyzeFile('/path/to/audio.wav');
/// if (result != null && result.isHighConfidence) {
///   // Auto-assign to result.bestCandidate!.stage
/// }
/// ```
class SpectralDnaClassifier {
  final NativeFFI _ffi;

  SpectralDnaClassifier(this._ffi);

  /// Analyze a single audio file.
  SpectralDnaResult? analyzeFile(String path) {
    try {
      final jsonStr = _ffi.spectralDnaAnalyze(path);
      if (jsonStr == null || jsonStr == '{}') return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (json.isEmpty || !json.containsKey('duration_ms')) return null;

      return SpectralDnaResult.fromJson(path, json);
    } catch (e) {
      dev.log('SpectralDNA analyzeFile error: $e', name: 'SpectralDNA');
      return null;
    }
  }

  /// Batch analyze multiple audio files.
  /// Returns map of filePath → SpectralDnaResult.
  Map<String, SpectralDnaResult> analyzeBatch(List<String> paths) {
    final results = <String, SpectralDnaResult>{};
    if (paths.isEmpty) return results;

    try {
      final jsonStr = _ffi.spectralDnaAnalyzeBatch(paths);
      if (jsonStr == null || jsonStr == '[]') return results;

      final jsonArray = jsonDecode(jsonStr) as List<dynamic>;

      for (int i = 0; i < jsonArray.length && i < paths.length; i++) {
        final item = jsonArray[i];
        if (item == null || item is! Map<String, dynamic>) continue;
        if (item.isEmpty || !item.containsKey('duration_ms')) continue;

        results[paths[i]] = SpectralDnaResult.fromJson(paths[i], item);
      }
    } catch (e) {
      dev.log('SpectralDNA analyzeBatch error: $e', name: 'SpectralDNA');
    }

    return results;
  }

  /// Classify and suggest auto-bind assignments for unmatched files.
  ///
  /// Takes files that FFNC (Level 1) failed to match and returns
  /// suggested stage assignments with confidence scores.
  ///
  /// [usedStages] — stages already assigned by Level 1, to avoid duplicates.
  Map<String, StageCandidate> suggestBindings(
    List<String> unmatchedPaths, {
    Set<String> usedStages = const {},
    double minConfidence = 0.40,
  }) {
    final suggestions = <String, StageCandidate>{};
    if (unmatchedPaths.isEmpty) return suggestions;

    final results = analyzeBatch(unmatchedPaths);

    for (final entry in results.entries) {
      final result = entry.value;
      if (result.candidates.isEmpty) continue;

      // Find best candidate that isn't already used
      for (final candidate in result.candidates) {
        if (candidate.confidence < minConfidence) break; // Already sorted desc
        if (!usedStages.contains(candidate.stage)) {
          suggestions[entry.key] = candidate;
          break;
        }
      }
    }

    return suggestions;
  }
}

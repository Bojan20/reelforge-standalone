// Audio Region Model — Timeline Audio Clip
//
// Represents a single audio clip on the timeline with waveform,
// non-destructive editing (trim, fade), and visual properties.

import 'package:flutter/material.dart';

/// Fade curve types
enum FadeCurve {
  linear,       // Straight line
  exponential,  // Fast start, slow end
  logarithmic,  // Slow start, fast end
  sCurve,       // S-shaped curve
  equalPower,   // Equal power crossfade (default)
}

/// Audio region on timeline
class AudioRegion {
  final String id;
  final String trackId;
  final String audioPath;

  // Timeline positioning
  final double startTime;       // Position on timeline (seconds)
  final double duration;        // Visible duration (seconds)

  // Non-destructive editing
  final double trimStart;       // Offset into audio file (seconds)
  final double trimEnd;         // Trim from end (seconds)

  // Fades
  final double fadeInMs;
  final double fadeOutMs;
  final FadeCurve fadeInCurve;
  final FadeCurve fadeOutCurve;

  // Mix parameters
  final double volume;          // 0.0-2.0 (0 = −∞ dB, 1.0 = 0dB, 2.0 = +6dB)
  final double pan;             // −1.0 to +1.0 (L to R)

  // Visual
  final Color regionColor;
  final bool isMuted;
  final bool isSelected;

  // Waveform cache
  final List<double>? waveformData; // Cached waveform from FFI

  const AudioRegion({
    required this.id,
    required this.trackId,
    required this.audioPath,
    required this.startTime,
    required this.duration,
    this.trimStart = 0.0,
    this.trimEnd = 0.0,
    this.fadeInMs = 0.0,
    this.fadeOutMs = 0.0,
    this.fadeInCurve = FadeCurve.equalPower,
    this.fadeOutCurve = FadeCurve.equalPower,
    this.volume = 1.0,
    this.pan = 0.0,
    this.regionColor = const Color(0xFF4A9EFF),
    this.isMuted = false,
    this.isSelected = false,
    this.waveformData,
  });

  /// Get end time on timeline
  double get endTime => startTime + duration;

  /// Get actual audio duration (accounting for trim)
  double get trimmedDuration => duration - trimStart - trimEnd;

  /// Check if time is within region bounds
  bool containsTime(double time) {
    return time >= startTime && time < endTime;
  }

  /// Get fade in gain at specific time (0.0-1.0)
  double getFadeInGain(double timeSeconds) {
    if (fadeInMs == 0) return 1.0;

    final fadeInSeconds = fadeInMs / 1000.0;
    final relativeTime = timeSeconds - startTime;

    if (relativeTime < 0) return 0.0;
    if (relativeTime >= fadeInSeconds) return 1.0;

    final t = relativeTime / fadeInSeconds;
    return _applyCurve(t, fadeInCurve);
  }

  /// Get fade out gain at specific time (0.0-1.0)
  double getFadeOutGain(double timeSeconds) {
    if (fadeOutMs == 0) return 1.0;

    final fadeOutSeconds = fadeOutMs / 1000.0;
    final relativeTime = endTime - timeSeconds;

    if (relativeTime < 0) return 0.0;
    if (relativeTime >= fadeOutSeconds) return 1.0;

    final t = relativeTime / fadeOutSeconds;
    return _applyCurve(t, fadeOutCurve);
  }

  /// Apply fade curve to normalized time (0-1)
  double _applyCurve(double t, FadeCurve curve) {
    switch (curve) {
      case FadeCurve.linear:
        return t;

      case FadeCurve.exponential:
        return t * t;

      case FadeCurve.logarithmic:
        return math.sqrt(t);

      case FadeCurve.sCurve:
        // Smoothstep formula
        return t * t * (3 - 2 * t);

      case FadeCurve.equalPower:
        // Equal power crossfade (−3dB at center)
        return math.sin(t * math.pi / 2);
    }
  }

  /// Convert volume (0-2) to dB
  double get volumeDb {
    if (volume <= 0.001) return double.negativeInfinity;
    return 20 * math.log(volume) / math.ln10;
  }

  /// Copy with modifications
  AudioRegion copyWith({
    String? id,
    String? trackId,
    String? audioPath,
    double? startTime,
    double? duration,
    double? trimStart,
    double? trimEnd,
    double? fadeInMs,
    double? fadeOutMs,
    FadeCurve? fadeInCurve,
    FadeCurve? fadeOutCurve,
    double? volume,
    double? pan,
    Color? regionColor,
    bool? isMuted,
    bool? isSelected,
    List<double>? waveformData,
  }) {
    return AudioRegion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      audioPath: audioPath ?? this.audioPath,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      fadeInCurve: fadeInCurve ?? this.fadeInCurve,
      fadeOutCurve: fadeOutCurve ?? this.fadeOutCurve,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      regionColor: regionColor ?? this.regionColor,
      isMuted: isMuted ?? this.isMuted,
      isSelected: isSelected ?? this.isSelected,
      waveformData: waveformData ?? this.waveformData,
    );
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'trackId': trackId,
    'audioPath': audioPath,
    'startTime': startTime,
    'duration': duration,
    'trimStart': trimStart,
    'trimEnd': trimEnd,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'fadeInCurve': fadeInCurve.name,
    'fadeOutCurve': fadeOutCurve.name,
    'volume': volume,
    'pan': pan,
    'regionColor': regionColor.value,
    'isMuted': isMuted,
    // Note: waveformData NOT serialized (regenerated on load)
  };

  factory AudioRegion.fromJson(Map<String, dynamic> json) {
    return AudioRegion(
      id: json['id'] as String,
      trackId: json['trackId'] as String,
      audioPath: json['audioPath'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
      trimStart: (json['trimStart'] as num?)?.toDouble() ?? 0.0,
      trimEnd: (json['trimEnd'] as num?)?.toDouble() ?? 0.0,
      fadeInMs: (json['fadeInMs'] as num?)?.toDouble() ?? 0.0,
      fadeOutMs: (json['fadeOutMs'] as num?)?.toDouble() ?? 0.0,
      fadeInCurve: FadeCurve.values.firstWhere(
        (c) => c.name == json['fadeInCurve'],
        orElse: () => FadeCurve.equalPower,
      ),
      fadeOutCurve: FadeCurve.values.firstWhere(
        (c) => c.name == json['fadeOutCurve'],
        orElse: () => FadeCurve.equalPower,
      ),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      regionColor: Color(json['regionColor'] as int? ?? 0xFF4A9EFF),
      isMuted: json['isMuted'] as bool? ?? false,
    );
  }
}

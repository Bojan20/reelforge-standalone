/// Timeline Models
///
/// Core data types for timeline/sequencer:
/// - TimelineClip
/// - TimelineTrack
/// - TimelineMarker
/// - Crossfade
/// - SnapConfig

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Clip on a timeline track
class TimelineClip {
  final String id;
  final String trackId;
  final String name;
  final double startTime; // in seconds
  final double duration;
  final Color? color;
  /// Pre-computed waveform peaks (0-1)
  final Float32List? waveform;
  /// Source offset within audio file (for left-edge trim)
  final double sourceOffset;
  /// Original source audio duration (immutable)
  final double? sourceDuration;
  /// Fade in duration in seconds
  final double fadeIn;
  /// Fade out duration in seconds
  final double fadeOut;
  /// Clip gain (0-2, 1 = unity)
  final double gain;
  /// Is muted
  final bool muted;
  /// Is selected
  final bool selected;

  const TimelineClip({
    required this.id,
    required this.trackId,
    required this.name,
    required this.startTime,
    required this.duration,
    this.color,
    this.waveform,
    this.sourceOffset = 0,
    this.sourceDuration,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.gain = 1,
    this.muted = false,
    this.selected = false,
  });

  double get endTime => startTime + duration;

  TimelineClip copyWith({
    String? id,
    String? trackId,
    String? name,
    double? startTime,
    double? duration,
    Color? color,
    Float32List? waveform,
    double? sourceOffset,
    double? sourceDuration,
    double? fadeIn,
    double? fadeOut,
    double? gain,
    bool? muted,
    bool? selected,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      color: color ?? this.color,
      waveform: waveform ?? this.waveform,
      sourceOffset: sourceOffset ?? this.sourceOffset,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      gain: gain ?? this.gain,
      muted: muted ?? this.muted,
      selected: selected ?? this.selected,
    );
  }
}

/// Bus routing options
enum OutputBus { master, music, sfx, ambience, voice }

/// Track on the timeline
class TimelineTrack {
  final String id;
  final String name;
  final Color color;
  final double height;
  final bool muted;
  final bool soloed;
  final bool armed;
  final bool locked;
  final OutputBus outputBus;
  final bool inputMonitor;
  final bool frozen;
  final double volume; // 0-1, 1 = unity
  final double pan; // -1 to 1, 0 = center

  const TimelineTrack({
    required this.id,
    required this.name,
    this.color = const Color(0xFF4A9EFF),
    this.height = 80,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.locked = false,
    this.outputBus = OutputBus.master,
    this.inputMonitor = false,
    this.frozen = false,
    this.volume = 1,
    this.pan = 0,
  });

  TimelineTrack copyWith({
    String? id,
    String? name,
    Color? color,
    double? height,
    bool? muted,
    bool? soloed,
    bool? armed,
    bool? locked,
    OutputBus? outputBus,
    bool? inputMonitor,
    bool? frozen,
    double? volume,
    double? pan,
  }) {
    return TimelineTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      height: height ?? this.height,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      armed: armed ?? this.armed,
      locked: locked ?? this.locked,
      outputBus: outputBus ?? this.outputBus,
      inputMonitor: inputMonitor ?? this.inputMonitor,
      frozen: frozen ?? this.frozen,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
    );
  }
}

/// Marker on the timeline
class TimelineMarker {
  final String id;
  final double time;
  final String name;
  final Color color;

  const TimelineMarker({
    required this.id,
    required this.time,
    required this.name,
    this.color = const Color(0xFFFF9040),
  });
}

/// Crossfade curve type
enum CrossfadeCurve { linear, equalPower, sCurve }

/// Crossfade between two clips
class Crossfade {
  final String id;
  final String trackId;
  final String clipAId;
  final String clipBId;
  final double startTime;
  final double duration;
  final CrossfadeCurve curveType;

  const Crossfade({
    required this.id,
    required this.trackId,
    required this.clipAId,
    required this.clipBId,
    required this.startTime,
    required this.duration,
    this.curveType = CrossfadeCurve.equalPower,
  });

  Crossfade copyWith({
    String? id,
    String? trackId,
    String? clipAId,
    String? clipBId,
    double? startTime,
    double? duration,
    CrossfadeCurve? curveType,
  }) {
    return Crossfade(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      clipAId: clipAId ?? this.clipAId,
      clipBId: clipBId ?? this.clipBId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      curveType: curveType ?? this.curveType,
    );
  }
}

/// Snap configuration
enum SnapType { grid, gridRelative, events, magneticCursor }

class SnapConfig {
  final bool enabled;
  /// Snap value in beats (0.25 = 16th, 0.5 = 8th, 1 = quarter, 4 = bar)
  final double value;
  final SnapType type;

  const SnapConfig({
    this.enabled = true,
    this.value = 1,
    this.type = SnapType.grid,
  });
}

/// Time display mode
enum TimeDisplayMode { bars, timecode, samples }

/// Loop region
class LoopRegion {
  final double start;
  final double end;

  const LoopRegion({required this.start, required this.end});

  double get duration => end - start;

  LoopRegion copyWith({double? start, double? end}) {
    return LoopRegion(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

// ============ Snap Utilities ============

/// Snap time to grid based on tempo and snap value.
double snapToGrid(double time, double snapValue, double tempo) {
  final beatsPerSecond = tempo / 60;
  final gridInterval = snapValue / beatsPerSecond;
  return (time / gridInterval).round() * gridInterval;
}

/// Snap time to nearest event boundary.
double snapToEvents(double time, List<TimelineClip> clips, {double threshold = 0.1}) {
  double nearestTime = time;
  double nearestDistance = threshold;

  for (final clip in clips) {
    // Check clip start
    final startDist = (clip.startTime - time).abs();
    if (startDist < nearestDistance) {
      nearestDistance = startDist;
      nearestTime = clip.startTime;
    }

    // Check clip end
    final endDist = (clip.endTime - time).abs();
    if (endDist < nearestDistance) {
      nearestDistance = endDist;
      nearestTime = clip.endTime;
    }
  }

  return nearestTime;
}

/// Apply snap based on configuration.
double applySnap(
  double time,
  bool snapEnabled,
  double snapValue,
  double tempo,
  List<TimelineClip> clips, {
  double eventSnapThreshold = 0.05,
}) {
  if (!snapEnabled) return time;

  // First, try event snap (higher priority)
  final eventSnapped = snapToEvents(time, clips, threshold: eventSnapThreshold);
  if (eventSnapped != time) {
    return eventSnapped;
  }

  // Fall back to grid snap
  return snapToGrid(time, snapValue, tempo);
}

// ============ Time Formatting ============

/// Format time as bars.beats
String formatBars(double seconds, double tempo, int timeSignatureNum) {
  final beatsPerSecond = tempo / 60;
  final totalBeats = seconds * beatsPerSecond;
  final bar = (totalBeats / timeSignatureNum).floor() + 1;
  final beat = (totalBeats % timeSignatureNum).floor() + 1;
  return '$bar.$beat';
}

/// Format time as timecode (MM:SS:FF)
String formatTimecode(double seconds, {int fps = 30}) {
  final mins = (seconds / 60).floor();
  final secs = (seconds % 60).floor();
  final frames = ((seconds % 1) * fps).floor();
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
}

/// Format time based on mode
String formatTime(
  double seconds,
  TimeDisplayMode mode, {
  double tempo = 120,
  int timeSignatureNum = 4,
  int sampleRate = 48000,
}) {
  switch (mode) {
    case TimeDisplayMode.bars:
      return formatBars(seconds, tempo, timeSignatureNum);
    case TimeDisplayMode.timecode:
      return formatTimecode(seconds);
    case TimeDisplayMode.samples:
      return (seconds * sampleRate).floor().toString();
  }
}

// ============ Demo Waveform Generator ============

/// Generate demo waveform data
Float32List generateDemoWaveform({int samples = 1000}) {
  final waveform = Float32List(samples);
  for (int i = 0; i < samples; i++) {
    final t = i / samples;
    final envelope = math.sin(t * 3.14159); // Fade in/out
    final noise = (_randomDouble() - 0.5) * 0.3;
    final sine = math.sin(t * 3.14159 * 8) * 0.5;
    final burst = (t > 0.2 && t < 0.4) ? _randomDouble() * 0.8 : 0;
    waveform[i] = (sine + noise + burst) * envelope;
  }
  return waveform;
}

double _randomDouble() {
  // Simple deterministic pseudo-random for demo
  return (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
}

// ============ Track Colors ============

const List<Color> kTrackColors = [
  Color(0xFF4A9EFF), // Blue
  Color(0xFFFF6B6B), // Red
  Color(0xFF51CF66), // Green
  Color(0xFFFFD43B), // Yellow
  Color(0xFF845EF7), // Purple
  Color(0xFFFF922B), // Orange
  Color(0xFF22B8CF), // Cyan
  Color(0xFFF06595), // Pink
  Color(0xFF94D82D), // Lime
  Color(0xFFBE4BDB), // Violet
  Color(0xFF339AF0), // Light Blue
  Color(0xFF20C997), // Teal
  Color(0xFFFAB005), // Gold
  Color(0xFF748FFC), // Indigo
  Color(0xFF69DB7C), // Light Green
];

/// Bus display info
class BusInfo {
  final OutputBus bus;
  final String name;
  final Color color;

  const BusInfo(this.bus, this.name, this.color);

  String get shortName => name.substring(0, 3);
}

const List<BusInfo> kBusOptions = [
  BusInfo(OutputBus.master, 'Master', Color(0xFF888888)),
  BusInfo(OutputBus.music, 'Music', Color(0xFF4A9EFF)),
  BusInfo(OutputBus.sfx, 'SFX', Color(0xFFFF6B6B)),
  BusInfo(OutputBus.voice, 'Voice', Color(0xFF51CF66)),
  BusInfo(OutputBus.ambience, 'Ambience', Color(0xFFFFD43B)),
];

BusInfo getBusInfo(OutputBus bus) {
  return kBusOptions.firstWhere((b) => b.bus == bus, orElse: () => kBusOptions[0]);
}

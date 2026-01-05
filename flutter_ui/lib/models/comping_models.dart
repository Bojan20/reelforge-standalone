/// Comping Models
///
/// Multi-take recording and comping system (Cubase/Pro Tools style):
/// - RecordingLane: Vertical lane within a track for take stacking
/// - Take: A single recording pass with metadata
/// - CompRegion: Selected region from a specific take for the comp
/// - CompState: Track-level comping configuration
///
/// Architecture:
/// Track → RecordingLanes[] → Takes[] → Clips
///                         ↓
///               CompRegions[] (selections for final comp)

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'timeline_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING LANE
// ═══════════════════════════════════════════════════════════════════════════

/// A recording lane within a track (Cubase: "Lane")
/// Each lane can contain multiple takes from different recordings
class RecordingLane {
  final String id;
  final String trackId;

  /// Display order (0 = topmost lane, usually the comp/active lane)
  final int index;

  /// Lane name (auto: "Take 1", "Take 2", or custom)
  final String name;

  /// Lane height in pixels (can be collapsed)
  final double height;

  /// Is this lane visible (false = collapsed)
  final bool visible;

  /// Is this the active lane for playback (only one active per track)
  final bool isActive;

  /// Is this the comp lane (special lane that plays the composite)
  final bool isCompLane;

  /// Muted (skip this lane in playback)
  final bool muted;

  /// Lane color (inherit from track or custom)
  final Color? color;

  /// Takes in this lane
  final List<Take> takes;

  const RecordingLane({
    required this.id,
    required this.trackId,
    required this.index,
    this.name = '',
    this.height = 60,
    this.visible = true,
    this.isActive = false,
    this.isCompLane = false,
    this.muted = false,
    this.color,
    this.takes = const [],
  });

  String get displayName => name.isEmpty ? 'Lane ${index + 1}' : name;

  RecordingLane copyWith({
    String? id,
    String? trackId,
    int? index,
    String? name,
    double? height,
    bool? visible,
    bool? isActive,
    bool? isCompLane,
    bool? muted,
    Color? color,
    List<Take>? takes,
  }) {
    return RecordingLane(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      index: index ?? this.index,
      name: name ?? this.name,
      height: height ?? this.height,
      visible: visible ?? this.visible,
      isActive: isActive ?? this.isActive,
      isCompLane: isCompLane ?? this.isCompLane,
      muted: muted ?? this.muted,
      color: color ?? this.color,
      takes: takes ?? this.takes,
    );
  }

  /// Add a take to this lane
  RecordingLane addTake(Take take) {
    return copyWith(takes: [...takes, take]);
  }

  /// Remove a take from this lane
  RecordingLane removeTake(String takeId) {
    return copyWith(takes: takes.where((t) => t.id != takeId).toList());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAKE
// ═══════════════════════════════════════════════════════════════════════════

/// Take rating (Pro Tools style)
enum TakeRating { none, bad, okay, good, best }

/// A single take (recording pass)
class Take {
  final String id;
  final String laneId;
  final String trackId;

  /// Take number (auto-incrementing per track)
  final int takeNumber;

  /// Custom name (optional)
  final String? name;

  /// Start time in seconds (timeline position)
  final double startTime;

  /// Duration in seconds
  final double duration;

  /// Source audio file path
  final String sourcePath;

  /// Source offset within audio file (for non-zero start)
  final double sourceOffset;

  /// Original source duration
  final double sourceDuration;

  /// Waveform peaks (for display)
  final Float32List? waveform;

  /// Take color (usually inherits from lane/track)
  final Color? color;

  /// Take rating
  final TakeRating rating;

  /// Recording timestamp
  final DateTime recordedAt;

  /// Is this take selected for the comp
  final bool inComp;

  /// Gain adjustment (0-2, 1 = unity)
  final double gain;

  /// Fade in duration
  final double fadeIn;

  /// Fade out duration
  final double fadeOut;

  /// Muted
  final bool muted;

  /// Locked (prevent edits)
  final bool locked;

  const Take({
    required this.id,
    required this.laneId,
    required this.trackId,
    required this.takeNumber,
    this.name,
    required this.startTime,
    required this.duration,
    required this.sourcePath,
    this.sourceOffset = 0,
    required this.sourceDuration,
    this.waveform,
    this.color,
    this.rating = TakeRating.none,
    required this.recordedAt,
    this.inComp = false,
    this.gain = 1.0,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.muted = false,
    this.locked = false,
  });

  double get endTime => startTime + duration;

  String get displayName => name ?? 'Take $takeNumber';

  /// Get rating icon
  IconData get ratingIcon {
    switch (rating) {
      case TakeRating.none:
        return Icons.star_border;
      case TakeRating.bad:
        return Icons.thumb_down;
      case TakeRating.okay:
        return Icons.thumbs_up_down;
      case TakeRating.good:
        return Icons.thumb_up;
      case TakeRating.best:
        return Icons.star;
    }
  }

  /// Get rating color
  Color get ratingColor {
    switch (rating) {
      case TakeRating.none:
        return Colors.grey;
      case TakeRating.bad:
        return Colors.red;
      case TakeRating.okay:
        return Colors.orange;
      case TakeRating.good:
        return Colors.lightGreen;
      case TakeRating.best:
        return Colors.yellow;
    }
  }

  Take copyWith({
    String? id,
    String? laneId,
    String? trackId,
    int? takeNumber,
    String? name,
    double? startTime,
    double? duration,
    String? sourcePath,
    double? sourceOffset,
    double? sourceDuration,
    Float32List? waveform,
    Color? color,
    TakeRating? rating,
    DateTime? recordedAt,
    bool? inComp,
    double? gain,
    double? fadeIn,
    double? fadeOut,
    bool? muted,
    bool? locked,
  }) {
    return Take(
      id: id ?? this.id,
      laneId: laneId ?? this.laneId,
      trackId: trackId ?? this.trackId,
      takeNumber: takeNumber ?? this.takeNumber,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceOffset: sourceOffset ?? this.sourceOffset,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      waveform: waveform ?? this.waveform,
      color: color ?? this.color,
      rating: rating ?? this.rating,
      recordedAt: recordedAt ?? this.recordedAt,
      inComp: inComp ?? this.inComp,
      gain: gain ?? this.gain,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      muted: muted ?? this.muted,
      locked: locked ?? this.locked,
    );
  }

  /// Convert to TimelineClip for rendering
  TimelineClip toClip() {
    return TimelineClip(
      id: id,
      trackId: trackId,
      name: displayName,
      startTime: startTime,
      duration: duration,
      color: color,
      waveform: waveform,
      sourceOffset: sourceOffset,
      sourceDuration: sourceDuration,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
      gain: gain,
      muted: muted,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMP REGION
// ═══════════════════════════════════════════════════════════════════════════

/// Crossfade type for comp region transitions
enum CompCrossfadeType { linear, equalPower, sCurve }

/// A selected region from a specific take for the final comp
class CompRegion {
  final String id;
  final String trackId;

  /// Which take this region comes from
  final String takeId;

  /// Start time in the comp (timeline position)
  final double startTime;

  /// End time in the comp
  final double endTime;

  /// Crossfade in duration (from previous region)
  final double crossfadeIn;

  /// Crossfade out duration (to next region)
  final double crossfadeOut;

  /// Crossfade type
  final CompCrossfadeType crossfadeType;

  const CompRegion({
    required this.id,
    required this.trackId,
    required this.takeId,
    required this.startTime,
    required this.endTime,
    this.crossfadeIn = 0.01, // 10ms default
    this.crossfadeOut = 0.01,
    this.crossfadeType = CompCrossfadeType.equalPower,
  });

  double get duration => endTime - startTime;

  CompRegion copyWith({
    String? id,
    String? trackId,
    String? takeId,
    double? startTime,
    double? endTime,
    double? crossfadeIn,
    double? crossfadeOut,
    CompCrossfadeType? crossfadeType,
  }) {
    return CompRegion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      takeId: takeId ?? this.takeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      crossfadeIn: crossfadeIn ?? this.crossfadeIn,
      crossfadeOut: crossfadeOut ?? this.crossfadeOut,
      crossfadeType: crossfadeType ?? this.crossfadeType,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMP STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Comping mode
enum CompMode {
  /// Single lane playback (one lane at a time)
  single,

  /// Comp mode (play from CompRegions)
  comp,

  /// Audition all lanes stacked (for comparison)
  auditAll,
}

/// Track-level comping state
class CompState {
  final String trackId;

  /// Current comping mode
  final CompMode mode;

  /// Is lane view expanded (show all lanes vs just active)
  final bool lanesExpanded;

  /// Recording lanes
  final List<RecordingLane> lanes;

  /// Comp regions (for CompMode.comp)
  final List<CompRegion> compRegions;

  /// Current active lane index (for single mode)
  final int activeLaneIndex;

  /// Next take number (auto-increment)
  final int nextTakeNumber;

  /// Is currently recording
  final bool isRecording;

  /// Recording start time
  final double? recordingStartTime;

  const CompState({
    required this.trackId,
    this.mode = CompMode.single,
    this.lanesExpanded = false,
    this.lanes = const [],
    this.compRegions = const [],
    this.activeLaneIndex = 0,
    this.nextTakeNumber = 1,
    this.isRecording = false,
    this.recordingStartTime,
  });

  /// Get active lane
  RecordingLane? get activeLane {
    if (lanes.isEmpty) return null;
    if (activeLaneIndex >= lanes.length) return lanes.first;
    return lanes[activeLaneIndex];
  }

  /// Get all takes across all lanes
  List<Take> get allTakes {
    return lanes.expand((l) => l.takes).toList();
  }

  /// Get takes at a specific time
  List<Take> takesAt(double time) {
    return allTakes
        .where((t) => t.startTime <= time && t.endTime >= time)
        .toList();
  }

  /// Total lane height when expanded
  double get expandedHeight {
    return lanes.where((l) => l.visible).fold(0.0, (sum, l) => sum + l.height);
  }

  CompState copyWith({
    String? trackId,
    CompMode? mode,
    bool? lanesExpanded,
    List<RecordingLane>? lanes,
    List<CompRegion>? compRegions,
    int? activeLaneIndex,
    int? nextTakeNumber,
    bool? isRecording,
    double? recordingStartTime,
  }) {
    return CompState(
      trackId: trackId ?? this.trackId,
      mode: mode ?? this.mode,
      lanesExpanded: lanesExpanded ?? this.lanesExpanded,
      lanes: lanes ?? this.lanes,
      compRegions: compRegions ?? this.compRegions,
      activeLaneIndex: activeLaneIndex ?? this.activeLaneIndex,
      nextTakeNumber: nextTakeNumber ?? this.nextTakeNumber,
      isRecording: isRecording ?? this.isRecording,
      recordingStartTime: recordingStartTime ?? this.recordingStartTime,
    );
  }

  /// Create a new lane
  CompState createLane({String? name}) {
    final newLane = RecordingLane(
      id: 'lane-${DateTime.now().millisecondsSinceEpoch}',
      trackId: trackId,
      index: lanes.length,
      name: name ?? '',
      isActive: lanes.isEmpty, // First lane is active by default
    );
    return copyWith(lanes: [...lanes, newLane]);
  }

  /// Add a take to specified lane (or active lane if null)
  CompState addTake(Take take, {String? laneId}) {
    final targetLaneId = laneId ?? activeLane?.id;
    if (targetLaneId == null) return this;

    final updatedLanes = lanes.map((lane) {
      if (lane.id == targetLaneId) {
        return lane.addTake(take);
      }
      return lane;
    }).toList();

    return copyWith(
      lanes: updatedLanes,
      nextTakeNumber: nextTakeNumber + 1,
    );
  }

  /// Set active lane by index
  CompState setActiveLane(int index) {
    if (index < 0 || index >= lanes.length) return this;

    final updatedLanes = lanes.asMap().map((i, lane) {
      return MapEntry(i, lane.copyWith(isActive: i == index));
    }).values.toList();

    return copyWith(
      lanes: updatedLanes,
      activeLaneIndex: index,
    );
  }

  /// Toggle lanes expanded view
  CompState toggleLanesExpanded() {
    return copyWith(lanesExpanded: !lanesExpanded);
  }

  /// Start recording
  CompState startRecording(double startTime) {
    return copyWith(
      isRecording: true,
      recordingStartTime: startTime,
    );
  }

  /// Stop recording and add the take
  CompState stopRecording(Take take) {
    return addTake(take).copyWith(
      isRecording: false,
      recordingStartTime: null,
    );
  }

  /// Add a comp region
  CompState addCompRegion(CompRegion region) {
    // Insert in sorted order and handle overlaps
    final newRegions = [...compRegions, region]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return copyWith(compRegions: newRegions, mode: CompMode.comp);
  }

  /// Remove a comp region
  CompState removeCompRegion(String regionId) {
    return copyWith(
      compRegions: compRegions.where((r) => r.id != regionId).toList(),
    );
  }

  /// Clear all comp regions
  CompState clearComp() {
    return copyWith(compRegions: [], mode: CompMode.single);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Default lane height in pixels
const double kDefaultLaneHeight = 60.0;

/// Minimum lane height
const double kMinLaneHeight = 30.0;

/// Maximum lane height
const double kMaxLaneHeight = 200.0;

/// Default comp crossfade duration in seconds
const double kDefaultCompCrossfade = 0.01; // 10ms

/// Lane colors for multi-take display
const List<Color> kLaneColors = [
  Color(0xFF4A9EFF), // Blue
  Color(0xFFFF9040), // Orange
  Color(0xFF40FF90), // Green
  Color(0xFFFF4090), // Pink
  Color(0xFF40C8FF), // Cyan
  Color(0xFFFFD43B), // Yellow
  Color(0xFF845EF7), // Purple
  Color(0xFFFF6B6B), // Red
];

/// Get lane color by index
Color getLaneColor(int index) {
  return kLaneColors[index % kLaneColors.length];
}

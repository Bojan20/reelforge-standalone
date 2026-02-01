// Timeline State Model — Complete Timeline State Management
//
// Central state for SlotLab timeline:
// - Tracks and regions
// - Playback position
// - Zoom/scroll state
// - Grid settings
// - Markers and automation

import 'package:flutter/material.dart';
import 'audio_region.dart';
import 'automation_lane.dart';
import 'stage_marker.dart';

/// Grid mode for timeline snapping
enum GridMode {
  beat,        // Snap to beats (requires tempo)
  millisecond, // Snap to ms intervals (10/50/100/250/500ms)
  frame,       // Snap to video frames (24/30/60fps)
  free,        // No snapping
}

/// Time display mode
enum TimeDisplayMode {
  milliseconds, // 1000ms, 2000ms
  seconds,      // 1.0s, 2.5s
  beats,        // 1.1.1 (bar.beat.tick)
  timecode,     // 00:00:01:00 (SMPTE)
}

/// Single audio track
class TimelineTrack {
  final String id;
  final String name;
  final List<AudioRegion> regions;
  final List<AutomationLane> automationLanes;
  final Color trackColor;
  final bool isMuted;
  final bool isSoloed;
  final bool isRecordArmed;
  final double volume;        // Track volume (0.0-2.0)
  final double pan;           // Track pan (−1.0 to +1.0)
  final int busId;            // Routed bus (0=Master, 1=Music, 2=SFX, etc.)

  const TimelineTrack({
    required this.id,
    required this.name,
    this.regions = const [],
    this.automationLanes = const [],
    this.trackColor = const Color(0xFF4A9EFF),
    this.isMuted = false,
    this.isSoloed = false,
    this.isRecordArmed = false,
    this.volume = 1.0,
    this.pan = 0.0,
    this.busId = 0,
  });

  /// Get region at specific time
  AudioRegion? getRegionAt(double timeSeconds) {
    for (final region in regions) {
      if (region.containsTime(timeSeconds)) return region;
    }
    return null;
  }

  /// Add region to track
  TimelineTrack addRegion(AudioRegion region) {
    final updatedRegions = List<AudioRegion>.from(regions)..add(region);
    return copyWith(regions: updatedRegions);
  }

  /// Remove region by ID
  TimelineTrack removeRegion(String regionId) {
    final updatedRegions = regions.where((r) => r.id != regionId).toList();
    return copyWith(regions: updatedRegions);
  }

  /// Update region
  TimelineTrack updateRegion(String regionId, AudioRegion updatedRegion) {
    final updatedRegions = regions.map((r) => r.id == regionId ? updatedRegion : r).toList();
    return copyWith(regions: updatedRegions);
  }

  TimelineTrack copyWith({
    String? id,
    String? name,
    List<AudioRegion>? regions,
    List<AutomationLane>? automationLanes,
    Color? trackColor,
    bool? isMuted,
    bool? isSoloed,
    bool? isRecordArmed,
    double? volume,
    double? pan,
    int? busId,
  }) {
    return TimelineTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      regions: regions ?? this.regions,
      automationLanes: automationLanes ?? this.automationLanes,
      trackColor: trackColor ?? this.trackColor,
      isMuted: isMuted ?? this.isMuted,
      isSoloed: isSoloed ?? this.isSoloed,
      isRecordArmed: isRecordArmed ?? this.isRecordArmed,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      busId: busId ?? this.busId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'regions': regions.map((r) => r.toJson()).toList(),
    'automationLanes': automationLanes.map((a) => a.toJson()).toList(),
    'trackColor': trackColor.value,
    'isMuted': isMuted,
    'isSoloed': isSoloed,
    'isRecordArmed': isRecordArmed,
    'volume': volume,
    'pan': pan,
    'busId': busId,
  };

  factory TimelineTrack.fromJson(Map<String, dynamic> json) {
    return TimelineTrack(
      id: json['id'] as String,
      name: json['name'] as String,
      regions: (json['regions'] as List?)
          ?.map((r) => AudioRegion.fromJson(r))
          .toList() ?? [],
      automationLanes: (json['automationLanes'] as List?)
          ?.map((a) => AutomationLane.fromJson(a))
          .toList() ?? [],
      trackColor: Color(json['trackColor'] as int? ?? 0xFF4A9EFF),
      isMuted: json['isMuted'] as bool? ?? false,
      isSoloed: json['isSoloed'] as bool? ?? false,
      isRecordArmed: json['isRecordArmed'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      busId: json['busId'] as int? ?? 0,
    );
  }
}

/// Complete timeline state
class TimelineState {
  final List<TimelineTrack> tracks;
  final List<StageMarker> markers;

  // Playback
  final double playheadPosition;  // Current time (seconds)
  final bool isPlaying;
  final bool isLooping;
  final double? loopStart;
  final double? loopEnd;

  // View settings
  final double zoom;              // 0.1x - 10.0x
  final double scrollOffset;      // Horizontal scroll position (pixels)
  final double totalDuration;     // Timeline duration (seconds)

  // Grid settings
  final GridMode gridMode;
  final bool snapEnabled;
  final double snapStrength;      // Magnetic pull radius (5-50px)
  final int millisecondInterval;  // 10, 50, 100, 250, 500
  final int frameRate;            // 24, 30, 60 fps

  // Display
  final TimeDisplayMode timeDisplayMode;

  const TimelineState({
    this.tracks = const [],
    this.markers = const [],
    this.playheadPosition = 0.0,
    this.isPlaying = false,
    this.isLooping = false,
    this.loopStart,
    this.loopEnd,
    this.zoom = 1.0,
    this.scrollOffset = 0.0,
    this.totalDuration = 30.0,
    this.gridMode = GridMode.millisecond,
    this.snapEnabled = true,
    this.snapStrength = 10.0,
    this.millisecondInterval = 100,
    this.frameRate = 60,
    this.timeDisplayMode = TimeDisplayMode.seconds,
  });

  /// Get track by ID
  TimelineTrack? getTrack(String trackId) {
    try {
      return tracks.firstWhere((t) => t.id == trackId);
    } catch (_) {
      return null;
    }
  }

  /// Add track
  TimelineState addTrack(TimelineTrack track) {
    return copyWith(tracks: [...tracks, track]);
  }

  /// Remove track
  TimelineState removeTrack(String trackId) {
    return copyWith(tracks: tracks.where((t) => t.id != trackId).toList());
  }

  /// Update track
  TimelineState updateTrack(String trackId, TimelineTrack updatedTrack) {
    final updatedTracks = tracks.map((t) => t.id == trackId ? updatedTrack : t).toList();
    return copyWith(tracks: updatedTracks);
  }

  /// Add marker
  TimelineState addMarker(StageMarker marker) {
    return copyWith(markers: [...markers, marker]);
  }

  /// Remove marker
  TimelineState removeMarker(String markerId) {
    return copyWith(markers: markers.where((m) => m.id != markerId).toList());
  }

  /// Get marker nearest to time
  StageMarker? getNearestMarker(double timeSeconds, {double maxDistance = 0.5}) {
    if (markers.isEmpty) return null;

    StageMarker? nearest;
    double minDistance = maxDistance;

    for (final marker in markers) {
      final distance = (marker.timeSeconds - timeSeconds).abs();
      if (distance < minDistance) {
        minDistance = distance;
        nearest = marker;
      }
    }

    return nearest;
  }

  /// Snap time to grid
  double snapToGrid(double timeSeconds) {
    if (!snapEnabled) return timeSeconds;

    switch (gridMode) {
      case GridMode.millisecond:
        final intervalSeconds = millisecondInterval / 1000.0;
        return (timeSeconds / intervalSeconds).round() * intervalSeconds;

      case GridMode.frame:
        final frameSeconds = 1.0 / frameRate;
        return (timeSeconds / frameSeconds).round() * frameSeconds;

      case GridMode.beat:
        // TODO: Implement beat snapping (requires tempo map)
        return timeSeconds;

      case GridMode.free:
        return timeSeconds;
    }
  }

  TimelineState copyWith({
    List<TimelineTrack>? tracks,
    List<StageMarker>? markers,
    double? playheadPosition,
    bool? isPlaying,
    bool? isLooping,
    double? loopStart,
    double? loopEnd,
    double? zoom,
    double? scrollOffset,
    double? totalDuration,
    GridMode? gridMode,
    bool? snapEnabled,
    double? snapStrength,
    int? millisecondInterval,
    int? frameRate,
    TimeDisplayMode? timeDisplayMode,
  }) {
    return TimelineState(
      tracks: tracks ?? this.tracks,
      markers: markers ?? this.markers,
      playheadPosition: playheadPosition ?? this.playheadPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      isLooping: isLooping ?? this.isLooping,
      loopStart: loopStart ?? this.loopStart,
      loopEnd: loopEnd ?? this.loopEnd,
      zoom: zoom ?? this.zoom,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      totalDuration: totalDuration ?? this.totalDuration,
      gridMode: gridMode ?? this.gridMode,
      snapEnabled: snapEnabled ?? this.snapEnabled,
      snapStrength: snapStrength ?? this.snapStrength,
      millisecondInterval: millisecondInterval ?? this.millisecondInterval,
      frameRate: frameRate ?? this.frameRate,
      timeDisplayMode: timeDisplayMode ?? this.timeDisplayMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'markers': markers.map((m) => m.toJson()).toList(),
    'playheadPosition': playheadPosition,
    'isLooping': isLooping,
    'loopStart': loopStart,
    'loopEnd': loopEnd,
    'zoom': zoom,
    'totalDuration': totalDuration,
    'gridMode': gridMode.name,
    'snapEnabled': snapEnabled,
    'snapStrength': snapStrength,
    'millisecondInterval': millisecondInterval,
    'frameRate': frameRate,
    'timeDisplayMode': timeDisplayMode.name,
  };

  factory TimelineState.fromJson(Map<String, dynamic> json) {
    return TimelineState(
      tracks: (json['tracks'] as List?)
          ?.map((t) => TimelineTrack.fromJson(t))
          .toList() ?? [],
      markers: (json['markers'] as List?)
          ?.map((m) => StageMarker.fromJson(m))
          .toList() ?? [],
      playheadPosition: (json['playheadPosition'] as num?)?.toDouble() ?? 0.0,
      isLooping: json['isLooping'] as bool? ?? false,
      loopStart: (json['loopStart'] as num?)?.toDouble(),
      loopEnd: (json['loopEnd'] as num?)?.toDouble(),
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      totalDuration: (json['totalDuration'] as num?)?.toDouble() ?? 30.0,
      gridMode: GridMode.values.firstWhere(
        (m) => m.name == json['gridMode'],
        orElse: () => GridMode.millisecond,
      ),
      snapEnabled: json['snapEnabled'] as bool? ?? true,
      snapStrength: (json['snapStrength'] as num?)?.toDouble() ?? 10.0,
      millisecondInterval: json['millisecondInterval'] as int? ?? 100,
      frameRate: json['frameRate'] as int? ?? 60,
      timeDisplayMode: TimeDisplayMode.values.firstWhere(
        (m) => m.name == json['timeDisplayMode'],
        orElse: () => TimeDisplayMode.seconds,
      ),
    );
  }
}

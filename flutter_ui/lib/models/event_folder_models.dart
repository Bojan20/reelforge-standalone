/// Event Folder Models — DAW-side view of SlotLab composite events
///
/// EventFolder is a read-only container in the DAW left panel that mirrors
/// a SlotCompositeEvent from the middleware. Structure is owned by SlotLab;
/// DAW can only read/display it. Audio parameters (volume, pan, inserts)
/// are bidirectional via shared rf-engine.
///
/// See: .claude/architecture/UNIFIED_TRACK_GRAPH.md

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT FOLDER — DAW-side read-only container
// ═══════════════════════════════════════════════════════════════════════════════

/// A read-only folder in the DAW left panel that represents a SlotLab event.
/// Created/deleted/modified ONLY by SlotLab. DAW displays it as-is.
class EventFolder {
  final String id;
  final String eventId;
  final String name;
  final String category;
  final Color color;
  final List<EventLayerRef> layers;
  final bool isCollapsed;

  /// Whether any layer from this folder is currently placed in the DAW timeline
  final bool hasLayersInTimeline;

  const EventFolder({
    required this.id,
    required this.eventId,
    required this.name,
    this.category = 'general',
    this.color = const Color(0xFF4A90D9),
    this.layers = const [],
    this.isCollapsed = false,
    this.hasLayersInTimeline = false,
  });

  EventFolder copyWith({
    String? id,
    String? eventId,
    String? name,
    String? category,
    Color? color,
    List<EventLayerRef>? layers,
    bool? isCollapsed,
    bool? hasLayersInTimeline,
  }) {
    return EventFolder(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      name: name ?? this.name,
      category: category ?? this.category,
      color: color ?? this.color,
      layers: layers ?? this.layers,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      hasLayersInTimeline: hasLayersInTimeline ?? this.hasLayersInTimeline,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT LAYER REF — reference to a track within an event folder
// ═══════════════════════════════════════════════════════════════════════════════

/// Reference to a layer (audio track) within an event folder.
/// Points to a SlotEventLayer by ID. DAW uses this to display layer info
/// and to drag layers into the timeline.
class EventLayerRef {
  final String layerId;
  final String name;
  final String audioPath;
  final double volume;
  final double pan;
  final bool muted;
  final bool solo;
  final bool loop;

  /// Whether this layer is currently placed in the DAW timeline
  final bool isInTimeline;

  /// DAW track ID if placed in timeline (null if only in folder)
  final int? dawTrackId;

  const EventLayerRef({
    required this.layerId,
    required this.name,
    this.audioPath = '',
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.solo = false,
    this.loop = false,
    this.isInTimeline = false,
    this.dawTrackId,
  });

  EventLayerRef copyWith({
    String? layerId,
    String? name,
    String? audioPath,
    double? volume,
    double? pan,
    bool? muted,
    bool? solo,
    bool? loop,
    bool? isInTimeline,
    int? dawTrackId,
  }) {
    return EventLayerRef(
      layerId: layerId ?? this.layerId,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      loop: loop ?? this.loop,
      isInTimeline: isInTimeline ?? this.isInTimeline,
      dawTrackId: dawTrackId ?? this.dawTrackId,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT CATEGORY COLORS — consistent color coding per event type
// ═══════════════════════════════════════════════════════════════════════════════

class EventCategoryColors {
  EventCategoryColors._();

  static const Color spin = Color(0xFFFF8C00);       // Orange
  static const Color reelStop = Color(0xFF4ECDC4);    // Teal
  static const Color win = Color(0xFFFFD700);          // Gold
  static const Color feature = Color(0xFFE040FB);      // Purple
  static const Color cascade = Color(0xFFFF5252);      // Red
  static const Color jackpot = Color(0xFFFFAB00);      // Amber
  static const Color bonus = Color(0xFF69F0AE);        // Green
  static const Color ambient = Color(0xFF64B5F6);      // Blue
  static const Color ui = Color(0xFF90A4AE);            // Gray
  static const Color general = Color(0xFF4A90D9);      // Default blue

  static Color forCategory(String category) {
    switch (category.toLowerCase()) {
      case 'spin':
        return spin;
      case 'reel_stop':
      case 'reelstop':
        return reelStop;
      case 'win':
        return win;
      case 'feature':
        return feature;
      case 'cascade':
        return cascade;
      case 'jackpot':
        return jackpot;
      case 'bonus':
        return bonus;
      case 'ambient':
      case 'ambience':
        return ambient;
      case 'ui':
        return ui;
      default:
        return general;
    }
  }
}

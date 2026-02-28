/// Event Folder Models — DAW-side view of SlotLab composite events
///
/// EventFolder is a read-only container in the DAW left panel that mirrors
/// a SlotCompositeEvent from the middleware. Structure is owned by SlotLab;
/// DAW can only read/display it. Audio parameters (volume, pan, inserts)
/// are bidirectional via shared rf-engine.
///
/// See: .claude/architecture/UNIFIED_TRACK_GRAPH.md

import 'package:flutter/material.dart';
import 'timeline_models.dart' show CrossfadeCurve;

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT FOLDER — DAW-side read-only container
// ═══════════════════════════════════════════════════════════════════════════════

/// Crossfade settings for an event folder's audio transitions
class CrossfadeSettings {
  final double fadeInMs;
  final double fadeOutMs;
  final CrossfadeCurve fadeInCurve;
  final CrossfadeCurve fadeOutCurve;

  const CrossfadeSettings({
    this.fadeInMs = 0.0,
    this.fadeOutMs = 0.0,
    this.fadeInCurve = CrossfadeCurve.equalPower,
    this.fadeOutCurve = CrossfadeCurve.equalPower,
  });

  CrossfadeSettings copyWith({
    double? fadeInMs,
    double? fadeOutMs,
    CrossfadeCurve? fadeInCurve,
    CrossfadeCurve? fadeOutCurve,
  }) {
    return CrossfadeSettings(
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      fadeInCurve: fadeInCurve ?? this.fadeInCurve,
      fadeOutCurve: fadeOutCurve ?? this.fadeOutCurve,
    );
  }
}

/// Variant group within an event (A/B/C alternatives with weighted selection)
class VariantGroup {
  final String id;
  final String name;
  final List<String> layerIds;
  final double weight;

  const VariantGroup({
    required this.id,
    required this.name,
    this.layerIds = const [],
    this.weight = 1.0,
  });
}

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

  /// Crossfade settings for event transitions
  final CrossfadeSettings crossfade;

  /// Variant groups within this event (A/B/C alternatives)
  final List<VariantGroup> variantGroups;

  const EventFolder({
    required this.id,
    required this.eventId,
    required this.name,
    this.category = 'general',
    this.color = const Color(0xFF4A90D9),
    this.layers = const [],
    this.isCollapsed = false,
    this.hasLayersInTimeline = false,
    this.crossfade = const CrossfadeSettings(),
    this.variantGroups = const [],
  });

  /// Layers that belong to a specific variant group
  List<EventLayerRef> layersForVariant(String groupId) =>
      layers.where((l) => l.variantGroup == groupId).toList();

  /// Layers that are always active (no variant group)
  List<EventLayerRef> get alwaysActiveLayers =>
      layers.where((l) => l.variantGroup == null).toList();

  /// Layers with conditional activation rules
  List<EventLayerRef> get conditionalLayers =>
      layers.where((l) => l.isConditional).toList();

  EventFolder copyWith({
    String? id,
    String? eventId,
    String? name,
    String? category,
    Color? color,
    List<EventLayerRef>? layers,
    bool? isCollapsed,
    bool? hasLayersInTimeline,
    CrossfadeSettings? crossfade,
    List<VariantGroup>? variantGroups,
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
      crossfade: crossfade ?? this.crossfade,
      variantGroups: variantGroups ?? this.variantGroups,
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

  /// Event IDs sharing this same underlying track (for 5.1 track reuse)
  final List<String> sharedEventIds;

  /// Variant group this layer belongs to (null = always active)
  final String? variantGroup;

  /// Weight within variant group (0.0–1.0, higher = more likely)
  final double variantWeight;

  /// Minimum win multiplier to activate this layer (0 = always)
  final double minMultiplier;

  /// Minimum bet threshold to activate this layer (0 = always)
  final double betThreshold;

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
    this.sharedEventIds = const [],
    this.variantGroup,
    this.variantWeight = 1.0,
    this.minMultiplier = 0.0,
    this.betThreshold = 0.0,
  });

  /// How many events share this layer's underlying track
  int get sharedCount => sharedEventIds.length;

  /// Whether this layer is shared across multiple events
  bool get isShared => sharedEventIds.length > 1;

  /// Whether this layer has conditional activation rules
  bool get isConditional => minMultiplier > 0.0 || betThreshold > 0.0;

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
    List<String>? sharedEventIds,
    String? variantGroup,
    double? variantWeight,
    double? minMultiplier,
    double? betThreshold,
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
      sharedEventIds: sharedEventIds ?? this.sharedEventIds,
      variantGroup: variantGroup ?? this.variantGroup,
      variantWeight: variantWeight ?? this.variantWeight,
      minMultiplier: minMultiplier ?? this.minMultiplier,
      betThreshold: betThreshold ?? this.betThreshold,
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

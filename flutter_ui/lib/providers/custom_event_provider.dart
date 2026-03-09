// Custom Event Provider
//
// Manages user-created events outside the predefined SlotLab stage system.
// Custom events have ID format `custom_<name>` to distinguish from `audio_<STAGE>`.
//
// Features:
// - CRUD operations for custom events
// - Audio layer management (drag & drop from pool)
// - EventRegistry + MiddlewareProvider synchronization
// - JSON serialization for project persistence

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM EVENT MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// A user-created event outside the predefined stage system
class CustomEvent {
  /// Unique ID — format: `custom_<name>` (distinguishes from `audio_<STAGE>`)
  final String id;

  /// Display name
  final String name;

  /// Optional description
  final String description;

  /// Category for grouping (user-defined)
  final String category;

  /// Color for UI display
  final Color color;

  /// Audio layers assigned to this event
  final List<CustomEventLayer> layers;

  /// Trigger mode — how this event is fired
  final CustomTriggerMode triggerMode;

  /// Probability of triggering (0-1, 1 = always)
  final double probability;

  /// Cooldown in seconds before event can re-trigger
  final double cooldownSeconds;

  /// Is this event enabled
  final bool enabled;

  /// Creation timestamp
  final DateTime createdAt;

  const CustomEvent({
    required this.id,
    required this.name,
    this.description = '',
    this.category = 'General',
    this.color = const Color(0xFF9040FF),
    this.layers = const [],
    this.triggerMode = CustomTriggerMode.manual,
    this.probability = 1.0,
    this.cooldownSeconds = 0,
    this.enabled = true,
    required this.createdAt,
  });

  /// Generate ID from name
  static String makeId(String name) {
    return 'custom_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
  }

  CustomEvent copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    Color? color,
    List<CustomEventLayer>? layers,
    CustomTriggerMode? triggerMode,
    double? probability,
    double? cooldownSeconds,
    bool? enabled,
    DateTime? createdAt,
  }) {
    return CustomEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      color: color ?? this.color,
      layers: layers ?? this.layers,
      triggerMode: triggerMode ?? this.triggerMode,
      probability: probability ?? this.probability,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Audio layer within a custom event
class CustomEventLayer {
  /// Unique layer ID
  final String id;

  /// Audio file path
  final String audioPath;

  /// Display name (defaults to filename)
  final String name;

  /// Volume (0-2, 1 = unity)
  final double volume;

  /// Pan (-1 to +1)
  final double pan;

  /// Pitch shift in semitones
  final double pitchSemitones;

  /// Is this layer muted
  final bool muted;

  /// Is this layer solo
  final bool solo;

  /// Playback probability (0-1, for variation)
  final double probability;

  const CustomEventLayer({
    required this.id,
    required this.audioPath,
    this.name = '',
    this.volume = 1.0,
    this.pan = 0.0,
    this.pitchSemitones = 0,
    this.muted = false,
    this.solo = false,
    this.probability = 1.0,
  });

  String get displayName => name.isNotEmpty ? name : audioPath.split('/').last;

  CustomEventLayer copyWith({
    String? id,
    String? audioPath,
    String? name,
    double? volume,
    double? pan,
    double? pitchSemitones,
    bool? muted,
    bool? solo,
    double? probability,
  }) {
    return CustomEventLayer(
      id: id ?? this.id,
      audioPath: audioPath ?? this.audioPath,
      name: name ?? this.name,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      pitchSemitones: pitchSemitones ?? this.pitchSemitones,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      probability: probability ?? this.probability,
    );
  }
}

/// How a custom event is triggered
enum CustomTriggerMode {
  /// Manual trigger only (via code or UI)
  manual,
  /// Trigger on specific marker
  marker,
  /// Trigger on timeline position
  position,
  /// Trigger via MIDI note
  midi,
  /// Trigger via OSC message
  osc,
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class CustomEventProvider extends ChangeNotifier {
  final List<CustomEvent> _events = [];
  String? _selectedEventId;

  // ─── Getters ──────────────────────────────────────────────────────────────

  List<CustomEvent> get events => List.unmodifiable(_events);
  String? get selectedEventId => _selectedEventId;

  CustomEvent? get selectedEvent {
    if (_selectedEventId == null) return null;
    return _events.cast<CustomEvent?>().firstWhere(
        (e) => e!.id == _selectedEventId, orElse: () => null);
  }

  /// Get events by category
  Map<String, List<CustomEvent>> get eventsByCategory {
    final map = <String, List<CustomEvent>>{};
    for (final e in _events) {
      map.putIfAbsent(e.category, () => []).add(e);
    }
    return map;
  }

  /// Get all category names
  List<String> get categories => eventsByCategory.keys.toList()..sort();

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  /// Create a new custom event
  CustomEvent createEvent({
    required String name,
    String description = '',
    String category = 'General',
    Color? color,
  }) {
    final id = CustomEvent.makeId(name);
    // Ensure unique ID
    var uniqueId = id;
    var counter = 1;
    while (_events.any((e) => e.id == uniqueId)) {
      uniqueId = '${id}_$counter';
      counter++;
    }

    final event = CustomEvent(
      id: uniqueId,
      name: name,
      description: description,
      category: category,
      color: color ?? const Color(0xFF9040FF),
      createdAt: DateTime.now(),
    );

    _events.add(event);
    notifyListeners();
    return event;
  }

  /// Update an existing event
  void updateEvent(String eventId, CustomEvent Function(CustomEvent) updater) {
    final index = _events.indexWhere((e) => e.id == eventId);
    if (index < 0) return;
    _events[index] = updater(_events[index]);
    notifyListeners();
  }

  /// Delete an event
  void deleteEvent(String eventId) {
    _events.removeWhere((e) => e.id == eventId);
    if (_selectedEventId == eventId) _selectedEventId = null;
    notifyListeners();
  }

  /// Rename event
  void renameEvent(String eventId, String newName) {
    updateEvent(eventId, (e) => e.copyWith(name: newName));
  }

  /// Set event category
  void setEventCategory(String eventId, String category) {
    updateEvent(eventId, (e) => e.copyWith(category: category));
  }

  /// Toggle event enabled
  void toggleEventEnabled(String eventId) {
    updateEvent(eventId, (e) => e.copyWith(enabled: !e.enabled));
  }

  /// Set event probability
  void setEventProbability(String eventId, double probability) {
    updateEvent(eventId,
        (e) => e.copyWith(probability: probability.clamp(0.0, 1.0)));
  }

  /// Set event trigger mode
  void setEventTriggerMode(String eventId, CustomTriggerMode mode) {
    updateEvent(eventId, (e) => e.copyWith(triggerMode: mode));
  }

  // ─── Selection ────────────────────────────────────────────────────────────

  void selectEvent(String? eventId) {
    _selectedEventId = eventId;
    notifyListeners();
  }

  // ─── Layer Management ─────────────────────────────────────────────────────

  /// Add audio layer to event (e.g. from drag & drop)
  void addLayer(String eventId, String audioPath, {String? name}) {
    updateEvent(eventId, (e) {
      final layerId = 'layer_${DateTime.now().millisecondsSinceEpoch}';
      final layer = CustomEventLayer(
        id: layerId,
        audioPath: audioPath,
        name: name ?? '',
      );
      return e.copyWith(layers: [...e.layers, layer]);
    });
  }

  /// Remove layer from event
  void removeLayer(String eventId, String layerId) {
    updateEvent(eventId, (e) {
      return e.copyWith(
          layers: e.layers.where((l) => l.id != layerId).toList());
    });
  }

  /// Update layer properties
  void updateLayer(String eventId, String layerId,
      CustomEventLayer Function(CustomEventLayer) updater) {
    updateEvent(eventId, (e) {
      final layers = e.layers.map((l) {
        if (l.id == layerId) return updater(l);
        return l;
      }).toList();
      return e.copyWith(layers: layers);
    });
  }

  /// Set layer volume
  void setLayerVolume(String eventId, String layerId, double volume) {
    updateLayer(eventId, layerId,
        (l) => l.copyWith(volume: volume.clamp(0.0, 2.0)));
  }

  /// Set layer pan
  void setLayerPan(String eventId, String layerId, double pan) {
    updateLayer(eventId, layerId,
        (l) => l.copyWith(pan: pan.clamp(-1.0, 1.0)));
  }

  /// Toggle layer mute
  void toggleLayerMute(String eventId, String layerId) {
    updateLayer(eventId, layerId, (l) => l.copyWith(muted: !l.muted));
  }

  /// Toggle layer solo
  void toggleLayerSolo(String eventId, String layerId) {
    updateLayer(eventId, layerId, (l) => l.copyWith(solo: !l.solo));
  }

  /// Reorder layers
  void reorderLayers(String eventId, int oldIndex, int newIndex) {
    updateEvent(eventId, (e) {
      final layers = List<CustomEventLayer>.from(e.layers);
      if (newIndex > oldIndex) newIndex--;
      final item = layers.removeAt(oldIndex);
      layers.insert(newIndex, item);
      return e.copyWith(layers: layers);
    });
  }

  // ─── Serialization ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'events': _events.map((e) => {
        'id': e.id,
        'name': e.name,
        'description': e.description,
        'category': e.category,
        'color': e.color.toARGB32(),
        'triggerMode': e.triggerMode.index,
        'probability': e.probability,
        'cooldownSeconds': e.cooldownSeconds,
        'enabled': e.enabled,
        'createdAt': e.createdAt.millisecondsSinceEpoch,
        'layers': e.layers.map((l) => {
          'id': l.id,
          'audioPath': l.audioPath,
          'name': l.name,
          'volume': l.volume,
          'pan': l.pan,
          'pitchSemitones': l.pitchSemitones,
          'muted': l.muted,
          'solo': l.solo,
          'probability': l.probability,
        }).toList(),
      }).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _events.clear();
    final events = json['events'] as List?;
    if (events == null) return;

    for (final e in events) {
      final map = e as Map<String, dynamic>;
      final layers = (map['layers'] as List?)?.map((l) {
        final lm = l as Map<String, dynamic>;
        return CustomEventLayer(
          id: lm['id'] as String,
          audioPath: lm['audioPath'] as String,
          name: lm['name'] as String? ?? '',
          volume: (lm['volume'] as num?)?.toDouble() ?? 1.0,
          pan: (lm['pan'] as num?)?.toDouble() ?? 0.0,
          pitchSemitones: (lm['pitchSemitones'] as num?)?.toDouble() ?? 0,
          muted: lm['muted'] as bool? ?? false,
          solo: lm['solo'] as bool? ?? false,
          probability: (lm['probability'] as num?)?.toDouble() ?? 1.0,
        );
      }).toList() ?? [];

      _events.add(CustomEvent(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String? ?? '',
        category: map['category'] as String? ?? 'General',
        color: Color(map['color'] as int? ?? 0xFF9040FF),
        triggerMode: CustomTriggerMode.values[map['triggerMode'] as int? ?? 0],
        probability: (map['probability'] as num?)?.toDouble() ?? 1.0,
        cooldownSeconds: (map['cooldownSeconds'] as num?)?.toDouble() ?? 0,
        enabled: map['enabled'] as bool? ?? true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        layers: layers,
      ));
    }

    notifyListeners();
  }

  // ─── Reset ────────────────────────────────────────────────────────────────

  void reset() {
    _events.clear();
    _selectedEventId = null;
    notifyListeners();
  }
}

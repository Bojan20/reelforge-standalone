/// Composite Event System Provider
///
/// Extracted from MiddlewareProvider as part of P1.5 decomposition.
/// Manages SlotCompositeEvent CRUD, undo/redo, layer operations,
/// batch operations, clipboard, and real-time sync with EventSystemProvider.
///
/// SlotCompositeEvents are layered audio events (Wwise/FMOD-style) that
/// combine multiple audio layers with timing, volume, and pan control.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/middleware_models.dart';
import '../../models/slot_audio_events.dart';
import '../../services/audio_playback_service.dart';
import '../../services/event_registry.dart';
import '../../src/rust/native_ffi.dart';
import 'event_system_provider.dart';

/// Change type for composite event notifications
enum CompositeEventChangeType {
  created,
  updated,
  deleted,
}

/// History entry for tracking event changes
class EventHistoryEntry {
  final DateTime timestamp;
  final String eventId;
  final String eventName;
  final CompositeEventChangeType changeType;
  final String description;
  final String? details;

  const EventHistoryEntry({
    required this.timestamp,
    required this.eventId,
    required this.eventName,
    required this.changeType,
    required this.description,
    this.details,
  });

  String get icon {
    switch (changeType) {
      case CompositeEventChangeType.created:
        return '➕';
      case CompositeEventChangeType.updated:
        return '✏️';
      case CompositeEventChangeType.deleted:
        return '🗑️';
    }
  }

  String get changeTypeLabel {
    switch (changeType) {
      case CompositeEventChangeType.created:
        return 'Created';
      case CompositeEventChangeType.updated:
        return 'Modified';
      case CompositeEventChangeType.deleted:
        return 'Deleted';
    }
  }
}

/// Provider for managing composite events (layered audio events)
class CompositeEventSystemProvider extends ChangeNotifier {
  final NativeFFI _ffi;
  final EventSystemProvider _eventSystemProvider;

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.1 SECURITY: Audio path validation
  // ═══════════════════════════════════════════════════════════════════════════

  /// Allowed audio file extensions (case-insensitive)
  static const _allowedAudioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

  /// Validate audio path for security and format compliance
  /// Returns true if path is valid, false otherwise
  bool _validateAudioPath(String path) {
    // Empty paths are allowed for placeholder layers (user assigns audio later)
    if (path.isEmpty) {
      return true;
    }

    // Block path traversal attacks
    if (path.contains('..')) {
      return false;
    }

    // Block null byte injection
    if (path.contains('\x00')) {
      return false;
    }

    // Validate file extension
    final lowerPath = path.toLowerCase();
    final hasValidExtension = _allowedAudioExtensions.any((ext) => lowerPath.endsWith(ext));
    if (!hasValidExtension) {
      return false;
    }

    // Block suspicious characters (command injection prevention)
    if (path.contains('\n') || path.contains('\r') || path.contains('|') || path.contains(';')) {
      return false;
    }

    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.5 SECURITY: Name/Category sanitization for XSS prevention
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sanitize a string for safe display (XSS prevention)
  /// Removes HTML-like tags and dangerous characters
  String _sanitizeName(String input) {
    if (input.isEmpty) return input;

    // Limit length
    const maxLength = 128;
    var sanitized = input.length > maxLength ? input.substring(0, maxLength) : input;

    // Remove HTML tags
    sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');

    // Escape HTML entities
    sanitized = sanitized
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');

    // Remove control characters
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

    // Trim whitespace
    sanitized = sanitized.trim();

    if (sanitized != input) {
    }

    return sanitized;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Composite events storage
  final Map<String, SlotCompositeEvent> _compositeEvents = {};

  /// Currently selected composite event ID
  String? _selectedCompositeEventId;

  /// Next layer ID counter
  int _nextLayerId = 1;

  /// Undo/Redo stacks for composite events
  final List<Map<String, SlotCompositeEvent>> _undoStack = [];
  final List<Map<String, SlotCompositeEvent>> _redoStack = [];
  static const int _maxUndoHistory = 50;

  /// P2.17 FIX: Maximum number of composite events to prevent unbounded memory growth
  static const int _maxCompositeEvents = 500;

  /// Layer clipboard for copy/paste (single layer)
  SlotEventLayer? _layerClipboard;
  String? _selectedLayerId;

  /// Multi-layer clipboard for batch copy/paste
  List<SlotEventLayer> _layersClipboard = [];

  /// Multi-select support for batch operations
  final Set<String> _selectedLayerIds = {};

  /// Event history tracking (most recent first)
  final List<EventHistoryEntry> _eventHistory = [];
  static const int _maxHistoryEntries = 100;

  /// Change listeners for bidirectional sync
  final List<void Function(String eventId, CompositeEventChangeType type)>
      _compositeChangeListeners = [];

  CompositeEventSystemProvider({
    required NativeFFI ffi,
    required EventSystemProvider eventSystemProvider,
  })  : _ffi = ffi,
        _eventSystemProvider = eventSystemProvider;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all composite events
  List<SlotCompositeEvent> get compositeEvents => _compositeEvents.values.toList();

  /// Get composite events count
  int get compositeEventCount => _compositeEvents.length;

  /// Get selected composite event
  SlotCompositeEvent? get selectedCompositeEvent =>
      _selectedCompositeEventId != null ? _compositeEvents[_selectedCompositeEventId] : null;

  /// Get selected composite event ID
  String? get selectedCompositeEventId => _selectedCompositeEventId;

  /// Undo/Redo getters
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoStackSize => _undoStack.length;
  int get redoStackSize => _redoStack.length;

  /// Layer clipboard getters (single)
  bool get hasLayerInClipboard => _layerClipboard != null;
  SlotEventLayer? get layerClipboard => _layerClipboard;
  String? get selectedLayerId => _selectedLayerId;

  /// Multi-layer clipboard getters
  bool get hasLayersInClipboard => _layersClipboard.isNotEmpty;
  List<SlotEventLayer> get layersClipboard => List.unmodifiable(_layersClipboard);
  int get clipboardLayerCount => _layersClipboard.length;

  /// Multi-select getters
  Set<String> get selectedLayerIds => Set.unmodifiable(_selectedLayerIds);

  /// Event history getters
  List<EventHistoryEntry> get eventHistory => List.unmodifiable(_eventHistory);
  int get eventHistoryCount => _eventHistory.length;

  /// Record a history entry
  void _recordHistory({
    required String eventId,
    required String eventName,
    required CompositeEventChangeType changeType,
    required String description,
    String? details,
  }) {
    final entry = EventHistoryEntry(
      timestamp: DateTime.now(),
      eventId: eventId,
      eventName: eventName,
      changeType: changeType,
      description: description,
      details: details,
    );

    // Insert at beginning (most recent first)
    _eventHistory.insert(0, entry);

    // Trim to max size
    if (_eventHistory.length > _maxHistoryEntries) {
      _eventHistory.removeLast();
    }
  }

  /// Clear event history
  void clearEventHistory() {
    _eventHistory.clear();
    notifyListeners();
  }
  bool get hasMultipleLayersSelected => _selectedLayerIds.length > 1;
  int get selectedLayerCount => _selectedLayerIds.length;

  /// Get composite event by ID
  SlotCompositeEvent? getCompositeEvent(String eventId) => _compositeEvents[eventId];

  /// Get events by category
  List<SlotCompositeEvent> getEventsByCategory(String category) =>
      _compositeEvents.values.where((e) => e.category == category).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANGE LISTENERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a listener for composite event changes
  void addCompositeChangeListener(
      void Function(String eventId, CompositeEventChangeType type) listener) {
    _compositeChangeListeners.add(listener);
  }

  /// Remove a composite event change listener
  void removeCompositeChangeListener(
      void Function(String eventId, CompositeEventChangeType type) listener) {
    _compositeChangeListeners.remove(listener);
  }

  /// Notify all listeners of a change
  void _notifyCompositeChange(String eventId, CompositeEventChangeType type) {
    for (final listener in _compositeChangeListeners) {
      listener(eventId, type);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOSITE EVENT CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new composite event
  SlotCompositeEvent createCompositeEvent({
    required String name,
    String category = 'general',
    Color? color,
  }) {
    _pushUndoState();
    // P2.5 SECURITY: Sanitize name and category for XSS prevention
    final sanitizedName = _sanitizeName(name);
    final sanitizedCategory = _sanitizeName(category);
    final id = 'event_${DateTime.now().millisecondsSinceEpoch}';
    final event = SlotCompositeEvent(
      id: id,
      name: sanitizedName,
      category: sanitizedCategory,
      color: color ??
          SlotEventCategory.values
              .firstWhere((c) => c.name == category, orElse: () => SlotEventCategory.ui)
              .color,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[id] = event;
    _selectedCompositeEventId = id;
    _syncCompositeToMiddleware(event);
    _notifyCompositeChange(id, CompositeEventChangeType.created);
    notifyListeners();
    return event;
  }

  /// Create composite event from template
  SlotCompositeEvent createFromTemplate(SlotCompositeEvent template) {
    _pushUndoState();
    final id = 'event_${DateTime.now().millisecondsSinceEpoch}';
    final event = template.copyWith(
      id: id,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[id] = event;
    _selectedCompositeEventId = id;
    _syncCompositeToMiddleware(event);
    notifyListeners();
    return event;
  }

  /// Add existing composite event (for sync from external sources)
  void addCompositeEvent(SlotCompositeEvent event, {bool select = true}) {
    _pushUndoState();
    _compositeEvents[event.id] = event;
    _syncCompositeToMiddleware(event);
    if (select) {
      _selectedCompositeEventId = event.id;
    }
    _enforceCompositeEventsLimit();

    // Record history
    _recordHistory(
      eventId: event.id,
      eventName: event.name,
      changeType: CompositeEventChangeType.created,
      description: 'Created event "${event.name}"',
      details: '${event.layers.length} layer(s), ${event.triggerStages.length} stage(s)',
    );

    notifyListeners();
  }

  /// Update composite event
  void updateCompositeEvent(SlotCompositeEvent event) {
    final oldEvent = _compositeEvents[event.id];
    _pushUndoState();
    // P2.5 SECURITY: Sanitize name and category for XSS prevention
    final sanitizedEvent = event.copyWith(
      name: _sanitizeName(event.name),
      category: _sanitizeName(event.category),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[event.id] = sanitizedEvent;
    _syncCompositeToMiddleware(sanitizedEvent);

    // CRITICAL: Sync layer parameter changes to EventRegistry cached events
    // so the next trigger uses updated values (pan, volume, bus, etc.)
    if (oldEvent != null) {
      final registry = EventRegistry.instance;
      for (final layer in sanitizedEvent.layers) {
        final oldLayer = oldEvent.layers.cast<SlotEventLayer?>().firstWhere(
          (l) => l?.id == layer.id, orElse: () => null,
        );
        if (oldLayer == null) continue;
        // Check if any playback parameter changed
        if (oldLayer.pan != layer.pan || oldLayer.volume != layer.volume ||
            oldLayer.offsetMs != layer.offsetMs || oldLayer.busId != layer.busId ||
            oldLayer.fadeInMs != layer.fadeInMs || oldLayer.fadeOutMs != layer.fadeOutMs) {
          // Update active voices in real-time
          if (oldLayer.pan != layer.pan) {
            registry.updateActiveLayerPan(layer.id, layer.pan);
          }
          if (oldLayer.volume != layer.volume) {
            registry.updateActiveLayerVolume(layer.id, layer.volume);
          }
          // Update cached AudioEvent for next trigger
          final cachedEventIds = registry.findEventIdsForLayer(layer.id);
          for (final cachedId in cachedEventIds) {
            registry.updateCachedEventLayer(
              cachedId,
              layer.id,
              pan: layer.pan,
              volume: layer.volume,
              delay: layer.offsetMs,
              busId: layer.busId,
              fadeInMs: layer.fadeInMs,
              fadeOutMs: layer.fadeOutMs,
              trimStartMs: layer.trimStartMs,
              trimEndMs: layer.trimEndMs,
            );
          }
        }
      }
    }

    // Record history with change details
    String details = '';
    if (oldEvent != null) {
      final changes = <String>[];
      if (oldEvent.name != sanitizedEvent.name) changes.add('name');
      if (oldEvent.layers.length != sanitizedEvent.layers.length) changes.add('layers');
      if (oldEvent.triggerStages.length != sanitizedEvent.triggerStages.length) changes.add('stages');
      details = changes.isNotEmpty ? 'Changed: ${changes.join(", ")}' : 'Properties updated';
    }
    _recordHistory(
      eventId: sanitizedEvent.id,
      eventName: sanitizedEvent.name,
      changeType: CompositeEventChangeType.updated,
      description: 'Modified "${sanitizedEvent.name}"',
      details: details,
    );

    notifyListeners();
  }

  /// Rename composite event
  void renameCompositeEvent(String eventId, String newName) {
    final event = _compositeEvents[eventId];
    if (event != null) {
      final oldName = event.name;
      _pushUndoState();
      final updated = event.copyWith(
        name: newName,
        modifiedAt: DateTime.now(),
      );
      _compositeEvents[eventId] = updated;
      _syncCompositeToMiddleware(updated);

      // Record history
      _recordHistory(
        eventId: eventId,
        eventName: newName,
        changeType: CompositeEventChangeType.updated,
        description: 'Renamed "$oldName" → "$newName"',
      );

      notifyListeners();
    }
  }

  /// Delete a composite event
  void deleteCompositeEvent(String eventId) {
    final deletedEvent = _compositeEvents[eventId];
    final deletedName = deletedEvent?.name ?? eventId;

    _pushUndoState();

    // Stop any playing voices for this event
    AudioPlaybackService.instance.stopEvent(eventId);

    _compositeEvents.remove(eventId);
    _removeMiddlewareEventForComposite(eventId);
    if (_selectedCompositeEventId == eventId) {
      _selectedCompositeEventId = _compositeEvents.keys.firstOrNull;
    }

    // Record history
    _recordHistory(
      eventId: eventId,
      eventName: deletedName,
      changeType: CompositeEventChangeType.deleted,
      description: 'Deleted "$deletedName"',
    );

    notifyListeners();
  }

  /// Select a composite event
  void selectCompositeEvent(String? eventId) {
    _selectedCompositeEventId = eventId;
    notifyListeners();
  }

  /// P2.17: Enforce maximum composite events by evicting least-recently-modified events
  void _enforceCompositeEventsLimit() {
    if (_compositeEvents.length <= _maxCompositeEvents) return;

    final entries = _compositeEvents.entries.toList()
      ..sort((a, b) => a.value.modifiedAt.compareTo(b.value.modifiedAt));

    final target = (_maxCompositeEvents * 0.9).round();
    while (_compositeEvents.length > target && entries.isNotEmpty) {
      final oldest = entries.removeAt(0);
      if (oldest.key == _selectedCompositeEventId) continue;
      _compositeEvents.remove(oldest.key);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add layer to composite event
  SlotEventLayer addLayerToEvent(
    String eventId, {
    required String audioPath,
    required String name,
    double? durationSeconds,
    List<double>? waveformData,
  }) {
    final event = _compositeEvents[eventId];
    if (event == null) throw Exception('Event not found: $eventId');

    // P1.1 SECURITY: Validate audio path before proceeding
    if (!_validateAudioPath(audioPath)) {
      throw Exception('Invalid audio path: $audioPath');
    }

    _pushUndoState();

    // Auto-detect duration if not provided
    final actualDuration = durationSeconds ?? _ffi.getAudioFileDuration(audioPath);
    final validDuration = (actualDuration > 0) ? actualDuration : null;

    if (durationSeconds == null && validDuration != null) {
    }

    final layerId = 'layer_${_nextLayerId++}';
    final layer = SlotEventLayer(
      id: layerId,
      name: name,
      audioPath: audioPath,
      durationSeconds: validDuration,
      waveformData: waveformData,
    );

    final updated = event.copyWith(
      layers: [...event.layers, layer],
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);

    // Record history
    _recordHistory(
      eventId: eventId,
      eventName: updated.name,
      changeType: CompositeEventChangeType.updated,
      description: 'Added layer "$name" to "${updated.name}"',
      details: 'Audio: ${audioPath.split('/').last}',
    );

    notifyListeners();
    return layer;
  }

  /// Remove layer from composite event
  void removeLayerFromEvent(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    try { _pushUndoState(); } catch (_) {}
    try { AudioPlaybackService.instance.stopLayer(layerId); } catch (_) {}

    final updated = event.copyWith(
      layers: event.layers.where((l) => l.id != layerId).toList(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    try { _syncCompositeToMiddleware(updated); } catch (_) {}
    try {
      _recordHistory(
        eventId: eventId,
        eventName: event.name,
        changeType: CompositeEventChangeType.updated,
        description: 'Removed layer from "${event.name}"',
      );
    } catch (_) {}

    notifyListeners();
  }

  /// Update layer in composite event (internal, no undo)
  void _updateEventLayerInternal(String eventId, SlotEventLayer layer) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    // Find old layer for real-time diff
    final oldLayer = event.layers.cast<SlotEventLayer?>().firstWhere(
      (l) => l?.id == layer.id,
      orElse: () => null,
    );

    final updated = event.copyWith(
      layers: event.layers.map((l) => l.id == layer.id ? layer : l).toList(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);

    // Push real-time parameter changes to active voices AND cached events
    final registry = EventRegistry.instance;
    if (oldLayer != null) {
      if (oldLayer.volume != layer.volume) {
        registry.updateActiveLayerVolume(layer.id, layer.volume);
      }
      if (oldLayer.pan != layer.pan) {
        registry.updateActiveLayerPan(layer.id, layer.pan);
      }
      if (oldLayer.muted != layer.muted) {
        registry.updateActiveLayerMute(layer.id, layer.muted);
      }
    }

    // CRITICAL: Update cached AudioEvent in EventRegistry so NEXT trigger
    // uses the new parameter values (pan, volume, etc.)
    final cachedEventIds = registry.findEventIdsForLayer(layer.id);
    for (final cachedId in cachedEventIds) {
      registry.updateCachedEventLayer(
        cachedId,
        layer.id,
        pan: layer.pan,
        volume: layer.volume,
        delay: layer.offsetMs,
        busId: layer.busId,
        fadeInMs: layer.fadeInMs,
        fadeOutMs: layer.fadeOutMs,
        trimStartMs: layer.trimStartMs,
        trimEndMs: layer.trimEndMs,
      );
    }

    notifyListeners();
  }

  /// Update layer in composite event (public, with undo)
  void updateEventLayer(String eventId, SlotEventLayer layer) {
    _pushUndoState();
    _updateEventLayerInternal(eventId, layer);
  }

  /// Toggle layer mute
  void toggleLayerMute(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();

    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(muted: !layer.muted));
  }

  /// Toggle layer solo
  void toggleLayerSolo(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();

    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(solo: !layer.solo));
  }

  /// Set layer volume (no undo - use for continuous slider updates)
  void setLayerVolumeContinuous(String eventId, String layerId, double volume) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(volume: volume.clamp(0.0, 1.0)));
  }

  /// Set layer volume (with undo - use for final value)
  void setLayerVolume(String eventId, String layerId, double volume) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(volume: volume.clamp(0.0, 1.0)));
  }

  /// Set layer pan (no undo - use for continuous slider updates)
  void setLayerPanContinuous(String eventId, String layerId, double pan) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(pan: pan.clamp(-1.0, 1.0)));
  }

  /// Set layer pan (with undo - use for final value)
  void setLayerPan(String eventId, String layerId, double pan) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(pan: pan.clamp(-1.0, 1.0)));
  }

  /// Set layer offset (no undo - use for continuous drag updates)
  void setLayerOffsetContinuous(String eventId, String layerId, double offsetMs) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(offsetMs: offsetMs.clamp(0, 10000)));
  }

  /// Set layer offset (with undo - use for final value)
  void setLayerOffset(String eventId, String layerId, double offsetMs) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(offsetMs: offsetMs.clamp(0, 10000)));
  }

  /// Set layer fade in/out times
  void setLayerFade(String eventId, String layerId, double fadeInMs, double fadeOutMs) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(
        eventId,
        layer.copyWith(
          fadeInMs: fadeInMs.clamp(0, 10000),
          fadeOutMs: fadeOutMs.clamp(0, 10000),
        ));
  }

  /// Reorder layers in event
  void reorderEventLayers(String eventId, int oldIndex, int newIndex) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();

    final layers = List<SlotEventLayer>.from(event.layers);
    if (oldIndex < newIndex) newIndex--;
    final layer = layers.removeAt(oldIndex);
    layers.insert(newIndex, layer);

    final updated = event.copyWith(
      layers: layers,
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Push current state to undo stack before making changes
  void _pushUndoState() {
    final snapshot = <String, SlotCompositeEvent>{};
    for (final entry in _compositeEvents.entries) {
      snapshot[entry.key] = entry.value.copyWith(
        layers: List<SlotEventLayer>.from(entry.value.layers),
      );
    }
    _undoStack.add(snapshot);

    while (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }

    _redoStack.clear();
  }

  /// Undo last composite event change
  void undoCompositeEvents() {
    if (_undoStack.isEmpty) return;

    final currentSnapshot = <String, SlotCompositeEvent>{};
    for (final entry in _compositeEvents.entries) {
      currentSnapshot[entry.key] = entry.value.copyWith(
        layers: List<SlotEventLayer>.from(entry.value.layers),
      );
    }
    _redoStack.add(currentSnapshot);

    final previousState = _undoStack.removeLast();
    _compositeEvents.clear();
    _compositeEvents.addAll(previousState);

    if (_selectedCompositeEventId != null &&
        !_compositeEvents.containsKey(_selectedCompositeEventId)) {
      _selectedCompositeEventId = _compositeEvents.keys.firstOrNull;
    }

    for (final event in _compositeEvents.values) {
      _syncCompositeToMiddleware(event);
    }

    notifyListeners();
  }

  /// Redo previously undone change
  void redoCompositeEvents() {
    if (_redoStack.isEmpty) return;

    final currentSnapshot = <String, SlotCompositeEvent>{};
    for (final entry in _compositeEvents.entries) {
      currentSnapshot[entry.key] = entry.value.copyWith(
        layers: List<SlotEventLayer>.from(entry.value.layers),
      );
    }
    _undoStack.add(currentSnapshot);

    final redoState = _redoStack.removeLast();
    _compositeEvents.clear();
    _compositeEvents.addAll(redoState);

    if (_selectedCompositeEventId != null &&
        !_compositeEvents.containsKey(_selectedCompositeEventId)) {
      _selectedCompositeEventId = _compositeEvents.keys.firstOrNull;
    }

    for (final event in _compositeEvents.values) {
      _syncCompositeToMiddleware(event);
    }

    notifyListeners();
  }

  /// Clear undo/redo history
  void clearUndoHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER SELECTION & CLIPBOARD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select a layer for clipboard operations
  void selectLayer(String? layerId) {
    _selectedLayerId = layerId;
    _selectedLayerIds.clear();
    if (layerId != null) {
      _selectedLayerIds.add(layerId);
    }
    notifyListeners();
  }

  /// Add layer to multi-selection (Cmd/Ctrl+click)
  void toggleLayerSelection(String layerId) {
    if (_selectedLayerIds.contains(layerId)) {
      _selectedLayerIds.remove(layerId);
      _selectedLayerId = _selectedLayerIds.isNotEmpty ? _selectedLayerIds.last : null;
    } else {
      _selectedLayerIds.add(layerId);
      _selectedLayerId = layerId;
    }
    notifyListeners();
  }

  /// Range selection (Shift+click)
  void selectLayerRange(String eventId, String fromLayerId, String toLayerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    final layers = event.layers;
    final fromIndex = layers.indexWhere((l) => l.id == fromLayerId);
    final toIndex = layers.indexWhere((l) => l.id == toLayerId);

    if (fromIndex < 0 || toIndex < 0) return;

    final start = fromIndex < toIndex ? fromIndex : toIndex;
    final end = fromIndex < toIndex ? toIndex : fromIndex;

    for (int i = start; i <= end; i++) {
      _selectedLayerIds.add(layers[i].id);
    }
    _selectedLayerId = toLayerId;
    notifyListeners();
  }

  /// Select all layers in event
  void selectAllLayers(String eventId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    _selectedLayerIds.clear();
    for (final layer in event.layers) {
      _selectedLayerIds.add(layer.id);
    }
    _selectedLayerId = event.layers.isNotEmpty ? event.layers.last.id : null;
    notifyListeners();
  }

  /// Clear multi-selection
  void clearLayerSelection() {
    _selectedLayerIds.clear();
    _selectedLayerId = null;
    notifyListeners();
  }

  /// Check if layer is selected
  bool isLayerSelected(String layerId) => _selectedLayerIds.contains(layerId);

  /// Copy selected layer to clipboard
  void copyLayer(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    try {
      final layer = event.layers.firstWhere((l) => l.id == layerId);
      _layerClipboard = layer;
      _selectedLayerId = layerId;
      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  /// Paste layer from clipboard to event
  SlotEventLayer? pasteLayer(String eventId) {
    if (_layerClipboard == null) return null;
    final event = _compositeEvents[eventId];
    if (event == null) return null;

    _pushUndoState();

    final newId = 'layer_${_nextLayerId++}';
    final pastedLayer = _layerClipboard!.copyWith(
      id: newId,
      name: '${_layerClipboard!.name} (copy)',
    );

    final updated = event.copyWith(
      layers: [...event.layers, pastedLayer],
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();

    return pastedLayer;
  }

  /// Duplicate a layer within the same event
  SlotEventLayer? duplicateLayer(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return null;

    try {
      final layer = event.layers.firstWhere((l) => l.id == layerId);
      _pushUndoState();

      final newId = 'layer_${_nextLayerId++}';
      final duplicatedLayer = layer.copyWith(
        id: newId,
        name: '${layer.name} (copy)',
        offsetMs: layer.offsetMs + 100,
      );

      final updated = event.copyWith(
        layers: [...event.layers, duplicatedLayer],
        modifiedAt: DateTime.now(),
      );
      _compositeEvents[eventId] = updated;
      _syncCompositeToMiddleware(updated);
      notifyListeners();

      return duplicatedLayer;
    } catch (e) {
      return null;
    }
  }

  /// Clear clipboard (both single and multi-layer)
  void clearClipboard() {
    _layerClipboard = null;
    _layersClipboard.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS FOR MULTI-SELECT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Delete all selected layers
  void deleteSelectedLayers(String eventId) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.where((l) => !_selectedLayerIds.contains(l.id)).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    _selectedLayerIds.clear();
    _selectedLayerId = null;
    notifyListeners();
  }

  /// Mute/unmute all selected layers
  void muteSelectedLayers(String eventId, bool mute) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      if (_selectedLayerIds.contains(l.id)) {
        return l.copyWith(muted: mute);
      }
      return l;
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Solo selected layers (mute all others)
  void soloSelectedLayers(String eventId, bool solo) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      final isSelected = _selectedLayerIds.contains(l.id);
      if (solo) {
        return l.copyWith(muted: !isSelected);
      } else {
        return l.copyWith(muted: false);
      }
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Copy all selected layers to clipboard
  void copySelectedLayers(String eventId) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    // Copy selected layers to multi-layer clipboard
    _layersClipboard = event.layers
        .where((l) => _selectedLayerIds.contains(l.id))
        .toList();

    notifyListeners();
  }

  /// Paste all layers from clipboard to event
  List<SlotEventLayer> pasteSelectedLayers(String eventId) {
    if (_layersClipboard.isEmpty) return [];

    final event = _compositeEvents[eventId];
    if (event == null) return [];

    _pushUndoState();

    final pastedLayers = <SlotEventLayer>[];

    for (final layer in _layersClipboard) {
      final newId = 'layer_${_nextLayerId++}';
      final pastedLayer = layer.copyWith(
        id: newId,
        name: '${layer.name} (copy)',
        // Offset each pasted layer slightly to make them visible
        offsetMs: layer.offsetMs + (pastedLayers.length * 50),
      );
      pastedLayers.add(pastedLayer);
    }

    final updated = event.copyWith(
      layers: [...event.layers, ...pastedLayers],
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();

    return pastedLayers;
  }

  /// Adjust volume for all selected layers
  void adjustSelectedLayersVolume(String eventId, double volumeDelta) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      if (_selectedLayerIds.contains(l.id)) {
        return l.copyWith(
          // P1.2 FIX: Clamp to 1.0 max (was 2.0 which causes clipping/distortion)
          volume: (l.volume + volumeDelta).clamp(0.0, 1.0),
        );
      }
      return l;
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Move all selected layers by offset
  void moveSelectedLayers(String eventId, double offsetDeltaMs) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      if (_selectedLayerIds.contains(l.id)) {
        return l.copyWith(
          offsetMs: (l.offsetMs + offsetDeltaMs).clamp(0.0, double.infinity),
        );
      }
      return l;
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Duplicate all selected layers
  List<SlotEventLayer> duplicateSelectedLayers(String eventId) {
    if (_selectedLayerIds.isEmpty) return [];

    final event = _compositeEvents[eventId];
    if (event == null) return [];

    _pushUndoState();

    final newLayers = <SlotEventLayer>[];
    final layersToDuplicate = event.layers.where((l) => _selectedLayerIds.contains(l.id)).toList();

    for (final layer in layersToDuplicate) {
      final newId = 'layer_${_nextLayerId++}';
      final duplicated = layer.copyWith(
        id: newId,
        name: '${layer.name} (copy)',
        offsetMs: layer.offsetMs + 100,
      );
      newLayers.add(duplicated);
    }

    final updated = event.copyWith(
      layers: [...event.layers, ...newLayers],
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();

    return newLayers;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REAL-TIME SYNC: SlotCompositeEvent ↔ MiddlewareEvent
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert composite event ID to middleware event ID
  String _compositeToMiddlewareId(String compositeId) => 'mw_$compositeId';

  /// Convert middleware event ID to composite event ID
  String? _middlewareToCompositeId(String middlewareId) {
    if (middlewareId.startsWith('mw_event_')) {
      return middlewareId.substring(3);
    }
    return null;
  }

  /// Sync SlotCompositeEvent to MiddlewareEvent (real-time)
  void _syncCompositeToMiddleware(SlotCompositeEvent composite) {
    final middlewareId = _compositeToMiddlewareId(composite.id);

    final actions = <MiddlewareAction>[];
    int actionIndex = 0;

    for (final layer in composite.layers) {
      if (layer.muted) continue;
      if (composite.hasSoloedLayer && !layer.solo) continue;

      actions.add(MiddlewareAction(
        id: '${middlewareId}_action_${actionIndex++}',
        type: ActionType.play,
        assetId: layer.audioPath,
        bus: _getBusNameForCategory(composite.category),
        gain: layer.volume * composite.masterVolume,
        pan: layer.pan,
        delay: layer.offsetMs / 1000.0,
        fadeTime: layer.fadeInMs / 1000.0,
        loop: composite.looping,
        priority: ActionPriority.normal,
      ));
    }

    final middlewareEvent = MiddlewareEvent(
      id: middlewareId,
      name: composite.name,
      category: 'Slot_${_capitalizeCategory(composite.category)}',
      actions: actions,
    );

    _eventSystemProvider.importEvent(middlewareEvent);

    _notifyCompositeChange(composite.id, CompositeEventChangeType.updated);
  }

  /// Remove MiddlewareEvent when composite is deleted
  void _removeMiddlewareEventForComposite(String compositeId) {
    final middlewareId = _compositeToMiddlewareId(compositeId);
    _eventSystemProvider.deleteEvent(middlewareId);

    _notifyCompositeChange(compositeId, CompositeEventChangeType.deleted);
  }

  /// Sync MiddlewareEvent back to SlotCompositeEvent (bidirectional)
  void syncMiddlewareToComposite(String middlewareId) {

    final compositeId = _middlewareToCompositeId(middlewareId);
    if (compositeId == null) {
      return;
    }

    final middlewareEvent = _eventSystemProvider.getEvent(middlewareId);
    final composite = _compositeEvents[compositeId];
    if (middlewareEvent == null || composite == null) {
      return;
    }

    final updatedLayers = <SlotEventLayer>[];

    for (int i = 0; i < composite.layers.length && i < middlewareEvent.actions.length; i++) {
      final action = middlewareEvent.actions[i];
      final layer = composite.layers[i];

      updatedLayers.add(layer.copyWith(
        volume: action.gain,
        pan: action.pan,
        offsetMs: action.delay * 1000.0,
        fadeInMs: action.fadeTime * 1000.0,
      ));
    }

    if (composite.layers.length > middlewareEvent.actions.length) {
      updatedLayers.addAll(composite.layers.skip(middlewareEvent.actions.length));
    }

    _compositeEvents[compositeId] = composite.copyWith(
      name: middlewareEvent.name,
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    // Log synced pan values
    for (int i = 0; i < updatedLayers.length; i++) {
    }
    notifyListeners();
  }

  /// Get bus name for event category
  String _getBusNameForCategory(String category) {
    return switch (category.toLowerCase()) {
      'spin' => 'Reels',
      'reelstop' => 'Reels',
      'anticipation' => 'SFX',
      'win' => 'Wins',
      'bigwin' => 'Wins',
      'feature' => 'Music',
      'bonus' => 'Music',
      'ui' => 'UI',
      'ambient' => 'Ambience',
      'music' => 'Music',
      _ => 'SFX',
    };
  }

  /// Capitalize category for middleware naming
  String _capitalizeCategory(String category) {
    if (category.isEmpty) return 'General';
    return category[0].toUpperCase() + category.substring(1);
  }

  /// Check if a middleware event is linked to a composite event
  bool isLinkedToComposite(String middlewareId) {
    return middlewareId.startsWith('mw_event_');
  }

  /// Get composite event for a middleware event
  SlotCompositeEvent? getCompositeForMiddleware(String middlewareId) {
    final compositeId = _middlewareToCompositeId(middlewareId);
    if (compositeId == null) return null;
    return _compositeEvents[compositeId];
  }

  /// Expand composite event to timeline clips
  List<Map<String, dynamic>> expandEventToTimelineClips(
    String compositeEventId, {
    required double startPositionNormalized,
    required double timelineWidth,
  }) {
    final event = _compositeEvents[compositeEventId];
    if (event == null) return [];

    final clips = <Map<String, dynamic>>[];
    final totalDuration = event.totalDurationMs;
    if (totalDuration <= 0) return [];

    for (final layer in event.playableLayers) {
      final layerDuration = (layer.durationSeconds ?? 1.0) * 1000;
      final offsetRatio = layer.offsetMs / totalDuration;
      final durationRatio = layerDuration / totalDuration;

      final clipStart = startPositionNormalized + (offsetRatio * 0.2);
      final clipEnd = clipStart + (durationRatio * 0.2);

      clips.add({
        'layerId': layer.id,
        'name': layer.name,
        'path': layer.audioPath,
        'start': clipStart.clamp(0.0, 1.0),
        'end': clipEnd.clamp(0.0, 1.0),
        'volume': layer.volume,
        'pan': layer.pan,
        'offsetMs': layer.offsetMs,
        'durationSeconds': layer.durationSeconds,
        'waveformData': layer.waveformData,
        'eventId': compositeEventId,
        'eventName': event.name,
        'eventColor': event.color,
        'bus': _getBusNameForCategory(event.category),
      });
    }

    return clips;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT/EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all composite events to JSON
  Map<String, dynamic> exportCompositeEventsToJson() {
    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'compositeEvents': _compositeEvents.values.map((e) => e.toJson()).toList(),
    };
  }

  /// Import composite events from JSON
  /// P1.3 FIX: Added comprehensive validation before importing
  void importCompositeEventsFromJson(Map<String, dynamic> json) {
    // Validate version
    final version = json['version'] as int?;
    if (version == null || version < 1) {
      return;
    }
    if (version > 1) {
    }

    // Validate events array exists and is a list
    final events = json['compositeEvents'];
    if (events == null) {
      return;
    }
    if (events is! List) {
      return;
    }

    // Validate each event before importing
    final validEvents = <SlotCompositeEvent>[];
    int skippedCount = 0;

    for (final eventJson in events) {
      if (eventJson is! Map<String, dynamic>) {
        skippedCount++;
        continue;
      }

      if (!_validateEventJson(eventJson)) {
        skippedCount++;
        continue;
      }

      try {
        final event = SlotCompositeEvent.fromJson(eventJson);
        // Additional validation: check layers have valid audio paths
        final validatedEvent = _validateEventLayers(event);
        validEvents.add(validatedEvent);
      } catch (e) {
        skippedCount++;
      }
    }

    // Only apply if we have valid events (or empty import is intentional)
    if (validEvents.isEmpty && events.isNotEmpty) {
      return;
    }

    // Clear and import
    _compositeEvents.clear();
    for (final event in validEvents) {
      _compositeEvents[event.id] = event;
      _syncCompositeToMiddleware(event);
    }

    notifyListeners();
  }

  /// Validate event JSON structure before parsing
  bool _validateEventJson(Map<String, dynamic> json) {
    // Required fields
    if (json['id'] is! String || (json['id'] as String).isEmpty) {
      return false;
    }
    if (json['name'] is! String) {
      return false;
    }

    // Validate layers if present
    final layers = json['layers'];
    if (layers != null) {
      if (layers is! List) {
        return false;
      }
      // Check each layer has required fields
      for (final layer in layers) {
        if (layer is! Map<String, dynamic>) continue;
        if (layer['id'] is! String) return false;
        if (layer['audioPath'] is! String) return false;
      }
    }

    // Validate triggerStages if present
    final stages = json['triggerStages'];
    if (stages != null && stages is! List) {
      return false;
    }

    return true;
  }

  /// Validate and sanitize event layers (remove layers with invalid paths)
  SlotCompositeEvent _validateEventLayers(SlotCompositeEvent event) {
    final validLayers = event.layers.where((layer) {
      // Allow empty paths (placeholder layers)
      if (layer.audioPath.isEmpty) return true;
      // Validate non-empty paths
      return _validateAudioPath(layer.audioPath);
    }).toList();

    if (validLayers.length != event.layers.length) {
    }

    return event.copyWith(layers: validLayers);
  }

  /// Get all composite events as JSON string
  String exportCompositeEventsToJsonString() {
    final json = exportCompositeEventsToJson();
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Import composite events from JSON string
  void importCompositeEventsFromJsonString(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      importCompositeEventsFromJson(json);
    } catch (e) { /* ignored */ }
  }

  /// Clear all composite events
  void clearAllCompositeEvents() {
    for (final event in _compositeEvents.values) {
      _removeMiddlewareEventForComposite(event.id);
    }
    _compositeEvents.clear();
    notifyListeners();
  }

  /// Initialize default composite events from templates
  void initializeDefaultCompositeEvents() {
    if (_compositeEvents.isNotEmpty) return;

    for (final template in SlotEventTemplates.allTemplates()) {
      final id =
          'event_${template.name.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}';
      final event = template.copyWith(
        id: id,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      _compositeEvents[id] = event;
      _syncCompositeToMiddleware(event);
    }
    _selectedCompositeEventId = _compositeEvents.keys.first;
    notifyListeners();
  }

  /// Clear all state
  void clear() {
    _compositeEvents.clear();
    _undoStack.clear();
    _redoStack.clear();
    _layerClipboard = null;
    _selectedLayerId = null;
    _selectedLayerIds.clear();
    _selectedCompositeEventId = null;
    _nextLayerId = 1;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE TRIGGER MAPPING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set trigger stages for a composite event
  void setTriggerStages(String eventId, List<String> stages) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerStages: stages,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Add a trigger stage to a composite event
  void addTriggerStage(String eventId, String stageType) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    if (event.triggerStages.contains(stageType)) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerStages: [...event.triggerStages, stageType],
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Remove a trigger stage from a composite event
  void removeTriggerStage(String eventId, String stageType) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    if (!event.triggerStages.contains(stageType)) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerStages: event.triggerStages.where((s) => s != stageType).toList(),
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Set trigger conditions for a composite event
  void setTriggerConditions(String eventId, Map<String, String> conditions) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerConditions: conditions,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Add a trigger condition
  void addTriggerCondition(String eventId, String rtpcName, String condition) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final newConditions = Map<String, String>.from(event.triggerConditions);
    newConditions[rtpcName] = condition;
    _compositeEvents[eventId] = event.copyWith(
      triggerConditions: newConditions,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Remove a trigger condition
  void removeTriggerCondition(String eventId, String rtpcName) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    if (!event.triggerConditions.containsKey(rtpcName)) return;
    _pushUndoState();
    final newConditions = Map<String, String>.from(event.triggerConditions);
    newConditions.remove(rtpcName);
    _compositeEvents[eventId] = event.copyWith(
      triggerConditions: newConditions,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Find all composite events that should trigger for a given stage type
  List<SlotCompositeEvent> getEventsForStage(String stageType) {
    return _compositeEvents.values
        .where((e) => e.triggerStages.contains(stageType))
        .toList();
  }

  /// Find all composite events that match stage + conditions
  List<SlotCompositeEvent> getEventsForStageWithConditions(
    String stageType,
    Map<String, double> rtpcValues,
  ) {
    return _compositeEvents.values.where((e) {
      // Must have this stage as trigger
      if (!e.triggerStages.contains(stageType)) return false;

      // Check all conditions
      for (final entry in e.triggerConditions.entries) {
        final rtpcName = entry.key;
        final condition = entry.value;
        final value = rtpcValues[rtpcName];
        if (value == null) return false;

        // Parse condition (e.g., ">= 10", "< 5", "== 1")
        if (!_evaluateCondition(value, condition)) return false;
      }

      return true;
    }).toList();
  }

  /// Evaluate a condition string against a value
  bool _evaluateCondition(double value, String condition) {
    final parts = condition.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return false;

    final op = parts[0];
    final target = double.tryParse(parts[1]);
    if (target == null) return false;

    return switch (op) {
      '>=' => value >= target,
      '>' => value > target,
      '<=' => value <= target,
      '<' => value < target,
      '==' => (value - target).abs() < 0.001,
      '!=' => (value - target).abs() >= 0.001,
      _ => false,
    };
  }

  /// Get all stages that have at least one event mapped
  List<String> get mappedStages {
    final stages = <String>{};
    for (final event in _compositeEvents.values) {
      stages.addAll(event.triggerStages);
    }
    return stages.toList()..sort();
  }

  /// Get event count per stage (for visualization)
  Map<String, int> get stageEventCounts {
    final counts = <String, int>{};
    for (final event in _compositeEvents.values) {
      for (final stage in event.triggerStages) {
        counts[stage] = (counts[stage] ?? 0) + 1;
      }
    }
    return counts;
  }
}

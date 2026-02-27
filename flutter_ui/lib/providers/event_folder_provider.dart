/// Event Folder Provider — DAW-side view of SlotLab composite events
///
/// Listens to CompositeEventSystemProvider and projects events as
/// read-only EventFolder instances for the DAW left panel.
///
/// Structure ownership: SlotLab → DAW (one-way, read-only)
/// Audio params: bidirectional (same rf-engine, same TrackProvider)
///
/// See: .claude/architecture/UNIFIED_TRACK_GRAPH.md
library;

import 'package:flutter/foundation.dart';
import '../models/event_folder_models.dart';
import 'subsystems/composite_event_system_provider.dart';

class EventFolderProvider extends ChangeNotifier {
  final CompositeEventSystemProvider _compositeProvider;

  /// Internal folder state, keyed by event ID
  final Map<String, EventFolder> _folders = {};

  /// Track which layers are placed in the DAW timeline
  final Map<String, int> _layerToTrackId = {};

  EventFolderProvider({
    required CompositeEventSystemProvider compositeProvider,
  }) : _compositeProvider = compositeProvider {
    // Listen for composite event changes and rebuild folders
    _compositeProvider.addListener(_onCompositeEventsChanged);
    // Initial sync
    _syncFromCompositeEvents();
  }

  @override
  void dispose() {
    _compositeProvider.removeListener(_onCompositeEventsChanged);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API — Read-only for DAW
  // ═══════════════════════════════════════════════════════════════════════════

  /// All event folders for DAW left panel display
  List<EventFolder> get folders => _folders.values.toList();

  /// Get folder by event ID
  EventFolder? getFolder(String eventId) => _folders[eventId];

  /// Get folders by category
  List<EventFolder> getFoldersByCategory(String category) =>
      _folders.values.where((f) => f.category == category).toList();

  /// Number of event folders
  int get folderCount => _folders.length;

  /// All unique categories present
  List<String> get categories =>
      _folders.values.map((f) => f.category).toSet().toList()..sort();

  // ═══════════════════════════════════════════════════════════════════════════
  // DAW TIMELINE PLACEMENT — user drags layers into timeline
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mark a layer as placed in the DAW timeline with a track ID
  void placeLayerInTimeline(String layerId, int dawTrackId) {
    _layerToTrackId[layerId] = dawTrackId;
    _rebuildFolderStates();
    notifyListeners();
  }

  /// Remove a layer from the DAW timeline
  void removeLayerFromTimeline(String layerId) {
    _layerToTrackId.remove(layerId);
    _rebuildFolderStates();
    notifyListeners();
  }

  /// Check if a layer is placed in the timeline
  bool isLayerInTimeline(String layerId) =>
      _layerToTrackId.containsKey(layerId);

  /// Get DAW track ID for a placed layer
  int? getTrackIdForLayer(String layerId) => _layerToTrackId[layerId];

  // ═══════════════════════════════════════════════════════════════════════════
  // UI STATE — collapse/expand
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle folder collapse state
  void toggleFolderCollapsed(String eventId) {
    final folder = _folders[eventId];
    if (folder == null) return;
    _folders[eventId] = folder.copyWith(isCollapsed: !folder.isCollapsed);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL — Sync from CompositeEventSystemProvider
  // ═══════════════════════════════════════════════════════════════════════════

  void _onCompositeEventsChanged() {
    _syncFromCompositeEvents();
  }

  void _syncFromCompositeEvents() {
    final compositeEvents = _compositeProvider.compositeEvents;
    final newIds = <String>{};

    for (final event in compositeEvents) {
      newIds.add(event.id);

      final existingFolder = _folders[event.id];
      final layers = event.layers.map((layer) {
        final isInTimeline = _layerToTrackId.containsKey(layer.id);
        return EventLayerRef(
          layerId: layer.id,
          name: layer.name,
          audioPath: layer.audioPath,
          volume: layer.volume,
          pan: layer.pan,
          muted: layer.muted,
          solo: layer.solo,
          loop: layer.loop,
          isInTimeline: isInTimeline,
          dawTrackId: _layerToTrackId[layer.id],
        );
      }).toList();

      final hasAnyInTimeline = layers.any((l) => l.isInTimeline);

      _folders[event.id] = EventFolder(
        id: 'folder_${event.id}',
        eventId: event.id,
        name: event.name,
        category: event.category,
        color: EventCategoryColors.forCategory(event.category),
        layers: layers,
        isCollapsed: existingFolder?.isCollapsed ?? false,
        hasLayersInTimeline: hasAnyInTimeline,
      );
    }

    // Remove folders for deleted events
    _folders.removeWhere((key, _) => !newIds.contains(key));

    // Clean up layer-to-track mappings for layers that no longer exist
    final allLayerIds = <String>{};
    for (final event in compositeEvents) {
      for (final layer in event.layers) {
        allLayerIds.add(layer.id);
      }
    }
    _layerToTrackId.removeWhere((key, _) => !allLayerIds.contains(key));

    notifyListeners();
  }

  void _rebuildFolderStates() {
    for (final entry in _folders.entries) {
      final folder = entry.value;
      final updatedLayers = folder.layers.map((layer) {
        final isInTimeline = _layerToTrackId.containsKey(layer.layerId);
        return layer.copyWith(
          isInTimeline: isInTimeline,
          dawTrackId: _layerToTrackId[layer.layerId],
        );
      }).toList();
      final hasAnyInTimeline = updatedLayers.any((l) => l.isInTimeline);
      _folders[entry.key] = folder.copyWith(
        layers: updatedLayers,
        hasLayersInTimeline: hasAnyInTimeline,
      );
    }
  }
}

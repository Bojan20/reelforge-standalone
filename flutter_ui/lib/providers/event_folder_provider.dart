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

  /// Reverse mapping: DAW trackId → layerId (for bidirectional sync)
  final Map<int, String> _trackIdToLayerId = {};

  /// Reverse mapping: layerId → eventId (for reverse lookup)
  final Map<String, String> _layerToEventId = {};

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
    _trackIdToLayerId[dawTrackId] = layerId;
    _rebuildFolderStates();
    notifyListeners();
  }

  /// Remove a layer from the DAW timeline
  void removeLayerFromTimeline(String layerId) {
    final trackId = _layerToTrackId.remove(layerId);
    if (trackId != null) _trackIdToLayerId.remove(trackId);
    _rebuildFolderStates();
    notifyListeners();
  }

  /// Check if a layer is placed in the timeline
  bool isLayerInTimeline(String layerId) =>
      _layerToTrackId.containsKey(layerId);

  /// Get DAW track ID for a placed layer
  int? getTrackIdForLayer(String layerId) => _layerToTrackId[layerId];

  /// Get layer ID for a DAW track (reverse lookup for bidirectional sync)
  String? getLayerIdForTrack(int dawTrackId) => _trackIdToLayerId[dawTrackId];

  /// Get event ID for a layer (reverse lookup)
  String? getEventIdForLayer(String layerId) => _layerToEventId[layerId];

  /// Check if a DAW track is linked to a SlotLab layer
  bool isLinkedTrack(int dawTrackId) => _trackIdToLayerId.containsKey(dawTrackId);

  // ═══════════════════════════════════════════════════════════════════════════
  // BIDIRECTIONAL SYNC — DAW changes → SlotLab layer params
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync volume change from DAW mixer back to SlotLab layer
  void syncVolumeFromDaw(int dawTrackId, double volume) {
    final layerId = _trackIdToLayerId[dawTrackId];
    if (layerId == null) return;
    final eventId = _layerToEventId[layerId];
    if (eventId == null) return;
    _compositeProvider.setLayerVolumeContinuous(eventId, layerId, volume);
  }

  /// Sync volume change (final, with undo) from DAW mixer back to SlotLab
  void syncVolumeFinalFromDaw(int dawTrackId, double volume) {
    final layerId = _trackIdToLayerId[dawTrackId];
    if (layerId == null) return;
    final eventId = _layerToEventId[layerId];
    if (eventId == null) return;
    _compositeProvider.setLayerVolume(eventId, layerId, volume);
  }

  /// Sync pan change from DAW mixer back to SlotLab layer
  void syncPanFromDaw(int dawTrackId, double pan) {
    final layerId = _trackIdToLayerId[dawTrackId];
    if (layerId == null) return;
    final eventId = _layerToEventId[layerId];
    if (eventId == null) return;
    _compositeProvider.setLayerPanContinuous(eventId, layerId, pan);
  }

  /// Sync pan change (final, with undo) from DAW mixer back to SlotLab
  void syncPanFinalFromDaw(int dawTrackId, double pan) {
    final layerId = _trackIdToLayerId[dawTrackId];
    if (layerId == null) return;
    final eventId = _layerToEventId[layerId];
    if (eventId == null) return;
    _compositeProvider.setLayerPan(eventId, layerId, pan);
  }

  /// Sync mute toggle from DAW mixer back to SlotLab layer
  void syncMuteFromDaw(int dawTrackId) {
    final layerId = _trackIdToLayerId[dawTrackId];
    if (layerId == null) return;
    final eventId = _layerToEventId[layerId];
    if (eventId == null) return;
    _compositeProvider.toggleLayerMute(eventId, layerId);
  }

  /// Sync solo toggle from DAW mixer back to SlotLab layer
  void syncSoloFromDaw(int dawTrackId) {
    final layerId = _trackIdToLayerId[dawTrackId];
    if (layerId == null) return;
    final eventId = _layerToEventId[layerId];
    if (eventId == null) return;
    _compositeProvider.toggleLayerSolo(eventId, layerId);
  }

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
  // CROSSFADE SETTINGS — per-event folder (5.5)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update crossfade settings for an event folder
  void setCrossfade(String eventId, CrossfadeSettings settings) {
    final folder = _folders[eventId];
    if (folder == null) return;
    _folders[eventId] = folder.copyWith(crossfade: settings);
    notifyListeners();
  }

  /// Update fade-in duration
  void setFadeIn(String eventId, double ms) {
    final folder = _folders[eventId];
    if (folder == null) return;
    _folders[eventId] = folder.copyWith(
      crossfade: folder.crossfade.copyWith(fadeInMs: ms),
    );
    notifyListeners();
  }

  /// Update fade-out duration
  void setFadeOut(String eventId, double ms) {
    final folder = _folders[eventId];
    if (folder == null) return;
    _folders[eventId] = folder.copyWith(
      crossfade: folder.crossfade.copyWith(fadeOutMs: ms),
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VARIANT GROUPS — A/B/C sub-groups within event (5.3)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get variant groups for an event
  List<VariantGroup> getVariantGroups(String eventId) =>
      _folders[eventId]?.variantGroups ?? [];

  /// Get layers belonging to a specific variant
  List<EventLayerRef> getLayersForVariant(String eventId, String groupId) =>
      _folders[eventId]?.layersForVariant(groupId) ?? [];

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK REUSE QUERIES — shared tracks across events (5.1/5.2)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all event IDs that share a specific audio path
  List<String> getEventsForAudioPath(String audioPath) {
    final eventIds = <String>[];
    for (final folder in _folders.values) {
      if (folder.layers.any((l) => l.audioPath == audioPath)) {
        eventIds.add(folder.eventId);
      }
    }
    return eventIds;
  }

  /// Count how many events use a specific audio path
  int getSharedCount(String audioPath) => getEventsForAudioPath(audioPath).length;

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL — Sync from CompositeEventSystemProvider
  // ═══════════════════════════════════════════════════════════════════════════

  void _onCompositeEventsChanged() {
    _syncFromCompositeEvents();
  }

  void _syncFromCompositeEvents() {
    final compositeEvents = _compositeProvider.compositeEvents;
    final newIds = <String>{};

    // Rebuild layer→event reverse mapping
    _layerToEventId.clear();

    // Phase 5.1: Build audioPath → eventIds map for shared track detection
    final audioPathToEvents = <String, List<String>>{};
    for (final event in compositeEvents) {
      for (final layer in event.layers) {
        if (layer.audioPath.isNotEmpty) {
          audioPathToEvents.putIfAbsent(layer.audioPath, () => []).add(event.id);
        }
      }
    }

    for (final event in compositeEvents) {
      newIds.add(event.id);

      final existingFolder = _folders[event.id];

      // Phase 5.3: Build variant groups from layer metadata
      final variantMap = <String, List<String>>{};

      final layers = event.layers.map((layer) {
        // Maintain reverse mapping for bidirectional sync
        _layerToEventId[layer.id] = event.id;

        final isInTimeline = _layerToTrackId.containsKey(layer.id);

        // Phase 5.1: Determine shared event IDs for this layer's audio
        final sharedEvents = layer.audioPath.isNotEmpty
            ? (audioPathToEvents[layer.audioPath] ?? [])
            : <String>[];

        // Phase 5.3: Track variant group membership
        if (layer.variantGroup != null) {
          variantMap.putIfAbsent(layer.variantGroup!, () => []).add(layer.id);
        }

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
          sharedEventIds: sharedEvents,
          variantGroup: layer.variantGroup,
          variantWeight: layer.variantWeight,
          minMultiplier: layer.minMultiplier,
          betThreshold: layer.betThreshold,
        );
      }).toList();

      final hasAnyInTimeline = layers.any((l) => l.isInTimeline);

      // Phase 5.3: Convert variant map to VariantGroup objects
      final variantGroups = variantMap.entries.map((e) =>
        VariantGroup(id: e.key, name: e.key, layerIds: e.value),
      ).toList();

      _folders[event.id] = EventFolder(
        id: 'folder_${event.id}',
        eventId: event.id,
        name: event.name,
        category: event.category,
        color: EventCategoryColors.forCategory(event.category),
        layers: layers,
        isCollapsed: existingFolder?.isCollapsed ?? false,
        hasLayersInTimeline: hasAnyInTimeline,
        crossfade: existingFolder?.crossfade ?? const CrossfadeSettings(),
        variantGroups: variantGroups,
      );
    }

    // Remove folders for deleted events
    _folders.removeWhere((key, _) => !newIds.contains(key));

    // Clean up layer-to-track mappings for layers that no longer exist
    final allLayerIds = _layerToEventId.keys.toSet();
    _layerToTrackId.removeWhere((key, _) => !allLayerIds.contains(key));
    _trackIdToLayerId.removeWhere((_, v) => !allLayerIds.contains(v));

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

/// Middleware ↔ DAW Bidirectional Event Bridge
///
/// Automatically syncs SlotCompositeEvents to DAW timeline as folder tracks
/// with child audio tracks, clips, and mixer channels. Changes in DAW (volume,
/// pan, mute, solo) sync back to middleware layers in real-time.
///
/// ID Convention (deterministic, double underscore separator):
///   Event folder track: mw_folder_{eventId}
///   Layer audio track:  mw_track_{eventId}__{layerId}
///   Layer clip:         mw_clip_{eventId}__{layerId}
///   Mixer channel:      ch_{engineTrackId}  (via _engineTrackIds mapping)

import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/slot_audio_events.dart';
import '../models/timeline_models.dart' as timeline;
import '../providers/middleware_provider.dart';
import '../providers/mixer_provider.dart';

/// Tracks and clips to add/remove in one batch
class SyncBatch {
  final List<timeline.TimelineTrack> tracksToAdd;
  final List<String> trackIdsToRemove;
  final List<timeline.TimelineClip> clipsToAdd;
  final List<String> clipIdsToRemove;

  const SyncBatch({
    this.tracksToAdd = const [],
    this.trackIdsToRemove = const [],
    this.clipsToAdd = const [],
    this.clipIdsToRemove = const [],
  });

  bool get isEmpty =>
      tracksToAdd.isEmpty &&
      trackIdsToRemove.isEmpty &&
      clipsToAdd.isEmpty &&
      clipIdsToRemove.isEmpty;
}

class MiddlewareTimelineSyncController {
  MiddlewareTimelineSyncController();

  // Dependencies (set via initialize())
  MixerProvider? _mixerProvider;
  MiddlewareProvider? _middlewareProvider;

  // Suppression flags — prevent infinite update loops
  bool _isSyncingToTimeline = false;
  bool _isSyncingToMiddleware = false;

  // Snapshot of last synced state for diffing
  final Map<String, _EventSnapshot> _lastSyncedEvents = {};

  /// Maps mw_track_{eventId}__{layerId} → engine-returned track ID.
  /// Critical for correct deletion of engine tracks and mixer channels.
  final Map<String, String> _engineTrackIds = {};

  // Callback to apply changes to engine_connected_layout state
  void Function(SyncBatch batch)? onSyncBatch;

  // Callback to create/delete engine tracks (needs engine_connected_layout context)
  String Function(String name, Color color, int busId)? onCreateEngineTrack;
  void Function(String trackId)? onDeleteEngineTrack;

  /// Initialize with dependencies. Call once from engine_connected_layout.initState()
  void initialize({
    required MixerProvider mixerProvider,
    required MiddlewareProvider middlewareProvider,
  }) {
    _mixerProvider = mixerProvider;
    _middlewareProvider = middlewareProvider;

    // Listen to middleware changes
    _middlewareProvider!.addListener(_onMiddlewareChanged);
  }

  /// Clean up listeners
  void dispose() {
    _middlewareProvider?.removeListener(_onMiddlewareChanged);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MW → DAW SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when MiddlewareProvider notifies listeners
  void _onMiddlewareChanged() {
    if (_isSyncingToMiddleware) return; // Suppress reverse sync
    if (_middlewareProvider == null) return;

    final currentEvents = _middlewareProvider!.compositeEvents;

    // Build current event map (only events with layers and audio)
    final currentMap = <String, SlotCompositeEvent>{};
    for (final event in currentEvents) {
      if (event.layers.isNotEmpty) {
        currentMap[event.id] = event;
      }
    }

    // Diff against last synced state
    final batch = _diffAndSync(currentMap);
    if (batch != null && !batch.isEmpty) {
      _isSyncingToTimeline = true;
      try {
        onSyncBatch?.call(batch);
        // Only update snapshot AFTER successful batch — if it throws,
        // we keep old snapshot so next cycle retries the diff.
        _lastSyncedEvents.clear();
        for (final entry in currentMap.entries) {
          _lastSyncedEvents[entry.key] = _EventSnapshot.from(entry.value);
        }
      } finally {
        _isSyncingToTimeline = false;
      }
    } else {
      // No changes — still update snapshot for added/removed empty-layer events
      _lastSyncedEvents.clear();
      for (final entry in currentMap.entries) {
        _lastSyncedEvents[entry.key] = _EventSnapshot.from(entry.value);
      }
    }
  }

  /// Diff current events against last synced state and produce a SyncBatch
  SyncBatch? _diffAndSync(Map<String, SlotCompositeEvent> currentMap) {
    final tracksToAdd = <timeline.TimelineTrack>[];
    final trackIdsToRemove = <String>[];
    final clipsToAdd = <timeline.TimelineClip>[];
    final clipIdsToRemove = <String>[];

    final previousIds = _lastSyncedEvents.keys.toSet();
    final currentIds = currentMap.keys.toSet();

    // ── New events ──
    final added = currentIds.difference(previousIds);
    for (final eventId in added) {
      final event = currentMap[eventId]!;
      final result = _createTrackStructureForEvent(event);
      tracksToAdd.addAll(result.tracks);
      clipsToAdd.addAll(result.clips);
    }

    // ── Removed events ──
    final removed = previousIds.difference(currentIds);
    for (final eventId in removed) {
      final result = _removeTrackStructureForEvent(eventId);
      trackIdsToRemove.addAll(result.trackIds);
      clipIdsToRemove.addAll(result.clipIds);
    }

    // ── Changed events (still present in both) ──
    final kept = currentIds.intersection(previousIds);
    for (final eventId in kept) {
      final current = currentMap[eventId]!;
      final previous = _lastSyncedEvents[eventId]!;

      if (!previous.isEqualTo(current)) {
        // Remove old structure, add new one
        final removeResult = _removeTrackStructureForEvent(eventId);
        trackIdsToRemove.addAll(removeResult.trackIds);
        clipIdsToRemove.addAll(removeResult.clipIds);

        final addResult = _createTrackStructureForEvent(current);
        tracksToAdd.addAll(addResult.tracks);
        clipsToAdd.addAll(addResult.clips);
      }
    }

    if (tracksToAdd.isEmpty &&
        trackIdsToRemove.isEmpty &&
        clipsToAdd.isEmpty &&
        clipIdsToRemove.isEmpty) {
      return null;
    }

    return SyncBatch(
      tracksToAdd: tracksToAdd,
      trackIdsToRemove: trackIdsToRemove,
      clipsToAdd: clipsToAdd,
      clipIdsToRemove: clipIdsToRemove,
    );
  }

  /// Create folder + child tracks + clips for an event
  _TrackStructure _createTrackStructureForEvent(SlotCompositeEvent event) {
    final tracks = <timeline.TimelineTrack>[];
    final clips = <timeline.TimelineClip>[];

    final folderId = _folderIdForEvent(event.id);
    final childTrackIds = <String>[];

    // Create child audio tracks + clips for each layer
    for (final layer in event.layers) {
      if (layer.audioPath.isEmpty) continue;

      final trackId = _trackIdForLayer(event.id, layer.id);
      childTrackIds.add(trackId);

      // Create engine track for DSP processing
      final engineTrackId = onCreateEngineTrack?.call(
        layer.name,
        const Color(0xFF9370DB),
        layer.busId ?? 0,
      );

      // Store mapping: mw_track_xxx → engine ID (e.g. "42")
      // Critical for correct deletion of engine tracks and mixer channels
      if (engineTrackId != null) {
        _engineTrackIds[trackId] = engineTrackId;
        _mixerProvider?.createChannelFromTrack(
          engineTrackId,
          layer.name,
          const Color(0xFF9370DB),
        );
      }

      // Audio track
      tracks.add(timeline.TimelineTrack(
        id: trackId,
        name: layer.name,
        color: const Color(0xFF9370DB),
        trackType: timeline.TrackType.audio,
        parentFolderId: folderId,
        indentLevel: 1,
        volume: layer.volume,
        pan: layer.pan,
        muted: layer.muted,
        soloed: layer.solo,
        outputBus: _busIdToOutputBus(layer.busId),
      ));

      // Clip on the track
      final clipId = _clipIdForLayer(event.id, layer.id);
      clips.add(timeline.TimelineClip(
        id: clipId,
        trackId: trackId,
        name: layer.name,
        startTime: layer.offsetMs / 1000.0,
        duration: layer.durationSeconds ?? 1.0,
        sourceFile: layer.audioPath,
        waveform: _convertWaveformData(layer.waveformData),
        fadeIn: layer.fadeInMs / 1000.0,
        fadeOut: layer.fadeOutMs / 1000.0,
        sourceOffset: layer.trimStartMs / 1000.0,
        eventId: event.id,
        loopEnabled: layer.loop,
      ));
    }

    // Folder track (always at position 0, parent of all child tracks)
    final displayName = event.triggerStages.isNotEmpty
        ? event.triggerStages.first
        : event.name;
    tracks.insert(
      0,
      timeline.TimelineTrack(
        id: folderId,
        name: '🎯 $displayName',
        color: const Color(0xFF9370DB),
        trackType: timeline.TrackType.folder,
        folderExpanded: true,
        volume: event.masterVolume,
        childTrackIds: childTrackIds,
      ),
    );

    return _TrackStructure(tracks: tracks, clips: clips);
  }

  /// Remove all tracks/clips/engine resources for an event
  _RemoveResult _removeTrackStructureForEvent(String eventId) {
    final trackIds = <String>[];
    final clipIds = <String>[];
    final previous = _lastSyncedEvents[eventId];

    if (previous != null) {
      for (final layerId in previous.layerIds) {
        final mwTrackId = _trackIdForLayer(eventId, layerId);
        trackIds.add(mwTrackId);
        clipIds.add(_clipIdForLayer(eventId, layerId));

        // Use stored engine track ID for deletion (NOT the mw_track_xxx ID)
        final engineTrackId = _engineTrackIds.remove(mwTrackId);
        if (engineTrackId != null) {
          onDeleteEngineTrack?.call(engineTrackId);
          _mixerProvider?.deleteChannel('ch_$engineTrackId');
        }
      }
    }

    trackIds.add(_folderIdForEvent(eventId));
    return _RemoveResult(trackIds: trackIds, clipIds: clipIds);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DAW → MW SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called from engine_connected_layout when a track parameter changes.
  /// Returns true if the track is a MW-synced track (handled here).
  bool handleTrackParameterChanged(
    String trackId,
    String param,
    dynamic value,
  ) {
    if (_isSyncingToTimeline) return false;
    if (_middlewareProvider == null) return false;

    // Check if this is a MW folder track
    if (trackId.startsWith('mw_folder_')) {
      _handleFolderParameterChanged(trackId, param, value);
      return true;
    }

    // Check if this is a MW layer track
    if (!trackId.startsWith('mw_track_')) return false;

    final parsed = _parseLayerTrackId(trackId);
    if (parsed == null) return false;

    _isSyncingToMiddleware = true;
    try {
      final event = _middlewareProvider!.compositeEvents
          .where((e) => e.id == parsed.eventId)
          .firstOrNull;
      if (event == null) return true;

      final layer = event.layers
          .where((l) => l.id == parsed.layerId)
          .firstOrNull;
      if (layer == null) return true;

      SlotEventLayer? updatedLayer;
      switch (param) {
        case 'volume':
          updatedLayer = layer.copyWith(volume: value as double);
          break;
        case 'pan':
          updatedLayer = layer.copyWith(pan: value as double);
          break;
        case 'mute':
          updatedLayer = layer.copyWith(muted: value as bool);
          break;
        case 'solo':
          updatedLayer = layer.copyWith(solo: value as bool);
          break;
        case 'bus':
          final busEnum = value as timeline.OutputBus;
          updatedLayer = layer.copyWith(busId: _outputBusToBusId(busEnum));
          break;
      }

      if (updatedLayer != null) {
        _middlewareProvider!.updateEventLayer(parsed.eventId, updatedLayer);
      }
    } finally {
      _isSyncingToMiddleware = false;
    }
    return true;
  }

  /// Handle folder track parameter change → event master parameter
  void _handleFolderParameterChanged(
    String folderId,
    String param,
    dynamic value,
  ) {
    final eventId = folderId.replaceFirst('mw_folder_', '');

    _isSyncingToMiddleware = true;
    try {
      final event = _middlewareProvider!.compositeEvents
          .where((e) => e.id == eventId)
          .firstOrNull;
      if (event == null) return;

      switch (param) {
        case 'volume':
          _middlewareProvider!.updateCompositeEvent(
            event.copyWith(masterVolume: value as double),
          );
          break;
        case 'mute':
          // Mute all layers in event
          for (final layer in event.layers) {
            _middlewareProvider!.updateEventLayer(
              eventId,
              layer.copyWith(muted: value as bool),
            );
          }
          break;
      }
    } finally {
      _isSyncingToMiddleware = false;
    }
  }

  /// Check if a track ID belongs to middleware sync system.
  /// Used to protect MW tracks from deletion by the user.
  bool isMwSyncedTrack(String trackId) {
    return trackId.startsWith('mw_folder_') ||
        trackId.startsWith('mw_track_');
  }

  /// Check if a clip ID belongs to middleware sync system.
  bool isMwSyncedClip(String clipId) {
    return clipId.startsWith('mw_clip_');
  }

  /// Called from engine_connected_layout when a clip parameter changes.
  /// Returns true if the clip is a MW-synced clip (handled here).
  bool handleClipParameterChanged(
    String clipId,
    String param,
    dynamic value,
  ) {
    if (_isSyncingToTimeline) return false;
    if (_middlewareProvider == null) return false;
    if (!clipId.startsWith('mw_clip_')) return false;

    final withoutPrefix = clipId.replaceFirst('mw_clip_', '');
    final separatorIndex = withoutPrefix.indexOf('__');
    if (separatorIndex == -1) return false;

    final eventId = withoutPrefix.substring(0, separatorIndex);
    final layerId = withoutPrefix.substring(separatorIndex + 2);
    if (eventId.isEmpty || layerId.isEmpty) return false;

    _isSyncingToMiddleware = true;
    try {
      final event = _middlewareProvider!.compositeEvents
          .where((e) => e.id == eventId)
          .firstOrNull;
      if (event == null) return true;

      final layer = event.layers
          .where((l) => l.id == layerId)
          .firstOrNull;
      if (layer == null) return true;

      SlotEventLayer? updatedLayer;
      switch (param) {
        case 'startTime':
          // Clip position (seconds) → layer offsetMs
          updatedLayer =
              layer.copyWith(offsetMs: (value as double) * 1000.0);
          break;
        case 'fadeIn':
          updatedLayer =
              layer.copyWith(fadeInMs: (value as double) * 1000.0);
          break;
        case 'fadeOut':
          updatedLayer =
              layer.copyWith(fadeOutMs: (value as double) * 1000.0);
          break;
        case 'sourceOffset':
          // Clip slip edit (seconds) → layer trimStartMs
          updatedLayer =
              layer.copyWith(trimStartMs: (value as double) * 1000.0);
          break;
        case 'duration':
          updatedLayer =
              layer.copyWith(durationSeconds: value as double);
          break;
        case 'loop':
          updatedLayer = layer.copyWith(loop: value as bool);
          break;
        case 'mute':
          updatedLayer = layer.copyWith(muted: value as bool);
          break;
      }

      if (updatedLayer != null) {
        _middlewareProvider!.updateEventLayer(eventId, updatedLayer);
      }
    } finally {
      _isSyncingToMiddleware = false;
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ID CONVENTION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static String _folderIdForEvent(String eventId) => 'mw_folder_$eventId';
  static String _trackIdForLayer(String eventId, String layerId) =>
      'mw_track_${eventId}__$layerId';
  static String _clipIdForLayer(String eventId, String layerId) =>
      'mw_clip_${eventId}__$layerId';

  /// Parse a layer track ID back to event/layer IDs.
  /// Uses double underscore (__) as separator between eventId and layerId
  /// since both IDs may contain single underscores.
  static _ParsedLayerTrackId? _parseLayerTrackId(String trackId) {
    final withoutPrefix = trackId.replaceFirst('mw_track_', '');
    final separatorIndex = withoutPrefix.indexOf('__');
    if (separatorIndex == -1) return null;

    final eventId = withoutPrefix.substring(0, separatorIndex);
    final layerId = withoutPrefix.substring(separatorIndex + 2);
    if (eventId.isEmpty || layerId.isEmpty) return null;

    return _ParsedLayerTrackId(eventId: eventId, layerId: layerId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  // Convert waveform data to Float32List for TimelineClip
  static Float32List? _convertWaveformData(List<double>? data) {
    if (data == null || data.isEmpty) return null;
    return Float32List.fromList(data.cast<double>());
  }

  /// Map busId to OutputBus enum
  static timeline.OutputBus _busIdToOutputBus(int? busId) {
    switch (busId) {
      case 0:
        return timeline.OutputBus.master;
      case 1:
        return timeline.OutputBus.music;
      case 2:
        return timeline.OutputBus.sfx;
      case 3:
        return timeline.OutputBus.voice;
      case 4:
        return timeline.OutputBus.ambience;
      default:
        return timeline.OutputBus.master;
    }
  }

  /// Reverse map OutputBus enum to busId
  static int _outputBusToBusId(timeline.OutputBus bus) {
    switch (bus) {
      case timeline.OutputBus.master:
        return 0;
      case timeline.OutputBus.music:
        return 1;
      case timeline.OutputBus.sfx:
        return 2;
      case timeline.OutputBus.voice:
        return 3;
      case timeline.OutputBus.ambience:
        return 4;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERNAL DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Lightweight snapshot for diff comparison (avoids deep equality on full model)
class _EventSnapshot {
  final String id;
  final String name;
  final double masterVolume;
  final List<String> layerIds;
  final Map<String, _LayerSnapshot> layers;

  _EventSnapshot({
    required this.id,
    required this.name,
    required this.masterVolume,
    required this.layerIds,
    required this.layers,
  });

  factory _EventSnapshot.from(SlotCompositeEvent event) {
    final layerMap = <String, _LayerSnapshot>{};
    for (final layer in event.layers) {
      layerMap[layer.id] = _LayerSnapshot.from(layer);
    }
    return _EventSnapshot(
      id: event.id,
      name: event.name,
      masterVolume: event.masterVolume,
      layerIds: event.layers.map((l) => l.id).toList(),
      layers: layerMap,
    );
  }

  bool isEqualTo(SlotCompositeEvent event) {
    if (name != event.name) return false;
    if (masterVolume != event.masterVolume) return false;
    if (layerIds.length != event.layers.length) return false;

    for (int i = 0; i < event.layers.length; i++) {
      final layer = event.layers[i];
      if (i >= layerIds.length || layerIds[i] != layer.id) return false;
      final snapshot = layers[layer.id];
      if (snapshot == null || !snapshot.isEqualTo(layer)) return false;
    }

    return true;
  }
}

/// Lightweight layer snapshot for diff comparison
class _LayerSnapshot {
  final String id;
  final String name;
  final String audioPath;
  final double volume;
  final double pan;
  final double offsetMs;
  final double fadeInMs;
  final double fadeOutMs;
  final double trimStartMs;
  final double trimEndMs;
  final bool muted;
  final bool solo;
  final bool loop;
  final int? busId;
  final double? durationSeconds;

  _LayerSnapshot({
    required this.id,
    required this.name,
    required this.audioPath,
    required this.volume,
    required this.pan,
    required this.offsetMs,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.muted,
    required this.solo,
    required this.loop,
    required this.busId,
    required this.durationSeconds,
  });

  factory _LayerSnapshot.from(SlotEventLayer layer) {
    return _LayerSnapshot(
      id: layer.id,
      name: layer.name,
      audioPath: layer.audioPath,
      volume: layer.volume,
      pan: layer.pan,
      offsetMs: layer.offsetMs,
      fadeInMs: layer.fadeInMs,
      fadeOutMs: layer.fadeOutMs,
      trimStartMs: layer.trimStartMs,
      trimEndMs: layer.trimEndMs,
      muted: layer.muted,
      solo: layer.solo,
      loop: layer.loop,
      busId: layer.busId,
      durationSeconds: layer.durationSeconds,
    );
  }

  bool isEqualTo(SlotEventLayer layer) {
    return name == layer.name &&
        audioPath == layer.audioPath &&
        volume == layer.volume &&
        pan == layer.pan &&
        offsetMs == layer.offsetMs &&
        fadeInMs == layer.fadeInMs &&
        fadeOutMs == layer.fadeOutMs &&
        trimStartMs == layer.trimStartMs &&
        trimEndMs == layer.trimEndMs &&
        muted == layer.muted &&
        solo == layer.solo &&
        loop == layer.loop &&
        busId == layer.busId &&
        durationSeconds == layer.durationSeconds;
  }
}

class _ParsedLayerTrackId {
  final String eventId;
  final String layerId;
  const _ParsedLayerTrackId({required this.eventId, required this.layerId});
}

class _TrackStructure {
  final List<timeline.TimelineTrack> tracks;
  final List<timeline.TimelineClip> clips;
  const _TrackStructure({required this.tracks, required this.clips});
}

class _RemoveResult {
  final List<String> trackIds;
  final List<String> clipIds;
  const _RemoveResult({required this.trackIds, required this.clipIds});
}

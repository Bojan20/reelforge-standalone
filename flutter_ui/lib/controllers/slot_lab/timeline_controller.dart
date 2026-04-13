// Timeline Controller — State Management & Actions
//
// Centralized controller for timeline state and operations.
// Handles playback, editing, zoom, grid, markers.
// Playback is wired to PLAYBACK_ENGINE via SlotLabTrackBridge.

import 'package:flutter/foundation.dart';
import '../../models/timeline/timeline_state.dart';
import '../../models/timeline/audio_region.dart';
import '../../models/timeline/stage_marker.dart';
import '../../services/waveform_cache.dart';
import '../../services/slotlab_track_bridge.dart';

class TimelineController extends ChangeNotifier {
  TimelineState _state = const TimelineState();

  final SlotLabTrackBridge _bridge = SlotLabTrackBridge.instance;

  TimelineState get state => _state;

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  void play() {
    _state = _state.copyWith(isPlaying: true);
    notifyListeners();
    // Wire to PLAYBACK_ENGINE via SlotLabTrackBridge
    _bridge.play(fromPosition: _state.playheadPosition);
  }

  void pause() {
    _state = _state.copyWith(isPlaying: false);
    notifyListeners();
    // Wire to PLAYBACK_ENGINE via SlotLabTrackBridge
    _bridge.pause();
  }

  void stop() {
    final stopPos = _state.loopStart ?? 0.0;
    _state = _state.copyWith(
      isPlaying: false,
      playheadPosition: stopPos,
    );
    notifyListeners();
    // Wire to PLAYBACK_ENGINE via SlotLabTrackBridge
    _bridge.stop();
  }

  void togglePlayback() {
    if (_state.isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void seek(double timeSeconds) {
    final clamped = timeSeconds.clamp(0.0, _state.totalDuration);
    _state = _state.copyWith(playheadPosition: clamped);
    notifyListeners();
    // Wire to PLAYBACK_ENGINE via SlotLabTrackBridge
    _bridge.seek(clamped);
  }

  /// Sync playhead from engine (call on timer tick)
  void syncFromEngine() {
    if (!_state.isPlaying) return;
    final pos = _bridge.currentPosition;
    if ((pos - _state.playheadPosition).abs() > 0.001) {
      _state = _state.copyWith(playheadPosition: pos);
      notifyListeners();
    }
  }

  void toggleLoop() {
    _state = _state.copyWith(isLooping: !_state.isLooping);
    notifyListeners();
  }

  void setLoopRegion(double? start, double? end) {
    _state = _state.copyWith(loopStart: start, loopEnd: end);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ZOOM & PAN
  // ═══════════════════════════════════════════════════════════════════════════

  void zoomIn() {
    final newZoom = (_state.zoom * 1.2).clamp(0.1, 10.0);
    _state = _state.copyWith(zoom: newZoom);
    notifyListeners();
  }

  void zoomOut() {
    final newZoom = (_state.zoom / 1.2).clamp(0.1, 10.0);
    _state = _state.copyWith(zoom: newZoom);
    notifyListeners();
  }

  void setZoom(double zoom) {
    _state = _state.copyWith(zoom: zoom.clamp(0.1, 10.0));
    notifyListeners();
  }

  void zoomToFit() {
    // Reset to 1.0x zoom
    _state = _state.copyWith(zoom: 1.0, scrollOffset: 0.0);
    notifyListeners();
  }

  void zoomToSelection() {
    // TODO: Zoom to selected regions
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GRID & SNAP
  // ═══════════════════════════════════════════════════════════════════════════

  void toggleSnap() {
    _state = _state.copyWith(snapEnabled: !_state.snapEnabled);
    notifyListeners();
  }

  void setGridMode(GridMode mode) {
    _state = _state.copyWith(gridMode: mode);
    notifyListeners();
  }

  void cycleGridMode() {
    final modes = GridMode.values;
    final currentIndex = modes.indexOf(_state.gridMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    _state = _state.copyWith(gridMode: modes[nextIndex]);
    notifyListeners();
  }

  void setMillisecondInterval(int intervalMs) {
    _state = _state.copyWith(millisecondInterval: intervalMs);
    notifyListeners();
  }

  void setFrameRate(int fps) {
    _state = _state.copyWith(frameRate: fps);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void addTrack({String? name}) {
    final trackId = 'track_${DateTime.now().millisecondsSinceEpoch}';
    final track = TimelineTrack(
      id: trackId,
      name: name ?? 'Track ${_state.tracks.length + 1}',
    );

    _state = _state.addTrack(track);
    notifyListeners();
  }

  void removeTrack(String trackId) {
    _state = _state.removeTrack(trackId);
    notifyListeners();
  }

  void toggleTrackMute(String trackId) {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    _state = _state.updateTrack(trackId, track.copyWith(isMuted: !track.isMuted));
    notifyListeners();
  }

  void toggleTrackSolo(String trackId) {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    _state = _state.updateTrack(trackId, track.copyWith(isSoloed: !track.isSoloed));
    notifyListeners();
  }

  void toggleTrackRecordArm(String trackId) {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    _state = _state.updateTrack(trackId, track.copyWith(isRecordArmed: !track.isRecordArmed));
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REGION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void addRegion(String trackId, AudioRegion region) {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    _state = _state.updateTrack(trackId, track.addRegion(region));
    notifyListeners();
  }

  void removeRegion(String trackId, String regionId) {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    _state = _state.updateTrack(trackId, track.removeRegion(regionId));
    notifyListeners();
  }

  void updateRegion(String trackId, String regionId, AudioRegion updatedRegion) {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    _state = _state.updateTrack(trackId, track.updateRegion(regionId, updatedRegion));
    notifyListeners();
  }

  void selectRegion(String regionId) {
    // Deselect all, select one
    final updatedTracks = _state.tracks.map((track) {
      final updatedRegions = track.regions.map((region) {
        return region.copyWith(isSelected: region.id == regionId);
      }).toList();
      return track.copyWith(regions: updatedRegions);
    }).toList();

    _state = _state.copyWith(tracks: updatedTracks);
    notifyListeners();
  }

  void deselectAll() {
    final updatedTracks = _state.tracks.map((track) {
      final updatedRegions = track.regions.map((region) {
        return region.copyWith(isSelected: false);
      }).toList();
      return track.copyWith(regions: updatedRegions);
    }).toList();

    _state = _state.copyWith(tracks: updatedTracks);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARKER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void addMarker(StageMarker marker) {
    _state = _state.addMarker(marker);
    notifyListeners();
  }

  void addMarkerAtPlayhead(String stageId, String label) {
    final marker = StageMarker.fromStageId(stageId, _state.playheadPosition);
    addMarker(marker);
  }

  void removeMarker(String markerId) {
    _state = _state.removeMarker(markerId);
    notifyListeners();
  }

  void jumpToMarker(String markerId) {
    final marker = _state.markers.firstWhere((m) => m.id == markerId);
    seek(marker.timeSeconds);
  }

  void jumpToNextMarker() {
    final sortedMarkers = List<StageMarker>.from(_state.markers)
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    final nextMarker = sortedMarkers.firstWhere(
      (m) => m.timeSeconds > _state.playheadPosition,
      orElse: () => sortedMarkers.first,
    );

    seek(nextMarker.timeSeconds);
  }

  void jumpToPreviousMarker() {
    final sortedMarkers = List<StageMarker>.from(_state.markers)
      ..sort((a, b) => b.timeSeconds.compareTo(a.timeSeconds)); // Reverse

    final prevMarker = sortedMarkers.firstWhere(
      (m) => m.timeSeconds < _state.playheadPosition,
      orElse: () => sortedMarkers.first,
    );

    seek(prevMarker.timeSeconds);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAVEFORM LOADING — Shared WaveformCache (same source as DAW)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tracks waveform loading in progress to prevent duplicate FFI calls
  final Set<String> _waveformLoading = {};

  /// Ensure waveform is in shared WaveformCache and set region's cacheKey.
  /// Uses the SAME WaveformCache singleton as DAW — zero duplication.
  ///
  /// The generateFn parameter is a sync FFI call wrapped in an async shell
  /// to allow the caller to yield before/after the expensive call.
  Future<void> loadWaveformForRegion(
    String trackId,
    String regionId, {
    required Future<String?> Function(String path, String cacheKey) generateFn,
  }) async {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    final region = track.regions.where((r) => r.id == regionId).firstOrNull;
    if (region == null) return;

    // Deterministic cache key — SAME key DAW would use for this audio path
    final cacheKey = 'slotlab_${region.audioPath.hashCode}';

    // Already has a cache key pointing to valid data — instant, no work needed
    if (region.waveformCacheKey == cacheKey && WaveformCache().hasMultiRes(cacheKey)) {
      return;
    }

    // Prevent duplicate concurrent loads for same path
    if (_waveformLoading.contains(cacheKey)) return;
    _waveformLoading.add(cacheKey);

    try {
      // Check if already in shared cache (may have been loaded by DAW)
      if (!WaveformCache().hasMultiRes(cacheKey)) {
        // Generate via FFI → populates WaveformCache singleton
        final json = await generateFn(region.audioPath, cacheKey);
        if (json != null && json.isNotEmpty) {
          // Parse into shared cache
          WaveformCache().getOrComputeMultiResFromPath(cacheKey, region.audioPath);
        }
      }

      // Set the cache key on the region — painter reads from WaveformCache
      final freshTrack = _state.getTrack(trackId);
      if (freshTrack == null) return;
      final freshRegion = freshTrack.regions.where((r) => r.id == regionId).firstOrNull;
      if (freshRegion == null) return;

      final updatedRegion = freshRegion.copyWith(waveformCacheKey: cacheKey);
      updateRegion(trackId, regionId, updatedRegion);
    } catch (e) {
      // Waveform load failed — region will display filename placeholder
    } finally {
      _waveformLoading.remove(cacheKey);
    }
  }

  /// Load waveforms for all regions in a track — PARALLEL
  Future<void> loadWaveformsForTrack(
    String trackId, {
    required Future<String?> Function(String path, String cacheKey) generateFn,
  }) async {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    // Launch all region waveform loads in parallel
    await Future.wait(
      track.regions.map((region) => loadWaveformForRegion(
        trackId,
        region.id,
        generateFn: generateFn,
      )),
    );
  }

  /// Load waveforms for all tracks — PARALLEL
  Future<void> loadAllWaveforms({
    required Future<String?> Function(String path, String cacheKey) generateFn,
  }) async {
    await Future.wait(
      _state.tracks.map((track) => loadWaveformsForTrack(
        track.id,
        generateFn: generateFn,
      )),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => _state.toJson();

  void loadFromJson(Map<String, dynamic> json) {
    _state = TimelineState.fromJson(json);
    notifyListeners();
  }

  /// Format time helper
  String _formatPlayheadTime(double timeSeconds, TimeDisplayMode mode) {
    switch (mode) {
      case TimeDisplayMode.milliseconds:
        return '${(timeSeconds * 1000).toInt()}ms';
      case TimeDisplayMode.seconds:
        return timeSeconds.toStringAsFixed(3);
      case TimeDisplayMode.beats:
        return '1.1.1';
      case TimeDisplayMode.timecode:
        return '00:00:00:00';
    }
  }
}

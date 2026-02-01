// Timeline Controller — State Management & Actions
//
// Centralized controller for timeline state and operations.
// Handles playback, editing, zoom, grid, markers.

import 'package:flutter/foundation.dart';
import '../../models/timeline/timeline_state.dart';
import '../../models/timeline/audio_region.dart';
import '../../models/timeline/stage_marker.dart';
import '../../models/timeline_models.dart' show parseWaveformFromJson;

class TimelineController extends ChangeNotifier {
  TimelineState _state = const TimelineState();

  TimelineState get state => _state;

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  void play() {
    _state = _state.copyWith(isPlaying: true);
    notifyListeners();
    // TODO: Start audio engine playback
  }

  void pause() {
    _state = _state.copyWith(isPlaying: false);
    notifyListeners();
    // TODO: Pause audio engine
  }

  void stop() {
    _state = _state.copyWith(
      isPlaying: false,
      playheadPosition: _state.loopStart ?? 0.0,
    );
    notifyListeners();
    // TODO: Stop audio engine
  }

  void togglePlayback() {
    if (_state.isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void seek(double timeSeconds) {
    _state = _state.copyWith(
      playheadPosition: timeSeconds.clamp(0.0, _state.totalDuration),
    );
    notifyListeners();
    // TODO: Seek audio engine
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
  // WAVEFORM LOADING (Phase 2)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load waveform data from Rust FFI
  Future<void> loadWaveformForRegion(
    String trackId,
    String regionId, {
    required Future<String> Function(String path, String cacheKey) generateWaveformFn,
  }) async {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    final region = track.regions.firstWhere(
      (r) => r.id == regionId,
      orElse: () => throw Exception('Region not found'),
    );

    try {
      // Call FFI to generate waveform JSON
      final cacheKey = 'timeline_${region.audioPath.hashCode}';
      final waveformJson = await generateWaveformFn(region.audioPath, cacheKey);

      // Parse JSON to Float32List (using existing helper)
      final waveformData = _parseWaveformJson(waveformJson);

      // Update region with waveform data
      if (waveformData != null) {
        final updatedRegion = region.copyWith(waveformData: waveformData);
        updateRegion(trackId, regionId, updatedRegion);
      }
    } catch (e) {
      // Waveform load failed — region will display filename instead
      debugPrint('[TimelineController] Waveform load failed for ${region.audioPath}: $e');
    }
  }

  /// Parse waveform JSON from Rust FFI (uses existing parseWaveformFromJson helper)
  List<double>? _parseWaveformJson(String json) {
    final (leftChannel, rightChannel) = parseWaveformFromJson(json, maxSamples: 2048);

    if (leftChannel == null) return null;

    // Convert Float32List to List<double>
    final waveformData = <double>[];

    // Mix stereo to mono if needed, or just use left
    if (rightChannel != null && rightChannel.length == leftChannel.length) {
      for (int i = 0; i < leftChannel.length; i++) {
        final mono = (leftChannel[i] + rightChannel[i]) / 2.0;
        waveformData.add(mono);
      }
    } else {
      waveformData.addAll(leftChannel);
    }

    return waveformData;
  }

  /// Load waveforms for all regions in a track
  Future<void> loadWaveformsForTrack(
    String trackId, {
    required Future<String> Function(String path, String cacheKey) generateWaveformFn,
  }) async {
    final track = _state.getTrack(trackId);
    if (track == null) return;

    for (final region in track.regions) {
      await loadWaveformForRegion(trackId, region.id, generateWaveformFn: generateWaveformFn);
    }
  }

  /// Load waveforms for all tracks
  Future<void> loadAllWaveforms({
    required Future<String> Function(String path, String cacheKey) generateWaveformFn,
  }) async {
    for (final track in _state.tracks) {
      await loadWaveformsForTrack(track.id, generateWaveformFn: generateWaveformFn);
    }
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

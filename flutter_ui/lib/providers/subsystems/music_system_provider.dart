/// Music System Provider
///
/// Extracted from MiddlewareProvider as part of P1.7 decomposition.
/// Manages music segments, stingers, and music playback state (Wwise/FMOD-style).
///
/// Music segments are looping or one-shot musical pieces that can be
/// queued and transitioned between. Stingers are short musical phrases
/// triggered by game events, synced to the beat/bar grid.

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing music system (segments and stingers)
class MusicSystemProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Music segments storage
  final Map<int, MusicSegment> _musicSegments = {};

  /// Stingers storage
  final Map<int, Stinger> _stingers = {};

  /// Currently playing music segment
  int? _currentMusicSegmentId;

  /// Next queued music segment (for seamless transition)
  int? _nextMusicSegmentId;

  /// Music bus ID for routing
  int _musicBusId = 1; // Default to music bus

  /// ID counters
  int _nextMusicSegmentIdCounter = 1;
  int _nextStingerId = 1;

  MusicSystemProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all music segments as list
  List<MusicSegment> get musicSegments => _musicSegments.values.toList();

  /// Get all stingers as list
  List<Stinger> get stingers => _stingers.values.toList();

  /// Get currently playing segment ID
  int? get currentMusicSegmentId => _currentMusicSegmentId;

  /// Get next queued segment ID
  int? get nextMusicSegmentId => _nextMusicSegmentId;

  /// Get music bus ID
  int get musicBusId => _musicBusId;

  /// Get segment count
  int get segmentCount => _musicSegments.length;

  /// Get stinger count
  int get stingerCount => _stingers.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC SEGMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new music segment
  MusicSegment addMusicSegment({
    required String name,
    required int soundId,
    double tempo = 120.0,
    int beatsPerBar = 4,
    int durationBars = 4,
  }) {
    final id = _nextMusicSegmentIdCounter++;

    final segment = MusicSegment(
      id: id,
      name: name,
      soundId: soundId,
      tempo: tempo,
      beatsPerBar: beatsPerBar,
      durationBars: durationBars,
    );

    _musicSegments[id] = segment;
    _ffi.middlewareAddMusicSegment(segment);

    notifyListeners();
    return segment;
  }

  /// Update an existing music segment
  void updateMusicSegment(MusicSegment segment) {
    _musicSegments[segment.id] = segment;
    notifyListeners();
  }

  /// Add marker to music segment
  void addMusicMarker(
    int segmentId, {
    required String name,
    required double positionBars,
    required MarkerType markerType,
  }) {
    final segment = _musicSegments[segmentId];
    if (segment == null) return;

    final marker = MusicMarker(
      name: name,
      positionBars: positionBars,
      markerType: markerType,
    );

    final updatedMarkers = List<MusicMarker>.from(segment.markers)..add(marker);
    _musicSegments[segmentId] = segment.copyWith(markers: updatedMarkers);

    _ffi.middlewareMusicSegmentAddMarker(segmentId, marker);
    notifyListeners();
  }

  /// Remove music segment
  void removeMusicSegment(int segmentId) {
    _musicSegments.remove(segmentId);
    _ffi.middlewareRemoveMusicSegment(segmentId);
    notifyListeners();
  }

  /// Get music segment by ID
  MusicSegment? getMusicSegment(int segmentId) => _musicSegments[segmentId];

  /// Import existing music segment (for profile loading)
  void importSegment(MusicSegment segment) {
    _musicSegments[segment.id] = segment;
    if (segment.id >= _nextMusicSegmentIdCounter) {
      _nextMusicSegmentIdCounter = segment.id + 1;
    }
    _ffi.middlewareAddMusicSegment(segment);
    notifyListeners();
  }

  /// Set currently playing music segment
  void setCurrentMusicSegment(int segmentId) {
    _currentMusicSegmentId = segmentId;
    _ffi.middlewareSetMusicSegment(segmentId);
    notifyListeners();
  }

  /// Queue next music segment for seamless transition
  void queueMusicSegment(int segmentId) {
    _nextMusicSegmentId = segmentId;
    _ffi.middlewareQueueMusicSegment(segmentId);
    notifyListeners();
  }

  /// Set music bus ID for routing
  void setMusicBusId(int busId) {
    _musicBusId = busId;
    _ffi.middlewareSetMusicBus(busId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STINGERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new stinger
  Stinger addStinger({
    required String name,
    required int soundId,
    MusicSyncPoint syncPoint = MusicSyncPoint.beat,
    double customGridBeats = 4.0,
    double musicDuckDb = 0.0,
    double duckAttackMs = 10.0,
    double duckReleaseMs = 100.0,
    int priority = 50,
    bool canInterrupt = false,
  }) {
    final id = _nextStingerId++;

    final stinger = Stinger(
      id: id,
      name: name,
      soundId: soundId,
      syncPoint: syncPoint,
      customGridBeats: customGridBeats,
      musicDuckDb: musicDuckDb,
      duckAttackMs: duckAttackMs,
      duckReleaseMs: duckReleaseMs,
      priority: priority,
      canInterrupt: canInterrupt,
    );

    _stingers[id] = stinger;
    _ffi.middlewareAddStinger(stinger);

    notifyListeners();
    return stinger;
  }

  /// Update an existing stinger
  void updateStinger(Stinger stinger) {
    _stingers[stinger.id] = stinger;
    notifyListeners();
  }

  /// Remove stinger
  void removeStinger(int stingerId) {
    _stingers.remove(stingerId);
    _ffi.middlewareRemoveStinger(stingerId);
    notifyListeners();
  }

  /// Get stinger by ID
  Stinger? getStinger(int stingerId) => _stingers[stingerId];

  /// Import existing stinger (for profile loading)
  void importStinger(Stinger stinger) {
    _stingers[stinger.id] = stinger;
    if (stinger.id >= _nextStingerId) {
      _nextStingerId = stinger.id + 1;
    }
    _ffi.middlewareAddStinger(stinger);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export music system state to JSON
  Map<String, dynamic> toJson() {
    return {
      'musicSegments': _musicSegments.values.map((s) => s.toJson()).toList(),
      'stingers': _stingers.values.map((s) => s.toJson()).toList(),
      'currentMusicSegmentId': _currentMusicSegmentId,
      'nextMusicSegmentId': _nextMusicSegmentId,
      'musicBusId': _musicBusId,
    };
  }

  /// Import music system state from JSON
  void fromJson(Map<String, dynamic> json) {
    _musicSegments.clear();
    _stingers.clear();

    if (json['musicSegments'] != null) {
      for (final segmentJson in json['musicSegments'] as List) {
        final segment = MusicSegment.fromJson(segmentJson);
        _musicSegments[segment.id] = segment;
        if (segment.id >= _nextMusicSegmentIdCounter) {
          _nextMusicSegmentIdCounter = segment.id + 1;
        }
      }
    }

    if (json['stingers'] != null) {
      for (final stingerJson in json['stingers'] as List) {
        final stinger = Stinger.fromJson(stingerJson);
        _stingers[stinger.id] = stinger;
        if (stinger.id >= _nextStingerId) {
          _nextStingerId = stinger.id + 1;
        }
      }
    }

    _currentMusicSegmentId = json['currentMusicSegmentId'];
    _nextMusicSegmentId = json['nextMusicSegmentId'];
    _musicBusId = json['musicBusId'] ?? 1;

    notifyListeners();
  }

  /// Clear all music data
  void clear() {
    _musicSegments.clear();
    _stingers.clear();
    _currentMusicSegmentId = null;
    _nextMusicSegmentId = null;
    _musicBusId = 1;
    _nextMusicSegmentIdCounter = 1;
    _nextStingerId = 1;
    notifyListeners();
  }
}

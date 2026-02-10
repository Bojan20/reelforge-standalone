/// SlotLab Track Bridge
///
/// Bridges SlotLab timeline regions/layers to DAW TRACK_MANAGER clips.
/// Enables unified playback through PLAYBACK_ENGINE.
///
/// Architecture:
/// - SlotLab regions → DAW clips on dedicated SlotLab track
/// - Playback uses engine_play() / engine_seek() (same as DAW)
/// - Transport is synchronized between SlotLab and DAW

import '../src/rust/native_ffi.dart';

/// Bridge between SlotLab timeline and DAW TRACK_MANAGER
class SlotLabTrackBridge {
  static SlotLabTrackBridge? _instance;
  static SlotLabTrackBridge get instance => _instance ??= SlotLabTrackBridge._();

  SlotLabTrackBridge._();

  final NativeFFI _ffi = NativeFFI.instance;

  /// Track ID in TRACK_MANAGER for SlotLab audio
  int? _slotLabTrackId;

  /// Map of layer ID → clip ID in TRACK_MANAGER
  final Map<String, int> _layerToClipId = {};

  /// Map of layer ID → audio file path (for tracking imports)
  final Map<String, String> _layerAudioPath = {};

  /// Whether bridge is initialized
  bool get isInitialized => _slotLabTrackId != null;

  /// Get all registered layer IDs (for sync diffing)
  Set<String> get registeredLayerIds => _layerToClipId.keys.toSet();

  /// Get SlotLab track ID (creates if needed)
  int get slotLabTrackId {
    _slotLabTrackId ??= _createSlotLabTrack();
    return _slotLabTrackId!;
  }

  /// Create SlotLab track in TRACK_MANAGER
  int _createSlotLabTrack() {
    // createTrack(String name, int color, int busId) - positional args
    final trackId = _ffi.createTrack('SlotLab', 0xFF4A9EFF, 2); // Blue, SFX bus
    return trackId;
  }

  /// Add layer as clip in TRACK_MANAGER
  /// Returns clip ID or -1 on error
  int addLayerClip({
    required String layerId,
    required String audioPath,
    required double startTime,
    required double duration,
    double volume = 1.0,
  }) {
    if (audioPath.isEmpty) return -1;

    // Check if layer already has a clip
    if (_layerToClipId.containsKey(layerId)) {
      // If same audio path, just return existing clip
      if (_layerAudioPath[layerId] == audioPath) {
        return _layerToClipId[layerId]!;
      }
      // Different audio - remove old clip first
      removeLayerClip(layerId);
    }

    // Import audio file to SlotLab track at the specified position
    // importAudio(String path, int trackId, double startTime) - returns clip ID
    final clipId = _ffi.importAudio(audioPath, slotLabTrackId, startTime);
    if (clipId <= 0) {
      return -1;
    }

    _layerToClipId[layerId] = clipId;
    _layerAudioPath[layerId] = audioPath;

    // Set clip gain
    _ffi.setClipGain(clipId, volume);

    return clipId;
  }

  /// Update layer clip position/duration
  void updateLayerClip({
    required String layerId,
    required double startTime,
    required double duration,
  }) {
    final clipId = _layerToClipId[layerId];
    if (clipId == null) return;

    // moveClip(int clipId, int targetTrackId, double startTime)
    _ffi.moveClip(clipId, slotLabTrackId, startTime);

    // resizeClip(int clipId, double startTime, double duration, double sourceOffset)
    // Keep sourceOffset at 0 (play from beginning of source)
    _ffi.resizeClip(clipId, startTime, duration, 0.0);
  }

  /// Remove layer clip from TRACK_MANAGER
  void removeLayerClip(String layerId) {
    final clipId = _layerToClipId.remove(layerId);
    _layerAudioPath.remove(layerId);
    if (clipId != null) {
      _ffi.deleteClip(clipId);
    }
  }

  /// Clear all SlotLab clips
  void clearAllClips() {
    for (final clipId in _layerToClipId.values) {
      _ffi.deleteClip(clipId);
    }
    _layerToClipId.clear();
    _layerAudioPath.clear();
  }

  /// Start playback at position (uses PLAYBACK_ENGINE)
  void play({double fromPosition = 0.0}) {
    // Ensure audio stream is running
    _ffi.startPlayback();
    // Seek to position
    _ffi.seek(fromPosition);
    // Start transport
    _ffi.play();
  }

  /// Pause playback
  void pause() {
    _ffi.pause();
  }

  /// Stop playback (resets to start)
  void stop() {
    _ffi.stop();
  }

  /// Seek to position
  void seek(double seconds) {
    _ffi.seek(seconds);
  }

  /// Check if playing
  bool get isPlaying => _ffi.isPlaying();

  /// Get current position in seconds
  double get currentPosition => _ffi.getPosition();

  /// Dispose bridge (cleanup)
  void dispose() {
    clearAllClips();
    if (_slotLabTrackId != null) {
      _ffi.deleteTrack(_slotLabTrackId!);
      _slotLabTrackId = null;
    }
  }
}

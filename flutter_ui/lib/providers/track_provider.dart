// Track Provider
//
// Central track management for the DAW:
// - Track creation/deletion
// - Track state (armed, muted, soloed)
// - Track routing
// - Recording integration
// - Plugin insert management
// - Sync with Rust engine via FFI

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import '../src/rust/engine_api.dart' as api;

// ═══════════════════════════════════════════════════════════════════════════════
// TRACK TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Track type enumeration
enum TrackType {
  audio,
  instrument,
  aux,
  master,
  folder,
}

/// Track input source
enum TrackInputSource {
  none,
  hardware1,
  hardware2,
  hardware3,
  hardware4,
  hardware5,
  hardware6,
  hardware7,
  hardware8,
  stereoIn1_2,
  stereoIn3_4,
  stereoIn5_6,
  stereoIn7_8,
  bus1,
  bus2,
  bus3,
  bus4,
  bus5,
  bus6,
}

/// Track output destination
enum TrackOutput {
  master,
  bus1,
  bus2,
  bus3,
  bus4,
  bus5,
  bus6,
  none,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRACK MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio track model
class Track {
  final int id;
  final String name;
  final TrackType type;
  final int color;

  // State
  final bool armed;
  final bool muted;
  final bool soloed;
  final bool monitorInput;

  // Levels
  final double volume; // 0.0 - 1.0
  final double pan; // -1.0 to 1.0

  // Routing
  final TrackInputSource inputSource;
  final TrackOutput output;
  final int inputChannels; // 1 = mono, 2 = stereo

  // Plugin inserts (instance IDs)
  final List<String?> inserts;

  // Recording
  final bool isRecording;
  final String? recordingPath;

  // Engine sync
  final int engineTrackId;

  const Track({
    required this.id,
    required this.name,
    this.type = TrackType.audio,
    this.color = 0xFF4A9EFF,
    this.armed = false,
    this.muted = false,
    this.soloed = false,
    this.monitorInput = false,
    this.volume = 0.8,
    this.pan = 0.0,
    this.inputSource = TrackInputSource.none,
    this.output = TrackOutput.master,
    this.inputChannels = 2,
    this.inserts = const [null, null, null, null, null, null, null, null],
    this.isRecording = false,
    this.recordingPath,
    this.engineTrackId = -1,
  });

  Track copyWith({
    int? id,
    String? name,
    TrackType? type,
    int? color,
    bool? armed,
    bool? muted,
    bool? soloed,
    bool? monitorInput,
    double? volume,
    double? pan,
    TrackInputSource? inputSource,
    TrackOutput? output,
    int? inputChannels,
    List<String?>? inserts,
    bool? isRecording,
    String? recordingPath,
    int? engineTrackId,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      color: color ?? this.color,
      armed: armed ?? this.armed,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      monitorInput: monitorInput ?? this.monitorInput,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      inputSource: inputSource ?? this.inputSource,
      output: output ?? this.output,
      inputChannels: inputChannels ?? this.inputChannels,
      inserts: inserts ?? this.inserts,
      isRecording: isRecording ?? this.isRecording,
      recordingPath: recordingPath ?? this.recordingPath,
      engineTrackId: engineTrackId ?? this.engineTrackId,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRACK PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Central track management provider
class TrackProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // Track storage
  final Map<int, Track> _tracks = {};
  int _nextTrackId = 1;

  // Selection
  int? _selectedTrackId;
  final Set<int> _multiSelectedTrackIds = {};

  // Solo state tracking
  bool _hasSoloedTracks = false;

  // Track colors palette
  static const List<int> _trackColors = [
    0xFF4A9EFF, // Blue
    0xFFFF9040, // Orange
    0xFF40FF90, // Green
    0xFFFF4060, // Red
    0xFF40C8FF, // Cyan
    0xFFFF40C8, // Magenta
    0xFFFFD040, // Yellow
    0xFF9040FF, // Purple
  ];
  int _colorIndex = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<Track> get tracks => _tracks.values.toList()
    ..sort((a, b) => a.id.compareTo(b.id));

  List<Track> get audioTracks => tracks
      .where((t) => t.type == TrackType.audio || t.type == TrackType.instrument)
      .toList();

  List<Track> get armedTracks => tracks.where((t) => t.armed).toList();

  List<Track> get recordingTracks => tracks.where((t) => t.isRecording).toList();

  int get trackCount => _tracks.length;

  int get armedCount => armedTracks.length;

  int get recordingCount => recordingTracks.length;

  int? get selectedTrackId => _selectedTrackId;

  Track? get selectedTrack => _selectedTrackId != null
      ? _tracks[_selectedTrackId]
      : null;

  Set<int> get multiSelectedTrackIds => Set.unmodifiable(_multiSelectedTrackIds);

  bool get hasSoloedTracks => _hasSoloedTracks;

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create new audio track
  Track createTrack({
    String? name,
    TrackType type = TrackType.audio,
    int? color,
    TrackInputSource inputSource = TrackInputSource.none,
    int inputChannels = 2,
  }) {
    final trackId = _nextTrackId++;
    final trackName = name ?? 'Track $trackId';
    final trackColor = color ?? _getNextColor();

    // Create in Rust engine (name, color, busId)
    // busId 0 = route to master
    final engineTrackId = _ffi.isLoaded
        ? _ffi.createTrack(trackName, trackColor, 0)
        : -1;

    final track = Track(
      id: trackId,
      name: trackName,
      type: type,
      color: trackColor,
      inputSource: inputSource,
      inputChannels: inputChannels,
      engineTrackId: engineTrackId,
      inserts: List.filled(8, null),
    );

    _tracks[trackId] = track;
    notifyListeners();

    debugPrint('[TrackProvider] Created track: $trackName (engine: $engineTrackId)');
    return track;
  }

  /// Delete track
  bool deleteTrack(int trackId) {
    final track = _tracks[trackId];
    if (track == null) return false;

    // Stop recording if active
    if (track.isRecording) {
      stopRecording(trackId);
    }

    // Disarm if armed
    if (track.armed) {
      disarmTrack(trackId);
    }

    // Delete from Rust engine
    if (_ffi.isLoaded && track.engineTrackId >= 0) {
      _ffi.deleteTrack(track.engineTrackId);
    }

    _tracks.remove(trackId);

    // Clear selection if deleted
    if (_selectedTrackId == trackId) {
      _selectedTrackId = null;
    }
    _multiSelectedTrackIds.remove(trackId);

    notifyListeners();
    debugPrint('[TrackProvider] Deleted track: ${track.name}');
    return true;
  }

  /// Get track by ID
  Track? getTrack(int trackId) => _tracks[trackId];

  /// Update track properties
  void updateTrack(int trackId, Track Function(Track) updater) {
    final track = _tracks[trackId];
    if (track == null) return;

    _tracks[trackId] = updater(track);
    notifyListeners();
  }

  /// Rename track
  void renameTrack(int trackId, String name) {
    final track = _tracks[trackId];
    if (track == null) return;

    _tracks[trackId] = track.copyWith(name: name);
    notifyListeners();
  }

  /// Set track color
  void setTrackColor(int trackId, int color) {
    final track = _tracks[trackId];
    if (track == null) return;

    _tracks[trackId] = track.copyWith(color: color);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select single track
  void selectTrack(int trackId) {
    _selectedTrackId = trackId;
    _multiSelectedTrackIds.clear();
    _multiSelectedTrackIds.add(trackId);
    notifyListeners();
  }

  /// Toggle track in multi-selection
  void toggleTrackSelection(int trackId) {
    if (_multiSelectedTrackIds.contains(trackId)) {
      _multiSelectedTrackIds.remove(trackId);
      if (_selectedTrackId == trackId) {
        _selectedTrackId = _multiSelectedTrackIds.isNotEmpty
            ? _multiSelectedTrackIds.first
            : null;
      }
    } else {
      _multiSelectedTrackIds.add(trackId);
      _selectedTrackId = trackId;
    }
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedTrackId = null;
    _multiSelectedTrackIds.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK STATE (Mute, Solo, Arm)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle track mute
  void toggleMute(int trackId) {
    final track = _tracks[trackId];
    if (track == null) return;

    final newMuted = !track.muted;
    _tracks[trackId] = track.copyWith(muted: newMuted);

    // Sync with engine
    if (_ffi.isLoaded && track.engineTrackId >= 0) {
      _ffi.setTrackMute(track.engineTrackId, newMuted);
    }

    notifyListeners();
  }

  /// Toggle track solo
  void toggleSolo(int trackId) {
    final track = _tracks[trackId];
    if (track == null) return;

    final newSoloed = !track.soloed;
    _tracks[trackId] = track.copyWith(soloed: newSoloed);

    // Sync with engine
    if (_ffi.isLoaded && track.engineTrackId >= 0) {
      _ffi.setTrackSolo(track.engineTrackId, newSoloed);
    }

    // Update solo state
    _updateSoloState();
    notifyListeners();
  }

  /// Clear all solos
  void clearAllSolos() {
    for (final trackId in _tracks.keys) {
      final track = _tracks[trackId]!;
      if (track.soloed) {
        _tracks[trackId] = track.copyWith(soloed: false);
        if (_ffi.isLoaded && track.engineTrackId >= 0) {
          _ffi.setTrackSolo(track.engineTrackId, false);
        }
      }
    }
    _hasSoloedTracks = false;
    notifyListeners();
  }

  void _updateSoloState() {
    _hasSoloedTracks = _tracks.values.any((t) => t.soloed);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING INTEGRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Arm track for recording
  bool armTrack(int trackId) {
    final track = _tracks[trackId];
    if (track == null) return false;

    // Arm in recording system
    final success = api.recordingArmTrack(
      track.engineTrackId >= 0 ? track.engineTrackId : trackId,
      numChannels: track.inputChannels,
    );

    if (success) {
      _tracks[trackId] = track.copyWith(armed: true);
      notifyListeners();
    }

    return success;
  }

  /// Disarm track
  bool disarmTrack(int trackId) {
    final track = _tracks[trackId];
    if (track == null) return false;

    // Disarm in recording system
    final success = api.recordingDisarmTrack(
      track.engineTrackId >= 0 ? track.engineTrackId : trackId,
    );

    if (success) {
      _tracks[trackId] = track.copyWith(armed: false);
      notifyListeners();
    }

    return success;
  }

  /// Toggle arm state
  bool toggleArm(int trackId) {
    final track = _tracks[trackId];
    if (track == null) return false;

    return track.armed ? disarmTrack(trackId) : armTrack(trackId);
  }

  /// Start recording on track
  Future<String?> startRecording(int trackId) async {
    final track = _tracks[trackId];
    if (track == null || !track.armed) return null;

    final recordId = track.engineTrackId >= 0 ? track.engineTrackId : trackId;
    final path = api.recordingStartTrack(recordId);

    if (path != null) {
      _tracks[trackId] = track.copyWith(
        isRecording: true,
        recordingPath: path,
      );
      notifyListeners();
    }

    return path;
  }

  /// Stop recording on track
  Future<String?> stopRecording(int trackId) async {
    final track = _tracks[trackId];
    if (track == null || !track.isRecording) return null;

    final recordId = track.engineTrackId >= 0 ? track.engineTrackId : trackId;
    final path = api.recordingStopTrack(recordId);

    _tracks[trackId] = track.copyWith(
      isRecording: false,
      recordingPath: path,
    );
    notifyListeners();

    return path;
  }

  /// Start recording on all armed tracks
  Future<int> startRecordingAll() async {
    int count = 0;
    for (final track in armedTracks) {
      final path = await startRecording(track.id);
      if (path != null) count++;
    }
    return count;
  }

  /// Stop recording on all tracks
  Future<int> stopRecordingAll() async {
    int count = 0;
    for (final track in recordingTracks) {
      final path = await stopRecording(track.id);
      if (path != null) count++;
    }
    return count;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEVELS & ROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set track volume (0.0 - 1.0)
  void setVolume(int trackId, double volume) {
    final track = _tracks[trackId];
    if (track == null) return;

    final clampedVolume = volume.clamp(0.0, 1.0);
    _tracks[trackId] = track.copyWith(volume: clampedVolume);

    // Sync with engine
    if (_ffi.isLoaded && track.engineTrackId >= 0) {
      _ffi.setTrackVolume(track.engineTrackId, clampedVolume);
    }

    notifyListeners();
  }

  /// Set track pan (-1.0 to 1.0)
  void setPan(int trackId, double pan) {
    final track = _tracks[trackId];
    if (track == null) return;

    final clampedPan = pan.clamp(-1.0, 1.0);
    _tracks[trackId] = track.copyWith(pan: clampedPan);

    // Sync with engine
    if (_ffi.isLoaded && track.engineTrackId >= 0) {
      _ffi.setTrackPan(track.engineTrackId, clampedPan);
    }

    notifyListeners();
  }

  /// Set track input source
  void setInputSource(int trackId, TrackInputSource source) {
    final track = _tracks[trackId];
    if (track == null) return;

    _tracks[trackId] = track.copyWith(inputSource: source);

    // TODO: Sync input routing with engine

    notifyListeners();
  }

  /// Set track output
  void setOutput(int trackId, TrackOutput output) {
    final track = _tracks[trackId];
    if (track == null) return;

    _tracks[trackId] = track.copyWith(output: output);

    // TODO: Sync output routing with engine

    notifyListeners();
  }

  /// Toggle input monitoring
  void toggleMonitorInput(int trackId) {
    final track = _tracks[trackId];
    if (track == null) return;

    _tracks[trackId] = track.copyWith(monitorInput: !track.monitorInput);

    // TODO: Sync with engine

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLUGIN INSERTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set plugin insert at slot
  void setInsert(int trackId, int slotIndex, String? instanceId) {
    final track = _tracks[trackId];
    if (track == null || slotIndex < 0 || slotIndex >= 8) return;

    final newInserts = List<String?>.from(track.inserts);
    newInserts[slotIndex] = instanceId;

    _tracks[trackId] = track.copyWith(inserts: newInserts);
    notifyListeners();
  }

  /// Remove plugin from slot
  void removeInsert(int trackId, int slotIndex) {
    setInsert(trackId, slotIndex, null);
  }

  /// Get insert instance IDs for track
  List<String?> getInserts(int trackId) {
    return _tracks[trackId]?.inserts ?? List.filled(8, null);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  int _getNextColor() {
    final color = _trackColors[_colorIndex % _trackColors.length];
    _colorIndex++;
    return color;
  }

  /// Refresh state from engine
  Future<void> refresh() async {
    // Sync armed/recording counts with recording system
    final armedCount = api.recordingArmedCount();
    final recordingCount = api.recordingRecordingCount();

    // Update track states based on engine state
    for (final trackId in _tracks.keys) {
      final track = _tracks[trackId]!;
      final recordId = track.engineTrackId >= 0 ? track.engineTrackId : trackId;

      final isArmed = api.recordingIsArmed(recordId);
      final isRecording = api.recordingIsRecording(recordId);

      if (track.armed != isArmed || track.isRecording != isRecording) {
        _tracks[trackId] = track.copyWith(
          armed: isArmed,
          isRecording: isRecording,
        );
      }
    }

    notifyListeners();
    debugPrint('[TrackProvider] Refresh: $armedCount armed, $recordingCount recording');
  }

  @override
  void dispose() {
    // No resources to clean up currently
    super.dispose();
  }
}

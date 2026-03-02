import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../src/rust/native_ffi.dart';

/// GAD Track Type — mirrors Rust GadTrackType enum (8 types per MASTER_SPEC §15).
enum GadTrackType {
  musicLayer,
  transient,
  reelBound,
  cascadeLayer,
  jackpotLadder,
  ui,
  system,
  ambientPad;

  String get label => switch (this) {
    musicLayer => 'Music Layer',
    transient => 'Transient',
    reelBound => 'Reel-Bound',
    cascadeLayer => 'Cascade Layer',
    jackpotLadder => 'Jackpot Ladder',
    ui => 'UI',
    system => 'System',
    ambientPad => 'Ambient/Pad',
  };

  int get index_ => switch (this) {
    musicLayer => 0,
    transient => 1,
    reelBound => 2,
    cascadeLayer => 3,
    jackpotLadder => 4,
    ui => 5,
    system => 6,
    ambientPad => 7,
  };

  int get color => switch (this) {
    musicLayer => 0xFF9370DB,
    transient => 0xFFFF9040,
    reelBound => 0xFF40C8FF,
    cascadeLayer => 0xFF40FF90,
    jackpotLadder => 0xFFFFD740,
    ui => 0xFF9E9E9E,
    system => 0xFF607D8B,
    ambientPad => 0xFF4DB6AC,
  };
}

/// GAD Timeline Marker Type.
enum GadMarkerType {
  cue,
  hookAnchor,
  regionStart,
  regionEnd,
  loopPoint,
  bakeBoundary;

  int get index_ => switch (this) {
    cue => 0,
    hookAnchor => 1,
    regionStart => 2,
    regionEnd => 3,
    loopPoint => 4,
    bakeBoundary => 5,
  };

  String get label => switch (this) {
    cue => 'Cue',
    hookAnchor => 'Hook Anchor',
    regionStart => 'Region Start',
    regionEnd => 'Region End',
    loopPoint => 'Loop Point',
    bakeBoundary => 'Bake Boundary',
  };
}

/// Bake step info for progress visualization.
class BakeStepInfo {
  final String name;
  final bool passed;
  final String? error;

  const BakeStepInfo({required this.name, required this.passed, this.error});
}

/// GAD Track data (parsed from JSON).
class GadTrackData {
  final String id;
  final String name;
  final String trackType;
  final String? audioPath;
  final String? hookBinding;
  final double emotionalBias;
  final double energyWeight;
  final int harmonicDensity;

  const GadTrackData({
    required this.id,
    required this.name,
    required this.trackType,
    this.audioPath,
    this.hookBinding,
    this.emotionalBias = 0.0,
    this.energyWeight = 0.5,
    this.harmonicDensity = 1,
  });

  factory GadTrackData.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    final binding = meta['event_binding'] as Map<String, dynamic>?;
    return GadTrackData(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      trackType: json['track_type'] as String? ?? 'MusicLayer',
      audioPath: json['audio_path'] as String?,
      hookBinding: binding?['hook'] as String?,
      emotionalBias: (meta['emotional_bias'] as num?)?.toDouble() ?? 0.0,
      energyWeight: (meta['energy_weight'] as num?)?.toDouble() ?? 0.5,
      harmonicDensity: (meta['harmonic_density'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Provider for the GAD (Gameplay-Aware DAW) system.
///
/// Manages dual timeline, 8-type track system, and Bake To Slot pipeline.
/// Register as GetIt singleton (Layer 7).
class GadProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  bool _initialized = false;
  bool get initialized => _initialized;

  // Project state
  double _bpm = 120.0;
  int _lengthBars = 32;
  List<GadTrackData> _tracks = [];

  // Bake state
  bool _baking = false;
  double _bakeProgress = 0.0;
  List<BakeStepInfo> _bakeSteps = [];
  bool? _bakeSuccess;

  // Validation
  List<String> _validationErrors = [];

  // Getters
  double get bpm => _bpm;
  int get lengthBars => _lengthBars;
  List<GadTrackData> get tracks => _tracks;
  bool get baking => _baking;
  double get bakeProgress => _bakeProgress;
  List<BakeStepInfo> get bakeSteps => _bakeSteps;
  bool? get bakeSuccess => _bakeSuccess;
  List<String> get validationErrors => _validationErrors;
  int get trackCount => _tracks.length;

  GadProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  /// Initialize GAD with default project (120 BPM, 32 bars, 8 tracks).
  bool initialize() {
    if (_initialized) return true;
    final ok = _ffi.gadCreateProject();
    if (ok) {
      _initialized = true;
      _refreshProject();
      notifyListeners();
    }
    return ok;
  }

  /// Initialize with custom settings.
  bool initializeCustom({double bpm = 120.0, int lengthBars = 32, int sampleRate = 48000}) {
    final ok = _ffi.gadCreateProjectCustom(bpm, lengthBars, sampleRate);
    if (ok) {
      _initialized = true;
      _bpm = bpm;
      _lengthBars = lengthBars;
      _refreshProject();
      notifyListeners();
    }
    return ok;
  }

  /// Add a track.
  bool addTrack(String name, GadTrackType type) {
    final ok = _ffi.gadAddTrack(name, type.index_);
    if (ok) _refreshProject();
    return ok;
  }

  /// Remove a track by ID.
  bool removeTrack(String trackId) {
    final ok = _ffi.gadRemoveTrack(trackId);
    if (ok) _refreshProject();
    return ok;
  }

  /// Set audio path for a track.
  bool setTrackAudio(String trackId, String audioPath) {
    final ok = _ffi.gadSetTrackAudio(trackId, audioPath);
    if (ok) _refreshProject();
    return ok;
  }

  /// Set event binding for a track.
  bool setTrackBinding(String trackId, String hook, {String substate = 'base'}) {
    final ok = _ffi.gadSetTrackBinding(trackId, hook, substate);
    if (ok) _refreshProject();
    return ok;
  }

  /// Set track metadata.
  bool setTrackMetadata(String trackId, {
    double? emotionalBias,
    double? energyWeight,
    int? harmonicDensity,
    double? turboReduction,
  }) {
    // Get current values for fields not being changed
    final track = _tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return false;

    final ok = _ffi.gadSetTrackMetadata(
      trackId,
      emotionalBias ?? track.emotionalBias,
      energyWeight ?? track.energyWeight,
      harmonicDensity ?? track.harmonicDensity,
      turboReduction ?? 1.0,
    );
    if (ok) _refreshProject();
    return ok;
  }

  /// Set BPM.
  bool setBpm(double bpm) {
    final ok = _ffi.gadSetBpm(bpm);
    if (ok) {
      _bpm = bpm;
      notifyListeners();
    }
    return ok;
  }

  /// Add timeline anchor.
  bool addAnchor(String id, int bar, int beat, int tick, int gameplayFrame, String hook) {
    return _ffi.gadAddAnchor(id, bar, beat, tick, gameplayFrame, hook);
  }

  /// Add timeline marker.
  bool addMarker(String id, String name, GadMarkerType type,
      int bar, int beat, int tick, {int color = 0xFF00FF00}) {
    return _ffi.gadAddMarker(id, name, type.index_, bar, beat, tick, color);
  }

  /// Run the 11-step Bake To Slot pipeline.
  bool bake() {
    _baking = true;
    _bakeSuccess = null;
    _bakeSteps = [];
    notifyListeners();

    final ok = _ffi.gadBake();
    _baking = false;
    _bakeSuccess = ok;
    _bakeProgress = _ffi.gadBakeProgress();

    // Parse result for step details
    final json = _ffi.gadBakeResultJson();
    if (json != null) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final steps = data['steps'] as List<dynamic>? ?? [];
        _bakeSteps = steps.map((s) {
          final step = s as Map<String, dynamic>;
          return BakeStepInfo(
            name: step['name'] as String? ?? '',
            passed: step['passed'] as bool? ?? false,
            error: step['error'] as String?,
          );
        }).toList();
      } catch (e) {
        assert(() { debugPrint('[GAD] Failed to parse test steps: $e'); return true; }());
      }
    }

    notifyListeners();
    return ok;
  }

  /// Validate project.
  void validate() {
    final json = _ffi.gadValidationErrorsJson();
    if (json != null) {
      try {
        final errors = (jsonDecode(json) as List<dynamic>).cast<String>();
        _validationErrors = errors;
      } catch (_) {
        _validationErrors = [];
      }
    } else {
      _validationErrors = [];
    }
    notifyListeners();
  }

  /// Get timeline JSON for display.
  String? get timelineJson => _ffi.gadTimelineJson();

  /// Refresh project state from engine.
  void _refreshProject() {
    final json = _ffi.gadProjectJson();
    if (json != null) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final config = data['config'] as Map<String, dynamic>? ?? {};
        _bpm = (config['bpm'] as num?)?.toDouble() ?? 120.0;
        _lengthBars = (config['length_bars'] as num?)?.toInt() ?? 32;

        final trackList = data['tracks'] as List<dynamic>? ?? [];
        _tracks = trackList
            .map((t) => GadTrackData.fromJson(t as Map<String, dynamic>))
            .toList();
      } catch (e) {
        assert(() { debugPrint('[GAD] Failed to parse track data: $e'); return true; }());
      }
    }
    notifyListeners();
  }
}

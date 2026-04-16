// T7.2–T7.4: Spatial Audio Service — VR slot positioning, HRTF, Ambisonics export
//
// Wraps rf-slot-spatial via FFI.
// T7.2: 3D scene management for VR slot audio positioning
// T7.3: HRTF binaural render configuration
// T7.4: Ambisonics B-format export metadata generation

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────

/// Spherical audio position
class SphericalPosition {
  final double azimuthDeg;
  final double elevationDeg;
  final double distanceM;

  const SphericalPosition({
    required this.azimuthDeg,
    required this.elevationDeg,
    this.distanceM = 1.0,
  });

  factory SphericalPosition.fromJson(Map<String, dynamic> json) => SphericalPosition(
    azimuthDeg: (json['azimuth_deg'] as num).toDouble(),
    elevationDeg: (json['elevation_deg'] as num).toDouble(),
    distanceM: (json['distance_m'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'azimuth_deg': azimuthDeg,
    'elevation_deg': elevationDeg,
    'distance_m': distanceM,
  };

  static const SphericalPosition front = SphericalPosition(azimuthDeg: 0, elevationDeg: 0);
}

/// Attenuation curve type
enum AttenuationCurveType { inverseSquare, linear, none, maxDistance }

/// Distance attenuation model
class AttenuationCurve {
  final AttenuationCurveType type;
  final double? slope;
  final double? maxDistanceM;

  const AttenuationCurve.inverseSquare() : type = AttenuationCurveType.inverseSquare, slope = null, maxDistanceM = null;
  const AttenuationCurve.none() : type = AttenuationCurveType.none, slope = null, maxDistanceM = null;
  const AttenuationCurve.linear(double slope) : type = AttenuationCurveType.linear, slope = slope, maxDistanceM = null;
  const AttenuationCurve.maxDistance(double maxM) : type = AttenuationCurveType.maxDistance, slope = null, maxDistanceM = maxM;

  Map<String, dynamic> toJson() {
    switch (type) {
      case AttenuationCurveType.inverseSquare: return {'InverseSquare': null};
      case AttenuationCurveType.none: return {'None': null};
      case AttenuationCurveType.linear: return {'Linear': {'slope': slope}};
      case AttenuationCurveType.maxDistance: return {'MaxDistance': {'max_m': maxDistanceM}};
    }
  }

  factory AttenuationCurve.fromJson(dynamic json) {
    if (json is String || json == null) return const AttenuationCurve.inverseSquare();
    final map = json as Map<String, dynamic>;
    if (map.containsKey('None')) return const AttenuationCurve.none();
    if (map.containsKey('Linear')) return AttenuationCurve.linear((map['Linear']['slope'] as num).toDouble());
    if (map.containsKey('MaxDistance')) return AttenuationCurve.maxDistance((map['MaxDistance']['max_m'] as num).toDouble());
    return const AttenuationCurve.inverseSquare();
  }
}

/// HRTF configuration for a source (T7.3)
class HrtfConfig {
  final bool enabled;
  final int interpolationQuality;
  final bool nearfieldCompensation;

  const HrtfConfig({
    this.enabled = true,
    this.interpolationQuality = 1,
    this.nearfieldCompensation = false,
  });

  factory HrtfConfig.fromJson(Map<String, dynamic> json) => HrtfConfig(
    enabled: json['enabled'] as bool,
    interpolationQuality: json['interpolation_quality'] as int,
    nearfieldCompensation: json['nearfield_compensation'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'interpolation_quality': interpolationQuality,
    'nearfield_compensation': nearfieldCompensation,
  };
}

/// A 3D spatial audio source in the slot scene
class SpatialAudioSource {
  final String eventId;
  final String label;
  final SphericalPosition position;
  final AttenuationCurve attenuation;
  final HrtfConfig hrtf;
  final bool includeInAmbisonics;
  final double gain;

  const SpatialAudioSource({
    required this.eventId,
    required this.label,
    required this.position,
    this.attenuation = const AttenuationCurve.inverseSquare(),
    this.hrtf = const HrtfConfig(),
    this.includeInAmbisonics = true,
    this.gain = 1.0,
  });

  factory SpatialAudioSource.fromJson(Map<String, dynamic> json) => SpatialAudioSource(
    eventId: json['event_id'] as String,
    label: json['label'] as String,
    position: SphericalPosition.fromJson(json['position'] as Map<String, dynamic>),
    attenuation: AttenuationCurve.fromJson(json['attenuation']),
    hrtf: HrtfConfig.fromJson(json['hrtf'] as Map<String, dynamic>),
    includeInAmbisonics: json['include_in_ambisonics'] as bool,
    gain: (json['gain'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'label': label,
    'position': position.toJson(),
    'attenuation': attenuation.toJson(),
    'hrtf': hrtf.toJson(),
    'include_in_ambisonics': includeInAmbisonics,
    'gain': gain,
  };

  SpatialAudioSource copyWith({
    String? eventId, String? label, SphericalPosition? position,
    AttenuationCurve? attenuation, HrtfConfig? hrtf,
    bool? includeInAmbisonics, double? gain,
  }) => SpatialAudioSource(
    eventId: eventId ?? this.eventId,
    label: label ?? this.label,
    position: position ?? this.position,
    attenuation: attenuation ?? this.attenuation,
    hrtf: hrtf ?? this.hrtf,
    includeInAmbisonics: includeInAmbisonics ?? this.includeInAmbisonics,
    gain: gain ?? this.gain,
  );
}

/// Complete 3D scene for a slot game
class SpatialSlotScene {
  final String gameId;
  final List<SpatialAudioSource> sources;
  final String description;

  const SpatialSlotScene({
    required this.gameId,
    this.sources = const [],
    this.description = '',
  });

  factory SpatialSlotScene.fromJson(Map<String, dynamic> json) => SpatialSlotScene(
    gameId: json['game_id'] as String,
    sources: (json['sources'] as List)
        .map((e) => SpatialAudioSource.fromJson(e as Map<String, dynamic>))
        .toList(),
    description: json['description'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'game_id': gameId,
    'sources': sources.map((s) => s.toJson()).toList(),
    'listener': {
      'position': [0.0, 0.0, -1.5],
      'forward': [0.0, 0.0, 1.0],
      'up': [0.0, 1.0, 0.0],
      'head_radius_m': 0.0875,
    },
    'description': description,
  };

  SpatialSlotScene withSource(SpatialAudioSource source) {
    final updated = sources.map((s) => s.eventId == source.eventId ? source : s).toList();
    if (!sources.any((s) => s.eventId == source.eventId)) updated.add(source);
    return SpatialSlotScene(gameId: gameId, sources: updated, description: description);
  }

  SpatialSlotScene withoutSource(String eventId) => SpatialSlotScene(
    gameId: gameId,
    sources: sources.where((s) => s.eventId != eventId).toList(),
    description: description,
  );
}

/// Available layout presets
class SpatialLayoutPreset {
  final String name;
  final String description;
  const SpatialLayoutPreset({required this.name, required this.description});
  factory SpatialLayoutPreset.fromJson(Map<String, dynamic> json) =>
      SpatialLayoutPreset(name: json['name'] as String, description: json['description'] as String);
}

/// Ambisonic order
enum AmbisonicOrder { first, second, third }
extension AmbisonicOrderExt on AmbisonicOrder {
  String get rustName => ['First', 'Second', 'Third'][index];
  int get channelCount => [4, 9, 16][index];
  String get displayName => ['1st Order FOA (4ch)', '2nd Order SOA (9ch)', '3rd Order TOA (16ch)'][index];
}

/// Spatial export format
enum SpatialExportFormat { binaural, ambisonics, both }

/// Ambisonics export configuration
class AmbisonicsExportConfig {
  final SpatialExportFormat format;
  final AmbisonicOrder order;
  final int sampleRate;
  final bool normalizeOutput;
  final bool metadataOnly;

  const AmbisonicsExportConfig({
    this.format = SpatialExportFormat.ambisonics,
    this.order = AmbisonicOrder.first,
    this.sampleRate = 48000,
    this.normalizeOutput = true,
    this.metadataOnly = true,
  });

  Map<String, dynamic> toJson() {
    dynamic fmtJson;
    switch (format) {
      case SpatialExportFormat.binaural:    fmtJson = 'Binaural'; break;
      case SpatialExportFormat.ambisonics:  fmtJson = {'Ambisonics': order.rustName}; break;
      case SpatialExportFormat.both:        fmtJson = {'Both': order.rustName}; break;
    }
    return {
      'format': fmtJson,
      'sample_rate': sampleRate,
      'normalize_output': normalizeOutput,
      'metadata_only': metadataOnly,
    };
  }
}

/// Ambisonics coefficients for a source
class AmbisonicsCoefficients {
  final double w, x, y, z;
  final List<double> higherOrder;

  const AmbisonicsCoefficients({
    required this.w, required this.x, required this.y, required this.z,
    this.higherOrder = const [],
  });

  factory AmbisonicsCoefficients.fromJson(Map<String, dynamic> json) => AmbisonicsCoefficients(
    w: (json['w'] as num).toDouble(),
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    higherOrder: (json['higher_order'] as List).map((e) => (e as num).toDouble()).toList(),
  );
}

/// Per-source spec in the export manifest
class SpatialSourceSpec {
  final String eventId;
  final String label;
  final double azimuthDeg;
  final double elevationDeg;
  final double distanceM;
  final double gain;
  final double effectiveGain;
  final bool includeInAmbisonics;
  final AmbisonicsCoefficients ambisonicsCoefficients;

  const SpatialSourceSpec({
    required this.eventId,
    required this.label,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.distanceM,
    required this.gain,
    required this.effectiveGain,
    required this.includeInAmbisonics,
    required this.ambisonicsCoefficients,
  });

  factory SpatialSourceSpec.fromJson(Map<String, dynamic> json) => SpatialSourceSpec(
    eventId: json['event_id'] as String,
    label: json['label'] as String,
    azimuthDeg: (json['azimuth_deg'] as num).toDouble(),
    elevationDeg: (json['elevation_deg'] as num).toDouble(),
    distanceM: (json['distance_m'] as num).toDouble(),
    gain: (json['gain'] as num).toDouble(),
    effectiveGain: (json['effective_gain'] as num).toDouble(),
    includeInAmbisonics: json['include_in_ambisonics'] as bool,
    ambisonicsCoefficients: AmbisonicsCoefficients.fromJson(
        json['ambisonics_coefficients'] as Map<String, dynamic>),
  );
}

/// Complete spatial export manifest
class SpatialExportManifest {
  final String gameId;
  final String format;
  final String orderName;
  final int channelCount;
  final int sourceCount;
  final List<SpatialSourceSpec> sources;
  final String generatedAt;

  const SpatialExportManifest({
    required this.gameId,
    required this.format,
    required this.orderName,
    required this.channelCount,
    required this.sourceCount,
    required this.sources,
    required this.generatedAt,
  });

  factory SpatialExportManifest.fromJson(Map<String, dynamic> json) => SpatialExportManifest(
    gameId: json['game_id'] as String,
    format: json['format'] as String,
    orderName: json['order_name'] as String,
    channelCount: json['channel_count'] as int,
    sourceCount: json['source_count'] as int,
    sources: (json['sources'] as List)
        .map((e) => SpatialSourceSpec.fromJson(e as Map<String, dynamic>))
        .toList(),
    generatedAt: json['generated_at'] as String,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SpatialAudioService (T7.2–T7.4)
// ─────────────────────────────────────────────────────────────────────────────

/// 3D spatial audio scene management and export service.
///
/// Usage:
/// ```dart
/// final svc = sl<SpatialAudioService>();
///
/// // Load default desktop layout for a game
/// await svc.loadPreset(gameId: 'golden_phoenix', preset: 'desktop');
///
/// // Move JACKPOT source to above player for VR
/// svc.updateSource(svc.scene!.sources[0].copyWith(
///   position: SphericalPosition(azimuthDeg: 0, elevationDeg: 60, distanceM: 3.0),
/// ));
///
/// // Generate Ambisonics export metadata (T7.4)
/// final manifest = await svc.generateExportManifest(
///   order: AmbisonicOrder.third,
/// );
/// ```
class SpatialAudioService extends ChangeNotifier {
  final NativeFFI _ffi;

  SpatialSlotScene? _scene;
  List<SpatialLayoutPreset> _availablePresets = [];
  SpatialExportManifest? _lastManifest;
  bool _isWorking = false;

  SpatialAudioService(this._ffi);

  SpatialSlotScene? get scene => _scene;
  List<SpatialLayoutPreset> get availablePresets => List.unmodifiable(_availablePresets);
  SpatialExportManifest? get lastManifest => _lastManifest;
  bool get isWorking => _isWorking;
  bool get hasScene => _scene != null && (_scene?.sources.isNotEmpty ?? false);

  /// Load available layout presets from the Rust engine.
  void loadPresets() {
    final json = _ffi.spatialAvailablePresets();
    if (json != null) {
      final list = jsonDecode(json) as List;
      _availablePresets = list
          .map((e) => SpatialLayoutPreset.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }

  /// Load a predefined layout preset for a game.
  ///
  /// [preset]: "desktop", "vr_standing", "vr_seated", "live_casino", "mobile"
  Future<void> loadPreset({required String gameId, required String preset}) async {
    _isWorking = true;
    notifyListeners();

    try {
      final sources = await Future(() {
        final json = _ffi.spatialLayoutGenerate(gameId, preset);
        if (json == null) return <SpatialAudioSource>[];
        final list = jsonDecode(json) as List;
        return list
            .map((e) => SpatialAudioSource.fromJson(e as Map<String, dynamic>))
            .toList();
      });

      _scene = SpatialSlotScene(gameId: gameId, sources: sources);
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  /// Update a specific source in the current scene.
  void updateSource(SpatialAudioSource source) {
    if (_scene == null) return;
    _scene = _scene!.withSource(source);
    notifyListeners();
  }

  /// Remove a source from the current scene.
  void removeSource(String eventId) {
    if (_scene == null) return;
    _scene = _scene!.withoutSource(eventId);
    notifyListeners();
  }

  /// Set scene from external JSON (e.g., loaded from disk).
  void loadScene(SpatialSlotScene scene) {
    _scene = scene;
    notifyListeners();
  }

  /// Generate Ambisonics / Binaural export manifest (T7.4 / T7.3).
  ///
  /// This generates metadata JSON describing how to spatialize each event
  /// in the requested format. Audio rendering is done by the audio engine.
  Future<SpatialExportManifest?> generateExportManifest({
    SpatialExportFormat format = SpatialExportFormat.ambisonics,
    AmbisonicOrder order = AmbisonicOrder.first,
    bool metadataOnly = true,
  }) async {
    if (_scene == null) return null;
    _isWorking = true;
    notifyListeners();

    try {
      final config = AmbisonicsExportConfig(
        format: format,
        order: order,
        metadataOnly: metadataOnly,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final sceneJson = jsonEncode(_scene!.toJson());
      final configJson = jsonEncode(config.toJson());

      final manifest = await Future(() {
        final json = _ffi.spatialExportManifest(sceneJson, configJson, now);
        if (json == null) return null;
        return SpatialExportManifest.fromJson(jsonDecode(json) as Map<String, dynamic>);
      });

      _lastManifest = manifest;
      return manifest;
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }
}

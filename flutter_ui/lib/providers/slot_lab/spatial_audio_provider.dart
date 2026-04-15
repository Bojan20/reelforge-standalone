/// 3D Spatial Audio for VR/AR Slots™ (STUB 9)
///
/// "Hear the jackpot travel across the room."
///
/// Spatial audio authoring module for VR/AR slot machine deployment.
/// 3D casino floor environment with per-reel spatialization, head tracking,
/// room acoustics simulation, and multi-platform VR export.
///
/// See: FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.md §STUB9
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// =============================================================================
// 3D POSITION
// =============================================================================

/// 3D position in the virtual casino space (meters)
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);
  const Vec3.zero() : x = 0, y = 0, z = 0;

  double distanceTo(Vec3 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  Map<String, double> toJson() => {'x': x, 'y': y, 'z': z};
}

// =============================================================================
// SURFACE MATERIALS
// =============================================================================

/// Casino floor surface materials — affect reflections and reverb
enum SurfaceMaterial {
  carpet,
  marble,
  hardwood,
  glass,
  concrete,
  fabric;

  String get displayName => switch (this) {
        SurfaceMaterial.carpet => 'Carpet',
        SurfaceMaterial.marble => 'Marble',
        SurfaceMaterial.hardwood => 'Hardwood',
        SurfaceMaterial.glass => 'Glass',
        SurfaceMaterial.concrete => 'Concrete',
        SurfaceMaterial.fabric => 'Fabric Panels',
      };

  /// Absorption coefficient (0 = fully reflective, 1 = fully absorptive)
  double get absorptionCoeff => switch (this) {
        SurfaceMaterial.carpet => 0.65,
        SurfaceMaterial.marble => 0.05,
        SurfaceMaterial.hardwood => 0.25,
        SurfaceMaterial.glass => 0.10,
        SurfaceMaterial.concrete => 0.15,
        SurfaceMaterial.fabric => 0.80,
      };

  /// High frequency absorption (relative to base coefficient)
  double get hfAbsorption => switch (this) {
        SurfaceMaterial.carpet => 0.85,
        SurfaceMaterial.marble => 0.08,
        SurfaceMaterial.hardwood => 0.35,
        SurfaceMaterial.glass => 0.15,
        SurfaceMaterial.concrete => 0.25,
        SurfaceMaterial.fabric => 0.90,
      };
}

// =============================================================================
// HRTF PROFILES
// =============================================================================

/// Head-Related Transfer Function profile
enum HrtfProfile {
  generic,
  smallHead,
  largeHead,
  customMeasured;

  String get displayName => switch (this) {
        HrtfProfile.generic => 'Generic HRTF',
        HrtfProfile.smallHead => 'Small Head',
        HrtfProfile.largeHead => 'Large Head',
        HrtfProfile.customMeasured => 'Custom Measured',
      };

  /// Inter-aural time delay in microseconds
  double get itdMaxUs => switch (this) {
        HrtfProfile.generic => 660.0,
        HrtfProfile.smallHead => 580.0,
        HrtfProfile.largeHead => 740.0,
        HrtfProfile.customMeasured => 660.0,
      };
}

// =============================================================================
// VR EXPORT TARGETS
// =============================================================================

/// Spatial audio export format
enum SpatialExportFormat {
  ambisonicsB,     // Ambisonics B-format (platform-agnostic)
  metaQuest,       // Meta Quest SDK format
  appleVisionPro,  // Apple Vision Pro AudioGraph
  playstationVr2,  // PlayStation VR2 format
  steamVr,         // SteamVR / OpenXR spatial audio
  webXr;           // WebXR spatial audio API

  String get displayName => switch (this) {
        SpatialExportFormat.ambisonicsB => 'Ambisonics B-Format',
        SpatialExportFormat.metaQuest => 'Meta Quest SDK',
        SpatialExportFormat.appleVisionPro => 'Apple Vision Pro',
        SpatialExportFormat.playstationVr2 => 'PlayStation VR2',
        SpatialExportFormat.steamVr => 'SteamVR / OpenXR',
        SpatialExportFormat.webXr => 'WebXR Spatial Audio',
      };
}

// =============================================================================
// 3D SCENE OBJECTS
// =============================================================================

/// A slot machine in the 3D casino scene
class SpatialSlotMachine {
  final String id;
  final String name;
  final Vec3 position;
  final double rotationY;  // Rotation around Y axis (degrees)
  final int reelCount;
  final double cabinetWidth;   // meters
  final double cabinetHeight;  // meters

  const SpatialSlotMachine({
    required this.id,
    required this.name,
    required this.position,
    this.rotationY = 0,
    this.reelCount = 5,
    this.cabinetWidth = 0.8,
    this.cabinetHeight = 1.5,
  });

  /// Get 3D position of a specific reel
  Vec3 reelPosition(int reelIndex) {
    final spacing = cabinetWidth / reelCount;
    final offset = (reelIndex - reelCount / 2) * spacing;
    // Rotate offset by machine rotation
    final radY = rotationY * math.pi / 180;
    return Vec3(
      position.x + offset * math.cos(radY),
      position.y + cabinetHeight * 0.6, // Reel height
      position.z + offset * math.sin(radY),
    );
  }
}

/// Casino room environment
class CasinoEnvironment {
  final double width;   // meters
  final double depth;   // meters
  final double height;  // meters (ceiling)
  final SurfaceMaterial floor;
  final SurfaceMaterial walls;
  final SurfaceMaterial ceiling;
  final double crowdDensity;  // 0-1 (more people = more ambient noise)

  const CasinoEnvironment({
    this.width = 30.0,
    this.depth = 20.0,
    this.height = 4.0,
    this.floor = SurfaceMaterial.carpet,
    this.walls = SurfaceMaterial.fabric,
    this.ceiling = SurfaceMaterial.concrete,
    this.crowdDensity = 0.5,
  });

  /// Estimated RT60 reverb time (Sabine equation approximation)
  double get rt60 {
    final volume = width * depth * height;
    final floorArea = width * depth;
    final wallArea = 2 * (width + depth) * height;
    final ceilingArea = width * depth;
    final totalAbsorption =
        floorArea * this.floor.absorptionCoeff +
        wallArea * walls.absorptionCoeff +
        ceilingArea * this.ceiling.absorptionCoeff +
        crowdDensity * floorArea * 0.5; // People absorb sound
    return 0.161 * volume / totalAbsorption;
  }
}

/// Listener (player) position and orientation
class SpatialListener {
  Vec3 position;
  double headYaw;    // degrees, 0 = forward
  double headPitch;  // degrees, 0 = level

  SpatialListener({
    this.position = const Vec3(0, 1.5, 0), // Standing height
    this.headYaw = 0,
    this.headPitch = 0,
  });
}

// =============================================================================
// SPATIAL AUDIO SOURCE
// =============================================================================

/// A spatialized audio source in the 3D scene
class SpatialAudioSource {
  final String id;
  final String name;
  final Vec3 position;
  final double maxDistance;   // meters — beyond this, volume = 0
  final double refDistance;   // meters — full volume within this
  final double rolloffFactor; // 1.0 = realistic, <1 = slower falloff
  final bool isDirectional;
  final double coneAngle;    // degrees (if directional)
  final double coneOuterGain; // 0-1

  const SpatialAudioSource({
    required this.id,
    required this.name,
    required this.position,
    this.maxDistance = 20.0,
    this.refDistance = 1.0,
    this.rolloffFactor = 1.0,
    this.isDirectional = false,
    this.coneAngle = 360,
    this.coneOuterGain = 0.0,
  });

  /// Calculate distance attenuation using inverse distance model
  double attenuationAt(Vec3 listenerPos) {
    final dist = position.distanceTo(listenerPos);
    if (dist <= refDistance) return 1.0;
    if (dist >= maxDistance) return 0.0;
    return refDistance / (refDistance + rolloffFactor * (dist - refDistance));
  }
}

// =============================================================================
// SPATIAL AUDIO PROVIDER
// =============================================================================

/// 3D Spatial Audio for VR/AR Slots
class SpatialAudioProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  CasinoEnvironment _environment = const CasinoEnvironment();
  SpatialListener _listener = SpatialListener();
  HrtfProfile _hrtfProfile = HrtfProfile.generic;
  final Set<SpatialExportFormat> _selectedExports = {SpatialExportFormat.ambisonicsB};
  bool _headTrackingEnabled = true;
  bool _roomCorrectionEnabled = true;
  bool _hapticSyncEnabled = false;

  final List<SpatialSlotMachine> _slotMachines = [
    // Default scene: player's machine centered, neighbors at sides
    const SpatialSlotMachine(
      id: 'player_machine',
      name: 'Player Machine',
      position: Vec3(0, 0, 0),
    ),
    const SpatialSlotMachine(
      id: 'neighbor_left',
      name: 'Left Neighbor',
      position: Vec3(-1.2, 0, 0),
    ),
    const SpatialSlotMachine(
      id: 'neighbor_right',
      name: 'Right Neighbor',
      position: Vec3(1.2, 0, 0),
    ),
  ];

  final List<SpatialAudioSource> _ambientSources = [
    const SpatialAudioSource(
      id: 'crowd_left',
      name: 'Crowd Murmur L',
      position: Vec3(-10, 1.5, 5),
      maxDistance: 30,
      refDistance: 5,
    ),
    const SpatialAudioSource(
      id: 'crowd_right',
      name: 'Crowd Murmur R',
      position: Vec3(10, 1.5, 5),
      maxDistance: 30,
      refDistance: 5,
    ),
    const SpatialAudioSource(
      id: 'music_ceiling',
      name: 'Background Music',
      position: Vec3(0, 3.5, 3),
      maxDistance: 25,
      refDistance: 8,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  CasinoEnvironment get environment => _environment;
  SpatialListener get listener => _listener;
  HrtfProfile get hrtfProfile => _hrtfProfile;
  Set<SpatialExportFormat> get selectedExports => Set.unmodifiable(_selectedExports);
  bool get headTrackingEnabled => _headTrackingEnabled;
  bool get roomCorrectionEnabled => _roomCorrectionEnabled;
  bool get hapticSyncEnabled => _hapticSyncEnabled;
  List<SpatialSlotMachine> get slotMachines => List.unmodifiable(_slotMachines);
  List<SpatialAudioSource> get ambientSources => List.unmodifiable(_ambientSources);

  /// Estimated reverb time
  double get rt60 => _environment.rt60;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setEnvironment(CasinoEnvironment env) {
    _environment = env;
    notifyListeners();
  }

  void setFloorMaterial(SurfaceMaterial m) {
    _environment = CasinoEnvironment(
      width: _environment.width,
      depth: _environment.depth,
      height: _environment.height,
      floor: m,
      walls: _environment.walls,
      ceiling: _environment.ceiling,
      crowdDensity: _environment.crowdDensity,
    );
    notifyListeners();
  }

  void setWallMaterial(SurfaceMaterial m) {
    _environment = CasinoEnvironment(
      width: _environment.width,
      depth: _environment.depth,
      height: _environment.height,
      floor: _environment.floor,
      walls: m,
      ceiling: _environment.ceiling,
      crowdDensity: _environment.crowdDensity,
    );
    notifyListeners();
  }

  void setCrowdDensity(double v) {
    _environment = CasinoEnvironment(
      width: _environment.width,
      depth: _environment.depth,
      height: _environment.height,
      floor: _environment.floor,
      walls: _environment.walls,
      ceiling: _environment.ceiling,
      crowdDensity: v.clamp(0, 1),
    );
    notifyListeners();
  }

  void setHrtfProfile(HrtfProfile p) {
    _hrtfProfile = p;
    notifyListeners();
  }

  void setHeadTracking(bool v) {
    _headTrackingEnabled = v;
    notifyListeners();
  }

  void setRoomCorrection(bool v) {
    _roomCorrectionEnabled = v;
    notifyListeners();
  }

  void setHapticSync(bool v) {
    _hapticSyncEnabled = v;
    notifyListeners();
  }

  void toggleExportFormat(SpatialExportFormat f) {
    if (_selectedExports.contains(f)) {
      _selectedExports.remove(f);
    } else {
      _selectedExports.add(f);
    }
    notifyListeners();
  }

  void updateListenerPosition(Vec3 pos) {
    _listener.position = pos;
    notifyListeners();
  }

  void updateListenerRotation(double yaw, double pitch) {
    _listener.headYaw = yaw;
    _listener.headPitch = pitch;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPATIAL CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate attenuation for all ambient sources from listener position
  Map<String, double> getAmbientAttenuations() {
    return {
      for (final s in _ambientSources)
        s.id: s.attenuationAt(_listener.position),
    };
  }

  /// Calculate per-reel spatial parameters for player's machine
  List<Map<String, double>> getReelSpatialParams() {
    final machine = _slotMachines.firstWhere(
      (m) => m.id == 'player_machine',
      orElse: () => _slotMachines.first,
    );
    final result = <Map<String, double>>[];

    for (int i = 0; i < machine.reelCount; i++) {
      final reelPos = machine.reelPosition(i);
      final delta = reelPos - _listener.position;
      final dist = reelPos.distanceTo(_listener.position);

      // Calculate azimuth angle from listener
      final azimuth = math.atan2(delta.x, delta.z) * 180 / math.pi;
      // Calculate elevation angle
      final elevation = math.atan2(delta.y, math.sqrt(delta.x * delta.x + delta.z * delta.z)) * 180 / math.pi;

      result.add({
        'azimuth': azimuth,
        'elevation': elevation,
        'distance': dist,
        'attenuation': _distanceAttenuation(dist),
        'itd_us': _calculateItd(azimuth),
      });
    }
    return result;
  }

  double _distanceAttenuation(double dist) {
    if (dist <= 0.5) return 1.0;
    if (dist >= 20.0) return 0.0;
    return 0.5 / (0.5 + (dist - 0.5));
  }

  /// Inter-aural time delay based on azimuth angle
  double _calculateItd(double azimuthDeg) {
    final maxItd = _hrtfProfile.itdMaxUs;
    return maxItd * math.sin(azimuthDeg * math.pi / 180);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JACKPOT SPATIAL ANIMATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate jackpot "expanding from machine to fill room" spatial path
  /// Returns list of (time_ms, position) keyframes
  List<(double, Vec3, double)> generateJackpotExpansion({
    double durationMs = 5000,
    int keyframeCount = 20,
  }) {
    final machine = _slotMachines.firstWhere(
      (m) => m.id == 'player_machine',
      orElse: () => _slotMachines.first,
    );
    final origin = machine.position + const Vec3(0, 1.0, 0);
    final keyframes = <(double, Vec3, double)>[];

    for (int i = 0; i < keyframeCount; i++) {
      final t = i / (keyframeCount - 1);
      final timeMs = t * durationMs;

      // Expand radius over time (ease-out cubic)
      final easedT = 1 - (1 - t) * (1 - t) * (1 - t);
      final radius = easedT * _environment.width * 0.4;

      // Spiral upward
      final angle = t * math.pi * 4;
      final pos = Vec3(
        origin.x + radius * math.cos(angle),
        origin.y + easedT * (_environment.height - origin.y) * 0.8,
        origin.z + radius * math.sin(angle),
      );

      // Volume: start loud, sustain, then fade slightly
      final volume = t < 0.1
          ? t * 10 // Fade in
          : t > 0.8
              ? 1.0 - (t - 0.8) * 2.5 // Fade out
              : 1.0; // Sustain

      keyframes.add((timeMs, pos, volume.clamp(0.0, 1.0)));
    }
    return keyframes;
  }

  /// Generate win celebration left-to-right payline sweep
  List<(double, Vec3)> generatePaylineSweep({
    double durationMs = 2000,
  }) {
    final machine = _slotMachines.firstWhere(
      (m) => m.id == 'player_machine',
      orElse: () => _slotMachines.first,
    );
    final keyframes = <(double, Vec3)>[];

    for (int i = 0; i < machine.reelCount; i++) {
      final t = i / (machine.reelCount - 1);
      keyframes.add((t * durationMs, machine.reelPosition(i)));
    }
    return keyframes;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate spatial metadata for export
  Map<String, dynamic> exportSpatialMetadata() {
    return {
      'format': 'FluxForge_SpatialAudio',
      'version': '1.0',
      'environment': {
        'dimensions': {
          'width': _environment.width,
          'depth': _environment.depth,
          'height': _environment.height,
        },
        'materials': {
          'floor': _environment.floor.name,
          'walls': _environment.walls.name,
          'ceiling': _environment.ceiling.name,
        },
        'rt60': rt60,
        'crowd_density': _environment.crowdDensity,
      },
      'listener': {
        'position': _listener.position.toJson(),
        'head_yaw': _listener.headYaw,
        'head_pitch': _listener.headPitch,
        'hrtf_profile': _hrtfProfile.name,
        'itd_max_us': _hrtfProfile.itdMaxUs,
      },
      'features': {
        'head_tracking': _headTrackingEnabled,
        'room_correction': _roomCorrectionEnabled,
        'haptic_sync': _hapticSyncEnabled,
      },
      'slot_machines': _slotMachines.map((m) => {
            'id': m.id,
            'name': m.name,
            'position': m.position.toJson(),
            'rotation_y': m.rotationY,
            'reel_count': m.reelCount,
            'reel_positions': List.generate(
              m.reelCount,
              (i) => m.reelPosition(i).toJson(),
            ),
          }).toList(),
      'ambient_sources': _ambientSources.map((s) => {
            'id': s.id,
            'name': s.name,
            'position': s.position.toJson(),
            'max_distance': s.maxDistance,
            'ref_distance': s.refDistance,
            'rolloff': s.rolloffFactor,
          }).toList(),
      'export_formats': _selectedExports.map((f) => f.name).toList(),
    };
  }
}

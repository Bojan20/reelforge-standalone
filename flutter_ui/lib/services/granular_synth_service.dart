/// Granular Synthesis Service — ReaGranular-style Grain Engine
///
/// #28: 4 grain voices, min/max size, per-grain pan/level,
/// random variations, freeze mode.
///
/// Features:
/// - 4 independent grain voices with individual parameters
/// - Global grain size range (min/max in ms)
/// - Per-grain pan, level, pitch offset
/// - Random variation for size, pan, pitch (humanize)
/// - Freeze mode (capture buffer, loop grains from frozen snapshot)
/// - Grain density control (grains per second)
/// - Window shape (Hann, Hamming, Blackman, Triangle, Rectangle)
/// - Source position with jitter
/// - JSON serialization for persistence
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// GRAIN WINDOW SHAPE
// ═══════════════════════════════════════════════════════════════════════════════

/// Window function applied to each grain
enum GrainWindowShape {
  hann,
  hamming,
  blackman,
  triangle,
  rectangle,
}

extension GrainWindowShapeX on GrainWindowShape {
  String get label => ['Hann', 'Hamming', 'Blackman', 'Triangle', 'Rectangle'][index];
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRAIN VOICE
// ═══════════════════════════════════════════════════════════════════════════════

/// A single grain voice with individual parameters
class GrainVoice {
  final int index; // 0-3

  /// Level (0.0 to 1.0)
  double level;

  /// Pan (-1.0 left to 1.0 right)
  double pan;

  /// Pitch offset in semitones (-24 to +24)
  double pitchOffset;

  /// Delay offset in ms (stagger grains)
  double delayMs;

  /// Whether this voice is active
  bool active;

  GrainVoice({
    required this.index,
    this.level = 1.0,
    this.pan = 0.0,
    this.pitchOffset = 0.0,
    this.delayMs = 0.0,
    this.active = true,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'level': level,
    'pan': pan,
    'pitchOffset': pitchOffset,
    'delayMs': delayMs,
    'active': active,
  };

  factory GrainVoice.fromJson(Map<String, dynamic> json) => GrainVoice(
    index: json['index'] as int? ?? 0,
    level: (json['level'] as num?)?.toDouble() ?? 1.0,
    pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    pitchOffset: (json['pitchOffset'] as num?)?.toDouble() ?? 0.0,
    delayMs: (json['delayMs'] as num?)?.toDouble() ?? 0.0,
    active: json['active'] as bool? ?? true,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRANULAR PRESET
// ═══════════════════════════════════════════════════════════════════════════════

/// A named preset for the granular synth
class GranularPreset {
  final String id;
  String name;

  /// Grain size range in milliseconds
  double grainSizeMinMs;
  double grainSizeMaxMs;

  /// Grain density (grains per second)
  double density;

  /// Source position (0.0 to 1.0 normalized)
  double sourcePosition;

  /// Source position jitter (random offset range, 0.0 to 1.0)
  double positionJitter;

  /// Window shape
  GrainWindowShape windowShape;

  /// Random variation amounts (0.0 to 1.0)
  double sizeVariation;
  double panVariation;
  double pitchVariation;

  /// Global pitch offset in semitones
  double globalPitch;

  /// Global output level
  double outputLevel;

  /// Freeze mode
  bool frozen;

  /// Per-voice settings
  final List<GrainVoice> voices;

  GranularPreset({
    required this.id,
    required this.name,
    this.grainSizeMinMs = 20,
    this.grainSizeMaxMs = 100,
    this.density = 10,
    this.sourcePosition = 0.5,
    this.positionJitter = 0.1,
    this.windowShape = GrainWindowShape.hann,
    this.sizeVariation = 0.0,
    this.panVariation = 0.0,
    this.pitchVariation = 0.0,
    this.globalPitch = 0.0,
    this.outputLevel = 1.0,
    this.frozen = false,
    List<GrainVoice>? voices,
  }) : voices = voices ?? List.generate(4, (i) => GrainVoice(index: i));

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'grainSizeMinMs': grainSizeMinMs,
    'grainSizeMaxMs': grainSizeMaxMs,
    'density': density,
    'sourcePosition': sourcePosition,
    'positionJitter': positionJitter,
    'windowShape': windowShape.name,
    'sizeVariation': sizeVariation,
    'panVariation': panVariation,
    'pitchVariation': pitchVariation,
    'globalPitch': globalPitch,
    'outputLevel': outputLevel,
    'frozen': frozen,
    'voices': voices.map((v) => v.toJson()).toList(),
  };

  factory GranularPreset.fromJson(Map<String, dynamic> json) {
    return GranularPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      grainSizeMinMs: (json['grainSizeMinMs'] as num?)?.toDouble() ?? 20,
      grainSizeMaxMs: (json['grainSizeMaxMs'] as num?)?.toDouble() ?? 100,
      density: (json['density'] as num?)?.toDouble() ?? 10,
      sourcePosition: (json['sourcePosition'] as num?)?.toDouble() ?? 0.5,
      positionJitter: (json['positionJitter'] as num?)?.toDouble() ?? 0.1,
      windowShape: GrainWindowShape.values.firstWhere(
        (w) => w.name == json['windowShape'],
        orElse: () => GrainWindowShape.hann,
      ),
      sizeVariation: (json['sizeVariation'] as num?)?.toDouble() ?? 0.0,
      panVariation: (json['panVariation'] as num?)?.toDouble() ?? 0.0,
      pitchVariation: (json['pitchVariation'] as num?)?.toDouble() ?? 0.0,
      globalPitch: (json['globalPitch'] as num?)?.toDouble() ?? 0.0,
      outputLevel: (json['outputLevel'] as num?)?.toDouble() ?? 1.0,
      frozen: json['frozen'] as bool? ?? false,
      voices: (json['voices'] as List<dynamic>?)
          ?.map((v) => GrainVoice.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRANULAR SYNTH SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for managing granular synthesis parameters and presets
class GranularSynthService extends ChangeNotifier {
  GranularSynthService._();
  static final GranularSynthService instance = GranularSynthService._();

  /// Current active preset (working state)
  late GranularPreset _current = GranularPreset(
    id: 'default',
    name: 'Default',
  );

  /// Saved presets
  final Map<String, GranularPreset> _presets = {};

  /// Whether the engine is actively processing grains
  bool _processing = false;

  /// Callback for sending parameter changes to the audio engine
  void Function(String param, double value)? onParamChanged;

  /// Callback for freeze toggle
  void Function(bool frozen)? onFreezeChanged;

  // Getters
  GranularPreset get current => _current;
  List<GranularPreset> get presets => _presets.values.toList();
  int get presetCount => _presets.length;
  bool get processing => _processing;
  List<GrainVoice> get voices => _current.voices;

  // ═══════════════════════════════════════════════════════════════════════════
  // PARAMETER CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set grain size range
  void setGrainSize({double? minMs, double? maxMs}) {
    if (minMs != null) _current.grainSizeMinMs = minMs.clamp(1, 500);
    if (maxMs != null) _current.grainSizeMaxMs = maxMs.clamp(1, 500);
    // Ensure min <= max
    if (_current.grainSizeMinMs > _current.grainSizeMaxMs) {
      _current.grainSizeMaxMs = _current.grainSizeMinMs;
    }
    onParamChanged?.call('grainSizeMin', _current.grainSizeMinMs);
    onParamChanged?.call('grainSizeMax', _current.grainSizeMaxMs);
    notifyListeners();
  }

  /// Set grain density
  void setDensity(double density) {
    _current.density = density.clamp(0.5, 100);
    onParamChanged?.call('density', _current.density);
    notifyListeners();
  }

  /// Set source position
  void setSourcePosition(double position) {
    _current.sourcePosition = position.clamp(0, 1);
    onParamChanged?.call('sourcePosition', _current.sourcePosition);
    notifyListeners();
  }

  /// Set position jitter
  void setPositionJitter(double jitter) {
    _current.positionJitter = jitter.clamp(0, 1);
    onParamChanged?.call('positionJitter', _current.positionJitter);
    notifyListeners();
  }

  /// Set window shape
  void setWindowShape(GrainWindowShape shape) {
    _current.windowShape = shape;
    onParamChanged?.call('windowShape', shape.index.toDouble());
    notifyListeners();
  }

  /// Set random variations
  void setVariation({double? size, double? pan, double? pitch}) {
    if (size != null) _current.sizeVariation = size.clamp(0, 1);
    if (pan != null) _current.panVariation = pan.clamp(0, 1);
    if (pitch != null) _current.pitchVariation = pitch.clamp(0, 1);
    notifyListeners();
  }

  /// Set global pitch
  void setGlobalPitch(double semitones) {
    _current.globalPitch = semitones.clamp(-24, 24);
    onParamChanged?.call('globalPitch', _current.globalPitch);
    notifyListeners();
  }

  /// Set output level
  void setOutputLevel(double level) {
    _current.outputLevel = level.clamp(0, 2);
    onParamChanged?.call('outputLevel', _current.outputLevel);
    notifyListeners();
  }

  /// Toggle freeze mode
  void toggleFreeze() {
    _current.frozen = !_current.frozen;
    onFreezeChanged?.call(_current.frozen);
    notifyListeners();
  }

  /// Set freeze mode
  void setFreeze(bool frozen) {
    _current.frozen = frozen;
    onFreezeChanged?.call(_current.frozen);
    notifyListeners();
  }

  /// Toggle processing
  void toggleProcessing() {
    _processing = !_processing;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VOICE CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle voice active state
  void toggleVoice(int index) {
    if (index < 0 || index >= _current.voices.length) return;
    _current.voices[index].active = !_current.voices[index].active;
    notifyListeners();
  }

  /// Set voice level
  void setVoiceLevel(int index, double level) {
    if (index < 0 || index >= _current.voices.length) return;
    _current.voices[index].level = level.clamp(0, 1);
    notifyListeners();
  }

  /// Set voice pan
  void setVoicePan(int index, double pan) {
    if (index < 0 || index >= _current.voices.length) return;
    _current.voices[index].pan = pan.clamp(-1, 1);
    notifyListeners();
  }

  /// Set voice pitch offset
  void setVoicePitch(int index, double semitones) {
    if (index < 0 || index >= _current.voices.length) return;
    _current.voices[index].pitchOffset = semitones.clamp(-24, 24);
    notifyListeners();
  }

  /// Set voice delay offset
  void setVoiceDelay(int index, double delayMs) {
    if (index < 0 || index >= _current.voices.length) return;
    _current.voices[index].delayMs = delayMs.clamp(0, 500);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save current state as a preset
  void savePreset(String name) {
    final id = 'preset_${DateTime.now().millisecondsSinceEpoch}';
    final json = _current.toJson();
    json['id'] = id;
    json['name'] = name;
    _presets[id] = GranularPreset.fromJson(json);
    notifyListeners();
  }

  /// Load a preset as current
  void loadPreset(String id) {
    final preset = _presets[id];
    if (preset == null) return;
    final json = preset.toJson();
    json['id'] = 'default';
    _current = GranularPreset.fromJson(json);
    _current.name = preset.name;
    notifyListeners();
  }

  /// Delete a preset
  void deletePreset(String id) {
    _presets.remove(id);
    notifyListeners();
  }

  /// Rename a preset
  void renamePreset(String id, String newName) {
    final preset = _presets[id];
    if (preset == null) return;
    preset.name = newName;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORY PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load factory presets (skips already-present)
  void loadFactoryPresets() {
    void addIfAbsent(GranularPreset preset) {
      if (!_presets.containsKey(preset.id)) _presets[preset.id] = preset;
    }

    // Ambient pad
    addIfAbsent(GranularPreset(
      id: 'factory_ambient',
      name: 'Ambient Pad',
      grainSizeMinMs: 80,
      grainSizeMaxMs: 200,
      density: 15,
      positionJitter: 0.3,
      sizeVariation: 0.4,
      panVariation: 0.6,
      pitchVariation: 0.1,
    ));

    // Glitch
    addIfAbsent(GranularPreset(
      id: 'factory_glitch',
      name: 'Glitch',
      grainSizeMinMs: 5,
      grainSizeMaxMs: 30,
      density: 40,
      positionJitter: 0.8,
      sizeVariation: 0.9,
      panVariation: 0.7,
      pitchVariation: 0.5,
    ));

    // Texture
    addIfAbsent(GranularPreset(
      id: 'factory_texture',
      name: 'Smooth Texture',
      grainSizeMinMs: 50,
      grainSizeMaxMs: 150,
      density: 20,
      positionJitter: 0.2,
      sizeVariation: 0.2,
      panVariation: 0.3,
      pitchVariation: 0.0,
      windowShape: GrainWindowShape.blackman,
    ));

    // Freeze Drone
    addIfAbsent(GranularPreset(
      id: 'factory_freeze_drone',
      name: 'Freeze Drone',
      grainSizeMinMs: 100,
      grainSizeMaxMs: 300,
      density: 8,
      positionJitter: 0.05,
      sizeVariation: 0.1,
      panVariation: 0.2,
      pitchVariation: 0.0,
      frozen: true,
    ));

    // Scatter
    addIfAbsent(GranularPreset(
      id: 'factory_scatter',
      name: 'Scatter',
      grainSizeMinMs: 10,
      grainSizeMaxMs: 60,
      density: 30,
      positionJitter: 0.6,
      sizeVariation: 0.7,
      panVariation: 0.8,
      pitchVariation: 0.3,
      voices: [
        GrainVoice(index: 0, pan: -0.7, pitchOffset: 0),
        GrainVoice(index: 1, pan: 0.7, pitchOffset: 0),
        GrainVoice(index: 2, pan: -0.3, pitchOffset: 12),
        GrainVoice(index: 3, pan: 0.3, pitchOffset: -12),
      ],
    ));

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'current': _current.toJson(),
    'presets': _presets.values.map((p) => p.toJson()).toList(),
    'processing': _processing,
  };

  void fromJson(Map<String, dynamic> json) {
    if (json['current'] != null) {
      _current = GranularPreset.fromJson(json['current'] as Map<String, dynamic>);
    }
    _presets.clear();
    final list = json['presets'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final preset = GranularPreset.fromJson(item as Map<String, dynamic>);
        _presets[preset.id] = preset;
      }
    }
    _processing = json['processing'] as bool? ?? false;
    notifyListeners();
  }
}

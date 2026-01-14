// Groove Quantize Provider
//
// Humanization and groove templates:
// - Extract groove from audio/MIDI
// - Apply groove to quantize events
// - Humanize timing, velocity, length
// - Swing amount control
// - Classic drum machine grooves (MPC, SP-1200, etc.)

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// A single timing point in a groove template
class GroovePoint {
  final double position;      // 0-1 relative position within beat
  final double offset;        // Timing offset in ticks
  final double velocity;      // Velocity multiplier (0.5-1.5)
  final double length;        // Length multiplier (0.5-1.5)

  const GroovePoint({
    required this.position,
    this.offset = 0,
    this.velocity = 1.0,
    this.length = 1.0,
  });

  GroovePoint copyWith({
    double? position,
    double? offset,
    double? velocity,
    double? length,
  }) {
    return GroovePoint(
      position: position ?? this.position,
      offset: offset ?? this.offset,
      velocity: velocity ?? this.velocity,
      length: length ?? this.length,
    );
  }
}

/// A complete groove template
class GrooveTemplate {
  final String id;
  final String name;
  final String? description;
  final String? category;

  // Groove points (one per subdivision)
  final List<GroovePoint> points;

  // Settings
  final int beatsPerPattern;    // How many beats the pattern covers (1, 2, 4)
  final int subdivisionsPerBeat; // 4 = 16th notes, 3 = triplets, etc.

  // Origin
  final bool isFactory;
  final String? sourceFile;     // If extracted from audio/MIDI

  const GrooveTemplate({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.points = const [],
    this.beatsPerPattern = 1,
    this.subdivisionsPerBeat = 4,
    this.isFactory = false,
    this.sourceFile,
  });

  GrooveTemplate copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    List<GroovePoint>? points,
    int? beatsPerPattern,
    int? subdivisionsPerBeat,
    bool? isFactory,
    String? sourceFile,
  }) {
    return GrooveTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      points: points ?? this.points,
      beatsPerPattern: beatsPerPattern ?? this.beatsPerPattern,
      subdivisionsPerBeat: subdivisionsPerBeat ?? this.subdivisionsPerBeat,
      isFactory: isFactory ?? this.isFactory,
      sourceFile: sourceFile ?? this.sourceFile,
    );
  }

  /// Get total subdivisions in pattern
  int get totalSubdivisions => beatsPerPattern * subdivisionsPerBeat;

  /// Get groove values at subdivision index
  GroovePoint? getPointAt(int subdivisionIndex) {
    final normalizedIndex = subdivisionIndex % totalSubdivisions;
    if (normalizedIndex < points.length) {
      return points[normalizedIndex];
    }
    return null;
  }

  /// Interpolate groove at any position (0-1 within pattern)
  GroovePoint interpolateAt(double position) {
    if (points.isEmpty) {
      return const GroovePoint(position: 0);
    }

    // Normalize position
    position = position - position.floor();

    // Find surrounding points
    GroovePoint? before;
    GroovePoint? after;

    for (final point in points) {
      if (point.position <= position) {
        before = point;
      }
      if (point.position >= position && after == null) {
        after = point;
      }
    }

    if (before == null && after == null) return points.first;
    if (before == null) return after!;
    if (after == null) return before;
    if (before.position == after.position) return before;

    // Interpolate
    final t = (position - before.position) / (after.position - before.position);
    return GroovePoint(
      position: position,
      offset: before.offset + t * (after.offset - before.offset),
      velocity: before.velocity + t * (after.velocity - before.velocity),
      length: before.length + t * (after.length - before.length),
    );
  }
}

/// Quantize settings
class QuantizeSettings {
  final int gridSize;           // PPQ ticks per grid step
  final double strength;        // 0-100% quantize strength
  final double swing;           // 0-100% swing amount
  final bool quantizeStart;     // Quantize note start positions
  final bool quantizeEnd;       // Quantize note end positions
  final double randomTiming;    // Random timing variation (ticks)
  final double randomVelocity;  // Random velocity variation (0-127)

  const QuantizeSettings({
    this.gridSize = 120,        // 16th note at 480 PPQ
    this.strength = 100,
    this.swing = 0,
    this.quantizeStart = true,
    this.quantizeEnd = false,
    this.randomTiming = 0,
    this.randomVelocity = 0,
  });

  QuantizeSettings copyWith({
    int? gridSize,
    double? strength,
    double? swing,
    bool? quantizeStart,
    bool? quantizeEnd,
    double? randomTiming,
    double? randomVelocity,
  }) {
    return QuantizeSettings(
      gridSize: gridSize ?? this.gridSize,
      strength: strength ?? this.strength,
      swing: swing ?? this.swing,
      quantizeStart: quantizeStart ?? this.quantizeStart,
      quantizeEnd: quantizeEnd ?? this.quantizeEnd,
      randomTiming: randomTiming ?? this.randomTiming,
      randomVelocity: randomVelocity ?? this.randomVelocity,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class GrooveQuantizeProvider extends ChangeNotifier {
  // Current settings
  QuantizeSettings _settings = const QuantizeSettings();

  // Active groove template
  String? _activeTemplateId;

  // Groove templates
  final Map<String, GrooveTemplate> _templates = {};
  final Map<String, GrooveTemplate> _factoryTemplates = {};

  // PPQ (ticks per quarter note)
  int _ppq = 480;

  // Random generator
  final _random = math.Random();

  // Enabled state
  bool _enabled = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  QuantizeSettings get settings => _settings;
  int get ppq => _ppq;
  String? get activeTemplateId => _activeTemplateId;

  GrooveTemplate? get activeTemplate {
    if (_activeTemplateId == null) return null;
    return _templates[_activeTemplateId] ?? _factoryTemplates[_activeTemplateId];
  }

  List<GrooveTemplate> get userTemplates =>
      _templates.values.where((t) => !t.isFactory).toList();

  List<GrooveTemplate> get factoryTemplates =>
      _factoryTemplates.values.toList();

  List<GrooveTemplate> get allTemplates => [
    ..._factoryTemplates.values,
    ..._templates.values,
  ];

  /// Get templates by category
  Map<String, List<GrooveTemplate>> get templatesByCategory {
    final result = <String, List<GrooveTemplate>>{};
    for (final template in allTemplates) {
      final category = template.category ?? 'Uncategorized';
      result.putIfAbsent(category, () => []).add(template);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  void setSettings(QuantizeSettings settings) {
    _settings = settings;
    notifyListeners();
  }

  void updateSettings({
    int? gridSize,
    double? strength,
    double? swing,
    bool? quantizeStart,
    bool? quantizeEnd,
    double? randomTiming,
    double? randomVelocity,
  }) {
    _settings = _settings.copyWith(
      gridSize: gridSize,
      strength: strength,
      swing: swing,
      quantizeStart: quantizeStart,
      quantizeEnd: quantizeEnd,
      randomTiming: randomTiming,
      randomVelocity: randomVelocity,
    );
    notifyListeners();
  }

  void setPpq(int ppq) {
    _ppq = ppq;
    notifyListeners();
  }

  void setActiveTemplate(String? templateId) {
    _activeTemplateId = templateId;
    notifyListeners();
  }

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void toggleEnabled() {
    _enabled = !_enabled;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUANTIZE CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Quantize a tick position
  int quantizeTick(int tick) {
    // Find nearest grid position
    final gridPos = (tick / _settings.gridSize).round() * _settings.gridSize;

    // Apply strength
    final strengthFactor = _settings.strength / 100;
    int quantized = (tick + (gridPos - tick) * strengthFactor).round();

    // Apply swing (affects off-beat positions)
    if (_settings.swing > 0) {
      final beatPos = tick % (_ppq * 4); // Position within bar
      final isOffBeat = (beatPos ~/ _settings.gridSize) % 2 == 1;
      if (isOffBeat) {
        final swingOffset = (_settings.gridSize * _settings.swing / 100).round();
        quantized += swingOffset;
      }
    }

    // Apply groove template
    if (activeTemplate != null) {
      final patternLength = activeTemplate!.beatsPerPattern * _ppq;
      final posInPattern = (tick % patternLength) / patternLength;
      final groovePoint = activeTemplate!.interpolateAt(posInPattern);
      quantized += groovePoint.offset.round();
    }

    // Apply random timing
    if (_settings.randomTiming > 0) {
      final randomOffset = (_random.nextDouble() * 2 - 1) * _settings.randomTiming;
      quantized += randomOffset.round();
    }

    return quantized.clamp(0, double.maxFinite.toInt());
  }

  /// Quantize velocity with humanization
  int quantizeVelocity(int velocity, int tick) {
    double result = velocity.toDouble();

    // Apply groove template velocity
    if (activeTemplate != null) {
      final patternLength = activeTemplate!.beatsPerPattern * _ppq;
      final posInPattern = (tick % patternLength) / patternLength;
      final groovePoint = activeTemplate!.interpolateAt(posInPattern);
      result *= groovePoint.velocity;
    }

    // Apply random velocity
    if (_settings.randomVelocity > 0) {
      final randomOffset = (_random.nextDouble() * 2 - 1) * _settings.randomVelocity;
      result += randomOffset;
    }

    return result.round().clamp(1, 127);
  }

  /// Quantize note length with humanization
  int quantizeLength(int length, int tick) {
    double result = length.toDouble();

    // Apply groove template length
    if (activeTemplate != null) {
      final patternLength = activeTemplate!.beatsPerPattern * _ppq;
      final posInPattern = (tick % patternLength) / patternLength;
      final groovePoint = activeTemplate!.interpolateAt(posInPattern);
      result *= groovePoint.length;
    }

    return result.round().clamp(1, double.maxFinite.toInt());
  }

  /// Apply full quantization to a note
  ({int start, int length, int velocity}) quantizeNote({
    required int startTick,
    required int lengthTicks,
    required int velocity,
  }) {
    return (
      start: _settings.quantizeStart ? quantizeTick(startTick) : startTick,
      length: _settings.quantizeEnd
          ? quantizeLength(lengthTicks, startTick)
          : lengthTicks,
      velocity: quantizeVelocity(velocity, startTick),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPLATE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create template from timing data
  GrooveTemplate createTemplate({
    required String name,
    required List<double> timingOffsets,  // Offset per subdivision
    List<double>? velocities,
    List<double>? lengths,
    int beatsPerPattern = 1,
    int subdivisionsPerBeat = 4,
    String? category,
  }) {
    final id = 'groove_${DateTime.now().millisecondsSinceEpoch}';

    final points = <GroovePoint>[];
    for (int i = 0; i < timingOffsets.length; i++) {
      points.add(GroovePoint(
        position: i / timingOffsets.length,
        offset: timingOffsets[i],
        velocity: velocities != null && i < velocities.length ? velocities[i] : 1.0,
        length: lengths != null && i < lengths.length ? lengths[i] : 1.0,
      ));
    }

    final template = GrooveTemplate(
      id: id,
      name: name,
      category: category,
      points: points,
      beatsPerPattern: beatsPerPattern,
      subdivisionsPerBeat: subdivisionsPerBeat,
    );

    _templates[id] = template;
    notifyListeners();
    return template;
  }

  /// Save/update template
  void saveTemplate(GrooveTemplate template) {
    _templates[template.id] = template;
    notifyListeners();
  }

  /// Delete template
  void deleteTemplate(String templateId) {
    _templates.remove(templateId);
    if (_activeTemplateId == templateId) {
      _activeTemplateId = null;
    }
    notifyListeners();
  }

  /// Duplicate template
  GrooveTemplate duplicateTemplate(String templateId) {
    final original = _templates[templateId] ?? _factoryTemplates[templateId];
    if (original == null) throw StateError('Template not found');

    final newId = 'groove_${DateTime.now().millisecondsSinceEpoch}';
    final copy = original.copyWith(
      id: newId,
      name: '${original.name} (Copy)',
      isFactory: false,
    );

    _templates[newId] = copy;
    notifyListeners();
    return copy;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORY GROOVES
  // ═══════════════════════════════════════════════════════════════════════════

  void _initFactoryGrooves() {
    // MPC60 Swing - Classic Akai groove
    _factoryTemplates['mpc60'] = GrooveTemplate(
      id: 'mpc60',
      name: 'MPC60 Swing',
      description: 'Classic Akai MPC-60 swing feel',
      category: 'Drum Machines',
      beatsPerPattern: 1,
      subdivisionsPerBeat: 4,
      points: [
        const GroovePoint(position: 0.0, offset: 0, velocity: 1.0),
        const GroovePoint(position: 0.25, offset: 12, velocity: 0.85),
        const GroovePoint(position: 0.5, offset: 0, velocity: 0.95),
        const GroovePoint(position: 0.75, offset: 8, velocity: 0.80),
      ],
      isFactory: true,
    );

    // SP-1200 Swing
    _factoryTemplates['sp1200'] = GrooveTemplate(
      id: 'sp1200',
      name: 'SP-1200 Swing',
      description: 'E-mu SP-1200 timing',
      category: 'Drum Machines',
      beatsPerPattern: 1,
      subdivisionsPerBeat: 4,
      points: [
        const GroovePoint(position: 0.0, offset: 0, velocity: 1.0),
        const GroovePoint(position: 0.25, offset: 18, velocity: 0.88),
        const GroovePoint(position: 0.5, offset: -2, velocity: 0.92),
        const GroovePoint(position: 0.75, offset: 14, velocity: 0.85),
      ],
      isFactory: true,
    );

    // TR-808 Straight
    _factoryTemplates['tr808'] = GrooveTemplate(
      id: 'tr808',
      name: 'TR-808',
      description: 'Roland TR-808 feel',
      category: 'Drum Machines',
      beatsPerPattern: 1,
      subdivisionsPerBeat: 4,
      points: [
        const GroovePoint(position: 0.0, offset: 0, velocity: 1.0),
        const GroovePoint(position: 0.25, offset: 0, velocity: 0.90),
        const GroovePoint(position: 0.5, offset: 0, velocity: 0.95),
        const GroovePoint(position: 0.75, offset: 0, velocity: 0.88),
      ],
      isFactory: true,
    );

    // Shuffle (triplet-based)
    _factoryTemplates['shuffle'] = GrooveTemplate(
      id: 'shuffle',
      name: 'Shuffle',
      description: 'Triplet-based shuffle',
      category: 'Classic',
      beatsPerPattern: 1,
      subdivisionsPerBeat: 2,
      points: [
        const GroovePoint(position: 0.0, offset: 0, velocity: 1.0),
        const GroovePoint(position: 0.5, offset: 40, velocity: 0.85), // Push toward triplet
      ],
      isFactory: true,
    );

    // Human Feel Light
    _factoryTemplates['human_light'] = GrooveTemplate(
      id: 'human_light',
      name: 'Human Feel Light',
      description: 'Subtle humanization',
      category: 'Humanize',
      beatsPerPattern: 2,
      subdivisionsPerBeat: 4,
      points: [
        const GroovePoint(position: 0.0, offset: 0, velocity: 1.0, length: 1.0),
        const GroovePoint(position: 0.125, offset: 3, velocity: 0.95, length: 0.98),
        const GroovePoint(position: 0.25, offset: -2, velocity: 0.92, length: 1.02),
        const GroovePoint(position: 0.375, offset: 5, velocity: 0.88, length: 0.96),
        const GroovePoint(position: 0.5, offset: 1, velocity: 0.98, length: 1.0),
        const GroovePoint(position: 0.625, offset: 4, velocity: 0.90, length: 0.99),
        const GroovePoint(position: 0.75, offset: -1, velocity: 0.94, length: 1.01),
        const GroovePoint(position: 0.875, offset: 6, velocity: 0.86, length: 0.97),
      ],
      isFactory: true,
    );

    // Laid Back
    _factoryTemplates['laid_back'] = GrooveTemplate(
      id: 'laid_back',
      name: 'Laid Back',
      description: 'Behind the beat feel',
      category: 'Feel',
      beatsPerPattern: 1,
      subdivisionsPerBeat: 4,
      points: [
        const GroovePoint(position: 0.0, offset: 8, velocity: 0.95),
        const GroovePoint(position: 0.25, offset: 12, velocity: 0.88),
        const GroovePoint(position: 0.5, offset: 6, velocity: 0.92),
        const GroovePoint(position: 0.75, offset: 14, velocity: 0.85),
      ],
      isFactory: true,
    );

    // Push (ahead of beat)
    _factoryTemplates['push'] = GrooveTemplate(
      id: 'push',
      name: 'Push',
      description: 'Ahead of the beat',
      category: 'Feel',
      beatsPerPattern: 1,
      subdivisionsPerBeat: 4,
      points: [
        const GroovePoint(position: 0.0, offset: -5, velocity: 1.02),
        const GroovePoint(position: 0.25, offset: -8, velocity: 0.95),
        const GroovePoint(position: 0.5, offset: -4, velocity: 1.0),
        const GroovePoint(position: 0.75, offset: -10, velocity: 0.92),
      ],
      isFactory: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GRID SIZE PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Common grid sizes in ticks (at 480 PPQ)
  static const Map<String, int> gridPresets = {
    '1/1': 1920,      // Whole note
    '1/2': 960,       // Half note
    '1/4': 480,       // Quarter note
    '1/8': 240,       // 8th note
    '1/16': 120,      // 16th note
    '1/32': 60,       // 32nd note
    '1/4T': 320,      // Quarter triplet
    '1/8T': 160,      // 8th triplet
    '1/16T': 80,      // 16th triplet
  };

  /// Get grid size for preset name
  int getGridSize(String presetName) {
    final preset = gridPresets[presetName];
    if (preset != null) {
      // Scale to current PPQ
      return (preset * _ppq / 480).round();
    }
    return _settings.gridSize;
  }

  /// Set grid from preset
  void setGridPreset(String presetName) {
    final size = getGridSize(presetName);
    updateSettings(gridSize: size);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'ppq': _ppq,
      'activeTemplateId': _activeTemplateId,
      'settings': {
        'gridSize': _settings.gridSize,
        'strength': _settings.strength,
        'swing': _settings.swing,
        'quantizeStart': _settings.quantizeStart,
        'quantizeEnd': _settings.quantizeEnd,
        'randomTiming': _settings.randomTiming,
        'randomVelocity': _settings.randomVelocity,
      },
      'templates': _templates.values
          .where((t) => !t.isFactory)
          .map((t) => _templateToJson(t))
          .toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _ppq = json['ppq'] ?? 480;
    _activeTemplateId = json['activeTemplateId'];

    if (json['settings'] != null) {
      final s = json['settings'];
      _settings = QuantizeSettings(
        gridSize: s['gridSize'] ?? 120,
        strength: (s['strength'] ?? 100).toDouble(),
        swing: (s['swing'] ?? 0).toDouble(),
        quantizeStart: s['quantizeStart'] ?? true,
        quantizeEnd: s['quantizeEnd'] ?? false,
        randomTiming: (s['randomTiming'] ?? 0).toDouble(),
        randomVelocity: (s['randomVelocity'] ?? 0).toDouble(),
      );
    }

    _templates.clear();
    if (json['templates'] != null) {
      for (final t in json['templates']) {
        final template = _templateFromJson(t);
        _templates[template.id] = template;
      }
    }

    _initFactoryGrooves();
    notifyListeners();
  }

  Map<String, dynamic> _templateToJson(GrooveTemplate t) {
    return {
      'id': t.id,
      'name': t.name,
      'description': t.description,
      'category': t.category,
      'beatsPerPattern': t.beatsPerPattern,
      'subdivisionsPerBeat': t.subdivisionsPerBeat,
      'sourceFile': t.sourceFile,
      'points': t.points.map((p) => {
        'position': p.position,
        'offset': p.offset,
        'velocity': p.velocity,
        'length': p.length,
      }).toList(),
    };
  }

  GrooveTemplate _templateFromJson(Map<String, dynamic> json) {
    return GrooveTemplate(
      id: json['id'],
      name: json['name'] ?? 'Groove',
      description: json['description'],
      category: json['category'],
      beatsPerPattern: json['beatsPerPattern'] ?? 1,
      subdivisionsPerBeat: json['subdivisionsPerBeat'] ?? 4,
      sourceFile: json['sourceFile'],
      points: (json['points'] as List?)?.map((p) => GroovePoint(
        position: (p['position'] ?? 0).toDouble(),
        offset: (p['offset'] ?? 0).toDouble(),
        velocity: (p['velocity'] ?? 1.0).toDouble(),
        length: (p['length'] ?? 1.0).toDouble(),
      )).toList() ?? [],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INIT / RESET
  // ═══════════════════════════════════════════════════════════════════════════

  GrooveQuantizeProvider() {
    _initFactoryGrooves();
  }

  void reset() {
    _settings = const QuantizeSettings();
    _activeTemplateId = null;
    _templates.clear();
    _initFactoryGrooves();
    notifyListeners();
  }
}

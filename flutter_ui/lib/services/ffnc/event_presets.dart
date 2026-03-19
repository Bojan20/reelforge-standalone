/// Event Presets — save/load audio parameter presets per event.
///
/// Presets store volume, bus, fade, loop settings that can be applied
/// to any stage. Built-in presets + user-saved presets in ~/.fluxforge/.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class EventPreset {
  final String name;
  final double volume;
  final int busId;
  final double fadeInMs;
  final double fadeOutMs;
  final bool loop;
  final bool overlap;
  final int crossfadeMs;

  const EventPreset({
    required this.name,
    this.volume = 1.0,
    this.busId = 2,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.loop = false,
    this.overlap = true,
    this.crossfadeMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'volume': volume,
    'busId': busId,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'loop': loop,
    'overlap': overlap,
    'crossfadeMs': crossfadeMs,
  };

  factory EventPreset.fromJson(Map<String, dynamic> json) => EventPreset(
    name: json['name'] as String? ?? 'Untitled',
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    busId: json['busId'] as int? ?? 2,
    fadeInMs: (json['fadeInMs'] as num?)?.toDouble() ?? 0,
    fadeOutMs: (json['fadeOutMs'] as num?)?.toDouble() ?? 0,
    loop: json['loop'] as bool? ?? false,
    overlap: json['overlap'] as bool? ?? true,
    crossfadeMs: json['crossfadeMs'] as int? ?? 0,
  );
}

class EventPresetService {
  EventPresetService._();
  static final instance = EventPresetService._();

  List<EventPreset> _userPresets = [];
  bool _loaded = false;

  /// All presets: built-in + user-saved
  List<EventPreset> get presets => [...builtInPresets, ..._userPresets];

  /// User-saved presets only
  List<EventPreset> get userPresets => List.unmodifiable(_userPresets);

  static const builtInPresets = [
    EventPreset(name: 'Standard Reel Stop', volume: 0.80, busId: 2, fadeOutMs: 100),
    EventPreset(name: 'Heavy Impact', volume: 0.90, busId: 2),
    EventPreset(name: 'Music Loop', volume: 0.60, busId: 1, fadeInMs: 200, loop: true),
    EventPreset(name: 'Ambient Pad', volume: 0.40, busId: 4, fadeInMs: 500, loop: true),
    EventPreset(name: 'UI Click', volume: 0.50, busId: 2),
    EventPreset(name: 'Win Celebration', volume: 0.75, busId: 2, fadeInMs: 50),
  ];

  /// Load user presets from disk
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final file = File(_presetPath);
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      final list = json['presets'] as List<dynamic>? ?? [];
      _userPresets = list
          .map((e) => EventPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _userPresets = [];
    }
  }

  /// Save a new user preset
  Future<void> savePreset(EventPreset preset) async {
    // Remove existing with same name
    _userPresets.removeWhere((p) => p.name == preset.name);
    _userPresets.add(preset);
    await _persist();
  }

  /// Delete a user preset by name
  Future<void> deletePreset(String name) async {
    _userPresets.removeWhere((p) => p.name == name);
    await _persist();
  }

  Future<void> _persist() async {
    final dir = Directory(p.dirname(_presetPath));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final json = jsonEncode({
      'presets': _userPresets.map((p) => p.toJson()).toList(),
    });
    await File(_presetPath).writeAsString(json);
  }

  String get _presetPath {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, '.fluxforge', 'event_presets.json');
  }
}

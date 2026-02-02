/// Session Template Service (P2-DAW-10)
///
/// Save/load complete session configurations:
/// - Track layouts
/// - Mixer settings
/// - Plugin chains
/// - 5 built-in templates
///
/// Created: 2026-02-02
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timeline_models.dart';

/// Session template schema version
const int kSessionTemplateVersion = 1;

/// Session template file extension
const String kSessionTemplateExtension = '.ffxsession';

/// Single track configuration in template
class TrackTemplate {
  final String name;
  final TrackType type;
  final OutputBus outputBus;
  final double volume;
  final double pan;
  final int colorIndex;
  final List<String> insertPlugins;

  const TrackTemplate({
    required this.name,
    this.type = TrackType.audio,
    this.outputBus = OutputBus.master,
    this.volume = 1.0,
    this.pan = 0.0,
    this.colorIndex = 0,
    this.insertPlugins = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.index,
    'outputBus': outputBus.index,
    'volume': volume,
    'pan': pan,
    'colorIndex': colorIndex,
    'insertPlugins': insertPlugins,
  };

  factory TrackTemplate.fromJson(Map<String, dynamic> json) {
    return TrackTemplate(
      name: json['name'] as String? ?? 'Track',
      type: TrackType.values[json['type'] as int? ?? 0],
      outputBus: OutputBus.values[json['outputBus'] as int? ?? 0],
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      colorIndex: json['colorIndex'] as int? ?? 0,
      insertPlugins: (json['insertPlugins'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// Complete session template
class SessionTemplate {
  final int version;
  final String id;
  final String name;
  final String? description;
  final String category;
  final double tempo;
  final int timeSignatureNumerator;
  final int timeSignatureDenominator;
  final List<TrackTemplate> tracks;
  final bool isBuiltIn;
  final DateTime? createdAt;

  const SessionTemplate({
    this.version = kSessionTemplateVersion,
    required this.id,
    required this.name,
    this.description,
    this.category = 'Custom',
    this.tempo = 120.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
    this.tracks = const [],
    this.isBuiltIn = false,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'tempo': tempo,
    'timeSignatureNumerator': timeSignatureNumerator,
    'timeSignatureDenominator': timeSignatureDenominator,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'createdAt': createdAt?.toIso8601String(),
  };

  factory SessionTemplate.fromJson(Map<String, dynamic> json) {
    return SessionTemplate(
      version: json['version'] as int? ?? 1,
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      category: json['category'] as String? ?? 'Custom',
      tempo: (json['tempo'] as num?)?.toDouble() ?? 120.0,
      timeSignatureNumerator: json['timeSignatureNumerator'] as int? ?? 4,
      timeSignatureDenominator: json['timeSignatureDenominator'] as int? ?? 4,
      tracks: (json['tracks'] as List<dynamic>?)
          ?.map((t) => TrackTemplate.fromJson(t as Map<String, dynamic>))
          .toList() ?? [],
      isBuiltIn: false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  SessionTemplate copyWith({
    int? version,
    String? id,
    String? name,
    String? description,
    String? category,
    double? tempo,
    int? timeSignatureNumerator,
    int? timeSignatureDenominator,
    List<TrackTemplate>? tracks,
    bool? isBuiltIn,
    DateTime? createdAt,
  }) {
    return SessionTemplate(
      version: version ?? this.version,
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      tempo: tempo ?? this.tempo,
      timeSignatureNumerator: timeSignatureNumerator ?? this.timeSignatureNumerator,
      timeSignatureDenominator: timeSignatureDenominator ?? this.timeSignatureDenominator,
      tracks: tracks ?? this.tracks,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Built-in session templates
class BuiltInSessionTemplates {
  static const mixing = SessionTemplate(
    id: 'builtin_mixing',
    name: 'Mixing Session',
    description: 'Standard mixing template with buses',
    category: 'Mixing',
    tempo: 120.0,
    isBuiltIn: true,
    tracks: [
      TrackTemplate(name: 'Drums', type: TrackType.bus, outputBus: OutputBus.master, colorIndex: 0),
      TrackTemplate(name: 'Bass', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 1),
      TrackTemplate(name: 'Guitar L', type: TrackType.audio, outputBus: OutputBus.master, pan: -0.5, colorIndex: 2),
      TrackTemplate(name: 'Guitar R', type: TrackType.audio, outputBus: OutputBus.master, pan: 0.5, colorIndex: 2),
      TrackTemplate(name: 'Keys', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 3),
      TrackTemplate(name: 'Vocals', type: TrackType.bus, outputBus: OutputBus.master, colorIndex: 4),
      TrackTemplate(name: 'FX', type: TrackType.aux, outputBus: OutputBus.master, colorIndex: 5),
    ],
  );

  static const mastering = SessionTemplate(
    id: 'builtin_mastering',
    name: 'Mastering Session',
    description: 'Mastering template with reference track',
    category: 'Mastering',
    tempo: 120.0,
    isBuiltIn: true,
    tracks: [
      TrackTemplate(name: 'Mix', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 0),
      TrackTemplate(name: 'Reference', type: TrackType.audio, outputBus: OutputBus.master, volume: 0.8, colorIndex: 1),
    ],
  );

  static const recording = SessionTemplate(
    id: 'builtin_recording',
    name: 'Recording Session',
    description: 'Multi-track recording template',
    category: 'Recording',
    tempo: 120.0,
    isBuiltIn: true,
    tracks: [
      TrackTemplate(name: 'Scratch', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 0),
      TrackTemplate(name: 'Take 1', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 1),
      TrackTemplate(name: 'Take 2', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 1),
      TrackTemplate(name: 'Take 3', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 1),
      TrackTemplate(name: 'Comp', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 2),
    ],
  );

  static const podcast = SessionTemplate(
    id: 'builtin_podcast',
    name: 'Podcast Session',
    description: 'Podcast/voiceover template',
    category: 'Podcast',
    tempo: 120.0,
    isBuiltIn: true,
    tracks: [
      TrackTemplate(name: 'Host', type: TrackType.audio, outputBus: OutputBus.voice, colorIndex: 0),
      TrackTemplate(name: 'Guest 1', type: TrackType.audio, outputBus: OutputBus.voice, colorIndex: 1),
      TrackTemplate(name: 'Guest 2', type: TrackType.audio, outputBus: OutputBus.voice, colorIndex: 2),
      TrackTemplate(name: 'Music', type: TrackType.audio, outputBus: OutputBus.music, volume: 0.5, colorIndex: 3),
      TrackTemplate(name: 'SFX', type: TrackType.audio, outputBus: OutputBus.sfx, colorIndex: 4),
    ],
  );

  static const soundDesign = SessionTemplate(
    id: 'builtin_sound_design',
    name: 'Sound Design Session',
    description: 'Sound design with FX buses',
    category: 'Sound Design',
    tempo: 120.0,
    isBuiltIn: true,
    tracks: [
      TrackTemplate(name: 'Source', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 0),
      TrackTemplate(name: 'Layer 1', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 1),
      TrackTemplate(name: 'Layer 2', type: TrackType.audio, outputBus: OutputBus.master, colorIndex: 2),
      TrackTemplate(name: 'Reverb', type: TrackType.aux, outputBus: OutputBus.master, colorIndex: 3),
      TrackTemplate(name: 'Delay', type: TrackType.aux, outputBus: OutputBus.master, colorIndex: 4),
      TrackTemplate(name: 'Output', type: TrackType.bus, outputBus: OutputBus.master, colorIndex: 5),
    ],
  );

  static const List<SessionTemplate> all = [mixing, mastering, recording, podcast, soundDesign];
}

/// Session template service
class SessionTemplateService extends ChangeNotifier {
  static final SessionTemplateService _instance = SessionTemplateService._();
  static SessionTemplateService get instance => _instance;

  SessionTemplateService._();

  final List<SessionTemplate> _customTemplates = [];

  List<SessionTemplate> get allTemplates => [...BuiltInSessionTemplates.all, ..._customTemplates];
  List<SessionTemplate> get customTemplates => List.unmodifiable(_customTemplates);
  List<SessionTemplate> get builtInTemplates => BuiltInSessionTemplates.all;

  Future<void> init() async {
    await _loadCustomTemplates();
  }

  Future<void> _loadCustomTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('session_templates');
    if (json != null) {
      try {
        final List<dynamic> decoded = jsonDecode(json);
        _customTemplates.clear();
        _customTemplates.addAll(
          decoded.map((e) => SessionTemplate.fromJson(e as Map<String, dynamic>)),
        );
        notifyListeners();
      } catch (e) {
        debugPrint('[SessionTemplateService] Failed to load templates: $e');
      }
    }
  }

  Future<bool> _saveCustomTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_customTemplates.map((t) => t.toJson()).toList());
      return await prefs.setString('session_templates', json);
    } catch (e) {
      debugPrint('[SessionTemplateService] Failed to save templates: $e');
      return false;
    }
  }

  Future<bool> saveTemplate(SessionTemplate template) async {
    if (template.isBuiltIn) return false;

    _customTemplates.removeWhere((t) => t.id == template.id);
    _customTemplates.add(template.copyWith(createdAt: DateTime.now()));

    final success = await _saveCustomTemplates();
    if (success) notifyListeners();
    return success;
  }

  Future<bool> deleteTemplate(String id) async {
    final index = _customTemplates.indexWhere((t) => t.id == id);
    if (index < 0) return false;

    _customTemplates.removeAt(index);
    final success = await _saveCustomTemplates();
    if (success) notifyListeners();
    return success;
  }

  SessionTemplate? getById(String id) {
    return allTemplates.where((t) => t.id == id).firstOrNull;
  }

  List<SessionTemplate> getByCategory(String category) {
    return allTemplates.where((t) => t.category == category).toList();
  }

  /// Export template to file
  Future<bool> exportTemplate(SessionTemplate template, String filePath) async {
    try {
      final file = File(filePath);
      final json = const JsonEncoder.withIndent('  ').convert(template.toJson());
      await file.writeAsString(json);
      return true;
    } catch (e) {
      debugPrint('[SessionTemplateService] Export failed: $e');
      return false;
    }
  }

  /// Import template from file
  Future<SessionTemplate?> importTemplate(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final json = await file.readAsString();
      final template = SessionTemplate.fromJson(jsonDecode(json) as Map<String, dynamic>);

      // Auto-save imported template
      await saveTemplate(template.copyWith(
        id: 'imported_${DateTime.now().millisecondsSinceEpoch}',
        isBuiltIn: false,
      ));

      return template;
    } catch (e) {
      debugPrint('[SessionTemplateService] Import failed: $e');
      return null;
    }
  }
}

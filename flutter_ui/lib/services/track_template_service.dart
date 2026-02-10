/// Track Template Service (P10.1.10)
///
/// Save/load complete track configurations:
/// - Channel strip + inserts + routing
/// - Built-in factory templates (5+)
/// - User template CRUD
/// - SharedPreferences storage
///
/// Logic Pro-style track template workflow.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track_template.dart';
import '../providers/dsp_chain_provider.dart';

/// Storage key for templates in SharedPreferences
const String _kStorageKey = 'fluxforge_track_templates';

// ═══════════════════════════════════════════════════════════════════════════
// TRACK TEMPLATE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Singleton service for track template management
class TrackTemplateService extends ChangeNotifier {
  static final TrackTemplateService _instance = TrackTemplateService._();
  static TrackTemplateService get instance => _instance;

  TrackTemplateService._();

  /// Cached templates
  final List<TrackTemplate> _templates = [];
  List<TrackTemplate> get templates => List.unmodifiable(_templates);

  /// Loading state
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ─── Initialization ─────────────────────────────────────────────────────

  /// Initialize service and load templates
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kStorageKey);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        _templates.clear();
        for (final item in jsonList) {
          try {
            _templates.add(TrackTemplate.fromJson(item as Map<String, dynamic>));
          } catch (e) { /* ignored */ }
        }
      }

      // Add built-in templates if empty
      if (_templates.isEmpty) {
        _addBuiltInTemplates();
        await _saveToStorage();
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _addBuiltInTemplates();
      _isInitialized = true;
      notifyListeners();
    }
  }

  // ─── Built-in Templates ─────────────────────────────────────────────────

  void _addBuiltInTemplates() {
    _templates.addAll([
      // Vocal template
      TrackTemplate(
        id: 'builtin_vocal',
        name: 'Vocal',
        description: 'Warm vocal chain with de-esser and compression',
        category: TrackTemplateCategory.vocal,
        createdAt: DateTime(2026, 1, 1),
        channelStrip: const TemplateChannelStrip(volume: 1.0, pan: 0.0),
        inserts: [
          TemplateInsertConfig(
            type: DspNodeType.deEsser,
            params: {'frequency': 6000, 'threshold': -20.0, 'range': -10.0},
          ),
          TemplateInsertConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 80, 'gain': -3, 'q': 0.7, 'type': 'lowShelf'},
                {'freq': 3000, 'gain': 2, 'q': 1.5, 'type': 'bell'},
                {'freq': 10000, 'gain': 1.5, 'q': 0.7, 'type': 'highShelf'},
              ]
            },
          ),
          TemplateInsertConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -18.0,
              'ratio': 3.0,
              'attack': 15.0,
              'release': 150.0,
              'knee': 6.0,
              'makeupGain': 3.0,
            },
          ),
        ],
        outputBusId: 'master',
        colorValue: 0xFFFF6B6B, // Red
      ),

      // Drum template
      TrackTemplate(
        id: 'builtin_drum',
        name: 'Drum Bus',
        description: 'Punchy drum processing with transient shaping',
        category: TrackTemplateCategory.drum,
        createdAt: DateTime(2026, 1, 1),
        channelStrip: const TemplateChannelStrip(volume: 1.0, pan: 0.0),
        inserts: [
          TemplateInsertConfig(
            type: DspNodeType.gate,
            params: {'threshold': -35.0, 'attack': 0.5, 'release': 80.0, 'range': -40.0},
          ),
          TemplateInsertConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 60, 'gain': 3, 'q': 1.0, 'type': 'bell'},
                {'freq': 5000, 'gain': 2, 'q': 2.0, 'type': 'bell'},
              ]
            },
          ),
          TemplateInsertConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -12.0,
              'ratio': 6.0,
              'attack': 5.0,
              'release': 80.0,
              'knee': 3.0,
              'makeupGain': 4.0,
            },
          ),
        ],
        outputBusId: 'master',
        colorValue: 0xFFFFD93D, // Yellow
      ),

      // Bass template
      TrackTemplate(
        id: 'builtin_bass',
        name: 'Bass',
        description: 'Clean bass with tight low end control',
        category: TrackTemplateCategory.bass,
        createdAt: DateTime(2026, 1, 1),
        channelStrip: const TemplateChannelStrip(volume: 1.0, pan: 0.0),
        inserts: [
          TemplateInsertConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 40, 'gain': 0, 'q': 1.0, 'type': 'lowCut'},
                {'freq': 80, 'gain': 2, 'q': 1.2, 'type': 'bell'},
                {'freq': 800, 'gain': -2, 'q': 1.0, 'type': 'bell'},
              ]
            },
          ),
          TemplateInsertConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -16.0,
              'ratio': 4.0,
              'attack': 20.0,
              'release': 120.0,
              'knee': 6.0,
              'makeupGain': 2.0,
            },
          ),
          TemplateInsertConfig(
            type: DspNodeType.saturation,
            wetDry: 0.3,
            params: {'drive': 0.2, 'mix': 0.3, 'type': 'tube'},
          ),
        ],
        outputBusId: 'master',
        colorValue: 0xFF9B59B6, // Purple
      ),

      // Guitar template
      TrackTemplate(
        id: 'builtin_guitar',
        name: 'Guitar',
        description: 'Guitar processing with warmth and presence',
        category: TrackTemplateCategory.guitar,
        createdAt: DateTime(2026, 1, 1),
        channelStrip: const TemplateChannelStrip(volume: 1.0, pan: 0.0),
        inserts: [
          TemplateInsertConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 100, 'gain': -2, 'q': 0.8, 'type': 'lowShelf'},
                {'freq': 2500, 'gain': 2, 'q': 1.5, 'type': 'bell'},
                {'freq': 8000, 'gain': 1, 'q': 0.7, 'type': 'highShelf'},
              ]
            },
          ),
          TemplateInsertConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -20.0,
              'ratio': 3.0,
              'attack': 25.0,
              'release': 200.0,
              'knee': 6.0,
              'makeupGain': 2.0,
            },
          ),
        ],
        sends: const [
          TemplateSendConfig(auxBusId: 'aux_reverb', level: 0.2, preFader: false),
        ],
        outputBusId: 'master',
        colorValue: 0xFFE67E22, // Orange
      ),

      // FX template
      TrackTemplate(
        id: 'builtin_fx',
        name: 'FX/Creative',
        description: 'Creative effects chain with reverb and delay',
        category: TrackTemplateCategory.fx,
        createdAt: DateTime(2026, 1, 1),
        channelStrip: const TemplateChannelStrip(volume: 0.8, pan: 0.0),
        inserts: [
          TemplateInsertConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 200, 'gain': -3, 'q': 0.7, 'type': 'lowShelf'},
              ]
            },
          ),
          TemplateInsertConfig(
            type: DspNodeType.delay,
            wetDry: 0.4,
            params: {'time': 375.0, 'feedback': 0.4, 'highCut': 6000, 'lowCut': 150},
          ),
          TemplateInsertConfig(
            type: DspNodeType.reverb,
            wetDry: 0.5,
            params: {'decay': 2.5, 'preDelay': 30.0, 'damping': 0.6, 'size': 0.8},
          ),
        ],
        outputBusId: 'master',
        colorValue: 0xFF40C8FF, // Cyan
      ),
    ]);
  }

  // ─── CRUD Operations ────────────────────────────────────────────────────

  /// Save a new template
  Future<bool> saveTemplate(TrackTemplate template) async {
    try {
      // Check for duplicate name
      final existingIndex = _templates.indexWhere((t) => t.id == template.id);
      if (existingIndex >= 0) {
        _templates[existingIndex] = template.copyWith(modifiedAt: DateTime.now());
      } else {
        _templates.add(template);
      }

      await _saveToStorage();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load template by ID
  TrackTemplate? loadTemplate(String id) {
    return _templates.where((t) => t.id == id).firstOrNull;
  }

  /// Delete template
  Future<bool> deleteTemplate(String id) async {
    try {
      // Prevent deleting built-in templates
      if (id.startsWith('builtin_')) {
        return false;
      }

      _templates.removeWhere((t) => t.id == id);
      await _saveToStorage();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Duplicate template with new ID
  Future<TrackTemplate?> duplicateTemplate(String id) async {
    final original = loadTemplate(id);
    if (original == null) return null;

    final duplicate = original.copyWith(
      id: TrackTemplate.generateId(),
      name: '${original.name} (Copy)',
      createdAt: DateTime.now(),
      modifiedAt: null,
    );

    if (await saveTemplate(duplicate)) {
      return duplicate;
    }
    return null;
  }

  // ─── Filtering ──────────────────────────────────────────────────────────

  /// Get templates by category
  List<TrackTemplate> getByCategory(TrackTemplateCategory category) {
    return _templates.where((t) => t.category == category).toList();
  }

  /// Search templates by name
  List<TrackTemplate> search(String query) {
    if (query.isEmpty) return templates;
    final lowerQuery = query.toLowerCase();
    return _templates
        .where((t) =>
            t.name.toLowerCase().contains(lowerQuery) ||
            (t.description?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }

  /// Get built-in templates only
  List<TrackTemplate> get builtInTemplates =>
      _templates.where((t) => t.id.startsWith('builtin_')).toList();

  /// Get user templates only
  List<TrackTemplate> get userTemplates =>
      _templates.where((t) => !t.id.startsWith('builtin_')).toList();

  // ─── Storage ────────────────────────────────────────────────────────────

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _templates.map((t) => t.toJson()).toList();
      await prefs.setString(_kStorageKey, jsonEncode(jsonList));
    } catch (e) { /* ignored */ }
  }

  /// Export template to JSON string
  String exportToJson(TrackTemplate template) {
    return const JsonEncoder.withIndent('  ').convert(template.toJson());
  }

  /// Import template from JSON string
  TrackTemplate? importFromJson(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return TrackTemplate.fromJson(json).copyWith(
        id: TrackTemplate.generateId(),
        createdAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }
}

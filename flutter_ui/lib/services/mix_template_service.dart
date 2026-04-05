/// Mix Template Service (P12.1.12)
///
/// Save/load bus mix settings as templates.
/// 5 built-in templates for common slot game scenarios:
/// - Base Game, Free Spins, Bonus, Big Win, Jackpot
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// MIX TEMPLATE MODELS
// =============================================================================

/// Bus mix settings for a single bus
class BusMixSettings {
  final int busId;
  final String busName;
  final double volume;     // 0.0 - 2.0 (linear), 1.0 = unity
  final double pan;        // -1.0 (L) to +1.0 (R)
  final bool muted;
  final bool soloed;
  final double auxSend1;   // Reverb send level (0.0 - 1.0)
  final double auxSend2;   // Delay send level (0.0 - 1.0)
  final double lowEqGain;  // Low shelf gain in dB (-12 to +12)
  final double midEqGain;  // Mid band gain in dB (-12 to +12)
  final double highEqGain; // High shelf gain in dB (-12 to +12)

  const BusMixSettings({
    required this.busId,
    required this.busName,
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
    this.auxSend1 = 0.0,
    this.auxSend2 = 0.0,
    this.lowEqGain = 0.0,
    this.midEqGain = 0.0,
    this.highEqGain = 0.0,
  });

  BusMixSettings copyWith({
    int? busId,
    String? busName,
    double? volume,
    double? pan,
    bool? muted,
    bool? soloed,
    double? auxSend1,
    double? auxSend2,
    double? lowEqGain,
    double? midEqGain,
    double? highEqGain,
  }) {
    return BusMixSettings(
      busId: busId ?? this.busId,
      busName: busName ?? this.busName,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      auxSend1: auxSend1 ?? this.auxSend1,
      auxSend2: auxSend2 ?? this.auxSend2,
      lowEqGain: lowEqGain ?? this.lowEqGain,
      midEqGain: midEqGain ?? this.midEqGain,
      highEqGain: highEqGain ?? this.highEqGain,
    );
  }

  Map<String, dynamic> toJson() => {
    'busId': busId,
    'busName': busName,
    'volume': volume,
    'pan': pan,
    'muted': muted,
    'soloed': soloed,
    'auxSend1': auxSend1,
    'auxSend2': auxSend2,
    'lowEqGain': lowEqGain,
    'midEqGain': midEqGain,
    'highEqGain': highEqGain,
  };

  factory BusMixSettings.fromJson(Map<String, dynamic> json) {
    return BusMixSettings(
      busId: json['busId'] as int? ?? 0,
      busName: json['busName'] as String? ?? 'Unknown',
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      muted: json['muted'] as bool? ?? false,
      soloed: json['soloed'] as bool? ?? false,
      auxSend1: (json['auxSend1'] as num?)?.toDouble() ?? 0.0,
      auxSend2: (json['auxSend2'] as num?)?.toDouble() ?? 0.0,
      lowEqGain: (json['lowEqGain'] as num?)?.toDouble() ?? 0.0,
      midEqGain: (json['midEqGain'] as num?)?.toDouble() ?? 0.0,
      highEqGain: (json['highEqGain'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Complete mix template with all bus settings
class MixTemplate {
  final String id;
  final String name;
  final String description;
  final String category; // 'built-in' or 'user'
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<BusMixSettings> busSettings;
  final double masterVolume;
  final double masterLimiterThreshold;

  const MixTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.createdAt,
    required this.modifiedAt,
    required this.busSettings,
    this.masterVolume = 1.0,
    this.masterLimiterThreshold = -0.3,
  });

  MixTemplate copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<BusMixSettings>? busSettings,
    double? masterVolume,
    double? masterLimiterThreshold,
  }) {
    return MixTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      busSettings: busSettings ?? this.busSettings,
      masterVolume: masterVolume ?? this.masterVolume,
      masterLimiterThreshold: masterLimiterThreshold ?? this.masterLimiterThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'busSettings': busSettings.map((b) => b.toJson()).toList(),
    'masterVolume': masterVolume,
    'masterLimiterThreshold': masterLimiterThreshold,
  };

  factory MixTemplate.fromJson(Map<String, dynamic> json) {
    return MixTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'user',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ?? DateTime.now(),
      busSettings: (json['busSettings'] as List<dynamic>?)
          ?.map((e) => BusMixSettings.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 1.0,
      masterLimiterThreshold: (json['masterLimiterThreshold'] as num?)?.toDouble() ?? -0.3,
    );
  }
}

// =============================================================================
// BUILT-IN MIX TEMPLATES (5 presets)
// =============================================================================

class BuiltInMixTemplates {
  static final List<MixTemplate> templates = [
    // Base Game — Balanced mix
    MixTemplate(
      id: 'base_game',
      name: 'Base Game',
      description: 'Balanced mix for standard base game play',
      category: 'built-in',
      createdAt: DateTime(2026, 1, 1),
      modifiedAt: DateTime(2026, 1, 1),
      masterVolume: 0.85,
      masterLimiterThreshold: -0.5,
      busSettings: [
        const BusMixSettings(busId: 0, busName: 'Master', volume: 1.0),
        const BusMixSettings(busId: 1, busName: 'Music', volume: 0.7, auxSend1: 0.15),
        const BusMixSettings(busId: 2, busName: 'SFX', volume: 0.85),
        const BusMixSettings(busId: 3, busName: 'Voice', volume: 1.0, lowEqGain: 2.0),
        const BusMixSettings(busId: 4, busName: 'Ambience', volume: 0.4, auxSend1: 0.3),
        const BusMixSettings(busId: 5, busName: 'UI', volume: 0.9),
      ],
    ),
    // Free Spins — Music emphasis
    MixTemplate(
      id: 'free_spins',
      name: 'Free Spins',
      description: 'Enhanced music and excitement for free spins',
      category: 'built-in',
      createdAt: DateTime(2026, 1, 1),
      modifiedAt: DateTime(2026, 1, 1),
      masterVolume: 0.9,
      masterLimiterThreshold: -0.3,
      busSettings: [
        const BusMixSettings(busId: 0, busName: 'Master', volume: 1.0),
        const BusMixSettings(busId: 1, busName: 'Music', volume: 0.85, auxSend1: 0.2, highEqGain: 1.5),
        const BusMixSettings(busId: 2, busName: 'SFX', volume: 0.9, highEqGain: 2.0),
        const BusMixSettings(busId: 3, busName: 'Voice', volume: 1.0),
        const BusMixSettings(busId: 4, busName: 'Ambience', volume: 0.3),
        const BusMixSettings(busId: 5, busName: 'UI', volume: 0.8),
      ],
    ),
    // Bonus — Dramatic emphasis
    MixTemplate(
      id: 'bonus',
      name: 'Bonus',
      description: 'Dramatic mix for bonus game sequences',
      category: 'built-in',
      createdAt: DateTime(2026, 1, 1),
      modifiedAt: DateTime(2026, 1, 1),
      masterVolume: 0.95,
      masterLimiterThreshold: -0.2,
      busSettings: [
        const BusMixSettings(busId: 0, busName: 'Master', volume: 1.0),
        const BusMixSettings(busId: 1, busName: 'Music', volume: 0.75, auxSend1: 0.25),
        const BusMixSettings(busId: 2, busName: 'SFX', volume: 1.0, lowEqGain: 2.0),
        const BusMixSettings(busId: 3, busName: 'Voice', volume: 1.1, lowEqGain: 3.0),
        const BusMixSettings(busId: 4, busName: 'Ambience', volume: 0.5, auxSend1: 0.4),
        const BusMixSettings(busId: 5, busName: 'UI', volume: 0.85),
      ],
    ),
    // Big Win — Celebration mode
    MixTemplate(
      id: 'big_win',
      name: 'Big Win',
      description: 'High energy celebration mix for big wins',
      category: 'built-in',
      createdAt: DateTime(2026, 1, 1),
      modifiedAt: DateTime(2026, 1, 1),
      masterVolume: 1.0,
      masterLimiterThreshold: -0.1,
      busSettings: [
        const BusMixSettings(busId: 0, busName: 'Master', volume: 1.0),
        const BusMixSettings(busId: 1, busName: 'Music', volume: 0.9, auxSend1: 0.1, highEqGain: 3.0),
        const BusMixSettings(busId: 2, busName: 'SFX', volume: 1.0, lowEqGain: 3.0, highEqGain: 2.0),
        const BusMixSettings(busId: 3, busName: 'Voice', volume: 1.2, lowEqGain: 2.0),
        const BusMixSettings(busId: 4, busName: 'Ambience', volume: 0.2, muted: true),
        const BusMixSettings(busId: 5, busName: 'UI', volume: 0.7),
      ],
    ),
    // Jackpot — Maximum impact
    MixTemplate(
      id: 'jackpot',
      name: 'Jackpot',
      description: 'Maximum impact mix for jackpot wins',
      category: 'built-in',
      createdAt: DateTime(2026, 1, 1),
      modifiedAt: DateTime(2026, 1, 1),
      masterVolume: 1.0,
      masterLimiterThreshold: 0.0,
      busSettings: [
        const BusMixSettings(busId: 0, busName: 'Master', volume: 1.0),
        const BusMixSettings(busId: 1, busName: 'Music', volume: 1.0, auxSend1: 0.3, lowEqGain: 4.0, highEqGain: 3.0),
        const BusMixSettings(busId: 2, busName: 'SFX', volume: 1.0, lowEqGain: 4.0, highEqGain: 4.0, auxSend2: 0.15),
        const BusMixSettings(busId: 3, busName: 'Voice', volume: 1.3, auxSend1: 0.2),
        const BusMixSettings(busId: 4, busName: 'Ambience', muted: true),
        const BusMixSettings(busId: 5, busName: 'UI', volume: 0.6),
      ],
    ),
  ];
}

// =============================================================================
// MIX TEMPLATE SERVICE — Singleton
// =============================================================================

class MixTemplateService extends ChangeNotifier {
  static final MixTemplateService _instance = MixTemplateService._();
  static MixTemplateService get instance => _instance;

  MixTemplateService._();

  static const String _prefsKey = 'fluxforge_mix_templates';
  static const String _activeKey = 'fluxforge_active_mix_template';

  final List<MixTemplate> _userTemplates = [];
  String? _activeTemplateId;
  bool _isInitialized = false;

  // ─── Getters ────────────────────────────────────────────────────────────────

  List<MixTemplate> get builtInTemplates => BuiltInMixTemplates.templates;

  List<MixTemplate> get userTemplates => List.unmodifiable(_userTemplates);

  List<MixTemplate> get allTemplates => [...builtInTemplates, ..._userTemplates];

  String? get activeTemplateId => _activeTemplateId;

  MixTemplate? get activeTemplate {
    if (_activeTemplateId == null) return null;
    return allTemplates.firstWhere(
      (t) => t.id == _activeTemplateId,
      orElse: () => builtInTemplates.first,
    );
  }

  bool get isInitialized => _isInitialized;

  // ─── Initialization ─────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load user templates
      final templatesJson = prefs.getString(_prefsKey);
      if (templatesJson != null) {
        final List<dynamic> decoded = jsonDecode(templatesJson);
        _userTemplates.clear();
        _userTemplates.addAll(
          decoded.map((e) => MixTemplate.fromJson(e as Map<String, dynamic>)),
        );
      }

      // Load active template
      _activeTemplateId = prefs.getString(_activeKey);

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _isInitialized = true;
    }
  }

  // ─── Template CRUD ──────────────────────────────────────────────────────────

  Future<void> saveTemplate(MixTemplate template) async {
    final existingIndex = _userTemplates.indexWhere((t) => t.id == template.id);
    final updatedTemplate = template.copyWith(modifiedAt: DateTime.now());

    if (existingIndex >= 0) {
      _userTemplates[existingIndex] = updatedTemplate;
    } else {
      _userTemplates.add(updatedTemplate);
    }

    await _persist();
    notifyListeners();
  }

  Future<void> deleteTemplate(String templateId) async {
    _userTemplates.removeWhere((t) => t.id == templateId);

    if (_activeTemplateId == templateId) {
      _activeTemplateId = null;
    }

    await _persist();
    notifyListeners();
  }

  Future<void> setActiveTemplate(String? templateId) async {
    _activeTemplateId = templateId;

    final prefs = await SharedPreferences.getInstance();
    if (templateId != null) {
      await prefs.setString(_activeKey, templateId);
    } else {
      await prefs.remove(_activeKey);
    }

    notifyListeners();
  }

  MixTemplate? getTemplateById(String id) {
    return allTemplates.firstWhere(
      (t) => t.id == id,
      orElse: () => builtInTemplates.first,
    );
  }

  // ─── Import/Export ──────────────────────────────────────────────────────────

  Future<bool> exportTemplate(MixTemplate template, String filePath) async {
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(template.toJson());
      final file = File(filePath);
      await file.writeAsString(jsonStr);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<MixTemplate?> importTemplate(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final template = MixTemplate.fromJson(json).copyWith(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        category: 'user',
      );

      await saveTemplate(template);
      return template;
    } catch (e) {
      return null;
    }
  }

  // ─── Persistence ────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_userTemplates.map((t) => t.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);
    } catch (e) { /* ignored */ }
  }
}

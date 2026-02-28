/// SlotLab Template Provider — Middleware §31
///
/// 7 SlotLab-specific project templates with pre-configured behavior trees,
/// bus routing, ducking rules, and win tier settings.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §31

import 'package:flutter/foundation.dart';

/// Template categories
enum TemplateCategory {
  /// Simple 5-reel, 3-row slot with basic audio
  classic,
  /// Cluster-pays or Megaways with cascades
  cascade,
  /// Feature-heavy with multiple bonus rounds
  featureRich,
  /// Progressive jackpot with tiered reveals
  jackpot,
  /// Multi-game/hold-and-win mechanic
  holdAndWin,
  /// Asian-themed high-volatility
  highVolatility,
  /// Minimalist/mobile-first with reduced audio layers
  mobile,
}

extension TemplateCategoryExtension on TemplateCategory {
  String get displayName {
    switch (this) {
      case TemplateCategory.classic: return 'Classic';
      case TemplateCategory.cascade: return 'Cascade';
      case TemplateCategory.featureRich: return 'Feature Rich';
      case TemplateCategory.jackpot: return 'Jackpot';
      case TemplateCategory.holdAndWin: return 'Hold & Win';
      case TemplateCategory.highVolatility: return 'High Volatility';
      case TemplateCategory.mobile: return 'Mobile';
    }
  }

  String get description {
    switch (this) {
      case TemplateCategory.classic: return '5×3 grid, 20 paylines, standard win tiers';
      case TemplateCategory.cascade: return 'Cluster/Megaways with cascade chains, multi-stage wins';
      case TemplateCategory.featureRich: return 'Multiple bonus rounds, feature transitions, layered music';
      case TemplateCategory.jackpot: return 'Progressive pools, tiered reveals (Mini/Major/Grand)';
      case TemplateCategory.holdAndWin: return 'Hold & Spin mechanic with respins and collect';
      case TemplateCategory.highVolatility: return 'Large multipliers, extended anticipation, dramatic audio';
      case TemplateCategory.mobile: return 'Optimized for mobile, reduced voice pool, efficient audio';
    }
  }

  /// Default reel count for this template type
  int get defaultReels {
    switch (this) {
      case TemplateCategory.classic: return 5;
      case TemplateCategory.cascade: return 6;
      case TemplateCategory.featureRich: return 5;
      case TemplateCategory.jackpot: return 5;
      case TemplateCategory.holdAndWin: return 5;
      case TemplateCategory.highVolatility: return 5;
      case TemplateCategory.mobile: return 5;
    }
  }

  /// Default row count for this template type
  int get defaultRows {
    switch (this) {
      case TemplateCategory.classic: return 3;
      case TemplateCategory.cascade: return 4;
      case TemplateCategory.featureRich: return 3;
      case TemplateCategory.jackpot: return 3;
      case TemplateCategory.holdAndWin: return 5;
      case TemplateCategory.highVolatility: return 4;
      case TemplateCategory.mobile: return 3;
    }
  }

  /// Default voice pool size
  int get defaultVoicePool {
    switch (this) {
      case TemplateCategory.classic: return 32;
      case TemplateCategory.cascade: return 48;
      case TemplateCategory.featureRich: return 48;
      case TemplateCategory.jackpot: return 48;
      case TemplateCategory.holdAndWin: return 36;
      case TemplateCategory.highVolatility: return 48;
      case TemplateCategory.mobile: return 24;
    }
  }

  /// Whether cascades are enabled by default
  bool get defaultCascadesEnabled {
    switch (this) {
      case TemplateCategory.cascade: return true;
      case TemplateCategory.featureRich: return true;
      default: return false;
    }
  }
}

/// A template with its full configuration
class SlotLabTemplate {
  final String id;
  final String name;
  final TemplateCategory category;
  final String description;
  final int reels;
  final int rows;
  final int voicePoolSize;
  final bool cascadesEnabled;
  final bool freeSpinsEnabled;
  final bool jackpotEnabled;
  /// Serialized behavior tree configuration
  final Map<String, dynamic>? behaviorTreeConfig;
  /// Serialized bus routing configuration
  final Map<String, dynamic>? busConfig;
  /// Serialized ducking rules
  final List<Map<String, dynamic>>? duckingRules;
  /// Serialized win tier config
  final Map<String, dynamic>? winTierConfig;
  /// Serialized context overrides
  final Map<String, dynamic>? contextOverrides;
  /// Template creation timestamp
  final DateTime createdAt;

  const SlotLabTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.reels = 5,
    this.rows = 3,
    this.voicePoolSize = 32,
    this.cascadesEnabled = false,
    this.freeSpinsEnabled = true,
    this.jackpotEnabled = false,
    this.behaviorTreeConfig,
    this.busConfig,
    this.duckingRules,
    this.winTierConfig,
    this.contextOverrides,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'description': description,
    'reels': reels,
    'rows': rows,
    'voicePoolSize': voicePoolSize,
    'cascadesEnabled': cascadesEnabled,
    'freeSpinsEnabled': freeSpinsEnabled,
    'jackpotEnabled': jackpotEnabled,
    'behaviorTreeConfig': behaviorTreeConfig,
    'busConfig': busConfig,
    'duckingRules': duckingRules,
    'winTierConfig': winTierConfig,
    'contextOverrides': contextOverrides,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SlotLabTemplate.fromJson(Map<String, dynamic> json) => SlotLabTemplate(
    id: json['id'] as String,
    name: json['name'] as String,
    category: TemplateCategory.values.byName(json['category'] as String),
    description: json['description'] as String,
    reels: json['reels'] as int? ?? 5,
    rows: json['rows'] as int? ?? 3,
    voicePoolSize: json['voicePoolSize'] as int? ?? 32,
    cascadesEnabled: json['cascadesEnabled'] as bool? ?? false,
    freeSpinsEnabled: json['freeSpinsEnabled'] as bool? ?? true,
    jackpotEnabled: json['jackpotEnabled'] as bool? ?? false,
    behaviorTreeConfig: json['behaviorTreeConfig'] as Map<String, dynamic>?,
    busConfig: json['busConfig'] as Map<String, dynamic>?,
    duckingRules: (json['duckingRules'] as List<dynamic>?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList(),
    winTierConfig: json['winTierConfig'] as Map<String, dynamic>?,
    contextOverrides: json['contextOverrides'] as Map<String, dynamic>?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class SlotLabTemplateProvider extends ChangeNotifier {
  /// Built-in templates
  final List<SlotLabTemplate> _builtInTemplates = [];

  /// User-created templates
  final List<SlotLabTemplate> _userTemplates = [];

  /// Currently selected template for preview
  String? _selectedTemplateId;

  SlotLabTemplateProvider() {
    _initBuiltInTemplates();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<SlotLabTemplate> get builtInTemplates => List.unmodifiable(_builtInTemplates);
  List<SlotLabTemplate> get userTemplates => List.unmodifiable(_userTemplates);
  List<SlotLabTemplate> get allTemplates => [..._builtInTemplates, ..._userTemplates];
  String? get selectedTemplateId => _selectedTemplateId;

  SlotLabTemplate? getTemplate(String id) {
    return allTemplates.where((t) => t.id == id).firstOrNull;
  }

  List<SlotLabTemplate> getByCategory(TemplateCategory category) =>
      allTemplates.where((t) => t.category == category).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPLATE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void selectTemplate(String? templateId) {
    _selectedTemplateId = templateId;
    notifyListeners();
  }

  /// Save current config as a user template
  void saveUserTemplate({
    required String name,
    required TemplateCategory category,
    required String description,
    required int reels,
    required int rows,
    required int voicePoolSize,
    Map<String, dynamic>? behaviorTreeConfig,
    Map<String, dynamic>? busConfig,
    List<Map<String, dynamic>>? duckingRules,
    Map<String, dynamic>? winTierConfig,
    Map<String, dynamic>? contextOverrides,
  }) {
    final template = SlotLabTemplate(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      category: category,
      description: description,
      reels: reels,
      rows: rows,
      voicePoolSize: voicePoolSize,
      behaviorTreeConfig: behaviorTreeConfig,
      busConfig: busConfig,
      duckingRules: duckingRules,
      winTierConfig: winTierConfig,
      contextOverrides: contextOverrides,
      createdAt: DateTime.now(),
    );
    _userTemplates.add(template);
    notifyListeners();
  }

  /// Remove a user template
  void removeUserTemplate(String id) {
    _userTemplates.removeWhere((t) => t.id == id);
    if (_selectedTemplateId == id) _selectedTemplateId = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILT-IN TEMPLATES
  // ═══════════════════════════════════════════════════════════════════════════

  void _initBuiltInTemplates() {
    final now = DateTime.now();
    for (final cat in TemplateCategory.values) {
      _builtInTemplates.add(SlotLabTemplate(
        id: 'builtin_${cat.name}',
        name: cat.displayName,
        category: cat,
        description: cat.description,
        reels: cat.defaultReels,
        rows: cat.defaultRows,
        voicePoolSize: cat.defaultVoicePool,
        cascadesEnabled: cat.defaultCascadesEnabled,
        freeSpinsEnabled: true,
        jackpotEnabled: cat == TemplateCategory.jackpot,
        createdAt: now,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'userTemplates': _userTemplates.map((t) => t.toJson()).toList(),
    'selectedTemplateId': _selectedTemplateId,
  };

  void fromJson(Map<String, dynamic> json) {
    _userTemplates.clear();
    final templatesList = json['userTemplates'] as List<dynamic>?;
    if (templatesList != null) {
      for (final item in templatesList) {
        _userTemplates.add(SlotLabTemplate.fromJson(item as Map<String, dynamic>));
      }
    }
    _selectedTemplateId = json['selectedTemplateId'] as String?;
    notifyListeners();
  }
}

/// Event Template Service
///
/// Pre-defined audio event templates for common slot game scenarios:
/// - Spin events (start, stop, loop)
/// - Win events (small, big, mega, epic)
/// - Feature events (free spins, bonus, cascade)
/// - UI events (buttons, menus)
/// - Custom template creation
///
/// Created: 2026-01-30 (P4.25)

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/slot_audio_events.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EVENT TEMPLATE MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Template for creating audio events
class EventTemplate {
  final String id;
  final String name;
  final String description;
  final EventTemplateCategory category;
  final String stage;
  final List<EventTemplateLayer> layers;
  final bool isBuiltIn;
  final String? icon;
  final Map<String, dynamic>? metadata;

  const EventTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.stage,
    this.layers = const [],
    this.isBuiltIn = false,
    this.icon,
    this.metadata,
  });

  EventTemplate copyWith({
    String? id,
    String? name,
    String? description,
    EventTemplateCategory? category,
    String? stage,
    List<EventTemplateLayer>? layers,
    bool? isBuiltIn,
    String? icon,
    Map<String, dynamic>? metadata,
  }) {
    return EventTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      stage: stage ?? this.stage,
      layers: layers ?? this.layers,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      icon: icon ?? this.icon,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category.index,
        'stage': stage,
        'layers': layers.map((l) => l.toJson()).toList(),
        'isBuiltIn': isBuiltIn,
        'icon': icon,
        'metadata': metadata,
      };

  factory EventTemplate.fromJson(Map<String, dynamic> json) {
    return EventTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      category: EventTemplateCategory.values[json['category'] as int? ?? 0],
      stage: json['stage'] as String,
      layers: (json['layers'] as List<dynamic>?)
              ?.map((l) => EventTemplateLayer.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      icon: json['icon'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Create a SlotCompositeEvent from this template
  SlotCompositeEvent toEvent({
    required String eventId,
    String? customName,
    String? customStage,
    Color? customColor,
  }) {
    final now = DateTime.now();
    return SlotCompositeEvent(
      id: eventId,
      name: customName ?? name,
      category: category.name,
      color: customColor ?? _categoryToColor(category),
      triggerStages: customStage != null ? [customStage] : [stage],
      createdAt: now,
      modifiedAt: now,
      layers: layers
          .asMap()
          .entries
          .map((entry) => SlotEventLayer(
                id: '${eventId}_layer_${entry.key}',
                name: entry.value.hint ?? 'Layer ${entry.key + 1}',
                audioPath: '', // User needs to assign audio
                volume: entry.value.volume,
                pan: entry.value.pan,
                offsetMs: entry.value.offsetMs,
                busId: entry.value.busId,
              ))
          .toList(),
    );
  }

  /// Get color for template category
  static Color _categoryToColor(EventTemplateCategory category) {
    switch (category) {
      case EventTemplateCategory.spin:
        return const Color(0xFF4A9EFF);
      case EventTemplateCategory.win:
        return const Color(0xFFFFD700);
      case EventTemplateCategory.feature:
        return const Color(0xFF40FF90);
      case EventTemplateCategory.cascade:
        return const Color(0xFFFF6B6B);
      case EventTemplateCategory.ui:
        return const Color(0xFF808080);
      case EventTemplateCategory.music:
        return const Color(0xFF40C8FF);
      case EventTemplateCategory.custom:
        return const Color(0xFF9370DB);
    }
  }
}

/// Template layer configuration
class EventTemplateLayer {
  final double volume;
  final double pan;
  final double offsetMs;
  final int busId;
  final String? hint;

  const EventTemplateLayer({
    this.volume = 1.0,
    this.pan = 0.0,
    this.offsetMs = 0,
    this.busId = 2, // SFX bus
    this.hint,
  });

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'pan': pan,
        'offsetMs': offsetMs,
        'busId': busId,
        'hint': hint,
      };

  factory EventTemplateLayer.fromJson(Map<String, dynamic> json) {
    return EventTemplateLayer(
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      offsetMs: (json['offsetMs'] as num?)?.toDouble() ?? 0.0,
      busId: json['busId'] as int? ?? 2,
      hint: json['hint'] as String?,
    );
  }
}

/// Template categories
enum EventTemplateCategory {
  spin,
  win,
  feature,
  cascade,
  ui,
  music,
  custom,
}

extension EventTemplateCategoryExtension on EventTemplateCategory {
  String get displayName {
    switch (this) {
      case EventTemplateCategory.spin:
        return 'Spin Events';
      case EventTemplateCategory.win:
        return 'Win Events';
      case EventTemplateCategory.feature:
        return 'Feature Events';
      case EventTemplateCategory.cascade:
        return 'Cascade Events';
      case EventTemplateCategory.ui:
        return 'UI Events';
      case EventTemplateCategory.music:
        return 'Music Events';
      case EventTemplateCategory.custom:
        return 'Custom Templates';
    }
  }

  String get icon {
    switch (this) {
      case EventTemplateCategory.spin:
        return '🎰';
      case EventTemplateCategory.win:
        return '🏆';
      case EventTemplateCategory.feature:
        return '⭐';
      case EventTemplateCategory.cascade:
        return '💫';
      case EventTemplateCategory.ui:
        return '🔘';
      case EventTemplateCategory.music:
        return '🎵';
      case EventTemplateCategory.custom:
        return '📝';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN TEMPLATES
// ═══════════════════════════════════════════════════════════════════════════

class BuiltInEventTemplates {
  BuiltInEventTemplates._();

  // Spin templates
  static const spinStart = EventTemplate(
    id: 'tpl_spin_start',
    name: 'Spin Start',
    description: 'Button press and spin initiation sound',
    category: EventTemplateCategory.spin,
    stage: 'SPIN_START',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 1.0, hint: 'Button click'),
      EventTemplateLayer(volume: 0.7, offsetMs: 50, hint: 'Whoosh'),
    ],
  );

  static const reelStop = EventTemplate(
    id: 'tpl_reel_stop',
    name: 'Reel Stop',
    description: 'Individual reel landing sound',
    category: EventTemplateCategory.spin,
    stage: 'REEL_STOP',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.9, hint: 'Thud/click'),
    ],
  );

  static const spinLoop = EventTemplate(
    id: 'tpl_spin_loop',
    name: 'Spin Loop',
    description: 'Continuous spinning sound (looping)',
    category: EventTemplateCategory.spin,
    stage: 'REEL_SPINNING',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.6, hint: 'Looping whoosh'),
    ],
  );

  // Win templates
  static const winSmall = EventTemplate(
    id: 'tpl_win_small',
    name: 'Small Win',
    description: 'Minor win celebration (<5x)',
    category: EventTemplateCategory.win,
    stage: 'WIN_PRESENT_SMALL',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.8, hint: 'Coin jingle'),
    ],
  );

  static const winBig = EventTemplate(
    id: 'tpl_win_big',
    name: 'Big Win',
    description: 'Major win fanfare (5x-15x)',
    category: EventTemplateCategory.win,
    stage: 'WIN_PRESENT_BIG',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 1.0, hint: 'Fanfare'),
      EventTemplateLayer(volume: 0.7, offsetMs: 100, hint: 'Coin shower'),
      EventTemplateLayer(volume: 0.5, offsetMs: 500, hint: 'Crowd cheer'),
    ],
  );

  static const winMega = EventTemplate(
    id: 'tpl_win_mega',
    name: 'Mega Win',
    description: 'Epic win celebration (30x+)',
    category: EventTemplateCategory.win,
    stage: 'WIN_PRESENT_MEGA',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 1.0, hint: 'Epic fanfare'),
      EventTemplateLayer(volume: 0.8, offsetMs: 200, hint: 'Coin avalanche'),
      EventTemplateLayer(volume: 0.6, offsetMs: 800, hint: 'Orchestra swell'),
      EventTemplateLayer(volume: 0.5, offsetMs: 1500, hint: 'Celebration loop'),
    ],
  );

  static const rollupTick = EventTemplate(
    id: 'tpl_rollup_tick',
    name: 'Rollup Tick',
    description: 'Counter increment sound',
    category: EventTemplateCategory.win,
    stage: 'ROLLUP_TICK',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.4, hint: 'Tick/blip'),
    ],
  );

  // Feature templates
  static const fsTrigger = EventTemplate(
    id: 'tpl_fs_trigger',
    name: 'Free Spins Trigger',
    description: 'Free spins feature activation',
    category: EventTemplateCategory.feature,
    stage: 'FS_TRIGGER',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 1.0, hint: 'Alert/announce'),
      EventTemplateLayer(volume: 0.8, offsetMs: 300, hint: 'Scatter collect'),
      EventTemplateLayer(volume: 0.6, offsetMs: 800, busId: 1, hint: 'Transition music'),
    ],
  );

  static const bonusEnter = EventTemplate(
    id: 'tpl_bonus_enter',
    name: 'Bonus Enter',
    description: 'Bonus game transition',
    category: EventTemplateCategory.feature,
    stage: 'BONUS_ENTER',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 1.0, hint: 'Whoosh transition'),
      EventTemplateLayer(volume: 0.9, offsetMs: 500, busId: 1, hint: 'Bonus music start'),
    ],
  );

  static const anticipation = EventTemplate(
    id: 'tpl_anticipation',
    name: 'Anticipation',
    description: 'Building tension for potential win',
    category: EventTemplateCategory.feature,
    stage: 'ANTICIPATION_ON',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.7, hint: 'Tension riser'),
      EventTemplateLayer(volume: 0.5, offsetMs: 200, busId: 1, hint: 'Heartbeat loop'),
    ],
  );

  // Cascade templates
  static const cascadeStart = EventTemplate(
    id: 'tpl_cascade_start',
    name: 'Cascade Start',
    description: 'Beginning of cascade sequence',
    category: EventTemplateCategory.cascade,
    stage: 'CASCADE_START',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.9, hint: 'Shatter/explode'),
    ],
  );

  static const cascadeStep = EventTemplate(
    id: 'tpl_cascade_step',
    name: 'Cascade Step',
    description: 'Each cascade iteration',
    category: EventTemplateCategory.cascade,
    stage: 'CASCADE_STEP',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.8, hint: 'Drop/fall'),
      EventTemplateLayer(volume: 0.5, offsetMs: 100, hint: 'Land'),
    ],
  );

  // UI templates
  static const buttonPress = EventTemplate(
    id: 'tpl_button_press',
    name: 'Button Press',
    description: 'Generic UI button click',
    category: EventTemplateCategory.ui,
    stage: 'UI_BUTTON_PRESS',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.6, busId: 4, hint: 'Click'),
    ],
  );

  static const menuOpen = EventTemplate(
    id: 'tpl_menu_open',
    name: 'Menu Open',
    description: 'Menu/panel appearance',
    category: EventTemplateCategory.ui,
    stage: 'UI_MENU_OPEN',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.5, busId: 4, hint: 'Slide/swoosh'),
    ],
  );

  // Music templates
  static const baseMusic = EventTemplate(
    id: 'tpl_base_music',
    name: 'Base Game Music',
    description: 'Main game background music',
    category: EventTemplateCategory.music,
    stage: 'MUSIC_BASE',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.6, busId: 1, hint: 'Base music loop'),
    ],
  );

  static const featureMusic = EventTemplate(
    id: 'tpl_feature_music',
    name: 'Feature Music',
    description: 'Feature/bonus music',
    category: EventTemplateCategory.music,
    stage: 'MUSIC_FEATURE',
    isBuiltIn: true,
    layers: [
      EventTemplateLayer(volume: 0.7, busId: 1, hint: 'Feature music loop'),
    ],
  );

  static final List<EventTemplate> all = [
    // Spin
    spinStart,
    reelStop,
    spinLoop,
    // Win
    winSmall,
    winBig,
    winMega,
    rollupTick,
    // Feature
    fsTrigger,
    bonusEnter,
    anticipation,
    // Cascade
    cascadeStart,
    cascadeStep,
    // UI
    buttonPress,
    menuOpen,
    // Music
    baseMusic,
    featureMusic,
  ];

  static List<EventTemplate> byCategory(EventTemplateCategory category) {
    return all.where((t) => t.category == category).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT TEMPLATE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing event templates
class EventTemplateService extends ChangeNotifier {
  EventTemplateService._();
  static final instance = EventTemplateService._();

  static const _prefsKeyCustomTemplates = 'event_templates_custom';

  final List<EventTemplate> _customTemplates = [];
  bool _initialized = false;

  bool get initialized => _initialized;

  /// All templates (built-in + custom)
  List<EventTemplate> get allTemplates => [
        ...BuiltInEventTemplates.all,
        ..._customTemplates,
      ];

  /// Custom templates only
  List<EventTemplate> get customTemplates => List.unmodifiable(_customTemplates);

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final customJson = prefs.getString(_prefsKeyCustomTemplates);

      if (customJson != null) {
        final list = jsonDecode(customJson) as List;
        for (final json in list) {
          _customTemplates.add(EventTemplate.fromJson(json as Map<String, dynamic>));
        }
      }

      _initialized = true;
      notifyListeners();
      debugPrint('[EventTemplateService] Initialized: ${_customTemplates.length} custom templates');
    } catch (e) {
      debugPrint('[EventTemplateService] Init error: $e');
      _initialized = true;
    }
  }

  /// Get templates by category
  List<EventTemplate> getByCategory(EventTemplateCategory category) {
    return allTemplates.where((t) => t.category == category).toList();
  }

  /// Get template by ID
  EventTemplate? getById(String id) {
    try {
      return allTemplates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Create custom template
  Future<EventTemplate> createTemplate({
    required String name,
    required String description,
    required String stage,
    List<EventTemplateLayer> layers = const [],
  }) async {
    final template = EventTemplate(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      category: EventTemplateCategory.custom,
      stage: stage,
      layers: layers,
      isBuiltIn: false,
    );

    _customTemplates.add(template);
    await _save();
    notifyListeners();

    debugPrint('[EventTemplateService] Created template: ${template.name}');
    return template;
  }

  /// Update custom template
  Future<void> updateTemplate(EventTemplate template) async {
    if (template.isBuiltIn) {
      debugPrint('[EventTemplateService] Cannot update built-in template');
      return;
    }

    final index = _customTemplates.indexWhere((t) => t.id == template.id);
    if (index >= 0) {
      _customTemplates[index] = template;
      await _save();
      notifyListeners();
      debugPrint('[EventTemplateService] Updated template: ${template.name}');
    }
  }

  /// Delete custom template
  Future<void> deleteTemplate(String templateId) async {
    final template = _customTemplates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => BuiltInEventTemplates.spinStart,
    );

    if (template.isBuiltIn) {
      debugPrint('[EventTemplateService] Cannot delete built-in template');
      return;
    }

    _customTemplates.removeWhere((t) => t.id == templateId);
    await _save();
    notifyListeners();
    debugPrint('[EventTemplateService] Deleted template: $templateId');
  }

  /// Duplicate template
  Future<EventTemplate> duplicateTemplate(String templateId) async {
    final source = getById(templateId);
    if (source == null) {
      throw Exception('Template not found: $templateId');
    }

    return createTemplate(
      name: '${source.name} (Copy)',
      description: source.description,
      stage: source.stage,
      layers: source.layers,
    );
  }

  /// Export template to JSON
  String exportTemplate(String templateId) {
    final template = getById(templateId);
    if (template == null) return '{}';
    return jsonEncode(template.toJson());
  }

  /// Import template from JSON
  Future<EventTemplate?> importTemplate(String json) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final template = EventTemplate.fromJson(data).copyWith(
        id: 'imported_${DateTime.now().millisecondsSinceEpoch}',
        isBuiltIn: false,
        name: '${data['name']} (Imported)',
      );

      _customTemplates.add(template);
      await _save();
      notifyListeners();

      debugPrint('[EventTemplateService] Imported template: ${template.name}');
      return template;
    } catch (e) {
      debugPrint('[EventTemplateService] Import error: $e');
      return null;
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customJson = jsonEncode(_customTemplates.map((t) => t.toJson()).toList());
      await prefs.setString(_prefsKeyCustomTemplates, customJson);
    } catch (e) {
      debugPrint('[EventTemplateService] Save error: $e');
    }
  }
}

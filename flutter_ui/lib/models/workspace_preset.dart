/// Workspace Preset Model (M3.2)
///
/// Defines workspace configuration presets for save/load of panel layouts.
/// Supports active tabs, expanded states, and panel heights.

import 'dart:convert';

/// Workspace section enum for different app areas
enum WorkspaceSection {
  daw,
  middleware,
  slotLab;

  String get displayName {
    switch (this) {
      case WorkspaceSection.daw:
        return 'DAW';
      case WorkspaceSection.middleware:
        return 'Middleware';
      case WorkspaceSection.slotLab:
        return 'Slot Lab';
    }
  }
}

/// Workspace preset configuration
class WorkspacePreset {
  final String id;
  final String name;
  final String? description;
  final WorkspaceSection section;
  final List<String> activeTabs;
  final List<String> expandedCategories;
  final double lowerZoneHeight;
  final bool lowerZoneExpanded;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isBuiltIn;

  const WorkspacePreset({
    required this.id,
    required this.name,
    this.description,
    required this.section,
    required this.activeTabs,
    this.expandedCategories = const [],
    this.lowerZoneHeight = 300,
    this.lowerZoneExpanded = true,
    required this.createdAt,
    required this.modifiedAt,
    this.isBuiltIn = false,
  });

  WorkspacePreset copyWith({
    String? id,
    String? name,
    String? description,
    WorkspaceSection? section,
    List<String>? activeTabs,
    List<String>? expandedCategories,
    double? lowerZoneHeight,
    bool? lowerZoneExpanded,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isBuiltIn,
  }) {
    return WorkspacePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      section: section ?? this.section,
      activeTabs: activeTabs ?? this.activeTabs,
      expandedCategories: expandedCategories ?? this.expandedCategories,
      lowerZoneHeight: lowerZoneHeight ?? this.lowerZoneHeight,
      lowerZoneExpanded: lowerZoneExpanded ?? this.lowerZoneExpanded,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'section': section.name,
        'activeTabs': activeTabs,
        'expandedCategories': expandedCategories,
        'lowerZoneHeight': lowerZoneHeight,
        'lowerZoneExpanded': lowerZoneExpanded,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'isBuiltIn': isBuiltIn,
      };

  factory WorkspacePreset.fromJson(Map<String, dynamic> json) {
    return WorkspacePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      section: WorkspaceSection.values.firstWhere(
        (s) => s.name == json['section'],
        orElse: () => WorkspaceSection.slotLab,
      ),
      activeTabs: (json['activeTabs'] as List<dynamic>).cast<String>(),
      expandedCategories:
          (json['expandedCategories'] as List<dynamic>?)?.cast<String>() ?? [],
      lowerZoneHeight: (json['lowerZoneHeight'] as num?)?.toDouble() ?? 300,
      lowerZoneExpanded: json['lowerZoneExpanded'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory WorkspacePreset.fromJsonString(String jsonString) {
    return WorkspacePreset.fromJson(jsonDecode(jsonString));
  }

  @override
  String toString() => 'WorkspacePreset(name: $name, section: $section)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspacePreset &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Built-in workspace presets
class BuiltInWorkspacePresets {
  static final now = DateTime.now();

  /// Audio Design preset - focused on event creation and containers
  static final audioDesign = WorkspacePreset(
    id: 'builtin_audio_design',
    name: 'Audio Design',
    description: 'Focus on audio events and containers',
    section: WorkspaceSection.slotLab,
    activeTabs: ['events', 'blend', 'random', 'sequence'],
    expandedCategories: ['audio'],
    lowerZoneHeight: 350,
    lowerZoneExpanded: true,
    createdAt: now,
    modifiedAt: now,
    isBuiltIn: true,
  );

  /// Routing preset - focused on bus hierarchy and ducking
  static final routing = WorkspacePreset(
    id: 'builtin_routing',
    name: 'Routing',
    description: 'Focus on bus routing and ducking',
    section: WorkspaceSection.slotLab,
    activeTabs: ['buses', 'ducking', 'auxSends'],
    expandedCategories: ['routing'],
    lowerZoneHeight: 300,
    lowerZoneExpanded: true,
    createdAt: now,
    modifiedAt: now,
    isBuiltIn: true,
  );

  /// Debug preset - focused on debugging and profiling
  static final debug = WorkspacePreset(
    id: 'builtin_debug',
    name: 'Debug',
    description: 'Focus on debugging and profiling',
    section: WorkspaceSection.slotLab,
    activeTabs: ['profiler', 'voicePool', 'memory', 'dspLoad'],
    expandedCategories: ['debug'],
    lowerZoneHeight: 400,
    lowerZoneExpanded: true,
    createdAt: now,
    modifiedAt: now,
    isBuiltIn: true,
  );

  /// Mixing preset - focused on mixing and DSP
  static final mixing = WorkspacePreset(
    id: 'builtin_mixing',
    name: 'Mixing',
    description: 'Focus on mixing and effects',
    section: WorkspaceSection.slotLab,
    activeTabs: ['compressor', 'limiter', 'reverb'],
    expandedCategories: ['dsp'],
    lowerZoneHeight: 350,
    lowerZoneExpanded: true,
    createdAt: now,
    modifiedAt: now,
    isBuiltIn: true,
  );

  /// Spatial preset - focused on spatial audio
  static final spatial = WorkspacePreset(
    id: 'builtin_spatial',
    name: 'Spatial',
    description: 'Focus on spatial audio and positioning',
    section: WorkspaceSection.slotLab,
    activeTabs: ['autoSpatial', 'attenuation'],
    expandedCategories: ['advanced'],
    lowerZoneHeight: 350,
    lowerZoneExpanded: true,
    createdAt: now,
    modifiedAt: now,
    isBuiltIn: true,
  );

  /// All built-in presets
  static List<WorkspacePreset> get all => [
        audioDesign,
        routing,
        debug,
        mixing,
        spatial,
      ];

  /// Get built-in presets by section
  static List<WorkspacePreset> bySection(WorkspaceSection section) {
    return all.where((p) => p.section == section).toList();
  }
}

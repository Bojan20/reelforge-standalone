/// Workspace Layout Preset Model (P1.1)
///
/// Saves/loads DAW Lower Zone layout configurations.
///
/// Created: 2026-01-26
library;

import '../widgets/lower_zone/lower_zone_types.dart';

class WorkspaceLayoutPreset {
  final String id;
  final String name;
  final DawSuperTab superTab;
  final int subTabIndex;
  final double height;
  final bool isExpanded;
  final bool isBuiltIn;
  final DateTime? createdAt;

  const WorkspaceLayoutPreset({
    required this.id,
    required this.name,
    required this.superTab,
    this.subTabIndex = 0,
    this.height = 500.0,
    this.isExpanded = true,
    this.isBuiltIn = false,
    this.createdAt,
  });

  // Built-in presets
  static const mixing = WorkspaceLayoutPreset(
    id: 'mixing',
    name: 'Mixing',
    superTab: DawSuperTab.mix,
    subTabIndex: 0, // Mixer
    height: 500.0,
    isBuiltIn: true,
  );

  static const mastering = WorkspaceLayoutPreset(
    id: 'mastering',
    name: 'Mastering',
    superTab: DawSuperTab.process,
    subTabIndex: 2, // Limiter
    height: 400.0,
    isBuiltIn: true,
  );

  static const editing = WorkspaceLayoutPreset(
    id: 'editing',
    name: 'Editing',
    superTab: DawSuperTab.edit,
    subTabIndex: 1, // Piano Roll
    height: 500.0,
    isBuiltIn: true,
  );

  static const tracking = WorkspaceLayoutPreset(
    id: 'tracking',
    name: 'Tracking',
    superTab: DawSuperTab.browse,
    subTabIndex: 0, // Files
    height: 350.0,
    isBuiltIn: true,
  );

  static const List<WorkspaceLayoutPreset> builtIn = [
    mixing,
    mastering,
    editing,
    tracking,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'superTab': superTab.index,
    'subTabIndex': subTabIndex,
    'height': height,
    'isExpanded': isExpanded,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory WorkspaceLayoutPreset.fromJson(Map<String, dynamic> json) {
    return WorkspaceLayoutPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      superTab: DawSuperTab.values[json['superTab'] as int],
      subTabIndex: json['subTabIndex'] as int? ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 500.0,
      isExpanded: json['isExpanded'] as bool? ?? true,
      isBuiltIn: false,
      createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    );
  }

  WorkspaceLayoutPreset copyWith({
    String? id,
    String? name,
    DawSuperTab? superTab,
    int? subTabIndex,
    double? height,
    bool? isExpanded,
    bool? isBuiltIn,
    DateTime? createdAt,
  }) {
    return WorkspaceLayoutPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      superTab: superTab ?? this.superTab,
      subTabIndex: subTabIndex ?? this.subTabIndex,
      height: height ?? this.height,
      isExpanded: isExpanded ?? this.isExpanded,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

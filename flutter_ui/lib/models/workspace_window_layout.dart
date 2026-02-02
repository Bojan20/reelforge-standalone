/// Workspace Window Layout Model (P2-DAW-11)
///
/// Extended layout model with window positions and panel visibility.
///
/// Created: 2026-02-02
library;

import 'dart:ui';

/// Window position and size
class WindowBounds {
  final double x;
  final double y;
  final double width;
  final double height;

  const WindowBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Rect toRect() => Rect.fromLTWH(x, y, width, height);

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory WindowBounds.fromJson(Map<String, dynamic> json) {
    return WindowBounds(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 800,
      height: (json['height'] as num?)?.toDouble() ?? 600,
    );
  }

  WindowBounds copyWith({double? x, double? y, double? width, double? height}) {
    return WindowBounds(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// Panel visibility and size configuration
class PanelConfig {
  final bool visible;
  final double? width;
  final double? height;
  final bool? expanded;

  const PanelConfig({
    this.visible = true,
    this.width,
    this.height,
    this.expanded,
  });

  Map<String, dynamic> toJson() => {
    'visible': visible,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (expanded != null) 'expanded': expanded,
  };

  factory PanelConfig.fromJson(Map<String, dynamic> json) {
    return PanelConfig(
      visible: json['visible'] as bool? ?? true,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      expanded: json['expanded'] as bool?,
    );
  }

  PanelConfig copyWith({bool? visible, double? width, double? height, bool? expanded}) {
    return PanelConfig(
      visible: visible ?? this.visible,
      width: width ?? this.width,
      height: height ?? this.height,
      expanded: expanded ?? this.expanded,
    );
  }
}

/// Complete workspace window layout
class WorkspaceWindowLayout {
  final String id;
  final String name;
  final WindowBounds? mainWindow;
  final PanelConfig leftPanel;
  final PanelConfig rightPanel;
  final PanelConfig bottomPanel;
  final PanelConfig mixerPanel;
  final PanelConfig browserPanel;
  final bool isBuiltIn;
  final DateTime? createdAt;

  const WorkspaceWindowLayout({
    required this.id,
    required this.name,
    this.mainWindow,
    this.leftPanel = const PanelConfig(),
    this.rightPanel = const PanelConfig(),
    this.bottomPanel = const PanelConfig(),
    this.mixerPanel = const PanelConfig(),
    this.browserPanel = const PanelConfig(),
    this.isBuiltIn = false,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (mainWindow != null) 'mainWindow': mainWindow!.toJson(),
    'leftPanel': leftPanel.toJson(),
    'rightPanel': rightPanel.toJson(),
    'bottomPanel': bottomPanel.toJson(),
    'mixerPanel': mixerPanel.toJson(),
    'browserPanel': browserPanel.toJson(),
    'createdAt': createdAt?.toIso8601String(),
  };

  factory WorkspaceWindowLayout.fromJson(Map<String, dynamic> json) {
    return WorkspaceWindowLayout(
      id: json['id'] as String,
      name: json['name'] as String,
      mainWindow: json['mainWindow'] != null
          ? WindowBounds.fromJson(json['mainWindow'] as Map<String, dynamic>)
          : null,
      leftPanel: json['leftPanel'] != null
          ? PanelConfig.fromJson(json['leftPanel'] as Map<String, dynamic>)
          : const PanelConfig(),
      rightPanel: json['rightPanel'] != null
          ? PanelConfig.fromJson(json['rightPanel'] as Map<String, dynamic>)
          : const PanelConfig(),
      bottomPanel: json['bottomPanel'] != null
          ? PanelConfig.fromJson(json['bottomPanel'] as Map<String, dynamic>)
          : const PanelConfig(),
      mixerPanel: json['mixerPanel'] != null
          ? PanelConfig.fromJson(json['mixerPanel'] as Map<String, dynamic>)
          : const PanelConfig(),
      browserPanel: json['browserPanel'] != null
          ? PanelConfig.fromJson(json['browserPanel'] as Map<String, dynamic>)
          : const PanelConfig(),
      isBuiltIn: false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  WorkspaceWindowLayout copyWith({
    String? id,
    String? name,
    WindowBounds? mainWindow,
    PanelConfig? leftPanel,
    PanelConfig? rightPanel,
    PanelConfig? bottomPanel,
    PanelConfig? mixerPanel,
    PanelConfig? browserPanel,
    bool? isBuiltIn,
    DateTime? createdAt,
  }) {
    return WorkspaceWindowLayout(
      id: id ?? this.id,
      name: name ?? this.name,
      mainWindow: mainWindow ?? this.mainWindow,
      leftPanel: leftPanel ?? this.leftPanel,
      rightPanel: rightPanel ?? this.rightPanel,
      bottomPanel: bottomPanel ?? this.bottomPanel,
      mixerPanel: mixerPanel ?? this.mixerPanel,
      browserPanel: browserPanel ?? this.browserPanel,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Built-in workspace window layouts
class BuiltInWindowLayouts {
  static const mix = WorkspaceWindowLayout(
    id: 'builtin_mix',
    name: 'Mix',
    leftPanel: PanelConfig(visible: true, width: 220),
    rightPanel: PanelConfig(visible: true, width: 300),
    bottomPanel: PanelConfig(visible: true, height: 500, expanded: true),
    mixerPanel: PanelConfig(visible: true),
    browserPanel: PanelConfig(visible: false),
    isBuiltIn: true,
  );

  static const edit = WorkspaceWindowLayout(
    id: 'builtin_edit',
    name: 'Edit',
    leftPanel: PanelConfig(visible: true, width: 180),
    rightPanel: PanelConfig(visible: true, width: 280),
    bottomPanel: PanelConfig(visible: true, height: 400, expanded: true),
    mixerPanel: PanelConfig(visible: false),
    browserPanel: PanelConfig(visible: true),
    isBuiltIn: true,
  );

  static const master = WorkspaceWindowLayout(
    id: 'builtin_master',
    name: 'Master',
    leftPanel: PanelConfig(visible: false),
    rightPanel: PanelConfig(visible: true, width: 350),
    bottomPanel: PanelConfig(visible: true, height: 350, expanded: true),
    mixerPanel: PanelConfig(visible: true),
    browserPanel: PanelConfig(visible: false),
    isBuiltIn: true,
  );

  static const List<WorkspaceWindowLayout> all = [mix, edit, master];
}

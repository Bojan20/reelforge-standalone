/// Workspace Provider
///
/// Manages layout presets (workspaces) like Cubase/Logic:
/// - Save/load layout configurations
/// - Quick workspace switching via keyboard
/// - Default workspaces (Mixing, Editing, Recording)
/// - Custom user workspaces

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/layout_models.dart';

/// Workspace definition
class Workspace {
  final String id;
  final String name;
  final String? icon;
  final String? shortcut; // e.g., "⌘1"
  final WorkspaceLayout layout;
  final bool isBuiltIn;
  final DateTime? lastModified;

  const Workspace({
    required this.id,
    required this.name,
    this.icon,
    this.shortcut,
    required this.layout,
    this.isBuiltIn = false,
    this.lastModified,
  });

  Workspace copyWith({
    String? id,
    String? name,
    String? icon,
    String? shortcut,
    WorkspaceLayout? layout,
    bool? isBuiltIn,
    DateTime? lastModified,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      shortcut: shortcut ?? this.shortcut,
      layout: layout ?? this.layout,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'shortcut': shortcut,
    'layout': layout.toJson(),
    'isBuiltIn': isBuiltIn,
    'lastModified': lastModified?.toIso8601String(),
  };

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      shortcut: json['shortcut'] as String?,
      layout: WorkspaceLayout.fromJson(json['layout'] as Map<String, dynamic>),
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'] as String)
          : null,
    );
  }
}

/// Layout configuration for a workspace
class WorkspaceLayout {
  /// Left zone visible
  final bool showLeftZone;
  /// Left zone width
  final double leftZoneWidth;

  /// Right zone visible
  final bool showRightZone;
  /// Right zone width
  final double rightZoneWidth;

  /// Lower zone visible
  final bool showLowerZone;
  /// Lower zone height
  final double lowerZoneHeight;
  /// Lower zone tab
  final String lowerZoneTab;

  /// Mixer visible (in lower zone)
  final bool showMixer;

  /// Transport position
  final bool transportAtTop;

  /// Timeline zoom level
  final double timelineZoom;

  /// Track heights mode
  final String trackHeightMode; // 'small', 'medium', 'large'

  /// Editor mode (DAW/Middleware)
  final String editorMode;

  const WorkspaceLayout({
    this.showLeftZone = true,
    this.leftZoneWidth = 250,
    this.showRightZone = true,
    this.rightZoneWidth = 300,
    this.showLowerZone = true,
    this.lowerZoneHeight = 250,
    this.lowerZoneTab = 'mixer',
    this.showMixer = true,
    this.transportAtTop = true,
    this.timelineZoom = 1.0,
    this.trackHeightMode = 'medium',
    this.editorMode = 'daw',
  });

  Map<String, dynamic> toJson() => {
    'showLeftZone': showLeftZone,
    'leftZoneWidth': leftZoneWidth,
    'showRightZone': showRightZone,
    'rightZoneWidth': rightZoneWidth,
    'showLowerZone': showLowerZone,
    'lowerZoneHeight': lowerZoneHeight,
    'lowerZoneTab': lowerZoneTab,
    'showMixer': showMixer,
    'transportAtTop': transportAtTop,
    'timelineZoom': timelineZoom,
    'trackHeightMode': trackHeightMode,
    'editorMode': editorMode,
  };

  factory WorkspaceLayout.fromJson(Map<String, dynamic> json) {
    return WorkspaceLayout(
      showLeftZone: json['showLeftZone'] as bool? ?? true,
      leftZoneWidth: (json['leftZoneWidth'] as num?)?.toDouble() ?? 250,
      showRightZone: json['showRightZone'] as bool? ?? true,
      rightZoneWidth: (json['rightZoneWidth'] as num?)?.toDouble() ?? 300,
      showLowerZone: json['showLowerZone'] as bool? ?? true,
      lowerZoneHeight: (json['lowerZoneHeight'] as num?)?.toDouble() ?? 250,
      lowerZoneTab: json['lowerZoneTab'] as String? ?? 'mixer',
      showMixer: json['showMixer'] as bool? ?? true,
      transportAtTop: json['transportAtTop'] as bool? ?? true,
      timelineZoom: (json['timelineZoom'] as num?)?.toDouble() ?? 1.0,
      trackHeightMode: json['trackHeightMode'] as String? ?? 'medium',
      editorMode: json['editorMode'] as String? ?? 'daw',
    );
  }

  WorkspaceLayout copyWith({
    bool? showLeftZone,
    double? leftZoneWidth,
    bool? showRightZone,
    double? rightZoneWidth,
    bool? showLowerZone,
    double? lowerZoneHeight,
    String? lowerZoneTab,
    bool? showMixer,
    bool? transportAtTop,
    double? timelineZoom,
    String? trackHeightMode,
    String? editorMode,
  }) {
    return WorkspaceLayout(
      showLeftZone: showLeftZone ?? this.showLeftZone,
      leftZoneWidth: leftZoneWidth ?? this.leftZoneWidth,
      showRightZone: showRightZone ?? this.showRightZone,
      rightZoneWidth: rightZoneWidth ?? this.rightZoneWidth,
      showLowerZone: showLowerZone ?? this.showLowerZone,
      lowerZoneHeight: lowerZoneHeight ?? this.lowerZoneHeight,
      lowerZoneTab: lowerZoneTab ?? this.lowerZoneTab,
      showMixer: showMixer ?? this.showMixer,
      transportAtTop: transportAtTop ?? this.transportAtTop,
      timelineZoom: timelineZoom ?? this.timelineZoom,
      trackHeightMode: trackHeightMode ?? this.trackHeightMode,
      editorMode: editorMode ?? this.editorMode,
    );
  }
}

/// Built-in workspace definitions
class BuiltInWorkspaces {
  static const mixing = Workspace(
    id: 'mixing',
    name: 'Mixing',
    icon: '🎚️',
    shortcut: '⌘1',
    isBuiltIn: true,
    layout: WorkspaceLayout(
      showLeftZone: false,
      showRightZone: true,
      rightZoneWidth: 350,
      showLowerZone: true,
      lowerZoneHeight: 300,
      lowerZoneTab: 'mixer',
      showMixer: true,
      trackHeightMode: 'small',
    ),
  );

  static const editing = Workspace(
    id: 'editing',
    name: 'Editing',
    icon: '✂️',
    shortcut: '⌘2',
    isBuiltIn: true,
    layout: WorkspaceLayout(
      showLeftZone: true,
      leftZoneWidth: 200,
      showRightZone: false,
      showLowerZone: true,
      lowerZoneHeight: 200,
      lowerZoneTab: 'editor',
      showMixer: false,
      trackHeightMode: 'large',
      timelineZoom: 2.0,
    ),
  );

  static const recording = Workspace(
    id: 'recording',
    name: 'Recording',
    icon: '🔴',
    shortcut: '⌘3',
    isBuiltIn: true,
    layout: WorkspaceLayout(
      showLeftZone: false,
      showRightZone: true,
      rightZoneWidth: 250,
      showLowerZone: false,
      trackHeightMode: 'large',
    ),
  );

  static const arranging = Workspace(
    id: 'arranging',
    name: 'Arranging',
    icon: '📐',
    shortcut: '⌘4',
    isBuiltIn: true,
    layout: WorkspaceLayout(
      showLeftZone: true,
      leftZoneWidth: 250,
      showRightZone: true,
      rightZoneWidth: 250,
      showLowerZone: true,
      lowerZoneHeight: 200,
      lowerZoneTab: 'markers',
      trackHeightMode: 'medium',
    ),
  );

  static const fullscreen = Workspace(
    id: 'fullscreen',
    name: 'Full Screen',
    icon: '🖥️',
    shortcut: '⌘5',
    isBuiltIn: true,
    layout: WorkspaceLayout(
      showLeftZone: false,
      showRightZone: false,
      showLowerZone: false,
      trackHeightMode: 'medium',
    ),
  );

  static List<Workspace> all = [
    mixing,
    editing,
    recording,
    arranging,
    fullscreen,
  ];
}

/// Workspace provider
class WorkspaceProvider extends ChangeNotifier {
  static const _prefsKey = 'reelforge_workspaces';
  static const _currentKey = 'reelforge_current_workspace';

  List<Workspace> _workspaces = [];
  Workspace? _currentWorkspace;
  WorkspaceLayout _currentLayout = const WorkspaceLayout();
  bool _initialized = false;

  List<Workspace> get workspaces => _workspaces;
  Workspace? get currentWorkspace => _currentWorkspace;
  WorkspaceLayout get currentLayout => _currentLayout;
  bool get initialized => _initialized;

  /// Initialize workspaces from storage
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load custom workspaces
      final workspacesJson = prefs.getString(_prefsKey);
      if (workspacesJson != null) {
        final List<dynamic> decoded = jsonDecode(workspacesJson);
        final custom = decoded
            .map((w) => Workspace.fromJson(w as Map<String, dynamic>))
            .toList();

        _workspaces = [...BuiltInWorkspaces.all, ...custom];
      } else {
        _workspaces = [...BuiltInWorkspaces.all];
      }

      // Load current workspace
      final currentId = prefs.getString(_currentKey);
      if (currentId != null) {
        _currentWorkspace = _workspaces.firstWhere(
          (w) => w.id == currentId,
          orElse: () => BuiltInWorkspaces.mixing,
        );
        _currentLayout = _currentWorkspace!.layout;
      } else {
        _currentWorkspace = BuiltInWorkspaces.mixing;
        _currentLayout = _currentWorkspace!.layout;
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load workspaces: $e');
      _workspaces = [...BuiltInWorkspaces.all];
      _currentWorkspace = BuiltInWorkspaces.mixing;
      _currentLayout = _currentWorkspace!.layout;
      _initialized = true;
      notifyListeners();
    }
  }

  /// Switch to a workspace
  Future<void> switchWorkspace(String workspaceId) async {
    final workspace = _workspaces.firstWhere(
      (w) => w.id == workspaceId,
      orElse: () => BuiltInWorkspaces.mixing,
    );

    _currentWorkspace = workspace;
    _currentLayout = workspace.layout;

    // Save current workspace ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentKey, workspaceId);

    notifyListeners();
  }

  /// Update current layout (without saving to workspace)
  void updateLayout(WorkspaceLayout layout) {
    _currentLayout = layout;
    notifyListeners();
  }

  /// Save current layout to a workspace
  Future<void> saveCurrentLayout({
    String? workspaceId,
    String? name,
  }) async {
    final id = workspaceId ?? _currentWorkspace?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final workspaceName = name ?? _currentWorkspace?.name ?? 'Custom Workspace';

    final workspace = Workspace(
      id: id,
      name: workspaceName,
      layout: _currentLayout,
      isBuiltIn: false,
      lastModified: DateTime.now(),
    );

    // Update or add
    final existingIndex = _workspaces.indexWhere((w) => w.id == id);
    if (existingIndex >= 0 && !_workspaces[existingIndex].isBuiltIn) {
      _workspaces[existingIndex] = workspace;
    } else {
      _workspaces.add(workspace);
    }

    _currentWorkspace = workspace;

    await _saveWorkspaces();
    notifyListeners();
  }

  /// Create new workspace from current layout
  Future<Workspace> createWorkspace(String name) async {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';

    final workspace = Workspace(
      id: id,
      name: name,
      layout: _currentLayout,
      isBuiltIn: false,
      lastModified: DateTime.now(),
    );

    _workspaces.add(workspace);
    _currentWorkspace = workspace;

    await _saveWorkspaces();
    notifyListeners();

    return workspace;
  }

  /// Delete a workspace
  Future<void> deleteWorkspace(String workspaceId) async {
    final workspace = _workspaces.firstWhere(
      (w) => w.id == workspaceId,
      orElse: () => BuiltInWorkspaces.mixing,
    );

    if (workspace.isBuiltIn) return; // Can't delete built-in

    _workspaces.removeWhere((w) => w.id == workspaceId);

    if (_currentWorkspace?.id == workspaceId) {
      _currentWorkspace = BuiltInWorkspaces.mixing;
      _currentLayout = _currentWorkspace!.layout;
    }

    await _saveWorkspaces();
    notifyListeners();
  }

  /// Rename workspace
  Future<void> renameWorkspace(String workspaceId, String newName) async {
    final index = _workspaces.indexWhere((w) => w.id == workspaceId);
    if (index < 0 || _workspaces[index].isBuiltIn) return;

    _workspaces[index] = _workspaces[index].copyWith(
      name: newName,
      lastModified: DateTime.now(),
    );

    if (_currentWorkspace?.id == workspaceId) {
      _currentWorkspace = _workspaces[index];
    }

    await _saveWorkspaces();
    notifyListeners();
  }

  /// Get workspace by shortcut
  Workspace? getWorkspaceByShortcut(String shortcut) {
    try {
      return _workspaces.firstWhere((w) => w.shortcut == shortcut);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveWorkspaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Only save custom workspaces
      final custom = _workspaces.where((w) => !w.isBuiltIn).toList();
      final json = jsonEncode(custom.map((w) => w.toJson()).toList());
      await prefs.setString(_prefsKey, json);

      if (_currentWorkspace != null) {
        await prefs.setString(_currentKey, _currentWorkspace!.id);
      }
    } catch (e) {
      debugPrint('Failed to save workspaces: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Layout shortcuts
  // ═══════════════════════════════════════════════════════════════════════

  void toggleLeftZone() {
    _currentLayout = _currentLayout.copyWith(
      showLeftZone: !_currentLayout.showLeftZone,
    );
    notifyListeners();
  }

  void toggleRightZone() {
    _currentLayout = _currentLayout.copyWith(
      showRightZone: !_currentLayout.showRightZone,
    );
    notifyListeners();
  }

  void toggleLowerZone() {
    _currentLayout = _currentLayout.copyWith(
      showLowerZone: !_currentLayout.showLowerZone,
    );
    notifyListeners();
  }

  void setLeftZoneWidth(double width) {
    _currentLayout = _currentLayout.copyWith(leftZoneWidth: width);
    notifyListeners();
  }

  void setRightZoneWidth(double width) {
    _currentLayout = _currentLayout.copyWith(rightZoneWidth: width);
    notifyListeners();
  }

  void setLowerZoneHeight(double height) {
    _currentLayout = _currentLayout.copyWith(lowerZoneHeight: height);
    notifyListeners();
  }

  void setLowerZoneTab(String tab) {
    _currentLayout = _currentLayout.copyWith(lowerZoneTab: tab);
    notifyListeners();
  }

  void setTimelineZoom(double zoom) {
    _currentLayout = _currentLayout.copyWith(timelineZoom: zoom);
    notifyListeners();
  }

  void setTrackHeightMode(String mode) {
    _currentLayout = _currentLayout.copyWith(trackHeightMode: mode);
    notifyListeners();
  }
}

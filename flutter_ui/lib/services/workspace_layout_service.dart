/// Workspace Layout Service (P1.1, P2-DAW-11)
///
/// Manages workspace layout presets with SharedPreferences persistence.
/// Extended with window positions and panel visibility (P2-DAW-11).
///
/// Created: 2026-01-26
/// Updated: 2026-02-02
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/workspace_layout_preset.dart';
import '../models/workspace_window_layout.dart';
import '../widgets/lower_zone/daw_lower_zone_controller.dart';

class WorkspaceLayoutService extends ChangeNotifier {
  static final WorkspaceLayoutService _instance = WorkspaceLayoutService._();
  static WorkspaceLayoutService get instance => _instance;

  WorkspaceLayoutService._();

  List<WorkspaceLayoutPreset> _customPresets = [];
  List<WorkspaceWindowLayout> _customWindowLayouts = [];

  // ─── Lower Zone Presets (P1.1) ─────────────────────────────────────────────

  List<WorkspaceLayoutPreset> get allPresets => [
    ...WorkspaceLayoutPreset.builtIn,
    ..._customPresets,
  ];

  List<WorkspaceLayoutPreset> get customPresets => _customPresets;

  // ─── Window Layouts (P2-DAW-11) ────────────────────────────────────────────

  List<WorkspaceWindowLayout> get allWindowLayouts => [
    ...BuiltInWindowLayouts.all,
    ..._customWindowLayouts,
  ];

  List<WorkspaceWindowLayout> get customWindowLayouts => List.unmodifiable(_customWindowLayouts);
  List<WorkspaceWindowLayout> get builtInWindowLayouts => BuiltInWindowLayouts.all;

  Future<void> init() async {
    await _loadCustomPresets();
    await _loadCustomWindowLayouts();
  }

  Future<void> _loadCustomPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('workspace_layout_presets');

    if (json != null) {
      try {
        final List<dynamic> decoded = jsonDecode(json);
        _customPresets = decoded
            .map((e) => WorkspaceLayoutPreset.fromJson(e as Map<String, dynamic>))
            .toList();
        notifyListeners();
      } catch (e) { /* ignored */ }
    }
  }

  Future<void> _loadCustomWindowLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('workspace_window_layouts');

    if (json != null) {
      try {
        final List<dynamic> decoded = jsonDecode(json);
        _customWindowLayouts = decoded
            .map((e) => WorkspaceWindowLayout.fromJson(e as Map<String, dynamic>))
            .toList();
        notifyListeners();
      } catch (e) { /* ignored */ }
    }
  }

  Future<bool> savePreset(WorkspaceLayoutPreset preset) async {
    if (preset.isBuiltIn) return false;

    _customPresets.removeWhere((p) => p.id == preset.id);
    _customPresets.add(preset);

    final success = await _persistCustomPresets();
    if (success) {
      notifyListeners();
    }
    return success;
  }

  Future<bool> deletePreset(String id) async {
    final initialLength = _customPresets.length;
    _customPresets.removeWhere((p) => p.id == id);
    if (_customPresets.length == initialLength) return false;

    final success = await _persistCustomPresets();
    if (success) {
      notifyListeners();
    }
    return success;
  }

  Future<bool> _persistCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_customPresets.map((p) => p.toJson()).toList());
      return await prefs.setString('workspace_layout_presets', json);
    } catch (e) {
      return false;
    }
  }

  Future<void> applyPreset(
    WorkspaceLayoutPreset preset,
    DawLowerZoneController controller,
  ) async {
    controller.setSuperTab(preset.superTab);
    controller.setSubTabIndex(preset.subTabIndex);
    controller.setHeight(preset.height);

    if (preset.isExpanded) {
      controller.expand();
    } else {
      controller.collapse();
    }
  }

  WorkspaceLayoutPreset createFromCurrentState(
    String name,
    DawLowerZoneController controller,
  ) {
    return WorkspaceLayoutPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      superTab: controller.superTab,
      subTabIndex: controller.currentSubTabIndex,
      height: controller.height,
      isExpanded: controller.isExpanded,
      createdAt: DateTime.now(),
    );
  }

  // ─── Window Layout Methods (P2-DAW-11) ─────────────────────────────────────

  Future<bool> saveWindowLayout(WorkspaceWindowLayout layout) async {
    if (layout.isBuiltIn) return false;

    _customWindowLayouts.removeWhere((l) => l.id == layout.id);
    _customWindowLayouts.add(layout.copyWith(createdAt: DateTime.now()));

    final success = await _persistCustomWindowLayouts();
    if (success) notifyListeners();
    return success;
  }

  Future<bool> deleteWindowLayout(String id) async {
    final index = _customWindowLayouts.indexWhere((l) => l.id == id);
    if (index < 0) return false;

    _customWindowLayouts.removeAt(index);
    final success = await _persistCustomWindowLayouts();
    if (success) notifyListeners();
    return success;
  }

  Future<bool> _persistCustomWindowLayouts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_customWindowLayouts.map((l) => l.toJson()).toList());
      return await prefs.setString('workspace_window_layouts', json);
    } catch (e) {
      return false;
    }
  }

  WorkspaceWindowLayout? getWindowLayoutById(String id) {
    return allWindowLayouts.where((l) => l.id == id).firstOrNull;
  }

  /// Create window layout from current panel states
  WorkspaceWindowLayout createWindowLayoutFromState({
    required String name,
    double? leftPanelWidth,
    double? rightPanelWidth,
    double? bottomPanelHeight,
    bool? leftPanelVisible,
    bool? rightPanelVisible,
    bool? bottomPanelExpanded,
    bool? mixerVisible,
    bool? browserVisible,
  }) {
    return WorkspaceWindowLayout(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      leftPanel: PanelConfig(
        visible: leftPanelVisible ?? true,
        width: leftPanelWidth,
      ),
      rightPanel: PanelConfig(
        visible: rightPanelVisible ?? true,
        width: rightPanelWidth,
      ),
      bottomPanel: PanelConfig(
        visible: true,
        height: bottomPanelHeight,
        expanded: bottomPanelExpanded,
      ),
      mixerPanel: PanelConfig(visible: mixerVisible ?? true),
      browserPanel: PanelConfig(visible: browserVisible ?? true),
      createdAt: DateTime.now(),
    );
  }
}

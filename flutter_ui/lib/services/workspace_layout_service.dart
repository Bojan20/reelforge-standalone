/// Workspace Layout Service (P1.1)
///
/// Manages workspace layout presets with SharedPreferences persistence.
///
/// Created: 2026-01-26
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/workspace_layout_preset.dart';
import '../widgets/lower_zone/daw_lower_zone_controller.dart';

class WorkspaceLayoutService extends ChangeNotifier {
  static final WorkspaceLayoutService _instance = WorkspaceLayoutService._();
  static WorkspaceLayoutService get instance => _instance;

  WorkspaceLayoutService._();

  List<WorkspaceLayoutPreset> _customPresets = [];

  List<WorkspaceLayoutPreset> get allPresets => [
    ...WorkspaceLayoutPreset.builtIn,
    ..._customPresets,
  ];

  List<WorkspaceLayoutPreset> get customPresets => _customPresets;

  Future<void> init() async {
    await _loadCustomPresets();
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
      } catch (e) {
        debugPrint('[WorkspaceLayoutService] Failed to load presets: $e');
      }
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
      debugPrint('[WorkspaceLayoutService] Failed to persist: $e');
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
}

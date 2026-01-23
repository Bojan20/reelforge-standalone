/// Workspace Preset Service (M3.2)
///
/// Manages workspace preset CRUD operations, persistence, and application.
/// Supports built-in and custom presets with SharedPreferences storage.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_preset.dart';

/// Callback for when workspace preset changes
typedef WorkspacePresetCallback = void Function(WorkspacePreset? preset);

/// Service for managing workspace presets
class WorkspacePresetService extends ChangeNotifier {
  static final WorkspacePresetService _instance = WorkspacePresetService._();
  static WorkspacePresetService get instance => _instance;

  WorkspacePresetService._();

  static const _prefsKeyCustomPresets = 'workspace_presets_custom';
  static const _prefsKeyActivePreset = 'workspace_preset_active';

  /// All presets (built-in + custom)
  final List<WorkspacePreset> _presets = [];
  List<WorkspacePreset> get presets => List.unmodifiable(_presets);

  /// Active preset per section
  final Map<WorkspaceSection, String?> _activePresetIds = {};

  /// Listeners for preset application
  final List<WorkspacePresetCallback> _applicationListeners = [];

  /// Whether service is initialized
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize service - must be called at startup
  Future<void> init() async {
    if (_initialized) return;

    // Add built-in presets
    _presets.addAll(BuiltInWorkspacePresets.all);

    // Load custom presets from storage
    await _loadCustomPresets();

    // Load active preset state
    await _loadActivePresets();

    _initialized = true;
    notifyListeners();
    debugPrint('[WorkspacePresetService] Initialized with ${_presets.length} presets');
  }

  /// Load custom presets from SharedPreferences
  Future<void> _loadCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefsKeyCustomPresets);
      if (jsonString != null) {
        final List<dynamic> list = jsonDecode(jsonString);
        for (final item in list) {
          final preset = WorkspacePreset.fromJson(item as Map<String, dynamic>);
          if (!preset.isBuiltIn) {
            _presets.add(preset);
          }
        }
      }
    } catch (e) {
      debugPrint('[WorkspacePresetService] Error loading custom presets: $e');
    }
  }

  /// Save custom presets to SharedPreferences
  Future<void> _saveCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customPresets = _presets.where((p) => !p.isBuiltIn).toList();
      final jsonString = jsonEncode(customPresets.map((p) => p.toJson()).toList());
      await prefs.setString(_prefsKeyCustomPresets, jsonString);
    } catch (e) {
      debugPrint('[WorkspacePresetService] Error saving custom presets: $e');
    }
  }

  /// Load active preset state
  Future<void> _loadActivePresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefsKeyActivePreset);
      if (jsonString != null) {
        final Map<String, dynamic> map = jsonDecode(jsonString);
        for (final section in WorkspaceSection.values) {
          _activePresetIds[section] = map[section.name] as String?;
        }
      }
    } catch (e) {
      debugPrint('[WorkspacePresetService] Error loading active presets: $e');
    }
  }

  /// Save active preset state
  Future<void> _saveActivePresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String?>{};
      for (final section in WorkspaceSection.values) {
        map[section.name] = _activePresetIds[section];
      }
      await prefs.setString(_prefsKeyActivePreset, jsonEncode(map));
    } catch (e) {
      debugPrint('[WorkspacePresetService] Error saving active presets: $e');
    }
  }

  /// Get presets for a specific section
  List<WorkspacePreset> getPresetsForSection(WorkspaceSection section) {
    return _presets.where((p) => p.section == section).toList();
  }

  /// Get active preset for a section
  WorkspacePreset? getActivePreset(WorkspaceSection section) {
    final id = _activePresetIds[section];
    if (id == null) return null;
    return _presets.where((p) => p.id == id).firstOrNull;
  }

  /// Set active preset for a section
  Future<void> setActivePreset(WorkspaceSection section, String? presetId) async {
    _activePresetIds[section] = presetId;
    await _saveActivePresets();

    final preset = presetId != null
        ? _presets.where((p) => p.id == presetId).firstOrNull
        : null;

    // Notify application listeners
    for (final listener in _applicationListeners) {
      listener(preset);
    }

    notifyListeners();
    debugPrint('[WorkspacePresetService] Active preset for $section: ${preset?.name ?? "none"}');
  }

  /// Apply a preset
  Future<void> applyPreset(WorkspacePreset preset) async {
    await setActivePreset(preset.section, preset.id);
  }

  /// Create a new custom preset
  Future<WorkspacePreset> createPreset({
    required String name,
    String? description,
    required WorkspaceSection section,
    required List<String> activeTabs,
    List<String> expandedCategories = const [],
    double lowerZoneHeight = 300,
    bool lowerZoneExpanded = true,
  }) async {
    final now = DateTime.now();
    final preset = WorkspacePreset(
      id: 'custom_${now.millisecondsSinceEpoch}',
      name: name,
      description: description,
      section: section,
      activeTabs: activeTabs,
      expandedCategories: expandedCategories,
      lowerZoneHeight: lowerZoneHeight,
      lowerZoneExpanded: lowerZoneExpanded,
      createdAt: now,
      modifiedAt: now,
      isBuiltIn: false,
    );

    _presets.add(preset);
    await _saveCustomPresets();
    notifyListeners();

    debugPrint('[WorkspacePresetService] Created preset: ${preset.name}');
    return preset;
  }

  /// Update an existing preset
  Future<void> updatePreset(WorkspacePreset preset) async {
    if (preset.isBuiltIn) {
      debugPrint('[WorkspacePresetService] Cannot update built-in preset');
      return;
    }

    final index = _presets.indexWhere((p) => p.id == preset.id);
    if (index == -1) return;

    _presets[index] = preset.copyWith(modifiedAt: DateTime.now());
    await _saveCustomPresets();
    notifyListeners();

    debugPrint('[WorkspacePresetService] Updated preset: ${preset.name}');
  }

  /// Delete a custom preset
  Future<void> deletePreset(String presetId) async {
    final preset = _presets.where((p) => p.id == presetId).firstOrNull;
    if (preset == null || preset.isBuiltIn) {
      debugPrint('[WorkspacePresetService] Cannot delete preset: $presetId');
      return;
    }

    _presets.removeWhere((p) => p.id == presetId);

    // Clear active preset if it was deleted
    for (final section in WorkspaceSection.values) {
      if (_activePresetIds[section] == presetId) {
        _activePresetIds[section] = null;
      }
    }

    await _saveCustomPresets();
    await _saveActivePresets();
    notifyListeners();

    debugPrint('[WorkspacePresetService] Deleted preset: ${preset.name}');
  }

  /// Duplicate a preset
  Future<WorkspacePreset> duplicatePreset(String presetId) async {
    final original = _presets.where((p) => p.id == presetId).firstOrNull;
    if (original == null) {
      throw ArgumentError('Preset not found: $presetId');
    }

    return createPreset(
      name: '${original.name} (Copy)',
      description: original.description,
      section: original.section,
      activeTabs: List.from(original.activeTabs),
      expandedCategories: List.from(original.expandedCategories),
      lowerZoneHeight: original.lowerZoneHeight,
      lowerZoneExpanded: original.lowerZoneExpanded,
    );
  }

  /// Add listener for preset application
  void addApplicationListener(WorkspacePresetCallback listener) {
    _applicationListeners.add(listener);
  }

  /// Remove application listener
  void removeApplicationListener(WorkspacePresetCallback listener) {
    _applicationListeners.remove(listener);
  }

  /// Export presets to JSON
  String exportPresetsToJson() {
    final customPresets = _presets.where((p) => !p.isBuiltIn).toList();
    return jsonEncode({
      'version': 1,
      'presets': customPresets.map((p) => p.toJson()).toList(),
    });
  }

  /// Import presets from JSON
  Future<int> importPresetsFromJson(String jsonString) async {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final List<dynamic> presetsList = data['presets'] as List<dynamic>;

      int imported = 0;
      for (final item in presetsList) {
        final preset = WorkspacePreset.fromJson(item as Map<String, dynamic>);
        // Create as new custom preset
        await createPreset(
          name: preset.name,
          description: preset.description,
          section: preset.section,
          activeTabs: preset.activeTabs,
          expandedCategories: preset.expandedCategories,
          lowerZoneHeight: preset.lowerZoneHeight,
          lowerZoneExpanded: preset.lowerZoneExpanded,
        );
        imported++;
      }

      debugPrint('[WorkspacePresetService] Imported $imported presets');
      return imported;
    } catch (e) {
      debugPrint('[WorkspacePresetService] Error importing presets: $e');
      return 0;
    }
  }

  /// Get preset by ID
  WorkspacePreset? getPresetById(String id) {
    return _presets.where((p) => p.id == id).firstOrNull;
  }

  /// Dispose resources
  @override
  void dispose() {
    _applicationListeners.clear();
    super.dispose();
  }
}

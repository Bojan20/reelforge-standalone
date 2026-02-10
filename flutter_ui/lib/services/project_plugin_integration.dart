/// Project Plugin Integration
///
/// Integrates PluginStateService with project save/load operations.
/// Provides utilities for capturing and restoring plugin states during project lifecycle.
///
/// Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/plugin_manifest.dart';
import 'missing_plugin_detector.dart';
import 'plugin_state_service.dart';
import 'service_locator.dart';

// =============================================================================
// PROJECT PLUGIN INTEGRATION
// =============================================================================

/// Integration utilities for plugin state with project save/load
class ProjectPluginIntegration {
  ProjectPluginIntegration._();
  static final instance = ProjectPluginIntegration._();

  PluginStateService get _stateService => sl<PluginStateService>();
  MissingPluginDetector get _detector => sl<MissingPluginDetector>();

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT SAVE INTEGRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Capture all plugin states before saving project
  ///
  /// Call this before project save to ensure all plugin states are captured.
  /// Returns the manifest JSON to include in project file.
  Future<Map<String, dynamic>> captureAllPluginStates({
    required List<PluginSlotState> pluginSlots,
  }) async {

    for (final slot in pluginSlots) {
      try {
        await _stateService.capturePluginState(
          trackId: slot.trackId,
          slotIndex: slot.slotIndex,
          plugin: slot.plugin,
          presetName: slot.presetName,
        );
      } catch (e) { /* ignored */ }
    }

    // Return manifest JSON
    return _stateService.exportManifestJson();
  }

  /// Save plugin states to project directory
  ///
  /// Creates plugins/states/ directory and saves .ffstate files.
  Future<void> saveStatesToProjectDir({
    required String projectDir,
    required List<PluginSlotState> pluginSlots,
  }) async {
    final statesDir = path.join(projectDir, 'plugins', 'states');
    await Directory(statesDir).create(recursive: true);

    for (final slot in pluginSlots) {
      final filename = 'track${slot.trackId}_slot${slot.slotIndex}.ffstate';
      final filePath = path.join(statesDir, filename);

      final success = await _stateService.saveStateToFileViaFFI(
        slot.trackId,
        slot.slotIndex,
        filePath,
      );

      if (success) {
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT LOAD INTEGRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load plugin manifest and detect missing plugins
  ///
  /// Returns a report of missing plugins. If all plugins are installed,
  /// report.allPluginsAvailable will be true.
  Future<MissingPluginReport> loadAndVerifyPlugins({
    required Map<String, dynamic> manifestJson,
  }) async {
    // Import manifest
    _stateService.importManifestJson(manifestJson);

    // Get the manifest
    final manifest = _stateService.getManifest();
    if (manifest == null) {
      // No plugins in project
      return MissingPluginReport(
        missingPlugins: [],
        totalPlugins: 0,
        installedPlugins: 0,
        detectedAt: DateTime.now(),
      );
    }

    // Detect missing plugins
    final report = await _detector.detectMissingPlugins(manifest);


    return report;
  }

  /// Load plugin states from project directory
  ///
  /// Loads .ffstate files from plugins/states/ directory.
  Future<int> loadStatesFromProjectDir({
    required String projectDir,
  }) async {
    final statesDir = path.join(projectDir, 'plugins', 'states');
    final dir = Directory(statesDir);

    if (!await dir.exists()) {
      return 0;
    }

    int loadedCount = 0;

    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.ffstate')) continue;

      // Parse filename: track{N}_slot{M}.ffstate
      final filename = path.basename(entity.path);
      final match = RegExp(r'track(\d+)_slot(\d+)\.ffstate').firstMatch(filename);

      if (match == null) continue;

      final trackId = int.parse(match.group(1)!);
      final slotIndex = int.parse(match.group(2)!);

      final success = await _stateService.loadStateFromFileViaFFI(
        trackId,
        slotIndex,
        entity.path,
      );

      if (success) {
        loadedCount++;
      }
    }

    return loadedCount;
  }

  /// Restore all plugin states after loading
  ///
  /// Restores states to plugins for slots where the plugin is installed.
  Future<void> restorePluginStates({
    required List<PluginSlotState> pluginSlots,
  }) async {
    for (final slot in pluginSlots) {
      // Check if plugin is installed
      if (!_detector.isPluginInstalled(slot.plugin)) {
        continue;
      }

      final success = await _stateService.restorePluginState(
        trackId: slot.trackId,
        slotIndex: slot.slotIndex,
      );

      if (success) {
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVENIENCE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Full project save integration
  ///
  /// Captures states, saves to files, and returns manifest JSON.
  Future<Map<String, dynamic>> onProjectSave({
    required String projectDir,
    required List<PluginSlotState> pluginSlots,
  }) async {
    // Capture all states
    final manifestJson = await captureAllPluginStates(pluginSlots: pluginSlots);

    // Save state files
    await saveStatesToProjectDir(
      projectDir: projectDir,
      pluginSlots: pluginSlots,
    );

    return manifestJson;
  }

  /// Full project load integration
  ///
  /// Loads manifest, detects missing plugins, loads state files, and restores states.
  /// Returns the missing plugin report for UI handling.
  Future<MissingPluginReport> onProjectLoad({
    required String projectDir,
    required Map<String, dynamic> manifestJson,
    required List<PluginSlotState> pluginSlots,
  }) async {
    // Load and verify plugins
    final report = await loadAndVerifyPlugins(manifestJson: manifestJson);

    // Load state files
    await loadStatesFromProjectDir(projectDir: projectDir);

    // Restore states for installed plugins
    await restorePluginStates(pluginSlots: pluginSlots);

    return report;
  }

  /// Clear all plugin state (for new project)
  void clearAllStates() {
    _stateService.clearFFIStates();
    _stateService.clearManifest();
  }

  /// Get summary of current plugin states
  Map<String, dynamic> getStatesSummary() {
    return {
      'ffiStateCount': _stateService.getFFIStateCount(),
      'manifestPluginCount': _stateService.getManifest()?.plugins.length ?? 0,
      'states': _stateService.getFFIStatesInfo(),
    };
  }
}

// =============================================================================
// PLUGIN SLOT STATE LIST BUILDER
// =============================================================================

/// Helper to build plugin slot state list from mixer/track data
class PluginSlotStateBuilder {
  final List<PluginSlotState> _slots = [];

  /// Add a plugin slot
  void addSlot({
    required int trackId,
    required int slotIndex,
    required String pluginId,
    required String pluginName,
    required PluginFormat format,
    String? vendor,
    String? version,
    String? presetName,
    String? freezeAudioPath,
    String? stateFilePath,
  }) {
    final plugin = PluginReference(
      uid: PluginUid(format: format, uid: pluginId),
      name: pluginName,
      vendor: vendor ?? 'Unknown',
      version: version ?? '1.0.0',
    );

    _slots.add(PluginSlotState(
      trackId: trackId,
      slotIndex: slotIndex,
      plugin: plugin,
      stateFilePath: stateFilePath,
      presetName: presetName,
      freezeAudioPath: freezeAudioPath,
    ));
  }

  /// Build the list
  List<PluginSlotState> build() => List.unmodifiable(_slots);

  /// Clear all slots
  void clear() => _slots.clear();

  /// Get current slot count
  int get length => _slots.length;
}

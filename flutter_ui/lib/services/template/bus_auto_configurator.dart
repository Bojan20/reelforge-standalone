/// Bus Auto Configurator
///
/// Configures the audio bus hierarchy based on template settings.
/// Sets up the standard 8-bus structure with proper parent-child relationships.
///
/// P3-12: Template Gallery
library;

import 'package:flutter/foundation.dart';

import '../../models/advanced_middleware_models.dart';
import '../../models/template_models.dart';
import '../../providers/subsystems/bus_hierarchy_provider.dart';
import '../service_locator.dart';

/// Configures audio bus hierarchy from template
class BusAutoConfigurator {
  /// Configure all buses from template
  ///
  /// Returns the number of buses configured
  int configureAll(BuiltTemplate template) {
    final busProvider = sl<BusHierarchyProvider>();

    // Standard 8-bus hierarchy:
    // Master (0)
    // ├── Music (1)
    // ├── SFX (2)
    // │   ├── Reels (3)
    // │   └── Wins (4)
    // ├── Voice (5)
    // ├── UI (6)
    // └── Ambience (7)

    final buses = [
      _createBus(TemplateBus.master),
      _createBus(TemplateBus.music),
      _createBus(TemplateBus.sfx),
      _createBus(TemplateBus.reels),
      _createBus(TemplateBus.wins),
      _createBus(TemplateBus.vo),
      _createBus(TemplateBus.ui),
      _createBus(TemplateBus.ambience),
    ];

    // Register all buses
    for (final bus in buses) {
      try {
        busProvider.addBus(bus);
      } catch (e) {
        debugPrint('[BusAutoConfigurator] ⚠️ Failed to add bus ${bus.name}: $e');
      }
    }

    // Apply template-specific bus settings
    _applyBusSettings(template, busProvider);

    debugPrint('[BusAutoConfigurator] Configured ${buses.length} buses');
    return buses.length;
  }

  /// Create an AudioBus from template bus definition
  AudioBus _createBus(TemplateBus templateBus) {
    return AudioBus(
      busId: templateBus.engineId,
      name: templateBus.displayName,
      parentBusId: templateBus.parentId,
      childBusIds: _getChildBusIds(templateBus),
      volume: _getDefaultVolume(templateBus),
      pan: 0.0,
      mute: false,
      solo: false,
    );
  }

  /// Get child bus IDs for a parent bus
  List<int> _getChildBusIds(TemplateBus parent) {
    return TemplateBus.values
        .where((b) => b.parentId == parent.engineId)
        .map((b) => b.engineId)
        .toList();
  }

  /// Get default volume for a bus type
  double _getDefaultVolume(TemplateBus bus) {
    return switch (bus) {
      TemplateBus.master => 1.0,
      TemplateBus.music => 0.75, // Slightly lower for music
      TemplateBus.sfx => 0.85,
      TemplateBus.reels => 0.8,
      TemplateBus.wins => 0.9, // Wins slightly louder
      TemplateBus.vo => 0.95, // Voice needs to be clear
      TemplateBus.ui => 0.7, // UI quieter
      TemplateBus.ambience => 0.5, // Ambience subtle
    };
  }

  /// Apply any template-specific bus settings
  void _applyBusSettings(BuiltTemplate template, BusHierarchyProvider provider) {
    // Apply settings from template metadata if present
    final busSettings = template.source.metadata['busSettings'] as Map<String, dynamic>?;
    if (busSettings == null) return;

    for (final entry in busSettings.entries) {
      final busName = entry.key;
      final settings = entry.value as Map<String, dynamic>?;
      if (settings == null) continue;

      // Find bus by name
      final bus = TemplateBus.values.where((b) => b.name == busName).firstOrNull;
      if (bus == null) continue;

      // Apply volume
      if (settings['volume'] != null) {
        provider.setBusVolume(bus.engineId, (settings['volume'] as num).toDouble());
      }

      // Apply pan
      if (settings['pan'] != null) {
        provider.setBusPan(bus.engineId, (settings['pan'] as num).toDouble());
      }
    }
  }

  /// Get engine ID for a template bus
  static int engineIdForBus(TemplateBus bus) => bus.engineId;

  /// Get template bus from engine ID
  static TemplateBus? busFromEngineId(int engineId) =>
      TemplateBus.values.where((b) => b.engineId == engineId).firstOrNull;
}

/// Event Auto Registrar
///
/// Creates AudioEvents in EventRegistry for each mapped stage.
/// Handles pan calculation for per-reel events.
///
/// P3-12: Template Gallery
library;

import 'package:flutter/foundation.dart';

import '../../models/template_models.dart';
import '../event_registry.dart';

/// Registers audio events from template mappings
class EventAutoRegistrar {
  /// Register all events from a built template
  ///
  /// Returns the number of events registered
  int registerAll(BuiltTemplate template) {
    final eventRegistry = EventRegistry.instance;
    int count = 0;

    // Group mappings by stage (one event can have multiple layers)
    final mappingsByStage = <String, List<AudioMapping>>{};
    for (final mapping in template.audioMappings) {
      mappingsByStage.putIfAbsent(mapping.stageId, () => []).add(mapping);
    }

    // Create events
    for (final entry in mappingsByStage.entries) {
      final stageId = entry.key;
      final mappings = entry.value;

      try {
        final event = _createAudioEvent(stageId, mappings, template);
        eventRegistry.registerEvent(event);
        count++;
      } catch (e) {
        debugPrint('[EventAutoRegistrar] ⚠️ Failed to create event for $stageId: $e');
      }
    }

    debugPrint('[EventAutoRegistrar] Registered $count events');
    return count;
  }

  /// Create an AudioEvent from mappings
  AudioEvent _createAudioEvent(
    String stageId,
    List<AudioMapping> mappings,
    BuiltTemplate template,
  ) {
    // Get stage definition for priority and settings
    final stageDef = template.source.allStages
        .where((s) => s.id == stageId)
        .firstOrNull;

    // Calculate pan for per-reel stages
    final pan = _calculatePanForStage(stageId, template);

    // Determine if this should loop
    final isLooping = stageDef?.isLooping ??
        stageId.contains('_LOOP') ||
        stageId.contains('SPINNING');

    // Create layers from mappings
    final layers = mappings.map((mapping) {
      return AudioLayer(
        id: 'layer_${mapping.stageId}_${mappings.indexOf(mapping)}',
        audioPath: mapping.audioPath,
        name: _nameFromPath(mapping.audioPath),
        volume: mapping.volume,
        pan: mapping.pan != 0.0 ? mapping.pan : pan,
        delay: 0.0,
        offset: 0.0,
        busId: mapping.busId,
      );
    }).toList();

    // Calculate total duration (use 0 for looping, estimate for others)
    final duration = isLooping ? 0.0 : 3.0; // Default 3 seconds

    return AudioEvent(
      id: 'evt_${stageId.toLowerCase()}',
      name: _generateEventName(stageId),
      stage: stageId,
      layers: layers,
      duration: duration,
      loop: isLooping,
      priority: stageDef?.priority ?? mappings.first.priority,
    );
  }

  /// Calculate pan position for per-reel stages
  double _calculatePanForStage(String stageId, BuiltTemplate template) {
    // Extract reel index from stage ID
    final reelMatch = RegExp(r'_(\d+)$').firstMatch(stageId);
    if (reelMatch == null) return 0.0;

    final reelIndex = int.parse(reelMatch.group(1)!);
    final reelCount = template.source.reelCount;

    // Pan formula: center reel = 0.0, leftmost = -0.8, rightmost = +0.8
    // For 5 reels: -0.8, -0.4, 0.0, +0.4, +0.8
    if (reelCount <= 1) return 0.0;

    final centerIndex = (reelCount - 1) / 2;
    final panStep = 0.8 / centerIndex;
    return ((reelIndex - centerIndex) * panStep).clamp(-1.0, 1.0);
  }

  /// Generate a human-readable event name from stage ID
  String _generateEventName(String stageId) {
    // Convert SPIN_START to "Spin Start"
    return stageId
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  /// Extract name from audio file path
  String _nameFromPath(String path) {
    final fileName = path.split('/').last;
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return nameWithoutExt
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }
}

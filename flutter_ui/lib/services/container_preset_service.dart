/// Container Preset Service (P3E)
///
/// Export/import container presets as `.ffxcontainer` JSON files.
/// Supports versioned schema for forward compatibility.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/middleware_models.dart';

/// Container preset schema version
const int kPresetSchemaVersion = 1;

/// Preset file extension
const String kPresetExtension = '.ffxcontainer';

/// Container preset data wrapper
class ContainerPreset {
  final int schemaVersion;
  final String type; // 'blend', 'random', 'sequence'
  final String name;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  ContainerPreset({
    required this.schemaVersion,
    required this.type,
    required this.name,
    required this.createdAt,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'type': type,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'data': data,
  };

  factory ContainerPreset.fromJson(Map<String, dynamic> json) {
    return ContainerPreset(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      type: json['type'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Untitled',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// Service for container preset import/export
class ContainerPresetService {
  static final ContainerPresetService _instance = ContainerPresetService._();
  static ContainerPresetService get instance => _instance;

  ContainerPresetService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // BLEND CONTAINER PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export blend container to preset file
  Future<bool> exportBlendContainer(BlendContainer container, String filePath) async {
    try {
      final preset = ContainerPreset(
        schemaVersion: kPresetSchemaVersion,
        type: 'blend',
        name: container.name,
        createdAt: DateTime.now(),
        data: _blendToPresetData(container),
      );

      final jsonStr = const JsonEncoder.withIndent('  ').convert(preset.toJson());
      final file = File(filePath);
      await file.writeAsString(jsonStr);

      debugPrint('[ContainerPresetService] Exported blend preset: ${container.name} → $filePath');
      return true;
    } catch (e) {
      debugPrint('[ContainerPresetService] Export error: $e');
      return false;
    }
  }

  /// Import blend container from preset file
  Future<BlendContainer?> importBlendContainer(String filePath, {int? newId}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[ContainerPresetService] File not found: $filePath');
        return null;
      }

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final preset = ContainerPreset.fromJson(json);

      if (preset.type != 'blend') {
        debugPrint('[ContainerPresetService] Wrong type: expected blend, got ${preset.type}');
        return null;
      }

      final container = _presetDataToBlend(preset.data, newId: newId);
      debugPrint('[ContainerPresetService] Imported blend preset: ${container.name}');
      return container;
    } catch (e) {
      debugPrint('[ContainerPresetService] Import error: $e');
      return null;
    }
  }

  Map<String, dynamic> _blendToPresetData(BlendContainer container) {
    return {
      'name': container.name,
      'rtpcId': container.rtpcId,
      'crossfadeCurve': container.crossfadeCurve.index,
      'enabled': container.enabled,
      'children': container.children.map((c) => {
        'name': c.name,
        'rtpcStart': c.rtpcStart,
        'rtpcEnd': c.rtpcEnd,
        'crossfadeWidth': c.crossfadeWidth,
        // Note: audioPath is NOT exported (project-specific)
      }).toList(),
    };
  }

  BlendContainer _presetDataToBlend(Map<String, dynamic> data, {int? newId}) {
    final children = (data['children'] as List<dynamic>?)?.asMap().entries.map((e) {
      final childData = e.value as Map<String, dynamic>;
      return BlendChild(
        id: e.key + 1,
        name: childData['name'] as String? ?? 'Child ${e.key + 1}',
        rtpcStart: (childData['rtpcStart'] as num?)?.toDouble() ?? 0.0,
        rtpcEnd: (childData['rtpcEnd'] as num?)?.toDouble() ?? 1.0,
        crossfadeWidth: (childData['crossfadeWidth'] as num?)?.toDouble() ?? 0.1,
        audioPath: null, // User must assign audio
      );
    }).toList() ?? [];

    return BlendContainer(
      id: newId ?? 0,
      name: data['name'] as String? ?? 'Imported Blend',
      rtpcId: data['rtpcId'] as int? ?? 0,
      crossfadeCurve: CrossfadeCurve.values[(data['crossfadeCurve'] as int?) ?? 0],
      enabled: data['enabled'] as bool? ?? true,
      children: children,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANDOM CONTAINER PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export random container to preset file
  Future<bool> exportRandomContainer(RandomContainer container, String filePath) async {
    try {
      final preset = ContainerPreset(
        schemaVersion: kPresetSchemaVersion,
        type: 'random',
        name: container.name,
        createdAt: DateTime.now(),
        data: _randomToPresetData(container),
      );

      final jsonStr = const JsonEncoder.withIndent('  ').convert(preset.toJson());
      final file = File(filePath);
      await file.writeAsString(jsonStr);

      debugPrint('[ContainerPresetService] Exported random preset: ${container.name}');
      return true;
    } catch (e) {
      debugPrint('[ContainerPresetService] Export error: $e');
      return false;
    }
  }

  /// Import random container from preset file
  Future<RandomContainer?> importRandomContainer(String filePath, {int? newId}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final preset = ContainerPreset.fromJson(json);

      if (preset.type != 'random') {
        debugPrint('[ContainerPresetService] Wrong type: expected random, got ${preset.type}');
        return null;
      }

      final container = _presetDataToRandom(preset.data, newId: newId);
      debugPrint('[ContainerPresetService] Imported random preset: ${container.name}');
      return container;
    } catch (e) {
      debugPrint('[ContainerPresetService] Import error: $e');
      return null;
    }
  }

  Map<String, dynamic> _randomToPresetData(RandomContainer container) {
    return {
      'name': container.name,
      'mode': container.mode.index,
      'enabled': container.enabled,
      'globalPitchMin': container.globalPitchMin,
      'globalPitchMax': container.globalPitchMax,
      'globalVolumeMin': container.globalVolumeMin,
      'globalVolumeMax': container.globalVolumeMax,
      'children': container.children.map((c) => {
        'name': c.name,
        'weight': c.weight,
        'pitchMin': c.pitchMin,
        'pitchMax': c.pitchMax,
        'volumeMin': c.volumeMin,
        'volumeMax': c.volumeMax,
      }).toList(),
    };
  }

  RandomContainer _presetDataToRandom(Map<String, dynamic> data, {int? newId}) {
    final children = (data['children'] as List<dynamic>?)?.asMap().entries.map((e) {
      final childData = e.value as Map<String, dynamic>;
      return RandomChild(
        id: e.key + 1,
        name: childData['name'] as String? ?? 'Child ${e.key + 1}',
        weight: (childData['weight'] as num?)?.toDouble() ?? 1.0,
        pitchMin: (childData['pitchMin'] as num?)?.toDouble() ?? 0.0,
        pitchMax: (childData['pitchMax'] as num?)?.toDouble() ?? 0.0,
        volumeMin: (childData['volumeMin'] as num?)?.toDouble() ?? 1.0,
        volumeMax: (childData['volumeMax'] as num?)?.toDouble() ?? 1.0,
        audioPath: null,
      );
    }).toList() ?? [];

    return RandomContainer(
      id: newId ?? 0,
      name: data['name'] as String? ?? 'Imported Random',
      mode: RandomMode.values[(data['mode'] as int?) ?? 0],
      enabled: data['enabled'] as bool? ?? true,
      globalPitchMin: (data['globalPitchMin'] as num?)?.toDouble() ?? 0.0,
      globalPitchMax: (data['globalPitchMax'] as num?)?.toDouble() ?? 0.0,
      globalVolumeMin: (data['globalVolumeMin'] as num?)?.toDouble() ?? 1.0,
      globalVolumeMax: (data['globalVolumeMax'] as num?)?.toDouble() ?? 1.0,
      children: children,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEQUENCE CONTAINER PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export sequence container to preset file
  Future<bool> exportSequenceContainer(SequenceContainer container, String filePath) async {
    try {
      final preset = ContainerPreset(
        schemaVersion: kPresetSchemaVersion,
        type: 'sequence',
        name: container.name,
        createdAt: DateTime.now(),
        data: _sequenceToPresetData(container),
      );

      final jsonStr = const JsonEncoder.withIndent('  ').convert(preset.toJson());
      final file = File(filePath);
      await file.writeAsString(jsonStr);

      debugPrint('[ContainerPresetService] Exported sequence preset: ${container.name}');
      return true;
    } catch (e) {
      debugPrint('[ContainerPresetService] Export error: $e');
      return false;
    }
  }

  /// Import sequence container from preset file
  Future<SequenceContainer?> importSequenceContainer(String filePath, {int? newId}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final preset = ContainerPreset.fromJson(json);

      if (preset.type != 'sequence') {
        debugPrint('[ContainerPresetService] Wrong type: expected sequence, got ${preset.type}');
        return null;
      }

      final container = _presetDataToSequence(preset.data, newId: newId);
      debugPrint('[ContainerPresetService] Imported sequence preset: ${container.name}');
      return container;
    } catch (e) {
      debugPrint('[ContainerPresetService] Import error: $e');
      return null;
    }
  }

  Map<String, dynamic> _sequenceToPresetData(SequenceContainer container) {
    return {
      'name': container.name,
      'endBehavior': container.endBehavior.index,
      'speed': container.speed,
      'enabled': container.enabled,
      'steps': container.steps.map((s) => {
        'childName': s.childName,
        'delayMs': s.delayMs,
        'durationMs': s.durationMs,
        'fadeInMs': s.fadeInMs,
        'fadeOutMs': s.fadeOutMs,
        'loopCount': s.loopCount,
        'volume': s.volume,
      }).toList(),
    };
  }

  SequenceContainer _presetDataToSequence(Map<String, dynamic> data, {int? newId}) {
    final steps = (data['steps'] as List<dynamic>?)?.asMap().entries.map((e) {
      final stepData = e.value as Map<String, dynamic>;
      return SequenceStep(
        index: e.key,
        childId: e.key + 1,
        childName: stepData['childName'] as String? ?? 'Step ${e.key + 1}',
        audioPath: null,
        delayMs: (stepData['delayMs'] as num?)?.toDouble() ?? 0.0,
        durationMs: (stepData['durationMs'] as num?)?.toDouble() ?? 100.0,
        fadeInMs: (stepData['fadeInMs'] as num?)?.toDouble() ?? 0.0,
        fadeOutMs: (stepData['fadeOutMs'] as num?)?.toDouble() ?? 0.0,
        loopCount: stepData['loopCount'] as int? ?? 1,
        volume: (stepData['volume'] as num?)?.toDouble() ?? 1.0,
      );
    }).toList() ?? [];

    return SequenceContainer(
      id: newId ?? 0,
      name: data['name'] as String? ?? 'Imported Sequence',
      endBehavior: SequenceEndBehavior.values[(data['endBehavior'] as int?) ?? 0],
      speed: (data['speed'] as num?)?.toDouble() ?? 1.0,
      enabled: data['enabled'] as bool? ?? true,
      steps: steps,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GENERIC IMPORT (auto-detect type)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import any container type from preset file
  /// Returns ContainerPreset with data, caller decides what to do with it
  Future<ContainerPreset?> importPreset(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ContainerPreset.fromJson(json);
    } catch (e) {
      debugPrint('[ContainerPresetService] Import error: $e');
      return null;
    }
  }

  /// Check preset type without full import
  Future<String?> getPresetType(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json['type'] as String?;
    } catch (e) {
      return null;
    }
  }
}

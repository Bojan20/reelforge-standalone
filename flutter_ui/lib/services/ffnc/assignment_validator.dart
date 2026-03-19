/// Assignment Validator — catches audio configuration errors before runtime.
///
/// Checks for missing audio, missing files, zero volume, loops without fade,
/// duplicate assignments, layer gaps, and invalid bus references.

import 'dart:io';
import '../../models/slot_audio_events.dart';

enum WarningSeverity { error, warning, info }

enum WarningType {
  missingAudio,        // Stage has no audio file assigned
  missingFile,         // Assigned file doesn't exist on disk
  zeroVolume,          // Volume is 0.0 (intentional for music L2+, warn for others)
  noFadeOnLoop,        // Looping sound with no fade-out (potential pop)
  duplicateAssignment, // Two different stages point to same file
  layerGap,            // Layer 1 and 3 exist but not 2
  invalidBus,          // Bus ID not in valid range 0-5
  noVariants,          // Pooled stage (rollup_tick, cascade_step) with only 1 file
}

class AssignmentWarning {
  final String stage;
  final WarningType type;
  final String message;
  final WarningSeverity severity;

  const AssignmentWarning({
    required this.stage,
    required this.type,
    required this.message,
    required this.severity,
  });
}

class AssignmentValidator {
  AssignmentValidator._();

  // Stages where volume 0.0 is expected (music L2-L5 start silent for crossfade)
  static const _silentByDesign = {
    'MUSIC_BASE_L2', 'MUSIC_BASE_L3', 'MUSIC_BASE_L4', 'MUSIC_BASE_L5',
    'MUSIC_FS_L2', 'MUSIC_FS_L3', 'MUSIC_FS_L4', 'MUSIC_FS_L5',
    'MUSIC_BONUS_L2', 'MUSIC_BONUS_L3', 'MUSIC_BONUS_L4', 'MUSIC_BONUS_L5',
    'MUSIC_HOLD_L2', 'MUSIC_HOLD_L3', 'MUSIC_HOLD_L4', 'MUSIC_HOLD_L5',
    'MUSIC_JACKPOT_L2', 'MUSIC_JACKPOT_L3', 'MUSIC_JACKPOT_L4', 'MUSIC_JACKPOT_L5',
    'MUSIC_GAMBLE_L2', 'MUSIC_GAMBLE_L3', 'MUSIC_GAMBLE_L4', 'MUSIC_GAMBLE_L5',
    'MUSIC_REVEAL_L2', 'MUSIC_REVEAL_L3', 'MUSIC_REVEAL_L4', 'MUSIC_REVEAL_L5',
  };

  // Stages that benefit from variants (rapid-fire, repetitive sounds)
  static const _pooledStages = {
    'ROLLUP_TICK', 'ROLLUP_TICK_FAST', 'CASCADE_STEP', 'CASCADE_POP',
    'COIN_DROP', 'COIN_COLLECT', 'WHEEL_TICK',
  };

  // Critical gameplay stages — missing = error
  static const _p0Stages = {
    'SPIN_START', 'REEL_SPIN_LOOP', 'SPIN_END',
    'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2', 'REEL_STOP_3', 'REEL_STOP_4',
    'REEL_STOP',
  };

  // Important stages — missing = warning
  static const _p1Prefixes = [
    'WIN_PRESENT_', 'BIG_WIN_', 'ROLLUP_', 'MUSIC_BASE_L',
    'FEATURE_', 'FREESPIN_',
  ];

  static List<AssignmentWarning> validate({
    required Map<String, String> audioAssignments,
    required List<SlotCompositeEvent> compositeEvents,
    required Set<String> enabledStages,
    Map<String, List<String>>? audioVariants,
  }) {
    final warnings = <AssignmentWarning>[];

    // 1. Missing audio for enabled stages
    for (final stage in enabledStages) {
      if (!audioAssignments.containsKey(stage) ||
          audioAssignments[stage]!.isEmpty) {
        warnings.add(AssignmentWarning(
          stage: stage,
          type: WarningType.missingAudio,
          message: 'No audio assigned',
          severity: _stageSeverity(stage),
        ));
      }
    }

    // 2. Missing files (assigned but file doesn't exist)
    for (final entry in audioAssignments.entries) {
      if (entry.value.isEmpty) continue;
      if (!File(entry.value).existsSync()) {
        warnings.add(AssignmentWarning(
          stage: entry.key,
          type: WarningType.missingFile,
          message: 'File not found: ${entry.value.split('/').last}',
          severity: WarningSeverity.error,
        ));
      }
    }

    // 3. Composite event checks
    for (final event in compositeEvents) {
      final stage = event.triggerStages.isNotEmpty
          ? event.triggerStages.first
          : event.id.replaceFirst('audio_', '');

      // Zero volume (skip music L2-L5 which are intentionally silent)
      if (event.masterVolume == 0.0 && !_silentByDesign.contains(stage)) {
        warnings.add(AssignmentWarning(
          stage: stage,
          type: WarningType.zeroVolume,
          message: 'Master volume is 0.0',
          severity: WarningSeverity.warning,
        ));
      }

      // Per-layer checks
      for (final layer in event.layers) {
        // Zero volume layer (not auto-generated, not silent-by-design)
        if (layer.volume == 0.0 &&
            layer.actionType == 'Play' &&
            layer.audioPath.isNotEmpty &&
            !layer.id.startsWith('auto_') &&
            !_silentByDesign.contains(stage)) {
          warnings.add(AssignmentWarning(
            stage: stage,
            type: WarningType.zeroVolume,
            message: 'Layer "${layer.name}" volume is 0.0',
            severity: WarningSeverity.warning,
          ));
        }

        // Loop without fade-out
        if ((layer.loop || event.looping) &&
            layer.fadeOutMs == 0 &&
            layer.actionType == 'Play' &&
            layer.audioPath.isNotEmpty) {
          warnings.add(AssignmentWarning(
            stage: stage,
            type: WarningType.noFadeOnLoop,
            message: 'Layer "${layer.name}" loops without fade-out (potential pop)',
            severity: WarningSeverity.info,
          ));
        }

        // Invalid bus ID
        if (layer.busId != null && (layer.busId! < 0 || layer.busId! > 5)) {
          warnings.add(AssignmentWarning(
            stage: stage,
            type: WarningType.invalidBus,
            message: 'Layer "${layer.name}" has invalid bus ID: ${layer.busId}',
            severity: WarningSeverity.error,
          ));
        }
      }

      // Layer gap check (layer1 + layer3 but no layer2)
      final layerNumbers = event.layers
          .where((l) => l.id.contains('ffnc_layer_'))
          .map((l) {
            final match = RegExp(r'ffnc_layer_\w+_(\d+)').firstMatch(l.id);
            return match != null ? int.tryParse(match.group(1)!) : null;
          })
          .where((n) => n != null)
          .cast<int>()
          .toList()
        ..sort();

      if (layerNumbers.length >= 2) {
        for (int i = 1; i < layerNumbers.length; i++) {
          if (layerNumbers[i] - layerNumbers[i - 1] > 1) {
            warnings.add(AssignmentWarning(
              stage: stage,
              type: WarningType.layerGap,
              message: 'Layer gap: L${layerNumbers[i - 1]} and L${layerNumbers[i]} exist but L${layerNumbers[i - 1] + 1} missing',
              severity: WarningSeverity.warning,
            ));
          }
        }
      }
    }

    // 4. Duplicate assignments (same file on different stages)
    final pathToStages = <String, List<String>>{};
    for (final entry in audioAssignments.entries) {
      if (entry.value.isEmpty) continue;
      pathToStages.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    for (final entry in pathToStages.entries) {
      if (entry.value.length > 1) {
        // SCATTER_LAND → WILD_LAND sharing is expected — skip
        final stages = entry.value;
        final isScatterWildPair = stages.length == 2 &&
            stages.any((s) => s.startsWith('SCATTER_LAND')) &&
            stages.any((s) => s.startsWith('WILD_LAND'));
        if (!isScatterWildPair) {
          for (final stage in stages) {
            warnings.add(AssignmentWarning(
              stage: stage,
              type: WarningType.duplicateAssignment,
              message: 'Same file used by: ${stages.where((s) => s != stage).join(", ")}',
              severity: WarningSeverity.info,
            ));
          }
        }
      }
    }

    // 5. Pooled stages without variants (repetitive sounds need variation)
    if (audioVariants != null) {
      for (final stage in _pooledStages) {
        if (audioAssignments.containsKey(stage)) {
          final variants = audioVariants[stage];
          if (variants == null || variants.length <= 1) {
            warnings.add(AssignmentWarning(
              stage: stage,
              type: WarningType.noVariants,
              message: 'Rapid-fire stage with only 1 sound (consider adding variants)',
              severity: WarningSeverity.info,
            ));
          }
        }
      }
    }

    // Sort: errors first, then warnings, then info
    warnings.sort((a, b) {
      final aSev = a.severity.index;
      final bSev = b.severity.index;
      if (aSev != bSev) return aSev.compareTo(bSev);
      return a.stage.compareTo(b.stage);
    });

    return warnings;
  }

  /// Get warning for a specific stage (first match only).
  static AssignmentWarning? getWarningForStage(String stage, List<AssignmentWarning> allWarnings) {
    return allWarnings.where((w) => w.stage == stage).firstOrNull;
  }

  /// Get all warnings for stages in a phase.
  static List<AssignmentWarning> getWarningsForStages(Set<String> stages, List<AssignmentWarning> allWarnings) {
    return allWarnings.where((w) => stages.contains(w.stage)).toList();
  }

  static WarningSeverity _stageSeverity(String stage) {
    if (_p0Stages.contains(stage)) return WarningSeverity.error;
    for (final prefix in _p1Prefixes) {
      if (stage.startsWith(prefix)) return WarningSeverity.warning;
    }
    return WarningSeverity.info;
  }
}

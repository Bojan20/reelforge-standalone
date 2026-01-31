/// Template Validation Service
///
/// Validates that all template wiring is complete and functional.
/// Checks audio file existence, stage mappings, and system consistency.
///
/// P3-12: Template Gallery
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/template_models.dart';
import '../../providers/ale_provider.dart';
import '../../providers/subsystems/bus_hierarchy_provider.dart';
import '../../providers/subsystems/ducking_system_provider.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../../services/event_registry.dart';
import '../../services/stage_configuration_service.dart';
import '../service_locator.dart';

/// Validation result for a single check
class ValidationResult {
  final String checkId;
  final String checkName;
  final bool passed;
  final String? message;
  final ValidationSeverity severity;

  const ValidationResult({
    required this.checkId,
    required this.checkName,
    required this.passed,
    this.message,
    this.severity = ValidationSeverity.error,
  });

  @override
  String toString() {
    final status = passed ? '✅' : (severity == ValidationSeverity.warning ? '⚠️' : '❌');
    return '$status $checkName${message != null ? ': $message' : ''}';
  }
}

/// Severity level for validation issues
enum ValidationSeverity {
  error,    // Critical - blocks usage
  warning,  // Non-critical - works but may have issues
  info,     // Informational - suggestions
}

/// Complete validation report
class ValidationReport {
  final List<ValidationResult> results;
  final Duration validationTime;
  final DateTime timestamp;

  const ValidationReport({
    required this.results,
    required this.validationTime,
    required this.timestamp,
  });

  /// All checks passed
  bool get allPassed => results.every((r) => r.passed);

  /// Has any errors (not just warnings)
  bool get hasErrors => results.any((r) => !r.passed && r.severity == ValidationSeverity.error);

  /// Has any warnings
  bool get hasWarnings => results.any((r) => !r.passed && r.severity == ValidationSeverity.warning);

  /// Count of passed checks
  int get passedCount => results.where((r) => r.passed).length;

  /// Count of failed checks
  int get failedCount => results.where((r) => !r.passed).length;

  /// Summary string
  String get summary {
    if (allPassed) {
      return '✅ All ${results.length} checks passed';
    } else {
      final errors = results.where((r) => !r.passed && r.severity == ValidationSeverity.error).length;
      final warnings = results.where((r) => !r.passed && r.severity == ValidationSeverity.warning).length;
      return '${errors > 0 ? '❌ $errors error(s)' : ''}${errors > 0 && warnings > 0 ? ', ' : ''}${warnings > 0 ? '⚠️ $warnings warning(s)' : ''} of ${results.length} checks';
    }
  }
}

/// Validates template wiring completeness
class TemplateValidationService {
  /// Validate a built template
  ///
  /// Returns comprehensive validation report
  ValidationReport validate(BuiltTemplate template) {
    final stopwatch = Stopwatch()..start();
    final results = <ValidationResult>[];

    // 1. Validate audio file existence
    results.addAll(_validateAudioFiles(template));

    // 2. Validate stage registrations
    results.addAll(_validateStages(template));

    // 3. Validate event registrations
    results.addAll(_validateEvents(template));

    // 4. Validate bus configuration
    results.addAll(_validateBuses(template));

    // 5. Validate ducking rules
    results.addAll(_validateDucking(template));

    // 6. Validate ALE contexts
    results.addAll(_validateAle(template));

    // 7. Validate RTPC definitions
    results.addAll(_validateRtpc(template));

    // 8. Validate template consistency
    results.addAll(_validateConsistency(template));

    stopwatch.stop();

    final report = ValidationReport(
      results: results,
      validationTime: stopwatch.elapsed,
      timestamp: DateTime.now(),
    );

    debugPrint('[TemplateValidationService] ${report.summary}');
    return report;
  }

  /// Validate that all referenced audio files exist
  List<ValidationResult> _validateAudioFiles(BuiltTemplate template) {
    final results = <ValidationResult>[];
    int missingCount = 0;
    int totalCount = 0;

    for (final mapping in template.audioMappings) {
      totalCount++;
      final file = File(mapping.audioPath);
      if (!file.existsSync()) {
        missingCount++;
        results.add(ValidationResult(
          checkId: 'audio_file_${mapping.stageId}',
          checkName: 'Audio file for ${mapping.stageId}',
          passed: false,
          message: 'File not found: ${mapping.audioPath}',
          severity: ValidationSeverity.error,
        ));
      }
    }

    if (missingCount == 0 && totalCount > 0) {
      results.add(ValidationResult(
        checkId: 'audio_files_all',
        checkName: 'Audio files',
        passed: true,
        message: 'All $totalCount audio files found',
      ));
    }

    if (totalCount == 0) {
      results.add(ValidationResult(
        checkId: 'audio_files_none',
        checkName: 'Audio files',
        passed: false,
        message: 'No audio mappings defined',
        severity: ValidationSeverity.warning,
      ));
    }

    return results;
  }

  /// Validate stage registrations
  List<ValidationResult> _validateStages(BuiltTemplate template) {
    final results = <ValidationResult>[];
    final stageService = StageConfigurationService.instance;

    int registeredCount = 0;
    int missingCount = 0;

    // Check each stage from template is registered
    for (final stageDef in template.source.coreStages) {
      final stageName = stageDef.id;
      final priority = stageService.getPriority(stageName);

      if (priority > 0) {
        registeredCount++;
      } else {
        missingCount++;
        results.add(ValidationResult(
          checkId: 'stage_$stageName',
          checkName: 'Stage registration: $stageName',
          passed: false,
          message: 'Stage not found in StageConfigurationService',
          severity: ValidationSeverity.warning,
        ));
      }
    }

    if (missingCount == 0 && registeredCount > 0) {
      results.add(ValidationResult(
        checkId: 'stages_all',
        checkName: 'Stage registrations',
        passed: true,
        message: 'All $registeredCount stages registered',
      ));
    }

    return results;
  }

  /// Validate event registrations
  List<ValidationResult> _validateEvents(BuiltTemplate template) {
    final results = <ValidationResult>[];
    final eventRegistry = EventRegistry.instance;

    int withAudioCount = 0;
    int withoutAudioCount = 0;

    for (final mapping in template.audioMappings) {
      final hasEvent = eventRegistry.hasEventForStage(mapping.stageId);
      if (hasEvent) {
        withAudioCount++;
      } else {
        withoutAudioCount++;
      }
    }

    results.add(ValidationResult(
      checkId: 'events_registered',
      checkName: 'Event registrations',
      passed: withAudioCount > 0,
      message: '$withAudioCount events registered${withoutAudioCount > 0 ? ', $withoutAudioCount stages without events' : ''}',
      severity: withAudioCount == 0 ? ValidationSeverity.error : ValidationSeverity.info,
    ));

    return results;
  }

  /// Validate bus configuration
  List<ValidationResult> _validateBuses(BuiltTemplate template) {
    final results = <ValidationResult>[];

    try {
      final busProvider = sl<BusHierarchyProvider>();
      final buses = busProvider.allBuses;

      // Check for required buses
      final requiredBuses = ['master', 'music', 'sfx', 'wins', 'voice', 'ui', 'ambience'];
      int foundCount = 0;

      for (final busName in requiredBuses) {
        final exists = buses.any((b) => b.name.toLowerCase() == busName.toLowerCase());
        if (exists) {
          foundCount++;
        } else {
          results.add(ValidationResult(
            checkId: 'bus_$busName',
            checkName: 'Bus: $busName',
            passed: false,
            message: 'Required bus not configured',
            severity: ValidationSeverity.warning,
          ));
        }
      }

      if (foundCount == requiredBuses.length) {
        results.add(ValidationResult(
          checkId: 'buses_all',
          checkName: 'Bus configuration',
          passed: true,
          message: 'All ${requiredBuses.length} required buses configured',
        ));
      }
    } catch (e) {
      results.add(ValidationResult(
        checkId: 'buses_error',
        checkName: 'Bus configuration',
        passed: false,
        message: 'Failed to validate buses: $e',
        severity: ValidationSeverity.error,
      ));
    }

    return results;
  }

  /// Validate ducking rules
  List<ValidationResult> _validateDucking(BuiltTemplate template) {
    final results = <ValidationResult>[];

    try {
      final duckingProvider = sl<DuckingSystemProvider>();
      final rulesList = duckingProvider.duckingRules;

      if (rulesList.isEmpty) {
        results.add(ValidationResult(
          checkId: 'ducking_none',
          checkName: 'Ducking rules',
          passed: false,
          message: 'No ducking rules configured',
          severity: ValidationSeverity.warning,
        ));
      } else {
        results.add(ValidationResult(
          checkId: 'ducking_configured',
          checkName: 'Ducking rules',
          passed: true,
          message: '${rulesList.length} ducking rules configured',
        ));
      }

      // Check for essential ducking rules
      final hasWinDuck = rulesList.any((r) =>
          r.sourceBus.toLowerCase().contains('win') &&
          r.targetBus.toLowerCase().contains('music'));
      final hasVoiceDuck = rulesList.any((r) =>
          r.sourceBus.toLowerCase().contains('voice') &&
          (r.targetBus.toLowerCase().contains('music') || r.targetBus.toLowerCase().contains('sfx')));

      if (!hasWinDuck) {
        results.add(ValidationResult(
          checkId: 'ducking_win_music',
          checkName: 'Win → Music ducking',
          passed: false,
          message: 'Recommended ducking rule not found',
          severity: ValidationSeverity.info,
        ));
      }

      if (!hasVoiceDuck) {
        results.add(ValidationResult(
          checkId: 'ducking_voice',
          checkName: 'Voice ducking',
          passed: false,
          message: 'Recommended voice ducking not found',
          severity: ValidationSeverity.info,
        ));
      }
    } catch (e) {
      results.add(ValidationResult(
        checkId: 'ducking_error',
        checkName: 'Ducking validation',
        passed: false,
        message: 'Failed to validate ducking: $e',
        severity: ValidationSeverity.error,
      ));
    }

    return results;
  }

  /// Validate ALE contexts
  List<ValidationResult> _validateAle(BuiltTemplate template) {
    final results = <ValidationResult>[];

    try {
      final aleProvider = sl<AleProvider>();
      final profile = aleProvider.profile;
      final contexts = profile?.contexts ?? {};

      if (contexts.isEmpty) {
        results.add(ValidationResult(
          checkId: 'ale_none',
          checkName: 'ALE contexts',
          passed: false,
          message: 'No ALE contexts configured',
          severity: ValidationSeverity.warning,
        ));
      } else {
        results.add(ValidationResult(
          checkId: 'ale_configured',
          checkName: 'ALE contexts',
          passed: true,
          message: '${contexts.length} ALE contexts configured',
        ));

        // Check for base game context
        final hasBaseGame = contexts.values.any((c) =>
            c.id.toLowerCase().contains('base') ||
            c.name.toLowerCase().contains('base'));

        if (!hasBaseGame) {
          results.add(ValidationResult(
            checkId: 'ale_base_game',
            checkName: 'ALE base game context',
            passed: false,
            message: 'No base game context found',
            severity: ValidationSeverity.info,
          ));
        }
      }
    } catch (e) {
      results.add(ValidationResult(
        checkId: 'ale_error',
        checkName: 'ALE validation',
        passed: false,
        message: 'Failed to validate ALE: $e',
        severity: ValidationSeverity.error,
      ));
    }

    return results;
  }

  /// Validate RTPC definitions
  List<ValidationResult> _validateRtpc(BuiltTemplate template) {
    final results = <ValidationResult>[];

    try {
      final rtpcProvider = sl<RtpcSystemProvider>();
      final definitions = rtpcProvider.rtpcDefinitions;

      if (definitions.isEmpty) {
        results.add(ValidationResult(
          checkId: 'rtpc_none',
          checkName: 'RTPC definitions',
          passed: false,
          message: 'No RTPC definitions configured',
          severity: ValidationSeverity.warning,
        ));
      } else {
        results.add(ValidationResult(
          checkId: 'rtpc_configured',
          checkName: 'RTPC definitions',
          passed: true,
          message: '${definitions.length} RTPC definitions configured',
        ));

        // Check for winMultiplier RTPC
        final hasWinMultiplier = definitions.any((d) =>
            d.name.toLowerCase().contains('win') ||
            d.name.toLowerCase().contains('multiplier'));

        if (!hasWinMultiplier) {
          results.add(ValidationResult(
            checkId: 'rtpc_win_multiplier',
            checkName: 'RTPC winMultiplier',
            passed: false,
            message: 'winMultiplier RTPC not found',
            severity: ValidationSeverity.warning,
          ));
        }
      }
    } catch (e) {
      results.add(ValidationResult(
        checkId: 'rtpc_error',
        checkName: 'RTPC validation',
        passed: false,
        message: 'Failed to validate RTPC: $e',
        severity: ValidationSeverity.error,
      ));
    }

    return results;
  }

  /// Validate template internal consistency
  List<ValidationResult> _validateConsistency(BuiltTemplate template) {
    final results = <ValidationResult>[];

    // Check grid configuration
    final reels = template.source.reelCount;
    final rows = template.source.rowCount;
    if (reels < 3 || reels > 8) {
      results.add(ValidationResult(
        checkId: 'consistency_reels',
        checkName: 'Grid reels',
        passed: false,
        message: 'Unusual reel count: $reels (expected 3-8)',
        severity: ValidationSeverity.warning,
      ));
    }

    if (rows < 2 || rows > 6) {
      results.add(ValidationResult(
        checkId: 'consistency_rows',
        checkName: 'Grid rows',
        passed: false,
        message: 'Unusual row count: $rows (expected 2-6)',
        severity: ValidationSeverity.warning,
      ));
    }

    // Check symbols
    if (template.source.symbols.isEmpty) {
      results.add(ValidationResult(
        checkId: 'consistency_symbols',
        checkName: 'Symbols',
        passed: false,
        message: 'No symbols defined',
        severity: ValidationSeverity.error,
      ));
    } else {
      final hasWild = template.source.symbols.any((s) => s.type == SymbolType.wild);
      final hasScatter = template.source.symbols.any((s) => s.type == SymbolType.scatter);

      if (!hasWild) {
        results.add(ValidationResult(
          checkId: 'consistency_wild',
          checkName: 'Wild symbol',
          passed: false,
          message: 'No wild symbol defined',
          severity: ValidationSeverity.info,
        ));
      }

      if (!hasScatter && template.source.modules.any((f) => f.type == FeatureModuleType.freeSpins)) {
        results.add(ValidationResult(
          checkId: 'consistency_scatter',
          checkName: 'Scatter symbol',
          passed: false,
          message: 'Free spins feature enabled but no scatter symbol',
          severity: ValidationSeverity.warning,
        ));
      }
    }

    // Check win tiers
    if (template.source.winTiers.isEmpty) {
      results.add(ValidationResult(
        checkId: 'consistency_win_tiers',
        checkName: 'Win tiers',
        passed: false,
        message: 'No win tiers defined',
        severity: ValidationSeverity.warning,
      ));
    }

    // If all consistency checks pass, add summary
    final consistencyFails = results.where((r) => !r.passed).length;
    if (consistencyFails == 0) {
      results.add(ValidationResult(
        checkId: 'consistency_all',
        checkName: 'Template consistency',
        passed: true,
        message: 'Template is internally consistent',
      ));
    }

    return results;
  }
}

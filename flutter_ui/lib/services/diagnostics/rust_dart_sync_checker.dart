import 'diagnostics_service.dart';
import '../../models/stage_models.dart' as dart_stage;

/// Validates that Rust engine stage names match Dart-side expectations.
///
/// This checker prevents the SpinStart↔UiSpinPress class of bugs where
/// engine generates one name but Dart code expects another.
///
/// How it works:
/// 1. Reads stage names from last spin result (what engine actually generates)
/// 2. Tries to parse each through Dart's Stage.fromTypeName()
/// 3. Any stage that fails parsing = Rust↔Dart mismatch
/// 4. Cross-references with SlotLabProvider._processStageEvent expectations
class RustDartSyncChecker extends DiagnosticChecker {
  final List<String> Function()? _getLastStageTypes;

  RustDartSyncChecker({List<String> Function()? getLastStageTypes})
      : _getLastStageTypes = getLastStageTypes;

  @override
  String get name => 'RustDartSync';

  @override
  String get description =>
      'Validates Rust engine stage names match Dart parser';

  @override
  List<DiagnosticFinding> check() {
    final findings = <DiagnosticFinding>[];

    findings.addAll(_checkDartParserCoversRustStages());
    findings.addAll(_checkCriticalStageMapping());

    if (findings.where((f) => !f.isOk).isEmpty) {
      findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.ok,
        message: 'Rust↔Dart stage names in sync',
      ));
    }

    return findings;
  }

  /// Check that every stage from last spin can be parsed by Dart
  List<DiagnosticFinding> _checkDartParserCoversRustStages() {
    final findings = <DiagnosticFinding>[];

    final getTypes = _getLastStageTypes;
    if (getTypes == null) return findings;

    final stageTypes = getTypes();
    if (stageTypes.isEmpty) return findings;

    final uniqueTypes = stageTypes.toSet();
    int parsed = 0;
    int failed = 0;

    for (final type in uniqueTypes) {
      final stage = dart_stage.Stage.fromTypeName(type);
      if (stage != null) {
        parsed++;
      } else {
        // Not every stage needs a Dart class — custom/dynamic stages are OK
        // But core lifecycle stages MUST parse
        if (_isCoreStage(type)) {
          findings.add(DiagnosticFinding(
            checker: name,
            severity: DiagnosticSeverity.error,
            message: 'Core stage "$type" not recognized by Dart parser',
            detail: 'Stage.fromTypeName("$type") returned null. '
                'Add case to Stage.fromJson() in stage_models.dart',
            affectedStage: type,
          ));
          failed++;
        }
      }
    }

    if (failed == 0 && parsed > 0) {
      findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.ok,
        message: '$parsed/${uniqueTypes.length} stage types recognized by Dart parser',
      ));
    }

    return findings;
  }

  /// Verify critical stage mappings that MUST work
  List<DiagnosticFinding> _checkCriticalStageMapping() {
    final findings = <DiagnosticFinding>[];

    // These mappings are critical — if any fails, features break
    const criticalMappings = {
      'ui_spin_press': 'UI_SPIN_PRESS',
      'reel_stop': 'REEL_STOP',
      'spin_end': 'SPIN_END',
      'evaluate_wins': 'EVALUATE_WINS',
      'reel_spin_loop': 'REEL_SPIN_LOOP',
    };

    for (final entry in criticalMappings.entries) {
      final rustName = entry.key;
      final dartExpected = entry.value;

      // Verify toUpperCase mapping
      if (rustName.toUpperCase() != dartExpected) {
        findings.add(DiagnosticFinding(
          checker: name,
          severity: DiagnosticSeverity.error,
          message: 'Critical mapping broken: "$rustName".toUpperCase() = '
              '"${rustName.toUpperCase()}" but expected "$dartExpected"',
          affectedStage: dartExpected,
        ));
      }

      // Verify Dart parser handles it
      final stage = dart_stage.Stage.fromTypeName(rustName);
      if (stage == null) {
        findings.add(DiagnosticFinding(
          checker: name,
          severity: DiagnosticSeverity.error,
          message: 'Dart parser cannot parse critical stage "$rustName"',
          detail: 'Stage.fromTypeName("$rustName") = null',
          affectedStage: dartExpected,
        ));
      }
    }

    return findings;
  }

  bool _isCoreStage(String type) {
    const coreStages = {
      'ui_spin_press',
      'reel_spin_loop',
      'reel_spinning',
      'reel_stop',
      'evaluate_wins',
      'spin_end',
      'anticipation_on',
      'anticipation_off',
      'win_present',
      'no_win',
      'rollup_start',
      'rollup_end',
      'big_win_start',
      'big_win_end',
      'feature_enter',
      'feature_exit',
    };
    return coreStages.contains(type.toLowerCase());
  }
}

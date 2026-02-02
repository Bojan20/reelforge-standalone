import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ui/services/gdd_import_service.dart';
import 'package:flutter_ui/services/gdd_validator_service.dart';

void main() {
  late GddValidatorService validator;

  setUp(() {
    validator = GddValidatorService.instance;
  });

  group('ValidationSeverity', () {
    test('has correct labels', () {
      expect(ValidationSeverity.error.label, 'Error');
      expect(ValidationSeverity.warning.label, 'Warning');
      expect(ValidationSeverity.info.label, 'Info');
    });

    test('has correct icons', () {
      expect(ValidationSeverity.error.icon, contains('❌'));
      expect(ValidationSeverity.warning.icon, contains('⚠'));
      expect(ValidationSeverity.info.icon, contains('ℹ'));
    });
  });

  group('ValidationCategory', () {
    test('has correct labels', () {
      expect(ValidationCategory.grid.label, 'Grid Configuration');
      expect(ValidationCategory.symbols.label, 'Symbol Definitions');
      expect(ValidationCategory.paytable.label, 'Paytable');
      expect(ValidationCategory.math.label, 'Math Model');
      expect(ValidationCategory.features.label, 'Features');
      expect(ValidationCategory.stages.label, 'Stage Events');
    });
  });

  group('ValidationIssue', () {
    test('toString formats correctly', () {
      const issue = ValidationIssue(
        severity: ValidationSeverity.error,
        category: ValidationCategory.grid,
        code: 'TEST_001',
        message: 'Test message',
        details: 'Extra info',
      );

      final str = issue.toString();
      expect(str, contains('TEST_001'));
      expect(str, contains('Test message'));
      expect(str, contains('Extra info'));
    });
  });

  group('GddValidationResult', () {
    test('calculates counts correctly', () {
      final result = GddValidationResult(
        isValid: false,
        issues: const [
          ValidationIssue(
            severity: ValidationSeverity.error,
            category: ValidationCategory.grid,
            code: 'E1',
            message: 'Error 1',
          ),
          ValidationIssue(
            severity: ValidationSeverity.error,
            category: ValidationCategory.grid,
            code: 'E2',
            message: 'Error 2',
          ),
          ValidationIssue(
            severity: ValidationSeverity.warning,
            category: ValidationCategory.symbols,
            code: 'W1',
            message: 'Warning 1',
          ),
          ValidationIssue(
            severity: ValidationSeverity.info,
            category: ValidationCategory.math,
            code: 'I1',
            message: 'Info 1',
          ),
        ],
        validationDuration: const Duration(milliseconds: 10),
      );

      expect(result.errorCount, 2);
      expect(result.warningCount, 1);
      expect(result.infoCount, 1);
      expect(result.issuesByCategory[ValidationCategory.grid]?.length, 2);
      expect(result.issuesByCategory[ValidationCategory.symbols]?.length, 1);
      expect(result.issuesByCategory[ValidationCategory.math]?.length, 1);
    });

    test('summary includes counts', () {
      final result = GddValidationResult(
        isValid: false,
        issues: const [
          ValidationIssue(
            severity: ValidationSeverity.error,
            category: ValidationCategory.grid,
            code: 'E1',
            message: 'Error',
          ),
        ],
        validationDuration: const Duration(milliseconds: 10),
      );

      expect(result.summary, contains('FAILED'));
      expect(result.summary, contains('1 errors'));
    });
  });

  group('GddValidatorService - Grid Validation', () {
    test('validates minimum columns', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 2, mechanic: 'lines'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'GRID_001'), true);
    });

    test('warns about unusual column count', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 10, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'GRID_002'), true);
    });

    test('validates minimum rows', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 0, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'GRID_003'), true);
    });

    test('requires paylines for lines mechanic', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'lines'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'GRID_006'), true);
    });

    test('accepts valid grid config', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(
          rows: 3,
          columns: 5,
          mechanic: 'lines',
          paylines: 20,
        ),
        symbols: [],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      final gridErrors = result.issues
          .where((i) =>
              i.category == ValidationCategory.grid &&
              i.severity == ValidationSeverity.error)
          .toList();
      expect(gridErrors, isEmpty);
    });
  });

  group('GddValidatorService - Symbol Validation', () {
    test('requires at least one symbol', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'SYM_001'), true);
    });

    test('warns about few symbols', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: const [
          GddSymbol(id: 'a', name: 'A', tier: SymbolTier.low, payouts: {}),
          GddSymbol(id: 'b', name: 'B', tier: SymbolTier.mid, payouts: {}),
        ],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'SYM_002'), true);
    });

    test('detects duplicate symbol IDs', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: const [
          GddSymbol(id: 'dup', name: 'A', tier: SymbolTier.low, payouts: {}),
          GddSymbol(id: 'dup', name: 'B', tier: SymbolTier.mid, payouts: {}),
        ],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'SYM_005'), true);
    });

    test('suggests wild symbol if missing', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: const [
          GddSymbol(id: 'a', name: 'A', tier: SymbolTier.low, payouts: {}),
        ],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'SYM_003'), true);
    });
  });

  group('GddValidatorService - Math Model Validation', () {
    test('warns about very low RTP', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(targetRtp: 0.70),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'MATH_001'), true);
    });

    test('warns about very high RTP', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(targetRtp: 0.995),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'MATH_002'), true);
    });

    test('warns about low hit frequency', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(hitFrequency: 0.05),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'MATH_003'), true);
    });
  });

  group('GddValidatorService - Feature Validation', () {
    test('provides info when no features defined', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'FEAT_001'), true);
    });

    test('warns about free spins without initial spins', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: const [
          GddFeature(
            id: 'fs',
            name: 'Free Spins',
            type: GddFeatureType.freeSpins,
          ),
        ],
        math: const GddMathModel(),
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'FEAT_003'), true);
    });
  });

  group('GddValidatorService - Stage Validation', () {
    test('warns about non-standard stage naming', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
        customStages: ['myCustomEvent', 'another-stage'],
      );

      final result = validator.validate(gdd);
      expect(result.issues.any((i) => i.code == 'STAGE_001'), true);
    });

    test('accepts valid stage names', () {
      final gdd = GameDesignDocument(
        name: 'Test',
        version: '1.0',
        grid: const GddGridConfig(rows: 3, columns: 5, mechanic: 'ways'),
        symbols: [],
        features: [],
        math: const GddMathModel(),
        customStages: ['CUSTOM_EVENT', 'MY_STAGE_123'],
      );

      final result = validator.validate(gdd);
      final stageWarnings = result.issues
          .where((i) =>
              i.category == ValidationCategory.stages &&
              i.code == 'STAGE_001')
          .toList();
      expect(stageWarnings, isEmpty);
    });
  });
}

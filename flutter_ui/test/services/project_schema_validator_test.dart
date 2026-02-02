// Project Schema Validator Tests
//
// Comprehensive test suite for JSON schema validation:
// - Valid project passes
// - Missing required fields
// - Type mismatches
// - Range validation
// - Enum validation
// - Array length limits
// - Cross-field dependencies
// - Migration testing
// - Error message quality

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/project_schema.dart';
import 'package:fluxforge_ui/models/validation_error.dart';
import 'package:fluxforge_ui/services/project_schema_validator.dart';
import 'package:fluxforge_ui/services/project_migrator.dart';

void main() {
  group('ProjectSchemaValidator', () {
    late ProjectSchemaValidator validator;

    setUp(() {
      validator = ProjectSchemaValidator.instance;
    });

    group('Valid Projects', () {
      test('accepts minimal valid project', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test Project',
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });

      test('accepts full valid project with all sections', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Complete Project',
          'created_at': '2026-02-02T12:00:00Z',
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Audio Track 1',
                'type': 'audio',
                'volume': 1.0,
                'pan': 0.0,
                'muted': false,
                'soloed': false,
              },
            ],
            'tempo': 120.0,
          },
          'middleware': {
            'events': [
              {
                'id': 'event_1',
                'name': 'Spin Sound',
                'category': 'spin',
              },
            ],
          },
          'slot_lab': {
            'name': 'SlotLab Project',
            'symbols': [
              {
                'id': 'wild',
                'name': 'Wild Symbol',
                'emoji': '🃏',
                'type': 'wild',
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });
    });

    group('Missing Required Fields', () {
      test('fails when schema_version is missing', () {
        final project = {
          'name': 'Test Project',
        };

        final result = validator.validateProject(project);

        // schema_version defaults to 1 when missing
        expect(result.schemaVersion, equals(1));
        expect(result.needsMigration, isTrue);
      });

      test('fails when name is missing', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(result.errors.length, greaterThan(0));
        expect(
          result.errors.any((e) => e.fieldPath == 'name'),
          isTrue,
        );
      });

      test('fails when track id is missing', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {
                'name': 'Track without ID',
                'type': 'audio',
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.fieldPath.contains('tracks[0].id')),
          isTrue,
        );
      });
    });

    group('Type Validation', () {
      test('fails when volume is not a number', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Track',
                'type': 'audio',
                'volume': 'loud', // Should be a number
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) =>
              e.fieldPath.contains('volume') &&
              e.category == ValidationErrorCategory.typeMismatch),
          isTrue,
        );
      });

      test('fails when muted is not a boolean', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Track',
                'type': 'audio',
                'muted': 'yes', // Should be boolean
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.category == ValidationErrorCategory.typeMismatch),
          isTrue,
        );
      });

      test('fails when tracks is not an array', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': 'not an array',
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) =>
              e.fieldPath.contains('tracks') &&
              e.category == ValidationErrorCategory.typeMismatch),
          isTrue,
        );
      });
    });

    group('Range Validation', () {
      test('warns when volume is out of range (too high)', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Track',
                'type': 'audio',
                'volume': 10.0, // Max is 4.0
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(
          result.warnings.any((e) =>
              e.fieldPath.contains('volume') &&
              e.category == ValidationErrorCategory.outOfRange),
          isTrue,
        );
      });

      test('warns when pan is out of range', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Track',
                'type': 'audio',
                'pan': -2.0, // Valid range is -1 to 1
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(
          result.warnings.any((e) =>
              e.fieldPath.contains('pan') &&
              e.category == ValidationErrorCategory.outOfRange),
          isTrue,
        );
      });

      test('warns when tempo is out of range', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tempo': 1500.0, // Max is 999
          },
        };

        final result = validator.validateProject(project);

        expect(
          result.warnings.any((e) =>
              e.fieldPath.contains('tempo') &&
              e.category == ValidationErrorCategory.outOfRange),
          isTrue,
        );
      });
    });

    group('Enum Validation', () {
      test('fails when track type is invalid', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Track',
                'type': 'invalid_type', // Not a valid track type
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) =>
              e.fieldPath.contains('type') &&
              e.category == ValidationErrorCategory.invalidEnum),
          isTrue,
        );
      });

      test('fails when symbol type is invalid', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'slot_lab': {
            'symbols': [
              {
                'id': 'sym1',
                'name': 'Symbol',
                'emoji': '🎰',
                'type': 'not_a_symbol_type',
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.category == ValidationErrorCategory.invalidEnum),
          isTrue,
        );
      });
    });

    group('Array Length Validation', () {
      test('warns when composite events exceed limit', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'slot_lab': {
            'composite_events': List.generate(600, (i) => {'id': 'event_$i'}),
          },
        };

        final result = validator.validateProject(project);

        expect(
          result.warnings.any((e) =>
              e.fieldPath.contains('composite_events') &&
              e.category == ValidationErrorCategory.arrayLength),
          isTrue,
        );
      });

      test('info when track count is very high', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': List.generate(
              150,
              (i) => {
                'id': 'track_$i',
                'name': 'Track $i',
                'type': 'audio',
              },
            ),
          },
        };

        final result = validator.validateProject(project);

        expect(
          result.infos.any((e) => e.fieldPath.contains('tracks')),
          isTrue,
        );
      });
    });

    group('Cross-Field Validation', () {
      test('detects duplicate track IDs', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {'id': 'track_1', 'name': 'Track 1', 'type': 'audio'},
              {'id': 'track_1', 'name': 'Track 2', 'type': 'audio'}, // Duplicate!
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.message.contains('Duplicate track ID')),
          isTrue,
        );
      });

      test('detects duplicate event IDs', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'middleware': {
            'events': [
              {'id': 'event_1', 'name': 'Event 1'},
              {'id': 'event_1', 'name': 'Event 2'}, // Duplicate!
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.message.contains('Duplicate event ID')),
          isTrue,
        );
      });

      test('detects duplicate symbol IDs', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'slot_lab': {
            'symbols': [
              {'id': 'wild', 'name': 'Wild 1', 'emoji': '🃏', 'type': 'wild'},
              {'id': 'wild', 'name': 'Wild 2', 'emoji': '🎲', 'type': 'wild'}, // Duplicate!
            ],
          },
        };

        final result = validator.validateProject(project);

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.message.contains('Duplicate symbol ID')),
          isTrue,
        );
      });
    });

    group('Error Messages Quality', () {
      test('error messages include field path', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Track',
                'type': 'invalid',
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        for (final error in result.errors) {
          expect(error.fieldPath, isNotEmpty);
          expect(error.fieldPath, contains('daw.tracks'));
        }
      });

      test('error messages include suggestions', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          // Missing name
        };

        final result = validator.validateProject(project);

        expect(result.errors.isNotEmpty, isTrue);
        expect(
          result.errors.any((e) => e.suggestion != null && e.suggestion!.isNotEmpty),
          isTrue,
        );
      });

      test('severity levels are correct', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          // Missing name (error)
          'daw': {
            'tracks': [
              {
                'id': 'track_1',
                'name': 'Track',
                'type': 'audio',
                'volume': 10.0, // Out of range (warning)
              },
            ],
          },
        };

        final result = validator.validateProject(project);

        // Should have at least one error (missing name)
        expect(
          result.errors.any((e) => e.severity == ValidationSeverity.error),
          isTrue,
        );

        // Should have at least one warning (volume out of range)
        expect(
          result.warnings.any((e) => e.severity == ValidationSeverity.warning),
          isTrue,
        );
      });
    });

    group('Deprecated Fields', () {
      test('warns about deprecated slot_events', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
          'slot_events': [], // Deprecated field
        };

        final result = validator.validateProject(project);

        expect(
          result.warnings.any((e) =>
              e.category == ValidationErrorCategory.deprecated &&
              e.fieldPath.contains('slot_events')),
          isTrue,
        );
      });
    });

    group('Section Validation', () {
      test('validates DAW section independently', () {
        final dawSection = {
          'tracks': [
            {
              'id': 'track_1',
              'name': 'Valid Track',
              'type': 'audio',
            },
          ],
          'tempo': 120.0,
        };

        final result = validator.validateSection('daw', dawSection);

        expect(result.isValid, isTrue);
      });

      test('validates track independently', () {
        final track = {
          'id': 'track_1',
          'name': 'Valid Track',
          'type': 'audio',
          'volume': 1.0,
        };

        final result = validator.validateSection('track', track);

        expect(result.isValid, isTrue);
      });

      test('returns error for unknown section', () {
        final result = validator.validateSection('unknown_section', {});

        expect(result.isValid, isFalse);
        expect(result.errors.first.message, contains('Unknown section'));
      });
    });

    group('Quick Validation', () {
      test('isValid returns correct boolean', () {
        final validProject = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
        };

        final invalidProject = {
          'schema_version': kCurrentSchemaVersion,
          // Missing name
        };

        expect(validator.isValid(validProject), isTrue);
        expect(validator.isValid(invalidProject), isFalse);
      });
    });

    group('Extension Methods', () {
      test('Map extension validateAsProject works', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
        };

        final result = project.validateAsProject();

        expect(result.isValid, isTrue);
      });

      test('Map extension isValidProject works', () {
        final project = {
          'schema_version': kCurrentSchemaVersion,
          'name': 'Test',
        };

        expect(project.isValidProject, isTrue);
      });
    });
  });

  group('ProjectMigrator', () {
    late ProjectMigrator migrator;

    setUp(() {
      migrator = ProjectMigrator.instance;
    });

    group('Version Detection', () {
      test('detects schema_version field', () {
        final project = {
          'schema_version': 3,
          'name': 'Test',
        };

        expect(migrator.needsMigration(project), isTrue);
      });

      test('defaults to v1 when no version present', () {
        final project = {
          'name': 'Legacy Project',
        };

        expect(migrator.needsMigration(project), isTrue);
      });
    });

    group('Migration v1 to v2', () {
      test('adds bus hierarchy', () {
        final project = {
          'schema_version': 1,
          'name': 'Test',
        };

        final result = migrator.migrate(project, targetVersion: 2);

        expect(result.success, isTrue);
        expect(result.migratedData!.containsKey('bus_hierarchy'), isTrue);
        expect(result.toVersion, equals(2));
      });

      test('adds output_bus_id to tracks', () {
        final project = {
          'schema_version': 1,
          'name': 'Test',
          'tracks': [
            {'id': 'track_1', 'name': 'Music Track'},
            {'id': 'track_2', 'name': 'SFX Hit'},
          ],
        };

        final result = migrator.migrate(project, targetVersion: 2);

        expect(result.success, isTrue);
        final tracks = result.migratedData!['tracks'] as List;
        for (final track in tracks) {
          expect((track as Map).containsKey('output_bus_id'), isTrue);
        }
      });
    });

    group('Migration v4 to v5', () {
      test('adds stage definitions', () {
        final project = {
          'schema_version': 4,
          'name': 'Test',
        };

        final result = migrator.migrate(project, targetVersion: 5);

        expect(result.success, isTrue);
        expect(result.migratedData!.containsKey('stage_definitions'), isTrue);
        expect(result.migratedData!.containsKey('stage_audio_mappings'), isTrue);
      });

      test('migrates slot_events to stage_audio_mappings', () {
        final project = {
          'schema_version': 4,
          'name': 'Test',
          'slot_events': [
            {'type': 'spin_start', 'audio_path': 'spin.wav'},
            {'type': 'win', 'audio_path': 'win.wav'},
          ],
        };

        final result = migrator.migrate(project, targetVersion: 5);

        expect(result.success, isTrue);
        expect(result.migratedData!.containsKey('slot_events'), isFalse);
        expect(result.migratedData!.containsKey('_deprecated_slot_events'), isTrue);

        final mappings = result.migratedData!['stage_audio_mappings'] as List;
        expect(mappings.length, equals(2));
        expect(
          mappings.any((m) => (m as Map)['stage'] == 'SPIN_START'),
          isTrue,
        );
      });
    });

    group('Full Migration Path', () {
      test('migrates from v1 to current version', () {
        final project = {
          'schema_version': 1,
          'name': 'Legacy Project',
        };

        final result = migrator.migrate(project);

        expect(result.success, isTrue);
        expect(result.fromVersion, equals(1));
        expect(result.toVersion, equals(kCurrentSchemaVersion));

        // Verify all expected fields are present
        expect(result.migratedData!.containsKey('bus_hierarchy'), isTrue);
        expect(result.migratedData!.containsKey('rtpc_definitions'), isTrue);
        expect(result.migratedData!.containsKey('aux_buses'), isTrue);
        expect(result.migratedData!.containsKey('stage_definitions'), isTrue);
      });

      test('records all changes made', () {
        final project = {
          'schema_version': 1,
          'name': 'Test',
        };

        final result = migrator.migrate(project);

        expect(result.changes, isNotEmpty);
        expect(
          result.changes.any((c) => c.type == MigrationChangeType.added),
          isTrue,
        );
      });

      test('validates after migration', () {
        final project = {
          'schema_version': 1,
          'name': 'Test',
        };

        final result = migrator.migrate(project);

        expect(result.validationResult, isNotNull);
        expect(result.validationResult!.isValid, isTrue);
      });
    });

    group('Rollback Support', () {
      test('preserves original data for rollback', () {
        final project = {
          'schema_version': 1,
          'name': 'Original Name',
        };

        final result = migrator.migrate(project);

        expect(result.originalData, isNotNull);
        expect(result.originalData!['name'], equals('Original Name'));
        expect(result.originalData!['schema_version'], equals(1));
      });

      test('rollback returns original data', () {
        final project = {
          'schema_version': 1,
          'name': 'Test',
        };

        final result = migrator.migrate(project);
        final rollback = result.rollback();

        expect(rollback, isNotNull);
        expect(rollback!['schema_version'], equals(1));
        expect(rollback.containsKey('bus_hierarchy'), isFalse);
      });
    });

    group('Error Handling', () {
      test('fails gracefully for unsupported version', () {
        final project = {
          'schema_version': 0, // Too old
          'name': 'Test',
        };

        final result = migrator.migrate(project);

        expect(result.success, isFalse);
        expect(result.error, contains('too old'));
      });

      test('getMigrationPath returns correct steps', () {
        final project = {
          'schema_version': 2,
          'name': 'Test',
        };

        final path = migrator.getMigrationPath(project);

        expect(path.length, equals(kCurrentSchemaVersion - 2));
        expect(path.first, contains('v2'));
      });
    });
  });

  group('ValidationError', () {
    test('toFullMessage includes all context', () {
      final error = ValidationError.outOfRange(
        fieldPath: 'daw.tracks[0].volume',
        value: 10.0,
        min: 0,
        max: 4,
      );

      final message = error.toFullMessage();

      expect(message, contains('daw.tracks[0].volume'));
      expect(message, contains('10.0'));
      expect(message, contains('0 to 4'));
      expect(message, contains('Suggestion'));
    });

    test('factory constructors create correct categories', () {
      expect(
        ValidationError.missingField(fieldPath: 'test').category,
        equals(ValidationErrorCategory.missingField),
      );
      expect(
        ValidationError.typeMismatch(
          fieldPath: 'test',
          expected: 'string',
          actual: 'int',
        ).category,
        equals(ValidationErrorCategory.typeMismatch),
      );
      expect(
        ValidationError.invalidEnum(
          fieldPath: 'test',
          value: 'invalid',
          validValues: ['a', 'b'],
        ).category,
        equals(ValidationErrorCategory.invalidEnum),
      );
    });

    test('serialization roundtrip works', () {
      final error = ValidationError.outOfRange(
        fieldPath: 'test.field',
        value: 100,
        min: 0,
        max: 50,
      );

      final json = error.toJson();
      final restored = ValidationError.fromJson(json);

      expect(restored.fieldPath, equals(error.fieldPath));
      expect(restored.message, equals(error.message));
      expect(restored.severity, equals(error.severity));
      expect(restored.category, equals(error.category));
    });
  });

  group('ValidationResult', () {
    test('toSummary provides useful overview', () {
      final result = ValidationResult.failure(
        errors: [
          ValidationError.missingField(fieldPath: 'name'),
        ],
        warnings: [
          ValidationError.outOfRange(
            fieldPath: 'volume',
            value: 10,
            min: 0,
            max: 4,
          ),
        ],
      );

      final summary = result.toSummary();

      expect(summary, contains('failed'));
      expect(summary, contains('1 error'));
      expect(summary, contains('1 warning'));
    });

    test('getErrorsByCategory filters correctly', () {
      final result = ValidationResult.failure(
        errors: [
          ValidationError.missingField(fieldPath: 'a'),
          ValidationError.typeMismatch(
            fieldPath: 'b',
            expected: 'string',
            actual: 'int',
          ),
          ValidationError.missingField(fieldPath: 'c'),
        ],
      );

      final missing = result.getErrorsByCategory(ValidationErrorCategory.missingField);

      expect(missing.length, equals(2));
    });
  });
}

// Project Schema Validator
//
// Production-grade JSON schema validation for FluxForge project files:
// - Validates against defined schemas
// - Type checking with coercion
// - Range and enum validation
// - Cross-field dependency validation
// - Rich error reporting with suggestions
// - Auto-migration support

import '../models/project_schema.dart';
import '../models/validation_error.dart';
import 'schema_migration.dart';

/// Project schema validation service
class ProjectSchemaValidator {
  // Singleton instance
  static final ProjectSchemaValidator _instance = ProjectSchemaValidator._internal();
  static ProjectSchemaValidator get instance => _instance;
  ProjectSchemaValidator._internal();

  /// Validate a complete project JSON
  ValidationResult validateProject(Map<String, dynamic> json) {
    final errors = <ValidationError>[];
    final warnings = <ValidationError>[];
    final infos = <ValidationError>[];

    // Check schema version
    final schemaVersion = _extractSchemaVersion(json);
    final needsMigration = schemaVersion < kCurrentSchemaVersion;

    if (schemaVersion < kMinSupportedSchemaVersion) {
      errors.add(ValidationError.versionMismatch(
        found: schemaVersion,
        expected: kCurrentSchemaVersion,
        canMigrate: false,
      ));
      return ValidationResult.failure(
        errors: errors,
        schemaVersion: schemaVersion,
        needsMigration: true,
        canAutoMigrate: false,
      );
    }

    if (needsMigration) {
      warnings.add(ValidationError.versionMismatch(
        found: schemaVersion,
        expected: kCurrentSchemaVersion,
        canMigrate: true,
      ));
    }

    // Validate root schema
    _validateObject(
      json,
      ProjectSchema.rootSchema,
      '',
      errors,
      warnings,
      infos,
    );

    // Validate DAW section if present
    if (json.containsKey('daw') && json['daw'] is Map<String, dynamic>) {
      _validateObject(
        json['daw'] as Map<String, dynamic>,
        ProjectSchema.dawSchema,
        'daw',
        errors,
        warnings,
        infos,
      );

      // Validate tracks array
      if (json['daw']['tracks'] is List) {
        _validateTracksArray(
          json['daw']['tracks'] as List,
          errors,
          warnings,
          infos,
        );
      }
    }

    // Validate Middleware section if present
    if (json.containsKey('middleware') && json['middleware'] is Map<String, dynamic>) {
      _validateObject(
        json['middleware'] as Map<String, dynamic>,
        ProjectSchema.middlewareSchema,
        'middleware',
        errors,
        warnings,
        infos,
      );

      // Validate events array
      if (json['middleware']['events'] is List) {
        _validateEventsArray(
          json['middleware']['events'] as List,
          errors,
          warnings,
          infos,
        );
      }
    }

    // Validate SlotLab section if present
    if (json.containsKey('slot_lab') && json['slot_lab'] is Map<String, dynamic>) {
      _validateObject(
        json['slot_lab'] as Map<String, dynamic>,
        ProjectSchema.slotLabSchema,
        'slot_lab',
        errors,
        warnings,
        infos,
      );

      // Validate symbols array
      if (json['slot_lab']['symbols'] is List) {
        _validateSymbolsArray(
          json['slot_lab']['symbols'] as List,
          errors,
          warnings,
          infos,
        );
      }

      // Validate composite events limit
      if (json['slot_lab']['composite_events'] is List) {
        final count = (json['slot_lab']['composite_events'] as List).length;
        if (count > 500) {
          warnings.add(ValidationError.arrayLength(
            fieldPath: 'slot_lab.composite_events',
            length: count,
            maxLength: 500,
            suggestion: 'Consider archiving older events to improve performance',
          ));
        }
      }
    }

    // Check for deprecated fields
    _checkDeprecatedFields(json, warnings);

    // Return result
    final hasErrors = errors.isNotEmpty;
    return ValidationResult(
      isValid: !hasErrors,
      errors: errors,
      warnings: warnings,
      infos: infos,
      schemaVersion: schemaVersion,
      needsMigration: needsMigration,
      canAutoMigrate: true,
    );
  }

  /// Validate a specific section
  ValidationResult validateSection(String section, Map<String, dynamic> json) {
    final schema = ProjectSchema.getSchemaForSection(section);
    if (schema == null) {
      return ValidationResult.failure(
        errors: [
          ValidationError(
            fieldPath: section,
            message: "Unknown section: '$section'",
            severity: ValidationSeverity.error,
            category: ValidationErrorCategory.customRule,
          ),
        ],
      );
    }

    final errors = <ValidationError>[];
    final warnings = <ValidationError>[];
    final infos = <ValidationError>[];

    _validateObject(json, schema, section, errors, warnings, infos);

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      infos: infos,
    );
  }

  /// Validate and optionally migrate project
  ValidationResult validateAndMigrate(Map<String, dynamic> json) {
    final result = validateProject(json);

    if (result.needsMigration && result.canAutoMigrate) {
      final migrationResult = SchemaMigrationService.migrate(json);
      if (migrationResult.success) {
        // Re-validate migrated data
        return validateProject(migrationResult.migratedData!);
      }
    }

    return result;
  }

  /// Quick validation - returns true/false without details
  bool isValid(Map<String, dynamic> json) {
    return validateProject(json).isValid;
  }

  // ==========================================================================
  // PRIVATE VALIDATION METHODS
  // ==========================================================================

  int _extractSchemaVersion(Map<String, dynamic> data) {
    if (data.containsKey('schema_version')) {
      final v = data['schema_version'];
      if (v is int) return v;
      if (v is double) return v.toInt();
    }
    if (data.containsKey('version')) {
      final v = data['version'];
      if (v is int) return v;
      if (v is double) return v.toInt();
    }
    if (data.containsKey('meta') && data['meta'] is Map) {
      final meta = data['meta'] as Map;
      if (meta.containsKey('schema_version')) {
        final v = meta['schema_version'];
        if (v is int) return v;
        if (v is double) return v.toInt();
      }
    }
    return 1; // Default to v1 for legacy files
  }

  void _validateObject(
    Map<String, dynamic> json,
    Map<String, FieldConstraint> schema,
    String basePath,
    List<ValidationError> errors,
    List<ValidationError> warnings,
    List<ValidationError> infos,
  ) {
    // Check required fields
    for (final entry in schema.entries) {
      final fieldName = entry.key;
      final constraint = entry.value;
      final fieldPath = basePath.isEmpty ? fieldName : '$basePath.$fieldName';

      if (constraint.required && !json.containsKey(fieldName)) {
        errors.add(ValidationError.missingField(
          fieldPath: fieldPath,
          defaultValue: constraint.defaultValue,
          suggestion: constraint.defaultValue != null
              ? "Add '$fieldName' with default value: ${constraint.defaultValue}"
              : null,
        ));
        continue;
      }

      if (json.containsKey(fieldName)) {
        _validateField(
          json[fieldName],
          constraint,
          fieldPath,
          errors,
          warnings,
          infos,
        );

        // Check cross-field dependencies
        if (constraint.dependsOn != null) {
          final dependencyPath = basePath.isEmpty
              ? constraint.dependsOn!
              : '$basePath.${constraint.dependsOn!}';
          if (!_fieldExists(json, constraint.dependsOn!)) {
            errors.add(ValidationError.crossFieldDependency(
              fieldPath: fieldPath,
              dependsOn: dependencyPath,
              reason: 'Required when $fieldPath is present',
            ));
          }
        }
      }
    }
  }

  void _validateField(
    dynamic value,
    FieldConstraint constraint,
    String fieldPath,
    List<ValidationError> errors,
    List<ValidationError> warnings,
    List<ValidationError> infos,
  ) {
    if (value == null) {
      if (constraint.required) {
        errors.add(ValidationError.missingField(
          fieldPath: fieldPath,
          defaultValue: constraint.defaultValue,
        ));
      }
      return;
    }

    // Type validation
    if (!_validateType(value, constraint.type, fieldPath, errors)) {
      return; // Skip further validation if type is wrong
    }

    // Type-specific validation
    switch (constraint.type) {
      case FieldType.string:
        _validateString(value as String, constraint, fieldPath, errors, warnings);
        break;
      case FieldType.number:
      case FieldType.integer:
        _validateNumber(value, constraint, fieldPath, errors, warnings);
        break;
      case FieldType.array:
        _validateArray(value as List, constraint, fieldPath, errors, warnings, infos);
        break;
      case FieldType.object:
        if (constraint.properties != null && value is Map<String, dynamic>) {
          _validateObject(value, constraint.properties!, fieldPath, errors, warnings, infos);
        }
        break;
      case FieldType.boolean:
      case FieldType.any:
        // No additional validation needed
        break;
    }
  }

  bool _validateType(
    dynamic value,
    FieldType expected,
    String fieldPath,
    List<ValidationError> errors,
  ) {
    bool isValid = false;
    String actualType = value.runtimeType.toString();

    switch (expected) {
      case FieldType.string:
        isValid = value is String;
        break;
      case FieldType.number:
        isValid = value is num;
        break;
      case FieldType.integer:
        isValid = value is int || (value is double && value == value.truncateToDouble());
        break;
      case FieldType.boolean:
        isValid = value is bool;
        break;
      case FieldType.array:
        isValid = value is List;
        break;
      case FieldType.object:
        isValid = value is Map;
        break;
      case FieldType.any:
        isValid = true;
        break;
    }

    if (!isValid) {
      errors.add(ValidationError.typeMismatch(
        fieldPath: fieldPath,
        expected: expected.name,
        actual: actualType,
      ));
    }

    return isValid;
  }

  void _validateString(
    String value,
    FieldConstraint constraint,
    String fieldPath,
    List<ValidationError> errors,
    List<ValidationError> warnings,
  ) {
    // Length validation
    if (constraint.minLength != null && value.length < constraint.minLength!) {
      errors.add(ValidationError.stringLength(
        fieldPath: fieldPath,
        length: value.length,
        minLength: constraint.minLength,
      ));
    }
    if (constraint.maxLength != null && value.length > constraint.maxLength!) {
      warnings.add(ValidationError.stringLength(
        fieldPath: fieldPath,
        length: value.length,
        maxLength: constraint.maxLength,
        suggestion: 'Truncate to ${constraint.maxLength} characters',
      ));
    }

    // Enum validation
    if (constraint.enumValues != null && !constraint.enumValues!.contains(value)) {
      errors.add(ValidationError.invalidEnum(
        fieldPath: fieldPath,
        value: value,
        validValues: constraint.enumValues!,
      ));
    }
  }

  void _validateNumber(
    dynamic value,
    FieldConstraint constraint,
    String fieldPath,
    List<ValidationError> errors,
    List<ValidationError> warnings,
  ) {
    final numValue = value is num ? value : double.tryParse(value.toString());
    if (numValue == null) {
      errors.add(ValidationError.typeMismatch(
        fieldPath: fieldPath,
        expected: 'number',
        actual: value.runtimeType.toString(),
      ));
      return;
    }

    // Range validation
    if (constraint.min != null && numValue < constraint.min!) {
      warnings.add(ValidationError.outOfRange(
        fieldPath: fieldPath,
        value: numValue,
        min: constraint.min!,
        max: constraint.max ?? double.infinity,
        suggestion: 'Value will be clamped to ${constraint.min}',
      ));
    }
    if (constraint.max != null && numValue > constraint.max!) {
      warnings.add(ValidationError.outOfRange(
        fieldPath: fieldPath,
        value: numValue,
        min: constraint.min ?? double.negativeInfinity,
        max: constraint.max!,
        suggestion: 'Value will be clamped to ${constraint.max}',
      ));
    }
  }

  void _validateArray(
    List value,
    FieldConstraint constraint,
    String fieldPath,
    List<ValidationError> errors,
    List<ValidationError> warnings,
    List<ValidationError> infos,
  ) {
    // Length validation
    if (constraint.minItems != null && value.length < constraint.minItems!) {
      errors.add(ValidationError.arrayLength(
        fieldPath: fieldPath,
        length: value.length,
        minLength: constraint.minItems,
      ));
    }
    if (constraint.maxItems != null && value.length > constraint.maxItems!) {
      warnings.add(ValidationError.arrayLength(
        fieldPath: fieldPath,
        length: value.length,
        maxLength: constraint.maxItems,
        suggestion: 'Consider reducing array size for better performance',
      ));
    }

    // Validate items if item schema is defined
    if (constraint.items != null) {
      for (int i = 0; i < value.length; i++) {
        _validateField(
          value[i],
          constraint.items!,
          '$fieldPath[$i]',
          errors,
          warnings,
          infos,
        );
      }
    }
  }

  void _validateTracksArray(
    List tracks,
    List<ValidationError> errors,
    List<ValidationError> warnings,
    List<ValidationError> infos,
  ) {
    final seenIds = <String>{};

    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      if (track is! Map<String, dynamic>) continue;

      final fieldPath = 'daw.tracks[$i]';

      // Validate against schema
      _validateObject(
        track,
        ProjectSchema.trackSchema,
        fieldPath,
        errors,
        warnings,
        infos,
      );

      // Check for duplicate IDs
      final id = track['id'] as String?;
      if (id != null) {
        if (seenIds.contains(id)) {
          errors.add(ValidationError(
            fieldPath: '$fieldPath.id',
            message: "Duplicate track ID: '$id'",
            severity: ValidationSeverity.error,
            category: ValidationErrorCategory.customRule,
            suggestion: 'Ensure all track IDs are unique',
          ));
        } else {
          seenIds.add(id);
        }
      }

      // Cross-field: container type requires container ID
      if (track.containsKey('containerType') && track['containerType'] != null) {
        if (!track.containsKey('containerId') || track['containerId'] == null) {
          errors.add(ValidationError.crossFieldDependency(
            fieldPath: '$fieldPath.containerType',
            dependsOn: '$fieldPath.containerId',
            reason: 'containerType is set but containerId is missing',
          ));
        }
      }
    }

    // Performance warning for large track counts
    if (tracks.length > 128) {
      infos.add(ValidationError(
        fieldPath: 'daw.tracks',
        message: 'Large number of tracks (${tracks.length}) may impact performance',
        severity: ValidationSeverity.info,
        category: ValidationErrorCategory.customRule,
        suggestion: 'Consider using bus routing to reduce track count',
      ));
    }
  }

  void _validateEventsArray(
    List events,
    List<ValidationError> errors,
    List<ValidationError> warnings,
    List<ValidationError> infos,
  ) {
    final seenIds = <String>{};

    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      if (event is! Map<String, dynamic>) continue;

      final fieldPath = 'middleware.events[$i]';

      // Validate against schema
      _validateObject(
        event,
        ProjectSchema.middlewareEventSchema,
        fieldPath,
        errors,
        warnings,
        infos,
      );

      // Check for duplicate IDs
      final id = event['id'] as String?;
      if (id != null) {
        if (seenIds.contains(id)) {
          errors.add(ValidationError(
            fieldPath: '$fieldPath.id',
            message: "Duplicate event ID: '$id'",
            severity: ValidationSeverity.error,
            category: ValidationErrorCategory.customRule,
            suggestion: 'Ensure all event IDs are unique',
          ));
        } else {
          seenIds.add(id);
        }
      }

      // Validate actions if present
      if (event['actions'] is List) {
        final actions = event['actions'] as List;
        for (int j = 0; j < actions.length; j++) {
          if (actions[j] is Map<String, dynamic>) {
            _validateObject(
              actions[j] as Map<String, dynamic>,
              ProjectSchema.actionSchema,
              '$fieldPath.actions[$j]',
              errors,
              warnings,
              infos,
            );
          }
        }
      }
    }
  }

  void _validateSymbolsArray(
    List symbols,
    List<ValidationError> errors,
    List<ValidationError> warnings,
    List<ValidationError> infos,
  ) {
    final seenIds = <String>{};

    for (int i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      if (symbol is! Map<String, dynamic>) continue;

      final fieldPath = 'slot_lab.symbols[$i]';

      // Validate against schema
      _validateObject(
        symbol,
        ProjectSchema.symbolSchema,
        fieldPath,
        errors,
        warnings,
        infos,
      );

      // Check for duplicate IDs
      final id = symbol['id'] as String?;
      if (id != null) {
        if (seenIds.contains(id)) {
          errors.add(ValidationError(
            fieldPath: '$fieldPath.id',
            message: "Duplicate symbol ID: '$id'",
            severity: ValidationSeverity.error,
            category: ValidationErrorCategory.customRule,
            suggestion: 'Ensure all symbol IDs are unique',
          ));
        } else {
          seenIds.add(id);
        }
      }
    }
  }

  void _checkDeprecatedFields(
    Map<String, dynamic> json,
    List<ValidationError> warnings,
  ) {
    // Check for deprecated slot_events (replaced by stage_audio_mappings in v5)
    if (json.containsKey('slot_events')) {
      warnings.add(ValidationError.deprecated(
        fieldPath: 'slot_events',
        replacement: 'stage_audio_mappings',
        suggestion: 'Migrate using SchemaMigrationService.migrate()',
      ));
    }

    // Check for deprecated _deprecated_slot_events
    if (json.containsKey('_deprecated_slot_events')) {
      warnings.add(ValidationError.deprecated(
        fieldPath: '_deprecated_slot_events',
        suggestion: 'This field can be safely removed after migration verification',
      ));
    }

    // Check for old version field (replaced by schema_version)
    if (json.containsKey('version') && !json.containsKey('schema_version')) {
      warnings.add(ValidationError.deprecated(
        fieldPath: 'version',
        replacement: 'schema_version',
      ));
    }
  }

  bool _fieldExists(Map<String, dynamic> json, String fieldPath) {
    final parts = fieldPath.split('.');
    dynamic current = json;

    for (final part in parts) {
      if (current is! Map) return false;
      if (!current.containsKey(part)) return false;
      current = current[part];
    }

    return current != null;
  }
}

// =============================================================================
// VALIDATION UTILITIES
// =============================================================================

/// Extension methods for quick validation
extension MapValidationExtension on Map<String, dynamic> {
  /// Quick validate as project
  ValidationResult validateAsProject() {
    return ProjectSchemaValidator.instance.validateProject(this);
  }

  /// Quick validate a section
  ValidationResult validateSection(String section) {
    return ProjectSchemaValidator.instance.validateSection(section, this);
  }

  /// Check if valid without details
  bool get isValidProject {
    return ProjectSchemaValidator.instance.isValid(this);
  }
}

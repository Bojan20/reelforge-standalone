// Validation Error Models
//
// Rich error reporting for project schema validation with:
// - Field path tracking (e.g., 'daw.tracks[0].volume')
// - Severity levels (error, warning, info)
// - Actionable suggestions
// - Error categorization

/// Severity level for validation issues
enum ValidationSeverity {
  /// Critical - blocks loading, must fix
  error,

  /// Warning - can load but may cause issues
  warning,

  /// Informational - optimization suggestion
  info;

  String get displayName {
    switch (this) {
      case ValidationSeverity.error:
        return 'Error';
      case ValidationSeverity.warning:
        return 'Warning';
      case ValidationSeverity.info:
        return 'Info';
    }
  }

  String get emoji {
    switch (this) {
      case ValidationSeverity.error:
        return '❌';
      case ValidationSeverity.warning:
        return '⚠️';
      case ValidationSeverity.info:
        return 'ℹ️';
    }
  }
}

/// Category of validation error
enum ValidationErrorCategory {
  /// Required field is missing
  missingField,

  /// Field has wrong type
  typeMismatch,

  /// Value is out of valid range
  outOfRange,

  /// Value is not in allowed set
  invalidEnum,

  /// Array has too many/few items
  arrayLength,

  /// String is too long/short
  stringLength,

  /// Cross-field dependency violated
  crossFieldDependency,

  /// Deprecated field usage
  deprecated,

  /// Schema version mismatch
  versionMismatch,

  /// Custom validation rule failed
  customRule,
}

/// Single validation error with full context
class ValidationError {
  /// JSON path to the field (e.g., 'daw.tracks[0].volume')
  final String fieldPath;

  /// Human-readable error message
  final String message;

  /// Severity of this error
  final ValidationSeverity severity;

  /// Error category for grouping
  final ValidationErrorCategory category;

  /// Suggestion to fix the error
  final String? suggestion;

  /// Expected value/type
  final String? expected;

  /// Actual value/type found
  final String? actual;

  /// Default value that will be used (if applicable)
  final dynamic defaultValue;

  const ValidationError({
    required this.fieldPath,
    required this.message,
    required this.severity,
    required this.category,
    this.suggestion,
    this.expected,
    this.actual,
    this.defaultValue,
  });

  /// Create error for missing required field
  factory ValidationError.missingField({
    required String fieldPath,
    String? suggestion,
    dynamic defaultValue,
  }) {
    return ValidationError(
      fieldPath: fieldPath,
      message: "Required field '$fieldPath' is missing",
      severity: ValidationSeverity.error,
      category: ValidationErrorCategory.missingField,
      suggestion: suggestion ?? "Add the required field '$fieldPath' to the project file",
      defaultValue: defaultValue,
    );
  }

  /// Create error for type mismatch
  factory ValidationError.typeMismatch({
    required String fieldPath,
    required String expected,
    required String actual,
    String? suggestion,
  }) {
    return ValidationError(
      fieldPath: fieldPath,
      message: "Type mismatch at '$fieldPath': expected $expected, got $actual",
      severity: ValidationSeverity.error,
      category: ValidationErrorCategory.typeMismatch,
      expected: expected,
      actual: actual,
      suggestion: suggestion ?? "Change '$fieldPath' to type $expected",
    );
  }

  /// Create error for out of range value
  factory ValidationError.outOfRange({
    required String fieldPath,
    required num value,
    required num min,
    required num max,
    String? suggestion,
  }) {
    return ValidationError(
      fieldPath: fieldPath,
      message: "Value at '$fieldPath' is out of range: $value (valid: $min to $max)",
      severity: ValidationSeverity.warning,
      category: ValidationErrorCategory.outOfRange,
      expected: '$min to $max',
      actual: '$value',
      suggestion: suggestion ?? "Change '$fieldPath' to a value between $min and $max",
    );
  }

  /// Create error for invalid enum value
  factory ValidationError.invalidEnum({
    required String fieldPath,
    required String value,
    required List<String> validValues,
    String? suggestion,
  }) {
    final validStr = validValues.join(', ');
    return ValidationError(
      fieldPath: fieldPath,
      message: "Invalid value at '$fieldPath': '$value' (valid: $validStr)",
      severity: ValidationSeverity.error,
      category: ValidationErrorCategory.invalidEnum,
      expected: validStr,
      actual: value,
      suggestion: suggestion ?? "Change '$fieldPath' to one of: $validStr",
    );
  }

  /// Create error for array length violation
  factory ValidationError.arrayLength({
    required String fieldPath,
    required int length,
    int? minLength,
    int? maxLength,
    String? suggestion,
  }) {
    String rangeStr;
    if (minLength != null && maxLength != null) {
      rangeStr = '$minLength to $maxLength';
    } else if (minLength != null) {
      rangeStr = 'at least $minLength';
    } else {
      rangeStr = 'at most $maxLength';
    }
    return ValidationError(
      fieldPath: fieldPath,
      message: "Array at '$fieldPath' has invalid length: $length (expected $rangeStr items)",
      severity: ValidationSeverity.warning,
      category: ValidationErrorCategory.arrayLength,
      expected: rangeStr,
      actual: '$length',
      suggestion: suggestion,
    );
  }

  /// Create error for string length violation
  factory ValidationError.stringLength({
    required String fieldPath,
    required int length,
    int? minLength,
    int? maxLength,
    String? suggestion,
  }) {
    String rangeStr;
    if (minLength != null && maxLength != null) {
      rangeStr = '$minLength to $maxLength';
    } else if (minLength != null) {
      rangeStr = 'at least $minLength';
    } else {
      rangeStr = 'at most $maxLength';
    }
    return ValidationError(
      fieldPath: fieldPath,
      message: "String at '$fieldPath' has invalid length: $length characters (expected $rangeStr)",
      severity: ValidationSeverity.warning,
      category: ValidationErrorCategory.stringLength,
      expected: rangeStr,
      actual: '$length characters',
      suggestion: suggestion,
    );
  }

  /// Create error for cross-field dependency
  factory ValidationError.crossFieldDependency({
    required String fieldPath,
    required String dependsOn,
    required String reason,
    String? suggestion,
  }) {
    return ValidationError(
      fieldPath: fieldPath,
      message: "Field '$fieldPath' requires '$dependsOn': $reason",
      severity: ValidationSeverity.error,
      category: ValidationErrorCategory.crossFieldDependency,
      suggestion: suggestion ?? "Either add '$dependsOn' or remove '$fieldPath'",
    );
  }

  /// Create warning for deprecated field
  factory ValidationError.deprecated({
    required String fieldPath,
    String? replacement,
    String? suggestion,
  }) {
    final msg = replacement != null
        ? "Field '$fieldPath' is deprecated, use '$replacement' instead"
        : "Field '$fieldPath' is deprecated and will be removed in future versions";
    return ValidationError(
      fieldPath: fieldPath,
      message: msg,
      severity: ValidationSeverity.warning,
      category: ValidationErrorCategory.deprecated,
      suggestion: suggestion ?? (replacement != null ? "Replace '$fieldPath' with '$replacement'" : null),
    );
  }

  /// Create error for version mismatch
  factory ValidationError.versionMismatch({
    required int found,
    required int expected,
    bool canMigrate = true,
  }) {
    return ValidationError(
      fieldPath: 'schema_version',
      message: "Schema version mismatch: found v$found, expected v$expected",
      severity: canMigrate ? ValidationSeverity.warning : ValidationSeverity.error,
      category: ValidationErrorCategory.versionMismatch,
      expected: 'v$expected',
      actual: 'v$found',
      suggestion: canMigrate ? 'The project can be automatically migrated' : 'Manual migration required',
    );
  }

  /// Full formatted message with all context
  String toFullMessage() {
    final parts = <String>[
      '${severity.emoji} [$fieldPath] $message',
    ];
    if (expected != null || actual != null) {
      parts.add('  Expected: ${expected ?? "N/A"}, Actual: ${actual ?? "N/A"}');
    }
    if (suggestion != null) {
      parts.add('  Suggestion: $suggestion');
    }
    if (defaultValue != null) {
      parts.add('  Default: $defaultValue');
    }
    return parts.join('\n');
  }

  @override
  String toString() => '${severity.displayName}: $message at $fieldPath';

  Map<String, dynamic> toJson() => {
        'fieldPath': fieldPath,
        'message': message,
        'severity': severity.name,
        'category': category.name,
        if (suggestion != null) 'suggestion': suggestion,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };

  factory ValidationError.fromJson(Map<String, dynamic> json) {
    return ValidationError(
      fieldPath: json['fieldPath'] as String,
      message: json['message'] as String,
      severity: ValidationSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => ValidationSeverity.error,
      ),
      category: ValidationErrorCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => ValidationErrorCategory.customRule,
      ),
      suggestion: json['suggestion'] as String?,
      expected: json['expected'] as String?,
      actual: json['actual'] as String?,
      defaultValue: json['defaultValue'],
    );
  }
}

/// Result of validation operation
class ValidationResult {
  /// Whether the validation passed (no errors, may have warnings)
  final bool isValid;

  /// All validation errors found
  final List<ValidationError> errors;

  /// All validation warnings found
  final List<ValidationError> warnings;

  /// All informational messages
  final List<ValidationError> infos;

  /// Schema version found
  final int? schemaVersion;

  /// Whether migration is required
  final bool needsMigration;

  /// Whether migration can be done automatically
  final bool canAutoMigrate;

  const ValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.infos = const [],
    this.schemaVersion,
    this.needsMigration = false,
    this.canAutoMigrate = true,
  });

  /// Create a successful validation result
  factory ValidationResult.success({
    List<ValidationError> warnings = const [],
    List<ValidationError> infos = const [],
    int? schemaVersion,
  }) {
    return ValidationResult(
      isValid: true,
      warnings: warnings,
      infos: infos,
      schemaVersion: schemaVersion,
    );
  }

  /// Create a failed validation result
  factory ValidationResult.failure({
    required List<ValidationError> errors,
    List<ValidationError> warnings = const [],
    List<ValidationError> infos = const [],
    int? schemaVersion,
    bool needsMigration = false,
    bool canAutoMigrate = true,
  }) {
    return ValidationResult(
      isValid: false,
      errors: errors,
      warnings: warnings,
      infos: infos,
      schemaVersion: schemaVersion,
      needsMigration: needsMigration,
      canAutoMigrate: canAutoMigrate,
    );
  }

  /// All issues combined
  List<ValidationError> get allIssues => [...errors, ...warnings, ...infos];

  /// Count of all issues by severity
  int get errorCount => errors.length;
  int get warningCount => warnings.length;
  int get infoCount => infos.length;
  int get totalIssueCount => allIssues.length;

  /// Has any issues at all
  bool get hasIssues => allIssues.isNotEmpty;

  /// Get errors by category
  List<ValidationError> getErrorsByCategory(ValidationErrorCategory category) {
    return errors.where((e) => e.category == category).toList();
  }

  /// Summary string
  String toSummary() {
    if (isValid && !hasIssues) {
      return '✅ Validation passed with no issues';
    }
    final parts = <String>[];
    if (!isValid) {
      parts.add('❌ Validation failed');
    } else {
      parts.add('✅ Validation passed');
    }
    if (errorCount > 0) parts.add('$errorCount error(s)');
    if (warningCount > 0) parts.add('$warningCount warning(s)');
    if (infoCount > 0) parts.add('$infoCount info(s)');
    if (needsMigration) {
      parts.add(canAutoMigrate ? '(auto-migration available)' : '(manual migration required)');
    }
    return parts.join(', ');
  }

  /// Full report with all errors
  String toFullReport() {
    final lines = <String>[toSummary(), ''];

    if (errors.isNotEmpty) {
      lines.add('ERRORS:');
      for (final e in errors) {
        lines.add(e.toFullMessage());
        lines.add('');
      }
    }

    if (warnings.isNotEmpty) {
      lines.add('WARNINGS:');
      for (final w in warnings) {
        lines.add(w.toFullMessage());
        lines.add('');
      }
    }

    if (infos.isNotEmpty) {
      lines.add('INFO:');
      for (final i in infos) {
        lines.add(i.toFullMessage());
        lines.add('');
      }
    }

    return lines.join('\n');
  }

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        'errors': errors.map((e) => e.toJson()).toList(),
        'warnings': warnings.map((e) => e.toJson()).toList(),
        'infos': infos.map((e) => e.toJson()).toList(),
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        'needsMigration': needsMigration,
        'canAutoMigrate': canAutoMigrate,
      };
}

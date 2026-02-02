// gdd_validator_service.dart — GDD Validation
import 'package:flutter/foundation.dart';

enum GddValidationSeverity { error, warning, info }

class GddValidationIssue {
  final GddValidationSeverity severity;
  final String message;
  final String? field;
  const GddValidationIssue({required this.severity, required this.message, this.field});
}

class GddValidatorService extends ChangeNotifier {
  static final instance = GddValidatorService._();
  GddValidatorService._();
  
  List<GddValidationIssue> validateGdd(Map<String, dynamic> gdd) {
    final issues = <GddValidationIssue>[];
    
    if (!gdd.containsKey('name')) issues.add(const GddValidationIssue(severity: GddValidationSeverity.error, message: 'Missing required field: name', field: 'name'));
    if (!gdd.containsKey('grid')) issues.add(const GddValidationIssue(severity: GddValidationSeverity.error, message: 'Missing grid configuration', field: 'grid'));
    if (!gdd.containsKey('symbols')) issues.add(const GddValidationIssue(severity: GddValidationSeverity.error, message: 'Missing symbols array', field: 'symbols'));
    
    final symbols = gdd['symbols'] as List?;
    if (symbols != null && symbols.isEmpty) {
      issues.add(const GddValidationIssue(severity: GddValidationSeverity.warning, message: 'No symbols defined', field: 'symbols'));
    }
    
    return issues;
  }
  
  bool isValid(Map<String, dynamic> gdd) => validateGdd(gdd).where((i) => i.severity == GddValidationSeverity.error).isEmpty;
}

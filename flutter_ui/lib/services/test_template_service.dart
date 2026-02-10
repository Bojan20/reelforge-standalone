/// P0 WF-08: Test Template Service (2026-01-30)
///
/// Manages test template execution, recording, and validation.
/// Enables systematic QA testing of slot audio scenarios.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/test_template.dart';
import 'event_registry.dart';

/// Result of template execution
class TestTemplateResult {
  final String templateId;
  final DateTime startTime;
  final DateTime endTime;
  final int actionCount;
  final int successCount;
  final int failureCount;
  final List<String> errors;
  final Map<String, dynamic> actualResults;

  const TestTemplateResult({
    required this.templateId,
    required this.startTime,
    required this.endTime,
    required this.actionCount,
    required this.successCount,
    required this.failureCount,
    required this.errors,
    required this.actualResults,
  });

  Duration get duration => endTime.difference(startTime);
  bool get passed => failureCount == 0;
  double get successRate => actionCount > 0 ? successCount / actionCount : 0.0;

  Map<String, dynamic> toJson() => {
    'templateId': templateId,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'actionCount': actionCount,
    'successCount': successCount,
    'failureCount': failureCount,
    'errors': errors,
    'actualResults': actualResults,
    'durationMs': duration.inMilliseconds,
    'passed': passed,
    'successRate': successRate,
  };

  factory TestTemplateResult.fromJson(Map<String, dynamic> json) {
    return TestTemplateResult(
      templateId: json['templateId'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      actionCount: json['actionCount'] as int,
      successCount: json['successCount'] as int,
      failureCount: json['failureCount'] as int,
      errors: (json['errors'] as List).cast<String>(),
      actualResults: json['actualResults'] as Map<String, dynamic>,
    );
  }
}

/// Test Template Service — Singleton for template execution
class TestTemplateService extends ChangeNotifier {
  static final TestTemplateService instance = TestTemplateService._();
  TestTemplateService._();

  // Custom templates (user-created)
  final List<TestTemplate> _customTemplates = [];

  // Execution state
  bool _isExecuting = false;
  double _progress = 0.0;
  String? _currentAction;

  // Results history
  final List<TestTemplateResult> _resultHistory = [];
  static const int _maxHistorySize = 50;

  // Getters
  bool get isExecuting => _isExecuting;
  double get progress => _progress;
  String? get currentAction => _currentAction;
  List<TestTemplate> get customTemplates => List.unmodifiable(_customTemplates);
  List<TestTemplateResult> get resultHistory => List.unmodifiable(_resultHistory);

  /// Get all templates (built-in + custom)
  List<TestTemplate> getAllTemplates() {
    return [...BuiltInTestTemplates.getAll(), ..._customTemplates];
  }

  /// Get templates by category
  List<TestTemplate> getTemplatesByCategory(TestTemplateCategory category) {
    return getAllTemplates().where((t) => t.category == category).toList();
  }

  /// Add custom template
  void addCustomTemplate(TestTemplate template) {
    _customTemplates.add(template);
    notifyListeners();
  }

  /// Remove custom template
  void removeCustomTemplate(String id) {
    _customTemplates.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  /// Execute a test template
  Future<TestTemplateResult> executeTemplate(
    TestTemplate template,
    EventRegistry eventRegistry,
  ) async {
    if (_isExecuting) {
      throw StateError('Template execution already in progress');
    }

    _isExecuting = true;
    _progress = 0.0;
    _currentAction = null;
    notifyListeners();

    final startTime = DateTime.now();
    int successCount = 0;
    int failureCount = 0;
    final List<String> errors = [];
    final Map<String, dynamic> actualResults = {};

    try {
      for (int i = 0; i < template.actions.length; i++) {
        final action = template.actions[i];
        _currentAction = '${action.stage} (+${action.delayMs}ms)';
        _progress = (i + 1) / template.actions.length;
        notifyListeners();

        // Wait for delay
        if (action.delayMs > 0) {
          await Future.delayed(Duration(milliseconds: action.delayMs));
        }

        // Trigger stage
        try {
          await eventRegistry.triggerStage(action.stage, context: action.context);
          successCount++;
        } catch (e) {
          failureCount++;
          errors.add('${action.stage}: $e');
        }
      }

      // Collect actual results (can be extended with metrics collection)
      actualResults['actionCount'] = template.actions.length;
      actualResults['executionTimeMs'] = DateTime.now().difference(startTime).inMilliseconds;

    } finally {
      _isExecuting = false;
      _progress = 1.0;
      _currentAction = null;
      notifyListeners();
    }

    final result = TestTemplateResult(
      templateId: template.id,
      startTime: startTime,
      endTime: DateTime.now(),
      actionCount: template.actions.length,
      successCount: successCount,
      failureCount: failureCount,
      errors: errors,
      actualResults: actualResults,
    );

    // Add to history
    _resultHistory.insert(0, result);
    if (_resultHistory.length > _maxHistorySize) {
      _resultHistory.removeLast();
    }

    return result;
  }

  /// Stop current execution
  void stopExecution() {
    if (_isExecuting) {
      _isExecuting = false;
      _currentAction = null;
      _progress = 0.0;
      notifyListeners();
    }
  }

  /// Export custom templates to JSON file
  Future<void> exportCustomTemplates(String filePath) async {
    final json = jsonEncode(_customTemplates.map((t) => t.toJson()).toList());
    final file = File(filePath);
    await file.writeAsString(json);
  }

  /// Import custom templates from JSON file
  Future<void> importCustomTemplates(String filePath) async {
    final file = File(filePath);
    final json = await file.readAsString();
    final List<dynamic> data = jsonDecode(json);

    for (final item in data) {
      final template = TestTemplate.fromJson(item as Map<String, dynamic>);
      // Check for duplicate IDs
      if (!_customTemplates.any((t) => t.id == template.id)) {
        _customTemplates.add(template);
      }
    }

    notifyListeners();
  }

  /// Clear all custom templates
  void clearCustomTemplates() {
    _customTemplates.clear();
    notifyListeners();
  }

  /// Clear result history
  void clearHistory() {
    _resultHistory.clear();
    notifyListeners();
  }

  /// Get latest result for a template
  TestTemplateResult? getLatestResult(String templateId) {
    try {
      return _resultHistory.firstWhere((r) => r.templateId == templateId);
    } catch (_) {
      return null;
    }
  }

  /// Export result history to JSON
  Future<void> exportResultHistory(String filePath) async {
    final json = jsonEncode(_resultHistory.map((r) => r.toJson()).toList());
    final file = File(filePath);
    await file.writeAsString(json);
  }
}

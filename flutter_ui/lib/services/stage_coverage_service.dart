/// P0 WF-10: Stage Coverage Tracking Service (2026-01-30)
///
/// Tracks which stages have been tested/triggered during development.
/// Provides coverage metrics for QA validation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'stage_configuration_service.dart';

/// Coverage status for a single stage
enum CoverageStatus {
  untested,   // Never triggered
  tested,     // Triggered at least once
  verified,   // Manually marked as verified
}

/// Stage coverage entry
class StageCoverageEntry {
  final String stage;
  final CoverageStatus status;
  final int triggerCount;
  final DateTime? lastTriggered;
  final List<DateTime> triggerHistory;

  const StageCoverageEntry({
    required this.stage,
    required this.status,
    this.triggerCount = 0,
    this.lastTriggered,
    this.triggerHistory = const [],
  });

  StageCoverageEntry copyWith({
    String? stage,
    CoverageStatus? status,
    int? triggerCount,
    DateTime? lastTriggered,
    List<DateTime>? triggerHistory,
  }) {
    return StageCoverageEntry(
      stage: stage ?? this.stage,
      status: status ?? this.status,
      triggerCount: triggerCount ?? this.triggerCount,
      lastTriggered: lastTriggered ?? this.lastTriggered,
      triggerHistory: triggerHistory ?? this.triggerHistory,
    );
  }

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'status': status.name,
    'triggerCount': triggerCount,
    'lastTriggered': lastTriggered?.toIso8601String(),
    'triggerHistory': triggerHistory.map((t) => t.toIso8601String()).toList(),
  };

  factory StageCoverageEntry.fromJson(Map<String, dynamic> json) {
    return StageCoverageEntry(
      stage: json['stage'] as String,
      status: CoverageStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => CoverageStatus.untested,
      ),
      triggerCount: json['triggerCount'] as int? ?? 0,
      lastTriggered: json['lastTriggered'] != null
          ? DateTime.parse(json['lastTriggered'] as String)
          : null,
      triggerHistory: (json['triggerHistory'] as List?)
          ?.map((t) => DateTime.parse(t as String))
          .toList() ?? [],
    );
  }
}

/// Coverage statistics
class CoverageStats {
  final int totalStages;
  final int testedStages;
  final int verifiedStages;
  final int untestedStages;

  const CoverageStats({
    required this.totalStages,
    required this.testedStages,
    required this.verifiedStages,
    required this.untestedStages,
  });

  double get coverage => totalStages > 0 ? testedStages / totalStages : 0.0;
  double get verifiedCoverage => totalStages > 0 ? verifiedStages / totalStages : 0.0;

  Map<String, dynamic> toJson() => {
    'totalStages': totalStages,
    'testedStages': testedStages,
    'verifiedStages': verifiedStages,
    'untestedStages': untestedStages,
    'coverage': coverage,
    'verifiedCoverage': verifiedCoverage,
  };
}

/// Stage Coverage Tracking Service — Singleton
class StageCoverageService extends ChangeNotifier {
  static final StageCoverageService instance = StageCoverageService._();
  StageCoverageService._();

  // Coverage data
  final Map<String, StageCoverageEntry> _coverage = {};

  // Recording state
  bool _isRecording = true;
  static const int _maxHistoryPerStage = 100;

  // Getters
  bool get isRecording => _isRecording;
  Map<String, StageCoverageEntry> get coverage => Map.unmodifiable(_coverage);

  /// Initialize coverage tracking for all known stages
  void initialize() {
    final allStages = StageConfigurationService.instance.getAllStages();

    for (final stageDef in allStages) {
      if (!_coverage.containsKey(stageDef.name)) {
        _coverage[stageDef.name] = StageCoverageEntry(
          stage: stageDef.name,
          status: CoverageStatus.untested,
        );
      }
    }

    debugPrint('[StageCoverageService] Initialized with ${_coverage.length} stages');
    notifyListeners();
  }

  /// Record a stage trigger
  void recordTrigger(String stage) {
    if (!_isRecording) return;

    final normalized = stage.toUpperCase().trim();
    final current = _coverage[normalized];

    if (current == null) {
      // Unknown stage - add it
      _coverage[normalized] = StageCoverageEntry(
        stage: normalized,
        status: CoverageStatus.tested,
        triggerCount: 1,
        lastTriggered: DateTime.now(),
        triggerHistory: [DateTime.now()],
      );
    } else {
      // Update existing
      final newHistory = [...current.triggerHistory, DateTime.now()];
      if (newHistory.length > _maxHistoryPerStage) {
        newHistory.removeAt(0);
      }

      _coverage[normalized] = current.copyWith(
        status: current.status == CoverageStatus.untested
            ? CoverageStatus.tested
            : current.status,
        triggerCount: current.triggerCount + 1,
        lastTriggered: DateTime.now(),
        triggerHistory: newHistory,
      );
    }

    notifyListeners();
  }

  /// Mark a stage as verified
  void markVerified(String stage) {
    final normalized = stage.toUpperCase().trim();
    final current = _coverage[normalized];

    if (current != null) {
      _coverage[normalized] = current.copyWith(status: CoverageStatus.verified);
      notifyListeners();
    }
  }

  /// Mark a stage as untested
  void markUntested(String stage) {
    final normalized = stage.toUpperCase().trim();
    final current = _coverage[normalized];

    if (current != null) {
      _coverage[normalized] = current.copyWith(status: CoverageStatus.untested);
      notifyListeners();
    }
  }

  /// Toggle recording
  void setRecording(bool enabled) {
    _isRecording = enabled;
    debugPrint('[StageCoverageService] Recording ${enabled ? 'enabled' : 'disabled'}');
    notifyListeners();
  }

  /// Get coverage statistics
  CoverageStats getStats() {
    int tested = 0;
    int verified = 0;
    int untested = 0;

    for (final entry in _coverage.values) {
      switch (entry.status) {
        case CoverageStatus.tested:
          tested++;
          break;
        case CoverageStatus.verified:
          verified++;
          break;
        case CoverageStatus.untested:
          untested++;
          break;
      }
    }

    return CoverageStats(
      totalStages: _coverage.length,
      testedStages: tested,
      verifiedStages: verified,
      untestedStages: untested,
    );
  }

  /// Get untested stages
  List<String> getUntestedStages() {
    return _coverage.values
        .where((e) => e.status == CoverageStatus.untested)
        .map((e) => e.stage)
        .toList()..sort();
  }

  /// Get tested stages
  List<String> getTestedStages() {
    return _coverage.values
        .where((e) => e.status == CoverageStatus.tested)
        .map((e) => e.stage)
        .toList()..sort();
  }

  /// Get verified stages
  List<String> getVerifiedStages() {
    return _coverage.values
        .where((e) => e.status == CoverageStatus.verified)
        .map((e) => e.stage)
        .toList()..sort();
  }

  /// Get most frequently triggered stages
  List<StageCoverageEntry> getMostTriggered({int limit = 10}) {
    final sorted = _coverage.values.toList()
      ..sort((a, b) => b.triggerCount.compareTo(a.triggerCount));
    return sorted.take(limit).toList();
  }

  /// Get least frequently triggered stages
  List<StageCoverageEntry> getLeastTriggered({int limit = 10}) {
    final sorted = _coverage.values.toList()
      ..sort((a, b) => a.triggerCount.compareTo(b.triggerCount));
    return sorted.take(limit).toList();
  }

  /// Reset all coverage data
  void reset() {
    for (final key in _coverage.keys) {
      _coverage[key] = StageCoverageEntry(
        stage: key,
        status: CoverageStatus.untested,
      );
    }
    debugPrint('[StageCoverageService] Coverage data reset');
    notifyListeners();
  }

  /// Export coverage to JSON file
  Future<void> exportToFile(String filePath) async {
    final data = {
      'timestamp': DateTime.now().toIso8601String(),
      'stats': getStats().toJson(),
      'coverage': _coverage.values.map((e) => e.toJson()).toList(),
    };

    final json = const JsonEncoder.withIndent('  ').convert(data);
    final file = File(filePath);
    await file.writeAsString(json);
  }

  /// Import coverage from JSON file
  Future<void> importFromFile(String filePath) async {
    final file = File(filePath);
    final json = await file.readAsString();
    final data = jsonDecode(json) as Map<String, dynamic>;

    _coverage.clear();
    final coverageList = data['coverage'] as List;
    for (final item in coverageList) {
      final entry = StageCoverageEntry.fromJson(item as Map<String, dynamic>);
      _coverage[entry.stage] = entry;
    }

    debugPrint('[StageCoverageService] Imported coverage for ${_coverage.length} stages');
    notifyListeners();
  }

  /// Export untested stages to text file
  Future<void> exportUntestedToFile(String filePath) async {
    final untested = getUntestedStages();
    final file = File(filePath);
    await file.writeAsString(untested.join('\n'));
  }
}

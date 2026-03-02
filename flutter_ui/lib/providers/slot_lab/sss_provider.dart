import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../src/rust/native_ffi.dart';

/// Risk level for config changes.
enum SssRiskLevel {
  none,
  low,
  medium,
  high,
  critical;

  String get label => switch (this) {
    none => 'None',
    low => 'Low',
    medium => 'Medium',
    high => 'High',
    critical => 'Critical',
  };

  int get color => switch (this) {
    none => 0xFF4CAF50,
    low => 0xFF8BC34A,
    medium => 0xFFFF9800,
    high => 0xFFF44336,
    critical => 0xFF9C27B0,
  };
}

/// Trend direction for drift metrics.
enum SssTrendDirection {
  stable,
  rising,
  falling,
  oscillating;

  String get label => switch (this) {
    stable => 'Stable',
    rising => 'Rising',
    falling => 'Falling',
    oscillating => 'Oscillating',
  };

  static SssTrendDirection fromString(String s) => switch (s) {
    'Stable' => stable,
    'Rising' => rising,
    'Falling' => falling,
    'Oscillating' => oscillating,
    _ => stable,
  };
}

/// Config diff entry.
class ConfigDiffEntry {
  final String key;
  final String diffType;
  final String? oldValue;
  final String? newValue;
  final String riskLevel;

  const ConfigDiffEntry({
    required this.key,
    required this.diffType,
    this.oldValue,
    this.newValue,
    required this.riskLevel,
  });

  factory ConfigDiffEntry.fromJson(Map<String, dynamic> json) {
    return ConfigDiffEntry(
      key: json['key'] as String? ?? '',
      diffType: json['diff_type'] as String? ?? 'Modified',
      oldValue: json['old_value'] as String?,
      newValue: json['new_value'] as String?,
      riskLevel: json['risk_level'] as String? ?? 'None',
    );
  }

  SssRiskLevel get risk => switch (riskLevel) {
    'Low' => SssRiskLevel.low,
    'Medium' => SssRiskLevel.medium,
    'High' => SssRiskLevel.high,
    'Critical' => SssRiskLevel.critical,
    _ => SssRiskLevel.none,
  };
}

/// Drift metric from burn test.
class DriftMetric {
  final String name;
  final double initialValue;
  final double finalValue;
  final double peakValue;
  final double minValue;
  final double meanValue;
  final double driftPct;
  final SssTrendDirection trend;
  final List<double> samples;

  const DriftMetric({
    required this.name,
    required this.initialValue,
    required this.finalValue,
    required this.peakValue,
    required this.minValue,
    required this.meanValue,
    required this.driftPct,
    required this.trend,
    required this.samples,
  });

  factory DriftMetric.fromJson(Map<String, dynamic> json) {
    return DriftMetric(
      name: json['name'] as String? ?? '',
      initialValue: (json['initial_value'] as num?)?.toDouble() ?? 0.0,
      finalValue: (json['final_value'] as num?)?.toDouble() ?? 0.0,
      peakValue: (json['peak_value'] as num?)?.toDouble() ?? 0.0,
      minValue: (json['min_value'] as num?)?.toDouble() ?? 0.0,
      meanValue: (json['mean_value'] as num?)?.toDouble() ?? 0.0,
      driftPct: (json['drift_pct'] as num?)?.toDouble() ?? 0.0,
      trend: SssTrendDirection.fromString(json['trend'] as String? ?? 'Stable'),
      samples: (json['samples'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList() ?? [],
    );
  }
}

/// SSS Project info.
class SssProjectInfo {
  final String id;
  final String name;
  final bool certified;
  final String configHash;

  const SssProjectInfo({
    required this.id,
    required this.name,
    required this.certified,
    required this.configHash,
  });

  factory SssProjectInfo.fromJson(Map<String, dynamic> json) {
    return SssProjectInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      certified: json['certified'] as bool? ?? false,
      configHash: json['config_hash'] as String? ?? '',
    );
  }
}

/// Regression scenario result.
class RegressionScenarioResult {
  final String scenario;
  final bool passed;
  final bool deterministic;
  final String hash;

  const RegressionScenarioResult({
    required this.scenario,
    required this.passed,
    required this.deterministic,
    required this.hash,
  });

  factory RegressionScenarioResult.fromJson(Map<String, dynamic> json) {
    return RegressionScenarioResult(
      scenario: json['scenario'] as String? ?? '',
      passed: json['passed'] as bool? ?? false,
      deterministic: json['deterministic'] as bool? ?? false,
      hash: json['hash'] as String? ?? '',
    );
  }
}

/// Provider for the SSS (Scale & Stability Suite).
///
/// Manages multi-project isolation, config diff, auto regression,
/// and 10,000-spin burn test.
/// Register as GetIt singleton (Layer 7).
class SssProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // Project state
  List<SssProjectInfo> _projects = [];
  SssProjectInfo? _activeProject;

  // Diff state
  List<ConfigDiffEntry> _lastDiff = [];
  bool _regressionRequired = false;

  // Regression state
  bool _regressionInitialized = false;
  bool _regressionRunning = false;
  bool? _regressionPassed;
  double _regressionPassRate = 0.0;
  List<RegressionScenarioResult> _regressionResults = [];

  // Burn test state
  bool _burnTestInitialized = false;
  bool _burnTestRunning = false;
  bool? _burnTestPassed;
  bool? _burnTestDeterministic;
  Map<String, DriftMetric> _burnTestMetrics = {};
  int _burnTestTotalSpins = 0;
  String _burnTestHash = '';
  int _burnTestDurationMs = 0;

  // Getters
  List<SssProjectInfo> get projects => _projects;
  SssProjectInfo? get activeProject => _activeProject;
  List<ConfigDiffEntry> get lastDiff => _lastDiff;
  bool get regressionRequired => _regressionRequired;
  bool get regressionInitialized => _regressionInitialized;
  bool get regressionRunning => _regressionRunning;
  bool? get regressionPassed => _regressionPassed;
  double get regressionPassRate => _regressionPassRate;
  List<RegressionScenarioResult> get regressionResults => _regressionResults;
  bool get burnTestInitialized => _burnTestInitialized;
  bool get burnTestRunning => _burnTestRunning;
  bool? get burnTestPassed => _burnTestPassed;
  bool? get burnTestDeterministic => _burnTestDeterministic;
  Map<String, DriftMetric> get burnTestMetrics => _burnTestMetrics;
  int get burnTestTotalSpins => _burnTestTotalSpins;
  String get burnTestHash => _burnTestHash;
  int get burnTestDurationMs => _burnTestDurationMs;

  SssProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  // ─── Project Isolation ───

  /// Create a new isolated project.
  bool createProject(String name) {
    final ok = _ffi.sssCreateProject(name);
    if (ok) refreshProjects();
    return ok;
  }

  /// Switch active project.
  bool switchProject(String id) {
    final ok = _ffi.sssSwitchProject(id);
    if (ok) refreshProjects();
    return ok;
  }

  /// Remove a project.
  bool removeProject(String id) {
    final ok = _ffi.sssRemoveProject(id);
    if (ok) refreshProjects();
    return ok;
  }

  /// Refresh projects list from engine.
  void refreshProjects() {
    final json = _ffi.sssListProjectsJson();
    if (json != null) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _projects = list.map((e) => SssProjectInfo.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        assert(() { debugPrint('[SSS] Failed to parse projects JSON: $e'); return true; }());
      }
    }

    final activeJson = _ffi.sssActiveProjectJson();
    if (activeJson != null) {
      try {
        final data = jsonDecode(activeJson) as Map<String, dynamic>;
        _activeProject = SssProjectInfo(
          id: data['project_id'] as String? ?? '',
          name: data['project_name'] as String? ?? '',
          certified: data['certification_chain'] != null,
          configHash: data['config_hash'] as String? ?? '',
        );
      } catch (_) {
        _activeProject = null;
      }
    } else {
      _activeProject = null;
    }
    notifyListeners();
  }

  // ─── Config Diff ───

  /// Compute diff between two configs (JSON objects).
  void computeDiff(Map<String, String> oldConfig, Map<String, String> newConfig) {
    final oldJson = jsonEncode(oldConfig);
    final newJson = jsonEncode(newConfig);

    final diffStr = _ffi.sssConfigDiff(oldJson, newJson);
    if (diffStr != null) {
      try {
        final data = jsonDecode(diffStr);
        if (data is Map<String, dynamic>) {
          final entries = data['entries'] as List<dynamic>? ?? [];
          _lastDiff = entries.map((e) => ConfigDiffEntry.fromJson(e as Map<String, dynamic>)).toList();
        }
      } catch (_) {
        _lastDiff = [];
      }
    }

    final regResult = _ffi.sssRequiresRegression(oldJson, newJson);
    _regressionRequired = regResult == 1;

    notifyListeners();
  }

  // ─── Auto Regression ───

  /// Initialize regression engine with default config.
  bool initRegression() {
    final ok = _ffi.sssRegressionInit();
    if (ok) _regressionInitialized = true;
    notifyListeners();
    return ok;
  }

  /// Initialize regression with custom config.
  bool initRegressionCustom({int sessionCount = 5, int spinsPerSession = 100}) {
    final ok = _ffi.sssRegressionInitCustom(sessionCount, spinsPerSession);
    if (ok) _regressionInitialized = true;
    notifyListeners();
    return ok;
  }

  /// Run regression suite.
  bool runRegression() {
    if (!_regressionInitialized) return false;
    _regressionRunning = true;
    _regressionPassed = null;
    notifyListeners();

    final result = _ffi.sssRegressionRun();
    _regressionRunning = false;
    _regressionPassed = result == 1;
    _regressionPassRate = _ffi.sssRegressionPassRate();

    // Parse results
    final json = _ffi.sssRegressionResultJson();
    if (json != null) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final scenarios = data['scenario_results'] as List<dynamic>? ?? [];
        _regressionResults = scenarios
            .map((s) => RegressionScenarioResult.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (e) {
        assert(() { debugPrint('[SSS] Failed to parse regression results: $e'); return true; }());
      }
    }

    notifyListeners();
    return _regressionPassed ?? false;
  }

  // ─── Burn Test ───

  /// Initialize burn test with default config (10,000 spins).
  bool initBurnTest() {
    final ok = _ffi.sssBurnTestInit();
    if (ok) _burnTestInitialized = true;
    notifyListeners();
    return ok;
  }

  /// Initialize burn test with custom config.
  bool initBurnTestCustom({int totalSpins = 10000, int sampleInterval = 100}) {
    final ok = _ffi.sssBurnTestInitCustom(totalSpins, sampleInterval);
    if (ok) _burnTestInitialized = true;
    notifyListeners();
    return ok;
  }

  /// Run burn test.
  bool runBurnTest() {
    if (!_burnTestInitialized) return false;
    _burnTestRunning = true;
    _burnTestPassed = null;
    notifyListeners();

    final result = _ffi.sssBurnTestRun();
    _burnTestRunning = false;
    _burnTestPassed = result == 1;

    final detResult = _ffi.sssBurnTestDeterministic();
    _burnTestDeterministic = detResult == 1;

    // Parse metrics
    final json = _ffi.sssBurnTestResultJson();
    if (json != null) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _burnTestTotalSpins = (data['total_spins'] as num?)?.toInt() ?? 0;
        _burnTestHash = data['hash'] as String? ?? '';
        _burnTestDurationMs = (data['duration_ms'] as num?)?.toInt() ?? 0;

        final metrics = data['metrics'] as Map<String, dynamic>? ?? {};
        _burnTestMetrics = {};
        for (final entry in metrics.entries) {
          if (entry.value is Map<String, dynamic>) {
            _burnTestMetrics[entry.key] = DriftMetric.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      } catch (e) {
        assert(() { debugPrint('[SSS] Failed to parse burn test metrics: $e'); return true; }());
      }
    }

    notifyListeners();
    return _burnTestPassed ?? false;
  }
}

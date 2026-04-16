import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// RGAI™ Provider — Responsible Gaming Audio Intelligence.
///
/// Bridges rf-rgai Rust crate to Flutter UI via FFI.
/// Manages jurisdiction selection, asset/session analysis,
/// export gate checks, and compliance reporting.
///
/// Register as GetIt singleton.
class RgaiFfiProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  bool _initialized = false;
  List<String> _activeJurisdictions = const ['UKGC', 'MGA'];
  List<Map<String, dynamic>> _availableJurisdictions = const [];

  // Last analysis results (cached for UI)
  Map<String, dynamic>? _lastAssetAnalysis;
  Map<String, dynamic>? _lastSessionAnalysis;
  Map<String, dynamic>? _lastExportGate;
  Map<String, dynamic>? _lastReport;
  Map<String, dynamic>? _lastRemediation;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get initialized => _initialized;
  List<String> get activeJurisdictions => _activeJurisdictions;
  List<Map<String, dynamic>> get availableJurisdictions => _availableJurisdictions;
  Map<String, dynamic>? get lastAssetAnalysis => _lastAssetAnalysis;
  Map<String, dynamic>? get lastSessionAnalysis => _lastSessionAnalysis;
  Map<String, dynamic>? get lastExportGate => _lastExportGate;
  Map<String, dynamic>? get lastReport => _lastReport;
  Map<String, dynamic>? get lastRemediation => _lastRemediation;

  /// Is export currently approved?
  bool get exportApproved {
    final gate = _lastExportGate;
    if (gate == null) return false;
    final decision = gate['decision'] as String?;
    return decision == 'Approved';
  }

  /// Number of critical violations in last gate check.
  int get criticalViolationCount {
    final gate = _lastExportGate;
    if (gate == null) return 0;
    return (gate['critical_count'] as int?) ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  RgaiFfiProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize RGAI with target jurisdictions.
  void init({List<String>? jurisdictions}) {
    final codes = jurisdictions ?? ['UKGC', 'MGA'];
    final json = jsonEncode(codes);
    final result = _ffi.rgaiInit(jurisdictionsJson: json);
    if (result == 0) {
      _activeJurisdictions = List.unmodifiable(codes);
      _initialized = true;
      _loadJurisdictions();
      notifyListeners();
    }
  }

  /// Set active jurisdictions and reinitialize.
  void setJurisdictions(List<String> codes) {
    init(jurisdictions: codes);
  }

  void _loadJurisdictions() {
    final json = _ffi.rgaiJurisdictions();
    if (json != null) {
      final list = jsonDecode(json) as List;
      _availableJurisdictions = list.cast<Map<String, dynamic>>();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyze a single audio asset.
  Map<String, dynamic>? analyzeAsset(Map<String, dynamic> assetProfile) {
    final json = _ffi.rgaiAnalyzeAsset(jsonEncode(assetProfile));
    if (json != null) {
      _lastAssetAnalysis = jsonDecode(json) as Map<String, dynamic>;
      notifyListeners();
      return _lastAssetAnalysis;
    }
    return null;
  }

  /// Analyze a full game audio session.
  Map<String, dynamic>? analyzeSession(Map<String, dynamic> session) {
    final json = _ffi.rgaiAnalyzeSession(jsonEncode(session));
    if (json != null) {
      _lastSessionAnalysis = jsonDecode(json) as Map<String, dynamic>;
      notifyListeners();
      return _lastSessionAnalysis;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT GATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if session passes export gate.
  Map<String, dynamic>? checkExportGate(Map<String, dynamic> session) {
    final json = _ffi.rgaiExportGate(jsonEncode(session));
    if (json != null) {
      _lastExportGate = jsonDecode(json) as Map<String, dynamic>;
      notifyListeners();
      return _lastExportGate;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate RGAR compliance report.
  Map<String, dynamic>? generateReport(Map<String, dynamic> session) {
    final json = _ffi.rgaiGetReport(jsonEncode(session));
    if (json != null) {
      _lastReport = jsonDecode(json) as Map<String, dynamic>;
      notifyListeners();
      return _lastReport;
    }
    return null;
  }

  /// Get remediation suggestions for a failing asset.
  Map<String, dynamic>? getRemediation(Map<String, dynamic> assetProfile) {
    final json = _ffi.rgaiGetRemediation(jsonEncode(assetProfile));
    if (json != null) {
      _lastRemediation = jsonDecode(json) as Map<String, dynamic>;
      notifyListeners();
      return _lastRemediation;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void clearResults() {
    _lastAssetAnalysis = null;
    _lastSessionAnalysis = null;
    _lastExportGate = null;
    _lastReport = null;
    _lastRemediation = null;
    notifyListeners();
  }
}

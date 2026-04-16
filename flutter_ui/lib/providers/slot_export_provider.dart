import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// UCP Export™ Provider — Universal Compliance Package Export.
///
/// Bridges rf-slot-export Rust crate to Flutter UI via FFI.
/// Manages export formats, single/batch export operations.
///
/// Register as GetIt singleton.
class SlotExportProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> _availableFormats = const [];
  List<Map<String, dynamic>> _lastExportResults = const [];
  Map<String, dynamic>? _lastSingleResult;
  bool _isExporting = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> get availableFormats => _availableFormats;
  List<Map<String, dynamic>> get lastExportResults => _lastExportResults;
  Map<String, dynamic>? get lastSingleResult => _lastSingleResult;
  bool get isExporting => _isExporting;

  /// All formats that succeeded in last batch export.
  List<Map<String, dynamic>> get successfulExports =>
      _lastExportResults.where((r) => r['success'] == true).toList();

  /// All formats that failed in last batch export.
  List<Map<String, dynamic>> get failedExports =>
      _lastExportResults.where((r) => r['success'] != true).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  SlotExportProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // FORMAT DISCOVERY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load available export formats from Rust.
  void loadFormats() {
    final json = _ffi.slotExportFormats();
    if (json != null) {
      final list = jsonDecode(json) as List;
      _availableFormats = list.cast<Map<String, dynamic>>();
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export to ALL available formats.
  /// [project] — FluxForgeExportProject as Map.
  /// Returns list of per-format results.
  List<Map<String, dynamic>>? exportAll(Map<String, dynamic> project) {
    _isExporting = true;
    notifyListeners();

    try {
      final json = _ffi.slotExportAll(jsonEncode(project));
      if (json != null) {
        final list = jsonDecode(json) as List;
        _lastExportResults = list.cast<Map<String, dynamic>>();
        return _lastExportResults;
      }
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  /// Export to a single specific format.
  /// [project] — FluxForgeExportProject as Map.
  /// [format] — target format: "howler", "wwise", "fmod", "generic".
  Map<String, dynamic>? exportSingle(Map<String, dynamic> project, String format) {
    _isExporting = true;
    notifyListeners();

    try {
      final request = {'project': project, 'format': format};
      final json = _ffi.slotExportSingle(jsonEncode(request));
      if (json != null) {
        _lastSingleResult = jsonDecode(json) as Map<String, dynamic>;
        return _lastSingleResult;
      }
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void clearResults() {
    _lastExportResults = const [];
    _lastSingleResult = null;
    notifyListeners();
  }
}

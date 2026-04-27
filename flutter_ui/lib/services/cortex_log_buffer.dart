/// CortexLogBuffer — Circular log buffer koji hvata SVE Flutter debug ispise
///
/// Inicijalizuje se pre runApp() i override-uje globalnu debugPrint funkciju.
/// Na taj način CORTEX uvek ima pristup poslednjim N log linijama, bez
/// Terminal-a i bez TCC permisija.
///
/// Endpointi:
///   GET /brain/logs?last=100   → JSON array poslednih N linija
///   GET /brain/logs/clear      → Briše buffer
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOG ENTRY
// ═══════════════════════════════════════════════════════════════════════════

class CortexLogEntry {
  final DateTime timestamp;
  final String message;
  final String level; // 'debug' | 'warning' | 'error' | 'info'

  const CortexLogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'level': level,
        'msg': message,
      };

  /// Heuristic — detekcija nivoa iz poruke
  static String detectLevel(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('error') || lower.contains('exception') || lower.contains('failed')) {
      return 'error';
    }
    if (lower.contains('warn') || lower.contains('warning')) {
      return 'warning';
    }
    if (lower.contains('[cortex]') || lower.contains('cortex:')) {
      return 'info';
    }
    return 'debug';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX LOG BUFFER
// ═══════════════════════════════════════════════════════════════════════════

/// Singleton circular log buffer.
/// Koristiti CortexLogBuffer.init() ODMAH posle WidgetsFlutterBinding.ensureInitialized()
class CortexLogBuffer {
  CortexLogBuffer._();
  static final instance = CortexLogBuffer._();

  static const int _maxEntries = 2000;

  // Koristi List kao circular buffer (insert(0) + removeLast za LIFO)
  final List<CortexLogEntry> _entries = [];
  List<CortexLogEntry> get entries => List.unmodifiable(_entries);

  // Statistike
  int _totalReceived = 0;
  int get totalReceived => _totalReceived;

  int _errorCount = 0;
  int get errorCount => _errorCount;

  // Čuva originalnu debugPrint funkciju
  DebugPrintCallback? _originalPrint;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ─── Initialization ─────────────────────────────────────────────────────

  /// Inicijalizuje buffer i override-uje debugPrint.
  /// Pozivati JEDNOM na startu aplikacije.
  void init() {
    if (_initialized) return;

    _originalPrint = debugPrint;

    debugPrint = (String? message, {int? wrapWidth}) {
      // Prosleđuje originalnom printeru (u debug buildu piše u console)
      _originalPrint?.call(message, wrapWidth: wrapWidth);

      if (message == null || message.isEmpty) return;

      final entry = CortexLogEntry(
        timestamp: DateTime.now(),
        message: message,
        level: CortexLogEntry.detectLevel(message),
      );

      _entries.insert(0, entry);
      _totalReceived++;

      if (entry.level == 'error') _errorCount++;

      // Trim buffer
      if (_entries.length > _maxEntries) {
        _entries.removeLast();
      }
    };

    _initialized = true;
    debugPrint('[CortexLogBuffer] 📝 Inicijalizovan — hvata debug log');
  }

  // ─── Query ──────────────────────────────────────────────────────────────

  /// Vraća poslednje N log unosa (najnoviji prvi)
  List<CortexLogEntry> recent({int n = 100}) {
    return _entries.take(n).toList();
  }

  /// Filtrirane po nivou
  List<CortexLogEntry> byLevel(String level, {int n = 100}) {
    return _entries.where((e) => e.level == level).take(n).toList();
  }

  /// Filtrirane po sadržaju (case-insensitive substring)
  List<CortexLogEntry> search(String query, {int n = 50}) {
    final lower = query.toLowerCase();
    return _entries.where((e) => e.message.toLowerCase().contains(lower)).take(n).toList();
  }

  /// Samo greške (poslednjih N)
  List<CortexLogEntry> get errors => byLevel('error');

  // ─── Mutation ───────────────────────────────────────────────────────────

  /// Briše buffer (ali ne utiče na debugPrint hook)
  void clear() {
    _entries.clear();
    debugPrint('[CortexLogBuffer] 🧹 Buffer obrisan');
  }

  /// Ručno loguje poruku (za CORTEX-interne poruke)
  void log(String message, {String level = 'info'}) {
    final entry = CortexLogEntry(
      timestamp: DateTime.now(),
      message: message,
      level: level,
    );
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) _entries.removeLast();
    _totalReceived++;
  }

  // ─── Stats ──────────────────────────────────────────────────────────────

  Map<String, dynamic> get stats => {
        'totalReceived': _totalReceived,
        'buffered': _entries.length,
        'errorCount': _errorCount,
        'initialized': _initialized,
        'maxEntries': _maxEntries,
      };
}

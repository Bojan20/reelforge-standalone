/// SlotLab Export Service — T3.1–T3.6
///
/// Wraps the rf-slot-export Rust crate FFI to provide:
/// - Export to Howler.js AudioSprite (T3.2)
/// - Export to Wwise project XML (T3.3)
/// - Export to FMOD Studio JSON (T3.4)
/// - Export to Generic JSON (T3.5)
/// - Export to all formats at once
/// - Export validation (roundtrip check) (T3.6)
///
/// The service converts FluxForge AudioEventMap → FluxForgeExportProject
/// and delegates all format-specific logic to Rust.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import 'math_audio_bridge_service.dart';
import 'par_import_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT FORMAT ENUM
// ═══════════════════════════════════════════════════════════════════════════════

/// Available export targets
enum ExportFormat {
  howler,
  wwise,
  fmod,
  genericJson,
  all;

  String get formatKey => switch (this) {
    ExportFormat.howler => 'howler',
    ExportFormat.wwise => 'wwise',
    ExportFormat.fmod => 'fmod',
    ExportFormat.genericJson => 'json',
    ExportFormat.all => 'all',
  };

  String get displayName => switch (this) {
    ExportFormat.howler => 'Howler.js AudioSprite',
    ExportFormat.wwise => 'Wwise Project XML',
    ExportFormat.fmod => 'FMOD Studio JSON',
    ExportFormat.genericJson => 'Generic JSON',
    ExportFormat.all => 'All Formats',
  };

  String get fileExtension => switch (this) {
    ExportFormat.howler => 'json',
    ExportFormat.wwise => 'xml',
    ExportFormat.fmod => 'json',
    ExportFormat.genericJson => 'json',
    ExportFormat.all => 'zip',
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// A single file in an export bundle
class ExportFile {
  final String filename;
  final String content;
  final String mimeType;
  final String? suggestedPath;

  const ExportFile({
    required this.filename,
    required this.content,
    required this.mimeType,
    this.suggestedPath,
  });

  factory ExportFile.fromJson(Map<String, dynamic> j) => ExportFile(
    filename: (j['filename'] as String?) ?? 'output.json',
    content: (j['content'] as String?) ?? '',
    mimeType: (j['mime_type'] as String?) ?? 'application/octet-stream',
    suggestedPath: j['suggested_path'] as String?,
  );

  bool get isJson => mimeType == 'application/json';
  bool get isXml => mimeType == 'application/xml';
}

/// Complete export bundle from one target
class ExportBundle {
  final String format;
  final String version;
  final List<ExportFile> files;
  final List<String> warnings;
  final int eventCount;

  const ExportBundle({
    required this.format,
    required this.version,
    required this.files,
    required this.warnings,
    required this.eventCount,
  });

  factory ExportBundle.fromJson(Map<String, dynamic> j) => ExportBundle(
    format: (j['format'] as String?) ?? '',
    version: (j['version'] as String?) ?? '',
    files: ((j['files'] as List?) ?? [])
        .map((e) => ExportFile.fromJson(e as Map<String, dynamic>))
        .toList(),
    warnings: ((j['warnings'] as List?) ?? []).cast<String>(),
    eventCount: (j['event_count'] as int?) ?? 0,
  );

  bool get hasWarnings => warnings.isNotEmpty;
  int get fileCount => files.length;
}

/// Result from exporting to all formats
class MultiFormatExportResult {
  final List<FormatExportEntry> entries;
  final DateTime exportedAt;

  const MultiFormatExportResult({
    required this.entries,
    required this.exportedAt,
  });

  List<FormatExportEntry> get successful =>
      entries.where((e) => e.success).toList();
  List<FormatExportEntry> get failed =>
      entries.where((e) => !e.success).toList();
  bool get allSucceeded => failed.isEmpty;
}

class FormatExportEntry {
  final String format;
  final bool success;
  final ExportBundle? bundle;
  final String? error;

  const FormatExportEntry({
    required this.format,
    required this.success,
    this.bundle,
    this.error,
  });

  factory FormatExportEntry.fromJson(Map<String, dynamic> j) => FormatExportEntry(
    format: (j['format'] as String?) ?? '',
    success: (j['success'] as bool?) ?? false,
    bundle: j.containsKey('bundle') && j['bundle'] != null
        ? ExportBundle.fromJson(j['bundle'] as Map<String, dynamic>)
        : null,
    error: j['error'] as String?,
  );
}

/// Export validation result (T3.6)
class ExportValidationResult {
  final bool valid;
  final List<String> findings;
  final int fileCount;
  final int totalBytes;

  const ExportValidationResult({
    required this.valid,
    required this.findings,
    required this.fileCount,
    required this.totalBytes,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// AVAILABLE FORMAT INFO
// ═══════════════════════════════════════════════════════════════════════════════

class ExportFormatInfo {
  final String name;
  final String version;

  const ExportFormatInfo({required this.name, required this.version});

  factory ExportFormatInfo.fromJson(Map<String, dynamic> j) => ExportFormatInfo(
    name: (j['name'] as String?) ?? '',
    version: (j['version'] as String?) ?? '',
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// SlotLab Export Service — T3.1–T3.6
class SlotLabExportService extends ChangeNotifier {
  ExportBundle? _lastBundle;
  ExportBundle? get lastBundle => _lastBundle;

  MultiFormatExportResult? _lastMultiResult;
  MultiFormatExportResult? get lastMultiResult => _lastMultiResult;

  bool _isExporting = false;
  bool get isExporting => _isExporting;

  String? _lastError;
  String? get lastError => _lastError;

  List<ExportFormatInfo> _availableFormats = [];
  List<ExportFormatInfo> get availableFormats => _availableFormats;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Fetch available export formats from Rust
  void loadAvailableFormats() {
    try {
      final json = NativeFFI.instance.slotLabExportFormats();
      if (json == null) return;
      final list = jsonDecode(json) as List;
      _availableFormats = list
          .map((e) => ExportFormatInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Export AudioEventMap to a specific format.
  /// [audioMap] — from MathAudioBridgeService
  /// [par] — source PAR document (for game metadata)
  /// [format] — target format
  Future<ExportBundle?> export({
    required AudioEventMap audioMap,
    required ParDocument par,
    required ExportFormat format,
  }) async {
    if (format == ExportFormat.all) {
      final multi = await exportAll(audioMap: audioMap, par: par);
      if (multi == null) return null;
      return multi.successful.isNotEmpty ? multi.successful.first.bundle : null;
    }

    _isExporting = true;
    _lastError = null;
    notifyListeners();

    try {
      final projectJson = _buildProjectJson(audioMap, par);
      final result = await compute(
        _exportInBackground,
        _ExportRequest(projectJson: projectJson, format: format.formatKey),
      );

      if (result == null) {
        _lastError = 'Export failed: no output from Rust engine';
        return null;
      }

      final bundle = ExportBundle.fromJson(
        jsonDecode(result) as Map<String, dynamic>,
      );
      _lastBundle = bundle;
      notifyListeners();
      return bundle;
    } catch (e) {
      _lastError = 'Export error: $e';
      notifyListeners();
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  /// Export to all formats at once
  Future<MultiFormatExportResult?> exportAll({
    required AudioEventMap audioMap,
    required ParDocument par,
  }) async {
    _isExporting = true;
    _lastError = null;
    notifyListeners();

    try {
      final projectJson = _buildProjectJson(audioMap, par);
      final result = await compute(
        _exportAllInBackground,
        projectJson,
      );

      if (result == null) {
        _lastError = 'Multi-format export failed';
        return null;
      }

      final list = jsonDecode(result) as List;
      final entries = list
          .map((e) => FormatExportEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      final multiResult = MultiFormatExportResult(
        entries: entries,
        exportedAt: DateTime.now(),
      );
      _lastMultiResult = multiResult;
      notifyListeners();
      return multiResult;
    } catch (e) {
      _lastError = 'Multi-format export error: $e';
      notifyListeners();
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  /// Save export bundle to disk directory
  Future<List<String>> saveToDisk(ExportBundle bundle, String outputDir) async {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final savedPaths = <String>[];
    for (final file in bundle.files) {
      final subDir = file.suggestedPath != null
          ? Directory('$outputDir/${file.suggestedPath}')
          : dir;
      if (!subDir.existsSync()) {
        await subDir.create(recursive: true);
      }
      final path = '${subDir.path}/${file.filename}';
      await File(path).writeAsString(file.content);
      savedPaths.add(path);
    }
    return savedPaths;
  }

  /// T3.6: Validate export bundle (roundtrip check)
  ExportValidationResult validateBundle(ExportBundle bundle) {
    final findings = <String>[];

    if (bundle.files.isEmpty) {
      findings.add('ERROR: Empty bundle — no files generated');
      return ExportValidationResult(
        valid: false,
        findings: findings,
        fileCount: 0,
        totalBytes: 0,
      );
    }

    int totalBytes = 0;
    for (final file in bundle.files) {
      totalBytes += file.content.length;

      if (file.content.isEmpty) {
        findings.add('WARNING: File "${file.filename}" is empty');
      }

      // JSON files must be valid JSON
      if (file.isJson && file.content.isNotEmpty) {
        try {
          jsonDecode(file.content);
        } catch (e) {
          findings.add('ERROR: File "${file.filename}" has invalid JSON: $e');
        }
      }

      // XML files must have XML declaration
      if (file.isXml && !file.content.startsWith('<?xml')) {
        findings.add(
          'WARNING: File "${file.filename}" missing XML declaration',
        );
      }
    }

    if (bundle.eventCount == 0) {
      findings.add('WARNING: Bundle has 0 events — may indicate empty project');
    }

    final hasErrors = findings.any((f) => f.startsWith('ERROR'));
    return ExportValidationResult(
      valid: !hasErrors,
      findings: findings,
      fileCount: bundle.files.length,
      totalBytes: totalBytes,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private
  // ──────────────────────────────────────────────────────────────────────────

  /// Convert AudioEventMap + ParDocument to FluxForgeExportProject JSON
  String _buildProjectJson(AudioEventMap audioMap, ParDocument par) {
    final events = audioMap.events.map((e) => {
      'name': e.name,
      'description': e.description,
      'category': _categoryKey(e.category),
      'tier': e.tier.name,
      'duration_ms': e.suggestedDurationMs,
      'voice_count': e.suggestedVoiceCount,
      'trigger_probability': e.triggerProbability,
      'can_overlap': true,
      'can_loop': e.name.contains('SPIN') && e.name != 'SPIN_START' && e.name != 'SPIN_END',
      'audio_weight': e.audioWeight,
      'rtp_contribution': e.rtpContribution,
      'is_required': e.isRequired,
      'priority': e.tier.index * 2 + 3,
    }).toList();

    return jsonEncode({
      'game_name': par.gameName,
      'game_id': par.gameId,
      'rtp_target': par.rtpTarget,
      'volatility': par.volatility.name.toUpperCase(),
      'voice_budget': 48,
      'reels': par.reels,
      'rows': par.rows,
      'win_mechanism': par.waysToWin != null
          ? '${par.waysToWin} ways'
          : '${par.paylines} paylines',
      'audio_events': events,
      'win_tiers': <dynamic>[],
      'exported_at': DateTime.now().toIso8601String(),
      'tool_version': 'FluxForge Studio 1.0',
    });
  }

  String _categoryKey(AudioEventCategory cat) => switch (cat) {
    AudioEventCategory.baseGame => 'BaseGame',
    AudioEventCategory.win => 'Win',
    AudioEventCategory.nearMiss => 'NearMiss',
    AudioEventCategory.feature => 'Feature',
    AudioEventCategory.jackpot => 'Jackpot',
    AudioEventCategory.special => 'Special',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate helpers
// ─────────────────────────────────────────────────────────────────────────────

class _ExportRequest {
  final String projectJson;
  final String format;
  const _ExportRequest({required this.projectJson, required this.format});
}

String? _exportInBackground(_ExportRequest req) {
  return NativeFFI.instance.slotLabExport(req.projectJson, req.format);
}

String? _exportAllInBackground(String projectJson) {
  return NativeFFI.instance.slotLabExportAll(projectJson);
}

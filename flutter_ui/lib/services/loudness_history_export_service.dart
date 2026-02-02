/// Loudness History Export Service
///
/// Exports LUFS history data in various formats for analysis and reporting.
/// Supports CSV and JSON export with configurable time ranges.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../widgets/metering/lufs_history_widget.dart';

/// Export time range options
enum LoudnessExportRange {
  /// Last 60 seconds of data
  last60Seconds,

  /// Last 5 minutes of data
  last5Minutes,

  /// Entire session
  fullSession,

  /// Custom time range (requires start/end timestamps)
  custom,
}

/// Export format options
enum LoudnessExportFormat {
  /// Comma-separated values
  csv,

  /// Structured JSON
  json,
}

/// Export configuration
class LoudnessExportConfig {
  final LoudnessExportFormat format;
  final LoudnessExportRange range;
  final double? customStartTime;
  final double? customEndTime;
  final bool includeMetadata;
  final bool includeTruePeak;
  final String? projectName;

  const LoudnessExportConfig({
    this.format = LoudnessExportFormat.csv,
    this.range = LoudnessExportRange.fullSession,
    this.customStartTime,
    this.customEndTime,
    this.includeMetadata = true,
    this.includeTruePeak = true,
    this.projectName,
  });

  LoudnessExportConfig copyWith({
    LoudnessExportFormat? format,
    LoudnessExportRange? range,
    double? customStartTime,
    double? customEndTime,
    bool? includeMetadata,
    bool? includeTruePeak,
    String? projectName,
  }) {
    return LoudnessExportConfig(
      format: format ?? this.format,
      range: range ?? this.range,
      customStartTime: customStartTime ?? this.customStartTime,
      customEndTime: customEndTime ?? this.customEndTime,
      includeMetadata: includeMetadata ?? this.includeMetadata,
      includeTruePeak: includeTruePeak ?? this.includeTruePeak,
      projectName: projectName ?? this.projectName,
    );
  }
}

/// Export result
class LoudnessExportResult {
  final bool success;
  final String? filePath;
  final int recordCount;
  final String? error;

  const LoudnessExportResult({
    required this.success,
    this.filePath,
    this.recordCount = 0,
    this.error,
  });

  factory LoudnessExportResult.success({
    required String filePath,
    required int recordCount,
  }) =>
      LoudnessExportResult(
        success: true,
        filePath: filePath,
        recordCount: recordCount,
      );

  factory LoudnessExportResult.failure(String error) =>
      LoudnessExportResult(success: false, error: error);
}

/// Session statistics
class LoudnessSessionStats {
  final double integratedLufs;
  final double maxMomentaryLufs;
  final double minMomentaryLufs;
  final double maxShortTermLufs;
  final double maxTruePeak;
  final double durationSeconds;
  final int sampleCount;

  const LoudnessSessionStats({
    required this.integratedLufs,
    required this.maxMomentaryLufs,
    required this.minMomentaryLufs,
    required this.maxShortTermLufs,
    required this.maxTruePeak,
    required this.durationSeconds,
    required this.sampleCount,
  });

  Map<String, dynamic> toJson() => {
        'integrated_lufs': integratedLufs,
        'max_momentary_lufs': maxMomentaryLufs,
        'min_momentary_lufs': minMomentaryLufs,
        'max_short_term_lufs': maxShortTermLufs,
        'max_true_peak_dbtp': maxTruePeak,
        'duration_seconds': durationSeconds,
        'sample_count': sampleCount,
      };
}

/// Loudness History Export Service
///
/// Singleton service for exporting LUFS measurement data.
class LoudnessHistoryExportService {
  LoudnessHistoryExportService._();
  static final instance = LoudnessHistoryExportService._();

  /// Export LUFS history data to file
  ///
  /// [history] - List of LUFS snapshots to export
  /// [outputPath] - Full path for output file
  /// [config] - Export configuration options
  Future<LoudnessExportResult> exportToFile({
    required List<LufsSnapshot> history,
    required String outputPath,
    LoudnessExportConfig config = const LoudnessExportConfig(),
  }) async {
    try {
      if (history.isEmpty) {
        return LoudnessExportResult.failure('No data to export');
      }

      // Filter by time range
      final filteredHistory = _filterByRange(history, config);

      if (filteredHistory.isEmpty) {
        return LoudnessExportResult.failure('No data in selected time range');
      }

      // Generate content based on format
      final content = switch (config.format) {
        LoudnessExportFormat.csv => _generateCsv(filteredHistory, config),
        LoudnessExportFormat.json => _generateJson(filteredHistory, config),
      };

      // Write to file
      final file = File(outputPath);
      await file.writeAsString(content);

      debugPrint(
          '[LoudnessExport] Exported ${filteredHistory.length} records to: $outputPath');

      return LoudnessExportResult.success(
        filePath: outputPath,
        recordCount: filteredHistory.length,
      );
    } catch (e) {
      debugPrint('[LoudnessExport] Error: $e');
      return LoudnessExportResult.failure('Export failed: $e');
    }
  }

  /// Export to CSV format (returns string content)
  String exportToCsvString(
    List<LufsSnapshot> history, {
    bool includeTruePeak = false,
  }) {
    return _generateCsv(
      history,
      LoudnessExportConfig(includeTruePeak: includeTruePeak),
    );
  }

  /// Export to JSON format (returns string content)
  String exportToJsonString(
    List<LufsSnapshot> history, {
    bool includeMetadata = true,
    String? projectName,
  }) {
    return _generateJson(
      history,
      LoudnessExportConfig(
        includeMetadata: includeMetadata,
        projectName: projectName,
      ),
    );
  }

  /// Calculate session statistics from history
  LoudnessSessionStats calculateStats(List<LufsSnapshot> history) {
    if (history.isEmpty) {
      return const LoudnessSessionStats(
        integratedLufs: -60.0,
        maxMomentaryLufs: -60.0,
        minMomentaryLufs: -60.0,
        maxShortTermLufs: -60.0,
        maxTruePeak: -60.0,
        durationSeconds: 0,
        sampleCount: 0,
      );
    }

    double maxMomentary = -100.0;
    double minMomentary = 0.0;
    double maxShortTerm = -100.0;

    // Integrated is typically the last value in history (running average)
    final integrated = history.last.integrated;

    for (final snap in history) {
      if (snap.momentary > maxMomentary) maxMomentary = snap.momentary;
      if (snap.momentary < minMomentary && snap.momentary > -60) {
        minMomentary = snap.momentary;
      }
      if (snap.shortTerm > maxShortTerm) maxShortTerm = snap.shortTerm;
    }

    final duration = history.isNotEmpty
        ? history.last.timestamp - history.first.timestamp
        : 0.0;

    return LoudnessSessionStats(
      integratedLufs: integrated,
      maxMomentaryLufs: maxMomentary,
      minMomentaryLufs: minMomentary,
      maxShortTermLufs: maxShortTerm,
      maxTruePeak: -1.0, // Would need true peak data from FFI
      durationSeconds: duration,
      sampleCount: history.length,
    );
  }

  /// Generate suggested filename based on config
  String generateFilename({
    String? projectName,
    LoudnessExportFormat format = LoudnessExportFormat.csv,
  }) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final prefix = projectName ?? 'loudness';
    final ext = format == LoudnessExportFormat.csv ? 'csv' : 'json';
    return '${prefix}_lufs_$timestamp.$ext';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<LufsSnapshot> _filterByRange(
    List<LufsSnapshot> history,
    LoudnessExportConfig config,
  ) {
    if (history.isEmpty) return [];

    final maxTime = history.last.timestamp;

    switch (config.range) {
      case LoudnessExportRange.last60Seconds:
        final startTime = maxTime - 60.0;
        return history.where((s) => s.timestamp >= startTime).toList();

      case LoudnessExportRange.last5Minutes:
        final startTime = maxTime - 300.0;
        return history.where((s) => s.timestamp >= startTime).toList();

      case LoudnessExportRange.fullSession:
        return history;

      case LoudnessExportRange.custom:
        final start = config.customStartTime ?? 0;
        final end = config.customEndTime ?? maxTime;
        return history
            .where((s) => s.timestamp >= start && s.timestamp <= end)
            .toList();
    }
  }

  String _generateCsv(
    List<LufsSnapshot> history,
    LoudnessExportConfig config,
  ) {
    final buffer = StringBuffer();

    // Header row
    buffer.writeln('timestamp_s,integrated_lufs,short_term_lufs,momentary_lufs');

    // Data rows
    for (final snap in history) {
      buffer.writeln(snap.toCsvRow());
    }

    return buffer.toString();
  }

  String _generateJson(
    List<LufsSnapshot> history,
    LoudnessExportConfig config,
  ) {
    final data = <String, dynamic>{};

    // Metadata
    if (config.includeMetadata) {
      data['metadata'] = {
        'export_time': DateTime.now().toIso8601String(),
        'project_name': config.projectName,
        'sample_count': history.length,
        'format_version': '1.0',
      };

      // Add statistics
      final stats = calculateStats(history);
      data['statistics'] = stats.toJson();
    }

    // Measurement data
    data['measurements'] = history
        .map((s) => {
              'timestamp': s.timestamp,
              'integrated': s.integrated,
              'short_term': s.shortTerm,
              'momentary': s.momentary,
            })
        .toList();

    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

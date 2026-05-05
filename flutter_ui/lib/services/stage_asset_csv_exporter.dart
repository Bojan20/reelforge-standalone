/// P0 WF-07: Stage→Asset CSV Export Service (2026-01-30)
///
/// Exports event→stage→asset mappings to CSV format for use in external tools,
/// documentation, and QA workflows.

import 'dart:io';
import '../models/middleware_models.dart';

/// CSV Exporter for stage→asset mappings
class StageAssetCsvExporter {
  /// UTF-8 BOM (Byte Order Mark, U+FEFF). Prepended so Excel for Windows
  /// recognises non-ASCII (e.g. ćčšđž in stage labels or asset paths) as
  /// UTF-8 instead of mojibake-ing them as Windows-1252.
  static const String utf8Bom = '﻿';

  /// RFC 4180 line terminator. Strict CSV parsers reject lone `\n`; CRLF is
  /// the only universally compatible record separator.
  static const String rfc4180Eol = '\r\n';

  /// Export events to CSV format (RFC 4180, UTF-8 BOM prefixed).
  ///
  /// Format: stage,event_name,audio_path,volume,pan,offset,bus,fade_in,fade_out,trim_start,trim_end,ale_layer
  ///
  /// Example output (BOM + CRLF, shown here as `\r\n`):
  /// ```csv
  /// ﻿stage,event_name,audio_path,volume,pan,offset,bus,fade_in,fade_out,trim_start,trim_end,ale_layer\r\n
  /// UI_SPIN_PRESS,onUiSpin,/audio/spin_button.wav,1.0,0.0,0.0,SFX,0.0,0.0,0.0,0.0,\r\n
  /// REEL_STOP_0,onReelLand1,/audio/reel_stop.wav,0.8,-0.8,0.0,Reels,0.0,50.0,0.0,0.0,2\r\n
  /// ```
  static String exportToCsv(List<MiddlewareEvent> events) {
    final buffer = StringBuffer();

    // RFC 4180 + Excel-Windows compatibility:
    //   1. UTF-8 BOM lets Excel auto-detect encoding without prompting.
    //   2. CRLF is the canonical record separator; lone LF breaks strict
    //      parsers (Power Query, RFC-conforming libs).
    buffer.write(utf8Bom);
    buffer.write(
      'stage,event_name,audio_path,volume,pan,offset,bus,fade_in,fade_out,trim_start,trim_end,ale_layer',
    );
    buffer.write(rfc4180Eol);

    // Iterate through events
    for (final event in events) {
      // Skip events without stage binding
      if (event.stage.isEmpty) continue;

      for (final action in event.actions) {
        // Only export Play actions with audio assets
        if (action.type != ActionType.play || action.assetId.isEmpty) continue;

        // Build CSV row
        final row = [
          _escapeCsv(event.stage),
          _escapeCsv(event.name),
          _escapeCsv(action.assetId), // Audio path
          action.gain.toStringAsFixed(2),
          action.pan.toStringAsFixed(2),
          action.delay.toStringAsFixed(3),
          _escapeCsv(action.bus),
          action.fadeInMs.toStringAsFixed(1),
          action.fadeOutMs.toStringAsFixed(1),
          action.trimStartMs.toStringAsFixed(1),
          action.trimEndMs.toStringAsFixed(1),
          action.aleLayerId?.toString() ?? '',
        ];

        buffer.write(row.join(','));
        buffer.write(rfc4180Eol);
      }
    }

    return buffer.toString();
  }

  /// Export to file
  static Future<void> exportToFile(List<MiddlewareEvent> events, String outputPath) async {
    final csv = exportToCsv(events);
    final file = File(outputPath);
    await file.writeAsString(csv);
  }

  /// Escape CSV field per RFC 4180 §2.6.
  ///
  /// Wraps the value in double-quotes and doubles any inner quote when the
  /// field contains a comma, double-quote, CR, or LF. Pre-fix this missed
  /// bare `\r` (which a producer could paste in via Windows clipboard) —
  /// strict parsers would then split the row on `\r\n` mid-field.
  static String _escapeCsv(String value) {
    final needsQuoting = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (needsQuoting) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Get export stats
  static Map<String, dynamic> getExportStats(List<MiddlewareEvent> events) {
    int totalEvents = 0;
    int eventsWithStage = 0;
    int totalLayers = 0;
    final Set<String> uniqueStages = {};
    final Set<String> uniqueBuses = {};

    for (final event in events) {
      totalEvents++;
      if (event.stage.isNotEmpty) {
        eventsWithStage++;
        uniqueStages.add(event.stage);
      }

      for (final action in event.actions) {
        if (action.type == ActionType.play && action.assetId.isNotEmpty) {
          totalLayers++;
          uniqueBuses.add(action.bus);
        }
      }
    }

    return {
      'totalEvents': totalEvents,
      'eventsWithStage': eventsWithStage,
      'totalLayers': totalLayers,
      'uniqueStages': uniqueStages.length,
      'uniqueBuses': uniqueBuses.length,
      'stages': uniqueStages.toList()..sort(),
      'buses': uniqueBuses.toList()..sort(),
    };
  }
}

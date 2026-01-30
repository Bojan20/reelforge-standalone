/// P0 WF-07: Stage→Asset CSV Export Service (2026-01-30)
///
/// Exports event→stage→asset mappings to CSV format for use in external tools,
/// documentation, and QA workflows.

import 'dart:io';
import '../models/middleware_models.dart';

/// CSV Exporter for stage→asset mappings
class StageAssetCsvExporter {
  /// Export events to CSV format
  ///
  /// Format: stage,event_name,audio_path,volume,pan,offset,bus,fade_in,fade_out,trim_start,trim_end,ale_layer
  ///
  /// Example output:
  /// ```csv
  /// stage,event_name,audio_path,volume,pan,offset,bus,fade_in,fade_out,trim_start,trim_end,ale_layer
  /// SPIN_START,onUiSpin,/audio/spin_button.wav,1.0,0.0,0.0,SFX,0.0,0.0,0.0,0.0,
  /// REEL_STOP_0,onReelLand1,/audio/reel_stop.wav,0.8,-0.8,0.0,Reels,0.0,50.0,0.0,0.0,2
  /// ```
  static String exportToCsv(List<MiddlewareEvent> events) {
    final buffer = StringBuffer();

    // Write CSV header
    buffer.writeln('stage,event_name,audio_path,volume,pan,offset,bus,fade_in,fade_out,trim_start,trim_end,ale_layer');

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

        buffer.writeln(row.join(','));
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

  /// Escape CSV field (handle commas, quotes, newlines)
  static String _escapeCsv(String value) {
    // If field contains comma, quote, or newline, wrap in quotes and escape quotes
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
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

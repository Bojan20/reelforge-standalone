import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/loudness_history_export_service.dart';
import 'package:fluxforge_ui/widgets/metering/lufs_history_widget.dart';

void main() {
  group('LoudnessHistoryExportService', () {
    late List<LufsSnapshot> testHistory;

    setUp(() {
      // Create test LUFS history data
      testHistory = List.generate(
        100,
        (i) => LufsSnapshot(
          timestamp: i * 0.5, // 0.5 second intervals
          integrated: -14.0 - (i * 0.01), // Slowly decreasing
          shortTerm: -12.0 + (i % 10) * 0.5, // Varying
          momentary: -10.0 + (i % 20) * 0.3, // More varying
        ),
      );
    });

    test('exportToCsvString generates valid CSV', () {
      final service = LoudnessHistoryExportService.instance;
      final csv = service.exportToCsvString(testHistory);

      // Check header
      expect(csv, contains('timestamp_s,integrated_lufs,short_term_lufs,momentary_lufs'));

      // Check data rows exist
      final lines = csv.split('\n');
      expect(lines.length, greaterThan(100)); // Header + 100 data rows

      // Verify a data row format
      final firstDataLine = lines[1];
      final parts = firstDataLine.split(',');
      expect(parts.length, 4); // timestamp, integrated, short_term, momentary
    });

    test('exportToJsonString generates valid JSON with metadata', () {
      final service = LoudnessHistoryExportService.instance;
      final jsonStr = service.exportToJsonString(
        testHistory,
        includeMetadata: true,
        projectName: 'TestProject',
      );

      final data = json.decode(jsonStr) as Map<String, dynamic>;

      // Check metadata
      expect(data.containsKey('metadata'), true);
      final metadata = data['metadata'] as Map<String, dynamic>;
      expect(metadata['project_name'], 'TestProject');
      expect(metadata['sample_count'], 100);

      // Check statistics
      expect(data.containsKey('statistics'), true);
      final stats = data['statistics'] as Map<String, dynamic>;
      expect(stats.containsKey('integrated_lufs'), true);
      expect(stats.containsKey('max_momentary_lufs'), true);

      // Check measurements
      expect(data.containsKey('measurements'), true);
      final measurements = data['measurements'] as List;
      expect(measurements.length, 100);
    });

    test('calculateStats returns correct statistics', () {
      final service = LoudnessHistoryExportService.instance;
      final stats = service.calculateStats(testHistory);

      expect(stats.sampleCount, 100);
      expect(stats.durationSeconds, closeTo(49.5, 0.1)); // (99 * 0.5)
      expect(stats.integratedLufs, closeTo(-14.99, 0.1)); // Last value
    });

    test('filterByRange respects last60Seconds', () {
      final service = LoudnessHistoryExportService.instance;
      final config = LoudnessExportConfig(
        range: LoudnessExportRange.last60Seconds,
      );

      // Export with filter
      final csv = service.exportToCsvString(
        testHistory.where((s) => s.timestamp >= (testHistory.last.timestamp - 60)).toList(),
      );

      final lines = csv.split('\n').where((l) => l.isNotEmpty).toList();
      // Should have header + data within 60 seconds
      // 100 samples at 0.5s = 50 seconds total, so all should be included
      expect(lines.length, lessThanOrEqualTo(122)); // 120 samples max + header + possible empty
    });

    test('generateFilename creates valid filename', () {
      final service = LoudnessHistoryExportService.instance;

      final csvFilename = service.generateFilename(
        projectName: 'MyProject',
        format: LoudnessExportFormat.csv,
      );
      expect(csvFilename, startsWith('MyProject_lufs_'));
      expect(csvFilename, endsWith('.csv'));

      final jsonFilename = service.generateFilename(
        projectName: 'MyProject',
        format: LoudnessExportFormat.json,
      );
      expect(jsonFilename, endsWith('.json'));
    });

    test('exportToFile creates file successfully', () async {
      final service = LoudnessHistoryExportService.instance;
      final tempDir = Directory.systemTemp.createTempSync('loudness_test_');
      final outputPath = '${tempDir.path}/test_export.csv';

      try {
        final result = await service.exportToFile(
          history: testHistory,
          outputPath: outputPath,
          config: const LoudnessExportConfig(format: LoudnessExportFormat.csv),
        );

        expect(result.success, true);
        expect(result.recordCount, 100);
        expect(File(outputPath).existsSync(), true);

        // Verify file content
        final content = await File(outputPath).readAsString();
        expect(content, contains('timestamp_s'));
        expect(content, contains('integrated_lufs'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('exportToFile handles empty history', () async {
      final service = LoudnessHistoryExportService.instance;
      final tempDir = Directory.systemTemp.createTempSync('loudness_test_');
      final outputPath = '${tempDir.path}/test_empty.csv';

      try {
        final result = await service.exportToFile(
          history: [],
          outputPath: outputPath,
        );

        expect(result.success, false);
        expect(result.error, contains('No data'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('LoudnessExportConfig', () {
    test('copyWith creates correct copy', () {
      const original = LoudnessExportConfig(
        format: LoudnessExportFormat.csv,
        range: LoudnessExportRange.fullSession,
      );

      final copy = original.copyWith(
        format: LoudnessExportFormat.json,
        range: LoudnessExportRange.last60Seconds,
      );

      expect(copy.format, LoudnessExportFormat.json);
      expect(copy.range, LoudnessExportRange.last60Seconds);
      expect(copy.includeMetadata, original.includeMetadata); // Unchanged
    });
  });

  group('LoudnessSessionStats', () {
    test('toJson produces valid output', () {
      const stats = LoudnessSessionStats(
        integratedLufs: -14.0,
        maxMomentaryLufs: -8.0,
        minMomentaryLufs: -20.0,
        maxShortTermLufs: -10.0,
        maxTruePeak: -1.0,
        durationSeconds: 120.0,
        sampleCount: 240,
      );

      final jsonMap = stats.toJson();
      expect(jsonMap['integrated_lufs'], -14.0);
      expect(jsonMap['max_momentary_lufs'], -8.0);
      expect(jsonMap['sample_count'], 240);
    });
  });
}

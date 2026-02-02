import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/session_archive_service.dart';

void main() {
  group('SessionArchiveService', () {
    late Directory testProjectDir;
    late Directory outputDir;

    setUp(() async {
      // Create test project structure
      testProjectDir = await Directory.systemTemp.createTemp('test_project_');
      outputDir = await Directory.systemTemp.createTemp('test_output_');

      // Create project files
      await File('${testProjectDir.path}/project.ffproj')
          .writeAsString('{"name": "Test Project"}');
      await File('${testProjectDir.path}/settings.json')
          .writeAsString('{"volume": 1.0}');

      // Create audio folder
      final audioDir = Directory('${testProjectDir.path}/audio');
      await audioDir.create();
      await File('${audioDir.path}/test.wav').writeAsBytes([0, 1, 2, 3, 4, 5]);
      await File('${audioDir.path}/music.mp3').writeAsBytes([10, 11, 12, 13]);

      // Create presets folder
      final presetsDir = Directory('${testProjectDir.path}/presets');
      await presetsDir.create();
      await File('${presetsDir.path}/my_preset.ffpreset')
          .writeAsString('{"eq": {}}');
    });

    tearDown(() async {
      await testProjectDir.delete(recursive: true);
      await outputDir.delete(recursive: true);
    });

    test('createArchive creates valid ZIP', () async {
      final service = SessionArchiveService.instance;
      final outputPath = '${outputDir.path}/test_archive.zip';

      final result = await service.createArchive(
        projectPath: testProjectDir.path,
        outputPath: outputPath,
        config: const SessionArchiveConfig(
          includeAudio: true,
          includePresets: true,
        ),
      );

      expect(result.success, true);
      expect(result.totalFiles, greaterThan(0));
      expect(result.audioFiles, 2); // test.wav, music.mp3
      expect(result.presetFiles, 1); // my_preset.ffpreset
      expect(File(outputPath).existsSync(), true);
    });

    test('createArchive excludes audio when configured', () async {
      final service = SessionArchiveService.instance;
      final outputPath = '${outputDir.path}/no_audio_archive.zip';

      final result = await service.createArchive(
        projectPath: testProjectDir.path,
        outputPath: outputPath,
        config: const SessionArchiveConfig(
          includeAudio: false,
          includePresets: true,
        ),
      );

      expect(result.success, true);
      expect(result.audioFiles, 0);
      expect(result.presetFiles, 1);
    });

    test('createArchive respects maxAudioFileSize', () async {
      final service = SessionArchiveService.instance;
      final outputPath = '${outputDir.path}/size_limited_archive.zip';

      final result = await service.createArchive(
        projectPath: testProjectDir.path,
        outputPath: outputPath,
        config: const SessionArchiveConfig(
          includeAudio: true,
          maxAudioFileSize: 3, // Very small limit
        ),
      );

      expect(result.success, true);
      expect(result.skippedFiles.length, greaterThan(0)); // Should skip audio files
    });

    test('extractArchive restores files', () async {
      final service = SessionArchiveService.instance;
      final archivePath = '${outputDir.path}/extract_test.zip';
      final extractPath = '${outputDir.path}/extracted';

      // First create an archive
      await service.createArchive(
        projectPath: testProjectDir.path,
        outputPath: archivePath,
      );

      // Then extract it
      final result = await service.extractArchive(
        archivePath: archivePath,
        outputPath: extractPath,
      );

      expect(result.success, true);
      expect(result.totalFiles, greaterThan(0));
      expect(Directory(extractPath).existsSync(), true);
    });

    test('getArchiveInfo returns correct metadata', () async {
      final service = SessionArchiveService.instance;
      final archivePath = '${outputDir.path}/info_test.zip';

      // Create archive
      await service.createArchive(
        projectPath: testProjectDir.path,
        outputPath: archivePath,
      );

      // Get info
      final info = await service.getArchiveInfo(archivePath);

      expect(info, isNotNull);
      expect(info!['audio_count'], 2);
      expect(info['preset_count'], 1);
      expect(info['version'], '1.0');
    });

    test('handles non-existent project directory', () async {
      final service = SessionArchiveService.instance;
      final outputPath = '${outputDir.path}/fail_archive.zip';

      final result = await service.createArchive(
        projectPath: '/non/existent/path',
        outputPath: outputPath,
      );

      expect(result.success, false);
      expect(result.error, contains('not found'));
    });

    test('generateFilename creates valid name', () {
      final service = SessionArchiveService.instance;
      final filename = service.generateFilename('MyProject');

      expect(filename, startsWith('MyProject_archive_'));
      expect(filename, endsWith('.zip'));
    });
  });

  group('SessionArchiveConfig', () {
    test('copyWith creates correct copy', () {
      const original = SessionArchiveConfig(
        includeAudio: true,
        includePresets: true,
        compress: true,
      );

      final copy = original.copyWith(
        includeAudio: false,
        maxAudioFileSize: 1024 * 1024,
      );

      expect(copy.includeAudio, false);
      expect(copy.includePresets, true); // Unchanged
      expect(copy.maxAudioFileSize, 1024 * 1024);
    });
  });

  group('SessionArchiveResult', () {
    test('success factory creates correct result', () {
      final result = SessionArchiveResult.success(
        archivePath: '/path/to/archive.zip',
        totalFiles: 10,
        audioFiles: 5,
        presetFiles: 2,
        otherFiles: 3,
        totalSizeBytes: 1000000,
        compressedSizeBytes: 500000,
      );

      expect(result.success, true);
      expect(result.compressionRatio, 0.5);
    });

    test('failure factory creates correct result', () {
      final result = SessionArchiveResult.failure('Test error');

      expect(result.success, false);
      expect(result.error, 'Test error');
    });
  });

  group('SessionArchiveManifest', () {
    test('toJson produces valid output', () {
      final manifest = SessionArchiveManifest(
        version: '1.0',
        createdAt: DateTime(2026, 2, 2),
        projectName: 'TestProject',
        fileChecksums: {},
        config: const SessionArchiveConfig(),
      );

      final json = manifest.toJson();
      expect(json['version'], '1.0');
      expect(json['project_name'], 'TestProject');
    });

    test('fromJson parses correctly', () {
      final jsonData = {
        'version': '1.0',
        'created_at': '2026-02-02T00:00:00.000',
        'project_name': 'TestProject',
      };

      final manifest = SessionArchiveManifest.fromJson(jsonData);
      expect(manifest.version, '1.0');
      expect(manifest.projectName, 'TestProject');
    });
  });
}

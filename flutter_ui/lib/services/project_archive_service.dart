/// Project Archive Service
///
/// Creates ZIP archives of FluxForge projects with configurable options.
/// Supports including audio files, presets, and plugin references.

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

/// Archive configuration options
class ArchiveConfig {
  final bool includeAudio;
  final bool includePresets;
  final bool includePlugins;
  final bool compress;

  const ArchiveConfig({
    this.includeAudio = true,
    this.includePresets = true,
    this.includePlugins = false,
    this.compress = true,
  });
}

/// Archive creation result
class ArchiveResult {
  final bool success;
  final String? outputPath;
  final int fileCount;
  final int totalBytes;
  final String? error;

  const ArchiveResult({
    required this.success,
    this.outputPath,
    this.fileCount = 0,
    this.totalBytes = 0,
    this.error,
  });

  factory ArchiveResult.success({
    required String outputPath,
    required int fileCount,
    required int totalBytes,
  }) =>
      ArchiveResult(
        success: true,
        outputPath: outputPath,
        fileCount: fileCount,
        totalBytes: totalBytes,
      );

  factory ArchiveResult.failure(String error) =>
      ArchiveResult(success: false, error: error);
}

/// Project Archive Service - Creates ZIP archives of projects
class ProjectArchiveService {
  ProjectArchiveService._();
  static final instance = ProjectArchiveService._();

  /// Create a project archive
  ///
  /// [projectPath] - Root directory of the project
  /// [outputPath] - Full path for output ZIP file
  /// [config] - Archive configuration options
  /// [onProgress] - Progress callback (0.0 - 1.0)
  Future<ArchiveResult> createArchive({
    required String projectPath,
    required String outputPath,
    ArchiveConfig config = const ArchiveConfig(),
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        return ArchiveResult.failure('Project directory not found: $projectPath');
      }

      onProgress?.call(0.0, 'Scanning project...');

      // Collect files to archive
      final filesToArchive = <File>[];
      final projectName = path.basename(projectPath);

      // Always include project file (.ffproj)
      await for (final entity in projectDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = path.relative(entity.path, from: projectPath);
          final ext = path.extension(entity.path).toLowerCase();

          // Skip hidden files and system files
          if (path.basename(entity.path).startsWith('.')) continue;
          if (relativePath.contains('/.')) continue;

          // Project files - always include
          if (ext == '.ffproj' || ext == '.json') {
            filesToArchive.add(entity);
            continue;
          }

          // Audio files
          if (config.includeAudio) {
            if (['.wav', '.flac', '.mp3', '.ogg', '.aiff', '.aif'].contains(ext)) {
              filesToArchive.add(entity);
              continue;
            }
          }

          // Preset files
          if (config.includePresets) {
            if (['.ffpreset', '.fxp', '.fxb'].contains(ext)) {
              filesToArchive.add(entity);
              continue;
            }
          }

          // Plugin references (just metadata, not actual plugins)
          if (config.includePlugins) {
            if (['.vst3', '.component', '.clap'].contains(ext)) {
              // Only include plugin info file, not actual binary
              filesToArchive.add(entity);
              continue;
            }
          }
        }
      }

      if (filesToArchive.isEmpty) {
        return ArchiveResult.failure('No files found to archive');
      }

      onProgress?.call(0.1, 'Creating archive...');

      // Create archive
      final archive = Archive();
      int processedFiles = 0;
      int totalBytes = 0;

      for (final file in filesToArchive) {
        final relativePath = path.relative(file.path, from: projectPath);
        final archivePath = '$projectName/$relativePath';

        final fileBytes = await file.readAsBytes();
        totalBytes += fileBytes.length;

        archive.addFile(ArchiveFile(
          archivePath,
          fileBytes.length,
          fileBytes,
        ));

        processedFiles++;
        final progress = 0.1 + (0.7 * processedFiles / filesToArchive.length);
        onProgress?.call(progress, 'Adding: ${path.basename(file.path)}');
      }

      onProgress?.call(0.8, 'Compressing...');

      // Encode to ZIP
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      if (zipData.isEmpty) {
        return ArchiveResult.failure('Failed to encode ZIP archive');
      }

      onProgress?.call(0.9, 'Writing file...');

      // Write to output file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(zipData);

      onProgress?.call(1.0, 'Complete!');


      return ArchiveResult.success(
        outputPath: outputPath,
        fileCount: processedFiles,
        totalBytes: zipData.length,
      );
    } catch (e) {
      return ArchiveResult.failure('Archive creation failed: $e');
    }
  }

  /// Extract a project archive
  ///
  /// [archivePath] - Path to ZIP file
  /// [outputPath] - Directory to extract to
  Future<ArchiveResult> extractArchive({
    required String archivePath,
    required String outputPath,
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        return ArchiveResult.failure('Archive file not found: $archivePath');
      }

      onProgress?.call(0.0, 'Reading archive...');

      final bytes = await archiveFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      onProgress?.call(0.2, 'Extracting files...');

      final outputDir = Directory(outputPath);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      int extractedFiles = 0;
      int totalBytes = 0;

      for (final file in archive) {
        final filePath = path.join(outputPath, file.name);

        if (file.isFile) {
          final outputFile = File(filePath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
          totalBytes += file.size;
          extractedFiles++;

          final progress = 0.2 + (0.8 * extractedFiles / archive.length);
          onProgress?.call(progress, 'Extracting: ${path.basename(file.name)}');
        }
      }

      onProgress?.call(1.0, 'Complete!');

      return ArchiveResult.success(
        outputPath: outputPath,
        fileCount: extractedFiles,
        totalBytes: totalBytes,
      );
    } catch (e) {
      return ArchiveResult.failure('Extraction failed: $e');
    }
  }

  /// Get archive info without extracting
  Future<Map<String, dynamic>?> getArchiveInfo(String archivePath) async {
    try {
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) return null;

      final bytes = await archiveFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      int audioCount = 0;
      int presetCount = 0;
      int otherCount = 0;
      int totalSize = 0;

      for (final file in archive) {
        if (file.isFile) {
          final ext = path.extension(file.name).toLowerCase();
          totalSize += file.size;

          if (['.wav', '.flac', '.mp3', '.ogg', '.aiff'].contains(ext)) {
            audioCount++;
          } else if (['.ffpreset', '.fxp', '.fxb'].contains(ext)) {
            presetCount++;
          } else {
            otherCount++;
          }
        }
      }

      return {
        'fileCount': archive.length,
        'audioCount': audioCount,
        'presetCount': presetCount,
        'otherCount': otherCount,
        'totalSize': totalSize,
        'compressedSize': bytes.length,
      };
    } catch (e) {
      return null;
    }
  }
}

/// Session Archive Service
///
/// Creates complete project archives with audio files, presets, and metadata.
/// Extends ProjectArchiveService with session-specific functionality.

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

/// Session archive configuration
class SessionArchiveConfig {
  /// Include audio files in archive
  final bool includeAudio;

  /// Include preset files (.ffpreset, .fxp, .fxb)
  final bool includePresets;

  /// Include plugin state files (not actual plugins)
  final bool includePluginStates;

  /// Include project settings
  final bool includeSettings;

  /// Include undo history (can be large)
  final bool includeUndoHistory;

  /// Compress the archive
  final bool compress;

  /// Maximum audio file size in bytes (skip larger files if set)
  final int? maxAudioFileSize;

  const SessionArchiveConfig({
    this.includeAudio = true,
    this.includePresets = true,
    this.includePluginStates = true,
    this.includeSettings = true,
    this.includeUndoHistory = false,
    this.compress = true,
    this.maxAudioFileSize,
  });

  SessionArchiveConfig copyWith({
    bool? includeAudio,
    bool? includePresets,
    bool? includePluginStates,
    bool? includeSettings,
    bool? includeUndoHistory,
    bool? compress,
    int? maxAudioFileSize,
  }) {
    return SessionArchiveConfig(
      includeAudio: includeAudio ?? this.includeAudio,
      includePresets: includePresets ?? this.includePresets,
      includePluginStates: includePluginStates ?? this.includePluginStates,
      includeSettings: includeSettings ?? this.includeSettings,
      includeUndoHistory: includeUndoHistory ?? this.includeUndoHistory,
      compress: compress ?? this.compress,
      maxAudioFileSize: maxAudioFileSize ?? this.maxAudioFileSize,
    );
  }
}

/// Archive creation result
class SessionArchiveResult {
  final bool success;
  final String? archivePath;
  final int totalFiles;
  final int audioFiles;
  final int presetFiles;
  final int otherFiles;
  final int totalSizeBytes;
  final int compressedSizeBytes;
  final List<String> skippedFiles;
  final String? error;

  const SessionArchiveResult({
    required this.success,
    this.archivePath,
    this.totalFiles = 0,
    this.audioFiles = 0,
    this.presetFiles = 0,
    this.otherFiles = 0,
    this.totalSizeBytes = 0,
    this.compressedSizeBytes = 0,
    this.skippedFiles = const [],
    this.error,
  });

  factory SessionArchiveResult.success({
    required String archivePath,
    required int totalFiles,
    required int audioFiles,
    required int presetFiles,
    required int otherFiles,
    required int totalSizeBytes,
    required int compressedSizeBytes,
    List<String> skippedFiles = const [],
  }) =>
      SessionArchiveResult(
        success: true,
        archivePath: archivePath,
        totalFiles: totalFiles,
        audioFiles: audioFiles,
        presetFiles: presetFiles,
        otherFiles: otherFiles,
        totalSizeBytes: totalSizeBytes,
        compressedSizeBytes: compressedSizeBytes,
        skippedFiles: skippedFiles,
      );

  factory SessionArchiveResult.failure(String error) =>
      SessionArchiveResult(success: false, error: error);

  /// Compression ratio (1.0 = no compression)
  double get compressionRatio => totalSizeBytes > 0
      ? compressedSizeBytes / totalSizeBytes
      : 1.0;
}

/// Archive manifest for verification
class SessionArchiveManifest {
  final String version;
  final DateTime createdAt;
  final String? projectName;
  final Map<String, String> fileChecksums;
  final SessionArchiveConfig config;

  const SessionArchiveManifest({
    required this.version,
    required this.createdAt,
    this.projectName,
    required this.fileChecksums,
    required this.config,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'created_at': createdAt.toIso8601String(),
        'project_name': projectName,
        'file_count': fileChecksums.length,
        'config': {
          'include_audio': config.includeAudio,
          'include_presets': config.includePresets,
          'include_plugin_states': config.includePluginStates,
          'include_settings': config.includeSettings,
        },
      };

  factory SessionArchiveManifest.fromJson(Map<String, dynamic> json) {
    return SessionArchiveManifest(
      version: json['version'] as String? ?? '1.0',
      createdAt: DateTime.parse(json['created_at'] as String),
      projectName: json['project_name'] as String?,
      fileChecksums: {},
      config: const SessionArchiveConfig(),
    );
  }
}

/// Session Archive Service
///
/// Singleton service for creating and extracting session archives.
class SessionArchiveService {
  SessionArchiveService._();
  static final instance = SessionArchiveService._();

  static const String _manifestFileName = 'session_manifest.json';
  static const String _archiveVersion = '1.0';

  // Audio file extensions
  static const _audioExtensions = [
    '.wav',
    '.flac',
    '.mp3',
    '.ogg',
    '.aiff',
    '.aif',
    '.m4a',
  ];

  // Preset file extensions
  static const _presetExtensions = [
    '.ffpreset',
    '.fxp',
    '.fxb',
    '.aupreset',
  ];

  // Plugin state extensions
  static const _pluginStateExtensions = [
    '.ffstate',
    '.vstpreset',
  ];

  /// Create a session archive
  ///
  /// [projectPath] - Root directory of the project
  /// [outputPath] - Full path for output ZIP file
  /// [config] - Archive configuration options
  /// [onProgress] - Progress callback (0.0 - 1.0)
  Future<SessionArchiveResult> createArchive({
    required String projectPath,
    required String outputPath,
    SessionArchiveConfig config = const SessionArchiveConfig(),
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        return SessionArchiveResult.failure(
            'Project directory not found: $projectPath');
      }

      onProgress?.call(0.0, 'Scanning project...');

      // Collect files to archive
      final filesToArchive = <File>[];
      final skippedFiles = <String>[];
      int audioCount = 0;
      int presetCount = 0;
      int otherCount = 0;
      int totalSize = 0;

      final projectName = path.basename(projectPath);

      await for (final entity in projectDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = path.relative(entity.path, from: projectPath);
          final ext = path.extension(entity.path).toLowerCase();
          final fileName = path.basename(entity.path);

          // Skip hidden files and system files
          if (fileName.startsWith('.')) continue;
          if (relativePath.contains('/.')) continue;

          // Check file type and config
          bool shouldInclude = false;
          String category = 'other';

          // Project files - always include
          if (ext == '.ffproj' || ext == '.json') {
            shouldInclude = true;
            category = 'project';
          }
          // Audio files
          else if (_audioExtensions.contains(ext)) {
            if (config.includeAudio) {
              // Check size limit
              if (config.maxAudioFileSize != null) {
                final size = await entity.length();
                if (size > config.maxAudioFileSize!) {
                  skippedFiles.add('$relativePath (too large: ${_formatSize(size)})');
                  continue;
                }
              }
              shouldInclude = true;
              category = 'audio';
            }
          }
          // Preset files
          else if (_presetExtensions.contains(ext)) {
            if (config.includePresets) {
              shouldInclude = true;
              category = 'preset';
            }
          }
          // Plugin state files
          else if (_pluginStateExtensions.contains(ext)) {
            if (config.includePluginStates) {
              shouldInclude = true;
              category = 'plugin_state';
            }
          }
          // Settings files
          else if (fileName == 'settings.json' ||
              fileName == 'preferences.json') {
            if (config.includeSettings) {
              shouldInclude = true;
              category = 'settings';
            }
          }
          // Undo history
          else if (fileName == 'undo_history.json') {
            if (config.includeUndoHistory) {
              shouldInclude = true;
              category = 'undo';
            }
          }

          if (shouldInclude) {
            filesToArchive.add(entity);
            totalSize += await entity.length();

            switch (category) {
              case 'audio':
                audioCount++;
                break;
              case 'preset':
                presetCount++;
                break;
              default:
                otherCount++;
            }
          }
        }
      }

      if (filesToArchive.isEmpty) {
        return SessionArchiveResult.failure('No files found to archive');
      }

      onProgress?.call(0.1, 'Creating archive...');

      // Create archive
      final archive = Archive();
      int processedFiles = 0;

      for (final file in filesToArchive) {
        final relativePath = path.relative(file.path, from: projectPath);
        final archivePath = '$projectName/$relativePath';

        final fileBytes = await file.readAsBytes();

        archive.addFile(ArchiveFile(
          archivePath,
          fileBytes.length,
          fileBytes,
        ));

        processedFiles++;
        final progress = 0.1 + (0.7 * processedFiles / filesToArchive.length);
        onProgress?.call(progress, 'Adding: ${path.basename(file.path)}');
      }

      // Add manifest
      final manifest = SessionArchiveManifest(
        version: _archiveVersion,
        createdAt: DateTime.now(),
        projectName: projectName,
        fileChecksums: {},
        config: config,
      );

      final manifestJson =
          const JsonEncoder.withIndent('  ').convert(manifest.toJson());
      archive.addFile(ArchiveFile(
        '$projectName/$_manifestFileName',
        manifestJson.length,
        utf8.encode(manifestJson),
      ));

      onProgress?.call(0.8, 'Compressing...');

      // Encode to ZIP
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      if (zipData.isEmpty) {
        return SessionArchiveResult.failure('Failed to encode ZIP archive');
      }

      onProgress?.call(0.9, 'Writing file...');

      // Write to output file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(zipData);

      onProgress?.call(1.0, 'Complete!');


      return SessionArchiveResult.success(
        archivePath: outputPath,
        totalFiles: filesToArchive.length,
        audioFiles: audioCount,
        presetFiles: presetCount,
        otherFiles: otherCount,
        totalSizeBytes: totalSize,
        compressedSizeBytes: zipData.length,
        skippedFiles: skippedFiles,
      );
    } catch (e) {
      return SessionArchiveResult.failure('Archive creation failed: $e');
    }
  }

  /// Extract a session archive
  ///
  /// [archivePath] - Path to ZIP file
  /// [outputPath] - Directory to extract to
  /// [onProgress] - Progress callback
  Future<SessionArchiveResult> extractArchive({
    required String archivePath,
    required String outputPath,
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        return SessionArchiveResult.failure(
            'Archive file not found: $archivePath');
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
      int audioCount = 0;
      int presetCount = 0;
      int otherCount = 0;
      int totalSize = 0;

      for (final file in archive) {
        final filePath = path.join(outputPath, file.name);
        final ext = path.extension(file.name).toLowerCase();

        if (file.isFile) {
          final outputFile = File(filePath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
          totalSize += file.size;
          extractedFiles++;

          // Categorize
          if (_audioExtensions.contains(ext)) {
            audioCount++;
          } else if (_presetExtensions.contains(ext)) {
            presetCount++;
          } else {
            otherCount++;
          }

          final progress = 0.2 + (0.8 * extractedFiles / archive.length);
          onProgress?.call(progress, 'Extracting: ${path.basename(file.name)}');
        }
      }

      onProgress?.call(1.0, 'Complete!');

      return SessionArchiveResult.success(
        archivePath: outputPath,
        totalFiles: extractedFiles,
        audioFiles: audioCount,
        presetFiles: presetCount,
        otherFiles: otherCount,
        totalSizeBytes: totalSize,
        compressedSizeBytes: bytes.length,
      );
    } catch (e) {
      return SessionArchiveResult.failure('Extraction failed: $e');
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
      SessionArchiveManifest? manifest;

      for (final file in archive) {
        if (file.isFile) {
          final ext = path.extension(file.name).toLowerCase();
          totalSize += file.size;

          if (path.basename(file.name) == _manifestFileName) {
            try {
              final jsonStr = utf8.decode(file.content as List<int>);
              manifest = SessionArchiveManifest.fromJson(
                  json.decode(jsonStr) as Map<String, dynamic>);
            } catch (_) { /* ignored */ }
          } else if (_audioExtensions.contains(ext)) {
            audioCount++;
          } else if (_presetExtensions.contains(ext)) {
            presetCount++;
          } else {
            otherCount++;
          }
        }
      }

      return {
        'file_count': archive.length,
        'audio_count': audioCount,
        'preset_count': presetCount,
        'other_count': otherCount,
        'total_size': totalSize,
        'compressed_size': bytes.length,
        'version': manifest?.version,
        'created_at': manifest?.createdAt.toIso8601String(),
        'project_name': manifest?.projectName,
      };
    } catch (e) {
      return null;
    }
  }

  /// Generate suggested filename for archive
  String generateFilename(String? projectName) {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final prefix = projectName ?? 'session';
    return '${prefix}_archive_$timestamp.zip';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

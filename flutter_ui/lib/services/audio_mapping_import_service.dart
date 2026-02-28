/// Audio Mapping Import Service
///
/// Unified service for bulk audio import via three methods:
/// 1. Folder Drop → fuzzy match against composed stages
/// 2. CSV file → stage,audioPath,bus,priority mapping
/// 3. JSON file → structured mapping with metadata
///
/// Bridges StageGroupService's fuzzy matching with the Trostepeni
/// FeatureComposer's dynamic composed stages.
///
/// See: .claude/architecture/TROSTEPENI_STAGE_SYSTEM.md

import 'dart:convert';
import 'dart:io';
import 'package:get_it/get_it.dart';
import '../providers/slot_lab/feature_composer_provider.dart';
import 'stage_group_service.dart';

// =============================================================================
// IMPORT RESULT MODELS
// =============================================================================

/// Result of a bulk import operation
class BulkImportResult {
  /// Successfully matched stage → audioPath pairs
  final List<AudioMappingEntry> mappings;

  /// Files that couldn't be matched
  final List<UnmatchedImportFile> unmatched;

  /// Warnings (e.g., duplicate stages, missing files)
  final List<String> warnings;

  /// Import method used
  final ImportMethod method;

  const BulkImportResult({
    required this.mappings,
    required this.unmatched,
    required this.warnings,
    required this.method,
  });

  int get totalFiles => mappings.length + unmatched.length;
  int get matchedCount => mappings.length;
  int get unmatchedCount => unmatched.length;
  double get matchRate => totalFiles > 0 ? matchedCount / totalFiles : 0.0;

  /// Stages covered by this import
  Set<String> get coveredStages => mappings.map((m) => m.stageId).toSet();
}

/// A single stage → audio mapping entry
class AudioMappingEntry {
  final String stageId;
  final String audioPath;
  final String? bus;
  final double confidence;
  final String source; // 'fuzzy', 'csv', 'json', 'template'

  const AudioMappingEntry({
    required this.stageId,
    required this.audioPath,
    this.bus,
    this.confidence = 1.0,
    this.source = 'fuzzy',
  });

  @override
  String toString() => 'AudioMapping($stageId → $audioPath, ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// A file that couldn't be matched during import
class UnmatchedImportFile {
  final String fileName;
  final String filePath;
  final List<StageSuggestion> suggestions;

  const UnmatchedImportFile({
    required this.fileName,
    required this.filePath,
    this.suggestions = const [],
  });
}

/// Import method
enum ImportMethod {
  folderDrop('Folder Drop'),
  csvFile('CSV Import'),
  jsonFile('JSON Import'),
  templatePack('Template Pack');

  const ImportMethod(this.displayName);
  final String displayName;
}

// =============================================================================
// SERVICE
// =============================================================================

class AudioMappingImportService {
  AudioMappingImportService._();
  static final AudioMappingImportService instance = AudioMappingImportService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // METHOD 1: FOLDER DROP → FUZZY MATCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Match all audio files from a folder against ALL composed stages.
  /// Uses StageGroupService's fuzzy matching + composed stage names.
  BulkImportResult matchFolder(List<String> audioPaths) {
    final mappings = <AudioMappingEntry>[];
    final unmatched = <UnmatchedImportFile>[];
    final warnings = <String>[];

    // Get composed stages from FeatureComposer (if available)
    Set<String> composedStageIds = {};
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      final composer = GetIt.instance<FeatureComposerProvider>();
      composedStageIds = composer.composedStages.map((s) => s.id).toSet();
    }

    // Track which stages have been assigned to detect duplicates
    final assignedStages = <String>{};

    for (final path in audioPaths) {
      // Try fuzzy match via StageGroupService
      final match = StageGroupService.instance.matchSingleFile(path);

      if (match != null) {
        // Check if matched stage exists in composed stages
        final stageValid = composedStageIds.isEmpty || composedStageIds.contains(match.stage);

        if (stageValid) {
          if (assignedStages.contains(match.stage)) {
            warnings.add('Duplicate: "${_fileName(path)}" also matches ${match.stage} (skipped)');
          } else {
            mappings.add(AudioMappingEntry(
              stageId: match.stage,
              audioPath: path,
              confidence: match.confidence,
              source: 'fuzzy',
            ));
            assignedStages.add(match.stage);
          }
        } else {
          // Stage matched but not in composed stages
          unmatched.add(UnmatchedImportFile(
            fileName: _fileName(path),
            filePath: path,
            suggestions: [StageSuggestion(
              stage: match.stage,
              confidence: match.confidence,
              reason: 'Matched but mechanic not enabled',
            )],
          ));
          warnings.add('"${_fileName(path)}" matches ${match.stage} but mechanic is not enabled');
        }
      } else {
        // Try composed stage name direct match
        final directMatch = _tryDirectMatch(path, composedStageIds);
        if (directMatch != null) {
          if (!assignedStages.contains(directMatch)) {
            mappings.add(AudioMappingEntry(
              stageId: directMatch,
              audioPath: path,
              confidence: 0.85,
              source: 'fuzzy',
            ));
            assignedStages.add(directMatch);
          }
        } else {
          unmatched.add(UnmatchedImportFile(
            fileName: _fileName(path),
            filePath: path,
          ));
        }
      }
    }

    // Sort by confidence
    mappings.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Coverage warning
    if (composedStageIds.isNotEmpty) {
      final uncovered = composedStageIds.difference(assignedStages);
      if (uncovered.isNotEmpty) {
        warnings.add('${uncovered.length} stages still need audio: ${uncovered.take(5).join(", ")}${uncovered.length > 5 ? "..." : ""}');
      }
    }

    return BulkImportResult(
      mappings: mappings,
      unmatched: unmatched,
      warnings: warnings,
      method: ImportMethod.folderDrop,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METHOD 2: CSV IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse a CSV file with stage→audio mappings.
  ///
  /// Expected format (header required):
  /// ```
  /// stage,audio,bus,priority
  /// REEL_STOP_0,audio/reel_stop_0.wav,reels,P0
  /// CASCADE_START,audio/cascade_start.wav,sfx,P1
  /// ```
  ///
  /// Minimum columns: stage, audio
  /// Optional columns: bus, priority
  ///
  /// [basePath] is prepended to relative audio paths.
  BulkImportResult importCsv(String csvContent, {String? basePath}) {
    final mappings = <AudioMappingEntry>[];
    final unmatched = <UnmatchedImportFile>[];
    final warnings = <String>[];

    final lines = csvContent.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      warnings.add('CSV file is empty');
      return BulkImportResult(
        mappings: mappings,
        unmatched: unmatched,
        warnings: warnings,
        method: ImportMethod.csvFile,
      );
    }

    // Parse header
    final header = _parseCsvLine(lines.first);
    final stageCol = _findColumn(header, ['stage', 'stageid', 'stage_id', 'id']);
    final audioCol = _findColumn(header, ['audio', 'audiopath', 'audio_path', 'path', 'file']);
    final busCol = _findColumn(header, ['bus', 'routing', 'channel']);

    if (stageCol < 0) {
      warnings.add('CSV missing required "stage" column. Found: ${header.join(", ")}');
      return BulkImportResult(
        mappings: mappings,
        unmatched: unmatched,
        warnings: warnings,
        method: ImportMethod.csvFile,
      );
    }

    if (audioCol < 0) {
      warnings.add('CSV missing required "audio" column. Found: ${header.join(", ")}');
      return BulkImportResult(
        mappings: mappings,
        unmatched: unmatched,
        warnings: warnings,
        method: ImportMethod.csvFile,
      );
    }

    // Get valid stages
    Set<String> validStages = {};
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      final composer = GetIt.instance<FeatureComposerProvider>();
      validStages = composer.composedStages.map((s) => s.id).toSet();
    }

    // Parse data rows
    for (int i = 1; i < lines.length; i++) {
      final cols = _parseCsvLine(lines[i]);
      if (cols.length <= stageCol || cols.length <= audioCol) {
        warnings.add('Line ${i + 1}: not enough columns (${cols.length})');
        continue;
      }

      final stageId = cols[stageCol].trim().toUpperCase();
      var audioPath = cols[audioCol].trim();
      final bus = busCol >= 0 && cols.length > busCol ? cols[busCol].trim() : null;

      // Resolve relative path
      if (basePath != null && !audioPath.startsWith('/')) {
        audioPath = '$basePath/$audioPath';
      }

      // Validate stage
      if (validStages.isNotEmpty && !validStages.contains(stageId)) {
        warnings.add('Line ${i + 1}: stage "$stageId" not found in composed stages');
        unmatched.add(UnmatchedImportFile(
          fileName: _fileName(audioPath),
          filePath: audioPath,
          suggestions: [StageSuggestion(
            stage: stageId,
            confidence: 0.5,
            reason: 'Stage from CSV but not in current config',
          )],
        ));
        continue;
      }

      mappings.add(AudioMappingEntry(
        stageId: stageId,
        audioPath: audioPath,
        bus: bus,
        confidence: 1.0,
        source: 'csv',
      ));
    }

    return BulkImportResult(
      mappings: mappings,
      unmatched: unmatched,
      warnings: warnings,
      method: ImportMethod.csvFile,
    );
  }

  /// Import from CSV file path
  Future<BulkImportResult> importCsvFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final basePath = file.parent.path;
      return importCsv(content, basePath: basePath);
    } catch (e) {
      return BulkImportResult(
        mappings: const [],
        unmatched: const [],
        warnings: ['Failed to read CSV: $e'],
        method: ImportMethod.csvFile,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METHOD 3: JSON IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse a JSON mapping file.
  ///
  /// Expected format:
  /// ```json
  /// {
  ///   "mappings": [
  ///     {"stage": "REEL_STOP_0", "audio": "reel_stop_0.wav", "bus": "reels"},
  ///     {"stage": "CASCADE_START", "audio": "cascade_start.wav"}
  ///   ]
  /// }
  /// ```
  ///
  /// [basePath] is prepended to relative audio paths.
  BulkImportResult importJson(Map<String, dynamic> json, {String? basePath}) {
    final mappings = <AudioMappingEntry>[];
    final unmatched = <UnmatchedImportFile>[];
    final warnings = <String>[];

    final rawMappings = json['mappings'] as List<dynamic>?;
    if (rawMappings == null || rawMappings.isEmpty) {
      warnings.add('JSON has no "mappings" array');
      return BulkImportResult(
        mappings: mappings,
        unmatched: unmatched,
        warnings: warnings,
        method: ImportMethod.jsonFile,
      );
    }

    // Get valid stages
    Set<String> validStages = {};
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      final composer = GetIt.instance<FeatureComposerProvider>();
      validStages = composer.composedStages.map((s) => s.id).toSet();
    }

    for (int i = 0; i < rawMappings.length; i++) {
      final entry = rawMappings[i] as Map<String, dynamic>?;
      if (entry == null) {
        warnings.add('Entry $i: invalid format');
        continue;
      }

      final stageId = (entry['stage'] as String?)?.trim().toUpperCase();
      var audioPath = (entry['audio'] as String? ?? entry['audioPath'] as String?)?.trim();
      final bus = entry['bus'] as String?;

      if (stageId == null || stageId.isEmpty) {
        warnings.add('Entry $i: missing "stage" field');
        continue;
      }

      if (audioPath == null || audioPath.isEmpty) {
        warnings.add('Entry $i ($stageId): missing "audio" field');
        continue;
      }

      // Resolve relative path
      if (basePath != null && !audioPath.startsWith('/')) {
        audioPath = '$basePath/$audioPath';
      }

      // Validate stage
      if (validStages.isNotEmpty && !validStages.contains(stageId)) {
        warnings.add('Entry $i: stage "$stageId" not in composed stages');
        unmatched.add(UnmatchedImportFile(
          fileName: _fileName(audioPath),
          filePath: audioPath,
          suggestions: [StageSuggestion(
            stage: stageId,
            confidence: 0.5,
            reason: 'Stage from JSON but not in current config',
          )],
        ));
        continue;
      }

      mappings.add(AudioMappingEntry(
        stageId: stageId,
        audioPath: audioPath,
        bus: bus,
        confidence: 1.0,
        source: 'json',
      ));
    }

    return BulkImportResult(
      mappings: mappings,
      unmatched: unmatched,
      warnings: warnings,
      method: ImportMethod.jsonFile,
    );
  }

  /// Import from JSON file path
  Future<BulkImportResult> importJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final json = _parseJson(content);
      if (json == null) {
        return BulkImportResult(
          mappings: const [],
          unmatched: const [],
          warnings: ['Failed to parse JSON'],
          method: ImportMethod.jsonFile,
        );
      }
      final basePath = file.parent.path;
      return importJson(json, basePath: basePath);
    } catch (e) {
      return BulkImportResult(
        mappings: const [],
        unmatched: const [],
        warnings: ['Failed to read JSON: $e'],
        method: ImportMethod.jsonFile,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT (save current mappings)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export current audio assignments as CSV
  String exportCsv(Map<String, String> audioAssignments) {
    final buffer = StringBuffer('stage,audio\n');
    final sorted = audioAssignments.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in sorted) {
      buffer.writeln('${entry.key},${entry.value}');
    }
    return buffer.toString();
  }

  /// Export current audio assignments as JSON
  Map<String, dynamic> exportJson(Map<String, String> audioAssignments) {
    final sorted = audioAssignments.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {
      'version': '1.0',
      'mappings': sorted.map((e) => {
        'stage': e.key,
        'audio': e.value,
      }).toList(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Try to directly match a filename against composed stage IDs
  /// (e.g. "cascade_start.wav" → "CASCADE_START")
  String? _tryDirectMatch(String path, Set<String> stageIds) {
    if (stageIds.isEmpty) return null;
    final name = _fileName(path).toUpperCase().replaceAll(RegExp(r'[-\s]+'), '_');
    for (final stageId in stageIds) {
      if (name == stageId || name.contains(stageId) || stageId.contains(name)) {
        return stageId;
      }
    }
    return null;
  }

  /// Extract filename without extension
  String _fileName(String path) {
    final parts = path.split('/');
    final fileName = parts.isNotEmpty ? parts.last : path;
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  /// Parse a CSV line (handles quoted fields)
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  /// Find column index by name variants
  int _findColumn(List<String> header, List<String> variants) {
    for (int i = 0; i < header.length; i++) {
      final normalized = header[i].trim().toLowerCase().replaceAll(RegExp(r'[-_\s]+'), '');
      for (final variant in variants) {
        if (normalized == variant) return i;
      }
    }
    return -1;
  }

  /// Parse JSON string
  Map<String, dynamic>? _parseJson(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }
}

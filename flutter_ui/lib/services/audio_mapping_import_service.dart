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
import 'variant_manager.dart';

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
  /// Uses intelligent token-based matching with industry-standard aliases.
  ///
  /// Handles real slot audio naming conventions:
  /// - Numeric prefixes: "004_quick_win_1of8_1" → strips "004_"
  /// - Variant notation: "1of8_1", "2of3_3" → variant info, stripped for matching
  /// - CamelCase: "BigWinStart" → ["big", "win", "start"]
  /// - Compound names: "spins_loop_1of3_3" → tokens ["spins", "loop"]
  /// - Industry aliases: "quick_win" → WIN_SMALL, "base_game" → base game music
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

    // Build stage token index for fast lookup
    final stageTokenIndex = _buildStageTokenIndex(composedStageIds);

    // Track assigned stages — allow variants (multiple files per stage)
    final assignedStages = <String, List<String>>{}; // stage → [paths]

    for (final path in audioPaths) {
      final result = _intelligentMatch(path, composedStageIds, stageTokenIndex);

      if (result != null) {
        final existing = assignedStages[result.stageId];
        if (existing != null) {
          // Allow variants — first match becomes primary, rest are variants
          warnings.add('Variant: "${_fileName(path)}" → ${result.stageId} (${existing.length + 1} variants)');
        }
        mappings.add(result);
        assignedStages.putIfAbsent(result.stageId, () => []).add(path);
      } else {
        // Try legacy StageGroupService as fallback
        final legacyMatch = StageGroupService.instance.matchSingleFile(path);
        if (legacyMatch != null) {
          final stageValid = composedStageIds.isEmpty ||
              composedStageIds.contains(legacyMatch.stage);
          if (stageValid) {
            mappings.add(AudioMappingEntry(
              stageId: legacyMatch.stage,
              audioPath: path,
              confidence: legacyMatch.confidence * 0.8, // Lower confidence for legacy
              source: 'fuzzy',
            ));
            assignedStages.putIfAbsent(legacyMatch.stage, () => []).add(path);
          } else {
            unmatched.add(UnmatchedImportFile(
              fileName: _fileName(path),
              filePath: path,
              suggestions: [StageSuggestion(
                stage: legacyMatch.stage,
                confidence: legacyMatch.confidence,
                reason: 'Matched but mechanic not enabled',
              )],
            ));
          }
        } else {
          unmatched.add(UnmatchedImportFile(
            fileName: _fileName(path),
            filePath: path,
          ));
        }
      }
    }

    // Sort by confidence (highest first)
    mappings.sort((a, b) => b.confidence.compareTo(a.confidence));

    // ═══════════════════════════════════════════════════════════════════════════
    // AUTO-VARIANT REGISTRATION
    // When multiple files match the same stage, register them as variants
    // (random playback by default). First file becomes the primary assignment,
    // additional files become weighted variants.
    // ═══════════════════════════════════════════════════════════════════════════
    final variantManager = VariantManager.instance;
    for (final entry in assignedStages.entries) {
      final stageId = entry.key;
      final paths = entry.value;
      if (paths.length > 1) {
        // Clear existing variants for this stage
        variantManager.clearStage(stageId);
        // Register all files as variants (random mode by default)
        for (final p in paths) {
          variantManager.addVariant(stageId, AudioVariant(
            path: p,
            name: _fileName(p),
          ));
        }
        warnings.add('${paths.length} variants registered for $stageId (random playback)');
      }
    }

    // Coverage warning
    if (composedStageIds.isNotEmpty) {
      final coveredStages = assignedStages.keys.toSet();
      final uncovered = composedStageIds.difference(coveredStages);
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

  // ═══════════════════════════════════════════════════════════════════════════
  // INTELLIGENT MATCHING ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Core intelligent matcher — tokenizes filename, applies aliases, scores against stages
  AudioMappingEntry? _intelligentMatch(
    String path,
    Set<String> composedStageIds,
    Map<String, Set<String>> stageTokenIndex,
  ) {
    if (composedStageIds.isEmpty) return null;

    final rawName = _fileName(path);
    final tokens = _tokenizeFilename(rawName);
    if (tokens.isEmpty) return null;

    // PASS 1: Check industry alias map for compound patterns
    final aliasMatch = _checkAliasMap(tokens, composedStageIds);
    if (aliasMatch != null) {
      return AudioMappingEntry(
        stageId: aliasMatch.$1,
        audioPath: path,
        confidence: aliasMatch.$2,
        source: 'fuzzy',
      );
    }

    // PASS 2: Direct token→stage matching (tokens join to stage name)
    final directMatch = _tokenDirectMatch(tokens, composedStageIds);
    if (directMatch != null) {
      return AudioMappingEntry(
        stageId: directMatch.$1,
        audioPath: path,
        confidence: directMatch.$2,
        source: 'fuzzy',
      );
    }

    // PASS 3: Token overlap scoring against stage token index
    final overlapMatch = _tokenOverlapMatch(tokens, composedStageIds, stageTokenIndex);
    if (overlapMatch != null) {
      return AudioMappingEntry(
        stageId: overlapMatch.$1,
        audioPath: path,
        confidence: overlapMatch.$2,
        source: 'fuzzy',
      );
    }

    return null;
  }

  /// Tokenize a filename into meaningful words.
  ///
  /// Handles:
  /// - Strip numeric prefix: "004_quick_win" → ["quick", "win"]
  /// - Strip variant suffix: "1of8_1", "2of3_3" → removed
  /// - Split camelCase: "BigWinStart" → ["big", "win", "start"]
  /// - Split separators: "spins_loop" → ["spins", "loop"]
  /// - Normalize plurals: "spins" → also matches "spin"
  List<String> _tokenizeFilename(String rawName) {
    // Step 1: Strip numeric-only prefix (e.g., "004_" or "01_")
    var name = rawName.replaceFirst(RegExp(r'^\d{1,4}[_\-]'), '');

    // Step 2: Strip variant notation at end (e.g., "_1of8_1", "_2of3_3")
    name = name.replaceAll(RegExp(r'_?\d+of\d+(_\d+)?$'), '');

    // Step 3: Strip trailing variant number (e.g., "_1", "_03") if preceded by text
    name = name.replaceFirst(RegExp(r'_\d{1,2}$'), '');

    // Step 4: Split camelCase BEFORE lowercasing
    // "BigWinStart" → "Big Win Start"
    name = name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]}_${m[2]}',
    );
    // Also handle sequences like "BGMusicLoop" → "BG Music Loop"
    name = name.replaceAllMapped(
      RegExp(r'([A-Z]+)([A-Z][a-z])'),
      (m) => '${m[1]}_${m[2]}',
    );

    // Step 4b: Split letter→digit boundaries (keeps "Nx" multipliers intact)
    // "win1x" → "win_1x", "rollup2" → "rollup_2"
    name = name.replaceAllMapped(
      RegExp(r'([a-zA-Z])(\d)'),
      (m) => '${m[1]}_${m[2]}',
    );
    // Split digit→letter ONLY when not followed by 'x' (multiplier) or 'of' (variant)
    name = name.replaceAllMapped(
      RegExp(r'(\d)([a-zA-Z])'),
      (m) {
        final letter = m[2]!;
        // Keep "Nx" together (1x, 10x, etc.) and "NofM" (1of8, 2of3)
        if (letter.toLowerCase() == 'x' || letter.toLowerCase() == 'o') {
          return '${m[1]}${m[2]}';
        }
        return '${m[1]}_${m[2]}';
      },
    );

    // Step 5: Lowercase and split on separators
    final parts = name.toLowerCase().split(RegExp(r'[-_\s.]+'));

    // Step 6: Filter out empty strings and pure numbers (but keep Nx multipliers like "1x", "10x")
    final tokens = parts
        .where((t) => t.isNotEmpty && (!RegExp(r'^\d+$').hasMatch(t) || RegExp(r'^\d+x$', caseSensitive: false).hasMatch(t)))
        .toList();

    return tokens;
  }

  /// Build a token index from stage IDs for fast lookup
  /// E.g., "REEL_STOP_0" → {"reel", "stop", "0"}
  Map<String, Set<String>> _buildStageTokenIndex(Set<String> stageIds) {
    final index = <String, Set<String>>{};
    for (final stageId in stageIds) {
      final tokens = stageId.toLowerCase().split('_').where((t) => t.isNotEmpty).toSet();
      index[stageId] = tokens;
    }
    return index;
  }

  /// PASS 1: Check compound alias patterns against industry-standard names
  (String stageId, double confidence)? _checkAliasMap(
    List<String> tokens,
    Set<String> composedStageIds,
  ) {
    final joined = tokens.join(' ');
    final joinedNoSpace = tokens.join('');

    // Try each alias pattern — longest match first (more specific = higher priority)
    final sortedAliases = _aliasPatterns.entries.toList()
      ..sort((a, b) => b.key.split(' ').length.compareTo(a.key.split(' ').length));

    for (final entry in sortedAliases) {
      final pattern = entry.key;
      final candidates = entry.value;
      final patternNoSpace = pattern.replaceAll(' ', '');

      // Match against both spaced and joined token forms
      if (_matchesPattern(joined, tokens, pattern) ||
          joinedNoSpace.contains(patternNoSpace)) {
        // Find first candidate that exists in composed stages
        for (final candidate in candidates) {
          if (composedStageIds.contains(candidate)) {
            return (candidate, 0.85);
          }
        }
      }
    }
    return null;
  }

  /// Check if tokens match an alias pattern (supports multi-word patterns)
  bool _matchesPattern(String joined, List<String> tokens, String pattern) {
    final patternParts = pattern.split(' ');

    // All pattern parts must be present in tokens (order-independent)
    for (final part in patternParts) {
      bool found = false;
      for (final token in tokens) {
        // Support plural/singular matching
        if (token == part ||
            token == '${part}s' ||
            '${token}s' == part ||
            token.startsWith(part) ||
            part.startsWith(token)) {
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  /// PASS 2: Try to reconstruct a stage ID from tokens
  /// "spins_stop" → try "SPINS_STOP", "SPIN_STOP", etc. against composed stages
  (String stageId, double confidence)? _tokenDirectMatch(
    List<String> tokens,
    Set<String> composedStageIds,
  ) {
    // Try joining tokens in order → stage ID
    final direct = tokens.join('_').toUpperCase();
    if (composedStageIds.contains(direct)) {
      return (direct, 0.95);
    }

    // Try with singularized tokens
    final singular = tokens.map(_singularize).toList();
    final singularDirect = singular.join('_').toUpperCase();
    if (composedStageIds.contains(singularDirect)) {
      return (singularDirect, 0.90);
    }

    // Try subsequences (2+ consecutive tokens)
    for (int len = tokens.length; len >= 2; len--) {
      for (int start = 0; start <= tokens.length - len; start++) {
        final sub = tokens.sublist(start, start + len).join('_').toUpperCase();
        if (composedStageIds.contains(sub)) {
          return (sub, 0.85);
        }
        // Singularized
        final subSingular = tokens.sublist(start, start + len)
            .map(_singularize).join('_').toUpperCase();
        if (composedStageIds.contains(subSingular)) {
          return (subSingular, 0.80);
        }
      }
    }

    return null;
  }

  /// PASS 3: Score each stage by token overlap
  (String stageId, double confidence)? _tokenOverlapMatch(
    List<String> tokens,
    Set<String> composedStageIds,
    Map<String, Set<String>> stageTokenIndex,
  ) {
    String? bestStage;
    double bestScore = 0.0;

    // Expand tokens with singulars for matching
    final expandedTokens = <String>{};
    for (final t in tokens) {
      expandedTokens.add(t);
      expandedTokens.add(_singularize(t));
      // Add common abbreviations
      final abbr = _abbreviations[t];
      if (abbr != null) expandedTokens.addAll(abbr);
    }

    for (final entry in stageTokenIndex.entries) {
      final stageId = entry.key;
      final stageTokens = entry.value;

      // Count how many stage tokens are matched by file tokens
      int matched = 0;
      for (final st in stageTokens) {
        if (expandedTokens.contains(st) || expandedTokens.contains(_singularize(st))) {
          matched++;
        }
      }

      if (matched == 0) continue;

      // Score: matched/total stage tokens, penalized by extra file tokens
      final coverage = matched / stageTokens.length;
      final precision = matched / expandedTokens.length.clamp(1, 100);
      final score = coverage * 0.7 + precision * 0.3;

      // Require at least 50% coverage of stage tokens
      if (score > bestScore && coverage >= 0.5) {
        bestScore = score;
        bestStage = stageId;
      }
    }

    if (bestStage != null && bestScore >= 0.3) {
      return (bestStage, bestScore.clamp(0.2, 0.75));
    }
    return null;
  }

  /// Singularize common English words used in slot audio
  String _singularize(String word) {
    if (word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
    if (word.endsWith('ses')) return word.substring(0, word.length - 2);
    if (word.endsWith('s') && !word.endsWith('ss')) return word.substring(0, word.length - 1);
    return word;
  }

  /// Industry-standard slot audio naming → stage ID mapping.
  /// Patterns are space-separated tokens (all must be present, order-independent).
  /// Values are candidate stage IDs (first match in composed stages wins).
  static const Map<String, List<String>> _aliasPatterns = {
    // ─── SPINS & REELS ──────────────────────────────────────────────
    'spin start': ['SPIN_START'],
    'spin button': ['SPIN_START'],
    'spin click': ['SPIN_START'],
    'spin press': ['SPIN_START'],
    'spin loop': ['REEL_SPIN'],
    'spins loop': ['REEL_SPIN'],
    'reel spin': ['REEL_SPIN'],
    'reel loop': ['REEL_SPIN'],
    'spinning': ['REEL_SPIN'],
    'spin stop': ['REEL_STOP'],
    'spins stop': ['REEL_STOP'],
    'reel stop': ['REEL_STOP'],
    'reel land': ['REEL_STOP'],
    'spin end': ['SPIN_END'],

    // ─── WINS ────────────────────────────────────────────────────────
    'quick win': ['WIN_SMALL', 'WIN_PRESENT'],
    'small win': ['WIN_SMALL'],
    'normal win': ['WIN_MEDIUM', 'WIN_PRESENT'],
    'medium win': ['WIN_MEDIUM'],
    'big win': ['WIN_BIG'],
    'bigwin': ['WIN_BIG'],
    'mega win': ['WIN_MEGA'],
    'megawin': ['WIN_MEGA'],
    'epic win': ['WIN_EPIC'],
    'super win': ['WIN_EPIC', 'WIN_ULTRA'],
    'ultra win': ['WIN_ULTRA'],
    'max win': ['WIN_ULTRA'],
    'win start': ['WIN_PRESENT'],
    'win end': ['WIN_PRESENT'],
    'win show': ['WIN_PRESENT'],
    'win line': ['WIN_LINE_SHOW'],

    // ─── WIN multiplier tiers (win1x, win2x, win5x, win10x, etc.) ───
    'win1x': ['WIN_SMALL', 'WIN_PRESENT'],
    'win 1x': ['WIN_SMALL', 'WIN_PRESENT'],
    'win2x': ['WIN_SMALL', 'WIN_PRESENT'],
    'win 2x': ['WIN_SMALL', 'WIN_PRESENT'],
    'win3x': ['WIN_MEDIUM'],
    'win 3x': ['WIN_MEDIUM'],
    'win5x': ['WIN_MEDIUM'],
    'win 5x': ['WIN_MEDIUM'],
    'win10x': ['WIN_BIG'],
    'win 10x': ['WIN_BIG'],
    'win15x': ['WIN_BIG'],
    'win 15x': ['WIN_BIG'],
    'win20x': ['WIN_MEGA'],
    'win 20x': ['WIN_MEGA'],
    'win25x': ['WIN_MEGA'],
    'win50x': ['WIN_EPIC'],
    'win100x': ['WIN_ULTRA'],

    // ─── ROLLUP variants (rollupLow, rollupMed, rollupHigh, etc.) ───
    'rollup': ['ROLLUP_TICK', 'ROLLUP_START'],
    'roll up': ['ROLLUP_TICK', 'ROLLUP_START'],
    'rollup low': ['ROLLUP_START', 'ROLLUP_TICK'],
    'rollupl': ['ROLLUP_START', 'ROLLUP_TICK'],
    'rollup med': ['ROLLUP_TICK'],
    'rollupm': ['ROLLUP_TICK'],
    'rollup high': ['ROLLUP_END', 'ROLLUP_TICK'],
    'rolluph': ['ROLLUP_END', 'ROLLUP_TICK'],
    'rollup end': ['ROLLUP_END'],
    'rollup start': ['ROLLUP_START'],
    'count up': ['ROLLUP_TICK'],
    'totalizer': ['ROLLUP_TICK'],

    // ─── WIN with Start/End modifiers ────────────────────────────────
    'big win start': ['WIN_BIG'],
    'big win end': ['WIN_BIG'],
    'mega win start': ['WIN_MEGA'],
    'mega win end': ['WIN_MEGA'],
    'epic win start': ['WIN_EPIC'],
    'ultra win start': ['WIN_ULTRA'],

    // ─── MUSIC ───────────────────────────────────────────────────────
    'base game music': ['BASE_MUSIC', 'MUSIC_BASE', 'MUSIC_LOOP'],
    'base game loop': ['BASE_MUSIC', 'MUSIC_BASE', 'MUSIC_LOOP'],
    'base music': ['BASE_MUSIC', 'MUSIC_BASE', 'MUSIC_LOOP'],
    'bg music': ['BASE_MUSIC', 'MUSIC_BASE', 'MUSIC_LOOP'],
    'background music': ['BASE_MUSIC', 'MUSIC_BASE', 'MUSIC_LOOP'],
    'music loop': ['MUSIC_LOOP', 'BASE_MUSIC'],
    'music base': ['MUSIC_BASE', 'BASE_MUSIC', 'MUSIC_LOOP'],
    'ambient': ['AMBIENT_LOOP', 'AMBIENCE'],
    'ambience': ['AMBIENT_LOOP', 'AMBIENCE'],
    'stinger': ['STINGER', 'MUSIC_STINGER'],

    // ─── FREE SPINS ──────────────────────────────────────────────────
    'free spin': ['FS_TRIGGER', 'FREE_SPINS_TRIGGER'],
    'free spins': ['FS_TRIGGER', 'FREE_SPINS_TRIGGER'],
    'fs trigger': ['FS_TRIGGER', 'FREE_SPINS_TRIGGER'],
    'fs start': ['FS_START', 'FREE_SPINS_START'],
    'fs end': ['FS_END', 'FREE_SPINS_END'],
    'fs music': ['FS_MUSIC', 'FREE_SPINS_MUSIC'],
    'fs loop': ['FS_MUSIC', 'FREE_SPINS_MUSIC'],
    'free spin music': ['FS_MUSIC', 'FREE_SPINS_MUSIC'],
    'free spin trigger': ['FS_TRIGGER', 'FREE_SPINS_TRIGGER'],
    'retrigger': ['FS_RETRIGGER', 'FREE_SPINS_RETRIGGER'],

    // ─── BONUS ───────────────────────────────────────────────────────
    'bonus': ['BONUS_TRIGGER', 'BONUS_START'],
    'bonus start': ['BONUS_START', 'BONUS_TRIGGER'],
    'bonus end': ['BONUS_END', 'BONUS_COMPLETE'],
    'bonus win': ['BONUS_WIN', 'BONUS_AWARD'],
    'pick bonus': ['PICK_SELECT', 'BONUS_TRIGGER'],
    'wheel spin': ['WHEEL_SPIN'],
    'wheel stop': ['WHEEL_STOP'],

    // ─── HOLD AND WIN ────────────────────────────────────────────────
    'hold win': ['HNW_TRIGGER', 'HOLD_AND_WIN_TRIGGER'],
    'hnw': ['HNW_TRIGGER', 'HOLD_AND_WIN_TRIGGER'],
    'lock': ['HNW_LOCK', 'HOLD_AND_WIN_LOCK'],
    'coin land': ['HNW_COIN_LAND'],
    'respin': ['HNW_RESPIN', 'RESPIN_START'],

    // ─── CASCADE ─────────────────────────────────────────────────────
    'cascade': ['CASCADE_START', 'CASCADE_TRIGGER'],
    'tumble': ['CASCADE_START', 'CASCADE_TRIGGER'],
    'avalanche': ['CASCADE_START'],
    'cascade fill': ['CASCADE_FILL'],
    'cascade end': ['CASCADE_END'],

    // ─── JACKPOT ─────────────────────────────────────────────────────
    'jackpot': ['JACKPOT_TRIGGER'],
    'jackpot trigger': ['JACKPOT_TRIGGER'],
    'jackpot win': ['JACKPOT_AWARD'],
    'jackpot mini': ['JACKPOT_MINI'],
    'jackpot minor': ['JACKPOT_MINOR'],
    'jackpot major': ['JACKPOT_MAJOR'],
    'jackpot grand': ['JACKPOT_GRAND'],

    // ─── GAMBLE ──────────────────────────────────────────────────────
    'gamble': ['GAMBLE_START'],
    'double': ['GAMBLE_START'],
    'gamble win': ['GAMBLE_WIN'],
    'gamble lose': ['GAMBLE_LOSE'],

    // ─── ANTICIPATION ────────────────────────────────────────────────
    'anticipation': ['ANTICIPATION_ON', 'ANTIC_TENSION_L1'],
    'tension': ['ANTIC_TENSION_L1', 'ANTICIPATION_ON'],
    'near miss': ['ANTIC_NEAR_MISS'],
    'heartbeat': ['ANTIC_HEARTBEAT'],

    // ─── WILDS ───────────────────────────────────────────────────────
    'wild': ['WILD_LAND'],
    'wild expand': ['WILD_EXPAND'],
    'wild land': ['WILD_LAND'],
    'wild sticky': ['WILD_STICKY'],
    'scatter': ['SCATTER_LAND'],
    'scatter land': ['SCATTER_LAND'],

    // ─── SYMBOLS ─────────────────────────────────────────────────────
    'symbol land': ['SYMBOL_LAND'],

    // ─── UI ──────────────────────────────────────────────────────────
    'button': ['UI_BUTTON_PRESS'],
    'ui click': ['UI_BUTTON_PRESS'],
    'hover': ['UI_BUTTON_HOVER'],
    'menu open': ['UI_PANEL_OPEN'],
    'menu close': ['UI_PANEL_CLOSE'],
    'notification': ['UI_NOTIFICATION'],

    // ─── TRANSITIONS ─────────────────────────────────────────────────
    'transition': ['TRANSITION_TO_BASE'],
    'swoosh': ['TRANSITION_SWOOSH'],
    'whoosh': ['TRANSITION_SWOOSH'],
    'impact': ['TRANSITION_IMPACT'],
    'reveal': ['TRANSITION_REVEAL'],

    // ─── COLLECT ─────────────────────────────────────────────────────
    'collect': ['COLLECT_TRIGGER', 'COLLECT_COIN'],
    'coin collect': ['COLLECT_COIN'],
    'meter': ['COLLECT_METER_FILL'],
  };

  /// Common abbreviations used in slot audio filenames
  static const Map<String, List<String>> _abbreviations = {
    'fs': ['free', 'spins', 'freespin'],
    'hnw': ['hold', 'win'],
    'bg': ['base', 'game', 'background'],
    'sfx': ['sound', 'effect'],
    'jp': ['jackpot'],
    'ui': ['button', 'interface'],
    'vo': ['voice', 'voiceover'],
    'amb': ['ambient', 'ambience'],
    'mus': ['music'],
    'antic': ['anticipation'],
  };

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

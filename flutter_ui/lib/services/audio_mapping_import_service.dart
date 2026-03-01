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

    // Use StageGroupService batch matching — handles XofY naming, indexing
    // convention detection, and has well-tested exclude/keyword logic.
    final batchResult = StageGroupService.instance.matchFilesToStages(
      audioPaths: audioPaths,
    );

    // Track assigned stages — allow variants (multiple files per stage)
    final assignedStages = <String, List<String>>{}; // stage → [paths]

    for (final match in batchResult.matched) {
      final existing = assignedStages[match.stage];
      if (existing != null) {
        warnings.add('Variant: "${match.audioFileName}" → ${match.stage} (${existing.length + 1} variants)');
      }
      mappings.add(AudioMappingEntry(
        stageId: match.stage,
        audioPath: match.audioPath,
        confidence: match.confidence,
        source: 'fuzzy',
      ));
      assignedStages.putIfAbsent(match.stage, () => []).add(match.audioPath);
    }

    for (final um in batchResult.unmatched) {
      unmatched.add(UnmatchedImportFile(
        fileName: um.audioFileName,
        filePath: um.audioPath,
        suggestions: um.suggestions,
      ));
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

  /// Extract NofM variant info from raw filename BEFORE tokenization.
  /// Returns (variantIndex 0-based, totalVariants) or null.
  /// Examples: "spins_stop_1of5_2" → (0, 5), "spins_stop_3of5_1" → (2, 5)
  (int index, int total)? _extractNofM(String rawName) {
    final match = RegExp(r'(\d+)of(\d+)').firstMatch(rawName);
    if (match == null) return null;
    final n = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    if (n == null || m == null || n < 1 || m < 1) return null;
    return (n - 1, m); // Convert to 0-based index
  }

  /// Core intelligent matcher — tokenizes filename, applies aliases, scores against stages
  AudioMappingEntry? _intelligentMatch(
    String path,
    Set<String> composedStageIds,
    Map<String, Set<String>> stageTokenIndex,
  ) {
    if (composedStageIds.isEmpty) return null;

    final rawName = _fileName(path);

    // PRE-PASS: Extract NofM variant info for indexed stage matching
    // e.g. "spins_stop_1of5_2" → variantIndex=0 (for REEL_STOP_0)
    final nofm = _extractNofM(rawName);

    final tokens = _tokenizeFilename(rawName);
    if (tokens.isEmpty) return null;

    // PASS 1: Check industry alias map for compound patterns
    final aliasMatch = _checkAliasMap(tokens, composedStageIds, nofm);
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
  /// [nofm] is the NofM variant info (0-based index, total) for indexed stage expansion.
  (String stageId, double confidence)? _checkAliasMap(
    List<String> tokens,
    Set<String> composedStageIds,
    (int, int)? nofm,
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
          // Indexed stage expansion: "REEL_STOP_*" with NofM → "REEL_STOP_0", "REEL_STOP_1"...
          if (candidate.endsWith('_*') && nofm != null) {
            final base = candidate.substring(0, candidate.length - 1); // "REEL_STOP_"
            final indexed = '$base${nofm.$1}';
            if (composedStageIds.contains(indexed)) {
              return (indexed, 0.90);
            }
          } else if (candidate.endsWith('_*')) {
            // No NofM info — try _0 as default
            final base = candidate.substring(0, candidate.length - 1);
            final defaulted = '${base}0';
            if (composedStageIds.contains(defaulted)) {
              return (defaulted, 0.80);
            }
          } else if (composedStageIds.contains(candidate)) {
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
  /// Industry alias patterns → actual composed stage IDs.
  ///
  /// Patterns ending with `_*` are INDEXED: expanded using NofM variant notation.
  /// E.g. "spins_stop_1of5_2" → NofM=(0,5) → "REEL_STOP_*" → "REEL_STOP_0"
  ///
  /// Candidates are tried in order — first match in composed stages wins.
  static const Map<String, List<String>> _aliasPatterns = {
    // ═══════════════════════════════════════════════════════════════════
    // SPIN BUTTON (user presses spin) → SPIN_START
    // ═══════════════════════════════════════════════════════════════════
    'spin button': ['SPIN_START'],
    'spin click': ['SPIN_START'],
    'spin press': ['SPIN_START'],
    'spin start': ['SPIN_START'],
    'ui spin': ['SPIN_START'],

    // ═══════════════════════════════════════════════════════════════════
    // REEL SPINNING (loop while reels rotate) → REEL_SPIN_LOOP
    // ═══════════════════════════════════════════════════════════════════
    'spin loop': ['REEL_SPIN_LOOP'],
    'spins loop': ['REEL_SPIN_LOOP'],
    'reel spin': ['REEL_SPIN_LOOP'],
    'reel loop': ['REEL_SPIN_LOOP'],
    'spinning': ['REEL_SPIN_LOOP'],
    'reels spin': ['REEL_SPIN_LOOP'],
    'reel spinning': ['REEL_SPIN_LOOP'],

    // ═══════════════════════════════════════════════════════════════════
    // REEL STOP (individual reel landing) → REEL_STOP_* (indexed by NofM)
    // "spins_stop_1of5_2" → REEL_STOP_0, "spins_stop_3of5_1" → REEL_STOP_2
    // Without NofM → defaults to REEL_STOP_0
    // ═══════════════════════════════════════════════════════════════════
    'spin stop': ['REEL_STOP_*'],
    'spins stop': ['REEL_STOP_*'],
    'reel stop': ['REEL_STOP_*'],
    'reel land': ['REEL_STOP_*'],
    'reel end': ['REEL_STOP_*'],
    'stop': ['REEL_STOP_*'],
    'land': ['REEL_STOP_*', 'SYMBOL_LAND'],

    // ═══════════════════════════════════════════════════════════════════
    // SPIN END → SPIN_END
    // ═══════════════════════════════════════════════════════════════════
    'spin end': ['SPIN_END'],
    'spin complete': ['SPIN_END'],
    'spins end': ['SPIN_END'],

    // ═══════════════════════════════════════════════════════════════════
    // SYMBOL LAND → SYMBOL_LAND + typed variants
    // ═══════════════════════════════════════════════════════════════════
    'symbol land': ['SYMBOL_LAND'],
    'wild land': ['SYMBOL_LAND_WILD', 'WILD_EXPAND'],
    'wild symbol': ['SYMBOL_LAND_WILD'],
    'scatter land': ['SYMBOL_LAND_SCATTER'],
    'scatter symbol': ['SYMBOL_LAND_SCATTER'],
    'bonus land': ['SYMBOL_LAND_BONUS'],
    'bonus symbol land': ['SYMBOL_LAND_BONUS'],

    // ═══════════════════════════════════════════════════════════════════
    // WINS → WIN_TIER_1 through WIN_TIER_5
    // Tier 1 = small, Tier 2 = medium, Tier 3 = big, Tier 4 = mega, Tier 5 = epic
    // ═══════════════════════════════════════════════════════════════════
    'quick win': ['WIN_TIER_1'],
    'small win': ['WIN_TIER_1'],
    'normal win': ['WIN_TIER_2'],
    'medium win': ['WIN_TIER_2'],
    'big win': ['WIN_TIER_3'],
    'bigwin': ['WIN_TIER_3'],
    'mega win': ['WIN_TIER_4'],
    'megawin': ['WIN_TIER_4'],
    'epic win': ['WIN_TIER_5'],
    'super win': ['WIN_TIER_5'],
    'ultra win': ['WIN_TIER_5'],
    'max win': ['WIN_TIER_5'],
    'mega win start': ['WIN_TIER_4'],
    'epic win start': ['WIN_TIER_5'],
    'win start': ['WIN_TIER_1'],
    'win end': ['WIN_TIER_1'],
    'win show': ['WIN_TIER_1'],
    'win line': ['WIN_LINE_SHOW'],
    'win collect': ['WIN_COLLECT'],
    'win highlight': ['WIN_SYMBOL_HIGHLIGHT'],
    'symbol highlight': ['WIN_SYMBOL_HIGHLIGHT'],

    // ─── WIN multiplier tiers → WIN_TIER_N ──────────────────────────
    'win 1x': ['WIN_TIER_1'],
    'win1x': ['WIN_TIER_1'],
    'win 2x': ['WIN_TIER_1'],
    'win2x': ['WIN_TIER_1'],
    'win 3x': ['WIN_TIER_2'],
    'win3x': ['WIN_TIER_2'],
    'win 5x': ['WIN_TIER_2'],
    'win5x': ['WIN_TIER_2'],
    'win 10x': ['WIN_TIER_3'],
    'win10x': ['WIN_TIER_3'],
    'win 15x': ['WIN_TIER_3'],
    'win15x': ['WIN_TIER_3'],
    'win 20x': ['WIN_TIER_4'],
    'win20x': ['WIN_TIER_4'],
    'win 25x': ['WIN_TIER_4'],
    'win25x': ['WIN_TIER_4'],
    'win 50x': ['WIN_TIER_5'],
    'win50x': ['WIN_TIER_5'],
    'win 100x': ['WIN_TIER_5'],
    'win100x': ['WIN_TIER_5'],

    // ═══════════════════════════════════════════════════════════════════
    // ROLLUP / COUNTUP → COUNTUP_TICK, COUNTUP_END, ROLLUP_START/END
    // ═══════════════════════════════════════════════════════════════════
    'rollup': ['COUNTUP_TICK', 'ROLLUP_TICK'],
    'roll up': ['COUNTUP_TICK', 'ROLLUP_TICK'],
    'rollup low': ['COUNTUP_TICK', 'ROLLUP_START'],
    'rollupl': ['COUNTUP_TICK', 'ROLLUP_START'],
    'rollup med': ['COUNTUP_TICK', 'ROLLUP_TICK'],
    'rollupm': ['COUNTUP_TICK', 'ROLLUP_TICK'],
    'rollup high': ['COUNTUP_END', 'ROLLUP_END'],
    'rolluph': ['COUNTUP_END', 'ROLLUP_END'],
    'rollup end': ['COUNTUP_END', 'ROLLUP_END'],
    'rollup start': ['COUNTUP_TICK', 'ROLLUP_START'],
    'count up': ['COUNTUP_TICK'],
    'countup': ['COUNTUP_TICK'],
    'totalizer': ['COUNTUP_TICK'],

    // ═══════════════════════════════════════════════════════════════════
    // MUSIC → MUSIC_BASE, MUSIC_FREESPINS, etc. (matches UltimateAudioPanel)
    // ═══════════════════════════════════════════════════════════════════
    'base game music': ['MUSIC_BASE'],
    'base game loop': ['MUSIC_BASE'],
    'basegame music': ['MUSIC_BASE'],
    'basegame musicloop': ['MUSIC_BASE'],
    'base game musicloop': ['MUSIC_BASE'],
    'basegame music start': ['MUSIC_BASE'],
    'base music': ['MUSIC_BASE'],
    'bg music': ['MUSIC_BASE'],
    'bgm': ['MUSIC_BASE'],
    'background music': ['MUSIC_BASE'],
    'music loop': ['MUSIC_BASE'],
    'music base': ['MUSIC_BASE'],
    'music start': ['MUSIC_BASE'],
    'win music': ['MUSIC_BIG_WIN'],
    'feature music': ['MUSIC_FREESPINS'],
    'free spin music': ['MUSIC_FREESPINS'],
    'free spins music': ['MUSIC_FREESPINS'],
    'freespins music': ['MUSIC_FREESPINS'],
    'freespins music loop': ['MUSIC_FREESPINS'],
    'fs music': ['MUSIC_FREESPINS'],
    'bonus music': ['MUSIC_BONUS'],
    'hold music': ['MUSIC_HOLD'],
    'jackpot music': ['MUSIC_JACKPOT'],
    'gamble music': ['MUSIC_GAMBLE'],
    'ambient': ['AMBIENCE'],
    'ambience': ['AMBIENCE'],
    'stinger': ['MUSIC_STINGER_WIN'],
    'stinger win': ['MUSIC_STINGER_WIN'],
    'stinger feature': ['MUSIC_STINGER_FEATURE'],
    'stinger bonus': ['MUSIC_STINGER_BONUS'],
    'stinger jackpot': ['MUSIC_STINGER_JACKPOT'],

    // ═══════════════════════════════════════════════════════════════════
    // FREE SPINS → FEATURE_ENTER, FEATURE_LOOP, FEATURE_EXIT
    // ═══════════════════════════════════════════════════════════════════
    'free spin': ['FEATURE_ENTER'],
    'free spins': ['FEATURE_ENTER'],
    'fs trigger': ['FEATURE_ENTER'],
    'fs start': ['FEATURE_ENTER'],
    'fs end': ['FEATURE_EXIT'],
    'fs loop': ['FEATURE_LOOP'],
    'free spin trigger': ['FEATURE_ENTER'],
    'retrigger': ['FEATURE_ENTER'],

    // ═══════════════════════════════════════════════════════════════════
    // BONUS → PICK_START, PICK_REVEAL, PICK_END, WHEEL_*
    // ═══════════════════════════════════════════════════════════════════
    'bonus': ['PICK_START', 'FEATURE_ENTER'],
    'bonus start': ['PICK_START', 'FEATURE_ENTER'],
    'bonus end': ['PICK_END', 'FEATURE_EXIT'],
    'bonus win': ['PICK_REVEAL'],
    'pick bonus': ['PICK_START'],
    'pick reveal': ['PICK_REVEAL'],
    'wheel spin': ['WHEEL_SPIN'],
    'wheel start': ['WHEEL_START'],
    'wheel stop': ['WHEEL_RESULT'],
    'wheel result': ['WHEEL_RESULT'],

    // ═══════════════════════════════════════════════════════════════════
    // HOLD AND WIN → HOLD_WIN_LOCK, HOLD_WIN_SPIN, HOLD_WIN_REVEAL
    // ═══════════════════════════════════════════════════════════════════
    'hold win': ['HOLD_WIN_LOCK'],
    'hnw': ['HOLD_WIN_LOCK'],
    'lock': ['HOLD_WIN_LOCK'],
    'coin land': ['HOLD_WIN_LOCK'],
    'respin': ['HOLD_WIN_SPIN', 'RESPIN_START'],

    // ═══════════════════════════════════════════════════════════════════
    // CASCADE → CASCADE_START, CASCADE_STEP, CASCADE_END
    // ═══════════════════════════════════════════════════════════════════
    'cascade': ['CASCADE_START'],
    'tumble': ['CASCADE_START'],
    'avalanche': ['CASCADE_START'],
    'cascade step': ['CASCADE_STEP'],
    'cascade fill': ['CASCADE_STEP'],
    'cascade end': ['CASCADE_END'],

    // ═══════════════════════════════════════════════════════════════════
    // JACKPOT → JACKPOT_TRIGGER, JACKPOT_MINI, JACKPOT_MAJOR, JACKPOT_GRAND
    // ═══════════════════════════════════════════════════════════════════
    'jackpot': ['JACKPOT_TRIGGER'],
    'jackpot trigger': ['JACKPOT_TRIGGER'],
    'jackpot win': ['JACKPOT_TRIGGER'],
    'jackpot mini': ['JACKPOT_MINI'],
    'jackpot minor': ['JACKPOT_MINI'],
    'jackpot major': ['JACKPOT_MAJOR'],
    'jackpot grand': ['JACKPOT_GRAND'],

    // ═══════════════════════════════════════════════════════════════════
    // GAMBLE → GAMBLE_START, GAMBLE_WIN, GAMBLE_LOSE
    // ═══════════════════════════════════════════════════════════════════
    'gamble': ['GAMBLE_START'],
    'double': ['GAMBLE_START'],
    'gamble win': ['GAMBLE_WIN'],
    'gamble lose': ['GAMBLE_LOSE'],

    // ═══════════════════════════════════════════════════════════════════
    // ANTICIPATION → ANTICIPATION_ON
    // ═══════════════════════════════════════════════════════════════════
    'anticipation': ['ANTICIPATION_ON'],
    'tension': ['ANTICIPATION_ON'],
    'near miss': ['NEAR_MISS'],
    'nearmiss': ['NEAR_MISS'],

    // ═══════════════════════════════════════════════════════════════════
    // WILDS → WILD_EXPAND, WILD_STICKY
    // ═══════════════════════════════════════════════════════════════════
    'wild': ['SYMBOL_LAND_WILD', 'WILD_EXPAND'],
    'wild expand': ['WILD_EXPAND'],
    'wild sticky': ['WILD_STICKY'],
    'scatter': ['SYMBOL_LAND_SCATTER', 'SYMBOL_LAND'],

    // ═══════════════════════════════════════════════════════════════════
    // UI → BUTTON_PRESS, BUTTON_RELEASE, POPUP_SHOW, POPUP_DISMISS
    // ═══════════════════════════════════════════════════════════════════
    'button': ['BUTTON_PRESS'],
    'button press': ['BUTTON_PRESS'],
    'button release': ['BUTTON_RELEASE'],
    'ui click': ['BUTTON_PRESS'],
    'popup': ['POPUP_SHOW'],
    'menu open': ['POPUP_SHOW'],
    'menu close': ['POPUP_DISMISS'],
    'notification': ['POPUP_SHOW'],

    // ═══════════════════════════════════════════════════════════════════
    // TRANSITIONS / MISC
    // ═══════════════════════════════════════════════════════════════════
    'transition': ['FEATURE_ENTER'],
    'swoosh': ['FEATURE_ENTER'],
    'whoosh': ['FEATURE_ENTER'],
    'impact': ['SYMBOL_LAND'],
    'reveal': ['PICK_REVEAL', 'HOLD_WIN_REVEAL'],
    'collect': ['WIN_COLLECT'],
    'coin collect': ['WIN_COLLECT'],

    // ═══════════════════════════════════════════════════════════════════
    // NUDGE / RESPIN → REEL_NUDGE, RESPIN_START
    // ═══════════════════════════════════════════════════════════════════
    'nudge': ['REEL_NUDGE'],
    'respin start': ['RESPIN_START'],

    // ═══════════════════════════════════════════════════════════════════
    // MEGAWAYS → MEGAWAYS_REVEAL
    // ═══════════════════════════════════════════════════════════════════
    'megaways': ['MEGAWAYS_REVEAL'],
    'megaways reveal': ['MEGAWAYS_REVEAL'],

    // ═══════════════════════════════════════════════════════════════════
    // MULTIPLIER → MULTIPLIER_INCREMENT, MULTIPLIER_APPLY
    // ═══════════════════════════════════════════════════════════════════
    'multiplier': ['MULTIPLIER_INCREMENT'],
    'multiplier increment': ['MULTIPLIER_INCREMENT'],
    'multiplier apply': ['MULTIPLIER_APPLY'],

    // ═══════════════════════════════════════════════════════════════════
    // BIG WIN specific stages (used in tier progression)
    // ═══════════════════════════════════════════════════════════════════
    'big win intro': ['BIG_WIN_INTRO', 'WIN_TIER_3'],
    'big win loop': ['BIG_WIN_LOOP', 'WIN_TIER_3'],
    'big win coins': ['BIG_WIN_COINS', 'WIN_TIER_3'],
    'big win end': ['BIG_WIN_END', 'WIN_TIER_3'],
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

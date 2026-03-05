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
import 'package:flutter/foundation.dart' show debugPrint;
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
  /// Uses dual-engine matching: OWN intelligent token+alias pipeline FIRST,
  /// then falls back to StageGroupService for fuzzy keyword matching.
  ///
  /// Handles real slot audio naming conventions:
  /// - Numeric prefixes: "004_quick_win_1of8_1" → strips "004_"
  /// - Variant notation: "1of8_1", "2of3_3" → variant info, stripped for matching
  /// - CamelCase: "BigWinStart" → ["big", "win", "start"]
  /// - Compound names: "spins_loop_1of3_3" → tokens ["spins", "loop"]
  /// - Music layers: "mus_bg_lvl_3" → MUSIC_BASE_L3
  /// - Ambient scenes: "ambient_freespins" → AMBIENT_FS
  BulkImportResult matchFolder(List<String> audioPaths) {
    final mappings = <AudioMappingEntry>[];
    final unmatched = <UnmatchedImportFile>[];
    final warnings = <String>[];

    // Build composed stage set from FeatureComposer (or use all known stages)
    Set<String> composedStageIds = {};
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      final composer = GetIt.instance<FeatureComposerProvider>();
      composedStageIds = composer.composedStages.map((s) => s.id).toSet();
    }
    // If no composed stages, use all known stage IDs as fallback
    if (composedStageIds.isEmpty) {
      composedStageIds = _allKnownStageIds;
    }

    // Build token index for PASS 3 overlap scoring
    final stageTokenIndex = _buildStageTokenIndex(composedStageIds);

    // Track assigned stages — allow variants (multiple files per stage)
    final assignedStages = <String, List<String>>{}; // stage → [paths]

    // Paths that our engine couldn't match — will be sent to StageGroupService
    final unmatchedPaths = <String>[];

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 1: OWN INTELLIGENT MATCHING ENGINE (token + alias + overlap)
    // ═══════════════════════════════════════════════════════════════════════════
    for (final path in audioPaths) {
      final match = _intelligentMatch(path, composedStageIds, stageTokenIndex);
      if (match != null) {
        final existing = assignedStages[match.stageId];
        if (existing != null) {
          warnings.add('Variant: "${_fileName(path)}" → ${match.stageId} (${existing.length + 1} variants)');
        }
        mappings.add(match);
        assignedStages.putIfAbsent(match.stageId, () => []).add(match.audioPath);
      } else {
        unmatchedPaths.add(path);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 2: FALLBACK — StageGroupService fuzzy keyword matching
    // For files our engine couldn't match, try the fuzzy keyword engine
    // ═══════════════════════════════════════════════════════════════════════════
    if (unmatchedPaths.isNotEmpty) {
      final batchResult = StageGroupService.instance.matchFilesToStages(
        audioPaths: unmatchedPaths,
      );

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

  /// Core intelligent matcher — tokenizes filename, applies aliases, scores against stages.
  ///
  /// 5-pass matching pipeline:
  /// 0. REGEX PRE-PASS — structural patterns (mus_bg_lvl_N, ambient_scene, music_scene_lN)
  /// 1. ALIAS MAP — industry-standard compound name matching
  /// 2. DIRECT TOKEN — reconstructed stage ID from tokens
  /// 3. TOKEN OVERLAP — fuzzy scoring against stage token index
  AudioMappingEntry? _intelligentMatch(
    String path,
    Set<String> composedStageIds,
    Map<String, Set<String>> stageTokenIndex,
  ) {
    if (composedStageIds.isEmpty) return null;

    final rawName = _fileName(path);

    // PRE-PASS 0: Regex-based structural pattern matching
    // Catches naming conventions that token-based matching would miss
    final regexMatch = _regexStructuralMatch(rawName, composedStageIds);
    if (regexMatch != null) {
      return AudioMappingEntry(
        stageId: regexMatch.$1,
        audioPath: path,
        confidence: regexMatch.$2,
        source: 'fuzzy',
      );
    }

    // PRE-PASS: Extract NofM variant info for indexed stage matching
    // e.g. "spins_stop_1of5_2" → variantIndex=0 (for REEL_STOP_0)
    final nofm = _extractNofM(rawName);

    final tokens = _tokenizeFilename(rawName);
    if (tokens.isEmpty) return null;

    // PASS 1: Check industry alias map for compound patterns
    final aliasMatch = _checkAliasMap(tokens, composedStageIds, nofm);
    if (aliasMatch != null) {
      // FIX: For non-indexed stages (no _* in candidates), if file has NofM
      // variant notation, only accept the FIRST variant (1ofN).
      // This prevents "spins_loop_2of3" from overwriting "spins_loop_1of3"
      // on REEL_SPIN_LOOP (which is a single stage, not indexed).
      if (nofm != null && !aliasMatch.$1.contains(RegExp(r'_\d+$'))) {
        // Non-indexed stage with NofM variant — only accept first variant
        if (nofm.$1 != 0) {
          return null; // Skip non-first variants for non-indexed stages
        }
      }
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
      // FIX: Same NofM guard as PASS 1 — skip non-first variants for non-indexed stages
      if (nofm != null && nofm.$1 != 0 && !directMatch.$1.contains(RegExp(r'_\d+$'))) {
        // Non-first variant on non-indexed stage — skip
      } else {
        return AudioMappingEntry(
          stageId: directMatch.$1,
          audioPath: path,
          confidence: directMatch.$2,
          source: 'fuzzy',
        );
      }
    }

    // PASS 3: Token overlap scoring against stage token index
    final overlapMatch = _tokenOverlapMatch(tokens, composedStageIds, stageTokenIndex);
    if (overlapMatch != null) {
      // FIX: Same NofM guard — skip non-first variants for non-indexed stages
      if (nofm != null && nofm.$1 != 0 && !overlapMatch.$1.contains(RegExp(r'_\d+$'))) {
        // Non-first variant on non-indexed stage — skip
      } else {
        return AudioMappingEntry(
          stageId: overlapMatch.$1,
          audioPath: path,
          confidence: overlapMatch.$2,
          source: 'fuzzy',
        );
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRE-PASS 0: REGEX STRUCTURAL PATTERN MATCHING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scene abbreviation → canonical scene name mapping
  static const Map<String, String> _sceneAbbreviations = {
    'bg': 'BASE', 'base': 'BASE', 'basegame': 'BASE', 'main': 'BASE',
    'fs': 'FS', 'freespin': 'FS', 'freespins': 'FS', 'free_spin': 'FS', 'free_spins': 'FS',
    'bonus': 'BONUS', 'bon': 'BONUS',
    'hold': 'HOLD', 'hnw': 'HOLD', 'holdwin': 'HOLD', 'respin': 'HOLD', 'rs': 'HOLD', 'resp': 'HOLD',
    'bw': 'BIGWIN', 'bigwin': 'BIGWIN', 'big_win': 'BIGWIN', 'win': 'BIGWIN',
    'jp': 'JACKPOT', 'jackpot': 'JACKPOT',
    'gamble': 'GAMBLE', 'gam': 'GAMBLE', 'risk': 'GAMBLE',
    'reveal': 'REVEAL', 'rev': 'REVEAL',
  };

  /// Match structural filename patterns via regex.
  /// Returns (stageId, confidence) or null.
  (String, double)? _regexStructuralMatch(String rawName, Set<String> composedStageIds) {
    final name = rawName.toLowerCase();

    // ── PATTERN 1: mus_{scene}_lvl_{N} or mus_{scene}_level_{N} ──
    // Examples: mus_bg_lvl_3, mus_fs_lvl_2, mus_bonus_level_4
    final musLvlMatch = RegExp(r'mus[ic]*[-_\s]*(\w+?)[-_\s]*(?:lvl|level|lyr|layer)[-_\s]*(\d)').firstMatch(name);
    if (musLvlMatch != null) {
      final sceneRaw = musLvlMatch.group(1)!;
      final level = musLvlMatch.group(2)!;
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        final stageId = 'MUSIC_${scene}_L$level';
        if (composedStageIds.contains(stageId)) return (stageId, 0.95);
      }
    }

    // ── PATTERN 2: mus_{scene}_start/loop/intro/outro/end ──
    // Examples: mus_fs_start, mus_fs_loop, mus_bg_intro, mus_bonus_outro, mus_rs_end
    final musTypeMatch = RegExp(r'mus[ic]*[-_\s]*(\w+?)[-_\s]*(start|loop|intro|outro|end)').firstMatch(name);
    if (musTypeMatch != null) {
      final sceneRaw = musTypeMatch.group(1)!;
      final type = musTypeMatch.group(2)!;
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        if (type == 'intro' || type == 'start') {
          final stageId = 'MUSIC_${scene}_INTRO';
          if (composedStageIds.contains(stageId)) return (stageId, 0.95);
          // Fallback: start → L1 if no INTRO stage exists
          if (type == 'start') {
            final l1 = 'MUSIC_${scene}_L1';
            if (composedStageIds.contains(l1)) return (l1, 0.90);
          }
        } else if (type == 'outro' || type == 'end') {
          final stageId = 'MUSIC_${scene}_OUTRO';
          if (composedStageIds.contains(stageId)) return (stageId, 0.95);
        } else {
          // loop → L1 (default layer)
          final stageId = 'MUSIC_${scene}_L1';
          if (composedStageIds.contains(stageId)) return (stageId, 0.90);
        }
      }
    }

    // ── PATTERN 3: mus_{scene} (bare scene reference) ──
    // Examples: mus_bw, mus_rs, mus_fs, mus_bonus
    final musSceneMatch = RegExp(r'^(?:\d{1,4}[-_\s])?mus[ic]*[-_\s]+(\w+?)(?:[-_\s]\d+)?$').firstMatch(name);
    if (musSceneMatch != null) {
      final sceneRaw = musSceneMatch.group(1)!;
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        final stageId = 'MUSIC_${scene}_L1';
        if (composedStageIds.contains(stageId)) return (stageId, 0.85);
      }
    }

    // ── PATTERN 4: music_{scene}_layer_{N} or music_{scene}_l{N} ──
    // Examples: music_base_layer_3, music_freespins_l2, music_hold_l5
    final musicLayerMatch = RegExp(r'music[-_\s]*(\w+?)[-_\s]*(?:layer|l|lvl)[-_\s]*(\d)').firstMatch(name);
    if (musicLayerMatch != null) {
      final sceneRaw = musicLayerMatch.group(1)!;
      final level = musicLayerMatch.group(2)!;
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        final stageId = 'MUSIC_${scene}_L$level';
        if (composedStageIds.contains(stageId)) return (stageId, 0.95);
      }
    }

    // ── PATTERN 5: {scene}_music_layer_{N} or {scene}_music_l{N} ──
    // Examples: base_music_layer_3, freespins_music_l2, bonus_music_l5
    final sceneMusLayerMatch = RegExp(r'(\w+?)[-_\s]*music[-_\s]*(?:layer|l|lvl)[-_\s]*(\d)').firstMatch(name);
    if (sceneMusLayerMatch != null) {
      final sceneRaw = sceneMusLayerMatch.group(1)!;
      final level = sceneMusLayerMatch.group(2)!;
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        final stageId = 'MUSIC_${scene}_L$level';
        if (composedStageIds.contains(stageId)) return (stageId, 0.95);
      }
    }

    // ── PATTERN 6: ambient_{scene} or amb_{scene} ──
    // Examples: ambient_freespins, amb_bonus, ambient_base, ambient_hold_and_win
    final ambientMatch = RegExp(r'(?:ambient|amb|ambience)[-_\s]*(\w+)').firstMatch(name);
    if (ambientMatch != null) {
      final sceneRaw = ambientMatch.group(1)!.replaceAll(RegExp(r'[-_\s]+'), '').toLowerCase();
      // Try direct scene mapping
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        final stageId = 'AMBIENT_$scene';
        if (composedStageIds.contains(stageId)) return (stageId, 0.95);
      }
      // Try with scene name remapping for compound names
      for (final entry in _sceneAbbreviations.entries) {
        if (sceneRaw.contains(entry.key)) {
          final stageId = 'AMBIENT_${entry.value}';
          if (composedStageIds.contains(stageId)) return (stageId, 0.90);
        }
      }
    }

    // ── PATTERN 7: {scene}_ambient or {scene}_amb ──
    // Examples: base_ambient, freespins_amb, bonus_ambience
    final sceneAmbientMatch = RegExp(r'(\w+?)[-_\s]*(?:ambient|amb|ambience)').firstMatch(name);
    if (sceneAmbientMatch != null) {
      final sceneRaw = sceneAmbientMatch.group(1)!.replaceAll(RegExp(r'[-_\s]+'), '').toLowerCase();
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        final stageId = 'AMBIENT_$scene';
        if (composedStageIds.contains(stageId)) return (stageId, 0.90);
      }
    }

    // ── PATTERN 8: {scene}_intro or {scene}_outro (music intro/outro) ──
    // Examples: basegame_intro, freespins_intro, bonus_outro
    final sceneIntroOutroMatch = RegExp(r'(\w+?)[-_\s]*(intro|outro)').firstMatch(name);
    if (sceneIntroOutroMatch != null) {
      final sceneRaw = sceneIntroOutroMatch.group(1)!.replaceAll(RegExp(r'[-_\s]+'), '').toLowerCase();
      final type = sceneIntroOutroMatch.group(2)!.toUpperCase();
      // Skip if it's clearly not a music scene (e.g., big_win_intro maps to BIG_WIN_START)
      final scene = _sceneAbbreviations[sceneRaw];
      if (scene != null) {
        // Try music intro/outro first
        final musicStage = 'MUSIC_${scene}_$type';
        if (composedStageIds.contains(musicStage)) return (musicStage, 0.85);
      }
    }

    // ── PATTERN 9: win_present_{N} or win_tier_{N} ──
    // Examples: win_present_3, win_tier_2
    final winTierMatch = RegExp(r'win[-_\s]*(?:present|tier)[-_\s]*(\d)').firstMatch(name);
    if (winTierMatch != null) {
      final tier = winTierMatch.group(1)!;
      final stageId = 'WIN_PRESENT_$tier';
      if (composedStageIds.contains(stageId)) return (stageId, 0.95);
    }

    // ── PATTERN 10: big_win_tier_{N} ──
    // Examples: big_win_tier_3, bigwin_tier_1
    final bwTierMatch = RegExp(r'big[-_\s]*win[-_\s]*tier[-_\s]*(\d)').firstMatch(name);
    if (bwTierMatch != null) {
      final tier = bwTierMatch.group(1)!;
      final stageId = 'BIG_WIN_TIER_$tier';
      if (composedStageIds.contains(stageId)) return (stageId, 0.95);
    }

    // ── PATTERN 11: transition/trn prefix → TRANSITION_SWOOSH/IMPACT ──
    // Examples: trn_bg_1, transition_bg, transition_swoosh, trn_impact
    // CRITICAL: Prevents transition files from being mismatched to MUSIC_BASE_*
    final transMatch = RegExp(r'^(?:\d{1,4}[-_\s])?(?:trn|trans|transition)[-_\s]+(\w+)').firstMatch(name);
    if (transMatch != null) {
      final qualifier = transMatch.group(1)!;
      if (qualifier.contains('impact') || qualifier.contains('hit')) {
        if (composedStageIds.contains('TRANSITION_IMPACT')) return ('TRANSITION_IMPACT', 0.90);
      }
      if (composedStageIds.contains('TRANSITION_SWOOSH')) return ('TRANSITION_SWOOSH', 0.90);
      // Fallback to generic MUSIC_TRANSITION if transition-specific stages don't exist
      if (composedStageIds.contains('MUSIC_TRANSITION')) return ('MUSIC_TRANSITION', 0.80);
    }

    // ── PATTERN 12: sym_{SYMBOL}_win or symbol_{SYMBOL}_win ──
    // Examples: sym_hp1_win, symbol_lp3_win, hp2_win_highlight, sym_wild_win
    // Matches: {sym|symbol}_{HP1-4|LP1-6|WILD|SCATTER|BONUS}_{win|highlight}
    final symWinMatch = RegExp(
      r'(?:sym(?:bol)?[-_\s]*)?'   // optional sym/symbol prefix
      r'(hp[1-4]|lp[1-6]|wild|scatter|bonus)'  // symbol name
      r'[-_\s]*(?:win|highlight)',  // win/highlight suffix
      caseSensitive: false,
    ).firstMatch(name);
    if (symWinMatch != null) {
      final symbolName = symWinMatch.group(1)!.toUpperCase();
      final stageId = 'WIN_SYMBOL_HIGHLIGHT_$symbolName';
      if (composedStageIds.contains(stageId)) return (stageId, 0.95);
      // Fallback: try category level (HP, LP)
      final catMatch = RegExp(r'^(HP|LP)\d+$').firstMatch(symbolName);
      if (catMatch != null) {
        final catStage = 'WIN_SYMBOL_HIGHLIGHT_${catMatch.group(1)}';
        if (composedStageIds.contains(catStage)) return (catStage, 0.90);
      }
    }

    // ── PATTERN 13: payline/line_highlight/pay_line ──
    // Examples: payline_highlight, line_highlight_2, pay_line_1of3, payline_win
    final paylineMatch = RegExp(
      r'(?:payline|pay[-_\s]*line|line[-_\s]*highlight)',
      caseSensitive: false,
    ).firstMatch(name);
    if (paylineMatch != null) {
      if (composedStageIds.contains('PAYLINE_HIGHLIGHT')) return ('PAYLINE_HIGHLIGHT', 0.95);
      if (composedStageIds.contains('WIN_LINE_SHOW')) return ('WIN_LINE_SHOW', 0.90);
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ALL KNOWN STAGE IDs (fallback when FeatureComposer has no composed stages)
  // ═══════════════════════════════════════════════════════════════════════════

  static final Set<String> _allKnownStageIds = {
    // Spins & Reels
    'SPIN_START', 'SPIN_END', 'SPIN_CANCEL', 'REEL_SPIN_LOOP',
    'REEL_STOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2', 'REEL_STOP_3', 'REEL_STOP_4',
    'TURBO_SPIN_LOOP', 'REEL_SLOW_STOP', 'REEL_SHAKE', 'REEL_WIGGLE',
    'SPIN_ACCELERATION', 'SPIN_DECELERATION',
    // Symbols
    'SYMBOL_LAND', 'WILD_LAND', 'SCATTER_LAND',
    'SCATTER_LAND_1', 'SCATTER_LAND_2', 'SCATTER_LAND_3', 'SCATTER_LAND_4', 'SCATTER_LAND_5',
    'SCATTER_COLLECT',
    // Anticipation tension system
    'ANTICIPATION_TENSION', 'ANTICIPATION_MISS',
    'ANTICIPATION_TENSION_R1', 'ANTICIPATION_TENSION_R2', 'ANTICIPATION_TENSION_R3', 'ANTICIPATION_TENSION_R4',
    'NEAR_MISS', 'NO_WIN',
    // Wins — unified WIN_PRESENT system
    'WIN_PRESENT_LOW', 'WIN_PRESENT_EQUAL', 'WIN_PRESENT_END',
    'WIN_PRESENT_1', 'WIN_PRESENT_2', 'WIN_PRESENT_3', 'WIN_PRESENT_4', 'WIN_PRESENT_5',
    'WIN_COLLECT',
    'BIG_WIN_TRIGGER', 'BIG_WIN_START', 'BIG_WIN_LOOP', 'BIG_WIN_COINS',
    'BIG_WIN_IMPACT', 'BIG_WIN_UPGRADE', 'BIG_WIN_END', 'BIG_WIN_OUTRO',
    'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_TIER_4', 'BIG_WIN_TIER_5',
    'WIN_EVAL', 'WIN_DETECTED', 'WIN_CALCULATE',
    'WIN_LINE_SHOW', 'WIN_LINE_HIDE', 'WIN_SYMBOL_HIGHLIGHT', 'WIN_LINE_CYCLE',
    'PAYLINE_HIGHLIGHT',
    'WIN_SYMBOL_HIGHLIGHT_HP', 'WIN_SYMBOL_HIGHLIGHT_HP1', 'WIN_SYMBOL_HIGHLIGHT_HP2',
    'WIN_SYMBOL_HIGHLIGHT_HP3', 'WIN_SYMBOL_HIGHLIGHT_HP4',
    'WIN_SYMBOL_HIGHLIGHT_LP', 'WIN_SYMBOL_HIGHLIGHT_LP1', 'WIN_SYMBOL_HIGHLIGHT_LP2',
    'WIN_SYMBOL_HIGHLIGHT_LP3', 'WIN_SYMBOL_HIGHLIGHT_LP4', 'WIN_SYMBOL_HIGHLIGHT_LP5',
    'WIN_SYMBOL_HIGHLIGHT_LP6',
    'WIN_SYMBOL_HIGHLIGHT_WILD', 'WIN_SYMBOL_HIGHLIGHT_SCATTER', 'WIN_SYMBOL_HIGHLIGHT_BONUS',
    'WIN_FANFARE',
    // Rollup
    'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_TICK_FAST', 'ROLLUP_TICK_SLOW',
    'ROLLUP_END', 'ROLLUP_SKIP', 'ROLLUP_ACCELERATION', 'ROLLUP_DECELERATION',
    // Coins & Effects
    'COIN_BURST', 'COIN_DROP', 'COIN_SHOWER', 'COIN_RAIN',
    'COIN_LAND', 'COIN_LOCK', 'COIN_COLLECT', 'COIN_VALUE_REVEAL',
    'SCREEN_SHAKE', 'LIGHT_FLASH', 'CONFETTI_BURST',
    'FIREWORKS_LAUNCH', 'FIREWORKS_EXPLODE',
    // Music — all scenes × (INTRO, OUTRO, L1-L5)
    'MUSIC_BASE_INTRO', 'MUSIC_BASE_OUTRO',
    'MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_BASE_L3', 'MUSIC_BASE_L4', 'MUSIC_BASE_L5',
    'MUSIC_FS_INTRO', 'MUSIC_FS_OUTRO',
    'MUSIC_FS_L1', 'MUSIC_FS_L2', 'MUSIC_FS_L3', 'MUSIC_FS_L4', 'MUSIC_FS_L5',
    'MUSIC_BONUS_INTRO', 'MUSIC_BONUS_OUTRO',
    'MUSIC_BONUS_L1', 'MUSIC_BONUS_L2', 'MUSIC_BONUS_L3', 'MUSIC_BONUS_L4', 'MUSIC_BONUS_L5',
    'MUSIC_HOLD_INTRO', 'MUSIC_HOLD_OUTRO',
    'MUSIC_HOLD_L1', 'MUSIC_HOLD_L2', 'MUSIC_HOLD_L3', 'MUSIC_HOLD_L4', 'MUSIC_HOLD_L5',
    // Big Win music handled via BIG_WIN_START/END/OUTRO composite event layers
    'MUSIC_JACKPOT_INTRO', 'MUSIC_JACKPOT_OUTRO',
    'MUSIC_JACKPOT_L1', 'MUSIC_JACKPOT_L2', 'MUSIC_JACKPOT_L3', 'MUSIC_JACKPOT_L4', 'MUSIC_JACKPOT_L5',
    'MUSIC_GAMBLE_INTRO', 'MUSIC_GAMBLE_OUTRO',
    'MUSIC_GAMBLE_L1', 'MUSIC_GAMBLE_L2', 'MUSIC_GAMBLE_L3', 'MUSIC_GAMBLE_L4', 'MUSIC_GAMBLE_L5',
    'MUSIC_REVEAL_INTRO', 'MUSIC_REVEAL_OUTRO',
    'MUSIC_REVEAL_L1', 'MUSIC_REVEAL_L2', 'MUSIC_REVEAL_L3', 'MUSIC_REVEAL_L4', 'MUSIC_REVEAL_L5',
    // Music — special
    'MUSIC_STINGER_WIN', 'MUSIC_STINGER_FEATURE', 'MUSIC_STINGER_BONUS', 'MUSIC_STINGER_JACKPOT',
    'MUSIC_TENSION_LOW', 'MUSIC_TENSION_MED', 'MUSIC_TENSION_HIGH', 'MUSIC_TENSION_MAX',
    'MUSIC_BUILDUP', 'MUSIC_CLIMAX', 'MUSIC_TRANSITION', 'MUSIC_CROSSFADE',
    // Ambient — per scene
    'AMBIENT_BASE', 'AMBIENT_FS', 'AMBIENT_BONUS', 'AMBIENT_HOLD',
    'AMBIENT_BIGWIN', 'AMBIENT_JACKPOT', 'AMBIENT_GAMBLE', 'AMBIENT_REVEAL',
    // Free Spins
    'FREESPIN_TRIGGER', 'FREESPIN_START', 'FREESPIN_SPIN', 'FREESPIN_END',
    'FREESPIN_RETRIGGER', 'FREESPIN_MUSIC',
    // Bonus
    'BONUS_TRIGGER', 'BONUS_ENTER', 'BONUS_STEP', 'BONUS_EXIT', 'BONUS_MUSIC', 'BONUS_SUMMARY',
    'PICK_REVEAL', 'PICK_GOOD', 'PICK_BAD', 'PICK_BONUS', 'PICK_COLLECT',
    'WHEEL_START', 'WHEEL_SPIN', 'WHEEL_TICK', 'WHEEL_LAND',
    // Hold & Win
    'HOLD_TRIGGER', 'HOLD_START', 'HOLD_SPIN', 'HOLD_LOCK', 'HOLD_END', 'HOLD_MUSIC',
    'RESPIN_START', 'RESPIN_SPIN', 'RESPIN_STOP', 'RESPIN_END',
    // Cascade
    'CASCADE_START', 'CASCADE_STEP', 'CASCADE_POP', 'CASCADE_END',
    'TUMBLE_DROP', 'AVALANCHE_TRIGGER',
    // Jackpot
    'JACKPOT_TRIGGER', 'JACKPOT_AWARD', 'JACKPOT_MINI', 'JACKPOT_MINOR',
    'JACKPOT_MAJOR', 'JACKPOT_GRAND', 'JACKPOT_MEGA', 'JACKPOT_ULTRA',
    // Gamble
    'GAMBLE_ENTER', 'GAMBLE_WIN', 'GAMBLE_LOSE', 'GAMBLE_COLLECT', 'GAMBLE_EXIT',
    'GAMBLE_CARD_FLIP',
    // Multiplier
    'MULTIPLIER_INCREASE', 'MULTIPLIER_APPLY', 'MULTIPLIER_RESET',
    // Features
    'FEATURE_ENTER', 'FEATURE_EXIT',
    // UI
    'UI_BUTTON_PRESS', 'UI_BUTTON_HOVER', 'UI_BUTTON_RELEASE',
    'UI_MENU_OPEN', 'UI_MENU_CLOSE', 'UI_POPUP_OPEN', 'UI_POPUP_CLOSE',
    'UI_NOTIFICATION', 'GAME_START', 'GAME_READY',
    // Attract
    'ATTRACT_LOOP', 'ATTRACT_EXIT', 'IDLE_LOOP',
    // Wild mechanics
    'WILD_EXPAND', 'WILD_STICKY', 'WILD_TRANSFORM',
    'WILD_MULTIPLY', 'WILD_WALKING',
    // Transitions
    'TRANSITION_SWOOSH', 'TRANSITION_IMPACT',
    'CONTEXT_BASE_TO_FS', 'CONTEXT_FS_TO_BASE',
    'CONTEXT_BASE_TO_BONUS', 'CONTEXT_BONUS_TO_BASE',
    'CONTEXT_BASE_TO_HOLDWIN', 'CONTEXT_HOLDWIN_TO_BASE',
    'CONTEXT_BASE_TO_GAMBLE', 'CONTEXT_GAMBLE_TO_BASE',
    'CONTEXT_BASE_TO_JACKPOT', 'CONTEXT_JACKPOT_TO_BASE',
    // Collect
    'COLLECT_TRIGGER', 'COLLECT_COIN',
    // VO
    'VO_WIN_1', 'VO_WIN_2', 'VO_WIN_3', 'VO_WIN_4', 'VO_WIN_5',
    'VO_BIG_WIN', 'VO_CONGRATULATIONS', 'VO_FREE_SPINS', 'VO_BONUS',
    // Megaways
    'MEGAWAYS_REVEAL', 'MEGAWAYS_EXPAND',
    // Reel mechanics
    'REEL_NUDGE', 'NUDGE_UP', 'NUDGE_DOWN',
    // Mystery
    'MYSTERY_LAND', 'MYSTERY_REVEAL', 'MYSTERY_TRANSFORM',
  };

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

  /// Tokens that indicate a transition/SFX context — NEVER bind to music layers
  static const Set<String> _transitionContextTokens = {
    'trn', 'trans', 'transition', 'swoosh', 'impact', 'whoosh', 'swipe',
    'wipe', 'sweep', 'slide', 'reveal', 'stab', 'hit', 'riser',
  };

  /// Check if tokens contain transition/SFX context that should block music matching.
  bool _hasTransitionContext(List<String> tokens) {
    for (final t in tokens) {
      if (_transitionContextTokens.contains(t)) return true;
    }
    return false;
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

    final hasTransCtx = _hasTransitionContext(tokens);

    for (final entry in sortedAliases) {
      final pattern = entry.key;
      final candidates = entry.value;
      final patternNoSpace = pattern.replaceAll(' ', '');

      // Context guard: if file has transition tokens, block music/ambient alias matches
      if (hasTransCtx) {
        final firstCandidate = candidates.firstOrNull ?? '';
        if (firstCandidate.startsWith('MUSIC_') || firstCandidate.startsWith('AMBIENT_')) {
          continue;
        }
      }

      // Match against token forms only — NO substring matching.
      // joinedNoSpace.contains() caused false positives:
      //   "mus_rs_end" contains "mus_rs" → wrong match to MUSIC_HOLD_L1
      if (_matchesPattern(joined, tokens, pattern)) {
        // Find first candidate that exists in composed stages
        for (final candidate in candidates) {
          // Indexed stage expansion: "REEL_STOP_*" with NofM → "REEL_STOP_0", "REEL_STOP_1"...
          // Some stages are 0-based (REEL_STOP_0), others 1-based (ANTICIPATION_TENSION_R1)
          if (candidate.endsWith('_*') && nofm != null) {
            final base = candidate.substring(0, candidate.length - 1); // "REEL_STOP_"
            final indexed0 = '$base${nofm.$1}'; // 0-based
            final indexed1 = '$base${nofm.$1 + 1}'; // 1-based
            if (composedStageIds.contains(indexed0)) {
              return (indexed0, 0.90);
            } else if (composedStageIds.contains(indexed1)) {
              return (indexed1, 0.90);
            }
          } else if (candidate.endsWith('_*')) {
            // No NofM info — try _0 then _1 as defaults
            final base = candidate.substring(0, candidate.length - 1);
            final defaulted0 = '${base}0';
            final defaulted1 = '${base}1';
            if (composedStageIds.contains(defaulted0)) {
              return (defaulted0, 0.80);
            } else if (composedStageIds.contains(defaulted1)) {
              return (defaulted1, 0.80);
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
        // Exact match, plural/singular, or abbreviation expansion only
        if (token == part ||
            token == '${part}s' ||
            '${token}s' == part ||
            _singularize(token) == part ||
            _singularize(token) == _singularize(part)) {
          found = true;
          break;
        }
        // Allow startsWith ONLY for long tokens (≥5 chars) to avoid
        // false positives like 'trn' matching 'transition'
        if (token.length >= 5 && part.length >= 5 &&
            (token.startsWith(part) || part.startsWith(token))) {
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
    final hasTransCtx = _hasTransitionContext(tokens);

    // Expand tokens with ONLY direct singulars — NO abbreviation expansion.
    // Abbreviations caused cascading false positives:
    //   fs → spins → (singularize) spin → matches SPIN_START
    //   bg → base → matches MUSIC_BASE_L1
    // Abbreviation matching belongs in PASS 1 (alias map), not fuzzy overlap.
    final expandedTokens = <String>{};
    for (final t in tokens) {
      expandedTokens.add(t);
      expandedTokens.add(_singularize(t));
    }

    for (final entry in stageTokenIndex.entries) {
      final stageId = entry.key;
      final stageTokens = entry.value;

      // Context guard: transition files must not match MUSIC_* or AMBIENT_*
      if (hasTransCtx && (stageId.startsWith('MUSIC_') || stageId.startsWith('AMBIENT_'))) {
        continue;
      }

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

      // Require at least 67% coverage of stage tokens
      if (score > bestScore && coverage >= 0.67) {
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
  ///
  /// CRITICAL: Stage IDs MUST match actual UI stage IDs from ultimate_audio_panel:
  /// - Wins: WIN_PRESENT_1-5, BIG_WIN_TIER_1-5, BIG_WIN_START/LOOP/END
  /// - Music: MUSIC_{SCENE}_L1-L5, MUSIC_{SCENE}_INTRO/OUTRO
  /// - Ambient: AMBIENT_BASE/FS/BONUS/HOLD/BIGWIN/JACKPOT/GAMBLE/REVEAL
  /// - Reels: REEL_STOP_0-4, REEL_SPIN_LOOP, SPIN_START
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
    'ui spin': ['SPIN_START', 'UI_SPIN_PRESS'],

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
    'turbo spin': ['TURBO_SPIN_LOOP'],

    // ═══════════════════════════════════════════════════════════════════
    // REEL STOP (individual reel landing) → REEL_STOP_* (indexed by NofM)
    // "spins_stop_1of5_2" → REEL_STOP_0, "spins_stop_3of5_1" → REEL_STOP_2
    // Without NofM → defaults to REEL_STOP (generic)
    // ═══════════════════════════════════════════════════════════════════
    'spin stop': ['REEL_STOP_*', 'REEL_STOP'],
    'spins stop': ['REEL_STOP_*', 'REEL_STOP'],
    'reel stop': ['REEL_STOP_*', 'REEL_STOP'],
    'reel land': ['REEL_STOP_*', 'REEL_STOP'],
    'reel end': ['REEL_STOP_*', 'REEL_STOP'],

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
    'sym land': ['SYMBOL_LAND'],
    'wild land': ['WILD_LAND', 'SYMBOL_LAND_WILD'],
    'wild symbol': ['WILD_LAND', 'SYMBOL_LAND_WILD'],
    'scatter land': ['SCATTER_LAND', 'SYMBOL_LAND_SCATTER'],
    'scatter symbol': ['SCATTER_LAND', 'SYMBOL_LAND_SCATTER'],
    'scatter land 1': ['SCATTER_LAND_1'],
    'scatter land 2': ['SCATTER_LAND_2'],
    'scatter land 3': ['SCATTER_LAND_3'],
    'scatter land 4': ['SCATTER_LAND_4'],
    'scatter land 5': ['SCATTER_LAND_5'],
    'scatter 1': ['SCATTER_LAND_1'],
    'scatter 2': ['SCATTER_LAND_2'],
    'scatter 3': ['SCATTER_LAND_3'],
    'scatter 4': ['SCATTER_LAND_4'],
    'scatter 5': ['SCATTER_LAND_5'],
    'scatter collect': ['SCATTER_COLLECT'],
    'bonus land': ['SYMBOL_LAND_BONUS'],
    'bonus symbol land': ['SYMBOL_LAND_BONUS'],

    // ═══════════════════════════════════════════════════════════════════
    // WINS — ACTUAL UI STAGE IDs
    // WIN_PRESENT_1-5 = standard win tiers
    // BIG_WIN_TIER_1-5 = big win celebration tiers
    // ═══════════════════════════════════════════════════════════════════
    'quick win': ['WIN_PRESENT_1', 'WIN_PRESENT_LOW'],
    'small win': ['WIN_PRESENT_1', 'WIN_PRESENT_LOW'],
    'low win': ['WIN_PRESENT_LOW', 'WIN_PRESENT_1'],
    'normal win': ['WIN_PRESENT_2'],
    'medium win': ['WIN_PRESENT_2', 'WIN_PRESENT_3'],
    'big win': ['WIN_PRESENT_4', 'BIG_WIN_START'],
    'bigwin': ['WIN_PRESENT_4', 'BIG_WIN_START'],
    'mega win': ['WIN_PRESENT_5', 'BIG_WIN_TIER_2'],
    'megawin': ['WIN_PRESENT_5', 'BIG_WIN_TIER_2'],
    'epic win': ['BIG_WIN_TIER_3', 'WIN_PRESENT_5'],
    'super win': ['BIG_WIN_TIER_3', 'WIN_PRESENT_5'],
    'ultra win': ['BIG_WIN_TIER_4', 'WIN_PRESENT_5'],
    'max win': ['BIG_WIN_TIER_5', 'WIN_PRESENT_5'],
    'sensational win': ['BIG_WIN_TIER_5'],
    'no win': ['NO_WIN'],
    'win present': ['WIN_PRESENT_1'],
    'win line': ['WIN_LINE_SHOW'],
    'win line show': ['WIN_LINE_SHOW'],
    'win line hide': ['WIN_LINE_HIDE'],
    'line highlight': ['WIN_LINE_SHOW', 'PAYLINE_HIGHLIGHT'],
    'payline': ['PAYLINE_HIGHLIGHT', 'WIN_LINE_SHOW'],
    'payline highlight': ['PAYLINE_HIGHLIGHT', 'WIN_LINE_SHOW'],
    'pay line': ['PAYLINE_HIGHLIGHT', 'WIN_LINE_SHOW'],
    'pay line highlight': ['PAYLINE_HIGHLIGHT', 'WIN_LINE_SHOW'],
    'line win': ['WIN_LINE_SHOW', 'PAYLINE_HIGHLIGHT'],
    'win collect': ['WIN_COLLECT', 'GAMBLE_COLLECT'],
    'win end': ['WIN_PRESENT_END'],
    'win present end': ['WIN_PRESENT_END'],
    'win line cycle': ['WIN_LINE_CYCLE'],
    'line cycle': ['WIN_LINE_CYCLE'],
    'win highlight': ['WIN_SYMBOL_HIGHLIGHT'],
    'symbol highlight': ['WIN_SYMBOL_HIGHLIGHT'],
    'sym highlight': ['WIN_SYMBOL_HIGHLIGHT'],
    'win fanfare': ['WIN_FANFARE'],
    'celebration': ['WIN_FANFARE'],
    'victory': ['WIN_FANFARE'],
    'win eval': ['WIN_EVAL'],
    'win evaluate': ['WIN_EVAL'],
    'win detect': ['WIN_DETECTED'],
    'win detected': ['WIN_DETECTED'],
    'win calc': ['WIN_CALCULATE'],
    'win calculate': ['WIN_CALCULATE'],

    // ─── Per-symbol win highlights — HP (High Pay) ───────────────────────
    'hp1 win': ['WIN_SYMBOL_HIGHLIGHT_HP1'],
    'hp2 win': ['WIN_SYMBOL_HIGHLIGHT_HP2'],
    'hp3 win': ['WIN_SYMBOL_HIGHLIGHT_HP3'],
    'hp4 win': ['WIN_SYMBOL_HIGHLIGHT_HP4'],
    'sym hp1 win': ['WIN_SYMBOL_HIGHLIGHT_HP1'],
    'sym hp2 win': ['WIN_SYMBOL_HIGHLIGHT_HP2'],
    'sym hp3 win': ['WIN_SYMBOL_HIGHLIGHT_HP3'],
    'sym hp4 win': ['WIN_SYMBOL_HIGHLIGHT_HP4'],
    'symbol hp1 win': ['WIN_SYMBOL_HIGHLIGHT_HP1'],
    'symbol hp2 win': ['WIN_SYMBOL_HIGHLIGHT_HP2'],
    'symbol hp3 win': ['WIN_SYMBOL_HIGHLIGHT_HP3'],
    'symbol hp4 win': ['WIN_SYMBOL_HIGHLIGHT_HP4'],
    'high pay 1 win': ['WIN_SYMBOL_HIGHLIGHT_HP1'],
    'high pay 2 win': ['WIN_SYMBOL_HIGHLIGHT_HP2'],
    'high pay 3 win': ['WIN_SYMBOL_HIGHLIGHT_HP3'],
    'high pay 4 win': ['WIN_SYMBOL_HIGHLIGHT_HP4'],
    'hp1 highlight': ['WIN_SYMBOL_HIGHLIGHT_HP1'],
    'hp2 highlight': ['WIN_SYMBOL_HIGHLIGHT_HP2'],
    'hp3 highlight': ['WIN_SYMBOL_HIGHLIGHT_HP3'],
    'hp4 highlight': ['WIN_SYMBOL_HIGHLIGHT_HP4'],
    'hp win': ['WIN_SYMBOL_HIGHLIGHT_HP'],
    'high pay win': ['WIN_SYMBOL_HIGHLIGHT_HP'],

    // ─── Per-symbol win highlights — LP (Low Pay) ────────────────────────
    'lp1 win': ['WIN_SYMBOL_HIGHLIGHT_LP1'],
    'lp2 win': ['WIN_SYMBOL_HIGHLIGHT_LP2'],
    'lp3 win': ['WIN_SYMBOL_HIGHLIGHT_LP3'],
    'lp4 win': ['WIN_SYMBOL_HIGHLIGHT_LP4'],
    'lp5 win': ['WIN_SYMBOL_HIGHLIGHT_LP5'],
    'lp6 win': ['WIN_SYMBOL_HIGHLIGHT_LP6'],
    'sym lp1 win': ['WIN_SYMBOL_HIGHLIGHT_LP1'],
    'sym lp2 win': ['WIN_SYMBOL_HIGHLIGHT_LP2'],
    'sym lp3 win': ['WIN_SYMBOL_HIGHLIGHT_LP3'],
    'sym lp4 win': ['WIN_SYMBOL_HIGHLIGHT_LP4'],
    'sym lp5 win': ['WIN_SYMBOL_HIGHLIGHT_LP5'],
    'sym lp6 win': ['WIN_SYMBOL_HIGHLIGHT_LP6'],
    'symbol lp1 win': ['WIN_SYMBOL_HIGHLIGHT_LP1'],
    'symbol lp2 win': ['WIN_SYMBOL_HIGHLIGHT_LP2'],
    'symbol lp3 win': ['WIN_SYMBOL_HIGHLIGHT_LP3'],
    'symbol lp4 win': ['WIN_SYMBOL_HIGHLIGHT_LP4'],
    'symbol lp5 win': ['WIN_SYMBOL_HIGHLIGHT_LP5'],
    'symbol lp6 win': ['WIN_SYMBOL_HIGHLIGHT_LP6'],
    'low pay 1 win': ['WIN_SYMBOL_HIGHLIGHT_LP1'],
    'low pay 2 win': ['WIN_SYMBOL_HIGHLIGHT_LP2'],
    'low pay 3 win': ['WIN_SYMBOL_HIGHLIGHT_LP3'],
    'low pay 4 win': ['WIN_SYMBOL_HIGHLIGHT_LP4'],
    'low pay 5 win': ['WIN_SYMBOL_HIGHLIGHT_LP5'],
    'low pay 6 win': ['WIN_SYMBOL_HIGHLIGHT_LP6'],
    'lp win': ['WIN_SYMBOL_HIGHLIGHT_LP'],
    'low pay win': ['WIN_SYMBOL_HIGHLIGHT_LP'],

    // ─── Per-symbol win highlights — Special ─────────────────────────────
    'wild win': ['WIN_SYMBOL_HIGHLIGHT_WILD'],
    'scatter win': ['WIN_SYMBOL_HIGHLIGHT_SCATTER'],
    'bonus symbol win': ['WIN_SYMBOL_HIGHLIGHT_BONUS'],
    'sym wild win': ['WIN_SYMBOL_HIGHLIGHT_WILD'],
    'sym scatter win': ['WIN_SYMBOL_HIGHLIGHT_SCATTER'],
    'sym bonus win': ['WIN_SYMBOL_HIGHLIGHT_BONUS'],

    // ─── WIN multiplier tiers → WIN_PRESENT_N ──────────────────────────
    'win 1x': ['WIN_PRESENT_1'],
    'win1x': ['WIN_PRESENT_1'],
    'win 2x': ['WIN_PRESENT_1'],
    'win2x': ['WIN_PRESENT_1'],
    'win 3x': ['WIN_PRESENT_2'],
    'win3x': ['WIN_PRESENT_2'],
    'win 5x': ['WIN_PRESENT_2'],
    'win5x': ['WIN_PRESENT_2'],
    'win 10x': ['WIN_PRESENT_3'],
    'win10x': ['WIN_PRESENT_3'],
    'win 15x': ['WIN_PRESENT_4'],
    'win15x': ['WIN_PRESENT_4'],
    'win 20x': ['BIG_WIN_TIER_1', 'WIN_PRESENT_5'],
    'win20x': ['BIG_WIN_TIER_1', 'WIN_PRESENT_5'],
    'win 25x': ['BIG_WIN_TIER_1'],
    'win25x': ['BIG_WIN_TIER_1'],
    'win 50x': ['BIG_WIN_TIER_2'],
    'win50x': ['BIG_WIN_TIER_2'],
    'win 100x': ['BIG_WIN_TIER_3'],
    'win100x': ['BIG_WIN_TIER_3'],
    'win 250x': ['BIG_WIN_TIER_4'],
    'win250x': ['BIG_WIN_TIER_4'],
    'win 500x': ['BIG_WIN_TIER_5'],
    'win500x': ['BIG_WIN_TIER_5'],

    // ═══════════════════════════════════════════════════════════════════
    // BIG WIN specific stages (celebration sequence)
    // ═══════════════════════════════════════════════════════════════════
    'big win intro': ['BIG_WIN_START'],
    'big win loop': ['BIG_WIN_LOOP'],
    'big win coins': ['BIG_WIN_COINS'],
    'big win impact': ['BIG_WIN_IMPACT'],
    'big win end': ['BIG_WIN_END'],
    'big win outro': ['BIG_WIN_OUTRO'],
    'big win upgrade': ['BIG_WIN_UPGRADE'],
    'big win trigger': ['BIG_WIN_TRIGGER'],

    // ═══════════════════════════════════════════════════════════════════
    // ROLLUP / COUNTUP → ROLLUP_START, ROLLUP_TICK, ROLLUP_END
    // ═══════════════════════════════════════════════════════════════════
    'rollup': ['ROLLUP_TICK'],
    'roll up': ['ROLLUP_TICK'],
    'rollup low': ['ROLLUP_TICK_SLOW', 'ROLLUP_START'],
    'rollupl': ['ROLLUP_TICK_SLOW', 'ROLLUP_START'],
    'rollup med': ['ROLLUP_TICK'],
    'rollupm': ['ROLLUP_TICK'],
    'rollup high': ['ROLLUP_TICK_FAST', 'ROLLUP_END'],
    'rolluph': ['ROLLUP_TICK_FAST', 'ROLLUP_END'],
    'rollup end': ['ROLLUP_END'],
    'rollup start': ['ROLLUP_START'],
    'rollup skip': ['ROLLUP_SKIP'],
    'rollup fast': ['ROLLUP_TICK_FAST'],
    'countup end': ['ROLLUP_END'],
    'countup start': ['ROLLUP_START'],
    'count up end': ['ROLLUP_END'],
    'count up start': ['ROLLUP_START'],
    'rollup slow': ['ROLLUP_TICK_SLOW'],
    'count up': ['ROLLUP_TICK'],
    'countup': ['ROLLUP_TICK'],
    'totalizer': ['ROLLUP_TICK'],

    // ═══════════════════════════════════════════════════════════════════
    // MUSIC — All scenes: MUSIC_{SCENE}_L1-L5, INTRO, OUTRO
    // ═══════════════════════════════════════════════════════════════════

    // ─── Base Game Music ─────────────────────────────────────────────
    'base game music': ['MUSIC_BASE_L1'],
    'base game loop': ['MUSIC_BASE_L1'],
    'basegame music': ['MUSIC_BASE_L1'],
    'basegame musicloop': ['MUSIC_BASE_L1'],
    'base game musicloop': ['MUSIC_BASE_L1'],
    'basegame music start': ['MUSIC_BASE_L1'],
    'base music': ['MUSIC_BASE_L1'],
    'bg music': ['MUSIC_BASE_L1'],
    'bgm': ['MUSIC_BASE_L1'],
    'background music': ['MUSIC_BASE_L1'],
    'music loop': ['MUSIC_BASE_L1'],
    'music base': ['MUSIC_BASE_L1'],
    'music start': ['MUSIC_BASE_L1'],
    'base intro': ['MUSIC_BASE_INTRO'],
    'base outro': ['MUSIC_BASE_OUTRO'],
    'base music intro': ['MUSIC_BASE_INTRO'],
    'base music outro': ['MUSIC_BASE_OUTRO'],
    // ─── Free Spins Music ────────────────────────────────────────────
    'feature music': ['MUSIC_FS_L1'],
    'free spin music': ['MUSIC_FS_L1'],
    'free spins music': ['MUSIC_FS_L1'],
    'freespins music': ['MUSIC_FS_L1'],
    'freespins music loop': ['MUSIC_FS_L1'],
    'fs music': ['MUSIC_FS_L1'],
    'fs intro': ['MUSIC_FS_INTRO'],
    'fs outro': ['MUSIC_FS_OUTRO'],
    'freespin music': ['MUSIC_FS_L1'],
    'freespin intro': ['MUSIC_FS_INTRO'],
    'freespin outro': ['MUSIC_FS_OUTRO'],
    // ─── Win / Big Win ────────────────────────────────────────────────
    'win music': ['BIG_WIN_START'],
    'big win music': ['BIG_WIN_START'],
    'bigwin music': ['BIG_WIN_START'],
    'bigwin intro': ['BIG_WIN_START'],
    'bigwin end': ['BIG_WIN_END'],
    'bigwin outro': ['BIG_WIN_OUTRO'],
    // ─── Bonus Music ─────────────────────────────────────────────────
    'bonus music': ['MUSIC_BONUS_L1'],
    'bonus intro': ['MUSIC_BONUS_INTRO'],
    'bonus outro': ['MUSIC_BONUS_OUTRO'],
    'bonus music intro': ['MUSIC_BONUS_INTRO'],
    'bonus music outro': ['MUSIC_BONUS_OUTRO'],
    // ─── Hold & Spin Music ───────────────────────────────────────────
    'hold music': ['MUSIC_HOLD_L1'],
    'hold intro': ['MUSIC_HOLD_INTRO'],
    'hold outro': ['MUSIC_HOLD_OUTRO'],
    'hold spin music': ['MUSIC_HOLD_L1'],
    'respin music': ['MUSIC_HOLD_L1'],
    'mus rs': ['MUSIC_HOLD_L1'],
    'mus rs start': ['MUSIC_HOLD_INTRO'],
    'mus rs intro': ['MUSIC_HOLD_INTRO'],
    'mus rs end': ['MUSIC_HOLD_OUTRO'],
    'mus rs outro': ['MUSIC_HOLD_OUTRO'],
    'mus hold': ['MUSIC_HOLD_L1'],
    'mus hold intro': ['MUSIC_HOLD_INTRO'],
    'mus hold end': ['MUSIC_HOLD_OUTRO'],
    // ─── Jackpot Music ───────────────────────────────────────────────
    'jackpot music': ['MUSIC_JACKPOT_L1'],
    'jackpot intro': ['MUSIC_JACKPOT_INTRO'],
    'jackpot outro': ['MUSIC_JACKPOT_OUTRO'],
    // ─── Gamble Music ────────────────────────────────────────────────
    'gamble music': ['MUSIC_GAMBLE_L1'],
    'gamble intro': ['MUSIC_GAMBLE_INTRO'],
    'gamble outro': ['MUSIC_GAMBLE_OUTRO'],
    // ─── Reveal Music ────────────────────────────────────────────────
    'reveal music': ['MUSIC_REVEAL_L1'],
    'reveal intro': ['MUSIC_REVEAL_INTRO'],
    'reveal outro': ['MUSIC_REVEAL_OUTRO'],
    // ─── Stingers & Transitions ──────────────────────────────────────
    'stinger': ['MUSIC_STINGER_WIN'],
    'stinger win': ['MUSIC_STINGER_WIN'],
    'stinger feature': ['MUSIC_STINGER_FEATURE'],
    'stinger bonus': ['MUSIC_STINGER_BONUS'],
    'stinger jackpot': ['MUSIC_STINGER_JACKPOT'],
    'music transition': ['MUSIC_TRANSITION'],
    'music crossfade': ['MUSIC_CROSSFADE'],
    // ─── Tension Music ───────────────────────────────────────────────
    'tension low': ['MUSIC_TENSION_LOW'],
    'tension med': ['MUSIC_TENSION_MED'],
    'tension high': ['MUSIC_TENSION_HIGH'],
    'tension max': ['MUSIC_TENSION_MAX'],
    'music buildup': ['MUSIC_BUILDUP'],
    'music climax': ['MUSIC_CLIMAX'],

    // ═══════════════════════════════════════════════════════════════════
    // AMBIENT — Per-scene ambient stages
    // ═══════════════════════════════════════════════════════════════════
    'ambient base': ['AMBIENT_BASE'],
    'ambient basegame': ['AMBIENT_BASE'],
    'ambient bg': ['AMBIENT_BASE'],
    'base ambient': ['AMBIENT_BASE'],
    'ambient freespins': ['AMBIENT_FS'],
    'ambient free spins': ['AMBIENT_FS'],
    'ambient fs': ['AMBIENT_FS'],
    'fs ambient': ['AMBIENT_FS'],
    'ambient bonus': ['AMBIENT_BONUS'],
    'bonus ambient': ['AMBIENT_BONUS'],
    'ambient hold': ['AMBIENT_HOLD'],
    'hold ambient': ['AMBIENT_HOLD'],
    'ambient bigwin': ['AMBIENT_BIGWIN'],
    'ambient big win': ['AMBIENT_BIGWIN'],
    'bigwin ambient': ['AMBIENT_BIGWIN'],
    'ambient jackpot': ['AMBIENT_JACKPOT'],
    'jackpot ambient': ['AMBIENT_JACKPOT'],
    'ambient gamble': ['AMBIENT_GAMBLE'],
    'gamble ambient': ['AMBIENT_GAMBLE'],
    'ambient reveal': ['AMBIENT_REVEAL'],
    'reveal ambient': ['AMBIENT_REVEAL'],
    'ambient': ['AMBIENT_BASE'],
    'ambience': ['AMBIENT_BASE'],
    'amb base': ['AMBIENT_BASE'],
    'amb fs': ['AMBIENT_FS'],
    'amb bonus': ['AMBIENT_BONUS'],

    // ═══════════════════════════════════════════════════════════════════
    // FREE SPINS → FREESPIN_TRIGGER, FREESPIN_START, etc.
    // ═══════════════════════════════════════════════════════════════════
    'free spin': ['FREESPIN_START', 'FEATURE_ENTER'],
    'free spins': ['FREESPIN_START', 'FEATURE_ENTER'],
    'fs trigger': ['FREESPIN_TRIGGER', 'FEATURE_ENTER'],
    'fs start': ['FREESPIN_START', 'FEATURE_ENTER'],
    'fs end': ['FREESPIN_END', 'FEATURE_EXIT'],
    'fs loop': ['FREESPIN_SPIN', 'FEATURE_LOOP'],
    'free spin trigger': ['FREESPIN_TRIGGER'],
    'free spin start': ['FREESPIN_START'],
    'free spin end': ['FREESPIN_END'],
    'retrigger': ['FREESPIN_RETRIGGER'],
    'fs retrigger': ['FREESPIN_RETRIGGER'],

    // ═══════════════════════════════════════════════════════════════════
    // BONUS → BONUS_TRIGGER, BONUS_ENTER, PICK_*, WHEEL_*
    // ═══════════════════════════════════════════════════════════════════
    'bonus': ['BONUS_ENTER', 'FEATURE_ENTER'],
    'bonus start': ['BONUS_ENTER', 'FEATURE_ENTER'],
    'bonus trigger': ['BONUS_TRIGGER'],
    'bonus end': ['BONUS_EXIT', 'FEATURE_EXIT'],
    'bonus win': ['PICK_GOOD', 'PICK_REVEAL'],
    'bonus summary': ['BONUS_SUMMARY'],
    'pick bonus': ['PICK_REVEAL'],
    'pick reveal': ['PICK_REVEAL'],
    'pick good': ['PICK_GOOD'],
    'pick bad': ['PICK_BAD'],
    'wheel spin': ['WHEEL_SPIN'],
    'wheel start': ['WHEEL_START'],
    'wheel stop': ['WHEEL_LAND'],
    'wheel result': ['WHEEL_LAND'],
    'wheel tick': ['WHEEL_TICK'],

    // ═══════════════════════════════════════════════════════════════════
    // HOLD AND WIN → HOLD_TRIGGER, HOLD_START, RESPIN_*
    // ═══════════════════════════════════════════════════════════════════
    'hold win': ['HOLD_TRIGGER'],
    'hold and win': ['HOLD_TRIGGER'],
    'hnw': ['HOLD_TRIGGER'],
    'hold trigger': ['HOLD_TRIGGER'],
    'hold start': ['HOLD_START'],
    'hold lock': ['HOLD_LOCK', 'COIN_LOCK'],
    'hold end': ['HOLD_END'],
    'lock': ['HOLD_LOCK', 'COIN_LOCK'],
    'coin land': ['COIN_LAND'],
    'coin lock': ['COIN_LOCK'],
    'respin': ['RESPIN_START'],
    'respin start': ['RESPIN_START'],
    'respin spin': ['RESPIN_SPIN'],
    'respin loop': ['RESPIN_SPIN'],
    'respin stop': ['RESPIN_STOP'],
    'respin end': ['RESPIN_END'],

    // ═══════════════════════════════════════════════════════════════════
    // CASCADE → CASCADE_START, CASCADE_STEP, CASCADE_END
    // ═══════════════════════════════════════════════════════════════════
    'cascade': ['CASCADE_START'],
    'cascade start': ['CASCADE_START'],
    'tumble': ['CASCADE_START', 'TUMBLE_DROP'],
    'avalanche': ['CASCADE_START', 'AVALANCHE_TRIGGER'],
    'cascade step': ['CASCADE_STEP'],
    'cascade fill': ['CASCADE_STEP'],
    'cascade end': ['CASCADE_END'],
    'cascade pop': ['CASCADE_POP'],

    // ═══════════════════════════════════════════════════════════════════
    // JACKPOT → JACKPOT_TRIGGER, JACKPOT_MINI/MINOR/MAJOR/GRAND
    // ═══════════════════════════════════════════════════════════════════
    'jackpot': ['JACKPOT_TRIGGER'],
    'jackpot trigger': ['JACKPOT_TRIGGER'],
    'jackpot win': ['JACKPOT_AWARD'],
    'jackpot award': ['JACKPOT_AWARD'],
    'jackpot mini': ['JACKPOT_MINI'],
    'jackpot minor': ['JACKPOT_MINOR'],
    'jackpot major': ['JACKPOT_MAJOR'],
    'jackpot grand': ['JACKPOT_GRAND'],
    'jackpot mega': ['JACKPOT_MEGA'],
    'jackpot ultra': ['JACKPOT_ULTRA'],
    'jp mini': ['JACKPOT_MINI'],
    'jp minor': ['JACKPOT_MINOR'],
    'jp major': ['JACKPOT_MAJOR'],
    'jp grand': ['JACKPOT_GRAND'],

    // ═══════════════════════════════════════════════════════════════════
    // GAMBLE → GAMBLE_ENTER, GAMBLE_WIN, GAMBLE_LOSE
    // ═══════════════════════════════════════════════════════════════════
    'gamble': ['GAMBLE_ENTER'],
    'gamble enter': ['GAMBLE_ENTER'],
    'gamble start': ['GAMBLE_ENTER'],
    'double': ['GAMBLE_ENTER'],
    'gamble win': ['GAMBLE_WIN'],
    'gamble lose': ['GAMBLE_LOSE'],
    'gamble collect': ['GAMBLE_COLLECT'],
    'gamble exit': ['GAMBLE_EXIT'],
    'card flip': ['GAMBLE_CARD_FLIP'],

    // ═══════════════════════════════════════════════════════════════════
    // ANTICIPATION → ANTICIPATION_TENSION (+ per-reel R1-R4)
    // ═══════════════════════════════════════════════════════════════════
    'anticipation': ['ANTICIPATION_TENSION_R*', 'ANTICIPATION_TENSION'],
    'anticipation start': ['ANTICIPATION_TENSION_R*', 'ANTICIPATION_TENSION'],
    'anticipation end': ['ANTICIPATION_MISS'],
    'anticipation miss': ['ANTICIPATION_MISS'],
    'tension': ['ANTICIPATION_TENSION_R*', 'ANTICIPATION_TENSION'],
    'suspense': ['ANTICIPATION_TENSION_R*', 'ANTICIPATION_TENSION'],
    'suspension': ['ANTICIPATION_TENSION_R*', 'ANTICIPATION_TENSION'],
    'spins susp': ['ANTICIPATION_TENSION_R*', 'ANTICIPATION_TENSION'],
    'spin susp': ['ANTICIPATION_TENSION_R*', 'ANTICIPATION_TENSION'],
    'near miss': ['NEAR_MISS'],
    'nearmiss': ['NEAR_MISS'],

    // ═══════════════════════════════════════════════════════════════════
    // WILDS → WILD_LAND, WILD_EXPAND, WILD_STICKY
    // ═══════════════════════════════════════════════════════════════════
    'wild': ['WILD_LAND'],
    'wild expand': ['WILD_EXPAND'],
    'wild sticky': ['WILD_STICKY'],
    'wild transform': ['WILD_TRANSFORM'],
    'wild multiply': ['WILD_MULTIPLY'],
    'wild walk': ['WILD_WALKING'],
    'walking wild': ['WILD_WALKING'],
    'scatter': ['SCATTER_LAND'],

    // ═══════════════════════════════════════════════════════════════════
    // UI → UI_BUTTON_PRESS, UI_MENU_OPEN, etc.
    // ═══════════════════════════════════════════════════════════════════
    'button': ['UI_BUTTON_PRESS'],
    'button press': ['UI_BUTTON_PRESS'],
    'button hover': ['UI_BUTTON_HOVER'],
    'button release': ['UI_BUTTON_RELEASE'],
    'ui click': ['UI_BUTTON_PRESS'],
    'popup': ['UI_POPUP_OPEN'],
    'menu open': ['UI_MENU_OPEN'],
    'menu close': ['UI_MENU_CLOSE'],
    'notification': ['UI_NOTIFICATION'],

    // ═══════════════════════════════════════════════════════════════════
    // TRANSITIONS — "trn", "trans", "transition" prefixed files
    // ═══════════════════════════════════════════════════════════════════
    'transition': ['TRANSITION_SWOOSH', 'TRANSITION_IMPACT'],
    'transition swoosh': ['TRANSITION_SWOOSH'],
    'transition impact': ['TRANSITION_IMPACT'],
    'transition bg': ['TRANSITION_SWOOSH'],
    'trn bg': ['TRANSITION_SWOOSH'],
    'trn swoosh': ['TRANSITION_SWOOSH'],
    'trn impact': ['TRANSITION_IMPACT'],
    'trn': ['TRANSITION_SWOOSH', 'TRANSITION_IMPACT'],
    'transition to free spins': ['CONTEXT_BASE_TO_FS'],
    'transition to fs': ['CONTEXT_BASE_TO_FS'],
    'transition to bonus': ['CONTEXT_BASE_TO_BONUS'],
    'transition to hold': ['CONTEXT_BASE_TO_HOLDWIN'],
    'transition from free spins': ['CONTEXT_FS_TO_BASE'],
    'transition from fs': ['CONTEXT_FS_TO_BASE'],
    'transition from bonus': ['CONTEXT_BONUS_TO_BASE'],
    'transition from hold': ['CONTEXT_HOLDWIN_TO_BASE'],
    'context base to fs': ['CONTEXT_BASE_TO_FS'],
    'context fs to base': ['CONTEXT_FS_TO_BASE'],
    'context base to bonus': ['CONTEXT_BASE_TO_BONUS'],
    'context bonus to base': ['CONTEXT_BONUS_TO_BASE'],
    'swoosh': ['TRANSITION_SWOOSH'],
    'whoosh': ['TRANSITION_SWOOSH'],
    'impact': ['TRANSITION_IMPACT', 'SYMBOL_LAND'],
    'reveal': ['PICK_REVEAL', 'MYSTERY_REVEAL'],
    'collect': ['COLLECT_TRIGGER'],
    'coin collect': ['COIN_COLLECT'],

    // ═══════════════════════════════════════════════════════════════════
    // COINS & EFFECTS
    // ═══════════════════════════════════════════════════════════════════
    'coin burst': ['COIN_BURST'],
    'coin drop': ['COIN_DROP'],
    'coin shower': ['COIN_SHOWER'],
    'coin rain': ['COIN_RAIN'],
    'confetti': ['CONFETTI_BURST'],
    'fireworks': ['FIREWORKS_LAUNCH'],
    'screen shake': ['SCREEN_SHAKE'],

    // ═══════════════════════════════════════════════════════════════════
    // NUDGE / RESPIN → REEL_NUDGE, NUDGE_*
    // ═══════════════════════════════════════════════════════════════════
    'nudge': ['REEL_NUDGE'],
    'nudge up': ['NUDGE_UP'],
    'nudge down': ['NUDGE_DOWN'],

    // ═══════════════════════════════════════════════════════════════════
    // MEGAWAYS → MEGAWAYS_REVEAL
    // ═══════════════════════════════════════════════════════════════════
    'megaways': ['MEGAWAYS_REVEAL'],
    'megaways reveal': ['MEGAWAYS_REVEAL'],
    'megaways expand': ['MEGAWAYS_EXPAND'],

    // ═══════════════════════════════════════════════════════════════════
    // MULTIPLIER → MULTIPLIER_INCREASE, MULTIPLIER_APPLY
    // ═══════════════════════════════════════════════════════════════════
    'multiplier': ['MULTIPLIER_INCREASE'],
    'multiplier increase': ['MULTIPLIER_INCREASE'],
    'multiplier apply': ['MULTIPLIER_APPLY'],
    'multiplier reset': ['MULTIPLIER_RESET'],

    // ═══════════════════════════════════════════════════════════════════
    // VOICEOVER
    // ═══════════════════════════════════════════════════════════════════
    'vo win': ['VO_WIN_1'],
    'vo big win': ['VO_BIG_WIN'],
    'vo congrats': ['VO_CONGRATULATIONS'],
    'vo free spins': ['VO_FREE_SPINS'],
    'vo bonus': ['VO_BONUS'],

    // ═══════════════════════════════════════════════════════════════════
    // ATTRACT / IDLE
    // ═══════════════════════════════════════════════════════════════════
    'attract': ['ATTRACT_LOOP'],
    'attract loop': ['ATTRACT_LOOP'],
    'idle': ['IDLE_LOOP'],
    'idle loop': ['IDLE_LOOP'],
    'game start': ['GAME_START'],
    'game ready': ['GAME_READY'],
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
    } catch (e) {
      assert(() { debugPrint('[AudioMapping] JSON parse error: $e'); return true; }());
    }
    return null;
  }
}

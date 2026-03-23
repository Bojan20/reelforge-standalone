/// FFNC Rename Tool — converts legacy audio filenames to FFNC-compliant names.
///
/// Uses the existing alias system to identify stages, then generates
/// FFNC-compliant names with correct prefixes. Includes Levenshtein
/// distance typo suggestion for unmatched files.
///
/// Normalization mirrors slot_lab_project_provider.dart autoBindFromFolder()
/// exactly — CamelCase split, sfx_ strip, numeric prefix strip, level strip,
/// trailing variant strip, and all 6 resolution attempts.

import 'dart:io';
import 'package:path/path.dart' as p;

import 'ffnc_parser.dart';

/// Result of analyzing a single file for rename.
class FFNCRenameResult {
  final String originalPath;
  final String originalName;
  String? ffncName;
  final String? stage;
  final FFNCCategory? category;
  final bool isExactMatch;

  FFNCRenameResult({
    required this.originalPath,
    required this.originalName,
    this.ffncName,
    this.stage,
    this.category,
    this.isExactMatch = false,
  });

  bool get isMatched => ffncName != null;
}

/// Suggested stage for an unmatched filename (typo correction).
class StageSuggestion {
  final String stage;
  final String ffncName;
  final int distance;

  const StageSuggestion({
    required this.stage,
    required this.ffncName,
    required this.distance,
  });
}

class FFNCRenamer {
  static const _audioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

  /// Known stage names for typo suggestion. Populated from StageConfigurationService.
  final Set<String> _knownStages;

  /// Cache for Levenshtein suggestions per originalName to avoid recomputation.
  final Map<String, List<StageSuggestion>> _suggestionCache = {};

  FFNCRenamer({required Set<String> knownStages}) : _knownStages = knownStages;

  /// Analyze a folder and generate rename suggestions for all audio files.
  List<FFNCRenameResult> analyze(
    String folderPath,
    String? Function(String normalizedName, String fullName) resolveStage,
  ) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    _suggestionCache.clear();

    final results = <FFNCRenameResult>[];
    // Track generated FFNC names to detect collisions
    final usedNames = <String, int>{}; // ffncName → count

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => _audioExtensions.contains(p.extension(f.path).toLowerCase()))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (final file in files) {
      final originalName = p.basename(file.path);

      // Already FFNC? Keep as-is.
      if (const FFNCParser().isFFNC(originalName)) {
        final parsed = const FFNCParser().parse(originalName);
        results.add(FFNCRenameResult(
          originalPath: file.path,
          originalName: originalName,
          ffncName: originalName,
          stage: parsed?.stage,
          category: parsed?.category,
          isExactMatch: true,
        ));
        continue;
      }

      // Try all 6 normalization variants (mirrors autoBindFromFolder exactly)
      final stage = _resolveWithAllVariants(originalName, resolveStage);

      if (stage != null) {
        final category = categorizeStage(stage);
        final ffncName = generateFFNCName(stage, category, p.extension(originalName));
        results.add(FFNCRenameResult(
          originalPath: file.path,
          originalName: originalName,
          ffncName: ffncName,
          stage: stage,
          category: category,
          isExactMatch: true,
        ));
      } else {
        results.add(FFNCRenameResult(
          originalPath: file.path,
          originalName: originalName,
        ));
      }
    }

    // Resolve filename collisions — append _variant_a, _variant_b, etc.
    _resolveCollisions(results);

    return results;
  }

  /// Try all 6 normalization variants that autoBindFromFolder uses.
  /// This ensures the rename tool matches exactly the same files as autobind.
  String? _resolveWithAllVariants(
    String originalName,
    String? Function(String normalizedName, String fullName) resolveStage,
  ) {
    final rawName = _stripExtension(originalName);

    // CamelCase → snake_case (same 4-step regex as autoBindFromFolder)
    final snaked = rawName
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([a-zA-Z])(\d)'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'(\d)([a-zA-Z])'), (m) => '${m[1]}_${m[2]}');
    final name = snaked.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');

    // Strip numeric prefix (004_, 043_) but preserve multiplier (2_x)
    final stripped = RegExp(r'^\d+_x(_|$)').hasMatch(name)
        ? name
        : name.replaceFirst(RegExp(r'^\d+_'), '');

    // Strip trailing variant number (_2, _1)
    final base = stripped.replaceFirst(RegExp(r'_\d$'), '');

    // Strip level suffix (_level_1, _lv2, _level)
    final noLevel = base.replaceFirst(RegExp(r'_?(?:level|lv)_?\d*$'), '');

    // Strip sfx_ prefix + numeric catalog number
    final afterSfx = stripped.startsWith('sfx_') ? stripped.substring(4) : stripped;
    final noSfx = afterSfx.replaceFirst(RegExp(r'^\d+_'), '');
    final afterSfxBase = base.startsWith('sfx_') ? base.substring(4) : base;
    final noSfxBase = afterSfxBase.replaceFirst(RegExp(r'^\d+_'), '');
    final noSfxNoLevel = noLevel.startsWith('sfx_') ? noLevel.substring(4) : noLevel;
    final noSfxNoLevelClean = noSfxNoLevel.replaceFirst(RegExp(r'^\d+_'), '');

    // Try all 6 resolution attempts in same order as autoBindFromFolder
    return resolveStage(noSfx, noSfx) ??
        (stripped != noSfx ? resolveStage(stripped, stripped) : null) ??
        resolveStage(noSfxNoLevelClean, noSfxNoLevelClean) ??
        resolveStage(noSfxBase, noSfxBase) ??
        (noLevel != noSfxNoLevelClean ? resolveStage(noLevel, noLevel) : null) ??
        (base != noSfxBase ? resolveStage(base, stripped) : null);
  }

  /// Resolve filename collisions by appending _variant_a, _variant_b, etc.
  void _resolveCollisions(List<FFNCRenameResult> results) {
    final nameCount = <String, List<FFNCRenameResult>>{};
    for (final r in results) {
      if (r.ffncName != null) {
        nameCount.putIfAbsent(r.ffncName!, () => []).add(r);
      }
    }
    for (final entry in nameCount.entries) {
      if (entry.value.length <= 1) continue;
      // Multiple files mapping to same FFNC name → add variant suffix
      final ext = p.extension(entry.key);
      final stem = p.basenameWithoutExtension(entry.key);
      for (int i = 0; i < entry.value.length; i++) {
        final variant = String.fromCharCode(97 + (i % 26)); // a, b, c, ...
        entry.value[i].ffncName = '${stem}_variant_$variant$ext';
      }
    }
  }

  /// Generate FFNC filename from internal stage name.
  /// Reverse transformations: REEL_STOP_0 → sfx_reel_stop_1, etc.
  String generateFFNCName(String stage, FFNCCategory category, String extension) {
    final ext = extension.startsWith('.') ? extension : '.$extension';

    switch (category) {
      case FFNCCategory.sfx:
        var name = stage.toLowerCase();
        // Special win names FIRST (before generic win_present_ replace)
        if (name == 'win_present_low') {
          return 'sfx_win_low$ext';
        } else if (name == 'win_present_equal') {
          return 'sfx_win_equal$ext';
        } else if (name == 'win_present_end') {
          return 'sfx_win_end$ext';
        }
        // WIN_PRESENT_N → win_tier_N (numbered tiers)
        name = name.replaceFirst('win_present_', 'win_tier_');
        // REEL_STOP_N → reel_stop_(N+1) [0-based → 1-based]
        final reelStop = RegExp(r'^reel_stop_(\d+)$').firstMatch(name);
        if (reelStop != null) {
          final idx = int.parse(reelStop.group(1)!) + 1;
          name = 'reel_stop_$idx';
        }
        return 'sfx_$name$ext';

      case FFNCCategory.mus:
        var name = stage.toLowerCase();
        // Non-MUSIC_ prefixed stages that live on music bus
        // These need explicit mapping because they don't follow MUSIC_ convention
        if (name == 'big_win_start') return 'mus_big_win_loop$ext';
        if (name == 'big_win_end') return 'mus_big_win_end$ext';
        if (name == 'game_start') return 'mus_game_start$ext';
        if (name == 'fs_end') return 'mus_fs_end$ext';
        // MUSIC_ prefix → strip
        name = name.replaceFirst('music_', '');
        // BASE_ → base_game_ (word boundary safe)
        if (name.startsWith('base_')) {
          name = 'base_game_${name.substring(5)}';
          // Clean up trailing underscore if BASE was the whole thing
          if (name.endsWith('_')) name = name.substring(0, name.length - 1);
        }
        // FS_ → freespin_ (word boundary safe)
        if (name.startsWith('fs_')) {
          name = 'freespin_${name.substring(3)}';
        } else if (name == 'fs') {
          name = 'freespin';
        }
        // BIGWIN → big_win
        name = name.replaceFirst('bigwin', 'big_win');
        return 'mus_$name$ext';

      case FFNCCategory.amb:
        var name = stage.toLowerCase();
        // AMBIENT_ → strip
        name = name.replaceFirst('ambient_', '');
        // ATTRACT_*, IDLE_* → keep full stage (strip AMBIENT_ but keep ATTRACT/IDLE)
        if (stage.startsWith('ATTRACT_') || stage.startsWith('IDLE_')) {
          return 'amb_${stage.toLowerCase()}$ext';
        }
        // BASE → base_game
        if (name == 'base') name = 'base_game';
        // FS → freespin
        if (name == 'fs') name = 'freespin';
        // BIGWIN → big_win
        name = name.replaceFirst('bigwin', 'big_win');
        return 'amb_$name$ext';

      case FFNCCategory.trn:
        var name = stage.toLowerCase();
        // TRANSITION_ → strip, CONTEXT_ → keep as context_
        name = name.replaceFirst('transition_', '');
        // CONTEXT_ stages keep their prefix (they're not TRANSITION_ internally)
        if (!name.startsWith('context_')) {
          // Word-boundary safe replacements for abbreviations
          // Replace _base_ in middle (e.g., transition_base_to_fs)
          name = name.replaceAllMapped(
            RegExp(r'(^|_)base($|_)'),
            (m) => '${m[1]}base_game${m[2]}',
          );
          // Replace _fs_ in middle
          name = name.replaceAllMapped(
            RegExp(r'(^|_)fs($|_)'),
            (m) => '${m[1]}freespin${m[2]}',
          );
        }
        return 'trn_$name$ext';

      case FFNCCategory.ui:
        return '${stage.toLowerCase()}$ext';

      case FFNCCategory.vo:
        return '${stage.toLowerCase()}$ext';
    }
  }

  /// Determine FFNC category from internal stage name.
  /// Uses StageDefaults bus routing as authority — music bus (1) = mus_, sfx bus (2) = sfx_.
  FFNCCategory categorizeStage(String stage) {
    if (stage.startsWith('MUSIC_')) return FFNCCategory.mus;
    if (stage.startsWith('AMBIENT_') ||
        stage.startsWith('ATTRACT_') ||
        stage.startsWith('IDLE_')) {
      return FFNCCategory.amb;
    }
    if (stage.startsWith('TRANSITION_') ||
        stage.startsWith('CONTEXT_')) {
      return FFNCCategory.trn;
    }
    if (stage.startsWith('UI_')) return FFNCCategory.ui;
    if (stage.startsWith('VO_')) return FFNCCategory.vo;

    // Music-bus stages that don't start with MUSIC_ prefix
    // BIG_WIN_START = looping big win music, BIG_WIN_END = stinger + base music restart
    // GAME_START = base game music start composite
    const musicBusStages = {
      'BIG_WIN_START', 'BIG_WIN_END',
      'GAME_START',
      'MUSIC_BIGWIN',
      'FS_END', // FS outro music — plays during exit transition
    };
    if (musicBusStages.contains(stage)) return FFNCCategory.mus;

    return FFNCCategory.sfx;
  }

  /// Suggest closest known stages for an unmatched filename.
  /// Only returns suggestions with Levenshtein distance <= maxDistance.
  /// Results are cached per originalName to avoid expensive recomputation on rebuild.
  List<StageSuggestion> suggestStage(String unmatchedName, {int maxResults = 3, int maxDistance = 3}) {
    if (_suggestionCache.containsKey(unmatchedName)) {
      return _suggestionCache[unmatchedName]!;
    }

    // Normalize: strip extension, CamelCase→snake, lowercase, strip prefix
    // Then uppercase to match stage name format for fair comparison
    final normalized = _normalizeForSuggestion(unmatchedName).toUpperCase();
    if (normalized.isEmpty) {
      _suggestionCache[unmatchedName] = const [];
      return const [];
    }
    final suggestions = <StageSuggestion>[];

    for (final stage in _knownStages) {
      // Compare normalized input against stage name (both uppercase)
      final dist = levenshtein(normalized, stage);
      // Also try without common prefixes that alias system would strip
      final withoutSfx = normalized.startsWith('SFX_') ? normalized.substring(4) : normalized;
      final altDist = withoutSfx != normalized ? levenshtein(withoutSfx, stage) : dist;
      final bestDist = dist < altDist ? dist : altDist;
      if (bestDist <= maxDistance) {
        final category = categorizeStage(stage);
        suggestions.add(StageSuggestion(
          stage: stage,
          ffncName: generateFFNCName(stage, category, '.wav'),
          distance: bestDist,
        ));
      }
    }

    suggestions.sort((a, b) => a.distance.compareTo(b.distance));
    final result = suggestions.take(maxResults).toList();
    _suggestionCache[unmatchedName] = result;
    return result;
  }

  /// Copy files with FFNC names to output folder. Returns count of copied files.
  Future<int> copyRenamed(List<FFNCRenameResult> results, String outputPath) async {
    final outDir = Directory(outputPath);
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    int count = 0;
    for (final result in results) {
      if (result.ffncName == null) continue;
      final source = File(result.originalPath);
      final dest = File(p.join(outputPath, result.ffncName!));
      if (source.existsSync()) {
        // Don't overwrite existing files silently
        if (dest.existsSync()) continue;
        await source.copy(dest.path);
        count++;
      }
    }
    return count;
  }

  // ═══════════════════════════════════════════════════════════════
  // Utility
  // ═══════════════════════════════════════════════════════════════

  /// Strip audio extension (case-insensitive).
  String _stripExtension(String filename) {
    final lower = filename.toLowerCase();
    for (final ext in _audioExtensions) {
      if (lower.endsWith(ext)) {
        return filename.substring(0, filename.length - ext.length);
      }
    }
    return filename;
  }

  /// Normalize for Levenshtein suggestion (simpler than full resolve).
  String _normalizeForSuggestion(String filename) {
    var name = _stripExtension(filename);
    // CamelCase → snake_case
    name = name
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([a-zA-Z])(\d)'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'(\d)([a-zA-Z])'), (m) => '${m[1]}_${m[2]}');
    name = name.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    // Strip numeric prefix
    if (!RegExp(r'^\d+_x(_|$)').hasMatch(name)) {
      name = name.replaceFirst(RegExp(r'^\d+_'), '');
    }
    return name;
  }

  /// Levenshtein distance between two strings.
  static int levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    if (a == b) return 0;

    final aLen = a.length;
    final bLen = b.length;

    // Use single-row optimization (O(min(m,n)) space)
    var prev = List<int>.generate(bLen + 1, (j) => j);
    var curr = List<int>.filled(bLen + 1, 0);

    for (int i = 1; i <= aLen; i++) {
      curr[0] = i;
      for (int j = 1; j <= bLen; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = _min3(
          prev[j] + 1,     // deletion
          curr[j - 1] + 1, // insertion
          prev[j - 1] + cost, // substitution
        );
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[bLen];
  }

  static int _min3(int a, int b, int c) {
    if (a <= b && a <= c) return a;
    if (b <= c) return b;
    return c;
  }
}

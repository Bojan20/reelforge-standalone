/// FFNC Rename Tool — converts legacy audio filenames to FFNC-compliant names.
///
/// Uses the existing alias system to identify stages, then generates
/// FFNC-compliant names with correct prefixes. Includes Levenshtein
/// distance typo suggestion for unmatched files.

import 'dart:io';
import 'package:path/path.dart' as p;

import 'ffnc_parser.dart';

/// Result of analyzing a single file for rename.
class FFNCRenameResult {
  final String originalPath;
  final String originalName;
  final String? ffncName;
  final String? stage;
  final FFNCCategory? category;
  final bool isExactMatch;

  const FFNCRenameResult({
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

  FFNCRenamer({required Set<String> knownStages}) : _knownStages = knownStages;

  /// Analyze a folder and generate rename suggestions for all audio files.
  List<FFNCRenameResult> analyze(
    String folderPath,
    String? Function(String normalizedName, String fullName) resolveStage,
  ) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    final results = <FFNCRenameResult>[];
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

      // Normalize and resolve via existing alias system
      final normalized = _normalizeForResolve(originalName);
      final stage = resolveStage(normalized, originalName);

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

    return results;
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
        // MUSIC_ prefix → strip
        name = name.replaceFirst('music_', '');
        // BASE_ → base_game_
        name = name.replaceFirst(RegExp(r'^base_'), 'base_game_');
        // FS_ → freespin_
        name = name.replaceFirst(RegExp(r'^fs_'), 'freespin_');
        // BIGWIN → big_win
        name = name.replaceFirst('bigwin', 'big_win');
        return 'mus_$name$ext';

      case FFNCCategory.amb:
        var name = stage.toLowerCase();
        // AMBIENT_ → strip
        name = name.replaceFirst('ambient_', '');
        // BASE → base_game
        if (name == 'base') name = 'base_game';
        // FS → freespin
        if (name == 'fs') name = 'freespin';
        // BIGWIN → big_win
        name = name.replaceFirst('bigwin', 'big_win');
        // ATTRACT_*, IDLE_* → keep as-is (already stripped prefix)
        if (stage.startsWith('ATTRACT_') || stage.startsWith('IDLE_')) {
          return 'amb_${stage.toLowerCase()}$ext';
        }
        return 'amb_$name$ext';

      case FFNCCategory.trn:
        var name = stage.toLowerCase();
        // TRANSITION_ → strip
        name = name.replaceFirst('transition_', '');
        // BASE → base_game
        name = name.replaceAll('_base_', '_base_game_');
        name = name.replaceAll('_base', '_base_game');
        if (name.startsWith('base_')) name = name.replaceFirst('base_', 'base_game_');
        // FS → freespin
        name = name.replaceAll('_fs_', '_freespin_');
        name = name.replaceAll('_fs', '_freespin');
        if (name.startsWith('fs_')) name = name.replaceFirst('fs_', 'freespin_');
        return 'trn_$name$ext';

      case FFNCCategory.ui:
        return '${stage.toLowerCase()}$ext';

      case FFNCCategory.vo:
        return '${stage.toLowerCase()}$ext';
    }
  }

  /// Determine FFNC category from internal stage name.
  FFNCCategory categorizeStage(String stage) {
    if (stage.startsWith('MUSIC_')) return FFNCCategory.mus;
    if (stage.startsWith('AMBIENT_') ||
        stage.startsWith('ATTRACT_') ||
        stage.startsWith('IDLE_')) {
      return FFNCCategory.amb;
    }
    if (stage.startsWith('TRANSITION_')) return FFNCCategory.trn;
    if (stage.startsWith('UI_')) return FFNCCategory.ui;
    if (stage.startsWith('VO_')) return FFNCCategory.vo;
    return FFNCCategory.sfx;
  }

  /// Suggest closest known stages for an unmatched filename.
  /// Only returns suggestions with Levenshtein distance <= maxDistance.
  List<StageSuggestion> suggestStage(String unmatchedName, {int maxResults = 3, int maxDistance = 3}) {
    // Normalize: strip extension, lowercase, strip numeric prefix
    // Then uppercase to match stage name format for fair comparison
    final normalized = _normalizeForResolve(unmatchedName).toUpperCase();
    if (normalized.isEmpty) return [];
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
    return suggestions.take(maxResults).toList();
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
        await source.copy(dest.path);
        count++;
      }
    }
    return count;
  }

  // ═══════════════════════════════════════════════════════════════
  // Utility
  // ═══════════════════════════════════════════════════════════════

  /// Normalize filename for alias resolution (strip extension, lowercase, basic cleanup).
  String _normalizeForResolve(String filename) {
    var name = filename;
    // Strip extension
    for (final ext in _audioExtensions) {
      if (name.toLowerCase().endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    // Lowercase, replace spaces/hyphens with underscore
    name = name.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    // Strip numeric prefix (004_, 043_)
    name = name.replaceFirst(RegExp(r'^\d{2,4}_'), '');
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

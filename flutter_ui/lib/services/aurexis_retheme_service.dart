import 'dart:math' as math;
import '../models/aurexis_retheme.dart';

/// AUREXIS™ Re-Theme Service — Fuzzy matching engine.
///
/// Provides intelligent file matching between source and target
/// audio themes using multiple strategies and confidence scoring.
class AurexisReThemeService {
  AurexisReThemeService._();

  /// Run auto-matching with the selected strategy.
  static ReThemeMapping autoMatch({
    required String sourceTheme,
    required String targetTheme,
    required List<String> sourceFiles,
    required List<String> targetFiles,
    required ReThemeMatchStrategy strategy,
    double fuzzyThreshold = 0.7,
    Map<String, String>? stageAssignments,
  }) {
    final mappings = <ReThemeFileMapping>[];
    final usedTargets = <String>{};

    for (final source in sourceFiles) {
      final match = _findBestMatch(
        source: source,
        targetFiles: targetFiles,
        usedTargets: usedTargets,
        strategy: strategy,
        sourceTheme: sourceTheme,
        targetTheme: targetTheme,
        fuzzyThreshold: fuzzyThreshold,
        stageAssignments: stageAssignments,
      );

      mappings.add(match);
      if (match.targetPath != null) {
        usedTargets.add(match.targetPath!);
      }
    }

    return ReThemeMapping(
      sourceTheme: sourceTheme,
      targetTheme: targetTheme,
      sourceDir: '',
      targetDir: '',
      mappings: mappings,
      strategy: strategy,
      fuzzyThreshold: fuzzyThreshold,
    );
  }

  static ReThemeFileMapping _findBestMatch({
    required String source,
    required List<String> targetFiles,
    required Set<String> usedTargets,
    required ReThemeMatchStrategy strategy,
    required String sourceTheme,
    required String targetTheme,
    required double fuzzyThreshold,
    Map<String, String>? stageAssignments,
  }) {
    String? bestTarget;
    double bestScore = 0.0;

    final availableTargets =
        targetFiles.where((t) => !usedTargets.contains(t)).toList();

    for (final target in availableTargets) {
      final score = switch (strategy) {
        ReThemeMatchStrategy.namePattern =>
          _namePatternScore(source, target, sourceTheme, targetTheme),
        ReThemeMatchStrategy.stageMapping =>
          _stageMappingScore(source, target, stageAssignments),
        ReThemeMatchStrategy.folderStructure =>
          _folderStructureScore(source, target),
        ReThemeMatchStrategy.manual => 0.0,
      };

      if (score > bestScore && score >= fuzzyThreshold) {
        bestScore = score;
        bestTarget = target;
      }
    }

    return ReThemeFileMapping(
      sourcePath: source,
      targetPath: bestTarget,
      stageName: stageAssignments?[source],
      confidenceScore: bestScore,
      strategy: strategy,
    );
  }

  /// Name pattern matching: strip theme prefix, compare remaining structure.
  static double _namePatternScore(
    String source,
    String target,
    String sourceTheme,
    String targetTheme,
  ) {
    // Normalize filenames
    final srcName = _extractFilename(source).toLowerCase();
    final tgtName = _extractFilename(target).toLowerCase();
    final srcThemeNorm = sourceTheme.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final tgtThemeNorm = targetTheme.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Strip theme name from both filenames
    String srcStripped = srcName.replaceAll(srcThemeNorm, '');
    String tgtStripped = tgtName.replaceAll(tgtThemeNorm, '');

    // Also try removing common separator patterns
    srcStripped = srcStripped.replaceAll(RegExp(r'^[_\-\.]+|[_\-\.]+$'), '');
    tgtStripped = tgtStripped.replaceAll(RegExp(r'^[_\-\.]+|[_\-\.]+$'), '');

    // Exact match after stripping
    if (srcStripped == tgtStripped && srcStripped.isNotEmpty) {
      return 1.0;
    }

    // Fuzzy similarity
    return _levenshteinSimilarity(srcStripped, tgtStripped);
  }

  /// Stage mapping: match files assigned to the same stage/event.
  static double _stageMappingScore(
    String source,
    String target,
    Map<String, String>? stageAssignments,
  ) {
    if (stageAssignments == null) return 0.0;

    final srcStage = stageAssignments[source];
    final tgtStage = stageAssignments[target];

    if (srcStage == null || tgtStage == null) return 0.0;
    if (srcStage == tgtStage) return 0.95;

    // Partial stage name match
    return _levenshteinSimilarity(srcStage.toLowerCase(), tgtStage.toLowerCase()) * 0.8;
  }

  /// Folder structure matching: compare directory depth and relative position.
  static double _folderStructureScore(String source, String target) {
    final srcParts = source.split('/');
    final tgtParts = target.split('/');

    // Compare directory depth
    final depthDiff = (srcParts.length - tgtParts.length).abs();
    double depthScore = depthDiff == 0 ? 1.0 : 1.0 / (1.0 + depthDiff);

    // Compare folder names (excluding file name and root theme folder)
    double folderScore = 0.0;
    if (srcParts.length > 2 && tgtParts.length > 2) {
      final srcFolders = srcParts.sublist(1, srcParts.length - 1);
      final tgtFolders = tgtParts.sublist(1, tgtParts.length - 1);

      int matches = 0;
      for (final sf in srcFolders) {
        if (tgtFolders.contains(sf)) matches++;
      }
      final maxLen = math.max(srcFolders.length, tgtFolders.length);
      folderScore = maxLen > 0 ? matches / maxLen : 0.0;
    }

    // Compare file names directly (fuzzy)
    final srcFile = _extractFilename(source);
    final tgtFile = _extractFilename(target);
    final fileScore = _levenshteinSimilarity(srcFile, tgtFile);

    // Weighted combination
    return depthScore * 0.2 + folderScore * 0.3 + fileScore * 0.5;
  }

  /// Levenshtein distance-based similarity (0.0-1.0).
  static double _levenshteinSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final distance = _levenshteinDistance(a, b);
    final maxLen = math.max(a.length, b.length);
    return 1.0 - (distance / maxLen);
  }

  /// Classic Levenshtein distance.
  static int _levenshteinDistance(String a, String b) {
    final la = a.length;
    final lb = b.length;

    // Use two rows instead of full matrix
    var prevRow = List<int>.generate(lb + 1, (i) => i);
    var currRow = List<int>.filled(lb + 1, 0);

    for (int i = 1; i <= la; i++) {
      currRow[0] = i;
      for (int j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        currRow[j] = [
          currRow[j - 1] + 1, // insertion
          prevRow[j] + 1, // deletion
          prevRow[j - 1] + cost, // substitution
        ].reduce(math.min);
      }
      final temp = prevRow;
      prevRow = currRow;
      currRow = temp;
    }

    return prevRow[lb];
  }

  /// Extract filename without path.
  static String _extractFilename(String path) {
    final lastSlash = path.lastIndexOf('/');
    final name = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
    // Remove extension
    final lastDot = name.lastIndexOf('.');
    return lastDot > 0 ? name.substring(0, lastDot) : name;
  }

  /// Re-match a single file with a specific target (manual override).
  static ReThemeMapping overrideMapping({
    required ReThemeMapping mapping,
    required int index,
    required String? newTarget,
  }) {
    final updated = List<ReThemeFileMapping>.from(mapping.mappings);
    updated[index] = updated[index].copyWith(
      targetPath: newTarget,
      confidenceScore: newTarget != null ? 1.0 : 0.0,
      strategy: ReThemeMatchStrategy.manual,
      userConfirmed: true,
    );
    return mapping.copyWith(mappings: updated);
  }

  /// Confirm a mapping (user reviewed and approved).
  static ReThemeMapping confirmMapping({
    required ReThemeMapping mapping,
    required int index,
  }) {
    final updated = List<ReThemeFileMapping>.from(mapping.mappings);
    updated[index] = updated[index].copyWith(userConfirmed: true);
    return mapping.copyWith(mappings: updated);
  }
}

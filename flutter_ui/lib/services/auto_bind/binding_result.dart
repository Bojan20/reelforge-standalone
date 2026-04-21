/// AutoBind result types — pure data, no Flutter dependency.
///
/// Used by AutoBindEngine.analyze() and the dialog UI.
// ──────────────────────────────────────────────────────────────────────────────
// ENUMS
// ──────────────────────────────────────────────────────────────────────────────

/// How the stage was resolved from the filename.
/// Higher ordinal → less certain match.
enum MatchMethod {
  /// sfx_ / mus_ / amb_ / trn_ / ui_ / vo_ prefix — 100% accurate.
  ffncPrefix,

  /// Exact match after normalization (snake_case, trim, lowercase).
  exactAlias,

  /// Longest-prefix alias match.
  prefixAlias,

  /// Alias match after stripping underscores (glued form).
  gluedAlias,

  /// NofM pattern: "3of5" → indexed stage.
  nofm,

  /// Multiplier pattern: "2x" → WIN_PRESENT_1.
  multiplier,

  /// Win-tier pattern: "win3" → WIN_PRESENT_3.
  winTier,

  /// Symbol-pay pattern: "hp1" → HP_WIN_1.
  symbolPay,

  /// Fuzzy token matching (lowest confidence, still usable).
  fuzzyToken,

  /// User manually assigned via the dialog.
  manual,
}

/// Severity of a binding warning.
enum WarningSeverity { info, warning, error }

// ──────────────────────────────────────────────────────────────────────────────
// RESULT TYPES
// ──────────────────────────────────────────────────────────────────────────────

/// A single file → stage binding.
class BindingMatch {
  final String filePath;
  final String fileName;
  final String stage;

  /// Confidence score 0–100. Higher → more certain.
  final int score;

  final MatchMethod method;

  /// Pre-generated FFNC rename target (e.g. "sfx_reel_spin_loop.wav").
  final String? ffncName;

  /// True if another file already occupies this stage (round-robin pool).
  final bool isVariant;

  /// 1-based layer index (MUSIC_BASE_L2 = layer 2). null for non-layered.
  final int? layer;

  const BindingMatch({
    required this.filePath,
    required this.fileName,
    required this.stage,
    required this.score,
    required this.method,
    this.ffncName,
    this.isVariant = false,
    this.layer,
  });

  /// Human-readable match method label.
  String get methodLabel {
    switch (method) {
      case MatchMethod.ffncPrefix:  return 'FFNC';
      case MatchMethod.exactAlias:  return 'Exact';
      case MatchMethod.prefixAlias: return 'Alias';
      case MatchMethod.gluedAlias:  return 'Alias';
      case MatchMethod.nofm:        return 'NofM';
      case MatchMethod.multiplier:  return 'Mult';
      case MatchMethod.winTier:     return 'Tier';
      case MatchMethod.symbolPay:   return 'Sym';
      case MatchMethod.fuzzyToken:  return 'Fuzzy';
      case MatchMethod.manual:      return 'Manual';
    }
  }

  /// Color hint for the UI (not a Flutter Color — returned as int ARGB).
  int get methodColor {
    switch (method) {
      case MatchMethod.ffncPrefix:  return 0xFF50FF98; // green
      case MatchMethod.exactAlias:  return 0xFF50FF98;
      case MatchMethod.prefixAlias: return 0xFF50D8FF; // cyan
      case MatchMethod.gluedAlias:  return 0xFF50D8FF;
      case MatchMethod.nofm:        return 0xFFFFD050; // yellow
      case MatchMethod.multiplier:  return 0xFFFFD050;
      case MatchMethod.winTier:     return 0xFFFFD050;
      case MatchMethod.symbolPay:   return 0xFFFFD050;
      case MatchMethod.fuzzyToken:  return 0xFFFF9850; // orange (low confidence)
      case MatchMethod.manual:      return 0xFF9080FF; // purple
    }
  }

  BindingMatch copyWith({
    String? stage,
    int? score,
    MatchMethod? method,
    String? ffncName,
    bool? isVariant,
    int? layer,
  }) => BindingMatch(
    filePath: filePath,
    fileName: fileName,
    stage: stage ?? this.stage,
    score: score ?? this.score,
    method: method ?? this.method,
    ffncName: ffncName ?? this.ffncName,
    isVariant: isVariant ?? this.isVariant,
    layer: layer ?? this.layer,
  );
}

/// A file that could not be matched to any stage.
class UnmatchedFile {
  final String filePath;
  final String fileName;

  /// Levenshtein suggestions from the scorer, sorted by score.
  final List<StageSuggestion> suggestions;

  const UnmatchedFile({
    required this.filePath,
    required this.fileName,
    this.suggestions = const [],
  });
}

/// A stage suggestion from fuzzy matching.
class StageSuggestion {
  final String stage;
  final int score;
  const StageSuggestion({required this.stage, required this.score});
}

/// A warning produced during analysis.
class BindingWarning {
  final String message;
  final WarningSeverity severity;
  final String? stage;
  final String? filePath;

  const BindingWarning({
    required this.message,
    required this.severity,
    this.stage,
    this.filePath,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// ANALYSIS RESULT
// ──────────────────────────────────────────────────────────────────────────────

/// Complete result of AutoBindEngine.analyze().
///
/// Immutable — produced by analysis, consumed by dialog and apply().
class BindingAnalysis {
  /// All successfully matched files (primary + variants).
  final List<BindingMatch> matched;

  /// Files that could not be matched.
  final List<UnmatchedFile> unmatched;

  /// Non-fatal warnings the user should see.
  final List<BindingWarning> warnings;

  /// Stage → [primary, variant1, variant2, ...] grouping.
  final Map<String, List<BindingMatch>> stageGroups;

  const BindingAnalysis({
    required this.matched,
    required this.unmatched,
    required this.warnings,
    required this.stageGroups,
  });

  int get totalFiles => matched.length + unmatched.length;
  int get matchedCount => matched.length;
  int get unmatchedCount => unmatched.length;
  double get matchRate => totalFiles == 0 ? 0 : matched.length / totalFiles;

  /// Unique stages bound (no variants counted twice).
  int get uniqueStageCount => stageGroups.keys.length;

  /// Returns a copy with a manual override applied.
  BindingAnalysis withManualOverride(UnmatchedFile file, String stage, {String? ffncName}) {
    final newMatch = BindingMatch(
      filePath: file.filePath,
      fileName: file.fileName,
      stage: stage,
      score: 100,
      method: MatchMethod.manual,
      ffncName: ffncName,
    );
    final newMatched = [...matched, newMatch];
    final newUnmatched = unmatched.where((u) => u.filePath != file.filePath).toList();
    final newGroups = Map<String, List<BindingMatch>>.from(stageGroups);
    newGroups.putIfAbsent(stage, () => []);
    newGroups[stage]!.add(newMatch);
    return BindingAnalysis(
      matched: newMatched,
      unmatched: newUnmatched,
      warnings: warnings,
      stageGroups: newGroups,
    );
  }
}

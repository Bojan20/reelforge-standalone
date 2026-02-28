import 'dart:convert';

/// AUREXIS™ Re-Theme Wizard — Models for audio theme replacement.
///
/// Enables re-skinning slot audio assets from one theme to another
/// while preserving AUREXIS profile configuration and game math.

/// Strategy for matching source → target audio files.
enum ReThemeMatchStrategy {
  /// Match by filename pattern: {theme}_spin_start → {newTheme}_spin_start.
  namePattern,

  /// Match by assigned stage/event name.
  stageMapping,

  /// Match by relative folder position and structure.
  folderStructure,

  /// All files manually assigned by user.
  manual;

  String get label => switch (this) {
        namePattern => 'Name Pattern',
        stageMapping => 'Stage Mapping',
        folderStructure => 'Folder Structure',
        manual => 'Manual',
      };

  String get description => switch (this) {
        namePattern => 'Matches files by replacing theme prefix in filenames',
        stageMapping => 'Maps files based on their assigned stage/event names',
        folderStructure => 'Matches by relative position in directory hierarchy',
        manual => 'User manually assigns all file pairs',
      };
}

/// Confidence level for a match.
enum MatchConfidence {
  /// 90-100% confidence (exact structural match).
  high,

  /// 70-89% confidence (fuzzy match).
  medium,

  /// 50-69% confidence (partial match, needs review).
  low,

  /// Below 50% confidence (likely wrong).
  veryLow,

  /// No match found.
  none;

  String get label => switch (this) {
        high => 'High',
        medium => 'Medium',
        low => 'Low',
        veryLow => 'Very Low',
        none => 'None',
      };

  double get minScore => switch (this) {
        high => 0.9,
        medium => 0.7,
        low => 0.5,
        veryLow => 0.3,
        none => 0.0,
      };

  static MatchConfidence fromScore(double score) {
    if (score >= 0.9) return high;
    if (score >= 0.7) return medium;
    if (score >= 0.5) return low;
    if (score >= 0.3) return veryLow;
    return none;
  }
}

/// A single source-to-target audio file mapping.
class ReThemeFileMapping {
  /// Source audio file path (relative).
  final String sourcePath;

  /// Target audio file path (relative). Null if unmatched.
  final String? targetPath;

  /// Stage/event name this file is assigned to.
  final String? stageName;

  /// Match confidence score (0.0-1.0).
  final double confidenceScore;

  /// Which strategy produced this match.
  final ReThemeMatchStrategy strategy;

  /// Whether user manually confirmed this mapping.
  final bool userConfirmed;

  const ReThemeFileMapping({
    required this.sourcePath,
    this.targetPath,
    this.stageName,
    this.confidenceScore = 0.0,
    this.strategy = ReThemeMatchStrategy.manual,
    this.userConfirmed = false,
  });

  MatchConfidence get confidence => MatchConfidence.fromScore(confidenceScore);
  bool get isMatched => targetPath != null;
  bool get needsReview => confidenceScore < 0.7 && targetPath != null;

  ReThemeFileMapping copyWith({
    String? sourcePath,
    String? targetPath,
    String? stageName,
    double? confidenceScore,
    ReThemeMatchStrategy? strategy,
    bool? userConfirmed,
  }) {
    return ReThemeFileMapping(
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      stageName: stageName ?? this.stageName,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      strategy: strategy ?? this.strategy,
      userConfirmed: userConfirmed ?? this.userConfirmed,
    );
  }

  Map<String, dynamic> toJson() => {
        'source': sourcePath,
        'target': targetPath,
        'stage': stageName,
        'confidence': confidenceScore,
        'strategy': strategy.name,
        'confirmed': userConfirmed,
      };

  factory ReThemeFileMapping.fromJson(Map<String, dynamic> json) {
    return ReThemeFileMapping(
      sourcePath: json['source'] as String,
      targetPath: json['target'] as String?,
      stageName: json['stage'] as String?,
      confidenceScore: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      strategy: ReThemeMatchStrategy.values.firstWhere(
        (s) => s.name == json['strategy'],
        orElse: () => ReThemeMatchStrategy.manual,
      ),
      userConfirmed: json['confirmed'] as bool? ?? false,
    );
  }
}

/// Complete re-theme mapping between source and target themes.
class ReThemeMapping {
  /// Source theme name.
  final String sourceTheme;

  /// Target theme name.
  final String targetTheme;

  /// Source audio directory.
  final String sourceDir;

  /// Target audio directory.
  final String targetDir;

  /// All file mappings.
  final List<ReThemeFileMapping> mappings;

  /// Default matching strategy.
  final ReThemeMatchStrategy strategy;

  /// Fuzzy match threshold (0.0-1.0).
  final double fuzzyThreshold;

  /// When this mapping was created.
  final DateTime createdAt;

  ReThemeMapping({
    required this.sourceTheme,
    required this.targetTheme,
    required this.sourceDir,
    required this.targetDir,
    this.mappings = const [],
    this.strategy = ReThemeMatchStrategy.namePattern,
    this.fuzzyThreshold = 0.7,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get totalCount => mappings.length;
  int get matchedCount => mappings.where((m) => m.isMatched).length;
  int get unmatchedCount => mappings.where((m) => !m.isMatched).length;
  int get reviewCount => mappings.where((m) => m.needsReview).length;
  int get confirmedCount => mappings.where((m) => m.userConfirmed).length;
  double get matchPercent =>
      totalCount > 0 ? matchedCount / totalCount : 0.0;

  double get avgConfidence {
    final matched = mappings.where((m) => m.isMatched).toList();
    if (matched.isEmpty) return 0.0;
    return matched.fold<double>(0.0, (sum, m) => sum + m.confidenceScore) /
        matched.length;
  }

  /// Get mappings filtered by status.
  List<ReThemeFileMapping> get matchedMappings =>
      mappings.where((m) => m.isMatched).toList();

  List<ReThemeFileMapping> get unmatchedMappings =>
      mappings.where((m) => !m.isMatched).toList();

  List<ReThemeFileMapping> get conflictMappings =>
      mappings.where((m) => m.needsReview).toList();

  ReThemeMapping copyWith({
    String? sourceTheme,
    String? targetTheme,
    String? sourceDir,
    String? targetDir,
    List<ReThemeFileMapping>? mappings,
    ReThemeMatchStrategy? strategy,
    double? fuzzyThreshold,
  }) {
    return ReThemeMapping(
      sourceTheme: sourceTheme ?? this.sourceTheme,
      targetTheme: targetTheme ?? this.targetTheme,
      sourceDir: sourceDir ?? this.sourceDir,
      targetDir: targetDir ?? this.targetDir,
      mappings: mappings ?? this.mappings,
      strategy: strategy ?? this.strategy,
      fuzzyThreshold: fuzzyThreshold ?? this.fuzzyThreshold,
      createdAt: createdAt,
    );
  }

  String toJsonString() => jsonEncode({
        'sourceTheme': sourceTheme,
        'targetTheme': targetTheme,
        'sourceDir': sourceDir,
        'targetDir': targetDir,
        'strategy': strategy.name,
        'fuzzyThreshold': fuzzyThreshold,
        'createdAt': createdAt.toIso8601String(),
        'mappings': mappings.map((m) => m.toJson()).toList(),
      });

  factory ReThemeMapping.fromJson(Map<String, dynamic> json) {
    return ReThemeMapping(
      sourceTheme: json['sourceTheme'] as String,
      targetTheme: json['targetTheme'] as String,
      sourceDir: json['sourceDir'] as String? ?? '',
      targetDir: json['targetDir'] as String? ?? '',
      strategy: ReThemeMatchStrategy.values.firstWhere(
        (s) => s.name == json['strategy'],
        orElse: () => ReThemeMatchStrategy.namePattern,
      ),
      fuzzyThreshold: (json['fuzzyThreshold'] as num?)?.toDouble() ?? 0.7,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      mappings: (json['mappings'] as List<dynamic>?)
              ?.map(
                  (m) => ReThemeFileMapping.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Create a reversed mapping (target → source).
  ReThemeMapping reversed() {
    return ReThemeMapping(
      sourceTheme: targetTheme,
      targetTheme: sourceTheme,
      sourceDir: targetDir,
      targetDir: sourceDir,
      strategy: strategy,
      fuzzyThreshold: fuzzyThreshold,
      mappings: mappings
          .where((m) => m.isMatched)
          .map((m) => ReThemeFileMapping(
                sourcePath: m.targetPath!,
                targetPath: m.sourcePath,
                stageName: m.stageName,
                confidenceScore: m.confidenceScore,
                strategy: m.strategy,
                userConfirmed: m.userConfirmed,
              ))
          .toList(),
    );
  }
}

/// Wizard step tracking.
enum ReThemeWizardStep {
  /// Step 1: Select/confirm source project.
  source,

  /// Step 2: Select target theme audio folder.
  target,

  /// Step 3: Review matches and apply.
  review;

  String get label => switch (this) {
        source => 'Source',
        target => 'Target',
        review => 'Review',
      };

  int get stepIndex => switch (this) {
        source => 0,
        target => 1,
        review => 2,
      };
}

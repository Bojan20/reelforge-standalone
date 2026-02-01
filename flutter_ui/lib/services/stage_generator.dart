/// StageGenerator - Stage generation from feature blocks for Feature Builder
///
/// Generates, deduplicates, and resolves stages from enabled feature blocks.
/// Exports to StageConfigurationService for runtime use.
/// Part of P13 Feature Builder Panel implementation.

import '../models/feature_block_models.dart';
import '../spatial/auto_spatial.dart' show SpatialBus;
import 'dependency_resolver.dart' as resolver;
import 'stage_configuration_service.dart';

/// Result of stage generation
class StageGenerationResult {
  /// Whether generation was successful
  final bool isValid;

  /// All generated stages (deduplicated)
  final List<GeneratedStageEntry> stages;

  /// Stage conflicts that were resolved
  final List<StageConflict> resolvedConflicts;

  /// Warnings during generation
  final List<StageWarning> warnings;

  /// Statistics about generation
  final StageGenerationStats stats;

  const StageGenerationResult({
    required this.isValid,
    required this.stages,
    this.resolvedConflicts = const [],
    this.warnings = const [],
    required this.stats,
  });

  /// Get stages by category
  List<GeneratedStageEntry> getStagesByCategory(String category) {
    return stages.where((s) => s.category == category).toList();
  }

  /// Get stages by bus
  List<GeneratedStageEntry> getStagesByBus(String bus) {
    return stages.where((s) => s.stage.bus == bus).toList();
  }

  /// Get pooled stages only
  List<GeneratedStageEntry> get pooledStages {
    return stages.where((s) => s.stage.pooled).toList();
  }

  /// Get looping stages only
  List<GeneratedStageEntry> get loopingStages {
    return stages.where((s) => s.stage.looping).toList();
  }
}

/// Entry for a generated stage with source info
class GeneratedStageEntry {
  /// The generated stage
  final GeneratedStage stage;

  /// Block ID that generated this stage
  final String sourceBlockId;

  /// Category for organization
  final String category;

  /// Whether this was merged from multiple blocks
  final bool isMerged;

  /// Original block IDs if merged
  final List<String> mergedFrom;

  const GeneratedStageEntry({
    required this.stage,
    required this.sourceBlockId,
    required this.category,
    this.isMerged = false,
    this.mergedFrom = const [],
  });

  /// Stage name for quick access
  String get name => stage.name;

  /// Create a merged entry
  factory GeneratedStageEntry.merged({
    required GeneratedStage stage,
    required List<String> fromBlocks,
    required String category,
  }) {
    return GeneratedStageEntry(
      stage: stage,
      sourceBlockId: fromBlocks.first,
      category: category,
      isMerged: true,
      mergedFrom: fromBlocks,
    );
  }
}

/// Represents a stage conflict that was resolved
class StageConflict {
  /// Stage name
  final String stageName;

  /// Block IDs that both generated this stage
  final List<String> conflictingBlocks;

  /// How it was resolved
  final ConflictResolution resolution;

  /// Final priority used
  final int finalPriority;

  /// Final bus used
  final String finalBus;

  const StageConflict({
    required this.stageName,
    required this.conflictingBlocks,
    required this.resolution,
    required this.finalPriority,
    required this.finalBus,
  });
}

/// How a stage conflict was resolved
enum ConflictResolution {
  /// Used higher priority
  higherPriority,

  /// Used first definition
  firstDefined,

  /// Merged properties
  merged,

  /// Used dependency order
  dependencyOrder,

  /// Used category priority
  categoryPriority,
}

/// Warning during stage generation
class StageWarning {
  /// Stage name
  final String stageName;

  /// Block ID
  final String blockId;

  /// Warning message
  final String message;

  const StageWarning({
    required this.stageName,
    required this.blockId,
    required this.message,
  });
}

/// Statistics about stage generation
class StageGenerationStats {
  /// Total stages before deduplication
  final int totalRaw;

  /// Total stages after deduplication
  final int totalFinal;

  /// Number of pooled stages
  final int pooledCount;

  /// Number of looping stages
  final int loopingCount;

  /// Stages per bus
  final Map<String, int> stagesPerBus;

  /// Stages per category
  final Map<String, int> stagesPerCategory;

  /// Blocks that contributed stages
  final int contributingBlocks;

  const StageGenerationStats({
    required this.totalRaw,
    required this.totalFinal,
    required this.pooledCount,
    required this.loopingCount,
    required this.stagesPerBus,
    required this.stagesPerCategory,
    required this.contributingBlocks,
  });

  /// Deduplication ratio
  double get deduplicationRatio =>
      totalRaw > 0 ? (totalRaw - totalFinal) / totalRaw : 0.0;
}

/// Service for generating stages from blocks
class StageGenerator {
  // Singleton pattern
  static final StageGenerator _instance = StageGenerator._internal();
  factory StageGenerator() => _instance;
  static StageGenerator get instance => _instance;
  StageGenerator._internal();

  /// Category priority for conflict resolution
  static const _categoryPriority = {
    BlockCategory.core: 100,
    BlockCategory.feature: 80,
    BlockCategory.presentation: 60,
    BlockCategory.bonus: 40,
  };

  /// Bus priority for merging
  static const _busPriority = {
    'music': 10,
    'sfx': 20,
    'wins': 30,
    'reels': 40,
    'vo': 50,
    'ui': 60,
    'ambience': 70,
  };

  /// Generate stages from all enabled blocks
  StageGenerationResult generate(List<FeatureBlockBase> blocks) {
    // Filter to enabled blocks only
    final enabledBlocks = blocks.where((b) => b.isEnabled).toList();

    if (enabledBlocks.isEmpty) {
      return StageGenerationResult(
        isValid: true,
        stages: [],
        stats: const StageGenerationStats(
          totalRaw: 0,
          totalFinal: 0,
          pooledCount: 0,
          loopingCount: 0,
          stagesPerBus: {},
          stagesPerCategory: {},
          contributingBlocks: 0,
        ),
      );
    }

    // Get dependency order
    final depResolver = resolver.DependencyResolver.instance;
    final depResult = depResolver.resolve(enabledBlocks);

    if (!depResult.isValid) {
      // Can't generate with invalid dependencies
      return StageGenerationResult(
        isValid: false,
        stages: [],
        warnings: [
          StageWarning(
            stageName: '*',
            blockId: '*',
            message: 'Cannot generate stages: dependency resolution failed',
          ),
        ],
        stats: const StageGenerationStats(
          totalRaw: 0,
          totalFinal: 0,
          pooledCount: 0,
          loopingCount: 0,
          stagesPerBus: {},
          stagesPerCategory: {},
          contributingBlocks: 0,
        ),
      );
    }

    // Sort blocks by dependency order
    final blockMap = {for (final b in enabledBlocks) b.id: b};
    final sortedBlocks = depResult.sortedBlockIds
        .where((id) => blockMap.containsKey(id))
        .map((id) => blockMap[id]!)
        .toList();

    // Collect raw stages from all blocks
    final rawStages = <String, List<_RawStageEntry>>{};
    var totalRaw = 0;

    for (final block in sortedBlocks) {
      final stages = block.generateStages();
      totalRaw += stages.length;

      for (final stage in stages) {
        final entry = _RawStageEntry(
          stage: stage,
          blockId: block.id,
          category: block.category,
          stagePriority: block.stagePriority,
        );

        if (!rawStages.containsKey(stage.name)) {
          rawStages[stage.name] = [];
        }
        rawStages[stage.name]!.add(entry);
      }
    }

    // Deduplicate and resolve conflicts
    final finalStages = <GeneratedStageEntry>[];
    final conflicts = <StageConflict>[];
    final warnings = <StageWarning>[];

    for (final entry in rawStages.entries) {
      final stageName = entry.key;
      final entries = entry.value;

      if (entries.length == 1) {
        // No conflict
        finalStages.add(GeneratedStageEntry(
          stage: entries.first.stage,
          sourceBlockId: entries.first.blockId,
          category: entries.first.category.name,
        ));
      } else {
        // Resolve conflict
        final resolution = _resolveConflict(stageName, entries);
        finalStages.add(resolution.entry);
        conflicts.add(resolution.conflict);

        // Warn about the merge
        if (entries.length > 2) {
          warnings.add(StageWarning(
            stageName: stageName,
            blockId: resolution.entry.sourceBlockId,
            message:
                'Stage merged from ${entries.length} blocks: ${entries.map((e) => e.blockId).join(", ")}',
          ));
        }
      }
    }

    // Sort final stages by priority (descending) then name
    finalStages.sort((a, b) {
      final priorityDiff = b.stage.priority - a.stage.priority;
      if (priorityDiff != 0) return priorityDiff;
      return a.name.compareTo(b.name);
    });

    // Calculate statistics
    final stagesPerBus = <String, int>{};
    final stagesPerCategory = <String, int>{};
    var pooledCount = 0;
    var loopingCount = 0;

    for (final stage in finalStages) {
      stagesPerBus[stage.stage.bus] = (stagesPerBus[stage.stage.bus] ?? 0) + 1;
      stagesPerCategory[stage.category] =
          (stagesPerCategory[stage.category] ?? 0) + 1;
      if (stage.stage.pooled) pooledCount++;
      if (stage.stage.looping) loopingCount++;
    }

    return StageGenerationResult(
      isValid: true,
      stages: finalStages,
      resolvedConflicts: conflicts,
      warnings: warnings,
      stats: StageGenerationStats(
        totalRaw: totalRaw,
        totalFinal: finalStages.length,
        pooledCount: pooledCount,
        loopingCount: loopingCount,
        stagesPerBus: stagesPerBus,
        stagesPerCategory: stagesPerCategory,
        contributingBlocks: sortedBlocks.length,
      ),
    );
  }

  /// Resolve a stage conflict
  _ConflictResolutionResult _resolveConflict(
    String stageName,
    List<_RawStageEntry> entries,
  ) {
    // Sort by category priority, then block stage priority
    entries.sort((a, b) {
      final catPriorityA = _categoryPriority[a.category] ?? 50;
      final catPriorityB = _categoryPriority[b.category] ?? 50;
      if (catPriorityA != catPriorityB) return catPriorityB - catPriorityA;
      return b.stagePriority - a.stagePriority;
    });

    final winner = entries.first;
    final resolution = entries.length == 2 &&
            entries[0].stagePriority == entries[1].stagePriority
        ? ConflictResolution.categoryPriority
        : ConflictResolution.higherPriority;

    // Merge pooled and looping flags (if ANY says pooled/looping, use it)
    final isPooled = entries.any((e) => e.stage.pooled);
    final isLooping = entries.any((e) => e.stage.looping);

    // Use highest priority
    final maxPriority = entries.map((e) => e.stage.priority).reduce((a, b) => a > b ? a : b);

    // Use highest priority bus
    final busByPriority = entries.map((e) => e.stage.bus).toList()
      ..sort((a, b) {
        final pa = _busPriority[a] ?? 100;
        final pb = _busPriority[b] ?? 100;
        return pa - pb;
      });
    final finalBus = busByPriority.first;

    // Create merged stage
    final mergedStage = GeneratedStage(
      name: stageName,
      description: winner.stage.description,
      bus: finalBus,
      priority: maxPriority,
      pooled: isPooled,
      looping: isLooping,
      sourceBlockId: winner.blockId,
    );

    return _ConflictResolutionResult(
      entry: GeneratedStageEntry.merged(
        stage: mergedStage,
        fromBlocks: entries.map((e) => e.blockId).toList(),
        category: winner.category.name,
      ),
      conflict: StageConflict(
        stageName: stageName,
        conflictingBlocks: entries.map((e) => e.blockId).toList(),
        resolution: resolution,
        finalPriority: maxPriority,
        finalBus: finalBus,
      ),
    );
  }

  /// Export stages to StageConfigurationService
  void exportToStageConfiguration(StageGenerationResult result) {
    if (!result.isValid) return;

    final service = StageConfigurationService.instance;

    // Register each stage
    for (final entry in result.stages) {
      final stage = entry.stage;

      // Convert bus string to SpatialBus enum
      final spatialBus = _stringToSpatialBus(stage.bus);

      // Create stage definition and register it
      service.registerCustomStage(StageDefinition(
        name: stage.name,
        category: _stringToStageCategory(entry.category),
        priority: stage.priority,
        bus: spatialBus,
        spatialIntent: _generateSpatialIntent(stage.name),
        isPooled: stage.pooled,
        isLooping: stage.looping,
        description: stage.description,
      ));
    }
  }

  /// Convert bus string to SpatialBus
  SpatialBus _stringToSpatialBus(String bus) {
    switch (bus.toLowerCase()) {
      case 'music':
        return SpatialBus.music;
      case 'sfx':
        return SpatialBus.sfx;
      case 'wins':
        return SpatialBus.sfx; // Wins go to SFX bus
      case 'reels':
        return SpatialBus.reels;
      case 'vo':
        return SpatialBus.vo;
      case 'ui':
        return SpatialBus.ui;
      case 'ambience':
        return SpatialBus.ambience;
      default:
        return SpatialBus.sfx;
    }
  }

  /// Convert category string to StageCategory
  StageCategory _stringToStageCategory(String category) {
    switch (category.toLowerCase()) {
      case 'core':
        return StageCategory.spin;
      case 'feature':
        return StageCategory.feature;
      case 'presentation':
        return StageCategory.win;
      case 'bonus':
        return StageCategory.feature;
      default:
        return StageCategory.custom;
    }
  }

  /// Generate spatial intent from stage name
  String _generateSpatialIntent(String stageName) {
    final name = stageName.toLowerCase();

    // Reel-related
    if (name.contains('reel_stop_0')) return 'reel_left';
    if (name.contains('reel_stop_1')) return 'reel_center_left';
    if (name.contains('reel_stop_2')) return 'reel_center';
    if (name.contains('reel_stop_3')) return 'reel_center_right';
    if (name.contains('reel_stop_4')) return 'reel_right';
    if (name.contains('reel')) return 'center';

    // Win-related
    if (name.contains('jackpot')) return 'center_focus';
    if (name.contains('big_win') || name.contains('mega_win')) return 'center_wide';
    if (name.contains('win')) return 'center';

    // Feature-related
    if (name.contains('fs_') || name.contains('freespin')) return 'center';
    if (name.contains('bonus')) return 'center';
    if (name.contains('hold')) return 'center';

    // Music
    if (name.contains('music')) return 'ambient_stereo';

    // UI
    if (name.contains('ui_')) return 'ui_center';

    // Default
    return 'center';
  }

  /// Get a preview of stages that would be generated
  Map<String, List<String>> previewStages(List<FeatureBlockBase> blocks) {
    final preview = <String, List<String>>{};

    for (final block in blocks.where((b) => b.isEnabled)) {
      final stages = block.generateStages();
      preview[block.id] = stages.map((s) => s.name).toList();
    }

    return preview;
  }

  /// Get stage count per block
  Map<String, int> getStageCountPerBlock(List<FeatureBlockBase> blocks) {
    final counts = <String, int>{};

    for (final block in blocks.where((b) => b.isEnabled)) {
      counts[block.id] = block.generateStages().length;
    }

    return counts;
  }

  /// Get all unique bus names used
  Set<String> getAllBusNames(StageGenerationResult result) {
    return result.stages.map((s) => s.stage.bus).toSet();
  }

  /// Filter stages by pattern
  List<GeneratedStageEntry> filterStages(
    StageGenerationResult result,
    String pattern,
  ) {
    final regex = RegExp(pattern, caseSensitive: false);
    return result.stages.where((s) => regex.hasMatch(s.name)).toList();
  }
}

/// Internal raw stage entry
class _RawStageEntry {
  final GeneratedStage stage;
  final String blockId;
  final BlockCategory category;
  final int stagePriority;

  const _RawStageEntry({
    required this.stage,
    required this.blockId,
    required this.category,
    required this.stagePriority,
  });
}

/// Internal conflict resolution result
class _ConflictResolutionResult {
  final GeneratedStageEntry entry;
  final StageConflict conflict;

  const _ConflictResolutionResult({
    required this.entry,
    required this.conflict,
  });
}

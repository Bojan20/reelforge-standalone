// ============================================================================
// FluxForge Studio — Feature Block Registry
// ============================================================================
// P13.0.6: Central registry for all feature blocks
// Manages block registration, retrieval, and lifecycle.
// ============================================================================

import '../../models/feature_builder/block_category.dart';
import '../../models/feature_builder/feature_block.dart';
import '../../models/feature_builder/block_dependency.dart';

/// Central registry for all feature blocks.
///
/// This singleton manages the registration and retrieval of feature blocks.
/// Blocks must be registered before they can be used by the Feature Builder.
///
/// Usage:
/// ```dart
/// // Register a block
/// FeatureBlockRegistry.instance.register(GameCoreBlock());
///
/// // Get a block by ID
/// final block = FeatureBlockRegistry.instance.get('game_core');
///
/// // Get all blocks in a category
/// final featureBlocks = FeatureBlockRegistry.instance.getByCategory(BlockCategory.feature);
/// ```
class FeatureBlockRegistry {
  FeatureBlockRegistry._();

  static final FeatureBlockRegistry _instance = FeatureBlockRegistry._();

  /// Singleton instance.
  static FeatureBlockRegistry get instance => _instance;

  /// Map of block ID to block instance.
  final Map<String, FeatureBlock> _blocks = {};

  /// List of block IDs in registration order (for consistent iteration).
  final List<String> _registrationOrder = [];

  /// Whether the registry has been initialized with built-in blocks.
  bool _initialized = false;

  // ============================================================================
  // Registration
  // ============================================================================

  /// Register a block.
  ///
  /// Throws [ArgumentError] if a block with the same ID is already registered.
  void register(FeatureBlock block) {
    if (_blocks.containsKey(block.id)) {
      throw ArgumentError('Block with ID "${block.id}" is already registered');
    }
    _blocks[block.id] = block;
    _registrationOrder.add(block.id);
  }

  /// Register multiple blocks at once.
  void registerAll(List<FeatureBlock> blocks) {
    for (final block in blocks) {
      register(block);
    }
  }

  /// Unregister a block by ID.
  ///
  /// Returns true if the block was unregistered, false if it wasn't found.
  bool unregister(String blockId) {
    if (_blocks.remove(blockId) != null) {
      _registrationOrder.remove(blockId);
      return true;
    }
    return false;
  }

  /// Clear all registered blocks.
  void clear() {
    _blocks.clear();
    _registrationOrder.clear();
    _initialized = false;
  }

  // ============================================================================
  // Retrieval
  // ============================================================================

  /// Get a block by ID.
  ///
  /// Returns null if the block is not found.
  FeatureBlock? get(String blockId) => _blocks[blockId];

  /// Get a block by ID, throwing if not found.
  FeatureBlock getRequired(String blockId) {
    final block = _blocks[blockId];
    if (block == null) {
      throw StateError('Block "$blockId" is not registered');
    }
    return block;
  }

  /// Check if a block is registered.
  bool contains(String blockId) => _blocks.containsKey(blockId);

  /// Get all registered blocks.
  List<FeatureBlock> get all =>
      _registrationOrder.map((id) => _blocks[id]!).toList();

  /// Get all block IDs.
  List<String> get allIds => List.unmodifiable(_registrationOrder);

  /// Get the number of registered blocks.
  int get count => _blocks.length;

  // ============================================================================
  // Category Filtering
  // ============================================================================

  /// Get all blocks in a category.
  List<FeatureBlock> getByCategory(BlockCategory category) =>
      all.where((b) => b.category == category).toList();

  /// Get blocks grouped by category.
  Map<BlockCategory, List<FeatureBlock>> get byCategory {
    final result = <BlockCategory, List<FeatureBlock>>{};
    for (final category in BlockCategory.values) {
      final blocks = getByCategory(category);
      if (blocks.isNotEmpty) {
        result[category] = blocks;
      }
    }
    return result;
  }

  /// Get all enabled blocks.
  List<FeatureBlock> get enabled => all.where((b) => b.isEnabled).toList();

  /// Get all disabled blocks.
  List<FeatureBlock> get disabled => all.where((b) => !b.isEnabled).toList();

  // ============================================================================
  // Dependency Queries
  // ============================================================================

  /// Get all dependencies for a block.
  List<BlockDependency> getDependenciesFor(String blockId) {
    final block = get(blockId);
    if (block == null) return [];
    return block.dependencies;
  }

  /// Get blocks that depend on a specific block.
  List<FeatureBlock> getDependentsOf(String blockId) => all
      .where((b) => b.dependencies.any((d) => d.targetBlockId == blockId))
      .toList();

  /// Get blocks that a specific block depends on.
  List<FeatureBlock> getDependenciesOf(String blockId) {
    final block = get(blockId);
    if (block == null) return [];
    return block.dependencies
        .map((d) => get(d.targetBlockId))
        .whereType<FeatureBlock>()
        .toList();
  }

  /// Get all dependencies of a specific type.
  List<BlockDependency> getDependenciesByType(DependencyType type) => all
      .expand((b) => b.dependencies)
      .where((d) => d.type == type)
      .toList();

  // ============================================================================
  // Stage Queries
  // ============================================================================

  /// Get all generated stages from enabled blocks.
  List<GeneratedStage> get allGeneratedStages {
    final stages = <GeneratedStage>[];
    for (final block in enabled) {
      stages.addAll(block.generateStages());
    }
    // Sort by block priority, then by stage name
    stages.sort((a, b) {
      final blockA = get(a.sourceBlockId);
      final blockB = get(b.sourceBlockId);
      final priorityCompare =
          (blockA?.stagePriority ?? 50).compareTo(blockB?.stagePriority ?? 50);
      if (priorityCompare != 0) return priorityCompare;
      return a.name.compareTo(b.name);
    });
    return stages;
  }

  /// Get all stage names from enabled blocks.
  List<String> get allStageNames =>
      allGeneratedStages.map((s) => s.name).toList();

  /// Get stages grouped by category.
  Map<String, List<GeneratedStage>> get stagesByCategory {
    final result = <String, List<GeneratedStage>>{};
    for (final stage in allGeneratedStages) {
      final category = stage.category ?? 'Other';
      result.putIfAbsent(category, () => []).add(stage);
    }
    return result;
  }

  /// Get pooled stage names (for voice pooling).
  Set<String> get pooledStageNames =>
      enabled.expand((b) => b.pooledStages).toSet();

  // ============================================================================
  // State Management
  // ============================================================================

  /// Enable a block by ID.
  void enableBlock(String blockId) {
    final block = get(blockId);
    if (block != null) {
      block.isEnabled = true;
    }
  }

  /// Disable a block by ID.
  void disableBlock(String blockId) {
    final block = get(blockId);
    if (block != null && block.canBeDisabled) {
      block.isEnabled = false;
    }
  }

  /// Toggle a block's enabled state.
  bool toggleBlock(String blockId) {
    final block = get(blockId);
    if (block == null) return false;
    if (!block.isEnabled) {
      block.isEnabled = true;
      return true;
    } else if (block.canBeDisabled) {
      block.isEnabled = false;
      return false;
    }
    return true;
  }

  /// Reset all blocks to disabled state (except core blocks).
  void resetAll() {
    for (final block in all) {
      if (block.canBeDisabled) {
        block.isEnabled = false;
      }
      block.resetOptions();
    }
  }

  // ============================================================================
  // Serialization
  // ============================================================================

  /// Export all block states to JSON.
  Map<String, dynamic> exportState() {
    final result = <String, dynamic>{};
    for (final block in all) {
      result[block.id] = block.toJson();
    }
    return result;
  }

  /// Import block states from JSON.
  void importState(Map<String, dynamic> state) {
    for (final entry in state.entries) {
      final block = get(entry.key);
      if (block != null && entry.value is Map<String, dynamic>) {
        block.fromJson(entry.value as Map<String, dynamic>);
      }
    }
  }

  // ============================================================================
  // Initialization
  // ============================================================================

  /// Whether the registry has been initialized.
  bool get isInitialized => _initialized;

  /// Mark the registry as initialized.
  void markInitialized() {
    _initialized = true;
  }

  /// Initialize the registry with built-in blocks.
  ///
  /// This should be called once at app startup.
  /// Pass a list of block factories to create the blocks.
  void initialize(List<FeatureBlock Function()> blockFactories) {
    if (_initialized) return;

    for (final factory in blockFactories) {
      register(factory());
    }

    _initialized = true;
  }
}

// ============================================================================
// Registry Query Helpers
// ============================================================================

/// Extension methods for querying the registry.
extension FeatureBlockRegistryQueries on FeatureBlockRegistry {
  /// Find blocks matching a predicate.
  List<FeatureBlock> where(bool Function(FeatureBlock) predicate) =>
      all.where(predicate).toList();

  /// Check if any block matches a predicate.
  bool any(bool Function(FeatureBlock) predicate) => all.any(predicate);

  /// Check if all blocks match a predicate.
  bool every(bool Function(FeatureBlock) predicate) => all.every(predicate);

  /// Get the first block matching a predicate, or null.
  FeatureBlock? firstWhereOrNull(bool Function(FeatureBlock) predicate) {
    for (final block in all) {
      if (predicate(block)) return block;
    }
    return null;
  }

  /// Count blocks matching a predicate.
  int countWhere(bool Function(FeatureBlock) predicate) =>
      all.where(predicate).length;

  /// Get blocks that have been modified from defaults.
  List<FeatureBlock> get modified => where((b) => b.isModified);

  /// Get core blocks.
  List<FeatureBlock> get coreBlocks => getByCategory(BlockCategory.core);

  /// Get feature blocks.
  List<FeatureBlock> get featureBlocks => getByCategory(BlockCategory.feature);

  /// Get presentation blocks.
  List<FeatureBlock> get presentationBlocks =>
      getByCategory(BlockCategory.presentation);

  /// Get bonus blocks.
  List<FeatureBlock> get bonusBlocks => getByCategory(BlockCategory.bonus);
}

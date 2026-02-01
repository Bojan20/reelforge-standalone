// ============================================================================
// FluxForge Studio — Feature Builder Provider
// ============================================================================
// P13.0.10: Basic provider for Feature Builder state management
// Manages block enable/disable, options, presets, and configuration generation.
// ============================================================================

import 'package:flutter/foundation.dart';

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';
import '../models/feature_builder/feature_preset.dart';
import '../models/feature_block_models.dart';
import '../services/feature_builder/feature_block_registry.dart';
import '../services/dependency_resolver.dart' as resolver;
import '../services/stage_generator.dart';
// Core blocks
import '../blocks/game_core_block.dart';
import '../blocks/grid_block.dart';
import '../blocks/symbol_set_block.dart';
// Feature blocks (Phase 2)
import '../blocks/free_spins_block.dart';
import '../blocks/respin_block.dart';
import '../blocks/hold_and_win_block.dart';
import '../blocks/cascades_block.dart';
import '../blocks/collector_block.dart';
// Presentation blocks (Phase 2)
import '../blocks/win_presentation_block.dart';
import '../blocks/music_states_block.dart';

/// Provider for Feature Builder state management.
///
/// This provider manages:
/// - Block enable/disable state
/// - Block option values
/// - Preset loading/saving
/// - Configuration generation
/// - Dependency validation
class FeatureBuilderProvider extends ChangeNotifier {
  /// Singleton instance for global access.
  static FeatureBuilderProvider? _instance;

  /// Get the singleton instance.
  static FeatureBuilderProvider get instance {
    _instance ??= FeatureBuilderProvider._();
    return _instance!;
  }

  /// Private constructor for singleton.
  FeatureBuilderProvider._() {
    _initialize();
  }

  /// Public constructor for testing or manual instantiation.
  FeatureBuilderProvider() {
    _initialize();
  }

  /// The block registry.
  final FeatureBlockRegistry _registry = FeatureBlockRegistry.instance;

  /// Currently loaded preset (if any).
  FeaturePreset? _currentPreset;

  /// Whether the configuration has been modified since last preset load.
  bool _isDirty = false;

  /// Last validation result.
  DependencyResolutionResult? _lastValidation;

  /// Undo stack for option changes.
  final List<BlockStateSnapshot> _undoStack = [];

  /// Redo stack for undone changes.
  final List<BlockStateSnapshot> _redoStack = [];

  /// Maximum undo history size.
  static const int _maxUndoHistory = 50;

  // ============================================================================
  // Initialization
  // ============================================================================

  /// The dependency resolver.
  final resolver.DependencyResolver _dependencyResolver =
      resolver.DependencyResolver.instance;

  /// The stage generator.
  final StageGenerator _stageGenerator = StageGenerator.instance;

  /// Cached advanced dependency resolution result.
  resolver.DependencyResolutionResult? _cachedAdvancedDependencyResult;

  /// Cached stage generation result.
  StageGenerationResult? _cachedStageResult;

  /// Whether stages need regeneration.
  bool _stagesNeedRegeneration = true;

  /// Initialize the provider with built-in blocks.
  void _initialize() {
    if (_registry.isInitialized) return;

    // Register core blocks
    _registry.registerAll([
      GameCoreBlock(),
      GridBlock(),
      SymbolSetBlock(),
    ]);

    // Register feature blocks (Phase 2)
    _registry.registerAll([
      FreeSpinsBlock(),
      RespinBlock(),
      HoldAndWinBlock(),
      CascadesBlock(),
      CollectorBlock(),
    ]);

    // Register presentation blocks (Phase 2)
    _registry.registerAll([
      WinPresentationBlock(),
      MusicStatesBlock(),
    ]);

    _registry.markInitialized();
  }

  /// Ensure initialization is complete.
  void ensureInitialized() => _initialize();

  // ============================================================================
  // Block Access
  // ============================================================================

  /// Get all registered blocks.
  List<FeatureBlock> get allBlocks => _registry.all;

  /// Get all block IDs.
  List<String> get allBlockIds => _registry.allIds;

  /// Get a block by ID.
  FeatureBlock? getBlock(String blockId) => _registry.get(blockId);

  /// Get blocks by category.
  List<FeatureBlock> getBlocksByCategory(BlockCategory category) =>
      _registry.getByCategory(category);

  /// Get blocks grouped by category.
  Map<BlockCategory, List<FeatureBlock>> get blocksByCategory =>
      _registry.byCategory;

  /// Get all enabled blocks.
  List<FeatureBlock> get enabledBlocks => _registry.enabled;

  /// Get enabled block IDs.
  List<String> get enabledBlockIds =>
      enabledBlocks.map((b) => b.id).toList();

  /// Get the number of enabled blocks.
  int get enabledBlockCount => enabledBlocks.length;

  // ============================================================================
  // Block State Management
  // ============================================================================

  /// Enable a block.
  ///
  /// Returns true if the block was enabled, false if it was already enabled
  /// or if it cannot be found.
  bool enableBlock(String blockId) {
    final block = _registry.get(blockId);
    if (block == null || block.isEnabled) return false;

    _saveStateForUndo(block);
    block.isEnabled = true;
    _markDirty();
    notifyListeners();
    return true;
  }

  /// Disable a block.
  ///
  /// Returns true if the block was disabled, false if it was already disabled,
  /// cannot be disabled, or cannot be found.
  bool disableBlock(String blockId) {
    final block = _registry.get(blockId);
    if (block == null || !block.isEnabled || !block.canBeDisabled) return false;

    _saveStateForUndo(block);
    block.isEnabled = false;
    _markDirty();
    notifyListeners();
    return true;
  }

  /// Toggle a block's enabled state.
  ///
  /// Returns the new enabled state, or null if the block cannot be found.
  bool? toggleBlock(String blockId) {
    final block = _registry.get(blockId);
    if (block == null) return null;

    _saveStateForUndo(block);
    if (block.isEnabled && block.canBeDisabled) {
      block.isEnabled = false;
    } else if (!block.isEnabled) {
      block.isEnabled = true;
    }
    _markDirty();
    notifyListeners();
    return block.isEnabled;
  }

  /// Set a block option value.
  void setBlockOption(String blockId, String optionId, dynamic value) {
    final block = _registry.get(blockId);
    if (block == null) return;

    _saveStateForUndo(block);
    block.setOptionValue(optionId, value);
    _markDirty();
    notifyListeners();
  }

  /// Get a block option value.
  T? getBlockOption<T>(String blockId, String optionId) {
    final block = _registry.get(blockId);
    if (block == null) return null;
    return block.getOptionValue<T>(optionId);
  }

  /// Reset a block to default options.
  void resetBlock(String blockId) {
    final block = _registry.get(blockId);
    if (block == null) return;

    _saveStateForUndo(block);
    block.resetOptions();
    _markDirty();
    notifyListeners();
  }

  /// Reset all blocks to defaults.
  void resetAll() {
    for (final block in allBlocks) {
      _saveStateForUndo(block);
    }
    _registry.resetAll();
    _currentPreset = null;
    _isDirty = false;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  // ============================================================================
  // Preset Management
  // ============================================================================

  /// Currently loaded preset.
  FeaturePreset? get currentPreset => _currentPreset;

  /// Whether the configuration has unsaved changes.
  bool get isDirty => _isDirty;

  /// Load a preset.
  void loadPreset(FeaturePreset preset) {
    // Reset all blocks first
    _registry.resetAll();

    // Apply preset block states
    for (final entry in preset.blocks.entries) {
      final block = _registry.get(entry.key);
      if (block == null) continue;

      block.isEnabled = entry.value.isEnabled;
      block.importOptions(entry.value.options);
    }

    _currentPreset = preset.recordUsage();
    _isDirty = false;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// Create a preset from current configuration.
  FeaturePreset createPreset({
    required String name,
    String? description,
    required PresetCategory category,
    List<String> tags = const [],
  }) {
    final blocks = <String, BlockPresetData>{};

    for (final block in allBlocks) {
      blocks[block.id] = BlockPresetData(
        isEnabled: block.isEnabled,
        options: block.exportOptions(),
      );
    }

    return FeaturePreset(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      category: category,
      tags: tags,
      blocks: blocks,
    );
  }

  /// Check if current config matches a preset.
  bool matchesPreset(FeaturePreset preset) {
    for (final entry in preset.blocks.entries) {
      final block = _registry.get(entry.key);
      if (block == null) continue;

      if (block.isEnabled != entry.value.isEnabled) return false;

      final currentOptions = block.exportOptions();
      final presetOptions = entry.value.options;

      for (final optKey in presetOptions.keys) {
        if (currentOptions[optKey] != presetOptions[optKey]) return false;
      }
    }
    return true;
  }

  // ============================================================================
  // Stage Generation
  // ============================================================================

  /// Get all generated stages from enabled blocks.
  List<GeneratedStage> get generatedStages => _registry.allGeneratedStages;

  /// Get all stage names.
  List<String> get stageNames => _registry.allStageNames;

  /// Get pooled stage names.
  Set<String> get pooledStageNames => _registry.pooledStageNames;

  /// Get stages grouped by category.
  Map<String, List<GeneratedStage>> get stagesByCategory =>
      _registry.stagesByCategory;

  /// Get total stage count.
  int get totalStageCount => generatedStages.length;

  /// Generate stages using StageGenerator with deduplication.
  StageGenerationResult generateStages() {
    if (!_stagesNeedRegeneration && _cachedStageResult != null) {
      return _cachedStageResult!;
    }

    // Convert to FeatureBlockBase list
    final blocks = enabledBlocks
        .whereType<FeatureBlockBase>()
        .toList();

    _cachedStageResult = _stageGenerator.generate(blocks);
    _stagesNeedRegeneration = false;
    return _cachedStageResult!;
  }

  /// Get stage generation statistics.
  StageGenerationStats? get stageStats => _cachedStageResult?.stats;

  /// Export generated stages to StageConfigurationService.
  void exportStagesToConfiguration() {
    final result = generateStages();
    if (result.isValid) {
      _stageGenerator.exportToStageConfiguration(result);
    }
  }

  /// Preview stages without affecting cache.
  Map<String, List<String>> previewBlockStages() {
    final blocks = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _stageGenerator.previewStages(blocks);
  }

  /// Get stage count per block.
  Map<String, int> get stageCountPerBlock {
    final blocks = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _stageGenerator.getStageCountPerBlock(blocks);
  }

  /// Force stage regeneration on next access.
  void invalidateStages() {
    _stagesNeedRegeneration = true;
    _cachedStageResult = null;
  }

  // ============================================================================
  // Validation
  // ============================================================================

  /// Validate the current configuration.
  DependencyResolutionResult validate() {
    final nodes = <DependencyGraphNode>[];
    final edges = <DependencyGraphEdge>[];
    final errors = <DependencyError>[];
    final warnings = <DependencyWarning>[];
    final fixes = <AutoResolveAction>[];

    // Build nodes
    for (final block in allBlocks) {
      nodes.add(DependencyGraphNode(
        blockId: block.id,
        displayName: block.name,
        isEnabled: block.isEnabled,
      ));
    }

    // Check dependencies
    for (final block in enabledBlocks) {
      for (final dep in block.dependencies) {
        final targetBlock = _registry.get(dep.targetBlockId);
        if (targetBlock == null) continue;

        bool isSatisfied = true;
        String? errorMsg;

        switch (dep.type) {
          case DependencyType.requires:
            if (!targetBlock.isEnabled) {
              isSatisfied = false;
              errorMsg = '${block.name} requires ${targetBlock.name}';
              errors.add(DependencyError(
                dependency: dep,
                message: errorMsg,
                suggestedFix: dep.autoResolveAction ??
                    AutoResolveAction(
                      type: AutoResolveType.enableBlock,
                      targetBlockId: dep.targetBlockId,
                      description: 'Enable ${targetBlock.name}',
                    ),
              ));
              if (dep.autoResolvable) {
                fixes.add(AutoResolveAction(
                  type: AutoResolveType.enableBlock,
                  targetBlockId: dep.targetBlockId,
                  description: 'Enable ${targetBlock.name}',
                ));
              }
            }
            break;

          case DependencyType.conflicts:
            if (targetBlock.isEnabled) {
              isSatisfied = false;
              errorMsg = '${block.name} conflicts with ${targetBlock.name}';
              errors.add(DependencyError(
                dependency: dep,
                message: errorMsg,
              ));
            }
            break;

          case DependencyType.modifies:
            if (targetBlock.isEnabled) {
              warnings.add(DependencyWarning(
                dependency: dep,
                message: '${block.name} modifies ${targetBlock.name} behavior',
              ));
            }
            break;

          case DependencyType.enables:
            // Informational only
            break;
        }

        edges.add(DependencyGraphEdge(
          sourceId: block.id,
          targetId: dep.targetBlockId,
          type: dep.type,
          isSatisfied: isSatisfied,
          errorMessage: errorMsg,
        ));
      }
    }

    final graph = DependencyGraph(nodes: nodes, edges: edges);
    _lastValidation = DependencyResolutionResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      suggestedFixes: fixes,
      graph: graph,
    );

    return _lastValidation!;
  }

  /// Get last validation result.
  DependencyResolutionResult? get lastValidation => _lastValidation;

  /// Whether current configuration is valid.
  bool get isValid => validate().isValid;

  /// Apply suggested fixes.
  void applyFixes(List<AutoResolveAction> fixes) {
    for (final fix in fixes) {
      switch (fix.type) {
        case AutoResolveType.enableBlock:
          enableBlock(fix.targetBlockId);
          break;
        case AutoResolveType.disableBlock:
          disableBlock(fix.targetBlockId);
          break;
        case AutoResolveType.setOption:
          if (fix.optionId != null) {
            setBlockOption(fix.targetBlockId, fix.optionId!, fix.value);
          }
          break;
      }
    }
  }

  // ============================================================================
  // Advanced Dependency Resolution (using DependencyResolver service)
  // ============================================================================

  /// Perform advanced dependency resolution with cycle detection.
  resolver.DependencyResolutionResult resolveAdvanced() {
    final blocks = enabledBlocks.whereType<FeatureBlockBase>().toList();
    _cachedAdvancedDependencyResult = _dependencyResolver.resolve(blocks);
    return _cachedAdvancedDependencyResult!;
  }

  /// Get cached advanced resolution result.
  resolver.DependencyResolutionResult? get advancedResolution =>
      _cachedAdvancedDependencyResult;

  /// Get dependency graph data for visualization.
  resolver.DependencyGraphData getDependencyGraphData() {
    final blocks = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _dependencyResolver.getVisualizationData(blocks);
  }

  /// Get blocks in initialization order.
  List<String> get initializationOrder {
    final blocks = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _dependencyResolver.getInitializationOrder(blocks);
  }

  /// Preview what would happen if a block is added.
  resolver.DependencyResolutionResult previewAddBlock(FeatureBlockBase block) {
    final existing = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _dependencyResolver.previewAddBlock(existing, block);
  }

  /// Preview what would happen if a block is removed.
  resolver.DependencyResolutionResult previewRemoveBlock(String blockId) {
    final existing = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _dependencyResolver.previewRemoveBlock(existing, blockId);
  }

  /// Get all blocks that depend on a given block.
  Set<String> getDependentsOf(String blockId) {
    final blocks = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _dependencyResolver.getDependents(blocks, blockId);
  }

  /// Get all blocks that a given block depends on.
  Set<String> getDependenciesOf(String blockId) {
    final blocks = enabledBlocks.whereType<FeatureBlockBase>().toList();
    return _dependencyResolver.getDependencies(blocks, blockId);
  }

  // ============================================================================
  // Undo/Redo
  // ============================================================================

  /// Whether undo is available.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether redo is available.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Undo the last change.
  void undo() {
    if (!canUndo) return;

    final snapshot = _undoStack.removeLast();
    final block = _registry.get(snapshot.blockId);
    if (block == null) return;

    // Save current state for redo
    _redoStack.add(BlockStateSnapshot.fromBlock(block));

    // Restore snapshot
    block.isEnabled = snapshot.isEnabled;
    block.importOptions(snapshot.options);
    notifyListeners();
  }

  /// Redo the last undone change.
  void redo() {
    if (!canRedo) return;

    final snapshot = _redoStack.removeLast();
    final block = _registry.get(snapshot.blockId);
    if (block == null) return;

    // Save current state for undo
    _undoStack.add(BlockStateSnapshot.fromBlock(block));

    // Apply redo state
    block.isEnabled = snapshot.isEnabled;
    block.importOptions(snapshot.options);
    notifyListeners();
  }

  /// Save current block state for undo.
  void _saveStateForUndo(FeatureBlock block) {
    _undoStack.add(BlockStateSnapshot.fromBlock(block));
    if (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear(); // Clear redo stack on new changes
  }

  /// Mark configuration as dirty.
  void _markDirty() {
    _isDirty = true;
    _stagesNeedRegeneration = true;
  }

  // ============================================================================
  // Serialization
  // ============================================================================

  /// Export current configuration to JSON.
  Map<String, dynamic> exportConfiguration() {
    return {
      'version': '1.0.0',
      'timestamp': DateTime.now().toIso8601String(),
      'blocks': _registry.exportState(),
      'enabledBlocks': enabledBlockIds,
      'stageCount': totalStageCount,
    };
  }

  /// Import configuration from JSON.
  void importConfiguration(Map<String, dynamic> json) {
    if (json['blocks'] is Map<String, dynamic>) {
      _registry.importState(json['blocks'] as Map<String, dynamic>);
    }
    _isDirty = false;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  // ============================================================================
  // Quick Block Access (Convenience)
  // ============================================================================

  /// Get Game Core block.
  GameCoreBlock? get gameCoreBlock => _registry.get('game_core') as GameCoreBlock?;

  /// Get Grid block.
  GridBlock? get gridBlock => _registry.get('grid') as GridBlock?;

  /// Get Symbol Set block.
  SymbolSetBlock? get symbolSetBlock =>
      _registry.get('symbol_set') as SymbolSetBlock?;

  /// Get Free Spins block.
  FreeSpinsBlock? get freeSpinsBlock =>
      _registry.get('free_spins') as FreeSpinsBlock?;

  /// Get Respin block.
  RespinBlock? get respinBlock => _registry.get('respin') as RespinBlock?;

  /// Get Hold and Win block.
  HoldAndWinBlock? get holdAndWinBlock =>
      _registry.get('hold_and_win') as HoldAndWinBlock?;

  /// Get Cascades block.
  CascadesBlock? get cascadesBlock => _registry.get('cascades') as CascadesBlock?;

  /// Get Collector block.
  CollectorBlock? get collectorBlock =>
      _registry.get('collector') as CollectorBlock?;

  /// Get Win Presentation block.
  WinPresentationBlock? get winPresentationBlock =>
      _registry.get('win_presentation') as WinPresentationBlock?;

  /// Get Music States block.
  MusicStatesBlock? get musicStatesBlock =>
      _registry.get('music_states') as MusicStatesBlock?;

  // ============================================================================
  // Dispose
  // ============================================================================

  @override
  void dispose() {
    _undoStack.clear();
    _redoStack.clear();
    super.dispose();
  }
}

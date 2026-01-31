/// SlotLab Project Provider
///
/// V6 Layout state management for:
/// - Symbol definitions and audio assignments
/// - Context definitions and music layer assignments
/// - Project persistence (save/load)
/// - GDD import integration

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/slot_lab_models.dart';
import '../models/win_tier_config.dart';
import '../providers/ale_provider.dart';
import '../providers/git_provider.dart';
import '../services/gdd_import_service.dart';
import '../services/stage_configuration_service.dart';
import '../src/rust/native_ffi.dart';

/// Provider for SlotLab V6 project state
class SlotLabProjectProvider extends ChangeNotifier {
  /// Constructor — initializes P5 win tier stages
  SlotLabProjectProvider() {
    // Register default win tier stages on construction
    _syncWinTierStages();
  }

  // Project metadata
  String _projectName = 'Untitled Project';
  bool _isDirty = false;
  String? _projectPath;

  // Symbols
  List<SymbolDefinition> _symbols = List.from(defaultSymbols);
  List<SymbolAudioAssignment> _symbolAudio = [];

  // Contexts (game chapters)
  List<ContextDefinition> _contexts = [
    ContextDefinition.base(),
    ContextDefinition.freeSpins(),
    ContextDefinition.holdWin(),
  ];
  List<MusicLayerAssignment> _musicLayers = [];

  // ==========================================================================
  // ULTIMATE AUDIO PANEL STATE (V7)
  // ==========================================================================

  /// Audio assignments: stage → audioPath
  /// Used by UltimateAudioPanel for drag-drop audio assignments
  Map<String, String> _audioAssignments = {};

  /// Expanded sections in UltimateAudioPanel
  Set<String> _expandedSections = {'spins_reels', 'symbols', 'wins'};

  /// Expanded groups within sections
  Set<String> _expandedGroups = {
    'spins_reels_spin_controls',
    'spins_reels_reel_stops',
    'symbols_land',
    'symbols_win',
    'wins_tiers',
    'wins_lines',
  };

  /// Last active tab in lower zone (optional)
  String? _lastActiveTab;

  // Optional ALE integration
  AleProvider? _aleProvider;

  // ==========================================================================
  // UI STATE PERSISTENCE (SL-INT-P1.2, SL-INT-P1.4)
  // ==========================================================================

  /// Selected event ID (synced across panels)
  String? _selectedEventId;

  /// Lower Zone height
  double? _lowerZoneHeight;

  /// Audio browser current directory
  String? _audioBrowserDirectory;

  // ==========================================================================
  // GDD IMPORT STATE (V8)
  // ==========================================================================

  /// Imported Game Design Document (if any)
  GameDesignDocument? _importedGdd;

  /// Grid configuration from GDD
  GddGridConfig? _gridConfig;

  // ==========================================================================
  // WIN TIER CONFIGURATION (P5)
  // ==========================================================================

  /// Complete win tier configuration (regular + big wins)
  SlotWinConfiguration _winConfiguration = SlotWinConfiguration.defaultConfig();

  /// Flag to track if win config was imported from GDD
  bool _winConfigFromGdd = false;

  // ==========================================================================
  // GETTERS
  // ==========================================================================

  String get projectName => _projectName;
  bool get isDirty => _isDirty;
  String? get projectPath => _projectPath;
  List<SymbolDefinition> get symbols => _symbols;
  List<ContextDefinition> get contexts => _contexts;
  List<SymbolAudioAssignment> get symbolAudio => _symbolAudio;
  List<MusicLayerAssignment> get musicLayers => _musicLayers;

  // UltimateAudioPanel state getters
  Map<String, String> get audioAssignments => Map.unmodifiable(_audioAssignments);
  Set<String> get expandedSections => Set.unmodifiable(_expandedSections);
  Set<String> get expandedGroups => Set.unmodifiable(_expandedGroups);
  String? get lastActiveTab => _lastActiveTab;

  // GDD state getters
  GameDesignDocument? get importedGdd => _importedGdd;
  GddGridConfig? get gridConfig => _gridConfig;
  bool get hasImportedGdd => _importedGdd != null;

  // Win Tier Configuration getters (P5)
  SlotWinConfiguration get winConfiguration => _winConfiguration;
  RegularWinTierConfig get regularWinConfig => _winConfiguration.regularWins;
  BigWinConfig get bigWinConfig => _winConfiguration.bigWins;
  bool get winConfigFromGdd => _winConfigFromGdd;

  /// Get all win tier stage names (for UltimateAudioPanel)
  List<String> get allWinTierStages => _winConfiguration.allStageNames;

  /// Get regular win tier stages only
  List<String> get regularWinStages =>
      _winConfiguration.regularWins.tiers.map((t) => t.stageName).toList();

  /// Get big win tier stages only
  List<String> get bigWinStages => [
    'BIG_WIN_INTRO',
    ..._winConfiguration.bigWins.tiers.map((t) => t.stageName),
    'BIG_WIN_END',
    'BIG_WIN_FADE_OUT',
  ];

  // UI state getters (SL-INT-P1.2, SL-INT-P1.4)
  String? get selectedEventId => _selectedEventId;
  double? get lowerZoneHeight => _lowerZoneHeight;
  String? get audioBrowserDirectory => _audioBrowserDirectory;

  /// Set selected event ID and notify listeners (SL-INT-P1.2)
  void setSelectedEventId(String? id) {
    if (_selectedEventId != id) {
      _selectedEventId = id;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Set lower zone height and notify listeners (SL-INT-P1.4)
  void setLowerZoneHeight(double? height) {
    if (_lowerZoneHeight != height) {
      _lowerZoneHeight = height;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Set audio browser directory and notify listeners (SL-INT-P1.4)
  void setAudioBrowserDirectory(String? dir) {
    if (_audioBrowserDirectory != dir) {
      _audioBrowserDirectory = dir;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Get complete project for serialization
  SlotLabProject get project => SlotLabProject(
        name: _projectName,
        symbols: _symbols,
        contexts: _contexts,
        symbolAudio: _symbolAudio,
        musicLayers: _musicLayers,
        // V7: Include audio panel state
        audioAssignments: _audioAssignments,
        expandedSections: _expandedSections,
        expandedGroups: _expandedGroups,
        lastActiveTab: _lastActiveTab,
        // V8: Include GDD data
        gridConfig: _gridConfig,
        importedGdd: _importedGdd,
        // V9: Include UI state (SL-INT-P1.2, P1.4)
        selectedEventId: _selectedEventId,
        lowerZoneHeight: _lowerZoneHeight,
        audioBrowserDirectory: _audioBrowserDirectory,
      );

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================

  /// Connect ALE provider for music layer sync
  void connectAle(AleProvider aleProvider) {
    _aleProvider = aleProvider;
  }

  /// Create new project with default content
  void newProject(String name) {
    _projectName = name;
    _projectPath = null;
    _symbols = List.from(defaultSymbols);
    _contexts = [
      ContextDefinition.base(),
      ContextDefinition.freeSpins(),
      ContextDefinition.holdWin(),
    ];
    _symbolAudio = [];
    _musicLayers = [];
    // Reset audio panel state
    _audioAssignments = {};
    _expandedSections = {'spins_reels', 'symbols', 'wins'};
    _expandedGroups = {
      'spins_reels_spin_controls',
      'spins_reels_reel_stops',
      'symbols_land',
      'symbols_win',
      'wins_tiers',
      'wins_lines',
    };
    _lastActiveTab = null;
    // V8: Reset GDD data
    _importedGdd = null;
    _gridConfig = null;
    _isDirty = false;
    _syncSymbolStages(); // Sync stages for default symbols
    notifyListeners();
  }

  // ==========================================================================
  // ULTIMATE AUDIO PANEL STATE MANAGEMENT
  // ==========================================================================

  /// Set audio assignment for a stage
  void setAudioAssignment(String stage, String audioPath) {
    _audioAssignments[stage] = audioPath;
    _markDirty();
  }

  /// Remove audio assignment for a stage
  void removeAudioAssignment(String stage) {
    _audioAssignments.remove(stage);
    _markDirty();
  }

  /// Clear all audio assignments
  void clearAllAudioAssignments() {
    _audioAssignments.clear();
    _markDirty();
  }

  /// Get audio path for a stage (null if not assigned)
  String? getAudioAssignment(String stage) => _audioAssignments[stage];

  /// Check if stage has audio assigned
  bool hasAudioAssignment(String stage) => _audioAssignments.containsKey(stage);

  /// Set expanded state for a section
  void setSectionExpanded(String sectionId, bool expanded) {
    if (expanded) {
      _expandedSections.add(sectionId);
    } else {
      _expandedSections.remove(sectionId);
    }
    notifyListeners();
  }

  /// Toggle section expanded state
  void toggleSection(String sectionId) {
    if (_expandedSections.contains(sectionId)) {
      _expandedSections.remove(sectionId);
    } else {
      _expandedSections.add(sectionId);
    }
    notifyListeners();
  }

  /// Check if section is expanded
  bool isSectionExpanded(String sectionId) => _expandedSections.contains(sectionId);

  /// Set expanded state for a group
  void setGroupExpanded(String groupId, bool expanded) {
    if (expanded) {
      _expandedGroups.add(groupId);
    } else {
      _expandedGroups.remove(groupId);
    }
    notifyListeners();
  }

  /// Toggle group expanded state
  void toggleGroup(String groupId) {
    if (_expandedGroups.contains(groupId)) {
      _expandedGroups.remove(groupId);
    } else {
      _expandedGroups.add(groupId);
    }
    notifyListeners();
  }

  /// Check if group is expanded
  bool isGroupExpanded(String groupId) => _expandedGroups.contains(groupId);

  /// Set last active tab
  void setLastActiveTab(String? tabId) {
    _lastActiveTab = tabId;
    notifyListeners();
  }

  /// Bulk update expanded sections (for restoring state)
  void setExpandedSections(Set<String> sections) {
    _expandedSections = Set.from(sections);
    notifyListeners();
  }

  /// Bulk update expanded groups (for restoring state)
  void setExpandedGroups(Set<String> groups) {
    _expandedGroups = Set.from(groups);
    notifyListeners();
  }

  /// Bulk update audio assignments (for restoring state)
  void setAudioAssignments(Map<String, String> assignments) {
    _audioAssignments = Map.from(assignments);
    _markDirty();
  }

  // ==========================================================================
  // GDD IMPORT MANAGEMENT (V8)
  // ==========================================================================

  /// Import GDD and store it in the project
  /// This method stores the full GDD for later reference and updates the grid config.
  void importGdd(GameDesignDocument gdd, {List<SymbolDefinition>? generatedSymbols}) {
    _importedGdd = gdd;
    _gridConfig = gdd.grid;
    _projectName = gdd.name;

    // Optionally replace symbols with generated ones from GDD
    if (generatedSymbols != null && generatedSymbols.isNotEmpty) {
      _symbols = List.from(generatedSymbols);
      _symbolAudio = []; // Clear audio assignments when replacing symbols
      _syncSymbolStages();
    }

    // P5: Convert GDD win tiers to SlotWinConfiguration
    if (gdd.math.winTiers.isNotEmpty) {
      final winConfig = convertGddWinTiersToP5(gdd.math);
      setWinConfigurationFromGdd(winConfig);
      debugPrint('[SlotLabProject]   Win tiers: ${gdd.math.winTiers.length} (converted to P5)');
      debugPrint('[SlotLabProject]     Regular tiers: ${winConfig.regularWins.tiers.length}');
      debugPrint('[SlotLabProject]     Big win threshold: ${winConfig.bigWins.threshold}x');
    }

    debugPrint('[SlotLabProject] Imported GDD: ${gdd.name}');
    debugPrint('[SlotLabProject]   Grid: ${gdd.grid.columns}x${gdd.grid.rows} (${gdd.grid.mechanic})');
    debugPrint('[SlotLabProject]   Symbols: ${gdd.symbols.length}');
    debugPrint('[SlotLabProject]   Features: ${gdd.features.length}');

    _markDirty();
  }

  /// Update grid configuration (can be called independently of full GDD import)
  void setGridConfig(GddGridConfig config) {
    _gridConfig = config;
    _markDirty();
  }

  /// Clear imported GDD data
  void clearGdd() {
    _importedGdd = null;
    _gridConfig = null;
    _markDirty();
  }

  /// Get GDD symbols (if GDD is imported)
  List<GddSymbol> get gddSymbols => _importedGdd?.symbols ?? [];

  /// Get GDD features (if GDD is imported)
  List<GddFeature> get gddFeatures => _importedGdd?.features ?? [];

  /// Get GDD math model (if GDD is imported)
  GddMathModel? get gddMath => _importedGdd?.math;

  // ==========================================================================
  // SYMBOL PRESETS
  // ==========================================================================

  /// Apply a symbol preset, replacing all current symbols
  void applyPreset(SymbolPreset preset, {bool clearAudio = true}) {
    _symbols = List.from(preset.symbols);
    if (clearAudio) {
      _symbolAudio = [];
    }
    _syncSymbolStages(); // Sync stages for new preset symbols
    _markDirty();
    debugPrint('[SlotLabProject] Applied preset: ${preset.name} (${preset.symbols.length} symbols)');
  }

  /// Apply preset by ID
  void applyPresetById(String presetId, {bool clearAudio = true}) {
    final preset = SymbolPreset.getById(presetId);
    if (preset != null) {
      applyPreset(preset, clearAudio: clearAudio);
    }
  }

  /// Get all available presets
  List<SymbolPreset> get availablePresets => SymbolPreset.builtInPresets;

  /// Check if current symbols match a preset
  SymbolPresetType? get currentPresetType {
    for (final preset in SymbolPreset.builtInPresets) {
      if (_symbolsMatchPreset(preset)) {
        return preset.type;
      }
    }
    return null;
  }

  bool _symbolsMatchPreset(SymbolPreset preset) {
    if (_symbols.length != preset.symbols.length) return false;
    final currentIds = _symbols.map((s) => s.id).toSet();
    final presetIds = preset.symbols.map((s) => s.id).toSet();
    return currentIds.difference(presetIds).isEmpty;
  }

  /// Replace all symbols with a new list
  void replaceSymbols(List<SymbolDefinition> newSymbols, {bool clearAudio = true}) {
    _symbols = List.from(newSymbols);
    if (clearAudio) {
      _symbolAudio = [];
    }
    _syncSymbolStages(); // Sync stages for new symbols
    _markDirty();
  }

  /// Get symbols filtered by type
  List<SymbolDefinition> getSymbolsByType(SymbolType type) {
    return _symbols.where((s) => s.type == type).toList();
  }

  /// Get symbols sorted by value (highest first)
  List<SymbolDefinition> get symbolsSortedByValue {
    return sortSymbolsByValue(_symbols);
  }

  /// Get all stage IDs for current symbols
  List<String> get allSymbolStageIds => getAllSymbolStageIds(_symbols);

  /// Find symbol by ID
  SymbolDefinition? getSymbolById(String id) => findSymbolById(_symbols, id);

  // ==========================================================================
  // SYMBOL CRUD
  // ==========================================================================

  /// Add a new symbol
  void addSymbol(SymbolDefinition symbol) {
    _symbols = [..._symbols, symbol];
    _syncSymbolStages(); // Sync stages for new symbol
    _markDirty();
  }

  /// Update existing symbol
  void updateSymbol(String id, SymbolDefinition symbol) {
    final index = _symbols.indexWhere((s) => s.id == id);
    if (index != -1) {
      _symbols = [
        ..._symbols.sublist(0, index),
        symbol,
        ..._symbols.sublist(index + 1),
      ];
      _syncSymbolStages(); // Sync stages for updated symbol
      _markDirty();
    }
  }

  /// Remove symbol and its audio assignments
  void removeSymbol(String id) {
    _symbols = _symbols.where((s) => s.id != id).toList();
    _symbolAudio = _symbolAudio.where((a) => a.symbolId != id).toList();
    _syncSymbolStages(); // Sync stages after removal
    _markDirty();
  }

  /// Reorder symbols
  void reorderSymbols(int oldIndex, int newIndex) {
    final symbols = List<SymbolDefinition>.from(_symbols);
    final symbol = symbols.removeAt(oldIndex);
    symbols.insert(newIndex < oldIndex ? newIndex : newIndex - 1, symbol);
    _symbols = symbols;
    // Note: Reorder doesn't need stage sync - stages don't depend on order
    _markDirty();
  }

  // ==========================================================================
  // SYMBOL AUDIO ASSIGNMENTS
  // ==========================================================================

  /// Assign audio to symbol context slot
  void assignSymbolAudio(String symbolId, String context, String audioPath, {double volume = 1.0, double pan = 0.0}) {
    // Remove existing assignment
    _symbolAudio = _symbolAudio.where((a) => !(a.symbolId == symbolId && a.context == context)).toList();
    // Add new assignment
    _symbolAudio = [
      ..._symbolAudio,
      SymbolAudioAssignment(
        symbolId: symbolId,
        context: context,
        audioPath: audioPath,
        volume: volume,
        pan: pan,
      ),
    ];
    _markDirty();
  }

  /// Clear symbol audio assignment
  void clearSymbolAudio(String symbolId, String context) {
    _symbolAudio = _symbolAudio.where((a) => !(a.symbolId == symbolId && a.context == context)).toList();
    _markDirty();
  }

  /// Get audio assignment for symbol context
  SymbolAudioAssignment? getSymbolAudio(String symbolId, String context) {
    final matches = _symbolAudio.where((a) => a.symbolId == symbolId && a.context == context);
    return matches.isNotEmpty ? matches.first : null;
  }

  // ==========================================================================
  // CONTEXT CRUD
  // ==========================================================================

  /// Add a new context
  void addContext(ContextDefinition context) {
    _contexts = [..._contexts, context];
    _markDirty();
    // Sync to ALE if connected
    _syncContextToAle(context);
  }

  /// Update existing context
  void updateContext(String id, ContextDefinition context) {
    final index = _contexts.indexWhere((c) => c.id == id);
    if (index != -1) {
      _contexts = [
        ..._contexts.sublist(0, index),
        context,
        ..._contexts.sublist(index + 1),
      ];
      _markDirty();
    }
  }

  /// Remove context and its music layer assignments
  void removeContext(String id) {
    // Don't allow removing base context
    if (id == 'base') return;
    _contexts = _contexts.where((c) => c.id != id).toList();
    _musicLayers = _musicLayers.where((a) => a.contextId != id).toList();
    _markDirty();
  }

  /// Reorder contexts
  void reorderContexts(int oldIndex, int newIndex) {
    final contexts = List<ContextDefinition>.from(_contexts);
    final context = contexts.removeAt(oldIndex);
    contexts.insert(newIndex < oldIndex ? newIndex : newIndex - 1, context);
    _contexts = contexts;
    _markDirty();
  }

  // ==========================================================================
  // MUSIC LAYER ASSIGNMENTS
  // ==========================================================================

  /// Assign audio to music layer slot
  void assignMusicLayer(String contextId, int layer, String audioPath, {double volume = 1.0, bool loop = true}) {
    // Remove existing assignment
    _musicLayers = _musicLayers.where((a) => !(a.contextId == contextId && a.layer == layer)).toList();
    // Add new assignment
    final assignment = MusicLayerAssignment(
      contextId: contextId,
      layer: layer,
      audioPath: audioPath,
      volume: volume,
      loop: loop,
    );
    _musicLayers = [..._musicLayers, assignment];
    _markDirty();
    // Sync to ALE if connected
    _syncMusicLayerToAle(assignment);
  }

  /// Clear music layer assignment
  void clearMusicLayer(String contextId, int layer) {
    _musicLayers = _musicLayers.where((a) => !(a.contextId == contextId && a.layer == layer)).toList();
    _markDirty();
  }

  /// Get music layer assignment
  MusicLayerAssignment? getMusicLayer(String contextId, int layer) {
    final matches = _musicLayers.where((a) => a.contextId == contextId && a.layer == layer);
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Get all layers for a context
  List<MusicLayerAssignment> getContextLayers(String contextId) {
    return _musicLayers.where((a) => a.contextId == contextId).toList()
      ..sort((a, b) => a.layer.compareTo(b.layer));
  }

  // ==========================================================================
  // ALE INTEGRATION
  // ==========================================================================

  /// Sync context definition to ALE provider
  void _syncContextToAle(ContextDefinition context) {
    if (_aleProvider == null) return;

    // Build layer configuration for this context
    final contextLayers = getContextLayers(context.id);
    debugPrint('[SlotLabProject] Syncing context ${context.id} to ALE with ${contextLayers.length} layers');

    // Note: Full ALE integration would require generating a profile JSON
    // and loading it via AleProvider.loadProfile(). For now, we log the sync.
  }

  /// Sync music layer assignment to ALE provider
  void _syncMusicLayerToAle(MusicLayerAssignment assignment) {
    if (_aleProvider == null) return;

    debugPrint('[SlotLabProject] Syncing music layer ${assignment.contextId}:L${assignment.layer}');
    debugPrint('[SlotLabProject]   → Audio: ${assignment.audioPath}');
    debugPrint('[SlotLabProject]   → Volume: ${assignment.volume}, Loop: ${assignment.loop}');

    // Note: Full ALE integration would require:
    // 1. Register audio path as ALE asset ID
    // 2. Update context layer in ALE profile
    // 3. Reload profile or hot-update layer
  }

  /// Generate ALE-compatible profile JSON for all contexts and layers
  Map<String, dynamic> generateAleProfile() {
    final contextsJson = <String, dynamic>{};

    for (final context in _contexts) {
      final layersList = <Map<String, dynamic>>[];
      final layers = getContextLayers(context.id);

      for (int i = 0; i < context.layerCount; i++) {
        final layer = layers.firstWhere(
          (l) => l.layer == i + 1,
          orElse: () => MusicLayerAssignment(
            contextId: context.id,
            layer: i + 1,
            audioPath: '',
          ),
        );
        layersList.add({
          'index': i,
          'asset_id': layer.audioPath.isNotEmpty
              ? 'slotlab_${context.id}_L${i + 1}'
              : '',
          'audio_path': layer.audioPath,
          'base_volume': layer.volume,
          'loop': layer.loop,
        });
      }

      contextsJson[context.id] = {
        'id': context.id,
        'name': context.displayName,
        'type': context.type.name,
        'layers': layersList,
      };
    }

    return {
      'game_name': _projectName,
      'version': '1.0',
      'contexts': contextsJson,
      'slotlab_source': true,
    };
  }

  /// Get all layer audio paths for a context (for playback)
  Map<int, String> getContextAudioPaths(String contextId) {
    final result = <int, String>{};
    for (final layer in getContextLayers(contextId)) {
      if (layer.audioPath.isNotEmpty) {
        result[layer.layer] = layer.audioPath;
      }
    }
    return result;
  }

  // ==========================================================================
  // WIN TIER CONFIGURATION MANAGEMENT (P5)
  // ==========================================================================

  /// Set complete win tier configuration
  void setWinConfiguration(SlotWinConfiguration config) {
    _winConfiguration = config;
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
    debugPrint('[SlotLabProject] Win configuration updated');
    debugPrint('[SlotLabProject]   Regular tiers: ${config.regularWins.tiers.length}');
    debugPrint('[SlotLabProject]   Big win threshold: ${config.bigWins.threshold}x');
    debugPrint('[SlotLabProject]   Big win tiers: ${config.bigWins.tiers.length}');
  }

  /// Set win configuration from GDD import
  void setWinConfigurationFromGdd(SlotWinConfiguration config) {
    _winConfiguration = config;
    _winConfigFromGdd = true;
    _syncWinTierStages();
    _markDirty();
    debugPrint('[SlotLabProject] Win configuration imported from GDD');
  }

  /// Add a new regular win tier
  void addRegularWinTier(WinTierDefinition tier) {
    final currentTiers = List<WinTierDefinition>.from(_winConfiguration.regularWins.tiers);

    // Check for ID collision
    if (currentTiers.any((t) => t.tierId == tier.tierId)) {
      debugPrint('[SlotLabProject] Warning: Tier ID ${tier.tierId} already exists');
      return;
    }

    currentTiers.add(tier);
    currentTiers.sort((a, b) => a.tierId.compareTo(b.tierId));

    _winConfiguration = _winConfiguration.copyWith(
      regularWins: _winConfiguration.regularWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
    debugPrint('[SlotLabProject] Added regular win tier: ${tier.stageName}');
  }

  /// Update existing regular win tier
  void updateRegularWinTier(int tierId, WinTierDefinition tier) {
    final currentTiers = List<WinTierDefinition>.from(_winConfiguration.regularWins.tiers);
    final index = currentTiers.indexWhere((t) => t.tierId == tierId);

    if (index == -1) {
      debugPrint('[SlotLabProject] Warning: Tier ID $tierId not found');
      return;
    }

    currentTiers[index] = tier;

    _winConfiguration = _winConfiguration.copyWith(
      regularWins: _winConfiguration.regularWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
    debugPrint('[SlotLabProject] Updated regular win tier: ${tier.stageName}');
  }

  /// Remove regular win tier
  void removeRegularWinTier(int tierId) {
    final currentTiers = List<WinTierDefinition>.from(_winConfiguration.regularWins.tiers);
    final removed = currentTiers.where((t) => t.tierId == tierId).firstOrNull;

    if (removed == null) {
      debugPrint('[SlotLabProject] Warning: Tier ID $tierId not found');
      return;
    }

    currentTiers.removeWhere((t) => t.tierId == tierId);

    _winConfiguration = _winConfiguration.copyWith(
      regularWins: _winConfiguration.regularWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
    debugPrint('[SlotLabProject] Removed regular win tier: ${removed.stageName}');
  }

  /// Update big win tier
  void updateBigWinTier(int tierId, BigWinTierDefinition tier) {
    final currentTiers = List<BigWinTierDefinition>.from(_winConfiguration.bigWins.tiers);
    final index = currentTiers.indexWhere((t) => t.tierId == tierId);

    if (index == -1) {
      debugPrint('[SlotLabProject] Warning: Big win tier ID $tierId not found');
      return;
    }

    currentTiers[index] = tier;

    _winConfiguration = _winConfiguration.copyWith(
      bigWins: _winConfiguration.bigWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    _markDirty();
    debugPrint('[SlotLabProject] Updated big win tier: ${tier.stageName}');
  }

  /// Update big win threshold
  void setBigWinThreshold(double threshold) {
    _winConfiguration = _winConfiguration.copyWith(
      bigWins: _winConfiguration.bigWins.copyWith(threshold: threshold),
    );
    _winConfigFromGdd = false;
    _markDirty();
    debugPrint('[SlotLabProject] Big win threshold set to ${threshold}x');
  }

  /// Get win tier for a specific win amount and bet
  /// Returns null if no win, or the tier definition
  WinTierResult? getWinTierForAmount(double winAmount, double betAmount) {
    if (winAmount <= 0 || betAmount <= 0) return null;

    final multiplier = winAmount / betAmount;

    // Check if it's a big win first
    if (_winConfiguration.bigWins.isBigWin(winAmount, betAmount)) {
      final maxTier = _winConfiguration.bigWins.getMaxTierForWin(winAmount, betAmount);
      final bigTier = _winConfiguration.bigWins.tiers.firstWhere(
        (t) => t.tierId == maxTier,
        orElse: () => _winConfiguration.bigWins.tiers.first,
      );
      return WinTierResult(
        isBigWin: true,
        multiplier: multiplier,
        regularTier: null,
        bigWinTier: bigTier,
        bigWinMaxTier: maxTier,
      );
    }

    // Regular win
    final regularTier = _winConfiguration.regularWins.getTierForWin(winAmount, betAmount);
    if (regularTier != null) {
      return WinTierResult(
        isBigWin: false,
        multiplier: multiplier,
        regularTier: regularTier,
        bigWinTier: null,
        bigWinMaxTier: null,
      );
    }

    return null;
  }

  /// Validate current win tier configuration
  bool validateWinConfiguration() {
    return _winConfiguration.regularWins.validate() &&
           _winConfiguration.bigWins.validate();
  }

  /// Reset win configuration to defaults
  void resetWinConfiguration() {
    _winConfiguration = SlotWinConfiguration.defaultConfig();
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
    debugPrint('[SlotLabProject] Win configuration reset to defaults');
  }

  /// Sync win tier stages to StageConfigurationService AND Rust engine
  void _syncWinTierStages() {
    // 1. Register all win tier stages with StageConfigurationService (Dart side)
    StageConfigurationService.instance.registerWinTierStages(_winConfiguration);
    final stages = _winConfiguration.allStageNames;
    debugPrint('[SlotLabProject] Synced ${stages.length} win tier stages to StageConfigurationService');

    // 2. Sync P5 win tier config to Rust engine (FFI)
    _syncWinTierConfigToRust();
  }

  /// Sync P5 win tier config to Rust SlotLab engine
  void _syncWinTierConfigToRust() {
    try {
      final ffi = NativeFFI.instance;

      // Convert SlotWinConfiguration to Rust JSON format
      final jsonConfig = _winConfiguration.toJson();

      // Convert Dart model names to Rust model names:
      // Dart: regularWins.tiers[].tierId, fromMultiplier, toMultiplier, displayLabel, rollupDurationMs, rollupTickRate
      // Rust: regular_wins.tiers[].tier_id, from_multiplier, to_multiplier, display_label, rollup_duration_ms, rollup_tick_rate
      final rustJson = _convertToRustJson(jsonConfig);
      final jsonStr = _jsonEncode(rustJson);

      final success = ffi.winTierSetConfigJson(jsonStr);
      if (success) {
        debugPrint('[SlotLabProject] ✅ P5 win tier config synced to Rust engine');
      } else {
        debugPrint('[SlotLabProject] ⚠️ Failed to sync P5 win tier config to Rust');
      }
    } catch (e) {
      debugPrint('[SlotLabProject] ❌ Error syncing P5 win tier to Rust: $e');
    }
  }

  /// Convert Dart JSON format to Rust JSON format (snake_case)
  Map<String, dynamic> _convertToRustJson(Map<String, dynamic> dartJson) {
    final regularWins = dartJson['regularWins'] as Map<String, dynamic>?;
    final bigWins = dartJson['bigWins'] as Map<String, dynamic>?;

    return {
      'regular_wins': {
        'tiers': (regularWins?['tiers'] as List?)?.map((t) => {
          'tier_id': t['tierId'],
          'from_multiplier': t['fromMultiplier'],
          'to_multiplier': t['toMultiplier'],
          'display_label': t['displayLabel'] ?? '',
          'rollup_duration_ms': t['rollupDurationMs'] ?? 1000,
          'rollup_tick_rate': t['rollupTickRate'] ?? 15,
          'particle_burst_count': t['particleBurstCount'] ?? 0,
        }).toList() ?? [],
      },
      'big_wins': {
        'threshold': bigWins?['threshold'] ?? 20.0,
        'intro_duration_ms': bigWins?['introDurationMs'] ?? 500,
        'end_duration_ms': bigWins?['endDurationMs'] ?? 4000,
        'fade_out_duration_ms': bigWins?['fadeOutDurationMs'] ?? 1000,
        'tiers': (bigWins?['tiers'] as List?)?.map((t) => {
          'tier_id': t['tierId'],
          'from_multiplier': t['fromMultiplier'],
          'to_multiplier': t['toMultiplier'],
          'display_label': t['displayLabel'] ?? '',
          'duration_ms': t['durationMs'] ?? 4000,
          'rollup_tick_rate': t['rollupTickRate'] ?? 10,
          'particle_burst_count': t['particleBurstCount'] ?? 20,
        }).toList() ?? [],
      },
    };
  }

  /// Simple JSON encode without importing dart:convert (already in scope via other imports)
  String _jsonEncode(Map<String, dynamic> map) {
    // Use the same encoder as toJsonString
    return _winConfiguration.toJsonString().isNotEmpty
        ? _encodeMap(map)
        : '{}';
  }

  String _encodeMap(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';
    if (value is List) {
      return '[${value.map(_encodeMap).join(',')}]';
    }
    if (value is Map) {
      final entries = value.entries.map((e) => '"${e.key}":${_encodeMap(e.value)}');
      return '{${entries.join(',')}}';
    }
    return '"$value"';
  }

  /// Apply a win tier preset configuration
  void applyWinTierPreset(SlotWinConfiguration preset) {
    _winConfiguration = preset;
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
    debugPrint('[SlotLabProject] Applied win tier preset');
    debugPrint('[SlotLabProject]   Regular tiers: ${preset.regularWins.tiers.length}');
    debugPrint('[SlotLabProject]   Big win threshold: ${preset.bigWins.threshold}x');
    debugPrint('[SlotLabProject]   Big win tiers: ${preset.bigWins.tiers.length}');
  }

  /// Export win configuration to JSON string
  String exportWinConfigurationJson() {
    return _winConfiguration.toJsonString();
  }

  /// Import win configuration from JSON string
  /// Returns true if import was successful
  bool importWinConfigurationJson(String jsonString) {
    try {
      final config = SlotWinConfiguration.fromJsonString(jsonString);
      if (!config.regularWins.validate() || !config.bigWins.validate()) {
        debugPrint('[SlotLabProject] Import failed: Invalid configuration');
        return false;
      }
      _winConfiguration = config;
      _winConfigFromGdd = false;
      _syncWinTierStages();
      _markDirty();
      debugPrint('[SlotLabProject] Win configuration imported from JSON');
      return true;
    } catch (e) {
      debugPrint('[SlotLabProject] Import failed: $e');
      return false;
    }
  }

  // ==========================================================================
  // PERSISTENCE
  // ==========================================================================

  /// Save project to file
  ///
  /// If [autoCommit] is true (default), changes will be auto-committed
  /// to the git repository after saving.
  Future<void> saveProject(String path, {bool autoCommit = true}) async {
    final file = File(path);
    await file.writeAsString(project.toJsonString());
    _projectPath = path;
    _isDirty = false;
    notifyListeners();

    // P3-05: Auto-commit on project save
    if (autoCommit) {
      final repoPath = file.parent.path;
      try {
        final gitProvider = GitProvider.instance;
        if (!gitProvider.isInitialized || gitProvider.repoPath != repoPath) {
          await gitProvider.init(repoPath);
        }
        if (gitProvider.state.isRepo && gitProvider.state.hasChanges) {
          await gitProvider.autoCommit(
            customMessage: 'Auto-save: $_projectName',
          );
        }
      } catch (e) {
        debugPrint('[SlotLabProjectProvider] Auto-commit failed: $e');
      }
    }
  }

  /// Load project from file
  Future<void> loadProject(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Project file not found: $path');
    }
    final content = await file.readAsString();
    final loaded = SlotLabProject.fromJsonString(content);

    _projectName = loaded.name;
    _projectPath = path;
    _symbols = List.from(loaded.symbols);
    _contexts = List.from(loaded.contexts);
    _symbolAudio = List.from(loaded.symbolAudio);
    _musicLayers = List.from(loaded.musicLayers);
    // V7: Restore audio panel state
    _audioAssignments = Map.from(loaded.audioAssignments);
    _expandedSections = Set.from(loaded.expandedSections);
    _expandedGroups = Set.from(loaded.expandedGroups);
    _lastActiveTab = loaded.lastActiveTab;
    // V8: Restore GDD data
    _gridConfig = loaded.gridConfig;
    _importedGdd = loaded.importedGdd;
    _isDirty = false;
    _syncSymbolStages(); // Sync stages for loaded symbols
    notifyListeners();
  }

  /// Import from JSON string (for GDD import, etc.)
  void importFromJson(String jsonString) {
    final loaded = SlotLabProject.fromJsonString(jsonString);
    _projectName = loaded.name;
    _symbols = List.from(loaded.symbols);
    _contexts = List.from(loaded.contexts);
    _symbolAudio = List.from(loaded.symbolAudio);
    _musicLayers = List.from(loaded.musicLayers);
    // V7: Restore audio panel state
    _audioAssignments = Map.from(loaded.audioAssignments);
    _expandedSections = Set.from(loaded.expandedSections);
    _expandedGroups = Set.from(loaded.expandedGroups);
    _lastActiveTab = loaded.lastActiveTab;
    // V8: Restore GDD data
    _gridConfig = loaded.gridConfig;
    _importedGdd = loaded.importedGdd;
    _syncSymbolStages(); // Sync stages for imported symbols
    _markDirty();
  }

  /// Export to JSON string
  String exportToJson() => project.toJsonString();

  // ==========================================================================
  // GDD IMPORT
  // ==========================================================================

  /// Import symbols from Game Design Document
  void importSymbolsFromGdd(List<Map<String, dynamic>> gddSymbols) {
    for (final gdd in gddSymbols) {
      final id = (gdd['id'] ?? gdd['name'] ?? 'sym_${_symbols.length}').toString().toLowerCase().replaceAll(' ', '_');
      final name = gdd['name']?.toString() ?? 'Symbol ${_symbols.length + 1}';
      final type = _parseSymbolType(gdd['type']?.toString());
      final emoji = gdd['emoji']?.toString() ?? _defaultEmojiForType(type);

      // Check if symbol already exists
      if (_symbols.any((s) => s.id == id)) continue;

      addSymbol(SymbolDefinition(
        id: id,
        name: name,
        emoji: emoji,
        type: type,
        payMultiplier: gdd['payMultiplier'] as int?,
      ));
    }
  }

  SymbolType _parseSymbolType(String? typeStr) {
    if (typeStr == null) return SymbolType.lowPay;
    final lower = typeStr.toLowerCase();
    if (lower.contains('wild')) return SymbolType.wild;
    if (lower.contains('scatter')) return SymbolType.scatter;
    if (lower.contains('bonus')) return SymbolType.bonus;
    if (lower.contains('high') || lower.contains('premium') || lower.contains('hp')) {
      return SymbolType.highPay;
    }
    if (lower.contains('medium') || lower.contains('mid') || lower.contains('mp')) {
      return SymbolType.mediumPay;
    }
    if (lower.contains('mult')) return SymbolType.multiplier;
    if (lower.contains('collect') || lower.contains('coin')) return SymbolType.collector;
    if (lower.contains('mystery')) return SymbolType.mystery;
    return SymbolType.lowPay;
  }

  String _defaultEmojiForType(SymbolType type) {
    return type.defaultEmoji;
  }

  // ==========================================================================
  // BULK RESET METHODS
  // ==========================================================================

  /// Reset all symbol audio assignments for a specific context (land, win, expand)
  void resetSymbolAudioForContext(String context) {
    final before = _symbolAudio.length;
    _symbolAudio = _symbolAudio.where((a) => a.context != context).toList();
    final removed = before - _symbolAudio.length;
    debugPrint('[SlotLabProject] Reset symbol audio for context "$context" — removed $removed assignments');
    _markDirty();
  }

  /// Reset all symbol audio assignments for a specific symbol
  void resetSymbolAudioForSymbol(String symbolId) {
    final before = _symbolAudio.length;
    _symbolAudio = _symbolAudio.where((a) => a.symbolId != symbolId).toList();
    final removed = before - _symbolAudio.length;
    debugPrint('[SlotLabProject] Reset symbol audio for symbol "$symbolId" — removed $removed assignments');
    _markDirty();
  }

  /// Reset ALL symbol audio assignments
  void resetAllSymbolAudio() {
    final count = _symbolAudio.length;
    _symbolAudio = [];
    debugPrint('[SlotLabProject] Reset ALL symbol audio — removed $count assignments');
    _markDirty();
  }

  /// Reset all music layers for a specific context (base, freeSpins, etc.)
  void resetMusicLayersForContext(String contextId) {
    final before = _musicLayers.length;
    _musicLayers = _musicLayers.where((a) => a.contextId != contextId).toList();
    final removed = before - _musicLayers.length;
    debugPrint('[SlotLabProject] Reset music layers for context "$contextId" — removed $removed assignments');
    _markDirty();
  }

  /// Reset ALL music layer assignments
  void resetAllMusicLayers() {
    final count = _musicLayers.length;
    _musicLayers = [];
    debugPrint('[SlotLabProject] Reset ALL music layers — removed $count assignments');
    _markDirty();
  }

  /// Get count of audio assignments per section (for UI display)
  Map<String, int> getAudioAssignmentCounts() {
    final counts = <String, int>{};

    // Symbol audio by context
    for (final assignment in _symbolAudio) {
      final key = 'symbol_${assignment.context}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // Music layers by context
    for (final assignment in _musicLayers) {
      final key = 'music_${assignment.contextId}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // Totals
    counts['symbol_total'] = _symbolAudio.length;
    counts['music_total'] = _musicLayers.length;

    return counts;
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  void _markDirty() {
    _isDirty = true;
    notifyListeners();
  }

  /// Sync symbol stages to StageConfigurationService
  /// Call this whenever symbols are added, removed, or modified
  void _syncSymbolStages() {
    StageConfigurationService.instance.syncSymbolStages(_symbols);
  }

  /// Debug: print current state
  void debugPrintState() {
    debugPrint('=== SlotLabProject State ===');
    debugPrint('Name: $_projectName');
    debugPrint('Symbols: ${_symbols.length}');
    debugPrint('Contexts: ${_contexts.length}');
    debugPrint('Symbol Audio: ${_symbolAudio.length}');
    debugPrint('Music Layers: ${_musicLayers.length}');
    debugPrint('Dirty: $_isDirty');
  }
}

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
import '../providers/ale_provider.dart';
import '../services/gdd_import_service.dart';
import '../services/stage_configuration_service.dart';

/// Provider for SlotLab V6 project state
class SlotLabProjectProvider extends ChangeNotifier {
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
  // GDD IMPORT STATE (V8)
  // ==========================================================================

  /// Imported Game Design Document (if any)
  GameDesignDocument? _importedGdd;

  /// Grid configuration from GDD
  GddGridConfig? _gridConfig;

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
  // PERSISTENCE
  // ==========================================================================

  /// Save project to file
  Future<void> saveProject(String path) async {
    final file = File(path);
    await file.writeAsString(project.toJsonString());
    _projectPath = path;
    _isDirty = false;
    notifyListeners();
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

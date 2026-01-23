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

  // Optional ALE integration
  AleProvider? _aleProvider;

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

  /// Get complete project for serialization
  SlotLabProject get project => SlotLabProject(
        name: _projectName,
        symbols: _symbols,
        contexts: _contexts,
        symbolAudio: _symbolAudio,
        musicLayers: _musicLayers,
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
    _isDirty = false;
    notifyListeners();
  }

  // ==========================================================================
  // SYMBOL CRUD
  // ==========================================================================

  /// Add a new symbol
  void addSymbol(SymbolDefinition symbol) {
    _symbols = [..._symbols, symbol];
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
      _markDirty();
    }
  }

  /// Remove symbol and its audio assignments
  void removeSymbol(String id) {
    _symbols = _symbols.where((s) => s.id != id).toList();
    _symbolAudio = _symbolAudio.where((a) => a.symbolId != id).toList();
    _markDirty();
  }

  /// Reorder symbols
  void reorderSymbols(int oldIndex, int newIndex) {
    final symbols = List<SymbolDefinition>.from(_symbols);
    final symbol = symbols.removeAt(oldIndex);
    symbols.insert(newIndex < oldIndex ? newIndex : newIndex - 1, symbol);
    _symbols = symbols;
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
    _isDirty = false;
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
    if (typeStr == null) return SymbolType.low;
    final lower = typeStr.toLowerCase();
    if (lower.contains('wild')) return SymbolType.wild;
    if (lower.contains('scatter')) return SymbolType.scatter;
    if (lower.contains('bonus')) return SymbolType.bonus;
    if (lower.contains('high') || lower.contains('premium')) return SymbolType.high;
    if (lower.contains('mult')) return SymbolType.multiplier;
    if (lower.contains('collect')) return SymbolType.collector;
    if (lower.contains('mystery')) return SymbolType.mystery;
    return SymbolType.low;
  }

  String _defaultEmojiForType(SymbolType type) {
    switch (type) {
      case SymbolType.wild:
        return '🃏';
      case SymbolType.scatter:
        return '⭐';
      case SymbolType.bonus:
        return '🎁';
      case SymbolType.high:
        return '💎';
      case SymbolType.low:
        return '🔤';
      case SymbolType.multiplier:
        return '✖️';
      case SymbolType.collector:
        return '🧲';
      case SymbolType.mystery:
        return '❓';
    }
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  void _markDirty() {
    _isDirty = true;
    notifyListeners();
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

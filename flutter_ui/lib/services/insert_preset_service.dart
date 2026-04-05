/// Insert Preset Service (P10.1.13)
///
/// Manage DSP insert chain presets:
/// - Built-in presets (10+)
/// - User preset CRUD
/// - Category organization
/// - SharedPreferences storage
///
/// Logic Pro Channel Strip-style workflow.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/insert_chain_preset.dart';
import '../providers/dsp_chain_provider.dart';

/// Storage key for presets in SharedPreferences
const String _kStorageKey = 'fluxforge_insert_chain_presets';

// ═══════════════════════════════════════════════════════════════════════════
// INSERT PRESET SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Singleton service for insert chain preset management
class InsertPresetService extends ChangeNotifier {
  static final InsertPresetService _instance = InsertPresetService._();
  static InsertPresetService get instance => _instance;

  InsertPresetService._();

  /// Cached presets
  final List<InsertChainPreset> _presets = [];
  List<InsertChainPreset> get presets => List.unmodifiable(_presets);

  /// Loading state
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ─── Initialization ─────────────────────────────────────────────────────

  /// Initialize service and load presets
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kStorageKey);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        _presets.clear();
        for (final item in jsonList) {
          try {
            _presets.add(InsertChainPreset.fromJson(item as Map<String, dynamic>));
          } catch (e) { /* ignored */ }
        }
      }

      // Add built-in presets if empty
      if (_presets.isEmpty) {
        _addBuiltInPresets();
        await _saveToStorage();
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _addBuiltInPresets();
      _isInitialized = true;
      notifyListeners();
    }
  }

  // ─── Built-in Presets ───────────────────────────────────────────────────

  void _addBuiltInPresets() {
    _presets.addAll([
      // === VOCAL CATEGORY ===
      InsertChainPreset(
        id: 'builtin_vocal_deess_comp',
        name: 'Vocal: De-Esser + Comp',
        description: 'Clean vocal chain with de-essing and smooth compression',
        category: InsertChainCategory.vocal,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.deEsser,
            params: {'frequency': 6000, 'threshold': -18.0, 'range': -12.0},
          ),
          ChainProcessorConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -18.0,
              'ratio': 3.0,
              'attack': 15.0,
              'release': 150.0,
              'knee': 6.0,
              'makeupGain': 3.0,
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 80, 'gain': -3, 'q': 0.7, 'type': 'lowShelf'},
                {'freq': 3000, 'gain': 2, 'q': 1.5, 'type': 'bell'},
              ]
            },
          ),
        ],
      ),

      // === MASTER CATEGORY ===
      InsertChainPreset(
        id: 'builtin_master_standard',
        name: 'Master: EQ + Comp + Limiter',
        description: 'Standard mastering chain',
        category: InsertChainCategory.master,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 30, 'gain': 0, 'q': 0.7, 'type': 'lowCut'},
                {'freq': 60, 'gain': 1, 'q': 1.0, 'type': 'bell'},
                {'freq': 10000, 'gain': 1.5, 'q': 0.7, 'type': 'highShelf'},
              ]
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -12.0,
              'ratio': 2.0,
              'attack': 30.0,
              'release': 250.0,
              'knee': 10.0,
              'makeupGain': 2.0,
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.limiter,
            params: {'ceiling': -0.3, 'release': 50.0, 'lookahead': 5.0},
          ),
        ],
      ),

      InsertChainPreset(
        id: 'builtin_master_loud',
        name: 'Master: Loud & Punchy',
        description: 'Aggressive mastering for electronic/pop',
        category: InsertChainCategory.master,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.saturation,
            wetDry: 0.2,
            params: {'drive': 0.3, 'mix': 0.2, 'type': 'tape'},
          ),
          ChainProcessorConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -8.0,
              'ratio': 4.0,
              'attack': 10.0,
              'release': 100.0,
              'knee': 3.0,
              'makeupGain': 4.0,
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.limiter,
            params: {'ceiling': -0.1, 'release': 30.0, 'lookahead': 3.0},
          ),
        ],
      ),

      // === MIX CATEGORY ===
      InsertChainPreset(
        id: 'builtin_drum_bus',
        name: 'Mix: Drum Bus',
        description: 'Drum bus glue compression',
        category: InsertChainCategory.mix,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 60, 'gain': 2, 'q': 1.0, 'type': 'bell'},
                {'freq': 5000, 'gain': 2, 'q': 2.0, 'type': 'bell'},
              ]
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -16.0,
              'ratio': 4.0,
              'attack': 10.0,
              'release': 100.0,
              'knee': 6.0,
              'makeupGain': 3.0,
            },
          ),
        ],
      ),

      InsertChainPreset(
        id: 'builtin_bass_control',
        name: 'Mix: Bass Control',
        description: 'Tight bass with controlled low end',
        category: InsertChainCategory.mix,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 30, 'gain': 0, 'q': 1.0, 'type': 'lowCut'},
                {'freq': 80, 'gain': 2, 'q': 1.2, 'type': 'bell'},
                {'freq': 800, 'gain': -2, 'q': 1.0, 'type': 'bell'},
              ]
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -20.0,
              'ratio': 6.0,
              'attack': 20.0,
              'release': 150.0,
              'knee': 3.0,
              'makeupGain': 4.0,
            },
          ),
        ],
      ),

      // === CREATIVE CATEGORY ===
      InsertChainPreset(
        id: 'builtin_reverb_delay',
        name: 'Creative: Reverb + Delay',
        description: 'Atmospheric FX chain',
        category: InsertChainCategory.creative,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 200, 'gain': -3, 'q': 0.7, 'type': 'lowShelf'},
                {'freq': 8000, 'gain': -2, 'q': 0.7, 'type': 'highShelf'},
              ]
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.delay,
            wetDry: 0.4,
            params: {'time': 375.0, 'feedback': 0.35, 'highCut': 6000, 'lowCut': 150},
          ),
          ChainProcessorConfig(
            type: DspNodeType.reverb,
            wetDry: 0.5,
            params: {'decay': 2.5, 'preDelay': 30.0, 'damping': 0.6, 'size': 0.8},
          ),
        ],
      ),

      InsertChainPreset(
        id: 'builtin_saturation_warmth',
        name: 'Creative: Analog Warmth',
        description: 'Saturation for analog warmth',
        category: InsertChainCategory.creative,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 100, 'gain': 1, 'q': 0.7, 'type': 'lowShelf'},
              ]
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.saturation,
            wetDry: 0.5,
            params: {'drive': 0.4, 'mix': 0.5, 'type': 'tube'},
          ),
        ],
      ),

      // === INSTRUMENT CATEGORY ===
      InsertChainPreset(
        id: 'builtin_guitar_clean',
        name: 'Instrument: Clean Guitar',
        description: 'Clean guitar with presence',
        category: InsertChainCategory.instrument,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 100, 'gain': -2, 'q': 0.8, 'type': 'lowShelf'},
                {'freq': 2500, 'gain': 2, 'q': 1.5, 'type': 'bell'},
              ]
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.compressor,
            params: {
              'threshold': -20.0,
              'ratio': 3.0,
              'attack': 25.0,
              'release': 200.0,
              'knee': 6.0,
              'makeupGain': 2.0,
            },
          ),
        ],
      ),

      InsertChainPreset(
        id: 'builtin_synth_pad',
        name: 'Instrument: Synth Pad',
        description: 'Spacious synth pad processing',
        category: InsertChainCategory.instrument,
        createdAt: DateTime(2026, 1, 1),
        processors: [
          ChainProcessorConfig(
            type: DspNodeType.eq,
            params: {
              'bands': [
                {'freq': 200, 'gain': -2, 'q': 0.7, 'type': 'lowShelf'},
                {'freq': 8000, 'gain': 2, 'q': 0.7, 'type': 'highShelf'},
              ]
            },
          ),
          ChainProcessorConfig(
            type: DspNodeType.reverb,
            wetDry: 0.4,
            params: {'decay': 3.0, 'preDelay': 40.0, 'damping': 0.5, 'size': 0.9},
          ),
        ],
      ),

      // === UTILITY CATEGORY ===
      InsertChainPreset(
        id: 'builtin_bypass',
        name: 'Utility: Bypass',
        description: 'Empty chain (unity pass-through)',
        category: InsertChainCategory.utility,
        createdAt: DateTime(2026, 1, 1),
        processors: [],
      ),
    ]);
  }

  // ─── CRUD Operations ────────────────────────────────────────────────────

  /// Save a preset
  Future<bool> savePreset(InsertChainPreset preset) async {
    try {
      final existingIndex = _presets.indexWhere((p) => p.id == preset.id);
      if (existingIndex >= 0) {
        _presets[existingIndex] = preset.copyWith(modifiedAt: DateTime.now());
      } else {
        _presets.add(preset);
      }

      await _saveToStorage();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load preset by ID
  InsertChainPreset? loadPreset(String id) {
    return _presets.where((p) => p.id == id).firstOrNull;
  }

  /// Delete preset
  Future<bool> deletePreset(String id) async {
    try {
      if (id.startsWith('builtin_')) {
        return false;
      }

      _presets.removeWhere((p) => p.id == id);
      await _saveToStorage();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Duplicate preset
  Future<InsertChainPreset?> duplicatePreset(String id) async {
    final original = loadPreset(id);
    if (original == null) return null;

    final duplicate = original.copyWith(
      id: InsertChainPreset.generateId(),
      name: '${original.name} (Copy)',
      createdAt: DateTime.now(),
      modifiedAt: null,
    );

    if (await savePreset(duplicate)) {
      return duplicate;
    }
    return null;
  }

  // ─── Filtering ──────────────────────────────────────────────────────────

  /// Get presets by category
  List<InsertChainPreset> getByCategory(InsertChainCategory category) {
    return _presets.where((p) => p.category == category).toList();
  }

  /// Get all categories with preset counts
  Map<InsertChainCategory, int> getCategoryCounts() {
    final counts = <InsertChainCategory, int>{};
    for (final cat in InsertChainCategory.values) {
      counts[cat] = _presets.where((p) => p.category == cat).length;
    }
    return counts;
  }

  /// Search presets by name
  List<InsertChainPreset> search(String query) {
    if (query.isEmpty) return presets;
    final lowerQuery = query.toLowerCase();
    return _presets
        .where((p) =>
            p.name.toLowerCase().contains(lowerQuery) ||
            (p.description?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }

  /// Get built-in presets only
  List<InsertChainPreset> get builtInPresets =>
      _presets.where((p) => p.id.startsWith('builtin_')).toList();

  /// Get user presets only
  List<InsertChainPreset> get userPresets =>
      _presets.where((p) => !p.id.startsWith('builtin_')).toList();

  // ─── Storage ────────────────────────────────────────────────────────────

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _presets.map((p) => p.toJson()).toList();
      await prefs.setString(_kStorageKey, jsonEncode(jsonList));
    } catch (e) { /* ignored */ }
  }

  /// Export preset to JSON string
  String exportToJson(InsertChainPreset preset) {
    return const JsonEncoder.withIndent('  ').convert(preset.toJson());
  }

  /// Import preset from JSON string
  InsertChainPreset? importFromJson(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return InsertChainPreset.fromJson(json).copyWith(
        id: InsertChainPreset.generateId(),
        createdAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  // ─── DspChainProvider Integration ───────────────────────────────────────

  /// Create preset from current DspChain
  InsertChainPreset createFromChain(
    DspChain chain, {
    required String name,
    String? description,
    InsertChainCategory category = InsertChainCategory.custom,
  }) {
    final processors = chain.sortedNodes.map((node) {
      return ChainProcessorConfig(
        type: node.type,
        customName: node.name != node.type.fullName ? node.name : null,
        bypass: node.bypass,
        wetDry: node.wetDry,
        inputGain: node.inputGain,
        outputGain: node.outputGain,
        params: node.params,
      );
    }).toList();

    return InsertChainPreset(
      id: InsertChainPreset.generateId(),
      name: name,
      description: description,
      category: category,
      createdAt: DateTime.now(),
      processors: processors,
      chainBypass: chain.bypass,
      chainInputGain: chain.inputGain,
      chainOutputGain: chain.outputGain,
    );
  }

  /// Apply preset to track via DspChainProvider
  void applyToTrack(int trackId, InsertChainPreset preset, DspChainProvider provider) {
    // Clear existing chain
    provider.clearChain(trackId);

    // Add processors from preset
    for (final proc in preset.processors) {
      provider.addNode(trackId, proc.type);

      // Get the newly added node
      final chain = provider.getChain(trackId);
      if (chain.nodes.isNotEmpty) {
        final nodeId = chain.nodes.last.id;
        final nodeIndex = chain.nodes.length - 1;

        // Apply node settings
        if (proc.bypass) {
          provider.toggleNodeBypass(trackId, nodeId);
        }
        if (proc.wetDry != 1.0) {
          provider.setNodeWetDry(trackId, nodeId, proc.wetDry);
        }
        if (proc.params.isNotEmpty) {
          provider.updateNodeParams(trackId, nodeId, proc.params);
        }
      }
    }

    // Apply chain-level settings
    if (preset.chainBypass) {
      provider.toggleChainBypass(trackId);
    }
    provider.setChainGain(
      trackId,
      inputGain: preset.chainInputGain,
      outputGain: preset.chainOutputGain,
    );

  }
}

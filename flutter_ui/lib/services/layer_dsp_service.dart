/// Layer DSP Service (P12.1.5)
///
/// Manages per-layer DSP insert chains for SlotLab composite events.
/// Each layer can have its own mini DSP chain (EQ, Comp, Reverb, Delay)
/// applied before playback, similar to Pro Tools clip gain plugins.
///
/// FFI Integration:
/// - Uses NativeFFI.insertLoadProcessor() for loading DSP processors
/// - Uses NativeFFI.insertSetParam() for parameter updates
/// - Uses dedicated layer track IDs (offset by 10000 to avoid collision)
library;

import 'package:flutter/foundation.dart';
import '../models/slot_audio_events.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LAYER DSP PRESETS
// ═══════════════════════════════════════════════════════════════════════════

/// Built-in DSP chain presets for quick layer processing
class LayerDspPreset {
  final String id;
  final String name;
  final String category;
  final List<LayerDspNode> chain;
  final String description;

  const LayerDspPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.chain,
    this.description = '',
  });
}

/// Factory for built-in layer DSP presets
class LayerDspPresets {
  static const List<LayerDspPreset> all = [
    // Clean up
    LayerDspPreset(
      id: 'clean_dialog',
      name: 'Clean Dialog',
      category: 'Voice',
      description: 'Remove mud, add clarity for voice',
      chain: [
        LayerDspNode(
          id: 'preset_eq',
          type: LayerDspType.eq,
          params: {
            'lowGain': -3.0,
            'lowFreq': 150.0,
            'midGain': 2.0,
            'midFreq': 3000.0,
            'midQ': 1.5,
            'highGain': 1.5,
            'highFreq': 8000.0,
          },
        ),
        LayerDspNode(
          id: 'preset_comp',
          type: LayerDspType.compressor,
          params: {
            'threshold': -18.0,
            'ratio': 3.0,
            'attack': 5.0,
            'release': 80.0,
            'makeupGain': 2.0,
          },
        ),
      ],
    ),

    // Impact
    LayerDspPreset(
      id: 'punchy_hit',
      name: 'Punchy Hit',
      category: 'SFX',
      description: 'Add punch and transient snap',
      chain: [
        LayerDspNode(
          id: 'preset_comp',
          type: LayerDspType.compressor,
          params: {
            'threshold': -12.0,
            'ratio': 6.0,
            'attack': 1.0,
            'release': 50.0,
            'makeupGain': 4.0,
          },
        ),
        LayerDspNode(
          id: 'preset_eq',
          type: LayerDspType.eq,
          params: {
            'lowGain': 2.0,
            'lowFreq': 80.0,
            'midGain': 0.0,
            'midFreq': 1000.0,
            'midQ': 1.0,
            'highGain': 3.0,
            'highFreq': 5000.0,
          },
        ),
      ],
    ),

    // Spatial
    LayerDspPreset(
      id: 'subtle_room',
      name: 'Subtle Room',
      category: 'Ambience',
      description: 'Add subtle room ambience',
      chain: [
        LayerDspNode(
          id: 'preset_reverb',
          type: LayerDspType.reverb,
          wetDry: 0.25,
          params: {
            'decay': 1.2,
            'preDelay': 15.0,
            'damping': 0.6,
            'size': 0.4,
          },
        ),
      ],
    ),

    LayerDspPreset(
      id: 'large_hall',
      name: 'Large Hall',
      category: 'Ambience',
      description: 'Epic hall reverb',
      chain: [
        LayerDspNode(
          id: 'preset_reverb',
          type: LayerDspType.reverb,
          wetDry: 0.4,
          params: {
            'decay': 3.5,
            'preDelay': 40.0,
            'damping': 0.35,
            'size': 0.85,
          },
        ),
      ],
    ),

    // Echo effects
    LayerDspPreset(
      id: 'slapback',
      name: 'Slapback',
      category: 'Effects',
      description: 'Quick slapback delay',
      chain: [
        LayerDspNode(
          id: 'preset_delay',
          type: LayerDspType.delay,
          wetDry: 0.3,
          params: {
            'time': 80.0,
            'feedback': 0.1,
            'highCut': 6000.0,
            'lowCut': 150.0,
          },
        ),
      ],
    ),

    LayerDspPreset(
      id: 'rhythmic_delay',
      name: 'Rhythmic Delay',
      category: 'Effects',
      description: 'Rhythmic echo effect',
      chain: [
        LayerDspNode(
          id: 'preset_delay',
          type: LayerDspType.delay,
          wetDry: 0.35,
          params: {
            'time': 375.0,
            'feedback': 0.45,
            'highCut': 4000.0,
            'lowCut': 200.0,
          },
        ),
      ],
    ),

    // Win celebrations
    LayerDspPreset(
      id: 'win_sparkle',
      name: 'Win Sparkle',
      category: 'Slot',
      description: 'Bright and exciting for wins',
      chain: [
        LayerDspNode(
          id: 'preset_eq',
          type: LayerDspType.eq,
          params: {
            'lowGain': -2.0,
            'lowFreq': 100.0,
            'midGain': 1.0,
            'midFreq': 2500.0,
            'midQ': 1.2,
            'highGain': 4.0,
            'highFreq': 10000.0,
          },
        ),
        LayerDspNode(
          id: 'preset_reverb',
          type: LayerDspType.reverb,
          wetDry: 0.2,
          params: {
            'decay': 1.8,
            'preDelay': 25.0,
            'damping': 0.4,
            'size': 0.6,
          },
        ),
      ],
    ),

    LayerDspPreset(
      id: 'big_win_impact',
      name: 'Big Win Impact',
      category: 'Slot',
      description: 'Powerful impact for big wins',
      chain: [
        LayerDspNode(
          id: 'preset_comp',
          type: LayerDspType.compressor,
          params: {
            'threshold': -8.0,
            'ratio': 8.0,
            'attack': 0.5,
            'release': 150.0,
            'makeupGain': 6.0,
          },
        ),
        LayerDspNode(
          id: 'preset_eq',
          type: LayerDspType.eq,
          params: {
            'lowGain': 4.0,
            'lowFreq': 60.0,
            'midGain': -2.0,
            'midFreq': 400.0,
            'midQ': 2.0,
            'highGain': 2.0,
            'highFreq': 6000.0,
          },
        ),
        LayerDspNode(
          id: 'preset_reverb',
          type: LayerDspType.reverb,
          wetDry: 0.15,
          params: {
            'decay': 2.0,
            'preDelay': 10.0,
            'damping': 0.5,
            'size': 0.7,
          },
        ),
      ],
    ),

    // Reel sounds
    LayerDspPreset(
      id: 'reel_mechanical',
      name: 'Reel Mechanical',
      category: 'Slot',
      description: 'Crisp mechanical reel sounds',
      chain: [
        LayerDspNode(
          id: 'preset_eq',
          type: LayerDspType.eq,
          params: {
            'lowGain': -4.0,
            'lowFreq': 120.0,
            'midGain': 3.0,
            'midFreq': 1500.0,
            'midQ': 2.0,
            'highGain': 2.0,
            'highFreq': 6000.0,
          },
        ),
        LayerDspNode(
          id: 'preset_comp',
          type: LayerDspType.compressor,
          params: {
            'threshold': -15.0,
            'ratio': 4.0,
            'attack': 2.0,
            'release': 60.0,
            'makeupGain': 2.0,
          },
        ),
      ],
    ),

    // Lo-fi / vintage
    LayerDspPreset(
      id: 'vintage_radio',
      name: 'Vintage Radio',
      category: 'Effects',
      description: 'Lo-fi radio sound',
      chain: [
        LayerDspNode(
          id: 'preset_eq',
          type: LayerDspType.eq,
          params: {
            'lowGain': -8.0,
            'lowFreq': 300.0,
            'midGain': 4.0,
            'midFreq': 1200.0,
            'midQ': 0.8,
            'highGain': -10.0,
            'highFreq': 4000.0,
          },
        ),
        LayerDspNode(
          id: 'preset_comp',
          type: LayerDspType.compressor,
          params: {
            'threshold': -10.0,
            'ratio': 10.0,
            'attack': 5.0,
            'release': 100.0,
            'makeupGain': 3.0,
          },
        ),
      ],
    ),
  ];

  /// Get presets by category
  static List<LayerDspPreset> getByCategory(String category) =>
      all.where((p) => p.category == category).toList();

  /// Get all categories
  static List<String> get categories =>
      all.map((p) => p.category).toSet().toList()..sort();

  /// Find preset by ID
  static LayerDspPreset? findById(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LAYER DSP SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing per-layer DSP chains in SlotLab
///
/// Layer DSP operates differently from track DSP:
/// - Uses virtual track IDs (offset by 10000) to avoid collision with DAW tracks
/// - Applied during layer playback preparation
/// - Lightweight chain (max 4 processors per layer)
class LayerDspService extends ChangeNotifier {
  static final LayerDspService _instance = LayerDspService._();
  static LayerDspService get instance => _instance;

  LayerDspService._();

  /// FFI instance for Rust engine communication
  NativeFFI get _ffi => NativeFFI.instance;

  /// Track ID offset for layer DSP (avoid collision with DAW tracks)
  static const int _layerTrackIdOffset = 10000;

  /// Maximum processors per layer (keep lightweight)
  static const int maxProcessorsPerLayer = 4;

  /// Active layer DSP states (layerId -> loaded slot count)
  final Map<String, int> _activeLayerDsp = {};

  /// Convert layer ID to virtual track ID for FFI
  int _layerToVirtualTrackId(String layerId) {
    return _layerTrackIdOffset + layerId.hashCode.abs() % 10000;
  }

  /// Maps LayerDspType to Rust processor name
  String _typeToProcessorName(LayerDspType type) {
    return switch (type) {
      LayerDspType.eq => 'pro-eq',
      LayerDspType.compressor => 'compressor',
      LayerDspType.reverb => 'reverb',
      LayerDspType.delay => 'delay',
    };
  }

  /// Check if layer has active DSP
  bool hasActiveDsp(String layerId) => _activeLayerDsp.containsKey(layerId);

  /// Get active DSP count for layer
  int getActiveDspCount(String layerId) => _activeLayerDsp[layerId] ?? 0;

  // ─── Chain Management ──────────────────────────────────────────────────────

  /// Validate a DSP chain (check max processors, parameter ranges)
  bool validateChain(List<LayerDspNode> chain) {
    if (chain.length > maxProcessorsPerLayer) {
      return false;
    }

    for (final node in chain) {
      if (!_validateNodeParams(node)) {
        return false;
      }
    }

    return true;
  }

  /// Validate node parameters are within acceptable ranges
  bool _validateNodeParams(LayerDspNode node) {
    switch (node.type) {
      case LayerDspType.eq:
        final lowGain = (node.params['lowGain'] as num?)?.toDouble() ?? 0;
        final midGain = (node.params['midGain'] as num?)?.toDouble() ?? 0;
        final highGain = (node.params['highGain'] as num?)?.toDouble() ?? 0;
        if (lowGain.abs() > 24 || midGain.abs() > 24 || highGain.abs() > 24) return false;
        break;

      case LayerDspType.compressor:
        final threshold = (node.params['threshold'] as num?)?.toDouble() ?? -20;
        final ratio = (node.params['ratio'] as num?)?.toDouble() ?? 4;
        if (threshold > 0 || threshold < -60) return false;
        if (ratio < 1 || ratio > 20) return false;
        break;

      case LayerDspType.reverb:
        final decay = (node.params['decay'] as num?)?.toDouble() ?? 2;
        if (decay < 0.1 || decay > 20) return false;
        break;

      case LayerDspType.delay:
        final time = (node.params['time'] as num?)?.toDouble() ?? 250;
        final feedback = (node.params['feedback'] as num?)?.toDouble() ?? 0.3;
        if (time < 1 || time > 5000) return false;
        if (feedback < 0 || feedback > 0.95) return false;
        break;
    }

    // Validate wet/dry
    if (node.wetDry < 0 || node.wetDry > 1) return false;

    return true;
  }

  /// Load DSP chain for a layer (prepare for playback)
  Future<bool> loadChainForLayer(String layerId, List<LayerDspNode> chain) async {
    if (chain.isEmpty) return true;

    if (!validateChain(chain)) {
      return false;
    }

    final virtualTrackId = _layerToVirtualTrackId(layerId);

    // Unload any existing DSP first
    await unloadChainForLayer(layerId);

    int loadedCount = 0;
    for (int i = 0; i < chain.length; i++) {
      final node = chain[i];
      if (node.bypass) continue;

      final processorName = _typeToProcessorName(node.type);
      final result = _ffi.insertLoadProcessor(virtualTrackId, loadedCount, processorName);

      if (result < 0) {
        continue;
      }

      // Set wet/dry mix
      if (node.wetDry < 1.0) {
        _ffi.insertSetMix(virtualTrackId, loadedCount, node.wetDry);
      }

      // Apply parameters
      _applyNodeParameters(virtualTrackId, loadedCount, node);

      loadedCount++;
    }

    _activeLayerDsp[layerId] = loadedCount;
    notifyListeners();

    return true;
  }

  /// Unload DSP chain for a layer
  Future<void> unloadChainForLayer(String layerId) async {
    final count = _activeLayerDsp[layerId];
    if (count == null || count == 0) return;

    final virtualTrackId = _layerToVirtualTrackId(layerId);

    // Unload in reverse order
    for (int i = count - 1; i >= 0; i--) {
      _ffi.insertUnloadSlot(virtualTrackId, i);
    }

    _activeLayerDsp.remove(layerId);
    notifyListeners();

  }

  /// Apply node parameters to loaded processor
  void _applyNodeParameters(int virtualTrackId, int slotIndex, LayerDspNode node) {
    switch (node.type) {
      case LayerDspType.eq:
        // 3-band EQ: low shelf, mid bell, high shelf
        // Param indices: 0=lowFreq, 1=lowGain, 2=midFreq, 3=midGain, 4=midQ, 5=highFreq, 6=highGain
        _ffi.insertSetParam(virtualTrackId, slotIndex, 0,
            (node.params['lowFreq'] as num?)?.toDouble() ?? 100.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 1,
            (node.params['lowGain'] as num?)?.toDouble() ?? 0.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 2,
            (node.params['midFreq'] as num?)?.toDouble() ?? 1000.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 3,
            (node.params['midGain'] as num?)?.toDouble() ?? 0.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 4,
            (node.params['midQ'] as num?)?.toDouble() ?? 1.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 5,
            (node.params['highFreq'] as num?)?.toDouble() ?? 8000.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 6,
            (node.params['highGain'] as num?)?.toDouble() ?? 0.0);
        break;

      case LayerDspType.compressor:
        // Param indices: 0=threshold, 1=ratio, 2=attack, 3=release, 4=makeupGain
        _ffi.insertSetParam(virtualTrackId, slotIndex, 0,
            (node.params['threshold'] as num?)?.toDouble() ?? -20.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 1,
            (node.params['ratio'] as num?)?.toDouble() ?? 4.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 2,
            (node.params['attack'] as num?)?.toDouble() ?? 10.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 3,
            (node.params['release'] as num?)?.toDouble() ?? 100.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 4,
            (node.params['makeupGain'] as num?)?.toDouble() ?? 0.0);
        break;

      case LayerDspType.reverb:
        // Param indices: 0=decay, 1=preDelay, 2=damping, 3=size
        _ffi.insertSetParam(virtualTrackId, slotIndex, 0,
            (node.params['decay'] as num?)?.toDouble() ?? 2.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 1,
            (node.params['preDelay'] as num?)?.toDouble() ?? 20.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 2,
            (node.params['damping'] as num?)?.toDouble() ?? 0.5);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 3,
            (node.params['size'] as num?)?.toDouble() ?? 0.7);
        break;

      case LayerDspType.delay:
        // Param indices: 0=time, 1=feedback, 2=highCut, 3=lowCut
        _ffi.insertSetParam(virtualTrackId, slotIndex, 0,
            (node.params['time'] as num?)?.toDouble() ?? 250.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 1,
            (node.params['feedback'] as num?)?.toDouble() ?? 0.3);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 2,
            (node.params['highCut'] as num?)?.toDouble() ?? 8000.0);
        _ffi.insertSetParam(virtualTrackId, slotIndex, 3,
            (node.params['lowCut'] as num?)?.toDouble() ?? 80.0);
        break;
    }
  }

  /// Update a single parameter for a loaded processor
  void updateParameter(
    String layerId,
    int nodeIndex,
    LayerDspType nodeType,
    String paramName,
    double value,
  ) {
    if (!hasActiveDsp(layerId)) return;

    final virtualTrackId = _layerToVirtualTrackId(layerId);
    final paramIndex = _getParamIndex(nodeType, paramName);
    if (paramIndex < 0) return;

    _ffi.insertSetParam(virtualTrackId, nodeIndex, paramIndex, value);
  }

  /// Get parameter index for a given param name and type
  int _getParamIndex(LayerDspType type, String paramName) {
    return switch (type) {
      LayerDspType.eq => switch (paramName) {
          'lowFreq' => 0,
          'lowGain' => 1,
          'midFreq' => 2,
          'midGain' => 3,
          'midQ' => 4,
          'highFreq' => 5,
          'highGain' => 6,
          _ => -1,
        },
      LayerDspType.compressor => switch (paramName) {
          'threshold' => 0,
          'ratio' => 1,
          'attack' => 2,
          'release' => 3,
          'makeupGain' => 4,
          _ => -1,
        },
      LayerDspType.reverb => switch (paramName) {
          'decay' => 0,
          'preDelay' => 1,
          'damping' => 2,
          'size' => 3,
          _ => -1,
        },
      LayerDspType.delay => switch (paramName) {
          'time' => 0,
          'feedback' => 1,
          'highCut' => 2,
          'lowCut' => 3,
          _ => -1,
        },
    };
  }

  // ─── Preset Application ────────────────────────────────────────────────────

  /// Apply a preset to create a new DSP chain
  List<LayerDspNode> applyPreset(String presetId) {
    final preset = LayerDspPresets.findById(presetId);
    if (preset == null) return [];

    // Create new copies with unique IDs
    return preset.chain.map((node) {
      return LayerDspNode(
        id: 'layer-dsp-${DateTime.now().millisecondsSinceEpoch}-${node.type.name}',
        type: node.type,
        bypass: node.bypass,
        wetDry: node.wetDry,
        params: Map<String, dynamic>.from(node.params),
      );
    }).toList();
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────────

  /// Unload all active layer DSP
  void unloadAll() {
    final layerIds = List<String>.from(_activeLayerDsp.keys);
    for (final layerId in layerIds) {
      unloadChainForLayer(layerId);
    }
  }

  /// Get stats
  int get activeLayerCount => _activeLayerDsp.length;
  int get totalProcessorCount =>
      _activeLayerDsp.values.fold(0, (sum, count) => sum + count);
}

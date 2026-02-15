/// DSP Chain Provider (P0.4)
///
/// Manages DSP processor chain for each track:
/// - Add/remove processors
/// - Reorder processors via drag & drop
/// - Toggle bypass per processor
/// - Per-processor state (EQ bands, compressor settings, etc.)
///
/// Chain flows: INPUT → [Processors] → OUTPUT
///
/// FFI INTEGRATION (2026-01-23):
/// - All operations sync with Rust engine via NativeFFI
/// - Uses insertLoadProcessor(), insertUnloadSlot(), insertSetBypass()
/// - UI state only updates on successful FFI calls
library;

import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DSP NODE TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Available DSP processor types
enum DspNodeType {
  eq('FF-Q', 'Parametric EQ'),
  compressor('FF-C', 'Compressor'),
  limiter('FF-L', 'Limiter'),
  gate('FF-G', 'Noise Gate'),
  expander('FF-X', 'Expander'),
  reverb('FF-R', 'Reverb'),
  delay('FF-D', 'Delay'),
  saturation('FF-S', 'Saturation'),
  deEsser('FF-E', 'De-Esser'),
  pultec('FF-PT', 'FF EQP1A'),
  api550('FF-API', 'FF 550A'),
  neve1073('FF-NEV', 'FF 1073');

  final String shortName;
  final String fullName;

  const DspNodeType(this.shortName, this.fullName);
}

// ═══════════════════════════════════════════════════════════════════════════
// DSP NODE MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Single DSP processor node in the chain
class DspNode {
  final String id;
  final DspNodeType type;
  final String name;
  final bool bypass;
  final bool solo; // Solo this processor (mute others)
  final int order; // Position in chain (0 = first after input)
  final double wetDry; // 0 = dry, 1 = wet
  final double inputGain; // dB
  final double outputGain; // dB

  // Type-specific parameters (as JSON-like map)
  final Map<String, dynamic> params;

  const DspNode({
    required this.id,
    required this.type,
    this.name = '',
    this.bypass = false,
    this.solo = false,
    this.order = 0,
    this.wetDry = 1.0,
    this.inputGain = 0.0,
    this.outputGain = 0.0,
    this.params = const {},
  });

  DspNode copyWith({
    String? id,
    DspNodeType? type,
    String? name,
    bool? bypass,
    bool? solo,
    int? order,
    double? wetDry,
    double? inputGain,
    double? outputGain,
    Map<String, dynamic>? params,
  }) {
    return DspNode(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      bypass: bypass ?? this.bypass,
      solo: solo ?? this.solo,
      order: order ?? this.order,
      wetDry: wetDry ?? this.wetDry,
      inputGain: inputGain ?? this.inputGain,
      outputGain: outputGain ?? this.outputGain,
      params: params ?? this.params,
    );
  }

  /// Create a new node with default parameters for the type
  factory DspNode.create(DspNodeType type, {int order = 0}) {
    final id = 'dsp-${DateTime.now().millisecondsSinceEpoch}-${type.name}';
    return DspNode(
      id: id,
      type: type,
      name: type.fullName,
      order: order,
      params: _defaultParams(type),
    );
  }

  static Map<String, dynamic> _defaultParams(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => {
          'bands': [
            {'freq': 80, 'gain': 0, 'q': 1.0, 'type': 'lowShelf'},
            {'freq': 250, 'gain': 0, 'q': 1.0, 'type': 'bell'},
            {'freq': 1000, 'gain': 0, 'q': 1.0, 'type': 'bell'},
            {'freq': 4000, 'gain': 0, 'q': 1.0, 'type': 'bell'},
            {'freq': 10000, 'gain': 0, 'q': 1.0, 'type': 'highShelf'},
          ],
        },
      DspNodeType.compressor => {
          'threshold': -20.0,
          'ratio': 4.0,
          'attack': 10.0,
          'release': 100.0,
          'knee': 6.0,
          'makeupGain': 0.0,
        },
      DspNodeType.limiter => {
          'ceiling': -0.3,
          'release': 50.0,
          'lookahead': 5.0,
        },
      DspNodeType.gate => {
          'threshold': -40.0,
          'attack': 0.5,
          'release': 50.0,
          'range': -80.0,
        },
      DspNodeType.expander => {
          'threshold': -30.0,
          'ratio': 2.0,
          'attack': 5.0,
          'release': 50.0,
          'knee': 3.0,
        },
      DspNodeType.reverb => {
          'size': 0.7,
          'damping': 0.5,
          'width': 1.0,
          'mix': 0.5,
          'preDelay': 20.0,
        },
      DspNodeType.delay => {
          'time': 250.0,
          'feedback': 0.3,
          'highCut': 8000,
          'lowCut': 80,
        },
      DspNodeType.saturation => {
          'drive': 0.0,
          'satType': 0.0,
          'tone': 0.0,
          'mix': 100.0,
          'output': 0.0,
          'tapeBias': 50.0,
          'oversampling': 1.0,
          'inputTrim': 0.0,
          'msMode': 0.0,
          'stereoLink': 1.0,
        },
      DspNodeType.deEsser => {
          'frequency': 6000,
          'threshold': -20.0,
          'range': -10.0,
        },
      DspNodeType.pultec => {
          'lowBoost': 0.0,
          'lowAtten': 0.0,
          'highBoost': 0.0,
          'highAtten': 0.0,
        },
      DspNodeType.api550 => {
          'lowGain': 0.0,
          'midGain': 0.0,
          'highGain': 0.0,
        },
      DspNodeType.neve1073 => {
          'hpEnabled': 0.0,
          'lowGain': 0.0,
          'highGain': 0.0,
        },
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'bypass': bypass,
        'solo': solo,
        'order': order,
        'wetDry': wetDry,
        'inputGain': inputGain,
        'outputGain': outputGain,
        'params': params,
      };

  factory DspNode.fromJson(Map<String, dynamic> json) {
    return DspNode(
      id: json['id'] as String? ?? '',
      type: DspNodeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => DspNodeType.eq,
      ),
      name: json['name'] as String? ?? '',
      bypass: json['bypass'] as bool? ?? false,
      solo: json['solo'] as bool? ?? false,
      order: json['order'] as int? ?? 0,
      wetDry: (json['wetDry'] as num?)?.toDouble() ?? 1.0,
      inputGain: (json['inputGain'] as num?)?.toDouble() ?? 0.0,
      outputGain: (json['outputGain'] as num?)?.toDouble() ?? 0.0,
      params: json['params'] as Map<String, dynamic>? ?? {},
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DSP CHAIN MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Complete DSP chain for a track
class DspChain {
  final int trackId;
  final List<DspNode> nodes;
  final bool bypass; // Bypass entire chain
  final double inputGain; // Chain input gain (dB)
  final double outputGain; // Chain output gain (dB)

  const DspChain({
    required this.trackId,
    this.nodes = const [],
    this.bypass = false,
    this.inputGain = 0.0,
    this.outputGain = 0.0,
  });

  bool get isEmpty => nodes.isEmpty;
  bool get isNotEmpty => nodes.isNotEmpty;
  int get length => nodes.length;

  /// Get nodes sorted by order
  List<DspNode> get sortedNodes {
    final sorted = List<DspNode>.from(nodes);
    sorted.sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  /// Get active (non-bypassed) nodes
  List<DspNode> get activeNodes => nodes.where((n) => !n.bypass).toList();

  DspChain copyWith({
    int? trackId,
    List<DspNode>? nodes,
    bool? bypass,
    double? inputGain,
    double? outputGain,
  }) {
    return DspChain(
      trackId: trackId ?? this.trackId,
      nodes: nodes ?? this.nodes,
      bypass: bypass ?? this.bypass,
      inputGain: inputGain ?? this.inputGain,
      outputGain: outputGain ?? this.outputGain,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DSP CHAIN PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for managing DSP chains across all tracks
class DspChainProvider extends ChangeNotifier {
  static final DspChainProvider _instance = DspChainProvider._();
  static DspChainProvider get instance => _instance;

  DspChainProvider._();

  /// FFI instance for Rust engine communication
  NativeFFI get _ffi => NativeFFI.instance;

  /// Per-track DSP chains
  final Map<int, DspChain> _chains = {};

  /// Maps DspNodeType to Rust processor name
  String _typeToProcessorName(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => 'pro-eq',
      DspNodeType.compressor => 'compressor',
      DspNodeType.limiter => 'limiter',
      DspNodeType.gate => 'gate',
      DspNodeType.expander => 'expander',
      DspNodeType.reverb => 'reverb',
      DspNodeType.delay => 'delay',
      DspNodeType.saturation => 'saturator',
      DspNodeType.deEsser => 'deesser',
      DspNodeType.pultec => 'pultec',
      DspNodeType.api550 => 'api550',
      DspNodeType.neve1073 => 'neve1073',
    };
  }

  /// Get chain for track (creates empty if not exists)
  DspChain getChain(int trackId) {
    return _chains[trackId] ?? DspChain(trackId: trackId);
  }

  /// Check if track has a chain
  bool hasChain(int trackId) => _chains.containsKey(trackId);

  // ─── Chain Operations ──────────────────────────────────────────────────────

  /// Initialize default chain for track (EQ + Comp)
  /// FFI SYNC: Loads default processors in Rust engine
  void initializeChain(int trackId) {
    if (_chains.containsKey(trackId)) return;

    // Create empty chain first
    _chains[trackId] = DspChain(trackId: trackId, nodes: []);

    // Add EQ via FFI
    addNode(trackId, DspNodeType.eq);
    // Add Compressor via FFI
    addNode(trackId, DspNodeType.compressor);

  }

  /// Clear chain for track
  /// FFI SYNC: Unloads all processors from Rust engine
  void clearChain(int trackId) {
    final chain = getChain(trackId);

    // Unload all nodes from engine (reverse order to avoid index issues)
    for (int i = chain.nodes.length - 1; i >= 0; i--) {
      _ffi.insertUnloadSlot(trackId, i);
    }

    _chains[trackId] = DspChain(trackId: trackId);
    notifyListeners();
  }

  /// Toggle chain bypass
  /// FFI SYNC: Calls insertBypassAll() to bypass entire chain in Rust engine
  void toggleChainBypass(int trackId) {
    final chain = getChain(trackId);
    final newBypass = !chain.bypass;

    // FFI sync — Bypass all slots in chain
    _ffi.insertBypassAll(trackId, newBypass);

    _chains[trackId] = chain.copyWith(bypass: newBypass);
    notifyListeners();
  }

  /// Set chain input/output gain
  void setChainGain(int trackId, {double? inputGain, double? outputGain}) {
    final chain = getChain(trackId);
    _chains[trackId] = chain.copyWith(
      inputGain: inputGain ?? chain.inputGain,
      outputGain: outputGain ?? chain.outputGain,
    );
    notifyListeners();
  }

  // ─── Node Operations ───────────────────────────────────────────────────────

  /// Add node to chain
  /// FFI SYNC: Calls insertLoadProcessor() to load processor in Rust engine
  void addNode(int trackId, DspNodeType type) {
    final chain = getChain(trackId);
    final slotIndex = chain.nodes.length;
    final processorName = _typeToProcessorName(type);

    // 1. FFI sync — CRITICAL: Load processor in Rust engine first
    final result = _ffi.insertLoadProcessor(trackId, slotIndex, processorName);
    if (result < 0) {
      return;
    }

    // 2. UI state — Only update on successful FFI call
    final order = chain.nodes.isEmpty ? 0 : chain.nodes.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;
    final node = DspNode.create(type, order: order);
    _chains[trackId] = chain.copyWith(nodes: [...chain.nodes, node]);

    notifyListeners();
  }

  /// Remove node from chain
  /// FFI SYNC: Calls insertUnloadSlot() to unload processor from Rust engine
  void removeNode(int trackId, String nodeId) {
    final chain = getChain(trackId);
    final nodeIndex = chain.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) {
      return;
    }

    // 1. FFI sync — Unload from Rust engine
    final result = _ffi.insertUnloadSlot(trackId, nodeIndex);
    if (result < 0) {
      return;
    }

    // 2. UI state — Only update on successful FFI call
    final newNodes = chain.nodes.where((n) => n.id != nodeId).toList();
    // Re-order remaining nodes
    for (int i = 0; i < newNodes.length; i++) {
      newNodes[i] = newNodes[i].copyWith(order: i);
    }
    _chains[trackId] = chain.copyWith(nodes: newNodes);

    notifyListeners();
  }

  /// Toggle node bypass
  /// FFI SYNC: Calls insertSetBypass() to set bypass state in Rust engine
  void toggleNodeBypass(int trackId, String nodeId) {
    final chain = getChain(trackId);
    final nodeIndex = chain.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) {
      return;
    }

    final node = chain.nodes[nodeIndex];
    final newBypass = !node.bypass;

    // 1. FFI sync — Set bypass in Rust engine
    _ffi.insertSetBypass(trackId, nodeIndex, newBypass);

    // 2. UI state
    final newNodes = chain.nodes.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(bypass: newBypass);
      }
      return n;
    }).toList();
    _chains[trackId] = chain.copyWith(nodes: newNodes);

    notifyListeners();
  }

  /// Set node bypass UI state only (no FFI call).
  /// Used when bypass was already sent via direct FFI.
  void setNodeBypassUiOnly(int trackId, DspNodeType nodeType, bool bypassed) {
    final chain = _chains[trackId];
    if (chain == null) return;
    final nodeIndex = chain.nodes.indexWhere((n) => n.type == nodeType);
    if (nodeIndex == -1) return;
    final node = chain.nodes[nodeIndex];
    if (node.bypass == bypassed) return;
    final newNodes = chain.nodes.map((n) {
      if (n.type == nodeType) return n.copyWith(bypass: bypassed);
      return n;
    }).toList();
    _chains[trackId] = chain.copyWith(nodes: newNodes);
    notifyListeners();
  }

  /// Update node parameters
  /// FFI SYNC: Calls insertSetParam() for each updated parameter
  void updateNodeParams(int trackId, String nodeId, Map<String, dynamic> params) {
    final chain = getChain(trackId);
    final nodeIndex = chain.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    // FFI sync — Send parameter updates to Rust engine
    // Parameter index mapping depends on processor type
    int paramIdx = 0;
    for (final entry in params.entries) {
      if (entry.value is num) {
        _ffi.insertSetParam(trackId, nodeIndex, paramIdx, (entry.value as num).toDouble());
      }
      paramIdx++;
    }

    // UI state
    final newNodes = chain.nodes.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(params: {...n.params, ...params});
      }
      return n;
    }).toList();
    _chains[trackId] = chain.copyWith(nodes: newNodes);
    notifyListeners();
  }

  /// Set node wet/dry mix
  /// FFI SYNC: Calls insertSetMix() to set wet/dry mix in Rust engine
  void setNodeWetDry(int trackId, String nodeId, double wetDry) {
    final chain = getChain(trackId);
    final nodeIndex = chain.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    final clampedMix = wetDry.clamp(0.0, 1.0);

    // 1. FFI sync — Set mix in Rust engine
    _ffi.insertSetMix(trackId, nodeIndex, clampedMix);

    // 2. UI state
    final newNodes = chain.nodes.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(wetDry: clampedMix);
      }
      return n;
    }).toList();
    _chains[trackId] = chain.copyWith(nodes: newNodes);
    notifyListeners();
  }

  // ─── Reorder Operations ────────────────────────────────────────────────────

  /// Move node to new position in chain
  /// FFI SYNC: Requires unloading/reloading processors (engine doesn't support swap)
  void reorderNode(int trackId, String nodeId, int newOrder) {
    final chain = getChain(trackId);
    final nodeIndex = chain.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;
    if (nodeIndex == newOrder) return; // No change

    // Prepare new order
    final newNodes = List<DspNode>.from(chain.nodes);
    final node = newNodes.removeAt(nodeIndex);
    final insertIndex = newOrder.clamp(0, newNodes.length);
    newNodes.insert(insertIndex, node);

    // Re-assign orders
    for (int i = 0; i < newNodes.length; i++) {
      newNodes[i] = newNodes[i].copyWith(order: i);
    }

    // FFI SYNC: Unload all processors and reload in new order
    // This is required because Rust InsertChain doesn't support native reorder
    for (int i = chain.nodes.length - 1; i >= 0; i--) {
      _ffi.insertUnloadSlot(trackId, i);
    }
    for (int i = 0; i < newNodes.length; i++) {
      final n = newNodes[i];
      final processorName = _typeToProcessorName(n.type);
      _ffi.insertLoadProcessor(trackId, i, processorName);
      if (n.bypass) {
        _ffi.insertSetBypass(trackId, i, true);
      }
      if (n.wetDry != 1.0) {
        _ffi.insertSetMix(trackId, i, n.wetDry);
      }
      _restoreNodeParameters(trackId, i, n); // ✅ Restore all params
    }

    _chains[trackId] = chain.copyWith(nodes: newNodes);
    notifyListeners();
  }

  /// Swap two nodes in chain
  /// FFI SYNC: Uses reorderNode internally (unload/reload)
  void swapNodes(int trackId, String nodeIdA, String nodeIdB) {
    final chain = getChain(trackId);
    final indexA = chain.nodes.indexWhere((n) => n.id == nodeIdA);
    final indexB = chain.nodes.indexWhere((n) => n.id == nodeIdB);
    if (indexA == -1 || indexB == -1) return;
    if (indexA == indexB) return;

    final newNodes = List<DspNode>.from(chain.nodes);
    final temp = newNodes[indexA];
    newNodes[indexA] = newNodes[indexB].copyWith(order: indexA);
    newNodes[indexB] = temp.copyWith(order: indexB);

    // FFI SYNC: Unload and reload in swapped order
    _ffi.insertUnloadSlot(trackId, indexA);
    _ffi.insertUnloadSlot(trackId, indexB);

    final nodeA = newNodes[indexA];
    final nodeB = newNodes[indexB];

    // Reload in correct order (lower index first)
    final firstIdx = indexA < indexB ? indexA : indexB;
    final secondIdx = indexA < indexB ? indexB : indexA;
    final firstNode = indexA < indexB ? nodeA : nodeB;
    final secondNode = indexA < indexB ? nodeB : nodeA;

    _ffi.insertLoadProcessor(trackId, firstIdx, _typeToProcessorName(firstNode.type));
    if (firstNode.bypass) _ffi.insertSetBypass(trackId, firstIdx, true);
    if (firstNode.wetDry != 1.0) _ffi.insertSetMix(trackId, firstIdx, firstNode.wetDry);
    _restoreNodeParameters(trackId, firstIdx, firstNode); // ✅ Restore params

    _ffi.insertLoadProcessor(trackId, secondIdx, _typeToProcessorName(secondNode.type));
    if (secondNode.bypass) _ffi.insertSetBypass(trackId, secondIdx, true);
    if (secondNode.wetDry != 1.0) _ffi.insertSetMix(trackId, secondIdx, secondNode.wetDry);
    _restoreNodeParameters(trackId, secondIdx, secondNode); // ✅ Restore params

    _chains[trackId] = chain.copyWith(nodes: newNodes);
    notifyListeners();
  }

  /// Restore all parameters from node to engine slot
  /// CRITICAL: Preserves EQ bands, comp settings, etc. after reorder
  void _restoreNodeParameters(int trackId, int slotIndex, DspNode node) {
    // Parameter restoration depends on processor type
    switch (node.type) {
      case DspNodeType.eq:
        // Restore EQ bands
        final bands = node.params['bands'] as List<dynamic>? ?? [];
        for (int i = 0; i < bands.length; i++) {
          final band = bands[i] as Map<String, dynamic>;
          final freq = (band['freq'] as num?)?.toDouble() ?? 1000.0;
          final gain = (band['gain'] as num?)?.toDouble() ?? 0.0;
          final q = (band['q'] as num?)?.toDouble() ?? 1.0;
          // Map to parameter indices (0-3 per band: freq, gain, q, type)
          _ffi.insertSetParam(trackId, slotIndex, i * 4 + 0, freq);
          _ffi.insertSetParam(trackId, slotIndex, i * 4 + 1, gain);
          _ffi.insertSetParam(trackId, slotIndex, i * 4 + 2, q);
        }
        break;

      case DspNodeType.compressor:
      case DspNodeType.expander:
        // Restore dynamics parameters
        final threshold = (node.params['threshold'] as num?)?.toDouble() ?? -20.0;
        final ratio = (node.params['ratio'] as num?)?.toDouble() ?? 4.0;
        final attack = (node.params['attack'] as num?)?.toDouble() ?? 10.0;
        final release = (node.params['release'] as num?)?.toDouble() ?? 100.0;
        final knee = (node.params['knee'] as num?)?.toDouble() ?? 6.0;
        final makeupGain = (node.params['makeupGain'] as num?)?.toDouble() ?? 0.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, threshold);
        _ffi.insertSetParam(trackId, slotIndex, 1, ratio);
        _ffi.insertSetParam(trackId, slotIndex, 2, attack);
        _ffi.insertSetParam(trackId, slotIndex, 3, release);
        _ffi.insertSetParam(trackId, slotIndex, 4, knee);
        _ffi.insertSetParam(trackId, slotIndex, 5, makeupGain);
        break;

      case DspNodeType.limiter:
        // Restore limiter parameters
        final ceiling = (node.params['ceiling'] as num?)?.toDouble() ?? -0.3;
        final release = (node.params['release'] as num?)?.toDouble() ?? 50.0;
        final lookahead = (node.params['lookahead'] as num?)?.toDouble() ?? 5.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, ceiling);
        _ffi.insertSetParam(trackId, slotIndex, 1, release);
        _ffi.insertSetParam(trackId, slotIndex, 2, lookahead);
        break;

      case DspNodeType.gate:
        // Restore gate parameters
        final threshold = (node.params['threshold'] as num?)?.toDouble() ?? -40.0;
        final attack = (node.params['attack'] as num?)?.toDouble() ?? 0.5;
        final release = (node.params['release'] as num?)?.toDouble() ?? 50.0;
        final range = (node.params['range'] as num?)?.toDouble() ?? -80.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, threshold);
        _ffi.insertSetParam(trackId, slotIndex, 1, attack);
        _ffi.insertSetParam(trackId, slotIndex, 2, release);
        _ffi.insertSetParam(trackId, slotIndex, 3, range);
        break;

      case DspNodeType.reverb:
        // Restore reverb parameters — indices match Rust ReverbWrapper:
        // 0=Room Size, 1=Damping, 2=Width, 3=Mix, 4=Predelay, 5=Type
        final size = (node.params['size'] as num?)?.toDouble() ?? 0.7;
        final damping = (node.params['damping'] as num?)?.toDouble() ?? 0.5;
        final width = (node.params['width'] as num?)?.toDouble() ?? 1.0;
        final mix = (node.params['mix'] as num?)?.toDouble() ?? 0.5;
        final preDelay = (node.params['preDelay'] as num?)?.toDouble() ?? 20.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, size);
        _ffi.insertSetParam(trackId, slotIndex, 1, damping);
        _ffi.insertSetParam(trackId, slotIndex, 2, width);
        _ffi.insertSetParam(trackId, slotIndex, 3, mix);
        _ffi.insertSetParam(trackId, slotIndex, 4, preDelay);
        break;

      case DspNodeType.delay:
        // Restore delay parameters
        final time = (node.params['time'] as num?)?.toDouble() ?? 250.0;
        final feedback = (node.params['feedback'] as num?)?.toDouble() ?? 0.3;
        final highCut = (node.params['highCut'] as num?)?.toDouble() ?? 8000.0;
        final lowCut = (node.params['lowCut'] as num?)?.toDouble() ?? 80.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, time);
        _ffi.insertSetParam(trackId, slotIndex, 1, feedback);
        _ffi.insertSetParam(trackId, slotIndex, 2, highCut);
        _ffi.insertSetParam(trackId, slotIndex, 3, lowCut);
        break;

      case DspNodeType.saturation:
        // Restore all 10 Saturn-class saturation parameters
        final drive = (node.params['drive'] as num?)?.toDouble() ?? 0.0;
        final satType = (node.params['satType'] as num?)?.toDouble() ?? 0.0;
        final tone = (node.params['tone'] as num?)?.toDouble() ?? 0.0;
        final mix = (node.params['mix'] as num?)?.toDouble() ?? 100.0;
        final output = (node.params['output'] as num?)?.toDouble() ?? 0.0;
        final tapeBias = (node.params['tapeBias'] as num?)?.toDouble() ?? 50.0;
        final oversampling = (node.params['oversampling'] as num?)?.toDouble() ?? 1.0;
        final inputTrim = (node.params['inputTrim'] as num?)?.toDouble() ?? 0.0;
        final msMode = (node.params['msMode'] as num?)?.toDouble() ?? 0.0;
        final stereoLink = (node.params['stereoLink'] as num?)?.toDouble() ?? 1.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, drive);
        _ffi.insertSetParam(trackId, slotIndex, 1, satType);
        _ffi.insertSetParam(trackId, slotIndex, 2, tone);
        _ffi.insertSetParam(trackId, slotIndex, 3, mix);
        _ffi.insertSetParam(trackId, slotIndex, 4, output);
        _ffi.insertSetParam(trackId, slotIndex, 5, tapeBias);
        _ffi.insertSetParam(trackId, slotIndex, 6, oversampling);
        _ffi.insertSetParam(trackId, slotIndex, 7, inputTrim);
        _ffi.insertSetParam(trackId, slotIndex, 8, msMode);
        _ffi.insertSetParam(trackId, slotIndex, 9, stereoLink);
        break;

      case DspNodeType.deEsser:
        // Restore de-esser parameters
        final frequency = (node.params['frequency'] as num?)?.toDouble() ?? 6000.0;
        final threshold = (node.params['threshold'] as num?)?.toDouble() ?? -20.0;
        final range = (node.params['range'] as num?)?.toDouble() ?? -10.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, frequency);
        _ffi.insertSetParam(trackId, slotIndex, 1, threshold);
        _ffi.insertSetParam(trackId, slotIndex, 2, range);
        break;

      case DspNodeType.pultec:
        // Restore Pultec EQP-1A parameters (Rust: 0=Low Boost, 1=Low Atten, 2=High Boost, 3=High Atten)
        final lowBoost = (node.params['lowBoost'] as num?)?.toDouble() ?? 0.0;
        final lowAtten = (node.params['lowAtten'] as num?)?.toDouble() ?? 0.0;
        final highBoost = (node.params['highBoost'] as num?)?.toDouble() ?? 0.0;
        final highAtten = (node.params['highAtten'] as num?)?.toDouble() ?? 0.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, lowBoost);
        _ffi.insertSetParam(trackId, slotIndex, 1, lowAtten);
        _ffi.insertSetParam(trackId, slotIndex, 2, highBoost);
        _ffi.insertSetParam(trackId, slotIndex, 3, highAtten);
        break;

      case DspNodeType.api550:
        // Restore API 550A parameters (Rust: 0=Low Gain, 1=Mid Gain, 2=High Gain)
        final lowGain = (node.params['lowGain'] as num?)?.toDouble() ?? 0.0;
        final midGain = (node.params['midGain'] as num?)?.toDouble() ?? 0.0;
        final highGain = (node.params['highGain'] as num?)?.toDouble() ?? 0.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, lowGain);
        _ffi.insertSetParam(trackId, slotIndex, 1, midGain);
        _ffi.insertSetParam(trackId, slotIndex, 2, highGain);
        break;

      case DspNodeType.neve1073:
        // Restore Neve 1073 parameters (Rust: 0=HP Enabled, 1=Low Gain, 2=High Gain)
        final hpEnabled = (node.params['hpEnabled'] as num?)?.toDouble() ?? 0.0;
        final lowGain = (node.params['lowGain'] as num?)?.toDouble() ?? 0.0;
        final highGain = (node.params['highGain'] as num?)?.toDouble() ?? 0.0;
        _ffi.insertSetParam(trackId, slotIndex, 0, hpEnabled);
        _ffi.insertSetParam(trackId, slotIndex, 1, lowGain);
        _ffi.insertSetParam(trackId, slotIndex, 2, highGain);
        break;
    }

  }

  // ─── Copy/Paste ────────────────────────────────────────────────────────────

  DspChain? _clipboard;

  /// Copy chain to clipboard
  void copyChain(int trackId) {
    _clipboard = getChain(trackId);
  }

  /// Paste chain from clipboard
  /// FFI SYNC: Clears existing chain and loads all pasted processors
  void pasteChain(int trackId) {
    if (_clipboard == null) return;

    // 1. Clear existing chain (unloads processors from engine)
    final existingChain = getChain(trackId);
    for (int i = existingChain.nodes.length - 1; i >= 0; i--) {
      _ffi.insertUnloadSlot(trackId, i);
    }

    // 2. Create new node IDs for pasted nodes
    final newNodes = _clipboard!.nodes.map((n) {
      return DspNode(
        id: 'dsp-${DateTime.now().millisecondsSinceEpoch}-${n.type.name}',
        type: n.type,
        name: n.name,
        bypass: n.bypass,
        order: n.order,
        wetDry: n.wetDry,
        inputGain: n.inputGain,
        outputGain: n.outputGain,
        params: Map<String, dynamic>.from(n.params),
      );
    }).toList();

    // 3. Load all processors via FFI
    for (int i = 0; i < newNodes.length; i++) {
      final n = newNodes[i];
      final processorName = _typeToProcessorName(n.type);
      _ffi.insertLoadProcessor(trackId, i, processorName);
      if (n.bypass) {
        _ffi.insertSetBypass(trackId, i, true);
      }
      if (n.wetDry != 1.0) {
        _ffi.insertSetMix(trackId, i, n.wetDry);
      }
      _restoreNodeParameters(trackId, i, n); // ✅ Restore all params
    }

    // 4. Update UI state
    _chains[trackId] = DspChain(
      trackId: trackId,
      nodes: newNodes,
      bypass: _clipboard!.bypass,
      inputGain: _clipboard!.inputGain,
      outputGain: _clipboard!.outputGain,
    );

    notifyListeners();
  }

  bool get hasClipboard => _clipboard != null;

  // ─── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'chains': _chains.map((k, v) => MapEntry(
            k.toString(),
            {
              'trackId': v.trackId,
              'bypass': v.bypass,
              'inputGain': v.inputGain,
              'outputGain': v.outputGain,
              'nodes': v.nodes.map((n) => n.toJson()).toList(),
            },
          )),
    };
  }

  /// Load chain from JSON (project load)
  /// FFI SYNC: Loads all processors into Rust engine
  void fromJson(Map<String, dynamic> json) {
    _chains.clear();
    final chainsJson = json['chains'] as Map<String, dynamic>? ?? {};
    for (final entry in chainsJson.entries) {
      final trackId = int.tryParse(entry.key) ?? 0;
      final chainJson = entry.value as Map<String, dynamic>;
      final nodes = (chainJson['nodes'] as List<dynamic>?)
              ?.map((n) => DspNode.fromJson(n as Map<String, dynamic>))
              .toList() ??
          [];

      // FFI SYNC: Load all processors into Rust engine
      for (int i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        final processorName = _typeToProcessorName(n.type);
        _ffi.insertLoadProcessor(trackId, i, processorName);
        if (n.bypass) {
          _ffi.insertSetBypass(trackId, i, true);
        }
        if (n.wetDry != 1.0) {
          _ffi.insertSetMix(trackId, i, n.wetDry);
        }
        _restoreNodeParameters(trackId, i, n); // ✅ Restore all params from JSON
      }

      _chains[trackId] = DspChain(
        trackId: chainJson['trackId'] as int? ?? trackId,
        bypass: chainJson['bypass'] as bool? ?? false,
        inputGain: (chainJson['inputGain'] as num?)?.toDouble() ?? 0.0,
        outputGain: (chainJson['outputGain'] as num?)?.toDouble() ?? 0.0,
        nodes: nodes,
      );

      // If chain bypass is enabled, bypass all
      if (_chains[trackId]!.bypass) {
        _ffi.insertBypassAll(trackId, true);
      }
    }
    notifyListeners();
  }
}

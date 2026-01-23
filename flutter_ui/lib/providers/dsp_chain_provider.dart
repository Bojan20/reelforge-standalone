/// DSP Chain Provider (P0.4)
///
/// Manages DSP processor chain for each track:
/// - Add/remove processors
/// - Reorder processors via drag & drop
/// - Toggle bypass per processor
/// - Per-processor state (EQ bands, compressor settings, etc.)
///
/// Chain flows: INPUT → [Processors] → OUTPUT
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DSP NODE TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Available DSP processor types
enum DspNodeType {
  eq('EQ', 'Parametric EQ'),
  compressor('Comp', 'Compressor'),
  limiter('Limiter', 'Limiter'),
  gate('Gate', 'Noise Gate'),
  reverb('Reverb', 'Reverb'),
  delay('Delay', 'Delay'),
  saturation('Sat', 'Saturation'),
  deEsser('De-Ess', 'De-Esser');

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
      DspNodeType.reverb => {
          'decay': 2.0,
          'preDelay': 20.0,
          'damping': 0.5,
          'size': 0.7,
        },
      DspNodeType.delay => {
          'time': 250.0,
          'feedback': 0.3,
          'highCut': 8000,
          'lowCut': 80,
        },
      DspNodeType.saturation => {
          'drive': 0.3,
          'mix': 0.5,
          'type': 'tape',
        },
      DspNodeType.deEsser => {
          'frequency': 6000,
          'threshold': -20.0,
          'range': -10.0,
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

  /// Per-track DSP chains
  final Map<int, DspChain> _chains = {};

  /// Get chain for track (creates empty if not exists)
  DspChain getChain(int trackId) {
    return _chains[trackId] ?? DspChain(trackId: trackId);
  }

  /// Check if track has a chain
  bool hasChain(int trackId) => _chains.containsKey(trackId);

  // ─── Chain Operations ──────────────────────────────────────────────────────

  /// Initialize default chain for track (EQ + Comp)
  void initializeChain(int trackId) {
    if (_chains.containsKey(trackId)) return;

    _chains[trackId] = DspChain(
      trackId: trackId,
      nodes: [
        DspNode.create(DspNodeType.eq, order: 0),
        DspNode.create(DspNodeType.compressor, order: 1),
      ],
    );
    debugPrint('[DspChainProvider] Initialized chain for track $trackId');
    notifyListeners();
  }

  /// Clear chain for track
  void clearChain(int trackId) {
    _chains[trackId] = DspChain(trackId: trackId);
    debugPrint('[DspChainProvider] Cleared chain for track $trackId');
    notifyListeners();
  }

  /// Toggle chain bypass
  void toggleChainBypass(int trackId) {
    final chain = getChain(trackId);
    _chains[trackId] = chain.copyWith(bypass: !chain.bypass);
    debugPrint('[DspChainProvider] Chain bypass: ${!chain.bypass} for track $trackId');
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
  void addNode(int trackId, DspNodeType type) {
    final chain = getChain(trackId);
    final order = chain.nodes.isEmpty ? 0 : chain.nodes.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;
    final node = DspNode.create(type, order: order);
    _chains[trackId] = chain.copyWith(nodes: [...chain.nodes, node]);
    debugPrint('[DspChainProvider] Added ${type.name} to track $trackId');
    notifyListeners();
  }

  /// Remove node from chain
  void removeNode(int trackId, String nodeId) {
    final chain = getChain(trackId);
    final newNodes = chain.nodes.where((n) => n.id != nodeId).toList();
    // Re-order remaining nodes
    for (int i = 0; i < newNodes.length; i++) {
      newNodes[i] = newNodes[i].copyWith(order: i);
    }
    _chains[trackId] = chain.copyWith(nodes: newNodes);
    debugPrint('[DspChainProvider] Removed node $nodeId from track $trackId');
    notifyListeners();
  }

  /// Toggle node bypass
  void toggleNodeBypass(int trackId, String nodeId) {
    final chain = getChain(trackId);
    final newNodes = chain.nodes.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(bypass: !n.bypass);
      }
      return n;
    }).toList();
    _chains[trackId] = chain.copyWith(nodes: newNodes);
    debugPrint('[DspChainProvider] Toggled bypass for node $nodeId');
    notifyListeners();
  }

  /// Update node parameters
  void updateNodeParams(int trackId, String nodeId, Map<String, dynamic> params) {
    final chain = getChain(trackId);
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
  void setNodeWetDry(int trackId, String nodeId, double wetDry) {
    final chain = getChain(trackId);
    final newNodes = chain.nodes.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(wetDry: wetDry.clamp(0.0, 1.0));
      }
      return n;
    }).toList();
    _chains[trackId] = chain.copyWith(nodes: newNodes);
    notifyListeners();
  }

  // ─── Reorder Operations ────────────────────────────────────────────────────

  /// Move node to new position in chain
  void reorderNode(int trackId, String nodeId, int newOrder) {
    final chain = getChain(trackId);
    final nodeIndex = chain.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    final newNodes = List<DspNode>.from(chain.nodes);
    final node = newNodes.removeAt(nodeIndex);
    final insertIndex = newOrder.clamp(0, newNodes.length);
    newNodes.insert(insertIndex, node);

    // Re-assign orders
    for (int i = 0; i < newNodes.length; i++) {
      newNodes[i] = newNodes[i].copyWith(order: i);
    }

    _chains[trackId] = chain.copyWith(nodes: newNodes);
    debugPrint('[DspChainProvider] Reordered node $nodeId to position $newOrder');
    notifyListeners();
  }

  /// Swap two nodes in chain
  void swapNodes(int trackId, String nodeIdA, String nodeIdB) {
    final chain = getChain(trackId);
    final indexA = chain.nodes.indexWhere((n) => n.id == nodeIdA);
    final indexB = chain.nodes.indexWhere((n) => n.id == nodeIdB);
    if (indexA == -1 || indexB == -1) return;

    final newNodes = List<DspNode>.from(chain.nodes);
    final temp = newNodes[indexA];
    newNodes[indexA] = newNodes[indexB].copyWith(order: indexA);
    newNodes[indexB] = temp.copyWith(order: indexB);

    _chains[trackId] = chain.copyWith(nodes: newNodes);
    debugPrint('[DspChainProvider] Swapped nodes $nodeIdA <-> $nodeIdB');
    notifyListeners();
  }

  // ─── Copy/Paste ────────────────────────────────────────────────────────────

  DspChain? _clipboard;

  /// Copy chain to clipboard
  void copyChain(int trackId) {
    _clipboard = getChain(trackId);
    debugPrint('[DspChainProvider] Copied chain from track $trackId');
  }

  /// Paste chain from clipboard
  void pasteChain(int trackId) {
    if (_clipboard == null) return;

    // Create new node IDs for pasted nodes
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

    _chains[trackId] = DspChain(
      trackId: trackId,
      nodes: newNodes,
      bypass: _clipboard!.bypass,
      inputGain: _clipboard!.inputGain,
      outputGain: _clipboard!.outputGain,
    );

    debugPrint('[DspChainProvider] Pasted chain to track $trackId');
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

  void fromJson(Map<String, dynamic> json) {
    _chains.clear();
    final chainsJson = json['chains'] as Map<String, dynamic>? ?? {};
    for (final entry in chainsJson.entries) {
      final trackId = int.tryParse(entry.key) ?? 0;
      final chainJson = entry.value as Map<String, dynamic>;
      _chains[trackId] = DspChain(
        trackId: chainJson['trackId'] as int? ?? trackId,
        bypass: chainJson['bypass'] as bool? ?? false,
        inputGain: (chainJson['inputGain'] as num?)?.toDouble() ?? 0.0,
        outputGain: (chainJson['outputGain'] as num?)?.toDouble() ?? 0.0,
        nodes: (chainJson['nodes'] as List<dynamic>?)
                ?.map((n) => DspNode.fromJson(n as Map<String, dynamic>))
                .toList() ??
            [],
      );
    }
    notifyListeners();
  }
}

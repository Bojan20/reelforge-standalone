/// Music System Provider
///
/// Extracted from MiddlewareProvider as part of P1.7 decomposition.
/// Manages music segments, stingers, and music playback state (Wwise/FMOD-style).
///
/// Music segments are looping or one-shot musical pieces that can be
/// queued and transitioned between. Stingers are short musical phrases
/// triggered by game events, synced to the beat/bar grid.

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing music system (segments and stingers)
class MusicSystemProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Music segments storage
  final Map<int, MusicSegment> _musicSegments = {};

  /// Stingers storage
  final Map<int, Stinger> _stingers = {};

  /// Currently playing music segment
  int? _currentMusicSegmentId;

  /// Next queued music segment (for seamless transition)
  int? _nextMusicSegmentId;

  /// Music bus ID for routing
  int _musicBusId = 1; // Default to music bus

  /// ID counters
  int _nextMusicSegmentIdCounter = 1;
  int _nextStingerId = 1;

  MusicSystemProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all music segments as list
  List<MusicSegment> get musicSegments => _musicSegments.values.toList();

  /// Get all stingers as list
  List<Stinger> get stingers => _stingers.values.toList();

  /// Get currently playing segment ID
  int? get currentMusicSegmentId => _currentMusicSegmentId;

  /// Get next queued segment ID
  int? get nextMusicSegmentId => _nextMusicSegmentId;

  /// Get music bus ID
  int get musicBusId => _musicBusId;

  /// Get segment count
  int get segmentCount => _musicSegments.length;

  /// Get stinger count
  int get stingerCount => _stingers.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC SEGMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new music segment
  MusicSegment addMusicSegment({
    required String name,
    required int soundId,
    double tempo = 120.0,
    int beatsPerBar = 4,
    int durationBars = 4,
  }) {
    final id = _nextMusicSegmentIdCounter++;

    final segment = MusicSegment(
      id: id,
      name: name,
      soundId: soundId,
      tempo: tempo,
      beatsPerBar: beatsPerBar,
      durationBars: durationBars,
    );

    _musicSegments[id] = segment;
    _ffi.middlewareAddMusicSegment(segment);

    notifyListeners();
    return segment;
  }

  /// Update an existing music segment
  void updateMusicSegment(MusicSegment segment) {
    _musicSegments[segment.id] = segment;
    notifyListeners();
  }

  /// Add marker to music segment
  void addMusicMarker(
    int segmentId, {
    required String name,
    required double positionBars,
    required MarkerType markerType,
  }) {
    final segment = _musicSegments[segmentId];
    if (segment == null) return;

    final marker = MusicMarker(
      name: name,
      positionBars: positionBars,
      markerType: markerType,
    );

    final updatedMarkers = List<MusicMarker>.from(segment.markers)..add(marker);
    _musicSegments[segmentId] = segment.copyWith(markers: updatedMarkers);

    _ffi.middlewareMusicSegmentAddMarker(segmentId, marker);
    notifyListeners();
  }

  /// Remove music segment
  void removeMusicSegment(int segmentId) {
    _musicSegments.remove(segmentId);
    _ffi.middlewareRemoveMusicSegment(segmentId);
    notifyListeners();
  }

  /// Get music segment by ID
  MusicSegment? getMusicSegment(int segmentId) => _musicSegments[segmentId];

  /// Import existing music segment (for profile loading)
  void importSegment(MusicSegment segment) {
    _musicSegments[segment.id] = segment;
    if (segment.id >= _nextMusicSegmentIdCounter) {
      _nextMusicSegmentIdCounter = segment.id + 1;
    }
    _ffi.middlewareAddMusicSegment(segment);
    notifyListeners();
  }

  /// Set currently playing music segment
  void setCurrentMusicSegment(int segmentId) {
    _currentMusicSegmentId = segmentId;
    _ffi.middlewareSetMusicSegment(segmentId);
    notifyListeners();
  }

  /// Queue next music segment for seamless transition
  void queueMusicSegment(int segmentId) {
    _nextMusicSegmentId = segmentId;
    _ffi.middlewareQueueMusicSegment(segmentId);
    notifyListeners();
  }

  /// Set music bus ID for routing
  void setMusicBusId(int busId) {
    _musicBusId = busId;
    _ffi.middlewareSetMusicBus(busId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STINGERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new stinger
  Stinger addStinger({
    required String name,
    required int soundId,
    MusicSyncPoint syncPoint = MusicSyncPoint.beat,
    double customGridBeats = 4.0,
    double musicDuckDb = 0.0,
    double duckAttackMs = 10.0,
    double duckReleaseMs = 100.0,
    int priority = 50,
    bool canInterrupt = false,
  }) {
    final id = _nextStingerId++;

    final stinger = Stinger(
      id: id,
      name: name,
      soundId: soundId,
      syncPoint: syncPoint,
      customGridBeats: customGridBeats,
      musicDuckDb: musicDuckDb,
      duckAttackMs: duckAttackMs,
      duckReleaseMs: duckReleaseMs,
      priority: priority,
      canInterrupt: canInterrupt,
    );

    _stingers[id] = stinger;
    _ffi.middlewareAddStinger(stinger);

    notifyListeners();
    return stinger;
  }

  /// Update an existing stinger
  void updateStinger(Stinger stinger) {
    _stingers[stinger.id] = stinger;
    notifyListeners();
  }

  /// Remove stinger
  void removeStinger(int stingerId) {
    _stingers.remove(stingerId);
    _ffi.middlewareRemoveStinger(stingerId);
    notifyListeners();
  }

  /// Get stinger by ID
  Stinger? getStinger(int stingerId) => _stingers[stingerId];

  /// Import existing stinger (for profile loading)
  void importStinger(Stinger stinger) {
    _stingers[stinger.id] = stinger;
    if (stinger.id >= _nextStingerId) {
      _nextStingerId = stinger.id + 1;
    }
    _ffi.middlewareAddStinger(stinger);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export music system state to JSON
  Map<String, dynamic> toJson() {
    return {
      'musicSegments': _musicSegments.values.map((s) => s.toJson()).toList(),
      'stingers': _stingers.values.map((s) => s.toJson()).toList(),
      'currentMusicSegmentId': _currentMusicSegmentId,
      'nextMusicSegmentId': _nextMusicSegmentId,
      'musicBusId': _musicBusId,
    };
  }

  /// Import music system state from JSON
  void fromJson(Map<String, dynamic> json) {
    _musicSegments.clear();
    _stingers.clear();

    if (json['musicSegments'] != null) {
      for (final segmentJson in json['musicSegments'] as List) {
        final segment = MusicSegment.fromJson(segmentJson);
        _musicSegments[segment.id] = segment;
        if (segment.id >= _nextMusicSegmentIdCounter) {
          _nextMusicSegmentIdCounter = segment.id + 1;
        }
      }
    }

    if (json['stingers'] != null) {
      for (final stingerJson in json['stingers'] as List) {
        final stinger = Stinger.fromJson(stingerJson);
        _stingers[stinger.id] = stinger;
        if (stinger.id >= _nextStingerId) {
          _nextStingerId = stinger.id + 1;
        }
      }
    }

    _currentMusicSegmentId = json['currentMusicSegmentId'];
    _nextMusicSegmentId = json['nextMusicSegmentId'];
    _musicBusId = json['musicBusId'] ?? 1;

    notifyListeners();
  }

  /// Clear all music data
  void clear() {
    _musicSegments.clear();
    _stingers.clear();
    _currentMusicSegmentId = null;
    _nextMusicSegmentId = null;
    _musicBusId = 1;
    _nextMusicSegmentIdCounter = 1;
    _nextStingerId = 1;
    _segmentLayers.clear();
    _activeLayers.clear();
    _nextLayerId = 1;
    _transitionRules.clear();
    _musicSwitchContainers.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSITION MATRIX — Source→Destination transition rules (Wwise parity)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Transition rules: key = "sourceId→destId" (or "*→destId" for any-source)
  final Map<String, MusicTransitionRule> _transitionRules = {};

  /// Get all transition rules
  List<MusicTransitionRule> get transitionRules => _transitionRules.values.toList();

  /// Add a transition rule between two segments
  void addTransitionRule(MusicTransitionRule rule) {
    final key = '${rule.sourceSegmentId ?? "*"}→${rule.destSegmentId ?? "*"}';
    _transitionRules[key] = rule;
    notifyListeners();
  }

  /// Remove a transition rule
  void removeTransitionRule(int? sourceId, int? destId) {
    final key = '${sourceId ?? "*"}→${destId ?? "*"}';
    _transitionRules.remove(key);
    notifyListeners();
  }

  /// Get the best transition rule for source→destination.
  /// Priority: exact match > any-source > any-dest > default crossfade
  MusicTransitionRule? getTransitionRule(int? sourceId, int destId) {
    // 1. Exact match
    final exact = _transitionRules['$sourceId→$destId'];
    if (exact != null) return exact;
    // 2. Any source → specific dest
    final anySrc = _transitionRules['*→$destId'];
    if (anySrc != null) return anySrc;
    // 3. Specific source → any dest
    final anyDst = _transitionRules['$sourceId→*'];
    if (anyDst != null) return anyDst;
    // 4. Any → Any (global default)
    return _transitionRules['*→*'];
  }

  /// Transition between music segments using transition matrix rules
  void transitionToSegment(int destSegmentId) {
    final rule = getTransitionRule(_currentMusicSegmentId, destSegmentId);
    if (rule != null) {
      // Use rule-specific timing
      if (rule.bridgeSoundId != null) {
        // Play bridge segment first, then queue destination
        _ffi.middlewareSetMusicSegment(rule.bridgeSoundId!);
        Future.delayed(Duration(milliseconds: rule.bridgeDurationMs), () {
          _ffi.middlewareSetMusicSegment(destSegmentId);
          _currentMusicSegmentId = destSegmentId;
          notifyListeners();
        });
      } else {
        // Direct transition with rule's crossfade
        _ffi.middlewareQueueMusicSegment(destSegmentId);
        _currentMusicSegmentId = destSegmentId;
        notifyListeners();
      }
    } else {
      // No rule — use default queue behavior (single notify)
      _nextMusicSegmentId = destSegmentId;
      _ffi.middlewareQueueMusicSegment(destSegmentId);
      _currentMusicSegmentId = destSegmentId;
      notifyListeners();
    }
  }

  /// Export transition rules to JSON
  List<Map<String, dynamic>> transitionRulesToJson() {
    return _transitionRules.values.map((r) => r.toJson()).toList();
  }

  /// Import transition rules from JSON
  void transitionRulesFromJson(List<dynamic> json) {
    _transitionRules.clear();
    for (final item in json) {
      final rule = MusicTransitionRule.fromJson(item as Map<String, dynamic>);
      final key = '${rule.sourceSegmentId ?? "*"}→${rule.destSegmentId ?? "*"}';
      _transitionRules[key] = rule;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC SWITCH CONTAINER — State/Switch-based music selection (Wwise parity)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Music switch containers: switch group → segment mapping
  final Map<String, MusicSwitchContainer> _musicSwitchContainers = {};

  /// Get all music switch containers
  List<MusicSwitchContainer> get musicSwitchContainers =>
      _musicSwitchContainers.values.toList();

  /// Add a music switch container
  void addMusicSwitchContainer(MusicSwitchContainer container) {
    _musicSwitchContainers[container.id] = container;
    notifyListeners();
  }

  /// Remove a music switch container
  void removeMusicSwitchContainer(String id) {
    _musicSwitchContainers.remove(id);
    notifyListeners();
  }

  /// Get music switch container by ID
  MusicSwitchContainer? getMusicSwitchContainer(String id) =>
      _musicSwitchContainers[id];

  /// Evaluate a music switch container — returns the segment ID to play
  /// based on current switch/state values.
  int? evaluateMusicSwitchContainer(String containerId, {
    required Map<int, int> currentSwitches,
    required Map<int, int> currentStates,
  }) {
    final container = _musicSwitchContainers[containerId];
    if (container == null) return null;

    // Build lookup key from switch/state values
    for (final mapping in container.mappings) {
      bool matches = true;
      for (final condition in mapping.conditions) {
        final currentValue = condition.isState
            ? currentStates[condition.groupId]
            : currentSwitches[condition.groupId];
        if (currentValue != condition.valueId) {
          matches = false;
          break;
        }
      }
      if (matches) return mapping.segmentId;
    }

    return container.defaultSegmentId;
  }

  /// Trigger music switch container — evaluate and transition
  void triggerMusicSwitchContainer(String containerId, {
    required Map<int, int> currentSwitches,
    required Map<int, int> currentStates,
  }) {
    final segmentId = evaluateMusicSwitchContainer(containerId,
        currentSwitches: currentSwitches, currentStates: currentStates);
    if (segmentId != null && segmentId != _currentMusicSegmentId) {
      transitionToSegment(segmentId);
    }
  }

  /// Export music switch containers to JSON
  List<Map<String, dynamic>> musicSwitchContainersToJson() {
    return _musicSwitchContainers.values.map((c) => c.toJson()).toList();
  }

  /// Import music switch containers from JSON
  void musicSwitchContainersFromJson(List<dynamic> json) {
    _musicSwitchContainers.clear();
    for (final item in json) {
      final container = MusicSwitchContainer.fromJson(item as Map<String, dynamic>);
      _musicSwitchContainers[container.id] = container;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // §27 — LAYERED LOOP SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Layer types for stacking (base always plays, others activate dynamically)
  static const List<String> layerTypes = ['base', 'fill', 'transition', 'extended'];

  /// Per-segment loop layers
  final Map<int, List<MusicLoopLayer>> _segmentLayers = {};

  /// Currently active layers per segment
  final Map<int, Set<String>> _activeLayers = {};

  /// Next layer ID
  int _nextLayerId = 1;

  /// Get layers for a segment
  List<MusicLoopLayer> getSegmentLayers(int segmentId) =>
      List.unmodifiable(_segmentLayers[segmentId] ?? []);

  /// Get active layers for a segment
  Set<String> getActiveLayers(int segmentId) =>
      Set.unmodifiable(_activeLayers[segmentId] ?? {'base'});

  /// Add a loop layer to a segment
  MusicLoopLayer addLoopLayer({
    required int segmentId,
    required String name,
    required int soundId,
    required String layerType,
    double fadeInMs = 500.0,
    double fadeOutMs = 500.0,
    double volumeDb = 0.0,
    String? behaviorNodeId,
  }) {
    final layer = MusicLoopLayer(
      id: _nextLayerId++,
      segmentId: segmentId,
      name: name,
      soundId: soundId,
      layerType: layerType,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      volumeDb: volumeDb,
      behaviorNodeId: behaviorNodeId,
    );

    _segmentLayers.putIfAbsent(segmentId, () => []).add(layer);
    notifyListeners();
    return layer;
  }

  /// Remove a loop layer
  void removeLoopLayer(int segmentId, int layerId) {
    _segmentLayers[segmentId]?.removeWhere((l) => l.id == layerId);
    notifyListeners();
  }

  /// Activate a set of layers for a segment (with crossfade)
  void activateLayerSet(int segmentId, Set<String> activeSet) {
    _activeLayers[segmentId] = {'base', ...activeSet};
    notifyListeners();
  }

  /// Activate a single layer
  void activateLayer(int segmentId, String layerType) {
    _activeLayers.putIfAbsent(segmentId, () => {'base'}).add(layerType);
    notifyListeners();
  }

  /// Deactivate a single layer (base cannot be deactivated)
  void deactivateLayer(int segmentId, String layerType) {
    if (layerType == 'base') return;
    _activeLayers[segmentId]?.remove(layerType);
    notifyListeners();
  }

  /// Check if a layer is active
  bool isLayerActive(int segmentId, String layerType) {
    return _activeLayers[segmentId]?.contains(layerType) ?? (layerType == 'base');
  }

  /// Get layers by behavior node ID
  List<MusicLoopLayer> getLayersByBehaviorNode(String behaviorNodeId) {
    final result = <MusicLoopLayer>[];
    for (final layers in _segmentLayers.values) {
      result.addAll(layers.where((l) => l.behaviorNodeId == behaviorNodeId));
    }
    return result;
  }

  /// Layer serialization
  List<Map<String, dynamic>> layersToJson() {
    final result = <Map<String, dynamic>>[];
    for (final entry in _segmentLayers.entries) {
      for (final layer in entry.value) {
        result.add(layer.toJson());
      }
    }
    return result;
  }

  /// Layer deserialization
  void layersFromJson(List<dynamic> json) {
    _segmentLayers.clear();
    for (final item in json) {
      final layer = MusicLoopLayer.fromJson(item as Map<String, dynamic>);
      _segmentLayers.putIfAbsent(layer.segmentId, () => []).add(layer);
      if (layer.id >= _nextLayerId) {
        _nextLayerId = layer.id + 1;
      }
    }
    notifyListeners();
  }
}

/// A loop layer within a music segment (§27)
class MusicLoopLayer {
  final int id;
  final int segmentId;
  final String name;
  final int soundId;
  /// One of: 'base', 'fill', 'transition', 'extended'
  final String layerType;
  final double fadeInMs;
  final double fadeOutMs;
  final double volumeDb;
  /// Behavior node that controls this layer's activation (optional)
  final String? behaviorNodeId;

  const MusicLoopLayer({
    required this.id,
    required this.segmentId,
    required this.name,
    required this.soundId,
    required this.layerType,
    this.fadeInMs = 500.0,
    this.fadeOutMs = 500.0,
    this.volumeDb = 0.0,
    this.behaviorNodeId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'segmentId': segmentId,
    'name': name,
    'soundId': soundId,
    'layerType': layerType,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'volumeDb': volumeDb,
    'behaviorNodeId': behaviorNodeId,
  };

  factory MusicLoopLayer.fromJson(Map<String, dynamic> json) => MusicLoopLayer(
    id: json['id'] as int,
    segmentId: json['segmentId'] as int,
    name: json['name'] as String,
    soundId: json['soundId'] as int,
    layerType: json['layerType'] as String,
    fadeInMs: (json['fadeInMs'] as num?)?.toDouble() ?? 500.0,
    fadeOutMs: (json['fadeOutMs'] as num?)?.toDouble() ?? 500.0,
    volumeDb: (json['volumeDb'] as num?)?.toDouble() ?? 0.0,
    behaviorNodeId: json['behaviorNodeId'] as String?,
  );
}

// =============================================================================
// TRANSITION MATRIX MODEL — Source→Destination transition rules
// =============================================================================

/// A transition rule between two music segments (Wwise Transition Matrix parity).
/// sourceSegmentId/destSegmentId = null means "any" (wildcard).
class MusicTransitionRule {
  final int? sourceSegmentId;
  final int? destSegmentId;
  /// Crossfade duration in ms for this specific transition
  final int crossfadeMs;
  /// Optional bridge segment sound ID (plays between source and dest)
  final int? bridgeSoundId;
  /// Bridge segment duration in ms (how long bridge plays before dest starts)
  final int bridgeDurationMs;
  /// Sync point: when to start the transition (immediate, nextBeat, nextBar, nextMarker)
  final String syncPoint;
  /// Fade-out curve for source ('linear', 'sCurve', 'exponential')
  final String fadeOutCurve;
  /// Fade-in curve for destination
  final String fadeInCurve;

  const MusicTransitionRule({
    this.sourceSegmentId,
    this.destSegmentId,
    this.crossfadeMs = 500,
    this.bridgeSoundId,
    this.bridgeDurationMs = 2000,
    this.syncPoint = 'immediate',
    this.fadeOutCurve = 'linear',
    this.fadeInCurve = 'linear',
  });

  Map<String, dynamic> toJson() => {
    'sourceSegmentId': sourceSegmentId,
    'destSegmentId': destSegmentId,
    'crossfadeMs': crossfadeMs,
    'bridgeSoundId': bridgeSoundId,
    'bridgeDurationMs': bridgeDurationMs,
    'syncPoint': syncPoint,
    'fadeOutCurve': fadeOutCurve,
    'fadeInCurve': fadeInCurve,
  };

  factory MusicTransitionRule.fromJson(Map<String, dynamic> json) =>
      MusicTransitionRule(
        sourceSegmentId: json['sourceSegmentId'] as int?,
        destSegmentId: json['destSegmentId'] as int?,
        crossfadeMs: json['crossfadeMs'] as int? ?? 500,
        bridgeSoundId: json['bridgeSoundId'] as int?,
        bridgeDurationMs: json['bridgeDurationMs'] as int? ?? 2000,
        syncPoint: json['syncPoint'] as String? ?? 'immediate',
        fadeOutCurve: json['fadeOutCurve'] as String? ?? 'linear',
        fadeInCurve: json['fadeInCurve'] as String? ?? 'linear',
      );
}

// =============================================================================
// MUSIC SWITCH CONTAINER MODEL — Switch/State-based music selection
// =============================================================================

/// A music switch container maps switch/state combinations to music segments.
/// When switch values change, the container auto-transitions to the matching segment
/// using the transition matrix rules.
class MusicSwitchContainer {
  final String id;
  final String name;
  /// Ordered list of switch→segment mappings (first match wins)
  final List<MusicSwitchMapping> mappings;
  /// Default segment when no mapping matches
  final int? defaultSegmentId;

  const MusicSwitchContainer({
    required this.id,
    required this.name,
    this.mappings = const [],
    this.defaultSegmentId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mappings': mappings.map((m) => m.toJson()).toList(),
    'defaultSegmentId': defaultSegmentId,
  };

  factory MusicSwitchContainer.fromJson(Map<String, dynamic> json) =>
      MusicSwitchContainer(
        id: json['id'] as String,
        name: json['name'] as String,
        mappings: (json['mappings'] as List?)
            ?.map((m) => MusicSwitchMapping.fromJson(m as Map<String, dynamic>))
            .toList() ?? [],
        defaultSegmentId: json['defaultSegmentId'] as int?,
      );
}

/// A mapping entry: conditions → segment
class MusicSwitchMapping {
  final List<SwitchCondition> conditions;
  final int segmentId;

  const MusicSwitchMapping({
    required this.conditions,
    required this.segmentId,
  });

  Map<String, dynamic> toJson() => {
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'segmentId': segmentId,
  };

  factory MusicSwitchMapping.fromJson(Map<String, dynamic> json) =>
      MusicSwitchMapping(
        conditions: (json['conditions'] as List)
            .map((c) => SwitchCondition.fromJson(c as Map<String, dynamic>))
            .toList(),
        segmentId: json['segmentId'] as int,
      );
}

/// A single condition in a music switch mapping
class SwitchCondition {
  /// Switch or State group ID
  final int groupId;
  /// Expected switch/state value ID
  final int valueId;
  /// true = state group, false = switch group
  final bool isState;

  const SwitchCondition({
    required this.groupId,
    required this.valueId,
    this.isState = false,
  });

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'valueId': valueId,
    'isState': isState,
  };

  factory SwitchCondition.fromJson(Map<String, dynamic> json) =>
      SwitchCondition(
        groupId: json['groupId'] as int,
        valueId: json['valueId'] as int,
        isState: json['isState'] as bool? ?? false,
      );
}

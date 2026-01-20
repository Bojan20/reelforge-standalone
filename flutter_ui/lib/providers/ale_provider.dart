/// ALE Provider — Adaptive Layer Engine State Management
///
/// Provides Flutter state management for the rf-ale Rust engine.
/// Handles signal updates, context transitions, and layer control.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Normalization mode for signals
enum NormalizationMode {
  linear,
  sigmoid,
  asymptotic,
  none,
}

/// Signal definition
class AleSignalDefinition {
  final String id;
  final String name;
  final double minValue;
  final double maxValue;
  final double defaultValue;
  final NormalizationMode normalization;
  final double? sigmoidK;
  final double? asymptoticMax;
  final bool isDerived;

  const AleSignalDefinition({
    required this.id,
    required this.name,
    this.minValue = 0.0,
    this.maxValue = 1.0,
    this.defaultValue = 0.0,
    this.normalization = NormalizationMode.linear,
    this.sigmoidK,
    this.asymptoticMax,
    this.isDerived = false,
  });

  factory AleSignalDefinition.fromJson(Map<String, dynamic> json) {
    return AleSignalDefinition(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      minValue: (json['min_value'] as num?)?.toDouble() ?? 0.0,
      maxValue: (json['max_value'] as num?)?.toDouble() ?? 1.0,
      defaultValue: (json['default_value'] as num?)?.toDouble() ?? 0.0,
      normalization: _parseNormalization(json['normalization']),
      sigmoidK: (json['sigmoid_k'] as num?)?.toDouble(),
      asymptoticMax: (json['asymptotic_max'] as num?)?.toDouble(),
      isDerived: json['is_derived'] as bool? ?? false,
    );
  }

  static NormalizationMode _parseNormalization(dynamic value) {
    if (value == null) return NormalizationMode.linear;
    final str = value.toString().toLowerCase();
    return switch (str) {
      'sigmoid' => NormalizationMode.sigmoid,
      'asymptotic' => NormalizationMode.asymptotic,
      'none' => NormalizationMode.none,
      _ => NormalizationMode.linear,
    };
  }
}

/// Audio layer in a context
class AleLayer {
  final int index;
  final String assetId;
  final double baseVolume;
  final double currentVolume;
  final bool isActive;

  const AleLayer({
    required this.index,
    required this.assetId,
    this.baseVolume = 1.0,
    this.currentVolume = 0.0,
    this.isActive = false,
  });

  factory AleLayer.fromJson(Map<String, dynamic> json) {
    return AleLayer(
      index: json['index'] as int,
      assetId: json['asset_id'] as String,
      baseVolume: (json['base_volume'] as num?)?.toDouble() ?? 1.0,
      currentVolume: (json['current_volume'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}

/// Context definition
class AleContext {
  final String id;
  final String name;
  final String? description;
  final List<AleLayer> layers;
  final int currentLevel;
  final bool isActive;

  const AleContext({
    required this.id,
    required this.name,
    this.description,
    this.layers = const [],
    this.currentLevel = 0,
    this.isActive = false,
  });

  factory AleContext.fromJson(Map<String, dynamic> json) {
    final layersJson = json['layers'] as List<dynamic>? ?? [];
    return AleContext(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      description: json['description'] as String?,
      layers: layersJson.map((l) => AleLayer.fromJson(l as Map<String, dynamic>)).toList(),
      currentLevel: json['current_level'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}

/// Rule condition comparison operator
enum ComparisonOp {
  eq, ne, lt, lte, gt, gte,
  inRange, outOfRange,
  rising, falling, crossed,
  aboveFor, belowFor,
  changed, stable,
}

/// Rule action type
enum ActionType {
  stepUp,
  stepDown,
  setLevel,
  hold,
  release,
  pulse,
}

/// Rule definition
class AleRule {
  final String id;
  final String name;
  final String? signalId;
  final ComparisonOp? op;
  final double? value;
  final ActionType action;
  final int? actionValue;
  final List<String> contexts;
  final int priority;
  final bool enabled;

  const AleRule({
    required this.id,
    required this.name,
    this.signalId,
    this.op,
    this.value,
    this.action = ActionType.stepUp,
    this.actionValue,
    this.contexts = const [],
    this.priority = 0,
    this.enabled = true,
  });

  factory AleRule.fromJson(Map<String, dynamic> json) {
    return AleRule(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      signalId: json['signal_id'] as String?,
      op: _parseOp(json['op']),
      value: (json['value'] as num?)?.toDouble(),
      action: _parseAction(json['action']),
      actionValue: json['action_value'] as int?,
      contexts: (json['contexts'] as List<dynamic>?)?.map((c) => c.toString()).toList() ?? [],
      priority: json['priority'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  static ComparisonOp? _parseOp(dynamic value) {
    if (value == null) return null;
    final str = value.toString().toLowerCase();
    return switch (str) {
      'eq' || '==' => ComparisonOp.eq,
      'ne' || '!=' => ComparisonOp.ne,
      'lt' || '<' => ComparisonOp.lt,
      'lte' || '<=' => ComparisonOp.lte,
      'gt' || '>' => ComparisonOp.gt,
      'gte' || '>=' => ComparisonOp.gte,
      'in_range' => ComparisonOp.inRange,
      'out_of_range' => ComparisonOp.outOfRange,
      'rising' => ComparisonOp.rising,
      'falling' => ComparisonOp.falling,
      'crossed' => ComparisonOp.crossed,
      'above_for' => ComparisonOp.aboveFor,
      'below_for' => ComparisonOp.belowFor,
      'changed' => ComparisonOp.changed,
      'stable' => ComparisonOp.stable,
      _ => null,
    };
  }

  static ActionType _parseAction(dynamic value) {
    if (value == null) return ActionType.stepUp;
    final str = value.toString().toLowerCase();
    return switch (str) {
      'step_up' => ActionType.stepUp,
      'step_down' => ActionType.stepDown,
      'set_level' => ActionType.setLevel,
      'hold' => ActionType.hold,
      'release' => ActionType.release,
      'pulse' => ActionType.pulse,
      _ => ActionType.stepUp,
    };
  }
}

/// Transition sync mode
enum SyncMode {
  immediate,
  beat,
  bar,
  phrase,
  nextDownbeat,
  custom,
}

/// Transition profile
class AleTransitionProfile {
  final String id;
  final String name;
  final SyncMode syncMode;
  final int fadeInMs;
  final int fadeOutMs;
  final double overlap;

  const AleTransitionProfile({
    required this.id,
    required this.name,
    this.syncMode = SyncMode.immediate,
    this.fadeInMs = 500,
    this.fadeOutMs = 500,
    this.overlap = 0.5,
  });

  factory AleTransitionProfile.fromJson(Map<String, dynamic> json) {
    return AleTransitionProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      syncMode: _parseSyncMode(json['sync_mode']),
      fadeInMs: json['fade_in_ms'] as int? ?? 500,
      fadeOutMs: json['fade_out_ms'] as int? ?? 500,
      overlap: (json['overlap'] as num?)?.toDouble() ?? 0.5,
    );
  }

  static SyncMode _parseSyncMode(dynamic value) {
    if (value == null) return SyncMode.immediate;
    final str = value.toString().toLowerCase();
    return switch (str) {
      'beat' => SyncMode.beat,
      'bar' => SyncMode.bar,
      'phrase' => SyncMode.phrase,
      'next_downbeat' => SyncMode.nextDownbeat,
      'custom' => SyncMode.custom,
      _ => SyncMode.immediate,
    };
  }
}

/// Stability configuration
class AleStabilityConfig {
  final int cooldownMs;
  final int holdMs;
  final double hysteresisUp;
  final double hysteresisDown;
  final double levelInertia;
  final int decayMs;
  final double decayRate;
  final int momentumWindow;
  final bool predictionEnabled;

  const AleStabilityConfig({
    this.cooldownMs = 500,
    this.holdMs = 2000,
    this.hysteresisUp = 0.1,
    this.hysteresisDown = 0.05,
    this.levelInertia = 0.3,
    this.decayMs = 10000,
    this.decayRate = 0.1,
    this.momentumWindow = 5000,
    this.predictionEnabled = false,
  });

  factory AleStabilityConfig.fromJson(Map<String, dynamic> json) {
    return AleStabilityConfig(
      cooldownMs: json['cooldown_ms'] as int? ?? 500,
      holdMs: json['hold_ms'] as int? ?? 2000,
      hysteresisUp: (json['hysteresis_up'] as num?)?.toDouble() ?? 0.1,
      hysteresisDown: (json['hysteresis_down'] as num?)?.toDouble() ?? 0.05,
      levelInertia: (json['level_inertia'] as num?)?.toDouble() ?? 0.3,
      decayMs: json['decay_ms'] as int? ?? 10000,
      decayRate: (json['decay_rate'] as num?)?.toDouble() ?? 0.1,
      momentumWindow: json['momentum_window'] as int? ?? 5000,
      predictionEnabled: json['prediction_enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'cooldown_ms': cooldownMs,
    'hold_ms': holdMs,
    'hysteresis_up': hysteresisUp,
    'hysteresis_down': hysteresisDown,
    'level_inertia': levelInertia,
    'decay_ms': decayMs,
    'decay_rate': decayRate,
    'momentum_window': momentumWindow,
    'prediction_enabled': predictionEnabled,
  };
}

/// Complete ALE profile
class AleProfile {
  final String version;
  final String? author;
  final String? gameName;
  final Map<String, AleContext> contexts;
  final List<AleRule> rules;
  final Map<String, AleTransitionProfile> transitions;
  final AleStabilityConfig stability;

  const AleProfile({
    this.version = '2.0',
    this.author,
    this.gameName,
    this.contexts = const {},
    this.rules = const [],
    this.transitions = const {},
    this.stability = const AleStabilityConfig(),
  });

  factory AleProfile.fromJson(Map<String, dynamic> json) {
    final contextsJson = json['contexts'] as Map<String, dynamic>? ?? {};
    final rulesJson = json['rules'] as List<dynamic>? ?? [];
    final transitionsJson = json['transitions'] as Map<String, dynamic>? ?? {};
    final stabilityJson = json['stability'] as Map<String, dynamic>?;

    return AleProfile(
      version: json['version'] as String? ?? '2.0',
      author: json['author'] as String?,
      gameName: json['metadata']?['game_name'] as String?,
      contexts: contextsJson.map((k, v) => MapEntry(k, AleContext.fromJson(v as Map<String, dynamic>))),
      rules: rulesJson.map((r) => AleRule.fromJson(r as Map<String, dynamic>)).toList(),
      transitions: transitionsJson.map((k, v) => MapEntry(k, AleTransitionProfile.fromJson(v as Map<String, dynamic>))),
      stability: stabilityJson != null ? AleStabilityConfig.fromJson(stabilityJson) : const AleStabilityConfig(),
    );
  }
}

/// Engine state snapshot
class AleEngineState {
  final String? activeContextId;
  final int currentLevel;
  final List<double> layerVolumes;
  final Map<String, double> signalValues;
  final bool inTransition;
  final double tempo;
  final int beatsPerBar;

  const AleEngineState({
    this.activeContextId,
    this.currentLevel = 0,
    this.layerVolumes = const [],
    this.signalValues = const {},
    this.inTransition = false,
    this.tempo = 120.0,
    this.beatsPerBar = 4,
  });

  factory AleEngineState.fromJson(Map<String, dynamic> json) {
    final volumesJson = json['layer_volumes'] as List<dynamic>? ?? [];
    final signalsJson = json['signal_values'] as Map<String, dynamic>? ?? {};

    return AleEngineState(
      activeContextId: json['active_context_id'] as String?,
      currentLevel: json['current_level'] as int? ?? 0,
      layerVolumes: volumesJson.map((v) => (v as num).toDouble()).toList(),
      signalValues: signalsJson.map((k, v) => MapEntry(k, (v as num).toDouble())),
      inTransition: json['in_transition'] as bool? ?? false,
      tempo: (json['tempo'] as num?)?.toDouble() ?? 120.0,
      beatsPerBar: json['beats_per_bar'] as int? ?? 4,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ALE PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for Adaptive Layer Engine state management
class AleProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // ─── State ────────────────────────────────────────────────────────────────
  bool _initialized = false;
  AleProfile? _profile;
  AleEngineState _state = const AleEngineState();
  Map<String, double> _currentSignals = {};
  Timer? _tickTimer;
  int _tickIntervalMs = 16; // ~60fps

  // ─── Getters ──────────────────────────────────────────────────────────────
  bool get initialized => _initialized;
  AleProfile? get profile => _profile;
  AleEngineState get state => _state;
  Map<String, double> get currentSignals => Map.unmodifiable(_currentSignals);

  /// Current active context
  AleContext? get activeContext {
    if (_state.activeContextId == null || _profile == null) return null;
    return _profile!.contexts[_state.activeContextId];
  }

  /// Current layer count in active context
  int get layerCount => activeContext?.layers.length ?? 0;

  /// Current level (0-based)
  int get currentLevel => _state.currentLevel;

  /// Max level for active context
  int get maxLevel => layerCount > 0 ? layerCount - 1 : 0;

  /// Layer volumes for mixing
  List<double> get layerVolumes => _state.layerVolumes;

  /// Check if in transition
  bool get inTransition => _state.inTransition;

  /// Tempo (BPM)
  double get tempo => _state.tempo;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize ALE engine
  bool initialize() {
    if (_initialized) {
      debugPrint('[AleProvider] Already initialized');
      return true;
    }

    final success = _ffi.aleInit();
    if (success) {
      _initialized = true;
      _refreshState();
      debugPrint('[AleProvider] Engine initialized');
      notifyListeners();
    } else {
      debugPrint('[AleProvider] Failed to initialize engine');
    }

    return success;
  }

  /// Shutdown ALE engine
  void shutdown() {
    if (!_initialized) return;

    _tickTimer?.cancel();
    _tickTimer = null;
    _ffi.aleShutdown();
    _initialized = false;
    _profile = null;
    _state = const AleEngineState();
    _currentSignals = {};
    debugPrint('[AleProvider] Engine shutdown');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROFILE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load profile from JSON string
  bool loadProfile(String json) {
    if (!_initialized) return false;

    final success = _ffi.aleLoadProfile(json);
    if (success) {
      // Parse profile locally for UI
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _profile = AleProfile.fromJson(data);
        _refreshState();
        debugPrint('[AleProvider] Profile loaded: ${_profile?.gameName ?? "unnamed"}');
        notifyListeners();
      } catch (e) {
        debugPrint('[AleProvider] Failed to parse profile: $e');
        return false;
      }
    }

    return success;
  }

  /// Export current profile as JSON
  String? exportProfile() {
    if (!_initialized) return null;
    return _ffi.aleExportProfile();
  }

  /// Create a new empty profile
  bool createNewProfile({String? gameName, String? author}) {
    if (!_initialized) return false;

    final profile = {
      'version': '2.0',
      'format': 'ale_profile',
      'author': author ?? '',
      'metadata': {
        'game_name': gameName ?? 'New Game',
        'game_id': '',
        'target_platforms': ['desktop', 'mobile'],
        'audio_budget_mb': 150,
      },
      'contexts': <String, dynamic>{},
      'rules': <dynamic>[],
      'transitions': <String, dynamic>{},
      'stability': const AleStabilityConfig().toJson(),
    };

    return loadProfile(jsonEncode(profile));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTEXT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enter a context
  bool enterContext(String contextId, {String? transitionId}) {
    if (!_initialized) return false;

    final success = _ffi.aleEnterContext(contextId, transitionId);
    if (success) {
      _refreshState();
      debugPrint('[AleProvider] Entered context: $contextId');
      notifyListeners();
    }

    return success;
  }

  /// Exit current context
  bool exitContext({String? transitionId}) {
    if (!_initialized) return false;

    final success = _ffi.aleExitContext(transitionId);
    if (success) {
      _refreshState();
      debugPrint('[AleProvider] Exited context');
      notifyListeners();
    }

    return success;
  }

  /// Get all context IDs
  List<String> get contextIds {
    return _profile?.contexts.keys.toList() ?? [];
  }

  /// Get context by ID
  AleContext? getContext(String id) {
    return _profile?.contexts[id];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIGNAL MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update a signal value
  void updateSignal(String signalId, double value) {
    if (!_initialized) return;

    _ffi.aleUpdateSignal(signalId, value);
    _currentSignals[signalId] = value;
    // Note: Don't notify here, let tick() handle state updates
  }

  /// Update multiple signals at once
  void updateSignals(Map<String, double> signals) {
    if (!_initialized) return;

    for (final entry in signals.entries) {
      _ffi.aleUpdateSignal(entry.key, entry.value);
      _currentSignals[entry.key] = entry.value;
    }
  }

  /// Get current value of a signal
  double getSignalValue(String signalId) {
    return _currentSignals[signalId] ?? 0.0;
  }

  /// Get normalized signal value (0.0-1.0)
  double getSignalNormalized(String signalId) {
    if (!_initialized) return 0.0;
    return _ffi.aleGetSignalNormalized(signalId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEVEL CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Manually set level
  bool setLevel(int level) {
    if (!_initialized) return false;

    final success = _ffi.aleSetLevel(level);
    if (success) {
      _refreshState();
      notifyListeners();
    }

    return success;
  }

  /// Step up one level
  bool stepUp() {
    if (!_initialized) return false;

    final success = _ffi.aleStepUp();
    if (success) {
      _refreshState();
      notifyListeners();
    }

    return success;
  }

  /// Step down one level
  bool stepDown() {
    if (!_initialized) return false;

    final success = _ffi.aleStepDown();
    if (success) {
      _refreshState();
      notifyListeners();
    }

    return success;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPO & SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set tempo (BPM)
  void setTempo(double bpm) {
    if (!_initialized) return;
    _ffi.aleSetTempo(bpm);
    _refreshState();
    notifyListeners();
  }

  /// Set time signature
  void setTimeSignature(int numerator, int denominator) {
    if (!_initialized) return;
    _ffi.aleSetTimeSignature(numerator, denominator);
    _refreshState();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TICK / UPDATE LOOP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start automatic tick loop
  void startTickLoop({int intervalMs = 16}) {
    _tickIntervalMs = intervalMs;
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      tick();
    });
    debugPrint('[AleProvider] Tick loop started (${intervalMs}ms)');
  }

  /// Stop automatic tick loop
  void stopTickLoop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    debugPrint('[AleProvider] Tick loop stopped');
  }

  /// Manual tick - call this from audio callback or timer
  void tick() {
    if (!_initialized) return;

    _ffi.aleTick();
    _refreshState();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  void _refreshState() {
    if (!_initialized) return;

    final stateJson = _ffi.aleGetState();
    if (stateJson != null) {
      try {
        final data = jsonDecode(stateJson) as Map<String, dynamic>;
        _state = AleEngineState.fromJson(data);
      } catch (e) {
        debugPrint('[AleProvider] Failed to parse state: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _tickTimer?.cancel();
    shutdown();
    super.dispose();
  }
}

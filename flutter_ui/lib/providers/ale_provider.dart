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

  // P1.2 SECURITY: Allowed audio extensions
  static const _allowedAudioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

  /// P1.2 SECURITY: Validate asset path for security
  static bool _validateAssetPath(String path) {
    if (path.isEmpty) return true; // Empty allowed (placeholder)
    if (path.contains('..')) {
      return false;
    }
    if (path.contains('\x00')) {
      return false;
    }
    final lowerPath = path.toLowerCase();
    final hasValidExt = _allowedAudioExtensions.any((ext) => lowerPath.endsWith(ext));
    if (!hasValidExt && path.isNotEmpty) {
      return false;
    }
    return true;
  }

  factory AleLayer.fromJson(Map<String, dynamic> json) {
    final assetId = json['asset_id'] as String? ?? '';

    // P1.2 SECURITY: Validate asset path
    if (!_validateAssetPath(assetId)) {
      return AleLayer(
        index: json['index'] as int? ?? 0,
        assetId: '', // Sanitized
        baseVolume: (json['base_volume'] as num?)?.toDouble() ?? 1.0,
        currentVolume: 0.0,
        isActive: false,
      );
    }

    return AleLayer(
      index: json['index'] as int? ?? 0,
      assetId: assetId,
      baseVolume: (json['base_volume'] as num?)?.toDouble() ?? 1.0,
      currentVolume: (json['current_volume'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'asset_id': assetId,
    'base_volume': baseVolume,
    'current_volume': currentVolume,
    'is_active': isActive,
  };
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'layers': layers.map((l) => l.toJson()).toList(),
    'current_level': currentLevel,
    'is_active': isActive,
  };
}

/// Rule condition comparison operator
enum ComparisonOp {
  eq, ne, lt, lte, gt, gte,
  inRange, outOfRange,
  rising, falling, crossed,
  aboveFor, belowFor,
  changed, stable,
}

/// Rule action type (prefixed to avoid conflict with middleware ActionType)
enum AleActionType {
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
  final AleActionType action;
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
    this.action = AleActionType.stepUp,
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

  static AleActionType _parseAction(dynamic value) {
    if (value == null) return AleActionType.stepUp;
    final str = value.toString().toLowerCase();
    return switch (str) {
      'step_up' => AleActionType.stepUp,
      'step_down' => AleActionType.stepDown,
      'set_level' => AleActionType.setLevel,
      'hold' => AleActionType.hold,
      'release' => AleActionType.release,
      'pulse' => AleActionType.pulse,
      _ => AleActionType.stepUp,
    };
  }

  static String _opToString(ComparisonOp? op) {
    if (op == null) return 'eq';
    return switch (op) {
      ComparisonOp.eq => 'eq',
      ComparisonOp.ne => 'ne',
      ComparisonOp.lt => 'lt',
      ComparisonOp.lte => 'lte',
      ComparisonOp.gt => 'gt',
      ComparisonOp.gte => 'gte',
      ComparisonOp.inRange => 'in_range',
      ComparisonOp.outOfRange => 'out_of_range',
      ComparisonOp.rising => 'rising',
      ComparisonOp.falling => 'falling',
      ComparisonOp.crossed => 'crossed',
      ComparisonOp.aboveFor => 'above_for',
      ComparisonOp.belowFor => 'below_for',
      ComparisonOp.changed => 'changed',
      ComparisonOp.stable => 'stable',
    };
  }

  static String _actionToString(AleActionType action) {
    return switch (action) {
      AleActionType.stepUp => 'step_up',
      AleActionType.stepDown => 'step_down',
      AleActionType.setLevel => 'set_level',
      AleActionType.hold => 'hold',
      AleActionType.release => 'release',
      AleActionType.pulse => 'pulse',
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (signalId != null) 'signal_id': signalId,
    if (op != null) 'op': _opToString(op),
    if (value != null) 'value': value,
    'action': _actionToString(action),
    if (actionValue != null) 'action_value': actionValue,
    'contexts': contexts,
    'priority': priority,
    'enabled': enabled,
  };
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

  static String _syncModeToString(SyncMode mode) {
    return switch (mode) {
      SyncMode.immediate => 'immediate',
      SyncMode.beat => 'beat',
      SyncMode.bar => 'bar',
      SyncMode.phrase => 'phrase',
      SyncMode.nextDownbeat => 'next_downbeat',
      SyncMode.custom => 'custom',
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sync_mode': _syncModeToString(syncMode),
    'fade_in_ms': fadeInMs,
    'fade_out_ms': fadeOutMs,
    'overlap': overlap,
  };
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

  /// Create a copy with updated values
  AleStabilityConfig copyWith({
    int? cooldownMs,
    int? holdMs,
    double? hysteresisUp,
    double? hysteresisDown,
    double? levelInertia,
    int? decayMs,
    double? decayRate,
    int? momentumWindow,
    bool? predictionEnabled,
  }) {
    return AleStabilityConfig(
      cooldownMs: cooldownMs ?? this.cooldownMs,
      holdMs: holdMs ?? this.holdMs,
      hysteresisUp: hysteresisUp ?? this.hysteresisUp,
      hysteresisDown: hysteresisDown ?? this.hysteresisDown,
      levelInertia: levelInertia ?? this.levelInertia,
      decayMs: decayMs ?? this.decayMs,
      decayRate: decayRate ?? this.decayRate,
      momentumWindow: momentumWindow ?? this.momentumWindow,
      predictionEnabled: predictionEnabled ?? this.predictionEnabled,
    );
  }
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

  Map<String, dynamic> toJson() => {
    'version': version,
    if (author != null) 'author': author,
    if (gameName != null) 'metadata': {'game_name': gameName},
    'contexts': contexts.map((k, v) => MapEntry(k, v.toJson())),
    'rules': rules.map((r) => r.toJson()).toList(),
    'transitions': transitions.map((k, v) => MapEntry(k, v.toJson())),
    'stability': stability.toJson(),
  };
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
  String? _lastStateJson; // P1.1: Cache for state diff check

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
      return true;
    }

    final success = _ffi.aleInit();
    if (success) {
      _initialized = true;
      _refreshState();
      notifyListeners();
    } else {
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
        notifyListeners();
      } catch (e) {
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

  /// Valid level range (L1-L5 maps to 0-4)
  static const int kMinLevel = 0;
  static const int kMaxLevel = 4;

  /// Manually set level (P2 FIX: clamped to valid range 0-4)
  bool setLevel(int level) {
    if (!_initialized) return false;

    // P2.1 FIX: Clamp level to valid range to prevent invalid state
    final clampedLevel = level.clamp(kMinLevel, kMaxLevel);
    if (clampedLevel != level) {
    }

    final success = _ffi.aleSetLevel(clampedLevel);
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
  // STABILITY MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update stability configuration
  ///
  /// Syncs the new config to the Rust engine via FFI and updates the local profile.
  bool updateStability(AleStabilityConfig config) {
    if (!_initialized) return false;

    // Sync to Rust via FFI
    final success = _ffi.aleSetStabilityJson(config.toJson());
    if (success) {
      // Update local profile
      if (_profile != null) {
        _profile = AleProfile(
          version: _profile!.version,
          author: _profile!.author,
          gameName: _profile!.gameName,
          contexts: _profile!.contexts,
          rules: _profile!.rules,
          transitions: _profile!.transitions,
          stability: config,
        );
      }
      notifyListeners();
    } else {
    }

    return success;
  }

  /// Get current stability configuration
  AleStabilityConfig get stability {
    return _profile?.stability ?? const AleStabilityConfig();
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
  }

  /// Stop automatic tick loop
  void stopTickLoop() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Manual tick - call this from audio callback or timer
  void tick() {
    if (!_initialized) return;

    _ffi.aleTick();
    // P1.1 FIX: Only notify if state actually changed
    final stateChanged = _refreshStateAndCheckChange();
    if (stateChanged) {
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.1 FIX: Refresh state and return true if it changed
  bool _refreshStateAndCheckChange() {
    if (!_initialized) return false;

    final stateJson = _ffi.aleGetState();
    if (stateJson == null) return false;

    // P1.1: Skip parsing if JSON unchanged (60fps optimization)
    if (stateJson == _lastStateJson) return false;
    _lastStateJson = stateJson;

    try {
      final data = jsonDecode(stateJson) as Map<String, dynamic>;
      _state = AleEngineState.fromJson(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _refreshState() {
    _refreshStateAndCheckChange();
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

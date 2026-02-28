/// Context Layer Provider — SlotLab Middleware §21
///
/// Per-node parameter overrides for different game modes.
/// Game modes: BASE, FREESPINS, BONUS, JACKPOT, GAMBLE, FEATURE.
/// Each node can have different gain, priority, playback mode, etc.
/// per game mode. Null values = inherit from default.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §21

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';

/// Game modes for context overrides
enum GameMode {
  base,
  freeSpins,
  bonus,
  jackpot,
  gamble,
  feature,
}

extension GameModeExtension on GameMode {
  String get displayName {
    switch (this) {
      case GameMode.base: return 'Base';
      case GameMode.freeSpins: return 'Free Spins';
      case GameMode.bonus: return 'Bonus';
      case GameMode.jackpot: return 'Jackpot';
      case GameMode.gamble: return 'Gamble';
      case GameMode.feature: return 'Feature';
    }
  }

  String get shortLabel {
    switch (this) {
      case GameMode.base: return 'BSE';
      case GameMode.freeSpins: return 'FS';
      case GameMode.bonus: return 'BNS';
      case GameMode.jackpot: return 'JP';
      case GameMode.gamble: return 'GMB';
      case GameMode.feature: return 'FTR';
    }
  }
}

/// Parameter overrides for a specific node in a specific game mode
class ContextOverrideSet {
  final String behaviorNodeId;
  final GameMode gameMode;

  /// Gain override in dB (null = inherit)
  final double? gainDb;
  /// Priority override (null = inherit)
  final int? priority;
  /// Playback mode override (null = inherit)
  final PlaybackMode? playbackMode;
  /// Bus route override (null = inherit)
  final String? busRoute;
  /// Whether the node is active in this mode (null = inherit, true by default)
  final bool? active;
  /// Emotional weight override (null = inherit)
  final double? emotionalWeight;
  /// Stereo width override (null = inherit)
  final double? stereoWidth;
  /// Fade in ms override (null = inherit)
  final int? fadeInMs;
  /// Fade out ms override (null = inherit)
  final int? fadeOutMs;

  const ContextOverrideSet({
    required this.behaviorNodeId,
    required this.gameMode,
    this.gainDb,
    this.priority,
    this.playbackMode,
    this.busRoute,
    this.active,
    this.emotionalWeight,
    this.stereoWidth,
    this.fadeInMs,
    this.fadeOutMs,
  });

  /// Check if any override is set
  bool get hasOverrides =>
      gainDb != null || priority != null || playbackMode != null ||
      busRoute != null || active != null || emotionalWeight != null ||
      stereoWidth != null || fadeInMs != null || fadeOutMs != null;

  /// Count of set overrides
  int get overrideCount {
    int count = 0;
    if (gainDb != null) count++;
    if (priority != null) count++;
    if (playbackMode != null) count++;
    if (busRoute != null) count++;
    if (active != null) count++;
    if (emotionalWeight != null) count++;
    if (stereoWidth != null) count++;
    if (fadeInMs != null) count++;
    if (fadeOutMs != null) count++;
    return count;
  }

  ContextOverrideSet copyWith({
    double? gainDb,
    int? priority,
    PlaybackMode? playbackMode,
    String? busRoute,
    bool? active,
    double? emotionalWeight,
    double? stereoWidth,
    int? fadeInMs,
    int? fadeOutMs,
    bool clearGainDb = false,
    bool clearPriority = false,
    bool clearPlaybackMode = false,
    bool clearBusRoute = false,
    bool clearActive = false,
    bool clearEmotionalWeight = false,
    bool clearStereoWidth = false,
    bool clearFadeInMs = false,
    bool clearFadeOutMs = false,
  }) => ContextOverrideSet(
    behaviorNodeId: behaviorNodeId,
    gameMode: gameMode,
    gainDb: clearGainDb ? null : (gainDb ?? this.gainDb),
    priority: clearPriority ? null : (priority ?? this.priority),
    playbackMode: clearPlaybackMode ? null : (playbackMode ?? this.playbackMode),
    busRoute: clearBusRoute ? null : (busRoute ?? this.busRoute),
    active: clearActive ? null : (active ?? this.active),
    emotionalWeight: clearEmotionalWeight ? null : (emotionalWeight ?? this.emotionalWeight),
    stereoWidth: clearStereoWidth ? null : (stereoWidth ?? this.stereoWidth),
    fadeInMs: clearFadeInMs ? null : (fadeInMs ?? this.fadeInMs),
    fadeOutMs: clearFadeOutMs ? null : (fadeOutMs ?? this.fadeOutMs),
  );

  Map<String, dynamic> toJson() => {
    'behaviorNodeId': behaviorNodeId,
    'gameMode': gameMode.name,
    'gainDb': gainDb,
    'priority': priority,
    'playbackMode': playbackMode?.name,
    'busRoute': busRoute,
    'active': active,
    'emotionalWeight': emotionalWeight,
    'stereoWidth': stereoWidth,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
  };

  factory ContextOverrideSet.fromJson(Map<String, dynamic> json) =>
      ContextOverrideSet(
        behaviorNodeId: json['behaviorNodeId'] as String,
        gameMode: GameMode.values.byName(json['gameMode'] as String),
        gainDb: (json['gainDb'] as num?)?.toDouble(),
        priority: json['priority'] as int?,
        playbackMode: json['playbackMode'] != null
            ? PlaybackMode.values.byName(json['playbackMode'] as String)
            : null,
        busRoute: json['busRoute'] as String?,
        active: json['active'] as bool?,
        emotionalWeight: (json['emotionalWeight'] as num?)?.toDouble(),
        stereoWidth: (json['stereoWidth'] as num?)?.toDouble(),
        fadeInMs: json['fadeInMs'] as int?,
        fadeOutMs: json['fadeOutMs'] as int?,
      );
}

class ContextLayerProvider extends ChangeNotifier {
  /// Current active game mode
  GameMode _currentMode = GameMode.base;

  /// All override sets: key = "$behaviorNodeId::$gameModeName"
  final Map<String, ContextOverrideSet> _overrides = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  GameMode get currentMode => _currentMode;

  /// Get override set for a node in a specific mode
  ContextOverrideSet? getOverride(String nodeId, GameMode mode) =>
      _overrides['$nodeId::${mode.name}'];

  /// Get override set for a node in current mode
  ContextOverrideSet? getCurrentOverride(String nodeId) =>
      getOverride(nodeId, _currentMode);

  /// Get all overrides for a node (all modes)
  Map<GameMode, ContextOverrideSet> getNodeOverrides(String nodeId) {
    final result = <GameMode, ContextOverrideSet>{};
    for (final mode in GameMode.values) {
      final override = getOverride(nodeId, mode);
      if (override != null && override.hasOverrides) {
        result[mode] = override;
      }
    }
    return result;
  }

  /// Check if a node has any overrides
  bool hasOverrides(String nodeId) {
    for (final mode in GameMode.values) {
      final override = getOverride(nodeId, mode);
      if (override != null && override.hasOverrides) return true;
    }
    return false;
  }

  /// Get total override count for a node
  int getOverrideCount(String nodeId) {
    int count = 0;
    for (final mode in GameMode.values) {
      final override = getOverride(nodeId, mode);
      if (override != null) count += override.overrideCount;
    }
    return count;
  }

  /// Check if a node is active in current mode
  bool isNodeActive(String nodeId) {
    final override = getCurrentOverride(nodeId);
    return override?.active ?? true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE SWITCHING
  // ═══════════════════════════════════════════════════════════════════════════

  void setCurrentMode(GameMode mode) {
    if (_currentMode == mode) return;
    _currentMode = mode;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OVERRIDE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set or update an override
  void setOverride(ContextOverrideSet override) {
    final key = '${override.behaviorNodeId}::${override.gameMode.name}';
    _overrides[key] = override;
    notifyListeners();
  }

  /// Remove override for a node in a specific mode
  void removeOverride(String nodeId, GameMode mode) {
    _overrides.remove('$nodeId::${mode.name}');
    notifyListeners();
  }

  /// Remove all overrides for a node
  void removeAllOverrides(String nodeId) {
    for (final mode in GameMode.values) {
      _overrides.remove('$nodeId::${mode.name}');
    }
    notifyListeners();
  }

  /// Copy overrides from one mode to another
  void copyOverrides(String nodeId, GameMode from, GameMode to) {
    final source = getOverride(nodeId, from);
    if (source != null) {
      setOverride(ContextOverrideSet(
        behaviorNodeId: nodeId,
        gameMode: to,
        gainDb: source.gainDb,
        priority: source.priority,
        playbackMode: source.playbackMode,
        busRoute: source.busRoute,
        active: source.active,
        emotionalWeight: source.emotionalWeight,
        stereoWidth: source.stereoWidth,
        fadeInMs: source.fadeInMs,
        fadeOutMs: source.fadeOutMs,
      ));
    }
  }

  /// Clear all overrides
  void clearAll() {
    _overrides.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'currentMode': _currentMode.name,
    'overrides': _overrides.values
        .where((o) => o.hasOverrides)
        .map((o) => o.toJson())
        .toList(),
  };

  void fromJson(Map<String, dynamic> json) {
    _currentMode = GameMode.values.byName(json['currentMode'] as String? ?? 'base');
    _overrides.clear();
    final overridesList = json['overrides'] as List<dynamic>?;
    if (overridesList != null) {
      for (final item in overridesList) {
        final override = ContextOverrideSet.fromJson(item as Map<String, dynamic>);
        final key = '${override.behaviorNodeId}::${override.gameMode.name}';
        _overrides[key] = override;
      }
    }
    notifyListeners();
  }
}

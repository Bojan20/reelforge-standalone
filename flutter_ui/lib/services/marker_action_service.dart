/// Marker Action Service — Timeline Position-triggered Actions
///
/// #27: Actions bound to timeline positions. Trigger when play cursor
/// passes a marker. `!` + action ID in marker name.
///
/// Features:
/// - Parse action markers: name starting with `!` is an action marker
/// - Track playhead crossing over markers during playback
/// - Execute actions (commands or onDspAction) when crossed
/// - Configurable trigger tolerance (default 100ms)
/// - Action marker registry with enable/disable per marker
/// - One-shot vs repeating markers
library;

import 'package:flutter/foundation.dart';
import '../widgets/daw/marker_system.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MARKER ACTION MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// How the action should be triggered
enum MarkerTriggerMode {
  /// Fire every time playhead crosses the marker
  always,

  /// Fire only once per playback session (reset on stop)
  once,
}

/// A parsed action from a marker name
class MarkerAction {
  final String markerId;
  final String actionId;
  final Map<String, dynamic>? params;
  final MarkerTriggerMode mode;
  bool enabled;

  MarkerAction({
    required this.markerId,
    required this.actionId,
    this.params,
    this.mode = MarkerTriggerMode.always,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'markerId': markerId,
    'actionId': actionId,
    if (params != null) 'params': params,
    'mode': mode.name,
    'enabled': enabled,
  };

  factory MarkerAction.fromJson(Map<String, dynamic> json) => MarkerAction(
    markerId: json['markerId'] as String? ?? '',
    actionId: json['actionId'] as String? ?? '',
    params: json['params'] as Map<String, dynamic>?,
    mode: MarkerTriggerMode.values.firstWhere(
      (m) => m.name == json['mode'],
      orElse: () => MarkerTriggerMode.always,
    ),
    enabled: json['enabled'] as bool? ?? true,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKER ACTION SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for detecting and executing marker actions during playback
class MarkerActionService extends ChangeNotifier {
  MarkerActionService._();
  static final MarkerActionService instance = MarkerActionService._();

  /// Registered marker actions (by marker ID)
  final Map<String, MarkerAction> _actions = {};

  /// Markers that have already fired in this playback session (for once mode)
  final Set<String> _firedThisSession = {};

  /// Previous playhead position for crossing detection
  double _lastPlayheadTime = 0;

  /// Whether playback is active
  bool _isPlaying = false;

  /// Trigger tolerance in seconds (markers within this window are triggered)
  double triggerToleranceMs = 100;

  /// Callback for executing commands
  void Function(String commandId)? onExecuteCommand;

  /// Callback for dispatching actions
  void Function(String action, Map<String, dynamic>? params)? onDispatchAction;

  // Getters
  List<MarkerAction> get actions => _actions.values.toList();
  int get count => _actions.length;
  int get enabledCount => _actions.values.where((a) => a.enabled).length;

  MarkerAction? getAction(String markerId) => _actions[markerId];

  /// Register an action for a marker
  void registerAction(MarkerAction action) {
    _actions[action.markerId] = action;
    notifyListeners();
  }

  /// Unregister action for a marker
  void unregisterAction(String markerId) {
    _actions.remove(markerId);
    notifyListeners();
  }

  /// Toggle action enabled state
  void toggleEnabled(String markerId) {
    final action = _actions[markerId];
    if (action == null) return;
    action.enabled = !action.enabled;
    notifyListeners();
  }

  /// Update action properties
  void updateAction(String markerId, {
    String? actionId,
    MarkerTriggerMode? mode,
    bool? enabled,
  }) {
    final action = _actions[markerId];
    if (action == null) return;
    if (actionId != null) {
      _actions[markerId] = MarkerAction(
        markerId: markerId,
        actionId: actionId,
        params: action.params,
        mode: mode ?? action.mode,
        enabled: enabled ?? action.enabled,
      );
    } else {
      if (mode != null) {
        _actions[markerId] = MarkerAction(
          markerId: markerId,
          actionId: action.actionId,
          params: action.params,
          mode: mode,
          enabled: action.enabled,
        );
      }
      if (enabled != null) action.enabled = enabled;
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-PARSE FROM MARKER NAMES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scan all markers and auto-register actions for those starting with `!`
  /// Format: `!actionId` or `!actionId param1=val1`
  void syncFromMarkers(List<DawMarker> markers) {
    final currentIds = <String>{};

    for (final marker in markers) {
      if (!marker.name.startsWith('!')) continue;

      final parsed = _parseActionName(marker.name);
      if (parsed == null) continue;

      currentIds.add(marker.id);

      // Only add if not already registered (preserve user settings)
      if (!_actions.containsKey(marker.id)) {
        _actions[marker.id] = MarkerAction(
          markerId: marker.id,
          actionId: parsed.actionId,
          params: parsed.params,
        );
      }
    }

    // Remove actions for markers that no longer have `!` prefix
    _actions.removeWhere((id, _) => !currentIds.contains(id));
    notifyListeners();
  }

  /// Parse `!actionId param1=val1 param2=val2` format
  _ParsedAction? _parseActionName(String name) {
    if (!name.startsWith('!')) return null;
    final parts = name.substring(1).trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return null;

    final actionId = parts[0];
    Map<String, dynamic>? params;

    if (parts.length > 1) {
      params = {};
      for (int i = 1; i < parts.length; i++) {
        final kv = parts[i].split('=');
        if (kv.length == 2) {
          // Try to parse as number
          final numVal = double.tryParse(kv[1]);
          params[kv[0]] = numVal ?? kv[1];
        }
      }
      if (params.isEmpty) params = null;
    }

    return _ParsedAction(actionId, params);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CROSSING DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when playback starts
  void onPlaybackStart(double startTime) {
    _isPlaying = true;
    _lastPlayheadTime = startTime;
    _firedThisSession.clear();
  }

  /// Called when playback stops
  void onPlaybackStop() {
    _isPlaying = false;
    _firedThisSession.clear();
  }

  /// Called on each playhead update — checks for marker crossings
  void onPlayheadUpdate(double currentTime, List<DawMarker> sortedMarkers) {
    if (!_isPlaying) return;

    final tolerance = triggerToleranceMs / 1000.0;

    for (final marker in sortedMarkers) {
      final action = _actions[marker.id];
      if (action == null || !action.enabled) continue;

      // Check if playhead crossed this marker since last update
      final crossed = _lastPlayheadTime < marker.time &&
          currentTime >= marker.time - tolerance;

      if (!crossed) continue;

      // Check one-shot
      if (action.mode == MarkerTriggerMode.once &&
          _firedThisSession.contains(marker.id)) {
        continue;
      }

      // Fire action
      _executeAction(action);
      _firedThisSession.add(marker.id);
    }

    _lastPlayheadTime = currentTime;
  }

  /// Execute a marker action
  void _executeAction(MarkerAction action) {
    // Try as command first, then as action
    if (action.actionId.contains('.')) {
      // Looks like a command ID (e.g., 'mix.toggle_mute')
      onExecuteCommand?.call(action.actionId);
    } else {
      // Dispatch as action
      onDispatchAction?.call(action.actionId, action.params);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'actions': _actions.values.map((a) => a.toJson()).toList(),
    'triggerToleranceMs': triggerToleranceMs,
  };

  void fromJson(Map<String, dynamic> json) {
    _actions.clear();
    _firedThisSession.clear();
    triggerToleranceMs = (json['triggerToleranceMs'] as num?)?.toDouble() ?? 100;
    final list = json['actions'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final action = MarkerAction.fromJson(item as Map<String, dynamic>);
        _actions[action.markerId] = action;
      }
    }
    notifyListeners();
  }
}

/// Internal parsed action result
class _ParsedAction {
  final String actionId;
  final Map<String, dynamic>? params;
  const _ParsedAction(this.actionId, this.params);
}

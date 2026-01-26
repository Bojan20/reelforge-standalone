/// Event System Provider
///
/// Extracted from MiddlewareProvider as part of P1.8 decomposition.
/// Manages MiddlewareEvent CRUD operations and FFI sync (Wwise/FMOD-style events).
///
/// MiddlewareEvents are action-based events that can play sounds, set parameters,
/// trigger other events, etc. They follow the Wwise/FMOD event model.
///
/// Note: postEvent/playback remains in MiddlewareProvider due to tight coupling
/// with composite events and playback controller.

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing middleware events (Wwise/FMOD-style)
class EventSystemProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Registered middleware events
  final Map<String, MiddlewareEvent> _events = {};

  /// Event name to numeric ID mapping for FFI
  final Map<String, int> _eventNameToId = {};

  /// Asset name to numeric ID mapping for FFI
  final Map<String, int> _assetNameToId = {};

  /// Bus name to numeric ID mapping
  static const Map<String, int> busNameToId = {
    'Master': 0,
    'Music': 1,
    'SFX': 2,
    'Voice': 3,
    'UI': 4,
    'Ambience': 5,
    'Reels': 2, // Maps to SFX bus
    'Wins': 2,  // Maps to SFX bus
    'VO': 3,    // Maps to Voice bus
  };

  /// Next event numeric ID
  int _nextEventNumericId = 1000;

  /// Next asset numeric ID
  int _nextAssetNumericId = 2000;

  EventSystemProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all registered events
  List<MiddlewareEvent> get events => _events.values.toList();

  /// Get event count
  int get eventCount => _events.length;

  /// Get event by ID
  MiddlewareEvent? getEvent(String id) => _events[id];

  /// Get event by name
  MiddlewareEvent? getEventByName(String name) {
    return _events.values.where((e) => e.name == name).firstOrNull;
  }

  /// Check if event exists
  bool hasEvent(String id) => _events.containsKey(id);

  /// Get numeric ID for event name (for FFI)
  int? getNumericIdForEvent(String eventName) => _eventNameToId[eventName];

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a new event
  void registerEvent(MiddlewareEvent event) {
    _events[event.id] = event;

    // Assign numeric ID for FFI
    final numericId = _nextEventNumericId++;
    _eventNameToId[event.name] = numericId;

    // Sync to Rust engine
    _syncEventToEngine(event, numericId);

    notifyListeners();
  }

  /// Update an existing event
  void updateEvent(MiddlewareEvent event) {
    if (!_events.containsKey(event.id)) return;

    _events[event.id] = event;

    // Re-sync to engine
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(event, numericId);
    }

    notifyListeners();
  }

  /// Delete an event
  void deleteEvent(String eventId) {
    final event = _events.remove(eventId);
    if (event != null) {
      _eventNameToId.remove(event.name);
      // Note: Rust side doesn't have unregister, but IDs won't be reused
    }
    notifyListeners();
  }

  /// Add action to an event
  void addActionToEvent(String eventId, MiddlewareAction action) {
    final event = _events[eventId];
    if (event == null) return;

    final updatedActions = [...event.actions, action];
    _events[eventId] = event.copyWith(actions: updatedActions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  /// Update action in an event
  void updateActionInEvent(String eventId, MiddlewareAction action) {
    final event = _events[eventId];
    if (event == null) return;

    final updatedActions = event.actions.map((a) {
      return a.id == action.id ? action : a;
    }).toList();

    _events[eventId] = event.copyWith(actions: updatedActions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  /// Remove action from an event
  void removeActionFromEvent(String eventId, String actionId) {
    final event = _events[eventId];
    if (event == null) return;

    final updatedActions = event.actions.where((a) => a.id != actionId).toList();
    _events[eventId] = event.copyWith(actions: updatedActions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  /// Reorder actions in an event
  void reorderActionsInEvent(String eventId, int oldIndex, int newIndex) {
    final event = _events[eventId];
    if (event == null) return;

    final actions = List<MiddlewareAction>.from(event.actions);
    if (oldIndex < 0 || oldIndex >= actions.length) return;
    if (newIndex < 0 || newIndex > actions.length) return;

    final action = actions.removeAt(oldIndex);
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    actions.insert(insertIndex, action);

    _events[eventId] = event.copyWith(actions: actions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FFI SYNC - Event to Rust Engine
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync event to Rust engine via FFI
  void _syncEventToEngine(MiddlewareEvent event, int numericId) {
    // Register event
    _ffi.middlewareRegisterEvent(
      numericId,
      event.name,
      event.category,
      maxInstances: 8,
    );

    // Add all actions
    for (final action in event.actions) {
      _addActionToEngine(numericId, action);
    }
  }

  /// Add action to engine (uses extended FFI with pan, gain, fade, trim)
  void _addActionToEngine(int eventId, MiddlewareAction action) {
    _ffi.middlewareAddActionEx(
      eventId,
      _mapActionType(action.type),
      assetId: _getOrCreateAssetId(action.assetId),
      busId: busNameToId[action.bus] ?? 0,
      scope: _mapActionScope(action.scope),
      priority: _mapActionPriority(action.priority),
      fadeCurve: _mapFadeCurve(action.fadeCurve),
      fadeTimeMs: (action.fadeTime * 1000).round(),
      delayMs: (action.delay * 1000).round(),
      // Extended playback parameters (2026-01-26)
      gain: action.gain,
      pan: action.pan,
      fadeInMs: action.fadeInMs.round(),
      fadeOutMs: action.fadeOutMs.round(),
      trimStartMs: action.trimStartMs.round(),
      trimEndMs: action.trimEndMs.round(),
    );
  }

  /// Map Dart ActionType to FFI MiddlewareActionType
  MiddlewareActionType _mapActionType(ActionType type) {
    return switch (type) {
      ActionType.play => MiddlewareActionType.play,
      ActionType.playAndContinue => MiddlewareActionType.playAndContinue,
      ActionType.stop => MiddlewareActionType.stop,
      ActionType.stopAll => MiddlewareActionType.stopAll,
      ActionType.pause => MiddlewareActionType.pause,
      ActionType.pauseAll => MiddlewareActionType.pauseAll,
      ActionType.resume => MiddlewareActionType.resume,
      ActionType.resumeAll => MiddlewareActionType.resumeAll,
      ActionType.break_ => MiddlewareActionType.breakLoop,
      ActionType.mute => MiddlewareActionType.mute,
      ActionType.unmute => MiddlewareActionType.unmute,
      ActionType.setVolume => MiddlewareActionType.setVolume,
      ActionType.setPitch => MiddlewareActionType.setPitch,
      ActionType.setLPF => MiddlewareActionType.setLPF,
      ActionType.setHPF => MiddlewareActionType.setHPF,
      ActionType.setBusVolume => MiddlewareActionType.setBusVolume,
      ActionType.setState => MiddlewareActionType.setState,
      ActionType.setSwitch => MiddlewareActionType.setSwitch,
      ActionType.setRTPC => MiddlewareActionType.setRTPC,
      ActionType.resetRTPC => MiddlewareActionType.resetRTPC,
      ActionType.seek => MiddlewareActionType.seek,
      ActionType.trigger => MiddlewareActionType.trigger,
      ActionType.postEvent => MiddlewareActionType.postEvent,
    };
  }

  /// Map Dart ActionScope to FFI MiddlewareActionScope
  MiddlewareActionScope _mapActionScope(ActionScope scope) {
    return switch (scope) {
      ActionScope.global => MiddlewareActionScope.global,
      ActionScope.gameObject => MiddlewareActionScope.gameObject,
      ActionScope.emitter => MiddlewareActionScope.emitter,
      ActionScope.all => MiddlewareActionScope.all,
      ActionScope.firstOnly => MiddlewareActionScope.firstOnly,
      ActionScope.random => MiddlewareActionScope.random,
    };
  }

  /// Map Dart ActionPriority to FFI MiddlewareActionPriority
  MiddlewareActionPriority _mapActionPriority(ActionPriority priority) {
    return switch (priority) {
      ActionPriority.lowest => MiddlewareActionPriority.lowest,
      ActionPriority.low => MiddlewareActionPriority.low,
      ActionPriority.belowNormal => MiddlewareActionPriority.belowNormal,
      ActionPriority.normal => MiddlewareActionPriority.normal,
      ActionPriority.aboveNormal => MiddlewareActionPriority.aboveNormal,
      ActionPriority.high => MiddlewareActionPriority.high,
      ActionPriority.highest => MiddlewareActionPriority.highest,
    };
  }

  /// Map Dart FadeCurve to FFI MiddlewareFadeCurve
  MiddlewareFadeCurve _mapFadeCurve(FadeCurve curve) {
    return switch (curve) {
      FadeCurve.linear => MiddlewareFadeCurve.linear,
      FadeCurve.log3 => MiddlewareFadeCurve.log3,
      FadeCurve.sine => MiddlewareFadeCurve.sine,
      FadeCurve.log1 => MiddlewareFadeCurve.log1,
      FadeCurve.invSCurve => MiddlewareFadeCurve.invSCurve,
      FadeCurve.sCurve => MiddlewareFadeCurve.sCurve,
      FadeCurve.exp1 => MiddlewareFadeCurve.exp1,
      FadeCurve.exp3 => MiddlewareFadeCurve.exp3,
    };
  }

  /// Get or create numeric asset ID
  int _getOrCreateAssetId(String assetName) {
    if (assetName.isEmpty || assetName == '—') return 0;

    var id = _assetNameToId[assetName];
    if (id == null) {
      id = _nextAssetNumericId++;
      _assetNameToId[assetName] = id;
    }
    return id;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT/EXPORT FOR PROFILE LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import event (for profile loading, preserves existing ID mappings)
  void importEvent(MiddlewareEvent event) {
    _events[event.id] = event;

    // Get existing or create new numeric ID
    var numericId = _eventNameToId[event.name];
    if (numericId == null) {
      numericId = _nextEventNumericId++;
      _eventNameToId[event.name] = numericId;
    }

    _syncEventToEngine(event, numericId);
    notifyListeners();
  }

  /// Export events to JSON
  List<Map<String, dynamic>> toJson() {
    return _events.values.map((e) => e.toJson()).toList();
  }

  /// Import events from JSON list
  void fromJson(List<dynamic> jsonList) {
    for (final eventJson in jsonList) {
      final event = MiddlewareEvent.fromJson(eventJson as Map<String, dynamic>);
      importEvent(event);
    }
  }

  /// Clear all events
  void clear() {
    _events.clear();
    _eventNameToId.clear();
    _assetNameToId.clear();
    _nextEventNumericId = 1000;
    _nextAssetNumericId = 2000;
    notifyListeners();
  }
}

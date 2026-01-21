/// State Groups Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition.
/// Manages global state groups (Wwise/FMOD-style).
///
/// State groups affect sound globally - e.g., "GameState" with states
/// like "Playing", "Paused", "GameOver" that change audio behavior.

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing state groups
class StateGroupsProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// State group storage
  final Map<int, StateGroup> _stateGroups = {};

  /// Next available state group ID
  int _nextStateGroupId = 100;

  StateGroupsProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all state groups
  Map<int, StateGroup> get stateGroups => Map.unmodifiable(_stateGroups);

  /// Get a specific state group
  StateGroup? getStateGroup(int groupId) => _stateGroups[groupId];

  /// Get current state for a group
  int? getCurrentState(int groupId) => _stateGroups[groupId]?.currentStateId;

  /// Get state group by name
  StateGroup? getStateGroupByName(String name) {
    return _stateGroups.values.where((g) => g.name == name).firstOrNull;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a state group from predefined constants
  void registerStateGroupFromPreset(String name, List<String> stateNames) {
    final groupId = _nextStateGroupId++;

    final states = <StateDefinition>[];
    for (int i = 0; i < stateNames.length; i++) {
      states.add(StateDefinition(id: i, name: stateNames[i]));
    }

    final group = StateGroup(
      id: groupId,
      name: name,
      states: states,
      currentStateId: 0,
      defaultStateId: 0,
    );

    _stateGroups[groupId] = group;

    // Register with Rust
    _ffi.middlewareRegisterStateGroup(groupId, name, defaultState: 0);
    for (final state in states) {
      _ffi.middlewareAddState(groupId, state.id, state.name);
    }

    notifyListeners();
  }

  /// Register a custom state group
  void registerStateGroup(StateGroup group) {
    _stateGroups[group.id] = group;

    // Update next ID if needed
    if (group.id >= _nextStateGroupId) {
      _nextStateGroupId = group.id + 1;
    }

    // Register with Rust
    _ffi.middlewareRegisterStateGroup(
      group.id,
      group.name,
      defaultState: group.defaultStateId,
    );
    for (final state in group.states) {
      _ffi.middlewareAddState(group.id, state.id, state.name);
    }

    notifyListeners();
  }

  /// Unregister a state group
  ///
  /// Note: Rust FFI currently doesn't support unregister - group remains
  /// in engine but is removed from UI tracking. IDs are never reused.
  void unregisterStateGroup(int groupId) {
    _stateGroups.remove(groupId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE CHANGES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set current state (global)
  void setState(int groupId, int stateId) {
    final group = _stateGroups[groupId];
    if (group == null) return;

    _stateGroups[groupId] = group.copyWith(currentStateId: stateId);

    // Send to Rust
    _ffi.middlewareSetState(groupId, stateId);

    notifyListeners();
  }

  /// Set state by name
  void setStateByName(int groupId, String stateName) {
    final group = _stateGroups[groupId];
    if (group == null) return;

    final state = group.states.where((s) => s.name == stateName).firstOrNull;
    if (state != null) {
      setState(groupId, state.id);
    }
  }

  /// Reset state to default
  void resetState(int groupId) {
    final group = _stateGroups[groupId];
    if (group == null) return;

    setState(groupId, group.defaultStateId);
  }

  /// Reset all state groups to defaults
  void resetAllStates() {
    for (final groupId in _stateGroups.keys.toList()) {
      resetState(groupId);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export state groups to JSON
  List<Map<String, dynamic>> toJson() {
    return _stateGroups.values.map((g) => g.toJson()).toList();
  }

  /// Import state groups from JSON
  void fromJson(List<dynamic> json) {
    _stateGroups.clear();
    _nextStateGroupId = 100;

    for (final item in json) {
      final group = StateGroup.fromJson(item as Map<String, dynamic>);
      registerStateGroup(group);
    }
  }

  /// Clear all state groups
  void clear() {
    _stateGroups.clear();
    _nextStateGroupId = 100;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _stateGroups.clear();
    super.dispose();
  }
}

/// Switch Groups Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition.
/// Manages per-object switch groups (Wwise/FMOD-style).
///
/// Switch groups are object-scoped (unlike State Groups which are global).
/// Example: "Surface" switch with values "Wood", "Metal", "Concrete" per
/// game object for footstep sounds.

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing switch groups
class SwitchGroupsProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Switch group storage
  final Map<int, SwitchGroup> _switchGroups = {};

  /// Per-object switch values: gameObjectId → (groupId → switchId)
  final Map<int, Map<int, int>> _objectSwitches = {};

  /// Next available switch group ID
  int _nextSwitchGroupId = 100;

  SwitchGroupsProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all switch groups
  Map<int, SwitchGroup> get switchGroups => Map.unmodifiable(_switchGroups);

  /// Get a specific switch group
  SwitchGroup? getSwitchGroup(int groupId) => _switchGroups[groupId];

  /// Get switch for a game object
  int? getSwitch(int gameObjectId, int groupId) {
    return _objectSwitches[gameObjectId]?[groupId];
  }

  /// Get switch group by name
  SwitchGroup? getSwitchGroupByName(String name) {
    return _switchGroups.values.where((g) => g.name == name).firstOrNull;
  }

  /// Get all switches for a game object
  Map<int, int>? getObjectSwitches(int gameObjectId) {
    return _objectSwitches[gameObjectId];
  }

  /// Get count of objects with switches
  int get objectSwitchesCount => _objectSwitches.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a switch group
  void registerSwitchGroup(SwitchGroup group) {
    _switchGroups[group.id] = group;

    // Update next ID if needed
    if (group.id >= _nextSwitchGroupId) {
      _nextSwitchGroupId = group.id + 1;
    }

    // Register with Rust
    _ffi.middlewareRegisterSwitchGroup(group.id, group.name);
    for (final sw in group.switches) {
      _ffi.middlewareAddSwitch(group.id, sw.id, sw.name);
    }

    notifyListeners();
  }

  /// Register switch group from name and switch names
  void registerSwitchGroupFromPreset(String name, List<String> switchNames) {
    final groupId = _nextSwitchGroupId++;

    final switches = <SwitchDefinition>[];
    for (int i = 0; i < switchNames.length; i++) {
      switches.add(SwitchDefinition(id: i, name: switchNames[i]));
    }

    final group = SwitchGroup(
      id: groupId,
      name: name,
      switches: switches,
      defaultSwitchId: 0,
    );

    registerSwitchGroup(group);
  }

  /// Unregister a switch group
  ///
  /// Note: Rust FFI currently doesn't support unregister - group remains
  /// in engine but is removed from UI tracking. IDs are never reused.
  void unregisterSwitchGroup(int groupId) {
    _switchGroups.remove(groupId);
    // Remove from all objects
    for (final objectSwitches in _objectSwitches.values) {
      objectSwitches.remove(groupId);
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SWITCH CHANGES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set switch for a game object
  void setSwitch(int gameObjectId, int groupId, int switchId) {
    _objectSwitches[gameObjectId] ??= {};
    _objectSwitches[gameObjectId]![groupId] = switchId;

    // Send to Rust
    _ffi.middlewareSetSwitch(gameObjectId, groupId, switchId);

    notifyListeners();
  }

  /// Set switch by name
  void setSwitchByName(int gameObjectId, int groupId, String switchName) {
    final group = _switchGroups[groupId];
    if (group == null) return;

    final sw = group.switches.where((s) => s.name == switchName).firstOrNull;
    if (sw != null) {
      setSwitch(gameObjectId, groupId, sw.id);
    }
  }

  /// Reset switch to default for a game object
  void resetSwitch(int gameObjectId, int groupId) {
    final group = _switchGroups[groupId];
    if (group == null) return;

    setSwitch(gameObjectId, groupId, group.defaultSwitchId);
  }

  /// Clear all switches for a game object
  void clearObjectSwitches(int gameObjectId) {
    _objectSwitches.remove(gameObjectId);
    notifyListeners();
  }

  /// Reset all switches for all objects
  void resetAllSwitches() {
    _objectSwitches.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export switch groups to JSON
  List<Map<String, dynamic>> toJson() {
    return _switchGroups.values.map((g) => g.toJson()).toList();
  }

  /// Export object switches to JSON
  Map<String, dynamic> objectSwitchesToJson() {
    return _objectSwitches.map(
      (k, v) => MapEntry(k.toString(), v.map((gk, sv) => MapEntry(gk.toString(), sv))),
    );
  }

  /// Import switch groups from JSON
  void fromJson(List<dynamic> json) {
    _switchGroups.clear();
    _nextSwitchGroupId = 100;

    for (final item in json) {
      final group = SwitchGroup.fromJson(item as Map<String, dynamic>);
      registerSwitchGroup(group);
    }
  }

  /// Import object switches from JSON
  void objectSwitchesFromJson(Map<String, dynamic> json) {
    _objectSwitches.clear();
    for (final entry in json.entries) {
      final gameObjectId = int.parse(entry.key);
      final switches = (entry.value as Map<String, dynamic>).map(
        (gk, sv) => MapEntry(int.parse(gk), sv as int),
      );
      _objectSwitches[gameObjectId] = switches;
    }
  }

  /// Clear all switch groups
  void clear() {
    _switchGroups.clear();
    _objectSwitches.clear();
    _nextSwitchGroupId = 100;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _switchGroups.clear();
    _objectSwitches.clear();
    super.dispose();
  }
}

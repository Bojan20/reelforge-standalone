// Lower Zone Persistence Service
//
// Saves and loads Lower Zone state for each section (DAW, Middleware, SlotLab)
// using SharedPreferences for persistent storage.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/lower_zone/lower_zone_types.dart';

/// Service for persisting Lower Zone state across sessions
class LowerZonePersistenceService {
  static const String _dawKey = 'lower_zone_daw_state';
  static const String _middlewareKey = 'lower_zone_middleware_state';
  static const String _slotLabKey = 'lower_zone_slotlab_state';

  static LowerZonePersistenceService? _instance;
  static LowerZonePersistenceService get instance {
    _instance ??= LowerZonePersistenceService._();
    return _instance!;
  }

  LowerZonePersistenceService._();

  SharedPreferences? _prefs;

  /// Initialize the service (call once at app startup)
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Ensure preferences are loaded
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // DAW STATE
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Save DAW Lower Zone state
  Future<bool> saveDawState(DawLowerZoneState state) async {
    try {
      final prefs = await _getPrefs();
      final json = jsonEncode(state.toJson());
      return await prefs.setString(_dawKey, json);
    } catch (e) {
      // Fail silently - state will just use defaults
      return false;
    }
  }

  /// Load DAW Lower Zone state
  Future<DawLowerZoneState> loadDawState() async {
    try {
      final prefs = await _getPrefs();
      final json = prefs.getString(_dawKey);
      if (json == null) return DawLowerZoneState();
      final map = jsonDecode(json) as Map<String, dynamic>;
      return DawLowerZoneState.fromJson(map);
    } catch (e) {
      // Return default state on any error
      return DawLowerZoneState();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // MIDDLEWARE STATE
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Save Middleware Lower Zone state
  Future<bool> saveMiddlewareState(MiddlewareLowerZoneState state) async {
    try {
      final prefs = await _getPrefs();
      final json = jsonEncode(state.toJson());
      return await prefs.setString(_middlewareKey, json);
    } catch (e) {
      return false;
    }
  }

  /// Load Middleware Lower Zone state
  Future<MiddlewareLowerZoneState> loadMiddlewareState() async {
    try {
      final prefs = await _getPrefs();
      final json = prefs.getString(_middlewareKey);
      if (json == null) return MiddlewareLowerZoneState();
      final map = jsonDecode(json) as Map<String, dynamic>;
      return MiddlewareLowerZoneState.fromJson(map);
    } catch (e) {
      return MiddlewareLowerZoneState();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // SLOTLAB STATE
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Save SlotLab Lower Zone state
  Future<bool> saveSlotLabState(SlotLabLowerZoneState state) async {
    try {
      final prefs = await _getPrefs();
      final json = jsonEncode(state.toJson());
      return await prefs.setString(_slotLabKey, json);
    } catch (e) {
      return false;
    }
  }

  /// Load SlotLab Lower Zone state
  Future<SlotLabLowerZoneState> loadSlotLabState() async {
    try {
      final prefs = await _getPrefs();
      final json = prefs.getString(_slotLabKey);
      if (json == null) return SlotLabLowerZoneState();
      final map = jsonDecode(json) as Map<String, dynamic>;
      return SlotLabLowerZoneState.fromJson(map);
    } catch (e) {
      return SlotLabLowerZoneState();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Load all Lower Zone states at once
  Future<({
    DawLowerZoneState daw,
    MiddlewareLowerZoneState middleware,
    SlotLabLowerZoneState slotLab,
  })> loadAllStates() async {
    final results = await Future.wait([
      loadDawState(),
      loadMiddlewareState(),
      loadSlotLabState(),
    ]);
    return (
      daw: results[0] as DawLowerZoneState,
      middleware: results[1] as MiddlewareLowerZoneState,
      slotLab: results[2] as SlotLabLowerZoneState,
    );
  }

  /// Save all Lower Zone states at once
  Future<void> saveAllStates({
    DawLowerZoneState? daw,
    MiddlewareLowerZoneState? middleware,
    SlotLabLowerZoneState? slotLab,
  }) async {
    await Future.wait([
      if (daw != null) saveDawState(daw),
      if (middleware != null) saveMiddlewareState(middleware),
      if (slotLab != null) saveSlotLabState(slotLab),
    ]);
  }

  /// Clear all saved states (reset to defaults)
  Future<void> clearAllStates() async {
    final prefs = await _getPrefs();
    await Future.wait([
      prefs.remove(_dawKey),
      prefs.remove(_middlewareKey),
      prefs.remove(_slotLabKey),
    ]);
  }
}

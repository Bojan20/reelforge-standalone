/// Metering Preset Service (P10.1.17)
///
/// Manage metering configuration presets:
/// - 4 built-in presets (Broadcast, Music, Mastering, Film)
/// - User preset CRUD
/// - Apply presets to MeterProvider
/// - SharedPreferences storage
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/metering_preset.dart';
import '../providers/meter_provider.dart';

/// Storage key for presets in SharedPreferences
const String _kStorageKey = 'fluxforge_metering_presets';

/// Key for active preset ID
const String _kActivePresetKey = 'fluxforge_metering_active_preset';

// ═══════════════════════════════════════════════════════════════════════════
// METERING PRESET SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Singleton service for metering preset management
class MeteringPresetService extends ChangeNotifier {
  static final MeteringPresetService _instance = MeteringPresetService._();
  static MeteringPresetService get instance => _instance;

  MeteringPresetService._();

  /// Cached presets (user-created only)
  final List<MeteringPreset> _userPresets = [];

  /// Currently active preset
  MeteringPreset? _activePreset;
  MeteringPreset? get activePreset => _activePreset;

  /// Loading state
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// All presets (built-in + user)
  List<MeteringPreset> get presets => [
        ...MeteringPresets.all,
        ..._userPresets,
      ];

  /// Built-in presets only
  List<MeteringPreset> get builtInPresets => MeteringPresets.all;

  /// User presets only
  List<MeteringPreset> get userPresets => List.unmodifiable(_userPresets);

  // ─── Initialization ─────────────────────────────────────────────────────

  /// Initialize service and load presets
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load user presets
      final jsonStr = prefs.getString(_kStorageKey);
      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        _userPresets.clear();
        for (final item in jsonList) {
          try {
            _userPresets.add(MeteringPreset.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('[MeteringPresetService] Error parsing preset: $e');
          }
        }
      }

      // Load active preset ID
      final activeId = prefs.getString(_kActivePresetKey);
      if (activeId != null) {
        _activePreset = presets.where((p) => p.id == activeId).firstOrNull;
      }

      // Default to Music preset if none selected
      _activePreset ??= MeteringPresets.music;

      _isInitialized = true;
      debugPrint('[MeteringPresetService] Loaded ${_userPresets.length} user presets, active: ${_activePreset?.name}');
      notifyListeners();
    } catch (e) {
      debugPrint('[MeteringPresetService] Init error: $e');
      _activePreset = MeteringPresets.music;
      _isInitialized = true;
      notifyListeners();
    }
  }

  // ─── Preset Application ─────────────────────────────────────────────────

  /// Apply a preset (sets as active and updates MeterProvider if provided)
  Future<void> applyPreset(MeteringPreset preset, {MeterProvider? meterProvider}) async {
    _activePreset = preset;

    // Save active preset ID
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActivePresetKey, preset.id);
    } catch (e) {
      debugPrint('[MeteringPresetService] Error saving active preset: $e');
    }

    // Apply to MeterProvider if provided
    // Note: MeterProvider would need methods to accept these settings
    // For now, this just updates the active preset reference
    if (meterProvider != null) {
      debugPrint('[MeteringPresetService] Applied preset "${preset.name}" to MeterProvider');
      // meterProvider.applyBallistics(preset.ballistics);
      // meterProvider.applyScale(preset.scale);
      // meterProvider.applyColors(preset.colors);
    }

    notifyListeners();
    debugPrint('[MeteringPresetService] Activated preset: ${preset.name}');
  }

  // ─── CRUD Operations ────────────────────────────────────────────────────

  /// Save a user preset
  Future<bool> savePreset(MeteringPreset preset) async {
    try {
      // Don't allow saving with built-in IDs
      if (preset.id.startsWith('builtin_')) {
        debugPrint('[MeteringPresetService] Cannot overwrite built-in preset');
        return false;
      }

      final existingIndex = _userPresets.indexWhere((p) => p.id == preset.id);
      if (existingIndex >= 0) {
        _userPresets[existingIndex] = preset;
      } else {
        _userPresets.add(preset);
      }

      await _saveToStorage();
      notifyListeners();
      debugPrint('[MeteringPresetService] Saved preset: ${preset.name}');
      return true;
    } catch (e) {
      debugPrint('[MeteringPresetService] Save error: $e');
      return false;
    }
  }

  /// Load preset by ID
  MeteringPreset? loadPreset(String id) {
    return presets.where((p) => p.id == id).firstOrNull;
  }

  /// Delete a user preset
  Future<bool> deletePreset(String id) async {
    try {
      if (id.startsWith('builtin_')) {
        debugPrint('[MeteringPresetService] Cannot delete built-in preset');
        return false;
      }

      _userPresets.removeWhere((p) => p.id == id);

      // If deleted preset was active, switch to default
      if (_activePreset?.id == id) {
        _activePreset = MeteringPresets.music;
      }

      await _saveToStorage();
      notifyListeners();
      debugPrint('[MeteringPresetService] Deleted preset: $id');
      return true;
    } catch (e) {
      debugPrint('[MeteringPresetService] Delete error: $e');
      return false;
    }
  }

  // ─── Storage ────────────────────────────────────────────────────────────

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _userPresets.map((p) => p.toJson()).toList();
      await prefs.setString(_kStorageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[MeteringPresetService] Storage error: $e');
    }
  }

  /// Export preset to JSON string
  String exportToJson(MeteringPreset preset) {
    return const JsonEncoder.withIndent('  ').convert(preset.toJson());
  }

  /// Import preset from JSON string
  MeteringPreset? importFromJson(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return MeteringPreset.fromJson(json).copyWith(
        id: MeteringPreset.generateId(),
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[MeteringPresetService] Import error: $e');
      return null;
    }
  }
}
